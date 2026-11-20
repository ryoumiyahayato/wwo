你现在继续独立私有仓库：

`ryoumiyahayato/wwo-economy-lab`

实际推进：

# Round6 — Multi-Firm Production Network & Shared Scarcity
# 多企业生产网络、共享供给与竞争性分配实验

这是一轮真实施工任务。

Round5B 已经建立：

- firm / projected requirement；
- stable rolling requirement bucket；
- release-by；
- lead-aware visibility；
- date-feasible supply allocation；
- confirmed cancellation replacement；
- recipe-driven planning；
- bounded supplier discovery/matching。

并通过：

`EXECUTABLE_PLANNING_GATE`

但目前物理经济仍然主要是：

`A coal → B steel → C machine`

Round4C 的双 buyer 只是接口 probe；
Round5B 也明确没有验证真实多 buyer 竞争。

因此本轮目标不是继续优化 X1/X2。

目标是：

> **把现有黑箱扩成一个真正存在多个买方、多个卖方、多个生产者、共享稀缺投入和独立规划状态的物理生产网络。**

本轮主要测试：

- 多个企业能否同时存在；
- 同一 supplier 的库存能否被多个 buyer 正确竞争；
- 中间品能否像煤一样使用统一 supplier admission / matching；
- 多个生产者是否各自拥有库存、订单、计划和需求；
- buyer/seller 数量增加以后是否仍然守恒；
- 不同稀缺分配规则会不会显著改变分布与服务；
- 算法工作量随活动 firm / edge / known candidate 如何增长。

这仍然不是完整市场。

不加入价格、货币、利润、工资或金融。

---

# Stage 0 — 合并并冻结 Round5B

检查 PR #7。

如果：

- CI 全绿；
- head 与已验证 Round5B head 相同；
- MERGEABLE/CLEAN；
- 无 unresolved blocking review；
- 没有未经说明的新提交；
- 当前账号具有 merge 权限；

则直接合并 PR #7。

PR OPEN 本身不是停止条件。

合并以后：

1. 同步最新 main；
2. 运行全部历史验证；
3. 创建 annotated tag：

`economy-lab-v0.5b-executable-planning`

建议 message：

`Verified Round5B executable rolling planning research baseline.`

4. 从最新 main 创建：

`research/multi-firm-network-round6`

随后继续。

如果 Git smart HTTP 失败而 GitHub API 可用：

继续使用已验证 API 发布方式。

GitHub 单步失败只阻塞对应远端操作。

只要 baseline 明确可取得，不停止本地研究。

---

# Stage 1 — 全量回归

施工前实际运行所有历史 tests 和 verify wrappers：

- original 8
- Round2 9
- Round3 18
- Round4A 29
- Round4B 33
- Round4C 32
- Round5 40
- Round5B 45

记录：

- Python version；
- base SHA；
- tag；
- branch；
- commands；
- exit codes；
- 所有历史 summary SHA。

施工结束以后全部再运行一次。

Round6 关闭时，所有旧实验继续复现。

不得为了多企业改写历史 fixture / CSV / report。

---

# Stage 2 — Round6 的核心边界

本轮必须从：

“一个企业链条”

推进到：

“多个真实企业节点组成的同一个物理网络”。

但：

**仍然只有一个世界、一个时间轴、一套订单和物质结算。**

禁止：

- 每个企业一个 Simulation；
- 每条产业链一个 Simulation；
- 第二套 inventory ledger；
- 第二套 shipment engine；
- 第二套 order authority。

所有企业必须存在于同一个模拟状态中。

---

# Stage 3 — 建立通用 FirmNode

增加最小通用企业表示。

每个 firm 至少有：

- `firm_id`
- `firm_type`
- `place_id`
- owned inventories by commodity
- recipes
- production capacities
- supplier knowledge by commodity
- customer order/request state
- planning state
- procurement state

建议类型只用于 fixture / diagnostics：

- RAW_SUPPLIER
- PROCESSOR
- FINAL_PRODUCER

