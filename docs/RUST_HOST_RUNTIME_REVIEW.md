# WWO Rust 正式游戏与迁移状态 · 2026-11-21

Windows 正式入口 `wwo-map-lab --play` 使用 Rust 的 `NativeSession`、`InitialWorld`、时钟、地图、UI 和存档。winit 提供窗口和输入，wgpu 提供图形接口。已归档的 Windows 实跑使用 Vulkan 驱动和 VC++ 运行库。R68 工程供对照及原始资产复用。Godot/R68 旧存档兼容已取消要求，工期从迁移清单移除。

## 2026-11-28 地图架构纠偏与五组施工

### 四项根因

1. 区域 Pack、QPK、QWG、QHW、QHL、QSC、QDT 和城市页叠加时，多个入口能决定同一处地表含义。城市水面盖住 QWG 会在页边、缩放接替和相邻城市产生冲突。
2. 手描 1890 年代岸线与现有现代底图的边界不同。重复描图只能逐城修补交界。旧静态摆放也未接入正式交通、厂房建设、战损或战斗用地。
3. 省界、行政读取和军事格依赖法国特判。`LandEdit[12]` 是固定容量的地表编辑显示。旗帜和政治调色仍依赖日期和静态资料，无法表达同一日的真实控制变化。
4. 月面分形噪声与近景普通建筑消耗 GPU 时间。实控疆界、市场归属和全球军事格是专题视图的主要内容。按模式决定细节和加载，使用同条件实机口径核对收益。

### 地图组交付

