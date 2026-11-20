你现在继续独立私有仓库：

`ryoumiyahayato/wwo-economy-lab`

实际推进：

**Round4C — Bounded Supplier Discovery & Search Scaling**
**有限供应商发现、信息获取与规模扩展实验**

这是一轮真实施工任务。

本轮目标不是证明当前经济模型正确，也不是继续把采购协议越做越深。

当前阶段的目标是：

> **扩大现有经济黑箱能够承载的世界规模、候选供应商数量和信息获取路径，为后续真正评估模型价值创造足够大的实验空间。**

本轮完成后，系统应该能够在：

- 世界里存在大量潜在供应商；
- 买方只知道其中很少一部分；
- 供应商可能位于不同区域、拥有不同 lead time / capacity / stock；
- 买方可以通过有限、有时延的信息渠道发现新的候选；
- matching 仍只作用于已知候选；
- 世界中大量未知或无关供应商不会每天参与采购计算；

的情况下稳定运行。

这仍然不是完整市场。

不要加入价格、货币、信用、工资、家庭或金融。

---

# Stage 0 — 冻结 Round4B 基线

先检查 PR #4：

`Experiment with bounded multi-supplier matching and switching`

如果：

- CI 全绿；
- PR head 仍然是已验证 Round4B head；
- mergeable / clean；
- 无 unresolved blocking review；
- 没有未经说明的新提交；
- 当前账号具有 merge 权限；

则直接合并 PR #4。

不要因为 PR OPEN 就停止。

合并以后：

1. 同步最新 main；
2. 运行全部已有验证；
3. 创建 annotated tag：

`economy-lab-v0.4b-multi-supplier`

建议 message：

`Verified Round4B bounded multi-supplier matching research baseline.`

4. 从最新 main 创建：

`research/supplier-search-round4c`

然后继续。

如果 Git smart HTTP 仍然失败但 GitHub API 可用：

继续使用已经验证的 API 发布方式，并核对本地/远端 commit/tree SHA。

GitHub 某一步失败只能阻塞对应 Git 操作。

只要已验证 Round4B baseline 能明确取得，就继续本地算法实验。

---

# Stage 1 — 完整回归

修改 Round4C 前实际运行：

- 原 8 项；
- Round2 9 项；
- Round3 18 项；
- Round4A 29 项；
- Round4B 33 项；
- `verify_baseline.py`
- `verify_round3.py`
- `verify_round4a.py`
- `verify_round4b.py`

记录：

- Python version；
- base commit；
- tag；
- branch；
- commands；
- exit codes；
- 各轮 summary SHA。

Round4C 功能关闭时：

所有旧行为继续成立。

不要修改旧实验结果迎合本轮。

---

# Stage 2 — Round4C 的概念边界

Round4B 已经区分：

`available supplier`

`known supplier`

`considered supplier`

`queried supplier`

Round4C 继续保留这个结构。

本轮增加：

`discoverable supplier`

以及：

`search result`

因此应有：

世界事实：

`available_suppliers`

↓

信息渠道允许找到：

`discoverable_suppliers`

↓

一次具体搜索返回：

`search_results`

↓

进入买方知识：

`known_suppliers`

↓

matching：

`considered / queried`

这几层不能合并。

---

# Stage 3 — 禁止 Global Supplier Scan

这是本轮最重要的规则之一。

买方不能：

```text
for supplier in all_world_suppliers:
    find best
```

任何 procurement / matching / decision 路径都不能扫描全部世界供应商。

世界级 supplier catalog 可以存在。

但它必须通过一个：

**Search / Directory Index**

提供有限查询。

例如：

`search(
 commodity="coal",
 origin=B,
 search_scope=LOCAL,
 result_limit=3
)`

返回最多3个 discoverable candidate。

matching 只处理已经返回并进入 known set 的候选。

---

# Stage 4 — 建立最小 Supplier Directory

不要建立完整商业数据库。

每个 supplier 的 directory entry 只暴露粗信息：

- supplier_id
- commodity
- region / search zone
- route_available
- nominal lead-time band
- advertised capacity band（可选）
- active / inactive
- discoverability channel

