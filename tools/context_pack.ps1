$ErrorActionPreference = "Continue"

. "$PSScriptRoot/../runtime/scripts/_lib.ps1"

$root = Get-RuntimeRoot
$logPath = Join-Path $root "runtime/logs/api.log"

Write-Host "" 
Write-Host "=== Context Pack (Mirror Coach) ===" -ForegroundColor Cyan
Write-Host "Root: $root" -ForegroundColor Cyan
Write-Host ""

Write-Host "# Git" -ForegroundColor Cyan
try {
  $head = git -C $root rev-parse HEAD
  $lastCommit = git -C $root log -1 --pretty=oneline
  Write-Host "HEAD: $head"
  Write-Host "Last commit: $lastCommit"
} catch {
  Write-Host "Git info unavailable"
}

try {
  Write-Host "" 
  git -C $root status -sb
} catch {
  Write-Host "Git status unavailable"
}

try {
  Write-Host "" 
  Write-Host "# Diff" -ForegroundColor Cyan
  git -C $root diff --name-only
  git -C $root diff --stat
} catch {
  Write-Host "Diff unavailable"
}

Write-Host "" 
Write-Host "# Tree (depth 2)" -ForegroundColor Cyan
try {
  cmd /c "tree /A /F /L 2 \"$root\""
} catch {
  Write-Host "Tree unavailable"
}

Write-Host "" 
Write-Host "# Versions" -ForegroundColor Cyan
try { python --version } catch { Write-Host "python not in PATH" }
try { pip --version } catch { Write-Host "pip not in PATH" }

Write-Host "" 
Write-Host "# Runtime presence checks" -ForegroundColor Cyan
$checks = @(
  @{ Label = "Python"; Path = Join-Path $root "runtime/python310/python.exe" },
  @{ Label = "Cloudflared"; Path = Join-Path $root "runtime/cloudflared/cloudflared.exe" },
  @{ Label = "Piper"; Path = Join-Path $root "runtime/tts/piper/piper.exe" },
  @{ Label = "llama-server"; Path = Join-Path $root "runtime/llm/llamacpp/llama-server.exe" },
  @{ Label = "ffmpeg"; Path = Join-Path $root "runtime/ffmpeg/ffmpeg.exe" }
)
foreach ($check in $checks) {
  if (Test-Path $check.Path) {
    Write-Status $check.Label "OK" $check.Path
  } else {
    Write-Status $check.Label "WARN" ("Missing: {0}" -f $check.Path)
  }
}

Write-Host "" 
Write-Host "# Recent API log (last 200 lines)" -ForegroundColor Cyan
if (Test-Path $logPath) {
  Get-Content -Path $logPath -Tail 200
} else {
  Write-Host "No API log found at runtime/logs/api.log" 
  Write-Host "Start the server to generate logs: ./runtime/scripts/run_local.ps1"
}

Write-Host "" 
Write-Host "Usage examples:" -ForegroundColor Cyan
Write-Host "  ./tools/context_pack.ps1"
Write-Host "  ./tools/quick_test.ps1"
Write-Host "  ./runtime/scripts/run_local.ps1"
