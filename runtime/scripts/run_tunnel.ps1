$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$cloudflaredHome = Join-Path $root "runtime/cloudflared/home"
if (-not (Test-Path $cloudflaredHome)) {
  New-Item -Path $cloudflaredHome -ItemType Directory -Force | Out-Null
}
$env:HOME = (Resolve-Path $cloudflaredHome).Path

$cloudflaredExe = Join-Path $root "runtime/cloudflared/cloudflared.exe"
$configPath = Join-Path $root "runtime/cloudflared/config.yml"

$tokenPath = Join-Path $root "runtime/cloudflared/home/.cloudflared/codicetunnel.json"
$tokenJson = Get-Json $tokenPath
if (-not $tokenJson -or -not $tokenJson.credentials -or -not $tokenJson.credentials.value) {
  Write-Status "Tunnel" "ERROR" ("Token JSON missing or invalid: {0}" -f $tokenPath)
  return
}

if (-not (Test-Path $cloudflaredExe)) {
  Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $cloudflaredExe)
  return
}

if (-not (Test-Path $configPath)) {
  Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $configPath)
  return
}

Write-Status "Tunnel" "OK" "Starting Cloudflare Tunnel via config"
Start-Proc "Cloudflared" $cloudflaredExe @("tunnel", "run", "--config", $configPath) (Split-Path $cloudflaredExe -Parent) | Out-Null
