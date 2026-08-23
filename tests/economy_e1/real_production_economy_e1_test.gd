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
	_test_r1_recipe_requirement_contract()
	_test_r1_persistent_schema()
	_test_r2_shipment_request_uniqueness()
	_test_r1_configure_phase_guard()
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


func _test_r1_recipe_requirement_contract() -> void:
	var collision_config: Dictionary = _fixture_config()
	var collision_recipe: Dictionary = (collision_config["recipes"] as Array)[0] as Dictionary
	collision_recipe["energy_requirements"] = [{"commodity_id": "coal", "quantity_per_output": 1_000_000}]
	var collision_economy: Variant = _new_fixture()
	_settle(collision_economy, 0)
	var collision_before: String = collision_economy.get_authoritative_state_hash()
	var collision_rejected: bool = not collision_economy.configure(collision_config)
	_case(
		"R1 PHYS collision rejects",
		collision_rejected and collision_economy.initialization_error.contains("both inputs and energy_requirements")
	)
	_case("R1 PHYS collision is atomic", collision_economy.get_authoritative_state_hash() == collision_before and collision_economy.get_phase() == "READY")

	var duplicate_input_config: Dictionary = _fixture_config()
	var duplicate_input_recipe: Dictionary = (duplicate_input_config["recipes"] as Array)[0] as Dictionary
	(duplicate_input_recipe["inputs"] as Array).append({"commodity_id": "coal", "quantity_per_output": 1_000_000})
	_case("R1 PHYS duplicate input rejects", not _configure(duplicate_input_config))
	var duplicate_energy_config: Dictionary = _fixture_config()
	var duplicate_energy_recipe: Dictionary = (duplicate_energy_config["recipes"] as Array)[0] as Dictionary
	duplicate_energy_recipe["energy_requirements"] = [
		{"commodity_id": "coal", "quantity_per_output": 1_000_000},
		{"commodity_id": "coal", "quantity_per_output": 1_000_000},
	]
	_case("R1 PHYS duplicate energy rejects", not _configure(duplicate_energy_config))

	var split_config: Dictionary = _fixture_config({"miner_enabled": false})
	var split_recipe: Dictionary = (split_config["recipes"] as Array)[0] as Dictionary
	split_recipe["inputs"] = [{"commodity_id": "iron_ore", "quantity_per_output": 2_000_000}]
	split_recipe["energy_requirements"] = [{"commodity_id": "coal", "quantity_per_output": 1_000_000}]
	var split_economy: Variant = EconomyScript.new()
	var split_configured: bool = split_economy.configure(split_config)
	_case("R1 PHYS distinct categories valid", split_configured)
	var normal_economy: Variant = _new_fixture({"miner_enabled": false})
	var normal_settled: bool = _settle(normal_economy, 0)
	var split_settled: bool = _settle(split_economy, 0)
	var normal_industry: Dictionary = normal_economy.get_industry_state("fixture:steel_site")
	var split_industry: Dictionary = split_economy.get_industry_state("fixture:steel_site")
	var normal_market: Dictionary = normal_economy.get_market_state("fixture:steel")
	var split_market: Dictionary = split_economy.get_market_state("fixture:steel")
	_case(
		"R1 PHYS normal production unchanged",
		normal_settled and split_settled
		and int(normal_industry.get("last_actual_output", -1)) == int(split_industry.get("last_actual_output", -2))
		and (normal_industry.get("input_buffers", {}) as Dictionary) == (split_industry.get("input_buffers", {}) as Dictionary)
		and int((normal_market.get("inventory", {}) as Dictionary).get("steel", -1)) == int((split_market.get("inventory", {}) as Dictionary).get("steel", -2))
	)