Directory 不暴露：

- 实时库存；
- 内部生产计划；
- 当前 stock commitment；
- 当前订单队列；
- 未来 capacity；
- ATP。

这些只有供应商在被真正 query offer 时才能返回。

---

# Stage 5 — 搜索范围

先建立三个抽象 search scope：

`LOCAL`

`REGIONAL`

`WIDE`

它们是实验层级。

不是正式国家市场。

例如可以通过 fixture 配置：

LOCAL：
只返回与 B 同 search zone 的 supplier。

REGIONAL：
包含邻近若干 zone。

WIDE：
包含当前实验世界允许进入远程搜索的 supplier。

不要实现：

NationalMarket
GlobalMarket

之类新的权威对象。

这些 scope 只是信息查询范围。

---

# Stage 6 — 搜索必须有时间成本

本轮不使用金钱搜索成本。

使用：

**information latency**

建议默认：

LOCAL：
1 day

REGIONAL：
3 days

WIDE：
7 days

买方在 Day t 发出 SearchRequest。

在：

`t + latency`

之前：

不能使用搜索结果。

SearchRequest 至少记录：

- search_id
- buyer
- commodity
- scope
- requested_day
- delivery_day
- result_limit
- status

结果交付时才把 supplier 加入 known set。

---

# Stage 7 — 搜索结果数量必须有界

默认：

`result_limit = 3`

不同实验可以用：

1 / 3 / 5

但不要大规模调参。

即使 WIDE scope 中有200个 supplier：

一次搜索仍最多返回 K 个。

因此 candidate matching 成本应该随：

**known / returned candidate**

增长，

而不是随：

**world supplier count**

直接增长。

---

# Stage 8 — Search Result 排序不能偷看实时经济状态

Directory search 可以依据稳定或粗粒度字段：

1. search zone / scope eligibility；
2. nominal lead band；
3. stable supplier ID tie-break。

不能依据：

- 当前真实库存；
- 当日 ATP；
- 当前订单队列；
- future capacity；
- 实际未来供货效果。

搜索只是：

“我找到谁”。

不是：

“系统替我知道谁现在最好”。

真正供货能力仍然必须通过 Round4B 的 SupplierOffer 查询。

---

# Stage 9 — 两种发现策略

本轮只比较两个。

## Q0 — Passive Knowledge

没有主动搜索。

known set 只包含初始已知 supplier 和 fixture 明确交付的信息事件。

作为 control。

## Q1 — Bounded Active Search

当：

`open_procurement_need > 0`

并且：

当前 known suppliers 的有效 offers 无法覆盖 need，

且：

当前没有同 commodity 的进行中 search，

则允许发起一次 search。

优先：

LOCAL

如果最近一次 LOCAL 已完成且仍不足，

下一次可以扩大到：

REGIONAL

再不足才：

WIDE。

不得同一天同时发 LOCAL + REGIONAL + WIDE 三次搜索。

---

# Stage 10 — 搜索不是每天重复

需要明确 search cooldown / knowledge memory。

本轮采用简单规则：

同一个：

buyer + commodity + scope

搜索完成以后：

默认30日内不重复同 scope 搜索。

已有 known supplier 不因为搜索结束而遗忘。

不要实现完整信息衰减。

如果 supplier 后来 inactive：

仍可保留“知道它存在”，但 offer 可以返回不可供应。

---

# Stage 11 — 扩大 Supplier Pool

Round4B 只有 A 与 D。

Round4C 建立可配置 supplier pool generator。

不要复制 Simulation。

创建同一种 coal supplier fixture。

至少支持：

- 2 suppliers
- 10 suppliers
- 50 suppliers
- 200 suppliers

所有 supplier 有：

- 唯一 supplier_id；
- 唯一 place/search zone；
- initial stock；
- production capacity；
- route capacity；
- lead time；
- directory metadata；
- independent source extraction ledger。

不要要求每一个 supplier 参数完全不同。

可以使用 deterministic pattern 生成。

例如按 ID 周期分配：

production:
20 / 40 / 60 / 80

route capacity:
20 / 40 / 60 / 100

lead:
2 / 4 / 6 / 8

