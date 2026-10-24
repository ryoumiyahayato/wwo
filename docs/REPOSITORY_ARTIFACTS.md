# 本地构建与验证产物

Windows Release 工作流导出到 `builds/windows/wwo-p0-demo.exe`。本轮没有生成 Release。`builds/`、`local-artifacts/`、`artifacts/` 不进入 Windows Release；本地日志不属于游戏存档。

阶段结束保留最终报告、必要 JSON summary、少量代表截图和历史来源。删除被后继版本替代的 EXE、probe/iteration/QA binary、重复日志、临时 profiler、临时存档副本与源码编辑备份。真实用户存档位于 Godot `user://`，不属于这些目录。

`local-artifacts/world-data-audit/` 中部分 JSON 仍由独立数据工具测试读取，保留。旧 loader contract 的生成与调用已删除，已有报告只能作为历史记录。

2026-10-18已清理两份失去生成工具和正式调用者的机器审计输出：`artifacts/formal-product-system-completeness.json`、`artifacts/variable-state-audit.json`。旧结构重建截图、`local-artifacts/ten-year-strategic-r1/` 的复制工程与临时计时/采样/哈希比对脚本、旧清理清单、冻结检查结果和历史地图日志也已清理。对应可读历史报告保留，不据此恢复旧探针或门禁。

大型机器字典 `docs/generated/world_data_dictionary/dictionary.json` 按需生成，不长期保留：

```powershell
python tools/world_data_dictionary/generate.py --repo-root .
```

生成脚本、源数据和可读的 dataset 文档保留。测试在内存中调用生成器，不读取该输出副本。

`.godot/` 和 Python `__pycache__/` 可重新生成；`.git/` 是版本历史。本约定没有自动清理程序，数据与旧源码仍需逐项核实用途。
