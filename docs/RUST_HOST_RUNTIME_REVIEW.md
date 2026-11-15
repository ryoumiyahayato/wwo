# WWO Rust 游戏宿主运行核实 · 2026-11-15

## 结论

当前 Windows 正式游戏可以由 WWO 自研 Rust 宿主独立运行。宿主拥有应用循环、输入分派、地图和 UI、权威世界状态、模拟调度和持久化。winit 提供窗口及事件，wgpu 提供图形接口。当前 Windows 实测后端为 Vulkan。系统安装的 Vulkan 驱动和 VC++ 运行库也是实测依赖。

## Windows 实跑范围

- 当前桌面运行的是 "WWO-Country-Records.exe"。从当前发布目录逐字节核对副本，在同一台 Windows 11 的 AppContainer 中以 "--play --observe … --background" 运行该 EXE。文档中列出的 "WWO-Mechanical-Preview.exe" 用自己的数据另测至法国开局。
- 两个隔离包只有 EXE 和运行数据。启动环境未提供 Godot 或 R68 路径。进程令牌能读随包数据，读取现有 Godot EXE、R68 项目和旧主项目均返回 Windows 错误 5。监视了从创建到退出的进程和动态模块事件。三次正式运行各只有自身 EXE，未观察到 Godot 子进程、Godot DLL 或旧脚本宿主。
- 当前 EXE 实测法国新开局、地理／政治／经济／军事图层切换和区域缩放、打开 65 项报价的法国市场、买入 1.000 面包、巴黎工坊签约及登记工作。市场成交扣除 265，工坊两小时工资入账 6，现金从 2,500 变为 2,241。存档中的市场结算进度是第 51 小时。
- 原生手动档第 1 槽在 1900-01-03 03:00 保存。退出后以同一 AppContainer 身份重启，从大厅恢复人物 ID、现金、库存、合同和行动记录一致。恢复后时钟从第 3,060 分钟推进到第 3,090 分钟。测试使用独立档案。
- 测试使用现有 Windows 的系统和 GPU 驱动。未在从未安装过 Godot 的第二台 Windows、全新虚拟机或 Android 设备运行。

## 运行链和模块归属

| 环节 | 当前源码 | 归属 |
| --- | --- | --- |
| 启动、主循环、键鼠 | strategic-host/src/main.rs 的入口、Config、Host 和 ApplicationHandler；native_start.rs 的 NativeSession | WWO 宿主。winit 负责窗口和系统事件 |
| 地图和渲染 | render.rs、globe.wgsl、camera.rs、world.rs、map_release.rs、terrain.rs | WWO 地图投影、相机、专题图层、分片加载、GPU 驻留和 LOD。wgpu 提供表面、缓冲和渲染提交 |
| UI 与资源 | lobby.rs、formal_ui.rs、market_ui.rs、ui.rs、overlay.rs、hud.wgsl | 原生大厅、地图、存档、人物、财务及市场界面。Rust 读取随包地图、图集、PNG、JSON 和压缩数据 |
| 世界与人物 | native_start.rs → formal_bootstrap.rs 的 InitialWorld 和 advance_migrated_domains → formal_clock.rs、formal_character.rs、formal_work.rs、character-core | 一个正式时钟，人口与具名人物、履历、巴黎开局劳动合同与班次。地点目录和线路资料可以为后续接入复用 |
| 经济 | formal_macro.rs、formal_ledger.rs、formal_stock.rs、formal_wages.rs | Rust 权威市场结算、统计供需与货运、现场支付与库存、有限工资结算 |
| 存读档 | native_start.rs → formal_save.rs 的 write_native_slot、read_native_slot → WorldBootstrap::restore_native | 原生格式 wwo_rust_formal_world_v1，写临时文件并替换，恢复校验时钟、开局与领域状态 |
| R68 对照 | "--r68" → desktop_start.rs 的 DesktopSession → Godot 4.6.3 和 tools/formal_host_bridge.gd | 显式旧对照入口。旧场景、旧存档及 3D 训练继续走该路径 |
| 构建和旧数据 | build_hud.py、package_map_release.py、legacy_variant.rs、wwo-formal-state | 图集及地图打包使用已有素材和导出数据。Rust 可读取部分旧存档。素材来源和旧格式兼容属于数据依赖 |

