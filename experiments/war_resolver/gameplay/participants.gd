extends RefCounted
## A bounded overlay of existing member capacity; no independent fire or RNG.
signal transition(record: Dictionary)
const State = preload("res://experiments/war_resolver/battle_state.gd")
# Four local participants plus two existing command-post officers.
const MAX_PEOPLE: int = 6
const MAX_PER_UNIT: int = 4
const MAX_ACTIONS: int = 256
var _state: State
var _space: RefCounted
var _structure: RefCounted
var _units: Dictionary = {}
var _bodies: Dictionary = {} # Index of the same body objects across LOD changes.
var _detail_tickets: Dictionary = {}
var _covers: Dictionary = {}
var _actions: Dictionary = {}
var local_rescues: Dictionary = {} # Existing bodies, one bounded local responsibility per helper.
var _serial: int = 0
var medical: RefCounted
var measure_cost: bool = false
var debug_calculations: bool = false
var cost_usec: Dictionary = {"prepare": 0, "allocation": 0, "settlement": 0}
var rules: Dictionary = {"cover_factor": 0.35, "local_speed_km_s": 0.002, "minimum_seconds": 5.0, "local_radius_km": 0.02,
	"minimum_carrier_health": 0.5, "carry_speed_factor": 0.5, "fatal_trauma": 1.0}
var work: Dictionary = {"member_preparations": 0, "member_allocations": 0, "member_settlements": 0, "local_actions": 0, "action_events": 0}

func configure(state: State, space: RefCounted, structure: RefCounted, covers: Dictionary, policy: Dictionary = {}) -> bool:
	if _state != null:
		return false
	var configured: Dictionary = rules.duplicate()
	for key: String in policy:
		if not configured.has(key) or not (policy[key] is float or policy[key] is int) or not is_finite(float(policy[key])) or float(policy[key]) <= 0.0:
			return false
		configured[key] = float(policy[key])
	if float(configured.cover_factor) > 1.0 or float(configured.carry_speed_factor) > 1.0 or float(configured.minimum_carrier_health) > 1.0 or covers.size() > 16:
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

func admit(actor: String, capacity_unit: String = "", command_post: String = "") -> Dictionary:
	if _state.time != 0.0 or _units.has(actor) or _units.size() >= MAX_PEOPLE or not _structure._people.has(actor):
		return _reject("invalid_existing_member")
	var node: Dictionary = _structure._nodes[_structure._people[actor].formation_id]
	var higher: bool = not command_post.is_empty()
	if higher and (not _space._nodes.has(command_post) or not _state.units.has(capacity_unit) or not _structure._contains(str(_structure._people[actor].formation_id), str(_structure._unit_nodes.get(capacity_unit, "")))):
		return _reject("actual_command_post_and_existing_personnel_share_required")
	if not higher and (_structure._people[actor].role not in ["ordinary_soldier", "squad_leader"] or not node.has("unit_id") or not _state.units.has(node.unit_id)):
		return _reject("member_requires_detailed_unit")
	var unit: Dictionary = _state.units[capacity_unit if higher else node.unit_id]
	if not unit.has("spatial") or unit.has("contact_weight") or float(unit.effective) < 1.0:
		return _reject("member_capacity_unavailable")
	if _space.combat_ids(str(unit.area_id)).size() > 16:
		return _reject("personal_scope_capacity")
	var ledger: Dictionary = unit.get("gameplay_personnel", {"anonymous": float(unit.effective), "members": {}})
	if ledger.members.size() >= MAX_PER_UNIT or float(ledger.anonymous) < 1.0:
		return _reject("member_capacity_unavailable")
	ledger.anonymous -= 1.0
	ledger.members[actor] = {"actor_ref": actor, "unit_ref": unit.id, "health": 1.0, "injury": 0.0,
		"state": "FOLLOWING", "life_state": "ABLE", "trauma": 0.0, "cover_ref": "", "action_ref": "", "xy": _space.xy(unit), "actionable": true}
	ledger.members[actor].anchor_node = command_post if higher else str(unit.spatial.node)
	if higher:
		ledger.members[actor].state = "STATIONARY"
		ledger.members[actor].xy = _space._nodes[command_post].xy.duplicate()
		ledger.members[actor].command_post = command_post
	unit.gameplay_personnel = ledger
	_units[actor] = str(unit.id)
	_bodies[actor] = ledger.members[actor]
	return {"ok": true, "status": "EXISTING_MEMBER_BOUND", "unit_ref": unit.id}

func has_unit(id: String) -> bool:
	return _state.units.has(id) and _state.units[id].has("gameplay_personnel")

func living_exposure(unit: Dictionary) -> bool:
	for actor: String in unit.get("gameplay_personnel", {}).get("members", {}):
		if not dead(actor) and _distance(position(actor), _space.xy(unit)) <= float(rules.local_radius_km):
			return true
	return false

func observation_opportunity(actor: String, unit_id: String) -> bool:
	if not _units.has(actor):
		return true
	var source: Dictionary = _state.gameplay_port.get_ref().tactics.actor_part(actor)
	var point: Array = _space.xy(_physical_unit(actor)) if source.is_empty() else _space.xy({"spatial": source.spatial})
	if _member(actor).has("local_ref") or str(_member(actor).get("local_edge", "")) != "":
		point = position(actor)
	return can_intend(actor) and _units[actor] == unit_id and _distance(position(actor), point) <= float(rules.local_radius_km)

func cover_fact(unit: Dictionary) -> Dictionary:
	var ids: Array[String] = []
	if str(unit.spatial.edge).is_empty():
		for id: String in State.sorted_ids(_covers):
			if _covers[id].node == unit.spatial.node and _covers[id].available:
				if _space._local_position_refs.has(id):
					var visible: bool = false
					for site_ref: String in _space._local_sites:
						var site: Dictionary = _space._local_sites[site_ref]
						if site.get("position_ref", site.get("cover_ref", "")) == id and _space.observation_at(unit, {"node": site.node_ref, "sight_ref": site_ref, "xy": site.xy, "ground": site.ground}) > 0.0:
							visible = true
					if not visible:
						continue
				ids.append(id)
	return {"node_ref": unit.spatial.node, "cover_refs": ids}

func _member(actor: String) -> Dictionary:
	return _bodies[actor]

func can_intend(actor: String) -> bool:
	return not _units.has(actor) or _member(actor).actionable and _member(actor).state not in ["AMMO_HANDLING", "PUTTING_DOWN", "PICKING_UP", "MEDICATING", "PLACING_REMAINS", "RELOCATING", "LOCAL_MOVING", "LOCAL_ENTERING", "TRANSPORTED", "PART_ENTERING"] and str(_member(actor).get("carrying_ref", "")).is_empty()

func dead(actor: String) -> bool:
	return _units.has(actor) and _member(actor).life_state == "DEAD"

func _physical_unit(actor: String) -> Dictionary:
	var id: String = str(_units[actor])
	return _state.units[_state.materialization_port.get_ref().representation_of(id)]

func requires_detail(unit_id: String) -> bool:
	var unit: Dictionary = _state.units[unit_id] if _state.units.has(unit_id) else _state.materialization_port.get_ref().preview_leaf(unit_id)
	for actor: String in unit.get("gameplay_personnel", {}).get("members", {}):
		var member: Dictionary = _member(actor)
		if member.state not in ["FOLLOWING", "DEAD"] or member.get("bleeding", {}).get("active", false) or member.get("treatment", {}).get("status", "") in ["IN_PROGRESS", "RECOVERING"] or not str(member.get("carrying_ref", "")).is_empty():
			return true
	return false

func has_members(unit_id: String) -> bool:
	var unit: Dictionary = _state.units[unit_id] if _state.units.has(unit_id) else _state.materialization_port.get_ref().preview_leaf(unit_id)
	return not unit.get("gameplay_personnel", {}).get("members", {}).is_empty()

func transport_check(patient: String, carrier: String, picked_up: bool = false, remains: bool = false, local_contact: bool = false) -> Dictionary:
	if patient == carrier or not _units.has(patient) or not _units.has(carrier) or not remains and _units[patient] != _units[carrier]:
		return _reject("existing_patient_and_carrier_in_same_group_required")
	var body: Dictionary = _member(patient)
	var helper: Dictionary = _member(carrier)
	if helper.state in ["MEDICATING", "PLACING_REMAINS", "TRANSPORTED"] or helper.state == "RELOCATING" and not picked_up:
		return _reject("carrier_has_conflicting_actual_personal_action")
	if body.has("carrier_ref") and body.carrier_ref != carrier:
		return _reject("body_already_carried_by_another_existing_person")
	if remains and body.get("remains", {}).get("status", "") == "PLACED":
		return _reject("placed_remains_exhumation_not_supported")
	if remains and (body.life_state != "DEAD" or body.state not in ["DEAD", "TRANSPORTED"] or _physical_unit(patient).side != _physical_unit(carrier).side):
		return _reject("existing_same_side_remains_required")
	if not remains and (body.life_state == "DEAD" or (body.actionable and body.state != "TRANSPORTED" or body.state not in ["INCAPACITATED", "TRANSPORTED"]) and not (local_contact and body.life_state == "WOUNDED" and str(body.action_ref).is_empty())):
		return _reject("living_incapacitated_patient_required")
	if not helper.actionable or float(helper.health) < float(rules.minimum_carrier_health):
		return _reject("carrier_no_longer_able_to_carry")
	if not str(helper.get("carrying_ref", "")).is_empty() and helper.carrying_ref != patient:
		return _reject("carrier_already_occupied")
	if picked_up:
		return {"ok": true} if body.state == "TRANSPORTED" and body.get("carrier_ref", "") == carrier and helper.get("carrying_ref", "") == patient else _reject("actual_pickup_required")
	if (not remains and not local_contact and _distance(position(patient), _space.xy(_physical_unit(carrier))) > float(rules.local_radius_km)) or _distance(position(patient), position(carrier)) > float(rules.local_radius_km):
		return _reject("patient_outside_actual_pickup_radius")
	if local_contact and (_space.local_place(body_spatial(patient)) != _space.local_place(body_spatial(carrier)) or str(body_spatial(patient).get("local_edge", "")) != "" or str(body_spatial(carrier).get("local_edge", "")) != ""):
		return _reject("actual_contact_at_declared_local_endpoint_required")
	return {"ok": true}

func start_transport(patient: String, carrier: String, movement: String, cause: String) -> void:
	# The carrier approaches the existing body; pickup completes on an action ticket.
	var body: Dictionary = _member(patient)
	body.transport_ref = movement
	body.transport_status = "WAITING_PICKUP"
	body.rescue_carrier_ref = carrier
	_start(carrier, cause, "PICKING_UP", position(patient), "")
	_actions[_member(carrier).action_ref].patient_ref = patient
	_actions[_member(carrier).action_ref].movement_ref = movement

