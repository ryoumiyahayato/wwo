from __future__ import annotations

import re
from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"missing replacement anchor: {label}")
    return text.replace(old, new, 1)


def replace_function(text: str, name: str, replacement: str) -> str:
    pattern = re.compile(rf"(?ms)^func {re.escape(name)}\(.*?(?=^func |\Z)")
    match = pattern.search(text)
    if not match:
        raise RuntimeError(f"function not found: {name}")
    return text[: match.start()] + dedent(replacement).strip() + "\n\n\n" + text[match.end() :]


def patch_menu() -> None:
    path = "scripts/v2_3/v2_3_life_loop_menu.gd"
    text = read(path)
    text = text.replace(
        'const LIFE_LOOP_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_main.tscn"',
        'const LIFE_LOOP_SCENE: String = "res://scenes/formal/formal_world_main.tscn"',
    )
    write(path, text)


def patch_historical_data() -> None:
    path = "scripts/alpha/alpha_historical_world_economy_data.gd"
    text = read(path)
    text = replace_once(
        text,
        'const TRANSPORT_MANIFEST_PATH := "res://data/alpha/historical_transport_network_1900.json"\n',
        'const TRANSPORT_MANIFEST_PATH := "res://data/alpha/historical_transport_network_1900.json"\n'
        'const COVERAGE_REGISTRY_PATH := "res://data/alpha/historical_economy_coverage_1900.json"\n',
        "coverage const",
    )
    text = replace_once(
        text,
        "var transport_manifest: Dictionary = {}\n",
        "var transport_manifest: Dictionary = {}\nvar coverage_registry: Dictionary = {}\n",
        "coverage var",
    )
    text = replace_once(
        text,
        "var budget_by_id: Dictionary = {}\n",
        "var budget_by_id: Dictionary = {}\nvar coverage_by_entity: Dictionary = {}\n",
        "coverage index",
    )
    text = replace_function(
        text,
        "configure",
        '''
        func configure() -> bool:
        	initialization_error = ""
        	countries.clear()
        	domestic_networks.clear()
        	maritime_corridors.clear()
        	river_corridors.clear()
        	country_by_entity.clear()
        	budget_by_id.clear()
        	coverage_by_entity.clear()
        	world_manifest = _load_document(WORLD_MANIFEST_PATH)
        	household_budgets = _load_document(HOUSEHOLD_BUDGET_PATH)
        	transport_manifest = _load_document(TRANSPORT_MANIFEST_PATH)
        	coverage_registry = _load_document(COVERAGE_REGISTRY_PATH)
        	if (
        		world_manifest.is_empty()
        		or household_budgets.is_empty()
        		or transport_manifest.is_empty()
        		or coverage_registry.is_empty()
        	):
        		return false
        	if str(world_manifest.get("schema_id", "")) != "historical_world_economy_1900_estimates_v1":
        		return _fail("1900世界经济清单 Schema 无效")
        	if str(household_budgets.get("schema_id", "")) != "historical_household_budgets_1900_v1":
        		return _fail("1900家庭预算 Schema 无效")
        	if str(transport_manifest.get("schema_id", "")) != "historical_transport_network_1900_estimates_v1":
        		return _fail("1900运输网络清单 Schema 无效")
        	if str(coverage_registry.get("schema_id", "")) != "historical_economy_coverage_1900_v1":
        		return _fail("1900经济覆盖登记表 Schema 无效")
        	_load_coverage_registry()
        	if not _load_country_table():
        		return false
        	if not _load_transport_table():
        		return false
        	for raw_budget: Variant in household_budgets.get("templates", []) as Array:
        		if not raw_budget is Dictionary:
        			continue
        		var budget: Dictionary = (raw_budget as Dictionary).duplicate(true)
        		var budget_id: String = str(budget.get("template_id", ""))
        		if not budget_id.is_empty():
        			budget_by_id[budget_id] = budget
        	var integrity: Dictionary = validate_integrity()
        	if not bool(integrity.get("success", false)):
        		return _fail(str(integrity.get("message", "1900世界经济数据完整性失败")))
        	return true
        ''',
    )
    text = replace_function(
        text,
        "formal_countries",
        '''
        func formal_countries() -> Array[Dictionary]:
        	var result: Array[Dictionary] = []
        	var threshold: int = int((world_manifest.get("policy", {}) as Dictionary).get(
        		"minimum_formal_confidence_bp", 4500
        	))
        	var required_dimensions: Array[String] = [
        		"population", "industrial_capacity", "railway_capacity",
        	]
        	for record: Dictionary in countries:
        		var entity_id := str(record.get("entity_id", ""))
        		var coverage := coverage_by_entity.get(entity_id, {}) as Dictionary
        		if str(coverage.get("status", "source_required")) != "verified":
        			continue
        		var verified := DataRecordUtils.to_string_array(coverage.get("verified_dimensions", []))
        		var complete := true
        		for dimension: String in required_dimensions:
        			if dimension not in verified:
        				complete = false
        				break
        		if (
        			complete
        			and bool(record.get("formal_simulation_allowed", false))
        			and int(record.get("overall_confidence_bp", 0)) >= threshold
        		):
        			var admitted := record.duplicate(true)
        			admitted["coverage"] = coverage.duplicate(true)
        			result.append(admitted)
        	return result
        ''',
    )
    insertion = dedent('''

    func simulation_countries() -> Array[Dictionary]:
    	var result: Array[Dictionary] = []
    	var formally_admitted: Dictionary = {}
    	for record: Dictionary in formal_countries():
    		formally_admitted[str(record.get("entity_id", ""))] = true
    	for record: Dictionary in countries:
    		var entity_id := str(record.get("entity_id", ""))
    		var coverage := (coverage_by_entity.get(entity_id, {
    			"entity_id": entity_id,
    			"status": "source_required",
    			"verified_dimensions": [],
    			"missing_dimensions": (coverage_registry.get("dimensions", []) as Array).duplicate(),
    		}) as Dictionary).duplicate(true)
    		coverage["status"] = "verified" if formally_admitted.has(entity_id) else "bounded_estimate"
    		var simulation_record := record.duplicate(true)
    		simulation_record["coverage"] = coverage
    		simulation_record["admission_status"] = str(coverage.get("status", "bounded_estimate"))
    		result.append(simulation_record)
    	return result


    func _load_coverage_registry() -> void:
    	coverage_by_entity.clear()
    	for raw_record: Variant in coverage_registry.get("countries", []) as Array:
    		if not raw_record is Dictionary:
    			continue
    		var record := (raw_record as Dictionary).duplicate(true)
    		var entity_id := str(record.get("entity_id", ""))
    		if not entity_id.is_empty():
    			coverage_by_entity[entity_id] = record
    ''').strip() + "\n\n\n"
    anchor = "func coverage_summary() -> Dictionary:"
    if "func simulation_countries()" not in text:
        text = text.replace(anchor, insertion + anchor, 1)
    text = replace_once(
        text,
        'summary["formal_country_count"] = formal_countries().size()\n',
        'summary["formal_country_count"] = formal_countries().size()\n'
        'summary["bounded_simulation_country_count"] = simulation_countries().size()\n'
        'summary["coverage_registry_country_count"] = coverage_by_entity.size()\n',
        "coverage summary",
    )
    write(path, text)


