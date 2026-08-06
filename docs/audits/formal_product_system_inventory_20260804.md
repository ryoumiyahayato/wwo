# 正式产品系统清单（2026-08-04）

## 读法

本清单固定于 `0feed6add253cead359a9e41f85e09bdf84c24e7`。每个系统均列出正式入口、生产文件/符号、权威状态、读写者、生命周期、持久化、玩家表面、数据、依赖、测试/CI、文档、12 个评估维度和成熟度。证据 ID 的完整路径、符号、支持范围与反证边界见 `artifacts/formal-product-system-completeness.json`。

维度状态为 `VERIFIED`、`PARTIAL`、`MISSING`、`NOT_APPLICABLE` 或 `UNKNOWN`。成熟度不是代码量，而是正式入口可达、组合、玩家表面、持久化与因果闭环的综合判断。

## A. 产品入口与会话生命周期

- 成熟度：`PLAYER_LOOP_PARTIAL`。
- 正式入口：`project.godot -> scenes/formal/formal_world_menu.tscn`。
- 生产文件/关键符号：`scenes/formal/formal_world_menu.tscn`、`scenes/formal/formal_world_main.tscn`、`scripts/formal/formal_world_menu.gd` 的 `_enter_world`、`scripts/formal/formal_world_application.gd` 的 `_ready`、`scripts/formal/formal_world_simulation.gd` 的 `initialize`。
- 权威状态：场景树启动模式、场景局部 `FormalWorldSimulation`、继承 UI 的导航状态；没有权威玩家会话 owner。
- 写入者/读取者：`FormalWorldMenu`、`FormalWorldApplication`、`FormalWorldSimulation` 写；应用、菜单和正式 UI draw 方法读。
- 生命周期：菜单按存档存在性决定 new/load，主场景初始化，timer 驱动；没有显式 session shutdown/退出 owner。
- 持久化：只恢复时间和经济；启动模式、玩家和 UI 会话状态不保存。
- 玩家表面：任意键菜单、自动继续提示、正式地图、F5/F9 和屏幕保存/读取按钮。
- 数据：无专属数据集；依赖 B、C、F、K、L、M；被 O 依赖。
- 测试/CI：`tests/formal/formal_world_integration_test.gd`、`tests/variable_state/formal_time_known_defects_test.gd`；发布 UI 与 Windows release workflow。
- 文档：`docs/economy/formal_world_integration.md`、`docs/refactors/formal_time_single_source.md`。
- 12 维：implementation `VERIFIED`（E001–E004）；runtime_reachability `VERIFIED`（E001、E011）；integration `PARTIAL`（E004、E006、E007）；player_surface `PARTIAL`（E002、E038）；state_ownership `PARTIAL`（E045、E046）；lifecycle `PARTIAL`（E002、E004、E038）；persistence `PARTIAL`（E007、E018）；causal_feedback `PARTIAL`（E039）；data_readiness `VERIFIED`（E008、E041）；verification `PARTIAL`（E011、E048）；observability `PARTIAL`（E016）；maintainability `PARTIAL`（E040、E046）。
- 结论：入口、自动新建/续档、初始化、时间、保存读取可达；缺少权威玩家、业务行动、显式退出和完整恢复边界。

## B. 时间与模拟调度

- 成熟度：`INTEGRATED_VERIFIED`。
- 正式入口：`FormalWorldApplication._advance_simulation_minutes`。
- 生产文件/关键符号：`scripts/formal/formal_world_simulation.gd` 的 `total_minutes`/`advance_minutes`，`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd` 的 timer/input，`scripts/v2_2/v2_datetime.gd`。
- 权威状态：`FormalWorldSimulation.total_minutes`；继承 UI 持有暂停/倍速控制；经济只接收注入的权威小时。
- 写入者/读取者：`advance_minutes`、`restore_persistent_state` 和 UI 按钮动作写；应用、经济服务、时间 HUD 读。
- 生命周期：场景 ready 初始化，未暂停时由 `ClockTimer` 推进，存档恢复；没有其它正式系统订阅调度。
- 持久化：累计分钟、受校验的分钟余数和经济小时。
- 玩家表面：日期/时间、暂停、1×/2×/4×。
- 数据：无；依赖 A、F；被 F、K、L 依赖。
- 测试/CI：正式集成、formal time stable/known-defect tests；`formal-time-behavior-baseline.yml`。
- 文档：`docs/refactors/formal_time_behavior_baseline.md`、`docs/refactors/formal_time_single_source.md`。
- 12 维：implementation `VERIFIED`（E005、E006）；runtime_reachability `VERIFIED`（E004、E005）；integration `VERIFIED`（E006、E009）；player_surface `VERIFIED`（E005）；state_ownership `VERIFIED`（E006、E012）；lifecycle `PARTIAL`（E003、E005、E006）；persistence `VERIFIED`（E007、E012）；causal_feedback `VERIFIED`（E006、E009）；data_readiness `VERIFIED`（E006）；verification `VERIFIED`（E011、E012、E049）；observability `PARTIAL`（E016）；maintainability `PARTIAL`（E030、E040）。
- 结论：正式单一累计时间、暂停/倍速、经济调度和往返已验证；正式调度目前只有经济消费者。

