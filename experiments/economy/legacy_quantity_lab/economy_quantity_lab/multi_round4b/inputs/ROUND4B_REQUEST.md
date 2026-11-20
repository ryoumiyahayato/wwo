你现在继续独立私有仓库：

`ryoumiyahayato/wwo-economy-lab`

实际推进：

**Round4B — Bounded Multi-Supplier Matching & Switching**
**有限已知供应商、多供应商分配与切换实验**

这是一轮实际算法研究施工。

不是只重新验证 Round4A，也不是让你写方案后停止。

除非发现真正会污染既有基线的 correctness blocker，否则按阶段持续推进到实验、报告和独立 PR。

GitHub 某一步失败只能阻塞对应 Git 操作，不能无理由终止本地算法实验。

---

# Stage 0 — 合并并冻结 Round4A

检查 PR #3：

- CI 是否仍全绿；
- HEAD 是否仍为已验证 HEAD；
- mergeable 是否正常；
- 是否有 conflict；
- 是否有 unresolved blocking review；
- 是否存在未经说明的新提交。

如果都正常且当前账号有权限：

直接合并 PR #3。

不要因为它仍是 OPEN 就停止。

合并后：

1. 同步最新 main；
2. 运行全部旧验证；
3. 创建 annotated tag：

`economy-lab-v0.4a-supplier-admission`

建议 message：

`Verified Round4A supplier admission and ATP research baseline.`

4. 从合并后的 main 创建：

`research/multi-supplier-round4b`

如果 Git smart HTTP 不通，但 GitHub API 可用，可以沿用之前已经验证过的 API 工作方式。

不得 force push。

如果 Git 操作受阻但 Round4A 基线能够明确取得，则继续本地 Round4B，并最终报告 Git blocker。

---

# Stage 1 — 完整回归验证

Round4B 修改代码以前实际运行：

- 原 8 项测试；
- Round2 9 项；
- Round3 18 项；
- Round4A 29 项；
- `verify_baseline.py`
- `verify_round3.py`
- `verify_round4a.py`

记录：

- Python version；
- base commit；
- tag；
- branch；
- commands；
- exit codes；
- Round2 / Round3 / Round4A summary hashes。

Round4B 功能关闭时必须继续保持既有历史结果。

不得为了 Round4B 修改：

- 旧 fixture；
- H0/H1；
- Round3 historical results；
- Round4A historical results；
- 原 quantity ledger；
- 原 shipment receive；
- 原 FIFO dispatch；
- 原 production recipe。

---

# Stage 2 — Round4B 首先补 Round4A 已经证明缺失的“真实当前可供货约束”

Round4A 的运输 ATP 已经被缺货探针明确证明不充分：

线路有运力，不等于供应商有货。

Round4B 不建立完整 MRP，也不预测未来复杂生产。

只增加一个保守的：

**Stock-Confirmed ATP**

暂称：

`S2`

其目的只有：

> 供应商不能用同一批当前库存同时对多个采购承诺。

---

## 2.1 供应商当前可销售库存

定义：

`uncommitted_sellable_stock`

初始基础为：

`on_hand`

再扣掉：

已经被仍有效 accepted order 占用、但尚未 dispatch 的 stock commitment。

因此不能简单写：

`stock_atp = on_hand`

否则多个请求会重复承诺同一批库存。

---

## 2.2 Stock Commitment

当 S2 接受数量 q 时：

同时建立：

`stock_commitment += q`

这不是商品移动。

实际库存仍然在供应商仓库。

它只是说明：

这部分当前库存已经承诺给某张订单。

实际 dispatch 时：

- on_hand 按原 Simulation 扣；
- 对应 stock commitment 同量释放。

确认取消时：

- 未发部分对应 commitment 释放。

不得：

- 创建货物；
- 创建 shipment；
- 改变商品数量账。

---

## 2.3 S2 ATP

供应商的可接受数量先受：

Round4A transport ATP

限制。

再受：

当前未承诺库存

限制。

所以本轮候选：

