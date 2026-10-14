# Round5 — Demand Propagation & Production Planning

本轮实际建立Demand → ProductionPlan → MaterialRequirement → ProcurementNeed →
原supplier offer/matching → PurchaseRequest。52×600日、四个通用接口probe与三个固定
E17信息诊断已运行。40项实现检查与双次完整784文件复现由`verify_round5.py`协调。
**PLANNING_EXTENSIBILITY_GATE=PASS**限定于所列表达和实现约束，不证明经济模型正确。

默认H10的Wide末backlog为P0/P1/P2/P3：**1282/1282/3/1268**。P3能区分到货日期，
却没有因此改善远途服务；P2的改善伴随更大的实际供给暴露与中间库存，不应正式采用。
下一轮优先修**计划释放日期/滚动窗口与采购可执行性之间的planning blocker**，不默认
扩大产业网络、ATP或价格。这个功能表达Gate通过，与候选策略不成熟可以同时成立。

## 基线、输入和实际验证

PR #5的head仍是`02e654f82a764589cb5b9cd4847f9b821789f2e1`，两项CI SUCCESS，
MERGEABLE/CLEAN，无review/thread或新增提交，账号ADMIN。按本轮授权合并于
2026-10-07T10:01:24Z。真实main/base：`366fe77704ee3d4ec9088ba1c544c46096289e40`。
签名commit object和tree与本地核对后同步；没有force push。

Annotated tag `economy-lab-v0.4c-supplier-search`，对象
`0c0e1f21843c4f21c0d86a7a35cdac25b63c79f1`指向该main，message：
`Verified Round4C bounded supplier discovery and search scaling baseline.`
分支`research/demand-planning-round5`由此建立。Python3.12.14标准库，实际执行器为
`C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`。

用户明确指定附件保存在`inputs/ROUND5_REQUEST.md`，仅规范化CRLF→LF；原hash、
规范化hash、commands、平台、exit code、tag及base在`evidence/provenance.json`和
pre/post验证记录。首次旧wrapper开始时还在已验证PR5 head，同步签名merge object后
继续；二者tree完全相同。全部post验证使用合并后的树。原156来源hash保持。

```sh
python verify_baseline.py --output-dir .local/round5-pre
python verify_round3.py --output-dir .local/round5-pre
python verify_round4a.py --output-dir .local/round5-pre
python verify_round4b.py --output-dir .local/round5-pre
python verify_round4c.py --output-dir .local/round5-pre
# 修改后再次运行以上五条，输出目录为.local/round5-post。
python economy_quantity_lab/planning_round5/run_demand_planning_experiment.py --output-dir .local/round5-release --execution-log .local/round5-release-execution.json
python verify_round5.py --output-dir .local/round5-release-validation
```

原8、Round2 9、Round3 18、Round4A 29、Round4B 33、Round4C 32项修改前后通过。
Windows旧105/139输出直接匹配，34份生成JSON仅按现有LF兼容政策匹配；Linux CI仍
要求139直接字节匹配。Round3/4A/4B/4C各两次59/44/115/184文件直接复现。

| Summary | SHA-256 |
|---|---|
| Round2 | 02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02 |
| Round3 | 070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae |
| Round4A | 7522b9313a1aa47c60943029c4aff3f8869657f67c98d11502a1d064e1249b55 |
| Round4B | afccc372d5ec721a31b3a39f507ce65f0eb1e73e6e791cd231aabc2048e1897f |
| Round4C | 37624a453a9563da0732fde9b13f5c81a58b3c9b3f7e69a0f7a30328cfab0f8a |
| Round5 | 4841f66e3eebe6773f77fe25edb5606030668e4c357b4ebf77fb43984a9acf77 |

旧源码、fixture、target、配方、CSV、报告不修改。统一入口保留失败日志，不刷新
历史manifest。完整新档案约517.5MB，进入忽略目录/CI artifacts；Git保存summary、
784文件hash manifest、selected daily、诊断、probe、命令/验证及修正缺陷证据。

## 事实、计划、需求、请求的分离

Demand是当天真正收到的terminal order；backlog不删除。CurrentDemandFeed属于世界
fixture，只在原step已经前进到当天后交付该日事实。为了step-up/down，在check_accounts
中仅把原`day×constant demand`检查适配为累计实际已收到订单；原商品账仍执行。
真实需求恒等式始终为received_total=delivered+backlog。

