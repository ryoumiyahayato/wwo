extends Control

const WORLD: String = "world"
const REGION: String = "region"
const CITY: String = "city"
const WORLD_COUNTRIES: String = "countries"
const WORLD_COUNTRY_FOCUS: String = "country_focus"
const LAYOUT_FOCUS: int = 0
const LAYOUT_WORKSPACE: int = 1
const FOCUS_COUNTRY_ID: String = "country_fra"
const CAMERA_ORTHO_SIZE: float = 2.55
const EDGE_BAND: float = 58.0
const DRAG_THRESHOLD: float = 5.0
const MOTION_EPSILON: float = 0.0005
const FOCUS_VIEWPORT_SIZE: Vector2i = Vector2i(720, 600)
const WORKSPACE_VIEWPORT_SIZE: Vector2i = Vector2i(600, 520)

var layout_mode_id: int = LAYOUT_FOCUS
var workspace_open: bool = true
var space_level: String = WORLD
var world_mode: String = WORLD_COUNTRIES

var selected_country_id: String = ""
var selected_region_id: String = ""
var selected_city_id: String = ""
var selected_event_id: String = ""
var selected_institution_id: String = ""
var hover_country_id: String = ""
var hover_region_id: String = ""
var hover_event_id: String = ""

var info_open: bool = false
var info_progress: float = 0.0
var _info_tween: Tween
var active_hud_panel: String = ""
var active_character_key: String = "worker"

var yaw: float = -0.08
var tilt: float = -0.18
var angular_velocity: float = 0.0
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_last: Vector2 = Vector2.ZERO
var drag_moved: bool = false

var sim_paused: bool = true
var sim_speed: int = 1
var sim_day: int = 12
var sim_month: int = 3
var sim_year: int = 1900
var sim_hour: int = 8
var sim_minute: int = 0
var activity_unread: int = 2

var _countries: Array[Dictionary] = []
var _country_by_id: Dictionary = {}
var _country_unit_polygons: Dictionary = {}
var _country_anchor_units: Dictionary = {}
var _coastline_unit_lines: Array[PackedVector3Array] = []

var _regions: Array[Dictionary] = []
var _region_by_id: Dictionary = {}
var _region_polygons: Dictionary = {}
var _cities: Array[Dictionary] = []
var _city_by_id: Dictionary = {}
var _cities_by_region: Dictionary = {}
var _institutions: Array[Dictionary] = []
var _institution_by_id: Dictionary = {}
var _institutions_by_city: Dictionary = {}
var _institutions_by_region: Dictionary = {}
var _character_profiles: Dictionary = {}
var _country_profile: Dictionary = {}
var _world_events: Array[Dictionary] = []
var _event_by_id: Dictionary = {}
var _data_errors: Array[String] = []

var _button_hits: Array[Dictionary] = []
var _hemisphere_center: Vector2 = Vector2.ZERO
var _hemisphere_rect: Rect2 = Rect2()
var _hemisphere_radius: float = 220.0
var _focus_bounds: Rect2 = Rect2(Vector2(-5.5, 41.0), Vector2(12.5, 11.0))

var _projection_dirty: bool = true
var _global_screen_segments: Array[PackedVector2Array] = []
var _selected_country_segments: Array[PackedVector2Array] = []
var _country_screen_anchors: Dictionary = {}
var _event_screen_positions: Dictionary = {}
var _focus_country_screen_polygons: Array[PackedVector2Array] = []
var _focus_region_screen_polygons: Dictionary = {}
var _focus_region_screen_anchors: Dictionary = {}

@onready var viewport_container: SubViewportContainer = %HemisphereViewportContainer
@onready var viewport: SubViewport = %HemisphereViewport


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_all_data()
	_apply_layout()
	_set_world_layer_visible(true)
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var hover_spin: float = _edge_hover_spin()
	if absf(angular_velocity) > MOTION_EPSILON or absf(hover_spin) > MOTION_EPSILON:
		yaw += (angular_velocity + hover_spin) * delta
		angular_velocity = lerpf(angular_velocity, 0.0, minf(1.0, delta * 6.5))
		_mark_projection_dirty()
		queue_redraw()
		return
	angular_velocity = 0.0
	set_process(false)
	queue_redraw()


func _on_clock_timer_timeout() -> void:
	if sim_paused:
		return
	_advance_clock(15 * sim_speed)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F1:
		_set_layout(LAYOUT_FOCUS)
	elif key_event.keycode == KEY_F2:
		_set_layout(LAYOUT_WORKSPACE)
	elif key_event.keycode == KEY_ESCAPE:
		_go_back()
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var initial_button: InputEventMouseButton = event as InputEventMouseButton
		if initial_button.button_index == MOUSE_BUTTON_LEFT and initial_button.pressed:
			if _handle_button_click(initial_button.position):
				accept_event()
				return

	if space_level != WORLD:
		return

	if world_mode == WORLD_COUNTRY_FOCUS:
		if event is InputEventMouseMotion:
			var focus_motion: InputEventMouseMotion = event as InputEventMouseMotion
			if _position_hits_ui(focus_motion.position):
				return
			_select_focus_region_at(focus_motion.position, false)
		elif event is InputEventMouseButton:
			var focus_button: InputEventMouseButton = event as InputEventMouseButton
			if focus_button.button_index == MOUSE_BUTTON_LEFT and focus_button.pressed:
				if not _position_hits_ui(focus_button.position):
					_select_focus_region_at(focus_button.position, true)
				accept_event()
		return

	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed and _hemisphere_rect.has_point(mouse_button.position):
			dragging = true
			drag_start = mouse_button.position
			drag_last = mouse_button.position
			drag_moved = false
			angular_velocity = 0.0
			_start_motion()
			accept_event()
		elif not mouse_button.pressed and dragging:
			dragging = false
			if not drag_moved:
				_select_global_object_at(mouse_button.position, true)
			accept_event()
		return

	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		if not dragging and _position_hits_ui(mouse_motion.position):
			return
		if dragging:
			var motion_delta: Vector2 = mouse_motion.position - drag_last
			drag_last = mouse_motion.position
			if mouse_motion.position.distance_to(drag_start) > DRAG_THRESHOLD:
				drag_moved = true
			yaw += motion_delta.x * 0.006
			tilt = clampf(tilt + motion_delta.y * 0.0025, -0.62, 0.12)
			angular_velocity = motion_delta.x * 0.018
			_start_motion()
			_mark_projection_dirty()
			queue_redraw()
		elif _hemisphere_rect.has_point(mouse_motion.position):
			_select_global_object_at(mouse_motion.position, false)
			if absf(_edge_hover_spin()) > MOTION_EPSILON:
				_start_motion()
		else:
			_clear_global_hover()


func _draw() -> void:
	_button_hits.clear()
	if space_level == WORLD:
		_draw_world_overlay()
	elif space_level == REGION:
		_draw_region_map()
	else:
		_draw_city_map()
	_draw_corners()
	_draw_top_info()
	_draw_layout_switch()
	_draw_breadcrumbs()
	_draw_active_hud_panel()
	_draw_data_errors()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_layout()
		_set_world_layer_visible(space_level == WORLD)
		_mark_projection_dirty()
		queue_redraw()


