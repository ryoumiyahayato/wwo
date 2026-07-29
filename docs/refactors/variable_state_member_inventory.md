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

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