DemandHistory保存最多20个已观察日，包括当日已经收到的订单，冷启动除以实际观察天数。
不预填未来20日，不读取interval结束日来计划。未来fixture留在世界服务，计划层只使用
已收到事实、stock、live pending/shipments、当前公开offer与过去的observed rate。

ProductionPlan有producer/commodity/decision date/production date/stable ID、desired、
capacity-limited、basis、horizon、unmet字段。计划不修改需求、stock、shipment或产出累计。
计划行的unmet是desired与capacity-limited的未安排量；到期后的实际投入不足缺口另在
deviations的unmet_planned_output中记录，不把两种缺口混为已发生的生产事实。
每个采掘producer也有每天一条LEGACY_SOURCE_STOCK_TARGET计划及实际量记录；它们仍
采用旧stock-target extraction，不把需求传播layer冒充production-aware supplier ATP。
MaterialRequirement由RecipeGraph系数生成，带commodity/quantity/need-by/source plan ID。
净采购需求再经过已知supplier公开S2 offer、原shared slots/stock admission成为请求与接受
订单。terminal backlog没有直接写coal order，库存target也没有冒充terminal demand。

P0调用完整旧production/procurement；新增观察不改轨迹。旧Normal/Wide控制逐行、
events、requests、offers与search events比较；Wide600日仍1282。P1只把当前backlog扣掉
当前machine库存，规划一天并受C capacity限制。投入由machine recipe再传播steel recipe。
P1当天需求在production时已经消耗或过期，缺少未来需求窗口，采购仍主要依赖原安全库存。

P2的总machine候选量为backlog+observed_rate×H−current machine stock。它按日均匀
整数分摊，C总量≤C capacity×H；B的需求组合包含下游steel缺口及已接受steel订单与原
B steel operating target，取MAX避免重复。B也按日粒度leveling并受B capacity×H约束。
这不是完整MRP或求解器，不保证所有下游日期可行。Gross材料来自受产能限制的计划，
投入缺货不会把gross悄悄改成实际可生产量。实际量另由当前可用投入限制后交给原produce。

P3使用相同observed basis/计划分摊，但覆盖分配按ETA。On-hand当前可用，已发cargo
按真实ETA；accepted pending按明确dispatch deadline+route lead。无promise或已违约且
尚未发出的余额保持真实ledger，但不声称其可及时到货。`scheduled_supply_before`与
allocation检查证明同样320总位置可以只有120覆盖Day+2、其余200要到Day+8。

## 时间边界、分配与采购暴露

计划日期是t…t+H−1。原日序仍为receive→demand→同一pre-production状态生成计划→
produce→terminal delivery→procure→FIFO dispatch。C当天只能使用已经到C仓的steel；
B当天新产钢不能穿越transport lead直接供给当天C。C投入need-by反向扣B_C真实lead，
早于今天的上游机会记为missed deadline，不允许回填历史production。

原target B coal320/C steel120与B steel operating target40保持。采购组件为safety gap，
加上未与其重叠的plan gap；因此total=max(safety,net plan)，不是简单相加。由于计划
覆盖未来日期，实际C库存/管线仍可能超过旧120；“target未改”不等于物资占用没有增加。

PlanningAllocations只看active日期需求与live供给，按日期一次分配每个supply余额。
稳定ID形如B:coal:日期；跨日修订与原decision date版本分别归档。已接受数量还保存
order↔requirement link。到货转换为on-hand覆盖；确认取消才释放真实采购链接；
dispatch转为实际cargo。到期记录planned/allocated/consumed/expired-unfulfilled，不销毁
未用库存。日初requirement快照、日末allocation快照和真实consumption归档分开。

**修正过的correctness defect：** 初稿将已过期需求关联的采购余额视为自由量，P3滚动
窗口反复购买，Wide/steel bottleneck/physical shortage钢pending达到17000/17960/17750。
这是重复承诺缺陷，不是有益策略。本轮修正为：真实未结采购始终占用该producer/material
的有限需求组合，即使它无可信ETA。新采购不能再次承担已经存在的数量暴露；但这些
余额仍不被标成timely coverage。对这三个600日场景加入回归。修正后Wide P3 H10期末
steel pending508、最大steel position540，而及时投入缺口仍存在。没有加任意order cap、
调target或改supplier能力；边界来自active gross requirement、已有余额和真实产能。

在此简化下，失去时间承诺的采购暴露可能压住替代请求；模型还没有完整的重排/取消/计划
释放机制。这是可观察的策略限制，需要研究，不把无ETA余额伪装成满足早期需求。

