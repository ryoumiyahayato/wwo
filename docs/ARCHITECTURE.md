# 架构

## 分层与依赖方向

```text
数据配置 -> 核心服务/数据模型 -> 模拟系统 -> 只读状态/事件 -> UI
                         \-> 存档服务
```

UI 不被核心模型依赖，也不包含模拟公式。实体间持久关系使用稳定 ID，不依赖场景节点引用。配置与权重集中在 `data/`，核心无场景服务位于 `scripts/core/`，领域代码按职责放在 `scripts/` 子目录。

## 已实现模块

- `scenes/menu/main_menu.tscn`：基础展示与入口。
- `scripts/ui/main_menu.gd`：绑定菜单文本和退出操作，不承载模拟逻辑。
- `scripts/ui/ui_strings.gd`：集中管理可见字符串。
- `scripts/core/log_service.gd`：无 UI 依赖的等级过滤和稳定日志格式。
- `tests/test_runner.gd`：历史综合回归。
- `tests/p0_r1_*.gd`、`tests/state_consistency_regression.gd`、`tests/simulation_quality_regression.gd`、`tests/codex_audit_regression.gd`：当前专项回归。
- `tools/run_validation.ps1`：干净检出导入、全局类缓存生成、全部测试和解析日志检查的统一入口。
- `data/balance/simulation_clock.json`：起始日期、现实秒换算和允许速度的唯一配置来源。
- `scripts/simulation/simulation_clock_config.gd`：读取并验证时间配置。
- `scripts/simulation/simulation_clock.gd`：持有整数小时、日历、周期信号和队列处理的唯一权威时钟。
- `scripts/simulation/simulation_event_queue.gd`：按到期小时和插入序号稳定排序的内存队列。
- `scripts/simulation/simulation_runner.gd`：唯一接收渲染帧增量的薄适配节点，只向时钟提交现实秒；页面间复用同一权威时钟。
- `scripts/core/stable_id_service.gd`：生成并恢复按命名空间递增的稳定 ID。
- `scripts/core/deterministic_random_service.gd`：业务随机调用的唯一入口，封装种子和 RNG 状态。
- `scripts/core/models/`：无 Node、无 UI 依赖的强类型可序列化模型。
- `scripts/core/core_data_loader.gd`：结构、ID 和跨引用两阶段验证，返回显式结果对象。
- `scripts/core/core_data_set.gd`：验证成功后按稳定 ID 建立的实体索引。
- `data/world/demo_world.json`：架空世界，包含 2 国、8 地区、80 控制单元、行动与组织定义。
- `scripts/map/map_rules_config.gd`：集中读取地图尺寸、缩放、控制阈值和压力倍率。
- `scripts/map/map_control_service.gd`：权威军事控制、铁路/社会支持/包围压力、地区摘要与增量前线边集合。
- `scripts/map/map_world_controller.gd`：通过核心加载器建立正式世界与地图服务。
- `scripts/map/strategic_map_canvas.gd`：单节点程序绘制与坐标命中，不持有权威控制逻辑。
- `scenes/map/strategic_map_view.tscn`：地图、时间工具栏和按变化刷新的地区信息面板。
- `data/characters/character_generation.json`：姓名池、人口职业倍率、能力键、年龄规则和倾向事件。
- `scripts/character/character_generator.gd`：注入正式世界、配置、统一 RNG 和稳定 ID 服务后确定性生成人物。
- `scripts/character/character_tendency_service.gd`：只在显式事件发生时更新单个人物倾向并刷新公开描述。
- `scripts/character/game_session_service.gd`：场景间权威内存会话。
- `scenes/character/`：国家/模式选择、公开人物预览和默认隐藏的开发者数据视图。
- `data/balance/action_rules.json`：行动公式、进度倍率、实践成长、精通保证和定性把握分档。
- `scripts/action/action_instance_data.gd`：可序列化的长期行动状态，不依赖节点或渲染帧。
- `scripts/action/action_service.gd`：开始、旧区间结算、依赖切换、暂停/恢复/取消、中断、阈值判定、技能成长和结果应用。
- `scripts/action/player_action_context_service.gd`：从权威人物、组织、关系、目标和玩家投入构建上下文。
- `scenes/action/action_panel.tscn`：技能选择、额外投入和固定开始按钮的正式行动界面，不包含公式。
- `data/balance/society_rules.json`：背景/活跃规模、组织经济、生命周期、关系默认值及 AI 候选。
- `scripts/character/character_roster_service.gd`：轻量背景与完整活跃人物索引、稳定身份升降级和 20 人上限。
- `scripts/organization/organization_service.gd`：组织成员、职位槽位和权限索引。
- `scripts/relationship/relationship_service.gd`：只为实际接触人物对创建的稀疏关系存储。
- `scripts/ai/simple_ai_service.gd`：每个活跃 NPC 的有限候选、长期行动状态和月度长期目标。
- `scripts/simulation/society_simulation_service.gd`：组合人物、组织、关系、行动、AI、生命周期和地区影响服务。
- `scenes/organization/social_system_panel.tscn`：组织、关系、合法退出原因和开发者 AI 调试界面。
- `data/balance/continuity_rules.json`：地区影响、退出约束、候选权重和部分继承比例。
- `scripts/map/regional_influence_service.gd`：社会影响、组织社会活动和组织军事支援的双通道边界。
- `scripts/character/succession_service.gd`：真实关系/组织候选、退出原因权威校验和部分继承。
- `scripts/save/game_save_service.gd`：临时恢复、地图回滚、人物上限、AI 覆盖和全局行动 ID 校验。

