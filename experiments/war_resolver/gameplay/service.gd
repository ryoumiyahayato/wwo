extends RefCounted
## Opt-in goal facts over the shared kernel. This service never computes fire.
signal transition(record: Dictionary)
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Participants = preload("res://experiments/war_resolver/gameplay/participants.gd")
const VERSION: String = "land-gameplay-slice-v1"
const MAX_GOALS: int = 32
const MAX_HISTORY: int = 256
const SCOPE_LIMIT: int = 16
var _state: State
var _lod: RefCounted
var _space: RefCounted
var _known: Dictionary = {}
var _goals: Dictionary = {}
var _timers: Dictionary = {}
var _ready: Dictionary = {}
var _commit_ids: Array[String] = []
var _commit_index: int = 0
var _history_count: int = 0
var _record_index: int = 0
var participants: Participants = Participants.new()
var measure_cost: bool = false
var cost_usec: Dictionary = {"goal_delivery": 0, "goal_commit": 0}
var rules: Dictionary = {"radius_km": 0.03, "hold_seconds": 60.0,
	"deadline_seconds": 1200.0, "dependency_seconds": 300.0}
var work: Dictionary = {"goal_commits": 0, "goal_candidate_reads": 0,
	"goal_inputs": 0, "timers_processed": 0, "transitions": 0}

func configure(state: State, lod: RefCounted, space: RefCounted, known: Dictionary, policy: Dictionary = {}, covers: Dictionary = {}, personal_rules: Dictionary = {}) -> bool:
	if _state != null or state.time != 0.0 or state.gameplay_port != null or not lod.owns_state(state) or state.spatial_port == null or state.spatial_port.get_ref() != space:
		return false
	var configured: Dictionary = rules.duplicate()
	for key: String in policy:
		if not configured.has(key) or not _positive(policy[key]):
			return false
		configured[key] = float(policy[key])
	for actor: String in known:
		if state.structure_port == null or not state.structure_port.get_ref()._people.has(actor) or not known[actor] is Dictionary:
			return false
		for node: String in known[actor]:
			if not space._nodes.has(node) or not known[actor][node] is Array or known[actor][node].size() > 16:
				return false
	if not participants.configure(state, space, state.structure_port.get_ref(), covers, personal_rules):
		return false
	_state = state
	_lod = lod
	_space = space
	_known = known.duplicate(true)
	rules = configured
	state.gameplay_port = weakref(self)
	participants.transition.connect(_on_personal_transition)
	return true

func reset_work() -> void:
	for key: String in work:
		work[key] = 0

func requires_detail(id: String) -> bool:
	return _goals.has(id) or participants.has_unit(id)

func blocks_structure(kind: String, values: Dictionary) -> bool:
	if kind == "merge":
		return requires_detail(str(values.get("survivor", ""))) or requires_detail(str(values.get("donor", "")))
	if kind != "split":
		return false
	var source: String = str(values.get("source", ""))
	if requires_detail(source):
		return true
	var structure: RefCounted = _state.structure_port.get_ref()
	if structure._nodes.has(source):
		for id: String in _goals:
			if structure._contains(source, str(structure._unit_nodes.get(id, ""))):
				return true
		for id: String in participants._units.values():
			if structure._contains(source, str(structure._unit_nodes.get(id, ""))):
				return true
	return false

func _on_personal_transition(record: Dictionary) -> void:
	transition.emit(record)

func validate_batch(actor: String, ids: Array[String], values: Dictionary, input_id: String) -> Dictionary:
	var added: int = 0
	var projected: Dictionary = {}
	var selected_proxies: Dictionary = {}
	for id: String in ids:
		added += int(not _goals.has(id))
		if _state.missions.has("goal_" + input_id + "_" + id):
			return _reject("goal_identity_collision")
		var unit: Dictionary = _state.units[id] if _state.units.has(id) else _lod.preview_leaf(id)
		var valid: Dictionary = validate_goal(actor, unit, values)
		if not valid.ok:
			return valid
		var scope: String = str(_space._cell_scope.get(str(unit.area_id), unit.area_id))
		if not projected.has(scope):
			projected[scope] = _space.combat_ids(str(unit.area_id)).size()
		var representation: String = _lod.representation_of(id)
		if representation != id:
			if not selected_proxies.has(representation):
				selected_proxies[representation] = {"count": 0, "scope": scope}
			selected_proxies[representation].count += 1
	for representation: String in selected_proxies:
		var selection: Dictionary = selected_proxies[representation]
		projected[selection.scope] += int(selection.count) - int(int(selection.count) == _lod._groups[representation].leaf_refs.size())
	for count: int in projected.values():
		if count > SCOPE_LIMIT:
			return _reject("gameplay_scope_capacity_after_materialization")
	if _history_count + ids.size() > MAX_HISTORY or _goals.size() + added > MAX_GOALS:
		return _reject("gameplay_goal_capacity")
	if participants._actions.size() + ids.size() * Participants.MAX_PER_UNIT > Participants.MAX_ACTIONS:
		return _reject("personal_regroup_capacity")
	return {"ok": true}

