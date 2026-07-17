class_name V2LifeLoopMain
extends PrototypeV2Main
## V2.2 scene adapter: advances the authoritative clock and injects live UI state.

const ERROR_OVERLAY_NAME: String = "V2LifeLoopInitializationError"

var life_simulation: V2LifeLoopSimulation
var life_binding: V2LifeLoopUiBinding
var life_initialization_error: String = ""


func _ready() -> void:
	super()
	if prototype_data == null or not prototype_data.errors.is_empty():
		life_initialization_error = "V2 地图与界面数据不可用"
		_show_initialization_error(life_initialization_error)
		set_process(false)
		return
	life_simulation = V2LifeLoopSimulation.new()
	if not life_simulation.initialize():
		life_initialization_error = life_simulation.initialization_error
		push_error("V2.2 生活模拟初始化失败：%s" % life_initialization_error)
		_show_initialization_error(life_initialization_error)
		set_process(false)
		return
	var developer_mode: bool = (
		_has_user_argument("--developer-mode") or interface.review_mode
	)
	life_binding = V2LifeLoopUiBinding.new(life_simulation, developer_mode)
	interface.setup_life_loop(life_binding)
	set_process(true)


func _process(delta: float) -> void:
	if life_simulation != null and life_simulation.initialized:
		life_simulation.advance_real_seconds(delta)


func get_window_title() -> String:
	return "《1900》— V2.2 人物生活闭环原型"


func debug_state() -> Dictionary:
	var state: Dictionary = super()
	state["life_initialized"] = (
		life_simulation != null and life_simulation.initialized
	)
	state["life_initialization_error"] = life_initialization_error
	if life_binding != null:
		state.merge(life_binding.debug_state(), true)
	return state


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
