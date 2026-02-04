import asyncio
import json
import logging
import os
import secrets
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import requests
from fastapi import FastAPI, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

try:
    from vosk import Model, KaldiRecognizer
except Exception:  # noqa: BLE001
    Model = None
    KaldiRecognizer = None

from app.mode_manager import ModeManager

APP_ROOT = Path(__file__).resolve().parent
DATA_ROOT = APP_ROOT / "data"
RUNTIME_ROOT = Path("runtime")
LOG_DIR = RUNTIME_ROOT / "logs"
TMP_DIR = RUNTIME_ROOT / "tmp"
VOSK_MODEL_PATH = RUNTIME_ROOT / "asr" / "vosk" / "model"
PIPER_BIN = RUNTIME_ROOT / "tts" / "piper" / "piper.exe"
PIPER_VOICES_DIR = RUNTIME_ROOT / "tts" / "voices"
LLAMA_SERVER = os.getenv("LLAMA_SERVER", "http://127.0.0.1:8080")

LOG_DIR.mkdir(parents=True, exist_ok=True)
TMP_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    filename=LOG_DIR / "server.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

app = FastAPI()
app.mount("/static", StaticFiles(directory=APP_ROOT / "client"), name="static")
mode_manager = ModeManager(DATA_ROOT)


@dataclass
class ConnectionState:
    session_id: str
    mode: Optional[str] = None
    transcript: str = ""
    last_candidate: str = ""
    last_candidate_at: float = 0.0
    last_transcript_at: float = 0.0
    asr: Optional[Any] = None
    partial: str = ""


class SessionStore:
    def __init__(self) -> None:
        self._sessions: Dict[str, Dict[str, Any]] = {}

    def get(self, session_id: str) -> Dict[str, Any]:
        return self._sessions.setdefault(session_id, {})

    def set_mode(self, session_id: str, mode: str) -> None:
        self.get(session_id)["mode"] = mode

    def get_mode(self, session_id: str) -> Optional[str]:
        return self.get(session_id).get("mode")


sessions = SessionStore()


class StreamingASR:
    def __init__(self) -> None:
        self.available = Model is not None and KaldiRecognizer is not None and VOSK_MODEL_PATH.exists()
        self.model = Model(str(VOSK_MODEL_PATH)) if self.available else None

    def create_recognizer(self) -> Optional[Any]:
        if not self.available:
            return None
        recognizer = KaldiRecognizer(self.model, 16000)
        recognizer.SetWords(True)
        return recognizer

    def accept(self, recognizer: Any, data: bytes) -> Dict[str, Any]:
        if recognizer.AcceptWaveform(data):
            return json.loads(recognizer.Result())
        return json.loads(recognizer.PartialResult())


asr_engine = StreamingASR()


async def llm_generate(prompt: str) -> str:
    payload = {
        "model": "local-model",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "max_tokens": 32,
    }
    try:
        response = requests.post(f"{LLAMA_SERVER}/v1/chat/completions", json=payload, timeout=3)
        response.raise_for_status()
        content = response.json()["choices"][0]["message"]["content"]
        return content.strip()
    except Exception as exc:  # noqa: BLE001
        logging.warning("LLM call failed: %s", exc)
        return ""


def enforce_word_limit(text: str, max_words: int) -> str:
    words = text.split()
    return " ".join(words[:max_words])


def choose_safe_line(mode: str) -> str:
    data = mode_manager.get_mode(mode)
    safe_lines = data.safe_lines()
    if safe_lines:
        return safe_lines[0]
    return "Capisco."


def detect_uncertain(transcript: str) -> bool:
    cleaned = transcript.strip().lower()
    if not cleaned:
        return True
    if len(cleaned) < 3:
        return True
    return False


async def build_candidate(mode: str, transcript: str) -> str:
    data = mode_manager.get_mode(mode)
    response = data.lookup_response(transcript)
    if response:
        return response
    prompt = data.prompt_builder(transcript)
    llm_text = await llm_generate(prompt)
    max_words = data.response_limits().get("max_words", 8)
    if not llm_text:
        return choose_safe_line(mode)
    return enforce_word_limit(llm_text, max_words)


