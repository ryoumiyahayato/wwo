extends RefCounted
## Opt-in goal facts over the shared kernel. This service never computes fire.
signal transition(record: Dictionary)
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Participants = preload("res://experiments/war_resolver/gameplay/participants.gd")
const Prerequisites = preload("res://experiments/war_resolver/gameplay/prerequisites.gd")
const FocusContinuity = preload("res://experiments/war_resolver/gameplay/focus_continuity.gd")
const Reserves = preload("res://experiments/war_resolver/gameplay/reserves.gd")
const Medical = preload("res://experiments/war_resolver/gameplay/medical.gd")
const Air = preload("res://experiments/war_resolver/gameplay/air_operations.gd")
const Sea = preload("res://experiments/war_resolver/gameplay/sea_operations.gd")
const Land = preload("res://experiments/war_resolver/gameplay/land_transport.gd")
const Operations = preload("res://experiments/war_resolver/gameplay/operations.gd")
const Tactics = preload("res://experiments/war_resolver/gameplay/tactical_actions.gd")
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
var _mission_timers: Dictionary = {}
var _ready: Dictionary = {}
var _commit_ids: Array[String] = []
var _commit_index: int = 0
var _history_count: int = 0
var _record_index: int = 0
var _representation_serial: int = 0
var participants: Participants = Participants.new()
var prerequisites: Prerequisites = Prerequisites.new()
var focus_continuity: FocusContinuity = FocusContinuity.new()
var reserves: Reserves = Reserves.new()
var medical: Medical = Medical.new()
var air: Air = Air.new()
var sea: Sea = Sea.new()
var land: Land = Land.new()
var operations: Operations = Operations.new()
var tactics: Tactics = Tactics.new()
var measure_cost: bool = false
var summary_goals: bool = false
var focused_person: String = ""
var cost_usec: Dictionary = {"goal_delivery": 0, "goal_commit": 0}
var rules: Dictionary = {"radius_km": 0.03, "hold_seconds": 60.0,
	"deadline_seconds": 1200.0, "dependency_seconds": 300.0}
var work: Dictionary = {"goal_commits": 0, "goal_candidate_reads": 0,
	"goal_inputs": 0, "timers_processed": 0, "transitions": 0}

const RUNTIME_FIELDS: Array[String] = ["_known", "_goals", "_timers", "_mission_timers", "_ready", "_commit_ids", "_commit_index", "_history_count", "_record_index", "_representation_serial", "summary_goals", "focused_person", "rules", "work"]

func runtime_modules() -> Dictionary:
	return {"participants": participants, "prerequisites": prerequisites, "focus": focus_continuity, "medical": medical,
		"air": air, "air_support": air.support, "air_defense": air.defense, "air_recovery": air.recovery,
		"sea": sea, "sea_support": sea.support, "sea_freight": sea.freight, "sea_recovery": sea.recovery,
		"land": land, "operations": operations, "tactics": tactics}

func runtime_state() -> Dictionary:
	if _state.settlement_pending:
		return _state.pending_view()
	var result: Dictionary = {"fields": State.capture_runtime_fields(self, RUNTIME_FIELDS), "modules": {}}
	for id: String in runtime_modules():
		result.modules[id] = runtime_modules()[id].runtime_state()
	return result

