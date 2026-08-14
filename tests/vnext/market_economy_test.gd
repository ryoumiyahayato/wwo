extends SceneTree

var market_checks: int = 0
var market_failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_catalog_and_public_queries()
	_test_partial_in_transit_progress()
	_test_production_chain()
	_test_trade_capacity_and_isolation()
	_test_in_transit_observability()
	_test_supply_demand_feedback()
	_test_snapshot_restore_and_json()
	_test_determinism()
	print(
		"VNext market economy: %d checks, %d failures"
		% [market_checks, market_failures]
	)
	quit(1 if market_failures > 0 or market_checks <= 0 else 0)


func _new_economy(label: String) -> VNextMarketEconomy:
	var economy: VNextMarketEconomy = VNextMarketEconomy.new()
	var configured: bool = economy.configure_1900()
	_check(configured, "%s configures from 1900 repository data" % label)
	if not configured:
		print("CONFIG_ERROR %s: %s" % [label, economy.initialization_error])
	return economy


func _test_catalog_and_public_queries() -> void:
	var economy: VNextMarketEconomy = _new_economy("catalog")
	for raw_region_id: Variant in economy.catalog.regions:
		var catalog_region: Dictionary = economy.catalog.regions[raw_region_id] as Dictionary
	_equal(economy.catalog.commodities.size(), 67, "catalog keeps the 67 existing commodity definitions")
	_equal(economy.catalog.recipes.size(), 38, "catalog keeps the 38 existing production recipes")
	_equal(economy.catalog.production_sites.size(), 49, "catalog keeps the 49 existing production sites")
	_equal(economy.region_market_ids().size(), 8, "catalog exposes eight regional markets")
	_equal(economy.country_market_ids().size(), 2, "catalog exposes two national markets")
	_equal(
		int(economy.catalog.source_summary.get("historical_country_count", 0)),
		50,
		"catalog reads the real 1900 compact historical country table"
	)
	var region_id: String = _region(economy, "region_loran_dawnbay")
	var country_id: String = _country(economy, "country_loran_federation")
	var region: Dictionary = economy.region_snapshot(region_id)
	var country: Dictionary = economy.country_snapshot(country_id)
	_check(not region.is_empty(), "regional snapshot is public")
	_check(not country.is_empty(), "national snapshot is public")
	_check((region.get("commodities", {}) as Dictionary).has("wheat"), "regional snapshot lists commodities")
	_check(
		(economy.commodity_snapshot(region_id, "wheat").get("price_centimes", 0) as int) > 0,
		"commodity query exposes a positive current price"
	)
	_check(
		economy.commodity_snapshot(region_id, "wheat").has("inventory_units"),
		"commodity query exposes inventory"
	)
	_check(
		economy.commodity_snapshot(region_id, "wheat").has("imports_units"),
		"commodity query exposes imports"
	)
	_check(
		economy.commodity_snapshot(region_id, "wheat").has("exports_units"),
		"commodity query exposes exports"
	)
	_check(
		economy.commodity_snapshot(region_id, "wheat").has("in_transit_import_units"),
		"commodity query exposes outstanding in-transit imports"
	)


func _test_production_chain() -> void:
	var economy: VNextMarketEconomy = _new_economy("production chain")
	var result: Dictionary = economy.settle_day(0)
	_check(bool(result.get("success", false)), "first market day settles")
	var country_id: String = _country(economy, "country_loran_federation")
	var commodities: Dictionary = economy.country_snapshot(country_id).get("commodities", {}) as Dictionary
	for commodity_id: String in ["coal", "iron_ore", "pig_iron", "steel"]:
		var row: Dictionary = commodities.get(commodity_id, {}) as Dictionary
		_check(
			float(row.get("production_units", 0.0)) > 0.0,
			"%s has production after the first day" % commodity_id
		)
	var steel: Dictionary = commodities.get("steel", {}) as Dictionary
	var pig_iron: Dictionary = commodities.get("pig_iron", {}) as Dictionary
	_check(
		float(steel.get("industrial_input_units", 0.0)) > 0.0,
		"steel is consumed as an intermediate input"
	)
	_check(
		float(pig_iron.get("production_units", 0.0)) > 0.0,
		"pig iron exists before steel in the production chain"
	)
	_check(economy.validate_integrity(), "physical flow ledger is valid after production")


