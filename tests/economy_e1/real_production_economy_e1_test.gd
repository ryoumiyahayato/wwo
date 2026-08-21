extends SceneTree
## Focused synthetic E1 tests.  These values are algorithm fixtures, not
## historical calibration and are deliberately small enough to audit by hand.

const EconomyScript = preload("res://scripts/economy_e1/real_production_economy_e1.gd")
const CommodityCatalogScript = preload("res://scripts/economy_e1/real_production_catalog.gd")
const NumericScript = preload("res://scripts/economy_e1/e1_numeric.gd")
const BASIS_POINTS: int = 10_000

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_numeric_helpers()
	_test_e1_01_capacity()
	_test_e1_02_missing_input()
	_test_e1_03_input_limit()
	_test_e1_04_labor_limit()
	_test_e1_resource_source_limit()
	_test_e1_05_demand_does_not_create_goods()
	_test_e1_06_output_inventory()
	_test_e1_07_input_consumption()
	_test_e1_08_buffer_delay()
	_test_e1_09_local_shortage()
	_test_e1_10_price_response()
	_test_e1_11_proportional_clearing()
	_test_e1_12_transport_ownership()
	_test_e1_13_shipment_conservation()
	_test_e1_14_physical_conservation()
	_test_e1_15_determinism()
	_test_e1_16_reordering()
	_test_e1_17_save_restore()
	_test_e1_18_source_mismatch()
	_test_failure_behavior()
	_test_alpha_catalog_salvage()
	_print_reference_trace()
	_print_complexity_sanity()
	print("REAL PRODUCTION ECONOMY E1 focused tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_numeric_helpers() -> void:
	_case(
		"NUMERIC MUL_DIV",
		NumericScript.mul_div_floor(5, 2, 3) == 3
		and NumericScript.mul_div_ceil(5, 2, 3) == 4
		and NumericScript.mul_div_floor(-5, 2, 3) == -4
		and NumericScript.mul_div_ceil(-5, 2, 3) == -3
	)


func _test_e1_01_capacity() -> void:
	var economy: Variant = _new_fixture()
	var settled: bool = _settle(economy, 0)
	var state: Dictionary = economy.get_industry_state("fixture:coal_site")
	_case("E1-01 CAPACITY", settled and int(state.get("last_actual_output", -1)) == 10_000)


func _test_e1_02_missing_input() -> void:
	var economy: Variant = _new_fixture({"miner_enabled": false, "steel_buffers": {}})
	_settle(economy, 0)
	var state: Dictionary = economy.get_industry_state("fixture:steel_site")
	_case(
		"E1-02 MISSING INPUT",
		int(state.get("last_actual_output", -1)) == 0 and str(state.get("production_constraint_reason", "")) == "input:coal"
	)


func _test_e1_03_input_limit() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_buffers": {"coal": 2_000, "iron_ore": 20_000},
	})
	_settle(economy, 0)
	var state: Dictionary = economy.get_industry_state("fixture:steel_site")
	var buffers: Dictionary = state.get("input_buffers", {}) as Dictionary
	_case(
		"E1-03 INPUT LIMIT",
		int(state.get("last_actual_output", -1)) == 2_000
		and str(state.get("production_constraint_reason", "")) == "input:coal"
		and int(buffers.get("coal", -1)) == 0
		and int(buffers.get("iron_ore", -1)) == 16_000
	)


func _test_e1_04_labor_limit() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_buffers": {"coal": 20_000, "iron_ore": 20_000},
	})
	var labor: Array[Dictionary] = _default_labor()
	for index: int in range(labor.size()):
		if str(labor[index].get("labor_class", "")) == "skilled":
			labor[index]["available_quantity"] = 1_000
	_settle(economy, 0, [], labor)
	var state: Dictionary = economy.get_industry_state("fixture:steel_site")
	_case(
		"E1-04 LABOR LIMIT",
		int(state.get("last_actual_output", -1)) == 1_000
		and str(state.get("production_constraint_reason", "")) == "labor"
	)


func _test_e1_resource_source_limit() -> void:
	var config: Dictionary = _fixture_config()
	var coal_producer: Dictionary = (config["producers"] as Array)[1] as Dictionary
	coal_producer["installed_capacity_per_day"] = 50_000
	coal_producer["resource_capacity_per_day"] = 50_000
	var coal_resource: Dictionary = (config["resource_sources"] as Array)[0] as Dictionary
	coal_resource["extraction_capacity_per_day"] = 2_000
	var economy: Variant = EconomyScript.new()
	var configured: bool = economy.configure(config)
	var settled: bool = _settle(economy, 0)
	var state: Dictionary = economy.get_industry_state("fixture:coal_site")
	_case(
		"E1 RESOURCE SOURCE LIMIT",
		configured and settled and int(state.get("last_actual_output", -1)) == 2_000
		and str(state.get("production_constraint_reason", "")) == "resource:resource:coal_bed"
	)


