class_name VNextMilitaryService
extends RefCounted
## Strategic military operations over the existing world-map graph, consuming Spatial physical capacity.
## The caller supplies the external time boundary; this service never touches
## VNextWorldRuntime or creates a second world clock.

const RESOURCE_IDS: PackedStringArray = ["food", "ammunition", "equipment", "transport_capacity"]
const EQUIPMENT_LOAD_PER_PERSON: float = 0.25
const CARGO_LOAD_WEIGHTS := {
	"food": 1.0,
	"ammunition": 1.25,
	"equipment": 2.0,
	"transport_capacity": 0.5,
}
const EPSILON: float = 0.0001

signal action_completed(action: Dictionary)
signal battle_resolved(result: Dictionary)
signal region_control_changed(change: Dictionary)

var capability_model := VNextMilitaryCapabilityModel.new()


func create_formation(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	country_id: String,
	city_id: String,
	personnel: int,
	equipment_sets: Dictionary = {},
	training: float = 0.65,
	morale: float = 0.7,
	organization: float = 0.7,
	daily_requirements: Dictionary = {}
) -> bool:
	if state == null or map == null or not state.is_valid(map):
		return false
	if VNextStableId.kind_of(formation_id) != "formation" or personnel <= 0:
		return false
	if not map.has_country(country_id) or not map.has_city(city_id):
		return false
	var region_id: String = map.get_region_id_for_city(city_id)
	if str(state.region_controls.get(region_id, "")) != country_id:
		return false
	var formation := VNextMilitaryFormation.new()
	if not formation.configure(
		formation_id,
		country_id,
		"army",
		personnel,
		equipment_sets if not equipment_sets.is_empty() else {"equipment_factor": 1.0},
		training,
		morale,
		organization,
		city_id,
		daily_requirements
	):
		return false
	return state.add_formation(formation)


func set_supply_input(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	region_id: String,
	input: Dictionary
) -> bool:
	if state == null or map == null or not map.has_region(region_id):
		return false
	return state.set_supply_input(region_id, input)


func setup_region_controller(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	region_id: String,
	controller_id: String,
	cause: String = "military test/setup fixture"
) -> bool:
	if state == null or map == null or not map.has_region(region_id) or not map.has_country(controller_id) or cause.is_empty():
		return false
	if not state.can_apply_setup_control_change():
		return false
	var previous_controller_id: String = str(state.region_controls.get(region_id, ""))
	if not state.apply_region_control_change(region_id, controller_id, cause, 0, "setup_fixture"):
		return false
	if previous_controller_id != controller_id:
		var change_index: int = state.control_history.size() - 1
		var change: Dictionary = state.control_history[change_index] as Dictionary
		change["control_origin_controller_id"] = map.get_initial_controller(region_id)
		change["source_action_kind"] = ""
		change["source_formation_id"] = ""
		change["source_target_region_id"] = ""
		change["source_controller_id"] = ""
		change["source_preparation_end_hour"] = -1
		state.control_history[change_index] = change
		region_control_changed.emit(change.duplicate(true))
	return true


func deploy(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	destination_city_id: String,
	start_hour: int
) -> Dictionary:
	return _issue_transport_action(state, map, formation_id, destination_city_id, start_hour, "deploy", false)


func move(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	destination_city_id: String,
	start_hour: int
) -> Dictionary:
	return _issue_transport_action(state, map, formation_id, destination_city_id, start_hour, "move", false)


func concentrate(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_ids: Array[String],
	destination_city_id: String,
	start_hour: int
) -> Dictionary:
	if state == null or map == null or formation_ids.is_empty() or start_hour != state.last_simulated_hour:
		return _failure("集中行动参数无效。")
	if not map.has_city(destination_city_id):
		return _failure("集中目标城市不存在。")
	var seen: Dictionary = {}
	var prepared: Array[Dictionary] = []
	var owner_id: String = ""
	for formation_id: String in formation_ids:
		if seen.has(formation_id):
			return _failure("集中行动不能包含重复编制 ID。")
		seen[formation_id] = true
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or not formation.can_receive_orders():
			return _failure("集中要求所有部队都处于可行动待命状态。")
		if owner_id.is_empty():
			owner_id = formation.country_id
		elif owner_id != formation.country_id:
			return _failure("集中不能混合不同控制方的部队。")
		var route: Dictionary = map.find_route(formation.current_city_id, destination_city_id, [], owner_id, state.region_controls, false)
		if not bool(route.get("reachable", false)):
			return _failure("集中路线不可通行。")
		if not _movement_allowed_for_condition(formation, route):
			return _failure("编制当前补给或组织状态不足以执行该长距离集中。")
		prepared.append({"formation_id": formation_id, "route": route})
	_sort_prepared_formations(prepared)

	var action_ids: Array[String] = []
	for item: Dictionary in prepared:
		var formation: VNextMilitaryFormation = state.get_formation(str(item["formation_id"]))
		var action_id: String = _next_action_id(state)
		var action: Dictionary = _new_transport_action(action_id, "concentrate", formation, destination_city_id, start_hour, item["route"] as Dictionary, map, false)
		state.active_actions[action_id] = action
		formation.action_state = VNextMilitaryFormation.ACTION_CONCENTRATING
		action_ids.append(action_id)
	return {"success": true, "action_ids": action_ids, "destination_city_id": destination_city_id}


func defend(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	start_hour: int,
	duration_hours: int
) -> Dictionary:
	if state == null or map == null or duration_hours <= 0 or start_hour != state.last_simulated_hour:
		return _failure("防御行动参数无效。")
	var formation: VNextMilitaryFormation = state.get_formation(formation_id)
	if formation == null or not formation.can_receive_orders():
		return _failure("该部队当前不能建立防御姿态。")
	var region_id: String = map.get_region_id_for_city(formation.current_city_id)
	if str(state.region_controls.get(region_id, "")) != formation.country_id:
		return _failure("部队不在己方控制区，不能建立防御姿态。")
	var action_id: String = _next_action_id(state)
	state.active_actions[action_id] = {
		"action_id": action_id,
		"kind": "defend",
		"formation_id": formation_id,
		"origin_city_id": formation.current_city_id,
		"destination_city_id": formation.current_city_id,
		"target_region_id": region_id,
		"start_hour": start_hour,
		"eta_hour": start_hour + duration_hours,
		"progress": 0.0,
		"route": {},
		"capacity_window_hour": -1,
		"capacity_link_id": "",
		"capacity_used_this_window": 0.0,
	}
	formation.action_state = VNextMilitaryFormation.ACTION_DEFENDING
	formation.defense_posture = _battle_rule(map, "defense_posture_multiplier", 1.2)
	return {"success": true, "action_id": action_id, "eta_hour": start_hour + duration_hours, "defense_posture": formation.defense_posture}


func attack(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	target_city_id: String,
	start_hour: int
) -> Dictionary:
	if state == null or map == null or start_hour != state.last_simulated_hour:
		return _failure("进攻行动参数无效。")
	var formation: VNextMilitaryFormation = state.get_formation(formation_id)
	if formation == null or not formation.can_receive_orders():
		return _failure("该部队当前不能发起进攻。")
	if not map.has_city(target_city_id):
		return _failure("进攻目标城市不存在。")
	var target_region_id: String = map.get_region_id_for_city(target_city_id)
	var target_controller_id: String = str(state.region_controls.get(target_region_id, ""))
	if target_controller_id.is_empty() or target_controller_id == formation.country_id:
		return _failure("进攻目标必须是敌方控制区。")
	var route: Dictionary = map.find_route(formation.current_city_id, target_city_id, [], formation.country_id, state.region_controls, true)
	if not bool(route.get("reachable", false)):
		return _failure("进攻路线不可通行。")
	if not _movement_allowed_for_condition(formation, route):
		return _failure("编制当前补给或组织状态不足以执行该长距离进攻。")
	var action_id: String = _next_action_id(state)
	var action: Dictionary = _new_transport_action(action_id, "attack", formation, target_city_id, start_hour, route, map, true)
	action["target_region_id"] = target_region_id
	action["attack_preparation_hours"] = maxi(1, int(_battle_rule(map, "attack_preparation_hours", 24.0)))
	action["eta_hour"] = int(action["eta_hour"]) + int(action["attack_preparation_hours"])
	state.active_actions[action_id] = action
	formation.action_state = VNextMilitaryFormation.ACTION_ATTACKING
	return {
		"success": true,
		"action_id": action_id,
		"target_region_id": target_region_id,
		"target_city_id": target_city_id,
		"eta_hour": int(action["eta_hour"]),
		"war_status": "active",
		"route": route.duplicate(true),
	}


