class_name V23SocialSandboxServiceV2
extends V23SocialSandboxService
## Completion layer for the formal social sandbox.
##
## This class keeps the original service as the authority for event, task and
## reaction state, while closing the unfinished product paths: stable goals,
## explicit player choices, real travel/reservations, relevant evidence,
## per-action atomicity and differentiated method consequences.

var _product: V23ProductSimulation
var _submit_options: Dictionary = {}
var _last_reservation_metadata: Dictionary = {}


func attach_product(product: V23ProductSimulation) -> void:
	_product = product


func submit_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String = "",
	source: String = "player",
	options: Dictionary = {}
) -> V2LifeLoopResult:
	var method: Dictionary = method_record(method_id)
	if method.is_empty():
		return V2LifeLoopResult.fail(
			"unknown_method", "找不到行动方法", method_id, [actor_id]
		)
	if source == "player" and _method_requires_target(method) and target_id.is_empty():
		return V2LifeLoopResult.fail(
			"target_required",
			"该行动必须由玩家明确选择对象，系统不会代替玩家随机挑选。",
			method_id,
			[actor_id]
		)
	var current_hour: int = int(options.get("current_hour", _last_processed_hour))
	var requested_start: int = int(options.get("start_hour", -1))
	if requested_start >= 0 and requested_start <= current_hour:
		return V2LifeLoopResult.fail(
			"invalid_social_start",
			"社会行动必须安排在当前时间之后。",
			V2DateTime.iso_from_total_hour(requested_start),
			[actor_id]
		)
	_submit_options = options.duplicate(true)
	_last_reservation_metadata.clear()
	var result: V2LifeLoopResult = super.submit_intent(
		actor_id, goal_id, method_id, target_id, source, options
	)
	_submit_options.clear()
	if not result.success:
		_last_reservation_metadata.clear()
		return result
	var task: Dictionary = result.data.get("task", {}) as Dictionary
	var task_id: String = str(task.get("task_id", ""))
	var goal: Dictionary = _goal_by_id(actor_id, goal_id)
	var position_id: String = _position_id_from_goal(goal)
	if not position_id.is_empty():
		task["position_id"] = position_id
	for raw_key: Variant in _last_reservation_metadata.keys():
		task[str(raw_key)] = _last_reservation_metadata[raw_key]
	if tasks.has(task_id):
		tasks[task_id] = task.duplicate(true)
	result.data["task"] = task.duplicate(true)
	result.data["plan"] = _last_reservation_metadata.duplicate(true)
	_last_reservation_metadata.clear()
	return result


