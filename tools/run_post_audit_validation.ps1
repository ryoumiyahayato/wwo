param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

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
    $lines = & $GodotPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($lines | Out-String)
    $lines | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode"
    }
    if ($text -match $parseErrorPattern) {
        throw "$Name emitted a script parse/load error despite exit code 0"
    }
}

# A clean checkout may not have Godot's global class cache. Import once before
# standalone --script tests, then treat parse/load log entries as hard failures.
Invoke-GodotStep -Name 'Clean import and script scan' -Arguments @(
    '--editor', '--headless', '--path', $ProjectPath, '--quit'
)

$tests = @(
    @{ Name = 'Current M0-M9 regression'; Script = 'res://tests/current_test_runner.gd' },
    @{ Name = 'P0-R1 logic regression'; Script = 'res://tests/p0_r1_logic_regression.gd' },
    @{ Name = 'Post-audit player journey'; Script = 'res://tests/p0_r1_player_journey_post_audit.gd' },
    @{ Name = 'P0-R1 safety regression'; Script = 'res://tests/p0_r1_safety_regression.gd' },
    @{ Name = 'State consistency regression'; Script = 'res://tests/state_consistency_regression.gd' },
    @{ Name = 'Simulation quality regression'; Script = 'res://tests/simulation_quality_regression.gd' },
    @{ Name = 'Codex audit regression'; Script = 'res://tests/codex_audit_regression.gd' }
)

foreach ($test in $tests) {
    Invoke-GodotStep -Name $test.Name -Arguments @(
        '--headless', '--path', $ProjectPath, '--script', $test.Script
    )
}

Invoke-GodotStep -Name 'Headless project startup' -Arguments @(
    '--headless', '--path', $ProjectPath, '--quit-after', '5'
)

Write-Host "`nAll post-audit validation steps passed without parse/load errors."
