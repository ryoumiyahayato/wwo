extends RefCounted
## Opt-in synthetic spatial facts. The inherited resolver owns combat and time.
signal route_feedback(unit_id: String, kind: String, cause_ref: String)
const State = preload("res://experiments/war_resolver/battle_state.gd")
var _state: State
var _lod: RefCounted
var _nodes: Dictionary = {}
var _edges: Dictionary = {}
var _lanes: Dictionary = {}
var _waterways: Dictionary = {} # External navigable connections over the same nodes.
var _facts: Dictionary = {}
var _cell_scope: Dictionary = {}
var _scope_cells: Dictionary = {}
var _scope_anchor: Dictionary = {}
var _cell_nodes: Dictionary = {}
var _cell_edges: Dictionary = {}
var _loaded: Dictionary = {}
var _facility_summaries: Dictionary = {}
var _position_sites: Dictionary = {}
var _positions: Dictionary = {}
var _node_positions: Dictionary = {}
var _local_sites: Dictionary = {}
var _local_edges: Dictionary = {}
var _local_lanes: Dictionary = {}
var _local_position_refs: Dictionary = {} # Derived links to existing earthworks.
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
	for scope: String in _scope_cells:
		_scope_anchor[scope] = State.sorted_ids(_scope_cells[scope])[0]
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
	if not unit.has("spatial") or not path is Array or path.size() > 64:
		return _reject("invalid_bounded_path")
	var route: Dictionary = unit.spatial
	if local_place(route) != "node:" + str(route.node) or str(route.get("local_edge", "")) != "":
		return _reject("actual_local_return_to_declared_road_access_required")
	if path.is_empty():
		return {"ok": true} if returning and not str(route.edge).is_empty() else _reject("invalid_bounded_path")
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
		selected[_scope_anchor[_cell_scope[cell]] if _cell_scope.has(cell) else cell] = true
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
	# A body source uses its actual road/local point; the node still selects the
	# declared visibility lane. This does not infer visibility over the whole edge.
	if route.has("point_xy"):
		return route.point_xy.duplicate()
	if str(route.edge).is_empty():
		return _nodes[route.node].xy.duplicate()
	var a: Array = _nodes[route.from].xy
	var b: Array = _nodes[route.to].xy
	var fraction: float = float(route.progress) / float(_edges[route.edge].length_km)
	return [float(a[0]) + (float(b[0]) - float(a[0])) * fraction,
		float(a[1]) + (float(b[1]) - float(a[1])) * fraction]

func admit_local_space(sites: Dictionary, links: Dictionary, lanes: Dictionary) -> bool:
	# Explicit finite geometry; no implicit node-to-neighbourhood reachability.
	if _state.time != 0.0 or not _local_sites.is_empty() or not _local_edges.is_empty() or sites.size() > 16 or links.size() > 16 or lanes.size() > 128:
		return false
	for id: String in sites:
		var site: Variant = sites[id]
		if id.is_empty() or ">" in id or id.begins_with("node:") or id.begins_with("segment:") or not site is Dictionary or not _nodes.has(site.get("node_ref", "")) or not _xy_valid(site.get("xy")) or not _ground_valid(site.get("ground")) or not _positive(site.get("enter_seconds")) or not _positive(site.get("radius_km")):
			return false
		if _nodes[site.node_ref].get("water", false) or _distance(site.xy, _nodes[site.node_ref].xy) > 0.25 or float(site.radius_km) > 0.02 or float(site.enter_seconds) > 120.0:
			return false
		if site.has("position_ref") and (not site.position_ref is String or str(site.position_ref).is_empty()):
			return false
		if site.has("cover_ref"):
			if site.has("position_ref") or not site.cover_ref is String or _state.gameplay_port == null:
				return false
			var cover: Dictionary = _state.gameplay_port.get_ref().participants._covers.get(site.cover_ref, {})
			if cover.is_empty() or cover.node != site.node_ref or _distance(cover.xy, site.xy) > 0.000001:
				return false
	for id: String in links:
		var link: Variant = links[id]
		if id.is_empty() or ">" in id or not link is Dictionary or not link.get("from") is String or not link.get("to") is String or link.from == link.to or not link.get("open") is bool or not _ground_valid(link.get("ground")) or not _positive(link.get("length_km")) or float(link.length_km) > 0.25:
			return false
		var a: Dictionary = _local_endpoint(str(link.from), sites)
		var b: Dictionary = _local_endpoint(str(link.to), sites)
		if a.is_empty() or b.is_empty() or _nodes[a.node_ref].get("water", false) or _nodes[b.node_ref].get("water", false) or _nodes[a.node_ref].cell != _nodes[b.node_ref].cell or float(link.length_km) + 0.00000001 < _distance(a.xy, b.xy):
			return false
	for key: String in lanes:
		var refs: PackedStringArray = key.split(">")
		if refs.size() != 2 or not _sight_known(refs[0], sites, links) or not _sight_known(refs[1], sites, links) or not lanes[key] is Dictionary or not lanes[key].get("observe") is bool or not lanes[key].get("fire") is bool:
			return false
	_local_sites = sites.duplicate(true)
	_local_edges = links.duplicate(true)
	_local_lanes = lanes.duplicate(true)
	_bind_local_positions()
	return true

