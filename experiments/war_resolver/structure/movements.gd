extends RefCounted
## A movement is an agreement plus the existing physical unit and route.
const KINDS: Array[String] = ["propose_move", "propose_transport", "approve_move", "cancel_move", "accept_move", "redirect_move"]
const MAX_MOVES: int = 64
var _owner: WeakRef
var records: Dictionary = {}
var _units: Dictionary = {}
var _people: Dictionary = {}
var _actors: Dictionary = {}

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func validate(request: Dictionary, executing: bool) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	var actor: String = str(request.person_id)
	var position: Dictionary = s.command_person(actor)
	if s.Roles.ROLES.find(str(position.role)) < 2 or not s.active(str(position.formation_id)):
		return _reject("movement_requires_current_commander")
	if executing and request.effective_time != s._state.time:
		return _reject("wrong_time_boundary")
	var v: Dictionary = request.values
	for field: String in ["source", "destination"]:
		if s._state.gameplay_port != null and (s._state.gameplay_port.get_ref().air.recovery._unit_jobs.has(str(v.get(field, ""))) or s._state.gameplay_port.get_ref().land._unit_jobs.has(str(v.get(field, "")))):
			return _reject("local_air_recovery_crew_is_busy")
	if request.kind in ["propose_move", "propose_transport"]:
		if records.size() >= MAX_MOVES:
			return _reject("movement_record_capacity")
		var transporting: bool = request.kind == "propose_transport"
		if v.size() != (7 if transporting else 6) or not s._keys(v, ["source", "destination", "meeting", "path", "detachment", "allocation", "transport"]) or not v.get("path") is Array or v.has("transport") != transporting:
			return _reject("explicit_movement_agreement_required")
		if transporting:
			if not v.transport is Dictionary or v.transport.size() != 2 or not v.transport.get("patient_ref") is String or not v.transport.get("carrier_ref") is String:
				return _reject("explicit_patient_and_carrier_required")
		if v.source == v.destination or not _scope(str(position.formation_id), str(v.source)) or not _scope(str(position.formation_id), str(v.destination)):
			return _reject("outside_movement_scope")
		return _departure_check(request, false)
	if not v.get("movement") is String or not records.has(v.movement):
		return _reject("existing_movement_required")
	var move: Dictionary = records[v.movement]
	if move.status in ["HANDED_OVER", "CANCELLED"]:
		return _reject("movement_already_closed")
	if request.kind == "redirect_move":
		if v.size() != 4 or not s._keys(v, ["movement", "meeting", "path", "return_to_start"]) or not move.departed or not s._lod.has_leaf(str(move.unit_id)) or not _scope(str(position.formation_id), str(move.unit_id)) or not _scope(str(position.formation_id), str(move.agreement.destination)):
			return _reject("explicit_current_movement_route_required")
		if move.agreement.has("transport"):
			var carrying: Dictionary = s._state.gameplay_port.get_ref().participants.transport_check(str(move.agreement.transport.patient_ref), str(move.agreement.transport.carrier_ref), true)
			if not carrying.ok:
				return carrying
		var valid: Dictionary = s._state.gameplay_port.get_ref().validate_goal(actor, s._lod.preview_leaf(str(move.unit_id)), {"intent": "advance", "target_node": v.meeting, "path": v.path, "return_to_start": v.return_to_start})
		return s._members._representation_capacity([str(move.unit_id)]) if valid.ok else valid
	if v.size() != 1:
		return _reject("movement_identity_only_required")
	var required: String = str(move.agreement.destination) if request.kind == "accept_move" else str(move.agreement.source)
	if not _scope(str(position.formation_id), required):
		return _reject("outside_current_movement_scope")
	if request.kind == "approve_move":
		if move.departed or move.status not in ["PROPOSED", "BLOCKED"]:
			return _reject("movement_already_approved_or_departed")
		var proposed: Dictionary = {"id": move.id, "person_id": actor, "values": move.agreement}
		return _departure_check(proposed, false)
	if request.kind == "accept_move":
		if not move.departed or move.status not in ["ARRIVED", "BLOCKED"]:
			return _reject("actual_arrival_required_before_acceptance")
		return _handover_check(move)
	if move.departed and s._lod.has_leaf(str(move.unit_id)):
		return s._members._representation_capacity([str(move.unit_id)])
	return {"ok": true}

