class_name HolographicWorkspaceSpike
extends Control

const WORLD := "world"
const REGION := "region"
const CITY := "city"
const LAYOUT_FOCUS := 0
const LAYOUT_WORKSPACE := 1

const CAMERA_ORTHO_SIZE := 2.55
const EDGE_BAND := 58.0
const DRAG_THRESHOLD := 5.0
const MOTION_EPSILON := 0.0005
const FOCUS_VIEWPORT_SIZE := Vector2i(720, 600)
const WORKSPACE_VIEWPORT_SIZE := Vector2i(600, 520)

var layout_mode_id: int = LAYOUT_FOCUS
var space_level: String = WORLD
var selected_region_id: String = ""
var selected_city_id: String = ""
var hover_region_id: String = ""
var info_open: bool = false
var yaw: float = -0.08
var tilt: float = -0.18
var angular_velocity: float = 0.0
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_last := Vector2.ZERO
var drag_moved: bool = false

var _regions: Array[Dictionary] = []
var _cities: Array[Dictionary] = []
var _coastline_lines: Array[PackedVector2Array] = []
var _region_polygons: Dictionary = {}
var _region_by_id: Dictionary = {}
var _city_by_id: Dictionary = {}
var _cities_by_region: Dictionary = {}
var _button_hits: Array[Dictionary] = []
var _hemisphere_center := Vector2.ZERO
var _hemisphere_rect := Rect2()
var _hemisphere_radius: float = 220.0

@onready var viewport_container: SubViewportContainer = %HemisphereViewportContainer
@onready var viewport: SubViewport = %HemisphereViewport


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_world_data_once()
	_apply_layout()
	_set_world_layer_visible(true)
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var hover_spin := _edge_hover_spin()
	if absf(angular_velocity) > MOTION_EPSILON or absf(hover_spin) > MOTION_EPSILON:
		yaw += (angular_velocity + hover_spin) * delta
		angular_velocity = lerpf(angular_velocity, 0.0, minf(1.0, delta * 6.5))
		queue_redraw()
		return
	angular_velocity = 0.0
	set_process(false)
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
				_select_region_at(mouse_button.position, true)
			accept_event()
		return

	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if dragging:
			var motion_delta := mouse_motion.position - drag_last
			drag_last = mouse_motion.position
			if mouse_motion.position.distance_to(drag_start) > DRAG_THRESHOLD:
				drag_moved = true
			yaw += motion_delta.x * 0.006
			tilt = clampf(tilt + motion_delta.y * 0.0025, -0.62, 0.12)
			angular_velocity = motion_delta.x * 0.018
			_start_motion()
			queue_redraw()
		elif _hemisphere_rect.has_point(mouse_motion.position):
			_select_region_at(mouse_motion.position, false)
			if absf(_edge_hover_spin()) > MOTION_EPSILON:
				_start_motion()
		elif not hover_region_id.is_empty():
			hover_region_id = ""
			queue_redraw()


func _draw() -> void:
	_button_hits.clear()
	_draw_background()
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_layout()
		_set_world_layer_visible(space_level == WORLD)
		queue_redraw()


func _load_world_data_once() -> void:
	var regions_document := _read_document("res://data/world_map/regions.json")
	_regions = _dictionary_array(regions_document, "regions")
	_cities = _read_array("res://data/world_map/cities.json", "cities")

	for region in _regions:
		_region_by_id[str(region.get("id", ""))] = region

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

	_load_coastline_lines()
	_build_region_polygons(regions_document)


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _read_array(path: String, key: String) -> Array[Dictionary]:
	return _dictionary_array(_read_document(path), key)


