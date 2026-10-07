extends RefCounted
## Opt-in synthetic spatial facts. The inherited resolver owns combat and time.
signal route_feedback(unit_id: String, kind: String, cause_ref: String)
const State = preload("res://experiments/war_resolver/battle_state.gd")
var _state: State
var _lod: RefCounted
var _nodes: Dictionary = {}
var _edges: Dictionary = {}
var _lanes: Dictionary = {}
var _facts: Dictionary = {}
var _cell_scope: Dictionary = {}
var _scope_cells: Dictionary = {}
var _cell_nodes: Dictionary = {}
var _cell_edges: Dictionary = {}
var _loaded: Dictionary = {}
var _facility_summaries: Dictionary = {}
var work: Dictionary = {"input_records_examined": 0, "route_records_examined": 0,
	"spatial_events_processed": 0, "future_facts_examined": 0, "fact_nodes_updated": 0,
	"fact_ancestors_updated": 0, "geometry_records_loaded": 0, "query_records_examined": 0}

func configure(state: State, lod: RefCounted, nodes: Dictionary, edges: Dictionary, lanes: Dictionary) -> bool:
	if _state != null or state.time != 0.0 or state.spatial_port != null or not lod.owns_state(state) or not state.events.is_empty() or nodes.is_empty():
		return false
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		if id.is_empty() or not _xy_valid(node.get("xy")) or not state.areas.has(node.get("cell", "")) or not node.get("scope") is String or str(node.scope).is_empty() or not _ground_valid(node.get("ground")):
			return false
	var cell_scopes: Dictionary = {}
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		if cell_scopes.has(node.cell) and cell_scopes[node.cell] != node.scope:
			return false
		cell_scopes[node.cell] = node.scope
	for id: String in edges:
		var edge: Dictionary = edges[id]
		if id.is_empty() or not nodes.has(edge.get("from", "")) or not nodes.has(edge.get("to", "")) or edge.from == edge.to or not _positive(edge.get("length_km")) or not edge.get("open") is bool or edge.get("kind") not in ["road", "bridge", "footpath", "rail"] or not edge.get("modes") is Array or not _ground_valid(edge.get("ground")) or not _nonnegative(edge.get("capacity")):
			return false
		if nodes[edge.from].scope != nodes[edge.to].scope or float(edge.length_km) + 0.00000001 < _distance(nodes[edge.from].xy, nodes[edge.to].xy):
			return false
		for mode: Variant in edge.modes:
			if mode not in ["FOOT", "MOTORIZED"] or edge.kind == "rail":
				return false
	for key: String in lanes:
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2 or not nodes.has(parts[0]) or not nodes.has(parts[1]) or not lanes[key] is Dictionary or not lanes[key].get("observe") is bool or not lanes[key].get("fire") is bool:
			return false
	_state = state
	_lod = lod
	_nodes = nodes.duplicate(true)
	_edges = edges.duplicate(true)
	_lanes = lanes.duplicate(true)
	for id: String in State.sorted_ids(nodes):
		var node: Dictionary = nodes[id]
		_cell_scope[node.cell] = node.scope
		if not _scope_cells.has(node.scope):
			_scope_cells[node.scope] = {}
		_scope_cells[node.scope][node.cell] = true
		if not _cell_nodes.has(node.cell):
			_cell_nodes[node.cell] = {}
		_cell_nodes[node.cell][id] = true
		work.input_records_examined += 1
	for id: String in edges:
		var cell: String = str(nodes[edges[id].from].cell)
		if not _cell_edges.has(cell):
			_cell_edges[cell] = {}
		_cell_edges[cell][id] = true
		work.input_records_examined += 1
		if not edges[id].open:
			_fold_facility(cell, 1)
	state.spatial_port = weakref(self)
	return true

func reset_work() -> void:
	for key: String in work:
		work[key] = 0

