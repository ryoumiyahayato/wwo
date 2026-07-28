class_name AlphaCommodityMarketService
extends RefCounted
## Population-linked 1900 commodity, warehouse, production and trade simulation.
## Runs only at day boundaries; detailed persons remain under AlphaLaborService.

const BASIS_POINTS: int = 10000
const POPULATION_UNIT: int = 1_000_000
const HISTORY_LIMIT: int = 96
const IMPORTABLE_CLASSES: Array[String] = [
	"global_bulk", "international_specialty", "regional_mass", "luxury",
]
const EXPORTABLE_CLASSES: Array[String] = [
	"global_bulk", "international_specialty", "luxury",
]

var commodities: Dictionary = {}
var recipes: Dictionary = {}
var production_sites: Dictionary = {}
var region_states: Dictionary = {}
var international_market: Dictionary = {}
var active_shocks: Array[Dictionary] = []
var history: Array[Dictionary] = []
var initialization_error: String = ""
var _commodity_ids: Array[String] = []
var _region_ids: Array[String] = []
var _processed_keys: Dictionary = {}
var _last_day_index: int = -1
var _policies: Dictionary = {}


func configure(config: AlphaConfig) -> bool:
	commodities.clear()
	recipes.clear()
	production_sites.clear()
	region_states.clear()
	international_market.clear()
	active_shocks.clear()
	history.clear()
	_commodity_ids.clear()
	_region_ids.clear()
	_processed_keys.clear()
	_last_day_index = -1
	initialization_error = ""
	var document: Dictionary = config.commodity_market()
	if str(document.get("schema_id", "")) != "alpha_commodity_market_1900_v1":
		return _fail_initialize("1900商品市场配置 Schema 无效")
	_policies = (document.get("policies", {}) as Dictionary).duplicate(true)
	for raw_commodity: Variant in document.get("commodities", []) as Array:
		if not raw_commodity is Dictionary:
			return _fail_initialize("商品记录格式无效")
		var commodity: Dictionary = (raw_commodity as Dictionary).duplicate(true)
		var commodity_id: String = str(commodity.get("commodity_id", ""))
		if commodity_id.is_empty() or commodities.has(commodity_id):
			return _fail_initialize("商品 ID 缺失或重复：%s" % commodity_id)
		commodities[commodity_id] = commodity
		_commodity_ids.append(commodity_id)
	_commodity_ids.sort()
	for raw_recipe: Variant in document.get("recipes", []) as Array:
		if not raw_recipe is Dictionary:
			return _fail_initialize("生产配方格式无效")
		var recipe: Dictionary = (raw_recipe as Dictionary).duplicate(true)
		var recipe_id: String = str(recipe.get("recipe_id", ""))
		if recipe_id.is_empty() or recipes.has(recipe_id):
			return _fail_initialize("生产配方 ID 缺失或重复：%s" % recipe_id)
		recipes[recipe_id] = recipe
	for raw_region: Variant in config.region_profiles():
		if not raw_region is Dictionary:
			continue
		_initialize_region(raw_region as Dictionary, document)
	for raw_site: Variant in document.get("production_sites", []) as Array:
		if not raw_site is Dictionary:
			return _fail_initialize("生产设施格式无效")
		var site: Dictionary = (raw_site as Dictionary).duplicate(true)
		var site_id: String = str(site.get("site_id", ""))
		var region_id: String = str(site.get("region_id", ""))
		var recipe_id: String = str(site.get("recipe_id", ""))
		if (
			site_id.is_empty()
			or production_sites.has(site_id)
			or not region_states.has(region_id)
			or not recipes.has(recipe_id)
		):
			return _fail_initialize("生产设施引用无效：%s" % site_id)
		site["last_batches"] = 0.0
		site["operating_target_bp"] = int(site.get("opening_operating_bp", BASIS_POINTS))
		site["last_operating_bp"] = 0
		production_sites[site_id] = site
	_initialize_international_market(document)
	_seed_opening_stocks()
	var integrity: Dictionary = validate_integrity()
	if not bool(integrity.get("success", false)):
		return _fail_initialize(str(integrity.get("message", "商品市场完整性失败")))
	return true


func settle_day(total_hour: int) -> Dictionary:
	var day_index: int = total_hour / 24
	if day_index <= _last_day_index:
		return _ok({"duplicate": true, "day_index": day_index})
	_expire_shocks(total_hour)
	_reset_daily_metrics()
	_apply_spoilage()
	_reset_local_services()
	_run_production(total_hour)
	_run_local_consumption()
	_run_regional_balancing()
	_run_international_market()
	_enforce_all_warehouse_capacity()
	_update_prices()
	_update_employment()
	_last_day_index = day_index
	var summary: Dictionary = world_summary()
	summary["day_index"] = day_index
	summary["total_hour"] = total_hour
	history.append(summary.duplicate(true))
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	return _ok(summary)


