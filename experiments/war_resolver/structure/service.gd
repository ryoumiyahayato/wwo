extends RefCounted
signal transition(record: Dictionary)
signal applying(event: Dictionary)
## Experimental military relations, not a formal Organization authority.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const Members = preload("res://experiments/war_resolver/structure/member_adjustments.gd")
const Movements = preload("res://experiments/war_resolver/structure/movements.gd")
const OFFICE_KINDS: Array[String] = ["vacate_position", "appoint"]
const Stocks: Array[String] = ["personnel_total", "effective", "casualties", "personnel_recovered", "equipment", "equipment_lost", "ammunition", "ammo_spent"]
const EPS: float = 0.0000001
const MIN_REMAINDER: float = 0.000001
var _state: State
var _lod: RefCounted
var _nodes: Dictionary = {}
var _people: Dictionary = {}
var _node_people: Dictionary = {}
var member_adjustments: bool = false
var _members: Members = Members.new()
var movements: Movements = Movements.new()
var _positions: Dictionary = {}
var _person_positions: Dictionary = {}
var _children: Dictionary = {}
var _leaves: Dictionary = {}
var _unit_nodes: Dictionary = {}
var _requests: Dictionary = {}
var _attachments: Dictionary = {}
var _pending: Dictionary = {}
var _retired: Dictionary = {}
var _used_units: Dictionary = {}
var _used_nodes: Dictionary = {}
var history: Array[Dictionary] = []
var attachment_continuity: bool = false
var continuity_work: Dictionary = {"leaf_previews": 0, "dependency_records": 0, "relation_events": 0}

func enable_attachment_continuity() -> bool:
	if _state == null or _state.time != 0.0 or attachment_continuity or not history.is_empty():
		return false
	attachment_continuity = true
	return true
var work: Dictionary = {"structure_records_examined": 0, "structure_events_processed": 0,
	"leaves_materialized_for_structure": 0, "aggregate_memberships_rebuilt": 0,
	"authority_scopes_updated": 0, "relations_changed": 0}

func configure(state: State, lod: RefCounted, formations: Dictionary, people: Dictionary) -> bool:
	if _state != null or state.structure_port != null or not lod.owns_state(state) or people.is_empty() or not state.events.is_empty():
		return false
	var admission: Roles = Roles.new()
	if not admission.configure(state, formations, people, State.sorted_ids(people)[0]):
		return false
	_state = state
	_lod = lod
	_nodes = formations.duplicate(true)
	_people = people.duplicate(true)
	for id: String in _nodes:
		_children[id] = {}
		_leaves[id] = {}
		_node_people[id] = {}
		_used_nodes[id] = true
	for id: String in _nodes:
		var parent: String = str(_nodes[id].parent)
		if not parent.is_empty():
			_children[parent][id] = true
		if _nodes[id].echelon == "squad":
			_unit_nodes[_nodes[id].unit_id] = id
			_used_units[_nodes[id].unit_id] = true
			for ancestor: String in _path(id):
				_leaves[ancestor][id] = true
	for id: String in _people:
		_node_people[_people[id].formation_id][id] = true
		if Roles.ROLES.find(str(_people[id].role)) > 0:
			var node_id: String = str(_people[id].formation_id)
			_positions[node_id] = {"person": id, "acting": false, "since": state.time, "cause": "initial_position"}
			_person_positions[id] = node_id
	_members.configure(self)
	movements.configure(self)
	_state.structure_port = weakref(self)
	work = {"structure_records_examined": 0, "structure_events_processed": 0,
		"leaves_materialized_for_structure": 0, "aggregate_memberships_rebuilt": 0,
		"authority_scopes_updated": 0, "relations_changed": 0}
	return true

func stock_keys() -> Array[String]:
	return Stocks + _state.logistics_port.get_ref().EXTRA_STOCKS if _state.logistics_port != null else Stocks

func command_person(person: String) -> Dictionary:
	# Permanent role and membership stay in _people; only this office grants command.
	var identity: Dictionary = _people[person]
	var node_id: String = str(_person_positions.get(person, ""))
	var available: bool = active(node_id)
	if _state.gameplay_port != null:
		var participants: RefCounted = _state.gameplay_port.get_ref().participants
		if participants._units.has(person):
			available = available and participants._member(person).actionable
	return {"role": Roles.ROLES[Roles.ECHELONS.find(str(_nodes[node_id].echelon)) + 1] if available else "ordinary_soldier",
		"formation_id": node_id if available else identity.formation_id, "has_position": available,
		"permanent_role": identity.role, "membership_ref": identity.formation_id,
		"acting": bool(_positions.get(node_id, {}).get("acting", false)) if available else false}

