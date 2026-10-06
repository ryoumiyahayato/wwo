extends RefCounted
## EXPERIMENT ONLY. One bound person replaces only the input owned by their position.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const ECHELONS: Array[String] = ["squad", "platoon", "company", "battalion", "regiment", "division"]
const ROLES: Array[String] = ["ordinary_soldier", "squad_leader", "platoon_leader",
	"company_commander", "battalion_commander", "regiment_commander", "division_commander"]
const INPUT_SECONDS: Array[float] = [30.0, 60.0, 120.0, 300.0, 600.0, 1200.0, 1800.0]
const POSTURES: Array[String] = ["idle", "hold", "advance", "support", "withdraw"]

var _state: State
var _formations: Dictionary = {}
var _people: Dictionary = {}
var _children: Dictionary = {}
var _leaves: Dictionary = {}
var _mission_inputs: Dictionary = {}
var _coordination_inputs: Dictionary = {}
var _accepted_ids: Dictionary = {}
var _next_input: Dictionary = {}
var _player_id: String = ""
var _personal_actions: Dictionary = {}


func configure(state: State, formations: Dictionary, people: Dictionary, player_id: String) -> bool:
	# One-time trusted snapshot admission. No mutation on invalid membership/position.
	if _state != null or not people.has(player_id):
		return false
	var occupied: Dictionary = {}
	var unit_membership: Dictionary = {}
	for id: String in State.sorted_ids(formations):
		var node: Dictionary = formations[id]
		if not _keys(node, ["echelon", "parent", "side", "unit_id"]) or not node.get("echelon", "") in ECHELONS:
			return false
		var rank: int = ECHELONS.find(str(node.echelon))
		var parent: String = str(node.get("parent", ""))
		if not parent.is_empty():
			if not formations.has(parent) or ECHELONS.find(str(formations[parent].get("echelon", ""))) != rank + 1 or formations[parent].get("side", "") != node.get("side", ""):
				return false
		if rank == 0:
			var unit_id: String = str(node.get("unit_id", ""))
			if not state.units.has(unit_id) or unit_membership.has(unit_id) or state.units[unit_id].side != node.get("side", ""):
				return false
			unit_membership[unit_id] = true
		elif node.has("unit_id"):
			return false
	for id: String in State.sorted_ids(people):
		var person: Dictionary = people[id]
		if not _keys(person, ["role", "formation_id"]) or not person.get("role", "") in ROLES or not formations.has(person.get("formation_id", "")):
			return false
		var rank: int = ROLES.find(str(person.role))
		if str(formations[person.formation_id].echelon) != ECHELONS[maxi(0, rank - 1)]:
			return false
		if rank > 0:
			if occupied.has(person.formation_id):
				return false
			occupied[person.formation_id] = true
	_state = state
	_formations = formations.duplicate(true)
	_people = people.duplicate(true)
	_player_id = player_id
	for id: String in State.sorted_ids(_formations):
		_children[id] = {}
		_leaves[id] = {}
	for id: String in State.sorted_ids(_formations):
		var parent: String = str(_formations[id].get("parent", ""))
		if not parent.is_empty():
			_children[parent][id] = true
		if _formations[id].echelon == "squad":
			var cursor: String = id
			while not cursor.is_empty():
				_leaves[cursor][id] = true
				cursor = str(_formations[cursor].get("parent", ""))
	return true


