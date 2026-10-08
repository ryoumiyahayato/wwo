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
# Engine failures are fatal in every phase, even when Godot exits with 0.
$engineErrorPattern = '(?im)(SCRIPT ERROR|Parse Error|Failed to load|Failed loading resource|Cannot load resource|Error loading resource|No loader found|Cannot instantiate script|Failed to instantiate|Could not resolve class|Could not find type|Cannot get class|Invalid call|Invalid get index|Assertion failed|Loaded resource as image file, this will not work on export|Resource file not found)'
$nonTestErrorPattern = '(?im)(^ERROR:(?!\s+\d+\s+resources still in use at exit\b)|\b[1-9][0-9]*\s+failures?\b)'
$testSummaryPattern = '(?im)^.*?:\s*(\d+)\s+checks,\s*(\d+)\s+failures\s*$'

function Invoke-GodotStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = $StepTimeoutSeconds,
        [switch]$TestRunner
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
    if ($text -match $engineErrorPattern) {
        throw "$Name emitted an engine parse, script or resource loading error despite exit code 0"
    }
    if ($TestRunner) {
        # Negative tests retain push_error output. The runner, rather than a
        # business-error allowlist, decides whether that rejection was expected.
        $summaries = [regex]::Matches($stdout, $testSummaryPattern)
        if ($summaries.Count -eq 0) {
            throw "$Name did not emit a test summary despite exit code 0"
        }
        foreach ($summary in $summaries) {
            if ([long]$summary.Groups[2].Value -gt 0) {
                throw "$Name reported $($summary.Groups[2].Value) test failures despite exit code 0"
            }
        }
        $finalSummary = $summaries[$summaries.Count - 1]
        if ([long]$finalSummary.Groups[1].Value -le 0) {
            throw "$Name reported no checks despite exit code 0"
        }
        Write-Host "PASS: $Name ($($finalSummary.Groups[1].Value) checks, 0 failures)"
    }
    elseif ($text -match $nonTestErrorPattern) {
        throw "$Name emitted an error despite exit code 0"
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
	@{ Name = 'Formal personal economy and wages'; Script = 'res://tests/formal/formal_personal_economy_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal livelihood player journeys'; Script = 'res://tests/formal/formal_livelihood_journey_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal application and main/menu'; Script = 'res://tests/formal/formal_application_architecture_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal Person integration'; Script = 'res://tests/formal/formal_person_overlay_integration_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal Spatial integration'; Script = 'res://tests/formal/formal_spatial_authority_integration_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal exact persistence'; Script = 'res://tests/formal/formal_exact_persistence_roundtrip_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal Population production integration'; Script = 'res://tests/formal/formal_population_integration_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Presentation content boundary'; Script = 'res://tests/formal/presentation_content_boundary_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Administrative foundation R1 (identity + independent synthetic fixture)'; Script = 'res://tests/formal/formal_administrative_foundation_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal map rendering regression'; Script = 'res://tests/formal/formal_map_rendering_regression_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal map scale transition'; Script = 'res://tests/formal/formal_map_scale_transition_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal map Local foundation'; Script = 'res://tests/formal/formal_map_local_foundation_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Paris Local Content R1'; Script = 'res://tests/formal/formal_paris_local_content_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Map visual scale utilization R1'; Script = 'res://tests/formal/formal_map_scale_utilization_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Map resource efficiency R2'; Script = 'res://tests/formal/formal_map_resource_efficiency_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Global physical relief R1'; Script = 'res://tests/formal/formal_global_physical_relief_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Global strategic geography R1'; Script = 'res://tests/formal/formal_global_strategic_geography_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Historical provenance foundation'; Script = 'res://tests/formal/historical_provenance_foundation_test.gd'; TimeoutSeconds = 180 },
	@{ Name = 'Runtime political identity foundation'; Script = 'res://tests/formal/runtime_political_identity_foundation_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal economy 30-day and one-year golden'; Script = 'res://tests/formal/formal_world_economy_golden_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal economic boundary closure'; Script = 'res://tests/formal/formal_world_economic_boundary_closure_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Formal market identity foundation'; Script = 'res://tests/formal/formal_world_market_identity_foundation_test.gd'; TimeoutSeconds = 240 },
	@{ Name = 'Organization state'; Script = 'res://tests/world/organization_state_test.gd'; TimeoutSeconds = 180 },
	@{ Name = 'Formal organization composition'; Script = 'res://tests/formal/formal_world_organization_composition_test.gd'; TimeoutSeconds = 360 },
	@{ Name = 'Current world domain convergence'; Script = 'res://tests/vnext/current_world_domain_convergence_test.gd'; TimeoutSeconds = 180 },
	@{ Name = 'Formal Windows export resource contract'; Script = 'res://tests/formal/formal_world_export_resource_smoke.gd'; TimeoutSeconds = 180 },
    @{ Name = 'Formal world integration'; Script = 'res://tests/formal/formal_world_integration_test.gd'; TimeoutSeconds = 360 },
    @{ Name = 'Formal world ten-year balance'; Script = 'res://tests/formal/formal_world_long_term_balance_test.gd'; TimeoutSeconds = 420 },
    @{ Name = 'Historical world economy data'; Script = 'res://tests/alpha/alpha_historical_world_economy_data_test.gd'; TimeoutSeconds = 120 }

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
    ) -TimeoutSeconds $timeout -TestRunner
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

$formalFingerprintProbeArguments = @(
    '--headless', '--path', $ProjectPath,
    '--script', 'res://tests/formal/formal_world_fingerprint_probe.gd'
)
$formalFingerprintProbeOne = Invoke-GodotStep -Name 'Formal world fingerprint fresh-process A' -Arguments $formalFingerprintProbeArguments -TimeoutSeconds 180
$formalFingerprintProbeTwo = Invoke-GodotStep -Name 'Formal world fingerprint fresh-process B' -Arguments $formalFingerprintProbeArguments -TimeoutSeconds 180
$formalFingerprintPattern = '(?m)^FORMAL_WORLD_FINGERPRINT_SHA256=([0-9a-f]{64})$'
if ($formalFingerprintProbeOne -notmatch $formalFingerprintPattern) {
    throw 'Formal world fingerprint probe A did not emit a canonical hash'
}
$formalFingerprintOne = $Matches[1]
if ($formalFingerprintProbeTwo -notmatch $formalFingerprintPattern) {
    throw 'Formal world fingerprint probe B did not emit a canonical hash'
}
$formalFingerprintTwo = $Matches[1]
if ($formalFingerprintOne -ne $formalFingerprintTwo) {
    throw "Formal world fingerprint differs across fresh processes: $formalFingerprintOne != $formalFingerprintTwo"
}
Write-Host "Formal world fresh-process deterministic fingerprint: $formalFingerprintOne"

$null = Invoke-GodotStep -Name 'Headless formal product startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
) -TimeoutSeconds 30

Write-Host "`nFormal hemisphere world and long-term balance validation passed."
