class_name V23ControlledSimulation
extends V23FormalSimulation
## Player travel creates a temporary stay intention. Automatic work travel cannot
## override it, but an idle person outside home will ask to return before sleep.

var manual_location_holds: Dictionary = {}
var manual_location_hold_started_hours: Dictionary = {}
var pending_return_home_prompts: Dictionary = {}
var stay_outside_home_until_hours: Dictionary = {}
var _return_home_policy_resume_after_decisions: bool = false


func initialize(simulation_clock: SimulationClock = null) -> bool:
	if not super.initialize(simulation_clock):
		return false
	manual_location_holds.clear()
	manual_location_hold_started_hours.clear()
	pending_return_home_prompts.clear()
	stay_outside_home_until_hours.clear()
	_return_home_policy_resume_after_decisions = false
	return true


func request_travel(
	person_id: String,
	destination_id: String,
	preference: String = "fastest",
	start_hour: int = -1
) -> V2LifeLoopResult:
	var actual_start: int = clock.total_hours + 1 if start_hour < 0 else start_hour
	var preview: V2LifeLoopResult = preview_route(
		person_id, destination_id, preference, actual_start
	)
	if not preview.success:
		return preview
	var arrival_hour: int = int(preview.data.get("arrival_hour", actual_start + 1))
	var schedule_before: Dictionary = schedule.get_persistent_state()
	var travel_before: Dictionary = travel_execution.get_persistent_state()
	_cancel_overlapping_automatic_work(
		person_id, actual_start, arrival_hour, false
	)
	var result: V2LifeLoopResult = super.request_travel(
		person_id, destination_id, preference, actual_start
	)
	if not result.success:
		schedule.restore_persistent_state(schedule_before)
		travel_execution.restore_persistent_state(travel_before)
		return result
	_clear_return_home_decision(person_id)
	var home_id: String = _home_for(person_id)
	if destination_id == home_id:
		manual_location_holds.erase(person_id)
		manual_location_hold_started_hours.erase(person_id)
		_resume_automatic_routine_after(arrival_hour)
	else:
		manual_location_holds[person_id] = destination_id
		manual_location_hold_started_hours[person_id] = arrival_hour
		_cancel_overlapping_automatic_work(
			person_id, actual_start, 2147483647, true
		)
	local_overlay_revision += 1
	state_changed.emit({
		"manual_location_hold": person_id,
		"destination_id": destination_id,
		"temporary_stay": destination_id != home_id,
		"local_overlay": local_overlay_revision,
	})
	return result


func request_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int
) -> V2LifeLoopResult:
	if activity_type == "authorized_leave":
		return super.request_activity(
			person_id, activity_type, start_hour, duration_hours
		)
	var location_check: V2LifeLoopResult = _validate_activity_location(
		person_id, activity_type, start_hour
	)
	if not location_check.success:
		return location_check
	var covered_hours: Array[int] = _unreleased_contract_hours(
		person_id, start_hour, duration_hours
	)
	if not covered_hours.is_empty():
		var leave_required := V2LifeLoopResult.fail(
			"requires_leave_authorization",
			"该行为与合同工作义务冲突，需要先确认请假。",
			"covered_hours=%d" % covered_hours.size(),
			[person_id]
		)
		leave_required.data = {
			"person_id": person_id,
			"activity_type": activity_type,
			"start_hour": start_hour,
			"duration_hours": duration_hours,
			"covered_contract_hours": covered_hours.duplicate(),
			"covered_hour_count": covered_hours.size(),
		}
		return leave_required
	var schedule_before: Dictionary = schedule.get_persistent_state()
	var travel_before: Dictionary = travel_execution.get_persistent_state()
	_cancel_overlapping_automatic_work(
		person_id, start_hour, start_hour + duration_hours, false
	)
	var result: V2LifeLoopResult = super.request_activity(
		person_id, activity_type, start_hour, duration_hours
	)
	if not result.success:
		schedule.restore_persistent_state(schedule_before)
		travel_execution.restore_persistent_state(travel_before)
	return result


