# Round4C — Bounded Supplier Discovery & Search Scaling

实际实现粗目录索引、Q0/Q1、LOCAL/REGIONAL/WIDE、1/3/7日信息时延、30日同scope
冷却与持久知识。18×600日、32项新增检查、两次184文件直接字节复现通过。
**EXTENSIBILITY_GATE=PASS**：通过的是表达能力与所列接口约束，不是经济真实性或模型价值。
下一轮优先建议 **Production Planning / Demand Propagation**，不继续默认加深搜索或开始价格。

## 合并基线与复现

PR #4 head `e82e7ac7fc07389183a03137830c52d30a445bb4` 与已验证Round4B一致，
两个CI SUCCESS，MERGEABLE/CLEAN，无新提交、review或未解决thread，账号ADMIN。
按用户本轮明确授权于2026-10-07T09:17:35Z合并。真实main/base：
`be9dfd54999ff156e5881b501118a53f151d68c8`；同步时核对签名Git object和tree SHA。
annotated tag `economy-lab-v0.4b-multi-supplier` 对象
`0c497d4c0112461a1f25483a6534dc764cbd3b6d` 指向该main，message：
`Verified Round4B bounded multi-supplier matching research baseline.`
分支 `research/supplier-search-round4c` 从验证后的main建立。使用已验证GitHub API方式，
没有force push，也没有把Git步骤当作本地实验的停止条件。

Python3.12.14，本机实际执行路径：
`C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`。
修改前后原8项、Round2 9项、Round3 18项、Round4A 29项、Round4B 33项均通过。
实际命令/版本/平台/退出码/base/branch在evidence pre/post验证JSON，全部exit code=0。

```sh
python verify_baseline.py --output-dir .local/round4c-pre
python verify_round3.py --output-dir .local/round4c-pre
python verify_round4a.py --output-dir .local/round4c-pre
python verify_round4b.py --output-dir .local/round4c-pre
# 新目录内：python -m unittest -v test_supplier_search.py
python economy_quantity_lab/search_round4c/run_supplier_search_experiment.py --output-dir .local/round4c-frozen --execution-log .local/round4c-frozen-execution.json
python economy_quantity_lab/search_round4c/run_supplier_search_experiment.py --output-dir .local/round4c-memory --execution-log .local/round4c-memory-execution.json --measure-memory
python verify_baseline.py --output-dir .local/round4c-post
python verify_round3.py --output-dir .local/round4c-post
python verify_round4a.py --output-dir .local/round4c-post
python verify_round4b.py --output-dir .local/round4c-post
python verify_round4c.py --output-dir .local/round4c-final
```

原156来源hash保持。Windows旧105/139输出直接相同，34份生成JSON按既有CRLF→LF
政策兼容；Linux CI继续要求旧139输出直接匹配。Round3两次59、Round4A两次44、
Round4B两次115、Round4C两次184文件直接相同；本轮内存追踪开/关输出也全部相同。

| Summary | SHA-256 |
|---|---|
| Round2 | 02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02 |
| Round3 | 070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae |
| Round4A | 7522b9313a1aa47c60943029c4aff3f8869657f67c98d11502a1d064e1249b55 |
| Round4B | afccc372d5ec721a31b3a39f507ce65f0eb1e73e6e791cd231aabc2048e1897f |
| Round4C | 37624a453a9563da0732fde9b13f5c81a58b3c9b3f7e69a0f7a30328cfab0f8a |

用户明确指定的附件保存于inputs，原字节与LF规范化hash分列；manifest记录18份
输入/源码hash，hash_manifest冻结184输出。全量逐日、请求、offers、来源账进入
忽略目录与CI artifact；Git保留summary、gate/probes、搜索过程、选定日与实际日志。
所有旧fixture/H0/H1/算法/历史结果不改，Round4B关闭本轮功能的M1轨迹另作oracle比较。

## 目录、信息与决策真正分离

