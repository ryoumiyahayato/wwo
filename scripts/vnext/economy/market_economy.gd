class_name VNextMarketEconomy
extends RefCounted
## Daily country/region market simulation for vNext.
##
## The system owns physical commodity state and market observations only. It
## does not own people, personal money, politics, military state or runtime
## time. Callers provide an explicit day index and read typed query results.
##
## `routes` is an isolated Alpha Economy fixture / derived commercial network.
## It is not authoritative physical topology or shared transport capacity.
## Future gameplay integration must submit transport demand to Spatial and
## retain only the resulting reservation/reference in Economy shipment state.

const BASIS_POINTS: int = 10000
const HOURS_PER_DAY: int = 24
const POPULATION_UNIT: float = 1_000_000.0
const HISTORY_LIMIT: int = 366
const MAX_SHIPMENTS_PER_DAY: int = 256
const MIN_PRICE_CENTIMES: int = 1
const SNAPSHOT_FLOAT_QUANTUM: float = 0.000000001
const SEASONAL_COMMODITY_CATEGORIES: Dictionary = {
	"agricultural_food": true,
	"processed_food": true,
	"agricultural_raw": true,
}

const DEFAULT_POLICIES: Dictionary = {
	"production_capacity_scale_bp": 40000,
	"warehouse_capacity_scale_bp": 40000,
	"opening_stock_days_cap": 30,
	"target_stock_days_scale_bp": 5000,
	"price_smoothing_bp": 1800,
	"maximum_daily_price_change_bp": 1400,
	"minimum_price_bp_of_base": 2500,
	"maximum_price_bp_of_base": 12000,
	"reserve_stock_bp": 8500,
	"operating_increase_step_bp": 140,
	"operating_decrease_step_bp": 100,
	"minimum_frictional_unemployment_bp": 250,
	"history_limit": HISTORY_LIMIT,
	"max_shipments_per_day": MAX_SHIPMENTS_PER_DAY,
	"seasonal_cycle_days": 365,
	"seasonal_demand_amplitude_bp": 900,
	"seasonal_supply_amplitude_bp": 1400,
}

var catalog: VNextMarketEconomyCatalog
var routes: VNextMarketRouteNetwork
var region_states: Dictionary = {}
var production_sites: Dictionary = {}
var shipments: Array[Dictionary] = []
var shipment_history: Array[Dictionary] = []
var active_shocks: Array[Dictionary] = []
var history: Array[Dictionary] = []
var flow_totals: Dictionary = {}
var last_summary: Dictionary = {}
var initialization_error: String = ""

var _spatial_transport_world: VNextSpatialWorld = null
var _spatial_route_links: Dictionary = {}
var _spatial_transport_window_hour: int = 0

var _policies: Dictionary = {}
var _region_ids: Array[String] = []
var _country_ids: Array[String] = []
var _commodity_ids: Array[String] = []
var _production_site_ids: Array[String] = []
var _production_order: Array[String] = []
var _trade_quota_remaining: Dictionary = {}
var _in_transit_units_by_destination: Dictionary = {}
var _last_day_index: int = -1
var _next_shipment_sequence: int = 1


func configure_1900() -> bool:
	_clear_runtime_state()
	catalog = VNextMarketEconomyCatalog.new()
	if not catalog.load_1900():
		return _fail(catalog.initialization_error)
	routes = VNextMarketRouteNetwork.new()
	if not routes.configure(catalog.transport_edges):
		return _fail(routes.initialization_error)
	_policies = DEFAULT_POLICIES.duplicate(true)
	var source_policies: Dictionary = catalog.policies
	for key: Variant in source_policies:
		if key != "international_market" and key != "integration":
			_policies[str(key)] = source_policies[key]
	_region_ids = catalog.region_market_ids()
	_country_ids = catalog.country_market_ids()
	_commodity_ids = _sorted_keys(catalog.commodities)
	_initialize_regions()
	_initialize_production_sites()
	_initialize_flow_totals()
	_build_production_order()
	_seed_opening_inventory()
	_reset_trade_quotas()
	if not validate_integrity():
		return _fail("初始市场完整性失败")
	return true


func settle_day(day_index: int) -> Dictionary:
	if catalog == null or routes == null:
		return _fail_result("not_configured", "vNext 市场经济尚未配置")
	if day_index <= _last_day_index:
		return _ok({"duplicate": true, "day_index": day_index, "summary": last_summary.duplicate(true)})
	if day_index != _last_day_index + 1:
		return _fail_result(
			"non_sequential_day",
			"市场日结必须从第%d天推进到第%d天" % [_last_day_index + 1, day_index]
		)
	_settle_single_day(day_index)
	return _ok(last_summary.duplicate(true))


func advance_days(day_count: int) -> Dictionary:
	if day_count < 0:
		return _fail_result("invalid_day_count", "日结天数不能为负")
	var result: Dictionary = _ok({"day_count": 0})
	for _step: int in range(day_count):
		result = settle_day(_last_day_index + 1)
		if not bool(result.get("success", false)):
			return result
	return result


func last_day_index() -> int:
	return _last_day_index


func commodity_ids() -> Array[String]:
	return _commodity_ids.duplicate()


func region_market_ids() -> Array[String]:
	return _region_ids.duplicate()


func country_market_ids() -> Array[String]:
	return _country_ids.duplicate()


func market_snapshot(market_id: String) -> Dictionary:
	if region_states.has(market_id):
		return _region_snapshot(market_id)
	if catalog != null and catalog.countries.has(market_id):
		return _country_snapshot(market_id)
	return {}


func region_snapshot(market_id: String) -> Dictionary:
	return _region_snapshot(market_id) if region_states.has(market_id) else {}


func country_snapshot(market_id: String) -> Dictionary:
	return _country_snapshot(market_id) if _country_ids.has(market_id) else {}


func commodity_snapshot(market_id: String, commodity_id: String) -> Dictionary:
	var market: Dictionary = market_snapshot(market_id)
	if market.is_empty():
		return {}
	var commodities: Dictionary = market.get("commodities", {}) as Dictionary
	return (commodities.get(commodity_id, {}) as Dictionary).duplicate(true)


func current_price(market_id: String, commodity_id: String) -> int:
	return int(commodity_snapshot(market_id, commodity_id).get("price_centimes", 0))


func inventory_units(market_id: String, commodity_id: String) -> float:
	if not region_states.has(market_id) or not catalog.commodities.has(commodity_id):
		return 0.0
	var state: Dictionary = region_states[market_id] as Dictionary
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	return float(inventory.get(commodity_id, 0.0))


func set_region_inventory(market_id: String, commodity_id: String, units: float) -> bool:
	if (
		is_nan(units)
		or is_inf(units)
		or units < 0.0
		or not region_states.has(market_id)
		or not catalog.commodities.has(commodity_id)
	):
		return false
	var state: Dictionary = region_states[market_id] as Dictionary
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	var previous: float = float(inventory.get(commodity_id, 0.0))
	inventory[commodity_id] = units
	state["inventory"] = inventory
	region_states[market_id] = state
	var initial: Dictionary = flow_totals.get("initial_inventory", {}) as Dictionary
	initial[commodity_id] = float(initial.get(commodity_id, 0.0)) + units - previous
	flow_totals["initial_inventory"] = initial
	return true


func set_fixture_route_budget(edge_id: String, units_per_day: float) -> bool:
	if routes == null:
		return false
	return routes.set_fixture_edge_budget(edge_id, units_per_day)


func restore_fixture_route_budget(edge_id: String) -> bool:
	if routes == null:
		return false
	return routes.restore_default_fixture_budget(edge_id)


func attach_spatial_transport_authority(
	spatial_world: VNextSpatialWorld,
	route_edge_to_links: Dictionary,
	window_hour: int = -1
) -> bool:
	if spatial_world == null or not spatial_world.is_valid() or routes == null:
		return false
	if route_edge_to_links.is_empty():
		return false
	var candidate_links: Dictionary = {}
	for raw_edge_id: Variant in route_edge_to_links:
		var edge_id: String = str(raw_edge_id)
		if not routes.edges_by_id.has(edge_id):
			return false
		var raw_links: Variant = route_edge_to_links[raw_edge_id]
		var links: Array[String] = []
		if raw_links is String:
			links.append(str(raw_links))
		elif raw_links is Array:
			for raw_link_id: Variant in raw_links as Array:
				if raw_link_id is String:
					links.append(str(raw_link_id))
		if links.is_empty():
			return false
		for link_id: String in links:
			if not spatial_world.catalog().has_link(link_id):
				return false
		candidate_links[edge_id] = links
	if candidate_links.size() != routes.edges_by_id.size():
		return false
	for raw_edge_id: Variant in routes.edges_by_id:
		if not candidate_links.has(str(raw_edge_id)):
			return false
	var candidate_hour: int = spatial_world.current_hour() if window_hour < 0 else window_hour
	if candidate_hour != spatial_world.current_hour() or candidate_hour < 0:
		return false
	_spatial_transport_world = spatial_world
	_spatial_route_links = candidate_links
	_spatial_transport_window_hour = candidate_hour
	return true


func detach_spatial_transport_authority() -> void:
	_spatial_transport_world = null
	_spatial_route_links.clear()
	_spatial_transport_window_hour = 0


func apply_shipment_progress(
	shipment_id: String, delivered_units: float, day_index: int
) -> Dictionary:
	if (
		shipment_id.is_empty()
		or is_nan(delivered_units)
		or is_inf(delivered_units)
		or delivered_units <= 0.0
		or day_index < _last_day_index
	):
		return _fail_result("invalid_shipment_progress", "shipment progress is invalid")
	for index: int in range(shipments.size()):
		var shipment: Dictionary = shipments[index] as Dictionary
		if str(shipment.get("shipment_id", "")) != shipment_id:
			continue
		if day_index < int(shipment.get("dispatch_day", -1)):
			return _fail_result("invalid_shipment_progress", "progress precedes dispatch")
		var remaining: float = float(shipment.get("units", 0.0))
		if delivered_units > remaining + 0.000001:
			return _fail_result("invalid_shipment_progress", "progress exceeds outstanding cargo")
		_apply_shipment_delivery(index, minf(delivered_units, remaining), day_index)
		_rebuild_in_transit_units_index()
		return _ok({"shipment_id": shipment_id, "delivered_units": delivered_units})
	return _fail_result("unknown_shipment", "shipment does not exist")


func apply_market_shock(
	shock_id: String,
	market_id: String,
	commodity_id: String,
	supply_multiplier_bp: int,
	demand_multiplier_bp: int,
	duration_days: int,
	price_delta_bp: int,
	start_day: int,
	reason: String
) -> Dictionary:
	if not _shock_by_id(shock_id).is_empty():
		return _ok({"duplicate": true, "shock_id": shock_id})
	if (
		shock_id.is_empty()
		or (not region_states.has(market_id) and not _country_ids.has(market_id))
		or not catalog.commodities.has(commodity_id)
		or supply_multiplier_bp < 0
		or demand_multiplier_bp < 0
		or duration_days <= 0
		or price_delta_bp < -8000
		or price_delta_bp > 15000
		or start_day < _last_day_index + 1
	):
		return _fail_result("invalid_market_shock", "市场冲击参数或引用无效")
	active_shocks.append({
		"shock_id": shock_id,
		"market_id": market_id,
		"commodity_id": commodity_id,
		"supply_multiplier_bp": supply_multiplier_bp,
		"demand_multiplier_bp": demand_multiplier_bp,
		"price_delta_bp": price_delta_bp,
		"start_day": start_day,
		"end_day": start_day + duration_days,
		"reason": reason,
	})
	return _ok({"shock_id": shock_id, "active_shock_count": active_shocks.size()})