func restore_runtime(state: State, lod: RefCounted, space: RefCounted, image: Dictionary) -> bool:
	if not image.get("fields") is Dictionary or not image.get("modules") is Dictionary or image.modules.size() != runtime_modules().size() or not State.restore_runtime_fields(self, image.fields, RUNTIME_FIELDS):
		return false
	for id: String in runtime_modules():
		if not image.modules.get(id) is Dictionary or not runtime_modules()[id].restore_runtime(image.modules[id]):
			return false
	_state = state
	_lod = lod
	_space = space
	state.gameplay_port = weakref(self)
	if not participants.bind_runtime(state, space, state.structure_port.get_ref()):
		return false
	for site: Dictionary in space._local_sites.values():
		if site.has("cover_ref"):
			var cover: Dictionary = participants._covers.get(site.cover_ref, {})
			if cover.is_empty() or cover.node != site.node_ref or _distance(cover.xy, site.xy) > 0.000001:
				return false
	prerequisites.configure(self)
	focus_continuity.configure(self)
	reserves.configure(self)
	medical.configure(self)
	air.configure(self)
	sea.configure(self)
	land.configure(self)
	operations.configure(self)
	tactics.configure(self)
	space.route_feedback.connect(prerequisites.on_route)
	participants.transition.connect(_on_personal_transition)
	var stocks: Dictionary = state.logistics_port.get_ref()._assets
	for asset: Dictionary in air.assets.values() + sea.vessels.values():
		if not stocks.has(asset.id) or asset.stock != stocks[asset.id]:
			return false
		asset.stock = stocks[asset.id] # Restore the original Task6 alias, never a mirror.
	return tactics.validate_runtime()

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
	prerequisites.configure(self)
	focus_continuity.configure(self)
	reserves.configure(self)
	medical.configure(self)
	air.configure(self)
	sea.configure(self)
	land.configure(self)
	operations.configure(self)
	tactics.configure(self)
	space.route_feedback.connect(prerequisites.on_route)
	participants.transition.connect(_on_personal_transition)
	return true

func reset_work() -> void:
	for key: String in work:
		work[key] = 0

func admit_local_routes(actor: String, routes: Dictionary) -> bool:
	# Initial declared personal map knowledge, in the same known-route authority.
	if _state.time != 0.0 or not _state.structure_port.get_ref()._people.has(actor) or routes.size() > 16:
		return false
	for destination: String in routes:
		if _space.local_endpoint(destination).is_empty() or not routes[destination] is Array or routes[destination].size() > 8:
			return false
		for path: Variant in routes[destination]:
			if not path is Array or path.is_empty() or path.size() > 4 or not _space._local_edges.has(path[0]):
				return false
			var first: Dictionary = _space._local_edges[path[0]]
			if _space.local_path_end(str(first.from), path) != destination and _space.local_path_end(str(first.to), path) != destination:
				return false
	if not _known.has(actor):
		_known[actor] = {}
	for destination: String in routes:
		_known[actor]["local:" + destination] = routes[destination].duplicate(true)
	return true

func known_local_places(actor: String) -> Array:
	var refs: Dictionary = {}
	for key: String in _known.get(actor, {}):
		if not key.begins_with("local:"):
			continue
		for path: Array in _known[actor][key]:
			for edge_id: String in path:
				var edge: Dictionary = _space._local_edges[edge_id]
				refs[edge.from] = true
				refs[edge.to] = true
	var result: Array = []
	for ref: String in State.sorted_ids(refs):
		var site: Dictionary = _space.local_endpoint(ref)
		result.append({"site_ref": ref, "node_ref": site.node_ref, "xy": site.xy.duplicate()})
	return result # Map knowledge carries no current damage or enemy presence.

func requires_detail(id: String) -> bool:
	if tactics.requires_detail(id) or operations.occupied_ground(id) or air.recovery._unit_jobs.has(id) or land._unit_jobs.has(id):
		return true
	if not focused_person.is_empty():
		var structure: RefCounted = _state.structure_port.get_ref()
		var owner: String = str(structure._people[focused_person].formation_id)
		if structure._nodes[owner].get("unit_id", "") == id:
			return true
	if not focused_person.is_empty() and participants._units.get(focused_person, "") == id:
		return true
	return participants.requires_detail(id) or _goals.has(id) and not can_summarize_goal(id)

func can_summarize_goal(id: String) -> bool:
	if tactics.requires_detail(id) or operations.occupied_ground(id) or not summary_goals or not _goals.has(id) or participants.requires_detail(id) or not _lod.has_leaf(id):
		return false
	var unit: Dictionary = _state.units[id] if _state.units.has(id) else _lod.preview_leaf(id)
	var mission: Dictionary = _state.missions[_goals[id]]
	if unit.mission_id != mission.id or not unit.has("spatial") or not mission.has("goal_v1") or unit.action in ["withdrawn", "disabled"]:
		return false
	var goal: Dictionary = mission.goal_v1
	if _state.coordination.get(id, {}).get("retained", false):
		return false
	if goal.get("dependency_state", "READY") != "READY" or goal.effective_incoming_contact or goal.continuing_fire or not str(unit.spatial.blocked_edge).is_empty():
		return false
	if str(unit.spatial.edge).is_empty() and unit.spatial.path.is_empty():
		return goal.intent == "hold" and goal.route_complete and unit.spatial.node == goal.target_node
	return mission.status == "active" and goal.intent in ["advance", "withdraw"] and _space.can_move(unit) and posture(unit) == goal.intent

