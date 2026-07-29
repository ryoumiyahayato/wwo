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

```text
@ scripts/action/action_instance_data.gd | ActionInstanceData
4 C STATUS_ACTIVE
5 C STATUS_PAUSED
6 C STATUS_COMPLETED
7 C STATUS_CANCELLED
8 C STATUS_INTERRUPTED
10 K id
11 K definition_id
12 K actor_character_id
13 K target_id
14 A status
15 K start_hour
16 K last_update_hour
17 A completion_hour
18 K accumulated_work
19 K total_work
20 K current_efficiency
21 K estimated_completion_hour
22 K context
23 K effective_value
24 K outlook
25 K outcome_code
26 K result_description
27 K applied_effects
28 K result_applied
29 K domain_effect_applied
30 K interruption_reason
@ scripts/action/action_rules_config.gd | ActionRulesConfig
5 C DEFAULT_PATH
7 K primary_skill_weight
8 K secondary_skill_weight
9 K position_permission_bonus
10 K progress_base_multiplier
11 K progress_effective_scale
12 K minimum_progress_multiplier
13 K maximum_progress_multiplier
14 K mastery_guarantee
15 K practice_growth
16 K state_rules
17 K player_context_rules
18 K outlook_bands
19 K guaranteed_label
20 K aptitude_by_skill
21 K error_message
@ scripts/action/action_service.gd | ActionService
8 K rules
9 K id_service
@ scripts/action/action_start_result.gd | ActionStartResult
4 K action
5 K errors
@ scripts/action/player_action_context_service.gd | PlayerActionContextService
5 C TARGET_DOMAIN_NONE
6 C TARGET_DOMAIN_CHARACTER
7 C TARGET_DOMAIN_ORGANIZATION
8 C TARGET_DOMAIN_MAP
10 K rules
11 K society
12 K map_service
@ scripts/ai/ai_state_data.gd | AiStateData
4 K character_id
5 K current_goal
6 K goal_priority
7 K current_action_id
8 K current_action_record
9 K last_action_result
10 K candidate_actions
11 K next_daily_decision_hour
12 K next_long_term_hour
13 E daily_decision_count
14 E long_term_evaluation_count
@ scripts/ai/simple_ai_service.gd | SimpleAiService
5 K roster
6 K rules
7 K states
@ scripts/alpha/alpha_ai_service.gd | AlphaAiService
5 C MAX_CANDIDATES
6 C HISTORY_LIMIT
8 K decisions
9 K last_candidates
10 K _labor
11 K _economy
12 K _enterprise
13 K _politics
14 K _organizations
15 K _characters
16 K _commodity_market
17 K _economy_integration
18 K _historical_world
19 K _processed_days
@ scripts/alpha/alpha_asset_service.gd | AlphaAssetService
5 C ASSET_TYPES
18 K assets
19 A _next_sequence
20 K _processed_keys
21 K _ledger
@ scripts/alpha/alpha_character_service.gd | AlphaCharacterService
5 C CREATION_MODES
11 C DEVELOPMENT_METHODS
20 C CATEGORY_MAP
30 K development_plans
31 K authorizations
32 K assessments
33 K _data_set
34 K _generation_config
35 K _alpha_config
36 K _economy
37 K _labor
38 K _processed_keys
39 A _next_plan_sequence
40 A _next_authorization_sequence
@ scripts/alpha/alpha_commodity_market_service.gd | AlphaCommodityMarketService
6 C BASIS_POINTS
7 C POPULATION_UNIT
8 C HISTORY_LIMIT
9 C IMPORTABLE_CLASSES
12 C EXPORTABLE_CLASSES
16 K commodities
17 K recipes
18 K production_sites
19 K region_states
20 K international_market
21 K active_shocks
22 K history
23 K initialization_error
24 K _commodity_ids
25 K _region_ids
26 K _production_site_ids
27 K _industrial_input_capacity
28 K _output_capacity
29 K _processed_keys
30 A _last_day_index
31 K _policies
32 K _external_logistics_managed
@ scripts/alpha/alpha_config.gd | AlphaConfig
5 C PATHS
13 C LOCATION_ROLE_OFFSETS
24 K documents
25 K errors
26 K locations
27 K transport_edges
28 K people
@ scripts/alpha/alpha_contract_service.gd | AlphaContractService
5 C CONTRACT_TYPES
14 C ACTIVE_STATUSES
23 C TERMINAL_STATUSES
32 K templates
33 K contracts
34 K _ledger
35 K _assets
36 K _processed_keys
37 A _next_sequence
@ scripts/alpha/alpha_economy_integration_service.gd | AlphaEconomyIntegrationService
6 C BASIS_POINTS
7 C HOURS_PER_DAY
8 C ESCROW_ID
9 C INSURER_ID
10 C CAPITAL_SUPPLIER_ID
11 C HISTORY_LIMIT_FALLBACK
13 K shipments
14 K shipment_history
15 K decision_history
16 K government_stockpiles
17 E country_finance
18 E region_accounts
19 K site_enterprise
20 E daily_summary
21 K initialization_error
23 K _commodity_market
24 K _economy
25 K _enterprise
26 K _labor
27 K _config
28 K _document
29 K _policies
30 K _adjacency
31 K _edges_by_id
32 K _nearest_by_origin
33 K _producer_by_region_commodity
34 K _industrial_need_capacity
35 K _household_strata
36 K _trade_relations
37 K _procurement_rules
38 K _edge_remaining_capacity
39 K _trade_quota_remaining
40 K _processed_days
41 A _next_shipment_sequence
42 K _liquidity_sequence_by_day_region
```

