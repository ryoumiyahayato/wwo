class_name V23SocialSandboxServiceV3
extends V23SocialSandboxServiceV2
## Product preview uses the same schedule/travel reservation path as submit.
## Explicit player confirmation authorizes only the controlled actor's trip;
## targets must still have a naturally available schedule.

var _authorize_player_travel_for_submit: bool = false


func preview_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String,
	options: Dictionary = {}
) -> V2LifeLoopResult:
	var basic: V2LifeLoopResult = super.preview_intent(
		actor_id, goal_id, method_id, target_id, options
	)
	if not basic.success:
		return basic
	var method: Dictionary = method_record(method_id)
	var resolved_target: String = str(basic.data.get("target_id", target_id))
	var location_id: String = str(basic.data.get("location_id", ""))
	var current_hour: int = int(options.get("current_hour", _last_processed_hour))
	var snapshot: Dictionary = _travel_snapshot()
	var metadata_before: Dictionary = _last_reservation_metadata.duplicate(true)
	_submit_options = options.duplicate(true)
	_last_reservation_metadata.clear()
	var reservation: V2LifeLoopResult = _reserve_schedule(
		"preview_social_task",
		actor_id,
		resolved_target,
		method,
		location_id,
		"player",
		current_hour
	)
	var reservation_metadata: Dictionary = _last_reservation_metadata.duplicate(true)
	_submit_options.clear()
	_restore_travel_snapshot(snapshot)
	_last_reservation_metadata = metadata_before
	if not reservation.success:
		return reservation
	var activity: Dictionary = reservation.data.get("activity", {}) as Dictionary
	var actual_start: int = int(
		activity.get(
			"start_hour",
			reservation_metadata.get("planned_start_hour", basic.data.get("start_hour", current_hour + 1))
		)
	)
	var duration: int = clampi(int(method.get("duration_hours", 1)), 1, 12)
	var data: Dictionary = basic.data.duplicate(true)
	data["start_hour"] = actual_start
	data["start_datetime"] = V2DateTime.display_from_total_hour(actual_start)
	data["end_hour"] = actual_start + duration
	data["duration_hours"] = duration
	data["travel_required"] = bool(reservation_metadata.get("travel_required", false))
	data["actor_travel_plan_id"] = str(reservation_metadata.get("actor_travel_plan_id", ""))
	data["target_travel_plan_id"] = str(reservation_metadata.get("target_travel_plan_id", ""))
	return V2LifeLoopResult.ok(
		"当前条件下可以建立这项计划",
		data,
		[actor_id, resolved_target, location_id]
	)


func submit_intent_with_player_leave(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String,
	options: Dictionary
) -> V2LifeLoopResult:
	_authorize_player_travel_for_submit = true
	var result: V2LifeLoopResult = super.submit_intent(
		actor_id, goal_id, method_id, target_id, "player", options
	)
	_authorize_player_travel_for_submit = false
	return result


func _ensure_arrival(
	person_id: String,
	location_id: String,
	action_start: int,
	current_hour: int,
	player_request: bool
) -> V2LifeLoopResult:
	var position: Dictionary = _locations.position_for(person_id)
	if (
		str(position.get("location_state", "")) == "at_location"
		and str(position.get("current_location_id", "")) == location_id
	):
		return V2LifeLoopResult.ok(
			"人物已经在行动地点",
			{"travel_required": false, "travel_plan_id": ""}
		)
	var preview: Dictionary = _route_preview_before(
		person_id, location_id, action_start, current_hour
	)
	if not bool(preview.get("success", false)):
		return V2LifeLoopResult.fail(
			"route_unavailable",
			"人物无法在行动开始前到达地点",
			location_id,
			[person_id, location_id]
		)
	var departure_hour: int = int(preview.get("departure_hour", current_hour + 1))
	var result: V2LifeLoopResult
	if player_request and _authorize_player_travel_for_submit:
		result = _product.authorize_leave_and_request_travel(
			person_id, location_id, "fastest", departure_hour
		)
	else:
		result = _product.request_travel(
			person_id, location_id, "fastest", departure_hour
		)
	if not result.success:
		if player_request and result.error_code == "requires_leave_authorization":
			result.user_message = "社会行动需要先确认请假并建立实际行程。"
		return result
	var plan: Dictionary = result.data.get("plan", result.data) as Dictionary
	return V2LifeLoopResult.ok(
		"人物行程已经建立",
		{
			"travel_required": true,
			"travel_plan_id": str(plan.get("travel_plan_id", "")),
			"departure_hour": departure_hour,
			"arrival_hour": int(preview.get("arrival_hour", action_start)),
		},
		[person_id, location_id]
	)
