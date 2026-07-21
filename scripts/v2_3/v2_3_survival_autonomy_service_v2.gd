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
