class_name VNextSpatialTransportAllocator
extends RefCounted
## Standalone Spatial-owned batch allocator for shared physical transport.
##
## Lifecycle is deliberately two-phase:
##
##   submit every request -> freeze_request_set() -> allocate() -> read result
##
## There is no per-request allocation method. A requester can only submit
## demand; only this allocator can produce the immutable batch result.

const CAPACITY_EPSILON: float = VNextSharedTransportEdge.CAPACITY_EPSILON
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991
const PHASE_UNINITIALIZED: int = 0
const PHASE_COLLECTING: int = 1
const PHASE_FROZEN: int = 2
const PHASE_ALLOCATED: int = 3

var _phase: int = PHASE_UNINITIALIZED
var _last_error: String = ""
var _edges_by_id: Dictionary = {}
var _adjacency: Dictionary = {}
var _requests_by_id: Dictionary = {}
var _frozen_request_ids: Array[String] = []
var _allocation_time: int = -1
var _result: VNextSharedTransportAllocationResult = null


static func create(edge_values: Array) -> VNextSpatialTransportAllocator:
	var allocator := VNextSpatialTransportAllocator.new()
	if not allocator.initialize(edge_values):
		return null
	return allocator


static func create_from_topology(
	topology: VNextSpatialSharedTransportTopology
) -> VNextSpatialTransportAllocator:
	if topology == null or not topology.is_valid():
		return null
	return create(topology.edges())


func initialize(edge_values: Array) -> bool:
	if _phase != PHASE_UNINITIALIZED or edge_values.is_empty():
		return false
	var candidate_edges: Dictionary = {}
	for raw_edge: Variant in edge_values:
		var edge: VNextSharedTransportEdge = null
		if raw_edge is VNextSharedTransportEdge:
			edge = raw_edge as VNextSharedTransportEdge
		elif typeof(raw_edge) == TYPE_DICTIONARY:
			edge = VNextSharedTransportEdge.from_dictionary(raw_edge as Dictionary)
		if edge == null or not edge.is_valid() or candidate_edges.has(edge.edge_id()):
			_last_error = "invalid_or_duplicate_edge"
			return false
		candidate_edges[edge.edge_id()] = edge
	var candidate_adjacency: Dictionary = {}
	for edge_id: String in _sorted_keys(candidate_edges):
		var edge: VNextSharedTransportEdge = candidate_edges[edge_id] as VNextSharedTransportEdge
		_append_adjacency(candidate_adjacency, edge.from_region_id(), edge_id)
		if not edge.directional():
			_append_adjacency(candidate_adjacency, edge.to_region_id(), edge_id)
	_edges_by_id = candidate_edges
	_adjacency = candidate_adjacency
	_requests_by_id = {}
	_frozen_request_ids = []
	_phase = PHASE_COLLECTING
	_last_error = ""
	return true


func initialize_from_topology(
	topology: VNextSpatialSharedTransportTopology
) -> bool:
	if topology == null or not topology.is_valid():
		_last_error = "invalid_topology"
		return false
	return initialize(topology.edges())


func is_valid() -> bool:
	if _phase == PHASE_UNINITIALIZED or _edges_by_id.is_empty():
		return false
	for edge_id: String in _sorted_keys(_edges_by_id):
		var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
		if edge == null or not edge.is_valid() or edge.edge_id() != edge_id:
			return false
	for request_id: String in _sorted_keys(_requests_by_id):
		var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
		if request == null or not request.is_valid() or request.request_id() != request_id:
			return false
	return true


func phase() -> int:
	return _phase


func last_error() -> String:
	return _last_error


func edge_ids() -> Array[String]:
	return _sorted_keys(_edges_by_id)


func edge(edge_id: String) -> VNextSharedTransportEdge:
	var value: Variant = _edges_by_id.get(edge_id)
	return value as VNextSharedTransportEdge if value is VNextSharedTransportEdge else null


func request_count() -> int:
	return _requests_by_id.size()


