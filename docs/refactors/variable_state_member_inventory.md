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

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

<!-- INVENTORY_PART_10 -->

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

<!-- INVENTORY_PART_11 -->

