import logging
import os
import secrets
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import FastAPI, File, Form, Request, Response, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.coach_engine import CoachEngine

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
engine = CoachEngine(DATA_ROOT, LLAMA_SERVER, VOSK_MODEL_PATH, PIPER_BIN, PIPER_VOICES_DIR)


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(APP_ROOT / "client" / "index.html")


@app.get("/session")
async def session(request: Request, response: Response) -> Dict[str, str]:
    session_id = request.cookies.get("session_id") or secrets.token_hex(8)
    response.set_cookie("session_id", session_id, httponly=False, samesite="lax")
    return {"session_id": session_id}


@app.get("/api/coach/health")
async def coach_health() -> Dict[str, Any]:
    return {"status": "ok", "components": engine.health()}


@app.get("/health")
async def health() -> Dict[str, Any]:
    return await coach_health()


@app.post("/api/coach/analyze_audio")
async def analyze_audio(
    mode: str = Form("emotional_core"),
    transcript: Optional[str] = Form(None),
    show_alternatives: bool = Form(False),
    live_beta: bool = Form(False),
    file: Optional[UploadFile] = File(None),
) -> Dict[str, Any]:
    audio_bytes = await file.read() if file else None
    return await engine.analyze(
        mode=mode,
        transcript=transcript,
        audio_bytes=audio_bytes,
        show_alternatives=show_alternatives,
        live_beta=live_beta,
    )


@app.get("/metrics")
async def metrics() -> Dict[str, Any]:
    return {"note": "TODO: add latency metrics"}
