class_name V23SocialSandboxService
extends RefCounted
## One coordinator for derived situations, unified intents, scheduled social
## tasks, deterministic event resolution, perceptions and bounded reactions.
##
## It deliberately does not own clocks, cash, locations, relationships,
## knowledge, schedules or organization membership. Those remain in the
## existing authoritative services supplied to configure().

const STATE_VERSION: int = 1
const PHASE_PREPARE: int = 1
const PHASE_CONFLICT: int = 2
const PHASE_COMMIT: int = 3
const SIGNAL_KINDS: PackedStringArray = [
	"maintenance", "threat", "opportunity", "ambition",
]
const NEGATIVE_EFFECTS: PackedStringArray = [
	"relationship_negative", "coercion", "deception", "sabotage",
	"hide_evidence", "forge_evidence",
]

var situations: Dictionary = {}
var goals: Dictionary = {}
var intents: Dictionary = {}
var tasks: Dictionary = {}
var event_ledger: Array[Dictionary] = []
var commitments: Dictionary = {}
var evidence_records: Dictionary = {}
var pending_reactions: Array[Dictionary] = []
var decision_explanations: Dictionary = {}
var last_planned_dates: Dictionary = {}
var player_person_id: String = ""

var _rules: Dictionary = {}
var _people: Dictionary = {}
var _methods: Dictionary = {}
var _dirty_people: Dictionary = {}
var _next_signal_sequence: int = 1
var _next_goal_sequence: int = 1
var _next_intent_sequence: int = 1
var _next_task_sequence: int = 1
var _next_event_sequence: int = 1
var _next_commitment_sequence: int = 1
var _next_evidence_sequence: int = 1
var _last_processed_hour: int = -1

var _schedule: V2ScheduleService
var _locations: SpatialLocationService
var _relationships: V23RelationshipService
var _knowledge: KnowledgeService
var _organizations: V2OrganizationActivityService
var _households: V2HouseholdService
var _ledger: V2LedgerService
var _employment: V2EmploymentService

# Test-only fault injection. The production UI never exposes this flag.
var fail_next_commit_for_test: bool = false


func configure(
	people: Array,
	rules: Dictionary,
	schedule: V2ScheduleService,
	locations: SpatialLocationService,
	relationships: V23RelationshipService,
	knowledge: KnowledgeService,
	organizations: V2OrganizationActivityService,
	households: V2HouseholdService,
	ledger: V2LedgerService,
	employment: V2EmploymentService,
	start_hour: int,
	controlled_person_id: String = ""
) -> V2LifeLoopResult:
	_rules = rules.duplicate(true)
	_schedule = schedule
	_locations = locations
	_relationships = relationships
	_knowledge = knowledge
	_organizations = organizations
	_households = households
	_ledger = ledger
	_employment = employment
	_people.clear()
	_methods.clear()
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = (raw_person as Dictionary).duplicate(true)
		var person_id: String = str(person.get("person_id", ""))
		if not person_id.is_empty():
			_people[person_id] = person
	for raw_method: Variant in rules.get("methods", []) as Array:
		if not raw_method is Dictionary:
			continue
		var method: Dictionary = (raw_method as Dictionary).duplicate(true)
		_methods[str(method.get("method_id", ""))] = method
	player_person_id = controlled_person_id
	if (
		_people.is_empty()
		or _methods.is_empty()
		or _schedule == null
		or _locations == null
		or _relationships == null
		or _knowledge == null
		or _organizations == null
		or (
			not player_person_id.is_empty()
			and not _people.has(player_person_id)
		)
	):
		return V2LifeLoopResult.fail(
			"sandbox_dependency_missing",
			"社会沙盒缺少现有权威服务或规则"
		)
	var organization_result: V2LifeLoopResult = (
		_organizations.configure_social_structure(
			rules.get("organizations", []) as Array,
			rules.get("memberships", []) as Array,
			rules.get("positions", []) as Array
		)
	)
	if not organization_result.success:
		return organization_result
	_reset_runtime_state()
	for person_id_variant: Variant in _people.keys():
		var person_id: String = str(person_id_variant)
		situations[person_id] = []
		goals[person_id] = []
		decision_explanations[person_id] = []
		_dirty_people[person_id] = true
	reevaluate_dirty(start_hour)
	_plan_npcs(start_hour)
	_last_processed_hour = start_hour
	return V2LifeLoopResult.ok(
		"社会沙盒闭环已接入现有权威服务",
		{
			"people": _people.size(),
			"methods": _methods.size(),
			"organizations": _organizations.organizations.size(),
		}
	)


func set_player_person(person_id: String) -> bool:
	if not _people.has(person_id):
		return false
	if player_person_id == person_id:
		return true
	var previous_person_id: String = player_person_id
	player_person_id = person_id
	if not previous_person_id.is_empty():
		last_planned_dates.erase(previous_person_id)
		_dirty_people[previous_person_id] = true
	last_planned_dates.erase(person_id)
	_dirty_people[person_id] = true
	return true


func reset_from_authority(current_hour: int) -> void:
	var organization_result: V2LifeLoopResult = (
		_organizations.configure_social_structure(
			_rules.get("organizations", []) as Array,
			_rules.get("memberships", []) as Array,
			_rules.get("positions", []) as Array
		)
	)
	if not organization_result.success:
		push_error(
			"社会沙盒无法从权威状态重建组织结构：%s"
			% organization_result.user_message
		)
	_reset_runtime_state()
	for person_id_variant: Variant in _people.keys():
		var person_id: String = str(person_id_variant)
		situations[person_id] = []
		goals[person_id] = []
		decision_explanations[person_id] = []
		_dirty_people[person_id] = true
	reevaluate_dirty(current_hour)
	_plan_npcs(current_hour)
	_last_processed_hour = current_hour


func process_hour(settled_hour: int) -> Dictionary:
	var current_hour: int = settled_hour + 1
	if current_hour <= _last_processed_hour:
		return {"already_processed": true, "hour": current_hour}
	var reaction_count: int = _process_due_reactions(current_hour)
	var due: Array[Dictionary] = _due_tasks(current_hour)
	var batch_result: Dictionary = _resolve_batch(due, current_hour)
	var value: Dictionary = V2DateTime.from_total_hour(current_hour)
	var daily_hour: int = int(
		(_rules.get("planning", {}) as Dictionary).get(
			"reevaluate_hour", 6
		)
	)
	if int(value.get("hour", -1)) == daily_hour:
		for person_id_variant: Variant in _people.keys():
			_dirty_people[str(person_id_variant)] = true
	if not _dirty_people.is_empty():
		reevaluate_dirty(current_hour)
	if int(value.get("hour", -1)) == daily_hour:
		_plan_npcs(current_hour)
	_prune()
	_last_processed_hour = current_hour
	return {
		"hour": current_hour,
		"due_tasks": due.size(),
		"committed_events": int(batch_result.get("committed_events", 0)),
		"rolled_back": bool(batch_result.get("rolled_back", false)),
		"reactions": reaction_count,
	}


func reevaluate_dirty(current_hour: int) -> void:
	var person_ids: Array[String] = []
	for person_id_variant: Variant in _dirty_people.keys():
		var person_id: String = str(person_id_variant)
		if _people.has(person_id):
			person_ids.append(person_id)
	person_ids.sort()
	for person_id: String in person_ids:
		var derived: Array[Dictionary] = _derive_situations(
			person_id, current_hour
		)
		situations[person_id] = derived
		goals[person_id] = _derive_goals(person_id, derived, current_hour)
		_dirty_people.erase(person_id)