func history_snapshot(
	market_id: String, commodity_id: String, period_days: int = 30
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if period_days <= 0 or not catalog.commodities.has(commodity_id):
		return result
	var start_index: int = maxi(0, history.size() - period_days)
	for index: int in range(start_index, history.size()):
		var entry: Dictionary = history[index] as Dictionary
		var markets: Dictionary = entry.get("markets", {}) as Dictionary
		var market_values: Dictionary = markets.get(market_id, {}) as Dictionary
		var value: Dictionary = market_values.get(commodity_id, {}) as Dictionary
		if not value.is_empty():
			var row: Dictionary = value.duplicate(true)
			row["day_index"] = int(entry.get("day_index", -1))
			result.append(row)
	return result


func validate_integrity() -> bool:
	if catalog == null or routes == null:
		return false
	if region_states.size() != _region_ids.size() or _region_ids.is_empty():
		return false
	if _commodity_ids.size() != catalog.commodities.size():
		return false
	for region_id: String in _region_ids:
		var state: Dictionary = region_states.get(region_id, {}) as Dictionary
		if not _validate_region_state(state):
			return false
	for site_id: String in _production_site_ids:
		var site: Dictionary = production_sites.get(site_id, {}) as Dictionary
		if (
			site.is_empty()
			or not region_states.has(str(site.get("market_id", "")))
			or not catalog.recipes.has(str(site.get("recipe_id", "")))
			or float(site.get("operating_target_bp", -1.0)) < 0.0
			or float(site.get("operating_target_bp", 10001.0)) > BASIS_POINTS
		):
			return false
	for shipment: Dictionary in shipments:
		if (
			float(shipment.get("units", 0.0)) <= 0.0
			or not _shipment_progress_is_conserved(shipment)
			or not region_states.has(str(shipment.get("origin_market_id", "")))
			or not region_states.has(str(shipment.get("destination_market_id", "")))
			or int(shipment.get("arrival_day", -1)) <= int(shipment.get("dispatch_day", -1))
			or str(shipment.get("status", "")) != "in_transit"
		):
			return false
	return _validate_physical_conservation()


func snapshot() -> Dictionary:
	var snapshot_value: Dictionary = {
		"schema_id": "vnext_market_economy_state_v1",
		"last_day_index": _last_day_index,
		"next_shipment_sequence": _next_shipment_sequence,
		"region_states": region_states.duplicate(true),
		"production_sites": production_sites.duplicate(true),
		"shipments": shipments.duplicate(true),
		"shipment_history": shipment_history.duplicate(true),
		"active_shocks": active_shocks.duplicate(true),
		"history": history.duplicate(true),
		"flow_totals": flow_totals.duplicate(true),
		"trade_quota_remaining": _trade_quota_remaining.duplicate(true),
		"route_network": routes.snapshot() if routes != null else {},
	}
	return _canonicalize_snapshot_value(snapshot_value) as Dictionary


func restore(snapshot_value: Dictionary) -> bool:
	if catalog == null or routes == null:
		return false
	if str(snapshot_value.get("schema_id", "")) != "vnext_market_economy_state_v1":
		return false
	if (
		not snapshot_value.get("region_states", {}) is Dictionary
		or not snapshot_value.get("production_sites", {}) is Dictionary
		or not snapshot_value.get("shipments", []) is Array
		or not snapshot_value.get("shipment_history", []) is Array
		or not snapshot_value.get("active_shocks", []) is Array
		or not snapshot_value.get("history", []) is Array
		or not snapshot_value.get("flow_totals", {}) is Dictionary
		or not snapshot_value.get("route_network", {}) is Dictionary
	):
		return false
	var candidate_regions: Dictionary = (
		snapshot_value.get("region_states", {}) as Dictionary
	).duplicate(true)
	var candidate_sites: Dictionary = (
		snapshot_value.get("production_sites", {}) as Dictionary
	).duplicate(true)
	var candidate_shipments: Array[Dictionary] = _dictionary_array(
		snapshot_value.get("shipments", [])
	)
	var candidate_shipment_history: Array[Dictionary] = _dictionary_array(
		snapshot_value.get("shipment_history", [])
	)
	var candidate_shocks: Array[Dictionary] = _dictionary_array(
		snapshot_value.get("active_shocks", [])
	)
	var candidate_history: Array[Dictionary] = _dictionary_array(
		snapshot_value.get("history", [])
	)
	var candidate_flow_totals: Dictionary = (
		snapshot_value.get("flow_totals", {}) as Dictionary
	).duplicate(true)
	var candidate_quotas: Dictionary = (
		snapshot_value.get("trade_quota_remaining", {}) as Dictionary
	).duplicate(true)
	var candidate_last_day: int = int(snapshot_value.get("last_day_index", -1))
	var candidate_sequence: int = int(snapshot_value.get("next_shipment_sequence", 1))
	_normalize_candidate_numeric_types(candidate_regions, candidate_sites, candidate_shipments, candidate_shipment_history, candidate_history)
	_erase_legacy_in_transit_observations(candidate_regions)
	_normalize_candidate_shipments(candidate_shipments)
	_normalize_candidate_flow_totals(candidate_flow_totals)
	_normalize_candidate_quota_types(candidate_quotas)
	if (
		candidate_last_day < -1
		or candidate_sequence < 1
		or candidate_regions.size() != region_states.size()
		or candidate_sites.size() != production_sites.size()
		or not _validate_candidate_regions(candidate_regions)
		or not _validate_candidate_shipments(candidate_shipments)
		or not _validate_candidate_flow_totals(candidate_flow_totals)
	):
		return false
	var original_routes: Dictionary = routes.snapshot()
	if not routes.restore(snapshot_value.get("route_network", {}) as Dictionary):
		return false
	var original_regions: Dictionary = region_states
	var original_sites: Dictionary = production_sites
	var original_shipments: Array[Dictionary] = shipments
	var original_history: Array[Dictionary] = history
	var original_shipment_history: Array[Dictionary] = shipment_history
	var original_shocks: Array[Dictionary] = active_shocks
	var original_flow_totals: Dictionary = flow_totals
	var original_quotas: Dictionary = _trade_quota_remaining.duplicate(true)
	var original_last_day: int = _last_day_index
	var original_sequence: int = _next_shipment_sequence
	var original_last_summary: Dictionary = last_summary.duplicate(true)
	region_states = candidate_regions
	production_sites = candidate_sites
	shipments = candidate_shipments
	_rebuild_in_transit_units_index()
	history = candidate_history
	shipment_history = candidate_shipment_history
	active_shocks = candidate_shocks
	flow_totals = candidate_flow_totals
	_last_day_index = candidate_last_day
	_next_shipment_sequence = candidate_sequence
	_trade_quota_remaining = candidate_quotas
	var valid: bool = validate_integrity()
	if not valid:
		region_states = original_regions
		production_sites = original_sites
		shipments = original_shipments
		_rebuild_in_transit_units_index()
		history = original_history
		shipment_history = original_shipment_history
		active_shocks = original_shocks
		flow_totals = original_flow_totals
		_trade_quota_remaining = original_quotas
		_last_day_index = original_last_day
		_next_shipment_sequence = original_sequence
		last_summary = original_last_summary
		routes.restore(original_routes)
		return false
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	if not last_summary.is_empty() and int(last_summary.get("day_index", -1)) > _last_day_index:
		last_summary = {}
	return true


func _clear_runtime_state() -> void:
	region_states.clear()
	production_sites.clear()
	shipments.clear()
	shipment_history.clear()
	active_shocks.clear()
	history.clear()
	flow_totals.clear()
	last_summary.clear()
	initialization_error = ""
	_region_ids.clear()
	_country_ids.clear()
	_commodity_ids.clear()
	_production_site_ids.clear()
	_production_order.clear()
	_trade_quota_remaining.clear()
	_in_transit_units_by_destination.clear()
	_spatial_transport_world = null
	_spatial_route_links.clear()
	_spatial_transport_window_hour = 0
	_last_day_index = -1
	_next_shipment_sequence = 1


func _initialize_regions() -> void:
	for region_id: String in _region_ids:
		var source: Dictionary = catalog.regions[region_id] as Dictionary
		var override: Dictionary = _region_override(source.get("source_region_id", ""))
		var wage_index: int = maxi(1, int(source.get("wage_index", 100)))
		var living_cost_index: int = maxi(1, int(source.get("living_cost_index", 100)))
		var income_index: int = clampi(wage_index * 100 / living_cost_index, 45, 180)
		var inventories: Dictionary = {}
		var commodity_states: Dictionary = {}
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
			inventories[commodity_id] = 0.0
			commodity_states[commodity_id] = _empty_commodity_state(
				int(commodity.get("base_price_centimes", MIN_PRICE_CENTIMES))
			)
		region_states[region_id] = {
			"market_id": region_id,
			"market_level": "region",
			"country_market_id": str(source.get("country_market_id", "")),
			"source_region_id": str(source.get("source_region_id", "")),
			"population": int(source.get("population", 0)),
			"income_index": income_index,
			"warehouse_capacity_tonnes": float(
				maxf(1.0, float(override.get("warehouse_capacity_tonnes", 100000.0)))
				* float(_policies.get("warehouse_capacity_scale_bp", BASIS_POINTS))
				/ float(BASIS_POINTS)
			),
			"labor_force_bp": int(override.get("labor_force_bp", 4400)),
			"nonmodeled_employment_bp": int(override.get("nonmodeled_employment_bp", 8200)),
			"import_capacity_units_per_day": float(
				override.get("import_capacity_units_per_day", 250.0)
			),
			"export_capacity_units_per_day": float(
				override.get("export_capacity_units_per_day", 250.0)
			),
			"demand_modifiers_bp": (
				override.get("demand_modifiers_bp", {}) as Dictionary
			).duplicate(true),
			"inventory": inventories,
			"commodities": commodity_states,
			"employment": {},
			"last_settlement_day": -1,
		}


func _initialize_production_sites() -> void:
	for raw_site_id: Variant in catalog.production_sites:
		var site_id: String = str(raw_site_id)
		var source: Dictionary = catalog.production_sites[site_id] as Dictionary
		var site: Dictionary = source.duplicate(true)
		site["last_batches"] = 0.0
		site["last_operating_bp"] = 0
		site["last_output_units"] = {}
		site["last_input_units"] = {}
		site["last_input_shortage_bp"] = 0
		site["last_margin_centimes"] = 0
		production_sites[site_id] = site
		_production_site_ids.append(site_id)
	_production_site_ids.sort()


func _initialize_flow_totals() -> void:
	flow_totals = {
		"initial_inventory": {},
		"production": {},
		"industrial_inputs": {},
		"household_consumption": {},
		"spoilage": {},
		"warehouse_overflow": {},
	}
	for commodity_id: String in _commodity_ids:
		for flow_name: String in [
			"initial_inventory", "production", "industrial_inputs",
			"household_consumption", "spoilage", "warehouse_overflow"
		]:
			var values: Dictionary = flow_totals[flow_name] as Dictionary
			values[commodity_id] = 0.0
			flow_totals[flow_name] = values


func _build_production_order() -> void:
	var depth_by_recipe: Dictionary = {}
	for recipe_id: String in catalog.recipes:
		depth_by_recipe[recipe_id] = _recipe_depth(recipe_id, depth_by_recipe, [])
	_production_order = _production_site_ids.duplicate()
	_production_order.sort_custom(func(a: String, b: String) -> bool:
		var recipe_a: String = str((production_sites[a] as Dictionary).get("recipe_id", ""))
		var recipe_b: String = str((production_sites[b] as Dictionary).get("recipe_id", ""))
		var depth_a: int = int(depth_by_recipe.get(recipe_a, 0))
		var depth_b: int = int(depth_by_recipe.get(recipe_b, 0))
		if depth_a == depth_b:
			return a < b
		return depth_a < depth_b
	)


func _seed_opening_inventory() -> void:
	var initial: Dictionary = flow_totals.get("initial_inventory", {}) as Dictionary
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var demand: float = _baseline_daily_demand(region_id, commodity_id)
			var industrial: float = _industrial_demand_for(region_id, commodity_id)
			var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
			var target_days: float = float(commodity.get("target_stock_days", 10))
			var opening_days: float = minf(
				target_days,
				float(_policies.get("opening_stock_days_cap", 30))
			)
			var daily_need: float = demand + industrial
			var local_output: float = _daily_output_capacity(region_id, commodity_id)
			var seeded: float = daily_need * opening_days
			seeded += minf(local_output * 4.0, daily_need * 8.0)
			if str(commodity.get("trade_class", "")) == "local_service":
				seeded = 0.0
			inventory[commodity_id] = maxf(0.0, seeded)
			initial[commodity_id] = float(initial.get(commodity_id, 0.0)) + seeded
		state["inventory"] = inventory
		region_states[region_id] = state
	flow_totals["initial_inventory"] = initial
	for region_id: String in _region_ids:
		_enforce_warehouse_capacity(region_id)


func _settle_single_day(day_index: int) -> void:
	_expire_shocks(day_index)
	routes.reset_daily_fixture_budget()
	_reset_trade_quotas()
	_reset_daily_metrics()
	_deliver_shipments(day_index)
	_rebuild_in_transit_units_index()
	_apply_spoilage()
	_build_daily_demand()
	_run_production(day_index)
	_consume_households()
	_finalize_unmet_demand()
	_schedule_shipments(day_index)
	_rebuild_in_transit_units_index()
	_update_prices()
	_update_site_targets()
	for region_id: String in _region_ids:
		_enforce_warehouse_capacity(region_id)
	_update_employment()
	_last_day_index = day_index
	last_summary = _world_summary(day_index)
	history.append(_history_entry(day_index))
	var history_limit: int = int(_policies.get("history_limit", HISTORY_LIMIT))
	while history.size() > maxi(1, history_limit):
		history.pop_front()
	while shipment_history.size() > maxi(1, history_limit):
		shipment_history.pop_front()


func _reset_daily_metrics() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			for metric_name: String in _metric_names():
				commodity_state[metric_name] = 0.0
			commodity_state.erase("in_transit_import_units")
			commodity_state["inventory_opening_units"] = float(inventory.get(commodity_id, 0.0))
			commodity_states[commodity_id] = commodity_state
		state["commodities"] = commodity_states
		state["employment"] = {}
		region_states[region_id] = state
	for site_id: String in _production_site_ids:
		var site: Dictionary = production_sites[site_id] as Dictionary
		site["last_batches"] = 0.0
		site["last_operating_bp"] = 0
		site["last_output_units"] = {}
		site["last_input_units"] = {}
		site["last_input_shortage_bp"] = 0
		site["last_margin_centimes"] = 0
		production_sites[site_id] = site


func _deliver_shipments(day_index: int) -> void:
	for index: int in range(shipments.size() - 1, -1, -1):
		var shipment: Dictionary = shipments[index] as Dictionary
		if int(shipment.get("arrival_day", 0)) > day_index:
			continue
		_apply_shipment_delivery(index, float(shipment.get("units", 0.0)), day_index)


func _apply_spoilage() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
			var rate_bp: int = int(commodity.get("spoilage_bp_per_day", 0))
			if rate_bp <= 0:
				continue
			var before: float = float(inventory.get(commodity_id, 0.0))
			var loss: float = before * float(rate_bp) / float(BASIS_POINTS)
			if loss <= 0.000001:
				continue
			inventory[commodity_id] = maxf(0.0, before - loss)
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			commodity_state["spoilage_units"] = loss
			commodity_states[commodity_id] = commodity_state
			_add_flow("spoilage", commodity_id, loss)
		state["inventory"] = inventory
		state["commodities"] = commodity_states
		region_states[region_id] = state


func _build_daily_demand() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			var household: float = _household_demand_for(region_id, commodity_id, _last_day_index + 1)
			var industrial: float = _industrial_demand_for(region_id, commodity_id)
			commodity_state["household_demand_units"] = household
			commodity_state["industrial_demand_units"] = industrial
			commodity_state["demand_units"] = household + industrial
			commodity_states[commodity_id] = commodity_state
		state["commodities"] = commodity_states
		region_states[region_id] = state


func _run_production(day_index: int) -> void:
	for site_id: String in _production_order:
		var site: Dictionary = production_sites[site_id] as Dictionary
		var region_id: String = str(site.get("market_id", ""))
		var recipe_id: String = str(site.get("recipe_id", ""))
		var recipe: Dictionary = catalog.recipes[recipe_id] as Dictionary
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		var desired_batches: float = _desired_batches(site)
		var batches: float = desired_batches
		var input_shortage: float = 0.0
		for input: Dictionary in _dictionary_array(recipe.get("inputs", [])):
			var commodity_id: String = str(input.get("commodity_id", ""))
			var units: float = float(input.get("units", 0.0))
			var available: float = float(inventory.get(commodity_id, 0.0))
			if units > 0.0:
				var possible: float = available / units
				if possible < batches:
					input_shortage += (batches - possible) * units
					batches = possible
		batches = maxf(0.0, floor(batches * 1000.0) / 1000.0)
		var input_units: Dictionary = {}
		for input: Dictionary in _dictionary_array(recipe.get("inputs", [])):
			var commodity_id: String = str(input.get("commodity_id", ""))
			var used: float = float(input.get("units", 0.0)) * batches
			inventory[commodity_id] = maxf(
				0.0, float(inventory.get(commodity_id, 0.0)) - used
			)
			input_units[commodity_id] = float(input_units.get(commodity_id, 0.0)) + used
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			commodity_state["industrial_input_units"] = float(
				commodity_state.get("industrial_input_units", 0.0)
			) + used
			commodity_states[commodity_id] = commodity_state
			_add_flow("industrial_inputs", commodity_id, used)
		var supply_multiplier_by_output: Dictionary = {}
		var output_units: Dictionary = {}
		for output: Dictionary in _dictionary_array(recipe.get("outputs", [])):
			var commodity_id: String = str(output.get("commodity_id", ""))
			var supply_multiplier_bp: int = _active_supply_multiplier_bp(
				region_id, commodity_id, day_index
			)
			supply_multiplier_by_output[commodity_id] = supply_multiplier_bp
			var produced: float = float(output.get("units", 0.0)) * batches
			produced *= float(supply_multiplier_bp) / float(BASIS_POINTS)
			produced *= _seasonal_supply_factor(catalog.commodities[commodity_id] as Dictionary, day_index)
			inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + produced
			output_units[commodity_id] = float(output_units.get(commodity_id, 0.0)) + produced
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			commodity_state["production_units"] = float(
				commodity_state.get("production_units", 0.0)
			) + produced
			commodity_state["supply_units"] = float(
				commodity_state.get("supply_units", 0.0)
			) + produced
			commodity_states[commodity_id] = commodity_state
			_add_flow("production", commodity_id, produced)
		var capacity: float = _site_capacity(site)
		var utilization: float = 0.0 if capacity <= 0.0 else batches / capacity
		site["last_batches"] = batches
		site["last_operating_bp"] = clampi(int(round(utilization * BASIS_POINTS)), 0, BASIS_POINTS)
		site["last_output_units"] = output_units
		site["last_input_units"] = input_units
		site["last_input_shortage_bp"] = (
			0 if desired_batches <= 0.0 else clampi(
				int(round(input_shortage / maxf(0.001, desired_batches) * 10000.0)),
				0,
				BASIS_POINTS
			)
		)
		production_sites[site_id] = site
		state["inventory"] = inventory
		state["commodities"] = commodity_states
		region_states[region_id] = state

func _consume_households() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			var demand: float = float(commodity_state.get("household_demand_units", 0.0))
			var available: float = float(inventory.get(commodity_id, 0.0))
			var consumed: float = minf(available, demand)
			inventory[commodity_id] = maxf(0.0, available - consumed)
			commodity_state["consumed_units"] = consumed
			_add_flow("household_consumption", commodity_id, consumed)
			commodity_states[commodity_id] = commodity_state
		state["inventory"] = inventory
		state["commodities"] = commodity_states
		region_states[region_id] = state


func _finalize_unmet_demand() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			var household_demand: float = float(commodity_state.get("household_demand_units", 0.0))
			var industrial_demand: float = float(commodity_state.get("industrial_demand_units", 0.0))
			var household_unmet: float = maxf(
				0.0, household_demand - float(commodity_state.get("consumed_units", 0.0))
			)
			var industrial_unmet: float = maxf(
				0.0,
				industrial_demand - float(commodity_state.get("industrial_input_units", 0.0))
			)
			commodity_state["unmet_units"] = household_unmet + industrial_unmet
			commodity_state["shortage_bp"] = (
				0 if household_demand + industrial_demand <= 0.0 else clampi(
					int(round(
						(household_unmet + industrial_unmet)
						/ (household_demand + industrial_demand)
						* BASIS_POINTS
					)),
					0,
					BASIS_POINTS
				)
			)
			commodity_states[commodity_id] = commodity_state
		state["commodities"] = commodity_states
		region_states[region_id] = state


func _rebuild_in_transit_units_index() -> void:
	_in_transit_units_by_destination.clear()
	for shipment: Dictionary in shipments:
		if str(shipment.get("status", "")) != "in_transit":
			continue
		var destination_id: String = str(shipment.get("destination_market_id", ""))
		var commodity_id: String = str(shipment.get("commodity_id", ""))
		var units: float = maxf(0.0, float(shipment.get("units", 0.0)))
		if destination_id.is_empty() or commodity_id.is_empty() or units <= 0.000001:
			continue
		var commodity_totals: Dictionary = (
			_in_transit_units_by_destination.get(destination_id, {}) as Dictionary
		)
		commodity_totals[commodity_id] = (
			float(commodity_totals.get(commodity_id, 0.0)) + units
		)
		_in_transit_units_by_destination[destination_id] = commodity_totals


func _in_transit_units_for(destination_id: String, commodity_id: String) -> float:
	var commodity_totals: Dictionary = (
		_in_transit_units_by_destination.get(destination_id, {}) as Dictionary
	)
	return maxf(0.0, float(commodity_totals.get(commodity_id, 0.0)))


func _schedule_shipments(day_index: int) -> void:
	if _spatial_transport_world != null:
		_schedule_spatial_shipments(day_index)
		return
	var requests: Array[Dictionary] = []
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			var unmet: float = maxf(0.0, float(commodity_state.get("unmet_units", 0.0)))
			var industrial_demand: float = maxf(0.0, float(commodity_state.get("industrial_demand_units", 0.0)))
			var replenishment: float = 0.0
			var target_stock: float = 0.0
			if industrial_demand > 0.0001:
				target_stock = float(commodity_state.get("target_stock_units", 0.0))
				if target_stock <= 0.0:
					target_stock = _target_stock_for(region_id, commodity_id)
				var stock: float = maxf(0.0, float(inventory.get(commodity_id, 0.0)))
				var in_transit: float = _in_transit_units_for(region_id, commodity_id)
				replenishment = maxf(0.0, target_stock - stock - in_transit)
			var requested: float = maxf(unmet, replenishment)
			if requested <= 0.0001:
				continue
			var replenishment_bp: int = (
				0 if target_stock <= 0.0 else clampi(
					int(round(replenishment / maxf(1.0, target_stock) * BASIS_POINTS)),
					0, BASIS_POINTS
				)
			)
			requests.append({
				"region_id": region_id,
				"commodity_id": commodity_id,
				"request_units": requested,
				"shortage_bp": int(commodity_state.get("shortage_bp", 0)),
				"industrial_replenishment_bp": replenishment_bp,
			})
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_shortage: int = int(a.get("shortage_bp", 0))
		var b_shortage: int = int(b.get("shortage_bp", 0))
		if a_shortage != b_shortage:
			return a_shortage > b_shortage
		var a_replenishment: int = int(a.get("industrial_replenishment_bp", 0))
		var b_replenishment: int = int(b.get("industrial_replenishment_bp", 0))
		if a_replenishment != b_replenishment:
			return a_replenishment > b_replenishment
		var a_key: String = str(a.get("region_id", "")) + str(a.get("commodity_id", ""))
		var b_key: String = str(b.get("region_id", "")) + str(b.get("commodity_id", ""))
		return a_key < b_key
	)
	var created: int = 0
	var max_shipments: int = int(_policies.get("max_shipments_per_day", MAX_SHIPMENTS_PER_DAY))
	for request: Dictionary in requests:
		if created >= max_shipments:
			break
		var destination_id: String = str(request.get("region_id", ""))
		var commodity_id: String = str(request.get("commodity_id", ""))
		var remaining: float = float(request.get("request_units", 0.0))
		var candidates: Array[Dictionary] = _supplier_candidates(
			destination_id, commodity_id
		)
		for candidate: Dictionary in candidates:
			if remaining <= 0.0001 or created >= max_shipments:
				break
			var origin_id: String = str(candidate.get("origin_market_id", ""))
			var route: Dictionary = candidate.get("route", {}) as Dictionary
			var relation: Dictionary = candidate.get("relation", {}) as Dictionary
			var relation_key: String = str(candidate.get("relation_key", ""))
			var quota: float = INF
			if not relation.is_empty():
				quota = float(_trade_quota_remaining.get(relation_key, 0.0))
			var units: float = minf(
				remaining,
				minf(float(candidate.get("surplus", 0.0)), routes.route_fixture_budget(route))
			)
			units = minf(units, quota)
			if units <= 0.0001:
				continue
			if not routes.consume_fixture_budget(route, units):
				continue
			var origin_state: Dictionary = region_states[origin_id] as Dictionary
			var origin_inventory: Dictionary = origin_state.get("inventory", {}) as Dictionary
			origin_inventory[commodity_id] = maxf(
				0.0, float(origin_inventory.get(commodity_id, 0.0)) - units
			)
			var origin_commodity: Dictionary = (
				origin_state.get("commodities", {}) as Dictionary
			).get(commodity_id, {}) as Dictionary
			origin_commodity["exports_units"] = float(
				origin_commodity.get("exports_units", 0.0)
			) + units
			origin_state["inventory"] = origin_inventory
			(origin_state.get("commodities", {}) as Dictionary)[commodity_id] = origin_commodity
			region_states[origin_id] = origin_state
			if not relation.is_empty():
				_trade_quota_remaining[relation_key] = maxf(0.0, quota - units)
			var unit_price: int = int(origin_commodity.get("price_centimes", 1))
			var goods_value: int = maxi(1, int(round(float(unit_price) * units)))
			var freight: int = maxi(
				0,
				int(round(float(route.get("cost_centimes_per_unit", 0.0)) * units))
			)
			var tariff: int = maxi(
				0,
				int(round(
					float(goods_value) * float(relation.get("tariff_bp", 0))
					/ float(BASIS_POINTS)
				))
			)
			var arrival_day: int = day_index + maxi(
				1, int(ceil(float(route.get("duration_hours", HOURS_PER_DAY)) / 24.0))
			)
			shipments.append({
				"shipment_id": "shipment:vnext_market:%d" % _next_shipment_sequence,
				"origin_market_id": origin_id,
				"destination_market_id": destination_id,
				"commodity_id": commodity_id,
				"units": units,
				"total_units": units,
				"delivered_units": 0.0,
				"progress_units": 0.0,
				"last_progress_day": day_index,
				"transport_demand_units": units,
				"goods_value_centimes": goods_value,
				"freight_cost_centimes": freight,
				"tariff_centimes": tariff,
				"landed_cost_centimes": goods_value + freight + tariff,
				"dispatch_day": day_index,
				"arrival_day": arrival_day,
				"duration_hours": int(route.get("duration_hours", 0)),
				"distance_days": float(route.get("distance_days", 0.0)),
				"route_edge_ids": (route.get("edge_ids", []) as Array).duplicate(),
				"cross_border": bool(route.get("cross_border", false)),
				"status": "in_transit",
			})
			_next_shipment_sequence += 1
			remaining -= units
			created += 1