def patch_commodity_market() -> None:
    path = "scripts/alpha/alpha_commodity_market_service.gd"
    text = read(path)
    text = replace_once(
        text,
        'site["last_operating_bp"] = 0\n',
        'site["last_operating_bp"] = 0\n\t\tsite["last_output_units"] = {}\n',
        "site actual output init",
    )
    text = replace_function(
        text,
        "_run_production",
        '''
        func _run_production(total_hour: int) -> void:
        	for site_id: String in _production_site_ids:
        		var site: Dictionary = production_sites[site_id] as Dictionary
        		var region_id: String = str(site.get("region_id", ""))
        		var recipe: Dictionary = recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
        		var state: Dictionary = region_states[region_id] as Dictionary
        		var inventory: Dictionary = state.get("inventory", {}) as Dictionary
        		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
        		var capacity: float = float(site.get("capacity_batches_per_day", 0.0))
        		var operating_bp: int = clampi(int(site.get("operating_target_bp", BASIS_POINTS)), 0, BASIS_POINTS)
        		var batches: float = capacity * float(operating_bp) / float(BASIS_POINTS)
        		for raw_input: Variant in recipe.get("inputs", []) as Array:
        			var input: Dictionary = raw_input as Dictionary
        			var commodity_id: String = str(input.get("commodity_id", ""))
        			var units: float = float(input.get("units", 0.0))
        			if units > 0.0:
        				batches = minf(batches, float(inventory.get(commodity_id, 0.0)) / units)
        		batches = maxf(0.0, floor(batches * 1000.0) / 1000.0)
        		for raw_input: Variant in recipe.get("inputs", []) as Array:
        			var input: Dictionary = raw_input as Dictionary
        			var commodity_id: String = str(input.get("commodity_id", ""))
        			var used: float = float(input.get("units", 0.0)) * batches
        			inventory[commodity_id] = maxf(0.0, float(inventory.get(commodity_id, 0.0)) - used)
        			_add_metric(metrics, "industrial_inputs", commodity_id, used)
        		var actual_outputs: Dictionary = {}
        		for raw_output: Variant in recipe.get("outputs", []) as Array:
        			var output: Dictionary = raw_output as Dictionary
        			var commodity_id: String = str(output.get("commodity_id", ""))
        			var produced: float = float(output.get("units", 0.0)) * batches
        			var supply_modifier_bp: int = _active_supply_modifier_bp(
        				region_id, commodity_id, total_hour
        			)
        			produced *= float(supply_modifier_bp) / float(BASIS_POINTS)
        			actual_outputs[commodity_id] = produced
        			inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + produced
        			_add_metric(metrics, "produced", commodity_id, produced)
        		var workers_capacity: int = int(site.get("workers_capacity", 0))
        		var utilization: float = 0.0 if capacity <= 0.0 else batches / capacity
        		metrics["workers_capacity"] = int(metrics.get("workers_capacity", 0)) + workers_capacity
        		metrics["workers_active"] = int(metrics.get("workers_active", 0)) + int(round(workers_capacity * utilization))
        		site["last_batches"] = batches
        		site["last_output_units"] = actual_outputs
        		site["last_operating_bp"] = int(round(utilization * BASIS_POINTS))
        		site["last_settlement_hour"] = total_hour
        		production_sites[site_id] = site
        		state["inventory"] = inventory
        		state["daily_metrics"] = metrics
        		region_states[region_id] = state
        	for region_id: String in _region_ids:
        		var state: Dictionary = region_states[region_id] as Dictionary
        		var metrics: Dictionary = state.get("daily_metrics", {}) as Dictionary
        		var capacity_workers: int = int(metrics.get("workers_capacity", 0))
        		metrics["production_utilization_bp"] = (
        			0 if capacity_workers <= 0
        			else int(metrics.get("workers_active", 0)) * BASIS_POINTS / capacity_workers
        		)
        		state["daily_metrics"] = metrics
        		region_states[region_id] = state
        ''',
    )
    write(path, text)


def patch_integration_service() -> None:
    path = "scripts/alpha/alpha_economy_integration_service.gd"
    text = read(path)
    text = replace_once(
        text,
        "var _next_shipment_sequence: int = 1\n",
        "var _next_shipment_sequence: int = 1\nvar _liquidity_sequence_by_day_region: Dictionary = {}\n",
        "liquidity var",
    )
    text = replace_once(
        text,
        "\t_next_shipment_sequence = 1\n\tinitialization_error = \"\"\n",
        "\t_next_shipment_sequence = 1\n\t_liquidity_sequence_by_day_region.clear()\n\tinitialization_error = \"\"\n",
        "liquidity reset",
    )
    text = replace_function(
        text,
        "deliver_due_shipments",
        '''
        func deliver_due_shipments(total_hour: int) -> Dictionary:
        	var delivered_count := 0
        	var delivered_units := 0.0
        	var defaulted_count := 0
        	for index: int in range(shipments.size() - 1, -1, -1):
        		var shipment := shipments[index] as Dictionary
        		if int(shipment.get("arrival_hour", 0)) > total_hour:
        			continue
        		var destination_id := str(shipment.get("destination_region_id", ""))
        		var commodity_id := str(shipment.get("commodity_id", ""))
        		var units := float(shipment.get("units", 0.0))
        		var seller_id := str(shipment.get("seller_id", ""))
        		var goods_value := int(shipment.get("goods_value_centimes", 0))
        		var explicitly_defaulted := (
        			str(shipment.get("status", "")) == "default_requested"
        			or bool(shipment.get("force_default", false))
        		)
        		if explicitly_defaulted:
        			_refund_failed_shipment(shipment, total_hour)
        			shipment["status"] = "defaulted"
        			shipment["default_reason"] = str(shipment.get("default_reason", "transport_default"))
        			defaulted_count += 1
        		else:
        			_add_region_inventory(destination_id, commodity_id, units)
        			_record_market_metric(destination_id, "transit_received", commodity_id, units)
        			if goods_value > 0 and not _safe_transfer(
        				"integration:shipment:release:%s" % str(shipment.get("shipment_id", "")),
        				total_hour,
        				ESCROW_ID,
        				seller_id,
        				goods_value,
        				"commodity_delivery",
        				"货物交付后释放托管货款"
        			):
        				return _fail("shipment_release_failed", "货物已到达但托管货款无法释放")
        			shipment["status"] = "delivered"
        			shipment["delivered_hour"] = total_hour
        			delivered_count += 1
        			delivered_units += units
        		shipment_history.append(shipment.duplicate(true))
        		shipments.remove_at(index)
        	_trim_history()
        	return _ok({
        		"delivered_count": delivered_count,
        		"delivered_units": delivered_units,
        		"defaulted_count": defaulted_count,
        	})
        ''',
    )
    text = replace_function(
        text,
        "get_persistent_state",
        '''
        func get_persistent_state() -> Dictionary:
        	return {
        		"shipments": shipments.duplicate(true),
        		"shipment_history": shipment_history.duplicate(true),
        		"decision_history": decision_history.duplicate(true),
        		"government_stockpiles": government_stockpiles.duplicate(true),
        		"country_finance": country_finance.duplicate(true),
        		"region_accounts": region_accounts.duplicate(true),
        		"daily_summary": daily_summary.duplicate(true),
        		"processed_days": _processed_days.keys(),
        		"next_shipment_sequence": _next_shipment_sequence,
        		"liquidity_sequence_by_day_region": _liquidity_sequence_by_day_region.duplicate(true),
        	}
        ''',
    )
    text = replace_function(
        text,
        "restore_persistent_state",
        '''
        func restore_persistent_state(state: Dictionary) -> bool:
        	if (
        		not state.get("shipments", []) is Array
        		or not state.get("shipment_history", []) is Array
        		or not state.get("decision_history", []) is Array
        		or not state.get("government_stockpiles", {}) is Dictionary
        		or not state.get("country_finance", {}) is Dictionary
        		or not state.get("region_accounts", region_accounts) is Dictionary
        	):
        		return false
        	var restored_regions := (state.get("region_accounts", region_accounts) as Dictionary).duplicate(true)
        	if restored_regions.size() != region_accounts.size():
        		return false
        	for raw_region_id: Variant in restored_regions:
        		if not region_accounts.has(str(raw_region_id)):
        			return false
        	shipments = DataRecordUtils.to_dictionary_array(state.get("shipments", []))
        	shipment_history = DataRecordUtils.to_dictionary_array(state.get("shipment_history", []))
        	decision_history = DataRecordUtils.to_dictionary_array(state.get("decision_history", []))
        	government_stockpiles = (state.get("government_stockpiles", {}) as Dictionary).duplicate(true)
        	country_finance = (state.get("country_finance", {}) as Dictionary).duplicate(true)
        	region_accounts = restored_regions
        	daily_summary = (state.get("daily_summary", {}) as Dictionary).duplicate(true)
        	_processed_days.clear()
        	for raw_day: Variant in state.get("processed_days", []) as Array:
        		_processed_days[int(raw_day)] = true
        	_next_shipment_sequence = int(state.get("next_shipment_sequence", 1))
        	_liquidity_sequence_by_day_region = (
        		state.get("liquidity_sequence_by_day_region", {}) as Dictionary
        	).duplicate(true)
        	_trim_history()
        	return bool(validate_integrity().get("success", false))
        ''',
    )
    text = replace_function(
        text,
        "_settle_enterprises",
        '''
        func _settle_enterprises(total_hour: int) -> Dictionary:
        	var total_revenue := 0
        	var total_cost := 0
        	var total_wages := 0
        	var total_tax := 0
        	var enterprise_results: Dictionary = {}
        	for raw_site_id: Variant in _commodity_market.production_sites:
        		var site_id := str(raw_site_id)
        		var site := _commodity_market.production_sites[site_id] as Dictionary
        		var enterprise_id := str(site_enterprise.get(site_id, ""))
        		var enterprise_state := _enterprise.enterprises.get(enterprise_id, {}) as Dictionary
        		if enterprise_state.is_empty() or str(enterprise_state.get("status", "")) in ["bankrupt", "dissolved"]:
        			continue
        		var region_id := str(site.get("region_id", ""))
        		var market_id := str((region_accounts[region_id] as Dictionary).get("market_id", ""))
        		var recipe := _commodity_market.recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
        		var batches := float(site.get("last_batches", 0.0))
        		var actual_outputs := site.get("last_output_units", {}) as Dictionary
        		var revenue := 0
        		var input_cost := 0
        		for output: Dictionary in DataRecordUtils.to_dictionary_array(recipe.get("outputs", [])):
        			var commodity_id := str(output.get("commodity_id", ""))
        			var produced_units := float(actual_outputs.get(
        				commodity_id, float(output.get("units", 0.0)) * batches
        			))
        			revenue += int(round(produced_units * float(_commodity_market.market_price(region_id, commodity_id))))
        		for input: Dictionary in DataRecordUtils.to_dictionary_array(recipe.get("inputs", [])):
        			var commodity_id := str(input.get("commodity_id", ""))
        			input_cost += int(round(float(input.get("units", 0.0)) * batches * float(_commodity_market.market_price(region_id, commodity_id))))
        		var active_workers := int(round(float(site.get("workers_capacity", 0)) * float(site.get("last_operating_bp", 0)) / float(BASIS_POINTS)))
        		var wage_rate := int((region_accounts[region_id] as Dictionary).get("wage_centimes_per_worker_day", 0))
        		var wage_cost := active_workers * wage_rate
        		var maintenance := revenue * int(_policies.get("maintenance_bp_of_revenue", 0)) / BASIS_POINTS
        		var taxable_profit := maxi(0, revenue - input_cost - wage_cost - maintenance)
        		var tax := taxable_profit * int(_policies.get("business_tax_bp", 0)) / BASIS_POINTS
        		_ensure_market_liquidity(region_id, revenue, total_hour, "site_revenue:%s" % site_id)
        		var revenue_paid := revenue <= 0 or _post_owner_entries(
        			"integration:revenue:%d:%s" % [total_hour, site_id],
        			total_hour,
        			"commodity_sales_revenue",
        			"生产设施商品销售收入",
        			[
        				{"owner_id": market_id, "delta_centimes": -revenue},
        				{"owner_id": enterprise_id, "delta_centimes": revenue},
        			]
        		)
        		var expenses_paid := _settle_site_expenses(
        			enterprise_id, region_id, market_id, input_cost, wage_cost,
        			maintenance, tax, total_hour, site_id
        		)
        		var all_paid := revenue_paid and expenses_paid
        		var margin := revenue - input_cost - wage_cost - maintenance - tax
        		_update_site_after_settlement(site_id, margin, all_paid)
        		var aggregate := enterprise_results.get(enterprise_id, {
        			"revenue": 0, "input_cost": 0, "wage_cost": 0,
        			"maintenance": 0, "tax": 0, "margin": 0,
        			"all_paid": true, "site_count": 0,
        		}) as Dictionary
        		aggregate["revenue"] = int(aggregate.get("revenue", 0)) + revenue
        		aggregate["input_cost"] = int(aggregate.get("input_cost", 0)) + input_cost
        		aggregate["wage_cost"] = int(aggregate.get("wage_cost", 0)) + wage_cost
        		aggregate["maintenance"] = int(aggregate.get("maintenance", 0)) + maintenance
        		aggregate["tax"] = int(aggregate.get("tax", 0)) + tax
        		aggregate["margin"] = int(aggregate.get("margin", 0)) + margin
        		aggregate["all_paid"] = bool(aggregate.get("all_paid", true)) and all_paid
        		aggregate["site_count"] = int(aggregate.get("site_count", 0)) + 1
        		enterprise_results[enterprise_id] = aggregate
        		total_revenue += revenue if revenue_paid else 0
        		total_cost += input_cost + wage_cost + maintenance + tax if expenses_paid else 0
        		total_wages += wage_cost if expenses_paid else 0
        		total_tax += tax if expenses_paid else 0
        	for raw_enterprise_id: Variant in enterprise_results:
        		var enterprise_id := str(raw_enterprise_id)
        		_finalize_enterprise_day(
        			enterprise_id, enterprise_results[enterprise_id] as Dictionary, total_hour
        		)
        		_maybe_invest(enterprise_id, total_hour)
        	return {
        		"revenue_centimes": total_revenue,
        		"cost_centimes": total_cost,
        		"wages_centimes": total_wages,
        		"tax_centimes": total_tax,
        		"enterprise_count": enterprise_results.size(),
        	}
        ''',
    )
    text = replace_function(
        text,
        "_update_site_and_enterprise_after_settlement",
        '''
        func _update_site_after_settlement(site_id: String, margin: int, all_paid: bool) -> void:
        	var site := _commodity_market.production_sites[site_id] as Dictionary
        	var condition := int(site.get("condition_bp", BASIS_POINTS))
        	condition = mini(BASIS_POINTS, condition + 20) if all_paid else maxi(2500, condition - 180)
        	var step := int(_policies.get("operating_target_step_bp", 350))
        	var target := int(site.get("operating_target_bp", BASIS_POINTS))
        	var output_shortage_bp := _site_output_shortage_bp(site)
        	if all_paid and margin > 0 and output_shortage_bp >= 1000:
        		target += step
        	elif not all_paid or margin < 0 or output_shortage_bp <= 100:
        		target -= step
        	target = clampi(
        		target,
        		int(_policies.get("minimum_operating_target_bp", 1500)),
        		mini(condition, int(_policies.get("maximum_operating_target_bp", BASIS_POINTS)))
        	)
        	site["condition_bp"] = condition
        	site["operating_target_bp"] = target
        	_commodity_market.production_sites[site_id] = site
        	decision_history.append({
        		"decision_id": "decision:enterprise_operating:%d:%s" % [int(site.get("last_settlement_hour", 0)), site_id],
        		"total_hour": int(site.get("last_settlement_hour", 0)),
        		"enterprise_id": str(site_enterprise.get(site_id, "")),
        		"site_id": site_id,
        		"decision_type": "operating_target",
        		"operating_target_bp": target,
        		"margin_centimes": margin,
        		"output_shortage_bp": output_shortage_bp,
        		"reason": "shortage_and_margin" if target >= int(site.get("last_operating_bp", 0)) else "loss_cash_or_glut",
        	})
        	_trim_history()


        func _finalize_enterprise_day(
        	enterprise_id: String, aggregate: Dictionary, total_hour: int
        ) -> void:
        	var state := _enterprise.enterprises.get(enterprise_id, {}) as Dictionary
        	if state.is_empty():
        		return
        	var all_paid := bool(aggregate.get("all_paid", false))
        	var margin := int(aggregate.get("margin", 0))
        	var failures := int(state.get("commodity_cash_failure_days", 0))
        	failures = 0 if all_paid else failures + 1
        	state["commodity_revenue_centimes"] = int(state.get("commodity_revenue_centimes", 0)) + int(aggregate.get("revenue", 0))
        	state["commodity_input_cost_centimes"] = int(state.get("commodity_input_cost_centimes", 0)) + int(aggregate.get("input_cost", 0))
        	state["commodity_wage_cost_centimes"] = int(state.get("commodity_wage_cost_centimes", 0)) + int(aggregate.get("wage_cost", 0))
        	state["commodity_maintenance_centimes"] = int(state.get("commodity_maintenance_centimes", 0)) + int(aggregate.get("maintenance", 0))
        	state["commodity_tax_centimes"] = int(state.get("commodity_tax_centimes", 0)) + int(aggregate.get("tax", 0))
        	state["last_commodity_margin_centimes"] = margin
        	state["commodity_cash_failure_days"] = failures
        	state["last_commodity_settlement_hour"] = total_hour
        	state["distress"] = clampi(
        		int(state.get("distress", 0)) + (-1 if all_paid and margin >= 0 else 3), 0, 100
        	)
        	_enterprise.enterprises[enterprise_id] = state
        	if failures >= 10 and int(state.get("distress", 0)) >= 95:
        		_enterprise.bankrupt(
        			"integration:bankrupt:%s:%d" % [enterprise_id, total_hour],
        			enterprise_id,
        			total_hour,
        			"商品经营连续现金流失败"
        		)
        ''',
    )
    text = replace_function(
        text,
        "_maybe_invest",
        '''
        func _maybe_invest(enterprise_id: String, total_hour: int) -> void:
        	if total_hour < 30 * HOURS_PER_DAY - 1 or (total_hour + 1) % (30 * HOURS_PER_DAY) != 0:
        		return
        	var state := _enterprise.enterprises.get(enterprise_id, {}) as Dictionary
        	if state.is_empty() or str(state.get("status", "")) not in AlphaEnterpriseService.ACTIVE_ENTERPRISE_STATUSES:
        		return
        	var site_ids := DataRecordUtils.to_string_array(state.get("production_site_ids", []))
        	if site_ids.is_empty():
        		return
        	var shortage_total := 0
        	var utilization_total := 0
        	for site_id: String in site_ids:
        		var site := _commodity_market.production_sites.get(site_id, {}) as Dictionary
        		shortage_total += _site_output_shortage_bp(site)
        		utilization_total += int(site.get("last_operating_bp", 0))
        	var average_shortage := shortage_total / site_ids.size()
        	var average_utilization := utilization_total / site_ids.size()
        	var available_cash := _economy.ledger.owner_cash(enterprise_id)
        	var investment := maxi(1000, int(state.get("commodity_revenue_centimes", 0)) / 200)
        	if average_shortage < 1600 or average_utilization < 8500 or available_cash < investment * 3:
        		return
        	var expanded := _enterprise.expand(
        		"integration:expand:%s:%d" % [enterprise_id, total_hour],
        		enterprise_id,
        		investment,
        		total_hour
        	)
        	if not bool(expanded.get("success", false)):
        		return
        	for site_id: String in site_ids:
        		var site := _commodity_market.production_sites.get(site_id, {}) as Dictionary
        		site["capacity_batches_per_day"] = float(site.get("capacity_batches_per_day", 0.0)) * 1.04
        		_commodity_market.production_sites[site_id] = site
        	decision_history.append({
        		"decision_id": "decision:enterprise_investment:%d:%s" % [total_hour, enterprise_id],
        		"total_hour": total_hour,
        		"enterprise_id": enterprise_id,
        		"decision_type": "capacity_investment",
        		"investment_centimes": investment,
        		"reason": "persistent_shortage_and_high_utilization",
        	})
        	_trim_history()
        ''',
    )
    text = replace_function(
        text,
        "_create_shipment",
        '''
        func _create_shipment(
        	origin_id: String,
        	destination_id: String,
        	commodity_id: String,
        	requested_units: float,
        	route: Dictionary,
        	total_hour: int
        ) -> Dictionary:
        	var origin_account := region_accounts[origin_id] as Dictionary
        	var destination_account := region_accounts[destination_id] as Dictionary
        	var origin_country := str(origin_account.get("country_id", ""))
        	var destination_country := str(destination_account.get("country_id", ""))
        	var cross_border := origin_country != destination_country
        	var relation := _trade_relations.get(_trade_key(origin_country, destination_country), {}) as Dictionary
        	if cross_border and (relation.is_empty() or bool(relation.get("embargo", false))):
        		return _fail("trade_blocked", "跨境贸易受禁运或缺少关系记录")
        	var units := requested_units
        	if cross_border:
        		units = minf(units, float(_trade_quota_remaining.get(_trade_key(origin_country, destination_country), 0.0)))
        		units = _limit_by_gold_reserve(destination_country, origin_country, origin_id, commodity_id, units)
        	var edge_ids := DataRecordUtils.to_string_array(route.get("edge_ids", []))
        	units = minf(units, _route_remaining_capacity(edge_ids))
        	if units <= 0.0001:
        		return _fail("shipment_capacity_missing", "运输、配额或黄金储备不足")
        	var shipment_id := "shipment:commodity:%d" % _next_shipment_sequence
        	_next_shipment_sequence += 1
        	var unit_price := _commodity_market.market_price(origin_id, commodity_id)
        	var goods_value := maxi(1, int(round(float(unit_price) * units)))
        	var route_terms := _route_terms(edge_ids)
        	var carrier_rates := route_terms.get("carrier_cost_per_unit", {}) as Dictionary
        	if carrier_rates.is_empty():
        		return _fail("carrier_missing", "运输路径缺少承运企业")
        	var freight := maxi(0, int(round(float(route_terms.get("cost_per_unit", 0.0)) * units)))
        	var tariff_bp := int(relation.get("tariff_bp", 0)) if cross_border else 0
        	var preference_bp := int(relation.get("preference_bp", 0)) if cross_border else 0
        	var tariff := goods_value * maxi(0, tariff_bp - preference_bp) / BASIS_POINTS
        	var insurance := goods_value * int(_policies.get("insurance_premium_bp", 0)) / BASIS_POINTS
        	var buyer_id := str(destination_account.get("market_id", ""))
        	var seller_id := str(origin_account.get("market_id", ""))
        	var producer_id := _producer_for(origin_id, commodity_id)
        	var total_due := goods_value + freight + tariff + insurance
        	_ensure_market_liquidity(destination_id, total_due, total_hour, "shipment:%s" % shipment_id)
        	var buyer_cash := _economy.ledger.owner_cash(buyer_id)
        	if buyer_cash < total_due:
        		var ratio := float(buyer_cash) / float(maxi(1, total_due))
        		units *= clampf(ratio, 0.0, 1.0)
        		if units <= 0.0001:
        			return _fail("buyer_cash_missing", "进口地区市场结算现金不足")
        		goods_value = maxi(1, int(round(float(unit_price) * units)))
        		freight = maxi(0, int(round(float(route_terms.get("cost_per_unit", 0.0)) * units)))
        		tariff = goods_value * maxi(0, tariff_bp - preference_bp) / BASIS_POINTS
        		insurance = goods_value * int(_policies.get("insurance_premium_bp", 0)) / BASIS_POINTS
        	var payment_entries: Array[Dictionary] = [
        		{"owner_id": buyer_id, "delta_centimes": -(goods_value + freight + tariff + insurance)},
        		{"owner_id": ESCROW_ID, "delta_centimes": goods_value},
        		{"owner_id": INSURER_ID, "delta_centimes": insurance},
        	]
        	var carrier_payments: Dictionary = {}
        	var allocated_freight := 0
        	var carrier_ids := DataRecordUtils.to_string_array(carrier_rates.keys())
        	carrier_ids.sort()
        	for index: int in range(carrier_ids.size()):
        		var carrier_id := carrier_ids[index]
        		var amount := (
        			freight - allocated_freight
        			if index == carrier_ids.size() - 1
        			else int(round(float(carrier_rates.get(carrier_id, 0.0)) * units))
        		)
        		amount = maxi(0, amount)
        		allocated_freight += amount
        		carrier_payments[carrier_id] = amount
        		if amount > 0:
        			payment_entries.append({"owner_id": carrier_id, "delta_centimes": amount})
        	if tariff > 0:
        		var treasury_id := str((country_finance[destination_country] as Dictionary).get("treasury_id", ""))
        		payment_entries.append({"owner_id": treasury_id, "delta_centimes": tariff})
        	if not _post_owner_entries(
        		"integration:shipment:dispatch:%s" % shipment_id,
        		total_hour,
        		"commodity_shipment_dispatch",
        		"商品货款托管、分段运输、保险与关税原子分账",
        		payment_entries
        	):
        		return _fail("shipment_payment_failed", "运输发出结算失败")
        	if tariff > 0:
        		var finance := country_finance[destination_country] as Dictionary
        		finance["cumulative_tariff_centimes"] = int(finance.get("cumulative_tariff_centimes", 0)) + tariff
        		country_finance[destination_country] = finance
        	_remove_region_inventory(origin_id, commodity_id, units)
        	_record_market_metric(origin_id, "transit_dispatched", commodity_id, units)
        	_consume_route_capacity(edge_ids, units)
        	var gold_transferred := 0.0
        	if cross_border:
        		_trade_quota_remaining[_trade_key(origin_country, destination_country)] = maxf(
        			0.0,
        			float(_trade_quota_remaining.get(_trade_key(origin_country, destination_country), 0.0)) - units
        		)
        		gold_transferred = _transfer_gold_for_trade(destination_country, origin_country, goods_value)
        	var shipment := {
        		"shipment_id": shipment_id,
        		"status": "in_transit",
        		"origin_region_id": origin_id,
        		"destination_region_id": destination_id,
        		"origin_country_id": origin_country,
        		"destination_country_id": destination_country,
        		"commodity_id": commodity_id,
        		"units": units,
        		"seller_id": seller_id,
        		"producer_id": producer_id,
        		"buyer_id": buyer_id,
        		"carrier_payments": carrier_payments,
        		"dispatch_hour": total_hour,
        		"arrival_hour": total_hour + int(route_terms.get("duration_hours", HOURS_PER_DAY)),
        		"edge_ids": edge_ids,
        		"cross_border": cross_border,
        		"goods_value_centimes": goods_value,
        		"freight_centimes": freight,
        		"tariff_centimes": tariff,
        		"insurance_centimes": insurance,
        		"gold_grams_transferred": gold_transferred,
        		"risk_bp": int(route_terms.get("risk_bp", 0)),
        	}
        	shipments.append(shipment)
        	return _ok({"shipment": shipment.duplicate(true)})
        ''',
    )
    text = replace_function(
        text,
        "_route_terms",
        '''
        func _route_terms(edge_ids: Array[String]) -> Dictionary:
        	var duration := 0
        	var cost := 0.0
        	var risk := 0
        	var carrier_cost_per_unit: Dictionary = {}
        	for edge_id: String in edge_ids:
        		var edge := _edges_by_id.get(edge_id, {}) as Dictionary
        		duration += int(edge.get("duration_hours", 0))
        		var edge_cost := float(edge.get("cost_centimes_per_unit", 0.0))
        		cost += edge_cost
        		risk += int(edge.get("risk_bp", 0))
        		var carrier_id := str(edge.get("carrier_id", ""))
        		if not carrier_id.is_empty():
        			carrier_cost_per_unit[carrier_id] = float(carrier_cost_per_unit.get(carrier_id, 0.0)) + edge_cost
        	return {
        		"duration_hours": maxi(HOURS_PER_DAY, duration),
        		"cost_per_unit": cost,
        		"risk_bp": mini(int(_policies.get("maximum_route_risk_bp", 3500)), risk),
        		"carrier_cost_per_unit": carrier_cost_per_unit,
        	}
        ''',
    )
    text = replace_function(
        text,
        "_ensure_market_liquidity",
        '''
        func _ensure_market_liquidity(
        	region_id: String, required: int, total_hour: int, obligation_id: String = ""
        ) -> void:
        	if required <= 0:
        		return
        	var account := region_accounts[region_id] as Dictionary
        	var market_id := str(account.get("market_id", ""))
        	var cash := _economy.ledger.owner_cash(market_id)
        	if cash >= required:
        		return
        	var country_id := str(account.get("country_id", ""))
        	var central_bank_id := str((country_finance[country_id] as Dictionary).get("central_bank_id", ""))
        	var available := _economy.ledger.owner_cash(central_bank_id)
        	var injection := mini(required - cash, available)
        	if injection <= 0:
        		return
        	var sequence_key := "%d:%s" % [total_hour / HOURS_PER_DAY, region_id]
        	var sequence := int(_liquidity_sequence_by_day_region.get(sequence_key, 0)) + 1
        	_liquidity_sequence_by_day_region[sequence_key] = sequence
        	_safe_transfer(
        		"integration:clearing_liquidity:%d:%s:%s:%d" % [
        			total_hour, region_id, obligation_id.validate_node_name(), sequence,
        		],
        		total_hour,
        		central_bank_id,
        		market_id,
        		injection,
        		"clearing_liquidity",
        		"商品市场日内清算流动性"
        	)
        ''',
    )
    text = replace_function(
        text,
        "_transfer_gold_for_trade",
        '''
        func _transfer_gold_for_trade(importer_country: String, exporter_country: String, value: int) -> float:
        	if importer_country == exporter_country or value <= 0:
        		return 0.0
        	var importer := country_finance[importer_country] as Dictionary
        	var exporter := country_finance[exporter_country] as Dictionary
        	var parity := maxf(1.0, float(importer.get("parity_centimes_per_gram", 1.0)))
        	var exchange_rate := maxf(1.0, float(importer.get("exchange_rate_bp", BASIS_POINTS)))
        	var gold := float(value) * exchange_rate / float(BASIS_POINTS) / parity
        	gold = minf(gold, float(importer.get("gold_reserve_grams", 0.0)))
        	importer["gold_reserve_grams"] = maxf(0.0, float(importer.get("gold_reserve_grams", 0.0)) - gold)
        	exporter["gold_reserve_grams"] = float(exporter.get("gold_reserve_grams", 0.0)) + gold
        	importer["cumulative_trade_balance_centimes"] = int(importer.get("cumulative_trade_balance_centimes", 0)) - value
        	exporter["cumulative_trade_balance_centimes"] = int(exporter.get("cumulative_trade_balance_centimes", 0)) + value
        	country_finance[importer_country] = importer
        	country_finance[exporter_country] = exporter
        	return gold
        ''',
    )
    text = replace_function(
        text,
        "_refund_failed_shipment",
        '''
        func _refund_failed_shipment(shipment: Dictionary, total_hour: int) -> void:
        	var buyer_id := str(shipment.get("buyer_id", ""))
        	var goods_value := int(shipment.get("goods_value_centimes", 0))
        	_refund_escrow(str(shipment.get("shipment_id", "")), buyer_id, goods_value, total_hour)
        	_reverse_gold_for_trade(shipment)


        func _reverse_gold_for_trade(shipment: Dictionary) -> void:
        	if not bool(shipment.get("cross_border", false)):
        		return
        	var importer_id := str(shipment.get("destination_country_id", ""))
        	var exporter_id := str(shipment.get("origin_country_id", ""))
        	var gold := float(shipment.get("gold_grams_transferred", 0.0))
        	var value := int(shipment.get("goods_value_centimes", 0))
        	if gold <= 0.0 or not country_finance.has(importer_id) or not country_finance.has(exporter_id):
        		return
        	var importer := country_finance[importer_id] as Dictionary
        	var exporter := country_finance[exporter_id] as Dictionary
        	var reversible := minf(gold, float(exporter.get("gold_reserve_grams", 0.0)))
        	exporter["gold_reserve_grams"] = maxf(0.0, float(exporter.get("gold_reserve_grams", 0.0)) - reversible)
        	importer["gold_reserve_grams"] = float(importer.get("gold_reserve_grams", 0.0)) + reversible
        	importer["cumulative_trade_balance_centimes"] = int(importer.get("cumulative_trade_balance_centimes", 0)) + value
        	exporter["cumulative_trade_balance_centimes"] = int(exporter.get("cumulative_trade_balance_centimes", 0)) - value
        	country_finance[importer_id] = importer
        	country_finance[exporter_id] = exporter
        ''',
    )
    insertion = dedent('''

    func is_integrated_enterprise(enterprise_id: String) -> bool:
    	return enterprise_id in site_enterprise.values()


    func manage_integrated_enterprise(enterprise_id: String, total_hour: int) -> Dictionary:
    	if not is_integrated_enterprise(enterprise_id):
    		return _fail("enterprise_not_integrated", "企业未接入商品经营结算")
    	var state := _enterprise.enterprises.get(enterprise_id, {}) as Dictionary
    	if state.is_empty():
    		return _fail("enterprise_missing", "企业不存在")
    	var changed := 0
    	for raw_site_id: Variant in site_enterprise:
    		var site_id := str(raw_site_id)
    		if str(site_enterprise[site_id]) != enterprise_id:
    			continue
    		var site := _commodity_market.production_sites.get(site_id, {}) as Dictionary
    		var target := int(site.get("operating_target_bp", BASIS_POINTS))
    		var shortage := _site_output_shortage_bp(site)
    		var margin := int(state.get("last_commodity_margin_centimes", 0))
    		var step := int(_policies.get("operating_target_step_bp", 350))
    		if shortage >= 1800 and margin >= 0:
    			target += step
    		elif shortage <= 200 or margin < 0:
    			target -= step
    		target = clampi(
    			target,
    			int(_policies.get("minimum_operating_target_bp", 1500)),
    			int(_policies.get("maximum_operating_target_bp", BASIS_POINTS))
    		)
    		if target != int(site.get("operating_target_bp", BASIS_POINTS)):
    			site["operating_target_bp"] = target
    			_commodity_market.production_sites[site_id] = site
    			changed += 1
    	return _ok({"enterprise_id": enterprise_id, "sites_changed": changed, "total_hour": total_hour})
    ''').strip() + "\n\n\n"
    anchor = "func transport_edge_count() -> int:"
    if "func is_integrated_enterprise" not in text:
        text = text.replace(anchor, insertion + anchor, 1)
    write(path, text)