func validate_goal(actor: String, unit: Dictionary, values: Dictionary) -> Dictionary:
	if values.size() != 4 or not _keys(values, ["intent", "target_node", "path", "return_to_start"]) or values.get("intent") not in ["hold", "advance", "withdraw", "cancel"] or not values.get("target_node") is String or not values.get("path") is Array or not values.get("return_to_start") is bool:
		return _reject("invalid_goal_intent")
	if _history_count >= MAX_HISTORY or not _goals.has(unit.id) and _goals.size() >= MAX_GOALS:
		return _reject("gameplay_goal_capacity")
	if not unit.has("spatial") or unit.has("contact_weight"):
		return _reject("goal_requires_detailed_spatial_leaf")
	if values.intent == "cancel":
		return {"ok": true} if values.target_node == "" and values.path.is_empty() and not values.return_to_start and _goals.has(unit.id) else _reject("invalid_goal_cancel")
	if not _known.get(actor, {}).has(values.target_node) or not _known[actor][values.target_node].has(values.path):
		return _reject("route_not_in_person_known_map")
	if values.path.is_empty():
		if str(unit.spatial.edge) != "" or str(unit.spatial.node) != str(values.target_node):
			return _reject("destination_requires_known_route")
	else:
		var valid: Dictionary = _space.validate_path(unit, values.path, values.return_to_start)
		if not valid.ok:
			return valid
		var node: String = str(unit.spatial.from) if values.return_to_start and str(unit.spatial.edge) != "" else str(unit.spatial.node)
		for edge_id: String in values.path:
			var edge: Dictionary = _space._edges[edge_id]
			node = str(edge.to) if node == edge.from else str(edge.from)
		if node != values.target_node:
			return _reject("route_does_not_reach_goal")
	if _space.combat_ids(str(unit.area_id)).size() > SCOPE_LIMIT:
		return _reject("gameplay_scope_capacity")
	return {"ok": true}

func admit_standing(unit_id: String, id: String, actor: String, values: Dictionary) -> Dictionary:
	if _state == null or _state.time != 0.0 or not _state.units.has(unit_id) or _goals.has(unit_id):
		return _reject("standing_goal_initial_only")
	var valid: Dictionary = validate_goal(actor, _state.units[unit_id], values)
	if not valid.ok:
		return valid
	return _assign(unit_id, id, actor, values)

func apply_goal(unit_id: String, id: String, actor: String, values: Dictionary) -> Dictionary:
	# Role preflights all leaves before entering this internal delivery method.
	if _state.information_port == null or _state.information_port.get_ref()._gate != "delivery" or _state.information_port.get_ref()._actor != actor:
		return _reject("communication_delivery_required")
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var result: Dictionary = _assign(unit_id, id, actor, values)
	if measure_cost:
		cost_usec.goal_delivery += Time.get_ticks_usec() - started
	return result

