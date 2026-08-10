extends SceneTree

const TEN_YEAR_DAYS: int = 3650
const FINAL_YEAR_DAYS: int = 366
const FINAL_YEAR_START: int = TEN_YEAR_DAYS - FINAL_YEAR_DAYS

var failures: int = 0
var ranges: Dictionary = {}


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

	print("ECON_UPSTREAM_DIAG failures=%d sampled_days=%d" % [failures, _count_for("bread_demand")])
	var keys: Array = ranges.keys()
	keys.sort()
	for raw_key: Variant in keys:
		var key := str(raw_key)
		var row: Dictionary = ranges[key] as Dictionary
		print("ECON_UPSTREAM_DIAG %s min=%.9f max=%.9f span=%.9f count=%d" % [
			key,
			float(row.get("min", 0.0)),
			float(row.get("max", 0.0)),
			float(row.get("max", 0.0)) - float(row.get("min", 0.0)),
			int(row.get("count", 0)),
		])
	print("VNext market economy upstream diagnostic: %d checks, %d failures" % [maxi(1, _count_for("bread_demand")), failures])
	quit(1 if failures > 0 else 0)


func _sample_day(economy: VNextMarketEconomy, market_id: String, day_index: int) -> void:
	var bread := economy.commodity_snapshot(market_id, "bread")
	var flour := economy.commodity_snapshot(market_id, "flour")
	var wheat := economy.commodity_snapshot(market_id, "wheat")
	var coal := economy.commodity_snapshot(market_id, "coal")
	var snapshot_value := economy.snapshot()
	var sites: Dictionary = snapshot_value.get("production_sites", {}) as Dictionary
	var bakery: Dictionary = sites.get("dawnbay_bakery", {}) as Dictionary
	var flour_mill: Dictionary = sites.get("dawnbay_flour", {}) as Dictionary

	_record_commodity("bread", bread)
	_record_commodity("flour", flour)
	_record_commodity("wheat", wheat)
	_record("coal_inventory", float(coal.get("inventory_end_units", coal.get("inventory_units", 0.0))))
	_record("coal_shortage_bp", float(coal.get("shortage_bp", 0)))

	_record_site("bakery", bakery)
	_record_site("flour_mill", flour_mill)

	var wheat_world := _world_commodity_totals(economy, "wheat")
	for key: String in ["inventory", "production", "supply", "demand", "unmet", "imports", "exports"]:
		_record("world_wheat_" + key, float(wheat_world.get(key, 0.0)))

	var wheat_sites := _recipe_site_totals(sites, "farm_wheat")
	_record("world_wheat_site_count", float(wheat_sites.get("count", 0)))
	_record("world_wheat_site_batches", float(wheat_sites.get("last_batches", 0.0)))
	_record("world_wheat_site_target_bp", float(wheat_sites.get("operating_target_bp", 0.0)))
	_record("world_wheat_site_input_shortage_bp", float(wheat_sites.get("input_shortage_bp", 0.0)))

	if day_index in [FINAL_YEAR_START, FINAL_YEAR_START + 91, FINAL_YEAR_START + 182, FINAL_YEAR_START + 273, TEN_YEAR_DAYS - 1]:
		print("ECON_UPSTREAM_SAMPLE day=%d bread_demand=%.6f bread_prod=%.6f bread_shortage=%d flour_inv=%.6f flour_prod=%.6f flour_shortage=%d flour_mill_target=%d flour_mill_batches=%.6f flour_mill_input_shortage=%d wheat_inv=%.6f wheat_prod=%.6f wheat_imports=%.6f wheat_shortage=%d world_wheat_inv=%.6f world_wheat_prod=%.6f world_wheat_unmet=%.6f wheat_sites=%d wheat_site_batches=%.6f" % [
			day_index,
			float(bread.get("demand_units", 0.0)),
			float(bread.get("production_units", 0.0)),
			int(bread.get("shortage_bp", 0)),
			float(flour.get("inventory_end_units", flour.get("inventory_units", 0.0))),
			float(flour.get("production_units", 0.0)),
			int(flour.get("shortage_bp", 0)),
			int(flour_mill.get("operating_target_bp", 0)),
			float(flour_mill.get("last_batches", 0.0)),
			int(flour_mill.get("last_input_shortage_bp", 0)),
			float(wheat.get("inventory_end_units", wheat.get("inventory_units", 0.0))),
			float(wheat.get("production_units", 0.0)),
			float(wheat.get("imports_units", 0.0)),
			int(wheat.get("shortage_bp", 0)),
			float(wheat_world.get("inventory", 0.0)),
			float(wheat_world.get("production", 0.0)),
			float(wheat_world.get("unmet", 0.0)),
			int(wheat_sites.get("count", 0)),
			float(wheat_sites.get("last_batches", 0.0)),
		])