`stock_confirmed_atp =
min(
    transport_atp,
    uncommitted_sellable_stock
)`

然后：

`accepted =
min(
    requested,
    stock_confirmed_atp
)`

这是保守策略。

它明确不承诺尚未生产出来的未来商品。

因此可能产生“明天会生产，但今天先拒单”的情况。

这是允许的实验结果。

不要偷偷加入未来 production forecast 来让曲线好看。

---

# Stage 3 — 必须先重新运行 Round4A 缺货反证

在进入多供应商以前，先用 S2 重跑一个最小探针：

供应商：

- on_hand = 0
- 当前没有可确认生产输出
- transport capacity = 100

请求：

320

S1 transport-only 预期仍可重现旧结果：

接受320。

S2 必须：

接受0；
拒绝320。

且：

- 不创建虚假 Order；
- 不创建 shipment；
- open_need 保留320。

如果 S2 在库存0时仍接受正数量：

Round4B correctness Gate FAIL。

先修正确性，不进入多供应商矩阵。

---

# Stage 4 — 建立第二供应商 D

只有 Stage 3 通过以后才加入 D。

不要复制另一个世界。

新增一个同类 coal supplier：

`CoalMine D`

使用同一个 commodity：

`coal`

明确给出自己的：

- place / supplier id；
- coal on_hand；
- coal production；
- production capacity；
- known transport route；
- route capacity；
- route lead_time；
- admission / stock commitment 状态。

建议第一轮使用清晰参数：

A：
- 原有参数保持；
- A→B lead_time=2；
- capacity=100/day。

D：
- 初始 coal on_hand=400；
- 最大生产=60/day；
- 默认仓内目标=400；
- D→B capacity=60/day；
- lead_time=4 days。

D 的生产也是显式 coal 来源。

不得从 A 复制库存。

D 必须进入 coal 的独立商品数量账来源记录。

总 coal 恒等式要相应包含：

累计 A 开采
+
累计 D 开采。

---

# Stage 5 — 严格区分 available / known / considered supplier

这是 Round4B 的核心之一。

世界事实可以有：

`available_supplier_ids = [A, D]`

但买方真正可使用的是：

`known_supplier_ids`

matching 只能输入：

`known_supplier_ids`

不能全局枚举所有 supplier。

因此：

D 即使真实存在、库存丰富、线路畅通，

如果 B 不知道 D：

**B 不得向 D 询价、发 request 或下订单。**

记录：

- available suppliers；
- known suppliers；
- considered suppliers；
- queried suppliers。

未来真正的信息系统只需要改变：

`known_supplier_ids`

而不是重写 matching。

---

# Stage 6 — Supplier Discovery 暂时用显式外部信息事件

本轮不要开发广告、商会、关系网、报纸或搜索成本。

使用确定性的：

`SUPPLIER_DISCOVERED`

事件。

例如：

Day60：

B learns supplier D。

这代表：

一个外部信息机制把 D 加入 known set。

它不是价格系统，也不是完整 information simulation。

记录：

- discovery_day；
- source label，例如 `fixture_information_event`；
- supplier id。

在 discovery 以前：

D 不得参与采购。

---

# Stage 7 — 定义 Supplier Offer

买方不能直接窥视 supplier 内部状态做排序。

对每个已知候选 supplier：

调用同一个 admission/offer 接口。

返回一个只包含买方可以获得的 offer：

至少：

- supplier_id
- commodity
- offer_day
- max_acceptable_quantity
- promised_dispatch_by_day
- route_lead_time
- expected_arrival_day
- supply_basis

其中：

`expected_arrival_day =
promised_dispatch_by_day + route_lead_time`

仅在固定 lead time 实验中成立。

它不是绝对保证到货时间。

`supply_basis` 至少区分：

`TRANSPORT_ONLY`

和：

`STOCK_CONFIRMED`

Round4B 正式多供应商匹配默认使用：

`STOCK_CONFIRMED`

Round4A S1 保留作为历史 control。

---

# Stage 8 — 本轮不引入价格