def patch_world_dynamics() -> None:
    path = "scripts/alpha/alpha_world_dynamics_service.gd"
    text = read(path)
    text = replace_once(
        text,
        "var _commodity_market: AlphaCommodityMarketService\n",
        "var _commodity_market: AlphaCommodityMarketService\nvar _economy_integration: AlphaEconomyIntegrationService\n",
        "world dynamics integration var",
    )
    text = text.replace(
        "\tcommodity_market: AlphaCommodityMarketService = null\n) -> bool:",
        "\tcommodity_market: AlphaCommodityMarketService = null,\n\teconomy_integration: AlphaEconomyIntegrationService = null\n) -> bool:",
        1,
    )
    text = replace_once(
        text,
        "\t_commodity_market = commodity_market\n",
        "\t_commodity_market = commodity_market\n\t_economy_integration = economy_integration\n",
        "world dynamics integration assign",
    )
    text = replace_once(
        text,
        "\t\tif str(state.get(\"status\", \"\")) not in AlphaEnterpriseService.ACTIVE_ENTERPRISE_STATUSES:\n\t\t\tcontinue\n\t\t_enterprise.aggregate_day(\n",
        "\t\tif str(state.get(\"status\", \"\")) not in AlphaEnterpriseService.ACTIVE_ENTERPRISE_STATUSES:\n\t\t\tcontinue\n\t\tif _economy_integration != null and _economy_integration.is_integrated_enterprise(organization_id):\n\t\t\tcontinue\n\t\t_enterprise.aggregate_day(\n",
        "skip integrated enterprises",
    )
    write(path, text)


