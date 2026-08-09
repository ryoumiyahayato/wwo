class_name VNextTravelQuote
extends RefCounted

var _origin_place_id: String = ""
var _destination_place_id: String = ""
var _duration_minutes: int = 0
var _cost_minor: int = 0


func configure(
	origin_place_id_value: Variant,
	destination_place_id_value: Variant,
	duration_minutes_value: Variant,
	cost_minor_value: Variant
) -> bool:
	if typeof(origin_place_id_value) != TYPE_STRING:
		return false
	if typeof(destination_place_id_value) != TYPE_STRING:
		return false
	if typeof(duration_minutes_value) != TYPE_INT:
		return false
	if typeof(cost_minor_value) != TYPE_INT:
		return false

	var candidate_origin: String = origin_place_id_value as String
	var candidate_destination: String = destination_place_id_value as String
	var candidate_duration: int = int(duration_minutes_value)
	var candidate_cost: int = int(cost_minor_value)
	if not _is_place_id(candidate_origin) or not _is_place_id(candidate_destination):
		return false
	if candidate_origin == candidate_destination:
		return false
	if candidate_duration <= 0:
		return false
	if candidate_cost < 0:
		return false

	_origin_place_id = candidate_origin
	_destination_place_id = candidate_destination
	_duration_minutes = candidate_duration
	_cost_minor = candidate_cost
	return true


func origin_place_id() -> String:
	return _origin_place_id


func destination_place_id() -> String:
	return _destination_place_id


func duration_minutes() -> int:
	return _duration_minutes


func cost_minor() -> int:
	return _cost_minor


func is_valid() -> bool:
	return (
		_is_place_id(_origin_place_id)
		and _is_place_id(_destination_place_id)
		and _origin_place_id != _destination_place_id
		and _duration_minutes > 0
		and _cost_minor >= 0
	)


func as_dictionary() -> Dictionary:
	return {
		"origin_place_id": _origin_place_id,
		"destination_place_id": _destination_place_id,
		"duration_minutes": _duration_minutes,
		"cost_minor": _cost_minor,
	}


static func _is_place_id(candidate_value: String) -> bool:
	return VNextStableId.is_valid(candidate_value) and VNextStableId.kind_of(candidate_value) == "place"