func _schedule_spatial_shipments(day_index: int) -> void:
	if _spatial_transport_world == null or not _spatial_transport_world.is_valid():
		return
	_spatial_transport_window_hour = _spatial_transport_world.current_hour()
	var requests: Array[Dictionary] = []
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			var unmet: float = maxf(0.0, float(commodity_state.get("unmet_units", 0.0)))
			var industrial_demand: float = maxf(
				0.0, float(commodity_state.get("industrial_demand_units", 0.0))
			)
			var replenishment: float = 0.0
			var target_stock: float = 0.0
			if industrial_demand > 0.0001:
				target_stock = float(commodity_state.get("target_stock_units", 0.0))
				if target_stock <= 0.0:
					target_stock = _target_stock_for(region_id, commodity_id)
				var stock: float = maxf(0.0, float(inventory.get(commodity_id, 0.0)))
				var in_transit: float = _in_transit_units_for(region_id, commodity_id)
				replenishment = maxf(0.0, target_stock - stock - in_transit)
			var requested: float = maxf(unmet, replenishment)
			if requested <= 0.0001:
				continue
			var replenishment_bp: int = (
				0 if target_stock <= 0.0 else clampi(
					int(round(replenishment / maxf(1.0, target_stock) * BASIS_POINTS)),
					0, BASIS_POINTS
				)
			)
			requests.append({
				"region_id": region_id,
				"commodity_id": commodity_id,
				"request_units": requested,
				"shortage_bp": int(commodity_state.get("shortage_bp", 0)),
				"industrial_replenishment_bp": replenishment_bp,
			})
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_shortage: int = int(a.get("shortage_bp", 0))
		var b_shortage: int = int(b.get("shortage_bp", 0))
		if a_shortage != b_shortage:
			return a_shortage > b_shortage
		var a_replenishment: int = int(a.get("industrial_replenishment_bp", 0))
		var b_replenishment: int = int(b.get("industrial_replenishment_bp", 0))
		if a_replenishment != b_replenishment:
			return a_replenishment > b_replenishment
		var a_key: String = str(a.get("region_id", "")) + str(a.get("commodity_id", ""))
		var b_key: String = str(b.get("region_id", "")) + str(b.get("commodity_id", ""))
		return a_key < b_key
	)
	var intents: Array[Dictionary] = []
	var local_surplus: Dictionary = {}
	var local_quota: Dictionary = _trade_quota_remaining.duplicate(true)
	for request: Dictionary in requests:
		var destination_id: String = str(request.get("region_id", ""))
		var commodity_id: String = str(request.get("commodity_id", ""))
		var remaining: float = float(request.get("request_units", 0.0))
		for candidate: Dictionary in _supplier_candidates(destination_id, commodity_id):
			if remaining <= 0.0001:
				break
			var origin_id: String = str(candidate.get("origin_market_id", ""))
			var route: Dictionary = candidate.get("route", {}) as Dictionary
			var link_ids: Array[String] = _spatial_links_for_route(route)
			if link_ids.is_empty():
				continue
			var relation: Dictionary = candidate.get("relation", {}) as Dictionary
			var relation_key: String = str(candidate.get("relation_key", ""))
			var quota: float = INF
			if not relation.is_empty():
				quota = float(local_quota.get(relation_key, 0.0))
			var surplus_key: String = origin_id + "|" + commodity_id
			var surplus: float = float(local_surplus.get(
				surplus_key, float(candidate.get("surplus", 0.0))
			))
			var units: float = minf(remaining, minf(surplus, quota))
			if units <= 0.0001:
				continue
			local_surplus[surplus_key] = maxf(0.0, surplus - units)
			if not relation.is_empty():
				local_quota[relation_key] = maxf(0.0, quota - units)
			var intent_index: int = intents.size()
			var request_ids: Array[String] = []
			for link_index: int in range(link_ids.size()):
				request_ids.append(
					"economy_transport:%d:%d:%d" % [day_index, intent_index, link_index]
				)
			intents.append({
				"origin_market_id": origin_id,
				"destination_market_id": destination_id,
				"commodity_id": commodity_id,
				"route": route,
				"relation": relation,
				"relation_key": relation_key,
				"request_units": units,
				"link_ids": link_ids,
				"request_ids": request_ids,
			})
			remaining -= units
	var submitted: Array[Dictionary] = []
	for intent: Dictionary in intents:
		var link_ids: Array = intent.get("link_ids", []) as Array
		var request_ids: Array = intent.get("request_ids", []) as Array
		for link_index: int in range(link_ids.size()):
			var request_id: String = str(request_ids[link_index])
			var link_id: String = str(link_ids[link_index])
			var result: Dictionary = _spatial_transport_world.request_capacity(
				request_id,
				link_id,
				_spatial_transport_window_hour,
				float(intent.get("request_units", 0.0))
			)
			if not bool(result.get("accepted", false)):
				_cancel_spatial_requests(submitted)
				return
			submitted.append({
				"request_id": request_id,
				"link_id": link_id,
				"window_hour": _spatial_transport_window_hour,
			})
	var final_allocations: Array[float] = []
	for intent: Dictionary in intents:
		var allocation: float = INF
		var link_ids: Array = intent.get("link_ids", []) as Array
		var request_ids: Array = intent.get("request_ids", []) as Array
		for link_index: int in range(link_ids.size()):
			var result: Dictionary = _spatial_transport_world.reservation_result(
				str(request_ids[link_index]),
				str(link_ids[link_index]),
				_spatial_transport_window_hour
			)
			if not bool(result.get("success", false)):
				_cancel_spatial_requests(submitted)
				return
			allocation = minf(allocation, float(result.get("allocated_capacity", 0.0)))
		final_allocations.append(maxf(0.0, allocation))
	for intent_index: int in range(intents.size()):
		var intent: Dictionary = intents[intent_index] as Dictionary
		var allocated: float = minf(
			final_allocations[intent_index], float(intent.get("request_units", 0.0))
		)
		var relation: Dictionary = intent.get("relation", {}) as Dictionary
		var relation_key: String = str(intent.get("relation_key", ""))
		if not relation.is_empty() and allocated > float(
			_trade_quota_remaining.get(relation_key, 0.0)
		) + 0.000001:
			allocated = 0.0
		if allocated <= 0.0001:
			_cancel_spatial_intent_requests(intent)
			continue
		var origin_id: String = str(intent.get("origin_market_id", ""))
		var destination_id: String = str(intent.get("destination_market_id", ""))
		var commodity_id: String = str(intent.get("commodity_id", ""))
		var origin_state: Dictionary = region_states[origin_id] as Dictionary
		var origin_inventory: Dictionary = origin_state.get("inventory", {}) as Dictionary
		if float(origin_inventory.get(commodity_id, 0.0)) + 0.000001 < allocated:
			_cancel_spatial_intent_requests(intent)
			continue
		var origin_commodity: Dictionary = (
			origin_state.get("commodities", {}) as Dictionary
		).get(commodity_id, {}) as Dictionary
		origin_inventory[commodity_id] = maxf(
			0.0, float(origin_inventory.get(commodity_id, 0.0)) - allocated
		)
		origin_commodity["exports_units"] = float(
			origin_commodity.get("exports_units", 0.0)
		) + allocated
		origin_state["inventory"] = origin_inventory
		(origin_state.get("commodities", {}) as Dictionary)[commodity_id] = origin_commodity
		region_states[origin_id] = origin_state
		if not relation.is_empty():
			_trade_quota_remaining[relation_key] = maxf(
				0.0, float(_trade_quota_remaining.get(relation_key, 0.0)) - allocated
			)
		var route: Dictionary = intent.get("route", {}) as Dictionary
		var unit_price: int = int(origin_commodity.get("price_centimes", 1))
		var goods_value: int = maxi(1, int(round(float(unit_price) * allocated)))
		var freight: int = maxi(
			0, int(round(float(route.get("cost_centimes_per_unit", 0.0)) * allocated))
		)
		var tariff: int = maxi(
			0,
			int(round(
				float(goods_value) * float(relation.get("tariff_bp", 0)) / BASIS_POINTS
			))
		)
		var arrival_day: int = day_index + maxi(
			1, int(ceil(float(route.get("duration_hours", HOURS_PER_DAY)) / 24.0))
		)
		shipments.append({
			"shipment_id": "shipment:vnext_market:%d" % _next_shipment_sequence,
			"origin_market_id": origin_id,
			"destination_market_id": destination_id,
			"commodity_id": commodity_id,
			"units": allocated,
			"total_units": allocated,
			"delivered_units": 0.0,
			"progress_units": 0.0,
			"last_progress_day": day_index,
			"transport_demand_units": float(intent.get("request_units", 0.0)),
			"spatial_allocation_units": allocated,
			"spatial_link_ids": (intent.get("link_ids", []) as Array).duplicate(),
			"spatial_request_ids": (intent.get("request_ids", []) as Array).duplicate(),
			"spatial_window_hour": _spatial_transport_window_hour,
			"goods_value_centimes": goods_value,
			"freight_cost_centimes": freight,
			"tariff_centimes": tariff,
			"landed_cost_centimes": goods_value + freight + tariff,
			"dispatch_day": day_index,
			"arrival_day": arrival_day,
			"duration_hours": int(route.get("duration_hours", 0)),
			"distance_days": float(route.get("distance_days", 0.0)),
			"route_edge_ids": (route.get("edge_ids", []) as Array).duplicate(),
			"cross_border": bool(route.get("cross_border", false)),
			"status": "in_transit",
		})
		_next_shipment_sequence += 1


