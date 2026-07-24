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
