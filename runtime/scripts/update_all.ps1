$ErrorActionPreference = "Stop"
Write-Host "[update_all] Pulling latest changes..."
& git pull
Write-Host "[update_all] Bootstrapping..."
& "runtime/scripts/bootstrap.ps1"
Write-Host "[update_all] Healthcheck..."
& "runtime/scripts/healthcheck.ps1"
