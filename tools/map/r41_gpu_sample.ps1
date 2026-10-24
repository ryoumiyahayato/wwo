param([int]$TargetProcess,[string]$OutputFile)
# Finite per-process Windows counter collection. Invoked only by the R41 run.
$rows = [System.Collections.Generic.List[object]]::new()
while (Get-Process -Id $TargetProcess -ErrorAction SilentlyContinue) {
    $row = @{ unix=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()/1000.0 }
    try {
        $engines = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter "Name LIKE 'pid_${TargetProcess}_%'" -ErrorAction Stop)
        $memory = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -Filter "Name LIKE 'pid_${TargetProcess}_%'" -ErrorAction Stop)
        $threeD = @($engines | Where-Object Name -Like '*engtype_3D*')
        $row.gpu_3d_busiest_percent = if ($threeD.Count) { ($threeD | Measure-Object UtilizationPercentage -Maximum).Maximum } else { $null }
        $row.dedicated_bytes = if ($memory.Count) { ($memory | Measure-Object DedicatedUsage -Sum).Sum } else { $null }
        $row.shared_bytes = if ($memory.Count) { ($memory | Measure-Object SharedUsage -Sum).Sum } else { $null }
        $row.counter_entries = $engines.Count
    } catch { $row.error = $_.Exception.Message }
    $rows.Add($row)
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputFile -Encoding utf8
    Start-Sleep -Milliseconds 1000
}
