$ErrorActionPreference = "Stop"
Write-Host "[bootstrap] Checking runtime paths..."
$paths = @(
  "runtime/python310",
  "runtime/llm",
  "runtime/tts",
  "runtime/asr"
)
foreach ($path in $paths) {
  if (!(Test-Path $path)) {
    New-Item -ItemType Directory -Path $path | Out-Null
  }
}
Write-Host "[bootstrap] Installing wheels (if present)..."
if (Test-Path "runtime/wheels") {
  Get-ChildItem -Path "runtime/wheels" -Filter "*.whl" | ForEach-Object {
    & "runtime/python310/python.exe" -m pip install $_.FullName --no-deps
  }
}
Write-Host "[bootstrap] Done."