func summary_posture(unit: Dictionary) -> String:
	var refs: Dictionary = _lod._groups[unit.id].get("goal_refs", {})
	if refs.is_empty():
		return "hold"
	var mission: Dictionary = _state.missions[refs[State.sorted_ids(refs)[0]]]
	if mission.status != "active" or mission.goal_v1.route_complete:
		return "hold"
	return "withdraw" if mission.goal_v1.intent == "withdraw" else "advance"

func on_route_fact(edge_id: String, nodes: Array[String]) -> void:
	participants.interrupt_edge(edge_id)
	var candidates: Dictionary = {}
	for node: String in nodes:
		for id: String in _space.combat_ids(str(_space._nodes[node].cell)):
			candidates[id] = true
	for id: String in candidates:
		if not _lod._groups.has(id):
			continue
		var route: Dictionary = _state.units[id].get("spatial", {})
		if route.get("edge", "") != edge_id and edge_id not in route.get("path", []):
			continue
		for leaf: String in _lod._groups[id].get("goal_refs", {}):
			if _goals.has(leaf):
				_schedule(leaf, str(_goals[leaf]), "representation", _state.time + 0.000001)

func blocks_structure(kind: String, values: Dictionary) -> bool:
	if kind == "merge":
		return participants.has_members(str(values.get("survivor", ""))) or participants.has_members(str(values.get("donor", ""))) or requires_detail(str(values.get("survivor", ""))) or requires_detail(str(values.get("donor", "")))
	if kind != "split":
		return false
	var source: String = str(values.get("source", ""))
	if participants.has_members(source) or requires_detail(source):
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
	_state.structure_port.get_ref().on_personal_transition(record)
	_state.structure_port.get_ref().movements.on_personal_transition(record)
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
	if tactics.manoeuvre_active(str(unit.id)) and values.get("intent", "") != "cancel":
		return _reject("regroup_existing_road_parts_before_new_ground_task")
	if land._unit_jobs.has(unit.id):
		return _reject("finish_or_redirect_actual_land_duty_before_reassigning_carrier")
	if air.recovery._unit_jobs.has(unit.id):
		return _reject("cancel_local_air_recovery_before_reassigning_its_crew")
	if values.size() < 4 or values.size() > 6 or not _keys(values, ["intent", "target_node", "path", "return_to_start", "dependencies", "resume"]) or values.get("intent") not in ["hold", "advance", "withdraw", "cancel"] or not values.get("target_node") is String or not values.get("path") is Array or not values.get("return_to_start") is bool or not values.get("resume", false) is bool:
		return _reject("invalid_goal_intent")
	if _history_count >= MAX_HISTORY or not _goals.has(unit.id) and _goals.size() >= MAX_GOALS:
		return _reject("gameplay_goal_capacity")
	if not unit.has("spatial") or unit.has("contact_weight"):
		return _reject("goal_requires_detailed_spatial_leaf")
	if values.intent == "cancel":
		return {"ok": true} if values.size() == 4 and values.target_node == "" and values.path.is_empty() and not values.return_to_start and _goals.has(unit.id) else _reject("invalid_goal_cancel")
	var dependencies: Dictionary = prerequisites.validate(actor, unit, values.get("dependencies", []))
	if not dependencies.ok:
		return dependencies
	if values.get("resume", false):
		if not _goals.has(unit.id) or _state.missions[_goals[unit.id]].status != "active" or values.has("dependencies"):
			return _reject("active_existing_task_route_resume_required")
		var original: Dictionary = _state.missions[_goals[unit.id]].goal_v1
		if original.intent != values.intent or original.target_node != values.target_node:
			return _reject("resume_keeps_task_identity_and_destination")
	if not _known.get(actor, {}).has(values.target_node) or not _known[actor][values.target_node].has(values.path):
		return _reject("route_not_in_person_known_map")
	if values.path.is_empty():
		if str(unit.spatial.edge) != "":
			if not values.return_to_start or str(unit.spatial.from) != values.target_node:
				return _reject("empty_return_must_reach_actual_leg_origin")
		elif str(unit.spatial.node) != str(values.target_node):
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

