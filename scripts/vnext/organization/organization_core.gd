class_name VNextOrganizationCore
extends RefCounted

## Owns only the structural grammar of organizations and their authorization facts.
## Position and appointment IDs are local to their organization; they are not
## VNextStableId values and must never be treated as a new stable-ID kind.

const SNAPSHOT_SCHEMA_ID: String = "vnext_organization_core_v1"

const _ORGANIZATION_FIELDS: Array[String] = [
	"organization_id",
	"organization_kind",
	"primary_place_id",
	"parent_organization_id",
	"active",
	"member_ids",
	"capability_ids",
	"positions",
	"appointments",
]
const _POSITION_FIELDS: Array[String] = [
	"position_id",
	"title",
	"slot_count",
	"capability_ids",
]
const _APPOINTMENT_FIELDS: Array[String] = [
	"appointment_id",
	"person_id",
	"position_id",
	"requires_membership",
]

var _organizations: Dictionary = {}
var _reference_catalog_configured: bool = false
var _reference_catalog: VNextOrganizationReferenceCatalog = null


static func create(
	known_person_ids: Array[String] = [], known_place_ids: Array[String] = []
) -> VNextOrganizationCore:
	var core := VNextOrganizationCore.new()
	if not known_person_ids.is_empty() or not known_place_ids.is_empty():
		if not core.configure_reference_catalog(known_person_ids, known_place_ids):
			return null
	return core


## An empty core is a valid structural registry. It has no external time source.
func is_valid() -> bool:
	return _validate_organizations(_organizations)


## The external reference catalog is required before any non-empty Person or
## Place reference can be accepted. It remains outside the snapshot and may only
## be configured before organizations are registered.
func configure_reference_catalog(
	person_ids: Array[String], place_ids: Array[String]
) -> bool:
	if not _organizations.is_empty() or _reference_catalog_configured:
		return false
	var candidate_catalog := VNextOrganizationReferenceCatalog.create(person_ids, place_ids)
	if candidate_catalog == null:
		return false
	_reference_catalog_configured = true
	_reference_catalog = candidate_catalog
	return true


func has_reference_catalog() -> bool:
	return _reference_catalog_configured and _reference_catalog != null


func reference_catalog_fingerprint() -> String:
	if not has_reference_catalog():
		return ""
	return _reference_catalog.fingerprint()


func organization_kind_ids() -> Array[String]:
	return VNextOrganizationKindCatalog.ids()


func organization_kind_catalog_fingerprint() -> String:
	return VNextOrganizationKindCatalog.fingerprint()


func known_capability_ids() -> Array[String]:
	return VNextOrganizationCapabilityCatalog.ids()


func capability_catalog_fingerprint() -> String:
	return VNextOrganizationCapabilityCatalog.fingerprint()


func organization_ids() -> Array[String]:
	return _sorted_dictionary_keys(_organizations)


func has_organization(organization_id: String) -> bool:
	return _organizations.has(organization_id)


func organization(organization_id: String) -> Dictionary:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return record.duplicate(true)


func organization_kind(organization_id: String) -> String:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return str(record.get("organization_kind", ""))


func primary_place_id(organization_id: String) -> String:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return str(record.get("primary_place_id", ""))


func parent_organization_id(organization_id: String) -> String:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return str(record.get("parent_organization_id", ""))


func subordinate_organization_ids(organization_id: String) -> Array[String]:
	var output: Array[String] = []
	if not _organizations.has(organization_id):
		return output
	for child_id: String in organization_ids():
		if parent_organization_id(child_id) == organization_id:
			output.append(child_id)
	return output


func is_organization_active(organization_id: String) -> bool:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return bool(record.get("active", false))


func register_organization(
	organization_id: String,
	organization_kind: String,
	primary_place_id_value: String = "",
	parent_organization_id_value: String = "",
	active: bool = true
) -> bool:
	if (
		not _is_valid_organization_id(organization_id)
		or not VNextOrganizationKindCatalog.is_known(organization_kind)
		or _organizations.has(organization_id)
		or not _is_valid_optional_place_id(primary_place_id_value)
		or not _is_valid_optional_parent_id(parent_organization_id_value)
	):
		return false
	if not _is_known_place_id(primary_place_id_value):
		return false
	if (
		not parent_organization_id_value.is_empty()
		and not _organizations.has(parent_organization_id_value)
	):
		return false

	var candidate: Dictionary = {
		"organization_id": organization_id,
		"organization_kind": organization_kind,
		"primary_place_id": primary_place_id_value,
		"parent_organization_id": parent_organization_id_value,
		"active": active,
		"member_ids": [],
		"capability_ids": [],
		"positions": {},
		"appointments": {},
	}
	return _commit_organization_state(organization_id, candidate)


