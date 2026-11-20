你刚才完成的是 **Round3 的再次验证**，不是本次要求的 Round4A。

Round3 已经验证充分。本次不要再把“重新运行 Round3 → 报告 Round3 状态”当作任务完成。

现在从当前状态继续实际推进：

**Round4A — Supplier Admission & Available-to-Promise**
**供应商接单能力、承诺数量、拒单与取消确认实验**

除非遇到真正会破坏基线的 correctness blocker，否则不要中途停止询问用户。

---

# Stage 0 — 先结束 Round3 PR 生命周期，然后继续施工

当前已知：

- PR #1 已合并；
- main = `60278ee7f1703ef5aec6cb7933a2bcf6073e1038`
- `economy-lab-v0.2-baseline` 已存在；
- Round3 PR #2 OPEN；
- Round3 CI 已绿；
- Round3 本地验证再次通过；
- Round3 branch 工作区干净。

现在实际检查 PR #2：

- CI 是否仍全部成功；
- 是否 mergeable；
- 是否存在 conflict；
- 是否有 unresolved blocking review；
- PR head 是否仍为已验证 Round3 head；
- 是否存在用户没有说明的新提交。

如果这些均正常且当前账号具有 merge 权限：

**直接合并 PR #2。**

PR #2 OPEN 本身不是停止条件。

不要再次回复：

“PR #2 未合并，所以我停止。”

合并以后：

1. 同步最新 main；
2. 运行：
   `python verify_baseline.py`
   `python verify_round3.py`
3. 确认合并后仍然通过；
4. 基于合并后的 main 创建 annotated tag：

`economy-lab-v0.3-order-commitment`

建议 message：

`Verified Round3 order commitment and disposition research baseline.`

5. 创建分支：

`research/supplier-admission-round4a`

然后立刻进入 Stage 1。

如果 Git smart HTTP 仍失败，但 GitHub API 可写：

可以继续使用此前已验证的方法，通过 GitHub API 完成 merge / branch / commit / PR 操作，并核对本地和远端 Git object SHA。

只有权限不足、CI 失败、merge conflict 或 PR head 与已验证输入不一致时，才阻止对应 Git 写操作。

即使 GitHub 某项操作受阻，只要已验证代码基线仍可明确取得，也继续完成本地 Round4A 实验，并在最后报告 Git blocker。

---

# Stage 1 — Round4A 的研究问题

Round3 已经证明：

1. accepted pending order 是真实订单事实，但不是实际货物；
2. promise breach 能区分“订单仍存在”和“近期履约已不可信”；
3. R1 排除 overdue pending 会产生重复采购承诺膨胀；
4. R2 向同一个供应商取消再重订不会创造新供给；
5. 单供应商断供时，R0/R1/R2 实体轨迹完全相同。

因此 Round4A 不再研究：

“买方如何反复处理已经坏掉的订单。”

本轮研究：

> **供应商收到 Purchase Request 时，是否应该无条件把全部请求变成 Accepted Order？**

正式区分：

`PurchaseRequest`

与：

`AcceptedOrder`

---

# Stage 2 — PurchaseRequest / AcceptedOrder 分离

增加明确的采购请求对象或 sidecar 表示。

至少包括：

`request_id`
`buyer_id`
`supplier_id`
`commodity`
`requested_quantity`
`request_day`

供应商处理 request 后产生：

`accepted_quantity`
`rejected_quantity`
`acceptance_day`
`rejection_reason`
`promised_dispatch_by_day`

必须每天检查：

`requested_quantity = accepted_quantity + rejected_quantity`

规则：

- 只有 accepted_quantity 创建真实 Order；
- rejected 不创建 pending；
- rejected 不进入 shipment；
- rejected 不进入 inventory position；
- accepted=0 时不创建 quantity=0 的假订单；
- partial acceptance 必须允许。

---

# Stage 3 — 比较两个 admission 策略

只比较：

## S0 — Legacy Auto Accept

保持旧行为：

`accepted_quantity = requested_quantity`

这是 Round3 legacy control。

## S1 — Bounded Admission / Available-to-Promise

供应商根据自身当前可承诺发运能力计算：

`available_to_promise`

然后：

`accepted_quantity = min(requested_quantity, available_to_promise)`

`rejected_quantity = requested_quantity - accepted_quantity`

允许：

- full accept；
- partial accept；
- full reject。

本轮不要增加第三个 admission 策略。

