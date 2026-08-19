extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"
## Authority-aware layer for the dated political world. The source evidence
## provider remains responsible for geometry/flags; this layer replaces the
## legacy sovereign==controller runtime assumption with typed authority queries.

var _historical_authority_model := HistoricalAuthorityModel.new()


func _rebuild_historical_political_world() -> void:
	var units := _dated_units_document.get("units", []) as Array
	if not _historical_authority_model.configure(units):
		var message := "Historical authority model: %s" % _historical_authority_model.initialization_error
		if message not in _data_errors:
			_data_errors.append(message)
		push_error(message)
		return
	super._rebuild_historical_political_world()


func _build_dated_historical_unit(unit: Dictionary) -> void:
	super._build_dated_historical_unit(unit)
	var entity_id := str(unit.get("id", ""))
	if not _country_by_id.has(entity_id):
		return
	var record := _country_by_id.get(entity_id, {}) as Dictionary
	# Legal sovereignty is derived only from an explicit sovereign relation.
	# Legacy controller_id remains presentation compatibility and is never
	# promoted to sovereignty by this layer.
	record["sovereign_id"] = _historical_authority_model.first_sovereign_id(entity_id)
	record["controller_id"] = _historical_authority_model.legacy_presentation_controller(entity_id)
	_country_by_id[entity_id] = record


func get_authority_relations(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_authority_relations(entity_id)


func get_relations_by_type(
	entity_id: String, relationship_type: String
) -> Array[Dictionary]:
	return _historical_authority_model.get_relations_by_type(entity_id, relationship_type)


func get_sovereigns(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_sovereigns(entity_id)


func get_protectors(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_protectors(entity_id)


func get_administrators(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_administrators(entity_id)


func get_occupiers(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_occupiers(entity_id)


func get_de_facto_controllers(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_de_facto_controllers(entity_id)


func get_foreign_relations_controllers(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_foreign_relations_controllers(entity_id)


func get_claimants(entity_id: String) -> Array[Dictionary]:
	return _historical_authority_model.get_claimants(entity_id)


func get_active_relations(entity_id: String, date: String) -> Array[Dictionary]:
	return _historical_authority_model.get_active_relations(entity_id, date)


func legacy_presentation_controller(entity_id: String) -> String:
	return _historical_authority_model.legacy_presentation_controller(entity_id)
