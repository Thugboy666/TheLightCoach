$ErrorActionPreference = "Stop"

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
    [string]$Workdir
  )
  $argumentList = $Args
  if (-not $argumentList) {
    $argumentList = @()
  }
  Write-Status $Label "INFO" ("Starting: {0} {1}" -f $Exe, ($argumentList -join " "))
  return Start-Process -FilePath $Exe -ArgumentList $argumentList -WorkingDirectory $Workdir -PassThru
}