func release_transport(patient: String, status: String, cause: String) -> void:
	var body: Dictionary = _member(patient)
	if body.get("transport_status", "") == status and not body.has("carrier_ref") and not body.has("rescue_carrier_ref"):
		return
	var was_carried: bool = body.has("carrier_ref")
	if was_carried or str(body.action_ref).is_empty():
		body.xy = position(patient)
	var carrier: String = str(body.get("carrier_ref", body.get("rescue_carrier_ref", "")))
	if _units.has(carrier):
		var helper: Dictionary = _member(carrier)
		if body.get("carrier_ref", "") == carrier:
			var actual: Dictionary = body_spatial(carrier)
			body.anchor_node = actual.node
			body.anchor_edge = actual.edge
			_bind_body_local(body, actual)
		if helper.state == "PICKING_UP" and _actions[helper.action_ref].patient_ref == patient:
			helper.xy = position(carrier)
			_actions[helper.action_ref].status = "INTERRUPTED"
			helper.action_ref = ""
			helper.state = "COVERED"
		helper.erase("carrying_ref")
		if local_rescues.get(carrier, {}).get("patient_ref", "") == patient:
			local_rescues[carrier].status = status
			local_rescues[carrier].finished_at = _state.time
			local_rescues[carrier].xy = body.xy.duplicate()
	body.erase("carrier_ref")
	body.erase("rescue_carrier_ref")
	body.transport_status = status
	if was_carried:
		if body.life_state != "DEAD":
			body.state = "STATIONARY" if body.actionable else "INCAPACITATED"
		else:
			body.state = "DEAD"
			body.remains.status = "RECEIVED" if status == "HANDED_OVER" else "UNRECOVERED"
	_emit(patient, "personal_transport_" + status.to_lower(), cause, {"xy": body.xy, "movement_ref": body.get("transport_ref", ""), "health": body.health})

func rebind_member(actor: String, destination: String, disposition: String = "carry", pooled: bool = false, cause: String = "") -> void:
	# Called by the current structure event after capacity and space admission.
	# The event ticket keeps its original unit reference; its body keeps its clock.
	var source: Dictionary = _state.units[_units[actor]]
	var target: Dictionary = _state.units[destination]
	var member: Dictionary = source.gameplay_personnel.members[actor]
	_state.gameplay_port.get_ref().tactics.member_moved(actor, str(source.id), destination, disposition, pooled, cause)
	if _structure._person_positions.get(actor, "") == _structure._unit_nodes[source.id]:
		_structure.vacate_node(str(_structure._unit_nodes[source.id]), "member_left_position", "member_" + actor + "_" + destination)
	member.xy = position(actor)
	source.gameplay_personnel.members.erase(actor)
	if not target.has("gameplay_personnel"):
		target.gameplay_personnel = {"anonymous": float(target.effective), "members": {}}
	target.gameplay_personnel.members[actor] = member
	member.unit_ref = destination
	_units[actor] = destination
	if _state.information_port != null:
		_state.information_port.get_ref().on_member_move(actor, str(_structure._unit_nodes[source.id]), str(_structure._unit_nodes[destination]))
	if not str(member.action_ref).is_empty() and _actions[member.action_ref].status == "PENDING":
		var action: Dictionary = _actions[member.action_ref]
		_settle_road_action(actor, action)
		if action.mode == "MEDICATING":
			_member(str(action.medical.patient_ref)).treatment.status = "INTERRUPTED"
		# Membership edits stop local work at its actual interpolated position.
		action.status = "INTERRUPTED"
		action.interrupted_at = _state.time
		action.reason = "member_handover"
		member.action_ref = ""
		member.state = "STATIONARY"
		_state.gameplay_port.get_ref().tactics.body_action_finished(actor, str(action.id), "TRANSFERRED")
	if source.gameplay_personnel.members.is_empty():
		source.erase("gameplay_personnel")

func validate_action(actor: String, action: String) -> Dictionary:
	if not _units.has(actor) or action not in ["wait", "take_cover"] or _actions.size() >= MAX_ACTIONS:
		return _reject("unsupported_personal_action_or_capacity")
	var member: Dictionary = _member(actor)
	var unit: Dictionary = _physical_unit(actor)
	if _state.gameplay_port.get_ref().tactics.manoeuvre_active(str(_units[actor])):
		return _reject("stop_and_regroup_road_task_before_other_local_body_movement")
	if not can_intend(actor):
		return _reject("person_dead" if dead(actor) else ("carrier_occupied" if member.actionable else "person_incapacitated"))
	if member.state in ["ENTERING", "RETURNING", "PICKING_UP"]:
		return _reject("personal_action_in_progress")
	if action == "wait":
		if _space.local_place(body_spatial(actor)) != _space.local_place(unit.spatial) or str(body_spatial(actor).get("local_edge", "")) != "":
			return _reject("actual_local_return_before_following_group")
		if member.state == "STATIONARY" and not member.has("command_post") and (_distance(position(actor), _space.xy(unit)) > float(rules.local_radius_km) or not str(unit.spatial.edge).is_empty() or not unit.spatial.path.is_empty()):
			return _reject("actual_regroup_location_required")
		return {"ok": true}
	if _distance(position(actor), _space.xy(unit)) > float(rules.local_radius_km):
		return _reject("cover_requires_actual_group_location")
	if not str(unit.spatial.edge).is_empty() or not unit.spatial.path.is_empty():
		return _reject("cover_requires_stationary_group")
	var selected: String = ""
	for claim: Dictionary in _state.information_port.get_ref().knowledge(actor).get("entries", []):
		# Terrain knowledge belongs to the person and place, even after membership moves.
		if claim.fact_kind != "cover" or claim.claimed_value.node_ref != unit.spatial.node:
			continue
		for cover_id: String in claim.claimed_value.cover_refs:
			if _covers.has(cover_id) and _covers[cover_id].available and _covers[cover_id].node == unit.spatial.node and (selected.is_empty() or cover_id < selected):
				selected = cover_id
	if selected.is_empty():
		return _reject("no_known_available_nearby_cover")
	if _space._local_position_refs.has(selected):
		var here: Dictionary = body_spatial(actor)
		var site: Dictionary = _space._local_sites.get(_space.local_place(here), {})
		if site.get("position_ref", site.get("cover_ref", "")) != selected or str(here.get("local_edge", "")) != "" or _distance(position(actor), _covers[selected].xy) > 0.000001:
			return _reject("declared_local_manoeuvre_and_actual_position_entry_required")
	return {"ok": true, "cover_ref": selected}

func admit_constructed_cover(producer: RefCounted, position: Dictionary) -> void:
	if producer != _space or position.kind != "personal" or _covers.size() >= 16 and not _covers.has(position.id):
		return
	_covers[position.id] = {"node": position.node_ref, "xy": position.xy.duplicate(), "available": _space.position_cover(str(position.id)) > 0.0, "constructed": true}

func _cover_factor(id: String) -> float:
	if _covers.get(id, {}).get("constructed", false):
		return 1.0 - _space.position_cover(id)
	return float(rules.cover_factor)

func apply_action(actor: String, id: String, action: String) -> Dictionary:
	var valid: Dictionary = validate_action(actor, action)
	if not valid.ok:
		return valid
	work.local_actions += 1
	var member: Dictionary = _member(actor)
	var representation: Dictionary = {"changed": [], "retired": []}
	if action == "take_cover" or member.state in ["COVERED", "STATIONARY"]:
		representation = _state.materialization_port.get_ref().materialize_leaf(str(_units[actor]), "precise_personal_action")
	if action == "wait":
		if member.state in ["COVERED", "STATIONARY"] and not member.has("command_post"):
			_start(actor, id, "RETURNING", _space.xy(_state.units[_units[actor]]), "")
		else:
			member.state = "STATIONARY" if member.has("command_post") else "FOLLOWING"
			_emit(actor, "personal_wait", id, {})
	else:
		_start(actor, id, "ENTERING", _covers[valid.cover_ref].xy, str(valid.cover_ref))
	return {"ok": true, "status": member.state, "actor_ref": actor, "changed": representation.get("changed", [_units[actor]]), "retired": representation.get("retired", [])}

func _bind_body_local(body: Dictionary, route: Dictionary) -> void:
	for field: String in ["local_ref", "local_edge", "local_from", "local_to", "local_progress", "local_returning", "entered_site_ref"]:
		body.erase(field)
		if route.has(field):
			body[field] = route[field]

func _start(actor: String, id: String, mode: String, destination: Array, cover: String, duration: float = 0.0) -> void:
	_state.gameplay_port.get_ref().tactics.body_action_started(actor)
	var member: Dictionary = _member(actor)
	var origin: Array = position(actor)
	if not str(member.action_ref).is_empty() and _actions[member.action_ref].status == "PENDING":
		var previous: Dictionary = _actions[member.action_ref]
		_settle_road_action(actor, previous)
		previous.status = "SUPERSEDED"
		previous.interrupted_at = _state.time
		_state.gameplay_port.get_ref().tactics.body_action_finished(actor, str(previous.id), "SUPERSEDED")
	if member.state == "FOLLOWING":
		member.anchor_node = str(_physical_unit(actor).spatial.node)
		member.anchor_edge = str(_physical_unit(actor).spatial.edge)
		_bind_body_local(member, _physical_unit(actor).spatial)
	var speed: float = float(rules.local_speed_km_s) * float(member.health)
	if not str(member.get("carrying_ref", "")).is_empty():
		speed *= float(rules.carry_speed_factor)
	var seconds: float = maxf(float(rules.minimum_seconds), _distance(origin, destination) / speed)
	if duration > 0.0:
		seconds = maxf(seconds, duration)
	var key: String = "personal_" + id + "_" + actor
	assert(not _actions.has(key) and _actions.size() < MAX_ACTIONS)
	_actions[key] = {"id": key, "actor_ref": actor, "unit_id": _units[actor], "event_unit_id": _units[actor], "from": origin, "to": destination.duplicate(),
		"started_at": _state.time, "due": _state.time + seconds, "mode": mode, "cover_ref": cover, "status": "PENDING", "input_ref": id}
	member.state = mode
	member.xy = origin.duplicate()
	member.action_ref = key
	assert(_state.schedule_event(key, _state.time + seconds, "gameplay", {"action_id": key, "unit_id": _units[actor]}))
	_state.wake(str(_state.units[_units[actor]].area_id))
	_emit(actor, "personal_action_started", id, {"state": mode, "from": origin, "to": destination, "due": _state.time + seconds})

