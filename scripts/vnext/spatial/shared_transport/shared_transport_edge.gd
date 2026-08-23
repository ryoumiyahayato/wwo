class_name VNextSharedTransportEdge
extends RefCounted
## One physical transport edge in the Spatial-owned network.
##
## `directional = false` means the physical segment is traversable in either
## direction. Capacity is shared by both directions for such an edge.

const CAPACITY_EPSILON: float = 0.000001
const MAX_ID_LENGTH: int = 256
const DEFAULT_BASE_COST_BY_MODE: Dictionary = {
	"road": 3.0,
	"rail": 1.0,
	"shipping": 2.0,
}

var _configured: bool = false
var _edge_id: String = ""
var _from_region_id: String = ""
var _to_region_id: String = ""
var _mode: String = ""
var _capacity_per_period: float = 0.0
var _travel_time: float = 0.0
var _enabled: bool = true
var _disruption_multiplier: float = 1.0
var _directional: bool = false
var _base_transport_cost: float = 0.0


static func create(
	edge_id_value: String,
	from_region_id_value: String,
	to_region_id_value: String,
	mode_value: String,
	capacity_per_period_value: Variant,
	travel_time_value: Variant,
	enabled_value: bool = true,
	disruption_multiplier_value: Variant = 1.0,
	directional_value: bool = false,
	base_transport_cost_value: Variant = null
) -> VNextSharedTransportEdge:
	var edge := VNextSharedTransportEdge.new()
	if not edge.configure(
		edge_id_value,
		from_region_id_value,
		to_region_id_value,
		mode_value,
		capacity_per_period_value,
		travel_time_value,
		enabled_value,
		disruption_multiplier_value,
		directional_value,
		base_transport_cost_value
	):
		return null
	return edge


static func from_dictionary(value: Dictionary) -> VNextSharedTransportEdge:
	if value.is_empty():
		return null
	var edge_id_value: Variant = value.get("edge_id", value.get("id", null))
	var from_value: Variant = value.get(
		"from", value.get("from_region_id", value.get("from_map_id", null))
	)
	var to_value: Variant = value.get(
		"to", value.get("to_region_id", value.get("to_map_id", null))
	)
	var mode_value: Variant = value.get("mode", value.get("link_type", null))
	if (
		typeof(edge_id_value) != TYPE_STRING
		or typeof(from_value) != TYPE_STRING
		or typeof(to_value) != TYPE_STRING
		or typeof(mode_value) != TYPE_STRING
	):
		return null
	var edge := VNextSharedTransportEdge.new()
	var base_cost: Variant = value.get("base_transport_cost", null)
	var directional: bool = false
	if value.has("directional"):
		if typeof(value.get("directional")) != TYPE_BOOL:
			return null
		directional = bool(value.get("directional"))
	elif value.has("bidirectional"):
		if typeof(value.get("bidirectional")) != TYPE_BOOL:
			return null
		directional = not bool(value.get("bidirectional"))
	var enabled: bool = true
	if value.has("enabled"):
		if typeof(value.get("enabled")) != TYPE_BOOL:
			return null
		enabled = bool(value.get("enabled"))
	if not edge.configure(
		edge_id_value as String,
		from_value as String,
		to_value as String,
		mode_value as String,
		value.get("capacity_per_period", value.get("capacity", -1.0)),
		value.get("travel_time", -1.0),
		enabled,
		value.get("disruption_multiplier", 1.0),
		directional,
		base_cost
	):
		return null
	return edge


