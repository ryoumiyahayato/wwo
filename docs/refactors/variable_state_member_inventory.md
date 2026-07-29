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

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

