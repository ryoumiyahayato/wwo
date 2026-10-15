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
|`SimulationStep`|按当前 GameClock → Spatial → Economy → Organization responsibility review → 已到期工资结算 顺序推进；领域算法仍在各领域组件中。|
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
|正式可变人口|`population_state: FormalWorldPopulationState`|
|市场|`market_registry: FormalWorldMarketRegistry`；`market_registry_view: FormalWorldMarketView`|
|经济运行|`economy_state: FormalWorldEconomyState`|
|空间 / place|`spatial_catalog: VNextSpatialCatalog`；`spatial_world: VNextSpatialWorld`|
|领土控制|`territory_state: TerritoryState`|
|人物|`person_overlay: VNextNamedPersonOverlay`|
|账务与生计|`ledger_state: FormalLedgerState`；`personal_economy_state: FormalPersonalEconomyState`|
|玩家|`player_state: VNextPlayerState`|
|组织|`organization_state: OrganizationState`；`organization_evidence: FormalWorldOrganizationEvidenceCatalog`；`organization_evidence_view: FormalWorldOrganizationEvidenceView`|
|组织职责评估|`organization_responsibility: FormalWorldOrganizationResponsibilityService`|
|权限|`authorization_check: AuthorizationCheck`|
|军事|`military_map: VNextMilitaryMapAdapter`；`military_state: VNextMilitaryState`；`military_service: VNextMilitaryService`|

`population_input_view` 是历史人口的只读输入，`population_state` 保存正式可变人口。当前没有独立正式 Relationship state，也没有独立 mutable Information state。政治实体 registry 和组织结构的存在，不表示已组合一个独立 Politics simulation。上述 VNext 前缀是实际组件类型名，不表示整个 vnext 目录都进入正式运行。隔离的 `VNextWorldRuntime` 不是正式产品根。

## 主要运行数据流

### BOOT：构建与安装

```text
Formal menu → Formal main / Application
→ WorldBootstrap.build → WorldBuildResult
→ Application._install_world → 当前 WorldState / Step / Persistence
→ prepare_presentation_content → map / pages refresh
```

经济构建路径为 WorldBootstrap → EconomyState.configure（绑定只读政治/市场/经济证据/人口输入及正式人口状态）→ EconomySimulation.initialize_state → SimulationStep。计算组件由构建结果连接给 Step，WorldState 不保存它；MarketRegistry 是市场身份的唯一所有者。市场由实际经济输入集合建立，状态和恢复引用必须覆盖对应市场身份，不要求恰好 50 个。

主场景先建立一个新世界；load 模式随后调用存档恢复。安装保存的是构建结果中的运行组件引用，不把 WorldBuildResult 当成永久世界。地图 geometry 在安装时配置，日期相关显示由 Content 的解析方法取得。

### TIME：世界时间推进

```text
TimeControl.advance_requested
→ Application._advance_world
→ SimulationStep.advance_minutes
→ GameClock → Spatial → Economy → Organization responsibility review → 已到期工资结算
→ Application → Content 日期解析 → Presenter → UI / Map
```

SimulationStep 将跨日推进分段处理：先把 Clock 推到日边界，再同步 Spatial、调用 FormalWorldEconomySimulation.settle_hour_range 修改同一 EconomyState，再以结算后只读经济观察进行 Organization responsibility review，并处理到期工资。最后不足一日的完整小时按 Clock → Spatial → Economy 处理，随后处理到期工资；不足一小时的分钟余量不触发经济小时结算。页面日期从 Clock 重新取得，地图在跨完整小时的刷新中重新解析日期相关内容。

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

存档路径为 `user://formal_world_1900.json`，snapshot schema 为 `formal_world_simulation_v15`。外层 JSON 使用 `formal_world_exact_variant_v1` 容器；snapshot 用 Godot Variant bytes + base64 保存，保留整数/浮点类型与精确浮点位，不经 JSON 数字解析重建运行数值。临时文件校验失败时不替换正式文件。

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

`FormalWorldEconomicEvidenceCatalog` 直接读取现有经济 manifest、country / transport 紧凑表、household budgets、coverage、commodity 与 crosswalk 输入，保留原校准、置信度、覆盖分类和 provenance。Alpha 旧读取宿主及其专用测试已删除；data/alpha 中仍被该 Catalog 读取的数据继续保留。

`VNextMilitaryMapAdapter` 从构建时提供的 `VNextSpatialWorld.catalog()` 读取节点、连接和地理记录，只额外读取军事语义 overlay。它保留军事路线成本与邻接索引，不保存第二份城市、国家、区域或港口表。运输容量即时读取同一 SpatialWorld 的当前基础设施状态。旧 Prototype 加载器已删除。

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
|`MainShell`|当前 GameClock 日期、Content errors、GlobeController、TimeControl 和页面输入；页面导航、系统操作请求与局部 UI 状态。|
|`PersonView`|当前人物、所在地、成员与职务、个人经济、账户收支及财产/生活记录；处境、账务、持有与消费操作请求。|
|`EconomyPage`（`economy_view.gd`）|polity summary、detached economy view、selected ID 与当前市场的商品页与个人购买报价；国家/统计经济、数量输入与购买请求。|
|`OrganizationPage`（`organization_view.gd`）|由当前组织、身份依据、地点与职责只读记录组装的行；列表、详情及明确引用导航。|
|`WorldPage`（`world_view.gd`）|current polity/place records 和 WorldPageContent；地图资料卡、政治/行政观察显示。|
|`GlobeRenderer`|MapGeometryContent、Controller、detached political/evidence/economy views、city/port records、date、ResolvedMapContent；绘制地表、territory fill、borders、flags、markers 与 labels。|
|`GlobeController`|地图输入及 Renderer 的命中结果；orientation、zoom、selection、hover、map mode 与 labels。|
|`PoliticalLayer`|上述只读 views、place records、date、geometry/display content；组装显示面、边界、旗帜与高亮，不读取历史文件或重建当前政治状态。|

地图 projection、clip、camera、LOD 和 flag UV 属于既有显示算法，不决定运行世界事实。Presentation 不持有完整或可修改的 WorldState，不持有 HistoricalLoader，不直接读取 raw historical JSON，也不解释原始 provenance 或将历史记录转成当前状态。正常 shader、texture、font 和 scene 等 Presentation resource 加载不属于历史数据读取。

## 正常解析与保存约束

存档格式保持 `formal_world_simulation_v15`。正常格式检查、解析错误返回、候选恢复与权威状态约束保留。内部地图资源不以哈希或逐字节对齐作为加载条件。没有组件注册表或启动版本互锁。

内部存档指纹绑定尚未清除。Population、Person、Personal Economy、Market、Organization 等组件仍在保存或恢复中比较来源、规则或状态指纹，部分绑定约束存档与当前输入的匹配。不能将这些依赖描述为仅有诊断用途。本轮保留其字段与恢复行为，完整快照字段见 [存档格式](SAVE_FORMAT.md)。

跨进程哈希探针、旧系统审计工具、审计文档同步门禁和提交号版本盖章已删除。LandTopology 的附加计时统计、TerritorySourceRegistry 的测试审计报告、Military 的夹具控制权注入分支已删除。土地拓扑、来源解析与入场条件、战斗控制变更和世界状态继续保留。`tools/run_validation.ps1` 保留为批量工具，不是每次修改的默认步骤。

## 当前 UI 调用

`FormalWorldApplication` 接收 MainShell 的实际请求；定位调用 GlobeController，经济与组织入口只改变页面观察对象。Application 在世界内容变化后更新只读显示快照，地图选择和返回页面复用这些快照。日期仍从 GameClock 读取。

MainShell 在当前正式场景中绘制四角 HUD 和有边界的现有页面。人物所在地政体与地图浏览对象分别显示。人物账务只读 Ledger 的账户分页记录，打开页面不初始化就业或结算工资。工资反馈只关联当前人物的已有工资交易。

当前地图主界面通过正式场景的 HUDMargins/HUDLayout 取得锚定边距。MainShell 使用单行顶部状态条、左侧互斥工具/上下文卡和底部两角概况。既有 GlobeController 保存土地叠加偏好与有限对象返回历史；GlobeRenderer 读取现有 LandTopology 的活动几何、拾取和相邻引用，不创建土地身份。行政名录选择保存在 WorldPage 的已有行政选择字段中，未提供边界的行政对象只显示资料卡。

HUD 避让矩形由 MainShell 在需要绘制时提供，既有世界/区域文字碰撞处理读取这些矩形。没有独立 UI 调度、导航或缓存服务。StrategicSpatialLoader.request 返回当前范围是否有有效请求；Renderer 在空范围或内容错误时清除旧显示，LocalSpatialLayer 仅保留当前完成的显示批次直到替换完成。详细入口、文件清单和未完成资料见 [UI 说明](UI_INFORMATION_ARCHITECTURE.md)。

