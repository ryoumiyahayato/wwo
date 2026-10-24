class_name OrganizationState
extends RefCounted



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
var _revision: int = 0
var _reference_catalog_configured: bool = false
var _reference_catalog: VNextOrganizationReferenceCatalog = null


const SNAPSHOT_SCHEMA_ID: String = "organization_state_v1"

const STAGE_PROPOSAL: String = "proposal"
const STAGE_REPRESENTATION: String = "representation"
const STAGE_DOMAIN_EXECUTION: String = "domain_execution"
const STAGE_DELEGATION: String = "delegation"
const _STAGES: Array[String] = [
	STAGE_PROPOSAL,
	STAGE_REPRESENTATION,
	STAGE_DOMAIN_EXECUTION,
	STAGE_DELEGATION,
]

const _HOLDER_KINDS: Array[String] = ["position", "decision_body", "membership", "person"]
const _DECISION_PARTICIPANT_KINDS: Array[String] = ["person", "position", "membership"]
const _DENOMINATORS: Array[String] = [
	"eligible_weight",
	"cast_weight",
	"eligible_count",
	"cast_count",
]
const _TIE_HANDLING: Array[String] = ["reject", "approve"]
const _VOTE_CHOICES: Array[String] = ["yes", "no", "abstain"]
const _RELATION_TYPES: Array[String] = [
	"grant",
	"appointment",
	"approval",
	"confirmation",
	"veto",
	"supervision",
	"reservation",
	"delegation",
	"exclusive_authority",
	"concurrent_authority",
	"accountability",
	"succession",
	"temporary_command_assignment",
]
const _TRANSFER_TYPES: Array[String] = [
	"appointment_change",
	"delegation",
	"decision_authorization",
	"succession",
	"command_assignment",
	"rule_grant",
	"rule_revoke",
]

var _authority_grants: Dictionary = {}
var _decision_bodies: Dictionary = {}
var _procedures: Dictionary = {}
var _proposals: Dictionary = {}
var _delegations: Dictionary = {}
var _power_relations: Dictionary = {}
var _power_transfers: Dictionary = {}

var _known_person_ids: Array[String]:
	get:
		return _reference_catalog.person_ids() if _reference_catalog != null else []
var _known_place_ids: Array[String]:
	get:
		return _reference_catalog.place_ids() if _reference_catalog != null else []


static func create(
	known_person_ids: Array[String] = [], known_place_ids: Array[String] = []
) -> OrganizationState:
	var core := OrganizationState.new()
	if not known_person_ids.is_empty() or not known_place_ids.is_empty():
		if not core.configure_reference_catalog(known_person_ids, known_place_ids):
			core._data_error("Invalid person/place references: persons=%s places=%s" % [str(known_person_ids), str(known_place_ids)])
			return null
	return core


## An empty core is a valid structural registry. It has no external time source.


func is_valid() -> bool:
	return _validate_organizations(_organizations) and _scope_validate_complete_state(
		_authority_grants, _decision_bodies, _procedures, _proposals,
		_delegations, _power_relations, _power_transfers
	)


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


func revision() -> int:
	return _revision


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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
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
	_adopt_mutation(candidate_state)
	return true


func _commit_organization_state(
	organization_id: String, candidate_organization: Dictionary
) -> bool:
	var candidate_state: Dictionary = _organizations.duplicate(true)
	candidate_state[organization_id] = candidate_organization
	if not _validate_organizations(candidate_state):
		return false
	_adopt_mutation(candidate_state)
	return true


func _adopt_mutation(candidate_state: Dictionary) -> void:
	_organizations = candidate_state
	_revision += 1


func _snapshot_organizations(source: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for organization_id: String in _sorted_dictionary_keys(source):
		output.append(_snapshot_organization(source[organization_id] as Dictionary))
	return output


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


func _normalize_nonnegative_int(candidate_value: Variant) -> int:
	var candidate_type: int = typeof(candidate_value)
	if candidate_type == TYPE_INT:
		var candidate_int: int = int(candidate_value)
		return candidate_int if candidate_int >= 0 else -1
	if candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float) or candidate_float < 0.0:
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


static func position_holder(organization_id: String, position_id: String) -> Dictionary:
	return {
		"kind": "position",
		"organization_id": organization_id,
		"local_id": position_id,
		"person_id": "",
	}


static func decision_body_holder(organization_id: String, decision_body_id: String) -> Dictionary:
	return {
		"kind": "decision_body",
		"organization_id": organization_id,
		"local_id": decision_body_id,
		"person_id": "",
	}


static func membership_holder(organization_id: String, qualification: String = "member") -> Dictionary:
	return {
		"kind": "membership",
		"organization_id": organization_id,
		"local_id": qualification,
		"person_id": "",
	}


static func person_holder(person_id: String) -> Dictionary:
	return {
		"kind": "person",
		"organization_id": "",
		"local_id": "",
		"person_id": person_id,
	}


static func acting_context(
	person_id: String,
	acting_organization_id: String,
	represented_organization_id: String,
	authority_basis: String,
	appointment_id: String = "",
	membership_basis: bool = false,
	decision_id: String = "",
	delegation_id: String = ""
) -> Dictionary:
	return {
		"person_id": person_id,
		"acting_organization_id": acting_organization_id,
		"appointment_id": appointment_id,
		"membership_basis": membership_basis,
		"represented_organization_id": represented_organization_id,
		"authority_basis": authority_basis,
		"decision_id": decision_id,
		"delegation_id": delegation_id,
	}


static func constraints(
	allowed_stages: Array[String],
	required_procedure_id: String = "",
	notes: String = ""
) -> Dictionary:
	var sorted_stages := allowed_stages.duplicate()
	sorted_stages.sort()
	return {
		"allowed_stages": sorted_stages,
		"required_procedure_id": required_procedure_id,
		"notes": notes,
	}


static func accountability(
	organization_id: String = "", relation_id: String = ""
) -> Dictionary:
	return {
		"organization_id": organization_id,
		"relation_id": relation_id,
	}


func authority_ids() -> Array[String]:
	return _scope_sorted_keys(_authority_grants)


func authority_grant(authority_id: String) -> Dictionary:
	return (_authority_grants.get(authority_id, {}) as Dictionary).duplicate(true)


func add_authority_grant(record: Dictionary) -> bool:
	var normalized := _scope_normalize_authority_grant(record)
	if normalized.is_empty():
		return _data_error("Malformed add_authority_grant record: %s" % str(record))
	var authority_id: String = str(normalized.get("authority_id", ""))
	if _authority_grants.has(authority_id):
		return false
	if not _scope_authority_references_valid(normalized, _decision_bodies, _procedures):
		return false
	if _scope_has_exclusive_authority_conflict(normalized, _authority_grants):
		return false
	var candidate := _authority_grants.duplicate(true)
	candidate[authority_id] = normalized
	_authority_grants = candidate
	_revision += 1
	return true


func revoke_authority(authority_id: String, revoked_at: int) -> bool:
	if not _authority_grants.has(authority_id) or revoked_at < 0:
		return false
	var record: Dictionary = _authority_grants[authority_id] as Dictionary
	if not bool(record.get("revocable", false)) or int(record.get("revoked_at", -1)) >= 0:
		return false
	if revoked_at < int(record.get("valid_from", 0)):
		return false
	var candidate := _authority_grants.duplicate(true)
	var updated: Dictionary = (candidate[authority_id] as Dictionary).duplicate(true)
	updated["revoked_at"] = revoked_at
	candidate[authority_id] = updated
	_authority_grants = candidate
	_revision += 1
	return true


func define_decision_body(record: Dictionary) -> bool:
	var normalized := _scope_normalize_decision_body(record)
	if normalized.is_empty():
		return _data_error("Malformed define_decision_body record: %s" % str(record))
	var body_id: String = str(normalized.get("decision_body_id", ""))
	if _decision_bodies.has(body_id):
		return false
	if not _scope_decision_body_references_valid(normalized):
		return false
	var candidate := _decision_bodies.duplicate(true)
	candidate[body_id] = normalized
	_decision_bodies = candidate
	_revision += 1
	return true


func decision_body(decision_body_id: String) -> Dictionary:
	return (_decision_bodies.get(decision_body_id, {}) as Dictionary).duplicate(true)


