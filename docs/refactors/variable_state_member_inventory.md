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

```text
@ scripts/v2_2/v2_life_loop_ui_binding.gd | V2LifeLoopUiBinding
7 K simulation
8 A save_service
9 K developer_mode
10 A last_command_result
11 K _panel_pause_depth
12 A _panel_previous_paused
13 A _panel_previous_speed
@ scripts/v2_2/v2_notification_service.gd | V2NotificationService
5 K notifications
6 A _next_sequence
7 A _maximum_entries
@ scripts/v2_2/v2_organization_activity_service.gd | V2OrganizationActivityService
5 K memberships
6 K organizations
7 K positions
8 K processed_idempotency_keys
9 K _rules
10 K _processed_key_order
12 C MAX_PROCESSED_KEYS
@ scripts/v2_2/v2_relationship_progress_service.gd | V2RelationshipProgressService
5 K relationships
6 K processed_idempotency_keys
7 K _rules
8 K _processed_key_order
10 C MAX_PROCESSED_KEYS
@ scripts/v2_2/v2_schedule_service.gd | V2ScheduleService
5 C SOURCE_PRIORITY
12 C PLAYER_TYPES
21 C TERMINAL_STATUSES
24 C ACTIVE_STATUSES
26 K schedules
27 K recent_completed_activities
28 K generation_reasons
29 K _people
30 K _employment
31 K _generated_days
32 A _next_sequence
33 A _minimum_horizon
34 A _refill_threshold
35 A _completed_limit
@ scripts/v2_3/communication_service.gd | CommunicationService
5 C MESSAGE_STATUSES
10 K messages
11 K inbox_index
12 K outbox_index
13 K delivery_queue
14 K public_notice_ids
15 K processed_idempotency_keys
16 K _processed_key_order
17 K _people
18 K _channels
19 A _next_sequence
20 A _message_limit
21 A _key_limit
@ scripts/v2_3/knowledge_service.gd | KnowledgeService
5 C STATUSES
9 K records
10 K person_index
11 K subject_index
12 K processed_idempotency_keys
13 K _processed_key_order
14 K _rules
15 A _next_sequence
16 A _history_limit
@ scripts/v2_3/relationship_service.gd | V23RelationshipService
5 C DIMENSIONS
9 K relationships
10 K person_pair_index
11 K processed_idempotency_keys
12 K _processed_key_order
13 K _rules
14 K _people
15 A _history_limit
16 A _key_limit
@ scripts/v2_3/route_planner_service.gd | RoutePlannerService
5 K graph
6 K locations
7 F _cache
8 F cache_hits
9 F cache_misses
@ scripts/v2_3/social_appointment_service.gd | SocialAppointmentService
5 C STATUSES
10 K appointments
11 K processed_idempotency_keys
12 K _processed_key_order
13 A _next_sequence
14 A _history_limit
15 A _key_limit
@ scripts/v2_3/social_introduction_service.gd | SocialIntroductionService
5 C STATUSES
10 K requests
11 K processed_idempotency_keys
12 A _next_sequence
@ scripts/v2_3/spatial_location_service.gd | SpatialLocationService
5 C LOCATION_STATES
9 K locations
10 K person_positions
11 K known_location_ids
12 K _type_index
13 K _service_index
@ scripts/v2_3/spatial_npc_routine_service.gd | SpatialNpcRoutineService
5 C REPLAN_REASONS
10 K npc_plans
11 K planning_events
12 E planning_call_count
13 A _planning_interval
14 A _history_limit
@ scripts/v2_3/travel_execution_service.gd | TravelExecutionService
5 C TRAVEL_ACTIVITY_TYPES
8 C PLAN_STATUSES
13 K travel_plans
14 K processed_idempotency_keys
15 K _processed_key_order
16 A _next_sequence
17 A _history_limit
18 A _idempotency_limit
19 K _nonterminal_plan_index
20 K _terminal_plan_order
21 K locations
22 K graph
23 K planner
@ scripts/v2_3/travel_graph_service.gd | TravelGraphService
5 K edges
6 K modes
7 K adjacency
8 K mode_edge_index
9 K known_edge_ids
@ scripts/v2_3/v2_3_config.gd | V23Config
5 C PATHS
20 K documents
21 K errors
@ scripts/v2_3/v2_3_controlled_simulation.gd | V23ControlledSimulation
6 K manual_location_holds
7 K manual_location_hold_started_hours
8 K pending_return_home_prompts
9 K stay_outside_home_until_hours
10 K _return_home_policy_resume_after_decisions
@ scripts/v2_3/v2_3_controlled_ui_binding.gd | V23ControlledUiBinding
5 K controlled_simulation
@ scripts/v2_3/v2_3_controlled_ui_binding_v2.gd | V23ControlledUiBindingV2
6 K _sandbox_selection_by_person
7 K _selected_message_by_person
@ scripts/v2_3/v2_3_finance_config.gd | V23FinanceConfig
5 C PATH
7 K document
8 K errors
@ scripts/v2_3/v2_3_finance_service.gd | V23FinanceService
5 C HOURS_PER_DAY
6 C DAYS_PER_YEAR
7 C MAX_HISTORY
9 K lenders
10 K products
11 K applications
12 K contracts
13 K event_history
15 K _households
16 K _ledger
17 K _processed_keys
18 K _processed_key_order
19 A _next_application_sequence
20 A _next_contract_sequence
@ scripts/v2_3/v2_3_formal_interface.gd | V23FormalInterface
5 C FINANCE_PANEL_ID
6 C FORMAL_PANEL_IDS
@ scripts/v2_3/v2_3_formal_schedule_interface.gd | V23FormalScheduleInterface
5 K leave_confirmation
```

### 第9段：`scripts/v2_3/v2_3_formal_simulation.gd` 至 `scripts/v2_3/v2_3_survival_autonomy_service.gd`

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