func apply(request: Dictionary, changed: Dictionary, retired: Dictionary) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	var v: Dictionary = request.values
	if request.kind in ["propose_move", "propose_transport"]:
		var record: Dictionary = {"id": request.id, "issuer": request.person_id, "agreement": v.duplicate(true), "status": "PROPOSED", "departed": false, "unit_id": "", "version": 0, "reason": "", "time": s._state.time}
		record.members = _members(v)
		records[request.id] = record
		if not _actors.has(request.person_id):
			_actors[request.person_id] = {}
		_actors[request.person_id][request.id] = true
		for person: String in _members(v):
			_people[person] = request.id
			if not _actors.has(person):
				_actors[person] = {}
			_actors[person][request.id] = true
		if v.has("transport"):
			var body: Dictionary = s._state.gameplay_port.get_ref().participants._member(str(v.transport.patient_ref))
			body.transport_ref = request.id
			body.transport_status = "WAITING_PICKUP"
		return _outcome(request, record)
	var move: Dictionary = records[v.movement]
	if not _actors.has(request.person_id):
		_actors[request.person_id] = {}
	_actors[request.person_id][move.id] = true
	if request.kind == "approve_move":
		move.approver = request.person_id
		move.status = "WAITING_DEPARTURE"
		move.version += 1
		move.wait_deadline = s._state.time + float(s._state.gameplay_port.get_ref().rules.dependency_seconds)
		_schedule_departure(move, s._state.time + 1.0)
	elif request.kind == "cancel_move":
		move.version += 1
		move.status = "CANCELLED"
		move.reason = "stopped_at_actual_position" if move.departed else "cancelled_before_departure"
		if move.departed and s._lod.has_leaf(str(move.unit_id)):
			s._materialize(str(s._unit_nodes[move.unit_id]), changed, retired)
			# Cancelling the goal stops its current edge without rewinding geometry.
			s._state.gameplay_port.get_ref().cancel_structural_goal(str(move.unit_id), str(request.id))
			s._state.units[move.unit_id].spatial.path.clear()
			changed[move.unit_id] = true
			_units.erase(move.unit_id)
		for person: String in _members(move.agreement):
			_people.erase(person)
		if move.agreement.has("transport"):
			s._state.gameplay_port.get_ref().participants.release_transport(str(move.agreement.transport.patient_ref), "CANCELLED", str(request.id))
	elif request.kind == "accept_move":
		_handover(move, request, changed, retired)
	elif request.kind == "redirect_move":
		s._materialize(str(s._unit_nodes[move.unit_id]), changed, retired)
		move.agreement.meeting = v.meeting
		move.agreement.path = v.path.duplicate()
		move.status = "DEPARTED"
		move.reason = ""
		move.goal_ref = "goal_move_redirect_" + str(request.id) + "_" + str(move.unit_id)
		s._state.gameplay_port.get_ref().assign_structural_task(str(move.unit_id), "move_redirect_" + str(request.id), str(request.person_id), {"intent": "advance", "target_node": v.meeting, "path": v.path, "return_to_start": v.return_to_start})
		changed[move.unit_id] = true
	return _outcome(request, move)

