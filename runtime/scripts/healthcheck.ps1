$ErrorActionPreference = "Stop"
Write-Host "[healthcheck] Checking FastAPI..."
try {
  Invoke-RestMethod -Uri "http://localhost:8000/health" | Out-Null
  Write-Host "[healthcheck] FastAPI OK"
} catch {
  Write-Host "[healthcheck] FastAPI NOT reachable"
}
Write-Host "[healthcheck] Checking llama.cpp server..."
try {
  Invoke-RestMethod -Uri "http://localhost:8080/health" | Out-Null
  Write-Host "[healthcheck] llama.cpp OK"
} catch {
  Write-Host "[healthcheck] llama.cpp NOT reachable"
}
Write-Host "[healthcheck] Checking Piper..."
if (Test-Path "runtime/tts/piper/piper.exe") {
  Write-Host "[healthcheck] Piper OK"
} else {
  Write-Host "[healthcheck] Piper missing"
}
Write-Host "[healthcheck] Checking Vosk model..."
if (Test-Path "runtime/asr/vosk/model") {
  Write-Host "[healthcheck] Vosk model OK"
} else {
  Write-Host "[healthcheck] Vosk model missing"
}
