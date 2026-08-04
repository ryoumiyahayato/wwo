# 正式产品系统所有权基线

## 目的

本文固定 `0feed6add253cead359a9e41f85e09bdf84c24e7` 上 A–O 系统的当前 owner、读写边界、生命周期与持久化责任，并给出下一阶段应收敛到的唯一 owner。它是后续重构的约束基线，不授权本审计修改生产实现。

PR #38 的 `docs/audits/variable_state_audit_20260803.md` 与 `artifacts/variable-state-audit.json` 是逐成员读写/持久化证据索引。本文件使用其证据定位重复或近似状态，但不因同名自动合并状态；动态调用、信号和 UI cache 仍需行为测试。

## 全局所有权规则

1. `FormalWorldSimulation` 是唯一正式会话组合根；新增正式系统必须由它或显式子服务拥有生命周期，不得由 UI、autoload、旧产品场景或测试夹具暗中创建第二实例。
2. 正式累计时间唯一可写 owner 是 `FormalWorldSimulation.total_minutes`。`minute_remainder`、经济 `total_hour` 和日期显示是派生/兼容视图。
3. UI 只能发命令和读投影；selection、hover、展开状态、几何 cache 可以归 UI，玩家、行动、经济、事件、政治、组织和 AI 事实不得归 UI。
4. 每类持久状态只有一个 schema owner。兼容字段、索引和 cache 必须能追溯到权威来源，并明确重建/校验规则。
5. 正式运行依赖以可达图为准。Alpha/V2/ui_spikes 来源文件若正式可达，就必须有正式维护 owner；未可达服务保持隔离，不能以“仓库已有”直接接入。
6. 新系统接入顺序是 owner → 命令/查询 → lifecycle → snapshot/restore → UI → 因果/旅程测试；不得把持久化留到最后补。

## 所有权总表

| ID | 当前正式 owner | 当前写入者 | 当前主要读取者 | 建议唯一 owner | 主要冲突/禁止缓存 |
|---|---|---|---|---|---|
| A | 场景局部 `FormalWorldSimulation`，但没有 player session owner | menu/application/simulation | menu、application、UI draw | `FormalWorldSimulation` 组合根 + 一个 session 子服务 | 禁止第二正式入口、autoload session、UI 玩家事实 |
| B | `FormalWorldSimulation.total_minutes` | advance/restore；UI 只发推进命令 | 经济、应用、time HUD | 保持现 owner | 禁止第二可写年月日/小时；余数只作派生/兼容 |
| C | 地理资料无可变世界 owner；selection/cache 归 UI | workspace input/loaders | map draw、polity query | 不可变 WorldGeography catalog + PlayerLocation 子状态 | 禁止把 selection 当位置；禁止重复政治/地点 ID |
| D | 无正式 player owner；静态 `active_character_key` 归 UI | UI switch；隔离 GameSession/Action | HUD、隔离服务 | 一个 FormalPlayerSession/命令边界，由组合根持有 | 禁止 `active_character_key` 成为第二玩家事实 |
| E | 无正式社会 owner | UI mark-read；隔离关系/通信服务 | static HUD、旧接口 | 选定一个 relationship/household service | 禁止平行关系图、消息 store、家庭 ID 空间 |
| F | `FormalWorldEconomyService` | configure/settle/restore | simulation、政经 panel | 保持聚合经济 owner；个人账本另有明确子 owner | 禁止 UI/Alpha service 复制 country ledger |
| G | 无可变政治 owner；历史目录是不可变投影 | data loaders | map/polity summary | FormalPoliticsService（接入时） | 禁止 controller/sovereign 同字段无语义复制 |
| H | 无正式组织 owner；静态 institution dictionary 在 UI | loader；隔离 OrganizationService | map/HUD、旧社会系统 | 选定一个 FormalOrganizationService | 禁止 UI agenda/membership 成为权威组织状态 |
| I | 当前事件由 UI `_world_events` 拥有；另有隔离候选 | `_seed_world_events`/mark_read、isolated services | activity HUD、旧接口 | 一个 FormalWorldActivity/Knowledge owner | 禁止 UI 生成世界事实；未读必须是投影或明确用户状态 |
| J | 无正式 AI owner | 隔离 core/Alpha AI | 隔离 tests/products | 由组合根注册的唯一 AI scheduler/state | 禁止 AI 自带时钟、第二社会图或直接 UI 写入 |
| K | UI selection/cache；`_last_summary` 为投影 | input/refresh/button handlers | draw methods | 视图 owner 保持 UI；业务命令交给 A/B/F/L 等 | 禁止 UI 持久化业务事实或直接修改服务内部字段 |
| L | `FormalWorldSimulation` 拥有 formal outer schema/file path | `save_to_user` | menu/load | FormalSaveCoordinator + 原子 file store，仍由组合根编排 | 禁止多 owner 写同一文件；禁止直接覆盖唯一有效档 |
| M | 打包源文档；runtime loaders 各持只读 cache | offline generators/runtime loaders | map/economy | 版本化 FormalDataCatalog/adapter 清单 | 禁止现代参考静默变历史事实；cache 不得成为可变事实 |
| N | 各服务局部 bound + CI；无诊断 owner | economy/loaders/tests | logs/UI error panel | 有界 FormalDiagnostics contract | 禁止逐小时海量日志、联网遥测、无上限 event queue |
| O | CI/export workflow | stamper/exporter | Godot exporter/installer | release workflow + machine-readable manifest | 禁止在无许可/旅程门禁时标记正式 release-ready |