func request_ids() -> Array[String]:
	return _sorted_keys(_requests_by_id)


func frozen_request_ids() -> Array[String]:
	return _frozen_request_ids.duplicate()


func submit_request(request: VNextSharedTransportRequest) -> bool:
	if _phase != PHASE_COLLECTING or request == null or not request.is_valid():
		_last_error = "request_submission_closed_or_invalid"
		return false
	var request_id: String = request.request_id()
	if _requests_by_id.has(request_id):
		_last_error = "duplicate_request_id"
		return false
	_requests_by_id[request_id] = request
	_last_error = ""
	return true


func submit_request_record(record: Dictionary) -> bool:
	var request := VNextSharedTransportRequest.from_dictionary(record)
	if request == null:
		_last_error = "invalid_request_record"
		return false
	return submit_request(request)


func submit_requests(request_values: Array) -> bool:
	if _phase != PHASE_COLLECTING or request_values.is_empty():
		_last_error = "request_submission_closed_or_empty"
		return false
	var candidate: Dictionary = _requests_by_id.duplicate()
	for raw_request: Variant in request_values:
		var request: VNextSharedTransportRequest = null
		if raw_request is VNextSharedTransportRequest:
			request = raw_request as VNextSharedTransportRequest
		elif typeof(raw_request) == TYPE_DICTIONARY:
			request = VNextSharedTransportRequest.from_dictionary(raw_request as Dictionary)
		if request == null or not request.is_valid():
			_last_error = "invalid_request_batch"
			return false
		if candidate.has(request.request_id()):
			_last_error = "duplicate_request_id"
			return false
		candidate[request.request_id()] = request
	_requests_by_id = candidate
	_last_error = ""
	return true


func freeze_request_set() -> bool:
	if _phase != PHASE_COLLECTING or not is_valid():
		_last_error = "request_collection_not_open"
		return false
	for request_id: String in _sorted_keys(_requests_by_id):
		var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
		if not _constraints_are_well_formed(request.route_constraints()):
			_last_error = "invalid_route_constraints:%s" % request_id
			return false
		if request.has_accepted_route():
			var route: VNextSharedTransportRoute = _build_route(
				request, request.accepted_route(), false
			)
			if route == null:
				_last_error = "invalid_route:%s" % request_id
				return false
	_frozen_request_ids = _sorted_keys(_requests_by_id)
	_phase = PHASE_FROZEN
	_last_error = ""
	return true


