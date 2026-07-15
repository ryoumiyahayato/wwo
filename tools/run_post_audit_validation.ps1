param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

# Compatibility entry retained for the remediation document. The canonical
# runner owns the suite so post-audit validation cannot omit later checks.
& (Join-Path $PSScriptRoot 'run_validation.ps1') `
    -GodotPath $GodotPath `
    -ProjectPath $ProjectPath
