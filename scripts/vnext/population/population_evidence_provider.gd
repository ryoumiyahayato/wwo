class_name VNextPopulationEvidenceProvider
extends RefCounted
## Read-only production evidence boundary. It intentionally supplies no
## regional or city facts and is not wired into the product root in Wave 2A-R1.

const SOURCE_PATH: String = "res://data/alpha/historical_world_economy_1900/countries_compact.json"
const SOURCE_MANIFEST_PATH: String = "res://data/alpha/historical_world_economy_1900.json"
const PROVIDER_REVISION: String = "historical_world_economy_1900_compact_country_table_v1:population"

var _loaded: bool = false
var _catalog := VNextPopulationUnitCatalog.new()
var _facts_by_id: Dictionary = {}
var _ordered_ids: Array[String] = []


func load_current_evidence() -> bool:
	if _loaded:
		return false
	var manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH)
	)
	if not manifest_value is Dictionary:
		return false
	var manifest := manifest_value as Dictionary
	var support_date: String = str(manifest.get("calibration_date", ""))
	var policy: Dictionary = manifest.get("policy", {}) as Dictionary
	var source_manifest: Array = manifest.get("source_manifest", []) as Array
	if (
		str(manifest.get("schema_id", "")) != "historical_world_economy_1900_estimates_v1"
		or str(manifest.get("compact_country_table_path", "")) != SOURCE_PATH
		or not VNextFactProvenance.is_iso_date(support_date)
		or not bool(policy.get("estimated_values_allowed", false))
		or not bool(policy.get("all_estimates_require_bounds", false))
		or source_manifest.is_empty()
	):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not parsed is Dictionary:
		return false
	var document := parsed as Dictionary
	if str(document.get("schema_id", "")) != "historical_world_economy_1900_compact_country_table_v1":
		return false
	var fields: Array = document.get("field_order", []) as Array
	var indexes: Dictionary = {}
	for index: int in range(fields.size()):
		indexes[str(fields[index])] = index
	for required: String in [
		"entity_id", "population_value", "population_lower", "population_upper",
		"population_confidence_bp",
	]:
		if not indexes.has(required):
			return false
	var method: String = str((document.get("common_methods", {}) as Dictionary).get("population", ""))
	if method.is_empty():
		return false
	var facts_by_id: Dictionary = {}
	var units: Array[Dictionary] = []
	for raw_row: Variant in document.get("rows", []) as Array:
		if not raw_row is Array:
			return false
		var row := raw_row as Array
		for required: String in [
			"entity_id", "population_value", "population_lower", "population_upper",
			"population_confidence_bp",
		]:
			if int(indexes[required]) >= row.size():
				return false
		var entity_id: String = str(row[int(indexes["entity_id"])])
		var unit_id: String = VNextPopulationUnitId.compose(entity_id)
		var value: int = int(row[int(indexes["population_value"])])
		var lower: int = int(row[int(indexes["population_lower"])])
		var upper: int = int(row[int(indexes["population_upper"])])
		var confidence_bp: int = int(row[int(indexes["population_confidence_bp"])])
		var provenance := VNextFactProvenance.create(
			VNextFactProvenance.NEAR_1900_SUPPORTED,
			VNextFactProvenance.ESTIMATED,
			str(manifest.get("schema_id", "")) + ".population",
			PROVIDER_REVISION,
			support_date,
			support_date,
			"",
			support_date,
			support_date,
			VNextFactProvenance.BASIS_POINTS
		)
		if (
			unit_id.is_empty() or value < 0 or lower < 0 or lower > value
			or upper < value or confidence_bp < 0 or confidence_bp > 10_000
			or provenance.is_empty() or facts_by_id.has(unit_id)
		):
			return false
		units.append({
			"population_unit_id": unit_id,
			"scope_kind": "major_economy_aggregate",
			"source_entity_id": entity_id,
		})
		facts_by_id[unit_id] = {
			"population_unit_id": unit_id,
			"total_population": value,
			"lower_bound": lower,
			"upper_bound": upper,
			"confidence_bp": confidence_bp,
			"method": method,
			"source_evidence_path": SOURCE_PATH,
			"source_manifest_path": SOURCE_MANIFEST_PATH,
			"source_manifest": source_manifest.duplicate(true),
			"source_classification": "BOUNDED_AGGREGATE_ESTIMATE",
			"provenance": provenance,
		}
	if facts_by_id.is_empty() or not _catalog.load_records(units, PROVIDER_REVISION):
		return false
	var ids := _catalog.population_unit_ids()
	if ids.size() != facts_by_id.size():
		return false
	_loaded = true
	_facts_by_id = facts_by_id
	_ordered_ids = ids
	return true


func is_loaded() -> bool:
	return _loaded and _catalog.is_loaded() and _facts_by_id.size() == _ordered_ids.size()


func revision() -> String:
	return PROVIDER_REVISION if is_loaded() else ""


func catalog() -> VNextPopulationUnitCatalog:
	return _catalog


func population_unit_ids() -> Array[String]:
	return _ordered_ids.duplicate()


func fact_at(unit_id: String) -> Dictionary:
	var value: Variant = _facts_by_id.get(unit_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func facts() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for unit_id: String in _ordered_ids:
		output.append(fact_at(unit_id))
	return output


func regional_fact(_spatial_region_id: String) -> Dictionary:
	return {}


func city_fact(_city_id: String) -> Dictionary:
	return {}