def tts_synthesize(text: str) -> Optional[bytes]:
    voices = list(PIPER_VOICES_DIR.glob("*.onnx"))
    if not PIPER_BIN.exists() or not voices:
        logging.warning("Piper binary or voice missing")
        return None
    voice = voices[0]
    wav_path = TMP_DIR / f"tts_{secrets.token_hex(4)}.wav"
    try:
        subprocess.run(
            [str(PIPER_BIN), "-m", str(voice), "-f", str(wav_path)],
            input=text.encode("utf-8"),
            check=True,
        )
        return wav_path.read_bytes()
    except Exception as exc:  # noqa: BLE001
        logging.warning("TTS failed: %s", exc)
        return None
    finally:
        if wav_path.exists():
            wav_path.unlink(missing_ok=True)


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(APP_ROOT / "client" / "index.html")


@app.get("/session")
async def session(request: Request, response: Response) -> Dict[str, str]:
    session_id = request.cookies.get("session_id") or secrets.token_hex(8)
    response.set_cookie("session_id", session_id, httponly=False, samesite="lax")
    return {"session_id": session_id}


@app.get("/health")
async def health() -> Dict[str, Any]:
    return {
        "status": "ok",
        "llama": LLAMA_SERVER,
        "vosk": asr_engine.available,
        "piper": PIPER_BIN.exists(),
    }


@app.get("/metrics")
async def metrics() -> Dict[str, Any]:
    return {"note": "TODO: add latency metrics"}


@app.websocket("/ws/audio")
async def ws_audio(websocket: WebSocket) -> None:
    await websocket.accept()
    session_id = websocket.cookies.get("session_id") or secrets.token_hex(8)
    state = ConnectionState(session_id=session_id)
    state.mode = sessions.get_mode(session_id)
    state.asr = asr_engine.create_recognizer()
    if not state.asr:
        await websocket.send_json({"type": "error", "message": "ASR not available"})

    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                break
            if message.get("text"):
                payload = json.loads(message["text"])
                if payload.get("type") == "set_mode":
                    state.mode = payload.get("mode")
                    if state.mode:
                        sessions.set_mode(session_id, state.mode)
                    await websocket.send_json({"type": "mode_set", "mode": state.mode})
                if payload.get("type") == "ptt":
                    if not state.mode:
                        await websocket.send_json({"type": "error", "message": "Mode not set"})
                        continue
                    transcript = state.transcript
                    data = mode_manager.get_mode(state.mode)
                    if detect_uncertain(transcript):
                        response_text = choose_safe_line(state.mode)
                    else:
                        response_text = state.last_candidate or await build_candidate(state.mode, transcript)
                    response_text = enforce_word_limit(
                        response_text,
                        data.response_limits().get("max_words", 8),
                    )
                    await websocket.send_json({"type": "response", "text": response_text})
                    tts_audio = tts_synthesize(response_text)
                    if tts_audio:
                        await websocket.send_bytes(tts_audio)
                continue

            if message.get("bytes"):
                if not state.asr:
                    continue
                result = asr_engine.accept(state.asr, message["bytes"])
                if "partial" in result:
                    state.partial = result["partial"]
                    await websocket.send_json({"type": "partial", "text": state.partial})
                if "text" in result and result["text"]:
                    state.transcript = result["text"]
                    state.last_transcript_at = time.time()
                    await websocket.send_json({"type": "final", "text": state.transcript})
                    if state.mode and time.time() - state.last_candidate_at > 2:
                        state.last_candidate_at = time.time()
                        asyncio.create_task(update_candidate(state))

    except WebSocketDisconnect:
        return


async def update_candidate(state: ConnectionState) -> None:
    if not state.mode:
        return
    transcript = state.transcript
    if not transcript:
        return
    candidate = await build_candidate(state.mode, transcript)
    state.last_candidate = candidate
