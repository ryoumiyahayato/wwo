# WWO内部预览入口

从工程根运行PowerShell。Python仅用标准库；不启动游戏。`WWO_PYTHON`和`WWO_GODOT`可指定本机已有运行时。

```powershell
./tools/build_preview.ps1 status
./tools/build_preview.ps1 cleanup                 # dry-run
./tools/build_preview.ps1 cleanup --execute
./tools/build_preview.ps1 build --version R57     # 仅确有正式输入变化时
```

`build`检查项目版本、并发进程、输入元数据及可选增量recipe；必要时调用现有Godot内部预览preset导入、导出。临时EXE在同卷发布到唯一候选路径，不复制完整包。PE x86-64及嵌入PCK头尾检查成功后登记CANDIDATE，再自动清理旧普通候选和已登记临时文件。导出失败只清理本次拥有的精确路径。游戏验收尚未发生。

相同输入和有效候选复用登记结果，不再次导入或导出。输入比较只用路径、长度、mtime，不生成哈希。相同版本重试同一路径；已验收、受保护或已淘汰版本不得覆盖。全局文件锁防止本入口并发；发现其他可能的制作进程就跳过清退。

只有用户明确通过实机验收后才运行：

```powershell
./tools/build_preview.ps1 promote R57 --acceptance "用户确认的验收内容和日期" --execute
```

该命令验证原候选未被替换，提升为CURRENT，并立即删除被取代普通ROLLBACK/CURRENT的登记文件。R56不是永久保护版本；在R57验收前保留，验收后按此路径清退。本轮没有执行提升。

状态在`builds/preview_registry.json`。静态保护和首次迁移依据在`tools/build/preview_policy.json`。R19/R30、正式`builds/windows/`、原始资料、许可证、Git跟踪文件、被占用或用途不明文件不能自动删除。目录只在空且已归工具所有时移除，不递归删除。

`resources`读取有限地貌目录、正式场景、加载器和制作器的消费者路径。导出排除不等于删除许可；目前旧BIN仍有重建消费者，因此不允许自动删除正式资产。

同源码旧资源对照使用正式预览预设和现有地貌清单：

```powershell
./tools/build_preview.ps1 pack-resources --current --legacy-map-storage --name r68-legacy-storage
```

`r68-relief.json` 固定 R67 回退 EXE 内的入包地貌与 287 张 WWOCM2 转换页。将保留的 R67 EXE 放在配方声明的相对路径，构建入口会重建可丢弃的本地中间件。R68 构建从现有欧陆 `.res` 生成地表共享索引，逐张比较 Godot 网格数组，再替换同一 PCK 路径。

旧地貌和欧陆地表源资源来自 PR #127 的资源树。R67 EXE 是离线构建输入，候选运行时从自身 PCK 读取。`local-artifacts/preview-manager/r68-relief` 中的 FRA0、WWOCM2、地表载荷和目录配方可重新生成。

对照 PCK 使用已验证的 FRA0、原欧陆地表 `.res` 及 `local-artifacts/map-task-a/original` 的原战略载荷。两种导出均保留原始 LOCAL 高程。

## 必要制作

默认不运行任何GIS制作。`build --recipe 工程内路径.json`可加入本轮确有必要的增量任务。recipe格式：

```json
{"jobs":[{"id":"本轮任务名","argv":["python.exe","tools/map/制作器.py","--rebuild","--temporary-budget-mib=64"],"inputs":["tools/map/制作器.py","已存在来源路径"],"outputs":["正式资产路径"],"temporary_estimate_bytes":67108864,"temporary_outputs":["local-artifacts/本轮/可重建临时文件"],"diagnostic_outputs":[]}]}
```

必须列出制作方法和真实输入。输入、输出和argv与上一成功记录相同就跳过。临时估算超过1GiB时需要本轮另行明确授权，才可传`--allow-large-preparation`。不要把唯一GIS、GeoTIFF、来源记录或许可证列成临时文件。临时清退不使正式资产重新生成。脚本发生异常时只清理本任务新建且声明为临时的文件。

R50—R57旧地貌CLI默认检查并复用已存在目录，不触发全量生成或下载。明确重制需`--rebuild`/`--refresh...`与临时预算；模块作为库导入不改变原制作函数。原有下载存在性检查继续保留。

普通构建每版本覆盖一份短摘要；子进程stdout只在内存保留128KiB尾部，最终摘要保留16KiB必要尾部。管理工具摘要总预算2MiB，登记诊断预算20MiB；超预算的可再生登记输出自动退出。没有永久日志或后台进程。来源、正式资产与唯一EXE不计入小型日志预算。

局部验证：`python tools/build/test_preview.py`。使用KB级假PE/PCK验证流程，不产生真实EXE包，也不代表Godot导出或玩家画面验收。


## R57现有GUI入口的最小互斥（2026-10-24）

`tools/map/run_r57_visual_repair.py`复用本入口的`builds/.preview-manager.lock`，在写启动配置前持锁，退出后释放。OS在包装进程退出时释放文件锁；状态文件的时间不用于夺锁。它检查实际Godot／WWO／Blender／FFmpeg命令行和CUDA进程，对未遵守锁的占用者同样等待；每120秒重新检测，不发送聊天消息，不结束其他进程。状态记录在`local-artifacts/r57-living-ui-2026-10-23/resource-state.json`，含包装PID、进程启动标识、资源需求及WAITING／RUNNING／RELEASED。正式源码写入、构建与安装清理应使用同一文件锁并先核对目标文件状态；锁只能保护遵守协议的工作线。当前机外旧自动队列已停用，不调用其旧自动领取入口。

2026-10-24用户明确选择“先做功能，性能待测”后，功能GUI可显式使用`--functional-gpu-sharing`。该参数只允许与路径及命令行均核实为Codex的`on_device_model.mojom.OnDeviceModelService`共用GPU；其他引擎和CUDA占用仍等待。结果强制记录`timing_environment_valid=false`，performance入口拒绝此参数。默认仍等待GPU空闲。材料贸易沿用development隔离目录，记录写入`material-trade-runs.json.gz`，旧30日`runs.json.gz`不改写。`--resume-material`只从正式槽4恢复真实检查点，核对原Opening及持久状态；本轮没有再次中断，冷进程续接分支未另测。`--recover-material-override`只恢复内容完全匹配、原PID及启动身份已结束的本线配置，且必须先取得OS锁并确认引擎空闲；不能依据文件年龄清理。
