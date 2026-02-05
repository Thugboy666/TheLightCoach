$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$criticalMissing = $false

function Test-Critical {
  param(
    [string]$Label,
    [string]$Path
  )
  if (-not (Require-Path $Label $Path)) {
    $script:criticalMissing = $true
  }
}

Test-Critical "Python" (Join-Path $root "runtime/python310/python.exe")
Test-Critical "FFmpeg" (Join-Path $root "runtime/ffmpeg/ffmpeg.exe")
Test-Critical "Cloudflared" (Join-Path $root "runtime/cloudflared/cloudflared.exe")
Test-Critical "Cloudflared config" (Join-Path $root "runtime/cloudflared/config.yml")
Test-Critical "Piper" (Join-Path $root "runtime/tts/piper/piper.exe")

$voskPath = Join-Path $root "runtime/asr/vosk/model"
if (Test-Path $voskPath) {
  $hasModelFile = Get-ChildItem -Path $voskPath -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hasModelFile) {
    Write-Status "Vosk" "OK" "Model files present"
  } else {
    Write-Status "Vosk" "WARN" "Model directory is empty"
  }
} else {
  Write-Status "Vosk" "WARN" "Model directory missing"
}

$configPath = Join-Path $root "runtime/cloudflared/config.yml"
if (Test-Path $configPath) {
  $hasHostname = Select-String -Path $configPath -Pattern "hostname:\s*coach\.vitazenith-wellness\.it" -SimpleMatch
  if ($hasHostname) {
    Write-Status "Tunnel config" "OK" "Hostname configured"
  } else {
    Write-Status "Tunnel config" "WARN" "Hostname coach.vitazenith-wellness.it not found"
  }
}

if ($criticalMissing) {
  exit 1
}
exit 0
