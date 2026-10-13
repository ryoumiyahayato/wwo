# WWO 后续讨论总提示词

请接续WWO军事审议，把云端研究整理成适合当前本地项目的设计讨论和开发指令草案。本轮只讨论，不修改或运行算法，不自动执行这些提示词，也不写入AGENTS.md等生效指令文件。后续实施等待用户确认。

先读取最新一轮本地实际结果报告及交接摘要，再读取提示词入口、01–09分项、活动讨论索引和已完成的中文审议报告。首次接续时，本包HANDOFF_ZH.md只表示提示词生成完成，不表示算法已实施。现状与旧方案冲突时，先修正理解和指令。材料入口：
- 本地：D:/programs/WWO/research/military/local-military-review-20261013/prompts/README.md。
- 云端提示词：https://github.com/ryoumiyahayato/wwo/blob/docs/local-military-review-20261013-v1/docs/research/local-military-review-20261013/prompts/README.md。
- 审议报告：https://github.com/ryoumiyahayato/wwo/blob/docs/local-military-review-20261013-v1/docs/research/local-military-review-20261013/REVIEW_ZH.md。
- 原研究：https://github.com/ryoumiyahayato/wwo/blob/9cc370611de97a0f5481c2ea7e8645b572f90727/docs/research/organization-military-20261013/README.md。
原研究是 docs/organization-military-20261013-v2 的2026-10-13 v2；阅读入口指向军事草案、组织摘要、组织研究。云端建议是候选方案，不是实施规格。

已核本地位置及审议事实：
H = D:/programs/WWO/wwo，分支 canonical/current-world。正式入口使用WorldState、WorldBootstrap、SimulationStep、FormalPersistence。相关文件为H/scripts/world/world_state.gd、H/scripts/content/world_bootstrap.gd、H/scripts/simulation/game_clock.gd、H/scripts/simulation/simulation_step.gd、H/scripts/persistence/formal_persistence.gd。GameClock为分钟时间；审议时Step未推进新军事研究。H/scripts/world/organization_state.gd与H/scripts/authorization/authorization_check.gd已有合并组织/授权；H/scripts/world/formal_ledger_state.gd、H/scripts/world/economy_r1_slice.gd、H/scripts/world/economy_capital_formation.gd已有资金、原生经济及资本项目。正式存档为v15，不含新军事实验的完整运行态。

M = D:/programs/WWO/research/military/wwo-person-attachment-20261011T0010/experiments/war_resolver，所在工作树分支 experiment/war-person-objective-attachment-v0-20261011T0010。M/battle_state.gd、M/resolver.gd、M/aggregation/authority.gd、M/structure/service.gd、M/gameplay/participants.gd、M/gameplay/operations.gd、M/information/service.gd、M/decision/service.gd、M/logistics/service.gd已有局部战斗、身体/岗位、任务、通信、决策、真实物流及陆海空专业过程。实验快照有遗漏；恢复增加能力/恢复信用，personnel_total不能当人口；read_leaf/zoom与focus可能触发表示转换。有限野战工事源码已出现，港口设施抢修未见；在港修舰不能替代港口修复。

E = D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo，分支 research/fifteen-algorithms-v0。E/economy_quantity_lab/algorithm_completion/world.py、E/economy_quantity_lab/economy.py、E/economy_quantity_lab/goal_cycle01/cash.py是独立经济对照。日级流程、订单FIFO和报告snapshot不能冒充已与宿主联合运行、商品批次FIFO或完整运行态恢复。

上述行为来自已完成审议。本轮只复核位置与分支；军事/宿主仍有未提交修改。若取得更新源码，先核对变化。云端旧源码不能替代当前工作树；访问不到的材料/位置标未知，不猜测，也不声称已重查本地。可继续不依赖缺失材料的讨论。

云端对应：《军事草案》4–8、10、12.3–12.4；《组织研究》5–9及10.4–10.5。活动索引覆盖1–113，优先核对9/16交接命令、43工事、48港口修复、70–89运输库存、91–113工业人员与战后责任。

请按01身份/人口/任职→02时间/粗细→03恢复→04共享资源→05命令/任务/所知→06空间/运输→07陆海空/工程→08人员/工业/制度→09界面/成本/113覆盖的顺序推进。前项未定时，后项可以列问题和候选，不能宣称接口已经成立。

