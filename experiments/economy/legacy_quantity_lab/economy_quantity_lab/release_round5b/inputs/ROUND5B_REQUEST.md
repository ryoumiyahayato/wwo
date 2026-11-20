你现在继续独立私有仓库：

`ryoumiyahayato/wwo-economy-lab`

实际推进：

# Round5B — Executable Planning Release & Commitment Reconciliation
# 可执行计划释放、滚动窗口与既有采购承诺协调实验

这是一轮真实算法研究施工。

Round5 已经完成：

Demand
→ ProductionPlan
→ MaterialRequirement
→ ProcurementNeed
→ supplier offer/matching
→ PurchaseRequest

并通过：

`PLANNING_EXTENSIBILITY_GATE`

但 Round5 同时暴露了明确的 planning blocker：

> 计划能够表达需求日期，但并不等于计划能够在正确的时间释放采购。

尤其是原 Wide 场景：

- production horizon H10 覆盖 t…t+9；
- long supplier 的保守 promised arrival 最迟为 t+10；
- 所以新的 long-lead offer 无法覆盖 H10 中任何一个 requirement；
- P3 因此保留严重服务缺口；
- H20 能工作不代表“把 horizon 调成20”就是正确解决方案。

本轮目标不是调大 horizon。

本轮研究：

> **滚动计划如何根据 lead time 提前释放采购，如何在每日重规划后保持稳定需求责任，以及已有 accepted / in-transit / late commitments 如何在未来需求日期之间重新协调而不重复采购。**

本轮仍然是黑箱扩展和算法实验。

不批准任何候选进入正式 WWO。

---

# Stage 0 — 合并并冻结 Round5

检查 PR #6：

`Experiment with demand propagation and time-phased production planning`

如果：

- CI 全部 SUCCESS；
- head 仍是已验证 Round5 head；
- MERGEABLE/CLEAN；
- 无 unresolved blocking review；
- 没有未经说明的新提交；
- 当前账号有 merge 权限；

则直接合并 PR #6。

PR OPEN 本身不是停止条件。

合并以后：

1. 更新 main；
2. 运行全部历史验证；
3. 创建 annotated tag：

`economy-lab-v0.5-demand-planning`

建议 message：

`Verified Round5 demand propagation and planning extensibility baseline.`

4. 创建：

`research/executable-planning-round5b`

继续施工。

如果 Git smart HTTP 失败，可继续采用已经验证的 GitHub API 发布方式。

单个 GitHub 操作失败不等于停止整个实验。

---

# Stage 1 — 全量历史回归

施工前运行：

- 原8项；
- Round2 9；
- Round3 18；
- Round4A 29；
- Round4B 33；
- Round4C 32；
- Round5 40；

以及全部现有 verify wrappers。

记录：

- Python version
- base SHA
- tag
- branch
- commands
- exit codes
- Round2–Round5 summary SHA

Round5B 关闭时：

历史行为必须继续成立。

禁止改写：

- Round5 P0/P1/P2/P3；
- Round5 正式场景；
- 原 H5/H10/H20 结果；
- Wide 失败；
- 历史 reports / fixtures / CSV；
- 原物资结算。

---

# Stage 2 — 本轮先固定 Round5 的诊断，不重新解释

Round5 已经证明：

1. P2 quantity planning 可以显著增加实际采购和缓冲；
2. 但 P2 不保证 need-by 日期可行；
3. P3 能区分 ETA 和日期；
4. 但 H10 中 long supplier 的 latest arrival=t+10 超出 t…t+9；
5. 因而 P3 无法形成足够的 long-lead executable procurement；
6. H20 恰好成功不等于20是正确常数；
7. 已接受但无可信及时性的采购余额还可能压制 replacement。

把这些作为固定输入。

不要重新调 target、supplier capacity 或 lead 来消掉问题。

---

# Stage 3 — 正式分离两个 horizon

Round5 把 production planning horizon 和采购可见范围基本绑定。

Round5B 必须分开：

## 3.1 Production Commitment Horizon

继续：

`production_horizon = 10 days`

表示企业真正形成较具体生产计划的日期范围：

`t ... t+9`

保持不变。

## 3.2 Supply Visibility Horizon

新增：

`supply_visibility_horizon`

