class_name HolographicWorkspaceSpike
extends Control

const WORLD := "world"
const REGION := "region"
const CITY := "city"
const WORLD_COUNTRIES := "countries"
const WORLD_COUNTRY_FOCUS := "country_focus"
const LAYOUT_FOCUS := 0
const LAYOUT_WORKSPACE := 1

const CAMERA_ORTHO_SIZE := 2.55
const EDGE_BAND := 58.0
const DRAG_THRESHOLD := 5.0
const MOTION_EPSILON := 0.0005
const FOCUS_VIEWPORT_SIZE := Vector2i(720, 600)
const WORKSPACE_VIEWPORT_SIZE := Vector2i(600, 520)
const FOCUS_COUNTRY_ID := "country_fra"

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
var drag_start := Vector2.ZERO
var drag_last := Vector2.ZERO
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
var _country_lonlat_polygons: Dictionary = {}
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
var _hemisphere_center := Vector2.ZERO
var _hemisphere_rect := Rect2()
var _hemisphere_radius: float = 220.0
var _focus_bounds := Rect2(Vector2(-5.5, 41.0), Vector2(12.5, 11.0))

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
	var hover_spin := _edge_hover_spin()
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
	var key_event := event as InputEventKey
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
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			if _handle_button_click(mouse_button.position):
				accept_event()
				return

	if space_level != WORLD:
		return

	if world_mode == WORLD_COUNTRY_FOCUS:
		if event is InputEventMouseMotion:
			var focus_motion := event as InputEventMouseMotion
			if _position_hits_ui(focus_motion.position):
				return
			_select_focus_region_at(focus_motion.position, false)
		elif event is InputEventMouseButton:
			var focus_button := event as InputEventMouseButton
			if focus_button.button_index == MOUSE_BUTTON_LEFT and focus_button.pressed:
				_select_focus_region_at(focus_button.position, true)
				accept_event()
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
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
		var mouse_motion := event as InputEventMouseMotion
		if not dragging and _position_hits_ui(mouse_motion.position):
			return
		if dragging:
			var motion_delta := mouse_motion.position - drag_last
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
	var world_document := _read_document("res://data/world_map/world_coastlines.json")
	_load_countries_and_coastlines(world_document)

	var regions_document := _read_document("res://data/world_map/regions.json")
	_load_regions(regions_document)

	var cities_document := _read_document("res://data/world_map/cities.json")
	_cities = _dictionary_array(cities_document, "cities")
	for city in _cities:
		var city_id := str(city.get("id", ""))
		var region_id := str(city.get("parent_region_id", ""))
		_city_by_id[city_id] = city
		if not region_id.is_empty():
			if not _cities_by_region.has(region_id):
				_cities_by_region[region_id] = []
			var city_ids: Array = _cities_by_region[region_id]
			city_ids.append(city_id)
			_cities_by_region[region_id] = city_ids

	var institutions_document := _read_document("res://data/world_map/institutions.json")
	_country_profile = institutions_document.get("country", {}) as Dictionary
	_institutions = _dictionary_array(institutions_document, "institutions")
	for institution in _institutions:
		var institution_id := str(institution.get("id", ""))
		var city_id := str(institution.get("city_id", ""))
		var region_id := str(institution.get("parent_region_id", ""))
		_institution_by_id[institution_id] = institution
		if not city_id.is_empty():
			if not _institutions_by_city.has(city_id):
				_institutions_by_city[city_id] = []
			var city_institutions: Array = _institutions_by_city[city_id]
			city_institutions.append(institution_id)
			_institutions_by_city[city_id] = city_institutions
		if not region_id.is_empty():
			if not _institutions_by_region.has(region_id):
				_institutions_by_region[region_id] = []
			var region_institutions: Array = _institutions_by_region[region_id]
			region_institutions.append(institution_id)
			_institutions_by_region[region_id] = region_institutions

	var characters_document := _read_document("res://data/world_map/characters.json")
	var identities: Dictionary = characters_document.get("identities", {}) as Dictionary
	for key in identities.keys():
		var profile: Variant = identities[key]
		if profile is Dictionary:
			_character_profiles[str(key)] = profile

	_seed_world_events()
	_focus_bounds = _lon_lat_bounds(_all_region_polygons())
	_mark_projection_dirty()


func _load_countries_and_coastlines(document: Dictionary) -> void:
	for feature_value in document.get("features", []):
		if not feature_value is Dictionary:
			continue
		var feature := feature_value as Dictionary
		var iso := str(feature.get("iso_a3", feature.get("source_iso_a3", ""))).to_upper()
		var country_id := _country_id_from_feature(feature, iso)
		var lonlat_polygons: Array = []
		var unit_polygons: Array = []
		var largest_score := -1.0
		var largest_units := PackedVector3Array()
		for polygon_value in feature.get("polygons", []):
			if not polygon_value is Dictionary:
				continue
			var raw_outer: Variant = (polygon_value as Dictionary).get("outer", [])
			var outer := _points_from_raw(raw_outer)
			if outer.size() < 3:
				continue
			var simplified := _simplify_line(outer, 96)
			var unit_line := _to_unit_line(simplified)
			lonlat_polygons.append(simplified)
			unit_polygons.append(unit_line)
			_coastline_unit_lines.append(unit_line)
			var score := absf(_polygon_area_score(simplified))
			if score > largest_score:
				largest_score = score
				largest_units = unit_line
		if lonlat_polygons.is_empty():
			continue
		var record := {
			"id": country_id,
			"iso_a3": iso,
			"name": str(feature.get("display_name_zh", feature.get("name", iso))),
			"native_name": str(feature.get("name", iso)),
			"label_rank": int(feature.get("label_rank", 9)),
		}
		_countries.append(record)
		_country_by_id[country_id] = record
		_country_lonlat_polygons[country_id] = lonlat_polygons
		_country_unit_polygons[country_id] = unit_polygons
		_country_anchor_units[country_id] = _average_unit(largest_units)


