# Round4A — Supplier Admission & Available-to-Promise

本轮实际实现请求/订单分离、S0/S1 准入、运输承诺槽和一日取消确认。
正式矩阵为 10×600 日，另有 C1–C4 取消专项及 10 日供应商缺货反证探针。
S1 减少不可履约承诺，但五种条件的实体轨迹与 S0 完全相同。
Round4B Gate：**PASS，限研究接口与账目约束**。这不是 ATP 的经济有效性批准。

## 基线、命令与可追溯性

PR #2 head 为已验证 `4212492508895eff89076d661af0d926af45911b`，两个
CI SUCCESS，MERGEABLE/CLEAN，无 review 或未解决 thread，账号 ADMIN。
用户本轮明确授权后，实际合并于 2026-10-07T07:41:57Z。
main 为 `42e2ad240716901b6ec0684f3ec4abbe0dc9be31`；GitHub 签名 merge object
与本地 SHA、tree 均核对。annotated tag `economy-lab-v0.3-order-commitment`
对象 `784458cc38dd4bad406de51a37034f5b189b147a` 指向该 main，message：
`Verified Round3 order commitment and disposition research baseline.`
分支 `research/supplier-admission-round4a` 从该真实合并 main 建立。

实施前后运行以下统一入口；Python 3.12.14，全部 exit code=0。
详细实际绝对命令、版本、平台、退出码在 evidence 的 pre/post 验证 JSON。

```sh
python verify_baseline.py --output-dir .local/round4a-pre
python verify_round3.py --output-dir .local/round4a-pre
python economy_quantity_lab/supplier_round4a/run_supplier_admission_experiment.py --output-dir .local/round4a-frozen --execution-log .local/round4a-frozen-execution.json
python economy_quantity_lab/supplier_round4a/run_supplier_admission_experiment.py --output-dir .local/round4a-frozen-memory --execution-log .local/round4a-frozen-memory-execution.json --measure-memory
python verify_baseline.py --output-dir .local/round4a-post
python verify_round3.py --output-dir .local/round4a-post
python verify_round4a.py --output-dir .local/round4a-post
```

本机实际使用 `C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`。
原 8 项、Round2 9 项、Round3 18 项检查通过；原两组 200 日、33×600 日
保持既有复现政策：156 来源文件不变，105/139 输出直接相同，34 个 Windows
生成 JSON 仅 CRLF→LF 兼容；Linux CI 要求旧 139 文件全部直接匹配。
Round3 两次各 59 文件直接相同；Round4A 29 项检查、两次各 44 文件直接相同。
带 tracemalloc 与不带的 Round4A 输出也全同。

| 输出 | SHA-256 |
|---|---|
| Round2 summary | 02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02 |
| Round3 summary | 070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae |
| Round4A summary | 7522b9313a1aa47c60943029c4aff3f8869657f67c98d11502a1d064e1249b55 |

`evidence/hash_manifest.json` 冻结全部 44 输出；manifest 记录 11 个输入/源码
hash，原请求保存于 inputs，原附件字节与仅 LF 规范化的 hash 分别记录。
完整逐日、所有请求及槽前后快照、订单事件进入忽略目录与 CI artifact；
Git 保存 summary、选定日证据、专项、manifest、性能及验证记录。

## 请求、准入和承诺槽

原 `Simulation.procure` 直接将目标差额交给 `accept_order`，所以“想买多少”
与“供应商答应多少”在原路径中相等。PurchaseRequest 有稳定 request ID、
买卖方、商品、数量和日期，响应明确接受、拒绝、理由、订单 ID、承诺数量和截止日。
只有 accepted>0 进入原订单创建路径；accepted=0 没有零量订单或虚构货物。
每日/每请求检查 requested=accepted+rejected。

S0 全接受，复现五个对应 Round3 R0 的原逐日数量、订单事件和承诺事件。
S1 接受 min(requested, ATP)，其余以 TRANSPORT_ATP 拒绝。S1 中 promised=accepted，
deadline=接受日+2；当天及未来两天共三格，用当前 capacity 对三格报价，最早格优先。
既有未完成、未过期槽由全部请求共享；本日已经真实发出的量也占用本日运力，
避免日内发运后再次向本日满额承诺。槽证据分别输出 committed 与 dispatched。