func preview_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String,
	options: Dictionary = {}
) -> V2LifeLoopResult:
	if not _people.has(actor_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到行动人物", actor_id)
	var goal: Dictionary = _goal_by_id(actor_id, goal_id)
	var method: Dictionary = method_record(method_id)
	if goal.is_empty() or method.is_empty():
		return V2LifeLoopResult.fail("invalid_social_plan", "目标或方法已经失效")
	if _method_requires_target(method) and target_id.is_empty():
		return V2LifeLoopResult.fail("target_required", "请选择具体行动对象")
	var resolved_target: String = _resolve_target(actor_id, target_id, method)
	var organization_id: String = _resolve_organization(
		actor_id, goal, method, options
	)
	_submit_options = options.duplicate(true)
	var location_id: String = _resolve_method_location(
		actor_id, resolved_target, organization_id, method
	)
	_submit_options.clear()
	if location_id.is_empty():
		return V2LifeLoopResult.fail(
			"social_location_unavailable", "无法确定该行动的实际地点"
		)
	var current_hour: int = int(options.get("current_hour", _last_processed_hour))
	var start_hour: int = int(options.get("start_hour", current_hour + 2))
	var duration: int = clampi(int(method.get("duration_hours", 1)), 1, 12)
	var actor_route: Dictionary = _route_preview_before(
		actor_id, location_id, start_hour, current_hour
	)
	if bool(actor_route.get("required", false)) and not bool(actor_route.get("success", false)):
		return V2LifeLoopResult.fail(
			"actor_route_unavailable", "行动人物无法按时到达行动地点"
		)
	var target_route: Dictionary = {}
	if not resolved_target.is_empty():
		target_route = _route_preview_before(
			resolved_target, location_id, start_hour, current_hour
		)
		if bool(target_route.get("required", false)) and not bool(target_route.get("success", false)):
			return V2LifeLoopResult.fail(
				"target_route_unavailable", "行动对象无法按时到达行动地点"
			)
	return V2LifeLoopResult.ok(
		"社会行动计划可以提交",
		{
			"actor_id": actor_id,
			"target_id": resolved_target,
			"organization_id": organization_id,
			"position_id": _position_id_from_goal(goal),
			"location_id": location_id,
			"location_name": _locations.location_name(location_id, actor_id, false),
			"start_hour": start_hour,
			"start_datetime": V2DateTime.iso_from_total_hour(start_hour),
			"end_hour": start_hour + duration,
			"duration_hours": duration,
			"preparation": clampi(int(options.get("preparation", 250)), 0, 900),
			"actor_route": actor_route,
			"target_route": target_route,
			"cash_cost_centimes": int(method.get("cash_cost_centimes", 0)),
			"risk": int(method.get("risk", 0)),
			"illegal": bool(method.get("illegal", false)),
		}
	)


func _derive_situations(
	person_id: String, current_hour: int
) -> Array[Dictionary]:
	var inherited: Array[Dictionary] = super._derive_situations(
		person_id, current_hour
	)
	var result: Array[Dictionary] = []
	for situation: Dictionary in inherited:
		if str(situation.get("signal_key", "")) in [
			"factory_delegate", "factory_delegate_held",
		]:
			continue
		result.append(situation)
	var memberships: Array[Dictionary] = _organizations.memberships_for_person(
		person_id
	)
	for membership: Dictionary in memberships:
		if str(membership.get("status", "active")) != "active":
			continue
		var organization_id: String = str(membership.get("organization_id", ""))
		for raw_position: Variant in _organizations.positions.values():
			var position: Dictionary = raw_position as Dictionary
			if str(position.get("organization_id", "")) != organization_id:
				continue
			var position_id: String = str(position.get("position_id", ""))
			var holder_id: String = str(position.get("holder_person_id", ""))
			var title: String = str(position.get("display_name_zh", position_id))
			if holder_id.is_empty():
				result.append(_make_signal(
					person_id,
					"opportunity",
					"%s职位空缺" % title,
					"取得该职位会改变组织内部的权限、责任与资源调用能力。",
					clampi(520 + int(membership.get("participation", 0)) / 2, 0, 900),
					current_hour + 14 * 24,
					[{
						"service": "V2OrganizationActivityService",
						"field": "position_vacancy",
						"value": position_id,
						"organization_id": organization_id,
					}],
					"职位已有持有人或人物离开组织",
					"position:%s" % position_id
				))
			elif holder_id != person_id:
				result.append(_make_signal(
					person_id,
					"threat",
					"%s已由他人占据" % title,
					"职位持有人可能改变组织内部议程和资源分配。",
					420,
					current_hour + 7 * 24,
					[{
						"service": "V2OrganizationActivityService",
						"field": "holder_person_id",
						"value": holder_id,
						"position_id": position_id,
						"organization_id": organization_id,
					}],
					"职位持有人变化",
					"position_held:%s" % position_id
				))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_urgency: int = int(left.get("urgency", 0))
		var right_urgency: int = int(right.get("urgency", 0))
		if left_urgency != right_urgency:
			return left_urgency > right_urgency
		return str(left.get("signal_key", "")) < str(right.get("signal_key", ""))
	)
	var limit: int = int(
		(_rules.get("limits", {}) as Dictionary).get("situations_per_person", 12)
	)
	if result.size() > limit:
		result.resize(limit)
	return result


func _derive_goals(
	person_id: String,
	derived: Array[Dictionary],
	current_hour: int
) -> Array[Dictionary]:
	var previous: Dictionary = {}
	for old_goal: Dictionary in goals_for(person_id):
		previous[str(old_goal.get("signal_key", ""))] = old_goal
	var result: Array[Dictionary] = []
	var limit: int = int(
		(_rules.get("limits", {}) as Dictionary).get("goals_per_person", 4)
	)
	for situation_record: Dictionary in derived:
		if result.size() >= limit:
			break
		var signal_key: String = str(situation_record.get("signal_key", ""))
		var old: Dictionary = previous.get(signal_key, {}) as Dictionary
		var goal_id: String = "social_goal:v2_3:%s:%s" % [
			_sanitize_id(person_id), _sanitize_id(signal_key),
		]
		result.append({
			"goal_id": goal_id,
			"person_id": person_id,
			"kind": str(situation_record.get("kind", "")),
			"title_zh": str(situation_record.get("title_zh", "")),
			"desired_outcome": str(situation_record.get("expected_consequence", "")),
			"urgency": int(situation_record.get("urgency", 0)),
			"signal_id": str(situation_record.get("signal_id", "")),
			"signal_key": signal_key,
			"created_hour": int(old.get("created_hour", current_hour)),
			"updated_hour": current_hour,
			"expires_hour": int(situation_record.get("expires_hour", current_hour + 24)),
			"known_evidence": (
				situation_record.get("known_evidence", []) as Array
			).duplicate(true),
			"cause_event_id": str(situation_record.get("cause_event_id", "")),
			"status": "active",
		})
	return result


