extends SceneTree

const TEN_YEAR_DAYS: int = 3650
const CHECKPOINT_DAYS: int = 30
const FINAL_YEAR_DAYS: int = 366

var long_term_checks: int = 0
var long_term_failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy: VNextMarketEconomy = VNextMarketEconomy.new()
	var configured: bool = economy.configure_1900()
	_check(configured, "ten-year economy configures from real 1900 data")
	var checkpoint_count: int = 0
	for day_index: int in range(TEN_YEAR_DAYS):
		var result: Dictionary = economy.settle_day(day_index)
		if not bool(result.get("success", false)):
			_check(false, "ten-year settlement succeeds at day %d" % day_index)
			break
		if day_index % CHECKPOINT_DAYS == 0 or day_index == TEN_YEAR_DAYS - 1:
			checkpoint_count += 1
			_check(economy.validate_integrity(), "physical ledger remains valid at day %d" % day_index)
			_check_checkpoint_health(economy, day_index)
	_check(checkpoint_count >= 120, "ten-year test reaches regular checkpoints")
	_check(economy.last_day_index() == TEN_YEAR_DAYS - 1, "simulation reaches the full 3650 days")
	_check(economy.history_snapshot(
		_region(economy, "region_loran_dawnbay"), "bread", FINAL_YEAR_DAYS
	).size() == FINAL_YEAR_DAYS, "history retains the bounded recent window")
	_check_price_wave(economy)
	_check_long_run_price_diagnostics(economy)
	_check_national_markets_survive(economy)
	var final_snapshot: Dictionary = economy.snapshot()
	_check((final_snapshot.get("shipments", []) as Array).size() <= 256, "in-transit queue stays bounded")
	print(
		"VNext market economy ten-year: %d checks, %d failures"
		% [long_term_checks, long_term_failures]
	)
	quit(1 if long_term_failures > 0 or long_term_checks <= 0 else 0)


func _check_checkpoint_health(economy: VNextMarketEconomy, day_index: int) -> void:
	var active_regions: int = 0
	var functioning_countries: Dictionary = {}
	var total_production: float = 0.0
	var total_demand: float = 0.0
	for region_id: String in economy.region_market_ids():
		var region: Dictionary = economy.region_snapshot(region_id)
		var commodities: Dictionary = region.get("commodities", {}) as Dictionary
		var region_activity: float = 0.0
		for commodity_id: String in economy.commodity_ids():
			var row: Dictionary = commodities.get(commodity_id, {}) as Dictionary
			var price: float = float(row.get("price_centimes", 0.0))
			var inventory: float = float(row.get("inventory_units", 0.0))
			var production: float = float(row.get("production_units", 0.0))
			var demand: float = float(row.get("demand_units", 0.0))
			var base_price: float = float(
				(economy.catalog.commodities[commodity_id] as Dictionary).get(
					"base_price_centimes", 1
				)
			)
			if (
				is_nan(price)
				or is_inf(price)
				or is_nan(inventory)
				or is_inf(inventory)
				or is_nan(production)
				or is_inf(production)
				or is_nan(demand)
				or is_inf(demand)
				or price < 1.0
				or price > base_price * 12.05
				or inventory < -0.0001
				or production < -0.0001
				or demand < -0.0001
			):
				_check(false, "finite bounded market values at day %d" % day_index)
				return
			total_production += production
			total_demand += demand
			region_activity += production + demand + inventory
		if region_activity > 0.0001:
			active_regions += 1
			var country_id: String = str(region.get("country_market_id", ""))
			functioning_countries[country_id] = true
	_check(active_regions >= 8, "all regional markets remain active at day %d" % day_index)
	_check(functioning_countries.size() >= 2, "both national markets remain active at day %d" % day_index)
	_check(total_production > 0.0, "production remains positive at day %d" % day_index)
	_check(total_demand > 0.0, "demand remains positive at day %d" % day_index)


func _check_price_wave(economy: VNextMarketEconomy) -> void:
	var values: Array[Dictionary] = economy.history_snapshot(
		_region(economy, "region_loran_dawnbay"), "bread", FINAL_YEAR_DAYS
	)
	var minimum: int = 2147483647
	var maximum: int = 0
	var distinct_prices: Dictionary = {}
	for row: Dictionary in values:
		var price: int = int(row.get("price_centimes", 0))
		minimum = mini(minimum, price)
		maximum = maxi(maximum, price)
		distinct_prices[price] = true
	_check(distinct_prices.size() > 1, "normal economy exhibits price movement")
	_check(maximum > minimum, "normal economy has a measurable price wave")


