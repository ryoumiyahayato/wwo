class_name FormalWorldOrganizationEvidenceView
extends RefCounted
## Detached read boundary for immutable Formal Organization composition evidence.

var _configured: bool = false
var _revision: String = ""
var _fingerprint: String = ""
var _historical_evidence_fingerprint: String = ""
var _records: Dictionary = {}
var _coverage: Dictionary = {}
var _provenance: Dictionary = {}


func _init(snapshot: Dictionary = {}) -> void:
	_configured = bool(snapshot.get("configured", false))
	_revision = str(snapshot.get("revision", ""))
	_fingerprint = str(snapshot.get("fingerprint", ""))
	_historical_evidence_fingerprint = str(
		snapshot.get("historical_evidence_fingerprint", "")
	)
	for raw_record: Variant in snapshot.get("records", []) as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var record := (raw_record as Dictionary).duplicate(true)
		var organization_id := str(record.get("organization_id", ""))
		if not organization_id.is_empty() and not _records.has(organization_id):
			_records[organization_id] = record
	_coverage = (snapshot.get("coverage", {}) as Dictionary).duplicate(true)
	_provenance = (snapshot.get("provenance", {}) as Dictionary).duplicate(true)


func is_configured() -> bool:
	return _configured


func revision() -> String:
	return _revision


func fingerprint() -> String:
	return _fingerprint


func historical_evidence_fingerprint() -> String:
	return _historical_evidence_fingerprint


func organization_ids() -> Array[String]:
	var output: Array[String] = []
	for raw_id: Variant in _records.keys():
		output.append(str(raw_id))
	output.sort()
	return output


func materialized_count() -> int:
	return _records.size()


func has_organization(organization_id: String) -> bool:
	return _records.has(organization_id)


func record(organization_id: String) -> Dictionary:
	return (_records.get(organization_id, {}) as Dictionary).duplicate(true)


func basis(organization_id: String) -> String:
	return str((record(organization_id)).get("basis", ""))


func represented_polity_source_id(organization_id: String) -> String:
	return str((record(organization_id)).get("represented_polity_source_id", ""))


func coverage() -> Dictionary:
	return _coverage.duplicate(true)


func provenance() -> Dictionary:
	return _provenance.duplicate(true)
