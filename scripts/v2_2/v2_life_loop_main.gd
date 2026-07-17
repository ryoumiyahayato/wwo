class_name V2LifeLoopMain
extends PrototypeV2Main
## V2.2 scene adapter: advances the authoritative clock and injects live UI state.

var life_simulation: V2LifeLoopSimulation
var life_binding: V2LifeLoopUiBinding
var life_initialization_error: String = ""


func _ready() -> void:
	super()
	if prototype_data == null or not prototype_data.errors.is_empty():
		life_initialization_error = "V2 地图与界面数据不可用"
		return
	life_simulation = V2LifeLoopSimulation.new()
	if not life_simulation.initialize():
		life_initialization_error = life_simulation.initialization_error
		push_error("V2.2 生活模拟初始化失败：%s" % life_initialization_error)
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


func _has_user_argument(argument_name: String) -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == argument_name:
			return true
	return false