地图在窗口背景中使用现有 WORLD / REGION 两个缓存视口。现有水系批次在需要的尺度发起区域请求，在对应视口间转移；相机滞回不再成为首次水系请求的前置条件。活动分片可复用解析结果，过期请求取消。新 LOD 完整后替换上一档，空结果也完成交接。字号缓存复用现有嵌入字体。

本批当前状态、数据缺口、长期待办和此前被拒绝删除的缓存路径集中在 [当前 UI 与任务状态](UI_INFORMATION_ARCHITECTURE.md)。旧独立审计与设计稿不作为当前入口指导。本批仅保存实现，未运行检查、试跑或测量。

## 个人购买与消费

Application 从既有玩家身份取得 person_id，将购买、消费及每日安排请求交给 FormalPersonalEconomyState。UI 只保留数量与选择草稿，读取报价，不修改世界状态。核心操作接受任何已有个人账户及所在地引用的人物 ID，不包含玩家专用库存或特权判断。

PersonalEconomy 通过现有 Population 的地点映射确定可访问的统计市场。EconomyState 将现有市场身份明确作为模拟存货保管主体，按原价格出售原库存；首次相关交易开立 Ledger 的零余额 market_receipts 账户。Ledger 保存唯一现金余额，执行 purchase 付款与收据。PersonalEconomy 保存独立的持有批次和生活记录，消费实际扣除物品；购入和消费记录通过同一 reference_id 对接账务。

SimulationStep 在既有日边界与下一笔有效生活安排边界之间推进同一 GameClock。日边界按原经济结算与组织观察、工资、个人安排顺序处理。每日安排缺物品时按当前条件购买差额，失败留下原因，不补生成物资。下一到期时间是安排的派生索引，不是第二个时钟或任务队列。

内部存档指纹、旧运行容器与其他经济算法不在本批清理范围。生产、宏观消费、采购与运输计算没有重写。具体零售商、所在地仓库和配送仍缺；本批交易不得解释为历史城市店铺数据。

## 原生经济中的人物旅行与运行中扩容（2026-10-12）

正式默认经济不变。有限原生企业和区域开发网络仍须显式启用。研究经济工作树本轮只作参考，没有同步修改。

`WorldState.person_travel` 引用 `FormalPersonTravel`。旅行使用宿主 Spatial 的实际连接和有效容量；旅客许可、分钟数、座位、票价、收款账户和携带范围来自显式开发配置。货运线路不会自动授予旅客资格。开发线路目前覆盖巴黎、里昂、马赛；票价与旅行时间不是历史票务资料。旅行按明确旅客许可跨统计单元活动，不自动变更常住人口归属；常住迁居使用独立迁居行动。人物覆盖层的 `current_place_id` 仍是唯一地点事实；在途时该字段是最后节点，`is_at_place` 返回不可出勤。每段到期由 `SimulationStep` 在同一 GameClock 上处理，抵达节点通过覆盖层 `relocate` 写入；中段受阻保留实际节点并等待。旧隔离运行容器的旅行服务没有接入正式结算。

已知异地岗位可经 `LivelihoodAction` 申请。合同不代替到达。登记劳动需要实际位于工作地点和足够剩余时间；已有劳动登记占用到日结，不允许同时离开。工资仍由原劳动记录形成。当地经营信息只在到达后按显式公告内容进入原消息与收据，既有知识保留。NPC迁移须配置 `person_travel.npc_policies`，默认为空；政策比较已知岗位、本币工资、实际现金、费用和时间，不增加资金。

到货后等待本人的批次仍由原 shipment 保管，地点锁定于原订单。`collect` 整批领取需要本人实际在场。原 `batch_payment` 同时完成货款、运输款和预留释放；随后减少在途责任、增加原生个人库存并登记来源。receipt 新增实际 `delivered_minute`，明确领取还引用 `collection_action_id`。旧 receipt 缺分钟时保持原日结语义。待领取货物不能消费，已取得持有随本人继续存在；工业物资和超出携带配置的物品不能用旅客旅行搬运。

`expand_scope` 追加人物、非重叠cohort、企业、地点、岗位及运输配置；`expand_configured_scope` 选择预先声明的开发扩容条目。权限使用既有有限企业管理关系。请求在旧原生与宏观当日日结完成后生效，首次未来消费从下一完整日开始。新增人物引用现有账户；新开账户为零余额。新增cohort、企业和地点不得附带新发现金或库存。新企业需引用已有商业组织；已有公司账户缺少责任承接规则时延后。新主体的生活类别须有明确的供应与路线关系。

旧工资关系、旧商品映射、生活安排或预留缺少承接规则时，人物接管延后。账户准备或人口范围发布失败保留原归属。历史订单、工资、股份与资金不重新初始化。企业暂停仍走原经营状态行动。`request_scope_exit` 保留原主体及未结责任；旧宏观尚无库存、合同和股份接收接口，因此目前退出只记录延后原因，没有清算或任意双向迁移。

本轮完成相关 Godot 解析；首次解析发现新类注册和类型推断问题，修复并注册后，正式行动入口解析未报错。未运行经济情景、回归或性能测量；业务运行结果尚未确认。

本批源码位置（相对正式工程）：

| 职责 | 文件 |
| --- | --- |
| 新增旅行状态 | `scripts/world/formal_person_travel.gd` |
| 人物位置与世界引用 | `scripts/vnext/population/named_person_overlay.gd`、`scripts/world/world_state.gd` |
| 组合、配置与时间 | `scripts/content/world_bootstrap.gd`、`scripts/content/economy_development_config.gd`、`scripts/simulation/simulation_step.gd` |
| 原生业务与范围 | `scripts/world/economy_r1_slice.gd`、`scripts/world/economy_slice_config.gd`、`scripts/world/formal_world_population_state.gd` |
| 个人持有与账务种类 | `scripts/world/formal_personal_economy_state.gd`、`scripts/world/formal_ledger_state.gd` |
| 页面行动和只读显示 | `scripts/formal/formal_world_application.gd`、`scripts/presentation/formal_world_presenter.gd`、`scripts/presentation/ui/person_view.gd`、`scripts/presentation/ui/economy_view.gd` |
| 原存档接线 | `scripts/persistence/formal_persistence.gd` |

行动继续复用原 `scripts/actions/livelihood_action.gd`。接口与保存说明分别更新在本文件、`docs/SAVE_FORMAT.md` 和 `docs/UI_INFORMATION_ARCHITECTURE.md`，没有新建报告或验收脚本。


## 同目录续接：旅行与区域接管（2026-10-12）

两个聊天使用同一正式目录。这里保留已完成的 FormalPersonTravel 接入，并继续修改既有代码。没有复制研究经济工作树。

SimulationStep 先完成实际位置推进，再使原生日游标到达正式边界，随后发送到达回调。午夜领取的 delivered_day、delivered_minute、Ledger 付款和个人来源保持同一时间。NPC到达后可依据合法已知岗位登记当天剩余时间内的工时；未结束的旅行不能登记劳动。当地实际岗位版本通过 local_notice 收据进入既有知识，远程消息不覆盖更晚取得的版本。

区域新世界组合生成有限的配置选择：已有宿主人物、未重叠背景人口，以及同一企业在另一已有地点的开发经营单元。新增资源为零；经营能力、岗位和初始经营偏好仍明确标为开发参数。不会创建历史企业或人物。运行中扩容可提供 route_knowledge 的 actor/route_id，来源必须是申请人或其管理企业已经知道的路线；它只增加路线知识，不复制运力或库存。新增商业企业仍须有宿主 Organization。正式默认范围不变。

公开的开发旅客线路可标记 public_notice=true。在场人物可以获知本站已声明的线路；私有许可不自动开放。费用使用原 Ledger 的 person_travel，双向旅客线路共享源连接的座位占用。携带资格同时检查原持有和原生持有。缺少物品承载规则时保持拒绝，不删除持有。

候选恢复检查原生旅行付款批次与正式行动，再由 FormalPersonTravel 检查原路线、费用、收款方、所在地、阶段和完成记录。scope_requests 与接受行动、subject_activation 相互引用。缺少旅行状态却保留旅行行动或付款的存档不能安装。加载不重放旅行、接管、工资、领取或消费。

人物页保留原布局，增加岗位及订单翻页、可用工时、范围与企业控制区。暂停/恢复和退出请求仍由 LivelihoodAction 进入原业务。企业库存、承诺与岗位只展示本人有管理权限的经营地点。退出因缺少旧宏观接收责任的接口而继续延后，不删除原归属。