不要把 firm_type 写成算法硬分支。

算法应主要依据：

recipe / inventory / routes / knowledge。

---

# Stage 4 — Inventory 必须变成 firm × commodity

不要继续假定：

B 永远拥有 steel，
C 永远拥有 machine。

正式表示：

`inventory[firm_id][commodity]`

至少真实支持：

- 多个 firm 持有 coal；
- 多个 firm 持有 steel；
- 多个 firm 持有 machine。

旧 A/B/C fixture 必须仍能映射到这一结构。

---

# Stage 5 — Recipe 必须绑定 producer

继续复用 Round5 RecipeGraph。

但生产执行必须能够表达：

B1：

`2 coal -> 1 steel`

B2：

`2 coal -> 1 steel`

C1：

`4 steel -> 1 machine`

C2：

`4 steel -> 1 machine`

每个 producer：

有独立 capacity。

不要把：

“steel 只有一个 producer B”

写死在 production path。

---

# Stage 6 — Route 必须是 seller → buyer → commodity

统一表示：

`Route(
 seller_id,
 buyer_id,
 commodity,
 capacity,
 lead_time
)`

例如：

A → B1 coal
A → B2 coal
D → B1 coal

B1 → C1 steel
B1 → C2 steel
B2 → C1 steel
B2 → C2 steel

不得根据 commodity 猜固定 route。

旧 B_C 路径应退化成：

B → C / steel

的一条普通 route。

---

# Stage 7 — 中间品采购必须升级到统一 admission

当前剩余明确限制之一是：

steel 仍使用旧单 supplier / S0 行为。

Round6 必须把：

Round4A/4B 已有：

- PurchaseRequest
- SupplierOffer
- S2 stock-confirmed ATP
- shared stock commitment
- accepted/rejected
- known candidate matching

推广到：

**所有可交易 intermediate commodities。**

至少：

coal

和：

steel

都走同一个 supplier interface。

不要再给 steel 保留隐藏的自动接受特权。

---

# Stage 8 — Supplier Stock Commitment 必须跨 buyer 共享

这是本轮最核心 correctness 之一。

如果 A 当前可承诺 coal=100：

B1 请求80；
B2 请求80。

总 accepted：

绝不能160。

同一：

supplier + commodity

必须共享：

`StockCommitments`

无论 buyer 是谁。

要求：

`sum(live stock commitments for supplier/commodity)
<= current uncommitted sellable stock`

同一单位库存不能同时卖给两个企业。

---

# Stage 9 — 多 buyer 报价与真实接受分开

SupplierOffer 仍然只是 quote。

多个 buyer 同时可能看到：

A max acceptable = 100。

这不意味着：

B1 和 B2 都最终接受100。

真正 acceptance 时必须重新检查：

- shared stock；
- shared commitment；
- transport slot；
- current request competition。

记录：

- quoted quantity；
- requested quantity；
- actually accepted quantity。

---

# Stage 10 — 同日多 buyer 不能依赖 Python 遍历顺序

不能因为：

B1 恰好在 dict 里排在 B2 前面，

就无意间获得所有稀缺货物。

建立明确：

**Procurement Round**

流程。

每个采购边界：

1. buyers 根据当前 need / offers 形成本轮 requests；
2. 按 supplier + commodity 汇总；
3. supplier 对本轮所有 requests 执行明确 contention policy；
4. 创建 accepted/rejected；
5. buyers 更新 remaining need；
6. 如果仍有下一 known candidate，可进入下一 procurement round；
7. 候选耗尽或 need=0 后停止。

限制：

单日 rounds 不得超过：

该 buyer 当前 known candidate count。

不能无限循环。

---

# Stage 11 — 两个正式 Scarcity Allocation Policy

本轮必须承认：

没有价格以后，

稀缺 supplier 在多个 buyer 之间如何分配本身就是策略选择。

只比较两个。

## C0 — Stable Queue Allocation

按照稳定键：

`request_day`
→ `procurement_round`
→ `buyer_id`
→ `request_id`