available是物理world collection；discoverable是粗目录中active/route-listed/channel
允许且符合commodity/scope的集合；search result是本次最多K个粗记录；known是初始知识、
被交付的搜索结果和明确外部事件的并集；considered/queried只在known里发生。
这些层不合并。Q0没有主动搜索；Q1仅当当前need>0、已知offers不足且无进行中搜索时发起。
每个buyer+commodity有自己的请求、pending、scope记忆与冷却，不因找到坏供应商遗忘它。

DirectoryEntry只有supplier/place/commodity/zone、静态route可达信息、nominal lead band、
advertised capacity band、active/channel。没有stock、ATP、订单队列、生产计划或future capacity。
目录字段是粗资料，不保证此刻可供。私有实时事实只能由已知supplier的S2 offer查询获得。
排序是粗nominal lead band再稳定ID，不看真实供货效果。正式matching仍用Round4B的
expected arrival、max acceptable、ID。SupplierOffer不是目录记录，结果交付也不是订单。

LOCAL只查Z0；REGIONAL查fixture相邻Z0/Z1/Z2；WIDE查该commodity预建远程bucket。
没有NationalMarket/GlobalMarket、全球采购扫描或搜索数据库。目录一次插入N条并排序
相关bucket；运行期使用dict lookup与已排序bucket的合并，排除已知ID，最多返回3。
结果由服务在交付日读取当日粗目录；等待期不会查询目录或提前把supplier加入known。

搜索t日发起，最早t+1/+3/+7交付。事件保存SEARCH_REQUESTED、SEARCH_COMPLETED或
SEARCH_COMPLETED_NO_RESULTS；空结果不凭空换成其他scope的supplier。完成后若仍不足，
下一请求LOCAL→REGIONAL→WIDE。完成WIDE后从LOCAL开始下一轮，距该scope上次完成
不足30日则等待；不会同日启动三个scope，不会因搜索完成而丢知识。
状态机scope记忆跨暂时供给充足期保留，未实现信息衰减或声誉。

## 物理supplier pool与有界procurement

generator支持2/10/50/200，稳定ID为A,D,E,S003…，place唯一，zone按十区域模式。
A/D保留旧参数；额外煤来源初始400、目标400，产能20/40/60/80、运输20/40/60/100、
lead2/4/6/8周期分配。正式特例的cap/zone/channel/库存差异在config中明确，不随机。
所有来源独立开采累计，进入原coal_mined总量；supplier_sources.csv逐源记录初始、开采、
仓库、在途、未发及订单账。钢/机器账及配方仍保持。

原step/FIFO/receive直接继承。生产先调用原A/B/C+D结算，再附加其余煤源，不复制世界。
决策的coal pending/transit由accepted/dispatch/arrival/confirmed cancel事件增量维护，
global position查询不扫描世界。只有已知supplier有激活的offer/slot map；请求与B matching
只访问这些ID。C钢采购直接定位原B_C线路，保持原目标/已知候选/接受行为，避免原入口
为查C入境线路遍历整个新世界。三种旧Round4B控制的原rows/events/requests/offers相同。

真实生产、原仓库/路线结算及物质账检查仍遍历world collection，这是物理模拟成本，
**不是matching成本**。新增观察器按日读事件，但完整CSV仍含每个世界仓库/路线。
原row将B采购总量重复标在每条入境线路；导出对全部线路校正为实际各supplier量，
未知supplier也正确输出0。该O(N)标签成本独立记录，不伪装为常数导出成本。

## 18×600日矩阵：真实效果和失败结果

A-F各Q0/Q1，G/H/I为10/50/200固定known2，J对比Day60外部事件与主动搜索，
另加2-supplier功能关闭控制。B-F的known A/D运输合计60，正常终端需要80 coal/日。
无关物理supplier可存在，但fixture将不属于该信息渠道的条目标记ARCHIVE_ONLY；
它们仍available，没有偷偷把世界全集交给搜索。容量、lead、初始库存及channel均归档。

