# TheLightCoach MVP

Locale voice assistant con PTT e selezione modalità.

## Quickstart (Windows 11)
1. Copia runtime (python310, llama.cpp, piper, vosk) nelle rispettive cartelle.
2. Esegui bootstrap:
   ```powershell
   ./runtime/scripts/bootstrap.ps1
   ```
3. Avvia:
   ```powershell
   ./runtime/scripts/run_local.ps1
   ```
4. Da telefono sulla LAN apri `http://PC:8000`.

## Avvio locale + tunnel Cloudflare
- Avvio completo (healthcheck + FastAPI + tunnel):
  ```powershell
  ./runtime/scripts/run_local.ps1
  ```
- Tunnel Cloudflare usa un named tunnel definito in `runtime/cloudflared/config.yml` con hostname `coach.vitazenith-wellness.it`.
- Credenziali tunnel: `runtime/cloudflared/home/.cloudflared/<TUNNEL_ID>.json`.
- Fallback token JSON: `runtime/cloudflared/home/.cloudflared/codicetunnel.json`.

## Modalità
Alla prima apertura viene richiesta la selezione modalità. La scelta è salvata lato client (localStorage) e lato server (cookie di sessione).

## Troubleshooting
- Nessun audio: verifica permessi microfono sul browser.
- LLM non risponde: controlla `runtime/llm/llamacpp/llama-server.exe` e modello in `runtime/llm/models/`.
- TTS muto: verifica Piper e una voce `.onnx` in `runtime/tts/voices/`.
- ASR muto: verifica modello Vosk in `runtime/asr/vosk/model`.

## File tree
- `app/server.py`: FastAPI + WebSocket ASR/TTS
- `app/data/`: dataset per modalità
- `app/client/`: PWA
- `runtime/scripts/`: script PowerShell