func define_procedure(record: Dictionary) -> bool:
	var normalized := _scope_normalize_procedure(record)
	if normalized.is_empty():
		return _data_error("Malformed define_procedure record: %s" % str(record))
	var procedure_id: String = str(normalized.get("procedure_id", ""))
	if _procedures.has(procedure_id) or not _scope_procedure_references_valid(normalized, _decision_bodies):
		return false
	var candidate := _procedures.duplicate(true)
	candidate[procedure_id] = normalized
	_procedures = candidate
	_revision += 1
	return true


func procedure(procedure_id: String) -> Dictionary:
	return (_procedures.get(procedure_id, {}) as Dictionary).duplicate(true)


## Records a proposal fact after its action caller checks permission.
func record_proposal(record: Dictionary) -> bool:
	var normalized := _scope_normalize_proposal(record)
	if normalized.is_empty():
		return _data_error("Malformed record_proposal record: %s" % str(record))
	var proposal_id: String = str(normalized.get("proposal_id", ""))
	if _proposals.has(proposal_id):
		return false
	var organization_id: String = str(normalized.get("organization_id", ""))
	var procedure_id: String = str(normalized.get("procedure_id", ""))
	if (
		not self.has_organization(organization_id)
		or not _procedures.has(procedure_id)
		or str((_procedures[procedure_id] as Dictionary).get("organization_id", "")) != organization_id
	):
		return false
	var context: Dictionary = normalized.get("proposer_context", {}) as Dictionary
	if str(context.get("represented_organization_id", "")) != organization_id:
		return false
	var candidate := _proposals.duplicate(true)
	candidate[proposal_id] = normalized
	_proposals = candidate
	_revision += 1
	return true


func proposal(proposal_id: String) -> Dictionary:
	return (_proposals.get(proposal_id, {}) as Dictionary).duplicate(true)


func revise_proposal(
	proposal_id: String, expected_version: int, new_content_fingerprint: String, at_time: int
) -> bool:
	if (
		not _proposals.has(proposal_id)
		or expected_version <= 0
		or new_content_fingerprint.length() != 64
		or at_time < 0
	):
		return false
	var current: Dictionary = _proposals[proposal_id] as Dictionary
	if (
		int(current.get("version", 0)) != expected_version
		or str(current.get("status", "")) != "proposed"
	):
		return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	updated["version"] = expected_version + 1
	updated["content_fingerprint"] = new_content_fingerprint
	updated["created_at"] = at_time
	updated["votes"] = []
	updated["step_results"] = {}
	updated["signatures"] = []
	updated["decision_id"] = ""
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func cast_vote(
	proposal_id: String,
	step_id: String,
	person_id: String,
	proposal_version: int,
	choice: String,
	recused: bool,
	at_time: int
) -> bool:
	if (
		not _proposals.has(proposal_id)
		or not _known_person_ids.has(person_id)
		or not _VOTE_CHOICES.has(choice)
		or at_time < 0
	):
		return false
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if (
		str(proposal_record.get("status", "")) != "proposed"
		or int(proposal_record.get("version", 0)) != proposal_version
	):
		return false
	var procedure_record: Dictionary = _procedures.get(
		str(proposal_record.get("procedure_id", "")), {}
	) as Dictionary
	var step := _scope_procedure_step(procedure_record, step_id)
	if step.is_empty():
		return false
	var body: Dictionary = _decision_bodies.get(str(step.get("decision_body_id", "")), {}) as Dictionary
	var eligible := _scope_eligible_participants(body)
	if not eligible.has(person_id):
		return false
	if recused and not bool(step.get("recusal_allowed", false)):
		return false
	if choice == "abstain" and not bool(step.get("abstention_allowed", false)):
		return false
	var votes: Array = proposal_record.get("votes", []) as Array
	for raw_vote: Variant in votes:
		var vote: Dictionary = raw_vote as Dictionary
		if str(vote.get("step_id", "")) == step_id and str(vote.get("person_id", "")) == person_id:
			return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	var updated_votes: Array = (updated.get("votes", []) as Array).duplicate(true)
	updated_votes.append({
		"step_id": step_id,
		"person_id": person_id,
		"proposal_version": proposal_version,
		"choice": choice,
		"recused": recused,
		"cast_at": at_time,
	})
	updated["votes"] = updated_votes
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func finalize_proposal_step(proposal_id: String, step_id: String, at_time: int) -> bool:
	if not _proposals.has(proposal_id) or at_time < 0:
		return false
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if str(proposal_record.get("status", "")) != "proposed":
		return false
	var procedure_record: Dictionary = _procedures.get(
		str(proposal_record.get("procedure_id", "")), {}
	) as Dictionary
	if procedure_record.is_empty() or _scope_procedure_deadline_expired(procedure_record, proposal_record, at_time):
		return false
	var step := _scope_procedure_step(procedure_record, step_id)
	if step.is_empty():
		return false
	var prior_results: Dictionary = proposal_record.get("step_results", {}) as Dictionary
	if prior_results.has(step_id):
		return false
	var result := _scope_evaluate_step(step, proposal_record)
	if not bool(result.get("quorum_met", false)):
		return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	var results: Dictionary = (updated.get("step_results", {}) as Dictionary).duplicate(true)
	results[step_id] = result
	updated["step_results"] = results
	if not bool(result.get("approved", false)):
		updated["status"] = "rejected"
	elif results.size() == (procedure_record.get("steps", []) as Array).size():
		var all_approved := true
		for raw_step: Variant in procedure_record.get("steps", []) as Array:
			var procedure_step_record: Dictionary = raw_step as Dictionary
			var result_for_step: Dictionary = results.get(
				str(procedure_step_record.get("step_id", "")), {}
			) as Dictionary
			if not bool(result_for_step.get("approved", false)):
				all_approved = false
				break
		if all_approved:
			updated["status"] = "approved"
			updated["decision_id"] = "decision:%s:v%d" % [
				proposal_id,
				int(updated.get("version", 0)),
			]
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


## Records an institutional signature, not a cached action permission.
func record_signature(
	proposal_id: String,
	expected_version: int,
	signature_id: String,
	context: Dictionary,
	at_time: int,
	authority_id: String
) -> bool:
	if (
		not _proposals.has(proposal_id)
		or not _scope_is_valid_token(signature_id)
		or at_time < 0
	):
		return false
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if (
		str(proposal_record.get("status", "")) != "approved"
		or int(proposal_record.get("version", 0)) != expected_version
	):
		return false
	if not _scope_context_references_valid(context):
		return false
	if str(context.get("represented_organization_id", "")) != str(proposal_record.get("organization_id", "")):
		return false
	if not _authority_grants.has(authority_id):
		return _data_error("Unknown signature authority: " + authority_id)
	var signatures: Array = proposal_record.get("signatures", []) as Array
	for raw_signature: Variant in signatures:
		if str((raw_signature as Dictionary).get("signature_id", "")) == signature_id:
			return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	var updated_signatures: Array = (updated.get("signatures", []) as Array).duplicate(true)
	updated_signatures.append({
		"signature_id": signature_id,
		"proposal_version": expected_version,
		"person_id": str(context.get("person_id", "")),
		"authority_id": authority_id,
		"delegation_id": str(context.get("delegation_id", "")),
		"signed_at": at_time,
	})
	updated["signatures"] = updated_signatures
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func record_delegation(record: Dictionary) -> bool:
	var normalized := _scope_normalize_delegation(record)
	if normalized.is_empty():
		return _data_error("Malformed record_delegation record: %s" % str(record))
	var delegation_id: String = str(normalized.get("delegation_id", ""))
	if _delegations.has(delegation_id):
		return false
	var source_kind: String = str(normalized.get("source_kind", ""))
	var source_id: String = str(normalized.get("source_id", ""))
	var source_scope := _scope_effective_source_scope(source_kind, source_id)
	if source_scope.is_empty():
		return false
	if not bool(source_scope.get("delegable", false)):
		return false
	if not _scope_delegation_scope_is_subset(normalized, source_scope):
		return false
	if _scope_delegation_person_cycle(source_kind, source_id, str(normalized.get("recipient_person_id", ""))):
		return false
	if _scope_has_delegation_exclusive_conflict(normalized, _delegations):
		return false
	var candidate := _delegations.duplicate(true)
	candidate[delegation_id] = normalized
	if not _scope_validate_delegation_graph(_authority_grants, candidate):
		return false
	_delegations = candidate
	_revision += 1
	return true


func delegation(delegation_id: String) -> Dictionary:
	return (_delegations.get(delegation_id, {}) as Dictionary).duplicate(true)