func _dictionary_array(document: Dictionary, key: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in document.get(key, []):
		if value is Dictionary:
			output.append(value)
	return output


func _load_coastline_lines() -> void:
	var document := _read_document("res://data/world_map/world_coastlines.json")
	var count := 0
	for feature in document.get("features", []):
		if count >= 160:
			break
		if not feature is Dictionary:
			continue
		for polygon in (feature as Dictionary).get("polygons", []):
			if not polygon is Dictionary:
				continue
			var line := _points_from_raw((polygon as Dictionary).get("outer", []))
			if line.size() > 2:
				_coastline_lines.append(_simplify_line(line, 220))
				count += 1
				if count >= 160:
					break


func _build_region_polygons(regions_document: Dictionary) -> void:
	var administrative_by_id: Dictionary = {}
	for unit in regions_document.get("administrative_units", []):
		if unit is Dictionary:
			administrative_by_id[str((unit as Dictionary).get("id", ""))] = unit

	for region in _regions:
		var region_id := str(region.get("id", ""))
		var polygons: Array[PackedVector2Array] = []
		for unit_id in region.get("administrative_unit_ids", []):
			var unit: Dictionary = administrative_by_id.get(str(unit_id), {})
			for geometry in unit.get("geometry", []):
				if geometry is Dictionary:
					var outer := _points_from_raw((geometry as Dictionary).get("outer", []))
					if outer.size() > 2:
						polygons.append(_simplify_line(outer, 180))
		_region_polygons[region_id] = polygons


func _points_from_raw(raw_points: Variant) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not raw_points is Array:
		return points
	for point in raw_points:
		if point is Array and (point as Array).size() >= 2:
			points.append(Vector2(float(point[0]), float(point[1])))
	return points


func _simplify_line(points: PackedVector2Array, max_points: int) -> PackedVector2Array:
	if points.size() <= max_points:
		return points
	var simplified := PackedVector2Array()
	var step := maxi(1, int(ceil(float(points.size() - 1) / float(max_points - 1))))
	for index in range(0, points.size(), step):
		simplified.append(points[index])
	if simplified.is_empty() or simplified[simplified.size() - 1] != points[points.size() - 1]:
		simplified.append(points[points.size() - 1])
	return simplified


func _apply_layout() -> void:
	var desired := FOCUS_VIEWPORT_SIZE if layout_mode_id == LAYOUT_FOCUS else WORKSPACE_VIEWPORT_SIZE
	var reserved_right := 32.0 if layout_mode_id == LAYOUT_FOCUS else minf(390.0, size.x * 0.34)
	var available_width := maxf(360.0, size.x - reserved_right - 48.0)
	var available_height := maxf(320.0, size.y - 112.0)
	var scale_factor := minf(1.0, minf(available_width / float(desired.x), available_height / float(desired.y)))
	var viewport_size := Vector2i(
		maxi(360, int(round(float(desired.x) * scale_factor))),
		maxi(320, int(round(float(desired.y) * scale_factor)))
	)
	viewport.size = viewport_size
	viewport_container.size = Vector2(viewport_size)

	var available_left_width := size.x if layout_mode_id == LAYOUT_FOCUS else maxf(440.0, size.x - reserved_right)
	var x := maxf(18.0, (available_left_width - float(viewport_size.x)) * 0.5)
	var y := maxf(88.0, (size.y - float(viewport_size.y)) * 0.5)
	viewport_container.position = Vector2(x, y)

	_hemisphere_center = viewport_container.position + Vector2(viewport_size) * 0.5
	_hemisphere_radius = minf(
		float(viewport_size.y) / CAMERA_ORTHO_SIZE,
		float(viewport_size.x) * 0.49
	)
	_hemisphere_rect = Rect2(
		_hemisphere_center - Vector2(_hemisphere_radius, _hemisphere_radius),
		Vector2(_hemisphere_radius * 2.0, _hemisphere_radius * 2.0)
	)


func _set_layout(id: int) -> void:
	layout_mode_id = id
	_apply_layout()
	_set_world_layer_visible(space_level == WORLD)
	queue_redraw()


func _set_world_layer_visible(active: bool) -> void:
	viewport_container.visible = active
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED


func _start_motion() -> void:
	if space_level == WORLD and not is_processing():
		set_process(true)


func _edge_hover_spin() -> float:
	if space_level != WORLD or dragging:
		return 0.0
	var pos := get_local_mouse_position()
	if not _hemisphere_rect.has_point(pos):
		return 0.0
	var left_power := clampf((_hemisphere_rect.position.x + EDGE_BAND - pos.x) / EDGE_BAND, 0.0, 1.0)
	var right_power := clampf((pos.x - (_hemisphere_rect.end.x - EDGE_BAND)) / EDGE_BAND, 0.0, 1.0)
	return (right_power - left_power) * 0.32


func _lon_lat_to_rotated_sphere(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	var point := Vector3(
		sin(lon) * cos(lat),
		sin(lat),
		cos(lon) * cos(lat)
	)
	var yaw_basis := Basis(Vector3.UP, yaw)
	var tilt_basis := Basis(Vector3.RIGHT, tilt)
	return tilt_basis * (yaw_basis * point)


func _sphere_to_screen(point: Vector3) -> Dictionary:
	return {
		"visible": point.z >= 0.0,
		"screen": _hemisphere_center + Vector2(
			point.x * _hemisphere_radius,
			-point.y * _hemisphere_radius
		),
		"depth": point.z,
	}


func _project_visible(lon_lat: Vector2) -> Dictionary:
	return _sphere_to_screen(_lon_lat_to_rotated_sphere(lon_lat))


func _draw_world_overlay() -> void:
	for line in _coastline_lines:
		_draw_geo_line(line, Color(0.64, 0.84, 0.78, 0.22), 0.8)

	for region_id in _region_polygons.keys():
		var color := Color(0.72, 0.78, 0.72, 0.20)
		if region_id == selected_region_id:
			color = Color(0.88, 0.78, 0.48, 0.74)
		elif region_id == hover_region_id:
			color = Color(0.75, 0.90, 0.86, 0.58)
		for polygon in _region_polygons[region_id]:
			_draw_geo_line(polygon, color, 1.2 if region_id == selected_region_id else 0.75)

	_draw_region_anchors()
	_draw_major_cities()


func _draw_region_anchors() -> void:
	for region in _regions:
		var anchor := _lon_lat_from_record(region, "label_lon_lat")
		if anchor == null:
			continue
		var projection := _project_visible(anchor)
		if not bool(projection.get("visible", false)):
			continue
		var region_id := str(region.get("id", ""))
		var point: Vector2 = projection.get("screen", Vector2.ZERO)
		var radius := 5.5 if region_id == selected_region_id else 4.0
		var color := Color(0.92, 0.76, 0.42, 0.92) if region_id == selected_region_id else Color(0.72, 0.88, 0.82, 0.72)
		if region_id == hover_region_id:
			radius = 6.0
			color = Color(0.82, 0.94, 0.88, 0.94)
		draw_circle(point, radius, color)
		if region_id == hover_region_id:
			_draw_label(
				point + Vector2(9.0, -8.0),
				str(region.get("display_name_zh", region.get("name", "")))
			)


func _draw_major_cities() -> void:
	var shown := 0
	for city in _cities:
		if shown >= 8:
			break
		if not bool(city.get("major", false)):
			continue
		var lon_lat := _lon_lat_from_record(city, "lon_lat")
		if lon_lat == null:
			continue
		var projection := _project_visible(lon_lat)
		if bool(projection.get("visible", false)):
			draw_circle(
				projection.get("screen", Vector2.ZERO),
				3.0,
				Color(0.90, 0.76, 0.44, 0.70)
			)
			shown += 1


func _draw_geo_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var segment := PackedVector2Array()
	var previous_lon := 0.0
	var has_previous := false
	for lon_lat in points:
		if has_previous and absf(lon_lat.x - previous_lon) > 160.0:
			_draw_projected_segment(segment, color, width)
			segment.clear()
		var projected := _project_visible(lon_lat)
		if bool(projected.get("visible", false)):
			segment.append(projected.get("screen", Vector2.ZERO))
		else:
			_draw_projected_segment(segment, color, width)
			segment.clear()
		previous_lon = lon_lat.x
		has_previous = true
	_draw_projected_segment(segment, color, width)


func _draw_projected_segment(segment: PackedVector2Array, color: Color, width: float) -> void:
	if segment.size() > 1:
		draw_polyline(segment, color, width, true)


func _select_region_at(pos: Vector2, click: bool) -> void:
	var best := _nearest_visible_region_anchor(pos)
	if hover_region_id != best:
		hover_region_id = best
		queue_redraw()
	if click and not best.is_empty():
		selected_region_id = best
		info_open = true
		queue_redraw()


func _nearest_visible_region_anchor(pos: Vector2) -> String:
	var best := ""
	var best_distance := 99999.0
	var hit_radius := maxf(30.0, _hemisphere_radius * 0.075)
	for region in _regions:
		var anchor := _lon_lat_from_record(region, "label_lon_lat")
		if anchor == null:
			continue
		var projected := _project_visible(anchor)
		if not bool(projected.get("visible", false)):
			continue
		var distance := pos.distance_to(projected.get("screen", Vector2.ZERO))
		if distance < best_distance and distance < hit_radius:
			best = str(region.get("id", ""))
			best_distance = distance
	return best


func _draw_region_map() -> void:
	var rect := _main_content_rect(150.0, 120.0, 90.0)
	_panel(rect, Color(0.025, 0.047, 0.052, 0.88), Color(0.70, 0.62, 0.36, 0.32))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(
		rect.position + Vector2(24.0, 34.0),
		"二维大区层 · " + str(region.get("display_name_zh", "选中大区")),
		17
	)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		"真实边界：所属行政单位外边界；交通线：样机占位",
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_region_flat_geometry(rect)
	_draw_region_cities(rect)


func _draw_region_flat_geometry(rect: Rect2) -> void:
	var polygons: Array = _region_polygons.get(selected_region_id, [])
	var bounds := _lon_lat_bounds(polygons)
	var map_rect := rect.grow(-70.0)
	map_rect.size.x = maxf(260.0, map_rect.size.x - 190.0)
	for polygon in polygons:
		var flat := PackedVector2Array()
		for lon_lat in polygon:
			flat.append(_lon_lat_to_rect(lon_lat, bounds, map_rect))
		if flat.size() > 2:
			draw_colored_polygon(flat, Color(0.32, 0.48, 0.48, 0.20))
			draw_polyline(flat, Color(0.83, 0.75, 0.48, 0.70), 1.4, true)

	for index in range(3):
		var y := map_rect.position.y + 70.0 + float(index) * 52.0
		draw_line(
			Vector2(map_rect.position.x + 20.0, y),
			Vector2(map_rect.end.x - 20.0, y + 20.0),
			Color(0.55, 0.75, 0.68, 0.20),
			1.4
		)


func _draw_region_cities(rect: Rect2) -> void:
	var city_ids: Array = _cities_by_region.get(selected_region_id, [])
	if city_ids.is_empty():
		_draw_label(
			rect.position + Vector2(86.0, rect.size.y - 60.0),
			"当前大区没有配置城市入口",
			13,
			Color(0.95, 0.72, 0.43, 1.0)
		)
		return

	var bounds := _lon_lat_bounds(_region_polygons.get(selected_region_id, []))
	var map_rect := rect.grow(-70.0)
	map_rect.size.x = maxf(260.0, map_rect.size.x - 190.0)
	var list_x := rect.end.x - 172.0
	var list_y := rect.position.y + 88.0
	var index := 0

	for city_id in city_ids:
		if index >= 8:
			break
		var city: Dictionary = _city_by_id.get(str(city_id), {})
		var lon_lat := _lon_lat_from_record(city, "lon_lat")
		if lon_lat == null:
			continue
		var point := _lon_lat_to_rect(lon_lat, bounds, map_rect)
		draw_circle(point, 6.0, Color(0.88, 0.74, 0.42, 0.86))
		_draw_label(point + Vector2(10.0, 4.0), str(city.get("name", "城市")), 12)
		_draw_button(
			Rect2(list_x, list_y + float(index) * 34.0, 140.0, 27.0),
			"进入 " + str(city.get("name", "城市")),
			"enter_city:" + str(city_id),
			true
		)
		index += 1


func _draw_city_map() -> void:
	var rect := _main_content_rect(180.0, 130.0, 100.0)
	_panel(rect, Color(0.03, 0.04, 0.04, 0.90), Color(0.72, 0.75, 0.66, 0.24))
	var city: Dictionary = _city_by_id.get(selected_city_id, {})
	_draw_label(
		rect.position + Vector2(24.0, 34.0),
		"城市本地层占位 · " + str(city.get("name", "本地城市")),
		17
	)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		"本层仅验证城市进入/返回，不声明接入正式城市本地地图",
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)

	var labels := ["市政厅", "车站", "工会会馆", "市场", "报社", "居住区"]
	var points: Array[Vector2] = []
	for index in range(labels.size()):
		var column := index % 3
		var row := index / 3
		points.append(
			rect.position + Vector2(
				rect.size.x * (0.22 + float(column) * 0.28),
				rect.size.y * (0.42 + float(row) * 0.25)
			)
		)

	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], Color(0.60, 0.68, 0.62, 0.28), 2.0)
	for index in range(labels.size()):
		draw_circle(points[index], 7.0, Color(0.82, 0.80, 0.62, 0.78))
		_draw_label(points[index] + Vector2(12.0, 5.0), labels[index], 12)


