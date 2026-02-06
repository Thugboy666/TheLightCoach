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

function Quote-Argument {
  param(
    [AllowNull()]
    [string]$Value
  )
  if ($null -eq $Value) {
    return '""'
  }
  if ([System.Management.Automation.Language.CodeGeneration] -and
      [System.Management.Automation.Language.CodeGeneration].GetMethod("QuoteArgument")) {
    return [System.Management.Automation.Language.CodeGeneration]::QuoteArgument($Value)
  }
  if ($Value -match '[\s"`]') {
    $escaped = $Value -replace '"', '\"'
    return '"' + $escaped + '"'
  }
  return $Value
}

function ConvertTo-ArgumentString {
  param(
    [string[]]$Args
  )
  if (-not $Args) {
    return ""
  }
  return ($Args | ForEach-Object { Quote-Argument $_ }) -join " "
}

function Start-Proc {
  param(
    [string]$Label,
    [string]$Exe,
    [Alias("ArgumentList")]
    [string[]]$ProcArgs,
    [string]$Workdir,
    [string]$LogName
  )
  $argumentList = @()
  if ($ProcArgs) {
    $argumentList = @($ProcArgs | Where-Object { $null -ne $_ })
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
  $commandPath = Join-Path $logDir ("{0}.command.log" -f $name)

  $exePath = $Exe
  $effectiveArgs = $argumentList
  if ($Exe -match '\.ps1$') {
    $powershellExe = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path $powershellExe)) {
      $powershellExe = "powershell.exe"
    }
    $exePath = $powershellExe
    $effectiveArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Exe) + $argumentList
  }

  $argumentSummary = ConvertTo-ArgumentString $effectiveArgs
  $startSummary = $exePath
  if (-not [string]::IsNullOrWhiteSpace($argumentSummary)) {
    $startSummary = "{0} {1}" -f $exePath, $argumentSummary
  }
  Write-Status $Label "INFO" ("Starting: {0}" -f $startSummary)
  Write-Status $Label "INFO" ("Stdout log: {0}" -f $stdoutPath)
  Write-Status $Label "INFO" ("Stderr log: {0}" -f $stderrPath)
  Set-Content -Path $commandPath -Value ("[{0}] {1}" -f (Get-Date -Format "s"), $startSummary)
  Write-Status $Label "INFO" ("Command log: {0}" -f $commandPath)
  $startParams = @{
    FilePath = $exePath
    WorkingDirectory = $safeWorkdir
    PassThru = $true
    RedirectStandardOutput = $stdoutPath
    RedirectStandardError = $stderrPath
    NoNewWindow = $true
  }
  if ($effectiveArgs.Count -gt 0) {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
      $startParams.ArgumentList = ConvertTo-ArgumentString $effectiveArgs
    } else {
      $startParams.ArgumentList = $effectiveArgs
    }
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

function Get-CloudflaredServiceConfigPath {
  $service = Get-WmiObject -Class Win32_Service -Filter "Name='Cloudflared'" -ErrorAction SilentlyContinue
  if (-not $service) {
    return $null
  }
  $pathName = $service.PathName
  if ([string]::IsNullOrWhiteSpace($pathName)) {
    return $null
  }
  $configMatch = [regex]::Match($pathName, '(--config|-config)\s+("?)([^"]+)\2')
  if ($configMatch.Success) {
    return $configMatch.Groups[3].Value
  }
  return $null
}
