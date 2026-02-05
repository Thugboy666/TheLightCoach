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

$useConfig = $false
$credentialsPath = $null

if (Test-Path $configPath) {
  $configLines = Get-Content -Path $configPath
  foreach ($line in $configLines) {
    if ($line -match "^\s*credentials-file:\s*(.+)\s*$") {
      $credentialsRaw = $Matches[1].Trim()
      if ([System.IO.Path]::IsPathRooted($credentialsRaw)) {
        $credentialsPath = $credentialsRaw
      } else {
        $credentialsPath = Join-Path (Split-Path $configPath -Parent) $credentialsRaw
      }
      break
    }
  }
  if ($credentialsPath -and (Test-Path $credentialsPath)) {
    $useConfig = $true
  } else {
    Write-Status "Tunnel" "WARN" "Config found but credentials file missing"
  }
} else {
  Write-Status "Tunnel" "WARN" "Config not found, trying token fallback"
}

if ($useConfig) {
  Write-Status "Tunnel" "OK" "Using named tunnel config"
  Start-Proc "Cloudflared" $cloudflaredExe @("tunnel", "--config", $configPath, "run") (Split-Path $cloudflaredExe -Parent) | Out-Null
  return
}

$tokenPath = Join-Path $root "runtime/cloudflared/home/.cloudflared/codicetunnel.json"
$tokenJson = Get-Json $tokenPath
if (-not $tokenJson -or -not $tokenJson.credentials -or -not $tokenJson.credentials.value) {
  Write-Status "Tunnel" "FAIL" "Token JSON missing or invalid"
  exit 1
}

Write-Status "Tunnel" "OK" "Using token fallback"
Start-Proc "Cloudflared" $cloudflaredExe @("tunnel", "run", "--token", $tokenJson.credentials.value) (Split-Path $cloudflaredExe -Parent) | Out-Null
