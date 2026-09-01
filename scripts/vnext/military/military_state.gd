class_name VNextMilitaryState
extends RefCounted
## Dynamic military state. Spatial owns physical infrastructure/capacity; this state keeps Military attribution only.

const SCHEMA_ID: String = "vnext_military_state_v3"
const ACTION_KINDS: PackedStringArray = ["deploy", "move", "concentrate", "defend", "attack", "supply"]
const TRANSPORT_STATES: PackedStringArray = ["waiting_capacity", "moving", "blocked", "interrupted", "preparing", "arrived"]
const MAX_COMPLETED_ACTIONS: int = 256
const MAX_BATTLE_RESULTS: int = 128
const MAX_CONTROL_CLAIMS: int = 256
const SNAPSHOT_FIELDS: PackedStringArray = [
	"schema_id",
	"last_simulated_hour",
	"next_action_sequence",
	"formations",
	"region_garrisons",
	"active_actions",
	"completed_actions",
	"battle_results",
	"control_claims",
	"capacity_window_hour",
]

var formations: Dictionary = {}
var region_garrisons: Dictionary = {}
var active_actions: Dictionary = {}
var completed_actions: Array[Dictionary] = []
var battle_results: Array[Dictionary] = []
var control_claims: Array[Dictionary] = []
var last_simulated_hour: int = 0
var next_action_sequence: int = 1

# External hourly/daily availability is injected runtime context. It is never
# authoritative Economy stock and is deliberately excluded from snapshots.
var _external_supply_allocations: Dictionary = {}

# Last closed Military transport window: diagnostic attribution only, never a physical budget or authority.
var capacity_window_hour: int = -1
var link_capacity_used: Dictionary = {}
var link_queues: Dictionary = {}


func initialize(map: VNextMilitaryMapAdapter) -> bool:
	if map == null:
		return false
	formations.clear()
	region_garrisons.clear()
	_external_supply_allocations.clear()
	active_actions.clear()
	completed_actions.clear()
	battle_results.clear()
	control_claims.clear()
	link_capacity_used.clear()
	link_queues.clear()
	last_simulated_hour = 0
	next_action_sequence = 1
	capacity_window_hour = -1
	for region_id: String in map.get_region_ids():
		region_garrisons[region_id] = map.get_initial_garrison(region_id)
	return is_valid(map)