本次续接修改的源码：

- scripts/world/formal_person_travel.gd
- scripts/simulation/simulation_step.gd
- scripts/world/economy_r1_slice.gd
- scripts/world/formal_personal_economy_state.gd
- scripts/vnext/population/named_person_overlay.gd
- scripts/content/world_bootstrap.gd
- scripts/content/economy_development_config.gd
- scripts/persistence/formal_persistence.gd
- scripts/formal/formal_world_application.gd
- scripts/presentation/formal_world_presenter.gd
- scripts/presentation/ui/person_view.gd
- scripts/presentation/ui/economy_view.gd
- scripts/presentation/ui/main_shell.gd

接口说明同时更新本文件、docs/SAVE_FORMAT.md 和 docs/UI_INFORMATION_ARCHITECTURE.md。研究工作树只读。没有新增验证脚本或报告。


## 跨统计单元活动与个人物资空间状态

人物常住统计归属由 FormalWorldPopulationState.named_person_units 和覆盖层 population_territory_id 保留。FormalPersonTravel 沿已配置旅客许可引用真实 Spatial 连接；relocate 只改变覆盖层 current_place_id。跨统计单元临时旅行不改国家总人口、常住消费排除范围、账户或原生接管关系。岗位申请仍依赖已知岗位，出勤仍依赖实际到达与剩余工时；工资使用原合同币种。

EconomyR1Slice 的人物 stock 表示已取得且尚未消费的所有权总量。个人 v3 的同一来源批次用 positions 将 remaining 分配为 CARRIED、STORED|place_id、FREIGHT|order_id；分配之和等于批次数量。CARRIED 的位置引用宿主人物，STORED 只在人物实际在场时可用，FREIGHT 只引用原订单和 shipment 的保管责任。personal_inventory 是当前位置可用量；personal_owned_inventory 是所有权总量。消费、耐用品需要和旅客携带检查使用相应可用部分。

personal_storage 是明确开发配置的经营地点保管许可，不是历史仓库资料。store_goods / withdraw_goods 不改变物主或企业库存。send_personal_goods 创建 PERSONAL_FREIGHT 原生运输订单，占用原 FIFO 批次并预留实际承运费；复用原调度、1–8 段路线、边与节点容量。货物到达后等待本人领取，未发部分取消回原保管地点。在途和待领个人货运始终属于同一人物，不生成卖方收入。

collect 可指定数量及 CARRIED / STORED。原 shipment 保留余量，每次领取产生可追溯 receipt。现有合同货款与各段运费均为锁定的整数单位金额，累计应结金额差额确定本次付款；全部领取后总额精确相等。没有新增固定票务或仓储收费合同。所有行动仍经 LivelihoodAction 与原命令去重表，所有到期仍经原 SimulationStep。

默认旧经济入口不变。开发旅客配置增加 shipping_channel 的勒阿弗尔港—伦敦港许可，耗时、票款和座位均为开发参数。宿主城市与港口是不同 place，当前没有城市—港口通行边；未创建虚构连接，因此巴黎尚无连通伦敦港的完整人物路线。永久具名人口迁居、旧商品到原生商品的转换、宏观合同接收和退出仍需要后续业务规则。区域新增开发经营单元仅声明一项生产活动和一单位产能，不复制总部全部产线。


### 常住迁居与经济责任交接

`FormalWorldPopulationState` 保存迁居请求与生效事实。`request_residence` 使用当前人物行动权限及配置中的有限开发许可。请求者必须已经在目标地点，且不在途。旅行和 `relocate` 不办理迁居。日结顺序为完成旧日原生与宏观责任、Population 提交常住迁居、原生范围扩容或有条件退出、组织观察。人口总量和具名计数在来源及目标单元各转移一人，Overlay 在同一提交中更新常住引用。当前物理地点、cohort、账户及合同不随迁居重建。配置中的人口单元以接入时刻的历史常住归属核对。

只有生效的原生人物及cohort从完整宏观需求中排除。账户存在不代表个人需要已被原生接管。旧个人购买、消费及工资历史继续保留。

`FormalCommodityMapping` 只处理带来源与用途限制的整数比换算，不保存库存和价格。开发商品千克口径与统计目录的吨口径明确分开。运行中接管已有个人物品时，从正式个人购买FIFO批次减少原数量，并形成同一物主的原生地点寄存来源。现金不变，不重复扣统计库存。无法换算的余量、没有来源批次、原固定工资或仍有效生活安排使接管延后。匿名统计库存没有企业所有权依据，继续由旧宏观管理。

具名人物退出仅在其无未结业务且旧宏观可承担未来常住消费时生效。Slice 保留演员、历史需要、订单、工资、资产及行动记录，只结束未来原生活动资格。企业、cohort及仍有库存、合同、债务或股份的主体没有旧接收方时保持原权威。已退出人物的重新接入未实现。

有限开发选项可以显式绑定此前未支持的宿主地点到已有统计单元。当前伦敦城市及港口采用标注为开发假设的 `british_isles_1900` 绑定；不改变整个 `british_empire` 的人口口径，不创建交通连接。普通旧模式及未含这些字段的旧存档不获得该绑定。


### 原生货损履约与有限小时运输

`EconomyCargoFulfilment` 保存原订单关联的货损观察、各方确认、处置及通知。`report_cargo_loss` / `confirm_cargo_loss` 先检查整组实际来源份额。实际保管方确认后扣减 `EconomyStockLots`；具名物主的 `native_loss` 同步减少来源保管描述，不计为消费。运输货损把缺少数量从 transit 转回原订单 pending，保留货款与运费的原现金预留和预算窗口。历史各段的 `departure_quantities` 不追溯缩小；空的 LOSS_RECORD 只保留发运历史，不参加日常推进。

`propose_cargo_disposition` / `confirm_cargo_disposition` / `execute_cargo_disposition` 支持 KEEP、REPLACE、RELEASE、REFUND、DAMAGES。处置需有关合同主体逐一确认。REPLACE 使用新的实际库存；个人寄运使用本人在原出发地点的寄存物和原来源。新 shipment 的 replacement_disposition_ids 引用原损失处置，不再增加一份顾客需求。fees 必须显式提供；空数组表示各承运方同意没有新增费用，不能由系统自动填入。首版收费里程碑只支持显式 `REPLACEMENT_ACCEPTANCE`，在补运实际接受时支付；仍受资金及对应 freight 科目预算约束。正式商业组织使用 `OrganizationState.acting_context` 与 `AuthorizationCheck.resolve_authority` 的实际根授权或子授权。`economy.cargo.replace` 等处置同意、`economy.procure` 新运费承诺和 `economy.cargo.pay` 退款/赔付执行分别检查。新增运费按 payer、币种、freight 科目与稳定预算窗口累计；根授权须与预算来源一致。接替经理不自动取得这些权利。历史采用保存授权和任命/委托来源；撤权只阻止新的决定，不删除已成立责任。

解除只释放确认不再履行的份额。退款引用原 goods / freight 付款并限制累计退款；赔付独立记录。钱不够时保留 PAYABLE，失败不向收款方加钱。退款不恢复采购预算额度。企业管理者的新增货损财务同意需明确 cargo_settlement_controller 与 EXPLICIT_DEVELOPMENT_CARGO_SETTLEMENT_AUTHORITY；经理接替不自动取得此权。承运配置的 custody_controller 与 settlement_controller 也分别授予保管事实确认和运输条款同意，必须声明 EXPLICIT_DEVELOPMENT_CARGO_AUTHORITY。它们不授予股权或分红权限。

货损不会自动传播给远方主体。notify_cargo_loss 需要明确收件合同主体、delivery_minute 和来源；未送达不提供原因。相关查询与原有人物订单区展示确认、未决处置和付款状态；页面只提交领域行动。现有数量输入可提出解除或“新增运费0”的补运条款；补运仍需所有有关承运方确认，不能自动免除原合同运费。约定赔付资金不足时，PAYABLE 变化也标记存档待保存。

shared_transport 可以继续使用原先明确 entry_minutes。新增小时执行必须同时提供 window_minutes（1–60）、loading_minutes、travel_minutes、vehicle_hold_minutes；缺项拒绝。时间与重量均是显式输入，没有日容量除以24或自然损耗默认值。Spatial 的进入采用仍承担不可回吐的入口吞吐；载具重量占用延续至真实 release_minute，之后释放未来占用。装卸实际工时从原工资工作记录分配，不能与施工和生产重复使用。LOADING、TRANSIT、WAITING 与到达边界由原 GameClock / SimulationStep 推进，中转段重新争用实际资源。EconomyR1Slice.advance_time 返回实际成功状态，窗口处理失败由 SimulationStep 返回错误。已进入的行程锁定原到达时刻。指向同一 source_link_id 而未提供 shared_transport 绑定的经济路线停止新增进入，不能旁路使用另一份日额度；已进入的旧行程保留原义。