## C. 世界状态与地理空间

- 成熟度：`PLAYER_LOOP_PARTIAL`。
- 正式入口：`FormalWorldApplication` 继承的 holographic workspace draw/input 链。
- 生产文件/关键符号：`holographic_workspace_historical_admin_runtime.gd`、`holographic_workspace_historical_evidence.gd`、`holographic_workspace_history.gd`、`holographic_workspace_runtime.gd`；`_rebuild_historical_political_world`、`_selected_polity_entity_id`、`selected_country_id`、`space_level`。
- 权威状态：多个 UI selection ID 与几何/index cache；政治记录和经济记录分开查询；没有玩家位置 owner。
- 写入者/读取者：workspace 输入/导航方法写；地图 draw 和 `FormalWorldApplication._selected_polity_entity_id` 读。
- 生命周期：ready 时加载/索引，导航和缩放时重建 cache；无旅行生命周期。
- 持久化：地图选择、玩家位置和旅行状态均不在正式存档。
- 玩家表面：可旋转历史半球、政治聚焦、行政/城市/机构浏览、现代参考下级层。
- 数据：`cities.json`、`cshapes_1900_snapshot.json`、`political_units_1900.json`、`world_admin1.json`；依赖 A、M；被 F、K 依赖。
- 测试/CI：正式集成、V2.3 player interface retained test；release UI workflow。
- 文档：`docs/MAP_DATA_AND_RENDERING.md`、`docs/SPATIAL_REACH_TRAVEL_AND_COMMUNICATION.md`。
- 12 维：implementation `VERIFIED`（E003、E017）；runtime_reachability `VERIFIED`（E003、E040）；integration `PARTIAL`（E044）；player_surface `VERIFIED`（E017、E048）；state_ownership `PARTIAL`（E017、E046）；lifecycle `PARTIAL`（E017）；persistence `MISSING`（E018）；causal_feedback `MISSING`（E039、E044）；data_readiness `PARTIAL`（E028、E029、E043、E052）；verification `PARTIAL`（E011、E048、E050）；observability `PARTIAL`（E016）；maintainability `MISSING`（E040、E043）。
- 结论：这是可用的历史导航投影，不是权威位置、路径或旅行系统。

## D. 玩家与角色

- 成熟度：`IMPLEMENTED_ISOLATED`。
- 正式入口：`holographic_workspace_runtime._load_all_data -> characters.json`。
- 生产文件/关键符号：正式 UI runtime；隔离的 `scripts/character/game_session_service.gd`、`scripts/action/action_service.gd`、`scripts/core/models/character_data.gd`；`active_character_key`、`GameSessionService.player_character`、`ActionService.start_action`。
- 权威状态：正式只有静态 profile key；隔离核心另有权威 player object。正式 needs/health/assets/action owner 缺失。
- 写入者/读取者：正式只允许 `switch_character` 改视角；隔离 GameSession/Action 服务自行写；正式人物 HUD 和隔离测试分别读。
- 生命周期：正式档案加载一次；核心玩家/行动生命周期未组合。
- 持久化：正式存档不含 profile/选择；核心玩家另有协议。
- 玩家表面：只读人物卡和视角切换，无生产行动。
- 数据：`character_generation.json`、`data/world_map/characters.json`；依赖 A、B、H；被 E、F、I 依赖。
- 测试/CI：`tests/codex_audit_regression.gd`、旧 `p0_r1_player_journey_current.gd`；统一验证仅保留服务范围。
- 文档：`docs/PLAYER_LAYERS_AND_PERMISSIONS.md`、`docs/TIME_ATTENTION_AND_ACTIVITY_MODEL.md`。
- 12 维：implementation `PARTIAL`（E019–E021）；runtime_reachability `PARTIAL`（E019、E032）；integration `MISSING`（E032、E039）；player_surface `PARTIAL`（E019）；state_ownership `MISSING`（E020、E045、E046）；lifecycle `MISSING`（E019、E020）；persistence `MISSING`（E018、E046）；causal_feedback `MISSING`（E039）；data_readiness `PARTIAL`（E019）；verification `PARTIAL`（E042、E050）；observability `MISSING`（E016）；maintainability `MISSING`（E040、E046）。
- 结论：仓库有玩家/行动实现，正式产品只有静态人物投影；两者不能相互证明。

