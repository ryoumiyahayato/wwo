# Round6 — Multi-Firm Production Network & Shared Scarcity

本轮把物理模型扩为同一世界中的多个企业，而不是复制 A/B/C 链条。正式网络中 coal/steel
都通过 S2 接受订单，库存承诺跨买方共享；各企业用自己的请求观察、订单、库存、产能和
知识形成 X1 计划。24 个网络场景各 600 日，另有两个旧单链兼容 control 各 600 日、
六个实际 12 日共享承诺专项及 100 日结构探针。

**NETWORK_EXTENSIBILITY_GATE = PASS**，仅指所测结构与实现约束支持继续做较大网络研究。
它不批准 C0/C1/X1，不证明经济真实性，不代表任意网络或任意配方已经验证。

推荐下一方向为 **Pricing / Market Clearing 的最小比较实验**。稀缺资源总量相同时，
排序与比例规则显著改变企业连续生产和最终服务分布；当前没有支付能力、价值或竞价事实
提供竞争依据。这里只提出下一轮研究问题，本轮没有加入价格或启动下一轮。

## 基线、命令与来源

PR #7 的已验证 head 为 `8550b5a5d4c11edbe8af70f51b469d59a4c323bf`。
两个 CI SUCCESS、MERGEABLE/CLEAN、无 review/review thread 阻塞、账号 ADMIN，确认三笔
既有提交没有变化后实际合并。main/base 为 `48b280a37be8f5fd72f0c277f4ae435e675efa1f`。
annotated tag `economy-lab-v0.5b-executable-planning`，tag object
`4278bdf49ade09f417393a7914d9a79851b4d082`；研究分支
`research/multi-firm-network-round6` 从该 main 创建。合并和 tag 的 API 对象与本地 Git
对象经过 SHA/父提交/tree 核对；没有改写历史。见 [baseline audit](evidence/baseline_audit.json)。

Windows 11、Python **3.12.14**。施工前后分别实际运行以下七个入口，全部 exit 0；
214 项历史检查（8+9+18+29+33+32+40+45）及历史完整实验均通过。

```text
python verify_baseline.py --output-dir .local/round6-pre
python verify_round3.py --output-dir .local/round6-pre
python verify_round4a.py --output-dir .local/round6-pre
python verify_round4b.py --output-dir .local/round6-pre
python verify_round4c.py --output-dir .local/round6-pre
python verify_round5.py --output-dir .local/round6-pre
python verify_round5b.py --output-dir .local/round6-pre
# 施工后相同七个命令，output-dir 改为 .local/round6-post
python economy_quantity_lab/network_round6/run_multi_firm_experiment.py --output-dir .local/round6-release --execution-log .local/round6-release_execution.json
python economy_quantity_lab/network_round6/evidence/derive_evidence.py --results .local/round6-release
python verify_round6.py --output-dir .local/round6-check
```

统一入口内部的测试/重放命令、实际解释器绝对路径、cwd、exit code 与时间保存于
[provenance](evidence/provenance.json) 及十四份 `historical_pre/post_*.json`。
`verify_baseline.py` 包含原 200 日、Round2 33×600 日及 17 项检查。
156 份原来源文件 hash 不变；本机 Round2 输出 105/139 直接字节一致、34 份 JSON 仅按
既有 LF/CRLF 政策比较，CSV 不使用该宽限。后续历史轮次均直接字节一致。
CI 的 Linux baseline 使用 `--strict-bytes`。

| 历史 summary | SHA-256，施工前后相同 |
|---|---|
| Round2 | `02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02` |
| Round3 | `070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae` |
| Round4A | `7522b9313a1aa47c60943029c4aff3f8869657f67c98d11502a1d064e1249b55` |
| Round4B | `afccc372d5ec721a31b3a39f507ce65f0eb1e73e6e791cd231aabc2048e1897f` |
| Round4C | `37624a453a9563da0732fde9b13f5c81a58b3c9b3f7e69a0f7a30328cfab0f8a` |
| Round5 | `4841f66e3eebe6773f77fe25edb5606030668e4c357b4ebf77fb43984a9acf77` |
| Round5B | `8768ac91cdd7db8eee354f1cd0591808e7ee4fff1e89637c990af8bf8e338016` |

