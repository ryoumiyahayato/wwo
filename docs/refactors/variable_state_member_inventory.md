# 变量状态成员清单

## 审计基线

- 基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。
- 引擎：Godot 4.6.3。
- 范围：`project.godot`、`scripts/`、`scenes/`、`data/`、`resources/`。
- 本文件只提供静态成员索引证据，不持有审计结论、实施方案、多写入状态总结、UI副本总结或停止项。

## 静态扫描限制

- 函数局部变量不进入表；每项只记录文件、所有者、声明行、A–K静态分类和字段名。
- 分类、写入者、读取者和持久化关联均为静态候选，不能代替qualified核验。
- 同名字段不得据此自动合并或删除。

## 基线指标

|成员|可写|全局|Autoload|持久化|兼容|UI|缓存|派生|K类|源文件|GDScript|
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|1613|1243|16|0|472|5|32|16|61|885|502|255|

## A–K分类说明

- **A**：唯一事实源候选。
- **B**：外部配置。
- **C**：不可变常量。
- **D**：节点或资源引用。
- **E**：可推导派生值候选。
- **F**：缓存候选，需核对失效规则。
- **G**：UI显示副本候选。
- **H**：兼容字段候选。
- **I**：临时迁移字段候选。
- **J**：无用字段候选。
- **K**：语义不明确，暂时不得修改。

## 1,613个生产成员字段逐项表

每个代码块中的文件标题后依次列出：`声明行 分类 字段`。

### 第1段：`scripts/action/action_instance_data.gd` 至 `scripts/alpha/alpha_economy_integration_service.gd`

<!-- INVENTORY_PART_01 -->

### 第2段：`scripts/alpha/alpha_economy_service.gd` 至 `scripts/alpha/alpha_simulation_service.gd`

<!-- INVENTORY_PART_02 -->

### 第3段：`scripts/alpha/alpha_ui_binding.gd` 至 `scripts/core/log_service.gd`

<!-- INVENTORY_PART_03 -->

### 第4段：`scripts/core/models/action_definition_data.gd` 至 `scripts/formal/formal_world_simulation.gd`

<!-- INVENTORY_PART_04 -->

### 第5段：`scripts/map/map_control_service.gd` 至 `scripts/simulation/society_simulation_service.gd`

<!-- INVENTORY_PART_05 -->

### 第6段：`scripts/simulation/world_activity_service.gd` 至 `scripts/ui_spikes/holographic_workspace/holographic_workspace_release_probe.gd`

<!-- INVENTORY_PART_06 -->

### 第7段：`scripts/ui_spikes/holographic_workspace/holographic_workspace_release_quality.gd` 至 `scripts/v2_2/v2_life_loop_simulation.gd`

<!-- INVENTORY_PART_07 -->

### 第8段：`scripts/v2_2/v2_life_loop_ui_binding.gd` 至 `scripts/v2_3/v2_3_formal_schedule_interface.gd`

<!-- INVENTORY_PART_08 -->

### 第9段：`scripts/v2_3/v2_3_formal_simulation.gd` 至 `scripts/v2_3/v2_3_survival_autonomy_service.gd`

