# 当前运行架构与引擎迁移

核对日期：2026-11-12。范围包括当前主工程源码和已导出的 R67。源码含有 R67 之后的地图修改，下面的封包数字以 R67 为准。

## 当前接线

WWO 在一个 Godot 4.6.3 Compatibility 进程内运行。正式菜单构建或恢复世界，`FormalWorldApplication` 安装 `WorldState`、`SimulationStep` 和存档服务。领域组件各自拥有状态，时钟由 `GameClock` 统一维护，地图和界面读取状态并提交操作。入口见 [项目配置](../project.godot) 和 [世界安装](../scripts/formal/formal_world_application.gd)。

| 模块 | 现状 | 迁移工作 |
| --- | --- | --- |
| 世界与经济 | 人口、人物、组织、空间、领土和账户按领域持有。正式世界运行宏观市场。法国普通开局还绑定 GDScript 节点经济，共用正式账本、时钟和空间。 | 移植计算和查询接口，保留事件顺序、整数金额、稳定 ID、货批和在途订单。先用同一开局逐日核对。 |
| 战略军事 | 创建独立的地图适配器、状态和服务。战略军事状态进入正式存档，普通 `SimulationStep` 当前没有调用军事服务。 | 规则可单独移植。重接空间、领土和存档接口。 |
| 坦克训练 | 主进程内按需装入的 3D 会话。训练进入时暂停正式世界，使用独立 `SubViewport` 和 `World3D`，训练状态没有写回正式存档。 | 保留现有嵌入模块直到地图和核心迁移稳定。移植时重接物理、碰撞、地形、输入和界面。 |
| 地图和界面 | 多个视口处理球体、区域和近景。地图按需加载预制地貌、岸线和城镇分片。Godot 控件承载菜单、HUD 和经济界面。 | 经纬度、来源数据、原始模型及图像可复用。Godot 网格、场景、着色器和预制 `.display` 需要转换或重做，缩放交接和拾取也需验证。 |
| 存档 | 外层 JSON 保存 Base64 编码的 Godot `Variant`。载荷模式为 `formal_world_simulation_v15`。 | 用现有读取器导出有版本的通用快照。保留整数、标识、事件顺序和相互引用，验证迁移后继续运行的结果。 |

参考 [世界构建](../scripts/content/world_bootstrap.gd)、[世界推进](../scripts/simulation/simulation_step.gd)、[节点经济](../scripts/world/economy_r1_slice.gd)、[训练接口](../military_runtime/native/modules/isolated_training/README.md)、[地图批绘](../scripts/presentation/map/local_spatial_layer.gd) 和 [存档编码](../scripts/formal/formal_world_persistence_document.gd)。

## 资源和迁移顺序

R67 可执行文件约 2,241 MiB。封包目录中的地貌、城镇和战略地图分别约 869、772、272 MiB，合计占可执行文件约 85%。原样搬运资源时，主要磁盘成本也会搬过去。运行时预算另看解码后内存、显存、帧时间和功耗。

1. 在同一设备上，用相同路线、分辨率、画质和帧率上限测量拖动、缩放、静止及后台。分别记录帧时间、进程内存、显存、瞬时与后台功耗。现有记录尚未分清引擎、驱动和模拟的功耗。
2. 若瓶颈集中在 CPU 解码或几何处理，用 Rust 和 GDExtension 试换一个热点。若瓶颈集中在绘制提交、显存驻留或后台渲染，用 Rust 和 wgpu 做一段海岸地图的独立样机。可把 Bevy 作为 Rust 框架对照。
3. 若样机在相同工作量下稳定降低成本，再扩大迁移。Unity 和 C# 可作为完整 UI 与战术 3D 一起迁移的对照。先保持单一世界状态所有者和可读旧存档的迁移路径。

本次验证限于源码接线和 R67 封包。各迁移路线尚无同机对照数据。详细待办见 [性能预算](PERFORMANCE_BUDGET.md)。
