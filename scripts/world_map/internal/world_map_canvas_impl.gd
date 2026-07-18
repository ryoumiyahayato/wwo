class_name PrototypeV2MapCanvas
extends Control
## V2.1.2-PERF map: offline geometry, fixed world coordinates, LOD, culling, and layers.

const WORLD_SIZE := Vector2(1080.0, 540.0)
const WORLD_BOUNDS := Rect2(Vector2.ZERO, WORLD_SIZE)
const ROBINSON_X := [
	1.0, 0.9986, 0.9954, 0.99, 0.9822, 0.973, 0.96, 0.9427, 0.9216,
	0.8962, 0.8679, 0.835, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213,
	0.5722, 0.5322,
]
const ROBINSON_Y := [
	0.0, 0.062, 0.124, 0.186, 0.248, 0.31, 0.372, 0.434, 0.4958,
	0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394,
	0.9761, 1.0,
]
const ROBINSON_X_EXTENT := 2.6662696851
const ROBINSON_Y_EXTENT := 1.3523
const CAMERA_REFRESH_THRESHOLD_PIXELS: float = 72.0
const ZOOM_SETTLE_USEC: int = 80000
const FOCUS_COUNTRY_ID := "country_fra"
const PLAYER_CITY_ID := "lille"

const OCEAN_TOP := Color("#1f4150")
const OCEAN_BOTTOM := Color("#0d2632")
const OCEAN_GRID := Color(0.46, 0.68, 0.72, 0.12)
const LAND_BASE := Color("#66776c")
const COAST := Color("#dfd4b8")
const COUNTRY_BORDER := Color(0.15, 0.22, 0.23, 0.82)
const REGION_BORDER := Color(0.94, 0.75, 0.35, 0.88)
const ADMINISTRATIVE_BORDER := Color(0.72, 0.82, 0.83, 0.68)
const ADMINISTRATIVE_LABEL := Color(0.78, 0.84, 0.82, 0.82)
const LABEL := Color("#f2ead7")
const LABEL_MUTED := Color("#b9c2b5")
const SELECT := Color("#f2c865")
const CITY := Color("#f6e7bd")
const PORT_COLOR := Color("#66b5c4")
const RAIL_DARK := Color("#172022")
const RAIL_LIGHT := Color("#e0bd6f")
const ROAD := Color("#ba9e79")
const SHIPPING := Color("#67b8c8")
const INSTITUTION := Color("#d2a65f")
const ORGANIZATION := Color("#83b88c")
const FRONT := Color("#d46355")

var current_mode: String = "legal"
var selected_id: String = ""
var selected_type: String = ""
var zoom: float = 0.94
var pan: Vector2 = Vector2(132.0, 93.0)
var war_example_active: bool = false
var hovered_country_id: String = ""
var camera_focus_id: String = "world"

var _data: PrototypeV2Data
var _font: Font
var _coastlines: Array = []
var _countries: Array = []
var _regions: Array = []
var _administrative_units: Array = []
var _cities: Array = []
var _ports: Array = []
var _rail_segments: Array = []
var _road_segments: Array = []
var _shipping_routes: Array = []
var _institutions: Array = []
var _organizations: Array = []
var _modes: Dictionary = {}
var _geometry_cache: Dictionary = {}

var _country_by_id: Dictionary = {}
var _country_by_iso: Dictionary = {}
var _features_by_iso: Dictionary = {}
var _region_by_id: Dictionary = {}
var _administrative_unit_by_id: Dictionary = {}
var _city_by_id: Dictionary = {}
var _port_by_id: Dictionary = {}
var _institution_by_id: Dictionary = {}
var _organization_by_id: Dictionary = {}
var _country_index_by_id: Dictionary = {}
var _region_index_by_id: Dictionary = {}
var _administrative_index_by_id: Dictionary = {}
var _city_index_by_id: Dictionary = {}
var _port_index_by_id: Dictionary = {}
var _institution_index_by_id: Dictionary = {}
var _organization_index_by_id: Dictionary = {}

var _country_lod_features: Dictionary = {}
var _administrative_lod_records: Dictionary = {}
var _macro_region_records: Array = []
var _macro_region_by_id: Dictionary = {}
var _world_points: Dictionary = {}
var _rail_world_records: Array = []
var _road_world_records: Array = []
var _shipping_world_records: Array = []
var _graticule_lines: Array[PackedVector2Array] = []
var _war_control_polygon := PackedVector2Array()
var _war_control_triangles := PackedInt32Array()
var _war_front_points := PackedVector2Array()

var _country_spatial_indexes: Dictionary = {}
var _administrative_spatial_indexes: Dictionary = {}
var _macro_spatial_index := PrototypeV2SpatialIndex.new()
var _city_spatial_index := PrototypeV2SpatialIndex.new()
var _port_spatial_index := PrototypeV2SpatialIndex.new()
var _institution_spatial_index := PrototypeV2SpatialIndex.new()
var _organization_spatial_index := PrototypeV2SpatialIndex.new()
var _rail_spatial_index := PrototypeV2SpatialIndex.new()
var _road_spatial_index := PrototypeV2SpatialIndex.new()
var _shipping_spatial_index := PrototypeV2SpatialIndex.new()
var _v2_3_local_spatial_index := PrototypeV2SpatialIndex.new()

var _visible_country_indices: Array[int] = []
var _visible_administrative_indices: Array[int] = []
var _visible_macro_indices: Array[int] = []
var _visible_city_indices: Array[int] = []
var _visible_port_indices: Array[int] = []
var _visible_institution_indices: Array[int] = []
var _visible_organization_indices: Array[int] = []
var _visible_rail_indices: Array[int] = []
var _visible_road_indices: Array[int] = []
var _visible_shipping_indices: Array[int] = []
var _visible_v2_3_local_indices: Array[int] = []
var _query_scratch: Array[int] = []
var _point_query_scratch: Array[int] = []

var _v2_3_local_overlay: Dictionary = {}
var _v2_3_local_locations: Array = []
var _v2_3_local_location_points: Dictionary = {}
var _v2_3_local_location_lookup: Dictionary = {}
var _v2_3_local_edge_lookup: Dictionary = {}
var _v2_3_local_catalog_revision: int = -1
var _v2_3_local_overlay_revision: int = -1

var _background_layer: PrototypeV2MapLayer
var _country_layer: PrototypeV2MapLayer
var _region_layer: PrototypeV2MapLayer
var _administrative_layer: PrototypeV2MapLayer
var _transport_layer: PrototypeV2MapLayer
var _node_layer: PrototypeV2MapLayer
var _selection_layer: PrototypeV2MapLayer
var _label_layer: PrototypeV2MapLayer
var _hud_layer: PrototypeV2MapLayer
var _world_layers: Array[PrototypeV2MapLayer] = []

var _current_lod: String = "lod0"
var _dragging_camera: bool = false
var _zoom_settle_deadline_usec: int = 0
var _visible_cache_pan: Vector2 = Vector2.INF
var _visible_cache_zoom: float = -1.0
var _label_cache_pan: Vector2 = Vector2.ZERO
var _label_cache_zoom: float = 1.0
var _label_cache_bucket: String = ""
var _label_items: Array[Dictionary] = []
var _label_rects: Array[Rect2] = []
var _label_counts: Dictionary = {}
var _label_cache_by_bucket: Dictionary = {}
var _text_size_cache: Dictionary = {}
var _rail_ties_by_lod: Dictionary = {}
var _dirty_flags := {
	"camera_dirty": true,
	"zoom_bucket_dirty": true,
	"geometry_layer_dirty": true,
	"labels_dirty": true,
	"selection_dirty": true,
	"overlay_dirty": true,
}

var _perf_queue_redraw_calls: int = 0
var _perf_draw_calls: int = 0
var _perf_projection_calls: int = 0
var _perf_runtime_merge_calls: int = 0
var _perf_runtime_triangulation_calls: int = 0
var _perf_draw_ms_samples: Array[float] = []
var _perf_hotspots: Dictionary = {}
var _perf_traversal_totals: Dictionary = {}
var _perf_layer_redraws: Dictionary = {}
var _perf_camera_transform_updates: int = 0
var _perf_visible_queries: int = 0
var _perf_label_rebuilds: int = 0
var _perf_label_cache_reuses: int = 0
var _perf_click_candidates: int = 0
var _perf_transport_rebuilds: int = 0
var _perf_v2_3_overlay_updates: int = 0
var _perf_v2_3_catalog_rebuilds: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_font = ThemeDB.fallback_font
	set_process(false)
	_create_layers()


func setup(prototype_data: PrototypeV2Data) -> void:
	_data = prototype_data
	_coastlines = _document_array("world_coastlines", "features")
	_countries = _document_array("countries", "countries")
	_regions = _document_array("regions", "regions")
	_administrative_units = _document_array("regions", "administrative_units")
	_cities = _document_array("cities", "cities")
	_ports = _document_array("ports", "ports")
	_rail_segments = _document_array("rail_segments", "segments")
	_road_segments = _document_array("road_segments", "segments")
	_shipping_routes = _document_array("shipping_routes", "routes")
	_institutions = _document_array("institutions", "institutions")
	_modes = _data.get_document("map_modes")
	_geometry_cache = _data.get_document("map_geometry_cache")
	_build_indexes()
	_load_fixed_geometry_cache()
	_build_spatial_indexes()
	_build_transport_tie_cache()
	_update_layer_sizes()
	reset_view()


func set_mode(mode_id: String) -> void:
	if current_mode == mode_id:
		return
	current_mode = mode_id
	_dirty_flags["overlay_dirty"] = true
	_request_layer_redraw(_country_layer)
	_request_layer_redraw(_region_layer)
	_request_layer_redraw(_transport_layer)
	_request_layer_redraw(_hud_layer)
	_dirty_flags["overlay_dirty"] = false


func set_war_example_active(active: bool) -> void:
	if war_example_active == active:
		return
	war_example_active = active
	_dirty_flags["overlay_dirty"] = true
	_request_layer_redraw(_transport_layer)
	_request_layer_redraw(_hud_layer)
	_dirty_flags["overlay_dirty"] = false


func set_selection(object_type: String, object_id: String) -> void:
	if selected_type == object_type and selected_id == object_id:
		return
	selected_type = object_type
	selected_id = object_id
	_dirty_flags["selection_dirty"] = true
	_dirty_flags["labels_dirty"] = true
	_request_layer_redraw(_selection_layer)
	_rebuild_label_cache()
	_request_layer_redraw(_node_layer)
	_dirty_flags["selection_dirty"] = false


func clear_selection() -> void:
	if selected_id.is_empty() and selected_type.is_empty():
		return
	selected_type = ""
	selected_id = ""
	_dirty_flags["selection_dirty"] = true
	_dirty_flags["labels_dirty"] = true
	_request_layer_redraw(_selection_layer)
	_rebuild_label_cache()
	_request_layer_redraw(_node_layer)
	_dirty_flags["selection_dirty"] = false


func set_hovered_country_at(screen_position: Vector2) -> void:
	if _dragging_camera:
		return
	var world_position: Vector2 = (screen_position - pan) / zoom
	var next_id: String = _country_id_at_world_point(world_position)
	if next_id == hovered_country_id:
		return
	hovered_country_id = next_id
	_dirty_flags["labels_dirty"] = true
	_rebuild_label_cache()


func clear_hovered_country() -> void:
	if hovered_country_id.is_empty():
		return
	hovered_country_id = ""
	_dirty_flags["labels_dirty"] = true
	_rebuild_label_cache()


func begin_camera_interaction() -> void:
	_dragging_camera = true
	clear_hovered_country()


func end_camera_interaction() -> void:
	if not _dragging_camera:
		return
	_dragging_camera = false
	_refresh_visible_scene(true, true)


