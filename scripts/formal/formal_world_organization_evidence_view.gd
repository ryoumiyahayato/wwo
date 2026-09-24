class_name FormalWorldOrganizationEvidenceView
extends RefCounted

## Detached read boundary for immutable production Organization composition evidence.

var _snapshot: Dictionary = {}
var _records: Dictionary = {}


func _init(snapshot_value: Dictionary = {}) -> void:
	_snapshot = snapshot_value.duplicate(true)
	var raw_records: Variant = _snapshot.get("organizations", [])
	if not raw_records is Array:
		return
	for raw_record: Variant in raw_records as Array:
		if not raw_record is Dictionary:
			continue
		var record := (raw_record as Dictionary).duplicate(true)
		var organization_id := str(record.get("organization_id", ""))
		if not organization_id.is_empty():
			_records[organization_id] = record


func fingerprint() -> String:
	return str(_snapshot.get("fingerprint", ""))


func organization_ids() -> Array[String]:
	var output: Array[String] = []
	for raw_id: Variant in _records.keys():
		output.append(str(raw_id))
	output.sort()
	return output


func organization_count() -> int:
	return _records.size()


func has_organization(organization_id: String) -> bool:
	return _records.has(organization_id)


func organization_basis(organization_id: String) -> Dictionary:
	return (
		(_records.get(organization_id, {}) as Dictionary)
		.duplicate(true)
	)


func represented_polity_id(organization_id: String) -> String:
	return str(organization_basis(organization_id).get("represented_polity_id", ""))


func basis_class(organization_id: String) -> String:
	return str(organization_basis(organization_id).get("basis_class", ""))


func coverage_summary() -> Dictionary:
	var value: Variant = _snapshot.get("coverage", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)