func _load_regions(document: Dictionary) -> void:
	_regions = _dictionary_array(document, "regions")
	var administrative_by_id: Dictionary = {}
	for unit_value in document.get("administrative_units", []):
		if unit_value is Dictionary:
			var unit := unit_value as Dictionary
			administrative_by_id[str(unit.get("id", ""))] = unit

	for region in _regions:
		var region_id := str(region.get("id", ""))
		_region_by_id[region_id] = region
		var polygons: Array = []
		for unit_id in region.get("administrative_unit_ids", []):
			var unit: Dictionary = administrative_by_id.get(str(unit_id), {})
			for geometry_value in unit.get("geometry", []):
				if not geometry_value is Dictionary:
					continue
				var outer := _points_from_raw((geometry_value as Dictionary).get("outer", []))
				if outer.size() > 2:
					polygons.append(_simplify_line(outer, 140))
		_region_polygons[region_id] = polygons


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_data_errors.append("无法读取：" + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	_data_errors.append("JSON格式无效：" + path)
	return {}


func _dictionary_array(document: Dictionary, key: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in document.get(key, []):
		if value is Dictionary:
			output.append(value)
	return output


func _country_id_from_feature(feature: Dictionary, iso: String) -> String:
	if iso == "FRA":
		return FOCUS_COUNTRY_ID
	if not iso.is_empty() and iso != "-99":
		return "country_" + iso.to_lower()
	return "country_" + str(feature.get("stable_id", feature.get("id", "unknown")))


func _points_from_raw(raw_points: Variant) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not raw_points is Array:
		return points
	for point in raw_points:
		if point is Array and (point as Array).size() >= 2:
			points.append(Vector2(float(point[0]), float(point[1])))
	return points


func _to_unit_line(points: PackedVector2Array) -> PackedVector3Array:
	var output := PackedVector3Array()
	for lon_lat in points:
		output.append(_lon_lat_to_unit(lon_lat))
	return output


func _lon_lat_to_unit(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	return Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))


func _average_unit(points: PackedVector3Array) -> Vector3:
	if points.is_empty():
		return Vector3.FORWARD
	var total := Vector3.ZERO
	for point in points:
		total += point
	if total.length_squared() < 0.000001:
		return points[0].normalized()
	return total.normalized()


func _polygon_area_score(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _simplify_line(points: PackedVector2Array, max_points: int) -> PackedVector2Array:
	if points.size() <= max_points:
		return points
	var closed := points[0].distance_squared_to(points[points.size() - 1]) < 0.0000001
	var source := PackedVector2Array(points)
	if closed:
		source.resize(source.size() - 1)
	var bounds := _lon_lat_bounds([source])
	var epsilon := maxf(0.0001, bounds.size.length() * 0.0008)
	var simplified := _rdp(source, epsilon)
	while simplified.size() > max_points:
		epsilon *= 1.45
		simplified = _rdp(source, epsilon)
	if closed and not simplified.is_empty():
		simplified.append(simplified[0])
	return simplified


func _rdp(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var maximum_distance := 0.0
	var split_index := 0
	var start := points[0]
	var finish := points[points.size() - 1]
	for index in range(1, points.size() - 1):
		var distance := _point_segment_distance(points[index], start, finish)
		if distance > maximum_distance:
			maximum_distance = distance
			split_index = index
	if maximum_distance <= epsilon:
		return PackedVector2Array([start, finish])
	var left := _rdp(points.slice(0, split_index + 1), epsilon)
	var right := _rdp(points.slice(split_index, points.size()), epsilon)
	left.resize(left.size() - 1)
	left.append_array(right)
	return left


func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _seed_world_events() -> void:
	var event_index := 0
	for institution in _institutions:
		if event_index >= 6:
			break
		var lon_lat := _lon_lat_from_record(institution, "lon_lat")
		var agenda := str(institution.get("agenda", ""))
		if lon_lat == null or agenda.is_empty():
			continue
		var event_id := "institution_agenda_" + str(event_index)
		var event := {
			"id": event_id,
			"title": agenda,
			"source": str(institution.get("name", "机构")),
			"lon_lat": lon_lat,
			"unit": _lon_lat_to_unit(lon_lat),
			"region_id": str(institution.get("parent_region_id", "")),
			"country_id": str(institution.get("parent_country_id", FOCUS_COUNTRY_ID)),
			"severity": 2 if event_index < 2 else 1,
		}
		_world_events.append(event)
		_event_by_id[event_id] = event
		event_index += 1


func _apply_layout() -> void:
	var desired := FOCUS_VIEWPORT_SIZE if layout_mode_id == LAYOUT_FOCUS else WORKSPACE_VIEWPORT_SIZE
	var reserved_right := 24.0
	if layout_mode_id == LAYOUT_WORKSPACE and workspace_open:
		reserved_right = minf(390.0, maxf(260.0, size.x * 0.32))
	var available_width := maxf(240.0, size.x - reserved_right - 36.0)
	var available_height := maxf(220.0, size.y - 104.0)
	var scale_factor := minf(1.0, minf(available_width / float(desired.x), available_height / float(desired.y)))
	var viewport_width := mini(int(round(float(desired.x) * scale_factor)), int(available_width))
	var viewport_height := mini(int(round(float(desired.y) * scale_factor)), int(available_height))
	viewport_width = maxi(240, viewport_width)
	viewport_height = maxi(220, viewport_height)
	var viewport_size := Vector2i(viewport_width, viewport_height)
	viewport_container.size = Vector2(viewport_size)

	var available_left_width := size.x - reserved_right
	var x := maxf(12.0, (available_left_width - float(viewport_size.x)) * 0.5)
	var y := maxf(80.0, (size.y - float(viewport_size.y)) * 0.5)
	viewport_container.position = Vector2(x, y)

	_hemisphere_center = viewport_container.position + Vector2(viewport_size) * 0.5
	_hemisphere_radius = minf(float(viewport_size.y) / CAMERA_ORTHO_SIZE, float(viewport_size.x) * 0.49)
	_hemisphere_rect = Rect2(
		_hemisphere_center - Vector2(_hemisphere_radius, _hemisphere_radius),
		Vector2(_hemisphere_radius * 2.0, _hemisphere_radius * 2.0)
	)
	_mark_projection_dirty()


func _set_layout(id: int) -> void:
	layout_mode_id = id
	if id == LAYOUT_WORKSPACE:
		workspace_open = true
	_apply_layout()
	_set_world_layer_visible(space_level == WORLD)
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
	var pos := get_local_mouse_position()
	if not _hemisphere_rect.has_point(pos):
		return 0.0
	var left_power := clampf((_hemisphere_rect.position.x + EDGE_BAND - pos.x) / EDGE_BAND, 0.0, 1.0)
	var right_power := clampf((pos.x - (_hemisphere_rect.end.x - EDGE_BAND)) / EDGE_BAND, 0.0, 1.0)
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
	if world_mode == WORLD_COUNTRIES:
		_rebuild_global_projection_cache()
	else:
		_rebuild_country_focus_cache()


func _rebuild_global_projection_cache() -> void:
	var rotation := Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	for unit_line in _coastline_unit_lines:
		var segments := _project_unit_line(unit_line, rotation)
		for segment in segments:
			_global_screen_segments.append(segment)

	var selected_polygons: Array = _country_unit_polygons.get(selected_country_id, [])
	for polygon in selected_polygons:
		var selected_segments := _project_unit_line(polygon, rotation)
		for segment in selected_segments:
			_selected_country_segments.append(segment)

	for country in _countries:
		if not _country_is_clickable(country):
			continue
		var country_id := str(country.get("id", ""))
		var unit: Vector3 = _country_anchor_units.get(country_id, Vector3.ZERO)
		var rotated := rotation * unit
		if rotated.z >= 0.0:
			_country_screen_anchors[country_id] = _rotated_to_screen(rotated)

	for event in _world_events:
		var event_unit: Vector3 = event.get("unit", Vector3.ZERO)
		var rotated: Vector3 = rotation * event_unit
		if rotated.z >= 0.0:
			_event_screen_positions[str(event.get("id", ""))] = _rotated_to_screen(rotated)


func _rebuild_country_focus_cache() -> void:
	var map_rect := _focus_map_rect()
	var country_polygons: Array = _country_lonlat_polygons.get(FOCUS_COUNTRY_ID, [])
	for polygon in country_polygons:
		if not _polygon_overlaps_bounds(polygon, _focus_bounds):
			continue
		var flat := PackedVector2Array()
		for lon_lat in polygon:
			flat.append(_lon_lat_to_rect(lon_lat, _focus_bounds, map_rect))
		if flat.size() > 2:
			_focus_country_screen_polygons.append(flat)

	for region in _regions:
		var region_id := str(region.get("id", ""))
		var screen_polygons: Array = []
		for polygon in _region_polygons.get(region_id, []):
			var flat := PackedVector2Array()
			for lon_lat in polygon:
				flat.append(_lon_lat_to_rect(lon_lat, _focus_bounds, map_rect))
			if flat.size() > 2:
				screen_polygons.append(flat)
		_focus_region_screen_polygons[region_id] = screen_polygons
		var anchor := _lon_lat_from_record(region, "label_lon_lat")
		if anchor != null:
			_focus_region_screen_anchors[region_id] = _lon_lat_to_rect(anchor, _focus_bounds, map_rect)


func _project_unit_line(unit_line: PackedVector3Array, rotation: Basis) -> Array:
	var output: Array = []
	if unit_line.size() < 2:
		return output
	var segment := PackedVector2Array()
	var previous := rotation * unit_line[0]
	var previous_visible := previous.z >= 0.0
	if previous_visible:
		segment.append(_rotated_to_screen(previous))
	for index in range(1, unit_line.size()):
		var current := rotation * unit_line[index]
		var current_visible := current.z >= 0.0
		if current_visible == previous_visible:
			if current_visible:
				segment.append(_rotated_to_screen(current))
		else:
			var denominator := previous.z - current.z
			var t := 0.5 if absf(denominator) < 0.000001 else clampf(previous.z / denominator, 0.0, 1.0)
			var edge := previous.lerp(current, t)
			var edge_screen := _rotated_to_screen(edge)
			if previous_visible:
				segment.append(edge_screen)
				if segment.size() > 1:
					output.append(segment)
				segment = PackedVector2Array()
			else:
				segment = PackedVector2Array([edge_screen, _rotated_to_screen(current)])
		previous = current
		previous_visible = current_visible
	if segment.size() > 1:
		output.append(segment)
	return output


func _rotated_to_screen(point: Vector3) -> Vector2:
	return _hemisphere_center + Vector2(point.x * _hemisphere_radius, -point.y * _hemisphere_radius)


func _country_is_clickable(country: Dictionary) -> bool:
	var country_id := str(country.get("id", ""))
	return country_id == FOCUS_COUNTRY_ID or int(country.get("label_rank", 9)) <= 4


func _focus_map_rect() -> Rect2:
	var side := _hemisphere_radius * 1.46
	return Rect2(_hemisphere_center - Vector2(side, side) * 0.5, Vector2(side, side))


func _draw_world_overlay() -> void:
	_ensure_projection_cache()
	if world_mode == WORLD_COUNTRIES:
		_draw_global_world()
	else:
		_draw_country_focus()


func _draw_global_world() -> void:
	for segment in _global_screen_segments:
		draw_polyline(segment, Color(0.64, 0.84, 0.78, 0.23), 0.85, true)
	for segment in _selected_country_segments:
		draw_polyline(segment, Color(0.92, 0.77, 0.42, 0.88), 2.0, true)

	for country_id in _country_screen_anchors.keys():
		var point: Vector2 = _country_screen_anchors[country_id]
		var selected := country_id == selected_country_id
		var hovered := country_id == hover_country_id
		var radius := 5.5 if selected or hovered else 3.5
		var color := Color(0.94, 0.76, 0.40, 0.94) if selected else Color(0.72, 0.88, 0.82, 0.72)
		if hovered:
			color = Color(0.84, 0.96, 0.90, 0.98)
		draw_circle(point, radius, color)
		if selected or hovered:
			var country: Dictionary = _country_by_id.get(country_id, {})
			_draw_label(point + Vector2(9.0, -8.0), str(country.get("name", country_id)), 12)

	for event_id in _event_screen_positions.keys():
		var point: Vector2 = _event_screen_positions[event_id]
		var event: Dictionary = _event_by_id.get(event_id, {})
		var severity := int(event.get("severity", 1))
		var color := Color(0.96, 0.59, 0.28, 0.94) if severity >= 2 else Color(0.91, 0.76, 0.40, 0.82)
		var radius := 5.5 if event_id == hover_event_id or event_id == selected_event_id else 4.0
		draw_circle(point, radius + 3.0, Color(color, 0.14), false, 1.2)
		draw_circle(point, radius, color)
		if event_id == hover_event_id:
			_draw_label(point + Vector2(10.0, 4.0), str(event.get("title", "状态")), 11)


func _draw_country_focus() -> void:
	for polygon in _focus_country_screen_polygons:
		draw_colored_polygon(polygon, Color(0.16, 0.28, 0.28, 0.22))
		draw_polyline(polygon, Color(0.68, 0.84, 0.76, 0.40), 1.2, true)

	for region in _regions:
		var region_id := str(region.get("id", ""))
		var selected := region_id == selected_region_id
		var hovered := region_id == hover_region_id
		var fill := _region_color(region, 0.16)
		var border := Color(0.82, 0.77, 0.58, 0.62)
		if selected:
			fill = Color(0.84, 0.63, 0.28, 0.34)
			border = Color(0.96, 0.80, 0.42, 0.96)
		elif hovered:
			fill = Color(0.44, 0.70, 0.64, 0.28)
			border = Color(0.78, 0.94, 0.86, 0.90)
		for polygon in _focus_region_screen_polygons.get(region_id, []):
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, 1.15 if not selected else 2.0, true)
		var anchor: Vector2 = _focus_region_screen_anchors.get(region_id, Vector2.INF)
		if anchor != Vector2.INF:
			draw_circle(anchor, 4.5 if selected or hovered else 3.0, border)
			_draw_label(anchor + Vector2(7.0, -5.0), str(region.get("display_name_zh", region_id)), 10)

	_draw_label(_hemisphere_rect.position + Vector2(18.0, 28.0), "国家聚焦 · 法兰西第三共和国", 15)
	_draw_button(
		Rect2(_hemisphere_rect.position + Vector2(18.0, 42.0), Vector2(96.0, 28.0)),
		"返回全球",
		"overview_world",
		true
	)


func _region_color(region: Dictionary, alpha: float) -> Color:
	var value := str(region.get("legal_color", "#6f8d9f"))
	var color := Color(value)
	color.a = alpha
	return color


func _select_global_object_at(pos: Vector2, click: bool) -> void:
	_ensure_projection_cache()
	var nearest_event := ""
	var nearest_event_distance := 18.0
	for event_id in _event_screen_positions.keys():
		var distance := pos.distance_to(_event_screen_positions[event_id])
		if distance < nearest_event_distance:
			nearest_event = str(event_id)
			nearest_event_distance = distance

	var nearest_country := ""
	var nearest_country_distance := 26.0
	for country_id in _country_screen_anchors.keys():
		var distance := pos.distance_to(_country_screen_anchors[country_id])
		if distance < nearest_country_distance:
			nearest_country = str(country_id)
			nearest_country_distance = distance

	var next_event := nearest_event
	var next_country := "" if not nearest_event.is_empty() else nearest_country
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
		_mark_projection_dirty()
		_set_info_open(true)
	elif not nearest_country.is_empty():
		selected_country_id = nearest_country
		selected_event_id = ""
		selected_region_id = ""
		selected_institution_id = ""
		_mark_projection_dirty()
		_set_info_open(true)


func _select_focus_region_at(pos: Vector2, click: bool) -> void:
	_ensure_projection_cache()
	var best := ""
	for region_id in _focus_region_screen_polygons.keys():
		for polygon in _focus_region_screen_polygons[region_id]:
			if Geometry2D.is_point_in_polygon(pos, polygon):
				best = str(region_id)
				break
		if not best.is_empty():
			break
	if best.is_empty():
		var nearest_distance := 24.0
		for region_id in _focus_region_screen_anchors.keys():
			var distance := pos.distance_to(_focus_region_screen_anchors[region_id])
			if distance < nearest_distance:
				best = str(region_id)
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
	var rect := _main_content_rect(120.0, 118.0, 82.0)
	_panel(rect, Color(0.025, 0.047, 0.052, 0.94), Color(0.70, 0.62, 0.36, 0.32))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(rect.position + Vector2(24.0, 34.0), "二维大区层 · " + str(region.get("display_name_zh", "选中大区")), 17)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		"行政边界、城市与机构来自现有数据；城市联系线按现有城市坐标派生",
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_region_flat_geometry(rect)
	_draw_region_cities_and_routes(rect)
	_draw_region_institutions(rect)


func _draw_region_flat_geometry(rect: Rect2) -> void:
	var polygons: Array = _region_polygons.get(selected_region_id, [])
	var bounds := _lon_lat_bounds(polygons)
	var map_rect := _region_map_rect(rect)
	for polygon in polygons:
		var flat := PackedVector2Array()
		for lon_lat in polygon:
			flat.append(_lon_lat_to_rect(lon_lat, bounds, map_rect))
		if flat.size() > 2:
			draw_colored_polygon(flat, Color(0.32, 0.48, 0.48, 0.20))
			draw_polyline(flat, Color(0.83, 0.75, 0.48, 0.70), 1.4, true)


func _draw_region_cities_and_routes(rect: Rect2) -> void:
	var city_ids: Array = _cities_by_region.get(selected_region_id, [])
	if city_ids.is_empty():
		_draw_label(
			rect.position + Vector2(86.0, rect.size.y - 60.0),
			"当前大区没有配置城市入口",
			13,
			Color(0.95, 0.72, 0.43, 1.0)
		)
		return

	var polygons: Array = _region_polygons.get(selected_region_id, [])
	var bounds := _lon_lat_bounds(polygons)
	var map_rect := _region_map_rect(rect)
	var city_records: Array = []
	for city_id in city_ids:
		var city: Dictionary = _city_by_id.get(str(city_id), {})
		if _lon_lat_from_record(city, "lon_lat") != null:
			city_records.append(city)
	city_records.sort_custom(Callable(self, "_city_lon_less"))

	var city_points: Array[Vector2] = []
	for city in city_records:
		var lon_lat: Vector2 = _lon_lat_from_record(city, "lon_lat")
		city_points.append(_lon_lat_to_rect(lon_lat, bounds, map_rect))
	for index in range(city_points.size() - 1):
		draw_line(city_points[index], city_points[index + 1], Color(0.55, 0.75, 0.68, 0.36), 1.8)

	var list_x := rect.end.x - 174.0
	var list_y := rect.position.y + 88.0
	for index in range(mini(city_records.size(), 8)):
		var city: Dictionary = city_records[index]
		var city_id := str(city.get("id", ""))
		var point := city_points[index]
		draw_circle(point, 7.0, Color(0.88, 0.74, 0.42, 0.92))
		_draw_label(point + Vector2(10.0, 4.0), str(city.get("name", "城市")), 12)
		_register_hit(Rect2(point - Vector2(12.0, 12.0), Vector2(24.0, 24.0)), "enter_city:" + city_id, true)
		_draw_button(
			Rect2(list_x, list_y + float(index) * 34.0, 142.0, 27.0),
			"进入 " + str(city.get("name", "城市")),
			"enter_city:" + city_id,
			true
		)


func _draw_region_institutions(rect: Rect2) -> void:
	var institution_ids: Array = _institutions_by_region.get(selected_region_id, [])
	if institution_ids.is_empty():
		return
	var bounds := _lon_lat_bounds(_region_polygons.get(selected_region_id, []))
	var map_rect := _region_map_rect(rect)
	for institution_id in institution_ids:
		var institution: Dictionary = _institution_by_id.get(str(institution_id), {})
		var lon_lat := _lon_lat_from_record(institution, "lon_lat")
		if lon_lat == null:
			continue
		var point := _lon_lat_to_rect(lon_lat, bounds, map_rect)
		draw_rect(Rect2(point - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), Color(0.82, 0.90, 0.78, 0.86))


func _region_map_rect(rect: Rect2) -> Rect2:
	var map_rect := rect.grow(-70.0)
	map_rect.size = Vector2(maxf(220.0, map_rect.size.x - 190.0), map_rect.size.y)
	return map_rect


func _city_lon_less(a: Dictionary, b: Dictionary) -> bool:
	var a_lon_lat := _lon_lat_from_record(a, "lon_lat")
	var b_lon_lat := _lon_lat_from_record(b, "lon_lat")
	if a_lon_lat == null:
		return false
	if b_lon_lat == null:
		return true
	var a_point: Vector2 = a_lon_lat
	var b_point: Vector2 = b_lon_lat
	return a_point.x < b_point.x


func _draw_city_map() -> void:
	var rect := _main_content_rect(120.0, 118.0, 82.0)
	_panel(rect, Color(0.03, 0.04, 0.04, 0.94), Color(0.72, 0.75, 0.66, 0.24))
	var city: Dictionary = _city_by_id.get(selected_city_id, {})
	_draw_label(rect.position + Vector2(24.0, 34.0), "城市本地层 · " + str(city.get("name", "本地城市")), 17)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		"显示该城市已配置的正式机构与人物；未配置对象不会用虚构地点补齐",
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_city_institutions(rect)
	_draw_city_characters(rect)


func _draw_city_institutions(rect: Rect2) -> void:
	var institution_ids: Array = _institutions_by_city.get(selected_city_id, [])
	if institution_ids.is_empty():
		_draw_label(rect.position + Vector2(40.0, 126.0), "当前城市没有配置正式机构节点。", 14, Color(0.95, 0.72, 0.43, 1.0))
		return

	var node_positions: Dictionary = {}
	var columns := 3
	var usable_width := maxf(360.0, rect.size.x - 96.0)
	for index in range(institution_ids.size()):
		var column := index % columns
		var row := int(index / columns)
		var point := rect.position + Vector2(
			72.0 + usable_width * (float(column) / float(maxi(1, columns - 1))),
			145.0 + float(row) * 118.0
		)
		node_positions[str(institution_ids[index])] = point

	for institution_id in institution_ids:
		var institution: Dictionary = _institution_by_id.get(str(institution_id), {})
		var parent_id := str(institution.get("parent_institution_id", ""))
		if node_positions.has(parent_id):
			draw_line(node_positions[parent_id], node_positions[str(institution_id)], Color(0.58, 0.70, 0.64, 0.34), 1.8)

	for institution_id in institution_ids:
		var institution: Dictionary = _institution_by_id.get(str(institution_id), {})
		var point: Vector2 = node_positions[str(institution_id)]
		var node_rect := Rect2(point - Vector2(72.0, 28.0), Vector2(144.0, 56.0))
		_panel(node_rect, Color(0.08, 0.12, 0.115, 0.90), Color(0.74, 0.68, 0.44, 0.42))
		_draw_label(node_rect.position + Vector2(10.0, 23.0), str(institution.get("name", "机构")), 12)
		_draw_label(node_rect.position + Vector2(10.0, 43.0), str(institution.get("department", institution.get("institution_kind", ""))), 10, Color(0.72, 0.82, 0.76, 1.0))
		_register_hit(node_rect, "inspect_institution:" + str(institution_id), true)


func _draw_city_characters(rect: Rect2) -> void:
	var x := rect.position.x + 34.0
	var y := rect.end.y - 54.0
	for key in _character_profiles.keys():
		var profile: Dictionary = _character_profiles[key]
		if str(profile.get("city_id", "")) != selected_city_id:
			continue
		var badge := Rect2(x, y, 210.0, 30.0)
		_panel(badge, Color(0.07, 0.10, 0.095, 0.88), Color(0.54, 0.70, 0.63, 0.34))
		_draw_label(badge.position + Vector2(10.0, 20.0), str(profile.get("display_name_zh", profile.get("name", "人物"))) + " · " + str(profile.get("position", "")), 11)
		x += 222.0


func _main_content_rect(preferred_margin: float, top: float, bottom: float) -> Rect2:
	var margin := minf(preferred_margin, maxf(18.0, (size.x - 520.0) * 0.5))
	var width := maxf(360.0, size.x - margin * 2.0)
	var height := maxf(280.0, size.y - top - bottom)
	return Rect2(margin, top, width, height)


func _draw_corners() -> void:
	var compact := size.x < 940.0 or size.y < 620.0
	var left_width := minf(284.0, size.x * 0.42)
	var right_width := minf(282.0, size.x * 0.42)
	var top_height := 66.0 if not compact else 56.0
	var bottom_height := 70.0 if not compact else 58.0
	var country_rect := Rect2(18.0, 18.0, left_width, top_height)
	var time_rect := Rect2(size.x - right_width - 18.0, 18.0, right_width, top_height)
	var character_rect := Rect2(18.0, size.y - bottom_height - 18.0, left_width, bottom_height)
	var activity_rect := Rect2(size.x - right_width - 18.0, size.y - bottom_height - 18.0, right_width, bottom_height)

	_draw_corner(country_rect, "法兰西第三共和国", "国家 / 政权 / 机构", "toggle_country_panel", Color(0.72, 0.64, 0.38, 0.22), compact)
	_draw_corner(character_rect, _active_character_name(), _active_character_position(), "toggle_character_panel", Color(0.72, 0.64, 0.38, 0.22), compact)
	_draw_corner(activity_rect, "已知信息 · 未读 %d" % activity_unread, _activity_summary(), "toggle_activity_panel", Color(0.72, 0.50, 0.25, 0.22), compact)

	_panel(time_rect, Color(0.025, 0.055, 0.06, 0.88), Color(0.72, 0.64, 0.38, 0.22))
	_register_hit(time_rect, "toggle_time_panel", true)
	_draw_label(time_rect.position + Vector2(12.0, 22.0), _format_sim_datetime(), 13)
	var button_y := time_rect.end.y - 28.0
	_draw_button(Rect2(time_rect.position.x + 10.0, button_y, 44.0, 22.0), "Ⅱ" if sim_paused else "▶", "toggle_pause", true)
	_draw_button(Rect2(time_rect.position.x + 60.0, button_y, 38.0, 22.0), "1×", "speed:1", true)
	_draw_button(Rect2(time_rect.position.x + 102.0, button_y, 38.0, 22.0), "2×", "speed:2", true)
	_draw_button(Rect2(time_rect.position.x + 144.0, button_y, 38.0, 22.0), "4×", "speed:4", true)


func _draw_corner(rect: Rect2, title: String, subtitle: String, action: String, border: Color, compact: bool) -> void:
	_panel(rect, Color(0.025, 0.055, 0.06, 0.88), border)
	_register_hit(rect, action, true)
	_draw_label(rect.position + Vector2(14.0, 25.0), title, 14 if compact else 15)
	if not compact:
		_draw_label(rect.position + Vector2(14.0, 48.0), subtitle, 10, Color(0.76, 0.67, 0.39, 1.0))


func _draw_top_info() -> void:
	if info_progress <= 0.001:
		return
	var compact := size.x < 940.0
	var height := minf(size.y * 0.34, 218.0)
	var rect: Rect2
	if compact:
		rect = Rect2(18.0, 86.0, size.x - 36.0, height)
	else:
		rect = Rect2(318.0, 8.0, maxf(360.0, size.x - 636.0), height)
	var hidden_y := -height - 12.0
	var shown_y := rect.position.y
	rect.position.y = lerpf(hidden_y, shown_y, info_progress)
	_panel(rect, Color(0.018, 0.035, 0.038, 0.96), Color(0.78, 0.70, 0.46, 0.40))
	_register_hit(rect, "noop", true)

	var title := "空间对象"
	var path := _breadcrumb_text()
	var summary := ""
	var action_label := ""
	var action := ""
	var action_enabled := false

	if not selected_institution_id.is_empty():
		var institution: Dictionary = _institution_by_id.get(selected_institution_id, {})
		title = str(institution.get("name", "机构"))
		summary = str(institution.get("mandate", institution.get("agenda", "未配置摘要")))
	elif not selected_event_id.is_empty():
		var event: Dictionary = _event_by_id.get(selected_event_id, {})
		title = str(event.get("title", "状态"))
		path = "世界 / 状态 / " + str(event.get("source", "机构"))
		summary = "来源：" + str(event.get("source", "机构"))
		action_label = "定位地区"
		action = "locate_event"
		action_enabled = not str(event.get("region_id", "")).is_empty()
	elif world_mode == WORLD_COUNTRIES and not selected_country_id.is_empty():
		var country: Dictionary = _country_by_id.get(selected_country_id, {})
		title = str(country.get("name", "国家"))
		path = "世界 / " + title
		summary = "国家级空间对象 · ISO " + str(country.get("iso_a3", ""))
		action_label = "进入国家"
		action = "focus_country"
		action_enabled = selected_country_id == FOCUS_COUNTRY_ID
	elif not selected_region_id.is_empty():
		var region: Dictionary = _region_by_id.get(selected_region_id, {})
		title = str(region.get("display_name_zh", "大区"))
		path = "世界 / 法兰西第三共和国 / " + title
		summary = "人口：%s · %s" % [str(region.get("population", "未配置")), str(region.get("market", "未配置"))]
		action_label = "进入大区"
		action = "enter_region"
		action_enabled = true

	_draw_label(rect.position + Vector2(24.0, 34.0), title, 19)
	_draw_label(rect.position + Vector2(24.0, 60.0), path, 11, Color(0.73, 0.82, 0.78, 1.0))
	_draw_label(rect.position + Vector2(24.0, 94.0), summary, 12)
	if not action.is_empty():
		_draw_button(Rect2(rect.end.x - 176.0, rect.end.y - 48.0, 128.0, 32.0), action_label, action, action_enabled)
	_draw_button(Rect2(rect.end.x - 42.0, rect.position.y + 10.0, 30.0, 26.0), "×", "close_info", true)


func _set_info_open(value: bool) -> void:
	info_open = value
	if _info_tween != null and _info_tween.is_valid():
		_info_tween.kill()
	_info_tween = create_tween()
	_info_tween.set_trans(Tween.TRANS_CUBIC)
	_info_tween.set_ease(Tween.EASE_OUT if value else Tween.EASE_IN)
	_info_tween.tween_method(Callable(self, "_set_info_progress"), info_progress, 1.0 if value else 0.0, 0.18)


func _set_info_progress(value: float) -> void:
	info_progress = value
	queue_redraw()


func _draw_layout_switch() -> void:
	var y := size.y - 42.0
	if size.x < 940.0:
		y = size.y - 120.0
	_draw_button(Rect2(size.x * 0.5 - 92.0, y, 84.0, 28.0), "F1 半球", "layout_focus", true)
	_draw_button(Rect2(size.x * 0.5 + 8.0, y, 96.0, 28.0), "F2 桌面", "layout_workspace", true)
	if layout_mode_id != LAYOUT_WORKSPACE or space_level != WORLD:
		return
	if not workspace_open:
		_draw_button(Rect2(size.x - 148.0, 104.0, 118.0, 30.0), "展开工作区", "toggle_workspace", true)
		return
	var panel_width := minf(318.0, maxf(250.0, size.x * 0.28))
	var rect := Rect2(size.x - panel_width - 24.0, 104.0, panel_width, 220.0)
	_panel(rect, Color(0.02, 0.043, 0.046, 0.92), Color(0.65, 0.78, 0.70, 0.28))
	_register_hit(rect, "noop", true)
	_draw_label(rect.position + Vector2(18.0, 30.0), "当前空间工作区", 15)
	_draw_label(rect.position + Vector2(18.0, 62.0), "层级：" + _breadcrumb_text(), 11)
	_draw_label(rect.position + Vector2(18.0, 90.0), "选择：" + _workspace_selection_name(), 11)
	_draw_button(Rect2(rect.end.x - 38.0, rect.position.y + 8.0, 28.0, 24.0), "×", "toggle_workspace", true)
	if world_mode == WORLD_COUNTRIES:
		_draw_button(Rect2(rect.position.x + 18.0, rect.end.y - 48.0, 118.0, 30.0), "进入国家", "focus_country", selected_country_id == FOCUS_COUNTRY_ID)
	else:
		_draw_button(Rect2(rect.position.x + 18.0, rect.end.y - 48.0, 118.0, 30.0), "进入大区", "enter_region", not selected_region_id.is_empty())


func _draw_breadcrumbs() -> void:
	_draw_label(Vector2(24.0, 104.0), _breadcrumb_text(), 12, Color(0.76, 0.82, 0.78, 1.0))
	if space_level != WORLD:
		_draw_button(Rect2(24.0, 122.0, 92.0, 28.0), "返回上层", "back", true)
		_draw_button(Rect2(126.0, 122.0, 92.0, 28.0), "返回世界", "world", true)
	elif world_mode == WORLD_COUNTRY_FOCUS:
		_draw_button(Rect2(24.0, 122.0, 92.0, 28.0), "返回全球", "overview_world", true)


func _draw_active_hud_panel() -> void:
	if active_hud_panel.is_empty():
		return
	var panel_width := minf(560.0, size.x - 44.0)
	var panel_height := minf(330.0, size.y - 170.0)
	var rect := Rect2((size.x - panel_width) * 0.5, (size.y - panel_height) * 0.5, panel_width, panel_height)
	_panel(rect, Color(0.016, 0.030, 0.032, 0.98), Color(0.78, 0.70, 0.46, 0.46))
	_register_hit(rect, "noop", true)
	_draw_button(Rect2(rect.end.x - 42.0, rect.position.y + 10.0, 30.0, 26.0), "×", "close_hud_panel", true)
	if active_hud_panel == "country":
		_draw_country_panel(rect)
	elif active_hud_panel == "character":
		_draw_character_panel(rect)
	elif active_hud_panel == "activity":
		_draw_activity_panel(rect)
	elif active_hud_panel == "time":
		_draw_time_panel(rect)


func _draw_country_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), str(_country_profile.get("formal_name_zh", "法兰西第三共和国")), 20)
	_draw_label(rect.position + Vector2(24.0, 72.0), "政体：" + str(_country_profile.get("government_name", "第三共和国")), 13)
	_draw_label(rect.position + Vector2(24.0, 104.0), "公开议程：" + str(_country_profile.get("public_policy", "未配置")), 12)
	_draw_label(rect.position + Vector2(24.0, 134.0), "新闻：" + str(_country_profile.get("news", "未配置")), 12)
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 138.0, 32.0), "定位法兰西", "focus_france", true)