func revoke_delegation(delegation_id: String, revoked_at: int) -> bool:
	if not _delegations.has(delegation_id) or revoked_at < 0:
		return false
	var record: Dictionary = _delegations[delegation_id] as Dictionary
	if not bool(record.get("revocable", false)) or int(record.get("revoked_at", -1)) >= 0:
		return false
	if revoked_at < int(record.get("valid_from", 0)):
		return false
	var candidate := _delegations.duplicate(true)
	var updated: Dictionary = (candidate[delegation_id] as Dictionary).duplicate(true)
	updated["revoked_at"] = revoked_at
	candidate[delegation_id] = updated
	_delegations = candidate
	_revision += 1
	return true


func add_power_relation(record: Dictionary) -> bool:
	var normalized := _scope_normalize_power_relation(record)
	if normalized.is_empty():
		return _data_error("Malformed add_power_relation record: %s" % str(record))
	var relation_id: String = str(normalized.get("relation_id", ""))
	if _power_relations.has(relation_id):
		return false
	var organization_id: String = str(normalized.get("represented_organization_id", ""))
	if not self.has_organization(organization_id):
		return false
	var candidate := _power_relations.duplicate(true)
	candidate[relation_id] = normalized
	_power_relations = candidate
	_revision += 1
	return true


func power_relation(relation_id: String) -> Dictionary:
	return (_power_relations.get(relation_id, {}) as Dictionary).duplicate(true)


func record_power_transfer(record: Dictionary) -> bool:
	var normalized := _scope_normalize_power_transfer(record)
	if normalized.is_empty():
		return _data_error("Malformed record_power_transfer record: %s" % str(record))
	var transfer_id: String = str(normalized.get("transfer_id", ""))
	if _power_transfers.has(transfer_id):
		return false
	var candidate := _power_transfers.duplicate(true)
	candidate[transfer_id] = normalized
	_power_transfers = candidate
	_revision += 1
	return true


func power_transfer(transfer_id: String) -> Dictionary:
	return (_power_transfers.get(transfer_id, {}) as Dictionary).duplicate(true)


func _scope_effective_source_scope(source_kind: String, source_id: String) -> Dictionary:
	if source_kind == "authority":
		if not _authority_grants.has(source_id):
			return {}
		var grant: Dictionary = _authority_grants[source_id] as Dictionary
		return {
			"target_scope": grant.get("target_scope", []),
			"spatial_scope": grant.get("spatial_scope", []),
			"subject_scope": grant.get("subject_scope", []),
			"amount_or_quantity_limit": float(grant.get("amount_or_quantity_limit", -1.0)),
			"valid_from": int(grant.get("valid_from", 0)),
			"valid_until": int(grant.get("valid_until", -1)),
			"delegable": bool(grant.get("delegable", false)),
			"redelegable": bool(grant.get("delegable", false)),
		}
	if source_kind == "delegation" and _delegations.has(source_id):
		var delegation_record: Dictionary = _delegations[source_id] as Dictionary
		return {
			"target_scope": delegation_record.get("target_scope", []),
			"spatial_scope": delegation_record.get("spatial_scope", []),
			"subject_scope": delegation_record.get("subject_scope", []),
			"amount_or_quantity_limit": float(delegation_record.get("amount_or_quantity_limit", -1.0)),
			"valid_from": int(delegation_record.get("valid_from", 0)),
			"valid_until": int(delegation_record.get("valid_until", -1)),
			"delegable": bool(delegation_record.get("redelegable", false)),
			"redelegable": bool(delegation_record.get("redelegable", false)),
		}
	return {}


func _scope_delegation_scope_is_subset(record: Dictionary, source_scope: Dictionary) -> bool:
	if not _scope_array_scope_subset(record.get("target_scope", []), source_scope.get("target_scope", [])):
		return false
	if not _scope_array_scope_subset(record.get("spatial_scope", []), source_scope.get("spatial_scope", [])):
		return false
	if not _scope_array_scope_subset(record.get("subject_scope", []), source_scope.get("subject_scope", [])):
		return false
	var source_limit := float(source_scope.get("amount_or_quantity_limit", -1.0))
	var delegated_limit := float(record.get("amount_or_quantity_limit", -1.0))
	if source_limit >= 0.0 and (delegated_limit < 0.0 or delegated_limit > source_limit):
		return false
	if int(record.get("valid_from", 0)) < int(source_scope.get("valid_from", 0)):
		return false
	var source_until := int(source_scope.get("valid_until", -1))
	var delegated_until := int(record.get("valid_until", -1))
	if source_until >= 0 and (delegated_until < 0 or delegated_until > source_until):
		return false
	return true


func _scope_evaluate_step(step: Dictionary, proposal_record: Dictionary) -> Dictionary:
	var body: Dictionary = _decision_bodies.get(str(step.get("decision_body_id", "")), {}) as Dictionary
	var eligible := _scope_eligible_participants(body)
	var recused: Dictionary = {}
	var yes_weight := 0
	var no_weight := 0
	var abstain_weight := 0
	var yes_count := 0
	var no_count := 0
	var abstain_count := 0
	for raw_vote: Variant in proposal_record.get("votes", []) as Array:
		var vote: Dictionary = raw_vote as Dictionary
		if str(vote.get("step_id", "")) != str(step.get("step_id", "")):
			continue
		var person_id := str(vote.get("person_id", ""))
		if not eligible.has(person_id):
			continue
		if bool(vote.get("recused", false)):
			recused[person_id] = true
			continue
		var weight := int(eligible.get(person_id, 0))
		match str(vote.get("choice", "")):
			"yes":
				yes_weight += weight
				yes_count += 1
			"no":
				no_weight += weight
				no_count += 1
			"abstain":
				abstain_weight += weight
				abstain_count += 1
	var eligible_weight := 0
	var eligible_count := 0
	for person_id: String in _scope_sorted_keys(eligible):
		if recused.has(person_id):
			continue
		eligible_weight += int(eligible[person_id])
		eligible_count += 1
	var participating_weight := yes_weight + no_weight + abstain_weight
	var participating_count := yes_count + no_count + abstain_count
	var quorum_met := (
		participating_weight * int(step.get("quorum_denominator", 1))
		>= eligible_weight * int(step.get("quorum_numerator", 1))
	)
	var denominator_kind := str(step.get("denominator", "eligible_weight"))
	var denominator_value := 0
	var yes_value := 0
	match denominator_kind:
		"eligible_weight":
			denominator_value = eligible_weight
			yes_value = yes_weight
		"cast_weight":
			denominator_value = yes_weight + no_weight
			yes_value = yes_weight
		"eligible_count":
			denominator_value = eligible_count
			yes_value = yes_count
		"cast_count":
			denominator_value = yes_count + no_count
			yes_value = yes_count
	var lhs := yes_value * int(step.get("threshold_denominator", 1))
	var rhs := denominator_value * int(step.get("threshold_numerator", 1))
	var approved := denominator_value > 0 and lhs > rhs
	if denominator_value > 0 and lhs == rhs:
		approved = str(step.get("tie_handling", "reject")) == "approve"
	return {
		"approved": quorum_met and approved,
		"quorum_met": quorum_met,
		"eligible_weight": eligible_weight,
		"participating_weight": participating_weight,
		"yes_weight": yes_weight,
		"no_weight": no_weight,
		"abstain_weight": abstain_weight,
		"eligible_count": eligible_count,
		"participating_count": participating_count,
		"yes_count": yes_count,
		"no_count": no_count,
		"abstain_count": abstain_count,
	}