func _load_all_data() -> void:
	var world_document: Dictionary = _read_document("res://data/world_map/world_coastlines.json")
	_load_countries_and_coastlines(world_document)

	var regions_document: Dictionary = _read_document("res://data/world_map/regions.json")
	_load_regions(regions_document)

	var cities_document: Dictionary = _read_document("res://data/world_map/cities.json")
	_cities = _dictionary_array(cities_document, "cities")
	for city: Dictionary in _cities:
		var city_id: String = str(city.get("id", ""))
		var region_id: String = str(city.get("parent_region_id", ""))
		_city_by_id[city_id] = city
		if not region_id.is_empty():
			var city_ids: Array = _cities_by_region.get(region_id, []) as Array
			city_ids.append(city_id)
			_cities_by_region[region_id] = city_ids

	var institutions_document: Dictionary = _read_document("res://data/world_map/institutions.json")
	_country_profile = institutions_document.get("country", {}) as Dictionary
	_institutions = _dictionary_array(institutions_document, "institutions")
	for institution: Dictionary in _institutions:
		var institution_id: String = str(institution.get("id", ""))
		var institution_city_id: String = str(institution.get("city_id", ""))
		var institution_region_id: String = str(institution.get("parent_region_id", ""))
		_institution_by_id[institution_id] = institution
		if not institution_city_id.is_empty():
			var city_institutions: Array = _institutions_by_city.get(institution_city_id, []) as Array
			city_institutions.append(institution_id)
			_institutions_by_city[institution_city_id] = city_institutions
		if not institution_region_id.is_empty():
			var region_institutions: Array = _institutions_by_region.get(institution_region_id, []) as Array
			region_institutions.append(institution_id)
			_institutions_by_region[institution_region_id] = region_institutions

	var characters_document: Dictionary = _read_document("res://data/world_map/characters.json")
	var identities: Dictionary = characters_document.get("identities", {}) as Dictionary
	for key_value: Variant in identities.keys():
		var key: String = str(key_value)
		var profile_value: Variant = identities.get(key, {})
		if profile_value is Dictionary:
			_character_profiles[key] = profile_value as Dictionary

	_seed_world_events()
	_focus_bounds = _lon_lat_bounds(_all_region_polygons())
	_mark_projection_dirty()


func _load_countries_and_coastlines(document: Dictionary) -> void:
	var features: Array = document.get("features", []) as Array
	for feature_value: Variant in features:
		if not feature_value is Dictionary:
			continue
		var feature: Dictionary = feature_value as Dictionary
		var iso: String = str(feature.get("iso_a3", feature.get("source_iso_a3", ""))).to_upper()
		var country_id: String = _country_id_from_feature(feature, iso)
		var unit_polygons: Array = []
		var largest_score: float = -1.0
		var largest_units: PackedVector3Array = PackedVector3Array()
		var polygons: Array = feature.get("polygons", []) as Array
		for polygon_value: Variant in polygons:
			if not polygon_value is Dictionary:
				continue
			var polygon: Dictionary = polygon_value as Dictionary
			var outer: PackedVector2Array = _points_from_raw(polygon.get("outer", []))
			if outer.size() < 3:
				continue
			var simplified: PackedVector2Array = _simplify_line(outer, 120)
			var unit_line: PackedVector3Array = _to_unit_line(simplified)
			unit_polygons.append(unit_line)
			_coastline_unit_lines.append(unit_line)
			var score: float = absf(_polygon_area_score(simplified))
			if score > largest_score:
				largest_score = score
				largest_units = unit_line
		if unit_polygons.is_empty():
			continue
		var display_name: String = str(feature.get("display_name_zh", feature.get("name", iso)))
		var record: Dictionary = {
			"id": country_id,
			"iso_a3": iso,
			"name": display_name,
			"native_name": str(feature.get("name", iso)),
			"label_rank": int(feature.get("label_rank", 9)),
		}
		_countries.append(record)
		_country_by_id[country_id] = record
		_country_unit_polygons[country_id] = unit_polygons
		_country_anchor_units[country_id] = _average_unit(largest_units)


func _load_regions(document: Dictionary) -> void:
	_regions = _dictionary_array(document, "regions")
	var administrative_by_id: Dictionary = {}
	var units: Array = document.get("administrative_units", []) as Array
	for unit_value: Variant in units:
		if unit_value is Dictionary:
			var unit: Dictionary = unit_value as Dictionary
			administrative_by_id[str(unit.get("id", ""))] = unit

	for region: Dictionary in _regions:
		var region_id: String = str(region.get("id", ""))
		_region_by_id[region_id] = region
		var region_polygons: Array = []
		var administrative_ids: Array = region.get("administrative_unit_ids", []) as Array
		for unit_id_value: Variant in administrative_ids:
			var unit_id: String = str(unit_id_value)
			var administrative_unit: Dictionary = administrative_by_id.get(unit_id, {}) as Dictionary
			var geometries: Array = administrative_unit.get("geometry", []) as Array
			for geometry_value: Variant in geometries:
				if not geometry_value is Dictionary:
					continue
				var geometry: Dictionary = geometry_value as Dictionary
				var outer: PackedVector2Array = _points_from_raw(geometry.get("outer", []))
				if outer.size() > 2:
					region_polygons.append(_simplify_line(outer, 100))
		_region_polygons[region_id] = region_polygons


