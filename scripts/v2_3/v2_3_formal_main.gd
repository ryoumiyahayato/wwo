class_name V23FormalMain
extends V23LifeLoopMain
## Product entry retaining the formal map with minute time and player authority.


func _create_life_simulation() -> V2LifeLoopSimulationPolish:
	return V23ProductSimulationV2.new()


func _create_life_binding(
	target_simulation: V2LifeLoopSimulationPolish,
	enable_developer_mode: bool
) -> V2LifeLoopUiBindingPolish:
	return V23PlayerUiBinding.new(target_simulation, enable_developer_mode)


func get_window_title() -> String:
	return BuildInfo.window_title()