它允许 planner 为更远期采购释放观察需求。

但这不等于把那些远日期变成 firm production plan。

默认计算候选：

`visibility_horizon =
production_horizon
+ max_current_known_procurement_lead`

其中 lead 来自：

当前已知 supplier offer 的：

promised dispatch window + route lead。

不得读取未来实际 dispatch。

不得读取未来 route capacity。

---

# Stage 4 — 建立 Projected Requirement Tail

production horizon 以外、

visibility horizon 以内，

允许建立：

`ProjectedMaterialRequirement`

它只能基于：

- 已观察 terminal demand history；
- 当前 backlog；
- 当前已知 recipe；
- 当前已知 capacity。

不能读取未来真实需求。

Projected requirement 至少包含：

- requirement_id
- producer
- commodity
- need_by_day
- projected_qty
- basis
- created_day
- last_revised_day

它不是：

- ProductionPlan；
- firm output commitment；
- actual demand；
- inventory；
- Order。

---

# Stage 5 — Firm 与 Projected 必须严格区分

`t...t+9`

中的 requirement：

`FIRM`

visibility tail：

`t+10...`

中的 requirement：

`PROJECTED`

只有 firm production plan 可以进入：

planned_output

统计。

Projected tail 只能用于：

**采购释放时机。**

不能把 projected quantity 输出成：

“企业计划实际生产”。

不能把 projected requirement 冒充 terminal order。

---

# Stage 6 — requirement ID 改为稳定日期桶

Round5 的滚动计划保存 decision-date 版本。

Round5B 在执行层增加稳定 bucket：

`requirement_bucket_id =
producer + commodity + need_by_day + requirement_class`

同一个：

B / coal / Day120

在 Day110、111、112 重算时，

仍然是同一个执行 bucket。

其 quantity 可以 revision。

但不能每天生成一个新的独立采购责任。

历史 revision 可以另外归档。

执行状态只能有一个当前 bucket。

---

# Stage 7 — Requirement Revision

每天 rolling replan 时：

同一 bucket 可以：

- increase；
- decrease；
- unchanged。

记录：

`previous_qty`
`revised_qty`
`revision_delta`

增加：

只产生 delta requirement。

减少：

不能直接删除已经：

- accepted；
- in_transit；

的真实供应。

减少后可能形成：

`excess_supply_exposure`

这是研究结果。

不要偷偷销毁订单。

---

# Stage 8 — 定义 Release-By Day

每一个 material requirement 都增加：

`release_by_day`

基本逻辑：

`release_by_day =
need_by_day - conservative_supply_lead`

其中 conservative supply lead 来自真实当前 offer：

`promised_dispatch_window + route_lead`

例如：

need_by=t+10

supplier latest-arrival lead=10

则：

release_by=t

因此 H10 production plan 虽然只到t+9，

Projected tail 中的 t+10 requirement 可以在今天形成可执行采购。

---

# Stage 9 — 不允许使用实际未来 shipment ETA 做释放计划

尚未购买时：

只能用当前 offer 的 conservative arrival。

购买并 dispatch 后：

才能使用 shipment 的真实 ETA。

也就是说：

Quote/Offer
→ conservative expected arrival

Shipment
→ actual ETA

两者不能混。

不得因为历史上该 supplier 往往提前发货就提前假定。

---

# Stage 10 — 本轮比较三个正式候选

不要继续增加很多策略。

只比较：

## X0 — Round5 P3 Control

完全保留原 P3 H10。

## X1 — Release-Aware Rolling Planner

使用：

- production horizon=10；
- lead-aware visibility tail；
- stable requirement buckets；
- release_by_day；
- supply reassignment；
- 无主动取消 stale order。

## X2 — Release-Aware + Confirmed Stale Commitment Disposition

在 X1 基础上，

允许对无法覆盖任何可见 requirement 的 stale pending 使用已有：

CANCEL_REQUESTED
→ delay
→ CANCEL_CONFIRMED

只有 confirmed 后才允许 replacement。

禁止立即双订。

---

# Stage 11 — Supply Allocation 必须改为“时间匹配”

每一单位 supply exposure 只能分配一次。

供应来源包括：

- on_hand
- in_transit
- accepted pending

每个 supply lot 至少有：

`available_by_day`

规则：

