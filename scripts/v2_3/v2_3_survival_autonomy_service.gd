class_name V23SurvivalAutonomyService
extends RefCounted
## Bounded household self-maintenance. It does not own inventory, cash, travel,
## location or schedule state; it only decides when to use the existing services.

const MARKET_LOCATION_ID: String = "location_lille_wazemmes_market"
const ITEM_TYPES: PackedStringArray = ["food", "essentials"]
const MAX_DECISIONS: int = 128

var product: V23ProductSimulationV2
var profiles: Dictionary = {}
var next_retry_hours: Dictionary = {}
var active_needs: Dictionary = {}
var decision_history: Array[Dictionary] = []


func configure(target: V23ProductSimulationV2, people: Array, start_hour: int) -> V2LifeLoopResult:
	product = target
	profiles.clear()
	next_retry_hours.clear()
	active_needs.clear()
	decision_history.clear()
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		if person_id.is_empty():
			continue
		profiles[person_id] = (person.get("maintenance_profile", {}) as Dictionary).duplicate(true)
	for person_id_variant: Variant in product.households.person_to_household.keys():
		var person_id: String = str(person_id_variant)
		if not profiles.has(person_id):
			profiles[person_id] = _default_profile()
		for item_type: String in ITEM_TYPES:
			next_retry_hours[_need_key(person_id, item_type)] = start_hour
	return V2LifeLoopResult.ok(
		"生活自理策略已建立",
		{"profile_count": profiles.size()}
	)


func process_hour(current_hour: int) -> Dictionary:
	if product == null:
		return {}
	var value: Dictionary = V2DateTime.from_total_hour(current_hour)
	var hour: int = int(value.get("hour", -1))
	if hour != 6:
		return {"planned": 0, "blocked": 0, "checked": 0}
	var planned: int = 0
	var blocked: int = 0
	var checked: int = 0
	var household_ids: Array[String] = []
	for household_id_variant: Variant in product.households.households.keys():
		household_ids.append(str(household_id_variant))
	household_ids.sort()
	for household_id: String in household_ids:
		var household: Dictionary = product.households.households.get(household_id, {}) as Dictionary
		var members: Array = household.get("member_ids", []) as Array
		if members.is_empty():
			continue
		var person_id: String = str(members[0])
		if person_id.is_empty() or not product.spatial_locations.positions.has(person_id):
			continue
		checked += 1
		var need: Dictionary = _most_urgent_need(person_id, household)
		if need.is_empty():
			_clear_satisfied_needs(person_id, household)
			continue
		var result: V2LifeLoopResult = _plan_need(person_id, household_id, household, need, current_hour)
		if result.success:
			planned += 1
		else:
			blocked += 1
	return {"planned": planned, "blocked": blocked, "checked": checked}


func maintenance_view(person_id: String) -> Dictionary:
	if product == null:
		return {}
	var household: Dictionary = product.households.household_for_person(person_id)
	if household.is_empty():
		return {}
	var member_count: int = maxi(1, (household.get("member_ids", []) as Array).size())
	var profile: Dictionary = _profile_for(person_id)
	var food_days: int = int(household.get("food_stock_person_days", 0)) / member_count
	var essentials_days: int = int(household.get("essentials_stock_person_days", 0)) / member_count
	return {
		"food_days": food_days,
		"essentials_days": essentials_days,
		"food_status": _stock_status(food_days, profile),
		"essentials_status": _stock_status(essentials_days, profile),
		"cash_reserve_centimes": int(profile.get("cash_reserve_centimes", 500)),
		"active_need": _active_need_for(person_id),
	}


func get_persistent_state() -> Dictionary:
	return {
		"next_retry_hours": next_retry_hours.duplicate(true),
		"active_needs": active_needs.duplicate(true),
		"decision_history": decision_history.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("next_retry_hours", {}) is Dictionary
		or not state.get("active_needs", {}) is Dictionary
		or not state.get("decision_history", []) is Array
	):
		return false
	next_retry_hours = (state.get("next_retry_hours", {}) as Dictionary).duplicate(true)
	active_needs = (state.get("active_needs", {}) as Dictionary).duplicate(true)
	decision_history.clear()
	for raw_record: Variant in state.get("decision_history", []) as Array:
		if not raw_record is Dictionary:
			return false
		decision_history.append((raw_record as Dictionary).duplicate(true))
	while decision_history.size() > MAX_DECISIONS:
		decision_history.pop_front()
	return true