func _draw_character_panel(rect: Rect2) -> void:
	var profile: Dictionary = _character_profiles.get(active_character_key, {})
	_draw_label(rect.position + Vector2(24.0, 38.0), str(profile.get("display_name_zh", profile.get("name", "人物"))), 20)
	_draw_label(rect.position + Vector2(24.0, 70.0), str(profile.get("position", profile.get("occupation", ""))), 13)
	_draw_label(rect.position + Vector2(24.0, 102.0), "所在地：" + str(profile.get("region", "未配置")), 12)
	_draw_label(rect.position + Vector2(24.0, 130.0), "当前事项：" + str(profile.get("plan", "未配置")), 12)
	_draw_label(rect.position + Vector2(24.0, 158.0), "关注：" + str(profile.get("primary_concern", "未配置")), 12)
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 150.0, 32.0), "切换角色视角", "switch_character", _character_profiles.size() > 1)


func _draw_activity_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), "已知信息与机构议程", 19)
	var y := rect.position.y + 76.0
	for index in range(mini(_world_events.size(), 6)):
		var event: Dictionary = _world_events[index]
		_draw_label(Vector2(rect.position.x + 28.0, y), "• " + str(event.get("title", "状态")), 11)
		y += 31.0
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 118.0, 32.0), "标记已读", "mark_read", activity_unread > 0)


