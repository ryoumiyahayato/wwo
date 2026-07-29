# 变量、状态所有权与数据流审计

## 0. 审计边界

- 审计基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。
- 引擎：Godot 4.6.3；正式入口：`res://scenes/formal/formal_world_menu.tscn`。
- 本报告只持有审计结论；第一批实施方案由 [`variable_refactor_plan.md`](variable_refactor_plan.md) 单独持有。
- 1,613个生产成员字段的静态逐项索引由 [`variable_state_member_inventory.md`](variable_state_member_inventory.md) 单独持有。
- 本轮未修改 `scripts/`、`scenes/`、`data/` 或 `resources/`，未创建测试或存档fixture。
- 扫描范围为502个源/配置文件、255个GDScript文件。
- 静态写入者、读取者、持久化、fallback和分类均为候选证据；不同对象的同名字段不能据此自动合并。

## 1. 基线指标

| 指标 | 审计值 | 说明 |
|---|---:|---|
| 生产成员字段 | 1,613 | 包含常量、节点引用和可写成员 |
| 可写成员字段 | 1,243 | 排除`const`和`@onready` |
| 进程级全局可写字段 | 16 | `static var`，主要集中于`GameSessionService` |
| Autoload可写字段 | 0 | `project.godot`无Autoload |
| 持久化关联候选 | 472 | 静态证据上限，不是精确存档字段数 |
| UI显示副本候选 | 32 | 仍需逐项人工确认 |
| 命名缓存候选 | 16 | 投影和索引缓存另行审计 |
| 可推导成员候选 | 61 | 只有证明后才能删除 |
| K类、不得修改字段 | 885 | 语义未确认 |

## 2. 最严重的10组重复或混乱状态

| 等级 | 组 | 当前事实与问题 | 审计决定 |
|---|---|---|---|
| P0 | D01 正式时间三重表示及初始错位 | 半球UI、正式模拟和正式经济分别保存可写时间，且初始日期已经不同。 | 现存正确性缺陷，必须作为独立批次处理；本批不得顺带修复。 |
| P0 | D02 经济体—政治单元关系来源、索引和持久化混合 | 原始来源、双向索引、持久化副本和UI投影混在同一服务内。 | 分类型审计；不预设删除必要索引。 |
| P0 | D03 导航层级多个直接写入者 | `space_level/world_mode`由继承链多个脚本直接赋值，并手工同步viewport、渲染和选择清理。 | 建立转场行为基线后再处理。 |
| P0 | D04 一级行政选择平行状态 | 四个选择字段属于历史领土、历史几何、现代近似几何和名称目录等不同ID空间。 | 不按名称合并，先建立ID命名空间和crosswalk矩阵。 |
| P0 | D05 `selected_country_id`同名不同义 | 会话字段是玩家所属国家，半球字段是用户地图选择。 | 两者不得合并；会话字段的qualified证据见第6节。 |
| P1 | D06 当前玩家、角色和显示身份分立 | `player_character`、`active_character_key`、`selected_person_id`关系未定义。 | 人工定义active/displayed/selected后再处理。 |
| P1 | D07 事件、消息和未读数缺少正式所有者 | 半球展示事件、事件队列、通知和通信inbox并存。 | 确定正式业务服务，HUD只读。 |
| P1 | D08 旧地图画布—界面双写 | Canvas与Interface分别保存模式和选择，Controller同时写两边。 | 决定隔离或删除旧样机；若保留则UI只读。 |
| P1 | D09 跨服务同步复制业务事实 | 位置、债务、工人、容量和空缺被同步进第二容器。 | 分别选择空间、金融和劳动所有者。 |
| P1 | D10 存档兼容和fallback混入内部状态 | 多schema和缺省补写进入运行结构。 | 迁移只允许发生在加载边界。 |

## 3. 已确认的现存正确性缺陷：正式时间初始错位（P0）

该问题是审计确认的现存行为缺陷，不是本审计批引入，也不得在本批顺带修复。

1. 半球UI继承层将初始时间保存为`sim_year = 1900`、`sim_month = 3`、`sim_day = 12`、`sim_hour = 8`、`sim_minute = 0`，即 **1900-03-12 08:00**。证据：`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:48-54`。
2. `FormalWorldSimulation.total_minutes`和`_minute_remainder`初始化并重置为0；`FormalWorldEconomyService.total_hour`也初始化并重置为0。`V2DateTime`明确将累计小时0定义为 **1900-01-01 00:00**。证据：`scripts/formal/formal_world_simulation.gd:13-23`、`scripts/formal/formal_world_economy_service.gd:21-28,40-55`、`scripts/v2_2/v2_datetime.gd:3-18`。
3. `FormalWorldApplication._on_clock_timer_timeout()`先调用继承层`_advance_clock(minutes)`，随后调用`formal_simulation.advance_minutes(minutes)`，因此每次计时分别推进两套已经错位的时间。证据：`scripts/formal/formal_world_application.gd:34-41`。
4. 新游戏初始化只初始化`formal_simulation`并读取世界摘要，没有把半球`sim_*`设置为正式模拟时间。进入新游戏时两套时间已经相差70天8小时。
5. 启动继续游戏和F9读取只调用`formal_simulation.load_from_user()`并刷新摘要，没有从`formal_simulation.date_time()`恢复半球`sim_year/month/day/hour/minute`。证据：`scripts/formal/formal_world_application.gd:23-30,62-69`。

风险：HUD日期、经济结算日期和正式存档累计时间可以长期表示不同日期。后续必须作为“正式时间所有权”独立批次处理，并先建立新游戏、连续计时、保存和读取行为特征测试。

