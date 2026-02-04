import json
from pathlib import Path
from typing import Any, Dict, List


class DataManager:
    def __init__(self, base_path: Path, mode: str) -> None:
        self.base_path = base_path
        self.mode = mode
        self.mode_path = self.base_path / mode
        self.rules = self._load_json(self.mode_path / "rules.json")
        self.prompt_templates = self._load_templates(self.mode_path / "prompt_templates")

    def _load_json(self, path: Path) -> Dict[str, Any]:
        if not path.exists():
            return {}
        return json.loads(path.read_text(encoding="utf-8"))

    def _load_templates(self, path: Path) -> Dict[str, str]:
        templates: Dict[str, str] = {}
        if not path.exists():
            return templates
        for template_file in path.glob("*.txt"):
            templates[template_file.stem] = template_file.read_text(encoding="utf-8")
        return templates

    def style_rules(self) -> Dict[str, Any]:
        return self.rules.get("style", {})

    def safe_lines(self) -> List[str]:
        return self.rules.get("safe_lines", [])

    def prompt_builder(self, transcript: str) -> str:
        template = self.prompt_templates.get("default")
        if not template:
            template = "User said: {transcript}\nRespond in <=8 words."
        return template.format(transcript=transcript)

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
