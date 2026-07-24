class_name HolographicWorkspaceSpike
extends Control

const WORLD := "world"
const REGION := "region"
const CITY := "city"
const LAYOUT_FOCUS := 0
const LAYOUT_WORKSPACE := 1
const RADIUS := 245.0
const EDGE_BAND := 58.0
const DRAG_THRESHOLD := 5.0
const MOTION_EPSILON := 0.0005

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
var _button_rects: Dictionary = {}
var _hemisphere_center := Vector2.ZERO
var _hemisphere_rect := Rect2()

@onready var viewport_container: SubViewportContainer = %HemisphereViewportContainer
@onready var viewport: SubViewport = %HemisphereViewport
@onready var hemisphere_3d: Node3D = %Hemisphere3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_world_data_once()
	_apply_layout()
	_set_world_viewport_active(true)
	queue_redraw()

func _process(delta: float) -> void:
	var hover_spin: float = _edge_hover_spin()
	if absf(angular_velocity) > MOTION_EPSILON or absf(hover_spin) > MOTION_EPSILON:
		yaw += (angular_velocity + hover_spin) * delta
		angular_velocity = lerpf(angular_velocity, 0.0, minf(1.0, delta * 6.5))
		_update_hemisphere_transform()
		queue_redraw()
		return
	angular_velocity = 0.0
	_update_hemisphere_transform()
	_set_world_viewport_idle()
	set_process(false)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_set_layout(LAYOUT_FOCUS)
			accept_event()
			return
		if event.keycode == KEY_F2:
			_set_layout(LAYOUT_WORKSPACE)
			accept_event()
			return
		if event.keycode == KEY_ESCAPE:
			_go_back()
			accept_event()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _handle_button_click(event.position):
			accept_event()
			return
	if space_level != WORLD:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _hemisphere_rect.has_point(event.position):
			dragging = true
			drag_start = event.position
			drag_last = event.position
			drag_moved = false
			angular_velocity = 0.0
			_start_motion()
		elif dragging:
			dragging = false
			if not drag_moved:
				_select_region_at(event.position, true)
	if event is InputEventMouseMotion:
		if dragging:
			var delta: Vector2 = event.position - drag_last
			drag_last = event.position
			if event.position.distance_to(drag_start) > DRAG_THRESHOLD:
				drag_moved = true
			yaw += delta.x * 0.006
			tilt = clampf(tilt + delta.y * 0.0025, -0.62, 0.12)
			angular_velocity = delta.x * 0.018
			_start_motion()
			queue_redraw()
		elif _hemisphere_rect.has_point(event.position):
			_select_region_at(event.position, false)
			if absf(_edge_hover_spin()) > MOTION_EPSILON:
				_start_motion()
		else:
			if not hover_region_id.is_empty():
				hover_region_id = ""
				queue_redraw()

func _draw() -> void:
	_button_rects.clear()
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
		queue_redraw()

func _load_world_data_once() -> void:
	var regions_document: Dictionary = _read_document("res://data/world_map/regions.json")
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
			(_cities_by_region[region_id] as Array).append(city_id)
	_load_coastline_lines()
	_build_region_polygons(regions_document)

func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}

func _read_array(path: String, key: String) -> Array[Dictionary]:
	return _dictionary_array(_read_document(path), key)