func advance_to_hour(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	target_hour: int
) -> Dictionary:
	if state == null or map == null or not state.is_valid(map):
		return _failure("军事状态无效。")
	var spatial: VNextSpatialWorld = map.get_spatial_world()
	if spatial == null or not spatial.is_valid() or spatial.current_hour() != state.last_simulated_hour:
		return _failure("军事推进需要与当前边界同步的 Spatial authority。")
	if target_hour < state.last_simulated_hour:
		return _failure("军事时间不能倒退。")
	var start_hour: int = state.last_simulated_hour
	var supply_report: Dictionary = {}
	var completed: Array[Dictionary] = []
	var battles: Array[Dictionary] = []
	while state.last_simulated_hour < target_hour:
		var hour: int = state.last_simulated_hour
		var tick: Dictionary = _advance_one_hour(state, map, hour)
		if not bool(tick.get("success", false)):
			return _failure(str(tick.get("reason", "Spatial capacity window advance failed.")))
		_merge_supply_report(supply_report, tick.get("supply", {}) as Dictionary)
		for raw_completion: Variant in tick.get("completed_actions", []) as Array:
			if raw_completion is Dictionary:
				completed.append((raw_completion as Dictionary).duplicate(true))
		for raw_battle: Variant in tick.get("battles", []) as Array:
			if raw_battle is Dictionary:
				battles.append((raw_battle as Dictionary).duplicate(true))
	return {
		"success": true,
		"elapsed_hours": target_hour - start_hour,
		"supply": supply_report,
		"completed_actions": completed,
		"battles": battles,
		"last_simulated_hour": state.last_simulated_hour,
	}


func get_action(state: VNextMilitaryState, action_id: String) -> Dictionary:
	if state == null:
		return {}
	return (state.active_actions.get(action_id, {}) as Dictionary).duplicate(true)


func get_supply_shipments(state: VNextMilitaryState) -> Array[Dictionary]:
	var shipments: Array[Dictionary] = []
	if state == null:
		return shipments
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("kind", "")) == "supply":
			shipments.append(action.duplicate(true))
	return shipments


func get_link_capacity_view(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, link_id: String) -> Dictionary:
	if state == null or map == null or map.get_link(link_id).is_empty():
		return {}
	var summary: Dictionary = map.get_spatial_capacity_summary(link_id)
	if summary.is_empty():
		return {}
	return {
		"link_id": link_id,
		"window_hour": state.capacity_window_hour,
		"spatial_window_hour": int(summary.get("window_hour", -1)),
		"capacity_per_hour": float(summary.get("effective_capacity", 0.0)),
		"used_capacity": float(summary.get("used_capacity", 0.0)),
		"available_capacity": float(summary.get("remaining_capacity", 0.0)),
		"military_attributed_capacity": maxf(0.0, float(state.link_capacity_used.get(link_id, 0.0))),
		"queue": (state.link_queues.get(link_id, []) as Array).duplicate(true),
	}


func get_formation_view(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, formation_id: String) -> Dictionary:
	if state == null or map == null:
		return {}
	var formation: VNextMilitaryFormation = state.get_formation(formation_id)
	if formation == null:
		return {}
	var result: Dictionary = formation.to_dict()
	result["region_id"] = map.get_region_id_for_city(formation.current_city_id)
	result["city_name"] = str(map.get_city(formation.current_city_id).get("name", formation.current_city_id))
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("formation_id", "")) == formation_id:
			result["active_action_id"] = action_id
			result["transport_state"] = str(action.get("transport_state", ""))
			result["current_route_edge"] = int(action.get("current_edge_index", -1))
			result["action_progress"] = float(action.get("progress", 0.0))
			break
	return result


func get_region_view(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, region_id: String) -> Dictionary:
	if state == null or map == null:
		return {}
	var result: Dictionary = map.get_region_report(region_id, state.region_controls)
	if result.is_empty():
		return {}
	var stationed: Array[Dictionary] = []
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation != null and map.get_region_id_for_city(formation.current_city_id) == region_id:
			stationed.append(get_formation_view(state, map, formation_id))
	result["formations"] = stationed
	result["garrison_personnel"] = int(state.region_garrisons.get(region_id, 0))
	return result


func preview_battle(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, attacker_formation_id: String, target_city_id: String) -> Dictionary:
	if state == null or map == null or not map.has_city(target_city_id):
		return {}
	var attacker: VNextMilitaryFormation = state.get_formation(attacker_formation_id)
	if attacker == null or attacker.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
		return {}
	var target_region_id: String = map.get_region_id_for_city(target_city_id)
	var terrain: Dictionary = map.get_region_terrain(target_region_id)
	var defender_summary: Dictionary = _defender_summary(state, map, target_region_id, target_city_id)
	var attacker_assessment := _formation_assessment(attacker, map, target_region_id, "attack")
	var attacker_power: float = float(attacker_assessment.get("operational_effectiveness", 0.0))
	var defender_power: float = float(defender_summary.get("power", 0.0))
	return {
		"attacker_power": attacker_power,
		"defender_power": defender_power,
		"power_ratio": attacker_power / maxf(1.0, defender_power),
		"terrain_defense_factor": float(terrain.get("defense_factor", 1.0)),
		"attacker_supply_level": attacker.supply_level,
		"defender_supply_level": float(defender_summary.get("average_supply_level", 0.0)),
		"defender_posture_multiplier": float(defender_summary.get("posture_multiplier", 1.0)),
		"attacker_assessment": attacker_assessment,
		"factors": ["兵力", "装备", "补给", "地形", "防御姿态", "组织", "士气"],
	}


func _issue_transport_action(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	destination_city_id: String,
	start_hour: int,
	kind: String,
	allow_enemy_destination: bool
) -> Dictionary:
	if state == null or map == null or start_hour != state.last_simulated_hour:
		return _failure("移动行动参数无效。")
	var formation: VNextMilitaryFormation = state.get_formation(formation_id)
	if formation == null or not formation.can_receive_orders():
		return _failure("该部队当前不能接收新的移动命令。")
	if not map.has_city(destination_city_id):
		return _failure("移动目标城市不存在。")
	var route: Dictionary = map.find_route(formation.current_city_id, destination_city_id, [], formation.country_id, state.region_controls, allow_enemy_destination)
	if not bool(route.get("reachable", false)):
		return _failure(str(route.get("reason", "移动路线不可通行。")))
	if not _movement_allowed_for_condition(formation, route):
		return _failure("编制当前补给或组织状态不足以执行该长距离移动。")
	var action_id: String = _next_action_id(state)
	var action: Dictionary = _new_transport_action(action_id, kind, formation, destination_city_id, start_hour, route, map, allow_enemy_destination)
	state.active_actions[action_id] = action
	formation.action_state = VNextMilitaryFormation.ACTION_MOVING
	return {"success": true, "action_id": action_id, "eta_hour": int(action["eta_hour"]), "route": route.duplicate(true)}


func _new_transport_action(
	action_id: String,
	kind: String,
	formation: VNextMilitaryFormation,
	destination_city_id: String,
	start_hour: int,
	route: Dictionary,
	map: VNextMilitaryMapAdapter,
	allow_enemy_destination: bool
) -> Dictionary:
	var load: float = _formation_transport_load(formation)
	var estimated_hours: int = _estimate_transport_hours(map, route, load)
	return {
		"action_id": action_id,
		"kind": kind,
		"formation_id": formation.formation_id,
		"origin_city_id": formation.current_city_id,
		"destination_city_id": destination_city_id,
		"target_region_id": "",
		"start_hour": start_hour,
		"eta_hour": start_hour + maxi(1, estimated_hours),
		"progress": 0.0,
		"route": route.duplicate(true),
		"current_edge_index": 0,
		"edge_request_hour": start_hour,
		"edge_started_hour": -1,
		"edge_elapsed_hours": 0,
		"edge_load_total": load,
		"edge_load_remaining": load,
		"reserved_link_id": "",
		"spatial_request_id": "",
		"transport_state": "waiting_capacity",
		"allow_enemy_destination": allow_enemy_destination,
		"capacity_window_hour": -1,
		"capacity_link_id": "",
		"capacity_used_this_window": 0.0,
	}


func _new_supply_action(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation: VNextMilitaryFormation,
	source_region_id: String,
	resource_id: String,
	amount: float,
	route: Dictionary,
	start_hour: int
) -> Dictionary:
	var action_id: String = _next_action_id(state)
	var weight: float = VNextMilitaryState.supply_cargo_weight(resource_id)
	var load: float = amount * weight
	return {
		"action_id": action_id,
		"kind": "supply",
		"destination_formation_id": formation.formation_id,
		"owner_country_id": formation.country_id,
		"source_region_id": source_region_id,
		"resource_id": resource_id,
		"cargo_amount_total": amount,
		"cargo_amount_remaining": amount,
		"origin_city_id": str((route.get("city_ids", []) as Array)[0]),
		"destination_city_id": formation.current_city_id,
		"current_city_id": str((route.get("city_ids", []) as Array)[0]),
		"start_hour": start_hour,
		"eta_hour": start_hour + maxi(1, _estimate_transport_hours(map, route, load)),
		"progress": 0.0,
		"route": route.duplicate(true),
		"current_edge_index": 0,
		"edge_request_hour": start_hour,
		"edge_started_hour": -1,
		"edge_elapsed_hours": 0,
		"edge_load_total": load,
		"edge_load_remaining": load,
		"reserved_link_id": "",
		"spatial_request_id": "",
		"transport_state": "waiting_capacity",
		"allow_enemy_destination": false,
		"capacity_window_hour": -1,
		"capacity_link_id": "",
		"capacity_used_this_window": 0.0,
	}