依次满足。

注意：

它可以造成稳定的 buyer 优势。

这是候选策略结果。

不是“正确规则”。

---

## C1 — Deterministic Pro-Rata Allocation

如果：

supplier available quantity < total requested

则按各 buyer：

`requested / total_requested`

比例分配。

整数数量使用：

deterministic largest remainder

处理。

tie-break：

稳定 buyer_id。

必须满足：

`sum accepted <= supplier available`

每个 buyer：

`accepted <= requested`

不得因为 rounding 创造商品。

---

# Stage 12 — C1 不允许依赖输入列表顺序

构造同一组 request，

随机/反向改变：

输入创建顺序。

结果必须按：

buyer ID / rule

保持一致。

这不是随机经济。

只是防止实现顺序变成隐藏分配政策。

---

# Stage 13 — Single Buyer 必须退化到旧 S2

如果某 supplier 在一个 procurement round 只有一个 buyer：

C0 与 C1 都必须：

接受 min(request, ATP)

即退化成原 S2 admission。

单 buyer control 必须能够与旧 Round5B 相应路径比较。

---

# Stage 14 — Buyer Planning 必须彼此独立

B1、B2、C1、C2：

各自拥有：

- DemandHistory；
- firm/projected requirements；
- ReleaseBook；
- allocations；
- procurement need；
- known suppliers。

B1 的 planning state：

不得直接成为 B2 的 state。

C1 也不得读 C2 的内部计划。

---

# Stage 15 — 企业之间只能通过可观察经济事实传播需求

这是本轮的重要信息边界。

禁止：

B1 直接读取 C1 的内部 ProductionPlan。

企业之间的真实需求传播使用：

- PurchaseRequest；
- accepted order；
- rejected request；
- delivered order；
- buyer公开采购请求。

也就是说：

C1 需要 steel

→ C1 向 B1/B2 发采购 request

→ B1/B2 才知道存在 downstream demand。

不要建立中央 planner 替所有企业共享内部计划。

---

# Stage 16 — Supplier-side Demand Observation

供应商可以观察：

自己实际收到的采购 requests。

包括：

accepted
和
rejected。

因为即使当前没有 stock 能接受，

supplier 仍然知道：

有人请求了这些货。

建立：

`CustomerRequestHistory`

按：

supplier + commodity

保存已收到需求。

它是供应商自己的观察事实。

不是世界全局需求。

---

# Stage 17 — 防止 repeated rejected request 被错误当成新最终需求

同一个 buyer 的同一个 requirement：

不能每天 retry 后被 supplier 当成完全独立的新最终消费。

PurchaseRequest 应保留：

`requirement_bucket_id`
或
`procurement_need_id`

Supplier-side observed demand 至少能够区分：

- new requirement exposure；
- repeated attempt for same unresolved requirement。

记录：

`gross request flow`

和：

`distinct unresolved demand exposure`

二者分开。

不要静默把每天重试累加成无限需求率。

---

# Stage 18 — 多企业 Planning 默认使用 Round5B X1 语义

正式 Multi-Firm 矩阵默认先使用：

**X1 release-aware rolling planning**

而不是 X2。

原因：

X2 stale cancellation 没有表现出普遍服务改善。

这不是宣布 X1 正式正确。

只是为了隔离：

多企业与共享稀缺性。

X0 与 X2 仍保留历史实现和专项 control。

不要删除。

---

# Stage 19 — 不允许中央计划直接把 C 需求换算成 B coal

以前单链条可以通过 RecipeGraph 直接传播：

machine → steel → coal。

多企业正式矩阵中：

跨企业边界不能直接跳过订单。

正确路径：

C1 计划 machine
↓
C1 生成 steel requirement
↓
C1 向 B supplier 发 request
↓
B 收到需求事实
↓
B 自己形成 steel production plan
↓
B 自己生成 coal requirement
↓
B 向 coal supplier request

这一步非常重要。

否则虽然有多个 FirmNode，

