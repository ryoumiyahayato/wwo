param(
    [string]$GodotExe = 'D:/tools/Godot-4.6.3/Godot_v4.6.3-stable_win64_console.exe',
    [string]$PythonExe = '',
    [int]$Port = 8791,
    [switch]$Background
)
$ErrorActionPreference = 'Stop'
if (-not $PythonExe) {
    $bundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (Test-Path -LiteralPath $bundledPython) { $PythonExe = $bundledPython }
    else { $PythonExe = (Get-Command python -ErrorAction Stop).Source }
}
if (-not (Test-Path -LiteralPath $GodotExe)) { throw '请用 -GodotExe 指定Godot 4.6.3标准版。' }
$previewArguments = @('-X', 'utf8', (Join-Path $PSScriptRoot 'preview.py'), '--godot', $GodotExe, '--port', $Port)
if ($Background) { $previewArguments += '--background' }
& $PythonExe @previewArguments
exit $LASTEXITCODE
