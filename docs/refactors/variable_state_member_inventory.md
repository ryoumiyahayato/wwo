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

