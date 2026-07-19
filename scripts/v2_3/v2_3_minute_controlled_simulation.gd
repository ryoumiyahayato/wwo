class_name V23MinuteControlledSimulation
extends V23ControlledSimulation
## Product composition root: minute clock plus player-authoritative movement.

const MINUTE_CLOCK_PATH: String = "res://data/v2_3/minute_clock.json"


func initialize(simulation_clock: SimulationClock = null) -> bool:
	var resolved_clock: SimulationClock = simulation_clock
	if resolved_clock == null:
		var clock_config := SimulationClockConfig.new()
		var load_error: Error = clock_config.load_from_file(
			MINUTE_CLOCK_PATH
		)
		if load_error != OK:
			initialization_error = clock_config.error_message
			return false
		resolved_clock = V23MinuteClock.new(clock_config)
	return super.initialize(resolved_clock)


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	if clock is V23MinuteClock:
		state["formal_minute_clock_state"] = (
			(clock as V23MinuteClock).get_persistent_state()
		)
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var base_result: V2LifeLoopResult = super.validate_v2_3_state(state)
	if not base_result.success:
		return base_result
	if state.has("formal_minute_clock_state") and not state.get(
		"formal_minute_clock_state", {}
	) is Dictionary:
		return V2LifeLoopResult.fail(
			"corrupt_save", "分钟时钟存档字段损坏"
		)
	return V2LifeLoopResult.ok("V2.3 分钟时钟状态有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.restore_v2_3_state(state)
	if not result.success:
		return result
	if (
		state.has("formal_minute_clock_state")
		and clock is V23MinuteClock
		and not (clock as V23MinuteClock).restore_persistent_state(
			state.get("formal_minute_clock_state", {}) as Dictionary
		)
	):
		return V2LifeLoopResult.fail(
			"minute_clock_restore_failed",
			"分钟时钟状态恢复失败"
		)
	state_changed.emit({"minute_clock_restored": true})
	return result


func determinism_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.determinism_snapshot()
	if clock is V23MinuteClock:
		snapshot["formal_minute_clock"] = (
			(clock as V23MinuteClock).get_persistent_state()
		)
	return snapshot


func _cancel_overlapping_automatic_work(
	person_id: String,
	start_hour: int,
	end_hour: int,
	all_future_work_commutes: bool
) -> int:
	var cancelled: int = 0
	var cancelled_activity_ids: Dictionary = {}
	var plan_ids: Array[String] = []
	for plan_id_variant: Variant in travel_execution.travel_plans.keys():
		plan_ids.append(str(plan_id_variant))
	plan_ids.sort()
	for plan_id: String in plan_ids:
		var plan: Dictionary = travel_execution.travel_plans[plan_id] as Dictionary
		var purpose: String = str(plan.get("purpose_activity_id", ""))
		var plan_start: int = int(plan.get("start_hour", -1))
		var plan_end: int = int(
			plan.get("expected_arrival_hour", plan_start + 1)
		)
		var overlaps: bool = plan_start < end_hour and plan_end > start_hour
		if all_future_work_commutes:
			overlaps = plan_start >= start_hour
		if (
			str(plan.get("person_id", "")) != person_id
			or str(plan.get("status", "")) != "planned"
			or not (purpose.begins_with("work:") or purpose.begins_with("return:"))
			or not overlaps
		):
			continue
		for raw_activity_id: Variant in plan.get(
			"scheduled_activity_ids", []
		) as Array:
			var activity_id: String = str(raw_activity_id)
			if schedule.cancel_activity_by_id(
				person_id,
				activity_id,
				clock.total_hours,
				"overridden_by_player_command"
			).success:
				cancelled_activity_ids[activity_id] = true
		plan["status"] = "cancelled"
		plan["interruption_reason"] = "overridden_by_player_command"
		travel_execution._store_terminal_plan(plan_id, plan)
		cancelled += 1
	if all_future_work_commutes:
		return cancelled
	var person_schedule: Array = schedule.schedules.get(person_id, []) as Array
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		var activity_id: String = str(activity.get("activity_id", ""))
		if cancelled_activity_ids.has(activity_id):
			continue
		if (
			str(activity.get("source", "")) == "npc_rule"
			and str(activity.get("status", "")) == "planned"
			and int(activity.get("start_hour", -1)) < end_hour
			and int(activity.get("end_hour", -1)) > start_hour
		):
			activity["status"] = "cancelled"
			activity["cancellation_reason"] = "overridden_by_player_command"
			person_schedule[index] = activity
			cancelled += 1
	schedule.schedules[person_id] = person_schedule
	return cancelled