func interrupt_action(actor: String, cause: String) -> void:
	var member: Dictionary = _member(actor)
	var action: Dictionary = _actions.get(member.action_ref, {})
	if action.is_empty() or action.status != "PENDING":
		return
	member.xy = position(actor)
	_settle_road_action(actor, action)
	action.status = "INTERRUPTED"
	action.interrupted_at = _state.time
	action.reason = cause
	if action.mode == "MEDICATING":
		_member(str(action.medical.patient_ref)).treatment.status = "INTERRUPTED"
	member.action_ref = ""
	member.state = "STATIONARY" if member.actionable else "INCAPACITATED"
	member.cover_ref = ""
	if action.get("rescue_ref", "") == local_rescues.get(actor, {}).get("id", "") and action.has("rescue_ref"):
		local_rescues[actor].status = "INTERRUPTED"
		local_rescues[actor].reason = cause
		var patient: String = str(local_rescues[actor].patient_ref)
		if _member(patient).get("carrier_ref", "") == actor or _member(patient).get("rescue_carrier_ref", "") == actor:
			release_transport(patient, "INTERRUPTED", str(action.input_ref))
	_state.gameplay_port.get_ref().tactics.body_action_finished(actor, str(action.id), "INTERRUPTED")
	_emit(actor, "personal_action_interrupted", str(action.input_ref), {"reason": cause, "xy": member.xy, "action_ref": action.id})

func prepare_departure(unit_id: String, cause: String) -> void:
	if not has_unit(unit_id):
		return
	for actor: String in State.sorted_ids(_state.units[unit_id].gameplay_personnel.members):
		var member: Dictionary = _member(actor)
		if _state.gameplay_port.get_ref().tactics.separated_actor(actor) or member.state in ["LOCAL_MOVING", "LOCAL_ENTERING"]:
			continue # Local bodies require their accepted path, never node attraction.
		if not member.actionable or not str(member.action_ref).is_empty() or member.state in ["FOLLOWING", "AMMO_HANDLING", "PUTTING_DOWN", "PICKING_UP", "MEDICATING", "PLACING_REMAINS", "RELOCATING"] or member.has("command_post"):
			continue
		if member.state in ["ENTERING", "RETURNING"]:
			var previous: Dictionary = _actions[member.action_ref]
			member.xy = position(actor)
			previous.status = "SUPERSEDED"
		_start(actor, "regroup_" + cause, "RETURNING", _space.xy(_state.units[unit_id]), "")

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	if payload.has("person_id"):
		return payload.size() == 1 and _detail_tickets.has(id) and payload.person_id == _detail_tickets[id].actor and due == _detail_tickets[id].due
	return payload.size() == 2 and _actions.has(id) and payload.get("action_id") == id and payload.get("unit_id") == _actions[id].get("event_unit_id", _actions[id].unit_id) and float(_actions[id].due) == due

func process_event(event: Dictionary) -> Dictionary:
	if event.payload.has("person_id"):
		var actor: String = str(event.payload.person_id)
		_detail_tickets.erase(event.id)
		var result: Dictionary = _state.materialization_port.get_ref().materialize_leaf(str(_units[actor]), "personal_state_requires_detail")
		return {"changed": result.get("changed", [_units[actor]]), "retired": result.get("retired", []), "record": {"kind": "personal_leaf_detailed", "actor_ref": actor}}
	var action: Dictionary = _actions[event.id]
	work.action_events += 1
	var member: Dictionary = _member(str(action.actor_ref))
	if action.status != "PENDING" or member.action_ref != action.id or not member.actionable:
		if action.status == "PENDING":
			action.status = "OBSOLETE"
		return {"changed": [], "retired": [], "record": {"status": "OBSOLETE", "id": event.id}}
	if action.mode == "AMMO_HANDLING":
		_state.gameplay_port.get_ref().tactics._finish_supply(str(action.unit_id), true)
		return {"changed": [action.unit_id], "retired": [], "record": action.duplicate(true)}
	if action.mode == "PUTTING_DOWN":
		var patient: String = str(action.patient_ref)
		if _member(patient).get("carrier_ref", "") == action.actor_ref:
			release_transport(patient, "PUT_DOWN", str(action.input_ref))
		member.action_ref = ""
		member.state = "STATIONARY"
		action.status = "EXECUTED"
		_state.gameplay_port.get_ref().tactics.body_action_finished(str(action.actor_ref), str(action.id), "EXECUTED")
		return {"changed": [action.unit_id], "retired": [], "record": action.duplicate(true)}
	if action.mode in ["LOCAL_MOVING", "LOCAL_ENTERING"]:
		return _complete_local_action(action)
	if action.mode == "MEDICATING":
		var result: Dictionary = medical.complete(action)
		member.action_ref = ""
		member.state = "COVERED" if _covers.has(member.cover_ref) and _distance(member.xy, _covers[member.cover_ref].xy) <= 0.000001 else "STATIONARY"
		if not member.has("command_post") and _distance(member.xy, _space.xy(_physical_unit(str(action.actor_ref)))) <= 0.000001:
			member.state = "FOLLOWING"
		action.status = str(result.status)
		var changed: Array = result.get("changed", [])
		if action.unit_id not in changed:
			changed.append(action.unit_id)
		return {"changed": changed, "retired": [], "record": result}
	if action.mode == "PLACING_REMAINS":
		var corpse: String = str(action.person_ref)
		if dead(corpse) and _distance(position(str(action.actor_ref)), position(corpse)) <= float(rules.local_radius_km):
			_member(corpse).remains.status = "PLACED"
			_member(corpse).remains.disposition = {"time": _state.time, "by": action.actor_ref, "xy": position(corpse), "cause_ref": action.input_ref}
		member.action_ref = ""
		member.state = "STATIONARY"
		action.status = "EXECUTED"
		return {"changed": [action.unit_id], "retired": [], "record": {"kind": "remains_placement", "person_ref": corpse}}
	if action.mode == "RELOCATING":
		_settle_road_action(str(action.actor_ref), action)
		member.xy = action.to.duplicate()
		member.anchor_node = action.destination_node
		if member.has("command_post"):
			member.command_post = action.destination_node
		member.anchor_edge = ""
		member.action_ref = ""
		member.state = "STATIONARY"
		action.status = "EXECUTED"
		_state.gameplay_port.get_ref().tactics.body_action_finished(str(action.actor_ref), str(action.id), "EXECUTED")
		_emit(str(action.actor_ref), "personal_route_leg_finished", str(action.input_ref), {"node_ref": member.anchor_node, "xy": member.xy, "action_ref": action.id})
		if not action.path.is_empty():
			_route_leg(str(action.actor_ref), str(action.input_ref), str(action.destination), action.path)
		elif action.has("remains_ref"):
			_member(str(action.remains_ref)).anchor_node = member.anchor_node
			release_transport(str(action.remains_ref), "HANDED_OVER", str(action.input_ref))
		return {"changed": [action.unit_id], "retired": [], "record": {"kind": "personal_route_leg", "person_ref": action.actor_ref}}
	if action.mode == "PICKING_UP":
		var valid: Dictionary = transport_check(str(action.patient_ref), str(action.actor_ref), false, action.has("remains_route"), action.has("rescue_ref"))
		member.action_ref = ""
		member.xy = action.to.duplicate()
		member.state = "COVERED"
		if not valid.ok:
			action.status = "INTERRUPTED"
			if action.has("rescue_ref"):
				release_transport(str(action.patient_ref), "INTERRUPTED", str(action.input_ref))
			_emit(str(action.actor_ref), "personal_pickup_interrupted", str(action.input_ref), {"reason": valid.error})
			return {"changed": [action.unit_id], "retired": [], "record": action.duplicate(true)}
		var patient: Dictionary = _member(str(action.patient_ref))
		patient.state = "TRANSPORTED"
		patient.carrier_ref = action.actor_ref
		patient.transport_status = "PICKED_UP"
		member.carrying_ref = action.patient_ref
		action.status = "EXECUTED"
		_state.gameplay_port.get_ref().focus_continuity.event_relation(str(action.actor_ref), str(action.patient_ref), "remains_collection" if dead(str(action.patient_ref)) else "rescue_contact", str(action.input_ref))
		_emit(str(action.patient_ref), "personal_picked_up", str(action.input_ref), {"carrier_ref": action.actor_ref, "movement_ref": action.movement_ref})
		if action.has("rescue_ref"):
			member.state = "STATIONARY"
			local_rescues[action.actor_ref].status = "CARRYING"
			_state.gameplay_port.get_ref().tactics.body_action_finished(str(action.actor_ref), str(action.id), "EXECUTED")
		elif action.has("remains_route"):
			patient.remains.status = "COLLECTED"
			_route_leg(str(action.actor_ref), str(action.input_ref), str(action.remains_route.destination_node), action.remains_route.path)
		else:
			_start(str(action.actor_ref), "pickup_return_" + str(action.id), "RETURNING", _space.xy(_state.units[action.unit_id]), "")
		return {"changed": [action.unit_id], "retired": [], "record": action.duplicate(true)}
	member.xy = action.to.duplicate()
	member.state = "COVERED" if action.mode == "ENTERING" else "FOLLOWING"
	member.cover_ref = action.cover_ref
	member.action_ref = ""
	action.status = "EXECUTED"
	_state.wake(str(_state.units[action.unit_id].area_id))
	_state.gameplay_port.get_ref().tactics.body_action_finished(str(action.actor_ref), str(action.id), "EXECUTED")
	_emit(str(action.actor_ref), "personal_action_finished", str(action.input_ref), {"state": member.state, "xy": member.xy})
	return {"changed": [action.unit_id], "retired": [], "record": action.duplicate(true)}