func allocate(allocation_time_value: int) -> VNextSharedTransportAllocationResult:
	if _phase == PHASE_ALLOCATED:
		return _result if allocation_time_value == _allocation_time else null
	if _phase != PHASE_FROZEN or not _is_valid_time(allocation_time_value):
		_last_error = "allocation_requires_frozen_requests"
		return null

	var edge_capacities: Dictionary = {}
	var edge_remaining: Dictionary = {}
	for edge_id: String in edge_ids():
		var capacity: float = (_edges_by_id[edge_id] as VNextSharedTransportEdge).effective_capacity()
		capacity = _round_capacity(maxf(0.0, capacity))
		edge_capacities[edge_id] = capacity
		edge_remaining[edge_id] = capacity

	var routes: Dictionary = {}
	var allocations: Dictionary = {}
	var request_results: Dictionary = {}
	var priority_groups: Dictionary = {}
	for request_id: String in _frozen_request_ids:
		var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
		allocations[request_id] = 0.0
		var record: Dictionary = request.to_dictionary()
		record["quantity"] = request.quantity()
		record["allocated_quantity"] = 0.0
		record["route"] = []
		record["route_travel_time"] = 0.0
		record["route_base_transport_cost"] = 0.0
		record["status"] = "pending"
		record["reason"] = ""
		if not request.is_active_at(allocation_time_value):
			record["status"] = "outside_time_window"
			record["reason"] = "request_not_active_at_allocation_time"
			request_results[request_id] = record
			continue

		var route: VNextSharedTransportRoute = null
		if request.has_accepted_route():
			route = _build_route(request, request.accepted_route(), false)
		else:
			route = _find_deterministic_route(request)
		if route == null:
			record["status"] = "unroutable"
			record["reason"] = "no_available_route"
			request_results[request_id] = record
			continue
		routes[request_id] = route
		record["route"] = route.edge_ids()
		record["route_travel_time"] = route.travel_time()
		record["route_base_transport_cost"] = route.base_transport_cost()
		record["status"] = "ready"
		if not priority_groups.has(request.priority_class()):
			priority_groups[request.priority_class()] = []
		(priority_groups[request.priority_class()] as Array).append(request_id)
		request_results[request_id] = record

	var priorities: Array[int] = []
	for priority_value: Variant in priority_groups.keys():
		priorities.append(int(priority_value))
	priorities.sort()
	priorities.reverse()
	for priority_value: int in priorities:
		var group: Array[String] = []
		for raw_request_id: Variant in priority_groups[priority_value] as Array:
			group.append(str(raw_request_id))
		group.sort()
		_allocate_priority_group(group, routes, allocations, edge_remaining)

	for request_id: String in _frozen_request_ids:
		var record: Dictionary = request_results[request_id] as Dictionary
		var allocated: float = _round_capacity(float(allocations.get(request_id, 0.0)))
		allocations[request_id] = allocated
		record["allocated_quantity"] = allocated
		if str(record.get("status", "")) == "ready":
			var quantity: float = float(record.get("quantity", 0.0))
			if allocated <= CAPACITY_EPSILON:
				record["status"] = "unfulfilled"
				record["reason"] = "insufficient_available_capacity"
			elif allocated + CAPACITY_EPSILON < quantity:
				record["status"] = "partial"
				record["reason"] = "capacity_constrained"
			else:
				record["status"] = "allocated"
				record["reason"] = ""
		request_results[request_id] = record

	var edge_usage: Dictionary = {}
	for edge_id: String in edge_ids():
		edge_usage[edge_id] = 0.0
	for request_id: String in _sorted_keys(routes):
		var route: VNextSharedTransportRoute = routes[request_id] as VNextSharedTransportRoute
		var allocated: float = float(allocations.get(request_id, 0.0))
		for edge_id: String in route.edge_ids():
			edge_usage[edge_id] = _round_capacity(
				float(edge_usage.get(edge_id, 0.0)) + allocated
			)
	var result := VNextSharedTransportAllocationResult.build(
		allocation_time_value,
		request_results,
		edge_capacities,
		edge_usage
	)
	if result == null or not result.is_valid():
		_last_error = "allocation_invariant_failure"
		return null
	_result = result
	_allocation_time = allocation_time_value
	_phase = PHASE_ALLOCATED
	_last_error = ""
	return _result


func allocation_result() -> VNextSharedTransportAllocationResult:
	return _result


