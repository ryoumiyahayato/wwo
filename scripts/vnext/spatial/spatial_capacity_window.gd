class_name VNextSpatialCapacityWindow
extends RefCounted
## Hour-level shared physical capacity contract.
## Requests are reallocated from canonical request IDs, so submission order is
## never the deciding factor.

const CAPACITY_EPSILON: float = VNextInfrastructureLinkState.CAPACITY_EPSILON
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

var _catalog: VNextSpatialCatalog = null
var _infrastructure: Dictionary = {}
var _current_hour: int = 0
var _requests: Dictionary = {}


func initialize(
	catalog_value: VNextSpatialCatalog,
	infrastructure_value: Dictionary,
	initial_hour: int = 0
) -> bool:
	if catalog_value == null or not catalog_value.is_loaded():
		return false
	if not _is_valid_hour(initial_hour):
		return false
	_catalog = catalog_value
	_infrastructure = infrastructure_value
	_current_hour = initial_hour
	_requests = {}
	for link_id: String in _catalog.link_ids():
		_requests[link_id] = {}
	return _is_internal_state_valid()


func is_valid() -> bool:
	return _is_internal_state_valid()


func current_hour() -> int:
	return _current_hour


func advance_to_hour(absolute_hour: int) -> bool:
	if not _is_internal_state_valid():
		return false
	if not _is_valid_hour(absolute_hour) or absolute_hour < _current_hour:
		return false
	while _current_hour < absolute_hour:
		_current_hour += 1
		_clear_requests()
	return true


func advance_hours(elapsed_hours: int) -> bool:
	if elapsed_hours < 0 or elapsed_hours > MAX_JSON_SAFE_INTEGER - _current_hour:
		return false
	return advance_to_hour(_current_hour + elapsed_hours)


# LEGACY TRANSPORT COMPATIBILITY PATH. Economy and Military still submit here
# until an authorized product-line migration collects all domain demand into one
# Shared Transport cycle. New consumers must not use this link-level allocator.
func request_capacity_batch(request_values: Array[Dictionary]) -> Dictionary:
	var rejected: Dictionary = {
		"success": false,
		"accepted": false,
		"reason": "",
		"results": {},
	}
	if not _is_internal_state_valid():
		rejected["reason"] = "invalid_capacity_state"
		return rejected
	if request_values.is_empty():
		rejected["reason"] = "empty_batch"
		return rejected

	var candidate_requests: Dictionary = {}
	for link_id: String in _catalog.link_ids():
		candidate_requests[link_id] = (_requests[link_id] as Dictionary).duplicate(true)
	for request_value: Dictionary in request_values:
		if not _has_fields(request_value, ["request_id", "link_id", "window_hour", "demand"]):
			rejected["reason"] = "invalid_batch_request"
			return rejected
		if typeof(request_value.get("request_id")) != TYPE_STRING or typeof(request_value.get("link_id")) != TYPE_STRING:
			rejected["reason"] = "invalid_batch_request"
			return rejected
		var request_id: String = str(request_value.get("request_id", ""))
		var link_id: String = str(request_value.get("link_id", ""))
		var window_hour: int = _parse_hour(request_value.get("window_hour"))
		var demand: float = _parse_positive_finite(request_value.get("demand"))
		if not _is_valid_request_id(request_id):
			rejected["reason"] = "invalid_request_id"
			return rejected
		if not _catalog.has_link(link_id):
			rejected["reason"] = "unknown_link"
			return rejected
		if window_hour != _current_hour:
			rejected["reason"] = "wrong_window"
			return rejected
		if demand <= 0.0:
			rejected["reason"] = "invalid_demand"
			return rejected
		if _request_exists_in(candidate_requests, request_id):
			rejected["reason"] = "duplicate_request"
			return rejected
		(candidate_requests[link_id] as Dictionary)[request_id] = {
			"request_id": request_id,
			"link_id": link_id,
			"window_hour": window_hour,
			"demand": _round_capacity(demand),
			"allocated_capacity": 0.0,
		}

	var previous_requests: Dictionary = _requests
	_requests = candidate_requests
	_recompute_allocations()
	if not _is_internal_state_valid():
		_requests = previous_requests
		rejected["reason"] = "invalid_capacity_state"
		return rejected

	# Build the response from one canonical calculation. Calling
	# reservation_result() once per member would recursively recalculate the whole
	# window and turn a batch into O(n^2) while producing identical values.
	var calculation: Dictionary = _calculate_allocations()
	var usage_by_link: Dictionary = calculation.get("usage", {})
	var results: Dictionary = {}
	for request_value: Dictionary in request_values:
		var request_id: String = str(request_value.get("request_id", ""))
		var link_id: String = str(request_value.get("link_id", ""))
		var request: Dictionary = (_requests[link_id] as Dictionary)[request_id]
		var demand: float = float(request.get("demand", 0.0))
		var allocated: float = float(request.get("allocated_capacity", 0.0))
		var result: Dictionary = _result_base(request_id, link_id, _current_hour, demand, allocated)
		result["success"] = true
		result["accepted"] = true
		result["status"] = _allocation_status(demand, allocated)
		result["remaining_capacity"] = float((usage_by_link.get(link_id, {}) as Dictionary).get("remaining_capacity", 0.0))
		results[request_id] = result
	return {"success": true, "accepted": true, "reason": "", "results": results}


