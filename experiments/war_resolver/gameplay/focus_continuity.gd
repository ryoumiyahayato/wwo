extends RefCounted
## A bounded, pre-existing relation catalogue; changing focus transfers no facts.
var _owner: WeakRef
var _links: Dictionary = {}
var _tickets: Dictionary = {}
var history: Array[Dictionary] = []
var _serial: int = 0

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func relate(a: String, b: String, basis: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	var p: RefCounted = g.participants
	if g._state.time != 0.0 or a == b or not p._units.has(a) or not p._units.has(b):
		return false
	var an: String = str(s._people[a].formation_id)
	var bn: String = str(s._people[b].formation_id)
	var valid: bool = basis == "same_squad" and an == bn or basis == "same_platoon" and s.parent(an) == s.parent(bn) and not s.parent(an).is_empty() or basis == "local_contact" and p._distance(p.position(a), p.position(b)) <= float(p.rules.local_radius_km) or basis == "command_service" and (s._contains(an, bn) or s._contains(bn, an)) or basis == "scenario_family"
	if not valid or s._nodes[an].side != s._nodes[bn].side:
		return false
	if _links.get(a, {}).size() >= p.MAX_PEOPLE or _links.get(b, {}).size() >= p.MAX_PEOPLE:
		return false
	if not _links.has(a):
		_links[a] = {}
	if not _links.has(b):
		_links[b] = {}
	_links[a][b] = {"basis": basis, "since": g._state.time}
	_links[b][a] = {"basis": basis, "since": g._state.time}
	return true

func event_relation(a: String, b: String, basis: String, cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var p: RefCounted = g.participants
	if a == b or cause.is_empty() or basis not in ["medical_contact", "rescue_contact", "remains_collection", "delivered_command", "shared_movement"] or not p._units.has(a) or not p._units.has(b):
		return
	if p._physical_unit(a).side != p._physical_unit(b).side:
		return
	if _links.get(a, {}).size() >= p.MAX_PEOPLE or _links.get(b, {}).size() >= p.MAX_PEOPLE:
		return
	if not _links.has(a):
		_links[a] = {}
	if not _links.has(b):
		_links[b] = {}
	if not _links[a].has(b):
		var relation: Dictionary = {"basis": basis, "since": g._state.time, "cause_ref": cause}
		_links[a][b] = relation
		_links[b][a] = relation.duplicate()

func candidates(person: String) -> Array[Dictionary]:
	var g: RefCounted = _owner.get_ref()
	var result: Array[Dictionary] = []
	if not g.participants._units.has(person) or g.participants._member(person).actionable:
		return result
	for id: String in _links.get(person, {}):
		if g.participants.can_intend(id) and not g.participants.dead(id):
			result.append({"person_ref": id, "basis": _links[person][id].basis})
	return result

func request(previous: String, next: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if g._state.public_pending():
		return {"ok": false, "error": "PENDING_RETRY_WHEN_READY"}
	if g.focused_person != previous or not _eligible(previous, next):
		return {"ok": false, "error": "existing_related_able_person_required_after_incapacity_or_death"}
	var capacity: Dictionary = g._state.structure_port.get_ref()._members._representation_capacity([str(g.participants._units[next])])
	if not capacity.ok:
		return capacity
	_serial += 1
	var id: String = "control_focus_%d" % _serial
	_tickets[id] = {"previous": previous, "next": next, "due": g._state.time}
	if not g._state.schedule_event(id, g._state.time, "gameplay", {"focus_id": id}):
		_tickets.erase(id)
		return {"ok": false, "error": "focus_schedule_failed"}
	return {"ok": true, "status": "FOCUS_SCHEDULED", "event_ref": id}

func _eligible(previous: String, next: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	return g.participants._units.has(previous) and not g.participants._member(previous).actionable and _links.get(previous, {}).has(next) and g.participants.can_intend(next) and not g.participants.dead(next)

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and payload.get("focus_id", "") == id and _tickets.has(id) and _tickets[id].due == due

func process_event(event: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var ticket: Dictionary = _tickets[event.id]
	_tickets.erase(event.id)
	if g.focused_person != ticket.previous or not _eligible(str(ticket.previous), str(ticket.next)):
		return {"changed": [], "retired": [], "record": {"kind": "focus_rejected", "reason": "candidate_unavailable"}}
	var body_unit: String = str(g.participants._units[ticket.next])
	var materialized: Dictionary = g._lod.materialize_leaf(body_unit, "existing_person_control_focus")
	if not materialized.ok:
		return {"changed": [], "retired": [], "record": {"kind": "focus_rejected", "reason": materialized.error}}
	g.focused_person = str(ticket.next)
	var record: Dictionary = {"kind": "control_focus_changed", "from": ticket.previous, "to": ticket.next, "time": g._state.time,
		"basis": _links[ticket.previous][ticket.next].basis}
	history.append(record)
	return {"changed": materialized.get("changed", [body_unit]), "retired": materialized.get("retired", []), "record": record}

const RUNTIME_FIELDS: Array[String] = ["_links", "_tickets", "history", "_serial"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
