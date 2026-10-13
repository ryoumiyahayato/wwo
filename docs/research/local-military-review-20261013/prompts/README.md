# WWO 后续追加提示词入口

本目录把2026-10-13军事审议转换为聊天模型可接续的提示词。用途是讨论设计和组织供用户确认的开发指令。本轮只新增文档，没有实施其中任何算法、接口或存档变更。

本地目录：D:/programs/WWO/research/military/local-military-review-20261013/prompts
远端目录：docs/research/local-military-review-20261013/prompts
仓库/分支：ryoumiyahayato/wwo，docs/local-military-review-20261013-v1。

本目录不含AGENTS.md等生效指令文件，不会自动追加给任何模型、发起聊天或触发实施。复制哪份提示词由用户决定。

## 建议阅读和使用顺序

1. 读本入口与[本轮交接摘要](HANDOFF_ZH.md)。若后续已有本地实施结果，先读最新实际结果报告/摘要，再读本包。
2. 将[总提示词](00_MASTER_PROMPT.md)全文复制给聊天模型。取得材料后，再按01–09追加；前置依赖未定时，讨论缺口和候选，不宣称接口成立。
3. 各分项需要什么活动时，查[113项活动讨论索引](ACTIVITY_ROUTING.md)。该索引用于路由专门问题，不是验收矩阵。
4. 本地以后实施一轮后，必须产生并上传实际结果报告。下一轮云端模型先读反馈，按当前代码修正理解/指令，避免调用已删除、已替换或尚未实现的接口。

| 顺序 | 文件名与本地链接 | 讨论内容 | 前置讨论 |
| --- | --- | --- | --- |
| 总 | [00_MASTER_PROMPT.md](00_MASTER_PROMPT.md) | 项目背景、共同约束、阶段和交接规则 | 最新反馈/材料 |
| 01 | [01_IDENTITY_BODY_OFFICE.md](01_IDENTITY_BODY_OFFICE.md) | 身份、身体、人口与任职 | 最新材料与审议 |
| 02 | [02_TIME_RESOLUTION_CONTINUITY.md](02_TIME_RESOLUTION_CONTINUITY.md) | 时间结算与粗细连续 | 01 |
| 03 | [03_SAVE_MIGRATION_RESTORE.md](03_SAVE_MIGRATION_RESTORE.md) | 存档迁移与候选恢复 | 01、02 |
| 04 | [04_SHARED_RESOURCES_ECONOMY.md](04_SHARED_RESOURCES_ECONOMY.md) | 共同资源、工时与经济接入 | 01–03 |
| 05 | [05_COMMAND_TASK_INFORMATION.md](05_COMMAND_TASK_INFORMATION.md) | 命令、任务、所知与人物介入 | 01–04 |
| 06 | [06_SPACE_TRANSPORT_HANDOVER.md](06_SPACE_TRANSPORT_HANDOVER.md) | 空间、运输容量与物理交接 | 01–05 |
| 07 | [07_COMBAT_AIR_SEA_ENGINEERING.md](07_COMBAT_AIR_SEA_ENGINEERING.md) | 战斗、陆海空与工程专门机制 | 01–06 |
| 08 | [08_PEOPLE_INDUSTRY_INSTITUTIONS.md](08_PEOPLE_INDUSTRY_INSTITUTIONS.md) | 人员、工业、技术与战后责任 | 01–06及有关07结果 |
| 09 | [09_UI_COST_COVERAGE.md](09_UI_COST_COVERAGE.md) | 界面、运行成本与113项编排 | 01–08及最新结果反馈 |
| 查询 | [ACTIVITY_ROUTING.md](ACTIVITY_ROUTING.md) | 113活动的主讨论入口及专门问题 | 总提示词与各项公共合同 |
| 交接 | [HANDOFF_ZH.md](HANDOFF_ZH.md) | 本轮实际文档变化、已核本地情况与云端待讨论项 | 下一轮先读 |

