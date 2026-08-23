class_name FormalWorldMilitaryLogistics
extends RefCounted
## Formal economy/transport adapter for contextual military supply projection.

const RAIL_DENSITY_REFERENCE_KM_PER_MILLION: float = 1600.0
const WATERWAY_DENSITY_REFERENCE_KM_PER_MILLION: float = 500.0
const SUPPLY_UNITS_PER_CAPABILITY: float = 8.0
const HOME_SUPPLY_CAPACITY_MULTIPLIER: float = 100.0
const DISTANCE_REFERENCE_HOURS: float = 120.0

var _economy: FormalWorldEconomyService
var _model: VNextMilitaryCapabilityModel


func configure(
	economy_service: FormalWorldEconomyService,
	capability_model: VNextMilitaryCapabilityModel
) -> bool:
	if economy_service == null or capability_model == null:
		return false
	_economy = economy_service
	_model = capability_model
	return true


func build_projection_context(
	origin_id: String,
	target_id: String,
	origin_context_id: String,
	target_context_id: String,
	assessment: Dictionary
) -> Dictionary:
	if _economy == null or not VNextMilitaryCapabilityModel.is_valid_assessment(assessment):
		return {}
	var origin_state := _economy.country_summary(origin_id)
	var target_state := _economy.country_summary(target_id)
	if origin_state.is_empty() or target_state.is_empty():
		return {}
	var route := _route_between(origin_id, target_id)
	var source_structure := structural_factors(origin_state)
	var target_structure := structural_factors(target_state)
	var infrastructure_ratio := _model.combine_bottlenecks([
		{"value": float(source_structure.get("infrastructure", 0.0)), "weight": 0.58},
		{"value": float(target_structure.get("infrastructure", 0.0)), "weight": 0.42},
	], -1.6)
	var route_capacity := float(route.get("capacity_units_per_day", 0.0))
	var route_confidence := float(route.get("confidence_ratio", 1.0))
	if origin_id == target_id:
		route_capacity = _domestic_supply_capacity(origin_state, source_structure)
	var deliverable_supply := route_capacity * route_confidence
	deliverable_supply *= float(assessment.get("sustainment_ratio", 0.0))
	deliverable_supply *= infrastructure_ratio
	return {
		"origin_id": origin_context_id,
		"target_id": target_context_id,
		"deliverable_supply": maxf(0.0, deliverable_supply),
		"supply_units_per_capability": SUPPLY_UNITS_PER_CAPABILITY,
		"access_ratio": 1.0 if bool(route.get("reachable", false)) else 0.0,
		"infrastructure_ratio": infrastructure_ratio,
		# Formal terrain traversal costs are not yet authoritative.
		"terrain_supply_ratio": 1.0,
		"distance_hours": float(route.get("duration_hours", 0.0)),
		"distance_reference_hours": DISTANCE_REFERENCE_HOURS,
		"route": route,
	}


func structural_factors(economy_state: Dictionary) -> Dictionary:
	var population_millions := maxf(
		0.05, float(economy_state.get("population", 0)) / 1000000.0
	)
	var production := economy_state.get("production", {}) as Dictionary
	var infrastructure := economy_state.get("infrastructure", {}) as Dictionary
	var industry := clampf(
		float(production.get("industrial_capacity_index", 0)) / 85.0,
		0.0,
		1.0
	)
	var rail_density := float(infrastructure.get("rail_route_km", 0)) / population_millions
	var waterway_density := float(infrastructure.get("navigable_waterway_km", 0)) / population_millions
	var rail := _saturating(rail_density, RAIL_DENSITY_REFERENCE_KM_PER_MILLION)
	var waterway := _saturating(waterway_density, WATERWAY_DENSITY_REFERENCE_KM_PER_MILLION)
	var port := clampf(float(infrastructure.get("port_capacity_index", 0)) / 100.0, 0.0, 1.0)
	var shipping := clampf(float(infrastructure.get("merchant_shipping_index", 0)) / 100.0, 0.0, 1.0)
	var domestic_transport := maxf(rail, 0.65 * waterway)
	var international_transport := maxf(port, shipping)
	var infrastructure_factor := clampf(
		0.72 * domestic_transport + 0.28 * international_transport,
		0.0,
		1.0
	)
	var administration := _model.combine_bottlenecks([
		{"value": infrastructure_factor, "weight": 0.65},
		{"value": economy_fulfillment(economy_state), "weight": 0.35},
	], -1.5)
	return {
		"industry": industry,
		"rail": rail,
		"waterway": waterway,
		"port": port,
		"shipping": shipping,
		"infrastructure": infrastructure_factor,
		"administration": administration,
	}


func economy_fulfillment(economy_state: Dictionary) -> float:
	var totals := economy_state.get("daily_totals", {}) as Dictionary
	var demand := float(totals.get("demand_units", 0.0))
	if demand <= 0.0:
		return 1.0
	return clampf(float(totals.get("consumed_units", 0.0)) / demand, 0.0, 1.0)