func _test_trade_capacity_and_isolation() -> void:
	var economy: VNextMarketEconomy = _new_economy("trade")
	var origin_id: String = _region(economy, "region_loran_riverback")
	var destination_id: String = _region(economy, "region_loran_dawnbay")
	_check(economy.set_region_inventory(origin_id, "clothing", 200000.0), "origin stock can be prepared")
	_check(economy.set_region_inventory(destination_id, "clothing", 0.0), "destination stock can be depleted")
	_check(bool(economy.settle_day(0).get("success", false)), "trade dispatch day settles")
	var shipment: Dictionary = _find_shipment(
		economy.snapshot(), origin_id, destination_id, "clothing"
	)
	_check(not shipment.is_empty(), "shortage creates an in-transit shipment")
	_check(float(shipment.get("freight_cost_centimes", 0.0)) > 0.0, "shipment pays route freight")
	_check(float(shipment.get("distance_days", 0.0)) > 0.0, "shipment retains route distance")
	_check(int(shipment.get("duration_hours", 0)) > 0, "shipment retains route duration")
	_check((shipment.get("route_edge_ids", []) as Array).size() > 0, "shipment retains route edges")
	_check(bool(economy.settle_day(1).get("success", false)), "arrival day settles")
	var delivered: Dictionary = economy.commodity_snapshot(destination_id, "clothing")
	_check(float(delivered.get("imports_units", 0.0)) > 0.0, "shipment delivery records imports")

	var capped: VNextMarketEconomy = _new_economy("fixture transport budget")
	var capped_origin: String = _region(capped, "region_loran_riverback")
	var capped_destination: String = _region(capped, "region_loran_dawnbay")
	_check(
		capped.set_fixture_route_budget("route:loran_dawnbay_riverback", 1.0),
		"fixture route budget can be reduced without claiming physical capacity authority"
	)
	_check(capped.set_region_inventory(capped_origin, "clothing", 200000.0), "capped origin stock prepared")
	_check(capped.set_region_inventory(capped_destination, "clothing", 0.0), "capped destination stock prepared")
	_check(bool(capped.settle_day(0).get("success", false)), "fixture-budget-limited day settles")
	var capped_shipment: Dictionary = _find_shipment(
		capped.snapshot(), capped_origin, capped_destination, "clothing"
	)
	_check(
		capped_shipment.is_empty() or float(capped_shipment.get("units", 0.0)) <= 1.0001,
		"fixture transport budget limits isolated Economy shipment units"
	)

	var isolated: VNextMarketEconomy = _new_economy("isolated markets")
	var isolated_origin: String = _region(isolated, "region_loran_riverback")
	var isolated_destination: String = _region(isolated, "region_loran_dawnbay")
	for edge: Dictionary in isolated.catalog.transport_edges:
		_check(
			isolated.set_fixture_route_budget(str(edge.get("edge_id", "")), 0.0),
			"all fixture route budgets can be closed"
		)
	_check(isolated.set_region_inventory(isolated_origin, "clothing", 200000.0), "isolated origin stock prepared")
	_check(isolated.set_region_inventory(isolated_destination, "clothing", 0.0), "isolated destination stock prepared")
	_check(bool(isolated.settle_day(0).get("success", false)), "isolated market day settles")
	_check(
		_find_shipment(isolated.snapshot(), isolated_origin, isolated_destination, "clothing").is_empty(),
		"market fixture isolation prevents cost-free teleportation"
	)