func _knowledge_evidence(
	person_id: String, provenance: Array[Dictionary]
) -> Array[Dictionary]:
	var relevant_subjects: Dictionary = {person_id: true}
	var relevant_types: Dictionary = {}
	var personal_sources: Dictionary = {
		"V2HouseholdService": true,
		"V2EmploymentService": true,
		"SpatialLocationService": true,
		"V23RelationshipService": true,
		"V2OrganizationActivityService": true,
	}
	for item: Dictionary in provenance:
		for key: String in ["target_id", "organization_id", "position_id"]:
			var subject_id: String = str(item.get(key, ""))
			if not subject_id.is_empty():
				relevant_subjects[subject_id] = true
		var value: Variant = item.get("value")
		if typeof(value) == TYPE_STRING and not str(value).is_empty():
			relevant_subjects[str(value)] = true
		relevant_types[str(item.get("field", ""))] = true
	var result: Array[Dictionary] = []
	var records: Array[Dictionary] = _knowledge.records_for_person(person_id)
	records.reverse()
	for record: Dictionary in records:
		if str(record.get("status", "")) == "outdated":
			continue
		var subject_id: String = str(record.get("subject_id", ""))
		var fact_type: String = str(record.get("fact_type", ""))
		if not relevant_subjects.has(subject_id) and not relevant_types.has(fact_type):
			continue
		result.append({
			"knowledge_id": str(record.get("knowledge_id", "")),
			"fact_type": fact_type,
			"subject_id": subject_id,
			"source_id": str(record.get("source_id", "")),
			"confidence": int(record.get("confidence", 0)),
		})
		if result.size() >= 4:
			break
	if result.is_empty():
		for item: Dictionary in provenance:
			var service: String = str(item.get("service", ""))
			if not personal_sources.has(service):
				continue
			result.append({
				"knowledge_id": "",
				"fact_type": "direct_personal_state",
				"subject_id": person_id,
				"source_id": service,
				"confidence": 1000,
			})
			if result.size() >= 4:
				break
	return result


func _select_npc_goal(
	person_id: String, candidates: Array[Dictionary]
) -> Dictionary:
	var selected: Dictionary = candidates.front()
	var best: int = -2147483648
	for goal: Dictionary in candidates:
		var utility: int = int(goal.get("urgency", 0))
		var signal_key: String = str(goal.get("signal_key", ""))
		if signal_key.begins_with("position:"):
			var membership: Dictionary = _membership_for_position_goal(
				person_id, signal_key
			)
			utility += int(membership.get("participation", 0)) / 4
		utility += _stable_roll("%s|%s|goal" % [person_id, signal_key]) % 101
		if utility > best:
			best = utility
			selected = goal
	return selected


func _select_npc_method(
	person_id: String,
	goal: Dictionary,
	candidates: Array[Dictionary],
	current_hour: int
) -> Dictionary:
	var available: Array[Dictionary] = []
	for method: Dictionary in candidates:
		if bool(method.get("available", false)):
			available.append(method)
	if available.is_empty():
		return {}
	var person: Dictionary = _people[person_id] as Dictionary
	var role: String = str(person.get("role", ""))
	var selected: Dictionary = {}
	var best: int = -2147483648
	for method: Dictionary in available:
		var utility: int = _method_utility(person_id, goal, method)
		var effect: String = str(method.get("effect", ""))
		if "工会" in role and effect in [
			"promise_create", "organization_participation", "relationship_positive",
		]:
			utility += 220
		elif "事务员" in role and effect in [
			"information", "evidence", "relationship_positive",
		]:
			utility += 180
		elif effect in ["work_reputation", "relationship_positive", "persuasion"]:
			utility += 120
		if str(goal.get("signal_key", "")).begins_with("position:"):
			if effect == "claim_position":
				utility += 280
			elif effect in ["organization_participation", "relationship_positive"]:
				utility += 160
		if bool(method.get("illegal", false)):
			utility -= 350
		utility += _stable_roll("%s|%s|%d" % [
			person_id, str(method.get("method_id", "")), current_hour / 24,
		]) % 181
		if utility > best:
			best = utility
			selected = method
	return selected


func _resolve_organization(
	actor_id: String,
	goal: Dictionary,
	method: Dictionary,
	options: Dictionary
) -> String:
	var requested: String = str(options.get("organization_id", ""))
	if not requested.is_empty() and not _organizations.organization(requested).is_empty():
		return requested
	var position_id: String = _position_id_from_goal(goal)
	if not position_id.is_empty():
		return str(_organizations.get_position(position_id).get("organization_id", ""))
	return super._resolve_organization(actor_id, goal, method, options)


