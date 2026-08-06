# 正式产品系统完整性审计（2026-08-04）

## 结论

固定基线 `0feed6add253cead359a9e41f85e09bdf84c24e7` 上的正式产品不是完整的“社会人物—行动—世界反馈”游戏，而是一个经过测试的历史世界与国家聚合经济观察器：入口、时间、地图浏览、聚合经济、局部保存读取、Windows 导出均真实存在；权威玩家、业务行动、生活经济、旅行、社会知识、政治组织 AI 反馈以及完整会话持久化尚未组成连续闭环。

因此：

- 连续可玩正式产品：否。
- 正式发布就绪：否。
- `PLAYER_LOOP_COMPLETE` 系统：0/15。
- 五条要求的产品路径：2 条 `PARTIAL`，3 条 `MISSING`，0 条端到端 `VERIFIED`。
- 差距：24 项，其中 P0 4 项、P1 9 项、P2 8 项、P3 3 项；12 项阻断可玩闭环，21 项阻断正式发布。

本结论只描述实现事实，不降低 `docs/PRODUCT_VISION.md` 的长期愿景。愿景是目标，不是运行证据。

## 基线、边界与可复现产物

- 报告基线：`0feed6add253cead359a9e41f85e09bdf84c24e7`。
- 正式入口：`project.godot` 的 `application/run/main_scene` 指向 `res://scenes/formal/formal_world_menu.tscn`；无 autoload（E001）。
- 正式世界场景：`res://scenes/formal/formal_world_main.tscn`（E003）。
- 正式组合根：场景局部持有的 `FormalWorldSimulation`；当前只组合权威分钟与 `FormalWorldEconomyService`（E004、E006、E032、E045）。
- 正式存档：`user://formal_world_1900.json`，外层 schema `formal_world_simulation_v2`，覆盖时间和经济（E007、E018）。
- 机器可读事实基线：`artifacts/formal-product-system-completeness.json`。
- 生成与检查工具：`tools/audit_formal_product_systems.py`。
- 工具回归：`tests/tools/test_audit_formal_product_systems.py`。

JSON 产物刻意不记录分支、检出目录、用户名、临时目录、执行时间或当前提交 SHA，避免环境依赖和提交自引用。工具在调用时用 `--root`、`--expected-head` 和 `--report-base-sha` 验证检出身份；同一 Git 树应生成逐字节相同结果。

## 方法与证据规则

审计把“扫描事实”和“评审判断”分开：

1. 扫描器从正式主场景出发，递归追踪字面 `res://` 引用与实际使用的全局 `class_name`，建立正式可达图。
2. 对所有 Git 跟踪的可审计文件标记 `FORMAL_RUNTIME`、`FORMAL_DEPENDENCY`、`TEST_ONLY`、`LEGACY_REFERENCE`、`SPIKE_ONLY`、`TOOLING_ONLY` 或保守的 `UNRESOLVED`。
3. 扫描缺失的字面资源引用、CI 入口与统一验证入口。
4. 人工审阅 owner、写入点、生命周期、持久化、UI、因果反馈、测试能力和文档声明。
5. 每个判断引用 E001–E052；完整路径、符号、支持范围与不能证明的内容在机器产物 `evidence` 中。

以下内容不能单独证明正式完整性：文件名或类名、注释/TODO、设计文档、未执行测试、没有从正式入口可达的服务，以及单张截图。

## 正式运行边界

扫描得到的正式运行图包含 112 个文件和 6 个显式正式依赖文件。它包含 20 个带 `ui_spikes`/spike 来源命名的正式可达文件，以及 9 个 Alpha/V2 等旧版本来源命名的正式可达文件。目录名因此不能替代可达性判断。

关键的跨目录正式依赖是：

- `scripts/alpha/alpha_historical_world_economy_data.gd`：正式经济数据装载与覆盖校验（E030、E041）。
- `scripts/v2_2/v2_datetime.gd`：正式日期时间换算（E030）。
- `scripts/core/data_record_utils.gd`：正式数据读取辅助。
- `scripts/world_map/historical_map_identity_style.gd`：正式历史地图身份样式。
- `scripts/ui_spikes/holographic_workspace/*`：正式 UI 的深继承链；它们因为真实可达而属于 `FORMAL_RUNTIME`，不能再被当成纯实验垃圾（E003、E040）。

