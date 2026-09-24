class_name VNextTerritorySourceRegistry
extends RefCounted
## Immutable registry of territory source evidence and production-admission facts.

const SOURCE_RECORD = preload("res://scripts/vnext/territory/territory_source_record.gd")
const ADMISSION = preload("res://scripts/vnext/territory/territory_source_admission.gd")

const DEFAULT_REGISTRY_PATH: String = "res://data/world_map/territory_source_registry.json"
const REGISTRY_SCHEMA: String = "vnext_territory_source_registry_v1"
const FINGERPRINT_SCHEMA: String = "vnext_territory_source_registry_fingerprint_v1"

var _configured: bool = false
var _records_by_id: Dictionary = {}
var _ordered_ids: Array[String] = []
var _admission_by_id: Dictionary = {}
var _fingerprint: String = ""
var _errors: Array[String] = []


func configure_from_path(path: String = DEFAULT_REGISTRY_PATH) -> bool:
	if _configured:
		return _fail("registry is immutable after configuration")
	if path.is_empty() or not FileAccess.file_exists(path):
		return _fail("registry resource is missing: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("registry resource must contain a dictionary")
	var root: Dictionary = parsed as Dictionary
	if str(root.get("schema_id", "")) != REGISTRY_SCHEMA:
		return _fail("unknown territory source registry schema")
	if typeof(root.get("sources")) != TYPE_ARRAY:
		return _fail("registry sources must be an array")
	return configure(root.get("sources") as Array)


func configure(records_value: Array) -> bool:
	if _configured:
		return _fail("registry is immutable after configuration")
	var candidate_by_id: Dictionary = {}
	var candidate_ids: Array[String] = []
	for raw_record: Variant in records_value:
		var record := VNextTerritorySourceRecord.new()
		if not record.configure(raw_record):
			return _fail("invalid territory source record")
		var source_id := record.source_snapshot_id()
		if candidate_by_id.has(source_id):
			return _fail("duplicate source_snapshot_id: %s" % source_id)
		candidate_by_id[source_id] = record
		candidate_ids.append(source_id)
	candidate_ids.sort()
	if not _validate_parent_graph(candidate_by_id, candidate_ids):
		return false

	var candidate_admission: Dictionary = {}
	for source_id: String in candidate_ids:
		var record: VNextTerritorySourceRecord = candidate_by_id[source_id] as VNextTerritorySourceRecord
		var hash_status := _source_hash_status(record)
		if hash_status == "HASH_MISMATCH":
			return _fail("declared source hash mismatch: %s" % source_id)
		if hash_status == "RESOURCE_MISSING":
			return _fail("local resource is missing: %s" % source_id)
		var normalized_hash_status := (
			ADMISSION.PASS if hash_status == ADMISSION.PASS else ADMISSION.UNRESOLVED
		)
		var derivation_status := _derivation_traceability_status(record, candidate_by_id)
		var evaluation := ADMISSION.evaluate(
			record.to_detached_dict(),
			normalized_hash_status,
			derivation_status
		)
		if not _validate_status_semantics(record, evaluation):
			return false
		candidate_admission[source_id] = evaluation.duplicate(true)

	_records_by_id = candidate_by_id
	_ordered_ids = candidate_ids
	_admission_by_id = candidate_admission
	_fingerprint = _fingerprint_for_registry()
	_errors.clear()
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func record_count() -> int:
	return _ordered_ids.size() if _configured else 0


func source_snapshot_ids() -> Array[String]:
	return _copy_strings(_ordered_ids) if _configured else []


func source_by_id(source_snapshot_id: String) -> Dictionary:
	if not _configured or not _records_by_id.has(source_snapshot_id):
		return {}
	var record: VNextTerritorySourceRecord = _records_by_id[source_snapshot_id] as VNextTerritorySourceRecord
	return record.to_detached_dict()


func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _configured:
		return result
	for source_id: String in _ordered_ids:
		result.append(source_by_id(source_id))
	return result


func records_with_status(status: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _configured or not VNextTerritorySourceRecord.ADMISSION_STATUSES.has(status):
		return result
	for source_id: String in _ordered_ids:
		var record := source_by_id(source_id)
		if str(record.get("production_admission_status", "")) == status:
			result.append(record)
	return result


func admitted_sources() -> Array[Dictionary]:
	return records_with_status(VNextTerritorySourceRecord.STATUS_ADMITTED)


func admission_for(source_snapshot_id: String) -> Dictionary:
	if not _configured or not _admission_by_id.has(source_snapshot_id):
		return {}
	return (_admission_by_id[source_snapshot_id] as Dictionary).duplicate(true)


func fingerprint() -> String:
	return _fingerprint if _configured else ""


func production_geography_available() -> bool:
	return _configured and not admitted_sources().is_empty()


func audit_report() -> Dictionary:
	var report: Dictionary = {
		"REGISTERED_SOURCE_COUNT": 0,
		"REFERENCE_ONLY_SOURCE_COUNT": 0,
		"CANDIDATE_SOURCE_COUNT": 0,
		"ADMITTED_SOURCE_COUNT": 0,
		"REJECTED_SOURCE_COUNT": 0,
		"PROTOTYPE_SOURCE_COUNT": 0,
		"LICENSE_RESTRICTED_SOURCE_COUNT": 0,
		"COMMERCIAL_INELIGIBLE_SOURCE_COUNT": 0,
		"UNRESOLVED_LICENSE_SOURCE_COUNT": 0,
		"UNRESOLVED_HISTORICAL_FIT_COUNT": 0,
		"DERIVED_SOURCE_COUNT": 0,
		"UNTRACEABLE_DERIVATION_COUNT": 0,
		"REGISTRY_FINGERPRINT": "",
		"PRODUCTION_GEOGRAPHY_AVAILABLE": "NO",
	}
	if not _configured:
		return report
	report["REGISTERED_SOURCE_COUNT"] = _ordered_ids.size()
	for source_id: String in _ordered_ids:
		var record := source_by_id(source_id)
		match str(record.get("production_admission_status", "")):
			VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY:
				report["REFERENCE_ONLY_SOURCE_COUNT"] = int(report["REFERENCE_ONLY_SOURCE_COUNT"]) + 1
			VNextTerritorySourceRecord.STATUS_CANDIDATE:
				report["CANDIDATE_SOURCE_COUNT"] = int(report["CANDIDATE_SOURCE_COUNT"]) + 1
			VNextTerritorySourceRecord.STATUS_ADMITTED:
				report["ADMITTED_SOURCE_COUNT"] = int(report["ADMITTED_SOURCE_COUNT"]) + 1
			VNextTerritorySourceRecord.STATUS_REJECTED:
				report["REJECTED_SOURCE_COUNT"] = int(report["REJECTED_SOURCE_COUNT"]) + 1
		if bool(record.get("prototype_only", false)):
			report["PROTOTYPE_SOURCE_COUNT"] = int(report["PROTOTYPE_SOURCE_COUNT"]) + 1
		var license_restricted: bool = (
			record.get("redistribution_allowed") == false
			or record.get("derivative_work_allowed") == false
			or record.get("commercial_use_allowed") == false
			or record.get("share_alike_required") == true
		)
		if license_restricted:
			report["LICENSE_RESTRICTED_SOURCE_COUNT"] = int(report["LICENSE_RESTRICTED_SOURCE_COUNT"]) + 1
		if record.get("commercial_use_allowed") == false:
			report["COMMERCIAL_INELIGIBLE_SOURCE_COUNT"] = int(report["COMMERCIAL_INELIGIBLE_SOURCE_COUNT"]) + 1
		if (
			str(record.get("license_id", "")).is_empty()
			or str(record.get("license_url", "")).is_empty()
			or record.get("redistribution_allowed") == null
			or record.get("derivative_work_allowed") == null
			or record.get("commercial_use_allowed") == null
		):
			report["UNRESOLVED_LICENSE_SOURCE_COUNT"] = int(report["UNRESOLVED_LICENSE_SOURCE_COUNT"]) + 1
		if str(record.get("historical_fit_status", "")) == VNextTerritorySourceRecord.HISTORICAL_FIT_UNRESOLVED:
			report["UNRESOLVED_HISTORICAL_FIT_COUNT"] = int(report["UNRESOLVED_HISTORICAL_FIT_COUNT"]) + 1
		if str(record.get("derivation_kind", "")) != VNextTerritorySourceRecord.DERIVATION_RAW_EXTERNAL:
			report["DERIVED_SOURCE_COUNT"] = int(report["DERIVED_SOURCE_COUNT"]) + 1
		var admission := admission_for(source_id)
		var gates: Dictionary = admission.get("gates", {}) as Dictionary
		if str(gates.get(ADMISSION.DERIVATION_TRACEABLE, ADMISSION.UNRESOLVED)) != ADMISSION.PASS:
			report["UNTRACEABLE_DERIVATION_COUNT"] = int(report["UNTRACEABLE_DERIVATION_COUNT"]) + 1
	report["REGISTRY_FINGERPRINT"] = _fingerprint
	report["PRODUCTION_GEOGRAPHY_AVAILABLE"] = "YES" if production_geography_available() else "NO"
	return report


func errors() -> Array[String]:
	return _copy_strings(_errors)


func _source_hash_status(record: VNextTerritorySourceRecord) -> String:
	var local_path := str(record.value("local_resource_path", ""))
	var declared_hash := str(record.value("source_sha256", ""))
	if local_path.is_empty():
		return ADMISSION.UNRESOLVED
	if not FileAccess.file_exists(local_path):
		return "RESOURCE_MISSING"
	if declared_hash.is_empty():
		return ADMISSION.UNRESOLVED
	var actual_hash: String
	if local_path.get_extension().to_lower() == "json":
		var canonical_text := FileAccess.get_file_as_string(local_path).replace("\r\n", "\n").replace("\r", "\n")
		actual_hash = canonical_text.sha256_text()
	else:
		actual_hash = FileAccess.get_sha256(local_path)
	return ADMISSION.PASS if actual_hash == declared_hash else "HASH_MISMATCH"


func _derivation_traceability_status(
	record: VNextTerritorySourceRecord,
	records_by_id: Dictionary
) -> String:
	if record.derivation_kind() == VNextTerritorySourceRecord.DERIVATION_RAW_EXTERNAL:
		return ADMISSION.PASS
	var parents := record.parent_source_snapshot_ids()
	if parents.is_empty() or str(record.value("derivation_method", "")).strip_edges().is_empty():
		return ADMISSION.FAIL
	for parent_id: String in parents:
		if not records_by_id.has(parent_id):
			return ADMISSION.FAIL
	return ADMISSION.PASS


func _validate_status_semantics(
	record: VNextTerritorySourceRecord,
	evaluation: Dictionary
) -> bool:
	var status := record.production_admission_status()
	var all_pass := bool(evaluation.get("production_geography_admitted", false))
	var failure_count := int(evaluation.get("failure_count", 0))
	var unresolved_count := int(evaluation.get("unresolved_count", 0))
	if status == VNextTerritorySourceRecord.STATUS_ADMITTED:
		if not all_pass:
			return _fail("ADMITTED source failed production gates: %s" % record.source_snapshot_id())
		if str(record.value("production_admission_reason", "")) != "ALL_GATES_PASSED":
			return _fail("ADMITTED source must use ALL_GATES_PASSED reason")
	elif status == VNextTerritorySourceRecord.STATUS_CANDIDATE:
		if failure_count > 0 or unresolved_count <= 0:
			return _fail("CANDIDATE source must be unresolved without a known failed gate: %s" % record.source_snapshot_id())
	elif status == VNextTerritorySourceRecord.STATUS_REJECTED:
		if failure_count <= 0:
			return _fail("REJECTED source must have a known failed production gate: %s" % record.source_snapshot_id())
	return true


func _validate_parent_graph(records_by_id: Dictionary, ordered_ids: Array[String]) -> bool:
	for source_id: String in ordered_ids:
		var record: VNextTerritorySourceRecord = records_by_id[source_id] as VNextTerritorySourceRecord
		for parent_id: String in record.parent_source_snapshot_ids():
			if not records_by_id.has(parent_id):
				return _fail("unknown parent source_snapshot_id %s referenced by %s" % [parent_id, source_id])
	var states: Dictionary = {}
	for source_id: String in ordered_ids:
		if _visit_parent_graph(source_id, records_by_id, states):
			return _fail("parent source cycle detected")
	return true


func _visit_parent_graph(
	source_id: String,
	records_by_id: Dictionary,
	states: Dictionary
) -> bool:
	var state := int(states.get(source_id, 0))
	if state == 1:
		return true
	if state == 2:
		return false
	states[source_id] = 1
	var record: VNextTerritorySourceRecord = records_by_id[source_id] as VNextTerritorySourceRecord
	for parent_id: String in record.parent_source_snapshot_ids():
		if _visit_parent_graph(parent_id, records_by_id, states):
			return true
	states[source_id] = 2
	return false


func _fingerprint_for_registry() -> String:
	var source_records: Array = []
	for source_id: String in _ordered_ids:
		source_records.append(source_by_id(source_id))
	var payload: Dictionary = {
		"fingerprint_schema": FINGERPRINT_SCHEMA,
		"sources": source_records,
	}
	return JSON.stringify(_canonical_copy(payload), "", false).sha256_text()


static func _canonical_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copied_array: Array = []
		for item: Variant in value as Array:
			copied_array.append(_canonical_copy(item))
		return copied_array
	if typeof(value) == TYPE_DICTIONARY:
		var source: Dictionary = value as Dictionary
		var keys: Array = source.keys()
		keys.sort()
		var copied_dictionary: Dictionary = {}
		for key: Variant in keys:
			copied_dictionary[key] = _canonical_copy(source.get(key))
		return copied_dictionary
	return value


static func _copy_strings(source: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	for value: String in source:
		copied.append(value)
	return copied


func _fail(message: String) -> bool:
	_errors.append(message)
	return false