func _resolve_method_location(
	actor_id: String,
	target_id: String,
	organization_id: String,
	method: Dictionary
) -> String:
	var requested: String = str(_submit_options.get("location_id", ""))
	if not requested.is_empty() and not _locations.get_location(requested).is_empty():
		return requested
	var inherited: String = super._resolve_method_location(
		actor_id, target_id, organization_id, method
	)
	if not inherited.is_empty():
		return inherited
	if str(method.get("location_kind", "")) == "target":
		if _same_active_organization(actor_id, target_id):
			return str((_people[actor_id] as Dictionary).get("workplace_location_id", ""))
		if not _locations.get_location("location_lille_public_square").is_empty():
			return "location_lille_public_square"
	if str(method.get("location_kind", "public")) == "public":
		if not _locations.get_location("location_lille_public_square").is_empty():
			return "location_lille_public_square"
	return str(_locations.position_for(actor_id).get("current_location_id", ""))


func _reserve_schedule(
	task_id: String,
	actor_id: String,
	target_id: String,
	method: Dictionary,
	preferred_location_id: String,
	source: String,
	current_hour: int
) -> V2LifeLoopResult:
	if _product == null:
		return super._reserve_schedule(
			task_id, actor_id, target_id, method,
			preferred_location_id, source, current_hour
		)
	var location_id: String = preferred_location_id
	if location_id.is_empty():
		location_id = _resolve_method_location(actor_id, target_id, "", method)
	if location_id.is_empty():
		return V2LifeLoopResult.fail(
			"social_location_unavailable", "社会行动没有可执行地点"
		)
	var duration: int = clampi(int(method.get("duration_hours", 1)), 1, 12)
	var planning: Dictionary = _rules.get("planning", {}) as Dictionary
	var search_start: int = maxi(
		current_hour + int(planning.get("minimum_delay_hours", 1)),
		int(_submit_options.get("start_hour", current_hour + 1))
	)
	var search_end: int = search_start + int(planning.get("search_horizon_hours", 72))
	var candidate: int = _find_joint_window(
		actor_id, target_id, source, search_start, search_end, duration
	)
	if candidate < 0:
		return V2LifeLoopResult.fail(
			"no_joint_schedule_window",
			"未来72小时没有双方均可到场的行动窗口。",
			str(method.get("method_id", "")),
			[actor_id, target_id]
		)
	var travel_snapshot: Dictionary = _travel_snapshot()
	var actor_travel: V2LifeLoopResult = _ensure_arrival(
		actor_id, location_id, candidate, current_hour, source == "player"
	)
	if not actor_travel.success:
		_restore_travel_snapshot(travel_snapshot)
		return actor_travel
	var target_travel := V2LifeLoopResult.ok("行动没有对象行程")
	if not target_id.is_empty():
		target_travel = _ensure_arrival(
			target_id, location_id, candidate, current_hour, false
		)
		if not target_travel.success:
			_restore_travel_snapshot(travel_snapshot)
			return target_travel
	var target_activity: Dictionary = {}
	if not target_id.is_empty():
		var target_result: V2LifeLoopResult = _schedule.schedule_rule_activity(
			target_id,
			"social_action",
			candidate,
			duration,
			location_id,
			"npc_rule",
			task_id,
			0
		)
		if not target_result.success:
			_restore_travel_snapshot(travel_snapshot)
			return V2LifeLoopResult.fail(
				"target_schedule_conflict",
				"行动对象在所选时间无法到场：%s" % target_result.user_message,
				str(method.get("method_id", "")),
				[actor_id, target_id]
			)
		target_activity = target_result.data.get("activity", {}) as Dictionary
	var actor_result: V2LifeLoopResult
	if source == "player":
		actor_result = _schedule.schedule_player_activity(
			actor_id,
			"social_action",
			candidate,
			duration,
			current_hour,
			location_id,
			task_id,
			int(method.get("cash_cost_centimes", 0)),
			{"sandbox_task_id": task_id}
		)
	else:
		actor_result = _schedule.schedule_rule_activity(
			actor_id,
			"social_action",
			candidate,
			duration,
			location_id,
			"npc_rule",
			task_id,
			int(method.get("cash_cost_centimes", 0))
		)
	if not actor_result.success:
		_restore_travel_snapshot(travel_snapshot)
		return actor_result
	var activity: Dictionary = actor_result.data.get("activity", {}) as Dictionary
	_schedule.merge_activity_metadata(
		actor_id,
		str(activity.get("activity_id", "")),
		{"social_task_ids": [task_id], "sandbox_task_id": task_id}
	)
	if not target_activity.is_empty():
		_schedule.merge_activity_metadata(
			target_id,
			str(target_activity.get("activity_id", "")),
			{"social_task_ids": [task_id], "sandbox_task_id": task_id, "participant_role": "target"}
		)
	_last_reservation_metadata = {
		"target_schedule_activity_id": str(target_activity.get("activity_id", "")),
		"actor_travel_plan_id": str(actor_travel.data.get("travel_plan_id", "")),
		"target_travel_plan_id": str(target_travel.data.get("travel_plan_id", "")),
		"travel_required": bool(actor_travel.data.get("travel_required", false))
			or bool(target_travel.data.get("travel_required", false)),
		"planned_location_id": location_id,
		"planned_start_hour": candidate,
	}
	return V2LifeLoopResult.ok(
		"行动、双方到场与实际路线已经建立",
		{
			"activity": activity,
			"embedded": false,
			"location_id": location_id,
			"target_activity": target_activity,
			"actor_travel": actor_travel.data.duplicate(true),
			"target_travel": target_travel.data.duplicate(true),
		},
		[actor_id, target_id, task_id]
	)