func _read_document(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_data_errors.append("无法读取：" + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	_data_errors.append("JSON格式错误：" + path)
	return {}


func _dictionary_array(document: Dictionary, key: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var values: Array = document.get(key, []) as Array
	for value: Variant in values:
		if value is Dictionary:
			output.append(value as Dictionary)
	return output


func _points_from_raw(raw_value: Variant) -> PackedVector2Array:
	var output: PackedVector2Array = PackedVector2Array()
	if not raw_value is Array:
		return output
	var raw_points: Array = raw_value as Array
	for point_value: Variant in raw_points:
		if point_value is Array:
			var point: Array = point_value as Array
			if point.size() >= 2:
				output.append(Vector2(float(point[0]), float(point[1])))
	return output


func _country_id_from_feature(feature: Dictionary, iso: String) -> String:
	if iso == "FRA":
		return FOCUS_COUNTRY_ID
	if not iso.is_empty() and iso != "-99":
		return "country_" + iso.to_lower()
	var source_id: String = str(feature.get("id", feature.get("name", "unknown")))
	return "country_" + source_id.to_lower().replace(" ", "_").replace("-", "_")


func _to_unit_line(points: PackedVector2Array) -> PackedVector3Array:
	var output: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in points:
		output.append(_lon_lat_to_unit(point))
	return output


func _lon_lat_to_unit(lon_lat: Vector2) -> Vector3:
	var lon: float = deg_to_rad(lon_lat.x)
	var lat: float = deg_to_rad(lon_lat.y)
	return Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))


func _average_unit(points: PackedVector3Array) -> Vector3:
	if points.is_empty():
		return Vector3.FORWARD
	var total: Vector3 = Vector3.ZERO
	for point: Vector3 in points:
		total += point
	if total.is_zero_approx():
		return points[0]
	return total.normalized()


func _polygon_area_score(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var area: float = 0.0
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var next: Vector2 = points[(index + 1) % points.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _simplify_line(points: PackedVector2Array, max_points: int) -> PackedVector2Array:
	if points.size() <= max_points:
		return points
	var epsilon: float = 0.015
	var simplified: PackedVector2Array = _rdp(points, epsilon)
	while simplified.size() > max_points and epsilon < 8.0:
		epsilon *= 1.55
		simplified = _rdp(points, epsilon)
	return simplified


func _rdp(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]
	var maximum_distance: float = -1.0
	var maximum_index: int = -1
	for index: int in range(1, points.size() - 1):
		var distance: float = _distance_to_segment(points[index], first, last)
		if distance > maximum_distance:
			maximum_distance = distance
			maximum_index = index
	if maximum_distance <= epsilon or maximum_index <= 0:
		return PackedVector2Array([first, last])
	var left: PackedVector2Array = PackedVector2Array()
	for left_index: int in range(maximum_index + 1):
		left.append(points[left_index])
	var right: PackedVector2Array = PackedVector2Array()
	for right_index: int in range(maximum_index, points.size()):
		right.append(points[right_index])
	var left_result: PackedVector2Array = _rdp(left, epsilon)
	var right_result: PackedVector2Array = _rdp(right, epsilon)
	var output: PackedVector2Array = PackedVector2Array()
	for left_result_index: int in range(left_result.size() - 1):
		output.append(left_result[left_result_index])
	for right_point: Vector2 in right_result:
		output.append(right_point)
	return output


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(start)
	var ratio: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _seed_world_events() -> void:
	_world_events.clear()
	_event_by_id.clear()
	var event_index: int = 0
	for institution: Dictionary in _institutions:
		if event_index >= 8:
			break
		var agenda: String = str(institution.get("agenda", ""))
		var lon_lat_value: Variant = _lon_lat_from_record(institution, "lon_lat")
		if agenda.is_empty() or lon_lat_value == null:
			continue
		var event_id: String = "institution_agenda_" + str(institution.get("id", event_index))
		var event: Dictionary = {
			"id": event_id,
			"title": agenda,
			"source": str(institution.get("name", "机构")),
			"region_id": str(institution.get("parent_region_id", "")),
			"city_id": str(institution.get("city_id", "")),
			"lon_lat": lon_lat_value,
			"severity": 2 if event_index < 2 else 1,
		}
		_world_events.append(event)
		_event_by_id[event_id] = event
		event_index += 1
	activity_unread = mini(2, _world_events.size())


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var desired: Vector2i = FOCUS_VIEWPORT_SIZE if layout_mode_id == LAYOUT_FOCUS else WORKSPACE_VIEWPORT_SIZE
	var reserved_right: float = 32.0
	if layout_mode_id == LAYOUT_WORKSPACE and workspace_open:
		reserved_right = minf(390.0, size.x * 0.34)
	var available_width: float = maxf(300.0, size.x - reserved_right - 48.0)
	var available_height: float = maxf(260.0, size.y - 112.0)
	var scale_factor: float = minf(1.0, minf(available_width / float(desired.x), available_height / float(desired.y)))
	var viewport_size: Vector2 = Vector2(
		maxf(300.0, round(float(desired.x) * scale_factor)),
		maxf(260.0, round(float(desired.y) * scale_factor))
	)
	viewport_container.size = viewport_size
	var left_area_width: float = size.x if reserved_right <= 32.0 else maxf(360.0, size.x - reserved_right)
	var x: float = maxf(16.0, (left_area_width - viewport_size.x) * 0.5)
	var y: float = maxf(82.0, (size.y - viewport_size.y) * 0.5)
	viewport_container.position = Vector2(x, y)
	_hemisphere_center = viewport_container.position + viewport_size * 0.5
	_hemisphere_radius = minf(viewport_size.y / CAMERA_ORTHO_SIZE, viewport_size.x * 0.49)
	_hemisphere_rect = Rect2(
		_hemisphere_center - Vector2(_hemisphere_radius, _hemisphere_radius),
		Vector2(_hemisphere_radius * 2.0, _hemisphere_radius * 2.0)
	)


func _set_layout(layout_id: int) -> void:
	layout_mode_id = layout_id
	if layout_mode_id == LAYOUT_FOCUS:
		workspace_open = false
	else:
		workspace_open = true
	_apply_layout()
	_mark_projection_dirty()
	queue_redraw()


func _set_world_layer_visible(active: bool) -> void:
	viewport_container.visible = active
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED


func _start_motion() -> void:
	if space_level == WORLD and world_mode == WORLD_COUNTRIES and not is_processing():
		set_process(true)


func _edge_hover_spin() -> float:
	if space_level != WORLD or world_mode != WORLD_COUNTRIES or dragging:
		return 0.0
	var position: Vector2 = get_local_mouse_position()
	if not _hemisphere_rect.has_point(position) or _position_hits_ui(position):
		return 0.0
	var left_power: float = clampf((_hemisphere_rect.position.x + EDGE_BAND - position.x) / EDGE_BAND, 0.0, 1.0)
	var right_power: float = clampf((position.x - (_hemisphere_rect.end.x - EDGE_BAND)) / EDGE_BAND, 0.0, 1.0)
	return (right_power - left_power) * 0.32


func _mark_projection_dirty() -> void:
	_projection_dirty = true


func _ensure_projection_cache() -> void:
	if not _projection_dirty:
		return
	_projection_dirty = false
	_global_screen_segments.clear()
	_selected_country_segments.clear()
	_country_screen_anchors.clear()
	_event_screen_positions.clear()
	_focus_country_screen_polygons.clear()
	_focus_region_screen_polygons.clear()
	_focus_region_screen_anchors.clear()

	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	for unit_line: PackedVector3Array in _coastline_unit_lines:
		var segments: Array[PackedVector2Array] = _project_unit_line(unit_line, basis)
		for segment: PackedVector2Array in segments:
			_global_screen_segments.append(segment)

	if not selected_country_id.is_empty():
		var selected_polygons: Array = _country_unit_polygons.get(selected_country_id, []) as Array
		for selected_value: Variant in selected_polygons:
			var selected_line: PackedVector3Array = selected_value
			var selected_segments: Array[PackedVector2Array] = _project_unit_line(selected_line, basis)
			for selected_segment: PackedVector2Array in selected_segments:
				_selected_country_segments.append(selected_segment)

	for country_key_value: Variant in _country_anchor_units.keys():
		var country_id: String = str(country_key_value)
		var anchor: Vector3 = _country_anchor_units.get(country_id, Vector3.ZERO) as Vector3
		var rotated: Vector3 = basis * anchor
		if rotated.z >= 0.0:
			_country_screen_anchors[country_id] = _sphere_screen(rotated)

	for event: Dictionary in _world_events:
		var event_lon_lat_value: Variant = _lon_lat_from_record(event, "lon_lat")
		if event_lon_lat_value == null:
			continue
		var event_lon_lat: Vector2 = event_lon_lat_value as Vector2
		var event_rotated: Vector3 = basis * _lon_lat_to_unit(event_lon_lat)
		if event_rotated.z >= 0.0:
			_event_screen_positions[str(event.get("id", ""))] = _sphere_screen(event_rotated)

	_rebuild_focus_cache()


func _project_unit_line(line: PackedVector3Array, basis: Basis) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	if line.size() < 2:
		return output
	var segment: PackedVector2Array = PackedVector2Array()
	var previous: Vector3 = basis * line[0]
	var previous_visible: bool = previous.z >= 0.0
	if previous_visible:
		segment.append(_sphere_screen(previous))
	for index: int in range(1, line.size()):
		var current: Vector3 = basis * line[index]
		var current_visible: bool = current.z >= 0.0
		if current_visible != previous_visible:
			var denominator: float = previous.z - current.z
			var ratio: float = 0.5
			if absf(denominator) > 0.000001:
				ratio = clampf(previous.z / denominator, 0.0, 1.0)
			var horizon: Vector3 = previous.lerp(current, ratio)
			horizon.z = 0.0
			segment.append(_sphere_screen(horizon))
			if segment.size() > 1:
				output.append(segment)
			segment = PackedVector2Array()
			if current_visible:
				segment.append(_sphere_screen(horizon))
		if current_visible:
			segment.append(_sphere_screen(current))
		previous = current
		previous_visible = current_visible
	if segment.size() > 1:
		output.append(segment)
	return output


func _sphere_screen(point: Vector3) -> Vector2:
	return _hemisphere_center + Vector2(point.x, -point.y) * _hemisphere_radius


func _rebuild_focus_cache() -> void:
	var focus_rect: Rect2 = _focus_map_rect()
	for region: Dictionary in _regions:
		var region_id: String = str(region.get("id", ""))
		var source_polygons: Array = _region_polygons.get(region_id, []) as Array
		var screen_polygons: Array[PackedVector2Array] = []
		for source_value: Variant in source_polygons:
			var source: PackedVector2Array = source_value
			var screen: PackedVector2Array = PackedVector2Array()
			for lon_lat: Vector2 in source:
				screen.append(_lon_lat_to_rect(lon_lat, _focus_bounds, focus_rect))
			if screen.size() > 2:
				screen_polygons.append(screen)
				_focus_country_screen_polygons.append(screen)
		_focus_region_screen_polygons[region_id] = screen_polygons
		var label_value: Variant = _lon_lat_from_record(region, "label_lon_lat")
		if label_value != null:
			var label_lon_lat: Vector2 = label_value as Vector2
			_focus_region_screen_anchors[region_id] = _lon_lat_to_rect(label_lon_lat, _focus_bounds, focus_rect)


func _focus_map_rect() -> Rect2:
	return _hemisphere_rect.grow(-24.0)


func _draw_world_overlay() -> void:
	_ensure_projection_cache()
	if world_mode == WORLD_COUNTRIES:
		_draw_global_world()
	else:
		_draw_country_focus()


func _draw_global_world() -> void:
	for segment: PackedVector2Array in _global_screen_segments:
		draw_polyline(segment, Color(0.64, 0.84, 0.78, 0.23), 0.85, true)
	for selected_segment: PackedVector2Array in _selected_country_segments:
		draw_polyline(selected_segment, Color(0.92, 0.77, 0.42, 0.88), 2.0, true)

	for country_key_value: Variant in _country_screen_anchors.keys():
		var country_id: String = str(country_key_value)
		var point: Vector2 = _country_screen_anchors.get(country_id, Vector2.ZERO) as Vector2
		var selected: bool = country_id == selected_country_id
		var hovered: bool = country_id == hover_country_id
		var radius: float = 5.5 if selected or hovered else 3.2
		var color: Color = Color(0.94, 0.76, 0.40, 0.94) if selected else Color(0.72, 0.88, 0.82, 0.72)
		if hovered:
			color = Color(0.84, 0.96, 0.90, 0.98)
		draw_circle(point, radius, color)
		if selected or hovered:
			var country: Dictionary = _country_by_id.get(country_id, {}) as Dictionary
			_draw_label(point + Vector2(9.0, -8.0), str(country.get("name", country_id)), 12)

	for event_key_value: Variant in _event_screen_positions.keys():
		var event_id: String = str(event_key_value)
		var event_point: Vector2 = _event_screen_positions.get(event_id, Vector2.ZERO) as Vector2
		var event: Dictionary = _event_by_id.get(event_id, {}) as Dictionary
		var severity: int = int(event.get("severity", 1))
		var event_color: Color = Color(0.96, 0.59, 0.28, 0.94) if severity >= 2 else Color(0.91, 0.76, 0.40, 0.82)
		var event_radius: float = 5.5 if event_id == hover_event_id or event_id == selected_event_id else 4.0
		var halo: Color = event_color
		halo.a = 0.14
		draw_circle(event_point, event_radius + 3.0, halo, false, 1.2)
		draw_circle(event_point, event_radius, event_color)
		if event_id == hover_event_id:
			_draw_label(event_point + Vector2(10.0, 4.0), _ellipsize(str(event.get("title", "状态")), 28), 11)


func _draw_country_focus() -> void:
	for focus_polygon: PackedVector2Array in _focus_country_screen_polygons:
		draw_colored_polygon(focus_polygon, Color(0.16, 0.28, 0.28, 0.20))
		draw_polyline(focus_polygon, Color(0.68, 0.84, 0.76, 0.30), 1.0, true)

	for region: Dictionary in _regions:
		var region_id: String = str(region.get("id", ""))
		var selected: bool = region_id == selected_region_id
		var hovered: bool = region_id == hover_region_id
		var fill: Color = _region_color(region, 0.14)
		var border: Color = Color(0.82, 0.77, 0.58, 0.62)
		if selected:
			fill = Color(0.84, 0.63, 0.28, 0.34)
			border = Color(0.96, 0.80, 0.42, 0.96)
		elif hovered:
			fill = Color(0.44, 0.70, 0.64, 0.28)
			border = Color(0.78, 0.94, 0.86, 0.90)
		var polygons: Array = _focus_region_screen_polygons.get(region_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, 2.0 if selected else 1.15, true)
		var anchor: Vector2 = _focus_region_screen_anchors.get(region_id, Vector2.INF) as Vector2
		if anchor != Vector2.INF:
			draw_circle(anchor, 4.5 if selected or hovered else 3.0, border)
			_draw_label(anchor + Vector2(7.0, -5.0), _ellipsize(str(region.get("display_name_zh", region_id)), 14), 10)

	_draw_label(_hemisphere_rect.position + Vector2(18.0, 28.0), "国家聚焦 · 法兰西第三共和国", 15)
	_draw_button(Rect2(_hemisphere_rect.position + Vector2(18.0, 42.0), Vector2(96.0, 28.0)), "返回全球", "overview_world", true)


func _region_color(region: Dictionary, alpha: float) -> Color:
	var value: String = str(region.get("legal_color", "#6f8d9f"))
	var color: Color = Color.from_string(value, Color(0.44, 0.56, 0.62, 1.0))
	color.a = alpha
	return color


func _select_global_object_at(position: Vector2, click: bool) -> void:
	_ensure_projection_cache()
	var nearest_event: String = ""
	var nearest_event_distance: float = 12.0
	for event_key_value: Variant in _event_screen_positions.keys():
		var event_id: String = str(event_key_value)
		var event_point: Vector2 = _event_screen_positions.get(event_id, Vector2.ZERO) as Vector2
		var event_distance: float = position.distance_to(event_point)
		if event_distance < nearest_event_distance:
			nearest_event = event_id
			nearest_event_distance = event_distance

	var nearest_country: String = ""
	var nearest_country_distance: float = 17.0
	for country_key_value: Variant in _country_screen_anchors.keys():
		var country_id: String = str(country_key_value)
		var country_point: Vector2 = _country_screen_anchors.get(country_id, Vector2.ZERO) as Vector2
		var country_distance: float = position.distance_to(country_point)
		if country_distance < nearest_country_distance:
			nearest_country = country_id
			nearest_country_distance = country_distance

	var next_event: String = nearest_event
	var next_country: String = "" if not nearest_event.is_empty() else nearest_country
	if hover_event_id != next_event or hover_country_id != next_country:
		hover_event_id = next_event
		hover_country_id = next_country
		queue_redraw()
	if not click:
		return
	if not nearest_event.is_empty():
		selected_event_id = nearest_event
		selected_country_id = ""
		selected_region_id = ""
		selected_institution_id = ""
		_set_info_open(true)
	elif not nearest_country.is_empty():
		selected_country_id = nearest_country
		selected_event_id = ""
		selected_region_id = ""
		selected_institution_id = ""
		_mark_projection_dirty()
		_set_info_open(true)


func _select_focus_region_at(position: Vector2, click: bool) -> void:
	_ensure_projection_cache()
	var best: String = ""
	for region_key_value: Variant in _focus_region_screen_polygons.keys():
		var region_id: String = str(region_key_value)
		var polygons: Array = _focus_region_screen_polygons.get(region_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			if Geometry2D.is_point_in_polygon(position, polygon):
				best = region_id
				break
		if not best.is_empty():
			break
	if best.is_empty():
		var nearest_distance: float = 24.0
		for region_anchor_key: Variant in _focus_region_screen_anchors.keys():
			var anchor_region_id: String = str(region_anchor_key)
			var anchor: Vector2 = _focus_region_screen_anchors.get(anchor_region_id, Vector2.ZERO) as Vector2
			var distance: float = position.distance_to(anchor)
			if distance < nearest_distance:
				best = anchor_region_id
				nearest_distance = distance
	if hover_region_id != best:
		hover_region_id = best
		queue_redraw()
	if click and not best.is_empty():
		selected_region_id = best
		selected_event_id = ""
		selected_institution_id = ""
		_set_info_open(true)
		queue_redraw()


func _clear_global_hover() -> void:
	if hover_country_id.is_empty() and hover_event_id.is_empty():
		return
	hover_country_id = ""
	hover_event_id = ""
	queue_redraw()


func _draw_region_map() -> void:
	var rect: Rect2 = _main_content_rect(120.0, 118.0, 82.0)
	_panel(rect, Color(0.025, 0.047, 0.052, 0.94), Color(0.70, 0.62, 0.36, 0.32))
	var region: Dictionary = _region_by_id.get(selected_region_id, {}) as Dictionary
	_draw_label(rect.position + Vector2(24.0, 34.0), "二维大区层 · " + str(region.get("display_name_zh", "选中大区")), 17)
	_draw_label(rect.position + Vector2(24.0, 58.0), "行政边界、城市与机构来自现有数据；城市联系线按现有坐标派生", 12, Color(0.73, 0.82, 0.78, 1.0))
	_draw_region_flat_geometry(rect)
	_draw_region_cities_and_routes(rect)
	_draw_region_institutions(rect)


func _draw_region_flat_geometry(rect: Rect2) -> void:
	var polygons: Array = _region_polygons.get(selected_region_id, []) as Array
	var bounds: Rect2 = _lon_lat_bounds(polygons)
	var map_rect: Rect2 = _region_map_rect(rect)
	for polygon_value: Variant in polygons:
		var polygon: PackedVector2Array = polygon_value
		var flat: PackedVector2Array = PackedVector2Array()
		for lon_lat: Vector2 in polygon:
			flat.append(_lon_lat_to_rect(lon_lat, bounds, map_rect))
		if flat.size() > 2:
			draw_colored_polygon(flat, Color(0.32, 0.48, 0.48, 0.20))
			draw_polyline(flat, Color(0.83, 0.75, 0.48, 0.70), 1.4, true)


func _draw_region_cities_and_routes(rect: Rect2) -> void:
	var city_ids: Array = _cities_by_region.get(selected_region_id, []) as Array
	if city_ids.is_empty():
		_draw_label(rect.position + Vector2(86.0, rect.size.y - 60.0), "当前大区没有配置城市入口", 13, Color(0.95, 0.72, 0.43, 1.0))
		return
	var polygons: Array = _region_polygons.get(selected_region_id, []) as Array
	var bounds: Rect2 = _lon_lat_bounds(polygons)
	var map_rect: Rect2 = _region_map_rect(rect)
	var city_records: Array[Dictionary] = []
	for city_id_value: Variant in city_ids:
		var city: Dictionary = _city_by_id.get(str(city_id_value), {}) as Dictionary
		if _lon_lat_from_record(city, "lon_lat") != null:
			city_records.append(city)
	city_records.sort_custom(Callable(self, "_city_lon_less"))
	var city_points: Array[Vector2] = []
	for city: Dictionary in city_records:
		var lon_lat_value: Variant = _lon_lat_from_record(city, "lon_lat")
		if lon_lat_value != null:
			city_points.append(_lon_lat_to_rect(lon_lat_value as Vector2, bounds, map_rect))
	for route_index: int in range(city_points.size() - 1):
		draw_line(city_points[route_index], city_points[route_index + 1], Color(0.55, 0.75, 0.68, 0.36), 1.8)
	var list_x: float = rect.end.x - 174.0
	var list_y: float = rect.position.y + 88.0
	var visible_count: int = mini(city_records.size(), 8)
	for index: int in range(visible_count):
		var city_record: Dictionary = city_records[index]
		var city_id: String = str(city_record.get("id", ""))
		var point: Vector2 = city_points[index]
		draw_circle(point, 7.0, Color(0.88, 0.74, 0.42, 0.92))
		_draw_label(point + Vector2(10.0, 4.0), _ellipsize(str(city_record.get("name", "城市")), 16), 12)
		_register_hit(Rect2(point - Vector2(12.0, 12.0), Vector2(24.0, 24.0)), "enter_city:" + city_id, true)
		_draw_button(Rect2(list_x, list_y + float(index) * 34.0, 142.0, 27.0), "进入 " + _ellipsize(str(city_record.get("name", "城市")), 12), "enter_city:" + city_id, true)


func _draw_region_institutions(rect: Rect2) -> void:
	var institution_ids: Array = _institutions_by_region.get(selected_region_id, []) as Array
	if institution_ids.is_empty():
		return
	var bounds: Rect2 = _lon_lat_bounds(_region_polygons.get(selected_region_id, []) as Array)
	var map_rect: Rect2 = _region_map_rect(rect)
	for institution_id_value: Variant in institution_ids:
		var institution: Dictionary = _institution_by_id.get(str(institution_id_value), {}) as Dictionary
		var lon_lat_value: Variant = _lon_lat_from_record(institution, "lon_lat")
		if lon_lat_value == null:
			continue
		var point: Vector2 = _lon_lat_to_rect(lon_lat_value as Vector2, bounds, map_rect)
		draw_rect(Rect2(point - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), Color(0.82, 0.90, 0.78, 0.86))


func _region_map_rect(rect: Rect2) -> Rect2:
	var map_rect: Rect2 = rect.grow(-70.0)
	map_rect.size = Vector2(maxf(220.0, map_rect.size.x - 190.0), map_rect.size.y)
	return map_rect


func _city_lon_less(a: Dictionary, b: Dictionary) -> bool:
	var a_value: Variant = _lon_lat_from_record(a, "lon_lat")
	var b_value: Variant = _lon_lat_from_record(b, "lon_lat")
	if a_value == null:
		return false
	if b_value == null:
		return true
	return (a_value as Vector2).x < (b_value as Vector2).x


func _draw_city_map() -> void:
	var rect: Rect2 = _main_content_rect(120.0, 118.0, 82.0)
	_panel(rect, Color(0.03, 0.04, 0.04, 0.94), Color(0.72, 0.75, 0.66, 0.24))
	var city: Dictionary = _city_by_id.get(selected_city_id, {}) as Dictionary
	_draw_label(rect.position + Vector2(24.0, 34.0), "城市本地层 · " + str(city.get("name", "本地城市")), 17)
	_draw_label(rect.position + Vector2(24.0, 58.0), "显示该城市已配置的正式机构与人物；未配置对象不会用虚构地点补齐", 12, Color(0.73, 0.82, 0.78, 1.0))
	_draw_city_institutions(rect)
	_draw_city_characters(rect)


func _draw_city_institutions(rect: Rect2) -> void:
	var institution_ids: Array = _institutions_by_city.get(selected_city_id, []) as Array
	if institution_ids.is_empty():
		_draw_label(rect.position + Vector2(40.0, 126.0), "当前城市没有配置正式机构节点。", 14, Color(0.95, 0.72, 0.43, 1.0))
		return
	var node_positions: Dictionary = {}
	var columns: int = mini(3, maxi(1, institution_ids.size()))
	var row_count: int = int(ceil(float(institution_ids.size()) / float(columns)))
	var inner_left: float = rect.position.x + 96.0
	var inner_right: float = rect.end.x - 96.0
	var available_top: float = rect.position.y + 145.0
	var available_bottom: float = rect.end.y - 104.0
	var row_step: float = 0.0
	if row_count > 1:
		row_step = maxf(44.0, (available_bottom - available_top) / float(row_count - 1))
	for index: int in range(institution_ids.size()):
		var column: int = index % columns
		var row: int = int(index / columns)
		var column_ratio: float = 0.5 if columns <= 1 else float(column) / float(columns - 1)
		node_positions[str(institution_ids[index])] = Vector2(lerpf(inner_left, inner_right, column_ratio), available_top + float(row) * row_step)
	for institution_id_value: Variant in institution_ids:
		var institution_id: String = str(institution_id_value)
		var institution: Dictionary = _institution_by_id.get(institution_id, {}) as Dictionary
		var parent_id: String = str(institution.get("parent_institution_id", ""))
		if node_positions.has(parent_id):
			draw_line(node_positions.get(parent_id, Vector2.ZERO) as Vector2, node_positions.get(institution_id, Vector2.ZERO) as Vector2, Color(0.58, 0.70, 0.64, 0.34), 1.8)
	for institution_id_value: Variant in institution_ids:
		var institution_id: String = str(institution_id_value)
		var institution: Dictionary = _institution_by_id.get(institution_id, {}) as Dictionary
		var point: Vector2 = node_positions.get(institution_id, Vector2.ZERO) as Vector2
		var node_rect: Rect2 = Rect2(point - Vector2(72.0, 28.0), Vector2(144.0, 56.0))
		_panel(node_rect, Color(0.08, 0.12, 0.115, 0.90), Color(0.74, 0.68, 0.44, 0.42))
		_draw_label(node_rect.position + Vector2(10.0, 23.0), _ellipsize(str(institution.get("name", "机构")), 18), 12)
		_draw_label(node_rect.position + Vector2(10.0, 43.0), _ellipsize(str(institution.get("department", institution.get("institution_kind", ""))), 20), 10, Color(0.72, 0.82, 0.76, 1.0))
		_register_hit(node_rect, "inspect_institution:" + institution_id, true)


func _draw_city_characters(rect: Rect2) -> void:
	var x: float = rect.position.x + 34.0
	var y: float = rect.end.y - 54.0
	for key_value: Variant in _character_profiles.keys():
		var key: String = str(key_value)
		var profile: Dictionary = _character_profiles.get(key, {}) as Dictionary
		if str(profile.get("city_id", "")) != selected_city_id:
			continue
		if x + 210.0 > rect.end.x - 24.0:
			x = rect.position.x + 34.0
			y -= 38.0
		var badge: Rect2 = Rect2(x, y, 210.0, 30.0)
		_panel(badge, Color(0.07, 0.10, 0.095, 0.88), Color(0.54, 0.70, 0.63, 0.34))
		var profile_text: String = str(profile.get("display_name_zh", profile.get("name", "人物"))) + " · " + str(profile.get("position", ""))
		_draw_label(badge.position + Vector2(10.0, 20.0), _ellipsize(profile_text, 30), 11)
		x += 222.0


func _main_content_rect(preferred_margin: float, top: float, bottom: float) -> Rect2:
	var margin: float = minf(preferred_margin, maxf(18.0, (size.x - 520.0) * 0.5))
	return Rect2(margin, top, maxf(240.0, size.x - margin * 2.0), maxf(220.0, size.y - top - bottom))


func _draw_corners() -> void:
	var compact: bool = size.x < 940.0 or size.y < 620.0
	var left_width: float = minf(284.0, size.x * 0.42)
	var right_width: float = minf(282.0, size.x * 0.42)
	var top_height: float = 56.0 if compact else 66.0
	var bottom_height: float = 58.0 if compact else 70.0
	var country_rect: Rect2 = Rect2(18.0, 18.0, left_width, top_height)
	var time_rect: Rect2 = Rect2(size.x - right_width - 18.0, 18.0, right_width, top_height)
	var character_rect: Rect2 = Rect2(18.0, size.y - bottom_height - 18.0, left_width, bottom_height)
	var activity_rect: Rect2 = Rect2(size.x - right_width - 18.0, size.y - bottom_height - 18.0, right_width, bottom_height)
	_draw_corner(country_rect, str(_country_profile.get("formal_name_zh", "法兰西第三共和国")), "国家 / 政权 / 机构", "toggle_country_panel", Color(0.72, 0.64, 0.38, 0.22), compact)
	_draw_corner(character_rect, _active_character_name(), _active_character_position(), "toggle_character_panel", Color(0.72, 0.64, 0.38, 0.22), compact)
	_draw_corner(activity_rect, "已知信息 · 未读 %d" % activity_unread, _activity_summary(), "toggle_activity_panel", Color(0.72, 0.50, 0.25, 0.22), compact)
	_panel(time_rect, Color(0.025, 0.055, 0.06, 0.88), Color(0.72, 0.64, 0.38, 0.22))
	_register_hit(time_rect, "toggle_time_panel", true)
	_draw_label(time_rect.position + Vector2(12.0, 22.0), _format_sim_datetime(), 13)
	var button_y: float = time_rect.end.y - 28.0
	_draw_button(Rect2(time_rect.position.x + 10.0, button_y, 44.0, 22.0), "Ⅱ" if sim_paused else "▶", "toggle_pause", true)
	_draw_button(Rect2(time_rect.position.x + 60.0, button_y, 38.0, 22.0), "1×", "speed:1", true)
	_draw_button(Rect2(time_rect.position.x + 102.0, button_y, 38.0, 22.0), "2×", "speed:2", true)
	_draw_button(Rect2(time_rect.position.x + 144.0, button_y, 38.0, 22.0), "4×", "speed:4", true)


func _draw_corner(rect: Rect2, title: String, subtitle: String, action: String, border: Color, compact: bool) -> void:
	_panel(rect, Color(0.025, 0.055, 0.06, 0.88), border)
	_register_hit(rect, action, true)
	_draw_label(rect.position + Vector2(14.0, 25.0), _ellipsize(title, 24), 14 if compact else 15)
	if not compact:
		_draw_label(rect.position + Vector2(14.0, 48.0), _ellipsize(subtitle, 30), 10, Color(0.76, 0.67, 0.39, 1.0))


func _draw_top_info() -> void:
	if info_progress <= 0.001:
		return
	var compact: bool = size.x < 940.0
	var height: float = minf(size.y * 0.34, 218.0)
	var rect: Rect2 = Rect2()
	if compact:
		rect = Rect2(18.0, 86.0, size.x - 36.0, height)
	else:
		rect = Rect2(318.0, 8.0, maxf(360.0, size.x - 636.0), height)
	var shown_y: float = rect.position.y
	rect.position.y = lerpf(-height - 12.0, shown_y, info_progress)
	_panel(rect, Color(0.018, 0.035, 0.038, 0.96), Color(0.78, 0.70, 0.46, 0.40))
	_register_hit(rect, "noop", true)
	var title: String = "空间对象"
	var path: String = _breadcrumb_text()
	var summary: String = ""
	var action_label: String = ""
	var action: String = ""
	var action_enabled: bool = false
	if not selected_institution_id.is_empty():
		var institution: Dictionary = _institution_by_id.get(selected_institution_id, {}) as Dictionary
		title = str(institution.get("name", "机构"))
		summary = str(institution.get("mandate", institution.get("agenda", "未配置摘要")))
	elif not selected_event_id.is_empty():
		var event: Dictionary = _event_by_id.get(selected_event_id, {}) as Dictionary
		title = str(event.get("title", "状态"))
		path = "世界 / 状态 / " + str(event.get("source", "机构"))
		summary = "来源：" + str(event.get("source", "机构"))
		action_label = "定位地区"
		action = "locate_event"
		action_enabled = not str(event.get("region_id", "")).is_empty()
	elif world_mode == WORLD_COUNTRIES and not selected_country_id.is_empty():
		var country: Dictionary = _country_by_id.get(selected_country_id, {}) as Dictionary
		title = str(country.get("name", "国家"))
		path = "世界 / " + title
		summary = "国家级空间对象 · ISO " + str(country.get("iso_a3", ""))
		action_label = "进入国家"
		action = "focus_country"
		action_enabled = selected_country_id == FOCUS_COUNTRY_ID
	elif not selected_region_id.is_empty():
		var region: Dictionary = _region_by_id.get(selected_region_id, {}) as Dictionary
		title = str(region.get("display_name_zh", "大区"))
		path = "世界 / 法兰西第三共和国 / " + title
		summary = "人口：%s · %s" % [str(region.get("population", "未配置")), str(region.get("market", "未配置"))]
		action_label = "进入大区"
		action = "enter_region"
		action_enabled = true
	_draw_label(rect.position + Vector2(24.0, 34.0), _ellipsize(title, 36), 19)
	_draw_label(rect.position + Vector2(24.0, 60.0), _ellipsize(path, 54), 11, Color(0.73, 0.82, 0.78, 1.0))
	_draw_label(rect.position + Vector2(24.0, 94.0), _ellipsize(summary, 68), 12)
	if not action.is_empty():
		_draw_button(Rect2(rect.end.x - 176.0, rect.end.y - 48.0, 128.0, 32.0), action_label, action, action_enabled)
	_draw_button(Rect2(rect.end.x - 42.0, rect.position.y + 10.0, 30.0, 26.0), "×", "close_info", true)


func _set_info_open(open: bool) -> void:
	info_open = open
	if _info_tween != null and _info_tween.is_valid():
		_info_tween.kill()
	_info_tween = create_tween()
	_info_tween.set_trans(Tween.TRANS_CUBIC)
	_info_tween.set_ease(Tween.EASE_OUT)
	_info_tween.tween_property(self, "info_progress", 1.0 if open else 0.0, 0.18)
	_info_tween.tween_callback(queue_redraw)
	_info_tween.parallel().tween_method(_redraw_info_progress, info_progress, 1.0 if open else 0.0, 0.18)


func _redraw_info_progress(value: float) -> void:
	info_progress = value
	queue_redraw()


func _draw_layout_switch() -> void:
	_draw_button(Rect2(size.x * 0.5 - 96.0, size.y - 42.0, 88.0, 28.0), "F1 半球", "layout_focus", true)
	_draw_button(Rect2(size.x * 0.5 + 8.0, size.y - 42.0, 98.0, 28.0), "F2 桌面", "layout_workspace", true)
	if layout_mode_id != LAYOUT_WORKSPACE or space_level != WORLD:
		return
	if not workspace_open:
		_draw_button(Rect2(size.x - 130.0, 102.0, 96.0, 28.0), "展开工作区", "toggle_workspace", true)
		return
	var panel_width: float = minf(318.0, maxf(260.0, size.x * 0.28))
	var rect: Rect2 = Rect2(size.x - panel_width - 36.0, 112.0, panel_width, 214.0)
	_panel(rect, Color(0.02, 0.043, 0.046, 0.92), Color(0.65, 0.78, 0.70, 0.24))
	_register_hit(rect, "noop", true)
	_draw_label(rect.position + Vector2(20.0, 30.0), "当前区域工作空间", 16)
	_draw_label(rect.position + Vector2(20.0, 62.0), "选择：" + _ellipsize(_workspace_selection_name(), 24), 12)
	_draw_label(rect.position + Vector2(20.0, 92.0), "层级：世界 → 大区 → 城市", 12)
	var can_enter: bool = world_mode == WORLD_COUNTRY_FOCUS and not selected_region_id.is_empty()
	_draw_button(Rect2(rect.position.x + 20.0, rect.end.y - 52.0, 118.0, 32.0), "进入大区", "enter_region", can_enter)
	_draw_button(Rect2(rect.end.x - 116.0, rect.end.y - 52.0, 96.0, 32.0), "收起", "toggle_workspace", true)


func _draw_breadcrumbs() -> void:
	_draw_label(Vector2(24.0, 108.0), _ellipsize(_breadcrumb_text(), 68), 13, Color(0.76, 0.82, 0.78, 1.0))
	if space_level != WORLD:
		_draw_button(Rect2(24.0, 126.0, 92.0, 30.0), "返回上层", "back", true)
		_draw_button(Rect2(126.0, 126.0, 92.0, 30.0), "返回世界", "world", true)


func _draw_active_hud_panel() -> void:
	if active_hud_panel.is_empty():
		return
	var rect: Rect2 = Rect2(maxf(24.0, size.x * 0.18), maxf(90.0, size.y * 0.17), maxf(360.0, size.x * 0.64), maxf(300.0, size.y * 0.62))
	_panel(rect, Color(0.018, 0.035, 0.038, 0.98), Color(0.78, 0.70, 0.46, 0.42))
	_register_hit(rect, "noop", true)
	_draw_button(Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 30.0, 26.0), "×", "close_hud_panel", true)
	if active_hud_panel == "country":
		_draw_country_panel(rect)
	elif active_hud_panel == "character":
		_draw_character_panel(rect)
	elif active_hud_panel == "activity":
		_draw_activity_panel(rect)
	else:
		_draw_time_panel(rect)


func _draw_country_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), str(_country_profile.get("formal_name_zh", "法兰西第三共和国")), 20)
	_draw_label(rect.position + Vector2(24.0, 72.0), "政体：" + str(_country_profile.get("government_name", "第三共和国")), 13)
	_draw_label(rect.position + Vector2(24.0, 104.0), _ellipsize("公开议程：" + str(_country_profile.get("public_policy", "未配置")), 62), 12)
	_draw_label(rect.position + Vector2(24.0, 134.0), _ellipsize("新闻：" + str(_country_profile.get("news", "未配置")), 62), 12)
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 138.0, 32.0), "定位法兰西", "focus_france", true)


