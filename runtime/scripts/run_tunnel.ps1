$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

param(
  [ValidateSet("config", "token")]
  [string]$Mode = "config"
)

$root = Get-RuntimeRoot
$cloudflaredHome = Join-Path $root "runtime/cloudflared/home"
if (-not (Test-Path $cloudflaredHome)) {
  New-Item -Path $cloudflaredHome -ItemType Directory -Force | Out-Null
}
$env:HOME = (Resolve-Path $cloudflaredHome).Path

$cloudflaredExe = Join-Path $root "runtime/cloudflared/cloudflared.exe"
$configPath = Join-Path $root "runtime/cloudflared/config.yml"

if (-not (Test-Path $cloudflaredExe)) {
  Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $cloudflaredExe)
  return
}

if (-not (Test-Path $configPath)) {
  Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $configPath)
  return
}

$tokenValue = $null
if ($Mode -eq "token") {
  $tokenPath = Join-Path $root "runtime/cloudflared/home/.cloudflared/codicetunnel.json"
  $tokenJson = Get-TunnelTokenInfo $tokenPath
  if (-not $tokenJson) {
    Write-Status "Tunnel" "ERROR" ("Token JSON missing or invalid: {0}" -f $tokenPath)
    Write-Host "Example JSON:" -ForegroundColor Red
    Write-Host '{ "tunnel_name": "coach", "tunnel_id": "UUID-HERE", "token": "TOKEN-HERE" }' -ForegroundColor Red
    return
  }
  $tokenValue = $tokenJson.token
}

Write-Status "Tunnel" "OK" "Starting Cloudflare Tunnel via config"
$args = @("--config", $configPath, "tunnel", "run")
if ($Mode -eq "token" -and $tokenValue) {
  $args += @("--token", $tokenValue)
}
Start-Proc "Cloudflared" $cloudflaredExe $args (Split-Path $cloudflaredExe -Parent) "tunnel"
