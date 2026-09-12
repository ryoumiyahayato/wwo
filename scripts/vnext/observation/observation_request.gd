class_name VNextObservationRequest
extends RefCounted

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")
const STABLE_ID = preload("res://scripts/vnext/identity/stable_id.gd")

var _observer_actor_id: String = ""
var _scope: String = ""
var _subject_ids: Array[String] = []
var _expected_world_revision: int = CONTRACT.UNSPECIFIED_WORLD_REVISION
var _requested_fields: Array[String] = []
var _requested_capabilities: Array[String] = []
var _validation_error: String = "request_not_configured"


func configure(
	observer_actor_id_value: Variant,
	scope_value: Variant,
	subject_ids_value: Variant,
	expected_world_revision_value: Variant = CONTRACT.UNSPECIFIED_WORLD_REVISION,
	requested_fields_value: Variant = [],
	requested_capabilities_value: Variant = []
) -> bool:
	_validation_error = ""
	if typeof(observer_actor_id_value) != TYPE_STRING:
		return _reject("observer_actor_id_required")
	var candidate_observer_actor_id: String = observer_actor_id_value as String
	if (
		not STABLE_ID.is_valid(candidate_observer_actor_id)
		or STABLE_ID.kind_of(candidate_observer_actor_id) != "person"
	):
		return _reject("observer_actor_id_invalid")

	if typeof(scope_value) != TYPE_STRING or not CONTRACT.is_valid_scope(scope_value as String):
		return _reject("scope_invalid")
	var candidate_scope: String = scope_value as String

	if typeof(expected_world_revision_value) != TYPE_INT:
		return _reject("expected_world_revision_invalid")
	var candidate_expected_revision: int = int(expected_world_revision_value)
	if candidate_expected_revision < CONTRACT.UNSPECIFIED_WORLD_REVISION:
		return _reject("expected_world_revision_invalid")

	var candidate_subject_ids: Array[String] = _read_stable_id_list(
		subject_ids_value, "subject_ids"
	)
	if not _validation_error.is_empty():
		return false
	var candidate_requested_fields: Array[String] = _read_token_list(
		requested_fields_value, "requested_fields"
	)
	if not _validation_error.is_empty():
		return false
	var candidate_requested_capabilities: Array[String] = _read_token_list(
		requested_capabilities_value, "requested_capabilities"
	)
	if not _validation_error.is_empty():
		return false

	_observer_actor_id = candidate_observer_actor_id
	_scope = candidate_scope
	_subject_ids = candidate_subject_ids
	_expected_world_revision = candidate_expected_revision
	_requested_fields = candidate_requested_fields
	_requested_capabilities = candidate_requested_capabilities
	_validation_error = ""
	return true


static func create(
	observer_actor_id_value: String,
	scope_value: String,
	subject_ids_value: Array[String],
	expected_world_revision_value: int = CONTRACT.UNSPECIFIED_WORLD_REVISION,
	requested_fields_value: Array[String] = [],
	requested_capabilities_value: Array[String] = []
) -> VNextObservationRequest:
	var request := VNextObservationRequest.new()
	if not request.configure(
		observer_actor_id_value,
		scope_value,
		subject_ids_value,
		expected_world_revision_value,
		requested_fields_value,
		requested_capabilities_value
	):
		return null
	return request


func is_valid() -> bool:
	return (
		_validation_error.is_empty()
		and STABLE_ID.is_valid(_observer_actor_id)
		and STABLE_ID.kind_of(_observer_actor_id) == "person"
		and CONTRACT.is_valid_scope(_scope)
		and not _subject_ids.is_empty()
		and CONTRACT.is_sorted_unique(_subject_ids)
		and CONTRACT.is_sorted_unique(_requested_fields)
		and CONTRACT.is_sorted_unique(_requested_capabilities)
		and _expected_world_revision >= CONTRACT.UNSPECIFIED_WORLD_REVISION
	)


func validation_error() -> String:
	return _validation_error


func observer_actor_id() -> String:
	return _observer_actor_id


func scope() -> String:
	return _scope


func subject_ids() -> Array[String]:
	return CONTRACT.copy_string_array(_subject_ids)


func expected_world_revision() -> int:
	return _expected_world_revision


func requested_fields() -> Array[String]:
	return CONTRACT.copy_string_array(_requested_fields)


func requested_capabilities() -> Array[String]:
	return CONTRACT.copy_string_array(_requested_capabilities)


func requests_field(field_id: String) -> bool:
	return _requested_fields.is_empty() or _requested_fields.has(field_id)


func requests_capability(capability: String) -> bool:
	return _requested_capabilities.has(capability)


func to_detached_dict() -> Dictionary:
	return {
		"observer_actor_id": _observer_actor_id,
		"scope": _scope,
		"subject_ids": CONTRACT.copy_string_array(_subject_ids),
		"expected_world_revision": _expected_world_revision,
		"requested_fields": CONTRACT.copy_string_array(_requested_fields),
		"requested_capabilities": CONTRACT.copy_string_array(_requested_capabilities),
	}


func _read_stable_id_list(value: Variant, field_name: String) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		_reject(field_name + "_required")
		return result
	for item: Variant in value as Array:
		if typeof(item) != TYPE_STRING or not STABLE_ID.is_valid(item as String):
			_reject(field_name + "_contains_invalid_id")
			return []
		var candidate: String = item as String
		if result.has(candidate):
			_reject(field_name + "_contains_duplicate")
			return []
		result.append(candidate)
	if result.is_empty():
		_reject(field_name + "_cannot_be_empty")
		return result
	result.sort()
	return result


func _read_token_list(value: Variant, field_name: String) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		_reject(field_name + "_required")
		return result
	for item: Variant in value as Array:
		if typeof(item) != TYPE_STRING or not CONTRACT.is_valid_token(item as String):
			_reject(field_name + "_contains_invalid_token")
			return []
		var candidate: String = item as String
		if result.has(candidate):
			_reject(field_name + "_contains_duplicate")
			return []
		result.append(candidate)
	result.sort()
	return result


func _reject(reason: String) -> bool:
	_validation_error = reason
	return false