func _draw_character_panel(rect: Rect2) -> void:
	var profile: Dictionary = _character_profiles.get(active_character_key, {}) as Dictionary
	_draw_label(rect.position + Vector2(24.0, 38.0), str(profile.get("display_name_zh", profile.get("name", "人物"))), 20)
	_draw_label(rect.position + Vector2(24.0, 70.0), str(profile.get("position", profile.get("occupation", ""))), 13)
	_draw_label(rect.position + Vector2(24.0, 102.0), _ellipsize("所在地：" + str(profile.get("region", "未配置")), 62), 12)
	_draw_label(rect.position + Vector2(24.0, 130.0), _ellipsize("当前事项：" + str(profile.get("plan", "未配置")), 62), 12)
	_draw_label(rect.position + Vector2(24.0, 158.0), _ellipsize("关注：" + str(profile.get("primary_concern", "未配置")), 62), 12)
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 150.0, 32.0), "切换角色视角", "switch_character", _character_profiles.size() > 1)


func _draw_activity_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), "已知信息与机构议程", 19)
	var y: float = rect.position.y + 66.0
	var count: int = mini(_world_events.size(), 6)
	for index: int in range(count):
		var event: Dictionary = _world_events[index]
		var event_id: String = str(event.get("id", ""))
		var row: Rect2 = Rect2(rect.position.x + 24.0, y, rect.size.x - 48.0, 27.0)
		_panel(row, Color(0.055, 0.075, 0.072, 0.82), Color(0.48, 0.62, 0.56, 0.22))
		_register_hit(row, "inspect_event:" + event_id, true)
		_draw_label(row.position + Vector2(8.0, 18.0), _ellipsize("• " + str(event.get("title", "状态")), 58), 10)
		y += 31.0
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 42.0, 118.0, 28.0), "标记已读", "mark_read", activity_unread > 0)