### 第2段：`scripts/alpha/alpha_economy_service.gd` 至 `scripts/alpha/alpha_simulation_service.gd`

```text
@ scripts/alpha/alpha_economy_service.gd | AlphaEconomyService
5 C HOURS_PER_DAY
6 C DAYS_PER_YEAR
7 C TRADE_ESCROW_ID
8 C CREDIT_LENDER_IDS
14 A ledger
15 A assets
16 A contracts
17 K credit_products
18 K goods
19 K markets
20 K applications
21 K loan_claim_assets
22 K entity_profiles
23 K external_events
24 K _processed_keys
25 A _next_application_sequence
@ scripts/alpha/alpha_enterprise_service.gd | AlphaEnterpriseService
5 C AGGREGATE_MARKET_ID
6 C ACTIVE_ENTERPRISE_STATUSES
12 K enterprises
13 K _economy
14 K _labor
15 K _organizations
16 E _region_country
17 K _processed_keys
18 A _next_enterprise_sequence
@ scripts/alpha/alpha_fixture_gate.gd | AlphaFixtureGate
5 C FORMAL_MENU_SCENE
6 C FIXTURE_SCENE
7 C FIXTURE_FLAG
8 C ALLOW_META
@ scripts/alpha/alpha_grid_fixture.gd | AlphaGridFixture
5 C FORMAL_MENU_SCENE
@ scripts/alpha/alpha_historical_world_economy_data.gd | AlphaHistoricalWorldEconomyData
6 C WORLD_MANIFEST_PATH
7 C HOUSEHOLD_BUDGET_PATH
8 C TRANSPORT_MANIFEST_PATH
9 C COVERAGE_REGISTRY_PATH
11 K world_manifest
12 K household_budgets
13 K transport_manifest
14 K coverage_registry
15 E countries
16 K domestic_networks
17 K maritime_corridors
18 K river_corridors
19 E country_by_entity
20 K budget_by_id
21 K coverage_by_entity
22 K initialization_error
@ scripts/alpha/alpha_labor_service.gd | AlphaLaborService
5 C ACTIVE_EMPLOYMENT_STATUSES
12 K jobs
13 K applications
14 K employment_states
15 K person_profiles
16 K unemployment
17 I migrations
18 K _economy
19 K _processed_keys
20 A _next_application_sequence
@ scripts/alpha/alpha_ledger_service.gd | AlphaLedgerService
5 C SYSTEM_OPENING_ACCOUNT
6 C DEFAULT_HISTORY_LIMIT
7 C DEFAULT_PROCESSED_KEY_MULTIPLIER
9 E accounts
10 K transactions
11 K opening_balances
12 K _transactions_by_key
13 K _processed_key_order
14 A _next_sequence
15 A _history_limit
16 A _processed_key_multiplier
@ scripts/alpha/alpha_main.gd | AlphaMain
5 C MENU_SCENE
6 C LAUNCH_MODE_META
7 C PRESET_META
8 C REVIEW_STATE_META
9 C DEVELOPER_META
11 C KIND_LABELS
22 C INTENTS
31 K simulation
32 K binding
33 K map_canvas
34 K header_label
35 K cash_label
36 K status_label
37 K object_kind
38 K object_search
39 K object_list
40 K detail_title
41 K detail_text
42 K actions_box
43 K event_list
44 K intent_option
45 K map_mode_option
46 K pause_button
47 K dev_panel
48 K dev_input
49 A _selected_kind
50 K _selected_object_id
51 A _view_dirty
52 K _clock_timer
53 K _refresh_timer
@ scripts/alpha/alpha_map_canvas.gd | AlphaMapCanvas
7 C MODES
19 C MODE_LABELS
32 K simulation
33 A map_mode
34 K selected_object_id
35 A selected_good_id
36 A _map_rect
37 A _cell_size
@ scripts/alpha/alpha_menu.gd | AlphaMenu
6 C FORMAL_MENU_SCENE
7 C FIXTURE_SCENE
8 C FIXTURE_FLAG
10 K preset_option
11 K load_button
12 K migrate_button
13 K developer_check
14 K status_label
15 A _config
17 C REVIEW_LABELS
@ scripts/alpha/alpha_politics_service.gd | AlphaPoliticsService
5 C PUBLIC_SPENDING_ID
6 C POSITION_PERMISSION_SET
21 C VALID_POSITION_LOSS_CAUSES
30 K organization_states
31 K position_packages
32 K appointments
33 K factions
34 K issues
35 K policies
36 K policy_implementations
37 K support_records
38 K political_exchanges
39 K corruption_cases
40 K investigations
41 K public_events
42 K obligations
43 K _organizations
44 K _economy
45 K _world
46 K _config
47 K _processed_keys
48 A _next_faction_sequence
49 A _next_policy_sequence
50 A _next_corruption_sequence
51 A _next_investigation_sequence
@ scripts/alpha/alpha_save_service.gd | AlphaSaveService
5 C SCHEMA_VERSION
6 C REVIEW_PATH
@ scripts/alpha/alpha_scenario_runner.gd | AlphaScenarioRunner
5 C SCENARIO_IDS
17 C FIXED_SEEDS
30 K last_simulation
@ scripts/alpha/alpha_simulation_service.gd | AlphaSimulationService
5 C ALPHA_SCHEMA_VERSION
6 C DEFAULT_PRESET_ID
7 C DEFAULT_REVIEW_STATE_ID
8 C CORE_WORLD_PATH
9 C HIGH_DETAIL_LIMIT
10 C REVIEW_STATE_PRESETS
24 A alpha_config
25 K core_data
26 A world
27 K organization_service
28 A economy
29 A commodity_market
30 A economy_integration
31 A historical_world_economy
32 A labor
33 A enterprise
34 A character_service
35 A politics
36 A alpha_ai
37 A world_dynamics
38 K roster
39 K generation_config
40 K society_rules
42 A launch_preset_id
43 A launch_review_state_id
44 K alpha_events
45 K current_intent
46 K detailed_enterprise_ids
47 K alpha_initialization_error
48 K alpha_last_hour_usec
49 K alpha_maximum_hour_usec
50 K alpha_hours_processed
51 H _last_legacy_cash
```

