class_name FormalWorldOrganizationView
extends RefCounted

## Detached, immutable-like query boundary for the authoritative OrganizationCore.
## Every record returned to callers is deep-copied.

var _snapshot: Dictionary = {}
var _organizations: Dictionary = {}


func _init(snapshot_value: Dictionary = {}) -> void:
	_snapshot = snapshot_value.duplicate(true)
	var raw_organizations: Variant = _snapshot.get("organizations", [])
	if typeof(raw_organizations) != TYPE_ARRAY:
		return
	for raw_record: Variant in raw_organizations as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		var organization_id: String = str(record.get("organization_id", ""))
		if not organization_id.is_empty():
			_organizations[organization_id] = record


func revision() -> int:
	return int(_snapshot.get("revision", 0))


func state_fingerprint() -> String:
	return str(_snapshot.get("state_fingerprint", ""))


func organization_ids() -> Array[String]:
	var output: Array[String] = []
	for raw_id: Variant in _organizations.keys():
		output.append(str(raw_id))
	output.sort()
	return output


func organization_count() -> int:
	return _organizations.size()


func has_organization(organization_id: String) -> bool:
	return _organizations.has(organization_id)


func organization(organization_id: String) -> Dictionary:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return record.duplicate(true)


func organization_kind(organization_id: String) -> String:
	return str((_record(organization_id)).get("organization_kind", ""))


func primary_place_id(organization_id: String) -> String:
	return str((_record(organization_id)).get("primary_place_id", ""))


func parent_organization_id(organization_id: String) -> String:
	return str((_record(organization_id)).get("parent_organization_id", ""))


func is_organization_active(organization_id: String) -> bool:
	return bool((_record(organization_id)).get("active", false))


func member_ids(organization_id: String) -> Array[String]:
	return _sorted_strings((_record(organization_id)).get("member_ids", []))


func capability_ids(organization_id: String) -> Array[String]:
	return _sorted_strings((_record(organization_id)).get("capability_ids", []))


func position_ids(organization_id: String) -> Array[String]:
	return _record_ids((_record(organization_id)).get("positions", []), "position_id")


func position(organization_id: String, position_id: String) -> Dictionary:
	return _find_record((_record(organization_id)).get("positions", []), "position_id", position_id)


func appointment_ids(organization_id: String) -> Array[String]:
	return _record_ids(
		(_record(organization_id)).get("appointments", []), "appointment_id"
	)


func appointment(organization_id: String, appointment_id: String) -> Dictionary:
	return _find_record(
		(_record(organization_id)).get("appointments", []),
		"appointment_id",
		appointment_id
	)


func memberships_for_person(person_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for organization_id: String in organization_ids():
		if member_ids(organization_id).has(person_id):
			output.append({
				"organization_id": organization_id,
				"person_id": person_id,
			})
	return output


func appointments_for_person(person_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for organization_id: String in organization_ids():
		for appointment_id: String in appointment_ids(organization_id):
			var record := appointment(organization_id, appointment_id)
			if str(record.get("person_id", "")) == person_id:
				record["organization_id"] = organization_id
				output.append(record)
	return output


func has_capability(
	person_id: String, organization_id: String, capability_id: String
) -> bool:
	if not is_organization_active(organization_id):
		return false
	if not capability_ids(organization_id).has(capability_id):
		return false
	for appointment_id: String in appointment_ids(organization_id):
		var appointment_record := appointment(organization_id, appointment_id)
		if str(appointment_record.get("person_id", "")) != person_id:
			continue
		if (
			bool(appointment_record.get("requires_membership", false))
			and not member_ids(organization_id).has(person_id)
		):
			continue
		var position_record := position(
			organization_id, str(appointment_record.get("position_id", ""))
		)
		if _sorted_strings(position_record.get("capability_ids", [])).has(capability_id):
			return true
	return false


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _record(organization_id: String) -> Dictionary:
	return _organizations.get(organization_id, {}) as Dictionary


func _find_record(
	raw_records: Variant, id_field: String, expected_id: String
) -> Dictionary:
	if typeof(raw_records) != TYPE_ARRAY:
		return {}
	for raw_record: Variant in raw_records as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = raw_record as Dictionary
		if str(record.get(id_field, "")) == expected_id:
			return record.duplicate(true)
	return {}


func _record_ids(raw_records: Variant, id_field: String) -> Array[String]:
	var output: Array[String] = []
	if typeof(raw_records) != TYPE_ARRAY:
		return output
	for raw_record: Variant in raw_records as Array:
		if typeof(raw_record) == TYPE_DICTIONARY:
			output.append(str((raw_record as Dictionary).get(id_field, "")))
	output.sort()
	return output


func _sorted_strings(raw_values: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(raw_values) != TYPE_ARRAY:
		return output
	for raw_value: Variant in raw_values as Array:
		if typeof(raw_value) == TYPE_STRING:
			output.append(str(raw_value))
	output.sort()
	return output