- **唯一水陆边界。** QWG 决定全球水陆边界。QPK 提供现有高程和坡度，QSC 等现有材质参与着色。禁止新增区域二进制补丁格式和城市私有水面覆盖。#253 只处理现有材质和着色器过渡，禁止新增局部高程读取。主线 #317 只改 `landscape.wgsl`，Z7 高程格距保持原值。 [#253](https://github.com/ryoumiyahayato/wwo/issues/253) · [#317](https://github.com/ryoumiyahayato/wwo/pull/317)
- **300 城共用入口。** #298 使用五项输入：冻结名录点、1900 开局人口规模及原来源纪年、区域风貌 Kit、正式铁路/港口/干道接入、QWG 岸线和 QPK 高程坡度。沿实际水岸布置港区和仓库，在真实铁路接入处布站场和工区。主次道路及街坊按人口扩展，在水面或陡坡处裁切和退让。缺输入时保留真实缺项。外缘预留工业和军事用地，保留稳定地块引用。少量独立地标沿用原模型，普通巴黎边缘模型迁出 EXE。停止新增逐城手描与私有水面。第六批旧候选保留复查，按新规核对后才能进入正式交付。 [#297](https://github.com/ryoumiyahayato/wwo/issues/297) · [#298](https://github.com/ryoumiyahayato/wwo/issues/298) · [#305](https://github.com/ryoumiyahayato/wwo/issues/305)
- **政治与经济同表。** owners 纹理保存固定二级政区 `u16` ID。先核定真实边界、ID 范围和未知码。CPU 原地更新 `admin_state[admin_id]`，记录实控政府组织、占领斜纹状态、中心市场、选定商品报价和渗透热力。提交后同帧更新选取、国界、省界、斜纹和重算范围的旗帜。开局史料使用日期，运行时按正式状态修订刷新。经济图读取同版本的市场和报价，复用 `transport_scene.rs` 的 FLOW、RESTRICTED、BLOCKED。移除法国专属索引、权限与尺度判断和固定 `LandEdit[12]`，保留地类事件的实际含义。全球二级历史边界和运行时控制记录目前未齐。 [#306](https://github.com/ryoumiyahayato/wwo/issues/306) · [#308](https://github.com/ryoumiyahayato/wwo/issues/308)
- **全球军事格。** 分带等距投影统一陆地与近海的 50／25／5 公里格。50 公里格含 2×2 个 25 公里格，25 公里格含 5×5 个 5 公里格，5 公里格含 5×5 个 1 公里战术格。地形、绘制、拾取、父子和边缘交接使用同一坐标定义。覆盖极区、180° 经线及带边，旧法国存档按原索引恢复。滚轮穿云时沿用同一战场身份和时钟。 [#307](https://github.com/ryoumiyahayato/wwo/issues/307) · [#316](https://github.com/ryoumiyahayato/wwo/issues/316)
- **专题帧时。** 政治、经济、军事视图优先用街廓底色、主干道、地标及玩法目标。普通立面和植被细节放在地理近景。固定机位、比例尺、前台与模拟状态，用既有方法分别复测静止和缩放平移。目标为大城市专题帧时低于 10 ms。实际显示间隔仍需同机授权会话。 [#309](https://github.com/ryoumiyahayato/wwo/issues/309)

### 五组共享接口与施工次序

| 组 | 可并行的第一项 | 对外接口 |
| --- | --- | --- |
| 1 地图与城市 | #298 接通 QWG、QPK 和名录的共用入口，同时推进全球格坐标、行政读取与专题细节 | `AdminId` 空间索引、城市地块与交通接入、军事格 ID 与边缘交付格。第七至九批分别生成 38／99／163 城，第十批核对正式组合。 |
| 2 组织与制度 | 核定正式政府的持续 `OrgId` 与现有组织、权限和资产关系 | 按状态修订发布实控、占领、渗透、任免与资产授权。政府主体和任职人分开。 [#313](https://github.com/ryoumiyahayato/wwo/issues/313) |
| 3 人口、市场、物流 | 衔接已有劳力、企业与货批，明确市场、设施与 `WaybillId` 映射 | 发布商品报价口径、节点归属、设施占地、运力及阻断原因。运单贯穿多个运力预约。 [#314](https://github.com/ryoumiyahayato/wwo/issues/314) |
| 4 人物、交涉、AI | 延用 `PersonId`、个人资产和组织权限查询，实现四类筹码的正式提交 | 提供人物任职、交涉、信用、承诺和继承的读写入口。组织与物流动作调用主责组。 [#315](https://github.com/ryoumiyahayato/wwo/issues/315) |
| 5 战斗与大头兵 | 明确连级 `UnitId` 与旧车辆身份映射，用第 1 组米格接现有战斗推进 | 发布人员和弹药、实控与地块损毁、补给交接。云层内外使用同一战斗状态。 [#316](https://github.com/ryoumiyahayato/wwo/issues/316) |

各组用独立短期分支和工作树。先冻结实际身份、保存字段、单位与接口提供者。`host`、`ui`、`render`、`formal_bootstrap`、`formal_step` 和正式存档的共用接线由整合负责人统一修改。组内先提交可验证的独立改动。正式联调使用现有运输事件和日界顺序，视图读取已提交状态，并复核失败回退、重试去重和存档恢复。

#298 共用入口验证后放行三个城市批次。各组使用同一输入版本和独立输出目录，整合端按 `city_id` 合并，复核相邻城市和共享设施。Windows 正式构建、实机窗口和 GPU 测量分时使用，共享 Cargo 缓存串行加锁。#296 至 #301 的 25,000,000,000 字节预算沿用原累计。正式提交、必需 CI 和运行资源按既有规则交付。 [#296](https://github.com/ryoumiyahayato/wwo/issues/296) · [#301](https://github.com/ryoumiyahayato/wwo/issues/301) · [#312](https://github.com/ryoumiyahayato/wwo/issues/312)

## 2026-11-24 整合基线

正式世界保持同一 `InitialWorld`、`GameClock` 和原生槽位。人口 v41 已入主线。人口分区查市场时保留正式统计归属，寻路仍使用已有物理接入点。意大利分区可按该归属查询市场。没有新增人口、货批或时钟。

| 系统 | 正式入口可用范围 | 未接入范围 |
| --- | --- | --- |
| 人口 | F7 和状态工具共用同一账本。按版本离线加载地域、年龄性别、社会边际、需求及未知人数。 | 部分地域缺可点选界线。广域匿名出生死亡和正式军队人员调用未接通。 |
| 经济 | 国家统计市场、报价与结算、企业货批、巴黎有限生产、工资及玩家交易共用正式账本。 | 完整产业批次成本、企业自主跨区寻源、旧经济沙盒开发授权未接通。 |
| 组织与人物 | 在地名册、成员和岗位、权限操作、经营活动、人物识字、收入与出行。 | 普遍组织生成与活动、家庭继承及科技项目未接通。 |
| 交通 | 客运、通勤、货运、迁移及宏观交割使用同一网络与运力。货批和预约随档恢复。 | 未细化地区保留路网缺口。签证、关税、兑换和完整历史班表未接通。 |
| 军事 | 法国 25／50 公里方格共享交战，演习车辆、弹药和战果随正式存档。 | 正式战略编制、人员损失入账、战略补给及多地同时交战未接通。 |
| 地图 | 地理、政治、经济和军事地图共用正式选择状态。海陆几何随对应地貌库加载。 | 全球资源产地和独立城市的专题覆盖不完整。 |

### 分支留存

| PR | 留存和处理 |
| --- | --- |
| [#250](https://github.com/ryoumiyahayato/wwo/pull/250) | 合入 v41。保留所有旧人口运行版本。 |
| [#241](https://github.com/ryoumiyahayato/wwo/pull/241) | 岸线和缩放源码已合入。Lynn Ø 七张 Z7 页在[受限资源草稿](https://github.com/ryoumiyahayato/wwo/releases/tag/untagged-717723abaf684f23b331)。 |
| [#125](https://github.com/ryoumiyahayato/wwo/pull/125)、[#121](https://github.com/ryoumiyahayato/wwo/pull/121) | 保留旧经济执行器、路径可见性及开发授权研究。节点网络已在后续旧同步分支延用。60 日期限与撤销仍有独有代码。 |
| [#126](https://github.com/ryoumiyahayato/wwo/pull/126)、[#127](https://github.com/ryoumiyahayato/wwo/pull/127)、[#77](https://github.com/ryoumiyahayato/wwo/pull/77) | 分别保留旧车组步兵连续、迁移资源和战略能力算法。各分支有独有文件，旧架构与现行 Rust 的存档和权限不兼容。 |
| [#122](https://github.com/ryoumiyahayato/wwo/pull/122)、[#123](https://github.com/ryoumiyahayato/wwo/pull/123) | Rust 观察模式及空闲调度替代旧 Godot 正式入口。候选反馈导出、旧省电比较和个别验收位置仍属保留资料。#123 依赖 #122。 |
| [#97](https://github.com/ryoumiyahayato/wwo/pull/97)、[#96](https://github.com/ryoumiyahayato/wwo/pull/96) | Rust 原生序章接管正式入口。旧多候选确认规则保留。OHM 快照证据保留，原始 PBF 不在 Git。 |

### 实跑与恢复

本轮 Windows `--play` 使用 v41 新局。F7 选择奥恩，人口 329,951。打开人物、组织关系、客运、货运和法国市场页面，法国市场显示 65 种商品。进入法国 25 公里军事格 `(0, -1)`，退出再进入，演习累计 5 步。F5 保存，F9 恢复该场演习。意大利人口分区的市场归属通过定向路网测试。交易和权限操作本轮未重跑。前一轮 v41 Windows 实跑已跨日，并恢复原生 v39 和 v40 存档。

从[构建与恢复](BUILD_AND_RECOVERY.md#构建与恢复)恢复代码和离线人口运行包。基础地图使用 [Windows 阶段归档](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115)，交通补充包见[交通归档](https://github.com/ryoumiyahayato/wwo/releases/tag/global-transport-1900-20261121)。Lynn Ø 修正 QWG 使用上表附件及其中的配套清单。原生候选在 48 米/像素载入视野所需的 9 页。归档文件已上传，本轮远端大文件回读中断，冷恢复未完成。七大洲验收本轮未运行。

本机验证使用固定工作树和共享 Cargo 缓存。旧工作树及用户存档保持原位。旧地貌树的 28 个改动文件可从[源码归档](https://github.com/ryoumiyahayato/wwo/tree/acbb72a5ba4d094c4d79ae2dfcec59d18bfdc37b)恢复，五个文件有行尾差异。[地貌附件](https://github.com/ryoumiyahayato/wwo/releases/tag/terrain-surface-20261115)保存相关 QDT、QPK 和耕地试制包。其他未发布试制文件仍在原工作树。

## Windows 实跑范围

以下记录对应 2026-11-15 的 Windows 实跑。阶段源码、运行附件和云端回读状态见 [Rust Windows 阶段归档](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115)。主线后续修改以 `main` 的提交为准。

- 当日的 `WWO-Country-Records.exe` 在 Windows 11 AppContainer 内以 `--play --observe … --background` 运行。`WWO-Mechanical-Preview.exe` 用自己的数据另测至法国开局。
- 两个隔离包只有 EXE 和运行数据。启动环境未提供 Godot 或 R68 路径。进程令牌能读随包数据，读取现有 Godot EXE、R68 项目和旧主项目均返回 Windows 错误 5。监视了从创建到退出的进程和动态模块事件。三次正式运行各只有自身 EXE，未观察到 Godot 子进程、Godot DLL 或旧脚本宿主。
- 当日 EXE 实测法国新开局、地理／政治／经济／军事图层切换和区域缩放、打开 65 项报价的法国市场、买入 1.000 面包、巴黎工坊签约及登记工作。市场成交扣除 265，工坊两小时工资入账 6，现金从 2,500 变为 2,241。存档中的市场结算进度是第 51 小时。
- 原生手动档第 1 槽在 1900-01-03 03:00 保存。退出后以同一 AppContainer 身份重启，从大厅恢复人物 ID、现金、库存、合同和行动记录一致。恢复后时钟从第 3,060 分钟推进到第 3,090 分钟。测试使用独立档案。
- 测试使用现有 Windows 的系统和 GPU 驱动。未在从未安装过 Godot 的第二台 Windows、全新虚拟机或 Android 设备运行。

已有后续正式运行记录包括法国序章、识字和重启恢复，以及 Z6–Z7 地面材质、景观和水域接替。水文记录列出了实际分片、回退、残余岸线问题和海面动态样本。各记录对应其当时的 EXE 和运行数据。 [人生序章](../rust/strategic-host/README.md#人生序章与人物存档) · [Z6–Z7 实跑](../rust/strategic-host/Z6_Z7_SURFACE.md) · [水文实跑](../rust/strategic-host/WATER_HANDOFF.md)

2026-11-21 的 #192 已进入主线。Windows 法国开局在巴黎买 1 千克面包后，现金从 2500 降到 2498。完成班次后，6 点工资到账。巴黎至里尔的途中存档在重启后继续计时，抵达后可登记迁居。 [正式人口与生计](https://github.com/ryoumiyahayato/wwo/pull/192)

同日合入的 #193 在 Windows 正式入口验证了巴黎至鲁昂途中存档恢复、经勒阿弗尔赴伦敦的路线查询、实物货批交割与销售、鲁昂至巴黎往返通勤及到岗登记。法国各站使用同一个统计市场，路网仍使用原型资料。 [正式交通](RUST_TRANSPORT_PHASE_2.md) · [PR #193](https://github.com/ryoumiyahayato/wwo/pull/193)

同日用后台正式入口在特鲁瓦点选 50 km 格 `(2, -2)` 和 25 km 格 `(5, -3)`。从 25 km 格进入，正式 Z7 高程上出现 20 辆车。手动开火使所选车辆弹药从 12 减至 11。RTX 3050 Laptop GPU、Vulkan、1280×720，20 辆车在场时车辆视角观测到约 58 FPS。交战推进 39.75 模拟秒后红方胜出。蓝方损失 10 辆，红方损失 8 辆、余 6 发。返回世界后保存手动档和退出自动档。重启从自动档恢复，再进入原 50 km 格，记录的战果、命中、弹药和格号一致。其他地区及更高负载仍待核验。

组织经营阶段的正式窗口记录了玩家向伦敦燃料商行追加 1,000 生丁，以及该商行的 1 吨煤运抵巴黎。货款 85 生丁，运费 144 生丁。巴黎市场实收资金不足，货批留在巴黎。另一次开局中，互助会介绍的柜台雇员完成一小时工作，次日收到 3 生丁工资。[组织操作与窗口截图](organization-life/README.md)

## 运行链和模块归属

| 环节 | 当前源码 | 正式游戏状态 |
| --- | --- | --- |
| 宿主 | `main.rs` → `native_start.rs` | Rust 应用循环、窗口、输入、正式世界和存档 |
| 地图和渲染 | `render.rs`、`globe.wgsl`、`terrain.rs`、`hydrology.rs`、`landscape.rs` | 地图投影、专题图层、地貌和水域按视野加载、景观 GPU 实例和 LOD |
| 静态 3D | `landmarks.rs`、`landmark.wgsl` | 七个地标，巴黎和伦敦共三个局部街区。内嵌 GLB、按视野解码及上传、深度和两档网格 |
| 装甲陆战 | `land_battle.rs`、`battlefield_terrain.rs`、`battle_view.rs`、`battle_render.rs` | 正式法国 Lambert-93 网格已实测选格、入场和手动开火。采用 Z7 QPK 粗高程及通用车辆。源码已有 20 辆车、四个编队、近景操控、20 Hz 模拟、地面碰撞、AI、战果及原生持久化。法国 4 米高程未覆盖 |
| UI 与人物 | `lobby.rs`、`prologue_ui.rs`、`formal_ui.rs`、`formal_character.rs`、`formal_work.rs` | 六国序章、履历、识字、休息和有限病伤处理、死亡与人口归属更新。玩家可查询在地组织、接受岗位介绍、应聘并登记班次 |
| 组织与经营 | `formal_organization_registration.rs`、`formal_organization_activity.rs`、`formal_counter.rs` | 六城开局共七家模拟企业、六个互助会。其他符合人口、市场及需求条件的城市在具名乘客到达后登记。巴黎按缺料和授权采购，商号按客户准备金和实际班次交货。企业账户承担购货与运费 |
| 世界与生计 | `formal_bootstrap.rs`、`formal_livelihood.rs`、`formal_enterprise.rs`、`formal_household.rs` | 同一时钟处理统计供需与货运、现货与货批、班次与工资、巴黎有限原料生产与口粮、共同住户和迁居 |
| 交通 | `formal_travel_live.rs`、`formal_freight.rs`、`transport/operations.rs`、`transport_scene.rs` | 逐段旅行、通勤和实物货运使用同一套线路预约。支持中途下车与退款、货批交割和市场回购。地图车辆由正式运输事件驱动。原生档恢复在途状态和预约 |
| 原生存档 | `native_start.rs` → `formal_save.rs` → `WorldBootstrap::restore_native` | `wwo_rust_formal_world_v1` 槽位。手动保存、保存并退出、重新启动后恢复 |
| R68 对照与维护 | `--r68` → `desktop_start.rs` → Godot 4.6.3。独立 `wwo-formal-state` 含旧格式维护命令 | 对照及离线维护。正式入口使用 Rust 世界和原生槽位 |

## 施工顺序和依赖

下表以已核对的正式入口和可复用代码估算工程量。资源来源核对、目标机性能和历史资料缺口会影响工期。空战沿既有 Rust 工作线推进。 [经济和军事历史实现](RUST_SANDBOX_MIGRATION_BASELINE.md) · [交通基础](RUST_TRANSPORT_PHASE_1.md)

| 顺序 | 剩余能力与当前实现 | 首个可验范围及依赖 | 估算 |
| --- | --- | --- | --- |
| 1 | 正式网格陆战。特鲁瓦 20 车入场、开火、AI 结算与原生重启恢复已实测 | 在 `--play` 复验持续驾驶、跨格入场边界、资源分发和恢复 | 2–4 人日复核其他格并修正发现的问题 |
| 2 | 扩大陆战。现有同一世界内的通用装甲编队。R68 有战略编组、部署、补给和训练步兵 | 先以实际目标机约 30 FPS 为目标调地形加载、实例绘制和模拟步进。再把网格战场接入正式军队编制、部署、补给和世界结算，随后接独立火炮与步兵 | 4–8 人日到装甲负载复验。战略接入、火炮和步兵另估 10–20 人日 |
| 3 | 空战和海战。空战已有独立 Rust 工作线 | 正式世界接入依赖共享单位身份、状态、弹药和结算接口。空战沿用现有成果。海战需水面行为、载具和地图数据 | 空战接入和海战原型分别在确认接口及资源后估算 |
| 并行 | 全球水域、海洋和 Z5–Z7 陆地。已有 QWG、共用海面材质、农田地表及实例 | 按原区段覆盖收敛余项。先查水域分类与回退，后验海面动态，再查材质和近景接替。依赖统一水陆边界、共用材质和高程。农田覆盖全球适用区域 | 4–8 人日复查水文和动态。陆地按跨级实拍分批估算 |
| 随后 | 约 1900 年人口达到 10 万的城市。已有地标及巴黎、伦敦局部街区 | 先整理年份、统计范围、来源和地理边界。按道路和城市范围部署可复用住宅、公共、工商业、铁路和外围模型 | 城市名单与可用几何明确后按批估算 |
| 随后 | 交通、企业和人口。已有客货预约、通勤、企业自有货批跨区交付、巴黎有限生产、住户与迁居 | 企业自主跨区寻源、城市级市场和更多地区人口待扩展。路网与班表待历史资料，跨境交易待签证、关税和兑换规则 | 跨区域覆盖按资料来源另估 |
| 随后 | 人物、组织、政治和设置。已有序章事件、六城工作与组织身份、人口归属、国家和部分行政资料、音量与语言设置 | 完善医疗、继承、更多行业的岗位与活动、政治组织和动态权属。音频需原生播放及混音 | 各能力验明范围后分批估算 |
