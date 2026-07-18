class_name PrototypeV2Main
extends Control
## Isolated controller for prototype input, visual state, and review captures.

const DRAG_THRESHOLD: float = 5.0

@onready var map_canvas: PrototypeV2MapCanvas = %PrototypeMap
@onready var interface: PrototypeV2Interface = %PrototypeInterface

var prototype_data: PrototypeV2Data
var _left_button_down: bool = false
var _dragging_map: bool = false
var _ui_captured_press: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _capture_path: String = ""
var _exit_after_capture: bool = false


func _ready() -> void:
	get_viewport().content_scale_size = Vector2i(1280, 720)
	_apply_prototype_window_title.call_deferred()
	prototype_data = PrototypeV2Data.new()
	if not prototype_data.load_all():
		push_error("V2 原型数据加载失败：%s" % "; ".join(prototype_data.errors))
		return
	map_canvas.setup(prototype_data)
	interface.setup(prototype_data)
	interface.mode_requested.connect(_on_mode_requested)
	interface.world_view_requested.connect(_on_world_view_requested)
	interface.selection_clear_requested.connect(_on_selection_clear_requested)
	_parse_review_arguments()
	queue_redraw()


func _apply_prototype_window_title() -> void:
	# Godot applies project metadata during startup, so the isolated scene wins one frame later.
	await get_tree().process_frame
	DisplayServer.window_set_title(get_window_title())


func get_window_title() -> String:
	return "《1900》 — V2 静态视觉原型"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var over_interface: bool = interface.handle_pointer_motion(motion.position)
		if over_interface:
			map_canvas.clear_hovered_country()
		else:
			map_canvas.set_hovered_country_at(motion.position)
		if _left_button_down and not _ui_captured_press:
			if not _dragging_map and motion.position.distance_to(_press_position) >= DRAG_THRESHOLD:
				_dragging_map = true
				map_canvas.begin_camera_interaction()
			if _dragging_map:
				map_canvas.pan_by(motion.relative)
				accept_event()
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not interface.contains_point(button.position):
				map_canvas.zoom_at(1.0, button.position)
			accept_event()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not interface.contains_point(button.position):
				map_canvas.zoom_at(-1.0, button.position)
			accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and button.double_click:
			var focus_target: String = interface.camera_focus_target_at(button.position)
			if focus_target == "person":
				_left_button_down = true
				_ui_captured_press = true
				_dragging_map = false
				map_canvas.focus_player_location()
				interface.show_camera_focus_feedback("已聚焦当前人物所在地 · 里尔")
				accept_event()
				return
			if focus_target == "country":
				_left_button_down = true
				_ui_captured_press = true
				_dragging_map = false
				map_canvas.focus_current_country()
				interface.show_camera_focus_feedback("已聚焦当前国家 · 法国")
				accept_event()
				return
		_left_button_down = button.pressed
		if button.pressed:
			_press_position = button.position
			_dragging_map = false
			_ui_captured_press = interface.handle_pointer_pressed(button.position)
		else:
			if _dragging_map:
				map_canvas.end_camera_interaction()
			if not _ui_captured_press and not _dragging_map:
				_select_map_object(button.position)
			_ui_captured_press = false
			_dragging_map = false
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			if interface.close_top_layer():
				get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F9:
			# Hidden local review aid; ordinary screenshots and play never show it by default.
			interface.set_review_mode(not interface.review_mode)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_SPACE:
			interface.toggle_pause_command()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_HOME:
			map_canvas.focus_world()
			interface.show_camera_focus_feedback("已返回世界视角")
			get_viewport().set_input_as_handled()


func select_review_object(object_type: String, object_id: String) -> bool:
	var object_data: Dictionary
	match object_type:
		"country":
			object_data = map_canvas.get_country(object_id)
		"region":
			object_data = map_canvas.get_region(object_id)
		"city":
			object_data = map_canvas.get_city(object_id)
		"institution":
			object_data = map_canvas.get_institution(object_id)
		"organization":
			object_data = map_canvas.get_organization(object_id)
		_:
			return false
	if object_data.is_empty():
		return false
	map_canvas.set_selection(object_type, object_id)
	interface.set_selected_object({"type": object_type, "id": object_id, "data": object_data})
	return true