func _prepare_proposal(
	task: Dictionary, current_hour: int
) -> Dictionary:
	var proposal: Dictionary = super._prepare_proposal(task, current_hour)
	if not bool(proposal.get("prepared", false)):
		return proposal
	var target_id: String = str(task.get("target_id", ""))
	var target_activity_id: String = str(task.get("target_schedule_activity_id", ""))
	if not target_id.is_empty():
		var target_activity: Dictionary = _schedule_activity(
			target_id, target_activity_id
		)
		if target_activity.is_empty() or str(target_activity.get("status", "")) not in [
			"completed", "active",
		]:
			proposal["prepared"] = false
			proposal["success"] = false
			proposal["failure_step"] = "target_schedule_verification"
			proposal["failure_reason"] = "行动对象没有履行到场日程"
			return proposal
	var position_id: String = str(task.get("position_id", ""))
	if not position_id.is_empty():
		proposal["conflict_key"] = position_id
		var membership: Dictionary = _organizations.get_membership(
			str(task.get("actor_id", "")),
			str(_organizations.get_position(position_id).get("organization_id", ""))
		)
		if int(membership.get("participation", 0)) < 200:
			proposal["success"] = false
			proposal["failure_step"] = "position_prerequisite"
			proposal["failure_reason"] = "组织参与不足，尚不能直接取得职位"
	proposal["guaranteed_success"] = false
	if bool(proposal.get("prepared", false)):
		proposal["success"] = int(proposal.get("roll", 1000)) < int(
			proposal.get("threshold", 0)
		)
		if not bool(proposal["success"]) and str(proposal.get("failure_step", "")).is_empty():
			proposal["failure_step"] = "outcome_resolution"
			proposal["failure_reason"] = "方法已执行，但结果未达到成功条件"
	return proposal


func _resolve_batch(
	due_tasks: Array[Dictionary], current_hour: int
) -> Dictionary:
	if due_tasks.is_empty():
		return {"committed_events": 0, "rolled_back": false, "failed_groups": 0}
	var proposals: Array[Dictionary] = []
	for task: Dictionary in due_tasks:
		proposals.append(_prepare_proposal(task, current_hour))
	proposals.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score: int = int(left.get("outcome_score", 0))
		var right_score: int = int(right.get("outcome_score", 0))
		if left_score != right_score:
			return left_score > right_score
		return str(left.get("task_id", "")) < str(right.get("task_id", ""))
	)
	var conflict_winners: Dictionary = {}
	for index: int in range(proposals.size()):
		var proposal: Dictionary = proposals[index]
		if not bool(proposal.get("prepared", false)) or not bool(proposal.get("success", false)):
			continue
		var proposal_task: Dictionary = proposal.get("task", {}) as Dictionary
		var conflict_keys: Array[String] = _proposal_conflict_keys(proposal_task, proposal)
		var conflicting_key: String = ""
		for conflict_key: String in conflict_keys:
			if conflict_winners.has(conflict_key):
				conflicting_key = conflict_key
				break
		if not conflicting_key.is_empty():
			proposal["prepared"] = false
			proposal["success"] = false
			proposal["failure_step"] = "conflict_resolution"
			proposal["failure_reason"] = "同一时间的人员或唯一资源竞争失败"
			proposal["conflict_winner_task_id"] = str(conflict_winners[conflicting_key])
			proposals[index] = proposal
		else:
			for conflict_key: String in conflict_keys:
				conflict_winners[conflict_key] = str(proposal.get("task_id", ""))
	var committed_events: Array[Dictionary] = []
	var failed_groups: int = 0
	for proposal: Dictionary in proposals:
		var authority_before: Dictionary = _authority_snapshot()
		var own_before: Dictionary = _sandbox_commit_snapshot()
		var commit_result: V2LifeLoopResult = _commit_proposal(proposal, current_hour)
		if not commit_result.success:
			_restore_authority(authority_before)
			_restore_sandbox_commit_snapshot(own_before)
			var failed_task_id: String = str(proposal.get("task_id", ""))
			if tasks.has(failed_task_id):
				var failed_task: Dictionary = tasks[failed_task_id] as Dictionary
				failed_task["status"] = "failed"
				failed_task["failure_step"] = "atomic_commit"
				failed_task["failure_reason"] = commit_result.user_message
				tasks[failed_task_id] = failed_task
			failed_groups += 1
			continue
		var event: Dictionary = commit_result.data.get("event", {}) as Dictionary
		if not event.is_empty():
			committed_events.append(event)
	for event: Dictionary in committed_events:
		_publish_perceptions(event, current_hour)
		_queue_reaction(event, current_hour)
		mark_dirty([
			str(event.get("actor_id", "")),
			str(event.get("target_id", "")),
		])
	return {
		"committed_events": committed_events.size(),
		"rolled_back": failed_groups > 0,
		"failed_groups": failed_groups,
	}


