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

$tests = @(
	@{ Name = 'Formal personal economy and wages'; Script = 'res://tests/formal/formal_personal_economy_test.gd'; TimeoutSeconds = 240 }
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

$null = Invoke-GodotStep -Name 'Headless formal product startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
) -TimeoutSeconds 30

Write-Host "`nFormal hemisphere world and long-term balance validation passed."