Round6 summary SHA-256 为
`c7ea27cec28caa2215e392e4e9e9e0a2483706d061e49f1c346c636d54131b82`。
来源 manifest 为 `febc3a75ed159645787b009f2f92ac6b2cca6c7c49bb4ffaf0aa769ee6e14803`。
完整 371 文件不加入 Git；[hash manifest](evidence/hash_manifest.json) 冻结文件集合和字节，
新 CSV/JSON 均 UTF-8/LF。50 项新检查及两次全矩阵重放由 `verify_round6.py` 检查，
执行记录见 [final verification](evidence/final_verification.json)。运行时间独立保存，不参与确定性 hash。

## 一个世界与明确的兼容边界

`NetworkSimulation` 仍使用原 `Simulation.stock/orders/queues/arrivals/shipments`；FirmNode
的 inventories 是该 stock map 的同一对象引用。原 acceptance、FIFO dispatch、receive、
部分发运和确认取消的数量操作继承使用。flow 表只有非拥有的核对计数，不是第二个库存账。
原 step 和 produce 写死 A/B/C 与一个 terminal，因此只在 opt-in 子类提供企业遍历、
recipe 执行及多 sink 编排 hook；没有为每个企业建立 Simulation，也没有 EconomicRuntime。

每日边界：receive → cancel confirmation → 当日自身外生事实/前一边界请求观察 →
企业局部计划与 reconcile → 依开工前投入生产 → terminal delivery → known public offers →
有界同日 procurement rounds → 原 FIFO dispatch → 企业/世界/订单核对 → 报告归档。
其他企业当天新生产的商品不能跳过运输直接成为投入。计划和 projected tail 都不制造商品。

**Stage25 不混淆两种比较。** 在进入网络矩阵前，X0/X1 各 600 日的
`SingleChainCompatibility` 对旧 `ExecutableSimulation.run_case` 的逐日实体、requests 和
events 完整一致；其 FirmNode/Route 是旧权威库存和线路的 identity view。此 control
明确保留旧 steel S0 和旧跨企业 P3 规划，仅用于冻结 oracle。另有相同单链开工状态下
通用 recipe hook 与原生产 hook 的实体数量相等测试。正式 generic S1 是相同初始参数，
但使用局部请求观察和 steel S2，**不声称其完整轨迹等于旧 P3/S0**。
例如 Day600 旧 X1 的 B coal/steel 为 100/0，generic S1 为 160/42；两者都累计交付6000，
末 backlog0。差异来自有意更换的采购/信息边界，并没有改写旧 fixture 来使其相等。

## 局部信息与统一采购

FirmNode 保存独立 RecipeGraph、DemandHistory、CustomerRequestHistory、ReleaseBook、
日期 bucket、known sets、订单观察和 procurement 状态。firm_type/place 只是 metadata；
firm_type 改名的实体结果一致。当前 planner 接口只接收本企业节点、day、H 和自身公开
lead 信息，不接收 world、其他企业 plan 或 terminal backlog。

跨企业路径为 C 的 machine 计划→steel request→被寻址的 B 观察实际请求→B 的 steel
计划→coal request。供应商同时看到 accepted 和 rejected；接受余额另存 customer_pending。
同一 `(buyer, need_id)` 的重复尝试不会被累加成新终端消费；50 缺口重试10次的 gross500
与 distinct50分开，50→80→100只有新增正差额。需求日期过期会清除 active unresolved，
订单仍保留。历史 `seen_max` 仅做按 ID 查找，随日期身份累计存储；它不是无限记忆免费的
预测器，同一 ID 回落后再次回升但未越过历史峰值也不计新增，这是本轮明确的观察假设。
同一公开 need 可以送给多个卖家，每家看到的是自己的竞争性请求兴趣，不能把它们相加
当作新增世界消费；buyer 的唯一实际暴露仍由自己的 ReleaseBook/accepted orders 协调。

