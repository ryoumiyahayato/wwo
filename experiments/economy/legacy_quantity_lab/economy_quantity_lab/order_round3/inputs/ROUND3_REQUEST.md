# WWO Economy Lab Round3 — Order Commitment & Disposition Experiment

你现在继续独立私有仓库 `wwo-economy-lab` 的经济算法研究。

本轮不是 WWO 正式经济开发，也不是继续调 H1 缓冲参数。目标是研究 Round2 暴露出的一个明确问题：

> 一张已经被供应商接受、但长期尚未发运的采购订单，在真实订单账中仍然存在；但它是否仍应被采购决策视为“可信的近期供给”？

Round2 已经证明：持续停运时可以出现 `on_hand=0`、`in_transit=0`、`pending_dispatch=320`、`inventory_position=320`，从而阻止继续补货。当前模型没有取消、转单、催发或多供应商处置机制。

本轮只研究“订单承诺—逾期—处置”语义。不要加入价格、资金、家庭、工资、银行、股票、多供应商或正式 WWO 集成。

---

## 0. Git 前置条件

先读取根目录 `AGENTS.md`、`BASELINE.md` 和适用的仓库说明。

确认 PR #1 `Bootstrap verified economy quantity lab baseline` 已经合并到 `main`。

如果 PR #1 尚未合并：
- 不要把 Round3 继续堆到 bootstrap 分支；
- 不要擅自合并 PR #1；
- 停止实现，报告当前阻塞和建议操作。

如果 PR #1 已合并：
1. 确认 `main` 指向已合并基线；
2. 如果 `economy-lab-v0.2-baseline` annotated tag 尚未存在且当前权限允许，基于合并后的 main 创建该 tag；若权限不允许，只记录建议，不伪称创建成功；
3. 从最新 main 创建：
   `research/order-commitment-round3`

不得直接在 main 施工，不 force push，不改写 baseline 历史。

---

## 1. 保护现有基线

本轮开始前实际运行当前统一验证入口和现有测试。

至少确认：
- 原 8 项测试；
- Round2 9 项测试；
- 现有 200 日实验；
- 现有 33×600 日 Round2 实验；
- `verify_baseline.py`。

记录实际 Python 版本、命令、退出码和关键 hash。

Round3 完成后，旧 baseline 行为必须继续成立。

特别要求：
- Round3 功能关闭时，旧 139 份正式输出必须保持原有兼容政策下的一致；
- 不修改原 fixture、H0、H1、Round2 report 和已发布结果来让新实验通过；
- 不复制第二套 `Simulation`；
- 不重写 production / dispatch / arrival / quantity ledger。

如果发现现有 baseline 已经失败，先单独定位，不静默修算法。

---

## 2. 本轮要正式区分的三个量

继续保留真实订单账和 Round2 的库存位置：

`ledger_inventory_position = on_hand + in_transit + pending_dispatch`

这是“已经拥有 + 已经发出 + 已被供应商接受但尚未发出”的事实账。

新增一个只用于实验性采购决策的：

`effective_supply_position`

它不是权威库存，也不能覆盖、删除或改写真实订单余额。

Round3 至少比较：

### R0 — Legacy
全部 `pending_dispatch` 仍 100% 计入决策：

`effective_supply_position = on_hand + in_transit + pending_dispatch`

这必须复现旧行为。

### R1 — Promise-filtered
仍未逾期的 pending 计入；已经逾期的 pending 不计入“近期可信供给”：

`effective_supply_position = on_hand + in_transit + pending_not_overdue`

真实账目中的 overdue pending 仍然存在，不能因为决策不再相信它就凭空消失。

### R2 — Cancel-and-reorder
订单逾期后，允许对尚未发出的余额执行显式取消，然后按同一补货目标重新下单给同一个供应商。

取消只能作用于 `pending_dispatch`：
- 已经 `in_transit` 的数量不能取消；
- 已经 delivered 的数量不能取消；
- 部分发运订单只能取消剩余 pending 部分。

这是实验性、即时被供应商接受的取消语义，不声称等同于现实合同法或 WWO 最终规则。

R2 的目的不是“让供应链恢复”，而是检验：
- 显式取消能否保持订单恒等式；
- 取消再下单是否只是重新排队；
- 在供给能力没有恢复时，是否仍然无法创造物资；
- 临时冲击恢复以后，其结果与 R0/R1 有何差异。

不要为了让 R2 好看而给它优先队列。

---

