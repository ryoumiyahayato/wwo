extends SceneTree

const TEN_YEAR_DAYS: int = 3650
const FINAL_YEAR_DAYS: int = 366

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_same_day_direction_and_bounds()
	_test_deterministic_partition()
	_test_long_run_diagnostics()
	print("VNext market economy behavior diagnostics: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _new_economy(label: String) -> VNextMarketEconomy:
	var economy: VNextMarketEconomy = VNextMarketEconomy.new()
	_check(economy.configure_1900(), "%s configures" % label)
	return economy


func _test_same_day_direction_and_bounds() -> void:
	var baseline: VNextMarketEconomy = _new_economy("same-day baseline")
	var market_id: String = _region(baseline, "region_loran_dawnbay")
	var initial_bread: int = baseline.current_price(market_id, "bread")
	_check(bool(baseline.settle_day(0).get("success", false)), "baseline day settles")
	var baseline_bread: int = baseline.current_price(market_id, "bread")

	var shortage: VNextMarketEconomy = _new_economy("same-day shortage")
	var shortage_market: String = _region(shortage, "region_loran_dawnbay")
	_check(shortage.set_region_inventory(shortage_market, "bread", 0.0), "bread stock can be depleted")
	_check(bool(shortage.settle_day(0).get("success", false)), "shortage day settles")
	var shortage_row: Dictionary = shortage.commodity_snapshot(shortage_market, "bread")
	var shortage_price: int = int(shortage_row.get("price_centimes", 0))
	_check(float(shortage_row.get("unmet_units", 0.0)) > 0.0, "same-day shortage creates unmet demand")
	_check(shortage_price >= baseline_bread, "same-day shortage does not lower bread price")

	var surplus: VNextMarketEconomy = _new_economy("same-day surplus")
	var surplus_market: String = _region(surplus, "region_loran_dawnbay")
	_check(surplus.set_region_inventory(surplus_market, "bread", 1000000.0), "bread stock can be overfilled")
	_check(bool(surplus.settle_day(0).get("success", false)), "surplus day settles")
	var surplus_price: int = surplus.current_price(surplus_market, "bread")
	_check(surplus_price <= baseline_bread, "same-day surplus does not raise bread price")

	var max_up: int = maxi(initial_bread, initial_bread * 11400 / 10000)
	var min_down: int = maxi(1, initial_bread * 8600 / 10000)
	_check(shortage_price <= max_up, "one-day shortage movement remains bounded")
	_check(surplus_price >= min_down, "one-day surplus movement remains bounded")

	print(
		"ECON_DIAG same_day bread initial=%d baseline=%d shortage=%d surplus=%d shortage_unmet=%.6f"
		% [
			initial_bread,
			baseline_bread,
			shortage_price,
			surplus_price,
			float(shortage_row.get("unmet_units", 0.0)),
		]
	)


func _test_deterministic_partition() -> void:
	var once: VNextMarketEconomy = _new_economy("partition once")
	var partitioned: VNextMarketEconomy = _new_economy("partition daily")
	_check(bool(once.advance_days(30).get("success", false)), "advance_days(30) succeeds")
	for day_index: int in range(30):
		_check(bool(partitioned.settle_day(day_index).get("success", false)), "partition day %d settles" % day_index)
	_equal(JSON.stringify(once.snapshot()), JSON.stringify(partitioned.snapshot()), "30-day partition is equivalent")

	var replay: VNextMarketEconomy = _new_economy("deterministic replay")
	_check(bool(replay.advance_days(30).get("success", false)), "replay advances")
	_equal(JSON.stringify(once.snapshot()), JSON.stringify(replay.snapshot()), "same fixture replays identically")


func _test_long_run_diagnostics() -> void:
	var economy: VNextMarketEconomy = _new_economy("ten-year diagnostics")
	for day_index: int in range(TEN_YEAR_DAYS):
		var result: Dictionary = economy.settle_day(day_index)
		if not bool(result.get("success", false)):
			_check(false, "ten-year settlement succeeds at day %d" % day_index)
			return
		if day_index % 365 == 0 or day_index == TEN_YEAR_DAYS - 1:
			_check(economy.validate_integrity(), "physical integrity at long-run checkpoint %d" % day_index)

	_check(economy.last_day_index() == TEN_YEAR_DAYS - 1, "ten-year diagnostics complete 3650 days")
	var market_id: String = _region(economy, "region_loran_dawnbay")
	var bread: Dictionary = _series_metrics(economy.history_snapshot(market_id, "bread", FINAL_YEAR_DAYS))
	var coal: Dictionary = _series_metrics(economy.history_snapshot(market_id, "coal", FINAL_YEAR_DAYS))
	var steel: Dictionary = _series_metrics(economy.history_snapshot(market_id, "steel", FINAL_YEAR_DAYS))
	_check(int(bread.get("count", 0)) == FINAL_YEAR_DAYS, "bread final-year history is complete")
	_check(int(coal.get("count", 0)) == FINAL_YEAR_DAYS, "coal final-year history is complete")
	_check(int(steel.get("count", 0)) == FINAL_YEAR_DAYS, "steel final-year history is complete")
	_check(int(bread.get("minimum", 0)) > 0, "bread price remains positive")
	_check(int(coal.get("minimum", 0)) > 0, "coal price remains positive")
	_check(int(steel.get("minimum", 0)) > 0, "steel price remains positive")
	_check(int(bread.get("max_daily_change_bp", 10001)) <= 1400, "bread one-day movement obeys global bound")
	_check(int(coal.get("max_daily_change_bp", 10001)) <= 1400, "coal one-day movement obeys global bound")
	_check(int(steel.get("max_daily_change_bp", 10001)) <= 1400, "steel one-day movement obeys global bound")
	_check(int(bread.get("distinct", 0)) > 1, "bread does not freeze to a constant")
	_check(int(coal.get("distinct", 0)) > 1, "coal does not freeze to a constant")

	print("ECON_DIAG bread_final_year %s" % _metric_string(bread))
	print("ECON_DIAG coal_final_year %s" % _metric_string(coal))
	print("ECON_DIAG steel_final_year %s" % _metric_string(steel))


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


func _region(economy: VNextMarketEconomy, source_region_id: String) -> String:
	var normalized_id: String = source_region_id
	if not normalized_id.begins_with("region:"):
		normalized_id = "region:" + normalized_id.trim_prefix("region_")
	return economy.catalog.region_market_id(normalized_id)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		print("FAIL: %s actual=%s expected=%s" % [message, str(actual), str(expected)])
