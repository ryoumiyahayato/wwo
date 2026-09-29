# 运行与状态规格

规范词“必须”表示实现验收要求。所有新增类型和 API 均为拟议接口，不能当成已存在的方法调用。

## R01. 运行边界

采用 Godot 4.6.3 Standard、强类型 GDScript、单进程、单模拟写入线程。保留 RefCounted 数据服务；地图和 UI 是读者。先不增加 ECS、数据库、脚本语言、在线 AI、消息中间件或通用插件系统。

`VNextWorldRuntime` 唯一拥有世界时间、领域实例及整体快照。新增 `WorldStepCoordinator` 只编排固定阶段，显式注入 Economy、Finance、Labor、Spatial、Military、Politics 等类型；它不能通过任意字符串调用任意业务方法。`WorldScheduler` 只管理到期时间和任务 ID；业务结果由领域计算。

```text
玩家输入 / NPC 决策
         ↓ 同种有类型命令
身份与已知条件预检 → 命令收件箱
         ↓ 到生效时间再核验
WorldStepCoordinator
  结算旧区间 → 到达与失效 → 到期收支 → 需求与决策
  → 共同资源分配 → 候选验证 → 整体提交
         ↓
各领域唯一事实 → 只读摘要 / 已提交事实 → 知识与下一轮决策
```

运行时只创建一组领域对象。每次提交不重建全世界。UI 查询返回有类型值或副本，不能拿到可写库存 Dictionary。现有公开字典逐步改为私有；开发命令也走同一验证器。

## R02. ID、单位、整数运算

运行身份与静态资料引用分开：

| 项目 | 契约 |
|---|---|
| person / organization / place / formation | 复用 VNextStableId；现有地图原始 ID 经显式 crosswalk 转换 |
| 法定政治实体 | `polity_id` 指向历史政治目录；不等同于国家市场、政府组织或几何 feature |
| account / stock / process / claim / order / cohort | W01 增加明确有类型 ID；不可未经修改就通过现有 StableId 白名单 |
| position / appointment | 保持 `(organization_id, local_id)` 联合键；不引入冲突的全球职位 ID |
| 时间 | 从 1900-01-01T00:00 起的整数分钟；日期转换只读；每个游标标识已结算区间，不是另一只可推进时钟 |
| 现金、存款、债务 | `currency_id` + 整数最小货币单位；不同货币不可直接相加 |
| 商品 | 每种商品定义 `quantum`，库存为整数 quanta；配方投入输出也用 quanta |
| 运输 | 统一整数载荷单位 LU；商品定义 `load_lu_per_quantum`，人员和车辆定义对应占用，不再猜 food/supply points 换算 |
| 劳动 | 整数人和整数人分钟；同一人同时只能有一个互斥主要劳动状态，可跨时段分配工作 |
| 概率、比例 | 整数 basis points，0..10000；时间积分保留余数 |

商品目录还必须区分 `stockable` 与 `capacity_service`。面粉/炮弹进入库存；住房、授课、运输服务按时段占用容量，不生成可囤积或运往前线的“服务库存”。两者可共用价格/付款机制，交付分别走库存转移或服务过程。现有67商品中每一项都必须显式归类，禁止仅凭名称猜。

计算 `a*b/divisor` 前必须检查乘法溢出，或采用已测试的商余分解函数。持久 JSON 整数限定在 ±(2^53−1) 内；运行 int64 也不能先溢出再检查。浮点只用于只读几何、路径估计与非权威显示。几何转为整数路段耗时只在规划时执行，结果持久化；本版重放目标为同引擎/同规则包，跨平台位相等另验。

比例整数分配统一使用 Hamilton 最大余数法：`base_i=floor(Q*w_i/sum(w))`；剩余单位按余数降序、稳定 ID 升序分配。上限不足的条目先封顶，然后对剩余集合重分配。零权重全返回零，不除零。不要分别 round 后修正世界总量。

