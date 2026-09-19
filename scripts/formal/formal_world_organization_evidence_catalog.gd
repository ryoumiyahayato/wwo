class_name FormalWorldOrganizationEvidenceCatalog
extends RefCounted
## Immutable production composition evidence for Formal organizations.
## This catalog derives only institutional-inference records from already-admitted
## historical political identity evidence. It never owns mutable Organization state.

const REVISION: String = "formal_organization_composition_1900_v1"
const CONFIG_PATH: String = (
	"res://data/vnext/organizations/formal_organization_composition_1900.json"
)

var initialization_error: String = ""
var _configured: bool = false
var _fingerprint: String = ""
var _historical_evidence_fingerprint: String = ""
var _records: Array[Dictionary] = []
var _record_by_organization_id: Dictionary = {}
var _coverage: Dictionary = {}
var _provenance: Dictionary = {}


func configure(historical_evidence: HistoricalPoliticalEvidenceView) -> bool:
	if _configured:
		return _fail("Formal Organization evidence is already initialized")
	initialization_error = ""
	if historical_evidence == null or not historical_evidence.is_configured():
		return _fail("Formal Organization evidence requires admitted historical political evidence")

	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return _fail("Formal Organization composition config is missing: %s" % CONFIG_PATH)
	var source_text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(source_text) != OK or not parser.data is Dictionary:
		return _fail("Formal Organization composition config is invalid JSON")
	var document := parser.data as Dictionary
	if str(document.get("schema_id", "")) != REVISION:
		return _fail("Formal Organization composition schema is invalid")
	if str(document.get("snapshot_date", "")) != historical_evidence.snapshot_date():
		return _fail("Formal Organization composition snapshot date does not match political evidence")
	var rules_value: Variant = document.get("rules", [])
	if typeof(rules_value) != TYPE_ARRAY or (rules_value as Array).size() != 1:
		return _fail("Formal Organization composition requires exactly one production rule")
	var rule_value: Variant = (rules_value as Array)[0]
	if typeof(rule_value) != TYPE_DICTIONARY:
		return _fail("Formal Organization composition rule must be an object")
	var rule := (rule_value as Dictionary).duplicate(true)
	if not _validate_rule(rule):
		return false

	var political_unit_count := historical_evidence.record_count()
	var inferred_count := 0
	var deferred_count := 0
	for source_id: String in historical_evidence.source_ids():
		var source_record := historical_evidence.record(source_id)
		if _eligible(source_record, rule):
			var organization_id := VNextStableId.compose(
				"organization",
				str(rule.get("organization_id_prefix", "")) + source_id
			)
			if organization_id.is_empty() or _record_by_organization_id.has(organization_id):
				return _fail(
					"Formal Organization inferred identity is invalid or duplicated: %s"
					% organization_id
				)
			var record := {
				"organization_id": organization_id,
				"organization_kind": str(rule.get("organization_kind", "")),
				"active": bool(rule.get("active", true)),
				"basis": str(rule.get("basis", "")),
				"source_domain": str(rule.get("source_domain", "")),
				"source_fact_id": "political_identity:" + source_id,
				"source_historical_id": source_id,
				"represented_polity_source_id": source_id,
				"inference_rule_id": str(rule.get("rule_id", "")),
				"inference_statement": str(rule.get("inference_statement", "")),
				"primary_place_id": "",
				"parent_organization_id": "",
			}
			_records.append(record)
			_record_by_organization_id[organization_id] = record.duplicate(true)
			inferred_count += 1
		else:
			deferred_count += 1

	_records.sort_custom(Callable(self, "_record_less"))
	_historical_evidence_fingerprint = historical_evidence.fingerprint()
	_fingerprint = (
		source_text
		+ "\n"
		+ _historical_evidence_fingerprint
		+ "\n"
		+ JSON.stringify(_records)
	).sha256_text()
	if _fingerprint.is_empty():
		return _fail("Formal Organization evidence fingerprint could not be computed")
	_coverage = {
		"political_unit_count": political_unit_count,
		"eligible_governing_institution_count": inferred_count,
		"materialized_organization_count": inferred_count,
		"historical_count": 0,
		"inferred_count": inferred_count,
		"generated_count": 0,
		"deferred_for_evidence_count": deferred_count,
		"prototype_count": 0,
	}
	_provenance = {
		"config_path": CONFIG_PATH,
		"historical_evidence_fingerprint": _historical_evidence_fingerprint,
		"basis_policy": "institutional_inference_only",
		"forbidden_source_paths": (
			document.get("forbidden_source_paths", []) as Array
		).duplicate(true),
	}
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func revision() -> String:
	return REVISION if _configured else ""


func fingerprint() -> String:
	return _fingerprint


func historical_evidence_fingerprint() -> String:
	return _historical_evidence_fingerprint


func materialization_records() -> Array[Dictionary]:
	return _records.duplicate(true)


func organization_ids() -> Array[String]:
	var output: Array[String] = []
	for record: Dictionary in _records:
		output.append(str(record.get("organization_id", "")))
	return output


func record(organization_id: String) -> Dictionary:
	return (
		(_record_by_organization_id.get(organization_id, {}) as Dictionary)
		.duplicate(true)
	)


func coverage() -> Dictionary:
	return _coverage.duplicate(true)


func read_only_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"revision": revision(),
		"fingerprint": _fingerprint,
		"historical_evidence_fingerprint": _historical_evidence_fingerprint,
		"records": materialization_records(),
		"coverage": coverage(),
		"provenance": _provenance.duplicate(true),
	}


func _validate_rule(rule: Dictionary) -> bool:
	for field: String in [
		"rule_id",
		"basis",
		"source_domain",
		"eligible_relationship",
		"eligible_status",
		"organization_kind",
		"organization_id_prefix",
		"active",
		"inference_statement",
	]:
		if not rule.has(field):
			return _fail("Formal Organization composition rule is missing field: %s" % field)
	if (
		str(rule.get("basis", "")) != "institutional_inference"
		or str(rule.get("source_domain", "")) != "political_identity"
		or str(rule.get("organization_kind", "")) != "government_body"
		or str(rule.get("organization_id_prefix", "")).is_empty()
		or str(rule.get("rule_id", "")).is_empty()
		or str(rule.get("inference_statement", "")).is_empty()
	):
		return _fail("Formal Organization composition rule violates the production boundary")
	if not VNextOrganizationKindCatalog.is_known(str(rule.get("organization_kind", ""))):
		return _fail("Formal Organization composition rule uses an unknown organization kind")
	return true


func _eligible(source_record: Dictionary, rule: Dictionary) -> bool:
	return (
		str(source_record.get("relationship", ""))
		== str(rule.get("eligible_relationship", ""))
		and str(source_record.get("status", ""))
		== str(rule.get("eligible_status", ""))
	)


func _record_less(first: Dictionary, second: Dictionary) -> bool:
	return (
		str(first.get("organization_id", ""))
		< str(second.get("organization_id", ""))
	)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
