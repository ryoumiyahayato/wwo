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
