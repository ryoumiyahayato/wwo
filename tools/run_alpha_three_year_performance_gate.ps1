param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$BasePath,
    [Parameter(Mandatory = $true)][string]$HeadPath,
    [string]$OutputPath = '',
    [int]$Runs = 5,
    [double]$TargetSeconds = 180.0,
    [double]$AbsoluteSafetyCapSeconds = 300.0,
    [double]$MaximumRelativeMedianRatio = 1.05
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedGodotVersion = '4.6.3.stable.official.7d41c59c4'
$expectedHours = 3 * 365 * 24
$expectedChecks = 15
$expectedRandomSeed = 1001900
$measurementScript = 'tests/alpha/alpha_ai_economy_stability_test.gd'

if ($Runs -lt 5) {
    throw 'The performance gate requires at least five runs per revision.'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
$BasePath = (Resolve-Path -LiteralPath $BasePath).Path
$HeadPath = (Resolve-Path -LiteralPath $HeadPath).Path
if ($BasePath -eq $HeadPath) {
    throw 'BasePath and HeadPath must be separate checkouts.'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $HeadPath 'builds/alpha-performance-gate'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

function Get-GitValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $value = & git -C $Path @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed in $Path with exit code $LASTEXITCODE"
    }
    return ($value | Out-String).Trim()
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$ArtifactPrefix
    )
    $quotedArguments = @(
        $Arguments | ForEach-Object {
            '"' + $_.Replace('"', '\"') + '"'
        }
    ) -join ' '
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $quotedArguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $process.Start()) {
        throw "Failed to start $FilePath"
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        $process.Kill()
    }
    $process.WaitForExit()
    $stopwatch.Stop()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $stdoutPath = "$ArtifactPrefix.stdout.log"
    $stderrPath = "$ArtifactPrefix.stderr.log"
    [System.IO.File]::WriteAllText(
        $stdoutPath,
        $stdout,
        (New-Object System.Text.UTF8Encoding($false))
    )
    [System.IO.File]::WriteAllText(
        $stderrPath,
        $stderr,
        (New-Object System.Text.UTF8Encoding($false))
    )
    return [pscustomobject]@{
        Finished = $finished
        ExitCode = if ($finished) { $process.ExitCode } else { -999 }
        WallSeconds = $stopwatch.Elapsed.TotalSeconds
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
        StdoutBytes = (Get-Item -LiteralPath $stdoutPath).Length
        StderrBytes = (Get-Item -LiteralPath $stderrPath).Length
    }
}

