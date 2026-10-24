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

## 必要制作

默认不运行任何GIS制作。`build --recipe 工程内路径.json`可加入本轮确有必要的增量任务。recipe格式：

```json
{"jobs":[{"id":"本轮任务名","argv":["python.exe","tools/map/制作器.py","--rebuild","--temporary-budget-mib=64"],"inputs":["tools/map/制作器.py","已存在来源路径"],"outputs":["正式资产路径"],"temporary_estimate_bytes":67108864,"temporary_outputs":["local-artifacts/本轮/可重建临时文件"],"diagnostic_outputs":[]}]}
```

必须列出制作方法和真实输入。输入、输出和argv与上一成功记录相同就跳过。临时估算超过1GiB时需要本轮另行明确授权，才可传`--allow-large-preparation`。不要把唯一GIS、GeoTIFF、来源记录或许可证列成临时文件。临时清退不使正式资产重新生成。脚本发生异常时只清理本任务新建且声明为临时的文件。

R50—R57旧地貌CLI默认检查并复用已存在目录，不触发全量生成或下载。明确重制需`--rebuild`/`--refresh...`与临时预算；模块作为库导入不改变原制作函数。原有下载存在性检查继续保留。

普通构建每版本覆盖一份短摘要；子进程stdout只在内存保留128KiB尾部，最终摘要保留16KiB必要尾部。管理工具摘要总预算2MiB，登记诊断预算20MiB；超预算的可再生登记输出自动退出。没有永久日志或后台进程。来源、正式资产与唯一EXE不计入小型日志预算。

局部验证：`python tools/build/test_preview.py`。使用KB级假PE/PCK验证流程，不产生真实EXE包，也不代表Godot导出或玩家画面验收。
