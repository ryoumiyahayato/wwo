# Round3：订单履约承诺、逾期识别与处置实验

本轮实际完成 14 个独立 600 日场景，共 8,400 场景日。R0/R1/R2 在本轮四种
供给条件下的实体库存、生产、发运、到货和终端交付逐日完全相同；订单承诺、
采购、取消和队列明显不同。持续停运下 R1 的未发订单膨胀，R2 的取消重订没有
创造供给。这些是当前单供应商与固定阶段规则下的有限实验结果，不是通用定理。

## 真实施工基线与 provenance

PR #1 的两个 CI 均 SUCCESS，review 列表和未解决 review threads 均为空，
mergeable=MERGEABLE、mergeStateStatus=CLEAN，账号权限 ADMIN。按用户在聊天中
明确授权合并，实际合并于 `2026-10-07T06:05:16Z`。此前附件中的“不合并”限制
被该直接授权覆盖，没有将附件本身作为合并授权。

- 实际 main merge commit：`60278ee7f1703ef5aec6cb7933a2bcf6073e1038`。
- 基线 annotated tag：`economy-lab-v0.2-baseline`，tag object
  `ef8a8aa86ebe2225077ff8ca31fca4559315992d`，指向上述 main。
- 标签于本轮较早阶段按当时指令创建，实际 message 为
  `Verified quantity-economy inventory comparison baseline before order disposition research.`
  后续用户消息给出另一条推荐 message；已发布的正确基线标签予以保留，没有重写。
- 分支：`research/order-commitment-round3`；`ROUND3_BASE_STATUS=MERGED_MAIN`。
- 同步 main 时核对 GitHub merge 的签名 payload、Git object SHA 和 tree SHA；
  使用 GitHub API 克服本机 Git smart HTTP 的连接限制，没有 force push。
- 原 156 文件、H0/H1、fixture、Round2 报告和正式结果均未修改，未改 source manifest。
- 原始附件保留为 `inputs/ROUND3_REQUEST.md`，SHA-256：
  `8e944235767010496c14130f75efd3d020ecd7f18d114a32525e3b451696e88d`。
  后续聊天明确授权合并并补充 promise_status、采购缺口、每日扫描和内存指标。

实施前后都运行 `verify_baseline.py`：原 8 项及 Round2 9 项通过，原两组 200 日与
33×600 日实验通过，所有来源 hash 保持。Windows 105/139 输出直接逐字节一致，
34 份生成 JSON 按既有 CRLF→LF 兼容政策一致。Linux CI 要求旧 139 输出直接匹配。
前后实际命令、版本、exit code、hash 在 `evidence/pre_baseline_verification.json`
与 `evidence/post_baseline_verification.json`，并标明 commit / branch。

## 语义与实现边界

accepted pending 是供应商已经接受的采购余额，尚无对应货物发运，不是仓内物资，
也没有 shipment ETA。原事实账保持 `P=on_hand+in_transit+pending_dispatch`。

每张订单的 sidecar 保留 accepted_day、promise_window_days 和明确的
promised_dispatch_by_day。promise_status 从当前日与剩余 pending 推导并在订单
事件中导出，避免独立维护一份可变的、会过时的状态缓存：PROMISED、DUE、OVERDUE、
UNPROMISED、NO_PENDING。NO_PENDING 只表示没有待发部分；在途部分仍有真实 ETA。

默认 promise window=2；接受日+2 是最晚发运日，截止日结束仍是 DUE，下一日才
OVERDUE。无 promise 的 deadline 为 null，任何等待年龄都不使其自动逾期，
未发余额继续按 legacy 计入可信供给。期限没有读取未来运力、冲击结束或实际发货日。

- R0：effective position=P，不做处置。
- R1：仅从采购决策的 effective position 排除 overdue pending。真实订单、
  未发余额、原 FIFO 均保留；没有 cooldown、上限或隐形取消。
- R2：在 B 采购边界显式取消 overdue pending，记入 sidecar cancelled，然后
  按同一 target 向原供应商重新计算采购。新订单有新 ID，进入原 FIFO 尾部。

