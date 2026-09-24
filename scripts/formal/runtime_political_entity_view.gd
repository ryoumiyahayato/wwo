class_name RuntimePoliticalEntityView
extends RefCounted
## Immutable current-world identity snapshot for economy, UI, and map consumers.
## It deliberately exposes no configure, restore, or entity mutation operation.

var _configured: bool = false
var _entities_by_runtime_id: Dictionary = {}
var _runtime_id_by_source_id: Dictionary = {}
var _authority_relations: Array[Dictionary] = []


func _init(snapshot: Dictionary = {}) -> void:
	_configured = not str(snapshot.get("schema_id", "")).is_empty()
	for entity_value: Variant in snapshot.get("entities", []) as Array:
		if not entity_value is Dictionary:
			continue
		var entity := (entity_value as Dictionary).duplicate(true)
		var runtime_id := str(entity.get("runtime_id", ""))
		if runtime_id.is_empty() or _entities_by_runtime_id.has(runtime_id):
			continue
		_entities_by_runtime_id[runtime_id] = entity
		var sources := DataRecordUtils.to_string_array(
			entity.get("source_historical_ids", [])
		)
		if sources.size() == 1:
			_runtime_id_by_source_id[sources[0]] = runtime_id
	_authority_relations = DataRecordUtils.to_dictionary_array(
		snapshot.get("authority_relations", [])
	)


func is_configured() -> bool:
	return _configured


func entity_count() -> int:
	return _entities_by_runtime_id.size()


func has_entity(runtime_id: String) -> bool:
	return _entities_by_runtime_id.has(runtime_id)


func entity(runtime_id: String) -> Dictionary:
	return (
		(_entities_by_runtime_id.get(runtime_id, {}) as Dictionary)
		.duplicate(true)
	)


func entity_ids() -> Array[String]:
	var result: Array[String] = []
	for runtime_id_value: Variant in _entities_by_runtime_id.keys():
		result.append(str(runtime_id_value))
	result.sort()
	return result


func entities() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for runtime_id: String in entity_ids():
		result.append(entity(runtime_id))
	return result


func runtime_id_for_source(source_historical_id: String) -> String:
	return str(_runtime_id_by_source_id.get(source_historical_id, ""))


func source_historical_id(runtime_id: String) -> String:
	var candidate := _entities_by_runtime_id.get(runtime_id, {}) as Dictionary
	var sources := DataRecordUtils.to_string_array(
		candidate.get("source_historical_ids", [])
	)
	return sources[0] if sources.size() == 1 else ""


func authority_relations() -> Array[Dictionary]:
	return _authority_relations.duplicate(true)


func authority_relations_for_target(runtime_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for relation: Dictionary in _authority_relations:
		if str(relation.get("target_runtime_id", "")) == runtime_id:
			result.append(relation.duplicate(true))
	return result