func _draw_time_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), "时间控制", 19)
	_draw_label(rect.position + Vector2(24.0, 76.0), _format_sim_datetime(), 16)
	_draw_label(rect.position + Vector2(24.0, 108.0), "状态：" + ("暂停" if sim_paused else "%d×运行" % sim_speed), 12)
	_draw_button(Rect2(rect.position.x + 24.0, rect.position.y + 142.0, 82.0, 30.0), "暂停/继续", "toggle_pause", true)
	_draw_button(Rect2(rect.position.x + 116.0, rect.position.y + 142.0, 58.0, 30.0), "1×", "speed:1", true)
	_draw_button(Rect2(rect.position.x + 184.0, rect.position.y + 142.0, 58.0, 30.0), "2×", "speed:2", true)
	_draw_button(Rect2(rect.position.x + 252.0, rect.position.y + 142.0, 58.0, 30.0), "4×", "speed:4", true)


func _draw_data_errors() -> void:
	if _data_errors.is_empty():
		return
	var rect := Rect2(18.0, 158.0, minf(520.0, size.x - 36.0), 30.0)
	_panel(rect, Color(0.28, 0.06, 0.05, 0.94), Color(0.96, 0.36, 0.26, 0.75))
	_register_hit(rect, "noop", true)
	_draw_label(rect.position + Vector2(10.0, 20.0), _data_errors[0], 11, Color(1.0, 0.78, 0.72, 1.0))