## 内容兼容缺口

| 内容 | 可复用 | 待补 |
| --- | --- | --- |
| GLB／glTF、场景 | 现有窗口、渲染设备、图像解码、缓存、地图相机与本地项目的 GLB 原件 | 用 gltf 读取 mesh、节点、材质、skin 和动画通道。添加局部米制坐标、场景实例、资源异步加载及卸载。另行转换 Godot 的 .tscn、.tres、自定义着色器和粒子配置 |
| 3D 与 2D | 现有战略地球、HUD 图集、界面命中和输入分派 | 局部 3D 渲染通道、深度、相机、最小 PBR 和对象拾取。按局部 3D、特效、HUD 顺序合成 |
| 骨骼、材质、特效 | 资产原件及现有 wgpu 管线管理 | 蒙皮、动画采样与混合、材质贴图和透明排序。烟尘和粒子由模拟事件驱动，效果生命周期由渲染负责 |
| 物理、音频 | winit 事件与宿主调度 | 评估 Rapier 的固定步进、碰撞与控制器。评估 Kira/CPAL 的混音、空间音频和设备生命周期。音量配置已有，游戏音频运行链待接入 |
| Windows | 已验证 Windows x64 本地发布 EXE 和 Vulkan | 固定正式发布入口与数据清单。在干净 Windows 上复验 GPU 驱动和 VC++ 运行库条件 |
| Android | Rust 领域代码、WGSL 和数据协议可复用 | 平台层需接 Activity、触控、暂停恢复、应用目录和 APK/AAB 打包。当前原生会话和档案路径走 Windows 分支，当前地貌路径要求 BC。移动端需检验 ASTC／ETC2 或备用纹理方案，首先做 arm64 实机最小包 |

## 按依赖推进迁移

已核对的历史实现和第一批迁移范围见 [Rust 沙盒迁移基线](RUST_SANDBOX_MIGRATION_BASELINE.md)。

1. **冻结共用入口。** 两个沙盒继续有测试入口，共用正式领域模块和同样的命令接口。正式游戏给两个领域注入现有世界、人物和地点 ID。只有 GameClock 持有正式日期。局部物理可以细分固定步长，结果在已有世界推进边界提交。保存世界使用同一原生档案，载入时重建渲染、物理句柄和缓存。
2. **经济先做最短完整链。** 以巴黎工坊、面包坊和一个已有品类验证企业投入、工时、生产、卖方订单、发货、交割、入账、跨日和读档。复用现有账本、库存货批、需求、市场和工资。下一步移入企业权限及账户、配方／产能／损耗、报价与锁价、货运预留和分段交付、经营与人物决策。法国开局统计消费在企业接管范围内显式交接，避免重复扣库存或重复支付。经济库的 20 家企业研究用于核对行为，保留其历史校准和完整净利润的缺口。
3. **军事先接一段陆地训练。** 复用 R68 训练场、坦克和步兵资产与已有游戏规则。用一个米制场景验证地形碰撞、乘员上下车的同一人物 ID、虚构弹道与接触事件、命中后裁决、动画和特效。裁决经领域命令更新弹药、伤员和单位状态，渲染读取事件。同一条链再接正式编制、授权、部署和存档。舰船、飞机在资产和旧规则逐项确认后接入，共用渲染、事件和资源设施，分别添加水面与飞行行为。军事工作线的主机适配器、M v9/runtime v8 档案和 3D 训练仍需保留。
4. **平台与内容验证。** Windows 先证明上述两条局部流程与正式档案互通。Android 在资源体量扩大前验证窗口、触控、进出后台和存档，以及设备可用纹理格式。现有地图、窗口和 UI 继续作为宿主基础。

原 R68、Godot 工程、独立沙盒源码、模型和历史资产继续保留。本次只核实和记录，未迁入新玩法或更改发布 EXE。

[Microsoft AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer) · [glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) · [gltf crate](https://docs.rs/gltf/latest/gltf/) · [Rapier](https://rapier.rs/docs/user_guides/rust/getting_started/) · [Kira](https://docs.rs/kira/latest/kira/) · [wgpu 24 纹理能力](https://docs.rs/wgpu/24.0.5/wgpu/struct.Features.html) · [Android NDK Vulkan](https://developer.android.com/ndk/guides/graphics/getting-started)
