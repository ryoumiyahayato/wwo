# 当前正式运行架构

本文记录当前 Formal 产品已经存在的运行结构。旧 prototype / alpha 产品路径不属于本文的当前实现；文件仍存在不代表正式运行使用它。UI / HUD 固定布局原则是保留的产品约束，待调整项不表示已经实现。

## 正式入口与依赖方向

Godot 4.6.3、Compatibility。项目入口为 `scenes/formal/formal_world_menu.tscn`；`FormalWorldMenu` 进入 `scenes/formal/formal_world_main.tscn`，以 new / load 标记选择新世界或继续存档。菜单只检查存档是否存在，恢复由主场景中的 `FormalWorldApplication` 协调。

```text
Content 文件 → 解析 / provenance 校验 → 构建输入与只读显示内容
                                      ↓
WorldBootstrap → WorldState 中的运行组件
                         ├─ SimulationStep → 时间与领域推进
                         ├─ FormalPersistence → 保存 / 候选恢复
                         └─ 当前快照 / 只读 views + 已解析 Content
                                      ↓
                             FormalWorldPresenter → UI / Map
```

World、Simulation、Content 和 Persistence 不依赖正式 UI；Application 连接它们与场景。持久引用使用稳定 ID，当前世界事实由对应状态组件保存，显示数据不反向写入这些组件。

## 顶层组件职责

|组件|当前职责|
|---|---|
|`WorldState`|当前运行世界的组件引用集合。没有 simulation、文件读取、历史解析、UI、存档编码或领域计算方法。|
|`WorldBootstrap`|创建组件、初始化必要 Content / evidence、建立引用并校验初始组合；返回一次构建结果。安装时的 `prepare_presentation_content` 准备可复用显示内容，不参与每次 UI refresh、hover 或 selection。|
|`WorldBuildResult`|携带 world、success/error、operation、经济计算组件、SimulationStep、Persistence 和构建所需组织引用信息；不是长期运行状态。|
|`GameClock`|保存正式世界唯一累计时间 `_total_minutes`，提供小时、日期与分钟余量；日历从 1900-01-01 00:00 换算。|
|`FormalWorldEconomyState`|保存市场运行结果、shipments、routes、history、revision；准备只读输入查找、生成 detached 经济视图并保存/恢复经济 payload，不执行结算。|
|`FormalWorldEconomySimulation`|持有经济状态引用和路线算法索引；初始化开局库存/价格/路线，并按日计算生产、需求、消费、短缺、运输和贸易结果。|
|`SimulationStep`|按当前 GameClock → Spatial → Economy → Organization responsibility review 顺序推进；领域算法仍在各领域组件中。|
|`FormalPersistence`|snapshot、精确编码/解码、save/load、schema 检查、隔离 candidate restore/validation 和文件存储协调。|
|`FormalWorldApplication`|主场景启动、安装世界、signal 连接、接收 UI 请求、调用 Step/Persistence/Presenter、成功 load 后替换世界和刷新显示、协调地图显示生命周期。|
|`FormalWorldPresenter`|无成员状态的显示输入组装；调用期间从当前世界与已解析 Content 产生 copied records 和 detached views，不长期保存 WorldState、不修改世界、不读取历史原始文件。|
|Content|历史文件读取、解析、来源处理、地理/行政/证据/地图资料及按日期解析显示内容；可独立于 UI 使用。|
|Presentation|MainShell、页面、地图绘制和交互；保存页面、selection、hover、显示模式等局部状态，不保存或修改正式世界事实。|

Application 保存当前 `WorldState`、`SimulationStep`、`FormalPersistence` 和 Content 对象引用，不保存各领域第二份状态，不执行经济、组织或军事算法，也不是统一查询转发层。

其他组件中的已结算小时、上次处理时刻或 review 进度是处理进度，不是第二个世界时钟。`TimeControl` 只保存暂停和速度偏好；主场景 Timer 的 tick 发出分钟推进请求，不保存累计世界时间。