运力改变后，旧承诺不能抹掉：旧占用可能高于新的当前报价，这种格剩余为零；
每次新增占位不得超过该次报价的剩余格。已过期格退出 prospective ATP，旧订单仍存在
并可 overdue。承诺槽不是调度器；原 FIFO、库存和真实 capacity 决定发运，
可提前完成承诺，实际发出或确认取消才释放对应未完成占位。
这不是未来 capacity 查询，也不是库存/生产预测。

专项中：capacity50、三格已有100占位，ATP50；请求80→接受50/拒绝30，
新 Order 只有50，买方 need 从80降到30。连续请求80/80/80→接受80/70/0，
三格各50，无新增超卖。两个未来分叉世界 Day1–99 请求、槽、ATP、接受/拒绝、
真实取消、need 和实体轨迹一致，运行期 guard 也拒绝非当前日 capacity 查询。

## 正式矩阵的结果

除 overload 的终端需求改为15，全部使用同一原 fixture、固定 target320、
运输 lead2、原配方/生产 capacity/C steel 规则和阶段顺序。
只对 B coal 准入做处理。normal100；shock 在50–79为30；shutdown 从50为0；
full_shutdown 在50–79为0，80恢复100。主矩阵没有自动逾期取消规则：
本轮隔离准入效果，显式取消在独立 C1–C4 和 prefix 测试中调用。

| 场景 | 策略 | 累计请求数量 | accepted | rejected | 部分接受/全拒次数 | breach订单/数量 | backlog峰/末 |
|---|---|---:|---:|---:|---|---|---|
| normal | S0/S1 | 47920 | 47920 | 0 | 0/0 | 0/0 | 0/0 |
| shock | S0 | 47920 | 47920 | 0 | 0/0 | 29/1040 | 148/0 |
| shock | S1 | 53380 | 47920 | 5460 | 29/0 | 0/0 | 148/0 |
| shutdown | S0 | 4160 | 4160 | 0 | 0/0 | 4/320 | 5440/5440 |
| shutdown | S1 | 179680 | 3840 | 175840 | 0/551 | 0/0 | 5440/5440 |
| full_shutdown | S0 | 47920 | 47920 | 0 | 0/0 | 4/320 | 260/0 |
| full_shutdown | S1 | 57060 | 47920 | 9140 | 1/30 | 0/0 | 260/0 |
| overload | S0/S1 | 60020 | 60020 | 0 | 0/0 | 0/0 | 1470/1470 |

累计 requested/rejected 是请求流量，**不能当作独立最终需求量**：相同未满足 need
可以次日再请求。shutdown S1 最终 open_need=320，而不是累计拒绝175840。

正常 S1 全接受，没有不必要拒绝、breach 或 backlog，与 S0 完全相同。
shock capacity30 后 S1从共享三日剩余槽部分接受，29次部分接受；日末最多4个活动
订单，S0为11。每日边界详见 selected_daily.csv，完整 requests.json 提供分槽证据。
拒绝不能降低 need：shock S1 日末 need最高200。

capacity0 后 S1 新请求全部 ATP0，全拒551次，没有制造新 accepted pending。
期末 pending=0、overdue=0、open_need=320；S0 pending=overdue=320、need=0。
两策略都实际停止供料与生产，末 backlog5440、machine-days1482400。
S0 本身也没有无限队列，因为真实 pending 去重；S1消除没有运力依据的新接受承诺，
并显示未满足 need，不夸称纠正 S0不存在的无限队列。

恢复后 S1 再接受新请求。两策略物质恢复日相同：shock 20日连续 production/delivery
匹配正常从142开始，backlog清零窗口141，pending154，仓内及在途156。
full_shutdown 对应187/187、186、199、201/201。S1 overdue从80为零，
S0 shock从82、full_shutdown从83；不代表整条供应链在80恢复。
承诺改善没有提高发运能力，因此没有物质 overshoot 或更快清 backlog 的证据。

overload最后200日交付均值12.5，两策略末 backlog1470、machine-days433062。
**S1没有拒单，也没有违约。** 买方目标补货响应实际投入耗用；煤炭运输限制生产，
目标差额随之被限制在真实消耗约100/日，而非把120/日终端需求直接作为采购请求。
该场景暴露长期终端能力不足，却不能证明当前采购规则把全部潜在需求转成请求。
零拒单、零 breach 不等于满足15/日服务，有限 ATP 也没有解决长期不足。

## 取消确认与旧在途去重

