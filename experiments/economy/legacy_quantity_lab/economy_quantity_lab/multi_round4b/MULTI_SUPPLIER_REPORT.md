# Round4B — Bounded Multi-Supplier Matching & Switching

实际完成 S2 当前库存承诺、已知候选集上的 M0/M1/M2、显式发现和确认后切换。
A–J 加单供应商控制共14×600日，33项新增检查及两次完整115文件复现通过。
未知 D 没有泄漏；已知 D 在临时冲击中消除了本轮 backlog，但其60/日容量
不能独立满足80 coal/日。M2改变承诺去向，没有改善J中的物质服务。
下一轮建议 **Round4C — Supplier Search / Information Acquisition**，不自动启动。

## 真实基线与执行来源

PR #3 head `a40f3ede565f0b920abc1a3a7ce23618be433654` 与已验证状态相同，
两个CI成功，MERGEABLE/CLEAN，没有新增提交、review或未解决thread，账号ADMIN。
按本轮明确授权于2026-10-07T08:31:08Z合并。实际 main/base：
`307df8f4d64dc039e2d291082394178c1d556a58`。使用GitHub API同步签名Git对象，
核对本地/远端commit与tree SHA；没有force push。

annotated tag `economy-lab-v0.4a-supplier-admission` 对象
`680db7dd8a1d64bde0cc442c97b8c7bb17af3f6c` 指向该main，message：
`Verified Round4A supplier admission and ATP research baseline.`
研究分支 `research/multi-supplier-round4b` 从验证后的合并main建立。
原8项、Round2 9项、Round3 18项、Round4A 29项在算法修改前后均通过。
旧fixture、H0/H1、来源156文件、各轮历史源码/结果/hash都保持不变。

本机Python3.12.14，实际运行的是
`C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`。
以下命令均实际执行，exit code=0；详细命令、平台、时间、退出码见evidence验证记录。

```sh
python verify_baseline.py --output-dir .local/round4b-pre
python verify_round3.py --output-dir .local/round4b-pre
python verify_round4a.py --output-dir .local/round4b-pre
# 新增目录内执行：python -m unittest -v test_multi_supplier.py
python economy_quantity_lab/multi_round4b/run_multi_supplier_experiment.py --output-dir .local/round4b-frozen --execution-log .local/round4b-frozen-execution.json
python economy_quantity_lab/multi_round4b/run_multi_supplier_experiment.py --output-dir .local/round4b-frozen-memory --execution-log .local/round4b-frozen-memory-execution.json --measure-memory
python verify_baseline.py --output-dir .local/round4b-post
python verify_round3.py --output-dir .local/round4b-post
python verify_round4a.py --output-dir .local/round4b-post
python verify_round4b.py --output-dir .local/round4b-final
```

Windows旧105/139输出直接匹配，34份生成JSON按既有CRLF→LF兼容政策匹配；
Linux CI仍要求旧139文件直接匹配。Round3两次59文件、Round4A两次44文件及
Round4B两次115文件直接字节一致。Round4B内存追踪开/关结果也全同。

| Summary | SHA-256 |
|---|---|
| Round2 | 02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02 |
| Round3 | 070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae |
| Round4A | 7522b9313a1aa47c60943029c4aff3f8869657f67c98d11502a1d064e1249b55 |
| Round4B | afccc372d5ec721a31b3a39f507ce65f0eb1e73e6e791cd231aabc2048e1897f |

inputs保存用户明确指定为请求的附件，原始与LF规范化hash分列。
manifest记录14份输入/源码hash，hash_manifest冻结115份完整输出；Git保留
summary、选定日、gate、专项、取消证据及执行日志；全量输出在忽略目录和CI artifact。

## S2先修复真实库存约束

S2 = min(运输ATP, 当前on_hand减尚未发出的库存承诺)。接受量同时占用共享运输槽
和供应商/商品库存池；不移动物资。stock commitment直到真实dispatch或confirmed
cancel才释放，**逾期本身不会释放**。同阶段检查承诺不超过库存并等于对应live pending。
实际dispatch使原仓库减少q、承诺同时减少q；确认取消只释放未发的承诺。
跨请求、跨订单共享同库存池，独立订单ID不能重复占用同一批货。