func create_organization(
	organization_id: String,
	organization_kind: String,
	primary_place_id_value: String = "",
	parent_organization_id_value: String = "",
	active: bool = true
) -> bool:
	return register_organization(
		organization_id,
		organization_kind,
		primary_place_id_value,
		parent_organization_id_value,
		active
	)


func set_parent_organization(
	organization_id: String, parent_organization_id_value: String
) -> bool:
	if (
		not _organizations.has(organization_id)
		or not is_organization_active(organization_id)
		or not _is_valid_optional_parent_id(parent_organization_id_value)
	):
		return false
	if (
		not parent_organization_id_value.is_empty()
		and not _organizations.has(parent_organization_id_value)
	):
		return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	candidate["parent_organization_id"] = parent_organization_id_value
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func set_organization_active(organization_id: String, active: bool) -> bool:
	if not _organizations.has(organization_id):
		return false
	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	candidate["active"] = active
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func capability_ids(organization_id: String) -> Array[String]:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return _copy_sorted_string_array(record.get("capability_ids", []))


func define_capability(organization_id: String, capability_id: String) -> bool:
	if not _is_mutable_organization(organization_id) or not _is_valid_capability_id(capability_id):
		return false
	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	var capabilities: Array[String] = _copy_sorted_string_array(
		candidate.get("capability_ids", [])
	)
	if capabilities.has(capability_id):
		return false
	capabilities.append(capability_id)
	capabilities.sort()
	candidate["capability_ids"] = capabilities
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func position_ids(organization_id: String) -> Array[String]:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	var positions: Dictionary = record.get("positions", {}) as Dictionary
	return _sorted_dictionary_keys(positions)


func position(organization_id: String, position_id: String) -> Dictionary:
	var organization_record: Dictionary = (
		_organizations.get(organization_id, {}) as Dictionary
	)
	var positions: Dictionary = organization_record.get("positions", {}) as Dictionary
	var record: Dictionary = positions.get(position_id, {}) as Dictionary
	return record.duplicate(true)


func define_position(
	organization_id: String,
	position_id: String,
	title: String,
	slot_count: int,
	granted_capability_ids: Array[String] = []
) -> bool:
	if (
		not _is_mutable_organization(organization_id)
		or not _is_valid_local_id(position_id)
		or title.is_empty()
		or slot_count <= 0
		or _has_position(organization_id, position_id)
	):
		return false
	if not _are_valid_unique_capabilities(granted_capability_ids):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var known_capabilities: Array[String] = _copy_sorted_string_array(
		organization_record.get("capability_ids", [])
	)
	for capability_id: String in granted_capability_ids:
		if not known_capabilities.has(capability_id):
			return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	var positions: Dictionary = candidate.get("positions", {}) as Dictionary
	positions[position_id] = {
		"position_id": position_id,
		"title": title,
		"slot_count": slot_count,
		"capability_ids": _copy_sorted_string_array(granted_capability_ids),
	}
	candidate["positions"] = positions
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func grant_capability(
	organization_id: String, position_id: String, capability_id: String
) -> bool:
	if (
		not _is_mutable_organization(organization_id)
		or not _is_valid_capability_id(capability_id)
	):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var positions: Dictionary = organization_record.get("positions", {}) as Dictionary
	if not positions.has(position_id):
		return false
	var known_capabilities: Array[String] = _copy_sorted_string_array(
		organization_record.get("capability_ids", [])
	)
	if not known_capabilities.has(capability_id):
		return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	positions = candidate.get("positions", {}) as Dictionary
	var position_record: Dictionary = (positions[position_id] as Dictionary).duplicate(true)
	var granted_capabilities: Array[String] = _copy_sorted_string_array(
		position_record.get("capability_ids", [])
	)
	if granted_capabilities.has(capability_id):
		return false
	granted_capabilities.append(capability_id)
	granted_capabilities.sort()
	position_record["capability_ids"] = granted_capabilities
	positions[position_id] = position_record
	candidate["positions"] = positions
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func revoke_capability(
	organization_id: String, position_id: String, capability_id: String
) -> bool:
	if not _is_mutable_organization(organization_id):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var positions: Dictionary = organization_record.get("positions", {}) as Dictionary
	if not positions.has(position_id):
		return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	positions = candidate.get("positions", {}) as Dictionary
	var position_record: Dictionary = (positions[position_id] as Dictionary).duplicate(true)
	var granted_capabilities: Array[String] = _copy_sorted_string_array(
		position_record.get("capability_ids", [])
	)
	if not granted_capabilities.has(capability_id):
		return false
	granted_capabilities.erase(capability_id)
	position_record["capability_ids"] = granted_capabilities
	positions[position_id] = position_record
	candidate["positions"] = positions
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func member_ids(organization_id: String) -> Array[String]:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	return _copy_sorted_string_array(record.get("member_ids", []))