cargo_fulfilment、原预算窗口、批次来源、进入采用、装卸与持续占用进入原生 snapshot / restore。派生活动和责任索引恢复时重建。FormalPersistence 继续在隔离候选中恢复这些状态及个人来源，不调用 initialize、不重放损失、补运或付款。旧存档没有新字段时不补造货龄、损耗或时刻表。`transport_facilities` 可声明已接管经营地点的有限开发装卸、泊位与在途保管设施，分别具有单位及实际开放窗口；可引用同地点真实资本资产作为可用状态条件；生产产能不换算为装卸能力。`shared_transport.node_resources` 将起终点设施与装卸时长、工时接到原 shipment。到站取得真实卸货工时、泊位和保管容量后进入 UNLOADING，否则留在 WAITING_UNLOAD 的实际载具上。装卸与施工、生产分配同一批已登记工时；没有工时则等待。载具保留至约定最短占用及实际卸货结束；保管份额仅由后段进入、交付或已采用损失释放。新节点绑定若同时引用既有 transport_nodes 日数量上限，必须声明 `legacy_node_limit_basis=EXPLICIT_DAILY_BUSINESS_QUANTITY_LIMIT`，说明它是额外经营限制；缺少声明拒绝组合，不推断成第二份物理运力。旧未映射路线保持原规则。这些保管设施只约束运输及待领取责任，不冒充全地点商业库存仓储容量。

旅客许可的可选 `shared_capacity` 必须明确源 Spatial 连接、共同资源单位及每人的有理用量依据。旅客仍单独受座位、携带与票款约束；有明确共用配置时才与货运调用同一 request / final allocation / consume_capacity_batch。未知单位关系不混合。下一段未取得容量则在实际节点等待。旅客票款仍是 person_travel，不变成货物运费。已使用吞吐不回吐，跨窗口保留采用事实。未声明共用的线路保留旧旅行规则；军事 Task6 未接入。

FormalPersistence 在候选的原生状态及人物旅行都恢复后，调用 `validate_transport_references` 核对 economy_entry 与 passenger_entry 的 Spatial 采用归属。恢复同时核对卸货结束、节点保管释放来源、真实工时、资金和授权历史，不重新付款或进入。设施容量、旅客单位换算与授权根须由明确配置/宿主事实提供；默认开发组合不会因接口存在而自动启用节点容量或共用旅客规则。

### 分层区域市场与玩家经营

`--formal-stratified-economy` 沿正式 WorldBootstrap 创建巴黎、里昂、马赛开发网络。现有四家开发企业通过 `development_organizations` 明确申请稳定的正式 company 身份；来源为 EXPLICIT_DEVELOPMENT_COMMERCIAL_ORGANIZATION，不是历史公司资料。创建在候选 OrganizationState 中准备，原生初始化失败时恢复原组织状态。公司没有已证实的总部地点，不从经营地点推断历史办公室。现有企业账户、库存、岗位及人口数量不因组织登记增加。明确配置的玩家经营任命不授予货损财务根授权、股权或分红权限。旧模式及未声明这些身份的配置不自动登记。

人物页原经营区增加“生产与企业采购”。`LivelihoodAction.query_business` 调用原生 `business_view`，只向合法管理者返回本企业地点、实际可用资金、有效产能、活动及已知供应商报价。采购沿原 buy 使用页面已显示的 quote_id、数量、币种、价格上限、路线及授权来源；过期报价不在点击时偷偷替换。生产开停沿原 set_activity_enabled。数量复用现有人物输入，企业、地点、活动和报价有限翻页。当前下一批限制来自实际材料及设备条件，不冒充过去某次停产的原因。查询不下单、不付款、不产生劳动。

分层开发组合显式启用已有有限 NPC 扩产策略：3日观察、压力门槛4、利用率门槛50%、冷却10日。它仍受已有投资模板、现金、材料及劳动条件限制，不保证提出项目。资本采购成功后的项目订单关联使用明确追加，不对 void 方法读取返回值。

本次在 Godot 4.6.3 中沿正式 WorldBootstrap（含行政安装）、SimulationStep 连续运行30日：1名人物、8个cohort／72名背景人口、4企业、7地点、11商品。第8日玩家暂停自有上游谷物活动，第18日恢复；第15日在存在未结订单、运输及工资时完成 FormalPersistence 候选恢复并继续。玩家投资实际消耗机器1、建设材料4、工具1及6工时，第24日形成4单位新增产能。企业实际采购、工资、生产、运输和家庭消费延续；纺织企业现金耗尽并留下到期欠薪351。单日推进约85–175毫秒，快照约29毫秒，候选恢复约2.82秒。这是有限开发场景结果，不代表历史校准或全国长期性能。该组合没有配置信用、换汇、证券、累计预算窗口或共享小时设施，不宣称这些机制在此次场景中联合验证。原日级线路继续使用其有限容量；没有补发资源或启用未知损耗参数。

### 资金压力、企业信用与劳动反馈

经济阶段源码已保存到私有仓库的 `integration/formal-economy-20261014`，提交 `e17db82f1c2061266ef99f28741869af659165fa`。资金压力增量随本次仓库整理纳入同一经济集成分支。主分支不因本次发布改变。

`--formal-stratified-economy --formal-liquidity-policy` 选择新增有限开发组合；原分层组合和默认旧经济保持原行为。组合不增加开局资金、库存、人物或企业。`EconomyLiquidityRules` 校验显式经营、劳动反应和独立金融权限，既有 Ledger、Credit、Capital、批次和订单继续拥有业务状态。

企业观察区分可用现金、预留、实收销售、承运收入、已付及到期未付工资、贷款剩余本金和利息。到期欠薪可触发有限实资融资，资金实际到账后才沿原工资支付路径使用。采购保留配置的现金及到期工资额度；到期偿债仍沿原有限策略。持续欠薪可排队暂停生产、暂停未完成投资及进入 wind_down，库存、合同和债务不清空。恢复仅适用于该策略自己暂停的活动，须满足真实现金、工资及到期债务条件；不覆盖管理者另行暂停的状态。自动投资避开已经成熟的工资及信用负担。

`finance_firm` 让合法人物为同一企业提交信用行为。独立 `firm_finance_authorities` 指定控制者、动作、币种、额度和时间；生产经理身份不产生这项权限。实际组织根授权使用既有 acting_context 与 AuthorizationCheck；开发金融许可单独标注来源。可选 borrow_limits 使用原企业 Ledger 当日提款及信用模块未清余额，不因经理、代理或行动ID变化刷新。资本借款也走同一权限。合同及代理行动相互引用，恢复核对原企业、实际额度、币种和授权来源，不重放资金转移。

劳动反应默认关闭。本组合只给里昂技能cohort声明7日欠薪等待规则；一日最多处理一个明确人群。只有自身所有现有岗位都满足欠薪条件时，沿原 leave_job 在合法边界退出。旧工资债权仍绑定雇主；未取得新岗位不形成新收入。再次求职继续使用已知岗位、技能、位置和实际岗位份额，并暂不重返自己仍有长期欠薪的岗位。

食品企业谷物采购采用两个显式开发窗口：第0–20日额度35、第20–60日额度55，均保留原窗口责任，只覆盖 goods:grain。两向巴黎—里昂路线以同一真实 Spatial 连接执行明确的午夜及正午小时安排。食品和上游企业使用本来存在的工时提供装卸和承运；有限载具、泊位及保管容量是开发设施配置，不是历史铁路参数。每商品单位占一开发载重单位，是该组合的机制假设，不是吨、座位或军事资源的换算。里昂—马赛及未声明共用的旅客线路继续使用原规则，没有自动启用汇兑、证券或自然损耗。

已完成一次50日正式运行。第25日候选恢复后继续推进。纺织企业第15日取得上游实资贷款11、固定利息3，第23日到期后保留逾期14；第22日暂停生产，第24日三个劳动份额离职，第38日进入收尾。第50日仍欠薪149，食品企业当日借款6、利息2后支付工资，期限至第58日。谷物两窗口实际承诺及支出为30和48；共享进入12次、节点采用60次。投资仍等待资源，没有新增产能。每日推进约110–284毫秒；第25日快照约45毫秒，候选恢复约3.40秒。未把有限区域结果外推为全国长期性能。

