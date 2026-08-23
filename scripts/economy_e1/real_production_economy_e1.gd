class_name RealProductionEconomyE1
extends RefCounted
## Phase E1 regional physical production core.
##
## This service is intentionally isolated from the current product entry and
## from FormalWorldEconomyService.  It owns only physical economic state.  A
## caller injects daily demand and labor snapshots; Spatial owns transport
## capacity and returns allocations before Economy dispatches a shipment.

const E1Numeric = preload("res://scripts/economy_e1/e1_numeric.gd")

const STATE_SCHEMA: String = "real_production_economy_e1_state_v1"
const CATALOG_SCHEMA: String = "real_production_economy_e1_catalog_v1"
const PHASE_UNCONFIGURED: String = "UNCONFIGURED"
const PHASE_READY: String = "READY"
const PHASE_WAITING_FOR_TRANSPORT: String = "WAITING_FOR_TRANSPORT"
const PHASE_ALLOCATED: String = "ALLOCATED"
const HISTORY_LIMIT: int = 64
const MAX_DIAGNOSTIC_ERRORS: int = 32
const PERSISTENT_STATE_FIELDS: Array[String] = [
	"catalog_identity", "cumulative_flows", "history", "industry_states",
	"known_request_ids", "known_shipment_ids", "last_day_index", "market_states",
	"next_shipment_sequence", "resource_states", "schema_id", "shipment_history", "shipments",
]
const MARKET_STATE_FIELDS: Array[String] = [
	"daily_metrics", "demand", "enabled", "fulfilled", "inventory", "last_flow",
	"market_id", "moving_average_daily_demand", "price", "region_id", "target_stock", "unmet",
]
const INDUSTRY_STATE_FIELDS: Array[String] = [
	"daily_metrics", "input_buffers", "input_satisfaction_bp", "labor_satisfaction_bp",
	"last_actual_output", "last_planned_output", "producer_id", "production_constraint_reason",
	"region_id", "utilization_bp",
]
const RESOURCE_STATE_FIELDS: Array[String] = ["available_quantity", "resource_id"]
const MARKET_DAILY_METRIC_FIELDS: Array[String] = [
	"arrivals", "demand_allocations", "household_system_consumed", "shortage_bp", "stock_pressure_bp",
]
const INDUSTRY_DAILY_METRIC_FIELDS: Array[String] = ["output", "process_inputs_consumed", "replenished"]
const DAILY_FLOW_FIELDS: Array[String] = [
	"arrivals", "closing_industry_buffers", "closing_market_inventory", "dispatched",
	"household_system_consumed", "losses", "moved_to_industry_buffers", "opening_industry_buffers",
	"opening_market_inventory", "process_inputs_consumed", "produced",
]
const HISTORY_FIELDS: Array[String] = [
	"arrivals", "day_index", "dispatched", "household_system_consumed", "in_transit_quantity",
	"phase", "process_inputs_consumed", "produced", "transport_allocated_quantity", "transport_requested_quantity",
]
const ACTIVE_SHIPMENT_FIELDS: Array[String] = [
	"arrival_day", "arrival_time", "commodity_id", "destination_region_id", "dispatch_day", "dispatch_time",
	"origin_region_id", "quantity", "request_id", "route_id", "shipment_id", "status", "transport_cost",
]
const DELIVERED_SHIPMENT_FIELDS: Array[String] = [
	"arrival_day", "arrival_time", "commodity_id", "delivered_day", "destination_region_id", "dispatch_day",
	"dispatch_time", "origin_region_id", "quantity", "request_id", "route_id", "shipment_id", "status", "transport_cost",
]

const DEFAULT_POLICIES: Dictionary = {
	"moving_average_days": 7,
	"target_stock_days": 7,
	"shortage_gain_bp": 600,
	"stock_gain_bp": 250,
	"maximum_daily_price_rise_bp": 1000,
	"maximum_daily_price_fall_bp": 500,
	"minimum_price_centimes": 1,
	"history_limit": HISTORY_LIMIT,
}

var initialization_error: String = ""

var _configured: bool = false
var _phase: String = PHASE_UNCONFIGURED
var _active_day_index: int = -1
var _last_day_index: int = -1
var _next_shipment_sequence: int = 1

var _policies: Dictionary = {}
var _catalog_identity: Dictionary = {}
var _commodities: Dictionary = {}
var _regions: Dictionary = {}
var _recipes: Dictionary = {}
var _producer_definitions: Dictionary = {}
var _resource_definitions: Dictionary = {}
var _market_states: Dictionary = {}
var _industry_states: Dictionary = {}
var _resource_states: Dictionary = {}

var _producer_ids: Array[String] = []
var _commodity_ids: Array[String] = []
var _region_ids: Array[String] = []

var _shipments: Array[Dictionary] = []
var _shipment_history: Array[Dictionary] = []
var _known_shipment_ids: Dictionary = {}
var _known_request_ids: Dictionary = {}
var _transport_requests: Array[Dictionary] = []
var _pending_allocations: Array[Dictionary] = []

var _initial_stock_by_commodity: Dictionary = {}
var _cumulative_flows: Dictionary = {}
var _history: Array[Dictionary] = []
var _last_summary: Dictionary = {}
var _daily_flow: Dictionary = {}
var _day_context: Dictionary = {}


func configure(configuration: Dictionary) -> bool:
	if _phase != PHASE_UNCONFIGURED and _phase != PHASE_READY:
		initialization_error = "configure requires UNCONFIGURED or READY, got %s" % _phase
		return false
	var built: Dictionary = _build_configuration(configuration)
	if not bool(built.get("success", false)):
		initialization_error = str(built.get("message", "invalid E1 configuration"))
		return false
	var data: Dictionary = built.get("data", {}) as Dictionary
	_commodities = data.get("commodities", {}) as Dictionary
	_regions = data.get("regions", {}) as Dictionary
	_recipes = data.get("recipes", {}) as Dictionary
	_producer_definitions = data.get("producer_definitions", {}) as Dictionary
	_resource_definitions = data.get("resource_definitions", {}) as Dictionary
	_market_states = data.get("market_states", {}) as Dictionary
	_industry_states = data.get("industry_states", {}) as Dictionary
	_resource_states = data.get("resource_states", {}) as Dictionary
	_initial_stock_by_commodity = data.get("initial_stock", {}) as Dictionary
	_cumulative_flows = data.get("cumulative_flows", {}) as Dictionary
	_policies = data.get("policies", {}) as Dictionary
	_catalog_identity = data.get("catalog_identity", {}) as Dictionary
	_commodity_ids = data.get("commodity_ids", []) as Array[String]
	_region_ids = data.get("region_ids", []) as Array[String]
	_producer_ids = data.get("producer_ids", []) as Array[String]
	_shipments.clear()
	_shipment_history.clear()
	_known_shipment_ids.clear()
	_known_request_ids.clear()
	_transport_requests.clear()
	_pending_allocations.clear()
	_history.clear()
	_last_summary.clear()
	_daily_flow.clear()
	_day_context.clear()
	_active_day_index = -1
	_last_day_index = -1
	_next_shipment_sequence = 1
	_phase = PHASE_READY
	_configured = true
	initialization_error = ""
	return true


func prepare_day(
	day_index: int,
	demand_snapshot: Array[Dictionary],
	labor_snapshot: Array[Dictionary],
	transport_intents: Array[Dictionary] = []
) -> Dictionary:
	if not _configured:
		return _fail_result("not_configured", "E1 is not configured")
	if _phase != PHASE_READY:
		return _fail_result("invalid_call_order", "prepare_day requires READY, got %s" % _phase)
	if day_index != _last_day_index + 1:
		return _fail_result(
			"non_sequential_day",
			"prepare_day expected day %d, got %d" % [_last_day_index + 1, day_index]
		)
	var preflight: Dictionary = validate_state()
	if not bool(preflight.get("success", false)):
		return _fail_result("state_invariant_failed", str(preflight.get("message", "state invalid before settlement")))
	var normalized_demand: Dictionary = _normalize_demand_snapshot(demand_snapshot)
	if not bool(normalized_demand.get("success", false)):
		return normalized_demand
	var normalized_labor: Dictionary = _normalize_labor_snapshot(labor_snapshot)
	if not bool(normalized_labor.get("success", false)):
		return normalized_labor
	var normalized_intents: Dictionary = _normalize_transport_intents(
		transport_intents, day_index
	)
	if not bool(normalized_intents.get("success", false)):
		return normalized_intents

	_day_context = {
		"day_index": day_index,
		"demand_snapshot": normalized_demand.get("data", []) as Array,
		"labor_snapshot": normalized_labor.get("data", []) as Array,
		"labor_remaining": _labor_remaining(normalized_labor.get("data", []) as Array),
		"demand_records": [],
		"transport_intents": normalized_intents.get("data", []) as Array,
		"transport_allocated": [],
	}
	_active_day_index = day_index
	_daily_flow = _new_daily_flow()
	_reset_daily_state()
	_deliver_due_shipments(day_index)
	_run_production()
	_collect_demands()
	_clear_local_markets()
	_update_prices()
	_build_transport_requests()
	_phase = PHASE_WAITING_FOR_TRANSPORT
	return _ok({
		"day_index": day_index,
		"phase": _phase,
		"transport_requests": _copy_dictionary_array(_transport_requests),
		"summary": _build_day_summary(),
	})


func get_transport_requests() -> Dictionary:
	if _phase != PHASE_WAITING_FOR_TRANSPORT:
		return _fail_result(
			"invalid_call_order",
			"get_transport_requests requires WAITING_FOR_TRANSPORT, got %s" % _phase
		)
	return _ok({"requests": _copy_dictionary_array(_transport_requests)})


func apply_transport_allocations(allocations: Array[Dictionary]) -> Dictionary:
	if _phase != PHASE_WAITING_FOR_TRANSPORT:
		return _fail_result(
			"invalid_call_order",
			"apply_transport_allocations requires WAITING_FOR_TRANSPORT, got %s" % _phase
		)
	var normalized: Dictionary = _normalize_transport_allocations(allocations)
	if not bool(normalized.get("success", false)):
		return normalized
	var candidate_allocations: Array = normalized.get("data", []) as Array
	var request_by_id: Dictionary = {}
	for request: Dictionary in _transport_requests:
		request_by_id[str(request.get("request_id", ""))] = request
	var source_totals: Dictionary = {}
	for allocation: Dictionary in candidate_allocations:
		var request_id: String = str(allocation.get("request_id", ""))
		var request: Dictionary = request_by_id.get(request_id, {}) as Dictionary
		if request.is_empty():
			return _fail_result("unknown_transport_request", "allocation references unknown request %s" % request_id)
		var requested: int = int(request.get("requested_quantity", 0))
		var allocated: int = int(allocation.get("allocated_quantity", 0))
		if allocated <= 0 or allocated > requested:
			return _fail_result(
				"invalid_transport_allocation",
				"allocation for %s exceeds its request" % request_id
			)
		if int(request.get("earliest_dispatch", _active_day_index)) > _active_day_index:
			return _fail_result(
				"transport_not_yet_dispatchable",
				"allocation for %s arrives before earliest dispatch" % request_id
			)
		var source_key: String = _flow_key(
				str(request.get("origin_region_id", "")),
				str(request.get("commodity_id", ""))
			)
		var source_total: int = int(source_totals.get(source_key, 0)) + allocated
		source_totals[source_key] = source_total
	var source_key_ids: Array[String] = E1Numeric.sorted_string_keys(source_totals)
	for source_key: String in source_key_ids:
		var split: PackedStringArray = source_key.split("\u001f")
		if split.size() != 2:
			return _fail_result("invalid_transport_allocation", "invalid source key")
		var origin_inventory: int = _market_inventory(split[0], split[1])
		if int(source_totals[source_key]) > origin_inventory:
			return _fail_result(
				"origin_inventory_missing",
				"allocation for %s exceeds origin market inventory" % source_key
			)

	for allocation: Dictionary in candidate_allocations:
		var request_id: String = str(allocation.get("request_id", ""))
		var request: Dictionary = request_by_id[request_id] as Dictionary
		var origin_id: String = str(request.get("origin_region_id", ""))
		var destination_id: String = str(request.get("destination_region_id", ""))
		var commodity_id: String = str(request.get("commodity_id", ""))
		var quantity: int = int(allocation.get("allocated_quantity", 0))
		_set_market_inventory(
			origin_id,
			commodity_id,
			_market_inventory(origin_id, commodity_id) - quantity
		)
		_flow_add(origin_id, commodity_id, "dispatched", quantity)
		var shipment_id: String = "shipment:e1:%08d" % _next_shipment_sequence
		_next_shipment_sequence += 1
		while _known_shipment_ids.has(shipment_id):
			shipment_id = "shipment:e1:%08d" % _next_shipment_sequence
			_next_shipment_sequence += 1
		var dispatch_day: int = _active_day_index
		var duration_days: int = int(allocation.get("duration", 0))
		var shipment: Dictionary = {
			"shipment_id": shipment_id,
			"origin_region_id": origin_id,
			"destination_region_id": destination_id,
			"commodity_id": commodity_id,
			"quantity": quantity,
			"dispatch_time": dispatch_day,
			"arrival_time": dispatch_day + duration_days,
			"dispatch_day": dispatch_day,
			"arrival_day": dispatch_day + duration_days,
			"transport_cost": int(allocation.get("transport_cost", 0)),
			"route_id": str(allocation.get("route_id", "")),
			"request_id": request_id,
			"status": "in_transit",
		}
		_shipments.append(shipment)
		_known_shipment_ids[shipment_id] = true
		_pending_allocations.append(allocation.duplicate(true))
	_day_context["transport_allocated"] = _copy_dictionary_array(_pending_allocations)
	_transport_requests.sort_custom(_request_order)
	_phase = PHASE_ALLOCATED
	return _ok({
		"day_index": _active_day_index,
		"allocated": _copy_dictionary_array(_pending_allocations),
		"phase": _phase,
	})


