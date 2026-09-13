class_name VNextObservationContract
extends RefCounted

## Shared transport vocabulary. This contract never owns authoritative world,
## knowledge, identity, or authorization state.

const SCHEMA_ID: String = "vnext_observation_v1"
const INVALIDATION_SCHEMA_ID: String = "vnext_observation_invalidation_v1"
const UNSPECIFIED_WORLD_REVISION: int = -1

const STATUS_OK: String = "ok"
const STATUS_INVALID_REQUEST: String = "invalid_request"
const STATUS_UNKNOWN_OBSERVER: String = "unknown_observer"
const STATUS_REVISION_MISMATCH: String = "revision_mismatch"
const STATUS_VISIBILITY_UNAVAILABLE: String = "visibility_unavailable"
const STATUS_QUERY_UNAVAILABLE: String = "query_unavailable"

const FRESHNESS_FRESH: String = "fresh"
const FRESHNESS_STALE: String = "stale"
const FRESHNESS_UNKNOWN: String = "unknown"

const TRUTH_CAPABILITY: String = "observation.truth.read"
const RESTRICTED_CAPABILITY: String = "observation.restricted.read"


static func is_valid_token(candidate_value: String) -> bool:
	if candidate_value.is_empty():
		return false
	for character_index: int in candidate_value.length():
		var character: String = candidate_value.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-.".contains(character):
			return false
	return true


static func is_valid_scope(candidate_value: String) -> bool:
	if candidate_value.is_empty() or candidate_value != candidate_value.strip_edges():
		return false
	for character_index: int in candidate_value.length():
		var character: String = candidate_value.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-. :/".replace(" ", "").contains(
			character
		):
			return false
	return true


static func is_valid_freshness(candidate_value: String) -> bool:
	return candidate_value in [FRESHNESS_FRESH, FRESHNESS_STALE, FRESHNESS_UNKNOWN]


static func is_valid_confidence(candidate_value: float) -> bool:
	return is_finite(candidate_value) and candidate_value >= 0.0 and candidate_value <= 1.0


static func is_valid_provenance_reference(candidate_value: String) -> bool:
	return (
		not candidate_value.is_empty()
		and candidate_value == candidate_value.strip_edges()
		and not candidate_value.contains(" ")
	)


static func is_valid_cause_id(candidate_value: String) -> bool:
	return (
		not candidate_value.is_empty()
		and candidate_value == candidate_value.strip_edges()
		and not candidate_value.contains(" ")
	)


static func is_sorted_unique(values: Array[String]) -> bool:
	for value_index: int in values.size():
		if value_index > 0 and values[value_index - 1] >= values[value_index]:
			return false
	return true


static func copy_string_array(values: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	for value: String in values:
		copied.append(value)
	return copied


static func is_detachable_value(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if (
		value_type == TYPE_NIL
		or value_type == TYPE_BOOL
		or value_type == TYPE_INT
		or value_type == TYPE_FLOAT
		or value_type == TYPE_STRING
	):
		return true
	if value_type == TYPE_ARRAY:
		for item: Variant in value as Array:
			if not is_detachable_value(item):
				return false
		return true
	if value_type == TYPE_DICTIONARY:
		var dictionary_value: Dictionary = value as Dictionary
		for key: Variant in dictionary_value.keys():
			if typeof(key) != TYPE_STRING or not is_detachable_value(dictionary_value.get(key)):
				return false
		return true
	return false


static func detached_copy(value: Variant) -> Variant:
	var value_type: int = typeof(value)
	if value_type == TYPE_ARRAY:
		var copied_array: Array = []
		for item: Variant in value as Array:
			copied_array.append(detached_copy(item))
		return copied_array
	if value_type == TYPE_DICTIONARY:
		var source_dictionary: Dictionary = value as Dictionary
		var keys: Array = source_dictionary.keys()
		keys.sort()
		var copied_dictionary: Dictionary = {}
		for key: Variant in keys:
			copied_dictionary[key] = detached_copy(source_dictionary.get(key))
		return copied_dictionary
	return value


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(detached_copy(value), "", false)


static func fingerprint_for(value: Variant) -> String:
	return canonical_json(value).sha256_text()