func configure(
	edge_id_value: String,
	from_region_id_value: String,
	to_region_id_value: String,
	mode_value: String,
	capacity_per_period_value: Variant,
	travel_time_value: Variant,
	enabled_value: bool = true,
	disruption_multiplier_value: Variant = 1.0,
	directional_value: bool = false,
	base_transport_cost_value: Variant = null
) -> bool:
	if _configured:
		return false
	var capacity: float = _parse_nonnegative_finite(capacity_per_period_value)
	var travel_time: float = _parse_nonnegative_finite(travel_time_value)
	var disruption_multiplier: float = _parse_multiplier(disruption_multiplier_value)
	if (
		not _is_valid_identifier(edge_id_value)
		or not _is_valid_identifier(from_region_id_value)
		or not _is_valid_identifier(to_region_id_value)
		or from_region_id_value == to_region_id_value
		or not _is_valid_identifier(mode_value)
		or capacity < 0.0
		or travel_time < 0.0
		or disruption_multiplier < 0.0
	):
		return false

	var base_cost: float = _default_base_cost(mode_value)
	if base_transport_cost_value != null:
		base_cost = _parse_nonnegative_finite(base_transport_cost_value)
	if base_cost < 0.0:
		return false

	_edge_id = edge_id_value
	_from_region_id = from_region_id_value
	_to_region_id = to_region_id_value
	_mode = mode_value
	_capacity_per_period = _round_capacity(capacity)
	_travel_time = _round_capacity(travel_time)
	_enabled = enabled_value
	_disruption_multiplier = _round_capacity(disruption_multiplier)
	_directional = directional_value
	_base_transport_cost = _round_capacity(base_cost)
	_configured = true
	return true


func is_valid() -> bool:
	return (
		_configured
		and _is_valid_identifier(_edge_id)
		and _is_valid_identifier(_from_region_id)
		and _is_valid_identifier(_to_region_id)
		and _from_region_id != _to_region_id
		and _is_valid_identifier(_mode)
		and is_finite(_capacity_per_period)
		and _capacity_per_period >= 0.0
		and is_finite(_travel_time)
		and _travel_time >= 0.0
		and is_finite(_disruption_multiplier)
		and _disruption_multiplier >= 0.0
		and _disruption_multiplier <= 1.0
		and is_finite(_base_transport_cost)
		and _base_transport_cost >= 0.0
	)


func edge_id() -> String:
	return _edge_id


func from_region_id() -> String:
	return _from_region_id


func to_region_id() -> String:
	return _to_region_id


func mode() -> String:
	return _mode


func capacity_per_period() -> float:
	return _capacity_per_period


func travel_time() -> float:
	return _travel_time


func enabled() -> bool:
	return _enabled


func disruption_multiplier() -> float:
	return _disruption_multiplier


func directional() -> bool:
	return _directional


func base_transport_cost() -> float:
	return _base_transport_cost


func effective_capacity() -> float:
	if not is_valid() or not _enabled:
		return 0.0
	return _round_capacity(_capacity_per_period * _disruption_multiplier)


func can_traverse_from(region_id: String) -> bool:
	if not is_valid() or not _enabled:
		return false
	if _directional:
		return region_id == _from_region_id
	return region_id == _from_region_id or region_id == _to_region_id


func next_region_from(region_id: String) -> String:
	if not can_traverse_from(region_id):
		return ""
	if region_id == _from_region_id:
		return _to_region_id
	return _from_region_id


func to_dictionary() -> Dictionary:
	return {
		"edge_id": _edge_id,
		"from": _from_region_id,
		"to": _to_region_id,
		"mode": _mode,
		"capacity_per_period": _capacity_per_period,
		"travel_time": _travel_time,
		"enabled": _enabled,
		"disruption_multiplier": _disruption_multiplier,
		"directional": _directional,
		"base_transport_cost": _base_transport_cost,
	}


static func _default_base_cost(mode_value: String) -> float:
	return float(DEFAULT_BASE_COST_BY_MODE.get(mode_value, 4.0))


static func _parse_nonnegative_finite(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized >= 0.0 else -1.0


static func _parse_multiplier(value: Variant) -> float:
	var normalized: float = _parse_nonnegative_finite(value)
	return normalized if normalized >= 0.0 and normalized <= 1.0 else -1.0


static func _is_valid_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH:
		return false
	for character_index: int in value.length():
		if value.substr(character_index, 1).unicode_at(0) < 32:
			return false
	return true


static func _round_capacity(value: float) -> float:
	return snappedf(value, CAPACITY_EPSILON)