func daily_household_demand(
	region_id: String,
	commodity_id: String,
	population_override: int = -1,
	income_index_override: int = -1
) -> float:
	var state: Dictionary = region_states.get(region_id, {}) as Dictionary
	var commodity: Dictionary = commodities.get(commodity_id, {}) as Dictionary
	if state.is_empty() or commodity.is_empty():
		return 0.0
	var rate: float = float(commodity.get("base_daily_units_per_million", 0.0))
	if rate <= 0.0:
		return 0.0
	var population: int = (
		population_override if population_override >= 0
		else int(state.get("population", 0))
	)
	var income_index: int = (
		income_index_override if income_index_override >= 0
		else int(state.get("income_index", 100))
	)
	var elasticity_bp: int = int(commodity.get("income_elasticity_bp", 0))
	var income_delta_bp: int = (income_index - 100) * 100
	var income_multiplier_bp: int = clampi(
		BASIS_POINTS + income_delta_bp * elasticity_bp / BASIS_POINTS,
		2500,
		30000
	)
	var modifiers: Dictionary = state.get("demand_modifiers_bp", {}) as Dictionary
	var region_modifier_bp: int = int(modifiers.get(commodity_id, BASIS_POINTS))
	return maxf(
		0.0,
		rate * float(population) / float(POPULATION_UNIT)
		* float(income_multiplier_bp) / float(BASIS_POINTS)
		* float(region_modifier_bp) / float(BASIS_POINTS)
	)


func inventory_units(region_id: String, commodity_id: String) -> float:
	var state: Dictionary = region_states.get(region_id, {}) as Dictionary
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	return float(inventory.get(commodity_id, 0.0))


func set_inventory(region_id: String, commodity_id: String, units: float) -> bool:
	if units < 0.0 or not region_states.has(region_id) or not commodities.has(commodity_id):
		return false
	var state: Dictionary = region_states[region_id] as Dictionary
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	inventory[commodity_id] = units
	state["inventory"] = inventory
	region_states[region_id] = state
	return true


func market_price(region_id: String, commodity_id: String) -> int:
	var state: Dictionary = region_states.get(region_id, {}) as Dictionary
	var prices: Dictionary = state.get("prices", {}) as Dictionary
	return int(prices.get(commodity_id, 0))


func apply_market_shock(
	idempotency_key: String,
	region_id: String,
	commodity_id: String,
	price_delta_bp: int,
	supply_delta_bp: int,
	duration_days: int,
	cause: String,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true})
	if (
		idempotency_key.is_empty()
		or not region_states.has(region_id)
		or not commodities.has(commodity_id)
		or duration_days <= 0
		or price_delta_bp < -9000
		or supply_delta_bp < -9000
	):
		return _fail("invalid_market_shock", "市场冲击参数或引用无效")
	active_shocks.append({
		"shock_id": "commodity_shock:%d" % active_shocks.size(),
		"region_id": region_id,
		"commodity_id": commodity_id,
		"price_delta_bp": price_delta_bp,
		"supply_delta_bp": supply_delta_bp,
		"cause": cause,
		"start_hour": total_hour,
		"end_hour": total_hour + duration_days * 24,
	})
	_processed_keys[idempotency_key] = true
	return _ok({"active_shock_count": active_shocks.size()})


func region_report(region_id: String) -> Dictionary:
	var state: Dictionary = region_states.get(region_id, {}) as Dictionary
	if state.is_empty():
		return {}
	var report: Dictionary = state.duplicate(true)
	report["warehouse_used_tonnes"] = _warehouse_used_tonnes(state)
	return report


func world_summary() -> Dictionary:
	var population: int = 0
	var labor_force: int = 0
	var employed: int = 0
	var unemployed: int = 0
	var demand_units: float = 0.0
	var consumed_units: float = 0.0
	var unmet_units: float = 0.0
	var imports: float = 0.0
	var exports: float = 0.0
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		population += int(state.get("population", 0))
		var employment: Dictionary = state.get("employment", {}) as Dictionary
		labor_force += int(employment.get("labor_force", 0))
		employed += int(employment.get("employed", 0))
		unemployed += int(employment.get("unemployed", 0))
		var totals: Dictionary = (state.get("daily_metrics", {}) as Dictionary).get(
			"totals", {}
		) as Dictionary
		demand_units += float(totals.get("household_demand_units", 0.0))
		consumed_units += float(totals.get("household_consumed_units", 0.0))
		unmet_units += float(totals.get("unmet_units", 0.0))
		imports += float(totals.get("international_import_units", 0.0))
		exports += float(totals.get("international_export_units", 0.0))
	return {
		"population": population,
		"commodity_count": commodities.size(),
		"luxury_commodity_count": _category_count("luxury"),
		"production_site_count": production_sites.size(),
		"region_count": region_states.size(),
		"labor_force": labor_force,
		"employed": employed,
		"unemployed": unemployed,
		"unemployment_bp": (
			0 if labor_force <= 0 else unemployed * BASIS_POINTS / labor_force
		),
		"household_demand_units": demand_units,
		"household_consumed_units": consumed_units,
		"unmet_units": unmet_units,
		"fulfillment_bp": (
			BASIS_POINTS
			if demand_units <= 0.0
			else int(round(consumed_units * BASIS_POINTS / demand_units))
		),
		"international_import_units": imports,
		"international_export_units": exports,
		"active_shock_count": active_shocks.size(),
	}


