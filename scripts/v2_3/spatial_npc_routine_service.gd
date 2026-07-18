class_name SpatialNpcRoutineService
extends RefCounted
## Event-driven NPC planning state; never called from a per-frame social loop.

const REPLAN_REASONS: PackedStringArray = [
	"scenario_initialization", "new_day", "message_arrived", "route_invalidated",
	"schedule_shortfall", "major_state_change",
]

var npc_plans: Dictionary = {}
var planning_events: Array[Dictionary] = []
var planning_call_count: int = 0
var _planning_interval: int = 24
var _history_limit: int = 256


func configure(people: Array, balance: Dictionary, start_hour: int) -> void:
	npc_plans.clear()
	planning_events.clear()
	planning_call_count = 0
	var npc: Dictionary = balance.get("npc", {}) as Dictionary
	_planning_interval = maxi(1, int(npc.get("planning_interval_hours", 24)))
	_history_limit = maxi(32, int(
		(balance.get("history_limits", {}) as Dictionary).get("messages", 256)
	))
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		npc_plans[person_id] = {
			"person_id": person_id,
			"person_kind": str(person.get("person_kind", "background")),
			"last_planned_hour": start_hour - _planning_interval,
			"last_reason": "",
			"plan_generation": 0,
			"pending_message_ids": [],
			"active_travel_plan_id": "",
		}


func should_plan(person_id: String, total_hour: int, reason: String) -> bool:
	if not npc_plans.has(person_id) or reason not in REPLAN_REASONS:
		return false
	var plan: Dictionary = npc_plans[person_id] as Dictionary
	return (
		reason != "new_day"
		or total_hour - int(plan.get("last_planned_hour", -999999)) >= _planning_interval
	)


func mark_planned(
	person_id: String,
	total_hour: int,
	reason: String,
	travel_plan_id: String = ""
) -> void:
	if not npc_plans.has(person_id):
		return
	var plan: Dictionary = npc_plans[person_id] as Dictionary
	plan["last_planned_hour"] = total_hour
	plan["last_reason"] = reason
	plan["plan_generation"] = int(plan.get("plan_generation", 0)) + 1
	plan["active_travel_plan_id"] = travel_plan_id
	npc_plans[person_id] = plan
	planning_call_count += 1
	planning_events.append({
		"person_id": person_id,
		"total_hour": total_hour,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"reason": reason,
		"travel_plan_id": travel_plan_id,
	})
	while planning_events.size() > _history_limit:
		planning_events.pop_front()


func queue_message(person_id: String, message_id: String) -> void:
	if not npc_plans.has(person_id):
		return
	var plan: Dictionary = npc_plans[person_id] as Dictionary
	var pending: Array = plan.get("pending_message_ids", []) as Array
	if message_id not in pending:
		pending.append(message_id)
	plan["pending_message_ids"] = pending
	npc_plans[person_id] = plan


func take_next_message(person_id: String) -> String:
	if not npc_plans.has(person_id):
		return ""
	var plan: Dictionary = npc_plans[person_id] as Dictionary
	var pending: Array = plan.get("pending_message_ids", []) as Array
	if pending.is_empty():
		return ""
	var message_id: String = str(pending.pop_front())
	plan["pending_message_ids"] = pending
	npc_plans[person_id] = plan
	return message_id


func deterministic_accepts_relationship_request(
	relation: Dictionary, fatigue: int, schedule_available: bool
) -> bool:
	return (
		schedule_available
		and fatigue < 950
		and int(relation.get("trust", 0)) >= 0
		and int(relation.get("tension", 0)) < 700
	)


func get_persistent_state() -> Dictionary:
	return {
		"npc_plans": npc_plans.duplicate(true),
		"planning_events": planning_events.duplicate(true),
		"planning_call_count": planning_call_count,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("npc_plans", {}) is Dictionary
		or not state.get("planning_events", []) is Array
		or int(state.get("planning_call_count", -1)) < 0
	):
		return false
	var restored: Dictionary = state["npc_plans"] as Dictionary
	if restored.size() != npc_plans.size():
		return false
	for raw_person_id: Variant in restored.keys():
		if not npc_plans.has(str(raw_person_id)) or not restored[raw_person_id] is Dictionary:
			return false
	npc_plans = restored.duplicate(true)
	planning_events.clear()
	for raw_event: Variant in state["planning_events"] as Array:
		if not raw_event is Dictionary:
			return false
		planning_events.append((raw_event as Dictionary).duplicate(true))
	planning_call_count = int(state["planning_call_count"])
	return true