本质仍然是中央 MRP。

---

# Stage 20 — 企业内部仍可 recipe-driven

同一企业内部：

production plan

→ input requirement

继续直接使用 RecipeGraph。

跨 firm：

必须通过 request/order 信息传播。

这样：

物料结构仍然通用，

但知识边界不会因为多企业而消失。

---

# Stage 21 — 每日统一结算顺序

定义并固定一个明确的多企业日循环。

至少：

1. receive all due shipments
2. deliver today's external demand facts
3. confirm due cancellations/information
4. each firm updates local observations
5. each firm generates/revises firm/projected plans
6. reconcile existing supply allocations
7. actual production using currently available inputs
8. terminal deliveries
9. compute procurement release needs
10. query known suppliers
11. collect procurement round requests
12. supplier contention/admission
13. repeat bounded procurement rounds if residual need remains
14. dispatch using original physical settlement
15. end-of-day ledgers / observations

如果为了保持历史单链 equivalence 需要不同细节：

明确记录兼容 boundary。

不要让 firm 遍历顺序改变经济结果。

---

# Stage 22 — 第一套正式网络 fixture

建立：

## Raw suppliers

A
D

## Steel producers

B1
B2

## Machine producers

C1
C2

## Terminal demand sinks

T1
T2

T1 默认向 C1 形成：

5 machine/day

T2 默认向 C2 形成：

5 machine/day

总终端需求仍：

10/day

这样可以与旧世界量级比较。

---

# Stage 23 — 基础产能建议

保持简单、明确。

A coal：
正常可支持100/day。

D coal：
60/day。

B1：
30 steel/day。

B2：
30 steel/day。

每 steel：

2 coal。

C1：
8 machine/day。

C2：
8 machine/day。

每 machine：

4 steel。

总正常 capacity 足以服务10/day。

不要为了让某候选更漂亮反复调这些数字。

---

# Stage 24 — Knowledge Topology

每个 buyer 拥有自己的 supplier known set。

例如正常 fixture：

B1 knows A,D
B2 knows A,D

C1 knows B1,B2
C2 knows B1,B2

正式 matching 不能遍历：

所有 world firms。

继续沿用 bounded known-candidate 原则。

---

# Stage 25 — Scenario A：Single-chain equivalence

只启用：

A
B1
C1
T1

并把参数设成旧对应 fixture。

使用单 buyer/supplier。

目标：

证明 generic Firm/Route/Order 路径能够复现旧 Round5B X1 对应行为。

如果不能：

先定位结构差异。

不要直接进入大网络。

---

# Stage 26 — Scenario B：Two firms, no scarcity

A/D 对 B1/B2 的总能力足够。

B1/B2 对 C1/C2 的 steel 总能力也足够。

运行：

C0
C1

正常情况下两种 contention policy 不应经常触发稀缺分配。

观察：

是否出现无理由 buyer 偏差。

---

# Stage 27 — Scenario C：Shared coal scarcity

只允许一个主要 coal supplier，

可持续供给：

80 coal/day。

B1+B2 合计希望获得：

120/day。

比较：

C0
C1。

观察：

- B1/B2 accepted coal；
- steel output；
- downstream machine output；
- backlog by sink；
- total backlog。

不要要求两策略总服务不同。

即使总服务一样，

分布差异也非常重要。

---

# Stage 28 — Scenario D：Persistent queue advantage

使用持续 scarcity。

运行600日。

检查 C0 是否因为稳定排序使某 buyer 长期占优。

如果出现：

保留。

不要偷偷轮换 buyer ID。

这是没有价格/公平规则时需要暴露的模型选择。

---

# Stage 29 — Scenario E：Pro-rata scarcity

同 D fixture。

C1。

检查：

稀缺投入是否更均匀分配。

但不要把：

“更均匀”

写成：

“经济更正确”。

只报告：

分配和服务后果。

---

# Stage 30 — Scenario F：Shared steel scarcity

coal充足。