func validate_integrity() -> Dictionary:
	if commodities.size() < 50 or recipes.size() < 20 or region_states.size() != 8:
		return _fail("market_scope_incomplete", "商品、配方或地区覆盖不足")
	for commodity_id: String in _commodity_ids:
		var commodity: Dictionary = commodities[commodity_id] as Dictionary
		if (
			float(commodity.get("unit_mass_kg", -1.0)) < 0.0
			or int(commodity.get("base_price_centimes", 0)) <= 0
			or str(commodity.get("trade_class", "")).is_empty()
		):
			return _fail("commodity_invalid", "商品参数无效：%s" % commodity_id)
	for raw_recipe: Variant in recipes.values():
		var recipe: Dictionary = raw_recipe as Dictionary
		for field: String in ["inputs", "outputs"]:
			for raw_flow: Variant in recipe.get(field, []) as Array:
				if not raw_flow is Dictionary:
					return _fail("recipe_flow_invalid", "生产配方流格式无效")
				var flow: Dictionary = raw_flow as Dictionary
				if (
					not commodities.has(str(flow.get("commodity_id", "")))
					or float(flow.get("units", 0.0)) <= 0.0
				):
					return _fail("recipe_reference_invalid", "生产配方引用无效")
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var prices: Dictionary = state.get("prices", {}) as Dictionary
		if inventory.size() != commodities.size() or prices.size() != commodities.size():
			return _fail("regional_catalog_incomplete", "地区商品目录不完整：%s" % region_id)
		for commodity_id: String in _commodity_ids:
			if float(inventory.get(commodity_id, -1.0)) < -0.0001:
				return _fail("negative_inventory", "地区库存为负：%s/%s" % [region_id, commodity_id])
			if int(prices.get(commodity_id, 0)) <= 0:
				return _fail("invalid_price", "地区价格无效：%s/%s" % [region_id, commodity_id])
	return _ok({
		"commodities": commodities.size(),
		"recipes": recipes.size(),
		"production_sites": production_sites.size(),
		"regions": region_states.size(),
	})


func get_persistent_state() -> Dictionary:
	return {
		"region_states": region_states.duplicate(true),
		"production_sites": production_sites.duplicate(true),
		"international_market": international_market.duplicate(true),
		"active_shocks": active_shocks.duplicate(true),
		"history": history.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"last_day_index": _last_day_index,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("region_states", {}) is Dictionary
		or not state.get("production_sites", {}) is Dictionary
		or not state.get("international_market", {}) is Dictionary
		or not state.get("active_shocks", []) is Array
		or not state.get("history", []) is Array
	):
		return false
	var restored_regions: Dictionary = (state["region_states"] as Dictionary).duplicate(true)
	if restored_regions.size() != region_states.size():
		return false
	for region_id: String in _region_ids:
		if not restored_regions.has(region_id):
			return false
	region_states = restored_regions
	production_sites = (state["production_sites"] as Dictionary).duplicate(true)
	international_market = (state["international_market"] as Dictionary).duplicate(true)
	active_shocks = DataRecordUtils.to_dictionary_array(state["active_shocks"])
	history = DataRecordUtils.to_dictionary_array(state["history"])
	_processed_keys = (state.get("processed_keys", {}) as Dictionary).duplicate(true)
	_last_day_index = int(state.get("last_day_index", -1))
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	return bool(validate_integrity().get("success", false))