这点严格保持。

supplier offer 不包含：

- price；
- money；
- credit；
- discount。

因此本轮 matching 只研究：

**谁能供、多少、多久。**

不要为了“选择供应商”顺手引入价格。

价格留给后面的独立轮次。

---

# Stage 9 — 定义两个正式 Matching Policy

不要一次发明很多。

只比较：

## M0 — Primary Supplier Only

只使用 A。

即使 D known，也不使用。

这是多供应商 control。

## M1 — Bounded Sequential Matching

针对当前：

`open_procurement_need`

只在：

`known_supplier_ids`

中取得 offer。

排序规则固定为：

1. `expected_arrival_day` 更早优先；
2. 若相同，`max_acceptable_quantity` 更大优先；
3. 若仍相同，`supplier_id` 稳定字典序作为 deterministic tie-break。

然后顺序请求。

每得到一个 accepted quantity：

立即减少：

`remaining_need`

再访问下一个 supplier。

直到：

`remaining_need = 0`

或者已知候选耗尽。

因此不能：

先向 A 请求320，
又向 D 请求320，

最后两个都接受。

---

# Stage 10 — 全供应商统一采购去重

Buyer 的采购位置必须跨供应商统一计算。

对于 commodity coal：

`global_supply_position =
on_hand_at_B
+ sum(all coal in_transit to B)
+ sum(all live accepted coal pending across suppliers)`

然后：

`open_need =
max(0, target - global_supply_position)`

不得按供应商分别计算：

A缺320
D又缺320。

这是 Round4B 最重要的 correctness invariant 之一。

旧在途：

不管来自 A 还是 D，

都必须共同去重。

---

# Stage 11 — 被拒绝的数量可以转向下一供应商

M1 中：

A request 80

A accepted30
rejected50

那么：

remaining need = 50

随后可以向 D 请求50。

不是重新请求80。

D 最多只处理当前 remaining need。

必须保留：

原 A accepted30

与：

D accepted ≤50

的独立订单。

---

# Stage 12 — 不自动取消仍然有效的旧订单

Round4B 第一部分先研究：

**rejection fallback**

不是 aggressive switching。

只要 A 已经有：

live accepted pending

或者：

in_transit

这些数量继续参与全局去重。

即使 D 更快：

不能自动把 A 的订单删除然后再向 D 全量采购。

---

# Stage 13 — 第二个策略阶段：Confirmed Overdue Switching

在基础 M1 验证完成以后，增加：

## M2 — Confirmed Overdue Switch

只针对：

**已经明确 OVERDUE 的旧 pending**

且：

另一个 known supplier 当前存在正的 STOCK_CONFIRMED offer

时：

可以启动 Round4A 已有的：

cancel request。

但依然遵守：

**conservative replacement**

即：

取消未确认以前：

旧 pending 仍计入 global supply position。

只有：

cancel confirmed

以后释放的 confirmed quantity：

才重新成为 open_need。

然后才能向另一供应商发 request。

不得：

取消请求当天立即双订。

---

# Stage 14 — M2 不允许偷换 in-transit

如果 A 订单：

pending80

取消请求以后：

A 在确认前 dispatch30

那么：

只确认 cancel50。

这30：

继续作为 A→B in_transit。

向 D 最多替代：

50。

绝不能替代80。

必须使用 Round4A 已经验证的取消确认语义。

---

# Stage 15 — 正式场景矩阵

建议每组600日。

至少完成以下场景。

---

## A — Single supplier equivalence

D 存在于世界，

但：

`known_supplier_ids=[A]`

运行 M1。

必须与对应单供应商 S2 场景一致。

这证明：

“世界有D”

本身不会导致全知使用D。

---

## B — Both known, normal supply

Day1：

A、D 都 known。

正常 capacity。

比较：

M0 / M1。

观察：

是否只因为 D 存在就产生无意义分单。

不要写测试强迫 M1 只用A；根据实际 offer 排序决定。

---

## C — A capacity30 shock, D known from start

A：