积分采用 `whole,carry=divmod(rate_num*elapsed_minutes+carry,rate_den)`。同一过程分 60 次一分钟和一次 60 分钟必须相同。变更速率前先用旧速率结算，再记录新速率；余数属于过程且进入存档。负收益使用带符号且已定义舍入的版本，不复用只适合非负流量的辅助函数。

## R03. 唯一事实表

表名是逻辑记录集合，可在 GDScript 内用带稳定排序索引的字典实现。主键、引用、数量约束必须有验证器。

| 唯一 owner | 主记录及关键字段 | 约束与其他领域读法 |
|---|---|---|
| Person | person_id, birth_date, health, alive, skills, allocation_ref | 命名人口是人口内覆盖记录；PlayerState 只选 person_id |
| Organization | organization, membership, position, appointment | 职位不保存余额或军队兵力；任命带起止时间 |
| Population | 现有人口边际、流量、余数、place_id | 所有年龄/性别/城乡轴各自等于总人口；它们不是可相加的独立人口 |
| Labor | cohort_id, place_id, eligible_people, employment_allocations, service_allocations, named_claims | 劳动子集互斥且不超过工作年龄人口；薪资合同不等于会员关系 |
| Finance | account, ledger_entry, reserve_hold, claim, loan, budget | 每条付款有来源与接收账户；预算和预留不是额外的钱 |
| Economy/StockLedger | stock_id, owner_id, custodian_id, place_or_transit_id, commodity_id, quantity, reserved | 同一批在仓/在途只能有一种位置；所有者和保管人可不同 |
| Economy/Production | site_id, operator_org_id, recipe_id, installed_capacity, condition, process_id | 产量来自被占用的投入、劳动和机器；地区产能只是聚合查询 |
| Economy/Trade | order, match, delivery_obligation, shipment | 订单不保存额外库存；在途货由 StockLedger 保管引用 |
| Spatial | topology、设施状态、capacity_window、territorial_facts | 基础设施占用唯一；控制事实细分法定归属/行政管辖/军事控制 |
| Military | formation, personnel_assignment_ref, orders, engagement, posture | 人力、物资只引用分配与库存；战斗不得独自减少宏观人口 |
| Politics/Institution | rule_version, jurisdiction, proposals, ballots, issue_preferences, support | 权利规则和具体执行任务分开；政府职位来自 Organization |
| Knowledge | fact_report, audience, delivery_time, belief, source | 真实事实和获知事实分开；无消息不可访问敌方精确库存 |
| Process owner | 下述 ProcessHeader + 有类型业务 payload | Scheduler 只保存 ID 和时间，不复制 payload |

库存恒等式逐商品验证：

`期初在仓+在途 + 生产 + 外部导入 − 生产投入 − 居民消费 − 军用消耗 − 损失 − 外部导出 = 期末在仓+在途`。

“预留”是库存子集；“应交货”是义务；都不能额外加入数量。原料转成产品分别进入投入/产出流量；不同商品的件数无需相等，配方的质量与能量守恒只在配置明确提供换算时验证。

人口守恒：`总人口变动=出生−死亡+外部迁入−外部迁出`。内部迁移净和为零。征兵、退役、罢工、受伤、就业改变分配状态，不自行改变总人口；战死必须以同一 casualty_id 一次提交 Person、Labor、Population、Military。

## R04. 命令和过程

```text
CommandHeader:
  command_id, issuer_person_id, acting_org_id?, appointment_local_id?,
  submitted_minute, effective_minute, kind, expected_revisions,
  cause_ids[], schema_version

ProcessHeader:
  process_id, kind, principal_id, executor_id,
  status, last_settled_minute, next_due_minute,
  generation, reservation_refs[], cause_ids[], payload_version

CommandResult:
  command_id, status(accepted/rejected/queued), reason_code,
  changed_refs[], process_id?, limiting_resources[], effective_minute
```

按类型分别定义 payload，不用无约束任意 effects 列表。工作、出价、排产、运输、提案、投票、任命、军事命令都调用明确入口。个人买食物只检查个人权利/现金/位置；替组织花钱必须指定一个当前有效身份，不合并所有职位的授权。