on_hand：

`available_by = today`

in_transit：

`available_by = shipment ETA`

promised pending：

`available_by = promised dispatch + route lead`

unpromised / overdue unknown：

`available_by = UNKNOWN`

---

# Stage 12 — Forward-Only Allocation

Supply allocation 必须满足：

`available_by_day <= requirement.need_by_day`

才能算 timely coverage。

如果原来分配给 Day120 的供应，

后来预计只能 Day123 到，

它不能继续覆盖 Day120。

允许将它重新分配到：

Day123 或更后的 requirement。

这叫：

`forward reassignment`

绝不能：

把 Day123 才到的货重新分配给 Day120。

---

# Stage 13 — 滚动重算时先 reconcile，后采购

每日 planning 边界顺序必须明确：

1. 更新 demand history；
2. 生成/修订 firm plans；
3. 生成/修订 projected tail；
4. 更新 supply availability；
5. reconcile existing allocations；
6. forward-reassign late supply；
7. 计算 timely gaps；
8. 计算 exposure ceiling；
9. 最后才允许创建新 procurement。

不要：

先买，
再发现已有订单其实可以覆盖。

---

# Stage 14 — 防止滚动重复采购的双重约束

Round5 已经发现过：

旧 accepted balance 与新 rolling requirement 导致重复采购。

Round5B 新采购必须同时满足：

### 条件 A：存在 timely gap

某 need-by bucket 没有及时覆盖。

### 条件 B：总 supply exposure 不超过当前可见责任

计算：

`visible_requirement_exposure`

与：

`existing_real_supply_exposure`

新采购量不能超过：

`visible requirement尚未被真实供应占用的数量`

即使某旧 pending 没有及时 ETA，

也不能简单忽略它然后无限再买。

---

# Stage 15 — Unallocated Exposure

如果某 accepted pending：

- 不及时；
- 无可信 available_by；
- 也暂时无法分配给 visibility horizon 内更晚 requirement；

则进入：

`UNALLOCATED_EXPOSURE`

它仍然是真实订单。

它继续参与总 exposure 去重。

但：

**不能算 timely coverage。**

必须单独输出。

这是“订单还存在”和“它能不能满足某个日期”的再次分离。

---

# Stage 16 — X1 不自动取消 UNALLOCATED_EXPOSURE

X1 中：

unallocated exposure 可以压住新采购。

如果因此继续服务失败：

保留。

这用于证明：

仅仅扩大 horizon / forward allocation 是否足够。

不要提前修。

---

# Stage 17 — X2 的 Stale Commitment 条件

X2 只有同时满足以下条件才允许取消：

1. pending 尚未 dispatch；
2. 已 OVERDUE 或明确失去当前 promise；
3. 无法及时覆盖原 requirement；
4. 无法 forward-assign 到当前 visibility horizon 内任何 requirement；
5. 当前 known suppliers 中存在一个正量 timely offer；
6. 取消后 replacement 不会超过真实可见 requirement exposure。

然后才：

CANCEL_REQUESTED。

确认前：

旧 pending 仍占 exposure。

---

# Stage 18 — Cancel Confirmation 后才释放采购责任

沿用 Round4A/4B 已验证规则。

例如：

pending80

请求取消

确认前 dispatch30

确认时：

只能取消50。

30：

继续 in_transit。

只释放50 exposure。

最多替代50。

绝不能替代80。

---

# Stage 19 — Safety Stock 继续与 Plan 分开

保持 Round5：

`total procurement need`

不是简单：

`safety + plan`

继续避免双算。

Round5B 只调整：

**什么时候释放计划需求。**

不能把 safety target320 改大来修 long lead。

不能把 long-lead tail 直接变成更大的 safety stock。

---

# Stage 20 — X1/X2 不允许修改生产能力

本轮禁止：

- 提高 B capacity；
- 提高 C capacity；
- 提高 supplier capacity；
- 修改 recipe；
- 修改 route lead；
- 修改 supplier search；
- 修改 target。

否则不能隔离 planning release 机制。

---

# Stage 21 — 正式实验矩阵

默认600日。

至少完成：

---

## A — Normal lead2

需求10/day。

正常短lead。

X0/X1/X2。

观察：

lead-aware tail 是否在简单环境制造无意义额外库存。

