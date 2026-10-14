你现在继续独立私有仓库：

`ryoumiyahayato/wwo-economy-lab`

实际推进：

# Round5 — Demand Propagation & Production Planning
# 需求传播、生产计划与时间化原料需求实验

这是一轮真实算法实验施工。

本轮不再继续加深 Supplier Search。

Round2–Round4C 已经逐步建立：

- 实体库存；
- 生产与物料配方；
- 实际运输与 lead time；
- 订单/pending/in-transit；
- supplier admission；
- stock-confirmed ATP；
- bounded multi-supplier matching；
- known / unknown supplier；
- bounded supplier discovery；
- 10/50/200 supplier 规模实验。

Round4C 已经通过 EXTENSIBILITY_GATE。

但 Round4C 的 Wide 场景暴露了一个新的明确问题：

供应商已经找到；
供应商有真实库存；
线路也有能力；
offer 也足够；

但长期终端缺口没有转化成足够的采购需求。

因此本轮研究：

> **经济系统中的需求，如何从最终商品逐层形成生产计划和投入品需求，而不是只有库存下降以后才被动补货。**

本轮仍然属于黑箱扩展与实验准备阶段。

不是要宣布某个 production planning 算法为最终经济模型。

---

# Stage 0 — 冻结 Round4C 基线

检查 PR #5：

`Extend supplier discovery and bounded search for scalable experiments`

如果：

- CI 仍 SUCCESS；
- PR head 与已验证 Round4C head 相同；
- MERGEABLE/CLEAN；
- 无 unresolved blocking review；
- 没有未经说明的新提交；
- 当前账号有 merge 权限；

则直接合并 PR #5。

PR OPEN 本身不是停止条件。

合并以后：

1. 同步最新 `main`；
2. 重新运行全部旧验证；
3. 创建 annotated tag：

`economy-lab-v0.4c-supplier-search`

message 建议：

`Verified Round4C bounded supplier discovery and search scaling baseline.`

4. 从最新 main 创建：

`research/demand-planning-round5`

然后继续。

如果 Git smart HTTP 失败而 GitHub API 可用，继续使用已经验证的 API 发布方式。

GitHub 单步失败只阻塞相应远端操作。

只要 baseline 可明确取得，不停止本地研究。

---

# Stage 1 — 完整回归

开始 Round5 前运行：

- 原 8 项；
- Round2 9 项；
- Round3 18 项；
- Round4A 29 项；
- Round4B 33 项；
- Round4C 32 项；

以及：

- `verify_baseline.py`
- `verify_round3.py`
- `verify_round4a.py`
- `verify_round4b.py`
- `verify_round4c.py`

记录：

- Python version；
- base SHA；
- tag；
- branch；
- commands；
- exit code；
- Round2–Round4C summary hashes。

Round5 关闭时：

全部历史结果保持。

不要修改旧 fixture、旧 CSV 或旧报告迎合 Round5。

---

# Stage 2 — 本轮必须正式区分四种东西

不要继续把下面四个概念混在一起：

1. **Demand**
2. **Production Plan**
3. **Material Requirement**
4. **Purchase Request**

建立最小、明确的数据流：

`Demand`
↓
`ProductionPlan`
↓
`MaterialRequirement`
↓
`ProcurementNeed`
↓
Round4B/4C 已有 supplier search / offer / matching
↓
`PurchaseRequest`

不能：

terminal backlog 直接写 coal order。

也不能：

库存 target 直接冒充最终需求。

---

# Stage 3 — Demand 是事实，Plan 是决策

Terminal demand / backlog 继续属于世界中的需求事实。

ProductionPlan 是企业根据已知事实生成的计划。

计划不是未来事实。

至少为每个 producer/day 输出：

- producer_id
- commodity
- plan_day
- desired_output_qty
- capacity_limited_output
- demand_basis
- planning_horizon
- unmet_planned_output

不要修改已经发生的 demand。

不要为了计划结果好看而删除 backlog。

---

# Stage 4 — 建立 P0 Legacy Control