coal 和 steel 的 quote/accept 都使用原 PurchaseRequest、SupplierOffer、StockCommitments
和 TransportSlots。共享池键为 supplier+commodity；quote 不预留库存，真正 acceptance
再检查当前共享库存、对应线路的槽与本轮分配。每条显式 route 有自己的容量/lead/槽；
没有共享码头或跨线路总运力约束。ETA/promise 基于当前已知 lead/容量窗口，不能读取未来
恢复；逾期 pending 不视为及时覆盖，但继续占真实采购暴露。正式 X1 不自动取消。

C0 使用明确 `(day, round, buyer_id, request_id)`；C1 使用精确整数比例和 largest remainder，
平局按 buyer_id，线路 ATP 上限后的剩余再分配。报价与可见性按 known edges 索引，不
扫描所有卖家；最多每个买方 known 候选数量个 round，目前 degree≤2。第一候选接受后
重新 reconcile，只有 residual 才能向下一候选请求。各商品都遵循这一机制。

## Fixtures 与实际场景

S2 正常参数：A/D raw capacity100/60；B1/B2 steel30各；C1/C2 machine8各；T1/T2需求5各。
初始 raw coal400各，B coal160/steel20各，C steel60各；input target B160/C50，B output
target20。初始/目标由旧单链数量拆分，不在冲击场景提高 buffer。S1 保持旧原料初始/目标320、
steel初始120/目标100、B产能60/output target40、C15、T10。

共享 coal C/D/E fixture 是同一场景的两种政策和持续600日观察：仅 A80，B合计capacity30+30
即最多希望120 coal/day。为持续暴露这一供需差额，**此场景明确令 T1/T2=8各**，需求16而
煤供给支持10 machine/day。它不是正常总需求10的受控容量单变量比较；C0/C1之间只有
分配策略不同。I 独立使用 A60、T8/2，保持总需求10。参数已冻结，不靠结果调优。

| 场景，600日 | C0末 backlog（T1/T2） | C1末 backlog（T1/T2） | 末200日交付均值 C0/C1 |
|---|---:|---:|---:|
| B 正常 S2 | 0（0/0） | 0（0/0） | 10/10 |
| C/D/E 持续共享煤80，需求16 | 3532（0/3532） | 3521（1760/1761） | 10/10 |
| F 两钢厂15各，煤充足 | 1488（0/1488） | 1476（738/738） | 7.5/7.5 |
| G B1 Day100停产 | 1240（0/1240） | 1228（614/614） | 7.5/7.5 |
| H B1短lead1/cap15，B2长lead8/cap45 | 0（0/0） | 0（0/0） | 10/10 |
| I A60，T8/2 | 1417（278/1139） | 1418（1418/0） | 7.5/7.505 |
| J T1 Day100从5升10，T2=5 | 1001（1001/0） | 1001（1001/0） | 13/13 |
| K A→B1 Day50–79停运，其他路线保持 | 0（0/0） | 0（0/0） | 10/10 |
| M 两钢厂10各，煤充足 | 2981（0/2981） | 2970（1485/1485） | 5/5 |
| S1 generic | 0 | 0 | 10/10 |
| S5 3 raw/5 steel/10 machine/10 sinks | 10344 | 10282 | 32.5/32.51 |
| S10 5 raw/10 steel/20 machine/20 sinks | 28131 | 28001 | 52.5/52.49 |

[summary](evidence/summary.csv) 给出接受量、分享率、machine-days、峰值和账残差；
[network analysis](evidence/network_analysis.json) 保存各企业实际产出连续性、最大 owned+
pending+transit 暴露、最大日期需求、逐买方 gross/accepted/rejected、边界49/50/79/80/
99/100/101/110/200/400/600及最终 procurement。`edge_work.csv` 保存每场景每天 request、
accepted、shipment 和 active edges；active定义为当日仍有accepted pending或在途，
shipment edge定义为当天positive dispatch。请求量含重试，不是新最终消费。

### 正常网络仍出现局部稀缺

B 的总产能足够，仍记录 C0/C1 scarcity241/298个 supplier-round，共1446/1615个非空
supplier-round；其中240/298个含多个买方。这不是零 contention。S2初始两钢厂各仅20
ready stock，计划、运输和同时请求在日边界集中；S2不能以未来可生产数量接受当前订单。
共同偏好与上一边界公开请求形成局部反馈，即使全网可持续产能足够也会发生 ready-stock
竞争。没有通过增库存或改阈值掩盖。B1接受coal约33734/33722、B2约14448/14456，
已有上游分布偏差，但两个 sink 都交付3000、没有backlog。正常“无稀缺”预期没有完全
成立；应区别总产能充分与每个当前 supplier stock 充分。