## A. 产品入口与会话生命周期

- 当前 owner/lifecycle：menu 自动决定 new/load；main scene 创建局部 `FormalWorldSimulation`；timer 在场景存活时驱动。退出没有 owner。
- 持久化责任：A 只编排 L；不能自行维护第二份 session snapshot。
- UI 边界：菜单可以持 launch mode/status，不能持玩家或世界事实。
- 冲突：核心 `GameSessionService` 是另一个候选组合点，当前未正式接入。直接实例化会造成双 session。
- 应收敛：保持 `FormalWorldSimulation` 为组合根，显式注入一个玩家/session 子服务并定义 new/load/shutdown 顺序。
- UNKNOWN：窗口关闭、异常退出、坏档后用户路径在完整产品中的最终策略。

## B. 时间与模拟调度

- 当前 owner/lifecycle：`total_minutes` 由 initialize/advance/restore 写；timer 只调用正式入口。
- 持久化责任：outer schema 保存累计分钟与兼容余数；经济验证接收的小时。
- UI 边界：`sim_paused`/`sim_speed` 是交互控制，不是第二时钟。
- 冲突：V2/Alpha 旧时钟存在但未正式可达；禁止接入第二可写日期时间。
- 应收敛：其它系统订阅由组合根发出的明确边界事件，结算使用区间开始时已保存的效率/上下文。
- UNKNOWN：未来日/周/月调度的顺序、失败隔离和 budget contract。

## C. 世界状态与地理空间

- 当前 owner/lifecycle：历史几何和目录作为只读资料加载；country/region/city selection 与几何/index cache 归 UI。
- 持久化责任：当前无玩家位置/旅行；UI selection 默认临时。
- UI 边界：选择政治单元可查询经济，但不改变世界。
- 冲突：政治单元、经济体、现代 admin/city 和未来 LocationId 是不同 ID 空间；controller/sovereign 语义尚未分离。
- 应收敛：不可变 geography catalog 拥有地理资料；玩家子状态拥有唯一 LocationId；crosswalk 版本化、双向校验。
- 禁止缓存：不得把 `selected_country_id`、地图中心或 hover 当玩家位置；派生 index 必须可重建。
- UNKNOWN：正式路线图、边界时点切换、海陆通行和位置迁移 schema。

## D. 玩家与角色

- 当前 owner/lifecycle：正式 UI 的 `active_character_key` 只选静态档案；核心 `GameSessionService.player_character` 与 `ActionService` 隔离。
- 持久化责任：正式档案选择不保存；核心 player protocol 不是 formal schema。
- UI 边界：profile/viewpoint 只能读玩家投影，不得成为身份来源。
- 冲突：对象、稳定 CharacterId、UI profile key、地图 selection ID 不是同一层级，不能按近名合并。
- 应收敛：组合根持一个权威玩家实体和命令 dispatcher；行动完成由权威服务提交，UI 不直接写属性。
- UNKNOWN：正式产品复用核心 GameSession/Action、做适配器或建立更小实现的选择。

## E. 家庭与社会

- 当前 owner/lifecycle：正式无 owner/tick；relationship、household、communication 分属多个隔离产品线。
- 持久化责任：正式 schema 不覆盖任何社会状态。
- UI 边界：静态 known agenda 不是关系或家庭状态。
- 冲突：核心 RelationshipService、V2 household/communication 和 society composition 可能重复人物/关系/message ID。
- 应收敛：在接入前选择唯一 relationship/household owner；写入只通过稳定 ID 和双向索引不变量。
- 禁止缓存：UI 不持第二份关系边；知识/未读不能静默充当关系强度。
- UNKNOWN：家庭和关系是一个服务还是两个事务协作者，以及社会更新的正式频率。