未从正式入口到达的核心 `ActionService`、`GameSessionService`、`SocietySimulationService`、`OrganizationService`、`RelationshipService`、`SimpleAiService`、`WorldActivityService`、V2.3 旅行/知识/通信服务，只能证明仓库内有孤立实现，不能提高正式产品成熟度（E020–E026、E032）。

## 15 个系统的成熟度总览

| ID | 系统 | 成熟度 | 正式事实 | 主要断点 |
|---|---|---|---|---|
| A | 产品入口与会话生命周期 | `PLAYER_LOOP_PARTIAL` | 菜单、初始化、自动新建/续档、时间、保存读取可达 | 无权威玩家会话、显式退出和完整恢复 |
| B | 时间与模拟调度 | `INTEGRATED_VERIFIED` | `total_minutes` 是正式累计时间，暂停/倍速/经济调度可验证 | 只有经济订阅正式调度；生命周期与诊断仍局部 |
| C | 世界状态与地理空间 | `PLAYER_LOOP_PARTIAL` | 历史半球和国家/行政/城市浏览可用 | 无权威位置、路径、旅行、地理状态持久化 |
| D | 玩家与角色 | `IMPLEMENTED_ISOLATED` | 正式 UI 有静态人物档案；仓库有核心玩家/行动服务 | 两者未组合，没有正式人物状态或生产行动 |
| E | 家庭与社会 | `IMPLEMENTED_ISOLATED` | 仓库有关系、家庭、通信实现与测试 | 正式入口只有静态投影，无关系—知识—行动链 |
| F | 经济与市场 | `PLAYER_LOOP_PARTIAL` | 国家聚合经济正式接入并有 90 日/十年验证 | 玩家、家庭、企业、劳动和政治反馈未接入 |
| G | 政治、法律与国家能力 | `IMPLEMENTED_ISOLATED` | 正式 UI 展示政治单元与静态概况 | 无政治变迁、法律、政策、国家能力写入 owner |
| H | 组织、机构与职业 | `IMPLEMENTED_ISOLATED` | 正式 UI 展示机构；仓库有组织/企业服务 | 无加入、职业、权限、决策和正式持久化 |
| I | 信息、知识、媒体与事件 | `IMPLEMENTED_ISOLATED` | UI 播种事件；仓库另有活动/知识/通信服务 | owner 冲突，事件无模拟后果与持久化 |
| J | AI 与自主模拟 | `IMPLEMENTED_ISOLATED` | 核心/Alpha AI 有实现和隔离测试 | 正式图无 AI owner、tick、写入或可见后果 |
| K | UI、反馈与可操作性 | `PLAYER_LOOP_PARTIAL` | 1280×720 正式地图、时间、政经查询、保存读取可操作 | 多数操作只改变 UI 状态，深 spike 继承难维护 |
| L | 保存、加载与兼容性 | `PLAYER_LOOP_PARTIAL` | 时间/经济磁盘往返与旧 schema 兼容有测试 | 非完整快照、直接覆盖文件、无坏档恢复 |
| M | 数据、内容与历史基线 | `INTEGRATED_VERIFIED` | 正式地图/经济数据确实装载并做 schema/覆盖校验 | 日期、历史/现代层、估算与许可未统一 |
| N | 性能、稳定性与可观测性 | `INTEGRATED_VERIFIED` | 聚合经济十年数值、耗时、队列和存档大小有门禁 | 无完整产品长跑、内存/泄漏和因果诊断 |
| O | 构建、发布与产品交付 | `INTEGRATED_VERIFIED` | Windows 嵌入 PCK 导出、启动、测试、截图工作流存在 | 无安装后完整旅程与发布许可门禁 |