## E. 家庭与社会

- 成熟度：`IMPLEMENTED_ISOLATED`。
- 正式入口：静态人物与机构投影。
- 生产文件/关键符号：`relationship_service.gd`、`society_simulation_service.gd`、`v2_household_service.gd`、`communication_service.gd`；`create_or_update`、`initialize`。
- 权威状态：无正式社会 owner；UI 静态投影与隔离关系/通信 store 并存。
- 写入者/读取者：正式仅 `mark_read` 写 UI 未读状态；隔离服务自行写；静态 HUD 和旧接口/测试分别读。
- 生命周期：无正式社会初始化或 tick 订阅。
- 持久化：正式存档不含关系、家庭、消息、知识。
- 玩家表面：静态已知 agenda；没有关系或通信命令。
- 数据：`communication_channels.json`、人物和机构 JSON；依赖 D、H、I；被 J 依赖。
- 测试/CI：V2.3 communication/relationship/social sandbox tests；统一验证的 retained service 回归。
- 文档：`docs/HOUSEHOLD_AND_FAMILY_MODEL.md`、`docs/SOCIAL_ORGANIZATION_INSTITUTION_MODEL.md`。
- 12 维：implementation `VERIFIED`（E022、E025、E026）；runtime_reachability `MISSING`（E032）；integration `MISSING`（E024、E025）；player_surface `PARTIAL`（E019、E024）；state_ownership `MISSING`（E024、E025、E046）；lifecycle `MISSING`（E022、E032）；persistence `MISSING`（E018、E025）；causal_feedback `MISSING`（E024、E039）；data_readiness `PARTIAL`（E019、E024）；verification `PARTIAL`（E026、E034、E042）；observability `MISSING`（E016）；maintainability `PARTIAL`（E040、E046）。
- 结论：隔离实现较多，但正式关系—知识—行动—持久化链不存在。

## F. 经济与市场

- 成熟度：`PLAYER_LOOP_PARTIAL`。
- 正式入口：`FormalWorldSimulation.economy -> FormalWorldEconomyService`。
- 生产文件/关键符号：`formal_world_economy_service.gd`、`alpha_historical_world_economy_data.gd`；`configure`、`_settle_day`、`_schedule_shortage_shipments`、`world_summary`。
- 权威状态：经济服务持有 country states、routes、shipments、history、indexes 和日结边界。
- 写入者/读取者：configure/settle/restore 写；正式应用政经面板和 `FormalWorldSimulation` 读。
- 生命周期：new/load 初始化；跨小时/日边界结算；在正式恢复事务内恢复。
- 持久化：time-coupled economy schema v1–v3；外层文件直接覆盖，`_last_day_index` 有一致性缺口。
- 玩家表面：世界满足率与所选政治单元摘要；无购买、工作、生产、投资命令。
- 数据：Alpha 1900 商品/交通/经济数据和 major economy crosswalk；依赖 B、C、M；被 A、K、L 依赖。
- 测试/CI：正式集成与十年平衡；Alpha commodity economy 和 Windows release workflow。
- 文档：`docs/economy/1900_economy_integration_phase2_validation.md`、`docs/economy/formal_world_integration.md`。
- 12 维：implementation `VERIFIED`（E008、E009）；runtime_reachability `VERIFIED`（E004、E006）；integration `VERIFIED`（E006、E044）；player_surface `PARTIAL`（E004、E031、E039）；state_ownership `PARTIAL`（E010、E031）；lifecycle `VERIFIED`（E006、E008、E009）；persistence `PARTIAL`（E007、E010、E023）；causal_feedback `PARTIAL`（E009、E039）；data_readiness `PARTIAL`（E028、E041）；verification `VERIFIED`（E011、E013、E014）；observability `PARTIAL`（E016）；maintainability `PARTIAL`（E030、E040、E046）。
- 结论：聚合经济真实接入并稳定，但还不是玩家生活经济。