## F. 经济与市场

- 当前 owner/lifecycle：`FormalWorldEconomyService` 拥有 50 个经济聚合体、routes、shipments、history 和日结；权威时间由 B 注入。
- 持久化责任：经济 schema v1–v3；restore 候选先验证。`_last_day_index` 仍需与小时约束。
- UI 边界：world/polity summary 是只读投影；无玩家市场命令。
- 冲突：Alpha/V2 的家庭、企业或劳动账本未正式接入，不能和 `country_states` 当作同一账本直接合并。
- 应收敛：保持聚合 owner；未来个人/家庭/企业账本通过显式交易/统计契约影响聚合层。
- 禁止缓存：UI `_last_summary` 不可写回；crosswalk/index 可重建，不是第二经济事实。
- UNKNOWN：个人交易如何守恒地聚合、政治政策写入权限以及低细节国家的模拟边界。

## G. 政治、法律与国家能力

- 当前 owner/lifecycle：历史政治目录和概况是只读投影；没有可变政治 tick。
- 持久化责任：无正式政治状态。
- UI 边界：边界、status、relationship、controller 只能显示来源语义。
- 冲突：旧 AlphaPoliticsService 不可达；投影把 controller 同时写作 sovereign/controller。
- 应收敛：数据契约先分历史法理/控制，再由一个 politics service 拥有政策、合法性和能力变化。
- 禁止缓存：UI 派生政治 record 不得成为可写 owner；经济政策不得在两个服务各存一份。
- UNKNOWN：战争/控制变化与历史快照切换的正式事件模型。

## H. 组织、机构与职业

- 当前 owner/lifecycle：UI 加载静态 institutions/organizations；核心 OrganizationService 与 AlphaEnterprise 隔离。
- 持久化责任：正式无 membership/position/career snapshot。
- UI 边界：institution/agenda 只读；加入、任职、工作必须走命令。
- 冲突：静态 institution ID 与核心 organization ID/position 规则没有正式 crosswalk。
- 应收敛：选一个 organization owner，维护成员、职位、权限和稳定 ID；职业/企业作为明确依赖而非复制成员表。
- 禁止缓存：UI 不维护权威 membership/agenda；AI 不直接改组织数组。
- UNKNOWN：现有核心服务能否覆盖正式历史机构语义。

## I. 信息、知识、媒体与事件

- 当前 owner/lifecycle：UI ready 时从 institution agenda 生成 `_world_events`，并持 `activity_unread`；另有 `WorldActivityService`、Knowledge/Communication 候选。
- 持久化责任：正式完全未保存事件、知识或未读。
- UI 边界：UI 只能读 event projection、发 mark-read/communication 命令；不得 seed 世界事实。
- 冲突：UI event、WorldActivity event、communication message 与 knowledge fact 的 ID/可见性/因果未统一。
- 应收敛：一个事件 owner 生成因果 ID，一个 knowledge/visibility owner 决定玩家可见投影；未读明确属于用户 UI 状态或可重建投影。
- 禁止缓存：任何 UI event list 不得被业务逻辑反向读取为世界事实。
- UNKNOWN：event 与 knowledge 是同一存档事务的子服务还是独立日志，以及保留/压缩策略。

## J. AI 与自主模拟

- 当前 owner/lifecycle：正式无 AI；核心/Alpha 各有状态和日决策实现。
- 持久化责任：无正式 AI schema。
- UI 边界：未来 intent/后果是投影，不允许 UI 驱动 AI 状态。
- 冲突：旧 AI 可能携带自己的时钟、人物/组织引用和产品线存档。
- 应收敛：组合根注册一个有预算的 scheduler；AI 只经与玩家相同的权威命令入口写世界。
- 禁止缓存：AI 不持第二社会图/经济账本；不做每小时全人物扫描或海量日志。
- UNKNOWN：选择哪个 AI 实现、背景人物分层与确定性 seed 生命周期。

## K. UI、反馈与可操作性

