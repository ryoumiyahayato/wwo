class_name VNextMilitaryStateInvariants
extends RefCounted
## Restore/runtime invariants that cross multiple Military state containers.
## VNextMilitaryState remains the state owner; this helper only validates the
## already-authoritative state and does not introduce a second ledger.

const EPSILON: float = 0.0001


static func validate(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	spatial_world: VNextSpatialWorld = null
) -> bool:
	if state == null:
		return false
	if not _validate_action_lifecycles(state):
		return false
	if not _validate_control_claims(state, map):
		return false
	if not _validate_transport_chronology(state):
		return false
	if not _validate_capacity_ledger(state, map, spatial_world):
		return false
	return true


static func _validate_action_lifecycles(state: VNextMilitaryState) -> bool:
	var completed_by_id: Dictionary = {}
	var battle_by_id: Dictionary = {}
	var control_claim_source_ids: Dictionary = {}
	var maximum_sequence: int = 0

	for record: Dictionary in state.completed_actions:
		var action_id: String = str(record.get("action_id", ""))
		var sequence: int = _action_sequence(action_id)
		if sequence < 1 or completed_by_id.has(action_id):
			return false
		if not _completed_record_valid(record):
			return false
		completed_by_id[action_id] = record
		maximum_sequence = maxi(maximum_sequence, sequence)

	for record: Dictionary in state.battle_results:
		var action_id: String = str(record.get("action_id", ""))
		var sequence: int = _action_sequence(action_id)
		if sequence < 1 or battle_by_id.has(action_id):
			return false
		if completed_by_id.has(action_id):
			var completion: Dictionary = completed_by_id[action_id] as Dictionary
			if str(completion.get("kind", "")) != "attack":
				return false
		battle_by_id[action_id] = record
		maximum_sequence = maxi(maximum_sequence, sequence)

	for record: Dictionary in state.control_claims:
		var battle_value: Variant = record.get("battle_result", {})
		if not battle_value is Dictionary:
			return false
		var source_action_id: String = str((battle_value as Dictionary).get("action_id", ""))
		var sequence: int = _action_sequence(source_action_id)
		if sequence < 1 or control_claim_source_ids.has(source_action_id):
			return false
		control_claim_source_ids[source_action_id] = str(record.get("location", ""))
		maximum_sequence = maxi(maximum_sequence, sequence)
		if completed_by_id.has(source_action_id):
			var completion: Dictionary = completed_by_id[source_action_id] as Dictionary
			if str(completion.get("kind", "")) != "attack":
				return false
		if battle_by_id.has(source_action_id):
			var battle: Dictionary = battle_by_id[source_action_id] as Dictionary
			if str(battle.get("target_region_id", "")) != str(record.get("location", "")):
				return false
			if str(battle.get("outcome", "")) != "attacker_win":
				return false

	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var sequence: int = _action_sequence(action_id)
		if sequence < 1:
			return false
		if completed_by_id.has(action_id) or battle_by_id.has(action_id) or control_claim_source_ids.has(action_id):
			return false
		maximum_sequence = maxi(maximum_sequence, sequence)

	return state.next_action_sequence > maximum_sequence


static func _completed_record_valid(record: Dictionary) -> bool:
	if str(record.get("kind", "")) != "supply":
		return true
	var total: float = float(record.get("cargo_amount_total", -1.0))
	var delivered: float = float(record.get("cargo_delivered", -1.0))
	var lost: float = float(record.get("cargo_lost", -1.0))
	if not is_finite(total) or not is_finite(delivered) or not is_finite(lost):
		return false
	if total <= 0.0 or delivered < 0.0 or lost < 0.0 or absf(total - delivered - lost) > EPSILON:
		return false
	if str(record.get("resource_id", "")).is_empty() or str(record.get("destination_formation_id", "")).is_empty() or str(record.get("source_region_id", "")).is_empty():
		return false
	return true


static func _validate_control_claims(
	state: VNextMilitaryState, map: VNextMilitaryMapAdapter
) -> bool:
	var seen_action_ids: Dictionary = {}
	for record: Dictionary in state.control_claims:
		var claim := VNextMilitaryControlClaim.new()
		if not claim.restore(record) or claim.timestamp > state.last_simulated_hour:
			return false
		if map != null and not map.has_region(claim.location):
			return false
		var action_id: String = str(claim.battle_result.get("action_id", ""))
		if seen_action_ids.has(action_id):
			return false
		seen_action_ids[action_id] = true
		var matched_battle: bool = false
		for battle: Dictionary in state.battle_results:
			if str(battle.get("action_id", "")) != action_id:
				continue
			if (
				str(battle.get("outcome", "")) != "attacker_win"
				or str(battle.get("target_region_id", "")) != claim.location
			):
				return false
			matched_battle = true
			break
		if not matched_battle:
			return false
	return true