处置边界为原“生产→终端交付”之后、B 采购之前、原发运之前。截止日当日的原发运
机会完整保留。只有 A→B coal 采购采用 R1/R2；B→C steel 维持原采购规则，其承诺
仅观察。两条链都建立真实 commitment metadata，但不能把两种商品数量混成同一账。

没有修改 `economy.py`。`CommitmentSimulation` 是窄继承适配器，step、receive、
production_plan、produce、dispatch 都直接继承唯一原实现。原 accept_order
创建 ID/索引/FIFO/接受事件后，仅将新订单表示适配为引用取消 sidecar 的 Order
子类；没有复制订单引擎。取消只扣 pending，不改变 ordered_quantity、货物、
shipment 或 ETA。被取消但仍在途的订单直到实际到货后才移出 active 索引。

每个订单与每条链逐日验证：

`ordered_quantity = pending_dispatch + in_transit + delivered + cancelled`

cancelled 单调累加，新订是新的 order_id。商品账仍由原 Simulation 检查，取消
不进入物质恒等式。R0 的 cancelled=0，退化为原检查。

## 矩阵、口径与正常供给

固定 H1=80×(2+2)=320，C steel 规则、初始 fixture、配方、产能、时延、每日需求
10 和阶段顺序均不变。没有扫 buffer 或调宽 promise window。

| 组 | A→B capacity | 策略/控制 | 数量 |
|---|---|---|---:|
| A normal | 始终100 | R0/R1/R2 | 3 |
| B shock | 50–79日30，其余100 | R0/R1/R2 | 3 |
| C shutdown | 50日起0 | R0/R1/R2 | 3 |
| D full_shutdown | 50–79日0，其余100 | R0/R1/R2 | 3 |
| E no_promise | B和C同容量 | R1，无promise，fallback legacy | 2 |

全部 ID 都实际运行，无结果别名。正常三策略的煤订单599张、累计采购47,920，
promise breach/取消/积压都为0，末日 B coal 仓内160、在途160；没有无理由处置。
两条链所有终态订单、shipment 时延、active/FIFO 索引也实际复核。

breach count 是在采购边界第一次发现 overdue 的不同订单数；breach quantity
是该订单首次违约时的剩余 pending，每张只计一次，不是逐日重复累加 overdue。
日末 overdue/oldest age 在发运和取消后读取，因此 R2 的日末 overdue=0 不能
解释为没有违约。daily 同时保存处置前 overdue、决策前后 position、采购缺口、
新订、取消订单数、重订次数及期末状态，event evidence 保存完整选中订单生命周期。

## 首次区分订单存在与近期供给不可信

持续/临时全停运中，order 98 接受于第50日、承诺最晚第52日，第53日首次违约，
80 pending 仍是真实订单。R1 第53日日末 P=400，effective=320；第600日 P=58,720，
effective仍320。R0则长期 P=320，没有用信任过滤解除补货阻塞。

30容量冲击中，首个 breach 是第54日 order 100：第51日接受80、承诺第53日。
第54日采购边界 pending40、in_transit30、delivered10。R1 据此额外采购40，
当天新订120对R0的80；但仍未删除原40。R2显式取消这40，保留在途30与已到10。
完整因果事件见各组 `evidence/*/event_evidence.csv`。

## 实体结果：订单变化没有改变本轮供给

| 条件 | R0/R1/R2 backlog峰值 | 期末backlog | machine-days | 清零20日窗口起点 | C产量等于正常20日起点 | 全仓内等于正常20日起点 |
|---|---:|---:|---:|---:|---:|---:|
| 正常 | 0 | 0 | 0 | 不适用 | 不适用 | 不适用 |
| 30容量临时冲击 | 148 | 0 | 6116 | 141 | 142 | 156 |
| 持续全停运 | 5440 | 5440 | 1482400 | 未发生 | 无恢复阶段 | 无恢复阶段 |
| 临时全停运恢复 | 260 | 0 | 16926 | 186 | 187 | 201 |

