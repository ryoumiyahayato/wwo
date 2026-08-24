class_name CurrentWorldPoliticalProjection
extends RefCounted
## Read-only adapter from runtime identity to existing map and panel record shapes.


static func map_units(
	registry: RuntimePoliticalEntityRegistry,
	evidence: HistoricalPoliticalEvidenceCatalog
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if registry == null or evidence == null:
		return result
	for runtime_id: String in registry.entity_ids():
		var source_id := registry.source_historical_id(runtime_id)
		var unit := evidence.record(source_id)
		if unit.is_empty():
			continue
		unit["id"] = runtime_id
		unit["source_historical_id"] = source_id
		unit["controller_id"] = registry.compatibility_controller_id(runtime_id)
		unit["sovereign_id"] = ""
		result.append(unit)
	return result


static func polity_summary(
	runtime_id: String,
	registry: RuntimePoliticalEntityRegistry,
	evidence: HistoricalPoliticalEvidenceCatalog
) -> Dictionary:
	if registry == null or evidence == null or not registry.has_entity(runtime_id):
		return {}
	var source_id := registry.source_historical_id(runtime_id)
	var result := evidence.record(source_id)
	if result.is_empty():
		return {}
	result["id"] = runtime_id
	result["entity_id"] = runtime_id
	result["runtime_id"] = runtime_id
	result["source_historical_id"] = source_id
	result["controller_id"] = registry.compatibility_controller_id(runtime_id)
	result["sovereign_id"] = ""
	result["runtime_entity"] = registry.entity(runtime_id)
	return result