另一次短行动检查通过领域查询借款20、还款10，其中利息1、本金9，余本金11；正式候选恢复成功。更换行动ID后再借70仍被企业当日提款上限拒绝；还款不刷新提款额度。篡改授权金额的候选被拒绝，活世界债务保留。承运收款、同账户内部运费和信用本息分别分类，不称净利润。50日场景没有自动还款成交。组织根授权金融分支、自动经营和投资恢复、页面点击效果未在该场景触发或实机验证，不称已经验证。

### 前向直接成本与有限经营贡献

`--formal-stratified-economy --formal-cost-accounting` 显式启用成本组合；可与 `--formal-liquidity-policy` 一起使用。原默认旧经济、N2/N3、金融与库存规则不变。`EconomyCostAllocation` 只保存成本来源和分配事实，不支付现金、不供应商品、不发工资、不拥有产能。批次数量仍由 StockLots 保存，个人 native_lots 仍是来源和保管描述。

每份物资绑定一个成本依据及累计区间。寄存、预留、运输、消费和内部调拨沿实际份额切分；整数累计差额保留全部尾差，计算不依赖浮点金额。采购交付关联原订单、锁价、原币种和已采用 Ledger 付款。BUYER_ACQUISITION 开发规则归集买方实际对外承担的原合同运费；SEPARATE_EXPENSE 可将运费单列。企业向自身承运账户的记录不当作对外运费成本；自身装卸工资单列，缺少逐货归属时保持未知。补运新增费用继续单列，不重收原货款。

实际材料耗用和工资形成进入生产批次。施工、装卸和生产引用原工时与工资债权，累计分配不得超过实际工时；补发欠薪不再次增加成本。未分配生产的工资单列。单产出形成直接成本；联合产出在未配置分摊时只显示整批共同成本，各产品成本未知。明确 joint_allocations 的整数相对权重代表有理份额，逐产品累计分摊总额等于整批已知成本。开局及旧档未知成本不按当前售价补造。

实际销售的成本只在履约数量上转出。查询分开返回 Ledger 现金、履约收入、已售已知成本、可比较部分贡献、未知成本销售和未履行采购义务。真实货款退款引用原支付，符合比较范围的金额另列并减少已知贡献；历史交付及成本依据不改写。采购退款与未确定的存货重估分开。货损单列资产损失，不能变成销售成本或消费。金额按币种分别表示，跨币不可比较。此结果不是净利润，未含完整管理费用、折旧、税费与资产减值。

资本材料及实际施工工资关联原项目；原资产查询提供 origin_cost，不生成第二份设备。维护投入属于其维护项目，不追溯改变设备形成成本。NPC成本策略仅在声明的企业、有限窗口和当前合法管理下使用自己的已履约结果。全部候选具备可比数据时，才在合同优先级与生产依赖约束内按直接贡献/生产工时调整顺序；否则保持原顺序。投资可避开已知亏损，未知成本仍沿原策略。价格算法不变。

上一批局部开发运行使用正式 WorldBootstrap、SimulationStep 与候选恢复。12日场景保留未知开局成本及无分摊的联合产出；16日资本优先场景通过合法活动开停取得设备，原项目实际投入已知成本50并完成；另一16日场景包含人物实际工作、采购、旅行及4条部分交付收据，项目仍等待资源。已形成未支付工资40时已有生产成本，后续付款未改变原成本。资本品履约收入24、对应直接成本28，贡献为−4。第6日和期末恢复成功；坏成本引用被拒绝且活状态不变。8日明确权重夹具中，联合成本8按1:2分配后仍合计8；旧档缺成本字段按当前边界恢复未知。以上为开发输入，不是历史校准，没有重跑30/50日原场景、全仓回归或历史矩阵。退款、货损成本及小时装卸成本未在上一批场景中触发。

成本生命周期查询继续读取原 CargoFulfilment、StockLots、Ledger 与资本项目。运输按真实订单、收据、段、付款人和处置分类，区分采购、同企业调拨、个人寄运及补运费用。原 BUYER_ACQUISITION 配置继续只归集原合同购入运费；补运新增费用独立列示。未配置的等待收费不生成费用。装卸查询同时显示已分配、已用和待命工时，工资义务只分配一次，不默认资本化到某批商品。

确定货损的成本区间不能与生产耗用、资本耗材或销售区间重叠。查询保留物主、保管者、原订单、阶段、来源成本及未决数量；不将物主直接解释为最终赔付责任人。补运成本来自新份额；原销售只按实际交付确认一次。确认的退款和赔付、未付责任、实际付款分别显示，退款不恢复商品或预算。只对有完整成本和币种依据的销售部分计算贡献，并显示确认退款后的调整；货损、物流和赔付仍独立列示，不称净利润。

CargoFulfilment 的主体/日期与开放处置索引由原合同重建，不保存第二份应付账。成本策略的有限窗口加入当前经理已经获知的物损、同一活动可归属的补运费用和确认退款；未知或联合归属不明时保持原顺序。投资判断可读取本地点实际装卸工资、单列物流和确认赔付负担，不改变价格或已承诺合同。设备 cost_lifecycle 分开显示 origin_cost 与 maintenance_cost；退役保留历史投入，可用新增产能为零，残值和折旧保持未知。

本批12日正式场景通过实际旅行、部分领取、确定损失、限定组织根授权、独立补运预算、补运费1与退款1完成原2单位订单。损失1单位豆类的已知成本为1，补运来自另一生产批次；共享进入7次，装卸工资和待命工时实际出现。未结退款及期末候选恢复成功，重复处置未改变 Ledger、预算或成本。删去新损失成本引用的候选被拒绝，活世界不变。18日资本场景实际形成初建成本50的设备，维护成本13后退役，第14日及退役后恢复成功。缺成本字段的旧档分别显示货损和维护成本未知。费用与授权数字仅为明确开发输入，没有增加现金、物资或岗位。赔付未付失败、解除、个人寄运费用新查询未在本批触发。经济领域解析通过；Application 解析受字体和纹理导入缓存缺失影响，页面未实机查看。

### 商业仓储与外部维修（显式开发组合）

`--formal-stratified-economy --formal-services` 选择 `service_regional_template`。可以另加既有 `--formal-liquidity-policy`。未配置服务的原生世界和旧统计默认入口保持原行为。组合继续使用四家正式开发企业、七个经营地点、八个 cohort 和原有资金、库存及工人；里昂纺织地点另声明有限仓储设施、维修工位和适用岗位。这些资格、容量、价格和单位是开发输入，不是历史资料。

`EconomyServiceMarket` 保存服务合同及控制来源。企业服务为仓储与维修；居民服务为同地点餐饮与理发。报价限定已知主体、送达时刻、有效期和实际提供地点。接受分别检查当前经理、独立服务采购/供应授权、对象产权、设施、原 Ledger 可用现金和对应累计预算。显式授权可引用正式 Organization 根授权；经理接替不会自动接续原控制人的服务财务授权。企业合同付款人等于委托企业。居民合同付款人等于本人或原聚合cohort。二者不支持第三方代付，居民身份不能替代组织采购授权。

仓储仅办理同一宿主地点的实际交接。跨地区货物须先用既有物流到达委托方的合法经营地点。客户商品沿原 StockLots 份额进入 `SERVICE|合同ID`；所有者不变，保管者变为提供服务的经营地点。提供者库存投影不包含客户货物，生产和销售不能使用这些份额。接受时占用有限仓位；实际入库需真实工时。分期费用按已有物资的数量分钟累积、按明确开发条款除以1440取整，使用累计差额结算。入库、保管和取回不会复制商品。期满未取物资仍占用空间；没有条款不追加超期费或留置。分批取回释放未来占用，保留已经履行的费用。

维修限定报价声明的设备类型、同地点现场工作和提供者自有材料。合同预留真实费用与工位；材料经既有采购到货后才能耗用。CapitalFormation 的 `begin_external_maintenance` / `complete_external_maintenance` 更新同一资产；真实材料、有效维修工时和原维护工期共同决定完成。已接受外修阻止另一份内部维护及设备处置；已有待生效设备控制会阻止新外修。未开始合同可取消；已开始维修只可暂停/恢复，缺少部分解除条款时不抹掉已耗材料、工资或履约责任。

日结先分配资本施工、再分配服务、再分配共享装卸和商品生产。服务引用已有实际工作登记及工资债权，不创建工人或第二份劳动时间。服务费通过 Ledger 原子付款与同一预算承诺采用；付款失败保留到期未付部分。CostAllocation 关联真实服务材料及工资，分别展示履约收入、现金收付、客户维护费用和整个已结合同的已知直接贡献。维修费用不加到设备初始价值。折旧、设施租金和管理费用未纳入，不称净利润。