统计不只比较均值：`evidence/physical_comparison.json` 对每个600日的三处库存、
生产、实际发运/到货/在途、终端交付/积压与原累计物质量进行逐字段比较。
每个 R1/R2 相对同条件 R0 的 differing_days 均为空。
这不是测试里强迫策略表现相同，而是本轮实际运行后归档的观察。

煤待发余额匹配正常基线的20日起点，临时30冲击全部为154，全停运恢复全部为199；
煤在途恢复分别156、201。日末 overdue=0 的20日起点却不同：30冲击 R0/R1/R2
分别82/144/80，全停运恢复为83/189/80。这明确区分承诺账清理与实体恢复。
所有窗口至少连续20日，另输出窗口之后最后不匹配日；不证明永久稳定。

## R1：持续停运中的订单膨胀与临时采购承诺

| 持续停运 | R0 | R1 | R2 |
|---|---:|---:|---:|
| 累计煤采购数量 | 4160 | 62560 | 62560 |
| 采购订单数 | 52 | 599 | 599 |
| 期末 pending | 320 | 58720 | 320 |
| 期末 overdue | 320 | 58400 | 0 |
| 最大活动/队列订单 | 4 | 551 | 3 |
| 最大overdue订单（处置前也计） | 4 | 548 | 1 |
| 累计取消数量 | 0 | 0 | 58400 |
| 取消过的订单数/重订次数 | 0/0 | 0/0 | 548/548 |

R1 第100/300/600日活动煤订单为51/251/551，未发5360/26720/58720。
稳定阶段每天新建一张订单，数量以80/160/80的三日循环增加，每三日再承诺320。
deadline=接受日+2使当日及后两日仍可信，随后过期触发下一轮。没有运输能力时
这些承诺变成历史未发余额，期末58400逾期、548日最老逾期。未加抑制器掩盖这一缺陷。

临时30冲击中，R1队列峰值22张对R0的10；第80日 P=2060、effective=420，
第80日以后 P 最大超target1760。全停运恢复中队列峰值31对4，P最大超target2980。
发运后的旧逾期余额变成真实在途，重新计入可信供给，所以日末 effective 可以
高于target；target只用于采购边界，不是每个阶段的硬上限。

600日内两种临时冲击的 R1 累计采购仍47920，与R0相同；多出的早期承诺后来
替代部分新订，没有观察到额外实体到货或仓内过量。第80日后 B coal 仓内峰值
都是正常160，未超过目标320。不能把“本轮没有库存overshoot”推广为R1永远安全。

## R2：取消保持账目，但未改善同供应商的物质供给

30容量冲击取消1760、重订28次；临时全停运取消2980、重订29次。总接受采购
分别49680、50900，减累计取消后均47920。持续停运取消58400、重订548次，
期末 pending 被保持在320、日末 overdue被清为0，但实体供给与5440积压不变。

取消记录与重新接受都是真实、不同的订单事件。取消不消灭在途物，不改变仓内，
没有 replacement priority；专门的FIFO测试保留一张较早非取消订单，使重订
订单排在其后。R2减少的是等待承诺的年龄与队列规模，不是运输约束；在本轮
临时恢复中也没有更快清积压或更慢物质恢复。即刻接受取消只是明确实验假设，
不代表真实合同、协商、执行成本或 WWO 最终规则。

## 无承诺控制、正确性与确定性

两个 no-promise R1 控制的原实体/订单事件与对应 R0 完全相同：deadline均null，
overdue和breach始终0。等待很久没有偷偷生成deadline。

原8+Round2 9+Round3 18项检查通过。新增覆盖明确截止边界、部分发运、无承诺、
R1只读账、取消限制、已到/在途保护、FIFO新ID、取消后到货与索引退休、逐日数量
和订单账、持续停运负向实验、三策略day1–99未来差异隔离、观察开关、重复运行、
采购缺口、扫描指标、原33场景关闭处置时完整轨迹等价与已发布CSV逐格等价。

Round3所有商品和订单残差最大绝对值0，没有发现本轮所列场景中的 correctness
defect。R1补单膨胀是候选策略缺陷，R2无供给改善是负向结果，不是为了变绿而修掉的错误。
所有R1/R2持续停运煤 shipment发运日都小于50；初始缓冲耗尽后B/C停产，没有物资凭空出现。