但 B1/B2 当前 steel 总供给低于 C1/C2 请求。

正式测试：

steel 也通过：

S2 + contention

而不是旧自动接受。

记录：

C1/C2 steel request / accepted / rejected。

---

# Stage 31 — Scenario G：One steel firm shutdown

Day100：

B1 停产。

B1 已有订单/在途继续按真实状态结算。

C1/C2 如果知道 B2：

可以把后续 residual need 转向 B2。

不得：

直接把 B1 订单删除。

如果 B2 capacity 不足：

backlog 应诚实增长。

---

# Stage 32 — Scenario H：Asymmetric lead

B1：

较短 lead，
较低 capacity。

B2：

较长 lead，
较高 capacity。

测试：

Round5B release-aware planning

在真实多个 steel supplier 上是否仍能工作。

---

# Stage 33 — Scenario I：Asymmetric terminal demand

T1：

8/day

T2：

2/day

总量仍10。

观察：

稀缺上游时 C0/C1 对两个 demand sink 的服务分布。

---

# Stage 34 — Scenario J：One sink step-up

Day1–99：

T1=5
T2=5

Day100+：

T1=10
T2=5

总需求变15。

不得提前知道。

保留 Round5B step-up 服务代价作为对照。

研究：

一个企业需求变化如何通过真实跨企业订单逐层传播。

---

# Stage 35 — Scenario K：Low-buffer disruption/recovery

保留 Round5B 明确暴露的：

低缓冲恢复较慢

这一失败方向。

对一个 coal route 做 temporary shutdown。

不要在多企业版本里提高 buffer 遮掉。

观察：

网络是否通过其他 firm / supplier 自动产生新路径，

以及真正恢复时间。

---

# Stage 36 — Scenario L：Shared supplier partial cancellation

B1、B2 都对 A 有 accepted pending。

其中一张订单进入 stale cancellation。

必须证明：

取消 B1 的 reservation

只释放 B1 对应数量。

不得动 B2 commitment。

随后释放的库存可以被新 requests 使用。

---

# Stage 37 — Scenario M：Intermediate bottleneck

coal 足够。

B1+B2 总 steel capacity 刻意限制在：

低于下游 demand。

要求：

B1/B2 coal采购不会因为 terminal backlog 无限增长。

capacity-constrained plan 必须阻止上游 raw overbuy。

---

# Stage 38 — Scale Fixture S1

真实物理网络：

1 raw
1 steel
1 machine
1 sink

作为 oracle scale。

---

# Stage 39 — Scale Fixture S2

2 raw
2 steel
2 machine
2 sinks

使用正式完整 planning/order/transport。

---

# Stage 40 — Scale Fixture S5

建议：

3 raw suppliers
5 steel producers
10 machine producers
10 demand sinks

每个 buyer 只知道：

2–3 个候选 supplier。

使用 deterministic ring / bounded-degree topology。

禁止 all-to-all network。

---

# Stage 41 — Scale Fixture S10

建议：

5 raw suppliers
10 steel producers
20 machine producers
20 sinks

仍然保持：

每个 buyer degree <= 3 或 <= 4。

运行至少：

200日

如果性能允许再跑600日。

不要因为600日太重而直接删除该规模。

如果缩短：

报告明确说明。

---

# Stage 42 — 网络生成器必须 deterministic

所有 firm ID、capacity、lead、known edges：

使用固定规则生成。

不要引入随机 network generator。

例如：

B_i knows raw[i % R], raw[(i+1) % R]

C_i knows steel[i % S], steel[(i+1) % S]

这样可以复现。

---

# Stage 43 — 不允许 procurement all-pairs

每天不能：

每个 buyer 扫描所有 sellers。

记录：

- world firms
- active firms
- known candidate edges
- offers queried
- request edges
- accepted edges
- shipment edges

目标：

matching/planning work 更接近：

**active known edges**

而不是：

buyer × all sellers。

---

# Stage 44 — Sleeping / irrelevant firms probe

在 S2 正常世界旁边加入：