## 4. D02经济体—政治单元关系分类

不得把所有映射字段笼统称为“五份重复状态”，也不得预设所有索引均应删除。

| 类型 | 当前表示 | 语义和处理原则 |
|---|---|---|
| 权威原始来源 | `data/world_map/historical/major_economy_polity_crosswalk_1900.json`；一对一关系还可以由经济体ID直接匹配政治单元ID | 配置加载后应视为不可变输入。需要进一步明确直接匹配与显式crosswalk的优先级。 |
| 正向只读索引 | `FormalWorldEconomyService.economy_polity_ids` | 经济体ID到一个或多个政治单元ID。若查询频繁且由权威来源一次构建，可以保留，但必须禁止运行期任意改写。 |
| 反向只读索引 | `FormalWorldEconomyService.economy_by_polity_id` | 政治单元ID到经济体ID。它不是正向索引的同义字段，可能是必要的反向查询结构。 |
| 持久化重复字段 | `country_states[economy_id]["polity_ids"]` | 与正向索引表达相同关系，并写入正式经济存档；恢复旧存档时还会缺省补写。优先审计其是否应从存档删除并在加载后推导。 |
| UI展示投影 | `polity_records[polity_id]["economy_entity_id"]` | 用于政治单元摘要和UI展示。应确认它是只读投影还是业务状态；不得仅因重复ID就直接删除。 |
| 加载期原始记录缓存 | `_crosswalk_records` | 保存crosswalk记录本体。必须核对配置加载后是否还有读取用途，以及是否有明确不可变边界。 |

下一步需记录各索引的构建入口、所有写入点、查询次数、失效规则和存档依赖，再决定保留、改为只读或删除。当前审计不作索引删除结论。

## 5. 已确认的多写入、UI副本和停止项

已人工确认的多写入状态包括正式时间、导航层级、国家/区域/城市/行政选择、玩家国家、经济映射、旧地图模式/选择，以及跨服务位置、债务和劳动副本。

可列为UI或派生候选但尚未删除：

- `FormalWorldApplication._last_summary`：来自`formal_simulation.world_summary()`，在ready、tick和load后手工刷新。
- 旧`PrototypeV2Interface.current_mode/selected_object`：旧MapCanvas状态镜像。
- 旧`PrototypeV2Interface.paused/speed`：有binding时是时钟镜像，无binding时又自行成为事实源。
- `activity_unread`：展示层自写，未绑定正式消息服务。

当前不得安全修改：

1. 未建立fixture的正式、V2、V2.3和Alpha持久化字段。
2. 四种行政选择字段，直到ID命名空间确定。
3. `player_character/active_character_key/selected_person_id`，直到语义确定。
4. `space_level/world_mode`，直到导航特征测试覆盖所有转场。
5. 投影、空间索引、可见性、标签和文本缓存，直到记录缓存键、失效条件和性能基线。
6. `_panel_previous_*`、`_activity_panel_was_open`等可能用于恢复或边沿检测的状态。
7. 不同语义的selected、hovered、focused、active、pending、previous、requested、displayed、loaded、visible和enabled。

## 6. `GameSessionService.selected_country_id` qualified引用证据

以下结果按所有者、限定名和词法作用域逐项核验，不使用纯名称扫描代替qualified核验。实施方案和测试计划只记录在`variable_refactor_plan.md`。

### 6.1 成员声明

- `scripts/character/game_session_service.gd:11`：`GameSessionService.selected_country_id`。

### 6.2 合格读取点

- `scripts/save/game_save_service.gd:231`：`build_snapshot()`读取`GameSessionService.selected_country_id`并生成旧存档键。
- 全仓库未发现其他合格运行期读取点。

### 6.3 合格写入点

- `scripts/character/game_session_service.gd:29`：`set_player()`按`character.country_id`写入。
- `scripts/character/game_session_service.gd:47`：`clear()`写入空字符串。
- `scripts/character/game_session_service.gd:82`：`transfer_player()`按`character.country_id`写入。
- `scripts/character/succession_service.gd:280`：继承事务失败回滚后按`restored_player.country_id`恢复。
- `scripts/save/game_save_service.gd:509`：存档恢复通过一致性验证后，将函数局部候选值写回会话成员。

声明处的空字符串初始化是初始化值，不重复计入上述五个运行期写入点。

### 6.4 存档键

- `scripts/save/game_save_service.gd:231`：生成`"selected_country_id"`键。
- `scripts/save/game_save_service.gd:455-460`：读取旧键，验证国家存在，并要求它等于`restored_player.country_id`。
- `scripts/save/game_save_service.gd:603`：验证快照必须包含非空旧键。

### 6.5 同名但属于其他对象的成员

- `scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:23`：半球场景成员`selected_country_id`，表示用户选择的地图政治单元。它不是玩家所属国家副本，本批必须保持不变。
- 全仓库成员声明核验只发现上述两个`selected_country_id`成员。

### 6.6 函数局部同名变量

- `scripts/save/game_save_service.gd:455`：`restore_snapshot()`局部`selected_country_id`，保存从快照读取、尚未提交的候选值。它不是成员字段。
- 全仓库词法核验未发现其他`var selected_country_id`函数局部声明。

## 7. 文档职责边界

- 本文件持有审计结论和qualified证据。
- `variable_refactor_plan.md`持有第一批实施方案、测试计划、风险与停止条件。
- `variable_state_member_inventory.md`只持有静态成员索引证据，不重复D01–D10、实施建议、多写入总结、UI副本总结或停止项。
- `state_ownership_matrix.md`持有当前与目标所有权矩阵。