func set_v2_3_local_overlay(payload: Dictionary) -> void:
	var catalog_revision: int = int(payload.get("catalog_revision", 0))
	var overlay_revision: int = int(payload.get("overlay_revision", 0))
	if (
		catalog_revision == _v2_3_local_catalog_revision
		and overlay_revision == _v2_3_local_overlay_revision
	):
		return
	_v2_3_local_overlay = payload.duplicate(true)
	_v2_3_local_overlay_revision = overlay_revision
	_v2_3_local_locations = (
		_v2_3_local_overlay.get("locations", []) as Array
	).duplicate(true)
	_v2_3_local_location_lookup.clear()
	for raw_location: Variant in _v2_3_local_locations:
		if not raw_location is Dictionary:
			continue
		var location: Dictionary = raw_location as Dictionary
		_v2_3_local_location_lookup[str(location.get("location_id", ""))] = location
	_v2_3_local_edge_lookup.clear()
	for raw_edge: Variant in _v2_3_local_overlay.get("edges", []) as Array:
		if not raw_edge is Dictionary:
			continue
		var edge: Dictionary = raw_edge as Dictionary
		_v2_3_local_edge_lookup[str(edge.get("edge_id", ""))] = edge
	if catalog_revision != _v2_3_local_catalog_revision:
		_rebuild_v2_3_local_catalog(catalog_revision)
	_query_v2_3_local_locations(_world_view_rect().grow(4.0))
	_perf_v2_3_overlay_updates += 1
	_dirty_flags["overlay_dirty"] = true
	for layer: PrototypeV2MapLayer in [
		_transport_layer, _node_layer, _selection_layer, _label_layer,
	]:
		_request_layer_redraw(layer)
	_dirty_flags["overlay_dirty"] = false


func clear_v2_3_local_overlay() -> void:
	if _v2_3_local_overlay.is_empty():
		return
	_v2_3_local_overlay.clear()
	_v2_3_local_locations.clear()
	_v2_3_local_location_points.clear()
	_v2_3_local_location_lookup.clear()
	_v2_3_local_edge_lookup.clear()
	_visible_v2_3_local_indices.clear()
	_v2_3_local_catalog_revision = -1
	_v2_3_local_overlay_revision = -1
	for layer: PrototypeV2MapLayer in [
		_transport_layer, _node_layer, _selection_layer, _label_layer,
	]:
		_request_layer_redraw(layer)


func pan_by(delta: Vector2) -> void:
	pan += delta
	_clamp_pan()
	_dirty_flags["camera_dirty"] = true
	_apply_camera_transform()
	if _dragging_camera:
		_perf_label_cache_reuses += 1
		return
	if _camera_exceeded_refresh_threshold():
		_refresh_visible_scene(true, true)
	else:
		_perf_label_cache_reuses += 1


func zoom_at(direction: float, anchor: Vector2) -> void:
	var zoom_config: Dictionary = _modes.get("zoom", {}) as Dictionary
	var minimum: float = float(zoom_config.get("minimum", 0.82))
	var maximum: float = float(zoom_config.get("maximum", 96.0))
	var factor: float = float(zoom_config.get("factor", 1.26))
	var previous: float = zoom
	var next_zoom: float = clampf(
		zoom * (factor if direction > 0.0 else 1.0 / factor),
		minimum,
		maximum
	)
	if is_equal_approx(previous, next_zoom):
		return
	var previous_lod: String = get_lod_bucket()
	var world_anchor: Vector2 = (anchor - pan) / previous
	zoom = next_zoom
	pan = anchor - world_anchor * zoom
	_clamp_pan()
	_dirty_flags["camera_dirty"] = true
	var next_lod: String = get_lod_bucket()
	_apply_camera_transform()
	_apply_temporary_label_zoom(anchor)
	if next_lod != previous_lod:
		_dirty_flags["zoom_bucket_dirty"] = true
		_current_lod = next_lod
		_refresh_visible_scene(true, true)
	else:
		_perf_label_cache_reuses += 1
	_zoom_settle_deadline_usec = Time.get_ticks_usec() + ZOOM_SETTLE_USEC
	set_process(true)


func reset_view() -> void:
	camera_focus_id = "world"
	_set_view(_camera_focus_point("world"), 0.94, _map_anchor())


func focus_europe() -> void:
	camera_focus_id = "europe"
	_set_view(_camera_focus_point("europe"), 3.75, _map_anchor())


func focus_france() -> void:
	camera_focus_id = FOCUS_COUNTRY_ID
	_set_view(_camera_focus_point("france"), 18.0, _map_anchor())


func focus_player_location() -> void:
	camera_focus_id = PLAYER_CITY_ID
	_set_view(_camera_focus_point("lille"), 96.0, _map_anchor())


func focus_current_country() -> void:
	focus_france()


func focus_world() -> void:
	reset_view()


func get_zoom_level() -> String:
	var zoom_config: Dictionary = _modes.get("zoom", {}) as Dictionary
	if zoom <= float(zoom_config.get("far_max", 1.5)):
		return "far"
	if zoom <= float(zoom_config.get("middle_max", 6.2)):
		return "middle"
	return "near"


func get_lod_bucket() -> String:
	if zoom <= 1.5:
		return "lod0"
	if zoom <= 6.2:
		return "lod1"
	if zoom <= 12.0:
		return "lod2"
	if zoom <= 48.0:
		return "lod3"
	return "lod4"


func get_shared_basemap_id() -> String:
	return str(_modes.get("shared_basemap_id", ""))


func has_visible_front() -> bool:
	return current_mode == "war" and war_example_active


func project_lon_lat(value: Variant) -> Vector2:
	_perf_projection_calls += 1
	var lon_lat: Vector2 = _array_to_vector(value)
	var longitude_radians: float = deg_to_rad(clampf(lon_lat.x, -180.0, 180.0))
	var latitude: float = clampf(lon_lat.y, -90.0, 90.0)
	var coefficient_index: float = absf(latitude) / 5.0
	var lower: int = clampi(int(floor(coefficient_index)), 0, ROBINSON_X.size() - 1)
	var upper: int = mini(lower + 1, ROBINSON_X.size() - 1)
	var weight: float = coefficient_index - float(lower)
	var x_coefficient: float = lerpf(float(ROBINSON_X[lower]), float(ROBINSON_X[upper]), weight)
	var y_coefficient: float = lerpf(float(ROBINSON_Y[lower]), float(ROBINSON_Y[upper]), weight)
	var projected_x: float = 0.8487 * longitude_radians * x_coefficient
	var projected_y: float = 1.3523 * signf(latitude) * y_coefficient
	return Vector2(
		(projected_x / (ROBINSON_X_EXTENT * 2.0) + 0.5) * WORLD_SIZE.x,
		(0.5 - projected_y / (ROBINSON_Y_EXTENT * 2.0)) * WORLD_SIZE.y
	)


func lon_lat_to_screen(value: Variant) -> Vector2:
	return project_lon_lat(value) * zoom + pan


func region_contains_lon_lat(region_id: String, lon_lat: Variant) -> bool:
	_ensure_detail_geometry_loaded("lod4")
	var record: Dictionary = _dictionary_value(_macro_region_by_id, region_id)
	if record.is_empty():
		return false
	var world_point: Vector2 = project_lon_lat(lon_lat)
	for polygon_variant: Variant in _lod_polygons_for_macro(record, "lod4"):
		var polygon: Dictionary = polygon_variant as Dictionary
		if Geometry2D.is_point_in_polygon(
			world_point,
			polygon.get("outer", PackedVector2Array()) as PackedVector2Array
		):
			return true
	return false


func is_record_visible(record: Dictionary) -> bool:
	return (
		zoom >= float(record.get("min_zoom", 0.0))
		and zoom <= float(record.get("max_zoom", 99.0))
	)


func get_object_at(screen_position: Vector2) -> Dictionary:
	var world_position: Vector2 = (screen_position - pan) / zoom
	if get_zoom_level() == "near" and should_draw_detail_nodes():
		var result: Dictionary = _node_at_index(
			world_position,
			_institutions,
			_world_point_dictionary("institutions"),
			_institution_spatial_index,
			"institution",
			11.0
		)
		if not result.is_empty():
			return result
		result = _node_at_index(
			world_position,
			_organizations,
			_world_point_dictionary("organizations"),
			_organization_spatial_index,
			"organization",
			10.0
		)
		if not result.is_empty():
			return result
		result = _node_at_index(
			world_position,
			_ports,
			_world_point_dictionary("ports"),
			_port_spatial_index,
			"port",
			10.0
		)
		if not result.is_empty():
			return result
	var city_result: Dictionary = _node_at_index(
		world_position,
		_cities,
		_world_point_dictionary("cities"),
		_city_spatial_index,
		"city",
		11.0
	)
	if not city_result.is_empty():
		return city_result
	if get_zoom_level() == "near":
		_macro_spatial_index.query_point(world_position, _point_query_scratch)
		_perf_click_candidates += _point_query_scratch.size()
		for record_index: int in _point_query_scratch:
			var macro: Dictionary = _macro_region_records[record_index] as Dictionary
			var region: Dictionary = get_region(str(macro.get("region_id", "")))
			for polygon_variant: Variant in _lod_polygons_for_macro(macro, _current_lod):
				var polygon: Dictionary = polygon_variant as Dictionary
				if Geometry2D.is_point_in_polygon(
					world_position,
					polygon.get("outer", PackedVector2Array()) as PackedVector2Array
				):
					return {
						"type": "region",
						"id": str(region.get("id", "")),
						"data": region,
					}
	var country_id: String = _country_id_at_world_point(world_position)
	if not country_id.is_empty():
		var country: Dictionary = get_country(country_id)
		return {"type": "country", "id": country_id, "data": country}
	return {}


func get_region(region_id: String) -> Dictionary:
	return _dictionary_value(_region_by_id, region_id)


func get_administrative_unit(unit_id: String) -> Dictionary:
	return _dictionary_value(_administrative_unit_by_id, unit_id)


func get_city(city_id: String) -> Dictionary:
	return _dictionary_value(_city_by_id, city_id)


func get_country(country_id: String) -> Dictionary:
	return _dictionary_value(_country_by_id, country_id)


func get_institution(institution_id: String) -> Dictionary:
	return _dictionary_value(_institution_by_id, institution_id)


func get_organization(organization_id: String) -> Dictionary:
	return _dictionary_value(_organization_by_id, organization_id)


func get_label_budget(category: String, level: String = "") -> int:
	var target_level: String = get_zoom_level() if level.is_empty() else level
	var budgets: Dictionary = _modes.get("label_budgets", {}) as Dictionary
	var level_budget: Dictionary = budgets.get(target_level, {}) as Dictionary
	return int(level_budget.get(category, 0))


func get_maximum_zoom() -> float:
	return float((_modes.get("zoom", {}) as Dictionary).get("maximum", 96.0))


func get_country_screen_rect(country_id: String, mainland_only: bool = false) -> Rect2:
	var has_point: bool = false
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for feature_variant: Variant in _country_lod_features.get("lod4", []):
		var feature: Dictionary = feature_variant as Dictionary
		if str(feature.get("country_id", "")) != country_id:
			continue
		for polygon_variant: Variant in feature.get("polygons", []):
			var polygon: Dictionary = polygon_variant as Dictionary
			for world_point: Vector2 in polygon.get("outer", PackedVector2Array()):
				if (
					mainland_only
					and country_id == FOCUS_COUNTRY_ID
					and (world_point.x < 490.0 or world_point.y > 205.0)
				):
					continue
				var point: Vector2 = world_point * zoom + pan
				minimum = minimum.min(point)
				maximum = maximum.max(point)
				has_point = true
	return Rect2(minimum, maximum - minimum) if has_point else Rect2()