统一入口两次再生全部59文件，Windows直接逐字节/hash匹配；内存测量开关也再生
相同59文件。Round3新JSON和CSV明确LF，无换行兼容例外。完整输出在`.local/`或
CI artifact，Git仅保留summary、period、manifest、hash manifest、小型因果证据和执行记录。

summary SHA-256：`070ce92c76f6341d8ee9d1b484001ac0dad88e6280cabd8254808ee833f3d0ae`。

## 性能与内存观察

最终未开tracemalloc的14场景生成用时2.8565654秒，本机Windows Python3.12.14。
持续停运R0/R1/R2 run_case分别0.0583/1.1175/0.0693秒；只是一次本机小实验观察。

| 持续停运 | R0 | R1 | R2 |
|---|---:|---:|---:|
| sidecar分类扫描访问总数 | 8413 | 608526 | 6223 |
| 最大每日sidecar分类扫描访问 | 15 | 2204 | 11 |
| tracemalloc峰值bytes | 3869588 | 5122892 | 5450732 |
| 开tracemalloc时run_case秒 | 0.2998 | 5.8243 | 0.3835 |

`active_scan_visits`与每日计数只度量新增sidecar的分类遍历，不包含原引擎内部
balances、quantity/order checks的遍历，也不是全模拟CPU操作数。运行用时包含完整
run_case。R1第100/300/600日分类扫描量204/1004/2204，随活动队列线性增加。在持续停运里活动
订单本身近似等于所有历史未履约订单，所以累计扫描呈增长；日常分类、决策和
原账目检查只扫描active_orders，未改为扫描已经结束的历史订单。完整历史只在
结束后的导出/证据/最终检查时遍历，没有做大型性能重构。

内存是每场景run_case期间新分配Python对象的tracemalloc峰值，含模拟状态、
逐日观察与事件归档，排除事先构造的输入case，不是进程RSS。R2活动队列虽小，
却有548次取消/重订的历史记录；其归档内存高于R1，因此不能以队列小断言总体
内存更省。两次带/不带内存观察的全部输出hash一致，时间和内存放在非确定性
execution log里；这些数字不能推断WWO全球性能。

## 如何复现

仓库根目录，Python3.12标准库，无第三方依赖：

```sh
python verify_baseline.py
python verify_round3.py
python economy_quantity_lab/order_round3/run_order_commitment_experiment.py --output-dir .local/my-round3 --execution-log .local/my-round3-execution.json
python economy_quantity_lab/order_round3/run_order_commitment_experiment.py --output-dir .local/my-memory-run --execution-log .local/my-memory-execution.json --measure-memory
```

单独新增测试在`economy_quantity_lab/order_round3/`内执行
`python -m unittest -v test_order_commitment.py`。输出目录必须是新的；不得覆盖源证据。
实际完整命令和exit code在`evidence/round3_verification.json`，非确定性时间见
`execution_log.json`与`memory_execution_log.json`。

## 研究结论、缺口与Round4建议

promise提供“账上订单仍存在、但供应商承诺已经违反”的有用事实，最早可在第53/54日
区分；它不提供新货源、未来恢复日期或可靠到货ETA。R1展示失信过滤可制造无限增长
的重复采购承诺；R2展示显式处置可以保持原数量账并缩短活跃等待，但不能恢复运力。
单供应商环境中，这两种动作本身都解决不了断供。

本轮已足以说明值得进一步研究替代履约路径，但还不足以直接开展完整
Multi-Supplier Search & Switching：尚无买方已知可履约候选、供应商拒单/可承诺
数量语义，也没有取消确认延迟及切换过程中旧在途/新订采购去重的定义。
建议先定义这些最小事实与责任边界，再设计有界多供应商对照；不宣布R1/R2正式采用。

没有第二供应商、发现/搜索、价格、钱、信用、仓储成本、家庭、工资、银行、股票、
需求预测、随机冲击或WWO集成。Round2历史外部审计ZIP仍缺失，未声称运行其中脚本。
本轮只创建研究PR，等待审查，不自动合并或继续Round4。
