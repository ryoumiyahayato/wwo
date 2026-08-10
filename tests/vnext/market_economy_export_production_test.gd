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
	var bread_production_days := 0
	var final_wheat_target := 0
	var final_wheat_batches := 0.0
	var final_bread_shortage := 10000

	for day_index: int in range(TEST_DAYS):
		var result := economy.settle_day(day_index)
		_check(bool(result.get("success", false)), "export-production day %d settles" % day_index)
		if not bool(result.get("success", false)):
			break

		var source_wheat := economy.commodity_snapshot(southridge, "wheat")
		var destination_wheat := economy.commodity_snapshot(dawnbay, "wheat")
		var bread := economy.commodity_snapshot(dawnbay, "bread")
		if float(source_wheat.get("exports_units", 0.0)) > 0.0001:
			saw_wheat_export = true
		if float(destination_wheat.get("imports_units", 0.0)) > 0.0001:
			saw_dawnbay_wheat_import = true

		if day_index >= FINAL_WINDOW_START:
			var sites: Dictionary = economy.snapshot().get("production_sites", {}) as Dictionary
			var wheat_farm: Dictionary = sites.get("southridge_wheat", {}) as Dictionary
			if float(wheat_farm.get("last_batches", 0.0)) > 0.0001:
				wheat_production_days += 1
			if float(bread.get("production_units", 0.0)) > 0.0001:
				bread_production_days += 1
			final_wheat_target = int(wheat_farm.get("operating_target_bp", 0))
			final_wheat_batches = float(wheat_farm.get("last_batches", 0.0))
			final_bread_shortage = int(bread.get("shortage_bp", 10000))

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