---

# Stage 4 — ATP 先只研究运输发运承诺

本轮不要直接做完整企业未来生产预测。

默认：

`commitment_horizon_days = 2`

如果订单接受日是 t：

可承诺 dispatch window 为：

`t`
`t+1`
`t+2`

供应商只能使用**当前已经知道的线路 capacity**。

不能读取未来 scenario capacity。

定义实验性：

`gross_dispatch_commitment_capacity
 = current_known_capacity × (commitment_horizon_days + 1)`

然后扣掉已有仍有效的 promise slot 占用。

剩余才是：

`available_to_promise`

这里是实验候选，不是 WWO 正式 ATP 规则。

---

# Stage 5 — Commitment Slot 必须真实占位

不能让每张新订单都独立看到完整 capacity。

建立轻量 promise slot schedule。

按 future dispatch day 维护：

`slot_capacity`
`committed_quantity`
`remaining_slot`

按 earliest-slot-first 给新 accepted quantity 分配。

例如当前 capacity=30：

t：30
t+1：30
t+2：30

已有承诺：

30 / 20 / 0

那么剩余：

0 / 10 / 30

新 request 最大只能再承诺40。

必须增加自动检查：

**同一天的总 promised dispatch 不得超过 admission 时所使用的 slot capacity。**

promise slot 只代表承诺。

实际 shipment 仍必须经过原 Simulation 的真实 dispatch。

不得直接从 promise 生成 shipment。

---

# Stage 6 — Promise Quantity 明确化

S1 中：

`promised_quantity = accepted_quantity`

因为本轮的假设就是：

> 供应商只接受自己认为能在 commitment horizon 内发出的数量。

不要增加：

“接受但不承诺”

这一额外状态。

Legacy / no-promise control 可以作为对照存在，但 S1 正常流程必须：

accepted → explicit promise。

---

# Stage 7 — Buyer Open Procurement Need

新增：

`open_procurement_need`

固定仍使用现有 H1 target：

`target = 320`

计算：

`open_procurement_need =
max(
  0,
  target
  - on_hand
  - in_transit
  - live_accepted_pending
)`

重要：

- purchase request 本身不降低 need；
- rejected 不降低 need；
- accepted pending 才降低 need；
- in_transit 继续去重；
- delivered 已进入 inventory，不重复计；
- confirmed cancelled 不再计 live accepted。

这一步必须把：

“我想买多少”

和：

“别人真的答应供应多少”

彻底分开。

---

# Stage 8 — Cancellation Handshake

Round3 R2 的取消是即时生效。

Round4A 不再允许这个假设作为未来切换基础。

新增：

`CANCEL_REQUESTED`

`CANCEL_CONFIRMED`

默认：

`cancel_confirmation_delay = 1 day`

Day t 买方请求取消后：

订单 pending 仍存在。

在确认之前：

它继续进入 live accepted pending。

也就是说：

**取消尚未确认时，买方不能假定那批货已经绝对不会来。**

---

# Stage 9 — 取消等待期间可能继续发货

确认取消时必须重新读取当前订单状态。

例如：

原 pending = 80

买方请求 cancel 80

确认前 supplier 实际 dispatch 30

那么确认时：

最多只能：

`cancel_confirmed = 50`

30 已经是 in_transit。

绝不能再取消。

记录：

`cancellation_requested_qty`
`cancellation_confirmed_qty`
`cancellation_no_longer_cancellable_qty`

最后一个量表示：

请求取消时想取消，但确认前已经发出的数量。

它不是商品损失。

---

# Stage 10 — Order Identity

继续保持：

`ordered_quantity =
pending_dispatch
+ in_transit
+ delivered
+ cancelled`

`CANCEL_REQUESTED`

只是 pending 的状态标签。

不能作为独立 quantity bucket 再加一次。

只有 cancel confirmed 后：

pending → cancelled。

---

# Stage 11 — Conservative Replacement

本轮明确使用：

**保守替代采购规则。**

取消请求未确认：

旧 pending 仍计入 live accepted pending。

因此不能因为刚请求 cancel，就立刻把同一数量重新采购。

只有取消确认以后：

confirmed cancelled quantity

才重新进入 open procurement need。

本轮不要增加 aggressive overlap。

那留给未来独立实验。

---

# Stage 12 — 实验矩阵

所有正式场景默认600日。

仍然只有一个供应商。

不要加入 Supplier D。

