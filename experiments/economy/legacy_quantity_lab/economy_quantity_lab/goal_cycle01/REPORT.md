# WWO Economy Lab — Goal Cycle01

**GOAL_COMPLETE**

实际施工位置 `/workspace/wwo-economy-lab`；分支 `research/economy-goal-cycle-01`；BASE_SHA `334d3f546824415604b7645a91a61196fb2bad83`。真实 UTC 起始2026-10-07 16:22:30，十小时上限2026-10-08 02:22:30；本轮未重置预算。全部操作在本地，没有push、远端PR、合并、tag或WWO修改。

新增的是可运行的整数支付闭环、固定报价采购和一套局部报价反馈，以及流式档案和独立账目重建。没有银行、借款、利润优化或家庭模型。价格/资金与原料、产能、运输、日期和固定sink拓扑分别约束行为。

## 账目与比较语义

唯一 CashAccounts 持有余额和其中受限的reserved；FirmNode只引用自己的Account。S2接受原子锁定库存、运输槽、现金和单价，中间四处故障注入均完整回滚。dispatch不付款；真实arrival只按实际到货量与locked price付款一次。确认取消只释放尚未发出的价值；等待期间的发运仍保留对应资金。终端商品先验证可付数量并转账，再同步交付，不把backlog记收入。

N0是Round6 C1；N1保留完整旧排序/稀缺规则，只加统一商品价格与充足有限支付；N2用价格优先和完整旧tie-break，日期释放仍由原ReleaseBook约束；N3与N2的初价、现金、限价、网络及分配相同，仅更新新报价。旧订单不改价。N0/N1八个600日场景的每日物理汇总hash全部相同，另有100日完整原字段、requests/events等价检查。

资金非约束上界按每企业自身最大投入成本、实验天数、固定23日暴露余量及原库存/target设置，假设零销售收入；规模不增加单企业cap、buffer或资金设置规则。外部账户按声明期限最大需求×固定终端价设置。所有正式非约束案例实际CASH/TERMINAL_CASH拒绝为零。终点余额恰好为零可以是期限资金全部使用，不能外推下一日仍非约束。有限组只有20日初始资金规则，没有运行时补充。

## 主矩阵：每个模式600日

八个独立Round6 fixtures覆盖正常、煤稀缺、钢短缺、非对称需求、step-up、非对称lead/capacity、恢复和停产。固定sink拓扑反证由step-up J同时提供：C1自身8/day无法满足T1的10/day，C2剩余产能没有到T1的销售边；shutdown G另外保留。没有伪造独立拓扑fixture。

| 场景 | N0交付/积压 | N1交付/积压 | N2交付/积压 | N3交付/积压 | N3 T1/T2积压 |
|---|---:|---:|---:|---:|---:|
| normal | 6000/0 | 6000/0 | 6000/0 | 6000/0 | 0/0 |
| coal_scarcity | 6079/3521 | 6079/3521 | 6079/3521 | 6079/3521 | 1760/1761 |
| steel_scarcity | 4524/1476 | 4524/1476 | 4524/1476 | 4524/1476 | 738/738 |
| asymmetric_demand | 4582/1418 | 4582/1418 | 4582/1418 | 4582/1418 | 1418/0 |
| step_up | 7504/1001 | 7504/1001 | 7504/1001 | 7504/1001 | 1001/0 |
| asymmetric_lead | 6000/0 | 6000/0 | 6000/0 | 6000/0 | 0/0 |
| recovery | 6000/0 | 6000/0 | 6000/0 | 6000/0 | 0/0 |
| shutdown | 4772/1228 | 4772/1228 | 4782/1218 | 4779/1221 | 610/611 |

多数终点服务不变，但正常、step-up、恢复、停产的N2/N3每日物理汇总路径不同。固定报价在shutdown比名义control多交付10；动态报价比固定价少3。煤/钢/非对称需求中的N3与N2物理汇总轨迹相同，报价和现金转移仍变化。因此不能把所有改价都称实体改善，也不能只看终点backlog。逐企业库存、投入分配、现金/预留、停产连续性及逐sink详情见formal_a_summary.json与完整daily.jsonl。

## 长周期：每个案例真实3600日

| 场景/资金 | N2交付/积压 | N3交付/积压 | N3上下限命中 | N3最长连续无产出日 |
|---|---:|---:|---:|---:|
| normal/nonbinding | 36000/0 | 36000/0 | 0/428 | 11 |
| normal/finite | 200/35800 | 200/35800 | 797/0 | 3425 |
| coal_scarcity/nonbinding | 36079/21521 | 36079/21521 | 0/1316 | 2 |
| coal_scarcity/finite | 320/57280 | 320/57280 | 767/0 | 3438 |
| recovery/nonbinding | 36000/0 | 36000/0 | 0/428 | 11 |
| recovery/finite | 200/35800 | 200/35800 | 797/0 | 3425 |