func apply(command: Dictionary) -> Dictionary:
	if _state == null:
		return _reject("not_configured")
	if not _keys(command, ["id", "kind", "target", "values"]) or not command.get("id") is String or str(command.id).is_empty() or not command.get("values") is Dictionary:
		return _reject("invalid_command")
	var id: String = str(command.id)
	if _accepted_ids.has(id):
		return _reject("duplicate_command")
	var person: Dictionary = _people[_player_id]
	var rank: int = ROLES.find(str(person.role))
	var owner: String = str(person.formation_id)
	var kind: String = str(command.get("kind", ""))
	var target: String = str(command.get("target", ""))
	var values: Dictionary = command.values
	if kind == "local_action":
		if rank != 0 or target != _player_id:
			return _reject("wrong_owner_or_layer")
		if not _keys(values, ["action"]) or not values.get("action", "") in ["wait", "take_cover", "step_forward", "step_back"]:
			return _reject("invalid_local_action")
	elif kind == "tactical_intent":
		if rank != 1 or target != owner:
			return _reject("wrong_owner_or_layer")
		if not _keys(values, ["posture"]) or not values.get("posture", "") in ["hold", "advance", "support"]:
			return _reject("invalid_tactical_intent")
	elif kind in ["mission", "coordination"]:
		# Higher rank does not inherit direct ownership of lower decision inputs.
		if rank < 2 or not _formations.has(target) or not (target == owner and rank >= 3 or _children[owner].has(target)):
			return _reject("wrong_owner_or_layer")
		if _leaves[target].is_empty():
			return _reject("empty_scope")
		if kind == "mission":
			if not _keys(values, ["posture", "objective", "direction"]) or not values.get("posture", "") in POSTURES or not _number(values.get("objective")) or not _number(values.get("direction")) or absf(float(values.direction)) != 1.0:
				return _reject("invalid_mission")
			for leaf: String in State.sorted_ids(_leaves[target]):
				var unit: Dictionary = _state.units[_formations[leaf].unit_id]
				if float(values.objective) < 0.0 or float(values.objective) > float(_state.areas[unit.area_id].size_km):
					return _reject("objective_outside_scope")
		else:
			if not _keys(values, ["posture", "release_after"]) or not values.get("posture", "") in ["hold", "advance", "support"] or not _number(values.get("release_after")) or float(values.release_after) < 0.0 or float(values.release_after) > 86400.0:
				return _reject("invalid_coordination")
	else:
		return _reject("wrong_layer")
	if _state.time < float(_next_input.get(_player_id, 0.0)):
		return _reject("input_not_due")
	var affected: Array[String] = []
	if kind != "local_action":
		affected = State.sorted_ids(_leaves[target])
	# Preflight every resource ID before committing anything, including clocks/IDs.
	for leaf: String in affected:
		var unit_id: String = str(_formations[leaf].unit_id)
		# Replacing a prerequisite needs explicit dependency migration semantics.
		# Reject the whole command rather than orphaning reserves on an old ID.
		if kind == "mission" and not (_state.mission_dependents.get(_state.units[unit_id].mission_id, {}) as Dictionary).is_empty():
			return _reject("mission_has_dependents")
		if kind == "mission" and _state.missions.has("role_" + id + "_" + unit_id):
			return _reject("mission_id_collision")
		if kind == "coordination" and _state.event_ids.has("role_release_" + id + "_" + unit_id):
			return _reject("event_id_collision")
	var delta: Dictionary = {"units": {}, "missions": {}, "tactical_intents": {}, "command_coordination": {}, "personal_actions": {}}
	if kind == "local_action":
		var unit: Dictionary = _state.units[_formations[owner].unit_id]
		var personal: Dictionary = _personal_actions.get(_player_id, {"offset_km": 0.0}).duplicate(true)
		var step: float = 0.005 if values.action == "step_forward" else (-0.005 if values.action == "step_back" else 0.0)
		personal.offset_km = clampf(float(personal.offset_km) + step, -0.02, 0.02)
		personal.action = values.action
		personal.time = _state.time
		personal.position = clampf(float(unit.position) + float(personal.offset_km), 0.0, float(_state.areas[unit.area_id].size_km))
		_personal_actions[_player_id] = personal
		delta.personal_actions[_player_id] = personal.duplicate(true)
	elif kind == "tactical_intent":
		var unit_id: String = str(_formations[target].unit_id)
		_state.tactical_intents[unit_id] = values.duplicate(true)
		delta.tactical_intents[unit_id] = values.duplicate(true)
		_state.wake(str(_state.units[unit_id].area_id))
	else:
		if kind == "mission":
			_mission_inputs[target] = values.duplicate(true)
		else:
			_coordination_inputs[target] = {"posture": values.posture, "release_time": _state.time + float(values.release_after)}
		for leaf: String in affected:
			var unit_id: String = str(_formations[leaf].unit_id)
			var unit: Dictionary = _state.units[unit_id]
			if kind == "mission":
				var input: Dictionary = _nearest_input(leaf, _mission_inputs)
				var mission: Dictionary = _state.missions[unit.mission_id].duplicate(true)
				mission.merge(input, true)
				mission.id = "role_" + id + "_" + unit_id
				mission.status = "active"
				mission.destination = ""
				_state.add_mission(mission)
				unit.mission_id = mission.id
				delta.missions[mission.id] = mission.duplicate(true)
				delta.units[unit_id] = unit.duplicate(true)
			else:
				var input: Dictionary = _nearest_input(leaf, _coordination_inputs).duplicate(true)
				var cursor: String = leaf
				while not cursor.is_empty():
					input.release_time = maxf(float(input.release_time), float(_coordination_inputs.get(cursor, {}).get("release_time", 0.0)))
					cursor = str(_formations[cursor].get("parent", ""))
				_state.command_coordination[unit_id] = input
				delta.command_coordination[unit_id] = input.duplicate(true)
				if float(input.release_time) > _state.time:
					assert(_state.schedule_event("role_release_" + id + "_" + unit_id, float(input.release_time), "coordination_release", {"unit_id": unit_id}))
			_state.wake(str(unit.area_id))
	_accepted_ids[id] = true
	_next_input[_player_id] = _state.time + INPUT_SECONDS[rank]
	return {"ok": true, "state_delta": delta, "event": {"kind": "role_override", "time": _state.time,
		"id": id, "person_id": _player_id, "role": person.role, "layer": kind, "target": target,
		"affected_squads": affected.size()}, "next_input_at": _next_input[_player_id]}


