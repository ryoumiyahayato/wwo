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
var _data_loaded: bool = false
var _regions: Array[Dictionary] = []
var _countries: Array[Dictionary] = []
var _cities: Array[Dictionary] = []
var _coastline_lines: Array[PackedVector2Array] = []
var _region_lines: Dictionary = {}
var _region_by_id: Dictionary = {}
var _city_by_id: Dictionary = {}
var _hemisphere_center := Vector2.ZERO
var _hemisphere_rect := Rect2()
var _needs_motion: bool = true

@onready var viewport_container: SubViewportContainer = %HemisphereViewportContainer
@onready var viewport: SubViewport = %HemisphereViewport
@onready var hemisphere_3d: Node3D = %Hemisphere3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_world_data_once()
	_apply_layout()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var hover_spin: float = _edge_hover_spin()
	if absf(angular_velocity) > 0.0005 or absf(hover_spin) > 0.0005:
		yaw += (angular_velocity + hover_spin) * delta
		angular_velocity = lerpf(angular_velocity, 0.0, minf(1.0, delta * 6.5))
		_mark_motion()
	else:
		angular_velocity = 0.0
		if _needs_motion:
			_needs_motion = false
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			set_process(space_level == WORLD)
	if hemisphere_3d != null:
		hemisphere_3d.call("set_orbit", yaw, tilt)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_set_layout(LAYOUT_FOCUS)
		elif event.keycode == KEY_F2:
			_set_layout(LAYOUT_WORKSPACE)
		elif event.keycode == KEY_ESCAPE:
			_go_back()
	if space_level != WORLD:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _handle_button_click(event.position):
			accept_event()
			return
		if event.pressed and _hemisphere_rect.has_point(event.position):
			dragging = true; drag_start = event.position; drag_last = event.position; drag_moved = false; angular_velocity = 0.0; _mark_motion()
		elif dragging:
			dragging = false
			if not drag_moved:
				_select_region_at(event.position, true)
	if event is InputEventMouseMotion:
		if dragging:
			var delta: Vector2 = event.position - drag_last
			drag_last = event.position
			if event.position.distance_to(drag_start) > DRAG_THRESHOLD: drag_moved = true
			yaw += delta.x * 0.006
			tilt = clampf(tilt + delta.y * 0.0025, -0.62, 0.12)
			angular_velocity = delta.x * 0.018
			_mark_motion()
		elif _hemisphere_rect.has_point(event.position):
			_select_region_at(event.position, false)
		else:
			hover_region_id = ""

func _draw() -> void:
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
		_apply_layout(); queue_redraw()

func _load_world_data_once() -> void:
	if _data_loaded: return
	_countries = _read_array("res://data/world_map/countries.json", "countries")
	_regions = _read_array("res://data/world_map/regions.json", "regions")
	_cities = _read_array("res://data/world_map/cities.json", "cities")
	for region in _regions: _region_by_id[str(region.get("id", ""))] = region
	for city in _cities: _city_by_id[str(city.get("id", ""))] = city
	_load_coastline_lines()
	_build_region_placeholder_lines()
	_data_loaded = true

