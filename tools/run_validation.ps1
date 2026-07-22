param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [int]$StepTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$expectedGodotVersion = '4.6.3.stable.official.7d41c59c4'

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
if ($StepTimeoutSeconds -lt 10) {
    throw 'StepTimeoutSeconds must be at least 10.'
}

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$parseErrorPattern = '(?im)(SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve class|Could not find type|Cannot get class|Invalid call|Invalid get index|Assertion failed|[1-9][0-9]* failures)'

function Invoke-GodotStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = $StepTimeoutSeconds
    )

    Write-Host "`n=== $Name ==="
    Write-Host "Timeout: $TimeoutSeconds seconds"
    $quotedArguments = @(
        $Arguments | ForEach-Object {
            '"' + $_.Replace('"', '\"') + '"'
        }
    ) -join ' '
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $GodotPath
    $startInfo.Arguments = $quotedArguments
    $startInfo.WorkingDirectory = $ProjectPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "$Name could not start"
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        $process.Kill()
    }
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $text = "$stdout$stderr"
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-Host $stdout.TrimEnd()
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Write-Host $stderr.TrimEnd()
    }

    if (-not $finished) {
        throw "$Name timed out after $TimeoutSeconds seconds; the Godot process was terminated"
    }
    if ($process.ExitCode -ne 0) {
        throw "$Name failed with exit code $($process.ExitCode)"
    }
    if ($text -match $parseErrorPattern) {
        throw "$Name emitted a script, assertion or nonzero test failure despite exit code 0"
    }
    return $text.Trim()
}

$actualGodotVersion = Invoke-GodotStep -Name 'Godot version' -Arguments @('--version') -TimeoutSeconds 30
if ($actualGodotVersion -ne $expectedGodotVersion) {
    throw "Godot version mismatch: expected $expectedGodotVersion, got $actualGodotVersion"
}

$null = Invoke-GodotStep -Name 'Clean import and script scan' -Arguments @(
    '--editor', '--headless', '--path', $ProjectPath, '--quit'
) -TimeoutSeconds 180

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
    @{ Name = 'V2.3 formal finance'; Script = 'res://tests/v2_3/v2_3_formal_finance_test.gd'; TimeoutSeconds = 60 },
    @{ Name = 'V2.3 formal leave and location'; Script = 'res://tests/v2_3/v2_3_formal_leave_location_test.gd'; TimeoutSeconds = 60 },
    @{ Name = 'V2.3 autonomous social sandbox'; Script = 'res://tests/v2_3/v2_3_social_sandbox_test.gd'; TimeoutSeconds = 220 },
    @{ Name = 'V2.3 completed social sandbox'; Script = 'res://tests/v2_3/v2_3_social_sandbox_completion_test.gd'; TimeoutSeconds = 120 },
    @{ Name = 'V2.3 survival autonomy'; Script = 'res://tests/v2_3/v2_3_survival_autonomy_test.gd'; TimeoutSeconds = 120 },
    @{ Name = 'V2.3 player interface'; Script = 'res://tests/v2_3/v2_3_player_interface_test.gd'; TimeoutSeconds = 120 },
    @{ Name = 'V2.3 UI binding'; Script = 'res://tests/v2_3/v2_3_ui_binding_test.gd' },
    @{ Name = 'V2.3 map integration'; Script = 'res://tests/v2_3/v2_3_map_integration_test.gd' },
    @{ Name = 'V2.3 performance guard'; Script = 'res://tests/v2_3/v2_3_performance_guard_test.gd'; TimeoutSeconds = 180 },
    @{ Name = 'V2.3 full loop smoke'; Script = 'res://tests/v2_3/v2_3_full_loop_smoke.gd' },
    @{ Name = 'Grid fixture world and topology'; Script = 'res://tests/alpha/alpha_world_topology_test.gd' },
    @{ Name = 'Grid fixture economy lifecycle'; Script = 'res://tests/alpha/alpha_economy_lifecycle_test.gd' },
    @{ Name = 'Grid fixture labor and enterprise'; Script = 'res://tests/alpha/alpha_labor_enterprise_test.gd' },
    @{ Name = 'Grid fixture character and development'; Script = 'res://tests/alpha/alpha_character_development_test.gd' },
    @{ Name = 'Grid fixture organization and politics'; Script = 'res://tests/alpha/alpha_organization_politics_test.gd' },
    @{ Name = 'Grid fixture composition smoke'; Script = 'res://tests/alpha/alpha_composition_smoke.gd' },
    @{ Name = 'Grid fixture quarantine and presets'; Script = 'res://tests/alpha/alpha_ui_and_presets_test.gd' },
    @{ Name = 'Grid fixture save and migration'; Script = 'res://tests/alpha/alpha_save_and_migration_test.gd' },
    @{ Name = 'Grid fixture cross-system scenarios'; Script = 'res://tests/alpha/alpha_cross_system_scenarios_test.gd' },
    @{ Name = 'Grid fixture three-year performance'; Script = 'res://tests/alpha/alpha_three_year_performance_test.gd'; TimeoutSeconds = 220 }
)

foreach ($test in $tests) {
    $timeout = if ($test.ContainsKey('TimeoutSeconds')) {
        [int]$test.TimeoutSeconds
    }
    else {
        $StepTimeoutSeconds
    }
    $null = Invoke-GodotStep -Name $test.Name -Arguments @(
        '--headless', '--path', $ProjectPath, '--script', $test.Script
    ) -TimeoutSeconds $timeout
}

$null = Invoke-GodotStep -Name 'Headless project startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
) -TimeoutSeconds 30

Write-Host "`nAll current life simulation, formal world, player-surface and quarantined fixture validation steps passed."
