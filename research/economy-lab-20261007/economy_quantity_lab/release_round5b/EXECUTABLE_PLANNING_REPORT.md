# Round5B — Executable Planning Release & Commitment Reconciliation

本轮在同一个实体世界中建立可滚动的采购释放责任。Wide H10 的最终 backlog 从旧 P3 的1268变为X1/X2的0；但step-up保留141、H20保留5、恢复较慢，X2没有改善stale场景服务。这些结果不支持正式采用某策略。

## 基线、范围与复现

PR #6在两项CI SUCCESS、MERGEABLE/CLEAN、无阻塞review且ADMIN权限成立后于2026-10-07 11:06:28 UTC合并。main/base为`98ead27160fec2eecb545f3bc9f67e690e13bbf1`，已验证Round5 head为`0e4f529e52872ee0402e91771651152ceebfe49b`。annotated tag `economy-lab-v0.5-demand-planning`对象`efc79d4d086d3b82cdf107b91487e7266bb48d13`冻结main；本轮分支`research/executable-planning-round5b`。

Python 3.12.14，Windows。施工前后各运行原8、R2 9、R3 18、R4A 29、R4B 33、R4C 32、R5 40，共169项历史检查。全部六个旧verify通过。旧Round2的105/139文件直接匹配，34 JSON按既有Windows CRLF→LF政策匹配；CSV不转换。Round3–Round5直接字节复现，历史源码/fixture/报告/CSV不改写。新输出显式跨平台写入，629文件集合与hash均参加两次完整重放。

```sh
python verify_baseline.py
python verify_round3.py
python verify_round4a.py
python verify_round4b.py
python verify_round4c.py
python verify_round5.py
python verify_round5b.py
# 直接运行，在release_round5b目录：
python -m unittest -v test_planning_release.py
# 在仓库根：
python economy_quantity_lab/release_round5b/run_executable_planning_experiment.py --output-dir .local/new-release-run --execution-log .local/new-release-execution.json
```

命令、cwd、exit code、版本和hash在[evidence/provenance.json](evidence/provenance.json)、pre/post verification及本轮verification记录中。全部最终入口exit0。完整逐日、供给lot、allocation、quote、revision、释放检查和订单事件放忽略目录/CI artifact；Git保存summary、紧凑证据与完整hash map，不保存批量世界副本。新证据和重放CSV/JSON均显式使用UTF-8/LF。

## 实现边界与每日顺序

`ExecutableSimulation`继承既有`PlanningSimulation`；step、FIFO dispatch、生产配方、物质结算没有第二实现。原P3形成firm计划及当日实体产出。新`ReleaseBook`只管理非拥有型责任，库存只能由原结算修改。X0直接调用原P3所有决策路径。X1先协调日期供给再释放；X2另启用显式stale处置。

receive已收到Demand → 原P3 firm计划 → 当前known公开quote取得保守lead → projected tail → 更新可用供给并reconcile → 原生产结算并退休今日firm → 采购边界接收信息/确认取消/刷新quote与tail → 重新协调 → timely gap和真实exposure上限 → cancellation request或采购 → 原dispatch/日末观察。没有读取未来需求、route事件或capacity表；用于prefix分叉的世界事件只在当日receive边界公开。新查询使offer成本增加，不把它藏进旧matching成本。

逐日供给证据标注为“最后一次procurement reconciliation，原dispatch之前”；物质daily为原日末账。不能把这两个边界的pending/transit分项直接混比。已有cargo的ETA与接受时promise不被未来lead变化重写。

## 1. 为什么旧P3 H10不能充分释放long-lead采购？

H10只含t…t+9。E route lead8加明确dispatch window2，公开保守arrival为t+10，不能覆盖任何H10日期。历史失败不是搜索不到E：原诊断已经显示P2增加量和缓冲但不保证日期，P3辨别日期却缺少可释放的远期责任。本轮保留此诊断及旧H5/H10/H20结果，不调参数消除失败。

## 2. firm与visibility为何分离？

firm H固定10；H5/H20只是明确敏感性控制。visibility=H+当前known保守供给lead最大值，同时包含已知B→C明确promise时延。Normal原fixture的A/D route lead为2/4，因此保守lead4/6、visibility16；并未把D改成2。Wide E被发现后visibility20，但firm仍t…t+9。尾部允许看到采购应准备的材料，不能宣称企业已承诺那些日期产出。