- 当前 owner/lifecycle：17 层 spike-provenance 继承链持 selection、hover、panel、几何和 draw cache；timer 受控刷新。
- 持久化责任：默认 UI 状态不保存；若将来保存工作区，必须独立于业务快照并可丢弃。
- UI 边界：允许输入适配、只读投影和 cache；只有命令/查询接口跨入模拟。
- 冲突：`active_character_key`、`_world_events` 等原型字段已越过纯视图边界。
- 应收敛：用行为特征测试保护现表面，再将正式 composition/view boundary 显式化；不一次重写整条 UI 链。
- 禁止缓存：`_last_summary`、indexes、projected records 不能被模拟读取；必须有明确 invalidation。
- UNKNOWN：最终拆分粒度、主题/渲染层复用和键盘焦点/退出行为。

## L. 保存、加载与兼容性

- 当前 owner/lifecycle：`FormalWorldSimulation` 持 `SAVE_PATH` 和 outer schema；menu 自动探测；load 初始化候选后校验/提交。
- 持久化责任：当前仅时间/经济；文件直接覆盖。核心 `AtomicJsonFileStore` 是可复用能力证据，不是当前 formal owner。
- UI 边界：菜单/按钮只发 save/load 命令并展示结构化结果。
- 冲突：formal、core、Alpha、V2.2、V2.3 多协议并行；同名 key 不等于同 schema。
- 应收敛：由组合根编排唯一 FormalSaveCoordinator，列出全部子状态、版本、恢复顺序、不变量、rollback；file store 只负责原子耐久性。
- 禁止缓存：不得由多个服务直接写同一正式文件；不得因坏档存在就无限自动续档。
- UNKNOWN：多槽位需求、backup 保留、未来迁移注册和用户可见恢复政策。

## M. 数据、内容与历史基线

- 当前 owner/lifecycle：版本化 JSON 是打包输入；经济和 UI loaders 各建只读 cache/index。
- 持久化责任：源数据不进入 session snapshot；派生可变经济由 F 保存。
- UI 边界：来源、日期、置信、modern reference 和 admission status 必须可见。
- 冲突：1900-01-01 时钟、1900-03-12 边界快照和现代 admin crosswalk 时点不同；Alpha 路径实际正式可达。
- 应收敛：维护显式 FormalDataCatalog/adapter manifest，版本化时点、许可、ID crosswalk 和运行接纳规则。
- 禁止缓存：loader cache 不可成为可变政治事实；bounded estimate 不得丢 provenance。
- UNKNOWN：正式基准日选择、商业发布数据替换和历史下级几何优先范围。

## N. 性能、稳定性与可观测性

- 当前 owner/lifecycle：经济内部有 queue/history 上限；CI 测十年；UI 只显示数据错误。
- 持久化责任：metrics/logs 不属于存档；因果 ID 若影响恢复需由事件 owner 保存。
- UI 边界：可显示有界诊断，不引入联网遥测。
- 冲突：通过经济长跑被误读为完整组合性能；retained tests 被误读为 formal coverage。
- 应收敛：统一 error code/stage/causal ID contract；完整组合建立 30 日/一年/三年 CPU、内存、queue、资源、存档大小基线。
- 禁止缓存：无界日志/event history、每小时全人物扫描、后台人物节点均禁止。
- UNKNOWN：发布崩溃诊断形式、内存阈值和平台实际预算。

## O. 构建、发布与产品交付

- 当前 owner/lifecycle：workflow 负责 checkout、stamp、import、tests、startup、export、installer、artifact/release。
- 持久化责任：构建 manifest 与 session save 分离；发布必须依赖 L 的完整性门禁。
- UI 边界：截图/启动 smoke 只能证明表面，不证明旅程。
- 冲突：正式导出可成功，但历史数据许可和完整玩家闭环未满足。
- 应收敛：release manifest 列正式 entry、数据许可、schema、测试旅程和构建身份；不同 release channel 有明确 gate。
- 禁止缓存：不得把未执行的人工平台测试写成通过；不得触碰无关发布/PR 流程。
- UNKNOWN：安装后 Windows 实机 smoke、签名/分发策略和商业发行许可决定。

## 下一次所有权评审的门槛

只有在以下证据同时存在时，某隔离服务才能提升为正式 owner：正式入口可达；组合根创建且唯一；权威命令和只读查询明确；生命周期和时间边界明确；完整 snapshot/restore/rollback；UI 无直接写入；至少一个因果旅程和状态一致性回归；旧产品线仍被明确隔离。缺一项时保守保持 `IMPLEMENTED_ISOLATED` 或 `PLAYER_LOOP_PARTIAL`。