| 场景 | Q1搜索请求/交付 | 有效新supplier进入known/首发运/首到货 | Q0末backlog / machine-days | Q1末backlog / machine-days |
|---|---|---|---|---|
| A正常10 | 无搜索 | 无新增 | 0 / 0 | 0 / 0 |
| B已知不足、E在regional | LOCAL6→7空；REGIONAL7→10 | E10 / 10 / 14 | 1462 / 428074 | 0 / 0 |
| C附近E | LOCAL6→7 | E7 / 7 / 9 | 1462 / 428074 | 0 / 0 |
| D local坏候选、regional E | LOCAL6→7；REGIONAL7→10 | E10 / 10 / 14 | 1462 / 428074 | 0 / 0 |
| E仅wide远方E | LOCAL6→7空；REGIONAL7→10空；WIDE10→17 | E17 / 17 / 25 | 1462 / 428074 | 1282 / 375694 |
| F先找到无库存E、后regional S003 | LOCAL6→7；REGIONAL7→10 | S00310 / 10 / 14 | 1462 / 428074 | 0 / 0 |
| J已知线路从50停运 | LOCAL50→51；Q0外部事件60 | Q1 E51 / 51 / 53；Q0 E60 / 60 / 62 | 20 / 11274 | 0 / 0 |

结果交付当天才首次query，随后原dispatch真实发运，再经过线路lead到货。
F的LOCAL E真实存在却库存/产能0，目录仍返回它；S2 offer=0、不创建Order。
它保留在known，后续仍可能被query，增加匹配成本；Q1按下一scope找到S003，没有根据
库存偷偷过滤目录或使用reliability score。D也保留无库存local候选，最终known4。
正常Q1没有无理由搜索；足够供应时Q0/Q1完整每日行一致。

J的搜索比本fixture Day60事件早，并产生可观察服务区别；不是假定主动搜索总更快。
Q0 backlog峰60、末20；E真实生产80/日只够正常流量，不能保证重建所有缓冲并清掉积压。
Q1 E53到货，当日旧链库存仍能产生机器，未产生backlog；Q0恢复后的机器首日产出为63。
信息时延、运输时延、供应余量与缓冲分别影响实体后果。

**Wide失败是本轮主要模型诊断。** E已知后有真实库存、线路100、生产80、lead8。
末200日200次E offer的可接受上限全部300，实际接受合计500，即2.5 coal/日；
同一200日open need全为0，最后global position320，backlog1282，交付均值7.81/日。
已知A/D加E的物理容量足够，却没有进入充分采购流量。长lead供给与固定320库存位置、
已接受pending/在途去重及先用较早offer的分配共同约束补货。Q1提高了少量服务，
没有完成10/日，更不能宣称“找到了就解决了”。本轮没有调target、lead或加预测遮掉它。
这是账目一致的策略/需求规划缺口，目前不能仅凭结果断言某一改法一定修复。

## 实测工作量与存储如何随规模变化

| N / known | 无搜索600日offers与matching visits | 单次LOCAL bucket大小 / emitted inspected / 返回 | 目录build visits | 模拟+观察秒 | tracemalloc峰bytes |
|---|---|---|---:|---:|---:|
| 10 / 2 | 1198 / 1198 | 2 / 2 / 0 | 10 | 0.2374 | 18422444 |
| 50 / 2 | 1198 / 1198 | 6 / 5 / 3 | 50 | 0.4721 | 45881642 |
| 200 / 2 | 1198 / 1198 | 21 / 4 / 3 | 200 | 1.4432 | 159432689 |

目录单次LOCAL测试是单独的信息接口probe（50请求、51交付），不是在充足供给时
违规触发Q1。10世界只有A/D在local且已知，因此返回0；没有捏造新local supplier。
每次只lookup一个local bucket，heap merge按序最多交付3个新ID，已知ID跳过。
query_visits计合并流中取出的候选，不计所有排序比较或merge头部预读；bucket_lookups
另计相关bucket数量。REGIONAL仅相邻bucket，WIDE仅当前commodity预建bucket。
guard测试禁止query迭代全catalog、禁止procurement迭代全世界routes，均通过。
build_visits是插入条目数；构建还含bucket排序，不能据此宣称严格线性总构建时间。
目录保留原entries和zone/wide引用，存储随N增长。

