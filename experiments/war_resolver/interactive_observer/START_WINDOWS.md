# Windows 启动与停止

源码只在当前研究工作树。使用现有Godot 4.6.3和Python标准库。默认不调用测试、源码核验或审计，不积累旧Observation诊断记录。本轮新增接口未试跑；以下只说明人工入口。

在 PowerShell 设置路径：

```powershell
$ObserverRoot = 'D:\programs\WWO\research\military\wwo-person-attachment-20261011T0010'
$ObserverPython = 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$ObserverClient = Join-Path $ObserverRoot 'experiments\war_resolver\interactive_observer\client.py'
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

真实成员调整使用A系列入口和相应军职，例如将启动参数设为`--scene A3 --actor company`。命令字段见[当前接口](../attachment_continuity/README.md)。根据代码接口给出，未试跑。

旧脚本、入口测试和历史输出保留原位。它们不作为启动、输入、退出或保存代码的前置。`--diagnostic`只保留显式人工导出入口，默认不加载该审计脚本。

停止当前会话：输入 `quit`，或关闭其标准输入。客户端等待所属 Godot 子进程退出；超时仅终止该子进程。AUTO最多86400游戏秒；每请求64个原bounded调用；全会话10000000调用。客户端有一小时墙钟和1000000轮上限。到限明确拒绝/BLOCKED，不显示完成。不支持换人物或死亡接续。
