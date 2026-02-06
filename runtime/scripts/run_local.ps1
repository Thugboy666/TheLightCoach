# NOTE: Keep param as the first executable statement for Windows PowerShell 5.1 compatibility.
param(
  [string]$CloudflaredMode = "foreground",
  [switch]$DisableTunnel,
  [switch]$EnableLlama
)

$ErrorActionPreference = "Stop"

Write-Host "Launching local runtime (FastAPI -> health -> tunnel -> summary)" -ForegroundColor Cyan

$argList = @()
$argList += @("-CloudflaredMode", $CloudflaredMode)
if ($DisableTunnel.IsPresent) {
  $argList += "-DisableTunnel"
}
if ($EnableLlama.IsPresent) {
  $argList += "-EnableLlama"
}

& (Join-Path $PSScriptRoot "run_all.ps1") @argList