## 3. 订单承诺必须是明确事实，不允许从等待时间偷偷猜 ETA

新增 Round3 sidecar commitment metadata，优先不要破坏原 Order 序列化。

每张新采购订单在“供应商接受”时可以得到：

- `accepted_day`
- `promise_window_days`
- `promised_dispatch_by_day`

本轮先采用简单、明确的实验假设：

`promised_dispatch_by_day = accepted_day + promise_window_days`

默认：
`promise_window_days = 2`

它表示供应商在接受订单时明确承诺“最迟在该日结束前发出尚可承诺的订单部分”。

这不是由未来真实运输能力推导出的 ETA，也不是算法偷看 future shock。

如果场景明确配置为“无承诺”：
`promised_dispatch_by_day = null`

则这笔订单不能仅因年龄变大被标记 overdue。

### overdue 定义

若某订单存在明确 `promised_dispatch_by_day`，则：

- 在 promise day 日末仍存在 `pending_dispatch > 0` 时，promise 当天仍记为 due；
- 从下一天开始，这部分未发余额记为 overdue；
- 部分发运后，只对剩余 pending 数量判断 overdue。

记录：
- `pending_promised_qty`
- `overdue_pending_qty`
- `oldest_overdue_days`
- `promise_breach_order_count`
- `promise_breach_qty`

不要为 pending 伪造 shipment ETA。

`in_transit` 仍只来自已经实际 dispatch 的 shipment，并继续使用真实 ETA。

---

## 4. 最小实现边界

优先新增独立 Round3 目录，例如：

`economy_quantity_lab/order_round3/`

建议包含：
- `order_commitment.py`
- `run_order_commitment_experiment.py`
- `test_order_commitment.py`
- `ORDER_COMMITMENT_REPORT.md`
- 结果目录/manifest
- 打包或复现脚本（如现有项目风格需要）

`order_commitment.py` 中应尽量放纯函数或小型 sidecar 状态：

- promise metadata 建立；
- overdue 分类；
- effective supply position 计算；
- disposition decision；
- 取消数量校验。

不要让策略函数接收整个 Simulation 后任意读取内部状态。

如果 R2 必须修改核心订单余额，允许对原 Simulation 做**最小、可关闭、默认不改变旧行为**的扩展，例如：
`cancel_pending(order_id, quantity)`

但必须满足：
- legacy runner 不调用它；
- 旧输出字段不被无关新增字段改变；
- baseline 模式下字节/兼容 hash 保持；
- 不复制一套订单引擎。

如果可以使用 sidecar 记录 `cancelled_by_order_id` 而不破坏旧输出，优先这样做。

---

## 5. 订单恒等式升级

对 Round3 启用取消的场景，明确检查：

`ordered_quantity = pending_dispatch + in_transit + delivered + cancelled`

其中：
- `cancelled` 只能累加，不能减少；
- 取消时必须从 pending 同量扣除；
- 不得取消超过 pending 的量；
- 不得让取消产生或销毁 shipment；
- 不得把 cancelled 重新算入物质数量账；
- 如果被取消后重新下单，新订单必须有新的 order_id，不得复活旧订单余额。

Legacy / R0 场景在 `cancelled=0` 时必须退化成原恒等式。

商品数量守恒仍沿用原 coal / steel / machine 逐日恒等式。

---

## 6. 补货目标本身不要再调参

Round3 固定使用已经存在的 H1：

`target = 80 × (lead_time + 2)`

即 buffer_days=2。

本轮重点不是比较 H0/H1。

为避免把问题混在一起：
- A→B 正常 lead_time 使用 2 日；
- 正常 target = 320；
- C 的 steel 规则保持旧 fixture；
- production recipe、capacity、阶段顺序保持不变；
- terminal demand 仍为 10 machine/day。

除非作为明确的 control，不再大规模扫 buffer 和 lead time。

---

## 7. 实验矩阵

所有场景使用同一初始 fixture，默认运行 600 日。

至少完成以下场景。

### A. Normal baseline
A→B capacity 始终 100。
promise_window_days=2。

分别运行：
- R0 legacy
- R1 promise-filtered
- R2 cancel-and-reorder

预期不是要求“三者一定完全相同”，而是检查：
- 正常供给下是否几乎没有 promise breach；
- Round3 机制是否在正常条件下无理由制造大量取消/补单；
- R0 必须复现原 baseline。

如果正常供给也频繁逾期，先解释阶段顺序与 promise 定义是否不合理，不要直接调宽 promise window 掩盖问题。