### 第3段：`scripts/alpha/alpha_ui_binding.gd` 至 `scripts/core/log_service.gd`

```text
@ scripts/alpha/alpha_ui_binding.gd | AlphaUiBinding
7 C OBJECT_KINDS
19 K simulation
20 A save_service
21 I migration
22 K developer_mode
23 K last_result
24 A _command_sequence
@ scripts/alpha/alpha_v23_config.gd | AlphaV23Config
5 A alpha
@ scripts/alpha/alpha_world_dynamics_service.gd | AlphaWorldDynamicsService
5 C EVENT_LIMIT
6 C BACKGROUND_MATTER_LIMIT
8 K background_states
9 K national_issues
10 K events
11 E counters
12 K _world
13 K _economy
14 K _enterprise
15 K _politics
16 K _roster
17 K _config
18 K _commodity_market
19 K _economy_integration
20 A _last_day_index
21 A _last_week_index
22 K _last_month_key
@ scripts/alpha/alpha_world_service.gd | AlphaWorldService
5 E countries
6 K regions
7 K cells
8 K cities
9 K locations
10 K routes
11 E topology_report
12 K initialization_error
13 K revision
@ scripts/character/background_character_data.gd | BackgroundCharacterData
5 K id
6 K name
7 K age
8 E country_id
9 K region_id
10 K occupation_id
11 K occupation
12 K public_position
13 K organization_ids
14 K relationship_ids
15 K manifested_traits
16 K current_status
17 K activation_seed
18 K persistent_core
@ scripts/character/character_generation_config.gd | CharacterGenerationConfig
5 C DEFAULT_PATH
7 K age_min
8 K age_max
9 K aptitude_min
10 K aptitude_max
11 K growth_modifier_min
12 K growth_modifier_max
13 K trait_rules
14 K aptitude_keys
15 K skill_keys
16 K trait_keys
17 K labels
18 K tendency_poles
19 E country_names
20 K occupations
21 K population_occupation_multipliers
22 K tendency_events
23 K error_message
@ scripts/character/character_generation_result.gd | CharacterGenerationResult
4 K character
5 K errors
@ scripts/character/character_generator.gd | CharacterGenerator
5 C MODE_STANDARD
6 C MODE_FULL_POPULATION
7 C MODE_CATEGORY
8 C VALID_MODES
10 K data_set
11 K config
12 K random
13 K id_service
@ scripts/character/character_roster_service.gd | CharacterRosterService
9 K data_set
10 K generation_config
11 K rules
12 K player_character_id
13 K background_characters
14 K active_characters
15 K exited_characters
16 K _activation_seeds
@ scripts/character/character_tendency_service.gd | CharacterTendencyService
5 K config
@ scripts/character/exited_character_record.gd | ExitedCharacterRecord
4 K character
5 K reason
6 K exit_hour
7 K successor_character_id
@ scripts/character/game_session_service.gd | GameSessionService
5 C SettlementLogServiceType
6 C PerformanceStatsServiceType
8 A player_character
9 E selected_country_id
10 A current_action
11 A recent_action_result
12 A action_history
13 A action_id_service
14 A society_service
15 A world_clock
16 A world_map_service
17 A world_autosave
18 A developer_mode
19 A settlement_log
20 A performance_stats
21 A pending_load_path
22 A pending_menu_message
@ scripts/character/succession_candidate_data.gd | SuccessionCandidateData
4 K character_id
5 K name
6 K role_label
7 K score
8 K relationship_id
9 K shared_organization_ids
@ scripts/character/succession_result.gd | SuccessionResult
4 K successor
5 K exited_record
6 K inherited_wealth
7 K inherited_reputation
8 K inherited_intelligence
9 E inherited_relationship_count
10 E inherited_enemy_count
11 E inherited_position_count
12 K errors
@ scripts/character/succession_service.gd | SuccessionService
5 K rules
6 K roster
7 K organizations
8 K relationships
9 K ai
10 K society_rules
@ scripts/core/build_info.gd | BuildInfo
5 C GAME_NAME
6 C BASE_VERSION
7 C BUILD_CODE
@ scripts/core/core_data_load_result.gd | CoreDataLoadResult
5 K data_set
6 K errors
@ scripts/core/core_data_loader.gd | CoreDataLoader
6 C SCHEMA_VERSION
7 C COLLECTIONS
17 C ID_NAMESPACES
@ scripts/core/core_data_set.gd | CoreDataSet
5 E countries
6 K regions
7 K control_units
8 K population_groups
9 K characters
10 K organizations
11 K relationships
12 K actions
@ scripts/core/deterministic_random_service.gd | DeterministicRandomService
5 A _rng
6 K _initial_seed
@ scripts/core/log_service.gd | LogService
13 A minimum_level
```

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