## WorldState 的实际组成

以下字段与 `scripts/world/world_state.gd` 一致；每个状态组件保存自身事实，WorldState 只保存引用。

|领域|实际字段与类型|
|---|---|
|时间|`game_clock: GameClock`|
|Provenance|`provenance: HistoricalProvenanceFoundation`|
|历史政治证据|`historical_evidence: HistoricalPoliticalEvidenceCatalog`；`historical_evidence_view: HistoricalPoliticalEvidenceView`|
|当前政治实体|`political_registry: RuntimePoliticalEntityRegistry`；`political_registry_view: RuntimePoliticalEntityView`|
|经济证据与人口输入|`economic_evidence: FormalWorldEconomicEvidenceCatalog`；`economic_static_view: FormalWorldEconomicStaticView`；`population_input_view: FormalWorldPopulationInputView`|
|市场|`market_registry: FormalWorldMarketRegistry`；`market_registry_view: FormalWorldMarketView`|
|经济运行|`economy_state: FormalWorldEconomyState`|
|空间 / place|`spatial_catalog: VNextSpatialCatalog`；`spatial_world: VNextSpatialWorld`|
|领土控制|`territory_state: TerritoryState`|
|人物|`person_overlay: VNextNamedPersonOverlay`|
|玩家|`player_state: VNextPlayerState`|
|组织|`organization_state: OrganizationState`；`organization_evidence: FormalWorldOrganizationEvidenceCatalog`；`organization_evidence_view: FormalWorldOrganizationEvidenceView`|
|组织职责评估|`organization_responsibility: FormalWorldOrganizationResponsibilityService`|
|权限|`authorization_check: AuthorizationCheck`|
|军事|`military_map: VNextMilitaryMapAdapter`；`military_state: VNextMilitaryState`；`military_service: VNextMilitaryService`|

`population_input_view` 是历史人口的只读输入，不是独立可变 Population state。当前没有独立正式 Relationship state，也没有独立 mutable Information state。政治实体 registry 和组织结构的存在，不表示已组合一个独立 Politics simulation。上述 VNext 前缀是实际组件类型名，不表示整个 vnext 目录都进入正式运行。

## 主要运行数据流

### BOOT：构建与安装

```text
Formal menu → Formal main / Application
→ WorldBootstrap.build → WorldBuildResult
→ Application._install_world → 当前 WorldState / Step / Persistence
→ prepare_presentation_content → map / pages refresh
```

经济构建路径为 WorldBootstrap → EconomyState.configure（绑定只读政治/市场/经济证据/人口输入）→ EconomySimulation.initialize_state → SimulationStep。计算组件由构建结果连接给 Step，WorldState 不保存它；MarketRegistry 仍是市场身份的唯一所有者。

主场景先建立一个新世界；load 模式随后调用存档恢复。安装保存的是构建结果中的运行组件引用，不把 WorldBuildResult 当成永久世界。地图 geometry 在安装时配置，日期相关显示由 Content 的解析方法取得。

### TIME：世界时间推进

```text
TimeControl.advance_requested
→ Application._advance_world
→ SimulationStep.advance_minutes
→ GameClock → Spatial → Economy → Organization responsibility review
→ Application → Content 日期解析 → Presenter → UI / Map
```

SimulationStep 将跨日推进分段处理：先把 Clock 推到日边界，再同步 Spatial、调用 FormalWorldEconomySimulation.settle_hour_range 修改同一 EconomyState，最后以该状态的结算后只读经济观察进行 Organization responsibility review。最后不足一日的完整小时按 Clock → Spatial → Economy 处理；不足一小时的分钟余量只改变 Clock。页面日期从 Clock 重新取得，地图在跨完整小时的刷新中重新解析日期相关内容。

当前未自动推进 Military，也没有在这条链中自动推进 NPC AI、Relationship 或独立 Politics simulation。

### SAVE：精确保存