func _scope_eligible_participants(body: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for raw_rule: Variant in body.get("eligible_participants", []) as Array:
		var rule: Dictionary = raw_rule as Dictionary
		var weight := int(rule.get("weight", 1))
		match str(rule.get("kind", "")):
			"person":
				var person_id := str(rule.get("person_id", ""))
				output[person_id] = int(output.get(person_id, 0)) + weight
			"position":
				var organization_id := str(body.get("organization_id", ""))
				var position_id := str(rule.get("position_id", ""))
				for appointment_id: String in self.appointment_ids(organization_id):
					var appointment_record := self.appointment(organization_id, appointment_id)
					if str(appointment_record.get("position_id", "")) == position_id:
						var person_id := str(appointment_record.get("person_id", ""))
						output[person_id] = int(output.get(person_id, 0)) + weight
			"membership":
				for person_id: String in self.member_ids(str(body.get("organization_id", ""))):
					output[person_id] = int(output.get(person_id, 0)) + weight
	return output


func _scope_procedure_step(procedure_record: Dictionary, step_id: String) -> Dictionary:
	for raw_step: Variant in procedure_record.get("steps", []) as Array:
		var step: Dictionary = raw_step as Dictionary
		if str(step.get("step_id", "")) == step_id:
			return step
	return {}


func _scope_procedure_deadline_expired(
	procedure_record: Dictionary, proposal_record: Dictionary, at_time: int
) -> bool:
	var deadline := int(procedure_record.get("deadline", -1))
	return deadline >= 0 and at_time > int(proposal_record.get("created_at", 0)) + deadline


func _scope_normalize_authority_grant(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"authority_id", "holder", "represented_entity", "operation",
		"target_scope", "spatial_scope", "subject_scope", "amount_or_quantity_limit",
		"valid_from", "valid_until", "basis", "revocable", "delegable",
		"exclusive_or_concurrent", "additional_constraints", "accountability", "revoked_at",
	]):
		return {}
	var authority_id := str(record.get("authority_id", ""))
	var represented_entity := str(record.get("represented_entity", ""))
	var operation := str(record.get("operation", ""))
	var holder := _scope_normalize_holder(record.get("holder", {}) as Dictionary)
	var target_scope := _scope_normalized_unique_strings(record.get("target_scope"))
	var spatial_scope := _scope_normalized_unique_strings(record.get("spatial_scope"))
	var subject_scope := _scope_normalized_unique_strings(record.get("subject_scope"))
	var limit := _scope_valid_limit(record.get("amount_or_quantity_limit"))
	var valid_from := _scope_nonnegative_int(record.get("valid_from"))
	var valid_until := _scope_optional_nonnegative_int(record.get("valid_until"))
	var revoked_at := _scope_optional_nonnegative_int(record.get("revoked_at"))
	if (
		not _scope_is_valid_token(authority_id)
		or holder.is_empty()
		or not _scope_is_valid_organization_id(represented_entity)
		or not _scope_is_valid_operation(operation)
		or target_scope.get("invalid", false)
		or spatial_scope.get("invalid", false)
		or subject_scope.get("invalid", false)
		or limit < -1.0
		or valid_from < 0
		or valid_until < -1
		or (valid_until >= 0 and valid_until < valid_from)
		or revoked_at < -1
		or (revoked_at >= 0 and revoked_at < valid_from)
		or typeof(record.get("revocable")) != TYPE_BOOL
		or typeof(record.get("delegable")) != TYPE_BOOL
		or str(record.get("exclusive_or_concurrent", "")) not in ["exclusive", "concurrent"]
	):
		return {}
	var basis := _scope_normalize_basis(record.get("basis", {}) as Dictionary)
	var constraint_record := _scope_normalize_constraints(record.get("additional_constraints", {}) as Dictionary)
	var accountability_record := _scope_normalize_accountability(record.get("accountability", {}) as Dictionary)
	if basis.is_empty() or constraint_record.is_empty() or accountability_record.is_empty():
		return {}
	return {
		"authority_id": authority_id,
		"holder": holder,
		"represented_entity": represented_entity,
		"operation": operation,
		"target_scope": target_scope.get("values", []),
		"spatial_scope": spatial_scope.get("values", []),
		"subject_scope": subject_scope.get("values", []),
		"amount_or_quantity_limit": limit,
		"valid_from": valid_from,
		"valid_until": valid_until,
		"basis": basis,
		"revocable": bool(record.get("revocable")),
		"delegable": bool(record.get("delegable")),
		"exclusive_or_concurrent": str(record.get("exclusive_or_concurrent")),
		"additional_constraints": constraint_record,
		"accountability": accountability_record,
		"revoked_at": revoked_at,
	}


func _scope_normalize_holder(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["kind", "organization_id", "local_id", "person_id"]):
		return {}
	var kind := str(record.get("kind", ""))
	var organization_id := str(record.get("organization_id", ""))
	var local_id := str(record.get("local_id", ""))
	var person_id := str(record.get("person_id", ""))
	if not _HOLDER_KINDS.has(kind):
		return {}
	match kind:
		"position", "decision_body", "membership":
			if not _scope_is_valid_organization_id(organization_id) or not _scope_is_valid_token(local_id) or not person_id.is_empty():
				return {}
		"person":
			if not organization_id.is_empty() or not local_id.is_empty() or not _known_person_ids.has(person_id):
				return {}
	return {
		"kind": kind,
		"organization_id": organization_id,
		"local_id": local_id,
		"person_id": person_id,
	}


func _scope_normalize_constraints(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"allowed_stages", "required_procedure_id", "notes"
	]):
		return {}
	var stages := _scope_normalized_unique_strings(record.get("allowed_stages"))
	if stages.get("invalid", false):
		return {}
	for stage: String in stages.get("values", []) as Array:
		if not _STAGES.has(stage):
			return {}
	var required_procedure_id := str(record.get("required_procedure_id", ""))
	if (
		not required_procedure_id.is_empty() and not _scope_is_valid_token(required_procedure_id)
	):
		return {}
	return {
		"allowed_stages": stages.get("values", []),
		"required_procedure_id": required_procedure_id,
		"notes": str(record.get("notes", "")),
	}


func _scope_normalize_accountability(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["organization_id", "relation_id"]):
		return {}
	var organization_id := str(record.get("organization_id", ""))
	var relation_id := str(record.get("relation_id", ""))
	if not organization_id.is_empty() and not _scope_is_valid_organization_id(organization_id):
		return {}
	if not relation_id.is_empty() and not _scope_is_valid_token(relation_id):
		return {}
	return {"organization_id": organization_id, "relation_id": relation_id}


func _scope_normalize_basis(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["kind", "id"]):
		return {}
	var kind := str(record.get("kind", ""))
	var basis_id := str(record.get("id", ""))
	if not _scope_is_valid_token(kind) or not _scope_is_valid_token(basis_id):
		return {}
	return {"kind": kind, "id": basis_id}


func _scope_normalize_decision_body(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["decision_body_id", "organization_id", "eligible_participants", "active"]):
		return {}
	var body_id := str(record.get("decision_body_id", ""))
	var organization_id := str(record.get("organization_id", ""))
	if not _scope_is_valid_token(body_id) or not _scope_is_valid_organization_id(organization_id) or typeof(record.get("active")) != TYPE_BOOL:
		return {}
	if typeof(record.get("eligible_participants")) != TYPE_ARRAY:
		return {}
	var participants: Array[Dictionary] = []
	for raw_rule: Variant in record.get("eligible_participants") as Array:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			return {}
		var rule := _scope_normalize_participant_rule(raw_rule as Dictionary)
		if rule.is_empty():
			return {}
		participants.append(rule)
	if participants.is_empty():
		return {}
	return {
		"decision_body_id": body_id,
		"organization_id": organization_id,
		"eligible_participants": participants,
		"active": bool(record.get("active")),
	}


func _scope_normalize_participant_rule(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["kind", "person_id", "position_id", "weight"]):
		return {}
	var kind := str(record.get("kind", ""))
	var person_id := str(record.get("person_id", ""))
	var position_id := str(record.get("position_id", ""))
	var weight := _scope_positive_int(record.get("weight"))
	if not _DECISION_PARTICIPANT_KINDS.has(kind) or weight <= 0:
		return {}
	match kind:
		"person":
			if not _known_person_ids.has(person_id) or not position_id.is_empty():
				return {}
		"position":
			if not person_id.is_empty() or not _scope_is_valid_token(position_id):
				return {}
		"membership":
			if not person_id.is_empty() or not position_id.is_empty():
				return {}
	return {"kind": kind, "person_id": person_id, "position_id": position_id, "weight": weight}


func _scope_normalize_procedure(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["procedure_id", "organization_id", "steps", "deadline"]):
		return {}
	var procedure_id := str(record.get("procedure_id", ""))
	var organization_id := str(record.get("organization_id", ""))
	var deadline := _scope_optional_nonnegative_int(record.get("deadline"))
	if not _scope_is_valid_token(procedure_id) or not _scope_is_valid_organization_id(organization_id) or deadline < -1:
		return {}
	if typeof(record.get("steps")) != TYPE_ARRAY:
		return {}
	var steps: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_step: Variant in record.get("steps") as Array:
		if typeof(raw_step) != TYPE_DICTIONARY:
			return {}
		var step := _scope_normalize_procedure_step(raw_step as Dictionary)
		if step.is_empty() or seen.has(str(step.get("step_id", ""))):
			return {}
		seen[str(step.get("step_id", ""))] = true
		steps.append(step)
	if steps.is_empty():
		return {}
	return {"procedure_id": procedure_id, "organization_id": organization_id, "steps": steps, "deadline": deadline}