持续煤80/day只支持约10 machine/day，外生需求16/day；资金充分仍积压21521。报价不能制造coal或绕过配方/运输。有限组终端账户耗尽，使正常/恢复仅支付200件、煤稀缺组仅支付320件；随后企业投入购买也受资金与预留约束，最长连续无产出超过3000日。现金向上游集中、终端账户耗尽都是无工资/税/分红等回流机制下的模型边界，不是应自动加入信贷的实现错误。firm未实施死亡/破产。

正常N3在600日尚无上限命中，但第609日D首次达到360（初价90的4倍），3600日共428次上限命中，末A报价49、D360。完好服务并不证明价格稳定。整数tick限制使低于50单位的2%步长为0，也不能把这类停步称理论收敛。有限组B1/B2到达下限（75/68），记录命中不隐藏clamp。

日期诊断额外执行1000日，使用与正式3600日案例相同的初始资金/配置；观察扩展后的前缀经济hash与正式档案相同，离线核对PASS。第610日A=49请求对应need_by614，而D=360请求对应need_by616；D两买方分别接受28/32、各物理拒绝8。长lead提前释放不同日期bucket，仍使D收到压力。它不是同一日期货源的纯价格需求弹性反证。此诊断不替代任何3600日或规模长跑，156条请求日期证据保留。

累计拒绝数量包含同一缺口/库存的重试：例如normal有限N3的TERMINAL_CASH累计5453246，并非新增消费。唯一需求看sink.received，真实收入看支付事件。反馈窗口按buyer+needID+原因去重，不能使用gross重试作新的需求。

## 规模：固定单企业参数、bounded degree

| 网络 | 企业/known边 | N2交付/积压 | N3交付/积压 | N2 sink积压范围 | N3 sink积压范围 |
|---|---:|---:|---:|---:|---:|
| S5 | 18/30 | 19709/10291 | 19717/10283 | 0–2156 | 16–2161 |
| S10 | 35/60 | 31995/28005 | 31995/28005 | 212–2056 | 334–1935 |
| S20 | 70/120 | 63962/56038 | 63962/56038 | 284–2231 | 284–2231 |

规模normal标签不代表总产能充分：S5/S10/S20的煤产能260/420/840分别只支持32.5/52.5/105 machine/day，而sink需求50/100/200。保留这些既有容量缺口，不能把扩大网络后积压解释为单纯算法成本或价格失败。

每个N2/N3均先20日smoke，再真实600日规模运行；S20沿确定性ring方法扩为10 raw/20 steel/40 machine，degree≤2。没有all-to-all，未提高单企业产能或buffer。S5总交付多8仍有部分sink变差；S10总量相同而服务分布不同。S20总量与sink终点不变，不能称规模收益或社会福利提高。

## 成本与观察边界

| N3网络 | planning/reconcile秒 | known/quote/update/allocation秒 | 物资/订单/资金结算秒 | 日志/metrics/archive/export秒 | 档案字节 | GC-tracked对象（结束） | 进程RSS高水位MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| S5 | 3.175 | 9.430 | 2.257 | 3.304 | 17491711 | 19766 | 66.28 |
| S10 | 5.606 | 18.319 | 3.715 | 5.849 | 34825697 | 21603 | 66.28 |
| S20 | 13.117 | 49.806 | 8.664 | 14.511 | 71142811 | 25330 | 71.12 |

以上是第一正式进程的实际hook边界时间，采购类含原子accept/资源预留，结算类计receive、取消确认、production、terminal pay、dispatch和account checks；reconcile也存在于production/procurement中。事件流写入时间与调用方重叠，四列不是互斥可加的CPU微基准。档案字节在case关闭后、summary/audit元数据写出前测量。RSS是Linux实际getrusage进程高水位，含之前案例，不能叫独立单案例峰值；GC统计不是所有Python对象。

compact保留当前日观察尾部并流式写事件/精简日报，退役closed runtime orders；full仅用于少量诊断；off关闭扩展日报/报价文件，仍保留最小审计事件。100日full/compact/off物理和资金权威hash相同，关闭价格观察器同样不改变行为。历史need identity/first-seen缓存仍随日期增长；未证明无限运行常量内存，也未在WWO或其他平台运行。

## 独立核对、反证与失败分类

