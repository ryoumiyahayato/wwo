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

```text
@ scripts/core/models/action_definition_data.gd | ActionDefinitionData
4 K id
5 K name
6 K category
7 K total_work
8 K base_progress_per_hour
9 K primary_skill
10 K secondary_skills
11 K aptitude_modifier_weight
12 K position_permission_required
13 K organization_support_weight
14 K relationship_support_weight
15 K funding_weight
16 K preparation_weight
17 K state_modifier_weight
18 K base_target_resistance
19 K interruption_conditions
20 K success_threshold
21 K guaranteed_success_threshold
22 K success_result
23 K failure_result
@ scripts/core/models/character_data.gd | CharacterData
4 K id
5 K name
6 K age
7 E country_id
8 K region_id
9 K occupation_id
10 K occupation
11 K public_position
12 K organization_ids
13 K relationship_ids
14 K hidden_aptitudes
15 K temperament_weights
16 K skills
17 K manifested_traits
18 K tendencies
19 K known_tendencies
20 K current_status
21 K background_history
22 K domain_experience
23 K qualifications
24 K drives
25 K issue_positions
26 K current_agendas
27 K bottom_lines
28 K is_active
29 K random_mode
30 K random_category
31 K is_challenge_start
32 K generation_seed
33 K random_state
@ scripts/core/models/control_unit_data.gd | ControlUnitData
4 K id
5 K region_id
6 K grid_x
7 K grid_y
8 K city_name
9 K neighbor_ids
10 E de_jure_country_id
11 E controller_country_id
12 K control_strength
13 K contested_level
14 K garrison_pressure
15 K enemy_pressure
16 K social_support
17 K railroad_neighbor_ids
18 K infrastructure_state
@ scripts/core/models/country_data.gd | CountryData
4 K id
5 K name
6 K region_ids
7 K public_status
@ scripts/core/models/organization_data.gd | OrganizationData
4 K id
5 K name
6 K type
7 E country_id
8 K region_id
9 K size
10 K resources
11 K influence
12 K public_stance
13 K leader_character_id
14 K member_ids
15 K position_structure
16 K organization_relations
@ scripts/core/models/population_group_data.gd | PopulationGroupData
4 K id
5 K region_id
6 E population_count
7 K social_class
8 K occupation_category
9 K average_income
10 K average_education
11 K unemployment_rate
12 K public_political_leaning
13 K basic_living_state
@ scripts/core/models/region_data.gd | RegionData
4 K id
5 K name
6 E de_jure_country_id
7 K population_group_ids
8 K city_names
9 K resources
10 K infrastructure
11 K organization_ids
12 K social_influence
@ scripts/core/models/relationship_data.gd | RelationshipData
4 K id
5 K character_a_id
6 K character_b_id
7 K familiarity
8 K trust
9 K affinity
10 K interest_link
11 K is_public
12 K last_interaction_hour
@ scripts/core/random_service_config.gd | RandomServiceConfig
5 C DEFAULT_PATH
7 A default_seed
8 K error_message
@ scripts/core/stable_id_service.gd | StableIdService
5 C GENERATED_WIDTH
7 E _counters
@ scripts/devtools/developer_command_service.gd | DeveloperCommandService
5 K clock
6 K map_service
7 A save_service
@ scripts/devtools/performance_stats_service.gd | PerformanceStatsService
4 K metrics
@ scripts/devtools/settlement_log_service.gd | SettlementLogService
5 C DEFAULT_MAX_ENTRIES
7 A max_entries
8 K entries
@ scripts/formal/formal_world_application.gd | FormalWorldApplication
7 C LAUNCH_MODE_META
9 A formal_simulation
10 G economy_panel_open
11 K _formal_status
12 E _last_summary
@ scripts/formal/formal_world_economy_service.gd | FormalWorldEconomyService
8 C HOURS_PER_DAY
9 C BASIS_POINTS
10 C HISTORY_LIMIT
11 C MAX_SHIPMENTS_PER_DAY
12 C MAX_SUPPLIERS_PER_SHORTAGE
13 C EXPECTED_MAJOR_ROSTER_COUNT
14 C PRIMARY_PLAYABLE_LIMIT
15 C COMMODITY_CATALOG_PATH
16 C POLITICAL_UNITS_PATH
17 C CROSSWALK_PATH
19 E country_states
20 K polity_records
21 K economy_polity_ids
22 K economy_by_polity_id
23 K routes
24 K shipments
25 K history
26 K total_hour
27 K initialization_error
29 A _historical
30 K _commodities
31 E _routes_by_country
32 K _crosswalk_records
33 A _next_shipment_sequence
34 A _last_day_index
35 E _political_unit_count
@ scripts/formal/formal_world_menu.gd | FormalWorldMenu
6 C WORLD_SCENE
7 C LAUNCH_MODE_META
8 C DISPLAY_VERSION
10 D title_label
11 D version_label
12 D prompt_label
13 D status_label
15 K _entering
@ scripts/formal/formal_world_simulation.gd | FormalWorldSimulation
8 C SAVE_PATH
9 C SCHEMA_ID
11 A economy
12 K initialized
13 K initialization_error
14 K total_minutes
15 K _minute_remainder
```