func _test_in_transit_observability() -> void:
	var economy: VNextMarketEconomy = _new_economy("in-transit observation")
	var fast_origin: String = _region(economy, "region_loran_dawnbay")
	var slow_origin: String = _region(economy, "region_loran_southridge")
	var destination: String = _region(economy, "region_loran_riverback")
	var commodity_id: String = "coal"
	var fast_edge: String = "route:loran_dawnbay_riverback"
	var slow_edge: String = "route:loran_riverback_southridge"
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(
			economy.set_fixture_route_budget(str(edge.get("edge_id", "")), 0.0),
			"observation fixture closes unrelated route budget"
		)
	_check(economy.set_fixture_route_budget(fast_edge, 1.0), "18-hour fixture route is enabled")
	_check(economy.set_fixture_route_budget(slow_edge, 1.0), "32-hour fixture route is enabled")
	_check(economy.set_region_inventory(fast_origin, commodity_id, 200000.0), "fast source stock prepared")
	_check(economy.set_region_inventory(slow_origin, commodity_id, 200000.0), "slow source stock prepared")
	_check(economy.set_region_inventory(destination, commodity_id, 0.0), "inbound destination depleted")
	_check(bool(economy.settle_day(0).get("success", false)), "multi-route dispatch day settles")
	var day0_snapshot: Dictionary = economy.snapshot()
	var day0_outstanding: float = _outstanding_units(day0_snapshot, destination, commodity_id)
	var day0_observed: float = float(
		economy.commodity_snapshot(destination, commodity_id).get("in_transit_import_units", 0.0)
	)
	_check(_active_inbound_count(day0_snapshot, destination, commodity_id) >= 2, "multiple simultaneous inbound shipments exist")
	_check(day0_outstanding > 1.5, "multiple shipments contribute to outstanding pipeline quantity")
	_check(is_equal_approx(day0_observed, day0_outstanding), "day-0 observation equals authoritative active cargo")

	_check(economy.set_fixture_route_budget(fast_edge, 0.0), "fast route fixture budget closes after dispatch")
	_check(economy.set_fixture_route_budget(slow_edge, 0.0), "slow route fixture budget closes after dispatch")
	_check(bool(economy.settle_day(1).get("success", false)), "intermediate shipment day settles")
	var day1_snapshot: Dictionary = economy.snapshot()
	var day1_outstanding: float = _outstanding_units(day1_snapshot, destination, commodity_id)
	var day1_observed: float = float(
		economy.commodity_snapshot(destination, commodity_id).get("in_transit_import_units", 0.0)
	)
	_check(day1_outstanding > 0.0, "32-hour cargo remains active on intermediate day")
	_check(day1_outstanding < day0_outstanding, "18-hour arrival partially clears simultaneous pipeline")
	_check(is_equal_approx(day1_observed, day1_outstanding), "intermediate observation equals remaining active cargo")

	var encoded: String = JSON.stringify(day1_snapshot)
	var parsed: Variant = JSON.parse_string(encoded)
	var restored: VNextMarketEconomy = _new_economy("in-transit resume")
	_check(parsed is Dictionary and economy.restore(parsed as Dictionary), "baseline restores from the same in-transit snapshot")
	_check(parsed is Dictionary and restored.restore(parsed as Dictionary), "in-transit snapshot resumes after JSON round trip")
	var restored_observed: float = float(
		restored.commodity_snapshot(destination, commodity_id).get("in_transit_import_units", 0.0)
	)
	_check(is_equal_approx(restored_observed, day1_outstanding), "restored observation is rebuilt from active shipment queue")
	var persisted_regions: Dictionary = restored.snapshot().get("region_states", {}) as Dictionary
	var persisted_destination: Dictionary = persisted_regions.get(destination, {}) as Dictionary
	var persisted_commodities: Dictionary = persisted_destination.get("commodities", {}) as Dictionary
	_check(
		not (persisted_commodities.get(commodity_id, {}) as Dictionary).has("in_transit_import_units"),
		"derived in-transit observation is not duplicated in persisted market state"
	)
	var replayed: VNextMarketEconomy = _new_economy("in-transit deterministic replay")
	_check(parsed is Dictionary and replayed.restore(parsed as Dictionary), "same persisted snapshot restores into a second replay")
	_equal(
		JSON.stringify(restored.snapshot()),
		JSON.stringify(replayed.snapshot()),
		"restored snapshots are identical before continuation"
	)

	_check(bool(economy.settle_day(2).get("success", false)), "final arrival day settles")
	_check(bool(restored.settle_day(2).get("success", false)), "restored final arrival day settles")
	_check(bool(replayed.settle_day(2).get("success", false)), "replayed final arrival day settles")
	_check(
		is_zero_approx(float(economy.commodity_snapshot(destination, commodity_id).get("in_transit_import_units", -1.0))),
		"arrival clears current in-transit observation"
	)
	_check(
		is_zero_approx(float(restored.commodity_snapshot(destination, commodity_id).get("in_transit_import_units", -1.0))),
		"arrival clears restored in-transit observation"
	)
	_check(economy.validate_integrity(), "multi-day observation repair preserves physical conservation")
	_equal(JSON.stringify(restored.snapshot()), JSON.stringify(economy.snapshot()), "snapshot/resume replay remains deterministic through arrival")
	_equal(JSON.stringify(restored.snapshot()), JSON.stringify(replayed.snapshot()), "snapshot/resume continuation is deterministic")

