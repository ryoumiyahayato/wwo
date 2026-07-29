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

<!-- INVENTORY_PART_09 -->

### 第10段：`scripts/world_map/internal/world_map_canvas_impl.gd` 至 `scripts/world_map/internal/world_map_data_impl.gd`

```text
@ scripts/world_map/internal/world_map_canvas_impl.gd | PrototypeV2MapCanvas
5 C WORLD_SIZE
6 C WORLD_BOUNDS
7 C ROBINSON_X
12 C ROBINSON_Y
17 C ROBINSON_X_EXTENT
18 C ROBINSON_Y_EXTENT
19 C CAMERA_REFRESH_THRESHOLD_PIXELS
20 C ZOOM_SETTLE_USEC
21 C FOCUS_COUNTRY_ID
22 C PLAYER_CITY_ID
24 C OCEAN_TOP
25 C OCEAN_BOTTOM
26 C OCEAN_GRID
27 C LAND_BASE
28 C COAST
29 C COUNTRY_BORDER
30 C REGION_BORDER
31 C ADMINISTRATIVE_BORDER
32 C ADMINISTRATIVE_LABEL
33 C LABEL
34 C LABEL_MUTED
35 C SELECT
36 C CITY
37 C PORT_COLOR
38 C RAIL_DARK
39 C RAIL_LIGHT
40 C ROAD
41 C SHIPPING
42 C INSTITUTION
43 C ORGANIZATION
44 C FRONT
46 A current_mode
47 K selected_id
48 K selected_type
49 A zoom
50 A pan
51 K war_example_active
52 E hovered_country_id
53 A camera_focus_id
55 K _data
56 K _font
57 K _coastlines
58 E _countries
59 K _regions
60 K _administrative_units
61 K _cities
62 K _ports
63 K _rail_segments
64 K _road_segments
65 K _shipping_routes
66 K _institutions
67 K _organizations
68 K _modes
69 F _geometry_cache
71 E _country_by_id
72 E _country_by_iso
73 K _features_by_iso
74 K _region_by_id
75 K _administrative_unit_by_id
76 K _city_by_id
77 K _port_by_id
78 K _institution_by_id
79 K _organization_by_id
80 E _country_index_by_id
81 K _region_index_by_id
82 K _administrative_index_by_id
83 K _city_index_by_id
84 K _port_index_by_id
85 K _institution_index_by_id
86 K _organization_index_by_id
88 E _country_lod_features
89 K _administrative_lod_records
90 K _macro_region_records
91 K _macro_region_by_id
92 K _world_points
93 K _rail_world_records
94 K _road_world_records
95 K _shipping_world_records
96 K _graticule_lines
97 A _war_control_polygon
98 A _war_control_triangles
99 A _war_front_points
101 E _country_spatial_indexes
102 K _administrative_spatial_indexes
103 A _macro_spatial_index
104 A _city_spatial_index
105 A _port_spatial_index
106 A _institution_spatial_index
107 A _organization_spatial_index
108 A _rail_spatial_index
109 A _road_spatial_index
110 A _shipping_spatial_index
111 A _v2_3_local_spatial_index
113 G _visible_country_indices
114 G _visible_administrative_indices
115 G _visible_macro_indices
116 G _visible_city_indices
117 G _visible_port_indices
118 G _visible_institution_indices
119 G _visible_organization_indices
120 G _visible_rail_indices
121 G _visible_road_indices
122 G _visible_shipping_indices
123 G _visible_v2_3_local_indices
124 K _query_scratch
125 K _point_query_scratch
127 K _v2_3_local_overlay
128 K _v2_3_local_locations
129 K _v2_3_local_location_points
130 K _v2_3_local_location_lookup
131 K _v2_3_local_edge_lookup
132 A _v2_3_local_catalog_revision
133 A _v2_3_local_overlay_revision
135 K _background_layer
136 E _country_layer
137 K _region_layer
138 K _administrative_layer
139 K _transport_layer
140 K _node_layer
141 K _selection_layer
142 K _label_layer
143 K _hud_layer
144 K _world_layers
146 A _current_lod
147 K _dragging_camera
148 K _zoom_settle_deadline_usec
149 F _visible_cache_pan
150 F _visible_cache_zoom
151 F _label_cache_pan
152 F _label_cache_zoom
153 F _label_cache_bucket
154 K _label_items
155 K _label_rects
156 E _label_counts
157 F _label_cache_by_bucket
158 F _text_size_cache
159 K _rail_ties_by_lod
160 A _dirty_flags
169 K _perf_queue_redraw_calls
170 K _perf_draw_calls
171 K _perf_projection_calls
172 K _perf_runtime_merge_calls
173 K _perf_runtime_triangulation_calls
174 K _perf_draw_ms_samples
175 K _perf_hotspots
176 K _perf_traversal_totals
177 K _perf_layer_redraws
178 K _perf_camera_transform_updates
179 G _perf_visible_queries
180 K _perf_label_rebuilds
181 F _perf_label_cache_reuses
182 K _perf_click_candidates
183 K _perf_transport_rebuilds
184 K _perf_v2_3_overlay_updates
185 K _perf_v2_3_catalog_rebuilds
@ scripts/world_map/internal/world_map_controller_impl.gd | PrototypeV2Main
5 C DRAG_THRESHOLD
7 D map_canvas
8 D interface
10 K prototype_data
11 K _left_button_down
12 K _dragging_map
13 G _ui_captured_press
14 A _press_position
15 K _capture_path
16 K _exit_after_capture
@ scripts/world_map/internal/world_map_data_impl.gd | PrototypeV2Data
6 C FILES
25 K records
26 K errors
```

