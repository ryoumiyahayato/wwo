extends RefCounted
## Experimental military relations, not a formal Organization authority.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const Stocks: Array[String] = ["personnel_total", "effective", "casualties", "equipment", "equipment_lost", "ammunition", "ammo_spent"]
const EPS: float = 0.0000001
const MIN_REMAINDER: float = 0.000001
var _state: State
var _lod: RefCounted
var _nodes: Dictionary = {}
var _people: Dictionary = {}
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
	_state.structure_port = weakref(self)
	work = {"structure_records_examined": 0, "structure_events_processed": 0,
		"leaves_materialized_for_structure": 0, "aggregate_memberships_rebuilt": 0,
		"authority_scopes_updated": 0, "relations_changed": 0}
	return true

func stock_keys() -> Array[String]:
	return Stocks + _state.logistics_port.get_ref().EXTRA_STOCKS if _state.logistics_port != null else Stocks

func owns_state(state: State) -> bool:
	return state == _state

func knows_identity(id: String) -> bool:
	return _used_units.has(id)

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
		outcome = _validate(request, true)
		if request.kind == "attach":
			_pending[request.values.target].erase(request.id)
		if outcome.ok:
			var values: Dictionary = request.values
			if request.kind == "split":
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
			outcome = {"ok": true, "kind": request.kind, "values": values.duplicate(true)}
	var record: Dictionary = {"id": event.id, "time": _state.time, "actor": request.person_id, "outcome": outcome.duplicate(true)}
	history.append(record)
	return {"changed": State.sorted_ids(changed), "retired": State.sorted_ids(retired), "record": record}

func _validate(request: Dictionary, executing: bool) -> Dictionary:
	if executing and float(request.effective_time) != _state.time:
		return _reject("wrong_time_boundary")
	var person: Dictionary = _people[request.person_id]
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
		if not values.get("new_id") is String or not values.get("new_node") is String or str(values.new_id).is_empty() or str(values.new_node).is_empty() or _used_units.has(values.new_id) or _used_nodes.has(values.new_node) or _state.knows_unit(str(values.new_id)) or _state.unit_event_counts.has(values.new_id) or _state.missions.has("structure_" + str(request.id) + "_mission"):
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
	if not v.get("new_id") is String or not v.get("new_node") is String or str(v.new_id).is_empty() or v.new_id != v.new_node or _used_nodes.has(v.new_id) or _used_units.has(v.new_id) or _state.knows_unit(str(v.new_id)) or _state.unit_event_counts.has(v.new_id):
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
