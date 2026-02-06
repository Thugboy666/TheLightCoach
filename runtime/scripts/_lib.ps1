$ErrorActionPreference = "Stop"

function Get-RuntimeRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-LogsDir {
  $logDir = Join-Path (Get-RuntimeRoot) "runtime/logs"
  if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
  }
  return $logDir
}

function Write-Status {
  param(
    [string]$Label,
    [string]$State,
    [string]$Details
  )
  $color = "Cyan"
  switch ($State.ToUpperInvariant()) {
    "OK" { $color = "Green" }
    "WARN" { $color = "Yellow" }
    "FAIL" { $color = "Red" }
    "ERROR" { $color = "Red" }
    "INFO" { $color = "Cyan" }
    default { $color = "Cyan" }
  }
  Write-Host ("[{0}] {1} - {2}" -f $Label, $State.ToUpperInvariant(), $Details) -ForegroundColor $color
}

function Require-Path {
  param(
    [string]$Label,
    [string]$Path
  )
  if (Test-Path $Path) {
    Write-Status $Label "OK" $Path
    return $true
  }
  Write-Status $Label "FAIL" ("Missing: {0}" -f $Path)
  return $false
}

function Get-Json {
  param(
    [string]$Path
  )
  if (-not (Test-Path $Path)) {
    return $null
  }
  try {
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
  } catch {
    Write-Status "JSON" "WARN" ("Invalid JSON: {0}" -f $Path)
    return $null
  }
}

function Wait-HttpOk {
  param(
    [string]$Url,
    [int]$TimeoutSec = 20
  )
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
      if ($response.StatusCode -eq 200) {
        return $true
      }
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  return $false
}

function Start-Proc {
  param(
    [string]$Label,
    [string]$Exe,
    [string[]]$Args,
    [string]$Workdir,
    [string]$LogName
  )
  $argumentList = @()
  if ($Args) {
    $argumentList = @($Args | Where-Object { $null -ne $_ })
  }
  $safeWorkdir = $Workdir
  if ([string]::IsNullOrWhiteSpace($safeWorkdir)) {
    if (Test-Path $Exe) {
      $safeWorkdir = Split-Path $Exe -Parent
    } else {
      $safeWorkdir = (Get-Location).Path
    }
  }
  $name = $LogName
  if ([string]::IsNullOrWhiteSpace($name)) {
    $name = ($Label -replace "\s+", "_").ToLowerInvariant()
  }
  $logDir = Get-LogsDir
  $stdoutPath = Join-Path $logDir ("{0}.log" -f $name)
  $stderrPath = Join-Path $logDir ("{0}.error.log" -f $name)

  Write-Status $Label "INFO" ("Starting: {0} {1}" -f $Exe, ($argumentList -join " "))
  $startParams = @{
    FilePath = $Exe
    WorkingDirectory = $safeWorkdir
    PassThru = $true
    RedirectStandardOutput = $stdoutPath
    RedirectStandardError = $stderrPath
    NoNewWindow = $true
  }
  if ($argumentList.Count -gt 0) {
    $startParams.ArgumentList = $argumentList
  }
  return Start-Process @startParams
}

function Get-TunnelTokenInfo {
  param(
    [string]$Path
  )
  if (-not (Test-Path $Path)) {
    return $null
  }
  try {
    $data = Get-Content -Path $Path -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
  if (-not $data) {
    return $null
  }
  if (-not $data.tunnel_name -or -not $data.tunnel_id -or -not $data.token) {
    return $null
  }
  return $data
}
