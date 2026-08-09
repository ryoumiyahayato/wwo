class_name VNextMilitaryService
extends RefCounted
## Strategic military operations over the existing world-map transport graph.
## The caller supplies the external time boundary; this service never touches
## VNextWorldRuntime or creates a second world clock.

const RESOURCE_IDS: PackedStringArray = [
	"food",
	"ammunition",
	"equipment",
	"transport_capacity",
]

signal action_completed(action: Dictionary)
signal battle_resolved(result: Dictionary)
signal region_control_changed(change: Dictionary)


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


func set_region_controller(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	region_id: String,
	controller_id: String,
	reason: String = "military control update"
) -> bool:
	if state == null or map == null or not map.has_region(region_id) or not map.has_country(controller_id):
		return false
	var previous_controller_id: String = str(state.region_controls.get(region_id, ""))
	if not state.set_region_controller(region_id, controller_id, reason):
		return false
	if previous_controller_id != controller_id:
		var change: Dictionary = state.control_history.back() as Dictionary
		region_control_changed.emit(change.duplicate(true))
	return true


func deploy(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	destination_city_id: String,
	start_hour: int
) -> Dictionary:
	return _issue_transport_action(
		state, map, formation_id, destination_city_id, start_hour, "deploy", false
	)


func move(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String,
	destination_city_id: String,
	start_hour: int
) -> Dictionary:
	return _issue_transport_action(
		state, map, formation_id, destination_city_id, start_hour, "move", false
	)


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
	var prepared: Array[Dictionary] = []
	var owner_id: String = ""
	for formation_id: String in formation_ids:
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.action_state != VNextMilitaryFormation.ACTION_IDLE:
			return _failure("集中要求所有部队都处于待命状态。")
		if owner_id.is_empty():
			owner_id = formation.country_id
		elif owner_id != formation.country_id:
			return _failure("集中不能混合不同控制方的部队。")
		var route: Dictionary = map.find_route(
			formation.current_city_id,
			destination_city_id,
			[],
			owner_id,
			state.region_controls,
			false
		)
		if not bool(route.get("reachable", false)):
			return _failure("集中路线不可通行。")
		prepared.append({"formation_id": formation_id, "route": route})
	var action_ids: Array[String] = []
	for item: Dictionary in prepared:
		var formation: VNextMilitaryFormation = state.get_formation(str(item["formation_id"]))
		var action_id: String = _next_action_id(state, "concentrate")
		var route: Dictionary = item["route"] as Dictionary
		var action: Dictionary = _new_transport_action(
			action_id,
			"concentrate",
			formation,
			destination_city_id,
			start_hour,
			route
		)
		state.active_actions[action_id] = action
		formation.action_state = VNextMilitaryFormation.ACTION_CONCENTRATING
		action_ids.append(action_id)
	return {
		"success": true,
		"action_ids": action_ids,
		"destination_city_id": destination_city_id,
	}


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
	if formation == null or formation.action_state != VNextMilitaryFormation.ACTION_IDLE:
		return _failure("该部队当前不能建立防御姿态。")
	var region_id: String = map.get_region_id_for_city(formation.current_city_id)
	if str(state.region_controls.get(region_id, "")) != formation.country_id:
		return _failure("部队不在己方控制区，不能建立防御姿态。")
	var action_id: String = _next_action_id(state, "defend")
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
	}
	formation.action_state = VNextMilitaryFormation.ACTION_DEFENDING
	formation.defense_posture = _battle_rule(map, "defense_posture_multiplier", 1.2)
	return {
		"success": true,
		"action_id": action_id,
		"eta_hour": start_hour + duration_hours,
		"defense_posture": formation.defense_posture,
	}


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
	if formation == null or formation.action_state != VNextMilitaryFormation.ACTION_IDLE:
		return _failure("该部队当前不能发起进攻。")
	if not map.has_city(target_city_id):
		return _failure("进攻目标城市不存在。")
	var target_region_id: String = map.get_region_id_for_city(target_city_id)
	var target_controller_id: String = str(state.region_controls.get(target_region_id, ""))
	if target_controller_id.is_empty() or target_controller_id == formation.country_id:
		return _failure("进攻目标必须是敌方控制区。")
	var route: Dictionary = map.find_route(
		formation.current_city_id,
		target_city_id,
		[],
		formation.country_id,
		state.region_controls,
		true
	)
	if not bool(route.get("reachable", false)):
		return _failure("进攻路线不可通行。")
	var action_id: String = _next_action_id(state, "attack")
	var preparation_hours: int = maxi(1, int(_battle_rule(map, "attack_preparation_hours", 24.0)))
	var action: Dictionary = _new_transport_action(
		action_id,
		"attack",
		formation,
		target_city_id,
		start_hour,
		route
	)
	action["target_region_id"] = target_region_id
	action["eta_hour"] = int(action["eta_hour"]) + preparation_hours
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
	if target_hour < state.last_simulated_hour:
		return _failure("军事时间不能倒退。")
	var elapsed_hours: int = target_hour - state.last_simulated_hour
	var supply_report: Dictionary = _update_supply(state, map, elapsed_hours)
	var completed: Array[Dictionary] = []
	var battles: Array[Dictionary] = []
	var action_ids: Array[String] = _sorted_dictionary_keys(state.active_actions)
	for action_id: String in action_ids:
		if not state.active_actions.has(action_id):
			continue
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		var start_hour: int = int(action.get("start_hour", target_hour))
		var eta_hour: int = int(action.get("eta_hour", target_hour))
		var duration_hours: int = maxi(1, eta_hour - start_hour)
		if target_hour < eta_hour:
			action["progress"] = clampf(float(target_hour - start_hour) / float(duration_hours), 0.0, 0.99)
			state.active_actions[action_id] = action
			continue
		var formation_id: String = str(action.get("formation_id", ""))
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null:
			state.active_actions.erase(action_id)
			continue
		var completion: Dictionary
		match str(action.get("kind", "")):
			"attack":
				completion = _resolve_attack(state, map, action, formation)
				battles.append(completion.duplicate(true))
				state.battle_results.append(completion.duplicate(true))
				battle_resolved.emit(completion.duplicate(true))
				formation.action_state = VNextMilitaryFormation.ACTION_IDLE
				formation.defense_posture = 1.0
			"defend":
				formation.action_state = VNextMilitaryFormation.ACTION_IDLE
				formation.defense_posture = 1.0
				completion = {
					"action_id": action_id,
					"kind": "defend",
					"formation_id": formation_id,
					"completed_at_hour": target_hour,
					"success": true,
				}
			_:
				formation.current_city_id = str(action.get("destination_city_id", formation.current_city_id))
				formation.action_state = VNextMilitaryFormation.ACTION_IDLE
				formation.defense_posture = 1.0
				completion = {
					"action_id": action_id,
					"kind": str(action.get("kind", "move")),
					"formation_id": formation_id,
					"completed_at_hour": target_hour,
					"destination_city_id": formation.current_city_id,
					"success": true,
				}
		var completion_route: Variant = action.get("route", {})
		if completion_route is Dictionary:
			completion["route"] = (completion_route as Dictionary).duplicate(true)
		state.completed_actions.append(completion.duplicate(true))
		completed.append(completion.duplicate(true))
		action_completed.emit(completion.duplicate(true))
		state.active_actions.erase(action_id)
	state.last_simulated_hour = target_hour
	return {
		"success": true,
		"elapsed_hours": elapsed_hours,
		"supply": supply_report,
		"completed_actions": completed,
		"battles": battles,
		"last_simulated_hour": state.last_simulated_hour,
	}