func authorize_leave_and_request_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int
) -> V2LifeLoopResult:
	if activity_type == "authorized_leave":
		return request_activity(
			person_id, activity_type, start_hour, duration_hours
		)
	var location_check: V2LifeLoopResult = _validate_activity_location(
		person_id, activity_type, start_hour
	)
	if not location_check.success:
		return location_check
	var covered_hours: Array[int] = _unreleased_contract_hours(
		person_id, start_hour, duration_hours
	)
	if covered_hours.is_empty():
		return request_activity(
			person_id, activity_type, start_hour, duration_hours
		)
	var schedule_before: Dictionary = schedule.get_persistent_state()
	var travel_before: Dictionary = travel_execution.get_persistent_state()
	var leave_before: Dictionary = leave.get_persistent_state()
	var authorization: V2LifeLoopResult = leave.authorize(
		person_id,
		start_hour,
		start_hour + duration_hours,
		clock.total_hours,
		employment
	)
	if not authorization.success:
		return authorization
	var record: Dictionary = authorization.data.get(
		"leave_authorization", {}
	) as Dictionary
	leave.release_contract_schedule(record, schedule)
	_replan_commutes_for_leave_record(record)
	_cancel_overlapping_automatic_work(
		person_id, start_hour, start_hour + duration_hours, false
	)
	var result: V2LifeLoopResult = super.request_activity(
		person_id, activity_type, start_hour, duration_hours
	)
	if not result.success:
		schedule.restore_persistent_state(schedule_before)
		travel_execution.restore_persistent_state(travel_before)
		leave.restore_persistent_state(leave_before)
		return result
	notifications.add(
		"personal",
		"event",
		"请假已批准并安排活动",
		"已解除冲突的合同工时，并保留玩家指定的活动。",
		clock.total_hours,
		"leave_for_activity:%s:%d" % [person_id, start_hour],
		result.affected_entity_ids
	)
	state_changed.emit({
		"schedule": person_id,
		"employment": person_id,
		"leave": true,
		"player_override": true,
	})
	return result


func manual_hold_for(person_id: String) -> String:
	return str(manual_location_holds.get(person_id, ""))


func next_return_home_prompt() -> Dictionary:
	if pending_return_home_prompts.has(selected_person_id):
		return (
			pending_return_home_prompts[selected_person_id] as Dictionary
		).duplicate(true)
	var person_ids: Array[String] = []
	for person_id_variant: Variant in pending_return_home_prompts.keys():
		person_ids.append(str(person_id_variant))
	person_ids.sort()
	if person_ids.is_empty():
		return {}
	return (
		pending_return_home_prompts[person_ids.front()] as Dictionary
	).duplicate(true)


func accept_return_home(person_id: String) -> V2LifeLoopResult:
	if not pending_return_home_prompts.has(person_id):
		return V2LifeLoopResult.fail(
			"return_home_prompt_missing", "当前没有需要处理的返家提示", person_id
		)
	var prompt: Dictionary = pending_return_home_prompts[person_id] as Dictionary
	var home_id: String = str(prompt.get("home_location_id", _home_for(person_id)))
	var position: Dictionary = spatial_locations.position_for(person_id)
	if str(position.get("current_location_id", "")) == home_id:
		_release_manual_hold(person_id, clock.total_hours)
		pending_return_home_prompts.erase(person_id)
		_resume_clock_when_prompt_queue_empty()
		return V2LifeLoopResult.ok("人物已经回到住所", {}, [person_id, home_id])
	var start_hour: int = clock.total_hours + 1
	var preview: V2LifeLoopResult = preview_route(
		person_id, home_id, "cheapest", start_hour
	)
	if not preview.success:
		return preview
	var arrival_hour: int = int(preview.data.get("arrival_hour", start_hour + 1))
	var schedule_before: Dictionary = schedule.get_persistent_state()
	var travel_before: Dictionary = travel_execution.get_persistent_state()
	_cancel_overlapping_automatic_work(
		person_id, start_hour, arrival_hour, false
	)
	var result: V2LifeLoopResult = super.request_travel(
		person_id, home_id, "cheapest", start_hour
	)
	if not result.success:
		schedule.restore_persistent_state(schedule_before)
		travel_execution.restore_persistent_state(travel_before)
		return result
	manual_location_holds.erase(person_id)
	manual_location_hold_started_hours.erase(person_id)
	stay_outside_home_until_hours.erase(person_id)
	pending_return_home_prompts.erase(person_id)
	_resume_automatic_routine_after(arrival_hour)
	notifications.add(
		"personal",
		"event",
		"人物开始返家",
		"已按较低费用路线安排返家；到家后恢复正常自动日程。",
		clock.total_hours,
		"return_home:%s:%d" % [person_id, clock.total_hours],
		[person_id, home_id]
	)
	local_overlay_revision += 1
	state_changed.emit({
		"return_home": person_id,
		"travel": person_id,
		"manual_location_hold_released": true,
		"local_overlay": local_overlay_revision,
	})
	_resume_clock_when_prompt_queue_empty()
	return result


