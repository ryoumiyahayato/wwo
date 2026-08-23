class_name VNextSpatialTransportAllocator
extends RefCounted
## One-shot Spatial-owned allocator for a frozen physical transport cycle.
##
## Lifecycle:
## collect -> freeze_request_set -> freeze_routes -> allocate -> observe.
## Route search never reads residual allocation capacity. Topology, disruption,
## requests, selected routes and the published result cross explicit detached
## snapshot boundaries before the next phase can begin.

const CAPACITY_EPSILON: float = VNextSharedTransportEdge.CAPACITY_EPSILON
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991
const PHASE_UNINITIALIZED: int = 0
const PHASE_COLLECTING: int = 1
const PHASE_REQUESTS_FROZEN: int = 2
const PHASE_ROUTES_FROZEN: int = 3
const PHASE_ALLOCATED: int = 4

var _phase: int = PHASE_UNINITIALIZED
var _last_error: String = ""
var _edges_by_id: Dictionary = {}
var _adjacency: Dictionary = {}
var _node_ids: Dictionary = {}
var _topology_snapshot_id: String = ""
var _requests_by_id: Dictionary = {}
var _frozen_requests_by_id: Dictionary = {}
var _frozen_request_ids: Array[String] = []
var _frozen_routes_by_id: Dictionary = {}
var _frozen_request_records: Dictionary = {}
var _edge_capacities: Dictionary = {}
var _allocation_time: int = -1
var _route_candidate_count: int = 0
var _routing_duration_usec: int = 0
var _allocation_duration_usec: int = 0
var _canonical_result: VNextSharedTransportAllocationResult = null


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
	return create(topology.edge_records())


func initialize(edge_values: Array) -> bool:
	if _phase != PHASE_UNINITIALIZED or edge_values.is_empty():
		return false
	var candidate_edges: Dictionary = {}
	for raw_edge: Variant in edge_values:
		var edge: VNextSharedTransportEdge = null
		if raw_edge is VNextSharedTransportEdge:
			edge = VNextSharedTransportEdge.from_dictionary(
				(raw_edge as VNextSharedTransportEdge).to_dictionary()
			)
		elif typeof(raw_edge) == TYPE_DICTIONARY:
			edge = VNextSharedTransportEdge.from_dictionary(
				(raw_edge as Dictionary).duplicate(true)
			)
		if edge == null or not edge.is_valid() or candidate_edges.has(edge.edge_id()):
			_last_error = "invalid_or_duplicate_edge"
			return false
		candidate_edges[edge.edge_id()] = edge
	var candidate_adjacency: Dictionary = {}
	var candidate_nodes: Dictionary = {}
	for edge_id: String in _sorted_keys(candidate_edges):
		var edge: VNextSharedTransportEdge = candidate_edges[edge_id] as VNextSharedTransportEdge
		candidate_nodes[edge.from_region_id()] = true
		candidate_nodes[edge.to_region_id()] = true
		_append_adjacency(candidate_adjacency, edge.from_region_id(), edge_id)
		if not edge.directional():
			_append_adjacency(candidate_adjacency, edge.to_region_id(), edge_id)
	_edges_by_id = candidate_edges
	_adjacency = candidate_adjacency
	_node_ids = candidate_nodes
	_topology_snapshot_id = _current_topology_snapshot_id()
	_phase = PHASE_COLLECTING
	_last_error = ""
	return true


func initialize_from_topology(
	topology: VNextSpatialSharedTransportTopology
) -> bool:
	if topology == null or not topology.is_valid():
		_last_error = "invalid_topology"
		return false
	return initialize(topology.edge_records())


func is_valid() -> bool:
	if (
		_phase == PHASE_UNINITIALIZED
		or _edges_by_id.is_empty()
		or _topology_snapshot_id.is_empty()
		or _current_topology_snapshot_id() != _topology_snapshot_id
	):
		return false
	for edge_id: String in _sorted_keys(_edges_by_id):
		var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
		if edge == null or not edge.is_valid() or edge.edge_id() != edge_id:
			return false
	var requests: Dictionary = (
		_requests_by_id if _phase == PHASE_COLLECTING else _frozen_requests_by_id
	)
	for request_id: String in _sorted_keys(requests):
		var request: VNextSharedTransportRequest = requests[request_id] as VNextSharedTransportRequest
		if request == null or not request.is_valid() or request.request_id() != request_id:
			return false
	return true