`expected_revisions` 是冲突检测提示；实际生效时重新核验生死、位置、任命、规则、库存和预算。预览不是预留。`command_id` 去重：同 ID 同 payload 返回已存结果，同 ID 不同 payload 返回 `ID_REUSED_WITH_DIFFERENT_PAYLOAD`。

任命失效使未来需要该人物新签署的命令失效，不抹去其在有效任期内已经让组织承担的合同。已成立组织债务继续到期，由组织的有效执行人处理；某部长死亡不能让国库债务自动清零。

过程状态允许 `queued → reserved → running ↔ blocked → completed/cancelled/failed`。实际运输另用装卸/路段 payload，投票另用提名/表决 payload，不强迫所有领域用同一业务状态机。blocked 保留过程和明确重试事件，不能每帧再试。终态释放未使用预留并结清/转移义务；不能删除已交付或已工作部分。

预约延期必须持有到期时间。命令接受不代表资源已经获得；缺资源可创建排队意图，只有分配提交成功才产生预留。

法律不是物理引擎的万能禁止开关。无授权调用政府转账必须拒绝；想从事盗窃等非法行为必须调用独立行为，其执行由实际人员、空间、防卫与侦测过程决定，并产生案件。不能让普通采购通过 `illegal=true` 绕过身份核验。

## R05. 同一时刻的唯一顺序

一个已提交世界 `S_t` 包含事实和正在执行的资源分配。下个边界是目标时间、下个到期过程、下一整点/日界/月界中最早者。只跳过没有持续流量且没有业务边界的空区间。

| 相位 | 边界 t 的处理 | 可见状态与结果 |
|---|---|---|
| 0 结算旧区间 | 按 `[last,t)` 的旧速率/姿态/合同结算生产、工作、旅行、战斗 | t 时开始的政策不能回溯修改过去；同时伤亡用区间开始双方状态 |
| 1 完成和失效 | 到货、伤亡、合同完成、命令到达；到期任命/禁令退出 | 先落下已经完成的物理事实；t 新任命不能冒领旧劳动收入 |
| 2 到期收支 | 到期工资、税、利息、到期补助；先形成债权，再按法定清偿顺序支付 | 没钱留下欠款，不回滚已完成劳动；同刻到货可用于随后市场 |
| 3 观察和决策 | 投递已到达报告；更新本期群体评价；执行到期程序；玩家/NPC 生成新命令 | 同一主体同一相位最多一次决策，全部读取本相位开始视图 |
| 4 资源计划 | 核验命令；形成交易、劳动、原料、运力、资金需求；求本轮分配 | 无实际写入；所有消费者同窗口共同竞争 |
| 5 验证并提交 | 验证 touched records 和跨表守恒，一次发布新事实/新预留/新游标 | 新区间从 t 开始；新产出至少在正时长后可用 |
| 6 派发 | 写已提交事件、脏索引、下一到期项、只读 UI 摘要 | 通知处理不得在同栈再改账；需要反应进入未来相位/时间 |

以上相位本身是同一边界的候选写集。相位间可以读前一相位已验证的候选结果，但不得在中途发 UI 信号或落盘。异常放弃整个当前边界候选，活世界保持最近完整提交。业务缺钱/无权限是正常拒绝结果，不是引擎异常。

每日市场只在日界运行；每小时安排下一小时生产和运输；工资按分钟应计、按合同日期到期；政治评价按日、政治策略按周或显著事件；人口自然流按真实日历月；交战和个别过程按整数分钟。所有频率是模型规则，不能随镜头或 CPU 负载改变。

### 停在小时中间

已承诺的本小时劳动、原料及载荷额度属于持续过程。到 t=30 分钟的玩家命令：先结算 0..30，再处理命令；取消只释放未执行部分。生产按已完成批次交付，半成品继续保留。运输按实际路段进度，不凭容量额度瞬间到达。