### 第5段：`scripts/map/map_control_service.gd` 至 `scripts/simulation/society_simulation_service.gd`

```text
@ scripts/map/map_control_service.gd | MapControlService
11 C STAGE_STABLE
12 C STAGE_WEAKENING
13 C STAGE_CONTESTED
14 C STAGE_ENEMY_OCCUPATION
15 C STAGE_CONSOLIDATING
16 C WAR_STATUS_PEACE
17 C WAR_STATUS_ACTIVE
19 K data_set
20 K rules
21 K _frontline_edges
22 K _units_by_grid_position
23 K _war_state
@ scripts/map/map_rules_config.gd | MapRulesConfig
5 C DEFAULT_PATH
7 A tile_width
8 A tile_height
9 A min_zoom
10 A max_zoom
11 A zoom_step
12 G pan_visible_margin
13 A weak_control_threshold
14 A contested_threshold
15 A capture_strength_threshold
16 A capture_contested_threshold
17 A consolidation_strength
18 A pressure_strength_loss
19 A pressure_contested_gain
20 A pressure_enemy_gain
21 A rail_attack_bonus
22 A rail_defense_bonus
23 A rail_consolidation_bonus
24 A social_support_scale
25 A unit_social_support_scale
26 A surrounded_attack_bonus
27 A multi_front_bonus
28 A minimum_pressure_multiplier
29 A maximum_pressure_multiplier
30 K error_message
@ scripts/map/map_world_controller.gd | MapWorldController
7 B world_data_path
8 B map_rules_path
10 K data_set
11 K rules
12 K control_service
13 K initialization_error
@ scripts/map/regional_influence_service.gd | RegionalInfluenceService
7 K rules
@ scripts/map/strategic_map_canvas.gd | StrategicMapCanvas
7 C MAP_BACKGROUND
8 C GRID_COLOR
9 C REGION_BORDER_COLOR
10 C RAIL_DARK_COLOR
11 C RAIL_LIGHT_COLOR
12 C CONTROL_BORDER_DARK_COLOR
13 C CONTROL_BORDER_COLOR
14 C CONTESTED_COLOR
15 C SELECTION_COLOR
16 C CITY_COLOR
17 C DRAG_THRESHOLD
19 K control_service
20 K rules
21 K selected_unit_id
23 A _zoom
24 A _pan_offset
25 K _left_button_down
26 K _dragging
27 A _press_position
28 E _country_colors
29 K _fallback_font
@ scripts/organization/organization_service.gd | OrganizationService
8 C LEGACY_BASE_ORGANIZATION_IDS
19 K organizations
20 K _positions_by_character
@ scripts/relationship/relationship_service.gd | RelationshipService
7 K roster
8 K defaults
9 K id_service
10 K relationships
11 K _id_by_pair
@ scripts/save/action_save_validator.gd | ActionSaveValidator
4 C NUMERIC_CONTEXT_FIELDS
7 C VALID_OUTCOMES
8 C DOMAIN_CATEGORIES
@ scripts/save/autosave_coordinator.gd | AutosaveCoordinator
5 K clock
6 K map_service
7 A save_service
8 A autosave_path
@ scripts/save/game_save_service.gd | GameSaveService
4 C SAVE_VERSION
5 C MANUAL_PATH
6 C AUTOSAVE_PATH
7 C V2_2_SCHEMA_VERSION
8 C V2_2_REVIEW_PATH
9 C CONFIG_VERSIONS
16 C REQUIRED_CHARACTER_FIELDS
@ scripts/save/save_operation_result.gd | SaveOperationResult
4 K success
5 K error_code
6 K message
7 K path
8 K snapshot
@ scripts/simulation/continuity_rules_config.gd | ContinuityRulesConfig
4 C DEFAULT_PATH
6 K social_influence
7 K candidate
8 K exit_constraints
9 K enemy_affinity_threshold
10 K position_inheritance_minimum_score
11 K exit_reasons
12 K error_message
@ scripts/simulation/simulation_clock.gd | SimulationClock
15 C HOURS_PER_DAY
16 C HOURS_PER_WEEK
17 C ACCUMULATOR_EPSILON
19 K year
20 K month
21 K day
22 K hour
23 K total_hours
24 A is_paused
25 A speed_multiplier
27 K _config
28 K _real_seconds_accumulator
29 A _event_queue
@ scripts/simulation/simulation_clock_config.gd | SimulationClockConfig
5 C DEFAULT_PATH
7 A start_year
8 A start_month
9 A start_day
10 K start_hour
11 A real_seconds_per_game_hour
12 A allowed_speed_multipliers
13 K error_message
@ scripts/simulation/simulation_event_queue.gd | SimulationEventQueue
5 K _events
6 K _event_ids
7 K _next_sequence
@ scripts/simulation/simulation_runner.gd | SimulationRunner
8 B config_path
10 K clock
11 K initialization_error
@ scripts/simulation/society_rules_config.gd | SocietyRulesConfig
4 C DEFAULT_PATH
6 E background_character_count
7 K active_character_limit
8 E initial_active_npc_count
9 K background_seed_base
10 K relationship_defaults
11 K organization_economy
12 K lifecycle_rules
13 K ai_rules
14 K error_message
@ scripts/simulation/society_simulation_service.gd | SocietySimulationService
5 C DOMAIN_ACTION_CATEGORIES
13 C STARTER_LEADER_ORGANIZATION_IDS
24 K rules
25 K roster
26 K organizations
27 K relationships
28 K ai
29 K continuity_rules
30 K regional_influence
31 K succession
32 K world_activity
33 K initialization_error
34 K paused_settlement_categories
35 K _clock
36 K _map_service
37 K _data_set
38 K _character_config
39 K _action_rules
40 K _action_service
41 F _control_owner_cache
```

### 第6段：`scripts/simulation/world_activity_service.gd` 至 `scripts/ui_spikes/holographic_workspace/holographic_workspace_release_probe.gd`

<!-- INVENTORY_PART_06 -->

### 第7段：`scripts/ui_spikes/holographic_workspace/holographic_workspace_release_quality.gd` 至 `scripts/v2_2/v2_life_loop_simulation.gd`

<!-- INVENTORY_PART_07 -->

### 第8段：`scripts/v2_2/v2_life_loop_ui_binding.gd` 至 `scripts/v2_3/v2_3_formal_schedule_interface.gd`

<!-- INVENTORY_PART_08 -->

### 第9段：`scripts/v2_3/v2_3_formal_simulation.gd` 至 `scripts/v2_3/v2_3_survival_autonomy_service.gd`

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