func _dictionary_array(document: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in document.get(key, []):
		if value is Dictionary:
			out.append(value)
	return out

func _load_coastline_lines() -> void:
	var document := _read_document("res://data/world_map/world_coastlines.json")
	var count := 0
	for feature in document.get("features", []):
		if count > 180:
			break
		if not feature is Dictionary:
			continue
		for polygon in (feature as Dictionary).get("polygons", []):
			if not polygon is Dictionary:
				continue
			var line := _points_from_raw((polygon as Dictionary).get("outer", []))
			if line.size() > 2:
				_coastline_lines.append(line)
				count += 1

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
						polygons.append(outer)
		_region_polygons[region_id] = polygons

func _points_from_raw(raw_points: Variant) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in raw_points:
		if point is Array and (point as Array).size() >= 2:
			points.append(Vector2(float(point[0]), float(point[1])))
	return points

func _apply_layout() -> void:
	var viewport_size := Vector2i(720, 600) if layout_mode_id == LAYOUT_FOCUS else Vector2i(600, 520)
	viewport.size = viewport_size
	viewport_container.size = Vector2(viewport_size)
	var x := (size.x - float(viewport_size.x)) * 0.5 if layout_mode_id == LAYOUT_FOCUS else maxf(250.0, size.x * 0.42 - float(viewport_size.x) * 0.5)
	viewport_container.position = Vector2(x, maxf(58.0, (size.y - float(viewport_size.y)) * 0.5 + 18.0))
	_hemisphere_center = viewport_container.position + Vector2(viewport_size) * 0.5 + Vector2(0.0, 14.0)
	_hemisphere_rect = Rect2(_hemisphere_center - Vector2(RADIUS, RADIUS), Vector2(RADIUS * 2.0, RADIUS * 2.0))

func _set_layout(id: int) -> void:
	layout_mode_id = id
	_apply_layout()
	if space_level == WORLD:
		_start_motion()
	queue_redraw()

func _start_motion() -> void:
	if space_level != WORLD:
		return
	_set_world_viewport_active(true)
	if not is_processing():
		set_process(true)

func _set_world_viewport_active(active: bool) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_update_hemisphere_transform()

func _set_world_viewport_idle() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if space_level == WORLD else SubViewport.UPDATE_DISABLED

func _update_hemisphere_transform() -> void:
	if hemisphere_3d != null:
		hemisphere_3d.call("set_orbit", yaw, tilt)

func _edge_hover_spin() -> float:
	if space_level != WORLD or dragging:
		return 0.0
	var pos := get_local_mouse_position()
	if not _hemisphere_rect.has_point(pos):
		return 0.0
	var left_power: float = clampf((_hemisphere_rect.position.x + EDGE_BAND - pos.x) / EDGE_BAND, 0.0, 1.0)
	var right_power: float = clampf((pos.x - (_hemisphere_rect.end.x - EDGE_BAND)) / EDGE_BAND, 0.0, 1.0)
	return (right_power - left_power) * 0.32

func _lon_lat_to_rotated_sphere(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	var point := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))
	var yaw_basis := Basis(Vector3.UP, yaw)
	var tilt_basis := Basis(Vector3.RIGHT, tilt)
	return tilt_basis * (yaw_basis * point)

func _sphere_to_screen(point: Vector3) -> Dictionary:
	return {
		"visible": point.z >= 0.01,
		"screen": _hemisphere_center + Vector2(point.x * RADIUS, -point.y * RADIUS),
		"depth": point.z,
	}

func _project_visible(lon_lat: Vector2) -> Dictionary:
	return _sphere_to_screen(_lon_lat_to_rotated_sphere(lon_lat))

func _draw_world_overlay() -> void:
	for line in _coastline_lines:
		_draw_geo_line(line, Color(0.64, 0.84, 0.78, 0.22), 0.8)
	for region_id in _region_polygons.keys():
		var color := Color(0.88, 0.78, 0.48, 0.70) if region_id == selected_region_id else (Color(0.75, 0.9, 0.86, 0.52) if region_id == hover_region_id else Color(0.72, 0.78, 0.72, 0.20))
		for polygon in _region_polygons[region_id]:
			_draw_geo_line(polygon, color, 1.15 if region_id == selected_region_id else 0.7)
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
			draw_circle(projection.get("screen", Vector2.ZERO), 3.2, Color(0.9, 0.76, 0.44, 0.74))
			shown += 1
	if not hover_region_id.is_empty():
		var region: Dictionary = _region_by_id.get(hover_region_id, {})
		var anchor := _lon_lat_from_record(region, "label_lon_lat")
		if anchor != null:
			var anchor_projection := _project_visible(anchor)
			if bool(anchor_projection.get("visible", false)):
				_draw_label(anchor_projection.get("screen", Vector2.ZERO) + Vector2(8.0, -8.0), str(region.get("display_name_zh", region.get("name", ""))))

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
	var best := ""
	for region_id in _region_polygons.keys():
		for polygon in _region_polygons[region_id]:
			var projected_polygon := _project_polygon_for_hit(polygon)
			if projected_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(pos, projected_polygon):
				best = str(region_id)
				break
		if not best.is_empty():
			break
	if best.is_empty():
		best = _nearest_visible_region_anchor(pos)
	if hover_region_id != best:
		hover_region_id = best
		queue_redraw()
	if click and not best.is_empty():
		selected_region_id = best
		info_open = true
		queue_redraw()

func _project_polygon_for_hit(points: PackedVector2Array) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for lon_lat in points:
		var data := _project_visible(lon_lat)
		if bool(data.get("visible", false)):
			projected.append(data.get("screen", Vector2.ZERO))
	return projected

func _nearest_visible_region_anchor(pos: Vector2) -> String:
	var best := ""
	var best_distance := 99999.0
	for region in _regions:
		var anchor := _lon_lat_from_record(region, "label_lon_lat")
		if anchor == null:
			continue
		var projected := _project_visible(anchor)
		if not bool(projected.get("visible", false)):
			continue
		var distance := pos.distance_to(projected.get("screen", Vector2.ZERO))
		if distance < best_distance and distance < 42.0:
			best = str(region.get("id", ""))
			best_distance = distance
	return best