func phase() -> int:
	return _phase


func last_error() -> String:
	return _last_error


func topology_snapshot_id() -> String:
	return _topology_snapshot_id


func routing_duration_usec() -> int:
	return _routing_duration_usec


func allocation_duration_usec() -> int:
	return _allocation_duration_usec


func route_candidate_count() -> int:
	return _route_candidate_count


func edge_ids() -> Array[String]:
	return _sorted_keys(_edges_by_id)


func edge(edge_id: String) -> VNextSharedTransportEdge:
	var value: Variant = _edges_by_id.get(edge_id)
	if not value is VNextSharedTransportEdge:
		return null
	return VNextSharedTransportEdge.from_dictionary(
		(value as VNextSharedTransportEdge).to_dictionary()
	)


func request_count() -> int:
	return (
		_requests_by_id.size()
		if _phase == PHASE_COLLECTING
		else _frozen_requests_by_id.size()
	)


func request_ids() -> Array[String]:
	return _sorted_keys(
		_requests_by_id if _phase == PHASE_COLLECTING else _frozen_requests_by_id
	)


func frozen_request_ids() -> Array[String]:
	return _frozen_request_ids.duplicate()


func frozen_route(request_id: String) -> Dictionary:
	var route_value: Variant = _frozen_routes_by_id.get(request_id)
	return (
		(route_value as VNextSharedTransportRoute).to_dictionary()
		if route_value is VNextSharedTransportRoute
		else {}
	)


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
	var request := VNextSharedTransportRequest.from_dictionary(record.duplicate(true))
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
			request = VNextSharedTransportRequest.from_dictionary(
				(raw_request as Dictionary).duplicate(true)
			)
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
	var detached_requests: Dictionary = {}
	for request_id: String in _sorted_keys(_requests_by_id):
		var source: VNextSharedTransportRequest = _requests_by_id[request_id] as VNextSharedTransportRequest
		var detached := VNextSharedTransportRequest.from_dictionary(source.to_dictionary())
		if detached == null or not detached.is_valid():
			_last_error = "invalid_request_at_freeze:%s" % request_id
			return false
		if not _constraints_are_well_formed(detached.route_constraints()):
			_last_error = "invalid_route_constraints:%s" % request_id
			return false
		detached_requests[request_id] = detached
	_frozen_requests_by_id = detached_requests
	_frozen_request_ids = _sorted_keys(detached_requests)
	_requests_by_id = {}
	_phase = PHASE_REQUESTS_FROZEN
	_last_error = ""
	return true


func freeze_routes(allocation_time_value: int) -> bool:
	if _phase != PHASE_REQUESTS_FROZEN or not _is_valid_time(allocation_time_value):
		_last_error = "route_freeze_requires_frozen_requests_and_valid_time"
		return false
	if not is_valid():
		_last_error = "topology_snapshot_corrupted"
		return false
	var started_usec: int = Time.get_ticks_usec()
	var candidate_capacities: Dictionary = {}
	for edge_id: String in edge_ids():
		var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
		candidate_capacities[edge_id] = _round_capacity(maxf(0.0, edge.effective_capacity()))
	var candidate_routes: Dictionary = {}
	var candidate_records: Dictionary = {}
	var automatic_route_cache: Dictionary = {}
	var candidate_count: int = 0
	for request_id: String in _frozen_request_ids:
		var request: VNextSharedTransportRequest = (
			_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
		)
		var record: Dictionary = _base_request_record(request)
		if not request.is_active_at(allocation_time_value):
			record["status"] = "outside_time_window"
			record["reason"] = "outside_time_window"
			candidate_records[request_id] = record
			continue
		if (
			not _node_ids.has(request.origin_region_id())
			or not _node_ids.has(request.destination_region_id())
		):
			record["status"] = "unroutable"
			record["reason"] = "invalid_endpoint"
			candidate_records[request_id] = record
			continue
		var route: VNextSharedTransportRoute = null
		if request.has_accepted_route():
			route = _build_route(request, request.accepted_route(), false)
			if route == null:
				_last_error = "invalid_route:%s" % request_id
				return false
		else:
			var route_key: String = _automatic_route_key(request)
			if automatic_route_cache.has(route_key):
				var cached_route: Variant = automatic_route_cache.get(route_key)
				route = (
					cached_route as VNextSharedTransportRoute
					if cached_route is VNextSharedTransportRoute
					else null
				)
			else:
				route = _find_deterministic_route(request)
				automatic_route_cache[route_key] = route
		if route == null:
			record["status"] = "unroutable"
			record["reason"] = "no_available_route"
			candidate_records[request_id] = record
			continue
		candidate_count += 1
		candidate_routes[request_id] = route
		record["route"] = route.edge_ids()
		record["route_travel_time"] = route.travel_time()
		record["route_base_transport_cost"] = route.base_transport_cost()
		record["route_candidate_count"] = 1
		record["status"] = "ready"
		candidate_records[request_id] = record
	_frozen_routes_by_id = candidate_routes
	_frozen_request_records = candidate_records
	_edge_capacities = candidate_capacities
	_allocation_time = allocation_time_value
	_route_candidate_count = candidate_count
	_routing_duration_usec = Time.get_ticks_usec() - started_usec
	_phase = PHASE_ROUTES_FROZEN
	_last_error = ""
	return true


