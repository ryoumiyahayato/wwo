extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_same_day_direction_and_bounds()
	_test_deterministic_partition()
	print("VNext market economy behavior: %d checks, %d failures" % [checks, failures])
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

	var max_up: int = maxi(initial_bread, initial_bread * 11800 / 10000)
	var min_down: int = maxi(1, initial_bread * 8200 / 10000)
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