func _advance_one_hour(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, hour: int) -> Dictionary:
	var spatial: VNextSpatialWorld = map.get_spatial_world()
	if spatial == null or not spatial.is_valid() or spatial.current_hour() != hour:
		return {"success": false, "reason": "Spatial capacity window is not synchronized."}
	state.begin_capacity_window(hour)

	var supply_context: Dictionary = _build_supply_context(state, map)
	_create_supply_shipments(state, map, hour, supply_context)
	var requests: Array[Dictionary] = []
	_collect_movement_requests(state, map, hour, requests)
	_collect_supply_transport_requests(state, map, hour, requests)
	_sort_capacity_requests(requests)

	# PASS 2: submit every eligible Military demand as one transactional Spatial
	# batch. Reverse construction is deliberate: final results must still follow
	# Spatial canonical request ordering rather than caller insertion order.
	var submission_order: Array[Dictionary] = requests.duplicate(true)
	submission_order.reverse()
	var spatial_batch: Array[Dictionary] = []
	for request: Dictionary in submission_order:
		var spatial_request_id: String = _spatial_capacity_request_id(request, hour)
		request["spatial_request_id"] = spatial_request_id
		spatial_batch.append({
			"request_id": spatial_request_id,
			"link_id": str(request.get("link_id", "")),
			"window_hour": hour,
			"demand": float(request.get("requested_capacity", 0.0)),
		})
	if not spatial_batch.is_empty():
		var batch_result: Dictionary = spatial.request_capacity_batch(spatial_batch)
		if not bool(batch_result.get("accepted", false)):
			return {"success": false, "reason": "Spatial rejected Military capacity batch: %s" % str(batch_result.get("reason", "unknown"))}

	# PASS 3: query every final reservation result only after the full batch exists.
	# The batch query is read-only and performs one canonical calculation for the
	# complete result set; it is equivalent to final reservation_result() calls.
	var final_query: Dictionary = spatial.reservation_results_batch(spatial_batch) if not spatial_batch.is_empty() else {"accepted": true, "results": {}}
	if not bool(final_query.get("accepted", false)):
		return {"success": false, "reason": "Spatial final reservation batch lookup failed."}
	var final_results: Dictionary = final_query.get("results", {}) as Dictionary
	var final_allocations: Dictionary = {}
	for request: Dictionary in requests:
		var action_id: String = str(request.get("request_id", ""))
		var spatial_request_id: String = _spatial_capacity_request_id(request, hour)
		request["spatial_request_id"] = spatial_request_id
		var result: Dictionary = final_results.get(spatial_request_id, {}) as Dictionary
		if not bool(result.get("accepted", false)):
			return {"success": false, "reason": "Spatial final reservation lookup failed."}
		final_allocations[action_id] = maxf(0.0, float(result.get("allocated_capacity", 0.0)))

	# PASS 4: Military records attribution and progresses actions from final results.
	for request: Dictionary in requests:
		if str(request.get("request_kind", "")) == "movement":
			_apply_movement_capacity_request(state, request, final_allocations, hour)
		else:
			_apply_supply_capacity_request(state, request, final_allocations, hour)

	var supply_report: Dictionary = _finalize_supply_hour(state, map, supply_context)
	var boundary_hour: int = hour + 1
	state.last_simulated_hour = boundary_hour
	var completed: Array[Dictionary] = []
	var battles: Array[Dictionary] = []
	_advance_actions_at_boundary(state, map, boundary_hour, completed, battles)

	# Closing the physical window is authoritative in Spatial. Military keeps only
	# historical attribution; no closed Spatial reservation object is required.
	if not spatial.advance_to_hour(boundary_hour):
		return {"success": false, "reason": "Spatial capacity window rollover failed."}
	_clear_spatial_request_references(state)
	return {"success": true, "supply": supply_report, "completed_actions": completed, "battles": battles}


func _build_supply_context(state: VNextMilitaryState, map: VNextMilitaryMapAdapter) -> Dictionary:
	var source_remaining: Dictionary = {}
	for source_region_id: String in _sorted_dictionary_keys(state.supply_inputs):
		var source_input: Dictionary = state.supply_inputs[source_region_id] as Dictionary
		var remaining: Dictionary = {}
		for resource_id: String in RESOURCE_IDS:
			remaining[resource_id] = maxf(0.0, float(source_input.get(resource_id, 0.0)) / 24.0)
		source_remaining[source_region_id] = remaining

	var demand_remaining: Dictionary = {}
	var demand_total: Dictionary = {}
	var pipeline_demand: Dictionary = {}
	var delivered: Dictionary = {}
	var sources_used: Dictionary = {}
	var links_used: Dictionary = {}
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE or formation.personnel <= 0:
			continue
		var formation_demand: Dictionary = {}
		var formation_delivered: Dictionary = {}
		for resource_id: String in RESOURCE_IDS:
			formation_demand[resource_id] = maxf(0.0, float(formation.daily_requirements.get(resource_id, 0.0)) / 24.0)
			formation_delivered[resource_id] = 0.0
		demand_remaining[formation_id] = formation_demand.duplicate(true)
		demand_total[formation_id] = formation_demand
		pipeline_demand[formation_id] = formation_demand.duplicate(true)
		delivered[formation_id] = formation_delivered
		sources_used[formation_id] = []
		links_used[formation_id] = []

	var context: Dictionary = {
		"source_remaining": source_remaining,
		"demand_remaining": demand_remaining,
		"pipeline_demand": pipeline_demand,
		"demand_total": demand_total,
		"delivered": delivered,
		"sources_used": sources_used,
		"links_used": links_used,
	}
	_consume_arrived_supply(state, context)

	# Same-region supply has no transport-link reservation, but still competes for source quantity.
	# Local coverage also reduces the demand rate that needs a remote rolling pipeline.
	for formation_id: String in state.get_sorted_formation_ids():
		if not demand_remaining.has(formation_id):
			continue
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		var local_region: String = map.get_region_id_for_city(formation.current_city_id)
		if not source_remaining.has(local_region):
			continue
		for resource_id: String in RESOURCE_IDS:
			var need: float = float((demand_remaining[formation_id] as Dictionary).get(resource_id, 0.0))
			var available: float = float((source_remaining[local_region] as Dictionary).get(resource_id, 0.0))
			var amount: float = minf(need, available)
			if amount <= EPSILON:
				continue
			(demand_remaining[formation_id] as Dictionary)[resource_id] = need - amount
			(source_remaining[local_region] as Dictionary)[resource_id] = available - amount
			(delivered[formation_id] as Dictionary)[resource_id] = float((delivered[formation_id] as Dictionary).get(resource_id, 0.0)) + amount
			(pipeline_demand[formation_id] as Dictionary)[resource_id] = maxf(0.0, float((pipeline_demand[formation_id] as Dictionary).get(resource_id, 0.0)) - amount)
			var source_list: Array = sources_used[formation_id] as Array
			if not source_list.has(local_region):
				source_list.append(local_region)
	return context


func _consume_arrived_supply(state: VNextMilitaryState, context: Dictionary) -> void:
	var demand_remaining: Dictionary = context["demand_remaining"] as Dictionary
	var delivered: Dictionary = context["delivered"] as Dictionary
	var sources_used: Dictionary = context["sources_used"] as Dictionary
	var links_used: Dictionary = context["links_used"] as Dictionary
	var action_ids: Array[String] = _sorted_dictionary_keys(state.active_actions)
	for action_id: String in action_ids:
		if not state.active_actions.has(action_id):
			continue
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("kind", "")) != "supply" or str(action.get("transport_state", "")) != "arrived":
			continue
		var formation_id: String = str(action.get("destination_formation_id", ""))
		if not demand_remaining.has(formation_id):
			continue
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.current_city_id != str(action.get("destination_city_id", "")):
			continue
		var resource_id: String = str(action.get("resource_id", ""))
		var need: float = maxf(0.0, float((demand_remaining[formation_id] as Dictionary).get(resource_id, 0.0)))
		var cargo_remaining: float = maxf(0.0, float(action.get("cargo_amount_remaining", 0.0)))
		var amount: float = minf(need, cargo_remaining)
		if amount <= EPSILON:
			continue
		(demand_remaining[formation_id] as Dictionary)[resource_id] = need - amount
		(delivered[formation_id] as Dictionary)[resource_id] = float((delivered[formation_id] as Dictionary).get(resource_id, 0.0)) + amount
		action["cargo_amount_remaining"] = cargo_remaining - amount
		var source_region_id: String = str(action.get("source_region_id", ""))
		var source_list: Array = sources_used[formation_id] as Array
		if not source_list.has(source_region_id):
			source_list.append(source_region_id)
		for raw_link_id: Variant in (action.get("route", {}) as Dictionary).get("link_ids", []) as Array:
			var link_id: String = str(raw_link_id)
			var link_list: Array = links_used[formation_id] as Array
			if not link_list.has(link_id):
				link_list.append(link_id)
		if float(action.get("cargo_amount_remaining", 0.0)) <= EPSILON:
			var cargo_total: float = maxf(0.0, float(action.get("cargo_amount_total", 0.0)))
			state.append_completed_action({
				"action_id": action_id,
				"kind": "supply",
				"destination_formation_id": formation_id,
				"source_region_id": source_region_id,
				"resource_id": resource_id,
				"completed_at_hour": state.last_simulated_hour,
				"success": true,
				"outcome": "delivered",
				"cargo_amount_total": cargo_total,
				"cargo_delivered": cargo_total,
				"cargo_lost": 0.0,
				"route": (action.get("route", {}) as Dictionary).duplicate(true),
				"capacity_window_hour": int(action.get("capacity_window_hour", -1)),
				"capacity_link_id": str(action.get("capacity_link_id", "")),
				"capacity_used_this_window": float(action.get("capacity_used_this_window", 0.0)),
			})
			state.remove_capacity_request(action_id)
			state.active_actions.erase(action_id)
		else:
			state.active_actions[action_id] = action


