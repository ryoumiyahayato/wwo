class_name V23ControlledUiBinding
extends V23FormalUiBinding
## Presentation and commands for player-authoritative movement and contextual leave.

var controlled_simulation: V23ControlledSimulation


func _init(
	life_simulation: V2LifeLoopSimulation,
	enable_developer_mode: bool = false
) -> void:
	super._init(life_simulation, enable_developer_mode)
	controlled_simulation = life_simulation as V23ControlledSimulation


func person_view(person_id: String = "") -> Dictionary:
	var view: Dictionary = super.person_view(person_id)
	if controlled_simulation == null:
		return view
	var resolved_id: String = str(
		view.get("person_id", selected_person_id())
	)
	var hold_location_id: String = controlled_simulation.manual_hold_for(
		resolved_id
	)
	view["manual_location_hold_id"] = hold_location_id
	view["manual_location_hold"] = not hold_location_id.is_empty()
	if hold_location_id.is_empty():
		return view
	var current_activity: Dictionary = view.get(
		"current_activity", {}
	) as Dictionary
	var source: String = str(current_activity.get("source", ""))
	var expected_location_id: String = str(
		current_activity.get("location_id", "")
	)
	var actual_location_id: String = str(
		view.get("current_location_id", "")
	)
	var location_state: String = str(
		view.get("location_state", "at_location")
	)
	if (
		location_state == "at_location"
		and source in ["default_routine", "contract", "npc_rule"]
		and not expected_location_id.is_empty()
		and expected_location_id != actual_location_id
	):
		var actual_name: String = str(
			view.get("current_location", "未知地点")
		)
		current_activity["activity_type"] = "free_time"
		current_activity["label"] = "停留"
		current_activity["suppressed_automatic_activity"] = true
		current_activity["suppressed_activity_source"] = source
		view["current_activity"] = current_activity
		view["current_work"] = "停留 · %s" % actual_name
		view["plan"] = "等待玩家指令；不会自动离开%s" % actual_name
	return view


func submit_activity_with_leave(
	activity_type: String,
	start_hour: int,
	duration_hours: int
) -> V2LifeLoopResult:
	if controlled_simulation == null:
		return V2LifeLoopResult.fail(
			"controlled_simulation_unavailable",
			"玩家控制模拟不可用"
		)
	last_command_result = controlled_simulation.authorize_leave_and_request_activity(
		selected_person_id(),
		activity_type,
		start_hour,
		duration_hours
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result
