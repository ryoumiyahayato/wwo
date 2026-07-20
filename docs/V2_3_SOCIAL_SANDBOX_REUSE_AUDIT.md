# V2.3 社会沙盒核心重构复用审计

审计日期：2026-07-20

## 实际产品入口

`project.godot` 的正式启动链最终创建 `V23ProductSimulation`。它继承
`V23MinuteControlledSimulation -> V23ControlledSimulation ->
V23FormalSimulation -> V23LifeLoopSimulation`，因此当前产品权威状态是
V2.2 生活闭环与 V2.3 空间、通信、认知系统的组合，而不是 README 中仍被
保留作网格夹具的 P0/战略模拟组合根。

## 复用决定

| 领域 | 唯一权威实现 | 本次决定 |
|---|---|---|
| 时间 | `SimulationClock` / `V23MinuteClock` | 复用；沙盒只在已结算小时边界运行 |
| 日程 | `V2ScheduleService` | 复用；玩家与 NPC 的方法都生成同一种 `social_action` 活动 |
| 就业 | `V2EmploymentService` | 复用合同、出勤与就业风险，不另建工资或工时 |
| 住户与资金 | `V2HouseholdService` + `V2LedgerService` | 复用；任何现金后果必须过账本 |
| 地点与旅行 | `SpatialLocationService`、旅行图、路线和执行服务 | 复用；任务准备与结算均重验实际地点 |
| 消息 | `CommunicationService` | 复用信件的发送、延迟、投递和阅读边界 |
| 认知 | `KnowledgeService` | 复用人物私有知识；客观事件账本不直接暴露给人物 |
| 关系 | `V23RelationshipService` | 复用定向多维关系；V2.2 旧关系仅保留作旧存档兼容 |
| 组织 | `V2OrganizationActivityService` | 扩展现有服务的组织、成员与唯一职位能力，不新建第二组织权威 |
| 存档 | `V23SaveService` / `V23SaveMigration` | 扩展同一快照与原子恢复；旧 V2.3 快照缺失沙盒字段时确定性补建 |
| 随机 | 稳定种子与任务稳定键 | 结果由任务 ID、方法 ID 和结算小时确定，不依赖字典遍历顺序 |

## 新增状态的归属

现有服务没有以下概念，因此由一个 `V23SocialSandboxService` 持有：

- 从真实状态派生、可失效的维护压力、威胁、机会和抱负；
- 目标、候选方法、统一意图和对应日程任务；
- 承诺、证据与方法执行的有限状态；
- 按 `world_hour / phase / sequence` 排序的追加式重要事件账本；
- NPC 决策解释、延迟反应队列和有界索引。

这些记录不得拥有时间、现金、位置、关系、知识或组织成员的副本。保存的
“处境”只作可解释缓存；每天及相关事件后都会从上述权威服务重新派生。

## 明确隔离

`SocietySimulationService`、`ActionService`、`SimpleAiService`、
`WorldActivityService` 与通用 `OrganizationService` 属于另一套 P0/网格夹具。
本重构不把它们接入 V2.3 产品入口，也不让两套系统共同写同一领域。

## 事件与原子性边界

每个到期社会任务按以下阶段处理：

1. 收集同一小时到期任务；
2. 只读准备并生成提案；
3. 以稳定键排序，解决人物时间、唯一职位、文件、现金等冲突；
4. 备份涉及的现有权威服务状态；
5. 提交领域变化并在同一成功边界追加客观事件；
6. 失败时恢复全部备份，不产生成功事件；
7. 事件提交后才向同地见证人或消息接收者写入人物认知，并排入有界反应。

`cause_event_id` 表示因果，`sequence` 只表示同相位排序，两者不可互相替代。