## G. 政治、法律与国家能力

- 成熟度：`IMPLEMENTED_ISOLATED`。
- 正式入口：历史政治地图与 polity summary 投影。
- 生产文件/关键符号：`alpha_politics_service.gd`、正式经济服务、`holographic_workspace_historical_evidence.gd`；`AlphaPoliticsService`、`_build_dated_historical_unit`、`polity_summary`。
- 权威状态：政治记录主要是不可变投影；controller/sovereign 未分；无政治变迁 owner。
- 写入者/读取者：正式仅数据 loader 写内存投影；隔离 AlphaPolitics 自写；地图和政经面板读。
- 生命周期：场景/经济初始化加载；无正式政治 tick 或 transition。
- 持久化：无可变政治/法律状态。
- 玩家表面：边界、状态、关系、controller 和国家概况文本；无政策行动。
- 数据：Alpha politics、major state profiles、political units；依赖 C、M；被 F、H、J 依赖。
- 测试/CI：Alpha organization/politics test 与正式集成；Alpha fixture 隔离。
- 文档：`docs/LAW_RIGHTS_AND_STATE_CAPACITY.md`、`docs/POLITICS_COALITIONS_AND_LEGITIMACY.md`。
- 12 维：implementation `PARTIAL`（E027、E052）；runtime_reachability `PARTIAL`（E008、E017）；integration `PARTIAL`（E044）；player_surface `PARTIAL`（E004、E017）；state_ownership `MISSING`（E027、E046）；lifecycle `MISSING`（E032、E039）；persistence `MISSING`（E018）；causal_feedback `MISSING`（E039）；data_readiness `PARTIAL`（E028、E029、E043、E052）；verification `PARTIAL`（E011、E034）；observability `PARTIAL`（E016）；maintainability `MISSING`（E027、E040）。
- 结论：静态政治可读，政治/法律/国家能力模拟不可玩且无正式 owner。

## H. 组织、机构与职业

- 成熟度：`IMPLEMENTED_ISOLATED`。
- 正式入口：workspace institutions 投影。
- 生产文件/关键符号：`alpha_enterprise_service.gd`、`organization_service.gd`、`society_simulation_service.gd`、正式 UI runtime；`join_organization`、`assign_position`、`_seed_world_events`。
- 权威状态：正式 UI 静态 institution dictionary；隔离 `OrganizationService` 另持 membership/position。
- 写入者/读取者：正式仅 loader；隔离 OrganizationService 写；地图/HUD 与隔离社会/行动系统读。
- 生命周期：正式只在加载时初始化静态内容。
- 持久化：无正式组织/职业状态；隔离服务有平行协议。
- 玩家表面：查看机构和 agenda；无加入、工作、权限或决策命令。
- 数据：institutions/organizations JSON；依赖 D、E、G；被 I、J 依赖。
- 测试/CI：Alpha labor/enterprise test、旧 test runner organization tests；只有隔离/retained 回归。
- 文档：`docs/SOCIAL_ORGANIZATION_INSTITUTION_MODEL.md`、`docs/STATE_AND_LIFE_ECONOMY.md`。
- 12 维：implementation `VERIFIED`（E022）；runtime_reachability `PARTIAL`（E017、E032）；integration `MISSING`（E024、E032）；player_surface `PARTIAL`（E017、E024）；state_ownership `MISSING`（E022、E024、E046）；lifecycle `MISSING`（E017、E032）；persistence `MISSING`（E018）；causal_feedback `MISSING`（E024、E039）；data_readiness `PARTIAL`（E024）；verification `PARTIAL`（E034、E042）；observability `MISSING`（E016）；maintainability `PARTIAL`（E040、E046）。
- 结论：静态机构可读，组织成员、职业和权限未进入正式会话。

## I. 信息、知识、媒体与事件

