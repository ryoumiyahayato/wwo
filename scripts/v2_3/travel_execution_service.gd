class_name TravelExecutionService
extends RefCounted
## Formal travel plans, schedule insertion, per-segment payment and arrival.

const TRAVEL_ACTIVITY_TYPES: PackedStringArray = [
	"travel_walk", "travel_urban_transit", "travel_regional_train",
]
const PLAN_STATUSES: PackedStringArray = [
	"planned", "waiting", "active", "completed", "failed",
	"interrupted", "cancelled",
]

var travel_plans: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _next_sequence: int = 1
var _history_limit: int = 128
var _idempotency_limit: int = 1024
var _nonterminal_plan_index: Dictionary = {}
var _terminal_plan_order: Array[String] = []
var locations: SpatialLocationService
var graph: TravelGraphService
var planner: RoutePlannerService


func configure(
	location_service: SpatialLocationService,
	graph_service: TravelGraphService,
	route_planner: RoutePlannerService,
	balance: Dictionary
) -> void:
	locations = location_service
	graph = graph_service
	planner = route_planner
	travel_plans.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_nonterminal_plan_index.clear()
	_terminal_plan_order.clear()
	_next_sequence = 1
	var limits: Dictionary = balance.get("history_limits", {}) as Dictionary
	_history_limit = maxi(32, int(limits.get("travel_plans", 128)))
	_idempotency_limit = maxi(128, int(limits.get("idempotency_keys", 1024)))


func create_plan(
	person_id: String,
	destination_id: String,
	preference: String,
	start_hour: int,
	available_cash_centimes: int,
	fatigue: int,
	purpose_activity_id: String = "",
	essential: bool = false,
	origin_override: String = ""
) -> V2LifeLoopResult:
	var position: Dictionary = locations.position_for(person_id)
	if position.is_empty():
		return V2LifeLoopResult.fail("unknown_person", "找不到旅行人物", person_id, [person_id])
	if str(position.get("location_state", "")) == "in_transit":
		return V2LifeLoopResult.fail(
			"already_in_transit", "人物已经在途中", str(position.get("current_route_id", "")),
			[person_id]
		)
	var origin_id: String = (
		origin_override
		if not origin_override.is_empty()
		else str(position.get("current_location_id", ""))
	)
	if not origin_override.is_empty() and not locations.knows_location(person_id, origin_id):
		return V2LifeLoopResult.fail(
			"unknown_location", "人物不知道预定行程起点", origin_id,
			[person_id, origin_id]
		)
	var route_result: V2LifeLoopResult = planner.plan_route(
		person_id, origin_id, destination_id, start_hour, preference,
		available_cash_centimes, fatigue, essential
	)
	if not route_result.success:
		return route_result
	var route: Dictionary = route_result.data
	if (route.get("route_segments", []) as Array).is_empty():
		return V2LifeLoopResult.fail(
			"already_at_destination", "人物已经在目的地", destination_id,
			[person_id, destination_id]
		)
	var plan_id: String = "travel_plan:v2_3:%06d" % _next_sequence
	_next_sequence += 1
	var plan: Dictionary = {
		"travel_plan_id": plan_id,
		"person_id": person_id,
		"origin_id": origin_id,
		"destination_id": destination_id,
		"route_preference": preference,
		"route_segments": (route.get("route_segments", []) as Array).duplicate(true),
		"start_hour": start_hour,
		"start_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"expected_arrival_hour": int(route.get("arrival_hour", start_hour)),
		"expected_arrival_datetime": str(route.get("arrival_datetime", "")),
		"total_cost_centimes": int(route.get("total_cost_centimes", 0)),
		"paid_transaction_ids": [],
		"scheduled_activity_ids": [],
		"status": "planned",
		"purpose_activity_id": purpose_activity_id,
		"failure_reason": "",
		"interruption_reason": "",
		"created_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"completed_datetime": "",
	}
	travel_plans[plan_id] = plan
	_nonterminal_plan_index[_plan_signature(plan)] = plan_id
	_trim_history()
	return V2LifeLoopResult.ok(
		"旅行计划已建立", {"travel_plan": plan.duplicate(true), "route": route},
		[person_id, plan_id, origin_id, destination_id]
	)