func prepare(unit: Dictionary, plan: Dictionary) -> void:
	if not has_unit(str(unit.id)):
		return
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var ledger: Dictionary = unit.gameplay_personnel
	var members: Dictionary = {}
	var weighted: float = float(ledger.anonymous)
	var exposure_capacity: float = float(ledger.anonymous)
	var occupied: float = 0.0
	var regrouping: bool = false
	for actor: String in State.sorted_ids(ledger.members):
		work.member_preparations += 1
		var member: Dictionary = ledger.members[actor]
		if member.state in ["LOCAL_MOVING", "LOCAL_ENTERING"] and body_suppression(actor) >= float(_state.missions[unit.mission_id].stop_suppression):
			interrupt_action(actor, "actual_local_pressure")
		var sheltered: bool = _covers.has(member.cover_ref) and _distance(position(actor), _covers[member.cover_ref].xy) <= 0.000001
		var weapon: Dictionary = _state.gameplay_port.get_ref().tactics.weapons.get(actor, {})
		var exposed_action: bool = weapon.get("mode", "") in ["FIRE", "WATCH"] or weapon.get("mode", "") == "GROUP" and weapon.get("status", "") in ["READY", "AIMING"] and weapon.get("group_target", "") != "" or float(member.get("combat_busy_until", 0.0)) > _state.time
		var factor: float = (maxf(_cover_factor(str(member.cover_ref)), 0.65) if exposed_action else _cover_factor(str(member.cover_ref))) if sheltered else 1.0
		if sheltered and _space._local_position_refs.has(member.cover_ref) and _space.entered_local_cover(body_spatial(actor)) > 0.0:
			factor = 1.0 # The same registered cover is already in spatial terrain.
		# Incapacity removes fighting capacity, but a living body can still be hit.
		var grouped: bool = _distance(position(actor), _space.xy(unit)) <= float(rules.local_radius_km) and not _state.gameplay_port.get_ref().tactics.separated_actor(actor)
		var exposed: float = (maxf(float(member.health), 1.0) if not member.actionable else float(member.health)) if member.life_state != "DEAD" and grouped else 0.0
		members[actor] = {"health": member.health, "factor": factor, "exposed": exposed, "requested": 0.0, "damage_owner": "GROUP" if grouped else "BODY"}
		weighted += exposed * factor
		exposure_capacity += exposed
		if not grouped or not str(member.get("carrying_ref", "")).is_empty() or member.state in ["AMMO_HANDLING", "PUTTING_DOWN", "PICKING_UP", "MEDICATING", "PLACING_REMAINS", "ENTERING", "RETURNING", "RELOCATING", "LOCAL_MOVING", "LOCAL_ENTERING"] or float(member.get("combat_busy_until", 0.0)) > _state.time:
			occupied += float(member.health)
		regrouping = regrouping or member.actionable and grouped and member.state != "FOLLOWING" and not member.has("command_post")
	plan.personal_ledger = {"effective": unit.effective, "anonymous": ledger.anonymous, "anonymous_requested": 0.0,
		"members": members, "base_exposure": plan.exposure, "exposure_capacity": exposure_capacity, "regrouping": regrouping,
		"group_capacity": maxf(0.0, float(unit.effective) - occupied), "events": []}
	plan.commitment *= maxf(0.0, 1.0 - occupied / maxf(0.000001, float(unit.effective)))
	plan.exposure *= weighted / maxf(0.000001, exposure_capacity)
	if measure_cost:
		cost_usec.prepare += Time.get_ticks_usec() - started

func constrain_movement(plan: Dictionary) -> void:
	if plan.has("personal_ledger") and (plan.personal_ledger.regrouping or float(plan.personal_ledger.group_capacity) <= 0.000001):
		plan.speed = 0.0
	elif plan.has("personal_ledger"):
		for actor: String in plan.personal_ledger.members:
			if not str(_member(actor).get("carrying_ref", "")).is_empty():
				plan.speed *= float(rules.carry_speed_factor)
				break

func incoming(plan: Dictionary, dose: float) -> void:
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var ledger: Dictionary = plan.personal_ledger
	var per_capacity: float = dose * float(ledger.base_exposure) / maxf(0.000001, float(ledger.exposure_capacity))
	ledger.anonymous_requested += per_capacity * float(ledger.anonymous)
	for actor: String in State.sorted_ids(ledger.members):
		work.member_allocations += 1
		if ledger.members[actor].damage_owner != "GROUP":
			continue
		ledger.members[actor].requested += per_capacity * float(ledger.members[actor].exposed) * float(ledger.members[actor].factor)
	if measure_cost:
		cost_usec.allocation += Time.get_ticks_usec() - started

func settle(unit: Dictionary, plan: Dictionary) -> float:
	if plan.get("action_parts", false):
		return 0.0 # Anonymous losses are adopted by their actual part, bodies by BODY.
	var started: int = Time.get_ticks_usec() if measure_cost else 0
	var requests: Dictionary = plan.personal_ledger
	var ledger: Dictionary = unit.gameplay_personnel
	var anonymous_loss: float = minf(float(requests.anonymous), float(requests.anonymous_requested))
	ledger.anonymous = float(requests.anonymous) - anonymous_loss
	var total: float = anonymous_loss
	var named_losses: Dictionary = {}
	var allocation_id: String = str(requests.get("cause_ref", "allocation_%.9f_%s" % [_state.time, unit.id]))
	for actor: String in State.sorted_ids(requests.members):
		work.member_settlements += 1
		var hit: float = float(requests.members[actor].requested)
		if requests.members[actor].damage_owner != "GROUP" or dead(actor) or hit <= 0.0:
			continue
		var event: Dictionary = hurt(actor, hit, allocation_id, "shared_incoming_fire")
		var loss: float = float(event.detail.new_capacity_loss)
		total += loss
		named_losses[actor] = loss
		requests.events.append(event)
	if _state.materialization_port.get_ref()._groups.has(unit.id):
		settle_sparse(unit, anonymous_loss, named_losses)
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

func after_movement(unit: Dictionary, plan: Dictionary) -> void:
	if not plan.has("personal_ledger"):
		return
	for event: Dictionary in plan.personal_ledger.events:
		var actor: String = str(event.actor)
		var body: Dictionary = _member(actor)
		if event.followed and not body.actionable:
			body.xy = _space.xy(unit)
			body.anchor_node = str(unit.spatial.node)
			body.anchor_edge = str(unit.spatial.edge)
			_bind_body_local(body, unit.spatial)
			if dead(actor):
				body.remains.death_xy = body.xy.duplicate()
		if body.life_state == "DEAD" and body.has("carrier_ref") and body.get("transport_kind", "") != "REMAINS":
			release_transport(actor, "INTERRUPTED", "death_" + actor)
		var patient: String = str(body.get("carrying_ref", ""))
		if (not body.actionable or float(body.health) < float(rules.minimum_carrier_health)) and _units.has(patient):
			body.xy = position(actor)
			_member(patient).xy = body.xy.duplicate()
			_member(patient).anchor_node = body.anchor_node
			if not str(body.action_ref).is_empty():
				_actions[body.action_ref].status = "INTERRUPTED"
				body.action_ref = ""
			if body.actionable:
				body.state = "STATIONARY"
			release_transport(patient, "INTERRUPTED", "carrier_loss_" + actor)
		_emit(actor, str(event.kind), str(event.get("cause_ref", "fire_segment_%.6f" % _state.time)), event.detail)
		if requires_detail(str(_units[actor])) and _state.materialization_port.get_ref().representation_of(str(_units[actor])) != _units[actor]:
			var id: String = "personal_detail_" + actor + "_" + str(_serial)
			var due: float = _state.time + 0.000001
			_detail_tickets[id] = {"actor": actor, "due": due}
			assert(_state.schedule_event(id, due, "gameplay", {"person_id": actor}))

func coalesced(images: Dictionary, aggregate: Dictionary, group: Dictionary) -> void:
	var named: bool = false
	for unit: Dictionary in images.values():
		named = named or unit.has("gameplay_personnel")
	if not named:
		return
	aggregate.gameplay_personnel = {"anonymous": 0.0, "members": {}}
	group.personnel_leaves = {}
	for id: String in images:
		var unit: Dictionary = images[id]
		var anonymous: float = float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))
		group.personnel_leaves[id] = {"anonymous": anonymous, "casualties": unit.casualties, "personnel_recovered": unit.personnel_recovered}
		aggregate.gameplay_personnel.anonymous += anonymous
		for actor: String in unit.get("gameplay_personnel", {}).get("members", {}):
			aggregate.gameplay_personnel.members[actor] = _member(actor)

func project_personnel(id: String, result: Dictionary, group: Dictionary) -> void:
	if not group.has("personnel_leaves"):
		return
	var leaf: Dictionary = group.personnel_leaves[id]
	var members: Dictionary = {}
	var effective: float = float(leaf.anonymous)
	for actor: String in group.leaf_refs[id].get("gameplay_personnel", {}).get("members", {}):
		members[actor] = _member(actor).duplicate(true)
		effective += float(_member(actor).health)
	result.effective = effective
	result.casualties = leaf.casualties
	result.personnel_recovered = leaf.personnel_recovered
	if not members.is_empty():
		result.gameplay_personnel = {"anonymous": leaf.anonymous, "members": members}

func materialized(id: String, result: Dictionary, macro: Dictionary, group: Dictionary) -> void:
	if not group.has("personnel_leaves"):
		return
	macro.gameplay_personnel.anonymous -= float(group.personnel_leaves[id].anonymous)
	for actor: String in result.get("gameplay_personnel", {}).get("members", {}):
		result.gameplay_personnel.members[actor] = _member(actor)
		macro.gameplay_personnel.members.erase(actor)
	group.personnel_leaves.erase(id)

func settle_sparse(unit: Dictionary, anonymous_loss: float, named_losses: Dictionary) -> void:
	var changed: bool = anonymous_loss > 0.0
	for loss: float in named_losses.values():
		changed = changed or loss > 0.0
	if not changed:
		return
	var leaves: Dictionary = _state.materialization_port.get_ref()._groups[unit.id].personnel_leaves
	var anonymous: float = 0.0
	for leaf: Dictionary in leaves.values():
		anonymous += float(leaf.anonymous)
	for leaf: Dictionary in leaves.values():
		var loss: float = anonymous_loss * float(leaf.anonymous) / anonymous if anonymous > 0.0 else 0.0
		leaf.anonymous -= loss
		leaf.casualties += loss
	for actor: String in named_losses:
		leaves[_units[actor]].casualties += float(named_losses[actor])

func validate_extended(actor: String, values: Dictionary) -> Dictionary:
	if values.get("action", "") == "rescue":
		return validate_rescue(actor, values)
	if values.has("local_path") or values.has("local_action"):
		return _validate_local_action(actor, values)
	if _state.gameplay_port.get_ref().tactics.manoeuvre_active(str(_units.get(actor, ""))):
		return _reject("regroup_road_task_before_separate_personal_route")
	if not _units.has(actor) or not can_intend(actor) or _member(actor).state not in ["FOLLOWING", "COVERED", "STATIONARY"] or _actions.size() >= MAX_ACTIONS - 16:
		return _reject("existing_available_body_required")
	var leaves: Array[String] = [str(_units[actor])]
	var mode: String = str(values.get("action", ""))
	if mode == "place_remains":
		if values.size() != 2 or not values.get("person_ref") is String or not dead(str(values.person_ref)) or _member(str(values.person_ref)).has("carrier_ref") or _member(str(values.person_ref)).remains.status == "PLACED" or _distance(position(actor), position(str(values.person_ref))) > float(rules.local_radius_km):
			return _reject("actual_nearby_remains_required")
		return _structure._members._representation_capacity(leaves)
	if mode not in ["relocate", "collect_remains"] or values.size() != (4 if mode == "collect_remains" else 3) or not values.get("destination_node") is String or not values.get("path") is Array or values.path.size() > 16:
		return _reject("explicit_bounded_personal_ground_route_required")
	var here: Dictionary = body_spatial(actor)
	if _space.local_place(here) != "node:" + str(here.node) or str(here.get("local_edge", "")) != "":
		return _reject("actual_local_return_to_road_access_before_personal_route")
	if mode == "collect_remains":
		if not values.get("person_ref") is String:
			return _reject("explicit_remains_identity_required")
		var valid: Dictionary = transport_check(str(values.person_ref), actor, false, true)
		if not valid.ok:
			return valid
	var g: RefCounted = _state.gameplay_port.get_ref()
	if values.path not in g._known.get(actor, {}).get(str(values.destination_node), []):
		return _reject("person_requires_known_ground_route")
	var node: String = str(_physical_unit(actor).spatial.node) if _member(actor).state == "FOLLOWING" else str(_member(actor).anchor_node)
	if _distance(position(actor), _space._nodes[node].xy) > float(rules.local_radius_km):
		return _reject("person_must_reach_known_route_start")
	var point: String = node
	for edge_id: Variant in values.path:
		if not edge_id is String or not _space._edges.has(edge_id):
			return _reject("unknown_personal_route_edge")
		var edge: Dictionary = _space._edges[edge_id]
		if not edge.open or "FOOT" not in edge.modes or point not in [edge.from, edge.to] or _space.movement_factor(edge.ground, "FOOT") <= 0.0:
			return _reject("personal_ground_route_not_executable")
		point = str(edge.to if point == edge.from else edge.from)
	if point != values.destination_node:
		return _reject("personal_route_destination_mismatch")
	return _structure._members._representation_capacity(leaves)