# Internal implementation for the legacy Military cancellation wrapper. This
# can release an old-window reservation but cannot admit or increase demand.
func _cancel_capacity_request(request_id: String, link_id: String, window_hour: int) -> bool:
	if not _is_internal_state_valid() or window_hour != _current_hour:
		return false
	if not _requests.has(link_id) or not (_requests[link_id] as Dictionary).has(request_id):
		return false
	(_requests[link_id] as Dictionary).erase(request_id)
	_recompute_allocations()
	return true


func reservation_result(request_id: String, link_id: String, window_hour: int) -> Dictionary:
	var rejected: Dictionary = _result_base(request_id, link_id, window_hour, 0.0, 0.0)
	if not _is_internal_state_valid():
		rejected["reason"] = "invalid_capacity_state"
		return rejected
	if not _requests.has(link_id) or not (_requests[link_id] as Dictionary).has(request_id):
		rejected["reason"] = "unknown_request"
		return rejected
	var request: Dictionary = (_requests[link_id] as Dictionary)[request_id]
	var summary: Dictionary = capacity_summary(link_id)
	var demand: float = float(request.get("demand", 0.0))
	var allocated: float = float(request.get("allocated_capacity", 0.0))
	var result: Dictionary = _result_base(
		request_id, link_id, window_hour, demand, allocated
	)
	result["success"] = true
	result["accepted"] = true
	result["status"] = _allocation_status(demand, allocated)
	result["remaining_capacity"] = float(summary.get("remaining_capacity", 0.0))
	return result


func reservation_results_batch(request_values: Array[Dictionary]) -> Dictionary:
	var rejected: Dictionary = {
		"success": false,
		"accepted": false,
		"reason": "",
		"results": {},
	}
	if not _is_internal_state_valid():
		rejected["reason"] = "invalid_capacity_state"
		return rejected
	if request_values.is_empty():
		rejected["reason"] = "empty_batch"
		return rejected
	var calculation: Dictionary = _calculate_allocations()
	var usage_by_link: Dictionary = calculation.get("usage", {})
	var results: Dictionary = {}
	for request_value: Dictionary in request_values:
		if not _has_fields(request_value, ["request_id", "link_id", "window_hour"]):
			rejected["reason"] = "invalid_batch_request"
			return rejected
		var request_id: String = str(request_value.get("request_id", ""))
		var link_id: String = str(request_value.get("link_id", ""))
		var window_hour: int = _parse_hour(request_value.get("window_hour"))
		if window_hour != _current_hour:
			rejected["reason"] = "wrong_window"
			return rejected
		if not _requests.has(link_id) or not (_requests[link_id] as Dictionary).has(request_id):
			rejected["reason"] = "unknown_request"
			return rejected
		var request: Dictionary = (_requests[link_id] as Dictionary)[request_id]
		var demand: float = float(request.get("demand", 0.0))
		var allocated: float = float(request.get("allocated_capacity", 0.0))
		var result: Dictionary = _result_base(request_id, link_id, window_hour, demand, allocated)
		result["success"] = true
		result["accepted"] = true
		result["status"] = _allocation_status(demand, allocated)
		result["remaining_capacity"] = float((usage_by_link.get(link_id, {}) as Dictionary).get("remaining_capacity", 0.0))
		results[request_id] = result
	return {"success": true, "accepted": true, "reason": "", "results": results}