func _assign(unit_id: String, id: String, actor: String, values: Dictionary) -> Dictionary:
	var unit: Dictionary = _state.units[unit_id]
	var old: Dictionary = _state.missions[unit.mission_id]
	if values.intent == "cancel":
		_history_count += 1
		work.goal_inputs += 1
		_finish(unit, old, "cancelled", "explicit_cancel", id)
		unit.spatial.path.clear()
		return {"ok": true, "status": "CANCELLED"}
	if old.has("goal_v1") and old.status == "active":
		_finish(unit, old, "cancelled", "superseded", id)
	var mission: Dictionary = old.duplicate(true)
	mission.id = "goal_" + id + "_" + unit_id
	if _state.missions.has(mission.id):
		return _reject("goal_identity_collision")
	mission.status = "active"
	mission.posture = "withdraw" if values.intent == "withdraw" else "hold"
	mission.destination = ""
	mission.goal_v1 = {"version": VERSION, "unit_id": unit_id, "actor": actor, "input_ref": id,
		"intent": values.intent, "target_node": values.target_node, "radius_km": rules.radius_km,
		"hold_seconds": rules.hold_seconds, "started_at": _state.time,
		"deadline": _state.time + float(rules.deadline_seconds), "dependency_deadline": _state.time + float(rules.dependency_seconds),
		"route_complete": false, "local_condition": false, "held_since": -1.0,
		"effective_incoming_contact": false, "execution": "ADMITTED", "reason": "",
		"continuing_movement": false, "continuing_fire": false, "fire_reason": "",
		"standing_rule": "hold_and_fire"}
	_state.add_mission(mission)
	unit.mission_id = mission.id
	_goals[unit_id] = str(mission.id)
	unit.spatial.path = values.path.duplicate()
	unit.spatial.returning = values.return_to_start and str(unit.spatial.edge) != ""
	unit.spatial.retreating = false
	unit.spatial.blocked_edge = ""
	if not values.path.is_empty():
		participants.prepare_departure(unit_id, id)
	_state.tactical_intents.erase(unit_id)
	_history_count += 1
	work.goal_inputs += 1
	var assigned: Dictionary = _state.missions[mission.id]
	_schedule(unit_id, str(mission.id), "deadline", float(assigned.goal_v1.deadline))
	if not (_state.coordination.get(unit_id, {}).get("after", []) as Array).is_empty():
		_schedule(unit_id, str(mission.id), "dependency", float(assigned.goal_v1.dependency_deadline))
	_state.wake(str(unit.area_id))
	_emit(unit_id, "goal_admitted", id, {"mission_id": mission.id, "intent": values.intent, "target_node": values.target_node})
	_evaluate(unit_id)
	return {"ok": true, "status": "GOAL_ADMITTED", "mission_id": mission.id}

func _schedule(unit_id: String, mission_id: String, purpose: String, due: float) -> void:
	var id: String = "gameplay_" + mission_id + "_" + purpose
	if _timers.has(id):
		return
	assert(_timers.size() < MAX_HISTORY * 3)
	_timers[id] = {"id": id, "unit_id": unit_id, "mission_id": mission_id, "purpose": purpose, "due": due, "status": "PENDING"}
	assert(_state.schedule_event(id, due, "gameplay", {"timer_id": id, "unit_id": unit_id}))

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	if payload.has("action_id"):
		return participants.accepts_event(id, payload, due)
	return payload.size() == 2 and _timers.has(id) and payload.get("timer_id") == id and payload.get("unit_id") == _timers[id].unit_id and _timers[id].due == due and _timers[id].status == "PENDING"

func process_event(event: Dictionary) -> Dictionary:
	if not accepts_event(str(event.id), event.payload, float(event.time)) or event.time != _state.time:
		return {"changed": [], "retired": [], "record": _reject("invalid_gameplay_timer")}
	if event.payload.has("action_id"):
		return participants.process_event(event)
	var timer: Dictionary = _timers[event.id]
	timer.status = "PROCESSED"
	work.timers_processed += 1
	var id: String = str(timer.unit_id)
	if not _state.units.has(id) or _state.units[id].mission_id != timer.mission_id:
		return {"changed": [], "retired": [], "record": {"id": event.id, "status": "OBSOLETE", "time": _state.time}}
	_evaluate(id)
	_state.wake(str(_state.units[id].area_id))
	return {"changed": [id], "retired": [], "record": {"id": event.id, "status": "APPLIED", "time": _state.time, "purpose": timer.purpose}}

func posture(unit: Dictionary) -> String:
	var mission: Dictionary = _state.missions[unit.mission_id]
	var goal: Dictionary = mission.goal_v1
	if mission.status != "active":
		return "hold"
	for dependency: String in _state.coordination.get(unit.id, {}).get("after", []):
		if _state.missions[dependency].status != "complete":
			return "reserve" if _state.missions[dependency].status == "active" else "hold"
	if _state.time < float(_state.coordination.get(unit.id, {}).get("release_time", 0.0)) or _state.time < float(_state.command_coordination.get(unit.id, {}).get("release_time", 0.0)):
		return "reserve"
	if _state.tactical_intents.has(unit.id):
		return str(_state.tactical_intents[unit.id].posture)
	if _state.command_coordination.get(unit.id, {}).get("posture", "") == "hold":
		return "hold"
	if bool(goal.route_complete):
		return "hold"
	return "withdraw" if goal.intent == "withdraw" else "advance"