## 时间数据流与事件流

`SimulationRunner` 接收现实帧增量，`SimulationClock` 按配置换算并一次提交所有完整游戏小时；不足一小时的余量保留到下次调用。权威日期只在完整小时边界改变，UI 仅响应状态信号。

单个小时的实际顺序固定为：

```text
小时 → 日 → 月 → 到期队列事件 → 周/自动存档
```

同一到期小时的队列事件按插入顺序处理。周边界和自动存档位于领域日/月结算及到期事件之后，使存档包含该小时全部权威结果。后续系统必须订阅对应周期信号或显式排队，不得在自身 `_process()` 中推断日历边界。

## 核心数据加载流

```text
UTF-8 JSON
  → 顶层版本与集合检查
  → 字段类型、范围、ID 格式和全局唯一性
  → 强类型模型实例化与 ID 索引
  → 跨实体引用检查
  → CoreDataSet 或完整错误列表
```

无效数据不抛出到 UI，也不返回部分可用的数据集。所有正式数据与 fixture 必须经过同一加载器。随机业务必须注入 `DeterministicRandomService`，不得直接创建未封装 RNG。

## 地图控制与前线流

```text
正式 JSON → CoreDataLoader → CoreDataSet → MapControlService
                                            ├─ 控制单元变化 → 只更新相关邻接前线
                                            ├─ 地区摘要 → 信息面板
                                            └─ 边集合/只读模型 → StrategicMapCanvas
```

前线边以排序后的两个控制单元 ID 为唯一键。初始化扫描所有邻接一次；之后只有控制者变化才检查相关邻接。压力倍率读取铁路、地区影响、控制单元本地支持、多方向进攻和包围，但不改变前线拓扑的增量维护边界。

## 人物生成与信息流

```text
玩家明确国家/模式/种子 → CharacterGenerator → CharacterData
                                            ├─ 公开快照/定性倾向 → 正式 UI
                                            └─ 精确隐藏字段 → 显式开发者视图
```

完整人口模式先按人口群体人数选择地区和群体，再用群体职业类别修正职业权重。国家抽样和人物生成使用隔离随机流，保证背景人物的激活种子仍可独立恢复成长核心。

## 长期行动流

```text
ActionDefinition + Character + 权威上下文
                  → ActionService.start_action
                  → ActionInstanceData
时间或依赖边界 → 先按旧效率结算已过去区间
                  → 在边界验证新目标/权限/状态
                  → 中断或切换新上下文并重算后续效率
                  → 完成阈值 → 通用结果 → 领域写回
```

玩家可选择学习技能和额外财富投入。学习行动提高所选技能，其他行动产生主要技能实践成长。主技能达到精通且准备、资金达到配置阈值时，公式提供明确的保证成功上界。NPC 使用同一行动实例和结果规则，但仅在每日边界批量推进。

## 分层人物与 AI 流

```text
BackgroundCharacterData（无 AI）
          │ 显式升级且未达 20 人上限
          ▼
CharacterData 活跃层 → 每个非玩家必须有一个 AiStateData
          │ 每日：推进旧行动或开始有限候选行动
          └ 每月：组织经济、地区行动和长期目标评估
```

组织职位通过 `character → organization → position` 索引提供权限；关系通过排序人物对索引按需创建。背景人物不建立 AI 或可见节点。存档恢复要求所有活跃 NPC 与 AI 状态一一对应。

## 地区影响与继承流

```text
政策/社会活动 → RegionData.social_influence ─┐
军事控制支援 → MapControlService            ├─ 分离保存与显示
控制单元支持 → ControlUnitData.social_support ┘

当前玩家 → 合法退出原因 + 真实关系/共同组织候选
        → 部分资源/职位/关系合并 → ExitedCharacterRecord
        → GameSessionService.transfer_player → 同一地图与社会世界
```

退休、死亡、长期监禁和严重失势由人物权威状态决定；自愿退出保持为常规玩家选择。继承过程事务式保存人物、组织、关系和 AI 状态，保留继承者已有关系与组织身份。

## 存档边界

`GameSaveService` 是唯一文件持久化边界。加载先在临时社会组合根恢复人物、组织和关系，再临时应用存档地图，对玩家及 NPC 进行中行动执行权威校验；任何失败都恢复加载前地图。成功后才替换 `GameSessionService`。

恢复必须同时验证：

- 活跃人物不超过配置上限，人物层级标记正确。
- 激活种子完整覆盖所有人物且背景种子匹配。
- 每个活跃 NPC 恰有一个 AI 状态，玩家没有 AI 状态。
- 玩家和所有 NPC 的进行中行动实例 ID 全局唯一。
- 行动人物、目标、权限、费用、上下文、公式和 ID 计数器有效。

`AutosaveCoordinator` 只监听权威周信号。`SettlementLogService` 保存有限条重大结算记录，`PerformanceStatsService` 只聚合分类次数及耗时，不输出逐小时日志。

## 更新频率

- 每帧：仅必要显示和输入，不运行全世界模拟。
- 每游戏小时：玩家长期行动、显式调度和地图控制压力。
- 每日：活跃 NPC 长期行动推进与新决策。
- 每月：组织收入、组织地区行动和长期 AI 计划。
- 每年：人物增龄、健康衰退、退休/死亡和领导补位。
- 每周边界：在小时、日/月与到期事件之后执行自动存档。

具体平衡值统一记录于 `data/balance/` 和 `docs/SIMULATION_RULES.md`。
