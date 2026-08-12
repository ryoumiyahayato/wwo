class_name VNextMarketRouteNetwork
extends RefCounted
## NON-AUTHORITATIVE Economy fixture / derived commercial route network.
##
## These edges come from the Alpha economy calibration, not from authoritative
## world-map geometry. This class does not own physical topology, infrastructure
## operational state, or total/shared transport capacity. Its per-day fixture
## budget only bounds isolated Economy candidate shipments until a later
## integration adapter projects Spatial truth into economic reachability/cost.
##
## Future contract: Economy produces transport demand; VNextSpatialWorld owns
## physical feasibility and shared per-link/per-hour allocation; Economy records
## the accepted reservation/reference and shipment lifecycle.

var edges_by_id: Dictionary = {}
var adjacency: Dictionary = {}
var fixture_edge_budget_overrides: Dictionary = {}
var fixture_edge_remaining_budget: Dictionary = {}
var initialization_error: String = ""

var _default_fixture_budget: Dictionary = {}


func configure(edges: Array[Dictionary]) -> bool:
	edges_by_id.clear()
	adjacency.clear()
	fixture_edge_budget_overrides.clear()
	fixture_edge_remaining_budget.clear()
	_default_fixture_budget.clear()
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
		# Legacy Alpha field name. Within this isolated Economy fixture it is a
		# commercial throughput budget, not authoritative physical capacity.
		_default_fixture_budget[edge_id] = float(edge.get("capacity_units_per_day", 0.0))
		_append_direction(edge, false)
		if bool(edge.get("bidirectional", false)):
			_append_direction(edge, true)
	reset_daily_fixture_budget()
	return not edges_by_id.is_empty()


func reset_daily_fixture_budget() -> void:
	fixture_edge_remaining_budget.clear()
	for edge_id: String in _default_fixture_budget:
		fixture_edge_remaining_budget[edge_id] = maxf(
			0.0,
			float(
				fixture_edge_budget_overrides.get(edge_id, _default_fixture_budget[edge_id])
			)
		)


func set_fixture_edge_budget(edge_id: String, units_per_day: float) -> bool:
	if (
		not _default_fixture_budget.has(edge_id)
		or is_nan(units_per_day)
		or is_inf(units_per_day)
		or units_per_day < 0.0
	):
		return false
	fixture_edge_budget_overrides[edge_id] = units_per_day
	fixture_edge_remaining_budget[edge_id] = units_per_day
	return true


func restore_default_fixture_budget(edge_id: String) -> bool:
	if not _default_fixture_budget.has(edge_id):
		return false
	fixture_edge_budget_overrides.erase(edge_id)
	fixture_edge_remaining_budget[edge_id] = float(_default_fixture_budget[edge_id])
	return true


func default_fixture_edge_budget(edge_id: String) -> float:
	return float(_default_fixture_budget.get(edge_id, 0.0))


func remaining_fixture_budget(edge_id: String) -> float:
	return float(fixture_edge_remaining_budget.get(edge_id, 0.0))


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
			if remaining_fixture_budget(edge_id) <= 0.000001:
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


func route_fixture_budget(route: Dictionary) -> float:
	var budget: float = INF
	for raw_edge_id: Variant in route.get("edge_ids", []) as Array:
		budget = minf(budget, remaining_fixture_budget(str(raw_edge_id)))
	return 0.0 if is_inf(budget) else maxf(0.0, budget)


func consume_fixture_budget(route: Dictionary, units: float) -> bool:
	if units <= 0.0 or units > route_fixture_budget(route) + 0.000001:
		return false
	for raw_edge_id: Variant in route.get("edge_ids", []) as Array:
		var edge_id: String = str(raw_edge_id)
		fixture_edge_remaining_budget[edge_id] = maxf(
			0.0, remaining_fixture_budget(edge_id) - units
		)
	return true


func snapshot() -> Dictionary:
	return {
		"fixture_edge_budget_overrides": fixture_edge_budget_overrides.duplicate(true),
		"fixture_edge_remaining_budget": fixture_edge_remaining_budget.duplicate(true),
	}


func restore(snapshot_value: Dictionary) -> bool:
	# R1 candidate snapshots used physical-sounding route-capacity key names.
	# Accept them at the load boundary, but immediately normalize to the
	# post-PR62 non-authoritative fixture-budget representation.
	var overrides_value: Variant = snapshot_value.get(
		"fixture_edge_budget_overrides",
		snapshot_value.get("edge_capacity_overrides", {})
	)
	var remaining_value: Variant = snapshot_value.get(
		"fixture_edge_remaining_budget",
		snapshot_value.get("edge_remaining_capacity", {})
	)
	if not overrides_value is Dictionary or not remaining_value is Dictionary:
		return false
	var candidate_overrides: Dictionary = (overrides_value as Dictionary).duplicate(true)
	var candidate_remaining: Dictionary = (remaining_value as Dictionary).duplicate(true)
	for raw_edge_id: Variant in candidate_overrides:
		var edge_id: String = str(raw_edge_id)
		if (
			not _default_fixture_budget.has(edge_id)
			or float(candidate_overrides[raw_edge_id]) < 0.0
		):
			return false
	for edge_id: String in _default_fixture_budget:
		if not candidate_remaining.has(edge_id):
			return false
		var remaining: float = float(candidate_remaining[edge_id])
		var maximum: float = float(
			candidate_overrides.get(edge_id, _default_fixture_budget[edge_id])
		)
		if remaining < -0.000001 or remaining > maximum + 0.000001:
			return false
	fixture_edge_budget_overrides = candidate_overrides
	fixture_edge_remaining_budget = candidate_remaining
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