### 分配改变连续生产和服务分布

煤稀缺 C0 B1/B2累计接受35940/12300，C1为24123/24117。C0末钢采购C1/C2为19200/5020，
C1为12120/12119。总末backlog只相差11，缺口分布完全不同。M更明显：C0 C2只接受16steel，
仅4日有machine产出，Day100后501日均停产；C1两个C各接受6010steel，末200日各产500。
S10 C0 C11/C20累计steel接受量为0、末backlog均2985；C1没有这两个零接受节点，但 ring
限制与局部请求仍使sink末backlog在1029–1876间不同，不是全网均等化。

I 是需要保留的反例：C0让高需求T1缺278、T2缺1139，C1变成T1缺1418、T2缺0，总量
几乎不变。C1并非按最终需求比例保证服务；每一卖家只按当次公开请求分配，经过多个企业
和日期后会改变效率/分布。没有利润、破产或生存规则，所以“停产”只报告实体连续性，
不称企业死亡。这些后果不能据此选定正式公平或经济正确规则。

### J 的订单传播、H 的长lead、G 的能力缺口

J Day99 C1/C2对B1各请求20steel；Day100 C1请求24、C2仍20；B1观察率当日仍28，
Day101为28.2。Day101 C1向B2请求28、接受27，残余1再向B1请求；Day102 B2观察率12.4。
传播靠被寻址 requests，供应商不能提前看到T1内部未来需求。两种政策最终都缺1001：
C1机器capacity8无法持续服务自身10/day，C2空余产能没有跨sink销售路径。这是明确的
生产/销售拓扑限制，不能用全网16≥15声称满足需求。

H Day1长lead B2 offer ETA11，对应请求是need_by11、PROJECTED日期桶；Day2 ETA12同理。
容量15的短lead钢厂不能包办，长期钢生产转到B2。两种末backlog0，但峰值26/24、
machine-days226/205；B1 Day100后不生产，B2末200日产8000steel。这证明本fixture中的
长lead真实供给可被释放表达承接，不证明所有路径恢复或排程已解决。

G Day100以后B1实际产出0，没有删除已有订单/库存/在途或自动取消。B2承接剩余采购，
末200日产6000steel，只支持7.5 machine/day；末backlog1240/1228诚实增长。

### K 与 M：不隐藏原失败，也不混淆不同网络

K只关闭一条A→B1煤路线，原初始/目标保持。C1政策Day49 B1真实煤暴露290，Day50
A到31、D到33并发48；Day79 D到46发60；Day80 A恢复发44。D是已知真实独立来源，
没有凭空跨路搬货。两个政策全期peak backlog0；Day80开始的连续20日交付≥10与
backlog0窗口均成立。这一拓扑没有复现旧Round5B低缓冲双线路受损的慢恢复失败；
旧失败及全部hash保留，不能把不同受损范围解释成X1普遍改进，也不把窗口称全部库存恢复。

M需求10，但steel20/day只支持5 machine/day。两B各累计coal接受11940，最大真实输入
暴露均160，末暴露120；终端backlog持续增长而原料采购未无限增长。产能约束和实际暴露
同时起作用。G/H等场景可超基础target：例如H B2最大煤暴露496，因其lead可见日期计划
较大；target并非所有场景硬上限，所有accepted迟到责任继续占暴露。

## 共享承诺和取消专项

[shared commitment probes](evidence/shared_commitment_probes.json) 是同一个世界实际12日
结算，每个commodity/C0/C1分别stock100、两个同日报价100、请求80各。C0接受80/20，
C1接受50/50，总100。Day1–3暂不可dispatch；Day3请求取消买方1的20，Day4确认后
free stock正好20，另一买方原reservation不变，随后新order接受20。确认前不释放。