func _test_e1_05_demand_does_not_create_goods() -> void:
	var quiet: Variant = _new_fixture({"miner_enabled": false})
	var hungry: Variant = _new_fixture({"miner_enabled": false})
	var huge_demand: Array[Dictionary] = [{
		"demand_id": "household:huge",
		"region_id": "fixture:steel",
		"commodity_id": "steel",
		"requested_quantity": 900_000,
		"demand_class": "household",
	}]
	_settle(quiet, 0)
	_settle(hungry, 0, huge_demand)
	var quiet_output: int = int(quiet.get_industry_state("fixture:steel_site").get("last_actual_output", -1))
	var hungry_output: int = int(hungry.get_industry_state("fixture:steel_site").get("last_actual_output", -1))
	_case("E1-05 DEMAND DOES NOT CREATE GOODS", quiet_output == hungry_output)


func _test_e1_06_output_inventory() -> void:
	var economy: Variant = _new_fixture()
	_settle(economy, 0)
	var market: Dictionary = economy.get_market_state("fixture:source")
	var inventory: Dictionary = market.get("inventory", {}) as Dictionary
	_case("E1-06 OUTPUT INVENTORY", int(inventory.get("coal", -1)) == 10_000)


func _test_e1_07_input_consumption() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_buffers": {"coal": 20_000, "iron_ore": 20_000},
	})
	_settle(economy, 0)
	var state: Dictionary = economy.get_industry_state("fixture:steel_site")
	var buffers: Dictionary = state.get("input_buffers", {}) as Dictionary
	var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
	var consumed: Dictionary = metrics.get("process_inputs_consumed", {}) as Dictionary
	_case(
		"E1-07 INPUT CONSUMPTION",
		int(consumed.get("coal", -1)) == 5_000
		and int(consumed.get("iron_ore", -1)) == 10_000
		and int(buffers.get("coal", -1)) == 15_000
		and int(buffers.get("iron_ore", -1)) == 10_000
	)


func _test_e1_08_buffer_delay() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_buffers": {"coal": 10_000, "iron_ore": 20_000},
	})
	_settle(economy, 0)
	var first: int = int(economy.get_industry_state("fixture:steel_site").get("last_actual_output", -1))
	_settle(economy, 1)
	var second: int = int(economy.get_industry_state("fixture:steel_site").get("last_actual_output", -1))
	_settle(economy, 2)
	var third_state: Dictionary = economy.get_industry_state("fixture:steel_site")
	_case(
		"E1-08 BUFFER DELAY",
		first == 5_000 and second == 5_000 and int(third_state.get("last_actual_output", -1)) == 0
		and str(third_state.get("production_constraint_reason", "")).begins_with("input:")
	)


func _test_e1_09_local_shortage() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 50}},
	})
	var demand: Array[Dictionary] = [{
		"demand_id": "household:shortage",
		"region_id": "fixture:source",
		"commodity_id": "coal",
		"requested_quantity": 100,
		"demand_class": "household",
	}]
	_settle(economy, 0, demand)
	var market: Dictionary = economy.get_market_state("fixture:source")
	var unmet: Dictionary = market.get("unmet", {}) as Dictionary
	_case("E1-09 LOCAL SHORTAGE", int(unmet.get("coal", -1)) == 50 and int((market.get("inventory", {}) as Dictionary).get("coal", -1)) == 0)


func _test_e1_10_price_response() -> void:
	var shortage: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 0}},
	})
	var demand: Array[Dictionary] = [{
		"demand_id": "household:price",
		"region_id": "fixture:source",
		"commodity_id": "coal",
		"requested_quantity": 100,
		"demand_class": "household",
	}]
	var shortage_base: int = int(shortage.get_market_state("fixture:source").get("price", {}).get("coal", -1))
	_settle(shortage, 0, demand)
	var shortage_price: int = int(shortage.get_market_state("fixture:source").get("price", {}).get("coal", -1))
	var excess: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 100_000}},
	})
	var excess_base: int = int(excess.get_market_state("fixture:source").get("price", {}).get("coal", -1))
	_settle(excess, 0, demand)
	var excess_price: int = int(excess.get_market_state("fixture:source").get("price", {}).get("coal", -1))
	_case("E1-10 PRICE RESPONSE", shortage_price > shortage_base and excess_price < excess_base and shortage_price <= shortage_base * 11 / 10)


func _test_e1_11_proportional_clearing() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 5}},
	})
	var demands: Array[Dictionary] = [
		{"demand_id": "buyer:b", "region_id": "fixture:source", "commodity_id": "coal", "requested_quantity": 5, "demand_class": "household"},
		{"demand_id": "buyer:a", "region_id": "fixture:source", "commodity_id": "coal", "requested_quantity": 5, "demand_class": "household"},
	]
	_settle(economy, 0, demands)
	var metrics: Dictionary = economy.get_market_state("fixture:source").get("daily_metrics", {}) as Dictionary
	var allocations: Dictionary = metrics.get("demand_allocations", {}) as Dictionary
	_case("E1-11 PROPORTIONAL CLEARING", int(allocations.get("buyer:a", -1)) == 3 and int(allocations.get("buyer:b", -1)) == 2)