## P0 — Legacy Replenishment

完整保留 Round4C 当前行为：

- C 按旧逻辑生产；
- B 按旧逻辑生产；
- coal 采购主要由库存 position / target 驱动；
- 没有 demand-derived upstream plan。

P0 必须复现 Round4C 对应场景。

它是本轮主要 control。

---

# Stage 5 — P1：Current Committed Demand Propagation

增加第一种最小计划候选：

## P1 — Committed-Demand Planner

它只能使用：

**当前已经存在的 terminal backlog / orders。**

不能读取未来 demand schedule。

例如当前 C 有：

`terminal_backlog = 10`

则：

`desired_machine_output =
min(
    machine_capacity,
    terminal_backlog
)`

如果 backlog=50：

最多按 C 真实 capacity 计划。

C 当前最大15 machine/day，

因此：

`desired_machine_output <= 15`

然后根据真实 recipe：

`4 steel -> 1 machine`

产生：

`gross_steel_requirement =
desired_machine_output × 4`

再传播给 B。

B 根据：

`2 coal -> 1 steel`

产生：

`gross_coal_requirement =
desired_steel_output × 2`

这一传播必须由 recipe 数据产生。

不要硬编码：

10 machine = 80 coal。

---

# Stage 6 — P1 的限制要故意保留

P1 只看当前 committed backlog。

它不知道：

“明天还会再来10个 demand”

除非那是已经存在的世界事实。

因此在稳定环境中：

P1 可能仍然只有一天视角。

这是本轮要观察的结果。

不要偷偷使用未来 fixture demand。

不要为了让 P1 好看加入隐藏 forecast。

---

# Stage 7 — P2：Backward-Looking Run-Rate Planner

为了研究更具延展性的计划能力，再增加：

## P2 — Observed Run-Rate Planner

P2 不读未来。

它从过去已经观察到的 terminal demand 计算：

`observed_demand_rate`

使用简单确定性 trailing window：

默认：

`demand_history_days = 20`

例如：

`observed_daily_demand =
sum(actual terminal orders received over last 20 days)
/ observed days`

冷启动阶段：

只使用已经实际观察到的天数。

不得预填未来20天。

然后：

`planned_machine_demand =
current_backlog
+ observed_daily_demand × planning_horizon_days`

这是计划量，不是新的真实订单。

---

# Stage 8 — Planning Horizon

本轮不要进行巨大参数搜索。

固定测试：

`planning_horizon_days = 10`

另外只做：

5

和：

20

两个 sensitivity probe。

不要把 horizon 调成能刚好解决 Wide failure 的值。

计划 horizon 是候选实验参数，不是正式经济常数。

---

# Stage 9 — 生产计划必须受真实产能约束

对于 horizon H：

C 最大可以计划：

`machine_capacity_per_day × H`

B 最大可以计划：

`steel_capacity_per_day × H`

不能因为 backlog 很高就在10日计划里生成1000 machine。

记录：

- unconstrained demand requirement；
- capacity constrained production plan；
- capacity shortfall。

这三个必须分开。

---

# Stage 10 — 上游传播必须是 recipe-driven

建立最小通用传播函数。

输入至少：

- desired output commodity；
- desired quantity；
- recipe；
- producer capacity；
- current inputs。

输出：

- gross material requirements。

当前链：

coal
→ steel
→ machine

但实现不要写成：

`if commodity == "machine": ...`

优先做：

`RecipeGraph`

或等价的只读 recipe dependency structure。

要求至少能表达：

`input commodity`
`input quantity`
`output commodity`
`output quantity`

不要建立第二套经济 runtime。

只建立 planning layer。

---

# Stage 11 — 计划不得制造物资

这是硬 invariant。

ProductionPlan 和 MaterialRequirement 都是：

**信息/决策状态。**

它们不能：

- 增加 inventory；
- 创建 shipment；
- 增加 delivered；
- 修改 coal_mined；
- 修改 steel produced；
- 修改 machine produced。