func _spatial_links_for_route(route: Dictionary) -> Array[String]:
	var links: Array[String] = []
	for raw_edge_id: Variant in route.get("edge_ids", []) as Array:
		var edge_id: String = str(raw_edge_id)
		if not _spatial_route_links.has(edge_id):
			return []
		var raw_links: Variant = _spatial_route_links[edge_id]
		if raw_links is String:
			raw_links = [raw_links]
		if not raw_links is Array:
			return []
		for raw_link_id: Variant in raw_links as Array:
			var link_id: String = str(raw_link_id)
			if link_id.is_empty() or not links.has(link_id):
				links.append(link_id)
	return links


func _cancel_spatial_requests(requests: Array[Dictionary]) -> void:
	if _spatial_transport_world == null:
		return
	for request: Dictionary in requests:
		_spatial_transport_world.cancel_capacity_request(
			str(request.get("request_id", "")),
			str(request.get("link_id", "")),
			int(request.get("window_hour", _spatial_transport_window_hour))
		)


func _cancel_spatial_intent_requests(intent: Dictionary) -> void:
	if _spatial_transport_world == null:
		return
	var link_ids: Array = intent.get("link_ids", []) as Array
	var request_ids: Array = intent.get("request_ids", []) as Array
	for link_index: int in range(link_ids.size()):
		_spatial_transport_world.cancel_capacity_request(
			str(request_ids[link_index]),
			str(link_ids[link_index]),
			_spatial_transport_window_hour
		)