func _draw_time_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), "时间与速度", 19)
	_draw_label(rect.position + Vector2(24.0, 78.0), _format_sim_datetime(), 15)
	_draw_label(rect.position + Vector2(24.0, 110.0), "样机本地时钟，不修改正式时间系统", 12, Color(0.73, 0.82, 0.78, 1.0))
	_draw_button(Rect2(rect.position.x + 24.0, rect.position.y + 142.0, 74.0, 30.0), "暂停" if not sim_paused else "继续", "toggle_pause", true)
	_draw_button(Rect2(rect.position.x + 110.0, rect.position.y + 142.0, 56.0, 30.0), "1×", "speed:1", true)
	_draw_button(Rect2(rect.position.x + 176.0, rect.position.y + 142.0, 56.0, 30.0), "2×", "speed:2", true)
	_draw_button(Rect2(rect.position.x + 242.0, rect.position.y + 142.0, 56.0, 30.0), "4×", "speed:4", true)


func _draw_data_errors() -> void:
	if _data_errors.is_empty():
		return
	var rect: Rect2 = Rect2(size.x * 0.25, size.y - 126.0, size.x * 0.5, 48.0)
	_panel(rect, Color(0.18, 0.04, 0.03, 0.94), Color(0.92, 0.44, 0.28, 0.72))
	_draw_label(rect.position + Vector2(12.0, 28.0), _ellipsize("数据错误：" + "; ".join(_data_errors), 80), 12)