真实物资仍然只能由现有 Simulation 结算。

---

# Stage 12 — Gross Requirement 与 Net Requirement 分离

对每个 material：

先有：

`gross_requirement`

再计算：

`net_requirement`

不能直接 gross → purchase。

至少考虑：

- current on_hand；
- already in_transit；
- live accepted pending。

但本轮必须开始考虑：

**时间。**

不能再只看总量。

---

# Stage 13 — 引入 Time-Phased Requirement

这是本轮最关键的扩展。

每个 MaterialRequirement 至少包含：

- commodity
- required_qty
- need_by_day
- source_plan_id

例如：

C 计划 Day t+3 使用40 steel，

则产生：

`steel requirement: qty40, need_by=t+3`

B 的对应 coal requirement 再依据生产时间边界产生自己的：

`need_by_day`

不要假定采购 arrival 后可以穿越时间直接参与 earlier production。

---

# Stage 14 — 不需要复杂生产排程

本轮不做：

- machine scheduling；
- shift；
- setup time；
- batch optimization；
- factory calendar。

使用当前日粒度。

可以假定：

当天可用投入
→ 当天 production stage
→ 按现有 stage 顺序结算。

但 need-by 必须与当前 stage 顺序一致。

把这个假设写清楚。

---

# Stage 15 — P3：Time-Phased Net Requirement

在 P1/P2 的基础上增加第三个正式候选：

## P3 — Time-Phased Requirement Planner

P3 使用 P2 的 observed demand basis，

但采购 need 不再只使用：

`target - total position`

而是：

> 某个 need-by date 以前能够实际到达并可使用的供应，是否覆盖该日期以前的计划投入需求。

建立：

`scheduled_supply_before(day)`

至少包括：

- current on_hand；
- shipment ETA <= day 的 in_transit；
- accepted pending 只有在其 promised arrival <= day 时才计入。

不能把：

lead8 的货

拿去覆盖：

Day+2 的 material requirement。

---

# Stage 16 — accepted pending 的时间价值

对于尚未 dispatch 的 accepted pending：

使用已有明确：

- promised dispatch day；
- route lead；
- expected arrival day。

只有：

`expected_arrival_day <= need_by_day`

才能覆盖该 requirement。

无 promise / unknown ETA 的 pending：

继续记录在真实 ledger，

但 P3 不得默认它能够覆盖任意近期 need。

本轮不要重新定义 Round3 order truth。

这里只改变 planning coverage。

---

# Stage 17 — Safety Stock 与 Planning Requirement 分离

不要删除已有 inventory target。

旧 target 继续作为：

`safety / operating inventory policy`

但新增：

`planned_material_requirement`

采购量应能明确分解为：

- safety-stock replenishment component；
- production-plan requirement component。

不要把二者混成一个无法解释的数字。

输出：

`procurement_need_safety`
`procurement_need_plan`
`procurement_need_total`

必须避免重复计算。

---

# Stage 18 — 不允许计划需求无限重复下单

同一个 plan requirement 必须有 stable ID。

例如：

`requirement_id`

采购以后需要记录：

多少 requirement 已被：

- on_hand coverage；
- in_transit allocation；
- accepted order coverage；

覆盖。

不能每天把同一个未来需求再买一遍。

新增 planning allocation sidecar。

它不是 ownership ledger。

只是需求覆盖记录。

---

# Stage 19 — Requirement Allocation 必须可以释放

如果：

accepted order 被 cancelled confirmed，

原来分配给它的 plan coverage 必须释放。

如果：

shipment 到货，

coverage 从 pipeline 转为 on_hand coverage。

如果：

requirement 到期后实际没有消耗对应数量，

不要偷偷销毁物资。

记录：

- planned；
- allocated；
- consumed；
- expired/unfulfilled requirement。

---

# Stage 20 — 计划与真实生产偏差

本轮必须输出：

`planned_output`

和：

`actual_output`

的差异。

原因至少分类：