func _allocate_priority_group(
	request_ids_value: Array[String],
	routes: Dictionary,
	allocations: Dictionary,
	edge_remaining: Dictionary
) -> void:
	var active: Array[String] = request_ids_value.duplicate()
	active.sort()
	while not active.is_empty():
		var active_weight_by_edge: Dictionary = {}
		for request_id: String in active:
			var route: VNextSharedTransportRoute = routes.get(request_id)
			if route == null:
				continue
			var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
			for edge_id: String in route.edge_ids():
				active_weight_by_edge[edge_id] = float(active_weight_by_edge.get(edge_id, 0.0)) + request.weight()

		var deltas: Dictionary = {}
		for request_id: String in active:
			var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
			var route: VNextSharedTransportRoute = routes.get(request_id)
			if route == null:
				continue
			var remaining_demand: float = maxf(
				0.0, request.quantity() - float(allocations.get(request_id, 0.0))
			)
			if remaining_demand <= CAPACITY_EPSILON:
				continue
			var fair_increment: float = remaining_demand
			for edge_id: String in route.edge_ids():
				var total_weight: float = float(active_weight_by_edge.get(edge_id, 0.0))
				if total_weight <= CAPACITY_EPSILON or not is_finite(total_weight):
					fair_increment = 0.0
					break
				var edge_share: float = float(edge_remaining.get(edge_id, 0.0)) * request.weight() / total_weight
				fair_increment = minf(fair_increment, maxf(0.0, edge_share))
			if fair_increment > CAPACITY_EPSILON and is_finite(fair_increment):
				deltas[request_id] = fair_increment

		if deltas.is_empty():
			break
		var total_delta: float = 0.0
		for request_id: String in active:
			if not deltas.has(request_id):
				continue
			var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
			var route: VNextSharedTransportRoute = routes.get(request_id)
			var delta: float = minf(
				float(deltas[request_id]),
				maxf(0.0, request.quantity() - float(allocations.get(request_id, 0.0)))
			)
			for edge_id: String in route.edge_ids():
				delta = minf(delta, maxf(0.0, float(edge_remaining.get(edge_id, 0.0))))
			if delta <= CAPACITY_EPSILON:
				continue
			allocations[request_id] = _round_capacity(float(allocations.get(request_id, 0.0)) + delta)
			total_delta += delta
			for edge_id: String in route.edge_ids():
				edge_remaining[edge_id] = _round_capacity(
					maxf(0.0, float(edge_remaining.get(edge_id, 0.0)) - delta)
				)
		if total_delta <= CAPACITY_EPSILON:
			break
		var next_active: Array[String] = []
		for request_id: String in active:
			var request: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
			if request.quantity() - float(allocations.get(request_id, 0.0)) <= CAPACITY_EPSILON:
				continue
			var route: VNextSharedTransportRoute = routes.get(request_id)
			if route == null or _route_has_remaining_capacity(route, edge_remaining):
				next_active.append(request_id)
		active = next_active


func _find_deterministic_route(
	request: VNextSharedTransportRequest
) -> VNextSharedTransportRoute:
	var origin: String = request.origin_region_id()
	var destination: String = request.destination_region_id()
	var best_by_node: Dictionary = {
		origin: {
			"travel_time": 0.0,
			"base_cost": 0.0,
			"score": 0.0,
			"edge_ids": [],
			"nodes": [origin],
		}
	}
	var open_nodes: Array[String] = [origin]
	while not open_nodes.is_empty():
		var current_node: String = _select_best_open_node(open_nodes, best_by_node)
		open_nodes.erase(current_node)
		if current_node == destination:
			var state: Dictionary = best_by_node[current_node] as Dictionary
			var path: Array[String] = []
			for raw_edge_id: Variant in state.get("edge_ids", []) as Array:
				path.append(str(raw_edge_id))
			return _build_route(request, path, true)
		var current_state: Dictionary = best_by_node[current_node] as Dictionary
		var adjacent_ids: Array[String] = []
		for raw_edge_id: Variant in _adjacency.get(current_node, []) as Array:
			adjacent_ids.append(str(raw_edge_id))
		adjacent_ids.sort()
		for edge_id: String in adjacent_ids:
			var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
			if not edge.can_traverse_from(current_node) or edge.effective_capacity() <= CAPACITY_EPSILON:
				continue
			if not _edge_allowed_by_constraints(edge, request.route_constraints()):
				continue
			var next_node: String = edge.next_region_from(current_node)
			if next_node.is_empty() or (current_state.get("nodes", []) as Array).has(next_node):
				continue
			var travel_time: float = float(current_state.get("travel_time", 0.0)) + edge.travel_time()
			var base_cost: float = float(current_state.get("base_cost", 0.0)) + edge.base_transport_cost()
			var max_travel: float = _max_travel_time(request.route_constraints())
			if max_travel >= 0.0 and travel_time > max_travel + CAPACITY_EPSILON:
				continue
			var max_base_cost: float = _max_base_transport_cost(request.route_constraints())
			if max_base_cost >= 0.0 and base_cost > max_base_cost + CAPACITY_EPSILON:
				continue
			var edge_ids: Array[String] = []
			for raw_edge_id: Variant in current_state.get("edge_ids", []) as Array:
				edge_ids.append(str(raw_edge_id))
			edge_ids.append(edge_id)
			var nodes: Array[String] = []
			for raw_node: Variant in current_state.get("nodes", []) as Array:
				nodes.append(str(raw_node))
			nodes.append(next_node)
			var candidate: Dictionary = {
				"travel_time": _round_capacity(travel_time),
				"base_cost": _round_capacity(base_cost),
				"score": _round_capacity(travel_time + base_cost),
				"edge_ids": edge_ids,
				"nodes": nodes,
			}
			if (
				not best_by_node.has(next_node)
				or _route_state_less(candidate, best_by_node[next_node] as Dictionary)
			):
				best_by_node[next_node] = candidate
				if not open_nodes.has(next_node):
					open_nodes.append(next_node)
	return null