共同约束：
1. 113项是完整内容目录。全部保留去向，不做113套系统或12套管理器；每项专门缺口需说明。
2. 模拟细度、人物权限、界面展开分开。当前岗位只限制当前参与，不删世界活动。粗细、换任、换人、视角变化不重置人口、资源、伤损、任务、知识或结果。
3. 沿用现有宿主装配、Ledger和正式候选恢复。当前原生经济作为优先接入候选，Python作为业务合同对照；讨论其适用边界，不另建账本/人口/Clock/总世界。
4. 已接受任务、在途签发命令与新的越权动作分开讨论。当前送达时权限重验先保留；组织签署延续按类别作为待决定方案。
5. 商品基础值只讨论单位重量、基础每日损耗率；运输方式损耗率及按日/按程、组合公式仍待用户确定。不填基础值，不增加必填商品属性，不推定损耗为零。
6. 不计算或比对内容哈希，不生成指纹清单，不追加门禁、验收矩阵、证据包或脚本；不跑全量回归、长期模拟、训练或测量。未来局部验证只列要求，不执行。

请逐份输出：已读材料及版本；本地事实/云端建议/本次候选的区分；具体待解决问题；复用模块与前置依赖；状态归属、边界与任务连续合同；保留行为、迁移风险和未来局部验证要求；待用户决定项。确认不了的现有或新文件位置标未知。

以后实施时，按选定改动局部核对人物/人口、伤损、未决任务、在途货物、资金/工时、同刻边界和候选恢复；检查重试/加载不重复结算、换人/粗细不刷结果、异常候选拒绝。具体案例沿用分项所列现有测试或待确认位置；本轮只列要求，未运行。

预期成果是可继续审议的分阶段设计，以及供用户确认后使用的开发指令草案。先解决同一事实和恢复，再接已有LAND补给任务链，随后讨论SEA交接与AIR出动；这只是本地审议推荐顺序，可依据更新材料反对并提出替代。不要只重述差异报告，不把草案自动转成实施。

## 实施后的结果交接要求

以下要求在用户确认并由本地完成本轮实施后适用；本次只生成提示词，不执行本轮实施。

本地须以实际代码和实际运行记录生成结果报告，并保存本地文件、上传用户指定的独立文档分支。默认候选为既有 docs/local-military-review-20261013-v1；具体结果文件名/目录由该轮指令草案指定，当前位置未知；须列出不冲突的完整本地保存目标和远端路径，标明拟新建文档，不覆盖旧报告。报告至少说明：

1. 执行前依据、分支/未提交状态及所读上轮反馈；实际完成了哪些变化，哪些计划没有执行，为什么。
2. 执行后的现存对象、状态归属、实际文件/函数和接口调用关系；已删除、替换、停用对象及替代路径。不存在或未实现的接口明确标记，不用拟议名称代替真实接口。
3. 实际行为、数据/时间/资源/任务/恢复合同的前后差别；保留行为、迁移兼容及已知风险。报告以实际代码为准，不照抄原计划。
4. 实际验证的局部案例、方法/命令、结果和局限；未运行、失败或缺覆盖分别写明。不得把未来验证要求写成已通过，不擅自增加全量回归、长期模拟、测量、哈希清单、门禁、验收矩阵或证据包。
5. 剩余缺口、待用户决定项、下一轮能使用的对象/接口与仍不能使用的东西。需要追加材料时，列确切文件或问题。
6. 上传后读回核验文本，交付完整本地路径和准确远端链接。只上传实际结果文档和交接摘要，保留原研究/历轮报告，不上传源码快照或凭据，不开PR、不合并，除非该轮另有明确授权。

后续云端模型必须先读取最新实际结果报告和交接摘要，再读旧方案。若未取得反馈，不推定本地已按计划完成。若反馈/新源码与旧方案冲突，先更新现状、标明旧指令失效部分并修正本轮候选指令，再安排下一轮。不得继续要求本地调用已删除、已替换或尚未实现的对象/接口；缺材料只暂停依赖它的指令，其他独立讨论可以继续。