func _draw_button(rect: Rect2, label: String, action: String, enabled: bool) -> void:
	_register_hit(rect, action, enabled)
	var fill: Color = Color(0.08, 0.10, 0.095, 0.90) if enabled else Color(0.05, 0.055, 0.052, 0.68)
	var border: Color = Color(0.72, 0.64, 0.38, 0.34) if enabled else Color(0.36, 0.34, 0.28, 0.22)
	_panel(rect, fill, border)
	_draw_label(rect.position + Vector2(10.0, rect.size.y * 0.64), label, 11, Color(0.90, 0.91, 0.84, 1.0) if enabled else Color(0.55, 0.57, 0.53, 1.0))


func _register_hit(rect: Rect2, action: String, enabled: bool) -> void:
	_button_hits.append({"rect": rect, "action": action, "enabled": enabled})


func _position_hits_ui(position: Vector2) -> bool:
	for record: Dictionary in _button_hits:
		var rect: Rect2 = record.get("rect", Rect2()) as Rect2
		if rect.has_point(position):
			return true
	return false


func _handle_button_click(position: Vector2) -> bool:
	for index: int in range(_button_hits.size() - 1, -1, -1):
		var record: Dictionary = _button_hits[index]
		var rect: Rect2 = record.get("rect", Rect2()) as Rect2
		if not rect.has_point(position):
			continue
		if bool(record.get("enabled", false)):
			_activate_button(str(record.get("action", "")))
		return true
	return false


