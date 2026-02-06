$ErrorActionPreference = "Stop"

param(
  [string]$CloudflaredMode = "foreground",
  [switch]$DisableTunnel,
  [switch]$EnableLlama
)

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