func is_valid(map: VNextMilitaryMapAdapter = null) -> bool:
	if last_simulated_hour < 0 or next_action_sequence < 1 or region_garrisons.is_empty():
		return false
	if capacity_window_hour > last_simulated_hour:
		return false
	if capacity_window_hour >= 0 and capacity_window_hour != last_simulated_hour - 1:
		return false
	if completed_actions.size() > MAX_COMPLETED_ACTIONS or battle_results.size() > MAX_BATTLE_RESULTS or control_claims.size() > MAX_CONTROL_CLAIMS:
		return false

	for region_id: String in _sorted_dictionary_keys(region_garrisons):
		var garrison_value: float = float(region_garrisons[region_id])
		if not is_finite(garrison_value) or garrison_value < 0.0:
			return false
		if map != null and not map.has_region(region_id):
			return false
	for raw_input_id: Variant in _external_supply_allocations.keys():
		var input: Variant = _external_supply_allocations[raw_input_id]
		if not input is Dictionary or not _is_supply_input_valid(input as Dictionary):
			return false
		if map != null and not map.has_region(str(raw_input_id)):
			return false

	for formation_id: String in get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = formations[formation_id] as VNextMilitaryFormation
		if formation == null or formation.formation_id != formation_id or VNextStableId.kind_of(formation_id) != "formation" or not formation.is_valid():
			return false
		if map != null and (not map.has_city(formation.current_city_id) or not map.has_country(formation.country_id)):
			return false

	var logged_action_ids: Dictionary = {}
	var maximum_sequence: int = 0
	for record: Dictionary in completed_actions:
		if not _history_action_record_valid(record):
			return false
		var completed_id: String = str(record.get("action_id", ""))
		if not completed_id.is_empty():
			if logged_action_ids.has(completed_id):
				return false
			logged_action_ids[completed_id] = true
			maximum_sequence = maxi(maximum_sequence, _action_sequence(completed_id))
	for record: Dictionary in battle_results:
		var battle_id: String = str(record.get("action_id", ""))
		if VNextStableId.kind_of(battle_id) != "military_action":
			return false
		maximum_sequence = maxi(maximum_sequence, _action_sequence(battle_id))
	for record: Dictionary in control_claims:
		var claim := VNextMilitaryControlClaim.new()
		if not claim.restore(record):
			return false
		if map != null and not map.has_region(claim.location):
			return false

	var active_formation_ids: Dictionary = {}
	for action_id: String in _sorted_dictionary_keys(active_actions):
		var raw_action: Variant = active_actions[action_id]
		if not raw_action is Dictionary:
			return false
		var action: Dictionary = raw_action as Dictionary
		if logged_action_ids.has(action_id) or not _active_action_valid(action_id, action, map):
			return false
		if str(action.get("kind", "")) != "supply":
			var formation_id: String = str(action.get("formation_id", ""))
			if active_formation_ids.has(formation_id):
				return false
			active_formation_ids[formation_id] = action_id
		maximum_sequence = maxi(maximum_sequence, _action_sequence(action_id))
	if next_action_sequence <= maximum_sequence:
		return false

	# Reverse invariant: every non-idle active formation owns exactly one matching action,
	# and idle/destroyed formations own none.
	for formation_id: String in get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = formations[formation_id] as VNextMilitaryFormation
		var has_action: bool = active_formation_ids.has(formation_id)
		if formation.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
			if has_action or formation.action_state != VNextMilitaryFormation.ACTION_IDLE:
				return false
		elif formation.action_state == VNextMilitaryFormation.ACTION_IDLE:
			if has_action:
				return false
		elif not has_action:
			return false

	for raw_link_id: Variant in link_capacity_used.keys():
		var link_id: String = str(raw_link_id)
		var used: float = float(link_capacity_used[raw_link_id])
		if not is_finite(used) or used < 0.0:
			return false
		if map != null and map.get_link(link_id).is_empty():
			return false

	var queued_request_links: Dictionary = {}
	for raw_link_id: Variant in link_queues.keys():
		var link_id: String = str(raw_link_id)
		var queue_value: Variant = link_queues[raw_link_id]
		if not queue_value is Array:
			return false
		if map != null and map.get_link(link_id).is_empty():
			return false
		for raw_request_id: Variant in queue_value as Array:
			var request_id: String = str(raw_request_id)
			if request_id.is_empty() or not active_actions.has(request_id):
				return false
			if queued_request_links.has(request_id):
				return false
			var action: Dictionary = active_actions[request_id] as Dictionary
			if _current_transport_link_id(action) != link_id:
				return false
			if int(action.get("edge_request_hour", -1)) < 0 or (capacity_window_hour >= 0 and int(action.get("edge_request_hour", -1)) > capacity_window_hour):
				return false
			var load_remaining: float = float(action.get("edge_load_remaining", -1.0))
			var reserved_link_id: String = str(action.get("reserved_link_id", ""))
			if load_remaining > 0.0001 and reserved_link_id != link_id:
				return false
			if load_remaining <= 0.0001 and not reserved_link_id.is_empty():
				return false
			queued_request_links[request_id] = link_id

	for action_id: String in _sorted_dictionary_keys(active_actions):
		var action: Dictionary = active_actions[action_id] as Dictionary
		var reserved_link_id: String = str(action.get("reserved_link_id", ""))
		if reserved_link_id.is_empty():
			continue
		if not queued_request_links.has(action_id) or str(queued_request_links[action_id]) != reserved_link_id:
			return false
	return true


func add_formation(formation: VNextMilitaryFormation) -> bool:
	if formation == null or not formation.is_valid() or VNextStableId.kind_of(formation.formation_id) != "formation" or formations.has(formation.formation_id):
		return false
	formations[formation.formation_id] = formation
	return true


