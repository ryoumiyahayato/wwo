# 01：本地语义、资源承诺与运行态恢复

本文件是交给本地执行端的开发指令。本文件已准备，不表示改造已执行。收到本阶段执行指令后，先读适用AGENTS.md和 `D:/programs/WWO/handoff/economy-review-20261013/REPORT.md`。重读最新执行反馈；没有前阶段反馈时以当前代码为准。保留未提交工作，不切换或重置分支，不合并云端代码。用户本次的局部检查限制优先于旧指南的全量测试、实验恢复和哈希要求。

## 实际入口和已有实现

十五类主根为 `D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo`：

- `economy_quantity_lab/algorithm_completion/world.py`：`ProgrammeWorld.production_plan()` 先调上层计划，再按实际劳动裁减；`step()` 执行日级阶段；`snapshot()` 给initial、day_close和final输出使用，没有完整运行态restore入口。
- `economy_quantity_lab/network_round6/network_simulation.py`：`production_plan()` 调 `local_plan(node, day, horizon, lead_by_good)`；`produce(plan)` 一次扣配方投入并加产出。`stock_commitments` 与单一stock表关联。
- `economy_quantity_lab/network_round6/firm_network.py`：`local_plan()` 从 `dict(node.inventories)` 建立available，未在此处扣销售承诺。
- `economy_quantity_lab/multi_round4b/stock_admission.py`：`StockCommitments.uncommitted(supplier, commodity, on_hand)`、`reserve`、`release`、`check`。可复用真实承诺，不建立第二套预留。
- `economy_quantity_lab/goal_cycle01/payment_policy.py`：`accept()` 对钱、物资、槽位及订单采用带回滚；货款到货付。`algorithm_completion/world.py` 的运费在发运时付。

正式根为 `D:/programs/WWO/wwo`：

- `scripts/world/economy_r1_slice.gd`：`_material_batches()` 已扣 `_committed()`；`_deliver_shipment()` 先构造收据和付款腿，调用Ledger后更新个人保管、stock、订单与来源记录。个人来源采用位于付款之后，是否可失败必须从当前调用链核实，不能先称已发生缺陷。
- `scripts/world/formal_personal_economy_state.gd`：`native_custody_ready`、`record_native_custody`、`record_native_source` 及 `snapshot`、`restore`。原生lot是来源和保管描述，数量权威仍在原生经济库存。
- `scripts/world/formal_ledger_state.gd`：`reserve`、`release`、`batch_payment`；批量付款验证资金和释放后再采用。
- `scripts/world/economy_r1_slice.gd`：`snapshot()`、`restore()` 已含订单、shipment、部分收据、命令、工资、金融、资本和业务接替；恢复重建派生索引。
- `scripts/persistence/formal_persistence.gd`：`restore_candidate()`、`_restore_candidate_state()`、`save_to_user()`。恢复到候选世界，成功后安装；不调用原生initialize补初始物资。`scripts/simulation/simulation_step.gd` 的 `safe_boundary` 连接保存边界。

正式已有资本、维护、动态经理、阶层人份、迁居、多站点和退出，不因R1/R2类名而判为缺失。已删除的 `FormalWorldEconomyService`、旧模拟宿主和旧组件注册路径不恢复。

## 本阶段任务