CANCEL_REQUESTED 是 pending 标签；默认一日后在原 B 采购边界确认。
请求时账、槽和 need 不变，可按原 FIFO 发货；确认重读 pending，
只移未发的请求部分至 cancelled。shipment 继续原 receive 路径。
新接口禁止立即 cancel_pending；confirmed 通过既有 Round3 的 pending-only
账目方法结算，不复制物质结算。部分取消按请求时 pending 的前部解释。

| 案例 | 请求取消 | 等待期发运 | 确认取消 | 已不可取消 | 等待期need | 确认后need |
|---|---:|---:|---:|---:|---:|---:|
| C1 | 80 | 0 | 80 | 0 | 0 | 80 |
| C2 | 80 | 30 | 50 | 30 | 0 | 50 |
| C3 | 80 | 0 | 80 | 0 | 0 | 80 |
| C4 | 80 | 0 | 80 | 0 | 0 | 80 |

四案等待期都没有重复替代请求；C4确认后产生新的80订单，旧订单不复活。
C2的30一直计在途；只重新请求50，30到货后转库存，need仍为0，未再次计30。
补充检查覆盖“部分取消40、等待发30→只确认10”和“80全发→确认0”。
专项使用明确小 fixture（B库存240及指定capacity），与正式同初始矩阵分开记录。
确认不产生shipment或物资；恒等式保持 ordered=pending+in_transit+delivered+cancelled。

## ATP 信息价值与反证

相比只事后报告 breach，ATP给出当前接单数量与拒单理由，slot防止多个新请求
重复使用运力。它把运输约束放在接受之前，却不能验证实际可供货数量。
独立10日探针令 A煤库存及产能为0，线路仍100：S1接受320，发运0，四张订单
breach共320。没有凭空供货，同时明确否证“运输槽足够就是可履约”。
这是策略适用范围缺口，未添加 MRP、预测、库存承诺或第二供应商来掩盖。
突发运力下降、供应商库存不足、上游生产不能及时完成、旧逾期FIFO阻塞新承诺
仍可能破坏运输-only promise；不能从正式场景的零S1breach排除这些情况。

## 性能与可扩展边界

无内存追踪时十个600日模拟及观察合计约1.07秒，单案约0.057–0.134秒，
不含导出；不能推广为全球模拟性能。tracemalloc改变耗时，单列日志。
shutdown S1峰值 Python新分配4407684字节，S0为3372520；包括请求、事件、逐日
档案，不是 RSS，也不是算法工作集。更多拒单档案仍有存储成本。

每个 admission 前瞻槽至多3个；正常日末为0，不代表从未占槽。
summary分别记录日末与admission时槽峰，shock/overload接单时均达3。
请求同步响应，active_requests日末为0；异步 cancel requests另记。
shutdown S1活动订单整个600日最多2个（停运前在途），期末0，不随拒单增长。
请求档案 Day100/300/600为99/299/599条。

观察器每日为了导出本日请求扫描整个请求档案，599请求场景累计179700次，
Day100/300/600单日99/299/599次。**观察成本随历史请求增长，累计二次复杂度**。
核心准入没有扫描所有历史订单；槽/订单分配按当前占用处理。
原引擎账目/库存/FIFO有自己的遍历，counter不代表所有Python循环次数。
order_scan_visits仅为继承的A_B/B_C承诺分类，slot_scan_visits为槽报价/释放，
request_archive_scan_visits为本日过滤的单次档案扫描。取消历史扫描另列。
本轮保留量化该观察问题，没有改写为数据库或scheduler。

## Correctness 与 Round4B Gate

29项检查覆盖 S0全轨迹、拒单/部分接受、共享槽、当前信息guard、含实际取消的
99日前缀、保守替代、部分/全发后确认、在途/到货去重、取消不造物、原settlement
方法继承、商品/订单账及确定性。旧8+9+18与历史复现继续通过。
这些证据支持所列实现约束；有限测试与零残差不证明经济模型真实。

Gate **PASS**：请求/响应明确，S1接单有运输边界，partial成立，新增槽未超卖，
request/confirm分离，未确认不重复替代，在途去重，拒绝保留need，未来隔离及
已检验账目成立。目前没有未解决 correctness blocker。
建议下一轮设计 Round4B 两供应商发现、匹配与切换，复用这些接口，保留缺货探针及
transport-only ATP标识，并明确候选供应商真实可供货约束。
不批准当前S1正式采用，不声称下一轮必然改善供货。未实现搜索、排序、第二供应商、
价格、资金、预测、完整企业ATP或WWO集成。本轮结束，不启动Round4B。