## 正式52×600日：真实结果

A–J各P0/P1/P2/P3共40；另恢复4；Normal/Wide对P2/P3的H5/H20共8。正式总31200日。
I/J使用充足的显式有限煤库存100000/源及真实200/日开采/运力，不制造无限资源。
H只有A/D线路合计60 coal/日，其余物理supplier线路关闭；不假装unknown也提供暗中供给。

| 场景 H10 | P0末backlog | P1 | P2 | P3 |
|---|---:|---:|---:|---:|
| A Normal10 | 0 | 0 | 0 | 0 |
| B Step-up10→15 Day100 | 1223 | 1223 | 6 | 6 |
| C Step-down15→5 Day100 | 0 | 0 | 0 | 0 |
| D Spike15 Day100–119 | 0 | 0 | 0 | 0 |
| E 原Wide | 1282 | 1282 | 3 | 1268 |
| F Long lead8，无发现问题 | 2960 | 2960 | 4 | 2960 |
| G Short30 lead2+Long100 lead8 | 1835 | 1835 | 3 | 1832 |
| H Physical supply60 | 1462 | 1462 | 1450 | 1450 |
| I C capacity8 | 1200 | 1200 | 1200 | 1200 |
| J B steel capacity30 | 1475 | 1475 | 1468 | 1468 |
| Temporary shutdown50–79，恢复 | 0 | 0 | 0 | 0 |

P1在正常条件不比旧策略差，但在Wide/long/mixed/step-up保留旧缺口，符合其故意的一日
视野。P1 plan/requirement是真实分离的信息，不意味着单看committed backlog就能预备管线。

P2/P3在step-up Day99 observed10；Day100收到15后才变10.25，Day119才15。C实际
output从10变11，再至15。最终6 backlog因为正常新需求已占满C15能力，无法再提供额外
清积压流量；流量15并不等于旧backlog恢复。所有候选99日前缀一致。

Step-down Day100 observed14.5，Day119为5。P2/P3当天仍production15，之后为消化已建
machine库存会低于需求：Day119产2，Day139回到5。machine库存峰50；Spike峰30，
相比P0/P1没有machine缓冲。这是过去窗口滞后与已有管线/库存的结果，商品账全部平衡。
Spike backlog峰P0/P1为20、P2/P3为6，不能据此正式选用P2。

## Wide反事实与P3失败原因

旧legacy煤position=320把长途在途与短期可用量混在一起，补到target就open_need0。
末200日P0 backlog>0且该need=0共200日，E有库存/offer却只得到少量采购。
P2由未来已观察run-rate窗口生成更多投入责任，即使旧safety gap=0仍有plan增量；
接受更多物资进入真实运输与生产，因此缺口明显缩小。不是改320或凭空生产。

正式fixture的能力、lead、初始库存、目录、scope/latency和搜索规则保持。Q1触发仍由
当前unmet need决定，所以候选改变need后会内生改变信息时点：P0/P1 E17 known，P2/P3
H10 E12 known。这不应忽略。三个额外600日诊断固定被动E17，仅隔离信息时点：
P1/P2/P3末backlog1282/2/1270；物理Wide参数不变。P2改善主要仍存在，不只是早五日发现。

P3对lead8 supplier使用原offer最迟到达t+2+8=t+10。H10最后日期是t+9，因此**没有一个
新计划投入日期能由这份报价覆盖**，远途采购主要仍限于safety组件。后来实际货物可能
提前dispatch并在t+8到达，其真实ETA会进入覆盖，但报价阶段不能借实际未来发运冒充
更早承诺。只让所有timely gap触发新订单会重现重复承诺；本轮保留及时缺口并限制真实
采购暴露，没有调报价或horizon掩盖它。Mixed lead同样保留可早到部分与晚到部分差异。

| Wide sensitivity | P2末backlog | P3末backlog |
|---|---:|---:|
| H5 | 857 | 1272 |
| H10默认 | 3 | 1268 |
| H20 | 0 | 0 |

H20提供远途报价可覆盖的计划日期，并增加实际在途/库存需求；不是“20为最佳经济常数”。
H5不足，H10对P3报价边界不足。P2只看总量有明显服务改善，但不能保证任何need-by可行。
P3时间表达正确也不保证有可执行的短窗口采购方案。

