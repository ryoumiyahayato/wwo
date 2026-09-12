class_name CurrentWorldPoliticalProjection
extends RefCounted
## Read-only adapter from runtime identity to existing map and panel record shapes.


static func map_units(
	registry: RuntimePoliticalEntityView,
	evidence: HistoricalPoliticalEvidenceView
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if registry == null or evidence == null:
		return result
	for runtime_id: String in registry.entity_ids():
		var source_id := registry.source_historical_id(runtime_id)
		var unit := evidence.record(source_id)
		if unit.is_empty():
			unit = _missing_metadata_record(runtime_id, source_id)
		else:
			unit["historical_metadata_state"] = "available"
		unit.erase("controller_id")
		unit.erase("sovereign_id")
		unit["id"] = runtime_id
		unit["runtime_id"] = runtime_id
		unit["source_historical_id"] = source_id
		unit["authority_relations"] = (
			registry.authority_relations_for_target(runtime_id)
		)
		unit["runtime_entity"] = registry.entity(runtime_id)
		result.append(unit)
	return result


static func polity_summary(
	runtime_id: String,
	registry: RuntimePoliticalEntityView,
	evidence: HistoricalPoliticalEvidenceView
) -> Dictionary:
	if registry == null or evidence == null or not registry.has_entity(runtime_id):
		return {}
	var source_id := registry.source_historical_id(runtime_id)
	var result := evidence.record(source_id)
	if result.is_empty():
		result = _missing_metadata_record(runtime_id, source_id)
	else:
		result["historical_metadata_state"] = "available"
	result.erase("controller_id")
	result.erase("sovereign_id")
	result["id"] = runtime_id
	result["entity_id"] = runtime_id
	result["runtime_id"] = runtime_id
	result["source_historical_id"] = source_id
	result["authority_relations"] = (
		registry.authority_relations_for_target(runtime_id)
	)
	result["runtime_entity"] = registry.entity(runtime_id)
	return result


static func _missing_metadata_record(
	runtime_id: String, source_historical_id: String
) -> Dictionary:
	return {
		"name": runtime_id,
		"name_zh": runtime_id,
		"short_name_zh": runtime_id,
		"status": "runtime_identity",
		"relationship": "",
		"source_historical_id": source_historical_id,
		"historical_metadata_state": "missing",
		"historical_metadata_missing": true,
	}