func transfer_goal(source: String, destination: String) -> void:
	# Structural ownership changes no goal identity, issuer, progress or deadline.
	if not _goals.has(source):
		return
	var mission_id: String = str(_goals[source])
	_goals.erase(source)
	_goals[destination] = mission_id
	_ready.erase(source)
	_state.units[destination].mission_id = mission_id
	_state.missions[mission_id].goal_v1.unit_id = destination
	if _state.coordination.has(source):
		var assignment: Dictionary = _state.coordination[source]
		_state.coordination.erase(source)
		_state.coordination[destination] = assignment
		for dependency: String in assignment.get("after", []):
			_state.mission_dependents[dependency].erase(source)
			_state.mission_dependents[dependency][destination] = true
	for id: String in _mission_timers.get(mission_id, []):
		var timer: Dictionary = _timers[id]
		timer.event_unit_id = timer.get("event_unit_id", timer.unit_id)
		timer.unit_id = destination

func cancel_structural_goal(unit_id: String, cause: String) -> void:
	if not _goals.has(unit_id):
		return
	var mission: Dictionary = _state.missions[_goals[unit_id]]
	_finish(_state.units[unit_id], mission, "cancelled", "explicit_structure_choice", cause)
	_goals.erase(unit_id)
	_ready.erase(unit_id)
	_clear_coordination(unit_id)

func can_transfer_dependencies(unit_id: String) -> bool:
	if not _goals.has(unit_id):
		return false
	var assignment: Dictionary = _state.coordination.get(unit_id, {})
	return _keys(assignment, ["after", "release_time", "role", "status"]) and float(assignment.get("release_time", 0.0)) <= _state.time

func on_dependency_completed(mission_id: String) -> void:
	var waiters: Dictionary = {}
	for unit_id: String in _state.mission_dependents.get(mission_id, {}):
		if _goals.has(unit_id):
			waiters[_goals[unit_id]] = true
	prerequisites.notify(waiters)

func on_unit_unavailable(unit_id: String) -> void:
	var s: RefCounted = _state.structure_port.get_ref()
	var units: Array[String] = [unit_id]
	if _lod._groups.has(unit_id):
		units.clear()
		for leaf: String in _lod._groups[unit_id].leaf_refs:
			units.append(leaf)
	for leaf: String in units:
		prerequisites.on_retired(leaf)
		var node_id: String = str(s._unit_nodes.get(leaf, ""))
		if not node_id.is_empty():
			s.vacate_node(node_id, "unit_incapacitated", "unit_" + leaf + "_%.6f" % _state.time)

func _clear_coordination(unit_id: String) -> void:
	for dependency: String in _state.coordination.get(unit_id, {}).get("after", []):
		_state.mission_dependents[dependency].erase(unit_id)
	_state.coordination.erase(unit_id)

func on_goal_executor_changed(unit_id: String, cause: String) -> void:
	if _goals.has(unit_id):
		_emit(unit_id, "goal_executor_changed", cause, {"mission_id": _goals[unit_id]})

func assign_structural_task(unit_id: String, id: String, actor: String, task: Dictionary) -> void:
	# The structure event preflights the same known-map goal rules before mutation.
	_assign(unit_id, id, actor, task)

