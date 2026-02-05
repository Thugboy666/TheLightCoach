$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

param(
  [ValidateSet("foreground", "service", "token")]
  [string]$CloudflaredMode = "foreground",
  [switch]$EnableLlama
)

$root = Get-RuntimeRoot
$apiUrl = "http://127.0.0.1:8000"
$tunnelHostname = "coach.vitazenith-wellness.it"
$tunnelUrl = "https://$tunnelHostname"
$logDir = Get-LogsDir
$pythonExe = Join-Path $root "runtime/python310/python.exe"
$cloudflaredExe = Join-Path $root "runtime/cloudflared/cloudflared.exe"
$configPath = Join-Path $root "runtime/cloudflared/config.yml"
$llamaExe = Join-Path $root "runtime/llm/llamacpp/llama-server.exe"
$llamaModel = Join-Path $root "runtime/llm/models/model.gguf"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "   TheLightCoach Runtime Launcher    " -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

$statusEntries = & (Join-Path $PSScriptRoot "healthcheck.ps1")
Write-Status "Healthcheck" "INFO" "Completed dependency scan"

$processes = @()

if ($EnableLlama.IsPresent) {
  if (Test-Path $llamaExe -and Test-Path $llamaModel) {
    try {
      $llamaArgs = @("--model", $llamaModel, "--port", "8080")
      $llamaProc = Start-Proc "Llama" $llamaExe $llamaArgs (Split-Path $llamaExe -Parent) "llama"
      $processes += $llamaProc
      Write-Status "Llama" "OK" ("Started (PID {0})" -f $llamaProc.Id)
    } catch {
      Write-Status "Llama" "WARN" ("Failed to start: {0}" -f $_.Exception.Message)
    }
  } else {
    Write-Status "Llama" "WARN" "llama-server.exe or model.gguf missing, skipping"
  }
} else {
  Write-Status "Llama" "INFO" "Skipped (use -EnableLlama to start)"
}

if (-not (Test-Path $pythonExe)) {
  Write-Status "FastAPI" "ERROR" ("Missing: {0}" -f $pythonExe)
  return
}

Write-Status "FastAPI" "INFO" ("Starting API on {0}" -f $apiUrl)
$apiArgs = @("-m", "uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "8000")
$apiProc = Start-Proc "FastAPI" $pythonExe $apiArgs $root "api"
$processes += $apiProc

if (-not (Wait-HttpOk "$apiUrl/health" 20)) {
  Write-Status "FastAPI" "WARN" "Health endpoint not ready after 20s"
} else {
  Write-Status "FastAPI" "OK" "Health endpoint responding"
}

switch ($CloudflaredMode) {
  "service" {
    $service = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
    if ($service) {
      if ($service.Status -ne "Running") {
        try {
          Start-Service -Name "Cloudflared"
        } catch {
          Write-Status "Tunnel" "WARN" ("Failed to start service: {0}" -f $_.Exception.Message)
        }
      }
      $service = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
      Write-Status "Tunnel" "INFO" ("Service status: {0}" -f $service.Status)
    } else {
      Write-Status "Tunnel" "WARN" "Cloudflared service not installed"
    }
  }
  "token" {
    if (-not (Test-Path $cloudflaredExe)) {
      Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $cloudflaredExe)
    } elseif (-not (Test-Path $configPath)) {
      Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $configPath)
    } else {
      $tunnelProc = & (Join-Path $PSScriptRoot "run_tunnel.ps1") -Mode "token"
      if ($tunnelProc) {
        $processes += $tunnelProc
      }
    }
  }
  default {
    if (-not (Test-Path $cloudflaredExe)) {
      Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $cloudflaredExe)
    } elseif (-not (Test-Path $configPath)) {
      Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $configPath)
    } else {
      $tunnelProc = & (Join-Path $PSScriptRoot "run_tunnel.ps1")
      if ($tunnelProc) {
        $processes += $tunnelProc
      }
    }
  }
}

Write-Host ""
Write-Host "Startup Summary" -ForegroundColor Cyan
Write-Host ("API URL: {0}" -f $apiUrl) -ForegroundColor Cyan
Write-Host ("Tunnel URL: {0}" -f $tunnelUrl) -ForegroundColor Cyan
if ($processes.Count -gt 0) {
  $pidList = $processes | ForEach-Object { $_.Id } | Sort-Object
  Write-Host ("Process PIDs: {0}" -f ($pidList -join ", ")) -ForegroundColor Cyan
}
Write-Host ("Logs: {0}" -f $logDir) -ForegroundColor Cyan
Write-Host ""

Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
try {
  while ($true) {
    Start-Sleep -Seconds 1
  }
} finally {
  foreach ($proc in $processes) {
    if ($proc -and -not $proc.HasExited) {
      Write-Status "Shutdown" "INFO" ("Stopping PID {0}" -f $proc.Id)
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
  Write-Status "Shutdown" "INFO" "Shutdown complete"
}
