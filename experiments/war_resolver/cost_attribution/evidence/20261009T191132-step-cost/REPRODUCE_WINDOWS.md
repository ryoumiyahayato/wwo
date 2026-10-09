本机保留工作树：`D:\programs\WWO\research\military\wwo-step-cost-20261009T191132`。本地分支：`experiment/continuous-war-step-cost-windows-20261009T191132`。本地代码提交：`a094f7e73d13b821a713656062e93fcbe5e003f7`，未推送；云端没有该源码提交链接。

来源复核记录在HEADS_AND_SOURCE.json。Task8完整树和其manifest基线hash已验证；直接取得远端冻结43f35完整树，47个CLI运行/依赖文件与用户ZIP逐项同指纹。未恢复原b411846或文档36e629d对象，不把ZIP当bundle，也不把Task8替代43先决条件。工作树的47个运行文件已恢复为准确LF blob字节，其余使用本机检出字节。固定Godot4.6.3.stable.official.7d41c59c4；Python3.12.14、Git2.54.0.windows.1、PowerShell7.6.5。

```powershell
$warResearchPath = 'D:\programs\WWO\research\military\wwo-step-cost-20261009T191132'
$warGodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe'
$warPythonPath = 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $warGodotPath --headless --editor --path $warResearchPath --quit
& $warGodotPath --headless --path $warResearchPath --script res://experiments/war_resolver/cost_attribution/tests.gd
& $warGodotPath --headless --path $warResearchPath --script res://experiments/war_resolver/continuous/long_tests.gd
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe' -NoProfile -File "$warResearchPath/tools/run_validation.ps1" -ProjectPath $warResearchPath -PythonPath $warPythonPath
```

上述直接命令只展示真实入口。原运行使用本地`D:\programs\WWO\research\military\runs\20261009T191132-step-cost/run_bounded.py`为每步限制时间/16MiB日志，并把APPDATA、LOCALAPPDATA、TEMP、TMP及XDG缓存重定向至研究根内；未改变执行策略、线程、优先级或电源设置。复跑应采用该包装器与唯一的新输出名字，避免写到正式目录或覆盖证据。

单次相关诊断入口是`res://experiments/war_resolver/cost_attribution/run.gd -- --seed 71 --seconds 1800 --quota 7 --diagnostic on --level2 on --aggregate true --sample-id <unique> --output <new-absolute-file-under-research-root>`；OFF改diagnostic off。二级前的宽模式使用level2 off，有明显开销。五组配对顺序及预热在本地g1_samples.py与原始样本manifest中。最终原入口还执行原Tasks1–8测试/两次fresh replay/benchmark、五条保留回归、九条战争脚本、Codex审计和world_data unittest；准确命令和timeout见FINAL_VALIDATION.json。

24h long_tests实际包含seeds71/109、normal及quota1/7/31。normal/quota的原始trace强序列差异另外保留，不能重排后宣称更强等价。所有完整原日志和必要失败尝试在raw-evidence.zip。外部包装器和本地源码不随本轮云端证据发布；源代码复跑依赖本机保留的提交。