func note_unit(id: String) -> void:
	if _goals.has(id):
		_ready[id] = true

func begin_commit() -> void:
	_commit_ids = State.sorted_ids(_ready)
	_commit_index = 0

func commit_step() -> bool:
	if _commit_index < _commit_ids.size():
		var started: int = Time.get_ticks_usec() if measure_cost else 0
		_evaluate(_commit_ids[_commit_index])
		if measure_cost:
			cost_usec.goal_commit += Time.get_ticks_usec() - started
		_commit_index += 1
		return false
	_ready.clear()
	_commit_ids.clear()
	return true

func commit_all() -> void:
	begin_commit()
	while not commit_step():
		pass

func _evaluate(id: String) -> void:
	if not _state.units.has(id) or not _goals.has(id):
		return
	var unit: Dictionary = _state.units[id]
	var mission: Dictionary = _state.missions[unit.mission_id]
	if not mission.has("goal_v1"):
		return
	work.goal_commits += 1
	var goal: Dictionary = mission.goal_v1
	var previous: Dictionary = goal.duplicate(true)
	var here: Array = _space.xy(unit)
	var point: Array = _space._nodes[goal.target_node].xy
	var arrived: bool = str(unit.spatial.edge) == "" and (unit.spatial.path as Array).is_empty() and _distance(here, point) <= float(goal.radius_km)
	var own: bool = false
	var enemy: bool = false
	var incoming: bool = false
	var outgoing: bool = false
	for other_id: String in _space.combat_ids(str(unit.area_id)):
		work.goal_candidate_reads += 1
		var other: Dictionary = _state.units[other_id]
		if float(other.effective) <= 0.001:
			continue
		if _distance(_space.xy(other), point) <= float(goal.radius_km):
			if other.side == unit.side:
				own = true
			else:
				enemy = true
		if other.side != unit.side:
			incoming = incoming or _fire_capable(other) and _space.detection(other, unit) > 0.0
			outgoing = outgoing or _fire_capable(unit) and _space.detection(unit, other) > 0.0
	goal.route_complete = arrived
	goal.local_condition = arrived and own and not enemy
	goal.effective_incoming_contact = incoming
	goal.continuing_fire = outgoing
	goal.fire_reason = "ammunition_exhausted" if float(unit.ammunition) <= 0.0 else ("equipment_unavailable" if float(unit.get("serviceable_equipment", unit.equipment)) <= 0.0 else ("no_effective_target" if not outgoing else ""))
	goal.continuing_movement = mission.status == "active" and not arrived and unit.action in ["advance", "withdraw"] and _space.can_move(unit)
	goal.execution = "STOPPED" if mission.status != "active" else ("ARRIVED" if arrived else ("MOVING" if str(unit.spatial.edge) != "" else "WAITING"))
	goal.reason = "route_blocked" if str(unit.spatial.blocked_edge) != "" else ("fuel_exhausted" if unit.get("supply_capability", {}).get("fuel_dependent", false) and float(unit.get("fuel", 0.0)) <= 0.0 else ("suppression" if float(unit.suppression) >= float(mission.stop_suppression) else ""))
	if mission.status == "active":
		if float(unit.effective) <= 0.001:
			_finish(unit, mission, "failed", "unit_unavailable", str(goal.input_ref))
		for dependency: String in _state.coordination.get(id, {}).get("after", []):
			if _state.missions[dependency].status in ["failed", "cancelled"]:
				_finish(unit, mission, "failed", "dependency_failed", dependency)
			elif _state.missions[dependency].status != "complete" and _state.time >= float(goal.dependency_deadline):
				_finish(unit, mission, "failed", "dependency_timeout", dependency)
		if mission.status == "active" and goal.intent == "hold":
			if goal.local_condition and float(goal.held_since) < 0.0:
				goal.held_since = _state.time
				_schedule(id, str(mission.id), "hold", _state.time + float(goal.hold_seconds))
			elif not goal.local_condition and float(goal.held_since) >= 0.0:
				_finish(unit, mission, "failed", "hold_interrupted", str(goal.input_ref))
			if float(goal.held_since) >= 0.0 and _state.time - float(goal.held_since) >= float(goal.hold_seconds):
				_finish(unit, mission, "complete", "local_hold_satisfied", str(goal.input_ref))
		elif mission.status == "active" and arrived:
			_finish(unit, mission, "complete", "route_arrived", str(goal.input_ref))
		if mission.status == "active" and _state.time >= float(goal.deadline):
			_finish(unit, mission, "failed", "deadline_exceeded", str(goal.input_ref))
		if mission.status == "active" and unit.action == "withdrawn" and not arrived:
			_finish(unit, mission, "failed", "forced_withdrawal", str(goal.input_ref))
	if goal.route_complete != previous.route_complete or goal.local_condition != previous.local_condition or goal.effective_incoming_contact != previous.effective_incoming_contact or goal.continuing_fire != previous.continuing_fire or goal.continuing_movement != previous.continuing_movement or goal.fire_reason != previous.fire_reason or goal.execution != previous.execution or goal.reason != previous.reason:
		_emit(id, "goal_state_changed", str(goal.input_ref), {"before": previous, "after": goal.duplicate(true), "mission_status": mission.status})