这些是文件名和阅读顺序，不是自动执行流水线。各分项都写明当前位置/事实、云端章节/编号、具体问题、复用模块、依赖、约束、成果、未来局部验证及实施后交接要求。

## 已有材料与版本

已完成的[中文审议报告](https://github.com/ryoumiyahayato/wwo/blob/docs/local-military-review-20261013-v1/docs/research/local-military-review-20261013/REVIEW_ZH.md)和[原反馈摘要](https://github.com/ryoumiyahayato/wwo/blob/docs/local-military-review-20261013-v1/docs/research/local-military-review-20261013/FEEDBACK_ZH.md)留在同分支父目录。它们未被替换；本地提示词目录未复制这两份报告。

所读云端原文为 docs/organization-military-20261013-v2 的2026-10-13 v2，定位9cc3706：

- [研究入口](https://github.com/ryoumiyahayato/wwo/blob/9cc370611de97a0f5481c2ea7e8645b572f90727/docs/research/organization-military-20261013/README.md)
- [军事活动覆盖与分层计算草案](https://github.com/ryoumiyahayato/wwo/blob/9cc370611de97a0f5481c2ea7e8645b572f90727/docs/research/organization-military-20261013/military-activity-layering.md)
- [组织摘要](https://github.com/ryoumiyahayato/wwo/blob/9cc370611de97a0f5481c2ea7e8645b572f90727/docs/research/organization-military-20261013/organization-summary.md)
- [组织研究](https://github.com/ryoumiyahayato/wwo/blob/9cc370611de97a0f5481c2ea7e8645b572f90727/docs/research/organization-military-20261013/organization-research.md)

链接需要私有仓库访问权。聊天模型不能访问时，应说明材料缺口，由用户提供相关原文/反馈。不要借旧云端源码推测本地最新实现。

## 本地事实口径

| 部分 | 实际位置 | 本轮只读复核 |
| --- | --- | --- |
| 正式宿主 | D:/programs/WWO/wwo | canonical/current-world；897条status项 |
| 最新已审军事树 | D:/programs/WWO/research/military/wwo-person-attachment-20261011T0010 | experiment/war-person-objective-attachment-v0-20261011T0010；258条status项 |
| 独立经济 | D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo | research/fifteen-algorithms-v0；status clean |

本轮重读适用规则、核对分支/路径及少量关键定位。行为说明沿用已完成审议，不是第二次完整算法审计。未提交树仍可被其他工作更新；不是冻结发布版本。接续时以最新实际结果/源码修正旧描述。

正式宿主已有合并组织/授权、Ledger、原生经济与资本项目、正式候选恢复。新军事树已有身体/岗位、任务/所知、实际物流和有限陆海空/工程，但审议时未由正式Step推进，专业快照不完整。原生经济与Python十五算法尚未证明等价。新接口/文件位置未定处均标未知，不制造空接口。

第43项有限野战工事已见局部源码；第48项港口设施抢修未见，不能把在港修舰当作港口修复。personnel_total含恢复信用，不能当人口；粗细/焦点切换防刷及联合恢复仍未验证。

## 方案和验证边界

云端建议是候选。各分项要求聊天模型分清本地事实、云端建议和本次新候选。113项是目录；模拟细度、权限和UI分开。身份/视角变化不重置事实。共享人物、时间和资源；不重复建账本、Clock或总世界。基础值、损耗组合与战斗尺度未定，不补值。

没有修改或运行算法，没有改正式存档、分支或生效指令。没有运行编译、测试、模拟、训练或性能测量，没有新增门禁/验收矩阵/证据包/脚本，没有计算内容哈希。文档读回只确认本轮交付文本，不能说明算法通过。

后续实施结果报告以实际代码为准：记录执行前后、现存接口、已删除/替换对象、实际验证和缺口。旧计划不能代替反馈；云端必须先修正冲突，再安排下一轮。具体要求在每份提示词末尾。