```text
Application → FormalPersistence.save_to_user
→ snapshot → FormalWorldPersistenceDocument.encode
→ AtomicJsonFileStore 写 .tmp
→ 读取 / 解码 / candidate restore 与 validation
→ 替换正式文件，保留上一份 .bak
```

经济保存直接调用 EconomyState.get_persistent_state；嵌套 payload 仍为 `formal_world_economy_state_v6`，字段与数值类型不变（权威小时、静态/人口引用、market_states、shipments、shipment sequence、last_day_index）。计算对象和缓存不序列化；history 与 routes 的既有持久化处理不变。

存档路径为 `user://formal_world_1900.json`，snapshot schema 为 `formal_world_simulation_v12`。外层 JSON 使用 `formal_world_exact_variant_v1` 容器；snapshot 用 Godot Variant bytes + base64 保存，保留整数/浮点类型与精确浮点位，不经 JSON 数字解析重建运行数值。临时文件校验失败时不替换正式文件。

### LOAD：隔离恢复后替换

```text
Application → FormalPersistence.load_from_user
→ 文件读取 / exact codec 解码
→ WorldBootstrap 建立 candidate world
→ restore / schema、ID、引用、状态与时间一致性 validation
→ 成功的 WorldBuildResult
→ Application._install_world
→ 基于新世界重新准备 Content / 当前日期解析
→ Presenter → map / pages
```

Candidate 从 Bootstrap 得到已连接的经济状态与计算组件。Persistence 恢复 EconomyState，并用构建结果中的计算引用重新连接 Step；经济算法不进入 Persistence。恢复后读写同一状态，短缺投影缓存清空并按需重建。

失败 candidate 不替换当前运行世界。成功后 Application 校验原地图选择是否仍存在，必要时清除 polity/place selection，再安装新世界。Content 对象随安装重新准备，WorldPage 与 map 使用新世界日期和视图，不沿用旧世界的解析结果。

主存档的普通读取/恢复失败可尝试安全备份；明确的格式版本不兼容直接报告，不通过备份猜测迁移。不支持的规则版本也明确拒绝。

### DISPLAY：准备明确显示输入

```text
WorldState 的当前快照 / read-only views
 + Application 调用 Content.resolve_map / resolve_world_page 得到的已解析内容
→ FormalWorldPresenter → MainShell / pages / GlobeRenderer
```

经济读取路径为 Presenter → EconomyState 的 summary/read_only_snapshot → FormalWorldEconomyView → EconomyPage；Organization responsibility review 使用状态生成的窄经济观察。原输入缓存作为读取和结算共用的只读查找留在 State，短缺缓存表示已结算结果；路线索引仅在 Simulation。没有旧 Service 转发层，也没有第二份经济状态。

Presenter 从 player/person/place、political registry、economy、organization 组件取得当前数据，组装页面输入；地图 city/port records 来自当前 Spatial。当前日期只来自 GameClock。`CurrentWorldPoliticalProjection` 用当前 registry 的 ID 生成 polity/map records，再关联历史 metadata，不修改政治实体。

### DEFEND：直接调用领域服务

```text
DefendAction.execute
→ 当前 player/person、formation 与时间检查
→ AuthorizationCheck.resolve_authority（domain execution）
→ MilitaryService.defend（VNextMilitaryService）
```

Defend 使用明确传入的 Player、Person、Authorization、MilitaryState、Service 和 MapAdapter；不经过统一 World facade。这个行动调用路径不等于 Military 已加入自动时间推进，也不表示 MainShell 当前已有完整军事操作界面。

## Content 与历史资料

历史资料与当前运行状态分开：

|类型|含义|
|---|---|
|`HISTORICAL_EVIDENCE`|历史来源记录，包含来源、适用日期与范围。|
|`BOUNDED_ESTIMATE`|有明确范围、方法与不确定性的人口/经济等估计。|
|`GENERATED_SIMULATION_ASSUMPTION`|模拟生成所需假设，例如生成的人物基本身份；不伪装成历史事实。|
|`RUNTIME_FACT`|当前运行组件保存的事实。|
|`UNKNOWN`|未知值；`UNKNOWN != 0`，null 不补成 0。|

