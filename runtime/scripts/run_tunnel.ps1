param(
  [ValidateSet("config", "token")]
  [string]$Mode = "config"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

Write-Host ("[Tunnel] PSVersion={0} Script={1}" -f $PSVersionTable.PSVersion, $MyInvocation.MyCommand.Path)

$root = Get-RuntimeRoot
$cloudflaredHome = Join-Path $root "runtime/cloudflared/home"
if (-not (Test-Path $cloudflaredHome)) {
  New-Item -Path $cloudflaredHome -ItemType Directory -Force | Out-Null
}
$env:HOME = (Resolve-Path $cloudflaredHome).Path

$cloudflaredExe = Join-Path $root "runtime/cloudflared/cloudflared.exe"
$configPath = Join-Path $root "runtime/cloudflared/config.yml"
$origincertPath = Join-Path $cloudflaredHome ".cloudflared/cert.pem"

if (-not (Test-Path $cloudflaredExe)) {
  Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $cloudflaredExe)
  return [pscustomobject]@{
    Success = $false
    Process = $null
    Error = "Missing cloudflared executable."
  }
}

if (-not (Test-Path $configPath)) {
  Write-Status "Tunnel" "ERROR" ("Missing: {0}" -f $configPath)
  return [pscustomobject]@{
    Success = $false
    Process = $null
    Error = "Missing cloudflared config."
  }
}

if (-not (Test-Path $origincertPath)) {
  Write-Status "Tunnel" "WARN" "cloudflared tunnel route dns richiede cert.pem (origincert). Eseguire: cloudflared tunnel login"
}

$tokenValue = $null
if ($Mode -eq "token") {
  $tokenPath = Join-Path $root "runtime/cloudflared/home/.cloudflared/codicetunnel.json"
  $tokenJson = Get-TunnelTokenInfo $tokenPath
  if (-not $tokenJson) {
    Write-Status "Tunnel" "ERROR" ("Token JSON missing or invalid: {0}" -f $tokenPath)
    Write-Host "Example JSON:" -ForegroundColor Red
    Write-Host '{ "tunnel_name": "coach", "tunnel_id": "UUID-HERE", "token": "TOKEN-HERE" }' -ForegroundColor Red
    return [pscustomobject]@{
      Success = $false
      Process = $null
      Error = "Token JSON missing or invalid."
    }
  }
  $tokenValue = $tokenJson.token
}

Write-Status "Tunnel" "OK" "Starting Cloudflare Tunnel via config"
$args = @("--config", $configPath, "tunnel", "run")
if ($Mode -eq "token" -and $tokenValue) {
  $args += @("--token", $tokenValue)
}
try {
  $proc = Start-Proc "Cloudflared" $cloudflaredExe $args (Split-Path $cloudflaredExe -Parent) "tunnel"
  return [pscustomobject]@{
    Success = $true
    Process = $proc
    Error = $null
  }
} catch {
  Write-Status "Tunnel" "WARN" ("Failed to start cloudflared: {0}" -f $_.Exception.Message)
  return [pscustomobject]@{
    Success = $false
    Process = $null
    Error = $_.Exception.Message
  }
}