func admit_unit(id: String, node: String, mode: String) -> bool:
	if _state == null or _state.time != 0.0 or not _state.units.has(id) or _state.units[id].has("spatial") or not _nodes.has(node) or mode not in ["FOOT", "MOTORIZED"] or _state.units[id].area_id != _nodes[node].cell:
		return false
	var unit: Dictionary = _state.units[id]
	if unit.has("supply_capability") and bool(unit.supply_capability.fuel_dependent) != (mode == "MOTORIZED"):
		return false
	unit.spatial = {"node": node, "edge": "", "from": node, "to": node, "progress": 0.0,
		"path": [], "traversed": [], "mode": mode, "returning": false, "retreating": false, "blocked_edge": "", "cause_ref": ""}
	unit.position = float(_nodes[node].xy[0])
	return true

func inject_path(id: String, path: Array) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state.time != 0.0 or _state.information_port != null:
		return _reject("initial_path_only")
	return set_path(id, path, false)

func validate_path(unit: Dictionary, path: Variant, returning: bool) -> Dictionary:
	if not unit.has("spatial") or not path is Array or path.is_empty() or path.size() > 64:
		return _reject("invalid_bounded_path")
	var route: Dictionary = unit.spatial
	var node: String = str(route.from) if returning and not str(route.edge).is_empty() else str(route.node)
	if not str(route.edge).is_empty() and not returning:
		return _reject("return_or_finish_current_edge_first")
	for id: Variant in path:
		if not id is String or not _edges.has(id):
			return _reject("unknown_edge")
		var edge: Dictionary = _edges[id]
		if node not in [edge.from, edge.to] or route.mode not in edge.modes:
			return _reject("noncontiguous_or_unsupported_path")
		node = str(edge.to) if node == edge.from else str(edge.from)
	return {"ok": true}

func set_path(id: String, path: Array, returning: bool = false, role: RefCounted = null, token: RefCounted = null) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state.information_port != null and not _state.information_port.get_ref().allows_role_delivery(role, token, false):
		return _reject("communication_delivery_required")
	if not _state.units.has(id):
		return _reject("route_requires_live_representation")
	var unit: Dictionary = _state.units[id]
	var valid: Dictionary = validate_path(unit, path, returning)
	if not valid.ok:
		return valid
	unit.spatial.path = path.duplicate()
	unit.spatial.returning = returning and not str(unit.spatial.edge).is_empty()
	unit.spatial.retreating = false
	unit.spatial.blocked_edge = ""
	_state.missions[unit.mission_id].status = "active"
	_state.missions[unit.mission_id].posture = "advance"
	_state.wake(str(unit.area_id))
	return {"ok": true, "status": "ROUTE_ADMITTED", "time": _state.time}

func resolution_scopes(active: Dictionary) -> Array[String]:
	var selected: Dictionary = {}
	for cell: String in active:
		var cells: Array[String] = scope_cells(cell)
		selected[cells[0]] = true
	return State.sorted_ids(selected)

func scope_cells(cell: String) -> Array[String]:
	if _cell_scope.has(cell):
		return State.sorted_ids(_scope_cells[_cell_scope[cell]])
	var cells: Array[String] = [cell]
	return cells

func combat_ids(cell: String) -> Array[String]:
	var selected: Dictionary = {}
	for member: String in scope_cells(cell):
		selected.merge(_state.area_units[member])
	return State.sorted_ids(selected)

func xy(unit: Dictionary) -> Array:
	if not unit.has("spatial"):
		return [float(unit.position), 0.0]
	var route: Dictionary = unit.spatial
	if str(route.edge).is_empty():
		return _nodes[route.node].xy.duplicate()
	var a: Array = _nodes[route.from].xy
	var b: Array = _nodes[route.to].xy
	var fraction: float = float(route.progress) / float(_edges[route.edge].length_km)
	return [float(a[0]) + (float(b[0]) - float(a[0])) * fraction,
		float(a[1]) + (float(b[1]) - float(a[1])) * fraction]

func terrain(unit: Dictionary) -> Dictionary:
	if not unit.has("spatial"):
		return _state.areas[unit.area_id]
	var route: Dictionary = unit.spatial
	var ground: Dictionary = _edges[route.edge].ground if not str(route.edge).is_empty() else _nodes[route.node].ground
	return {"cover": ground.cover, "concealment": ground.concealment, "visibility": ground.visibility,
		"frontage": ground.width, "movement_modifier": movement_factor(ground, str(route.mode))}