func office_scope(person: String) -> String:
	var position: Dictionary = command_person(person)
	return str(position.formation_id) if position.has_position else ""

func vacate_node(node_id: String, reason: String, cause: String) -> void:
	if not _positions.has(node_id) or str(_positions[node_id].person).is_empty():
		return
	var person: String = str(_positions[node_id].person)
	_person_positions.erase(person)
	_positions[node_id] = {"person": "", "acting": false, "since": _state.time, "cause": cause, "reason": reason}
	var record: Dictionary = {"id": "position_" + cause + "_" + node_id, "time": _state.time, "actor": person,
		"outcome": {"ok": true, "kind": "position_vacant", "affected_nodes": [node_id], "position_people": [person], "reason": reason}}
	if _state.decision_port != null:
		_state.decision_port.get_ref().on_structure(record)
	if attachment_continuity:
		transition.emit(record)

func on_personal_transition(record: Dictionary) -> void:
	var person: String = str(record.get("actor_ref", ""))
	if record.kind in ["personal_injury", "personal_death"] and _person_positions.has(person) and not _state.gameplay_port.get_ref().participants._member(person).actionable:
		vacate_node(str(_person_positions[person]), "dead" if record.kind == "personal_death" else "incapacitated", str(record.event_id))

func _validate_office(request: Dictionary) -> Dictionary:
	var v: Dictionary = request.values
	var target: String = str(v.get("node", ""))
	if not active(target):
		return _reject("active_command_position_required")
	var actor: Dictionary = command_person(str(request.person_id))
	var rank: int = Roles.ROLES.find(str(actor.role))
	var target_rank: int = Roles.ECHELONS.find(str(_nodes[target].echelon)) + 1
	var self_handover: bool = request.kind == "vacate_position" and _positions.get(target, {}).get("person", "") == request.person_id
	if not self_handover and (rank <= target_rank or not _contains(str(actor.formation_id), target)):
		return _reject("appointment_requires_current_superior")
	if request.kind == "vacate_position":
		return {"ok": true} if v.size() == 1 and _positions.get(target, {}).get("person", "") != "" else _reject("occupied_position_required")
	if v.size() != 4 or not _keys(v, ["node", "person", "acting", "vacate_previous"]) or not v.get("acting") is bool or not v.get("vacate_previous") is bool or not _people.has(v.get("person", "")):
		return _reject("explicit_existing_appointment_required")
	if str(_positions.get(target, {}).get("person", "")) != "":
		return _reject("vacate_current_incumbent_first")
	var candidate: Dictionary = _people[v.person]
	# One adjacent office step is permitted; permanent rank is never promoted.
	if Roles.ROLES.find(str(candidate.role)) < target_rank - 1 or not active(str(candidate.formation_id)) or _nodes[candidate.formation_id].side != _nodes[target].side or not _contains(str(actor.formation_id), str(candidate.formation_id)):
		return _reject("candidate_outside_eligible_existing_scope")
	if _state.gameplay_port != null:
		var p: RefCounted = _state.gameplay_port.get_ref().participants
		if p._units.has(v.person):
			if not p._member(v.person).actionable or movements._people.has(v.person):
				return _reject("candidate_unavailable")
			if target_rank == 1 and p._units[v.person] != _nodes[target].unit_id:
				return _reject("squad_candidate_must_be_actual_member")
	var previous: String = str(_person_positions.get(v.person, ""))
	if not previous.is_empty() and (not v.vacate_previous or not _contains(str(actor.formation_id), previous)):
		return _reject("explicit_previous_office_handover_required")
	return {"ok": true}

func _apply_office(request: Dictionary) -> Dictionary:
	var v: Dictionary = request.values
	var affected: Array[String] = []
	if request.kind == "vacate_position":
		affected.append(str(_positions[v.node].person))
		vacate_node(str(v.node), "explicit_handover", str(request.id))
	else:
		var previous: String = str(_person_positions.get(v.person, ""))
		if not previous.is_empty():
			vacate_node(previous, "appointed_elsewhere", str(request.id))
		_positions[v.node] = {"person": v.person, "acting": v.acting, "since": _state.time, "cause": request.id}
		_person_positions[v.person] = v.node
		affected.append(str(v.person))
		if _state.decision_port != null:
			_state.decision_port.get_ref().on_position_changed(str(v.person), str(v.node))
	return {"ok": true, "kind": request.kind, "values": v.duplicate(true), "affected_nodes": [v.node], "position_people": affected}

func move_person(person: String, destination: String) -> void:
	var previous: String = str(_people[person].formation_id)
	_node_people[previous].erase(person)
	_node_people[destination][person] = true
	_people[person].formation_id = destination
	movements.on_member_move(person)
	if _state.decision_port != null:
		_state.decision_port.get_ref().on_member_move(person, destination)
	if _state.information_port != null:
		_state.information_port.get_ref().on_member_move(person, previous, destination)