func _scope_normalize_procedure_step(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"step_id", "decision_body_id", "quorum_numerator", "quorum_denominator",
		"threshold_numerator", "threshold_denominator", "denominator", "tie_handling",
		"abstention_allowed", "recusal_allowed",
	]):
		return {}
	var step_id := str(record.get("step_id", ""))
	var body_id := str(record.get("decision_body_id", ""))
	var qn := _scope_positive_int(record.get("quorum_numerator"))
	var qd := _scope_positive_int(record.get("quorum_denominator"))
	var tn := _scope_positive_int(record.get("threshold_numerator"))
	var td := _scope_positive_int(record.get("threshold_denominator"))
	if (
		not _scope_is_valid_token(step_id)
		or not _scope_is_valid_token(body_id)
		or qn <= 0 or qd <= 0 or qn > qd
		or tn <= 0 or td <= 0 or tn > td
		or str(record.get("denominator", "")) not in _DENOMINATORS
		or str(record.get("tie_handling", "")) not in _TIE_HANDLING
		or typeof(record.get("abstention_allowed")) != TYPE_BOOL
		or typeof(record.get("recusal_allowed")) != TYPE_BOOL
	):
		return {}
	return {
		"step_id": step_id,
		"decision_body_id": body_id,
		"quorum_numerator": qn,
		"quorum_denominator": qd,
		"threshold_numerator": tn,
		"threshold_denominator": td,
		"denominator": str(record.get("denominator")),
		"tie_handling": str(record.get("tie_handling")),
		"abstention_allowed": bool(record.get("abstention_allowed")),
		"recusal_allowed": bool(record.get("recusal_allowed")),
	}


func _scope_normalize_proposal(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"proposal_id", "organization_id", "operation", "target_id", "spatial_place_id",
		"subject_id", "amount_or_quantity", "content_fingerprint", "version",
		"proposer_context", "procedure_id", "created_at", "status", "step_results",
		"votes", "signatures", "decision_id",
	]):
		return {}
	var proposal_id := str(record.get("proposal_id", ""))
	var organization_id := str(record.get("organization_id", ""))
	var operation := str(record.get("operation", ""))
	var place_id := str(record.get("spatial_place_id", ""))
	var amount := _scope_nonnegative_float(record.get("amount_or_quantity"))
	var version := _scope_positive_int(record.get("version"))
	var created_at := _scope_nonnegative_int(record.get("created_at"))
	if (
		not _scope_is_valid_token(proposal_id)
		or not _scope_is_valid_organization_id(organization_id)
		or not _scope_is_valid_operation(operation)
		or (not place_id.is_empty() and not _known_place_ids.has(place_id))
		or amount < 0.0
		or str(record.get("content_fingerprint", "")).length() != 64
		or version <= 0
		or not _scope_context_references_valid(record.get("proposer_context", {}) as Dictionary)
		or not _scope_is_valid_token(str(record.get("procedure_id", "")))
		or created_at < 0
		or str(record.get("status", "")) not in ["proposed", "approved", "rejected"]
		or typeof(record.get("step_results")) != TYPE_DICTIONARY
		or typeof(record.get("votes")) != TYPE_ARRAY
		or typeof(record.get("signatures")) != TYPE_ARRAY
	):
		return {}
	var normalized := record.duplicate(true)
	normalized["version"] = version
	normalized["created_at"] = created_at

	var normalized_votes: Array = []
	for raw_vote: Variant in record.get("votes") as Array:
		if typeof(raw_vote) != TYPE_DICTIONARY:
			return {}
		var vote: Dictionary = (raw_vote as Dictionary).duplicate(true)
		var proposal_version := _scope_positive_int(vote.get("proposal_version"))
		var cast_at := _scope_nonnegative_int(vote.get("cast_at"))
		if proposal_version <= 0 or cast_at < 0:
			return {}
		vote["proposal_version"] = proposal_version
		vote["cast_at"] = cast_at
		normalized_votes.append(vote)
	normalized["votes"] = normalized_votes

	var normalized_signatures: Array = []
	for raw_signature: Variant in record.get("signatures") as Array:
		if typeof(raw_signature) != TYPE_DICTIONARY:
			return {}
		var signature: Dictionary = (raw_signature as Dictionary).duplicate(true)
		var proposal_version := _scope_positive_int(signature.get("proposal_version"))
		var signed_at := _scope_nonnegative_int(signature.get("signed_at"))
		if proposal_version <= 0 or signed_at < 0:
			return {}
		signature["proposal_version"] = proposal_version
		signature["signed_at"] = signed_at
		normalized_signatures.append(signature)
	normalized["signatures"] = normalized_signatures

	var normalized_step_results: Dictionary = {}
	var step_results: Dictionary = record.get("step_results") as Dictionary
	for raw_step_id: Variant in step_results.keys():
		if typeof(raw_step_id) != TYPE_STRING:
			return {}
		var raw_result: Variant = step_results.get(raw_step_id)
		if typeof(raw_result) != TYPE_DICTIONARY:
			return {}
		var result: Dictionary = (raw_result as Dictionary).duplicate(true)
		for field: String in [
			"eligible_weight", "participating_weight", "yes_weight", "no_weight", "abstain_weight",
			"eligible_count", "participating_count", "yes_count", "no_count", "abstain_count",
		]:
			var integer_value := _scope_nonnegative_int(result.get(field))
			if integer_value < 0:
				return {}
			result[field] = integer_value
		normalized_step_results[str(raw_step_id)] = result
	normalized["step_results"] = normalized_step_results
	return normalized


func _scope_normalize_delegation(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"delegation_id", "source_kind", "source_id", "delegator_context", "recipient_person_id",
		"target_scope", "spatial_scope", "subject_scope", "amount_or_quantity_limit",
		"valid_from", "valid_until", "redelegable", "revocable", "exclusive_or_concurrent", "revoked_at",
	]):
		return {}
	var delegation_id := str(record.get("delegation_id", ""))
	var source_kind := str(record.get("source_kind", ""))
	var source_id := str(record.get("source_id", ""))
	var recipient_person_id := str(record.get("recipient_person_id", ""))
	var target_scope := _scope_normalized_unique_strings(record.get("target_scope"))
	var spatial_scope := _scope_normalized_unique_strings(record.get("spatial_scope"))
	var subject_scope := _scope_normalized_unique_strings(record.get("subject_scope"))
	var limit := _scope_valid_limit(record.get("amount_or_quantity_limit"))
	var valid_from := _scope_nonnegative_int(record.get("valid_from"))
	var valid_until := _scope_optional_nonnegative_int(record.get("valid_until"))
	var revoked_at := _scope_optional_nonnegative_int(record.get("revoked_at"))
	if (
		not _scope_is_valid_token(delegation_id)
		or source_kind not in ["authority", "delegation"]
		or not _scope_is_valid_token(source_id)
		or not _scope_context_references_valid(record.get("delegator_context", {}) as Dictionary)
		or not _known_person_ids.has(recipient_person_id)
		or target_scope.get("invalid", false)
		or spatial_scope.get("invalid", false)
		or subject_scope.get("invalid", false)
		or limit < -1.0
		or valid_from < 0
		or valid_until < -1
		or (valid_until >= 0 and valid_until < valid_from)
		or revoked_at < -1
		or typeof(record.get("redelegable")) != TYPE_BOOL
		or typeof(record.get("revocable")) != TYPE_BOOL
		or str(record.get("exclusive_or_concurrent", "")) not in ["exclusive", "concurrent"]
	):
		return {}
	return {
		"delegation_id": delegation_id,
		"source_kind": source_kind,
		"source_id": source_id,
		"delegator_context": (record.get("delegator_context") as Dictionary).duplicate(true),
		"recipient_person_id": recipient_person_id,
		"target_scope": target_scope.get("values", []),
		"spatial_scope": spatial_scope.get("values", []),
		"subject_scope": subject_scope.get("values", []),
		"amount_or_quantity_limit": limit,
		"valid_from": valid_from,
		"valid_until": valid_until,
		"redelegable": bool(record.get("redelegable")),
		"revocable": bool(record.get("revocable")),
		"exclusive_or_concurrent": str(record.get("exclusive_or_concurrent")),
		"revoked_at": revoked_at,
	}