- INPUT_SHORTAGE
- CAPACITY_LIMIT
- NO_DEMAND
- PLAN_NOT_DUE
- OTHER_EXPLICIT_FIXTURE_REASON

不要为了让计划等于实际生产而改真实 production。

Plan 是预测/决策。

偏差本身是研究结果。

---

# Stage 21 — 正式场景矩阵

每个正式场景默认600日。

至少执行以下组。

---

## A — Normal steady demand

terminal demand：

10 machine/day。

运行：

P0
P1
P2
P3

观察：

- plan；
- actual；
- material requirement；
- procurement；
- inventory；
- backlog。

重点看 P1 是否因只有当前 committed demand 而表现为短视。

---

## B — Demand step-up

Day1–99：

10/day

Day100+：

15/day

Planner 不得提前知道 Day100。

比较：

P0/P1/P2/P3。

观察：

- demand 被观察到以后多久改变 production plan；
- steel requirement；
- coal requirement；
- purchase request；
- actual production；
- backlog。

---

## C — Demand step-down

Day1–99：

15/day

Day100+：

5/day

观察：

计划是否逐步下降。

特别检查：

P2/P3 是否因为 trailing demand 导致暂时 over-plan。

如果出现：

保留。

不要立即加复杂 forecast。

---

## D — Temporary demand spike

Day100–119：

15/day

其他：

10/day。

观察：

P2 是否滞后；
P3 是否产生库存/采购 overshoot。

---

## E — Original Round4C Wide failure

必须完整保留 Round4C Wide 失败 fixture。

不要修改：

- supplier能力；
- lead；
- search；
- discovery；
- target；
- initial inventory。

分别运行：

P0 / P1 / P2 / P3。

这是本轮最重要反事实之一。

检查：

在 E 已知且 offer 充足时，

是否仍然出现：

`open need = 0`

但：

terminal backlog 持续。

如果 P3 改善：

必须解释到底是：

- demand propagation；
- time-phased coverage；
- 还是 safety target 变化；

造成。

不能只写“P3更好”。

---

## F — Long lead only

保持需求10。

供应商供给足够。

设置主要补货 lead：

8 days。

无搜索问题。

研究：

纯 lead 是否导致 legacy position 错估近期覆盖。

---

## G — Short + long mixed lead

两个已知供应商：

short supplier：
capacity有限，lead2。

long supplier：
capacity较大，lead8。

观察：

P3 是否正确处理：

同样320 position，

但到货时间不同。

---

## H — Physical supply insufficient

所有 supplier 合计最多只能支持：

7.5 machine/day。

terminal demand：

10/day。

P0–P3。

要求：

任何 planner 都不能凭空满足10。

应明确形成：

- planned shortfall；
- material shortfall；
- terminal backlog。

---

## I — Production capacity bottleneck

原料无限充足。

但 C machine capacity 降到：

8/day。

terminal demand10。

要求：

计划明确识别 capacity shortfall。

采购不能无限扩张试图解决工厂 capacity 不足。

---

## J — Intermediate bottleneck

coal足够，
C能力足够，

B steel capacity 降低。

验证：

需求传播必须识别中间生产瓶颈。

不能把所有 unmet final demand 都转成无限 coal purchase。

---

# Stage 22 — Backlog Recovery

专门测试一次 temporary disruption：

造成 terminal backlog。

随后物理供给恢复并且 C 有 spare capacity15/day。

P2/P3 应允许：

`planned machine output > normal demand10`

但：

`<= capacity15`

从而研究：

计划是否尝试清旧 backlog。

这不代表一定成功。

如果上游供给不足：

记录失败原因。

---

# Stage 23 — 不加入未来需求真值

增加 prefix equivalence：

两个世界：

Day1–99 demand 完全一样。

Day100 后一个变15，
一个维持10。

Day1–99 的：

- demand estimate；
- plans；
- material requirements；
- procurement；
- orders；
- shipments；
- production；

必须一致。

P2/P3 不得读取 future fixture demand。

---

# Stage 24 — Generalization Probe：更深生产链