func _assign(unit_id: String, id: String, actor: String, values: Dictionary) -> Dictionary:
	var unit: Dictionary = _state.units[unit_id]
	var old: Dictionary = _state.missions[unit.mission_id]
	if values.get("resume", false):
		unit.spatial.path = values.path.duplicate()
		unit.spatial.returning = values.return_to_start and str(unit.spatial.edge) != ""
		unit.spatial.retreating = false
		unit.spatial.blocked_edge = ""
		old.goal_v1.latest_route_input = id
		for dependency: Dictionary in old.goal_v1.get("dependencies", []):
			if dependency.kind == "new_route":
				dependency.satisfied = true
		participants.prepare_departure(unit_id, id)
		_history_count += 1
		work.goal_inputs += 1
		_evaluate(unit_id)
		_state.wake(str(unit.area_id))
		_emit(unit_id, "goal_route_resumed", id, {"mission_id": old.id})
		return {"ok": true, "status": "TASK_ROUTE_UPDATED", "mission_id": old.id}
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
	mission.goal_v1.dependencies = values.get("dependencies", []).duplicate(true)
	mission.goal_v1.dependency_state = "WAITING" if not mission.goal_v1.dependencies.is_empty() else "READY"
	_state.add_mission(mission)
	unit.mission_id = mission.id
	_goals[unit_id] = str(mission.id)
	unit.spatial.path = values.path.duplicate()
	unit.spatial.returning = values.return_to_start and str(unit.spatial.edge) != ""
	unit.spatial.retreating = false
	unit.spatial.blocked_edge = ""
	if not values.path.is_empty() or unit.spatial.returning:
		participants.prepare_departure(unit_id, id)
	_state.tactical_intents.erase(unit_id)
	_history_count += 1
	work.goal_inputs += 1
	var assigned: Dictionary = _state.missions[mission.id]
	prerequisites.register(assigned)
	_schedule(unit_id, str(mission.id), "deadline", float(assigned.goal_v1.deadline))
	if not assigned.goal_v1.dependencies.is_empty() or not (_state.coordination.get(unit_id, {}).get("after", []) as Array).is_empty():
		_schedule(unit_id, str(mission.id), "dependency", float(assigned.goal_v1.dependency_deadline))
	_state.wake(str(unit.area_id))
	_emit(unit_id, "goal_admitted", id, {"mission_id": mission.id, "intent": values.intent, "target_node": values.target_node})
	_evaluate(unit_id)
	return {"ok": true, "status": "GOAL_ADMITTED", "mission_id": mission.id}

func _schedule(unit_id: String, mission_id: String, purpose: String, due: float) -> void:
	var id: String = "gameplay_" + mission_id + "_" + purpose
	if purpose == "representation":
		var previous: String = str(_state.missions[mission_id].goal_v1.get("representation_ticket", ""))
		if _timers.has(previous) and _timers[previous].status == "PENDING":
			return
		_representation_serial += 1
		id += "_%d" % _representation_serial
		_state.missions[mission_id].goal_v1.representation_ticket = id
	if _timers.has(id):
		return
	assert(_timers.size() < MAX_HISTORY * 8)
	_timers[id] = {"id": id, "unit_id": unit_id, "event_unit_id": unit_id, "mission_id": mission_id, "purpose": purpose, "due": due, "status": "PENDING"}
	if not _mission_timers.has(mission_id):
		_mission_timers[mission_id] = []
	_mission_timers[mission_id].append(id)
	assert(_state.schedule_event(id, due, "gameplay", {"timer_id": id, "unit_id": unit_id}))

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	if payload.has("tactical_ref"):
		return tactics.accepts(id, payload, due)
	if payload.has("operation_work"):
		return operations.accepts_work(id, payload, due)
	if payload.has("land_id"):
		return land.accepts_event(id, payload, due)
	if payload.has("sea_id"):
		return sea.accepts_event(id, payload, due)
	if payload.has("air_id"):
		return air.accepts_event(id, payload, due)
	if payload.has("care_id"):
		return medical.accepts_event(id, payload, due)
	if payload.has("focus_id"):
		return focus_continuity.accepts_event(id, payload, due)
	if payload.has("action_id") or payload.has("person_id"):
		return participants.accepts_event(id, payload, due)
	return payload.size() == 2 and _timers.has(id) and payload.get("timer_id") == id and payload.get("unit_id") == _timers[id].get("event_unit_id", _timers[id].unit_id) and _timers[id].due == due and _timers[id].status == "PENDING"

