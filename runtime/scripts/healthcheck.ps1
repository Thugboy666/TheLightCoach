$ErrorActionPreference = "Continue"

. "$PSScriptRoot/_lib.ps1"

$root = Get-RuntimeRoot
$apiUrl = "http://127.0.0.1:8000"
$tunnelHostname = "coach.vitazenith-wellness.it"
$tunnelUrl = "https://$tunnelHostname"

$statusEntries = @()

function Add-Status {
  param(
    [string]$Component,
    [string]$State,
    [string]$Details
  )
  $statusEntries += [pscustomobject]@{
    Component = $Component
    State = $State.ToUpperInvariant()
    Details = $Details
  }
  Write-Status $Component $State $Details
}

function Test-RequiredPath {
  param(
    [string]$Component,
    [string]$Path
  )
  if (Test-Path $Path) {
    Add-Status $Component "OK" $Path
  } else {
    Add-Status $Component "ERROR" ("Missing: {0}" -f $Path)
  }
}

function Test-OptionalPath {
  param(
    [string]$Component,
    [string]$Path
  )
  if (Test-Path $Path) {
    Add-Status $Component "OK" $Path
  } else {
    Add-Status $Component "WARN" ("Missing: {0}" -f $Path)
  }
}

Test-RequiredPath "Python" (Join-Path $root "runtime/python310/python.exe")
Test-RequiredPath "Piper (TTS)" (Join-Path $root "runtime/tts/piper/piper.exe")
Test-RequiredPath "Cloudflared" (Join-Path $root "runtime/cloudflared/cloudflared.exe")
Test-RequiredPath "Tunnel config" (Join-Path $root "runtime/cloudflared/config.yml")
Test-RequiredPath "llama.cpp (LLM)" (Join-Path $root "runtime/llm/llamacpp/llama-server.exe")
Test-RequiredPath "LLM model (GGUF)" (Join-Path $root "runtime/llm/models/model.gguf")

$voskPath = Join-Path $root "runtime/asr/vosk/model"
$voskRequired = @(
  (Join-Path $voskPath "conf/model.conf"),
  (Join-Path $voskPath "am/final.mdl"),
  (Join-Path $voskPath "graph/words.txt")
)
if (Test-Path $voskPath) {
  $missing = @($voskRequired | Where-Object { -not (Test-Path $_) })
  if ($missing.Count -eq 0) {
    Add-Status "Vosk (ASR)" "OK" "Model files present"
  } else {
    Add-Status "Vosk (ASR)" "WARN" ("Missing: {0}" -f ($missing -join ", "))
  }
} else {
  Add-Status "Vosk (ASR)" "WARN" "Model directory missing"
}

$configPath = Join-Path $root "runtime/cloudflared/config.yml"
$hostnameMatch = $false
if (Test-Path $configPath) {
  $hostnameMatch = Select-String -Path $configPath -Pattern "hostname:\s*$tunnelHostname" -SimpleMatch -ErrorAction SilentlyContinue
}
if ($hostnameMatch) {
  Add-Status "Tunnel hostname" "OK" ("{0} configured" -f $tunnelHostname)
} else {
  Add-Status "Tunnel hostname" "WARN" ("{0} not found in config" -f $tunnelHostname)
}

$cloudflaredProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
if ($cloudflaredProc) {
  Add-Status "Cloudflare Tunnel" "OK" "cloudflared running"
} else {
  Add-Status "Cloudflare Tunnel" "ERROR" "cloudflared not running"
}

$fastApiPath = Join-Path $root "app/server.py"
if (Test-Path $fastApiPath) {
  if (Wait-HttpOk "$apiUrl/health" 3) {
    Add-Status "FastAPI" "OK" "Health endpoint responding"
  } else {
    Add-Status "FastAPI" "ERROR" "Health endpoint not responding"
  }
} else {
  Add-Status "FastAPI" "ERROR" ("Missing: {0}" -f $fastApiPath)
}

Write-Host ""
Write-Host "Startup Summary" -ForegroundColor Cyan
Write-Host ("API URL: {0}" -f $apiUrl) -ForegroundColor Cyan
Write-Host ("Tunnel URL: {0}" -f $tunnelUrl) -ForegroundColor Cyan
Write-Host ""

$statusEntries