func _record_commodity(prefix: String, row: Dictionary) -> void:
	_record(prefix + "_price", float(row.get("price_centimes", 0)))
	_record(prefix + "_target_price", float(row.get("target_price_centimes", 0)))
	_record(prefix + "_inventory", float(row.get("inventory_end_units", row.get("inventory_units", 0.0))))
	_record(prefix + "_target_stock", float(row.get("target_stock_units", 0.0)))
	_record(prefix + "_coverage_bp", float(row.get("inventory_coverage_bp", 0)))
	_record(prefix + "_demand", float(row.get("demand_units", 0.0)))
	_record(prefix + "_supply", float(row.get("supply_units", 0.0)))
	_record(prefix + "_production", float(row.get("production_units", 0.0)))
	_record(prefix + "_imports", float(row.get("imports_units", 0.0)))
	_record(prefix + "_unmet", float(row.get("unmet_units", 0.0)))
	_record(prefix + "_shortage_bp", float(row.get("shortage_bp", 0)))


func _record_site(prefix: String, site: Dictionary) -> void:
	_record(prefix + "_target_bp", float(site.get("operating_target_bp", 0)))
	_record(prefix + "_operating_bp", float(site.get("last_operating_bp", 0)))
	_record(prefix + "_batches", float(site.get("last_batches", 0.0)))
	_record(prefix + "_input_shortage_bp", float(site.get("last_input_shortage_bp", 0)))
	_record(prefix + "_margin", float(site.get("last_margin_centimes", 0)))


func _world_commodity_totals(economy: VNextMarketEconomy, commodity_id: String) -> Dictionary:
	var totals := {
		"inventory": 0.0,
		"production": 0.0,
		"supply": 0.0,
		"demand": 0.0,
		"unmet": 0.0,
		"imports": 0.0,
		"exports": 0.0,
	}
	for region_id: String in economy.region_market_ids():
		var row := economy.commodity_snapshot(region_id, commodity_id)
		totals["inventory"] = float(totals["inventory"]) + float(row.get("inventory_end_units", row.get("inventory_units", 0.0)))
		totals["production"] = float(totals["production"]) + float(row.get("production_units", 0.0))
		totals["supply"] = float(totals["supply"]) + float(row.get("supply_units", 0.0))
		totals["demand"] = float(totals["demand"]) + float(row.get("demand_units", 0.0))
		totals["unmet"] = float(totals["unmet"]) + float(row.get("unmet_units", 0.0))
		totals["imports"] = float(totals["imports"]) + float(row.get("imports_units", 0.0))
		totals["exports"] = float(totals["exports"]) + float(row.get("exports_units", 0.0))
	return totals


func _recipe_site_totals(sites: Dictionary, recipe_id: String) -> Dictionary:
	var result := {
		"count": 0,
		"last_batches": 0.0,
		"operating_target_bp": 0.0,
		"input_shortage_bp": 0.0,
	}
	for raw_site_id: Variant in sites:
		var site: Dictionary = sites[raw_site_id] as Dictionary
		if str(site.get("recipe_id", "")) != recipe_id:
			continue
		result["count"] = int(result["count"]) + 1
		result["last_batches"] = float(result["last_batches"]) + float(site.get("last_batches", 0.0))
		result["operating_target_bp"] = float(result["operating_target_bp"]) + float(site.get("operating_target_bp", 0))
		result["input_shortage_bp"] = float(result["input_shortage_bp"]) + float(site.get("last_input_shortage_bp", 0))
	return result


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