function Invoke-ProjectImport {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$ProjectPath
    )
    $prefix = Join-Path $OutputPath "$Label-import"
    $godotLog = "$prefix.godot.log"
    $result = Invoke-CapturedProcess `
        -FilePath $GodotPath `
        -Arguments @(
            '--headless', '--audio-driver', 'Dummy', '--editor',
            '--path', $ProjectPath, '--quit-after', '8',
            '--log-file', $godotLog
        ) `
        -WorkingDirectory $ProjectPath `
        -TimeoutSeconds 180 `
        -ArtifactPrefix $prefix
    $logText = if (Test-Path -LiteralPath $godotLog) {
        Get-Content -LiteralPath $godotLog -Raw
    }
    else {
        ''
    }
    $importErrorPattern = 'SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve class|Could not find type|(?m)^ERROR:'
    if ((-not $result.Finished) -or ($result.ExitCode -ne 0) -or ($logText -match $importErrorPattern)) {
        throw "$Label cold import failed; inspect $prefix.*.log"
    }
    return [pscustomobject]@{
        Label = $Label
        WallSeconds = $result.WallSeconds
        GodotLog = $godotLog
        LogBytes = (Get-Item -LiteralPath $godotLog).Length
    }
}

function Invoke-MeasurementRun {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][int]$Run
    )
    $prefix = Join-Path $OutputPath ("{0}-run-{1}" -f $Label, $Run)
    $godotLog = "$prefix.godot.log"
    $result = Invoke-CapturedProcess `
        -FilePath $GodotPath `
        -Arguments @(
            '--headless', '--audio-driver', 'Dummy',
            '--path', $ProjectPath,
            '--script', "res://$measurementScript",
            '--log-file', $godotLog
        ) `
        -WorkingDirectory $ProjectPath `
        -TimeoutSeconds 420 `
        -ArtifactPrefix $prefix
    if (-not $result.Finished) {
        throw "$Label run $Run timed out after 420 seconds."
    }
    if (-not (Test-Path -LiteralPath $godotLog -PathType Leaf)) {
        throw "$Label run $Run did not create its Godot log."
    }
    $lines = @(Get-Content -LiteralPath $godotLog)
    $metricsLine = @(
        $lines | Where-Object { $_ -like 'ALPHA_AI_ECONOMY_METRICS=*' }
    ) | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($metricsLine)) {
        throw "$Label run $Run did not emit structured metrics."
    }
    $metrics = $metricsLine.Substring(
        'ALPHA_AI_ECONOMY_METRICS='.Length
    ) | ConvertFrom-Json
    $finishLine = @(
        $lines | Where-Object {
            $_ -match '^Alpha AI economy stability: \d+ checks, \d+ failures$'
        }
    ) | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($finishLine)) {
        throw "$Label run $Run did not emit its check summary."
    }
    if ($finishLine -notmatch '(\d+) checks, (\d+) failures') {
        throw "$Label run $Run check summary could not be parsed."
    }
    $checks = [int]$Matches[1]
    $failures = [int]$Matches[2]
    $expectedPerformanceFailures = 0
    if ([double]$metrics.elapsed_usec -ge [double]$metrics.absolute_safety_cap_usec) {
        $expectedPerformanceFailures += 1
    }
    if ([int64]$metrics.maximum_hour_usec -ge 1000000) {
        $expectedPerformanceFailures += 1
    }
    if ($checks -ne $expectedChecks) {
        throw "$Label run $Run executed $checks checks; expected $expectedChecks."
    }
    if ($failures -ne $expectedPerformanceFailures) {
        $message = "$Label run $Run reported $failures failures; only $expectedPerformanceFailures performance-cap failures were expected."
        throw $message
    }
    $expectedExitCode = if ($failures -eq 0) { 0 } else { 1 }
    if ($result.ExitCode -ne $expectedExitCode) {
        $message = "$Label run $Run exit code $($result.ExitCode) did not match its $failures failures."
        throw $message
    }
    if ([int]$metrics.hours -ne $expectedHours) {
        throw "$Label run $Run simulated $($metrics.hours) hours; expected $expectedHours."
    }
    if ([int]$metrics.random_seed -ne $expectedRandomSeed) {
        $message = "$Label run $Run used seed $($metrics.random_seed); expected $expectedRandomSeed."
        throw $message
    }
    if ((-not [bool]$metrics.restore_success) -or (-not [bool]$metrics.state_equivalent) -or ($metrics.state_summary_sha256 -ne $metrics.restored_state_summary_sha256)) {
        throw "$Label run $Run failed save/restore state equivalence."
    }
    return [pscustomobject]@{
        Revision = $Label
        Run = $Run
        IsFirstProcessRun = $Run -eq 1
        ExitCode = $result.ExitCode
        Checks = $checks
        Failures = $failures
        WallSeconds = $result.WallSeconds
        ElapsedUsec = [int64]$metrics.elapsed_usec
        ElapsedSeconds = [double]$metrics.elapsed_usec / 1000000.0
        InitializeUsec = [int64]$metrics.initialize_usec
        ProcessTotalUsec = [int64]$metrics.process_total_usec
        RestoreUsec = [int64]$metrics.restore_usec
        MaximumHourUsec = [int64]$metrics.maximum_hour_usec
        SaveStateBytes = [int64]$metrics.save_state_bytes
        PerformanceTargetMet = [bool]$metrics.performance_target_met
        StateSummarySha256 = [string]$metrics.state_summary_sha256
        RestoredStateSummarySha256 = [string]$metrics.restored_state_summary_sha256
        StateEquivalent = [bool]$metrics.state_equivalent
        WorldSummary = $metrics.world_summary
        GodotLog = $godotLog
        GodotLogBytes = (Get-Item -LiteralPath $godotLog).Length
        GodotLogLines = $lines.Count
        StdoutBytes = $result.StdoutBytes
        StderrBytes = $result.StderrBytes
    }
}

function Get-PerformanceStatistics {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records
    )
    $ordered = @(
        $Records | ForEach-Object { [double]$_.ElapsedSeconds } |
            Sort-Object
    )
    $wallOrdered = @(
        $Records | ForEach-Object { [double]$_.WallSeconds } |
            Sort-Object
    )
    $count = $ordered.Count
    $middle = [int][Math]::Floor($count / 2)
    $median = if ($count % 2 -eq 1) {
        $ordered[$middle]
    }
    else {
        ($ordered[$middle - 1] + $ordered[$middle]) / 2.0
    }
    $wallMedian = if ($count % 2 -eq 1) {
        $wallOrdered[$middle]
    }
    else {
        ($wallOrdered[$middle - 1] + $wallOrdered[$middle]) / 2.0
    }
    $p90Index = [Math]::Max(
        0,
        [Math]::Ceiling(0.90 * $count) - 1
    )
    return [pscustomobject]@{
        Count = $count
        RawSeconds = @($Records | ForEach-Object { $_.ElapsedSeconds })
        RawWallSeconds = @($Records | ForEach-Object { $_.WallSeconds })
        FastestSeconds = $ordered[0]
        SlowestSeconds = $ordered[-1]
        MedianSeconds = $median
        P90NearestRankSeconds = $ordered[$p90Index]
        RangeSeconds = $ordered[-1] - $ordered[0]
        FirstProcessWallSeconds = [double]$Records[0].WallSeconds
        MedianWallSeconds = $wallMedian
        WarmMedianSeconds = if ($count -gt 1) {
            (
                Get-PerformanceStatistics -Records @($Records | Select-Object -Skip 1)
            ).MedianSeconds
        }
        else {
            $median
        }
        WarmMedianWallSeconds = if ($count -gt 1) {
            (
                Get-PerformanceStatistics -Records @($Records | Select-Object -Skip 1)
            ).MedianWallSeconds
        }
        else {
            $wallMedian
        }
    }
}