商业仓储可显式引用同地点、同单位的物流 `STORAGE_OCCUPANCY` 设施；此时其占用由 SharedTransport 读取同一合同投影，不能获得第二份物理额度。未声明共用关系的设施保持独立。已确认仓储货损沿原 StockLots/CargoFulfilment 扣减，保留成本来源；服务损害赔偿条款尚未配置，不借商品销售处置直接清账。货损通知复用原延迟通知；未获知的一方看不到现场损失原因，数量权威仍立即停止供应毁损份额。

局部正式运行使用 WorldBootstrap、SimulationStep 和 FormalPersistence。18日场景取得真实设备后完成外修：仓储费3、维修费18，维修消耗一份工具及2工时，同一设备恢复可用。第5日和维修开始后的候选恢复均继续推进；完工后再次恢复。另一个6日开发夹具检查现金不足无副作用、NPC实际仓储、共享4单位空间投影、确定货损、重复确认、坏引用拒绝及恢复续接。另有5日延迟通知场景。一个较晚委托的尝试持续缺料，未补发资源。这些结果不是全国规模、历史校准或所有物流并发场景验证。


### 居民现场服务

`--formal-stratified-economy --formal-resident-services` 显式启用居民开发组合，复用原四家企业、八个cohort和开局资源。巴黎食品企业的指定support岗位被明确配置为餐饮、理发的合格岗位，同时保留其原生产工作。餐饮设施每日2份、理发每日1份；每份需1整小时。价格3/2、七日理发目标和两类cohort的有限消费政策均为开发输入，不是历史参数。未启用该组合时原行为不变。

`EconomyResidentServices` 是同一ServiceMarket内部的现场执行规则和派生查询索引，权威合同仍只保存在ServiceMarket。客户使用原Ledger个人/聚合账户，以自身身份锁定费用。企业供应仍检查原独立供应授权。具名人物只办理自己的合同；cohort以明确成员区间和实际服务份额办理，不创建逐人钱包。报价限已知客户和真实通知时间；居民查询隐藏提供者原料来源、工单和成本。

本版只支持日界预约、下一个日界执行，且客户须同地、不得与其实际劳动份额重叠。具名人物在预约期间不能旅行或登记冲突劳动。cohort使用未分配给当前岗位的成员份额。缺工、缺料或停业时进入WAITING，原资金承诺保留，可在日界重新预约同一未履行责任。部分履行按实际数量结算；未开始可取消，已经发生工作后不提供无条款的整单退款。没有分钟预约、异地配送或自动赊账。

餐饮每份实际耗用提供者一份未承诺面包及一小时现有劳动，不产生食品零售收入或个人商品。履约在当日实物消费之前计入原food需要，实物只补剩余缺口，满足不超过当日需要。理发只形成服务回执，按目标窗口合并成员区间，同一成员重复付费不重复获得同窗目标满足，不影响健康、技能或肖像。食品履约数量表示实际服务份数；不能推断每名cohort成员的生活质量。

NPC仅按显式已知报价、所在地点、未满足目标、可用资金、未完预约和窗口消费上限选择。居民策略在当日普通商品采购前形成下一日预约，符合显式SERVICE_FIRST规则；商品采购仍经原账户及真实到货。已有未结同报价服务不重复下单；没有足够现金、食品或工时可以失败。服务与施工、装卸、生产共享原实际工时和工资债权。CostAllocation追加实际材料成本区间，劳动成本形成于工资义务；付款不重复计成本。初始食品成本缺失仍标未知，服务贡献不称净利润。

短场景使用正式WorldBootstrap、SimulationStep和FormalPersistence。8日默认居民组合发生NPC餐饮、理发与满额拒绝。9日定向组合关闭NPC服务自动采购，并显式使用14日目标窗口；完成具名用餐、两次同窗理发、现金不足拒绝、身份拒绝、未开始取消和候选续接；同窗第二次理发目标新增为0。高价现金拒绝夹具只改变该次明确报价和供应授权，不增加资源，也不写入默认模板。8日部分履约组合为6人cohort结算两份餐饮，共耗2份食品、2工时、支付6，分两日各满足1食品单位；第5日部分履约后恢复，第6日完成。同行仓储履约费1并保留到期保管。坏服务数量候选被拒绝，活世界保留。这些均是有限开发运行；未执行完整界面点击、全国运行或历史校准。

### 有限住房与经营场地使用权

`--formal-stratified-economy --formal-leases` 显式启用租赁组合，沿用居民服务、四家企业、八个cohort及原开局资源。`EconomyLeaseMarket`只保存有限使用权合同、交付/结束/交还事实、期间租金和原付款引用。它不保存土地所有权、第二份设施、现金、物资、人口或时钟。Spatial地点及政治控制不构成建筑产权。巴黎两处标的使用明确开发使用权授予：住房3人份额、食品企业巴黎站点1份独占经营空间。权利来源、单位、出租主体和有效期均显式配置，不是历史建筑资料；不与仓储或运输容量换算。

新签约分别检查本人或企业资格、出租/承租独立授权、有效组织、真实同币账户、已知报价、有限空间、成员份额、首期现金和适用预算。经理身份不自动授予租赁财务权限；可选正式根授权沿用AuthorizationCheck。首期资金只预留，实际使用后按两日开发周期到期付款，后续租期允许形成欠租。租金用累计已提供人份/场地份额分钟计算整数差额，当前只在日界采用。未来承诺、已发生租金、已到期和已付分别保存。没有押金、预付租金、欠租自动驱逐或未交还后的自动加租政策。

住房接受不等于交付。本人须实际到达，cohort只满足不重叠的已交付人份额。日界住房目标依据当地实际可用使用权，欠租不改写已经提供的居住；未知初始住房不认定为无家可归。租约不移动人物，不修改Population常住归属。仅明确配置的食品企业巴黎站点受商业租约限制；其他站点原资格保留。租约不产生设备、劳动、原料或产能。过去合法区间的劳动、施工、服务和生产先按原使用权结算，未来业务按当前租权判断。

结束未来使用、清偿租金、实际交还分别处理。已交付合同到期进入ENDED_OCCUPIED，继续阻塞空间再出租。企业实际交还须沿原站点收尾条件处理库存、劳动、工资、设备、服务和物流；不得清空资源。居民交还只处理本租约使用份额，不推断城市内搬迁或司法驱逐。重新承租在实际交还后创建引用predecessor的新合同，不改写旧锁价和欠租。企业租金单列为地点期间费用，不分摊到商品直接成本，不称净利润。已有资本引用可约束可用状态，开发标的本身不形成新建设资产。

NPC只对显式政策中的已知候选、实际资金和未占用成员作有限选择。开发组合明确选择先处理既有工资/债务，再结算租金，随后新增商品与服务采购；这不是全国支出优先规则。租金实际占用原现金并参与消费竞争，商业租金使用原累计预算窗口。活动合同和到期欠款参与日结，历史合同仅按主体/日期查询。

9日正式短场景使用WorldBootstrap、SimulationStep和FormalPersistence：6人cohort取得2人住房份额，累计租金18、实付10、欠租8；商业场地租金15实付，到期后停止该站点未来经营，库存保留。人物提前结束、实际交还后重新承租；空间不足及首期资金不足均拒绝且无租约/预留残留。企业交还因服务责任仍在被拒绝，未删除库存。第1、4、7日及第9日后60分钟候选恢复成功，原生快照一致；坏期间金额候选拒绝且活世界保留。最后补充组织/同币账户检查后的2日续接及日内恢复通过。Application已解析，未进行完整界面点击或全国运行。

### 真实建设形成的出租空间

`--formal-stratified-economy --formal-building-leases` 启用有限建筑开发组合。沿用原四家企业、八个cohort、72名背景人口、账户及开局资源。`RESIDENTIAL_BUILD`和`COMMERCIAL_PREMISES_BUILD`属于原CapitalFormation项目，沿原采购、运输、批次耗材、劳动分配、工资、项目预算和日界施工完成。没有建筑专用库存、钱包、劳工或时钟。材料阶段之后的实际工作仍按原应计工资责任处理，欠薪不被当作免费劳动，也不要求在归集已发生工资时再扣一次现金。

每项building模板包含permit、object和offer。permit明确持有企业、独立控制人、正式place、建设类别、有效期、稳定开发建设空间ID及1份建设份额。建设空间和许可ID不得重复；接受项目后不自动回收该名额，取消或停工不自动返还耗材。新项目检查真实可用现金、原工资/到期贷款资金保护、实际经理和组织状态；可选根授权使用economy.construct及原AuthorizationCheck。恢复核对原建设行动和保存的授权依据。土地政治控制、股东身份、普通生产管理权和建筑产权不互相推导。开发建设空间是有限模拟输入，不是历史地籍或建筑足迹。