为了测试黑箱延展性，

增加一个独立接口 probe：

5-stage deterministic recipe chain。

例如：

raw1
→ intermediate1
→ intermediate2
→ intermediate3
→ final

不需要加入正式经济 fixture。

只测试：

final demand requirement

是否可以通过 RecipeGraph

逐层产生 upstream material requirements。

不能写五套专门代码。

---

# Stage 25 — Branching Recipe Probe

增加一个很小的：

一个 final commodity 同时需要两类 input。

例如：

1 final =
2 input_A
+
3 input_B

检查：

需求传播能够产生两个独立 material requirements。

不要因此实现完整新产业。

---

# Stage 26 — Shared Input Probe

再增加一个接口 probe：

两个不同 output 都需要同一个 input commodity。

验证：

planner 不会把同一 on_hand 数量同时完整分配给两个 requirement。

只需要 planning allocation correctness。

不是完整多企业生产网络。

---

# Stage 27 — Multiple Demand Sinks Probe

建立：

两个 terminal demand sinks

消费同一个 final commodity。

只测试：

aggregate committed demand

和：

requirement allocation。

不要创建第二套 Simulation。

如果现有结构必须复制 Simulation 才能实现：

停止这个 probe 并记录结构限制。

---

# Stage 28 — Demand Propagation Performance

记录：

- active demand records
- production plans
- material requirements
- requirement edges traversed
- requirement allocations
- planning horizon days
- recipe graph nodes
- recipe graph edges
- procurement requests
- runtime
- optional tracemalloc

重点观察：

planning work

是否更接近：

`active plans × reachable recipe edges × horizon`

而不是：

扫描所有历史订单/需求档案。

使用按日/按 requirement 索引。

不要重犯 Round4A 历史全扫描问题。

---

# Stage 29 — Correctness Tests

至少覆盖：

1. P0 reproduces legacy Round4C。
2. Demand 不被 planner 修改。
3. Plan 不产生物资。
4. MaterialRequirement 不产生物资。
5. recipe conversion 正确。
6. capacity limit 正确。
7. P1 不读未来 demand。
8. P2 trailing window 只读过去。
9. P3 supply coverage respecting ETA。
10. lead8 shipment 不能覆盖 lead2 requirement。
11. cancelled coverage 正确释放。
12. in-transit allocation 不重复。
13. same requirement 不重复采购。
14. safety need + plan need 不双算。
15. planned vs actual 独立记录。
16. physical insufficiency 下 planner 不造供给。
17. production bottleneck 下不无限采购 raw input。
18. five-stage propagation 正确。
19. branching recipe 正确。
20. shared input allocation 不重复。
21. multi-sink demand aggregation 正确。
22. future-demand prefix equivalence。
23. commodity residual=0。
24. order identities=0。
25. 所有 Round2–4C 历史验证继续通过。
26. replay deterministic。

不要写：

`P3 backlog < P0`

作为 correctness test。

那只能是实验结果。

---

# Stage 30 — 本轮要主动寻找的失败模式

不要提前修。

## 1. P1 太短视

如果只看当前 backlog 导致采购仍不足：

保留结果。

## 2. P2 反应滞后

需求突变以后 trailing average 慢：

保留。

这是 backward-looking planner 的真实性质。

## 3. P3 overshoot

如果需求下降后仍有大量长途在途：

可能产生高库存。

先判断是：

账目错误

还是：

计划滞后 + lead time 的策略结果。

## 4. Planner 无限采购

如果生产 capacity 已经成为瓶颈但原料需求仍无限增长：

优先视为 planning correctness 缺陷。

## 5. Wide failure 没有改善

允许。

如果传播和时间化以后仍失败，

就继续追踪真正瓶颈。

不要为了通过 Gate 调 target。

---

# Stage 31 — 报告

生成：

`DEMAND_PLANNING_REPORT.md`

必须明确回答：