桥梁在分钟 30 损坏：过去占用保留，未来半小时不能继续进入这条链路。已在路上的货进入该路段的“等待修复/损坏损失”规则；未发货继续在原库存。不能重算整个小时抹掉过去运输。新急件可用本窗口剩余额度，不能回收已承诺的普通货额度；带合法优先权的改派需要显式取消未来部分并生成补偿义务。

### 推进伪代码

```text
advance_to(target):
  require target >= committed_minute
  while committed_minute < target:
    t = min(target, next_due, next_required_calendar_boundary)
    frame = begin_candidate(touched_records_for_interval_and_due_jobs)
    settle_previous_interval(frame, committed_minute, t)
    apply_completions_and_expiries(frame, t)
    settle_due_obligations(frame, t)
    deliver_reports_and_collect_decisions(frame, t)
    demands = collect_typed_resource_demands(frame, t)
    allocations = allocate_shared_resources(frame, demands, t)
    prepare_all_domain_changes(frame, allocations)
    if not validate(frame): return failure_at(committed_minute)
    commit_all_owners_without_callbacks(frame)
    committed_minute = t
    publish_after_commit(frame)
```

`target` 仅为了展示而截短时，不触发不在该时刻到期的日/小时决策；不能让 `advance(60)` 多调用次数导致更多收入或更多 AI 决策。暂停时提交命令允许在当前时刻处理一次命令边界，下一行为若需要时间，必须安排到未来。

已完成相位的即时事件只能指向本边界更晚相位；更早相位的反应安排到最早合法后续分钟。运行时记录 `(minute,completed_phase)`，不能从堆里重复拿到同一已结算边界而卡住。业务间零时间循环由此被拒绝并给出循环链，不能以静默丢事件解决。

## R06. 原子提交、失败和冲突

不依靠事件链“经济扣钱成功，等军事收到消息再给货”。明确三种跨 owner 事务：`TradeSettlement`、`ResourceDispatch`、`PersonnelTransition`，其余按需增加有名事务，不先造任意业务 DSL。

每种事务执行：读取 revision → 生成各 owner 候选记录 → 核验全部前置条件和守恒 → 安装所有已验证记录 → 发布一个 commit_id。安装阶段无 await、外部调用和用户回调；仅赋值，不得再发现业务验证失败。内存成本与触及记录相关，不是每个命令深拷贝整个世界。

同阶段的冲突在分配器解决，不采用“后一个失败再无限重试”。公平资源见 A01。有限预算竞争采用事先确定的债务/预算优先级。跨阶段 revision 已过期的命令在当前视图重算一次；仍冲突则排到下一明确边界。

固定故障注入点：每个 owner prepare 之后、全局 validate 之后、commit 之前。任一失败必须保持快照 hash 不变，无事件、无 ID 漏发、无资金/货物变化。真实进程崩溃后恢复最后完整存档；本版不承诺未保存分钟的持久事务。内存原子性和落盘耐久性要分别报告。

## R07. 调度和反应成本

最小堆 key=`(due_minute, phase, owner_kind_order, stable_process_id, generation)`。更改到期时间递增 generation，弹出的旧 generation 丢弃。死任务占比超过 50% 时在已提交边界重建堆；重建是派生操作，不改变任务顺序。禁止同一 job 反复调度到自己当前/更早相位，避免零时间死循环。

依赖索引使用领域已知键：`link→shipments`、`stock→production/obligations`、`account→claims`、`appointment→pending_commands`、`cohort→employment/unions`。每次开始/取消/变更过程同步增删索引，恢复后从事实重建，并与慢扫描对照验收。不要订阅所有字段。

价格软变化达到上次决策价的 5%、现金预计不足 3 日、库存低于 2 日需求，标记主体 dirty；同日软通知合并。硬事件如死亡、到期、断路、欠付、撤职不得被阈值过滤。周期复查最迟 7 日防止小变化累计永不触发。dirty 只省决策，不能省账。

成本模型明确包含背景结算：

