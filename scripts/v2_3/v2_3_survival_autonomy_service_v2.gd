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