func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 1.0)


func _draw_label(pos: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0)) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_button(rect: Rect2, label: String, action: String, enabled: bool) -> void:
	_register_hit(rect, action, enabled)
	var fill := Color(0.08, 0.10, 0.095, 0.90) if enabled else Color(0.05, 0.055, 0.052, 0.68)
	var border := Color(0.72, 0.64, 0.38, 0.34) if enabled else Color(0.36, 0.34, 0.28, 0.22)
	_panel(rect, fill, border)
	_draw_label(rect.position + Vector2(9.0, rect.size.y * 0.65), label, 11, Color(0.90, 0.91, 0.84, 1.0) if enabled else Color(0.55, 0.57, 0.53, 1.0))


func _register_hit(rect: Rect2, action: String, enabled: bool) -> void:
	_button_hits.append({"rect": rect, "action": action, "enabled": enabled})


func _position_hits_ui(position: Vector2) -> bool:
	for record in _button_hits:
		var rect: Rect2 = record.get("rect", Rect2())
		if rect.has_point(position):
			return true
	return false


func _handle_button_click(position: Vector2) -> bool:
	for index in range(_button_hits.size() - 1, -1, -1):
		var record: Dictionary = _button_hits[index]
		var rect: Rect2 = record.get("rect", Rect2())
		if bool(record.get("enabled", false)) and rect.has_point(position):
			_activate_button(str(record.get("action", "")))
			return true
	return false