func _test_r1_persistent_schema() -> void:
	var original: Variant = _new_fixture({"miner_enabled": false})
	_settle(original, 0)
	var saved: Dictionary = original.get_persistent_state()

	var missing_demand: Dictionary = saved.duplicate(true)
	((missing_demand["market_states"] as Dictionary)["fixture:steel"] as Dictionary).erase("demand")
	_assert_restore_rejected("R1 PERSIST missing demand", missing_demand)
	var missing_moving: Dictionary = saved.duplicate(true)
	((missing_moving["market_states"] as Dictionary)["fixture:steel"] as Dictionary).erase("moving_average_daily_demand")
	_assert_restore_rejected("R1 PERSIST missing moving demand", missing_moving)
	var missing_target: Dictionary = saved.duplicate(true)
	((missing_target["market_states"] as Dictionary)["fixture:steel"] as Dictionary).erase("target_stock")
	_assert_restore_rejected("R1 PERSIST missing target stock", missing_target)
	var missing_constraint: Dictionary = saved.duplicate(true)
	((missing_constraint["industry_states"] as Dictionary)["fixture:steel_site"] as Dictionary).erase("production_constraint_reason")
	_assert_restore_rejected("R1 PERSIST missing industry constraint", missing_constraint)
	var impossible_output: Dictionary = saved.duplicate(true)
	var impossible_industry: Dictionary = (impossible_output["industry_states"] as Dictionary)["fixture:steel_site"] as Dictionary
	impossible_industry["last_actual_output"] = int(impossible_industry.get("last_planned_output", 0)) + 1
	_assert_restore_rejected("R1 PERSIST actual exceeds planned", impossible_output)
	var malformed_nested: Dictionary = saved.duplicate(true)
	((malformed_nested["market_states"] as Dictionary)["fixture:steel"] as Dictionary)["daily_metrics"] = []
	_assert_restore_rejected("R1 PERSIST malformed nested dictionary", malformed_nested)

	var restored: Variant = _new_fixture({"miner_enabled": false})
	var restored_ok: bool = restored.restore_persistent_state(saved)
	_case(
		"R1 PERSIST current writer round trip",
		restored_ok and restored.get_authoritative_state_hash() == original.get_authoritative_state_hash() and restored.get_persistent_state() == saved
	)

	var shipment_options: Dictionary = {"miner_enabled": false, "steel_enabled": false, "initial_market_inventory": {"fixture:source": {"coal": 2_000}}}
	var active_source: Variant = _new_fixture(shipment_options)
	var active_intents: Array[Dictionary] = [_transport_intent("r1:shipment", 1_000)]
	var active_allocations: Array[Dictionary] = [_allocation("r1:shipment", 1_000, 2)]
	var active_ok: bool = _settle(active_source, 0, _empty_records(), _default_labor(), active_intents, active_allocations)
	var active_saved: Dictionary = active_source.get_persistent_state()
	var active_hash: String = active_source.get_authoritative_state_hash()
	var active_restored: Variant = _new_fixture(shipment_options)
	var active_restore_ok: bool = active_restored.restore_persistent_state(active_saved)
	var delivered_ok: bool = _settle(active_source, 1) and _settle(active_source, 2)
	var delivered_saved: Dictionary = active_source.get_persistent_state()
	var delivered_restored: Variant = _new_fixture(shipment_options)
	var delivered_restore_ok: bool = delivered_restored.restore_persistent_state(delivered_saved)
	_case("R1 PERSIST active shipment writer round trip", active_ok and active_restore_ok and active_restored.get_authoritative_state_hash() == active_hash)
	_case("R1 PERSIST delivered shipment writer round trip", delivered_ok and delivered_restore_ok and delivered_restored.get_authoritative_state_hash() == active_source.get_authoritative_state_hash())