func finalize_day() -> Dictionary:
	if _phase != PHASE_ALLOCATED:
		return _fail_result("invalid_call_order", "finalize_day requires ALLOCATED, got %s" % _phase)
	_close_daily_flow()
	var flow_validation: Dictionary = _validate_daily_flow()
	if not bool(flow_validation.get("success", false)):
		return flow_validation
	var state_validation: Dictionary = validate_state()
	if not bool(state_validation.get("success", false)):
		return _fail_result("state_invariant_failed", str(state_validation.get("message", "state invalid")))
	var summary: Dictionary = _build_day_summary()
	_history.append(summary.duplicate(true))
	var history_limit: int = int(_policies.get("history_limit", HISTORY_LIMIT))
	while _history.size() > maxi(1, history_limit):
		_history.pop_front()
	_last_summary = summary.duplicate(true)
	_last_day_index = _active_day_index
	_active_day_index = -1
	_phase = PHASE_READY
	_transport_requests.clear()
	_pending_allocations.clear()
	_day_context.clear()
	_daily_flow.clear()
	return _ok({"summary": summary, "phase": _phase})


func get_region_summary(region_id: String) -> Dictionary:
	if not _regions.has(region_id):
		return {}
	var market: Dictionary = _market_states[region_id] as Dictionary
	var industry_ids: Array[String] = []
	for producer_id: String in _producer_ids:
		if str((_producer_definitions[producer_id] as Dictionary).get("region_id", "")) == region_id:
			industry_ids.append(producer_id)
	return {
		"region_id": region_id,
		"market_id": str((_regions[region_id] as Dictionary).get("market_id", "")),
		"market": market.duplicate(true),
		"industry_ids": industry_ids,
		"in_transit_out": _transit_summary(region_id, true),
		"in_transit_in": _transit_summary(region_id, false),
	}


func get_market_state(region_id: String) -> Dictionary:
	return (_market_states.get(region_id, {}) as Dictionary).duplicate(true)


func get_industry_state(producer_id: String) -> Dictionary:
	return (_industry_states.get(producer_id, {}) as Dictionary).duplicate(true)


func get_persistent_state() -> Dictionary:
	if not _configured:
		return {}
	if _phase != PHASE_READY:
		initialization_error = "persistent state is available only at READY boundary"
		return {}
	var value: Dictionary = {
		"schema_id": STATE_SCHEMA,
		"catalog_identity": _catalog_identity.duplicate(true),
		"last_day_index": _last_day_index,
		"next_shipment_sequence": _next_shipment_sequence,
		"market_states": _market_states.duplicate(true),
		"industry_states": _industry_states.duplicate(true),
		"resource_states": _resource_states.duplicate(true),
		"shipments": _shipments.duplicate(true),
		"shipment_history": _shipment_history.duplicate(true),
		"history": _history.duplicate(true),
		"cumulative_flows": _cumulative_flows.duplicate(true),
		"known_request_ids": E1Numeric.sorted_string_keys(_known_request_ids),
		"known_shipment_ids": E1Numeric.sorted_string_keys(_known_shipment_ids),
	}
	return E1Numeric.canonicalize(value) as Dictionary


func restore_persistent_state(candidate: Dictionary) -> bool:
	if not _configured:
		initialization_error = "E1 is not configured"
		return false
	if _phase != PHASE_READY:
		initialization_error = "restore requires READY"
		return false
	var result: Dictionary = _validate_persistent_candidate(candidate)
	if not bool(result.get("success", false)):
		initialization_error = str(result.get("message", "invalid persistent state"))
		return false
	var data: Dictionary = result.get("data", {}) as Dictionary
	_market_states = data.get("market_states", {}) as Dictionary
	_industry_states = data.get("industry_states", {}) as Dictionary
	_resource_states = data.get("resource_states", {}) as Dictionary
	_shipments = data.get("shipments", []) as Array[Dictionary]
	_shipment_history = data.get("shipment_history", []) as Array[Dictionary]
	_history = data.get("history", []) as Array[Dictionary]
	_cumulative_flows = data.get("cumulative_flows", {}) as Dictionary
	_known_request_ids = data.get("known_request_ids", {}) as Dictionary
	_known_shipment_ids = data.get("known_shipment_ids", {}) as Dictionary
	_last_day_index = int(data.get("last_day_index", -1))
	_next_shipment_sequence = int(data.get("next_shipment_sequence", 1))
	_last_summary = _history.back().duplicate(true) if not _history.is_empty() else {}
	initialization_error = ""
	return true


func validate_state() -> Dictionary:
	if not _configured:
		return _fail_result("not_configured", "E1 is not configured")
	var errors: Array[String] = []
	var negative_count: int = _count_negative_state()
	if negative_count > 0:
		errors.append("negative physical quantity")
	var duplicate_delivery_count: int = _duplicate_delivery_count()
	if duplicate_delivery_count > 0:
		errors.append("duplicate shipment delivery")
	var drift_by_commodity: Dictionary = _global_physical_drift_by_commodity()
	var global_drift: int = _sum_drift(drift_by_commodity)
	var drift_count: int = _count_nonzero_drift(drift_by_commodity)
	if drift_count > 0:
		errors.append("unexplained physical drift: %d" % global_drift)
	var shipment_index: Dictionary = {}
	var shipment_boundary_day: int = maxi(_last_day_index, _active_day_index)
	for delivered: Dictionary in _shipment_history:
		if not _validate_delivered_shipment(delivered, shipment_index, shipment_boundary_day, _known_request_ids):
			errors.append("invalid delivered shipment")
	for shipment: Dictionary in _shipments:
		if not _validate_active_shipment(shipment, shipment_index, shipment_boundary_day, _known_request_ids):
			errors.append("invalid active shipment")
	for producer_id: String in _producer_ids:
		var state: Dictionary = _industry_states.get(producer_id, {}) as Dictionary
		if int(state.get("last_actual_output", 0)) > int(state.get("last_planned_output", 0)):
			errors.append("production exceeded plan for %s" % producer_id)
	var diagnostics: Dictionary = {
		"negative_inventory_count": negative_count,
		"unexplained_physical_drift_count": drift_count,
		"unexplained_physical_drift": global_drift,
		"unexplained_physical_drift_by_commodity": drift_by_commodity,
		"duplicate_shipment_delivery_count": duplicate_delivery_count,
		"demand_created_production_count": 0,
		"errors": errors.slice(0, MAX_DIAGNOSTIC_ERRORS),
	}
	if not errors.is_empty():
		return _fail_result("state_invariant_failed", "; ".join(errors.slice(0, MAX_DIAGNOSTIC_ERRORS)))
	return _ok(diagnostics)


func get_authoritative_state_summary() -> Dictionary:
	if _phase == PHASE_READY:
		return get_persistent_state()
	return E1Numeric.canonicalize({
		"schema_id": STATE_SCHEMA,
		"catalog_identity": _catalog_identity,
		"phase": _phase,
		"active_day_index": _active_day_index,
		"last_day_index": _last_day_index,
		"market_states": _market_states,
		"industry_states": _industry_states,
		"resource_states": _resource_states,
		"shipments": _shipments,
		"transport_requests": _transport_requests,
		"daily_flow": _daily_flow,
	}) as Dictionary


func get_authoritative_state_hash() -> String:
	return E1Numeric.sha256(get_authoritative_state_summary())


func get_phase() -> String:
	return _phase


func get_last_summary() -> Dictionary:
	return _last_summary.duplicate(true)


func get_history() -> Array[Dictionary]:
	return _history.duplicate(true)


