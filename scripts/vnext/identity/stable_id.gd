class_name VNextStableId
extends RefCounted


static func is_valid(candidate_value: String) -> bool:
	if candidate_value.is_empty():
		return false
	if candidate_value.count(":") != 1:
		return false

	var separator_index: int = candidate_value.find(":")
	if separator_index <= 0 or separator_index >= candidate_value.length() - 1:
		return false

	var candidate_kind: String = candidate_value.left(separator_index)
	var candidate_local_id: String = candidate_value.substr(separator_index + 1)
	return _is_supported_kind(candidate_kind) and _is_valid_local_id(candidate_local_id)


static func kind_of(candidate_value: String) -> String:
	if not is_valid(candidate_value):
		return ""
	return candidate_value.get_slice(":", 0)


static func local_id_of(candidate_value: String) -> String:
	if not is_valid(candidate_value):
		return ""
	return candidate_value.get_slice(":", 1)


static func compose(candidate_kind: String, candidate_local_id: String) -> String:
	if not _is_supported_kind(candidate_kind):
		return ""
	if not _is_valid_local_id(candidate_local_id):
		return ""
	return candidate_kind + ":" + candidate_local_id


static func _is_supported_kind(candidate_kind: String) -> bool:
	return (
		candidate_kind == "person"
		or candidate_kind == "place"
		or candidate_kind == "organization"
		or candidate_kind == "event"
		or candidate_kind == "economy"
		or candidate_kind == "state"
		or candidate_kind == "policy"
		or candidate_kind == "formation"
		or candidate_kind == "military_action"
	)


static func _is_valid_local_id(candidate_local_id: String) -> bool:
	if candidate_local_id.is_empty():
		return false
	for character_index: int in candidate_local_id.length():
		var candidate_character: String = candidate_local_id.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(candidate_character):
			return false
	return true