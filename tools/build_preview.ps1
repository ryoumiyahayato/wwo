param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
$ErrorActionPreference = 'Stop'
$python = $env:WWO_PYTHON
if (-not $python) {
    $bundled = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (Test-Path -LiteralPath $bundled) { $python = $bundled }
    else { $python = (Get-Command python -ErrorAction Stop).Source }
}
& $python -X utf8 (Join-Path $PSScriptRoot 'build/preview.py') @Arguments
exit $LASTEXITCODE