`O(D log P + Σ日(活跃市场商品格 + 生产点 + cohort) + Σ窗口(竞争请求排序) + 活跃战斗步数 + dirty主体×候选数)`。

P 是持久过程数，D 是到期数。不能声称复杂度与全世界规模完全无关：人人吃饭的日界，本来就会覆盖所有人口聚合格。

初始性能目标：单帧模拟工作最多约 4ms 后 yield；后台候选完成前 UI 保持最后提交状态，世界时间不先跳到 target。预算不足降低现实推进速度，不能丢请求、让国家停算、跳过工资或按首 256 运单永远截断。大批次分片保存处理游标，结果不依分片尺寸。

## R08. 读档、重放和快照

新增完整世界 schema `vnext_world_runtime_v3`，精确包含：scenario_id、start_datetime、total_minutes、rules_hash、catalog_hash、各领域状态、所有持久过程、资源预留、到期游标/积分余数、命令幂等结果、随机流状态或计数、sequence、session(person_id)。当前 v2 的严格六字段验证器不可直接塞额外字段。

保存只发生在完整提交边界。调度堆与依赖索引可重建，但下一次到期时间、generation 和过程内部余数必须保存。不能从 UI 当前订单列表恢复世界。随机按 `(world_seed, subsystem, actor_id, decision_index)` 分流；不得用无稳定保证的容器 hash 或运行时间作为种子。

幂等历史采用每个签发者的单调 command_sequence：近期结果保留，未终结过程的结果始终保留；超过归档水位的旧序号一律返回 `COMMAND_ARCHIVED`，不能当作新命令重新执行。归档水位及未结命令索引进存档。详细事件报告可限制窗口，财务期初结转和未结债权不能因日志截断消失。

加载：新建候选各 owner → schema/单位/范围 → 全部引用 → 预留和总量守恒 → 规则及目录版本 → 过程时序 → 重建索引 → 一次替换当前世界。拒绝时原世界和对象引用保持可用。

旧 Formal 存档只有国家聚合数据，无法恢复不存在的企业/劳动/债务历史。W18 应实现明确的迁移报告：能守恒映射的库存/日期保留；缺少所有权的库存分配给声明的 opening aggregate owner；不生成虚构历史合同。字段无法安全映射时拒绝为可继续的新世界并保留旧存档/旧入口。新游戏采用完整 v3。不得静默重新开局并报告“读档成功”。

AtomicJsonFileStore 继续校验临时文件、备份和替换。业务错误必须显式返回失败，Godot release 的 assert 不能作为唯一保护。

## R09. Current World 数据装配

新增版本化场景 manifest 指定现有政治快照、空间目录、商品配方包、初值生成规则、组织制度包及唯一 start_datetime。默认建议与现有政治快照对齐为 `1900-03-12T00:00`（累计分钟 100800）；这是设计选择，批准后更新旧时间契约与测试。不得加载不覆盖该日期的行后忽略。

启动管线固定为：

1. 校验资料 schema/日期/许可证引用；加载 151 单元的历史身份，保留母国、殖民地、聚合市场间的区别。
2. 加载已有几何和交通；所有新生产点/仓库/人口格都必须显式绑定可用 place。缺精确点位时使用**已有**区域锚点并标记 coarse，不捏造现代地点映射。
3. 通过 crosswalk 建经济覆盖分区。一个政治单元可以引用一个跨单元经济区；一个统计人口不能重复分配给重叠单元。每个政治单元须有明确覆盖记录，完整图层不自动等于完整经济。
4. 从经过数据准入的资料建立人口。对于未知数值只接受带方法/范围的生成估计；没有人口或空间依据时产出缺口清单，该区域不能被宣称已可运行。其余区域可供开发验证，完整世界门槛仍失败。
5. 从资料拆出劳动 cohort；最初只需要 place×技能组×劳动状态，保留已知边际。宗教等未参与规则的维度暂不笛卡尔相乘。
6. 按有明确版本的 profile 创建政府机构、真实/生成企业、基础生产与物流组织、学校等；owner、账户、仓库和执行者必须齐全。生成企业标注 generated，不能冒充历史企业。
7. 所有开局商品写一次 opening ledger；所有开局金融资产对应资本或负债；所有军队从人口分配；维护、土地与外部原料来自显式资源池，不能无输入无限生产。
8. 为每项持续过程生成下一到期时间；运行全世界引用和资源自检，再允许用户进入。

