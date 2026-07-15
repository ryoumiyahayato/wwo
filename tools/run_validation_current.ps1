param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

# Compatibility entry retained for existing local commands. The canonical
# runner owns the suite so validation variants cannot silently diverge.
& (Join-Path $PSScriptRoot 'run_validation.ps1') `
    -GodotPath $GodotPath `
    -ProjectPath $ProjectPath
