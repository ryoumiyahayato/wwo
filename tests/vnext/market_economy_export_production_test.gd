extends SceneTree

const TEST_DAYS: int = 240
const FINAL_WINDOW_START: int = 180

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy := VNextMarketEconomy.new()
	_check(economy.configure_1900(), "export-production fixture configures")
	if failures > 0:
		_finish()
		return

	var dawnbay := economy.catalog.region_market_id("region:loran_dawnbay")
	var southridge := economy.catalog.region_market_id("region:loran_southridge")
	var saw_wheat_export := false
	var saw_dawnbay_wheat_import := false
	var wheat_production_days := 0
	var flour_production_days := 0
	var bread_production_days := 0
	var bread_inventory_days := 0
	var bread_non_total_shortage_days := 0
	var flour_non_total_shortage_days := 0
	var flour_mill_active_days := 0
	var flour_mill_input_shortage_days := 0
	var bakery_active_days := 0
	var bakery_input_shortage_days := 0
	var final_wheat_target := 0
	var final_wheat_batches := 0.0
	var final_bread_shortage := 10000
	var final_bread_inventory := 0.0
	var final_flour_inventory := 0.0
	var final_wheat_inventory := 0.0
	var total_bread_production := 0.0
	var total_bread_demand := 0.0
	var total_flour_production := 0.0

	for day_index: int in range(TEST_DAYS):
		var result := economy.settle_day(day_index)
		_check(bool(result.get("success", false)), "export-production day %d settles" % day_index)
		if not bool(result.get("success", false)):
			break

		var source_wheat := economy.commodity_snapshot(southridge, "wheat")
		var destination_wheat := economy.commodity_snapshot(dawnbay, "wheat")
		var flour := economy.commodity_snapshot(dawnbay, "flour")
		var bread := economy.commodity_snapshot(dawnbay, "bread")
		if float(source_wheat.get("exports_units", 0.0)) > 0.0001:
			saw_wheat_export = true
		if float(destination_wheat.get("imports_units", 0.0)) > 0.0001:
			saw_dawnbay_wheat_import = true

		if day_index >= FINAL_WINDOW_START:
			var sites: Dictionary = economy.snapshot().get("production_sites", {}) as Dictionary
			var wheat_farm: Dictionary = sites.get("southridge_wheat", {}) as Dictionary
			var flour_mill: Dictionary = sites.get("dawnbay_flour", {}) as Dictionary
			var bakery: Dictionary = sites.get("dawnbay_bakery", {}) as Dictionary
			if float(wheat_farm.get("last_batches", 0.0)) > 0.0001:
				wheat_production_days += 1
			if float(flour.get("production_units", 0.0)) > 0.0001:
				flour_production_days += 1
			if float(bread.get("production_units", 0.0)) > 0.0001:
				bread_production_days += 1
			if float(bread.get("inventory_end_units", bread.get("inventory_units", 0.0))) > 0.0001:
				bread_inventory_days += 1
			if int(bread.get("shortage_bp", 10000)) < 10000:
				bread_non_total_shortage_days += 1
			if int(flour.get("shortage_bp", 10000)) < 10000:
				flour_non_total_shortage_days += 1
			if float(flour_mill.get("last_batches", 0.0)) > 0.0001:
				flour_mill_active_days += 1
			if int(flour_mill.get("last_input_shortage_bp", 0)) > 0:
				flour_mill_input_shortage_days += 1
			if float(bakery.get("last_batches", 0.0)) > 0.0001:
				bakery_active_days += 1
			if int(bakery.get("last_input_shortage_bp", 0)) > 0:
				bakery_input_shortage_days += 1
			total_bread_production += float(bread.get("production_units", 0.0))
			total_bread_demand += float(bread.get("demand_units", 0.0))
			total_flour_production += float(flour.get("production_units", 0.0))
			final_wheat_target = int(wheat_farm.get("operating_target_bp", 0))
			final_wheat_batches = float(wheat_farm.get("last_batches", 0.0))
			final_bread_shortage = int(bread.get("shortage_bp", 10000))
			final_bread_inventory = float(bread.get("inventory_end_units", bread.get("inventory_units", 0.0)))
			final_flour_inventory = float(flour.get("inventory_end_units", flour.get("inventory_units", 0.0)))
			final_wheat_inventory = float(destination_wheat.get("inventory_end_units", destination_wheat.get("inventory_units", 0.0)))
			if day_index % 10 == 0 or day_index == TEST_DAYS - 1:
				print("ECON_EXPORT_SAMPLE day=%d wheat_target=%d wheat_batches=%.6f wheat_inv=%.6f wheat_import=%.6f wheat_shortage=%d flour_target=%d flour_batches=%.6f flour_input_shortage=%d flour_prod=%.6f flour_inv=%.6f flour_shortage=%d bakery_target=%d bakery_batches=%.6f bakery_input_shortage=%d bread_prod=%.6f bread_inv=%.6f bread_shortage=%d bread_demand=%.6f" % [
					day_index,
					final_wheat_target,
					final_wheat_batches,
					final_wheat_inventory,
					float(destination_wheat.get("imports_units", 0.0)),
					int(destination_wheat.get("shortage_bp", 0)),
					int(flour_mill.get("operating_target_bp", 0)),
					float(flour_mill.get("last_batches", 0.0)),
					int(flour_mill.get("last_input_shortage_bp", 0)),
					float(flour.get("production_units", 0.0)),
					final_flour_inventory,
					int(flour.get("shortage_bp", 0)),
					int(bakery.get("operating_target_bp", 0)),
					float(bakery.get("last_batches", 0.0)),
					int(bakery.get("last_input_shortage_bp", 0)),
					float(bread.get("production_units", 0.0)),
					final_bread_inventory,
					final_bread_shortage,
					float(bread.get("demand_units", 0.0)),
				])

	print("ECON_EXPORT_DIAG wheat_production_days=%d flour_production_days=%d bread_production_days=%d bread_inventory_days=%d bread_non_total_shortage_days=%d flour_non_total_shortage_days=%d flour_mill_active_days=%d flour_mill_input_shortage_days=%d bakery_active_days=%d bakery_input_shortage_days=%d total_bread_production=%.6f total_bread_demand=%.6f total_flour_production=%.6f final_wheat_target=%d final_wheat_batches=%.6f final_wheat_inventory=%.6f final_flour_inventory=%.6f final_bread_inventory=%.6f final_bread_shortage=%d" % [
		wheat_production_days,
		flour_production_days,
		bread_production_days,
		bread_inventory_days,
		bread_non_total_shortage_days,
		flour_non_total_shortage_days,
		flour_mill_active_days,
		flour_mill_input_shortage_days,
		bakery_active_days,
		bakery_input_shortage_days,
		total_bread_production,
		total_bread_demand,
		total_flour_production,
		final_wheat_target,
		final_wheat_batches,
		final_wheat_inventory,
		final_flour_inventory,
		final_bread_inventory,
		final_bread_shortage,
	])

	_check(saw_wheat_export, "remote wheat demand produces physical exports")
	_check(saw_dawnbay_wheat_import, "remote wheat demand produces physical imports")
	_check(wheat_production_days >= 45, "export supplier remains productive through the final 60-day window")
	_check(bread_production_days >= 45, "downstream bread production remains active through the final 60-day window")
	_check(final_wheat_target > 0, "export-only wheat producer does not ratchet its operating target to zero")
	_check(final_wheat_batches > 0.0, "export-only wheat producer is still physically producing")
	_check(final_bread_shortage < 10000, "downstream bread market is not locked in total shortage")
	_check(economy.validate_integrity(), "export-driven production preserves physical accounting")
	_finish()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func _finish() -> void:
	print("VNext market economy export production: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)