func debug_state() -> Dictionary:
	var state: Dictionary = interface.debug_state()
	state["map_mode"] = map_canvas.current_mode
	state["map_zoom"] = map_canvas.zoom
	state["map_pan"] = map_canvas.pan
	state["selected_id"] = map_canvas.selected_id
	state["camera_focus_id"] = map_canvas.camera_focus_id
	state["maximum_zoom"] = map_canvas.get_maximum_zoom()
	return state


func _select_map_object(position: Vector2) -> void:
	var selected: Dictionary = map_canvas.get_object_at(position)
	if selected.is_empty():
		map_canvas.clear_selection()
		interface.set_selected_object({})
		return
	map_canvas.set_selection(str(selected.get("type", "")), str(selected.get("id", "")))
	interface.set_selected_object(selected)


func _on_mode_requested(mode_id: String) -> void:
	map_canvas.set_mode(mode_id)
	interface.set_mode_display(mode_id)


func _on_world_view_requested() -> void:
	map_canvas.focus_world()
	interface.show_camera_focus_feedback("已返回世界视角")


func _on_selection_clear_requested() -> void:
	map_canvas.clear_selection()


func _parse_review_arguments() -> void:
	var view_id: String = ""
	var arguments: PackedStringArray = OS.get_cmdline_args()
	for user_argument: String in OS.get_cmdline_user_args():
		if not arguments.has(user_argument):
			arguments.append(user_argument)
	for argument: String in arguments:
		if argument.begins_with("--prototype-view="):
			view_id = argument.trim_prefix("--prototype-view=")
		elif argument.begins_with("--prototype-capture="):
			_capture_path = argument.trim_prefix("--prototype-capture=")
		elif argument == "--prototype-exit-after-capture":
			_exit_after_capture = true
		elif argument == "--prototype-review":
			interface.set_review_mode(true)
	if not view_id.is_empty():
		_apply_review_state(view_id)
	if not _capture_path.is_empty():
		_capture_review_image.call_deferred()


func _apply_review_state(view_id: String) -> void:
	interface.apply_review_state(view_id)
	map_canvas.set_war_example_active(false)
	match view_id:
		"world_labels":
			map_canvas.reset_view()
			map_canvas.hovered_country_id = "country_lux"
		"europe_mid", "sequence_02_europe":
			map_canvas.focus_europe()
		"france_close", "macro_admin_compare", "label_priority", "sequence_03_france", "city_card", "sequence_04_city":
			map_canvas.focus_france()
			if view_id in ["city_card", "sequence_04_city"]:
				select_review_object("city", "lille")
			elif view_id == "label_priority":
				select_review_object("region", "northern_industrial_belt")
		"nord_close", "camera_focus":
			map_canvas.focus_player_location()
			if view_id == "nord_close":
				select_review_object("city", "lille")
		"market_map":
			map_canvas.set_mode("market")
			interface.set_mode_display("market")
			map_canvas.focus_europe()
		"population_map":
			map_canvas.set_mode("population")
			interface.set_mode_display("population")
			map_canvas.focus_europe()
		"legal_map":
			map_canvas.set_mode("legal")
			interface.set_mode_display("legal")
			map_canvas.focus_europe()
		"war_map":
			map_canvas.set_mode("war")
			interface.set_mode_display("war")
			map_canvas.set_war_example_active(true)
			map_canvas.focus_europe()
		"peace_map":
			map_canvas.set_mode("war")
			interface.set_mode_display("war")
			map_canvas.focus_europe()
		"institution_official", "institution_worker", "official_permissions", "worker_permissions":
			map_canvas.focus_europe()
		"person_card", "person_detail", "person_more_menu", "worker_character", "official_character", "status_symbols", "plan_detail", "owned_organizations", "discover_organizations", "organization_name_tooltip", "official_discover_organizations", "position_salary_tooltip", "official_economy", "world_activity", "time_panel", "system_menu", "activity_toast", "mode_menu", "sequence_05_person", "sequence_06_character", "sequence_07_official", "sequence_08_activity":
			map_canvas.focus_europe()
		_:
			map_canvas.reset_view()
			map_canvas.set_mode("legal")
			interface.set_mode_display("legal")


func _capture_review_image() -> void:
	for _frame: int in range(10):
		await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(_capture_path)
	if error != OK:
		push_error("无法保存原型截图：%s" % _capture_path)
	else:
		print("PROTOTYPE_CAPTURE_SAVED %s" % _capture_path)
	if _exit_after_capture:
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0 if error == OK else 1)