func _initialize_region(region: Dictionary, document: Dictionary) -> void:
	var region_id: String = str(region.get("region_id", ""))
	if region_id.is_empty():
		return
	var overrides: Dictionary = (
		(document.get("region_overrides", {}) as Dictionary).get(region_id, {})
		as Dictionary
	)
	var inventory: Dictionary = {}
	var prices: Dictionary = {}
	for commodity_id: String in _commodity_ids:
		inventory[commodity_id] = 0.0
		prices[commodity_id] = int(
			(commodities[commodity_id] as Dictionary).get("base_price_centimes", 1)
		)
	var living_cost_index: int = maxi(1, int(region.get("living_cost_index", 100)))
	var wage_index: int = maxi(1, int(region.get("wage_index", 100)))
	var income_index: int = clampi(wage_index * 100 / living_cost_index, 45, 180)
	region_states[region_id] = {
		"region_id": region_id,
		"country_id": str(region.get("country_id", "")),
		"population": int(region.get("population", 0)),
		"income_index": income_index,
		"warehouse_capacity_tonnes": float(overrides.get("warehouse_capacity_tonnes", 100000.0)),
		"import_capacity_units_per_day": float(overrides.get("import_capacity_units_per_day", 250.0)),
		"export_capacity_units_per_day": float(overrides.get("export_capacity_units_per_day", 250.0)),
		"labor_force_bp": int(overrides.get("labor_force_bp", 4400)),
		"nonmodeled_employment_bp": int(overrides.get("nonmodeled_employment_bp", 8200)),
		"demand_modifiers_bp": (
			overrides.get("demand_modifiers_bp", {}) as Dictionary
		).duplicate(true),
		"inventory": inventory,
		"prices": prices,
		"employment": {},
		"daily_metrics": _empty_metrics(),
	}
	_region_ids.append(region_id)
	_region_ids.sort()


func _initialize_international_market(document: Dictionary) -> void:
	var pool: Dictionary = {}
	var reference_prices: Dictionary = {}
	for commodity_id: String in _commodity_ids:
		var commodity: Dictionary = commodities[commodity_id] as Dictionary
		pool[commodity_id] = float(commodity.get("international_liquidity_units", 0.0))
		reference_prices[commodity_id] = int(commodity.get("base_price_centimes", 1))
	international_market = {
		"inventory": pool,
		"reference_prices": reference_prices,
		"policy": (document.get("international_market", {}) as Dictionary).duplicate(true),
		"cumulative_import_units": 0.0,
		"cumulative_export_units": 0.0,
	}


func _seed_opening_stocks() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = commodities[commodity_id] as Dictionary
			var target_days: int = int(commodity.get("target_stock_days", 10))
			var demand: float = daily_household_demand(region_id, commodity_id)
			var industrial_need: float = _daily_industrial_input_need(region_id, commodity_id)
			var local_output: float = _daily_output_capacity(region_id, commodity_id)
			var seed: float = (demand + industrial_need) * float(target_days)
			if local_output > 0.0:
				seed += minf(local_output * 12.0, maxf(0.0, seed * 0.5))
			if str(commodity.get("trade_class", "")) == "local_service":
				seed = 0.0
			inventory[commodity_id] = maxf(0.0, seed)
		state["inventory"] = inventory
		region_states[region_id] = state
		_enforce_warehouse_capacity(region_id)
	_update_employment()


func _reset_daily_metrics() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		state["daily_metrics"] = _empty_metrics()
		region_states[region_id] = state


func _empty_metrics() -> Dictionary:
	return {
		"demand": {},
		"consumed": {},
		"unmet": {},
		"produced": {},
		"industrial_inputs": {},
		"regional_received": {},
		"regional_sent": {},
		"international_imports": {},
		"international_exports": {},
		"spoiled": {},
		"warehouse_overflow": {},
		"workers_active": 0,
		"workers_capacity": 0,
		"production_utilization_bp": 0,
		"totals": {
			"household_demand_units": 0.0,
			"household_consumed_units": 0.0,
			"unmet_units": 0.0,
			"international_import_units": 0.0,
			"international_export_units": 0.0,
		},
	}


func _reset_local_services() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			if str((commodities[commodity_id] as Dictionary).get("trade_class", "")) == "local_service":
				inventory[commodity_id] = 0.0
		state["inventory"] = inventory
		region_states[region_id] = state