func apply_extended(actor: String, id: String, values: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_extended(actor, values)
	if not valid.ok:
		return valid
	if values.get("action", "") == "rescue":
		return apply_rescue(actor, id, values)
	if values.has("local_path") or values.has("local_action"):
		return _apply_local_action(actor, id, values)
	var representation: Dictionary = _state.materialization_port.get_ref().materialize_leaf(str(_units[actor]), "precise_personal_ground_action")
	var member: Dictionary = _member(actor)
	if member.state == "FOLLOWING":
		member.anchor_node = str(_physical_unit(actor).spatial.node)
	if values.action == "place_remains":
		_start(actor, id, "PLACING_REMAINS", position(actor), "", 30.0)
		_actions[member.action_ref].person_ref = values.person_ref
	elif values.action == "collect_remains":
		var corpse: String = str(values.person_ref)
		_member(corpse).transport_kind = "REMAINS"
		start_transport(corpse, actor, "remains_" + id, id)
		_actions[member.action_ref].remains_route = values.duplicate(true)
	else:
		member.xy = position(actor)
		member.state = "STATIONARY"
		_route_leg(actor, id, str(values.destination_node), values.path)
	var changed: Array = representation.get("changed", [])
	if _units[actor] not in changed:
		changed.append(_units[actor])
	return {"ok": true, "status": member.state, "changed": changed, "retired": representation.get("retired", [])}

func _validate_local_action(actor: String, values: Dictionary, carrying: bool = false) -> Dictionary:
	if values.get("action", "") != "relocate" or not _units.has(actor) or _actions.size() >= MAX_ACTIONS - 16:
		return _reject("own_available_body_outside_active_part_task_required")
	var tactics: RefCounted = _state.gameplay_port.get_ref().tactics
	if tactics.manoeuvre_active(str(_units[actor])) and tactics.manoeuvres[_units[actor]].phase != "STOPPED":
		return _reject("stop_part_task_before_individual_local_support")
	var body: Dictionary = _member(actor)
	var action: String = str(values.get("local_action", "move"))
	if action == "stop":
		return {"ok": true} if values.size() == 2 and _actions.get(body.action_ref, {}).get("mode", "") in ["LOCAL_MOVING", "LOCAL_ENTERING"] else _reject("existing_personal_local_action_required")
	if (not can_intend(actor) and not (carrying and body.actionable and float(body.health) >= float(rules.minimum_carrier_health) and _units.has(str(body.get("carrying_ref", ""))))) or not str(body.action_ref).is_empty() or _physical_unit(actor).spatial.mode != "FOOT":
		return _reject("able_stationary_foot_body_without_other_work_required")
	var here: Dictionary = body_spatial(actor)
	if action == "return":
		return {"ok": true} if values.size() == 2 and _space._local_edges.has(here.get("local_edge", "")) else _reject("actual_occupied_local_leg_required")
	if action == "enter":
		return {"ok": true} if values.size() == 2 and _space.local_enterable(here) else _reject("actual_usable_local_site_required")
	if action != "move" or values.size() != 3 or not values.get("local_path") is Array or values.local_path.is_empty() or values.local_path.size() > 4 or not values.get("destination_ref") is String or str(here.get("local_edge", "")) != "" or str(here.edge) != "":
		return _reject("bounded_personal_local_path_and_actual_access_required")
	if not _space.local_arrived(here, _space.local_place(here)) or _space.local_path_end(_space.local_place(here), values.local_path) != values.destination_ref or values.local_path not in _state.gameplay_port.get_ref()._known.get(actor, {}).get("local:" + str(values.destination_ref), []):
		return _reject("own_known_connected_local_route_required")
	return {"ok": true}

func _known_patient(observer: String, patient: String) -> bool:
	if not visible_person(observer, patient).is_empty():
		return true
	for claim: Dictionary in _state.information_port.get_ref().knowledge(observer).get("entries", []):
		if claim.subject_ref == patient and claim.fact_kind == "person_status" and float(claim.reliability) > 0.0:
			return true
	return false

func _rescue_route(values: Dictionary) -> Dictionary:
	if values.get("rescue_action", "") == "return":
		return {"action": "relocate", "local_action": "return"}
	return {"action": "relocate", "local_path": values.get("local_path", []), "destination_ref": values.get("destination_ref", "")}

func validate_rescue(actor: String, values: Dictionary, issuer: String = "") -> Dictionary:
	if values.get("action", "") != "rescue":
		return _reject("explicit_local_rescue_action_required")
	if issuer.is_empty():
		issuer = actor
	if not _units.has(actor) or _actions.size() >= MAX_ACTIONS - 16 or not _member(actor).actionable or float(_member(actor).health) < float(rules.minimum_carrier_health) or _physical_unit(actor).spatial.mode != "FOOT":
		return _reject("existing_able_foot_helper_required")
	for field: String in values:
		if field not in ["action", "rescue_action", "patient_ref", "local_path", "destination_ref", "path", "destination_node", "pickup_on_arrival"]:
			return _reject("unsupported_local_rescue_field")
	if values.has("pickup_on_arrival") and not values.pickup_on_arrival is bool:
		return _reject("explicit_pickup_after_approach_choice_required")
	var mode: String = str(values.get("rescue_action", "approach"))
	var body: Dictionary = _member(actor)
	var current: Dictionary = local_rescues.get(actor, {})
	var tactics: RefCounted = _state.gameplay_port.get_ref().tactics
	if tactics.manoeuvre_active(str(_units[actor])) and tactics.manoeuvres[_units[actor]].phase != "STOPPED":
		return _reject("stop_part_motion_before_assigning_helper")
	if mode == "stop":
		return {"ok": true} if _actions.get(body.action_ref, {}).get("rescue_ref", "") == current.get("id", "missing") and not current.is_empty() else _reject("existing_owned_rescue_motion_required")
	if not str(body.action_ref).is_empty() or float(body.get("combat_busy_until", 0.0)) > _state.time or tactics.weapons.get(actor, {}).get("status", "") in ["AIMING", "RELOADING"] or tactics._carried_amount(actor) > 0.000001:
		return _reject("helper_has_unfinished_body_weapon_or_ammunition_duty")
	var patient: String = str(values.get("patient_ref", body.get("carrying_ref", "")))
	if mode in ["approach", "pickup"]:
		if not can_intend(actor) or not _units.has(patient) or _units[patient] != _units[actor] or patient == actor or not _known_patient(issuer, patient) or _member(patient).get("rescue_carrier_ref", actor) != actor:
			return _reject("known_existing_same_group_patient_without_other_rescuer_required")
		if mode == "pickup":
			return transport_check(patient, actor, false, false, true)
		return _validate_local_action(actor, _rescue_route(values))
	if mode not in ["carry", "return", "put_down", "road"] or not _units.has(patient):
		return _reject("explicit_existing_local_patient_transport_required")
	var picked: Dictionary = transport_check(patient, actor, true)
	if not picked.ok:
		return picked
	if current.get("patient_ref", "") != patient:
		return _reject("existing_local_rescue_responsibility_required")
	if mode == "put_down":
		return {"ok": true}
	if mode in ["carry", "return"]:
		return _validate_local_action(actor, _rescue_route(values), true)
	var here: Dictionary = body_spatial(actor)
	if _space.local_place(here) != "node:" + str(here.node) or str(here.get("local_edge", "")) != "" or str(here.edge) != "" or _distance(position(actor), _space._nodes[here.node].xy) > 0.000001:
		return _reject("actual_road_access_required_before_existing_evacuation")
	if not values.get("path") is Array or values.path.is_empty() or values.path.size() > 16 or not values.get("destination_node") is String or values.path not in _state.gameplay_port.get_ref()._known.get(issuer, {}).get(str(values.destination_node), []):
		return _reject("explicit_known_bounded_evacuation_road_route_required")
	var node: String = str(here.node)
	for reference: Variant in values.path:
		var edge: Dictionary = _space._edges.get(reference, {})
		if edge.is_empty() or not edge.open or "FOOT" not in edge.modes or node not in [edge.from, edge.to] or _space.movement_factor(edge.ground, "FOOT") <= 0.0:
			return _reject("existing_evacuation_road_not_executable")
		node = str(edge.to if node == edge.from else edge.from)
	return {"ok": true} if node == values.destination_node else _reject("evacuation_destination_mismatch")

func apply_rescue(actor: String, id: String, values: Dictionary, issuer: String = "") -> Dictionary:
	var valid: Dictionary = validate_rescue(actor, values, issuer)
	if not valid.ok:
		return valid
	var mode: String = str(values.get("rescue_action", "approach"))
	if mode == "stop":
		interrupt_action(actor, "received_local_rescue_stop")
		return {"ok": true, "status": "INTERRUPTED", "changed": [_units[actor]], "retired": []}
	var changed: Dictionary = _state.materialization_port.get_ref().materialize_leaf(str(_units[actor]), "local_patient_rescue")
	var body: Dictionary = _member(actor)
	_state.gameplay_port.get_ref().tactics.begin_local_duty(actor)
	var patient: String = str(values.get("patient_ref", body.get("carrying_ref", "")))
	if mode in ["approach", "pickup"]:
		local_rescues[actor] = {"id": id, "issuer": actor if issuer.is_empty() else issuer, "patient_ref": patient, "unit_ref": _units[actor], "started_at": _state.time,
			"status": "APPROACHING", "action_ref": "", "known_destination_ref": values.get("destination_ref", ""), "path": values.get("local_path", []).duplicate(), "pickup_on_arrival": values.get("pickup_on_arrival", true)}
		_member(patient).rescue_carrier_ref = actor
		_member(patient).transport_ref = id
		_member(patient).transport_status = "LOCAL_APPROACH_ASSIGNED"
		if mode == "pickup":
			_start_local_pickup(actor, patient, id)
		else:
			_apply_local_action(actor, id, _rescue_route(values))
	elif mode in ["carry", "return"]:
		local_rescues[actor].status = "CARRYING"
		local_rescues[actor].path = values.get("local_path", []).duplicate()
		_apply_local_action(actor, id, _rescue_route(values))
	elif mode == "put_down":
		_start(actor, id, "PUTTING_DOWN", position(actor), "", float(rules.minimum_seconds))
		_actions[body.action_ref].patient_ref = patient
		_actions[body.action_ref].rescue_ref = local_rescues[actor].id
	else:
		local_rescues[actor].status = "ROAD_EVACUATION"
		_route_leg(actor, id, str(values.destination_node), values.path)
	if not str(body.action_ref).is_empty():
		local_rescues[actor].action_ref = body.action_ref
	elif mode in ["approach", "carry", "return"]:
		release_transport(patient, "INTERRUPTED", id)
		local_rescues[actor].reason = "actual_local_motion_could_not_start"
	_emit(actor, "local_rescue_intent", id, {"patient_ref": patient, "stage": mode, "xy": position(actor)})
	return {"ok": true, "status": body.state, "changed": changed.get("changed", [_units[actor]]), "retired": changed.get("retired", [])}

func _start_local_pickup(actor: String, patient: String, id: String) -> void:
	var valid: Dictionary = transport_check(patient, actor, false, false, true)
	if not valid.ok:
		release_transport(patient, "INTERRUPTED", id)
		_emit(actor, "local_rescue_contact_failed", id, {"patient_ref": patient, "reason": valid.error, "xy": position(actor)})
		return
	# No treatment is implied; the original bleeding and care clocks keep running.
	_state.gameplay_port.get_ref().tactics.begin_local_duty(patient)
	_state.information_port.get_ref().record_person_observation(self, actor, patient, id + "_contact_" + str(_serial))
	start_transport(patient, actor, id, id)
	_actions[_member(actor).action_ref].rescue_ref = local_rescues[actor].id
	local_rescues[actor].status = "PICKUP_PENDING"
	local_rescues[actor].action_ref = _member(actor).action_ref

func _apply_local_action(actor: String, id: String, values: Dictionary) -> Dictionary:
	var body: Dictionary = _member(actor)
	var action: String = str(values.get("local_action", "move"))
	if action == "stop":
		interrupt_action(actor, "received_local_stop")
		return {"ok": true, "status": body.state, "changed": [_units[actor]], "retired": []}
	var representation: Dictionary = _state.materialization_port.get_ref().materialize_leaf(str(_units[actor]), "actual_local_body_motion")
	_state.gameplay_port.get_ref().tactics.begin_local_duty(actor)
	var here: Dictionary = body_spatial(actor)
	body.xy = position(actor)
	body.anchor_node = here.node
	body.state = "STATIONARY"
	for field: String in ["local_ref", "local_edge", "local_from", "local_to", "local_progress", "local_returning", "entered_site_ref"]:
		if here.has(field):
			body[field] = here[field]
	if action == "enter":
		_start_local_entry(actor, id)
	elif action == "return":
		_start_local_leg(actor, id, str(body.local_from), [body.local_edge], true)
	else:
		_start_local_leg(actor, id, str(values.destination_ref), values.local_path)
	return {"ok": true, "status": body.state, "changed": representation.get("changed", [_units[actor]]), "retired": representation.get("retired", [])}

func _start_local_leg(actor: String, id: String, destination: String, path: Array, returning: bool = false) -> void:
	var body: Dictionary = _member(actor)
	var unit: Dictionary = _physical_unit(actor)
	var edge_id: String = str(path[0])
	var edge: Dictionary = _space._local_edges[edge_id]
	var here: Dictionary = body_spatial(actor)
	if not edge.open and not returning:
		_emit(actor, "personal_local_blocked", id, {"link_ref": edge_id, "xy": position(actor)})
		return
	var from: String = str(here.local_from) if returning else _space.local_place(here)
	var to: String = str(edge.to if from == edge.from else edge.from)
	var progress: float = float(here.get("local_progress", 0.0)) if returning else 0.0
	var end_progress: float = 0.0 if returning else float(edge.length_km)
	var arrival: String = from if returning else to
	var speed: float = minf(float(rules.local_speed_km_s), float(unit.mobility) / 60.0) * float(body.health) * _space.movement_factor(edge.ground, "FOOT")
	speed *= minf(1.0, float(edge.ground.width))
	speed *= float(unit.readiness) * (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression)) * (1.0 - body_suppression(actor))
	if not str(body.get("carrying_ref", "")).is_empty():
		speed *= float(rules.carry_speed_factor)
	elif _state.gameplay_port.get_ref().tactics._carried_amount(actor) > 0.000001:
		speed *= float(rules.carry_speed_factor)
	if speed <= 0.00000001 or body_suppression(actor) >= float(_state.missions[unit.mission_id].stop_suppression):
		_emit(actor, "personal_local_blocked", id, {"link_ref": edge_id, "reason": "actual_mobility_or_pressure", "xy": position(actor)})
		return
	_structure.vacate_node(str(_structure._person_positions.get(actor, "")), "person_body_departed", id)
	_start(actor, id + "_local_%d" % _serial, "LOCAL_MOVING", _space.local_endpoint(arrival).xy, "", absf(end_progress - progress) / speed)
	var ticket: Dictionary = _actions[body.action_ref]
	ticket.input_ref = id
	ticket.local_edge_ref = edge_id
	ticket.start_progress_km = progress
	ticket.end_progress_km = end_progress
	ticket.destination_ref = arrival
	ticket.destination = destination
	ticket.path = [] if returning else path.slice(1)
	ticket.start_health = body.health
	ticket.returning = returning
	if local_rescues.get(actor, {}).get("status", "") in ["APPROACHING", "CARRYING"]:
		ticket.rescue_ref = local_rescues[actor].id
		local_rescues[actor].action_ref = ticket.id
	body.local_ref = from
	body.local_edge = edge_id
	body.local_from = from
	body.local_to = to
	body.local_progress = progress
	body.local_returning = returning
	body.erase("entered_site_ref")
	body.cover_ref = ""