func _bind_local_positions() -> void:
	_local_position_refs.clear()
	for site: Dictionary in _local_sites.values():
		if site.has("position_ref"):
			_local_position_refs[site.position_ref] = true
		if site.has("cover_ref"):
			_local_position_refs[site.cover_ref] = true

func _local_endpoint(reference: String, sites: Dictionary) -> Dictionary:
	if reference.begins_with("node:") and _nodes.has(reference.trim_prefix("node:")):
		var node: String = reference.trim_prefix("node:")
		return {"node_ref": node, "xy": _nodes[node].xy, "ground": _nodes[node].ground}
	return sites.get(reference, {})

func local_endpoint(reference: String) -> Dictionary:
	return _local_endpoint(reference, _local_sites)

func _sight_known(reference: String, sites: Dictionary, links: Dictionary) -> bool:
	return links.has(reference.trim_prefix("segment:")) if reference.begins_with("segment:") else not _local_endpoint(reference, sites).is_empty()

func local_place(route: Dictionary) -> String:
	return str(route.get("local_ref", "node:" + str(route.node)))

func sight_ref(route: Dictionary) -> String:
	return "segment:" + str(route.local_edge) if str(route.get("local_edge", "")) != "" else local_place(route)

func local_path_end(start: String, path: Array) -> String:
	var place: String = start
	for id: Variant in path:
		if not id is String or not _local_edges.has(id) or place not in [_local_edges[id].from, _local_edges[id].to]:
			return ""
		place = str(_local_edges[id].to if place == _local_edges[id].from else _local_edges[id].from)
	return place

func local_arrived(route: Dictionary, place: String) -> bool:
	return str(route.get("local_edge", "")) == "" and local_place(route) == place and _distance(xy({"spatial": route}), local_endpoint(place).xy) <= 0.000001

func _visibility_lane(source: Dictionary, target: Dictionary) -> Dictionary:
	var a: String = sight_ref(source)
	var b: String = str(target.get("sight_ref", sight_ref(target)))
	if a.begins_with("node:") and b.begins_with("node:"):
		return _lanes.get(a.trim_prefix("node:") + ":" + b.trim_prefix("node:"), {})
	return _local_lanes.get(a + ">" + b, {})

func entered_local_cover(route: Dictionary) -> float:
	var reference: String = local_place(route)
	if not _local_sites.has(reference) or route.get("entered_site_ref", "") != reference or str(route.get("local_edge", "")) != "":
		return 0.0
	var site: Dictionary = _local_sites[reference]
	if _distance(xy({"spatial": route}), site.xy) > float(site.radius_km):
		return 0.0
	if site.has("cover_ref"):
		var members: RefCounted = _state.gameplay_port.get_ref().participants
		if not members._covers.get(site.cover_ref, {}).get("available", false):
			return 0.0
		return 1.0 - (1.0 - float(site.ground.cover)) * members._cover_factor(str(site.cover_ref))
	return position_cover(str(site.position_ref)) if site.has("position_ref") and _positions.has(site.position_ref) else (0.0 if site.has("position_ref") else float(site.ground.cover))

func local_enterable(route: Dictionary) -> bool:
	var reference: String = local_place(route)
	if not _local_sites.has(reference) or not local_arrived(route, reference):
		return false
	var site: Dictionary = _local_sites[reference]
	if site.has("cover_ref"):
		return _state.gameplay_port.get_ref().participants._covers.get(site.cover_ref, {}).get("available", false)
	if not site.has("position_ref"):
		return true
	var position: Dictionary = _positions.get(site.position_ref, {})
	return not position.is_empty() and position.node_ref == site.node_ref and _distance(position.xy, site.xy) <= float(position.radius_km) and position_cover(str(site.position_ref)) > 0.0