func continue_staying_outside_home(person_id: String) -> V2LifeLoopResult:
	if not pending_return_home_prompts.has(person_id):
		return V2LifeLoopResult.fail(
			"return_home_prompt_missing", "当前没有需要处理的返家提示", person_id
		)
	var rules: Dictionary = _player_location_rules()
	var until_hour: int = _next_hour_of_day(
		clock.total_hours,
		int(rules.get("late_stay_penalty_end_hour", 6))
	)
	stay_outside_home_until_hours[person_id] = until_hour
	pending_return_home_prompts.erase(person_id)
	notifications.add(
		"personal",
		"notification",
		"人物继续在外停留",
		"玩家阻止返家；夜间每小时会增加疲劳与压力，并轻微损害健康。",
		clock.total_hours,
		"stay_outside:%s:%d" % [person_id, clock.total_hours],
		[person_id]
	)
	state_changed.emit({
		"stay_outside_home": person_id,
		"until_hour": until_hour,
		"condition_risk": true,
	})
	_resume_clock_when_prompt_queue_empty()
	return V2LifeLoopResult.ok(
		"人物将继续停留到清晨；夜间状态会逐小时恶化。",
		{"person_id": person_id, "until_hour": until_hour},
		[person_id]
	)


func process_manual_location_policy(settled_hour: int) -> void:
	var rules: Dictionary = _player_location_rules()
	var current_hour: int = settled_hour + 1
	var current_value: Dictionary = V2DateTime.from_total_hour(current_hour)
	var hour_of_day: int = int(current_value.get("hour", 0))
	var prompt_hour: int = int(rules.get("return_home_prompt_hour", 21))
	var person_ids: Array[String] = []
	for person_id_variant: Variant in manual_location_holds.keys():
		person_ids.append(str(person_id_variant))
	person_ids.sort()
	for person_id: String in person_ids:
		if not person_states.has(person_id):
			continue
		if not travel_execution.active_plan_for_person(person_id).is_empty():
			continue
		var position: Dictionary = spatial_locations.position_for(person_id)
		if str(position.get("location_state", "")) != "at_location":
			continue
		var actual_location_id: String = str(
			position.get("current_location_id", "")
		)
		var home_id: String = _home_for(person_id)
		if actual_location_id == home_id:
			_release_manual_hold(person_id, current_hour)
			continue
		var stay_until: int = int(
			stay_outside_home_until_hours.get(person_id, -1)
		)
		if stay_until > current_hour:
			_apply_late_stay_penalty(person_id, settled_hour, rules)
			continue
		if stay_until >= 0:
			stay_outside_home_until_hours.erase(person_id)
		if pending_return_home_prompts.has(person_id):
			continue
		if not _is_return_home_time(
			hour_of_day,
			prompt_hour,
			int(rules.get("late_stay_penalty_end_hour", 6))
		):
			continue
		if not _is_idle_for_return_home(person_id, current_hour):
			continue
		_create_return_home_prompt(
			person_id, actual_location_id, home_id, current_hour, rules
		)


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["manual_location_holds"] = manual_location_holds.duplicate(true)
	state["manual_location_hold_started_hours"] = (
		manual_location_hold_started_hours.duplicate(true)
	)
	state["pending_return_home_prompts"] = (
		pending_return_home_prompts.duplicate(true)
	)
	state["stay_outside_home_until_hours"] = (
		stay_outside_home_until_hours.duplicate(true)
	)
	state["return_home_policy_resume_after_decisions"] = (
		_return_home_policy_resume_after_decisions
	)
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var base_result: V2LifeLoopResult = super.validate_v2_3_state(state)
	if not base_result.success:
		return base_result
	for field: String in [
		"manual_location_holds",
		"manual_location_hold_started_hours",
		"pending_return_home_prompts",
		"stay_outside_home_until_hours",
	]:
		if state.has(field) and not state.get(field, {}) is Dictionary:
			return V2LifeLoopResult.fail(
				"corrupt_save", "玩家临时停留记录损坏：%s" % field
			)
	return V2LifeLoopResult.ok("V2.3 玩家控制状态有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.restore_v2_3_state(state)
	if not result.success:
		return result
	manual_location_holds.clear()
	manual_location_hold_started_hours.clear()
	pending_return_home_prompts.clear()
	stay_outside_home_until_hours.clear()
	for person_id_variant: Variant in (
		state.get("manual_location_holds", {}) as Dictionary
	).keys():
		var person_id: String = str(person_id_variant)
		var location_id: String = str(
			(state.get("manual_location_holds", {}) as Dictionary).get(
				person_id_variant, ""
			)
		)
		if (
			person_states.has(person_id)
			and not spatial_locations.get_location(location_id).is_empty()
		):
			manual_location_holds[person_id] = location_id
	for person_id_variant: Variant in (
		state.get("manual_location_hold_started_hours", {}) as Dictionary
	).keys():
		var person_id: String = str(person_id_variant)
		if manual_location_holds.has(person_id):
			manual_location_hold_started_hours[person_id] = int(
				(state.get("manual_location_hold_started_hours", {}) as Dictionary).get(
					person_id_variant, clock.total_hours
				)
			)
	for person_id_variant: Variant in (
		state.get("pending_return_home_prompts", {}) as Dictionary
	).keys():
		var person_id: String = str(person_id_variant)
		var prompt: Variant = (
			state.get("pending_return_home_prompts", {}) as Dictionary
		).get(person_id_variant, {})
		if manual_location_holds.has(person_id) and prompt is Dictionary:
			pending_return_home_prompts[person_id] = (
				prompt as Dictionary
			).duplicate(true)
	for person_id_variant: Variant in (
		state.get("stay_outside_home_until_hours", {}) as Dictionary
	).keys():
		var person_id: String = str(person_id_variant)
		if manual_location_holds.has(person_id):
			stay_outside_home_until_hours[person_id] = int(
				(state.get("stay_outside_home_until_hours", {}) as Dictionary).get(
					person_id_variant, -1
				)
			)
	_return_home_policy_resume_after_decisions = bool(
		state.get("return_home_policy_resume_after_decisions", false)
	)
	if not pending_return_home_prompts.is_empty():
		clock.set_paused(true)
	state_changed.emit({
		"manual_location_holds_restored": true,
		"return_home_prompts_restored": pending_return_home_prompts.size(),
	})
	return result


func determinism_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.determinism_snapshot()
	snapshot["manual_location_holds"] = manual_location_holds.duplicate(true)
	snapshot["pending_return_home_prompts"] = (
		pending_return_home_prompts.duplicate(true)
	)
	snapshot["stay_outside_home_until_hours"] = (
		stay_outside_home_until_hours.duplicate(true)
	)
	return snapshot


func _schedule_commute(
	person_id: String,
	origin_id: String,
	destination_id: String,
	departure_hour: int,
	preference: String,
	cash: int,
	fatigue: int,
	purpose_id: String,
	reason: String
) -> void:
	if (
		manual_location_holds.has(person_id)
		and (purpose_id.begins_with("work:") or purpose_id.begins_with("return:"))
	):
		return
	super._schedule_commute(
		person_id,
		origin_id,
		destination_id,
		departure_hour,
		preference,
		cash,
		fatigue,
		purpose_id,
		reason
	)


func _validate_activity_location(
	person_id: String,
	activity_type: String,
	start_hour: int
) -> V2LifeLoopResult:
	var required_locations: Array[String] = _required_locations_for_activity(
		person_id, activity_type
	)
	if required_locations.is_empty():
		return V2LifeLoopResult.ok()
	var predicted: Dictionary = _predicted_position_at(person_id, start_hour)
	var predicted_location: String = str(
		predicted.get("current_location_id", "")
	)
	if (
		str(predicted.get("location_state", "at_location")) == "at_location"
		and predicted_location in required_locations
	):
		return V2LifeLoopResult.ok()
	var required_location: String = _preferred_known_location(
		person_id, required_locations
	)
	var required_name: String = spatial_locations.location_name(
		required_location, person_id, truth_view
	)
	var current_name: String = spatial_locations.location_name(
		predicted_location, person_id, truth_view
	)
	var result := V2LifeLoopResult.fail(
		"requires_location",
		"该行为必须在%s进行；人物预计仍位于%s。" % [
			required_name, current_name,
		],
		activity_type,
		[person_id, required_location]
	)
	result.data = {
		"activity_type": activity_type,
		"required_location_id": required_location,
		"required_location_name": required_name,
		"current_location_id": predicted_location,
		"current_location_name": current_name,
		"start_hour": start_hour,
	}
	return result


func _required_locations_for_activity(
	person_id: String,
	activity_type: String
) -> Array[String]:
	var result: Array[String] = []
	match activity_type:
		"sleep", "rest":
			result.append(_home_for(person_id))
		"overtime":
			result.append(_workplace_for(person_id))
		"purchase_food", "purchase_essentials", "union_activity", "write_message", "read_public_notice":
			result = spatial_locations.locations_for_service(activity_type)
		_:
			pass
	var filtered: Array[String] = []
	for location_id: String in result:
		if (
			not location_id.is_empty()
			and not spatial_locations.get_location(location_id).is_empty()
			and location_id not in filtered
		):
			filtered.append(location_id)
	filtered.sort()
	return filtered


func _preferred_known_location(
	person_id: String,
	location_ids: Array[String]
) -> String:
	for location_id: String in location_ids:
		if spatial_locations.knows_location(person_id, location_id):
			return location_id
	return "" if location_ids.is_empty() else location_ids.front()


func _predicted_position_at(person_id: String, target_hour: int) -> Dictionary:
	var position: Dictionary = spatial_locations.position_for(person_id)
	var predicted_location: String = str(
		position.get("current_location_id", "")
	)
	var predicted_state: String = str(
		position.get("location_state", "at_location")
	)
	var latest_arrival: int = -1
	for raw_plan: Variant in travel_execution.travel_plans.values():
		var plan: Dictionary = raw_plan as Dictionary
		if (
			str(plan.get("person_id", "")) != person_id
			or str(plan.get("status", "")) not in ["planned", "waiting", "active"]
		):
			continue
		var plan_start: int = int(plan.get("start_hour", -1))
		var arrival: int = int(plan.get("expected_arrival_hour", -1))
		if plan_start <= target_hour and target_hour < arrival:
			return {
				"current_location_id": predicted_location,
				"location_state": "in_transit",
				"travel_destination_id": str(plan.get("destination_id", "")),
			}
		if arrival <= target_hour and arrival > latest_arrival:
			latest_arrival = arrival
			predicted_location = str(plan.get("destination_id", ""))
			predicted_state = "at_location"
	return {
		"current_location_id": predicted_location,
		"location_state": predicted_state,
	}


func _unreleased_contract_hours(
	person_id: String,
	start_hour: int,
	duration_hours: int
) -> Array[int]:
	var result: Array[int] = []
	for total_hour: int in range(
		start_hour, start_hour + maxi(1, duration_hours)
	):
		if (
			employment.is_required_work_hour(person_id, total_hour)
			and not leave.covers(person_id, total_hour)
		):
			result.append(total_hour)
	return result


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


func _player_location_rules() -> Dictionary:
	return (
		v2_3_config.get_document("balance").get("player_location", {})
		as Dictionary
	)


func _is_idle_for_return_home(person_id: String, total_hour: int) -> bool:
	var activity: Dictionary = schedule.activity_for_hour(person_id, total_hour)
	if activity.is_empty():
		return true
	var activity_type: String = str(activity.get("activity_type", "free_time"))
	if activity_type in TRAVEL_TYPES:
		return false
	return not (
		str(activity.get("source", "")) == "player"
		and activity_type != "free_time"
	)


func _is_return_home_time(
	hour_of_day: int,
	prompt_hour: int,
	penalty_end_hour: int
) -> bool:
	return hour_of_day >= prompt_hour or hour_of_day < penalty_end_hour


func _create_return_home_prompt(
	person_id: String,
	current_location_id: String,
	home_id: String,
	current_hour: int,
	rules: Dictionary
) -> void:
	if pending_return_home_prompts.is_empty():
		_return_home_policy_resume_after_decisions = not clock.is_paused
	clock.set_paused(true)
	pending_return_home_prompts[person_id] = {
		"person_id": person_id,
		"person_name": str(_social_person(person_id).get(
			"display_name_zh", person_id
		)),
		"current_location_id": current_location_id,
		"current_location_name": spatial_locations.location_name(
			current_location_id, person_id, truth_view
		),
		"home_location_id": home_id,
		"home_location_name": spatial_locations.location_name(
			home_id, person_id, truth_view
		),
		"prompt_hour": current_hour,
		"prompt_datetime": V2DateTime.iso_from_total_hour(current_hour),
		"fatigue_per_hour": int(rules.get("late_stay_fatigue_per_hour", 45)),
		"stress_per_hour": int(rules.get("late_stay_stress_per_hour", 20)),
		"health_per_hour": int(rules.get("late_stay_health_per_hour", -2)),
	}
	notifications.add(
		"personal",
		"notification",
		"人物准备返家",
		"人物已无玩家安排，准备从当前地点返回住所。",
		current_hour,
		"return_home_prompt:%s:%d" % [person_id, current_hour],
		[person_id, current_location_id, home_id]
	)
	state_changed.emit({
		"return_home_prompt": person_id,
		"clock_paused": true,
	})


func _apply_late_stay_penalty(
	person_id: String,
	settled_hour: int,
	rules: Dictionary
) -> void:
	var hour_of_day: int = int(
		V2DateTime.from_total_hour(settled_hour).get("hour", 0)
	)
	var start_hour: int = int(rules.get("late_stay_penalty_start_hour", 22))
	var end_hour: int = int(rules.get("late_stay_penalty_end_hour", 6))
	if hour_of_day < start_hour and hour_of_day >= end_hour:
		return
	conditions.apply_delta(
		person_id,
		"fatigue",
		int(rules.get("late_stay_fatigue_per_hour", 45)),
		settled_hour,
		"玩家要求人物夜间继续在住所外停留",
		"stay_outside_home",
		V2DateTime.iso_from_total_hour(settled_hour)
	)
	conditions.apply_delta(
		person_id,
		"stress",
		int(rules.get("late_stay_stress_per_hour", 20)),
		settled_hour,
		"夜间无法按正常生活节奏返家",
		"stay_outside_home",
		V2DateTime.iso_from_total_hour(settled_hour)
	)
	conditions.apply_delta(
		person_id,
		"health",
		int(rules.get("late_stay_health_per_hour", -2)),
		settled_hour,
		"持续在住所外过夜影响健康",
		"stay_outside_home",
		V2DateTime.iso_from_total_hour(settled_hour)
	)
	state_changed.emit({
		"condition": person_id,
		"late_stay_penalty": true,
	})


func _release_manual_hold(person_id: String, resume_hour: int) -> void:
	var existed: bool = manual_location_holds.erase(person_id)
	manual_location_hold_started_hours.erase(person_id)
	pending_return_home_prompts.erase(person_id)
	stay_outside_home_until_hours.erase(person_id)
	if existed:
		_resume_automatic_routine_after(resume_hour)
		state_changed.emit({
			"manual_location_hold_released": person_id,
			"automatic_routine_resumed": true,
		})


func _clear_return_home_decision(person_id: String) -> void:
	pending_return_home_prompts.erase(person_id)
	stay_outside_home_until_hours.erase(person_id)
	_resume_clock_when_prompt_queue_empty()


func _resume_clock_when_prompt_queue_empty() -> void:
	if not pending_return_home_prompts.is_empty():
		return
	var should_resume: bool = _return_home_policy_resume_after_decisions
	_return_home_policy_resume_after_decisions = false
	if should_resume:
		clock.set_paused(false)


func _resume_automatic_routine_after(start_hour: int) -> void:
	_commute_planned_through_day = -1
	_replace_fixed_commutes(
		maxi(clock.total_hours, start_hour), "manual_location_hold_released"
	)


func _next_hour_of_day(current_hour: int, target_hour_of_day: int) -> int:
	var value: Dictionary = V2DateTime.from_total_hour(current_hour)
	var candidate: int = current_hour - int(value.get("hour", 0)) + target_hour_of_day
	if candidate <= current_hour:
		candidate += 24
	return candidate