func _departure_check(request: Dictionary, actual: bool) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	var v: Dictionary = request.values
	var source: String = str(v.get("source", ""))
	var destination: String = str(v.get("destination", ""))
	if not s._unit_nodes.has(source) or not s._unit_nodes.has(destination) or not s.active(str(s._unit_nodes[source])) or not s.active(str(s._unit_nodes[destination])):
		return _reject("live_movement_units_required")
	var unit: Dictionary = s._lod.preview_leaf(source)
	if float(unit.effective) <= s.MIN_REMAINDER:
		return _reject("movement_source_incapacitated")
	if unit.side != s._lod.preview_leaf(destination).side or _units.has(source):
		return _reject("same_side_available_movement_source_required")
	var owner: String = str(s.command_person(str(request.person_id)).formation_id)
	if not _scope(owner, source) or not _scope(owner, destination):
		return _reject("outside_current_movement_scope")
	if v.detachment is Dictionary:
		if v.detachment.size() != 4 or not s._keys(v.detachment, ["new_id", "new_node", "members", "anonymous"]):
			return _reject("explicit_travelling_members_required")
		var split: Dictionary = _split_request(request)
		var checked: Dictionary = s._members._validate_split(split, owner)
		if not checked.ok:
			return checked
	else:
		if v.detachment != "whole_unit":
			return _reject("explicit_whole_group_stocks_required")
		# A whole group already owns these stocks; later consumption stays deducted.
		if v.allocation != "existing_unit_stocks":
			if not v.allocation is Dictionary or v.allocation.size() != s._members.RESOURCES.size() or not s._keys(v.allocation, s._members.RESOURCES):
				return _reject("explicit_whole_group_stocks_required")
			for key: String in s._members.RESOURCES:
				if not s._number(v.allocation[key]) or float(v.allocation[key]) != float(unit.get(key, 0.0)):
					return _reject("whole_group_allocation_must_match_current_stocks")
		var stationary: Dictionary = s._members._handover(unit, unit)
		if not stationary.ok:
			return stationary
		var capacity: Dictionary = s._members._representation_capacity([source])
		if not capacity.ok:
			return capacity
	var gameplay: RefCounted = s._state.gameplay_port.get_ref()
	var patient: String = str(v.get("transport", {}).get("patient_ref", ""))
	if v.has("transport"):
		var carrier: String = str(v.transport.carrier_ref)
		if patient not in _members(v) or carrier not in _members(v):
			return _reject("patient_and_carrier_must_travel_together")
		var valid: Dictionary = gameplay.participants.transport_check(patient, carrier, gameplay.participants._units.has(patient) and gameplay.participants._member(patient).state == "TRANSPORTED")
		if not valid.ok:
			return valid
	var regrouping: int = 0
	for person: String in _members(v):
		if gameplay.participants._member(person).has("command_post"):
			return _reject("command_post_body_uses_personal_relocation")
		if person != patient and gameplay.participants._member(person).actionable and gameplay.participants._distance(gameplay.participants.position(person), gameplay._space.xy(unit)) > float(gameplay.participants.rules.local_radius_km):
			return _reject("travelling_member_must_reach_actual_group_before_departure")
		if _people.has(person) and _people[person] != request.id:
			return _reject("person_already_has_movement")
		if gameplay.participants.dead(person):
			return _reject("dead_person_cannot_depart")
		if actual and person != patient and not gameplay.participants._member(person).actionable:
			return _reject("travelling_person_incapacitated")
		regrouping += int(gameplay.participants._member(person).state != "FOLLOWING")
	if gameplay.participants._actions.size() + regrouping > gameplay.participants.MAX_ACTIONS:
		return _reject("personal_regroup_capacity")
	var projected: Dictionary = unit.duplicate(true)
	if v.detachment is Dictionary:
		projected.id = v.detachment.new_id
	return gameplay.validate_goal(str(request.person_id), projected, {"intent": "advance", "target_node": v.meeting, "path": v.path, "return_to_start": false})

func _split_request(request: Dictionary) -> Dictionary:
	var v: Dictionary = request.values
	var split: Dictionary = {"id": request.id, "person_id": request.person_id, "defer_membership": true, "values": {"source": v.source, "new_id": v.detachment.new_id, "new_node": v.detachment.new_node, "members": v.detachment.members, "anonymous": v.detachment.anonymous, "allocation": v.allocation, "keep_goal": "source", "other_task": "idle"}}
	return split

func _schedule_departure(move: Dictionary, due: float) -> void:
	var s: RefCounted = _owner.get_ref()
	var id: String = "move_depart_%s_%d_%.6f" % [move.id, move.version, due]
	var request: Dictionary = {"id": id, "kind": "move_depart", "person_id": move.approver, "effective_time": due, "values": {"movement": move.id, "version": move.version}}
	s._requests[id] = request
	assert(s._state.schedule_event("structure_" + id, due, "structure", {"request_id": id}))