func _test_partial_in_transit_progress() -> void:
	var economy: VNextMarketEconomy = _new_economy("partial in-transit progress")
	var origin: String = _region(economy, "region_loran_southridge")
	var destination: String = _region(economy, "region_loran_riverback")
	var commodity_id: String = "coal"
	var slow_edge: String = "route:loran_riverback_southridge"
	for edge: Dictionary in economy.catalog.transport_edges:
		_check(economy.set_fixture_route_budget(str(edge.get("edge_id", "")), 0.0), "partial-progress fixture closes unrelated route budget")
	_check(economy.set_fixture_route_budget(slow_edge, 10.0), "partial-progress slow route is enabled")
	_check(economy.set_region_inventory(origin, commodity_id, 200000.0), "partial-progress source stock prepared")
	_check(economy.set_region_inventory(destination, commodity_id, 0.0), "partial-progress destination depleted")
	_check(bool(economy.settle_day(0).get("success", false)), "partial-progress dispatch day settles")
	var dispatched: Dictionary = _find_shipment(economy.snapshot(), origin, destination, commodity_id)
	_check(not dispatched.is_empty(), "partial-progress creates a shipment")
	var shipment_id: String = str(dispatched.get("shipment_id", ""))
	var total_units: float = float(dispatched.get("total_units", 0.0))
	var partial_units: float = total_units * 0.5
	var inventory_before: float = economy.inventory_units(destination, commodity_id)
	var progress: Dictionary = economy.apply_shipment_progress(shipment_id, partial_units, 0)
	_check(bool(progress.get("success", false)), "partial progress is accepted before arrival")
	var after_progress: Dictionary = economy.snapshot()
	var active: Dictionary = _find_shipment(after_progress, origin, destination, commodity_id)
	_check(not active.is_empty(), "partially progressed shipment remains active")
	_check(is_equal_approx(float(active.get("units", 0.0)), total_units - partial_units), "outstanding units exclude delivered partial cargo")
	_check(is_equal_approx(float(active.get("delivered_units", 0.0)), partial_units), "shipment records delivered partial cargo")
	_check(is_equal_approx(float(active.get("progress_units", 0.0)), partial_units), "shipment records cumulative progress")
	_check(is_equal_approx(economy.inventory_units(destination, commodity_id) - inventory_before, partial_units), "partial delivery enters destination inventory")
	_check(is_equal_approx(_outstanding_units(after_progress, destination, commodity_id), total_units - partial_units), "in-transit metric remains outstanding cargo")
	_check(_active_inbound_count(after_progress, destination, commodity_id) == 1, "partial progress does not remove active shipment")
	_check(economy.validate_integrity(), "partial progress preserves physical conservation")
	_check(economy.set_fixture_route_budget(slow_edge, 0.0), "partial-progress route closes after dispatch")
	var saved: Dictionary = economy.snapshot()
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var restored: VNextMarketEconomy = _new_economy("partial in-transit restore")
	_check(parsed is Dictionary and restored.restore(parsed as Dictionary), "partial shipment restores from JSON mid-transit")
	_check(parsed is Dictionary and economy.restore(parsed as Dictionary), "partial baseline restores from the same JSON snapshot")
	_equal(JSON.stringify(restored.snapshot()), JSON.stringify(economy.snapshot()), "partial mid-transit restore is exact before continuation")
	var history_before: int = (saved.get("shipment_history", []) as Array).size()
	_check(bool(economy.settle_day(1).get("success", false)), "partial shipment intermediate day settles")
	_check(bool(restored.settle_day(1).get("success", false)), "restored partial shipment intermediate day settles")
	_check(bool(economy.settle_day(2).get("success", false)), "partial shipment delivery day settles")
	_check(bool(restored.settle_day(2).get("success", false)), "restored partial shipment delivery day settles")
	var delivered_snapshot: Dictionary = economy.snapshot()
	var restored_delivered_snapshot: Dictionary = restored.snapshot()
	_check(_active_inbound_count(delivered_snapshot, destination, commodity_id) == 0, "delivery removes the completed shipment")
	_check(is_zero_approx(_outstanding_units(delivered_snapshot, destination, commodity_id)), "delivery removes outstanding in-transit units")
	_check((delivered_snapshot.get("shipment_history", []) as Array).size() > history_before, "delivery records shipment history")
	_check(economy.validate_integrity() and restored.validate_integrity(), "partial restore continuation preserves conservation")
	_equal(JSON.stringify(restored_delivered_snapshot), JSON.stringify(delivered_snapshot), "partial restore continuation is deterministic")