---

## B — Original Wide H10

完整复用 Round5 原 Wide fixture。

绝对不要改参数。

运行：

X0
X1
X2

这是最重要反事实。

重点回答：

X1 是否因为 t+10 projected requirement 可以在t释放采购，

而真正增加 long-lead procurement。

---

## C — Wide H5

production horizon=5。

visibility 仍按 lead-aware 方法扩大。

研究：

production horizon 小于 supply lead 时，

是否还能形成合理 release。

不要把 H5 production horizon 自动扩大成10或20。

---

## D — Wide H20 Control

保留历史 H20。

用于比较：

“直接扩大 firm horizon”

和：

“firm H10 + projected visibility tail”

是否产生不同库存/计划责任。

---

## E — Mixed lead

short supplier：
lead2、能力有限。

long supplier：
lead8、能力充足。

X0/X1/X2。

检查：

短途供早期 bucket，

长途供更晚 bucket。

不能把所有需求都塞给短 supplier。

---

## F — Demand step-up

Day1–99：
10

Day100+：
15。

planner 不得提前知道。

观察：

projected tail 多快反映 observed-rate 变化。

---

## G — Demand step-down

Day1–99：
15

Day100+：
5。

重点观察：

滚动 requirement decrease

是否产生：

excess exposure。

不要自动把真实在途货删除。

---

## H — Temporary spike

Day100–119：
15

其他10。

观察：

visibility tail 是否导致更大的过量采购。

---

## I — Physical supply insufficient

物理网络最多7.5 machine/day。

X0/X1/X2 都必须失败满足10。

确认：

planning release 不制造供给。

---

## J — C capacity bottleneck

C=8/day。

需求10。

不得因为 projected tail 无限增加 coal/steel采购。

---

## K — B steel capacity bottleneck

中间产能不足。

需求传播仍受 capacity 限制。

---

## L — Stale pending + timely alternative

构造：

A先接受80；

随后 promise失效；

A pending 未发；

D 已知且可以 timely deliver。

比较：

X1：

不主动取消；

X2：

确认后取消并替代。

研究：

既有真实 exposure 如何与早期缺口协调。

---

## M — Partial dispatch during cancellation

A pending80。

取消等待期间 dispatch30。

确认50。

D最多替代50。

作为完整600日 scenario 或独立专项均可，

但必须经过真实订单/运输结算。

---

# Stage 22 — Requirement Bucket Stability Probe

固定需求10/day。

运行600日。

检查：

同一个绝对 need_by day

不会因为每天滚动重算拥有大量同时 active 的重复 bucket。

记录：

- bucket count
- revision count
- active buckets
- archived revisions

一个日期的执行责任只有一个当前状态。

---

# Stage 23 — Horizon Boundary Probe

专门构造：

production H=10

supplier total conservative lead：

9
10
11

要求解释：

- lead9；
- lead10；
- lead11；

对应 release/visibility 是否正确。

不要写：

lead<=H 才允许采购。

visibility tail 本来就是为了解除这个错误耦合。

---

# Stage 24 — Multiple Lead Suppliers Probe

同一 commodity：

supplier A arrival lead2
D lead4
E lead8
F lead12

建立 requirements：

Day+2
Day+5
Day+9
Day+13

检查 allocation / release：

每个 bucket 使用能够及时覆盖它的候选。

排序继续使用已有 matching 规则。

不要发明价格。

---

# Stage 25 — Rolling Revision Probe

Day t：

projected Day+15 requirement=80

Day t+1：

修订为100

应该新增：

20 responsibility。

不能再买100。

反向：

80→50

如果已有80 accepted，

不能删除30物资。

应产生：

30 excess exposure。

---

# Stage 26 — Excess Supply Exposure

新增诊断：

`excess_supply_exposure`

表示：

已经存在真实 supply，

但当前 revised visible requirements 不再需要全部数量。

它可以以后被新的未来 requirement 使用。

不能：

自动销毁；
自动退款；
自动取消。

X2 只对符合 stale 条件的 pending 做取消。

已 in_transit 的 excess：

必须继续到货。

---

# Stage 27 — Backlog Recovery

复用 Round5 temporary disruption。

C有 spare capacity15。

X1/X2 应能形成：

高于正常10