Day50–79 capacity=30。

D 始终60。

A、D Day1 known。

比较：

M0 / M1。

观察：

A partial/reject 的剩余 need 是否流向 D。

实体结果是否变化由实验决定。

不要预设一定改善。

---

## D — A shutdown, D unknown forever

A：

Day50+=0。

D 实际存在且正常。

但 B 永远不知道 D。

M1。

预期：

不得使用 D。

这个结果应该接近单供应商断供。

---

## E — A shutdown, D discovered Day60

Day1–49：

A正常。

Day50起：

A capacity=0。

D正常。

但：

Day1–59：

known=[A]

Day60：

discover D

之后：

known=[A,D]

比较：

D unknown forever

与：

D discovered Day60。

要求 Day1–59 的所有：

request
offer
order
shipment
inventory
production
backlog

完全一致。

---

## F — A shutdown, D discovered Day90

与 E 相同，

只把 discovery 改成90。

用来验证：

发现时间本身会改变恢复路径，

而不是算法提前知道 D。

---

## G — A stockout but route healthy, D known

A：

route capacity100，

但明确构造：

on_hand=0
且当前没有可承诺库存。

D：

有真实库存与正常路线。

这是 Round4A 反证的多供应商版本。

要求：

A S2 offer=0

D 可以提供其真实 stock-confirmed offer。

M1 只能基于 offer 行动。

---

## H — Split fulfillment

构造：

open_need=100

A stock-confirmed offer=40

D stock-confirmed offer=60

验证：

总 accepted=100

且：

不超过任何供应商 offer。

---

## I — Combined supply insufficient

open_need=150

A offer40

D offer60

总共只能接受100。

剩余：

open_need=50。

不要创建假订单填平。

---

## J — Overdue switch

A 先真实接受一批订单，

随后其 route shutdown，

订单进入 OVERDUE。

D 已知且有 positive offer。

比较：

M1 不取消；

M2 confirmed overdue switch。

重点检查：

取消确认之前不能向 D 重复采购这批 quantity。

---

# Stage 16 — 不要做“搜索算法”

这一轮 supplier discovery 是明确事件。

不要把：

“世界存在的所有 supplier”

扫描一遍找最佳者。

不要实现：

- 商会；
- 报纸；
- 网络爬取；
- relationship discovery；
- search cost。

Round4B 只验证：

**已知候选集上的 bounded matching 与 switching。**

真正的 supplier search 可以另开后续轮次。

---

# Stage 17 — 不要加入 supplier reliability score

Round3 / Round4A 已经有 promise breach 事实。

但本轮不要马上压成：

`reliability=0.73`

然后参与排序。

保留原始可观察事实：

- accepted；
- breach；
- cancellation；
- delivery history。

Reliability aggregation 后面单独研究。

---

# Stage 18 — 供应商库存承诺 correctness

Stock commitment 必须检查：

`stock_committed_pending <= current_on_hand`

在同一结算阶段成立。

若实际 dispatch：

同时减少：

on_hand
和对应 stock commitment。

若 confirmed cancel：

只释放未发 commitment。

若 order 部分 dispatch：

只释放实际 dispatch 数量。

不得：

同一个库存单位被 A→buyer1 和 A→buyer2 重复承诺。

虽然当前正式 fixture 只有一个 buyer，也必须通过多个 request 专项验证。

---

# Stage 19 — Commodity ledger 扩展

新增 D 后 coal 数量账必须扩展。

原 coal identity 基础上加入：

- D initial coal；
- cumulative D extraction；
- D on_hand；
- D→B in_transit。

不能因为第二供应商加入就破坏：

coal residual=0。

所有旧 steel / machine identity 继续成立。

---

# Stage 20 — Future Information Isolation

继续做 prefix test。

两个世界：

Day1–99 完全相同。

例如：

世界1 Day100 discover D；
世界2 Day100 不 discover。

Day1–99 必须：

- known suppliers；
- offers；
- requests；
- accepted/rejected；
- stock commitment；
- cancel；
- shipment；
- inventory；
- production；