func _create_supply_shipments(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, hour: int, context: Dictionary) -> void:
	var pipeline_demand: Dictionary = context["pipeline_demand"] as Dictionary
	var source_remaining: Dictionary = context["source_remaining"] as Dictionary
	for formation_id: String in state.get_sorted_formation_ids():
		if not pipeline_demand.has(formation_id):
			continue
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
			continue
		for source_region_id: String in _sorted_dictionary_keys(source_remaining):
			if source_region_id == map.get_region_id_for_city(formation.current_city_id):
				continue
			var source_city_ids: Array[String] = map.get_city_ids_for_region(source_region_id)
			if source_city_ids.is_empty():
				continue
			var route: Dictionary = map.find_route(source_city_ids[0], formation.current_city_id, [], formation.country_id, state.region_controls, false)
			if not bool(route.get("reachable", false)):
				continue
			var pipeline_hours: int = maxi(1, int(route.get("duration_hours", 1)) + 1)
			for resource_id: String in RESOURCE_IDS:
				var hourly_remote_demand: float = maxf(0.0, float((pipeline_demand[formation_id] as Dictionary).get(resource_id, 0.0)))
				var available: float = maxf(0.0, float((source_remaining[source_region_id] as Dictionary).get(resource_id, 0.0)))
				if hourly_remote_demand <= EPSILON or available <= EPSILON:
					continue
				var desired_outstanding: float = hourly_remote_demand * float(pipeline_hours)
				var committed_total: float = _outstanding_supply_cargo(state, formation_id, resource_id)
				var committed_from_source: float = _outstanding_supply_cargo(state, formation_id, resource_id, source_region_id)
				var total_needed: float = maxf(0.0, desired_outstanding - committed_total)
				var source_needed: float = maxf(0.0, desired_outstanding - committed_from_source)
				var needed: float = minf(total_needed, source_needed)
				if needed <= EPSILON:
					continue
				var amount: float = minf(hourly_remote_demand, minf(needed, available))
				var action: Dictionary = _new_supply_action(state, map, formation, source_region_id, resource_id, amount, route, hour)
				if action.is_empty():
					continue
				state.active_actions[str(action["action_id"])] = action
				(source_remaining[source_region_id] as Dictionary)[resource_id] = available - amount


func _outstanding_supply_cargo(state: VNextMilitaryState, formation_id: String, resource_id: String, source_region_id: String = "") -> float:
	var total: float = 0.0
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("kind", "")) != "supply":
			continue
		if str(action.get("destination_formation_id", "")) != formation_id or str(action.get("resource_id", "")) != resource_id:
			continue
		if not source_region_id.is_empty() and str(action.get("source_region_id", "")) != source_region_id:
			continue
		total += maxf(0.0, float(action.get("cargo_amount_remaining", 0.0)))
	return total


func _collect_movement_requests(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	hour: int,
	requests: Array[Dictionary]
) -> void:
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		var kind: String = str(action.get("kind", ""))
		if kind in ["defend", "supply"] or str(action.get("transport_state", "")) == "preparing":
			continue
		var formation: VNextMilitaryFormation = state.get_formation(str(action.get("formation_id", "")))
		if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
			continue
		var route: Dictionary = action.get("route", {}) as Dictionary
		var link_ids: Array = route.get("link_ids", []) as Array
		var edge_index: int = int(action.get("current_edge_index", -1))
		if edge_index < 0 or edge_index >= link_ids.size():
			continue
		var link_id: String = str(link_ids[edge_index])
		var can_enter: bool = map.can_enter_link(
			link_id, formation.current_city_id, str(action.get("destination_city_id", "")),
			formation.country_id, state.region_controls, bool(action.get("allow_enemy_destination", false))
		)
		if not can_enter:
			_cancel_active_spatial_request(map, action)
			action["reserved_link_id"] = ""
			action["spatial_request_id"] = ""
			action["transport_state"] = "interrupted" if map.get_link_transport_capacity_per_hour(link_id) <= 0.0 else "blocked"
			state.active_actions[action_id] = action
			continue
		var demand: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
		if demand <= EPSILON:
			action["reserved_link_id"] = ""
			action["spatial_request_id"] = ""
			action["transport_state"] = "moving"
			state.active_actions[action_id] = action
			continue
		action["transport_state"] = "waiting_capacity"
		action["reserved_link_id"] = link_id
		state.active_actions[action_id] = action
		requests.append({
			"request_kind": "movement",
			"request_hour": int(action.get("edge_request_hour", action.get("start_hour", hour))),
			"request_id": action_id,
			"formation_id": formation.formation_id,
			"resource_id": "",
			"link_id": link_id,
			"requested_capacity": demand,
		})


func _collect_supply_transport_requests(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	hour: int,
	requests: Array[Dictionary]
) -> void:
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("kind", "")) != "supply" or str(action.get("transport_state", "")) == "arrived":
			continue
		var formation: VNextMilitaryFormation = state.get_formation(str(action.get("destination_formation_id", "")))
		if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
			continue
		var route: Dictionary = action.get("route", {}) as Dictionary
		var link_ids: Array = route.get("link_ids", []) as Array
		var edge_index: int = int(action.get("current_edge_index", -1))
		if edge_index < 0 or edge_index >= link_ids.size():
			continue
		var link_id: String = str(link_ids[edge_index])
		var can_enter: bool = map.can_enter_link(
			link_id, str(action.get("current_city_id", "")), str(action.get("destination_city_id", "")),
			str(action.get("owner_country_id", "")), state.region_controls, false
		)
		if not can_enter:
			_cancel_active_spatial_request(map, action)
			action["reserved_link_id"] = ""
			action["spatial_request_id"] = ""
			action["transport_state"] = "interrupted" if map.get_link_transport_capacity_per_hour(link_id) <= 0.0 else "blocked"
			state.active_actions[action_id] = action
			continue
		var demand: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
		if demand <= EPSILON:
			action["reserved_link_id"] = ""
			action["spatial_request_id"] = ""
			action["transport_state"] = "moving"
			state.active_actions[action_id] = action
			continue
		action["transport_state"] = "waiting_capacity"
		action["reserved_link_id"] = link_id
		state.active_actions[action_id] = action
		requests.append({
			"request_kind": "supply",
			"request_hour": int(action.get("edge_request_hour", action.get("start_hour", hour))),
			"request_id": action_id,
			"formation_id": str(action.get("destination_formation_id", "")),
			"resource_id": str(action.get("resource_id", "")),
			"link_id": link_id,
			"requested_capacity": demand,
		})


func _apply_movement_capacity_request(
	state: VNextMilitaryState,
	request: Dictionary,
	final_allocations: Dictionary,
	hour: int
) -> void:
	var action_id: String = str(request.get("request_id", ""))
	if not state.active_actions.has(action_id):
		return
	var action: Dictionary = state.active_actions[action_id] as Dictionary
	var link_id: String = str(request.get("link_id", ""))
	state.queue_capacity_request(link_id, action_id)
	var remaining: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
	var allocation: float = minf(remaining, maxf(0.0, float(final_allocations.get(action_id, 0.0))))
	action["spatial_request_id"] = str(request.get("spatial_request_id", ""))
	if allocation > EPSILON:
		state.record_capacity_use(link_id, allocation)
		action = state.active_actions[action_id] as Dictionary
		action["spatial_request_id"] = str(request.get("spatial_request_id", ""))
		action["capacity_window_hour"] = state.capacity_window_hour
		action["capacity_link_id"] = link_id
		action["capacity_used_this_window"] = allocation
		action["edge_load_remaining"] = maxf(0.0, remaining - allocation)
		action["transport_state"] = "moving"
		if int(action.get("edge_started_hour", -1)) < 0:
			action["edge_started_hour"] = hour
	else:
		action["transport_state"] = "waiting_capacity"
	if float(action.get("edge_load_remaining", 0.0)) <= EPSILON:
		action["reserved_link_id"] = ""
	state.active_actions[action_id] = action


func _apply_supply_capacity_request(
	state: VNextMilitaryState,
	request: Dictionary,
	final_allocations: Dictionary,
	hour: int
) -> void:
	var action_id: String = str(request.get("request_id", ""))
	if not state.active_actions.has(action_id):
		return
	var action: Dictionary = state.active_actions[action_id] as Dictionary
	if str(action.get("kind", "")) != "supply":
		return
	var link_id: String = str(request.get("link_id", ""))
	state.queue_capacity_request(link_id, action_id)
	var remaining: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
	var allocation: float = minf(remaining, maxf(0.0, float(final_allocations.get(action_id, 0.0))))
	action["spatial_request_id"] = str(request.get("spatial_request_id", ""))
	if allocation > EPSILON:
		state.record_capacity_use(link_id, allocation)
		action = state.active_actions[action_id] as Dictionary
		action["spatial_request_id"] = str(request.get("spatial_request_id", ""))
		action["capacity_window_hour"] = state.capacity_window_hour
		action["capacity_link_id"] = link_id
		action["capacity_used_this_window"] = allocation
		action["edge_load_remaining"] = maxf(0.0, remaining - allocation)
		action["transport_state"] = "moving"
		if int(action.get("edge_started_hour", -1)) < 0:
			action["edge_started_hour"] = hour
	else:
		action["transport_state"] = "waiting_capacity"
	if float(action.get("edge_load_remaining", 0.0)) <= EPSILON:
		action["reserved_link_id"] = ""
	state.active_actions[action_id] = action