但不超过15

的 firm plan。

projected tail 同时为后续正常需求提前准备。

观察：

是否比 Round5 P3 更可执行。

不能把恢复前建立的缓冲与恢复后的计划效果混在一起。

报告必须分开。

---

# Stage 28 — Future Information Isolation

建立两个世界：

Day1–99 完全一致。

Day100以后：

一个需求升15，
一个维持10。

要求 Day1–99：

- firm plans
- projected tail
- release days
- requirement revisions
- allocations
- cancellations
- procurement
- shipment
- production

完全一致。

再增加：

Day100 后 route lead 改变

的分叉。

Day1–99 也必须一致。

---

# Stage 29 — 五阶段 mixed-lead Probe

复用 Round5 5-stage RecipeGraph。

给每一层不同 procurement / transfer lead。

验证：

最终 projected demand

可以向上游生成不同 release-by 日期。

不是只验证数量。

要求至少证明：

越上游的 requirement release 不晚于其下游生产需要。

不要实现完整工厂 scheduler。

---

# Stage 30 — Branching / Shared Input Regression

Round5 的：

- branching recipe；
- shared input；
- multi-sink；

全部继续作为回归。

另外检查：

时间化 allocation

不会把同一个 supply quantity 同时覆盖两个不同 need-by bucket。

---

# Stage 31 — Performance

Round5 已经有：

active requirements × live supplies

嵌套 reconciliation 成本。

本轮记录：

- active firm buckets
- active projected buckets
- revisions
- release checks
- allocation candidates
- forward reassignments
- unallocated exposures
- stale cancellation checks
- excess exposures
- supplier offer evaluations
- runtime
- optional tracemalloc

不要扫描完整 planning archive 来做每日决策。

历史 revision 只能用于报告。

运行决策使用 active indexes。

---

# Stage 32 — 必须寻找的失败模式

不要提前修。

## 1. X1 仍被 unallocated exposure 卡住

保留。

这正是 X2 存在的原因。

## 2. X2 频繁 cancel/reorder

记录。

可能说明 stale 判定过激。

不要加 cooldown 掩盖。

## 3. Step-down 出现 excess inventory

如果账目正确：

这是 rolling forecast + long lead 的经济结果。

不要当 correctness bug。

## 4. H5 与 H10 仍不同

允许。

目标不是让所有 horizon 结果相同。

目标是：

**不再因为 supplier lead 比 firm horizon 长1天，就完全无法形成可执行采购。**

## 5. X1/X2 没改善 Wide

允许。

继续定位真正瓶颈。

不要改参数。

---

# Stage 33 — Correctness Tests

至少新增：

1. X0完整复现Round5 P3。
2. firm/projected严格分离。
3. projected不进入actual production。
4. stable requirement bucket不按decision day重复。
5. revision increase只产生delta。
6. revision decrease不删除真实供应。
7. release_by计算正确。
8. release不读取future shipment。
9. supply只能覆盖available_by<=need_by。
10. forward reassignment不能向过去移动。
11. supply quantity不能双重分配。
12. unallocated exposure仍进入总去重。
13. X1不自动取消。
14. X2只有满足stale条件才取消。
15. cancel未确认不能replacement。
16. partial dispatch后只取消剩余pending。
17. in_transit永远不能取消。
18. safety/plan不重复采购。
19. rolling600日不重复购买同一责任。
20. horizon lead9/10/11边界正确。
21. future demand隔离。
22. future lead/capacity隔离。
23. physical shortage不能被planner修复。
24. production capacity bottleneck不会无限采购。
25. coal/steel/machine residual=0。
26. order residual=0。
27. Round2–Round5历史验证全部继续通过。
28. replay deterministic。

不要断言：

X1 backlog < X0

或：

X2 backlog < X1

作为 correctness test。

---

# Stage 34 — 报告

生成：

`EXECUTABLE_PLANNING_REPORT.md`

必须回答：

