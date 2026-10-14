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
var _lod_port: WeakRef = null
var _structure_port: WeakRef = null

func bind_structure(port: RefCounted) -> bool:
	if _state == null or _structure_port != null or not port.owns_state(_state) or not port.matches_admission(_formations, _people):
		return false
	_structure_port = weakref(port)
	return true

func _node(id: String) -> Dictionary:
	return _formations[id] if _structure_port == null else _structure_port.get_ref().node(id)

func _person(id: String) -> Dictionary:
	return _people[id] if _structure_port == null else _structure_port.get_ref().command_person(id)

func _parent(id: String) -> String:
	return str(_formations[id].get("parent", "")) if _structure_port == null else _structure_port.get_ref().parent(id)

func _scope_children(id: String) -> Dictionary:
	return _children[id] if _structure_port == null else _structure_port.get_ref().children(id)

func _scope_leaves(id: String) -> Dictionary:
	return _leaves[id] if _structure_port == null else _structure_port.get_ref().leaves(id)

func _active(id: String) -> bool:
	return _formations.has(id) if _structure_port == null else _structure_port.get_ref().active(id)

func _binding_current() -> bool:
	# A second, unbound legacy adapter cannot retain operational authority after
	# this BattleState adopts dynamic relations. It must bind the same authority.
	if _state.structure_port == null:
		return true
	return _structure_port != null and _structure_port.get_ref() != null and _structure_port.get_ref() == _state.structure_port.get_ref() and _lod_port != null and _lod_port.get_ref() != null and _lod_port.get_ref() == _state.materialization_port.get_ref()


func bind_lod(port: RefCounted) -> bool:
	if _state == null or _lod_port != null or not port.owns_state(_state):
		return false
	_lod_port = weakref(port)
	return true


func _unit(id: String) -> Dictionary:
	if _state.units.has(id):
		return _state.units[id]
	return _lod_port.get_ref().preview_leaf(id)


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


