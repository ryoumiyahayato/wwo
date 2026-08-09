class_name VNextMilitaryState
extends RefCounted
## Dynamic military state. Static geography remains in VNextMilitaryMapAdapter.

const SCHEMA_ID: String = "vnext_military_state_v1"

var formations: Dictionary = {}
var region_controls: Dictionary = {}
var region_garrisons: Dictionary = {}
var supply_inputs: Dictionary = {}
var active_actions: Dictionary = {}
var completed_actions: Array[Dictionary] = []
var battle_results: Array[Dictionary] = []
var control_history: Array[Dictionary] = []
var last_simulated_hour: int = 0
var next_action_sequence: int = 1


func initialize(map: VNextMilitaryMapAdapter) -> bool:
	if map == null:
		return false
	formations.clear()
	region_controls.clear()
	region_garrisons.clear()
	supply_inputs.clear()
	active_actions.clear()
	completed_actions.clear()
	battle_results.clear()
	control_history.clear()
	last_simulated_hour = 0
	next_action_sequence = 1
	for region_id: String in map.get_region_ids():
		var controller_id: String = map.get_initial_controller(region_id)
		if controller_id.is_empty():
			return false
		region_controls[region_id] = controller_id
		region_garrisons[region_id] = map.get_initial_garrison(region_id)
	return is_valid(map)


func is_valid(map: VNextMilitaryMapAdapter = null) -> bool:
	if last_simulated_hour < 0 or next_action_sequence < 1 or region_controls.is_empty():
		return false
	for region_id: String in _sorted_dictionary_keys(region_controls):
		var controller_id: String = str(region_controls[region_id])
		if controller_id.is_empty() or not region_garrisons.has(region_id):
			return false
		var garrison_value: float = float(region_garrisons[region_id])
		if not is_finite(garrison_value) or garrison_value < 0.0:
			return false
		if map != null and (not map.has_region(region_id) or not map.has_country(controller_id)):
			return false
	for raw_garrison_id: Variant in region_garrisons.keys():
		if not region_controls.has(str(raw_garrison_id)):
			return false
	for raw_input_id: Variant in supply_inputs.keys():
		var input: Variant = supply_inputs[raw_input_id]
		if not input is Dictionary or not _is_supply_input_valid(input as Dictionary):
			return false
		if map != null and not map.has_region(str(raw_input_id)):
			return false
	for formation_id: String in get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = formations[formation_id] as VNextMilitaryFormation
		if formation == null or formation.formation_id != formation_id or not formation.is_valid():
			return false
		if map != null and (not map.has_city(formation.current_city_id) or not map.has_country(formation.country_id)):
			return false
	var logged_action_ids: Dictionary = {}
	for record: Dictionary in completed_actions:
		var completed_id: String = str(record.get("action_id", ""))
		if not completed_id.is_empty():
			logged_action_ids[completed_id] = true
	for record: Dictionary in battle_results:
		var battle_id: String = str(record.get("action_id", ""))
		if not battle_id.is_empty():
			logged_action_ids[battle_id] = true
	var active_formation_ids: Dictionary = {}
	for action_id: String in _sorted_dictionary_keys(active_actions):
		var action: Variant = active_actions[action_id]
		if not action is Dictionary:
			return false
		var action_data: Dictionary = action as Dictionary
		if str(action_data.get("action_id", "")) != action_id or action_id.is_empty() or logged_action_ids.has(action_id):
			return false
		var action_formation_id: String = str(action_data.get("formation_id", ""))
		if action_formation_id.is_empty() or not formations.has(action_formation_id) or active_formation_ids.has(action_formation_id):
			return false
		var start_hour: int = int(action_data.get("start_hour", -1))
		var eta_hour: int = int(action_data.get("eta_hour", -1))
		if start_hour < 0 or eta_hour < start_hour:
			return false
		if map != null:
			var destination_city_id: String = str(action_data.get("destination_city_id", ""))
			if not destination_city_id.is_empty() and not map.has_city(destination_city_id):
				return false
		active_formation_ids[action_formation_id] = true
	return true


func add_formation(formation: VNextMilitaryFormation) -> bool:
	if formation == null or not formation.is_valid() or formations.has(formation.formation_id):
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