- 成熟度：`IMPLEMENTED_ISOLATED`。
- 正式入口：`holographic_workspace_runtime._seed_world_events`。
- 生产文件/关键符号：`world_activity_service.gd`、正式 UI runtime、V2.3 communication/knowledge services；`add_event`、`_world_events`、`activity_unread`。
- 权威状态：UI 自有 seeded events/unread；另有可持久化 activity 和知识/通信候选；未选正式 owner。
- 写入者/读取者：UI seed/mark_read 与隔离服务分别写；活动 HUD 和旧接口/测试分别读。
- 生命周期：ready 时 seed 一次；没有正式触发、传播或调度。
- 持久化：事件、知识、通信、未读均不在正式存档。
- 玩家表面：可查看已知机构 agenda/事件位置；无通信或知识约束行动。
- 数据：communication channels、knowledge rules、institutions；依赖 E、H；被 J、K 依赖。
- 测试/CI：V2.3 communication/knowledge tests；retained service 回归。
- 文档：`docs/EVENT_AND_AI_SIMULATION.md`、`docs/INFORMATION_KNOWLEDGE_AND_MEDIA.md`。
- 12 维：implementation `VERIFIED`（E024–E026）；runtime_reachability `PARTIAL`（E024、E032）；integration `MISSING`（E024、E025）；player_surface `PARTIAL`（E024）；state_ownership `MISSING`（E024、E025、E046）；lifecycle `PARTIAL`（E024）；persistence `MISSING`（E018、E025）；causal_feedback `MISSING`（E024、E039）；data_readiness `PARTIAL`（E024）；verification `PARTIAL`（E026、E034）；observability `PARTIAL`（E016、E024）；maintainability `MISSING`（E040、E046）。
- 结论：UI 事件是展示层状态，不是权威世界事件；孤立服务不能补足这一点。

## J. AI 与自主模拟

- 成熟度：`IMPLEMENTED_ISOLATED`。
- 正式入口：无。
- 生产文件/关键符号：`ai_state_data.gd`、`simple_ai_service.gd`、`alpha_ai_service.gd`、`society_simulation_service.gd`；`run_daily_decisions`、`_execute_ai_daily_actions`。
- 权威状态：无正式 AI 状态；核心和 Alpha 各持平行 AI state。
- 写入者/读取者：只有隔离 AI/社会服务写；隔离测试和旧产品读。
- 生命周期：无正式注册、预算、决策 schedule 或 shutdown。
- 持久化：正式不含 AI；核心/Alpha schema 不同。
- 玩家表面：无意图、行动或后果展示。
- 数据：Alpha presets、society rules；依赖 B、D、E、G、H、I；无正式 dependent。
- 测试/CI：Alpha AI/economy stability 与旧 society AI tests；fixture 隔离。
- 文档：`docs/EVENT_AND_AI_SIMULATION.md`、`docs/PERFORMANCE_BUDGET.md`。
- 12 维：implementation `VERIFIED`（E022）；runtime_reachability `MISSING`（E032）；integration `MISSING`（E032、E039）；player_surface `MISSING`（E039）；state_ownership `UNKNOWN`（E022、E046）；lifecycle `MISSING`（E022、E032）；persistence `MISSING`（E018、E046）；causal_feedback `MISSING`（E039）；data_readiness `PARTIAL`（E022）；verification `PARTIAL`（E034、E042）；observability `MISSING`（E016）；maintainability `PARTIAL`（E040、E046）。
- 结论：仓库有 AI 代码，但正式运行没有 AI。

## K. UI、反馈与可操作性

- 成熟度：`PLAYER_LOOP_PARTIAL`。
- 正式入口：formal menu/main scenes。
- 生产文件/关键符号：`formal_world_application.gd`、`formal_world_menu.gd`、workspace runtime；`_activate_button`、`_draw`、`_draw_formal_polity_panel`、`_gui_input`。
- 权威状态：深继承 UI selection/cache、`_last_summary` 投影和经济面板 flag；业务事实不应由其拥有。
- 写入者/读取者：refresh/input/button actions 写 UI；draw 方法读；只有时间/保存/读取调用正式模拟写入口。
- 生命周期：ready 加载、受控 timer redraw、交互 cache invalidation。
- 持久化：UI 状态不保存。
- 玩家表面：标题、地图、HUD、时间、政经、保存读取和数据错误。
- 数据：`data/world_map/*` 与 historical 子树；依赖 A、B、C、F、I、M；被 O 依赖。
- 测试/CI：正式集成、UI capture、V2.3 interface retained test；release UI workflow。
- 文档：`docs/UI_INFORMATION_ARCHITECTURE.md`、`docs/ui_spikes/holographic_workspace_spike.md`。
- 12 维：implementation `VERIFIED`（E002–E004、E017）；runtime_reachability `VERIFIED`（E001、E011）；integration `PARTIAL`（E039、E044）；player_surface `VERIFIED`（E005、E017、E038）；state_ownership `PARTIAL`（E018、E024、E045）；lifecycle `PARTIAL`（E003、E005、E017）；persistence `MISSING`（E018）；causal_feedback `PARTIAL`（E009、E039、E044）；data_readiness `PARTIAL`（E029、E043）；verification `PARTIAL`（E011、E015、E048、E050）；observability `PARTIAL`（E016）；maintainability `MISSING`（E040）。
- 结论：观察与导航表面真实可用，多数交互不产生权威世界后果。