### 第11段：`scripts/world_map/internal/world_map_interface_impl.gd` 至 `scripts/world_map/world_map_canvas_detail.gd`

```text
@ scripts/world_map/internal/world_map_interface_impl.gd | PrototypeV2Interface
9 C INK
10 C INK_MUTED
11 C INK_DIM
12 C PANEL
13 C PANEL_SOLID
14 C PANEL_SOFT
15 C LINE
16 C GOLD
17 C GREEN
18 C RED
19 C AMBER
20 C BLUE
21 C SHADOW
23 C COUNTRY_CORNER
24 C TIME_CORNER
25 C SYSTEM_CORNER
26 C CHARACTER_CORNER
27 C ACTIVITY_CORNER
28 C MODE_ENTRY
29 C WORLD_VIEW_ENTRY
30 C REVIEW_SWITCH
31 C MAX_PRIMARY_PANEL_WIDTH
33 K data
34 K life_binding
35 A identity
36 K open_panel
37 A character_section
38 K detail_person_id
39 K person_detail_level
40 K action_detail_id
41 K selected_object
42 A paused
43 A speed
44 A current_mode
45 K mode_menu_open
46 K system_menu_open
47 K person_more_menu_open
48 K review_mode
49 K schedule_form
50 A panel_progress
55 K _font
56 K _click_targets
57 K _hover_tooltip
58 A _hover_position
59 K _toast
60 K _toast_until_msec
61 K _panel_tween
@ scripts/world_map/internal/world_map_layer_impl.gd | PrototypeV2MapLayer
5 K layer_id
6 K draw_callback
7 E redraw_count
8 A size
@ scripts/world_map/internal/world_map_spatial_index_impl.gd | PrototypeV2SpatialIndex
5 E _world_bounds
6 A _cell_size
7 A _columns
8 A _rows
9 K _buckets
10 A _stamps
11 A _generation
12 K last_query_cells
13 K last_query_candidates
@ scripts/world_map/world_city_shard_catalog.gd | WorldCityShardCatalog
7 C INDEX_PATH
8 C SHARD_ROOT
9 C HARD_CACHE_LIMIT
10 C HARD_NODE_BUDGET
11 C HARD_LABEL_BUDGET
12 C MIN_RUNTIME_PRIORITY
14 K configured
15 K index_document
16 K shard_metadata
17 G visible_records
18 G visible_by_id
20 K _projector
21 K _loaded_shards
22 K _lru_shard_ids
23 G _visible_signature
24 F _cache_limit
25 A _node_budget
26 A _label_budget
27 A _metrics
@ scripts/world_map/world_map_canvas.gd | WorldMapCanvas
6 C MAP_SCOPE_WORLD
7 C MAP_SCOPE_REGIONAL
8 C MAP_SCOPE_CITY
9 C REGIONAL_ZOOM
10 C CITY_SCOPE_THRESHOLD
11 C CITY_ZOOM
12 C CITY_LOCAL_SCALE
13 C CITY_PLATE_HALF_SIZE
15 F _scope_cache
16 A _current_city_parent_id
@ scripts/world_map/world_map_canvas_detail.gd | WorldMapCanvasDetail
6 C DETAIL_CITY_COLOR
7 C DETAIL_SELECTED_COLOR
9 A _city_detail_catalog
```