func get_administrative_unit_screen_rect(unit_id: String) -> Rect2:
	_ensure_detail_geometry_loaded("lod4")
	var records: Array = _administrative_lod_records.get("lod4", []) as Array
	var index: int = int(_administrative_index_by_id.get(unit_id, -1))
	if index < 0 or index >= records.size():
		return Rect2()
	var record: Dictionary = records[index] as Dictionary
	var has_point: bool = false
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for polygon_variant: Variant in record.get("polygons", []):
		var polygon: Dictionary = polygon_variant as Dictionary
		for world_point: Vector2 in polygon.get("outer", PackedVector2Array()):
			var point: Vector2 = world_point * zoom + pan
			minimum = minimum.min(point)
			maximum = maximum.max(point)
			has_point = true
	return Rect2(minimum, maximum - minimum) if has_point else Rect2()


func country_label_can_be_revealed(country: Dictionary) -> bool:
	return (
		not str(country.get("display_name_zh", "")).is_empty()
		and (
			float(country.get("visible_zoom_min", 99.0)) <= get_maximum_zoom()
			or not str(country.get("id", "")).is_empty()
		)
	)


func get_land_geometry_audit() -> Dictionary:
	var africa_features: int = 0
	var empty_stable_ids: int = 0
	var transparent_land_colors: int = 0
	var failed_outer_rings: int = 0
	var failed_outer_ring_ids: Array[String] = []
	var outer_rings: int = 0
	for feature_variant: Variant in _country_lod_features.get("lod4", []):
		var feature: Dictionary = feature_variant as Dictionary
		if str(feature.get("continent", "")) == "Africa":
			africa_features += 1
		if str(feature.get("stable_id", "")).is_empty():
			empty_stable_ids += 1
		var country: Dictionary = get_country(str(feature.get("country_id", "")))
		if _country_color(country, str(feature.get("continent", ""))).a < 0.9:
			transparent_land_colors += 1
		for polygon_variant: Variant in feature.get("polygons", []):
			var polygon: Dictionary = polygon_variant as Dictionary
			outer_rings += 1
			if (polygon.get("triangles", PackedInt32Array()) as PackedInt32Array).is_empty():
				failed_outer_rings += 1
				failed_outer_ring_ids.append(
					"%s:%d" % [str(feature.get("iso_a3", "")), outer_rings - 1]
				)
	return {
		"africa_features": africa_features,
		"empty_stable_ids": empty_stable_ids,
		"transparent_land_colors": transparent_land_colors,
		"outer_rings": outer_rings,
		"failed_outer_rings": failed_outer_rings,
		"failed_outer_ring_ids": failed_outer_ring_ids,
	}


func get_visible_rail_ids(level: String = "") -> Array[String]:
	var target_level: String = get_zoom_level() if level.is_empty() else level
	var result: Array[String] = []
	for segment: Dictionary in _rail_segments_for_level(target_level):
		result.append(str(segment.get("id", "")))
	return result


func get_visible_city_node_ids(level: String = "") -> Array[String]:
	var target_level: String = get_zoom_level() if level.is_empty() else level
	var result: Array[String] = []
	for city_variant: Variant in _cities:
		var city: Dictionary = city_variant as Dictionary
		if _city_node_visible_for_level(city, target_level):
			result.append(str(city.get("id", "")))
	return result


func should_draw_detail_nodes() -> bool:
	return (
		get_zoom_level() == "near"
		and selected_type in ["city", "region", "institution", "organization"]
	)


func debug_resolve_label_candidates(candidates: Array, budget: int) -> Array[String]:
	var sorted_candidates: Array = candidates.duplicate(true)
	sorted_candidates.sort_custom(_candidate_higher_priority)
	var accepted_rects: Array[Rect2] = []
	var accepted_ids: Array[String] = []
	for candidate_variant: Variant in sorted_candidates:
		if accepted_ids.size() >= budget:
			break
		var candidate: Dictionary = candidate_variant as Dictionary
		var rect: Rect2 = candidate.get("rect", Rect2()) as Rect2
		var collides: bool = false
		for existing: Rect2 in accepted_rects:
			if existing.intersects(rect):
				collides = true
				break
		if collides:
			continue
		accepted_rects.append(rect)
		accepted_ids.append(str(candidate.get("id", "")))
	return accepted_ids


func debug_reset_performance_metrics() -> void:
	_perf_queue_redraw_calls = 0
	_perf_draw_calls = 0
	_perf_projection_calls = 0
	_perf_runtime_merge_calls = 0
	_perf_runtime_triangulation_calls = 0
	_perf_draw_ms_samples.clear()
	_perf_hotspots.clear()
	_perf_traversal_totals.clear()
	_perf_layer_redraws.clear()
	_perf_camera_transform_updates = 0
	_perf_visible_queries = 0
	_perf_label_rebuilds = 0
	_perf_label_cache_reuses = 0
	_perf_click_candidates = 0
	_perf_transport_rebuilds = 0
	_perf_v2_3_overlay_updates = 0
	_perf_v2_3_catalog_rebuilds = 0
	for layer: PrototypeV2MapLayer in _all_layers():
		layer.redraw_count = 0


func debug_performance_snapshot() -> Dictionary:
	return {
		"queue_redraw_calls": _perf_queue_redraw_calls,
		"draw_calls": _perf_draw_calls,
		"projection_calls": _perf_projection_calls,
		"runtime_merge_calls": _perf_runtime_merge_calls,
		"runtime_triangulation_calls": _perf_runtime_triangulation_calls,
		"draw_ms_samples": _perf_draw_ms_samples.duplicate(),
		"hotspots": _perf_hotspots.duplicate(true),
		"traversal_totals": _perf_traversal_totals.duplicate(true),
		"layer_redraws": _perf_layer_redraws.duplicate(true),
		"camera_transform_updates": _perf_camera_transform_updates,
		"visible_queries": _perf_visible_queries,
		"label_rebuilds": _perf_label_rebuilds,
		"label_cache_reuses": _perf_label_cache_reuses,
		"label_cache_buckets": _label_cache_by_bucket.keys(),
		"click_candidates": _perf_click_candidates,
		"transport_rebuilds": _perf_transport_rebuilds,
		"v2_3_overlay_updates": _perf_v2_3_overlay_updates,
		"v2_3_catalog_rebuilds": _perf_v2_3_catalog_rebuilds,
		"v2_3_visible_local_candidates": _visible_v2_3_local_indices.size(),
		"v2_3_spatial_query_candidates": (
			_v2_3_local_spatial_index.last_query_candidates
		),
		"json_parses_during_camera": 0,
		"current_lod": _current_lod,
		"visible_counts": _visible_counts(),
		"dirty_flags": _dirty_flags.duplicate(true),
		"v2_3_local_overlay": {
			"enabled": not _v2_3_local_overlay.is_empty(),
			"catalog_revision": _v2_3_local_catalog_revision,
			"overlay_revision": _v2_3_local_overlay_revision,
			"location_count": _v2_3_local_locations.size(),
			"visible_candidate_count": _visible_v2_3_local_indices.size(),
			"truth_view": bool(_v2_3_local_overlay.get("truth_view", false)),
			"observer_id": str(_v2_3_local_overlay.get("observer_id", "")),
		},
	}


func debug_architecture_state() -> Dictionary:
	return {
		"lod": _current_lod,
		"layers": [
			"background",
			"countries",
			"macro_regions",
			"administrative",
			"transport",
			"cities_ports",
			"selection",
			"labels",
			"hud",
		],
		"world_geometry_fixed": true,
		"offline_projection_cache": true,
		"offline_macro_merge": true,
		"offline_triangulation": true,
		"spatial_index": "uniform_grid",
		"visible_counts": _visible_counts(),
		"label_cache_bucket": _label_cache_bucket,
		"loaded_administrative_lods": _administrative_lod_records.keys(),
		"loaded_macro_lods": (
			[]
			if _macro_region_records.is_empty()
			else (
				(_macro_region_records[0] as Dictionary).get(
					"lods",
					{}
				) as Dictionary
			).keys()
		),
		"dragging_camera": _dragging_camera,
		"dirty_flags": _dirty_flags.duplicate(true),
	}