func apply(command: Dictionary, communication_owner: RefCounted = null, validate_only: bool = false) -> Dictionary:
	if _state == null:
		return _reject("not_configured")
	if not _binding_current():
		return _reject("current_structure_binding_required")
	if _state.information_port != null and not _state.information_port.get_ref().allows_role_delivery(self, communication_owner, validate_only):
		return _reject("communication_delivery_required")
	if not _keys(command, ["id", "kind", "target", "values"]) or not command.get("id") is String or str(command.id).is_empty() or not command.get("values") is Dictionary:
		return _reject("invalid_command")
	var id: String = str(command.id)
	if _accepted_ids.has(id):
		return _reject("duplicate_command")
	var person: Dictionary = _person(_player_id)
	if _state.gameplay_port != null and not _state.gameplay_port.get_ref().participants.can_intend(_player_id):
		return _reject("person_dead" if _state.gameplay_port.get_ref().participants.dead(_player_id) else "person_incapacitated_or_occupied")
	var rank: int = ROLES.find(str(person.role))
	var owner: String = str(person.formation_id)
	if not _active(owner):
		return _reject("position_retired")
	var kind: String = str(command.get("kind", ""))
	var target: String = str(command.get("target", ""))
	var values: Dictionary = command.values
	if kind == "local_action":
		var embodied: bool = _state.gameplay_port != null and _state.gameplay_port.get_ref().participants._units.has(_player_id)
		if (rank != 0 and not embodied) or target != _player_id:
			return _reject("wrong_owner_or_layer")
		if values.get("action", "") == "aid" and _state.gameplay_port != null:
			var care_check: Dictionary = _state.gameplay_port.get_ref().medical.validate(_player_id, values)
			if not care_check.ok:
				return care_check
		elif values.get("action", "") == "ammunition" and _state.gameplay_port != null:
			var ammo_check: Dictionary = _state.gameplay_port.get_ref().tactics.validate_ammunition(_player_id, str(_state.gameplay_port.get_ref().participants._units.get(_player_id, "")), values)
			if not ammo_check.ok:
				return ammo_check
		elif values.get("action", "") in ["relocate", "collect_remains", "place_remains", "rescue"] and _state.gameplay_port != null:
			var body_check: Dictionary = _state.gameplay_port.get_ref().participants.validate_extended(_player_id, values)
			if not body_check.ok:
				return body_check
		elif _state.gameplay_port != null and values.get("action", "") in _state.gameplay_port.get_ref().tactics.LOCAL_ACTIONS:
			var combat_check: Dictionary = _state.gameplay_port.get_ref().tactics.validate_person(_player_id, values)
			if not combat_check.ok:
				return combat_check
		elif not _keys(values, ["action"]) or not values.get("action", "") in ["wait", "take_cover", "step_forward", "step_back"]:
			return _reject("invalid_local_action")
		elif _state.gameplay_port != null:
			var local_check: Dictionary = _state.gameplay_port.get_ref().participants.validate_action(_player_id, str(values.action))
			if not local_check.ok:
				return local_check
	elif kind == "tactical_intent":
		if values.has("gun_action") and _state.gameplay_port != null:
			var gun: Dictionary = _state.gameplay_port.get_ref().tactics.guns.get(values.get("gun_ref", ""), {})
			if rank < 1 or not _active(target) or not _structure_port.get_ref()._contains(owner, target) or not _structure_port.get_ref()._contains(target, str(_structure_port.get_ref()._unit_nodes.get(gun.get("unit_ref", ""), ""))):
				return _reject("gun_support_requires_current_owned_scope")
			var gun_check: Dictionary = _state.gameplay_port.get_ref().tactics.validate_gun(_player_id, values)
			if not gun_check.ok:
				return gun_check
		elif rank != 1 or target != owner:
			return _reject("wrong_owner_or_layer")
		elif (values.has("fire_mode") or values.has("manoeuvre_action") or values.has("ammo_action") or values.has("rescue_order")) and _state.gameplay_port != null:
			var fire_check: Dictionary = _state.gameplay_port.get_ref().tactics.validate_squad(_player_id, str(_node(target).unit_id), values)
			if not fire_check.ok:
				return fire_check
		elif not _keys(values, ["posture"]) or not values.get("posture", "") in ["hold", "advance", "support"]:
			return _reject("invalid_tactical_intent")
		elif _state.gameplay_port != null and _state.gameplay_port.get_ref().tactics.manoeuvre_active(str(_node(target).unit_id)):
			return _reject("road_parts_keep_their_accepted_roles_until_stopped_and_regrouped")
	elif kind == "route_intent":
		if _state.spatial_port == null or not _active(target) or not (rank == 1 and target == owner or rank >= 2 and (target == owner and rank >= 3 or _scope_children(owner).has(target))):
			return _reject("wrong_owner_or_layer")
		if _scope_leaves(target).is_empty() or values.size() != 2 or not _keys(values, ["path", "return_to_start"]) or not values.get("path") is Array or not values.get("return_to_start") is bool:
			return _reject("invalid_route_intent")
		for leaf: String in State.sorted_ids(_scope_leaves(target)):
			if _state.gameplay_port != null and _state.gameplay_port.get_ref().tactics.manoeuvre_active(str(_node(leaf).unit_id)):
				return _reject("regroup_road_parts_before_replacing_unit_route")
			var route_check: Dictionary = _state.spatial_port.get_ref().validate_path(_unit(str(_node(leaf).unit_id)), values.path, values.return_to_start)
			if not route_check.ok:
				return route_check
	elif kind == "operation_intent":
		if _state.gameplay_port == null or not _active(target) or not (target == owner and rank >= 2 or _scope_children(owner).has(target) and rank >= 2):
			return _reject("purpose_requires_current_office_or_direct_child")
		var purpose_check: Dictionary = _state.gameplay_port.get_ref().operations.validate(_player_id, target, values, id)
		if not purpose_check.ok:
			return purpose_check
	elif kind == "land_intent":
		if _state.gameplay_port == null:
			return _reject("ground_transport_algorithm_required")
		var land_check: Dictionary = _state.gameplay_port.get_ref().land.validate(_player_id, target, values, id)
		if not land_check.ok:
			return land_check
	elif kind == "naval_intent":
		if _state.gameplay_port == null:
			return _reject("surface_algorithm_required")
		var naval_check: Dictionary = _state.gameplay_port.get_ref().sea.validate(_player_id, target, values, id)
		if not naval_check.ok:
			return naval_check
	elif kind == "air_intent":
		if _state.gameplay_port == null:
			return _reject("aviation_algorithm_required")
		var air_check: Dictionary = _state.gameplay_port.get_ref().air.validate(_player_id, target, values, id)
		if not air_check.ok:
			return air_check
	elif kind == "reserve_intent":
		if _state.gameplay_port == null:
			return _reject("wrong_layer")
		var reserve_check: Dictionary = _state.gameplay_port.get_ref().reserves.validate(_player_id, target, values, id)
		if not reserve_check.ok:
			return reserve_check
	elif kind == "goal_intent":
		if _state.gameplay_port == null:
			return _reject("wrong_layer")
		if not _active(target) or not (rank == 1 and target == owner or rank >= 2 and (target == owner and rank >= 3 or _scope_children(owner).has(target))):
			return _reject("wrong_owner_or_layer")
		if _scope_leaves(target).is_empty():
			return _reject("empty_scope")
	elif kind in ["mission", "coordination"]:
		# Higher rank does not inherit direct ownership of lower decision inputs.
		if rank < 2 or not _active(target) or not (target == owner and rank >= 3 or _scope_children(owner).has(target)):
			return _reject("wrong_owner_or_layer")
		if _scope_leaves(target).is_empty():
			return _reject("empty_scope")
		if kind == "mission":
			if not _keys(values, ["posture", "objective", "direction"]) or not values.get("posture", "") in POSTURES or not _number(values.get("objective")) or not _number(values.get("direction")) or absf(float(values.direction)) != 1.0:
				return _reject("invalid_mission")
			for leaf: String in State.sorted_ids(_scope_leaves(target)):
				var unit: Dictionary = _unit(str(_node(leaf).unit_id))
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
		affected = delivery_leaves(command)
	if kind == "goal_intent":
		var goal_units: Array[String] = []
		for leaf: String in affected:
			goal_units.append(str(_node(leaf).unit_id))
		var goal_check: Dictionary = _state.gameplay_port.get_ref().validate_batch(_player_id, goal_units, values, id)
		if not goal_check.ok:
			return goal_check
	# Preflight every resource ID before committing anything, including clocks/IDs.
	for leaf: String in affected:
		var unit_id: String = str(_node(leaf).unit_id)
		if _state.gameplay_port != null and kind in ["mission", "route_intent", "goal_intent"] and _state.gameplay_port.get_ref().tactics.movement_blocked(unit_id):
			var moves: bool = kind == "mission" and values.get("posture", "") in ["advance", "withdraw"] or not values.get("path", []).is_empty() or kind == "goal_intent" and values.get("intent", "") != "cancel" and values.get("target_node", "") != _unit(unit_id).spatial.node
			if moves:
				return _reject("deployed_gun_requires_actual_packing_before_movement")
		if _state.gameplay_port != null and _state.gameplay_port.get_ref().land._unit_jobs.has(unit_id):
			return _reject("occupied_ground_carrier_requires_its_transport_command")
		# Replacing a prerequisite needs explicit dependency migration semantics.
		# Reject the whole command rather than orphaning reserves on an old ID.
		if kind in ["mission", "route_intent"] and not (_state.mission_dependents.get(_unit(unit_id).mission_id, {}) as Dictionary).is_empty():
			return _reject("mission_has_dependents")
		if kind == "goal_intent" and not (_state.mission_dependents.get(_unit(unit_id).mission_id, {}) as Dictionary).is_empty() and not _state.missions[_unit(unit_id).mission_id].has("goal_v1"):
			return _reject("legacy_dependency_migration_required")
		if kind in ["mission", "route_intent"] and _state.missions[_unit(unit_id).mission_id].has("goal_v1"):
			return _reject("versioned_goal_intent_required")
		if kind == "mission" and _state.missions.has("role_" + id + "_" + unit_id):
			return _reject("mission_id_collision")
		if kind == "coordination" and _state.event_ids.has("role_release_" + id + "_" + unit_id):
			return _reject("event_id_collision")
	if validate_only:
		return {"ok": true}
	# Permission/value/ID/cooldown checks precede causal materialization.
	if _lod_port != null and kind != "local_action":
		for leaf: String in affected:
			_lod_port.get_ref().materialize_leaf(str(_node(leaf).unit_id), "subordinate_command")
	var delta: Dictionary = {"units": {}, "missions": {}, "tactical_intents": {}, "command_coordination": {}, "personal_actions": {}}
	var representation_change: Dictionary = {}
	if kind == "local_action":
		if _state.gameplay_port != null:
			var personal_result: Dictionary
			if values.action == "aid":
				personal_result = _state.gameplay_port.get_ref().medical.start(_player_id, id, values)
			elif values.action == "ammunition":
				personal_result = _state.gameplay_port.get_ref().tactics.ammunition_action(_player_id, str(_state.gameplay_port.get_ref().participants._units[_player_id]), id, values)
			elif values.action in ["relocate", "collect_remains", "place_remains", "rescue"]:
				personal_result = _state.gameplay_port.get_ref().participants.apply_extended(_player_id, id, values)
			elif values.action in _state.gameplay_port.get_ref().tactics.LOCAL_ACTIONS:
				personal_result = _state.gameplay_port.get_ref().tactics.personal(_player_id, id, values)
			else:
				personal_result = _state.gameplay_port.get_ref().participants.apply_action(_player_id, id, str(values.action))
			assert(personal_result.ok)
			delta.personal_actions[_player_id] = personal_result
			representation_change = {"changed": personal_result.get("changed", []), "retired": personal_result.get("retired", [])}
		else:
			var unit: Dictionary = _unit(str(_node(owner).unit_id))
			var personal: Dictionary = _personal_actions.get(_player_id, {"offset_km": 0.0}).duplicate(true)
			var step: float = 0.005 if values.action == "step_forward" else (-0.005 if values.action == "step_back" else 0.0)
			personal.offset_km = clampf(float(personal.offset_km) + step, -0.02, 0.02)
			personal.action = values.action
			personal.time = _state.time
			personal.position = clampf(float(unit.position) + float(personal.offset_km), 0.0, float(_state.areas[unit.area_id].size_km))
			_personal_actions[_player_id] = personal
			delta.personal_actions[_player_id] = personal.duplicate(true)
	elif kind == "tactical_intent":
		var unit_id: String = str(_state.gameplay_port.get_ref().tactics.guns[values.gun_ref].unit_ref) if values.has("gun_action") else str(_node(target).unit_id)
		if values.has("gun_action"):
			var result: Dictionary = _state.gameplay_port.get_ref().tactics.gun_action(_player_id, id, values)
			if not result.ok:
				return result
		elif values.has("fire_mode") or values.has("manoeuvre_action") or values.has("ammo_action") or values.has("rescue_order"):
			var result: Dictionary = _state.gameplay_port.get_ref().tactics.squad(_player_id, unit_id, id, values)
			if not result.ok:
				return result
		else:
			_state.tactical_intents[unit_id] = values.duplicate(true)
			delta.tactical_intents[unit_id] = values.duplicate(true)
		_state.wake(str(_state.units[unit_id].area_id))
	elif kind == "operation_intent":
		var purpose_result: Dictionary = _state.gameplay_port.get_ref().operations.apply(_player_id, target, values, id)
		if not purpose_result.ok:
			return purpose_result
		delta.merge(purpose_result.state_delta)
	elif kind == "land_intent":
		var land_result: Dictionary = _state.gameplay_port.get_ref().land.apply(_player_id, values, id)
		delta.merge(land_result.state_delta)
		for unit_id: String in land_result.changed:
			if _state.units.has(unit_id):
				delta.units[unit_id] = _state.units[unit_id].duplicate(true)
	elif kind == "naval_intent":
		var naval_result: Dictionary = _state.gameplay_port.get_ref().sea.apply(_player_id, values, id)
		if not naval_result.ok:
			return naval_result
		delta = naval_result.state_delta
	elif kind == "air_intent":
		delta = _state.gameplay_port.get_ref().air.apply(_player_id, values, id).state_delta
	elif kind == "reserve_intent":
		delta = _state.gameplay_port.get_ref().reserves.apply(_player_id, values, id)
	elif kind == "goal_intent":
		for leaf: String in affected:
			var unit_id: String = str(_node(leaf).unit_id)
			var result: Dictionary = _state.gameplay_port.get_ref().apply_goal(unit_id, id, _player_id, values)
			assert(result.ok)
			delta.units[unit_id] = _state.units[unit_id].duplicate(true)
			delta.missions[_state.units[unit_id].mission_id] = _state.missions[_state.units[unit_id].mission_id].duplicate(true)
	elif kind == "route_intent":
		for leaf: String in affected:
			var unit_id: String = str(_node(leaf).unit_id)
			var applied: Dictionary = _state.spatial_port.get_ref().set_path(unit_id, values.path, values.return_to_start, self, communication_owner)
			assert(applied.ok)
			delta.units[unit_id] = _state.units[unit_id].duplicate(true)
			var mission_id: String = str(_state.units[unit_id].mission_id)
			delta.missions[mission_id] = _state.missions[mission_id].duplicate(true)
	else:
		if kind == "mission":
			_mission_inputs[target] = values.duplicate(true)
		else:
			_coordination_inputs[target] = {"posture": values.posture, "release_time": _state.time + float(values.release_after)}
		for leaf: String in affected:
			var unit_id: String = str(_node(leaf).unit_id)
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
					cursor = _parent(cursor)
				_state.command_coordination[unit_id] = input
				delta.command_coordination[unit_id] = input.duplicate(true)
				if float(input.release_time) > _state.time:
					assert(_state.schedule_event("role_release_" + id + "_" + unit_id, float(input.release_time), "coordination_release", {"unit_id": unit_id}))
			_state.wake(str(unit.area_id))
	_accepted_ids[id] = true
	_next_input[_player_id] = _state.time + INPUT_SECONDS[rank]
	return {"ok": true, "state_delta": delta, "representation_change": representation_change, "event": {"kind": "role_override", "time": _state.time,
		"id": id, "person_id": _player_id, "role": person.role, "layer": kind, "target": target,
		"affected_squads": affected.size()}, "next_input_at": _next_input[_player_id]}

