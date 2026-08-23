class_name VNextTypedCrosswalkCatalog
extends RefCounted
## Sparse, versioned cross-domain relationships. Empty catalogs are valid.

const POLITICAL_UNIT: String = "POLITICAL_UNIT"
const SPATIAL_REGION: String = "SPATIAL_REGION"
const POPULATION_UNIT: String = "POPULATION_UNIT"
const ECONOMIC_REGION: String = "ECONOMIC_REGION"

const ALLOCATION: String = "ALLOCATION"
const RELEVANCE: String = "RELEVANCE"
const ASSOCIATION: String = "ASSOCIATION"
const GEOMETRIC_OVERLAP: String = "GEOMETRIC_OVERLAP"

var _loaded: bool = false
var _revision: String = ""
var _records: Array[Dictionary] = []
var _by_source: Dictionary = {}
var _by_target: Dictionary = {}


func load_records(records: Array[Dictionary], revision: String) -> bool:
	if _loaded or revision.is_empty():
		return false
	var normalized: Array[Dictionary] = []
	var duplicate_keys: Dictionary = {}
	for source: Dictionary in records:
		var record: Dictionary = _normalize_record(source)
		if record.is_empty():
			return false
		var duplicate_key: String = "\u001f".join([
			str(record["source_type"]), str(record["source_id"]),
			str(record["target_type"]), str(record["target_id"]),
			str(record["measure"]), str(record["mapping_kind"]),
			str(record["valid_from"]), str(record["valid_to"]),
		])
		if duplicate_keys.has(duplicate_key):
			return false
		duplicate_keys[duplicate_key] = true
		normalized.append(record)
	normalized.sort_custom(Callable(self, "_compare_records"))
	if not _validate_allocation_groups(normalized):
		return false
	var by_source: Dictionary = {}
	var by_target: Dictionary = {}
	for record: Dictionary in normalized:
		_append_indexed(by_source, _index_key(str(record["source_type"]), str(record["source_id"])), record)
		_append_indexed(by_target, _index_key(str(record["target_type"]), str(record["target_id"])), record)
	_loaded = true
	_revision = revision
	_records = normalized
	_by_source = by_source
	_by_target = by_target
	return true


func is_loaded() -> bool:
	return _loaded and not _revision.is_empty()


func revision() -> String:
	return _revision


func size() -> int:
	return _records.size()


func status() -> String:
	return "EMPTY / NOT AVAILABLE" if _records.is_empty() else "ACTIVE"


func records() -> Array[Dictionary]:
	return _copy_records(_records)


func records_from(source_type: String, source_id: String) -> Array[Dictionary]:
	return _copy_records(_by_source.get(_index_key(source_type, source_id), []) as Array)


func records_to(target_type: String, target_id: String) -> Array[Dictionary]:
	return _copy_records(_by_target.get(_index_key(target_type, target_id), []) as Array)


func unresolved_bp(source_type: String, source_id: String, measure: String) -> int:
	for record: Dictionary in records_from(source_type, source_id):
		if str(record.get("mapping_kind", "")) == ALLOCATION and str(record.get("measure", "")) == measure:
			return int(record.get("unresolved_bp", -1))
	return -1


func _normalize_record(source: Dictionary) -> Dictionary:
	for field_name: String in [
		"source_type", "source_id", "target_type", "target_id", "measure",
		"mapping_kind", "applicability", "valid_from", "valid_to", "provenance_id",
	]:
		if not source.has(field_name):
			return {}
	var source_type: String = str(source.get("source_type", ""))
	var source_id: String = str(source.get("source_id", ""))
	var target_type: String = str(source.get("target_type", ""))
	var target_id: String = str(source.get("target_id", ""))
	var measure: String = str(source.get("measure", ""))
	var mapping_kind: String = str(source.get("mapping_kind", ""))
	var applicability: String = str(source.get("applicability", ""))
	var valid_from: String = str(source.get("valid_from", ""))
	var valid_to: String = str(source.get("valid_to", ""))
	if (
		not _is_supported_type(source_type) or not _is_supported_type(target_type)
		or source_type == target_type or not _valid_typed_id(source_type, source_id)
		or not _valid_typed_id(target_type, target_id) or measure.is_empty()
		or mapping_kind not in [ALLOCATION, RELEVANCE, ASSOCIATION, GEOMETRIC_OVERLAP]
		or not VNextFactProvenance.is_applicability(applicability)
		or not VNextFactProvenance.is_iso_date(valid_from)
		or not VNextFactProvenance.is_iso_date(valid_to) or valid_from > valid_to
		or str(source.get("provenance_id", "")).is_empty()
	):
		return {}
	var output: Dictionary = {
		"source_type": source_type,
		"source_id": source_id,
		"target_type": target_type,
		"target_id": target_id,
		"measure": measure,
		"mapping_kind": mapping_kind,
		"applicability": applicability,
		"valid_from": valid_from,
		"valid_to": valid_to,
		"provenance_id": str(source.get("provenance_id", "")),
	}
	if mapping_kind == ALLOCATION:
		for field_name: String in ["allocation_weight_bp", "coverage_bp", "unresolved_bp"]:
			if not source.has(field_name) or typeof(source.get(field_name)) != TYPE_INT:
				return {}
		var weight: int = int(source.get("allocation_weight_bp"))
		var coverage: int = int(source.get("coverage_bp"))
		var unresolved: int = int(source.get("unresolved_bp"))
		if (
			weight < 0 or weight > VNextFactProvenance.BASIS_POINTS
			or coverage < 0 or coverage > VNextFactProvenance.BASIS_POINTS
			or unresolved != VNextFactProvenance.BASIS_POINTS - coverage
			or source.has("relevance_bp")
		):
			return {}
		output["allocation_weight_bp"] = weight
		output["coverage_bp"] = coverage
		output["unresolved_bp"] = unresolved
	elif mapping_kind == RELEVANCE:
		if not source.has("relevance_bp") or typeof(source.get("relevance_bp")) != TYPE_INT:
			return {}
		var relevance: int = int(source.get("relevance_bp"))
		if relevance < 0 or relevance > VNextFactProvenance.BASIS_POINTS or _has_allocation_fields(source):
			return {}
		output["relevance_bp"] = relevance
	else:
		if _has_allocation_fields(source) or source.has("relevance_bp"):
			return {}
		if mapping_kind == GEOMETRIC_OVERLAP and measure in ["population", "working_age_population", "labor", "demand"]:
			return {}
	return output