static func movement_factor(ground: Dictionary, mode: String) -> float:
	if mode == "MOTORIZED" and (float(ground.softness) > 0.65 or float(ground.slope) > 0.3):
		return 0.0
	return 1.0 / (1.0 + float(ground.resistance) + float(ground.softness) * (3.0 if mode == "MOTORIZED" else 1.0) + float(ground.slope) * (4.0 if mode == "MOTORIZED" else 2.0))

func detection(source: Dictionary, target: Dictionary) -> float:
	if _distance(xy(source), xy(target)) > float(source.weapon.range_km):
		return 0.0
	if not source.has("spatial") or not target.has("spatial"):
		return 0.0 if source.area_id != target.area_id else float(terrain(source).visibility) * (1.0 - float(terrain(source).concealment))
	var key: String = str(source.spatial.node) + ":" + str(target.spatial.node)
	var lane: Dictionary = _lanes.get(key, {})
	if not lane.get("observe", false) or not lane.get("fire", false):
		return 0.0
	var target_ground: Dictionary = terrain(target)
	return float(target_ground.visibility) * (1.0 - float(target_ground.concealment))

func _next(unit: Dictionary) -> Dictionary:
	var route: Dictionary = unit.spatial
	if not str(route.edge).is_empty():
		return {"edge": route.edge, "from": route.from, "to": route.to}
	if route.path.is_empty():
		return {}
	var edge_id: String = str(route.path[0])
	var edge: Dictionary = _edges[edge_id]
	return {"edge": edge_id, "from": route.node, "to": edge.to if route.node == edge.from else edge.from}