func _build_route(
	request: VNextSharedTransportRequest,
	edge_ids_value: Array[String],
	require_available_edges: bool
) -> VNextSharedTransportRoute:
	if edge_ids_value.is_empty():
		return null
	var current_node: String = request.origin_region_id()
	var total_travel_time: float = 0.0
	var total_base_cost: float = 0.0
	var seen_edges: Dictionary = {}
	for edge_id: String in edge_ids_value:
		if seen_edges.has(edge_id) or not _edges_by_id.has(edge_id):
			return null
		seen_edges[edge_id] = true
		var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
		if require_available_edges and (
			not edge.enabled() or edge.effective_capacity() <= CAPACITY_EPSILON
		):
			return null
		if not _edge_allowed_by_constraints(edge, request.route_constraints()):
			return null
		var next_node: String = _next_node_without_availability(edge, current_node)
		if next_node.is_empty():
			return null
		current_node = next_node
		total_travel_time += edge.travel_time()
		total_base_cost += edge.base_transport_cost()
	if current_node != request.destination_region_id():
		return null
	var max_travel: float = _max_travel_time(request.route_constraints())
	if max_travel >= 0.0 and total_travel_time > max_travel + CAPACITY_EPSILON:
		return null
	var max_base_cost: float = _max_base_transport_cost(request.route_constraints())
	if max_base_cost >= 0.0 and total_base_cost > max_base_cost + CAPACITY_EPSILON:
		return null
	return VNextSharedTransportRoute.create(
		request.origin_region_id(),
		request.destination_region_id(),
		edge_ids_value,
		total_travel_time,
		total_base_cost
	)


func _next_node_without_availability(
	edge: VNextSharedTransportEdge,
	current_node: String
) -> String:
	if edge.directional():
		return edge.to_region_id() if current_node == edge.from_region_id() else ""
	if current_node == edge.from_region_id():
		return edge.to_region_id()
	if current_node == edge.to_region_id():
		return edge.from_region_id()
	return ""


func _edge_allowed_by_constraints(
	edge: VNextSharedTransportEdge,
	constraints: Dictionary
) -> bool:
	var allowed_edges: Array[String] = _string_array_constraint(constraints, "allowed_edge_ids")
	if constraints.has("allowed_edge_ids") and allowed_edges.is_empty():
		return false
	if not allowed_edges.is_empty() and not allowed_edges.has(edge.edge_id()):
		return false
	var disallowed_edges: Array[String] = _string_array_constraint(constraints, "disallowed_edge_ids")
	if constraints.has("disallowed_edge_ids") and disallowed_edges.is_empty():
		return false
	if disallowed_edges.has(edge.edge_id()):
		return false
	var allowed_modes: Array[String] = _string_array_constraint(constraints, "allowed_modes")
	if constraints.has("allowed_modes") and allowed_modes.is_empty():
		return false
	if not allowed_modes.is_empty() and not allowed_modes.has(edge.mode()):
		return false
	var disallowed_modes: Array[String] = _string_array_constraint(constraints, "disallowed_modes")
	if constraints.has("disallowed_modes") and disallowed_modes.is_empty():
		return false
	return not disallowed_modes.has(edge.mode())