至少执行：

## A Normal

capacity 始终100

S0 / S1

观察：

- request；
- accepted；
- rejected；
- ATP；
- promise；
- breach；
- backlog。

---

## B Temporary capacity 30

Day1–49 = 100
Day50–79 = 30
Day80+ = 100

S0 / S1。

重点观察：

capacity 已经降到30以后，S1 对新请求实际接受多少、拒绝多少。

---

## C Sustained shutdown

Day1–49 = 100
Day50+ = 0

S0 / S1。

这是最重要场景之一。

capacity=0 后：

S1 的 ATP 应变成0。

新的 request 应被明确拒绝，而不是继续无限制造 accepted pending。

买方允许长期存在：

`open_procurement_need > 0`

这是正确结果。

如果没有运输能力时 S1 仍然恢复物质生产：

作为 correctness defect 排查。

---

## D Full shutdown and recovery

Day1–49 = 100
Day50–79 = 0
Day80+ = 100

S0 / S1。

观察：

- shutdown 时 request/reject；
- recovery 后重新接受；
- promise breach；
- old pending；
- open need；
- physical recovery。

---

## E Steady overload

terminal demand 改为：

15 machine/day

对应正常需求：

60 steel/day
120 coal/day

保持：

A→B capacity = 100/day。

因此实体运输最多支持约12.5 machine/day。

S0 / S1。

这个场景不是要求系统满足15。

恰恰用于观察：

**当真实长期需求超过供给能力时，供应商是否仍然无限承诺。**

终端 backlog 增长可以是正确结果。

---

# Stage 13 — Partial Acceptance 专项测试

必须构造确定性例子：

requested=80

ATP=50

结果：

accepted=50
rejected=30

只创建 quantity=50 的 Order。

检查：

`80 = 50 + 30`

rejected=30 保留为 buyer open need。

---

# Stage 14 — Slot Overcommit 专项测试

至少构造连续多个 request。

确认同一 future dispatch day：

所有承诺总量不能超过 slot capacity。

禁止出现：

request1 承诺100
request2 又承诺100

但线路当天只有100。

---

# Stage 15 — Cancellation Handshake 专项实验

至少四个案例：

### C1

pending80
请求取消80
确认前未发货

结果：

confirmed_cancel=80

### C2

pending80
请求取消80
确认前发出30

结果：

confirmed_cancel=50
30仍为in_transit

### C3

cancel requested 尚未 confirmed

buyer 不得把80全部重新计入 open procurement need。

### C4

cancel confirmed 后

对应 confirmed quantity 才重新进入 open need。

---

# Stage 16 — Future Information Isolation

建立两个场景：

Day1–99 完全一样。

Day100 后不同。

要求 Day1–99：

- requests；
- admission；
- ATP；
- slot assignment；
- accepted；
- rejected；
- cancellation；
- open need；
- shipment；
- production；

全部相同。

S1 不能看到 future capacity。

---

# Stage 17 — 结果指标

至少输出：

## Request / Admission

- request_count
- requested_qty
- accepted_qty
- rejected_qty
- acceptance_ratio
- partial_accept_count
- full_reject_count

## Supplier ATP

- ATP
- total slot capacity
- slot committed
- slot remaining
- promised qty
- breach count
- breach qty

## Buyer

- on_hand
- in_transit
- live accepted pending
- open procurement need

## Cancellation

- cancel requested
- cancel confirmed
- no-longer-cancellable
- confirmation delay

## Physical

- dispatch
- arrival
- steel production
- machine production
- delivery
- backlog
- machine-days

## Performance

- active requests
- active orders
- slot entries
- scan visits
- runtime
- optional tracemalloc

---

# Stage 18 — Correctness Tests

至少包含：

1. S0 能复现 Round3 对应 legacy。
2. request = accepted + rejected。
3. rejected 不创建 Order。
4. partial acceptance 正确。
5. ATP 不为负。
6. promise slot 不超卖。
7. S1 不读取未来 capacity。
8. capacity=0 后新 request 可 full reject。
9. rejected 不进入 inventory position。
10. rejected 保留为 open procurement need。
11. accepted 才降低 open need。
12. cancel request 不改变 quantity ledger。
13. cancel confirmed 才 pending→cancelled。
14. 已经 dispatch 的数量不能取消。
15. cancel waiting 期间不会重复替代采购。
16. old in_transit 始终去重。
17. 商品 residual=0。
18. order identity residual=0。
19. baseline/Round2/Round3 全部继续通过。
20. 重复运行确定性一致。