但必须：

确定性；
配置可检查；
不依赖随机数才可复现。

---

# Stage 12 — 大量“睡眠供应商”必须不进入每日 matching

创建规模实验：

世界 supplier count：

10
50
200

buyer 初始只 known：

2

如果没有 active search：

每日 offer / matching candidate 数量必须保持接近 known set，

不能因为世界 supplier 从10变200就每天 query 200次。

记录：

- total world suppliers
- directory indexed suppliers
- known suppliers
- search candidates inspected
- offers queried
- matching candidates
- active orders

---

# Stage 13 — Directory Index

为了让规模实验有意义：

不要每个 SearchRequest 都线性扫描世界全部 supplier。

允许构建简单索引，例如：

`commodity -> scope/zone -> supplier ids`

目录构建时可以 O(N)。

但运行期 LOCAL/REGIONAL 查询应该只访问相应 bucket。

记录：

- index build visits
- query bucket visits
- returned results

不要为了200个 fixture 上数据库。

Python dict/list 即可。

---

# Stage 14 — 搜索信息与真实 offer 严格分离

一个 supplier 被 search 返回以后：

只能获得 directory information。

随后真正 matching 时：

才调用 Round4B offer。

因此可能出现：

搜索结果显示某供应商存在，

但真正 query 后：

ATP=0。

这是正确结果。

不要让搜索引擎提前过滤：

“现在没库存的供应商”。

否则搜索系统会泄漏实时内部状态。

---

# Stage 15 — 正式场景矩阵

每个正式场景默认600日。

至少执行：

---

## A — No shortage control

世界10个 suppliers。

buyer 初始知道 A 和 D。

A 足够正常供货。

Q0 / Q1。

Q1 不应该无理由不断搜索。

---

## B — Known suppliers insufficient

A、D 合计长期只能支持例如：

60 coal/day。

终端正常需要80。

世界中存在第三个可用 supplier E。

buyer 初始不知道 E。

比较：

Q0

和：

Q1。

观察：

搜索什么时候触发；
E什么时候进入 known；
什么时候第一次 query / dispatch / arrival；
服务是否变化。

---

## C — Unknown good supplier nearby

世界10个 supplier。

有一个 LOCAL scope 的 supplier E：

能力足够补缺。

buyer不知道。

比较：

Q0 / Q1。

---

## D — Only regional supplier can solve gap

LOCAL 中所有 candidate 能力不足。

REGIONAL 中存在一个有效 supplier。

验证：

Q1：

先完成 LOCAL，
发现仍不足，
再扩大 REGIONAL。

不能直接知道 regional supplier。

---

## E — Wide-only rescue

LOCAL / REGIONAL 都没有足够候选。

WIDE 才有。

观察信息延迟如何造成供应损失。

---

## F — Bad discovery result

Search 返回一个真实存在的 supplier，

但 query 时 stock ATP=0。

必须：

不产生虚假 accepted order。

buyer 在 cooldown / 下一阶段后仍可以继续搜索其他候选。

---

## G — World scale 10

10 supplier；
known 2；
正常运行。

---

## H — World scale 50

50 supplier；
known 2。

---

## I — World scale 200

200 supplier；
known 2。

比较 G/H/I：

没有搜索时：

每日 matching work 是否基本保持。

有一次 LOCAL search 时：

query work 是否与对应 bucket 大小有关，

而不是总 N。

---

## J — Discovery timing

使用同一个世界。

设置：

Q0 fixture information event Day60

对比：

Q1 active search。

不要预设谁一定更快。

比较实际：

- discovery day
- first dispatch
- first arrival
- backlog
- machine-days

---

# Stage 16 — Search Failure 必须是真实状态

Search 可以返回：

0 results。

例如 scope 内没有 supplier。

必须记录：

`SEARCH_COMPLETED_NO_RESULTS`

不能为了推进流程凭空返回世界其他位置的 supplier。

然后 Q1 才能根据规则扩大 scope。

---

# Stage 17 — Known Set 不自动等于全部 Search Results 永久可用

搜索结果加入 known。

但 offer query 仍可能：

- reject；
- inactive；
- ATP=0；
- route unavailable。

