$ErrorActionPreference = "Continue"

. "$PSScriptRoot/_lib.ps1"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

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

$tokenPath = Join-Path $root "runtime/cloudflared/home/.cloudflared/codicetunnel.json"
if (Test-Path $tokenPath) {
  $tokenJson = Get-Json $tokenPath
  if ($tokenJson -and $tokenJson.credentials -and $tokenJson.credentials.value) {
    Add-Status "Tunnel token" "OK" $tokenPath
  } else {
    Add-Status "Tunnel token" "ERROR" ("Invalid token JSON: {0}" -f $tokenPath)
  }
} else {
  Add-Status "Tunnel token" "ERROR" ("Missing: {0}" -f $tokenPath)
}

$voskPath = Join-Path $root "runtime/asr/vosk/model"
if (Test-Path $voskPath) {
  $hasModelFile = Get-ChildItem -Path $voskPath -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hasModelFile) {
    Add-Status "Vosk (ASR)" "OK" "Model files present"
  } else {
    Add-Status "Vosk (ASR)" "WARN" "Model directory is empty"
  }
} else {
  Add-Status "Vosk (ASR)" "WARN" "Model directory missing"
}

$hasHostname = $false
$configPath = Join-Path $root "runtime/cloudflared/config.yml"
if (Test-Path $configPath) {
  $hasHostname = Select-String -Path $configPath -Pattern "hostname:\s*coach\.vitazenith-wellness\.it" -SimpleMatch -ErrorAction SilentlyContinue
}
if ($hasHostname) {
  Add-Status "Tunnel hostname" "OK" "coach.vitazenith-wellness.it configured"
} else {
  Add-Status "Tunnel hostname" "WARN" "coach.vitazenith-wellness.it not found in config"
}

$cloudflaredProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
if ($cloudflaredProc) {
  Add-Status "Cloudflare Tunnel" "OK" "cloudflared running"
} else {
  Add-Status "Cloudflare Tunnel" "ERROR" "cloudflared not running"
}

$fastApiPath = Join-Path $root "app/server.py"
if (Test-Path $fastApiPath) {
  if (Wait-HttpOk "http://127.0.0.1:8000/health" 3) {
    Add-Status "FastAPI" "OK" "Health endpoint responding"
  } else {
    Add-Status "FastAPI" "ERROR" "Health endpoint not responding"
  }
} else {
  Add-Status "FastAPI" "ERROR" ("Missing: {0}" -f $fastApiPath)
}

Test-OptionalPath "llama.cpp (LLM)" (Join-Path $root "runtime/llm/llamacpp/llama-server.exe")

$statusEntries