func _domestic_supply_capacity(economy_state: Dictionary, structural: Dictionary) -> float:
	var population_millions := maxf(
		0.0, float(economy_state.get("population", 0)) / 1000000.0
	)
	var economic_mass := sqrt(population_millions * maxf(
		0.0, float(economy_state.get("income_per_capita", 0)) / 1000.0
	))
	return economic_mass * (0.25 + float(structural.get("infrastructure", 0.0)))
		* HOME_SUPPLY_CAPACITY_MULTIPLIER


func _route_between(origin_id: String, target_id: String) -> Dictionary:
	if origin_id == target_id:
		return {
			"reachable": true,
			"route_ids": [],
			"duration_hours": 0,
			"capacity_units_per_day": 0.0,
			"confidence_ratio": 1.0,
			"logistics_impedance": 0.0,
			"mode": "domestic",
		}
	var scores: Dictionary = {origin_id: 0.0}
	var durations: Dictionary = {origin_id: 0.0}
	var capacities: Dictionary = {origin_id: INF}
	var confidences: Dictionary = {origin_id: 1.0}
	var paths: Dictionary = {origin_id: []}
	var visited: Dictionary = {}
	var ids := _economy.economy_entity_ids()
	var network_routes := _economy.transport_routes()
	while visited.size() < ids.size():
		var current_id := ""
		var current_score := INF
		for candidate_id: String in ids:
			if visited.has(candidate_id) or not scores.has(candidate_id):
				continue
			var candidate_score := float(scores[candidate_id])
			if candidate_score < current_score or (
				is_equal_approx(candidate_score, current_score)
				and (current_id.is_empty() or candidate_id < current_id)
			):
				current_id = candidate_id
				current_score = candidate_score
		if current_id.is_empty() or current_id == target_id:
			break
		visited[current_id] = true
		for route: Dictionary in network_routes:
			var neighbor := ""
			if str(route.get("from", "")) == current_id:
				neighbor = str(route.get("to", ""))
			elif str(route.get("to", "")) == current_id:
				neighbor = str(route.get("from", ""))
			if neighbor.is_empty() or visited.has(neighbor):
				continue
			_update_route_candidate(
				current_id, neighbor, route, current_score,
				scores, durations, capacities, confidences, paths
			)
	if not scores.has(target_id):
		return {
			"reachable": false,
			"route_ids": [],
			"duration_hours": 0,
			"capacity_units_per_day": 0.0,
			"confidence_ratio": 0.0,
			"logistics_impedance": 0.0,
			"mode": "unreachable",
		}
	return {
		"reachable": true,
		"route_ids": (paths[target_id] as Array).duplicate(),
		"duration_hours": int(round(float(durations[target_id]))),
		"capacity_units_per_day": float(capacities[target_id]),
		"confidence_ratio": float(confidences[target_id]),
		"logistics_impedance": float(scores[target_id]),
		"mode": "network",
	}


func _update_route_candidate(
	current_id: String,
	neighbor: String,
	route: Dictionary,
	current_score: float,
	scores: Dictionary,
	durations: Dictionary,
	capacities: Dictionary,
	confidences: Dictionary,
	paths: Dictionary
) -> void:
	var edge_capacity := maxf(1.0, float(route.get("capacity_units_per_day", 0.0)))
	var edge_confidence := clampf(
		float(route.get("confidence_bp", 0)) / 10000.0, 0.05, 1.0
	)
	var next_score := current_score + float(route.get("duration_hours", 0.0)) / sqrt(
		edge_capacity * edge_confidence
	)
	var next_duration := float(durations[current_id]) + float(
		route.get("duration_hours", 0.0)
	)
	var next_capacity := minf(float(capacities[current_id]), edge_capacity)
	var next_confidence := minf(float(confidences[current_id]), edge_confidence)
	var next_path := (paths[current_id] as Array).duplicate()
	next_path.append(str(route.get("route_id", "")))
	var should_replace := not scores.has(neighbor) or next_score < float(scores[neighbor])
	if not should_replace and is_equal_approx(next_score, float(scores.get(neighbor, INF))):
		var current_delivery := float(capacities.get(neighbor, 0.0)) * float(
			confidences.get(neighbor, 0.0)
		)
		var next_delivery := next_capacity * next_confidence
		should_replace = next_delivery > current_delivery or (
			is_equal_approx(next_delivery, current_delivery)
			and _path_key(next_path) < _path_key(paths.get(neighbor, []) as Array)
		)
	if should_replace:
		scores[neighbor] = next_score
		durations[neighbor] = next_duration
		capacities[neighbor] = next_capacity
		confidences[neighbor] = next_confidence
		paths[neighbor] = next_path


func _saturating(value: float, half_saturation: float) -> float:
	if value <= 0.0:
		return 0.0
	return clampf(value / (value + maxf(0.000001, half_saturation)), 0.0, 1.0)


func _path_key(path: Array) -> String:
	var result := ""
	for raw_id: Variant in path:
		if not result.is_empty():
			result += "|"
		result += str(raw_id)
	return result