这不会把 supplier 从 known set 删除。

它只是：

当前不能供货。

不要在本轮建立复杂 supplier reputation。

---

# Stage 18 — 不加入价格

继续禁止：

price
money
credit

排序仍沿用 Round4B：

expected arrival
→ max acceptable
→ stable supplier id

本轮研究的是：

**谁能被发现，以及信息需要多久。**

不是“谁最便宜”。

---

# Stage 19 — 多供应商数量账继续成立

所有新 supplier 必须进入 coal ledger。

总 coal：

initial coal across all suppliers and B
+
cumulative extraction across all suppliers
-
coal consumed in steel

必须与：

all supplier warehouses
+
B coal
+
all coal in transit

一致。

不能为了200 supplier逐个手写 ledger。

建立通用 supplier collection 求和。

Round4C 功能关闭时旧 Round4B identity 结果必须保持。

---

# Stage 20 — 性能/规模指标

本轮重点不是追求绝对速度。

而是知道算法工作量跟什么增长。

记录：

- N world suppliers
- directory build visits
- directory buckets
- active searches
- query bucket visits
- search results returned
- known supplier count
- offers queried/day
- matching candidate visits/day
- active orders
- shipments
- runtime
- optional tracemalloc

重点回答：

当：

world supplier N = 10 → 50 → 200

但：

known supplier K=2

且没有 search 时，

matching work 是否更接近：

O(K)

而不是：

O(N)。

搜索发生时：

是否接近：

O(relevant bucket)

而不是每次 O(N)。

这不是要求数学证明。

用实际 counters 说明。

---

# Stage 21 — 不要现在做完全随机世界

所有规模世界 deterministic。

supplier parameters 使用固定生成规则。

不要引入随机 supplier birth/death。

不要引入随机搜索成功率。

黑箱现在需要：

可复现的大规模结构，

而不是随机噪声。

---

# Stage 22 — 自动检查

至少新增：

1. unknown supplier 不得 query。
2. search 未完成前 result 不得进入 known。
3. result 交付后才进入 known。
4. directory search 不读取 supplier real stock。
5. search 不读取 future capacity。
6. result_limit 生效。
7. no-result search 正确完成。
8. scope expansion 只能按 Q1 顺序发生。
9. cooldown 生效。
10. 同 scope 不产生重复进行中 search。
11. world N 增大但 known 不变时 matching query 数不随 N同比增长。
12. directory indexed query 不做每日全世界线性扫描。
13. discovered supplier offer 仍经过 S2 ATP。
14. ATP=0 supplier 不产生假 order。
15. accepted across suppliers 不超过 open need。
16. all in-transit 继续全局去重。
17. commodity residual=0。
18. order identities=0 residual。
19. future search result 不泄漏。
20. Day1–99 prefix worlds 保持一致。
21. 全部旧 Round2/3/4A/4B 验证通过。
22. 重复运行确定性一致。

---

# Stage 23 — 黑箱扩展专项

除了正式矩阵，增加一个：

**Black-box Extensibility Probe**

目标不是证明经济正确。

而是证明当前结构能表达更宽的情况。

至少构建：

- 5 commodities directory metadata
- 200 suppliers
- 10 search zones
- 1 buyer
- known suppliers 5
- active commodity 仍只有 coal

其他4种 commodity 暂时不实际生产交易。

它们只存在于 directory/index。

检查：

coal 搜索不会访问其他 commodity bucket。

这是为了证明：

未来扩商品数量时，

信息检索结构不是硬编码只支持 coal。

不要因此实现其他商品的完整生产链。

---

# Stage 24 — 再增加一个 Multiple Buyers Probe，但不要进入正式矩阵

为了测试延展性，而不是现在做完整市场：

增加一个非常小的结构探针：

2 buyers
3 suppliers
1 commodity

两个 buyer 分别拥有：

- 自己的 known set
- 自己的 search state

共享 supplier stock commitment。

只检查：

同一供应商库存不能被两个 buyer 重复承诺。

不要把第二 buyer 接入完整 B→C 生产链。

这是接口 probe。

不是正式多企业世界模拟。