```text
@ scripts/simulation/world_activity_service.gd | WorldActivityService
7 C MAX_EVENTS
8 C IMPORTANCE_NORMAL
9 C IMPORTANCE_IMPORTANT
10 C VALID_IMPORTANCE
13 C VALID_SUBJECT_TYPES
17 K _events
18 A _next_event_id
@ scripts/ui_spikes/holographic_workspace/holographic_hemisphere_3d.gd | holographic_hemisphere_3d
3 C LAT_SEGMENTS
4 C LON_SEGMENTS
5 C RADIUS
6 C MOON_RADIUS
8 D _surface
9 D _moon
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1.gd | holographic_workspace_admin1
3 K selected_world_admin1_id
4 K hover_world_admin1_id
5 K _world_admin1_by_iso
6 K _world_admin1_by_id
7 G _world_admin1_screen_polygons
8 E _world_admin1_bounds
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1_probe.gd | holographic_workspace_admin1_probe
3 C TARGET_SCENE
5 K workspace
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_capture.gd | holographic_workspace_capture
3 C TARGET_SCENE
4 C OUTPUT_DIRECTORY
6 K workspace
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_flags_fixed.gd | holographic_workspace_crisp_flags_fixed
3 C FLAG_TEXTURE_WIDTH
4 C FLAG_TEXTURE_HEIGHT
5 C ADMIN1_GLOBAL_ZOOM_START
6 C ADMIN1_GLOBAL_LABEL_ZOOM
8 K _flag_texture_by_entity
9 K _historical_outline_polygons
10 F _world_admin1_unit_cache
11 E _world_admin1_country_count
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_final.gd | holographic_workspace_final
3 D _moon_node
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_flags.gd | holographic_workspace_flags
3 C WORLD_ZOOM_MIN
4 C WORLD_ZOOM_MAX
5 C WORLD_ZOOM_STEP
6 C COUNTRY_LABEL_FADE_START
7 C COUNTRY_LABEL_FADE_END
8 C FLAG_TIMER_STEP
10 A world_zoom
11 A _base_hemisphere_radius
12 K _flag_time
13 K _flag_palettes
14 G _flag_screen_polygons
15 G _flag_screen_bounds
17 D _world_camera
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd | holographic_workspace_historical_admin_runtime
5 C MAJOR_STATE_PROFILE_PATH
6 C HISTORICAL_ADMIN_PATH
7 C ADMIN_PAGE_SIZE
9 K selected_admin_unit_id
10 K admin_page_index
11 K _major_state_profile_by_entity
12 H _entity_by_nationality_alias
13 K _historical_admin_by_entity
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd | holographic_workspace_historical_evidence
5 C HISTORICAL_GEOMETRY_PATH
6 C HISTORICAL_UNITS_PATH
7 C HISTORICAL_FLAGS_PATH
8 C HISTORICAL_SNAPSHOT_DATE
9 C GLOBAL_SOURCE_NOTICE
10 C LOWER_ADMIN_NOTICE
12 C NATIONALITY_ENTITY_ALIASES
46 K _dated_geometry_document
47 K _dated_units_document
48 K _historical_flag_document
49 K _historical_flag_records
50 K _geometry_feature_by_id
51 K _missing_flag_record_ids
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_history.gd | holographic_workspace_history
3 C WORLD_HISTORICAL_ENTITY_FOCUS
4 C HISTORY_ZOOM_MIN
5 C HISTORY_ZOOM_MAX
6 C HISTORY_ZOOM_FACTOR
7 C HISTORY_LABEL_FADE_START
8 C HISTORY_LABEL_FADE_END
10 A history_war_layer_visible
11 K selected_historical_territory_iso
12 K hover_historical_territory_iso
14 K _history_document
15 K _history_entity_by_id
16 K _history_territories_by_entity
17 K _history_modern_record_by_iso
18 K _history_modern_polygons_by_iso
19 E _history_modern_anchor_by_iso
20 K _history_explicit_mapped_isos
21 K _history_provisional_entity_ids
22 G _history_focus_screen_polygons
23 G _history_focus_screen_bounds
24 A _history_focus_dirty
25 K _history_conflicts
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_interaction_probe.gd | holographic_workspace_interaction_probe
3 C TARGET_SCENE
5 K workspace
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_polish.gd | holographic_workspace_polish
3 C REGION_CITY_SUPPLEMENTS
29 K selected_administrative_unit_id
30 K hover_administrative_unit_id
31 K _administrative_notice
32 K _administrative_unit_by_id
33 K _administrative_polygons_by_id
34 E _administrative_anchor_by_id
35 K _administrative_units_by_region
36 G _administrative_screen_polygons
37 K _globe_grid_unit_lines
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd | holographic_workspace_release
4 C FOREIGN_ADMIN1_NOTICE
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_release_probe.gd | holographic_workspace_release_probe
3 C TARGET_SCENE
5 K workspace
```