Stage3在加D以前实际通过：A库存0、产能0、线路100、请求320，S2接受0/拒绝320，
没有Order或shipment，open need320。S1控制的**单次**接受是300/拒绝20，
因为三日运输窗100×3=300；旧Round4A探针的320是十日累计接受。
两者都实际复现。本轮不把累计结果伪装成单次320，也不调大窗口来迎合文字期待。
stock_gate.json保留加D前的检查，最终probes.json另保存当前实现的完整证据。

这是保守ATP：明确不承诺尚未产出的货物。独立探针中今天库存0，纵使A明日产能100，
今天请求80仍接受0；次日真实生产完成后能接受正量。没有未来生产预测、MRP或隐形库存。

## 一个世界中的D与数量来源

D有独立supplier/place ID、初始coal400、开采上限60/日、仓内目标400、D_B线路
capacity60、lead4。A原参数100/日、lead2保持。普通fixture中的B煤目标仍320，
终端需求10，B/C配方与产能、C steel采购保持不变。

没有复制Simulation。原step、receive、FIFO dispatch直接继承；原production_plan
先产生A/B/C计划，再附加D的当前补仓量，produce先执行原A/B/C结算，再增加D煤来源。
原coal_mined在该新adapter中计A+D，并另外保存source_extraction[A/D]，检查二者之和
相同。原数量账已经对所有初始库存、仓库和线路在途求和，因此D的400初始、实际开采、
仓内与在途进入原账，无需修改旧ledger/receive或复制结算。

原逐日row把同一买方的aggregate new_order重复标到每条入境线路。新增观察器只校正
A_B/D_B采购输出标签为实际各supplier接受/拒绝量；不改step或任何经济行为。

## 信息边界、公开offer与matching

available固定为世界fixture中的[A,D]，known是买方当前集合；considered为本边界
政策实际输入，queried只记录真正offer调用。M0即使known=[A,D]也只consider/query A。
M1/M2从known构造候选，unknown offer/request直接拒绝。没有全球枚举寻找卖方。
观察器能导出世界事实中的D仓库/运力诊断，但买方排序只接收SupplierOffer，
不会把这些诊断当作已知信息。未查询供应商的offer字段为空。

offer含supplier、commodity、当天、可接受量、最晚dispatch、lead、expected arrival
及STOCK_CONFIRMED basis，无价格或内部生产/库存状态。最晚dispatch=当天+2，
expected arrival=最晚dispatch+固定lead，这是保守承诺上界估计，不是实际shipment ETA。
匹配排序固定为expected arrival升序、可接受量降序、supplier ID字典序。
供应商真正接受时重新核对自己的库存/槽，不能依赖一个已被占用的旧quote。

信息使用外部InformationInbox只交付当日SUPPLIER_DISCOVERED，source为
fixture_information_event。Day60/90加入D前绝不查询D，未读取未来发现事件。
Day1–59/89与unknown对照完整一致；另有Day100发现分叉与D capacity分叉的99日前缀。

全局position= B on_hand + A/D全部在途 + A/D全部live pending。拒绝不进入账，
每接受q就减少remaining need，再访问下一offer。H专项在Day0明确设置B220、A40、D60，
初始need100→A request100/accept40/reject60→D request60/accept60，最终need0。
I设置B170，need150→A40+D60，只接受100，保留need50。随后各运行600日，
这些是有明确初始差异的专项，不伪称与普通初始fixture完全相同。

## 正式14×600日结果