如果这项需要复制整个 Simulation：

停止该 probe，记录结构限制。

不能为了 probe 建第二套世界。

---

# Stage 25 — 报告必须回答

生成：

`SUPPLIER_SEARCH_REPORT.md`

必须回答：

1. supplier discovery 是否真正从 fixture 单次事件扩展成 bounded search？
2. 世界存在 supplier 与 buyer知道 supplier 是否仍严格分离？
3. search latency 是否产生可观察的实体后果？
4. LOCAL/REGIONAL/WIDE expansion 是否正确？
5. search result 有没有泄漏实时库存？
6. 找到一个无库存 supplier 后发生什么？
7. 10/50/200 supplier 时：
   - matching work
   - search work
   - storage/build work
   分别怎样变化？
8. sleeping/unknown suppliers 是否影响正常 matching？
9. commodity directory 扩到5类以后是否仍然隔离？
10. 双 buyer probe 是否暴露 shared stock commitment 问题？
11. 现在这个黑箱能够表达哪些此前不能表达的场景？
12. 哪些仍然完全表达不了？
13. 是否已经具备进入“较大规模模型价值评估”的条件？
14. 下一轮应该：
   - 扩 buyer/network scale；
   - 做 production planning / demand propagation；
   - 做 production-aware ATP；
   - 还是开始 pricing？

不能因为测试都通过就回答“模型有价值”。

这里只判断：

**表达能力和实验空间是否足够扩大。**

---

# Stage 26 — Extension Gate

本轮最后给出：

`EXTENSIBILITY_GATE`

只能是：

PASS
或
FAIL

PASS 至少要求：

- 200 supplier fixture 可运行；
- unknown 不参与 daily matching；
- bounded search 可改变 known set；
- scope / latency 生效；
- search 不泄漏 real stock/future state；
- indexed search 不依赖每次全世界扫描；
- 多 commodity directory 不互串；
- shared supplier stock commitment 至少通过2-buyer probe或明确证明当前结构为什么不能安全支持；
- 所有数量账保持。

PASS 不代表：

经济算法正确。

它只代表：

**这个黑箱已经具有足够的延展性，可以进入更大规模、更复杂条件下的模型评估。**

---

# Stage 27 — Git / PR

完成后：

运行所有历史验证与 Round4C 两次完整 replay。

从：

`research/supplier-search-round4c`

提交少量清晰 commits。

创建 PR。

建议标题：

`Extend supplier discovery and bounded search for scalable experiments`

不要自动 merge。

PR body 必须写：

- Round4B baseline；
- directory/search；
- Q0/Q1；
- scope/latency；
- 10/50/200 scale；
- extensibility probes；
- correctness；
- performance counters；
- known limits；
- EXTENSIBILITY_GATE。

---

# Stage 28 — 明确禁止

本轮不要加入：

- price
- money
- credit
- banking
- wage
- household
- labor
- supplier reputation score
- random search
- demand forecasting
- full production planning
- full MRP
- stochastic shocks
- WWO integration

不要建立：

EconomicRuntime

不要复制第二套 Simulation。

---

# Stage 29 — 阶段反馈

最终必须报告：

### Stage 0 — Round4B baseline
DONE / PARTIAL / BLOCKED

### Stage 1 — Regression
DONE / FAILED

### Stage 2–10 — Search semantics
DONE / PARTIAL / BLOCKED

### Stage 11–24 — Scale & extensibility
DONE / PARTIAL / BLOCKED

### Stage 25 — Report
DONE / PARTIAL

### Stage 26 — EXTENSIBILITY_GATE
PASS / FAIL

明确说明依据。

### Stage 27 — Git / PR
DONE / PARTIAL / BLOCKED

列出：

- main/base SHA
- tag
- branch
- commits
- PR URL
- CI

### Remaining structural limits

只写真实限制。

### Recommendation

不要默认继续 Supplier Search。

根据实验结果明确推荐：

- 扩大多 buyer/network；
- 或回到 Production Planning / Demand Propagation；
- 或 Production-aware ATP；
- 或 Pricing；
- 或先修结构 blocker。

本轮完成后停止。

不要自动开始下一轮。