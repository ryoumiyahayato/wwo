class_name V2LifeLoopMain
extends WorldMapMain
## V2.2 scene adapter: advances the authoritative clock, injects live UI state,
## and provides Paradox-style map edge scrolling.

const ERROR_OVERLAY_NAME: String = "V2LifeLoopInitializationError"
const EDGE_SCROLL_MARGIN: float = 20.0
const EDGE_SCROLL_MIN_SPEED: float = 240.0
const EDGE_SCROLL_MAX_SPEED: float = 720.0
const LAUNCH_MODE_META: StringName = &"v2_2_launch_mode"

var life_simulation: V2LifeLoopSimulationPolish
var life_binding: V2LifeLoopUiBindingPolish
var life_initialization_error: String = ""
var _activity_panel_was_open: bool = false
var _edge_scrolling_map: bool = false


func _ready() -> void:
	super()
	if prototype_data == null or not prototype_data.errors.is_empty():
		var data_errors: String = (
			"未创建地图数据加载器"
			if prototype_data == null
			else "; ".join(prototype_data.errors)
		)
		life_initialization_error = "地图与界面资源加载失败：%s" % data_errors
		push_error(life_initialization_error)
		_show_initialization_error(life_initialization_error)
		set_process(false)
		return
	life_simulation = V2LifeLoopSimulationPolish.new()
	if not life_simulation.initialize():
		life_initialization_error = life_simulation.initialization_error
		push_error("V2.2 生活模拟初始化失败：%s" % life_initialization_error)
		_show_initialization_error(life_initialization_error)
		set_process(false)
		return
	var developer_mode: bool = (
		_has_user_argument("--developer-mode") or interface.review_mode
	)
	life_binding = V2LifeLoopUiBindingPolish.new(
		life_simulation, developer_mode
	)
	life_binding.save_service = V2ReviewSaveService.new()
	interface.setup_life_loop(life_binding)
	_apply_launch_request()
	if not life_simulation.state_changed.is_connected(_on_life_state_changed):
		life_simulation.state_changed.connect(_on_life_state_changed)
	set_process(true)


func _process(delta: float) -> void:
	if life_simulation != null and life_simulation.initialized:
		life_simulation.advance_real_seconds(delta)
	_sync_activity_panel_read_state()
	_update_edge_scroll(delta)


func get_window_title() -> String:
	return "《1900》— V2.2 人物生活闭环原型"


func debug_state() -> Dictionary:
	var state: Dictionary = super()
	state["life_initialized"] = (
		life_simulation != null and life_simulation.initialized
	)
	state["life_initialization_error"] = life_initialization_error
	state["edge_scroll_enabled"] = true
	state["edge_scroll_margin"] = EDGE_SCROLL_MARGIN
	state["edge_scrolling_map"] = _edge_scrolling_map
	if life_binding != null:
		state.merge(life_binding.debug_state(), true)
	return state


func _apply_launch_request() -> void:
	var launch_mode: String = str(get_tree().get_meta(LAUNCH_MODE_META, ""))
	if get_tree().has_meta(LAUNCH_MODE_META):
		get_tree().remove_meta(LAUNCH_MODE_META)
	if launch_mode != "load":
		return
	var result: V2LifeLoopResult = life_binding.load_review()
	if interface != null and interface.has_method("show_launch_result"):
		interface.call("show_launch_result", result)