| 场景 | 策略/信息 | A累计接受 | D累计接受 | backlog峰/末 | machine-days | 末200日交付均值 |
|---|---|---:|---:|---|---:|---:|
| A单供应商S2 | M1，无D | 47920 | 0 | 0/0 | 0 | 10 |
| A世界有D但unknown | M1，known A | 47920 | 0 | 0/0 | 0 | 10 |
| B正常 | M0 | 47920 | 0 | 0/0 | 0 | 10 |
| B正常 | M1 | 47920 | 0 | 0/0 | 0 | 10 |
| C A50–79容量30 | M0 | 47920 | 0 | 148/0 | 6116 | 10 |
| C A50–79容量30 | M1，D已知 | 46480 | 1440 | 0/0 | 0 | 10 |
| D A从50停运 | M1，D永远unknown | 3840 | 0 | 5440/5440 | 1482400 | 0 |
| E A从50停运 | M1，Day60发现D | 3840 | 32540 | 1420/1420 | 403164 | 7.5 |
| F A从50停运 | M1，Day90发现D | 3840 | 30740 | 1645/1645 | 520494 | 7.5 |
| G A无库存/产能，线路100 | M1，D已知 | 0 | 36020 | 1465/1465 | 430124 | 7.5 |
| H Day0 need100、offer40/60 | M1 | 47960 | 60 | 0/0 | 0 | 10 |
| I Day0 need150、offer40/60 | M1 | 48010 | 60 | 0/0 | 0 | 10 |
| J Day0 A接受80、Day1起停运 | M1 | 80 | 35940 | 1475/1475 | 436010 | 7.5 |
| J 同上 | M2 | 80 | 36020 | 1475/1475 | 436010 | 7.5 |

A单供应商S2与世界有D但unknown的A/B/C数量、请求、offer和订单事件一致；D维持自身
400库存，未被偷用。M0与单供应商S2在normal/shock/shutdown/full_shutdown的原row/events
全部一致，历史功能关闭仍由旧完整验证检查，不混称S2在缺货时等同旧S1。

B正常M1确实查询D，但按公开offer排序A较早且足够，于是没有分单；这是实际结果，
测试没有强迫M1只用A。C第一次D dispatch在51、arrival在55；A的partial/reject余额
累计1440流向D，A30+D60运力满足本轮80正常需求，初始缓冲与真实到货共同避免积压。
该有限场景改善不证明一般多供应商规则正确。

D unknown时D仍有真实400库存，却没有查询、request、订单、发运或开采利用。
E发现当天60开始D dispatch，64第一次coal到货；F对应90和94。
Day60比Day90多交付225 machine，期末backlog少225、machine-days少117330。
两者都只达7.5/日，不能称恢复10/日或清积压；连续20日“至少10/日”窗口不存在。
主要长期缺口是D60 coal/日，而10 machine需80；四日lead还产生发现后的等待。
这不是D unknown泄漏，也不是账目错误，不能靠改发现日期或调capacity掩盖。

G把A库存及实际产能设0，线路仍100：A stock-confirmed offer始终0，累计请求36020
被stock约束拒绝；D提供真实36020接受量，仍受60/日限制。此拒单不是“未来会产出但过度保守”。
H/I在Day0分配后，次日真实开采恢复库存，后续能补足，原need50没有用假订单填平。

## M2：只确认后切换，不偷换旧在途

M1不取消live pending或已发在途。M2仅在旧pending明确OVERDUE且另一known供应商
有正STOCK_CONFIRMED offer时request cancellation。继承Round4A默认一日确认，
等待期间旧pending继续占全局position；确认重读pending，只把已确认量形成replacement
ticket，按公开offer向非原supplier请求。原在途保留。未完成ticket保留真实open need，
暂不回购原source；没有新货或shipment。替代订单仍进入原supplier FIFO尾部。
这个等待规则是明确M2策略限制，不是额外运力或运输优先级。

J是正常600日结算：Day0 A从真实库存接受80、deadline2；Day1线路停运；Day3 OVERDUE
请求取消，Day4确认80并向D替代80。等待期仍可为**新耗用形成的新need**采购，
但不能把旧80提前再订。M2的D累计接受多80，最终未发余额由A80变成D80。
J的全部物质仓库、生产、运输数量、到货、交付和backlog逐日一致；有订单与offer差异，
不能宣称“整个状态一致”。D运输已经满负荷，所以释放坏承诺没有增加真实服务。
M2峰值活动订单6，M1为5，并增加一日确认等待和取消/替代事件。