func _read_array(path: String, key: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var out: Array[Dictionary] = []
	if parsed is Dictionary:
		for v in (parsed as Dictionary).get(key, []):
			if v is Dictionary: out.append(v)
	return out

func _load_coastline_lines() -> void:
	var file := FileAccess.open("res://data/world_map/world_coastlines.json", FileAccess.READ)
	if file == null: return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return
	var count := 0
	for feature in (parsed as Dictionary).get("features", []):
		if count > 160: break
		for polygon in (feature as Dictionary).get("polygons", []):
			var line := PackedVector2Array()
			for point in (polygon as Dictionary).get("outer", []):
				if point is Array and (point as Array).size() >= 2: line.append(Vector2(float(point[0]), float(point[1])))
			if line.size() > 2: _coastline_lines.append(line); count += 1

func _build_region_placeholder_lines() -> void:
	for region in _regions:
		var anchor: Array = region.get("label_lon_lat", region.get("label_anchor", [])) as Array
		if anchor.size() < 2: continue
		var lon := float(anchor[0]); var lat := float(anchor[1]); var ring := PackedVector2Array()
		for i in range(25):
			var a := TAU * float(i) / 24.0
			ring.append(Vector2(lon + cos(a) * 3.2, lat + sin(a) * 1.7))
		_region_lines[str(region.get("id", ""))] = ring

func _apply_layout() -> void:
	var s := size
	var vp_size := Vector2i(720, 600) if layout_mode_id == LAYOUT_FOCUS else Vector2i(600, 520)
	viewport.size = vp_size
	viewport_container.size = Vector2(vp_size)
	var x := (s.x - vp_size.x) * 0.5 if layout_mode_id == LAYOUT_FOCUS else maxf(250.0, s.x * 0.42 - vp_size.x * 0.5)
	viewport_container.position = Vector2(x, maxf(58.0, (s.y - vp_size.y) * 0.5 + 18.0))
	_hemisphere_center = viewport_container.position + Vector2(vp_size) * 0.5 + Vector2(0, 14)
	_hemisphere_rect = Rect2(_hemisphere_center - Vector2(RADIUS, RADIUS * 0.72), Vector2(RADIUS * 2.0, RADIUS * 1.44))

func _set_layout(id: int) -> void:
	layout_mode_id = id; _apply_layout(); _mark_motion(); queue_redraw()

func _mark_motion() -> void:
	_needs_motion = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not is_processing():
		set_process(true)

func _edge_hover_spin() -> float:
	if space_level != WORLD or dragging: return 0.0
	var pos := get_local_mouse_position()
	if not _hemisphere_rect.has_point(pos): return 0.0
	var left_power: float = clampf((_hemisphere_rect.position.x + EDGE_BAND - pos.x) / EDGE_BAND, 0.0, 1.0)
	var right_power: float = clampf((pos.x - (_hemisphere_rect.end.x - EDGE_BAND)) / EDGE_BAND, 0.0, 1.0)
	return (right_power - left_power) * 0.32

func _project(lon_lat: Vector2) -> Vector2:
	var lon := deg_to_rad(lon_lat.x) + yaw
	var lat := deg_to_rad(lon_lat.y) + tilt * 0.35
	return _hemisphere_center + Vector2(sin(lon) * cos(lat) * RADIUS, -sin(lat) * RADIUS * 0.72)

func _draw_world_overlay() -> void:
	draw_arc(_hemisphere_center, RADIUS, PI, TAU, 96, Color(0.82, 0.82, 0.72, 0.24), 1.4)
	for line in _coastline_lines: _draw_geo_line(line, Color(0.64, 0.84, 0.78, 0.22), 0.8)
	for region_id in _region_lines.keys():
		var color := Color(0.88, 0.78, 0.48, 0.62) if region_id == selected_region_id else (Color(0.75, 0.9, 0.86, 0.46) if region_id == hover_region_id else Color(0.72, 0.78, 0.72, 0.18))
		_draw_geo_line(_region_lines[region_id], color, 1.1 if region_id == selected_region_id else 0.7)
	var shown := 0
	for city in _cities:
		if shown >= 8: break
		if not bool(city.get("major", false)): continue
		var p := _project(Vector2(float(city.get("lon_lat", [0,0])[0]), float(city.get("lon_lat", [0,0])[1])))
		draw_circle(p, 3.2, Color(0.9, 0.76, 0.44, 0.74)); shown += 1
	if not hover_region_id.is_empty():
		var r: Dictionary = _region_by_id.get(hover_region_id, {})
		_draw_label(_project(Vector2(float(r.get("label_lon_lat", [0,0])[0]), float(r.get("label_lon_lat", [0,0])[1]))) + Vector2(8,-8), str(r.get("display_name_zh", r.get("name", ""))))

func _draw_geo_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var projected := PackedVector2Array()
	for p in points:
		projected.append(_project(p))
	if projected.size() > 1: draw_polyline(projected, color, width, true)

func _select_region_at(pos: Vector2, click: bool) -> void:
	var best := ""; var best_d := 99999.0
	for region in _regions:
		var anchor: Array = region.get("label_lon_lat", []) as Array
		if anchor.size() < 2: continue
		var d := pos.distance_to(_project(Vector2(float(anchor[0]), float(anchor[1]))))
		if d < best_d and d < 42.0: best = str(region.get("id", "")); best_d = d
	hover_region_id = best
	if click and not best.is_empty(): selected_region_id = best; info_open = true; queue_redraw()

func _draw_region_map() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := Rect2(150, 120, size.x - 300, size.y - 210); _panel(rect, Color(0.025,0.047,0.052,0.88), Color(0.7,0.62,0.36,0.32))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(rect.position + Vector2(24, 34), "二维大区交通层 · " + str(region.get("display_name_zh", "选中大区")), 17)
	for i in range(7): draw_line(rect.position + Vector2(80+i*90, rect.size.y*0.25), rect.position + Vector2(130+i*82, rect.size.y*0.75), Color(0.55,0.75,0.68,0.26), 2)
	var shown := 0
	for city in _cities:
		if str(city.get("parent_region_id", "")) != selected_region_id: continue
		var p := rect.position + Vector2(110 + shown * 118, 160 + (shown % 3) * 55)
		draw_circle(p, 6, Color(0.88,0.74,0.42,0.8)); _draw_label(p + Vector2(10,4), str(city.get("name", "城市")), 12)
		shown += 1
		if shown >= 5: break
	_draw_button(Rect2(rect.end.x - 170, rect.end.y - 52, 136, 34), "进入城市", "enter_city")

func _draw_city_map() -> void:
	var rect := Rect2(180, 130, size.x - 360, size.y - 230); _panel(rect, Color(0.03,0.04,0.04,0.9), Color(0.72,0.75,0.66,0.24))
	var city: Dictionary = _city_by_id.get(selected_city_id, {})
	_draw_label(rect.position + Vector2(24, 34), "城市本地层 · " + str(city.get("name", "本地城市")), 17)
	for i in range(5): draw_line(rect.position + Vector2(80,120+i*48), rect.end - Vector2(80,90+i*22), Color(0.6,0.68,0.62,0.28), 2)
	for i in range(6):
		var p := rect.position + Vector2(130 + (i%3)*190, 155 + int(i/3)*90)
		draw_circle(p, 7, Color(0.82,0.8,0.62,0.78)); _draw_label(p+Vector2(12,5), ["市政厅","车站","工会会馆","市场","报社","居住区"][i], 12)

func _draw_corners() -> void:
	_panel(Rect2(18,18,284,66), Color(0.025,0.055,0.06,0.82), Color(0.72,0.64,0.38,0.22)); _draw_label(Vector2(78,43), "法兰西第三共和国", 16); _draw_label(Vector2(78,64), "国家 / 政权 / 机构入口", 11, Color(0.76,0.67,0.39,1)); draw_circle(Vector2(48,51), 18, Color(0.9,0.88,0.78,0.8))
	_panel(Rect2(size.x-244,18,226,66), Color(0.025,0.055,0.06,0.82), Color(0.72,0.64,0.38,0.22)); _draw_label(Vector2(size.x-226,43), "1900年3月12日", 14); _draw_label(Vector2(size.x-226,64), "Ⅱ 暂停 · 1×  2×  4×", 11, Color(0.82,0.72,0.44,1))
	_panel(Rect2(18,size.y-88,286,70), Color(0.025,0.055,0.06,0.82), Color(0.72,0.64,0.38,0.22)); draw_circle(Vector2(50,size.y-52), 22, Color(0.56,0.68,0.62,0.75)); _draw_label(Vector2(80,size.y-61), "让·马丁", 16); _draw_label(Vector2(80,size.y-40), "铁路工人 · 个人层级入口", 11, Color(0.76,0.67,0.39,1))
	_panel(Rect2(size.x-300,size.y-92,282,74), Color(0.025,0.055,0.06,0.82), Color(0.72,0.50,0.25,0.22)); _draw_label(Vector2(size.x-282,size.y-66), "! 已知信息", 12, Color(0.95,0.72,0.43,1)); _draw_label(Vector2(size.x-282,size.y-42), "北部交通状态更新 · 未读 2", 12)

func _draw_top_info() -> void:
	if not info_open: return
	var h := minf(size.y * 0.42, 245.0); var rect := Rect2(size.x*0.18, 8, size.x*0.64, h)
	_panel(rect, Color(0.018,0.035,0.038,0.92), Color(0.78,0.70,0.46,0.36))
	var region: Dictionary = _region_by_id.get(selected_region_id, {})
	_draw_label(rect.position + Vector2(24,34), str(region.get("display_name_zh", "空间对象")), 20)
	_draw_label(rect.position + Vector2(24,62), "世界 / 法兰西第三共和国 / " + str(region.get("display_name_zh", "大区")), 12, Color(0.73,0.82,0.78,1))
	_draw_label(rect.position + Vector2(24,98), "摘要：复用现有地图数据的层级位置与少量交通、城市入口。内容为 UI 样机占位。", 13)
	_draw_button(Rect2(rect.end.x-192, rect.end.y-52, 132, 34), "进入大区", "enter_region")
	_draw_button(Rect2(rect.end.x-52, rect.position.y+12, 34, 28), "×", "close_info")

func _draw_layout_switch() -> void:
	_draw_button(Rect2(size.x*0.5-92, size.y-42, 84, 28), "F1 半球", "layout_focus")
	_draw_button(Rect2(size.x*0.5+8, size.y-42, 96, 28), "F2 桌面", "layout_workspace")
	if layout_mode_id == LAYOUT_WORKSPACE and space_level == WORLD:
		var rect := Rect2(size.x-390, 118, 318, 210); _panel(rect, Color(0.02,0.043,0.046,0.86), Color(0.65,0.78,0.70,0.24)); _draw_label(rect.position+Vector2(20,30), "当前区域工作空间", 16); _draw_label(rect.position+Vector2(20,62), "选择：" + _selected_region_name(), 12); _draw_label(rect.position+Vector2(20,92), "层级：世界 → 大区 → 城市", 12); _draw_button(Rect2(rect.position.x+20, rect.end.y-52, 118, 32), "进入大区", "enter_region")

func _draw_breadcrumbs() -> void:
	_draw_label(Vector2(24,112), "世界" + (" / " + _selected_region_name() if not selected_region_id.is_empty() else "") + (" / " + _city_name() if space_level == CITY else ""), 13, Color(0.76,0.82,0.78,1))
	if space_level != WORLD:
		_draw_button(Rect2(24,132,92,30), "返回上层", "back")
		_draw_button(Rect2(126,132,92,30), "返回世界", "world")

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018,0.023,0.027,1))

