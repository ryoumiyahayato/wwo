# 工程代理指南

## 项目目标

本项目使用 Godot 构建一款从 1900 年开始的二维离线社会与战争模拟 Demo。玩家扮演社会人物并通过职位、组织、关系与行动影响世界，而不是直接控制国家。

## 环境与命令

- 引擎：Godot `4.6.3.stable.official.7d41c59c4` 标准版 x86-64。
- 渲染器：Compatibility。
- 本机引擎：`D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe`。
- 启动：`& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --path 'D:\wwo'`
- Headless 启动检查：`& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --quit-after 5`
- 测试：`& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script res://tests/test_runner.gd`
- P0-R1 玩家旅程：`& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script res://tests/p0_r1_player_journey.gd`
- 状态一致性回归：`& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script res://tests/state_consistency_regression.gd`
- Windows Release 导出：`& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --export-release 'Windows Desktop' 'D:\wwo\builds\windows\wwo-p0-demo.exe'`。

## 目录

- `assets/`：有明确来源与许可证的本地素材。
- `data/`：数据驱动配置。
- `scenes/`：Godot 场景；按菜单、世界、地图、UI、开发工具分区。
- `scripts/`：按核心、模拟、人物、组织、地图、行动、AI、存档、UI、工具分区。
- `tests/`：自包含测试运行器、单元测试、集成测试与固定样本。
- `docs/`：设计、架构、数据、计划、性能、存档与已知问题。

## 编码约定

- 使用 UTF-8 和尽可能完整的强类型 GDScript；函数与变量使用英文。
- 单个脚本只承担一个主要职责。模拟逻辑不进入 UI 脚本。
- UI 通过信号、事件或只读状态访问模拟；可见文本集中管理。
- 配置、公式与权重不得散落为魔法数字；持久关系使用稳定 ID。
- 注释解释约束和原因，不复述代码。

## 性能禁区

- 禁止在 `_process()` 或 `_physics_process()` 中遍历全部人物或运行社会模拟。
- 禁止为背景人物创建可见节点，或每小时深度扫描整个世界。
- UI 仅在数据变化或受控刷新频率下更新；前线按控制单元变化增量更新。
- 正式运行禁止输出海量逐小时日志。

## 禁止事项

- 不升级或替换指定 Godot，不使用 C#、C++、GDExtension 或未批准插件。
- 不加入联网、遥测、账户、广告、在线 AI 或来源不明素材。
- 不提前实现当前里程碑以外的系统，不搭建空泛的未来框架。
- 不声称未经真机测试的平台已兼容。

## 完成定义与提交前检查

每轮只完成最早未完成的里程碑。提交前必须检查代码和文档、运行项目及测试、确认无解析错误和阻塞警告、更新 `docs/ROADMAP.md` 与 `docs/KNOWN_ISSUES.md`，并报告真实限制。涉及人物层级、继承、组织索引、行动结算或存档权威校验时，还必须运行状态一致性回归。详细规则见 `docs/`。