func _start_local_entry(actor: String, id: String) -> void:
	var body: Dictionary = _member(actor)
	var here: Dictionary = body_spatial(actor)
	if not _space.local_enterable(here):
		_emit(actor, "personal_position_unavailable", id, {"site_ref": _space.local_place(here)})
		return
	_start(actor, id + "_entry_%d" % _serial, "LOCAL_ENTERING", position(actor), "", float(_space._local_sites[_space.local_place(here)].enter_seconds))
	_actions[body.action_ref].site_ref = _space.local_place(here)

func _complete_local_action(action: Dictionary) -> Dictionary:
	var actor: String = str(action.actor_ref)
	var body: Dictionary = _member(actor)
	if action.mode == "LOCAL_ENTERING" and not _space.local_enterable(body_spatial(actor)):
		interrupt_action(actor, "position_damaged_during_entry")
		return {"changed": [action.unit_id], "retired": [], "record": {"status": "INTERRUPTED", "id": action.id}}
	_settle_road_action(actor, action)
	body.xy = action.to.duplicate()
	body.state = "STATIONARY"
	body.action_ref = ""
	action.status = "EXECUTED"
	if action.mode == "LOCAL_MOVING":
		body.local_ref = action.destination_ref
		body.local_edge = ""
		body.local_progress = 0.0
		body.local_returning = false
		body.anchor_node = _space.local_endpoint(str(action.destination_ref)).node_ref
		body.anchor_edge = ""
	else:
		body.entered_site_ref = action.site_ref
	_state.gameplay_port.get_ref().tactics.body_action_finished(actor, str(action.id), "EXECUTED")
	_emit(actor, "personal_local_arrived" if action.mode == "LOCAL_MOVING" else "personal_position_entered", str(action.input_ref), {"site_ref": _space.local_place(body_spatial(actor)), "xy": body.xy})
	if action.mode == "LOCAL_MOVING":
		if not action.path.is_empty():
			_start_local_leg(actor, str(action.input_ref), str(action.destination), action.path)
		elif action.has("rescue_ref") and local_rescues.get(actor, {}).get("id", "") == action.rescue_ref:
			var rescue: Dictionary = local_rescues[actor]
			if rescue.status == "APPROACHING":
				if rescue.pickup_on_arrival:
					_start_local_pickup(actor, str(rescue.patient_ref), str(rescue.id))
				else:
					rescue.status = "CONTACT_REACHED"
					_state.information_port.get_ref().record_person_observation(self, actor, str(rescue.patient_ref), str(rescue.id) + "_contact_" + str(_serial))
			else:
				rescue.status = "ARRIVED_CARRYING"
				_emit(actor, "local_patient_arrived", str(rescue.id), {"patient_ref": rescue.patient_ref, "xy": position(actor), "requires_put_down_or_road_handover": true})
		elif _space._local_sites.has(str(action.destination_ref)):
			_start_local_entry(actor, str(action.input_ref))
	return {"changed": [action.unit_id], "retired": [], "record": {"kind": action.mode, "person_ref": actor, "status": "EXECUTED"}}

func interrupt_local_edge(reference: String) -> void:
	if not _space._local_edges.has(reference) or _space._local_edges[reference].open:
		return
	for actor: String in _bodies:
		var body: Dictionary = _member(actor)
		var action: Dictionary = _actions.get(body.action_ref, {})
		if action.get("mode", "") == "LOCAL_MOVING" and action.get("local_edge_ref", "") == reference and not action.get("returning", false):
			interrupt_action(actor, "actual_local_link_closed")