func _test_e1_12_transport_ownership() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 1_000}},
	})
	var intent: Array[Dictionary] = [_transport_intent("transport:ownership", 500)]
	var prepared: Dictionary = economy.prepare_day(0, _empty_records(), _default_labor(), intent)
	var requests: Dictionary = economy.get_transport_requests()
	var before: Array[Dictionary] = _as_dictionary_array(economy.get_region_summary("fixture:source").get("in_transit_out", []))
	var applied: Dictionary = economy.apply_transport_allocations(_empty_records())
	var finalized: Dictionary = economy.finalize_day()
	_case("E1-12 TRANSPORT OWNERSHIP", bool(prepared.get("success", false)) and bool(requests.get("success", false)) and before.is_empty() and bool(applied.get("success", false)) and bool(finalized.get("success", false)))


func _test_e1_13_shipment_conservation() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 5_000}},
	})
	var intent: Array[Dictionary] = [_transport_intent("transport:shipment", 2_000)]
	var prepared: Dictionary = economy.prepare_day(0, _empty_records(), _default_labor(), intent)
	var allocation: Array[Dictionary] = [_allocation("transport:shipment", 2_000, 2)]
	var applied: Dictionary = economy.apply_transport_allocations(allocation)
	var finalized: Dictionary = economy.finalize_day()
	var source_after_dispatch: Dictionary = economy.get_market_state("fixture:source")
	var transit_after_dispatch: Array[Dictionary] = _as_dictionary_array(economy.get_region_summary("fixture:source").get("in_transit_out", []))
	var day_one: bool = _settle(economy, 1)
	var dest_before: int = int((economy.get_market_state("fixture:steel").get("inventory", {}) as Dictionary).get("coal", -1))
	var day_two: bool = _settle(economy, 2)
	var dest_after: int = int((economy.get_market_state("fixture:steel").get("inventory", {}) as Dictionary).get("coal", -1))
	var day_three: bool = _settle(economy, 3)
	var dest_after_repeat_day: int = int((economy.get_market_state("fixture:steel").get("inventory", {}) as Dictionary).get("coal", -1))
	var source_inventory: int = int((source_after_dispatch.get("inventory", {}) as Dictionary).get("coal", -1))
	_case(
		"E1-13 SHIPMENT CONSERVATION",
		bool(prepared.get("success", false)) and bool(applied.get("success", false)) and bool(finalized.get("success", false))
		and source_inventory == 3_000 and transit_after_dispatch.size() == 1
		and day_one and dest_before == 0 and day_two and day_three and dest_after == 2_000 and dest_after_repeat_day == dest_after
	)


func _test_e1_14_physical_conservation() -> void:
	var economy: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_buffers": {"coal": 20_000, "iron_ore": 20_000},
		"initial_market_inventory": {"fixture:steel": {"steel": 0}},
	})
	var demand: Array[Dictionary] = [{
		"demand_id": "household:steel-flow",
		"region_id": "fixture:steel",
		"commodity_id": "steel",
		"requested_quantity": 1_000,
		"demand_class": "household",
	}]
	_settle(economy, 0, demand)
	var validation: Dictionary = economy.validate_state()
	var summary: Dictionary = validation.get("data", {}) as Dictionary
	_case("E1-14 PHYSICAL CONSERVATION", bool(validation.get("success", false)) and int(summary.get("unexplained_physical_drift_count", -1)) == 0)


func _test_e1_15_determinism() -> void:
	var first: Variant = _new_fixture()
	var second: Variant = _new_fixture()
	var demand: Array[Dictionary] = [{
		"demand_id": "household:deterministic",
		"region_id": "fixture:steel",
		"commodity_id": "steel",
		"requested_quantity": 2_000,
		"demand_class": "household",
	}]
	_settle(first, 0, demand)
	_settle(second, 0, demand)
	var hash_a: String = first.get_authoritative_state_hash()
	var hash_b: String = second.get_authoritative_state_hash()
	print("E1-15 run A state hash: %s" % hash_a)
	print("E1-15 run B state hash: %s" % hash_b)
	_case("E1-15 DETERMINISM", hash_a == hash_b)


func _test_e1_16_reordering() -> void:
	var canonical: Variant = _new_fixture()
	var reordered: Variant = _new_fixture({"reorder": true})
	var demand: Array[Dictionary] = [
		{"demand_id": "buyer:z", "region_id": "fixture:steel", "commodity_id": "steel", "requested_quantity": 1_000, "demand_class": "household"},
		{"demand_id": "buyer:a", "region_id": "fixture:steel", "commodity_id": "steel", "requested_quantity": 4_000, "demand_class": "household"},
	]
	_settle(canonical, 0, demand)
	_settle(reordered, 0, demand)
	var canonical_hash: String = canonical.get_authoritative_state_hash()
	var reordered_hash: String = reordered.get_authoritative_state_hash()
	print("E1-16 canonical state hash: %s" % canonical_hash)
	print("E1-16 reordered-source state hash: %s" % reordered_hash)
	_case("E1-16 REORDERING", canonical_hash == reordered_hash)


func _test_e1_17_save_restore() -> void:
	var initial: Variant = _new_fixture()
	var initial_restored: Variant = _new_fixture()
	var initial_state: Dictionary = initial.get_persistent_state()
	var initial_ok: bool = initial_restored.restore_persistent_state(initial_state)
	var original: Variant = _new_fixture()
	_settle(original, 0)
	var state: Dictionary = original.get_persistent_state()
	var restored: Variant = _new_fixture()
	var restored_ok: bool = restored.restore_persistent_state(state)
	_case("E1-17 SAVE/RESTORE", initial_ok and initial.get_authoritative_state_hash() == initial_restored.get_authoritative_state_hash() and restored_ok and original.get_authoritative_state_hash() == restored.get_authoritative_state_hash())


func _test_e1_18_source_mismatch() -> void:
	var original: Variant = _new_fixture()
	_settle(original, 0)
	var state: Dictionary = original.get_persistent_state()
	var before: String = original.get_authoritative_state_hash()
	var mismatch: Variant = _new_fixture({"catalog_revision": "synthetic-reference-e1-other"})
	var mismatch_before: String = mismatch.get_authoritative_state_hash()
	var rejected: bool = not mismatch.restore_persistent_state(state)
	var after: String = mismatch.get_authoritative_state_hash()
	_case("E1-18 SOURCE MISMATCH", rejected and before != after and mismatch_before == after and mismatch.get_last_summary().is_empty())


func _test_failure_behavior() -> void:
	var unknown_recipe: Dictionary = _fixture_config()
	(unknown_recipe["recipes"] as Array)[0]["output_commodity_id"] = "unknown_commodity"
	_case("FAIL unknown recipe commodity", not _configure(unknown_recipe))
	var unknown_region: Dictionary = _fixture_config()
	(unknown_region["producers"] as Array)[0]["region_id"] = "fixture:missing"
	_case("FAIL unknown producer region", not _configure(unknown_region))
	var duplicate_producer: Dictionary = _fixture_config()
	(duplicate_producer["producers"] as Array).append(((duplicate_producer["producers"] as Array)[0] as Dictionary).duplicate(true))
	_case("FAIL duplicate producer", not _configure(duplicate_producer))
	var duplicate_recipe: Dictionary = _fixture_config()
	(duplicate_recipe["recipes"] as Array).append(((duplicate_recipe["recipes"] as Array)[0] as Dictionary).duplicate(true))
	_case("FAIL duplicate recipe", not _configure(duplicate_recipe))
	var negative_capacity: Dictionary = _fixture_config()
	(negative_capacity["producers"] as Array)[0]["installed_capacity_per_day"] = -1
	_case("FAIL negative installed capacity", not _configure(negative_capacity))
	var invalid_utilization: Dictionary = _fixture_config()
	(invalid_utilization["producers"] as Array)[0]["initial_utilization_bp"] = BASIS_POINTS + 1
	_case("FAIL invalid utilization", not _configure(invalid_utilization))

	var economy: Variant = _new_fixture({"miner_enabled": false, "steel_enabled": false, "initial_market_inventory": {"fixture:source": {"coal": 100}}})
	var intent: Array[Dictionary] = [_transport_intent("transport:failure", 50)]
	_case("FAIL get requests before prepare", not bool(economy.get_transport_requests().get("success", false)))
	_case("FAIL apply before prepare", not bool(economy.apply_transport_allocations(_empty_records()).get("success", false)))
	_case("FAIL finalize before prepare", not bool(economy.finalize_day().get("success", false)))
	economy.prepare_day(0, _empty_records(), _default_labor(), intent)
	var future_economy: Variant = _new_fixture({"miner_enabled": false, "steel_enabled": false, "initial_market_inventory": {"fixture:source": {"coal": 100}}})
	var future_intent: Dictionary = _transport_intent("transport:future", 50)
	future_intent["earliest_dispatch"] = 2
	var future_intents: Array[Dictionary] = [future_intent]
	future_economy.prepare_day(0, _empty_records(), _default_labor(), future_intents)
	var early_dispatch: Dictionary = future_economy.apply_transport_allocations(_records([_allocation("transport:future", 50, 1)]))
	_case("FAIL dispatch before earliest", not bool(early_dispatch.get("success", false)))
	var unknown_allocation: Dictionary = economy.apply_transport_allocations(_records([_allocation("transport:unknown", 1, 1)]))
	_case("FAIL unknown transport request", not bool(unknown_allocation.get("success", false)))
	var too_much: Dictionary = economy.apply_transport_allocations(_records([_allocation("transport:failure", 51, 1)]))
	_case("FAIL allocation exceeds request", not bool(too_much.get("success", false)))
	var finalize_before_allocation: Dictionary = economy.finalize_day()
	_case("FAIL finalize before allocation", not bool(finalize_before_allocation.get("success", false)))
	var applied: Dictionary = economy.apply_transport_allocations(_records([_allocation("transport:failure", 50, 1)]))
	var duplicate_apply: Dictionary = economy.apply_transport_allocations(_records([_allocation("transport:failure", 50, 1)]))
	_case("FAIL same allocation twice", bool(applied.get("success", false)) and not bool(duplicate_apply.get("success", false)))
	_case("PASS finalize after allocation", bool(economy.finalize_day().get("success", false)))
	var invalid_repeat_prepare: Dictionary = economy.prepare_day(0, _empty_records(), _default_labor())
	_case("FAIL same shipment arrival/invalid repeated prepare", not bool(invalid_repeat_prepare.get("success", false)))

	var delivered: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 2_000}},
	})
	var delivered_intent: Array[Dictionary] = [_transport_intent("transport:duplicate-arrival", 1_000)]
	var delivered_allocation: Array[Dictionary] = [_allocation("transport:duplicate-arrival", 1_000, 1)]
	_settle(delivered, 0, _empty_records(), _default_labor(), delivered_intent, delivered_allocation)
	_settle(delivered, 1)
	var delivered_state: Dictionary = delivered.get_persistent_state()
	var clean_delivered_state: Dictionary = delivered_state.duplicate(true)
	var duplicate_history: Array = (delivered_state.get("shipment_history", []) as Array).duplicate(true)
	if not duplicate_history.is_empty():
		duplicate_history.append((duplicate_history[0] as Dictionary).duplicate(true))
	delivered_state["shipment_history"] = duplicate_history
	var restore_target: Variant = _new_fixture({
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 2_000}},
	})
	var restore_before: String = restore_target.get_authoritative_state_hash()
	var duplicate_restore_rejected: bool = not restore_target.restore_persistent_state(delivered_state)
	_case("FAIL duplicate shipment arrival", duplicate_restore_rejected and restore_target.get_authoritative_state_hash() == restore_before)
	var missing_history_state: Dictionary = clean_delivered_state.duplicate(true)
	missing_history_state.erase("history")
	var missing_history_rejected: bool = not restore_target.restore_persistent_state(missing_history_state)
	_case("FAIL missing persistence history", missing_history_rejected and restore_target.get_authoritative_state_hash() == restore_before)
	var mismatched_identity_state: Dictionary = clean_delivered_state.duplicate(true)
	var mismatched_industry: Dictionary = (mismatched_identity_state["industry_states"] as Dictionary)["fixture:steel_site"] as Dictionary
	mismatched_industry["producer_id"] = "fixture:coal_site"
	var mismatched_identity_rejected: bool = not restore_target.restore_persistent_state(mismatched_identity_state)
	_case("FAIL mismatched persistent identity", mismatched_identity_rejected and restore_target.get_authoritative_state_hash() == restore_before)


func _test_alpha_catalog_salvage() -> void:
	var result: Dictionary = CommodityCatalogScript.load_existing_commodity_catalog()
	var data: Dictionary = result.get("data", {}) as Dictionary
	var ids: Array = data.get("commodity_ids", []) as Array
	print("SALVAGE catalog_revision=%s catalog_hash=%s commodity_count=%d" % [str(data.get("catalog_revision", "")), str(data.get("catalog_hash", "")), ids.size()])
	_case("SALVAGE canonical commodity catalog", bool(result.get("success", false)) and ids.has("coal") and ids.has("iron_ore") and ids.has("steel"))


func _print_reference_trace() -> void:
	print("--- E1 synthetic reference physical-flow trace ---")
	var economy: Variant = _new_fixture({"steel_buffers": {"coal": 10_000, "iron_ore": 20_000}})
	var coal_opening: int = int((economy.get_industry_state("fixture:steel_site").get("input_buffers", {}) as Dictionary).get("coal", 0))
	var totals: Dictionary = {"coal_produced": 0, "coal_process": 0, "coal_household": 0, "coal_dispatched": 0, "coal_arrivals": 0, "steel_produced": 0, "steel_process": 0, "steel_household": 0}
	for day: int in range(6):
		var demands: Array[Dictionary] = [{
			"demand_id": "trace:steel-households:%d" % day,
			"region_id": "fixture:steel",
			"commodity_id": "steel",
			"requested_quantity": 3_000,
			"demand_class": "household",
		}]
		var intents: Array[Dictionary] = []
		var allocations: Array[Dictionary] = []
		if day == 2:
			var trace_intent: Dictionary = _transport_intent("trace:coal:%d" % day, 10_000)
			trace_intent["earliest_dispatch"] = day
			intents.append(trace_intent)
			allocations.append(_allocation("trace:coal:%d" % day, 10_000, 2))
		_settle(economy, day, demands, _default_labor(), intents, allocations)
		var steel_state: Dictionary = economy.get_industry_state("fixture:steel_site")
		var steel_market: Dictionary = economy.get_market_state("fixture:steel")
		var market_demand: Dictionary = steel_market.get("demand", {}) as Dictionary
		var fulfilled: Dictionary = steel_market.get("fulfilled", {}) as Dictionary
		var unmet: Dictionary = steel_market.get("unmet", {}) as Dictionary
		var steel_price: int = int((steel_market.get("price", {}) as Dictionary).get("steel", 0))
		var source_transit: Array[Dictionary] = economy.get_region_summary("fixture:source").get("in_transit_out", []) as Array[Dictionary]
		var summary: Dictionary = economy.get_last_summary()
		var summary_produced: Dictionary = summary.get("produced", {}) as Dictionary
		var summary_consumed: Dictionary = summary.get("process_inputs_consumed", {}) as Dictionary
		var summary_household: Dictionary = summary.get("household_system_consumed", {}) as Dictionary
		var summary_arrivals: Dictionary = summary.get("arrivals", {}) as Dictionary
		var summary_dispatched: Dictionary = summary.get("dispatched", {}) as Dictionary
		totals["coal_produced"] = int(totals["coal_produced"]) + int(summary_produced.get("coal", 0))
		totals["coal_process"] = int(totals["coal_process"]) + int(summary_consumed.get("coal", 0))
		totals["coal_household"] = int(totals["coal_household"]) + int(summary_household.get("coal", 0))
		totals["coal_dispatched"] = int(totals["coal_dispatched"]) + int(summary_dispatched.get("coal", 0))
		totals["coal_arrivals"] = int(totals["coal_arrivals"]) + int(summary_arrivals.get("coal", 0))
		totals["steel_produced"] = int(totals["steel_produced"]) + int(summary_produced.get("steel", 0))
		totals["steel_process"] = int(totals["steel_process"]) + int(summary_consumed.get("steel", 0))
		totals["steel_household"] = int(totals["steel_household"]) + int(summary_household.get("steel", 0))
		print("TRACE day=%d planned=%d actual=%d reason=%s coal_buffer=%d steel_inventory=%d demand=%d fulfilled=%d unmet=%d price=%d transport_requested=%d transport_allocated=%d in_transit=%d arrivals=%d" % [
			day,
			int(steel_state.get("last_planned_output", 0)),
			int(steel_state.get("last_actual_output", 0)),
			str(steel_state.get("production_constraint_reason", "")),
			int((steel_state.get("input_buffers", {}) as Dictionary).get("coal", 0)),
			int((steel_market.get("inventory", {}) as Dictionary).get("steel", 0)),
			int(market_demand.get("steel", 0)),
			int(fulfilled.get("steel", 0)),
			int(unmet.get("steel", 0)),
			steel_price,
			int(summary.get("transport_requested_quantity", 0)),
			int(summary.get("transport_allocated_quantity", 0)),
			_source_transit_quantity(source_transit),
			int(summary_arrivals.get("coal", 0)),
		])
	var coal_closing: int = _total_commodity_stock(economy, "coal")
	var steel_closing: int = _total_commodity_stock(economy, "steel")
	print("CONSERVATION coal opening=%d produced=%d process_inputs=%d household=%d dispatched=%d arrived=%d closing_plus_transit=%d drift=%d" % [
		coal_opening,
		int(totals["coal_produced"]),
		int(totals["coal_process"]),
		int(totals["coal_household"]),
		int(totals["coal_dispatched"]),
		int(totals["coal_arrivals"]),
		coal_closing,
		coal_opening + int(totals["coal_produced"]) - int(totals["coal_process"]) - int(totals["coal_household"]) - coal_closing,
	])
	print("CONSERVATION steel opening=0 produced=%d process_inputs=%d household=%d closing_plus_transit=%d drift=%d" % [
		int(totals["steel_produced"]),
		int(totals["steel_process"]),
		int(totals["steel_household"]),
		steel_closing,
		int(totals["steel_produced"]) - int(totals["steel_process"]) - int(totals["steel_household"]) - steel_closing,
	])