def patch_ai() -> None:
    path = "scripts/alpha/alpha_ai_service.gd"
    text = read(path)
    text = replace_once(
        text,
        "var _characters: AlphaCharacterService\n",
        "var _characters: AlphaCharacterService\nvar _commodity_market: AlphaCommodityMarketService\nvar _economy_integration: AlphaEconomyIntegrationService\nvar _historical_world: AlphaHistoricalWorldEconomyData\n",
        "ai dependencies",
    )
    text = text.replace(
        "\tcharacters: AlphaCharacterService\n) -> bool:",
        "\tcharacters: AlphaCharacterService,\n\tcommodity_market: AlphaCommodityMarketService = null,\n\teconomy_integration: AlphaEconomyIntegrationService = null,\n\thistorical_world: AlphaHistoricalWorldEconomyData = null\n) -> bool:",
        1,
    )
    text = replace_once(
        text,
        "\t_characters = characters\n",
        "\t_characters = characters\n\t_commodity_market = commodity_market\n\t_economy_integration = economy_integration\n\t_historical_world = historical_world\n",
        "ai dependency assign",
    )
    text = replace_function(
        text,
        "process_person_day",
        '''
        func process_person_day(
        	character: CharacterData, known: Dictionary, total_hour: int
        ) -> Dictionary:
        	if character == null:
        		return _result(false, "invalid_character", {})
        	var day_index: int = total_hour / 24
        	var process_key: String = "%s:%d" % [character.id, day_index]
        	if _processed_days.has(process_key):
        		return _result(true, "already_processed", {
        			"decision_id": str(_processed_days[process_key]),
        			"duplicate": true,
        		})
        	var candidates: Array[Dictionary] = build_candidates(character, known, total_hour)
        	if candidates.is_empty():
        		return _result(false, "no_candidate", {})
        	var ordered := candidates.duplicate(true)
        	var secondary_day: bool = posmod(day_index + absi(character.id.hash()), 7) == 0
        	if secondary_day:
        		for index: int in range(ordered.size()):
        			var action := str((ordered[index] as Dictionary).get("action_id", ""))
        			if action not in ["work", "seek_job", "migrate_for_work", "seek_credit", "repay_debt", "join_organization", "wait"]:
        				var secondary := ordered[index]
        				ordered.remove_at(index)
        				ordered.push_front(secondary)
        				break
        	var attempted: Array[String] = []
        	var selected := ordered[0] as Dictionary
        	var execution := _result(false, "no_action_succeeded", {})
        	for candidate: Dictionary in ordered:
        		var action_id := str(candidate.get("action_id", "wait"))
        		attempted.append(action_id)
        		var attempt := _execute(character, action_id, known, total_hour, process_key)
        		selected = candidate
        		execution = attempt
        		if bool(attempt.get("success", false)):
        			break
        	var final_action_id := str(selected.get("action_id", "wait"))
        	var decision: Dictionary = {
        		"decision_id": "ai_decision:%s:%d" % [character.id, day_index],
        		"person_id": character.id,
        		"total_hour": total_hour,
        		"action_id": final_action_id,
        		"reason": str(selected.get("reason", "")),
        		"known_fields_used": (selected.get("known_fields_used", []) as Array).duplicate(),
        		"candidate_count": candidates.size(),
        		"attempted_action_ids": attempted,
        		"execution_success": bool(execution.get("success", false)),
        		"execution_code": str(execution.get("code", "")),
        	}
        	decisions.append(decision)
        	while decisions.size() > HISTORY_LIMIT:
        		decisions.pop_front()
        	_processed_days[process_key] = decision["decision_id"]
        	_trim_processed_days(day_index)
        	return _result(true, "ok", {
        		"decision": decision.duplicate(true),
        		"execution": execution.duplicate(true),
        	})
        ''',
    )
    old_manage = '''\t\t"manage_enterprise":\n\t\t\treturn _enterprise.aggregate_day(\n\t\t\t\t"ai:manage:%s" % key,\n\t\t\t\tstr(known.get("controlled_enterprise_id", "")),\n\t\t\t\ttotal_hour\n\t\t\t)'''
    new_manage = '''\t\t"manage_enterprise":\n\t\t\tvar managed_id := str(known.get("controlled_enterprise_id", ""))\n\t\t\tif _economy_integration != null and _economy_integration.is_integrated_enterprise(managed_id):\n\t\t\t\treturn _economy_integration.manage_integrated_enterprise(managed_id, total_hour)\n\t\t\treturn _enterprise.aggregate_day(\n\t\t\t\t"ai:manage:%s" % key, managed_id, total_hour\n\t\t\t)'''
    text = replace_once(text, old_manage, new_manage, "ai manage integrated")
    text = text.replace('str(known.get("business_input_id", "grain"))', 'str(known.get("business_input_id", "wheat"))')
    write(path, text)