func _main_content_rect(preferred_margin: float, top: float, bottom: float) -> Rect2:
	var margin := minf(preferred_margin, maxf(24.0, (size.x - 520.0) * 0.5))
	return Rect2(
		margin,
		top,
		maxf(420.0, size.x - margin * 2.0),
		maxf(300.0, size.y - top - bottom)
	)


func _draw_corners() -> void:
	_panel(Rect2(18.0, 18.0, 284.0, 66.0), Color(0.025, 0.055, 0.06, 0.82), Color(0.72, 0.64, 0.38, 0.22))
	_draw_label(Vector2(78.0, 43.0), "法兰西第三共和国", 16)
	_draw_label(Vector2(78.0, 64.0), "国家 / 政权 / 机构入口", 11, Color(0.76, 0.67, 0.39, 1.0))
	draw_circle(Vector2(48.0, 51.0), 18.0, Color(0.90, 0.88, 0.78, 0.80))

	_panel(Rect2(size.x - 244.0, 18.0, 226.0, 66.0), Color(0.025, 0.055, 0.06, 0.82), Color(0.72, 0.64, 0.38, 0.22))
	_draw_label(Vector2(size.x - 226.0, 43.0), "1900年3月12日", 14)
	_draw_label(Vector2(size.x - 226.0, 64.0), "Ⅱ 暂停 · 1×  2×  4×", 11, Color(0.82, 0.72, 0.44, 1.0))

	_panel(Rect2(18.0, size.y - 88.0, 286.0, 70.0), Color(0.025, 0.055, 0.06, 0.82), Color(0.72, 0.64, 0.38, 0.22))
	draw_circle(Vector2(50.0, size.y - 52.0), 22.0, Color(0.56, 0.68, 0.62, 0.75))
	_draw_label(Vector2(80.0, size.y - 61.0), "让·马丁", 16)
	_draw_label(Vector2(80.0, size.y - 40.0), "铁路工人 · 个人层级入口", 11, Color(0.76, 0.67, 0.39, 1.0))

	_panel(Rect2(size.x - 300.0, size.y - 92.0, 282.0, 74.0), Color(0.025, 0.055, 0.06, 0.82), Color(0.72, 0.50, 0.25, 0.22))
	_draw_label(Vector2(size.x - 282.0, size.y - 66.0), "! 已知信息", 12, Color(0.95, 0.72, 0.43, 1.0))
	_draw_label(Vector2(size.x - 282.0, size.y - 42.0), "北部交通状态更新 · 未读 2", 12)