建筑资产仍只保存在CapitalFormation.assets，以capital_asset加原行动ID稳定标识。capacity在建筑类别中代表住房人份或独占场地份额，明确排除工业产能池及累计生产能力。LeaseMarket预先知道获准公开的建设报价，但实际供给为零；只有原资本项目真实完工后才登记资产引用。实际容量、产权、完工时刻及可用状态从原资产读取，引用投影不保存另一份可增加的建筑数量。原巴黎3人份住房和1份场地继续保持开发授予来源，不倒推历史施工。

新商业场地的承租站点沿expand_configured_scope准备。开发站点在原正式place，零资金、零商品、零工业产能、零新增人员。租约只提供场地资格，不复制原工厂、仓储吨位或服务设施。建设用地份额、住房人数、独占经营空间和工业产能没有换算。新增站点尚未合法纳入时，租约拒绝；活动租权结束后，未来经营受限，库存、工资及合同仍保留。

合法出租人可通过set_lease_offer暂停或恢复已配置报价，不追溯改变已接受租约。现有租金继续进入实际产权企业账户，按原期间履行结算。资产观察分开返回原建设投入、履约租金、实收、欠收、空置份额、实际占用及企业信用合同；不把企业全部贷款自动分配给某栋建筑，不称完整投资回报率或净利润。停用/维护/退役沿原资本事件影响未来供给，未交还占用与债务保留；不可用期间记入原租约期间事实，不自动退款或赔偿。未设置折旧、残值、随机损坏或新维护率。

building_policies默认缺省关闭。显式策略只读取本企业窗口内真实收租、已知空置、真实资金和工资/贷款负担、可比自身材料成本或已知供应报价、真实当地工作及建设许可。达到门槛后仍提交原invest行动；不直接生成建筑。开发组合只声明一项基于自身实收租金的有限策略，既有建筑份额已承诺、空置、缺款或资料不足时可以不投资。建设和租赁供应不保证满租或盈利。

本轮18日住宅场景和15日商业场地场景使用正式WorldBootstrap、SimulationStep与FormalPersistence。经营者通过原活动开停将有限生产转向建材和工具，未补资源。各自优先建设的项目第9日消耗4批建材、1组工具及4施工工时后完工，已知建设投入38。住宅形成2人容量，人物取得1份，实付租金4，另1份空置；商业场地形成1份，原范围入口准备零资源站点后承租，实付租金8，重复占用拒绝。商业场地实际交还后容量回到1，原资产退役后降为0。另一项目缺料/失去未来施工场地资格仍保留；低预算项目也继续等待。商业场景第15日成熟未付工资100未消失。新场景的14日基础场地租期、40采购窗口、建造配方和租金均为开发输入，原租赁组合不变。

候选恢复覆盖第4日在建、第11日未结租约、住宅第17/18日及商业第15日退役后，并包含日内续接；原生快照一致。擅改实际建筑容量的候选拒绝且活世界保留。报价停开、无独立建设许可、未完工提前承租和重复空间请求均运行过。NPC策略未在本轮场景另外发起成功新建，不将经营者明确提交的项目称为自主投资。Application解析通过，未进行完整界面点击或全仓回归。


### 实体零售与批发补货

显式启动 `--formal-stratified-economy --formal-retail-market` 使用既有四企业、八cohort及72名背景人口。巴黎上游企业的空门店站点沿真实建造商业场地和原租约取得使用资格。未完工、未交付、停用及到期场地不提供新营业资格。新增站点开局库存、资金、设备和产能均为零；一项有限店员岗位使用原劳动人口，增加的岗位选择上限不增加劳动人数。

EconomyRetailRules只保存门店每日实际营业工时分配。商品仍由StockLots、现金仍由Ledger、销售仍由原SALE订单和delivery_receipts保存。批发采购继续锁价、预留、运输及交付。取得成本由原CostAllocation按零售商真实采购价及已选运费规则归集；上游自身已售成本独立保留。现场订单用onsite站点履行方式和空运输段，不假造运力采用或运费。交易前准备个人持有、原子付款、批次和预算采用。已实际交付才付款及转移成本，购买不直接满足生活需要。

门店在资本施工、服务之后，从实际工作记录分配整数营业工时，再与装卸和生产扣用同一工时。明确日级已结工作营业窗口不表示逐分钟排班。每小时可办理数量、每日上限、开门区间和专用库存单位均为开发假设，不是历史建筑面积或重量。门店专用保管空间独立于已有商业仓储和运输设施，未实现二者的共用配置。进货承诺连同在途数量占用门店接货上限，在途货不能现场出售。

原企业采购按实际库存阈值、目标、批次上限、已确认在途、已知供应商、价格上限和真实现金保留补货。仅显式配置的巴黎工业cohort优先考虑可执行现场报价，其余选择沿原规则，生产企业直接销售继续存在。原N2/N3规则不变。门店查询按站点及有限日期索引读取销量、履约收入、实收、可追溯已售成本和商品贡献，营业工资、租金及其他费用分别列示，不是净利润。

23日正式WorldBootstrap/SimulationStep场景中，商业场地第9日完工并交付租用。零售商实际采购8面包及3肥皂，后者走马赛—里昂—巴黎两段运输；人物购买1面包，cohort现场购买7面包和1肥皂。第16日窗口履约收入与实收76、已售取得成本66、商品贡献10；未扣营业工资及租金。门店已发生真实工资与租金。第18日暂停后的购买拒绝；第19日租期到期，剩余肥皂、原采购和工资责任保留。第12、18、23日正式候选恢复续接，快照一致；重复购买行动不再转钱或交货，篡改营业工时的候选被拒绝。未做全国长期模拟或完整界面点击。末次Application复查被地图工作线region_view.gd缺少_surface_height、_make_water_mask、_make_surface_mesh、_make_surface_lines及_make_surface_cover阻塞；未修改该文件。


### 有限商业公告与信息竞争

显式启动 `--formal-stratified-economy --formal-commercial-information` 使用现有四企业、八cohort和真实个人账户。EconomyCommercialInformation只保存公告原行动、来源站点、发布时商品批次/服务报价、有效期及原服务合同引用。消息发送与送达继续使用EconomyR1Slice.messages/receipts；商品候选进入原known_suppliers，服务知情索引由实际收据重建。supplier_directory仍是有限搜索目录，不等于所有主体已经知道其条目。

自有地点公告要求合法经营场地和本日实际工作人员；这是既有营业中的附带张贴，不新增一份免费劳动。有限付费本地发布是原ServiceMarket的ANNOUNCEMENT合同，独立提供企业使用实际岗位工时完成发布，工资和直接成本沿原SERVICE分配。客户须有单独采购授权、真实现金预留和适用service:announcement累计窗口；不能借用goods:grain预算，也不向自己支付外部宣传费用。工作履行后形成费用、原Ledger实际付款和延迟消息。收费针对一次实际发布工作，不保证受众购买或广告因果收益。

渠道明确地点、有限接收名单、受众上限、日级延迟、冷却和期间发行上限。人物必须实际在场；跨城cohort不会因公告到达而迁移或现场购物。cohort接收者表示既有共同现金池的聚合采购窗口，不表示全体成员逐人获得信息，也不增加采购预算。地点公告保持有限活动索引，到访接触仍有原时钟下的投递延迟。企业在本站取得供应公告后只增加自己的已知候选，不获得对方成本、贷款和秘密库存。

公告中的价格和数量是发布时观察，publication_quote不是可执行购买凭据。历史消息可以保留；未来购物必须用原即时询价及SALE行动，重新检查报价、现金、位置、库存、营业劳动和场地。失效公告不复活旧价格。多门店选择继续使用原已知商品偏好、显式现场优先、同币价格及原可执行FX比较，没有新增效用最优或销量百分比公式。

NPC宣传策略默认缺省关闭。显式策略仅读取本企业库存、实际窗口销量/服务履行、可营业能力和真实现金，仍提交原公告或服务行动。冷却和累计发行按企业、渠道和日期计算，不随action_id刷新。实际后续销量、询价和补货由原订单及日期索引查询，不把相关性称为营销回报。商品和服务公告共享受众规则，但不共享或扩增其专业供给能力。