func get_formation(formation_id: String) -> VNextMilitaryFormation:
	return formations.get(formation_id) as VNextMilitaryFormation


func get_sorted_formation_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in formations.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func set_external_supply_allocation(region_id: String, input: Dictionary) -> bool:
	if region_id.is_empty() or not region_garrisons.has(region_id) or not _is_supply_input_valid(input):
		return false
	_external_supply_allocations[region_id] = {
		"food": float(input.get("food", 0.0)),
		"ammunition": float(input.get("ammunition", 0.0)),
		"equipment": float(input.get("equipment", 0.0)),
		"transport_capacity": float(input.get("transport_capacity", 0.0)),
	}
	return true


func external_supply_allocations() -> Dictionary:
	return _external_supply_allocations.duplicate(true)


func begin_capacity_window(hour: int) -> void:
	capacity_window_hour = hour
	link_capacity_used.clear()
	link_queues.clear()


func queue_capacity_request(link_id: String, request_id: String) -> void:
	if not link_queues.has(link_id):
		link_queues[link_id] = []
	var queue: Array = link_queues[link_id] as Array
	if not queue.has(request_id):
		queue.append(request_id)


func remove_capacity_request(request_id: String) -> void:
	if request_id.is_empty():
		return
	for link_id: String in _sorted_dictionary_keys(link_queues):
		var queue: Array = link_queues[link_id] as Array
		while queue.has(request_id):
			queue.erase(request_id)


