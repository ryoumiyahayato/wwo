# 当前研究边界

Round2历史基线仍由`BASELINE.md`和`docs/source_manifest.json`定义。156个来源
文件及139个输出的校验政策不变；`economy-lab-v0.2-baseline`指向实际合并main
`60278ee7f1703ef5aec6cb7933a2bcf6073e1038`。

Round3仅在`economy_quantity_lab/order_round3/`增加明确承诺、派生promise_status、
可信供给过滤与即时接受的未发余额取消实验。固定target320、时延2、buffer2。
不修改原Simulation、生产、运输、fixture、H0/H1或Round2结果。

R0保留事实账采购；R1只过滤决策；R2在原B采购边界取消逾期未发余额，再向同一个
供应商FIFO尾部新订。真实订单恒等式增加cancelled，商品账不计取消。C steel规则
保持原样，其承诺仅观察。没有实现合同协商或异步取消确认。

实际14×600日结果并未改善物质服务。持续停运R1队列551张、未发58720；R2累计
取消58400、期末未发320，却同样停产。R1/R2均未获准作为正式规则。

详见`economy_quantity_lab/order_round3/ORDER_COMMITMENT_REPORT.md`。进入完整
多供应商发现/切换前，需要明确已知可履约候选、拒单/承诺数量、取消确认和旧在途
去重语义。未实现任何第二供应商、资金/价格/金融或WWO运行时集成；不自动开展Round4。

Round3 PR #2已按本轮明确授权合并，main为`42e2ad240716901b6ec0684f3ec4abbe0dc9be31`，
annotated tag为`economy-lab-v0.3-order-commitment`。上述Round3即时取消仍是冻结的
历史研究假设，不因Round4A的确认握手而被重写。

Round4A在`supplier_round4a/`比较S0全接受与S1运输ATP，10×600日，另有取消专项。
拒单保留为open need；只接受量创建订单。共享承诺槽不生成货物；原FIFO真实发运。
取消默认一日确认，确认前pending及旧在途继续去重。五组实体轨迹相同，S1减少
坏承诺但未创造运力。缺货探针显示运输ATP不能保证企业可供货。
29项契约及历史复现支持研究Gate PASS，见SUPPLIER_ADMISSION_REPORT.md；
尚未批准策略正式采用。本轮没有第二供应商，也不自动开始Round4B。

Round4A PR #3已合并，main为`307df8f4d64dc039e2d291082394178c1d556a58`，
tag为`economy-lab-v0.4a-supplier-admission`。Round4B只在新multi_round4b目录
扩展当前库存承诺、固定D煤来源、已知集合M0/M1/M2及显式发现，未改历史来源。
确认取消前跨供应商pending/在途统一去重。原step/FIFO/receive仍继承，D开采
通过独立来源hook计入原商品账。新增观察按日索引，不改Round4A的历史输出。
14×600日及33项检查支持本轮实现契约；报告推荐后续Supplier Search / Information
Acquisition，尚未实现真正搜索、价格、可靠性score或WWO集成，不自动进入下一轮。

Round4B PR #4已按新授权合并，main `be9dfd54999ff156e5881b501118a53f151d68c8`，
tag `economy-lab-v0.4b-multi-supplier`。Round4C在search_round4c增加粗目录索引、
有界Q0/Q1和时延/冷却，supplier pool到200；全部历史来源保持不变。
生产/物质账复用旧核心并附加独立煤源，采购与全局去重不扫world，matching只用known。
物理世界与全量档案仍有N成本。五commodity只有目录扩展；双buyer只验证共享库存接口，
不能声称第二生产消费链已运行。18×600日、32项及双184文件复现支持Extension Gate PASS，
不支持经济真实性。Wide场景已知正offer却backlog1282，报告推荐下一轮研究需求传播/规划，
不默认加深搜索、引入价格或接入WWO。
# Round5增量边界

复用原Simulation结算；只有当前需求注入、生产计划选择与采购需求使用新的实验层。
Demand/Plan/MaterialRequirement/ProcurementNeed/accepted Order有独立事实与决策记录。
P2/P3过去20日run-rate不是未来真值；P3的及时覆盖与未结采购暴露分开。旧target保持，
未来投入计划仍可能形成更大的实际库存。发现滚动需求过期后重复采购的缺陷已修正并
加入600日回归。五阶段、branching/shared-input/multi-sink均为接口probe；物理网络仍是
原B/C链，不声称已经完成多企业网络、排程优化、production-aware ATP或经济真实性验证。

## Round5B boundary

Round5 is merged and tagged; its P0–P3, fixtures and evidence remain immutable.
Round5B adds dated execution buckets and an informational projected tail on the same world.
X1/X2 resolve the Wide H10 release boundary but retain step-up backlog141, H20 oscillations,
and physical bottlenecks. Confirmed disposition changes exposure, never goods.
The four-lead and five-stage probes exercise interfaces; they are not four new physical
suppliers or a settled multi-firm network. Steel still uses the original S0 admission.
EXECUTABLE_PLANNING_GATE supports further Multi-Firm Production Network research only.
No price, finance, households, optimizer, full scheduler or WWO integration is approved.

## Round6 boundary

Round5B is merged/tagged. Opt-in generic recipe and multi-sink orchestration hooks reuse one
original inventory/order/FIFO/receive authority. Formal coal and steel share S2 admission;
FirmNode plans use only own facts and addressed public requests. Shared seller/good stock
commitments and explicit C0/C1 contention are tested in actual multi-buyer worlds.
The 600-day legacy compatibility controls retain old P3/S0 explicitly; they are not evidence
that the formal local-plan/S2 trajectory equals the old central-plan/S0 trajectory.
24 networks include bounded-degree S5/S10 for600days; 50 checks and two371-file exact replays
support NETWORK_EXTENSIBILITY_GATE only within tested goods, recipes and scales.
ID starvation, pro-rata distribution costs, production bottlenecks and fixed sink topology
remain. Known-edge decisions avoid supplier all-pairs; world ledgers and archives still cost.
Pricing / Market Clearing is recommended as a future comparison question, not implemented
or approved here. No next round, household, finance, scheduler rewrite or WWO integration.
