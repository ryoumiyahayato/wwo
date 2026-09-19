class_name FormalWorldOrganizationEvidenceCatalog
extends RefCounted

## Immutable composition evidence for production Formal organizations.
## This catalog owns only why an Organization should exist. Runtime Organization
## state remains solely in VNextOrganizationCore.

const DEFAULT_PATH: String = "res://data/vnext/organizations/formal_organization_composition_1900.json"
const SCHEMA_ID: String = "formal_organization_composition_v1"
const BASIS_INFERRED: String = "institutional_inference"

var initialization_error: String = ""
var _configured: bool = false
var _fingerprint: String = ""
var _records_by_organization_id: Dictionary = {}
var _sorted_organization_ids: Array[String] = []
var _coverage: Dictionary = {}


func configure(
	historical_evidence: HistoricalPoliticalEvidenceCatalog,
	path: String = DEFAULT_PATH
) -> bool:
	if _configured:
		return _fail("Formal Organization evidence is already initialized")
	initialization_error = ""
	_fingerprint = ""
	_records_by_organization_id.clear()
	_sorted_organization_ids.clear()
	_coverage.clear()
	if historical_evidence == null or not historical_evidence.is_configured():
		return _fail("Formal Organization evidence requires configured historical political evidence")

	var source_text := FileAccess.get_file_as_string(path)
	if source_text.is_empty():
		return _fail("Formal Organization composition catalog cannot be read: %s" % path)
	var parser := JSON.new()
	if parser.parse(source_text) != OK or not parser.data is Dictionary:
		return _fail("Formal Organization composition catalog is invalid JSON: %s" % path)
	var document := parser.data as Dictionary
	if str(document.get("schema_id", "")) != SCHEMA_ID:
		return _fail("Formal Organization composition schema is invalid")
	var rule_value: Variant = document.get("governing_institution_rule", {})
	if not rule_value is Dictionary:
		return _fail("Formal Organization composition governing rule is missing")
	var rule := rule_value as Dictionary
	if (
		str(rule.get("eligible_status", "")) != "sovereign"
		or str(rule.get("eligible_relationship", "")) != "independent_state"
		or str(rule.get("organization_kind", "")) != "government_body"
		or str(rule.get("basis_class", "")) != BASIS_INFERRED
		or str(rule.get("id_prefix", "")) != "organization:gov_"
	):
		return _fail("Formal Organization governing inference rule is unsupported")

	var deferred_count := 0
	for source_id: String in historical_evidence.source_ids():
		var political_record := historical_evidence.record(source_id)
		var eligible := (
			str(political_record.get("status", "")) == str(rule.get("eligible_status", ""))
			and str(political_record.get("relationship", "")) == str(rule.get("eligible_relationship", ""))
		)
		if not eligible:
			deferred_count += 1
			continue
		var organization_id := str(rule.get("id_prefix", "")) + source_id
		if _records_by_organization_id.has(organization_id):
			return _fail("Formal Organization deterministic ID collision: %s" % organization_id)
		var record: Dictionary = {
			"organization_id": organization_id,
			"organization_kind": str(rule.get("organization_kind", "")),
			"represented_polity_id": source_id,
			"basis_class": BASIS_INFERRED,
			"basis": "source_backed_institutional_inference",
			"inference": str(rule.get("inference", "")),
			"source_fact_ids": ["political_identity:" + source_id],
			"source_historical_ids": [source_id],
			"inferred_fields": [
				"organization_identity",
				"organization_kind",
			],
			"rule_version": str(document.get("rule_version", "")),
			"historical_exact_name_claimed": false,
			"prototype_source": false,
		}
		_records_by_organization_id[organization_id] = record
		_sorted_organization_ids.append(organization_id)

	_sorted_organization_ids.sort()
	_coverage = {
		"political_unit_count": historical_evidence.record_count(),
		"eligible_governing_institution_count": _sorted_organization_ids.size(),
		"materialized_organization_count": _sorted_organization_ids.size(),
		"historical_a_count": 0,
		"inferred_b_count": _sorted_organization_ids.size(),
		"generated_c_count": 0,
		"deferred_for_evidence_count": deferred_count,
		"prototype_d_count": 0,
	}
	_fingerprint = JSON.stringify({
		"schema_id": SCHEMA_ID,
		"rule_source_hash": source_text.sha256_text(),
		"historical_evidence_fingerprint": historical_evidence.fingerprint(),
		"records": records(),
	}).sha256_text()
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func fingerprint() -> String:
	return _fingerprint


func organization_ids() -> Array[String]:
	return _sorted_organization_ids.duplicate()


func organization_count() -> int:
	return _sorted_organization_ids.size()


func has_organization(organization_id: String) -> bool:
	return _records_by_organization_id.has(organization_id)


func record(organization_id: String) -> Dictionary:
	return (
		(_records_by_organization_id.get(organization_id, {}) as Dictionary)
		.duplicate(true)
	)


func records() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for organization_id: String in _sorted_organization_ids:
		output.append(record(organization_id))
	return output


func coverage_summary() -> Dictionary:
	return _coverage.duplicate(true)


func read_only_snapshot() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"fingerprint": _fingerprint,
		"organizations": records(),
		"coverage": coverage_summary(),
	}


func _fail(message: String) -> bool:
	initialization_error = message
	_configured = false
	return false
