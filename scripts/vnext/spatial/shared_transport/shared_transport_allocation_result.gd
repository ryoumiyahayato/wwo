class_name VNextSharedTransportAllocationResult
extends RefCounted
## Detached read-only view of one published Shared Transport cycle.
##
## Every getter returns values or deep copies. The allocator retains a separate
## canonical result and returns a detached copy to each observer, so even
## reflective mutation of an underscore-prefixed member cannot change Spatial's
## published capacity truth or another consumer's view.

const CAPACITY_EPSILON: float = 0.000001

var _initialized: bool = false
var _allocation_time: int = -1
var _topology_snapshot_id: String = ""
var _route_candidate_count: int = 0
var _request_results: Dictionary = {}
var _allocations: Dictionary = {}
var _edge_diagnostics: Dictionary = {}
var _edge_capacities: Dictionary = {}
var _edge_usage: Dictionary = {}


static func build(
	allocation_time_value: int,
	topology_snapshot_id_value: String,
	request_results_value: Dictionary,
	edge_diagnostics_value: Dictionary,
	route_candidate_count_value: int
) -> VNextSharedTransportAllocationResult:
	var result := VNextSharedTransportAllocationResult.new()
	if not result._initialize_result(
		allocation_time_value,
		topology_snapshot_id_value,
		request_results_value,
		edge_diagnostics_value,
		route_candidate_count_value
	):
		return null
	return result


func is_valid() -> bool:
	if (
		not _initialized
		or _allocation_time < 0
		or _topology_snapshot_id.is_empty()
		or _route_candidate_count < 0
		or _request_results.size() != _allocations.size()
	):
		return false
	for request_id: String in _sorted_keys(_request_results):
		var record_value: Variant = _request_results.get(request_id)
		if typeof(record_value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = record_value as Dictionary
		if str(record.get("request_id", "")) != request_id:
			return false
		var quantity: float = float(record.get("quantity", -1.0))
		var allocated: float = float(record.get("allocated_quantity", -1.0))
		var unallocated: float = float(record.get("unallocated_quantity", -1.0))
		var fraction: float = float(record.get("allocation_fraction", -1.0))
		if (
			not is_finite(quantity)
			or quantity <= 0.0
			or not is_finite(allocated)
			or allocated < -CAPACITY_EPSILON
			or allocated > quantity + CAPACITY_EPSILON
			or not _approximately_equal(unallocated, maxf(0.0, quantity - allocated))
			or not _approximately_equal(fraction, allocated / quantity)
			or typeof(record.get("route", [])) != TYPE_ARRAY
			or typeof(record.get("binding_edge_ids", [])) != TYPE_ARRAY
			or typeof(record.get("route_diagnostics", [])) != TYPE_ARRAY
		):
			return false
		if not _approximately_equal(allocated, float(_allocations.get(request_id, -1.0))):
			return false

	for edge_id: String in _sorted_keys(_edge_diagnostics):
		var diagnostic_value: Variant = _edge_diagnostics.get(edge_id)
		if typeof(diagnostic_value) != TYPE_DICTIONARY:
			return false
		var diagnostic: Dictionary = diagnostic_value as Dictionary
		var base_capacity: float = float(diagnostic.get("base_capacity", -1.0))
		var effective_capacity: float = float(diagnostic.get("effective_capacity", -1.0))
		var usage: float = float(diagnostic.get("allocated_capacity", -1.0))
		var multiplier: float = float(diagnostic.get("disruption_multiplier", -1.0))
		if (
			str(diagnostic.get("edge_id", "")) != edge_id
			or not is_finite(base_capacity)
			or base_capacity < -CAPACITY_EPSILON
			or not is_finite(effective_capacity)
			or effective_capacity < -CAPACITY_EPSILON
			or effective_capacity > base_capacity + CAPACITY_EPSILON
			or not is_finite(usage)
			or usage < -CAPACITY_EPSILON
			or usage > effective_capacity + CAPACITY_EPSILON
			or not is_finite(multiplier)
			or multiplier < 0.0
			or multiplier > 1.0
			or typeof(diagnostic.get("usage_by_priority", {})) != TYPE_DICTIONARY
		):
			return false
		var priority_usage_total: float = 0.0
		var usage_by_priority: Dictionary = diagnostic.get("usage_by_priority") as Dictionary
		for priority_key: String in _sorted_keys(usage_by_priority):
			var priority_usage: float = float(usage_by_priority.get(priority_key, -1.0))
			if not is_finite(priority_usage) or priority_usage < -CAPACITY_EPSILON:
				return false
			priority_usage_total += priority_usage
		if not _approximately_equal(priority_usage_total, usage):
			return false

	var expected_usage: Dictionary = {}
	for request_id: String in _sorted_keys(_request_results):
		var request_record: Dictionary = _request_results[request_id] as Dictionary
		var allocated_quantity: float = float(request_record.get("allocated_quantity", 0.0))
		for raw_edge_id: Variant in request_record.get("route", []) as Array:
			var edge_id: String = str(raw_edge_id)
			if not _edge_diagnostics.has(edge_id):
				return false
			expected_usage[edge_id] = float(expected_usage.get(edge_id, 0.0)) + allocated_quantity
	for edge_id: String in _sorted_keys(_edge_diagnostics):
		if not _approximately_equal(
			float(_edge_usage.get(edge_id, 0.0)),
			float(expected_usage.get(edge_id, 0.0))
		):
			return false
	return true


func allocation_time() -> int:
	return _allocation_time


func topology_snapshot_id() -> String:
	return _topology_snapshot_id


func route_candidate_count() -> int:
	return _route_candidate_count


func is_immutable() -> bool:
	return _initialized


func detached_copy() -> VNextSharedTransportAllocationResult:
	return VNextSharedTransportAllocationResult.build(
		_allocation_time,
		_topology_snapshot_id,
		_request_results,
		_edge_diagnostics,
		_route_candidate_count
	)


func has_request(request_id: String) -> bool:
	return _request_results.has(request_id)


func request_ids() -> Array[String]:
	return _sorted_keys(_request_results)


func allocation_for(request_id: String) -> float:
	return float(_allocations.get(request_id, 0.0))


func requested_quantity(request_id: String) -> float:
	return float(request_result(request_id).get("quantity", 0.0))


func unallocated_quantity(request_id: String) -> float:
	return float(request_result(request_id).get("unallocated_quantity", 0.0))


func allocation_fraction(request_id: String) -> float:
	return float(request_result(request_id).get("allocation_fraction", 0.0))


func status_for(request_id: String) -> String:
	return str(request_result(request_id).get("status", "unknown_request"))


func reason_for(request_id: String) -> String:
	return str(request_result(request_id).get("reason", "unknown_request"))


func request_result(request_id: String) -> Dictionary:
	var value: Variant = _request_results.get(request_id, {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func request_results() -> Dictionary:
	return _request_results.duplicate(true)


func allocations() -> Dictionary:
	return _allocations.duplicate(true)


func edge_ids() -> Array[String]:
	return _sorted_keys(_edge_diagnostics)


func edge_capacity(edge_id: String) -> float:
	return float(_edge_capacities.get(edge_id, 0.0))


func edge_usage(edge_id: String) -> float:
	return float(_edge_usage.get(edge_id, 0.0))


func edge_remaining_capacity(edge_id: String) -> float:
	return maxf(0.0, edge_capacity(edge_id) - edge_usage(edge_id))


func edge_diagnostic(edge_id: String) -> Dictionary:
	var value: Variant = _edge_diagnostics.get(edge_id, {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func edge_diagnostics() -> Dictionary:
	return _edge_diagnostics.duplicate(true)


func edge_capacities() -> Dictionary:
	return _edge_capacities.duplicate(true)


func edge_usages() -> Dictionary:
	return _edge_usage.duplicate(true)


func total_requested_quantity() -> float:
	var total: float = 0.0
	for request_id: String in _sorted_keys(_request_results):
		total += float((_request_results[request_id] as Dictionary).get("quantity", 0.0))
	return snappedf(total, CAPACITY_EPSILON)


func total_allocated_quantity() -> float:
	var total: float = 0.0
	for request_id: String in _sorted_keys(_allocations):
		total += float(_allocations.get(request_id, 0.0))
	return snappedf(total, CAPACITY_EPSILON)


func snapshot() -> Dictionary:
	var request_records: Array[Dictionary] = []
	for request_id: String in _sorted_keys(_request_results):
		request_records.append((_request_results[request_id] as Dictionary).duplicate(true))
	var edge_records: Array[Dictionary] = []
	for edge_id: String in _sorted_keys(_edge_diagnostics):
		edge_records.append((_edge_diagnostics[edge_id] as Dictionary).duplicate(true))
	return {
		"allocation_time": _allocation_time,
		"topology_snapshot_id": _topology_snapshot_id,
		"route_candidate_count": _route_candidate_count,
		"requests": request_records,
		"edges": edge_records,
	}


func _initialize_result(
	allocation_time_value: int,
	topology_snapshot_id_value: String,
	request_results_value: Dictionary,
	edge_diagnostics_value: Dictionary,
	route_candidate_count_value: int
) -> bool:
	if (
		_initialized
		or allocation_time_value < 0
		or topology_snapshot_id_value.is_empty()
		or route_candidate_count_value < 0
	):
		return false
	_request_results = request_results_value.duplicate(true)
	_allocations = {}
	for request_id: String in _sorted_keys(_request_results):
		var record_value: Variant = _request_results.get(request_id)
		if typeof(record_value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = record_value as Dictionary
		if str(record.get("request_id", "")) != request_id:
			return false
		_allocations[request_id] = float(record.get("allocated_quantity", -1.0))
	_edge_diagnostics = edge_diagnostics_value.duplicate(true)
	_edge_capacities = {}
	_edge_usage = {}
	for edge_id: String in _sorted_keys(_edge_diagnostics):
		var diagnostic_value: Variant = _edge_diagnostics.get(edge_id)
		if typeof(diagnostic_value) != TYPE_DICTIONARY:
			return false
		var diagnostic: Dictionary = diagnostic_value as Dictionary
		_edge_capacities[edge_id] = float(diagnostic.get("effective_capacity", -1.0))
		_edge_usage[edge_id] = float(diagnostic.get("allocated_capacity", -1.0))
	_allocation_time = allocation_time_value
	_topology_snapshot_id = topology_snapshot_id_value
	_route_candidate_count = route_candidate_count_value
	_initialized = true
	return is_valid()


static func _approximately_equal(left: float, right: float) -> bool:
	return is_finite(left) and is_finite(right) and absf(left - right) <= CAPACITY_EPSILON


static func _sorted_keys(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key: Variant in value.keys():
		output.append(str(key))
	output.sort()
	return output
