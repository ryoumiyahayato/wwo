extends Node

const TARGET_SCENE: String = "res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn"

var workspace: Control


func _ready() -> void:
	_run_probe.call_deferred()


func _run_probe() -> void:
	var packed_scene: PackedScene = load(TARGET_SCENE) as PackedScene
	if not _require(packed_scene != null, "样机场景无法加载"):
		return
	workspace = packed_scene.instantiate() as Control
	if not _require(workspace != null, "样机场景无法实例化为Control"):
		return
	add_child(workspace)
	await _settle_frames(4)

	var f2_event: InputEventKey = _key_event(KEY_F2)
	workspace.call("_unhandled_key_input", f2_event)
	if not _require(int(workspace.get("layout_mode_id")) == 1, "F2未切换操作桌面布局"):
		return
	var f1_event: InputEventKey = _key_event(KEY_F1)
	workspace.call("_unhandled_key_input", f1_event)
	if not _require(int(workspace.get("layout_mode_id")) == 0, "F1未切换半球聚焦布局"):
		return

	var centre: Vector2 = workspace.get("_hemisphere_center") as Vector2
	var yaw_before: float = float(workspace.get("yaw"))
	_send_mouse_button(centre, true)
	_send_mouse_motion(centre + Vector2(42.0, 0.0), Vector2(42.0, 0.0))
	_send_mouse_button(centre + Vector2(42.0, 0.0), false)
	if not _require(absf(float(workspace.get("yaw")) - yaw_before) > 0.05, "半球拖动未改变经度角"):
		return
	workspace.set("angular_velocity", 0.0)
	workspace.set_process(false)

	workspace.set("yaw", -0.08)
	workspace.set("tilt", -0.18)
	workspace.call("_mark_projection_dirty")
	workspace.call("_ensure_projection_cache")
	var country_anchors: Dictionary = workspace.get("_country_screen_anchors") as Dictionary
	if not _require(country_anchors.has("country_fra"), "默认视角下法兰西国家锚点不可见"):
		return
	var france_point: Vector2 = country_anchors.get("country_fra", Vector2.INF) as Vector2
	_send_mouse_button(france_point, true)
	_send_mouse_button(france_point, false)
	if not _require(str(workspace.get("selected_country_id")) == "country_fra", "点击法兰西锚点未选择国家"):
		return

	workspace.call("_focus_selected_country")
	if not _require(str(workspace.get("world_mode")) == "country_focus", "进入国家后未切换国家聚焦模式"):
		return
	workspace.call("_ensure_projection_cache")

	var regions: Array = workspace.get("_regions") as Array
	var region_polygons: Dictionary = workspace.get("_region_polygons") as Dictionary
	var region_units: Dictionary = workspace.get("_administrative_units_by_region") as Dictionary
	var region_cities: Dictionary = workspace.get("_cities_by_region") as Dictionary
	if not _require(regions.size() == 9, "法兰西宏观大区数量不是9"):
		return
	for region_value: Variant in regions:
		var region: Dictionary = region_value as Dictionary
		var region_id: String = str(region.get("id", ""))
		var polygons: Array = region_polygons.get(region_id, []) as Array
		var units: Array = region_units.get(region_id, []) as Array
		var cities: Array = region_cities.get(region_id, []) as Array
		if not _require(not polygons.is_empty(), "大区缺少几何：" + region_id):
			return
		if not _require(not units.is_empty(), "大区缺少行政分区：" + region_id):
			return
		if not _require(not cities.is_empty(), "大区缺少城市入口：" + region_id):
			return

	var sample_bounds: Rect2 = Rect2(Vector2(0.0, 45.0), Vector2(4.0, 4.0))
	var sample_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(800.0, 400.0))
	var sample_center: Vector2 = sample_bounds.get_center()
	var projected_center: Vector2 = workspace.call("_lon_lat_to_rect", sample_center, sample_bounds, sample_rect) as Vector2
	var projected_lon: Vector2 = workspace.call("_lon_lat_to_rect", sample_center + Vector2(1.0, 0.0), sample_bounds, sample_rect) as Vector2
	var projected_lat: Vector2 = workspace.call("_lon_lat_to_rect", sample_center + Vector2(0.0, 1.0), sample_bounds, sample_rect) as Vector2
	var expected_ratio: float = cos(deg_to_rad(sample_center.y))
	var measured_ratio: float = projected_center.distance_to(projected_lon) / maxf(0.001, projected_center.distance_to(projected_lat))
	if not _require(absf(measured_ratio - expected_ratio) < 0.03, "大区投影未保持统一地理比例"):
		return

	var region_anchors: Dictionary = workspace.get("_focus_region_screen_anchors") as Dictionary
	if not _require(region_anchors.has("northern_industrial_belt"), "北部工业带聚焦锚点不存在"):
		return
	var region_point: Vector2 = region_anchors.get("northern_industrial_belt", Vector2.INF) as Vector2
	_send_mouse_button(region_point, true)
	if not _require(str(workspace.get("selected_region_id")) == "northern_industrial_belt", "点击聚焦地图未选择北部工业带"):
		return

	workspace.call("_enter_region")
	if not _require(str(workspace.get("space_level")) == "region", "进入大区操作未切换到大区层"):
		return
	var viewport_container: SubViewportContainer = workspace.get_node("HemisphereViewportContainer") as SubViewportContainer
	if not _require(viewport_container != null and not viewport_container.visible, "离开世界层后3D视口仍可见"):
		return
	workspace.queue_redraw()
	await _settle_frames(3)

	var administrative_polygons: Dictionary = workspace.get("_administrative_screen_polygons") as Dictionary
	if not _require(administrative_polygons.size() == 5, "北部工业带未绘制5个行政分区"):
		return
	workspace.call("_activate_button", "next_region")
	if not _require(str(workspace.get("selected_region_id")) == "paris_basin", "下一个大区按钮未切换到巴黎盆地"):
		return
	workspace.call("_activate_button", "previous_region")
	if not _require(str(workspace.get("selected_region_id")) == "northern_industrial_belt", "上一个大区按钮未返回北部工业带"):
		return

	workspace.call("_enter_city", "lille")
	if not _require(str(workspace.get("space_level")) == "city", "进入里尔未切换到城市层"):
		return
	if not _require(str(workspace.get("selected_city_id")) == "lille", "城市层没有保留里尔选择"):
		return

	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("space_level")) == "region", "城市层Esc未返回大区层"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("space_level")) == "world" and str(workspace.get("world_mode")) == "country_focus", "大区层Esc未返回国家聚焦层"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("world_mode")) == "countries", "国家聚焦层Esc未返回全球层"):
		return

	workspace.queue_redraw()
	await _settle_frames(3)
	_send_mouse_button(Vector2(50.0, 50.0), true)
	if not _require(str(workspace.get("active_hud_panel")) == "country", "左上国家角点击未打开国家面板"):
		return
	workspace.call("_activate_button", "close_hud_panel")
	workspace.call("_activate_button", "speed:4")
	if not _require(int(workspace.get("sim_speed")) == 4 and not bool(workspace.get("sim_paused")), "速度按钮未设置4倍并解除暂停"):
		return

	workspace.queue_free()
	get_tree().quit(0)


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	workspace.call("_gui_input", event)


func _send_mouse_motion(position: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	workspace.call("_gui_input", event)


func _key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Holographic workspace interaction probe: " + message)
	get_tree().quit(1)
	return false