func _scope_normalize_power_relation(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"relation_id", "relation_type", "source_entity", "target_entity",
		"represented_organization_id", "scope", "valid_from", "valid_until", "basis",
	]):
		return {}
	var relation_id := str(record.get("relation_id", ""))
	var relation_type := str(record.get("relation_type", ""))
	var organization_id := str(record.get("represented_organization_id", ""))
	var valid_from := _scope_nonnegative_int(record.get("valid_from"))
	var valid_until := _scope_optional_nonnegative_int(record.get("valid_until"))
	if (
		not _scope_is_valid_token(relation_id)
		or relation_type not in _RELATION_TYPES
		or str(record.get("source_entity", "")).is_empty()
		or str(record.get("target_entity", "")).is_empty()
		or not _scope_is_valid_organization_id(organization_id)
		or typeof(record.get("scope")) != TYPE_DICTIONARY
		or valid_from < 0 or valid_until < -1 or (valid_until >= 0 and valid_until < valid_from)
		or _scope_normalize_basis(record.get("basis", {}) as Dictionary).is_empty()
	):
		return {}
	return {
		"relation_id": relation_id,
		"relation_type": relation_type,
		"source_entity": str(record.get("source_entity")),
		"target_entity": str(record.get("target_entity")),
		"represented_organization_id": organization_id,
		"scope": (record.get("scope") as Dictionary).duplicate(true),
		"valid_from": valid_from,
		"valid_until": valid_until,
		"basis": _scope_normalize_basis(record.get("basis", {}) as Dictionary),
	}


func _scope_normalize_power_transfer(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"transfer_id", "transfer_type", "source_ref", "target_ref", "basis_ref", "effective_at",
		"authority_id", "relation_id", "delegation_id",
	]):
		return {}
	var transfer_id := str(record.get("transfer_id", ""))
	var transfer_type := str(record.get("transfer_type", ""))
	var effective_at := _scope_nonnegative_int(record.get("effective_at"))
	if (
		not _scope_is_valid_token(transfer_id)
		or transfer_type not in _TRANSFER_TYPES
		or str(record.get("source_ref", "")).is_empty()
		or str(record.get("target_ref", "")).is_empty()
		or str(record.get("basis_ref", "")).is_empty()
		or effective_at < 0
	):
		return {}
	return {
		"transfer_id": transfer_id,
		"transfer_type": transfer_type,
		"source_ref": str(record.get("source_ref")),
		"target_ref": str(record.get("target_ref")),
		"basis_ref": str(record.get("basis_ref")),
		"effective_at": effective_at,
		"authority_id": str(record.get("authority_id", "")),
		"relation_id": str(record.get("relation_id", "")),
		"delegation_id": str(record.get("delegation_id", "")),
	}


func _scope_authority_references_valid(
	record: Dictionary, bodies: Dictionary, procedures: Dictionary
) -> bool:
	var represented := str(record.get("represented_entity", ""))
	if not self.has_organization(represented):
		return false
	var holder: Dictionary = record.get("holder", {}) as Dictionary
	var holder_kind := str(holder.get("kind", ""))
	var holder_org := str(holder.get("organization_id", ""))
	match holder_kind:
		"position":
			if not self.has_organization(holder_org) or self.position(holder_org, str(holder.get("local_id", ""))).is_empty():
				return false
		"decision_body":
			if not bodies.has(str(holder.get("local_id", ""))):
				return false
		"membership":
			if not self.has_organization(holder_org):
				return false
		"person":
			if not _known_person_ids.has(str(holder.get("person_id", ""))):
				return false
	for place_id: String in _scope_string_array(record.get("spatial_scope", [])):
		if not _known_place_ids.has(place_id):
			return false
	var required_procedure_id := str((record.get("additional_constraints", {}) as Dictionary).get("required_procedure_id", ""))
	if not required_procedure_id.is_empty() and not procedures.has(required_procedure_id):
		return false
	return true


func _scope_decision_body_references_valid(record: Dictionary) -> bool:
	var organization_id := str(record.get("organization_id", ""))
	if not self.has_organization(organization_id):
		return false
	for raw_rule: Variant in record.get("eligible_participants", []) as Array:
		var rule: Dictionary = raw_rule as Dictionary
		if str(rule.get("kind", "")) == "position" and self.position(organization_id, str(rule.get("position_id", ""))).is_empty():
			return false
	return true


func _scope_procedure_references_valid(record: Dictionary, bodies: Dictionary) -> bool:
	var organization_id := str(record.get("organization_id", ""))
	if not self.has_organization(organization_id):
		return false
	for raw_step: Variant in record.get("steps", []) as Array:
		var step: Dictionary = raw_step as Dictionary
		var body_id := str(step.get("decision_body_id", ""))
		if not bodies.has(body_id):
			return false
		if str((bodies[body_id] as Dictionary).get("organization_id", "")) != organization_id:
			return false
	return true


func _scope_validate_complete_state(
	grants: Dictionary,
	bodies: Dictionary,
	procedures: Dictionary,
	proposals: Dictionary,
	delegations: Dictionary,
	relations: Dictionary,
	transfers: Dictionary
) -> bool:
	for authority_id: String in _scope_sorted_keys(grants):
		if _scope_normalize_authority_grant(grants[authority_id]).is_empty():
			return _data_error("Malformed authority grant: " + authority_id)
	for delegation_id: String in _scope_sorted_keys(delegations):
		if _scope_normalize_delegation(delegations[delegation_id]).is_empty():
			return _data_error("Malformed delegation: " + delegation_id)
	for body_id: String in _scope_sorted_keys(bodies):
		if not _scope_decision_body_references_valid(bodies[body_id] as Dictionary):
			return false
	for procedure_id: String in _scope_sorted_keys(procedures):
		if not _scope_procedure_references_valid(procedures[procedure_id] as Dictionary, bodies):
			return false
	for authority_id: String in _scope_sorted_keys(grants):
		if not _scope_authority_references_valid(grants[authority_id] as Dictionary, bodies, procedures):
			return false
		if _scope_has_exclusive_authority_conflict(grants[authority_id] as Dictionary, grants, authority_id):
			return false
	for proposal_id: String in _scope_sorted_keys(proposals):
		var proposal_record: Dictionary = proposals[proposal_id] as Dictionary
		var procedure_id := str(proposal_record.get("procedure_id", ""))
		var organization_id := str(proposal_record.get("organization_id", ""))
		if not procedures.has(procedure_id):
			return false
		if not self.has_organization(organization_id):
			return false
		if str((procedures[procedure_id] as Dictionary).get("organization_id", "")) != organization_id:
			return false
		var proposer_context: Dictionary = proposal_record.get("proposer_context", {}) as Dictionary
		if str(proposer_context.get("represented_organization_id", "")) != organization_id:
			return false
	if not _scope_validate_delegation_graph(grants, delegations):
		return false
	for relation_id: String in _scope_sorted_keys(relations):
		if not self.has_organization(str((relations[relation_id] as Dictionary).get("represented_organization_id", ""))):
			return false
	for transfer_id: String in _scope_sorted_keys(transfers):
		var transfer: Dictionary = transfers[transfer_id] as Dictionary
		var authority_id := str(transfer.get("authority_id", ""))
		var relation_id := str(transfer.get("relation_id", ""))
		var delegation_id := str(transfer.get("delegation_id", ""))
		if not authority_id.is_empty() and not grants.has(authority_id):
			return false
		if not relation_id.is_empty() and not relations.has(relation_id):
			return false
		if not delegation_id.is_empty() and not delegations.has(delegation_id):
			return false
	return true


func _scope_validate_delegation_graph(grants: Dictionary, delegations: Dictionary) -> bool:
	if _scope_candidate_delegation_graph_has_cycle(delegations):
		return false
	for delegation_id: String in _scope_sorted_keys(delegations):
		var delegation_record: Dictionary = delegations[delegation_id] as Dictionary
		var source_kind := str(delegation_record.get("source_kind", ""))
		var source_id := str(delegation_record.get("source_id", ""))
		if source_id == delegation_id:
			return false
		if source_kind == "authority" and not grants.has(source_id):
			return false
		if source_kind == "delegation" and not delegations.has(source_id):
			return false
		var source_scope := _scope_candidate_source_scope(source_kind, source_id, grants, delegations)
		if source_scope.is_empty() or not bool(source_scope.get("delegable", false)):
			return false
		if not _scope_delegation_scope_is_subset(delegation_record, source_scope):
			return false
		# Source identity is a persistent grant reference, not a current permission result.
		var context: Dictionary = delegation_record["delegator_context"]
		var root_source_id: String = source_id
		while delegations.has(root_source_id):
			root_source_id = str((delegations[root_source_id] as Dictionary)["source_id"])
		if not grants.has(root_source_id):
			return false
		var root_grant: Dictionary = grants[root_source_id]
		if str(context["authority_basis"]) != root_source_id or str(context["represented_organization_id"]) != str(root_grant["represented_entity"]):
			return false
		if source_kind == "authority":
			if not str(context["delegation_id"]).is_empty():
				return false
		elif str(context["delegation_id"]) != source_id or str(context["person_id"]) != str((delegations[source_id] as Dictionary)["recipient_person_id"]):
			return false
		if _scope_candidate_delegation_person_cycle(
			source_kind,
			source_id,
			str(delegation_record.get("recipient_person_id", "")),
			delegations
		):
			return false
		if _scope_has_delegation_exclusive_conflict(delegation_record, delegations, delegation_id):
			return false
	return true