$baseHead = Get-GitValue -Path $BasePath -Arguments @('rev-parse', 'HEAD')
$headHead = Get-GitValue -Path $HeadPath -Arguments @('rev-parse', 'HEAD')
$baseStatus = Get-GitValue -Path $BasePath -Arguments @('status', '--short')
$headStatusBeforeCopy = Get-GitValue -Path $HeadPath -Arguments @('status', '--short')
if (-not [string]::IsNullOrWhiteSpace($baseStatus)) {
    throw "Base checkout must be clean before measurement: $baseStatus"
}
if (-not [string]::IsNullOrWhiteSpace($headStatusBeforeCopy)) {
    Write-Warning 'Head checkout has local changes; CI should normally measure a clean checkout.'
}
$networkApiPattern = 'HTTPRequest|HTTPClient|WebSocket|PacketPeerUDP|StreamPeerTCP|ENetMultiplayerPeer'
$networkApiMatches = @(
    & git -C $HeadPath grep -n -E $networkApiPattern -- '*.gd' '*.tscn' '*.godot' 2>$null
)
$networkScanExitCode = $LASTEXITCODE
if ($networkScanExitCode -notin @(0, 1)) {
    throw "Project networking API scan failed with exit code $networkScanExitCode."
}

$headMeasurementPath = Join-Path $HeadPath $measurementScript
$baseMeasurementPath = Join-Path $BasePath $measurementScript
Copy-Item -LiteralPath $headMeasurementPath -Destination $baseMeasurementPath -Force
$measurementScriptSha256 = (
    Get-FileHash -LiteralPath $headMeasurementPath -Algorithm SHA256
).Hash.ToLowerInvariant()