func capacity_summary(link_id: String) -> Dictionary:
	if not _is_internal_state_valid() or not _catalog.has_link(link_id):
		return {}
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	if state == null:
		return {}
	var calculation: Dictionary = _calculate_allocations()
	var usage: Dictionary = (calculation.get("usage", {}) as Dictionary).get(link_id, {})
	var reservations: Array[Dictionary] = []
	var link_requests: Dictionary = _requests[link_id]
	for request_id: String in _sorted_keys(link_requests):
		var request: Dictionary = link_requests[request_id]
		reservations.append({
			"request_id": request_id,
			"link_id": link_id,
			"window_hour": _current_hour,
			"demand": float(request.get("demand", 0.0)),
			"allocated_capacity": float(request.get("allocated_capacity", 0.0)),
		})
	return {
		"link_id": link_id,
		"window_hour": _current_hour,
		"nominal_capacity": state.nominal_capacity(),
		"effective_capacity": state.effective_capacity(),
		"used_capacity": float(usage.get("used_capacity", 0.0)),
		"remaining_capacity": float(usage.get("remaining_capacity", 0.0)),
		"reservations": reservations,
	}


func used_capacity(link_id: String) -> float:
	return float(capacity_summary(link_id).get("used_capacity", 0.0))


func remaining_capacity(link_id: String) -> float:
	return float(capacity_summary(link_id).get("remaining_capacity", 0.0))