func _activate_button(action: String) -> void:
	if action == "noop":
		return
	elif action == "layout_focus":
		_set_layout(LAYOUT_FOCUS)
	elif action == "layout_workspace":
		_set_layout(LAYOUT_WORKSPACE)
	elif action == "toggle_workspace":
		workspace_open = not workspace_open
		_apply_layout()
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
	world_mode = WORLD_COUNTRY_FOCUS
	selected_event_id = ""
	selected_region_id = ""
	hover_region_id = ""
	_set_info_open(false)
	_mark_projection_dirty()
	queue_redraw()


func _return_to_global_world() -> void:
	world_mode = WORLD_COUNTRIES
	selected_region_id = ""
	hover_region_id = ""
	_set_info_open(false)
	_mark_projection_dirty()
	queue_redraw()


func _locate_selected_event() -> void:
	var event: Dictionary = _event_by_id.get(selected_event_id, {})
	var region_id := str(event.get("region_id", ""))
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
		set_process(false)
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
	var keys := _character_profiles.keys()
	if keys.size() < 2:
		return
	var current_index := keys.find(active_character_key)
	active_character_key = str(keys[(current_index + 1) % keys.size()])
	queue_redraw()


func _active_character_name() -> String:
	var profile: Dictionary = _character_profiles.get(active_character_key, {})
	return str(profile.get("display_name_zh", profile.get("name", "玩家角色")))


