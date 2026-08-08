class_name VNextLocationState
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_location_state_v1"

var _player_id: String = ""
var _place_id: String = ""


func initialize(player_id_value: String, place_id_value: String) -> bool:
	if not _is_person_id(player_id_value):
		return false
	if not _is_place_id(place_id_value):
		return false
	_player_id = player_id_value
	_place_id = place_id_value
	return true


func player_id() -> String:
	return _player_id


func place_id() -> String:
	return _place_id


func is_valid() -> bool:
	return _is_person_id(_player_id) and _is_place_id(_place_id)


func move_to(place_id_value: String) -> bool:
	if not is_valid():
		return false
	if not _is_place_id(place_id_value):
		return false
	_place_id = place_id_value
	return true


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"player_id": _player_id,
		"place_id": _place_id,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if not snapshot_value.has("player_id") or not snapshot_value.has("place_id"):
		return false

	var candidate_player_id: Variant = snapshot_value.get("player_id")
	var candidate_place_id: Variant = snapshot_value.get("place_id")
	if typeof(candidate_player_id) != TYPE_STRING or typeof(candidate_place_id) != TYPE_STRING:
		return false

	var normalized_player_id: String = candidate_player_id as String
	var normalized_place_id: String = candidate_place_id as String
	if not _is_person_id(normalized_player_id):
		return false
	if not _is_place_id(normalized_place_id):
		return false

	_player_id = normalized_player_id
	_place_id = normalized_place_id
	return true


static func _is_person_id(candidate_value: String) -> bool:
	return VNextStableId.is_valid(candidate_value) and VNextStableId.kind_of(candidate_value) == "person"


static func _is_place_id(candidate_value: String) -> bool:
	return VNextStableId.is_valid(candidate_value) and VNextStableId.kind_of(candidate_value) == "place"