## 3. projected是否冒充产出？

尾部用当前观察的20日需求率、当前backlog、recipe和capacity生成，保留basis、created/revised day、数量和绝对need-by。表示为`RequirementBucket(requirement_class=PROJECTED)`，bucket ID即稳定requirement ID。生产统计只取原firm ProductionPlan；projected从不进入plans、不产生Demand/Order/goods、不可以被consume当作当日产出。尾部C材料基于capacity-bounded run rate，B煤材料再受B产能约束；这是材料准备投影，不是完整工厂排程。

## 4. stable bucket是否消除每天滚动的第二份责任？

key为producer/commodity/need-by/class。每日绝对日期只有一个当前状态。PROJECTED进入firm窗口时移交原qty/created day，替换旧class；不会额外加一份qty。Normal X1 600日有2428个历史class ID、1230个绝对日期ID、37200条修订，但日末最多18个firm和12个projected。两次日内重规划都会归档修订，归档数不是新增责任数。80→100只增加20缺口；accepted80下80→50留下30 excess。订单不会随bucket退役消失。

## 5. release-by是否解除边界耦合？

`release_by=need_by-(current_quote.expected_arrival-today)`；还要求quote是今日、arrival<=need-by且release_due。Wide X1 Day18的E quote arrival28，`B:coal:28:PROJECTED` gap80在Day18释放并真实接受80；firm最后一天是27。H5也能释放长lead尾部。lead9/10/11接口probe分别visibility19/20/21，今日释放的bucket类别FIRM/PROJECTED/PROJECTED，没有lead<=H的采购门槛。

采购还必须在`max(原safety320, 当前visible requirement)-真实supply exposure`内。沿用原safety与plan的MAX并集，并用正量到期及时gap开启采购；没有把tail变成新safety target。UNKNOWN/late余额不覆盖日期但占真实exposure。不存在任何档案扫描后凭空“释放”已接受量。

## 6. 正式39×600日结果

A–L与恢复R各三策略；C/D为H5/H20，其他H10。M另经真实12日世界结算。下表为最终backlog，非correctness断言：

| 场景 | X0 | X1 | X2 |
|---|---:|---:|---:|
| Normal | 0 | 0 | 0 |
| Original Wide H10 | 1268 | 0 | 0 |
| Wide H5 | 1272 | 0 | 0 |
| Wide H20 | 0 | 5 | 5 |
| Mixed lead | 1832 | 0 | 0 |
| Demand step-up | 6 | 141 | 141 |
| Demand step-down | 0 | 0 | 0 |
| Temporary spike | 0 | 0 | 0 |
| Physical 7.5/day | 1450 | 1454 | 1454 |
| C capacity8 | 1200 | 1200 | 1200 |
| B steel capacity30 | 1468 | 1468 | 1468 |
| Stale A80 / D60 | 1458 | 1459 | 1467 |
| Shutdown/recovery | 0 | 0 | 0 |

Wide E累计采购X0/X1/X2为1480/46140/46140，最后200日X1/X2 delivery均值10。原搜索算法和目录参数不改；新need触发时机有变化：E发现日X0=12，X1/X2=18。因此另固定Q0、E17被动信息、原Wide实体fixture运行三组600日：backlog1270/0/0，E采购1460/46158/46158。此对照支持释放责任的因果解释；不会将正式矩阵发现日期差异隐去。

## 7. X1是否被unallocated卡住？

机制专项确实证明UNKNOWN80对visible80形成零headroom，虽有timely gap也不再买80。正式L的A80一直pending且UNKNOWN、保留80煤unallocated；但当前可见责任足够大，正timely gap且coal exposure room=0的日数为0。所以不能把L的1459全归因于exposure锁死：D真实60 coal/日只支持7.5 machine/日，C的旧S0钢订单也可长期无可信日期。X1没有自动取消；真实未分配订单仍可压缩空间，但此矩阵未出现完全锁死的煤headroom。

## 8. X2改善和代价是什么？

L只发生1次取消请求，确认取消80、替代80，最终backlog1467反而高于X1的1459；最后200日仍7.5/day。早期供给/订单排队路径改变带来服务损失，取消不创造D运力。本轮未观察到大量cancel/reorder，未加cooldown掩盖。其余正式场景取消0。

