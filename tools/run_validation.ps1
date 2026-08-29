param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath = '',
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

if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) {
        $PythonPath = $pythonCommand.Source
    }
    if ([string]::IsNullOrWhiteSpace($PythonPath) -or $PythonPath -like '*\WindowsApps\python.exe') {
        $bundledPython = Join-Path $env:APPDATA 'uv\python\cpython-3.10.20-windows-x86_64-none\python.exe'
        if (Test-Path -LiteralPath $bundledPython -PathType Leaf) {
            $PythonPath = $bundledPython
        }
    }
}
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw "Python executable not found: $PythonPath"
}

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$parseErrorPattern = '(?im)(^ERROR:(?!\s+\d+\s+resources still in use at exit\b)|SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve class|Could not find type|Cannot get class|Invalid call|Invalid get index|Assertion failed|Loaded resource as image file, this will not work on export|Failed loading resource|Resource file not found|[1-9][0-9]* failures)'

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
& $PythonPath "$ProjectPath/tools/audit_1900_commodity_economy.py"
if ($LASTEXITCODE -ne 0) { throw 'Commodity economy static audit failed' }
& $PythonPath "$ProjectPath/tools/audit_1900_economy_integration.py"
if ($LASTEXITCODE -ne 0) { throw 'Economy integration static audit failed' }
& $PythonPath "$ProjectPath/tools/audit_1900_world_economy_compact.py"
if ($LASTEXITCODE -ne 0) { throw 'Historical world economy static audit failed' }

Write-Host "`n=== Historical provenance deterministic generation ==="
& $PythonPath "$ProjectPath/tools/provenance/generate_historical_provenance.py" --check
if ($LASTEXITCODE -ne 0) { throw 'Historical provenance generated catalog check failed' }

Write-Host "`n=== World data audit regressions ==="
& $PythonPath -m unittest discover -s "$ProjectPath/tests/world_data" -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) { throw 'World data audit regression suite failed' }

$tests = @(
	@{ Name = 'Historical provenance foundation'; Script = 'res://tests/formal/historical_provenance_foundation_test.gd'; TimeoutSeconds = 180 },
	@{ Name = 'Runtime political identity foundation'; Script = 'res://tests/formal/runtime_political_identity_foundation_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal economy 30-day and one-year golden'; Script = 'res://tests/formal/formal_world_economy_golden_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal economic boundary closure'; Script = 'res://tests/formal/formal_world_economic_boundary_closure_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal market identity foundation'; Script = 'res://tests/formal/formal_world_market_identity_foundation_test.gd'; TimeoutSeconds = 240 },
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

$politicalProbeArguments = @(
    '--headless', '--path', $ProjectPath,
    '--script', 'res://tests/formal/runtime_political_snapshot_probe.gd'
)
$politicalProbeOne = Invoke-GodotStep -Name 'Runtime political fresh-process hash A' -Arguments $politicalProbeArguments -TimeoutSeconds 120
$politicalProbeTwo = Invoke-GodotStep -Name 'Runtime political fresh-process hash B' -Arguments $politicalProbeArguments -TimeoutSeconds 120
$politicalHashPattern = '(?m)^RUNTIME_POLITICAL_SNAPSHOT_SHA256=([0-9a-f]{64})$'
if ($politicalProbeOne -notmatch $politicalHashPattern) {
    throw 'Runtime political snapshot probe A did not emit a canonical hash'
}
$politicalHashOne = $Matches[1]
if ($politicalProbeTwo -notmatch $politicalHashPattern) {
    throw 'Runtime political snapshot probe B did not emit a canonical hash'
}
$politicalHashTwo = $Matches[1]
if ($politicalHashOne -ne $politicalHashTwo) {
    throw "Runtime political snapshot differs across fresh processes: $politicalHashOne != $politicalHashTwo"
}
Write-Host "Runtime political fresh-process deterministic hash: $politicalHashOne"

$marketProbeArguments = @(
    '--headless', '--path', $ProjectPath,
    '--script', 'res://tests/formal/formal_world_market_snapshot_probe.gd'
)
$marketProbeOne = Invoke-GodotStep -Name 'Formal market fresh-process hash A' -Arguments $marketProbeArguments -TimeoutSeconds 120
$marketProbeTwo = Invoke-GodotStep -Name 'Formal market fresh-process hash B' -Arguments $marketProbeArguments -TimeoutSeconds 120
$marketHashPattern = '(?m)^FORMAL_MARKET_SNAPSHOT_SHA256=([0-9a-f]{64})$'
if ($marketProbeOne -notmatch $marketHashPattern) {
    throw 'Formal market snapshot probe A did not emit a canonical hash'
}
$marketHashOne = $Matches[1]
if ($marketProbeTwo -notmatch $marketHashPattern) {
    throw 'Formal market snapshot probe B did not emit a canonical hash'
}
$marketHashTwo = $Matches[1]
if ($marketHashOne -ne $marketHashTwo) {
    throw "Formal market snapshot differs across fresh processes: $marketHashOne != $marketHashTwo"
}
Write-Host "Formal market fresh-process deterministic hash: $marketHashOne"

$economicProbeArguments = @(
    '--headless', '--path', $ProjectPath,
    '--script', 'res://tests/formal/formal_world_economic_snapshot_probe.gd'
)
$economicProbeOne = Invoke-GodotStep -Name 'Formal economic fresh-process hash A' -Arguments $economicProbeArguments -TimeoutSeconds 180
$economicProbeTwo = Invoke-GodotStep -Name 'Formal economic fresh-process hash B' -Arguments $economicProbeArguments -TimeoutSeconds 180
$economicHashPattern = '(?m)^FORMAL_ECONOMIC_SNAPSHOT_SHA256=([0-9a-f]{64})$'
if ($economicProbeOne -notmatch $economicHashPattern) {
    throw 'Formal economic snapshot probe A did not emit a canonical hash'
}
$economicHashOne = $Matches[1]
if ($economicProbeTwo -notmatch $economicHashPattern) {
    throw 'Formal economic snapshot probe B did not emit a canonical hash'
}
$economicHashTwo = $Matches[1]
if ($economicHashOne -ne $economicHashTwo) {
    throw "Formal economic snapshot differs across fresh processes: $economicHashOne != $economicHashTwo"
}
Write-Host "Formal economic fresh-process deterministic hash: $economicHashOne"

$null = Invoke-GodotStep -Name 'Headless formal product startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
) -TimeoutSeconds 30

Write-Host "`nFormal hemisphere world, long-term balance and retained service validation passed."