func has_nonterminal_plan(
	person_id: String, origin_id: String, destination_id: String, start_hour: int
) -> bool:
	return _nonterminal_plan_index.has(
		"%s|%s|%s|%d" % [person_id, origin_id, destination_id, start_hour]
	)


func schedule_plan(
	travel_plan_id: String,
	schedule: V2ScheduleService,
	current_hour: int,
	source: String = "npc_rule"
) -> V2LifeLoopResult:
	if not travel_plans.has(travel_plan_id):
		return V2LifeLoopResult.fail(
			"unknown_travel_plan", "找不到旅行计划", travel_plan_id, [travel_plan_id]
		)
	if source not in ["player", "npc_rule", "system"]:
		return V2LifeLoopResult.fail("invalid_source", "旅行日程来源无效", source)
	var plan: Dictionary = travel_plans[travel_plan_id] as Dictionary
	if str(plan.get("status", "")) != "planned":
		return V2LifeLoopResult.fail(
			"travel_plan_not_planned", "旅行计划不能重复写入日程", travel_plan_id,
			[travel_plan_id]
		)
	var blocks: Array[Dictionary] = _schedule_blocks(plan)
	for block: Dictionary in blocks:
		var preflight: V2LifeLoopResult = schedule.can_schedule_activity(
			str(plan.get("person_id", "")),
			str(block.get("activity_type", "")),
			int(block.get("start_hour", -1)),
			int(block.get("duration_hours", 0)),
			source
		)
		if not preflight.success:
			plan["status"] = "failed"
			plan["failure_reason"] = preflight.error_code
			_store_terminal_plan(travel_plan_id, plan)
			return preflight
	var activity_ids: Array[String] = []
	for block: Dictionary in blocks:
		var result: V2LifeLoopResult
		if source == "player":
			result = schedule.schedule_player_activity(
				str(plan.get("person_id", "")),
				str(block.get("activity_type", "")),
				int(block.get("start_hour", -1)),
				int(block.get("duration_hours", 1)),
				current_hour,
				str(block.get("location_id", "")),
				travel_plan_id
			)
		else:
			result = schedule.schedule_rule_activity(
				str(plan.get("person_id", "")),
				str(block.get("activity_type", "")),
				int(block.get("start_hour", -1)),
				int(block.get("duration_hours", 1)),
				str(block.get("location_id", "")),
				source,
				travel_plan_id
			)
		if not result.success:
			push_error("旅行日程预检后写入失败：%s" % result.user_message)
			plan["status"] = "failed"
			plan["failure_reason"] = "schedule_commit_failed"
			_store_terminal_plan(travel_plan_id, plan)
			return result
		var activity: Dictionary = result.data.get("activity", {}) as Dictionary
		var activity_id: String = str(activity.get("activity_id", ""))
		activity_ids.append(activity_id)
		schedule.merge_activity_metadata(
			str(plan.get("person_id", "")),
			activity_id,
			{
				"travel_plan_id": travel_plan_id,
				"route_segment_id": str(block.get("route_segment_id", "")),
				"route_segment_index": int(block.get("route_segment_index", -1)),
				"transport_mode": str(block.get("transport_mode", "")),
				"travel_destination_id": str(plan.get("destination_id", "")),
			}
		)
	plan["scheduled_activity_ids"] = activity_ids
	travel_plans[travel_plan_id] = plan
	return V2LifeLoopResult.ok(
		"旅行已写入现有日程",
		{"travel_plan": plan.duplicate(true), "scheduled_blocks": blocks},
		[str(plan.get("person_id", "")), travel_plan_id]
	)