func validate_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("next_retry_hours", {}) is Dictionary
		or not state.get("active_needs", {}) is Dictionary
		or not state.get("decision_history", []) is Array
	):
		return false
	for retry_variant: Variant in (state.get("next_retry_hours", {}) as Dictionary).values():
		if int(retry_variant) < 0:
			return false
	return true


func _most_urgent_need(person_id: String, household: Dictionary) -> Dictionary:
	var members: int = maxi(1, (household.get("member_ids", []) as Array).size())
	var profile: Dictionary = _profile_for(person_id)
	var candidates: Array[Dictionary] = []
	for item_type: String in ITEM_TYPES:
		var stock_days: int = int(household.get("%s_stock_person_days" % item_type, 0)) / members
		var warning: int = int(profile.get("warning_stock_days", 4))
		if stock_days > warning:
			continue
		var emergency: int = int(profile.get("emergency_stock_days", 1))
		var urgent: int = int(profile.get("urgent_stock_days", 2))
		var priority: int = 100 - stock_days * 10
		if stock_days <= emergency:
			priority += 100
		elif stock_days <= urgent:
			priority += 50
		if item_type == "food":
			priority += 20
		candidates.append({
			"item_type": item_type,
			"stock_days": stock_days,
			"priority": priority,
			"emergency": stock_days <= emergency,
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("priority", 0)) > int(right.get("priority", 0))
	)
	return candidates[0]


func _plan_need(
	person_id: String,
	household_id: String,
	household: Dictionary,
	need: Dictionary,
	current_hour: int
) -> V2LifeLoopResult:
	var item_type: String = str(need.get("item_type", ""))
	var key: String = _need_key(person_id, item_type)
	if current_hour < int(next_retry_hours.get(key, 0)):
		return V2LifeLoopResult.fail("maintenance_retry_pending", "采购会在稍后重新尝试")
	if product.schedule.has_pending_activity(person_id, "purchase_%s" % item_type, current_hour):
		active_needs[key] = {
			"status": "scheduled",
			"item_type": item_type,
			"stock_days": int(need.get("stock_days", 0)),
		}
		return V2LifeLoopResult.ok("采购已经安排")
	if not product.travel_execution.active_plan_for_person(person_id).is_empty():
		return _block_and_retry(person_id, household_id, need, current_hour, "人物正在途中")
	if product.manual_location_holds.has(person_id):
		return _block_and_retry(person_id, household_id, need, current_hour, "玩家要求人物继续停留在当前地点")
	var costs: Dictionary = product.config.get_document("living_costs")
	var package: Dictionary = costs.get("%s_package" % item_type, {}) as Dictionary
	var price: int = int(package.get("price_centimes", 0))
	var cash: int = int(household.get("cash_centimes", 0))
	var profile: Dictionary = _profile_for(person_id)
	var reserve: int = int(profile.get("cash_reserve_centimes", 500))
	var emergency: bool = bool(need.get("emergency", false))
	if cash < price or (not emergency and cash - price < reserve):
		var reason: String = (
			"现金不足，无法购买%s" % _item_label(item_type)
			if cash < price
			else "为了保留基本生活资金，暂缓购买%s" % _item_label(item_type)
		)
		return _block_and_retry(person_id, household_id, need, current_hour, reason)
	var position: Dictionary = product.spatial_locations.position_for(person_id)
	var current_location_id: String = str(position.get("current_location_id", ""))
	if current_location_id == MARKET_LOCATION_ID:
		return _schedule_purchase(person_id, household_id, need, current_hour, price)
	return _schedule_purchase_trip(person_id, household_id, household, need, current_hour, price, cash)


