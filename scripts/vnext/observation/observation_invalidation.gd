class_name VNextObservationInvalidation
extends RefCounted

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")

var _new_world_revision: int = CONTRACT.UNSPECIFIED_WORLD_REVISION
var _changed_scopes: Array[String] = []
var _cause_id: String = ""


func configure(
	new_world_revision_value: Variant,
	changed_scopes_value: Variant,
	cause_id_value: Variant
) -> bool:
	if typeof(new_world_revision_value) != TYPE_INT or int(new_world_revision_value) < 0:
		return false
	if typeof(changed_scopes_value) != TYPE_ARRAY:
		return false
	if (
		typeof(cause_id_value) != TYPE_STRING
		or not CONTRACT.is_valid_cause_id(cause_id_value as String)
	):
		return false

	var candidate_scopes: Array[String] = []
	for scope_value: Variant in changed_scopes_value as Array:
		if typeof(scope_value) != TYPE_STRING or not CONTRACT.is_valid_scope(scope_value as String):
			return false
		var scope: String = scope_value as String
		if candidate_scopes.has(scope):
			return false
		candidate_scopes.append(scope)
	if candidate_scopes.is_empty():
		return false
	candidate_scopes.sort()

	_new_world_revision = int(new_world_revision_value)
	_changed_scopes = candidate_scopes
	_cause_id = cause_id_value as String
	return true


func new_world_revision() -> int:
	return _new_world_revision


func changed_scopes() -> Array[String]:
	return CONTRACT.copy_string_array(_changed_scopes)


func cause_id() -> String:
	return _cause_id


func to_detached_dict() -> Dictionary:
	return {
		"schema_id": CONTRACT.INVALIDATION_SCHEMA_ID,
		"new_world_revision": _new_world_revision,
		"changed_scopes": CONTRACT.copy_string_array(_changed_scopes),
		"cause_id": _cause_id,
	}
