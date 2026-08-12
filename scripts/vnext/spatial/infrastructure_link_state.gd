class_name VNextInfrastructureLinkState
extends RefCounted
## Dynamic state for one catalog link.
## Status carries semantic availability; condition is only a bounded physical
## multiplier and is not a replacement for status.

const STATUS_OPERATIONAL: String = "operational"
const STATUS_CONSTRUCTION: String = "construction"
const STATUS_DAMAGED: String = "damaged"
const STATUS_INTERRUPTED: String = "interrupted"
const STATUS_DESTROYED: String = "destroyed"
const STATUS_REPAIRING: String = "repairing"
const STATUS_RESTORED: String = "restored"

const CONDITION_MIN: float = 0.0
const CONDITION_MAX: float = 1.0
const CAPACITY_EPSILON: float = 0.000001

var _link_id: String = ""
var _link_type: String = ""
var _status: String = STATUS_OPERATIONAL
var _nominal_capacity: float = 0.0
var _condition: float = CONDITION_MAX


static func supported_statuses() -> PackedStringArray:
	return PackedStringArray([
		STATUS_OPERATIONAL,
		STATUS_CONSTRUCTION,
		STATUS_DAMAGED,
		STATUS_INTERRUPTED,
		STATUS_DESTROYED,
		STATUS_REPAIRING,
		STATUS_RESTORED,
	])


static func is_valid_status(candidate: String) -> bool:
	return supported_statuses().has(candidate)


func configure(
	link_id_value: String,
	link_type_value: String,
	nominal_capacity_value: Variant,
	status_value: String = STATUS_OPERATIONAL,
	condition_value: Variant = CONDITION_MAX
) -> bool:
	var nominal_capacity: float = _parse_nonnegative_finite(nominal_capacity_value)
	var condition: float = _parse_condition(condition_value)
	if not VNextSpatialCatalog.is_valid_map_id(link_id_value):
		return false
	if not _is_supported_link_type(link_type_value):
		return false
	if nominal_capacity < 0.0 or condition < CONDITION_MIN:
		return false
	if not is_valid_status(status_value):
		return false

	_link_id = link_id_value
	_link_type = link_type_value
	_nominal_capacity = _round_capacity(nominal_capacity)
	_condition = condition
	_status = status_value
	return true


func is_valid() -> bool:
	return (
		VNextSpatialCatalog.is_valid_map_id(_link_id)
		and _is_supported_link_type(_link_type)
		and is_valid_status(_status)
		and is_finite(_nominal_capacity)
		and _nominal_capacity >= 0.0
		and is_finite(_condition)
		and _condition >= CONDITION_MIN
		and _condition <= CONDITION_MAX
	)


func link_id() -> String:
	return _link_id


func link_type() -> String:
	return _link_type


func status() -> String:
	return _status


func nominal_capacity() -> float:
	return _nominal_capacity


func condition() -> float:
	return _condition


func effective_capacity() -> float:
	if not is_valid():
		return 0.0
	return _round_capacity(
		_nominal_capacity * _status_capacity_factor(_status) * _condition
	)


func set_status(status_value: String) -> bool:
	if not is_valid() or not is_valid_status(status_value):
		return false
	_status = status_value
	return true


func set_nominal_capacity(nominal_capacity_value: Variant) -> bool:
	if not is_valid():
		return false
	var nominal_capacity: float = _parse_nonnegative_finite(nominal_capacity_value)
	if nominal_capacity < 0.0:
		return false
	_nominal_capacity = _round_capacity(nominal_capacity)
	return true


func set_condition(condition_value: Variant) -> bool:
	if not is_valid():
		return false
	var condition: float = _parse_condition(condition_value)
	if condition < CONDITION_MIN:
		return false
	_condition = condition
	return true


func snapshot() -> Dictionary:
	return {
		"link_id": _link_id,
		"link_type": _link_type,
		"status": _status,
		"nominal_capacity": _nominal_capacity,
		"condition": _condition,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 5:
		return false
	for required_field: String in [
		"link_id", "link_type", "status", "nominal_capacity", "condition",
	]:
		if not snapshot_value.has(required_field):
			return false
	var link_id_value: Variant = snapshot_value.get("link_id")
	var link_type_value: Variant = snapshot_value.get("link_type")
	var status_value: Variant = snapshot_value.get("status")
	if (
		typeof(link_id_value) != TYPE_STRING
		or typeof(link_type_value) != TYPE_STRING
		or typeof(status_value) != TYPE_STRING
	):
		return false
	var nominal_capacity: float = _parse_nonnegative_finite(
		snapshot_value.get("nominal_capacity")
	)
	var condition: float = _parse_condition(snapshot_value.get("condition"))
	if nominal_capacity < 0.0 or condition < CONDITION_MIN:
		return false
	if not VNextSpatialCatalog.is_valid_map_id(link_id_value as String):
		return false
	if not _is_supported_link_type(link_type_value as String):
		return false
	if not is_valid_status(status_value as String):
		return false

	_link_id = link_id_value as String
	_link_type = link_type_value as String
	_status = status_value as String
	_nominal_capacity = _round_capacity(nominal_capacity)
	_condition = condition
	return true


static func _status_capacity_factor(status_value: String) -> float:
	match status_value:
		STATUS_OPERATIONAL, STATUS_RESTORED:
			return 1.0
		STATUS_DAMAGED:
			return 0.5
		STATUS_REPAIRING:
			return 0.75
		STATUS_CONSTRUCTION, STATUS_INTERRUPTED, STATUS_DESTROYED:
			return 0.0
	return 0.0


static func _is_supported_link_type(link_type_value: String) -> bool:
	return (
		link_type_value == VNextSpatialCatalog.LINK_TYPE_ROAD
		or link_type_value == VNextSpatialCatalog.LINK_TYPE_RAIL
		or link_type_value == VNextSpatialCatalog.LINK_TYPE_SHIPPING
	)


static func _parse_nonnegative_finite(candidate_value: Variant) -> float:
	if typeof(candidate_value) != TYPE_INT and typeof(candidate_value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(candidate_value)
	if not is_finite(normalized) or normalized < 0.0:
		return -1.0
	return normalized


static func _parse_condition(candidate_value: Variant) -> float:
	if typeof(candidate_value) != TYPE_INT and typeof(candidate_value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(candidate_value)
	if not is_finite(normalized):
		return -1.0
	if normalized < CONDITION_MIN or normalized > CONDITION_MAX:
		return -1.0
	return _round_capacity(normalized)


static func _round_capacity(value: float) -> float:
	return snappedf(value, CAPACITY_EPSILON)
