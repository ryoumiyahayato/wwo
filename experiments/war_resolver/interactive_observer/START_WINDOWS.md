# Windows 启动与停止

源码只在本地研究工作树。使用 Godot 4.6.3 和 Python 标准库。默认不输出 DEBUG_TRUTH。入口和脚本已由真实 Windows 进程测试；人工终端体验尚未验收。

在 PowerShell 设置路径：

```powershell
$ObserverRoot = 'D:\programs\WWO\research\military\wwo-interactive-observer-20261010T1934'
$ObserverPython = 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$ObserverClient = Join-Path $ObserverRoot 'experiments\war_resolver\interactive_observer\client.py'
$ObserverScripts = Join-Path $ObserverRoot 'experiments\war_resolver\interactive_observer\scripts'
```

启动一个固定班长会话。JSON 包含已知目标、路线和已收报告。去掉 `--json` 使用短文本格式。

```powershell
& $ObserverPython -B $ObserverClient --scene S1 --actor squad --session local_review --quota 31 --json
```

手动等待时研究时钟暂停。可逐行输入：

```text
look
advance 10
drain
intent move node_unit_000 advance B AB
look
advance 15
drain
look
auto 1800 30
quit
```

`drain` 只续接当前 PENDING。`advance` 是游戏秒增量；`auto` 是绝对结束秒与固定步长。终端 AUTO 无输入仍推进；`look` 不选择时间目标。`pause` 在提交边界暂停。普通人物使用 `personal cover take_cover` 或 `personal follow wait`。取消使用 `intent stop node_unit_000 cancel -`。普通人物/班/排/连输入间隔仍为原30/60/120/300秒。被拒请求也保留ID；新意图使用新ID，同ID同内容不会再次执行。

三组实际脚本会话，另列连级：

```powershell
& $ObserverPython -B $ObserverClient --scene S1 --actor squad --session demo_S1 --quota 31 --script (Join-Path $ObserverScripts 'S1.txt') --json
& $ObserverPython -B $ObserverClient --scene S2 --actor platoon --session demo_S2 --quota 7 --script (Join-Path $ObserverScripts 'S2.txt') --json
& $ObserverPython -B $ObserverClient --scene S3 --actor soldier --session demo_S3 --quota 1 --script (Join-Path $ObserverScripts 'S3.txt') --json
& $ObserverPython -B $ObserverClient --scene S1 --actor company --session demo_company --quota 31 --script (Join-Path $ObserverScripts 'company.txt') --json
```

实际入口启动、帮助和停止烟测：

```powershell
@'
look
help
quit
'@ | & $ObserverPython -B $ObserverClient --scene S1 --actor squad --session smoke_windows --quota 31 --json
$LASTEXITCODE
```

自动回归含四个回归seed、真实脚本、headless对照、无输入、查询密度、权限、PENDING、格式拒绝、清理和24小时：

```powershell
$ObserverE2E = Join-Path $ObserverRoot 'experiments\war_resolver\interactive_observer\e2e_tests.py'
$ObserverOutput = 'D:\programs\WWO\research\military\runs\observer-user-e2e'
& $ObserverPython -B $ObserverE2E --output $ObserverOutput --long
```

输出目录必须尚不存在，避免覆盖旧证据。测试创建独立实例并全部退出。DEBUG_TRUTH 只作显式审计，人物显示单列；默认交互不创建诊断文件。

停止当前会话：输入 `quit`，或关闭其标准输入。客户端等待所属 Godot 子进程退出；超时仅终止该子进程。AUTO最多86400游戏秒；每请求64个原bounded调用；全会话10000000调用。客户端有一小时墙钟和1000000轮上限。到限明确拒绝/BLOCKED，不显示完成。不支持换人物或死亡接续。