def patch_simulation() -> None:
    path = "scripts/alpha/alpha_simulation_service.gd"
    text = read(path)
    text = replace_once(
        text,
        "var economy_integration := AlphaEconomyIntegrationService.new()\n",
        "var economy_integration := AlphaEconomyIntegrationService.new()\nvar historical_world_economy := AlphaHistoricalWorldEconomyData.new()\n",
        "historical runtime var",
    )
    text = replace_once(
        text,
        "\tif not character_service.configure(\n",
        "\tif not historical_world_economy.configure():\n\t\treturn _fail_alpha(\"1900历史世界经济数据初始化失败：%s\" % historical_world_economy.initialization_error)\n\tif not character_service.configure(\n",
        "historical configure",
    )
    text = text.replace(
        "\t\tlabor, economy, enterprise, politics, organization_service,\n\t\tcharacter_service\n",
        "\t\tlabor, economy, enterprise, politics, organization_service,\n\t\tcharacter_service, commodity_market, economy_integration, historical_world_economy\n",
        1,
    )
    text = text.replace(
        "\t\tworld, economy, enterprise, politics, roster, alpha_config, commodity_market\n",
        "\t\tworld, economy, enterprise, politics, roster, alpha_config, commodity_market,\n\t\teconomy_integration\n",
        1,
    )
    text = replace_function(
        text,
        "_settle_hour",
        '''
        func _settle_hour(total_hour: int) -> void:
        	var started_usec: int = Time.get_ticks_usec()
        	var legacy_before: Dictionary = _legacy_cash_snapshot()
        	super._settle_hour(total_hour)
        	_reconcile_legacy_cash(legacy_before, total_hour)
        	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
        	if int(value.get("hour", -1)) == 23:
        		var snapshot := _capture_economy_day_state()
        		economy.expire_market_shocks(total_hour)
        		var market_result: Dictionary = commodity_market.settle_day(total_hour)
        		var delivery_result: Dictionary = _result(false, "not_run", {})
        		var integration_result: Dictionary = _result(false, "not_run", {})
        		var failed_code := ""
        		if not bool(market_result.get("success", false)):
        			failed_code = "commodity_market_failure"
        		else:
        			delivery_result = economy_integration.deliver_due_shipments(total_hour)
        			if not bool(delivery_result.get("success", false)):
        				failed_code = "shipment_delivery_failure"
        			else:
        				integration_result = economy_integration.settle_day(total_hour)
        				if not bool(integration_result.get("success", false)):
        					failed_code = "economy_integration_failure"
        		if not failed_code.is_empty():
        			_restore_economy_day_state(snapshot)
        			_append_alpha_event({
        				"event_id": "event:%s:%d" % [failed_code, total_hour],
        				"total_hour": total_hour,
        				"fact_type": failed_code,
        				"summary": "商品、现金、企业、劳动与运输日结未能原子完成，已完整回滚。",
        				"requires_decision": true,
        			})
        		else:
        			_process_active_ai(total_hour)
        			world_dynamics.process_boundaries(total_hour, roster.active_characters)
        			_settle_due_development(total_hour)
        	alpha_hours_processed += 1
        	alpha_last_hour_usec = Time.get_ticks_usec() - started_usec
        	alpha_maximum_hour_usec = maxi(alpha_maximum_hour_usec, alpha_last_hour_usec)


        func _capture_economy_day_state() -> Dictionary:
        	return {
        		"economy": economy.get_persistent_state(),
        		"commodity_market": commodity_market.get_persistent_state(),
        		"economy_integration": economy_integration.get_persistent_state(),
        		"enterprise": enterprise.get_persistent_state(),
        		"labor": labor.get_persistent_state(),
        	}


        func _restore_economy_day_state(snapshot: Dictionary) -> bool:
        	var ok := economy.restore_persistent_state(snapshot.get("economy", {}) as Dictionary)
        	ok = commodity_market.restore_persistent_state(snapshot.get("commodity_market", {}) as Dictionary) and ok
        	ok = enterprise.restore_persistent_state(snapshot.get("enterprise", {}) as Dictionary) and ok
        	ok = labor.restore_persistent_state(snapshot.get("labor", {}) as Dictionary) and ok
        	ok = economy_integration.restore_persistent_state(snapshot.get("economy_integration", {}) as Dictionary) and ok
        	return ok
        ''',
    )
    text = replace_once(
        text,
        'counts["enterprise_economic_decisions"] = economy_integration.decision_history.size()\n',
        'counts["enterprise_economic_decisions"] = economy_integration.decision_history.size()\n'
        'counts["historical_world_countries"] = historical_world_economy.countries.size()\n'
        'counts["historical_formal_countries"] = historical_world_economy.formal_countries().size()\n',
        "historical counts",
    )
    write(path, text)