func stationary_local(unit: Dictionary) -> bool:
	return unit.has("spatial") and _local_sites.has(local_place(unit.spatial)) and str(unit.spatial.get("local_edge", "")) == "" and unit.spatial.get("local_path", []).is_empty()

func landing_site(point: Array, anchor: String) -> Dictionary:
	# Consume only declared local surface bounds. Unknown surfaces stay unknown.
	var closest: String = anchor
	var surface: String = "UNKNOWN"
	var distance: float = INF
	for id: String in _cell_nodes[_nodes[anchor].cell]:
		var node: Dictionary = _nodes[id]
		var bounds: Array = node.get("surface_bounds_km", [])
		if bounds.size() != 4 or float(point[0]) < float(bounds[0]) or float(point[1]) < float(bounds[1]) or float(point[0]) > float(bounds[2]) or float(point[1]) > float(bounds[3]):
			continue
		var d: float = _distance(point, node.xy)
		if d < distance:
			distance = d
			closest = id
			surface = "WATER" if node.get("water", false) else "LAND"
	return {"node_ref": closest, "surface": surface, "xy": point.duplicate()}

func road_point(edge_id: String, point: Array) -> Dictionary:
	if not _edges.has(edge_id) or point.size() != 2:
		return {}
	var edge: Dictionary = _edges[edge_id]
	var a: Array = _nodes[edge.from].xy
	var b: Array = _nodes[edge.to].xy
	var dx: float = float(b[0]) - float(a[0])
	var dy: float = float(b[1]) - float(a[1])
	var squared: float = dx * dx + dy * dy
	if squared <= 0.000000000001:
		return {}
	var fraction: float = ((float(point[0]) - float(a[0])) * dx + (float(point[1]) - float(a[1])) * dy) / squared
	var projected: Array = [float(a[0]) + fraction * dx, float(a[1]) + fraction * dy]
	if not is_finite(fraction) or fraction < -0.000001 or fraction > 1.000001 or _distance(point, projected) > 0.000001:
		return {} # Only the existing straight edge interpretation is supported.
	return {"edge_ref": edge_id, "from_node": edge.from, "to_node": edge.to, "progress_km": clampf(fraction, 0.0, 1.0) * float(edge.length_km), "xy": point.duplicate()}

func terrain(unit: Dictionary) -> Dictionary:
	if not unit.has("spatial"):
		return _state.areas[unit.area_id]
	var route: Dictionary = unit.spatial
	var local_edge: String = str(route.get("local_edge", ""))
	var local_site: String = local_place(route)
	var local: bool = local_edge != "" or _local_sites.has(local_site)
	var ground: Dictionary = _local_edges[local_edge].ground if local_edge != "" else (_local_sites[local_site].ground if _local_sites.has(local_site) else (_edges[route.edge].ground if not str(route.edge).is_empty() else _nodes[route.node].ground))
	var local_cover: float = float(ground.cover)
	if local and local_edge == "":
		local_cover = entered_local_cover(route)
	if not local and str(route.edge).is_empty():
		for id: String in _node_positions.get(route.node, {}):
			var position: Dictionary = _positions[id]
			if position.kind != "personal" and not _local_position_refs.has(id) and _distance(xy(unit), position.xy) <= float(position.radius_km):
				local_cover = maxf(local_cover, float(position.cover) * float(position.integrity) * float(position.progress))
	return {"cover": local_cover, "concealment": ground.concealment, "visibility": ground.visibility,
		"frontage": ground.width, "movement_modifier": movement_factor(ground, str(route.mode))}

func admit_position_site(node: String, kinds: Array) -> bool:
	if _state.time != 0.0 or _position_sites.size() >= 8 or _position_sites.has(node) or not _nodes.has(node) or _nodes[node].get("water", false) or float(_nodes[node].ground.slope) > 0.3 or kinds.is_empty():
		return false
	for kind: Variant in kinds:
		if kind not in ["personal", "squad", "weapon"]:
			return false
	_position_sites[node] = kinds.duplicate()
	return true

func prepare_position(producer: RefCounted, id: String, node: String, kind: String, point: Array) -> bool:
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().operations or kind not in _position_sites.get(node, []) or _positions.size() >= 16 and not _positions.has(id) or not _xy_valid(point) or _distance(point, _nodes[node].xy) > 0.02:
		return false
	if _positions.has(id):
		return _positions[id].node_ref == node and _positions[id].kind == kind and _positions[id].xy == point
	_positions[id] = {"id": id, "node_ref": node, "kind": kind, "xy": point.duplicate(), "progress": 0.0, "integrity": 1.0,
		"cover": 0.65 if kind == "personal" else 0.5, "radius_km": 0.005 if kind == "personal" else 0.02, "created_at": _state.time, "last_work_ref": ""}
	if not _node_positions.has(node):
		_node_positions[node] = {}
	_node_positions[node][id] = true
	return true

