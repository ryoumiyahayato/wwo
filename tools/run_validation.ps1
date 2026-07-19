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
    @{ Name = 'V2.2.1 polish'; Script = 'res://tests/v2_2/v2_2_polish_test.gd' },
    @{ Name = 'V2.2 performance and cleanup guard'; Script = 'res://tests/v2_2/v2_2_performance_guard_test.gd' },
    @{ Name = 'V2.3 locations'; Script = 'res://tests/v2_3/v2_3_location_test.gd' },
    @{ Name = 'V2.3 route planner'; Script = 'res://tests/v2_3/v2_3_route_planner_test.gd' },
    @{ Name = 'V2.3 travel execution'; Script = 'res://tests/v2_3/v2_3_travel_execution_test.gd' },
    @{ Name = 'V2.3 schedule integration'; Script = 'res://tests/v2_3/v2_3_schedule_integration_test.gd' },
    @{ Name = 'V2.3 communication'; Script = 'res://tests/v2_3/v2_3_communication_test.gd' },
    @{ Name = 'V2.3 knowledge'; Script = 'res://tests/v2_3/v2_3_knowledge_test.gd' },
    @{ Name = 'V2.3 relationships'; Script = 'res://tests/v2_3/v2_3_relationship_test.gd' },
    @{ Name = 'V2.3 appointments'; Script = 'res://tests/v2_3/v2_3_appointment_test.gd' },
    @{ Name = 'V2.3 NPC spatial routine'; Script = 'res://tests/v2_3/v2_3_npc_test.gd' },
    @{ Name = 'V2.3 save migration'; Script = 'res://tests/v2_3/v2_3_save_migration_test.gd' },
    @{ Name = 'V2.3 save load'; Script = 'res://tests/v2_3/v2_3_save_load_test.gd' },
    @{ Name = 'V2.3 determinism'; Script = 'res://tests/v2_3/v2_3_determinism_test.gd' },
    @{ Name = 'V2.3 UI binding'; Script = 'res://tests/v2_3/v2_3_ui_binding_test.gd' },
    @{ Name = 'V2.3 map integration'; Script = 'res://tests/v2_3/v2_3_map_integration_test.gd' },
    @{ Name = 'V2.3 performance guard'; Script = 'res://tests/v2_3/v2_3_performance_guard_test.gd' },
    @{ Name = 'V2.3 full loop smoke'; Script = 'res://tests/v2_3/v2_3_full_loop_smoke.gd' },
    @{ Name = 'Alpha world and topology'; Script = 'res://tests/alpha/alpha_world_topology_test.gd' },
    @{ Name = 'Alpha economy lifecycle'; Script = 'res://tests/alpha/alpha_economy_lifecycle_test.gd' },
    @{ Name = 'Alpha labor and enterprise'; Script = 'res://tests/alpha/alpha_labor_enterprise_test.gd' }
)

foreach ($test in $tests) {
    $null = Invoke-GodotStep -Name $test.Name -Arguments @(
        '--headless', '--path', $ProjectPath, '--script', $test.Script
    )
}

$null = Invoke-GodotStep -Name 'Headless project startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
)

Write-Host "`nAll current V2.2, V2.3 and Alpha validation steps passed without parse/load errors."