func process_event(event: Dictionary) -> Dictionary:
	if not accepts_event(str(event.id), event.payload, float(event.time)) or event.time != _state.time:
		return {"changed": [], "retired": [], "record": _reject("invalid_gameplay_timer")}
	if event.payload.has("tactical_ref"):
		return tactics.process(event)
	if event.payload.has("operation_work"):
		return operations.process_work(event)
	if event.payload.has("land_id"):
		return land.process_event(event)
	if event.payload.has("sea_id"):
		return sea.process_event(event)
	if event.payload.has("air_id"):
		return air.process_event(event)
	if event.payload.has("care_id"):
		return medical.process_event(event)
	if event.payload.has("focus_id"):
		return focus_continuity.process_event(event)
	if event.payload.has("action_id") or event.payload.has("person_id"):
		return participants.process_event(event)
	var timer: Dictionary = _timers[event.id]
	if str(timer.purpose).begins_with("prerequisite_"):
		prerequisites.processed(str(timer.mission_id))
	timer.status = "PROCESSED"
	work.timers_processed += 1
	var id: String = str(timer.unit_id)
	if not _lod.has_leaf(id) or _goals.get(id, "") != timer.mission_id:
		return {"changed": [], "retired": [], "record": {"id": event.id, "status": "OBSOLETE", "time": _state.time}}
	var current: Dictionary = _state.units[id] if _state.units.has(id) else _lod.preview_leaf(id)
	if current.mission_id != timer.mission_id:
		return {"changed": [], "retired": [], "record": {"id": event.id, "status": "OBSOLETE", "time": _state.time}}
	if timer.purpose == "representation":
		var materialized: Dictionary = _lod.materialize_leaf(id, "goal_physical_policy_changed")
		return {"changed": materialized.get("changed", [id]), "retired": materialized.get("retired", []),
			"record": {"id": event.id, "status": "GOAL_LEAF_DETAILED", "time": _state.time}}
	_evaluate(id)
	var representation: String = _lod.representation_of(id)
	_state.wake(str(_state.units[representation].area_id))
	return {"changed": [representation], "retired": [], "record": {"id": event.id, "status": "APPLIED", "time": _state.time, "purpose": timer.purpose}}

