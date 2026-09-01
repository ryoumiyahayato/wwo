class_name VNextSharedTransportRequest
extends RefCounted
## Generic demand submitted to the shared physical transport allocator.
##
## A request is configured once and is immutable afterwards. The requester owns
## the demand; Spatial owns routing, physical capacity and the final result.

const MAX_ID_LENGTH: int = 256
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

var _configured: bool = false
var _request_id: String = ""
var _requester_system: String = ""
var _origin_region_id: String = ""
var _destination_region_id: String = ""
var _quantity: float = 0.0
var _cargo_class: String = ""
var _priority_class: int = 0
var _weight: float = 1.0
var _earliest_time: int = 0
var _has_latest_time: bool = false
var _latest_time: int = -1
var _accepted_route: Array[String] = []
var _route_constraints: Dictionary = {}


static func create(
	request_id_value: String,
	requester_system_value: String,
	origin_region_id_value: String,
	destination_region_id_value: String,
	quantity_value: Variant,
	cargo_class_value: String,
	priority_class_value: Variant,
	weight_value: Variant,
	earliest_time_value: Variant,
	latest_time_value: Variant = null,
	accepted_route_value: Array[String] = [],
	route_constraints_value: Dictionary = {}
) -> VNextSharedTransportRequest:
	var request := VNextSharedTransportRequest.new()
	if not request.configure(
		request_id_value,
		requester_system_value,
		origin_region_id_value,
		destination_region_id_value,
		quantity_value,
		cargo_class_value,
		priority_class_value,
		weight_value,
		earliest_time_value,
		latest_time_value,
		accepted_route_value,
		route_constraints_value
	):
		return null
	return request


static func from_dictionary(value: Dictionary) -> VNextSharedTransportRequest:
	if value.is_empty():
		return null
	for field_name: String in [
		"request_id", "requester_system", "origin_region_id", "destination_region_id",
		"cargo_class",
	]:
		if not value.has(field_name) or typeof(value.get(field_name)) != TYPE_STRING:
			return null
	var accepted_route: Array[String] = []
	if value.has("accepted_route") or value.has("route"):
		var direct_route: Variant = value.get("accepted_route", value.get("route", []))
		if not _is_string_array(direct_route):
			return null
		accepted_route = _string_array_from_variant(direct_route)
	var constraints_value: Variant = value.get("route_constraints", {})
	if typeof(constraints_value) != TYPE_DICTIONARY:
		return null
	var constraints: Dictionary = (constraints_value as Dictionary).duplicate(true)
	if accepted_route.is_empty():
		for field_name: String in ["accepted_route", "accepted_edge_ids"]:
			if not constraints.has(field_name):
				continue
			var constrained_route: Variant = constraints.get(field_name)
			if not _is_string_array(constrained_route):
				return null
			accepted_route = _string_array_from_variant(constraints.get(
				"accepted_route", constraints.get("accepted_edge_ids", [])
			))
	var request := VNextSharedTransportRequest.new()
	if not request.configure(
		str(value.get("request_id", "")),
		str(value.get("requester_system", "")),
		str(value.get("origin_region_id", "")),
		str(value.get("destination_region_id", "")),
		value.get("quantity", -1.0),
		str(value.get("cargo_class", "")),
		value.get("priority_class", -1),
		value.get("weight", -1.0),
		value.get("earliest_time", -1),
		value.get("latest_time", null),
		accepted_route,
		constraints
	):
		return null
	return request


func configure(
	request_id_value: String,
	requester_system_value: String,
	origin_region_id_value: String,
	destination_region_id_value: String,
	quantity_value: Variant,
	cargo_class_value: String,
	priority_class_value: Variant,
	weight_value: Variant,
	earliest_time_value: Variant,
	latest_time_value: Variant = null,
	accepted_route_value: Array[String] = [],
	route_constraints_value: Dictionary = {}
) -> bool:
	if _configured:
		return false
	var quantity: float = _parse_positive_finite(quantity_value)
	var priority_class: int = _parse_integer(priority_class_value)
	var weight: float = _parse_positive_finite(weight_value)
	var earliest_time: int = _parse_time(earliest_time_value)
	if (
		not _is_valid_identifier(request_id_value)
		or not _is_valid_identifier(requester_system_value)
		or not _is_valid_identifier(origin_region_id_value)
		or not _is_valid_identifier(destination_region_id_value)
		or not _is_valid_identifier(cargo_class_value)
		or quantity <= 0.0
		or priority_class < 0
		or weight <= 0.0
		or earliest_time < 0
		or typeof(route_constraints_value) != TYPE_DICTIONARY
	):
		return false

	var has_latest_time: bool = latest_time_value != null
	var latest_time: int = -1
	if has_latest_time:
		latest_time = _parse_time(latest_time_value)
		if latest_time < earliest_time:
			return false
	var accepted_route: Array[String] = accepted_route_value.duplicate()
	for edge_id: String in accepted_route:
		if not _is_valid_identifier(edge_id):
			return false

	_request_id = request_id_value
	_requester_system = requester_system_value
	_origin_region_id = origin_region_id_value
	_destination_region_id = destination_region_id_value
	_quantity = _round_quantity(quantity)
	_cargo_class = cargo_class_value
	_priority_class = priority_class
	_weight = _round_quantity(weight)
	_earliest_time = earliest_time
	_has_latest_time = has_latest_time
	_latest_time = latest_time
	_accepted_route = accepted_route
	_route_constraints = route_constraints_value.duplicate(true)
	_configured = true
	return true


