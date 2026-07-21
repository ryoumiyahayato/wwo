class_name V23SocialSandboxServiceV3
extends V23SocialSandboxServiceV2
## Product preview uses the same schedule/travel reservation path as submit.
## Explicit player confirmation authorizes only the controlled actor's trip;
## targets must still have a naturally available schedule.

var _authorize_player_travel_for_submit: bool = false


func methods_for(actor_id: String, goal_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = super.methods_for(actor_id, goal_id)
	if _has_open_commitment(actor_id):
		return result
	var filtered: Array[Dictionary] = []
	for method: Dictionary in result:
		if str(method.get("method_id", "")) != "repay_favor":
			filtered.append(method)
	return filtered


func submit_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String = "",
	source: String = "player",
	options: Dictionary = {}
) -> V2LifeLoopResult:
	if method_id == "repay_favor" and not _has_open_commitment(actor_id, target_id):
		return V2LifeLoopResult.fail(
			"commitment_required",
			"当前没有需要向这个人物履行的承诺或人情。",
			target_id,
			[actor_id, target_id]
		)
	return super.submit_intent(
		actor_id, goal_id, method_id, target_id, source, options
	)


func preview_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String,
	options: Dictionary = {}
) -> V2LifeLoopResult:
	if method_id == "repay_favor" and not _has_open_commitment(actor_id, target_id):
		return V2LifeLoopResult.fail(
			"commitment_required",
			"当前没有需要向这个人物履行的承诺或人情。",
			target_id,
			[actor_id, target_id]
		)
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
	if method_id == "repay_favor" and not _has_open_commitment(actor_id, target_id):
		return V2LifeLoopResult.fail(
			"commitment_required",
			"当前没有需要向这个人物履行的承诺或人情。",
			target_id,
			[actor_id, target_id]
		)
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


func _settle_commitment(
	actor_id: String,
	target_id: String,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	var candidate_ids: Array[String] = _open_commitment_ids(actor_id, target_id)
	if candidate_ids.is_empty():
		return V2LifeLoopResult.fail(
			"commitment_required",
			"当前没有可以履行的既有承诺。",
			target_id,
			[actor_id, target_id]
		)
	var commitment_id: String = candidate_ids.front()
	var commitment: Dictionary = commitments[commitment_id] as Dictionary
	commitment["status"] = "kept"
	commitment["settled_event_id"] = event_id
	commitment["settled_hour"] = current_hour
	commitments[commitment_id] = commitment
	var relation: V2LifeLoopResult = _apply_relationship_effect(
		actor_id,
		str(commitment.get("beneficiary_id", "")),
		"promise_kept",
		event_id,
		current_hour
	)
	if not relation.success:
		return relation
	return V2LifeLoopResult.ok(
		"承诺已经履行",
		{
			"commitment": commitment.duplicate(true),
			"relationship": relation.data.duplicate(true),
		},
		[actor_id, str(commitment.get("beneficiary_id", "")), commitment_id]
	)


func _has_open_commitment(actor_id: String, target_id: String = "") -> bool:
	return not _open_commitment_ids(actor_id, target_id).is_empty()


func _open_commitment_ids(actor_id: String, target_id: String = "") -> Array[String]:
	var candidate_ids: Array[String] = []
	for commitment_id_variant: Variant in commitments.keys():
		var commitment_id: String = str(commitment_id_variant)
		var commitment: Dictionary = commitments[commitment_id] as Dictionary
		if (
			str(commitment.get("promisor_id", "")) == actor_id
			and (
				target_id.is_empty()
				or str(commitment.get("beneficiary_id", "")) == target_id
			)
			and str(commitment.get("status", "")) == "open"
		):
			candidate_ids.append(commitment_id)
	candidate_ids.sort()
	return candidate_ids