func settle_activity(
	person_id: String,
	activity: Dictionary,
	total_hour: int,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null,
	conditions: V2ConditionService = null
) -> V2LifeLoopResult:
	var activity_type: String = str(activity.get("activity_type", ""))
	if activity_type == "wait_for_transport":
		return _settle_wait(person_id, activity, total_hour, conditions)
	if activity_type not in TRAVEL_ACTIVITY_TYPES:
		return V2LifeLoopResult.ok()
	var plan_id: String = str(activity.get("travel_plan_id", ""))
	if not travel_plans.has(plan_id):
		return V2LifeLoopResult.fail(
			"unknown_travel_plan", "旅行活动缺少正式计划", plan_id, [person_id]
		)
	var plan: Dictionary = travel_plans[plan_id] as Dictionary
	var segment_index: int = int(activity.get("route_segment_index", -1))
	var segments: Array = plan.get("route_segments", []) as Array
	if segment_index < 0 or segment_index >= segments.size():
		return V2LifeLoopResult.fail(
			"invalid_route_segment", "旅行活动路段索引无效", str(segment_index),
			[person_id, plan_id]
		)
	var segment: Dictionary = segments[segment_index] as Dictionary
	var segment_start: int = int(segment.get("departure_hour", -1))
	if total_hour == segment_start:
		var payment: V2LifeLoopResult = V2LifeLoopResult.ok("背景人物无完整经济")
		if households != null and ledger != null:
			payment = _pay_segment(
				person_id, plan, segment, total_hour, households, ledger
			)
		if not payment.success:
			plan["status"] = "failed"
			plan["failure_reason"] = payment.error_code
			_store_terminal_plan(plan_id, plan)
			locations.interrupt(person_id, payment.error_code)
			return payment
		plan = travel_plans[plan_id] as Dictionary
		var begin: V2LifeLoopResult = locations.begin_transit(
			person_id, plan_id, str(segment.get("edge_id", "")), segment_index,
			total_hour, int(segment.get("arrival_hour", total_hour + 1)),
			str(plan.get("destination_id", ""))
		)
		if not begin.success:
			return begin
		plan["status"] = "active"
		travel_plans[plan_id] = plan
	var duration: int = maxi(1, int(segment.get("duration_hours", 1)))
	if conditions != null and not conditions.get_state(person_id).is_empty():
		conditions.apply_delta(
			person_id, "fatigue",
			int(segment.get("fatigue", 0)) / duration, total_hour,
			"旅行产生疲劳", "travel",
			str(segment.get("route_segment_id", ""))
		)
		conditions.apply_delta(
			person_id, "stress",
			int(segment.get("stress", 0)) / duration, total_hour,
			"旅行产生压力", "travel",
			str(segment.get("route_segment_id", ""))
		)
	if total_hour + 1 >= int(segment.get("arrival_hour", total_hour + 1)):
		var final_segment: bool = segment_index == segments.size() - 1
		var arrival: V2LifeLoopResult = locations.complete_segment(
			person_id, str(segment.get("to_location_id", "")), total_hour + 1, final_segment
		)
		if not arrival.success:
			return arrival
		if final_segment:
			plan["status"] = "completed"
			plan["completed_datetime"] = V2DateTime.iso_from_total_hour(total_hour + 1)
			_store_terminal_plan(plan_id, plan)
		else:
			plan["status"] = "waiting"
			travel_plans[plan_id] = plan
	return V2LifeLoopResult.ok(
		"旅行小时已结算",
		{
			"travel_plan_id": plan_id,
			"route_segment_id": str(segment.get("route_segment_id", "")),
			"status": str(plan.get("status", "")),
		},
		[person_id, plan_id]
	)


func interrupt_plan(travel_plan_id: String, reason: String) -> V2LifeLoopResult:
	if not travel_plans.has(travel_plan_id):
		return V2LifeLoopResult.fail(
			"unknown_travel_plan", "找不到旅行计划", travel_plan_id, [travel_plan_id]
		)
	var plan: Dictionary = travel_plans[travel_plan_id] as Dictionary
	if str(plan.get("status", "")) in ["completed", "cancelled", "failed"]:
		return V2LifeLoopResult.fail(
			"travel_plan_terminal", "旅行计划已经结束", travel_plan_id, [travel_plan_id]
		)
	plan["status"] = "interrupted"
	plan["interruption_reason"] = reason
	_store_terminal_plan(travel_plan_id, plan)
	locations.interrupt(str(plan.get("person_id", "")), reason)
	return V2LifeLoopResult.ok("旅行已中断", {}, [travel_plan_id])


func active_plan_for_person(person_id: String) -> Dictionary:
	var ids: Array[String] = []
	for raw_plan_id: Variant in travel_plans.keys():
		ids.append(str(raw_plan_id))
	ids.sort()
	for plan_id: String in ids:
		var plan: Dictionary = travel_plans[plan_id] as Dictionary
		if (
			str(plan.get("person_id", "")) == person_id
			and str(plan.get("status", "")) in ["planned", "waiting", "active"]
		):
			return plan.duplicate(true)
	return {}