开发组合在原巴黎纺织企业销售站点增加空库存面包零售资格和一项店员岗位，使用原cohort劳动份额；必须从食品企业真实购买并运输。6单位零售价是允许亏损的固定开发报价，上游价7，未修改N2/N3。另一个已建并承租门店保持价8。原已知供应商不删除；新面包候选不通过开局或自动到访公告提前公开。新增理发公告报价引用原同一设施和工作人员，不增加椅位。发布费3、1实际工时、1/2日延迟、受众3/4、冷却4日和7日最多2次均为开发假设。此组合新世界基础食品场地选择20日租期及50累计租金额度，仍使用原现金和真实付款，不改写旧世界租约。

本轮18日正式场景中，新面包门店第13日自有公告，第14日实际送达后cohort首次从其购买3单位；上游价7、该店零售价6，允许负商品价差。第15/16/17日继续提交真实补货，非免费补库存。里昂仓储服务在第6/13日发布原报价公告，各有2个本地企业采购窗口收到。巴黎付费公告第14日接受，第15日用1个原店员工时发布并实付3，第17日4个合法主体收到；这1小时同时使提供方当日门店营业工时不足。发布服务直接劳动成本2、已知合同贡献1，未计设施等费用。食品企业收到公告后增加零售商供应候选并实际买入2单位，未用广告直接生成需求或款项。远方里昂cohort没有收到巴黎现场公告。

正式候选在第8/14/16/18日恢复，包含未开工发布合同、已付款但尚未投递的消息及关店后的历史成交，快照一致。改早投递日期的候选拒绝，活世界不变；重复原发布行动未再扣款或发布。公告编号下单被拒绝，现金不变；关店后仍可读旧公告，当前现场报价为不可购买。修复日结自动现场成交先于同分钟经营开停采用的恢复校验，仅原自动消费行动使用原经营区间，实际租期/人物在场仍按真实时刻检查。另用7日自然运行和第8日续接检查公告查询不写状态、自主策略停开及撤下公告恢复。Application当前解析通过；未做完整界面点击、全国运行或全仓回归。


### 动态招聘与已接受劳动条件

`--formal-stratified-economy --formal-labor-market` 启用有限劳动开发组合。默认统计经济和此前开发组合不启用。EconomyLaborMarket只保存未来招聘版本、工资变更同意及有限策略观察。原R1合同、人员份额、工作、工资、消息、Population和Ledger仍是对应权威。

`set_job_offer`在下一日界申请未来名额和时薪，接受请求不等于聘用。日界重查独立用工授权、经理和场地，不能缩减已占用名额。报价版本不可改写，招聘撤回或到期不终止现有员工。工作地点招聘复用CommercialInformation发送入口和原messages/receipts；只向配置中实际同地的个人或cohort共同决策窗口投递，延迟1日，不代表每个成员独立知情。商品付费广告没有取得招聘发布许可。

`apply`锁定job_quote_id。实际签约重查当前版本、期限、名额、技能、账户、场地和工资承担观察。已有合同保存terms和employment_action_id，工资按接受条款及真实工时产生。经理调整未来报价不改变旧合同。`propose_employment_terms`提出本岗位未来条款，`accept_employment_terms`须由已经收到条件的劳动者确认，下一日界重查后采用。此前登记并完成的劳动先按旧合同结算，补发欠薪继续引用原债权。

cohort继续使用原labor_start和workers。部分离职通过原employment_ends释放所选岗位尾部人份，其他岗位继续工作；已登记工作不撤销。新岗位只能使用实际空闲人份，并受原max_jobs限制。求职只比较已知同币报价，跨币按稳定币种顺序处理，不凭显示数值认定工资更高。旧雇主欠薪反应继续使用原阈值；混合雇主cohort可只退出欠薪岗位。退出和再次录用有边界间隔，不保证新岗位仍有空缺。

企业策略读取本企业实际生产计划及可用材料、在建施工、实际服务工单、门店库存和已有人员工时。其他岗位覆盖的工时参与需求估算，专门服务岗位保留资格约束。招聘考虑Ledger可用现金、现有工资承担、成熟欠薪和到期信用责任；采购预留已体现在可用现金中。这里没有预留整个未来雇佣期间工资，不称资金担保招聘。有限日观察、报价上下限、步幅、冷却和人数上限均为开发规则。

此组合沿用4企业、8cohort、72名背景人口和1名具名人物。巴黎食品开局岗位为10个1小时名额；原12名可劳动成员不增加。巴黎纺织门店设0个开局空缺的辅助岗位，使用同一库存、工资和零售劳动分配；明确营业窗口为2工时、每日上限6单位，保管容量不变。没有新增现金、商品或工人。通常时薪范围1—6，辅助岗位3—6，单次变动1；冷却3日，辅助岗位2日，报价12日有效。数值不代表历史工资或全国政策。

生产、服务、装卸和零售成本继续引用实际工资债权。CapitalFormation的已发生施工成本、项目预算耗用和工资负担改为原工资金额/原工时；未来施工估算读取当前报价及仍有效的已接受工资上界，不回填历史成本。区域查询从原合同、工资和人口派生职位、空缺、就业、未就业及按币工资承担，没有第二份就业底账。

22日正式联合场景完成。里昂原3人按时薪2，新接受2人按3；原3人确认后未来劳动改为3，随后新报价降为2仍保留这5人的原条款。巴黎同一cohort在收到招聘后释放食品岗位1人份，并于第5日按时薪5接受零售辅助岗位；总分配不超过12。门店第10日采用2个营业工时，第17日为1，第22日为0。成熟欠薪导致员工退出，旧债权保留；第22日纺织企业成熟欠薪201，区域44名可劳动背景人口中实际就业20、未就业24。巴黎劳动cohort累计实收549、仍有84成熟欠薪；当日食品缺量仍为36。收入经原采购和消费使用，没有直接增加需要满足。

第4、14、22日候选恢复后继续，原生状态相同。第4日含未生效的劳动者同意及未结工资；破坏报价金额的候选被拒，活世界不变；原行动重放未改变状态。另有4日具名人物场景，实际录用、出勤、工资2→3和候选恢复成立；新条件收到前不能确认，已登记旧工作仍按2结算，第4日新工作按3。实际Application解析通过。未执行全仓回归、历史矩阵或界面实机验收。


## 自愿经营收尾与原债权（显式开发范围）

`--formal-stratified-economy --formal-enterprise-wind-down` 使用原四家企业、八个 cohort、72 名背景人口及原开局资源。`EconomyWindDown` 只协调独立授权、业务准入、派生责任查询和有限偿付。决定仍存入 `enterprise_changes`，付款行动仍存入 `commands`。未建第二份现金、库存、劳动或清算账。

收尾阻止新增采购、投资、招聘、服务接单、租赁及宣传。已有合同继续履行、退赔、取货或合法结束。原 SALE、StockLots、运输、成本与 Ledger 承担有权出售的自由库存。人工暂停不由收尾自动撤销。已结束但未交还的租约继续占用空间。组织、账户、股份及资产产权保留。没有设备产权交易与重新安装协议，因此本轮设备不出售；有设备或未结责任的企业继续等待处理。

收尾决定、恢复、库存处置和偿付具有独立开发授权，可引用正式组织根授权。工资、贷款、租金、服务、采购承诺及货损处置从原业务读取。收尾自由现金不再隐含按日结遍历顺序清偿；已预留合同资金仍按原条款使用。开发自动策略明确采用 WAGE → RENT → LOAN，同类按到期日和稳定引用排序，每两日最多处理一项，每币种每日最多15。额度从原 Ledger 当日收据派生，读档不刷新。此顺序不代表历史法律优先权。无策略时由合法控制者决定，退款和赔付仍走原 CargoFulfilment。

38日正式 WorldBootstrap / SimulationStep 局部场景：食品企业第31日、纺织企业第32日生效收尾。纺织企业经真实公告取得的采购机会，出售2单位衣物，收到80；买方形成各40的两份取得成本。纺织企业后续支付旧工资2和5。食品企业部分支付旧工资15，控制者通过原租金行动支付欠租4。第38日成熟欠薪分别为食品14、纺织179，未还贷款分别为本金4+利息2、本金11+利息3。食品场地仍因库存未迁出不能交还；纺织企业的旧租客及欠收租金10保留。

4名原纺织技能劳动者通过原欠薪离职和实际收到的招聘版本，于第35日接受上游岗位。第36—38日实际工作24小时，已收到工资64；旧工资债权不转移。上游里昂站点实际工时第34日15、第38日23；对应豆类活动实际批次3和4。未直接写入产量。第24、32、34、36、38日候选恢复成功。重复付款行动未再次采用，篡改授权的候选被拒绝且活世界未变。Application解析及经营查询只读检查通过；未作完整界面实机查看。
