class_name VNextSpatialSharedTransportTopology
extends RefCounted
## Read-only bridge from existing Spatial topology to the generic transport
## allocator. It creates no map data and owns no dynamic infrastructure state.

const CAPACITY_EPSILON: float = 0.000001
const DEFAULT_TRAVEL_TIME_BY_MODE: Dictionary = {
	"road": 1.0,
	"rail": 1.0,
	"shipping": 1.0,
}

var _edges_by_id: Dictionary = {}


static func from_edges(edge_values: Array) -> VNextSpatialSharedTransportTopology:
	var topology := VNextSpatialSharedTransportTopology.new()
	if not topology._configure_edges(edge_values):
		return null
	return topology


static func from_spatial_world(
	world: VNextSpatialWorld,
	travel_time_by_mode: Dictionary = {}
) -> VNextSpatialSharedTransportTopology:
	if world == null or not world.is_valid() or world.catalog() == null:
		return null
	var records: Array[VNextSharedTransportEdge] = []
	for link: Dictionary in world.catalog().links():
		var link_id: String = str(link.get("link_id", ""))
		var state: Dictionary = world.infrastructure_state(link_id)
		if state.is_empty():
			return null
		var nominal_capacity: float = float(state.get("nominal_capacity", -1.0))
		var effective_capacity: float = float(state.get("effective_capacity", -1.0))
		if (
			not is_finite(nominal_capacity)
			or nominal_capacity < 0.0
			or not is_finite(effective_capacity)
			or effective_capacity < 0.0
		):
			return null
		var multiplier: float = 0.0
		if nominal_capacity > CAPACITY_EPSILON:
			multiplier = clampf(effective_capacity / nominal_capacity, 0.0, 1.0)
		var status: String = str(state.get("status", ""))
		var enabled: bool = not _is_unavailable_status(status)
		var mode: String = str(link.get("link_type", ""))
		var travel_time: float = _physical_value(
			link, "travel_time", travel_time_by_mode, DEFAULT_TRAVEL_TIME_BY_MODE.get(mode, 1.0)
		)
		var edge := VNextSharedTransportEdge.create(
			link_id,
			str(link.get("from_map_id", "")),
			str(link.get("to_map_id", "")),
			mode,
			nominal_capacity,
			travel_time,
			enabled,
			multiplier,
			bool(link.get("directional", false)),
			link.get("base_transport_cost", null)
		)
		if edge == null:
			return null
		records.append(edge)
	return from_edges(records)


static func from_spatial_catalog(
	catalog: VNextSpatialCatalog,
	capacity_by_mode: Dictionary,
	travel_time_by_mode: Dictionary = {}
) -> VNextSpatialSharedTransportTopology:
	if catalog == null or not catalog.is_loaded():
		return null
	var records: Array[VNextSharedTransportEdge] = []
	for link: Dictionary in catalog.links():
		var mode: String = str(link.get("link_type", ""))
		if not capacity_by_mode.has(mode):
			return null
		var travel_time: float = _physical_value(
			link, "travel_time", travel_time_by_mode, DEFAULT_TRAVEL_TIME_BY_MODE.get(mode, 1.0)
		)
		var edge := VNextSharedTransportEdge.create(
			str(link.get("link_id", "")),
			str(link.get("from_map_id", "")),
			str(link.get("to_map_id", "")),
			mode,
			capacity_by_mode.get(mode, -1.0),
			travel_time,
			true,
			1.0,
			bool(link.get("directional", false)),
			link.get("base_transport_cost", null)
		)
		if edge == null:
			return null
		records.append(edge)
	return from_edges(records)


func is_valid() -> bool:
	if _edges_by_id.is_empty():
		return false
	for edge_id: String in edge_ids():
		var edge: VNextSharedTransportEdge = _edges_by_id.get(edge_id)
		if edge == null or not edge.is_valid() or edge.edge_id() != edge_id:
			return false
	return true


func edge_ids() -> Array[String]:
	var output: Array[String] = []
	for key: Variant in _edges_by_id.keys():
		output.append(str(key))
	output.sort()
	return output


func edge(edge_id: String) -> VNextSharedTransportEdge:
	var value: Variant = _edges_by_id.get(edge_id)
	return value as VNextSharedTransportEdge if value is VNextSharedTransportEdge else null


func edges() -> Array[VNextSharedTransportEdge]:
	var output: Array[VNextSharedTransportEdge] = []
	for edge_id: String in edge_ids():
		output.append(_edges_by_id[edge_id] as VNextSharedTransportEdge)
	return output


func edge_records() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for edge_id: String in edge_ids():
		output.append((_edges_by_id[edge_id] as VNextSharedTransportEdge).to_dictionary())
	return output


func _configure_edges(edge_values: Array) -> bool:
	if not _edges_by_id.is_empty() or edge_values.is_empty():
		return false
	var candidate: Dictionary = {}
	for raw_edge: Variant in edge_values:
		var edge: VNextSharedTransportEdge = null
		if raw_edge is VNextSharedTransportEdge:
			edge = raw_edge as VNextSharedTransportEdge
		elif typeof(raw_edge) == TYPE_DICTIONARY:
			edge = VNextSharedTransportEdge.from_dictionary(raw_edge as Dictionary)
		if edge == null or not edge.is_valid() or candidate.has(edge.edge_id()):
			return false
		candidate[edge.edge_id()] = edge
	_edges_by_id = candidate
	return is_valid()


static func _physical_value(
	record: Dictionary,
	field_name: String,
	mode_values: Dictionary,
	default_value: Variant
) -> float:
	var value: Variant = record.get(field_name, mode_values.get(str(record.get("link_type", "")), default_value))
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return float(default_value)
	var normalized: float = float(value)
	return normalized if is_finite(normalized) and normalized >= 0.0 else float(default_value)


static func _is_unavailable_status(status: String) -> bool:
	return status == VNextInfrastructureLinkState.STATUS_CONSTRUCTION \
		or status == VNextInfrastructureLinkState.STATUS_INTERRUPTED \
		or status == VNextInfrastructureLinkState.STATUS_DESTROYED