func _active_character_position() -> String:
	var profile: Dictionary = _character_profiles.get(active_character_key, {})
	return str(profile.get("position", profile.get("occupation", "个人层级入口")))


func _activity_summary() -> String:
	if _world_events.is_empty():
		return "暂无已知信息"
	return str(_world_events[0].get("title", "机构议程"))


func _workspace_selection_name() -> String:
	if world_mode == WORLD_COUNTRIES:
		var country: Dictionary = _country_by_id.get(selected_country_id, {})
		return str(country.get("name", "未选择国家"))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	return str(region.get("display_name_zh", "未选择大区"))


func _breadcrumb_text() -> String:
	var text := "世界"
	if world_mode == WORLD_COUNTRY_FOCUS or space_level != WORLD:
		text += " / 法兰西第三共和国"
	if not selected_region_id.is_empty() and (world_mode == WORLD_COUNTRY_FOCUS or space_level != WORLD):
		text += " / " + _selected_region_name()
	if space_level == CITY:
		text += " / " + _city_name()
	return text


func _selected_region_name() -> String:
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	return str(region.get("display_name_zh", "未选择"))


func _city_name() -> String:
	var city: Dictionary = _city_by_id.get(selected_city_id, {})
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
		var days_in_month := _days_in_month(sim_year, sim_month)
		if sim_day > days_in_month:
			sim_day = 1
			sim_month += 1
			if sim_month > 12:
				sim_month = 1
				sim_year += 1