static func _validate_transport_chronology(state: VNextMilitaryState) -> bool:
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		var kind: String = str(action.get("kind", ""))
		if kind == "defend" or str(action.get("transport_state", "")) in ["preparing", "arrived"]:
			continue
		var request_hour: int = int(action.get("edge_request_hour", -1))
		var started_hour: int = int(action.get("edge_started_hour", -1))
		var elapsed_hours: int = int(action.get("edge_elapsed_hours", -1))
		if request_hour < int(action.get("start_hour", 0)) or request_hour > state.last_simulated_hour:
			return false
		if started_hour < -1 or started_hour > state.last_simulated_hour or elapsed_hours < 0:
			return false
		if started_hour == -1 and elapsed_hours != 0:
			return false
		if started_hour >= 0:
			if started_hour < request_hour:
				return false
			if elapsed_hours > state.last_simulated_hour - started_hour:
				return false
	return true


static func _validate_capacity_ledger(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	spatial_world: VNextSpatialWorld = null
) -> bool:
	var explained: Dictionary = {}
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if not _validate_capacity_record(state, map, spatial_world, action, true, explained):
			return false
	for record: Dictionary in state.completed_actions:
		if not _validate_capacity_record(state, map, spatial_world, record, false, explained):
			return false

	var link_ids: Dictionary = {}
	for raw_link_id: Variant in state.link_capacity_used.keys():
		link_ids[str(raw_link_id)] = true
	for raw_link_id: Variant in explained.keys():
		link_ids[str(raw_link_id)] = true
	for link_id: String in _sorted_dictionary_keys(link_ids):
		var actual: float = float(state.link_capacity_used.get(link_id, 0.0))
		var expected: float = float(explained.get(link_id, 0.0))
		if not is_finite(actual) or actual < 0.0 or absf(actual - expected) > EPSILON:
			return false
		if map != null and map.get_link(link_id).is_empty():
			return false
	return true


static func _validate_capacity_record(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	spatial_world: VNextSpatialWorld,
	record: Dictionary,
	is_active: bool,
	explained: Dictionary
) -> bool:
	var window_hour: int = int(record.get("capacity_window_hour", -1))
	var link_id: String = str(record.get("capacity_link_id", ""))
	var used: float = float(record.get("capacity_used_this_window", 0.0))
	var spatial_request_id: String = str(record.get("spatial_request_id", ""))
	if not is_finite(used) or used < 0.0 or window_hour < -1 or window_hour > state.capacity_window_hour:
		return false
	if not spatial_request_id.is_empty():
		# A persisted current reservation reference is legal only while Spatial still
		# owns that exact current request. Closed historical attribution never needs it.
		if spatial_world == null or window_hour != spatial_world.current_hour() or link_id.is_empty():
			return false
		var reservation: Dictionary = spatial_world.reservation_result(spatial_request_id, link_id, window_hour)
		if not bool(reservation.get("accepted", false)):
			return false
		if absf(float(reservation.get("allocated_capacity", -1.0)) - used) > EPSILON:
			return false
	if used <= EPSILON:
		return link_id.is_empty() or not spatial_request_id.is_empty()
	if link_id.is_empty() or map == null or map.get_link(link_id).is_empty():
		return false
	if not _capacity_link_matches_record(record, link_id, is_active):
		return false
	if window_hour == state.capacity_window_hour:
		explained[link_id] = float(explained.get(link_id, 0.0)) + used
	return true


static func _capacity_link_matches_record(record: Dictionary, link_id: String, is_active: bool) -> bool:
	var route_value: Variant = record.get("route", {})
	if not route_value is Dictionary:
		return false
	var links_value: Variant = (route_value as Dictionary).get("link_ids", [])
	if not links_value is Array:
		return false
	var link_ids: Array = links_value as Array
	if not link_ids.has(link_id):
		return false
	if not is_active:
		return true
	var edge_index: int = int(record.get("current_edge_index", -1))
	if edge_index < 0:
		return false
	if edge_index >= link_ids.size():
		return not link_ids.is_empty() and str(link_ids[link_ids.size() - 1]) == link_id
	if str(link_ids[edge_index]) == link_id:
		return true
	return edge_index > 0 and str(link_ids[edge_index - 1]) == link_id


static func _action_sequence(action_id: String) -> int:
	if VNextStableId.kind_of(action_id) != "military_action":
		return -1
	var local_id: String = VNextStableId.local_id_of(action_id)
	if local_id.is_empty():
		return -1
	for index: int in local_id.length():
		if not "0123456789".contains(local_id.substr(index, 1)):
			return -1
	return int(local_id)


static func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in source.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids
