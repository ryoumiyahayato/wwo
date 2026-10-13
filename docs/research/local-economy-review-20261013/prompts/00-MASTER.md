# WWO本地经济后续开发总提示词

请执行WWO经济后续开发。按依赖推进，一次只执行我本轮指定的阶段；未指定时执行01。先读 `D:/programs/WWO/handoff/economy-review-20261013/REPORT.md`、 `D:/programs/WWO/handoff/economy-review-20261013/prompts/README.md`、适用AGENTS.md，以及前阶段真实执行反馈。分项文件均在上述prompts目录。核对当前分支、未提交工作和实际文件。提示词已经准备好不表示本地已经执行完。

本地依据如下：

- 十五类仓库根为 `D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo`。主体是 `economy_quantity_lab/algorithm_completion/world.py` 的 `ProgrammeWorld`，继承同仓库 `economy_quantity_lab/network_round6/network_simulation.py`，继续复用 `economy_quantity_lab/economy.py`、 `economy_quantity_lab/multi_round4b/stock_admission.py` 和 `economy_quantity_lab/goal_cycle01/`。它是主要研究基础；较早的 `wwo-economy-lab` 和较窄的历史R2不能替代它。
- 正式宿主在 `D:/programs/WWO/wwo`。重点读取 `scripts/world/economy_r1_slice.gd` 的 `submit`、`submit_internal`、`_admit`、`settle_day`、`_deliver_shipment`、`_material_batches`、`snapshot`、`restore`；资本、经理接替、阶层组、多站点、寄存和迁居已有增量，不能全部写成待建。金融使用 `scripts/world/formal_ledger_state.gd` 的 `reserve`、`release`、`batch_payment`。组织授权位于 `scripts/authorization/authorization_check.gd`；世界时间和恢复位于 `scripts/simulation/simulation_step.gd`、 `scripts/simulation/game_clock.gd`、 `scripts/persistence/formal_persistence.gd`。
- 最新Task6在 `D:/programs/WWO/research/military/wwo-person-attachment-20261011T0010/experiments/war_resolver/`。`logistics/service.gd`、 `gameplay/land_transport.gd`、 `gameplay/sea_transport.gd` 和 `attachment_continuity/session.gd` 有自身资源与秒级过程，尚未证明与正式经济共用资源。

读取指定分项的完整正文，按以下顺序实施：

1. `01-BASELINE-COMMITMENTS-RECOVERY.md`：复现十五类生产可能使用已承诺销售材料的情境，确认后局部修复。核查正式交付的资金与保管采用原子性，验证短业务续接及坏引用拒绝。保留独立日志snapshot和正式运行态restore的区别，不恢复旧宿主。
2. `02-CUMULATIVE-BUDGET.md`：把预算绑定组织/企业、授权来源、币种、科目和窗口；接受登记承诺，支付转为已支出，确认取消释放未履行份额。拆单、代理或经理换人不能刷新额度；授权、现金和物资仍各自重验。
3. `03-LOTS-AND-LOSS.md`：将现有数量库存写入改为可追踪的批次份额，贯穿生产、销售预留、运输、寄存、个人消费和资本材料。价格留在报价/成交状态。用户选定损耗量纲、组合、舍入及责任后，才启用全链损耗；同时迁移预算责任和存档。
4. `04-SHARED-CAPACITY.md`：复用 `scripts/vnext/spatial/spatial_world.gd` 的 `request_capacity_batch`、`reservation_results_batch` 等实际入口。处理重分配和跨小时清空，区分候选请求、最终分配、已用运力和未来承诺；让货运、节点装卸和接入的其他活动共同争用。
5. `05-INTERRUPTIBLE-TIME.md`：用户确认时间模型及首批过程后，按共同边界先结旧区间，再改变未来上下文。保留日级策略；不一次改全部生产、信用和军事时间。
6. `06-MILITARY-ECONOMY-CHAIN.md`：用一条明确映射的军需链连接实际生产、财政采购、承运、交接和耗用/战损。经济与军事引用同一批次和事件；不重复扣货、不复制库存。接秒级Task6依赖05；较粗切片另需用户选择。

每阶段都接入真实恢复路径。`ProgrammeWorld.snapshot()` 是实验日志，不是完整可恢复世界；不要把日志读回或源码恢复报告成运行态恢复。正式已有 `FormalPersistence.restore_candidate()` 和原生 `restore()`，应复用候选校验与成功安装路径；恢复不得重新initialize、补钱补货或丢失未结责任。若另需独立实验运行态恢复，先提出具体范围，不在本组顺带扩成另一套引擎。

保留有限资金、库存、劳动、已知信息、原行动ID、订单锁价、未付工资和到期债务。保留两线现有付款时点及价格策略差异，除非我另行批准模型变化。不能把需要或无款询价当作有支付保障的订单，也不能把借款本金、内部调拨或现金净流入算成利润。

尚待我选择的事项是预算窗口与跨窗口径、必要支出优先级、损耗量纲/组合/余量及货损责任、共同容量单位与优先规则、世界细时间和军需单位映射。先完成不依赖选择的工作，给出具体选项及影响；未确定部分写入未完成项，不擅自定值或变成实现要求。保留funded credit；贷款创造存款、全面银行、完整利润表、任意角色切换和62项活动全面落地另行设计。

每阶段只运行针对性短测试和受影响调用方的局部回归，验证真实业务续接而不只比导出外观。不跑全量测试、全仓回归、长期模拟或重型测试，不新增额外门禁、验收矩阵、证据包及其脚本，不主动计算或比对内容哈希。已有工具完整性机制保留。未运行的检查不得称通过。不得覆盖其他人的工作，不自动切换本地分支、合并云端代码、修改AGENTS.md或推送源码。

执行后反馈要求：实际完成本阶段后，生成中文真实结果报告和交接摘要，保存本地并上传私有仓库 `ryoumiyahayato/wwo` 的独立文档分支，保留原研究、审议和提示词。建议路径为 `docs/research/local-economy-review-20261013/execution-feedback/<实际日期时间>/`。写清改动前后行为、实际修改文件与接口签名、删除或替代的旧内容、兼容和数据迁移、实际验证命令与结果、未运行检查、未完成项及对下一阶段的影响。标明本次执行的提示词及所审阅云端研究版本 `beed4b12c0d0fd0c0a8a04afd9f30481db533918`。只上传反馈文档，不上传源码快照、存档、凭据或无关材料，不创建PR、不合并；远端读回核验后返回文档链接。失败或部分完成也须如实反馈，不能把计划当完成。云端聊天模型下一轮下达指令前必须先读这份结果与摘要，更新本地现状和接口，再决定后续任务。