func delivery_leaves(command: Dictionary) -> Array[String]:
	if command.kind == "tactical_intent" and command.values.has("gun_ref") and _state.gameplay_port != null:
		var gun: Dictionary = _state.gameplay_port.get_ref().tactics.guns.get(command.values.gun_ref, {})
		var node: String = str(_structure_port.get_ref()._unit_nodes.get(gun.get("unit_ref", ""), ""))
		return [node] if node != "" else []
	if command.kind in ["air_intent", "naval_intent", "land_intent", "operation_intent"]:
		return []
	if command.kind != "reserve_intent":
		return State.sorted_ids(_scope_leaves(str(command.target)))
	var result: Array[String] = []
	for id: String in _state.gameplay_port.get_ref().reserves.units(command.values):
		result.append(str(_structure_port.get_ref()._unit_nodes[id]))
	return result


func _nearest_input(leaf: String, inputs: Dictionary) -> Dictionary:
	var cursor: String = leaf
	while not cursor.is_empty():
		if inputs.has(cursor):
			return inputs[cursor]
		cursor = _parent(cursor)
	return {}


func report() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state != null and _state.information_port != null:
		return _state.information_port.get_ref().role_report(self)
	if _state == null:
		return _reject("not_configured")
	if not _binding_current():
		return _reject("current_structure_binding_required")
	var person: Dictionary = _person(_player_id)
	var owner: String = str(person.formation_id)
	if not _active(owner):
		return _reject("position_retired")
	var rank: int = ROLES.find(str(person.role))
	var result: Dictionary = {"person_id": _player_id, "role": person.role, "time": _state.time,
		"input_interval_seconds": INPUT_SECONDS[rank], "next_input_at": _next_input.get(_player_id, 0.0),
		"knowledge": "perfect experimental snapshot; no fog or communication latency"}
	if _lod_port != null:
		result.distribution = "macro current; suspended leaf values are unresolved proportional projections, not individual history"
	if rank == 0:
		var unit: Dictionary = _unit(str(_node(owner).unit_id))
		result.personal_action = _personal_actions.get(_player_id, {"action": "AI_follow_squad", "offset_km": 0.0}).duplicate(true)
		result.personal_action.position = clampf(float(unit.position) + float(result.personal_action.offset_km), 0.0, float(_state.areas[unit.area_id].size_km))
		return result
	var targets: Array[String] = []
	if rank == 1:
		targets.append(owner)
	else:
		targets = State.sorted_ids(_scope_children(owner))
	result.formations = {}
	for target: String in targets:
		var aggregate: Dictionary = {"squads": 0, "effective": 0.0, "casualties": 0.0, "ammunition": 0.0, "missions_complete": 0, "actions": {}}
		for leaf: String in State.sorted_ids(_scope_leaves(target)):
			var unit: Dictionary = _unit(str(_node(leaf).unit_id))
			aggregate.squads += 1
			for key: String in ["effective", "casualties", "ammunition"]:
				aggregate[key] += float(unit[key])
			aggregate.missions_complete += int(_state.missions[unit.mission_id].status == "complete")
			aggregate.actions[unit.action] = int(aggregate.actions.get(unit.action, 0)) + 1
		result.formations[target] = aggregate
	return result