func _update_prices() -> void:
	var smoothing_bp: int = clampi(
		int(_policies.get("price_smoothing_bp", 1800)), 1, BASIS_POINTS
	)
	var max_change_bp: int = clampi(
		int(_policies.get("maximum_daily_price_change_bp", 1400)), 1, BASIS_POINTS
	)
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			var base_price: int = maxi(
				MIN_PRICE_CENTIMES, int(commodity.get("base_price_centimes", 1))
			)
			var demand_units: float = maxf(0.0, float(commodity_state.get("demand_units", 0.0)))
			var demand: float = maxf(0.001, demand_units)
			var same_day_supply: float = maxf(0.0, float(commodity_state.get("supply_units", 0.0)))
			var same_day_balance_pressure_bp: int = 0
			if demand_units > 0.0001 or same_day_supply > 0.0001:
				var balance_denominator: float = maxf(0.001, demand_units + same_day_supply)
				same_day_balance_pressure_bp = clampi(
					int(round((demand_units - same_day_supply) / balance_denominator * 8000.0)),
					-3000,
					3000
				)
			var target_days: float = float(commodity.get("target_stock_days", 10)) * float(
				_policies.get("target_stock_days_scale_bp", BASIS_POINTS)
			) / float(BASIS_POINTS)
			var target_stock: float = maxf(1.0, demand * target_days)
			var stock: float = maxf(0.0, float(inventory.get(commodity_id, 0.0)))
			var coverage: float = stock / target_stock
			var unmet_ratio: float = clampf(
				float(commodity_state.get("unmet_units", 0.0)) / demand, 0.0, 1.0
			)
			var stock_pressure_bp: int = clampi(
				int(round((1.0 - coverage) * 3200.0)), -5000, 5000
			)
			var shortage_pressure_bp: int = int(round(unmet_ratio * 6500.0))
			var price_shock_bp: int = _active_price_modifier_bp(
				region_id, commodity_id
			)
			var target_multiplier_bp: int = (
				BASIS_POINTS
				+ stock_pressure_bp
				+ shortage_pressure_bp
				+ same_day_balance_pressure_bp
				+ price_shock_bp
			)
			var minimum_multiplier_bp: int = int(_policies.get("minimum_price_bp_of_base", 2500))
			var maximum_multiplier_bp: int = int(_policies.get("maximum_price_bp_of_base", 12000))
			target_multiplier_bp = clampi(
				target_multiplier_bp, minimum_multiplier_bp, maximum_multiplier_bp
			)
			var target_price: int = maxi(
				MIN_PRICE_CENTIMES, base_price * target_multiplier_bp / BASIS_POINTS
			)
			var previous_price: int = maxi(
				MIN_PRICE_CENTIMES, int(commodity_state.get("price_centimes", base_price))
			)
			var smoothed: int = (
				previous_price * (BASIS_POINTS - smoothing_bp)
				+ target_price * smoothing_bp
			) / BASIS_POINTS
			var minimum_price: int = maxi(
				MIN_PRICE_CENTIMES,
				previous_price * (BASIS_POINTS - max_change_bp) / BASIS_POINTS
			)
			var maximum_price: int = maxi(
				minimum_price,
				previous_price * (BASIS_POINTS + max_change_bp) / BASIS_POINTS
			)
			commodity_state["price_centimes"] = clampi(smoothed, minimum_price, maximum_price)
			commodity_state["target_price_centimes"] = target_price
			commodity_state["target_stock_units"] = target_stock
			commodity_state["inventory_end_units"] = stock
			commodity_state["inventory_coverage_bp"] = clampi(
				int(round(coverage * BASIS_POINTS)), 0, 50000
			)
			commodity_states[commodity_id] = commodity_state
		state["commodities"] = commodity_states
		region_states[region_id] = state


func _reachable_external_shortage_bp(origin_id: String, commodity_id: String) -> int:
	var maximum_shortage_bp: int = 0
	for destination_id: String in _region_ids:
		if destination_id == origin_id:
			continue
		var destination_state: Dictionary = region_states[destination_id] as Dictionary
		var destination_row: Dictionary = (destination_state.get("commodities", {}) as Dictionary).get(commodity_id, {}) as Dictionary
		var shortage_bp: int = int(destination_row.get("shortage_bp", 0))
		if shortage_bp <= maximum_shortage_bp or shortage_bp < 500:
			continue
		var route: Dictionary = routes.find_route(
			origin_id, destination_id, _spatial_transport_world == null
		)
		if route.is_empty():
			continue
		if _spatial_transport_world == null and routes.route_fixture_budget(route) <= 0.0001:
			continue
		if _spatial_transport_world != null and _spatial_links_for_route(route).is_empty():
			continue
		if bool(route.get("cross_border", false)):
			var origin_country: String = str((region_states[origin_id] as Dictionary).get("country_market_id", ""))
			var destination_country: String = str(destination_state.get("country_market_id", ""))
			var relation_key: String = origin_country + ">" + destination_country
			var relation: Dictionary = catalog.trade_relations.get(relation_key, {}) as Dictionary
			if relation.is_empty() or bool(relation.get("embargo", false)) or float(_trade_quota_remaining.get(relation_key, 0.0)) <= 0.0001:
				continue
		maximum_shortage_bp = shortage_bp
	return maximum_shortage_bp


func _update_site_targets() -> void:
	for site_id: String in _production_site_ids:
		var site: Dictionary = production_sites[site_id] as Dictionary
		var region_id: String = str(site.get("market_id", ""))
		var recipe: Dictionary = catalog.recipes[str(site.get("recipe_id", ""))] as Dictionary
		var output_value_per_batch: float = 0.0
		var input_cost_per_batch: float = 0.0
		var output_shortage_bp: int = 0
		var output_external_shortage_bp: int = 0
		var output_exports: float = 0.0
		var output_surplus: bool = true
		var region_commodities: Dictionary = (
			(region_states[region_id] as Dictionary).get("commodities", {}) as Dictionary
		)
		for output: Dictionary in _dictionary_array(recipe.get("outputs", [])):
			var commodity_id: String = str(output.get("commodity_id", ""))
			var units: float = float(output.get("units", 0.0))
			var commodity_state: Dictionary = region_commodities.get(commodity_id, {}) as Dictionary
			output_value_per_batch += units * float(commodity_state.get("price_centimes", 0))
			output_shortage_bp = maxi(
				output_shortage_bp, int(commodity_state.get("shortage_bp", 0))
			)
			output_external_shortage_bp = maxi(output_external_shortage_bp, _reachable_external_shortage_bp(region_id, commodity_id))
			output_exports += float(commodity_state.get("exports_units", 0.0))
			if float(commodity_state.get("inventory_coverage_bp", 0)) <= 12000.0:
				output_surplus = false
		for input: Dictionary in _dictionary_array(recipe.get("inputs", [])):
			var commodity_id: String = str(input.get("commodity_id", ""))
			var commodity_state: Dictionary = region_commodities.get(commodity_id, {}) as Dictionary
			input_cost_per_batch += float(input.get("units", 0.0)) * float(
				commodity_state.get("price_centimes", 0)
			)
		var margin: int = int(round(output_value_per_batch - input_cost_per_batch))
		var target: int = clampi(int(site.get("operating_target_bp", 0)), 0, BASIS_POINTS)
		var input_shortage_bp: int = int(site.get("last_input_shortage_bp", 0))
		if margin > 0 and (
			output_shortage_bp >= 500
			or output_external_shortage_bp >= 500
			or input_shortage_bp >= 500
			or output_exports > 0.0001
		):
			target += int(_policies.get("operating_increase_step_bp", 140))
		elif margin < 0 or (output_surplus and output_shortage_bp == 0 and output_external_shortage_bp < 500 and output_exports <= 0.0001):
			target -= int(_policies.get("operating_decrease_step_bp", 100))
		site["operating_target_bp"] = clampi(target, 0, BASIS_POINTS)
		site["last_margin_centimes"] = margin * float(site.get("last_batches", 0.0))
		production_sites[site_id] = site


func _enforce_warehouse_capacity(region_id: String) -> void:
	var state: Dictionary = region_states[region_id] as Dictionary
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	var capacity_tonnes: float = float(state.get("warehouse_capacity_tonnes", 0.0))
	var used_tonnes: float = _warehouse_used_tonnes(state)
	if capacity_tonnes <= 0.0 or used_tonnes <= capacity_tonnes:
		return
	var excess_kg: float = (used_tonnes - capacity_tonnes) * 1000.0
	var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
	for priority: int in range(1, 11):
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
			if int(commodity.get("storage_priority", 5)) != priority:
				continue
			var mass_kg: float = float(commodity.get("unit_mass_kg", 0.0))
			if mass_kg <= 0.0:
				continue
			var available: float = float(inventory.get(commodity_id, 0.0))
			var removed: float = minf(available, excess_kg / mass_kg)
			if removed <= 0.000001:
				continue
			inventory[commodity_id] = maxf(0.0, available - removed)
			excess_kg -= removed * mass_kg
			var commodity_state: Dictionary = commodity_states[commodity_id] as Dictionary
			commodity_state["warehouse_overflow_units"] = float(
				commodity_state.get("warehouse_overflow_units", 0.0)
			) + removed
			commodity_states[commodity_id] = commodity_state
			_add_flow("warehouse_overflow", commodity_id, removed)
			if excess_kg <= 0.001:
				break
		if excess_kg <= 0.001:
			break
	state["inventory"] = inventory
	state["commodities"] = commodity_states
	region_states[region_id] = state


func _update_employment() -> void:
	var frictional_bp: int = int(
		_policies.get("minimum_frictional_unemployment_bp", 250)
	)
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var population: int = int(state.get("population", 0))
		var labor_force: int = population * int(state.get("labor_force_bp", 4400)) / BASIS_POINTS
		var active_workers: int = 0
		var worker_capacity: int = 0
		for site_id: String in _production_site_ids:
			var site: Dictionary = production_sites[site_id] as Dictionary
			if str(site.get("market_id", "")) != region_id:
				continue
			worker_capacity += int(site.get("workers_capacity", 0))
			active_workers += int(round(
				float(site.get("workers_capacity", 0))
				* float(site.get("last_operating_bp", 0))
				/ float(BASIS_POINTS)
			))
		var nonmodeled: int = labor_force * int(state.get("nonmodeled_employment_bp", 8200)) / BASIS_POINTS
		var production_pressure: int = _region_production_pressure_bp(region_id)
		var shortage_penalty: int = labor_force * production_pressure / BASIS_POINTS / 4
		var employed: int = clampi(nonmodeled + active_workers - shortage_penalty, 0, labor_force)
		var minimum_unemployed: int = labor_force * frictional_bp / BASIS_POINTS
		var unemployed: int = maxi(minimum_unemployed, labor_force - employed)
		employed = maxi(0, labor_force - unemployed)
		state["employment"] = {
			"labor_force": labor_force,
			"employed": employed,
			"unemployed": unemployed,
			"unemployment_bp": 0 if labor_force <= 0 else unemployed * BASIS_POINTS / labor_force,
			"modeled_industry_workers": active_workers,
			"modeled_industry_capacity": worker_capacity,
			"vacancies": maxi(0, worker_capacity - active_workers),
			"production_pressure_bp": production_pressure,
		}
		region_states[region_id] = state