100 个与当前 commodity 网络没有 known edge 的 firm。

它们可以存在：

inventory / metadata

但不参与当前 active network。

要求：

- buyer known sets不变；
- offer/matching counters不变；
- active physical结果不变。

允许：

world construction / storage / ledger总成本增加。

不要宣称 sleeping firm 免费。

---

# Stage 45 — Firm insertion order probe

同一个 network fixture，

改变：

FirmNode 创建顺序。

C1 pro-rata 结果必须一致。

C0 只能依赖明确 stable buyer ID policy，

不能依赖容器插入顺序。

---

# Stage 46 — 多商品数量守恒

对每个 commodity：

coal
steel
machine

都建立 network-wide identity。

至少：

initial stock
+ cumulative production/source
- cumulative recipe consumption
- terminal delivery

必须对应：

all firm inventories
+ all in-transit

订单取消不进入物质来源。

每个 supplier / buyer order identity 继续成立。

---

# Stage 47 — Firm-level 账也要可核对

除 world total 外，

每个 firm/commodity 至少能报告：

opening inventory
received
produced
consumed
dispatched
closing inventory

避免只有全世界守恒，

但企业间凭空转移。

增加：

firm-level inventory flow residual。

---

# Stage 48 — Shared Stock Commitment correctness

至少构造专项：

A stock=100

B1 request80
B2 request80

C0：

按明确规则分配。

C1：

按比例分配。

但两者始终：

total commitment <=100。

再加入：

B1 confirmed cancel20

验证：

只释放20。

B2原承诺不受影响。

---

# Stage 49 — Shared Intermediate Inventory correctness

B1 steel stock100。

C1 request80
C2 request80。

重复 Stage48。

这证明：

统一 supplier机制不只是煤层有效。

---

# Stage 50 — Buyer-specific Knowledge

同一个 supplier B2：

C1知道；

C2不知道。

即使 B2 有库存，

C2 不得 query B2。

不能因为 network registry 有 B2 就全知。

---

# Stage 51 — Demand Information Boundary

验证：

B1 的 demand history

只来自：

- 自己收到的 PurchaseRequest；
- 自己已有 accepted customer orders；
- 明确自身外生需求（如有）。

不能读取：

C1 terminal backlog；
C1 internal ProductionPlan；
整个 world final demand。

增加 guard。

---

# Stage 52 — Repeated Request Identity

如果 C1 对同一个 steel requirement：

连续多日重试，

B1 demand observation 必须识别：

同一个 unresolved requirement。

输出同时记录：

gross request flow

和：

distinct requirement exposure。

避免 supplier planner 将：

同一个50缺口重试10天

误判为500新需求。

---

# Stage 53 — 本轮不要强行统一所有 planning 策略

正式网络默认 X1。

但至少做三个小 controls：

- X0 single-chain；
- X1 single-chain；
- X1 multi-firm。

不要跑：

X0/X1/X2 × C0/C1 × 全部网络

形成无意义组合爆炸。

本轮重点是：

**网络结构和共享稀缺性。**

---

# Stage 54 — 输出指标

至少输出：

## Network

- firm count
- producer count
- buyer count
- seller count
- route count
- known edges
- active edges

## Firm

每 firm：

- inventories
- planned output
- actual output
- input shortages
- customer demand exposure
- procurement need

## Requests

每 buyer/seller/commodity：

- quoted
- requested
- accepted
- rejected
- cancellation

## Scarcity

- supplier available quantity
- total requests
- allocation policy
- accepted by buyer
- unmet requests
- concentration/share metrics

简单 concentration 可以输出：

max buyer share

不需要经济指数理论。

## Physical

- production by firm
- shipments by route
- terminal delivery by sink
- backlog by sink
- total backlog
- machine-days

## Performance

- active planning buckets
- known-candidate visits
- offer queries
- procurement rounds
- contention allocations
- active orders
- active shipments
- firm settlement visits
- route settlement visits
- runtime
- optional tracemalloc

---

