class_name V23LifeLoopMain
extends V2LifeLoopMain
## V2.3 scene adapter retaining the V2.2 map/controller and authoritative clock.

const V2_3_LAUNCH_MODE_META: StringName = &"v2_3_launch_mode"


func _ready() -> void:
	super._ready()
	if life_simulation == null or not life_simulation.initialized:
		return
	var binding: V23LifeLoopUiBinding = life_binding as V23LifeLoopUiBinding
	if binding != null and not binding.view_changed.is_connected(
		_sync_v2_3_map_overlay
	):
		binding.view_changed.connect(_sync_v2_3_map_overlay)
	_sync_v2_3_map_overlay()
	map_canvas.focus_player_location()


func _create_life_simulation() -> V2LifeLoopSimulationPolish:
	return V23LifeLoopSimulation.new()


func _create_life_binding(
	target_simulation: V2LifeLoopSimulationPolish,
	enable_developer_mode: bool
) -> V2LifeLoopUiBindingPolish:
	return V23LifeLoopUiBinding.new(
		target_simulation, enable_developer_mode
	)


func get_window_title() -> String:
	return "《1900》— V2.3 空间、认知与关系闭环"


func _apply_launch_request() -> void:
	var launch_mode: String = str(
		get_tree().get_meta(V2_3_LAUNCH_MODE_META, "")
	)
	if get_tree().has_meta(V2_3_LAUNCH_MODE_META):
		get_tree().remove_meta(V2_3_LAUNCH_MODE_META)
	var result: V2LifeLoopResult
	match launch_mode:
		"load":
			result = life_binding.load_review()
		"migrate":
			result = (
				life_binding as V23LifeLoopUiBinding
			).migrate_v2_2_review()
		_:
			return
	if interface != null and interface.has_method("show_launch_result"):
		interface.call("show_launch_result", result)


func _on_life_state_changed(change_set: Dictionary) -> void:
	super._on_life_state_changed(change_set)
	_sync_v2_3_map_overlay()


func _sync_v2_3_map_overlay() -> void:
	var binding: V23LifeLoopUiBinding = life_binding as V23LifeLoopUiBinding
	if binding == null or map_canvas == null:
		return
	map_canvas.set_v2_3_local_overlay(binding.map_overlay_payload())


func debug_state() -> Dictionary:
	var state: Dictionary = super.debug_state()
	state["v2_3_scene"] = true
	state["map_local_overlay"] = map_canvas.debug_performance_snapshot().get(
		"v2_3_local_overlay", {}
	)
	return state
