class_name V23FormalMain
extends V23LifeLoopMain
## Product entry retaining the formal map while adding migrated formal services.


func _create_life_simulation() -> V2LifeLoopSimulationPolish:
	return V23FormalSimulation.new()


func _create_life_binding(
	target_simulation: V2LifeLoopSimulationPolish,
	enable_developer_mode: bool
) -> V2LifeLoopUiBindingPolish:
	return V23FormalUiBinding.new(target_simulation, enable_developer_mode)


func get_window_title() -> String:
	return "《1900》— 正式世界、人物生活与个人经济"
