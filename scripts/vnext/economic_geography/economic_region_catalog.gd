class_name VNextEconomicRegionCatalog
extends RefCounted
## Economic Geography owns region identity and membership meaning. The trusted
## baseline currently supplies no approved region records, so empty is valid.

var _loaded: bool = false
var _revision: String = ""
var _records_by_id: Dictionary = {}
var _ordered_ids: Array[String] = []


func initialize_empty(revision: String = "economic_geography_empty_v1") -> bool:
	return load_records([], revision)


func load_records(records: Array[Dictionary], revision: String) -> bool:
	if _loaded or revision.is_empty():
		return false
	var candidate: Dictionary = {}
	for source: Dictionary in records:
		var region_id: String = str(source.get("economic_region_id", ""))
		var provenance: Dictionary = source.get("provenance", {}) as Dictionary
		if (
			not VNextEconomicRegionId.is_valid(region_id)
			or candidate.has(region_id)
			or not VNextFactProvenance.is_valid(provenance)
		):
			return false
		candidate[region_id] = {
			"economic_region_id": region_id,
			"name": str(source.get("name", "")),
			"provenance": provenance.duplicate(true),
		}
	var ids: Array[String] = []
	for raw_id: Variant in candidate.keys():
		ids.append(str(raw_id))
	ids.sort()
	_loaded = true
	_revision = revision
	_records_by_id = candidate
	_ordered_ids = ids
	return true


func is_loaded() -> bool:
	return _loaded and not _revision.is_empty()


func status() -> String:
	return "EMPTY / NOT AVAILABLE" if _ordered_ids.is_empty() else "ACTIVE"


func revision() -> String:
	return _revision


func economic_region_ids() -> Array[String]:
	return _ordered_ids.duplicate()


func get_region(region_id: String) -> Dictionary:
	var value: Variant = _records_by_id.get(region_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