func _test_supply_demand_feedback() -> void:
	var baseline: VNextMarketEconomy = _new_economy("feedback baseline")
	_check(bool(baseline.settle_day(0).get("success", false)), "baseline feedback day settles")
	var forgeplain: String = _region(baseline, "region_loran_forgeplain")
	var baseline_coal: Dictionary = baseline.commodity_snapshot(forgeplain, "coal")
	var baseline_coal_price: int = int(baseline_coal.get("price_centimes", 0))

	var supply_shock: VNextMarketEconomy = _new_economy("supply shock")
	var shock_result: Dictionary = supply_shock.apply_market_shock(
		"shock:coal_mine_closure",
		forgeplain,
		"coal",
		0,
		10000,
		3,
		0,
		0,
		"temporary coal supply loss"
	)
	_check(bool(shock_result.get("success", false)), "supply shock is accepted")
	_check(bool(supply_shock.settle_day(0).get("success", false)), "supply shock day settles")
	var shock_coal: Dictionary = supply_shock.commodity_snapshot(forgeplain, "coal")
	_check(
		float(shock_coal.get("production_units", 0.0))
		< float(baseline_coal.get("production_units", 0.0)),
		"supply loss reduces production"
	)
	_check(
		int(shock_coal.get("price_centimes", 0)) >= baseline_coal_price,
		"coal price responds upward to a supply loss"
	)

	var demand_shock: VNextMarketEconomy = _new_economy("demand shock")
	var demand_result: Dictionary = demand_shock.apply_market_shock(
		"shock:bread_demand",
		_region(demand_shock, "region_loran_dawnbay"),
		"bread",
		10000,
		20000,
		3,
		0,
		0,
		"temporary bread demand surge"
	)
	_check(bool(demand_result.get("success", false)), "demand shock is accepted")
	_check(bool(demand_shock.settle_day(0).get("success", false)), "demand shock day settles")
	var demand_bread: Dictionary = demand_shock.commodity_snapshot(
		_region(demand_shock, "region_loran_dawnbay"), "bread"
	)
	var normal_bread: Dictionary = baseline.commodity_snapshot(
		_region(baseline, "region_loran_dawnbay"), "bread"
	)
	_check(
		float(demand_bread.get("demand_units", 0.0))
		> float(normal_bread.get("demand_units", 0.0)),
		"demand shock increases demand"
	)
	_check(
		int(demand_bread.get("price_centimes", 0))
		>= int(normal_bread.get("price_centimes", 0)),
		"demand shock creates upward price pressure"
	)

	var shortage: VNextMarketEconomy = _new_economy("inventory shortage")
	var shortage_region: String = _region(shortage, "region_loran_dawnbay")
	_check(shortage.set_region_inventory(shortage_region, "clothing", 0.0), "shortage inventory can be forced")
	_check(bool(shortage.settle_day(0).get("success", false)), "shortage day settles")
	var shortage_clothing: Dictionary = shortage.commodity_snapshot(shortage_region, "clothing")
	_check(float(shortage_clothing.get("unmet_units", 0.0)) > 0.0, "inventory shortage creates unmet demand")
	_check(int(shortage_clothing.get("shortage_bp", 0)) > 0, "public shortage metric is nonzero")

	var oversupply: VNextMarketEconomy = _new_economy("inventory oversupply")
	var oversupply_region: String = _region(oversupply, "region_loran_dawnbay")
	_check(oversupply.set_region_inventory(oversupply_region, "bread", 1000000.0), "surplus inventory can be prepared")
	_check(bool(oversupply.settle_day(0).get("success", false)), "oversupply day settles")
	var oversupply_bread: Dictionary = oversupply.commodity_snapshot(oversupply_region, "bread")
	_check(
		int(oversupply_bread.get("price_centimes", 0))
		<= int(normal_bread.get("price_centimes", 0)),
		"inventory surplus creates downward price pressure"
	)

	var input_shortage: VNextMarketEconomy = _new_economy("input shortage")
	var input_region: String = _region(input_shortage, "region_loran_forgeplain")
	for commodity_id: String in ["iron_ore", "coke", "limestone"]:
		_check(
			input_shortage.set_region_inventory(input_region, commodity_id, 0.0),
			"input shortage inventory can be depleted: %s" % commodity_id
		)
	_check(bool(input_shortage.settle_day(0).get("success", false)), "input shortage day settles")
	var steelworks_shortage: bool = false
	for raw_site_id: Variant in input_shortage.production_sites:
		var site: Dictionary = input_shortage.production_sites[raw_site_id] as Dictionary
		if str(site.get("recipe_id", "")) == "steelworks":
			steelworks_shortage = steelworks_shortage or int(site.get("last_input_shortage_bp", 0)) > 0
	_check(steelworks_shortage, "steel production records insufficient intermediate inputs")


