extends RefCounted
## A bounded overlay of existing member capacity; no independent fire or RNG.
signal transition(record: Dictionary)
const State = preload("res://experiments/war_resolver/battle_state.gd")
const MAX_PEOPLE: int = 4
const MAX_PER_UNIT: int = 2
const MAX_ACTIONS: int = 256
var _state: State
var _space: RefCounted
var _structure: RefCounted
var _units: Dictionary = {}
var _covers: Dictionary = {}
var _actions: Dictionary = {}
var _serial: int = 0
var measure_cost: bool = false
var debug_calculations: bool = false
var cost_usec: Dictionary = {"prepare": 0, "allocation": 0, "settlement": 0}
var rules: Dictionary = {"cover_factor": 0.35, "local_speed_km_s": 0.002, "minimum_seconds": 5.0, "local_radius_km": 0.02}
var work: Dictionary = {"member_preparations": 0, "member_allocations": 0, "member_settlements": 0, "local_actions": 0, "action_events": 0}

func configure(state: State, space: RefCounted, structure: RefCounted, covers: Dictionary, policy: Dictionary = {}) -> bool:
	if _state != null:
		return false
	var configured: Dictionary = rules.duplicate()
	for key: String in policy:
		if not configured.has(key) or not (policy[key] is float or policy[key] is int) or not is_finite(float(policy[key])) or float(policy[key]) <= 0.0:
			return false
		configured[key] = float(policy[key])
	if float(configured.cover_factor) > 1.0 or covers.size() > 16:
		return false
	for id: String in covers:
		var cover: Dictionary = covers[id]
		if not space._nodes.has(cover.get("node", "")) or not cover.get("xy") is Array or cover.xy.size() != 2 or not cover.get("available") is bool:
			return false
		for coordinate: Variant in cover.xy:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return false
		if _distance(space._nodes[cover.node].xy, cover.xy) > float(configured.local_radius_km):
			return false
	_state = state
	_space = space
	_structure = structure
	_covers = covers.duplicate(true)
	rules = configured
	return true

func admit(actor: String) -> Dictionary:
	if _state.time != 0.0 or _units.has(actor) or _units.size() >= MAX_PEOPLE or not _structure._people.has(actor) or _structure._people[actor].role != "ordinary_soldier":
		return _reject("invalid_existing_member")
	var node: Dictionary = _structure._nodes[_structure._people[actor].formation_id]
	if not node.has("unit_id") or not _state.units.has(node.unit_id):
		return _reject("member_requires_detailed_unit")
	var unit: Dictionary = _state.units[node.unit_id]
	if not unit.has("spatial") or unit.has("contact_weight") or float(unit.effective) < 1.0:
		return _reject("member_capacity_unavailable")
	if _space.combat_ids(str(unit.area_id)).size() > 16:
		return _reject("personal_scope_capacity")
	var ledger: Dictionary = unit.get("gameplay_personnel", {"anonymous": float(unit.effective), "members": {}})
	if ledger.members.size() >= MAX_PER_UNIT or float(ledger.anonymous) < 1.0:
		return _reject("member_capacity_unavailable")
	ledger.anonymous -= 1.0
	ledger.members[actor] = {"actor_ref": actor, "unit_ref": unit.id, "health": 1.0, "injury": 0.0,
		"state": "FOLLOWING", "cover_ref": "", "action_ref": "", "xy": _space.xy(unit), "actionable": true}
	unit.gameplay_personnel = ledger
	_units[actor] = str(unit.id)
	return {"ok": true, "status": "EXISTING_MEMBER_BOUND", "unit_ref": unit.id}

func has_unit(id: String) -> bool:
	return _state.units.has(id) and _state.units[id].has("gameplay_personnel")

func observation_opportunity(actor: String, unit_id: String) -> bool:
	if not _units.has(actor):
		return true
	return _units[actor] == unit_id and _distance(position(actor), _space.xy(_state.units[unit_id])) <= float(rules.local_radius_km)

func cover_fact(unit: Dictionary) -> Dictionary:
	var ids: Array[String] = []
	if str(unit.spatial.edge).is_empty():
		for id: String in State.sorted_ids(_covers):
			if _covers[id].node == unit.spatial.node and _covers[id].available:
				ids.append(id)
	return {"node_ref": unit.spatial.node, "cover_refs": ids}

func _member(actor: String) -> Dictionary:
	return _state.units[_units[actor]].gameplay_personnel.members[actor]