```text
@ scripts/v2_3/v2_3_formal_simulation.gd | V23FormalSimulation
5 A finance_config
6 A finance
7 A leave
@ scripts/v2_3/v2_3_formal_ui_binding.gd | V23FormalUiBinding
5 K formal_simulation
@ scripts/v2_3/v2_3_leave_service.gd | V23LeaveService
5 K authorizations
6 A _next_sequence
@ scripts/v2_3/v2_3_life_loop_interface.gd | V23LifeLoopInterface
5 C V2_3_MENU_SCENE
6 C V2_3_PANEL_IDS
@ scripts/v2_3/v2_3_life_loop_simulation.gd | V23LifeLoopSimulation
5 C V2_3_SCHEMA_VERSION
6 C JULES_ID
7 C LUCIEN_ID
8 C FORMAL_PERSON_IDS
9 C TRAVEL_TYPES
13 C LOCATION_ALIASES
22 A v2_3_config
23 A spatial_locations
24 A travel_graph
25 A route_planner
26 A travel_execution
27 A communication
28 A knowledge
29 A dynamic_relationships
30 A appointments
31 A introductions
32 A npc_routines
34 K truth_view
35 A review_mode
36 K background_person_ids
37 K v2_3_initialization_error
38 K v2_3_hours_processed
39 E last_delivery_count
40 E last_knowledge_expiration_count
41 E last_appointment_result_count
42 K local_overlay_revision
43 K public_notice_id
44 A _commute_planned_through_day
@ scripts/v2_3/v2_3_life_loop_ui_binding.gd | V23LifeLoopUiBinding
5 K v2_3_simulation
6 A v2_3_save_service
7 I save_migration
8 K route_preview
9 A _view_revision
@ scripts/v2_3/v2_3_minimal_hud_overlay.gd | V23MinimalHudOverlay
4 C PAPER
5 C PAPER_DARK
6 C INK
7 C INK_MUTED
8 C GOLD
9 C PANEL
10 C PANEL_BORDER
12 K host
13 K field_book_open
14 K field_book_progress
15 K _refresh_timer
@ scripts/v2_3/v2_3_minute_clock.gd | V23MinuteClock
9 C REAL_SECONDS_PER_TICK
10 C MINUTES_PER_SPEED
17 C TICK_EPSILON
19 K minute
20 K total_minutes
21 K _tick_seconds_remainder
@ scripts/v2_3/v2_3_minute_controlled_simulation.gd | V23MinuteControlledSimulation
5 C MINUTE_CLOCK_PATH
@ scripts/v2_3/v2_3_minute_formal_interface_v2.gd | V23MinuteFormalInterfaceV2
6 K _selected_contact_id
@ scripts/v2_3/v2_3_product_simulation.gd | V23ProductSimulation
5 A social_sandbox
6 K last_social_sandbox_hour
@ scripts/v2_3/v2_3_product_simulation_v2.gd | V23ProductSimulationV2
6 A survival_autonomy
@ scripts/v2_3/v2_3_save_service.gd | V23SaveService
5 C SCHEMA_VERSION
6 C REVIEW_PATH
@ scripts/v2_3/v2_3_social_sandbox_service.gd | V23SocialSandboxService
10 C STATE_VERSION
11 C PHASE_PREPARE
12 C PHASE_CONFLICT
13 C PHASE_COMMIT
14 C SIGNAL_KINDS
17 C NEGATIVE_EFFECTS
22 K situations
23 K goals
24 K intents
25 K tasks
26 K event_ledger
27 K commitments
28 K evidence_records
29 K pending_reactions
30 K decision_explanations
31 K last_planned_dates
32 K player_person_id
34 K _rules
35 K _people
36 K _methods
37 K _dirty_people
38 A _next_signal_sequence
39 A _next_goal_sequence
40 A _next_intent_sequence
41 A _next_task_sequence
42 A _next_event_sequence
43 A _next_commitment_sequence
44 A _next_evidence_sequence
45 A _last_processed_hour
47 K _schedule
48 K _locations
49 K _relationships
50 K _knowledge
51 K _organizations
52 K _households
53 K _ledger
54 K _employment
57 K fail_next_commit_for_test
@ scripts/v2_3/v2_3_social_sandbox_service_v2.gd | V23SocialSandboxServiceV2
10 K _product
11 K _submit_options
12 K _last_reservation_metadata
@ scripts/v2_3/v2_3_social_sandbox_service_v3.gd | V23SocialSandboxServiceV3
7 K _authorize_player_travel_for_submit
@ scripts/v2_3/v2_3_survival_autonomy_service.gd | V23SurvivalAutonomyService
6 C MARKET_LOCATION_ID
7 C ITEM_TYPES
8 C MAX_DECISIONS
10 K product
11 K profiles
12 K next_retry_hours
13 K active_needs
14 K decision_history
```

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