func _test_r2_shipment_request_uniqueness() -> void:
	var shipment_options: Dictionary = {
		"miner_enabled": false,
		"steel_enabled": false,
		"initial_market_inventory": {"fixture:source": {"coal": 3_000}},
	}
	var active_source: Variant = _new_fixture(shipment_options)
	var active_intents: Array[Dictionary] = [
		_transport_intent("r2:request:one", 1_000),
		_transport_intent("r2:request:two", 1_000),
	]
	var active_allocations: Array[Dictionary] = [
		_allocation("r2:request:one", 1_000, 3),
		_allocation("r2:request:two", 1_000, 3),
	]
	var active_ok: bool = _settle(
		active_source,
		0,
		_empty_records(),
		_default_labor(),
		active_intents,
		active_allocations
	)
	var active_saved: Dictionary = active_source.get_persistent_state()
	var active_shipments: Array = (active_saved.get("shipments", []) as Array).duplicate(true)
	var active_setup_valid: bool = active_ok and active_shipments.size() == 2

	var duplicate_active_candidate: Dictionary = active_saved.duplicate(true)
	var duplicate_active_rejected: bool = false
	var duplicate_active_hash_unchanged: bool = false
	if active_setup_valid:
		var first_active: Dictionary = active_shipments[0] as Dictionary
		var second_active: Dictionary = active_shipments[1] as Dictionary
		second_active["request_id"] = str(first_active.get("request_id", ""))
		duplicate_active_candidate["shipments"] = active_shipments
		var duplicate_active_target: Variant = _new_fixture(shipment_options)
		var duplicate_active_before: String = duplicate_active_target.get_authoritative_state_hash()
		duplicate_active_rejected = not duplicate_active_target.restore_persistent_state(duplicate_active_candidate)
		duplicate_active_hash_unchanged = duplicate_active_target.get_authoritative_state_hash() == duplicate_active_before
	_case("R2-01 duplicate request IDs across active shipments reject", active_setup_valid and duplicate_active_rejected)
	_case("R2-02 duplicate request restore is atomic", active_setup_valid and duplicate_active_hash_unchanged)

	var distinct_target: Variant = _new_fixture(shipment_options)
	var distinct_restore_ok: bool = distinct_target.restore_persistent_state(active_saved)
	_case(
		"R2-03 distinct request IDs remain valid",
		active_setup_valid and distinct_restore_ok and distinct_target.get_authoritative_state_hash() == active_source.get_authoritative_state_hash()
	)

	var lifecycle_source: Variant = _new_fixture(shipment_options)
	var lifecycle_intents: Array[Dictionary] = [
		_transport_intent("r2:lifecycle:delivered", 1_000),
		_transport_intent("r2:lifecycle:active", 1_000),
	]
	var lifecycle_allocations: Array[Dictionary] = [
		_allocation("r2:lifecycle:delivered", 1_000, 1),
		_allocation("r2:lifecycle:active", 1_000, 3),
	]
	var lifecycle_day_zero: bool = _settle(
		lifecycle_source,
		0,
		_empty_records(),
		_default_labor(),
		lifecycle_intents,
		lifecycle_allocations
	)
	var lifecycle_day_one: bool = _settle(lifecycle_source, 1)
	var lifecycle_saved: Dictionary = lifecycle_source.get_persistent_state()
	var lifecycle_history: Array = (lifecycle_saved.get("shipment_history", []) as Array).duplicate(true)
	var lifecycle_active: Array = (lifecycle_saved.get("shipments", []) as Array).duplicate(true)
	var lifecycle_setup_valid: bool = lifecycle_day_zero and lifecycle_day_one and lifecycle_history.size() == 1 and lifecycle_active.size() == 1
	var cross_collection_candidate: Dictionary = lifecycle_saved.duplicate(true)
	var cross_collection_rejected: bool = false
	var cross_collection_hash_unchanged: bool = false
	if lifecycle_setup_valid:
		var delivered_record: Dictionary = lifecycle_history[0] as Dictionary
		var active_record: Dictionary = lifecycle_active[0] as Dictionary
		active_record["request_id"] = str(delivered_record.get("request_id", ""))
		cross_collection_candidate["shipments"] = lifecycle_active
		var cross_collection_target: Variant = _new_fixture(shipment_options)
		var cross_collection_before: String = cross_collection_target.get_authoritative_state_hash()
		cross_collection_rejected = not cross_collection_target.restore_persistent_state(cross_collection_candidate)
		cross_collection_hash_unchanged = cross_collection_target.get_authoritative_state_hash() == cross_collection_before
	_case(
		"R2-04 duplicate request ID across active and history rejects",
		lifecycle_setup_valid and cross_collection_rejected and cross_collection_hash_unchanged
	)

	var duplicate_shipment_candidate: Dictionary = lifecycle_saved.duplicate(true)
	var duplicate_shipment_rejected: bool = false
	if lifecycle_setup_valid:
		var duplicate_history_record: Dictionary = lifecycle_history[0] as Dictionary
		var duplicate_active_record: Dictionary = lifecycle_active[0] as Dictionary
		duplicate_active_record["shipment_id"] = str(duplicate_history_record.get("shipment_id", ""))
		duplicate_shipment_candidate["shipments"] = lifecycle_active
		var known_shipment_ids: Array[String] = [str(duplicate_history_record.get("shipment_id", ""))]
		known_shipment_ids.sort()
		duplicate_shipment_candidate["known_shipment_ids"] = known_shipment_ids
		var duplicate_shipment_target: Variant = _new_fixture(shipment_options)
		duplicate_shipment_rejected = not duplicate_shipment_target.restore_persistent_state(duplicate_shipment_candidate)
	_case("R2-05 duplicate shipment IDs remain rejected", lifecycle_setup_valid and duplicate_shipment_rejected)


