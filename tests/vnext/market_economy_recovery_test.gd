extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_shortage_and_surplus_recovery()
	_test_transport_recovery()
	_test_extreme_legal_inputs()
	print("VNext market economy recovery: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _new_economy(label: String) -> VNextMarketEconomy:
	var economy := VNextMarketEconomy.new()
	_check(economy.configure_1900(), "%s configures" % label)
	return economy


func _test_shortage_and_surplus_recovery() -> void:
	var control := _new_economy("recovery control")
	var shortage := _new_economy("shortage recovery")
	var surplus := _new_economy("surplus recovery")
	var control_market := _region(control, "region_loran_dawnbay")
	var shortage_market := _region(shortage, "region_loran_dawnbay")
	var surplus_market := _region(surplus, "region_loran_dawnbay")
	for pair: Array in [
		[control, control_market],
		[shortage, shortage_market],
		[surplus, surplus_market],
	]:
		_check((pair[0] as VNextMarketEconomy).set_region_inventory(str(pair[1]), "bread", 0.0), "recovery fixture starts with equivalent bread stock")

	_check(bool(shortage.apply_market_shock(
		"test_shortage_recovery", shortage_market, "bread", 0, 10000, 1, 0, 0,
		"one-day supply interruption"
	).get("success", false)), "shortage recovery shock is accepted")
	_check(bool(surplus.apply_market_shock(
		"test_surplus_recovery", surplus_market, "bread", 40000, 10000, 1, 0, 0,
		"one-day supply surge"
	).get("success", false)), "surplus recovery shock is accepted")

	_check(bool(control.settle_day(0).get("success", false)), "control day zero settles")
	_check(bool(shortage.settle_day(0).get("success", false)), "shortage day zero settles")
	_check(bool(surplus.settle_day(0).get("success", false)), "surplus day zero settles")
	var control_day0 := control.current_price(control_market, "bread")
	var shortage_day0 := shortage.current_price(shortage_market, "bread")
	var surplus_day0 := surplus.current_price(surplus_market, "bread")
	var shortage_gap0 := absi(shortage_day0 - control_day0)
	var surplus_gap0 := absi(surplus_day0 - control_day0)
	_check(shortage_day0 > control_day0, "one-day shortage creates an upward relative price gap")
	_check(surplus_day0 < control_day0, "one-day surplus creates a downward relative price gap")

	for day_index: int in range(1, 46):
		_check(bool(control.settle_day(day_index).get("success", false)), "control recovery day %d settles" % day_index)
		_check(bool(shortage.settle_day(day_index).get("success", false)), "shortage recovery day %d settles" % day_index)
		_check(bool(surplus.settle_day(day_index).get("success", false)), "surplus recovery day %d settles" % day_index)
	var shortage_gap45 := absi(shortage.current_price(shortage_market, "bread") - control.current_price(control_market, "bread"))
	var surplus_gap45 := absi(surplus.current_price(surplus_market, "bread") - control.current_price(control_market, "bread"))
	_check(shortage_gap45 < shortage_gap0, "temporary shortage price effect converges toward control")
	_check(surplus_gap45 < surplus_gap0, "temporary surplus price effect converges toward control")
	_check(shortage.validate_integrity(), "shortage recovery preserves physical accounting")
	_check(surplus.validate_integrity(), "surplus recovery preserves physical accounting")


func _test_transport_recovery() -> void:
	var economy := _new_economy("transport recovery")
	var origin := _region(economy, "region_loran_riverback")
	var destination := _region(economy, "region_loran_dawnbay")
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(economy.set_route_capacity(str(edge.get("edge_id", "")), 0.0), "transport edge can be closed")
	_check(economy.set_region_inventory(origin, "clothing", 200000.0), "transport recovery origin stock prepared")
	_check(economy.set_region_inventory(destination, "clothing", 0.0), "transport recovery destination stock depleted")
	_check(bool(economy.settle_day(0).get("success", false)), "closed-network day settles")
	_check(_find_shipment(economy.snapshot(), origin, destination, "clothing").is_empty(), "closed transport prevents shipment")
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(economy.restore_route_capacity(str(edge.get("edge_id", ""))), "transport edge restores default capacity")
	_check(bool(economy.settle_day(1).get("success", false)), "restored-network day settles")
	_check(not _find_shipment(economy.snapshot(), origin, destination, "clothing").is_empty(), "restored transport resumes physical shipment")
	_check(economy.validate_integrity(), "transport recovery preserves physical accounting")


func _test_extreme_legal_inputs() -> void:
	var economy := _new_economy("extreme legal inputs")
	var market_id := _region(economy, "region_loran_dawnbay")
	_check(economy.set_region_inventory(market_id, "bread", 0.0), "extreme fixture permits zero inventory")
	_check(bool(economy.apply_market_shock(
		"test_extreme_legal", market_id, "bread", 0, 40000, 3, 15000, 0,
		"maximum legal shortage and price shock"
	).get("success", false)), "maximum legal shock is accepted")
	var initial_price := economy.current_price(market_id, "bread")
	for day_index: int in range(3):
		_check(bool(economy.settle_day(day_index).get("success", false)), "extreme legal day %d settles" % day_index)
		var row := economy.commodity_snapshot(market_id, "bread")
		var price := int(row.get("price_centimes", 0))
		var stock := float(row.get("inventory_units", 0.0))
		_check(price > 0, "extreme legal price remains positive")
		_check(not is_nan(stock) and not is_inf(stock) and stock >= 0.0, "extreme legal stock remains finite and nonnegative")
		_check(economy.validate_integrity(), "extreme legal day preserves accounting")
	var final_price := economy.current_price(market_id, "bread")
	_check(final_price <= int(ceil(float(initial_price) * pow(1.18, 3.0))), "extreme legal price remains within compounded daily movement bounds")


func _find_shipment(snapshot_value: Dictionary, origin_id: String, destination_id: String, commodity_id: String) -> Dictionary:
	for raw_value: Variant in snapshot_value.get("shipments", []) as Array:
		if not raw_value is Dictionary:
			continue
		var shipment := raw_value as Dictionary
		if str(shipment.get("origin_market_id", "")) == origin_id and str(shipment.get("destination_market_id", "")) == destination_id and str(shipment.get("commodity_id", "")) == commodity_id:
			return shipment
	return {}


func _region(economy: VNextMarketEconomy, source_region_id: String) -> String:
	var normalized_id := source_region_id
	if not normalized_id.begins_with("region:"):
		normalized_id = "region:" + normalized_id.trim_prefix("region_")
	return economy.catalog.region_market_id(normalized_id)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)