func _days_in_month(year: int, month: int) -> int:
	if month in [4, 6, 9, 11]:
		return 30
	if month == 2:
		var leap := year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
		return 29 if leap else 28
	return 31


func _lon_lat_from_record(record: Dictionary, key: String) -> Variant:
	var value: Variant = record.get(key, [])
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return null


func _all_region_polygons() -> Array:
	var output: Array = []
	for region_id in _region_polygons.keys():
		for polygon in _region_polygons[region_id]:
			output.append(polygon)
	return output


func _lon_lat_bounds(polygons: Array) -> Rect2:
	var has_point := false
	var min_point := Vector2(999.0, 999.0)
	var max_point := Vector2(-999.0, -999.0)
	for polygon in polygons:
		for point in polygon:
			has_point = true
			min_point.x = minf(min_point.x, point.x)
			min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x)
			max_point.y = maxf(max_point.y, point.y)
	if not has_point:
		return Rect2(Vector2(-5.0, 42.0), Vector2(12.0, 10.0))
	return Rect2(min_point, max_point - min_point)


func _polygon_overlaps_bounds(polygon: PackedVector2Array, bounds: Rect2) -> bool:
	if polygon.is_empty():
		return false
	var polygon_bounds := _lon_lat_bounds([polygon])
	return polygon_bounds.intersects(bounds) or bounds.encloses(polygon_bounds)


func _lon_lat_to_rect(lon_lat: Vector2, bounds: Rect2, rect: Rect2) -> Vector2:
	var safe_width := maxf(bounds.size.x, 0.001)
	var safe_height := maxf(bounds.size.y, 0.001)
	var x := rect.position.x + ((lon_lat.x - bounds.position.x) / safe_width) * rect.size.x
	var y := rect.end.y - ((lon_lat.y - bounds.position.y) / safe_height) * rect.size.y
	return Vector2(x, y)