stale须未发、overdue/unpromised、无法当前/未来可见日期分配、有known正量及时alternative且释放后不超exposure。候选保守要求不同supplier，沿用既有替代语义；同一supplier重新承诺未研究。C仍原B单供应商S0准入，不能满足不同supplier替代条件，X2不会暗中获得第二钢源。确认前旧pending仍占exposure，reservation只防同一prospective gap被再次占用；确认后ticket上限为真实cancelled，替代仍需今日offer、到期gap和空间。

## 9. H5/H10/H20的库存、在途与暴露

| Wide策略 | 最终backlog | 最终煤position | pending | in-transit | 煤position峰值 | B煤库存峰值 | C钢库存峰值 |
|---|---:|---:|---:|---:|---:|---:|---:|
| H5 X0 | 1272 | 320 | 120 | 200 | 320 | 272 | 118 |
| H5 X1 | 0 | 640 | 0 | 640 | 760 | 272 | 111 |
| H5 X2 | 0 | 640 | 0 | 640 | 760 | 272 | 111 |
| H10 X0 | 1268 | 320 | 120 | 200 | 436 | 256 | 130 |
| H10 X1 | 0 | 640 | 0 | 640 | 710 | 256 | 76 |
| H10 X2 | 0 | 640 | 0 | 640 | 710 | 256 | 76 |
| H20 X0 | 0 | 424 | 92 | 332 | 1260 | 400 | 412 |
| H20 X1 | 5 | 654 | 0 | 654 | 704 | 248 | 76 |
| H20 X2 | 5 | 654 | 0 | 654 | 704 | 248 | 76 |

X1/X2的H5/H10最后煤暴露640主要是实际在途，不是target320被改写。H20最后200日delivery9.975、production9.925，仍有库存/钢pending与日粒度补货的周期波动；其Day131出现20日backlog零窗口不等于永久恢复，Day600仍5。Normal X1/X2没有额外煤position膨胀：峰值382对X0的576；但钢缓冲峰值80对旧320。这种缓冲差异有后续服务代价。

## 10. step-down excess是否真实？

X1/X2出现steel excess最大71；existing real supply没有删除。需求率只在Day100收到变化后逐渐下降，Day119变成5。Day600煤position232、钢on-hand80、原煤pending40/transit160仍真实存在。反向修订专项accepted80→需求50保留80 supply并标记30 excess，未取消在途或生成退款。Spike最后backlog0也不能掩盖先形成远期承诺的风险。

## 11. mixed lead如何分工？

原mixed的短A route2、长D route8，保守arrival4/10。Day1长D接受80去覆盖Day11 projected；短A只能覆盖其公开时延可行的早期bucket。实际daily allocation逐lot检查arrival<=need-by且used<=lotqty，未将长供给塞入过去需求。四lead接口probe按A2/D4/E8/F12到货分配need+2/+5/+9/+13，数量各20；这是公开quote/allocation接口，不是四个新增实体supplier。

## 12. 部分取消是否保留旧在途？

M真实Day0接受A80；Day3请求取消80且原FIFO发运30，arrivalDay5；Day4仅确认50。D Day4替代50，原30按期到货。旧订单最终ordered80=delivered30+cancelled50，pending/transit0。无提前替代、无取消shipment、无复制生产或伪造事件。M所有商品与订单残差0。

## 13. 物理与产能短缺仍失败吗？

是。I三策略末backlog1450/1454/1454，J均1200，K均1468；原7.5 machine/日网络或C8/B30不能被projected修复。采购与tail受已知recipe/capacity和真实exposure约束，不随backlog无限扩大。Step-up Day100需求15，Day119观察率15；新策略后来达到15/day，但C已满产没有余力清早期141，而旧P3较大钢缓冲只留下6。这是服务/缓冲取舍，不是通过测试宣告最优。

恢复R须拆开缓冲和恢复行动：Day49 X0煤160/钢320，X1/X2煤80/钢80；停运期间后者先耗尽。Day80后都有C>10且不超过15的真实生产，X0连续20日backlog零窗口Day125，X1/X2 Day139。独立20日production/delivery均值>=10窗口从Day80起成立，不能写成全链恢复。较慢清欠含更小的停运前缓冲影响，不能全归因于恢复后release。