func _supplier_candidates(destination_id: String, commodity_id: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for origin_id: String in _region_ids:
		if origin_id == destination_id:
			continue
		var route: Dictionary = routes.find_route(
			origin_id, destination_id, _spatial_transport_world == null
		)
		if route.is_empty():
			continue
		var relation: Dictionary = {}
		var relation_key: String = ""
		if bool(route.get("cross_border", false)):
			var origin_country: String = str((region_states[origin_id] as Dictionary).get("country_market_id", ""))
			var destination_country: String = str((region_states[destination_id] as Dictionary).get("country_market_id", ""))
			relation_key = origin_country + ">" + destination_country
			relation = catalog.trade_relations.get(relation_key, {}) as Dictionary
			if relation.is_empty() or bool(relation.get("embargo", false)):
				continue
			if float(_trade_quota_remaining.get(relation_key, 0.0)) <= 0.0001:
				continue
		var origin_state: Dictionary = region_states[origin_id] as Dictionary
		var inventory: Dictionary = origin_state.get("inventory", {}) as Dictionary
		var origin_commodity: Dictionary = (
			origin_state.get("commodities", {}) as Dictionary
		).get(commodity_id, {}) as Dictionary
		var target_stock: float = float(origin_commodity.get("target_stock_units", 0.0))
		if target_stock <= 0.0:
			target_stock = _target_stock_for(origin_id, commodity_id)
		var surplus: float = maxf(
			0.0,
			float(inventory.get(commodity_id, 0.0))
			- target_stock * float(_policies.get("reserve_stock_bp", 8500)) / BASIS_POINTS
		)
		if surplus <= 0.0001:
			continue
		var delivered_cost: float = float(
			origin_commodity.get("price_centimes", 1)
		) + float(route.get("cost_centimes_per_unit", 0.0))
		if not relation.is_empty():
			delivered_cost *= 1.0 + float(relation.get("tariff_bp", 0)) / float(BASIS_POINTS)
		candidates.append({
			"origin_market_id": origin_id,
			"surplus": surplus,
			"route": route,
			"relation": relation,
			"relation_key": relation_key,
			"delivered_cost": delivered_cost,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cost: float = float(a.get("delivered_cost", 0.0))
		var b_cost: float = float(b.get("delivered_cost", 0.0))
		if is_equal_approx(a_cost, b_cost):
			return str(a.get("origin_market_id", "")) < str(b.get("origin_market_id", ""))
		return a_cost < b_cost
	)
	return candidates


func _household_demand_for(region_id: String, commodity_id: String, day_index: int = -1) -> float:
	var state: Dictionary = region_states[region_id] as Dictionary
	var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
	var base_rate: float = float(commodity.get("base_daily_units_per_million", 0.0))
	if base_rate <= 0.0:
		return 0.0
	var population: float = float(state.get("population", 0))
	var income_index: float = float(state.get("income_index", 100))
	var income_elasticity: float = float(commodity.get("income_elasticity_bp", 0)) / BASIS_POINTS
	var income_factor: float = clampf(
		1.0 + (income_index - 100.0) / 100.0 * income_elasticity,
		0.25,
		2.5
	)
	var price: float = maxf(1.0, float(
		((state.get("commodities", {}) as Dictionary).get(commodity_id, {}) as Dictionary).get(
			"price_centimes", commodity.get("base_price_centimes", 1)
		)
	))
	var base_price: float = maxf(1.0, float(commodity.get("base_price_centimes", 1)))
	var price_ratio: float = clampf(price / base_price, 0.25, 12.0)
	var price_elasticity: float = float(commodity.get("price_elasticity_bp", 2200)) / BASIS_POINTS
	var price_factor: float = clampf(
		pow(price_ratio, -price_elasticity), 0.12, 2.5
	)
	var modifier: float = float(
		((state.get("demand_modifiers_bp", {}) as Dictionary).get(commodity_id, BASIS_POINTS))
	) / BASIS_POINTS
	var shock_multiplier: float = _active_demand_multiplier(region_id, commodity_id)
	var effective_day: int = _last_day_index + 1 if day_index < 0 else day_index
	var seasonal_factor: float = _seasonal_demand_factor(commodity, effective_day)
	return maxf(
		0.0,
		base_rate * population / POPULATION_UNIT * income_factor * price_factor
		* modifier * shock_multiplier * seasonal_factor
	)


func _seasonal_demand_factor(commodity: Dictionary, day_index: int) -> float:
	var category: String = str(commodity.get("category", ""))
	if not SEASONAL_COMMODITY_CATEGORIES.has(category):
		return 1.0
	var cycle_days: float = maxf(1.0, float(_policies.get("seasonal_cycle_days", 365)))
	var amplitude: float = clampf(
		float(_policies.get("seasonal_demand_amplitude_bp", 450)) / BASIS_POINTS,
		0.0,
		0.25
	)
	var phase: float = fposmod(float(day_index), cycle_days) / cycle_days * PI * 2.0
	return maxf(0.0, 1.0 + amplitude * sin(phase))

func _seasonal_supply_factor(commodity: Dictionary, day_index: int) -> float:
	var category: String = str(commodity.get("category", ""))
	if not SEASONAL_COMMODITY_CATEGORIES.has(category):
		return 1.0
	var cycle_days: float = maxf(1.0, float(_policies.get("seasonal_cycle_days", 365)))
	var amplitude: float = clampf(
		float(_policies.get("seasonal_supply_amplitude_bp", 1400)) / BASIS_POINTS,
		0.0,
		0.25
	)
	var phase: float = fposmod(float(day_index), cycle_days) / cycle_days * PI * 2.0 + PI
	return maxf(0.0, 1.0 + amplitude * sin(phase))

func _baseline_daily_demand(region_id: String, commodity_id: String) -> float:
	var state: Dictionary = region_states[region_id] as Dictionary
	var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
	var base_rate: float = float(commodity.get("base_daily_units_per_million", 0.0))
	if base_rate <= 0.0:
		return 0.0
	var population: float = float(state.get("population", 0))
	var income_index: float = float(state.get("income_index", 100))
	var income_elasticity: float = float(commodity.get("income_elasticity_bp", 0)) / BASIS_POINTS
	var income_factor: float = clampf(
		1.0 + (income_index - 100.0) / 100.0 * income_elasticity, 0.25, 2.5
	)
	var modifier: float = float(
		((state.get("demand_modifiers_bp", {}) as Dictionary).get(commodity_id, BASIS_POINTS))
	) / BASIS_POINTS
	return maxf(0.0, base_rate * population / POPULATION_UNIT * income_factor * modifier)


func _industrial_demand_for(region_id: String, commodity_id: String) -> float:
	var total: float = 0.0
	for site_id: String in _production_site_ids:
		var site: Dictionary = production_sites[site_id] as Dictionary
		if str(site.get("market_id", "")) != region_id:
			continue
		var recipe: Dictionary = catalog.recipes[str(site.get("recipe_id", ""))] as Dictionary
		var batches: float = _desired_batches(site)
		for input: Dictionary in _dictionary_array(recipe.get("inputs", [])):
			if str(input.get("commodity_id", "")) == commodity_id:
				total += float(input.get("units", 0.0)) * batches
	return total


func _daily_output_capacity(region_id: String, commodity_id: String) -> float:
	var total: float = 0.0
	for site_id: String in _production_site_ids:
		var site: Dictionary = production_sites[site_id] as Dictionary
		if str(site.get("market_id", "")) != region_id:
			continue
		var recipe: Dictionary = catalog.recipes[str(site.get("recipe_id", ""))] as Dictionary
		for output: Dictionary in _dictionary_array(recipe.get("outputs", [])):
			if str(output.get("commodity_id", "")) == commodity_id:
				total += float(output.get("units", 0.0)) * _site_capacity(site)
	return total


func _desired_batches(site: Dictionary) -> float:
	return _site_capacity(site) * clampf(
		float(site.get("operating_target_bp", 0.0)) / BASIS_POINTS, 0.0, 1.0
	)


func _site_capacity(site: Dictionary) -> float:
	var scale_bp: float = float(_policies.get("production_capacity_scale_bp", BASIS_POINTS))
	var efficiency_bp: float = float(site.get("technology_efficiency_bp", BASIS_POINTS))
	return maxf(
		0.0,
		float(site.get("capacity_batches_per_day", 0.0))
		* scale_bp / BASIS_POINTS
		* clampf(efficiency_bp / BASIS_POINTS, 0.0, 2.0)
	)


func _target_stock_for(region_id: String, commodity_id: String) -> float:
	var state: Dictionary = region_states[region_id] as Dictionary
	var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
	var demand: float = _household_demand_for(region_id, commodity_id) + _industrial_demand_for(
		region_id, commodity_id
	)
	var days: float = float(commodity.get("target_stock_days", 10)) * float(
		_policies.get("target_stock_days_scale_bp", BASIS_POINTS)
	) / BASIS_POINTS
	return maxf(1.0, demand * days)


func _region_override(source_region_id: String) -> Dictionary:
	for site_id: String in catalog.production_sites:
		var site: Dictionary = catalog.production_sites[site_id] as Dictionary
		if str(site.get("source_region_id", "")) == source_region_id:
			return (site.get("region_override", {}) as Dictionary).duplicate(true)
	return {}


func _recipe_depth(recipe_id: String, depths: Dictionary, visiting: Array[String]) -> int:
	if depths.has(recipe_id):
		return int(depths[recipe_id])
	if visiting.has(recipe_id):
		return 0
	var next_visiting: Array[String] = visiting.duplicate()
	next_visiting.append(recipe_id)
	var recipe: Dictionary = catalog.recipes[recipe_id] as Dictionary
	var depth: int = 0
	for input: Dictionary in _dictionary_array(recipe.get("inputs", [])):
		var input_id: String = str(input.get("commodity_id", ""))
		var source_recipe: String = _recipe_for_output(input_id)
		if not source_recipe.is_empty():
			depth = maxi(depth, _recipe_depth(source_recipe, depths, next_visiting) + 1)
	depths[recipe_id] = depth
	return depth


func _recipe_for_output(commodity_id: String) -> String:
	var candidates: Array[String] = []
	for recipe_id: String in catalog.recipes:
		var recipe: Dictionary = catalog.recipes[recipe_id] as Dictionary
		for output: Dictionary in _dictionary_array(recipe.get("outputs", [])):
			if str(output.get("commodity_id", "")) == commodity_id:
				candidates.append(recipe_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _reset_trade_quotas() -> void:
	_trade_quota_remaining.clear()
	for key: String in catalog.trade_relations:
		_trade_quota_remaining[key] = maxf(
			0.0,
			float((catalog.trade_relations[key] as Dictionary).get("daily_quota_units", 0.0))
		)


func _expire_shocks(day_index: int) -> void:
	var remaining: Array[Dictionary] = []
	for shock: Dictionary in active_shocks:
		if day_index < int(shock.get("end_day", -1)):
			remaining.append(shock)
	active_shocks = remaining


func _active_shock_matches(shock: Dictionary, region_id: String, commodity_id: String, day_index: int) -> bool:
	if (
		str(shock.get("commodity_id", "")) != commodity_id
		or day_index < int(shock.get("start_day", 0))
		or day_index >= int(shock.get("end_day", 0))
	):
		return false
	var market_id: String = str(shock.get("market_id", ""))
	if market_id == region_id:
		return true
	return market_id == str((region_states[region_id] as Dictionary).get("country_market_id", ""))


func _active_supply_multiplier_bp(region_id: String, commodity_id: String, day_index: int) -> int:
	var multiplier: int = BASIS_POINTS
	for shock: Dictionary in active_shocks:
		if _active_shock_matches(shock, region_id, commodity_id, day_index):
			multiplier = multiplier * int(shock.get("supply_multiplier_bp", BASIS_POINTS)) / BASIS_POINTS
	return clampi(multiplier, 0, 40000)


func _active_demand_multiplier(region_id: String, commodity_id: String) -> float:
	var multiplier: float = 1.0
	for shock: Dictionary in active_shocks:
		if _active_shock_matches(shock, region_id, commodity_id, _last_day_index + 1):
			multiplier *= float(shock.get("demand_multiplier_bp", BASIS_POINTS)) / BASIS_POINTS
	return clampf(multiplier, 0.0, 4.0)


func _active_price_modifier_bp(region_id: String, commodity_id: String) -> int:
	var total: int = 0
	for shock: Dictionary in active_shocks:
		if _active_shock_matches(shock, region_id, commodity_id, _last_day_index + 1):
			total += int(shock.get("price_delta_bp", 0))
	return clampi(total, -8000, 15000)


func _region_production_pressure_bp(region_id: String) -> int:
	var state: Dictionary = region_states[region_id] as Dictionary
	var commodity_states: Dictionary = state.get("commodities", {}) as Dictionary
	var maximum: int = 0
	for commodity_id: String in _commodity_ids:
		maximum = maxi(maximum, int((commodity_states[commodity_id] as Dictionary).get("shortage_bp", 0)))
	return maximum


func _warehouse_used_tonnes(state: Dictionary) -> float:
	var kilograms: float = 0.0
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	for commodity_id: String in _commodity_ids:
		var commodity: Dictionary = catalog.commodities[commodity_id] as Dictionary
		kilograms += float(inventory.get(commodity_id, 0.0)) * float(commodity.get("unit_mass_kg", 0.0))
	return kilograms / 1000.0


func _region_snapshot(region_id: String) -> Dictionary:
	var state: Dictionary = region_states.get(region_id, {}) as Dictionary
	if state.is_empty():
		return {}
	var result: Dictionary = state.duplicate(true)
	var inventory: Dictionary = result.get("inventory", {}) as Dictionary
	var commodities: Dictionary = result.get("commodities", {}) as Dictionary
	for commodity_id: String in _commodity_ids:
		var commodity_state: Dictionary = commodities[commodity_id] as Dictionary
		commodity_state["inventory_units"] = float(inventory.get(commodity_id, 0.0))
		commodity_state["in_transit_import_units"] = _in_transit_units_for(
			region_id, commodity_id
		)
		commodity_state["commodity_id"] = commodity_id
		commodity_state["name_zh"] = str((catalog.commodities[commodity_id] as Dictionary).get("name_zh", commodity_id))
		commodities[commodity_id] = commodity_state
	result["commodities"] = commodities
	result["warehouse_used_tonnes"] = _warehouse_used_tonnes(state)
	result["critical_shortages"] = _top_shortages(result, 8)
	result["last_day_index"] = _last_day_index
	return result


func _country_snapshot(country_id: String) -> Dictionary:
	if not _country_ids.has(country_id):
		return {}
	var member_regions: Array[String] = []
	for region_id: String in _region_ids:
		if str((region_states[region_id] as Dictionary).get("country_market_id", "")) == country_id:
			member_regions.append(region_id)
	member_regions.sort()
	var country: Dictionary = catalog.countries[country_id] as Dictionary
	var aggregate: Dictionary = {}
	for commodity_id: String in _commodity_ids:
		var row: Dictionary = _empty_commodity_state(0)
		var demand_weight: float = 0.0
		var inventory_total: float = 0.0
		var in_transit_total: float = 0.0
		for region_id: String in member_regions:
			var state: Dictionary = region_states[region_id] as Dictionary
			var inventory: Dictionary = state.get("inventory", {}) as Dictionary
			var source_row: Dictionary = (state.get("commodities", {}) as Dictionary)[commodity_id] as Dictionary
			for key: String in _metric_names():
				row[key] = float(row.get(key, 0.0)) + float(source_row.get(key, 0.0))
			inventory_total += float(inventory.get(commodity_id, 0.0))
			in_transit_total += _in_transit_units_for(region_id, commodity_id)
			var demand_value: float = float(source_row.get("demand_units", 0.0))
			row["price_centimes"] = int(row.get("price_centimes", 0)) + int(
				float(source_row.get("price_centimes", 0)) * demand_value
			)
			demand_weight += demand_value
		row["price_centimes"] = (
			0 if demand_weight <= 0.0 else int(round(float(row.get("price_centimes", 0)) / demand_weight))
		)
		row["inventory_units"] = inventory_total
		row["in_transit_import_units"] = in_transit_total
		row["commodity_id"] = commodity_id
		row["name_zh"] = str((catalog.commodities[commodity_id] as Dictionary).get("name_zh", commodity_id))
		aggregate[commodity_id] = row
	var population: int = 0
	var employed: int = 0
	var unemployed: int = 0
	for region_id: String in member_regions:
		var state: Dictionary = region_states[region_id] as Dictionary
		population += int(state.get("population", 0))
		var employment: Dictionary = state.get("employment", {}) as Dictionary
		employed += int(employment.get("employed", 0))
		unemployed += int(employment.get("unemployed", 0))
	var summary: Dictionary = {
		"market_id": country_id,
		"market_level": "country",
		"source_country_id": str(country.get("source_country_id", "")),
		"display_name": str(country.get("name", country_id)),
		"member_region_ids": member_regions,
		"population": population,
		"commodities": aggregate,
		"employment": {
			"employed": employed,
			"unemployed": unemployed,
			"unemployment_bp": 0 if employed + unemployed <= 0 else unemployed * BASIS_POINTS / (employed + unemployed),
		},
		"active_shipments": _shipment_count_for_country(country_id),
		"last_day_index": _last_day_index,
	}
	summary["critical_shortages"] = _top_shortages(summary, 8)
	return summary


func _world_summary(day_index: int) -> Dictionary:
	var population: int = 0
	var demand: float = 0.0
	var consumed: float = 0.0
	var unmet: float = 0.0
	var production: float = 0.0
	var inventory: float = 0.0
	var imports: float = 0.0
	var exports: float = 0.0
	var employed: int = 0
	var unemployed: int = 0
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		population += int(state.get("population", 0))
		var employment: Dictionary = state.get("employment", {}) as Dictionary
		employed += int(employment.get("employed", 0))
		unemployed += int(employment.get("unemployed", 0))
		var state_inventory: Dictionary = state.get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			inventory += float(state_inventory.get(commodity_id, 0.0))
			var row: Dictionary = (state.get("commodities", {}) as Dictionary)[commodity_id] as Dictionary
			demand += float(row.get("demand_units", 0.0))
			consumed += float(row.get("consumed_units", 0.0)) + float(row.get("industrial_input_units", 0.0))
			unmet += float(row.get("unmet_units", 0.0))
			production += float(row.get("production_units", 0.0))
			imports += float(row.get("imports_units", 0.0))
			exports += float(row.get("exports_units", 0.0))
	return {
		"day_index": day_index,
		"region_market_count": _region_ids.size(),
		"country_market_count": _country_ids.size(),
		"commodity_count": _commodity_ids.size(),
		"production_site_count": _production_site_ids.size(),
		"population": population,
		"demand_units": demand,
		"consumed_units": consumed,
		"unmet_units": unmet,
		"production_units": production,
		"inventory_units": inventory,
		"imports_units": imports,
		"exports_units": exports,
		"fulfillment_bp": 0 if demand <= 0.0 else int(round(clampf(consumed / demand, 0.0, 1.0) * BASIS_POINTS)),
		"employment": {
			"employed": employed,
			"unemployed": unemployed,
			"unemployment_bp": 0 if employed + unemployed <= 0 else unemployed * BASIS_POINTS / (employed + unemployed),
		},
		"active_shipments": shipments.size(),
		"completed_shipments": shipment_history.size(),
		"critical_shortages": _top_world_shortages(8),
	}


func _history_entry(day_index: int) -> Dictionary:
	var market_values: Dictionary = {}
	for region_id: String in _region_ids:
		market_values[region_id] = _compact_market_values(_region_snapshot(region_id))
	for country_id: String in _country_ids:
		market_values[country_id] = _compact_market_values(_country_snapshot(country_id))
	return {"day_index": day_index, "markets": market_values}


func _compact_market_values(market: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var commodities: Dictionary = market.get("commodities", {}) as Dictionary
	for commodity_id: String in _commodity_ids:
		var source: Dictionary = commodities.get(commodity_id, {}) as Dictionary
		values[commodity_id] = {
			"price_centimes": int(source.get("price_centimes", 0)),
			"inventory_units": float(source.get("inventory_units", 0.0)),
			"supply_units": float(source.get("supply_units", 0.0)),
			"demand_units": float(source.get("demand_units", 0.0)),
			"production_units": float(source.get("production_units", 0.0)),
			"imports_units": float(source.get("imports_units", 0.0)),
			"exports_units": float(source.get("exports_units", 0.0)),
			"unmet_units": float(source.get("unmet_units", 0.0)),
			"in_transit_import_units": float(source.get("in_transit_import_units", 0.0)),
		}
	return values


func _top_shortages(market: Dictionary, limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var commodities: Dictionary = market.get("commodities", {}) as Dictionary
	for commodity_id: String in commodities:
		var row: Dictionary = commodities[commodity_id] as Dictionary
		var unmet: float = float(row.get("unmet_units", 0.0))
		if unmet > 0.0001:
			rows.append({
				"commodity_id": commodity_id,
				"name_zh": str(row.get("name_zh", commodity_id)),
				"unmet_units": unmet,
				"demand_units": float(row.get("demand_units", 0.0)),
				"shortage_bp": int(row.get("shortage_bp", 0)),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("shortage_bp", 0)) == int(b.get("shortage_bp", 0)):
			return str(a.get("commodity_id", "")) < str(b.get("commodity_id", ""))
		return int(a.get("shortage_bp", 0)) > int(b.get("shortage_bp", 0))
	)
	if rows.size() > limit:
		rows.resize(limit)
	return rows


func _top_world_shortages(limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var commodities: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var row: Dictionary = commodities[commodity_id] as Dictionary
			var unmet: float = float(row.get("unmet_units", 0.0))
			if unmet > 0.0001:
				rows.append({
					"market_id": region_id,
					"commodity_id": commodity_id,
					"unmet_units": unmet,
					"shortage_bp": int(row.get("shortage_bp", 0)),
				})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("shortage_bp", 0)) == int(b.get("shortage_bp", 0)):
			var a_key: String = str(a.get("market_id", "")) + str(a.get("commodity_id", ""))
			var b_key: String = str(b.get("market_id", "")) + str(b.get("commodity_id", ""))
			return a_key < b_key
		return int(a.get("shortage_bp", 0)) > int(b.get("shortage_bp", 0))
	)
	if rows.size() > limit:
		rows.resize(limit)
	return rows


func _shipment_count_for_country(country_id: String) -> int:
	var count: int = 0
	for shipment: Dictionary in shipments:
		var origin: String = str(shipment.get("origin_market_id", ""))
		var destination: String = str(shipment.get("destination_market_id", ""))
		if (
			str((region_states.get(origin, {}) as Dictionary).get("country_market_id", "")) == country_id
			or str((region_states.get(destination, {}) as Dictionary).get("country_market_id", "")) == country_id
		):
			count += 1
	return count


func _validate_region_state(state: Dictionary) -> bool:
	if (
		state.is_empty()
		or not state.get("inventory", {}) is Dictionary
		or not state.get("commodities", {}) is Dictionary
	):
		return false
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	var commodities: Dictionary = state.get("commodities", {}) as Dictionary
	if inventory.size() != _commodity_ids.size() or commodities.size() != _commodity_ids.size():
		return false
	for commodity_id: String in _commodity_ids:
		if not inventory.has(commodity_id) or not commodities.has(commodity_id):
			return false
		var units: float = float(inventory[commodity_id])
		if is_nan(units) or is_inf(units) or units < -0.000001:
			return false
		var row: Dictionary = commodities[commodity_id] as Dictionary
		var price: float = float(row.get("price_centimes", 0))
		if is_nan(price) or is_inf(price) or price < MIN_PRICE_CENTIMES:
			return false
		for metric_name: String in _metric_names():
			var value: float = float(row.get(metric_name, 0.0))
			if is_nan(value) or is_inf(value) or value < -0.000001:
				return false
	return true


func _validate_candidate_regions(candidate: Dictionary) -> bool:
	for region_id: String in _region_ids:
		if not candidate.has(region_id) or not _validate_region_state(candidate[region_id] as Dictionary):
			return false
	return true


func _erase_legacy_in_transit_observations(candidate: Dictionary) -> void:
	for region_id: String in _region_ids:
		if not candidate.has(region_id):
			continue
		var state: Dictionary = candidate[region_id] as Dictionary
		var commodities: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			if not commodities.has(commodity_id):
				continue
			var row: Dictionary = commodities[commodity_id] as Dictionary
			row.erase("in_transit_import_units")
			commodities[commodity_id] = row
		state["commodities"] = commodities
		candidate[region_id] = state


func _validate_candidate_shipments(candidate: Array[Dictionary]) -> bool:
	var seen_ids: Dictionary = {}
	for shipment: Dictionary in candidate:
		var shipment_id: String = str(shipment.get("shipment_id", ""))
		if seen_ids.has(shipment_id):
			return false
		seen_ids[shipment_id] = true
		if (
			shipment_id.is_empty()
			or float(shipment.get("units", 0.0)) <= 0.0
			or not _shipment_progress_is_conserved(shipment)
			or int(shipment.get("arrival_day", -1)) <= int(shipment.get("dispatch_day", -1))
			or not region_states.has(str(shipment.get("origin_market_id", "")))
			or not region_states.has(str(shipment.get("destination_market_id", "")))
			or not catalog.commodities.has(str(shipment.get("commodity_id", "")))
		):
			return false
	return true


func _normalize_candidate_shipments(candidate: Array[Dictionary]) -> void:
	for shipment: Dictionary in candidate:
		var outstanding: float = maxf(0.0, float(shipment.get("units", 0.0)))
		var delivered: float = maxf(0.0, float(shipment.get("delivered_units", 0.0)))
		var total: float = float(shipment.get("total_units", outstanding + delivered))
		if not shipment.has("total_units"):
			shipment["total_units"] = total
		if not shipment.has("delivered_units"):
			shipment["delivered_units"] = delivered
		if not shipment.has("progress_units"):
			shipment["progress_units"] = delivered
		if not shipment.has("last_progress_day"):
			shipment["last_progress_day"] = int(shipment.get("dispatch_day", -1))
		if not shipment.has("transport_demand_units"):
			shipment["transport_demand_units"] = total
		if not shipment.has("status"):
			shipment["status"] = "in_transit"
func _canonicalize_snapshot_value(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key: Variant in dictionary:
			dictionary[key] = _canonicalize_snapshot_value(dictionary[key])
		return dictionary
	if value is Array:
		var array: Array = value as Array
		for index: int in range(array.size()):
			array[index] = _canonicalize_snapshot_value(array[index])
		return array
	if typeof(value) == TYPE_FLOAT:
		var numeric_value: float = float(value)
		if is_nan(numeric_value) or is_inf(numeric_value):
			return numeric_value
		return snappedf(numeric_value, SNAPSHOT_FLOAT_QUANTUM)
	return value


func _normalize_candidate_numeric_types(
	candidate_regions: Dictionary,
	candidate_sites: Dictionary,
	candidate_shipments: Array[Dictionary],
	candidate_shipment_history: Array[Dictionary],
	candidate_history: Array[Dictionary]
) -> void:
	for region_id: String in candidate_regions:
		var state: Dictionary = candidate_regions[region_id] as Dictionary
		state["population"] = int(state.get("population", 0))
		state["labor_force_bp"] = int(state.get("labor_force_bp", 0))
		state["nonmodeled_employment_bp"] = int(state.get("nonmodeled_employment_bp", 0))
		var employment: Dictionary = state.get("employment", {}) as Dictionary
		for key: String in ["labor_force", "employed", "unemployed", "unemployment_bp", "modeled_industry_workers", "modeled_industry_capacity", "vacancies", "production_pressure_bp"]:
			if employment.has(key):
				employment[key] = int(employment[key])
		state["employment"] = employment
		var demand_modifiers: Dictionary = state.get("demand_modifiers_bp", {}) as Dictionary
		for commodity_id: String in demand_modifiers:
			demand_modifiers[commodity_id] = int(demand_modifiers[commodity_id])
		state["demand_modifiers_bp"] = demand_modifiers
		var commodities: Dictionary = state.get("commodities", {}) as Dictionary
		for commodity_id: String in commodities:
			var commodity: Dictionary = commodities[commodity_id] as Dictionary
			for key: String in ["price_centimes", "target_price_centimes", "inventory_coverage_bp", "shortage_bp"]:
				if commodity.has(key):
					commodity[key] = int(commodity[key])
			commodities[commodity_id] = commodity
		state["commodities"] = commodities
		candidate_regions[region_id] = state
	for site_id: String in candidate_sites:
		var site: Dictionary = candidate_sites[site_id] as Dictionary
		for key: String in ["last_operating_bp", "last_input_shortage_bp"]:
			if site.has(key):
				site[key] = int(site[key])
		candidate_sites[site_id] = site
	_normalize_shipment_numeric_types(candidate_shipments, false)
	_normalize_shipment_numeric_types(candidate_shipment_history, true)
	for entry: Dictionary in candidate_history:
		entry["day_index"] = int(entry.get("day_index", -1))
		var markets: Dictionary = entry.get("markets", {}) as Dictionary
		for market_id: String in markets:
			var market: Dictionary = markets[market_id] as Dictionary
			for commodity_id: String in market:
				var commodity: Dictionary = market[commodity_id] as Dictionary
				for key: String in ["price_centimes", "inventory_coverage_bp", "shortage_bp"]:
					if commodity.has(key):
						commodity[key] = int(commodity[key])
				for key: String in [
					"demand_units", "inventory_units", "supply_units", "production_units",
					"imports_units", "exports_units", "unmet_units", "in_transit_import_units"
				]:
					if commodity.has(key):
						commodity[key] = float(commodity[key])
				market[commodity_id] = commodity
			markets[market_id] = market
		entry["markets"] = markets


func _normalize_candidate_flow_totals(candidate: Dictionary) -> void:
	for flow_name: String in [
		"initial_inventory", "production", "industrial_inputs",
		"household_consumption", "spoilage", "warehouse_overflow"
	]:
		var values: Dictionary = candidate.get(flow_name, {}) as Dictionary
		for commodity_id: String in values:
			values[commodity_id] = float(values[commodity_id])
		candidate[flow_name] = values


func _normalize_candidate_quota_types(candidate: Dictionary) -> void:
	for relation_key: String in candidate:
		candidate[relation_key] = float(candidate[relation_key])


func _normalize_shipment_numeric_types(
	collection: Array[Dictionary], include_delivered_day: bool
) -> void:
	for shipment: Dictionary in collection:
		for key: String in ["dispatch_day", "arrival_day", "duration_hours", "last_progress_day", "spatial_window_hour"]:
			if shipment.has(key):
				shipment[key] = int(shipment[key])
		if include_delivered_day and shipment.has("delivered_day"):
			shipment["delivered_day"] = int(shipment["delivered_day"])
		for key: String in ["goods_value_centimes", "freight_cost_centimes", "tariff_centimes", "landed_cost_centimes"]:
			if shipment.has(key):
				shipment[key] = int(shipment[key])


func _shipment_progress_is_conserved(shipment: Dictionary) -> bool:
	var outstanding: float = float(shipment.get("units", 0.0))
	var total: float = float(shipment.get("total_units", -1.0))
	var delivered: float = float(shipment.get("delivered_units", -1.0))
	var progress: float = float(shipment.get("progress_units", -1.0))
	if (
		is_nan(outstanding) or is_inf(outstanding) or outstanding < -0.000001
		or is_nan(total) or is_inf(total) or total <= 0.0
		or is_nan(delivered) or is_inf(delivered) or delivered < -0.000001
		or is_nan(progress) or is_inf(progress) or progress < -0.000001
	):
		return false
	return (
		is_equal_approx(delivered, progress)
		and absf(total - outstanding - delivered) <= 0.000001
		and delivered <= total + 0.000001
	)


func _validate_candidate_flow_totals(candidate: Dictionary) -> bool:
	for flow_name: String in [
		"initial_inventory", "production", "industrial_inputs",
		"household_consumption", "spoilage", "warehouse_overflow"
	]:
		if not candidate.get(flow_name, {}) is Dictionary:
			return false
		var values: Dictionary = candidate[flow_name] as Dictionary
		for commodity_id: String in _commodity_ids:
			var value: float = float(values.get(commodity_id, -1.0))
			if is_nan(value) or is_inf(value) or value < -0.000001:
				return false
	return true


func _validate_physical_conservation() -> bool:
	var initial: Dictionary = flow_totals.get("initial_inventory", {}) as Dictionary
	var actual: Dictionary = {}
	for commodity_id: String in _commodity_ids:
		actual[commodity_id] = 0.0
	for region_id: String in _region_ids:
		var inventory: Dictionary = (region_states[region_id] as Dictionary).get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			actual[commodity_id] = float(actual[commodity_id]) + float(inventory.get(commodity_id, 0.0))
	for shipment: Dictionary in shipments:
		var commodity_id: String = str(shipment.get("commodity_id", ""))
		actual[commodity_id] = float(actual.get(commodity_id, 0.0)) + float(shipment.get("units", 0.0))
	for commodity_id: String in _commodity_ids:
		var expected: float = float(initial.get(commodity_id, 0.0))
		for flow_name: String in ["production"]:
			expected += float((flow_totals.get(flow_name, {}) as Dictionary).get(commodity_id, 0.0))
		for flow_name: String in [
			"industrial_inputs", "household_consumption", "spoilage", "warehouse_overflow"
		]:
			expected -= float((flow_totals.get(flow_name, {}) as Dictionary).get(commodity_id, 0.0))
		if absf(float(actual.get(commodity_id, 0.0)) - expected) > 0.05:
			return false
	return true


func _empty_commodity_state(base_price: int) -> Dictionary:
	var state: Dictionary = {
		"price_centimes": maxi(MIN_PRICE_CENTIMES, base_price),
		"target_price_centimes": maxi(MIN_PRICE_CENTIMES, base_price),
		"target_stock_units": 0.0,
		"inventory_opening_units": 0.0,
		"inventory_end_units": 0.0,
		"inventory_coverage_bp": 0,
	}
	for metric_name: String in _metric_names():
		state[metric_name] = 0.0
	return state


func _metric_names() -> Array[String]:
	return [
		"supply_units", "demand_units", "household_demand_units",
		"industrial_demand_units", "production_units", "industrial_input_units",
		"consumed_units", "unmet_units", "imports_units", "exports_units",
		"spoilage_units", "warehouse_overflow_units",
	]


func _add_flow(flow_name: String, commodity_id: String, amount: float) -> void:
	if amount <= 0.000001:
		return
	var values: Dictionary = flow_totals.get(flow_name, {}) as Dictionary
	values[commodity_id] = float(values.get(commodity_id, 0.0)) + amount
	flow_totals[flow_name] = values


func _shock_by_id(shock_id: String) -> Dictionary:
	for shock: Dictionary in active_shocks:
		if str(shock.get("shock_id", "")) == shock_id:
			return shock
	return {}


func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for raw_key: Variant in source:
		keys.append(str(raw_key))
	keys.sort()
	return keys


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result




func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


func _fail_result(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}


func _fail(message: String) -> bool:
	initialization_error = message
	return false


func _apply_shipment_delivery(index: int, delivered_units: float, day_index: int) -> void:
	if index < 0 or index >= shipments.size() or delivered_units <= 0.000001:
		return
	var shipment: Dictionary = shipments[index] as Dictionary
	var destination_id: String = str(shipment.get("destination_market_id", ""))
	var commodity_id: String = str(shipment.get("commodity_id", ""))
	var units: float = minf(
		delivered_units, maxf(0.0, float(shipment.get("units", 0.0)))
	)
	if region_states.has(destination_id) and units > 0.0:
		var state: Dictionary = region_states[destination_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + units
		var commodity_state: Dictionary = (
			state.get("commodities", {}) as Dictionary
		).get(commodity_id, {}) as Dictionary
		commodity_state["imports_units"] = float(commodity_state.get("imports_units", 0.0)) + units
		commodity_state["supply_units"] = float(commodity_state.get("supply_units", 0.0)) + units
		(state.get("commodities", {}) as Dictionary)[commodity_id] = commodity_state
		state["inventory"] = inventory
		region_states[destination_id] = state
	shipment["units"] = maxf(0.0, float(shipment.get("units", 0.0)) - units)
	shipment["delivered_units"] = float(shipment.get("delivered_units", 0.0)) + units
	shipment["progress_units"] = float(shipment.get("progress_units", 0.0)) + units
	shipment["last_progress_day"] = day_index
	if float(shipment.get("units", 0.0)) <= 0.000001:
		shipment["units"] = 0.0
		shipment["status"] = "delivered"
		shipment["delivered_day"] = day_index
		shipment_history.append(shipment.duplicate(true))
		shipments.remove_at(index)
	else:
		shipment["status"] = "in_transit"
		shipments[index] = shipment