完全相同。

不得读取未来 discovery event。

同样测试：

Day100以后 D route capacity 才不同。

Day1–99 不能提前改变 offer。

---

# Stage 21 — 输出指标

每个场景至少输出：

## Information

- available_supplier_count
- known_supplier_count
- considered_supplier_count
- queried_supplier_ids
- discovery events

## Offers

按 supplier：

- max acceptable
- stock-confirmed ATP
- transport ATP
- stock commitment
- promised dispatch
- expected arrival

## Requests

按 supplier：

- requested
- accepted
- rejected
- partial / full reject

## Buyer aggregate

- global supply position
- open need
- total in_transit
- total live pending

## Supplier allocation

- quantity allocated to A
- quantity allocated to D
- supplier shares

## Switching

- overdue source supplier
- cancel requested
- cancel confirmed
- replacement supplier
- replacement qty

## Physical

- A extraction
- D extraction
- A→B dispatch/arrival
- D→B dispatch/arrival
- B steel
- C machine
- delivery
- backlog
- machine-days

## Performance

- offer evaluations
- candidate scans
- active requests
- active orders
- slot entries
- stock commitment entries
- runtime
- optional tracemalloc

---

# Stage 22 — 自动检查

至少增加以下 invariants：

1. unknown supplier 永远不能被 query。
2. world-available 但 unknown supplier 不影响轨迹。
3. discovery 前 prefix 与 unknown world 一致。
4. offer 不能读取未来 discovery/capacity。
5. stock-confirmed ATP 不超过未承诺 on_hand。
6. transport ATP 原约束继续成立。
7. 同库存不能重复承诺。
8. rejected quantity 不创建订单。
9. M1 每个后续 request 只能请求 remaining need。
10. 同一采购边界：
   `sum(accepted across suppliers) <= initial open_need`
11. 全供应商 in_transit 统一去重。
12. 全供应商 live pending 统一去重。
13. cancel requested 未确认前不能重复 replacement。
14. confirmed cancel 只能释放 pending。
15. old in_transit 永远不能切换/取消。
16. D 加入后 coal residual仍=0。
17. steel/machine residual仍=0。
18. 全订单 identity成立。
19. M0/single-known control 可复现对应旧行为。
20. 重复运行确定性一致。
21. 全部旧 baseline/Round2/Round3/Round4A 验证继续通过。

测试不要要求：

M1 backlog 一定比 M0 小。

也不要要求：

M2 一定比 M1 好。

这些都是实验结果。

---

# Stage 23 — Round4A 观察器历史扫描问题

Round4A 已经记录：

请求输出观察器会扫描完整历史请求，

累计形成二次复杂度。

Round4B 新实现不要继续复制这种模式。

对于新增 Round4B 输出，优先在 request / offer / discovery 创建时维护：

**当日事件列表或按日索引**

导出当天只读取当天事件。

不得为了这个目的修改经济结果。

如果可以用一个很小的 instrumentation-only 改动修正 Round4A 的历史请求扫描，也允许单独提交，但必须证明：

- 所有模型输出与旧结果一致；
- 只改变观察/导出成本；
- baseline hashes 在其适用政策下不被无关修改。

如果会扩大范围，则仅保证 Round4B 新观察器不再使用历史全扫描，并把旧问题继续记录。

---

# Stage 24 — 必须研究的失败模式

不要提前修这些：

## 1. Stock-confirmed ATP 过于保守

供应商明天会生产，

今天却拒单。

记录。

这将决定以后是否需要：

production-aware ATP。

本轮不要自动加入未来生产预测。

## 2. D 被发现以后仍不能救供应链

可能是：

- D capacity不足；
- D stock不足；
- lead time太长；
- old in-transit/pending占满 need；
- matching policy选择问题。

分解原因。

不要直接调参数。

## 3. Multi-supplier 导致库存 overshoot

重点检查：

是否是：

- 去重错误；
- cancellation waiting；
- 同日多 supplier request；
- stock commitment；
- delivery timing。

