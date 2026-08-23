class_name VNextSpatialWorld
extends RefCounted
## Authoritative physical Spatial / Infrastructure fact layer.
## Political, administrative and military control are deliberately external.

const SNAPSHOT_SCHEMA_ID: String = "vnext_spatial_world_v2"
const LEGACY_SNAPSHOT_SCHEMA_ID: String = "vnext_spatial_world_v1"
const DEFAULT_NOMINAL_CAPACITY_BY_TYPE: Dictionary = {
	VNextSpatialCatalog.LINK_TYPE_ROAD: 100.0,
	VNextSpatialCatalog.LINK_TYPE_RAIL: 1000.0,
	VNextSpatialCatalog.LINK_TYPE_SHIPPING: 2000.0,
}

var _catalog: VNextSpatialCatalog = null
var _current_hour: int = 0
var _infrastructure: Dictionary = {}
var _capacity: VNextSpatialCapacityWindow = null


func _init(catalog_value: VNextSpatialCatalog = null) -> void:
	_catalog = catalog_value


static func create(catalog_value: VNextSpatialCatalog) -> VNextSpatialWorld:
	var world := VNextSpatialWorld.new()
	if not world.initialize(catalog_value):
		return null
	return world


static func create_from_legacy_world_map() -> VNextSpatialWorld:
	var catalog := VNextSpatialCatalog.new()
	if not catalog.load_legacy_world_map():
		return null
	return create(catalog)


func initialize(catalog_value: VNextSpatialCatalog) -> bool:
	if catalog_value == null or not catalog_value.is_loaded():
		return false
	var candidate_infrastructure: Dictionary = {}
	for link: Dictionary in catalog_value.links():
		var link_id: String = str(link.get("link_id", ""))
		var link_type: String = str(link.get("link_type", ""))
		var default_capacity: float = float(
			DEFAULT_NOMINAL_CAPACITY_BY_TYPE.get(link_type, -1.0)
		)
		var state := VNextInfrastructureLinkState.new()
		if not state.configure(link_id, link_type, default_capacity):
			return false
		candidate_infrastructure[link_id] = state

	var candidate_capacity := VNextSpatialCapacityWindow.new()
	if not candidate_capacity.initialize(catalog_value, candidate_infrastructure, 0):
		return false
	_catalog = catalog_value
	_current_hour = 0
	_infrastructure = candidate_infrastructure
	_capacity = candidate_capacity
	return _is_internal_state_valid()


func is_valid() -> bool:
	return _is_internal_state_valid()


func catalog() -> VNextSpatialCatalog:
	return _catalog


func current_hour() -> int:
	return _current_hour


func advance_to_hour(absolute_hour: int) -> bool:
	if not _is_internal_state_valid():
		return false
	if not _capacity.advance_to_hour(absolute_hour):
		return false
	_current_hour = _capacity.current_hour()
	return true


func advance_hours(elapsed_hours: int) -> bool:
	if not _is_internal_state_valid():
		return false
	if not _capacity.advance_hours(elapsed_hours):
		return false
	_current_hour = _capacity.current_hour()
	return true


func get_place(place_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_place(place_query)


func get_region(region_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_region(region_query)


func get_city(city_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_city(city_query)


func get_port(port_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_port(port_query)


func links_of_type(link_type: String) -> Array[Dictionary]:
	if _catalog == null:
		return []
	return _catalog.links_of_type(link_type)


func links_between(
	origin_query: String, destination_query: String, link_type: String = ""
) -> Array[Dictionary]:
	if _catalog == null:
		return []
	return _catalog.links_between(origin_query, destination_query, link_type)


func links_from(place_query: String, link_type: String = "") -> Array[Dictionary]:
	if _catalog == null:
		return []
	return _catalog.links_from(place_query, link_type)


func neighboring_place_ids(place_query: String, link_type: String = "") -> Array[String]:
	if _catalog == null:
		return []
	return _catalog.neighboring_place_ids(place_query, link_type)


func effective_capacity(link_id: String) -> float:
	# Allocation-independent physical query for routing/access consumers. This
	# reads the authoritative InfrastructureLinkState directly and never creates
	# a second capacity ledger.
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	return 0.0 if state == null else state.effective_capacity()


func infrastructure_state(link_id: String) -> Dictionary:
	if _catalog == null or not _infrastructure.has(link_id):
		return {}
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	if state == null:
		return {}
	var output: Dictionary = _catalog.get_link(link_id)
	output.merge(state.snapshot(), true)
	var capacity: Dictionary = _capacity.capacity_summary(link_id)
	output["effective_capacity"] = state.effective_capacity()
	output["used_capacity"] = float(capacity.get("used_capacity", 0.0))
	output["remaining_capacity"] = float(capacity.get("remaining_capacity", 0.0))
	return output


func set_infrastructure_status(link_id: String, status_value: String) -> bool:
	return _mutate_infrastructure(link_id, Callable(_state_for_link(link_id), "set_status").bind(status_value))


func set_infrastructure_condition(link_id: String, condition_value: Variant) -> bool:
	return _mutate_infrastructure(link_id, Callable(_state_for_link(link_id), "set_condition").bind(condition_value))


func set_nominal_capacity(link_id: String, capacity_value: Variant) -> bool:
	return _mutate_infrastructure(link_id, Callable(_state_for_link(link_id), "set_nominal_capacity").bind(capacity_value))


func restore_infrastructure(link_id: String) -> bool:
	if not set_infrastructure_condition(link_id, 1.0):
		return false
	return set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_RESTORED)


func request_capacity(
	request_id: String, link_id: String, window_hour: int, demand: Variant
) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world"}
	return _capacity.request_capacity(request_id, link_id, window_hour, demand)


func request_capacity_batch(request_values: Array[Dictionary]) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world", "results": {}}
	return _capacity.request_capacity_batch(request_values)


func reserve_capacity(
	request_id: String, link_id: String, window_hour: int, demand: Variant
) -> Dictionary:
	return request_capacity(request_id, link_id, window_hour, demand)


func cancel_capacity_request(request_id: String, link_id: String, window_hour: int) -> bool:
	return _capacity != null and _capacity.cancel_capacity_request(request_id, link_id, window_hour)


func reservation_result(request_id: String, link_id: String, window_hour: int) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world"}
	return _capacity.reservation_result(request_id, link_id, window_hour)


func reservation_results_batch(request_values: Array[Dictionary]) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world", "results": {}}
	return _capacity.reservation_results_batch(request_values)


func capacity_summary(link_id: String) -> Dictionary:
	if _capacity == null:
		return {}
	return _capacity.capacity_summary(link_id)


func used_capacity(link_id: String) -> float:
	return float(capacity_summary(link_id).get("used_capacity", 0.0))


func remaining_capacity(link_id: String) -> float:
	return float(capacity_summary(link_id).get("remaining_capacity", 0.0))


func snapshot() -> Dictionary:
	if not _is_internal_state_valid():
		return {}
	var infrastructure: Array[Dictionary] = []
	for link_id: String in _catalog.link_ids():
		infrastructure.append(_state_for_link(link_id).snapshot())
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"current_hour": _current_hour,
		"infrastructure": infrastructure,
		"capacity_window": _capacity.snapshot(),
	}


func restore(snapshot_value: Dictionary) -> bool:
	if not _is_internal_state_valid():
		return false
	var candidate_snapshot: Dictionary = snapshot_value.duplicate(true)
	if candidate_snapshot.get("schema_id") == LEGACY_SNAPSHOT_SCHEMA_ID:
		# Legacy controller rows are compatibility input only. Spatial deliberately
		# drops them rather than restoring cross-domain authority.
		if (
			candidate_snapshot.size() != 5
			or not candidate_snapshot.has("territories")
			or typeof(candidate_snapshot.get("territories")) != TYPE_ARRAY
			or not _legacy_control_rows_are_well_formed(
				candidate_snapshot.get("territories") as Array
			)
		):
			return false
		candidate_snapshot.erase("territories")
		candidate_snapshot["schema_id"] = SNAPSHOT_SCHEMA_ID
	if candidate_snapshot.size() != 4 or candidate_snapshot.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if not _has_fields(candidate_snapshot, [
		"schema_id", "current_hour", "infrastructure", "capacity_window",
	]):
		return false
	var candidate_hour: int = _parse_hour(candidate_snapshot.get("current_hour"))
	if candidate_hour < 0:
		return false
	if typeof(candidate_snapshot.get("infrastructure")) != TYPE_ARRAY:
		return false
	if typeof(candidate_snapshot.get("capacity_window")) != TYPE_DICTIONARY:
		return false

	var candidate_infrastructure: Dictionary = {}
	for raw_value: Variant in (candidate_snapshot.get("infrastructure") as Array):
		if typeof(raw_value) != TYPE_DICTIONARY:
			return false
		var state := VNextInfrastructureLinkState.new()
		if not state.restore(raw_value as Dictionary):
			return false
		var link_id: String = state.link_id()
		if candidate_infrastructure.has(link_id) or not _catalog.has_link(link_id):
			return false
		if str(_catalog.get_link(link_id).get("link_type", "")) != state.link_type():
			return false
		candidate_infrastructure[link_id] = state
	if candidate_infrastructure.size() != _catalog.link_ids().size():
		return false
	for link_id: String in _catalog.link_ids():
		if not candidate_infrastructure.has(link_id):
			return false

	var candidate := VNextSpatialWorld.new()
	candidate._catalog = _catalog
	candidate._current_hour = candidate_hour
	candidate._infrastructure = candidate_infrastructure
	candidate._capacity = VNextSpatialCapacityWindow.new()
	if not candidate._validate_infrastructure_collection():
		return false
	if not candidate._capacity.initialize(
		_catalog, candidate_infrastructure, candidate_hour
	):
		return false
	if not candidate._capacity.restore(candidate_snapshot.get("capacity_window") as Dictionary):
		return false
	if not candidate._is_internal_state_valid():
		return false

	_current_hour = candidate._current_hour
	_infrastructure = candidate._infrastructure
	_capacity = candidate._capacity
	return true


func _is_internal_state_valid() -> bool:
	if _catalog == null or not _catalog.is_loaded() or _capacity == null:
		return false
	if not _validate_infrastructure_collection():
		return false
	return _capacity.is_valid() and _capacity.current_hour() == _current_hour


func _validate_infrastructure_collection() -> bool:
	if _infrastructure.size() != _catalog.link_ids().size():
		return false
	for link_id: String in _catalog.link_ids():
		if not _infrastructure.has(link_id):
			return false
		var state: VNextInfrastructureLinkState = _state_for_link(link_id)
		if state == null or not state.is_valid():
			return false
		if str(_catalog.get_link(link_id).get("link_type", "")) != state.link_type():
			return false
	return true


func _legacy_control_rows_are_well_formed(rows: Array) -> bool:
	if rows.size() != _catalog.place_map_ids().size():
		return false
	var seen: Dictionary = {}
	for raw_row: Variant in rows:
		if not raw_row is Dictionary:
			return false
		var row := raw_row as Dictionary
		if row.size() != 5 or not _has_fields(row, [
			"entity_id", "entity_kind", "sovereign_owner_id",
			"administrative_parent_id", "military_controller_id",
		]) or not _all_string_fields(row, [
			"entity_id", "entity_kind", "sovereign_owner_id",
			"administrative_parent_id", "military_controller_id",
		]):
			return false
		var entity_id: String = str(row.get("entity_id", ""))
		if seen.has(entity_id) or not _catalog.has_place(entity_id):
			return false
		var place: Dictionary = _catalog.get_place(entity_id)
		if str(row.get("entity_kind", "")) != str(
			place.get("object_level", place.get("spatial_kind", ""))
		):
			return false
		if (
			not _catalog.has_country(str(row.get("sovereign_owner_id", "")))
			or not _catalog.has_country(str(row.get("military_controller_id", "")))
		):
			return false
		var parent_id: String = str(row.get("administrative_parent_id", ""))
		if not parent_id.is_empty() and not (
			_catalog.has_country(parent_id) or _catalog.has_region(parent_id)
		):
			return false
		if parent_id == entity_id:
			return false
		seen[entity_id] = true
	return true


func _mutate_infrastructure(link_id: String, mutation: Callable) -> bool:
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	if state == null or not mutation.is_valid():
		return false
	var before: Dictionary = state.snapshot()
	var mutation_result: Variant = mutation.call()
	if typeof(mutation_result) != TYPE_BOOL or not bool(mutation_result):
		return false
	_capacity._recompute_allocations()
	if _is_internal_state_valid():
		return true
	state.restore(before)
	_capacity._recompute_allocations()
	return false


func _state_for_link(link_id: String) -> VNextInfrastructureLinkState:
	var value: Variant = _infrastructure.get(link_id)
	if not value is VNextInfrastructureLinkState:
		return null
	return value as VNextInfrastructureLinkState


static func _parse_hour(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		var integer_hour: int = int(value)
		return integer_hour if integer_hour >= 0 and integer_hour <= 9_007_199_254_740_991 else -1
	if typeof(value) == TYPE_FLOAT:
		var float_hour: float = float(value)
		if not is_finite(float_hour) or float_hour != floor(float_hour):
			return -1
		var normalized_hour: int = int(float_hour)
		return normalized_hour if normalized_hour >= 0 and normalized_hour <= 9_007_199_254_740_991 else -1
	return -1


static func _has_fields(value: Dictionary, fields: Array[String]) -> bool:
	for field_name: String in fields:
		if not value.has(field_name):
			return false
	return true


static func _all_string_fields(value: Dictionary, fields: Array[String]) -> bool:
	for field_name: String in fields:
		if typeof(value.get(field_name)) != TYPE_STRING:
			return false
	return true