func depart(request: Dictionary, changed: Dictionary, retired: Dictionary) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	var move: Dictionary = records[request.values.movement]
	if move.version != request.values.version or move.status != "WAITING_DEPARTURE":
		return {"ok": true, "kind": "stale_movement_noop"}
	var proposed: Dictionary = {"id": move.id, "person_id": move.approver, "values": move.agreement}
	var valid: Dictionary = _departure_check(proposed, true)
	if not valid.ok or s._state.time >= float(move.wait_deadline):
		move.status = "BLOCKED"
		move.reason = valid.get("error", "departure_wait_expired")
		if move.agreement.has("transport"):
			s._state.gameplay_port.get_ref().participants.release_transport(str(move.agreement.transport.patient_ref), "INTERRUPTED", str(request.id))
		return _outcome(request, move)
	var p: RefCounted = s._state.gameplay_port.get_ref().participants
	var next: float = s._state.time
	var patient: String = str(move.agreement.get("transport", {}).get("patient_ref", ""))
	var carrier: String = str(move.agreement.get("transport", {}).get("carrier_ref", ""))
	# Finish an existing action first; a covered member then returns by the old rule.
	for person: String in _members(move.agreement):
		if person == patient:
			continue
		var member: Dictionary = p._member(person)
		if member.state in ["COVERED", "STATIONARY"]:
			p._start(person, "regroup_" + str(request.id), "RETURNING", s._state.gameplay_port.get_ref()._space.xy(s._state.units[move.agreement.source]), "")
		if member.state in ["ENTERING", "RETURNING", "PICKING_UP", "MEDICATING", "PLACING_REMAINS", "RELOCATING"]:
			next = maxf(next, float(p._actions[member.action_ref].due) + 0.000001)
	if next > s._state.time:
		_schedule_departure(move, minf(next, float(move.wait_deadline)))
		return _outcome(request, move)
	if not patient.is_empty() and p._member(patient).state != "TRANSPORTED":
		p.start_transport(patient, carrier, str(move.id), str(request.id))
		_schedule_departure(move, minf(float(p._actions[p._member(carrier).action_ref].due) + 0.000001, float(move.wait_deadline)))
		return _outcome(request, move)
	# Whole-group membership is captured at real departure, before edits are locked.
	move.members = _members(move.agreement)
	for person: String in move.members:
		_people[person] = move.id
		if not _actors.has(person):
			_actors[person] = {}
		_actors[person][move.id] = true
	var travel: String = str(move.agreement.source)
	if move.agreement.detachment is Dictionary:
		s._members._split(_split_request(proposed), changed, retired)
		travel = str(move.agreement.detachment.new_id)
	else:
		s._materialize(str(s._unit_nodes[travel]), changed, retired)
	move.unit_id = travel
	move.departed = true
	var companions: Array[String] = _members(move.agreement)
	for a: String in companions:
		for b: String in companions:
			if a < b:
				s._state.gameplay_port.get_ref().focus_continuity.event_relation(a, b, "shared_movement", str(move.id))
	move.status = "DEPARTED"
	move.reason = ""
	if not patient.is_empty():
		p._member(patient).transport_status = "IN_TRANSIT"
	_units[travel] = move.id
	move.goal_ref = "goal_move_" + str(move.id) + "_" + travel
	s._state.gameplay_port.get_ref().assign_structural_task(travel, "move_" + str(move.id), str(move.approver), {"intent": "advance", "target_node": move.agreement.meeting, "path": move.agreement.path, "return_to_start": false})
	changed[travel] = true
	return _outcome(request, move)

func on_goal(record: Dictionary) -> void:
	var unit: String = str(record.subject_ref)
	if not _units.has(unit):
		return
	var s: RefCounted = _owner.get_ref()
	var move: Dictionary = records[_units[unit]]
	if move.status in ["CANCELLED", "HANDED_OVER"]:
		return
	var raw: Dictionary = s._lod.preview_leaf(unit)
	var goal: Dictionary = s._state.missions[raw.mission_id]
	if not goal.has("goal_v1"):
		return
	if goal.id != move.get("goal_ref", ""):
		if record.kind == "goal_admitted":
			move.status = "BLOCKED"
			move.reason = "movement_task_replaced_requires_explicit_agreement"
		return
	if goal.goal_v1.route_complete and raw.spatial.node == move.agreement.meeting:
		move.status = "ARRIVED"
		move.reason = "awaiting_actual_acceptance"
		if move.agreement.has("transport"):
			s._state.gameplay_port.get_ref().participants._member(str(move.agreement.transport.patient_ref)).transport_status = "AWAITING_HANDOVER"
	elif goal.status in ["failed", "cancelled"]:
		move.status = "BLOCKED"
		move.reason = goal.goal_v1.get("terminal_reason", "movement_goal_ended")
	elif goal.goal_v1.execution == "MOVING":
		move.status = "IN_TRANSIT"
		move.reason = ""
	elif not str(goal.goal_v1.reason).is_empty():
		move.status = "BLOCKED"
		move.reason = goal.goal_v1.reason
	move.time = s._state.time