func _draw_top_info() -> void:
	if not info_open:
		return
	var height := minf(size.y * 0.38, 220.0)
	var rect := Rect2(size.x * 0.18, 8.0, size.x * 0.64, height)
	_panel(rect, Color(0.018, 0.035, 0.038, 0.92), Color(0.78, 0.70, 0.46, 0.36))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(rect.position + Vector2(24.0, 34.0), str(region.get("display_name_zh", "空间对象")), 20)
	_draw_label(
		rect.position + Vector2(24.0, 62.0),
		"世界 / 法兰西第三共和国 / " + str(region.get("display_name_zh", "大区")),
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_label(rect.position + Vector2(24.0, 98.0), "摘要：法国宏观大区样例；边界来自所属行政单位经纬度多边形。", 13)
	_draw_button(
		Rect2(rect.end.x - 192.0, rect.end.y - 52.0, 132.0, 34.0),
		"进入大区",
		"enter_region",
		not selected_region_id.is_empty()
	)
	_draw_button(Rect2(rect.end.x - 52.0, rect.position.y + 12.0, 34.0, 28.0), "×", "close_info", true)


func _draw_layout_switch() -> void:
	_draw_button(Rect2(size.x * 0.5 - 92.0, size.y - 42.0, 84.0, 28.0), "F1 半球", "layout_focus", true)
	_draw_button(Rect2(size.x * 0.5 + 8.0, size.y - 42.0, 96.0, 28.0), "F2 桌面", "layout_workspace", true)
	if layout_mode_id == LAYOUT_WORKSPACE and space_level == WORLD:
		var panel_width := minf(318.0, maxf(260.0, size.x * 0.28))
		var rect := Rect2(size.x - panel_width - 36.0, 118.0, panel_width, 210.0)
		_panel(rect, Color(0.02, 0.043, 0.046, 0.86), Color(0.65, 0.78, 0.70, 0.24))
		_draw_label(rect.position + Vector2(20.0, 30.0), "当前区域工作空间", 16)
		_draw_label(rect.position + Vector2(20.0, 62.0), "选择：" + _selected_region_name(), 12)
		_draw_label(rect.position + Vector2(20.0, 92.0), "层级：世界 → 大区 → 城市", 12)
		_draw_button(
			Rect2(rect.position.x + 20.0, rect.end.y - 52.0, 118.0, 32.0),
			"进入大区",
			"enter_region",
			not selected_region_id.is_empty()
		)


func _draw_breadcrumbs() -> void:
	_draw_label(Vector2(24.0, 112.0), _breadcrumb_text(), 13, Color(0.76, 0.82, 0.78, 1.0))
	if space_level != WORLD:
		_draw_button(Rect2(24.0, 132.0, 92.0, 30.0), "返回上层", "back", true)
		_draw_button(Rect2(126.0, 132.0, 92.0, 30.0), "返回世界", "world", true)


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.023, 0.027, 1.0))


