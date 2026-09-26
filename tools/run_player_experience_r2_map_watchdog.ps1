param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$OutputDirectory = 'C:\Users\agcrf\wwo-formal-person-entry-r1\evidence\player_experience_r2\m\watchdog'
)

$ErrorActionPreference = 'Stop'
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($outputPath) | Out-Null
$heartbeatPath = Join-Path $outputPath 'heartbeat.json'
$stdoutPath = Join-Path $outputPath 'godot_stdout.log'
$stderrPath = Join-Path $outputPath 'godot_stderr.log'
$resultPath = Join-Path $outputPath 'watchdog_result.json'
foreach ($ownedPath in @($heartbeatPath, $stdoutPath, $stderrPath, $resultPath)) {
    if (Test-Path -LiteralPath $ownedPath) {
        Remove-Item -LiteralPath $ownedPath -Force
    }
}

$arguments = @(
    '--path', [System.IO.Path]::GetFullPath($ProjectPath),
    '--resolution', '1280x720',
    'res://tests/formal/player_experience_r2_map_watchdog_probe.tscn'
)
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

$samples = [System.Collections.Generic.List[object]]::new()
$stallEvents = [System.Collections.Generic.List[object]]::new()
$lastHeartbeatWrite = $null
$lastHeartbeatChange = [DateTime]::UtcNow
$heartbeatSeen = $false
$startupHeartbeatDelay = $null
$lastHeartbeat = $null
$lastStdoutLines = 0
$startedAt = [DateTime]::UtcNow
$terminatedForStall = $false

while (-not $process.HasExited) {
    Start-Sleep -Milliseconds 250
    $process.Refresh()
    $now = [DateTime]::UtcNow
    if (Test-Path -LiteralPath $heartbeatPath) {
        $write = (Get-Item -LiteralPath $heartbeatPath).LastWriteTimeUtc
        if ($null -eq $lastHeartbeatWrite -or $write -gt $lastHeartbeatWrite) {
            $lastHeartbeatWrite = $write
            $lastHeartbeatChange = $now
            if (-not $heartbeatSeen) {
                $heartbeatSeen = $true
                $startupHeartbeatDelay = ($now - $startedAt).TotalSeconds
            }
            try {
                $lastHeartbeat = Get-Content -LiteralPath $heartbeatPath -Raw | ConvertFrom-Json
            } catch {
                # A write can be observed between truncate and flush. The next
                # sample retries; an incomplete read is not a simulated frame.
            }
        }
    }
    $heartbeatAge = $(if ($heartbeatSeen) { ($now - $lastHeartbeatChange).TotalSeconds } else { 0.0 })
    $lineCount = 0
    if (Test-Path -LiteralPath $stdoutPath) {
        $lineCount = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue).Count
    }
    $lineRate = [Math]::Max(0, $lineCount - $lastStdoutLines) * 4
    $lastStdoutLines = $lineCount
    $responding = $true
    try {
        $responding = (Get-Process -Id $process.Id -ErrorAction Stop).Responding
    } catch {
        $responding = $false
    }
    $samples.Add([ordered]@{
        elapsed_seconds = [Math]::Round(($now - $startedAt).TotalSeconds, 3)
        pid = $process.Id
        cpu_seconds = [Math]::Round($process.TotalProcessorTime.TotalSeconds, 3)
        working_set_bytes = $process.WorkingSet64
        private_bytes = $process.PrivateMemorySize64
        responding = $responding
        heartbeat_age_seconds = [Math]::Round($heartbeatAge, 3)
        heartbeat_frame = $(if ($null -ne $lastHeartbeat) { $lastHeartbeat.frame } else { $null })
        heartbeat_stage = $(if ($null -ne $lastHeartbeat) { $lastHeartbeat.stage } else { 'startup' })
        stdout_lines_per_second = $lineRate
    })
    if ($heartbeatSeen -and $heartbeatAge -gt 2.0 -and ($stallEvents.Count -eq 0 -or $heartbeatAge -gt ([double]$stallEvents[$stallEvents.Count - 1]['heartbeat_age_seconds'] + 1.0))) {
        $stallEvents.Add([ordered]@{
            elapsed_seconds = [Math]::Round(($now - $startedAt).TotalSeconds, 3)
            heartbeat_age_seconds = [Math]::Round($heartbeatAge, 3)
            responding = $responding
            classification = $(if ($heartbeatAge -gt 5.0) { 'DIAGNOSTIC_STALL' } else { 'STALL' })
        })
    }
    if ($heartbeatAge -gt 10.0) {
        # This PID was created by this watchdog and is the only process it may stop.
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $terminatedForStall = $true
        break
    }
}

$process.WaitForExit()
$nativeExitCode = $process.ExitCode
$exitCode = $(
    if ($terminatedForStall) { 124 }
    elseif ($null -ne $nativeExitCode) { $nativeExitCode }
    elseif ($null -ne $lastHeartbeat -and $lastHeartbeat.stage -eq 'complete') { 0 }
    else { 1 }
)
$maxHeartbeatAge = 0.0
foreach ($sample in $samples) {
    $maxHeartbeatAge = [Math]::Max($maxHeartbeatAge, [double]$sample['heartbeat_age_seconds'])
}
$result = [ordered]@{
    pid = $process.Id
    exit_code = $exitCode
    terminated_for_stall = $terminatedForStall
    max_heartbeat_age_seconds = $maxHeartbeatAge
    startup_heartbeat_delay_seconds = $startupHeartbeatDelay
    sample_count = $samples.Count
    stall_events = $stallEvents
    samples = $samples
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Output ('WATCHDOG_RESULT=' + $resultPath)
Write-Output ('EXIT=' + $exitCode)
Write-Output ('MAX_HEARTBEAT_AGE_SECONDS=' + $maxHeartbeatAge)
Write-Output ('STALL_EVENTS=' + $stallEvents.Count)
exit $exitCode