func _print_complexity_sanity() -> void:
	var config: Dictionary = _expanded_fixture_config(24, 48, 8, 96)
	var economy: Variant = EconomyScript.new()
	var started: int = Time.get_ticks_usec()
	var configured: bool = economy.configure(config)
	var settlement: Dictionary = {}
	if configured:
		var labor: Array[Dictionary] = []
		var demands: Array[Dictionary] = []
		for region_index: int in range(24):
			var region_id: String = "expanded:region:%02d" % region_index
			labor.append({"region_id": region_id, "labor_class": "general", "available_quantity": 100_000})
			for demand_index: int in range(4):
				demands.append({"demand_id": "expanded:demand:%02d:%d" % [region_index, demand_index], "region_id": region_id, "commodity_id": "coal", "requested_quantity": 100, "demand_class": "household"})
		settlement = economy.prepare_day(0, demands, labor)
		if bool(settlement.get("success", false)):
			economy.apply_transport_allocations(_empty_records())
			economy.finalize_day()
	var elapsed: float = float(Time.get_ticks_usec() - started) / 1_000.0
	var state_size: int = JSON.stringify(economy.get_authoritative_state_summary()).length()
	print("COMPLEXITY regions=24 producers=48 commodities=8 demand_records=96 transport_requests=0 one_day_ms=%.3f authoritative_state_bytes=%d configured=%s" % [elapsed, state_size, configured])