func snapshot() -> Dictionary:
	if not _is_internal_state_valid():
		return {}
	var calculation: Dictionary = _calculate_allocations()
	var allocations: Dictionary = calculation.get("allocations", {})
	var reservations: Array[Dictionary] = []
	for link_id: String in _catalog.link_ids():
		var link_requests: Dictionary = _requests[link_id]
		for request_id: String in _sorted_keys(link_requests):
			var request: Dictionary = link_requests[request_id]
			reservations.append({
				"request_id": request_id,
				"link_id": link_id,
				"window_hour": _current_hour,
				"demand": float(request.get("demand", 0.0)),
				"allocated_capacity": float(allocations.get(request_id, 0.0)),
			})
	var link_usage: Array[Dictionary] = []
	var usage_by_link: Dictionary = calculation.get("usage", {})
	for link_id: String in _catalog.link_ids():
		var state: VNextInfrastructureLinkState = _state_for_link(link_id)
		var usage: Dictionary = usage_by_link.get(link_id, {})
		link_usage.append({
			"link_id": link_id,
			"window_hour": _current_hour,
			"nominal_capacity": state.nominal_capacity(),
			"effective_capacity": state.effective_capacity(),
			"used_capacity": float(usage.get("used_capacity", 0.0)),
			"remaining_capacity": float(usage.get("remaining_capacity", 0.0)),
		})
	return {
		"window_hour": _current_hour,
		"reservations": reservations,
		"link_usage": link_usage,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if not _is_internal_state_valid():
		return false
	if snapshot_value.size() != 3 or not _has_fields(
		snapshot_value, ["window_hour", "reservations", "link_usage"]
	):
		return false
	var candidate_hour: int = _parse_hour(snapshot_value.get("window_hour"))
	if candidate_hour < 0 or typeof(snapshot_value.get("reservations")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("link_usage")) != TYPE_ARRAY:
		return false
	var candidate_requests: Dictionary = {}
	for link_id: String in _catalog.link_ids():
		candidate_requests[link_id] = {}
	var reservations: Array = snapshot_value.get("reservations")
	for raw_value: Variant in reservations:
		if typeof(raw_value) != TYPE_DICTIONARY:
			return false
		var reservation: Dictionary = raw_value
		if reservation.size() != 5 or not _has_fields(reservation, [
			"request_id", "link_id", "window_hour", "demand", "allocated_capacity",
		]):
			return false
		if typeof(reservation.get("request_id")) != TYPE_STRING:
			return false
		if typeof(reservation.get("link_id")) != TYPE_STRING:
			return false
		var request_id: String = str(reservation.get("request_id"))
		var link_id: String = str(reservation.get("link_id"))
		var reservation_hour: int = _parse_hour(reservation.get("window_hour"))
		var demand: float = _parse_positive_finite(reservation.get("demand"))
		var allocated: float = _parse_nonnegative_finite(
			reservation.get("allocated_capacity")
		)
		if (
			not _is_valid_request_id(request_id)
			or not _catalog.has_link(link_id)
			or reservation_hour < 0
			or reservation_hour != candidate_hour
			or demand <= 0.0
			or allocated < 0.0
			or _request_exists_in(candidate_requests, request_id)
		):
			return false
		(candidate_requests[link_id] as Dictionary)[request_id] = {
			"request_id": request_id,
			"link_id": link_id,
			"window_hour": reservation_hour,
			"demand": _round_capacity(demand),
			"allocated_capacity": _round_capacity(allocated),
		}

	var supplied_usage: Dictionary = {}
	var usage_records: Array = snapshot_value.get("link_usage")
	for raw_value: Variant in usage_records:
		if typeof(raw_value) != TYPE_DICTIONARY:
			return false
		var usage: Dictionary = raw_value
		if usage.size() != 6 or not _has_fields(usage, [
			"link_id", "window_hour", "nominal_capacity", "effective_capacity",
			"used_capacity", "remaining_capacity",
		]):
			return false
		if typeof(usage.get("link_id")) != TYPE_STRING:
			return false
		var link_id: String = str(usage.get("link_id"))
		var hour_value: int = _parse_hour(usage.get("window_hour"))
		var nominal: float = _parse_nonnegative_finite(usage.get("nominal_capacity"))
		var effective: float = _parse_nonnegative_finite(usage.get("effective_capacity"))
		var used: float = _parse_nonnegative_finite(usage.get("used_capacity"))
		var remaining: float = _parse_nonnegative_finite(usage.get("remaining_capacity"))
		if (
			hour_value < 0
			or hour_value != candidate_hour
			or not _catalog.has_link(link_id)
			or supplied_usage.has(link_id)
			or nominal < 0.0
			or effective < 0.0
			or used < 0.0
			or remaining < 0.0
		):
			return false
		supplied_usage[link_id] = {
			"nominal_capacity": _round_capacity(nominal),
			"effective_capacity": _round_capacity(effective),
			"used_capacity": _round_capacity(used),
			"remaining_capacity": _round_capacity(remaining),
		}
	if supplied_usage.size() != _catalog.link_ids().size():
		return false

	var candidate := VNextSpatialCapacityWindow.new()
	candidate._catalog = _catalog
	candidate._infrastructure = _infrastructure
	candidate._current_hour = candidate_hour
	candidate._requests = candidate_requests
	if not candidate._is_internal_state_valid():
		return false
	var calculation: Dictionary = candidate._calculate_allocations()
	var allocations: Dictionary = calculation.get("allocations", {})
	for link_id: String in candidate._catalog.link_ids():
		for request_id: String in candidate._sorted_keys(candidate_requests[link_id]):
			var request: Dictionary = (candidate_requests[link_id] as Dictionary)[request_id]
			if not _approximately_equal(
				float(request.get("allocated_capacity", -1.0)),
				float(allocations.get(request_id, -1.0))
			):
				return false
	var usage_by_link: Dictionary = calculation.get("usage", {})
	for link_id: String in candidate._catalog.link_ids():
		var expected: Dictionary = usage_by_link.get(link_id, {})
		var supplied: Dictionary = supplied_usage.get(link_id, {})
		var state: VNextInfrastructureLinkState = candidate._state_for_link(link_id)
		if not _approximately_equal(float(supplied.get("nominal_capacity", -1.0)), state.nominal_capacity()):
			return false
		if not _approximately_equal(float(supplied.get("effective_capacity", -1.0)), float(expected.get("effective_capacity", -1.0))):
			return false
		if not _approximately_equal(float(supplied.get("used_capacity", -1.0)), float(expected.get("used_capacity", -1.0))):
			return false
		if not _approximately_equal(float(supplied.get("remaining_capacity", -1.0)), float(expected.get("remaining_capacity", -1.0))):
			return false
	_current_hour = candidate._current_hour
	_requests = candidate._requests
	return true


func _is_internal_state_valid() -> bool:
	if _catalog == null or not _catalog.is_loaded() or not _is_valid_hour(_current_hour):
		return false
	if _requests.size() != _catalog.link_ids().size():
		return false
	for link_id: String in _catalog.link_ids():
		if not _requests.has(link_id) or _state_for_link(link_id) == null:
			return false
		var link_requests: Dictionary = _requests[link_id]
		for request_id: String in _sorted_keys(link_requests):
			var request: Variant = link_requests[request_id]
			if typeof(request) != TYPE_DICTIONARY:
				return false
			var record: Dictionary = request
			if record.size() != 5 or not _has_fields(record, [
				"request_id", "link_id", "window_hour", "demand", "allocated_capacity",
			]):
				return false
			if (
				typeof(record.get("request_id")) != TYPE_STRING
				or typeof(record.get("link_id")) != TYPE_STRING
				or typeof(record.get("window_hour")) != TYPE_INT
				or str(record.get("request_id")) != request_id
				or str(record.get("link_id")) != link_id
				or int(record.get("window_hour")) != _current_hour
				or not _is_valid_request_id(request_id)
				or _parse_positive_finite(record.get("demand")) <= 0.0
				or _parse_nonnegative_finite(record.get("allocated_capacity")) < 0.0
			):
				return false
	var calculation: Dictionary = _calculate_allocations()
	var allocations: Dictionary = calculation.get("allocations", {})
	for link_id: String in _catalog.link_ids():
		var link_requests: Dictionary = _requests[link_id]
		for request_id: String in _sorted_keys(link_requests):
			if not _approximately_equal(
				float(link_requests[request_id].get("allocated_capacity", -1.0)),
				float(allocations.get(request_id, -1.0))
			):
				return false
	return true


func _calculate_allocations() -> Dictionary:
	var allocations: Dictionary = {}
	var usage: Dictionary = {}
	if _catalog == null:
		return {"allocations": allocations, "usage": usage}
	for link_id: String in _catalog.link_ids():
		var state: VNextInfrastructureLinkState = _state_for_link(link_id)
		if state == null:
			continue
		var effective: float = state.effective_capacity()
		var used: float = 0.0
		var link_requests: Dictionary = _requests.get(link_id, {})
		for request_id: String in _sorted_keys(link_requests):
			var demand: float = maxf(0.0, float(link_requests[request_id].get("demand", 0.0)))
			var allocated: float = _round_capacity(minf(demand, maxf(0.0, effective - used)))
			allocations[request_id] = allocated
			used = _round_capacity(used + allocated)
		usage[link_id] = {
			"effective_capacity": _round_capacity(effective),
			"used_capacity": used,
			"remaining_capacity": maxf(0.0, _round_capacity(effective - used)),
		}
	return {"allocations": allocations, "usage": usage}


func _recompute_allocations() -> void:
	var allocations: Dictionary = _calculate_allocations().get("allocations", {})
	for link_id: String in _catalog.link_ids():
		for request_id: String in _sorted_keys(_requests[link_id]):
			(_requests[link_id] as Dictionary)[request_id]["allocated_capacity"] = float(allocations.get(request_id, 0.0))


func _clear_requests() -> void:
	_requests.clear()
	for link_id: String in _catalog.link_ids():
		_requests[link_id] = {}


func _state_for_link(link_id: String) -> VNextInfrastructureLinkState:
	var value: Variant = _infrastructure.get(link_id)
	if not value is VNextInfrastructureLinkState:
		return null
	return value as VNextInfrastructureLinkState


func _request_exists(request_id: String) -> bool:
	return _request_exists_in(_requests, request_id)


static func _request_exists_in(requests: Dictionary, request_id: String) -> bool:
	for value: Variant in requests.values():
		if typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(request_id):
			return true
	return false


static func _result_base(
	request_id: String, link_id: String, window_hour: int, demand: float, allocated: float
) -> Dictionary:
	return {
		"success": false,
		"accepted": false,
		"status": "rejected",
		"reason": "",
		"request_id": request_id,
		"link_id": link_id,
		"window_hour": window_hour,
		"requested_capacity": demand,
		"allocated_capacity": allocated,
		"remaining_capacity": 0.0,
	}


static func _allocation_status(demand: float, allocated: float) -> String:
	if allocated <= CAPACITY_EPSILON:
		return "unfulfilled"
	if allocated + CAPACITY_EPSILON < demand:
		return "partial"
	return "allocated"


static func _is_valid_request_id(request_id: String) -> bool:
	if request_id.is_empty() or request_id.length() > 256:
		return false
	for character_index: int in request_id.length():
		if request_id.substr(character_index, 1).unicode_at(0) < 32:
			return false
	return true


static func _is_valid_hour(hour_value: int) -> bool:
	return hour_value >= 0 and hour_value <= MAX_JSON_SAFE_INTEGER


static func _parse_hour(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		var integer_hour: int = int(value)
		return integer_hour if _is_valid_hour(integer_hour) else -1
	if typeof(value) == TYPE_FLOAT:
		var float_hour: float = float(value)
		if not is_finite(float_hour) or float_hour != floor(float_hour):
			return -1
		var normalized_hour: int = int(float_hour)
		return normalized_hour if _is_valid_hour(normalized_hour) else -1
	return -1


static func _parse_positive_finite(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized > 0.0 else -1.0


static func _parse_nonnegative_finite(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized >= 0.0 else -1.0


static func _has_fields(value: Dictionary, fields: Array[String]) -> bool:
	for field_name: String in fields:
		if not value.has(field_name):
			return false
	return true


static func _approximately_equal(left: float, right: float) -> bool:
	return is_finite(left) and is_finite(right) and absf(left - right) <= CAPACITY_EPSILON


static func _round_capacity(value: float) -> float:
	return snappedf(value, CAPACITY_EPSILON)


static func _sorted_keys(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key: Variant in value.keys():
		output.append(str(key))
	output.sort()
	return output