func _finalize_supply_hour(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, context: Dictionary) -> Dictionary:
	var report: Dictionary = {}
	var demand_total: Dictionary = context["demand_total"] as Dictionary
	var delivered_all: Dictionary = context["delivered"] as Dictionary
	for formation_id: String in state.get_sorted_formation_ids():
		if not demand_total.has(formation_id):
			continue
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
			continue
		var demand: Dictionary = demand_total[formation_id] as Dictionary
		var delivered: Dictionary = delivered_all[formation_id] as Dictionary
		var fill: Dictionary = {}
		var minimum_fill: float = 1.0
		var has_demand: bool = false
		for resource_id: String in RESOURCE_IDS:
			var required: float = float(demand.get(resource_id, 0.0))
			var ratio: float = 1.0 if required <= EPSILON else clampf(float(delivered.get(resource_id, 0.0)) / required, 0.0, 1.0)
			fill[resource_id] = ratio
			if required > EPSILON:
				has_demand = true
				minimum_fill = minf(minimum_fill, ratio)
		if not has_demand:
			minimum_fill = 1.0
		var status: String = _supply_status(map, minimum_fill)
		formation.update_supply(fill, minimum_fill, status)
		_apply_supply_effects(formation, map, minimum_fill, 1.0 / 24.0)
		report[formation_id] = {
			"formation_id": formation_id,
			"demand": demand.duplicate(true),
			"delivered": delivered.duplicate(true),
			"fill": fill,
			"supply_level": minimum_fill,
			"status": status,
			"source_region_ids": ((context["sources_used"] as Dictionary)[formation_id] as Array).duplicate(),
			"route_link_ids": ((context["links_used"] as Dictionary)[formation_id] as Array).duplicate(),
		}
	return report


func _advance_actions_at_boundary(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	boundary_hour: int,
	completed: Array[Dictionary],
	battles: Array[Dictionary]
) -> void:
	_cancel_destroyed_formation_spatial_requests(state, map)
	_cleanup_all_destroyed_formation_references(state, boundary_hour, completed)
	var action_ids: Array[String] = _sorted_dictionary_keys(state.active_actions)
	for action_id: String in action_ids:
		if not state.active_actions.has(action_id):
			continue
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		var kind: String = str(action.get("kind", ""))
		if kind == "supply":
			_advance_supply_action_at_boundary(state, map, action_id, boundary_hour)
			continue
		var formation: VNextMilitaryFormation = state.get_formation(str(action.get("formation_id", "")))
		if formation == null:
			state.remove_capacity_request(action_id)
			state.active_actions.erase(action_id)
			continue
		if formation.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
			_complete_interrupted_action(state, action, formation, boundary_hour, "formation_destroyed", completed)
			continue
		if kind == "defend":
			var start_hour: int = int(action.get("start_hour", boundary_hour - 1))
			var eta_hour: int = int(action.get("eta_hour", boundary_hour))
			action["progress"] = clampf(float(boundary_hour - start_hour) / float(maxi(1, eta_hour - start_hour)), 0.0, 1.0)
			if boundary_hour >= eta_hour:
				formation.action_state = VNextMilitaryFormation.ACTION_IDLE
				formation.defense_posture = 1.0
				var completion: Dictionary = {
					"action_id": action_id,
					"kind": "defend",
					"formation_id": formation.formation_id,
					"completed_at_hour": boundary_hour,
					"success": true,
				}
				_record_completion(state, completion, completed)
				state.remove_capacity_request(action_id)
				state.active_actions.erase(action_id)
			else:
				state.active_actions[action_id] = action
			continue

		if str(action.get("transport_state", "")) == "preparing":
			var prep_end: int = int(action.get("preparation_end_hour", -1))
			if boundary_hour >= prep_end:
				var battle: Dictionary = _resolve_attack(state, map, action, formation, completed)
				battles.append(battle.duplicate(true))
				state.append_battle_result(battle)
				battle_resolved.emit(battle.duplicate(true))
				formation.action_state = VNextMilitaryFormation.ACTION_IDLE
				formation.defense_posture = 1.0
				var completion: Dictionary = battle.duplicate(true)
				completion["kind"] = "attack"
				completion["formation_id"] = formation.formation_id
				completion["completed_at_hour"] = boundary_hour
				completion["route"] = (action.get("route", {}) as Dictionary).duplicate(true)
				_record_completion(state, completion, completed)
				state.remove_capacity_request(action_id)
				state.active_actions.erase(action_id)
			else:
				var prep_start: int = int(action.get("preparation_start_hour", prep_end - int(action.get("attack_preparation_hours", 1))))
				action["progress"] = clampf(0.95 + 0.05 * float(boundary_hour - prep_start) / float(maxi(1, int(action.get("attack_preparation_hours", 1)))), 0.95, 0.999)
				state.active_actions[action_id] = action
			continue

		if str(action.get("transport_state", "")) == "moving" and int(action.get("edge_started_hour", -1)) >= 0:
			action["edge_elapsed_hours"] = int(action.get("edge_elapsed_hours", 0)) + 1
		var route: Dictionary = action.get("route", {}) as Dictionary
		var link_ids: Array = route.get("link_ids", []) as Array
		var city_ids: Array = route.get("city_ids", []) as Array
		var edge_index: int = int(action.get("current_edge_index", 0))
		if edge_index < 0 or edge_index >= link_ids.size():
			action["transport_state"] = "interrupted"
			state.active_actions[action_id] = action
			continue
		var link: Dictionary = map.get_link(str(link_ids[edge_index]))
		var movement_hours: int = maxi(1, int(link.get("movement_hours", 1)))
		if str(action.get("transport_state", "")) == "moving" and float(action.get("edge_load_remaining", 0.0)) <= EPSILON and int(action.get("edge_elapsed_hours", 0)) >= movement_hours:
			state.remove_capacity_request(action_id)
			edge_index += 1
			action["current_edge_index"] = edge_index
			action["reserved_link_id"] = ""
			if edge_index >= link_ids.size():
				if kind == "attack":
					formation.current_city_id = str(city_ids[city_ids.size() - 2])
					action["fallback_city_id"] = formation.current_city_id
					action["transport_state"] = "preparing"
					action["edge_load_total"] = 0.0
					action["edge_load_remaining"] = 0.0
					action["edge_started_hour"] = -1
					action["edge_elapsed_hours"] = 0
					action["preparation_start_hour"] = boundary_hour
					action["preparation_end_hour"] = boundary_hour + maxi(1, int(action.get("attack_preparation_hours", 1)))
					action["progress"] = 0.95
					state.active_actions[action_id] = action
				else:
					formation.current_city_id = str(action.get("destination_city_id", formation.current_city_id))
					formation.action_state = VNextMilitaryFormation.ACTION_IDLE
					formation.defense_posture = 1.0
					var completion: Dictionary = {
						"action_id": action_id,
						"kind": kind,
						"formation_id": formation.formation_id,
						"completed_at_hour": boundary_hour,
						"destination_city_id": formation.current_city_id,
						"success": true,
						"route": route.duplicate(true),
					}
					_record_completion(state, completion, completed)
					state.active_actions.erase(action_id)
			else:
				formation.current_city_id = str(city_ids[edge_index])
				var new_load: float = _formation_transport_load(formation)
				action["edge_request_hour"] = boundary_hour
				action["edge_started_hour"] = -1
				action["edge_elapsed_hours"] = 0
				action["edge_load_total"] = new_load
				action["edge_load_remaining"] = new_load
				action["transport_state"] = "waiting_capacity"
				action["progress"] = float(edge_index) / float(maxi(1, link_ids.size()))
				state.active_actions[action_id] = action
		else:
			var total_load: float = maxf(EPSILON, float(action.get("edge_load_total", 1.0)))
			var edge_fraction: float = clampf(1.0 - float(action.get("edge_load_remaining", total_load)) / total_load, 0.0, 1.0)
			action["progress"] = clampf((float(edge_index) + edge_fraction) / float(maxi(1, link_ids.size())), 0.0, 0.94 if kind == "attack" else 0.999)
			state.active_actions[action_id] = action
	_reconcile_transport_access(state, map)


