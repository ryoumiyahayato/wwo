class_name VNextObservationRecord
extends RefCounted

const STABLE_ID = preload("res://scripts/vnext/identity/stable_id.gd")

var _subject_id: String = ""
var _world_revision: int = -1
var _fields: Array[VNextObservedField] = []


func configure(subject_id_value: Variant, world_revision_value: Variant, fields_value: Variant) -> bool:
	if (
		typeof(subject_id_value) != TYPE_STRING
		or not STABLE_ID.is_valid(subject_id_value as String)
	):
		return false
	if typeof(world_revision_value) != TYPE_INT or int(world_revision_value) < 0:
		return false
	if typeof(fields_value) != TYPE_ARRAY or (fields_value as Array).is_empty():
		return false

	var candidate_fields: Array[VNextObservedField] = []
	var candidate_field_ids: Array[String] = []
	for field_value: Variant in fields_value as Array:
		if not field_value is VNextObservedField:
			return false
		var field: VNextObservedField = field_value as VNextObservedField
		if field == null or candidate_field_ids.has(field.field_id()):
			return false
		var copied_field: VNextObservedField = field.copy_detached()
		if copied_field == null:
			return false
		candidate_fields.append(copied_field)
		candidate_field_ids.append(copied_field.field_id())
	candidate_fields.sort_custom(_compare_fields)

	_subject_id = subject_id_value as String
	_world_revision = int(world_revision_value)
	_fields = candidate_fields
	return true


func subject_id() -> String:
	return _subject_id


func world_revision() -> int:
	return _world_revision


func fields() -> Array[VNextObservedField]:
	var copied_fields: Array[VNextObservedField] = []
	for field: VNextObservedField in _fields:
		copied_fields.append(field.copy_detached())
	return copied_fields


func field_ids() -> Array[String]:
	var result: Array[String] = []
	for field: VNextObservedField in _fields:
		result.append(field.field_id())
	return result


func has_field(field_id: String) -> bool:
	for field: VNextObservedField in _fields:
		if field.field_id() == field_id:
			return true
	return false


func field_by_id(field_id: String) -> VNextObservedField:
	for field: VNextObservedField in _fields:
		if field.field_id() == field_id:
			return field.copy_detached()
	return null


func copy_detached() -> VNextObservationRecord:
	var copied := VNextObservationRecord.new()
	if not copied.configure(_subject_id, _world_revision, _fields):
		return null
	return copied


func to_detached_dict() -> Dictionary:
	var serialized_fields: Array = []
	for field: VNextObservedField in _fields:
		serialized_fields.append(field.to_detached_dict())
	return {
		"subject_id": _subject_id,
		"world_revision": _world_revision,
		"fields": serialized_fields,
	}


static func _compare_fields(left: VNextObservedField, right: VNextObservedField) -> bool:
	return left.field_id() < right.field_id()
