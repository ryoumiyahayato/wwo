class_name VNextTerritorySourceAdmission
extends RefCounted
## Pure production-admission policy over normalized territory source evidence.

const SOURCE_RECORD = preload("res://scripts/vnext/territory/territory_source_record.gd")

const PASS: String = "PASS"
const FAIL: String = "FAIL"
const UNRESOLVED: String = "UNRESOLVED"

const PROVENANCE_VALID: String = "PROVENANCE_VALID"
const SOURCE_HASH_VERIFIED: String = "SOURCE_HASH_VERIFIED"
const TEMPORAL_SCOPE_VALID: String = "TEMPORAL_SCOPE_VALID"
const HISTORICAL_FIT_VALID: String = "HISTORICAL_FIT_VALID"
const GEOMETRY_SCOPE_VALID: String = "GEOMETRY_SCOPE_VALID"
const LICENSE_IDENTIFIED: String = "LICENSE_IDENTIFIED"
const REDISTRIBUTION_ALLOWED: String = "REDISTRIBUTION_ALLOWED"
const DERIVATIVE_WORK_ALLOWED: String = "DERIVATIVE_WORK_ALLOWED"
const COMMERCIAL_USE_ALLOWED: String = "COMMERCIAL_USE_ALLOWED"
const DERIVATION_TRACEABLE: String = "DERIVATION_TRACEABLE"
const PROTOTYPE_ONLY_FALSE: String = "PROTOTYPE_ONLY_FALSE"
const REQUIRED_GATES: Array[String] = [
	PROVENANCE_VALID,
	SOURCE_HASH_VERIFIED,
	TEMPORAL_SCOPE_VALID,
	HISTORICAL_FIT_VALID,
	GEOMETRY_SCOPE_VALID,
	LICENSE_IDENTIFIED,
	REDISTRIBUTION_ALLOWED,
	DERIVATIVE_WORK_ALLOWED,
	COMMERCIAL_USE_ALLOWED,
	DERIVATION_TRACEABLE,
	PROTOTYPE_ONLY_FALSE,
]


static func evaluate(
	record: Dictionary,
	source_hash_status: String,
	derivation_status: String
) -> Dictionary:
	var gates: Dictionary = {
		PROVENANCE_VALID: _provenance_gate(record),
		SOURCE_HASH_VERIFIED: source_hash_status,
		TEMPORAL_SCOPE_VALID: _temporal_gate(record),
		HISTORICAL_FIT_VALID: _historical_fit_gate(record),
		GEOMETRY_SCOPE_VALID: _geometry_gate(record),
		LICENSE_IDENTIFIED: _license_gate(record),
		REDISTRIBUTION_ALLOWED: _permission_gate(record.get("redistribution_allowed")),
		DERIVATIVE_WORK_ALLOWED: _permission_gate(record.get("derivative_work_allowed")),
		COMMERCIAL_USE_ALLOWED: _permission_gate(record.get("commercial_use_allowed")),
		DERIVATION_TRACEABLE: derivation_status,
		PROTOTYPE_ONLY_FALSE: FAIL if bool(record.get("prototype_only", true)) else PASS,
	}
	var all_pass := true
	var failure_count := 0
	var unresolved_count := 0
	var reasons: Array[String] = []
	for gate_name: String in REQUIRED_GATES:
		var gate_status := str(gates.get(gate_name, UNRESOLVED))
		if gate_status != PASS:
			all_pass = false
			reasons.append("%s_%s" % [gate_name, gate_status])
		if gate_status == FAIL:
			failure_count += 1
		elif gate_status == UNRESOLVED:
			unresolved_count += 1
	return {
		"gates": gates.duplicate(true),
		"production_geography_admitted": all_pass,
		"failure_count": failure_count,
		"unresolved_count": unresolved_count,
		"reasons": reasons,
	}


static func _provenance_gate(record: Dictionary) -> String:
	if (
		str(record.get("dataset_name", "")).strip_edges().is_empty()
		or str(record.get("dataset_version", "")).strip_edges().is_empty()
		or str(record.get("provider", "")).strip_edges().is_empty()
	):
		return UNRESOLVED
	if (
		str(record.get("source_page", "")).strip_edges().is_empty()
		and str(record.get("download_url", "")).strip_edges().is_empty()
	):
		return UNRESOLVED
	return PASS


static func _temporal_gate(record: Dictionary) -> String:
	var target := str(record.get("historical_target_date", ""))
	if target.is_empty():
		return UNRESOLVED
	var valid_from := str(record.get("valid_from", ""))
	var valid_to := str(record.get("valid_to", ""))
	if not valid_from.is_empty() and not valid_to.is_empty():
		return PASS if valid_from <= target and target <= valid_to else FAIL
	var snapshot_date := str(record.get("snapshot_date", ""))
	if not snapshot_date.is_empty():
		return PASS if snapshot_date == target else UNRESOLVED
	return UNRESOLVED


static func _historical_fit_gate(record: Dictionary) -> String:
	match str(record.get("historical_fit_status", "")):
		SOURCE_RECORD.HISTORICAL_FIT_STRONG, SOURCE_RECORD.HISTORICAL_FIT_QUALIFIED:
			return PASS
		SOURCE_RECORD.HISTORICAL_FIT_FAIL:
			return FAIL
		_:
			return UNRESOLVED


static func _geometry_gate(record: Dictionary) -> String:
	if (
		str(record.get("geometry_scope", "")).strip_edges().is_empty()
		or str(record.get("geometry_granularity", "")).strip_edges().is_empty()
		or str(record.get("coordinate_reference_system", "")).strip_edges().is_empty()
	):
		return UNRESOLVED
	var feature_count_value: Variant = record.get("feature_count")
	if feature_count_value == null:
		return UNRESOLVED
	return PASS if typeof(feature_count_value) == TYPE_INT and int(feature_count_value) >= 0 else FAIL


static func _license_gate(record: Dictionary) -> String:
	if (
		str(record.get("license_id", "")).strip_edges().is_empty()
		or str(record.get("license_url", "")).strip_edges().is_empty()
	):
		return UNRESOLVED
	return PASS


static func _permission_gate(value: Variant) -> String:
	if value == null:
		return UNRESOLVED
	if typeof(value) != TYPE_BOOL:
		return FAIL
	return PASS if bool(value) else FAIL
