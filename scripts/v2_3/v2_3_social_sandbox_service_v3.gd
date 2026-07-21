class_name V23SocialSandboxServiceV3
extends V23SocialSandboxServiceV2
## Product preview uses the same schedule/travel reservation path as submit.
## The complete authority snapshot is restored immediately after preview.


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