## L. 保存、加载与兼容性

- 成熟度：`PLAYER_LOOP_PARTIAL`。
- 正式入口：`FormalWorldMenu._formal_save_exists`、`FormalWorldSimulation.save_to_user/load_from_user`。
- 生产文件/关键符号：正式 simulation/economy、隔离 `atomic_json_file_store.gd` 与 `game_save_service.gd`；`SAVE_PATH`、`SCHEMA_ID`、`get_persistent_state`、`restore_persistent_state`。
- 权威状态：formal outer v2 包装 economy v1–v3；核心/V2/Alpha 协议仍平行存在。
- 写入者/读取者：正式 simulation 写磁盘；菜单和 simulation 读。
- 生命周期：菜单自动探测；load 先初始化 fresh target，再验证并提交；无坏档隔离/backup。
- 持久化：只对正式时间/经济子集完整；直接 `WRITE` 覆盖文件。
- 玩家表面：自动 continue、F5/F9、屏幕按钮和布尔结果文本。
- 数据：无；依赖 A、B、F；被 A、O 依赖。
- 测试/CI：十年经济、formal time stable/known-defect；formal time baseline 与 Windows release workflow。
- 文档：`docs/SAVE_FORMAT.md`、PR #38 变量审计、formal time single source。
- 12 维：implementation `VERIFIED`（E002、E007）；runtime_reachability `VERIFIED`（E002、E004）；integration `PARTIAL`（E007、E018、E046）；player_surface `VERIFIED`（E004、E038）；state_ownership `PARTIAL`（E007、E023、E046）；lifecycle `PARTIAL`（E002、E004、E007）；persistence `PARTIAL`（E007、E010、E018、E023）；causal_feedback `NOT_APPLICABLE`（E007）；data_readiness `VERIFIED`（E007、E012）；verification `VERIFIED`（E011–E013、E049）；observability `PARTIAL`（E004、E016）；maintainability `PARTIAL`（E023、E046、E047）。
- 结论：时间/经济往返真实，但不是完整或耐久的产品会话快照。

## M. 数据、内容与历史基线

- 成熟度：`INTEGRATED_VERIFIED`。
- 正式入口：经济 `configure` 与地图 data loaders。
- 生产文件/关键符号：Alpha historical data、formal economy、historical evidence UI；`configure`、`_read_document`、`_validate_historical_evidence`。
- 权威状态：版本化源文档加载到地图/UI 与经济各自 cache/index；源数据运行期不可变。
- 写入者/读取者：离线 generator 写源；runtime loaders 复制；正式经济和地图读。
- 生命周期：场景/经济初始化时加载验证；session 中不可变。
- 持久化：源数据随包发布；派生经济另存。
- 玩家表面：来源提示、政治/行政层、旗帜、置信与接纳状态。
- 数据：`data/alpha/*1900*.json`、`data/world_map/*.json`、historical 子树；无前置系统；被 C、F、G、K、O 依赖。
- 测试/CI：Alpha historical data 与正式集成；commodity economy 和 Windows release workflow。
- 文档：地图渲染、1900 数据方法与状态文档。
- 12 维：implementation `VERIFIED`（E008、E041）；runtime_reachability `VERIFIED`（E008、E017）；integration `VERIFIED`（E008、E044）；player_surface `PARTIAL`（E004、E043）；state_ownership `PARTIAL`（E008、E017、E046）；lifecycle `VERIFIED`（E008、E017、E041）；persistence `NOT_APPLICABLE`（E007）；causal_feedback `PARTIAL`（E009、E044）；data_readiness `PARTIAL`（E028、E029、E041、E043、E052）；verification `VERIFIED`（E011、E013、E014）；observability `PARTIAL`（E016、E041）；maintainability `PARTIAL`（E030、E040、E043）。
- 结论：数据真实装载且有校验；历史时点、现代参考、估算和许可仍是发布契约缺口。