func _activate_button(action: String) -> void:
	if action == "noop":
		return
	if action == "layout_focus":
		_set_layout(LAYOUT_FOCUS)
	elif action == "layout_workspace":
		_set_layout(LAYOUT_WORKSPACE)
	elif action == "toggle_workspace":
		workspace_open = not workspace_open
		_apply_layout()
		_mark_projection_dirty()
		queue_redraw()
	elif action == "focus_country":
		_focus_selected_country()
	elif action == "focus_france":
		selected_country_id = FOCUS_COUNTRY_ID
		active_hud_panel = ""
		_focus_selected_country()
	elif action == "overview_world":
		_return_to_global_world()
	elif action == "locate_event":
		_locate_selected_event()
	elif action == "enter_region":
		_enter_region()
	elif action.begins_with("enter_city:"):
		_enter_city(action.get_slice(":", 1))
	elif action.begins_with("inspect_institution:"):
		selected_institution_id = action.get_slice(":", 1)
		_set_info_open(true)
	elif action.begins_with("inspect_event:"):
		_show_event_from_hud(action.get_slice(":", 1))
	elif action == "close_info":
		_set_info_open(false)
	elif action == "back":
		_go_back()
	elif action == "world":
		space_level = WORLD
		world_mode = WORLD_COUNTRIES
		_set_world_layer_visible(true)
		_set_info_open(false)
		_mark_projection_dirty()
		queue_redraw()
	elif action == "toggle_country_panel":
		_toggle_hud_panel("country")
	elif action == "toggle_character_panel":
		_toggle_hud_panel("character")
	elif action == "toggle_activity_panel":
		_toggle_hud_panel("activity")
	elif action == "toggle_time_panel":
		_toggle_hud_panel("time")
	elif action == "close_hud_panel":
		active_hud_panel = ""
		queue_redraw()
	elif action == "switch_character":
		_switch_character()
	elif action == "mark_read":
		activity_unread = 0
		queue_redraw()
	elif action == "toggle_pause":
		sim_paused = not sim_paused
		queue_redraw()
	elif action.begins_with("speed:"):
		sim_speed = maxi(1, int(action.get_slice(":", 1)))
		sim_paused = false
		queue_redraw()