# Stage 55 — 本轮特别关注“分配规则敏感性”

同一个物理网络、

同样总资源、

只改变：

C0 vs C1。

比较：

- total output
- total backlog
- backlog distribution
- firm survival/production continuity
- inventory distribution

如果总结果相近、分布差异很大：

这是重要结果。

说明：

没有价格时，

稀缺分配机制本身对个体企业命运影响很大。

不要对此提前做价值判断。

---

# Stage 56 — 不加入价格来解决 contention

即使 C0/C1 结果差异很大：

本轮也不要立即加入 price。

先记录：

**scarcity allocation sensitivity**

作为将来是否需要价格/竞价机制的证据。

---

# Stage 57 — Correctness Tests

至少新增：

1. single-firm generic path reproduces oracle。
2. firm inventories彼此独立。
3. route明确seller/buyer/commodity。
4. steel使用统一admission。
5. 多buyer不能重复承诺supplier stock。
6. quote不是reservation。
7. actual admission重新检查shared availability。
8. C0不依赖container insertion order。
9. C1 pro-rata不依赖request insertion order。
10. C1总accepted<=available。
11. buyer accepted<=requested。
12. residual need才能进入下一supplier round。
13. procurement rounds有界。
14. buyer planning state隔离。
15. buyer knowledge隔离。
16. unknown supplier不得query。
17. supplier demand history不读取buyer内部plan。
18. repeated requirement不会被supplier当成无限新需求。
19. firm-level commodity residual=0。
20. network-level commodity residual=0。
21. order identities=0。
22. confirmed cancellation只释放对应buyer commitment。
23. old in-transit不取消。
24. intermediate steel stock不重复承诺。
25. capacity bottleneck不导致raw无限采购。
26. future demand prefix隔离。
27. future shutdown/capacity prefix隔离。
28. sleeping firms不改变active matching/outcome。
29. C1 firm insertion order invariance。
30. bounded-degree network不做all-pairs supplier scan。
31. 所有旧历史验证继续通过。
32. replay deterministic。

不要把：

C1 backlog<C0

写成 correctness test。

---

# Stage 58 — 必须保留的失败

不要提前修。

## 1. Stable queue starves one buyer

保留。

## 2. Pro-rata降低某个高需求企业效率

保留。

## 3. Step-up重新出现较大backlog

保留。

## 4. Low-buffer recovery变慢

保留。

## 5. Stale切换没有改善

保留。

## 6. Intermediate bottleneck产生长期缺口

保留。

这些都可能是模型诊断，

不是测试失败。

---

# Stage 59 — 性能与规模

重点回答：

S1
→ S2
→ S5
→ S10

时：

- planning work
- matching work
- physical settlement
- archive size

分别随什么增长。

不要只报总秒数。

特别区分：

1. known-edge decision cost；
2. active order/shipment cost；
3. world firm iteration cost；
4. reporting/archive cost。

如果 S10 暴露 O(N²) all-pairs：

记录为 structural blocker。

不要立刻大型优化掩盖。

---

# Stage 60 — 报告

生成：

`MULTI_FIRM_NETWORK_REPORT.md`

必须回答：

1. 是否真正存在多个独立 buyer / producer，而不是复制链条？
2. 是否只有一个 world / ledger / shipment authority？
3. steel 是否已经和coal一样走统一supplier机制？
4. shared stock commitment能否安全支持多个buyer？
5. C0与C1在稀缺环境下产生什么不同？
6. 是否存在稳定buyer偏置？
7. total服务与分布服务是否不同？
8. 一个企业需求step-up如何通过真实订单逐层传播？
9. 是否还有中央planner泄漏？
10. intermediate bottleneck 是否正确阻止 raw overbuy？
11. B1 shutdown 后其他钢厂能否承接 residual demand？
12. buyer-specific knowledge是否保持？
13. 1/2/5/10规模下工作量如何变化？
14. sleeping/irrelevant firms影响什么、不影响什么？
15. 多企业以后 Round5B 哪些失败被放大？
16. 是否观察到必须引入价格才能进一步回答的问题？
17. 还是主要缺口仍是生产/运输/信息？
18. 黑箱是否已经达到可以做“较大网络模型价值实验”的规模？