func _draw_button(rect: Rect2, label: String, action: String, enabled: bool) -> void:
	_button_hits.append({"rect": rect, "action": action, "enabled": enabled})
	var fill := Color(0.08, 0.10, 0.095, 0.86) if enabled else Color(0.05, 0.055, 0.052, 0.62)
	var border := Color(0.72, 0.64, 0.38, 0.30) if enabled else Color(0.36, 0.34, 0.28, 0.22)
	_panel(rect, fill, border)
	_draw_label(
		rect.position + Vector2(12.0, rect.size.y * 0.62),
		label,
		12,
		Color(0.90, 0.91, 0.84, 1.0) if enabled else Color(0.55, 0.57, 0.53, 1.0)
	)


func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 1.0)


func _draw_label(pos: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0)) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _handle_button_click(position: Vector2) -> bool:
	for index in range(_button_hits.size() - 1, -1, -1):
		var record: Dictionary = _button_hits[index]
		var rect: Rect2 = record.get("rect", Rect2())
		if bool(record.get("enabled", false)) and rect.has_point(position):
			_activate_button(str(record.get("action", "")))
			return true
	return false


func _activate_button(action: String) -> void:
	if action == "layout_focus":
		_set_layout(LAYOUT_FOCUS)
	elif action == "layout_workspace":
		_set_layout(LAYOUT_WORKSPACE)
	elif action == "enter_region":
		_enter_region()
	elif action.begins_with("enter_city:"):
		_enter_city(action.get_slice(":", 1))
	elif action == "close_info":
		info_open = false
		queue_redraw()
	elif action == "back":
		_go_back()
	elif action == "world":
		space_level = WORLD
		_set_world_layer_visible(true)
		queue_redraw()