func _test_snapshot_restore_and_json() -> void:
	var original: VNextMarketEconomy = _new_economy("snapshot source")
	_check(bool(original.advance_days(5).get("success", false)), "snapshot source advances five days")
	var saved: Dictionary = original.snapshot()
	var encoded: String = JSON.stringify(saved)
	var parsed: Variant = JSON.parse_string(encoded)
	_check(parsed is Dictionary, "snapshot survives JSON encoding")
	var restored: VNextMarketEconomy = _new_economy("snapshot target")
	_check(restored.restore(parsed as Dictionary), "snapshot restores with validation")
	var restored_snapshot: Dictionary = restored.snapshot()
	_check(restored.last_day_index() == original.last_day_index(), "JSON restore keeps the last settled day")
	_check(restored.validate_integrity(), "JSON restore keeps physical conservation")
	_equal(
		int((restored_snapshot.get("route_network", {}) as Dictionary).get("fixture_edge_remaining_budget", {}).size()),
		int((saved.get("route_network", {}) as Dictionary).get("fixture_edge_remaining_budget", {}).size()),
		"JSON restore keeps every fixture route budget state")
	var sample_region: String = _region(original, "region_loran_dawnbay")
	_check(is_equal_approx(restored.inventory_units(sample_region, "bread"), original.inventory_units(sample_region, "bread")), "JSON restore keeps physical inventory")
	_equal(restored.current_price(sample_region, "bread"), original.current_price(sample_region, "bread"), "JSON restore keeps price state")
	_equal(restored.snapshot().get("shipments", []).size(), saved.get("shipments", []).size(), "JSON restore keeps in-transit shipment count")
	_check(
		original.history_snapshot(
			_region(original, "region_loran_dawnbay"), "bread", 5
		).size() == 5,
		"history query returns the requested daily window"
	)
	var before_invalid: String = JSON.stringify(restored.snapshot())
	var invalid: Dictionary = restored.snapshot()
	invalid["schema_id"] = "wrong_schema"
	_check(not restored.restore(invalid), "invalid snapshot schema is rejected")
	_equal(
		JSON.stringify(restored.snapshot()),
		before_invalid,
		"rejected snapshot does not mutate live state"
	)