func _draw_region_map() -> void:
	_set_world_viewport_active(false)
	var rect := Rect2(150.0, 120.0, size.x - 300.0, size.y - 210.0)
	_panel(rect, Color(0.025, 0.047, 0.052, 0.88), Color(0.7, 0.62, 0.36, 0.32))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(rect.position + Vector2(24.0, 34.0), "二维大区层 · " + str(region.get("display_name_zh", "选中大区")), 17)
	_draw_label(rect.position + Vector2(24.0, 58.0), "真实边界：所属行政单位外边界；交通：样机占位", 12, Color(0.73, 0.82, 0.78, 1.0))
	_draw_region_flat_geometry(rect)
	_draw_region_cities(rect)

func _draw_region_flat_geometry(rect: Rect2) -> void:
	var polygons: Array = _region_polygons.get(selected_region_id, [])
	var bounds := _lon_lat_bounds(polygons)
	for polygon in polygons:
		var flat := PackedVector2Array()
		for lon_lat in polygon:
			flat.append(_lon_lat_to_rect(lon_lat, bounds, rect.grow(-70.0)))
		if flat.size() > 2:
			draw_colored_polygon(flat, Color(0.32, 0.48, 0.48, 0.20))
			draw_polyline(flat, Color(0.83, 0.75, 0.48, 0.70), 1.4, true)
	for index in range(3):
		var y := rect.position.y + 110.0 + float(index) * 48.0
		draw_line(Vector2(rect.position.x + 70.0, y), Vector2(rect.end.x - 70.0, y + 20.0), Color(0.55, 0.75, 0.68, 0.20), 1.4)

func _draw_region_cities(rect: Rect2) -> void:
	var city_ids: Array = _cities_by_region.get(selected_region_id, [])
	if city_ids.is_empty():
		_draw_label(rect.position + Vector2(86.0, rect.size.y - 60.0), "当前大区没有配置城市入口", 13, Color(0.95, 0.72, 0.43, 1.0))
		return
	var bounds := _lon_lat_bounds(_region_polygons.get(selected_region_id, []))
	var index := 0
	for city_id in city_ids:
		var city: Dictionary = _city_by_id.get(str(city_id), {})
		var lon_lat := _lon_lat_from_record(city, "lon_lat")
		if lon_lat == null:
			continue
		var point := _lon_lat_to_rect(lon_lat, bounds, rect.grow(-70.0))
		draw_circle(point, 6.0, Color(0.88, 0.74, 0.42, 0.86))
		_draw_label(point + Vector2(10.0, 4.0), str(city.get("name", "城市")), 12)
		var button_rect := Rect2(point + Vector2(-34.0, 12.0), Vector2(96.0, 26.0))
		_draw_button(button_rect, "进入城市", "enter_city:" + str(city_id), true)
		index += 1

func _draw_city_map() -> void:
	_set_world_viewport_active(false)
	var rect := Rect2(180.0, 130.0, size.x - 360.0, size.y - 230.0)
	_panel(rect, Color(0.03, 0.04, 0.04, 0.9), Color(0.72, 0.75, 0.66, 0.24))
	var city: Dictionary = _city_by_id.get(selected_city_id, {})
	_draw_label(rect.position + Vector2(24.0, 34.0), "城市本地层占位 · " + str(city.get("name", "本地城市")), 17)
	_draw_label(rect.position + Vector2(24.0, 58.0), "本层仅验证城市进入/返回，不声明接入正式城市本地地图", 12, Color(0.73, 0.82, 0.78, 1.0))
	var labels := ["市政厅", "车站", "工会会馆", "市场", "报社", "居住区"]
	var points: Array[Vector2] = []
	for index in range(labels.size()):
		points.append(rect.position + Vector2(130.0 + float(index % 3) * 190.0, 155.0 + float(index / 3) * 90.0))
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], Color(0.6, 0.68, 0.62, 0.28), 2.0)
	for index in range(labels.size()):
		draw_circle(points[index], 7.0, Color(0.82, 0.8, 0.62, 0.78))
		_draw_label(points[index] + Vector2(12.0, 5.0), labels[index], 12)