func _build_configuration(configuration: Dictionary) -> Dictionary:
	var revision: String = str(configuration.get("catalog_revision", "")).strip_edges()
	if revision.is_empty():
		return _configuration_failure("catalog_revision is required")
	var raw_commodities: Variant = configuration.get("commodities", [])
	var raw_regions: Variant = configuration.get("regions", [])
	var raw_recipes: Variant = configuration.get("recipes", [])
	var raw_producers: Variant = configuration.get("producers", [])
	var raw_resources: Variant = configuration.get("resource_sources", [])
	if not raw_commodities is Array or not raw_regions is Array or not raw_recipes is Array or not raw_producers is Array:
		return _configuration_failure("catalog arrays are required")
	if not raw_resources is Array:
		return _configuration_failure("resource_sources must be an array")
	var commodities: Dictionary = {}
	for raw_value: Variant in raw_commodities as Array:
		if not raw_value is Dictionary:
			return _configuration_failure("commodity record is not a dictionary")
		var source: Dictionary = raw_value as Dictionary
		var commodity_id: String = str(source.get("commodity_id", "")).strip_edges()
		if commodity_id.is_empty() or commodities.has(commodity_id):
			return _configuration_failure("duplicate or empty commodity ID: %s" % commodity_id)
		var price: Dictionary = _as_int(source.get("base_price_centimes", 0), "base price", false)
		if not bool(price.get("success", false)):
			return _configuration_failure(str(price.get("message", "invalid commodity price")))
		var stock_days: Dictionary = _as_int(source.get("target_stock_days", DEFAULT_POLICIES["target_stock_days"]), "target stock days", true)
		if not bool(stock_days.get("success", false)):
			return _configuration_failure(str(stock_days.get("message", "invalid stock days")))
		var commodity: Dictionary = source.duplicate(true)
		commodity["commodity_id"] = commodity_id
		commodity["base_price_centimes"] = int(price["value"])
		commodity["target_stock_days"] = int(stock_days["value"])
		commodities[commodity_id] = commodity
	var commodity_ids: Array[String] = E1Numeric.sorted_string_keys(commodities)

	var regions: Dictionary = {}
	var market_ids: Dictionary = {}
	for raw_value: Variant in raw_regions as Array:
		if not raw_value is Dictionary:
			return _configuration_failure("economic region record is not a dictionary")
		var source: Dictionary = raw_value as Dictionary
		for forbidden: String in ["controller_id", "political_controller_id", "country_id", "sovereign_id", "owner_id", "political_owner_id"]:
			if source.has(forbidden):
				return _configuration_failure("economic region contains political fact: %s" % forbidden)
		var region_id: String = str(source.get("region_id", "")).strip_edges()
		var market_id: String = str(source.get("market_id", "")).strip_edges()
		if region_id.is_empty() or regions.has(region_id) or market_id.is_empty() or market_ids.has(market_id):
			return _configuration_failure("duplicate or empty economic region/market ID: %s" % region_id)
		var spatial_value: Variant = source.get("spatial_region_ids", [])
		if not spatial_value is Array or (spatial_value as Array).is_empty():
			return _configuration_failure("economic region %s needs spatial region references" % region_id)
		var spatial_ids: Array[String] = []
		for raw_spatial: Variant in spatial_value as Array:
			var spatial_id: String = str(raw_spatial).strip_edges()
			if spatial_id.is_empty() or spatial_ids.has(spatial_id):
				return _configuration_failure("invalid spatial reference in %s" % region_id)
			spatial_ids.append(spatial_id)
		spatial_ids.sort()
		var enabled: Variant = source.get("enabled", true)
		if not enabled is bool:
			return _configuration_failure("enabled must be bool for %s" % region_id)
		regions[region_id] = {
			"region_id": region_id,
			"spatial_region_ids": spatial_ids,
			"market_id": market_id,
			"enabled": bool(enabled),
		}
		market_ids[market_id] = true
	var region_ids: Array[String] = E1Numeric.sorted_string_keys(regions)

	var recipes: Dictionary = {}
	for raw_value: Variant in raw_recipes as Array:
		if not raw_value is Dictionary:
			return _configuration_failure("recipe record is not a dictionary")
		var source: Dictionary = raw_value as Dictionary
		var recipe_id: String = str(source.get("recipe_id", "")).strip_edges()
		var output_id: String = str(source.get("output_commodity_id", "")).strip_edges()
		if recipe_id.is_empty() or recipes.has(recipe_id) or not commodities.has(output_id):
			return _configuration_failure("invalid or duplicate recipe ID: %s" % recipe_id)
		var output_quantity: Dictionary = _as_int(source.get("output_quantity", 0), "output quantity", false)
		if not bool(output_quantity.get("success", false)):
			return _configuration_failure(str(output_quantity.get("message", "invalid output quantity")))
		var inputs_result: Dictionary = _normalize_requirements(source.get("inputs", []), commodities, "input")
		if not bool(inputs_result.get("success", false)):
			return _configuration_failure(str(inputs_result.get("message", "invalid recipe input")))
		var energy_result: Dictionary = _normalize_requirements(source.get("energy_requirements", []), commodities, "energy")
		if not bool(energy_result.get("success", false)):
			return _configuration_failure(str(energy_result.get("message", "invalid energy requirement")))
		var input_ids: Dictionary = {}
		for input_requirement: Dictionary in inputs_result.get("data", []) as Array:
			input_ids[str(input_requirement.get("commodity_id", ""))] = true
		for energy_requirement: Dictionary in energy_result.get("data", []) as Array:
			var energy_commodity_id: String = str(energy_requirement.get("commodity_id", ""))
			if input_ids.has(energy_commodity_id):
				return _configuration_failure(
					"recipe %s uses commodity %s in both inputs and energy_requirements" % [recipe_id, energy_commodity_id]
				)
		var labor_result: Dictionary = _normalize_labor_requirements(source.get("labor_requirements", []))
		if not bool(labor_result.get("success", false)):
			return _configuration_failure(str(labor_result.get("message", "invalid labor requirement")))
		var recipe: Dictionary = source.duplicate(true)
		recipe["recipe_id"] = recipe_id
		recipe["output_commodity_id"] = output_id
		recipe["output_quantity"] = int(output_quantity["value"])
		recipe["inputs"] = inputs_result.get("data", [])
		recipe["energy_requirements"] = energy_result.get("data", [])
		recipe["labor_requirements"] = labor_result.get("data", [])
		recipe["producer_type"] = str(source.get("producer_type", "industrial"))
		if not ["extractive", "agricultural", "industrial"].has(str(recipe["producer_type"])):
			return _configuration_failure("invalid producer type for recipe %s" % recipe_id)
		var byproducts: Dictionary = _normalize_optional_outputs(source.get("byproducts", []), commodities)
		if not bool(byproducts.get("success", false)):
			return _configuration_failure(str(byproducts.get("message", "invalid byproduct")))
		recipe["byproducts"] = byproducts.get("data", [])
		recipes[recipe_id] = recipe
	var recipe_ids: Array[String] = E1Numeric.sorted_string_keys(recipes)

	var resources: Dictionary = {}
	if raw_resources is Array:
		for raw_value: Variant in raw_resources as Array:
			if not raw_value is Dictionary:
				return _configuration_failure("resource source record is not a dictionary")
			var source: Dictionary = raw_value as Dictionary
			var resource_id: String = str(source.get("resource_id", "")).strip_edges()
			if resource_id.is_empty() or resources.has(resource_id):
				return _configuration_failure("duplicate or empty resource ID: %s" % resource_id)
			var available: Dictionary = _as_int(source.get("available_quantity", 0), "resource available quantity", true)
			var capacity: Dictionary = _as_int(source.get("extraction_capacity_per_day", 0), "resource extraction capacity", true)
			if not bool(available.get("success", false)) or not bool(capacity.get("success", false)):
				return _configuration_failure("invalid resource source %s" % resource_id)
			resources[resource_id] = {
				"resource_id": resource_id,
				"extraction_capacity_per_day": int(capacity["value"]),
				"initial_available_quantity": int(available["value"]),
			}
	var resource_states: Dictionary = {}
	for resource_id: String in E1Numeric.sorted_string_keys(resources):
		var resource_definition: Dictionary = resources[resource_id] as Dictionary
		resource_states[resource_id] = {
			"resource_id": resource_id,
			"available_quantity": int(resource_definition.get("initial_available_quantity", 0)),
		}

	var producers: Dictionary = {}
	for raw_value: Variant in raw_producers as Array:
		if not raw_value is Dictionary:
			return _configuration_failure("producer record is not a dictionary")
		var source: Dictionary = raw_value as Dictionary
		var producer_id: String = str(source.get("producer_id", "")).strip_edges()
		var region_id: String = str(source.get("region_id", "")).strip_edges()
		var recipe_id: String = str(source.get("recipe_id", "")).strip_edges()
		if producer_id.is_empty() or producers.has(producer_id) or not regions.has(region_id) or not recipes.has(recipe_id):
			return _configuration_failure("invalid or duplicate producer ID: %s" % producer_id)
		var capacity: Dictionary = _as_int(source.get("installed_capacity_per_day", 0), "installed capacity", true)
		var utilization: Dictionary = _as_int(source.get("initial_utilization_bp", 0), "initial utilization", true)
		var buffer_days: Dictionary = _as_int(source.get("input_buffer_target_days", 0), "input buffer target days", true)
		if not bool(capacity.get("success", false)) or not bool(utilization.get("success", false)) or not bool(buffer_days.get("success", false)):
			return _configuration_failure("invalid physical capacity fields for %s" % producer_id)
		if int(utilization["value"]) > E1Numeric.BASIS_POINTS:
			return _configuration_failure("utilization exceeds basis points for %s" % producer_id)
		var producer: Dictionary = source.duplicate(true)
		producer["producer_id"] = producer_id
		producer["region_id"] = region_id
		producer["recipe_id"] = recipe_id
		producer["installed_capacity_per_day"] = int(capacity["value"])
		producer["initial_utilization_bp"] = int(utilization["value"])
		producer["input_buffer_target_days"] = int(buffer_days["value"])
		var enabled: Variant = source.get("enabled", true)
		if not enabled is bool:
			return _configuration_failure("enabled must be bool for producer %s" % producer_id)
		producer["enabled"] = bool(enabled)
		var buffers_result: Dictionary = _normalize_quantity_map(source.get("initial_input_buffers", {}), commodities, "initial input buffer")
		if not bool(buffers_result.get("success", false)):
			return _configuration_failure(str(buffers_result.get("message", "invalid input buffer")))
		producer["initial_input_buffers"] = buffers_result.get("data", {})
		var producer_labor: Dictionary = _normalize_labor_requirements(source.get("labor_requirements", []))
		if not bool(producer_labor.get("success", false)):
			return _configuration_failure(str(producer_labor.get("message", "invalid producer labor")))
		producer["labor_requirements"] = producer_labor.get("data", [])
		var resource_id: String = str(source.get("resource_source_id", "")).strip_edges()
		if not resource_id.is_empty() and not resources.has(resource_id):
			return _configuration_failure("producer %s references unknown resource %s" % [producer_id, resource_id])
		producer["resource_source_id"] = resource_id
		var resource_ratio: Dictionary = _as_int(source.get("resource_quantity_per_output", 0), "resource quantity per output", true)
		var resource_capacity: Dictionary = _as_int(source.get("resource_capacity_per_day", 0), "producer resource capacity", true)
		if not bool(resource_ratio.get("success", false)) or not bool(resource_capacity.get("success", false)):
			return _configuration_failure("invalid resource constraint for %s" % producer_id)
		producer["resource_quantity_per_output"] = int(resource_ratio["value"])
		producer["resource_capacity_per_day"] = int(resource_capacity["value"])
		if not resource_id.is_empty() and int(resource_ratio["value"]) <= 0:
			return _configuration_failure("resource quantity per output must be positive for %s" % producer_id)
		producers[producer_id] = producer
	var producer_ids: Array[String] = E1Numeric.sorted_string_keys(producers)
	for producer_id: String in producer_ids:
		var producer: Dictionary = producers[producer_id] as Dictionary
		var recipe: Dictionary = recipes[str(producer.get("recipe_id", ""))] as Dictionary
		for requirement: Dictionary in _combined_requirements(recipe):
			if not (producer["initial_input_buffers"] as Dictionary).has(str(requirement.get("commodity_id", ""))):
				(producer["initial_input_buffers"] as Dictionary)[str(requirement.get("commodity_id", ""))] = 0

	var policies: Dictionary = DEFAULT_POLICIES.duplicate(true)
	var policy_value: Variant = configuration.get("policies", {})
	if policy_value is Dictionary:
		for raw_key: Variant in policy_value as Dictionary:
			var key: String = str(raw_key)
			var parsed: Dictionary = _as_int((policy_value as Dictionary)[raw_key], "policy %s" % key, true)
			if not bool(parsed.get("success", false)):
				return _configuration_failure(str(parsed.get("message", "invalid policy")))
			policies[key] = int(parsed["value"])
	if int(policies.get("moving_average_days", 0)) <= 0 or int(policies.get("minimum_price_centimes", 0)) <= 0:
		return _configuration_failure("moving average days and minimum price must be positive")
	if int(policies.get("maximum_daily_price_fall_bp", E1Numeric.BASIS_POINTS)) >= E1Numeric.BASIS_POINTS:
		return _configuration_failure("maximum daily price fall must keep a positive price multiplier")

	var market_states: Dictionary = {}
	for region_id: String in region_ids:
		var region: Dictionary = regions[region_id] as Dictionary
		var inventory: Dictionary = {}
		var prices: Dictionary = {}
		for commodity_id: String in commodity_ids:
			inventory[commodity_id] = 0
			prices[commodity_id] = int((commodities[commodity_id] as Dictionary).get("base_price_centimes", 1))
		market_states[region_id] = {
			"region_id": region_id,
			"market_id": str(region.get("market_id", "")),
			"enabled": bool(region.get("enabled", true)),
			"inventory": inventory,
			"price": prices,
			"demand": {},
			"fulfilled": {},
			"unmet": {},
			"moving_average_daily_demand": {},
			"target_stock": {},
			"last_flow": {},
			"daily_metrics": {},
		}
	var initial_inventory_value: Variant = configuration.get("initial_market_inventory", {})
	if not initial_inventory_value is Dictionary:
		return _configuration_failure("initial_market_inventory must be a dictionary")
	for raw_region_id: Variant in initial_inventory_value as Dictionary:
		var region_id: String = str(raw_region_id)
		if not market_states.has(region_id):
			return _configuration_failure("initial inventory references unknown region %s" % region_id)
		var region_inventory: Variant = (initial_inventory_value as Dictionary)[raw_region_id]
		if not region_inventory is Dictionary:
			return _configuration_failure("initial inventory for %s is not a dictionary" % region_id)
		for raw_commodity_id: Variant in region_inventory as Dictionary:
			var commodity_id: String = str(raw_commodity_id)
			if not commodities.has(commodity_id):
				return _configuration_failure("initial inventory references unknown commodity %s" % commodity_id)
			var quantity: Dictionary = _as_int((region_inventory as Dictionary)[raw_commodity_id], "initial inventory", true)
			if not bool(quantity.get("success", false)):
				return _configuration_failure(str(quantity.get("message", "invalid initial inventory")))
			((market_states[region_id] as Dictionary)["inventory"] as Dictionary)[commodity_id] = int(quantity["value"])

	var industry_states: Dictionary = {}
	for producer_id: String in producer_ids:
		var producer: Dictionary = producers[producer_id] as Dictionary
		var buffers: Dictionary = (producer.get("initial_input_buffers", {}) as Dictionary).duplicate(true)
		industry_states[producer_id] = {
			"producer_id": producer_id,
			"region_id": str(producer.get("region_id", "")),
			"utilization_bp": int(producer.get("initial_utilization_bp", 0)),
			"input_buffers": buffers,
			"last_planned_output": 0,
			"last_actual_output": 0,
			"labor_satisfaction_bp": E1Numeric.BASIS_POINTS,
			"input_satisfaction_bp": E1Numeric.BASIS_POINTS,
			"production_constraint_reason": "capacity",
			"daily_metrics": {},
		}
	var initial_stock: Dictionary = {}
	for commodity_id: String in commodity_ids:
		var quantity: int = 0
		for region_id: String in region_ids:
			quantity += int(((market_states[region_id] as Dictionary)["inventory"] as Dictionary).get(commodity_id, 0))
		for producer_id: String in producer_ids:
			quantity += int(((industry_states[producer_id] as Dictionary)["input_buffers"] as Dictionary).get(commodity_id, 0))
		initial_stock[commodity_id] = quantity
	var cumulative: Dictionary = _empty_cumulative_flows(commodity_ids)
	var catalog_producers: Array[Dictionary] = []
	for producer_id: String in producer_ids:
		var producer: Dictionary = producers[producer_id].duplicate(true) as Dictionary
		producer.erase("initial_input_buffers")
		catalog_producers.append(producer)
	var catalog_payload: Dictionary = {
		"schema_id": CATALOG_SCHEMA,
		"catalog_revision": revision,
		"commodities": _dictionary_values(commodities, commodity_ids),
		"regions": _dictionary_values(regions, region_ids),
		"recipes": _dictionary_values(recipes, recipe_ids),
		"producers": catalog_producers,
		"resources": _dictionary_values(resources, E1Numeric.sorted_string_keys(resources)),
		"policies": policies,
	}
	var catalog_identity: Dictionary = {
		"schema_version": CATALOG_SCHEMA,
		"catalog_revision": revision,
		"catalog_hash": E1Numeric.sha256(catalog_payload),
	}
	return _ok({
		"commodities": commodities,
		"regions": regions,
		"recipes": recipes,
		"producer_definitions": producers,
		"resource_definitions": resources,
		"market_states": market_states,
		"industry_states": industry_states,
		"resource_states": resource_states,
		"initial_stock": initial_stock,
		"cumulative_flows": cumulative,
		"policies": policies,
		"catalog_identity": catalog_identity,
		"commodity_ids": commodity_ids,
		"region_ids": region_ids,
		"producer_ids": producer_ids,
	})


func _run_production() -> void:
	var labor_remaining: Dictionary = _day_context.get("labor_remaining", {}) as Dictionary
	for producer_id: String in _producer_ids:
		var producer: Dictionary = _producer_definitions[producer_id] as Dictionary
		var state: Dictionary = _industry_states[producer_id] as Dictionary
		var region_id: String = str(producer.get("region_id", ""))
		var region: Dictionary = _regions[region_id] as Dictionary
		var recipe: Dictionary = _recipes[str(producer.get("recipe_id", ""))] as Dictionary
		var enabled: bool = bool(producer.get("enabled", true)) and bool(region.get("enabled", true))
		var planned_output: int = 0
		if enabled:
			planned_output = E1Numeric.mul_div_floor(
				int(producer.get("installed_capacity_per_day", 0)),
				int(state.get("utilization_bp", 0)),
				E1Numeric.BASIS_POINTS
			)
		var actual_output: int = planned_output
		var limiting_reason: String = "capacity"
		var input_satisfaction: int = E1Numeric.BASIS_POINTS
		var labor_satisfaction: int = E1Numeric.BASIS_POINTS
		if not enabled:
			actual_output = 0
			limiting_reason = "disabled"
		else:
			var input_buffers: Dictionary = state.get("input_buffers", {}) as Dictionary
			for requirement: Dictionary in _combined_requirements(recipe):
				var commodity_id: String = str(requirement.get("commodity_id", ""))
				var ratio: int = int(requirement.get("quantity_per_output", 0))
				var available: int = int(input_buffers.get(commodity_id, 0))
				var max_from_input: int = E1Numeric.ratio_to_output(available, ratio)
				if planned_output > 0 and ratio > 0:
					input_satisfaction = mini(
						input_satisfaction,
						E1Numeric.mul_div_floor(
							available,
							E1Numeric.BASIS_POINTS,
							E1Numeric.required_from_output(planned_output, ratio)
						)
					)
				if max_from_input < actual_output:
					actual_output = max_from_input
					limiting_reason = "input:%s" % commodity_id
			var labor_requirements: Array[Dictionary] = _producer_labor_requirements(producer, recipe)
			for requirement: Dictionary in labor_requirements:
				var labor_class: String = str(requirement.get("labor_class", ""))
				var ratio: int = int(requirement.get("quantity_per_output", 0))
				var labor_key: String = _labor_key(region_id, labor_class)
				var available_labor: int = int(labor_remaining.get(labor_key, 0))
				var planned_labor: int = E1Numeric.required_from_output(planned_output, ratio)
				if planned_labor > 0:
					labor_satisfaction = mini(
						labor_satisfaction,
						E1Numeric.mul_div_floor(available_labor, E1Numeric.BASIS_POINTS, planned_labor)
					)
				var max_from_labor: int = E1Numeric.ratio_to_output(available_labor, ratio)
				if max_from_labor < actual_output:
					actual_output = max_from_labor
					limiting_reason = "labor"
			var resource_id: String = str(producer.get("resource_source_id", ""))
			if not resource_id.is_empty():
				var resource: Dictionary = _resource_states.get(resource_id, {}) as Dictionary
				var resource_ratio: int = int(producer.get("resource_quantity_per_output", 0))
				var resource_available: int = int(resource.get("available_quantity", 0))
				var resource_max: int = E1Numeric.ratio_to_output(resource_available, resource_ratio)
				var resource_definition: Dictionary = _resource_definitions.get(resource_id, {}) as Dictionary
				var source_extraction_capacity: int = int(resource_definition.get("extraction_capacity_per_day", 0))
				resource_max = mini(
					resource_max,
					E1Numeric.ratio_to_output(source_extraction_capacity, resource_ratio)
				)
				var producer_resource_capacity: int = int(producer.get("resource_capacity_per_day", 0))
				if producer_resource_capacity > 0:
					resource_max = mini(
						resource_max,
						E1Numeric.ratio_to_output(producer_resource_capacity, resource_ratio)
					)
				if resource_max < actual_output:
					actual_output = resource_max
					limiting_reason = "resource:%s" % resource_id
		actual_output = maxi(0, actual_output)

		var input_buffers: Dictionary = state.get("input_buffers", {}) as Dictionary
		var consumed_inputs: Dictionary = {}
		for requirement: Dictionary in _combined_requirements(recipe):
			var commodity_id: String = str(requirement.get("commodity_id", ""))
			var required: int = E1Numeric.required_from_output(
				actual_output, int(requirement.get("quantity_per_output", 0))
			)
			var available: int = int(input_buffers.get(commodity_id, 0))
			if required > available:
				initialization_error = "internal input underflow for %s" % producer_id
				return
			input_buffers[commodity_id] = available - required
			consumed_inputs[commodity_id] = required
			_flow_add(region_id, commodity_id, "process_inputs_consumed", required)
			_add_cumulative("process_inputs_consumed", commodity_id, required)
			var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
			var input_metric: Dictionary = metrics.get("process_inputs_consumed", {}) as Dictionary
			input_metric[commodity_id] = int(input_metric.get(commodity_id, 0)) + required
			metrics["process_inputs_consumed"] = input_metric
			state["daily_metrics"] = metrics

		for requirement: Dictionary in _producer_labor_requirements(producer, recipe):
			var labor_class: String = str(requirement.get("labor_class", ""))
			var labor_key: String = _labor_key(region_id, labor_class)
			var labor_used: int = E1Numeric.required_from_output(
				actual_output, int(requirement.get("quantity_per_output", 0))
			)
			labor_remaining[labor_key] = int(labor_remaining.get(labor_key, 0)) - labor_used
		var resource_id: String = str(producer.get("resource_source_id", ""))
		if not resource_id.is_empty():
			var resource: Dictionary = _resource_states[resource_id] as Dictionary
			var resource_used: int = E1Numeric.required_from_output(
				actual_output, int(producer.get("resource_quantity_per_output", 0))
			)
			resource["available_quantity"] = int(resource.get("available_quantity", 0)) - resource_used
			_resource_states[resource_id] = resource

		var output_commodity_id: String = str(recipe.get("output_commodity_id", ""))
		_add_market_inventory(region_id, output_commodity_id, actual_output)
		_flow_add(region_id, output_commodity_id, "produced", actual_output)
		_add_cumulative("produced", output_commodity_id, actual_output)
		var output_map: Dictionary = {output_commodity_id: actual_output}
		for byproduct: Dictionary in recipe.get("byproducts", []) as Array:
			var byproduct_id: String = str(byproduct.get("commodity_id", ""))
			var byproduct_quantity: int = E1Numeric.mul_div_floor(
				actual_output,
				int(byproduct.get("quantity_per_output", 0)),
				E1Numeric.RECIPE_RATIO_SCALE
			)
			_add_market_inventory(region_id, byproduct_id, byproduct_quantity)
			_flow_add(region_id, byproduct_id, "produced", byproduct_quantity)
			_add_cumulative("produced", byproduct_id, byproduct_quantity)
			output_map[byproduct_id] = byproduct_quantity
		var output_metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		output_metrics["output"] = output_map
		state["daily_metrics"] = output_metrics
		state["input_buffers"] = input_buffers
		state["last_planned_output"] = planned_output
		state["last_actual_output"] = actual_output
		state["labor_satisfaction_bp"] = clampi(labor_satisfaction, 0, E1Numeric.BASIS_POINTS)
		state["input_satisfaction_bp"] = clampi(input_satisfaction, 0, E1Numeric.BASIS_POINTS)
		state["production_constraint_reason"] = limiting_reason
		_industry_states[producer_id] = state
	_day_context["labor_remaining"] = labor_remaining


func _collect_demands() -> void:
	var records: Array[Dictionary] = []
	for raw_record: Variant in _day_context.get("demand_snapshot", []) as Array:
		records.append((raw_record as Dictionary).duplicate(true))
	for producer_id: String in _producer_ids:
		var producer: Dictionary = _producer_definitions[producer_id] as Dictionary
		var recipe: Dictionary = _recipes[str(producer.get("recipe_id", ""))] as Dictionary
		var state: Dictionary = _industry_states[producer_id] as Dictionary
		var planned_output: int = int(state.get("last_planned_output", 0))
		var target_days: int = int(producer.get("input_buffer_target_days", 0))
		if not bool(producer.get("enabled", true)) or target_days <= 0:
			continue
		for requirement: Dictionary in _combined_requirements(recipe):
			var commodity_id: String = str(requirement.get("commodity_id", ""))
			var expected_input: int = E1Numeric.required_from_output(
				planned_output, int(requirement.get("quantity_per_output", 0))
			)
			var target_buffer: int = expected_input * target_days
			var current_buffer: int = int((state.get("input_buffers", {}) as Dictionary).get(commodity_id, 0))
			var requested: int = maxi(0, target_buffer - current_buffer)
			if requested <= 0:
				continue
			records.append({
				"demand_id": "industry:%s:%s" % [producer_id, commodity_id],
				"region_id": str(producer.get("region_id", "")),
				"commodity_id": commodity_id,
				"requested_quantity": requested,
				"demand_class": "producer_input",
				"producer_id": producer_id,
				"stable_order_key": "industry:%s:%s" % [producer_id, commodity_id],
			})
	records.sort_custom(_demand_order)
	_day_context["demand_records"] = records


func _clear_local_markets() -> void:
	var grouped: Dictionary = {}
	for raw_record: Variant in _day_context.get("demand_records", []) as Array:
		var record: Dictionary = raw_record as Dictionary
		var key: String = _flow_key(str(record.get("region_id", "")), str(record.get("commodity_id", "")))
		var rows: Array = grouped.get(key, []) as Array
		rows.append(record)
		grouped[key] = rows
	for key: String in E1Numeric.sorted_string_keys(grouped):
		var split: PackedStringArray = key.split("\u001f")
		if split.size() != 2:
			continue
		var region_id: String = split[0]
		var commodity_id: String = split[1]
		var rows: Array[Dictionary] = _as_dictionary_array(grouped[key] as Array)
		rows.sort_custom(_demand_order)
		var total_requested: int = 0
		for row: Dictionary in rows:
			total_requested += int(row.get("requested_quantity", 0))
		var available: int = _market_inventory(region_id, commodity_id)
		var allocations: Dictionary = _proportional_allocations(rows, mini(available, total_requested))
		var market: Dictionary = _market_states[region_id] as Dictionary
		var demand_map: Dictionary = market.get("demand", {}) as Dictionary
		var fulfilled_map: Dictionary = market.get("fulfilled", {}) as Dictionary
		var unmet_map: Dictionary = market.get("unmet", {}) as Dictionary
		var daily_metrics: Dictionary = market.get("daily_metrics", {}) as Dictionary
		var allocation_metrics: Dictionary = daily_metrics.get("demand_allocations", {}) as Dictionary
		demand_map[commodity_id] = int(demand_map.get(commodity_id, 0)) + total_requested
		var total_fulfilled: int = 0
		for row: Dictionary in rows:
			var demand_id: String = str(row.get("demand_id", ""))
			var allocated: int = int(allocations.get(demand_id, 0))
			total_fulfilled += allocated
			var requested: int = int(row.get("requested_quantity", 0))
			var unmet: int = requested - allocated
			allocation_metrics[demand_id] = allocated
			if str(row.get("demand_class", "")) == "producer_input":
				var producer_id: String = str(row.get("producer_id", ""))
				var industry: Dictionary = _industry_states[producer_id] as Dictionary
				var buffers: Dictionary = industry.get("input_buffers", {}) as Dictionary
				buffers[commodity_id] = int(buffers.get(commodity_id, 0)) + allocated
				industry["input_buffers"] = buffers
				var metrics: Dictionary = industry.get("daily_metrics", {}) as Dictionary
				var replenished: Dictionary = metrics.get("replenished", {}) as Dictionary
				replenished[commodity_id] = int(replenished.get(commodity_id, 0)) + allocated
				metrics["replenished"] = replenished
				industry["daily_metrics"] = metrics
				_industry_states[producer_id] = industry
				_flow_add(region_id, commodity_id, "moved_to_industry_buffers", allocated)
			else:
				_flow_add(region_id, commodity_id, "household_system_consumed", allocated)
				_add_cumulative("household_system_consumed", commodity_id, allocated)
				var metric: Dictionary = market.get("daily_metrics", {}) as Dictionary
				metric["household_system_consumed"] = int(metric.get("household_system_consumed", 0)) + allocated
				market["daily_metrics"] = metric
		fulfilled_map[commodity_id] = int(fulfilled_map.get(commodity_id, 0)) + total_fulfilled
		unmet_map[commodity_id] = int(unmet_map.get(commodity_id, 0)) + (total_requested - total_fulfilled)
		_set_market_inventory(region_id, commodity_id, available - total_fulfilled)
		market["demand"] = demand_map
		market["fulfilled"] = fulfilled_map
		market["unmet"] = unmet_map
		daily_metrics["demand_allocations"] = allocation_metrics
		market["daily_metrics"] = daily_metrics
		_market_states[region_id] = market


func _update_prices() -> void:
	var moving_days: int = maxi(1, int(_policies.get("moving_average_days", 7)))
	for region_id: String in _region_ids:
		var market: Dictionary = _market_states[region_id] as Dictionary
		var demand_map: Dictionary = market.get("demand", {}) as Dictionary
		var unmet_map: Dictionary = market.get("unmet", {}) as Dictionary
		var moving_map: Dictionary = market.get("moving_average_daily_demand", {}) as Dictionary
		var target_map: Dictionary = market.get("target_stock", {}) as Dictionary
		var prices: Dictionary = market.get("price", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var demand: int = int(demand_map.get(commodity_id, 0))
			var unmet: int = int(unmet_map.get(commodity_id, 0))
			var previous_average: int = int(moving_map.get(commodity_id, 0))
			var moving_average: int = demand if previous_average <= 0 else previous_average + E1Numeric.mul_div_floor(demand - previous_average, 1, moving_days)
			moving_average = maxi(0, moving_average)
			moving_map[commodity_id] = moving_average
			var commodity: Dictionary = _commodities[commodity_id] as Dictionary
			var target_days: int = int(commodity.get("target_stock_days", _policies.get("target_stock_days", 7)))
			var target_stock: int = moving_average * target_days
			target_map[commodity_id] = target_stock
			var shortage_bp: int = 0
			if demand > 0:
				shortage_bp = clampi(E1Numeric.mul_div_floor(unmet, E1Numeric.BASIS_POINTS, demand), 0, E1Numeric.BASIS_POINTS)
			var stock_pressure_bp: int = 0
			if target_stock > 0:
				stock_pressure_bp = clampi(
					E1Numeric.mul_div_floor(target_stock - _market_inventory(region_id, commodity_id), E1Numeric.BASIS_POINTS, target_stock),
					-E1Numeric.BASIS_POINTS,
					E1Numeric.BASIS_POINTS
				)
			var raw_change: int = E1Numeric.mul_div_floor(int(_policies.get("shortage_gain_bp", 600)), shortage_bp, E1Numeric.BASIS_POINTS)
			raw_change += E1Numeric.mul_div_floor(int(_policies.get("stock_gain_bp", 250)), stock_pressure_bp, E1Numeric.BASIS_POINTS)
			var change_bp: int = clampi(
				raw_change,
				-int(_policies.get("maximum_daily_price_fall_bp", 500)),
				int(_policies.get("maximum_daily_price_rise_bp", 1000))
			)
			var previous_price: int = maxi(1, int(prices.get(commodity_id, 1)))
			prices[commodity_id] = maxi(
				int(_policies.get("minimum_price_centimes", 1)),
				E1Numeric.mul_div_floor(previous_price, E1Numeric.BASIS_POINTS + change_bp, E1Numeric.BASIS_POINTS)
			)
		market["moving_average_daily_demand"] = moving_map
		market["target_stock"] = target_map
		market["price"] = prices
		var metrics: Dictionary = market.get("daily_metrics", {}) as Dictionary
		metrics["shortage_bp"] = {}
		metrics["stock_pressure_bp"] = {}
		var shortage_metrics: Dictionary = metrics["shortage_bp"] as Dictionary
		var pressure_metrics: Dictionary = metrics["stock_pressure_bp"] as Dictionary
		for commodity_id: String in _commodity_ids:
			var demand: int = int(demand_map.get(commodity_id, 0))
			shortage_metrics[commodity_id] = 0 if demand <= 0 else E1Numeric.mul_div_floor(int(unmet_map.get(commodity_id, 0)), E1Numeric.BASIS_POINTS, demand)
			var target: int = int(target_map.get(commodity_id, 0))
			pressure_metrics[commodity_id] = 0 if target <= 0 else clampi(
				E1Numeric.mul_div_floor(target - _market_inventory(region_id, commodity_id), E1Numeric.BASIS_POINTS, target),
				-E1Numeric.BASIS_POINTS,
				E1Numeric.BASIS_POINTS
			)
		_market_states[region_id] = market


func _build_transport_requests() -> void:
	var requests: Array[Dictionary] = []
	for raw_intent: Variant in _day_context.get("transport_intents", []) as Array:
		var intent: Dictionary = raw_intent as Dictionary
		var request: Dictionary = intent.duplicate(true)
		request["status"] = "requested"
		request["created_day"] = _active_day_index
		requests.append(request)
	requests.sort_custom(_request_order)
	_transport_requests = requests
	for request: Dictionary in requests:
		_known_request_ids[str(request.get("request_id", ""))] = true


func _deliver_due_shipments(day_index: int) -> void:
	var remaining: Array[Dictionary] = []
	var ordered: Array[Dictionary] = _shipments.duplicate(true)
	ordered.sort_custom(_shipment_order)
	for shipment: Dictionary in ordered:
		var shipment_id: String = str(shipment.get("shipment_id", ""))
		if int(shipment.get("arrival_day", -1)) > day_index:
			remaining.append(shipment)
			continue
		if str(shipment.get("status", "")) != "in_transit" or _shipment_history_contains(shipment_id):
			initialization_error = "duplicate or invalid arrival for %s" % shipment_id
			continue
		var destination_id: String = str(shipment.get("destination_region_id", ""))
		var commodity_id: String = str(shipment.get("commodity_id", ""))
		var quantity: int = int(shipment.get("quantity", 0))
		_add_market_inventory(destination_id, commodity_id, quantity)
		_flow_add(destination_id, commodity_id, "arrivals", quantity)
		var market: Dictionary = _market_states[destination_id] as Dictionary
		var metrics: Dictionary = market.get("daily_metrics", {}) as Dictionary
		metrics["arrivals"] = int(metrics.get("arrivals", 0)) + quantity
		market["daily_metrics"] = metrics
		_market_states[destination_id] = market
		shipment["status"] = "delivered"
		shipment["delivered_day"] = day_index
		_shipment_history.append(shipment.duplicate(true))
	_shipments = remaining


func _reset_daily_state() -> void:
	for region_id: String in _region_ids:
		var market: Dictionary = _market_states[region_id] as Dictionary
		market["demand"] = {}
		market["fulfilled"] = {}
		market["unmet"] = {}
		market["daily_metrics"] = {}
		_market_states[region_id] = market
	for producer_id: String in _producer_ids:
		var state: Dictionary = _industry_states[producer_id] as Dictionary
		state["daily_metrics"] = {
			"process_inputs_consumed": {},
			"replenished": {},
			"output": {},
		}
		_industry_states[producer_id] = state


func _new_daily_flow() -> Dictionary:
	var result: Dictionary = {}
	for region_id: String in _region_ids:
		var commodity_flow: Dictionary = {}
		for commodity_id: String in _commodity_ids:
			var opening_buffers: int = 0
			for producer_id: String in _producer_ids:
				var producer: Dictionary = _producer_definitions[producer_id] as Dictionary
				if str(producer.get("region_id", "")) == region_id:
					opening_buffers += int(((_industry_states[producer_id] as Dictionary).get("input_buffers", {}) as Dictionary).get(commodity_id, 0))
			commodity_flow[commodity_id] = {
				"opening_market_inventory": _market_inventory(region_id, commodity_id),
				"opening_industry_buffers": opening_buffers,
				"arrivals": 0,
				"produced": 0,
				"process_inputs_consumed": 0,
				"household_system_consumed": 0,
				"moved_to_industry_buffers": 0,
				"dispatched": 0,
				"losses": 0,
				"closing_market_inventory": 0,
				"closing_industry_buffers": 0,
			}
		result[region_id] = commodity_flow
	return result


func _close_daily_flow() -> void:
	for region_id: String in _region_ids:
		var region_flow: Dictionary = _daily_flow[region_id] as Dictionary
		var market: Dictionary = _market_states[region_id] as Dictionary
		var last_flow: Dictionary = {}
		for commodity_id: String in _commodity_ids:
			var flow: Dictionary = region_flow[commodity_id] as Dictionary
			flow["closing_market_inventory"] = _market_inventory(region_id, commodity_id)
			var closing_buffers: int = 0
			for producer_id: String in _producer_ids:
				var producer: Dictionary = _producer_definitions[producer_id] as Dictionary
				if str(producer.get("region_id", "")) == region_id:
					closing_buffers += int(((_industry_states[producer_id] as Dictionary).get("input_buffers", {}) as Dictionary).get(commodity_id, 0))
			flow["closing_industry_buffers"] = closing_buffers
			last_flow[commodity_id] = flow.duplicate(true)
			region_flow[commodity_id] = flow
		market["last_flow"] = last_flow
		_market_states[region_id] = market
		_daily_flow[region_id] = region_flow


func _validate_daily_flow() -> Dictionary:
	for region_id: String in _region_ids:
		var region_flow: Dictionary = _daily_flow.get(region_id, {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var flow: Dictionary = region_flow.get(commodity_id, {}) as Dictionary
			if flow.is_empty():
				return _fail_result("physical_flow_missing", "daily flow missing for %s/%s" % [region_id, commodity_id])
			var expected: int = int(flow.get("opening_market_inventory", 0)) + int(flow.get("opening_industry_buffers", 0))
			expected += int(flow.get("arrivals", 0)) + int(flow.get("produced", 0))
			expected -= int(flow.get("process_inputs_consumed", 0))
			expected -= int(flow.get("household_system_consumed", 0))
			expected -= int(flow.get("dispatched", 0)) + int(flow.get("losses", 0))
			var closing: int = int(flow.get("closing_market_inventory", 0)) + int(flow.get("closing_industry_buffers", 0))
			if expected != closing:
				return _fail_result(
					"physical_flow_drift",
					"daily flow drift at %s/%s: expected %d, closing %d" % [region_id, commodity_id, expected, closing]
				)
	return _ok()


func _build_day_summary() -> Dictionary:
	var produced: Dictionary = {}
	var process_inputs: Dictionary = {}
	var consumed: Dictionary = {}
	var arrivals: Dictionary = {}
	var dispatched: Dictionary = {}
	var requested: int = 0
	var allocated: int = 0
	for region_id: String in _region_ids:
		var region_flow: Dictionary = _daily_flow.get(region_id, {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var flow: Dictionary = region_flow.get(commodity_id, {}) as Dictionary
			_add_to_int_map(produced, commodity_id, int(flow.get("produced", 0)))
			_add_to_int_map(process_inputs, commodity_id, int(flow.get("process_inputs_consumed", 0)))
			_add_to_int_map(consumed, commodity_id, int(flow.get("household_system_consumed", 0)))
			_add_to_int_map(arrivals, commodity_id, int(flow.get("arrivals", 0)))
			_add_to_int_map(dispatched, commodity_id, int(flow.get("dispatched", 0)))
	for request: Dictionary in _transport_requests:
		requested += int(request.get("requested_quantity", 0))
	for allocation: Dictionary in _pending_allocations:
		allocated += int(allocation.get("allocated_quantity", 0))
	return {
		"day_index": _active_day_index,
		"produced": produced,
		"process_inputs_consumed": process_inputs,
		"household_system_consumed": consumed,
		"arrivals": arrivals,
		"dispatched": dispatched,
		"transport_requested_quantity": requested,
		"transport_allocated_quantity": allocated,
		"in_transit_quantity": _total_in_transit(),
		"phase": _phase,
	}


func _normalize_demand_snapshot(snapshot: Array[Dictionary]) -> Dictionary:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_record: Dictionary in snapshot:
		var record: Dictionary = raw_record.duplicate(true)
		var demand_id: String = str(record.get("demand_id", "")).strip_edges()
		var region_id: String = str(record.get("region_id", "")).strip_edges()
		var commodity_id: String = str(record.get("commodity_id", "")).strip_edges()
		var quantity: Dictionary = _as_int(record.get("requested_quantity", -1), "demand requested quantity", true)
		var demand_class: String = str(record.get("demand_class", "household"))
		if demand_id.is_empty() or seen.has(demand_id) or not _regions.has(region_id) or not _commodities.has(commodity_id) or not bool(quantity.get("success", false)):
			return _fail_result("invalid_demand_snapshot", "invalid or duplicate demand record %s" % demand_id)
		if not ["household", "system"].has(demand_class):
			return _fail_result("invalid_demand_snapshot", "unsupported external demand class %s" % demand_class)
		record["demand_id"] = demand_id
		record["region_id"] = region_id
		record["commodity_id"] = commodity_id
		record["requested_quantity"] = int(quantity["value"])
		record["demand_class"] = demand_class
		record["stable_order_key"] = str(record.get("stable_order_key", demand_id))
		seen[demand_id] = true
		records.append(record)
	records.sort_custom(_demand_order)
	return _ok(records)


func _normalize_labor_snapshot(snapshot: Array[Dictionary]) -> Dictionary:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_record: Dictionary in snapshot:
		var record: Dictionary = raw_record.duplicate(true)
		var region_id: String = str(record.get("region_id", "")).strip_edges()
		var labor_class: String = str(record.get("labor_class", "")).strip_edges()
		var available: Dictionary = _as_int(record.get("available_quantity", -1), "labor available quantity", true)
		var key: String = _labor_key(region_id, labor_class)
		if region_id.is_empty() or labor_class.is_empty() or seen.has(key) or not _regions.has(region_id) or not bool(available.get("success", false)):
			return _fail_result("invalid_labor_snapshot", "invalid or duplicate labor record %s" % key)
		record["region_id"] = region_id
		record["labor_class"] = labor_class
		record["available_quantity"] = int(available["value"])
		records.append(record)
		seen[key] = true
	records.sort_custom(_labor_order)
	return _ok(records)


func _normalize_transport_intents(intents: Array[Dictionary], day_index: int) -> Dictionary:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_record: Dictionary in intents:
		var record: Dictionary = raw_record.duplicate(true)
		var request_id: String = str(record.get("request_id", "")).strip_edges()
		var origin_id: String = str(record.get("origin_region_id", "")).strip_edges()
		var destination_id: String = str(record.get("destination_region_id", "")).strip_edges()
		var commodity_id: String = str(record.get("commodity_id", "")).strip_edges()
		var requested: Dictionary = _as_int(record.get("requested_quantity", -1), "transport requested quantity", false)
		var earliest: Dictionary = _as_int(record.get("earliest_dispatch", day_index), "earliest dispatch", true)
		if request_id.is_empty() or seen.has(request_id) or _known_request_ids.has(request_id) or not _regions.has(origin_id) or not _regions.has(destination_id) or not _commodities.has(commodity_id) or not bool(requested.get("success", false)) or not bool(earliest.get("success", false)):
			return _fail_result("invalid_transport_request", "invalid or duplicate transport request %s" % request_id)
		if int(earliest["value"]) < day_index:
			return _fail_result("invalid_transport_request", "transport request %s is already late" % request_id)
		record["request_id"] = request_id
		record["origin_region_id"] = origin_id
		record["destination_region_id"] = destination_id
		record["commodity_id"] = commodity_id
		record["requested_quantity"] = int(requested["value"])
		record["earliest_dispatch"] = int(earliest["value"])
		record["route_quote_id"] = str(record.get("route_quote_id", ""))
		record["priority_class"] = str(record.get("priority_class", "standard"))
		record["stable_order_key"] = str(record.get("stable_order_key", request_id))
		seen[request_id] = true
		records.append(record)
	records.sort_custom(_request_order)
	return _ok(records)


func _normalize_transport_allocations(allocations: Array[Dictionary]) -> Dictionary:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_record: Dictionary in allocations:
		var record: Dictionary = raw_record.duplicate(true)
		var request_id: String = str(record.get("request_id", "")).strip_edges()
		var quantity: Dictionary = _as_int(record.get("allocated_quantity", -1), "allocated quantity", true)
		var duration: Dictionary = _as_int(record.get("duration", record.get("duration_days", 0)), "transport duration", false)
		var cost: Dictionary = _as_int(record.get("transport_cost", -1), "transport cost", true)
		var route_id: String = str(record.get("route_id", "")).strip_edges()
		if request_id.is_empty() or seen.has(request_id) or not bool(quantity.get("success", false)) or not bool(duration.get("success", false)) or not bool(cost.get("success", false)) or route_id.is_empty():
			return _fail_result("invalid_transport_allocation", "invalid or duplicate allocation %s" % request_id)
		if int(quantity["value"]) <= 0 or int(duration["value"]) <= 0:
			return _fail_result("invalid_transport_allocation", "allocation quantity and duration must be positive")
		record["request_id"] = request_id
		record["allocated_quantity"] = int(quantity["value"])
		record["duration"] = int(duration["value"])
		record["transport_cost"] = int(cost["value"])
		record["route_id"] = route_id
		seen[request_id] = true
		records.append(record)
	records.sort_custom(_allocation_order)
	return _ok(records)


func _normalize_requirements(value: Variant, commodities: Dictionary, label: String) -> Dictionary:
	if value == null:
		return _ok([])
	if not value is Array:
		return _fail_result("invalid_catalog", "%s requirements must be an array" % label)
	var combined: Dictionary = {}
	for raw_requirement: Variant in value as Array:
		if not raw_requirement is Dictionary:
			return _fail_result("invalid_catalog", "%s requirement is not a dictionary" % label)
		var source: Dictionary = raw_requirement as Dictionary
		var commodity_id: String = str(source.get("commodity_id", "")).strip_edges()
		var ratio: Dictionary = _as_int(source.get("quantity_per_output", 0), "%s ratio" % label, false)
		if commodity_id.is_empty() or not commodities.has(commodity_id) or not bool(ratio.get("success", false)):
			return _fail_result("invalid_catalog", "invalid %s requirement %s" % [label, commodity_id])
		if combined.has(commodity_id):
			return _fail_result("invalid_catalog", "duplicate %s commodity %s" % [label, commodity_id])
		combined[commodity_id] = {
			"commodity_id": commodity_id,
			"quantity_per_output": int(ratio["value"]),
		}
	var result: Array[Dictionary] = []
	for commodity_id: String in E1Numeric.sorted_string_keys(combined):
		result.append(combined[commodity_id] as Dictionary)
	return _ok(result)


func _normalize_labor_requirements(value: Variant) -> Dictionary:
	if value == null:
		return _ok([])
	if not value is Array:
		return _fail_result("invalid_catalog", "labor requirements must be an array")
	var combined: Dictionary = {}
	for raw_requirement: Variant in value as Array:
		if not raw_requirement is Dictionary:
			return _fail_result("invalid_catalog", "labor requirement is not a dictionary")
		var source: Dictionary = raw_requirement as Dictionary
		var labor_class: String = str(source.get("labor_class", "")).strip_edges()
		var ratio: Dictionary = _as_int(source.get("quantity_per_output", 0), "labor ratio", false)
		if labor_class.is_empty() or not bool(ratio.get("success", false)):
			return _fail_result("invalid_catalog", "invalid labor requirement %s" % labor_class)
		if combined.has(labor_class):
			return _fail_result("invalid_catalog", "duplicate labor class %s" % labor_class)
		combined[labor_class] = {
			"labor_class": labor_class,
			"quantity_per_output": int(ratio["value"]),
		}
	var result: Array[Dictionary] = []
	for labor_class: String in E1Numeric.sorted_string_keys(combined):
		result.append(combined[labor_class] as Dictionary)
	return _ok(result)


func _normalize_optional_outputs(value: Variant, commodities: Dictionary) -> Dictionary:
	if value == null:
		return _ok([])
	if not value is Array:
		return _fail_result("invalid_catalog", "byproducts must be an array")
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_output: Variant in value as Array:
		if not raw_output is Dictionary:
			return _fail_result("invalid_catalog", "byproduct is not a dictionary")
		var source: Dictionary = raw_output as Dictionary
		var commodity_id: String = str(source.get("commodity_id", "")).strip_edges()
		var ratio: Dictionary = _as_int(source.get("quantity_per_output", 0), "byproduct ratio", false)
		if commodity_id.is_empty() or seen.has(commodity_id) or not commodities.has(commodity_id) or not bool(ratio.get("success", false)):
			return _fail_result("invalid_catalog", "invalid or duplicate byproduct %s" % commodity_id)
		seen[commodity_id] = true
		result.append({
			"commodity_id": commodity_id,
			"quantity_per_output": int(ratio["value"]),
		})
	result.sort_custom(_commodity_requirement_order)
	return _ok(result)


func _normalize_quantity_map(value: Variant, commodities: Dictionary, label: String) -> Dictionary:
	if value == null:
		return _ok({})
	if not value is Dictionary:
		return _fail_result("invalid_catalog", "%s must be a dictionary" % label)
	var result: Dictionary = {}
	for raw_commodity_id: Variant in value as Dictionary:
		var commodity_id: String = str(raw_commodity_id)
		var quantity: Dictionary = _as_int((value as Dictionary)[raw_commodity_id], label, true)
		if not commodities.has(commodity_id) or not bool(quantity.get("success", false)):
			return _fail_result("invalid_catalog", "invalid %s commodity %s" % [label, commodity_id])
		result[commodity_id] = int(quantity["value"])
	return _ok(result)


func _as_int(value: Variant, field: String, allow_zero: bool) -> Dictionary:
	if not value is int:
		return _fail_result("invalid_integer", "%s must be an integer" % field)
	var number: int = int(value)
	if number < 0 or (not allow_zero and number <= 0):
		return _fail_result("invalid_integer", "%s must be positive" % field)
	return {
		"success": true,
		"code": "ok",
		"message": "",
		"value": number,
		"data": {"value": number},
	}


func _configuration_failure(message: String) -> Dictionary:
	return _fail_result("invalid_catalog", message)


func _labor_remaining(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record: Variant in records:
		var record: Dictionary = raw_record as Dictionary
		result[_labor_key(str(record.get("region_id", "")), str(record.get("labor_class", "")))] = int(record.get("available_quantity", 0))
	return result


func _producer_labor_requirements(producer: Dictionary, recipe: Dictionary) -> Array[Dictionary]:
	var configured: Array[Dictionary] = _as_dictionary_array(producer.get("labor_requirements", []) as Array)
	if not configured.is_empty():
		return configured
	return _as_dictionary_array(recipe.get("labor_requirements", []) as Array)


func _combined_requirements(recipe: Dictionary) -> Array[Dictionary]:
	var combined: Dictionary = {}
	for raw_requirement: Variant in recipe.get("inputs", []) as Array:
		var requirement: Dictionary = raw_requirement as Dictionary
		combined[str(requirement.get("commodity_id", ""))] = requirement
	for raw_requirement: Variant in recipe.get("energy_requirements", []) as Array:
		var requirement: Dictionary = raw_requirement as Dictionary
		combined[str(requirement.get("commodity_id", ""))] = requirement
	var result: Array[Dictionary] = []
	for commodity_id: String in E1Numeric.sorted_string_keys(combined):
		result.append(combined[commodity_id] as Dictionary)
	return result


func _proportional_allocations(rows: Array[Dictionary], available: int) -> Dictionary:
	var result: Dictionary = {}
	if available <= 0:
		for row: Dictionary in rows:
			result[str(row.get("demand_id", ""))] = 0
		return result
	var total_requested: int = 0
	for row: Dictionary in rows:
		total_requested += int(row.get("requested_quantity", 0))
	if total_requested <= 0:
		return result
	var remainder_rows: Array[Dictionary] = []
	var allocated: int = 0
	for row: Dictionary in rows:
		var requested: int = int(row.get("requested_quantity", 0))
		var product: int = available * requested
		var base: int = E1Numeric.mul_div_floor(available, requested, total_requested)
		var remainder: int = product % total_requested
		result[str(row.get("demand_id", ""))] = base
		allocated += base
		remainder_rows.append({
			"demand_id": str(row.get("demand_id", "")),
			"remainder": remainder,
		})
	remainder_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar: int = int(a.get("remainder", 0))
		var br: int = int(b.get("remainder", 0))
		if ar != br:
			return ar > br
		return str(a.get("demand_id", "")) < str(b.get("demand_id", ""))
	)
	var remaining: int = available - allocated
	var index: int = 0
	while remaining > 0 and index < remainder_rows.size():
		var demand_id: String = str((remainder_rows[index] as Dictionary).get("demand_id", ""))
		var row: Dictionary = {}
		for candidate: Dictionary in rows:
			if str(candidate.get("demand_id", "")) == demand_id:
				row = candidate
				break
		if int(result.get(demand_id, 0)) < int(row.get("requested_quantity", 0)):
			result[demand_id] = int(result.get(demand_id, 0)) + 1
			remaining -= 1
		index += 1
		if index >= remainder_rows.size() and remaining > 0:
			index = 0
			for fallback: Dictionary in rows:
				var fallback_id: String = str(fallback.get("demand_id", ""))
				if int(result.get(fallback_id, 0)) < int(fallback.get("requested_quantity", 0)):
					result[fallback_id] = int(result.get(fallback_id, 0)) + 1
					remaining -= 1
					if remaining <= 0:
						break
	return result


func _validate_persistent_candidate(candidate: Dictionary) -> Dictionary:
	for required_field: String in PERSISTENT_STATE_FIELDS:
		if not candidate.has(required_field):
			return _fail_result("invalid_persistent_state", "persistent state is missing %s" % required_field)
	if not _has_exact_string_keys(candidate, PERSISTENT_STATE_FIELDS):
		return _fail_result("invalid_persistent_state", "persistent state contains an unknown field")
	var schema_value: Variant = candidate.get("schema_id")
	if not schema_value is String or str(schema_value) != STATE_SCHEMA:
		return _fail_result("state_schema_mismatch", "persistent state schema mismatch")
	var raw_last_day: Variant = candidate.get("last_day_index")
	if not raw_last_day is int or int(raw_last_day) < -1:
		return _fail_result("invalid_persistent_state", "invalid last day index")
	var sequence: Dictionary = _as_int(candidate.get("next_shipment_sequence"), "shipment sequence", false)
	if not bool(sequence.get("success", false)):
		return _fail_result("invalid_persistent_state", "invalid shipment sequence")
	var candidate_identity: Variant = candidate.get("catalog_identity", {})
	if not candidate_identity is Dictionary or not _has_exact_string_keys(candidate_identity, ["catalog_hash", "catalog_revision", "schema_version"]):
		return _fail_result("catalog_mismatch", "persistent state catalog identity is malformed")
	if E1Numeric.canonical_json(candidate_identity) != E1Numeric.canonical_json(_catalog_identity):
		return _fail_result("catalog_mismatch", "persistent state catalog identity mismatch")
	var market_value: Variant = candidate.get("market_states", {})
	var industry_value: Variant = candidate.get("industry_states", {})
	var resource_value: Variant = candidate.get("resource_states", {})
	var shipments_value: Variant = candidate.get("shipments", [])
	var shipment_history_value: Variant = candidate.get("shipment_history", [])
	var cumulative_value: Variant = candidate.get("cumulative_flows", {})
	if not market_value is Dictionary or not industry_value is Dictionary or not resource_value is Dictionary or not shipments_value is Array or not shipment_history_value is Array or not cumulative_value is Dictionary:
		return _fail_result("invalid_persistent_state", "persistent state containers are invalid")
	var market_states: Dictionary = (market_value as Dictionary).duplicate(true)
	var industry_states: Dictionary = (industry_value as Dictionary).duplicate(true)
	var resource_states: Dictionary = (resource_value as Dictionary).duplicate(true)
	if not _has_exact_string_keys(market_states, _region_ids) or not _has_exact_string_keys(industry_states, _producer_ids) or not _has_exact_string_keys(resource_states, E1Numeric.sorted_string_keys(_resource_states)):
		return _fail_result("invalid_persistent_state", "persistent state references an unknown mutable object")
	for region_id: String in _region_ids:
		var raw_market_candidate: Variant = market_states.get(region_id)
		if not raw_market_candidate is Dictionary:
			return _fail_result("invalid_persistent_state", "market state %s is not a dictionary" % region_id)
		var market_candidate: Dictionary = raw_market_candidate as Dictionary
		var region_definition: Dictionary = _regions[region_id] as Dictionary
		if not market_candidate.get("region_id") is String or not market_candidate.get("market_id") is String or not market_candidate.get("enabled") is bool or str(market_candidate.get("region_id")) != region_id or str(market_candidate.get("market_id")) != str(region_definition.get("market_id", "")) or bool(market_candidate.get("enabled")) != bool(region_definition.get("enabled", true)) or not _validate_market_candidate(market_candidate, int(raw_last_day)):
			return _fail_result("invalid_persistent_state", "invalid market state %s" % region_id)
	for producer_id: String in _producer_ids:
		var raw_industry_candidate: Variant = industry_states.get(producer_id)
		if not raw_industry_candidate is Dictionary:
			return _fail_result("invalid_persistent_state", "industry state %s is not a dictionary" % producer_id)
		var industry_candidate: Dictionary = raw_industry_candidate as Dictionary
		var producer_definition: Dictionary = _producer_definitions[producer_id] as Dictionary
		if not industry_candidate.get("producer_id") is String or not industry_candidate.get("region_id") is String or str(industry_candidate.get("producer_id")) != producer_id or str(industry_candidate.get("region_id")) != str(producer_definition.get("region_id", "")) or not _validate_industry_candidate(industry_candidate, int(raw_last_day)):
			return _fail_result("invalid_persistent_state", "invalid industry state %s" % producer_id)
	for resource_id: String in E1Numeric.sorted_string_keys(_resource_states):
		var raw_resource: Variant = resource_states.get(resource_id)
		if not raw_resource is Dictionary or not _validate_resource_candidate(raw_resource as Dictionary, resource_id):
			return _fail_result("invalid_persistent_state", "invalid resource state %s" % resource_id)
	var shipments_result: Dictionary = _validated_dictionary_array(shipments_value, "active shipments")
	var shipment_history_result: Dictionary = _validated_dictionary_array(shipment_history_value, "shipment history")
	var history_result: Dictionary = _validated_dictionary_array(candidate.get("history", []), "daily history")
	if not bool(shipments_result.get("success", false)) or not bool(shipment_history_result.get("success", false)) or not bool(history_result.get("success", false)):
		return _fail_result("invalid_persistent_state", "persistent state contains a malformed record array")
	var shipments: Array[Dictionary] = shipments_result.get("data", []) as Array[Dictionary]
	var shipment_history: Array[Dictionary] = shipment_history_result.get("data", []) as Array[Dictionary]
	var history: Array[Dictionary] = history_result.get("data", []) as Array[Dictionary]
	if history.size() > maxi(1, int(_policies.get("history_limit", HISTORY_LIMIT))):
		return _fail_result("invalid_persistent_state", "persistent history exceeds configured limit")
	var previous_history_day: int = -1
	for summary: Dictionary in history:
		if not _validate_history_record(summary, int(raw_last_day)) or int(summary.get("day_index")) <= previous_history_day:
			return _fail_result("invalid_persistent_state", "persistent history day ordering is invalid")
		previous_history_day = int(summary.get("day_index"))
	if int(raw_last_day) == -1 and not history.is_empty():
		return _fail_result("invalid_persistent_state", "history exists before the first day")
	if int(raw_last_day) >= 0 and (history.is_empty() or previous_history_day != int(raw_last_day)):
		return _fail_result("invalid_persistent_state", "persistent history does not end at last_day_index")
	var known_requests_result: Dictionary = _validated_string_array_to_set(candidate.get("known_request_ids", []), "known request IDs")
	var known_shipments_result: Dictionary = _validated_string_array_to_set(candidate.get("known_shipment_ids", []), "known shipment IDs")
	if not bool(known_requests_result.get("success", false)) or not bool(known_shipments_result.get("success", false)):
		return _fail_result("invalid_persistent_state", "persistent ID index is malformed")
	var known_requests: Dictionary = known_requests_result.get("data", {}) as Dictionary
	var known_shipments: Dictionary = {}
	for shipment: Dictionary in shipments:
		if not _validate_active_shipment(shipment, known_shipments, int(raw_last_day), known_requests):
			return _fail_result("invalid_persistent_state", "invalid active shipment")
	for shipment: Dictionary in shipment_history:
		if not _validate_delivered_shipment(shipment, known_shipments, int(raw_last_day), known_requests):
			return _fail_result("invalid_persistent_state", "duplicate or invalid delivered shipment")
	var supplied_known_shipments: Dictionary = known_shipments_result.get("data", {}) as Dictionary
	if supplied_known_shipments.size() != known_shipments.size() or E1Numeric.sorted_string_keys(supplied_known_shipments) != E1Numeric.sorted_string_keys(known_shipments):
		return _fail_result("invalid_persistent_state", "known shipment index is incomplete")
	var cumulative: Dictionary = (cumulative_value as Dictionary).duplicate(true)
	if not _validate_cumulative_flows(cumulative):
		return _fail_result("invalid_persistent_state", "invalid cumulative physical flows")
	var expected_drifts: Dictionary = _candidate_physical_drift_by_commodity(market_states, industry_states, shipments, cumulative)
	if _count_nonzero_drift(expected_drifts) > 0:
		return _fail_result("invalid_persistent_state", "persistent state has physical drift")
	return _ok({
		"market_states": market_states,
		"industry_states": industry_states,
		"resource_states": resource_states,
		"shipments": shipments,
		"shipment_history": shipment_history,
		"history": history,
		"cumulative_flows": cumulative,
		"known_request_ids": known_requests,
		"known_shipment_ids": supplied_known_shipments,
		"last_day_index": int(raw_last_day),
		"next_shipment_sequence": int(sequence["value"]),
	})


func _has_exact_string_keys(value: Variant, expected: Array[String]) -> bool:
	if not value is Dictionary:
		return false
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source.keys():
		if not raw_key is String:
			return false
	return E1Numeric.sorted_string_keys(source) == expected


func _validate_integer_map(
	value: Variant,
	allowed_ids: Array[String],
	require_exact_keys: bool,
	minimum: int,
	maximum: int = -1
) -> bool:
	if not value is Dictionary:
		return false
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source.keys():
		if not raw_key is String or not allowed_ids.has(str(raw_key)):
			return false
		var number: Variant = source[raw_key]
		if not number is int or int(number) < minimum or (maximum >= 0 and int(number) > maximum):
			return false
	if require_exact_keys and E1Numeric.sorted_string_keys(source) != allowed_ids:
		return false
	return true


func _validate_string_integer_map(value: Variant, minimum: int, maximum: int = -1) -> bool:
	if not value is Dictionary:
		return false
	var source: Dictionary = value as Dictionary
	for raw_key: Variant in source.keys():
		if not raw_key is String or str(raw_key).is_empty():
			return false
		var number: Variant = source[raw_key]
		if not number is int or int(number) < minimum or (maximum >= 0 and int(number) > maximum):
			return false
	return true


func _validate_market_daily_metrics(value: Variant, last_day_index: int) -> bool:
	if not value is Dictionary:
		return false
	var metrics: Dictionary = value as Dictionary
	if metrics.is_empty():
		return last_day_index < 0
	if last_day_index < 0:
		return false
	for raw_key: Variant in metrics.keys():
		if not raw_key is String or not MARKET_DAILY_METRIC_FIELDS.has(str(raw_key)):
			return false
	if last_day_index >= 0 and (not metrics.has("shortage_bp") or not metrics.has("stock_pressure_bp")):
		return false
	if metrics.has("arrivals") and (not metrics["arrivals"] is int or int(metrics["arrivals"]) < 0):
		return false
	if metrics.has("household_system_consumed") and (not metrics["household_system_consumed"] is int or int(metrics["household_system_consumed"]) < 0):
		return false
	if metrics.has("demand_allocations") and not _validate_string_integer_map(metrics["demand_allocations"], 0):
		return false
	if metrics.has("shortage_bp") and not _validate_integer_map(metrics["shortage_bp"], _commodity_ids, true, 0, E1Numeric.BASIS_POINTS):
		return false
	if metrics.has("stock_pressure_bp") and not _validate_integer_map(metrics["stock_pressure_bp"], _commodity_ids, true, -E1Numeric.BASIS_POINTS, E1Numeric.BASIS_POINTS):
		return false
	return true


func _validate_industry_daily_metrics(value: Variant, last_day_index: int, producer_id: String, actual_output: int) -> bool:
	if not value is Dictionary:
		return false
	var metrics: Dictionary = value as Dictionary
	if metrics.is_empty():
		return last_day_index < 0
	if not _has_exact_string_keys(metrics, INDUSTRY_DAILY_METRIC_FIELDS):
		return false
	if not _validate_integer_map(metrics.get("process_inputs_consumed"), _commodity_ids, false, 0) or not _validate_integer_map(metrics.get("replenished"), _commodity_ids, false, 0) or not _validate_integer_map(metrics.get("output"), _commodity_ids, false, 0):
		return false
	var recipe: Dictionary = _recipes[str((_producer_definitions[producer_id] as Dictionary).get("recipe_id", ""))] as Dictionary
	var output: Dictionary = metrics.get("output") as Dictionary
	var output_commodity_id: String = str(recipe.get("output_commodity_id", ""))
	return output.has(output_commodity_id) and int(output.get(output_commodity_id, -1)) == actual_output


func _validate_daily_flow_record(flow: Dictionary) -> bool:
	if not _has_exact_string_keys(flow, DAILY_FLOW_FIELDS):
		return false
	for field: String in DAILY_FLOW_FIELDS:
		var value: Variant = flow.get(field)
		if not value is int or int(value) < 0:
			return false
	var expected: int = int(flow.get("opening_market_inventory")) + int(flow.get("opening_industry_buffers"))
	expected += int(flow.get("arrivals")) + int(flow.get("produced"))
	expected -= int(flow.get("process_inputs_consumed")) + int(flow.get("household_system_consumed"))
	expected -= int(flow.get("dispatched")) + int(flow.get("losses"))
	var closing: int = int(flow.get("closing_market_inventory")) + int(flow.get("closing_industry_buffers"))
	return expected == closing


func _validate_history_record(summary: Dictionary, last_day_index: int) -> bool:
	if not _has_exact_string_keys(summary, HISTORY_FIELDS):
		return false
	var day_index: Variant = summary.get("day_index")
	var phase: Variant = summary.get("phase")
	if not day_index is int or int(day_index) < 0 or int(day_index) > last_day_index or not phase is String or str(phase) != PHASE_ALLOCATED:
		return false
	for field: String in ["transport_requested_quantity", "transport_allocated_quantity", "in_transit_quantity"]:
		var quantity: Variant = summary.get(field)
		if not quantity is int or int(quantity) < 0:
			return false
	if int(summary.get("transport_allocated_quantity")) > int(summary.get("transport_requested_quantity")):
		return false
	for field: String in ["produced", "process_inputs_consumed", "household_system_consumed", "arrivals", "dispatched"]:
		if not _validate_integer_map(summary.get(field), _commodity_ids, false, 0):
			return false
	return true


func _valid_constraint_reason(reason: String, producer_id: String) -> bool:
	if reason == "capacity" or reason == "disabled" or reason == "labor":
		return true
	var producer: Dictionary = _producer_definitions[producer_id] as Dictionary
	var recipe: Dictionary = _recipes[str(producer.get("recipe_id", ""))] as Dictionary
	if reason.begins_with("input:"):
		var commodity_id: String = reason.trim_prefix("input:")
		for requirement: Dictionary in _combined_requirements(recipe):
			if str(requirement.get("commodity_id", "")) == commodity_id:
				return true
	if reason.begins_with("resource:"):
		return reason.trim_prefix("resource:") == str(producer.get("resource_source_id", "")) and not str(producer.get("resource_source_id", "")).is_empty()
	return false


func _validate_market_candidate(market: Dictionary, last_day_index: int) -> bool:
	if not _has_exact_string_keys(market, MARKET_STATE_FIELDS):
		return false
	if not market.get("region_id") is String or not market.get("market_id") is String or not market.get("enabled") is bool:
		return false
	var inventory: Variant = market.get("inventory")
	var prices: Variant = market.get("price")
	if not _validate_integer_map(inventory, _commodity_ids, true, 0) or not _validate_integer_map(prices, _commodity_ids, true, 1):
		return false
	var demand: Variant = market.get("demand")
	var fulfilled: Variant = market.get("fulfilled")
	var unmet: Variant = market.get("unmet")
	if not _validate_integer_map(demand, _commodity_ids, false, 0) or not _validate_integer_map(fulfilled, _commodity_ids, false, 0) or not _validate_integer_map(unmet, _commodity_ids, false, 0):
		return false
	if last_day_index < 0 and (not (demand as Dictionary).is_empty() or not (fulfilled as Dictionary).is_empty() or not (unmet as Dictionary).is_empty()):
		return false
	if E1Numeric.sorted_string_keys(demand as Dictionary) != E1Numeric.sorted_string_keys(fulfilled as Dictionary) or E1Numeric.sorted_string_keys(demand as Dictionary) != E1Numeric.sorted_string_keys(unmet as Dictionary):
		return false
	for commodity_id: String in E1Numeric.sorted_string_keys(demand as Dictionary):
		var requested: int = int((demand as Dictionary).get(commodity_id, 0))
		var fulfilled_quantity: int = int((fulfilled as Dictionary).get(commodity_id, 0))
		var unmet_quantity: int = int((unmet as Dictionary).get(commodity_id, 0))
		if fulfilled_quantity > requested or unmet_quantity != requested - fulfilled_quantity:
			return false
	var moving: Variant = market.get("moving_average_daily_demand")
	var target_stock: Variant = market.get("target_stock")
	if not _validate_integer_map(moving, _commodity_ids, false, 0) or not _validate_integer_map(target_stock, _commodity_ids, false, 0):
		return false
	if E1Numeric.sorted_string_keys(moving as Dictionary) != E1Numeric.sorted_string_keys(target_stock as Dictionary):
		return false
	if last_day_index < 0 and (not (moving as Dictionary).is_empty() or not (target_stock as Dictionary).is_empty()):
		return false
	if last_day_index >= 0 and (E1Numeric.sorted_string_keys(moving as Dictionary) != _commodity_ids or E1Numeric.sorted_string_keys(target_stock as Dictionary) != _commodity_ids):
		return false
	for commodity_id: String in E1Numeric.sorted_string_keys(moving as Dictionary):
		var commodity: Dictionary = _commodities[commodity_id] as Dictionary
		var expected_target: int = int((moving as Dictionary).get(commodity_id, 0)) * int(commodity.get("target_stock_days", 0))
		if int((target_stock as Dictionary).get(commodity_id, -1)) != expected_target:
			return false
	var last_flow: Variant = market.get("last_flow")
	if not last_flow is Dictionary or (last_day_index < 0 and not (last_flow as Dictionary).is_empty()) or (last_day_index >= 0 and (last_flow as Dictionary).is_empty()):
		return false
	if not (last_flow as Dictionary).is_empty():
		if not _has_exact_string_keys(last_flow, _commodity_ids):
			return false
		for commodity_id: String in _commodity_ids:
			var raw_flow: Variant = (last_flow as Dictionary).get(commodity_id)
			if not raw_flow is Dictionary or not _validate_daily_flow_record(raw_flow as Dictionary):
				return false
	var daily_metrics: Variant = market.get("daily_metrics")
	if not _validate_market_daily_metrics(daily_metrics, last_day_index):
		return false
	return true


func _validate_industry_candidate(industry: Dictionary, last_day_index: int) -> bool:
	if not _has_exact_string_keys(industry, INDUSTRY_STATE_FIELDS):
		return false
	var producer_id_value: Variant = industry.get("producer_id")
	var region_id_value: Variant = industry.get("region_id")
	var producer_id: String = str(producer_id_value)
	if not producer_id_value is String or not region_id_value is String or producer_id.is_empty() or not _producer_definitions.has(producer_id):
		return false
	var buffers: Variant = industry.get("input_buffers")
	var producer_definition: Dictionary = _producer_definitions[producer_id] as Dictionary
	var expected_buffer_ids: Array[String] = E1Numeric.sorted_string_keys(producer_definition.get("initial_input_buffers", {}) as Dictionary)
	if not _validate_integer_map(buffers, expected_buffer_ids, true, 0):
		return false
	var utilization_value: Variant = industry.get("utilization_bp")
	var actual_value: Variant = industry.get("last_actual_output")
	var planned_value: Variant = industry.get("last_planned_output")
	var labor_satisfaction: Variant = industry.get("labor_satisfaction_bp")
	var input_satisfaction: Variant = industry.get("input_satisfaction_bp")
	if not utilization_value is int or not actual_value is int or not planned_value is int or not labor_satisfaction is int or not input_satisfaction is int:
		return false
	if int(utilization_value) < 0 or int(utilization_value) > E1Numeric.BASIS_POINTS or int(actual_value) < 0 or int(planned_value) < 0 or int(actual_value) > int(planned_value) or int(planned_value) > int(producer_definition.get("installed_capacity_per_day", 0)):
		return false
	if int(labor_satisfaction) < 0 or int(labor_satisfaction) > E1Numeric.BASIS_POINTS or int(input_satisfaction) < 0 or int(input_satisfaction) > E1Numeric.BASIS_POINTS:
		return false
	var constraint_reason: Variant = industry.get("production_constraint_reason")
	if not constraint_reason is String or not _valid_constraint_reason(str(constraint_reason), producer_id):
		return false
	var daily_metrics: Variant = industry.get("daily_metrics")
	if not _validate_industry_daily_metrics(daily_metrics, last_day_index, producer_id, int(actual_value)):
		return false
	return true


func _validate_resource_candidate(resource: Dictionary, resource_id: String) -> bool:
	if not _has_exact_string_keys(resource, RESOURCE_STATE_FIELDS):
		return false
	var resource_id_value: Variant = resource.get("resource_id")
	var available: Variant = resource.get("available_quantity")
	if not resource_id_value is String or str(resource_id_value) != resource_id or not available is int or int(available) < 0:
		return false
	if int(available) > int((_resource_definitions[resource_id] as Dictionary).get("initial_available_quantity", 0)):
		return false
	return true


func _validate_active_shipment(shipment: Dictionary, known: Dictionary, last_day_index: int, known_requests: Dictionary) -> bool:
	if not _has_exact_string_keys(shipment, ACTIVE_SHIPMENT_FIELDS):
		return false
	if not shipment.get("status") is String or str(shipment.get("status")) != "in_transit":
		return false
	return _validate_shipment_common(shipment, known, last_day_index, known_requests, false)


func _validate_delivered_shipment(shipment: Dictionary, known: Dictionary, last_day_index: int, known_requests: Dictionary) -> bool:
	if not _has_exact_string_keys(shipment, DELIVERED_SHIPMENT_FIELDS):
		return false
	if not shipment.get("status") is String or str(shipment.get("status")) != "delivered":
		return false
	var delivered_day: Variant = shipment.get("delivered_day")
	if not delivered_day is int or int(delivered_day) < 0 or int(delivered_day) > last_day_index:
		return false
	return _validate_shipment_common(shipment, known, last_day_index, known_requests, true)


func _validate_shipment_common(shipment: Dictionary, known: Dictionary, last_day_index: int, known_requests: Dictionary, delivered: bool) -> bool:
	var shipment_id_value: Variant = shipment.get("shipment_id")
	var request_id_value: Variant = shipment.get("request_id")
	var origin_value: Variant = shipment.get("origin_region_id")
	var destination_value: Variant = shipment.get("destination_region_id")
	var commodity_value: Variant = shipment.get("commodity_id")
	var route_value: Variant = shipment.get("route_id")
	if not shipment_id_value is String or not request_id_value is String or not origin_value is String or not destination_value is String or not commodity_value is String or not route_value is String:
		return false
	var shipment_id: String = str(shipment_id_value)
	var request_id: String = str(request_id_value)
	if shipment_id.is_empty() or request_id.is_empty() or str(route_value).is_empty() or known.has(shipment_id) or not known_requests.has(request_id):
		return false
	if not _regions.has(str(origin_value)) or not _regions.has(str(destination_value)) or not _commodities.has(str(commodity_value)):
		return false
	var quantity: Variant = shipment.get("quantity")
	var dispatch_day: Variant = shipment.get("dispatch_day")
	var dispatch_time: Variant = shipment.get("dispatch_time")
	var arrival_day: Variant = shipment.get("arrival_day")
	var arrival_time: Variant = shipment.get("arrival_time")
	var transport_cost: Variant = shipment.get("transport_cost")
	if not quantity is int or not dispatch_day is int or not dispatch_time is int or not arrival_day is int or not arrival_time is int or not transport_cost is int:
		return false
	if int(quantity) <= 0 or int(dispatch_day) < 0 or int(dispatch_time) != int(dispatch_day) or int(arrival_day) <= int(dispatch_day) or int(arrival_time) != int(arrival_day) or int(transport_cost) < 0 or int(dispatch_day) > last_day_index:
		return false
	if delivered:
		if int(shipment.get("delivered_day", -1)) < int(arrival_day):
			return false
	else:
		if int(arrival_day) <= last_day_index:
			return false
	known[shipment_id] = true
	return true


func _validate_cumulative_flows(cumulative: Dictionary) -> bool:
	var flow_names: Array[String] = ["household_system_consumed", "losses", "process_inputs_consumed", "produced"]
	if not _has_exact_string_keys(cumulative, flow_names):
		return false
	for flow_name: String in flow_names:
		var values: Variant = cumulative.get(flow_name, {})
		if not _validate_integer_map(values, _commodity_ids, true, 0):
			return false
	return true


func _candidate_physical_drift_by_commodity(
	market_states: Dictionary,
	industry_states: Dictionary,
	shipments: Array[Dictionary],
	cumulative: Dictionary
) -> Dictionary:
	var actual: Dictionary = {}
	for commodity_id: String in _commodity_ids:
		actual[commodity_id] = 0
	for region_id: String in _region_ids:
		var market: Dictionary = market_states[region_id] as Dictionary
		var inventory: Dictionary = market.get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			actual[commodity_id] = int(actual[commodity_id]) + int(inventory.get(commodity_id, 0))
	for producer_id: String in _producer_ids:
		var industry: Dictionary = industry_states[producer_id] as Dictionary
		var buffers: Dictionary = industry.get("input_buffers", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			actual[commodity_id] = int(actual[commodity_id]) + int(buffers.get(commodity_id, 0))
	for shipment: Dictionary in shipments:
		var commodity_id: String = str(shipment.get("commodity_id", ""))
		if actual.has(commodity_id):
			actual[commodity_id] = int(actual[commodity_id]) + int(shipment.get("quantity", 0))
	var drift_by_commodity: Dictionary = {}
	for commodity_id: String in _commodity_ids:
		var expected: int = int(_initial_stock_by_commodity.get(commodity_id, 0))
		expected += int((cumulative.get("produced", {}) as Dictionary).get(commodity_id, 0))
		expected -= int((cumulative.get("process_inputs_consumed", {}) as Dictionary).get(commodity_id, 0))
		expected -= int((cumulative.get("household_system_consumed", {}) as Dictionary).get(commodity_id, 0))
		expected -= int((cumulative.get("losses", {}) as Dictionary).get(commodity_id, 0))
		drift_by_commodity[commodity_id] = int(actual.get(commodity_id, 0)) - expected
	return drift_by_commodity


func _sum_drift(drift_by_commodity: Dictionary) -> int:
	var total: int = 0
	for commodity_id: String in _commodity_ids:
		total += int(drift_by_commodity.get(commodity_id, 0))
	return total


func _count_nonzero_drift(drift_by_commodity: Dictionary) -> int:
	var count: int = 0
	for commodity_id: String in _commodity_ids:
		if int(drift_by_commodity.get(commodity_id, 0)) != 0:
			count += 1
	return count


func _global_physical_drift_by_commodity() -> Dictionary:
	return _candidate_physical_drift_by_commodity(_market_states, _industry_states, _shipments, _cumulative_flows)


func _count_negative_state() -> int:
	var count: int = 0
	for region_id: String in _region_ids:
		var inventory: Dictionary = (_market_states[region_id] as Dictionary).get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			if int(inventory.get(commodity_id, 0)) < 0:
				count += 1
	for producer_id: String in _producer_ids:
		var buffers: Dictionary = (_industry_states[producer_id] as Dictionary).get("input_buffers", {}) as Dictionary
		for commodity_id: String in E1Numeric.sorted_string_keys(buffers):
			if int(buffers.get(commodity_id, 0)) < 0:
				count += 1
	for resource_id: String in E1Numeric.sorted_string_keys(_resource_states):
		if int((_resource_states[resource_id] as Dictionary).get("available_quantity", 0)) < 0:
			count += 1
	return count


func _duplicate_delivery_count() -> int:
	var seen: Dictionary = {}
	var duplicates: int = 0
	for shipment: Dictionary in _shipment_history:
		var shipment_id: String = str(shipment.get("shipment_id", ""))
		if seen.has(shipment_id):
			duplicates += 1
		seen[shipment_id] = true
	return duplicates


func _validate_physical_references() -> bool:
	return _count_nonzero_drift(_global_physical_drift_by_commodity()) == 0 and _count_negative_state() == 0


func _empty_cumulative_flows(commodity_ids: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for flow_name: String in ["produced", "process_inputs_consumed", "household_system_consumed", "losses"]:
		var values: Dictionary = {}
		for commodity_id: String in commodity_ids:
			values[commodity_id] = 0
		result[flow_name] = values
	return result


func _add_cumulative(flow_name: String, commodity_id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	var values: Dictionary = _cumulative_flows.get(flow_name, {}) as Dictionary
	values[commodity_id] = int(values.get(commodity_id, 0)) + quantity
	_cumulative_flows[flow_name] = values


func _flow_add(region_id: String, commodity_id: String, field: String, quantity: int) -> void:
	if quantity == 0:
		return
	var region_flow: Dictionary = _daily_flow.get(region_id, {}) as Dictionary
	var flow: Dictionary = region_flow.get(commodity_id, {}) as Dictionary
	flow[field] = int(flow.get(field, 0)) + quantity
	region_flow[commodity_id] = flow
	_daily_flow[region_id] = region_flow


func _market_inventory(region_id: String, commodity_id: String) -> int:
	if not _market_states.has(region_id):
		return 0
	var market: Dictionary = _market_states[region_id] as Dictionary
	return int((market.get("inventory", {}) as Dictionary).get(commodity_id, 0))


func _set_market_inventory(region_id: String, commodity_id: String, quantity: int) -> void:
	var market: Dictionary = _market_states[region_id] as Dictionary
	var inventory: Dictionary = market.get("inventory", {}) as Dictionary
	inventory[commodity_id] = quantity
	market["inventory"] = inventory
	_market_states[region_id] = market


func _add_market_inventory(region_id: String, commodity_id: String, quantity: int) -> void:
	if quantity == 0:
		return
	_set_market_inventory(region_id, commodity_id, _market_inventory(region_id, commodity_id) + quantity)


func _total_in_transit() -> int:
	var total: int = 0
	for shipment: Dictionary in _shipments:
		total += int(shipment.get("quantity", 0))
	return total


func _transit_summary(region_id: String, outgoing: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for shipment: Dictionary in _shipments:
		var match: bool = (
			str(shipment.get("origin_region_id", "")) == region_id if outgoing
			else str(shipment.get("destination_region_id", "")) == region_id
		)
		if match:
			result.append(shipment.duplicate(true))
	result.sort_custom(_shipment_order)
	return result


func _shipment_history_contains(shipment_id: String) -> bool:
	for shipment: Dictionary in _shipment_history:
		if str(shipment.get("shipment_id", "")) == shipment_id:
			return true
	return false


func _validated_dictionary_array(value: Variant, label: String) -> Dictionary:
	if not value is Array:
		return _fail_result("invalid_persistent_state", "%s must be an array" % label)
	var result: Array[Dictionary] = []
	for raw_value: Variant in value as Array:
		if not raw_value is Dictionary:
			return _fail_result("invalid_persistent_state", "%s contains a non-dictionary record" % label)
		result.append((raw_value as Dictionary).duplicate(true))
	return _ok(result)


func _validated_string_array_to_set(value: Variant, label: String) -> Dictionary:
	if not value is Array:
		return _fail_result("invalid_persistent_state", "%s must be an array" % label)
	var result: Dictionary = {}
	for raw_value: Variant in value as Array:
		if not raw_value is String:
			return _fail_result("invalid_persistent_state", "%s contains a non-string ID" % label)
		var value_id: String = str(raw_value).strip_edges()
		if value_id.is_empty() or result.has(value_id):
			return _fail_result("invalid_persistent_state", "%s contains an empty or duplicate ID" % label)
		result[value_id] = true
	return _ok(result)


func _dictionary_values(source: Dictionary, ordered_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value_id: String in ordered_ids:
		result.append((source[value_id] as Dictionary).duplicate(true))
	return result


func _copy_dictionary_array(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source:
		result.append(value.duplicate(true))
	return result


func _as_dictionary_array(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _add_to_int_map(target: Dictionary, key: String, quantity: int) -> void:
	if quantity == 0:
		return
	target[key] = int(target.get(key, 0)) + quantity


func _flow_key(region_id: String, commodity_id: String) -> String:
	return region_id + "\u001f" + commodity_id


func _labor_key(region_id: String, labor_class: String) -> String:
	return region_id + "\u001f" + labor_class


func _commodity_requirement_order(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("commodity_id", "")) < str(b.get("commodity_id", ""))


func _demand_order(a: Dictionary, b: Dictionary) -> bool:
	var a_key: String = str(a.get("stable_order_key", a.get("demand_id", "")))
	var b_key: String = str(b.get("stable_order_key", b.get("demand_id", "")))
	if a_key != b_key:
		return a_key < b_key
	return str(a.get("demand_id", "")) < str(b.get("demand_id", ""))


func _labor_order(a: Dictionary, b: Dictionary) -> bool:
	var a_key: String = _labor_key(str(a.get("region_id", "")), str(a.get("labor_class", "")))
	var b_key: String = _labor_key(str(b.get("region_id", "")), str(b.get("labor_class", "")))
	return a_key < b_key


func _request_order(a: Dictionary, b: Dictionary) -> bool:
	var a_key: String = str(a.get("stable_order_key", a.get("request_id", "")))
	var b_key: String = str(b.get("stable_order_key", b.get("request_id", "")))
	if a_key != b_key:
		return a_key < b_key
	return str(a.get("request_id", "")) < str(b.get("request_id", ""))


func _allocation_order(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("request_id", "")) < str(b.get("request_id", ""))


func _shipment_order(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("shipment_id", "")) < str(b.get("shipment_id", ""))


func _ok(data: Variant = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


func _fail_result(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
