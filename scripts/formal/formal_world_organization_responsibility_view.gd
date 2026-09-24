class_name FormalWorldOrganizationResponsibilityView
extends RefCounted

## Detached immutable-like query boundary for authoritative Organization responsibility state.

var _snapshot: Dictionary = {}
var _records: Dictionary = {}


func _init(snapshot_value: Dictionary = {}) -> void:
	_snapshot = snapshot_value.duplicate(true)
	var raw_records: Variant = _snapshot.get("responsibilities", [])
	if not raw_records is Array:
		return
	for raw_record: Variant in raw_records as Array:
		if not raw_record is Dictionary:
			continue
		var record := (raw_record as Dictionary).duplicate(true)
		var organization_id := str(record.get("organization_id", ""))
		if not organization_id.is_empty():
			_records[organization_id] = record


func state_fingerprint() -> String:
	return str(_snapshot.get("state_fingerprint", ""))


func responsibility_count() -> int:
	return _records.size()


func organization_ids() -> Array[String]:
	var output: Array[String] = []
	for raw_id: Variant in _records.keys():
		output.append(str(raw_id))
	output.sort()
	return output


func responsibilities_for_organization(organization_id: String) -> Array[Dictionary]:
	if not _records.has(organization_id):
		return []
	return [(_records[organization_id] as Dictionary).duplicate(true)]


func responsibility_state(
	organization_id: String,
	responsibility_id: String = FormalWorldOrganizationResponsibilityService.RESPONSIBILITY_ID
) -> Dictionary:
	if responsibility_id != FormalWorldOrganizationResponsibilityService.RESPONSIBILITY_ID:
		return {}
	return (
		(_records.get(organization_id, {}) as Dictionary).duplicate(true)
	)


func responsibility_status(organization_id: String) -> String:
	return str(responsibility_state(organization_id).get("status", ""))


func current_case_summary(organization_id: String) -> Dictionary:
	var record := responsibility_state(organization_id)
	var value: Variant = record.get("current_case", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func count_by_status(status: String) -> int:
	var count := 0
	for organization_id: String in organization_ids():
		if responsibility_status(organization_id) == status:
			count += 1
	return count


func status_counts() -> Dictionary:
	return {
		FormalWorldOrganizationResponsibilityService.STATUS_MONITORING:
			count_by_status(FormalWorldOrganizationResponsibilityService.STATUS_MONITORING),
		FormalWorldOrganizationResponsibilityService.STATUS_ATTENTION_REQUIRED:
			count_by_status(FormalWorldOrganizationResponsibilityService.STATUS_ATTENTION_REQUIRED),
		FormalWorldOrganizationResponsibilityService.STATUS_NO_DETAILED_ECONOMY:
			count_by_status(FormalWorldOrganizationResponsibilityService.STATUS_NO_DETAILED_ECONOMY),
		FormalWorldOrganizationResponsibilityService.STATUS_ORGANIZATION_INACTIVE:
			count_by_status(FormalWorldOrganizationResponsibilityService.STATUS_ORGANIZATION_INACTIVE),
	}


func coverage_summary() -> Dictionary:
	var value: Variant = _snapshot.get("coverage", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)
