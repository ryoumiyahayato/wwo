class_name V23ControlledUiBinding
extends V23FormalUiBinding
## Presentation and commands for minute time, player movement and contextual leave.

var controlled_simulation: V23ControlledSimulation


func _init(
	life_simulation: V2LifeLoopSimulation,
	enable_developer_mode: bool = false
) -> void:
	super._init(life_simulation, enable_developer_mode)
	controlled_simulation = life_simulation as V23ControlledSimulation
	if (
		simulation != null
		and simulation.clock != null
		and not simulation.clock.time_changed.is_connected(
			_on_clock_time_changed
		)
	):
		simulation.clock.time_changed.connect(_on_clock_time_changed)


func time_view() -> Dictionary:
	var view: Dictionary = super.time_view()
	if simulation == null or not simulation.clock is V23MinuteClock:
		return view
	var minute_clock: V23MinuteClock = simulation.clock as V23MinuteClock
	var snapshot: Dictionary = minute_clock.get_snapshot()
	view["minute"] = int(snapshot.get("minute", 0))
	view["total_minutes"] = int(snapshot.get("total_minutes", 0))
	view["hour_display"] = "%02d:%02d" % [
		int(snapshot.get("hour", 0)),
		int(snapshot.get("minute", 0)),
	]
	view["speed"] = int(snapshot.get("speed_level", 1))
	view["speed_level"] = int(snapshot.get("speed_level", 1))
	view["game_minutes_per_tick"] = int(
		snapshot.get("game_minutes_per_tick", 1)
	)
	view["real_seconds_per_tick"] = float(
		snapshot.get("real_seconds_per_tick", 0.1)
	)
	view["allowed_speeds"] = minute_clock.get_allowed_speeds()
	return view


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
	var raw_expected_location_id: String = str(
		current_activity.get("location_id", "")
	)
	var expected_location_id: String = str(
		V23LifeLoopSimulation.LOCATION_ALIASES.get(
			raw_expected_location_id, raw_expected_location_id
		)
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


func submit_travel_with_leave(request: Dictionary) -> V2LifeLoopResult:
	var product_simulation: V23ProductSimulation = (
		controlled_simulation as V23ProductSimulation
	)
	if product_simulation == null:
		return V2LifeLoopResult.fail(
			"product_simulation_unavailable",
			"旅行请假服务不可用"
		)
	last_command_result = product_simulation.authorize_leave_and_request_travel(
		selected_person_id(),
		str(request.get("destination_id", "")),
		str(request.get("preference", "fastest")),
		int(request.get("start_hour", -1))
	)
	if last_command_result.success:
		route_preview.clear()
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func _on_clock_time_changed(_snapshot: Dictionary) -> void:
	_view_revision += 1
	view_changed.emit()