func _apply_effect(
	task: Dictionary,
	method: Dictionary,
	event_id: String,
	current_hour: int,
	discovered: bool
) -> V2LifeLoopResult:
	var method_id: String = str(method.get("method_id", ""))
	match method_id:
		"ask_raise":
			return _apply_raise(task, event_id, current_hour)
		"support_candidate":
			return _apply_candidate_support(task, 18, event_id, current_hour)
		"oppose_candidate":
			return _apply_candidate_support(task, -18, event_id, current_hour)
		"call_meeting":
			var organization_id: String = str(task.get("organization_id", ""))
			return _organizations.adjust_participation(
				str(task.get("actor_id", "")), organization_id, 25,
				current_hour, event_id
			)
		"disobey_order":
			return _adjust_employment_risk(
				str(task.get("actor_id", "")), 80, event_id, current_hour
			)
		"sabotage":
			return _apply_task_sabotage(task, event_id, current_hour)
		"ask_question":
			return _new_evidence(
				str(task.get("actor_id", "")), str(task.get("target_id", "")),
				"reported_answer", event_id, current_hour, false
			)
		"observe":
			return _new_evidence(
				str(task.get("actor_id", "")), str(task.get("organization_id", "")),
				"direct_observation", event_id, current_hour, false
			)
		"investigate":
			return _new_evidence(
				str(task.get("actor_id", "")),
				str(task.get("target_id", task.get("organization_id", ""))),
				"investigation_trace", event_id, current_hour,
				bool(method.get("illegal", false))
			)
		"verify_fact":
			return _new_evidence(
				str(task.get("actor_id", "")),
				str(task.get("target_id", task.get("organization_id", ""))),
				"verified_fact", event_id, current_hour, false
			)
		"seek_position":
			var position_id: String = str(task.get("position_id", ""))
			if position_id.is_empty():
				return V2LifeLoopResult.fail(
					"position_required", "争取职位必须对应具体职位"
				)
			return _organizations.claim_position(
				str(task.get("actor_id", "")), position_id, current_hour, event_id
			)
	return super._apply_effect(task, method, event_id, current_hour, discovered)


func _settle_commitment(
	actor_id: String,
	target_id: String,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	var has_open: bool = false
	for raw_commitment: Variant in commitments.values():
		var commitment: Dictionary = raw_commitment as Dictionary
		if (
			str(commitment.get("promisor_id", "")) == actor_id
			and str(commitment.get("status", "")) == "open"
			and (
				target_id.is_empty()
				or str(commitment.get("beneficiary_id", "")) == target_id
			)
		):
			has_open = true
			break
	if not has_open:
		return V2LifeLoopResult.fail(
			"no_open_commitment", "没有可以履行的既有承诺，不能把偿还人情变成新承诺。"
		)
	return super._settle_commitment(actor_id, target_id, event_id, current_hour)


func _proposal_conflict_keys(
	task: Dictionary, proposal: Dictionary
) -> Array[String]:
	var start_hour: int = int(task.get("start_hour", -1))
	var end_hour: int = int(task.get("end_hour", -1))
	var result: Array[String] = [
		"person:%s:%d:%d" % [str(task.get("actor_id", "")), start_hour, end_hour],
	]
	var target_id: String = str(task.get("target_id", ""))
	if not target_id.is_empty():
		result.append("person:%s:%d:%d" % [target_id, start_hour, end_hour])
	var unique_key: String = str(proposal.get("conflict_key", ""))
	if not unique_key.is_empty():
		result.append("unique:%s" % unique_key)
	if str(task.get("method_id", "")) == "hide_evidence":
		result.append("evidence_owner:%s" % str(task.get("actor_id", "")))
	return result


func _find_joint_window(
	actor_id: String,
	target_id: String,
	source: String,
	start_hour: int,
	end_hour: int,
	duration: int
) -> int:
	var actor_source: String = "player" if source == "player" else "npc_rule"
	for candidate: int in range(start_hour, end_hour):
		var actor_check: V2LifeLoopResult = _schedule.can_schedule_activity(
			actor_id, "social_action", candidate, duration, actor_source
		)
		if not actor_check.success:
			continue
		if not target_id.is_empty():
			var target_check: V2LifeLoopResult = _schedule.can_schedule_activity(
				target_id, "social_action", candidate, duration, "npc_rule"
			)
			if not target_check.success:
				continue
		return candidate
	return -1


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
			"route_unavailable", "人物无法在行动开始前到达地点", location_id,
			[person_id, location_id]
		)
	var departure_hour: int = int(preview.get("departure_hour", current_hour + 1))
	var result: V2LifeLoopResult = _product.request_travel(
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
		}
	)