## 14. 五阶段与共享材料日期是否成立？

复用原RecipeGraph，最终Day50 quantity3、传递lead2/3/4/1，上游required6/12/24/48，采购lead3/5/7/11分别releaseDay46/40/35/29，每个release不晚于对应need-by。原branching/shared-input/multi-sink继续回归；同一lot跨日期/producer bucket也不得双分配。此证据只证明接口时序传播，五阶段尚无完整实体生产/交易世界。

## 15. performance随什么增长？

决策用active buckets × live supply lots；offer查询用known candidates；X2额外扫描当前unallocated列表。report archive只追加、lookup，不遍历历史plans/orders/revisions做决策，抛异常的archive容器专项覆盖真实12日step。原世界source/account/export仍依赖实体源数量，未隐藏全世界成本。

Normal X1：18 firm+12 projected，37200 revision、99000 release checks、920080 allocation candidates；Wide H10 X1：18+20、46520 revision、168960 checks、2408182 candidates；H20 X1 candidates6452776。L X2 stale checks29796。正式fixture没有可信ETA变晚后触发的forward事件，人工迟到及UNKNOWN→late-cargo专项验证forward重分配；不把正常滚动分配迁移计成delay事件。

完整39组simulation/planning/observation/archive时间见execution_log（89.297秒，排除export；并发本机测量不是性能SLA）。tracemalloc Normal X1 peak99389625 bytes，Wide X2 peak124331792 bytes；含保存逐日revision/quote/allocation等报告档案，不是RSS。监测下daily字节与无监测相同。active工作有界，档案内存仍随天数增长；本轮没有改成数据库/index scheduler。

曾发现split pending/cargo共享诊断lineage导致正常误报7185次forward；现按lot及上一边界pending ancestry分别记录，正常计数0。所有39 daily除诊断计数外完全一致，plans/deviations/requests/order traces/disposition直接字节一致，见corrected_diagnostic_defect.json。没有通过改变经济轨迹修漂亮结果。

## 16. Gate与下一轮

`EXECUTABLE_PLANNING_GATE = PASS`，依赖45项correctness及完整矩阵重放，不依赖“X1 backlog更小”断言。检查firm/projected分离、H外long-lead释放、stable revisions、严格日期单次allocation、晚到仅向可行未来分配、UNKNOWN真实去重、confirmed cancel上限、在途保留、mixed与五阶段接口、账目和未来信息prefix隔离。通过只支持扩大研究网络，不能证明模型经济真实，也不保证每张firm计划有工厂级可执行排程。

建议下一方向 **Multi-Firm Production Network**：释放与协调接口已有时序基础，需要把多个真实buyer/producer放入同一库存/运输承诺竞争网络，而不是继续接口拼接。第一组应保留本轮step-up与低缓冲恢复失败，加入共享supplier承诺和中间钢生产约束。Production Scheduling当前没有独立capacity-leveling主因证据，不作为默认下一轮；Pricing/Household缺口也未被本轮证明。正式WWO应用需要另行研究/批准。

剩余结构限制：C的S0钢准入无法保证产出；tail是量/日期投影而非完整上下游排程；bucket allocation贪心且会重匹配，不是supplier reserve或优化器；以当前保守lead形成exact release日，尚无工厂准备提前量；single steel source无法X2替代；未测试真实多buyer竞争；档案内存线性增长。本轮停止，不自动启动下一轮。

## 历史summary SHA-256

- Round2: `02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02`
- Round3: `070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae`
- Round4A: `7522b9313a1aa47c60943029c4aff3f8869657f67c98d11502a1d064e1249b55`
- Round4B: `afccc372d5ec721a31b3a39f507ce65f0eb1e73e6e791cd231aabc2048e1897f`
- Round4C: `37624a453a9563da0732fde9b13f5c81a58b3c9b3f7e69a0f7a30328cfab0f8a`
- Round5: `4841f66e3eebe6773f77fe25edb5606030668e4c357b4ebf77fb43984a9acf77`

Round5B summary: `8768ac91cdd7db8eee354f1cd0591808e7ee4fff1e89637c990af8bf8e338016`。
