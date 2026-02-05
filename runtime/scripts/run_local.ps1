$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$apiUrl = "http://127.0.0.1:8000"
$tunnelUrl = "https://coach.vitazenith-wellness.it"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " TheLightCoach Local Runtime Startup " -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

$statusEntries = & (Join-Path $PSScriptRoot "healthcheck.ps1")
Write-Status "Healthcheck" "INFO" "Completed dependency scan"

$tunnelProc = Start-Proc "Tunnel" "powershell" @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "run_tunnel.ps1")) $root

Write-Status "Tunnel" "INFO" ("Public URL: {0}" -f $tunnelUrl)
Write-Status "FastAPI" "INFO" ("Starting API on {0}" -f $apiUrl)
Write-Status "FastAPI" "INFO" ("Command: runtime/python310/python.exe -m uvicorn app.server:app --host 0.0.0.0 --port 8000")

Write-Host ""
Write-Host "Startup Summary" -ForegroundColor Cyan
Write-Host ("API URL: {0}" -f $apiUrl) -ForegroundColor Cyan
Write-Host ("Tunnel URL: {0}" -f $tunnelUrl) -ForegroundColor Cyan
Write-Host ""
Write-Host "Component Status" -ForegroundColor Cyan
if ($statusEntries) {
  $statusEntries | Format-Table -AutoSize Component, State, Details
} else {
  Write-Host "No status data returned." -ForegroundColor Yellow
}
Write-Host ""

$pythonExe = Join-Path $root "runtime/python310/python.exe"
try {
  & $pythonExe -m uvicorn app.server:app --host 0.0.0.0 --port 8000
} finally {
  if ($tunnelProc -and -not $tunnelProc.HasExited) {
    Write-Status "Tunnel" "INFO" "Stopping Cloudflare Tunnel"
    Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
  }
  Write-Status "Startup" "INFO" "Shutdown complete"
}