func _route_preview_before(
	person_id: String,
	location_id: String,
	action_start: int,
	current_hour: int
) -> Dictionary:
	var position: Dictionary = _locations.position_for(person_id)
	if (
		str(position.get("location_state", "")) == "at_location"
		and str(position.get("current_location_id", "")) == location_id
	):
		return {
			"required": false,
			"success": true,
			"departure_hour": action_start,
			"arrival_hour": action_start,
		}
	var first_preview: V2LifeLoopResult = _product.preview_route(
		person_id, location_id, "fastest", current_hour + 1
	)
	if not first_preview.success:
		return {"required": true, "success": false}
	var first_departure: int = int(first_preview.data.get("departure_hour", current_hour + 1))
	var first_arrival: int = int(first_preview.data.get("arrival_hour", first_departure + 1))
	var duration: int = maxi(1, first_arrival - first_departure)
	var departure: int = maxi(current_hour + 1, action_start - duration)
	var timed: V2LifeLoopResult = _product.preview_route(
		person_id, location_id, "fastest", departure
	)
	if not timed.success:
		return {"required": true, "success": false}
	var arrival: int = int(timed.data.get("arrival_hour", departure + duration))
	return {
		"required": true,
		"success": arrival <= action_start,
		"departure_hour": departure,
		"arrival_hour": arrival,
		"duration_hours": maxi(1, arrival - departure),
		"cost_centimes": int(timed.data.get("total_cost_centimes", 0)),
	}


func _travel_snapshot() -> Dictionary:
	if _product == null:
		return {}
	return {
		"schedule": _schedule.get_persistent_state(),
		"spatial": _product.spatial_locations.get_persistent_state(),
		"travel": _product.travel_execution.get_persistent_state(),
		"households": _households.get_persistent_state(),
		"ledger": _ledger.get_persistent_state(),
		"manual_holds": _product.manual_location_holds.duplicate(true),
	}


func _restore_travel_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or _product == null:
		return
	_schedule.restore_persistent_state(snapshot.get("schedule", {}) as Dictionary)
	_product.spatial_locations.restore_persistent_state(
		snapshot.get("spatial", {}) as Dictionary
	)
	_product.travel_execution.restore_persistent_state(
		snapshot.get("travel", {}) as Dictionary
	)
	_households.restore_persistent_state(snapshot.get("households", {}) as Dictionary)
	_ledger.restore_persistent_state(snapshot.get("ledger", {}) as Dictionary)
	_product.manual_location_holds = (
		snapshot.get("manual_holds", {}) as Dictionary
	).duplicate(true)


func _apply_raise(
	task: Dictionary, event_id: String, current_hour: int
) -> V2LifeLoopResult:
	var actor_id: String = str(task.get("actor_id", ""))
	for contract_id_variant: Variant in _employment.contracts.keys():
		var contract_id: String = str(contract_id_variant)
		var contract: Dictionary = _employment.contracts[contract_id] as Dictionary
		if str(contract.get("person_id", "")) != actor_id:
			continue
		if str(contract.get("contract_status", "")) != "active":
			return V2LifeLoopResult.fail("inactive_contract", "当前劳动合同不再有效")
		var previous_wage: int = int(contract.get("base_wage_centimes", 0))
		var increase: int = maxi(10, ceili(float(previous_wage) * 0.05))
		contract["base_wage_centimes"] = previous_wage + increase
		var history: Array = contract.get("wage_history", []) as Array
		history.append({
			"event_id": event_id,
			"datetime": V2DateTime.iso_from_total_hour(current_hour),
			"previous_wage_centimes": previous_wage,
			"new_wage_centimes": previous_wage + increase,
		})
		while history.size() > 16:
			history.pop_front()
		contract["wage_history"] = history
		_employment.contracts[contract_id] = contract
		return V2LifeLoopResult.ok(
			"加薪谈判改变了实际劳动合同",
			{"contract": contract.duplicate(true), "wage_delta_centimes": increase},
			[actor_id, contract_id]
		)
	return V2LifeLoopResult.fail("contract_not_found", "人物没有可谈判的劳动合同")