func allocate() -> VNextSharedTransportAllocationResult:
	if _phase == PHASE_ALLOCATED:
		return _canonical_result.detached_copy() if _canonical_result != null else null
	if _phase != PHASE_ROUTES_FROZEN:
		_last_error = "allocation_requires_frozen_routes"
		return null
	if not is_valid():
		_last_error = "frozen_cycle_corrupted"
		return null
	var started_usec: int = Time.get_ticks_usec()
	var edge_remaining: Dictionary = _edge_capacities.duplicate(true)
	var allocations: Dictionary = {}
	var request_results: Dictionary = _frozen_request_records.duplicate(true)
	var priority_groups: Dictionary = {}
	for request_id: String in _frozen_request_ids:
		allocations[request_id] = 0.0
		if not _frozen_routes_by_id.has(request_id):
			continue
		var request: VNextSharedTransportRequest = (
			_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
		)
		if not priority_groups.has(request.priority_class()):
			priority_groups[request.priority_class()] = []
		(priority_groups[request.priority_class()] as Array).append(request_id)

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
		_allocate_priority_group(group, allocations, edge_remaining)

	var edge_usage: Dictionary = {}
	var usage_by_priority_by_edge: Dictionary = {}
	for edge_id: String in edge_ids():
		edge_usage[edge_id] = 0.0
		usage_by_priority_by_edge[edge_id] = {}
	for request_id: String in _sorted_keys(_frozen_routes_by_id):
		var route: VNextSharedTransportRoute = (
			_frozen_routes_by_id[request_id] as VNextSharedTransportRoute
		)
		var allocated: float = _round_capacity(float(allocations.get(request_id, 0.0)))
		allocations[request_id] = allocated
		var priority_key: String = str(
			(_frozen_requests_by_id[request_id] as VNextSharedTransportRequest).priority_class()
		)
		for edge_id: String in route.edge_ids():
			edge_usage[edge_id] = _round_capacity(
				float(edge_usage.get(edge_id, 0.0)) + allocated
			)
			var priority_usage: Dictionary = usage_by_priority_by_edge[edge_id] as Dictionary
			priority_usage[priority_key] = _round_capacity(
				float(priority_usage.get(priority_key, 0.0)) + allocated
			)

	var edge_diagnostics: Dictionary = _build_edge_diagnostics(
		edge_usage, usage_by_priority_by_edge
	)
	for request_id: String in _frozen_request_ids:
		var request: VNextSharedTransportRequest = (
			_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
		)
		var record: Dictionary = request_results[request_id] as Dictionary
		var allocated: float = _round_capacity(float(allocations.get(request_id, 0.0)))
		var unallocated: float = _round_capacity(maxf(0.0, request.quantity() - allocated))
		record["allocated_quantity"] = allocated
		record["unallocated_quantity"] = unallocated
		record["allocation_fraction"] = _round_capacity(allocated / request.quantity())
		var route_diagnostics: Array[Dictionary] = []
		var binding_edge_ids: Array[String] = []
		var blocked_by_higher_priority: bool = false
		for raw_edge_id: Variant in record.get("route", []) as Array:
			var edge_id: String = str(raw_edge_id)
			var edge_diagnostic: Dictionary = edge_diagnostics[edge_id] as Dictionary
			var usage_by_priority: Dictionary = (
				edge_diagnostic.get("usage_by_priority", {}) as Dictionary
			)
			var used_by_higher: float = _usage_above_priority(
				usage_by_priority, request.priority_class()
			)
			var used_at_priority: float = float(
				usage_by_priority.get(str(request.priority_class()), 0.0)
			)
			var binding: bool = (
				unallocated > CAPACITY_EPSILON
				and float(edge_diagnostic.get("remaining_capacity", 0.0)) <= CAPACITY_EPSILON
			)
			if binding:
				binding_edge_ids.append(edge_id)
				blocked_by_higher_priority = (
					blocked_by_higher_priority or used_by_higher > CAPACITY_EPSILON
				)
			route_diagnostics.append({
				"edge_id": edge_id,
				"binding": binding,
				"base_capacity": float(edge_diagnostic.get("base_capacity", 0.0)),
				"effective_capacity": float(edge_diagnostic.get("effective_capacity", 0.0)),
				"disruption_multiplier": float(edge_diagnostic.get("disruption_multiplier", 0.0)),
				"disruption_capacity_loss": float(edge_diagnostic.get("disruption_capacity_loss", 0.0)),
				"capacity_used_by_higher_priorities": used_by_higher,
				"capacity_used_at_priority": used_at_priority,
				"total_capacity_used": float(edge_diagnostic.get("allocated_capacity", 0.0)),
			})
		record["route_diagnostics"] = route_diagnostics
		record["binding_edge_ids"] = binding_edge_ids
		record["blocked_by_higher_priority"] = blocked_by_higher_priority
		if str(record.get("status", "")) == "ready":
			if unallocated <= CAPACITY_EPSILON:
				record["status"] = "allocated"
				record["reason"] = ""
			elif allocated <= CAPACITY_EPSILON:
				record["status"] = "unfulfilled"
				record["reason"] = (
					"higher_priority_capacity"
					if blocked_by_higher_priority
					else "insufficient_effective_capacity"
				)
			else:
				record["status"] = "partial"
				record["reason"] = (
					"higher_priority_and_shared_capacity"
					if blocked_by_higher_priority
					else "shared_capacity"
				)
		request_results[request_id] = record

	var result := VNextSharedTransportAllocationResult.build(
		_allocation_time,
		_topology_snapshot_id,
		request_results,
		edge_diagnostics,
		_route_candidate_count
	)
	if result == null or not result.is_valid():
		_last_error = "allocation_invariant_failure"
		return null
	_canonical_result = result
	_allocation_duration_usec = Time.get_ticks_usec() - started_usec
	_phase = PHASE_ALLOCATED
	_last_error = ""
	return _canonical_result.detached_copy()