func get_action(state: VNextMilitaryState, action_id: String) -> Dictionary:
	if state == null:
		return {}
	return (state.active_actions.get(action_id, {}) as Dictionary).duplicate(true)


func get_formation_view(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation_id: String
) -> Dictionary:
	if state == null or map == null:
		return {}
	var formation: VNextMilitaryFormation = state.get_formation(formation_id)
	if formation == null:
		return {}
	var result: Dictionary = formation.to_dict()
	result["region_id"] = map.get_region_id_for_city(formation.current_city_id)
	result["city_name"] = str(map.get_city(formation.current_city_id).get("name", formation.current_city_id))
	return result


func get_region_view(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	region_id: String
) -> Dictionary:
	if state == null or map == null:
		return {}
	var result: Dictionary = map.get_region_report(region_id, state.region_controls)
	if result.is_empty():
		return {}
	var stationed: Array[Dictionary] = []
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if map.get_region_id_for_city(formation.current_city_id) == region_id:
			stationed.append(get_formation_view(state, map, formation_id))
	result["formations"] = stationed
	result["garrison_personnel"] = int(state.region_garrisons.get(region_id, 0))
	return result


func preview_battle(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	attacker_formation_id: String,
	target_city_id: String
) -> Dictionary:
	if state == null or map == null or not map.has_city(target_city_id):
		return {}
	var attacker: VNextMilitaryFormation = state.get_formation(attacker_formation_id)
	if attacker == null:
		return {}
	var target_region_id: String = map.get_region_id_for_city(target_city_id)
	var terrain: Dictionary = map.get_region_terrain(target_region_id)
	var defender_summary: Dictionary = _defender_summary(state, map, target_region_id, target_city_id)
	var attacker_power: float = _attacker_power(attacker, map, target_region_id)
	var defender_power: float = float(defender_summary.get("power", 0.0))
	return {
		"attacker_power": attacker_power,
		"defender_power": defender_power,
		"power_ratio": attacker_power / maxf(1.0, defender_power),
		"terrain_defense_factor": float(terrain.get("defense_factor", 1.0)),
		"attacker_supply_level": attacker.supply_level,
		"defender_supply_level": float(defender_summary.get("average_supply_level", 0.0)),
		"defender_posture_multiplier": float(defender_summary.get("posture_multiplier", 1.0)),
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
	if formation == null or formation.action_state != VNextMilitaryFormation.ACTION_IDLE:
		return _failure("该部队当前不能接收新的移动命令。")
	if not map.has_city(destination_city_id):
		return _failure("移动目标城市不存在。")
	var route: Dictionary = map.find_route(
		formation.current_city_id,
		destination_city_id,
		[],
		formation.country_id,
		state.region_controls,
		allow_enemy_destination
	)
	if not bool(route.get("reachable", false)):
		return _failure(str(route.get("reason", "移动路线不可通行。")))
	var action_id: String = _next_action_id(state, kind)
	var action: Dictionary = _new_transport_action(
		action_id,
		kind,
		formation,
		destination_city_id,
		start_hour,
		route
	)
	state.active_actions[action_id] = action
	formation.action_state = VNextMilitaryFormation.ACTION_MOVING
	return {
		"success": true,
		"action_id": action_id,
		"eta_hour": int(action["eta_hour"]),
		"route": route.duplicate(true),
	}


func _new_transport_action(
	action_id: String,
	kind: String,
	formation: VNextMilitaryFormation,
	destination_city_id: String,
	start_hour: int,
	route: Dictionary
) -> Dictionary:
	var route_hours: int = maxi(1, int(route.get("duration_hours", 0)))
	var capacity_personnel: int = maxi(0, int(route.get("capacity_personnel", 0)))
	var transport_waves: int = 1
	if capacity_personnel > 0:
		transport_waves = maxi(1, ceili(float(maxi(1, formation.personnel)) / float(capacity_personnel)))
	var travel_hours: int = route_hours * transport_waves
	return {
		"action_id": action_id,
		"kind": kind,
		"formation_id": formation.formation_id,
		"origin_city_id": formation.current_city_id,
		"destination_city_id": destination_city_id,
		"target_region_id": "",
		"start_hour": start_hour,
		"eta_hour": start_hour + travel_hours,
		"transport_waves": transport_waves,
		"transport_capacity_personnel": capacity_personnel,
		"progress": 0.0,
		"route": route.duplicate(true),
	}


func _update_supply(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	elapsed_hours: int
) -> Dictionary:
	if elapsed_hours <= 0:
		return {}
	var elapsed_days: float = float(elapsed_hours) / 24.0
	var source_remaining: Dictionary = {}
	for source_region_id: String in _sorted_dictionary_keys(state.supply_inputs):
		var source_input: Dictionary = state.supply_inputs[source_region_id] as Dictionary
		var remaining: Dictionary = {}
		for resource_id: String in RESOURCE_IDS:
			remaining[resource_id] = maxf(0.0, float(source_input.get(resource_id, 0.0)) * elapsed_days)
		source_remaining[source_region_id] = remaining
	var report: Dictionary = {}
	for formation_id: String in state.get_sorted_formation_ids():
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.personnel <= 0:
			continue
		var demand: Dictionary = {}
		for resource_id: String in RESOURCE_IDS:
			demand[resource_id] = maxf(0.0, float(formation.daily_requirements.get(resource_id, 0.0)) * elapsed_days)
		var delivered: Dictionary = {"food": 0.0, "ammunition": 0.0, "equipment": 0.0, "transport_capacity": 0.0}
		var sources: Array[Dictionary] = _supply_candidates(state, map, formation)
		var source_regions_used: Array[String] = []
		var route_ids_used: Array[String] = []
		for candidate: Dictionary in sources:
			var source_region_id: String = str(candidate["source_region_id"])
			var route: Dictionary = candidate["route"] as Dictionary
			var remaining: Dictionary = source_remaining[source_region_id] as Dictionary
			var same_region: bool = source_region_id == map.get_region_id_for_city(formation.current_city_id)
			var route_capacity_remaining: float = INF if same_region else map.get_route_capacity_per_day(route) * elapsed_days
			for resource_id: String in RESOURCE_IDS:
				var needed: float = maxf(0.0, float(demand[resource_id]) - float(delivered[resource_id]))
				if needed <= 0.0:
					continue
				var available: float = maxf(0.0, float(remaining.get(resource_id, 0.0)))
				var deliverable: float = minf(needed, available)
				if not same_region:
					deliverable = minf(deliverable, maxf(0.0, route_capacity_remaining))
				if deliverable <= 0.0:
					continue
				delivered[resource_id] = float(delivered[resource_id]) + deliverable
				remaining[resource_id] = available - deliverable
				if not same_region:
					route_capacity_remaining = maxf(0.0, route_capacity_remaining - deliverable)
			if source_regions_used.find(source_region_id) < 0:
				source_regions_used.append(source_region_id)
			for link_id: String in route.get("link_ids", []) as Array:
				if not route_ids_used.has(link_id):
					route_ids_used.append(link_id)
		var fill: Dictionary = {}
		var minimum_fill: float = 1.0
		var has_demand: bool = false
		for resource_id: String in RESOURCE_IDS:
			var required: float = float(demand[resource_id])
			var ratio: float = 1.0 if required <= 0.0 else clampf(float(delivered[resource_id]) / required, 0.0, 1.0)
			fill[resource_id] = ratio
			if required > 0.0:
				has_demand = true
				minimum_fill = minf(minimum_fill, ratio)
		if not has_demand:
			minimum_fill = 1.0
		var status: String = _supply_status(map, minimum_fill)
		formation.update_supply(fill, minimum_fill, status)
		_apply_supply_effects(formation, map, minimum_fill, elapsed_days)
		report[formation_id] = {
			"formation_id": formation_id,
			"demand": demand,
			"delivered": delivered,
			"fill": fill,
			"supply_level": minimum_fill,
			"status": status,
			"source_region_ids": source_regions_used,
			"route_link_ids": route_ids_used,
		}
	return report


func _supply_candidates(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	formation: VNextMilitaryFormation
) -> Array[Dictionary]:
	var destination_city_id: String = formation.current_city_id
	var candidates: Array[Dictionary] = []
	for source_region_id: String in _sorted_dictionary_keys(state.supply_inputs):
		var source_city_ids: Array[String] = map.get_city_ids_for_region(source_region_id)
		if source_city_ids.is_empty():
			continue
		var route: Dictionary = map.find_route(
			source_city_ids[0],
			destination_city_id,
			[],
			formation.country_id,
			state.region_controls,
			false
		)
		if bool(route.get("reachable", false)):
			candidates.append({
				"source_region_id": source_region_id,
				"route": route,
			})
	for index: int in range(candidates.size()):
		var best_index: int = index
		for candidate_index: int in range(index + 1, candidates.size()):
			var candidate: Dictionary = candidates[candidate_index] as Dictionary
			var best: Dictionary = candidates[best_index] as Dictionary
			var candidate_hours: int = int((candidate["route"] as Dictionary).get("duration_hours", 0))
			var best_hours: int = int((best["route"] as Dictionary).get("duration_hours", 0))
			if candidate_hours < best_hours or (candidate_hours == best_hours and str(candidate["source_region_id"]) < str(best["source_region_id"])):
				best_index = candidate_index
		if best_index != index:
			var swap: Dictionary = candidates[index] as Dictionary
			candidates[index] = candidates[best_index]
			candidates[best_index] = swap
	return candidates


func _apply_supply_effects(
	formation: VNextMilitaryFormation,
	map: VNextMilitaryMapAdapter,
	supply_level: float,
	elapsed_days: float
) -> void:
	var supply: Dictionary = map.get_overlay_rules().get("supply", {}) as Dictionary
	var shortage: float = clampf(1.0 - supply_level, 0.0, 1.0)
	if shortage > 0.0:
		formation.organization = clampf(
			formation.organization - shortage * float(supply.get("organization_loss_per_day_at_zero", 0.07)) * elapsed_days,
			0.0,
			1.0
		)
		formation.morale = clampf(
			formation.morale - shortage * float(supply.get("morale_loss_per_day_at_zero", 0.05)) * elapsed_days,
			0.0,
			1.0
		)
		var equipment_factor: float = formation.equipment_factor()
		equipment_factor = clampf(
			equipment_factor - shortage * float(supply.get("equipment_loss_per_day_at_zero", 0.025)) * elapsed_days,
			0.0,
			1.5
		)
		formation.equipment_sets["equipment_factor"] = equipment_factor
		var losses: int = int(round(float(formation.personnel) * shortage * float(supply.get("personnel_loss_per_day_at_zero", 0.012)) * elapsed_days))
		formation.apply_losses(losses)
	else:
		formation.organization = clampf(
			formation.organization + float(supply.get("organization_recovery_per_day", 0.018)) * elapsed_days,
			0.0,
			1.0
		)
		formation.morale = clampf(
			formation.morale + float(supply.get("morale_recovery_per_day", 0.012)) * elapsed_days,
			0.0,
			1.0
		)


func _resolve_attack(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	action: Dictionary,
	attacker: VNextMilitaryFormation
) -> Dictionary:
	var target_city_id: String = str(action.get("destination_city_id", ""))
	var target_region_id: String = str(action.get("target_region_id", map.get_region_id_for_city(target_city_id)))
	var defender_country_id: String = str(state.region_controls.get(target_region_id, ""))
	if defender_country_id.is_empty() or defender_country_id == attacker.country_id:
		return {
			"success": false,
			"outcome": "cancelled",
			"reason": "目标已经不再是敌方控制区。",
			"action_id": str(action.get("action_id", "")),
			"target_region_id": target_region_id,
		}
	var terrain: Dictionary = map.get_region_terrain(target_region_id)
	var defender_summary: Dictionary = _defender_summary(state, map, target_region_id, target_city_id)
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
	var attacker_losses: int = int(round(float(attacker.personnel) * clampf(attacker_loss_rate, 0.0, 0.9)))
	var defender_formation_losses: int = int(round(float(defender_summary.get("formation_personnel", 0)) * clampf(defender_loss_rate, 0.0, 0.95)))
	var garrison_personnel: int = int(state.region_garrisons.get(target_region_id, 0))
	var garrison_losses: int = int(round(float(garrison_personnel) * clampf(defender_loss_rate, 0.0, 0.95)))
	var defender_losses_total: int = defender_formation_losses + garrison_losses
	var pressure_denominator: float = maxf(1.0, float(attacker.personnel + attacker_losses + int(defender_summary.get("formation_personnel", 0)) + garrison_personnel))
	var mobilization_pressure: float = clampf(float(attacker_losses + defender_losses_total) / pressure_denominator, 0.0, 1.0)
	attacker.apply_losses(attacker_losses)
	_apply_defender_formation_losses(state, map, target_region_id, defender_country_id, defender_formation_losses)
	state.region_garrisons[target_region_id] = maxi(0, garrison_personnel - garrison_losses)
	var control_changed: bool = false
	if outcome == "attacker_win" and attacker.personnel > 0:
		var previous_controller_id: String = defender_country_id
		if state.set_region_controller(target_region_id, attacker.country_id, "战略进攻胜利"):
			control_changed = previous_controller_id != attacker.country_id
			if control_changed:
				var change: Dictionary = state.control_history.back() as Dictionary
				region_control_changed.emit(change.duplicate(true))
	# The attacking formation has spent the action reaching the target even when
	# the defender holds the region; its next order must start from this city.
	attacker.current_city_id = target_city_id
	return {
		"success": true,
		"outcome": outcome,
		"action_id": str(action.get("action_id", "")),
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
		"casualties": {
			"attacker": attacker_losses,
			"defender": defender_losses_total,
		},
		"mobilization_pressure": mobilization_pressure,
		"war_status": "resolved",
		"control_changed": control_changed,
		"controller_country_id": str(state.region_controls.get(target_region_id, defender_country_id)),
		"factors": {
			"personnel": attacker.personnel + attacker_losses,
			"equipment_factor": attacker.equipment_factor(),
			"attacker_supply_level": attacker.supply_level,
			"terrain_id": str(terrain.get("id", "")),
			"terrain_defense_factor": float(terrain.get("defense_factor", 1.0)),
			"defender_posture_multiplier": float(defender_summary.get("posture_multiplier", 1.0)),
			"defender_organization": float(defender_summary.get("average_organization", 0.0)),
			"defender_morale": float(defender_summary.get("average_morale", 0.0)),
		},
	}


func _attacker_power(
	formation: VNextMilitaryFormation,
	map: VNextMilitaryMapAdapter,
	target_region_id: String
) -> float:
	var terrain: Dictionary = map.get_region_terrain(target_region_id)
	var minimum_power_factor: float = _battle_rule(map, "minimum_power_factor", 0.35)
	var training_factor: float = 0.45 + formation.training * 0.2 + formation.organization * 0.35
	var morale_factor: float = 0.45 + formation.morale * 0.55
	var supply_factor: float = maxf(minimum_power_factor, 0.35 + formation.supply_level * 0.65)
	var terrain_factor: float = 1.0 / maxf(1.0, float(terrain.get("defense_factor", 1.0)))
	return maxf(0.0, float(formation.personnel) * formation.equipment_factor() * training_factor * morale_factor * supply_factor * terrain_factor)


func _defender_summary(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	target_region_id: String,
	target_city_id: String
) -> Dictionary:
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
		if formation == null or formation.country_id != defender_country_id or formation.personnel <= 0:
			continue
		if map.get_region_id_for_city(formation.current_city_id) != target_region_id:
			continue
		var base_power: float = _base_formation_power(formation, map)
		var local_posture: float = formation.defense_posture if formation.action_state == VNextMilitaryFormation.ACTION_DEFENDING else 1.0
		formation_power += base_power * terrain_factor * city_factor * local_posture
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


func _base_formation_power(
	formation: VNextMilitaryFormation,
	map: VNextMilitaryMapAdapter
) -> float:
	var minimum_power_factor: float = _battle_rule(map, "minimum_power_factor", 0.35)
	var training_factor: float = 0.45 + formation.training * 0.2 + formation.organization * 0.35
	var morale_factor: float = 0.45 + formation.morale * 0.55
	var supply_factor: float = maxf(minimum_power_factor, 0.35 + formation.supply_level * 0.65)
	return maxf(0.0, float(formation.personnel) * formation.equipment_factor() * training_factor * morale_factor * supply_factor)


func _apply_defender_formation_losses(
	state: VNextMilitaryState,
	map: VNextMilitaryMapAdapter,
	target_region_id: String,
	defender_country_id: String,
	losses: int
) -> void:
	var remaining_losses: int = maxi(0, losses)
	for formation_id: String in state.get_sorted_formation_ids():
		if remaining_losses <= 0:
			break
		var formation: VNextMilitaryFormation = state.get_formation(formation_id)
		if formation == null or formation.country_id != defender_country_id or formation.personnel <= 0:
			continue
		if map.get_region_id_for_city(formation.current_city_id) != target_region_id:
			continue
		var applied: int = formation.apply_losses(mini(remaining_losses, formation.personnel))
		remaining_losses -= applied


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


func _next_action_id(state: VNextMilitaryState, kind: String) -> String:
	var sequence: int = state.next_action_sequence
	state.next_action_sequence += 1
	return "military_action:%s_%06d" % [kind, sequence]


func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in source.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