func _handover_check(move: Dictionary) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	if not s._lod.has_leaf(str(move.unit_id)) or not s._lod.has_leaf(str(move.agreement.destination)):
		return _reject("handover_unit_unavailable")
	var a: Dictionary = s._lod.preview_leaf(str(move.unit_id))
	var b: Dictionary = s._lod.preview_leaf(str(move.agreement.destination))
	var dependencies: Dictionary = s._members._dependencies(str(a.id), true)
	if not dependencies.ok:
		return dependencies
	if a.spatial.node != move.agreement.meeting or b.spatial.node != move.agreement.meeting:
		return _reject("agreed_meeting_not_shared_request_new_orders")
	var place: Dictionary = s._members._handover(a, b)
	if not place.ok:
		return place
	for key: String in ["type", "weapon", "mobility"]:
		if a[key] != b[key]:
			return _reject("handover_capability_mismatch")
	if s._state.logistics_port != null and not s._state.logistics_port.get_ref().compatible(a, b, false):
		return _reject("handover_supply_capability_mismatch")
	var p: RefCounted = s._state.gameplay_port.get_ref().participants
	if a.get("gameplay_personnel", {}).get("members", {}).size() + b.get("gameplay_personnel", {}).get("members", {}).size() > p.MAX_PER_UNIT:
		return _reject("handover_named_member_capacity")
	for person: String in a.get("gameplay_personnel", {}).get("members", {}):
		if person == move.agreement.get("transport", {}).get("patient_ref", ""):
			var carried: Dictionary = p.transport_check(person, str(move.agreement.transport.carrier_ref), true)
			if not carried.ok:
				return carried
		elif p._member(person).state != "FOLLOWING":
			return _reject("actual_person_regroup_required")
	return s._members._representation_capacity([str(a.id), str(b.id)], 0, 1)

func _handover(move: Dictionary, request: Dictionary, changed: Dictionary, retired: Dictionary) -> void:
	var s: RefCounted = _owner.get_ref()
	var destination: String = str(move.agreement.destination)
	s._materialize(str(s._unit_nodes[move.unit_id]), changed, retired)
	s._materialize(str(s._unit_nodes[destination]), changed, retired)
	var a: Dictionary = s._state.units[destination]
	var b: Dictionary = s._state.units[move.unit_id]
	var historical: Dictionary = b.duplicate(true)
	var gameplay: RefCounted = s._state.gameplay_port.get_ref()
	if move.agreement.has("transport"):
		gameplay.participants.release_transport(str(move.agreement.transport.patient_ref), "HANDED_OVER", str(request.id))
	if b.has("gameplay_personnel"):
		if not a.has("gameplay_personnel"):
			a.gameplay_personnel = {"anonymous": float(a.effective), "members": {}}
		a.gameplay_personnel.anonymous += float(b.gameplay_personnel.anonymous)
		for person: String in b.gameplay_personnel.members.keys():
			gameplay.participants.rebind_member(person, destination, "carry", true, str(request.id))
			s.move_person(person, str(s._unit_nodes[destination]))
			_people.erase(person)
	gameplay.cancel_structural_goal(str(move.unit_id), str(request.id))
	s.vacate_node(str(s._unit_nodes[move.unit_id]), "physical_handover", str(request.id))
	for person: String in s._node_people[s._unit_nodes[move.unit_id]].keys():
		s.move_person(person, str(s._unit_nodes[destination]))
	var merge: Dictionary = {"id": request.id, "values": {"survivor": destination, "donor": move.unit_id}}
	s._merge(merge, changed, retired)
	gameplay.medical.on_unit_merge(str(move.unit_id), destination)
	s._retired[s._unit_nodes[move.unit_id]].historical_unit_not_current = historical
	_units.erase(move.unit_id)
	move.status = "HANDED_OVER"
	move.reason = "remaining_stocks_received_once"
	move.time = s._state.time

