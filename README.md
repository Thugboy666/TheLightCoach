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
   ./runtime/scripts/run_all.ps1
   ```
4. Da telefono sulla LAN apri `http://PC:8000`.

## Avvio locale + tunnel Cloudflare
- Avvio completo (healthcheck + FastAPI + tunnel):
  ```powershell
  ./runtime/scripts/run_all.ps1
  ```
- Avvio con llama-server (se presente):
  ```powershell
  ./runtime/scripts/run_all.ps1 -EnableLlama
  ```
- Tunnel Cloudflare usa un named tunnel definito in `runtime/cloudflared/config.yml` con hostname `coach.vitazenith-wellness.it`.
- Credenziali tunnel: `runtime/cloudflared/home/.cloudflared/<TUNNEL_ID>.json`.
- Fallback token JSON: `runtime/cloudflared/home/.cloudflared/codicetunnel.json`.
- Modalità token (usa config.yml + codicetunnel.json):
  ```powershell
  ./runtime/scripts/run_all.ps1 -CloudflaredMode token
  ```

### Cloudflared come servizio Windows (opzionale)
La modalità predefinita è **foreground** (portatile, senza admin). Per usare un servizio:
1. Installa il servizio manualmente con `--config` (non inserire token nel binpath).
   ```powershell
   sc.exe create Cloudflared binPath= "\"C:\TheLightCoach\runtime\cloudflared\cloudflared.exe\" --config \"C:\TheLightCoach\runtime\cloudflared\config.yml\" tunnel run"
   ```
2. Avvia con:
   ```powershell
   ./runtime/scripts/run_all.ps1 -CloudflaredMode service
   ```

## Modalità
Alla prima apertura viene richiesta la selezione modalità. La scelta è salvata lato client (localStorage) e lato server (cookie di sessione).

## Troubleshooting
- Nessun audio: verifica permessi microfono sul browser.
- LLM non risponde: controlla `runtime/llm/llamacpp/llama-server.exe` e modello in `runtime/llm/models/`.
- TTS muto: verifica Piper e una voce `.onnx` in `runtime/tts/voices/`.
- ASR muto: verifica modello Vosk in `runtime/asr/vosk/model`.

## Debug Loop in 60 seconds
```powershell
./tools/context_pack.ps1
./tools/quick_test.ps1
./runtime/scripts/run_local.ps1
```

## File tree
- `app/server.py`: FastAPI + Coach Engine API
- `app/data/`: dataset per modalità
- `app/client/`: PWA
- `runtime/scripts/`: script PowerShell
