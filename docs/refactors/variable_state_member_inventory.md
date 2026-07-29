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

