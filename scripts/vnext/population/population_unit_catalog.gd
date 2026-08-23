class_name VNextPopulationUnitCatalog
extends RefCounted
## Identity authority only. Geographic relationships belong to crosswalks.

var _loaded: bool = false
var _revision: String = ""
var _records_by_id: Dictionary = {}
var _ordered_ids: Array[String] = []


func load_records(records: Array[Dictionary], revision: String) -> bool:
	if _loaded or revision.is_empty():
		return false
	var candidate_by_id: Dictionary = {}
	var identity_by_source_entity: Dictionary = {}
	for source: Dictionary in records:
		var unit_id: String = str(source.get("population_unit_id", ""))
		var scope_kind: String = str(source.get("scope_kind", ""))
		var source_entity_id: String = str(source.get("source_entity_id", ""))
		if (
			not VNextPopulationUnitId.is_valid(unit_id)
			or scope_kind not in ["political_unit", "country_aggregate", "major_economy_aggregate"]
			or source_entity_id.is_empty()
			or candidate_by_id.has(unit_id)
		):
			return false
		if identity_by_source_entity.has(source_entity_id):
			# Scope labels describe evidence; they may not create a second
			# demographic identity for the same source entity.
			return false
		identity_by_source_entity[source_entity_id] = unit_id
		candidate_by_id[unit_id] = {
			"population_unit_id": unit_id,
			"scope_kind": scope_kind,
			"source_entity_id": source_entity_id,
		}
	var candidate_ids: Array[String] = []
	for raw_id: Variant in candidate_by_id.keys():
		candidate_ids.append(str(raw_id))
	candidate_ids.sort()
	_loaded = true
	_revision = revision
	_records_by_id = candidate_by_id
	_ordered_ids = candidate_ids
	return true


func is_loaded() -> bool:
	return _loaded and not _revision.is_empty() and _records_by_id.size() == _ordered_ids.size()


func revision() -> String:
	return _revision


func population_unit_ids() -> Array[String]:
	return _ordered_ids.duplicate()


func has_population_unit(unit_id: String) -> bool:
	return VNextPopulationUnitId.is_valid(unit_id) and _records_by_id.has(unit_id)


func get_population_unit(unit_id: String) -> Dictionary:
	var value: Variant = _records_by_id.get(unit_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
