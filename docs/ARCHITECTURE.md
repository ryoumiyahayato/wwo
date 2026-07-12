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
- `scripts/ui/ui_strings.gd`：集中管理 M0 可见字符串。
- `scripts/core/log_service.gd`：无 UI 依赖的等级过滤和稳定日志格式。
- `tests/test_runner.gd`：从命令行加载项目配置、文档、日志和菜单场景。
- `data/balance/simulation_clock.json`：起始日期、现实秒换算和允许速度的唯一配置来源。
- `scripts/simulation/simulation_clock_config.gd`：读取并验证时间配置。
- `scripts/simulation/simulation_clock.gd`：持有整数小时、日历、周期信号和队列处理的唯一权威时钟。
- `scripts/simulation/simulation_event_queue.gd`：按到期小时和插入序号稳定排序的内存队列。
- `scripts/simulation/simulation_runner.gd`：唯一接收渲染帧增量的薄适配节点，只向时钟提交现实秒。
- `scenes/world/simulation_clock_view.tscn`：通过信号读取时间并发送暂停、速度和单步命令。
- `scripts/core/stable_id_service.gd`：生成并恢复按命名空间递增的稳定 ID。
- `scripts/core/deterministic_random_service.gd`：业务随机调用的唯一入口，封装种子和 RNG 状态。
- `scripts/core/models/`：八类无 Node、无 UI 依赖的强类型可序列化模型。
- `scripts/core/core_data_loader.gd`：结构/ID 和跨引用两阶段验证，返回显式结果对象。
- `scripts/core/core_data_set.gd`：验证成功后按稳定 ID 建立的实体索引。
- `data/world/demo_world.json`：M3 正式架空世界，包含 2 国、8 地区和 80 单元的显式坐标、邻接、城市与铁路。
- `scripts/map/map_rules_config.gd`：集中读取地图尺寸、缩放和控制阈值。
- `scripts/map/map_control_service.gd`：权威军事控制、压力、地区摘要与增量前线边集合。
- `scripts/map/map_world_controller.gd`：通过 M2 加载器建立正式世界与地图服务。
- `scripts/map/strategic_map_canvas.gd`：单节点程序绘制与坐标命中，不持有权威控制逻辑。
- `scenes/map/strategic_map_view.tscn`：地图、时间工具栏和按变化刷新的地区信息面板。
- `data/characters/character_generation.json`：姓名池、职业权重、能力键、年龄规则和倾向事件的唯一配置来源。
- `scripts/character/character_generator.gd`：注入正式世界、配置、统一 RNG 和稳定 ID 服务后确定性生成单个人物。
- `scripts/character/character_tendency_service.gd`：只在显式事件发生时更新单个人物倾向并刷新公开定性描述。
- `scripts/character/game_session_service.gd`：M4 场景间轻量内存会话，不承担存档职责。
- `scenes/character/`：国家/模式选择、公开人物预览和默认隐藏的开发者数据视图。
- `data/balance/action_rules.json`：M5 全局行动公式、进度倍率、状态修正和定性把握分档。
- `scripts/action/action_instance_data.gd`：可序列化的长期行动状态，不依赖节点或渲染帧。
- `scripts/action/action_service.gd`：开始、按时间差结算、依赖重算、暂停/恢复/取消、中断、阈值判定和结果应用。
- `scenes/action/action_panel.tscn`：战略地图上的单人物行动适配界面，不包含行动公式。
- `data/balance/society_rules.json`：背景/活跃规模、关系默认值及 AI 候选和权重。
- `scripts/character/character_roster_service.gd`：轻量背景与完整活跃人物索引、稳定身份升降级和 20 人上限。
- `scripts/organization/organization_service.gd`：组织成员、职位槽位和权限索引。
- `scripts/relationship/relationship_service.gd`：只为实际接触人物对创建的稀疏关系存储。
- `scripts/ai/simple_ai_service.gd`：活跃 NPC 的有限候选每日决策与月度长期目标。
- `scripts/simulation/society_simulation_service.gd`：组合 M6 服务并接入权威日/月事件。
- `scenes/organization/social_system_panel.tscn`：组织、职位、关系、层级和显式开发者 AI 调试界面。
- `data/balance/continuity_rules.json`：地区影响、组织资源消耗、退出原因、候选权重和部分继承比例。
- `scripts/map/regional_influence_service.gd`：社会影响、组织社会活动和组织军事支援的双通道边界。
- `scripts/character/succession_service.gd`：真实关系/组织候选、退出记录及部分资源、职位和关系继承。

## 时间数据流与事件流

`SimulationRunner` 接收现实帧增量，`SimulationClock` 按配置换算并一次提交所有完整游戏小时；不足一小时的余量保留到下次调用。权威日期只在完整小时边界改变，UI 仅响应状态信号。单个小时的信号顺序固定为：小时 → 日 → 周 → 月 → 到期队列事件。同一到期小时的队列事件按插入顺序处理。

后续系统必须订阅对应周期信号或显式排队，不得在自身 `_process()` 中推断日历边界。长期行动仍应按权威时间差计算，而非逐小时或逐帧更新每个人物。