func _scope_candidate_source_scope(
	source_kind: String, source_id: String, grants: Dictionary, delegations: Dictionary
) -> Dictionary:
	if source_kind == "authority":
		if not grants.has(source_id):
			return {}
		var grant: Dictionary = grants[source_id] as Dictionary
		return {
			"target_scope": grant.get("target_scope", []),
			"spatial_scope": grant.get("spatial_scope", []),
			"subject_scope": grant.get("subject_scope", []),
			"amount_or_quantity_limit": float(grant.get("amount_or_quantity_limit", -1.0)),
			"valid_from": int(grant.get("valid_from", 0)),
			"valid_until": int(grant.get("valid_until", -1)),
			"delegable": bool(grant.get("delegable", false)),
			"redelegable": bool(grant.get("delegable", false)),
		}
	if source_kind == "delegation" and delegations.has(source_id):
		var delegation_record: Dictionary = delegations[source_id] as Dictionary
		return {
			"target_scope": delegation_record.get("target_scope", []),
			"spatial_scope": delegation_record.get("spatial_scope", []),
			"subject_scope": delegation_record.get("subject_scope", []),
			"amount_or_quantity_limit": float(delegation_record.get("amount_or_quantity_limit", -1.0)),
			"valid_from": int(delegation_record.get("valid_from", 0)),
			"valid_until": int(delegation_record.get("valid_until", -1)),
			"delegable": bool(delegation_record.get("redelegable", false)),
			"redelegable": bool(delegation_record.get("redelegable", false)),
		}
	return {}


func _scope_candidate_delegation_graph_has_cycle(delegations: Dictionary) -> bool:
	var state: Dictionary = {}
	for start_id: String in _scope_sorted_keys(delegations):
		if int(state.get(start_id, 0)) == 2:
			continue
		var path: Array[String] = []
		var current_id := start_id
		while delegations.has(current_id):
			var color := int(state.get(current_id, 0))
			if color == 1:
				return true
			if color == 2:
				break
			state[current_id] = 1
			path.append(current_id)
			var record: Dictionary = delegations[current_id] as Dictionary
			if str(record.get("source_kind", "")) != "delegation":
				break
			current_id = str(record.get("source_id", ""))
		for path_id: String in path:
			state[path_id] = 2
	return false


func _scope_candidate_delegation_person_cycle(
	source_kind: String, source_id: String, recipient_person_id: String, delegations: Dictionary
) -> bool:
	var current_kind := source_kind
	var current_id := source_id
	var visited: Dictionary = {}
	while current_kind == "delegation":
		if visited.has(current_id) or not delegations.has(current_id):
			return true
		visited[current_id] = true
		var record: Dictionary = delegations[current_id] as Dictionary
		if str(record.get("recipient_person_id", "")) == recipient_person_id:
			return true
		current_kind = str(record.get("source_kind", ""))
		current_id = str(record.get("source_id", ""))
	return false


func _scope_has_exclusive_authority_conflict(
	new_record: Dictionary, source: Dictionary, ignore_id: String = ""
) -> bool:
	for authority_id: String in _scope_sorted_keys(source):
		if authority_id == ignore_id:
			continue
		var existing: Dictionary = source[authority_id] as Dictionary
		if str(existing.get("represented_entity", "")) != str(new_record.get("represented_entity", "")):
			continue
		if str(existing.get("operation", "")) != str(new_record.get("operation", "")):
			continue
		if str(existing.get("exclusive_or_concurrent", "")) != "exclusive" and str(new_record.get("exclusive_or_concurrent", "")) != "exclusive":
			continue
		if not _scope_time_ranges_overlap(existing, new_record):
			continue
		if (
			_scope_scope_arrays_overlap(existing.get("target_scope", []), new_record.get("target_scope", []))
			and _scope_scope_arrays_overlap(existing.get("spatial_scope", []), new_record.get("spatial_scope", []))
			and _scope_scope_arrays_overlap(existing.get("subject_scope", []), new_record.get("subject_scope", []))
		):
			return true
	return false


func _scope_has_delegation_exclusive_conflict(
	new_record: Dictionary, source: Dictionary, ignore_id: String = ""
) -> bool:
	for delegation_id: String in _scope_sorted_keys(source):
		if delegation_id == ignore_id:
			continue
		var existing: Dictionary = source[delegation_id] as Dictionary
		if str(existing.get("source_kind", "")) != str(new_record.get("source_kind", "")) or str(existing.get("source_id", "")) != str(new_record.get("source_id", "")):
			continue
		if str(existing.get("exclusive_or_concurrent", "")) != "exclusive" and str(new_record.get("exclusive_or_concurrent", "")) != "exclusive":
			continue
		if not _scope_time_ranges_overlap(existing, new_record):
			continue
		if (
			_scope_scope_arrays_overlap(existing.get("target_scope", []), new_record.get("target_scope", []))
			and _scope_scope_arrays_overlap(existing.get("spatial_scope", []), new_record.get("spatial_scope", []))
			and _scope_scope_arrays_overlap(existing.get("subject_scope", []), new_record.get("subject_scope", []))
		):
			return true
	return false


func _scope_delegation_person_cycle(source_kind: String, source_id: String, recipient_person_id: String) -> bool:
	var current_kind := source_kind
	var current_id := source_id
	var visited: Dictionary = {}
	while current_kind == "delegation":
		if visited.has(current_id) or not _delegations.has(current_id):
			return true
		visited[current_id] = true
		var record: Dictionary = _delegations[current_id] as Dictionary
		if str(record.get("recipient_person_id", "")) == recipient_person_id:
			return true
		current_kind = str(record.get("source_kind", ""))
		current_id = str(record.get("source_id", ""))
	return false


func _scope_array_scope_subset(child_value: Variant, parent_value: Variant) -> bool:
	var child := _scope_string_array(child_value)
	var parent := _scope_string_array(parent_value)
	if parent.is_empty():
		return true
	if child.is_empty():
		return false
	for item: String in child:
		if not parent.has(item):
			return false
	return true


func _scope_scope_arrays_overlap(first_value: Variant, second_value: Variant) -> bool:
	var first := _scope_string_array(first_value)
	var second := _scope_string_array(second_value)
	if first.is_empty() or second.is_empty():
		return true
	for item: String in first:
		if second.has(item):
			return true
	return false


func _scope_time_ranges_overlap(first: Dictionary, second: Dictionary) -> bool:
	var first_start := int(first.get("valid_from", 0))
	var second_start := int(second.get("valid_from", 0))
	var first_end := int(first.get("valid_until", -1))
	var second_end := int(second.get("valid_until", -1))
	if first_end >= 0 and second_start > first_end:
		return false
	if second_end >= 0 and first_start > second_end:
		return false
	return true


func _scope_decode_record_array(raw_value: Variant, normalizer: Callable, id_field: String) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return {"invalid": true, "records": {}}
	var records: Dictionary = {}
	for raw_record: Variant in raw_value as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return {"invalid": true, "records": {}}
		var normalized: Dictionary = normalizer.call(raw_record as Dictionary)
		if normalized.is_empty():
			return {"invalid": true, "records": {}}
		var record_id := str(normalized.get(id_field, ""))
		if records.has(record_id):
			return {"invalid": true, "records": {}}
		records[record_id] = normalized
	return {"invalid": false, "records": records}