恢复场景backlog峰260/260/190/190，连续20日清零窗口首日135/135/125/125。
所有策略都实际使用过C15；P2/P3既尝试高于正常10清backlog，也在冲击前建立更多缓冲。
因此十日差不能只归因于恢复后计划。P2/P3最大C steel320，旧仅80，必须计入占用代价。

物理60 coal/日只有7.5 machine/日，不论planner如何传播都仍积压；I的C8使每日至少2
需求无法服务，末1200。J steel30使终端约7.5，末1468等仍有缺口。上游gross受cap限制，
煤仓/position不随无限终端backlog无限增长，B/C的capacity shortfall与INPUT_SHORTAGE分列。
煤仍可能被库存政策囤在B：J P2/P3 max B coal420/400，这是有限多余占用，不是修复瓶颈。

## 接口延展性与性能

五commodity阶段g0→g1→g2→g3→g4，用同一RecipeGraph四条转换；final3向上得到
6/12/24/48，并逐层扣日期。Branching final4产生input_A8、input_B12两个独立需求。
两个output共用raw：gross8+12，stock10总计只分配10。两terminal sinks7+9合计16，
再从同一graph传播并分配。没有复制第二Simulation或真实多企业网络，这些是接口probe。

Normal P2 H5/H10/H20，600日edge traversals为6000/12000/24000，B/C传播plan records同数；
加上十个采掘producer逐日记录，总plan records为12000/18000/30000。
max active requirements为8/18/38，allocation candidate visits74539/163668/362754。
DemandHistory最多20日；计划与需求按decision day/absolute requirement ID索引；supply读取
live active orders/active shipments，不扫描订单、shipment或需求历史档案。禁止历史orders
iteration的guard测试通过。但coverage是active requirements×live supply的嵌套分配，不能
将总planning cost只宣称为edges×H。重复reconciliation也有成本，尚未做复杂增量优化。

一次实际52案construction/simulation/planning/observation/archive约63.437秒，文件导出
不计；硬件/同时运行验证会影响耗时。完整档案517513082字节，保留每次滚动计划版本，
档案规模近似days×H，物理world row另随supplier N增长。另测两个tracemalloc案例，
日CSV与未追踪运行直接字节相同；日志为`evidence/memory_log.json`，这不是RSS。
Normal P2 H10峰43321753 bytes；Wide P3 H10峰49799564 bytes，含档案、索引与观察。
不把文件体积当内存峰值，也不把小Lab时间推广为全球性能。

40项检查覆盖所有请求的correctness类别，加上观察开关、图循环拒绝、及时供给函数、
原step/FIFO继承、按历史archive禁止迭代、整数分摊不是产能shortfall，以及已修正的滚动
重复采购缺陷。计划与实际有独立记录：INPUT_SHORTAGE、CAPACITY_LIMIT、NO_DEMAND、
PLAN_NOT_DUE、MATCHED。未观察到其他fixture原因时不伪造原因记录。非到期计划不能
被输出成实际0产出失败；真实未消耗需求到期单独归档。

所有已运行coal/steel/machine residual和order residual为0；计划不能修改库存/物资累计
的pure-layer检查通过。这只支持这些结算约束，不证明需求行为或经济真实性。

## Gate、剩余限制与下一轮

PLANNING_EXTENSIBILITY_GATE **PASS**：当前终端事实可逐层传播、recipe-driven、产能
约束、日期与ETA分离、稳定ID和真实采购暴露去重、safety/plan分解、四项通用probe、
全量商品/订单账及未来需求前缀隔离均通过。它表示可表达更完整生产因果链，允许后续
扩大网络做模型价值测试；不代表现在应该采用P2/P3。

P1仍短视；P2将run-rate需求量转成更多实际缓冲，反应滞后并忽视日期；P3有限窗口与
保守报价不能支持长lead的可执行计划。B采用简单leveling，没有保证C每个日期的上游
可行性。真实跨企业排队/多buyer拥塞、订单重排与计划释放、额外产业网络、工厂日历、
batch/setup均未实现；共享输入probe不代表正式多企业生产账已接入。

因此下一轮最值得先研究**planning blocker：滚动计划释放/日期可行性与已承诺采购的
协调**。H20恰能服务不等于通过调H修复H10，也不能先扩大网络复制现有时序问题。
随后才评估多企业网络或更真实production scheduling。现有供应商库存/ATP足够但请求
日期不兼容，尚无证据优先production-aware ATP；价格/household consumption也无法
替代这个已观察到的缺口。本轮不自动开始下一轮，不接入WWO。
