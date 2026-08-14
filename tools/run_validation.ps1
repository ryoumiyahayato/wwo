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
$parseErrorPattern = '(?im)(^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve class|Could not find type|Cannot get class|Invalid call|Invalid get index|Assertion failed|Loaded resource as image file, this will not work on export|Failed loading resource|Resource file not found|[1-9][0-9]* failures)'

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

Write-Host "`n=== 1900 economy static audits ==="
& python "$ProjectPath/tools/audit_1900_commodity_economy.py"
if ($LASTEXITCODE -ne 0) { throw 'Commodity economy static audit failed' }
& python "$ProjectPath/tools/audit_1900_economy_integration.py"
if ($LASTEXITCODE -ne 0) { throw 'Economy integration static audit failed' }
& python "$ProjectPath/tools/audit_1900_world_economy_compact.py"
if ($LASTEXITCODE -ne 0) { throw 'Historical world economy static audit failed' }

Write-Host "`n=== World data audit regressions ==="
& python -m unittest discover -s "$ProjectPath/tests/world_data" -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) { throw 'World data audit regression suite failed' }

$tests = @(
	@{ Name = 'Formal player release journey'; Script = 'res://tests/formal/formal_world_player_journey_smoke.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal Windows export resource contract'; Script = 'res://tests/formal/formal_world_export_resource_smoke.gd'; TimeoutSeconds = 180 },
    @{ Name = 'Formal world integration'; Script = 'res://tests/formal/formal_world_integration_test.gd'; TimeoutSeconds = 360 },
    @{ Name = 'Formal world ten-year balance'; Script = 'res://tests/formal/formal_world_long_term_balance_test.gd'; TimeoutSeconds = 420 },
    @{ Name = 'Formal hemisphere product surface'; Script = 'res://tests/v2_3/v2_3_player_interface_test.gd'; TimeoutSeconds = 180 },
    @{ Name = 'Historical world economy data'; Script = 'res://tests/alpha/alpha_historical_world_economy_data_test.gd'; TimeoutSeconds = 120 },

    # Retained person/social service regressions. These do not own a map or a
    # product entry and may later be composed under the formal hemisphere.
    @{ Name = 'Retained location service'; Script = 'res://tests/v2_3/v2_3_location_test.gd' },
    @{ Name = 'Retained route planner service'; Script = 'res://tests/v2_3/v2_3_route_planner_test.gd' },
    @{ Name = 'Retained travel execution service'; Script = 'res://tests/v2_3/v2_3_travel_execution_test.gd' },
    @{ Name = 'Retained schedule integration'; Script = 'res://tests/v2_3/v2_3_schedule_integration_test.gd' },
    @{ Name = 'Retained communication service'; Script = 'res://tests/v2_3/v2_3_communication_test.gd' },
    @{ Name = 'Retained knowledge service'; Script = 'res://tests/v2_3/v2_3_knowledge_test.gd' },
    @{ Name = 'Retained relationship service'; Script = 'res://tests/v2_3/v2_3_relationship_test.gd' },
    @{ Name = 'Retained appointment service'; Script = 'res://tests/v2_3/v2_3_appointment_test.gd' },
    @{ Name = 'Retained NPC spatial routine'; Script = 'res://tests/v2_3/v2_3_npc_test.gd' },
    @{ Name = 'Retained social sandbox'; Script = 'res://tests/v2_3/v2_3_social_sandbox_test.gd'; TimeoutSeconds = 220 },
    @{ Name = 'Retained social completion'; Script = 'res://tests/v2_3/v2_3_social_sandbox_completion_test.gd'; TimeoutSeconds = 120 },
    @{ Name = 'Retained survival autonomy'; Script = 'res://tests/v2_3/v2_3_survival_autonomy_test.gd'; TimeoutSeconds = 120 },

    # The fictional two-country/eight-region data remains quarantined only for
    # low-level ledger, enterprise and migration regression. It is not a world,
    # map, product entry or balance authority.
    @{ Name = 'Quarantined commodity fixture'; Script = 'res://tests/alpha/alpha_commodity_market_test.gd'; TimeoutSeconds = 180 },
    @{ Name = 'Quarantined economy lifecycle fixture'; Script = 'res://tests/alpha/alpha_economy_lifecycle_test.gd' },
    @{ Name = 'Quarantined labor-enterprise fixture'; Script = 'res://tests/alpha/alpha_labor_enterprise_test.gd' },
    @{ Name = 'Quarantined unified economy fixture'; Script = 'res://tests/alpha/alpha_economy_integration_phase2_test.gd'; TimeoutSeconds = 300 },
    @{ Name = 'Quarantined AI economy fixture'; Script = 'res://tests/alpha/alpha_ai_economy_stability_test.gd'; TimeoutSeconds = 360 },
    @{ Name = 'Quarantined Alpha save-restore equivalence'; Script = 'res://tests/alpha/alpha_state_equivalence_test.gd'; TimeoutSeconds = 120 },
    @{ Name = 'Quarantined save-migration fixture'; Script = 'res://tests/alpha/alpha_save_and_migration_test.gd' }
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

$null = Invoke-GodotStep -Name 'Headless formal product startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
) -TimeoutSeconds 30

Write-Host "`nFormal hemisphere world, long-term balance and retained service validation passed."