func _reconcile_transport_access(state: VNextMilitaryState, map: VNextMilitaryMapAdapter) -> void:
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		var kind: String = str(action.get("kind", ""))
		if kind == "defend" or str(action.get("transport_state", "")) in ["preparing", "arrived"]:
			continue
		var route: Dictionary = action.get("route", {}) as Dictionary
		var link_ids: Array = route.get("link_ids", []) as Array
		var edge_index: int = int(action.get("current_edge_index", -1))
		if edge_index < 0 or edge_index >= link_ids.size():
			continue
		var link_id: String = str(link_ids[edge_index])
		var current_city_id: String = ""
		var destination_city_id: String = str(action.get("destination_city_id", ""))
		var owner_country_id: String = ""
		var allow_enemy_destination: bool = false
		if kind == "supply":
			current_city_id = str(action.get("current_city_id", ""))
			owner_country_id = str(action.get("owner_country_id", ""))
		else:
			var formation: VNextMilitaryFormation = state.get_formation(str(action.get("formation_id", "")))
			if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
				continue
			current_city_id = formation.current_city_id
			owner_country_id = formation.country_id
			allow_enemy_destination = bool(action.get("allow_enemy_destination", false))
		if map.can_enter_link(link_id, current_city_id, destination_city_id, owner_country_id, state.region_controls, allow_enemy_destination):
			continue
		state.remove_capacity_request(action_id)
		action["reserved_link_id"] = ""
		action["transport_state"] = "interrupted" if map.get_link_transport_capacity_per_hour(link_id) <= 0.0 else "blocked"
		state.active_actions[action_id] = action


func _advance_supply_action_at_boundary(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, action_id: String, boundary_hour: int) -> void:
	if not state.active_actions.has(action_id):
		return
	var action: Dictionary = state.active_actions[action_id] as Dictionary
	if str(action.get("transport_state", "")) == "arrived":
		return
	if str(action.get("transport_state", "")) == "moving" and int(action.get("edge_started_hour", -1)) >= 0:
		action["edge_elapsed_hours"] = int(action.get("edge_elapsed_hours", 0)) + 1
	var route: Dictionary = action.get("route", {}) as Dictionary
	var link_ids: Array = route.get("link_ids", []) as Array
	var city_ids: Array = route.get("city_ids", []) as Array
	var edge_index: int = int(action.get("current_edge_index", -1))
	if edge_index < 0 or edge_index >= link_ids.size():
		action["reserved_link_id"] = ""
		action["transport_state"] = "interrupted"
		state.active_actions[action_id] = action
		return
	var link: Dictionary = map.get_link(str(link_ids[edge_index]))
	var movement_hours: int = maxi(1, int(link.get("movement_hours", 1)))
	if str(action.get("transport_state", "")) == "moving" and float(action.get("edge_load_remaining", 0.0)) <= EPSILON and int(action.get("edge_elapsed_hours", 0)) >= movement_hours:
		state.remove_capacity_request(action_id)
		edge_index += 1
		action["current_edge_index"] = edge_index
		action["reserved_link_id"] = ""
		if edge_index >= link_ids.size():
			action["current_city_id"] = str(action.get("destination_city_id", ""))
			action["transport_state"] = "arrived"
			action["edge_load_total"] = 0.0
			action["edge_load_remaining"] = 0.0
			action["edge_started_hour"] = -1
			action["edge_elapsed_hours"] = 0
			action["progress"] = 1.0
			state.active_actions[action_id] = action
			return
		action["current_city_id"] = str(city_ids[edge_index])
		action["edge_request_hour"] = boundary_hour
		action["edge_started_hour"] = -1
		action["edge_elapsed_hours"] = 0
		var new_load: float = float(action.get("cargo_amount_remaining", 0.0)) * VNextMilitaryState.supply_cargo_weight(str(action.get("resource_id", "")))
		action["edge_load_total"] = new_load
		action["edge_load_remaining"] = new_load
		action["transport_state"] = "waiting_capacity"
		action["progress"] = float(edge_index) / float(maxi(1, link_ids.size()))
		state.active_actions[action_id] = action
		return
	var total_load: float = maxf(EPSILON, float(action.get("edge_load_total", 1.0)))
	var edge_fraction: float = clampf(1.0 - float(action.get("edge_load_remaining", total_load)) / total_load, 0.0, 1.0)
	action["progress"] = clampf((float(edge_index) + edge_fraction) / float(maxi(1, link_ids.size())), 0.0, 0.999)
	state.active_actions[action_id] = action


func _cancel_destroyed_formation_spatial_requests(
	state: VNextMilitaryState, map: VNextMilitaryMapAdapter
) -> void:
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation != null and formation.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
			_cancel_spatial_requests_for_formation(state, map, formation_id)


func _cancel_spatial_requests_for_formation(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	preserve_action_id: String = ""
) -> void:
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		if action_id == preserve_action_id or not state.active_actions.has(action_id):
			continue
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		var belongs_to_destroyed: bool = (
			(str(action.get("kind", "")) == "supply" and str(action.get("destination_formation_id", "")) == formation_id)
			or str(action.get("formation_id", "")) == formation_id
		)
		if not belongs_to_destroyed:
			continue
		_cancel_active_spatial_request(map, action)
		action["spatial_request_id"] = ""
		state.active_actions[action_id] = action


func _cleanup_all_destroyed_formation_references(state: VNextMilitaryState, boundary_hour: int, completed: Array[Dictionary]) -> void:
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation != null and formation.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
			_cleanup_destroyed_formation_references(state, formation_id, boundary_hour, completed)


func _cleanup_destroyed_formation_references(
	state: VNextMilitaryState,
	formation_id: String,
	boundary_hour: int,
	completed: Array[Dictionary],
	preserve_action_id: String = ""
) -> void:
	var formation: VNextMilitaryFormation = state.get_formation(formation_id)
	if formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_DESTROYED:
		return
	formation.action_state = VNextMilitaryFormation.ACTION_IDLE
	formation.defense_posture = 1.0
	var action_ids: Array[String] = _sorted_dictionary_keys(state.active_actions)
	for action_id: String in action_ids:
		if action_id == preserve_action_id or not state.active_actions.has(action_id):
			continue
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("kind", "")) == "supply":
			if str(action.get("destination_formation_id", "")) == formation_id:
				_cancel_supply_action(state, action, boundary_hour, "destination_formation_destroyed", completed)
			continue
		if str(action.get("formation_id", "")) == formation_id:
			_complete_interrupted_action(state, action, formation, boundary_hour, "formation_destroyed", completed)


func _cancel_supply_action(state: VNextMilitaryState, action: Dictionary, boundary_hour: int, reason: String, completed: Array[Dictionary]) -> void:
	var action_id: String = str(action.get("action_id", ""))
	var cargo_total: float = maxf(0.0, float(action.get("cargo_amount_total", 0.0)))
	var cargo_remaining: float = maxf(0.0, float(action.get("cargo_amount_remaining", 0.0)))
	var completion: Dictionary = {
		"action_id": action_id,
		"kind": "supply",
		"destination_formation_id": str(action.get("destination_formation_id", "")),
		"source_region_id": str(action.get("source_region_id", "")),
		"completed_at_hour": boundary_hour,
		"success": false,
		"outcome": "cancelled",
		"reason": reason,
		"resource_id": str(action.get("resource_id", "")),
		"cargo_amount_total": cargo_total,
		"cargo_delivered": maxf(0.0, cargo_total - cargo_remaining),
		"cargo_lost": cargo_remaining,
		"route": (action.get("route", {}) as Dictionary).duplicate(true),
	}
	_record_completion(state, completion, completed)
	state.remove_capacity_request(action_id)
	state.active_actions.erase(action_id)


func _complete_interrupted_action(
	state: VNextMilitaryState,
	action: Dictionary,
	formation: VNextMilitaryFormation,
	boundary_hour: int,
	reason: String,
	completed: Array[Dictionary]
) -> void:
	var action_id: String = str(action.get("action_id", ""))
	var completion: Dictionary = {
		"action_id": action_id,
		"kind": str(action.get("kind", "move")),
		"formation_id": formation.formation_id,
		"completed_at_hour": boundary_hour,
		"success": false,
		"outcome": "interrupted",
		"reason": reason,
		"route": (action.get("route", {}) as Dictionary).duplicate(true),
	}
	_record_completion(state, completion, completed)
	state.remove_capacity_request(action_id)
	state.active_actions.erase(action_id)


func _record_completion(state: VNextMilitaryState, completion: Dictionary, completed: Array[Dictionary]) -> void:
	var action_id: String = str(completion.get("action_id", ""))
	if state.active_actions.has(action_id):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		completion["capacity_window_hour"] = int(action.get("capacity_window_hour", -1))
		completion["capacity_link_id"] = str(action.get("capacity_link_id", ""))
		completion["capacity_used_this_window"] = float(action.get("capacity_used_this_window", 0.0))
	state.append_completed_action(completion)
	completed.append(completion.duplicate(true))
	action_completed.emit(completion.duplicate(true))


func _formation_transport_load(formation: VNextMilitaryFormation) -> float:
	var personnel_load: float = float(maxi(0, formation.personnel))
	var equipment_load: float = personnel_load * clampf(formation.equipment_factor(), 0.0, 1.5) * EQUIPMENT_LOAD_PER_PERSON
	var base_load: float = personnel_load + equipment_load
	return maxf(1.0, base_load / maxf(0.20, formation.movement_efficiency()))


func _estimate_transport_hours(map: VNextMilitaryMapAdapter, route: Dictionary, load: float) -> int:
	var total_hours: int = 0
	for raw_link_id: Variant in route.get("link_ids", []) as Array:
		var link_id: String = str(raw_link_id)
		var link: Dictionary = map.get_link(link_id)
		var movement_hours: int = maxi(1, int(link.get("movement_hours", 1)))
		var capacity_per_hour: float = map.get_link_transport_capacity_per_hour(link_id)
		if capacity_per_hour <= 0.0:
			return 2147483647
		var throughput_hours: int = maxi(1, ceili(load / capacity_per_hour))
		total_hours += maxi(movement_hours, throughput_hours)
	return maxi(1, total_hours)


