param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = 'D:\wwo',
    [switch]$SkipVisibleCapture,
    [switch]$SkipPerformanceCapture,
    [switch]$OpenManualReview,
    [switch]$ContinueOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ExpectedGodotVersion = '4.6.3.stable.official.7d41c59c4'

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
}

function Convert-ToArgumentString {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    return (@(
        $Arguments | ForEach-Object {
            '"' + $_.Replace('"', '\"') + '"'
        }
    ) -join ' ')
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Visible
    )

    if ($Visible) {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList (Convert-ToArgumentString -Arguments $Arguments) `
            -WorkingDirectory $ProjectPath `
            -Wait `
            -PassThru
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = ''
        }
    }

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList (Convert-ToArgumentString -Arguments $Arguments) `
            -WorkingDirectory $ProjectPath `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Host $stdout.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host $stderr.TrimEnd()
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = (($stdout + "`n" + $stderr).Trim())
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Visible
    )

    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $started = Get-Date
    $result = Invoke-ExternalProcess `
        -FilePath $GodotPath `
        -Arguments $Arguments `
        -Visible:$Visible

    $script:Results += [pscustomobject]@{
        Name = $Name
        ExitCode = $result.ExitCode
        Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    }

    if ($result.ExitCode -ne 0 -and -not $ContinueOnFailure) {
        throw "$Name failed with exit code $($result.ExitCode)"
    }
}

Assert-PathExists -Path $GodotPath -Label 'Godot executable'
Assert-PathExists -Path $ProjectPath -Label 'Project directory'
Assert-PathExists -Path (Join-Path $ProjectPath 'project.godot') -Label 'project.godot'
Assert-PathExists -Path (Join-Path $ProjectPath 'tools\v2_2\capture_review.tscn') -Label 'V2.2 review capture scene'
Assert-PathExists -Path (Join-Path $ProjectPath 'tools\v2_2\perf_capture.tscn') -Label 'V2.2 performance capture scene'

$versionResult = Invoke-ExternalProcess -FilePath $GodotPath -Arguments @('--version')
$versionOutput = $versionResult.Output.Trim()
if ($versionResult.ExitCode -ne 0) {
    throw "Godot version command failed with exit code $($versionResult.ExitCode)"
}
if ($versionOutput -ne $ExpectedGodotVersion) {
    throw "Godot version mismatch. Expected $ExpectedGodotVersion, got: $versionOutput"
}
Write-Host "Godot: $versionOutput" -ForegroundColor DarkGray

$Results = @()
$headlessScripts = @(
    'res://tests/v2_2/v2_2_config_datetime_test.gd',
    'res://tests/v2_2/v2_2_atomicity_test.gd',
    'res://tests/v2_2/v2_2_time_test.gd',
    'res://tests/v2_2/v2_2_schedule_test.gd',
    'res://tests/v2_2/v2_2_employment_test.gd',
    'res://tests/v2_2/v2_2_household_test.gd',
    'res://tests/v2_2/v2_2_condition_test.gd',
    'res://tests/v2_2/v2_2_notification_test.gd',
    'res://tests/v2_2/v2_2_save_load_test.gd',
    'res://tests/v2_2/v2_2_determinism_test.gd',
    'res://tests/v2_2/v2_2_ui_binding_test.gd',
    'res://tests/v2_2/v2_2_performance_guard_test.gd',
    'res://tests/v2_2/v2_2_life_loop_smoke.gd',
    'res://tests/v2_2/v2_2_review_report.gd'
)

foreach ($scriptPath in $headlessScripts) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
    Invoke-Step -Name $name -Arguments @(
        '--headless',
        '--path', $ProjectPath,
        '--script', $scriptPath
    )
}

Write-Host ''
Write-Host '=== run_validation.ps1 ===' -ForegroundColor Cyan
$validationStarted = Get-Date
$validationResult = Invoke-ExternalProcess `
    -FilePath 'powershell.exe' `
    -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $ProjectPath 'tools\run_validation.ps1'),
        '-GodotPath', $GodotPath,
        '-ProjectPath', $ProjectPath
    )
$Results += [pscustomobject]@{
    Name = 'run_validation.ps1'
    ExitCode = $validationResult.ExitCode
    Seconds = [math]::Round(((Get-Date) - $validationStarted).TotalSeconds, 2)
}
if ($validationResult.ExitCode -ne 0 -and -not $ContinueOnFailure) {
    throw "Unified validation failed with exit code $($validationResult.ExitCode)"
}

if (-not $SkipVisibleCapture) {
    Invoke-Step -Name 'visible_review_capture' -Visible -Arguments @(
        '--path', $ProjectPath,
        'res://tools/v2_2/capture_review.tscn',
        '--', '--developer-mode'
    )
}

if (-not $SkipPerformanceCapture) {
    Invoke-Step -Name 'visible_performance_capture' -Visible -Arguments @(
        '--path', $ProjectPath,
        'res://tools/v2_2/perf_capture.tscn',
        '--', '--developer-mode'
    )
}

Write-Host ''
Write-Host '=== V2.2 local acceptance summary ===' -ForegroundColor Green
$Results | Format-Table -AutoSize

$failed = @($Results | Where-Object { $_.ExitCode -ne 0 })
if ($failed.Count -gt 0) {
    Write-Error "$($failed.Count) acceptance step(s) failed."
    exit 1
}

Write-Host ''
Write-Host 'Automated validation and capture steps returned exit code 0.' -ForegroundColor Yellow
Write-Host 'Manual UI, input, layout, and drag-feel review is still required.' -ForegroundColor Yellow
Write-Host "Review artifacts: $ProjectPath\artifacts\v2_2_life_loop_review" -ForegroundColor Yellow

if ($OpenManualReview) {
    Start-Process `
        -FilePath $GodotPath `
        -ArgumentList (Convert-ToArgumentString -Arguments @(
            '--path', $ProjectPath,
            'res://scenes/v2_2/v2_2_life_loop_main.tscn',
            '--', '--prototype-review', '--developer-mode'
        )) `
        -WorkingDirectory $ProjectPath
}

exit 0