func _scope_records_as_sorted_array(source: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for key: String in _scope_sorted_keys(source):
		output.append((source[key] as Dictionary).duplicate(true))
	return output


func _scope_normalized_unique_strings(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return {"invalid": true, "values": []}
	var output: Array[String] = []
	for raw_item: Variant in raw_value as Array:
		if typeof(raw_item) != TYPE_STRING:
			return {"invalid": true, "values": []}
		var item := str(raw_item)
		if item.is_empty() or output.has(item):
			return {"invalid": true, "values": []}
		output.append(item)
	output.sort()
	return {"invalid": false, "values": output}


func _scope_string_array(raw_value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(raw_value) != TYPE_ARRAY:
		return output
	for raw_item: Variant in raw_value as Array:
		if typeof(raw_item) == TYPE_STRING:
			output.append(str(raw_item))
	output.sort()
	return output


func _scope_sorted_keys(source: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for raw_key: Variant in source.keys():
		if typeof(raw_key) == TYPE_STRING:
			output.append(str(raw_key))
	output.sort()
	return output


func _scope_is_valid_person_id(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "person"


func _scope_is_valid_place_id(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "place"


func _scope_is_valid_organization_id(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "organization"


func _scope_is_valid_operation(value: String) -> bool:
	return _scope_is_valid_token(value) and value.contains(".")


func _scope_is_valid_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var character := value.substr(index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_.:-/".contains(character):
			return false
	return true


func _scope_positive_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value) if int(value) > 0 else -1
	if typeof(value) != TYPE_FLOAT:
		return -1
	var candidate := float(value)
	if not is_finite(candidate) or candidate <= 0.0 or candidate != floor(candidate):
		return -1
	return int(candidate)


func _scope_nonnegative_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value) if int(value) >= 0 else -1
	if typeof(value) != TYPE_FLOAT:
		return -1
	var candidate := float(value)
	if not is_finite(candidate) or candidate < 0.0 or candidate != floor(candidate):
		return -1
	return int(candidate)


func _scope_optional_nonnegative_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value) if int(value) >= -1 else -2
	if typeof(value) != TYPE_FLOAT:
		return -2
	var candidate := float(value)
	if not is_finite(candidate) or candidate < -1.0 or candidate != floor(candidate):
		return -2
	return int(candidate)


func _scope_nonnegative_float(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return -1.0
	var result := float(value)
	return result if is_finite(result) and result >= 0.0 else -1.0


func _scope_valid_limit(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return -2.0
	var result := float(value)
	return result if is_finite(result) and result >= -1.0 else -2.0


func structure_fingerprint() -> String:
	return JSON.stringify(_snapshot_organizations(_organizations)).sha256_text()


func state_fingerprint() -> String:
	return JSON.stringify(_payload()).sha256_text()


func snapshot() -> Dictionary:
	var result := _payload()
	result["state_fingerprint"] = state_fingerprint()
	return result


func _payload() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"revision": _revision,
		"reference_fingerprint": reference_catalog_fingerprint(),
		"organizations": _snapshot_organizations(_organizations),
		"authority_grants": _scope_records_as_sorted_array(_authority_grants),
		"decision_bodies": _scope_records_as_sorted_array(_decision_bodies),
		"procedures": _scope_records_as_sorted_array(_procedures),
		"proposals": _scope_records_as_sorted_array(_proposals),
		"delegations": _scope_records_as_sorted_array(_delegations),
		"power_relations": _scope_records_as_sorted_array(_power_relations),
		"power_transfers": _scope_records_as_sorted_array(_power_transfers),
	}


func restore(snapshot_value: Dictionary) -> bool:
	if str(snapshot_value.get("schema_id", "")) != SNAPSHOT_SCHEMA_ID:
		return _data_error("Unsupported organization schema: %s" % str(snapshot_value.get("schema_id")))
	if not _has_exact_fields(snapshot_value, ["schema_id","revision","reference_fingerprint","organizations","authority_grants","decision_bodies","procedures","proposals","delegations","power_relations","power_transfers","state_fingerprint"]):
		return _data_error("Malformed organization snapshot fields")
	if str(snapshot_value["reference_fingerprint"]) != reference_catalog_fingerprint():
		return _data_error("Broken person/place reference catalog")
	var candidate := OrganizationState.new()
	candidate._reference_catalog = _reference_catalog
	candidate._reference_catalog_configured = _reference_catalog_configured
	candidate._revision = _normalize_nonnegative_int(snapshot_value["revision"])
	if candidate._revision < 0 or not snapshot_value["organizations"] is Array:
		return _data_error("Malformed organization revision/records")
	for raw: Variant in snapshot_value["organizations"] as Array:
		if not raw is Dictionary:
			return _data_error("Malformed organization record: %s" % str(raw))
		var decoded: Dictionary = candidate._decode_organization(raw)
		if decoded.is_empty() or candidate._organizations.has(str(decoded["organization_id"])):
			return _data_error("Malformed/duplicate organization: %s" % str(raw))
		candidate._organizations[str(decoded["organization_id"])] = decoded
	var authority_grants_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["authority_grants"], Callable(candidate, "_scope_normalize_authority_grant"), "authority_id")
	if bool(authority_grants_decoded.get("invalid", false)):
		return _data_error("Malformed authority_grants: %s" % str(snapshot_value["authority_grants ".strip_edges()]))
	candidate._authority_grants = authority_grants_decoded["records"]
	var decision_bodies_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["decision_bodies"], Callable(candidate, "_scope_normalize_decision_body"), "decision_body_id")
	if bool(decision_bodies_decoded.get("invalid", false)):
		return _data_error("Malformed decision_bodies: %s" % str(snapshot_value["decision_bodies ".strip_edges()]))
	candidate._decision_bodies = decision_bodies_decoded["records"]
	var procedures_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["procedures"], Callable(candidate, "_scope_normalize_procedure"), "procedure_id")
	if bool(procedures_decoded.get("invalid", false)):
		return _data_error("Malformed procedures: %s" % str(snapshot_value["procedures ".strip_edges()]))
	candidate._procedures = procedures_decoded["records"]
	var proposals_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["proposals"], Callable(candidate, "_scope_normalize_proposal"), "proposal_id")
	if bool(proposals_decoded.get("invalid", false)):
		return _data_error("Malformed proposals: %s" % str(snapshot_value["proposals ".strip_edges()]))
	candidate._proposals = proposals_decoded["records"]
	var delegations_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["delegations"], Callable(candidate, "_scope_normalize_delegation"), "delegation_id")
	if bool(delegations_decoded.get("invalid", false)):
		return _data_error("Malformed delegations: %s" % str(snapshot_value["delegations ".strip_edges()]))
	candidate._delegations = delegations_decoded["records"]
	var power_relations_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["power_relations"], Callable(candidate, "_scope_normalize_power_relation"), "relation_id")
	if bool(power_relations_decoded.get("invalid", false)):
		return _data_error("Malformed power_relations: %s" % str(snapshot_value["power_relations ".strip_edges()]))
	candidate._power_relations = power_relations_decoded["records"]
	var power_transfers_decoded: Dictionary = candidate._scope_decode_record_array(snapshot_value["power_transfers"], Callable(candidate, "_scope_normalize_power_transfer"), "transfer_id")
	if bool(power_transfers_decoded.get("invalid", false)):
		return _data_error("Malformed power_transfers: %s" % str(snapshot_value["power_transfers ".strip_edges()]))
	candidate._power_transfers = power_transfers_decoded["records"]
	if not candidate.is_valid():
		return _data_error("Broken organization/authority references: %s" % str(snapshot_value))
	if str(snapshot_value["state_fingerprint"]) != candidate.state_fingerprint():
		return _data_error("Organization snapshot fingerprint mismatch")
	_organizations = candidate._organizations
	_revision = candidate._revision
	_authority_grants = candidate._authority_grants
	_decision_bodies = candidate._decision_bodies
	_procedures = candidate._procedures
	_proposals = candidate._proposals
	_delegations = candidate._delegations
	_power_relations = candidate._power_relations
	_power_transfers = candidate._power_transfers
	return true


func _data_error(detail: String) -> bool:
	push_error("ORGANIZATION DATA ERROR: " + detail)
	return false


func _scope_context_references_valid(context: Dictionary) -> bool:
	if not _has_exact_fields(context, ["person_id", "acting_organization_id", "appointment_id", "membership_basis", "represented_organization_id", "authority_basis", "decision_id", "delegation_id"]):
		return false
	return (
		_known_person_ids.has(str(context["person_id"]))
		and has_organization(str(context["acting_organization_id"]))
		and has_organization(str(context["represented_organization_id"]))
		and typeof(context["membership_basis"]) == TYPE_BOOL
	)