func submit_intent(
	actor_id: String,
	goal_id: String,
	method_id: String,
	target_id: String = "",
	source: String = "player",
	options: Dictionary = {}
) -> V2LifeLoopResult:
	if not _people.has(actor_id):
		return V2LifeLoopResult.fail(
			"unknown_person", "找不到行动人物", actor_id, [actor_id]
		)
	if source not in ["player", "npc", "reaction"]:
		return V2LifeLoopResult.fail(
			"invalid_intent_source", "行动意图来源无效", source
		)
	var method: Dictionary = method_record(method_id)
	if method.is_empty():
		return V2LifeLoopResult.fail(
			"unknown_method", "找不到行动方法", method_id, [actor_id]
		)
	var goal: Dictionary = _goal_by_id(actor_id, goal_id)
	if goal.is_empty():
		return V2LifeLoopResult.fail(
			"unknown_goal", "目标已经失效或不存在", goal_id, [actor_id]
		)
	if str(goal.get("kind", "")) not in (
		method.get("goal_kinds", []) as Array
	):
		return V2LifeLoopResult.fail(
			"method_goal_mismatch", "该方法不适用于当前目标",
			"%s/%s" % [goal_id, method_id], [actor_id]
		)
	var resolved_target: String = _resolve_target(
		actor_id, target_id, method
	)
	if (
		_method_requires_target(method)
		and resolved_target.is_empty()
	):
		return V2LifeLoopResult.fail(
			"target_unavailable", "该方法当前没有可用对象",
			method_id, [actor_id]
		)
	var organization_id: String = _resolve_organization(
		actor_id, goal, method, options
	)
	var location_id: String = _resolve_method_location(
		actor_id, resolved_target, organization_id, method
	)
	var intent_id: String = "intent:v2_3:%07d" % _next_intent_sequence
	_next_intent_sequence += 1
	var task_id: String = "social_task:v2_3:%07d" % _next_task_sequence
	_next_task_sequence += 1
	var current_hour: int = int(options.get(
		"current_hour", _last_processed_hour
	))
	var reservation: V2LifeLoopResult = _reserve_schedule(
		task_id,
		actor_id,
		resolved_target,
		method,
		location_id,
		source,
		current_hour
	)
	var intent: Dictionary = {
		"intent_id": intent_id,
		"actor_id": actor_id,
		"goal_id": goal_id,
		"method_id": method_id,
		"target_id": resolved_target,
		"organization_id": organization_id,
		"location_id": location_id,
		"source": source,
		"created_hour": current_hour,
		"created_datetime": V2DateTime.iso_from_total_hour(current_hour),
		"preparation": clampi(int(options.get("preparation", 200)), 0, 1000),
		"cause_event_id": str(options.get(
			"cause_event_id", goal.get("cause_event_id", "")
		)),
		"status": "scheduled" if reservation.success else "rejected",
		"failure_code": "" if reservation.success else reservation.error_code,
	}
	intents[intent_id] = intent
	if not reservation.success:
		_remember_explanation(actor_id, {
			"hour": current_hour,
			"goal_id": goal_id,
			"method_id": method_id,
			"decision": "schedule_failed",
			"reason": reservation.user_message,
			"failure_step": "schedule_reservation",
		})
		return reservation
	var activity: Dictionary = reservation.data.get(
		"activity", {}
	) as Dictionary
	var task: Dictionary = {
		"task_id": task_id,
		"intent_id": intent_id,
		"actor_id": actor_id,
		"target_id": resolved_target,
		"organization_id": organization_id,
		"method_id": method_id,
		"goal_id": goal_id,
		"location_id": str(reservation.data.get(
			"location_id", location_id
		)),
		"start_hour": int(activity.get("start_hour", -1)),
		"end_hour": int(activity.get("end_hour", -1)),
		"schedule_activity_id": str(activity.get("activity_id", "")),
		"embedded": bool(reservation.data.get("embedded", false)),
		"source": source,
		"preparation": int(intent.get("preparation", 0)),
		"cause_event_id": str(intent.get("cause_event_id", "")),
		"status": "scheduled",
		"created_hour": current_hour,
	}
	tasks[task_id] = task
	intent["task_id"] = task_id
	intents[intent_id] = intent
	_remember_explanation(actor_id, {
		"hour": current_hour,
		"goal_id": goal_id,
		"method_id": method_id,
		"decision": "scheduled",
		"reason": "方法通过统一意图 API，并已绑定现有权威日程",
		"task_id": task_id,
		"known": _known_evidence_for(actor_id, goal),
	})
	return V2LifeLoopResult.ok(
		"行动意图已转为日程任务",
		{
			"intent": intent.duplicate(true),
			"task": task.duplicate(true),
			"illegal_attempt": bool(method.get("illegal", false)),
		},
		[actor_id, intent_id, task_id]
	)


func situations_for(person_id: String) -> Array[Dictionary]:
	return _dictionary_array_copy(situations.get(person_id, []) as Array)


func goals_for(person_id: String) -> Array[Dictionary]:
	return _dictionary_array_copy(goals.get(person_id, []) as Array)


func methods_for(person_id: String, goal_id: String) -> Array[Dictionary]:
	var goal: Dictionary = _goal_by_id(person_id, goal_id)
	if goal.is_empty():
		return []
	var result: Array[Dictionary] = []
	var method_ids: Array[String] = []
	for method_id_variant: Variant in _methods.keys():
		method_ids.append(str(method_id_variant))
	method_ids.sort()
	for method_id: String in method_ids:
		var method: Dictionary = _methods[method_id] as Dictionary
		if str(goal.get("kind", "")) not in (
			method.get("goal_kinds", []) as Array
		):
			continue
		var decorated: Dictionary = method.duplicate(true)
		decorated["available"] = (
			not _method_requires_target(method)
			or not _resolve_target(person_id, "", method).is_empty()
		)
		decorated["illegal_attempt_allowed"] = bool(
			method.get("illegal", false)
		)
		decorated["expected_consequence"] = _method_consequence(method)
		result.append(decorated)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score: int = _method_utility(person_id, goal, left)
		var right_score: int = _method_utility(person_id, goal, right)
		if left_score != right_score:
			return left_score > right_score
		return str(left.get("method_id", "")) < str(
			right.get("method_id", "")
		)
	)
	return result


