param(
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
 [switch]$IncludeMainSource,
 [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$root = 'D:\programs\WWO\wwo'
$archivePath = 'docs/archive/main-wwo-r57-g21-20261024/inventory.json'
$raw = & gh api "repos/ryoumiyahayato/wwo/contents/${archivePath}?ref=$Commit" -H 'Accept: application/vnd.github.raw+json'
if ($LASTEXITCODE -ne 0) { throw 'GitHub清单读取失败。没有删除。' }
$manifest = ($raw -join "`n") | ConvertFrom-Json
$backup = $manifest.resource_supplement.remaining_originals_backup
if ($manifest.repository -ne 'ryoumiyahayato/wwo' -or $backup.state -ne 'UPLOADED_VERIFIED') { throw '未找到已回下载核对的本轮归档。' }
$assetRaw = & gh api "repos/ryoumiyahayato/wwo/releases/$($manifest.resource_supplement.release_id)/assets?per_page=100" --paginate --slurp --jq 'add | map({id,size})'
if ($LASTEXITCODE -ne 0) { throw '私有附件清单读取失败。没有删除。' }
$assets = @{}
foreach ($asset in (($assetRaw -join "`n") | ConvertFrom-Json)) { $assets[[string]$asset.id] = [int64]$asset.size }
foreach ($package in $manifest.resource_supplement.packages) {
 if ($package.state -ne 'UPLOADED_VERIFIED' -or -not $assets.ContainsKey([string]$package.asset_id) -or $assets[[string]$package.asset_id] -ne [int64]$package.bytes) { throw "云端附件缺失或长度变化：$($package.name)" }
}
$protected = @(
 "$root\.git",
 "$root\local-artifacts\r57-person-consumption-2026-10-23",
 "$root\local-artifacts\r57-person-participation-2026-10-23",
 "$root\local-artifacts\revoked-r30",
 "$root\local-artifacts\global-strategic-r1",
 "$root\local-artifacts\preview-manager"
)
$busy = @(Get-CimInstance Win32_Process | Where-Object {
 $_.ProcessId -ne $PID -and $_.Name -match '^(godot.*|wwo.*|python.*|blender.*)\.exe$' -and
 (($_.ExecutablePath -and $_.ExecutablePath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) -or ($_.CommandLine -and $_.CommandLine.Contains($root)))
})
if ($busy.Count) { throw '本工程有运行进程。没有删除；请自行正常关闭后再决定。' }
$approved = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$chosen = @($backup.manual_cleanup_files)
if ($IncludeMainSource) { $chosen += @($backup.main_worktree_cleanup_files) }
$epoch = [int64]621355968000000000
foreach ($row in $chosen) {
 if ($seen.ContainsKey([string]$row.path)) { continue }
 $seen[[string]$row.path] = $true
 $path = [IO.Path]::GetFullPath((Join-Path $root $row.path))
 if (-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "越界路径：$path" }
 if ($path -eq "$root\local-artifacts\.gdignore" -or $path -eq "$root\builds\.preview-manager.lock") { throw "共享导入边界或锁文件保留：$path" }
 if ([IO.Path]::GetFileName($path) -in @('FIFO_QUEUE_ZH.md','queue.sqlite3')) { throw "公共协调历史保留：$path" }
 foreach ($hold in $protected) {
  if ($path -eq $hold -or $path.StartsWith($hold+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "受保护路径：$path" }
 }
 if (-not (Test-Path -LiteralPath $path)) { continue }
 $item = Get-Item -LiteralPath $path -Force
 if ($item.PSIsContainer) { throw "预期文件，实际为目录：$path" }
 $ancestor = $item
 while ($ancestor -and $ancestor.FullName.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
  if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "链接路径保留：$path" }
  $ancestor = if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
 }
 $mtimeNs = [int64](($item.LastWriteTimeUtc.Ticks - $epoch) * [int64]100)
 if ($item.Length -ne [int64]$row.bytes -or $mtimeNs -ne [int64]$row.mtime_ns) { throw "归档后文件已变化，停止：$path" }
 $approved.Add([pscustomobject]@{Path=$path;Bytes=[int64]$row.bytes})
}
$total = ($approved | Measure-Object -Property Bytes -Sum).Sum
Write-Host "已核对：$($approved.Count)个本轮已归档文件，逻辑大小$total 字节。"
Write-Host '范围只含清单中的已归档文件。IncludeMainSource会加入已核对的主工源码及运行资源；.git、经济45项、主工此前拒绝165项、混合服务目录、真实玩家存档、外部共享库及其他工作线均排除。'
if (-not $Execute) { Write-Host '当前为预览。带-Execute才执行。'; return }
$lock = $null
$removedCount = 0
$removedBytes = [int64]0
try {
 $lock = [IO.File]::Open("$root\builds\.preview-manager.lock",[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 foreach ($item in $approved) {
  Remove-Item -LiteralPath $item.Path -ErrorAction Stop
  $removedCount++
  $removedBytes += $item.Bytes
 }
 $parents = @($approved | ForEach-Object { [IO.Path]::GetDirectoryName($_.Path) } | Sort-Object -Unique | Sort-Object Length -Descending)
 foreach ($directory in $parents) {
  while ($directory -and $directory -ne $root -and (Test-Path -LiteralPath $directory)) {
   if (@(Get-ChildItem -LiteralPath $directory -Force | Select-Object -First 1).Count) { break }
   $parent = [IO.Path]::GetDirectoryName($directory)
   Remove-Item -LiteralPath $directory -ErrorAction Stop
   $directory = $parent
  }
 }
 Write-Host "已删除$removedCount 个文件，逻辑大小$removedBytes 字节；只移除已空的父目录。"
} catch {
 Write-Host "停止。实际已删除$removedCount 个文件，逻辑大小$removedBytes 字节。未改用其他方式。"
 throw
} finally { if ($lock) { $lock.Dispose() } }
