extends SceneTree

const DIAGNOSTIC_DAYS: int = 400

var failures: int = 0
var first_wheat_export_day: int = -1
var first_wheat_target_zero_day: int = -1
var first_dawnbay_wheat_total_shortage_day: int = -1
var first_flour_zero_production_day: int = -1
var first_bread_zero_production_day: int = -1
var export_days: int = 0
var wheat_production_days: int = 0
var bread_production_days: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var economy := VNextMarketEconomy.new()
	if not economy.configure_1900():
		print("FAIL: diagnostic economy configure_1900")
		quit(1)
		return
	var dawnbay := economy.catalog.region_market_id("region:loran_dawnbay")
	var southridge := economy.catalog.region_market_id("region:loran_southridge")
	for day_index: int in range(DIAGNOSTIC_DAYS):
		var result: Dictionary = economy.settle_day(day_index)
		if not bool(result.get("success", false)):
			failures += 1
			print("FAIL: diagnostic settlement day=%d result=%s" % [day_index, JSON.stringify(result)])
			break
		var snapshot_value := economy.snapshot()
		var sites: Dictionary = snapshot_value.get("production_sites", {}) as Dictionary
		var wheat_farm: Dictionary = sites.get("southridge_wheat", {}) as Dictionary
		var flour_mill: Dictionary = sites.get("dawnbay_flour", {}) as Dictionary
		var bakery: Dictionary = sites.get("dawnbay_bakery", {}) as Dictionary
		var source_wheat := economy.commodity_snapshot(southridge, "wheat")
		var destination_wheat := economy.commodity_snapshot(dawnbay, "wheat")
		var flour := economy.commodity_snapshot(dawnbay, "flour")
		var bread := economy.commodity_snapshot(dawnbay, "bread")

		var exported := float(source_wheat.get("exports_units", 0.0))
		var wheat_batches := float(wheat_farm.get("last_batches", 0.0))
		var wheat_target := int(wheat_farm.get("operating_target_bp", 0))
		if exported > 0.0001:
			export_days += 1
			if first_wheat_export_day < 0:
				first_wheat_export_day = day_index
		if wheat_batches > 0.0001:
			wheat_production_days += 1
		if wheat_target <= 0 and first_wheat_target_zero_day < 0:
			first_wheat_target_zero_day = day_index
		if int(destination_wheat.get("shortage_bp", 0)) >= 10000 and first_dawnbay_wheat_total_shortage_day < 0:
			first_dawnbay_wheat_total_shortage_day = day_index
		if day_index > 0 and float(flour.get("production_units", 0.0)) <= 0.0001 and first_flour_zero_production_day < 0:
			first_flour_zero_production_day = day_index
		if float(bread.get("production_units", 0.0)) > 0.0001:
			bread_production_days += 1
		elif day_index > 0 and first_bread_zero_production_day < 0:
			first_bread_zero_production_day = day_index

		if day_index % 25 == 0 or day_index in [first_wheat_export_day, first_wheat_target_zero_day, first_dawnbay_wheat_total_shortage_day, DIAGNOSTIC_DAYS - 1]:
			print("ECON_CHAIN_SAMPLE day=%d wheat_target=%d wheat_batches=%.6f source_wheat_inv=%.6f source_wheat_exports=%.6f dawnbay_wheat_inv=%.6f dawnbay_wheat_imports=%.6f dawnbay_wheat_shortage=%d flour_target=%d flour_batches=%.6f flour_input_shortage=%d flour_prod=%.6f bread_target=%d bread_batches=%.6f bread_input_shortage=%d bread_prod=%.6f bread_shortage=%d" % [
				day_index,
				wheat_target,
				wheat_batches,
				float(source_wheat.get("inventory_end_units", source_wheat.get("inventory_units", 0.0))),
				exported,
				float(destination_wheat.get("inventory_end_units", destination_wheat.get("inventory_units", 0.0))),
				float(destination_wheat.get("imports_units", 0.0)),
				int(destination_wheat.get("shortage_bp", 0)),
				int(flour_mill.get("operating_target_bp", 0)),
				float(flour_mill.get("last_batches", 0.0)),
				int(flour_mill.get("last_input_shortage_bp", 0)),
				float(flour.get("production_units", 0.0)),
				int(bakery.get("operating_target_bp", 0)),
				float(bakery.get("last_batches", 0.0)),
				int(bakery.get("last_input_shortage_bp", 0)),
				float(bread.get("production_units", 0.0)),
				int(bread.get("shortage_bp", 0)),
			])

	print("ECON_CHAIN_DIAG first_wheat_export_day=%d first_wheat_target_zero_day=%d first_dawnbay_wheat_total_shortage_day=%d first_flour_zero_production_day=%d first_bread_zero_production_day=%d export_days=%d wheat_production_days=%d bread_production_days=%d" % [
		first_wheat_export_day,
		first_wheat_target_zero_day,
		first_dawnbay_wheat_total_shortage_day,
		first_flour_zero_production_day,
		first_bread_zero_production_day,
		export_days,
		wheat_production_days,
		bread_production_days,
	])
	print("VNext market economy chain diagnostic: %d checks, %d failures" % [DIAGNOSTIC_DAYS, failures])
	quit(1 if failures > 0 else 0)
