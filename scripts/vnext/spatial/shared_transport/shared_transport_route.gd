class_name VNextSharedTransportRoute
extends RefCounted
## Deterministic physical route selected or supplied for one request.

const CAPACITY_EPSILON: float = 0.000001

var _configured: bool = false
var _origin_region_id: String = ""
var _destination_region_id: String = ""
var _edge_ids: Array[String] = []
var _travel_time: float = 0.0
var _base_transport_cost: float = 0.0


static func create(
	origin_region_id_value: String,
	destination_region_id_value: String,
	edge_ids_value: Array[String],
	travel_time_value: Variant,
	base_transport_cost_value: Variant
) -> VNextSharedTransportRoute:
	var route := VNextSharedTransportRoute.new()
	if not route.configure(
		origin_region_id_value,
		destination_region_id_value,
		edge_ids_value,
		travel_time_value,
		base_transport_cost_value
	):
		return null
	return route


func configure(
	origin_region_id_value: String,
	destination_region_id_value: String,
	edge_ids_value: Array[String],
	travel_time_value: Variant,
	base_transport_cost_value: Variant
) -> bool:
	if _configured:
		return false
	if (
		origin_region_id_value.is_empty()
		or destination_region_id_value.is_empty()
		or origin_region_id_value == destination_region_id_value
		or edge_ids_value.is_empty()
	):
		return false
	var travel_time: float = _parse_nonnegative_finite(travel_time_value)
	var base_cost: float = _parse_nonnegative_finite(base_transport_cost_value)
	if travel_time < 0.0 or base_cost < 0.0:
		return false
	var candidate_edges: Array[String] = []
	var seen_edges: Dictionary = {}
	for edge_id: String in edge_ids_value:
		if edge_id.is_empty() or seen_edges.has(edge_id):
			return false
		seen_edges[edge_id] = true
		candidate_edges.append(edge_id)

	_origin_region_id = origin_region_id_value
	_destination_region_id = destination_region_id_value
	_edge_ids = candidate_edges
	_travel_time = snappedf(travel_time, CAPACITY_EPSILON)
	_base_transport_cost = snappedf(base_cost, CAPACITY_EPSILON)
	_configured = true
	return true


func is_valid() -> bool:
	return (
		_configured
		and not _origin_region_id.is_empty()
		and not _destination_region_id.is_empty()
		and _origin_region_id != _destination_region_id
		and not _edge_ids.is_empty()
		and is_finite(_travel_time)
		and _travel_time >= 0.0
		and is_finite(_base_transport_cost)
		and _base_transport_cost >= 0.0
	)


func origin_region_id() -> String:
	return _origin_region_id


func destination_region_id() -> String:
	return _destination_region_id


func edge_ids() -> Array[String]:
	return _edge_ids.duplicate()


func travel_time() -> float:
	return _travel_time


func base_transport_cost() -> float:
	return _base_transport_cost


func physical_score() -> float:
	return snappedf(_travel_time + _base_transport_cost, CAPACITY_EPSILON)


func to_dictionary() -> Dictionary:
	return {
		"origin_region_id": _origin_region_id,
		"destination_region_id": _destination_region_id,
		"edge_ids": _edge_ids.duplicate(),
		"travel_time": _travel_time,
		"base_transport_cost": _base_transport_cost,
		"physical_score": physical_score(),
	}


static func _parse_nonnegative_finite(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized >= 0.0 else -1.0