1. Round5 P3 H10 为什么无法形成 long-lead executable procurement？
2. firm horizon 和 supply visibility 为什么必须分开？
3. projected tail 是否真的不冒充 production plan？
4. stable buckets 是否解决每日滚动重复责任？
5. release_by 是否解除“H < lead 就完全不能采购”的耦合？
6. Wide X0/X1/X2 实际结果是什么？
7. X1是否被 stale/unallocated exposure 卡住？
8. X2 cancellation 是否带来实际改善，代价是什么？
9. H5/H10/H20 下库存、在途、backlog和采购暴露分别如何？
10. step-down 是否出现真实 excess exposure？
11. mixed lead 是否形成正确的日期分工？
12. partial cancellation 是否继续保持旧在途？
13. physical/capacity bottleneck 是否仍诚实失败？
14. 五阶段 mixed-lead release 是否成立？
15. planning work随什么增长？
16. 当前是否已经具备扩大到正式多企业生产网络的时序基础？

不能写：

“H20最好，因此正式用20”。

不能写：

“X1/X2 backlog最低，因此正确”。

---

# Stage 35 — EXECUTABLE_PLANNING_GATE

最后给出：

`EXECUTABLE_PLANNING_GATE = PASS / FAIL`

PASS 至少要求：

- firm plan与projected visibility分离；
- long lead 不再因 firm horizon 边界完全无法释放；
- stable rolling buckets成立；
- revision不会重复采购；
- supply allocation严格按日期；
- late supply只能forward reassign；
- unallocated真实exposure不消失；
- confirmed cancel才能replacement；
- in-transit不重复采购；
- mixed lead工作；
- 五阶段release probe成立；
- 所有物质账保持；
- future information isolation成立。

PASS 只表示：

> **当前 planning layer 已经能够形成时间上可执行、可滚动协调的采购释放责任，可以开始扩大多企业生产网络进行更大价值实验。**

不表示：

X1/X2 是最终经济模型。

---

# Stage 36 — 下一轮 Gate

如果 EXECUTABLE_PLANNING_GATE PASS：

下一轮优先候选才允许包括：

## A. Multi-Firm Production Network

如果 planning 时序已经稳定，

把多个真实 buyer/producer 接到同一网络。

## B. Production Scheduling

只有发现日粒度capacity leveling成为主要瓶颈时。

## C. Pricing

只有供需网络已经可以形成真实竞争和短缺，

并且价格缺失成为明确因果缺口时。

## D. Household Consumption

只有最终商品供给链已经足够稳定，

需要把需求从 fixture 转成人物/家庭时。

不要自动选择。

必须根据结果推荐。

---

# Stage 37 — Git / PR

完成后运行：

- 全部历史 verify
- Round5B tests
- Round5B full replay ×2

branch：

`research/executable-planning-round5b`

创建独立 PR。

建议标题：

`Coordinate rolling plans with executable procurement release`

不要自动 merge。

PR body 至少包含：

- Round5 baseline
- X0/X1/X2
- firm vs projected
- stable buckets
- release-by
- allocation reconciliation
- stale exposure
- Wide反事实
- H5/H10/H20
- correctness
- performance
- limitations
- EXECUTABLE_PLANNING_GATE

---

# Stage 38 — 本轮禁止

不要加入：

- price
- money
- credit
- banking
- wage
- household
- labor
- securities
- supplier reputation
- random forecast
- ML
- stochastic demand
- optimization solver
- full MRP suite
- factory shift calendar
- WWO integration

不要复制 Simulation。

不要建立 EconomicRuntime。

不要通过扩大 safety target 修 Wide。

不要把 production horizon 直接改成20然后宣布问题解决。

---

# Stage 39 — 最终反馈

最终按：

### Stage 0 — Round5 baseline
DONE / PARTIAL / BLOCKED

### Stage 1 — Regression
DONE / FAILED

### Stage 2–20 — Executable planning semantics
DONE / PARTIAL / BLOCKED

### Stage 21–32 — Experiments
DONE / PARTIAL / BLOCKED

### Stage 33 — Correctness
DONE / FAILED

### Stage 34 — Report
DONE / PARTIAL

### Stage 35 — EXECUTABLE_PLANNING_GATE
PASS / FAIL

### Stage 36 — Next Gate
根据实际结果推荐下一方向。

### Stage 37 — Git / PR
DONE / PARTIAL / BLOCKED

列出：

- main/base SHA
- tag
- branch
- commits
- PR URL
- CI

### Remaining structural limits

只列真实剩余限制。

本轮完成后停止。

不要自动启动下一轮。