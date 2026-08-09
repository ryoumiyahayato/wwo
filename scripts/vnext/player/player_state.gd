class_name VNextPlayerState
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_player_state_v1"

var _player_id: String = ""


func _init(initial_player_id: String = "") -> void:
	if initial_player_id.is_empty():
		return
	if _is_valid_player_id(initial_player_id):
		_player_id = initial_player_id


func player_id() -> String:
	return _player_id


func is_valid() -> bool:
	return _is_valid_player_id(_player_id)


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"player_id": _player_id,
	}


func restore(snapshot_value: Dictionary) -> bool:
	var candidate_schema_id: Variant = snapshot_value.get("schema_id")
	var has_player_id: bool = snapshot_value.has("player_id")
	var candidate_player_id_value: Variant = snapshot_value.get("player_id")

	if candidate_schema_id != SNAPSHOT_SCHEMA_ID:
		return false
	if not has_player_id:
		return false
	if typeof(candidate_player_id_value) != TYPE_STRING:
		return false

	var candidate_player_id: String = candidate_player_id_value
	if not _is_valid_player_id(candidate_player_id):
		return false

	_player_id = candidate_player_id
	return true


static func _is_valid_player_id(candidate_player_id: String) -> bool:
	return (
		VNextStableId.is_valid(candidate_player_id)
		and VNextStableId.kind_of(candidate_player_id) == "person"
	)