func tasks_for(person_id: String, include_terminal: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_task: Variant in tasks.values():
		var task: Dictionary = raw_task as Dictionary
		if str(task.get("actor_id", "")) != person_id:
			continue
		if (
			not include_terminal
			and str(task.get("status", "")) not in ["scheduled", "active"]
		):
			continue
		result.append(task.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_hour: int = int(left.get("start_hour", 0))
		var right_hour: int = int(right.get("start_hour", 0))
		if left_hour != right_hour:
			return left_hour < right_hour
		return str(left.get("task_id", "")) < str(right.get("task_id", ""))
	)
	return result


func visible_events_for(
	person_id: String, truth_view: bool = false, limit: int = 20
) -> Array[Dictionary]:
	var known_event_ids: Dictionary = {}
	if not truth_view:
		for record: Dictionary in _knowledge.records_for_person(person_id):
			if str(record.get("fact_type", "")) == "social_event":
				known_event_ids[str(record.get("subject_id", ""))] = true
	var result: Array[Dictionary] = []
	for index: int in range(event_ledger.size() - 1, -1, -1):
		var event: Dictionary = event_ledger[index]
		var event_id: String = str(event.get("event_id", ""))
		if (
			not truth_view
			and not known_event_ids.has(event_id)
			and str(event.get("actor_id", "")) != person_id
			and str(event.get("target_id", "")) != person_id
		):
			continue
		result.append(event.duplicate(true))
		if result.size() >= limit:
			break
	return result


func explanation_for(person_id: String) -> Dictionary:
	var history: Array = decision_explanations.get(person_id, []) as Array
	return (
		(history.back() as Dictionary).duplicate(true)
		if not history.is_empty()
		else {}
	)


func method_record(method_id: String) -> Dictionary:
	var value: Variant = _methods.get(method_id, {})
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


func mark_dirty(person_ids: Array) -> void:
	for raw_person_id: Variant in person_ids:
		var person_id: String = str(raw_person_id)
		if _people.has(person_id):
			_dirty_people[person_id] = true


func get_persistent_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"situations": situations.duplicate(true),
		"goals": goals.duplicate(true),
		"intents": intents.duplicate(true),
		"tasks": tasks.duplicate(true),
		"event_ledger": event_ledger.duplicate(true),
		"commitments": commitments.duplicate(true),
		"evidence_records": evidence_records.duplicate(true),
		"pending_reactions": pending_reactions.duplicate(true),
		"decision_explanations": decision_explanations.duplicate(true),
		"last_planned_dates": last_planned_dates.duplicate(true),
		"player_person_id": player_person_id,
		"dirty_people": _dirty_people.duplicate(true),
		"next_signal_sequence": _next_signal_sequence,
		"next_goal_sequence": _next_goal_sequence,
		"next_intent_sequence": _next_intent_sequence,
		"next_task_sequence": _next_task_sequence,
		"next_event_sequence": _next_event_sequence,
		"next_commitment_sequence": _next_commitment_sequence,
		"next_evidence_sequence": _next_evidence_sequence,
		"last_processed_hour": _last_processed_hour,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if int(state.get("state_version", 0)) != STATE_VERSION:
		return false
	var restored_player_person_id: String = str(
		state.get("player_person_id", player_person_id)
	)
	if (
		not restored_player_person_id.is_empty()
		and not _people.has(restored_player_person_id)
	):
		return false
	for field: String in [
		"situations", "goals", "intents", "tasks", "commitments",
		"evidence_records", "decision_explanations", "last_planned_dates",
		"dirty_people",
	]:
		if not state.get(field, {}) is Dictionary:
			return false
	for field: String in ["event_ledger", "pending_reactions"]:
		if not state.get(field, []) is Array:
			return false
	var restored_tasks: Dictionary = state["tasks"] as Dictionary
	var task_ids: Dictionary = {}
	for task_id_variant: Variant in restored_tasks.keys():
		var task_id: String = str(task_id_variant)
		var raw_task: Variant = restored_tasks[task_id]
		if not raw_task is Dictionary:
			return false
		var task: Dictionary = raw_task as Dictionary
		if (
			task_id.is_empty()
			or task_id != str(task.get("task_id", ""))
			or task_ids.has(task_id)
			or not _people.has(str(task.get("actor_id", "")))
			or not _methods.has(str(task.get("method_id", "")))
			or str(task.get("status", "")) not in [
				"scheduled", "active", "completed", "failed", "cancelled",
			]
		):
			return false
		task_ids[task_id] = true
	var restored_events: Array[Dictionary] = []
	var event_ids: Dictionary = {}
	var previous_order: String = ""
	for raw_event: Variant in state["event_ledger"] as Array:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = (raw_event as Dictionary).duplicate(true)
		var event_id: String = str(event.get("event_id", ""))
		var order_key: String = _event_order_key(event)
		if (
			event_id.is_empty()
			or event_ids.has(event_id)
			or (not previous_order.is_empty() and order_key <= previous_order)
		):
			return false
		event_ids[event_id] = true
		previous_order = order_key
		restored_events.append(event)
	for raw_event: Dictionary in restored_events:
		var cause_event_id: String = str(raw_event.get("cause_event_id", ""))
		if (
			not cause_event_id.is_empty()
			and cause_event_id.begins_with("social_event:")
			and not event_ids.has(cause_event_id)
		):
			return false
	for field: String in [
		"next_signal_sequence", "next_goal_sequence", "next_intent_sequence",
		"next_task_sequence", "next_event_sequence",
		"next_commitment_sequence", "next_evidence_sequence",
	]:
		if int(state.get(field, 0)) < 1:
			return false
	situations = (state["situations"] as Dictionary).duplicate(true)
	goals = (state["goals"] as Dictionary).duplicate(true)
	intents = (state["intents"] as Dictionary).duplicate(true)
	tasks = restored_tasks.duplicate(true)
	event_ledger = restored_events
	commitments = (state["commitments"] as Dictionary).duplicate(true)
	evidence_records = (state["evidence_records"] as Dictionary).duplicate(true)
	pending_reactions = _dictionary_array_copy(
		state["pending_reactions"] as Array
	)
	decision_explanations = (
		state["decision_explanations"] as Dictionary
	).duplicate(true)
	last_planned_dates = (
		state["last_planned_dates"] as Dictionary
	).duplicate(true)
	player_person_id = restored_player_person_id
	_dirty_people = (state["dirty_people"] as Dictionary).duplicate(true)
	_next_signal_sequence = int(state["next_signal_sequence"])
	_next_goal_sequence = int(state["next_goal_sequence"])
	_next_intent_sequence = int(state["next_intent_sequence"])
	_next_task_sequence = int(state["next_task_sequence"])
	_next_event_sequence = int(state["next_event_sequence"])
	_next_commitment_sequence = int(state["next_commitment_sequence"])
	_next_evidence_sequence = int(state["next_evidence_sequence"])
	_last_processed_hour = int(state.get("last_processed_hour", -1))
	fail_next_commit_for_test = false
	return true


func _derive_situations(
	person_id: String, current_hour: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var person: Dictionary = _people[person_id] as Dictionary
	var household: Dictionary = _households.household_for_person(person_id)
	var contract: Dictionary = _employment.contract_for_person(person_id)
	var livelihood_urgency: int = 350
	var livelihood_provenance: Array[Dictionary] = []
	if not household.is_empty():
		var cash: int = int(household.get("cash_centimes", 0))
		var arrears: int = int(household.get("rent_arrears_centimes", 0))
		livelihood_urgency = clampi(700 - cash / 20 + arrears / 4, 120, 950)
		livelihood_provenance.append({
			"service": "V2HouseholdService",
			"field": "cash_centimes",
			"value": cash,
		})
		livelihood_provenance.append({
			"service": "V2HouseholdService",
			"field": "rent_arrears_centimes",
			"value": arrears,
		})
	else:
		livelihood_provenance.append({
			"service": "V2ScheduleService",
			"field": "workplace_location_id",
			"value": str(person.get("workplace_location_id", "")),
		})
	if not contract.is_empty():
		livelihood_provenance.append({
			"service": "V2EmploymentService",
			"field": "employment_risk",
			"value": int(contract.get("employment_risk", 0)),
		})
	result.append(_make_signal(
		person_id,
		"maintenance",
		"维持生计与可靠声誉",
		"持续履行工作与生活义务，避免现金和信誉恶化。",
		livelihood_urgency,
		current_hour + 7 * 24,
		livelihood_provenance,
		"现金、合同或工作关系发生变化时重新评估",
		"stability"
	))
	var employment_risk: int = int(contract.get("employment_risk", 0))
	if employment_risk >= 100:
		result.append(_make_signal(
			person_id,
			"threat",
			"就业稳定性正在下降",
			"继续缺勤或公开冲突可能导致失去工作。",
			clampi(500 + employment_risk / 2, 0, 1000),
			current_hour + 72,
			[{
				"service": "V2EmploymentService",
				"field": "employment_risk",
				"value": employment_risk,
			}],
			"就业风险回落到 100 以下",
			"employment_risk"
		))
	var memberships: Array[Dictionary] = (
		_organizations.memberships_for_person(person_id)
	)
	var delegate: Dictionary = _organizations.get_position(
		"factory_fives_workgroup_three:delegate"
	)
	if (
		_organizations.is_active_member(
			person_id, "factory_fives_workgroup_three"
		)
		and str(delegate.get("holder_person_id", "")).is_empty()
	):
		result.append(_make_signal(
			person_id,
			"opportunity",
			"工作组代表职位空缺",
			"取得职位会扩大在工厂同事与工会中的影响。",
			820,
			current_hour + 14 * 24,
			[{
				"service": "V2OrganizationActivityService",
				"field": "positions.factory_fives_workgroup_three:delegate",
				"value": "vacant",
			}],
			"职位已有持有人或人物退出工作组",
			"factory_delegate"
		))
	elif (
		_organizations.is_active_member(
			person_id, "factory_fives_workgroup_three"
		)
		and str(delegate.get("holder_person_id", "")) != person_id
	):
		result.append(_make_signal(
			person_id,
			"threat",
			"同事已取得工作组代表职位",
			"新的代表可能改变工作组内部的资源与发言权。",
			520,
			current_hour + 7 * 24,
			[{
				"service": "V2OrganizationActivityService",
				"field": "holder_person_id",
				"value": str(delegate.get("holder_person_id", "")),
			}],
			"职位持有人变化",
			"factory_delegate_held"
		))
	if not memberships.is_empty():
		result.append(_make_signal(
			person_id,
			"ambition",
			"扩大组织影响",
			"通过合作、会议、承诺或职位逐步积累实际支持。",
			430 + memberships.size() * 30,
			current_hour + 30 * 24,
			[{
				"service": "V2OrganizationActivityService",
				"field": "active_memberships",
				"value": memberships.size(),
			}],
			"人物离开全部组织",
			"organization_influence"
		))
	var strongest_tension: int = 0
	var tense_target: String = ""
	for raw_relation: Variant in _relationships.relationships.values():
		var relation: Dictionary = raw_relation as Dictionary
		if str(relation.get("person_id", "")) != person_id:
			continue
		var tension: int = int(relation.get("tension", 0))
		if tension > strongest_tension:
			strongest_tension = tension
			tense_target = str(relation.get("target_id", ""))
	if strongest_tension >= 120:
		result.append(_make_signal(
			person_id,
			"threat",
			"人际紧张正在累积",
			"未处理的冲突可能破坏合作与承诺。",
			clampi(450 + strongest_tension / 2, 0, 1000),
			current_hour + 7 * 24,
			[{
				"service": "V23RelationshipService",
				"field": "tension",
				"value": strongest_tension,
				"target_id": tense_target,
			}],
			"关系紧张降至 120 以下",
			"relationship_tension"
		))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_urgency: int = int(left.get("urgency", 0))
		var right_urgency: int = int(right.get("urgency", 0))
		if left_urgency != right_urgency:
			return left_urgency > right_urgency
		return str(left.get("signal_id", "")) < str(
			right.get("signal_id", "")
		)
	)
	var limit: int = int(
		(_rules.get("limits", {}) as Dictionary).get(
			"situations_per_person", 12
		)
	)
	if result.size() > limit:
		result.resize(limit)
	return result


func _derive_goals(
	person_id: String,
	derived: Array[Dictionary],
	current_hour: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var limit: int = int(
		(_rules.get("limits", {}) as Dictionary).get(
			"goals_per_person", 4
		)
	)
	for situation_record: Dictionary in derived:
		if result.size() >= limit:
			break
		var goal_id: String = "social_goal:v2_3:%07d" % _next_goal_sequence
		_next_goal_sequence += 1
		result.append({
			"goal_id": goal_id,
			"person_id": person_id,
			"kind": str(situation_record.get("kind", "")),
			"title_zh": str(situation_record.get("title_zh", "")),
			"desired_outcome": str(
				situation_record.get("expected_consequence", "")
			),
			"urgency": int(situation_record.get("urgency", 0)),
			"signal_id": str(situation_record.get("signal_id", "")),
			"signal_key": str(situation_record.get("signal_key", "")),
			"created_hour": current_hour,
			"expires_hour": int(
				situation_record.get("expires_hour", current_hour + 24)
			),
			"known_evidence": (
				situation_record.get("known_evidence", []) as Array
			).duplicate(true),
			"cause_event_id": str(
				situation_record.get("cause_event_id", "")
			),
			"status": "active",
		})
	return result


func _make_signal(
	person_id: String,
	kind: String,
	title: String,
	consequence: String,
	urgency: int,
	expires_hour: int,
	provenance: Array[Dictionary],
	invalidation: String,
	signal_key: String
) -> Dictionary:
	var signal_id: String = "situation:v2_3:%07d" % _next_signal_sequence
	_next_signal_sequence += 1
	return {
		"signal_id": signal_id,
		"signal_key": signal_key,
		"person_id": person_id,
		"kind": kind,
		"title_zh": title,
		"expected_consequence": consequence,
		"urgency": clampi(urgency, 0, 1000),
		"expires_hour": expires_hour,
		"expires_datetime": V2DateTime.iso_from_total_hour(expires_hour),
		"invalidation_condition": invalidation,
		"provenance": provenance.duplicate(true),
		"known_evidence": _knowledge_evidence(person_id, provenance),
		"cause_event_id": _latest_relevant_event_id(person_id),
	}


func _knowledge_evidence(
	person_id: String, provenance: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var records: Array[Dictionary] = _knowledge.records_for_person(person_id)
	for record: Dictionary in records:
		if result.size() >= 4:
			break
		if str(record.get("status", "")) == "outdated":
			continue
		result.append({
			"knowledge_id": str(record.get("knowledge_id", "")),
			"fact_type": str(record.get("fact_type", "")),
			"source_id": str(record.get("source_id", "")),
			"confidence": int(record.get("confidence", 0)),
		})
	if result.is_empty():
		for item: Dictionary in provenance:
			result.append({
				"knowledge_id": "",
				"fact_type": "direct_personal_state",
				"source_id": str(item.get("service", "")),
				"confidence": 1000,
			})
	return result


func _plan_npcs(current_hour: int) -> void:
	var date: String = V2DateTime.date_from_total_hour(current_hour)
	var person_ids: Array[String] = []
	for person_id_variant: Variant in _people.keys():
		var person_id: String = str(person_id_variant)
		if person_id != player_person_id:
			person_ids.append(person_id)
	person_ids.sort()
	for person_id: String in person_ids:
		if str(last_planned_dates.get(person_id, "")) == date:
			continue
		if not tasks_for(person_id).is_empty():
			last_planned_dates[person_id] = date
			continue
		var person_goals: Array[Dictionary] = goals_for(person_id)
		if person_goals.is_empty():
			continue
		var goal: Dictionary = _select_npc_goal(person_id, person_goals)
		var planning: Dictionary = _rules.get("planning", {}) as Dictionary
		var normal_interval: int = maxi(
			1, int(planning.get("npc_normal_action_interval_days", 3))
		)
		var absolute_day: int = floori(float(current_hour) / 24.0)
		var phase: int = _stable_roll(
			"%s|normal_action_phase" % person_id
		) % normal_interval
		if (
			str(goal.get("signal_key", "")) != "factory_delegate"
			and normal_interval > 1
			and absolute_day % normal_interval != phase
		):
			_remember_explanation(person_id, {
				"hour": current_hour,
				"goal_id": str(goal.get("goal_id", "")),
				"decision": "deferred",
				"reason": "普通社会行动按人物稳定相位错峰；高紧迫反应不受此限制",
				"next_review": current_hour + 24,
			})
			last_planned_dates[person_id] = date
			continue
		var candidates: Array[Dictionary] = methods_for(
			person_id, str(goal.get("goal_id", ""))
		)
		var method: Dictionary = _select_npc_method(
			person_id, goal, candidates, current_hour
		)
		if method.is_empty():
			_remember_explanation(person_id, {
				"hour": current_hour,
				"goal_id": str(goal.get("goal_id", "")),
				"decision": "no_method",
				"reason": "没有满足认知、对象和时间约束的方法",
				"failure_step": "method_selection",
			})
			last_planned_dates[person_id] = date
			continue
		var target_id: String = _resolve_target(person_id, "", method)
		var result: V2LifeLoopResult = submit_intent(
			person_id,
			str(goal.get("goal_id", "")),
			str(method.get("method_id", "")),
			target_id,
			"npc",
			{
				"current_hour": current_hour,
				"preparation": (
					1000
					if str(goal.get("signal_key", ""))
					== "factory_delegate"
					else 250 + _stable_roll(
						"%s|%s|preparation" % [person_id, date]
					) % 351
				),
			}
		)
		_remember_explanation(person_id, {
			"hour": current_hour,
			"goal_id": str(goal.get("goal_id", "")),
			"goal_reason": str(goal.get("title_zh", "")),
			"method_id": str(method.get("method_id", "")),
			"target_id": target_id,
			"decision": "scheduled" if result.success else "schedule_failed",
			"reason": result.user_message,
			"known": _known_evidence_for(person_id, goal),
			"unknown": "人物不能读取未被观察或传达的客观事件",
			"failure_step": "" if result.success else "schedule_reservation",
		})
		last_planned_dates[person_id] = date


func _select_npc_goal(
	person_id: String, candidates: Array[Dictionary]
) -> Dictionary:
	var selected: Dictionary = candidates.front()
	var best: int = -2147483648
	for goal: Dictionary in candidates:
		var utility: int = int(goal.get("urgency", 0))
		if str(goal.get("signal_key", "")) == "factory_delegate":
			utility += 500
		utility += _stable_roll(
			"%s|%s|goal" % [person_id, str(goal.get("signal_key", ""))]
		) % 101
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
	if str(goal.get("signal_key", "")) == "factory_delegate":
		for method: Dictionary in available:
			if str(method.get("method_id", "")) == "seek_position":
				return method
	var person: Dictionary = _people[person_id] as Dictionary
	var role: String = str(person.get("role", ""))
	var preferred_effects: PackedStringArray = PackedStringArray()
	if "工会" in role:
		preferred_effects = PackedStringArray([
			"promise_create", "organization_participation",
			"relationship_positive",
		])
	elif "事务员" in role:
		preferred_effects = PackedStringArray([
			"information", "relationship_positive", "evidence",
		])
	else:
		preferred_effects = PackedStringArray([
			"relationship_positive", "work_reputation", "persuasion",
		])
	var selected: Dictionary = {}
	var best: int = -2147483648
	for method: Dictionary in available:
		var utility: int = _method_utility(person_id, goal, method)
		if str(method.get("effect", "")) in preferred_effects:
			utility += 260
		if (
			"工会" in role
			and str(method.get("effect", "")) == "promise_create"
		):
			utility += 240
		if bool(method.get("illegal", false)):
			utility -= 350
		utility += _stable_roll("%s|%s|%d" % [
			person_id, str(method.get("method_id", "")), current_hour / 24,
		]) % 181
		if utility > best:
			best = utility
			selected = method
	return selected


func _method_utility(
	person_id: String, goal: Dictionary, method: Dictionary
) -> int:
	var score: int = int(method.get("base_score", 0))
	score -= int(method.get("risk", 0)) / 2
	if bool(method.get("illegal", false)):
		score -= 140
	if str(goal.get("kind", "")) == "threat":
		score += int(method.get("risk", 0)) / 5
	if str(goal.get("signal_key", "")) == "factory_delegate":
		if str(method.get("effect", "")) == "claim_position":
			score += 700
	var household: Dictionary = _households.household_for_person(person_id)
	var cash_cost: int = int(method.get("cash_cost_centimes", 0))
	if (
		cash_cost > 0
		and (
			household.is_empty()
			or int(household.get("cash_centimes", 0)) < cash_cost
		)
	):
		score -= 2000
	return score


func _reserve_schedule(
	task_id: String,
	actor_id: String,
	target_id: String,
	method: Dictionary,
	preferred_location_id: String,
	source: String,
	current_hour: int
) -> V2LifeLoopResult:
	var planning: Dictionary = _rules.get("planning", {}) as Dictionary
	var search_start: int = current_hour + int(
		planning.get("minimum_delay_hours", 1)
	)
	var search_end: int = search_start + int(
		planning.get("search_horizon_hours", 72)
	)
	var duration: int = clampi(
		int(method.get("duration_hours", 1)), 1, 12
	)
	for candidate: int in range(search_start, search_end):
		var embedded: Dictionary = _compatible_schedule_span(
			actor_id,
			target_id,
			candidate,
			duration,
			preferred_location_id
		)
		if embedded.is_empty():
			continue
		var activity_id: String = str(embedded.get("activity_id", ""))
		var task_ids: Array = (
			embedded.get("social_task_ids", []) as Array
		).duplicate()
		if task_id not in task_ids:
			task_ids.append(task_id)
		if not _schedule.merge_activity_metadata(
			actor_id, activity_id, {"social_task_ids": task_ids}
		):
			continue
		return V2LifeLoopResult.ok(
			"行动已嵌入现有权威日程",
			{
				"activity": embedded,
				"embedded": true,
				"location_id": str(embedded.get("location_id", "")),
			},
			[actor_id, activity_id, task_id]
		)
	var fallback_location: String = preferred_location_id
	if fallback_location.is_empty():
		fallback_location = str(
			_locations.position_for(actor_id).get(
				"current_location_id", ""
			)
		)
	var free_hour: int = _schedule.find_available_hour(
		actor_id, search_start, search_end, 6, 22, duration
	)
	if free_hour < 0:
		return V2LifeLoopResult.fail(
			"no_schedule_window",
			"未来 72 小时没有满足地点与日程约束的行动窗口",
			str(method.get("method_id", "")), [actor_id]
		)
	var result: V2LifeLoopResult
	if source == "player":
		result = _schedule.schedule_player_activity(
			actor_id,
			"social_action",
			free_hour,
			duration,
			current_hour,
			fallback_location,
			task_id,
			int(method.get("cash_cost_centimes", 0)),
			{"sandbox_task_id": task_id}
		)
	else:
		result = _schedule.schedule_rule_activity(
			actor_id,
			"social_action",
			free_hour,
			duration,
			fallback_location,
			"npc_rule",
			task_id,
			int(method.get("cash_cost_centimes", 0))
		)
	if not result.success:
		return result
	var activity: Dictionary = result.data.get("activity", {}) as Dictionary
	_schedule.merge_activity_metadata(
		actor_id,
		str(activity.get("activity_id", "")),
		{"social_task_ids": [task_id], "sandbox_task_id": task_id}
	)
	activity["social_task_ids"] = [task_id]
	activity["sandbox_task_id"] = task_id
	result.data["activity"] = activity
	result.data["embedded"] = false
	result.data["location_id"] = fallback_location
	return result


func _compatible_schedule_span(
	actor_id: String,
	target_id: String,
	start_hour: int,
	duration: int,
	preferred_location_id: String
) -> Dictionary:
	var first_activity: Dictionary = {}
	for offset: int in range(duration):
		var hour: int = start_hour + offset
		var activity: Dictionary = _schedule.activity_for_hour(actor_id, hour)
		if activity.is_empty():
			return {}
		if not (activity.get("social_task_ids", []) as Array).is_empty():
			return {}
		var activity_location: String = _normalize_location_id(
			str(activity.get("location_id", ""))
		)
		if (
			not preferred_location_id.is_empty()
			and activity_location != preferred_location_id
		):
			return {}
		if not target_id.is_empty():
			var target_activity: Dictionary = _schedule.activity_for_hour(
				target_id, hour
			)
			if (
				target_activity.is_empty()
				or _normalize_location_id(str(
					target_activity.get("location_id", "")
				)) != activity_location
			):
				return {}
		if offset == 0:
			first_activity = activity.duplicate(true)
		elif str(activity.get("activity_id", "")) != str(
			first_activity.get("activity_id", "")
		):
			return {}
	if first_activity.is_empty():
		return {}
	first_activity["start_hour"] = start_hour
	first_activity["end_hour"] = start_hour + duration
	first_activity["location_id"] = _normalize_location_id(str(
		first_activity.get("location_id", "")
	))
	return first_activity


func _due_tasks(current_hour: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_task: Variant in tasks.values():
		var task: Dictionary = raw_task as Dictionary
		if (
			str(task.get("status", "")) == "scheduled"
			and int(task.get("end_hour", -1)) == current_hour
		):
			result.append(task.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("task_id", "")) < str(right.get("task_id", ""))
	)
	return result


func _resolve_batch(
	due_tasks: Array[Dictionary], current_hour: int
) -> Dictionary:
	if due_tasks.is_empty():
		return {"committed_events": 0, "rolled_back": false}
	var proposals: Array[Dictionary] = []
	for task: Dictionary in due_tasks:
		proposals.append(_prepare_proposal(task, current_hour))
	proposals.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score: int = int(left.get("outcome_score", 0))
		var right_score: int = int(right.get("outcome_score", 0))
		if left_score != right_score:
			return left_score > right_score
		return str(left.get("task_id", "")) < str(
			right.get("task_id", "")
		)
	)
	var conflict_winners: Dictionary = {}
	for index: int in range(proposals.size()):
		var proposal: Dictionary = proposals[index]
		if (
			not bool(proposal.get("prepared", false))
			or not bool(proposal.get("success", false))
		):
			continue
		var proposal_task: Dictionary = proposal.get("task", {}) as Dictionary
		var conflict_keys: Array[String] = [
			"person:%s:%d:%d" % [
				str(proposal_task.get("actor_id", "")),
				int(proposal_task.get("start_hour", -1)),
				int(proposal_task.get("end_hour", -1)),
			],
		]
		var method_conflict_key: String = str(
			proposal.get("conflict_key", "")
		)
		if not method_conflict_key.is_empty():
			conflict_keys.append("unique:%s" % method_conflict_key)
		var conflicting_key: String = ""
		for conflict_key: String in conflict_keys:
			if conflict_winners.has(conflict_key):
				conflicting_key = conflict_key
				break
		if not conflicting_key.is_empty():
			proposal["prepared"] = false
			proposal["success"] = false
			proposal["failure_step"] = "conflict_resolution"
			proposal["failure_reason"] = "同一结算批次的唯一资源竞争失败"
			proposal["conflict_winner_task_id"] = str(
				conflict_winners[conflicting_key]
			)
			proposals[index] = proposal
		else:
			for conflict_key: String in conflict_keys:
				conflict_winners[conflict_key] = str(
					proposal.get("task_id", "")
				)
	var authority_before: Dictionary = _authority_snapshot()
	var own_before: Dictionary = _sandbox_commit_snapshot()
	var committed_events: Array[Dictionary] = []
	for proposal: Dictionary in proposals:
		var commit_result: V2LifeLoopResult = _commit_proposal(
			proposal, current_hour
		)
		if not commit_result.success:
			_restore_authority(authority_before)
			_restore_sandbox_commit_snapshot(own_before)
			for task: Dictionary in due_tasks:
				var task_id: String = str(task.get("task_id", ""))
				if tasks.has(task_id):
					var stored: Dictionary = tasks[task_id] as Dictionary
					stored["status"] = "failed"
					stored["failure_step"] = "atomic_commit"
					stored["failure_reason"] = commit_result.user_message
					tasks[task_id] = stored
			return {
				"committed_events": 0,
				"rolled_back": true,
				"error": commit_result.user_message,
			}
		var event: Dictionary = commit_result.data.get(
			"event", {}
		) as Dictionary
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
		"rolled_back": false,
	}


func _prepare_proposal(
	task: Dictionary, current_hour: int
) -> Dictionary:
	var task_id: String = str(task.get("task_id", ""))
	var actor_id: String = str(task.get("actor_id", ""))
	var method: Dictionary = method_record(str(task.get("method_id", "")))
	var proposal: Dictionary = {
		"task_id": task_id,
		"task": task.duplicate(true),
		"method": method,
		"prepared": true,
		"success": false,
		"failure_step": "",
		"failure_reason": "",
		"conflict_key": str(method.get("conflict_key", "")),
		"phase": PHASE_PREPARE,
	}
	if method.is_empty():
		proposal["prepared"] = false
		proposal["failure_step"] = "method_lookup"
		proposal["failure_reason"] = "方法规则不存在"
		return proposal
	var schedule_activity: Dictionary = _schedule_activity(
		actor_id, str(task.get("schedule_activity_id", ""))
	)
	if schedule_activity.is_empty():
		proposal["prepared"] = false
		proposal["failure_step"] = "schedule_verification"
		proposal["failure_reason"] = "关联日程活动不存在"
		return proposal
	if str(schedule_activity.get("status", "")) not in [
		"completed", "active",
	]:
		proposal["prepared"] = false
		proposal["failure_step"] = "schedule_verification"
		proposal["failure_reason"] = "关联日程未实际完成"
		return proposal
	var actor_position: Dictionary = _locations.position_for(actor_id)
	var location_id: String = str(task.get("location_id", ""))
	if (
		str(actor_position.get("location_state", "")) != "at_location"
		or str(actor_position.get("current_location_id", "")) != location_id
	):
		proposal["prepared"] = false
		proposal["failure_step"] = "location_verification"
		proposal["failure_reason"] = "人物结算时不在任务地点"
		return proposal
	var target_id: String = str(task.get("target_id", ""))
	if not target_id.is_empty():
		var target_position: Dictionary = _locations.position_for(target_id)
		if (
			str(target_position.get("location_state", "")) != "at_location"
			or str(target_position.get("current_location_id", ""))
			!= location_id
		):
			proposal["prepared"] = false
			proposal["failure_step"] = "target_verification"
			proposal["failure_reason"] = "行动对象没有实际到场"
			return proposal
	var cash_cost: int = int(method.get("cash_cost_centimes", 0))
	if cash_cost > 0:
		var household: Dictionary = _households.household_for_person(actor_id)
		if (
			household.is_empty()
			or int(household.get("cash_centimes", 0)) < cash_cost
		):
			proposal["prepared"] = false
			proposal["failure_step"] = "resource_verification"
			proposal["failure_reason"] = "权威住户现金不足"
			return proposal
	var preparation: int = int(task.get("preparation", 0))
	var threshold: int = clampi(
		int(method.get("base_score", 500))
		+ preparation / 4
		+ _relationship_modifier(actor_id, target_id)
		+ _organization_modifier(
			actor_id, str(task.get("organization_id", ""))
		),
		50,
		1000
	)
	var roll: int = _stable_roll("%s|%s|%d|outcome" % [
		task_id, str(method.get("method_id", "")), current_hour,
	])
	var guaranteed: bool = (
		preparation >= 1000
		and (
			cash_cost == 0
			or int(_households.household_for_person(actor_id).get(
				"cash_centimes", 0
			)) >= cash_cost
		)
	)
	proposal["threshold"] = threshold
	proposal["roll"] = roll
	proposal["outcome_score"] = threshold - roll
	proposal["success"] = guaranteed or roll < threshold
	proposal["guaranteed_success"] = guaranteed
	if not bool(proposal["success"]):
		proposal["failure_step"] = "outcome_resolution"
		proposal["failure_reason"] = "方法已尝试，但结果检定未成功"
	var risk: int = int(method.get("risk", 0))
	proposal["discovered"] = (
		bool(method.get("illegal", false))
		and _stable_roll("%s|%d|discovery" % [task_id, current_hour])
		< risk
	)
	return proposal


func _commit_proposal(
	proposal: Dictionary, current_hour: int
) -> V2LifeLoopResult:
	if fail_next_commit_for_test:
		fail_next_commit_for_test = false
		return V2LifeLoopResult.fail(
			"injected_commit_failure",
			"测试注入的提交失败"
		)
	var task_id: String = str(proposal.get("task_id", ""))
	if not tasks.has(task_id):
		return V2LifeLoopResult.fail(
			"task_missing_at_commit", "提交时任务不存在", task_id
		)
	var task: Dictionary = tasks[task_id] as Dictionary
	var method: Dictionary = proposal.get("method", {}) as Dictionary
	var success: bool = (
		bool(proposal.get("prepared", false))
		and bool(proposal.get("success", false))
	)
	var event_id: String = "social_event:v2_3:%07d" % _next_event_sequence
	var effect_result := V2LifeLoopResult.ok("行动未产生领域变化")
	if success:
		effect_result = _apply_effect(
			task, method, event_id, current_hour,
			bool(proposal.get("discovered", false))
		)
		if not effect_result.success:
			return effect_result
	_next_event_sequence += 1
	task["status"] = "completed" if success else "failed"
	task["resolved_hour"] = current_hour
	task["failure_step"] = str(proposal.get("failure_step", ""))
	task["failure_reason"] = str(proposal.get("failure_reason", ""))
	task["result_event_id"] = event_id
	tasks[task_id] = task
	var intent_id: String = str(task.get("intent_id", ""))
	if intents.has(intent_id):
		var intent: Dictionary = intents[intent_id] as Dictionary
		intent["status"] = "completed" if success else "failed"
		intent["result_event_id"] = event_id
		intents[intent_id] = intent
	var event: Dictionary = {
		"event_id": event_id,
		"world_hour": current_hour,
		"datetime": V2DateTime.iso_from_total_hour(current_hour),
		"phase": PHASE_COMMIT,
		"sequence": _next_event_sequence - 1,
		"event_type": "social_action_resolved",
		"task_id": task_id,
		"intent_id": intent_id,
		"goal_id": str(task.get("goal_id", "")),
		"method_id": str(task.get("method_id", "")),
		"actor_id": str(task.get("actor_id", "")),
		"target_id": str(task.get("target_id", "")),
		"source": str(task.get("source", "")),
		"organization_id": str(task.get("organization_id", "")),
		"location_id": str(task.get("location_id", "")),
		"success": success,
		"attempted": true,
		"illegal": bool(method.get("illegal", false)),
		"discovered": bool(proposal.get("discovered", false)),
		"failure_step": str(proposal.get("failure_step", "")),
		"failure_reason": str(proposal.get("failure_reason", "")),
		"outcome_roll": int(proposal.get("roll", -1)),
		"outcome_threshold": int(proposal.get("threshold", -1)),
		"guaranteed_success": bool(
			proposal.get("guaranteed_success", false)
		),
		"effects": effect_result.data.duplicate(true),
		"cause_event_id": str(task.get("cause_event_id", "")),
		"ordering_key": "%012d|%02d|%09d" % [
			current_hour, PHASE_COMMIT, _next_event_sequence - 1,
		],
	}
	event_ledger.append(event)
	return V2LifeLoopResult.ok(
		"社会行动事件已原子提交",
		{"event": event.duplicate(true)},
		[str(task.get("actor_id", "")), task_id, event_id]
	)


func _apply_effect(
	task: Dictionary,
	method: Dictionary,
	event_id: String,
	current_hour: int,
	discovered: bool
) -> V2LifeLoopResult:
	var effect: String = str(method.get("effect", ""))
	var actor_id: String = str(task.get("actor_id", ""))
	var target_id: String = str(task.get("target_id", ""))
	var organization_id: String = str(task.get("organization_id", ""))
	match effect:
		"work_reputation":
			if organization_id.is_empty():
				organization_id = _work_organization_for(actor_id)
			if not organization_id.is_empty():
				return _organizations.adjust_participation(
					actor_id, organization_id, 12, current_hour, event_id
				)
			return V2LifeLoopResult.ok(
				"可靠工作已完成", {"reputation_delta": 0}
			)
		"earn_cash":
			var household_id: String = (
				_households.household_id_for_person(actor_id)
			)
			if household_id.is_empty():
				return V2LifeLoopResult.fail(
					"household_required",
					"临时收入必须进入现有住户账本"
				)
			return _ledger.post(
				_households.households,
				household_id,
				actor_id,
				120,
				"income",
				"temporary_work",
				current_hour,
				str(task.get("location_id", "")),
				event_id,
				"sandbox:%s:income" % event_id,
				"社会沙盒临时工作收入"
			)
		"employment_exit":
			return _employment.change_contract_status(
				actor_id, "resigned", current_hour, event_id
			)
		"relationship_positive":
			return _apply_relationship_effect(
				actor_id, target_id, "cooperation", event_id, current_hour
			)
		"relationship_negative":
			return _apply_relationship_effect(
				actor_id, target_id, "threat", event_id, current_hour
			)
		"persuasion":
			return _apply_relationship_effect(
				actor_id, target_id, "persuasion_success",
				event_id, current_hour
			)
		"coercion":
			var charge: V2LifeLoopResult = _charge_method_cost(
				task, method, event_id, current_hour
			)
			if not charge.success:
				return charge
			return _apply_relationship_effect(
				actor_id, target_id, "threat", event_id, current_hour
			)
		"deception":
			if discovered:
				return _apply_relationship_effect(
					actor_id, target_id, "deception_exposed",
					event_id, current_hour
				)
			return _new_evidence(
				actor_id, target_id, "concealed_deception",
				event_id, current_hour, true
			)
		"promise_create":
			return _create_commitment(
				actor_id, target_id, event_id, current_hour
			)
		"promise_kept":
			return _settle_commitment(
				actor_id, target_id, event_id, current_hour
			)
		"information":
			return _new_evidence(
				actor_id,
				target_id if not target_id.is_empty() else organization_id,
				"verified_information",
				event_id,
				current_hour,
				false
			)
		"evidence":
			return _new_evidence(
				actor_id,
				target_id if not target_id.is_empty() else organization_id,
				"material_evidence",
				event_id,
				current_hour,
				bool(method.get("illegal", false))
			)
		"hide_evidence":
			return _hide_evidence(actor_id, event_id, current_hour)
		"forge_evidence":
			return _new_evidence(
				actor_id, organization_id, "forged_document",
				event_id, current_hour, true
			)
		"rumor":
			return _new_evidence(
				actor_id,
				target_id if not target_id.is_empty() else organization_id,
				"reported_rumor",
				event_id,
				current_hour,
				bool(method.get("illegal", false))
			)
		"alliance":
			var alliance_relation: V2LifeLoopResult = (
				_apply_relationship_effect(
					actor_id, target_id, "cooperation",
					event_id, current_hour
				)
			)
			if not alliance_relation.success:
				return alliance_relation
			return _create_commitment(
				actor_id, target_id, event_id, current_hour
			)
		"join_organization":
			return _organizations.join(
				actor_id, organization_id, current_hour, event_id
			)
		"leave_organization":
			return _organizations.leave_organization(
				actor_id, organization_id, current_hour, event_id
			)
		"claim_position":
			return _organizations.claim_position(
				actor_id,
				str(method.get(
					"conflict_key",
					"factory_fives_workgroup_three:delegate"
				)),
				current_hour,
				event_id
			)
		"organization_participation":
			return _organizations.adjust_participation(
				actor_id, organization_id, 20, current_hour, event_id
			)
		"sabotage":
			var sabotage_relation: V2LifeLoopResult = (
				_apply_relationship_effect(
					actor_id, target_id, "threat", event_id, current_hour
				)
			)
			if not sabotage_relation.success:
				return sabotage_relation
			return _new_evidence(
				actor_id, target_id, "sabotage_trace",
				event_id, current_hour, true
			)
	return V2LifeLoopResult.ok(
		"方法没有额外领域后果", {"effect": effect}
	)


func _apply_relationship_effect(
	actor_id: String,
	target_id: String,
	interaction_type: String,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	if target_id.is_empty():
		return V2LifeLoopResult.fail(
			"relationship_target_required", "关系后果缺少对象"
		)
	if not _relationships.has_relationship(actor_id, target_id):
		var create: V2LifeLoopResult = _relationships.create_relationship(
			actor_id,
			target_id,
			"co_located_acquaintance",
			["face_to_face", "local_letter"]
		)
		if not create.success:
			return create
	return _relationships.apply_interaction(
		actor_id,
		target_id,
		interaction_type,
		event_id,
		current_hour,
		"社会沙盒客观事件 %s" % event_id
	)


func _charge_method_cost(
	task: Dictionary,
	method: Dictionary,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	var amount: int = int(method.get("cash_cost_centimes", 0))
	if amount <= 0:
		return V2LifeLoopResult.ok("方法无需现金")
	var actor_id: String = str(task.get("actor_id", ""))
	var household_id: String = _households.household_id_for_person(actor_id)
	if household_id.is_empty():
		return V2LifeLoopResult.fail(
			"household_required", "现金后果必须进入现有住户账本"
		)
	return _ledger.post(
		_households.households,
		household_id,
		actor_id,
		amount,
		"expense",
		"social_action",
		current_hour,
		str(task.get("target_id", "")),
		event_id,
		"sandbox:%s:cost" % event_id,
		"社会行动支出"
	)


func _create_commitment(
	actor_id: String,
	target_id: String,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
	if target_id.is_empty():
		return V2LifeLoopResult.fail(
			"commitment_target_required", "承诺必须有对象"
		)
	var commitment_id: String = (
		"commitment:v2_3:%07d" % _next_commitment_sequence
	)
	_next_commitment_sequence += 1
	var commitment: Dictionary = {
		"commitment_id": commitment_id,
		"promisor_id": actor_id,
		"beneficiary_id": target_id,
		"status": "open",
		"created_event_id": event_id,
		"created_hour": current_hour,
		"due_hour": current_hour + 7 * 24,
	}
	commitments[commitment_id] = commitment
	return V2LifeLoopResult.ok(
		"承诺已建立",
		{"commitment": commitment.duplicate(true)},
		[actor_id, target_id, commitment_id]
	)


func _settle_commitment(
	actor_id: String,
	target_id: String,
	event_id: String,
	current_hour: int
) -> V2LifeLoopResult:
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
	if candidate_ids.is_empty():
		return _create_commitment(
			actor_id, target_id, event_id, current_hour
		)
	var commitment_id: String = candidate_ids.front()
	var commitment: Dictionary = commitments[commitment_id] as Dictionary
	commitment["status"] = "kept"
	commitment["settled_event_id"] = event_id
	commitment["settled_hour"] = current_hour
	commitments[commitment_id] = commitment
	var relation: V2LifeLoopResult = _apply_relationship_effect(
		actor_id, str(commitment.get("beneficiary_id", "")),
		"promise_kept", event_id, current_hour
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


func _new_evidence(
	owner_id: String,
	subject_id: String,
	evidence_type: String,
	event_id: String,
	current_hour: int,
	illegal_origin: bool
) -> V2LifeLoopResult:
	var evidence_id: String = "evidence:v2_3:%07d" % _next_evidence_sequence
	_next_evidence_sequence += 1
	var evidence: Dictionary = {
		"evidence_id": evidence_id,
		"owner_id": owner_id,
		"subject_id": subject_id if not subject_id.is_empty() else owner_id,
		"evidence_type": evidence_type,
		"status": "held",
		"created_event_id": event_id,
		"created_hour": current_hour,
		"illegal_origin": illegal_origin,
	}
	evidence_records[evidence_id] = evidence
	return V2LifeLoopResult.ok(
		"证据记录已建立",
		{"evidence": evidence.duplicate(true)},
		[owner_id, evidence_id]
	)


func _hide_evidence(
	owner_id: String, event_id: String, current_hour: int
) -> V2LifeLoopResult:
	var candidate_ids: Array[String] = []
	for evidence_id_variant: Variant in evidence_records.keys():
		var evidence_id: String = str(evidence_id_variant)
		var evidence: Dictionary = evidence_records[evidence_id] as Dictionary
		if (
			str(evidence.get("owner_id", "")) == owner_id
			and str(evidence.get("status", "")) == "held"
		):
			candidate_ids.append(evidence_id)
	candidate_ids.sort()
	if candidate_ids.is_empty():
		return V2LifeLoopResult.fail(
			"no_evidence_to_hide", "人物没有可隐藏的证据"
		)
	var evidence_id: String = candidate_ids.front()
	var evidence: Dictionary = evidence_records[evidence_id] as Dictionary
	evidence["status"] = "hidden"
	evidence["hidden_event_id"] = event_id
	evidence["hidden_hour"] = current_hour
	evidence_records[evidence_id] = evidence
	return V2LifeLoopResult.ok(
		"证据已被隐藏", {"evidence": evidence.duplicate(true)},
		[owner_id, evidence_id]
	)


func _publish_perceptions(event: Dictionary, current_hour: int) -> void:
	var observers: Array[String] = _event_observers(event)
	var event_id: String = str(event.get("event_id", ""))
	var actor_id: String = str(event.get("actor_id", ""))
	var target_id: String = str(event.get("target_id", ""))
	for observer_id: String in observers:
		var direct: bool = observer_id in [actor_id, target_id]
		var illegal_hidden: bool = (
			bool(event.get("illegal", false))
			and not bool(event.get("discovered", false))
			and not direct
		)
		if illegal_hidden:
			continue
		_knowledge.record_fact(
			observer_id,
			"social_event_fact:%s" % event_id,
			event_id,
			"social_event",
			{
				"actor_id": actor_id,
				"target_id": target_id,
				"method_id": str(event.get("method_id", "")),
				"success": bool(event.get("success", false)),
				"illegal": bool(event.get("illegal", false))
				and bool(event.get("discovered", false)),
			},
			event_id,
			"direct_observation" if direct else "witness",
			current_hour,
			1000 if direct else 720,
			"confirmed" if direct else "reported",
			current_hour + 30 * 24,
			"",
			"knowledge:%s:event:%s" % [observer_id, event_id]
		)


func _event_observers(event: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id_value: String in [
		str(event.get("actor_id", "")),
		str(event.get("target_id", "")),
	]:
		if not id_value.is_empty() and id_value not in result:
			result.append(id_value)
	var location_id: String = str(event.get("location_id", ""))
	var person_ids: Array[String] = []
	for person_id_variant: Variant in _people.keys():
		person_ids.append(str(person_id_variant))
	person_ids.sort()
	for person_id: String in person_ids:
		var position: Dictionary = _locations.position_for(person_id)
		if (
			str(position.get("location_state", "")) == "at_location"
			and str(position.get("current_location_id", "")) == location_id
			and person_id not in result
		):
			result.append(person_id)
	return result


func _queue_reaction(event: Dictionary, current_hour: int) -> void:
	var target_id: String = str(event.get("target_id", ""))
	if (
		target_id.is_empty()
		or not _people.has(target_id)
		or (
			bool(event.get("success", false))
			and str(method_record(str(event.get(
				"method_id", ""
			))).get("effect", "")) not in NEGATIVE_EFFECTS
		)
	):
		return
	var delay: int = int(
		(_rules.get("planning", {}) as Dictionary).get(
			"reaction_delay_hours", 2
		)
	)
	pending_reactions.append({
		"reaction_id": "reaction:%s:%s" % [
			str(event.get("event_id", "")), target_id,
		],
		"person_id": target_id,
		"source_event_id": str(event.get("event_id", "")),
		"due_hour": current_hour + delay,
		"status": "pending",
	})


func _process_due_reactions(current_hour: int) -> int:
	var processed: int = 0
	var due: Array[Dictionary] = []
	for raw_reaction: Variant in pending_reactions:
		var reaction: Dictionary = raw_reaction as Dictionary
		if (
			str(reaction.get("status", "")) == "pending"
			and int(reaction.get("due_hour", -1)) <= current_hour
		):
			due.append(reaction)
	due.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("reaction_id", "")) < str(
			right.get("reaction_id", "")
		)
	)
	for due_reaction: Dictionary in due:
		var person_id: String = str(due_reaction.get("person_id", ""))
		_dirty_people[person_id] = true
		reevaluate_dirty(current_hour)
		var person_goals: Array[Dictionary] = goals_for(person_id)
		if person_goals.is_empty():
			_set_reaction_status(
				str(due_reaction.get("reaction_id", "")), "no_goal"
			)
			continue
		var goal: Dictionary = person_goals.front()
		var method_id: String = "investigate"
		var source_event: Dictionary = _event_by_id(str(
			due_reaction.get("source_event_id", "")
		))
		var actor_id: String = str(source_event.get("actor_id", ""))
		if (
			_relationships.has_relationship(person_id, actor_id)
			and str(goal.get("kind", "")) != "opportunity"
		):
			method_id = "refuse_request"
		var result: V2LifeLoopResult = submit_intent(
			person_id,
			str(goal.get("goal_id", "")),
			method_id,
			actor_id,
			"reaction",
			{
				"current_hour": current_hour,
				"cause_event_id": str(
					due_reaction.get("source_event_id", "")
				),
				"preparation": 300,
			}
		)
		_set_reaction_status(
			str(due_reaction.get("reaction_id", "")),
			"scheduled" if result.success else "failed"
		)
		processed += 1
	return processed


func _set_reaction_status(reaction_id: String, status: String) -> void:
	for index: int in range(pending_reactions.size()):
		var reaction: Dictionary = pending_reactions[index]
		if str(reaction.get("reaction_id", "")) == reaction_id:
			reaction["status"] = status
			pending_reactions[index] = reaction
			return


func _authority_snapshot() -> Dictionary:
	return {
		"relationships": _relationships.get_persistent_state(),
		"organizations": _organizations.get_persistent_state(),
		"households": _households.get_persistent_state(),
		"ledger": _ledger.get_persistent_state(),
		"employment": _employment.get_persistent_state(),
	}


func _restore_authority(snapshot: Dictionary) -> bool:
	return (
		_relationships.restore_persistent_state(
			snapshot.get("relationships", {}) as Dictionary
		)
		and _organizations.restore_persistent_state(
			snapshot.get("organizations", {}) as Dictionary
		)
		and _households.restore_persistent_state(
			snapshot.get("households", {}) as Dictionary
		)
		and _ledger.restore_persistent_state(
			snapshot.get("ledger", {}) as Dictionary
		)
		and _employment.restore_persistent_state(
			snapshot.get("employment", {}) as Dictionary
		)
	)


func _sandbox_commit_snapshot() -> Dictionary:
	# Commit never mutates situations, goals, explanations, reactions or
	# planning dates. Copying the full append-only ledger for every daily
	# action would make a year run quadratic, so retain only the fields the
	# commit phase can actually touch plus the prior ledger length.
	return {
		"tasks": tasks.duplicate(true),
		"intents": intents.duplicate(true),
		"commitments": commitments.duplicate(true),
		"evidence_records": evidence_records.duplicate(true),
		"event_count": event_ledger.size(),
		"next_event_sequence": _next_event_sequence,
		"next_commitment_sequence": _next_commitment_sequence,
		"next_evidence_sequence": _next_evidence_sequence,
	}


func _restore_sandbox_commit_snapshot(snapshot: Dictionary) -> void:
	tasks = (snapshot.get("tasks", {}) as Dictionary).duplicate(true)
	intents = (snapshot.get("intents", {}) as Dictionary).duplicate(true)
	commitments = (
		snapshot.get("commitments", {}) as Dictionary
	).duplicate(true)
	evidence_records = (
		snapshot.get("evidence_records", {}) as Dictionary
	).duplicate(true)
	var event_count: int = int(snapshot.get("event_count", 0))
	while event_ledger.size() > event_count:
		event_ledger.pop_back()
	_next_event_sequence = int(snapshot.get("next_event_sequence", 1))
	_next_commitment_sequence = int(
		snapshot.get("next_commitment_sequence", 1)
	)
	_next_evidence_sequence = int(
		snapshot.get("next_evidence_sequence", 1)
	)


func _resolve_target(
	actor_id: String, requested_target_id: String, method: Dictionary
) -> String:
	if (
		not requested_target_id.is_empty()
		and requested_target_id != actor_id
		and _people.has(requested_target_id)
		and _knowledge.knows_person(actor_id, requested_target_id)
	):
		return requested_target_id
	if not _method_requires_target(method):
		return ""
	var candidates: Array[String] = []
	for target_id_variant: Variant in _people.keys():
		var target_id: String = str(target_id_variant)
		if target_id == actor_id:
			continue
		if _knowledge.knows_person(actor_id, target_id):
			candidates.append(target_id)
	candidates.sort()
	if candidates.is_empty():
		return ""
	var index: int = _stable_roll("%s|%s|target" % [
		actor_id, str(method.get("method_id", "")),
	]) % candidates.size()
	return candidates[index]


func _resolve_organization(
	actor_id: String,
	goal: Dictionary,
	method: Dictionary,
	options: Dictionary
) -> String:
	var requested: String = str(options.get("organization_id", ""))
	if (
		not requested.is_empty()
		and not _organizations.organization(requested).is_empty()
	):
		return requested
	if str(method.get("effect", "")) == "claim_position":
		return "factory_fives_workgroup_three"
	var memberships: Array[Dictionary] = (
		_organizations.memberships_for_person(actor_id)
	)
	for membership: Dictionary in memberships:
		if str(membership.get("status", "active")) == "active":
			return str(membership.get("organization_id", ""))
	if str(goal.get("signal_key", "")) == "factory_delegate":
		return "factory_fives_workgroup_three"
	return ""


func _resolve_method_location(
	actor_id: String,
	target_id: String,
	organization_id: String,
	method: Dictionary
) -> String:
	var kind: String = str(method.get("location_kind", "public"))
	if kind == "workplace":
		return str((_people[actor_id] as Dictionary).get(
			"workplace_location_id", ""
		))
	if kind == "organization":
		var organization: Dictionary = _organizations.organization(
			organization_id
		)
		return str(organization.get("location_id", ""))
	if kind == "target" and not target_id.is_empty():
		# The shared place is selected from both authoritative future
		# schedules. Using the target's present location would reject
		# coworkers who will meet at their workplace.
		return ""
	return str(_locations.position_for(actor_id).get(
		"current_location_id", ""
	))


func _method_requires_target(method: Dictionary) -> bool:
	return str(method.get("location_kind", "")) == "target" or str(
		method.get("effect", "")
	) in [
		"relationship_positive", "relationship_negative", "persuasion",
		"coercion", "deception", "promise_create", "promise_kept",
		"alliance", "sabotage",
	]


func _relationship_modifier(actor_id: String, target_id: String) -> int:
	if target_id.is_empty():
		return 0
	var relation: Dictionary = _relationships.get_relationship(
		actor_id, target_id
	)
	return (
		int(relation.get("trust", 0)) / 5
		+ int(relation.get("familiarity", 0)) / 10
		- int(relation.get("tension", 0)) / 4
	)


func _organization_modifier(
	actor_id: String, organization_id: String
) -> int:
	if organization_id.is_empty():
		return 0
	var membership: Dictionary = _organizations.get_membership(
		actor_id, organization_id
	)
	return int(membership.get("participation", 0)) / 5


func _work_organization_for(person_id: String) -> String:
	for membership: Dictionary in (
		_organizations.memberships_for_person(person_id)
	):
		var organization_id: String = str(
			membership.get("organization_id", "")
		)
		var organization: Dictionary = _organizations.organization(
			organization_id
		)
		if str(organization.get("organization_type", "")) in [
			"enterprise", "government",
		]:
			return organization_id
	return ""


func _same_active_organization(first_id: String, second_id: String) -> bool:
	for membership: Dictionary in (
		_organizations.memberships_for_person(first_id)
	):
		var organization_id: String = str(
			membership.get("organization_id", "")
		)
		if (
			str(membership.get("status", "active")) == "active"
			and _organizations.is_active_member(second_id, organization_id)
		):
			return true
	return false


func _goal_by_id(person_id: String, goal_id: String) -> Dictionary:
	for goal: Dictionary in goals_for(person_id):
		if str(goal.get("goal_id", "")) == goal_id:
			return goal
	return {}


func _schedule_activity(person_id: String, activity_id: String) -> Dictionary:
	for raw_activity: Variant in (
		_schedule.schedules.get(person_id, []) as Array
	):
		var activity: Dictionary = raw_activity as Dictionary
		if str(activity.get("activity_id", "")) == activity_id:
			return activity.duplicate(true)
	for activity: Dictionary in _schedule.recent_completed_activities:
		if (
			str(activity.get("person_id", "")) == person_id
			and str(activity.get("activity_id", "")) == activity_id
		):
			return activity.duplicate(true)
	return {}


func _latest_relevant_event_id(person_id: String) -> String:
	for index: int in range(event_ledger.size() - 1, -1, -1):
		var event: Dictionary = event_ledger[index]
		if person_id in [
			str(event.get("actor_id", "")),
			str(event.get("target_id", "")),
		]:
			return str(event.get("event_id", ""))
	return ""


func _known_evidence_for(
	person_id: String, goal: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_evidence: Variant in goal.get("known_evidence", []) as Array:
		if raw_evidence is Dictionary:
			var evidence: Dictionary = raw_evidence as Dictionary
			var knowledge_id: String = str(
				evidence.get("knowledge_id", "")
			)
			if (
				knowledge_id.is_empty()
				or not _knowledge.get_record(knowledge_id).is_empty()
			):
				result.append(evidence.duplicate(true))
	return result


func _event_by_id(event_id: String) -> Dictionary:
	for event: Dictionary in event_ledger:
		if str(event.get("event_id", "")) == event_id:
			return event.duplicate(true)
	return {}


func _method_consequence(method: Dictionary) -> String:
	var effect: String = str(method.get("effect", ""))
	var risk: int = int(method.get("risk", 0))
	var illegal: bool = bool(method.get("illegal", false))
	return "%s；风险 %d%s" % [
		effect,
		risk,
		"；违法但允许尝试，可能留下证据" if illegal else "",
	]


func _remember_explanation(person_id: String, record: Dictionary) -> void:
	var history: Array = decision_explanations.get(person_id, []) as Array
	history.append(record.duplicate(true))
	var limit: int = int(
		(_rules.get("limits", {}) as Dictionary).get(
			"explanations_per_person", 16
		)
	)
	while history.size() > limit:
		history.pop_front()
	decision_explanations[person_id] = history


func _prune() -> void:
	var limits: Dictionary = _rules.get("limits", {}) as Dictionary
	while event_ledger.size() > int(limits.get("events", 1024)):
		event_ledger.pop_front()
	_trim_dictionary_by_sequence(
		tasks, int(limits.get("tasks", 256)), "task_id",
		PackedStringArray(["completed", "failed", "cancelled"])
	)
	_trim_dictionary_by_sequence(
		intents, int(limits.get("intents", 256)), "intent_id",
		PackedStringArray([
			"completed", "failed", "rejected", "cancelled",
		])
	)
	_trim_dictionary_by_sequence(
		commitments, int(limits.get("commitments", 128)),
		"commitment_id", PackedStringArray(["kept", "broken", "cancelled"])
	)
	_trim_dictionary_by_sequence(
		evidence_records, int(limits.get("evidence", 128)),
		"evidence_id", PackedStringArray(["hidden", "destroyed", "released"])
	)
	while pending_reactions.size() > int(limits.get("reactions", 128)):
		pending_reactions.pop_front()


func _trim_dictionary_by_sequence(
	records: Dictionary,
	limit: int,
	id_field: String,
	terminal_statuses: PackedStringArray
) -> void:
	if records.size() <= limit:
		return
	var ids: Array[String] = []
	for record_id_variant: Variant in records.keys():
		ids.append(str(record_id_variant))
	ids.sort()
	for record_id: String in ids:
		if records.size() <= limit:
			break
		var record: Dictionary = records[record_id] as Dictionary
		if (
			str(record.get("status", "")) in terminal_statuses
			and str(record.get(id_field, "")) == record_id
		):
			records.erase(record_id)


func _reset_runtime_state() -> void:
	situations.clear()
	goals.clear()
	intents.clear()
	tasks.clear()
	event_ledger.clear()
	commitments.clear()
	evidence_records.clear()
	pending_reactions.clear()
	decision_explanations.clear()
	last_planned_dates.clear()
	_dirty_people.clear()
	_next_signal_sequence = 1
	_next_goal_sequence = 1
	_next_intent_sequence = 1
	_next_task_sequence = 1
	_next_event_sequence = 1
	_next_commitment_sequence = 1
	_next_evidence_sequence = 1
	_last_processed_hour = -1
	fail_next_commit_for_test = false


func _normalize_location_id(location_id: String) -> String:
	return str(V23LifeLoopSimulation.LOCATION_ALIASES.get(
		location_id, location_id
	))


func _event_order_key(event: Dictionary) -> String:
	return "%012d|%02d|%09d" % [
		int(event.get("world_hour", -1)),
		int(event.get("phase", -1)),
		int(event.get("sequence", -1)),
	]


static func _stable_roll(key: String) -> int:
	return int(key.sha256_text().left(8).hex_to_int() & 0x7fffffff) % 1000


static func _dictionary_array_copy(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_item: Variant in source:
		if raw_item is Dictionary:
			result.append((raw_item as Dictionary).duplicate(true))
	return result