func construct_position(producer: RefCounted, id: String, seconds: float, total_seconds: float, reference: String) -> bool:
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().operations or not producer.permits_position(id, reference) or not _positions.has(id) or seconds <= 0.0 or total_seconds <= 0.0:
		return false
	var position: Dictionary = _positions[id]
	# Each paid work ticket credits once; an interruption keeps completed earthwork.
	if position.last_work_ref == reference:
		return false
	position.last_work_ref = reference
	position.progress = minf(1.0, float(position.progress) + seconds / total_seconds)
	position.updated_at = _state.time
	var members: RefCounted = _state.gameplay_port.get_ref().participants
	members.admit_constructed_cover(self, position)
	_state.wake(str(_nodes[position.node_ref].cell))
	return true

func position_cover(id: String) -> float:
	var position: Dictionary = _positions.get(id, {})
	return float(position.get("cover", 0.0)) * float(position.get("progress", 0.0)) * float(position.get("integrity", 0.0))

func damage_positions_at(node: String, point: Array, radius: float, rounds: float, cause: String) -> void:
	for local_node: String in _node_positions:
		if _nodes[local_node].cell != _nodes[node].cell:
			continue
		for id: String in _node_positions[local_node]:
			var position: Dictionary = _positions[id]
			if _distance(point, position.xy) <= radius and position.get("last_damage_ref", "") != cause:
				position.integrity = maxf(0.0, float(position.integrity) - maxf(0.0, rounds) * 0.01)
				position.updated_at = _state.time
				position.last_damage_ref = cause
				_state.gameplay_port.get_ref().participants.admit_constructed_cover(self, position)

static func movement_factor(ground: Dictionary, mode: String) -> float:
	if mode == "MOTORIZED" and (float(ground.softness) > 0.65 or float(ground.slope) > 0.3):
		return 0.0
	return 1.0 / (1.0 + float(ground.resistance) + float(ground.softness) * (3.0 if mode == "MOTORIZED" else 1.0) + float(ground.slope) * (4.0 if mode == "MOTORIZED" else 2.0))

func detection(source: Dictionary, target: Dictionary) -> float:
	if _distance(xy(source), xy(target)) > float(source.weapon.range_km):
		return 0.0
	if not source.has("spatial") or not target.has("spatial"):
		return 0.0 if source.area_id != target.area_id else float(terrain(source).visibility) * (1.0 - float(terrain(source).concealment))
	var lane: Dictionary = _visibility_lane(source.spatial, target.spatial)
	if not lane.get("observe", false) or not lane.get("fire", false):
		return 0.0
	var target_ground: Dictionary = terrain(target)
	return float(target_ground.visibility) * (1.0 - float(target_ground.concealment))

func detection_at(source: Dictionary, anchor: Dictionary) -> float:
	if not source.has("spatial") or not _nodes.has(anchor.get("node", "")) or _distance(xy(source), anchor.xy) > float(source.weapon.range_km):
		return 0.0
	var lane: Dictionary = _visibility_lane(source.spatial, anchor)
	if not lane.get("observe", false) or not lane.get("fire", false):
		return 0.0
	var ground: Dictionary = anchor.get("ground", _nodes[anchor.node].ground)
	return float(ground.visibility) * (1.0 - float(ground.concealment))

func observation(source: Dictionary, target: Dictionary) -> float:
	if _distance(xy(source), xy(target)) > float(source.weapon.get("observation_range_km", source.weapon.range_km)):
		return 0.0
	if not source.has("spatial") or not target.has("spatial"):
		return 0.0
	if not _visibility_lane(source.spatial, target.spatial).get("observe", false):
		return 0.0
	var ground: Dictionary = terrain(target)
	return float(ground.visibility) * (1.0 - float(ground.concealment))

