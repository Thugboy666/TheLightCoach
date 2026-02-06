import io
import json
import re
import time
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests

from app.data_manager import get_distillati_bundle


@dataclass
class AsrResult:
    transcript: str
    engine: str
    error: Optional[str]
    duration_s: float


class LazyVoskASR:
    def __init__(self, model_path: Path) -> None:
        self.model_path = model_path
        self._model = None
        self._available: Optional[bool] = None

    def _has_model_files(self) -> bool:
        required_files = [
            self.model_path / "am" / "final.mdl",
            self.model_path / "conf" / "model.conf",
            self.model_path / "graph" / "words.txt",
        ]
        return self.model_path.exists() and all(path.exists() for path in required_files)

    def available(self) -> bool:
        if self._available is None:
            self._available = self._has_model_files()
        return bool(self._available)

    def _load_model(self) -> Optional[Any]:
        if self._model is not None:
            return self._model
        if not self.available():
            return None
        try:
            from vosk import Model  # type: ignore
        except Exception:
            self._available = False
            return None
        try:
            self._model = Model(str(self.model_path))
            return self._model
        except Exception:
            self._available = False
            return None

    def transcribe(self, wav_bytes: bytes) -> AsrResult:
        start = time.monotonic()
        if not self.available():
            return AsrResult("", "none", "Vosk model not available", 0.0)
        model = self._load_model()
        if model is None:
            return AsrResult("", "none", "Vosk model failed to load", 0.0)
        try:
            from vosk import KaldiRecognizer  # type: ignore
        except Exception:
            return AsrResult("", "none", "Vosk recognizer unavailable", 0.0)
        try:
            with wave.open(io.BytesIO(wav_bytes), "rb") as wav_file:
                if wav_file.getframerate() != 16000:
                    return AsrResult(
                        "",
                        "none",
                        "Audio must be 16kHz WAV",
                        time.monotonic() - start,
                    )
                recognizer = KaldiRecognizer(model, 16000)
                while True:
                    data = wav_file.readframes(4000)
                    if not data:
                        break
                    recognizer.AcceptWaveform(data)
                result = json.loads(recognizer.FinalResult())
                return AsrResult(
                    result.get("text", ""),
                    "vosk",
                    None,
                    time.monotonic() - start,
                )
        except Exception as exc:
            return AsrResult("", "none", f"ASR failed: {exc}", time.monotonic() - start)


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def clamp(value: float, minimum: int = 0, maximum: int = 100) -> int:
    return int(max(minimum, min(maximum, round(value))))


def compute_indicators(transcript: str) -> Tuple[int, int, int, List[str]]:
    text = transcript.lower()
    patterns = {
        "urgency": (r"\b(urgente|subito|adesso|immediatamente|ora)\b", 10),
        "reassurance": (r"\b(rassicura|rassicurazione|dimmi che|sei sicuro)\b", 8),
        "triangulation": (r"\b(terz[oa]|triangol|ha detto a|mi ha detto che)\b", 12),
        "threat": (r"\b(minaccia|ti rovino|denuncio|se non)\b", 18),
        "guilt": (r"\b(colpa|mi fai|dopo tutto|ti ho dato)\b", 10),
        "night_impulse": (r"\b(stanotte|notte|di notte|tardi)\b", 12),
        "impulse": (r"\b(impulso|non resisto|non riesco a trattener)\b", 10),
    }
    hits: List[str] = []
    risk_points = 0
    for label, (pattern, weight) in patterns.items():
        if re.search(pattern, text):
            hits.append(label)
            risk_points += weight
    words = len(text.split())
    clarity = clamp(35 + min(words, 60) * 1.1)
    centeredness = clamp(85 - risk_points * 0.7)
    risk = clamp(5 + risk_points)
    return clarity, centeredness, risk, hits


def detect_active_silence(transcript: str, hits: List[str]) -> Optional[str]:
    text = transcript.lower()
    direct = re.search(r"cosa rispondo|cosa rispondere|a caldo|rispondere ora", text)
    night = "night_impulse" in hits or re.search(r"scrivere di notte|stanotte", text)
    if direct or night:
        return "Non rispondere ora. Respira e rimanda tra 20 minuti."
    return None


def sanitize_phrase(text: str, max_words: int) -> str:
    cleaned = re.sub(r"\s+", " ", text.replace("\n", " ")).strip()
    words = cleaned.split()
    return " ".join(words[:max_words])


def parse_llm_json(text: str) -> Dict[str, Any]:
    if not text:
        return {}
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return {}
    try:
        return json.loads(match.group(0))
    except json.JSONDecodeError:
        return {}