func posture(unit: Dictionary) -> String:
	if operations._work_units.get(unit.id, {}).get("kind", "") in ["ENGINEERING", "POSITION"]:
		return "reserve"
	if _state.coordination.get(unit.id, {}).get("retained", false):
		return "reserve"
	if _space.stationary_local(unit):
		return "hold"
	var mission: Dictionary = _state.missions[unit.mission_id]
	if mission.get("summary_goal_policy", false):
		return summary_posture(unit)
	var goal: Dictionary = mission.goal_v1
	if mission.status != "active":
		return "hold"
	if goal.get("dependency_state", "READY") != "READY":
		return "reserve"
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
	tactics.on_unit(id)
	operations.on_unit(id)
	land.on_unit(id)
	air.recovery.on_unit(id)
	if _goals.has(id):
		_ready[id] = true
	elif _lod._groups.has(id):
		for leaf: String in _lod._groups[id].get("goal_refs", {}):
			_ready[leaf] = true

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
	if not _lod.has_leaf(id) or not _goals.has(id):
		return
	var unit: Dictionary = _state.units[id] if _state.units.has(id) else _lod.preview_leaf(id)
	var mission: Dictionary = _state.missions[_goals[id]]
	if unit.mission_id != mission.id or not mission.has("goal_v1"):
		return
	work.goal_commits += 1
	var goal: Dictionary = mission.goal_v1
	var previous: Dictionary = goal.duplicate(true)
	var prerequisite: Dictionary = prerequisites.status(unit, mission)
	if _state.coordination.get(id, {}).get("retained", false):
		prerequisite = {"state": "WAITING", "reason": "waiting_reserve_release"}
	if prerequisite.state == "READY":
		for dependency: String in _state.coordination.get(id, {}).get("after", []):
			if _state.missions[dependency].status in ["failed", "cancelled"]:
				prerequisite = {"state": "IMPOSSIBLE", "reason": "dependency_failed"}
				break
			if _state.missions[dependency].status != "complete":
				prerequisite = {"state": "WAITING", "reason": "waiting_support_complete"}
				break
	goal.dependency_state = prerequisite.state
	if mission.status == "active" and prerequisite.state != "READY":
		goal.execution = "WAITING"
		goal.reason = prerequisite.reason
		goal.continuing_movement = false
		if float(unit.effective) <= 0.001:
			_finish(unit, mission, "failed", "unit_unavailable", str(goal.input_ref))
		elif prerequisite.state == "IMPOSSIBLE":
			_finish(unit, mission, "failed", str(prerequisite.reason), str(goal.input_ref))
		elif _state.time >= float(goal.dependency_deadline):
			_finish(unit, mission, "failed", "common_dependency_timeout", str(goal.input_ref))
		if previous.execution != goal.execution or previous.reason != goal.reason:
			_emit(id, "goal_waiting_changed", str(goal.input_ref), {"mission_id": mission.id, "reason": goal.reason})
		return
	var here: Array = _space.xy(unit)
	var point: Array = _space._nodes[goal.target_node].xy
	var arrived: bool = not tactics.manoeuvre_active(id) and str(unit.spatial.edge) == "" and (unit.spatial.path as Array).is_empty() and _distance(here, point) <= float(goal.radius_km)
	if arrived:
		for person: String in unit.get("gameplay_personnel", {}).get("members", {}):
			if not participants.dead(person) and _distance(participants.position(person), point) > float(goal.radius_km):
				arrived = false # Inventory/summary arrival does not move an outside body.
				break
	var own: bool = false
	var enemy: bool = false
	var incoming: bool = false
	var outgoing: bool = false
	for other_id: String in _space.combat_ids(str(unit.area_id)):
		work.goal_candidate_reads += 1
		var other: Dictionary = _state.units[other_id]
		if float(other.effective) <= 0.001:
			continue
		for location: Array in tactics.ground_positions(other_id):
			if _distance(location, point) <= float(goal.radius_km):
				if other.side == unit.side:
					own = true
				else:
					enemy = true
		if other.side != unit.side:
			if tactics.manoeuvre_active(other_id):
				for part: Dictionary in tactics.manoeuvres[other_id].parts.values():
					incoming = incoming or part.role == "FIRE" and float(part.ammunition) > 0.0 and _space.detection(tactics.part_source(other, part), unit) > 0.0
				outgoing = outgoing or _fire_capable(unit) and not tactics.visible_targets(unit, other_id).is_empty()
			else:
				incoming = incoming or _fire_capable(other) and _space.detection(other, unit) > 0.0
				outgoing = outgoing or _fire_capable(unit) and _space.detection(unit, other) > 0.0
	if tactics.manoeuvre_active(id):
		incoming = false
		outgoing = false
		for cell: String in _space.scope_cells(str(unit.area_id)):
			for contact: Dictionary in _state.contacts.get(cell, []):
				if float(contact.usable_fire_per_minute) <= 0.000001:
					continue
				outgoing = outgoing or contact.source == id
				incoming = incoming or contact.get("target_unit", contact.target) == id or str(contact.target).begins_with("body:") and str(contact.target).trim_prefix("body:") in tactics.manoeuvres[id].roster
	goal.route_complete = arrived
	goal.local_condition = arrived and own and not enemy
	goal.effective_incoming_contact = incoming
	goal.continuing_fire = outgoing
	goal.fire_reason = "ammunition_exhausted" if float(unit.ammunition) <= 0.0 else ("equipment_unavailable" if float(unit.get("serviceable_equipment", unit.equipment)) <= 0.0 else ("no_effective_target" if not outgoing else ""))
	goal.continuing_movement = mission.status == "active" and not arrived and unit.action in ["advance", "withdraw"] and _space.can_move(unit)
	goal.execution = "STOPPED" if mission.status != "active" else ("ARRIVED" if arrived else ("MOVING" if str(unit.spatial.edge) != "" else "WAITING"))
	if tactics.manoeuvre_active(id):
		goal.continuing_movement = tactics.manoeuvres[id].phase in ["FRONT_MOVING", "FRONT_RETURNING", "REAR_MOVING", "REAR_RETURNING"]
		goal.execution = "MOVING" if goal.continuing_movement else "WAITING"
		goal.manoeuvre_ref = tactics.manoeuvres[id].id
	if mission.status == "active" and (goal.continuing_movement or goal.continuing_fire or arrived):
		goal.support_started = true
	goal.reason = "route_blocked" if str(unit.spatial.blocked_edge) != "" else ("fuel_exhausted" if unit.get("supply_capability", {}).get("fuel_dependent", false) and float(unit.get("fuel", 0.0)) <= 0.0 else ("suppression" if float(unit.suppression) >= float(mission.stop_suppression) else ""))
	if tactics.manoeuvre_active(id):
		goal.reason = tactics.manoeuvres[id].reason
	if _lod.representation_of(id) != id and not can_summarize_goal(id):
		_schedule(id, str(mission.id), "representation", _state.time)
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
	if tactics.manoeuvre_active(str(unit.id)):
		tactics._stop_manoeuvre(str(unit.id), "parent_task_" + status, cause)
	mission.goal_v1.execution = "STOPPED"
	mission.goal_v1.continuing_movement = false
	mission.goal_v1.terminal_reason = reason
	mission.goal_v1.reason = reason
	prerequisites.unregister(mission)
	on_dependency_completed(str(mission.id))
	if _lod.representation_of(str(unit.id)) != str(unit.id):
		# A terminal goal has different retreat rules. Expand only its leaf before
		# the next physical segment, through the existing same-time event queue.
		_schedule(str(unit.id), str(mission.id), "representation", _state.time)
	for dependent: String in State.sorted_ids(_state.mission_dependents.get(mission.id, {})):
		if _lod.has_leaf(dependent):
			_state.wake(str(_lod.preview_leaf(dependent).area_id))
	_emit(str(unit.id), "goal_" + status, cause, {"mission_id": mission.id, "reason": reason, "standing_rule": "hold_and_fire"})