func _constraints_are_well_formed(constraints: Dictionary) -> bool:
	for field_name: String in [
		"allowed_edge_ids", "disallowed_edge_ids", "allowed_modes", "disallowed_modes",
		"accepted_route", "accepted_edge_ids",
	]:
		if constraints.has(field_name) and _string_array_constraint(constraints, field_name).is_empty():
			return false
	for field_name: String in ["max_travel_time", "max_base_transport_cost"]:
		if constraints.has(field_name):
			var value: Variant = constraints.get(field_name)
			if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) or float(value) < 0.0:
				return false
	return true


func _string_array_constraint(constraints: Dictionary, field_name: String) -> Array[String]:
	var value: Variant = constraints.get(field_name, [])
	if typeof(value) != TYPE_ARRAY:
		return []
	var output: Array[String] = []
	for raw_item: Variant in value as Array:
		if typeof(raw_item) != TYPE_STRING or str(raw_item).is_empty():
			return []
		output.append(raw_item as String)
	return output


func _max_travel_time(constraints: Dictionary) -> float:
	return _nonnegative_constraint(constraints, "max_travel_time")


func _max_base_transport_cost(constraints: Dictionary) -> float:
	return _nonnegative_constraint(constraints, "max_base_transport_cost")


func _nonnegative_constraint(constraints: Dictionary, field_name: String) -> float:
	if not constraints.has(field_name):
		return -1.0
	var value: Variant = constraints.get(field_name)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized >= 0.0 else -1.0


func _route_has_remaining_capacity(
	route: VNextSharedTransportRoute,
	edge_remaining: Dictionary
) -> bool:
	for edge_id: String in route.edge_ids():
		if float(edge_remaining.get(edge_id, 0.0)) <= CAPACITY_EPSILON:
			return false
	return true


func _select_best_open_node(open_nodes: Array[String], best_by_node: Dictionary) -> String:
	var selected: String = open_nodes[0]
	for node: String in open_nodes:
		if _route_state_less(best_by_node[node] as Dictionary, best_by_node[selected] as Dictionary):
			selected = node
	return selected


func _route_state_less(left: Dictionary, right: Dictionary) -> bool:
	var left_score: float = float(left.get("score", INF))
	var right_score: float = float(right.get("score", INF))
	if left_score < right_score - CAPACITY_EPSILON:
		return true
	if absf(left_score - right_score) > CAPACITY_EPSILON:
		return false
	var left_travel: float = float(left.get("travel_time", INF))
	var right_travel: float = float(right.get("travel_time", INF))
	if left_travel < right_travel - CAPACITY_EPSILON:
		return true
	if absf(left_travel - right_travel) > CAPACITY_EPSILON:
		return false
	var left_base: float = float(left.get("base_cost", INF))
	var right_base: float = float(right.get("base_cost", INF))
	if left_base < right_base - CAPACITY_EPSILON:
		return true
	if absf(left_base - right_base) > CAPACITY_EPSILON:
		return false
	return _path_key(left.get("edge_ids", []) as Array) < _path_key(right.get("edge_ids", []) as Array)


func _append_adjacency(adjacency: Dictionary, node: String, edge_id: String) -> void:
	if not adjacency.has(node):
		adjacency[node] = []
	(adjacency[node] as Array).append(edge_id)


static func _path_key(edge_ids_value: Array) -> String:
	var values: Array[String] = []
	for raw_edge_id: Variant in edge_ids_value:
		values.append(str(raw_edge_id))
	return "\u001f".join(values)


static func _is_valid_time(value: int) -> bool:
	return value >= 0 and value <= MAX_JSON_SAFE_INTEGER


static func _round_capacity(value: float) -> float:
	return snappedf(value, CAPACITY_EPSILON)


static func _sorted_keys(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key: Variant in value.keys():
		output.append(str(key))
	output.sort()
	return output