$versionResult = Invoke-CapturedProcess `
    -FilePath $GodotPath `
    -Arguments @('--version') `
    -WorkingDirectory $HeadPath `
    -TimeoutSeconds 30 `
    -ArtifactPrefix (Join-Path $OutputPath 'godot-version')
$actualGodotVersion = (
    Get-Content -LiteralPath $versionResult.StdoutPath -Raw
).Trim()
if ($actualGodotVersion -ne $expectedGodotVersion) {
    $message = "Godot version mismatch: expected $expectedGodotVersion, got $actualGodotVersion"
    throw $message
}

$baseImport = Invoke-ProjectImport -Label 'base' -ProjectPath $BasePath
$headImport = Invoke-ProjectImport -Label 'head' -ProjectPath $HeadPath
$records = New-Object System.Collections.Generic.List[object]
for ($run = 1; $run -le $Runs; $run++) {
    Write-Host "Base run $run of $Runs"
    $records.Add((
        Invoke-MeasurementRun -Label 'base' -ProjectPath $BasePath -Run $run
    ))
    Write-Host "Head run $run of $Runs"
    $records.Add((
        Invoke-MeasurementRun -Label 'head' -ProjectPath $HeadPath -Run $run
    ))
}

$baseRecords = @($records | Where-Object { $_.Revision -eq 'base' })
$headRecords = @($records | Where-Object { $_.Revision -eq 'head' })
$baseStatistics = Get-PerformanceStatistics -Records $baseRecords
$headStatistics = Get-PerformanceStatistics -Records $headRecords
$relativeMedianRatio = (
    $headStatistics.MedianSeconds / $baseStatistics.MedianSeconds
)
$gateFailures = New-Object System.Collections.Generic.List[string]
if ($headStatistics.MedianSeconds -ge $TargetSeconds) {
    $gateFailures.Add("Head median $($headStatistics.MedianSeconds)s is not below the $TargetSeconds second target.")
}
if ($headStatistics.P90NearestRankSeconds -ge $AbsoluteSafetyCapSeconds) {
    $gateFailures.Add("Head nearest-rank P90 $($headStatistics.P90NearestRankSeconds)s reached the $AbsoluteSafetyCapSeconds second absolute cap.")
}
if ($relativeMedianRatio -gt $MaximumRelativeMedianRatio) {
    $gateFailures.Add("Head/Base median ratio $relativeMedianRatio exceeded the allowed $MaximumRelativeMedianRatio.")
}

$allStateHashes = @(
    $records | ForEach-Object { $_.StateSummarySha256 } |
        Sort-Object -Unique
)
if ($allStateHashes.Count -ne 1) {
    $gateFailures.Add(
        "Base and Head produced $($allStateHashes.Count) deterministic state hashes."
    )
}
$worldSummaries = @(
    $records | ForEach-Object {
        $_.WorldSummary | ConvertTo-Json -Compress -Depth 20
    } | Sort-Object -Unique
)
if ($worldSummaries.Count -ne 1) {
    $gateFailures.Add(
        "Base and Head produced $($worldSummaries.Count) world summaries."
    )
}
$logLineCounts = @(
    $records | ForEach-Object { $_.GodotLogLines } | Sort-Object -Unique
)
if ($networkApiMatches.Count -ne 0) {
    $gateFailures.Add(
        "Project networking API scan found $($networkApiMatches.Count) references."
    )
}

$operatingSystem = Get-CimInstance Win32_OperatingSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$report = [ordered]@{
    schema_version = 1
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    environment = [ordered]@{
        os_caption = $operatingSystem.Caption
        os_version = $operatingSystem.Version
        os_build = $operatingSystem.BuildNumber
        processor = $processor.Name
        logical_processors = $processor.NumberOfLogicalProcessors
        godot_version = $actualGodotVersion
        godot_path = $GodotPath
        measurement_script_sha256 = $measurementScriptSha256
        orchestrator_network_requests_during_measurement = 0
        project_network_api_match_count = $networkApiMatches.Count
        concurrent_test_processes = 1
        debugger_attached = $false
        screenshot_tasks = 0
    }
    revisions = [ordered]@{
        base_sha = $baseHead
        head_sha = $headHead
    }
    fixture = [ordered]@{
        years = 3
        hours = $expectedHours
        random_seed = $expectedRandomSeed
        checks_per_run = $expectedChecks
    }
    gate = [ordered]@{
        target_seconds = $TargetSeconds
        absolute_safety_cap_seconds = $AbsoluteSafetyCapSeconds
        maximum_relative_median_ratio = $MaximumRelativeMedianRatio
        relative_median_ratio = $relativeMedianRatio
        passed = $gateFailures.Count -eq 0
        failures = @($gateFailures)
    }
    cold_import = [ordered]@{
        base_wall_seconds = $baseImport.WallSeconds
        head_wall_seconds = $headImport.WallSeconds
        base_import_plus_first_run_wall_seconds = (
            $baseImport.WallSeconds + $baseStatistics.FirstProcessWallSeconds
        )
        head_import_plus_first_run_wall_seconds = (
            $headImport.WallSeconds + $headStatistics.FirstProcessWallSeconds
        )
    }
    statistics = [ordered]@{
        base = $baseStatistics
        head = $headStatistics
    }
    equivalence = [ordered]@{
        unique_state_hashes = $allStateHashes
        unique_world_summary_count = $worldSummaries.Count
        unique_godot_log_line_counts = $logLineCounts
        all_restore_checks_passed = @(
            $records | Where-Object { -not $_.StateEquivalent }
        ).Count -eq 0
    }
    runs = @($records)
}
$reportJson = $report | ConvertTo-Json -Depth 100
$reportPath = Join-Path $OutputPath 'alpha-three-year-performance-report.json'
[System.IO.File]::WriteAllText(
    $reportPath,
    $reportJson,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Base raw seconds: $($baseStatistics.RawSeconds -join ', ')"
Write-Host "Head raw seconds: $($headStatistics.RawSeconds -join ', ')"
Write-Host "Base raw wall seconds: $($baseStatistics.RawWallSeconds -join ', ')"
Write-Host "Head raw wall seconds: $($headStatistics.RawWallSeconds -join ', ')"
Write-Host "Base median: $($baseStatistics.MedianSeconds)s"
Write-Host "Head median: $($headStatistics.MedianSeconds)s"
Write-Host "Head nearest-rank P90: $($headStatistics.P90NearestRankSeconds)s"
Write-Host "Head/Base median ratio: $relativeMedianRatio"
Write-Host "Structured report: $reportPath"
if ($gateFailures.Count -gt 0) {
    foreach ($failure in $gateFailures) {
        Write-Error $failure
    }
    exit 1
}
Write-Host 'Alpha three-year performance gate passed.'
