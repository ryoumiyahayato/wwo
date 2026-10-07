# 本地构建与验证产物

当前 Windows Release 使用 `builds/windows/wwo-performance-r1.exe`，重新导出时覆盖同一路径。`builds/`、`local-artifacts/`、`artifacts/` 不进入 Windows Release；本地验证日志使用固定名称覆盖，避免每次运行增加一个历史目录。

阶段结束保留最终报告、必要 JSON summary、少量代表截图和历史来源。删除被后继版本替代的 EXE、probe/iteration/QA binary、重复日志、临时 profiler、临时存档副本与源码编辑备份。真实用户存档位于 Godot `user://`，不属于这些目录。

`local-artifacts/world-data-audit/` 中已追踪的 JSON 被当前 Python 回归读取，不能按普通产物删除。`artifacts/formal-product-system-completeness.json` 仍是审计测试的文件输入；`artifacts/variable-state-audit.json` 是固定历史提交的证据索引，当前源码重新扫描不能重建原历史记录。它们继续保留。

大型机器字典 `docs/generated/world_data_dictionary/dictionary.json` 按需生成，不长期保留：

```powershell
python tools/world_data_dictionary/generate.py --repo-root .
```

生成脚本、源数据和可读的 dataset 文档保留。测试在内存中调用生成器，不读取该输出副本。

`.godot/` 和 Python `__pycache__/` 可重新生成；`.git/` 是版本历史。本约定没有自动清理程序，数据与旧源码仍需逐项核实用途。