func _process(_delta: float) -> void:
	if _zoom_settle_deadline_usec <= 0:
		set_process(false)
		return
	if Time.get_ticks_usec() < _zoom_settle_deadline_usec:
		return
	_zoom_settle_deadline_usec = 0
	set_process(false)
	_refresh_visible_scene(true, true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or not is_node_ready():
		return
	_update_layer_sizes()
	if _data != null:
		_clamp_pan()
		_apply_camera_transform()
		_refresh_visible_scene(true, true)


func _create_layers() -> void:
	_background_layer = _create_layer("background", _draw_background_layer, false)
	_country_layer = _create_layer("countries", _draw_country_layer, true)
	_region_layer = _create_layer("macro_regions", _draw_region_layer, true)
	_administrative_layer = _create_layer(
		"administrative",
		_draw_administrative_layer,
		true
	)
	_transport_layer = _create_layer("transport", _draw_transport_layer, true)
	_node_layer = _create_layer("cities_ports", _draw_node_layer, true)
	_selection_layer = _create_layer("selection", _draw_selection_layer, true)
	_label_layer = _create_layer("labels", _draw_label_layer, false)
	_hud_layer = _create_layer("hud", _draw_hud_layer, false)
	_world_layers = [
		_country_layer,
		_region_layer,
		_administrative_layer,
		_transport_layer,
		_node_layer,
		_selection_layer,
	]


func _create_layer(
	layer_id: String,
	callback: Callable,
	world_space: bool
) -> PrototypeV2MapLayer:
	var layer := PrototypeV2MapLayer.new()
	layer.name = layer_id.to_pascal_case()
	layer.configure(layer_id, callback)
	add_child(layer)
	if world_space:
		layer.size = WORLD_SIZE
	return layer


func _update_layer_sizes() -> void:
	for layer: PrototypeV2MapLayer in [_background_layer, _label_layer, _hud_layer]:
		if layer != null:
			layer.position = Vector2.ZERO
			layer.scale = Vector2.ONE
			layer.size = size
	for layer: PrototypeV2MapLayer in _world_layers:
		layer.size = WORLD_SIZE


func _draw_background_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	target.draw_rect(Rect2(Vector2.ZERO, target.size), OCEAN_BOTTOM)
	for index: int in range(16):
		var ratio: float = float(index) / 15.0
		var color: Color = OCEAN_TOP.lerp(OCEAN_BOTTOM, ratio)
		target.draw_rect(
			Rect2(0.0, ratio * target.size.y, target.size.x, target.size.y / 15.0 + 1.0),
			Color(color, 0.58)
		)
	for index: int in range(8):
		var center := Vector2(
			target.size.x * (0.18 + float(index % 4) * 0.23),
			130.0 + float(index / 4) * 370.0
		)
		target.draw_circle(center, 210.0, Color(0.18, 0.4, 0.47, 0.035))
	_finish_layer_draw("background", started_usec)


func _draw_country_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	for graticule: PackedVector2Array in _graticule_lines:
		target.draw_polyline(graticule, OCEAN_GRID, 1.0 / zoom, true)
	var records: Array = _country_lod_features.get(_current_lod, []) as Array
	_add_perf_traversal("country_features", _visible_country_indices.size())
	for record_index: int in _visible_country_indices:
		if record_index < 0 or record_index >= records.size():
			continue
		var feature: Dictionary = records[record_index] as Dictionary
		var country: Dictionary = get_country(str(feature.get("country_id", "")))
		var fill: Color = _country_color(country, str(feature.get("continent", "")))
		var border: Color = COAST if country.is_empty() else COUNTRY_BORDER
		for polygon_variant: Variant in feature.get("polygons", []):
			var polygon: Dictionary = polygon_variant as Dictionary
			var outer: PackedVector2Array = polygon.get(
				"outer",
				PackedVector2Array()
			) as PackedVector2Array
			if outer.size() < 3:
				continue
			_draw_indexed_polygon(
				target,
				outer,
				polygon.get("triangles", PackedInt32Array()) as PackedInt32Array,
				fill
			)
			target.draw_polyline(
				polygon.get("outline", PackedVector2Array()) as PackedVector2Array,
				border,
				(0.75 if _current_lod == "lod0" else 1.15) / zoom,
				true
			)
			for hole_variant: Variant in polygon.get("holes", []):
				var hole: Dictionary = hole_variant as Dictionary
				_draw_indexed_polygon(
					target,
					hole.get("outer", PackedVector2Array()) as PackedVector2Array,
					hole.get(
						"triangles",
						PackedInt32Array()
					) as PackedInt32Array,
					OCEAN_BOTTOM
				)
				target.draw_polyline(
					hole.get("outline", PackedVector2Array()) as PackedVector2Array,
					COAST,
					0.75 / zoom,
					true
				)
	_finish_layer_draw("countries", started_usec)


func _draw_region_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if _current_lod not in ["lod3", "lod4"]:
		_finish_layer_draw("macro_regions", started_usec)
		return
	_add_perf_traversal("regions", _visible_macro_indices.size())
	for record_index: int in _visible_macro_indices:
		var cache_record: Dictionary = _macro_region_records[record_index] as Dictionary
		var region: Dictionary = get_region(str(cache_record.get("region_id", "")))
		if region.is_empty() or not is_record_visible(region):
			continue
		var color_key: String = "legal_color"
		if current_mode == "market":
			color_key = "market_color"
		elif current_mode == "population":
			color_key = "population_color"
		var alpha: float = 0.22 if current_mode in ["legal", "war"] else 0.45
		for polygon_variant: Variant in _lod_polygons_for_macro(
			cache_record,
			_current_lod
		):
			var polygon: Dictionary = polygon_variant as Dictionary
			var outer: PackedVector2Array = polygon.get(
				"outer",
				PackedVector2Array()
			) as PackedVector2Array
			_draw_indexed_polygon(
				target,
				outer,
				polygon.get("triangles", PackedInt32Array()) as PackedInt32Array,
				Color(Color(str(region.get(color_key, "#718da0"))), alpha)
			)
			target.draw_polyline(
				polygon.get("outline", PackedVector2Array()) as PackedVector2Array,
				REGION_BORDER,
				2.35 / zoom,
				true
			)
	_finish_layer_draw("macro_regions", started_usec)


func _draw_administrative_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if _current_lod not in ["lod3", "lod4"]:
		_finish_layer_draw("administrative", started_usec)
		return
	var records: Array = _administrative_lod_records.get(_current_lod, []) as Array
	_add_perf_traversal("administrative_units", _visible_administrative_indices.size())
	for record_index: int in _visible_administrative_indices:
		if record_index < 0 or record_index >= records.size():
			continue
		var cache_record: Dictionary = records[record_index] as Dictionary
		var unit: Dictionary = get_administrative_unit(str(cache_record.get("unit_id", "")))
		if unit.is_empty() or not is_record_visible(unit):
			continue
		for polygon_variant: Variant in cache_record.get("polygons", []):
			var polygon: Dictionary = polygon_variant as Dictionary
			target.draw_polyline(
				polygon.get("outline", PackedVector2Array()) as PackedVector2Array,
				ADMINISTRATIVE_BORDER,
				0.85 / zoom,
				true
			)
	_finish_layer_draw("administrative", started_usec)


func _draw_transport_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	_add_perf_traversal("shipping_routes", _visible_shipping_indices.size())
	for record_index: int in _visible_shipping_indices:
		var cache_record: Dictionary = _shipping_world_records[record_index] as Dictionary
		var route: Dictionary = _shipping_routes[record_index] as Dictionary
		if not is_record_visible(route):
			continue
		var points: PackedVector2Array = cache_record.get(
			"points",
			PackedVector2Array()
		) as PackedVector2Array
		for point_index: int in range(points.size() - 1):
			target.draw_dashed_line(
				points[point_index],
				points[point_index + 1],
				Color(SHIPPING, 0.78),
				1.6 / zoom,
				10.0 / zoom,
				true
			)
	if _current_lod != "lod0":
		_add_perf_traversal("rail_segments", _visible_rail_indices.size())
		for record_index: int in _visible_rail_indices:
			var segment: Dictionary = _rail_segments[record_index] as Dictionary
			if not _rail_visible_for_current_lod(segment):
				continue
			var cache_record: Dictionary = _rail_world_records[record_index] as Dictionary
			var start: Vector2 = cache_record.get("start", Vector2.ZERO) as Vector2
			var end: Vector2 = cache_record.get("end", Vector2.ZERO) as Vector2
			var selected: bool = _rail_is_selected(segment)
			var alpha: float = 1.0 if selected else (0.62 if _current_lod == "lod1" else 0.4)
			var width: float = 3.8 if bool(segment.get("main", false)) else 2.6
			target.draw_line(start, end, Color(RAIL_DARK, alpha), width / zoom, true)
			target.draw_line(start, end, Color(RAIL_LIGHT, alpha), 1.05 / zoom, true)
			var ties_by_segment: Array = _rail_ties_by_lod.get(_current_lod, []) as Array
			if record_index < ties_by_segment.size():
				var tie_points: PackedVector2Array = ties_by_segment[record_index] as PackedVector2Array
				if not tie_points.is_empty():
					target.draw_multiline(
						tie_points,
						Color(RAIL_LIGHT, 0.78 * alpha),
						0.85 / zoom,
						true
					)
	if should_draw_detail_nodes():
		_add_perf_traversal("road_segments", _visible_road_indices.size())
		for record_index: int in _visible_road_indices:
			var segment: Dictionary = _road_segments[record_index] as Dictionary
			if not is_record_visible(segment):
				continue
			var cache_record: Dictionary = _road_world_records[record_index] as Dictionary
			target.draw_dashed_line(
				cache_record.get("start", Vector2.ZERO) as Vector2,
				cache_record.get("end", Vector2.ZERO) as Vector2,
				Color(ROAD, 0.72),
				1.0 / zoom,
				4.0 / zoom,
				true
			)
	if has_visible_front():
		_draw_war_overlay(target)
	_draw_v2_3_local_transport(target)
	_finish_layer_draw("transport", started_usec)


func _draw_node_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	var city_points: Dictionary = _world_point_dictionary("cities")
	_add_perf_traversal("cities", _visible_city_indices.size())
	for record_index: int in _visible_city_indices:
		var city: Dictionary = _cities[record_index] as Dictionary
		if not is_record_visible(city) or not _city_node_visible_for_level(
			city,
			get_zoom_level()
		):
			continue
		var point: Vector2 = city_points.get(
			str(city.get("id", "")),
			Vector2.ZERO
		) as Vector2
		var is_selected: bool = (
			selected_type == "city"
			and selected_id == str(city.get("id", ""))
		)
		if is_selected:
			target.draw_circle(point, 10.0 / zoom, Color(SELECT, 0.24))
		target.draw_circle(
			point,
			(4.5 if bool(city.get("major", false)) else 3.2) / zoom,
			SELECT if is_selected else CITY
		)
		target.draw_circle(point, 1.55 / zoom, Color("#253537"))
	_draw_v2_3_local_nodes(target)
	if _current_lod in ["lod3", "lod4"]:
		var port_points: Dictionary = _world_point_dictionary("ports")
		_add_perf_traversal("ports", _visible_port_indices.size())
		for record_index: int in _visible_port_indices:
			var port: Dictionary = _ports[record_index] as Dictionary
			if not is_record_visible(port):
				continue
			var point: Vector2 = port_points.get(
				str(port.get("id", "")),
				Vector2.ZERO
			) as Vector2
			target.draw_arc(
				point + Vector2(0.0, 7.0 / zoom),
				5.5 / zoom,
				0.15,
				PI - 0.15,
				12,
				PORT_COLOR,
				1.5 / zoom
			)
	if should_draw_detail_nodes():
		_draw_detail_nodes(target)
	_finish_layer_draw("cities_ports", started_usec)


func _draw_selection_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if selected_type == "country":
		var records: Array = _country_lod_features.get(_current_lod, []) as Array
		for feature_variant: Variant in records:
			var feature: Dictionary = feature_variant as Dictionary
			if str(feature.get("country_id", "")) != selected_id:
				continue
			for polygon_variant: Variant in feature.get("polygons", []):
				var polygon: Dictionary = polygon_variant as Dictionary
				target.draw_polyline(
					polygon.get("outline", PackedVector2Array()) as PackedVector2Array,
					SELECT,
					3.2 / zoom,
					true
				)
	elif selected_type == "region":
		var macro: Dictionary = _dictionary_value(_macro_region_by_id, selected_id)
		for polygon_variant: Variant in _lod_polygons_for_macro(macro, _current_lod):
			var polygon: Dictionary = polygon_variant as Dictionary
			target.draw_polyline(
				polygon.get("outline", PackedVector2Array()) as PackedVector2Array,
				SELECT,
				3.4 / zoom,
				true
			)
	_finish_layer_draw("selection", started_usec)


func _draw_label_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	_add_perf_traversal("labels", _label_items.size())
	for item: Dictionary in _label_items:
		target.draw_string(
			_font,
			item.get("baseline", Vector2.ZERO) as Vector2,
			str(item.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			int(item.get("font_size", 12)),
			item.get("color", LABEL) as Color
		)
	_draw_v2_3_local_labels(target)
	_finish_layer_draw("labels", started_usec)


func _draw_hud_layer(target: PrototypeV2MapLayer) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if get_zoom_level() != "far":
		var origin := Vector2(target.size.x * 0.38, target.size.y - 48.0)
		target.draw_rect(
			Rect2(origin - Vector2(12.0, 18.0), Vector2(326.0, 34.0)),
			Color(0.025, 0.06, 0.07, 0.78)
		)
		target.draw_line(origin, origin + Vector2(34.0, 0.0), RAIL_DARK, 3.4, true)
		target.draw_line(origin, origin + Vector2(34.0, 0.0), RAIL_LIGHT, 1.0, true)
		target.draw_string(
			_font,
			origin + Vector2(40.0, 4.0),
			"铁路",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			LABEL_MUTED
		)
		target.draw_dashed_line(
			origin + Vector2(86.0, 0.0),
			origin + Vector2(120.0, 0.0),
			ROAD,
			1.0,
			4.0,
			true
		)
		target.draw_string(
			_font,
			origin + Vector2(126.0, 4.0),
			"陆路",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			LABEL_MUTED
		)
		target.draw_dashed_line(
			origin + Vector2(170.0, 0.0),
			origin + Vector2(206.0, 0.0),
			SHIPPING,
			1.5,
			9.0,
			true
		)
		target.draw_string(
			_font,
			origin + Vector2(212.0, 4.0),
			"航运",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			LABEL_MUTED
		)
	_finish_layer_draw("hud", started_usec)


func _draw_war_overlay(target: PrototypeV2MapLayer) -> void:
	_draw_indexed_polygon(
		target,
		_war_control_polygon,
		_war_control_triangles,
		Color(FRONT, 0.2)
	)
	target.draw_polyline(
		_war_front_points,
		Color(FRONT, 0.22),
		13.0 / zoom,
		true
	)
	target.draw_polyline(_war_front_points, FRONT, 4.0 / zoom, true)


func _draw_detail_nodes(target: PrototypeV2MapLayer) -> void:
	var institution_points: Dictionary = _world_point_dictionary("institutions")
	for record_index: int in _visible_institution_indices:
		var institution: Dictionary = _institutions[record_index] as Dictionary
		if not is_record_visible(institution) or not _detail_record_relevant(institution):
			continue
		var point: Vector2 = institution_points.get(
			str(institution.get("id", "")),
			Vector2.ZERO
		) as Vector2
		_draw_diamond(
			target,
			point,
			6.0 / zoom,
			SELECT if selected_type == "institution" and selected_id == str(institution.get("id", "")) else INSTITUTION
		)
	var organization_points: Dictionary = _world_point_dictionary("organizations")
	for record_index: int in _visible_organization_indices:
		var organization: Dictionary = _organizations[record_index] as Dictionary
		if not is_record_visible(organization) or not _detail_record_relevant(organization):
			continue
		var point: Vector2 = organization_points.get(
			str(organization.get("id", "")),
			Vector2.ZERO
		) as Vector2
		var selected: bool = (
			selected_type == "organization"
			and selected_id == str(organization.get("id", ""))
		)
		target.draw_circle(point, 5.5 / zoom, SELECT if selected else ORGANIZATION)
		target.draw_circle(point, 2.2 / zoom, Color("#1c3430"))


func _refresh_visible_scene(redraw_geometry: bool, rebuild_labels: bool) -> void:
	_current_lod = get_lod_bucket()
	if _current_lod in ["lod3", "lod4"]:
		_ensure_detail_geometry_loaded(_current_lod)
	var world_rect: Rect2 = _world_view_rect()
	var prefetch: float = maxf(4.0, maxf(world_rect.size.x, world_rect.size.y) * 0.28)
	var query_rect: Rect2 = world_rect.grow(prefetch)
	_query_visible_index(
		_country_spatial_indexes.get(_current_lod) as PrototypeV2SpatialIndex,
		query_rect,
		_country_lod_features.get(_current_lod, []) as Array,
		_visible_country_indices
	)
	if _current_lod in ["lod3", "lod4"]:
		_query_visible_index(
			_administrative_spatial_indexes.get(_current_lod) as PrototypeV2SpatialIndex,
			query_rect,
			_administrative_lod_records.get(_current_lod, []) as Array,
			_visible_administrative_indices
		)
		_query_visible_index(
			_macro_spatial_index,
			query_rect,
			_macro_region_records,
			_visible_macro_indices
		)
	else:
		_visible_administrative_indices.clear()
		_visible_macro_indices.clear()
	_query_visible_points(_city_spatial_index, query_rect, _visible_city_indices)
	_query_visible_points(_port_spatial_index, query_rect, _visible_port_indices)
	_query_visible_points(
		_institution_spatial_index,
		query_rect,
		_visible_institution_indices
	)
	_query_visible_points(
		_organization_spatial_index,
		query_rect,
		_visible_organization_indices
	)
	_query_visible_index(
		_rail_spatial_index,
		query_rect,
		_rail_world_records,
		_visible_rail_indices
	)
	_query_visible_index(
		_road_spatial_index,
		query_rect,
		_road_world_records,
		_visible_road_indices
	)
	_query_visible_index(
		_shipping_spatial_index,
		query_rect,
		_shipping_world_records,
		_visible_shipping_indices
	)
	_query_v2_3_local_locations(query_rect)
	_visible_cache_pan = pan
	_visible_cache_zoom = zoom
	_perf_visible_queries += 1
	_dirty_flags["camera_dirty"] = false
	_dirty_flags["zoom_bucket_dirty"] = false
	if redraw_geometry:
		_dirty_flags["geometry_layer_dirty"] = true
		for layer: PrototypeV2MapLayer in [
			_country_layer,
			_region_layer,
			_administrative_layer,
			_transport_layer,
			_node_layer,
			_selection_layer,
			_hud_layer,
		]:
			_request_layer_redraw(layer)
	if rebuild_labels:
		_rebuild_label_cache()
	_dirty_flags["geometry_layer_dirty"] = false
	_dirty_flags["selection_dirty"] = false
	_dirty_flags["overlay_dirty"] = false


func _rebuild_v2_3_local_catalog(catalog_revision: int) -> void:
	_v2_3_local_location_points.clear()
	_v2_3_local_spatial_index.configure(WORLD_BOUNDS, 24.0, _v2_3_local_locations.size())
	for index: int in range(_v2_3_local_locations.size()):
		var location: Dictionary = _v2_3_local_locations[index] as Dictionary
		var location_id: String = str(location.get("location_id", ""))
		if location_id.is_empty():
			continue
		var point: Vector2 = project_lon_lat(location.get("world_position", []))
		_v2_3_local_location_points[location_id] = point
		_v2_3_local_spatial_index.insert(
			index, Rect2(point - Vector2.ONE * 0.05, Vector2.ONE * 0.1)
		)
	_v2_3_local_catalog_revision = catalog_revision
	_perf_v2_3_catalog_rebuilds += 1


func _query_v2_3_local_locations(query_rect: Rect2) -> void:
	if _v2_3_local_overlay.is_empty() or _v2_3_local_locations.is_empty():
		_visible_v2_3_local_indices.clear()
		return
	_v2_3_local_spatial_index.query(query_rect, _visible_v2_3_local_indices)


func _v2_3_local_overlay_visible() -> bool:
	return not _v2_3_local_overlay.is_empty() and zoom >= 48.0


func _draw_v2_3_local_transport(target: PrototypeV2MapLayer) -> void:
	if not _v2_3_local_overlay_visible():
		return
	var edges: Array = _v2_3_local_overlay.get("edges", []) as Array
	_add_perf_traversal("v2_3_local_edges", edges.size())
	for raw_edge: Variant in edges:
		if not raw_edge is Dictionary:
			continue
		var edge: Dictionary = raw_edge as Dictionary
		if not bool(edge.get("visible", false)):
			continue
		_draw_v2_3_route_segment(
			target, edge, Color(0.54, 0.58, 0.53, 0.44), 1.1
		)
	for raw_segment: Variant in (
		_v2_3_local_overlay.get("preview_route_segments", []) as Array
	):
		if raw_segment is Dictionary:
			_draw_v2_3_route_segment(
				target, raw_segment as Dictionary, Color("#63a9d8"), 2.5
			)
	for raw_segment: Variant in (
		_v2_3_local_overlay.get("active_route_segments", []) as Array
	):
		if raw_segment is Dictionary:
			_draw_v2_3_route_segment(
				target, raw_segment as Dictionary, Color("#d9b85c"), 3.2
			)


func _draw_v2_3_route_segment(
	target: PrototypeV2MapLayer,
	segment: Dictionary,
	color: Color,
	width_pixels: float
) -> void:
	var from_id: String = str(segment.get("from_location_id", ""))
	var to_id: String = str(segment.get("to_location_id", ""))
	if (from_id.is_empty() or to_id.is_empty()) and segment.has("edge_id"):
		var edge: Dictionary = _v2_3_local_edge_lookup.get(
			str(segment.get("edge_id", "")), {}
		) as Dictionary
		from_id = str(edge.get("from_location_id", ""))
		to_id = str(edge.get("to_location_id", ""))
	if (
		not _v2_3_local_location_points.has(from_id)
		or not _v2_3_local_location_points.has(to_id)
	):
		return
	target.draw_line(
		_v2_3_local_location_points[from_id] as Vector2,
		_v2_3_local_location_points[to_id] as Vector2,
		color,
		width_pixels / zoom,
		true
	)


func _draw_v2_3_local_nodes(target: PrototypeV2MapLayer) -> void:
	if not _v2_3_local_overlay_visible():
		return
	_add_perf_traversal("v2_3_local_locations", _visible_v2_3_local_indices.size())
	for index: int in _visible_v2_3_local_indices:
		if index < 0 or index >= _v2_3_local_locations.size():
			continue
		var location: Dictionary = _v2_3_local_locations[index] as Dictionary
		if not bool(location.get("visible", false)):
			continue
		var location_id: String = str(location.get("location_id", ""))
		var point: Vector2 = _v2_3_local_location_points.get(
			location_id, Vector2.ZERO
		) as Vector2
		target.draw_circle(point, 5.0 / zoom, Color("#d9c77a"))
		target.draw_circle(point, 2.2 / zoom, Color("#273c38"))
	var observer_id: String = str(_v2_3_local_overlay.get("observer_id", ""))
	for raw_position: Variant in (
		_v2_3_local_overlay.get("person_positions", []) as Array
	):
		if not raw_position is Dictionary:
			continue
		var position: Dictionary = raw_position as Dictionary
		if not bool(position.get("visible", false)):
			continue
		var point: Vector2 = _v2_3_person_world_point(position)
		if point == Vector2.INF:
			continue
		var selected: bool = str(position.get("person_id", "")) == observer_id
		target.draw_circle(
			point,
			(6.4 if selected else 4.2) / zoom,
			Color("#e8c55e") if selected else Color("#82a7a0")
		)
		target.draw_circle(point, 1.8 / zoom, Color("#172b2b"))


func _v2_3_person_world_point(position: Dictionary) -> Vector2:
	var location_id: String = str(position.get("current_location_id", ""))
	var point: Vector2 = _v2_3_local_location_points.get(
		location_id, Vector2.INF
	) as Vector2
	if str(position.get("location_state", "")) != "in_transit":
		return point
	var edge: Dictionary = _v2_3_local_edge_lookup.get(
		str(position.get("current_edge_id", "")), {}
	) as Dictionary
	if edge.is_empty():
		return point
	var from_point: Vector2 = _v2_3_local_location_points.get(
		str(edge.get("from_location_id", "")), point
	) as Vector2
	var to_point: Vector2 = _v2_3_local_location_points.get(
		str(edge.get("to_location_id", "")), point
	) as Vector2
	return from_point.lerp(to_point, float(position.get("segment_progress", 0.5)))


func _draw_v2_3_local_labels(target: PrototypeV2MapLayer) -> void:
	if not _v2_3_local_overlay_visible() or _font == null:
		return
	var accepted: Array[Rect2] = []
	for index: int in _visible_v2_3_local_indices:
		if index < 0 or index >= _v2_3_local_locations.size():
			continue
		var location: Dictionary = _v2_3_local_locations[index] as Dictionary
		if not bool(location.get("visible", false)):
			continue
		var label: String = str(location.get("display_name", ""))
		if label.is_empty():
			continue
		var point: Vector2 = (
			_v2_3_local_location_points.get(
				str(location.get("location_id", "")), Vector2.ZERO
			) as Vector2
		) * zoom + pan
		if not Rect2(Vector2.ZERO, size).grow(-8.0).has_point(point):
			continue
		var text_size: Vector2 = _font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11
		)
		var rect := Rect2(point + Vector2(7.0, -13.0), text_size + Vector2(6.0, 4.0))
		var collides: bool = false
		for existing: Rect2 in accepted:
			if existing.intersects(rect):
				collides = true
				break
		if collides:
			continue
		accepted.append(rect)
		target.draw_rect(rect, Color(0.025, 0.06, 0.065, 0.82))
		target.draw_string(
			_font, rect.position + Vector2(3.0, 13.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("#e6dfc5")
		)


func _rebuild_label_cache() -> void:
	if _data == null or _font == null:
		return
	_label_items.clear()
	_label_rects.clear()
	_label_counts.clear()
	_label_layer.position = Vector2.ZERO
	_label_layer.scale = Vector2.ONE
	_label_cache_pan = pan
	_label_cache_zoom = zoom
	_label_cache_bucket = _current_lod
	_cache_selected_and_hovered_labels()
	_cache_country_labels()
	if _current_lod in ["lod3", "lod4"]:
		_cache_region_labels()
		_cache_administrative_labels()
	_cache_city_labels()
	if _current_lod != "lod0":
		_cache_transport_labels()
	if _current_lod == "lod0":
		for ocean_label: Dictionary in [
			{"point": Vector2(444.0, 270.0), "text": "大 西 洋"},
			{"point": Vector2(777.0, 340.0), "text": "印 度 洋"},
			{"point": Vector2(205.0, 265.0), "text": "太 平 洋"},
			{"point": Vector2(1040.0, 270.0), "text": "太 平 洋"},
		]:
			_try_cache_label(
				(ocean_label["point"] as Vector2) * zoom + pan,
				str(ocean_label["text"]),
				14,
				Color(LABEL_MUTED, 0.56),
				true
			)
	_label_cache_by_bucket[_current_lod] = {
		"pan": pan,
		"zoom": zoom,
		"item_count": _label_items.size(),
	}
	_perf_label_rebuilds += 1
	_dirty_flags["labels_dirty"] = false
	_request_layer_redraw(_label_layer)


func _cache_selected_and_hovered_labels() -> void:
	if not selected_id.is_empty():
		var record: Dictionary
		var category: String = ""
		match selected_type:
			"country":
				record = get_country(selected_id)
				category = "countries"
			"region":
				record = get_region(selected_id)
				category = "regions"
			"city":
				record = get_city(selected_id)
				category = "cities"
			"institution":
				record = get_institution(selected_id)
				category = "institutions"
			"organization":
				record = get_organization(selected_id)
				category = "organizations"
		var point: Vector2 = _world_point_for_record(category, selected_id)
		if not record.is_empty() and point != Vector2.ZERO:
			_try_cache_label(
				point * zoom + pan,
				str(record.get("display_name_zh", record.get("name", ""))),
				14,
				SELECT,
				true
			)
	if not hovered_country_id.is_empty() and hovered_country_id != selected_id:
		var country: Dictionary = get_country(hovered_country_id)
		var point: Vector2 = _world_point_for_record("countries", hovered_country_id)
		_try_cache_label(
			point * zoom + pan,
			str(country.get("display_name_zh", country.get("name", ""))),
			14,
			SELECT,
			true
		)


func _cache_country_labels() -> void:
	var candidates: Array[int] = _visible_country_indices.duplicate()
	var records: Array = _country_lod_features.get(_current_lod, []) as Array
	candidates.sort_custom(func(first: int, second: int) -> bool:
		var first_feature: Dictionary = records[first] as Dictionary
		var second_feature: Dictionary = records[second] as Dictionary
		return _record_priority(get_country(str(first_feature.get("country_id", "")))) > _record_priority(get_country(str(second_feature.get("country_id", ""))))
	)
	var seen_country_ids: Dictionary = {}
	for feature_index: int in candidates:
		var feature: Dictionary = records[feature_index] as Dictionary
		var country_id: String = str(feature.get("country_id", ""))
		if country_id.is_empty() or seen_country_ids.has(country_id):
			continue
		seen_country_ids[country_id] = true
		var country: Dictionary = get_country(country_id)
		if (
			_current_lod == "lod0"
			and bool(country.get("theme_label_placeholder", true))
			and country_id not in [FOCUS_COUNTRY_ID, hovered_country_id]
		):
			continue
		if not is_record_visible(country) or country_id in [selected_id, hovered_country_id]:
			continue
		if _current_lod in ["lod3", "lod4"] and country_id != FOCUS_COUNTRY_ID:
			continue
		var color: Color = LABEL
		if _current_lod in ["lod3", "lod4"] and country_id != FOCUS_COUNTRY_ID:
			color = Color(LABEL_MUTED, 0.34)
		_try_cache_label(
			_world_point_for_record("countries", country_id) * zoom + pan,
			str(country.get("display_name_zh", country.get("name", ""))),
			15,
			color,
			true,
			"country"
		)


func _cache_region_labels() -> void:
	var candidates: Array[int] = _visible_macro_indices.duplicate()
	candidates.sort_custom(func(first: int, second: int) -> bool:
		var first_region: Dictionary = get_region(str((_macro_region_records[first] as Dictionary).get("region_id", "")))
		var second_region: Dictionary = get_region(str((_macro_region_records[second] as Dictionary).get("region_id", "")))
		return _record_priority(first_region) > _record_priority(second_region)
	)
	for record_index: int in candidates:
		var cache_record: Dictionary = _macro_region_records[record_index] as Dictionary
		var region_id: String = str(cache_record.get("region_id", ""))
		var region: Dictionary = get_region(region_id)
		if region_id == selected_id or not is_record_visible(region):
			continue
		_try_cache_label(
			_world_point_for_record("regions", region_id) * zoom + pan,
			str(region.get("display_name_zh", region.get("name", ""))),
			13,
			LABEL,
			true,
			"region"
		)


func _cache_administrative_labels() -> void:
	var candidates: Array[int] = _visible_administrative_indices.duplicate()
	candidates.sort_custom(func(first: int, second: int) -> bool:
		return _record_priority(_administrative_units[first] as Dictionary) > _record_priority(_administrative_units[second] as Dictionary)
	)
	for record_index: int in candidates:
		var unit: Dictionary = _administrative_units[record_index] as Dictionary
		if not is_record_visible(unit):
			continue
		var unit_id: String = str(unit.get("stable_id", unit.get("id", "")))
		_try_cache_label(
			_world_point_for_record("administrative_units", unit_id) * zoom + pan,
			str(unit.get("display_name_zh", unit.get("name", ""))),
			10,
			ADMINISTRATIVE_LABEL,
			true,
			"administrative"
		)


func _cache_city_labels() -> void:
	var candidates: Array[int] = _visible_city_indices.duplicate()
	candidates.sort_custom(func(first: int, second: int) -> bool:
		return _record_priority(_cities[first] as Dictionary) > _record_priority(_cities[second] as Dictionary)
	)
	for record_index: int in candidates:
		var city: Dictionary = _cities[record_index] as Dictionary
		var city_id: String = str(city.get("id", ""))
		if not is_record_visible(city) or not _city_node_visible_for_level(
			city,
			get_zoom_level()
		):
			continue
		if selected_type == "city" and selected_id == city_id:
			continue
		var point: Vector2 = _world_point_for_record("cities", city_id) * zoom + pan
		var color: Color = SELECT if city_id == PLAYER_CITY_ID else LABEL
		_try_cache_label(
			point + Vector2(8.0, 3.0),
			str(city.get("name", "")),
			12 if city_id == PLAYER_CITY_ID else 11,
			color,
			false,
			"city"
		)


func _cache_transport_labels() -> void:
	for record_index: int in _visible_rail_indices:
		var segment: Dictionary = _rail_segments[record_index] as Dictionary
		if not bool(segment.get("main", false)) or not _rail_visible_for_current_lod(segment):
			continue
		var cache_record: Dictionary = _rail_world_records[record_index] as Dictionary
		var midpoint: Vector2 = (
			(cache_record.get("start", Vector2.ZERO) as Vector2)
			+ (cache_record.get("end", Vector2.ZERO) as Vector2)
		) * 0.5
		_try_cache_label(
			midpoint * zoom + pan + Vector2(0.0, -5.0),
			str(segment.get("name", "")),
			9,
			Color(RAIL_LIGHT, 0.62),
			true,
			"transport"
		)


func _try_cache_label(
	position: Vector2,
	value: String,
	font_size: int,
	color: Color,
	centered: bool,
	category: String = ""
) -> bool:
	if value.is_empty():
		return false
	if (
		not category.is_empty()
		and int(_label_counts.get(category, 0)) >= get_label_budget(category)
	):
		return false
	var size_key := "%s|%d" % [value, font_size]
	var text_size: Vector2 = _text_size_cache.get(size_key, Vector2.ZERO) as Vector2
	if text_size == Vector2.ZERO:
		text_size = _font.get_string_size(
			value,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		)
		_text_size_cache[size_key] = text_size
	var top_left := Vector2(
		position.x - text_size.x * 0.5 if centered else position.x,
		position.y - text_size.y * 0.72
	)
	var rect := Rect2(
		top_left - Vector2(7.0, 4.0),
		text_size + Vector2(14.0, 8.0)
	)
	if (
		rect.end.x < 0.0
		or rect.position.x > size.x
		or rect.end.y < 0.0
		or rect.position.y > size.y
	):
		return false
	for existing: Rect2 in _label_rects:
		if existing.intersects(rect):
			return false
	_label_rects.append(rect)
	if not category.is_empty():
		_label_counts[category] = int(_label_counts.get(category, 0)) + 1
	_label_items.append({
		"baseline": top_left + Vector2(0.0, text_size.y * 0.78),
		"text": value,
		"font_size": font_size,
		"color": color,
	})
	return true


func _build_indexes() -> void:
	_country_by_id.clear()
	_country_by_iso.clear()
	_features_by_iso.clear()
	_region_by_id.clear()
	_administrative_unit_by_id.clear()
	_city_by_id.clear()
	_port_by_id.clear()
	_institution_by_id.clear()
	_organization_by_id.clear()
	_country_index_by_id.clear()
	_region_index_by_id.clear()
	_administrative_index_by_id.clear()
	_city_index_by_id.clear()
	_port_index_by_id.clear()
	_institution_index_by_id.clear()
	_organization_index_by_id.clear()
	_organizations.clear()
	for feature_variant: Variant in _coastlines:
		var feature: Dictionary = feature_variant as Dictionary
		_features_by_iso[str(feature.get("iso_a3", ""))] = feature
	for index: int in range(_countries.size()):
		var country: Dictionary = _countries[index] as Dictionary
		var country_id: String = str(country.get("id", ""))
		_country_by_id[country_id] = country
		_country_index_by_id[country_id] = index
		for iso_variant: Variant in country.get("geometry_iso_a3", []):
			_country_by_iso[str(iso_variant)] = country
	for index: int in range(_regions.size()):
		var region: Dictionary = _regions[index] as Dictionary
		var region_id: String = str(region.get("id", ""))
		_region_by_id[region_id] = region
		_region_index_by_id[region_id] = index
	for index: int in range(_administrative_units.size()):
		var unit: Dictionary = _administrative_units[index] as Dictionary
		var unit_id: String = str(unit.get("stable_id", unit.get("id", "")))
		_administrative_unit_by_id[unit_id] = unit
		_administrative_index_by_id[unit_id] = index
	for index: int in range(_cities.size()):
		var city: Dictionary = _cities[index] as Dictionary
		var city_id: String = str(city.get("id", ""))
		_city_by_id[city_id] = city
		_city_index_by_id[city_id] = index
	for index: int in range(_ports.size()):
		var port: Dictionary = _ports[index] as Dictionary
		var port_id: String = str(port.get("id", ""))
		_port_by_id[port_id] = port
		_port_index_by_id[port_id] = index
	for index: int in range(_institutions.size()):
		var institution: Dictionary = _institutions[index] as Dictionary
		var institution_id: String = str(institution.get("id", ""))
		_institution_by_id[institution_id] = institution
		_institution_index_by_id[institution_id] = index
	for organization_variant: Variant in _data.get_document("organizations").get("catalog", []):
		var organization: Dictionary = organization_variant as Dictionary
		var organization_id: String = str(organization.get("id", ""))
		_organization_by_id[organization_id] = organization
		if organization.has("lon_lat"):
			_organization_index_by_id[organization_id] = _organizations.size()
			_organizations.append(organization)


func _load_fixed_geometry_cache() -> void:
	_country_lod_features.clear()
	var country_lods: Dictionary = _geometry_cache.get("country_lods", {}) as Dictionary
	for lod_id_variant: Variant in country_lods.keys():
		var lod_id: String = str(lod_id_variant)
		var records: Array = []
		for record_variant: Variant in country_lods.get(lod_id, []):
			var source_record: Dictionary = record_variant as Dictionary
			var record: Dictionary = source_record.duplicate()
			record["bounds_rect"] = _array_to_rect(source_record.get("bounds", []))
			record["polygons"] = _convert_cached_polygons(
				source_record.get("polygons", []) as Array
			)
			records.append(record)
		_country_lod_features[lod_id] = records
	_administrative_lod_records.clear()
	_administrative_spatial_indexes.clear()
	_macro_region_records.clear()
	_macro_region_by_id.clear()
	_world_points.clear()
	for category_variant: Variant in (
		_geometry_cache.get("anchors", {}) as Dictionary
	).keys():
		var category: String = str(category_variant)
		var converted: Dictionary = {}
		var source_points: Dictionary = (
			_geometry_cache.get("anchors", {}) as Dictionary
		).get(category, {}) as Dictionary
		for id_variant: Variant in source_points.keys():
			converted[str(id_variant)] = _array_to_vector(source_points[id_variant])
		_world_points[category] = converted
	_rail_world_records = _convert_transport_records(
		(_geometry_cache.get("transport", {}) as Dictionary).get("rail", []) as Array
	)
	_road_world_records = _convert_transport_records(
		(_geometry_cache.get("transport", {}) as Dictionary).get("road", []) as Array
	)
	_shipping_world_records = _convert_transport_records(
		(_geometry_cache.get("transport", {}) as Dictionary).get("shipping", []) as Array
	)
	_graticule_lines.clear()
	for points_variant: Variant in _geometry_cache.get("graticule", []):
		_graticule_lines.append(_array_to_packed_points(points_variant))
	var war_example: Dictionary = _geometry_cache.get(
		"war_example",
		{}
	) as Dictionary
	var control_polygon: Dictionary = war_example.get(
		"control_polygon",
		{}
	) as Dictionary
	_war_control_polygon = _array_to_packed_points(
		control_polygon.get("outer", [])
	)
	_war_control_triangles = _array_to_packed_ints(
		control_polygon.get("triangles", [])
	)
	_war_front_points = _array_to_packed_points(
		war_example.get("front_points", [])
	)


func _ensure_detail_geometry_loaded(lod_id: String) -> void:
	if lod_id not in ["lod3", "lod4"]:
		return
	if not _administrative_lod_records.has(lod_id):
		var source_lods: Dictionary = _geometry_cache.get(
			"administrative_lods",
			{}
		) as Dictionary
		var records: Array = []
		for record_variant: Variant in source_lods.get(lod_id, []):
			var source_record: Dictionary = record_variant as Dictionary
			var record: Dictionary = source_record.duplicate()
			record["bounds_rect"] = _array_to_rect(
				source_record.get("bounds", [])
			)
			record["polygons"] = _convert_cached_polygons(
				source_record.get("polygons", []) as Array
			)
			records.append(record)
		_administrative_lod_records[lod_id] = records
		var administrative_index := PrototypeV2SpatialIndex.new()
		administrative_index.configure(WORLD_BOUNDS, 6.0, records.size())
		for record_index: int in range(records.size()):
			administrative_index.insert(
				record_index,
				(records[record_index] as Dictionary).get(
					"bounds_rect",
					Rect2()
				) as Rect2
			)
		_administrative_spatial_indexes[lod_id] = administrative_index
	if _macro_region_records.is_empty():
		var source_macros: Array = _geometry_cache.get(
			"macro_regions",
			[]
		) as Array
		for record_variant: Variant in source_macros:
			var source_record: Dictionary = record_variant as Dictionary
			var record: Dictionary = source_record.duplicate()
			record["bounds_rect"] = _array_to_rect(
				source_record.get("bounds", [])
			)
			record["lods"] = {}
			var region_id: String = str(record.get("region_id", ""))
			_macro_region_by_id[region_id] = record
			_macro_region_records.append(record)
		_macro_spatial_index.configure(
			WORLD_BOUNDS,
			8.0,
			_macro_region_records.size()
		)
		for record_index: int in range(_macro_region_records.size()):
			_macro_spatial_index.insert(
				record_index,
				(_macro_region_records[record_index] as Dictionary).get(
					"bounds_rect",
					Rect2()
				) as Rect2
			)
	var source_macros: Array = _geometry_cache.get(
		"macro_regions",
		[]
	) as Array
	for record_index: int in range(_macro_region_records.size()):
		var record: Dictionary = _macro_region_records[record_index] as Dictionary
		var converted_lods: Dictionary = record.get("lods", {}) as Dictionary
		if converted_lods.has(lod_id):
			continue
		var source_record: Dictionary = source_macros[record_index] as Dictionary
		converted_lods[lod_id] = _convert_cached_polygons(
			(source_record.get("lods", {}) as Dictionary).get(
				lod_id,
				[]
			) as Array
		)
		record["lods"] = converted_lods


func _convert_cached_polygons(source: Array) -> Array:
	var result: Array = []
	for polygon_variant: Variant in source:
		var source_polygon: Dictionary = polygon_variant as Dictionary
		var outer: PackedVector2Array = _array_to_packed_points(
			source_polygon.get("outer", [])
		)
		var holes: Array = []
		for hole_variant: Variant in source_polygon.get("holes", []):
			var source_hole: Dictionary = hole_variant as Dictionary
			var hole_outer: PackedVector2Array = _array_to_packed_points(
				source_hole.get("outer", [])
			)
			holes.append({
				"outer": hole_outer,
				"outline": _closed_polygon(hole_outer),
				"triangles": _array_to_packed_ints(
					source_hole.get("triangles", [])
				),
			})
		result.append({
			"outer": outer,
			"outline": _closed_polygon(outer),
			"holes": holes,
			"triangles": _array_to_packed_ints(source_polygon.get("triangles", [])),
		})
	return result


func _convert_transport_records(source: Array) -> Array:
	var result: Array = []
	for record_variant: Variant in source:
		var source_record: Dictionary = record_variant as Dictionary
		var record: Dictionary = source_record.duplicate()
		record["bounds_rect"] = _array_to_rect(source_record.get("bounds", []))
		if source_record.has("start"):
			record["start"] = _array_to_vector(source_record.get("start", []))
			record["end"] = _array_to_vector(source_record.get("end", []))
		if source_record.has("points"):
			record["points"] = _array_to_packed_points(source_record.get("points", []))
		result.append(record)
	return result


func _build_spatial_indexes() -> void:
	_country_spatial_indexes.clear()
	for lod_id_variant: Variant in _country_lod_features.keys():
		var lod_id: String = str(lod_id_variant)
		var records: Array = _country_lod_features[lod_id] as Array
		var index := PrototypeV2SpatialIndex.new()
		index.configure(WORLD_BOUNDS, 45.0, records.size())
		for record_index: int in range(records.size()):
			index.insert(
				record_index,
				(records[record_index] as Dictionary).get("bounds_rect", Rect2()) as Rect2
			)
		_country_spatial_indexes[lod_id] = index
	_administrative_spatial_indexes.clear()
	_build_point_spatial_index(_city_spatial_index, _cities, "cities", 0.4)
	_build_point_spatial_index(_port_spatial_index, _ports, "ports", 0.4)
	_build_point_spatial_index(
		_institution_spatial_index,
		_institutions,
		"institutions",
		0.3
	)
	_build_point_spatial_index(
		_organization_spatial_index,
		_organizations,
		"organizations",
		0.3
	)
	_build_record_spatial_index(_rail_spatial_index, _rail_world_records, 8.0)
	_build_record_spatial_index(_road_spatial_index, _road_world_records, 8.0)
	_build_record_spatial_index(
		_shipping_spatial_index,
		_shipping_world_records,
		20.0
	)


func _build_point_spatial_index(
	index: PrototypeV2SpatialIndex,
	records: Array,
	category: String,
	radius: float
) -> void:
	index.configure(WORLD_BOUNDS, 8.0, records.size())
	var points: Dictionary = _world_point_dictionary(category)
	for record_index: int in range(records.size()):
		var record: Dictionary = records[record_index] as Dictionary
		var point: Vector2 = points.get(str(record.get("id", "")), Vector2.ZERO) as Vector2
		index.insert(
			record_index,
			Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		)


func _build_record_spatial_index(
	index: PrototypeV2SpatialIndex,
	records: Array,
	cell_size: float
) -> void:
	index.configure(WORLD_BOUNDS, cell_size, records.size())
	for record_index: int in range(records.size()):
		index.insert(
			record_index,
			(records[record_index] as Dictionary).get("bounds_rect", Rect2()) as Rect2
		)


func _build_transport_tie_cache() -> void:
	_rail_ties_by_lod.clear()
	var representative_zoom := {
		"lod0": 1.0,
		"lod1": 3.8,
		"lod2": 9.0,
		"lod3": 24.0,
		"lod4": 72.0,
	}
	for lod_id_variant: Variant in representative_zoom.keys():
		var lod_id: String = str(lod_id_variant)
		var lod_zoom: float = float(representative_zoom[lod_id])
		var ties_by_segment: Array = []
		for record_variant: Variant in _rail_world_records:
			var record: Dictionary = record_variant as Dictionary
			var start: Vector2 = record.get("start", Vector2.ZERO) as Vector2
			var end: Vector2 = record.get("end", Vector2.ZERO) as Vector2
			var distance: float = start.distance_to(end)
			var direction: Vector2 = (end - start).normalized()
			var normal := Vector2(-direction.y, direction.x) * (3.5 / lod_zoom)
			var step: float = 13.0 / lod_zoom
			var cursor: float = 8.0 / lod_zoom
			var points := PackedVector2Array()
			while cursor < distance:
				var center: Vector2 = start + direction * cursor
				points.append(center - normal)
				points.append(center + normal)
				cursor += step
			ties_by_segment.append(points)
		_rail_ties_by_lod[lod_id] = ties_by_segment
	_perf_transport_rebuilds += 1


func _query_visible_index(
	index: PrototypeV2SpatialIndex,
	query_rect: Rect2,
	records: Array,
	output: Array[int]
) -> void:
	if index == null:
		output.clear()
		return
	index.query(query_rect, output)
	var write_index: int = 0
	for read_index: int in range(output.size()):
		var record_index: int = output[read_index]
		if record_index < 0 or record_index >= records.size():
			continue
		var record: Dictionary = records[record_index] as Dictionary
		if not (record.get("bounds_rect", Rect2()) as Rect2).intersects(query_rect):
			continue
		output[write_index] = record_index
		write_index += 1
	output.resize(write_index)


func _query_visible_points(
	index: PrototypeV2SpatialIndex,
	query_rect: Rect2,
	output: Array[int]
) -> void:
	index.query(query_rect, output)


func _country_id_at_world_point(world_position: Vector2) -> String:
	var index: PrototypeV2SpatialIndex = _country_spatial_indexes.get(
		_current_lod
	) as PrototypeV2SpatialIndex
	if index == null:
		return ""
	index.query_point(world_position, _point_query_scratch)
	_perf_click_candidates += _point_query_scratch.size()
	var records: Array = _country_lod_features.get(_current_lod, []) as Array
	for record_index: int in _point_query_scratch:
		var feature: Dictionary = records[record_index] as Dictionary
		for polygon_variant: Variant in feature.get("polygons", []):
			var polygon: Dictionary = polygon_variant as Dictionary
			if Geometry2D.is_point_in_polygon(
				world_position,
				polygon.get("outer", PackedVector2Array()) as PackedVector2Array
			):
				return str(feature.get("country_id", ""))
	return ""


func _node_at_index(
	world_position: Vector2,
	records: Array,
	points: Dictionary,
	index: PrototypeV2SpatialIndex,
	object_type: String,
	radius_pixels: float
) -> Dictionary:
	index.query_point(world_position, _point_query_scratch)
	_perf_click_candidates += _point_query_scratch.size()
	for record_index: int in _point_query_scratch:
		var record: Dictionary = records[record_index] as Dictionary
		if not is_record_visible(record):
			continue
		var point: Vector2 = points.get(
			str(record.get("id", "")),
			Vector2.ZERO
		) as Vector2
		if world_position.distance_to(point) <= radius_pixels / zoom:
			return {
				"type": object_type,
				"id": str(record.get("id", "")),
				"data": record,
			}
	return {}


func _set_view(center_world: Vector2, next_zoom: float, screen_anchor: Vector2) -> void:
	zoom = clampf(
		next_zoom,
		float((_modes.get("zoom", {}) as Dictionary).get("minimum", 0.82)),
		get_maximum_zoom()
	)
	pan = screen_anchor - center_world * zoom
	_clamp_pan()
	_current_lod = get_lod_bucket()
	_dirty_flags["camera_dirty"] = true
	_dirty_flags["zoom_bucket_dirty"] = true
	_apply_camera_transform()
	_refresh_visible_scene(true, true)


func _apply_camera_transform() -> void:
	for layer: PrototypeV2MapLayer in _world_layers:
		layer.position = pan
		layer.scale = Vector2.ONE * zoom
	if is_equal_approx(_label_cache_zoom, zoom):
		_label_layer.position = pan - _label_cache_pan
		_label_layer.scale = Vector2.ONE
	_perf_camera_transform_updates += 1


func _apply_temporary_label_zoom(anchor: Vector2) -> void:
	if _label_cache_zoom <= 0.0:
		return
	var ratio: float = zoom / _label_cache_zoom
	var cached_anchor_screen: Vector2 = (
		(anchor - pan) / zoom * _label_cache_zoom
		+ _label_cache_pan
	)
	_label_layer.scale = Vector2.ONE * ratio
	_label_layer.position = anchor - cached_anchor_screen * ratio


func _camera_exceeded_refresh_threshold() -> bool:
	if _visible_cache_zoom <= 0.0 or not is_finite(_visible_cache_pan.x):
		return true
	return (
		pan.distance_to(_visible_cache_pan) >= CAMERA_REFRESH_THRESHOLD_PIXELS
		or absf(zoom - _visible_cache_zoom) / maxf(_visible_cache_zoom, 0.001) >= 0.12
	)


func _world_view_rect() -> Rect2:
	return Rect2(-pan / zoom, size / zoom)


func _clamp_pan() -> void:
	var scaled: Vector2 = WORLD_SIZE * zoom
	var required_visible := Vector2(180.0, 135.0)
	if scaled.x + required_visible.x * 2.0 <= size.x:
		pan.x = (size.x - scaled.x) * 0.5
	else:
		pan.x = clampf(
			pan.x,
			required_visible.x - scaled.x,
			size.x - required_visible.x
		)
	if scaled.y + required_visible.y * 2.0 <= size.y:
		pan.y = (size.y - scaled.y) * 0.5
	else:
		pan.y = clampf(
			pan.y,
			required_visible.y - scaled.y,
			size.y - required_visible.y
		)


func _map_anchor() -> Vector2:
	return Vector2(
		size.x * 0.52 if size.x > 0.0 else 650.0,
		size.y * 0.5 if size.y > 0.0 else 360.0
	)


func _request_layer_redraw(layer: PrototypeV2MapLayer) -> void:
	if layer == null:
		return
	_perf_queue_redraw_calls += 1
	_perf_layer_redraws[layer.layer_id] = int(
		_perf_layer_redraws.get(layer.layer_id, 0)
	) + 1
	layer.request_redraw()


func _finish_layer_draw(layer_id: String, started_usec: int) -> void:
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	_perf_draw_calls += 1
	_perf_draw_ms_samples.append(float(elapsed_usec) / 1000.0)
	_record_perf_hotspot_usec("draw_%s" % layer_id, elapsed_usec)


func _record_perf_hotspot_usec(metric_id: String, elapsed_usec: int) -> void:
	var metric: Dictionary = _perf_hotspots.get(metric_id, {
		"calls": 0,
		"total_usec": 0,
		"max_usec": 0,
	}) as Dictionary
	metric["calls"] = int(metric.get("calls", 0)) + 1
	metric["total_usec"] = int(metric.get("total_usec", 0)) + elapsed_usec
	metric["max_usec"] = maxi(int(metric.get("max_usec", 0)), elapsed_usec)
	_perf_hotspots[metric_id] = metric


func _add_perf_traversal(metric_id: String, count: int) -> void:
	_perf_traversal_totals[metric_id] = int(
		_perf_traversal_totals.get(metric_id, 0)
	) + count


func _visible_counts() -> Dictionary:
	return {
		"countries": _visible_country_indices.size(),
		"administrative_units": _visible_administrative_indices.size(),
		"regions": _visible_macro_indices.size(),
		"cities": _visible_city_indices.size(),
		"ports": _visible_port_indices.size(),
		"institutions": _visible_institution_indices.size(),
		"organizations": _visible_organization_indices.size(),
		"rail": _visible_rail_indices.size(),
		"road": _visible_road_indices.size(),
		"shipping": _visible_shipping_indices.size(),
		"labels": _label_items.size(),
	}


func _all_layers() -> Array[PrototypeV2MapLayer]:
	return [
		_background_layer,
		_country_layer,
		_region_layer,
		_administrative_layer,
		_transport_layer,
		_node_layer,
		_selection_layer,
		_label_layer,
		_hud_layer,
	]


func _country_color(country: Dictionary, continent: String) -> Color:
	if country.is_empty():
		var color: Color = LAND_BASE
		match continent:
			"Africa":
				color = Color("#777d68")
			"Asia":
				color = Color("#747a68")
			"Europe":
				color = Color("#6e7d76")
			"North America":
				color = Color("#6e7c71")
			"South America":
				color = Color("#6f806e")
			"Oceania":
				color = Color("#7b806d")
		return Color(color, 0.94)
	var key: String = "legal_color"
	if current_mode == "market":
		key = "market_color"
	elif current_mode == "population":
		key = "population_color"
	elif current_mode == "war":
		key = "war_color"
	var fallback: String = str(country.get("neutral_land_color", "#738077"))
	return Color(Color(str(country.get(key, fallback))), 0.96)


func _rail_segments_for_level(level: String) -> Array[Dictionary]:
	if level == "far":
		return []
	var candidates: Array[Dictionary] = []
	for segment_variant: Variant in _rail_segments:
		var segment: Dictionary = segment_variant as Dictionary
		if level == get_zoom_level() and not is_record_visible(segment):
			continue
		if level == "middle" and not bool(segment.get("main", false)):
			continue
		candidates.append(segment)
	candidates.sort_custom(_record_higher_priority)
	var result: Array[Dictionary] = []
	var limit: int = get_label_budget("transport", level)
	for index: int in range(mini(limit, candidates.size())):
		result.append(candidates[index])
	return result


func _rail_visible_for_current_lod(segment: Dictionary) -> bool:
	if not is_record_visible(segment):
		return false
	return _current_lod != "lod1" or bool(segment.get("main", false))


func _city_node_visible_for_level(city: Dictionary, level: String) -> bool:
	if level != "middle":
		return true
	var city_id: String = str(city.get("id", ""))
	if str(city.get("parent_country_id", "")) != FOCUS_COUNTRY_ID:
		return int(city.get("label_priority", 0)) >= 84
	if city_id in ["paris", PLAYER_CITY_ID]:
		return true
	for segment: Dictionary in _rail_segments_for_level("middle"):
		if city_id in [
			str(segment.get("from_city_id", "")),
			str(segment.get("to_city_id", "")),
		]:
			return true
	return false


func _rail_is_selected(segment: Dictionary) -> bool:
	if selected_type == "city":
		return selected_id in [
			str(segment.get("from_city_id", "")),
			str(segment.get("to_city_id", "")),
		]
	if selected_type == "region":
		var first: Dictionary = get_city(str(segment.get("from_city_id", "")))
		var second: Dictionary = get_city(str(segment.get("to_city_id", "")))
		return selected_id in [
			str(first.get("parent_region_id", "")),
			str(second.get("parent_region_id", "")),
		]
	return false


func _detail_record_relevant(record: Dictionary) -> bool:
	match selected_type:
		"city":
			return str(record.get("city_id", "")) == selected_id
		"region":
			return str(record.get("parent_region_id", "")) == selected_id
		"institution":
			return (
				str(record.get("id", "")) == selected_id
				or str(record.get("institution_id", "")) == selected_id
			)
		"organization":
			return str(record.get("id", "")) == selected_id
	return false


func _draw_diamond(
	target: PrototypeV2MapLayer,
	center: Vector2,
	radius: float,
	color: Color
) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	_draw_indexed_polygon(
		target,
		points,
		PackedInt32Array([0, 1, 2, 0, 2, 3]),
		color
	)
	target.draw_polyline(_closed_polygon(points), Color("#2a3331"), 1.0 / zoom, true)


func _lod_polygons_for_macro(record: Dictionary, lod_id: String) -> Array:
	var lods: Dictionary = record.get("lods", {}) as Dictionary
	var resolved_lod: String = "lod4" if lod_id == "lod4" else "lod3"
	return lods.get(resolved_lod, []) as Array


func _world_point_dictionary(category: String) -> Dictionary:
	return _world_points.get(category, {}) as Dictionary


func _world_point_for_record(category: String, record_id: String) -> Vector2:
	return _world_point_dictionary(category).get(record_id, Vector2.ZERO) as Vector2


func _camera_focus_point(focus_id: String) -> Vector2:
	return _world_point_for_record("camera_focus", focus_id)


func _draw_indexed_polygon(
	target: PrototypeV2MapLayer,
	points: PackedVector2Array,
	indices: PackedInt32Array,
	color: Color
) -> void:
	if points.size() < 3 or indices.size() < 3:
		return
	RenderingServer.canvas_item_add_triangle_array(
		target.get_canvas_item(),
		indices,
		points,
		PackedColorArray([color])
	)


func _record_higher_priority(first: Dictionary, second: Dictionary) -> bool:
	return _record_priority(first) > _record_priority(second)


func _record_priority(record: Dictionary) -> int:
	if record.has("label_priority"):
		return int(record.get("label_priority", 0))
	return 70 if bool(record.get("main", false)) else 30


func _candidate_higher_priority(first_variant: Variant, second_variant: Variant) -> bool:
	return (
		int((first_variant as Dictionary).get("priority", 0))
		> int((second_variant as Dictionary).get("priority", 0))
	)


func _document_array(document_id: String, field: String) -> Array:
	return _data.get_document(document_id).get(field, []) as Array


func _dictionary_value(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _array_to_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _array_to_rect(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() < 4:
		return Rect2()
	var source: Array = value as Array
	return Rect2(
		float(source[0]),
		float(source[1]),
		float(source[2]),
		float(source[3])
	)


func _array_to_packed_points(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is Array:
		for point_variant: Variant in value as Array:
			result.append(_array_to_vector(point_variant))
	return result


func _array_to_packed_ints(value: Variant) -> PackedInt32Array:
	var result := PackedInt32Array()
	if value is Array:
		for index_variant: Variant in value as Array:
			result.append(int(index_variant))
	return result


func _closed_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if not result.is_empty() and result[0] != result[-1]:
		result.append(result[0])
	return result