### B. Temporary capacity shock
保持 Round2 shock：
- day 1–49: 100
- day 50–79: 30
- day 80+: 100

R0/R1/R2 全部运行。

观察：
- 首次 promise breach；
- overdue 数量轨迹；
- effective position 与 ledger position 的分离；
- R1 是否产生额外订单；
- R2 取消和重新排队规模；
- backlog 峰值和清零；
- 物质恢复、订单恢复与服务恢复的差异。

### C. Sustained shutdown
- day 1–49: 100
- day 50+: 0

R0/R1/R2 全部运行。

这是关键负向实验。

必须允许出现：
- R0 卡在旧 pending；
- R1 因不再相信 overdue pending 而不断出现新补货需求；
- R1 的订单队列可能增长；
- R2 反复取消/重订；
- 三者都无法恢复物质供给。

如果 R1 或 R2 在没有运输能力的情况下恢复生产，优先视为严重 correctness defect，查明是否凭空产生物资或绕过 capacity。

### D. Temporary full shutdown then recovery
- day 1–49: 100
- day 50–79: 0
- day 80+: 100

R0/R1/R2 全部运行。

这个场景用于区分：
- “识别旧承诺失效”
与
- “真的存在恢复后的运输能力”。

观察 R1/R2 是否在恢复后因为额外排队或取消重排反而延迟恢复，或者产生过量到货。

### E. No-promise control
选择 Temporary shock 与 Sustained shutdown，各运行一次“无明确 promise”的控制。

要求：
- `promised_dispatch_by_day=null`；
- 不得仅根据订单年龄自动 overdue；
- 不得偷偷套 `accepted_day + 2`；
- R1 在无 promise 时应明确采用规定的 fallback。

本轮 fallback 定义为：
**没有明确承诺的 pending 继续按 legacy 计入 effective position。**

这样可以证明 overdue 语义来自显式承诺，而不是从年龄推断。

---

## 8. R1 必须允许暴露“补单爆炸”而不是提前修掉

R1 在 sustained shutdown 中很可能出现：
- 旧订单逾期；
- 被排除出 effective position；
- 新订单补到 target；
- 新订单后来再次逾期；
- 再次触发新订单。

不要提前给它加复杂抑制器。

这正是本轮要观察的候选缺陷。

记录：
- total_ordered
- active_pending
- overdue_pending
- new_order_qty/day
- order_count
- max supplier queue
- eventual overstock after recovery（若发生）

如果 R1 订单量爆炸，这是有效实验结果，不要为了通过测试把它限制住。

测试只应要求账目正确、无未来信息、无负数、无凭空物资，不要求 R1 表现“良好”。

---

## 9. R2 也不要预设为正确

R2 每次取消 overdue pending 后重新下单给**同一个供应商**。

因此它可能：
- 只是在 FIFO 队列里把自己移动到队尾；
- 在持续停运时完全无效；
- 在恢复后改变发运顺序；
- 减少旧订单年龄，但没有改善实体供给；
- 因取消时点而产生不同的恢复路径。

全部保留并解释。

不要给重订订单任何隐形优先权。
不要因为“这是 replacement”就越过其他 pending。

---

## 10. 信息边界

Round3 决策可使用：
- 本企业 on_hand；
- 本企业已知订单状态；
- 供应商明确给出的 promise；
- 已 dispatch shipment 的真实 ETA；
- 当前日已知的线路 capacity；
- 已批准的正常计划 80 coal/day；
- 当前 lead_time。

不得使用：
- future shock start/end；
- 未来 capacity；
- 未来实际 production；
- 未来 shipment；
- “实际上 day80 会恢复”之类 scenario truth。

增加 prefix equivalence 检查：

建立两组在 day 1–99 完全相同、day100 以后不同的场景。
要求 day1–99 的：
- promise；
- overdue；
- disposition；
- orders；
- inventory；
- production；
- shipments；
完全相同。

---

## 11. 结果指标

每个场景至少输出：

### 真实账
- on_hand
- in_transit
- pending_dispatch
- delivered
- cancelled
- ledger_inventory_position

### 承诺/决策账
- promised_pending
- overdue_pending
- effective_supply_position
- promise breach count / quantity
- oldest overdue age

### 行动
- new order qty
- cancelled qty
- reorder count
- cumulative ordered
- cumulative cancelled

### 实体结果
- coal arrivals
- B steel production
- C machine production
- terminal deliveries
- terminal backlog
- machine-days
- peak backlog
- final backlog

