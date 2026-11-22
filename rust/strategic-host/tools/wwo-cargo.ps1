[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'build', 'test', 'run')]
    [string] $Command = 'check',

    [switch] $DebugSymbols,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]] $CargoArguments
)

$ErrorActionPreference = 'Stop'
$hostRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$worktree = (Resolve-Path -LiteralPath (Join-Path $hostRoot '../..')).Path
$workspace = Split-Path -Parent $worktree
$formalWorktree = Join-Path $workspace 'wwo-population-foundation-v32'
if ($worktree -ne $formalWorktree) {
    throw "Run local builds from the fixed worktree: $formalWorktree"
}

$target = Get-Item -LiteralPath (Join-Path $workspace '.wwo-historical-population-v31-target')
if (!$target.PSIsContainer -or $target.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
    throw "The shared Cargo target must be an existing directory: $($target.FullName)"
}
foreach ($arg in $CargoArguments) {
    if ($arg -eq '--') { break }
    if ($arg -match '^(-r|--release|--profile|--target-dir|--manifest-path|--config|--target)(=|$)') {
        throw "The shared build command manages Cargo option $arg. Use -DebugSymbols for debugger builds."
    }
}

$manifest = Join-Path $hostRoot 'Cargo.toml'
$profile = 'dev'
$output = 'debug'
$budget = 10GB
$profileArguments = @()
if ($DebugSymbols) {
    $profile = 'dev-debug'
    $output = 'dev-debug'
    $budget = 6GB
    $profileArguments = @('--profile', $profile)
}

function Get-OutputBytes([string] $Path) {
    [long] $bytes = 0
    if (Test-Path -LiteralPath $Path -PathType Container) {
        foreach ($path in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            $bytes += [IO.FileInfo]::new($path).Length
        }
    }
    return $bytes
}

$profileDirectory = Join-Path $target.FullName $output
$previousTarget = $env:CARGO_TARGET_DIR
$previousData = $env:WWO_DATA_DIR
$lock = [Threading.Mutex]::new($false, 'Local\WWO-Shared-Cargo-v31')
$held = $false
try {
    try {
        $held = $lock.WaitOne()
    } catch [Threading.AbandonedMutexException] {
        $held = $true
    }
    $env:CARGO_TARGET_DIR = $target.FullName
    if (!$env:WWO_DATA_DIR) {
        $env:WWO_DATA_DIR = Join-Path $worktree 'data'
    }
    $bytes = Get-OutputBytes $profileDirectory
    if ($bytes -gt $budget) {
        $directory = Get-Item -LiteralPath $profileDirectory
        $expected = Join-Path $target.FullName $output
        if ($directory.FullName -ne $expected -or
            $directory.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) -or
            (Get-ChildItem -LiteralPath $expected -Directory -Recurse -Attributes ReparsePoint)) {
            throw "Unexpected Cargo cache path: $profileDirectory"
        }
        $running = Get-Process wwo-map-lab, wwo-formal-state -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -like "$expected\*" }
        if ($running) {
            throw "Close the development program in $expected before refreshing its Cargo profile."
        }
        Write-Host "Cargo $profile cache exceeded $budget bytes ($bytes). Removing project outputs in this profile."
        & cargo clean --workspace --offline --locked --manifest-path $manifest --profile $profile
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
        $bytes = Get-OutputBytes $profileDirectory
        if ($bytes -gt $budget) {
            Write-Host "The remaining $profile dependency cache is $bytes bytes. Refreshing this profile."
            & cargo clean --offline --locked --manifest-path $manifest --profile $profile
            if ($LASTEXITCODE) { exit $LASTEXITCODE }
        }
    }
    & cargo $Command --locked --manifest-path $manifest @profileArguments @CargoArguments
    $code = $LASTEXITCODE
    $bytes = Get-OutputBytes $profileDirectory
    if ($bytes -gt $budget) {
        Write-Warning "Cargo $profile cache is $bytes bytes. It will be refreshed before its next build."
    }
    exit $code
} finally {
    $env:CARGO_TARGET_DIR = $previousTarget
    $env:WWO_DATA_DIR = $previousData
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
