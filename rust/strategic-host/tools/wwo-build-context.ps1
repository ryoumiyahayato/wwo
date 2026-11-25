function Set-WwoBuildContext([string] $HostRoot, [string] $Target, [switch] $Validation) {
    $commit = & git -C $HostRoot rev-parse --verify HEAD
    if ($LASTEXITCODE) { throw 'Cannot identify the WWO build source commit.' }
    $changes = & git -C $HostRoot status --porcelain=v1 --untracked-files=normal
    if ($LASTEXITCODE) { throw 'Cannot identify modifications to the WWO build source.' }
    $dirty = if ($changes) { 'dirty' } else { 'clean' }
    $env:WWO_BUILD_SOURCE = "$commit|$dirty"
    if ($Validation) {
        $env:WWO_BUILD_ALLOCATION = 'validation'
        return
    }
    $env:WWO_BUILD_ALLOCATION = 'numbered'
    $env:WWO_BUILD_SHELL = (Get-Process -Id $PID).Path
    $env:WWO_BUILD_ALLOCATOR = Join-Path $HostRoot 'tools/allocate-wwo-build.ps1'
    $env:WWO_BUILD_RECEIPT = Join-Path $Target ('.wwo-build-' + [Guid]::NewGuid().ToString('N'))
    $source = Join-Path $HostRoot 'tools/wwo-build-rustc.rs'
    $wrapper = Join-Path $Target 'wwo-build-rustc.exe'
    if (!(Test-Path -LiteralPath $wrapper -PathType Leaf) -or
        (Get-Item -LiteralPath $wrapper).LastWriteTimeUtc -lt (Get-Item -LiteralPath $source).LastWriteTimeUtc) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        & rustc --edition=2021 -C debuginfo=0 $source -o $wrapper
        if ($LASTEXITCODE) { throw 'Cannot build the WWO compiler wrapper.' }
    }
    $env:RUSTC_WORKSPACE_WRAPPER = $wrapper
}
