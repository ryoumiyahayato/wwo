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
$ExpectedGodotVersionPrefix = '4.6.3.stable.official.7d41c59c4'

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label 不存在：$Path"
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Visible
    )

    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $started = Get-Date

    if ($Visible) {
        $process = Start-Process -FilePath $GodotPath -ArgumentList $Arguments -Wait -PassThru
        $exitCode = $process.ExitCode
    }
    else {
        & $GodotPath @Arguments
        $exitCode = $LASTEXITCODE
    }

    $elapsed = (Get-Date) - $started
    $script:Results += [pscustomobject]@{
        Name = $Name
        ExitCode = $exitCode
        Seconds = [math]::Round($elapsed.TotalSeconds, 2)
    }

    if ($exitCode -ne 0 -and -not $ContinueOnFailure) {
        throw "$Name 失败，退出码：$exitCode"
    }
}

Assert-PathExists -Path $GodotPath -Label 'Godot 可执行文件'
Assert-PathExists -Path $ProjectPath -Label '项目目录'
Assert-PathExists -Path (Join-Path $ProjectPath 'project.godot') -Label 'project.godot'
Assert-PathExists -Path (Join-Path $ProjectPath 'tools\v2_2\capture_review.tscn') -Label 'V2.2 可见评审场景'
Assert-PathExists -Path (Join-Path $ProjectPath 'tools\v2_2\perf_capture.tscn') -Label 'V2.2 性能采集场景'

$versionOutput = (& $GodotPath --version 2>&1 | Out-String).Trim()
if (-not $versionOutput.StartsWith($ExpectedGodotVersionPrefix)) {
    throw "Godot 版本不匹配。需要 $ExpectedGodotVersionPrefix，实际为：$versionOutput"
}
Write-Host "Godot：$versionOutput" -ForegroundColor DarkGray

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

Write-Host ""
Write-Host '=== run_validation.ps1 ===' -ForegroundColor Cyan
$validationStarted = Get-Date
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectPath 'tools\run_validation.ps1')
$validationExit = $LASTEXITCODE
$Results += [pscustomobject]@{
    Name = 'run_validation.ps1'
    ExitCode = $validationExit
    Seconds = [math]::Round(((Get-Date) - $validationStarted).TotalSeconds, 2)
}
if ($validationExit -ne 0 -and -not $ContinueOnFailure) {
    throw "统一验证失败，退出码：$validationExit"
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

Write-Host ""
Write-Host '=== V2.2 本地验收汇总 ===' -ForegroundColor Green
$Results | Format-Table -AutoSize

$failed = @($Results | Where-Object { $_.ExitCode -ne 0 })
if ($failed.Count -gt 0) {
    Write-Error "共有 $($failed.Count) 个步骤失败。"
    exit 1
}

Write-Host ""
Write-Host '自动化与采集步骤全部返回 0。仍需人工检查界面、交互和实际拖动手感。' -ForegroundColor Yellow
Write-Host "评审产物目录：$ProjectPath\artifacts\v2_2_life_loop_review" -ForegroundColor Yellow

if ($OpenManualReview) {
    Start-Process -FilePath $GodotPath -ArgumentList @(
        '--path', $ProjectPath,
        'res://scenes/v2_2/v2_2_life_loop_main.tscn',
        '--', '--prototype-review', '--developer-mode'
    )
}

exit 0
