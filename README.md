# 1900 · WWO

Godot 4.6.3 / Compatibility 的二维离线社会与战争模拟项目。玩家是人物，地图选择与资料浏览不改变玩家身份或世界事实。

正式入口：`scenes/formal/formal_world_menu.tscn` → `scenes/formal/formal_world_main.tscn`。项目路径：`D:/programs/WWO/wwo`。

当前运行调用是 `WorldBootstrap` 创建 `WorldState`，`SimulationStep` 推进领域，`FormalPersistence` 读写现有存档，`FormalWorldApplication` 接收操作，`FormalWorldPresenter` 为 MainShell 与地图组装只读显示输入。没有旧 FormalWorldSimulation / EconomyService UI 入口。

正式界面使用四角 HUD。左上是人物所在地政体，左下是人物，右上是时间/系统，右下是自己的消息和操作反馈。人物、个人账务、地图地点、国家统计经济、组织与世界资料可通过已有明确引用导航。人物可在所在地明确映射的统计库存池购买商品，支付真实账户资金，持有并消费物品，也可设置每日消费；具体零售商和城市配送尚缺。打开页面不重新初始化现金、就业、工资或物品。

地图保留 Political / Economy 图层、铁路显示、WORLD / REGION / LOCAL、按需加载、嵌入字体和现有地形。静态批次准备完成后更新画面，页面外地图仍可操作。

当前实现、资料缺口与长期待办集中在 [当前 UI 与任务状态](docs/UI_INFORMATION_ARCHITECTURE.md)。领域调用关系见 [架构说明](docs/ARCHITECTURE.md)。旧原型、线框与独立审计文件不指导当前正式入口。

正式存档为 `user://formal_world_1900.json`，使用 `formal_world_simulation_v15` 快照与 `formal_world_exact_variant_v1` 容器，字段见 [存档格式](docs/SAVE_FORMAT.md)。内部存档指纹绑定仍保留。市场由实际经济输入与市场身份集合建立。

Prototype、Alpha 旧读取宿主、跨进程哈希探针、旧审计生成与文档同步门禁、版本盖章和失效的导出探针已删除。`tools/run_validation.ps1` 仍是批量工具，检查范围按当前任务决定。

本批只修改并保存源文件，未运行检查、试跑、回归、审计或测量。未生成新 Release，不以历史结果代表当前行为。