func observation_at(source: Dictionary, anchor: Dictionary) -> float:
	if not source.has("spatial") or not _nodes.has(anchor.get("node", "")) or _distance(xy(source), anchor.xy) > float(source.weapon.get("observation_range_km", source.weapon.range_km)):
		return 0.0
	if not _visibility_lane(source.spatial, anchor).get("observe", false):
		return 0.0
	var ground: Dictionary = anchor.get("ground", _nodes[anchor.node].ground)
	return float(ground.visibility) * (1.0 - float(ground.concealment))

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
	if str(unit.spatial.get("local_edge", "")) != "" or not unit.spatial.get("local_path", []).is_empty():
		_prepare_local_movement(unit, plan)
		return
	if local_place(unit.spatial) != "node:" + str(unit.spatial.node):
		plan.speed = 0.0
		plan.route_edge = {}
		plan.route_blocked = "local_return_to_road_access_required"
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
	if not unit.spatial.returning and not plan.route_retreat and not plan.get("manoeuvre_return", false) and not edge.open:
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
	if plan.get("local_motion", false):
		var length: float = float(_local_edges[plan.route_edge.edge].length_km)
		var progress: float = float(unit.spatial.get("local_progress", 0.0))
		return (progress if float(plan.speed) < 0.0 else length - progress) / absf(float(plan.speed)) * 60.0
	var edge: Dictionary = _edges[plan.route_edge.edge]
	var remaining: float = float(unit.spatial.progress) if float(plan.speed) < 0.0 else float(edge.length_km) - float(unit.spatial.progress)
	return remaining / absf(float(plan.speed)) * 60.0

func move(unit: Dictionary, plan: Dictionary, minutes: float, log: Array[Dictionary]) -> float:
	if plan.get("local_motion", false):
		return _move_local(unit, plan, minutes, log)
	if local_place(unit.spatial) != "node:" + str(unit.spatial.node):
		return 0.0
	var route: Dictionary = unit.spatial
	var versioned: bool = _state.missions[unit.mission_id].has("goal_v1") or _state.missions[unit.mission_id].get("summary_goal_policy", false)
	if versioned and _state.missions[unit.mission_id].status != "active" and not plan.get("manoeuvre_return", false):
		return 0.0
	if plan.get("route_retreat", false) and plan.route_edge.is_empty():
		# No previous leg exists: remain at this known node, never invent a route.
		route.path.clear()
		if not versioned:
			_state.missions[unit.mission_id].status = "withdrawn"
		unit.action = "withdrawn"
		log.append({"time": _state.time, "kind": "mission_withdrawn", "unit_id": unit.id, "mission_id": unit.mission_id})
		return 0.0
	if not str(plan.get("route_blocked", "")).is_empty():
		var blocked: String = str(plan.route_blocked)
		if route.blocked_edge != blocked:
			route.blocked_edge = blocked
			route.blocked_at = _state.time
			route.cause_ref = _edges[blocked].get("last_fact_id", "terrain_input")
			log.append({"id": "blocked_" + str(unit.id) + "_" + str(route.cause_ref), "time": _state.time,
				"kind": "part_route_blocked" if plan.has("action_part") else "route_blocked", "unit_id": unit.id, "part_ref": plan.get("action_part", ""), "edge_ref": blocked, "cause_ref": route.cause_ref,
				"scope": unit.area_id, "execution": "BLOCKED"})
			if not plan.has("action_part"):
				route_feedback.emit(str(unit.id), "BLOCKED", str(route.cause_ref))
	if float(plan.speed) == 0.0 or unit.action == "disabled":
		return 0.0
	if str(route.edge).is_empty():
		route.erase("local_ref")
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
		if destination != previous and not plan.has("action_part"):
			_state.area_units[previous].erase(unit.id)
			_state.area_units[destination][unit.id] = true
			unit.area_id = destination
			_lod.on_spatial_transfer(str(unit.id), previous, destination)
			_state.wake(destination)
			log.append({"time": _state.time, "kind": "area_transition", "unit_id": unit.id, "from": previous, "to": destination})
		log.append({"time": _state.time, "kind": "part_route_arrival" if plan.has("action_part") else "route_arrival", "unit_id": unit.id, "part_ref": plan.get("action_part", ""), "node_ref": route.node})
		if not plan.has("action_part"):
			route_feedback.emit(str(unit.id), "ARRIVED", "")
		if plan.get("route_retreat", false):
			route.path.clear()
			if not versioned:
				_state.missions[unit.mission_id].status = "withdrawn"
			unit.action = "withdrawn"
			log.append({"time": _state.time, "kind": "mission_withdrawn", "unit_id": unit.id, "mission_id": unit.mission_id})
		elif route.path.is_empty() and not versioned and not plan.has("manoeuvre_ref"):
			_state.missions[unit.mission_id].status = "complete"
			log.append({"time": _state.time, "kind": "mission_complete", "unit_id": unit.id, "mission_id": unit.mission_id})
	return travelled

