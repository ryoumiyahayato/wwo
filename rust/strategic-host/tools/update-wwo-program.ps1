function Update-WwoProgram([string] $Build) {
    $configPath = Join-Path $env:LOCALAPPDATA 'WWO-Rust-Candidate/runtime.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (![IO.Path]::IsPathRooted($config.program_directory)) {
        throw "Set an absolute program_directory in $configPath."
    }
    $directory = Get-Item -LiteralPath $config.program_directory
    if (!$directory.PSIsContainer) { throw 'The formal program directory must be a directory.' }
    $exe = Join-Path $directory.FullName 'wwo-map-lab.exe'
    if ($exe -eq [IO.Path]::GetFullPath($Build)) { throw 'Place the formal program outside Cargo output.' }

    $version = (& $Build --version | Out-String).Trim()
    if ($LASTEXITCODE -or $version -notmatch '^wwo-map-lab .+ Build [1-9][0-9]*$') {
        throw 'The completed build has no numbered program.'
    }
    $profile = if ($env:WWO_RUST_PROFILE) { $env:WWO_RUST_PROFILE } else { 'Default' }
    if ($profile -notmatch '^[A-Za-z0-9_-]{1,40}$') { throw 'Invalid WWO_RUST_PROFILE.' }
    $save = Join-Path (Split-Path -Parent $configPath) "profiles/$profile/formal-world/formal_world_1900_auto.json"
    $savedBefore = [IO.File]::GetLastWriteTimeUtc($save)
    $running = @(Get-Process -Name 'wwo-map-lab' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
    foreach ($old in $running) {
        if (!$old.CloseMainWindow() -and !$old.HasExited) { throw 'Could not request normal shutdown of WWO.' }
        Write-Host 'Waiting for WWO to save and exit using its normal quit dialog.'
        if (!$old.WaitForExit(45000)) { throw 'WWO is still running. The installed game was retained.' }
    }
    $resume = $running.Count -gt 0 -and [IO.File]::GetLastWriteTimeUtc($save) -gt $savedBefore

    $token = [Guid]::NewGuid().ToString('N')
    $candidate = Join-Path $directory.FullName ".wwo-$token.new"
    $rollback = Join-Path $directory.FullName ".wwo-$token.previous"
    $ready = Join-Path $directory.FullName ".wwo-$token.ready"
    $hadPrior = [IO.File]::Exists($exe)
    try {
        [IO.File]::Copy($Build, $candidate)
        if ($hadPrior) { [IO.File]::Replace($candidate, $exe, $rollback) }
        else { [IO.File]::Move($candidate, $exe) }
        $game = $null
        try {
            $launch = [Diagnostics.ProcessStartInfo]::new($exe)
            $launch.WorkingDirectory = $directory.FullName
            $launch.UseShellExecute = $false
            $launch.EnvironmentVariables['WWO_UPDATE_READY_FILE'] = $ready
            if ($resume) { $launch.Arguments = '--resume' }
            $game = [Diagnostics.Process]::Start($launch)
            $deadline = [Diagnostics.Stopwatch]::StartNew()
            $status = ''
            while ($deadline.Elapsed.TotalSeconds -lt 45 -and !$game.HasExited) {
                if ([IO.File]::Exists($ready)) {
                    $status = [IO.File]::ReadAllText($ready)
                    if ($status) { break }
                }
                Start-Sleep -Milliseconds 100
            }
            if ($status -ne 'ready') {
                if ($status) { throw $status }
                if ($game.HasExited) { throw "WWO stopped during startup with exit code $($game.ExitCode)." }
                throw 'WWO did not render its first ready frame in 45 seconds.'
            }
        } catch {
            if ($game -and !$game.HasExited) {
                # This process has not reached a playable frame.
                $game.Kill()
                $game.WaitForExit()
            }
            if ($hadPrior) { [IO.File]::Replace($rollback, $exe, $null) }
            else { [IO.File]::Delete($exe) }
            throw
        }
        Write-Host "$version · $exe"
    } finally {
        [IO.File]::Delete($candidate)
        [IO.File]::Delete($ready)
    }
    if ([IO.File]::Exists($rollback)) { [IO.File]::Delete($rollback) }
}
