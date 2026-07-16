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
	DisplayServer.window_set_title("《1900》 — V2 静态视觉原型")
	prototype_data = PrototypeV2Data.new()
	if not prototype_data.load_all():
		push_error("V2 原型数据加载失败：%s" % "; ".join(prototype_data.errors))
		return
	map_canvas.setup(
		prototype_data.get_document("regions"),
		prototype_data.get_document("map_modes")
	)
	interface.setup(prototype_data)
	interface.mode_requested.connect(_on_mode_requested)
	interface.selection_clear_requested.connect(_on_selection_clear_requested)
	_parse_review_arguments()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		interface.handle_pointer_motion(motion.position)
		if _left_button_down and not _ui_captured_press:
			if not _dragging_map and motion.position.distance_to(_press_position) >= DRAG_THRESHOLD:
				_dragging_map = true
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
		_left_button_down = button.pressed
		if button.pressed:
			_press_position = button.position
			_dragging_map = false
			_ui_captured_press = interface.handle_pointer_pressed(button.position)
		else:
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
		elif key.keycode == KEY_SPACE:
			interface.paused = not interface.paused
			interface.queue_redraw()
			get_viewport().set_input_as_handled()


func select_review_object(object_type: String, object_id: String) -> bool:
	var object_data: Dictionary
	if object_type == "region":
		object_data = map_canvas.get_region(object_id)
	elif object_type == "city":
		object_data = map_canvas.get_city(object_id)
	else:
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


func _on_selection_clear_requested() -> void:
	map_canvas.clear_selection()


func _parse_review_arguments() -> void:
	var view_id: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--prototype-view="):
			view_id = argument.trim_prefix("--prototype-view=")
		elif argument.begins_with("--prototype-capture="):
			_capture_path = argument.trim_prefix("--prototype-capture=")
		elif argument == "--prototype-exit-after-capture":
			_exit_after_capture = true
	if not view_id.is_empty():
		_apply_review_state(view_id)
	if not _capture_path.is_empty():
		_capture_review_image.call_deferred()


func _apply_review_state(view_id: String) -> void:
	interface.apply_review_state(view_id)
	match view_id:
		"market_region":
			map_canvas.set_mode("market")
			interface.set_mode_display("market")
			select_review_object("region", "western_europe")
		"war_map":
			map_canvas.set_mode("war")
			interface.set_mode_display("war")
		"peace_map":
			map_canvas.set_mode("legal")
			interface.set_mode_display("legal")
		_:
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
		get_tree().quit(0 if error == OK else 1)
