$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

& (Join-Path $PSScriptRoot "healthcheck.ps1")
if ($LASTEXITCODE -ne 0) {
  Write-Status "Healthcheck" "FAIL" "Missing critical runtime components."
  exit 1
}
Write-Status "Healthcheck" "OK" "Runtime dependencies present"

$pythonExe = Join-Path $root "runtime/python310/python.exe"
$fastApiProc = Start-Proc "FastAPI" $pythonExe @("-m", "uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "8000") $root

if (-not (Wait-HttpOk "http://127.0.0.1:8000/health" 20)) {
  Write-Status "FastAPI" "FAIL" "Health endpoint not reachable"
  if ($fastApiProc) {
    Stop-Process -Id $fastApiProc.Id -Force
  }
  exit 1
}
Write-Status "FastAPI" "OK" "Health endpoint responding"

Start-Proc "Tunnel" "powershell" @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "run_tunnel.ps1")) $root | Out-Null

Write-Status "Tunnel" "INFO" "Hostname configured: coach.vitazenith-wellness.it"
Write-Status "Tunnel" "INFO" "Check from phone: https://coach.vitazenith-wellness.it/health"

if ($fastApiProc) {
  Wait-Process -Id $fastApiProc.Id
}
