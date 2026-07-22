class_name V23SurvivalAutonomyServiceV2
extends V23SurvivalAutonomyService
## Uses only SpatialLocationService's public projection. The service must not
## inspect a second or private positions dictionary.


func process_hour(current_hour: int) -> Dictionary:
	if product == null:
		return {}
	var value: Dictionary = V2DateTime.from_total_hour(current_hour)
	if int(value.get("hour", -1)) != 6:
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
		if person_id.is_empty() or product.spatial_locations.position_for(person_id).is_empty():
			continue
		checked += 1
		var need: Dictionary = _most_urgent_need(person_id, household)
		if need.is_empty():
			_clear_satisfied_needs(person_id, household)
			continue
		var result: V2LifeLoopResult = _plan_need(
			person_id, household_id, household, need, current_hour
		)
		if result.success:
			planned += 1
		else:
			blocked += 1
	return {"planned": planned, "blocked": blocked, "checked": checked}


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
		return V2LifeLoopResult.fail(
			"maintenance_retry_pending", "采购会在稍后重新尝试"
		)
	if product.schedule.has_pending_activity(
		person_id, "purchase_%s" % item_type, current_hour
	):
		active_needs[key] = {
			"status": "scheduled",
			"item_type": item_type,
			"stock_days": int(need.get("stock_days", 0)),
		}
		return V2LifeLoopResult.ok("采购已经安排")
	if product.manual_location_holds.has(person_id):
		return _block_and_retry(
			person_id,
			household_id,
			need,
			current_hour,
			"玩家要求人物继续停留在当前地点"
		)
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
		return _block_and_retry(
			person_id, household_id, need, current_hour, reason
		)
	var position: Dictionary = product.spatial_locations.position_for(person_id)
	var current_location_id: String = str(position.get("current_location_id", ""))
	if current_location_id == MARKET_LOCATION_ID:
		return _schedule_purchase(
			person_id, household_id, need, current_hour, price
		)
	# A planned commute or another future trip is not the same as being unable to
	# shop. The authoritative schedule and travel services below decide whether
	# a later departure can coexist with every existing obligation.
	return _schedule_purchase_trip(
		person_id,
		household_id,
		household,
		need,
		current_hour,
		price,
		cash
	)


func _schedule_purchase_trip(
	person_id: String,
	household_id: String,
	_household: Dictionary,
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
		# Travel settlement moves the person to the destination at the end of the
		# arrival hour. Purchase therefore starts no earlier than the following
		# hour; scheduling both at arrival_hour caused a remote-purchase rejection.
		var purchase_hour: int = arrival_hour + 1
		var purchase_value: Dictionary = V2DateTime.from_total_hour(purchase_hour)
		var purchase_clock_hour: int = int(purchase_value.get("hour", -1))
		if purchase_clock_hour < 6 or purchase_clock_hour >= 21:
			continue
		if not product.schedule.can_schedule_activity(
			person_id,
			"purchase_%s" % item_type,
			purchase_hour,
			1,
			"npc_rule"
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
			str(plan.get("travel_plan_id", "")),
			product.schedule,
			current_hour,
			"npc_rule"
		)
		if not travel_result.success:
			product.schedule.restore_persistent_state(schedule_before)
			product.travel_execution.restore_persistent_state(travel_before)
			continue
		var purchase_result: V2LifeLoopResult = product.schedule.schedule_rule_activity(
			person_id,
			"purchase_%s" % item_type,
			purchase_hour,
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
		return _record_plan(
			person_id,
			household_id,
			need,
			current_hour,
			purchase_hour,
			"travel_and_purchase_scheduled",
			str(activity.get("activity_id", ""))
		)
	return _block_and_retry(
		person_id,
		household_id,
		need,
		current_hour,
		"未来三天没有能够完成采购的行程和时间"
	)
