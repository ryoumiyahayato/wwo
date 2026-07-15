# 1900年二维社会与战争模拟 Demo

一个使用 Godot 制作的二维、离线、可暂停、实时推进的社会与战争模拟项目。玩家从架空国家的一名社会人物开始，通过技能、职业、组织和关系逐步获得影响力。

## 当前范围

目标 P0 Demo 包含两个架空国家、双层二维地图、人物随机开局、行动与组织、简化 AI、继承、存档和开发工具。历史 Windows 11 x86-64 系统原型曾成功导出，但不能代表当前版本。当前发布状态必须按下表理解：

- 后台模拟与状态一致性：上一轮统一自动回归通过，本轮 UI 重构后的全量复验进行中。
- 玩家核心闭环：结构性重构中；关闭开发者模式的自动可见控件旅程已建立，人工普通角色旅程尚未全部完成。
- 正式 UI：1280×720 实际窗口复核进行中，尚未最终验收。
- Windows Release：尚未对当前提交导出和验收。
- P0-R1：未完成，不是发布候选。

地图支持拖动、滚轮缩放、法理边界、实际控制色、争夺斜纹、城市与铁路、自动前线和地区信息面板。控制压力读取铁路连接、地区与单元社会支持、进攻邻接数和包围状态；直接修改权威状态的控件只在开发模式中显示。

## 环境要求

- Windows 11 x86-64（当前开发、审计与历史导出环境）
- Godot 标准版 `4.6.3.stable.official.7d41c59c4`
- Compatibility 渲染器
- 强类型 GDScript

Windows 10 是目标兼容平台，但尚未完成实机验证。Linux 和 macOS 仅保持设计兼容，不宣称已测试。

## 安装和运行

Godot 已由用户安装，不需要本项目下载或升级：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --path 'D:\wwo'
```

## 测试

干净检出不能直接假设 Godot 已生成全局 `class_name` 缓存。优先使用自举验证脚本；它会先执行 Headless 编辑器导入，再依次运行全部测试和启动检查，并把日志中的解析/加载错误视为失败，即使 Godot 进程返回 `0`：

```powershell
powershell -ExecutionPolicy Bypass -File 'D:\wwo\tools\run_validation.ps1'
```

脚本覆盖：

- `tests/current_test_runner.gd`（继承并运行完整 M0 至 M9 综合套件）
- `tests/p0_r1_logic_regression.gd`
- `tests/p0_r1_player_journey_post_audit.gd`
- `tests/p0_r1_safety_regression.gd`
- `tests/state_consistency_regression.gd`
- `tests/simulation_quality_regression.gd`
- `tests/codex_audit_regression.gd`
- Headless 主项目启动与解析日志检查

完整验收步骤见 `docs/TEST_PLAN.md` 和 `docs/P0_R1_VALIDATION.md`。

## 导出

`export_presets.cfg` 提供 Windows Desktop x86-64、Linux x86-64 和 macOS Universal 预设。全部回归与人工验收通过后再重新导出：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --export-release 'Windows Desktop' 'D:\wwo\builds\windows\wwo-p0-r1.exe'
```

Linux 与 macOS 未导出、未测试。

## 当前验证事实

2026-07-13 使用精确 Godot 版本 `4.6.3.stable.official.7d41c59c4` 对提交 `9e92e77c422be782fd21baaa69ee7b41099ce8be` 进行了只读 Codex 审计：

- 原始源码的 Headless 进程虽然返回 `0`，日志实际包含强类型解析错误，因此启动不通过。
- 临时影子副本只修复该单点后：原有总测试 `552/564`、P0-R1 逻辑 `35/35`、玩家旅程 `20/21`、安全回归 `25/26`、状态一致性 `240/240`、模拟质量 `50/50`。
- 影子一年模拟约 `1,916 ms`，仍低于 10 秒预算，但旧的 `846 ms` 不能继续作为当前默认分支证据。

审计后默认分支已进一步修复：

- 强类型 `is_surrounded()` 调用错误。
- 干净检出导入和“退出码为 0 但有解析错误”的验证缺口。
- 任意技能正式学习、实际行动主技能成长，以及训练、准备和资金充分后的明确保证成功路径。
- 退休、死亡、长期监禁和失势退出原因的权威状态约束。
- NPC 先按旧上下文结算已过去区间，再从边界应用新条件。
- 存档活跃上限、激活种子、AI 覆盖和行动实例 ID 唯一性校验。
- 1280×720 行动面板将开始按钮固定在滚动区外。
- 备份快照测试按 JSON 语义归一化比较。
- 继承事务在运行时活跃上限变化导致升级失败时，仍可完整恢复继承前名册；外部存档恢复继续强制执行配置上限。

2026-07-15 UI 重构前，在精确 Godot `4.6.3.stable.official.7d41c59c4` 上运行统一验证脚本并通过：综合 `570/570`、逻辑 `35/35`、当时的自动玩家旅程 `32/32`、安全 `26/26`、状态一致性 `41/41`、模拟质量 `50/50`、Codex 审计专项 `29/29`；Headless 主项目没有解析或脚本加载错误。目标规模一年模拟约 `2,833 ms`，测试存档约 `292.7 KiB`。这些是重构前基线，不能替代当前提交的最终复验。

本轮已把地图顶栏、行动、社会系统和人物页改为正式玩家入口，并新增关闭开发模式的 1280×720 可见控件旅程。只有当前提交再次通过统一验证、实际窗口旅程和 Windows Release 独立冒烟后，才允许更新为阶段性健全；在此之前 P0-R1 保持未完成。