func expire_stale_plans(total_hour: int) -> int:
	var expired_count: int = 0
	var plan_ids: Array[String] = []
	for raw_plan_id: Variant in travel_plans.keys():
		plan_ids.append(str(raw_plan_id))
	plan_ids.sort()
	for plan_id: String in plan_ids:
		var plan: Dictionary = travel_plans[plan_id] as Dictionary
		var status: String = str(plan.get("status", ""))
		if (
			status not in ["planned", "waiting", "active"]
			or int(plan.get("expected_arrival_hour", total_hour + 1)) >= total_hour
		):
			continue
		if status == "active":
			locations.interrupt(
				str(plan.get("person_id", "")), "travel_arrival_deadline_missed"
			)
			plan["status"] = "interrupted"
			plan["interruption_reason"] = "travel_arrival_deadline_missed"
		else:
			plan["status"] = "failed"
			plan["failure_reason"] = "scheduled_travel_not_completed"
		_store_terminal_plan(plan_id, plan)
		expired_count += 1
	return expired_count


func get_persistent_state() -> Dictionary:
	return {
		"travel_plans": travel_plans.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("travel_plans", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
		or not state.get("processed_key_order", []) is Array
		or int(state.get("next_sequence", 0)) < 1
	):
		return false
	var restored_plans: Dictionary = state["travel_plans"] as Dictionary
	for raw_plan_id: Variant in restored_plans.keys():
		var plan_id: String = str(raw_plan_id)
		if not restored_plans[plan_id] is Dictionary:
			return false
		var plan: Dictionary = restored_plans[plan_id] as Dictionary
		if (
			plan_id != str(plan.get("travel_plan_id", ""))
			or str(plan.get("status", "")) not in PLAN_STATUSES
			or not plan.get("route_segments", []) is Array
		):
			return false
	var processed: Dictionary = state["processed_idempotency_keys"] as Dictionary
	var order: Array[String] = []
	for raw_key: Variant in state["processed_key_order"] as Array:
		var key: String = str(raw_key)
		if key.is_empty() or not processed.has(key) or key in order:
			return false
		order.append(key)
	travel_plans = restored_plans.duplicate(true)
	processed_idempotency_keys = processed.duplicate(true)
	_processed_key_order = order
	_next_sequence = int(state["next_sequence"])
	_nonterminal_plan_index.clear()
	_terminal_plan_order.clear()
	var restored_ids: Array[String] = []
	for raw_plan_id: Variant in travel_plans.keys():
		restored_ids.append(str(raw_plan_id))
	restored_ids.sort()
	for plan_id: String in restored_ids:
		var plan: Dictionary = travel_plans[plan_id] as Dictionary
		if str(plan.get("status", "")) in ["planned", "waiting", "active"]:
			_nonterminal_plan_index[_plan_signature(plan)] = plan_id
		else:
			_terminal_plan_order.append(plan_id)
	return true


func _schedule_blocks(plan: Dictionary) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var segments: Array = plan.get("route_segments", []) as Array
	for index: int in range(segments.size()):
		var segment: Dictionary = segments[index] as Dictionary
		var waiting: int = int(segment.get("waiting_hours", 0))
		if waiting > 0:
			blocks.append({
				"activity_type": "wait_for_transport",
				"start_hour": int(segment.get("departure_hour", 0)) - waiting,
				"duration_hours": waiting,
				"location_id": str(segment.get("from_location_id", "")),
				"route_segment_id": str(segment.get("route_segment_id", "")),
				"route_segment_index": index,
				"transport_mode": str(segment.get("mode_id", "")),
			})
		blocks.append({
			"activity_type": _travel_activity_type(str(segment.get("mode_id", ""))),
			"start_hour": int(segment.get("departure_hour", 0)),
			"duration_hours": int(segment.get("duration_hours", 1)),
			"location_id": str(segment.get("from_location_id", "")),
			"route_segment_id": str(segment.get("route_segment_id", "")),
			"route_segment_index": index,
			"transport_mode": str(segment.get("mode_id", "")),
		})
	return blocks


func _settle_wait(
	person_id: String,
	activity: Dictionary,
	total_hour: int,
	conditions: V2ConditionService = null
) -> V2LifeLoopResult:
	var plan_id: String = str(activity.get("travel_plan_id", ""))
	if not travel_plans.has(plan_id):
		return V2LifeLoopResult.fail(
			"unknown_travel_plan", "等待活动缺少旅行计划", plan_id, [person_id]
		)
	var plan: Dictionary = travel_plans[plan_id] as Dictionary
	var segment_index: int = int(activity.get("route_segment_index", 0))
	var segments: Array = plan.get("route_segments", []) as Array
	if segment_index < 0 or segment_index >= segments.size():
		return V2LifeLoopResult.fail("invalid_route_segment", "等待路段无效", plan_id)
	var segment: Dictionary = segments[segment_index] as Dictionary
	locations.set_waiting(
		person_id, plan_id, str(segment.get("edge_id", "")),
		str(plan.get("destination_id", ""))
	)
	plan["status"] = "waiting"
	travel_plans[plan_id] = plan
	if conditions != null and not conditions.get_state(person_id).is_empty():
		conditions.apply_delta(
			person_id, "fatigue", 3, total_hour,
			"等待交通产生疲劳", "wait_for_transport",
			str(segment.get("route_segment_id", ""))
		)
		conditions.apply_delta(
			person_id, "stress", 8, total_hour,
			"等待交通产生压力", "wait_for_transport",
			str(segment.get("route_segment_id", ""))
		)
	return V2LifeLoopResult.ok("等待交通小时已结算", {}, [person_id, plan_id])


func _pay_segment(
	person_id: String,
	plan: Dictionary,
	segment: Dictionary,
	total_hour: int,
	households: V2HouseholdService,
	ledger: V2LedgerService
) -> V2LifeLoopResult:
	var cost: int = int(segment.get("cost_centimes", 0))
	if cost == 0:
		return V2LifeLoopResult.ok("免费路段无需扣款")
	var plan_id: String = str(plan.get("travel_plan_id", ""))
	var segment_id: String = str(segment.get("route_segment_id", ""))
	var key: String = "travel:%s:%s:%s" % [person_id, plan_id, segment_id]
	if processed_idempotency_keys.has(key) or ledger.has_key(key):
		return V2LifeLoopResult.ok("该收费路段已经扣款", {"already_paid": true})
	var household_id: String = households.household_id_for_person(person_id)
	var result: V2LifeLoopResult = ledger.post(
		households.households, household_id, person_id, cost, "expense", "transport",
		total_hour, plan_id, segment_id, key,
		"交通费：%s" % str(segment.get("mode_id", ""))
	)
	if not result.success:
		return result
	var stored_plan: Dictionary = travel_plans[plan_id] as Dictionary
	var paid_ids: Array = stored_plan.get("paid_transaction_ids", []) as Array
	paid_ids.append(str(
		(result.data.get("transaction", {}) as Dictionary).get("transaction_id", "")
	))
	stored_plan["paid_transaction_ids"] = paid_ids
	travel_plans[plan_id] = stored_plan
	_remember_key(key)
	return result


func _remember_key(key: String) -> void:
	processed_idempotency_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > _idempotency_limit:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


func _store_terminal_plan(plan_id: String, plan: Dictionary) -> void:
	travel_plans[plan_id] = plan
	var signature: String = _plan_signature(plan)
	if str(_nonterminal_plan_index.get(signature, "")) == plan_id:
		_nonterminal_plan_index.erase(signature)
	if plan_id not in _terminal_plan_order:
		_terminal_plan_order.append(plan_id)
	_trim_history()


func _trim_history() -> void:
	while travel_plans.size() > _history_limit and not _terminal_plan_order.is_empty():
		var plan_id: String = _terminal_plan_order.pop_front()
		if travel_plans.has(plan_id):
			travel_plans.erase(plan_id)


static func _plan_signature(plan: Dictionary) -> String:
	return "%s|%s|%s|%d" % [
		str(plan.get("person_id", "")),
		str(plan.get("origin_id", "")),
		str(plan.get("destination_id", "")),
		int(plan.get("start_hour", -1)),
	]


static func _travel_activity_type(mode_id: String) -> String:
	match mode_id:
		"walk":
			return "travel_walk"
		"urban_transit":
			return "travel_urban_transit"
		"regional_train":
			return "travel_regional_train"
	return "travel_walk"