### 恢复
继续使用事先定义的 20 日连续窗口，分开报告：
- 生产恢复；
- 交付恢复；
- backlog 清零；
- pending/overdue 恢复；
- 仓内库存恢复；
- 在途恢复。

不要把平均产量恢复等同于 backlog 清零。

---

## 12. 必须有的自动检查

至少新增：

1. Legacy R0 复现原 Round2 对应场景。
2. promise day / overdue 边界：promise day 日末仍是 due，下一日才 overdue。
3. 部分发运只使剩余 pending 进入 overdue。
4. 无 promise 不按年龄自动 overdue。
5. R1 只改变决策中的 effective position，不改 ledger pending。
6. R2 只能取消 pending，不得取消 in_transit/delivered。
7. Round3 订单恒等式含 cancelled 后每天成立。
8. 商品数量残差仍为 0。
9. sustained shutdown 下 R1/R2 不得恢复物质生产。
10. future-info prefix equivalence。
11. 观察/诊断开关不改变 R0 实体轨迹。
12. 重复运行确定性一致。
13. baseline verify 仍通过。
14. legacy 输出兼容政策仍满足。

测试不得断言“R1 一定比 R0 好”或“R2 一定更快恢复”。

---

## 13. 报告要回答的问题

`ORDER_COMMITMENT_REPORT.md` 必须明确回答：

1. “accepted pending order”在当前模型中究竟代表什么？
2. 显式 promise 加入后，什么时候第一次能区分“订单仍存在”和“近期供给已不可信”？
3. R1 在 temporary shock 下有没有改善物质服务？代价是什么？
4. R1 在 sustained shutdown 下是否导致订单膨胀？速度和规模如何？
5. R2 的取消重订有没有真正改善供给，还是只改变队列/账龄？
6. 恢复以后有没有出现过量到货、重复采购或库存高于目标？
7. 哪些现象证明“识别承诺失效”不等于“存在替代供给”？
8. 哪些结果只是当前单供应商、即时取消、固定 promise window 的实验后果？
9. 是否已经有足够证据进入“多供应商发现与切换”研究？
10. 如果没有，缺的最小机制是什么？

不要把：
- 测试通过；
- 数量残差 0；
- 某策略 backlog 更小；
写成“经济算法正确”。

---

## 14. 性能边界

继续记录实验用时、活动订单数量和最大队列长度。

本轮特别关注 sustained shutdown 下 R1 是否导致活动订单数量增长。

如果活动订单扫描复杂度明显随历史总订单增长，记录出来。

不要因此立刻做大型性能重构；先证明问题。

不把小型 Lab 耗时推广为 WWO 全球性能结论。

---

## 15. Git / PR

Round3 实际完成后：

1. 所有旧测试和新测试通过；
2. 实际运行全部 Round3 场景；
3. 生成 report、summary 和必要 evidence；
4. 更新研究边界文档，但不要改写 `inventory-round2-2026-10-07` 的历史事实；
5. push：
   `research/order-commitment-round3`
6. 创建独立 PR。

PR 标题建议：

`Experiment with order commitments and overdue disposition`

PR 正文必须区分：
- 新增的事实/观察语义；
- R0/R1/R2 三个候选；
- 实际场景与结果；
- correctness checks；
- 没有实现的东西；
- 是否建议继续 Round4。

不要自动 merge PR。
不要创建“正式经济规则”tag。
只有审查后才能决定是否接受 Round3 的任何候选。

---

## 16. 本轮禁止

不要加入：
- 第二煤矿 / 第二供应商；
- supplier search；
- 价格；
- 金钱；
- 信用；
- 仓储成本；
- household；
- wage / labor；
- 银行；
- 股票；
- demand forecast；
- stochastic disruption；
- WWO 正式集成。

不要重构整个 repo。
不要重新实现一套 Simulation。
不要为了漂亮结果调 promise window。

---

## 17. 最终回复

最终回复给出：

- 实际基线 commit / tag；
- Round3 branch；
- 修改/新增文件；
- 实际命令；
- 原测试、新测试结果；
- 场景数量与运行日数；
- 关键结果表；
- 数量和订单恒等式结果；
- sustained shutdown 下订单队列结果；
- 是否发现 correctness defect；
- PR URL（若真实创建）；
- CI 状态（若真实获取）；
- 仍然缺失的机制；
- 是否建议进入 Round4 多供应商实验，以及依据。

失败或无法执行的部分如实说明。
本轮完成后停止，不自动继续 Round4。