func _movement_allowed_for_condition(formation: VNextMilitaryFormation, route: Dictionary) -> bool:
	if formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE or formation.personnel <= 0:
		return false
	var duration: int = int(route.get("duration_hours", 0))
	if duration > 48 and formation.supply_level < 0.05 and formation.organization < 0.05:
		return false
	return formation.movement_efficiency() >= 0.20


func _apply_supply_effects(
	formation: VNextMilitaryFormation,
	map: VNextMilitaryMapAdapter,
	supply_level: float,
	elapsed_days: float
) -> void:
	if formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
		return
	var supply: Dictionary = map.get_overlay_rules().get("supply", {}) as Dictionary
	var shortage: float = clampf(1.0 - supply_level, 0.0, 1.0)
	if shortage > 0.0:
		formation.organization = clampf(formation.organization - shortage * float(supply.get("organization_loss_per_day_at_zero", 0.07)) * elapsed_days, 0.0, 1.0)
		formation.morale = clampf(formation.morale - shortage * float(supply.get("morale_loss_per_day_at_zero", 0.05)) * elapsed_days, 0.0, 1.0)
		var equipment_factor: float = formation.equipment_factor()
		equipment_factor = clampf(equipment_factor - shortage * float(supply.get("equipment_loss_per_day_at_zero", 0.025)) * elapsed_days, 0.0, 1.5)
		formation.equipment_sets["equipment_factor"] = equipment_factor
		var losses: int = int(round(float(formation.personnel) * shortage * float(supply.get("personnel_loss_per_day_at_zero", 0.012)) * elapsed_days))
		formation.apply_losses(losses)
	else:
		formation.organization = clampf(formation.organization + float(supply.get("organization_recovery_per_day", 0.018)) * elapsed_days, 0.0, 1.0)
		formation.morale = clampf(formation.morale + float(supply.get("morale_recovery_per_day", 0.012)) * elapsed_days, 0.0, 1.0)
		formation.equipment_sets["equipment_factor"] = clampf(formation.equipment_factor() + float(supply.get("equipment_recovery_per_day", 0.01)) * elapsed_days, 0.0, 1.5)


func _resolve_attack(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	action: Dictionary,
	attacker: VNextMilitaryFormation,
	completed: Array[Dictionary]
) -> Dictionary:
	var target_city_id: String = str(action.get("destination_city_id", ""))
	var target_region_id: String = str(action.get("target_region_id", map.get_region_id_for_city(target_city_id)))
	var fallback_city_id: String = str(action.get("fallback_city_id", attacker.current_city_id))
	var defender_country_id: String = str(state.region_controls.get(target_region_id, ""))
	if defender_country_id.is_empty() or defender_country_id == attacker.country_id:
		attacker.current_city_id = fallback_city_id
		return {
			"success": false,
			"outcome": "cancelled",
			"reason": "目标已经不再是敌方控制区。",
			"action_id": str(action.get("action_id", "")),
			"target_region_id": target_region_id,
			"target_city_id": target_city_id,
			"control_changed": false,
			"war_status": "resolved",
		}
	var terrain: Dictionary = map.get_region_terrain(target_region_id)
	var defender_summary: Dictionary = _defender_summary(state, map, target_region_id, target_city_id)
	var attacker_personnel_before: int = attacker.personnel
	var attacker_power: float = _attacker_power(attacker, map, target_region_id)
	var defender_power: float = float(defender_summary.get("power", 0.0))
	var ratio: float = attacker_power / maxf(1.0, defender_power)
	var win_threshold: float = _battle_rule(map, "attack_ratio_for_win", 1.25)
	var hold_threshold: float = _battle_rule(map, "attack_ratio_for_hold", 0.85)
	var outcome: String = "stalemate"
	if ratio >= win_threshold and attacker.personnel > 0:
		outcome = "attacker_win"
	elif ratio <= hold_threshold:
		outcome = "defender_hold"
	var attacker_loss_rate: float
	var defender_loss_rate: float
	match outcome:
		"attacker_win":
			attacker_loss_rate = _battle_rule(map, "attacker_win_loss_rate", 0.08) / maxf(0.8, ratio)
			defender_loss_rate = _battle_rule(map, "defender_garrison_loss_rate_on_win", 0.72)
		"defender_hold":
			attacker_loss_rate = _battle_rule(map, "defender_win_loss_rate", 0.18)
			defender_loss_rate = _battle_rule(map, "attacker_win_loss_rate", 0.08)
		_:
			attacker_loss_rate = _battle_rule(map, "stalemate_loss_rate", 0.06)
			defender_loss_rate = _battle_rule(map, "stalemate_loss_rate", 0.06)
	var attacker_losses: int = mini(attacker.personnel, maxi(0, int(round(float(attacker.personnel) * clampf(attacker_loss_rate, 0.0, 0.9)))))
	var defender_formation_losses: int = maxi(0, int(round(float(defender_summary.get("formation_personnel", 0)) * clampf(defender_loss_rate, 0.0, 0.95))))
	var garrison_personnel: int = int(state.region_garrisons.get(target_region_id, 0))
	var garrison_losses: int = mini(garrison_personnel, maxi(0, int(round(float(garrison_personnel) * clampf(defender_loss_rate, 0.0, 0.95)))))
	var defender_losses_total: int = defender_formation_losses + garrison_losses
	var pressure_denominator: float = maxf(1.0, float(attacker_personnel_before + int(defender_summary.get("formation_personnel", 0)) + garrison_personnel))
	var mobilization_pressure: float = clampf(float(attacker_losses + defender_losses_total) / pressure_denominator, 0.0, 1.0)
	attacker.apply_losses(attacker_losses)
	var destroyed_defenders: Array[String] = _apply_defender_formation_losses(state, map, target_region_id, defender_country_id, defender_formation_losses)
	state.region_garrisons[target_region_id] = maxi(0, garrison_personnel - garrison_losses)
	var current_action_id: String = str(action.get("action_id", ""))
	if attacker.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
		_cancel_spatial_requests_for_formation(state, map, attacker.formation_id, current_action_id)
		_cleanup_destroyed_formation_references(state, attacker.formation_id, state.last_simulated_hour, completed, current_action_id)
	for destroyed_formation_id: String in destroyed_defenders:
		_cancel_spatial_requests_for_formation(state, map, destroyed_formation_id)
		_cleanup_destroyed_formation_references(state, destroyed_formation_id, state.last_simulated_hour, completed)
	var control_changed: bool = false
	if outcome == "attacker_win" and attacker.formation_status == VNextMilitaryFormation.STATUS_ACTIVE and attacker.personnel > 0:
		var previous_controller_id: String = defender_country_id
		if state.apply_region_control_change(target_region_id, attacker.country_id, "strategic_attack_victory", state.last_simulated_hour, "battle", current_action_id):
			control_changed = previous_controller_id != attacker.country_id
			if control_changed:
				var change_index: int = state.control_history.size() - 1
				var change: Dictionary = state.control_history[change_index] as Dictionary
				var origin_controller_id: String = map.get_initial_controller(target_region_id)
				for history_index: int in range(change_index - 1, -1, -1):
					var prior: Dictionary = state.control_history[history_index] as Dictionary
					if str(prior.get("region_id", "")) == target_region_id:
						origin_controller_id = str(prior.get("control_origin_controller_id", prior.get("previous_controller_id", origin_controller_id)))
						break
				change["control_origin_controller_id"] = origin_controller_id
				change["source_action_kind"] = "attack"
				change["source_formation_id"] = attacker.formation_id
				change["source_target_region_id"] = target_region_id
				change["source_controller_id"] = attacker.country_id
				change["source_preparation_end_hour"] = int(action.get("preparation_end_hour", -1))
				state.control_history[change_index] = change
				region_control_changed.emit(change.duplicate(true))
		attacker.current_city_id = target_city_id
	else:
		attacker.current_city_id = fallback_city_id
	return {
		"success": true,
		"outcome": outcome,
		"action_id": current_action_id,
		"attacker_formation_id": attacker.formation_id,
		"attacker_country_id": attacker.country_id,
		"defender_country_id": defender_country_id,
		"target_region_id": target_region_id,
		"target_city_id": target_city_id,
		"attacker_power": attacker_power,
		"defender_power": defender_power,
		"power_ratio": ratio,
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses_total,
		"casualties": {"attacker": attacker_losses, "defender": defender_losses_total},
		"mobilization_pressure": mobilization_pressure,
		"war_status": "resolved",
		"control_changed": control_changed,
		"controller_country_id": str(state.region_controls.get(target_region_id, defender_country_id)),
		"attacker_final_city_id": attacker.current_city_id,
		"factors": {
			"personnel": attacker_personnel_before,
			"equipment_factor": attacker.equipment_factor(),
			"attacker_supply_level": attacker.supply_level,
			"terrain_id": str(terrain.get("id", "")),
			"terrain_defense_factor": float(terrain.get("defense_factor", 1.0)),
			"defender_posture_multiplier": float(defender_summary.get("posture_multiplier", 1.0)),
			"defender_organization": float(defender_summary.get("average_organization", 0.0)),
			"defender_morale": float(defender_summary.get("average_morale", 0.0)),
		},
	}


