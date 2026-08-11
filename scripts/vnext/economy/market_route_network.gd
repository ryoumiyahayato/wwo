class_name VNextMarketRouteNetwork
extends RefCounted
## Sparse route graph for commodity movement between regional markets.
## Every route consumes shared edge capacity and retains duration/cost terms.

var edges_by_id: Dictionary = {}
var adjacency: Dictionary = {}
var edge_capacity_overrides: Dictionary = {}
var edge_remaining_capacity: Dictionary = {}
var initialization_error: String = ""

var _default_capacity: Dictionary = {}


func configure(edges: Array[Dictionary]) -> bool:
	edges_by_id.clear()
	adjacency.clear()
	edge_capacity_overrides.clear()
	edge_remaining_capacity.clear()
	_default_capacity.clear()
	initialization_error = ""
	for edge_value: Dictionary in edges:
		var edge: Dictionary = edge_value.duplicate(true)
		var edge_id: String = str(edge.get("edge_id", ""))
		var from_market_id: String = str(edge.get("from_market_id", ""))
		var to_market_id: String = str(edge.get("to_market_id", ""))
		if (
			edge_id.is_empty()
			or edges_by_id.has(edge_id)
			or from_market_id.is_empty()
			or to_market_id.is_empty()
			or from_market_id == to_market_id
			or float(edge.get("capacity_units_per_day", 0.0)) <= 0.0
			or int(edge.get("duration_hours", 0)) <= 0
		):
			initialization_error = "运输边参数无效：%s" % edge_id
			return false
		edge["distance_days"] = maxf(
			0.001, float(edge.get("distance_days", 0.0))
			if float(edge.get("distance_days", 0.0)) > 0.0
			else float(edge.get("duration_hours", 1)) / 24.0
		)
		edges_by_id[edge_id] = edge
		_default_capacity[edge_id] = float(edge.get("capacity_units_per_day", 0.0))
		_append_direction(edge, false)
		if bool(edge.get("bidirectional", false)):
			_append_direction(edge, true)
	reset_daily_capacity()
	return not edges_by_id.is_empty()


func reset_daily_capacity() -> void:
	edge_remaining_capacity.clear()
	for edge_id: String in _default_capacity:
		edge_remaining_capacity[edge_id] = maxf(
			0.0,
			float(
				edge_capacity_overrides.get(edge_id, _default_capacity[edge_id])
			)
		)


func set_edge_capacity(edge_id: String, capacity_units_per_day: float) -> bool:
	if (
		not _default_capacity.has(edge_id)
		or is_nan(capacity_units_per_day)
		or is_inf(capacity_units_per_day)
		or capacity_units_per_day < 0.0
	):
		return false
	edge_capacity_overrides[edge_id] = capacity_units_per_day
	edge_remaining_capacity[edge_id] = capacity_units_per_day
	return true


func restore_default_capacity(edge_id: String) -> bool:
	if not _default_capacity.has(edge_id):
		return false
	edge_capacity_overrides.erase(edge_id)
	edge_remaining_capacity[edge_id] = float(_default_capacity[edge_id])
	return true


func default_edge_capacity(edge_id: String) -> float:
	return float(_default_capacity.get(edge_id, 0.0))


func remaining_capacity(edge_id: String) -> float:
	return float(edge_remaining_capacity.get(edge_id, 0.0))


func find_route(origin_market_id: String, destination_market_id: String) -> Dictionary:
	if origin_market_id.is_empty() or destination_market_id.is_empty():
		return {}
	if origin_market_id == destination_market_id:
		return {
			"origin_market_id": origin_market_id,
			"destination_market_id": destination_market_id,
			"edge_ids": [],
			"duration_hours": 0,
			"distance_days": 0.0,
			"cost_centimes_per_unit": 0.0,
			"risk_bp": 0,
			"cross_border": false,
		}

	var unvisited: Array[String] = []
	var distance: Dictionary = {}
	var duration: Dictionary = {}
	var paths: Dictionary = {}
	for raw_from: Variant in adjacency:
		var from_id: String = str(raw_from)
		unvisited.append(from_id)
		distance[from_id] = INF
		duration[from_id] = 0
		paths[from_id] = []
	if not unvisited.has(origin_market_id):
		return {}
	if not unvisited.has(destination_market_id):
		unvisited.append(destination_market_id)
		distance[destination_market_id] = INF
		duration[destination_market_id] = 0
		paths[destination_market_id] = []
	distance[origin_market_id] = 0.0

	while not unvisited.is_empty():
		var current: String = ""
		var current_distance: float = INF
		for candidate: String in unvisited:
			var candidate_distance: float = float(distance.get(candidate, INF))
			if (
				candidate_distance < current_distance
				or (
					is_equal_approx(candidate_distance, current_distance)
					and (current.is_empty() or candidate < current)
				)
			):
				current = candidate
				current_distance = candidate_distance
		if current.is_empty() or is_inf(current_distance):
			break
		unvisited.erase(current)
		if current == destination_market_id:
			break
		var neighbors: Array = adjacency.get(current, []) as Array
		neighbors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("edge_id", "")) < str(b.get("edge_id", ""))
		)
		for edge_value: Variant in neighbors:
			var edge: Dictionary = edge_value as Dictionary
			var edge_id: String = str(edge.get("edge_id", ""))
			if remaining_capacity(edge_id) <= 0.000001:
				continue
			var neighbor: String = str(edge.get("to_market_id", ""))
			if neighbor not in unvisited:
				continue
			var edge_cost: float = _edge_score(edge)
			var alternative: float = current_distance + edge_cost
			var previous_distance: float = float(distance.get(neighbor, INF))
			var should_replace: bool = alternative < previous_distance
			if (
				is_equal_approx(alternative, previous_distance)
				and _path_key(paths.get(neighbor, []) as Array)
				> _path_key(paths.get(current, []) as Array) + edge_id
			):
				should_replace = true
			if should_replace:
				distance[neighbor] = alternative
				duration[neighbor] = int(duration.get(current, 0)) + int(
					edge.get("duration_hours", 0)
				)
				var path: Array = (paths.get(current, []) as Array).duplicate()
				path.append(edge_id)
				paths[neighbor] = path

	if is_inf(float(distance.get(destination_market_id, INF))):
		return {}
	var route: Dictionary = _route_terms(paths[destination_market_id] as Array)
	route["origin_market_id"] = origin_market_id
	route["destination_market_id"] = destination_market_id
	return route