1. 当前 legacy 采购为什么会出现 backlog>0 但 open_need=0？
2. Demand、Plan、Requirement、Purchase Request 是否真正分离？
3. P1 是否太短视？
4. P2 的 trailing demand 如何响应 step-up / step-down？
5. P3 是否真正处理 mixed lead？
6. Round4C Wide failure 在 P0/P1/P2/P3 下分别发生什么？
7. 如果改善，因果链具体是什么？
8. 如果未改善，真正瓶颈是什么？
9. backlog recovery 时是否正确利用 spare capacity？
10. supply insufficient 时 planner 是否诚实暴露 shortfall？
11. factory capacity bottleneck 是否能阻止无意义上游采购？
12. 五阶段链、branching recipe、shared input、multi-sink probe 是否通过？
13. 计划层是否已经具备扩大产业网络的表达能力？
14. planner 的主要工作量随什么增长？
15. 哪个候选只值得继续研究，不应正式采用？
16. 下一步最值得扩的是：
   - 多 buyer / 多企业生产网络；
   - 更真实 production scheduling；
   - production-aware ATP；
   - pricing；
   - household consumption；
   - 还是先修 planning blocker？

禁止回答：

“P3最好，所以正式采用。”

---

# Stage 32 — PLANNING_EXTENSIBILITY_GATE

最后给出：

`PLANNING_EXTENSIBILITY_GATE = PASS / FAIL`

PASS 至少要求：

- terminal demand 可以明确传播到上游；
- recipe-driven，不硬编码三商品链；
- capacity 能限制计划；
- time-phased requirements 能区分短/长 lead；
- requirement 不重复采购；
- safety stock 与 plan demand 可分解；
- 五阶段链可传播；
- branching input 可传播；
- shared input 不重复分配；
- multiple sink probe 可表示；
- 所有物质账保持；
- future information isolation 通过。

PASS 的含义只有：

> **这个黑箱已经能够表达“需求—计划—投入—采购”这条更完整的生产因果链，可以继续扩大企业网络进行模型价值测试。**

PASS 不表示：

模型经济学正确。

---

# Stage 33 — Git / PR

完成以后：

运行：

- verify_baseline
- verify_round3
- verify_round4a
- verify_round4b
- verify_round4c
- Round5 tests
- Round5 full replay ×2

提交少量清晰 commits。

branch：

`research/demand-planning-round5`

创建独立 PR。

建议标题：

`Experiment with demand propagation and time-phased production planning`

不要自动 merge。

PR body 必须写：

- Round4C baseline；
- P0/P1/P2/P3；
- demand/plan/requirement split；
- recipe graph；
- time-phased coverage；
- Wide failure反事实；
- scenario results；
- extensibility probes；
- performance；
- limitations；
- PLANNING_EXTENSIBILITY_GATE。

---

# Stage 34 — 本轮禁止

不要加入：

- price
- money
- credit
- bank
- wage
- household
- labor
- securities
- supplier reputation
- random forecasting
- ML forecast
- stochastic demand
- full MRP
- factory shift scheduler
- optimization solver
- WWO integration

不要新建第二套 Simulation。

不要新建 EconomicRuntime。

本轮只建立：

**可验证的 planning layer。**

---

# Stage 35 — 最终回复格式

最终必须按：

### Stage 0 — Round4C baseline
DONE / PARTIAL / BLOCKED

### Stage 1 — Regression
DONE / FAILED

### Stage 2–20 — Planning semantics
DONE / PARTIAL / BLOCKED

### Stage 21–30 — Experiments & probes
DONE / PARTIAL / BLOCKED

### Stage 31 — Report
DONE / PARTIAL

### Stage 32 — PLANNING_EXTENSIBILITY_GATE
PASS / FAIL

说明真实依据。

### Stage 33 — Git / PR
DONE / PARTIAL / BLOCKED

列出：

- main/base SHA
- tag
- branch
- commits
- PR URL
- CI status

### Remaining structural limits

只列真实限制。

### Recommendation

基于本轮证据选择下一轮方向。

不要默认继续 production planning。

本轮完成以后停止。