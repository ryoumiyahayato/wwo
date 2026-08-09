class_name VNextWorldRuntime
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_world_runtime_v2"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

var _total_minutes: int = 0
var _player: VNextPlayerState = null
var _wallet: VNextPersonalWallet = null
var _location: VNextLocationState = null
var _event_knowledge: VNextEventKnowledgeState = null


func _init(initial_player_id: String = "", initial_place_id: String = "") -> void:
	if initial_player_id.is_empty() and initial_place_id.is_empty():
		return
	initialize(initial_player_id, initial_place_id)


static func create(
	initial_player_id: String, initial_place_id: String
) -> VNextWorldRuntime:
	var runtime := VNextWorldRuntime.new()
	if not runtime.initialize(initial_player_id, initial_place_id):
		return null
	return runtime


func initialize(initial_player_id: String, initial_place_id: String) -> bool:
	var candidate_player := VNextPlayerState.new(initial_player_id)
	var candidate_wallet: VNextPersonalWallet = VNextPersonalWallet.create(initial_player_id)
	var candidate_location := VNextLocationState.new()
	var candidate_event_knowledge: VNextEventKnowledgeState = (
		VNextEventKnowledgeState.create(initial_player_id)
	)

	if not candidate_player.is_valid():
		return false
	if candidate_wallet == null or not candidate_wallet.is_valid():
		return false
	if not candidate_location.initialize(initial_player_id, initial_place_id):
		return false
	if candidate_event_knowledge == null:
		return false
	if not _is_composition_valid(
		candidate_player,
		candidate_wallet,
		candidate_location,
		candidate_event_knowledge
	):
		return false

	_total_minutes = 0
	_player = candidate_player
	_wallet = candidate_wallet
	_location = candidate_location
	_event_knowledge = candidate_event_knowledge
	return true


func is_valid() -> bool:
	return _is_composition_valid(_player, _wallet, _location, _event_knowledge)


func is_initialized() -> bool:
	return is_valid()


func player() -> VNextPlayerState:
	return _player


func wallet() -> VNextPersonalWallet:
	return _wallet


func location() -> VNextLocationState:
	return _location


func event_knowledge() -> VNextEventKnowledgeState:
	return _event_knowledge


func player_id() -> String:
	if _player == null:
		return ""
	return _player.player_id()


func total_minutes() -> int:
	return _total_minutes


func advance_minutes(minutes: int) -> bool:
	if not can_advance_minutes(minutes):
		return false
	_total_minutes += minutes
	return true


func can_advance_minutes(minutes: int) -> bool:
	if not is_valid():
		return false
	if minutes <= 0:
		return false
	return minutes <= MAX_JSON_SAFE_INTEGER - _total_minutes


func record_event(event_id: String) -> bool:
	if not is_valid():
		return false
	return _event_knowledge.record_event(event_id, total_minutes())


func reveal_event(event_id: String) -> bool:
	if not is_valid():
		return false
	return _event_knowledge.reveal_event(event_id)


func mark_event_read(event_id: String) -> bool:
	if not is_valid():
		return false
	return _event_knowledge.mark_event_read(event_id)