func _nearest_input(leaf: String, inputs: Dictionary) -> Dictionary:
	var cursor: String = leaf
	while not cursor.is_empty():
		if inputs.has(cursor):
			return inputs[cursor]
		cursor = str(_formations[cursor].get("parent", ""))
	return {}


func report() -> Dictionary:
	if _state == null:
		return _reject("not_configured")
	var person: Dictionary = _people[_player_id]
	var owner: String = str(person.formation_id)
	var rank: int = ROLES.find(str(person.role))
	var result: Dictionary = {"person_id": _player_id, "role": person.role, "time": _state.time,
		"input_interval_seconds": INPUT_SECONDS[rank], "next_input_at": _next_input.get(_player_id, 0.0),
		"knowledge": "perfect experimental snapshot; no fog or communication latency"}
	if rank == 0:
		var unit: Dictionary = _state.units[_formations[owner].unit_id]
		result.personal_action = _personal_actions.get(_player_id, {"action": "AI_follow_squad", "offset_km": 0.0}).duplicate(true)
		result.personal_action.position = clampf(float(unit.position) + float(result.personal_action.offset_km), 0.0, float(_state.areas[unit.area_id].size_km))
		return result
	var targets: Array[String] = []
	if rank == 1:
		targets.append(owner)
	else:
		targets = State.sorted_ids(_children[owner])
	result.formations = {}
	for target: String in targets:
		var aggregate: Dictionary = {"squads": 0, "effective": 0.0, "casualties": 0.0, "ammunition": 0.0, "missions_complete": 0, "actions": {}}
		for leaf: String in State.sorted_ids(_leaves[target]):
			var unit: Dictionary = _state.units[_formations[leaf].unit_id]
			aggregate.squads += 1
			for key: String in ["effective", "casualties", "ammunition"]:
				aggregate[key] += float(unit[key])
			aggregate.missions_complete += int(_state.missions[unit.mission_id].status == "complete")
			aggregate.actions[unit.action] = int(aggregate.actions.get(unit.action, 0)) + 1
		result.formations[target] = aggregate
	return result


func command_scope() -> Dictionary:
	# Read-only selection metadata. apply() still validates every submitted command.
	if _state == null:
		return _reject("not_configured")
	var person: Dictionary = _people[_player_id]
	var owner: String = str(person.formation_id)
	var rank: int = ROLES.find(str(person.role))
	var targets: Dictionary = {}
	if rank == 0:
		targets.local_action = [_player_id]
	elif rank == 1:
		targets.tactical_intent = [owner]
	else:
		var eligible: Array[String] = []
		if rank >= 3 and not _leaves[owner].is_empty():
			eligible.append(owner)
		for child: String in State.sorted_ids(_children[owner]):
			if not _leaves[child].is_empty():
				eligible.append(child)
		targets.mission = eligible.duplicate()
		targets.coordination = eligible.duplicate()
	return {"person_id": _player_id, "role": person.role, "formation_id": owner,
		"targets": targets, "input_interval_seconds": INPUT_SECONDS[rank],
		"next_input_at": _next_input.get(_player_id, 0.0)}


func snapshot() -> Dictionary:
	return {"player_id": _player_id, "missions": _mission_inputs.duplicate(true),
		"coordination": _coordination_inputs.duplicate(true), "accepted_ids": _accepted_ids.duplicate(),
		"next_input": _next_input.duplicate(), "personal_actions": _personal_actions.duplicate(true)}


static func _keys(record: Dictionary, allowed: Array) -> bool:
	for key: Variant in record:
		if key not in allowed:
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}
