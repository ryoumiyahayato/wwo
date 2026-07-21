class_name V23PlayerUiBinding
extends V23ControlledUiBindingV2
## Final product projection. It enriches existing authoritative records without
## creating any second location, inventory or relationship state.


func person_view(person_id: String = "") -> Dictionary:
	var view: Dictionary = super.person_view(person_id)
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return view
	var resolved_id: String = str(view.get("person_id", selected_person_id()))
	view["maintenance"] = product.survival_autonomy.maintenance_view(resolved_id)
	return view


func submit_selected_sandbox_plan_with_leave() -> V2LifeLoopResult:
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return V2LifeLoopResult.fail("sandbox_unavailable", "行动计划不可用")
	var person_id: String = selected_person_id()
	var selection: Dictionary = _selection_for(person_id)
	var goal_id: String = str(selection.get("goal_id", ""))
	var method_id: String = str(selection.get("method_id", ""))
	if goal_id.is_empty() or method_id.is_empty():
		return V2LifeLoopResult.fail("incomplete_social_plan", "请先选择处境和应对方式")
	last_command_result = product.authorize_leave_and_submit_social_intent(
		person_id,
		goal_id,
		method_id,
		str(selection.get("target_id", "")),
		{
			"current_hour": product.clock.total_hours,
			"start_hour": int(selection.get("start_hour", product.clock.total_hours + 12)),
			"preparation": int(selection.get("preparation", 400)),
			"location_id": str(selection.get("location_id", "")),
			"organization_id": str(selection.get("organization_id", "")),
		}
	)
	if last_command_result.success:
		selection["start_hour"] = product.clock.total_hours + 12
		_sandbox_selection_by_person[person_id] = selection
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func map_overlay_payload() -> Dictionary:
	var payload: Dictionary = super.map_overlay_payload()
	var product: V23ProductSimulationV2 = controlled_simulation as V23ProductSimulationV2
	if product == null:
		return payload
	var decorated_locations: Array[Dictionary] = []
	for raw_location: Variant in payload.get("locations", []) as Array:
		if not raw_location is Dictionary:
			continue
		var location: Dictionary = (raw_location as Dictionary).duplicate(true)
		var source: Dictionary = product.spatial_locations.locations.get(
			str(location.get("location_id", "")), {}
		) as Dictionary
		location["parent_region_id"] = str(source.get("parent_region_id", ""))
		location["local_position"] = (source.get("local_position", []) as Array).duplicate()
		location["available_services"] = (source.get("available_services", []) as Array).duplicate()
		decorated_locations.append(location)
	payload["locations"] = decorated_locations
	return payload