func can_move(unit: Dictionary) -> bool:
	if not unit.has("spatial"):
		return true
	if str(unit.spatial.get("local_edge", "")) != "" or local_place(unit.spatial) != "node:" + str(unit.spatial.node):
		return false # Local movement is owned by the accepted part action.
	var next: Dictionary = _next(unit)
	return not next.is_empty() and (unit.spatial.returning or _edges[next.edge].open) and movement_factor(_edges[next.edge].ground, str(unit.spatial.mode)) > 0.0

func _prepare_local_movement(unit: Dictionary, plan: Dictionary) -> void:
	var route: Dictionary = unit.spatial
	plan.local_motion = true
	plan.speed = 0.0
	plan.route_blocked = ""
	plan.route_edge = {}
	var id: String = str(route.get("local_edge", ""))
	if id == "" and not route.get("local_path", []).is_empty():
		id = str(route.local_path[0])
	if not _local_edges.has(id):
		return
	var edge: Dictionary = _local_edges[id]
	var start: String = str(route.local_from) if str(route.get("local_edge", "")) != "" else local_place(route)
	plan.route_edge = {"edge": id, "from": start, "to": edge.to if start == edge.from else edge.from}
	if not plan.has("action_part") or plan.posture not in ["advance", "withdraw"] or plan.advance_inhibited:
		return
	# Returning on occupied geometry cannot create a new route through a closure.
	if not edge.open and not (route.get("local_returning", false) and str(route.get("local_edge", "")) != ""):
		plan.route_blocked = id
		return
	var factor: float = movement_factor(edge.ground, "FOOT")
	plan.speed = float(unit.mobility) * factor * float(unit.readiness)
	plan.speed *= minf(1.0, float(edge.ground.width) / maxf(1.0, float(plan.get("side_frontage", 1.0))))
	plan.speed *= (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
	if route.get("local_returning", false):
		plan.speed = -float(plan.speed)

func _move_local(unit: Dictionary, plan: Dictionary, minutes: float, log: Array[Dictionary]) -> float:
	var route: Dictionary = unit.spatial
	if not plan.has("action_part") or unit.action == "disabled" or float(plan.speed) == 0.0:
		return 0.0
	if str(route.get("local_edge", "")) == "":
		route.local_edge = plan.route_edge.edge
		route.local_from = plan.route_edge.from
		route.local_to = plan.route_edge.to
		route.local_progress = 0.0
		route.erase("entered_site_ref")
	var length: float = float(_local_edges[route.local_edge].length_km)
	var before: float = float(route.local_progress)
	route.local_progress = clampf(before + float(plan.speed) * minutes, 0.0, length)
	var a: Dictionary = local_endpoint(str(route.local_from))
	var b: Dictionary = local_endpoint(str(route.local_to))
	var fraction: float = float(route.local_progress) / length
	var travelled: float = absf(float(route.local_progress) - before)
	route.point_xy = [float(a.xy[0]) + (float(b.xy[0]) - float(a.xy[0])) * fraction, float(a.xy[1]) + (float(b.xy[1]) - float(a.xy[1])) * fraction]
	unit.position = float(route.point_xy[0])
	if absf(float(route.local_progress) - (0.0 if route.get("local_returning", false) else length)) <= 0.00000001:
		var destination: String = str(route.local_from if route.get("local_returning", false) else route.local_to)
		route.local_ref = destination
		route.node = local_endpoint(destination).node_ref
		route.local_edge = ""
		route.local_progress = 0.0
		route.local_returning = false
		route.local_path = []
		if destination.begins_with("node:"):
			route.erase("point_xy")
		log.append({"time": _state.time, "kind": "part_local_arrival", "unit_id": unit.id, "part_ref": plan.action_part, "local_ref": destination})
	return travelled

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

func admit_engineering(edge: String, actions: Array, work_nodes: Array) -> bool:
	if _state.time != 0.0 or not _edges.has(edge) or _edges[edge].kind not in ["road", "bridge"] or actions.is_empty() or actions.size() > 2 or work_nodes.is_empty() or work_nodes.size() > 2:
		return false
	for action: Variant in actions:
		if action not in ["clear", "repair"]:
			return false
	for node: Variant in work_nodes:
		if node not in [_edges[edge].from, _edges[edge].to]:
			return false
	_edges[edge].engineering = {"actions": actions.duplicate(), "work_nodes": work_nodes.duplicate()}
	return true

func schedule_obstruction(id: String, due: float, edge: String, obstruction: String) -> Dictionary:
	if obstruction not in ["debris", "limited_damage", "severe_damage", "unclassified"] or not _edges.has(edge):
		return _reject("existing_edge_and_explicit_obstruction_required")
	var result: Dictionary = schedule_fact(id, due, edge, false)
	if result.get("ok", false):
		_facts[id].obstruction = obstruction
	return result

func finish_engineering(producer: RefCounted, edge: String, revision: String, reference: String) -> void:
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().operations or not producer.permits_engineering(edge, reference):
		return
	var id: String = "engineering_" + reference
	if _facts.has(id):
		return
	_facts[id] = {"id": id, "due": _state.time, "edge_ref": edge, "open": true, "property": "open", "status": "PENDING", "engineering_ref": reference, "expected_revision": revision}
	assert(_state.schedule_event("spatial_" + id, _state.time, "spatial", {"fact_id": id}))

func admit_waterways(connections: Dictionary) -> bool:
	if _state.time != 0.0 or not _waterways.is_empty() or connections.size() > 16:
		return false
	for id: String in connections:
		var lane: Dictionary = connections[id]
		if id.is_empty() or not _nodes.has(lane.get("from", "")) or not _nodes.has(lane.get("to", "")) or lane.from == lane.to or not _nodes[lane.from].get("water", false) or not _nodes[lane.to].get("water", false) or not lane.get("water_only", false) or not lane.get("open") is bool or not _positive(lane.get("depth_km")) or not _positive(lane.get("length_km")) or float(lane.length_km) + 0.0000001 < _distance(_nodes[lane.from].xy, _nodes[lane.to].xy):
			return false
	_waterways = connections.duplicate(true)
	return true

func schedule_waterway(id: String, due: float, lane: String, open: bool) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if id.is_empty() or _facts.has(id) or not _waterways.has(lane) or not is_finite(due) or due < _state.time:
		return _reject("invalid_waterway_fact")
	_facts[id] = {"id": id, "due": due, "lane_ref": lane, "open": open, "property": "waterway", "status": "PENDING"}
	if not _state.schedule_event("spatial_" + id, due, "spatial", {"fact_id": id}):
		_facts.erase(id)
		return _reject("fact_schedule_failed")
	return {"ok": true, "time": due}

func schedule_site(id: String, due: float, node: String, property: String, value: Variant) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if id.is_empty() or _facts.has(id) or not _nodes.has(node) or not is_finite(due) or due < _state.time or property not in ["airfield_open", "port_open", "communication_open", "sea_visibility", "sea_state"]:
		return _reject("invalid_site_fact")
	if property in ["airfield_open", "port_open", "communication_open"] and not value is bool or property in ["sea_visibility", "sea_state"] and (not _nonnegative(value) or float(value) > 1.0):
		return _reject("invalid_site_value")
	_facts[id] = {"id": id, "due": due, "node_ref": node, "site_property": property, "value": value, "property": "site", "status": "PENDING"}
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

func schedule_local_fact(id: String, due: float, link: String, open: bool) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if id.is_empty() or _facts.has(id) or not _local_edges.has(link) or not is_finite(due) or due < _state.time:
		return _reject("existing_local_link_and_future_boundary_required")
	_facts[id] = {"id": id, "due": due, "local_edge_ref": link, "open": open, "property": "local_open", "status": "PENDING"}
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
	if fact.has("engineering_ref") and (_edges[fact.edge_ref].get("last_fact_id", "") != fact.expected_revision or not _state.gameplay_port.get_ref().operations.permits_engineering(str(fact.edge_ref), str(fact.engineering_ref))):
		fact.status = "SUPERSEDED"
		_state.gameplay_port.get_ref().operations.engineering_applied(str(fact.engineering_ref), false)
		return {"changed": [], "retired": [], "record": fact.duplicate(true)}
	work.spatial_events_processed += 1
	var affected: Array[String] = []
	if fact.property == "local_open":
		var link: Dictionary = _local_edges[fact.local_edge_ref]
		link.open = fact.open
		link.last_fact_id = fact.id
		affected.append(str(local_endpoint(str(link.from)).node_ref))
		if _state.gameplay_port != null:
			_state.gameplay_port.get_ref().tactics.on_local_link(str(fact.local_edge_ref))
	elif fact.property == "waterway":
		var lane: Dictionary = _waterways[fact.lane_ref]
		lane.open = fact.open
		lane.last_fact_id = fact.id
		affected.assign([lane.from, lane.to])
		if _state.gameplay_port != null:
			_state.gameplay_port.get_ref().sea.on_waterway(str(fact.lane_ref))
	elif fact.property == "site":
		_nodes[fact.node_ref][fact.site_property] = fact.value
		_nodes[fact.node_ref].last_fact_id = fact.id
		affected.append(str(fact.node_ref))
		if _state.gameplay_port != null:
			_state.gameplay_port.get_ref().sea.on_site(str(fact.node_ref))
	elif fact.property == "ground":
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
		edge.obstruction = "NONE" if fact.open else fact.get("obstruction", "unclassified")
		edge.last_fact_id = fact.id
		affected.assign([edge.from, edge.to])
	fact.status = "APPLIED"
	fact.processed_at = _state.time
	if _state.gameplay_port != null and fact.property == "open":
		_state.gameplay_port.get_ref().prerequisites.on_edge(str(fact.edge_ref))
		_state.gameplay_port.get_ref().on_route_fact(str(fact.edge_ref), affected)
	if fact.has("engineering_ref"):
		_state.gameplay_port.get_ref().operations.engineering_applied(str(fact.engineering_ref), true)
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

const RUNTIME_FIELDS: Array[String] = ["_nodes", "_edges", "_lanes", "_waterways", "_facts", "_cell_scope", "_scope_cells", "_scope_anchor", "_cell_nodes", "_cell_edges", "_loaded", "_facility_summaries", "_position_sites", "_positions", "_node_positions", "_local_sites", "_local_edges", "_local_lanes", "work"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)

func bind_runtime(state: State, lod: RefCounted) -> void:
	_state = state
	_lod = lod
	_bind_local_positions()
	state.spatial_port = weakref(self)

func valid_local_spatial(route: Dictionary) -> bool:
	if not _nodes.has(route.get("node", "")) or local_endpoint(local_place(route)).is_empty():
		return false
	var id: String = str(route.get("local_edge", ""))
	if id != "":
		if not _local_edges.has(id) or str(route.get("edge", "")) != "" or not _nonnegative(route.get("local_progress")) or not route.get("local_returning") is bool:
			return false
		var link: Dictionary = _local_edges[id]
		if route.get("local_from", "") not in [link.from, link.to] or route.get("local_to", "") not in [link.from, link.to] or route.local_from == route.local_to or float(route.local_progress) > float(link.length_km) or not _xy_valid(route.get("point_xy")):
			return false
		var a: Array = local_endpoint(str(route.local_from)).xy
		var b: Array = local_endpoint(str(route.local_to)).xy
		var f: float = float(route.local_progress) / float(link.length_km)
		if _distance(route.point_xy, [float(a[0]) + (float(b[0]) - float(a[0])) * f, float(a[1]) + (float(b[1]) - float(a[1])) * f]) > 0.000001:
			return false
	elif not local_place(route).begins_with("node:"):
		if not local_arrived(route, local_place(route)) or local_endpoint(local_place(route)).node_ref != route.node:
			return false
	if route.has("entered_site_ref") and (route.entered_site_ref != local_place(route) or not _local_sites.has(route.entered_site_ref) or id != ""):
		return false
	for edge: Variant in route.get("local_path", []):
		if not _local_edges.has(edge):
			return false
	return true

func valid_local_runtime() -> bool:
	if _local_sites.size() > 16 or _local_edges.size() > 16 or _local_lanes.size() > 128:
		return false
	for id: String in _local_sites:
		var site: Dictionary = _local_sites[id]
		if not _nodes.has(site.get("node_ref", "")) or not _xy_valid(site.get("xy")) or not _ground_valid(site.get("ground")) or not _positive(site.get("enter_seconds")) or not _positive(site.get("radius_km")):
			return false
	for edge: Dictionary in _local_edges.values():
		if local_endpoint(str(edge.get("from", ""))).is_empty() or local_endpoint(str(edge.get("to", ""))).is_empty() or not _positive(edge.get("length_km")) or not _ground_valid(edge.get("ground")) or not edge.get("open") is bool:
			return false
	for key: String in _local_lanes:
		var refs: PackedStringArray = key.split(">")
		if refs.size() != 2 or not _sight_known(refs[0], _local_sites, _local_edges) or not _sight_known(refs[1], _local_sites, _local_edges) or not _local_lanes[key].get("observe") is bool or not _local_lanes[key].get("fire") is bool:
			return false
	for fact: Dictionary in _facts.values():
		if fact.get("property", "") == "local_open" and not _local_edges.has(fact.get("local_edge_ref", "")):
			return false
	for unit: Dictionary in _state.units.values():
		if unit.has("spatial") and not valid_local_spatial(unit.spatial):
			return false
	return true
