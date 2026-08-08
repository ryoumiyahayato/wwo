class_name VNextEventKnowledgeState
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_event_knowledge_v1"

var _player_id: String
var _event_records: Dictionary = {}
var _known_event_ids: Dictionary = {}
var _read_event_ids: Dictionary = {}


func _init(initial_player_id: String) -> void:
	assert(_is_person_id(initial_player_id), "player_id must be a valid person stable ID")
	_player_id = initial_player_id


func player_id() -> String:
	return _player_id


func record_event(event_id: String, occurred_at_minutes: int) -> bool:
	if not _is_event_id(event_id):
		return false
	if occurred_at_minutes < 0:
		return false
	if _event_records.has(event_id):
		return false

	_event_records[event_id] = {
		"event_id": event_id,
		"occurred_at_minutes": occurred_at_minutes,
	}
	return true


func reveal_event(event_id: String) -> bool:
	if not _event_records.has(event_id):
		return false
	_known_event_ids[event_id] = true
	return true


func mark_event_read(event_id: String) -> bool:
	if not _known_event_ids.has(event_id):
		return false
	_read_event_ids[event_id] = true
	return true


func knows_event(event_id: String) -> bool:
	return _known_event_ids.has(event_id)


func has_read_event(event_id: String) -> bool:
	return _read_event_ids.has(event_id)


func snapshot() -> Dictionary:
	var sorted_event_ids: Array[String] = _sorted_string_keys(_event_records)
	var event_records: Array[Dictionary] = []
	for event_id: String in sorted_event_ids:
		var record: Dictionary = _event_records[event_id] as Dictionary
		event_records.append({
			"event_id": event_id,
			"occurred_at_minutes": int(record.get("occurred_at_minutes", 0)),
		})

	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"player_id": _player_id,
		"event_records": event_records,
		"known_event_ids": _sorted_string_keys(_known_event_ids),
		"read_event_ids": _sorted_string_keys(_read_event_ids),
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 5:
		return false
	for required_field: String in [
		"schema_id", "player_id", "event_records", "known_event_ids", "read_event_ids",
	]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if typeof(snapshot_value.get("player_id")) != TYPE_STRING:
		return false

	var candidate_player_id: String = str(snapshot_value.get("player_id"))
	if not _is_person_id(candidate_player_id):
		return false

	var raw_event_records: Variant = snapshot_value.get("event_records")
	var raw_known_event_ids: Variant = snapshot_value.get("known_event_ids")
	var raw_read_event_ids: Variant = snapshot_value.get("read_event_ids")
	if typeof(raw_event_records) != TYPE_ARRAY:
		return false
	if typeof(raw_known_event_ids) != TYPE_ARRAY:
		return false
	if typeof(raw_read_event_ids) != TYPE_ARRAY:
		return false

	var candidate_event_records: Dictionary = {}
	for raw_record: Variant in raw_event_records as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = raw_record as Dictionary
		if record.size() != 2:
			return false
		if not record.has("event_id") or not record.has("occurred_at_minutes"):
			return false
		if typeof(record.get("event_id")) != TYPE_STRING:
			return false
		var event_id: String = str(record.get("event_id"))
		if not _is_event_id(event_id) or candidate_event_records.has(event_id):
			return false
		var occurred_at_minutes: int = _normalized_nonnegative_int(
			record.get("occurred_at_minutes")
		)
		if occurred_at_minutes < 0:
			return false
		candidate_event_records[event_id] = {
			"event_id": event_id,
			"occurred_at_minutes": occurred_at_minutes,
		}

	var candidate_known_event_ids: Dictionary = {}
	for raw_event_id: Variant in raw_known_event_ids as Array:
		if typeof(raw_event_id) != TYPE_STRING:
			return false
		var event_id: String = str(raw_event_id)
		if (
			not _is_event_id(event_id)
			or not candidate_event_records.has(event_id)
			or candidate_known_event_ids.has(event_id)
		):
			return false
		candidate_known_event_ids[event_id] = true

	var candidate_read_event_ids: Dictionary = {}
	for raw_event_id: Variant in raw_read_event_ids as Array:
		if typeof(raw_event_id) != TYPE_STRING:
			return false
		var event_id: String = str(raw_event_id)
		if (
			not _is_event_id(event_id)
			or not candidate_known_event_ids.has(event_id)
			or candidate_read_event_ids.has(event_id)
		):
			return false
		candidate_read_event_ids[event_id] = true

	_player_id = candidate_player_id
	_event_records = candidate_event_records
	_known_event_ids = candidate_known_event_ids
	_read_event_ids = candidate_read_event_ids
	return true


static func _is_person_id(candidate_id: String) -> bool:
	return VNextStableId.is_valid(candidate_id) and VNextStableId.kind_of(candidate_id) == "person"


static func _is_event_id(candidate_id: String) -> bool:
	return VNextStableId.is_valid(candidate_id) and VNextStableId.kind_of(candidate_id) == "event"


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in source.keys():
		result.append(str(raw_key))
	result.sort()
	return result


static func _normalized_nonnegative_int(candidate_value: Variant) -> int:
	var candidate_type: int = typeof(candidate_value)
	if candidate_type == TYPE_INT:
		var candidate_int: int = int(candidate_value)
		return candidate_int if candidate_int >= 0 else -1
	if candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float):
			return -1
		if candidate_float < 0.0 or candidate_float != floor(candidate_float):
			return -1
		return int(candidate_float)
	return -1