func _draw_button(rect: Rect2, label: String, action: String) -> void:
	_panel(rect, Color(0.08,0.10,0.095,0.86), Color(0.72,0.64,0.38,0.30)); _draw_label(rect.position + Vector2(12, rect.size.y*0.62), label, 12)

func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill); draw_rect(rect, border, false, 1.0)

func _draw_label(pos: Vector2, text: String, font_size: int = 12, color: Color = Color(0.9,0.91,0.84,1)) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _selected_region_name() -> String:
	var r: Dictionary = _region_by_id.get(selected_region_id, {})
	return str(r.get("display_name_zh", "未选择"))
func _city_name() -> String:
	var c: Dictionary = _city_by_id.get(selected_city_id, {})
	return str(c.get("name", "城市"))

func _handle_button_click(p: Vector2) -> bool:
	# Lightweight button hit map; labels are stable enough for this isolated spike.
	if Rect2(size.x * 0.5 - 92.0, size.y - 42.0, 84.0, 28.0).has_point(p):
		_set_layout(LAYOUT_FOCUS)
		return true
	if Rect2(size.x * 0.5 + 8.0, size.y - 42.0, 96.0, 28.0).has_point(p):
		_set_layout(LAYOUT_WORKSPACE)
		return true
	if info_open and Rect2(size.x * 0.82 - 192.0, 8.0 + minf(size.y * 0.42, 245.0) - 52.0, 132.0, 34.0).has_point(p):
		_enter_region()
		return true
	if info_open and Rect2(size.x * 0.82 - 52.0, 20.0, 34.0, 28.0).has_point(p):
		info_open = false
		queue_redraw()
		return true
	if space_level != WORLD and Rect2(24.0, 132.0, 92.0, 30.0).has_point(p):
		_go_back()
		return true
	if space_level != WORLD and Rect2(126.0, 132.0, 92.0, 30.0).has_point(p):
		space_level = WORLD
		_mark_motion()
		queue_redraw()
		return true
	if space_level == REGION:
		selected_city_id = _first_city_in_region()
		space_level = CITY
		queue_redraw()
		return true
	return false

func _enter_region() -> void:
	if selected_region_id.is_empty(): return
	space_level = REGION; info_open = false; viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED; set_process(false); queue_redraw()
func _go_back() -> void:
	if space_level == CITY: space_level = REGION
	elif space_level == REGION: space_level = WORLD; _mark_motion()
	else: info_open = false
	queue_redraw()
func _first_city_in_region() -> String:
	for c in _cities:
		if str(c.get("parent_region_id", "")) == selected_region_id: return str(c.get("id", ""))
	return "paris"