## 核心数据加载流

```text
UTF-8 JSON
  → 顶层版本与集合检查
  → 字段类型、范围、ID 格式和全局唯一性
  → 强类型模型实例化与 ID 索引
  → 跨实体引用检查
  → CoreDataSet 或完整错误列表
```

无效数据不抛出到 UI，也不返回部分可用的数据集。M2 fixture 只验证边界；M3 正式世界必须经过同一加载器。后续随机业务必须注入 `DeterministicRandomService`，不得直接创建 `RandomNumberGenerator`。

## 地图控制与前线流

```text
正式 JSON → CoreDataLoader → CoreDataSet → MapControlService
                                            ├─ 控制单元变化 → 只更新相关邻接前线
                                            ├─ 地区摘要 → 信息面板
                                            └─ 边集合/只读模型 → StrategicMapCanvas
```

前线边以排序后的两个控制单元 ID 为唯一键。初始化扫描所有邻接一次；之后只有控制者变化才检查该单元邻接。争夺度、强度和社会支持变化只重绘相关显示，不触发全地图拓扑扫描。地图画布集中绘制 80 单元，不为每个单元创建节点。

## 人物生成与信息流

```text
玩家明确国家/模式/种子 → CharacterGenerator → CharacterData
                                            ├─ to_public_dict / 定性倾向 → 正式 UI
                                            └─ 精确隐藏字段 → 显式开发者视图
```

每次生成使用新注入的 RNG 和 ID 服务，因此相同国家、模式、类别与种子产生完全相同人物。生成与倾向事件都是按操作执行，不在 `_process()` 中轮询。

## 长期行动流

```text
ActionDefinition + Character + 输入上下文
                  → ActionService.start_action
                  → ActionInstanceData
权威小时/依赖变化 → 结算旧时间段 → 重算效率与预计完成时间
                  → 完成阈值 → 一次性人物/地图结果
```

行动服务不实现 `_process()`，也不持有人物集合。UI 只在权威时间信号、玩家输入或行动状态改变时刷新。M6 已提供组织、关系和职位服务；M5 领域效果到这些服务的自动分派仍留作后续整合，地区影响由 M7 接续。

## 分层人物与 AI 流

```text
120 名 BackgroundCharacterData（无 AI）
          │ 显式升级且未达 20 人上限
          ▼
CharacterData 活跃层 → SimpleAiService 状态（玩家除外）
          │ 每日：有限候选短期决策
          └ 每月：长期目标评估
```

组织职位通过 `character → organization → position` 索引提供权限；关系通过排序人物对索引按需创建。两者都使用稳定 ID，不建立人物节点引用或全人物关系矩阵。社会 UI 只在操作或周期信号后刷新。

## 地区影响与继承流

```text
政策/社会活动 → RegionData.social_influence ─┐
军事控制支援 → MapControlService            ├─ 分离保存与显示
                                              ┘

当前玩家 → 真实关系/共同组织候选 → 选择退出原因
        → 部分资源/职位/关系转移 → ExitedCharacterRecord
        → GameSessionService.transfer_player → 同一地图与社会世界
```

继承不会调用场景切换、重新加载世界或重新初始化社会服务。前人物退出和新玩家切换都使用稳定人物 ID；M8 只需序列化既有状态，不能重新执行候选评分或继承公式。

## M8 存档与开发工具边界

`GameSaveService` 是唯一文件持久化边界。各权威服务只暴露强类型状态快照与验证恢复方法，不自行打开文件。加载先重建临时社会组合根，再恢复地图与时钟，成功后才替换 `GameSessionService` 引用；候选评分、行动结果和继承公式都不会在加载时重放。

`AutosaveCoordinator` 只监听权威周信号，不参与渲染帧。`DeveloperCommandService` 集中所有调试变更并检查开发模式标记；开发 UI 不直接写模型。`SettlementLogService` 保存有限条重大结算记录，`PerformanceStatsService` 只聚合分类次数及耗时，不输出逐小时日志。

## M9 核心循环整合

行动面板根据行动类别选择稳定目标 ID：人物用于关系与调查，组织用于加入与职位，控制单元用于政策和军事支援。`ActionService` 仍只负责时间、阈值和通用数值结果；完成后由 `SocietySimulationService.apply_action_domain_effect()` 把成功的领域结果写入关系、成员、职位、情报或地区影响服务，并通过 `domain_effect_applied` 保持幂等。

这种分层让社会面板的直接按钮继续作为开发验证入口，同时正式玩家闭环不再依赖这些按钮。失败行动会消费领域钩子但不创建实体，加载存档也不会重放领域结果。

## 更新频率

- 每帧：仅必要显示和输入，不运行全世界模拟。
- 每游戏小时：控制压力或显式调度项。
- 每日：活跃人物短期决策与基础生产。
- 每周：关系、工资及部分倾向。
- 每月：人口群体和长期 AI 计划。

具体临时值统一记录于 `docs/SIMULATION_RULES.md`。M1 只实现时钟和调度基础设施，尚无世界系统订阅这些事件。