offline_audit.py只依赖标准库，不导入模拟器的库存、支付或清算检查。它流式重建买卖双方现金、reserved、订单/shipments、锁价、确认取消、企业商品流量、配方及世界总量，检查terminal商品与现金匹配。所有42个有支付正式案例均核对；N0没有支付日志，依历史物理回归，明确NOT_APPLICABLE。七种日志副本破坏均被拒绝：重复付款、少卖方收入、到货超发运、取消在途、新价付款、同余额两笔预留、终端无现金。临时副本不污染正式证据；这不是第三方认证。

I01/I02是拒绝分类与日志字典实现缺陷，已修复并保留回归。E01–E05是探针假设错误；E06是规模资金上界设计错误，正式观察前更正并保存v1清单；E07是一次手工驱动器bootstrap/import顺序错误。第一次Round6验证重叠源码写入导致manifest-only差异，经济370文件一致；恢复精确BASE后两次371文件PASS。最终保持原strict verifier/golden不变，显式验证370冻结经济文件及唯一NetworkSimulation源hash变化。已在本地将未来CI路由到新完整入口，远端CI未执行。

所有不利模型结果、价格clamp、有限资金饥饿均保留。没有模型修订/参数搜索（主要候选local-window-v1，修订0/允许最多2）。资金不足、价格上限、物理不足、日期差异与销售拓扑没有混为一个市场改善结论。

## 验收与下一步

| 阶段 | IMPLEMENTATION_GATE | MODEL_RESULT | STAGE_STATUS |
|---|---|---|---|
| M0 | PASS | NOT_APPLICABLE | DONE |
| M1 | PASS | NOT_APPLICABLE | DONE |
| M2 | PASS | INCONCLUSIVE | DONE |
| M3 | PASS | MIXED | DONE |
| M4 | PASS | MIXED | DONE |
| M5 | PASS | NOT_APPLICABLE | DONE |

最值得保留的是原子支付+双账+N0/N1因果control，以及独立离线核对。N2可作为可解释固定价格benchmark；N3 v1不值得默认采用：多数服务不变、shutdown退步、分布代价混合、长跑价格触顶并可能被tick或clamp掩盖。没有福利、GDP或利润结论。

下一轮最小有证据方向是单独比较日期释放与价格排序的相互作用：先保留同一物理/资金边界，限定相同need identity与到货日期的已知offer对照，解释D长期高价压力是否来自提前释放/责任占用。它是建议，不在本轮继续实现，也不开始金融或家庭。

最终42新增正确性检查、264历史检查与全部历史经济回归通过。两个独立进程各50案例/66000日，合计100案例/132000日，84次正式离线重建PASS；353个经济文件及集合字节hash相同，性能日志排除在经济hash外。经济manifest SHA-256 `852447e45bfabac966ff1789962deb745cf08cbda418b69ca8d791997e19c9ba`。最终持久化验证时间2026-10-07 17:30:36 UTC；各子命令exit0，见evidence/final_verification.json。旧session35229完成后句柄过期，无实验中断或重复执行。

恢复入口：根目录GOAL_STATE.json/EXECUTION_PLAN.md；最小验证命令python verify_goal_cycle01.py --correctness-only；正式完整验证命令python verify_goal_cycle01.py --output-dir .local/goal-cycle01。完整原始档案位于/workspace/wwo-economy-lab/.local/goal-cycle01/final-verification-sze0jumd；导出包含补丁、bundle、报告、manifest、阶段证据及正式第一遍完整档案。平台下载入口以实际Library回执为准，不虚构PR/CI或下载URL。

LAST_VALIDATED_COMMIT: ae1e3b29b8e3437c55be4c4f82f44dad6be0d9b7（经济实现checkpoint；后续封存只改报告/evidence/CI路由，当前运行源码digest与两次最终重放相同；远端CI NOT_RUN。）
COMPLETED_MILESTONES: M0/M1/M2/M3/M4/M5
UNFINISHED_MILESTONES: 无必需阶段未完成
ACTUAL_RUN_COUNTS: final264历史+42新增；formal2×50案例/2×66000日；其中主矩阵64×600，长跑24×3600，规模12×600；另smoke6×20、dated诊断1×1000；详见evidence/actual_run_counts.json。开发失败两轮及来源摘要失败均保留，不能冒充成功执行。
FAILED_OR_NOT_RUN_CASES: evidence/failed_or_not_run.json（含远端CI、Windows、WWO及未跑的扩展矩阵）；正式必需案例无删除。
NEXT_ACTION: 读取`/workspace/wwo-economy-lab/.local/goal-cycle01/export/library_receipt.json`与`export_manifest.json`；在具备BASE_SHA的仓库执行git bundle verify economy-goal-cycle01.bundle，然后审阅DRAFT_PR.md与REPORT.md。若重新验证，用python verify_goal_cycle01.py --output-dir .local/goal-cycle01（新目录由入口生成）；本周期已结束，不自动开始下一轮或远端发布。