func _route_leg(actor: String, id: String, destination: String, path: Array, stop_node: String = "", manoeuvre_ref: String = "") -> void:
	var member: Dictionary = _member(actor)
	if path.is_empty():
		member.state = "STATIONARY"
		if not str(member.get("carrying_ref", "")).is_empty():
			release_transport(str(member.carrying_ref), "HANDED_OVER", id)
		return
	var edge_id: String = str(path[0])
	var edge: Dictionary = _space._edges[edge_id]
	var returning: bool = not manoeuvre_ref.is_empty() and _state.gameplay_port.get_ref().tactics.manoeuvres.get(str(_units[actor]), {}).get("returning", false)
	if not edge.open and not returning or "FOOT" not in edge.modes:
		member.state = "STATIONARY"
		if not str(member.get("carrying_ref", "")).is_empty():
			release_transport(str(member.carrying_ref), "INTERRUPTED", id)
		_emit(actor, "personal_route_blocked", id, {"edge_ref": edge_id})
		return
	var next: String = stop_node if stop_node != "" else str(edge.to if member.anchor_node == edge.from else edge.from)
	var point: Dictionary = _space.road_point(edge_id, position(actor))
	if point.is_empty() and manoeuvre_ref.is_empty():
		# Keep the existing near-node personal approach contract. A new group
		# section, in contrast, must explain its point on the actual road.
		point = {"progress_km": 0.0 if member.anchor_node == edge.from else float(edge.length_km)}
	if next not in [edge.from, edge.to] or point.is_empty():
		member.state = "STATIONARY"
		_emit(actor, "personal_route_blocked", id, {"edge_ref": edge_id, "reason": "unexplained_road_position"})
		return
	var speed: float = float(rules.local_speed_km_s) * float(member.health) * _space.movement_factor(edge.ground, "FOOT")
	_bind_body_local(member, {}) # A validated road leg starts at actual road access.
	if not manoeuvre_ref.is_empty():
		var unit: Dictionary = _physical_unit(actor)
		speed = minf(float(rules.local_speed_km_s), float(unit.mobility) / 60.0) * float(member.health) * _space.movement_factor(edge.ground, "FOOT")
		speed *= float(unit.readiness) * (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
		speed *= 1.0 - body_suppression(actor)
	if not str(member.get("carrying_ref", "")).is_empty():
		speed *= float(rules.carry_speed_factor)
	_structure.vacate_node(str(_structure._person_positions.get(actor, "")), "person_body_departed", id)
	if speed <= 0.00000001:
		member.state = "STATIONARY"
		if not str(member.get("carrying_ref", "")).is_empty():
			release_transport(str(member.carrying_ref), "INTERRUPTED", id)
		return
	var remaining: float = float(point.progress_km) if next == edge.from else float(edge.length_km) - float(point.progress_km)
	_start(actor, id + "_leg_%d" % _serial, "RELOCATING", _space._nodes[next].xy, "", remaining / speed)
	var action: Dictionary = _actions[member.action_ref]
	action.input_ref = id
	action.edge_ref = edge_id
	action.road_from = edge.from
	action.road_to = edge.to
	action.start_progress_km = point.progress_km
	action.end_progress_km = 0.0 if next == edge.from else float(edge.length_km)
	action.manoeuvre_ref = manoeuvre_ref
	action.start_health = member.health
	member.anchor_edge = edge_id
	action.destination_node = next
	action.destination = destination
	action.path = path.slice(1)
	if not str(member.get("carrying_ref", "")).is_empty():
		action.remains_ref = member.carrying_ref
		if local_rescues.get(actor, {}).get("patient_ref", "") == member.carrying_ref:
			action.rescue_ref = local_rescues[actor].id
			local_rescues[actor].action_ref = action.id

func interrupt_edge(edge_id: String) -> void:
	if not _space._edges.has(edge_id) or _space._edges[edge_id].open:
		return
	for actor: String in _bodies:
		var body: Dictionary = _member(actor)
		if body.state != "RELOCATING" or _actions[body.action_ref].edge_ref != edge_id:
			continue
		var action: Dictionary = _actions[body.action_ref]
		body.xy = position(actor)
		_settle_road_action(actor, action)
		body.state = "STATIONARY"
		body.action_ref = ""
		action.status = "INTERRUPTED"
		action.interrupted_at = _state.time
		_state.gameplay_port.get_ref().tactics.body_action_finished(actor, str(action.id), "INTERRUPTED")
		if not str(body.get("carrying_ref", "")).is_empty():
			release_transport(str(body.carrying_ref), "INTERRUPTED", str(action.input_ref))
		_emit(actor, "personal_route_blocked", str(action.input_ref), {"edge_ref": edge_id, "xy": body.xy})

func road_position(actor: String) -> Dictionary:
	var body: Dictionary = _member(actor)
	var edge: String = str(_physical_unit(actor).spatial.edge) if body.state == "FOLLOWING" else str(body.get("anchor_edge", ""))
	if edge == "":
		return {"node_ref": _physical_unit(actor).spatial.node if body.state == "FOLLOWING" else body.anchor_node, "edge_ref": "", "xy": position(actor)}
	return _space.road_point(edge, position(actor))

func _settle_road_action(actor: String, action: Dictionary) -> void:
	if action.get("mode", "") not in ["RELOCATING", "LOCAL_MOVING"] or action.get("road_settled", false):
		return
	var body: Dictionary = _member(actor)
	var seconds: float = maxf(0.0, minf(_state.time, float(action.due)) - float(action.started_at))
	var fraction: float = clampf(seconds / maxf(0.000001, float(action.due) - float(action.started_at)), 0.0, 1.0)
	var length: float = absf(float(action.get("end_progress_km", 0.0)) - float(action.get("start_progress_km", 0.0)))
	body.distance_moved = float(body.get("distance_moved", 0.0)) + length * fraction
	body.movement_seconds = float(body.get("movement_seconds", 0.0)) + seconds
	if action.mode == "LOCAL_MOVING":
		body.local_progress = lerpf(float(action.start_progress_km), float(action.end_progress_km), fraction)
	action.road_settled = true
	action.settled_at = _state.time

func position(actor: String) -> Array:
	var member: Dictionary = _member(actor)
	if member.state == "PART_MOVING":
		return member.xy.duplicate()
	if member.state == "FOLLOWING":
		return _space.xy(_physical_unit(actor))
	if member.state == "TRANSPORTED":
		return position(str(member.carrier_ref))
	if member.state in ["ENTERING", "RETURNING", "PICKING_UP", "RELOCATING", "LOCAL_MOVING"]:
		var action: Dictionary = _actions[member.action_ref]
		var fraction: float = clampf((_state.time - float(action.started_at)) / (float(action.due) - float(action.started_at)), 0.0, 1.0)
		return [lerpf(float(action.from[0]), float(action.to[0]), fraction), lerpf(float(action.from[1]), float(action.to[1]), fraction)]
	return member.xy.duplicate()

func hurt(actor: String, dose: float, cause_ref: String, cause: String) -> Dictionary:
	var body: Dictionary = _member(actor)
	if dead(actor) or dose <= 0.0 or body.get("last_damage_ref", "") == cause_ref:
		return {}
	var before: float = float(body.health)
	var loss: float = minf(before, dose)
	var prior: String = str(body.state)
	var here: Array = position(actor)
	body.last_damage_ref = cause_ref
	body.health = before - loss
	body.injury += loss
	body.trauma += maxf(0.0, dose - before)
	body.actionable = float(body.health) > 0.000001
	body.life_state = "WOUNDED" if body.actionable else "INCAPACITATED"
	if body.actionable and prior in ["LOCAL_MOVING", "LOCAL_ENTERING"]:
		interrupt_action(actor, "actual_local_body_injury")
	if not body.actionable:
		_state.gameplay_port.get_ref().tactics.body_action_started(actor)
		body.xy = here
		if prior == "FOLLOWING":
			body.anchor_node = str(_physical_unit(actor).spatial.node)
			body.anchor_edge = str(_physical_unit(actor).spatial.edge)
			_bind_body_local(body, _physical_unit(actor).spatial)
		if not str(body.action_ref).is_empty():
			_settle_road_action(actor, _actions[body.action_ref])
			if prior == "MEDICATING":
				_member(str(_actions[body.action_ref].medical.patient_ref)).treatment.status = "INTERRUPTED"
			_actions[body.action_ref].status = "INTERRUPTED"
			_state.gameplay_port.get_ref().tactics.body_action_finished(actor, str(body.action_ref), "INCAPACITATED")
			body.action_ref = ""
		body.state = "TRANSPORTED" if prior == "TRANSPORTED" else "INCAPACITATED"
		if float(body.trauma) >= float(rules.fatal_trauma):
			body.life_state = "DEAD"
			body.state = "DEAD"
			body.death = {"time": _state.time, "cause": cause, "event_ref": cause_ref, "new_capacity_loss": loss, "trauma": body.trauma}
			body.remains = {"person_ref": actor, "death_time": _state.time, "death_xy": here.duplicate(), "cause_ref": cause_ref, "status": "UNRECOVERED", "found_by": []}
	if medical != null:
		medical.on_hurt(actor, dose, loss, cause_ref, cause)
	if not body.actionable and local_rescues.has(actor):
		var patient: String = str(local_rescues[actor].patient_ref)
		if _member(patient).get("rescue_carrier_ref", "") == actor or _member(patient).get("carrier_ref", "") == actor:
			release_transport(patient, "INTERRUPTED", cause_ref)
	return {"actor": actor, "cause_ref": cause_ref, "kind": "personal_death" if dead(actor) else "personal_injury", "followed": prior in ["FOLLOWING", "TRANSPORTED"],
		"detail": {"before_health": before, "after_health": body.health, "actionable": body.actionable, "life_state": body.life_state,
			"new_capacity_loss": loss, "incoming_damage": dose, "trauma": body.trauma, "cause": cause}}

func external_damage(actor: String, dose: float, cause_ref: String, cause: String) -> Dictionary:
	# Fire/bleeding on a detached body uses its current capacity holder exactly once.
	var event: Dictionary = hurt(actor, dose, cause_ref, cause)
	if event.is_empty():
		return {"changed": [], "retired": []}
	var unit: Dictionary = _physical_unit(actor)
	var loss: float = float(event.detail.new_capacity_loss)
	unit.effective = maxf(0.0, float(unit.effective) - loss)
	unit.casualties += loss
	_state.totals.casualties += loss
	if _state.materialization_port.get_ref()._groups.has(unit.id):
		settle_sparse(unit, 0.0, {actor: loss})
	# No equipment is destroyed merely because a body at another place is wounded.
	after_movement(unit, {"personal_ledger": {"events": [event]}})
	_state.wake(str(unit.area_id))
	return {"changed": [unit.id], "retired": []}

func recover(actor: String, amount: float, cause: String) -> Dictionary:
	if dead(actor):
		return {"changed": [], "retired": []}
	var body: Dictionary = _member(actor)
	var gain: float = minf(maxf(0.0, amount), maxf(0.0, 1.0 - float(body.health)))
	var unit: Dictionary = _physical_unit(actor)
	body.health += gain
	body.recovered = float(body.get("recovered", 0.0)) + gain
	body.actionable = float(body.health) > 0.000001
	body.life_state = "INCAPACITATED" if not body.actionable else ("ABLE" if float(body.health) >= 0.999999 and float(body.trauma) <= 0.000001 else "WOUNDED")
	if body.actionable and body.state == "INCAPACITATED":
		body.state = "STATIONARY"
	unit.effective += gain
	# Preserve the old effective + historical casualties = ledger total contract.
	# Recovery credit identifies the restored part; initial world people stay fixed.
	unit.personnel_total += gain
	unit.personnel_recovered += gain
	_state.totals.personnel_recovered += gain
	if unit.action == "disabled" and float(unit.effective) > _state.materialization_port.get_ref()._kernel._effective_epsilon(_state, unit):
		unit.action = "hold"
	_state.wake(str(unit.area_id))
	_emit(actor, "personal_partial_recovery", cause, {"health": body.health, "restored": gain, "historical_injury": body.injury})
	return {"changed": [unit.id], "retired": []}

func detached_targets(cell: String) -> Dictionary:
	var result: Dictionary = {}
	var cells: Array[String] = _space.scope_cells(cell)
	# This is the bounded local body overlay, never an organization/person scan.
	for actor: String in State.sorted_ids(_bodies):
		var body: Dictionary = _member(actor)
		var unit: Dictionary = _physical_unit(actor)
		if dead(actor) or _distance(position(actor), _space.xy(unit)) <= float(rules.local_radius_km) and not _state.gameplay_port.get_ref().tactics.separated_actor(actor):
			continue
		var node: String = str(_member(str(body.carrier_ref)).anchor_node) if body.state == "TRANSPORTED" else str(body.anchor_node)
		if not _space._nodes.has(node) or str(_space._nodes[node].cell) not in cells:
			continue
		var factor: float = _cover_factor(str(body.cover_ref)) if _covers.has(body.cover_ref) and _distance(position(actor), _covers[body.cover_ref].xy) <= 0.000001 else 1.0
		if _space._local_position_refs.has(body.cover_ref) and _space.entered_local_cover(body_spatial(actor)) > 0.0:
			factor = 1.0
		var weapon: Dictionary = _state.gameplay_port.get_ref().tactics.weapons.get(actor, {})
		if weapon.get("mode", "") in ["FIRE", "WATCH"] or float(body.get("combat_busy_until", 0.0)) > _state.time:
			factor = maxf(factor, 0.65)
		var ground: Dictionary = body_ground(actor)
		var cover: float = minf(float(ground.cover), 0.35) if weapon.get("mode", "") in ["FIRE", "WATCH"] and _space._local_sites.has(_space.local_place(body_spatial(actor))) else float(ground.cover)
		result["body:" + actor] = {"actor_ref": actor, "side": unit.side, "node": node, "sight_ref": _space.sight_ref(body_spatial(actor)), "xy": position(actor), "ground": ground, "weight": 1.0 / maxf(1.0, float(unit.personnel_total)),
			"exposure": (1.15 if body.state in ["RELOCATING", "LOCAL_MOVING", "LOCAL_ENTERING", "PART_MOVING", "PART_ENTERING"] else 0.65) * (1.0 - cover) * factor, "incoming": 0.0, "incoming_pressure": 0.0, "damage_owner": "BODY", "unit_ref": unit.id}
	return result

func body_suppression(actor: String) -> float:
	var body: Dictionary = _member(actor)
	var elapsed: float = maxf(0.0, _state.time - float(body.get("pressure_at", _state.time))) / 60.0
	return float(body.get("local_suppression", 0.0)) * exp(-_state.materialization_port.get_ref()._kernel.SUPPRESSION_DECAY * elapsed)

func body_spatial(actor: String) -> Dictionary:
	var body: Dictionary = _member(actor)
	if body.state == "TRANSPORTED":
		return body_spatial(str(body.carrier_ref))
	if body.state == "FOLLOWING":
		return _physical_unit(actor).spatial.duplicate(true)
	var edge: String = str(body.get("anchor_edge", ""))
	var result: Dictionary = {"node": body.anchor_node, "edge": edge if _space._edges.has(edge) else "", "mode": "FOOT", "point_xy": position(actor)}
	for field: String in ["local_ref", "local_edge", "local_from", "local_to", "local_progress", "local_returning", "entered_site_ref"]:
		if body.has(field):
			result[field] = body[field]
	if body.state == "LOCAL_MOVING" and _actions.has(body.action_ref):
		var action: Dictionary = _actions[body.action_ref]
		var fraction: float = clampf((_state.time - float(action.started_at)) / (float(action.due) - float(action.started_at)), 0.0, 1.0)
		result.local_progress = lerpf(float(action.start_progress_km), float(action.end_progress_km), fraction)
	return result

func body_ground(actor: String) -> Dictionary:
	return _space.terrain({"spatial": body_spatial(actor)})

func visible_person(observer: String, subject: String) -> Dictionary:
	if not _units.has(observer) or not _units.has(subject) or not can_intend(observer) or _distance(position(observer), position(subject)) > float(rules.local_radius_km):
		return {}
	var ground: Dictionary = body_ground(subject)
	var tactics: RefCounted = _state.gameplay_port.get_ref().tactics
	var scene: Dictionary = {"node": body_spatial(subject).node, "sight_ref": _space.sight_ref(body_spatial(subject)), "xy": position(subject), "ground": ground}
	if _space.observation_at(tactics._body_source(observer, float(rules.local_radius_km)), scene) <= 0.0:
		return {}
	if float(ground.visibility) * (1.0 - float(ground.concealment)) <= 0.0:
		return {}
	if dead(subject) and observer not in _member(subject).remains.found_by:
		_member(subject).remains.found_by.append(observer)
		_member(subject).remains.status = "DISCOVERED" if _member(subject).remains.status == "UNRECOVERED" else _member(subject).remains.status
	return {"person_ref": subject, "life_state": _member(subject).life_state, "xy": position(subject),
		"body_status": _member(subject).get("remains", {}).get("status", _member(subject).state)}

func view(actor: String) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if not _units.has(actor):
		return _reject("person_not_in_causal_overlay")
	var result: Dictionary = _member(actor).duplicate(true)
	result.xy = position(actor)
	result.capacity_holder_ref = _units[actor]
	result.body_anchor = {"node_ref": _member(actor).anchor_node, "xy": result.xy.duplicate()}
	result.local_place_ref = _space.local_place(body_spatial(actor))
	result.entered_site_ref = body_spatial(actor).get("entered_site_ref", "")
	result.known_local_places = _state.gameplay_port.get_ref().known_local_places(actor)
	result.following_ref = str(_units[actor]) if result.state == "FOLLOWING" else ""
	result.view = "PERSON_VISIBLE"
	result.representation = "SPARSE_GROUP" if _state.materialization_port.get_ref().representation_of(str(_units[actor])) != _units[actor] else "DETAILED"
	result.time = _state.time
	if _state.gameplay_port.get_ref().tactics.manoeuvre_active(str(_units[actor])):
		var order: Dictionary = _state.gameplay_port.get_ref().tactics.manoeuvres[_units[actor]]
		var part: Dictionary = _state.gameplay_port.get_ref().tactics.roster_part(actor)
		result.road_action = {"id": order.id, "phase": part.get("role", ""), "part_ref": part.get("id", ""), "role": part.get("role", ""), "road": road_position(actor), "travel_kind": order.get("travel_kind", "ROAD"), "local_ref": _space.local_place(part.spatial), "local_edge": part.spatial.get("local_edge", ""), "local_progress_km": part.spatial.get("local_progress", 0.0)}
	result.local_suppression = body_suppression(actor)
	if _state.gameplay_port.get_ref().tactics.ammunition_custody.has(actor):
		result.carried_ammunition = _state.gameplay_port.get_ref().tactics.ammunition_custody[actor].duplicate(true)
	if local_rescues.has(actor):
		result.local_rescue = local_rescues[actor].duplicate(true)
	if _state.gameplay_port.get_ref().tactics.weapons.has(actor):
		result.weapon = _state.gameplay_port.get_ref().tactics.weapons[actor].duplicate(true)
		if result.weapon.get("holder_ref", "") == actor:
			result.weapon.actual_xy = result.xy.duplicate()
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

const RUNTIME_FIELDS: Array[String] = ["_units", "_detail_tickets", "_covers", "_actions", "local_rescues", "_serial", "rules", "work", "debug_calculations"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)

func bind_runtime(state: State, space: RefCounted, structure: RefCounted) -> bool:
	_state = state
	_space = space
	_structure = structure
	_bodies.clear()
	if _units.size() > MAX_PEOPLE or _actions.size() > MAX_ACTIONS or local_rescues.size() > MAX_PEOPLE:
		return false
	for actor: String in _units:
		if not structure._people.has(actor) or not state.knows_unit(str(_units[actor])):
			return false
		var unit: Dictionary = _physical_unit(actor)
		var body: Dictionary = unit.get("gameplay_personnel", {}).get("members", {}).get(actor, {})
		if body.get("actor_ref", "") != actor or body.get("unit_ref", "") != _units[actor]:
			return false
		_bodies[actor] = body
		if not str(body.action_ref).is_empty() and (not _actions.has(body.action_ref) or _actions[body.action_ref].actor_ref != actor or _actions[body.action_ref].status != "PENDING"):
			return false
	for actor: String in _bodies:
		var body: Dictionary = _member(actor)
		if body.has("carrier_ref"):
			var carrier: String = str(body.carrier_ref)
			if not _bodies.has(carrier) or _member(carrier).state == "TRANSPORTED" or _member(carrier).get("carrying_ref", "") != actor or body.state != "TRANSPORTED" or carrier == actor:
				return false
		if body.has("carrying_ref") and (not _bodies.has(body.carrying_ref) or _member(str(body.carrying_ref)).get("carrier_ref", "") != actor):
			return false
		if body.get("local_duty", false) and (not body.get("local_duty_part_ref") is String or body.local_duty_part_ref != body.get("part_ref", "")):
			return false
		if (body.has("local_ref") or str(body.get("local_edge", "")) != "") and not _space.valid_local_spatial(body_spatial(actor)):
			return false
		if body.state in ["LOCAL_MOVING", "LOCAL_ENTERING"]:
			var action: Dictionary = _actions.get(body.action_ref, {})
			if action.get("mode", "") != body.state:
				return false
			if body.state == "LOCAL_MOVING" and (action.get("local_edge_ref", "") != body.get("local_edge", "") or _space.local_endpoint(str(action.get("destination_ref", ""))).is_empty()):
				return false
			if body.state == "LOCAL_ENTERING" and (action.get("site_ref", "") != _space.local_place(body_spatial(actor)) or not _space._local_sites.has(action.get("site_ref", ""))):
				return false
	for actor: String in local_rescues:
		var rescue: Dictionary = local_rescues[actor]
		if not _bodies.has(actor) or not _bodies.has(rescue.get("patient_ref", "")) or rescue.get("unit_ref", "") != _units[actor] or not rescue.get("id") is String or rescue.id.is_empty() or rescue.get("status", "") not in ["APPROACHING", "CONTACT_REACHED", "PICKUP_PENDING", "CARRYING", "ARRIVED_CARRYING", "ROAD_EVACUATION", "PUT_DOWN", "HANDED_OVER", "INTERRUPTED"]:
			return false
		if rescue.status in ["APPROACHING", "CONTACT_REACHED", "PICKUP_PENDING", "CARRYING", "ARRIVED_CARRYING", "ROAD_EVACUATION"] and _member(str(rescue.patient_ref)).get("rescue_carrier_ref", "") != actor:
			return false
		if rescue.status in ["APPROACHING", "PICKUP_PENDING"] and _actions.get(_member(actor).action_ref, {}).get("rescue_ref", "") != rescue.id:
			return false
	return true
