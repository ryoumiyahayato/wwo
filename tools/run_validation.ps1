param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$expectedGodotVersion = '4.6.3.stable.official.7d41c59c4'

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$parseErrorPattern = '(?im)(SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve class|Could not find type|Cannot get class)'

function Invoke-GodotStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Host "`n=== $Name ==="
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $quotedArguments = @(
            $Arguments | ForEach-Object {
                '"' + $_.Replace('"', '\"') + '"'
            }
        ) -join ' '
        $process = Start-Process `
            -FilePath $GodotPath `
            -ArgumentList $quotedArguments `
            -WorkingDirectory $ProjectPath `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath
        $lines = @(
            Get-Content -LiteralPath $stdoutPath -Encoding UTF8 -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $stderrPath -Encoding UTF8 -ErrorAction SilentlyContinue
        )
        $text = ($lines | Out-String)
        $lines | ForEach-Object { Write-Host $_ }

        if ($process.ExitCode -ne 0) {
            throw "$Name failed with exit code $($process.ExitCode)"
        }
        if ($text -match $parseErrorPattern) {
            throw "$Name emitted a script parse/load error despite exit code 0"
        }
        return $text.Trim()
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

$actualGodotVersion = Invoke-GodotStep -Name 'Godot version' -Arguments @('--version')
if ($actualGodotVersion -ne $expectedGodotVersion) {
    throw "Godot version mismatch: expected $expectedGodotVersion, got $actualGodotVersion"
}

$null = Invoke-GodotStep -Name 'Clean import and script scan' -Arguments @(
    '--editor', '--headless', '--path', $ProjectPath, '--quit'
)

$tests = @(
    @{ Name = 'Current M0-M9 regression'; Script = 'res://tests/current_test_runner.gd' },
    @{ Name = 'P0-R1 logic regression'; Script = 'res://tests/p0_r1_logic_regression.gd' },
    @{ Name = 'Post-audit player journey'; Script = 'res://tests/p0_r1_player_journey_post_audit.gd' },
    @{ Name = 'P0-R1 safety regression'; Script = 'res://tests/p0_r1_safety_regression.gd' },
    @{ Name = 'State consistency regression'; Script = 'res://tests/state_consistency_regression.gd' },
    @{ Name = 'Simulation quality regression'; Script = 'res://tests/simulation_quality_regression.gd' },
    @{ Name = 'Codex audit regression'; Script = 'res://tests/codex_audit_regression.gd' },
    @{ Name = '1000-seed early-game reachability'; Script = 'res://tests/early_game_reachability_regression.gd' },
    @{ Name = 'V2.2 config and datetime'; Script = 'res://tests/v2_2/v2_2_config_datetime_test.gd' },
    @{ Name = 'V2.2 atomicity'; Script = 'res://tests/v2_2/v2_2_atomicity_test.gd' },
    @{ Name = 'V2.2 life-loop smoke'; Script = 'res://tests/v2_2/v2_2_life_loop_smoke.gd' },
    @{ Name = 'V2.2 time'; Script = 'res://tests/v2_2/v2_2_time_test.gd' },
    @{ Name = 'V2.2 schedule'; Script = 'res://tests/v2_2/v2_2_schedule_test.gd' },
    @{ Name = 'V2.2 employment'; Script = 'res://tests/v2_2/v2_2_employment_test.gd' },
    @{ Name = 'V2.2 household'; Script = 'res://tests/v2_2/v2_2_household_test.gd' },
    @{ Name = 'V2.2 condition'; Script = 'res://tests/v2_2/v2_2_condition_test.gd' },
    @{ Name = 'V2.2 notification'; Script = 'res://tests/v2_2/v2_2_notification_test.gd' },
    @{ Name = 'V2.2 save/load'; Script = 'res://tests/v2_2/v2_2_save_load_test.gd' },
    @{ Name = 'V2.2 determinism'; Script = 'res://tests/v2_2/v2_2_determinism_test.gd' },
    @{ Name = 'V2.2 UI binding'; Script = 'res://tests/v2_2/v2_2_ui_binding_test.gd' },
    @{ Name = 'V2.2 performance guard'; Script = 'res://tests/v2_2/v2_2_performance_guard_test.gd' }
)

foreach ($test in $tests) {
    $null = Invoke-GodotStep -Name $test.Name -Arguments @(
        '--headless', '--path', $ProjectPath, '--script', $test.Script
    )
}

$null = Invoke-GodotStep -Name 'Headless project startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
)

Write-Host "`nAll validation steps passed without parse/load errors."