func allocation_result() -> VNextSharedTransportAllocationResult:
	return _canonical_result.detached_copy() if _canonical_result != null else null


func _base_request_record(request: VNextSharedTransportRequest) -> Dictionary:
	var record: Dictionary = request.to_dictionary()
	record["quantity"] = request.quantity()
	record["allocated_quantity"] = 0.0
	record["unallocated_quantity"] = request.quantity()
	record["allocation_fraction"] = 0.0
	record["route"] = []
	record["route_travel_time"] = 0.0
	record["route_base_transport_cost"] = 0.0
	record["route_candidate_count"] = 0
	record["binding_edge_ids"] = []
	record["route_diagnostics"] = []
	record["blocked_by_higher_priority"] = false
	record["deterministic_tie_rule"] = (
		"priority_desc_then_weighted_progressive_bottleneck;"
		+ "request_id_only_for_canonical_iteration_and_epsilon_rounding"
	)
	record["status"] = "pending"
	record["reason"] = ""
	return record


func _build_edge_diagnostics(
	edge_usage: Dictionary,
	usage_by_priority_by_edge: Dictionary
) -> Dictionary:
	var output: Dictionary = {}
	for edge_id: String in edge_ids():
		var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
		var base_capacity: float = edge.capacity_per_period()
		var effective_capacity: float = float(_edge_capacities.get(edge_id, 0.0))
		var raw_priority_usage: Dictionary = (
			usage_by_priority_by_edge.get(edge_id, {}) as Dictionary
		)
		var canonical_priority_usage: Dictionary = {}
		var priorities: Array[int] = []
		for raw_priority: Variant in raw_priority_usage.keys():
			priorities.append(int(str(raw_priority)))
		priorities.sort()
		priorities.reverse()
		for priority: int in priorities:
			canonical_priority_usage[str(priority)] = _round_capacity(
				float(raw_priority_usage.get(str(priority), 0.0))
			)
		var used: float = _round_capacity(float(edge_usage.get(edge_id, 0.0)))
		output[edge_id] = {
			"edge_id": edge_id,
			"base_capacity": base_capacity,
			"enabled": edge.enabled(),
			"disruption_multiplier": edge.disruption_multiplier(),
			"disruption_capacity_loss": _round_capacity(
				base_capacity * (1.0 - edge.disruption_multiplier())
			),
			"closure_capacity_loss": (
				0.0 if edge.enabled() else _round_capacity(
					base_capacity * edge.disruption_multiplier()
				)
			),
			"effective_capacity": effective_capacity,
			"allocated_capacity": used,
			"remaining_capacity": _round_capacity(
				maxf(0.0, effective_capacity - used)
			),
			"saturated": effective_capacity - used <= CAPACITY_EPSILON,
			"usage_by_priority": canonical_priority_usage,
		}
	return output