1. 沿上述调用链核对十五类和正式增量的语义差异。只记录影响本阶段及下一阶段的差异：原生材料预留、付款时点、经理权限、人口责任、恢复。不要新建十五类替代实现或复制整个Python世界到Godot。
2. 在十五类主根构造一个短业务：同一企业的同一种物资，一部分已经由真实接受订单承诺销售，余下才可投入另一配方。先证明当前 `local_plan -> ProgrammeWorld劳动裁减 -> produce` 的实际结果。若能吞用承诺材料，局部修复上层计划传入的可用投入及生产采用重验，复用 `StockCommitments.uncommitted`。可扩展现有local_plan参数，但这属于待新增接口，需在结果中写出签名和全部受影响调用方。不要改全局stock为扣承诺后的假库存。输出目标与销售库存观察、投入可用量应分别处理，不能用一个裁减字典改变全部经营观察。
3. 保留多配方共享材料和实际劳动限制；修复后销售仍能履约，取消确认释放后才重新可投入。若该情境已有其他层保护，记录实际保护路径和短测试结果，不为迎合审议制造修改。
4. 对正式 `_deliver_shipment` 做一次针对性失败路径核查：付款成功后个人保管或来源采用是否还可能失败，失败是否会留下已付钱但未交货、可重复领取或来源重复。若可复现，采用局部预检、候选采用或原事务范围回滚，使一份业务回执只采用一次。不只回滚钱却保留已变动的shipment或个人lot；不新建通用第二Ledger。不可复现时保留现有行为并报告证据边界。
5. 用短业务验证正式原生运行态恢复：未发订单、在途货物、部分领取、未付工资、一个未完资本项目及已接受的经理接替中，挑选能覆盖实际改动的最小组合。保存后走真实候选恢复并续接同一事件；检查ID、已收累计量、预留、责任和索引连续。坏商品/人物/收据引用或与Ledger不一致的候选应拒绝，当前活世界不受污染。若发现局部恢复缺陷，在原路径修复；不能把日志补字段视为完成恢复。

本阶段不开发累计预算、批次损耗、共同物流、银行或时间新模型。经理接替与asset配置manager分叉只记录，不直接赋予新经理分红权。分红的决议与利润规则待用户选择。不给独立日志添加“运行态存档”标签；完整恢复独立ProgrammeWorld另行指定范围。

## 兼容与验证

保留C0/C1分配、S2库存确认、有限知识、现有价格策略、现金/份额约束、原合同及ID。正式同企业调拨不产生销售款，宏观人口排除与原生控制锁不解除。当前正式存档为 `formal_world_simulation_v15` 和外层 `formal_world_exact_variant_v1`；本阶段尽量不增加权威字段。若确实需要变更，只为本缺陷明确兼容或拒绝原因，不补未知历史，不修改用户实际存档。

新增或更新与上述反例直接相关的局部测试。十五类已有 `algorithm_completion/test_programme.py` 的 `HouseholdLaborTests.test_shared_input_recipes_and_labor_capacity`、`test_pending_goods_cannot_be_eaten`，以及 `test_spatial.py` 的 `SpatialTests.test_freight_and_goods_rollback_share_one_wallet` 可作为受影响回归。执行前再次核对类和方法是否仍存在；使用明确方法选择，不启动研究总验证脚本。

正式参考 `D:/programs/WWO/wwo/tests/formal/formal_personal_economy_test.gd` 的Ledger、分段工资和恢复拒绝样例，为本阶段建立短的原生业务测试。`formal_exact_persistence_roundtrip_test.gd` 含180日案例，不整体运行。Godot只用当前指定4.6.3与受影响短测试；测试所需导入限于当前项目且确认必要，不能借导入触发全量验证。未运行项如实列出。不加额外门禁、验收矩阵、证据包或哈希脚本。

完成标准是：确认的资源承诺或采用缺陷有实际前后行为与局部测试；正式受影响业务走候选恢复后能续接且不重复获利；没有复现的风险有明确结论。后续得到的是当前实际调用路径和可保留行为，不是“十五类与正式已全面等价”。

## 执行后反馈要求

实际执行后，生成中文01结果报告和交接摘要，保存本地并上传私有仓库 `ryoumiyahayato/wwo` 的独立文档分支。保留原研究、审议、提示词和他人工作。建议路径为 `docs/research/local-economy-review-20261013/execution-feedback/<实际日期时间>/01-RESULT.md` 及 `01-HANDOFF.md`。

报告写清实际前后行为、修改文件绝对路径与仓库相对路径、类/函数和新签名、删除或替代的旧内容、未提交基础、存档兼容、实际测试命令/结果和未运行检查。写清承诺反例、交付原子性及候选续接哪些确已验证、哪些未证实，列出未完成项、用户选择及对02/03的接口影响。标明所执行提示词和云端研究版本 `beed4b12c0d0fd0c0a8a04afd9f30481db533918`。只上传反馈文档，不上传源码快照、存档、凭据或无关材料，不创建PR、不合并。远端读回核验并返回链接；失败或部分完成也如实反馈，不能把计划当完成。云端聊天模型下一轮下达指令前必须先读本反馈和摘要，更新本地现状与接口，再决定后续任务。
