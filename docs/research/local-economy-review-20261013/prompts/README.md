# 本地经济后续开发追加提示词

2026年10月13日。状态：提示词已准备；本地尚未执行这些改造。本轮只新增本文档目录，未修改算法、运行代码、AGENTS.md或存档格式，也未运行算法测试。

原审议保留在上级目录的 `REPORT.md` 和 `HANDOFF.md`。远端原报告为 [REPORT.md](https://github.com/ryoumiyahayato/wwo/blob/bcc9601f7e44b6e945c85ba27b0505b7395b54ac/docs/research/local-economy-review-20261013/REPORT.md)。所审阅的云端研究版本仍为 `beed4b12c0d0fd0c0a8a04afd9f30481db533918`，文档分支为 `docs/organization-military-20261013-v2`。本组提示词接续该审议，不把云端建议当成已确定规格。

## 保存位置与阅读顺序

本地完整目录：`D:/programs/WWO/handoff/economy-review-20261013/prompts/`。

| 顺序 | 文件名 | 用途与前置依赖 |
| --- | --- | --- |
| 0 | `00-MASTER.md` | 可直接复制的总提示词。规定执行范围、依赖和反馈。未指定阶段时从01开始 |
| 1 | `01-BASELINE-COMMITMENTS-RECOVERY.md` | 核对十五类与正式增量；复现并修复资源承诺问题；验证正式运行态恢复。后续阶段的共同前置 |
| 2 | `02-CUMULATIVE-BUDGET.md` | 组织和企业累计预算；承诺、支付与取消的衔接；资金分类。依赖01的实际反馈 |
| 3 | `03-LOTS-AND-LOSS.md` | 全链批次及损耗；个人来源记录、订单、资本和恢复共同迁移。依赖01；使用02实际形成的预算与责任接口 |
| 4 | `04-SHARED-CAPACITY.md` | 小时窗口最终分配、实际占用、节点装卸和时间连接。依赖01至03的实际反馈 |
| 5 | `05-INTERRUPTIBLE-TIME.md` | 有条件的经济时间模型变更。依赖04；用户确定细时间与首批过程后执行 |
| 6 | `06-MILITARY-ECONOMY-CHAIN.md` | 一条真实军需链的生产、采购、运输、接收、使用和损失。依赖01至04；接秒级Task6还依赖05及时间选择 |

默认按表阅读和下达任务，一次完成一个阶段并反馈。02和03并非两个互不相关的任务：货损、部分交付、取消及补运会改变预算占用，03必须接续02的实际接口。04不能绕过批次；06不能绕过共同运力和时间边界。若05尚未获准，可先讨论仅覆盖正式分钟/日结边界的06切片，但必须由用户明确选择，不能把它报告为完整接入秒级军事过程。

恢复贯穿所有阶段。01先验证已有恢复基础；02至06新增的权威状态各自接入候选恢复，不能集中留到最后。日志、源码备份和运行态存档分别处理。

## 本轮核读的本地基础

- 十五类主线：`D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo`，分支 `research/fifteen-algorithms-v0`，HEAD `030de3f`，本轮读取时工作副本干净。
- 正式增量：`D:/programs/WWO/wwo`，分支 `canonical/current-world`，HEAD `622b260`，有未提交修改、删除和未跟踪文件。`scripts/world` 等增量以工作副本为准。不要重置、切分支或恢复已删除的旧宿主。
- 军事实验：`D:/programs/WWO/research/military/wwo-person-attachment-20261011T0010`，分支 `experiment/war-person-objective-attachment-v0-20261011T0010`，HEAD `2fb4f70`，有未提交工作。只在06需要时读取适用指南和实际接口。
- `D:/programs/WWO/research/economy/wwo-economy-lab` 是较早Round6，不替代十五类完成版。

以上Git标识只辅助定位，不代表未提交增量已上传。交给执行端时必须重读当前文件和前阶段真实结果，不根据本提示词冻结行号或假定方法未变化。

本轮追加核读发现：`D:/programs/WWO/wwo/scripts/vnext/spatial/spatial_capacity_window.gd` 是小时窗口。加入或取消请求会重算分配，跨小时会清空请求。`request_capacity_batch` 的 `accepted` 表示请求被接受，不表示全量分配或不可撤回的实际占用。`scripts/vnext/economy/market_economy.gd` 和 `scripts/vnext/military/military_service.gd` 已使用批量请求及最终查询，可参考其语义；它们不能证明正式 `EconomyR1Slice` 或最新Task6已经接通。04据此细化了审议方向。原报告未被覆盖。

## 阶段边界与用户选择

01是缺陷核查和局部修复。02是机制扩充，累计预算的窗口和跨窗口径需选择。03包含批次结构迁移；基础每日损耗、运输方式按日或按程、组合、余量和货损责任仍需选择。04是共享运力机制与适配；容量量纲和优先规则仍需确定。05改变时间模型，不能用“修复”名义改变旧日结结果。06是专业连接，资源与装备映射必须有明确依据。

保留funded credit。银行吸储、贷款创造存款、完整成本与利润报表、集团重组、任意人物控制切换以及62项活动的全面实现均不在本组默认执行范围。云端20个案例仍是设计要求，不是通过结果。价格、工资、损耗率和产业倍率不在没有资料时批量填写。

## 执行反馈的使用

每份提示词末尾都有反馈要求。结果必须在实际执行后形成，上传 `ryoumiyahayato/wwo` 的独立文档分支，并读回核验。建议远端位置为 `docs/research/local-economy-review-20261013/execution-feedback/<实际日期时间>/`，分别保存阶段结果和交接摘要。当前没有这些执行结果；不得预先生成“已完成”报告。

云端聊天模型下一轮必须先读取最新结果报告和交接摘要，替换旧接口假设，再决定下一项任务。未读到结果，不能把本组提示词当成实施证据。执行部分完成时也应反馈实际完成范围及阻塞，不能直接进入依赖它的下一阶段。