func _focus_selected_country() -> void:
	if selected_country_id != FOCUS_COUNTRY_ID:
		return
	space_level = WORLD
	world_mode = WORLD_COUNTRY_FOCUS
	selected_event_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	hover_country_id = ""
	hover_event_id = ""
	hover_region_id = ""
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	_set_world_layer_visible(true)
	_set_info_open(false)
	_mark_projection_dirty()
	queue_redraw()


func _show_event_from_hud(event_id: String) -> void:
	if not _event_by_id.has(event_id):
		return
	active_hud_panel = ""
	space_level = WORLD
	world_mode = WORLD_COUNTRIES
	selected_event_id = event_id
	selected_country_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	hover_country_id = ""
	hover_event_id = ""
	hover_region_id = ""
	_set_world_layer_visible(true)
	_mark_projection_dirty()
	_set_info_open(true)
	queue_redraw()


func _return_to_global_world() -> void:
	space_level = WORLD
	world_mode = WORLD_COUNTRIES
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	hover_region_id = ""
	_set_world_layer_visible(true)
	_set_info_open(false)
	_mark_projection_dirty()
	queue_redraw()


func _locate_selected_event() -> void:
	var event: Dictionary = _event_by_id.get(selected_event_id, {}) as Dictionary
	var region_id: String = str(event.get("region_id", ""))
	if region_id.is_empty():
		return
	selected_country_id = FOCUS_COUNTRY_ID
	world_mode = WORLD_COUNTRY_FOCUS
	selected_region_id = region_id
	selected_event_id = ""
	_mark_projection_dirty()
	_set_info_open(true)
	queue_redraw()


func _enter_region() -> void:
	if selected_region_id.is_empty():
		return
	space_level = REGION
	_set_info_open(false)
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	_set_world_layer_visible(false)
	queue_redraw()


func _enter_city(city_id: String) -> void:
	if city_id.is_empty() or not _city_by_id.has(city_id):
		return
	selected_city_id = city_id
	selected_institution_id = ""
	space_level = CITY
	set_process(false)
	_set_world_layer_visible(false)
	queue_redraw()


func _go_back() -> void:
	if not active_hud_panel.is_empty():
		active_hud_panel = ""
		queue_redraw()
		return
	if info_open or info_progress > 0.01:
		_set_info_open(false)
		return
	if space_level == CITY:
		space_level = REGION
		selected_institution_id = ""
	elif space_level == REGION:
		space_level = WORLD
		world_mode = WORLD_COUNTRY_FOCUS
		_set_world_layer_visible(true)
		_mark_projection_dirty()
	elif world_mode == WORLD_COUNTRY_FOCUS:
		_return_to_global_world()
	queue_redraw()


func _toggle_hud_panel(panel: String) -> void:
	active_hud_panel = "" if active_hud_panel == panel else panel
	queue_redraw()


func _switch_character() -> void:
	var keys: Array = _character_profiles.keys()
	if keys.size() < 2:
		return
	var current_index: int = keys.find(active_character_key)
	active_character_key = str(keys[(current_index + 1) % keys.size()])
	queue_redraw()


func _active_character_name() -> String:
	var profile: Dictionary = _character_profiles.get(active_character_key, {}) as Dictionary
	return str(profile.get("display_name_zh", profile.get("name", "玩家角色")))


func _active_character_position() -> String:
	var profile: Dictionary = _character_profiles.get(active_character_key, {}) as Dictionary
	return str(profile.get("position", profile.get("occupation", "个人层级入口")))


func _activity_summary() -> String:
	if _world_events.is_empty():
		return "暂无已知信息"
	return _ellipsize(str(_world_events[0].get("title", "机构议程")), 22)


func _workspace_selection_name() -> String:
	if world_mode == WORLD_COUNTRIES:
		var country: Dictionary = _country_by_id.get(selected_country_id, {}) as Dictionary
		return str(country.get("name", "未选择国家"))
	return _selected_region_name()


func _breadcrumb_text() -> String:
	var text: String = "世界"
	if world_mode == WORLD_COUNTRY_FOCUS or space_level != WORLD:
		text += " / 法兰西第三共和国"
	if not selected_region_id.is_empty() and (world_mode == WORLD_COUNTRY_FOCUS or space_level != WORLD):
		text += " / " + _selected_region_name()
	if space_level == CITY:
		text += " / " + _city_name()
	return text


func _selected_region_name() -> String:
	var region: Dictionary = _region_by_id.get(selected_region_id, {}) as Dictionary
	return str(region.get("display_name_zh", "未选择"))


func _city_name() -> String:
	var city: Dictionary = _city_by_id.get(selected_city_id, {}) as Dictionary
	return str(city.get("name", "城市"))


func _format_sim_datetime() -> String:
	return "%04d年%02d月%02d日 %02d:%02d" % [sim_year, sim_month, sim_day, sim_hour, sim_minute]


func _advance_clock(minutes: int) -> void:
	sim_minute += minutes
	while sim_minute >= 60:
		sim_minute -= 60
		sim_hour += 1
	while sim_hour >= 24:
		sim_hour -= 24
		sim_day += 1
	if sim_day > 31:
		sim_day = 1
		sim_month += 1
	if sim_month > 12:
		sim_month = 1
		sim_year += 1


func _lon_lat_from_record(record: Dictionary, key: String) -> Variant:
	var value: Variant = record.get(key, [])
	if value is Array:
		var array: Array = value as Array
		if array.size() >= 2:
			return Vector2(float(array[0]), float(array[1]))
	return null


func _all_region_polygons() -> Array:
	var output: Array = []
	for region_key_value: Variant in _region_polygons.keys():
		var polygons: Array = _region_polygons.get(str(region_key_value), []) as Array
		for polygon_value: Variant in polygons:
			output.append(polygon_value)
	return output


func _lon_lat_bounds(polygons: Array) -> Rect2:
	var has_point: bool = false
	var minimum: Vector2 = Vector2(999.0, 999.0)
	var maximum: Vector2 = Vector2(-999.0, -999.0)
	for polygon_value: Variant in polygons:
		var polygon: PackedVector2Array = polygon_value
		for point: Vector2 in polygon:
			has_point = true
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
	if not has_point:
		return Rect2(Vector2(-5.0, 42.0), Vector2(12.0, 10.0))
	return Rect2(minimum, maximum - minimum)


func _lon_lat_to_rect(lon_lat: Vector2, bounds: Rect2, rect: Rect2) -> Vector2:
	var safe_width: float = maxf(bounds.size.x, 0.001)
	var safe_height: float = maxf(bounds.size.y, 0.001)
	var x: float = rect.position.x + ((lon_lat.x - bounds.position.x) / safe_width) * rect.size.x
	var y: float = rect.end.y - ((lon_lat.y - bounds.position.y) / safe_height) * rect.size.y
	return Vector2(x, y)


func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 1.0)


func _draw_label(position: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0)) -> void:
	draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _ellipsize(value: String, maximum_characters: int) -> String:
	if maximum_characters <= 1 or value.length() <= maximum_characters:
		return value
	return value.left(maximum_characters - 1) + "…"