func _draw_corners() -> void:
	_panel(Rect2(18.0, 18.0, 284.0, 66.0), Color(0.025, 0.055, 0.06, 0.82), Color(0.72, 0.64, 0.38, 0.22))
	_draw_label(Vector2(78.0, 43.0), "法兰西第三共和国", 16)
	_draw_label(Vector2(78.0, 64.0), "国家 / 政权 / 机构入口", 11, Color(0.76, 0.67, 0.39, 1.0))
	draw_circle(Vector2(48.0, 51.0), 18.0, Color(0.9, 0.88, 0.78, 0.8))
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
	var height := minf(size.y * 0.42, 245.0)
	var rect := Rect2(size.x * 0.18, 8.0, size.x * 0.64, height)
	_panel(rect, Color(0.018, 0.035, 0.038, 0.92), Color(0.78, 0.70, 0.46, 0.36))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(rect.position + Vector2(24.0, 34.0), str(region.get("display_name_zh", "空间对象")), 20)
	_draw_label(rect.position + Vector2(24.0, 62.0), "世界 / 法兰西第三共和国 / " + str(region.get("display_name_zh", "大区")), 12, Color(0.73, 0.82, 0.78, 1.0))
	_draw_label(rect.position + Vector2(24.0, 98.0), "摘要：法国宏观大区样例；边界来自所属行政单位经纬度多边形。", 13)
	_draw_button(Rect2(rect.end.x - 192.0, rect.end.y - 52.0, 132.0, 34.0), "进入大区", "enter_region", not selected_region_id.is_empty())
	_draw_button(Rect2(rect.end.x - 52.0, rect.position.y + 12.0, 34.0, 28.0), "×", "close_info", true)

func _draw_layout_switch() -> void:
	_draw_button(Rect2(size.x * 0.5 - 92.0, size.y - 42.0, 84.0, 28.0), "F1 半球", "layout_focus", true)
	_draw_button(Rect2(size.x * 0.5 + 8.0, size.y - 42.0, 96.0, 28.0), "F2 桌面", "layout_workspace", true)
	if layout_mode_id == LAYOUT_WORKSPACE and space_level == WORLD:
		var rect := Rect2(size.x - 390.0, 118.0, 318.0, 210.0)
		_panel(rect, Color(0.02, 0.043, 0.046, 0.86), Color(0.65, 0.78, 0.70, 0.24))
		_draw_label(rect.position + Vector2(20.0, 30.0), "当前区域工作空间", 16)
		_draw_label(rect.position + Vector2(20.0, 62.0), "选择：" + _selected_region_name(), 12)
		_draw_label(rect.position + Vector2(20.0, 92.0), "层级：世界 → 大区 → 城市", 12)
		_draw_button(Rect2(rect.position.x + 20.0, rect.end.y - 52.0, 118.0, 32.0), "进入大区", "enter_region", not selected_region_id.is_empty())

func _draw_breadcrumbs() -> void:
	_draw_label(Vector2(24.0, 112.0), _breadcrumb_text(), 13, Color(0.76, 0.82, 0.78, 1.0))
	if space_level != WORLD:
		_draw_button(Rect2(24.0, 132.0, 92.0, 30.0), "返回上层", "back", true)
		_draw_button(Rect2(126.0, 132.0, 92.0, 30.0), "返回世界", "world", true)

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.023, 0.027, 1.0))

func _draw_button(rect: Rect2, label: String, action: String, enabled: bool) -> void:
	_button_rects[action] = {"rect": rect, "enabled": enabled}
	var fill := Color(0.08, 0.10, 0.095, 0.86) if enabled else Color(0.05, 0.055, 0.052, 0.62)
	var border := Color(0.72, 0.64, 0.38, 0.30) if enabled else Color(0.36, 0.34, 0.28, 0.22)
	_panel(rect, fill, border)
	_draw_label(rect.position + Vector2(12.0, rect.size.y * 0.62), label, 12, Color(0.9, 0.91, 0.84, 1.0) if enabled else Color(0.55, 0.57, 0.53, 1.0))

func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 1.0)

func _draw_label(pos: Vector2, text: String, font_size: int = 12, color: Color = Color(0.9, 0.91, 0.84, 1.0)) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _handle_button_click(position: Vector2) -> bool:
	for action in _button_rects.keys():
		var record: Dictionary = _button_rects[action]
		if bool(record.get("enabled", false)) and (record.get("rect", Rect2()) as Rect2).has_point(position):
			_activate_button(str(action))
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
		_set_world_viewport_active(true)
		_start_motion()
		queue_redraw()

func _enter_region() -> void:
	if selected_region_id.is_empty():
		return
	space_level = REGION
	info_open = false
	dragging = false
	set_process(false)
	_set_world_viewport_active(false)
	queue_redraw()

func _enter_city(city_id: String) -> void:
	if city_id.is_empty() or not _city_by_id.has(city_id):
		return
	selected_city_id = city_id
	space_level = CITY
	set_process(false)
	_set_world_viewport_active(false)
	queue_redraw()

func _go_back() -> void:
	if space_level == CITY:
		space_level = REGION
		set_process(false)
	elif space_level == REGION:
		space_level = WORLD
		_set_world_viewport_active(true)
		_start_motion()
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
