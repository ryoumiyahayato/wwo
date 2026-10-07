param([Parameter(Mandatory=$true)][string]$Executable,[Parameter(Mandatory=$true)][string]$Output,[string[]]$ProbeArguments=@(),[switch]$Visible)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$probeProcess = Start-Process -FilePath $Executable -ArgumentList (@('--',('"'+$Output.Replace('\','/')+'"'))+$ProbeArguments) -WindowStyle $(if($Visible){'Normal'}else{'Hidden'}) -PassThru -RedirectStandardOutput (Join-Path $Output 'stdout.log') -RedirectStandardError (Join-Path $Output 'stderr.log')
$processHandle = $probeProcess.Handle
$cores = [Environment]::ProcessorCount
$lastCpu = 0.0
$lastTime = [DateTime]::UtcNow
$writer = [System.IO.StreamWriter]::new((Join-Path $Output 'system.jsonl'),$false,[System.Text.UTF8Encoding]::new($false))
try {
 while (-not $probeProcess.HasExited) {
  $counters = Get-Counter -Counter '\GPU Engine(*)\Utilization Percentage','\GPU Process Memory(*)\Dedicated Usage','\GPU Process Memory(*)\Shared Usage' -ErrorAction SilentlyContinue
  $probeProcess.Refresh()
  if ($probeProcess.HasExited) { break }
  $now = [DateTime]::UtcNow
  $cpu = $probeProcess.TotalProcessorTime.TotalSeconds
  $elapsed = ($now-$lastTime).TotalSeconds
  $gpu = @($counters.CounterSamples | Where-Object {$_.InstanceName -match ('pid_'+$probeProcess.Id+'_')})
  $engines = @($gpu | Where-Object {$_.Path -like '*utilization*'})
  $nvidia = (& nvidia-smi --query-gpu=utilization.gpu,power.draw,memory.used,temperature.gpu,clocks.current.graphics --format=csv,noheader,nounits) -split ','
  $live = $null
  try { $live = Get-Content -LiteralPath (Join-Path $Output 'live.json') -Raw | ConvertFrom-Json } catch {}
  $row = @{utc=$now.ToString('o');pid=$probeProcess.Id;stage=if($live){$live.stage}else{'startup'};t_sec=if($live){$live.t_sec}else{0};cpu_pct=100*($cpu-$lastCpu)/($elapsed*$cores);working_set=$probeProcess.WorkingSet64;private_bytes=$probeProcess.PrivateMemorySize64;process_gpu_pct=($engines|Measure-Object -Property CookedValue -Maximum).Maximum;engines=@($engines|Select-Object InstanceName,CookedValue);dedicated_gpu_bytes=($gpu|Where-Object{$_.Path -like '*dedicated*'}|Measure-Object -Property CookedValue -Sum).Sum;shared_gpu_bytes=($gpu|Where-Object{$_.Path -like '*shared*'}|Measure-Object -Property CookedValue -Sum).Sum;nvidia_gpu_pct=$nvidia[0].Trim();nvidia_power_w=$nvidia[1].Trim();nvidia_memory_mib=$nvidia[2].Trim();nvidia_temp_c=$nvidia[3].Trim();nvidia_clock_mhz=$nvidia[4].Trim();logical_processors=$cores}
  $writer.WriteLine(($row|ConvertTo-Json -Depth 6 -Compress));$writer.Flush()
  $lastCpu=$cpu;$lastTime=$now
 }
 $probeProcess.WaitForExit()
 Write-Output ('RELEASE_EXIT='+$probeProcess.ExitCode)
} finally {$writer.Dispose()}