func _apply_candidate_support(
	task: Dictionary,
	delta: int,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	var actor_id: String = str(task.get("actor_id", ""))
	var target_id: String = str(task.get("target_id", ""))
	var organization_id: String = str(task.get("organization_id", ""))
	if target_id.is_empty() or organization_id.is_empty():
		return V2LifeLoopResult.fail(
			"candidate_context_required", "候选人支持行动缺少人物或组织"
		)
	var participation: V2LifeLoopResult = _organizations.adjust_participation(
		target_id, organization_id, delta, current_hour, event_id
	)
	if not participation.success:
		return participation
	var relation_type: String = "cooperation" if delta > 0 else "competition_loss"
	var relation: V2LifeLoopResult = _apply_relationship_effect(
		actor_id, target_id, relation_type, event_id, current_hour
	)
	if not relation.success:
		return relation
	return V2LifeLoopResult.ok(
		"候选人的实际组织基础已经变化",
		{
			"participation": participation.data.duplicate(true),
			"relationship": relation.data.duplicate(true),
			"support_delta": delta,
		}
	)


func _adjust_employment_risk(
	person_id: String,
	delta: int,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	for contract_id_variant: Variant in _employment.contracts.keys():
		var contract_id: String = str(contract_id_variant)
		var contract: Dictionary = _employment.contracts[contract_id] as Dictionary
		if str(contract.get("person_id", "")) != person_id:
			continue
		contract["employment_risk"] = clampi(
			int(contract.get("employment_risk", 0)) + delta, 0, 1000
		)
		contract["last_risk_event_id"] = event_id
		contract["last_risk_datetime"] = V2DateTime.iso_from_total_hour(current_hour)
		_employment.contracts[contract_id] = contract
		return V2LifeLoopResult.ok(
			"劳动关系风险已经改变",
			{"contract": contract.duplicate(true), "risk_delta": delta},
			[person_id, contract_id]
		)
	return V2LifeLoopResult.fail("contract_not_found", "人物没有劳动合同")


func _apply_task_sabotage(
	task: Dictionary, event_id: String, current_hour: int
) -> V2LifeLoopResult:
	var actor_id: String = str(task.get("actor_id", ""))
	var target_id: String = str(task.get("target_id", ""))
	var candidate_ids: Array[String] = []
	for task_id_variant: Variant in tasks.keys():
		var candidate_id: String = str(task_id_variant)
		var candidate: Dictionary = tasks[candidate_id] as Dictionary
		if (
			str(candidate.get("actor_id", "")) == target_id
			and str(candidate.get("status", "")) == "scheduled"
			and int(candidate.get("start_hour", -1)) > current_hour
		):
			candidate_ids.append(candidate_id)
	candidate_ids.sort()
	if candidate_ids.is_empty():
		return V2LifeLoopResult.fail(
			"no_target_plan", "行动对象当前没有可被破坏的未来计划"
		)
	var victim_task_id: String = candidate_ids.front()
	var victim: Dictionary = tasks[victim_task_id] as Dictionary
	var cancel_result: V2LifeLoopResult = _schedule.cancel_activity_by_id(
		target_id,
		str(victim.get("schedule_activity_id", "")),
		current_hour,
		"social_sabotage:%s" % event_id
	)
	if not cancel_result.success:
		return cancel_result
	victim["status"] = "cancelled"
	victim["cancelled_by_event_id"] = event_id
	tasks[victim_task_id] = victim
	var relation: V2LifeLoopResult = _apply_relationship_effect(
		actor_id, target_id, "threat", event_id, current_hour
	)
	if not relation.success:
		return relation
	var trace: V2LifeLoopResult = _new_evidence(
		actor_id, target_id, "sabotage_trace", event_id, current_hour, true
	)
	if not trace.success:
		return trace
	return V2LifeLoopResult.ok(
		"对方的具体未来计划已被破坏",
		{
			"cancelled_task_id": victim_task_id,
			"relationship": relation.data.duplicate(true),
			"evidence": trace.data.duplicate(true),
		}
	)


func _position_id_from_goal(goal: Dictionary) -> String:
	var signal_key: String = str(goal.get("signal_key", ""))
	if signal_key.begins_with("position:"):
		return signal_key.trim_prefix("position:")
	if signal_key.begins_with("position_held:"):
		return signal_key.trim_prefix("position_held:")
	return ""


func _membership_for_position_goal(
	person_id: String, signal_key: String
) -> Dictionary:
	var position_id: String = signal_key.trim_prefix("position:")
	var position: Dictionary = _organizations.get_position(position_id)
	return _organizations.get_membership(
		person_id, str(position.get("organization_id", ""))
	)


static func _sanitize_id(value: String) -> String:
	var result: String = ""
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1)
		if "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character.to_lower()):
			result += character.to_lower()
		else:
			result += "_"
	return result