禁止：

因为 C1 更均匀

就宣布 C1 正确。

禁止：

因为多企业跑通

就宣布经济模型有效。

---

# Stage 61 — NETWORK_EXTENSIBILITY_GATE

最终给出：

`NETWORK_EXTENSIBILITY_GATE = PASS / FAIL`

PASS 至少要求：

- 两个以上真实生产 buyer 同时运行；
- 两个以上中间生产者；
- 多buyer共享supplier库存安全；
- coal/steel统一supplier机制；
- firm-local planning state；
- 跨企业需求通过request/order传播；
- 无中央plan读取泄漏；
- contention policy明确；
- allocation不依赖容器遍历顺序；
- firm-level和world-level守恒；
- bounded known-edge matching；
- S5完整600日运行；
- S10至少完成明确规模实验；
- future isolation成立。

PASS 的含义只有：

> **经济黑箱已经从单链条扩成真正多企业物理生产网络，可以开始在较大网络中评估策略、短缺、价格或家庭需求是否值得加入。**

不代表：

C0/C1/X1 被正式采用。

---

# Stage 62 — 下一方向 Gate

Round6 完成后根据实际证据选。

可能方向：

## A — Pricing / Market Clearing

只有当：

稀缺 buyer 分配规则显著影响结果，

而没有价格导致缺乏自然竞争依据。

## B — Transport Congestion / Shared Logistics

如果：

多企业后主要瓶颈变成线路共享和运输排队。

## C — Production Scheduling

如果：

工厂内部 capacity/date feasibility成为主要问题。

## D — Household Consumption

如果：

生产网络已经稳定，

下一缺口是 demand仍来自fixture而不是人物/家庭。

## E — Larger Network Validation

如果：

结构正确但规模仍不足以评估。

不要提前决定。

---

# Stage 63 — Git / PR

完成以后：

运行：

- 所有历史 verify
- Round6 tests
- Round6 full replay ×2

branch：

`research/multi-firm-network-round6`

创建独立 PR。

建议标题：

`Expand the lab into a shared multi-firm production network`

不要自动 merge。

PR body 必须写：

- Round5B baseline
- generic firm/inventory/routes
- unified coal/steel admission
- multi-buyer contention
- C0/C1
- local demand information
- scenario matrix
- scale fixtures
- correctness
- performance
- failure results
- NETWORK_EXTENSIBILITY_GATE
- next recommendation

---

# Stage 64 — 本轮禁止

不要加入：

- price
- money
- profit
- accounting currency
- credit
- banking
- wage
- household
- labor market
- securities
- auction
- bidding
- supplier reputation score
- random network
- random demand
- global optimization
- central economic planner
- WWO integration

不要复制 Simulation。

不要建立 EconomicRuntime。

不要通过提高capacity来消除scarcity实验。

---

# Stage 65 — 最终反馈

最终按：

### Stage 0 — Round5B baseline
DONE / PARTIAL / BLOCKED

### Stage 1 — Regression
DONE / FAILED

### Stage 2–20 — Generic multi-firm semantics
DONE / PARTIAL / BLOCKED

### Stage 21–58 — Network experiments
DONE / PARTIAL / BLOCKED

### Stage 59 — Scale / performance
DONE / PARTIAL

### Stage 60 — Report
DONE / PARTIAL

### Stage 61 — NETWORK_EXTENSIBILITY_GATE
PASS / FAIL

### Stage 62 — Next Direction
根据证据明确推荐一个方向。

### Stage 63 — Git / PR
DONE / PARTIAL / BLOCKED

列出：

- main/base SHA
- tag
- branch
- commits
- PR URL
- CI

### Remaining Structural Limits

只列真实限制。

本轮完成后停止。

不要自动进入价格、家庭或下一轮。