如果违反 invariant：

correctness defect。

如果账目正确，只是策略造成高库存：

策略结果。

## 4. M2 切换比 M1 更慢

允许。

确认取消等待本来就可能降低响应速度。

## 5. D unknown 时仍然被使用

这是 correctness defect。

必须修复。

---

# Stage 25 — 报告

生成：

`MULTI_SUPPLIER_REPORT.md`

至少回答：

1. available / known / considered supplier 是否真正分离？
2. D unknown 时有没有任何泄漏？
3. explicit discovery 后采购行为如何变化？
4. S2 是否修复了 Round4A “没货也接单”的反例？
5. stock commitment 是否避免同库存重复承诺？
6. A partial/reject 后 residual need 是否正确转向 D？
7. 两个 supplier 的 accepted 总量有没有超过真实 open need？
8. old in-transit 是否始终正确去重？
9. D discovery Day60 vs Day90 对实体恢复产生什么差异？
10. M2 confirmed switching 是否改善结果，代价是什么？
11. 是否出现库存 overshoot？如果有，是账目错误还是策略行为？
12. stock-only ATP 是否过于保守？
13. 是否已经需要 production-aware ATP？
14. 是否有必要下一步研究 supplier search / ranking？
15. 哪些机制仍然不能进入正式 WWO？

不要因为某场景改善：

就宣布多供应商算法正确。

---

# Stage 26 — 下一 Gate

Round4B 完成以后不要自动进入价格。

先判断应该去哪里。

可能的下一轮只能根据证据选择，例如：

**Round4C — Production-aware ATP**

如果 stock-only ATP 明显过度拒单；

或者：

**Round4C — Supplier Search / Information Acquisition**

如果 known-set matching 已经稳定，而真正缺的是如何发现 supplier；

或者：

**Round5 — Adaptive Pricing**

只有当物质采购网络已经足够稳定，且价格成为下一个明确缺口时。

不要提前决定。

报告必须基于结果给出推荐。

---

# Stage 27 — Git / PR

Round4B 完成后运行：

- verify_baseline
- verify_round3
- verify_round4a
- Round4B tests
- Round4B full experiment twice

建立少量清晰 commits。

push：

`research/multi-supplier-round4b`

创建独立 PR。

建议标题：

`Experiment with bounded multi-supplier matching and switching`

不要自动 merge。

PR body 必须写：

- Round4A baseline；
- stock-confirmed ATP；
- supplier D；
- known set；
- discovery；
- M0/M1/M2；
- scenario matrix；
- correctness；
- actual findings；
- performance；
- limitations；
- next-gate recommendation。

---

# Stage 28 — 本轮禁止

不要加入：

- price
- money
- credit
- banking
- household
- wage
- labor
- relationship scoring
- supplier reliability score
- stochastic supplier search
- global supplier scan
- demand forecasting
- full MRP
- securities
- WWO integration

不要创建：

EconomicRuntime

不要复制第二套 Simulation。

---

# Stage 29 — 最终反馈必须阶段化

最终报告：

### Stage 0 — Round4A baseline
DONE / PARTIAL / BLOCKED

### Stage 1 — Regression
DONE / FAILED

### Stage 2–3 — Stock-confirmed ATP gate
PASS / FAIL

### Stage 4–14 — Multi-supplier implementation
DONE / PARTIAL / BLOCKED

### Stage 15–24 — Experiments / correctness
DONE / PARTIAL / BLOCKED

### Stage 25 — Report
DONE / PARTIAL

### Stage 26 — Next Gate
明确写：

- 推荐 Round4C Production-aware ATP；
- 或 Supplier Search；
- 或 Round5 Pricing；
- 或暂不继续。

必须说明证据。

### Stage 27 — Git / PR
DONE / PARTIAL / BLOCKED

列出：

- main/base SHA
- tag
- branch
- commits
- PR URL
- CI

### Remaining Issues

只写真实剩余问题。

本轮完成以后停止。

不要自动进入下一轮。