func is_valid() -> bool:
	return (
		_configured
		and _is_valid_identifier(_request_id)
		and _is_valid_identifier(_requester_system)
		and _is_valid_identifier(_origin_region_id)
		and _is_valid_identifier(_destination_region_id)
		and _is_valid_identifier(_cargo_class)
		and is_finite(_quantity)
		and _quantity > 0.0
		and _priority_class >= 0
		and is_finite(_weight)
		and _weight > 0.0
		and _earliest_time >= 0
		and (
			not _has_latest_time
			or _latest_time >= _earliest_time
		)
	)


func request_id() -> String:
	return _request_id


func requester_system() -> String:
	return _requester_system


func origin_region_id() -> String:
	return _origin_region_id


func destination_region_id() -> String:
	return _destination_region_id


func quantity() -> float:
	return _quantity


func cargo_class() -> String:
	return _cargo_class


func priority_class() -> int:
	return _priority_class


func weight() -> float:
	return _weight


func earliest_time() -> int:
	return _earliest_time


func has_latest_time() -> bool:
	return _has_latest_time


func latest_time() -> int:
	return _latest_time


func is_active_at(time_value: int) -> bool:
	return (
		is_valid()
		and time_value >= _earliest_time
		and (not _has_latest_time or time_value <= _latest_time)
	)


func has_accepted_route() -> bool:
	return not accepted_route().is_empty()


func accepted_route() -> Array[String]:
	if not _accepted_route.is_empty():
		return _accepted_route.duplicate()
	var constrained_route: Variant = _route_constraints.get(
		"accepted_route", _route_constraints.get("accepted_edge_ids", [])
	)
	return _string_array_from_variant(constrained_route)


func route_constraints() -> Dictionary:
	return _route_constraints.duplicate(true)


func to_dictionary() -> Dictionary:
	var output: Dictionary = {
		"request_id": _request_id,
		"requester_system": _requester_system,
		"origin_region_id": _origin_region_id,
		"destination_region_id": _destination_region_id,
		"quantity": _quantity,
		"cargo_class": _cargo_class,
		"priority_class": _priority_class,
		"weight": _weight,
		"earliest_time": _earliest_time,
		"accepted_route": accepted_route(),
		"route_constraints": _route_constraints.duplicate(true),
	}
	if _has_latest_time:
		output["latest_time"] = _latest_time
	return output


static func _string_array_from_variant(value: Variant) -> Array[String]:
	if typeof(value) != TYPE_ARRAY:
		return []
	var output: Array[String] = []
	for raw_item: Variant in value as Array:
		if typeof(raw_item) != TYPE_STRING:
			return []
		output.append(raw_item as String)
	return output


static func _is_string_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for raw_item: Variant in value as Array:
		if typeof(raw_item) != TYPE_STRING or (raw_item as String).is_empty():
			return false
	return true


static func _parse_positive_finite(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized > 0.0 else -1.0


static func _parse_integer(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var normalized: float = float(value)
		if is_finite(normalized) and normalized == floor(normalized):
			return int(normalized)
	return -1


static func _parse_time(value: Variant) -> int:
	var normalized: int = _parse_integer(value)
	return normalized if normalized >= 0 and normalized <= MAX_JSON_SAFE_INTEGER else -1


static func _is_valid_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH:
		return false
	for character_index: int in value.length():
		if value.substr(character_index, 1).unicode_at(0) < 32:
			return false
	return true


static func _round_quantity(value: float) -> float:
	return snappedf(value, 0.000001)