func _test_determinism() -> void:
	var first: VNextMarketEconomy = _new_economy("determinism first")
	var second: VNextMarketEconomy = _new_economy("determinism second")
	_check(bool(first.advance_days(30).get("success", false)), "first deterministic run advances")
	_check(bool(second.advance_days(30).get("success", false)), "second deterministic run advances")
	_equal(
		JSON.stringify(first.snapshot()),
		JSON.stringify(second.snapshot()),
		"same inputs produce the same 30-day state"
	)


func _find_shipment(
	snapshot_value: Dictionary, origin_id: String, destination_id: String, commodity_id: String
) -> Dictionary:
	for raw_value: Variant in snapshot_value.get("shipments", []) as Array:
		if not raw_value is Dictionary:
			continue
		var shipment: Dictionary = raw_value as Dictionary
		if (
			str(shipment.get("origin_market_id", "")) == origin_id
			and str(shipment.get("destination_market_id", "")) == destination_id
			and str(shipment.get("commodity_id", "")) == commodity_id
		):
			return shipment
	return {}


func _outstanding_units(
	snapshot_value: Dictionary, destination_id: String, commodity_id: String
) -> float:
	var total: float = 0.0
	for raw_value: Variant in snapshot_value.get("shipments", []) as Array:
		if not raw_value is Dictionary:
			continue
		var shipment: Dictionary = raw_value as Dictionary
		if (
			str(shipment.get("destination_market_id", "")) == destination_id
			and str(shipment.get("commodity_id", "")) == commodity_id
			and str(shipment.get("status", "")) == "in_transit"
		):
			total += float(shipment.get("units", 0.0))
	return total


func _active_inbound_count(
	snapshot_value: Dictionary, destination_id: String, commodity_id: String
) -> int:
	var count: int = 0
	for raw_value: Variant in snapshot_value.get("shipments", []) as Array:
		if not raw_value is Dictionary:
			continue
		var shipment: Dictionary = raw_value as Dictionary
		if (
			str(shipment.get("destination_market_id", "")) == destination_id
			and str(shipment.get("commodity_id", "")) == commodity_id
			and str(shipment.get("status", "")) == "in_transit"
		):
			count += 1
	return count


func _region(economy: VNextMarketEconomy, source_region_id: String) -> String:
	var normalized_id: String = source_region_id
	if not normalized_id.begins_with("region:"):
		normalized_id = "region:" + normalized_id.trim_prefix("region_")
	return economy.catalog.region_market_id(normalized_id)


func _country(economy: VNextMarketEconomy, source_country_id: String) -> String:
	var normalized_id: String = source_country_id
	if not normalized_id.begins_with("country:"):
		normalized_id = "country:" + normalized_id.trim_prefix("country_")
	return economy.catalog.country_market_id(normalized_id)


func _check(condition: bool, message: String) -> void:
	market_checks += 1
	if not condition:
		market_failures += 1
		print("FAIL: " + message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	market_checks += 1
	if actual != expected:
		market_failures += 1
		print("FAIL: %s actual=%s expected=%s" % [message, str(actual), str(expected)])