67 商品、38 配方是可复用候选，不需要另拍脑袋缩成七类。逐条补齐 quantum、载荷换算、生产时长、劳时、设备要求和运营成本。缺字段直接报具体记录错误，不能以默认零成本凑过。未形成明确企业的普通经济使用有账户和生产约束的 sector pool，和具名企业运行同一公式。

初始化输出覆盖报告：`political_units_total`、`covered_units`、`economy_partitions`、`population_covered`、`unmapped_places`、`invalid_recipes`、`unfunded_operators`、`unallocated_formations`、`generated_estimates`。覆盖达标是集合包含与不重叠证明，不是硬编码“必须正好 50”。

### 当前小型交通目录如何扩大

现有 vNext Spatial 加载的7类文件并不等于正式历史几何目录：其中 cities32、rail9、road3、shipping3、ports8；国家目录177项也不能直接对应历史政治151单元。W02必须先增加 `load_world_scenario` 路径，同时把 `load_legacy_world_map` 保留为旧测试夹具入口。

空间装配采用三级有证据的精度：

- 精确地点：复用现有、有效且已映射的 city/port；
- 统计区域锚点：从已有 historical polity 的 capital坐标或现有几何内确定性代表点生成 `place:polity_anchor_<id>`，保存 source feature引用与生成方法。它是同一 Spatial 目录中的派生 place，不创建第二份边界，也不冒充详细城市；
- 粗交通联系：优先核对 `historical_transport_network_1900/transport_compact.json` 的50条 domestic、30条 maritime、13条 river估计记录。它们需要显式实体/端点 crosswalk、单位换算和方式标记，不能直接当作已实现路段。缺连接证据时，该方向保持不可达并报告；若采用生成的估计连接，必须在场景包中显式列边、端点、模式、距离/耗时/容量假设与 provenance，不能让寻路器暗补边。

coarse 经济区中的生活/工作可在共同锚点聚合，但跨经济区移动必须经过显式边。以后细分锚点时按人口/库存/设施划转而非复制，使同一世界可以先以资料支持的粒度运作，再提高地理细节。运输覆盖报告必须同时列出连通分量和未连接人口比例，不能只报政治着色覆盖率。

## R10. 工作 AI 必须实现的边界接口

这是新增接口契约，名称可以在W00一次性按仓库风格调整并更新所有调用者；之后任务不能各自发明不兼容签名。下列类型是有字段约束的 RefCounted 值对象，边界序列化才使用 Dictionary。

