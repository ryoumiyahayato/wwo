extends SceneTree

const TEN_YEAR_DAYS: int = 3650
const CHECKPOINT_DAYS: int = 30

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
		_region(economy, "region_loran_dawnbay"), "bread", 366
	).size() == 366, "history retains the bounded recent window")
	_check_price_wave(economy)
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
		_region(economy, "region_loran_dawnbay"), "bread", 366
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