计数为：`IMPLEMENTED_ISOLATED` 6、`INTEGRATED_VERIFIED` 4、`PLAYER_LOOP_PARTIAL` 5，其余成熟度均为 0。详细的生产文件、owner、读写者、生命周期、数据、UI、持久化、依赖、测试、CI、文档和 12 维判断见 `docs/audits/formal_product_system_inventory_20260804.md`。

## 五条产品路径

### 1. 启动—操作—保存—重新加载：`PARTIAL`

启动、菜单、世界初始化、正式时间推进均有生产与测试证据（E001–E006、E011）。玩家进入世界只是静态档案/视角，正式写入仅限推进时间、保存和读取；没有业务行动（E019、E032、E039）。保存只覆盖时间和经济，菜单没有显式退出，加载只能继续该子集（E007、E018、E038）。所以这不是完整玩家旅程。

### 2. 生活—工作—市场—长期决策：`MISSING`

市场自身会随时间变化且有十年稳定性证明（E009、E013），但玩家没有需求、工作、收入、消费或投资命令。国家聚合账本与人物生活状态之间没有因果契约（E031、E039）。

### 3. 移动/旅行—地理上下文—成本—恢复：`MISSING`

地图导航和政治/经济查询可用（E017、E044），但导航不是玩家位置。V2.3 旅行实现未正式可达；没有路径、时间/费用结算、行动上下文变化或存档恢复（E018、E026、E032）。

### 4. 社会/通信—知识—行动—后果—持久化：`MISSING`

正式 UI 从静态机构 agenda 播种事件和未读状态，仓库另有世界活动、知识和通信候选实现（E024–E026）。没有选定唯一 owner，没有知识影响行动的路径，也没有正式持久化。

### 5. 非玩家变化—玩家获知—应对—世界反馈：`PARTIAL`

聚合经济能产生非玩家世界变化，玩家能看到部分摘要（E009、E044）；政治、组织、AI 没有正式生命周期，UI 事件也不是模拟事件。玩家没有应对命令，后续反馈不存在（E024、E032、E039）。

## 持久化与状态所有权

`FormalWorldSimulation` 对时间和正式经济提供内存恢复事务：先验证候选，再提交；失败会恢复内存快照（E007、E012）。但产品级耐久性仍不成立：

- 外层文件直接以 `FileAccess.WRITE` 覆盖，没有临时文件、校验后替换、备份或坏档隔离；仓库已有 `AtomicJsonFileStore`，正式路径未使用（E007、E023）。
- 快照只有 `schema_id`、`total_minutes`、分钟余数和经济；玩家、行动、位置、地图/UI 状态、组织、关系、知识、事件、政治和 AI 均不在其中（E018）。
- 经济 `_last_day_index` 可独立恢复，但 `_validate_state()` 不验证它与权威小时一致；特制存档可能跳过日结（E010）。
- 正式、核心、Alpha、V2.2、V2.3 存在平行状态/存档协议；PR #38 的变量审计提供证据索引，但不能替代正式唯一 owner 的选择（E046、E047）。

## 历史、现代与实验边界

正式时钟从 1900-01-01 开始，而正式政治边界和政治单元目录声明的快照日期是 1900-03-12（E028、E052）。下级行政内容又明确包含现代参考 crosswalk 或仍需数字化的历史几何（E029、E043）。历史政治投影还把同一 `controller_id` 同时派生成 `sovereign_id` 和 `controller_id`，没有表达法理与实际控制差异（E027）。

这意味着目前的地图可作为有来源提示的浏览投影，不能被表述为统一时点、统一法理语义的权威 1900 空间模型。正式边界数据的源元数据声明 CC BY-NC-SA 4.0 且 `commercial_use_allowed=false`；这是必须由负责人审查并形成发布门禁的风险事实，不在本审计中作法律结论（E028）。

## 测试、CI 与“绿色”的含义

现有正式证据真实但范围有限：

- `tests/formal/formal_world_integration_test.gd` 覆盖场景、151 个政治单元、50 个经济聚合体、90 日推进、内存快照恢复和 UI 时间入口（E011）。
- `tests/formal/formal_world_long_term_balance_test.gd` 覆盖十年聚合经济数值、边界、队列、耗时、存档大小与恢复摘要（E013）。
- 正式时间稳定/已知缺陷测试覆盖暂停倍速、磁盘往返和失败内存回滚（E012、E049）。
- Windows 发布工作流运行导入、正式测试、启动和导出；UI 工作流捕获三个正式表面（E014、E015、E048）。