func _allocate_priority_group(
	request_ids_value: Array[String],
	allocations: Dictionary,
	edge_remaining: Dictionary
) -> void:
	var active: Array[String] = request_ids_value.duplicate()
	active.sort()
	while not active.is_empty():
		var active_weight_by_edge: Dictionary = {}
		for request_id: String in active:
			var route: VNextSharedTransportRoute = _frozen_routes_by_id.get(request_id)
			if route == null:
				continue
			var request: VNextSharedTransportRequest = (
				_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
			)
			for edge_id: String in route.edge_ids():
				active_weight_by_edge[edge_id] = (
					float(active_weight_by_edge.get(edge_id, 0.0)) + request.weight()
				)

		var deltas: Dictionary = {}
		for request_id: String in active:
			var request: VNextSharedTransportRequest = (
				_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
			)
			var route: VNextSharedTransportRoute = _frozen_routes_by_id.get(request_id)
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
				var edge_share: float = (
					float(edge_remaining.get(edge_id, 0.0))
					* request.weight()
					/ total_weight
				)
				fair_increment = minf(fair_increment, maxf(0.0, edge_share))
			if fair_increment > CAPACITY_EPSILON and is_finite(fair_increment):
				deltas[request_id] = fair_increment

		if deltas.is_empty():
			break
		var total_delta: float = 0.0
		for request_id: String in active:
			if not deltas.has(request_id):
				continue
			var request: VNextSharedTransportRequest = (
				_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
			)
			var route: VNextSharedTransportRoute = _frozen_routes_by_id.get(request_id)
			var delta: float = minf(
				float(deltas[request_id]),
				maxf(0.0, request.quantity() - float(allocations.get(request_id, 0.0)))
			)
			for edge_id: String in route.edge_ids():
				delta = minf(delta, maxf(0.0, float(edge_remaining.get(edge_id, 0.0))))
			if delta <= CAPACITY_EPSILON:
				continue
			allocations[request_id] = _round_capacity(
				float(allocations.get(request_id, 0.0)) + delta
			)
			total_delta += delta
			for edge_id: String in route.edge_ids():
				edge_remaining[edge_id] = _round_capacity(
					maxf(0.0, float(edge_remaining.get(edge_id, 0.0)) - delta)
				)
		if total_delta <= CAPACITY_EPSILON:
			break
		var next_active: Array[String] = []
		for request_id: String in active:
			var request: VNextSharedTransportRequest = (
				_frozen_requests_by_id[request_id] as VNextSharedTransportRequest
			)
			if (
				request.quantity() - float(allocations.get(request_id, 0.0))
				<= CAPACITY_EPSILON
			):
				continue
			var route: VNextSharedTransportRoute = _frozen_routes_by_id.get(request_id)
			if route != null and _route_has_remaining_capacity(route, edge_remaining):
				next_active.append(request_id)
		active = next_active