func set_supply_input(region_id: String, input: Dictionary) -> bool:
	if region_id.is_empty() or not region_controls.has(region_id) or not _is_supply_input_valid(input):
		return false
	supply_inputs[region_id] = {
			"food": float(input.get("food", 0.0)),
			"ammunition": float(input.get("ammunition", 0.0)),
			"equipment": float(input.get("equipment", 0.0)),
			"transport_capacity": float(input.get("transport_capacity", 0.0)),
		}
	return true


func set_region_controller(
	region_id: String,
	controller_id: String,
	reason: String = "external military integration"
) -> bool:
	if not region_controls.has(region_id) or controller_id.is_empty():
		return false
	var previous: String = str(region_controls[region_id])
	if previous == controller_id:
		return true
	region_controls[region_id] = controller_id
	control_history.append({
		"region_id": region_id,
		"previous_controller_id": previous,
		"controller_id": controller_id,
		"reason": reason,
		"hour": last_simulated_hour,
	})
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
		"region_controls": region_controls.duplicate(true),
		"region_garrisons": region_garrisons.duplicate(true),
		"supply_inputs": supply_inputs.duplicate(true),
		"active_actions": action_snapshots,
		"completed_actions": completed_actions.duplicate(true),
		"battle_results": battle_results.duplicate(true),
		"control_history": control_history.duplicate(true),
	}


func restore(snapshot_value: Dictionary, map: VNextMilitaryMapAdapter = null) -> bool:
	var formation_value: Variant = snapshot_value.get("formations", [])
	var active_action_value: Variant = snapshot_value.get("active_actions", [])
	var completed_value: Variant = snapshot_value.get("completed_actions", [])
	var battle_value: Variant = snapshot_value.get("battle_results", [])
	var history_value: Variant = snapshot_value.get("control_history", [])
	var controls_value: Variant = snapshot_value.get("region_controls", {})
	var garrisons_value: Variant = snapshot_value.get("region_garrisons", {})
	var inputs_value: Variant = snapshot_value.get("supply_inputs", {})
	if snapshot_value.get("schema_id", "") != SCHEMA_ID or not formation_value is Array or not active_action_value is Array or not completed_value is Array or not battle_value is Array or not history_value is Array or not controls_value is Dictionary or not garrisons_value is Dictionary or not inputs_value is Dictionary:
		return false
	if not _array_contains_only_dictionaries(completed_value as Array) or not _array_contains_only_dictionaries(battle_value as Array) or not _array_contains_only_dictionaries(history_value as Array):
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
		if action_id.is_empty() or candidate_actions.has(action_id):
			return false
		candidate_actions[action_id] = action.duplicate(true)
	if int(snapshot_value.get("last_simulated_hour", -1)) < 0 or int(snapshot_value.get("next_action_sequence", 0)) < 1:
		return false
	var candidate_state := VNextMilitaryState.new()
	candidate_state.formations = candidate_formations
	candidate_state.active_actions = candidate_actions
	candidate_state.region_controls = (controls_value as Dictionary).duplicate(true)
	candidate_state.region_garrisons = (garrisons_value as Dictionary).duplicate(true)
	candidate_state.supply_inputs = (inputs_value as Dictionary).duplicate(true)
	candidate_state.completed_actions = _dictionary_array(completed_value as Array)
	candidate_state.battle_results = _dictionary_array(battle_value as Array)
	candidate_state.control_history = _dictionary_array(history_value as Array)
	candidate_state.last_simulated_hour = int(snapshot_value["last_simulated_hour"])
	candidate_state.next_action_sequence = int(snapshot_value["next_action_sequence"])
	if not candidate_state.is_valid(map):
		return false
	formations = candidate_state.formations
	active_actions = candidate_state.active_actions
	region_controls = candidate_state.region_controls
	region_garrisons = candidate_state.region_garrisons
	supply_inputs = candidate_state.supply_inputs
	completed_actions = candidate_state.completed_actions
	battle_results = candidate_state.battle_results
	control_history = candidate_state.control_history
	last_simulated_hour = candidate_state.last_simulated_hour
	next_action_sequence = candidate_state.next_action_sequence
	return true


func _array_contains_only_dictionaries(source: Array) -> bool:
	for raw_value: Variant in source:
		if not raw_value is Dictionary:
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


func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in source.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids
