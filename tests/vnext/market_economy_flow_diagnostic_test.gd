extends SceneTree

const TEN_YEAR_DAYS: int = 3650
const FINAL_YEAR_DAYS: int = 366
const FINAL_YEAR_START: int = TEN_YEAR_DAYS - FINAL_YEAR_DAYS
const BASIS_POINTS: int = 10000

var failures: int = 0
var ranges: Dictionary = {}
var distinct_prices: Dictionary = {}
var distinct_target_prices: Dictionary = {}
var distinct_target_multipliers: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy := VNextMarketEconomy.new()
	if not economy.configure_1900():
		print("FAIL: diagnostic economy configure_1900")
		quit(1)
		return
	var market_id := economy.catalog.region_market_id("region:loran_dawnbay")
	for day_index: int in range(TEN_YEAR_DAYS):
		var result: Dictionary = economy.settle_day(day_index)
		if not bool(result.get("success", false)):
			failures += 1
			print("FAIL: diagnostic settlement day=%d result=%s" % [day_index, JSON.stringify(result)])
			break
		if day_index % 365 == 0 or day_index == TEN_YEAR_DAYS - 1:
			if not economy.validate_integrity():
				failures += 1
				print("FAIL: diagnostic integrity day=%d" % day_index)
				break
		if day_index >= FINAL_YEAR_START:
			_sample_day(economy, market_id, day_index)

	print("ECON_FLOW_DIAG failures=%d sampled_days=%d" % [failures, _count_for("price_centimes")])
	for key: String in ranges.keys():
		var row: Dictionary = ranges[key] as Dictionary
		print("ECON_FLOW_DIAG %s min=%.9f max=%.9f span=%.9f count=%d" % [
			key,
			float(row.get("min", 0.0)),
			float(row.get("max", 0.0)),
			float(row.get("max", 0.0)) - float(row.get("min", 0.0)),
			int(row.get("count", 0)),
		])
	print("ECON_FLOW_DIAG price_distinct=%d values=%s" % [distinct_prices.size(), _sorted_keys(distinct_prices)])
	print("ECON_FLOW_DIAG target_price_distinct=%d values=%s" % [distinct_target_prices.size(), _sorted_keys(distinct_target_prices)])
	print("ECON_FLOW_DIAG target_multiplier_distinct=%d minmax=%s" % [distinct_target_multipliers.size(), _dictionary_key_minmax(distinct_target_multipliers)])
	quit(1 if failures > 0 else 0)