func prepare_movement(unit: Dictionary, plan: Dictionary) -> void:
	if not unit.has("spatial"):
		return
	work.route_records_examined += 1
	plan.speed = 0.0
	plan.route_edge = _next(unit)
	plan.route_blocked = ""
	plan.route_retreat = plan.posture == "withdraw" and _state.missions[unit.mission_id].posture != "withdraw"
	if plan.route_retreat and str(unit.spatial.edge).is_empty():
		if unit.spatial.traversed.is_empty():
			plan.route_edge = {}
		else:
			var previous: String = str(unit.spatial.traversed[-1])
			var known: Dictionary = _edges[previous]
			plan.route_edge = {"edge": previous, "from": unit.spatial.node,
				"to": known.to if unit.spatial.node == known.from else known.from}
	if plan.route_edge.is_empty() or plan.posture not in ["advance", "withdraw"] or plan.advance_inhibited:
		return
	var edge: Dictionary = _edges[plan.route_edge.edge]
	# Retreat along already occupied geometry remains possible after closure.
	if not unit.spatial.returning and not plan.route_retreat and not edge.open:
		plan.route_blocked = plan.route_edge.edge
		return
	var factor: float = movement_factor(edge.ground, str(unit.spatial.mode))
	if factor == 0.0:
		plan.route_blocked = plan.route_edge.edge
		return
	var ground: Dictionary = terrain(unit)
	plan.speed = float(unit.mobility) * factor * float(unit.readiness)
	plan.speed *= minf(1.0, float(ground.frontage) / maxf(1.0, float(plan.get("side_frontage", 1.0))))
	plan.speed *= (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
	if unit.spatial.returning or plan.route_retreat and not str(unit.spatial.edge).is_empty() and not unit.spatial.retreating:
		plan.speed = -float(plan.speed)

func movement_eta(unit: Dictionary, plan: Dictionary) -> float:
	if not unit.has("spatial") or float(plan.speed) == 0.0:
		return INF
	var edge: Dictionary = _edges[plan.route_edge.edge]
	var remaining: float = float(unit.spatial.progress) if float(plan.speed) < 0.0 else float(edge.length_km) - float(unit.spatial.progress)
	return remaining / absf(float(plan.speed)) * 60.0

func move(unit: Dictionary, plan: Dictionary, minutes: float, log: Array[Dictionary]) -> float:
	var route: Dictionary = unit.spatial
	if plan.get("route_retreat", false) and plan.route_edge.is_empty():
		# No previous leg exists: remain at this known node, never invent a route.
		route.path.clear()
		_state.missions[unit.mission_id].status = "withdrawn"
		unit.action = "withdrawn"
		log.append({"time": _state.time, "kind": "mission_withdrawn", "unit_id": unit.id, "mission_id": unit.mission_id})
		return 0.0
	if not str(plan.get("route_blocked", "")).is_empty():
		var blocked: String = str(plan.route_blocked)
		if route.blocked_edge != blocked:
			route.blocked_edge = blocked
			route.cause_ref = _edges[blocked].get("last_fact_id", "terrain_input")
			log.append({"id": "blocked_" + str(unit.id) + "_" + str(route.cause_ref), "time": _state.time,
				"kind": "route_blocked", "unit_id": unit.id, "edge_ref": blocked, "cause_ref": route.cause_ref,
				"scope": unit.area_id, "execution": "BLOCKED"})
			route_feedback.emit(str(unit.id), "BLOCKED", str(route.cause_ref))
	if float(plan.speed) == 0.0 or unit.action == "disabled":
		return 0.0
	if str(route.edge).is_empty():
		route.edge = plan.route_edge.edge
		route.from = plan.route_edge.from
		route.to = plan.route_edge.to
		route.progress = 0.0
	elif plan.get("route_retreat", false) and not route.retreating:
		route.returning = true
	if plan.get("route_retreat", false):
		# A reverse leg started at a node keeps its orientation across segments.
		route.retreating = true
	var old_progress: float = float(route.progress)
	var length: float = float(_edges[route.edge].length_km)
	route.progress = clampf(old_progress + float(plan.speed) * minutes, 0.0, length)
	var travelled: float = absf(float(route.progress) - old_progress)
	unit.position = float(xy(unit)[0])
	if absf(float(route.progress) - (0.0 if route.returning else length)) < 0.00000001:
		var previous: String = str(unit.area_id)
		route.node = route.from if route.returning else route.to
		if not route.returning and not plan.get("route_retreat", false):
			route.path.pop_front()
			route.traversed.append(route.edge)
		route.edge = ""
		route.progress = 0.0
		route.returning = false
		route.retreating = false
		route.blocked_edge = ""
		unit.position = float(_nodes[route.node].xy[0])
		var destination: String = str(_nodes[route.node].cell)
		if destination != previous:
			_state.area_units[previous].erase(unit.id)
			_state.area_units[destination][unit.id] = true
			unit.area_id = destination
			_lod.on_spatial_transfer(str(unit.id), previous, destination)
			_state.wake(destination)
			log.append({"time": _state.time, "kind": "area_transition", "unit_id": unit.id, "from": previous, "to": destination})
		log.append({"time": _state.time, "kind": "route_arrival", "unit_id": unit.id, "node_ref": route.node})
		route_feedback.emit(str(unit.id), "ARRIVED", "")
		if plan.get("route_retreat", false):
			route.path.clear()
			_state.missions[unit.mission_id].status = "withdrawn"
			unit.action = "withdrawn"
			log.append({"time": _state.time, "kind": "mission_withdrawn", "unit_id": unit.id, "mission_id": unit.mission_id})
		elif route.path.is_empty():
			_state.missions[unit.mission_id].status = "complete"
			log.append({"time": _state.time, "kind": "mission_complete", "unit_id": unit.id, "mission_id": unit.mission_id})
	return travelled

func can_move(unit: Dictionary) -> bool:
	if not unit.has("spatial"):
		return true
	var next: Dictionary = _next(unit)
	return not next.is_empty() and (unit.spatial.returning or _edges[next.edge].open) and movement_factor(_edges[next.edge].ground, str(unit.spatial.mode)) > 0.0

func schedule_fact(id: String, due: float, edge: String, open: bool) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if id.is_empty() or _facts.has(id) or not _edges.has(edge) or not is_finite(due) or due < _state.time:
		return _reject("invalid_external_fact")
	_facts[id] = {"id": id, "due": due, "edge_ref": edge, "open": open, "property": "open", "status": "PENDING"}
	if not _state.schedule_event("spatial_" + id, due, "spatial", {"fact_id": id}):
		_facts.erase(id)
		return _reject("fact_schedule_failed")
	return {"ok": true, "time": due}

func schedule_ground(id: String, due: float, target_kind: String, target_ref: String, ground: Dictionary) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if id.is_empty() or _facts.has(id) or not is_finite(due) or due < _state.time or not _ground_valid(ground) or target_kind not in ["node", "edge"] or not (_nodes if target_kind == "node" else _edges).has(target_ref):
		return _reject("invalid_ground_fact")
	_facts[id] = {"id": id, "due": due, "target_kind": target_kind, "target_ref": target_ref,
		"ground": ground.duplicate(true), "property": "ground", "status": "PENDING"}
	if not _state.schedule_event("spatial_" + id, due, "spatial", {"fact_id": id}):
		_facts.erase(id)
		return _reject("fact_schedule_failed")
	return {"ok": true, "time": due}

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and _facts.has(payload.get("fact_id", "")) and id == "spatial_" + str(payload.fact_id) and _facts[payload.fact_id].due == due and _facts[payload.fact_id].status == "PENDING"

func process_event(event: Dictionary) -> Dictionary:
	if event.time != _state.time or not accepts_event(str(event.id), event.payload, float(event.time)):
		return {"changed": [], "retired": [], "record": _reject("invalid_fact_ticket")}
	var fact: Dictionary = _facts[event.payload.fact_id]
	work.spatial_events_processed += 1
	var affected: Array[String] = []
	if fact.property == "ground":
		var record: Dictionary = (_nodes if fact.target_kind == "node" else _edges)[fact.target_ref]
		record.ground = fact.ground.duplicate(true)
		record.last_fact_id = fact.id
		if fact.target_kind == "node":
			affected.append(str(fact.target_ref))
		else:
			affected.assign([record.from, record.to])
	else:
		var edge: Dictionary = _edges[fact.edge_ref]
		var cell: String = str(_nodes[edge.from].cell)
		if bool(edge.open) != bool(fact.open):
			_fold_facility(cell, -1 if fact.open else 1)
		edge.open = fact.open
		edge.last_fact_id = fact.id
		affected.assign([edge.from, edge.to])
	fact.status = "APPLIED"
	fact.processed_at = _state.time
	for node: String in affected:
		_state.wake(str(_nodes[node].cell))
	return {"changed": [], "retired": [], "record": fact.duplicate(true)}

func _fold_facility(cell: String, delta: int) -> void:
	var cursor: String = cell
	while not cursor.is_empty() and _lod.spatial.nodes.has(cursor):
		_facility_summaries[cursor] = int(_facility_summaries.get(cursor, 0)) + delta
		work.fact_nodes_updated += 1
		work.fact_ancestors_updated += int(cursor != cell)
		cursor = str(_lod.spatial.nodes[cursor].parent)

func load_cell(cell: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if not _state.areas.has(cell):
		return _reject("unknown_cell")
	var geometry: Dictionary = {}
	for id: String in _cell_nodes.get(cell, {}):
		geometry[id] = _nodes[id].xy.duplicate()
		work.geometry_records_loaded += 1
	_loaded[cell] = geometry
	return {"ok": true, "cell": cell, "geometry": geometry.duplicate(true)}

func unload_cell(cell: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	_loaded.erase(cell)
	return {"ok": true}

func edge_view(id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	work.query_records_examined += 1
	return _edges.get(id, {}).duplicate(true)

func facility_summary(id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	work.query_records_examined += 1
	return {"time": _state.time, "node_ref": id, "closed_facilities": _facility_summaries.get(id, 0)}

static func _xy_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

static func _ground_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("label") is String:
		return false
	for key: String in ["resistance", "width"]:
		if not _nonnegative(value.get(key)):
			return false
	for key: String in ["softness", "slope", "cover", "concealment", "visibility"]:
		if not _nonnegative(value.get(key)) or float(value[key]) > 1.0:
			return false
	return true

static func _distance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0

static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0

static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}