| 接收者 | 拟实现签名 | 成功和失败语义 |
|---|---|---|
| WorldRuntime | `submit_command(command: WorldCommand) -> CommandResult` | 只接受/拒绝/排队；返回预期生效分钟，不直接推进世界 |
| WorldRuntime | `request_advance_to(target_minute: int) -> AdvanceRequestResult` | 设待推进目标；不提前增加 total_minutes |
| WorldRuntime | `pump_budget(max_work_usec: int) -> StepProgress` | 分片准备；仅完整提交后更新 committed_minute；进度含 target、committed、pending、error |
| WorldRuntime | `advance_minutes(minutes: int) -> bool` | 兼容同步调用，内部走同一 request/pump 直到完成或失败；禁止另一套测试结算逻辑 |
| Scheduler | `schedule(header: ProcessHeader) -> bool`；`peek_due_minute() -> int` | 唯一过程 generation；无任务返回约定的∞哨兵，不能返回当前时间反复触发 |
| Domain process | `prepare_interval(view: DomainReadView, start: int, end: int) -> DomainChanges` | 纯候选；记录旧速率、资源占用、余数、完成事件；不发布回调 |
| Transport participants | `collect_transport_demands(view, window) -> Array[TransportDemand]` | Economy/Military/Travel 各自返回同单位需求；不改 Spatial |
| Spatial | `prepare_window(window, all_demands) -> CapacityPlan` | 一次验证、一次分配；包含 window_id、revision、allocations 和未用额度 |
| Transport participants | `prepare_transport_progress(view, plan: CapacityPlan) -> DomainChanges` | 仅依据最终 plan 中自己的 allocation；不再次分配或推进空间时间 |
| Finance | `prepare_transfer(request: TransferRequest) -> FinanceChanges` | 输入含付款方、收款方、币种、金额、授权/债权引用、command_id；不可透支 |
| StockLedger | `prepare_transfer(request: StockTransferRequest) -> StockChanges` | 输入含库存/数量、旧/新 owner、custody/location、reservation_id；检查守恒 |
| Personnel transition | `prepare_transition(request: PersonnelTransitionRequest) -> PersonnelChanges` | 同时列人口、Labor、Person、Military变更，任何一方拒绝全部不提交 |
| Domain owner | `validate_changes(changes, expected_revision) -> ValidationResult`；`install_validated(changes) -> void` | install只用于已全局验证写集，不再运行有失败可能的业务逻辑或回调 |
| Runtime persistence | `snapshot() -> Dictionary`；`restore(snapshot) -> bool` | 完整边界快照；拒绝保留原世界；恢复后重建派生索引 |

`DomainReadView` 是每个领域分别定义的窄读取类型；不做一个可任意访问所有系统的万能 Context。候选集可引用其他领域通过命令前置检查得到的值/版本，但不能保存对外部私有字典的可变引用。

### 必需的命令 payload

| command kind | 除公共header外的必需字段 | 结果 |
|---|---|---|
| apply_job / accept_job | person或cohort、job_id、headcount、shift_id、pay_contract_version | 有效劳动分配/工资合同或具体拒绝 |
| buy / sell | account_id、stock/commodity、quantity、limit_unit_price、currency、place、expiry | 可融资订单；不是已到货量 |
| start_production | site_id、recipe_version、batches、due_minute、input_stock_refs | 资源齐备则WIP过程；不足则排队/拒绝 |
| transport | stock_reservation、quantity、origin、destination、carrier、payment_terms、deadline | 有货有载荷的持久运单，ETA是估计 |
| lend / repay | lender、borrower、currency、principal、schedule、rate/day_count、collateral | 完整债权负债分录；拒绝不加余额 |
| propose_rule / vote | institution、procedure、rule_version或proposal_id、choice、jurisdiction | 提案/选票；程序完成之前不写最终法律 |
| start_strike | union、ballot_result、employment_refs、start_shift、aid_schedule | 有基金/参与者约束的未来劳动改变 |
| publish_report | source、claim/fact_ref、audience、issue_id、reach_plan、distribution | 耗材/劳时/资金和未来可知报告 |
| military_order | issuing_appointment、formation、kind、objective、known_target、start、deadline | 合法命令传播/准备/行动过程 |
| allocate_service | institution、service_type、recipient_refs、staff、materials、budget | 教育/救济/行政/医护等有类型服务过程 |

每种命令都有显式 `preview`，返回预计资源、时间和限制原因，但不能包含隐藏全局真相，也不能在预览时抢资源。failure code 最少区分 `INVALID_REFERENCE、NOT_AUTHORIZED、NOT_KNOWN、NOT_REACHABLE、INSUFFICIENT_FUNDS、BUDGET_EXCEEDED、STOCK_RESERVED、CAPACITY_QUEUED、ACTOR_UNAVAILABLE、STALE_REVISION、INVALID_TIME、INVALID_RULE_VERSION`。本地化文案在UI层映射，算法不通过中文字符串判断错误类型。

## R11. 可执行的开局初值生成算法