func _sample_day(economy: VNextMarketEconomy, market_id: String, day_index: int) -> void:
	var bread: Dictionary = economy.commodity_snapshot(market_id, "bread")
	var demand: float = float(bread.get("demand_units", 0.0))
	var supply: float = float(bread.get("supply_units", 0.0))
	var production: float = float(bread.get("production_units", 0.0))
	var inventory: float = float(bread.get("inventory_end_units", bread.get("inventory_units", 0.0)))
	var target_stock: float = float(bread.get("target_stock_units", 0.0))
	var coverage_bp: int = int(bread.get("inventory_coverage_bp", 0))
	var shortage_bp: int = int(bread.get("shortage_bp", 0))
	var unmet: float = float(bread.get("unmet_units", 0.0))
	var price: int = int(bread.get("price_centimes", 0))
	var target_price: int = int(bread.get("target_price_centimes", 0))
	var flow_ratio_bp: int = 0
	var flow_scale: float = maxf(1.0, maxf(demand, supply))
	flow_ratio_bp = int(round(clampf((demand - supply) / flow_scale, -1.0, 1.0) * BASIS_POINTS))
	var stock_pressure_bp: int = clampi(int(round((1.0 - float(coverage_bp) / BASIS_POINTS) * 3200.0)), -5000, 5000)
	var shortage_pressure_bp: int = int(round(float(shortage_bp) / BASIS_POINTS * 6500.0))
	var target_multiplier_bp: int = BASIS_POINTS + stock_pressure_bp + shortage_pressure_bp

	_record("price_centimes", price)
	_record("target_price_centimes", target_price)
	_record("demand_units", demand)
	_record("supply_units", supply)
	_record("production_units", production)
	_record("inventory_end_units", inventory)
	_record("target_stock_units", target_stock)
	_record("coverage_bp", coverage_bp)
	_record("shortage_bp", shortage_bp)
	_record("unmet_units", unmet)
	_record("flow_imbalance_bp", flow_ratio_bp)
	_record("stock_pressure_bp", stock_pressure_bp)
	_record("shortage_pressure_bp", shortage_pressure_bp)
	_record("target_multiplier_bp", target_multiplier_bp)
	distinct_prices[price] = true
	distinct_target_prices[target_price] = true
	distinct_target_multipliers[target_multiplier_bp] = true

	var snapshot_value: Dictionary = economy.snapshot()
	var sites: Dictionary = snapshot_value.get("production_sites", {}) as Dictionary
	var bakery: Dictionary = sites.get("dawnbay_bakery", {}) as Dictionary
	_record("bakery_operating_target_bp", float(bakery.get("operating_target_bp", 0)))
	_record("bakery_last_operating_bp", float(bakery.get("last_operating_bp", 0)))
	_record("bakery_last_batches", float(bakery.get("last_batches", 0.0)))
	_record("bakery_input_shortage_bp", float(bakery.get("last_input_shortage_bp", 0)))
	_record("bakery_margin_centimes", float(bakery.get("last_margin_centimes", 0)))

	var flour: Dictionary = economy.commodity_snapshot(market_id, "flour")
	_record("flour_inventory_units", float(flour.get("inventory_end_units", flour.get("inventory_units", 0.0))))
	_record("flour_shortage_bp", float(flour.get("shortage_bp", 0)))
	_record("flour_price_centimes", float(flour.get("price_centimes", 0)))
	var coal: Dictionary = economy.commodity_snapshot(market_id, "coal")
	_record("coal_inventory_units", float(coal.get("inventory_end_units", coal.get("inventory_units", 0.0))))
	_record("coal_shortage_bp", float(coal.get("shortage_bp", 0)))

	if day_index in [FINAL_YEAR_START, FINAL_YEAR_START + 91, FINAL_YEAR_START + 182, FINAL_YEAR_START + 273, TEN_YEAR_DAYS - 1]:
		print("ECON_FLOW_SAMPLE day=%d price=%d target=%d demand=%.6f supply=%.6f production=%.6f inventory=%.6f target_stock=%.6f coverage_bp=%d shortage_bp=%d flow_bp=%d stock_pressure=%d shortage_pressure=%d target_multiplier=%d bakery_target=%d bakery_batches=%.6f input_shortage_bp=%d" % [
			day_index,
			price,
			target_price,
			demand,
			supply,
			production,
			inventory,
			target_stock,
			coverage_bp,
			shortage_bp,
			flow_ratio_bp,
			stock_pressure_bp,
			shortage_pressure_bp,
			target_multiplier_bp,
			int(bakery.get("operating_target_bp", 0)),
			float(bakery.get("last_batches", 0.0)),
			int(bakery.get("last_input_shortage_bp", 0)),
		])


func _record(key: String, value: float) -> void:
	if not ranges.has(key):
		ranges[key] = {"min": value, "max": value, "count": 1}
		return
	var row: Dictionary = ranges[key] as Dictionary
	row["min"] = minf(float(row.get("min", value)), value)
	row["max"] = maxf(float(row.get("max", value)), value)
	row["count"] = int(row.get("count", 0)) + 1
	ranges[key] = row


func _count_for(key: String) -> int:
	return int((ranges.get(key, {}) as Dictionary).get("count", 0))


func _sorted_keys(source: Dictionary) -> Array:
	var values: Array = source.keys()
	values.sort()
	return values


func _dictionary_key_minmax(source: Dictionary) -> String:
	if source.is_empty():
		return "empty"
	var values: Array = source.keys()
	values.sort()
	return "%s..%s" % [str(values[0]), str(values[values.size() - 1])]
