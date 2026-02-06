$ErrorActionPreference = "Continue"

. "$PSScriptRoot/../runtime/scripts/_lib.ps1"

$root = Get-RuntimeRoot
$apiUrl = "http://127.0.0.1:8000"
$pythonExe = Join-Path $root "runtime/python310/python.exe"

function Invoke-ApiFormPost {
  param(
    [string]$Uri,
    [hashtable]$FormData
  )
  if ($PSVersionTable.PSVersion.Major -ge 7) {
    return Invoke-RestMethod -Uri $Uri -Method Post -Form $FormData
  }

  $encodedBody = ($FormData.GetEnumerator() | ForEach-Object {
      "{0}={1}" -f [System.Uri]::EscapeDataString($_.Key), [System.Uri]::EscapeDataString([string]$_.Value)
    }) -join "&"
  return Invoke-RestMethod -Uri $Uri -Method Post -Body $encodedBody -ContentType "application/x-www-form-urlencoded"
}

function Add-Result {
  param(
    [string]$Label,
    [bool]$Success,
    [string]$Details
  )
  if ($Success) {
    Write-Status $Label "OK" $Details
  } else {
    Write-Status $Label "ERROR" $Details
  }
}

if (-not (Test-Path $pythonExe)) {
  Write-Status "Python" "ERROR" ("Missing: {0}" -f $pythonExe)
  exit 1
}

$apiProc = $null
try {
  $apiArgs = @("-m", "uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "8000")
  $apiProc = Start-Proc "FastAPI" $pythonExe $apiArgs $root "api_quick"

  if (-not (Wait-HttpOk "$apiUrl/api/coach/health" 15)) {
    Write-Status "FastAPI" "ERROR" "Health endpoint not responding"
    exit 1
  }
  Write-Status "FastAPI" "OK" "Health endpoint responding"

  $tests = @(
    @{ Name = "ansia + triangolazione"; Mode = "emotional_core"; Transcript = "Sento ansia e lui ha detto a lei che sono confusa."; Silence = $false },
    @{ Name = "richiesta rassicurazione"; Mode = "emotional_core"; Transcript = "Dimmi che va tutto bene, ho bisogno di rassicurazione."; Silence = $false },
    @{ Name = "impulso notturno"; Mode = "emotional_core"; Transcript = "Ho l'impulso di scrivere di notte, cosa rispondo ora?"; Silence = $true },
    @{ Name = "debrief post meeting B2B"; Mode = "sales_b2b"; Transcript = "Post meeting: ho promesso troppo e ora devo fare follow-up."; Silence = $false },
    @{ Name = "social/dating visualizzato"; Mode = "social_dating"; Transcript = "Mi ha lasciato visualizzato, cosa faccio?"; Silence = $false }
  )

  foreach ($test in $tests) {
    try {
      $form = @{
        transcript = $test.Transcript
        mode = $test.Mode
        show_alternatives = "true"
        live_beta = "false"
      }
      $response = Invoke-ApiFormPost -Uri "$apiUrl/api/coach/analyze_audio" -FormData $form
      $ok = $true
      if (-not $response.phrase) { $ok = $false }
      if (-not $response.score) { $ok = $false }
      if (-not $response.indicators) { $ok = $false }
      if ($test.Silence -and -not $response.active_silence.enabled) { $ok = $false }
      if (-not $response.alternatives -or $response.alternatives.Count -lt 1) { $ok = $false }
      Add-Result $test.Name $ok "JSON received"
    } catch {
      Add-Result $test.Name $false $_.Exception.Message
    }
  }
} finally {
  if ($apiProc -and -not $apiProc.HasExited) {
    Write-Status "Shutdown" "INFO" ("Stopping PID {0}" -f $apiProc.Id)
    Stop-Process -Id $apiProc.Id -Force -ErrorAction SilentlyContinue
  }
}
