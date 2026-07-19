# Alpha 系统登记与当前状态

## 状态

2026-07-19 生成的 `scripts/alpha/*` 不是当前正式 Alpha。它建立在已经废弃的洛岚—维斯塔 10×8 架空网格上，并且普通 UI 没有覆盖报告所称的全部生命周期。

这些代码暂时保留为：

- 经济、合同、债务、企业和政治服务的实现候选；
- 自动场景与存档测试夹具；
- 后续迁移到正式世界地图时可复用的代码来源。

它们不得继续被描述为“完整 Alpha 功能与性能验收通过”。

## 当前正式入口

- 普通启动：`scenes/v2_3/v2_3_life_loop_menu.tscn`
- 正式地图数据：`data/world_map/*`
- 正式地图实现：`scripts/world_map/*`
- 详细空间、旅行、消息、知识与关系：V2.3 正式服务

旧架空 Alpha 入口仍可由开发者显式打开，但必须视为历史技术夹具。

## 实现审查摘要

| 范围 | 代码现状 | 当前判定 |
|---|---|---|
| 时间、日程、旅行、消息、知识、关系 | 继承并调用 V2.2/V2.3 服务 | 可复用 |
| 账本、资产、合同、债务 | 存在独立服务与测试 | 可迁移候选，尚未在正式地图 Alpha 验收 |
| 劳动和企业 | 存在较多生命周期方法 | 服务层候选；普通 UI 未暴露完整订单、采购、生产、交付、扩张、破产链 |
| 人物能力与发展 | 存在评估、发展计划和角色字段 | 可迁移候选；需验证其与正式世界机会和日程连接 |
| 组织、职位、政策、腐败 | 存在服务和场景调用 | 普通 UI 使用固定首项政策和固定腐败模板，不能视为完整自由玩法 |
| AI | 使用有限候选并调用部分正式服务 | 可复用候选；当前是规则优先级与确定性轮换，不等于完整目标—承诺—计划 AI |
| 地图与世界 | 读取 `demo_world.json` 并生成 80 格网格 | 已否决，不得迁移为正式权威 |
| 普通 UI | 对象列表、详情和少量快捷动作 | 不足以支持完成报告声称的完整生命周期 |
| 自动场景 | 场景脚本直接调用服务并检查结果 | 证明部分服务可调用，不证明普通玩家流程完整可玩 |
| 窗口烟测 | 检查窗口尺寸和平均 FPS | 不证明交互、保存、企业、政策或腐败流程可用 |

## 重新成为正式 Alpha 的门槛

必须同时满足：

1. `AlphaWorldService` 不再读取或派生旧两国八区80单元世界。
2. 国家、地区、城市、地点与交通统一迁移到 `data/world_map/*` 权威。
3. 普通启动、普通存档和普通 UI 不再出现洛岚、维斯塔、晨港、铁川、星城或赤原。
4. 玩家可以通过普通 UI 完成受雇、迁移、借款、企业经营、组织职位和政策的主要成功与失败生命周期。
5. 自动场景不得在服务调用后直接修改人物国家、地区或城市字段。
6. AI 与玩家通过相同领域命令或事项入口行动，不使用仅供测试的捷径。
7. 存档迁移明确区分旧架空夹具和正式世界存档，不静默映射不存在的地理对象。
8. 性能重新按正式地图和实际对象规模测量。
9. 实际窗口检查覆盖主要流程，而不是只测窗口尺寸和 FPS。

## 代码位置

保留的候选实现：

- 组合根：`scripts/alpha/alpha_simulation_service.gd`
- 账本、资产、合同、经济：`scripts/alpha/alpha_ledger_service.gd`、`alpha_asset_service.gd`、`alpha_contract_service.gd`、`alpha_economy_service.gd`
- 劳动与企业：`scripts/alpha/alpha_labor_service.gd`、`alpha_enterprise_service.gd`
- 人物：`scripts/alpha/alpha_character_service.gd`
- 组织政治：`scripts/alpha/alpha_politics_service.gd`
- AI与动态：`scripts/alpha/alpha_ai_service.gd`、`alpha_world_dynamics_service.gd`
- 存档：`scripts/alpha/alpha_save_service.gd`、`alpha_save_migration.gd`
- 自动场景：`scripts/alpha/alpha_scenario_runner.gd`

已否决的正式世界实现：

- `scripts/alpha/alpha_world_service.gd` 当前网格初始化部分
- `scripts/alpha/alpha_topology_service.gd` 对10×8网格的正式验收用途
- `scripts/alpha/alpha_map_canvas.gd` 当前正交格子画布
- `data/alpha/world.json` 中洛岚—维斯塔世界内容

这些文件可以继续用于历史测试，但不得被普通入口或正式发布声明引用。