func _test_r1_configure_phase_guard() -> void:
	var unconfigured: Variant = EconomyScript.new()
	_case("R1 STATE configure from UNCONFIGURED", bool(unconfigured.configure(_fixture_config())) and unconfigured.get_phase() == "READY")

	var ready: Variant = _new_fixture()
	var replacement: Dictionary = _fixture_config({"initial_market_inventory": {"fixture:source": {"coal": 7}}})
	var ready_configured: bool = ready.configure(replacement)
	_case(
		"R1 STATE configure from READY permitted",
		ready_configured and ready.get_phase() == "READY" and int((ready.get_market_state("fixture:source").get("inventory", {}) as Dictionary).get("coal", -1)) == 7
	)

	var waiting: Variant = _new_fixture()
	waiting.prepare_day(0, _empty_records(), _default_labor())
	var waiting_before: String = waiting.get_authoritative_state_hash()
	var waiting_rejected: bool = not waiting.configure(_fixture_config({"catalog_revision": "r1:waiting-attempt"}))
	_case("R1 STATE configure during WAITING rejects atomically", waiting_rejected and waiting.get_authoritative_state_hash() == waiting_before and waiting.get_phase() == "WAITING_FOR_TRANSPORT")

	var allocated: Variant = _new_fixture({"miner_enabled": false, "steel_enabled": false, "initial_market_inventory": {"fixture:source": {"coal": 500}}})
	var allocated_intents: Array[Dictionary] = [_transport_intent("r1:allocated", 100)]
	var allocated_prepared: Dictionary = allocated.prepare_day(0, _empty_records(), _default_labor(), allocated_intents)
	var allocated_records: Array[Dictionary] = [_allocation("r1:allocated", 100, 1)]
	var allocated_applied: Dictionary = allocated.apply_transport_allocations(allocated_records)
	var allocated_before: String = allocated.get_authoritative_state_hash()
	var allocated_rejected: bool = not allocated.configure(_fixture_config({"catalog_revision": "r1:allocated-attempt"}))
	_case(
		"R1 STATE configure during ALLOCATED rejects atomically",
		bool(allocated_prepared.get("success", false)) and bool(allocated_applied.get("success", false))
		and allocated_rejected and allocated.get_authoritative_state_hash() == allocated_before and allocated.get_phase() == "ALLOCATED"
	)


func _assert_restore_rejected(label: String, candidate: Dictionary) -> void:
	var target: Variant = _new_fixture({"miner_enabled": false})
	var before: String = target.get_authoritative_state_hash()
	var rejected: bool = not target.restore_persistent_state(candidate)
	_case(label, rejected and target.get_authoritative_state_hash() == before)


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
