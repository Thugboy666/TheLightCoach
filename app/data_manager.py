import json
from pathlib import Path
from typing import Any, Dict, List, Optional


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def read_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _collect_core_texts(base_dirs: List[Path]) -> str:
    chunks: List[str] = []
    for base_dir in base_dirs:
        if not base_dir.exists():
            continue
        for entry in sorted(base_dir.iterdir()):
            if entry.is_dir():
                continue
            text = read_text(entry).strip()
            if text:
                chunks.append(f"{entry.name}:\n{text}")
    return "\n\n".join(chunks)


def get_distillati_bundle(mode: str) -> Optional[Dict[str, Any]]:
    base_dir = Path("app/data") / mode / "distillati"
    if not base_dir.exists():
        return None
    module_spec = read_json(base_dir / "module_spec.json")
    playbook_text = read_text(base_dir / "playbook.md")
    if not playbook_text:
        playbook_text = read_text(base_dir / "quickstart.md")
    profiles = {
        "toxic": read_json(Path("app/data/emotional_core/profiles/toxic_profiles.json")),
        "healthy": read_json(Path("app/data/emotional_core/profiles/healthy_profiles.json")),
    }
    core_texts = _collect_core_texts(
        [
            Path("app/data/core"),
            Path("app/data/playbooks"),
            Path("app/data/templates"),
        ]
    )
    return {
        "module_spec": module_spec,
        "playbook_text": playbook_text,
        "profiles": profiles,
        "core_texts": core_texts,
    }


class DataManager:
    def __init__(self, base_path: Path, mode: str) -> None:
        self.base_path = base_path
        self.mode = mode
        self.mode_path = self.base_path / mode
        self.rules = self._load_json(self.mode_path / "rules.json")
        self.prompt_templates = self._load_templates(self.mode_path / "prompt_templates")

    def _load_json(self, path: Path) -> Dict[str, Any]:
        return read_json(path)

    def _load_templates(self, path: Path) -> Dict[str, str]:
        templates: Dict[str, str] = {}
        if not path.exists():
            return templates
        for template_file in path.glob("*.txt"):
            templates[template_file.stem] = read_text(template_file)
        return templates

    def style_rules(self) -> Dict[str, Any]:
        return self.rules.get("style", {})

    def safe_lines(self) -> List[str]:
        return self.rules.get("safe_lines", [])

    def prompt_builder(self, transcript: str) -> str:
        template = self.prompt_templates.get("default")
        if not template:
            template = "User said: {transcript}\nRespond in <=8 words."
        prompt = template.format(transcript=transcript)
        distillati = get_distillati_bundle(self.mode)
        if not distillati:
            return prompt
        distillati_section = self._format_distillati(distillati)
        return f"{distillati_section}\n\n{prompt}"

    def _format_distillati(self, bundle: Dict[str, Any]) -> str:
        lines: List[str] = [f"DISTILLATI (mode: {self.mode})"]
        module_spec = bundle.get("module_spec") or {}
        if module_spec:
            lines.append("MODULE SPEC:")
            lines.append(json.dumps(module_spec, indent=2, ensure_ascii=False))
        playbook_text = (bundle.get("playbook_text") or "").strip()
        if playbook_text:
            lines.append("PLAYBOOK:")
            lines.append(playbook_text)
        profiles = bundle.get("profiles") or {}
        toxic_profiles = profiles.get("toxic") or {}
        healthy_profiles = profiles.get("healthy") or {}
        if toxic_profiles or healthy_profiles:
            lines.append("EMOTIONAL CORE PROFILES:")
            if toxic_profiles:
                lines.append("TOXIC:")
                lines.append(json.dumps(toxic_profiles, indent=2, ensure_ascii=False))
            if healthy_profiles:
                lines.append("HEALTHY:")
                lines.append(json.dumps(healthy_profiles, indent=2, ensure_ascii=False))
        core_texts = (bundle.get("core_texts") or "").strip()
        if core_texts:
            lines.append("CORE TEXTS:")
            lines.append(core_texts)
        return "\n".join(lines)

    def response_limits(self) -> Dict[str, Any]:
        return self.rules.get("limits", {"max_words": 8})

    def lookup_response(self, transcript: str) -> str:
        patterns_path = self.mode_path / "patterns"
        responses_path = self.mode_path / "responses"
        for pattern_file in patterns_path.glob("*.txt"):
            pattern = pattern_file.read_text(encoding="utf-8").strip().lower()
            if pattern and pattern in transcript.lower():
                response_file = responses_path / f"{pattern_file.stem}.txt"
                if response_file.exists():
                    return response_file.read_text(encoding="utf-8").strip()
        return ""


if __name__ == "__main__":
    data_root = Path("app/data")
    if data_root.exists():
        for mode_dir in sorted(p for p in data_root.iterdir() if p.is_dir()):
            bundle = get_distillati_bundle(mode_dir.name)
            status = "found" if bundle else "missing"
            print(f"{mode_dir.name}: distillati {status}")