func route_capacity(route: Dictionary) -> float:
	var capacity: float = INF
	for raw_edge_id: Variant in route.get("edge_ids", []) as Array:
		capacity = minf(capacity, remaining_capacity(str(raw_edge_id)))
	return 0.0 if is_inf(capacity) else maxf(0.0, capacity)


func consume_route_capacity(route: Dictionary, units: float) -> bool:
	if units <= 0.0 or units > route_capacity(route) + 0.000001:
		return false
	for raw_edge_id: Variant in route.get("edge_ids", []) as Array:
		var edge_id: String = str(raw_edge_id)
		edge_remaining_capacity[edge_id] = maxf(
			0.0, remaining_capacity(edge_id) - units
		)
	return true


func snapshot() -> Dictionary:
	return {
		"edge_capacity_overrides": edge_capacity_overrides.duplicate(true),
		"edge_remaining_capacity": edge_remaining_capacity.duplicate(true),
	}


func restore(snapshot_value: Dictionary) -> bool:
	if (
		not snapshot_value.get("edge_capacity_overrides", {}) is Dictionary
		or not snapshot_value.get("edge_remaining_capacity", {}) is Dictionary
	):
		return false
	var candidate_overrides: Dictionary = (
		snapshot_value.get("edge_capacity_overrides", {}) as Dictionary
	).duplicate(true)
	var candidate_remaining: Dictionary = (
		snapshot_value.get("edge_remaining_capacity", {}) as Dictionary
	).duplicate(true)
	for raw_edge_id: Variant in candidate_overrides:
		var edge_id: String = str(raw_edge_id)
		if (
			not _default_capacity.has(edge_id)
			or float(candidate_overrides[raw_edge_id]) < 0.0
		):
			return false
	for edge_id: String in _default_capacity:
		if not candidate_remaining.has(edge_id):
			return false
		var remaining: float = float(candidate_remaining[edge_id])
		var maximum: float = float(
			candidate_overrides.get(edge_id, _default_capacity[edge_id])
		)
		if remaining < -0.000001 or remaining > maximum + 0.000001:
			return false
	edge_capacity_overrides = candidate_overrides
	edge_remaining_capacity = candidate_remaining
	return true


func _append_direction(edge: Dictionary, reverse: bool) -> void:
	var direction: Dictionary = edge.duplicate(true)
	if reverse:
		var from_id: String = str(direction.get("from_market_id", ""))
		direction["from_market_id"] = str(direction.get("to_market_id", ""))
		direction["to_market_id"] = from_id
	var from_market_id: String = str(direction.get("from_market_id", ""))
	var neighbors: Array = adjacency.get(from_market_id, []) as Array
	neighbors.append(direction)
	adjacency[from_market_id] = neighbors


func _edge_score(edge: Dictionary) -> float:
	return (
		float(edge.get("cost_centimes_per_unit", 0.0))
		+ float(edge.get("duration_hours", 0)) * 0.25
		+ float(edge.get("distance_days", 0.0)) * 0.5
		+ float(edge.get("risk_bp", 0)) / 1000.0
	)


func _route_terms(edge_ids: Array) -> Dictionary:
	var cost: float = 0.0
	var duration: int = 0
	var distance_days: float = 0.0
	var risk_bp: int = 0
	var cross_border: bool = false
	for raw_edge_id: Variant in edge_ids:
		var edge_id: String = str(raw_edge_id)
		var edge: Dictionary = edges_by_id.get(edge_id, {}) as Dictionary
		cost += float(edge.get("cost_centimes_per_unit", 0.0))
		duration += int(edge.get("duration_hours", 0))
		distance_days += float(edge.get("distance_days", 0.0))
		risk_bp = maxi(risk_bp, int(edge.get("risk_bp", 0)))
		cross_border = cross_border or bool(edge.get("cross_border", false))
	return {
		"edge_ids": edge_ids.duplicate(),
		"duration_hours": duration,
		"distance_days": distance_days,
		"cost_centimes_per_unit": cost,
		"risk_bp": risk_bp,
		"cross_border": cross_border,
	}


func _path_key(path: Array) -> String:
	var result: String = ""
	for value: Variant in path:
		result += str(value)
	return result
