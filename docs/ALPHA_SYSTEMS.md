# Alpha 正式系统登记

本表回答每个正式系统的创建、读取、修改、结束、保存、迁移、玩家/AI 使用和连接边界。
静态内容来自 `data/alpha/*.json`；运行态由下列唯一服务持有，UI、地图和测试均不另存
第二份权威状态。

| 正式对象 | 创建与唯一修改者 | 读取者 | 生命周期结束 | 保存与迁移 | 玩家与 AI 入口 | 主要连接 |
|---|---|---|---|---|---|---|
| 时间与周期边界 | `SimulationClock`；`AlphaSimulationService._settle_hour` 只消费小时边界 | 所有到期和批处理服务 | 世界会话结束 | V2.2/V2.3 原时刻迁移；Alpha 快照保存整数小时 | UI 速度/暂停；AI 不修改时钟 | 日程、到期合同、日/周/月批次 |
| 国家、地区、单元、地点、路线 | `CoreDataLoader` + `AlphaWorldService`；政策完成时可改地区正式字段 | 地图、市场、劳动、信用、政治、旅行 | 静态对象本 Alpha 不删除；动态效果到期或被新政策改变 | 稳定 ID 迁移；废弃旧几何并重建拓扑 | 玩家按对象发现入口；AI 读取已知地区/路线 | 工资、生活成本、价格、信用、运输、权限 |
| 人物与精度层 | `CharacterGenerator`、`CharacterRosterService`、`CharacterData` | 劳动、企业、政治、知识、UI | 死亡/退休等进入退出记录；可在活跃/背景间升降 | 保存完整活跃记录、背景持久核心、退出记录和激活种子 | 四类创建；AI 使用同一人物对象 | 技能、资质、状态、财富、合同、组织、职位 |
| 日程、旅行、消息、知识、关系 | 既有 V2.2/V2.3 正式服务 | 人物 UI、行动校验、AI 已知快照 | 活动完成/取消、消息过期、关系继续持久 | 原域完整保存；V2.2→V2.3→Alpha 保留兼容状态 | 玩家发起；NPC 使用相同空间和通信规则 | 时间、地点、有限认知、当前状态 |
| 现金与账本交易 | `AlphaLedgerService` | 经济、企业、劳动、政治、UI | 交易不可删除；历史可有界裁剪但余额保留 | 账户、交易、余额和幂等窗口保存 | 所有支付均经正式服务；AI 相同 | 资产、合同、工资、债务、政策、腐败 |
| 资产、所有权与控制权 | `AlphaAssetService` | 经济、企业、信用、破产、UI | 出售、转让、继承、没收、损坏、贬值、破产处置或关闭 | 资产、份额、控制人、抵押引用保存 | 对象动作；AI 可建立/出售企业权益 | 账本、合同、企业、债权、抵押 |
| 合同、订单与债务 | `AlphaContractService`；借款由 `AlphaEconomyService` 原子连接债权资产和账本 | 劳动、企业、政治、信用、UI | 履行、结算、违约、执法、私了、终止 | 合同历史、余额、文件、证据、幂等键保存 | 玩家和 AI 使用相同申请/签订/履行入口 | 资产、账本、工作、贸易、合伙、政策、腐败 |
| 工作、失业与迁移 | `AlphaLaborService` | 人物、企业、AI、UI | 辞职、解雇、期限、失业和重新雇佣 | 申请、雇佣状态、人物档案、失业和迁移记录保存 | 玩家对象动作；AI 有限候选 | 合同、工资账本、状态、经验、地点 |
| 企业经营 | `AlphaEnterpriseService`，组织身份仍归 `OrganizationService` | 市场、AI、政治、UI | 出售、收缩、违约、破产、解散；历史组织保留 | 经营状态只保存资产/合同/人员 ID 和风险；运行时组织一并恢复 | 创建、购买、合伙、借债、订单、采购、生产、交付等；AI 相同 | 组织、资产、合同、劳动、账本、地区市场 |
| 人物能力与发展 | `AlphaCharacterService` 修改同一 `CharacterData` | 行动评估、知识估计、UI、AI | 计划完成/中止；资格和经验留在人物履历 | 计划、授权、评估及人物字段保存 | 七种发展方式；AI 可安排独立训练 | 日程、技能、资质、经验、资格、专业服务 |
| 组织、成员与职位 | `OrganizationService` 是成员/职位唯一权威；`AlphaPoliticsService` 保存权限包和任期扩展 | 企业、政治、AI、UI | 离开、辞职、罢免、任期、组织变化、违法 | 组织记录、人物职位索引、任期和支持记录保存 | 玩家与 AI 均可加入、争取和使用职位 | 人物、企业、预算、政策、合同签署 |
| 政策、预算、腐败与调查 | `AlphaPoliticsService`；政策完成时由 `AlphaWorldService` 写地区效果 | 世界批处理、组织、地图、事件 UI | 政策完成/失败；腐败调查不足、成立或处分；职位可失去 | 实施、资金、阻力、证据、知情者、调查和公开事件保存 | 玩家对象动作；AI 在已知公开议题上竞争与实施 | 职位权限、组织预算、账本、合同、资产、地区 |
| AI 决定与世界动态 | `AlphaAiService`、`AlphaWorldDynamicsService` | 事件摘要、开发真相视图、测试 | 每日决定后结束；历史固定上限；事项最多三项 | 候选摘要、决定、背景状态、国家问题、计数器和边界索引保存 | 玩家可什么都不做；AI 只调用上述正式入口 | 全部正式系统，但不读取未提供的隐藏真相 |
| UI、地图与当前打算 | `AlphaUiBinding`、`AlphaMapCanvas` 仅投影；当前打算由组合根保存过滤元数据 | 玩家 | 选择改变或会话结束 | 只保存当前打算 ID、高亮、期限、风险和过滤 | 世界对象是行为发现入口 | 不直接修改权威数据，不提供推荐路线 |

## 统一入口位置

- 组合根：`scripts/alpha/alpha_simulation_service.gd`
- 世界/拓扑：`scripts/alpha/alpha_world_service.gd`、
  `scripts/alpha/alpha_topology_service.gd`
- 经济：`scripts/alpha/alpha_ledger_service.gd`、
  `alpha_asset_service.gd`、`alpha_contract_service.gd`、`alpha_economy_service.gd`
- 劳动/企业/人物/政治：`alpha_labor_service.gd`、`alpha_enterprise_service.gd`、
  `alpha_character_service.gd`、`alpha_politics_service.gd`
- AI/分层动态：`alpha_ai_service.gd`、`alpha_world_dynamics_service.gd`
- 存档/迁移：`alpha_save_service.gd`、`alpha_save_migration.gd`
- UI/地图：`alpha_ui_binding.gd`、`alpha_main.gd`、`alpha_map_canvas.gd`
- 确定性场景：`alpha_scenario_runner.gd`
