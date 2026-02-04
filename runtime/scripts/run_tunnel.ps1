$ErrorActionPreference = "Stop"
Write-Host "[run_tunnel] Starting cloudflared tunnel..."
Start-Process -FilePath "runtime/tools/cloudflared.exe" -ArgumentList "tunnel", "--url", "http://localhost:8000"
