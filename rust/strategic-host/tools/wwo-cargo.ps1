[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'build', 'test', 'run')]
    [string] $Command = 'check',

    [switch] $DebugSymbols,
    [switch] $Restart,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]] $CargoArguments
)

$ErrorActionPreference = 'Stop'
if ($Restart -and ($Command -ne 'build' -or $CargoArguments)) {
    throw 'Use wwo-cargo.ps1 build -Restart to build and restart the configured game.'
}
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

function Get-VolumeWrites([string] $Volume) {
    try {
        $counter = Get-CimInstance Win32_PerfRawData_PerfDisk_LogicalDisk -Filter "Name='$Volume'" -ErrorAction Stop
        if ($null -ne $counter.DiskWriteBytesPersec) {
            return [long] $counter.DiskWriteBytesPersec
        }
    } catch {
        Write-Verbose "Volume write counter unavailable: $_"
    }
}

function Write-BuildUsage([string] $Directory, [hashtable] $Usage) {
    try {
        $log = Join-Path $Directory 'wwo-build-usage.jsonl'
        if ((Test-Path -LiteralPath $log -PathType Leaf) -and
            ((Get-Item -LiteralPath $log).Length -ge 512KB)) {
            Move-Item -LiteralPath $log -Destination (Join-Path $Directory 'wwo-build-usage.previous.jsonl') -Force
        }
        Add-Content -LiteralPath $log -Encoding utf8 -Value ($Usage | ConvertTo-Json -Compress)
    } catch {
        Write-Warning "Could not record local Cargo build usage: $_"
    }
}

$profileDirectory = Join-Path $target.FullName $output
$retirementMarker = Join-Path $target.FullName ".wwo-$profile-retired"
$rearmAt = $budget - 1GB
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($target.FullName))
$volume = $drive.Name.TrimEnd('\')
$previousTarget = $env:CARGO_TARGET_DIR
$previousData = $env:WWO_DATA_DIR
$previousRustFlags = $env:RUSTFLAGS
$previousEncodedRustFlags = $env:CARGO_ENCODED_RUSTFLAGS
$buildEnvironment = @{}
foreach ($name in 'RUSTC_WORKSPACE_WRAPPER', 'WWO_BUILD_SOURCE', 'WWO_BUILD_ALLOCATION', 'WWO_BUILD_SHELL', 'WWO_BUILD_ALLOCATOR', 'WWO_BUILD_RECEIPT') {
    $buildEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
. (Join-Path $PSScriptRoot 'wwo-build-context.ps1')
if ($Restart) {
    . (Join-Path $PSScriptRoot 'update-wwo-program.ps1')
    $CargoArguments = @('--bin', 'wwo-map-lab')
}
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
    # rustc still requests an MSVC PDB with debug = 0.
    if (!$DebugSymbols) {
        $linkFlag = '-Clink-arg=/DEBUG:NONE'
        if ($previousEncodedRustFlags) {
            $env:CARGO_ENCODED_RUSTFLAGS = $previousEncodedRustFlags + [char]31 + $linkFlag
        } else {
            $env:RUSTFLAGS = "$previousRustFlags $linkFlag".Trim()
        }
    }
    $bytesBefore = Get-OutputBytes $profileDirectory
    $retired = Test-Path -LiteralPath $retirementMarker
    $retirement = 'none'
    if ($Command -ne 'run') {
        $freeBefore = $drive.AvailableFreeSpace
        $writesBefore = Get-VolumeWrites $volume
    }
    if ($bytesBefore -gt $budget -and !$retired) {
        $directory = Get-Item -LiteralPath $profileDirectory
        $expected = Join-Path $target.FullName $output
        if ($directory.FullName -ne $expected -or
            $directory.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint) -or
            (Get-ChildItem -LiteralPath $expected -Directory -Recurse -Attributes ReparsePoint)) {
            throw "Unexpected Cargo cache path: $profileDirectory"
        }
        $running = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -like "$expected\*" }
        if ($running) {
            $retirement = 'deferred-in-use'
            Write-Warning "Cargo $profile workspace cleanup deferred while its program is running."
        } else {
            Write-Host "Cargo $profile cache exceeded $budget bytes ($bytesBefore). Removing workspace outputs in this profile once."
            & cargo clean --workspace --offline --locked --manifest-path $manifest --profile $profile
            if ($LASTEXITCODE) { exit $LASTEXITCODE }
            Set-Content -LiteralPath $retirementMarker -Value ([DateTime]::UtcNow.ToString('o'))
            $retired = $true
            $retirement = 'workspace'
        }
    } elseif ($bytesBefore -gt $budget) {
        $retirement = 'already-retired'
    }

    Set-WwoBuildContext $hostRoot $target.FullName
    $buildReceipt = $env:WWO_BUILD_RECEIPT
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & cargo $Command --locked --manifest-path $manifest @profileArguments @CargoArguments
    $code = $LASTEXITCODE
    $timer.Stop()
    if ($Command -ne 'run') {
        $writesAfter = Get-VolumeWrites $volume
        $freeAfter = $drive.AvailableFreeSpace
        $writeBytes = $null
        if ($null -ne $writesBefore -and $null -ne $writesAfter -and $writesAfter -ge $writesBefore) {
            $writeBytes = $writesAfter - $writesBefore
        }
    }
    $bytesAfter = Get-OutputBytes $profileDirectory
    if ($retired -and $bytesAfter -le $rearmAt) {
        Remove-Item -LiteralPath $retirementMarker
    }
    if ($Command -ne 'run') {
        $commit = & git -C $worktree rev-parse --verify HEAD
        Write-BuildUsage $target.FullName @{
            utc = [DateTime]::UtcNow.ToString('o')
            commit = $commit
            build = if ([IO.File]::Exists($buildReceipt)) { [IO.File]::ReadAllText($buildReceipt) }
            command = $Command
            profile = $profile
            cargo_ms = $timer.ElapsedMilliseconds
            exit_code = $code
            workspace_retirement = $retirement
            profile_bytes_before = $bytesBefore
            profile_bytes_after = $bytesAfter
            volume = $volume
            volume_free_before = $freeBefore
            volume_free_after = $freeAfter
            volume_write_bytes = $writeBytes
        }
    }
    if ($bytesAfter -gt $budget) {
        Write-Warning "Cargo $profile cache is $bytesAfter bytes. Dependency outputs are retained. Automatic workspace cleanup rearms at $rearmAt bytes."
    }
    if ($Restart -and !$code) {
        # Child startup reads the unified configuration instead of Cargo's developer data setting.
        $env:WWO_DATA_DIR = $previousData
        Update-WwoProgram (Join-Path $profileDirectory 'wwo-map-lab.exe')
    }
    exit $code
} finally {
    $env:CARGO_TARGET_DIR = $previousTarget
    $env:WWO_DATA_DIR = $previousData
    $env:RUSTFLAGS = $previousRustFlags
    $env:CARGO_ENCODED_RUSTFLAGS = $previousEncodedRustFlags
    if ($buildReceipt -and [IO.File]::Exists($buildReceipt)) { [IO.File]::Delete($buildReceipt) }
    foreach ($name in $buildEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $buildEnvironment[$name])
    }
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
