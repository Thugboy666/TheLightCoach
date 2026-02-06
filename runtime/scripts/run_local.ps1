param(
  [string]$CloudflaredMode = "foreground",
  [switch]$DisableTunnel,
  [switch]$EnableLlama
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_lib.ps1"

$null = Get-LogsDir

$argList = @()
if ($PSBoundParameters.ContainsKey("CloudflaredMode")) {
  $argList += @("-CloudflaredMode", $CloudflaredMode)
}
if ($DisableTunnel.IsPresent) {
  $argList += "-DisableTunnel"
}
if ($EnableLlama.IsPresent) {
  $argList += "-EnableLlama"
}

& "$PSScriptRoot/run_all.ps1" @argList