`HistoricalProvenanceFoundation` 读取现有 source registry / evidence catalog，校验 schema、唯一 ID、必需字段和 source binding；`HistoricalProvenanceGate` 比较结构化事实输入。正式 provenance generator 将基础身份、人口、CShapes 输入与 geography / authority / coverage 三个 supplement 一起生成 catalog。Supplement builders 只产生来源输入，不各自修改 catalog。

`FormalWorldEconomicEvidenceCatalog` 直接读取现有经济 manifest、country / transport 紧凑表、household budgets、coverage、commodity 与 crosswalk 输入，保留原校准、置信度、覆盖分类和 provenance。纯表展开及 admission 函数由旧 Alpha 数据测试读取方复用；正式构建不再创建 `AlphaHistoricalWorldEconomyData`，也不进入 Alpha simulation。

`VNextMilitaryMapAdapter` 从构建时提供的 `VNextSpatialWorld.catalog()` 读取节点、连接和地理记录，只额外读取军事语义 overlay。它保留军事路线成本与邻接索引，但不保存第二份城市、国家、区域或港口表，也不创建 `PrototypeV2Data`。运输容量即时读取同一 SpatialWorld 的当前基础设施状态。

安装使用 `HistoricalLoader` 组合 `GeographyLoader`、`AdministrativeLoader`、`EvidenceLoader` 和地图显示文档。`ContentDocument` 等读取历史文件；Content 负责 geometry、administrative profiles、flag evidence、来源及日期选择。日期相关显示通过 `resolve_map` / `resolve_world_page` 解析，不重新运行整个 WorldBootstrap。

Content 向 Presentation 提供三个用途有限的数据对象：

- `MapGeometryContent`：可复用的已解析地理 geometry。
- `ResolvedMapContent`：当前日期的 copied map units、display regions、resolved visual metadata 与可用 flag textures。
- `WorldPageContent`：当前选择 polity 的 profile、administration、完整 flag record 与按日期可显示的 texture。

这些对象通过复制提供记录，不保存 WorldState、HistoricalLoader、文件读取或世界修改能力。Texture 是已准备的显示资源。过期旗帜的 texture 不继续显示，历史 flag evidence 仍保留；缺失资料仍显示为缺失。

历史资料不能重新创造不在当前 runtime view 中的政治实体：`CurrentWorldPoliticalProjection` 从当前 registry 枚举，只为存在的 ID 关联 metadata。Content 可加入明确的 display-only 历史行政/地图记录，但它们不进入 runtime registry，也不成为新的游戏控制事实。

## Presentation 与地图输入

|组件|当前输入与职责|
|---|---|
|`MainShell`|copied date、Content errors、GlobeController、TimeControl 和页面输入；页面导航、系统操作请求与局部 UI 状态。|
|`PersonView`|copied person、place、current polity summary、memberships；人物当前处境显示。|
|`EconomyPage`（`economy_view.gd`）|polity/world summaries、detached economy view、selected ID；经济与市场显示。|
|`OrganizationPage`（`organization_view.gd`）|detached organization、evidence、responsibility views 与 player person ID；组织显示。|
|`WorldPage`（`world_view.gd`）|current polity/place records 和 WorldPageContent；地图资料卡、政治/行政观察显示。|
|`GlobeRenderer`|MapGeometryContent、Controller、detached political/evidence/economy views、city/port records、date、ResolvedMapContent；绘制地表、territory fill、borders、flags、markers 与 labels。|
|`GlobeController`|地图输入及 Renderer 的命中结果；orientation、zoom、selection、hover、map mode 与 labels。|
|`PoliticalLayer`|上述只读 views、place records、date、geometry/display content；组装显示面、边界、旗帜与高亮，不读取历史文件或重建当前政治状态。|