func command_scope() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	# Read-only selection metadata. apply() still validates every submitted command.
	if _state == null:
		return _reject("not_configured")
	if not _binding_current():
		return _reject("current_structure_binding_required")
	var person: Dictionary = _person(_player_id)
	var owner: String = str(person.formation_id)
	if not _active(owner):
		return _reject("position_retired")
	var rank: int = ROLES.find(str(person.role))
	var targets: Dictionary = {}
	if rank == 0:
		targets.local_action = [_player_id]
	elif rank == 1:
		targets.tactical_intent = [owner]
		if _state.gameplay_port != null:
			targets.goal_intent = [owner]
	else:
		var eligible: Array[String] = []
		if rank >= 3 and not _scope_leaves(owner).is_empty():
			eligible.append(owner)
		for child: String in State.sorted_ids(_scope_children(owner)):
			if not _scope_leaves(child).is_empty():
				eligible.append(child)
		targets.mission = eligible.duplicate()
		targets.coordination = eligible.duplicate()
		if _state.gameplay_port != null:
			targets.tactical_intent = eligible.duplicate()
			targets.goal_intent = eligible.duplicate()
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

const RUNTIME_FIELDS: Array[String] = ["_formations", "_people", "_children", "_leaves", "_mission_inputs", "_coordination_inputs", "_accepted_ids", "_next_input", "_player_id", "_personal_actions"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)

func bind_runtime(state: State, lod: RefCounted, structure: RefCounted) -> void:
	_state = state
	_lod_port = weakref(lod)
	_structure_port = weakref(structure)