## N. 性能、稳定性与可观测性

- 成熟度：`INTEGRATED_VERIFIED`。
- 正式入口：CI validation entries 与正式 timer/economy loop。
- 生产文件/关键符号：formal economy、workspace runtime；`HISTORY_LIMIT`、`MAX_SHIPMENTS_PER_DAY`、`_draw_data_errors`。
- 权威状态：有界经济 queue/history 和临时 UI error strings；无正式诊断 owner。
- 写入者/读取者：经济与 loader 写；CI logs、错误面板、测试读。
- 生命周期：运行时边界持续生效；验证在 headless CI/隔离检出执行。
- 持久化：性能日志非产品状态；经济历史有界并保存。
- 玩家表面：只有数据错误和摘要，无故障诊断面板。
- 数据：无；依赖 B、F、K；被 O 依赖。
- 测试/CI：正式集成和十年平衡；release UI 与 Windows release workflow。
- 文档：`docs/PERFORMANCE_BUDGET.md`、`docs/performance/formal_time_d01_validation.md`。
- 12 维：implementation `PARTIAL`（E009、E013、E016）；runtime_reachability `PARTIAL`（E016）；integration `PARTIAL`（E013、E014）；player_surface `PARTIAL`（E016）；state_ownership `PARTIAL`（E016、E046）；lifecycle `PARTIAL`（E013、E014）；persistence `NOT_APPLICABLE`（E013）；causal_feedback `NOT_APPLICABLE`（E013）；data_readiness `VERIFIED`（E013、E041）；verification `VERIFIED`（E013–E015、E034）；observability `PARTIAL`（E013、E016）；maintainability `PARTIAL`（E034、E040）。
- 结论：聚合经济长跑门禁真实，完整产品的长跑、内存、泄漏和因果诊断缺失。

## O. 构建、发布与产品交付

- 成熟度：`INTEGRATED_VERIFIED`。
- 正式入口：Windows Desktop export preset 与 `project.godot` 正式 main scene。
- 生产文件/关键符号：`.github/workflows/windows-prototype-release.yml`、`export_presets.cfg`、`project.godot`；`application/run/main_scene`、`preset.0`、`validate-and-export`。
- 权威状态：CI 写 build identity；无账户、网络或遥测状态。
- 写入者/读取者：CI stamper/exporter 写构建产物；Godot exporter 和 Inno Setup workflow 读。
- 生命周期：checkout、stamp、import、tests、startup、export、installer、artifact/release。
- 持久化：构建状态不适用；产品存档质量仍是 release 依赖。
- 玩家表面：正式标题/主场景与截图；没有安装后端到端旅程。
- 数据：embedded PCK 内的 `res://`；依赖 A、K、L、M、N。
- 测试/CI：正式集成、十年平衡、UI capture；两个 release workflow。
- 文档：`docs/P0_R1_VALIDATION.md`、`docs/TEST_PLAN.md`。
- 12 维：implementation `VERIFIED`（E014、E037）；runtime_reachability `VERIFIED`（E001、E014）；integration `VERIFIED`（E014、E015）；player_surface `PARTIAL`（E015、E038、E048）；state_ownership `PARTIAL`（E014）；lifecycle `PARTIAL`（E014）；persistence `NOT_APPLICABLE`（E007、E018）；causal_feedback `NOT_APPLICABLE`（E014）；data_readiness `PARTIAL`（E028、E029、E041）；verification `PARTIAL`（E014、E015、E048）；observability `PARTIAL`（E014、E016）；maintainability `PARTIAL`（E034、E040）。
- 结论：构建/导出链已接通，不能据此宣称正式玩家产品发布就绪。

## 汇总

| 成熟度 | 数量 |
|---|---:|
| `ABSENT` | 0 |
| `SCAFFOLD_ONLY` | 0 |
| `IMPLEMENTED_ISOLATED` | 6 |
| `INTEGRATED_UNVERIFIED` | 0 |
| `INTEGRATED_VERIFIED` | 4 |
| `PLAYER_LOOP_PARTIAL` | 5 |
| `PLAYER_LOOP_COMPLETE` | 0 |

“无 `ABSENT`”不表示完整：A–O 每个领域在仓库里都有某种代码、数据或表面，但六个领域只存在孤立实现，五个领域只有局部玩家表面。正式产品判断必须以组合根和连续因果链为准。