func validate_action(actor: String, action: String) -> Dictionary:
	if not _units.has(actor) or action not in ["wait", "take_cover"] or _actions.size() >= MAX_ACTIONS:
		return _reject("unsupported_personal_action_or_capacity")
	var member: Dictionary = _member(actor)
	var unit: Dictionary = _state.units[_units[actor]]
	if not member.actionable:
		return _reject("person_incapacitated")
	if member.state in ["ENTERING", "RETURNING"]:
		return _reject("personal_action_in_progress")
	if action == "wait":
		return {"ok": true}
	if not str(unit.spatial.edge).is_empty() or not unit.spatial.path.is_empty():
		return _reject("cover_requires_stationary_group")
	var selected: String = ""
	for claim: Dictionary in _state.information_port.get_ref().knowledge(actor).get("entries", []):
		if claim.fact_kind != "cover" or claim.subject_ref != unit.id or claim.claimed_value.node_ref != unit.spatial.node:
			continue
		for cover_id: String in claim.claimed_value.cover_refs:
			if _covers.has(cover_id) and _covers[cover_id].available and _covers[cover_id].node == unit.spatial.node and (selected.is_empty() or cover_id < selected):
				selected = cover_id
	if selected.is_empty():
		return _reject("no_known_available_nearby_cover")
	return {"ok": true, "cover_ref": selected}

func apply_action(actor: String, id: String, action: String) -> Dictionary:
	var valid: Dictionary = validate_action(actor, action)
	if not valid.ok:
		return valid
	work.local_actions += 1
	var member: Dictionary = _member(actor)
	if action == "wait":
		if member.state == "COVERED":
			_start(actor, id, "RETURNING", _space.xy(_state.units[_units[actor]]), "")
		else:
			member.state = "FOLLOWING"
			_emit(actor, "personal_wait", id, {})
	else:
		_start(actor, id, "ENTERING", _covers[valid.cover_ref].xy, str(valid.cover_ref))
	return {"ok": true, "status": member.state, "actor_ref": actor}

func _start(actor: String, id: String, mode: String, destination: Array, cover: String) -> void:
	var member: Dictionary = _member(actor)
	var origin: Array = position(actor)
	var seconds: float = maxf(float(rules.minimum_seconds), _distance(origin, destination) / (float(rules.local_speed_km_s) * float(member.health)))
	var key: String = "personal_" + id + "_" + actor
	assert(not _actions.has(key) and _actions.size() < MAX_ACTIONS)
	_actions[key] = {"id": key, "actor_ref": actor, "unit_id": _units[actor], "from": origin, "to": destination.duplicate(),
		"started_at": _state.time, "due": _state.time + seconds, "mode": mode, "cover_ref": cover, "status": "PENDING", "input_ref": id}
	member.state = mode
	member.action_ref = key
	assert(_state.schedule_event(key, _state.time + seconds, "gameplay", {"action_id": key, "unit_id": _units[actor]}))
	_state.wake(str(_state.units[_units[actor]].area_id))
	_emit(actor, "personal_action_started", id, {"state": mode, "from": origin, "to": destination, "due": _state.time + seconds})

func prepare_departure(unit_id: String, cause: String) -> void:
	if not has_unit(unit_id):
		return
	for actor: String in State.sorted_ids(_state.units[unit_id].gameplay_personnel.members):
		var member: Dictionary = _member(actor)
		if not member.actionable or member.state == "FOLLOWING":
			continue
		if member.state in ["ENTERING", "RETURNING"]:
			var previous: Dictionary = _actions[member.action_ref]
			member.xy = position(actor)
			previous.status = "SUPERSEDED"
		_start(actor, "regroup_" + cause, "RETURNING", _space.xy(_state.units[unit_id]), "")

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 2 and _actions.has(id) and payload.get("action_id") == id and payload.get("unit_id") == _actions[id].unit_id and float(_actions[id].due) == due

func process_event(event: Dictionary) -> Dictionary:
	var action: Dictionary = _actions[event.id]
	work.action_events += 1
	var member: Dictionary = _member(str(action.actor_ref))
	if action.status != "PENDING" or member.action_ref != action.id or not member.actionable:
		action.status = "OBSOLETE"
		return {"changed": [], "retired": [], "record": {"status": "OBSOLETE", "id": event.id}}
	member.xy = action.to.duplicate()
	member.state = "COVERED" if action.mode == "ENTERING" else "FOLLOWING"
	member.cover_ref = action.cover_ref
	member.action_ref = ""
	action.status = "EXECUTED"
	_state.wake(str(_state.units[action.unit_id].area_id))
	_emit(str(action.actor_ref), "personal_action_finished", str(action.input_ref), {"state": member.state, "xy": member.xy})
	return {"changed": [action.unit_id], "retired": [], "record": action.duplicate(true)}

func prepare(unit: Dictionary, plan: Dictionary) -> void:
	if not has_unit(str(unit.id)):
		return
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var ledger: Dictionary = unit.gameplay_personnel
	var members: Dictionary = {}
	var weighted: float = float(ledger.anonymous)
	var regrouping: bool = false
	for actor: String in State.sorted_ids(ledger.members):
		work.member_preparations += 1
		var member: Dictionary = ledger.members[actor]
		var factor: float = float(rules.cover_factor) if member.state == "COVERED" else 1.0
		members[actor] = {"health": member.health, "factor": factor, "requested": 0.0}
		weighted += float(member.health) * factor
		regrouping = regrouping or member.actionable and member.state != "FOLLOWING"
	plan.personal_ledger = {"effective": unit.effective, "anonymous": ledger.anonymous, "anonymous_requested": 0.0,
		"members": members, "base_exposure": plan.exposure, "regrouping": regrouping}
	plan.exposure *= weighted / maxf(0.000001, float(unit.effective))
	if measure_cost:
		cost_usec.prepare += Time.get_ticks_usec() - started