func _update_edge_scroll(delta: float) -> void:
	if (
		map_canvas == null
		or interface == null
		or _left_button_down
		or _dragging_map
		or _ui_captured_press
	):
		_stop_edge_scroll()
		return
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	if not viewport_rect.has_point(mouse_position):
		_stop_edge_scroll()
		return
	if interface.contains_point(mouse_position):
		_stop_edge_scroll()
		return

	var direction := Vector2.ZERO
	var strength: float = 0.0
	if mouse_position.x <= viewport_rect.position.x + EDGE_SCROLL_MARGIN:
		var left_strength: float = 1.0 - clampf(
			(mouse_position.x - viewport_rect.position.x) / EDGE_SCROLL_MARGIN,
			0.0,
			1.0
		)
		direction.x -= left_strength
		strength = maxf(strength, left_strength)
	elif mouse_position.x >= viewport_rect.end.x - EDGE_SCROLL_MARGIN:
		var right_strength: float = 1.0 - clampf(
			(viewport_rect.end.x - mouse_position.x) / EDGE_SCROLL_MARGIN,
			0.0,
			1.0
		)
		direction.x += right_strength
		strength = maxf(strength, right_strength)
	if mouse_position.y <= viewport_rect.position.y + EDGE_SCROLL_MARGIN:
		var top_strength: float = 1.0 - clampf(
			(mouse_position.y - viewport_rect.position.y) / EDGE_SCROLL_MARGIN,
			0.0,
			1.0
		)
		direction.y -= top_strength
		strength = maxf(strength, top_strength)
	elif mouse_position.y >= viewport_rect.end.y - EDGE_SCROLL_MARGIN:
		var bottom_strength: float = 1.0 - clampf(
			(viewport_rect.end.y - mouse_position.y) / EDGE_SCROLL_MARGIN,
			0.0,
			1.0
		)
		direction.y += bottom_strength
		strength = maxf(strength, bottom_strength)

	if direction.is_zero_approx():
		_stop_edge_scroll()
		return
	if not _edge_scrolling_map:
		_edge_scrolling_map = true
		map_canvas.begin_camera_interaction()
	var speed: float = lerpf(
		EDGE_SCROLL_MIN_SPEED, EDGE_SCROLL_MAX_SPEED, clampf(strength, 0.0, 1.0)
	)
	map_canvas.pan_by(-direction.normalized() * speed * delta)


func _stop_edge_scroll() -> void:
	if not _edge_scrolling_map:
		return
	_edge_scrolling_map = false
	if map_canvas != null:
		map_canvas.end_camera_interaction()


func _sync_activity_panel_read_state() -> void:
	if life_simulation == null or not life_simulation.initialized:
		_activity_panel_was_open = false
		return
	var panel_open: bool = interface != null and interface.open_panel == "activity"
	if panel_open and not _activity_panel_was_open:
		_mark_visible_notifications_read()
	_activity_panel_was_open = panel_open


func _on_life_state_changed(_change_set: Dictionary) -> void:
	if interface != null and interface.open_panel == "activity":
		_mark_visible_notifications_read()


func _mark_visible_notifications_read() -> void:
	if life_simulation.notifications.unread_count() <= 0:
		return
	if life_simulation.notifications.mark_all_read() > 0 and interface != null:
		interface.queue_redraw()


func _show_initialization_error(message: String) -> void:
	var existing: Node = get_node_or_null(ERROR_OVERLAY_NAME)
	if existing != null:
		existing.queue_free()

	var overlay := ColorRect.new()
	overlay.name = ERROR_OVERLAY_NAME
	overlay.position = Vector2(320.0, 226.0)
	overlay.size = Vector2(640.0, 268.0)
	overlay.color = Color(0.025, 0.045, 0.05, 0.98)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 1000
	add_child(overlay)

	var title := Label.new()
	title.position = Vector2(28.0, 24.0)
	title.size = Vector2(584.0, 34.0)
	title.text = "V2.2 初始化失败"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f1ead9"))
	overlay.add_child(title)

	var detail := Label.new()
	detail.position = Vector2(28.0, 72.0)
	detail.size = Vector2(584.0, 92.0)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text = message if not message.is_empty() else "未提供错误信息"
	detail.add_theme_font_size_override("font_size", 15)
	detail.add_theme_color_override("font_color", Color("#d19a5f"))
	overlay.add_child(detail)

	var hint := Label.new()
	hint.position = Vector2(28.0, 176.0)
	hint.size = Vector2(584.0, 64.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "请记录当前 HEAD、启动命令和第一处 Godot 错误。该画面不代表时间或生活模拟已经运行。"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#bcc2b8"))
	overlay.add_child(hint)


func _has_user_argument(argument_name: String) -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == argument_name:
			return true
	return false