func _find_deterministic_route(
	request: VNextSharedTransportRequest
) -> VNextSharedTransportRoute:
	var origin: String = request.origin_region_id()
	var destination: String = request.destination_region_id()
	var start_state: Dictionary = {
		"node": origin,
		"travel_time": 0.0,
		"base_cost": 0.0,
		"score": 0.0,
		"edge_ids": [],
		"nodes": [origin],
	}
	var labels_by_node: Dictionary = {origin: [start_state]}
	var open_states: Array[Dictionary] = [start_state]
	var constraints: Dictionary = request.route_constraints()
	var requires_pareto: bool = (
		_max_travel_time(constraints) >= 0.0
		or _max_base_transport_cost(constraints) >= 0.0
	)
	while not open_states.is_empty():
		var current_state: Dictionary = _select_best_open_state(open_states)
		open_states.erase(current_state)
		if not _label_is_current(current_state, labels_by_node):
			continue
		var current_node: String = str(current_state.get("node", ""))
		if current_node == destination:
			var path: Array[String] = []
			for raw_edge_id: Variant in current_state.get("edge_ids", []) as Array:
				path.append(str(raw_edge_id))
			return _build_route(request, path, true)
		var adjacent_ids: Array[String] = []
		for raw_edge_id: Variant in _adjacency.get(current_node, []) as Array:
			adjacent_ids.append(str(raw_edge_id))
		adjacent_ids.sort()
		for edge_id: String in adjacent_ids:
			var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
			if not edge.can_traverse_from(current_node) or edge.effective_capacity() <= CAPACITY_EPSILON:
				continue
			if not _edge_allowed_by_constraints(edge, constraints):
				continue
			var next_node: String = edge.next_region_from(current_node)
			if next_node.is_empty() or (current_state.get("nodes", []) as Array).has(next_node):
				continue
			var travel_time: float = (
				float(current_state.get("travel_time", 0.0)) + edge.travel_time()
			)
			var base_cost: float = (
				float(current_state.get("base_cost", 0.0)) + edge.base_transport_cost()
			)
			var max_travel: float = _max_travel_time(constraints)
			if max_travel >= 0.0 and travel_time > max_travel + CAPACITY_EPSILON:
				continue
			var max_base_cost: float = _max_base_transport_cost(constraints)
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
				"node": next_node,
				"travel_time": _round_capacity(travel_time),
				"base_cost": _round_capacity(base_cost),
				"score": _round_capacity(travel_time + base_cost),
				"edge_ids": edge_ids,
				"nodes": nodes,
			}
			var labels: Array = labels_by_node.get(next_node, []) as Array
			if not requires_pareto:
				if not labels.is_empty() and not _route_state_less(
					candidate, labels[0] as Dictionary
				):
					continue
				labels_by_node[next_node] = [candidate]
				open_states.append(candidate)
				continue
			var dominated: bool = false
			for raw_label: Variant in labels:
				if _state_dominates(raw_label as Dictionary, candidate):
					dominated = true
					break
			if dominated:
				continue
			var retained: Array[Dictionary] = []
			for raw_label: Variant in labels:
				var label: Dictionary = raw_label as Dictionary
				if not _state_dominates(candidate, label):
					retained.append(label)
			retained.append(candidate)
			labels_by_node[next_node] = retained
			open_states.append(candidate)
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
	var constraints: Dictionary = request.route_constraints()
	for edge_id: String in edge_ids_value:
		if seen_edges.has(edge_id) or not _edges_by_id.has(edge_id):
			return null
		seen_edges[edge_id] = true
		var edge: VNextSharedTransportEdge = _edges_by_id[edge_id] as VNextSharedTransportEdge
		if require_available_edges and (
			not edge.enabled() or edge.effective_capacity() <= CAPACITY_EPSILON
		):
			return null
		if not _edge_allowed_by_constraints(edge, constraints):
			return null
		var next_node: String = _next_node_without_availability(edge, current_node)
		if next_node.is_empty():
			return null
		current_node = next_node
		total_travel_time += edge.travel_time()
		total_base_cost += edge.base_transport_cost()
	if current_node != request.destination_region_id():
		return null
	var max_travel: float = _max_travel_time(constraints)
	if max_travel >= 0.0 and total_travel_time > max_travel + CAPACITY_EPSILON:
		return null
	var max_base_cost: float = _max_base_transport_cost(constraints)
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
	var disallowed_edges: Array[String] = _string_array_constraint(
		constraints, "disallowed_edge_ids"
	)
	if constraints.has("disallowed_edge_ids") and disallowed_edges.is_empty():
		return false
	if disallowed_edges.has(edge.edge_id()):
		return false
	var allowed_modes: Array[String] = _string_array_constraint(constraints, "allowed_modes")
	if constraints.has("allowed_modes") and allowed_modes.is_empty():
		return false
	if not allowed_modes.is_empty() and not allowed_modes.has(edge.mode()):
		return false
	var disallowed_modes: Array[String] = _string_array_constraint(
		constraints, "disallowed_modes"
	)
	if constraints.has("disallowed_modes") and disallowed_modes.is_empty():
		return false
	return not disallowed_modes.has(edge.mode())