但 `tools/run_validation.ps1` 不运行旧 `tests/test_runner.gd` 或旧玩家旅程。前者仍断言已删除的 `scenes/menu/main_menu.tscn` 是主入口，二者引用多个缺失场景（E033、E034、E042、E051）。保留服务测试只证明孤立服务；截图只证明表面能实例化。当前 CI 绿色不能证明五条产品路径。

## 文档事实分级

| 声明来源 | 分级 | 原因 |
|---|---|---|
| `docs/PRODUCT_VISION.md` 的社会人物长期愿景 | `DESIGN_ONLY` | 目标有效，但大部分系统未正式组合（E036） |
| `docs/ARCHITECTURE.md` 的旧主菜单路径 | `STALE`/`CONTRADICTED` | 路径不存在且与 `project.godot` 冲突（E001、E035） |
| `docs/TEST_PLAN.md` 的广泛产品验证含义 | `PARTIALLY_SUPPORTED` | 正式经济/时间覆盖真实，完整旅程未进入统一验证（E034、E042） |
| 正式经济集成与长期平衡声明 | `TEST_VERIFIED`（限定聚合经济范围） | 有 90 日与十年运行测试（E011、E013） |
| PR #38 变量/状态审计 | `CODE_VERIFIED` 的状态索引证据 | 可用于定位 owner 冲突，不自动证明正式接入（E046、E047） |
| UI spike 文档 | `PARTIALLY_SUPPORTED` | 表面已成为正式运行依赖，但“spike”命名不再代表隔离（E003、E040） |

完整声明清单及每条引用在 JSON 的 `documentation_truth` 中。后续文档应明确区分 `DESIGN_ONLY`、正式运行事实、测试验证事实和历史里程碑，不应删除愿景来“修正”事实。

## 发布阻断与优先级

四个必须串行处理的 P0 是：

1. `FPSC-P0-001`：建立唯一权威玩家/会话/行动命令边界。
2. `FPSC-P0-002`：定义覆盖正式玩家、行动、时间和经济的完整快照及恢复顺序。
3. `FPSC-P0-003`：实现原子替换、备份和损坏存档恢复。
4. `FPSC-P0-004`：约束经济结算边界与权威小时一致，补恶意/损坏存档回归。

P1 才扩展生活经济、旅行、社会知识、权威事件、政治/组织/AI 反馈，并先解决正式/核心组合契约、地理/政治/经济稳定 ID、历史时点语义与许可门禁。完整差距登记、依赖、风险与验收见 `docs/audits/formal_product_gap_register_20260804.md`。

## 下一阶段唯一建议任务

建议只启动“建立正式会话权威与完整持久化契约”：以 `FormalWorldSimulation` 为唯一正式组合根，接入一个权威玩家实体、一个最小生产行动命令，并先定义覆盖玩家、行动、时间、经济的事务快照。

完成定义：

- 新建与继续游戏都只产生一个权威玩家实体。
- 至少一个玩家行动经过权威重验，改变正式状态并获得 UI 反馈。
- 完整状态可保存，进程退出、重启加载后继续。
- 有效、无效、中断和旧版本存档通过事务与兼容回归。
- 1280×720 自动旅程、正式状态一致性、磁盘故障注入、统一验证和 Codex 审计回归均通过。

本阶段不得恢复旧场景作为第二入口，不得一次接入全部 Alpha/V2 社会系统，也不得把新的业务状态写入 UI 或 spike 继承层。

## 审计限制

本任务不修改生产实现，不声称人工 1280×720 旅程、长期完整产品性能或安装后产品体验已通过。静态扫描不能发现所有反射式动态引用，也不能替代 owner/因果审阅；因此未知项保持 `UNKNOWN` 或保守成熟度，而不是以“代码存在”推断完整。