func _check_long_run_price_diagnostics(economy: VNextMarketEconomy) -> void:
	var market_id: String = _region(economy, "region_loran_dawnbay")
	for commodity_id: String in ["bread", "coal", "steel"]:
		var metrics: Dictionary = _series_metrics(
			economy.history_snapshot(market_id, commodity_id, FINAL_YEAR_DAYS)
		)
		_check(int(metrics.get("count", 0)) == FINAL_YEAR_DAYS, "%s final-year history is complete" % commodity_id)
		_check(int(metrics.get("minimum", 0)) > 0, "%s final-year prices remain positive" % commodity_id)
		_check(int(metrics.get("distinct", 0)) > 1, "%s final-year prices do not freeze" % commodity_id)
		print("ECON_DIAG %s_final_year %s" % [commodity_id, _metric_string(metrics)])


func _series_metrics(values: Array[Dictionary]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var minimum: int = 2147483647
	var maximum: int = 0
	var total: float = 0.0
	var abs_change_bp_total: float = 0.0
	var max_daily_change_bp: int = 0
	var distinct: Dictionary = {}
	var previous: int = 0
	for index: int in range(values.size()):
		var price: int = int(values[index].get("price_centimes", 0))
		minimum = mini(minimum, price)
		maximum = maxi(maximum, price)
		total += price
		distinct[price] = true
		if index > 0 and previous > 0:
			var change_bp: int = int(round(absf(float(price - previous)) / float(previous) * 10000.0))
			abs_change_bp_total += change_bp
			max_daily_change_bp = maxi(max_daily_change_bp, change_bp)
		previous = price
	var mean: float = total / float(values.size())
	var variance: float = 0.0
	for row: Dictionary in values:
		var delta: float = float(row.get("price_centimes", 0)) - mean
		variance += delta * delta
	variance /= float(values.size())
	var stddev: float = sqrt(maxf(0.0, variance))
	return {
		"count": values.size(),
		"minimum": minimum,
		"maximum": maximum,
		"mean": mean,
		"range_bp_of_mean": 0 if mean <= 0.0 else int(round(float(maximum - minimum) / mean * 10000.0)),
		"coefficient_variation_bp": 0 if mean <= 0.0 else int(round(stddev / mean * 10000.0)),
		"avg_abs_daily_change_bp": 0 if values.size() <= 1 else int(round(abs_change_bp_total / float(values.size() - 1))),
		"max_daily_change_bp": max_daily_change_bp,
		"distinct": distinct.size(),
	}


func _metric_string(value: Dictionary) -> String:
	return (
		"count=%d min=%d max=%d mean=%.3f range_bp=%d cv_bp=%d avg_abs_daily_change_bp=%d max_daily_change_bp=%d distinct=%d"
		% [
			int(value.get("count", 0)),
			int(value.get("minimum", 0)),
			int(value.get("maximum", 0)),
			float(value.get("mean", 0.0)),
			int(value.get("range_bp_of_mean", 0)),
			int(value.get("coefficient_variation_bp", 0)),
			int(value.get("avg_abs_daily_change_bp", 0)),
			int(value.get("max_daily_change_bp", 0)),
			int(value.get("distinct", 0)),
		]
	)


func _check_national_markets_survive(economy: VNextMarketEconomy) -> void:
	for country_id: String in economy.country_market_ids():
		var country: Dictionary = economy.country_snapshot(country_id)
		var commodities: Dictionary = country.get("commodities", {}) as Dictionary
		var key_activity: float = 0.0
		for commodity_id: String in ["wheat", "coal", "steel", "bread"]:
			key_activity += float(
				(commodities.get(commodity_id, {}) as Dictionary).get("production_units", 0.0)
			)
			key_activity += float(
				(commodities.get(commodity_id, {}) as Dictionary).get("demand_units", 0.0)
			)
		_check(key_activity > 0.0, "national market remains economically active: %s" % country_id)


func _region(economy: VNextMarketEconomy, source_region_id: String) -> String:
	var normalized_id: String = source_region_id
	if not normalized_id.begins_with("region:"):
		normalized_id = "region:" + normalized_id.trim_prefix("region_")
	return economy.catalog.region_market_id(normalized_id)


func _check(condition: bool, message: String) -> void:
	long_term_checks += 1
	if not condition:
		long_term_failures += 1
		print("FAIL: " + message)