地图 projection、clip、camera、LOD 和 flag UV 属于既有显示算法，不决定运行世界事实。Presentation 不持有完整或可修改的 WorldState，不持有 HistoricalLoader，不直接读取 raw historical JSON，也不解释原始 provenance 或将历史记录转成当前状态。正常 shader、texture、font 和 scene 等 Presentation resource 加载不属于历史数据读取。

## 版本、完整性与运行状态指纹

程序/数据格式兼容使用已有 `schema`、`version`、`revision`、`rule_version`。正式 provenance 使用 `historical_source_registry_v2` / `historical_fact_evidence_catalog_v2`，存档保持 `formal_world_simulation_v12`。不支持的格式明确失败，内部 JSON 的 LF/CRLF、空白和字段顺序不表示不同版本。

Git SHA 只用于源代码历史和开发定位，不用于 runtime compatibility；内部 JSON SHA 也不用于 runtime compatibility。外部原始 archive、扫描、图片的 checksum 用于真正需要逐字节确认的文件完整性。

运行状态 hash / fingerprint 用于确定性测试、回归比较与诊断。部分 snapshot restore 还重算 state/reference fingerprint 校验当前状态与引用一致性；它们不是程序版本、数据格式版本或模块兼容关系。`FORMAL_WORLD_FINGERPRINT_SHA256`、`RUNTIME_POLITICAL_SNAPSHOT_SHA256` 等探针输出属于状态比较。遗留存档键 `rule_fingerprint` 当前保存已有的普通 `rule_version`，不再保存内部文件 SHA。

## 测试与验证

`tools/run_validation.ps1` 是当前正式统一验证入口：先检查指定 Godot 版本并 clean import，再执行数据生成/结构/引用检查、simulation regressions、save/load、长期模拟、Presentation / Content boundary、独立进程确定性状态比较和 headless product startup。Scene/resource 加载由 import、正式场景/资源测试和产品启动检查；测试范围以入口实际列出的 runners 为准，不把历史测试文件都称为当前正式套件。

负向测试可以按设计输出 ERROR。Godot tests 以退出码、现有 checks/failures summary 和引擎解析/加载错误判断；普通业务 ERROR 不覆盖明确通过的结果。非零退出、非零 failures、缺失有效 summary、SCRIPT ERROR、Parse Error 或真正 script/resource 加载失败仍失败。Import、启动和探针保持严格日志检查；Python tests / generator 保持非零退出检查。完整错误输出保留，不通过业务错误字符串白名单判断。

## UI / HUD 固定布局原则

以下是 WWO 重构与整合的产品约束；后续 UI 重构遵守，本轮仅记录，不修改界面实现。

- **左上角：国家 / 当前政治实体。** 当前人物与国家或政治实体存在适用关系时，可以显示国旗、国徽或政治实体标识等身份信息。
- **左下角：玩家人物。** 放置人物状态、当前活动、个人资源与相关快捷信息。
- **左侧发展方向：人物日程与个人侧栏。** 未来人物日程、任务、活动等优先从左侧发展。完整人物侧栏尚未实现，此处不提前设计或施工。
- **右上角：全局控制。** 时间、日期、速度、暂停、设置与系统操作归此区域。Personal Economy R1 已将现有日期、暂停、速度与系统操作移至右上；右下显示现有状态消息，左下保留给人物信息。
- **右下角：信息接收。** 消息、通知、事件提示、通信与信息提醒归此区域。
- **主要操作：左侧或顶部偏左。** 主要功能入口、人物相关入口与常用操作应符合大战略和策略模拟用户的基本操作习惯，不应为了视觉新奇系统性搬到右侧。右侧主要承载全局时间 / 设置与消息 / 信息反馈，不是主要菜单和人物操作的默认区域。

地图布局、页面导航、HUD 按钮及人物侧栏施工留给后续 UI 重构。