部分发运coal/C0：原80发30，次日确认只能取消50，原订单最终delivered30/cancelled50，
新单50。steel/C1：原50发30、只能取消20，新单20；另一个买方50全交付、cancelled0。
专项在确认后、当日原FIFO dispatch前抓取commitment快照，避免把另一订单自然履约
误认为取消污染。订单恒等式含cancelled，取消不进入商品来源，已在途/已交付不能取消。

## Correctness 与 gate 的证据范围

50项自动检查覆盖：库存引用/企业隔离、通用recipe实体oracle、两种单链旧边界600日、
统一coal/steel单买方S2、共享库存、quote非reservation、accept重验、C0/C1顺序不变性、
比例取整/线路上限、有界residual轮次、局部history/知识、未知候选拒绝、重复need去重、
peer-plan/backlog guard、下一边界信息、世界/企业/订单账、确认取消/部分在途、瓶颈暴露、
Day1–99未来需求/工厂产能/路线容量prefix、sleeping/insertion probes、known-edge计数、
禁止决策遍历orders/plans/shipments/revisions历史档案、preproduction投入、确定性。
没有 `C1 backlog < C0` 断言。

每步coal/steel/machine world residual、每企业每日flow residual和每route订单residual均0。
这些恒等式与测试只排除所列数量/信息/实现错误，不验证消费、企业行为或经济真实。
Gate的模型输入限定为本轮goods/fixtures、显式本地信息、已知degree2网络；
多生产买方、多个钢厂、共享承诺、统一采购、局部计划、请求传播、容器顺序不变、账、
future isolation、S5/S10均有自动检查及实际运行证据。生成的 `network_gate.json` 是矩阵
计数/账/专项检查，必须结合完整测试与两次重放，不能单独用六个字段批准整个模型。

## 性能：四类成本分开

本机最终生成24网络案例实体/计划/观察归档合计 **99.599秒**，不含compatibility controls、
tests、专项及文件export。以下取C1；秒数含本轮逐日观察归档，不是吞吐SLA或平台承诺。

| scale | firms / known edges | offer queries | planning visits | live supply visits | allocation candidates | peak orders/shipments | seconds | serialized bytes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| S1 | 3/2 | 2400 | 1800 | 5990 | 106810 | 4/5 | 0.857 | 5349847 |
| S2 B | 6/8 | 9600 | 3600 | 30446 | 362636 | 13/13 | 2.735 | 12490783 |
| S5 | 18/30 | 36000 | 10800 | 133055 | 1678110 | 46/46 | 9.463 | 54409178 |
| S10 | 35/60 | 72000 | 21000 | 201854 | 2858917 | 80/80 | 21.144 | 108742397 |

两次查询阶段（visibility+matching）使600日offer数=2×known_edges×600。S10有30buyers、
15sellers，如果all-pairs则每阶段450pairs；实际60known edges。没有发现采购 all-pairs
structural blocker；这不意味着总成本只随known edges。

| C1 scale | planning s | procurement s | production/delivery s | dispatch s | account s | report/archive s |
|---|---:|---:|---:|---:|---:|---:|
| S1 | 0.310 | 0.261 | 0.061 | 0.022 | 0.017 | 0.145 |
| S2 B | 0.910 | 1.011 | 0.202 | 0.059 | 0.046 | 0.409 |
| S5 | 2.745 | 4.182 | 0.549 | 0.231 | 0.132 | 1.312 |
| S10 | 6.027 | 9.195 | 1.138 | 0.446 | 0.256 | 3.476 |

[execution](evidence/execution.json) 另给receive/observations和export秒数。以上是hook边界
时间，planning/procurement内部包含reconcile，production含consume/reconcile，不能当
单个函数纯微基准。ReleaseBook的日期bucket×当前supply lot分配随活动责任增加，S10
C1 2858917候选访问，大于C0 1714729；不是跨世界supplier笛卡尔扫描。
active order/shipments在live索引结算；历史orders/requests/plans/revisions只追加或按ID查，
guard测试禁止决策整表遍历。报告CSV和customer ID历史存储随天数累计，本轮没有tracemalloc
或RSS测量，serialized bytes不能叫内存峰值。S10约109MB完整案例档案是实际成本。