func _settle(
	economy: Variant,
	day: int,
	demand: Array[Dictionary] = [],
	labor: Array[Dictionary] = [],
	intents: Array[Dictionary] = [],
	allocations: Array[Dictionary] = []
) -> bool:
	var actual_labor: Array[Dictionary] = labor if not labor.is_empty() else _default_labor()
	var prepared: Dictionary = economy.prepare_day(day, demand, actual_labor, intents)
	if not bool(prepared.get("success", false)):
		return false
	var applied: Dictionary = economy.apply_transport_allocations(allocations)
	if not bool(applied.get("success", false)):
		return false
	var finalized: Dictionary = economy.finalize_day()
	return bool(finalized.get("success", false))


func _new_fixture(options: Dictionary = {}) -> Variant:
	var economy: Variant = EconomyScript.new()
	var configured: bool = economy.configure(_fixture_config(options))
	if not configured:
		print("FIXTURE CONFIG FAIL: %s" % str(economy.initialization_error))
	return economy


func _configure(configuration: Dictionary) -> bool:
	var economy: Variant = EconomyScript.new()
	return bool(economy.configure(configuration))


func _fixture_config(options: Dictionary = {}) -> Dictionary:
	var miner_enabled: bool = bool(options.get("miner_enabled", true))
	var steel_enabled: bool = bool(options.get("steel_enabled", true))
	var steel_buffers: Dictionary = (options.get("steel_buffers", {"coal": 10_000, "iron_ore": 20_000}) as Dictionary).duplicate(true)
	var commodities: Array[Dictionary] = [
		{"commodity_id": "steel", "base_price_centimes": 100, "target_stock_days": 7},
		{"commodity_id": "iron_ore", "base_price_centimes": 40, "target_stock_days": 7},
		{"commodity_id": "coal", "base_price_centimes": 60, "target_stock_days": 7},
	]
	var regions: Array[Dictionary] = [
		{"region_id": "fixture:steel", "spatial_region_ids": ["spatial:steel"], "market_id": "market:fixture:steel", "enabled": true},
		{"region_id": "fixture:source", "spatial_region_ids": ["spatial:source"], "market_id": "market:fixture:source", "enabled": true},
	]
	var recipes: Array[Dictionary] = [
		{
			"recipe_id": "fixture:steel_recipe",
			"output_commodity_id": "steel",
			"output_quantity": 1_000,
			"inputs": [
				{"commodity_id": "iron_ore", "quantity_per_output": 2_000_000},
				{"commodity_id": "coal", "quantity_per_output": 1_000_000},
			],
			"labor_requirements": [{"labor_class": "skilled", "quantity_per_output": 1_000_000}],
			"producer_type": "industrial",
		},
		{"recipe_id": "fixture:coal_recipe", "output_commodity_id": "coal", "output_quantity": 1_000, "inputs": [], "labor_requirements": [{"labor_class": "extractive", "quantity_per_output": 1_000_000}], "producer_type": "extractive"},
		{"recipe_id": "fixture:iron_recipe", "output_commodity_id": "iron_ore", "output_quantity": 1_000, "inputs": [], "labor_requirements": [{"labor_class": "extractive", "quantity_per_output": 1_000_000}], "producer_type": "extractive"},
	]
	var producers: Array[Dictionary] = [
		{"producer_id": "fixture:steel_site", "region_id": "fixture:steel", "recipe_id": "fixture:steel_recipe", "installed_capacity_per_day": 5_000, "initial_utilization_bp": BASIS_POINTS, "input_buffer_target_days": 2, "initial_input_buffers": steel_buffers, "enabled": steel_enabled},
		{"producer_id": "fixture:coal_site", "region_id": "fixture:source", "recipe_id": "fixture:coal_recipe", "installed_capacity_per_day": 10_000, "initial_utilization_bp": BASIS_POINTS, "input_buffer_target_days": 0, "resource_source_id": "resource:coal_bed", "resource_quantity_per_output": 1_000_000, "resource_capacity_per_day": 10_000, "enabled": miner_enabled},
		{"producer_id": "fixture:iron_site", "region_id": "fixture:steel", "recipe_id": "fixture:iron_recipe", "installed_capacity_per_day": 10_000, "initial_utilization_bp": BASIS_POINTS, "input_buffer_target_days": 0, "resource_source_id": "resource:iron_bed", "resource_quantity_per_output": 1_000_000, "resource_capacity_per_day": 10_000, "enabled": miner_enabled},
	]
	var config: Dictionary = {
		"catalog_revision": str(options.get("catalog_revision", "synthetic-reference-e1-v1")),
		"commodities": commodities,
		"regions": regions,
		"recipes": recipes,
		"producers": producers,
		"resource_sources": [
			{"resource_id": "resource:coal_bed", "available_quantity": 1_000_000, "extraction_capacity_per_day": 10_000},
			{"resource_id": "resource:iron_bed", "available_quantity": 1_000_000, "extraction_capacity_per_day": 10_000},
		],
		"initial_market_inventory": (options.get("initial_market_inventory", {}) as Dictionary).duplicate(true),
	}
	if options.has("policies"):
		config["policies"] = (options.get("policies", {}) as Dictionary).duplicate(true)
	if bool(options.get("reorder", false)):
		config["commodities"] = _reverse_dictionary_array(commodities)
		config["regions"] = _reverse_dictionary_array(regions)
		config["recipes"] = _reverse_dictionary_array(recipes)
		config["producers"] = _reverse_dictionary_array(producers)
		config["resource_sources"] = _reverse_dictionary_array(config["resource_sources"] as Array)
	return config


