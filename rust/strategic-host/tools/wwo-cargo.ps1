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
    exit $code
} finally {
    $env:CARGO_TARGET_DIR = $previousTarget
    $env:WWO_DATA_DIR = $previousData
    $env:RUSTFLAGS = $previousRustFlags
    $env:CARGO_ENCODED_RUSTFLAGS = $previousEncodedRustFlags
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