func _finish(unit: Dictionary, mission: Dictionary, status: String, reason: String, cause: String) -> void:
	if mission.status != "active":
		return
	mission.status = status
	mission.goal_v1.execution = "STOPPED"
	mission.goal_v1.continuing_movement = false
	mission.goal_v1.terminal_reason = reason
	for dependent: String in State.sorted_ids(_state.mission_dependents.get(mission.id, {})):
		_state.wake(str(_state.examine_unit(dependent).area_id))
	_emit(str(unit.id), "goal_" + status, cause, {"mission_id": mission.id, "reason": reason, "standing_rule": "hold_and_fire"})

func _emit(unit_id: String, kind: String, cause: String, detail: Dictionary) -> void:
	_record_index += 1
	work.transitions += 1
	transition.emit({"event_id": "v1_%06d" % _record_index, "effective_time": _state.time,
		"phase": 20, "kind": kind, "subject_ref": unit_id, "cause_refs": [cause], "detail": detail.duplicate(true), "view": "DEBUG_TRUTH"})

func snapshot() -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	var goals: Dictionary = {}
	for id: String in State.sorted_ids(_goals):
		goals[id] = _state.missions[_goals[id]].duplicate(true)
	return {"ok": true, "version": VERSION, "goals": goals, "work": work.duplicate(), "history_count": _history_count, "timer_count": _timers.size(), "view": "DEBUG_TRUTH"}

func visible_fact(ids: Array[String], kind: String) -> Dictionary:
	if ids.size() != 1 or not _state.units[ids[0]].has("spatial"):
		return {}
	var unit: Dictionary = _state.units[ids[0]]
	if kind == "cover":
		return participants.cover_fact(unit)
	if kind == "objective":
		var mission: Dictionary = _state.missions[unit.mission_id]
		if not mission.has("goal_v1"):
			return {}
		return {"target_node": mission.goal_v1.target_node, "route_complete": mission.goal_v1.route_complete,
			"local_condition": mission.goal_v1.local_condition, "status": mission.status}
	if kind == "contact":
		var observed: Array[String] = []
		for other_id: String in _space.combat_ids(str(unit.area_id)):
			var other: Dictionary = _state.units[other_id]
			if other.side != unit.side and float(other.effective) > 0.001 and _space.observation(unit, other) > 0.0:
				observed.append(other_id)
		return {"observed_unit_refs": observed}
	return {}

static func _fire_capable(unit: Dictionary) -> bool:
	return unit.action not in ["idle", "reserve", "withdraw", "withdrawn", "disabled"] and float(unit.ammunition) > 0.0 and float(unit.effective) > 0.001 and float(unit.get("serviceable_equipment", unit.equipment)) > 0.0 and float(unit.readiness) > 0.0 and float(unit.cohesion) > 0.0 and float(unit.suppression) < 1.0

static func _distance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0])-float(b[0]), 2.0)+pow(float(a[1])-float(b[1]), 2.0))

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0

static func _keys(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if key not in allowed:
			return false
	return true

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