func _schedule_purchase(
	person_id: String,
	household_id: String,
	need: Dictionary,
	current_hour: int,
	price: int
) -> V2LifeLoopResult:
	var item_type: String = str(need.get("item_type", ""))
	var start_hour: int = product.schedule.find_available_hour(
		person_id, current_hour + 1, current_hour + 48, 6, 21, 1
	)
	if start_hour < 0:
		return _block_and_retry(person_id, household_id, need, current_hour, "未来两天没有可用于采购的时间")
	var result: V2LifeLoopResult = product.schedule.schedule_rule_activity(
		person_id,
		"purchase_%s" % item_type,
		start_hour,
		1,
		MARKET_LOCATION_ID,
		"npc_rule",
		household_id,
		price
	)
	if not result.success:
		return _block_and_retry(person_id, household_id, need, current_hour, result.user_message)
	var activity: Dictionary = result.data.get("activity", {}) as Dictionary
	product.schedule.merge_activity_metadata(
		person_id,
		str(activity.get("activity_id", "")),
		{
			"autonomous_maintenance": true,
			"maintenance_item_type": item_type,
			"required_cash_centimes": price,
		}
	)
	return _record_plan(person_id, household_id, need, current_hour, start_hour, "purchase_scheduled", str(activity.get("activity_id", "")))


func _schedule_purchase_trip(
	person_id: String,
	household_id: String,
	household: Dictionary,
	need: Dictionary,
	current_hour: int,
	price: int,
	cash: int
) -> V2LifeLoopResult:
	var item_type: String = str(need.get("item_type", ""))
	var position: Dictionary = product.spatial_locations.position_for(person_id)
	var origin_id: String = str(position.get("current_location_id", ""))
	var fatigue: int = int(product.conditions.get_state(person_id).get("fatigue", 0))
	for departure_hour: int in range(current_hour + 1, current_hour + 73):
		var route: V2LifeLoopResult = product.route_planner.plan_route(
			person_id,
			origin_id,
			MARKET_LOCATION_ID,
			departure_hour,
			"fastest",
			cash,
			fatigue,
			bool(need.get("emergency", false))
		)
		if not route.success:
			continue
		var arrival_hour: int = int(route.data.get("arrival_hour", departure_hour + 1))
		var arrival_value: Dictionary = V2DateTime.from_total_hour(arrival_hour)
		var arrival_clock_hour: int = int(arrival_value.get("hour", -1))
		if arrival_clock_hour < 6 or arrival_clock_hour >= 21:
			continue
		if not product.schedule.can_schedule_activity(
			person_id, "purchase_%s" % item_type, arrival_hour, 1, "npc_rule"
		).success:
			continue
		var schedule_before: Dictionary = product.schedule.get_persistent_state()
		var travel_before: Dictionary = product.travel_execution.get_persistent_state()
		var created: V2LifeLoopResult = product.travel_execution.create_plan(
			person_id,
			MARKET_LOCATION_ID,
			"fastest",
			departure_hour,
			cash,
			fatigue,
			"survival_purchase:%s" % item_type,
			bool(need.get("emergency", false))
		)
		if not created.success:
			continue
		var plan: Dictionary = created.data.get("travel_plan", {}) as Dictionary
		var travel_result: V2LifeLoopResult = product.travel_execution.schedule_plan(
			str(plan.get("travel_plan_id", "")), product.schedule, current_hour, "npc_rule"
		)
		if not travel_result.success:
			product.schedule.restore_persistent_state(schedule_before)
			product.travel_execution.restore_persistent_state(travel_before)
			continue
		var purchase_result: V2LifeLoopResult = product.schedule.schedule_rule_activity(
			person_id,
			"purchase_%s" % item_type,
			arrival_hour,
			1,
			MARKET_LOCATION_ID,
			"npc_rule",
			household_id,
			price
		)
		if not purchase_result.success:
			product.schedule.restore_persistent_state(schedule_before)
			product.travel_execution.restore_persistent_state(travel_before)
			continue
		var activity: Dictionary = purchase_result.data.get("activity", {}) as Dictionary
		product.schedule.merge_activity_metadata(
			person_id,
			str(activity.get("activity_id", "")),
			{
				"autonomous_maintenance": true,
				"maintenance_item_type": item_type,
				"required_cash_centimes": price,
				"travel_plan_id": str(plan.get("travel_plan_id", "")),
			}
		)
		return _record_plan(person_id, household_id, need, current_hour, arrival_hour, "travel_and_purchase_scheduled", str(activity.get("activity_id", "")))
	return _block_and_retry(person_id, household_id, need, current_hour, "未来三天没有能够完成采购的行程和时间")