func _attacker_power(formation: VNextMilitaryFormation, map: VNextMilitaryMapAdapter, target_region_id: String) -> float:
	return float(_formation_assessment(
		formation, map, target_region_id, "attack"
	).get("operational_effectiveness", 0.0))


func _defender_summary(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, target_region_id: String, target_city_id: String) -> Dictionary:
	var defender_country_id: String = str(state.region_controls.get(target_region_id, ""))
	var terrain: Dictionary = map.get_region_terrain(target_region_id)
	var terrain_factor: float = float(terrain.get("defense_factor", 1.0))
	var city_factor: float = map.get_city_defense_factor(target_city_id)
	var formation_personnel: int = 0
	var formation_power: float = 0.0
	var organization_total: float = 0.0
	var morale_total: float = 0.0
	var supply_total: float = 0.0
	var defender_count: int = 0
	var posture_multiplier: float = 1.0
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.country_id != defender_country_id or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE or formation.personnel <= 0:
			continue
		if map.get_region_id_for_city(formation.current_city_id) != target_region_id:
			continue
		var local_posture: float = formation.defense_posture if formation.action_state == VNextMilitaryFormation.ACTION_DEFENDING else 1.0
		formation_power += _base_formation_power(formation, map) * terrain_factor * city_factor * local_posture
		formation_personnel += formation.personnel
		organization_total += formation.organization
		morale_total += formation.morale
		supply_total += formation.supply_level
		posture_multiplier = maxf(posture_multiplier, local_posture)
		defender_count += 1
	var garrison_personnel: int = int(state.region_garrisons.get(target_region_id, 0))
	formation_power += float(garrison_personnel) * 0.45 * terrain_factor * city_factor
	return {
		"power": formation_power,
		"formation_personnel": formation_personnel,
		"garrison_personnel": garrison_personnel,
		"average_organization": organization_total / float(maxi(1, defender_count)),
		"average_morale": morale_total / float(maxi(1, defender_count)),
		"average_supply_level": supply_total / float(maxi(1, defender_count)),
		"posture_multiplier": posture_multiplier,
	}


func _base_formation_power(formation: VNextMilitaryFormation, map: VNextMilitaryMapAdapter) -> float:
	return float(capability_model.formation_effectiveness(
		formation,
		"attack",
		1.0,
		1.0,
		1.0,
		_battle_rule(map, "minimum_power_factor", 0.35)
	).get("operational_effectiveness", 0.0))


func _formation_assessment(
	formation: VNextMilitaryFormation,
	map: VNextMilitaryMapAdapter,
	target_region_id: String,
	role: String
) -> Dictionary:
	var terrain := map.get_region_terrain(target_region_id)
	return capability_model.formation_effectiveness(
		formation,
		role,
		float(terrain.get("defense_factor", 1.0)),
		1.0,
		1.0,
		_battle_rule(map, "minimum_power_factor", 0.35)
	)


func _apply_defender_formation_losses(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, target_region_id: String, defender_country_id: String, losses: int) -> Array[String]:
	var destroyed_ids: Array[String] = []
	var remaining_losses: int = maxi(0, losses)
	for formation_id: String in state.get_sorted_formation_ids():
		if remaining_losses <= 0:
			break
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.country_id != defender_country_id or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE or formation.personnel <= 0:
			continue
		if map.get_region_id_for_city(formation.current_city_id) != target_region_id:
			continue
		var applied: int = formation.apply_losses(mini(remaining_losses, formation.personnel))
		remaining_losses -= applied
		if formation.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
			destroyed_ids.append(formation_id)
	return destroyed_ids


func _supply_status(map: VNextMilitaryMapAdapter, level: float) -> String:
	var rules: Dictionary = map.get_overlay_rules().get("supply", {}) as Dictionary
	if level >= float(rules.get("full_threshold", 0.95)):
		return "full"
	if level >= float(rules.get("strained_threshold", 0.75)):
		return "strained"
	if level >= float(rules.get("low_threshold", 0.4)):
		return "low"
	return "cut"


func _battle_rule(map: VNextMilitaryMapAdapter, key: String, fallback: float) -> float:
	var rules: Dictionary = map.get_overlay_rules().get("battle", {}) as Dictionary
	return float(rules.get(key, fallback))


func _next_action_id(state: VNextMilitaryState) -> String:
	var sequence: int = state.next_action_sequence
	state.next_action_sequence += 1
	return VNextStableId.compose("military_action", "%06d" % sequence)


func _sort_prepared_formations(prepared: Array[Dictionary]) -> void:
	for index: int in range(prepared.size()):
		var best_index: int = index
		for candidate_index: int in range(index + 1, prepared.size()):
			if str(prepared[candidate_index].get("formation_id", "")) < str(prepared[best_index].get("formation_id", "")):
				best_index = candidate_index
		if best_index != index:
			var swap: Dictionary = prepared[index]
			prepared[index] = prepared[best_index]
			prepared[best_index] = swap


func _spatial_capacity_request_id(request: Dictionary, window_hour: int) -> String:
	return "%016d|%016d|military|%s|%s" % [
		int(request.get("request_hour", window_hour)), window_hour,
		str(request.get("request_id", "")), str(request.get("request_kind", "")),
	]


func _cancel_active_spatial_request(map: VNextMilitaryMapAdapter, action: Dictionary) -> void:
	var spatial: VNextSpatialWorld = map.get_spatial_world() if map != null else null
	var request_id: String = str(action.get("spatial_request_id", ""))
	var link_id: String = str(action.get("capacity_link_id", action.get("reserved_link_id", "")))
	var window_hour: int = int(action.get("capacity_window_hour", -1))
	if spatial != null and not request_id.is_empty() and not link_id.is_empty() and window_hour == spatial.current_hour():
		spatial.cancel_capacity_request(request_id, link_id, window_hour)


func _clear_spatial_request_references(state: VNextMilitaryState) -> void:
	for action_id: String in _sorted_dictionary_keys(state.active_actions):
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		action["spatial_request_id"] = ""
		state.active_actions[action_id] = action


func _sort_capacity_requests(requests: Array[Dictionary]) -> void:
	requests.sort_custom(Callable(self, "_capacity_request_less"))


func _capacity_request_less(first: Dictionary, second: Dictionary) -> bool:
	var first_hour: int = int(first.get("request_hour", 0))
	var second_hour: int = int(second.get("request_hour", 0))
	if first_hour != second_hour:
		return first_hour < second_hour
	var first_id: String = str(first.get("request_id", ""))
	var second_id: String = str(second.get("request_id", ""))
	if first_id != second_id:
		return first_id < second_id
	var first_kind: String = str(first.get("request_kind", ""))
	var second_kind: String = str(second.get("request_kind", ""))
	if first_kind != second_kind:
		return first_kind < second_kind
	var first_formation: String = str(first.get("formation_id", ""))
	var second_formation: String = str(second.get("formation_id", ""))
	if first_formation != second_formation:
		return first_formation < second_formation
	var first_resource: String = str(first.get("resource_id", ""))
	var second_resource: String = str(second.get("resource_id", ""))
	if first_resource != second_resource:
		return first_resource < second_resource
	return str(first.get("link_id", "")) < str(second.get("link_id", ""))


func _merge_supply_report(target: Dictionary, hourly: Dictionary) -> void:
	for formation_id: String in _sorted_dictionary_keys(hourly):
		var hour_record: Dictionary = hourly[formation_id] as Dictionary
		if not target.has(formation_id):
			target[formation_id] = {
				"formation_id": formation_id,
				"demand": {"food": 0.0, "ammunition": 0.0, "equipment": 0.0, "transport_capacity": 0.0},
				"delivered": {"food": 0.0, "ammunition": 0.0, "equipment": 0.0, "transport_capacity": 0.0},
				"fill": {},
				"supply_level": 0.0,
				"status": "cut",
				"source_region_ids": [],
				"route_link_ids": [],
			}
		var aggregate: Dictionary = target[formation_id] as Dictionary
		for resource_id: String in RESOURCE_IDS:
			(aggregate["demand"] as Dictionary)[resource_id] = float((aggregate["demand"] as Dictionary).get(resource_id, 0.0)) + float((hour_record.get("demand", {}) as Dictionary).get(resource_id, 0.0))
			(aggregate["delivered"] as Dictionary)[resource_id] = float((aggregate["delivered"] as Dictionary).get(resource_id, 0.0)) + float((hour_record.get("delivered", {}) as Dictionary).get(resource_id, 0.0))
		aggregate["fill"] = (hour_record.get("fill", {}) as Dictionary).duplicate(true)
		aggregate["supply_level"] = float(hour_record.get("supply_level", 0.0))
		aggregate["status"] = str(hour_record.get("status", "cut"))
		for raw_source: Variant in hour_record.get("source_region_ids", []) as Array:
			if not (aggregate["source_region_ids"] as Array).has(raw_source):
				(aggregate["source_region_ids"] as Array).append(raw_source)
		for raw_link: Variant in hour_record.get("route_link_ids", []) as Array:
			if not (aggregate["route_link_ids"] as Array).has(raw_link):
				(aggregate["route_link_ids"] as Array).append(raw_link)


func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in source.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