func _constraints_are_well_formed(constraints: Dictionary) -> bool:
	for field_name: String in [
		"allowed_edge_ids", "disallowed_edge_ids", "allowed_modes", "disallowed_modes",
		"accepted_route", "accepted_edge_ids",
	]:
		if constraints.has(field_name) and _string_array_constraint(
			constraints, field_name
		).is_empty():
			return false
	for field_name: String in ["max_travel_time", "max_base_transport_cost"]:
		if constraints.has(field_name):
			var value: Variant = constraints.get(field_name)
			if (
				(typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT)
				or not is_finite(float(value))
				or float(value) < 0.0
			):
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


func _select_best_open_state(open_states: Array[Dictionary]) -> Dictionary:
	var selected: Dictionary = open_states[0]
	for state: Dictionary in open_states:
		if _route_state_less(state, selected):
			selected = state
	return selected


func _label_is_current(state: Dictionary, labels_by_node: Dictionary) -> bool:
	var state_key: String = _state_key(state)
	for raw_label: Variant in labels_by_node.get(str(state.get("node", "")), []) as Array:
		if _state_key(raw_label as Dictionary) == state_key:
			return true
	return false


func _state_dominates(left: Dictionary, right: Dictionary) -> bool:
	var left_travel: float = float(left.get("travel_time", INF))
	var right_travel: float = float(right.get("travel_time", INF))
	var left_cost: float = float(left.get("base_cost", INF))
	var right_cost: float = float(right.get("base_cost", INF))
	if (
		left_travel > right_travel + CAPACITY_EPSILON
		or left_cost > right_cost + CAPACITY_EPSILON
	):
		return false
	if (
		left_travel < right_travel - CAPACITY_EPSILON
		or left_cost < right_cost - CAPACITY_EPSILON
	):
		return true
	return _path_key(left.get("edge_ids", []) as Array) <= _path_key(
		right.get("edge_ids", []) as Array
	)


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
	return _path_key(left.get("edge_ids", []) as Array) < _path_key(
		right.get("edge_ids", []) as Array
	)


func _usage_above_priority(usage_by_priority: Dictionary, priority: int) -> float:
	var total: float = 0.0
	for raw_priority: Variant in usage_by_priority.keys():
		if int(str(raw_priority)) > priority:
			total += float(usage_by_priority.get(raw_priority, 0.0))
	return _round_capacity(total)


func _automatic_route_key(request: VNextSharedTransportRequest) -> String:
	var constraints: Dictionary = request.route_constraints()
	var canonical_constraints: Dictionary = {}
	for field_name: String in [
		"allowed_edge_ids", "disallowed_edge_ids", "allowed_modes", "disallowed_modes",
	]:
		if not constraints.has(field_name):
			continue
		var values: Array[String] = _string_array_constraint(constraints, field_name)
		values.sort()
		canonical_constraints[field_name] = values
	for field_name: String in ["max_travel_time", "max_base_transport_cost"]:
		if constraints.has(field_name):
			canonical_constraints[field_name] = float(constraints.get(field_name))
	return (
		request.origin_region_id()
		+ "\u001e"
		+ request.destination_region_id()
		+ "\u001e"
		+ JSON.stringify(canonical_constraints)
	)


func _current_topology_snapshot_id() -> String:
	var records: Array[Dictionary] = []
	for edge_id: String in _sorted_keys(_edges_by_id):
		records.append((_edges_by_id[edge_id] as VNextSharedTransportEdge).to_dictionary())
	return JSON.stringify(records).sha256_text()


func _append_adjacency(adjacency: Dictionary, node: String, edge_id: String) -> void:
	if not adjacency.has(node):
		adjacency[node] = []
	(adjacency[node] as Array).append(edge_id)


static func _state_key(state: Dictionary) -> String:
	return str(state.get("node", "")) + "\u001e" + _path_key(
		state.get("edge_ids", []) as Array
	)


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