func _record_plan(
	person_id: String,
	household_id: String,
	need: Dictionary,
	current_hour: int,
	start_hour: int,
	status: String,
	activity_id: String
) -> V2LifeLoopResult:
	var item_type: String = str(need.get("item_type", ""))
	var key: String = _need_key(person_id, item_type)
	active_needs[key] = {
		"person_id": person_id,
		"household_id": household_id,
		"item_type": item_type,
		"stock_days": int(need.get("stock_days", 0)),
		"status": status,
		"activity_id": activity_id,
		"planned_hour": current_hour,
		"start_hour": start_hour,
	}
	next_retry_hours[key] = current_hour + 24
	_append_decision(active_needs[key] as Dictionary)
	product.notifications.add(
		"personal",
		"event",
		"已安排%s采购" % _item_label(item_type),
		"人物注意到库存只够约 %d 天，已经安排前往市场购买。" % int(need.get("stock_days", 0)),
		current_hour,
		"autonomous_purchase:%s:%s:%s" % [person_id, item_type, V2DateTime.date_from_total_hour(current_hour)],
		[person_id, household_id, activity_id]
	)
	product.state_changed.emit({"household_autonomy": true, "schedule": person_id})
	return V2LifeLoopResult.ok("已安排生活必需品采购", active_needs[key] as Dictionary)


func _block_and_retry(
	person_id: String,
	household_id: String,
	need: Dictionary,
	current_hour: int,
	reason: String
) -> V2LifeLoopResult:
	var item_type: String = str(need.get("item_type", ""))
	var key: String = _need_key(person_id, item_type)
	next_retry_hours[key] = current_hour + 24
	active_needs[key] = {
		"person_id": person_id,
		"household_id": household_id,
		"item_type": item_type,
		"stock_days": int(need.get("stock_days", 0)),
		"status": "retry_next_day",
		"reason": reason,
		"planned_hour": current_hour,
	}
	_append_decision(active_needs[key] as Dictionary)
	product.notifications.add(
		"personal",
		"notification",
		"%s采购尚未完成" % _item_label(item_type),
		"%s；人物会在次日继续尝试。" % reason,
		current_hour,
		"autonomous_purchase_blocked:%s:%s:%s" % [person_id, item_type, V2DateTime.date_from_total_hour(current_hour)],
		[person_id, household_id]
	)
	return V2LifeLoopResult.fail("maintenance_deferred", reason)


func _clear_satisfied_needs(person_id: String, household: Dictionary) -> void:
	var members: int = maxi(1, (household.get("member_ids", []) as Array).size())
	var profile: Dictionary = _profile_for(person_id)
	for item_type: String in ITEM_TYPES:
		var stock_days: int = int(household.get("%s_stock_person_days" % item_type, 0)) / members
		if stock_days >= int(profile.get("warning_stock_days", 4)):
			active_needs.erase(_need_key(person_id, item_type))


func _active_need_for(person_id: String) -> Dictionary:
	var result: Dictionary = {}
	for item_type: String in ITEM_TYPES:
		var value: Variant = active_needs.get(_need_key(person_id, item_type), {})
		if value is Dictionary and not (value as Dictionary).is_empty():
			result = (value as Dictionary).duplicate(true)
			break
	return result


func _profile_for(person_id: String) -> Dictionary:
	var value: Variant = profiles.get(person_id, _default_profile())
	return (value as Dictionary).duplicate(true) if value is Dictionary else _default_profile()


static func _default_profile() -> Dictionary:
	return {
		"preferred_stock_days": 7,
		"warning_stock_days": 4,
		"urgent_stock_days": 2,
		"emergency_stock_days": 1,
		"cash_reserve_centimes": 500,
		"shopping_preference": "balanced",
	}


static func _stock_status(days: int, profile: Dictionary) -> String:
	if days <= int(profile.get("emergency_stock_days", 1)):
		return "即将耗尽"
	if days <= int(profile.get("urgent_stock_days", 2)):
		return "需要尽快补充"
	if days <= int(profile.get("warning_stock_days", 4)):
		return "已经列入采购计划"
	return "充足"


static func _item_label(item_type: String) -> String:
	return "食品" if item_type == "food" else "生活用品"


static func _need_key(person_id: String, item_type: String) -> String:
	return "%s|%s" % [person_id, item_type]


func _append_decision(record: Dictionary) -> void:
	decision_history.append(record.duplicate(true))
	while decision_history.size() > MAX_DECISIONS:
		decision_history.pop_front()