固定known时，coal匹配工作更接近O(K)而非O(N)；有效返回进入known后K确实增加，
bad候选也保留，所以D/F最后每日至多4次query，这是知识集合的真实成本。
世界实体计划访问10/50/200×600分别6000/30000/120000，物质账路线及导出也随N增长。
因此总运行时间及内存明显增长，即使matching不增长。完整每日原row和合并观察row保留
所有仓库/线路，使档案内存约随N×days增长；不是恒定工作集或全球性能承诺。
18案未追踪模拟/构建/观察合计约7.145秒，文件导出不含在内。
tracemalloc含档案/索引/行，非RSS；仪器影响耗时，内存日志单列且输出hash相同。

## Black-box与两buyer接口probe

混合目录200条、5 commodities、10 zones、1 buyer、初始known5，只对coal获取信息。
其他四类steel/machine/grain/timber在这个probe中仅目录元数据，没有新增生产交易链。
coal LOCAL/WIDE只访问coal buckets，检查的ID全部属于coal；未触碰其他commodity的bucket。
因此检索结构没有硬编码只能存coal，但不声称完整经济模型已经支持五类新生产网络。

两buyer、三supplier、coal共享同一个旧StockCommitments池；buyer各有独立known与
pending/cooldown，B1启动不会替B2启动搜索或增加知识。交付以后都可知道A，两个80请求
只接受80+20，A库存100不移动，承诺100，没有重复承诺。Search ID包含buyer/commodity。
这是接口probe，不是第二B→C生产链、第二Simulation、或完整跨buyer运输/消费市场。

## Correctness、Extension Gate与表达范围

32项检查覆盖unknown拒绝、pending结果隔离、真实latency、result-limit1/3/5、空结果、
顺序扩大、冷却、normal无搜索、固定known规模工作量、目录不看经济状态、zero-ATP、
全局need上限/在途去重、独立煤源与订单账、99日前缀、共享库存、5类bucket隔离、
旧M1 oracle、观察开关、确定性、禁止catalog/routes全扫描与known5初始化。
各世界coal/steel/machine residual以及订单residual均0；无未解决correctness defect。

EXTENSIBILITY_GATE **PASS**：200世界运行，unknown不参与日常matching，有界搜索能
改变known，scope/latency成立，目录不读取实时/未来经济状态，检索使用索引，5类目录
隔离，两buyer共享库存接口通过，所有已检验数量账保持。gate_checks及实际probe归档。
测试和零残差只支持这些结构约束，不能回答“经济模型有价值”。

黑箱现在能表达大量可用但未知供应商、不同zone/lead/capacity、渠道不公开、空结果、
信息延迟、scope扩大、发现后无货及固定known下世界扩张；可进入这些更大条件的模型评估。
仍不能表达真正多buyer生产网络、共享线路拥塞/公平分配、额外commodity生产链、
动态目录更新/消息丢失、真实搜索成本、信息衰减、完整生产规划、价格或金融。
物理消费链仍是原B/C，未来扩buyers必须接入独立需求与物质账户，不能把接口probe当成它。
source/account/export仍有O(N)物理循环，未做睡眠源增量scheduler或稀疏档案。

## 下一轮推荐

优先 **Production Planning / Demand Propagation**：Wide已完成发现且E每次offer300，
持续未满足终端需求却不形成足够open need。进一步搜索或production-aware ATP不会
自动让买方发出足够请求；当前缺口是需求、计划、库存位置与混合lead的协调。
应设计独立反事实解释这条传播链，保留本轮Wide失败，不直接调buffer让它消失。
扩多buyer/network是之后较大价值评估的重要条件，但先要让现有单buyer的需求与
规划缺口可解释，否则扩大只是复制同一瓶颈。库存已充分的E说明暂不优先production-aware
ATP，更没有证据支持直接开始Pricing。本轮不自动启动下一轮，不接入WWO。