func owns_state(state: State) -> bool:
	return state == _state

func knows_identity(id: String) -> bool:
	return _used_units.has(id) or _used_nodes.has(id) or _people.has(id)

func matches_admission(formations: Dictionary, people: Dictionary) -> bool:
	return formations == _nodes and people == _people and history.is_empty()

func node(id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	work.structure_records_examined += 1
	return _nodes.get(id, {}).duplicate(true)

func active(id: String) -> bool:
	return _nodes.has(id) and not _retired.has(id)

func parent(id: String) -> String:
	work.structure_records_examined += 1
	return str(_attachments[id].operational_parent) if _attachments.has(id) else str(_nodes[id].parent)

func children(id: String) -> Dictionary:
	return _children.get(id, {}).duplicate()

func leaves(id: String) -> Dictionary:
	return _leaves.get(id, {}).duplicate()

func _path(id: String) -> Array[String]:
	var result: Array[String] = []
	while not id.is_empty():
		result.append(id)
		id = parent(id)
	return result

func can_coalesce(source: String, ids: Array[String]) -> bool:
	if not active(source):
		return false
	for id: String in ids:
		work.structure_records_examined += 1
		if not _unit_nodes.has(id) or not _leaves[source].has(_unit_nodes[id]):
			return false
	return true

func relation(id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if not active(id):
		return {"ok": false, "error": "inactive_node"}
	return {"ok": true, "permanent_parent": _nodes[id].parent, "effective_parent": parent(id),
		"attachment": _attachments.get(id, {}).duplicate(true),
		"supply_responsibility_reference": parent(id)}

func submit(person_id: String, command: Dictionary) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state == null or not _people.has(person_id):
		return _reject("unknown_person")
	if not _keys(command, ["id", "kind", "effective_time", "values"]) or command.size() != 4 or not command.get("kind") is String or not command.get("id") is String or str(command.id).is_empty() or not command.get("values") is Dictionary or not _number(command.get("effective_time")) or float(command.effective_time) < _state.time:
		return _reject("invalid_request")
	if _requests.has(command.id) or _state.event_ids.has("structure_" + str(command.id)):
		return _reject("duplicate_request")
	var request: Dictionary = command.duplicate(true)
	request.person_id = person_id
	var valid: Dictionary = _validate(request, false)
	if not valid.ok:
		return valid
	if attachment_continuity and request.kind == "revoke":
		request.attachment_id = _attachments[request.values.target].id
	_requests[command.id] = request
	if request.kind == "attach":
		var target: String = str(request.values.target)
		if not _pending.has(target):
			_pending[target] = {}
		_pending[target][request.id] = true
	assert(_state.schedule_event("structure_" + str(request.id), float(request.effective_time), "structure", {"request_id": request.id}))
	return {"ok": true, "status": "scheduled", "effective_time": request.effective_time}

func accepts_event(event_id: String, payload: Dictionary, due: float) -> bool:
	if not _keys(payload, ["request_id", "expiry"]) or not payload.get("request_id") is String or not payload.get("expiry", false) is bool or not _requests.has(payload.get("request_id", "")):
		return false
	var request: Dictionary = _requests[payload.request_id]
	var expiry: bool = bool(payload.get("expiry", false))
	if expiry and request.kind != "attach":
		return false
	if event_id != ("structure_expiry_" if expiry else "structure_") + str(request.id):
		return false
	return due == (float(request.values.until) if payload.get("expiry", false) else float(request.effective_time))

func process_event(event: Dictionary) -> Dictionary:
	if attachment_continuity:
		applying.emit(event)
	work.structure_events_processed += 1
	var request: Dictionary = _requests[event.payload.request_id]
	var changed: Dictionary = {}
	var retired: Dictionary = {}
	var outcome: Dictionary
	if event.payload.get("expiry", false):
		var target: String = str(request.values.target)
		if _attachments.has(target) and _attachments[target].id == request.id:
			_materialize(target, changed, retired)
			_reparent(target, str(_nodes[target].parent))
			_attachments.erase(target)
			outcome = {"ok": true, "kind": "attachment_expired", "target": target}
		else:
			outcome = {"ok": true, "kind": "stale_expiry_noop"}
	else:
		outcome = {"ok": true} if request.kind in ["move_depart", "move_transport_stop"] else _validate(request, true)
		if request.kind == "attach":
			_pending[request.values.target].erase(request.id)
		if outcome.ok:
			var values: Dictionary = request.values
			if request.kind == "move_depart":
				outcome = movements.depart(request, changed, retired)
			elif request.kind == "move_transport_stop":
				outcome = movements.stop_transport(request, changed)
			elif request.kind in Movements.KINDS:
				outcome = movements.apply(request, changed, retired)
			elif request.kind in OFFICE_KINDS:
				outcome = _apply_office(request)
			elif request.kind in Members.KINDS:
				outcome = _members.apply(request, changed, retired)
			elif request.kind == "split":
				if _nodes.has(values.source) and _nodes[values.source].echelon == "company":
					_materialize(str(values.source), changed, retired)
					_split_company(request, changed)
				else:
					_materialize(str(_unit_nodes[values.source]), changed, retired)
					_split(request, changed)
			elif request.kind == "merge":
				_materialize(str(_unit_nodes[values.survivor]), changed, retired)
				_materialize(str(_unit_nodes[values.donor]), changed, retired)
				_merge(request, changed, retired)
			elif request.kind == "attach":
				_materialize(str(values.target), changed, retired)
				var permanent: String = str(_nodes[values.target].parent)
				_reparent(str(values.target), str(values.parent))
				_attachments[values.target] = {"id": request.id, "permanent_parent": permanent,
					"operational_parent": values.parent, "from": _state.time, "until": values.until}
				assert(_state.schedule_event("structure_expiry_" + str(request.id), float(values.until), "structure", {"request_id": request.id, "expiry": true}))
			elif request.kind == "revoke":
				_materialize(str(values.target), changed, retired)
				_reparent(str(values.target), str(_nodes[values.target].parent))
				_attachments.erase(values.target)
			if request.kind not in Members.KINDS and request.kind not in Movements.KINDS and request.kind not in OFFICE_KINDS and request.kind not in ["move_depart", "move_transport_stop"]:
				outcome = {"ok": true, "kind": request.kind, "values": values.duplicate(true)}
	if outcome.ok and request.kind in ["split", "merge"]:
		var affected_nodes: Dictionary = {}
		var created_nodes: Dictionary = {}
		var fresh_root: String = str(request.values.get("new_node", "")) if request.kind == "split" else ""
		for unit: String in changed.keys() + retired.keys():
			var leaf: String = str(_unit_nodes.get(unit, ""))
			for node: String in _path(leaf):
				affected_nodes[node] = true
				if not fresh_root.is_empty() and _contains(fresh_root, node):
					created_nodes[node] = true
		outcome.affected_nodes = State.sorted_ids(affected_nodes)
		outcome.created_nodes = State.sorted_ids(created_nodes)
	var record: Dictionary = {"id": event.id, "time": _state.time, "actor": request.person_id, "outcome": outcome.duplicate(true)}
	history.append(record)
	if _state.gameplay_port != null:
		for id: String in retired:
			if not _lod.has_leaf(id):
				_state.gameplay_port.get_ref().prerequisites.on_retired(id)
				movements.on_retired(id)
	if _state.decision_port != null:
		_state.decision_port.get_ref().on_structure(record)
	if attachment_continuity:
		continuity_work.relation_events += int(outcome.ok and outcome.get("kind", "") != "stale_expiry_noop")
		transition.emit(record.duplicate(true))
	return {"changed": State.sorted_ids(changed), "retired": State.sorted_ids(retired), "record": record, "representation_only": outcome.get("representation_only", false)}

func _validate(request: Dictionary, executing: bool) -> Dictionary:
	if _state.gameplay_port != null and not _state.gameplay_port.get_ref().participants.can_intend(str(request.person_id)):
		return _reject("person_unavailable_for_structure_intent")
	if request.kind in Movements.KINDS or request.kind in OFFICE_KINDS:
		if not member_adjustments:
			return _reject("member_adjustments_not_enabled")
		if executing and float(request.effective_time) != _state.time:
			return _reject("wrong_time_boundary")
		return movements.validate(request, executing) if request.kind in Movements.KINDS else _validate_office(request)
	if request.kind in Members.KINDS:
		if not member_adjustments:
			return _reject("member_adjustments_not_enabled")
		return _members.validate(request, executing)
	if _state.gameplay_port != null and _state.gameplay_port.get_ref().blocks_structure(str(request.kind), request.values):
		return _reject("gameplay_identity_migration_not_supported")
	if attachment_continuity and request.kind in ["attach", "revoke"]:
		var continuity: Dictionary = _validate_continuity(request, executing)
		if not continuity.ok:
			return continuity
	if executing and float(request.effective_time) != _state.time:
		return _reject("wrong_time_boundary")
	var person: Dictionary = command_person(str(request.person_id))
	var owner: String = str(person.formation_id)
	if Roles.ROLES.find(str(person.role)) < 3 or not active(owner):
		return _reject("structure_authority_required")
	var values: Dictionary = request.values
	if request.kind == "split":
		if not _keys(values, ["source", "new_id", "new_node", "allocation"]) or not values.get("allocation") is Dictionary or not _keys(values.allocation, stock_keys()) or values.allocation.size() != stock_keys().size():
			return _reject("invalid_split")
		if _nodes.has(values.get("source", "")) and _nodes[values.source].echelon == "company":
			return _validate_company_split(request, owner)
		if not _leaf_scope(owner, str(values.get("source", ""))):
			return _reject("outside_effective_scope")
		var source: Dictionary = _lod.preview_leaf(str(values.source))
		if not values.get("new_id") is String or not values.get("new_node") is String or str(values.new_id).is_empty() or str(values.new_node).is_empty() or _state.identity_reserved(str(values.new_id)) or _state.identity_reserved(str(values.new_node)) or _state.unit_event_counts.has(values.new_id) or _state.missions.has("structure_" + str(request.id) + "_mission"):
			return _reject("identity_collision")
		if not _clear_leaf(str(values.source)):
			return _reject("dependency_migration_required")
		if not _number(values.allocation.get("personnel_total")) or float(source.personnel_total) <= 0.0:
			return _reject("invalid_allocation")
		var amount: float = float(values.allocation.personnel_total)
		if amount < MIN_REMAINDER or float(source.personnel_total) - amount < MIN_REMAINDER:
			return _reject("empty_or_full_detachment")
		var fraction: float = amount / float(source.personnel_total)
		for key: String in stock_keys():
			if not _number(values.allocation.get(key)) or absf(float(values.allocation[key]) - float(source.get(key, 0.0)) * fraction) > EPS:
				return _reject("proportional_allocation_required")
	elif request.kind == "merge":
		if not _keys(values, ["survivor", "donor"]) or values.get("survivor", "") == values.get("donor", "") or not _leaf_scope(owner, str(values.get("survivor", ""))) or not _leaf_scope(owner, str(values.get("donor", ""))):
			return _reject("invalid_merge_scope")
		var x: String = str(_unit_nodes[values.survivor])
		var y: String = str(_unit_nodes[values.donor])
		if _nodes[x].parent != _nodes[y].parent or parent(x) != parent(y) or _attachments.has(x) or _attachments.has(y) or not _clear_leaf(str(values.survivor)) or not _clear_leaf(str(values.donor)):
			return _reject("incompatible_relation_or_dependency")
		var a: Dictionary = _lod.preview_leaf(str(values.survivor))
		var b: Dictionary = _lod.preview_leaf(str(values.donor))
		for key: String in ["side", "area_id", "position", "type", "weapon", "readiness", "mobility"]:
			if a[key] != b[key]:
				return _reject("incompatible_spatial_or_capability")
		if _state.logistics_port != null and not _state.logistics_port.get_ref().compatible(a, b, false):
			return _reject("incompatible_supply_capability")
		if a.get("spatial", {}) != b.get("spatial", {}):
			return _reject("incompatible_spatial_route")
		var am: Dictionary = _current_mission(str(values.survivor), a)
		var bm: Dictionary = _current_mission(str(values.donor), b)
		am.erase("id")
		bm.erase("id")
		if am != bm:
			return _reject("incompatible_mission")
	elif request.kind == "attach":
		if not _keys(values, ["target", "parent", "until"]) or not _number(values.get("until")) or float(values.until) <= float(request.effective_time):
			return _reject("invalid_attachment_interval")
		var target: String = str(values.get("target", ""))
		var destination: String = str(values.get("parent", ""))
		if not _contains(owner, target) or not _contains(owner, destination) or target == owner or not active(target) or not active(destination):
			return _reject("outside_effective_scope")
		if _nodes[target].side != _nodes[destination].side or Roles.ECHELONS.find(str(_nodes[destination].echelon)) != Roles.ECHELONS.find(str(_nodes[target].echelon)) + 1 or destination == parent(target):
			return _reject("incompatible_parent")
		if _attachments.has(target) and float(_attachments[target].until) > float(request.effective_time):
			return _reject("overlapping_attachment")
		for id: String in _pending.get(target, {}):
			if id == request.id:
				continue
			var other: Dictionary = _requests[id]
			if float(request.effective_time) < float(other.values.until) and float(other.effective_time) < float(values.until):
				return _reject("overlapping_attachment")
		if _state.event_ids.has("structure_expiry_" + str(request.id)):
			return _reject("expiry_id_collision")
	elif request.kind == "revoke":
		if not _keys(values, ["target"]) or not _attachments.has(values.get("target", "")) or not _contains(owner, str(values.target)) or not _contains(owner, str(_nodes[values.target].parent)):
			return _reject("invalid_revoke_scope")
	else:
		return _reject("unknown_structure_kind")
	if executing and float(request.effective_time) != _state.time:
		return _reject("wrong_time_boundary")
	return {"ok": true}

func _validate_continuity(request: Dictionary, executing: bool) -> Dictionary:
	var target: String = str(request.values.get("target", ""))
	if not active(target) or _nodes[target].echelon != "squad":
		return _reject("continuity_requires_single_squad")
	if executing and request.kind == "revoke" and str(_attachments.get(target, {}).get("id", "")) != str(request.get("attachment_id", "")):
		return _reject("stale_attachment_revoke")
	var unit_id: String = str(_nodes[target].unit_id)
	var unit: Dictionary = _lod.preview_leaf(unit_id)
	continuity_work.leaf_previews += 1
	continuity_work.dependency_records += 4
	if unit.is_empty():
		return _reject("live_attachment_unit_required")
	var gameplay: RefCounted = _state.gameplay_port.get_ref() if _state.gameplay_port != null else null
	if _state.coordination.has(unit_id) and (gameplay == null or not gameplay.can_transfer_dependencies(unit_id)):
		return _reject("attachment_special_preparation_policy_required")
	if _state.command_coordination.has(unit_id) or _state.tactical_intents.has(unit_id):
		return _reject("attachment_timed_or_tactical_policy_required")
	if not (_state.mission_dependents.get(unit.mission_id, {}) as Dictionary).is_empty() and not _state.missions[unit.mission_id].has("goal_v1"):
		return _reject("attachment_legacy_task_dependents_policy_required")
	if _state.gameplay_port != null and _state.gameplay_port.get_ref().requires_detail(unit_id) and _lod.representation_of(unit_id) != unit_id:
		return _reject("personal_goal_leaf_requires_detail")
	return {"ok": true}

func _current_mission(id: String, leaf: Dictionary) -> Dictionary:
	var representation: String = _lod.representation_of(id)
	work.structure_records_examined += 1
	if representation != id:
		_lod.work.formation_records_examined += 1
		return _state.missions[_state.units[representation].mission_id].duplicate(true)
	return _state.missions[leaf.mission_id].duplicate(true)

func _validate_company_split(request: Dictionary, owner: String) -> Dictionary:
	var v: Dictionary = request.values
	var source: String = str(v.source)
	if not _contains(owner, source) or not _contains(owner, str(_nodes[source].parent)) or _attachments.has(source) or _leaves[source].is_empty():
		return _reject("company_split_requires_superior_scope")
	if not v.get("new_id") is String or not v.get("new_node") is String or str(v.new_id).is_empty() or v.new_id != v.new_node or _state.identity_reserved(str(v.new_id)) or _state.unit_event_counts.has(v.new_id):
		return _reject("identity_collision")
	var total: Dictionary = {}
	for key: String in stock_keys():
		total[key] = 0.0
	for child: String in _children[source]:
		if _nodes[child].echelon != "platoon" or _nodes[child].parent != source or _attachments.has(child) or _used_nodes.has(str(v.new_id) + "_" + child):
			return _reject("company_child_migration_required")
	for leaf: String in _leaves[source]:
		work.structure_records_examined += 1
		var unit_id: String = str(_nodes[leaf].unit_id)
		var new_unit: String = str(v.new_id) + "_" + unit_id
		if _used_nodes.has("node_" + new_unit) or _used_units.has(new_unit) or _state.knows_unit(new_unit) or _state.unit_event_counts.has(new_unit) or _state.missions.has("structure_" + str(request.id) + "_" + unit_id + "_mission") or not _clear_leaf(unit_id):
			return _reject("company_leaf_migration_required")
		var unit: Dictionary = _lod.preview_leaf(unit_id)
		for key: String in stock_keys():
			total[key] += float(unit.get(key, 0.0))
	if not _number(v.allocation.personnel_total) or float(total.personnel_total) <= 0.0:
		return _reject("invalid_allocation")
	var fraction: float = float(v.allocation.personnel_total) / float(total.personnel_total)
	if fraction <= 0.0 or fraction >= 1.0:
		return _reject("empty_or_full_detachment")
	for key: String in stock_keys():
		if not _number(v.allocation[key]) or absf(float(v.allocation[key]) - float(total[key]) * fraction) > EPS:
			return _reject("proportional_allocation_required")
	for leaf: String in _leaves[source]:
		var size: float = float(_lod.preview_leaf(str(_nodes[leaf].unit_id)).personnel_total)
		if size * fraction < MIN_REMAINDER or size * (1.0 - fraction) < MIN_REMAINDER:
			return _reject("empty_or_full_detachment")
	return {"ok": true}

func _split_company(request: Dictionary, changed: Dictionary) -> void:
	var source: String = str(request.values.source)
	var fresh: String = str(request.values.new_id)
	var source_leaves: Array[String] = State.sorted_ids(_leaves[source])
	var size: float = 0.0
	for leaf: String in source_leaves:
		size += float(_state.units[_nodes[leaf].unit_id].personnel_total)
	var fraction: float = float(request.values.allocation.personnel_total) / size
	_nodes[fresh] = _nodes[source].duplicate(true)
	_nodes[fresh].provenance = {"from": source, "event": request.id, "time": _state.time}
	_children[fresh] = {}
	_leaves[fresh] = {}
	_used_nodes[fresh] = true
	_used_units[fresh] = true
	_children[parent(source)][fresh] = true
	for child: String in State.sorted_ids(_children[source]):
		var clone: String = fresh + "_" + child
		_nodes[clone] = _nodes[child].duplicate(true)
		_nodes[clone].parent = fresh
		_nodes[clone].provenance = {"from": child, "event": request.id, "time": _state.time}
		_children[clone] = {}
		_leaves[clone] = {}
		_children[fresh][clone] = true
		_used_nodes[clone] = true
	for leaf: String in source_leaves:
		var unit: String = str(_nodes[leaf].unit_id)
		var allocation: Dictionary = {}
		for key: String in stock_keys():
			allocation[key] = float(_state.units[unit].get(key, 0.0)) * fraction
		var new_unit: String = fresh + "_" + unit
		_split({"id": str(request.id) + "_" + unit, "values": {"source": unit, "new_id": new_unit,
			"new_node": "node_" + new_unit, "allocation": allocation}}, changed)
		var destination: String = fresh + "_" + str(_nodes[leaf].parent)
		_reparent("node_" + new_unit, destination)
		_nodes["node_" + new_unit].parent = destination
	work.relations_changed += 1

func _contains(owner: String, target: String) -> bool:
	if not active(target):
		return false
	return owner in _path(target)

func _leaf_scope(owner: String, unit: String) -> bool:
	work.structure_records_examined += 1
	return _unit_nodes.has(unit) and _leaves[owner].has(_unit_nodes[unit]) and active(str(_unit_nodes[unit]))

func _clear_leaf(id: String) -> bool:
	var unit: Dictionary = _lod.preview_leaf(id)
	return not _attachments.has(_unit_nodes[id]) and not _state.unit_event_counts.has(id) and not _state.coordination.has(id) and not _state.command_coordination.has(id) and not _state.tactical_intents.has(id) and (_state.mission_dependents.get(unit.mission_id, {}) as Dictionary).is_empty() and str(_state.missions[unit.mission_id].destination).is_empty()

func _materialize(target: String, changed: Dictionary, retired: Dictionary) -> void:
	var memberships: Dictionary = {}
	for leaf: String in State.sorted_ids(_leaves[target]):
		work.structure_records_examined += 1
		var unit: String = str(_nodes[leaf].unit_id)
		var prior: String = _lod.representation_of(unit)
		var result: Dictionary = _lod.materialize_leaf(unit, "real_structure_boundary")
		assert(result.ok)
		work.leaves_materialized_for_structure += int(result.materialized)
		if int(result.materialized) > 0:
			memberships[prior] = true
		for id: String in result.get("changed", [unit]):
			changed[id] = true
		for id: String in result.get("retired", []):
			retired[id] = true
			changed.erase(id)
	work.aggregate_memberships_rebuilt += memberships.size()

func _split(request: Dictionary, changed: Dictionary) -> void:
	var values: Dictionary = request.values
	var source: Dictionary = _state.units[values.source]
	var fresh: Dictionary = source.duplicate(true)
	var fraction: float = float(values.allocation.personnel_total) / float(source.personnel_total)
	fresh.id = values.new_id
	for key: String in stock_keys():
		fresh[key] = float(source.get(key, 0.0)) * fraction
		source[key] = float(source.get(key, 0.0))
		source[key] -= float(fresh[key])
	var weight: float = float(source.get("tactical_weight", 1.0))
	fresh.tactical_weight = weight * fraction
	source.tactical_weight = weight - float(fresh.tactical_weight)
	var mission: Dictionary = _state.missions[source.mission_id].duplicate(true)
	mission.id = "structure_" + str(request.id) + "_mission"
	_state.add_mission(mission)
	fresh.mission_id = mission.id
	fresh.structure_provenance = {"from": source.id, "event": request.id, "time": _state.time}
	_state.units[fresh.id] = fresh
	_state.area_units[fresh.area_id][fresh.id] = true
	var source_node: String = str(_unit_nodes[source.id])
	var parent_id: String = str(_nodes[source_node].parent)
	_nodes[values.new_node] = {"echelon": "squad", "side": source.side, "parent": parent_id,
		"unit_id": fresh.id, "provenance": fresh.structure_provenance.duplicate(true)}
	_unit_nodes[fresh.id] = values.new_node
	_used_nodes[values.new_node] = true
	_used_units[fresh.id] = true
	_children[values.new_node] = {}
	_leaves[values.new_node] = {values.new_node: true}
	_node_people[values.new_node] = {}
	# A split follows both the permanent and current operational parent of source.
	var operational: String = parent(source_node)
	_children[operational][values.new_node] = true
	for ancestor: String in _path(operational):
		_leaves[ancestor][values.new_node] = true
		work.authority_scopes_updated += 1
	changed[source.id] = true
	changed[fresh.id] = true
	work.relations_changed += 1
	_state.contacts.erase(source.area_id)
	_state.wake(str(source.area_id))

func _merge(request: Dictionary, changed: Dictionary, retired: Dictionary) -> void:
	var a: Dictionary = _state.units[request.values.survivor]
	var b: Dictionary = _state.units[request.values.donor]
	for key: String in stock_keys():
		a[key] = float(a.get(key, 0.0)) + float(b.get(key, 0.0))
	if _state.gameplay_port != null:
		_state.gameplay_port.get_ref().tactics.unit_merged(str(b.id), str(a.id))
	for key: String in ["fatigue", "suppression", "distance_moved"]:
		a[key] = maxf(float(a[key]), float(b[key]))
	a.cohesion = minf(float(a.cohesion), float(b.cohesion))
	a.tactical_weight = float(a.get("tactical_weight", 1.0)) + float(b.get("tactical_weight", 1.0))
	var id: String = str(_unit_nodes[b.id])
	_retired[id] = {"time": _state.time, "into": a.id, "event": request.id, "historical_unit_not_current": b.duplicate(true)}
	for ancestor: String in _path(id):
		_leaves[ancestor].erase(id)
		work.authority_scopes_updated += 1
	_children[parent(id)].erase(id)
	_attachments.erase(id)
	_state.units.erase(b.id)
	_state.area_units[b.area_id].erase(b.id)
	changed.erase(b.id)
	changed[a.id] = true
	retired[b.id] = true
	work.relations_changed += 1
	_state.contacts.erase(a.area_id)
	_state.wake(str(a.area_id))

func _reparent(target: String, destination: String) -> void:
	var previous: String = parent(target)
	var moving: Dictionary = _leaves[target]
	var old_path: Array[String] = _path(previous)
	var new_path: Array[String] = _path(destination)
	_children[previous].erase(target)
	_children[destination][target] = true
	for ancestor: String in old_path:
		if ancestor not in new_path:
			for leaf: String in moving:
				work.structure_records_examined += 1
				_leaves[ancestor].erase(leaf)
			work.authority_scopes_updated += 1
	for ancestor: String in new_path:
		if ancestor not in old_path:
			_leaves[ancestor].merge(moving)
			work.structure_records_examined += moving.size()
			work.authority_scopes_updated += 1
	work.relations_changed += 1

func snapshot() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	return {"time": _state.time, "nodes": _nodes.duplicate(true), "children": _children.duplicate(true),
		"leaves": _leaves.duplicate(true), "attachments": _attachments.duplicate(true),
		"pending": _pending.duplicate(true), "requests": _requests.duplicate(true),
		"retired_history_not_current": _retired.duplicate(true), "history": history.duplicate(true)}

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _keys(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if key not in allowed:
			return false
	return true

static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}

const RUNTIME_FIELDS: Array[String] = ["_nodes", "_people", "_node_people", "member_adjustments", "_positions", "_person_positions", "_children", "_leaves", "_unit_nodes", "_requests", "_attachments", "_pending", "_retired", "_used_units", "_used_nodes", "history", "attachment_continuity", "continuity_work", "work"]

func runtime_state() -> Dictionary:
	return {"fields": State.capture_runtime_fields(self, RUNTIME_FIELDS), "movements": movements.runtime_state()}

func restore_runtime(image: Dictionary) -> bool:
	return image.get("fields") is Dictionary and image.get("movements") is Dictionary and State.restore_runtime_fields(self, image.fields, RUNTIME_FIELDS) and movements.restore_runtime(image.movements)

func bind_runtime(state: State, lod: RefCounted) -> void:
	_state = state
	_lod = lod
	_members.configure(self)
	movements.configure(self)
	state.structure_port = weakref(self)