class CoachEngine:
    def __init__(
        self,
        data_root: Path,
        llama_server: str,
        vosk_model_path: Path,
        piper_bin: Path,
        piper_voices_dir: Path,
    ) -> None:
        self.data_root = data_root
        self.llama_server = llama_server
        self.asr = LazyVoskASR(vosk_model_path)
        self.piper_bin = piper_bin
        self.piper_voices_dir = piper_voices_dir

    def health(self) -> Dict[str, Any]:
        llama_ok = False
        try:
            response = requests.get(f"{self.llama_server}/v1/models", timeout=2)
            llama_ok = response.status_code == 200
        except Exception:
            llama_ok = False
        piper_ok = self.piper_bin.exists() and any(self.piper_voices_dir.glob("*.onnx"))
        return {
            "llama": {"reachable": llama_ok, "url": self.llama_server},
            "vosk": {"model_present": self.asr.available()},
            "piper": {"available": piper_ok},
        }

    async def analyze(
        self,
        mode: str,
        transcript: Optional[str],
        audio_bytes: Optional[bytes],
        show_alternatives: bool,
        live_beta: bool,
    ) -> Dict[str, Any]:
        total_start = time.monotonic()
        asr_result = AsrResult("", "none", None, 0.0)
        final_transcript = transcript or ""
        if not final_transcript and audio_bytes:
            asr_result = self.asr.transcribe(audio_bytes)
            final_transcript = asr_result.transcript
        elif final_transcript:
            asr_result = AsrResult(final_transcript, "manual", None, 0.0)

        clarity, centeredness, risk, hits = compute_indicators(final_transcript)
        active_silence_phrase = detect_active_silence(final_transcript, hits)

        prompt = self._build_prompt(mode, final_transcript, show_alternatives, live_beta)
        llm_start = time.monotonic()
        llm_text = await self._llm_generate(prompt)
        llm_duration = time.monotonic() - llm_start
        llm_payload = parse_llm_json(llm_text)

        fallback_phrase = "Respira. Riassumi l'evento in una frase chiara."
        phrase = sanitize_phrase(llm_payload.get("phrase", fallback_phrase), 18)
        if not phrase:
            phrase = sanitize_phrase(fallback_phrase, 18)

        alternatives: Optional[List[str]] = None
        if show_alternatives:
            raw_alts = llm_payload.get("alternatives") or []
            alternatives = [sanitize_phrase(str(item), 12) for item in raw_alts][:2]
            alternatives = [alt for alt in alternatives if alt]
            if len(alternatives) < 2:
                alternatives = (alternatives or []) + [
                    "Aspetta 20 minuti e rileggi.",
                    "Scrivi una bozza e non inviare.",
                ]
                alternatives = alternatives[:2]

        total_duration = time.monotonic() - total_start
        response = {
            "phrase": phrase,
            "score": clamp((clarity + centeredness + (100 - risk)) / 3),
            "indicators": {
                "clarity": clarity,
                "centeredness": centeredness,
                "risk": risk,
            },
            "active_silence": {
                "enabled": bool(active_silence_phrase),
                "phrase": active_silence_phrase,
            },
            "alternatives": alternatives if show_alternatives else None,
            "meta": {
                "mode": mode,
                "durations": {
                    "asr": round(asr_result.duration_s, 3),
                    "llm": round(llm_duration, 3),
                    "total": round(total_duration, 3),
                },
                "asr_engine": asr_result.engine,
                "llm_model": "local-model",
                "transcript": final_transcript,
                "asr_error": asr_result.error,
            },
        }
        return self._post_process(response)

    def _build_prompt(
        self,
        mode: str,
        transcript: str,
        show_alternatives: bool,
        live_beta: bool,
    ) -> str:
        core_guardrails = read_text(self.data_root / "core" / "guardrails.md")
        privacy = read_text(self.data_root / "core" / "ethics_and_privacy.md")
        schema = read_text(self.data_root / "templates" / "prompt_schema.md")
        module_rules = read_text(self.data_root / mode / "mirror_rules.md")
        if not module_rules:
            module_rules = read_text(self.data_root / mode / "debrief_rules.md")
        distillati = get_distillati_bundle(mode)
        distillati_text = ""
        if distillati:
            distillati_text = "DISTILLATI:\n" + json.dumps(distillati, indent=2, ensure_ascii=False)

        return "\n\n".join(
            [
                "SYSTEM: Mirror Coach post-evento. Risposte brevi, 1 riga per la Frase Unica.",
                core_guardrails,
                privacy,
                schema,
                module_rules,
                distillati_text,
                f"FLAGS: show_alternatives={show_alternatives}, live_beta={live_beta}",
                f"TRANSCRIPT: {transcript}",
                "Return only JSON. Use keys: phrase, alternatives (optional).",
            ]
        ).strip()

    async def _llm_generate(self, prompt: str) -> str:
        payload = {
            "model": "local-model",
            "messages": [
                {"role": "system", "content": "You are a concise Italian coach."},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
            "max_tokens": 120,
        }
        try:
            response = requests.post(
                f"{self.llama_server}/v1/chat/completions",
                json=payload,
                timeout=4,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            return content.strip()
        except Exception:
            return ""

    def _post_process(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        phrase = sanitize_phrase(payload.get("phrase", ""), 18)
        payload["phrase"] = phrase
        if payload.get("alternatives") is not None:
            payload["alternatives"] = [
                sanitize_phrase(item, 12) for item in payload.get("alternatives", [])
            ][:2]
        silence = payload.get("active_silence") or {}
        if silence.get("phrase"):
            silence["phrase"] = sanitize_phrase(silence.get("phrase", ""), 14)
        payload["active_silence"] = silence
        return payload