func _enter_region() -> void:
	if selected_region_id.is_empty():
		return
	space_level = REGION
	info_open = false
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	_set_world_layer_visible(false)
	queue_redraw()


func _enter_city(city_id: String) -> void:
	if city_id.is_empty() or not _city_by_id.has(city_id):
		return
	selected_city_id = city_id
	space_level = CITY
	set_process(false)
	_set_world_layer_visible(false)
	queue_redraw()


func _go_back() -> void:
	if space_level == CITY:
		space_level = REGION
		set_process(false)
	elif space_level == REGION:
		space_level = WORLD
		_set_world_layer_visible(true)
	else:
		info_open = false
	queue_redraw()


func _selected_region_name() -> String:
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	return str(region.get("display_name_zh", "未选择"))


func _city_name() -> String:
	var city: Dictionary = _city_by_id.get(selected_city_id, {})
	return str(city.get("name", "城市"))


func _breadcrumb_text() -> String:
	var text := "世界"
	if not selected_region_id.is_empty():
		text += " / " + _selected_region_name()
	if space_level == CITY:
		text += " / " + _city_name()
	return text


func _lon_lat_from_record(record: Dictionary, key: String) -> Variant:
	var value: Variant = record.get(key, [])
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return null


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


func _lon_lat_to_rect(lon_lat: Vector2, bounds: Rect2, rect: Rect2) -> Vector2:
	var safe_width := maxf(bounds.size.x, 0.001)
	var safe_height := maxf(bounds.size.y, 0.001)
	var x := rect.position.x + ((lon_lat.x - bounds.position.x) / safe_width) * rect.size.x
	var y := rect.end.y - ((lon_lat.y - bounds.position.y) / safe_height) * rect.size.y
	return Vector2(x, y)