func constrain_movement(plan: Dictionary) -> void:
	if plan.has("personal_ledger") and plan.personal_ledger.regrouping:
		plan.speed = 0.0

func incoming(plan: Dictionary, dose: float) -> void:
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var ledger: Dictionary = plan.personal_ledger
	var per_capacity: float = dose * float(ledger.base_exposure) / maxf(0.000001, float(ledger.effective))
	ledger.anonymous_requested += per_capacity * float(ledger.anonymous)
	for actor: String in State.sorted_ids(ledger.members):
		work.member_allocations += 1
		ledger.members[actor].requested += per_capacity * float(ledger.members[actor].health) * float(ledger.members[actor].factor)
	if measure_cost:
		cost_usec.allocation += Time.get_ticks_usec() - started

func settle(unit: Dictionary, plan: Dictionary) -> float:
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var requests: Dictionary = plan.personal_ledger
	var ledger: Dictionary = unit.gameplay_personnel
	var anonymous_loss: float = minf(float(requests.anonymous), float(requests.anonymous_requested))
	ledger.anonymous = float(requests.anonymous) - anonymous_loss
	var total: float = anonymous_loss
	var allocation_id: String = "allocation_%.9f_%s" % [_state.time, unit.id]
	for actor: String in State.sorted_ids(requests.members):
		work.member_settlements += 1
		var before: float = float(requests.members[actor].health)
		var loss: float = minf(before, float(requests.members[actor].requested))
		var member: Dictionary = ledger.members[actor]
		member.health = before - loss
		member.injury += loss
		member.actionable = float(member.health) > 0.000001
		total += loss
		if loss > 0.0:
			if not member.actionable:
				member.xy = position(actor)
				member.state = "INCAPACITATED"
			_emit(actor, "personal_injury", allocation_id if debug_calculations else "fire_segment_%.6f" % _state.time, {"before_health": before, "after_health": member.health, "actionable": member.actionable, "cause": "shared_incoming_fire"})
	if debug_calculations and total > 0.0:
		var scope: String = str(_space._scope_anchor.get(str(_space._cell_scope.get(str(unit.area_id), unit.area_id)), unit.area_id))
		var contacts: Array[Dictionary] = []
		var sources: Array[String] = []
		for contact: Dictionary in _state.contacts.get(scope, []):
			if contact.target == unit.id and float(contact.usable_fire_per_minute) > 0.0:
				contacts.append(contact.duplicate(true))
				sources.append(str(contact.source))
		transition.emit({"event_id": allocation_id, "effective_time": _state.time, "learned_time": null, "phase": -3,
			"kind": "shared_fire_allocation", "subject_ref": unit.id, "cause_refs": sources, "view": "DEBUG_TRUTH",
			"detail": {"segment_start_capacity": requests.effective, "base_exposure": requests.base_exposure,
				"anonymous_requested": requests.anonymous_requested, "anonymous_loss": anonymous_loss, "member_requests": requests.members.duplicate(true),
				"total_loss_applied_once": total, "prepared_contacts": contacts, "contact_note": "planned contact rates; requested dose includes actual ammunition limit and shared keyed variation"}})
	if measure_cost:
		cost_usec.settlement += Time.get_ticks_usec() - started
	return total

func position(actor: String) -> Array:
	var member: Dictionary = _member(actor)
	if member.state == "FOLLOWING":
		return _space.xy(_state.units[_units[actor]])
	if member.state in ["ENTERING", "RETURNING"]:
		var action: Dictionary = _actions[member.action_ref]
		var fraction: float = clampf((_state.time - float(action.started_at)) / (float(action.due) - float(action.started_at)), 0.0, 1.0)
		return [lerpf(float(action.from[0]), float(action.to[0]), fraction), lerpf(float(action.from[1]), float(action.to[1]), fraction)]
	return member.xy.duplicate()

func view(actor: String) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if not _units.has(actor):
		return _reject("person_not_in_causal_overlay")
	var result: Dictionary = _member(actor).duplicate(true)
	result.xy = position(actor)
	result.view = "PERSON_VISIBLE"
	result.time = _state.time
	return result

func _emit(actor: String, kind: String, cause: String, detail: Dictionary) -> void:
	_serial += 1
	transition.emit({"event_id": "person_%06d" % _serial, "effective_time": _state.time, "learned_time": _state.time,
		"phase": 10, "kind": kind, "actor_ref": actor, "subject_ref": _units[actor], "cause_refs": [cause],
		"detail": detail.duplicate(true), "view": "PERSON_VISIBLE"})

static func _distance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