100日增加100个sleeping firm：offer仍1600、planning仍600、requests/quotes/实体结果
完全相同；world ledger firm visits从606增至10706。构造、stock存储、世界守恒及flow
报告必须处理它们，因此sleeping不是免费。各世界在同一个真实库存/订单引擎中执行，
不是只测matching mock。详见 [structural probes](evidence/structural_probes.json)。

## 对18个研究问题的直接回答

1. **独立买方/生产者**：S2中B1/B2/C1/C2同时运行，S10有35个生产节点，拥有独立库存和计划；共享上游供应，不是互不相干复制链。
2. **唯一权威**：一个stock map、订单/active订单、FIFO队列和arrivals heap；flow只是可核对记录。
3. **steel统一机制**：正式网络coal/steel完全相同S2路径；仅旧oracle control保留显式S0边界。
4. **共享承诺**：100库存、80+80竞争及确认取消专项安全；所有实际账满足，不外推到未测并发服务。
5. **C0/C1差别**：主要是连续生产和缺口分布，多个场景总吞吐接近。
6. **稳定偏置**：C0显著偏向稳定ID靠前买方；S10 C11/C20零steel接受。ID排序是公开政策，没有轮换掩盖。
7. **总服务/分布**：coal3532/3521很接近，但0/3532与1760/1761不同；I反例说明C1也可能损害高需求sink服务。
8. **step-up传播**：Day100公开steel请求增加，Day101起供应商观察变化、形成自己coal需求；C1机器cap8造成长期2/day缺口。
9. **中央泄漏**：正式local_plan没有peer/world参数，guard及future prefix通过；全局registry只承担结算和寻址。旧control的中央P3是明确例外。
10. **bottleneck阻止raw overbuy**：M两个钢厂各煤暴露峰值160、累计11940，没有随backlog无限增长。
11. **钢厂shutdown**：B2接 residual，但30steel/day不足以服务10machines；没有删除B1旧订单。
12. **知识边界**：buyer-specific known sets和未知query/request拒绝测试成立；当前固定known graph，无本轮自动搜索。
13. **规模工作量**：报价随known E，局部计划随active firm与日期桶，reconcile随活动责任×lot，物理/world账随firm/route/active订单，档案随天数。
14. **sleeping影响**：不改变活动查询和实体结果；增加world账、构造、存储、报告。
15. **放大的失败**：长期中间瓶颈、ID饥饿、非对称需求分配与step-up1001；旧stale无改进/低buffer慢恢复仍由历史回归保留，K单路线冲击未触发慢恢复。
16. **需要价格的问题**：若要比较“稀缺单位应给哪个buyer”的竞争依据，当前ID和请求比例均是外加规则；存在足够分配敏感性证据设计价格/出清比较，但未证明价格必然改善服务。
17. **生产/运输/信息缺口**：依然存在C1自身cap8、固定销售sink、ring、共享物流未建模、请求观察假设等真实限制；价格不能创造煤/钢或修复cap。它们不是本轮数量 correctness defect。
18. **较大网络研究能力**：S5/S10完整600日、真实竞争与确定性证明可以进行有界规模的模型价值实验；尚不能外推全国/人物经济或任意commodity runtime。

## 下一方向与剩余结构限制

只推荐一个方向：**A — Pricing / Market Clearing**。煤/钢/S5/S10有显著稀缺分配敏感性，
I进一步证明按请求比例并不自动对应最终服务价值，当前缺少竞争性依据。下一轮应仍在
固定物质/信息网络中设计最小可反驳比较，明确支付/需求含义；本轮不先实现auction、money
或金融，也不宣称市场均衡已经定义。capacity/运输/sink拓扑作为固定约束保留。

剩余限制：固定coal/steel/machine物理计数及已测recipe；各route独立ATP、无共享码头；
固定known degree2、无新搜索；sink固定连接自身生产者；日期ID历史与完整报告档案线性
累计；历史峰值需求去重假设；没有任意配方周期/多阶段同厂排程验证。旧control与正式
网络的信息/steel采购边界不同，需要分开解读。没有加入价格、家庭、金融、随机性、
中央优化器或WWO集成。Round6独立PR待审查，完成后停止。