func _apply_spoilage() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		var spoiled: Dictionary = metrics.get("spoiled", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var rate_bp: int = int((commodities[commodity_id] as Dictionary).get("spoilage_bp_per_day", 0))
			if rate_bp <= 0:
				continue
			var before: float = float(inventory.get(commodity_id, 0.0))
			var loss: float = before * float(rate_bp) / float(BASIS_POINTS)
			if loss > 0.0001:
				inventory[commodity_id] = maxf(0.0, before - loss)
				spoiled[commodity_id] = loss
		metrics["spoiled"] = spoiled
		state["inventory"] = inventory
		state["daily_metrics"] = metrics
		region_states[region_id] = state


func _run_production(total_hour: int) -> void:
	var site_ids: Array[String] = []
	for raw_id: Variant in production_sites:
		site_ids.append(str(raw_id))
	site_ids.sort()
	for site_id: String in site_ids:
		var site: Dictionary = production_sites[site_id] as Dictionary
		var region_id: String = str(site.get("region_id", ""))
		var recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		var capacity: float = float(site.get("capacity_batches_per_day", 0.0))
		var operating_bp: int = clampi(int(site.get("operating_target_bp", BASIS_POINTS)), 0, BASIS_POINTS)
		var batches: float = capacity * float(operating_bp) / float(BASIS_POINTS)
		for raw_input: Variant in recipe.get("inputs", []) as Array:
			var input: Dictionary = raw_input as Dictionary
			var commodity_id: String = str(input.get("commodity_id", ""))
			var units: float = float(input.get("units", 0.0))
			if units > 0.0:
				batches = minf(batches, float(inventory.get(commodity_id, 0.0)) / units)
		batches = maxf(0.0, floor(batches * 1000.0) / 1000.0)
		for raw_input: Variant in recipe.get("inputs", []) as Array:
			var input: Dictionary = raw_input as Dictionary
			var commodity_id: String = str(input.get("commodity_id", ""))
			var used: float = float(input.get("units", 0.0)) * batches
			inventory[commodity_id] = maxf(0.0, float(inventory.get(commodity_id, 0.0)) - used)
			_add_metric(metrics, "industrial_inputs", commodity_id, used)
		for raw_output: Variant in recipe.get("outputs", []) as Array:
			var output: Dictionary = raw_output as Dictionary
			var commodity_id: String = str(output.get("commodity_id", ""))
			var produced: float = float(output.get("units", 0.0)) * batches
			var supply_modifier_bp: int = _active_supply_modifier_bp(
				region_id, commodity_id, total_hour
			)
			produced *= float(supply_modifier_bp) / float(BASIS_POINTS)
			inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + produced
			_add_metric(metrics, "produced", commodity_id, produced)
		var workers_capacity: int = int(site.get("workers_capacity", 0))
		var utilization: float = 0.0 if capacity <= 0.0 else batches / capacity
		metrics["workers_capacity"] = int(metrics.get("workers_capacity", 0)) + workers_capacity
		metrics["workers_active"] = int(metrics.get("workers_active", 0)) + int(round(workers_capacity * utilization))
		site["last_batches"] = batches
		site["last_operating_bp"] = int(round(utilization * BASIS_POINTS))
		site["last_settlement_hour"] = total_hour
		production_sites[site_id] = site
		state["inventory"] = inventory
		state["daily_metrics"] = metrics
		region_states[region_id] = state
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		var capacity_workers: int = int(metrics.get("workers_capacity", 0))
		metrics["production_utilization_bp"] = (
			0 if capacity_workers <= 0
			else int(metrics.get("workers_active", 0)) * BASIS_POINTS / capacity_workers
		)
		state["daily_metrics"] = metrics
		region_states[region_id] = state


func _run_local_consumption() -> void:
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		var totals: Dictionary = metrics.get("totals", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var demand: float = daily_household_demand(region_id, commodity_id)
			if demand <= 0.0:
				continue
			var available: float = float(inventory.get(commodity_id, 0.0))
			var consumed: float = minf(available, demand)
			var unmet: float = maxf(0.0, demand - consumed)
			inventory[commodity_id] = available - consumed
			_add_metric(metrics, "demand", commodity_id, demand)
			_add_metric(metrics, "consumed", commodity_id, consumed)
			if unmet > 0.0001:
				_add_metric(metrics, "unmet", commodity_id, unmet)
			totals["household_demand_units"] = float(totals.get("household_demand_units", 0.0)) + demand
			totals["household_consumed_units"] = float(totals.get("household_consumed_units", 0.0)) + consumed
			totals["unmet_units"] = float(totals.get("unmet_units", 0.0)) + unmet
		metrics["totals"] = totals
		state["inventory"] = inventory
		state["daily_metrics"] = metrics
		region_states[region_id] = state


func _run_regional_balancing() -> void:
	var country_regions: Dictionary = {}
	for region_id: String in _region_ids:
		var country_id: String = str((region_states[region_id] as Dictionary).get("country_id", ""))
		var ids: Array = country_regions.get(country_id, []) as Array
		ids.append(region_id)
		country_regions[country_id] = ids
	for raw_country_id: Variant in country_regions:
		var ids: Array = country_regions[raw_country_id] as Array
		for commodity_id: String in _commodity_ids:
			for receiver_value: Variant in ids:
				var receiver_id: String = str(receiver_value)
				var unmet: float = _metric_value(receiver_id, "unmet", commodity_id)
				if unmet <= 0.0001:
					continue
				for donor_value: Variant in ids:
					var donor_id: String = str(donor_value)
					if donor_id == receiver_id:
						continue
					var donor_state: Dictionary = region_states[donor_id] as Dictionary
					var donor_inventory: Dictionary = donor_state.get("inventory", {}) as Dictionary
					var reserve: float = _target_stock_units(donor_id, commodity_id, 0.35)
					var surplus: float = maxf(0.0, float(donor_inventory.get(commodity_id, 0.0)) - reserve)
					var moved: float = minf(unmet, surplus)
					if moved <= 0.0001:
						continue
					donor_inventory[commodity_id] = float(donor_inventory.get(commodity_id, 0.0)) - moved
					donor_state["inventory"] = donor_inventory
					var donor_metrics: Dictionary = donor_state.get("daily_metrics", {}) as Dictionary
					_add_metric(donor_metrics, "regional_sent", commodity_id, moved)
					donor_state["daily_metrics"] = donor_metrics
					region_states[donor_id] = donor_state
					_fulfill_shortage(receiver_id, commodity_id, moved, "regional_received")
					unmet -= moved
					if unmet <= 0.0001:
						break


func _run_international_market() -> void:
	var pool: Dictionary = international_market.get("inventory", {}) as Dictionary
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var remaining_capacity: float = float(state.get("import_capacity_units_per_day", 0.0))
		for commodity_id: String in _commodity_ids:
			if remaining_capacity <= 0.0001:
				break
			var commodity: Dictionary = commodities[commodity_id] as Dictionary
			if str(commodity.get("trade_class", "")) not in IMPORTABLE_CLASSES:
				continue
			var unmet: float = _metric_value(region_id, "unmet", commodity_id)
			var available: float = float(pool.get(commodity_id, 0.0))
			var moved: float = minf(unmet, minf(available, remaining_capacity))
			if moved <= 0.0001:
				continue
			pool[commodity_id] = available - moved
			remaining_capacity -= moved
			_fulfill_shortage(region_id, commodity_id, moved, "international_imports")
			international_market["cumulative_import_units"] = (
				float(international_market.get("cumulative_import_units", 0.0)) + moved
			)
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		var remaining_capacity: float = float(state.get("export_capacity_units_per_day", 0.0))
		for commodity_id: String in _commodity_ids:
			if remaining_capacity <= 0.0001:
				break
			var commodity: Dictionary = commodities[commodity_id] as Dictionary
			if str(commodity.get("trade_class", "")) not in EXPORTABLE_CLASSES:
				continue
			var reserve: float = _target_stock_units(region_id, commodity_id, 1.05)
			var surplus: float = maxf(0.0, float(inventory.get(commodity_id, 0.0)) - reserve)
			var moved: float = minf(surplus, remaining_capacity)
			if moved <= 0.0001:
				continue
			inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) - moved
			pool[commodity_id] = float(pool.get(commodity_id, 0.0)) + moved
			remaining_capacity -= moved
			_add_metric(metrics, "international_exports", commodity_id, moved)
			var totals: Dictionary = metrics.get("totals", {}) as Dictionary
			totals["international_export_units"] = float(totals.get("international_export_units", 0.0)) + moved
			metrics["totals"] = totals
			international_market["cumulative_export_units"] = (
				float(international_market.get("cumulative_export_units", 0.0)) + moved
			)
		state["inventory"] = inventory
		state["daily_metrics"] = metrics
		region_states[region_id] = state
	international_market["inventory"] = pool


func _fulfill_shortage(
	region_id: String, commodity_id: String, delivered: float, metric_name: String
) -> void:
	var state: Dictionary = region_states[region_id] as Dictionary
	var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
	var unmet_map: Dictionary = metrics.get("unmet", {}) as Dictionary
	var current_unmet: float = float(unmet_map.get(commodity_id, 0.0))
	var used: float = minf(current_unmet, delivered)
	unmet_map[commodity_id] = maxf(0.0, current_unmet - used)
	metrics["unmet"] = unmet_map
	_add_metric(metrics, "consumed", commodity_id, used)
	_add_metric(metrics, metric_name, commodity_id, delivered)
	var totals: Dictionary = metrics.get("totals", {}) as Dictionary
	totals["household_consumed_units"] = float(totals.get("household_consumed_units", 0.0)) + used
	totals["unmet_units"] = maxf(0.0, float(totals.get("unmet_units", 0.0)) - used)
	if metric_name == "international_imports":
		totals["international_import_units"] = float(totals.get("international_import_units", 0.0)) + delivered
	metrics["totals"] = totals
	state["daily_metrics"] = metrics
	region_states[region_id] = state


func _update_prices() -> void:
	var smoothing_bp: int = int(_policies.get("price_smoothing_bp", 2500))
	var max_change_bp: int = int(_policies.get("maximum_daily_price_change_bp", 1800))
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
		var prices: Dictionary = state.get("prices", {}) as Dictionary
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = commodities[commodity_id] as Dictionary
			var base_price: int = int(commodity.get("base_price_centimes", 1))
			var target: float = maxf(1.0, _target_stock_units(region_id, commodity_id, 1.0))
			var stock: float = float(inventory.get(commodity_id, 0.0))
			var coverage_ratio: float = stock / target
			var unmet: float = _metric_value(region_id, "unmet", commodity_id)
			var demand: float = maxf(1.0, _metric_value(region_id, "demand", commodity_id))
			var shortage_bp: int = int(round(clampf(unmet / demand, 0.0, 1.0) * 6500.0))
			var stock_pressure_bp: int = int(round(clampf(1.0 - coverage_ratio, -0.7, 1.2) * 3500.0))
			var shock_bp: int = _active_price_modifier_bp(region_id, commodity_id)
			var target_price: int = maxi(
				1,
				base_price * maxi(2000, BASIS_POINTS + shortage_bp + stock_pressure_bp + shock_bp) / BASIS_POINTS
			)
			var previous: int = maxi(1, int(prices.get(commodity_id, base_price)))
			var smoothed: int = (
				previous * (BASIS_POINTS - smoothing_bp) + target_price * smoothing_bp
			) / BASIS_POINTS
			var minimum: int = maxi(1, previous * (BASIS_POINTS - max_change_bp) / BASIS_POINTS)
			var maximum: int = maxi(1, previous * (BASIS_POINTS + max_change_bp) / BASIS_POINTS)
			prices[commodity_id] = clampi(smoothed, minimum, maximum)
		state["prices"] = prices
		region_states[region_id] = state


func _update_employment() -> void:
	var friction_bp: int = int(_policies.get("minimum_frictional_unemployment_bp", 250))
	for region_id: String in _region_ids:
		var state: Dictionary = region_states[region_id] as Dictionary
		var population: int = int(state.get("population", 0))
		var labor_force: int = population * int(state.get("labor_force_bp", 4400)) / BASIS_POINTS
		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
		var modeled_active: int = int(metrics.get("workers_active", 0))
		var modeled_capacity: int = int(metrics.get("workers_capacity", 0))
		var nonmodeled: int = labor_force * int(state.get("nonmodeled_employment_bp", 8200)) / BASIS_POINTS
		var totals: Dictionary = metrics.get("totals", {}) as Dictionary
		var demand: float = float(totals.get("household_demand_units", 0.0))
		var unmet: float = float(totals.get("unmet_units", 0.0))
		var shortage_penalty: int = (
			0 if demand <= 0.0
			else int(round(float(labor_force) * clampf(unmet / demand, 0.0, 1.0) * 0.08))
		)
		var employed: int = clampi(nonmodeled + modeled_active - shortage_penalty, 0, labor_force)
		var minimum_unemployed: int = labor_force * friction_bp / BASIS_POINTS
		var unemployed: int = maxi(minimum_unemployed, labor_force - employed)
		employed = maxi(0, labor_force - unemployed)
		state["employment"] = {
			"labor_force": labor_force,
			"employed": employed,
			"unemployed": unemployed,
			"unemployment_bp": 0 if labor_force <= 0 else unemployed * BASIS_POINTS / labor_force,
			"modeled_industry_workers": modeled_active,
			"modeled_industry_capacity": modeled_capacity,
			"vacancies": maxi(0, modeled_capacity - modeled_active),
		}
		region_states[region_id] = state


func _enforce_all_warehouse_capacity() -> void:
	for region_id: String in _region_ids:
		_enforce_warehouse_capacity(region_id)


func _enforce_warehouse_capacity(region_id: String) -> void:
	var state: Dictionary = region_states[region_id] as Dictionary
	var capacity_tonnes: float = float(state.get("warehouse_capacity_tonnes", 0.0))
	var used_tonnes: float = _warehouse_used_tonnes(state)
	if capacity_tonnes <= 0.0 or used_tonnes <= capacity_tonnes:
		return
	var excess_kg: float = (used_tonnes - capacity_tonnes) * 1000.0
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
	for priority: int in range(1, 11):
		for commodity_id: String in _commodity_ids:
			var commodity: Dictionary = commodities[commodity_id] as Dictionary
			if int(commodity.get("storage_priority", 5)) != priority:
				continue
			var mass_kg: float = float(commodity.get("unit_mass_kg", 0.0))
			if mass_kg <= 0.0:
				continue
			var available: float = float(inventory.get(commodity_id, 0.0))
			var removed: float = minf(available, excess_kg / mass_kg)
			if removed <= 0.0001:
				continue
			inventory[commodity_id] = available - removed
			excess_kg -= removed * mass_kg
			_add_metric(metrics, "warehouse_overflow", commodity_id, removed)
			if excess_kg <= 0.001:
				break
		if excess_kg <= 0.001:
			break
	state["inventory"] = inventory
	state["daily_metrics"] = metrics
	region_states[region_id] = state


func _warehouse_used_tonnes(state: Dictionary) -> float:
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	var kilograms: float = 0.0
	for commodity_id: String in _commodity_ids:
		var mass_kg: float = float((commodities[commodity_id] as Dictionary).get("unit_mass_kg", 0.0))
		kilograms += float(inventory.get(commodity_id, 0.0)) * mass_kg
	return kilograms / 1000.0


func _target_stock_units(region_id: String, commodity_id: String, multiplier: float) -> float:
	var commodity: Dictionary = commodities[commodity_id] as Dictionary
	if str(commodity.get("trade_class", "")) == "local_service":
		return maxf(1.0, daily_household_demand(region_id, commodity_id))
	var days: float = float(commodity.get("target_stock_days", 10)) * multiplier
	return maxf(
		1.0,
		(daily_household_demand(region_id, commodity_id)
		+ _daily_industrial_input_need(region_id, commodity_id)) * days
	)


func _daily_industrial_input_need(region_id: String, commodity_id: String) -> float:
	var total: float = 0.0
	for raw_site: Variant in production_sites.values():
		var site: Dictionary = raw_site as Dictionary
		if str(site.get("region_id", "")) != region_id:
			continue
		var recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
		for raw_input: Variant in recipe.get("inputs", []) as Array:
			var input: Dictionary = raw_input as Dictionary
			if str(input.get("commodity_id", "")) == commodity_id:
				total += float(input.get("units", 0.0)) * float(site.get("capacity_batches_per_day", 0.0))
	return total


func _daily_output_capacity(region_id: String, commodity_id: String) -> float:
	var total: float = 0.0
	for raw_site: Variant in production_sites.values():
		var site: Dictionary = raw_site as Dictionary
		if str(site.get("region_id", "")) != region_id:
			continue
		var recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
		for raw_output: Variant in recipe.get("outputs", []) as Array:
			var output: Dictionary = raw_output as Dictionary
			if str(output.get("commodity_id", "")) == commodity_id:
				total += float(output.get("units", 0.0)) * float(site.get("capacity_batches_per_day", 0.0))
	return total


func _metric_value(region_id: String, map_name: String, commodity_id: String) -> float:
	var state: Dictionary = region_states[region_id] as Dictionary
	var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
	var values: Dictionary = metrics.get(map_name, {}) as Dictionary
	return float(values.get(commodity_id, 0.0))


func _add_metric(
	metrics: Dictionary, map_name: String, commodity_id: String, amount: float
) -> void:
	if amount <= 0.000001:
		return
	var values: Dictionary = metrics.get(map_name, {}) as Dictionary
	values[commodity_id] = float(values.get(commodity_id, 0.0)) + amount
	metrics[map_name] = values


func _active_supply_modifier_bp(
	region_id: String, commodity_id: String, total_hour: int
) -> int:
	var modifier: int = BASIS_POINTS
	for shock: Dictionary in active_shocks:
		if (
			str(shock.get("region_id", "")) == region_id
			and str(shock.get("commodity_id", "")) == commodity_id
			and total_hour < int(shock.get("end_hour", -1))
		):
			modifier = modifier * (BASIS_POINTS + int(shock.get("supply_delta_bp", 0))) / BASIS_POINTS
	return clampi(modifier, 0, 25000)


func _active_price_modifier_bp(region_id: String, commodity_id: String) -> int:
	var total: int = 0
	for shock: Dictionary in active_shocks:
		if (
			str(shock.get("region_id", "")) == region_id
			and str(shock.get("commodity_id", "")) == commodity_id
		):
			total += int(shock.get("price_delta_bp", 0))
	return clampi(total, -8000, 15000)


func _expire_shocks(total_hour: int) -> void:
	var remaining: Array[Dictionary] = []
	for shock: Dictionary in active_shocks:
		if total_hour < int(shock.get("end_hour", -1)):
			remaining.append(shock)
	active_shocks = remaining


func _category_count(category: String) -> int:
	var count: int = 0
	for raw_commodity: Variant in commodities.values():
		if str((raw_commodity as Dictionary).get("category", "")) == category:
			count += 1
	return count


func _fail_initialize(message: String) -> bool:
	initialization_error = message
	return false


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