probes另保存人工构造的逾期订单状态边界：A pending80，Day3请求取消；等待期
原dispatch发30；Day4只确认50、A在途30、D只替代50，global position320。
该专项不冒充完整生产时间轨迹，说明其时钟/订单状态fixture，并检查真实物资账。
30到货后转库存仍去重；D取消也有对称检查。商品取消量从不进入物资来源。

## Overshoot、保守性与尚未解决的问题

全部正式每日global position最大320，没有超目标重复接受；B库存全期最大320
含初始缓冲，C/E/F在50日起仓内煤最高160，没有观察到超正常稳态的仓内overshoot。
每个采购边界跨supplier accepted总量不超过该边界初始need；全部旧在途共同去重。
这不排除其他lead、目标或需求下出现账目正确的策略过量库存。

正常、C及E/F正式采购没有stock引起的拒绝；G的大量stock拒绝来自真实零库存/零产能，
H/I拒绝来自明确Day0小库存。probe证明S2可能保守等待明日产出，但这轮没有证据表明
production-aware ATP是主要物质服务瓶颈。更完整ATP还可能需要保护多产品库存用途、
生产输入、损耗、可供货时间和未来已知产能；本轮不扩MRP或预测。
固定arrival排序没有价格、可靠性score或全局搜索，未证明在更多候选/拥塞路线上最优。

## 性能、索引与验证边界

最终未追踪运行14案模拟/观察合计约2.932秒，单案0.113–0.344秒，不含导出。
tracemalloc峰值约8.51–16.24MB，含请求/offer/逐日/订单档案和索引，不是RSS或核心工作集；
仪器会改变耗时，单列memory_execution_log。不能推广为WWO全球性能。

新请求、offer、discovery、cancel和switch建立当日索引，导出只访问当前事件。
unknown shutdown有599历史请求，Day100/300/600各只访问2个本日request/offer，
600日累计1198，不复制Round4A的179700档案扫描。正式案日峰2–8个导出事件。
档案和日索引仍随天数线性保留；不是常量内存。本轮没有改Round4A历史观察器。
候选最多2个，正常M1每日多一次D查询是无分单的实际成本。
slot、stock commitment、活动订单均按当前占用检查；summary区分日末与接受时峰，
例如正常日末未发承诺0，不代表日内未使用槽或库存承诺。
counter分别限定为offer调用、候选枚举、承诺分类、槽访问、库存检查和当日导出，
没有声称覆盖原引擎每个Python循环或完整运行时成本。

33项检查覆盖knowledge边界、partial/reject、库存共用、运输槽、跨供应商need上限、
在途/到货去重、两类99日前缀、保守取消及部分dispatch、D来源、订单/商品账、
旧控制、观察on/off和全部确定性。全部商品/订单残差为0，没有未解决correctness defect。
这些是实现契约证据，不是“测试通过所以模型正确”或经济真实性证明。

## Next Gate

推荐 **Round4C — Supplier Search / Information Acquisition**：known-set matching已
在本轮有限候选下稳定工作，unknown完全不被使用，外部发现时间直接改变服务损失。
Day60/90差异225 delivery及117330 machine-days提供比“需要价格”更直接的证据。
下一轮应设计有界信息获取来改变known集合，并保留D供给不足和当前ATP标签。
production-aware ATP保留为候选，需先有真正“库存暂低但已知生产可及时履约”的
量化反事实；本轮probe只能证明保守边界，不能证明扩大预测会改善完整网络。
不推荐立刻Round5 Pricing：当前真实瓶颈是信息、运力/产能和lead，而非已验证的价格缺口。
无自动下一轮、价格/资金/信用/工资/金融、随机搜索、可靠性score、完整MRP或WWO集成。
所有机制仍是研究候选，不能凭一组改善进入正式WWO。