## Derived from the authoritative organization records on every call. The
## detached result cannot mutate membership state and is sorted by organization.
func memberships_for_person(person_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not _is_known_person_id(person_id):
		return output
	for organization_id: String in organization_ids():
		if member_ids(organization_id).has(person_id):
			output.append({
				"organization_id": organization_id,
				"person_id": person_id,
			})
	return output


func is_member(organization_id: String, person_id: String) -> bool:
	if not _is_valid_person_id(person_id):
		return false
	return member_ids(organization_id).has(person_id)


func add_member(organization_id: String, person_id: String) -> bool:
	if (
		not _is_mutable_organization(organization_id)
		or not _is_valid_person_id(person_id)
		or not _is_known_person_id(person_id)
	):
		return false
	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	var members: Array[String] = _copy_sorted_string_array(candidate.get("member_ids", []))
	if members.has(person_id):
		return false
	members.append(person_id)
	members.sort()
	candidate["member_ids"] = members
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func remove_member(organization_id: String, person_id: String) -> bool:
	if not _is_mutable_organization(organization_id):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var members: Array[String] = _copy_sorted_string_array(
		organization_record.get("member_ids", [])
	)
	if not members.has(person_id):
		return false

	var appointments: Dictionary = organization_record.get("appointments", {}) as Dictionary
	for appointment_id: String in _sorted_dictionary_keys(appointments):
		var appointment_record: Dictionary = appointments[appointment_id] as Dictionary
		if (
			str(appointment_record.get("person_id", "")) == person_id
			and bool(appointment_record.get("requires_membership", false))
		):
			return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	members = _copy_sorted_string_array(candidate.get("member_ids", []))
	members.erase(person_id)
	candidate["member_ids"] = members
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func appointment_ids(organization_id: String) -> Array[String]:
	var record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	var appointments: Dictionary = record.get("appointments", {}) as Dictionary
	return _sorted_dictionary_keys(appointments)


func appointment(organization_id: String, appointment_id: String) -> Dictionary:
	var organization_record: Dictionary = (
		_organizations.get(organization_id, {}) as Dictionary
	)
	var appointments: Dictionary = organization_record.get("appointments", {}) as Dictionary
	var record: Dictionary = appointments.get(appointment_id, {}) as Dictionary
	return record.duplicate(true)


## Derived reverse view ordered by organization ID and then appointment ID.
## Appointment dictionaries are deep-detached from the authoritative records.
func appointments_for_person(person_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not _is_known_person_id(person_id):
		return output
	for organization_id: String in organization_ids():
		for appointment_id: String in appointment_ids(organization_id):
			var record: Dictionary = appointment(organization_id, appointment_id)
			if str(record.get("person_id", "")) != person_id:
				continue
			record["organization_id"] = organization_id
			output.append(record)
	return output


func create_appointment(
	organization_id: String,
	appointment_id: String,
	person_id: String,
	position_id: String,
	requires_membership: bool = true
) -> bool:
	if (
		not _is_mutable_organization(organization_id)
		or not _is_valid_local_id(appointment_id)
		or not _is_valid_person_id(person_id)
		or not _is_known_person_id(person_id)
	):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var positions: Dictionary = organization_record.get("positions", {}) as Dictionary
	if not positions.has(position_id):
		return false
	if requires_membership and not is_member(organization_id, person_id):
		return false
	var appointments: Dictionary = organization_record.get("appointments", {}) as Dictionary
	if appointments.has(appointment_id):
		return false
	for existing_id: String in _sorted_dictionary_keys(appointments):
		var existing: Dictionary = appointments[existing_id] as Dictionary
		if str(existing.get("person_id", "")) == person_id:
			return false
	var position_record: Dictionary = positions[position_id] as Dictionary
	var slot_count: int = int(position_record.get("slot_count", 0))
	var holder_count: int = 0
	for existing_id: String in _sorted_dictionary_keys(appointments):
		var existing: Dictionary = appointments[existing_id] as Dictionary
		if str(existing.get("position_id", "")) == position_id:
			holder_count += 1
	if holder_count >= slot_count:
		return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	appointments = candidate.get("appointments", {}) as Dictionary
	appointments[appointment_id] = {
		"appointment_id": appointment_id,
		"person_id": person_id,
		"position_id": position_id,
		"requires_membership": requires_membership,
	}
	candidate["appointments"] = appointments
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func appoint_person(
	organization_id: String,
	appointment_id: String,
	person_id: String,
	position_id: String,
	requires_membership: bool = true
) -> bool:
	return create_appointment(
		organization_id,
		appointment_id,
		person_id,
		position_id,
		requires_membership
	)


func remove_appointment(organization_id: String, appointment_id: String) -> bool:
	if not _is_mutable_organization(organization_id):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var appointments: Dictionary = organization_record.get("appointments", {}) as Dictionary
	if not appointments.has(appointment_id):
		return false

	var candidate_state: Dictionary = _organizations.duplicate(true)
	var candidate: Dictionary = (
		candidate_state[organization_id] as Dictionary
	).duplicate(true)
	appointments = candidate.get("appointments", {}) as Dictionary
	appointments.erase(appointment_id)
	candidate["appointments"] = appointments
	candidate_state[organization_id] = candidate
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func has_capability(
	person_id: String, organization_id: String, capability_id: String
) -> bool:
	if (
		not _is_valid_person_id(person_id)
		or not _is_known_person_id(person_id)
		or not _is_valid_organization_id(organization_id)
		or not _is_valid_capability_id(capability_id)
		or not _organizations.has(organization_id)
	):
		return false
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	if not bool(organization_record.get("active", false)):
		return false
	var capabilities: Array[String] = _copy_sorted_string_array(
		organization_record.get("capability_ids", [])
	)
	if not capabilities.has(capability_id):
		return false
	var members: Array[String] = _copy_sorted_string_array(
		organization_record.get("member_ids", [])
	)
	var positions: Dictionary = organization_record.get("positions", {}) as Dictionary
	var appointments: Dictionary = organization_record.get("appointments", {}) as Dictionary
	for appointment_id: String in _sorted_dictionary_keys(appointments):
		var appointment_record: Dictionary = appointments[appointment_id] as Dictionary
		if str(appointment_record.get("person_id", "")) != person_id:
			continue
		if (
			bool(appointment_record.get("requires_membership", false))
			and not members.has(person_id)
		):
			continue
		var position_id: String = str(appointment_record.get("position_id", ""))
		var position_record: Dictionary = positions.get(position_id, {}) as Dictionary
		var granted: Array[String] = _copy_sorted_string_array(
			position_record.get("capability_ids", [])
		)
		if granted.has(capability_id):
			return true
	return false


func is_authorized(
	person_id: String, organization_id: String, capability_id: String
) -> bool:
	return has_capability(person_id, organization_id, capability_id)


func capabilities_for_person(
	person_id: String, organization_id: String
) -> Array[String]:
	var output: Array[String] = []
	if (
		not _is_valid_person_id(person_id)
		or not _is_known_person_id(person_id)
		or not _is_valid_organization_id(organization_id)
		or not _organizations.has(organization_id)
		or not is_organization_active(organization_id)
	):
		return output
	var organization_record: Dictionary = _organizations[organization_id] as Dictionary
	var declared: Array[String] = _copy_sorted_string_array(
		organization_record.get("capability_ids", [])
	)
	for capability_id: String in declared:
		if has_capability(person_id, organization_id, capability_id):
			output.append(capability_id)
	output.sort()
	return output


func snapshot() -> Dictionary:
	var saved_organizations: Array[Dictionary] = []
	for organization_id: String in organization_ids():
		saved_organizations.append(_snapshot_organization(_organizations[organization_id] as Dictionary))
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"organizations": saved_organizations,
	}


## Decodes and validates the complete candidate before replacing live state.
## No field of the current state is changed on any rejection path.
func restore(snapshot_value: Dictionary) -> bool:
	if not _has_exact_fields(snapshot_value, ["schema_id", "organizations"]):
		return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	var raw_organizations: Variant = snapshot_value.get("organizations")
	if typeof(raw_organizations) != TYPE_ARRAY:
		return false

	var candidate_state: Dictionary = {}
	for raw_organization: Variant in raw_organizations as Array:
		if typeof(raw_organization) != TYPE_DICTIONARY:
			return false
		var decoded: Dictionary = _decode_organization(raw_organization as Dictionary)
		if decoded.is_empty():
			return false
		var organization_id: String = str(decoded.get("organization_id", ""))
		if candidate_state.has(organization_id):
			return false
		candidate_state[organization_id] = decoded

	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func _commit_organization_state(
	organization_id: String, candidate_organization: Dictionary
) -> bool:
	var candidate_state: Dictionary = _organizations.duplicate(true)
	candidate_state[organization_id] = candidate_organization
	if not _validate_organizations(candidate_state):
		return false
	_organizations = candidate_state
	return true


func _is_mutable_organization(organization_id: String) -> bool:
	return _organizations.has(organization_id) and is_organization_active(organization_id)


func _has_position(organization_id: String, position_id: String) -> bool:
	var organization_record: Dictionary = _organizations.get(organization_id, {}) as Dictionary
	var positions: Dictionary = organization_record.get("positions", {}) as Dictionary
	return positions.has(position_id)


func _decode_organization(raw_organization: Dictionary) -> Dictionary:
	if not _has_exact_fields(raw_organization, _ORGANIZATION_FIELDS):
		return {}
	if typeof(raw_organization.get("organization_id")) != TYPE_STRING:
		return {}
	if typeof(raw_organization.get("organization_kind")) != TYPE_STRING:
		return {}
	if typeof(raw_organization.get("primary_place_id")) != TYPE_STRING:
		return {}
	if typeof(raw_organization.get("parent_organization_id")) != TYPE_STRING:
		return {}
	if typeof(raw_organization.get("active")) != TYPE_BOOL:
		return {}

	var organization_id: String = str(raw_organization.get("organization_id"))
	var organization_kind: String = str(raw_organization.get("organization_kind"))
	var primary_place_id_value: String = str(raw_organization.get("primary_place_id"))
	var parent_id: String = str(raw_organization.get("parent_organization_id"))
	if (
		not _is_valid_organization_id(organization_id)
		or not VNextOrganizationKindCatalog.is_known(organization_kind)
		or not _is_valid_optional_place_id(primary_place_id_value)
		or not _is_valid_optional_parent_id(parent_id)
		or not _is_known_place_id(primary_place_id_value)
	):
		return {}

	var members: Array[String] = []
	var raw_members: Variant = raw_organization.get("member_ids")
	if typeof(raw_members) != TYPE_ARRAY:
		return {}
	for raw_member: Variant in raw_members as Array:
		if typeof(raw_member) != TYPE_STRING:
			return {}
		var person_id: String = str(raw_member)
		if (
			not _is_valid_person_id(person_id)
			or not _is_known_person_id(person_id)
			or members.has(person_id)
		):
			return {}
		members.append(person_id)
	members.sort()

	var capabilities: Array[String] = []
	var raw_capabilities: Variant = raw_organization.get("capability_ids")
	if typeof(raw_capabilities) != TYPE_ARRAY:
		return {}
	for raw_capability: Variant in raw_capabilities as Array:
		if typeof(raw_capability) != TYPE_STRING:
			return {}
		var capability_id: String = str(raw_capability)
		if not _is_valid_capability_id(capability_id) or capabilities.has(capability_id):
			return {}
		capabilities.append(capability_id)
	capabilities.sort()

	var positions: Dictionary = {}
	var raw_positions: Variant = raw_organization.get("positions")
	if typeof(raw_positions) != TYPE_ARRAY:
		return {}
	for raw_position: Variant in raw_positions as Array:
		if typeof(raw_position) != TYPE_DICTIONARY:
			return {}
		var decoded_position: Dictionary = _decode_position(raw_position as Dictionary)
		if decoded_position.is_empty():
			return {}
		var position_id: String = str(decoded_position.get("position_id", ""))
		if positions.has(position_id):
			return {}
		positions[position_id] = decoded_position

	var appointments: Dictionary = {}
	var raw_appointments: Variant = raw_organization.get("appointments")
	if typeof(raw_appointments) != TYPE_ARRAY:
		return {}
	for raw_appointment: Variant in raw_appointments as Array:
		if typeof(raw_appointment) != TYPE_DICTIONARY:
			return {}
		var decoded_appointment: Dictionary = _decode_appointment(raw_appointment as Dictionary)
		if decoded_appointment.is_empty():
			return {}
		var appointment_id: String = str(decoded_appointment.get("appointment_id", ""))
		if appointments.has(appointment_id):
			return {}
		appointments[appointment_id] = decoded_appointment

	return {
		"organization_id": organization_id,
		"organization_kind": organization_kind,
		"primary_place_id": primary_place_id_value,
		"parent_organization_id": parent_id,
		"active": bool(raw_organization.get("active")),
		"member_ids": members,
		"capability_ids": capabilities,
		"positions": positions,
		"appointments": appointments,
	}


func _decode_position(raw_position: Dictionary) -> Dictionary:
	if not _has_exact_fields(raw_position, _POSITION_FIELDS):
		return {}
	if (
		typeof(raw_position.get("position_id")) != TYPE_STRING
		or typeof(raw_position.get("title")) != TYPE_STRING
	):
		return {}
	var position_id: String = str(raw_position.get("position_id"))
	var title: String = str(raw_position.get("title"))
	var slot_count: int = _normalize_positive_int(raw_position.get("slot_count"))
	if not _is_valid_local_id(position_id) or title.is_empty() or slot_count <= 0:
		return {}

	var capabilities: Array[String] = []
	var raw_capabilities: Variant = raw_position.get("capability_ids")
	if typeof(raw_capabilities) != TYPE_ARRAY:
		return {}
	for raw_capability: Variant in raw_capabilities as Array:
		if typeof(raw_capability) != TYPE_STRING:
			return {}
		var capability_id: String = str(raw_capability)
		if not _is_valid_capability_id(capability_id) or capabilities.has(capability_id):
			return {}
		capabilities.append(capability_id)
	capabilities.sort()

	return {
		"position_id": position_id,
		"title": title,
		"slot_count": slot_count,
		"capability_ids": capabilities,
	}


func _decode_appointment(raw_appointment: Dictionary) -> Dictionary:
	if not _has_exact_fields(raw_appointment, _APPOINTMENT_FIELDS):
		return {}
	if (
		typeof(raw_appointment.get("appointment_id")) != TYPE_STRING
		or typeof(raw_appointment.get("person_id")) != TYPE_STRING
		or typeof(raw_appointment.get("position_id")) != TYPE_STRING
		or typeof(raw_appointment.get("requires_membership")) != TYPE_BOOL
	):
		return {}
	var appointment_id: String = str(raw_appointment.get("appointment_id"))
	var person_id: String = str(raw_appointment.get("person_id"))
	var position_id: String = str(raw_appointment.get("position_id"))
	if (
		not _is_valid_local_id(appointment_id)
		or not _is_valid_person_id(person_id)
		or not _is_known_person_id(person_id)
		or not _is_valid_local_id(position_id)
	):
		return {}
	return {
		"appointment_id": appointment_id,
		"person_id": person_id,
		"position_id": position_id,
		"requires_membership": bool(raw_appointment.get("requires_membership")),
	}


func _validate_organizations(candidate_state: Dictionary) -> bool:
	var organization_ids_value: Array[String] = _sorted_dictionary_keys(candidate_state)
	for organization_id: String in organization_ids_value:
		var raw_record: Variant = candidate_state.get(organization_id)
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = raw_record as Dictionary
		if not _has_exact_fields(record, _ORGANIZATION_FIELDS):
			return false
		if (
			record.get("organization_id") != organization_id
			or not _is_valid_organization_id(organization_id)
			or typeof(record.get("organization_kind")) != TYPE_STRING
			or not VNextOrganizationKindCatalog.is_known(str(record.get("organization_kind")))
			or typeof(record.get("primary_place_id")) != TYPE_STRING
			or not _is_valid_optional_place_id(str(record.get("primary_place_id")))
			or not _is_known_place_id(str(record.get("primary_place_id")))
			or typeof(record.get("parent_organization_id")) != TYPE_STRING
			or not _is_valid_optional_parent_id(str(record.get("parent_organization_id")))
			or typeof(record.get("active")) != TYPE_BOOL
		):
			return false
		var parent_id: String = str(record.get("parent_organization_id"))
		if not parent_id.is_empty() and not candidate_state.has(parent_id):
			return false

		var members: Array[String] = []
		var raw_members: Variant = record.get("member_ids")
		if typeof(raw_members) != TYPE_ARRAY:
			return false
		for raw_member: Variant in raw_members as Array:
			if typeof(raw_member) != TYPE_STRING:
				return false
			var person_id: String = str(raw_member)
			if (
				not _is_valid_person_id(person_id)
				or not _is_known_person_id(person_id)
				or members.has(person_id)
			):
				return false
			members.append(person_id)

		var capabilities: Array[String] = []
		var raw_capabilities: Variant = record.get("capability_ids")
		if typeof(raw_capabilities) != TYPE_ARRAY:
			return false
		for raw_capability: Variant in raw_capabilities as Array:
			if typeof(raw_capability) != TYPE_STRING:
				return false
			var capability_id: String = str(raw_capability)
			if not _is_valid_capability_id(capability_id) or capabilities.has(capability_id):
				return false
			capabilities.append(capability_id)

		var positions: Dictionary = record.get("positions", {}) as Dictionary
		if typeof(record.get("positions")) != TYPE_DICTIONARY:
			return false
		for position_id: String in _sorted_dictionary_keys(positions):
			var raw_position: Variant = positions.get(position_id)
			if typeof(raw_position) != TYPE_DICTIONARY:
				return false
			var position_record: Dictionary = raw_position as Dictionary
			if not _has_exact_fields(position_record, _POSITION_FIELDS):
				return false
			var position_capabilities: Array[String] = []
			if (
				position_record.get("position_id") != position_id
				or not _is_valid_local_id(position_id)
				or typeof(position_record.get("title")) != TYPE_STRING
				or str(position_record.get("title")).is_empty()
				or typeof(position_record.get("slot_count")) != TYPE_INT
				or int(position_record.get("slot_count")) <= 0
				or typeof(position_record.get("capability_ids")) != TYPE_ARRAY
			):
				return false
			for raw_position_capability: Variant in position_record.get("capability_ids") as Array:
				if typeof(raw_position_capability) != TYPE_STRING:
					return false
				var position_capability_id: String = str(raw_position_capability)
				if (
					not _is_valid_capability_id(position_capability_id)
					or not capabilities.has(position_capability_id)
					or position_capabilities.has(position_capability_id)
				):
					return false
				position_capabilities.append(position_capability_id)

		var appointments: Dictionary = record.get("appointments", {}) as Dictionary
		if typeof(record.get("appointments")) != TYPE_DICTIONARY:
			return false
		var appointment_people: Dictionary = {}
		var position_holders: Dictionary = {}
		for appointment_id: String in _sorted_dictionary_keys(appointments):
			var raw_appointment: Variant = appointments.get(appointment_id)
			if typeof(raw_appointment) != TYPE_DICTIONARY:
				return false
			var appointment_record: Dictionary = raw_appointment as Dictionary
			if not _has_exact_fields(appointment_record, _APPOINTMENT_FIELDS):
				return false
			var appointment_person_id: String = str(appointment_record.get("person_id", ""))
			var appointment_position_id: String = str(appointment_record.get("position_id", ""))
			if (
				appointment_record.get("appointment_id") != appointment_id
				or not _is_valid_local_id(appointment_id)
				or not _is_valid_person_id(appointment_person_id)
				or not _is_known_person_id(appointment_person_id)
				or not positions.has(appointment_position_id)
				or typeof(appointment_record.get("requires_membership")) != TYPE_BOOL
				or appointment_people.has(appointment_person_id)
			):
				return false
			if (
				bool(appointment_record.get("requires_membership"))
				and not members.has(appointment_person_id)
			):
				return false
			appointment_people[appointment_person_id] = true
			position_holders[appointment_position_id] = int(
				position_holders.get(appointment_position_id, 0)
			) + 1

		for position_id: String in _sorted_dictionary_keys(position_holders):
			var position_record: Dictionary = positions[position_id] as Dictionary
			if int(position_holders[position_id]) > int(position_record.get("slot_count", 0)):
				return false

	return not _has_hierarchy_cycle(candidate_state, organization_ids_value)


func _has_hierarchy_cycle(
	candidate_state: Dictionary, organization_ids_value: Array[String]
) -> bool:
	for start_id: String in organization_ids_value:
		var visited: Dictionary = {}
		var current_id: String = start_id
		while not current_id.is_empty():
			if visited.has(current_id):
				return true
			visited[current_id] = true
			if not candidate_state.has(current_id):
				return true
			var record: Dictionary = candidate_state[current_id] as Dictionary
			current_id = str(record.get("parent_organization_id", ""))
	return false


func _snapshot_organization(record: Dictionary) -> Dictionary:
	var positions: Array[Dictionary] = []
	var position_records: Dictionary = record.get("positions", {}) as Dictionary
	for position_id: String in _sorted_dictionary_keys(position_records):
		var position_record: Dictionary = position_records[position_id] as Dictionary
		positions.append({
			"position_id": position_id,
			"title": str(position_record.get("title", "")),
			"slot_count": int(position_record.get("slot_count", 0)),
			"capability_ids": _copy_sorted_string_array(
				position_record.get("capability_ids", [])
			),
		})

	var appointments: Array[Dictionary] = []
	var appointment_records: Dictionary = record.get("appointments", {}) as Dictionary
	for appointment_id: String in _sorted_dictionary_keys(appointment_records):
		var appointment_record: Dictionary = appointment_records[appointment_id] as Dictionary
		appointments.append({
			"appointment_id": appointment_id,
			"person_id": str(appointment_record.get("person_id", "")),
			"position_id": str(appointment_record.get("position_id", "")),
			"requires_membership": bool(
				appointment_record.get("requires_membership", false)
			),
		})

	return {
		"organization_id": str(record.get("organization_id", "")),
		"organization_kind": str(record.get("organization_kind", "")),
		"primary_place_id": str(record.get("primary_place_id", "")),
		"parent_organization_id": str(record.get("parent_organization_id", "")),
		"active": bool(record.get("active", false)),
		"member_ids": _copy_sorted_string_array(record.get("member_ids", [])),
		"capability_ids": _copy_sorted_string_array(record.get("capability_ids", [])),
		"positions": positions,
		"appointments": appointments,
	}


func _is_valid_organization_id(candidate_value: String) -> bool:
	return (
		VNextStableId.is_valid(candidate_value)
		and VNextStableId.kind_of(candidate_value) == "organization"
	)


func _is_valid_person_id(candidate_value: String) -> bool:
	return (
		VNextStableId.is_valid(candidate_value)
		and VNextStableId.kind_of(candidate_value) == "person"
	)


func _is_valid_place_id(candidate_value: String) -> bool:
	return (
		VNextStableId.is_valid(candidate_value)
		and VNextStableId.kind_of(candidate_value) == "place"
	)


func _is_valid_optional_place_id(candidate_value: String) -> bool:
	return candidate_value.is_empty() or _is_valid_place_id(candidate_value)


func _is_valid_optional_parent_id(candidate_value: String) -> bool:
	return candidate_value.is_empty() or _is_valid_organization_id(candidate_value)


func _is_known_person_id(person_id: String) -> bool:
	return has_reference_catalog() and _reference_catalog.has_person(person_id)


func _is_known_place_id(place_id: String) -> bool:
	return place_id.is_empty() or (
		has_reference_catalog() and _reference_catalog.has_place(place_id)
	)


func _is_valid_local_id(candidate_value: String) -> bool:
	if candidate_value.is_empty():
		return false
	for character_index: int in candidate_value.length():
		var character: String = candidate_value.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true


func _is_valid_capability_id(candidate_value: String) -> bool:
	return VNextOrganizationCapabilityCatalog.is_known(candidate_value)


func _are_valid_unique_capabilities(capability_ids_value: Array[String]) -> bool:
	var seen: Dictionary = {}
	for capability_id: String in capability_ids_value:
		if not _is_valid_capability_id(capability_id) or seen.has(capability_id):
			return false
		seen[capability_id] = true
	return true


func _normalize_positive_int(candidate_value: Variant) -> int:
	var candidate_type: int = typeof(candidate_value)
	if candidate_type == TYPE_INT:
		var candidate_int: int = int(candidate_value)
		return candidate_int if candidate_int > 0 else -1
	if candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float) or candidate_float <= 0.0:
			return -1
		if candidate_float != floor(candidate_float):
			return -1
		return int(candidate_float)
	return -1


func _copy_sorted_string_array(raw_value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(raw_value) != TYPE_ARRAY:
		return output
	for raw_item: Variant in raw_value as Array:
		if typeof(raw_item) == TYPE_STRING:
			output.append(str(raw_item))
	output.sort()
	return output


func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for raw_key: Variant in source.keys():
		if typeof(raw_key) == TYPE_STRING:
			output.append(str(raw_key))
	output.sort()
	return output


func _has_exact_fields(record: Dictionary, fields: Array[String]) -> bool:
	if record.size() != fields.size():
		return false
	for field: String in fields:
		if not record.has(field):
			return false
	return true