func _emit(unit_id: String, kind: String, cause: String, detail: Dictionary) -> void:
	_record_index += 1
	work.transitions += 1
	var record: Dictionary = {"event_id": "v1_%06d" % _record_index, "effective_time": _state.time,
		"phase": 20, "kind": kind, "subject_ref": unit_id, "cause_refs": [cause], "detail": detail.duplicate(true), "view": "DEBUG_TRUTH"}
	_state.structure_port.get_ref().movements.on_goal(record)
	prerequisites.on_goal(record)
	operations.on_unit(unit_id)
	transition.emit(record)

func snapshot() -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	var goals: Dictionary = {}
	for id: String in State.sorted_ids(_goals):
		goals[id] = _state.missions[_goals[id]].duplicate(true)
	return {"ok": true, "version": VERSION, "goals": goals, "work": work.duplicate(), "history_count": _history_count, "timer_count": _timers.size(), "view": "DEBUG_TRUTH"}

func visible_fact(ids: Array[String], kind: String) -> Dictionary:
	if ids.size() != 1 or not _lod.has_leaf(ids[0]) and not _state.units.has(ids[0]):
		return {}
	var unit: Dictionary = _state.units[ids[0]] if _state.units.has(ids[0]) else _lod.preview_leaf(ids[0])
	if not unit.has("spatial"):
		return {}
	if kind == "cover":
		return participants.cover_fact(unit)
	if kind == "objective":
		var mission: Dictionary = _state.missions[unit.mission_id]
		if not mission.has("goal_v1"):
			return {}
		return {"mission_ref": mission.id, "target_node": mission.goal_v1.target_node, "route_complete": mission.goal_v1.route_complete,
			"local_condition": mission.goal_v1.local_condition, "status": mission.status,
			"incoming_contact": mission.goal_v1.get("effective_incoming_contact", false),
			"dependency_state": mission.goal_v1.get("dependency_state", "READY"), "reason": mission.goal_v1.reason,
			"node_ref": unit.spatial.node, "edge_ref": unit.spatial.edge, "from_node": unit.spatial.get("from", ""),
			"path": unit.spatial.path.duplicate(), "fire_reason": mission.goal_v1.get("fire_reason", ""),
			"ammunition_level": operations.ammunition_level(unit),
			"capability": "UNAVAILABLE" if float(unit.effective) <= 0.001 else ("IMMOBILE" if float(unit.get("serviceable_equipment", unit.equipment)) <= 0.0 else "AVAILABLE")}
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
