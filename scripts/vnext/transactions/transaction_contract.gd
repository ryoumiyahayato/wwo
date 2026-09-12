class_name VNextTransactionContract
extends RefCounted

const STATUS_COMMITTED: String = "committed"
const STATUS_REJECTED: String = "rejected"

const FAILURE_NONE: String = "none"
const FAILURE_MALFORMED_COMMAND: String = "malformed_command"
const FAILURE_DUPLICATE_PARTICIPANT: String = "duplicate_participant"
const FAILURE_STALE_REVISION: String = "stale_revision"
const FAILURE_MISSING_PARTICIPANT: String = "missing_participant"
const FAILURE_PREPARE: String = "prepare_failed"
const FAILURE_LOCAL_VALIDATION: String = "local_validation_failed"
const FAILURE_CROSS_DOMAIN_VALIDATION: String = "cross_domain_validation_failed"
const FAILURE_CONSERVATION_VALIDATION: String = "conservation_validation_failed"


static func is_valid_identity(candidate_value: String) -> bool:
	if candidate_value.is_empty() or candidate_value != candidate_value.strip_edges():
		return false
	for character_index: int in candidate_value.length():
		var character: String = candidate_value.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-.".contains(character):
			return false
	return true


static func is_detachable_value(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if value_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value_type != TYPE_FLOAT or is_finite(value as float)
	if value_type == TYPE_ARRAY:
		for item: Variant in value as Array:
			if not is_detachable_value(item):
				return false
		return true
	if value_type == TYPE_DICTIONARY:
		for key: Variant in (value as Dictionary).keys():
			if typeof(key) != TYPE_STRING or not is_detachable_value((value as Dictionary).get(key)):
				return false
		return true
	return false


static func detached_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copied_array: Array = []
		for item: Variant in value as Array:
			copied_array.append(detached_copy(item))
		return copied_array
	if typeof(value) == TYPE_DICTIONARY:
		var source: Dictionary = value as Dictionary
		var keys: Array = source.keys()
		keys.sort()
		var copied_dictionary: Dictionary = {}
		for key: Variant in keys:
			copied_dictionary[key] = detached_copy(source.get(key))
		return copied_dictionary
	return value


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(detached_copy(value), "", false)


static func fingerprint_for(value: Variant) -> String:
	return canonical_json(value).sha256_text()


static func sorted_unique(values: Array[String]) -> bool:
	for value_index: int in values.size():
		if value_index > 0 and values[value_index - 1] >= values[value_index]:
			return false
	return true