这部分仅生成明确标记为 simulation_assumption 的开局记录，源资料已给出的数量优先。它不修改运行算法来强行保持平衡，也不能替代缺失的政治/人口范围证明。

### 必需输入

每个经济分区有：已去重人口N、人口来源适用范围、现有place绑定、采用的货币区、消费篮子、工资/税/行政制度profile、可用生产配方、原始资源能力、对外贸易联系。任何缺失返回该字段/分区错误。profile应是版本化数值表，不是自然语言“工业强国”。

首版生成参数固定为：库存缓冲14日、工资周转30日、家庭现金7日篮子费用、正常机器利用率目标9000bp、政府服务现金储备30日。它们是设计默认值，可被有来源的记录覆写，须保存实际使用值。

### G1. 需求与产能

1. 对每个人口分组，按A05篮子计算每日最终需要。对必须跨境获得的商品生成有真实对手/路线/资金的开局补货计划，不认为“import_share”字段本身会发货。
2. 每种需要的主产品选一个资料允许的默认配方。开局求解所选配方的主产品依赖图必须无环；存在回收环时不用于开局倒推，作为后续可选工艺保留。无配方的stockable品必须有明确原始资源/进口供应者。
3. 反向拓扑遍历：`daily_batches=ceil(required_main_output/output_per_batch)`；将各输入的 `daily_batches*input_per_batch` 累加到上游需求。副产品不抵扣这次产能倒推需求，避免多产出交叉依赖的歧义；它在正式生产时仍实际入库。这会保守高估部分产能，结果和方法写进报告。
4. `installed_batches=ceil(daily_batches*10000/9000)`；工人需求由真实配方劳时/班次分钟上取整，机器容量同理。给定原始资源、工作年龄人口或资料产能上限不足时，按配置的食物/已有义务优先分配；未满足需求保留，不凭空增加工人。输出明确 shortage_by_constraint。
5. 首次按资料/模板建立production site owner，每个site引用实际劳动和原料来源。小规模生产可由一个sector pool代表。不能每个配方都分配同一批全部工人。

### G2. 库存与资金

6. 开局库存为已声明的14日正常消耗/投入量，上限受仓容与资源来源记录约束；写一次 `opening_stock` 来源分录。按民用/企业/公共/军用用途划给对应owner，总额不能先放地区一份再放企业一份。
7. 家庭现金初值为7日篮子费用；企业流动资金为30日已分配毛工资加14日需外购投入成本；政府现金为30日已批准服务开支。存在可信账户/资产初值则使用源值，并记录与生成值差异。
8. 生成的现金须由场景的 opening settlement资产与资本分录支持。非银行主体：现金/库存/设施记资产，投入资本记权益；若由银行存款承载，银行同时记存款负债和相应opening准备/资产及资本。禁止初始化时凭空加银行存款后把资产负债差塞到运行时其他收入。用共通估值基准时标明valuation_unit，不冒称各历史货币的名义汇率。
9. 股票/资本所有权引用已被分配的资产权益，不再生成同额可花现金。历史数据缺所有者时使用声明的聚合资本所有者，不能编造一个有名字的历史富豪。

### G3. 人物、机构和流程

10. 从已存在cohort中为需要的执行岗位展开人物；按制度profile建立任命，预留人员从该群体劳动预算扣除。政府、银行、学校、部队都不能免费从未分配人口外另生员工。
11. 普通机构按A07创建初始7日计划。现有政府支出、军费、租金、债务只有对应双方记录齐全才创建正式合同；没有历史债务记录时声明开局模型不含该历史债务，不虚构过去的欠条。
12. 在独立候选场景上进行30日预热诊断，记录物资/人口/财务恒等式、缺食、现金耗尽和运输排队。诊断结束丢弃候选，仅输出建议校准差异；不能把预热多生产的货偷偷塞回起始日期。修改profile后重新生成同一种子开局，保存版本和差异。

开局生成的目标是明确、可重现且可运行的模拟初态。它可以暴露缺口，并非保证所有国家经济健康。T45的行为校准与T32的技术覆盖分开验收。