func record_capacity_use(link_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	link_capacity_used[link_id] = float(link_capacity_used.get(link_id, 0.0)) + amount


func append_completed_action(record: Dictionary) -> void:
	completed_actions.append(record.duplicate(true))
	_trim_history(completed_actions, MAX_COMPLETED_ACTIONS)


func append_battle_result(record: Dictionary) -> void:
	battle_results.append(record.duplicate(true))
	_trim_history(battle_results, MAX_BATTLE_RESULTS)


func append_control_claim(claim: VNextMilitaryControlClaim) -> bool:
	if claim == null or not claim.is_valid() or claim.timestamp != last_simulated_hour:
		return false
	for record: Dictionary in control_claims:
		if str((record.get("battle_result", {}) as Dictionary).get("action_id", "")) == str(claim.battle_result.get("action_id", "")):
			return false
	control_claims.append(claim.snapshot())
	_trim_history(control_claims, MAX_CONTROL_CLAIMS)
	return true


func snapshot() -> Dictionary:
	var formation_snapshots: Array[Dictionary] = []
	for formation_id: String in get_sorted_formation_ids():
		formation_snapshots.append((formations[formation_id] as VNextMilitaryFormation).to_dict())
	var action_snapshots: Array[Dictionary] = []
	for action_id: String in _sorted_dictionary_keys(active_actions):
		action_snapshots.append((active_actions[action_id] as Dictionary).duplicate(true))
	return {
		"schema_id": SCHEMA_ID,
		"last_simulated_hour": last_simulated_hour,
		"next_action_sequence": next_action_sequence,
		"formations": formation_snapshots,
		"region_garrisons": region_garrisons.duplicate(true),
		"active_actions": action_snapshots,
		"completed_actions": completed_actions.duplicate(true),
		"battle_results": battle_results.duplicate(true),
		"control_claims": control_claims.duplicate(true),
		"capacity_window_hour": capacity_window_hour,
	}


func restore(snapshot_value: Dictionary, map: VNextMilitaryMapAdapter = null, spatial_world: VNextSpatialWorld = null) -> bool:
	if not _has_exact_snapshot_fields(snapshot_value):
		return false
	var formation_value: Variant = snapshot_value.get("formations", [])
	var active_action_value: Variant = snapshot_value.get("active_actions", [])
	var completed_value: Variant = snapshot_value.get("completed_actions", [])
	var battle_value: Variant = snapshot_value.get("battle_results", [])
	var claims_value: Variant = snapshot_value.get("control_claims", [])
	var garrisons_value: Variant = snapshot_value.get("region_garrisons", {})
	if snapshot_value.get("schema_id", "") != SCHEMA_ID:
		return false
	if not formation_value is Array or not active_action_value is Array or not completed_value is Array or not battle_value is Array or not claims_value is Array:
		return false
	if not garrisons_value is Dictionary:
		return false
	if not _array_contains_only_dictionaries(completed_value as Array) or not _array_contains_only_dictionaries(battle_value as Array) or not _array_contains_only_dictionaries(claims_value as Array):
		return false
	if int(snapshot_value.get("last_simulated_hour", -1)) < 0 or int(snapshot_value.get("next_action_sequence", 0)) < 1:
		return false

	var candidate_formations: Dictionary = {}
	for raw_formation: Variant in formation_value as Array:
		if not raw_formation is Dictionary:
			return false
		var formation := VNextMilitaryFormation.new()
		if not formation.restore(raw_formation as Dictionary) or candidate_formations.has(formation.formation_id):
			return false
		candidate_formations[formation.formation_id] = formation

	var candidate_actions: Dictionary = {}
	for raw_action: Variant in active_action_value as Array:
		if not raw_action is Dictionary:
			return false
		var action: Dictionary = raw_action as Dictionary
		var action_id: String = str(action.get("action_id", ""))
		if VNextStableId.kind_of(action_id) != "military_action" or candidate_actions.has(action_id):
			return false
		candidate_actions[action_id] = action.duplicate(true)

	var candidate_state := VNextMilitaryState.new()
	candidate_state.formations = candidate_formations
	candidate_state.active_actions = candidate_actions
	candidate_state.region_garrisons = (garrisons_value as Dictionary).duplicate(true)
	candidate_state.completed_actions = _dictionary_array(completed_value as Array)
	candidate_state.battle_results = _dictionary_array(battle_value as Array)
	candidate_state.control_claims = _dictionary_array(claims_value as Array)
	candidate_state.last_simulated_hour = int(snapshot_value["last_simulated_hour"])
	candidate_state.next_action_sequence = int(snapshot_value["next_action_sequence"])
	candidate_state.capacity_window_hour = int(snapshot_value.get("capacity_window_hour", -1))
	candidate_state._rebuild_transient_transport_attribution()
	if not candidate_state.is_valid(map) or not VNextMilitaryStateInvariants.validate(candidate_state, map, spatial_world):
		return false

	formations = candidate_state.formations
	active_actions = candidate_state.active_actions
	region_garrisons = candidate_state.region_garrisons
	_external_supply_allocations.clear()
	completed_actions = candidate_state.completed_actions
	battle_results = candidate_state.battle_results
	control_claims = candidate_state.control_claims
	last_simulated_hour = candidate_state.last_simulated_hour
	next_action_sequence = candidate_state.next_action_sequence
	capacity_window_hour = candidate_state.capacity_window_hour
	link_capacity_used = candidate_state.link_capacity_used
	link_queues = candidate_state.link_queues
	return true


func _rebuild_transient_transport_attribution() -> void:
	link_capacity_used.clear()
	link_queues.clear()
	for action_id: String in _sorted_dictionary_keys(active_actions):
		var action: Dictionary = active_actions[action_id] as Dictionary
		var reserved_link_id: String = str(action.get("reserved_link_id", ""))
		if not reserved_link_id.is_empty():
			if not link_queues.has(reserved_link_id):
				link_queues[reserved_link_id] = []
			(link_queues[reserved_link_id] as Array).append(action_id)
		_accumulate_current_capacity_attribution(action)
	for record: Dictionary in completed_actions:
		_accumulate_current_capacity_attribution(record)


func _accumulate_current_capacity_attribution(record: Dictionary) -> void:
	if int(record.get("capacity_window_hour", -1)) != capacity_window_hour:
		return
	var link_id: String = str(record.get("capacity_link_id", ""))
	var used: float = float(record.get("capacity_used_this_window", 0.0))
	if link_id.is_empty() or not is_finite(used) or used <= 0.0:
		return
	link_capacity_used[link_id] = float(link_capacity_used.get(link_id, 0.0)) + used


func _active_action_valid(
	action_id: String,
	action: Dictionary,
	map: VNextMilitaryMapAdapter
) -> bool:
	if str(action.get("action_id", "")) != action_id or VNextStableId.kind_of(action_id) != "military_action" or _action_sequence(action_id) < 1:
		return false
	var kind: String = str(action.get("kind", ""))
	if not ACTION_KINDS.has(kind):
		return false
	if kind == "supply":
		return _supply_action_valid(action, map)

	var formation_id: String = str(action.get("formation_id", ""))
	if VNextStableId.kind_of(formation_id) != "formation" or not formations.has(formation_id):
		return false
	var formation: VNextMilitaryFormation = formations[formation_id] as VNextMilitaryFormation
	if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
		return false
	var expected_action_state: String = VNextMilitaryFormation.ACTION_MOVING
	match kind:
		"concentrate":
			expected_action_state = VNextMilitaryFormation.ACTION_CONCENTRATING
		"attack":
			expected_action_state = VNextMilitaryFormation.ACTION_ATTACKING
		"defend":
			expected_action_state = VNextMilitaryFormation.ACTION_DEFENDING
	if formation.action_state != expected_action_state:
		return false

	var start_hour: int = int(action.get("start_hour", -1))
	var eta_hour: int = int(action.get("eta_hour", -1))
	if start_hour < 0 or eta_hour <= start_hour or start_hour > last_simulated_hour:
		return false
	var progress: float = float(action.get("progress", -1.0))
	if not is_finite(progress) or progress < 0.0 or progress > 1.0:
		return false
	var origin_city_id: String = str(action.get("origin_city_id", ""))
	var destination_city_id: String = str(action.get("destination_city_id", ""))
	if origin_city_id.is_empty() or destination_city_id.is_empty():
		return false
	if map != null and (not map.has_city(origin_city_id) or not map.has_city(destination_city_id)):
		return false

	var route_value: Variant = action.get("route", {})
	if not route_value is Dictionary:
		return false
	var route: Dictionary = route_value as Dictionary
	if kind == "defend":
		return origin_city_id == destination_city_id and route.is_empty()
	if origin_city_id == destination_city_id:
		return false
	if not _transport_route_valid(route, origin_city_id, destination_city_id, map):
		return false
	var route_duration: int = int(route.get("duration_hours", 0))
	if route_duration <= 0 or eta_hour - start_hour < route_duration:
		return false
	if kind == "attack":
		var preparation_hours_contract: int = int(action.get("attack_preparation_hours", 0))
		if preparation_hours_contract <= 0 or eta_hour - start_hour < route_duration + preparation_hours_contract:
			return false
		if VNextStableId.kind_of(str(action.get("political_authorization_id", ""))) != "event":
			return false
		if VNextStableId.kind_of(str(action.get("political_state_id", ""))) != "state":
			return false
		if VNextStableId.kind_of(str(action.get("order_authorization_id", ""))) != "event":
			return false
		if str(action.get("issuing_organization_id", "")) != formation.unit_organization_id:
			return false

	var city_ids: Array = route.get("city_ids", []) as Array
	var link_ids: Array = route.get("link_ids", []) as Array
	var edge_index: int = int(action.get("current_edge_index", -1))
	if edge_index < 0 or edge_index > link_ids.size():
		return false
	var transport_state: String = str(action.get("transport_state", ""))
	if not TRANSPORT_STATES.has(transport_state) or transport_state == "arrived":
		return false
	var reserved_link_id: String = str(action.get("reserved_link_id", ""))

	if edge_index < link_ids.size():
		if not _transport_edge_state_valid(action, route, edge_index, formation.current_city_id, formation.country_id, destination_city_id, bool(action.get("allow_enemy_destination", false)), map):
			return false
		if kind == "attack" and progress >= 0.95:
			return false
	else:
		if kind != "attack" or transport_state != "preparing":
			return false
		if progress < 0.95 or progress >= 1.0 or not reserved_link_id.is_empty():
			return false
		if city_ids.size() < 2 or formation.current_city_id != str(city_ids[city_ids.size() - 2]):
			return false
		if float(action.get("edge_load_total", -1.0)) != 0.0 or float(action.get("edge_load_remaining", -1.0)) != 0.0:
			return false
		var preparation_hours: int = int(action.get("attack_preparation_hours", 0))
		var preparation_start: int = int(action.get("preparation_start_hour", -1))
		var preparation_end: int = int(action.get("preparation_end_hour", -1))
		if preparation_hours <= 0 or preparation_start < start_hour or preparation_start > last_simulated_hour:
			return false
		if preparation_end != preparation_start + preparation_hours or preparation_end <= preparation_start:
			return false
		if last_simulated_hour >= preparation_end:
			return false
	return true


func _supply_action_valid(action: Dictionary, map: VNextMilitaryMapAdapter) -> bool:
	var destination_formation_id: String = str(action.get("destination_formation_id", ""))
	if VNextStableId.kind_of(destination_formation_id) != "formation" or not formations.has(destination_formation_id):
		return false
	var formation: VNextMilitaryFormation = formations[destination_formation_id] as VNextMilitaryFormation
	if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
		return false
	var owner_country_id: String = str(action.get("owner_country_id", ""))
	if owner_country_id != formation.country_id:
		return false
	var resource_id: String = str(action.get("resource_id", ""))
	if not ["food", "ammunition", "equipment", "transport_capacity"].has(resource_id):
		return false
	var cargo_total: float = float(action.get("cargo_amount_total", -1.0))
	var cargo_remaining: float = float(action.get("cargo_amount_remaining", -1.0))
	if not is_finite(cargo_total) or not is_finite(cargo_remaining) or cargo_total <= 0.0 or cargo_remaining <= 0.0 or cargo_remaining > cargo_total + 0.0001:
		return false
	var origin_city_id: String = str(action.get("origin_city_id", ""))
	var destination_city_id: String = str(action.get("destination_city_id", ""))
	var current_city_id: String = str(action.get("current_city_id", ""))
	var source_region_id: String = str(action.get("source_region_id", ""))
	var start_hour: int = int(action.get("start_hour", -1))
	var eta_hour: int = int(action.get("eta_hour", -1))
	var progress: float = float(action.get("progress", -1.0))
	if origin_city_id.is_empty() or destination_city_id.is_empty() or current_city_id.is_empty() or source_region_id.is_empty():
		return false
	if start_hour < 0 or eta_hour <= start_hour or start_hour > last_simulated_hour or not is_finite(progress) or progress < 0.0 or progress > 1.0:
		return false
	if map != null and (not map.has_city(origin_city_id) or not map.has_city(destination_city_id) or not map.has_city(current_city_id) or not map.has_region(source_region_id) or not map.has_country(owner_country_id)):
		return false
	var route_value: Variant = action.get("route", {})
	if not route_value is Dictionary:
		return false
	var route: Dictionary = route_value as Dictionary
	if not _transport_route_valid(route, origin_city_id, destination_city_id, map):
		return false
	var route_duration: int = int(route.get("duration_hours", 0))
	if route_duration <= 0 or eta_hour - start_hour < route_duration:
		return false
	var link_ids: Array = route.get("link_ids", []) as Array
	var city_ids: Array = route.get("city_ids", []) as Array
	var edge_index: int = int(action.get("current_edge_index", -1))
	var transport_state: String = str(action.get("transport_state", ""))
	if edge_index < 0 or edge_index > link_ids.size() or not TRANSPORT_STATES.has(transport_state) or transport_state == "preparing":
		return false
	if edge_index == link_ids.size():
		return (
			transport_state == "arrived"
			and progress == 1.0
			and current_city_id == destination_city_id
			and str(action.get("reserved_link_id", "")).is_empty()
			and is_zero_approx(float(action.get("edge_load_total", -1.0)))
			and is_zero_approx(float(action.get("edge_load_remaining", -1.0)))
			and int(action.get("edge_started_hour", -2)) == -1
			and int(action.get("edge_elapsed_hours", -1)) == 0
		)
	if current_city_id != str(city_ids[edge_index]):
		return false
	if not is_equal_approx(cargo_remaining, cargo_total):
		return false
	var expected_edge_load: float = cargo_remaining * supply_cargo_weight(resource_id)
	if expected_edge_load <= 0.0 or absf(float(action.get("edge_load_total", -1.0)) - expected_edge_load) > 0.0001:
		return false
	if map != null and map.get_region_id_for_city(origin_city_id) != source_region_id:
		return false
	return _transport_edge_state_valid(action, route, edge_index, current_city_id, owner_country_id, destination_city_id, false, map)


func _transport_edge_state_valid(
	action: Dictionary,
	route: Dictionary,
	edge_index: int,
	current_city_id: String,
	owner_country_id: String,
	destination_city_id: String,
	allow_enemy_destination: bool,
	map: VNextMilitaryMapAdapter
) -> bool:
	var link_ids: Array = route.get("link_ids", []) as Array
	if edge_index < 0 or edge_index >= link_ids.size():
		return false
	var edge_count: float = float(link_ids.size())
	var progress: float = float(action.get("progress", -1.0))
	var minimum_progress: float = float(edge_index) / edge_count
	var maximum_progress: float = float(edge_index + 1) / edge_count
	if progress + 0.0001 < minimum_progress or progress > maximum_progress + 0.0001:
		return false
	var load_total: float = float(action.get("edge_load_total", -1.0))
	var load_remaining: float = float(action.get("edge_load_remaining", -1.0))
	if not is_finite(load_total) or not is_finite(load_remaining) or load_total <= 0.0 or load_remaining < 0.0 or load_remaining > load_total + 0.0001:
		return false
	var edge_request_hour: int = int(action.get("edge_request_hour", -1))
	var edge_started_hour: int = int(action.get("edge_started_hour", -2))
	var edge_elapsed_hours: int = int(action.get("edge_elapsed_hours", -1))
	if edge_request_hour < int(action.get("start_hour", 0)) or edge_request_hour > last_simulated_hour:
		return false
	if edge_started_hour < -1 or edge_started_hour > last_simulated_hour or edge_elapsed_hours < 0:
		return false
	if edge_started_hour == -1 and edge_elapsed_hours != 0:
		return false
	if edge_started_hour >= 0 and edge_elapsed_hours > last_simulated_hour - edge_started_hour:
		return false
	var transport_state: String = str(action.get("transport_state", ""))
	var reserved_link_id: String = str(action.get("reserved_link_id", ""))
	var current_link_id: String = str(link_ids[edge_index])
	if not reserved_link_id.is_empty() and reserved_link_id != current_link_id:
		return false
	if load_remaining > 0.0001 and transport_state == "moving" and reserved_link_id != current_link_id:
		return false
	if load_remaining > 0.0001 and transport_state == "waiting_capacity" and reserved_link_id.is_empty() and edge_request_hour <= capacity_window_hour:
		return false
	if load_remaining > 0.0001 and transport_state == "waiting_capacity" and not reserved_link_id.is_empty() and reserved_link_id != current_link_id:
		return false
	if load_remaining <= 0.0001 and not reserved_link_id.is_empty():
		return false
	var progress_cap: float = 0.94 if str(action.get("kind", "")) == "attack" else 0.999
	var expected_progress: float = clampf((float(edge_index) + clampf(1.0 - load_remaining / load_total, 0.0, 1.0)) / edge_count, 0.0, progress_cap)
	if absf(progress - expected_progress) > 0.001:
		return false
	if map != null:
		var link: Dictionary = map.get_link(current_link_id)
		if link.is_empty():
			return false
		var requires_active_access: bool = transport_state == "moving" or not reserved_link_id.is_empty() or (transport_state == "waiting_capacity" and edge_request_hour <= capacity_window_hour)
		if requires_active_access and map.get_link_transport_capacity_per_hour(current_link_id) > 0.0:
			if not map.can_enter_link(current_link_id, current_city_id, destination_city_id, owner_country_id, allow_enemy_destination):
				return false
	return true


func _transport_route_valid(
	route: Dictionary,
	origin_city_id: String,
	destination_city_id: String,
	map: VNextMilitaryMapAdapter
) -> bool:
	if not bool(route.get("reachable", false)):
		return false
	var city_value: Variant = route.get("city_ids", [])
	var link_value: Variant = route.get("link_ids", [])
	if not city_value is Array or not link_value is Array:
		return false
	var city_ids: Array = city_value as Array
	var link_ids: Array = link_value as Array
	if city_ids.size() < 2 or link_ids.is_empty() or link_ids.size() != city_ids.size() - 1:
		return false
	if str(city_ids[0]) != origin_city_id or str(city_ids[city_ids.size() - 1]) != destination_city_id:
		return false
	var route_duration: int = int(route.get("duration_hours", 0))
	if route_duration <= 0:
		return false
	if map == null:
		return true
	var calculated_duration: int = 0
	for index: int in range(link_ids.size()):
		var link: Dictionary = map.get_link(str(link_ids[index]))
		if link.is_empty():
			return false
		var first_city: String = str(city_ids[index])
		var second_city: String = str(city_ids[index + 1])
		var from_city: String = str(link.get("from_city_id", ""))
		var to_city: String = str(link.get("to_city_id", ""))
		if not ((from_city == first_city and to_city == second_city) or (from_city == second_city and to_city == first_city)):
			return false
		calculated_duration += maxi(1, int(link.get("movement_hours", 0)))
	return route_duration == calculated_duration


func _current_transport_link_id(action: Dictionary) -> String:
	var route_value: Variant = action.get("route", {})
	if not route_value is Dictionary:
		return ""
	var link_value: Variant = (route_value as Dictionary).get("link_ids", [])
	if not link_value is Array:
		return ""
	var link_ids: Array = link_value as Array
	var edge_index: int = int(action.get("current_edge_index", -1))
	if edge_index < 0 or edge_index >= link_ids.size():
		return ""
	return str(link_ids[edge_index])


func _history_action_record_valid(record: Dictionary) -> bool:
	var action_id: String = str(record.get("action_id", ""))
	if VNextStableId.kind_of(action_id) != "military_action" or _action_sequence(action_id) < 1:
		return false
	var kind: String = str(record.get("kind", ""))
	return ACTION_KINDS.has(kind)


func _action_sequence(action_id: String) -> int:
	if VNextStableId.kind_of(action_id) != "military_action":
		return -1
	var local_id: String = VNextStableId.local_id_of(action_id)
	if local_id.is_empty():
		return -1
	for index: int in local_id.length():
		var character: String = local_id.substr(index, 1)
		if not "0123456789".contains(character):
			return -1
	return int(local_id)


static func supply_cargo_weight(resource_id: String) -> float:
	match resource_id:
		"food":
			return 1.0
		"ammunition":
			return 1.25
		"equipment":
			return 2.0
		"transport_capacity":
			return 0.5
		_:
			return 0.0


func _array_contains_only_dictionaries(source: Array) -> bool:
	for raw_value: Variant in source:
		if not raw_value is Dictionary:
			return false
	return true


func _has_exact_snapshot_fields(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != SNAPSHOT_FIELDS.size():
		return false
	for field: String in SNAPSHOT_FIELDS:
		if not snapshot_value.has(field):
			return false
	return true


func _is_supply_input_valid(input: Dictionary) -> bool:
	for resource_id: String in ["food", "ammunition", "equipment", "transport_capacity"]:
		var value: float = float(input.get(resource_id, 0.0))
		if not is_finite(value) or value < 0.0:
			return false
	return true


func _dictionary_array(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_value: Variant in source:
		if raw_value is Dictionary:
			result.append((raw_value as Dictionary).duplicate(true))
	return result


func _trim_history(history: Array[Dictionary], limit: int) -> void:
	while history.size() > limit:
		history.pop_front()


func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in source.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids
