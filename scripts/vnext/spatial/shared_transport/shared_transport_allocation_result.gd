class_name VNextSharedTransportAllocationResult
extends RefCounted
## Read-only result of one frozen Spatial allocation batch.
##
## Getter methods return copies. There is intentionally no mutation API: a
## consumer can apply this result to its own state, but cannot alter Spatial's
## authoritative allocation.

const CAPACITY_EPSILON: float = 0.000001

var _initialized: bool = false
var _allocation_time: int = -1
var _request_results: Dictionary = {}
var _allocations: Dictionary = {}
var _edge_capacities: Dictionary = {}
var _edge_usage: Dictionary = {}


static func build(
	allocation_time_value: int,
	request_results_value: Dictionary,
	edge_capacities_value: Dictionary,
	edge_usage_value: Dictionary
) -> VNextSharedTransportAllocationResult:
	var result := VNextSharedTransportAllocationResult.new()
	if not result._initialize_result(
		allocation_time_value,
		request_results_value,
		edge_capacities_value,
		edge_usage_value
	):
		return null
	return result


func is_valid() -> bool:
	if not _initialized or _allocation_time < 0:
		return false
	if _request_results.size() != _allocations.size():
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
		if (
			not is_finite(quantity)
			or quantity < 0.0
			or not is_finite(allocated)
			or allocated < -CAPACITY_EPSILON
			or allocated > quantity + CAPACITY_EPSILON
		):
			return false
		if not _approximately_equal(allocated, float(_allocations.get(request_id, -1.0))):
			return false
	for edge_id: String in _sorted_keys(_edge_capacities):
		var capacity: float = float(_edge_capacities.get(edge_id, -1.0))
		var usage: float = float(_edge_usage.get(edge_id, -1.0))
		if (
			not is_finite(capacity)
			or capacity < -CAPACITY_EPSILON
			or not is_finite(usage)
			or usage < -CAPACITY_EPSILON
			or usage > capacity + CAPACITY_EPSILON
		):
			return false
	var expected_usage: Dictionary = {}
	for request_id: String in _sorted_keys(_request_results):
		var request_record: Dictionary = _request_results[request_id] as Dictionary
		var allocated_quantity: float = float(request_record.get("allocated_quantity", 0.0))
		for raw_edge_id: Variant in request_record.get("route", []) as Array:
			var edge_id: String = str(raw_edge_id)
			expected_usage[edge_id] = float(expected_usage.get(edge_id, 0.0)) + allocated_quantity
	for edge_id: String in _sorted_keys(_edge_capacities):
		if not _approximately_equal(
			float(_edge_usage.get(edge_id, 0.0)),
			float(expected_usage.get(edge_id, 0.0))
		):
			return false
	return true


func allocation_time() -> int:
	return _allocation_time


func is_immutable() -> bool:
	return _initialized


func has_request(request_id: String) -> bool:
	return _request_results.has(request_id)


func request_ids() -> Array[String]:
	return _sorted_keys(_request_results)


func allocation_for(request_id: String) -> float:
	return float(_allocations.get(request_id, 0.0))


func requested_quantity(request_id: String) -> float:
	var record: Dictionary = request_result(request_id)
	return float(record.get("quantity", 0.0))


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
	return _sorted_keys(_edge_capacities)


func edge_capacity(edge_id: String) -> float:
	return float(_edge_capacities.get(edge_id, 0.0))


func edge_usage(edge_id: String) -> float:
	return float(_edge_usage.get(edge_id, 0.0))


func edge_remaining_capacity(edge_id: String) -> float:
	return maxf(0.0, edge_capacity(edge_id) - edge_usage(edge_id))


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
	for edge_id: String in _sorted_keys(_edge_capacities):
		edge_records.append({
			"edge_id": edge_id,
			"effective_capacity": float(_edge_capacities.get(edge_id, 0.0)),
			"allocated_capacity": float(_edge_usage.get(edge_id, 0.0)),
			"remaining_capacity": edge_remaining_capacity(edge_id),
		})
	return {
		"allocation_time": _allocation_time,
		"requests": request_records,
		"edges": edge_records,
	}


func _initialize_result(
	allocation_time_value: int,
	request_results_value: Dictionary,
	edge_capacities_value: Dictionary,
	edge_usage_value: Dictionary
) -> bool:
	if _initialized or allocation_time_value < 0:
		return false
	_request_results = request_results_value.duplicate(true)
	_allocations = {}
	for request_id: String in _sorted_keys(_request_results):
		var record_value: Variant = _request_results.get(request_id)
		if typeof(record_value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = record_value as Dictionary
		if record.get("request_id", "") != request_id:
			return false
		_allocations[request_id] = float(record.get("allocated_quantity", -1.0))
	_edge_capacities = {}
	for edge_id: String in _sorted_keys(edge_capacities_value):
		var capacity: float = float(edge_capacities_value.get(edge_id, -1.0))
		if not is_finite(capacity) or capacity < 0.0:
			return false
		_edge_capacities[edge_id] = snappedf(capacity, CAPACITY_EPSILON)
	_edge_usage = {}
	for edge_id: String in _sorted_keys(_edge_capacities):
		var usage: float = float(edge_usage_value.get(edge_id, 0.0))
		if not is_finite(usage) or usage < 0.0:
			return false
		_edge_usage[edge_id] = snappedf(usage, CAPACITY_EPSILON)
	_allocation_time = allocation_time_value
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