func snapshot() -> Dictionary:
	var player_snapshot: Dictionary = {}
	var wallet_snapshot: Dictionary = {}
	var location_snapshot: Dictionary = {}
	var event_knowledge_snapshot: Dictionary = {}
	if _player != null:
		player_snapshot = _player.snapshot()
	if _wallet != null:
		wallet_snapshot = _wallet.snapshot()
	if _location != null:
		location_snapshot = _location.snapshot()
	if _event_knowledge != null:
		event_knowledge_snapshot = _event_knowledge.snapshot()

	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"total_minutes": _total_minutes,
		"player": player_snapshot,
		"wallet": wallet_snapshot,
		"location": location_snapshot,
		"event_knowledge": event_knowledge_snapshot,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 6:
		return false
	for required_field: String in [
		"schema_id", "total_minutes", "player", "wallet", "location", "event_knowledge",
	]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false

	var candidate_total_minutes: int = _normalize_json_safe_nonnegative_int(
		snapshot_value.get("total_minutes")
	)
	if candidate_total_minutes < 0:
		return false

	if typeof(snapshot_value.get("player")) != TYPE_DICTIONARY:
		return false
	if typeof(snapshot_value.get("wallet")) != TYPE_DICTIONARY:
		return false
	if typeof(snapshot_value.get("location")) != TYPE_DICTIONARY:
		return false
	if typeof(snapshot_value.get("event_knowledge")) != TYPE_DICTIONARY:
		return false

	var candidate_player := VNextPlayerState.new()
	var candidate_wallet := VNextPersonalWallet.new()
	var candidate_location := VNextLocationState.new()
	var candidate_event_knowledge := VNextEventKnowledgeState.new()
	if not candidate_player.restore(snapshot_value.get("player") as Dictionary):
		return false
	if not candidate_wallet.restore(snapshot_value.get("wallet") as Dictionary):
		return false
	if not candidate_location.restore(snapshot_value.get("location") as Dictionary):
		return false
	if not candidate_event_knowledge.restore(
		snapshot_value.get("event_knowledge") as Dictionary
	):
		return false
	if not _is_composition_valid(
		candidate_player,
		candidate_wallet,
		candidate_location,
		candidate_event_knowledge
	):
		return false

	if _has_initialized_owner_objects():
		var previous_player: Dictionary = _player.snapshot()
		var previous_wallet: Dictionary = _wallet.snapshot()
		var previous_location: Dictionary = _location.snapshot()
		var previous_event_knowledge: Dictionary = _event_knowledge.snapshot()
		if not _restore_owner_objects(
			candidate_player.snapshot(),
			candidate_wallet.snapshot(),
			candidate_location.snapshot(),
			candidate_event_knowledge.snapshot()
		):
			_restore_owner_objects(
				previous_player,
				previous_wallet,
				previous_location,
				previous_event_knowledge
			)
			return false
		_total_minutes = candidate_total_minutes
		return true

	_total_minutes = candidate_total_minutes
	_player = candidate_player
	_wallet = candidate_wallet
	_location = candidate_location
	_event_knowledge = candidate_event_knowledge
	return true


func _has_initialized_owner_objects() -> bool:
	return (
		_player != null
		and _wallet != null
		and _location != null
		and _event_knowledge != null
		and is_valid()
	)


func _restore_owner_objects(
	player_snapshot: Dictionary,
	wallet_snapshot: Dictionary,
	location_snapshot: Dictionary,
	event_knowledge_snapshot: Dictionary
) -> bool:
	if not _player.restore(player_snapshot):
		return false
	if not _wallet.restore(wallet_snapshot):
		return false
	if not _location.restore(location_snapshot):
		return false
	return _event_knowledge.restore(event_knowledge_snapshot)


static func _is_composition_valid(
	player_value: VNextPlayerState,
	wallet_value: VNextPersonalWallet,
	location_value: VNextLocationState,
	event_knowledge_value: VNextEventKnowledgeState
) -> bool:
	if (
		player_value == null
		or wallet_value == null
		or location_value == null
		or event_knowledge_value == null
	):
		return false
	if not player_value.is_valid():
		return false
	if not wallet_value.is_valid():
		return false
	if not location_value.is_valid():
		return false
	if not VNextStableId.is_valid(event_knowledge_value.player_id()):
		return false
	if VNextStableId.kind_of(event_knowledge_value.player_id()) != "person":
		return false

	var authoritative_player_id: String = player_value.player_id()
	return (
		wallet_value.owner_id() == authoritative_player_id
		and location_value.player_id() == authoritative_player_id
		and event_knowledge_value.player_id() == authoritative_player_id
	)


static func _normalize_json_safe_nonnegative_int(candidate_value: Variant) -> int:
	var candidate_type: int = typeof(candidate_value)
	if candidate_type == TYPE_INT:
		var candidate_int: int = int(candidate_value)
		if candidate_int < 0 or candidate_int > MAX_JSON_SAFE_INTEGER:
			return -1
		return candidate_int
	if candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float):
			return -1
		if candidate_float < 0.0 or candidate_float > float(MAX_JSON_SAFE_INTEGER):
			return -1
		if candidate_float != floor(candidate_float):
			return -1
		return int(candidate_float)
	return -1