func _default_labor() -> Array[Dictionary]:
	return [
		{"region_id": "fixture:source", "labor_class": "extractive", "available_quantity": 100_000},
		{"region_id": "fixture:steel", "labor_class": "extractive", "available_quantity": 100_000},
		{"region_id": "fixture:steel", "labor_class": "skilled", "available_quantity": 100_000},
	]


func _transport_intent(request_id: String, quantity: int) -> Dictionary:
	return {
		"request_id": request_id,
		"origin_region_id": "fixture:source",
		"destination_region_id": "fixture:steel",
		"commodity_id": "coal",
		"requested_quantity": quantity,
		"earliest_dispatch": 0,
		"priority_class": "industrial_input",
		"stable_order_key": request_id,
	}


func _allocation(request_id: String, quantity: int, duration: int) -> Dictionary:
	return {"request_id": request_id, "allocated_quantity": quantity, "route_id": "synthetic:route:source-steel", "duration": duration, "transport_cost": 12}


func _reverse_dictionary_array(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(values.size() - 1, -1, -1):
		result.append((values[index] as Dictionary).duplicate(true))
	return result


func _records(values: Array[Dictionary]) -> Array[Dictionary]:
	return values


func _empty_records() -> Array[Dictionary]:
	return []


func _as_dictionary_array(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not values is Array:
		return result
	for value: Variant in values as Array:
		if value is Dictionary:
			result.append(value as Dictionary)
	return result


func _source_transit_quantity(shipments: Array[Dictionary]) -> int:
	var total: int = 0
	for shipment: Dictionary in shipments:
		total += int(shipment.get("quantity", 0))
	return total


func _total_commodity_stock(economy: Variant, commodity_id: String) -> int:
	var total: int = 0
	for region_id: String in ["fixture:source", "fixture:steel"]:
		total += int((economy.get_market_state(region_id).get("inventory", {}) as Dictionary).get(commodity_id, 0))
	for producer_id: String in ["fixture:steel_site", "fixture:coal_site", "fixture:iron_site"]:
		total += int((economy.get_industry_state(producer_id).get("input_buffers", {}) as Dictionary).get(commodity_id, 0))
	for region_id: String in ["fixture:source", "fixture:steel"]:
		var shipments: Array[Dictionary] = economy.get_region_summary(region_id).get("in_transit_out", []) as Array[Dictionary]
		total += _source_transit_quantity(shipments)
	return total


func _expanded_fixture_config(region_count: int, producer_count: int, commodity_count: int, demand_count: int) -> Dictionary:
	var commodities: Array[Dictionary] = []
	for index: int in range(commodity_count):
		commodities.append({"commodity_id": "commodity:%02d" % index if index > 0 else "coal", "base_price_centimes": 10 + index, "target_stock_days": 3})
	var regions: Array[Dictionary] = []
	for index: int in range(region_count):
		regions.append({"region_id": "expanded:region:%02d" % index, "spatial_region_ids": ["expanded:spatial:%02d" % index], "market_id": "expanded:market:%02d" % index, "enabled": true})
	var recipes: Array[Dictionary] = [{"recipe_id": "expanded:recipe", "output_commodity_id": "coal", "output_quantity": 1_000, "inputs": [], "labor_requirements": [{"labor_class": "general", "quantity_per_output": 1_000_000}], "producer_type": "extractive"}]
	var producers: Array[Dictionary] = []
	for index: int in range(producer_count):
		var region_id: String = "expanded:region:%02d" % (index % region_count)
		producers.append({"producer_id": "expanded:producer:%03d" % index, "region_id": region_id, "recipe_id": "expanded:recipe", "installed_capacity_per_day": 1_000, "initial_utilization_bp": BASIS_POINTS, "input_buffer_target_days": 0, "enabled": true})
	return {"catalog_revision": "synthetic-expanded-e1-v1", "commodities": commodities, "regions": regions, "recipes": recipes, "producers": producers, "resource_sources": [], "initial_market_inventory": {}}


func _case(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("%s: PASS" % label)
	else:
		failures += 1
		print("%s: FAIL" % label)