### 第7段：`scripts/ui_spikes/holographic_workspace/holographic_workspace_release_quality.gd` 至 `scripts/v2_2/v2_life_loop_simulation.gd`

```text
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_release_quality.gd | holographic_workspace_release_quality
4 C IDENTITY_PREFIX
5 C IDENTITY_SEPARATOR
6 C ADMIN1_REFERENCE_NOTICE
7 C FLAG_REFERENCE_NOTICE
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd | holographic_workspace_runtime
3 C WORLD
4 C REGION
5 C CITY
6 C WORLD_COUNTRIES
7 C WORLD_COUNTRY_FOCUS
8 C LAYOUT_FOCUS
9 C LAYOUT_WORKSPACE
10 C FOCUS_COUNTRY_ID
11 C CAMERA_ORTHO_SIZE
12 C EDGE_BAND
13 C DRAG_THRESHOLD
14 C MOTION_EPSILON
15 C FOCUS_VIEWPORT_SIZE
16 C WORKSPACE_VIEWPORT_SIZE
18 A layout_mode_id
19 G workspace_open
20 A space_level
21 A world_mode
23 E selected_country_id
24 K selected_region_id
25 K selected_city_id
26 K selected_event_id
27 K selected_institution_id
28 E hover_country_id
29 K hover_region_id
30 K hover_event_id
32 G info_open
33 K info_progress
34 K _info_tween
35 K active_hud_panel
36 A active_character_key
38 A yaw
39 A tilt
40 K angular_velocity
41 K dragging
42 A drag_start
43 A drag_last
44 K drag_moved
46 A sim_paused
47 A sim_speed
48 A sim_day
49 A sim_month
50 A sim_year
51 A sim_hour
52 K sim_minute
53 A activity_unread
55 E _countries
56 E _country_by_id
57 E _country_unit_polygons
58 E _country_anchor_units
59 K _coastline_unit_lines
61 K _regions
62 K _region_by_id
63 K _region_polygons
64 K _cities
65 K _city_by_id
66 K _cities_by_region
67 K _institutions
68 K _institution_by_id
69 K _institutions_by_city
70 K _institutions_by_region
71 K _character_profiles
72 E _country_profile
73 K _world_events
74 K _event_by_id
75 K _data_errors
77 K _button_hits
78 A _hemisphere_center
79 A _hemisphere_rect
80 A _hemisphere_radius
81 E _focus_bounds
83 A _projection_dirty
84 G _global_screen_segments
85 E _selected_country_segments
86 G _country_screen_anchors
87 G _event_screen_positions
88 G _focus_country_screen_polygons
89 G _focus_region_screen_polygons
90 G _focus_region_screen_anchors
92 D viewport_container
93 D viewport
@ scripts/ui_spikes/holographic_workspace/holographic_workspace_visual.gd | holographic_workspace_visual
3 K _workspace_font
@ scripts/v2_2/v2_condition_service.gd | V2ConditionService
5 K person_states
6 K causal_events
7 K sleep_hour_history
8 K _effects
9 K _rules
10 A _next_sequence
11 A _maximum_events
@ scripts/v2_2/v2_datetime.gd | V2DateTime
5 C START_YEAR
6 C WEEKDAY_NAMES
@ scripts/v2_2/v2_employment_service.gd | V2EmploymentService
5 K contracts
6 K attendance_records
7 K processed_pay_period_ids
8 K _attendance_keys
9 A _maximum_records
@ scripts/v2_2/v2_household_service.gd | V2HouseholdService
5 K households
6 K person_to_household
7 K processed_idempotency_keys
8 K living_costs
9 K _processed_key_order
11 C MAX_PROCESSED_KEYS
@ scripts/v2_2/v2_ledger_service.gd | V2LedgerService
5 C MAX_PROCESSED_KEYS
7 K transactions
8 K opening_cash
9 K _processed_keys
10 K _processed_key_order
11 A _next_sequence
12 A _maximum_per_household
@ scripts/v2_2/v2_life_loop_config.gd | V2LifeLoopConfig
5 C PATHS
14 K documents
15 K errors
@ scripts/v2_2/v2_life_loop_interface_final.gd | V2LifeLoopInterfaceFinal
5 C V2_MENU_SCENE
6 C RELATIONSHIP_FIRST_ROW_OFFSET
7 C SUMMARY_HEADING_OFFSET
@ scripts/v2_2/v2_life_loop_main.gd | V2LifeLoopMain
6 C ERROR_OVERLAY_NAME
7 C EDGE_SCROLL_MARGIN
8 C EDGE_SCROLL_MIN_SPEED
9 C EDGE_SCROLL_MAX_SPEED
10 C LAUNCH_MODE_META
12 K life_simulation
13 K life_binding
14 K life_initialization_error
15 K _activity_panel_was_open
16 K _edge_scrolling_map
@ scripts/v2_2/v2_life_loop_menu.gd | V2LifeLoopMenu
5 C LIFE_LOOP_SCENE
6 C LAUNCH_MODE_META
8 D new_button
9 D load_button
10 D quit_button
11 D status_label
@ scripts/v2_2/v2_life_loop_result.gd | V2LifeLoopResult
5 K success
6 K error_code
7 K user_message
8 K technical_message
9 K affected_entity_ids
10 K suggested_alternatives
11 K data
@ scripts/v2_2/v2_life_loop_simulation.gd | V2LifeLoopSimulation
7 C SCHEMA_VERSION
8 C DEFAULT_REVIEW_SAVE_PATH
9 C PIERRE_ID
10 C ALBERT_ID
11 C JEANNE_ID
12 C UNION_ID
14 K clock
15 A config
16 K random
17 A schedule
18 A employment
19 A ledger
20 A households
21 A conditions
22 A relationships
23 A organizations
24 A notifications
26 K scenario_id
27 A selected_person_id
28 K person_states
29 K processed_idempotency_keys
30 K _processed_hour_keys
31 K initialization_error
32 K initialized
33 K last_hour_processing_usec
34 K maximum_hour_processing_usec
35 K hours_processed
```

### 第8段：`scripts/v2_2/v2_life_loop_ui_binding.gd` 至 `scripts/v2_3/v2_3_formal_schedule_interface.gd`

<!-- INVENTORY_PART_08 -->

### 第9段：`scripts/v2_3/v2_3_formal_simulation.gd` 至 `scripts/v2_3/v2_3_survival_autonomy_service.gd`

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