func _members(v: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if v.detachment is Dictionary:
		for person: String in v.detachment.members:
			result.append(person)
	else:
		var s: RefCounted = _owner.get_ref()
		var unit: Dictionary = s._lod.preview_leaf(str(v.source))
		for person: String in unit.get("gameplay_personnel", {}).get("members", {}):
			result.append(person)
	return result

func _scope(owner: String, unit: String) -> bool:
	var s: RefCounted = _owner.get_ref()
	return s.active(owner) and s._unit_nodes.has(unit) and s.active(str(s._unit_nodes[unit])) and s._contains(owner, str(s._unit_nodes[unit]))

func _outcome(request: Dictionary, move: Dictionary) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	return {"ok": true, "kind": request.kind, "values": request.values.duplicate(true), "movement": move.id, "movement_status": move.status, "reason": move.reason,
		"affected_nodes": [s._unit_nodes[move.agreement.source], s._unit_nodes[move.agreement.destination]], "movement_people": move.members,
		"moved_people": move.members if move.status == "HANDED_OVER" else [],
		"created_nodes": [move.agreement.detachment.new_node] if move.departed and move.agreement.detachment is Dictionary else []}

func own_records(person: String) -> Array[Dictionary]:
	var ids: Dictionary = _actors.get(person, {}).duplicate()
	if _people.has(person):
		ids[_people[person]] = true
	var result: Array[Dictionary] = []
	for id: String in ids:
		var move: Dictionary = records[id]
		result.append({"id": id, "status": move.status, "reason": move.reason, "meeting": move.agreement.meeting, "source": move.agreement.source, "destination": move.agreement.destination, "physical_unit": move.unit_id, "departed": move.departed, "transport": move.agreement.get("transport", {}).duplicate(true)})
	return result

func on_personal_transition(record: Dictionary) -> void:
	var actor: String = str(record.get("actor_ref", ""))
	if not _people.has(actor) or record.kind not in ["personal_injury", "personal_death"]:
		return
	var move: Dictionary = records[_people[actor]]
	if not move.agreement.has("transport") or move.status in ["CANCELLED", "HANDED_OVER"]:
		return
	var s: RefCounted = _owner.get_ref()
	var p: RefCounted = s._state.gameplay_port.get_ref().participants
	if p.transport_check(str(move.agreement.transport.patient_ref), str(move.agreement.transport.carrier_ref), move.departed).ok:
		return
	move.status = "BLOCKED"
	move.reason = "patient_or_carrier_unavailable"
	move.version += 1
	if not move.departed:
		p.release_transport(str(move.agreement.transport.patient_ref), "INTERRUPTED", str(record.event_id))
	if move.departed:
		# Injury is already settled. A later boundary stops the existing route.
		var id: String = "move_stop_" + str(record.event_id)
		var due: float = s._state.time + 0.000001
		s._requests[id] = {"id": id, "person_id": move.approver, "kind": "move_transport_stop", "effective_time": due, "values": {"movement": move.id, "version": move.version}}
		assert(s._state.schedule_event("structure_" + id, due, "structure", {"request_id": id}))

func stop_transport(request: Dictionary, changed: Dictionary) -> Dictionary:
	var s: RefCounted = _owner.get_ref()
	var move: Dictionary = records[request.values.movement]
	if move.version != request.values.version or move.status != "BLOCKED":
		return {"ok": true, "kind": "stale_movement_noop"}
	var p: RefCounted = s._state.gameplay_port.get_ref().participants
	p.release_transport(str(move.agreement.transport.patient_ref), "INTERRUPTED", str(request.id))
	if s._state.units.has(move.unit_id):
		s._state.gameplay_port.get_ref().cancel_structural_goal(str(move.unit_id), str(request.id))
		s._state.units[move.unit_id].spatial.path.clear()
		changed[move.unit_id] = true
	move.status = "BLOCKED"
	move.reason = "patient_or_carrier_unavailable"
	return _outcome(request, move)

func on_member_move(person: String) -> void:
	if not _people.has(person):
		return
	var move: Dictionary = records[_people[person]]
	if move.departed:
		return
	move.status = "CANCELLED"
	move.reason = "source_membership_changed_before_departure"
	move.version += 1
	if move.agreement.has("transport"):
		_owner.get_ref()._state.gameplay_port.get_ref().participants.release_transport(str(move.agreement.transport.patient_ref), "CANCELLED", "membership_" + person)
	for member: String in move.members:
		_people.erase(member)

func on_retired(unit_id: String) -> void:
	if not _units.has(unit_id):
		return
	var move: Dictionary = records[_units[unit_id]]
	move.status = "CANCELLED"
	move.reason = "physical_movement_unit_retired"
	_units.erase(unit_id)
	for member: String in move.members:
		_people.erase(member)

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["records", "_units", "_people", "_actors"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