def patch_validation() -> None:
    path = "tools/run_validation.ps1"
    text = read(path)
    audit_anchor = "$tests = @(\n"
    audit_block = dedent('''
    Write-Host "`n=== 1900 economy static audits ==="
    & python "$ProjectPath/tools/audit_1900_commodity_economy.py"
    if ($LASTEXITCODE -ne 0) { throw 'Commodity economy static audit failed' }
    & python "$ProjectPath/tools/audit_1900_economy_integration.py"
    if ($LASTEXITCODE -ne 0) { throw 'Economy integration static audit failed' }
    & python "$ProjectPath/tools/audit_1900_world_economy_compact.py"
    if ($LASTEXITCODE -ne 0) { throw 'Historical world economy static audit failed' }

    ''')
    if "1900 economy static audits" not in text:
        text = text.replace(audit_anchor, audit_block + audit_anchor, 1)
    test_anchor = "    @{ Name = 'Grid fixture economy lifecycle'; Script = 'res://tests/alpha/alpha_economy_lifecycle_test.gd' },\n"
    additions = test_anchor + dedent('''
        @{ Name = 'Grid fixture commodity market'; Script = 'res://tests/alpha/alpha_commodity_market_test.gd'; TimeoutSeconds = 180 },
        @{ Name = 'Grid fixture economy UI'; Script = 'res://tests/alpha/alpha_economy_ui_audit_test.gd'; TimeoutSeconds = 180 },
        @{ Name = 'Grid fixture unified economy phase two'; Script = 'res://tests/alpha/alpha_economy_integration_phase2_test.gd'; TimeoutSeconds = 240 },
        @{ Name = 'Grid fixture AI economy stability'; Script = 'res://tests/alpha/alpha_ai_economy_stability_test.gd'; TimeoutSeconds = 300 },
        @{ Name = 'Historical world economy data'; Script = 'res://tests/alpha/alpha_historical_world_economy_data_test.gd'; TimeoutSeconds = 120 },
        @{ Name = 'Formal historical world integration'; Script = 'res://tests/formal/formal_world_integration_test.gd'; TimeoutSeconds = 300 },
    ''')
    if "Formal historical world integration" not in text:
        text = text.replace(test_anchor, additions, 1)
    write(path, text)


def patch_alpha_workflow() -> None:
    path = ".github/workflows/alpha-commodity-economy.yml"
    text = read(path)
    text = replace_once(
        text,
        '      - "scripts/alpha/**"\n',
        '      - "scripts/alpha/**"\n      - "scripts/formal/**"\n      - "scenes/formal/**"\n      - "tests/formal/**"\n',
        "formal workflow paths",
    )
    text = replace_once(
        text,
        "            tests/alpha/alpha_historical_world_economy_data_test.gd\n",
        "            tests/alpha/alpha_historical_world_economy_data_test.gd\n            tests/formal/formal_world_integration_test.gd\n",
        "formal workflow test",
    )
    write(path, text)


def cleanup_repository() -> None:
    cleanup = ROOT / ".github/workflows/cleanup-completed-agent-branches.yml"
    if cleanup.exists():
        cleanup.unlink()


def main() -> None:
    patch_menu()
    patch_historical_data()
    patch_commodity_market()
    patch_integration_service()
    patch_world_dynamics()
    patch_ai()
    patch_simulation()
    patch_validation()
    patch_alpha_workflow()
    cleanup_repository()
    print("formal world integration patches applied")


if __name__ == "__main__":
    main()
