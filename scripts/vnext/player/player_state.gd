class_name VNextPlayerState
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_player_state_v1"

var _player_id: String = ""
var _person_authority: RefCounted = null


func _init(initial_player_id: String = "", person_authority: RefCounted = null) -> void:
	if person_authority != null:
		bind_person_authority(person_authority)
	if initial_player_id.is_empty():
		return
	set_player_id(initial_player_id)


func bind_person_authority(person_authority: RefCounted) -> bool:
	if person_authority == null or not person_authority.has_method("has_person"):
		return false
	if _person_authority != null and _person_authority != person_authority:
		return false
	if not _player_id.is_empty() and not bool(person_authority.call("has_person", _player_id)):
		return false
	_person_authority = person_authority
	return true


func has_person_authority() -> bool:
	return _person_authority != null


func set_player_id(candidate_player_id: String) -> bool:
	if not _is_valid_player_id(candidate_player_id):
		return false
	if (
		_person_authority != null
		and not bool(_person_authority.call("has_person", candidate_player_id))
	):
		return false
	_player_id = candidate_player_id
	return true


func player_id() -> String:
	return _player_id


func is_valid() -> bool:
	if not _is_valid_player_id(_player_id):
		return false
	return (
		_person_authority == null
		or bool(_person_authority.call("has_person", _player_id))
	)


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
	if (
		_person_authority != null
		and not bool(_person_authority.call("has_person", candidate_player_id))
	):
		return false

	_player_id = candidate_player_id
	return true


static func _is_valid_player_id(candidate_player_id: String) -> bool:
	return (
		VNextStableId.is_valid(candidate_player_id)
		and VNextStableId.kind_of(candidate_player_id) == "person"
	)