不要写：

`S1 backlog < S0`

这不是 correctness invariant。

---

# Stage 19 — 不要提前修的结果

如果出现以下情况：

## S1 大量 reject

保留。

它可能只是诚实暴露供应不足。

## Open need 很大

保留。

只有一个供应商而且无法履约时，本来就应该出现。

## Promise breach 仍然较多

记录。

这可能说明仅用 dispatch capacity 做 ATP 不够，将来需要 supplier inventory / production ATP。

本轮不要立刻扩完整 MRP。

## Steady overload 下 backlog 无限增长

如果物质供给本身小于需求，这是合理结果。

不要调参把它消掉。

---

# Stage 20 — 报告

生成：

`SUPPLIER_ADMISSION_REPORT.md`

必须回答：

1. 原 auto-accept 为什么会把采购需求直接变成供应承诺？
2. request/order 分离后有什么变化？
3. 正常条件下 S1 表现怎样？
4. capacity30 下 accepted/rejected 分别怎样？
5. capacity0 后是否停止制造无限 accepted pending？
6. rejected demand 最终落在哪里？
7. ATP/promise 相比 Round3 是否更有信息价值？
8. 是否出现 overcommit？
9. steady overload 如何暴露真实长期能力不足？
10. cancel handshake 是否防止未确认取消后的重复采购？
11. old in-transit 是否正确去重？
12. 哪些问题仍然需要 supplier production/inventory ATP？
13. 是否满足进入真正两供应商实验的 Gate？

---

# Stage 21 — Round4B Gate

只有下列全部成立，才建议下一轮进入：

**Round4B — Multi-Supplier Discovery, Matching & Switching**

要求：

- request/accepted/rejected 明确；
- partial accept 正确；
- supplier 不无限 auto-accept；
- promise slots 不超卖；
- cancel request/confirm 已分离；
- cancel 未确认不重复采购；
- in-transit 去重正确；
- rejected quantity 形成 open need；
- future information isolation 通过；
- 所有 quantity/order identities 正确。

如果 correctness 有 blocker：

Gate FAIL。

如果只是 S1 的经济效果不理想，但账目正确：

报告策略缺陷，再判断是否值得增加第二个 admission candidate。

---

# Stage 22 — Git / PR

完成后：

运行：

- verify_baseline
- verify_round3
- Round4A tests
- Round4A full experiment reproduction

从：

`research/supplier-admission-round4a`

提交少量清晰 commit。

创建独立 PR。

建议标题：

`Experiment with bounded supplier admission and confirmed cancellation`

不要自动 merge Round4A PR。

PR body 必须写明：

- Round3 baseline；
- request/order split；
- S0/S1；
- ATP；
- commitment slots；
- cancellation handshake；
- scenario matrix；
- correctness；
- actual findings；
- limitations；
- Round4B Gate PASS/FAIL。

---

# Stage 23 — 明确禁止

本轮不要增加：

- 第二供应商；
- supplier discovery；
- supplier search；
- supplier ranking；
- price；
- money；
- credit；
- warehouse cost；
- relationship；
- household；
- wages；
- bank；
- stock；
- demand forecasting；
- stochastic shock；
- WWO integration。

不要建立第二套 Simulation。

不要建立 EconomicRuntime。

---

# Stage 24 — 最终反馈必须阶段化

最终必须回答：

### Stage 0 — Round3 merge/baseline
DONE / PARTIAL / BLOCKED

### Stage 1 — Regression verification
DONE / FAILED

### Stage 2–11 — Admission semantics
DONE / PARTIAL / BLOCKED

### Stage 12–19 — Experiments & tests
DONE / PARTIAL / BLOCKED

### Stage 20 — Report
DONE / PARTIAL

### Stage 21 — Round4B Gate
PASS / FAIL

解释具体依据。

### Stage 22 — Git / PR
DONE / PARTIAL / BLOCKED

列出：

- base commit
- tag
- branch
- commits
- PR URL
- CI status

### Remaining issues

只列真实剩余问题。

### Recommendation

只回答：

**下一轮是否应该进入 Round4B。**

不要再次把“Round3 又验证了一遍”作为本轮完成条件。

本轮必须实际产生 Round4A 实现和实验结果，或者明确指出一个真正阻止 Round4A 实现的 correctness blocker。