func _validate_allocation_groups(records_value: Array[Dictionary]) -> bool:
	var groups: Dictionary = {}
	for record: Dictionary in records_value:
		if str(record.get("mapping_kind", "")) != ALLOCATION:
			continue
		var group_key: String = "\u001f".join([
			str(record["source_type"]), str(record["source_id"]), str(record["target_type"]),
			str(record["measure"]), str(record["valid_from"]), str(record["valid_to"]),
		])
		var group: Dictionary = groups.get(group_key, {
			"weight_sum": 0,
			"coverage_bp": int(record["coverage_bp"]),
			"unresolved_bp": int(record["unresolved_bp"]),
			"applicability": str(record["applicability"]),
			"provenance_id": str(record["provenance_id"]),
		})
		if (
			int(group["coverage_bp"]) != int(record["coverage_bp"])
			or int(group["unresolved_bp"]) != int(record["unresolved_bp"])
			or str(group["applicability"]) != str(record["applicability"])
			or str(group["provenance_id"]) != str(record["provenance_id"])
		):
			return false
		group["weight_sum"] = int(group["weight_sum"]) + int(record["allocation_weight_bp"])
		groups[group_key] = group
	for group_value: Variant in groups.values():
		var group := group_value as Dictionary
		if int(group["weight_sum"]) != int(group["coverage_bp"]):
			return false
	return true


static func _is_supported_type(value: String) -> bool:
	return value in [POLITICAL_UNIT, SPATIAL_REGION, POPULATION_UNIT, ECONOMIC_REGION]


static func _valid_typed_id(type_name: String, value: String) -> bool:
	match type_name:
		POPULATION_UNIT:
			return VNextPopulationUnitId.is_valid(value)
		ECONOMIC_REGION:
			return VNextEconomicRegionId.is_valid(value)
		SPATIAL_REGION:
			return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "place"
		POLITICAL_UNIT:
			return _is_local_id(value)
	return false


static func _is_local_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in range(value.length()):
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(value.substr(index, 1)):
			return false
	return true


static func _has_allocation_fields(value: Dictionary) -> bool:
	return value.has("allocation_weight_bp") or value.has("coverage_bp") or value.has("unresolved_bp")


static func _index_key(type_name: String, identity: String) -> String:
	return type_name + "\u001f" + identity


static func _append_indexed(index: Dictionary, key: String, record: Dictionary) -> void:
	var values: Array = index.get(key, []) as Array
	values.append(record.duplicate(true))
	index[key] = values


static func _copy_records(source: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for raw_record: Variant in source:
		if raw_record is Dictionary:
			output.append((raw_record as Dictionary).duplicate(true))
	return output


static func _compare_records(left: Dictionary, right: Dictionary) -> bool:
	var left_key: String = "\u001f".join([
		str(left["source_type"]), str(left["source_id"]), str(left["target_type"]),
		str(left["target_id"]), str(left["measure"]), str(left["mapping_kind"]),
	])
	var right_key: String = "\u001f".join([
		str(right["source_type"]), str(right["source_id"]), str(right["target_type"]),
		str(right["target_id"]), str(right["measure"]), str(right["mapping_kind"]),
	])
	return left_key < right_key
