class_name AlphaEconomyIntegrationService
extends RefCounted
## Unifies physical commodity flows with cash, enterprises, labor, logistics and public finance.
## Detailed historical-world nodes are admitted only through the source-gated coverage registry.

const BASIS_POINTS: int = 10000
const HOURS_PER_DAY: int = 24
const ESCROW_ID: String = "system:commodity_trade_escrow"
const INSURER_ID: String = "system:commodity_trade_insurer"
const CAPITAL_SUPPLIER_ID: String = "system:capital_goods_supplier"
const HISTORY_LIMIT_FALLBACK: int = 512

var shipments: Array[Dictionary] = []
var shipment_history: Array[Dictionary] = []
var decision_history: Array[Dictionary] = []
var government_stockpiles: Dictionary = {}
var country_finance: Dictionary = {}
var region_accounts: Dictionary = {}
var site_enterprise: Dictionary = {}
var daily_summary: Dictionary = {}
var initialization_error: String = ""

var _commodity_market: AlphaCommodityMarketService
var _economy: AlphaEconomyService
var _enterprise: AlphaEnterpriseService
var _labor: AlphaLaborService
var _config: AlphaConfig
var _document: Dictionary = {}
var _policies: Dictionary = {}
var _adjacency: Dictionary = {}
var _edges_by_id: Dictionary = {}
var _nearest_by_origin: Dictionary = {}
var _producer_by_region_commodity: Dictionary = {}
var _industrial_need_capacity: Dictionary = {}
var _household_strata: Array[Dictionary] = []
var _trade_relations: Dictionary = {}
var _procurement_rules: Array[Dictionary] = []
var _edge_remaining_capacity: Dictionary = {}
var _trade_quota_remaining: Dictionary = {}
var _processed_days: Dictionary = {}
var _next_shipment_sequence: int = 1
var _liquidity_sequence_by_day_region: Dictionary = {}


func configure(
	config: AlphaConfig,
	commodity_market: AlphaCommodityMarketService,
	economy: AlphaEconomyService,
	enterprise: AlphaEnterpriseService,
	labor: AlphaLaborService
) -> bool:
	_config = config
	_commodity_market = commodity_market
	_economy = economy
	_enterprise = enterprise
	_labor = labor
	shipments.clear()
	shipment_history.clear()
	decision_history.clear()
	government_stockpiles.clear()
	country_finance.clear()
	region_accounts.clear()
	site_enterprise.clear()
	daily_summary.clear()
	_adjacency.clear()
	_edges_by_id.clear()
	_nearest_by_origin.clear()
	_producer_by_region_commodity.clear()
	_industrial_need_capacity.clear()
	_trade_relations.clear()
	_procurement_rules.clear()
	_edge_remaining_capacity.clear()
	_trade_quota_remaining.clear()
	_processed_days.clear()
	_next_shipment_sequence = 1
	_liquidity_sequence_by_day_region.clear()
	initialization_error = ""
	_document = config.economy_integration()
	if str(_document.get("schema_id", "")) != "alpha_economy_integration_1900_v1":
		return _fail_initialize("统一经济结算配置 Schema 无效")
	_policies = (_document.get("policies", {}) as Dictionary).duplicate(true)
	_commodity_market.set_external_logistics_managed(bool(
		_policies.get("external_logistics_managed", true)
	))
	_household_strata = DataRecordUtils.to_dictionary_array(
		_document.get("household_strata", [])
	)
	_procurement_rules = DataRecordUtils.to_dictionary_array(
		_document.get("government_procurement", [])
	)
	if not _register_system_accounts():
		return false
	if not _initialize_countries():
		return false
	if not _initialize_regions():
		return false
	if not _initialize_trade_relations():
		return false
	if not _initialize_transport_graph():
		return false
	if not _assign_production_sites():
		return false
	_build_capacity_indexes()
	_build_all_nearest_indexes()
	var integrity := validate_integrity()
	if not bool(integrity.get("success", false)):
		return _fail_initialize(str(integrity.get("message", "统一经济结算完整性失败")))
	return true


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


func settle_day(total_hour: int) -> Dictionary:
	var day_index := total_hour / HOURS_PER_DAY
	if _processed_days.has(day_index):
		return _ok({"duplicate": true, "day_index": day_index})
	_reset_daily_limits()
	var household_result := _settle_household_consumption(total_hour)
	var enterprise_result := _settle_enterprises(total_hour)
	var shipment_result := _schedule_shortage_shipments(total_hour)
	var procurement_result := _settle_government_procurement(total_hour)
	_adjust_exchange_rates()
	_sync_labor_market()
	_processed_days[day_index] = true
	daily_summary = {
		"day_index": day_index,
		"total_hour": total_hour,
		"household_spending_centimes": int(household_result.get("spending_centimes", 0)),
		"household_arrears_centimes": int(household_result.get("arrears_centimes", 0)),
		"enterprise_revenue_centimes": int(enterprise_result.get("revenue_centimes", 0)),
		"enterprise_cost_centimes": int(enterprise_result.get("cost_centimes", 0)),
		"wages_centimes": int(enterprise_result.get("wages_centimes", 0)),
		"business_tax_centimes": int(enterprise_result.get("tax_centimes", 0)),
		"shipments_created": int(shipment_result.get("shipment_count", 0)),
		"shipment_units": float(shipment_result.get("shipment_units", 0.0)),
		"tariff_centimes": int(shipment_result.get("tariff_centimes", 0)),
		"freight_centimes": int(shipment_result.get("freight_centimes", 0)),
		"procurement_units": float(procurement_result.get("purchased_units", 0.0)),
		"strategic_release_units": float(procurement_result.get("released_units", 0.0)),
		"active_shipments": shipments.size(),
		"gold_reserves": _gold_reserve_summary(),
	}
	return _ok(daily_summary.duplicate(true))


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


func transport_edge_count() -> int:
	return _edges_by_id.size()


func integration_summary() -> Dictionary:
	var summary := daily_summary.duplicate(true)
	summary["active_shipments"] = shipments.size()
	summary["shipment_history_count"] = shipment_history.size()
	summary["decision_count"] = decision_history.size()
	summary["government_stockpiles"] = government_stockpiles.duplicate(true)
	summary["country_finance"] = country_finance.duplicate(true)
	return summary


func validate_integrity() -> Dictionary:
	if region_accounts.size() != _commodity_market.region_states.size():
		return _fail("region_account_mismatch", "地区市场账户与商品地区数量不一致")
	if site_enterprise.size() != _commodity_market.production_sites.size():
		return _fail("site_owner_mismatch", "生产设施没有全部绑定企业")
	if _edges_by_id.is_empty() or _nearest_by_origin.size() != region_accounts.size():
		return _fail("transport_graph_incomplete", "运输图或邻近索引不完整")
	for raw_site_id: Variant in site_enterprise:
		var enterprise_id := str(site_enterprise[raw_site_id])
		if not _enterprise.enterprises.has(enterprise_id):
			return _fail("site_owner_missing", "生产设施引用未知企业：%s" % enterprise_id)
	for raw_country: Variant in country_finance.values():
		var finance := raw_country as Dictionary
		if (
			float(finance.get("gold_reserve_grams", -1.0)) < 0.0
			or int(finance.get("exchange_rate_bp", 0)) <= 0
		):
			return _fail("currency_state_invalid", "货币或黄金储备状态无效")
	for shipment: Dictionary in shipments:
		if (
			float(shipment.get("units", 0.0)) <= 0.0
			or int(shipment.get("arrival_hour", 0)) <= int(shipment.get("dispatch_hour", 0))
		):
			return _fail("shipment_invalid", "在途运输记录无效")
	var ledger_check := _economy.ledger.validate_balances()
	if not bool(ledger_check.get("success", false)):
		return ledger_check
	return _ok({
		"regions": region_accounts.size(),
		"transport_edges": _edges_by_id.size(),
		"site_bindings": site_enterprise.size(),
		"active_shipments": shipments.size(),
	})


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


func _register_system_accounts() -> bool:
	for record: Dictionary in [
		{"id": ESCROW_ID, "type": "system", "cash": 0},
		{"id": INSURER_ID, "type": "organization", "cash": 12000000},
		{"id": CAPITAL_SUPPLIER_ID, "type": "organization", "cash": 16000000},
	]:
		if not _ensure_entity(
			str(record["id"]), str(record["type"]), int(record["cash"]), {}
		):
			return _fail_initialize("统一经济系统账户登记失败：%s" % str(record["id"]))
	return true


func _initialize_countries() -> bool:
	for raw_country: Variant in _document.get("countries", []) as Array:
		if not raw_country is Dictionary:
			return _fail_initialize("国家货币记录格式无效")
		var country := (raw_country as Dictionary).duplicate(true)
		var country_id := str(country.get("country_id", ""))
		var treasury_id := str(country.get("treasury_id", ""))
		var central_bank_id := str(country.get("central_bank_id", ""))
		if country_id.is_empty() or treasury_id.is_empty() or central_bank_id.is_empty():
			return _fail_initialize("国家财政记录缺少标识")
		if not _ensure_entity(
			treasury_id,
			"government",
			int(country.get("opening_treasury_cash_centimes", 0)),
			{"region_id": ""}
		):
			return false
		if not _ensure_entity(
			central_bank_id,
			"organization",
			int(country.get("opening_central_bank_cash_centimes", 0)),
			{"region_id": ""}
		):
			return false
		country["exchange_rate_bp"] = int(country.get("opening_exchange_rate_bp", BASIS_POINTS))
		country["opening_gold_reserve_grams"] = float(country.get("gold_reserve_grams", 0.0))
		country["cumulative_tariff_centimes"] = 0
		country["cumulative_trade_balance_centimes"] = 0
		country_finance[country_id] = country
		government_stockpiles[country_id] = {}
	return country_finance.size() >= 2


func _initialize_regions() -> bool:
	for raw_region: Variant in _document.get("regions", []) as Array:
		if not raw_region is Dictionary:
			return _fail_initialize("地区统一结算记录格式无效")
		var record := (raw_region as Dictionary).duplicate(true)
		var region_id := str(record.get("region_id", ""))
		var market_id := str(record.get("market_id", ""))
		var household_id := str(record.get("household_id", ""))
		if (
			region_id.is_empty()
			or not _commodity_market.region_states.has(region_id)
			or market_id.is_empty()
			or household_id.is_empty()
		):
			return _fail_initialize("地区统一结算引用无效：%s" % region_id)
		if not _ensure_entity(
			market_id,
			"market_clearing",
			int(record.get("market_opening_cash_centimes", 0)),
			{"region_id": region_id}
		):
			return false
		var population := int(
			(_commodity_market.region_states[region_id] as Dictionary).get("population", 0)
		)
		var stratum_ids: Array[String] = []
		for stratum: Dictionary in _household_strata:
			var stratum_id := "%s:%s" % [household_id, str(stratum.get("stratum_id", "household"))]
			var stratum_population := population * int(stratum.get("population_bp", 0)) / BASIS_POINTS
			var opening_cash := stratum_population * int(
				stratum.get("opening_cash_per_person_centimes", 0)
			)
			if not _ensure_entity(
				stratum_id,
				"household_pool",
				opening_cash,
				{"region_id": region_id}
			):
				return false
			stratum_ids.append(stratum_id)
		record["stratum_ids"] = stratum_ids
		record["household_arrears_centimes"] = 0
		record["last_household_spending_centimes"] = 0
		region_accounts[region_id] = record
		_adjacency[region_id] = []
	return region_accounts.size() == _commodity_market.region_states.size()


func _initialize_trade_relations() -> bool:
	for raw_relation: Variant in _document.get("trade_relations", []) as Array:
		if not raw_relation is Dictionary:
			return false
		var relation := (raw_relation as Dictionary).duplicate(true)
		var key := _trade_key(
			str(relation.get("exporter_country_id", "")),
			str(relation.get("importer_country_id", ""))
		)
		if key == ">" or _trade_relations.has(key):
			return false
		_trade_relations[key] = relation
	return true


func _initialize_transport_graph() -> bool:
	for raw_edge: Variant in _document.get("transport_edges", []) as Array:
		if not raw_edge is Dictionary:
			return false
		var edge := (raw_edge as Dictionary).duplicate(true)
		var edge_id := str(edge.get("edge_id", ""))
		var from_id := str(edge.get("from_region_id", ""))
		var to_id := str(edge.get("to_region_id", ""))
		if (
			edge_id.is_empty()
			or _edges_by_id.has(edge_id)
			or not region_accounts.has(from_id)
			or not region_accounts.has(to_id)
			or float(edge.get("capacity_units_per_day", 0.0)) <= 0.0
			or int(edge.get("duration_hours", 0)) <= 0
		):
			return _fail_initialize("运输边引用或容量无效：%s" % edge_id)
		_edges_by_id[edge_id] = edge
		_append_directional_edge(edge, false)
		if bool(edge.get("bidirectional", false)):
			_append_directional_edge(edge, true)
	return not _edges_by_id.is_empty()


func _append_directional_edge(edge: Dictionary, reverse: bool) -> void:
	var directional := edge.duplicate(true)
	var from_id := str(edge.get("from_region_id", ""))
	var to_id := str(edge.get("to_region_id", ""))
	if reverse:
		directional["from_region_id"] = to_id
		directional["to_region_id"] = from_id
	var actual_from := str(directional.get("from_region_id", ""))
	var neighbors := _adjacency.get(actual_from, []) as Array
	neighbors.append(directional)
	_adjacency[actual_from] = neighbors


func _assign_production_sites() -> bool:
	var assignment := _document.get("enterprise_assignment", {}) as Dictionary
	var region_enterprises := assignment.get("region_enterprises", {}) as Dictionary
	var affinity := assignment.get("recipe_structure_affinity", {}) as Dictionary
	for raw_site_id: Variant in _commodity_market.production_sites:
		var site_id := str(raw_site_id)
		var site := _commodity_market.production_sites[site_id] as Dictionary
		var region_id := str(site.get("region_id", ""))
		var recipe_id := str(site.get("recipe_id", ""))
		var candidates := DataRecordUtils.to_string_array(region_enterprises.get(region_id, []))
		var desired_structure := str(affinity.get(recipe_id, ""))
		var selected := ""
		for candidate_id: String in candidates:
			var state := _enterprise.enterprises.get(candidate_id, {}) as Dictionary
			if state.is_empty():
				continue
			if selected.is_empty():
				selected = candidate_id
			if not desired_structure.is_empty() and str(state.get("structure", "")) == desired_structure:
				selected = candidate_id
				break
		if selected.is_empty():
			return _fail_initialize("地区没有可用企业承接生产设施：%s" % site_id)
		site_enterprise[site_id] = selected
		site["enterprise_id"] = selected
		site["condition_bp"] = int(site.get("condition_bp", BASIS_POINTS))
		_commodity_market.production_sites[site_id] = site
		var enterprise_state := _enterprise.enterprises[selected] as Dictionary
		var ids := DataRecordUtils.to_string_array(enterprise_state.get("production_site_ids", []))
		if site_id not in ids:
			ids.append(site_id)
			ids.sort()
		enterprise_state["production_site_ids"] = ids
		_enterprise.enterprises[selected] = enterprise_state
	return true


func _build_capacity_indexes() -> void:
	for raw_region_id: Variant in region_accounts:
		var region_id := str(raw_region_id)
		_industrial_need_capacity[region_id] = {}
		_producer_by_region_commodity[region_id] = {}
	for raw_site_id: Variant in _commodity_market.production_sites:
		var site_id := str(raw_site_id)
		var site := _commodity_market.production_sites[site_id] as Dictionary
		var region_id := str(site.get("region_id", ""))
		var recipe := _commodity_market.recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
		var capacity := float(site.get("capacity_batches_per_day", 0.0))
		var input_map := _industrial_need_capacity[region_id] as Dictionary
		for input: Dictionary in DataRecordUtils.to_dictionary_array(recipe.get("inputs", [])):
			var commodity_id := str(input.get("commodity_id", ""))
			input_map[commodity_id] = float(input_map.get(commodity_id, 0.0)) + float(input.get("units", 0.0)) * capacity
		_industrial_need_capacity[region_id] = input_map
		var producer_map := _producer_by_region_commodity[region_id] as Dictionary
		for output: Dictionary in DataRecordUtils.to_dictionary_array(recipe.get("outputs", [])):
			var commodity_id := str(output.get("commodity_id", ""))
			if not producer_map.has(commodity_id):
				producer_map[commodity_id] = str(site_enterprise.get(site_id, ""))
		_producer_by_region_commodity[region_id] = producer_map


func _build_all_nearest_indexes() -> void:
	for raw_origin: Variant in region_accounts:
		var origin := str(raw_origin)
		_nearest_by_origin[origin] = _dijkstra_index(origin)


func _dijkstra_index(origin: String) -> Array[Dictionary]:
	var unvisited: Array[String] = []
	var distance: Dictionary = {}
	var duration: Dictionary = {}
	var paths: Dictionary = {}
	for raw_region_id: Variant in region_accounts:
		var region_id := str(raw_region_id)
		unvisited.append(region_id)
		distance[region_id] = INF
		duration[region_id] = 0
		paths[region_id] = []
	distance[origin] = 0.0
	while not unvisited.is_empty():
		var current := ""
		var current_distance := INF
		for candidate: String in unvisited:
			var candidate_distance := float(distance.get(candidate, INF))
			if candidate_distance < current_distance:
				current = candidate
				current_distance = candidate_distance
		if current.is_empty() or is_inf(current_distance):
			break
		unvisited.erase(current)
		for edge_value: Variant in _adjacency.get(current, []) as Array:
			var edge := edge_value as Dictionary
			var neighbor := str(edge.get("to_region_id", ""))
			if neighbor not in unvisited:
				continue
			var edge_cost := float(edge.get("cost_centimes_per_unit", 0)) + float(edge.get("duration_hours", 0)) * 0.2 + float(edge.get("risk_bp", 0)) / 1000.0
			var alternative := current_distance + edge_cost
			if alternative < float(distance.get(neighbor, INF)):
				distance[neighbor] = alternative
				duration[neighbor] = int(duration.get(current, 0)) + int(edge.get("duration_hours", 0))
				var path := (paths.get(current, []) as Array).duplicate()
				path.append(str(edge.get("edge_id", "")))
				paths[neighbor] = path
	var result: Array[Dictionary] = []
	for raw_region_id: Variant in region_accounts:
		var region_id := str(raw_region_id)
		if region_id == origin or is_inf(float(distance.get(region_id, INF))):
			continue
		result.append({
			"region_id": region_id,
			"distance_score": float(distance[region_id]),
			"duration_hours": int(duration[region_id]),
			"edge_ids": (paths[region_id] as Array).duplicate(),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance_score", INF)) < float(b.get("distance_score", INF))
	)
	return result


func _reset_daily_limits() -> void:
	_edge_remaining_capacity.clear()
	for raw_edge_id: Variant in _edges_by_id:
		var edge_id := str(raw_edge_id)
		_edge_remaining_capacity[edge_id] = float(
			(_edges_by_id[edge_id] as Dictionary).get("capacity_units_per_day", 0.0)
		)
	_trade_quota_remaining.clear()
	for raw_key: Variant in _trade_relations:
		var key := str(raw_key)
		_trade_quota_remaining[key] = float(
			(_trade_relations[key] as Dictionary).get("daily_quota_units", 0.0)
		)


func _settle_household_consumption(total_hour: int) -> Dictionary:
	var spending := 0
	var arrears := 0
	for raw_region_id: Variant in region_accounts:
		var region_id := str(raw_region_id)
		var account := region_accounts[region_id] as Dictionary
		var market_id := str(account.get("market_id", ""))
		var state := _commodity_market.region_states.get(region_id, {}) as Dictionary
		var metrics := state.get("daily_metrics", {}) as Dictionary
		var consumed := metrics.get("consumed", {}) as Dictionary
		var value := 0
		for raw_commodity_id: Variant in consumed:
			var commodity_id := str(raw_commodity_id)
			value += maxi(0, int(round(
				float(consumed[commodity_id])
				* float(_commodity_market.market_price(region_id, commodity_id))
			)))
		var entries: Array[Dictionary] = []
		var paid_total := 0
		var region_arrears := 0
		var allocated := 0
		for stratum_index: int in range(_household_strata.size()):
			var stratum := _household_strata[stratum_index] as Dictionary
			var share := (
				value - allocated
				if stratum_index == _household_strata.size() - 1
				else value * int(stratum.get("budget_share_bp", 0)) / BASIS_POINTS
			)
			allocated += share
			var payer_id := str((account.get("stratum_ids", []) as Array)[stratum_index])
			var paid := mini(share, _economy.ledger.owner_cash(payer_id))
			if paid > 0:
				entries.append({"owner_id": payer_id, "delta_centimes": -paid})
				paid_total += paid
			region_arrears += share - paid
		if paid_total > 0:
			entries.append({"owner_id": market_id, "delta_centimes": paid_total})
			if not _post_owner_entries(
				"integration:household:%d:%s" % [total_hour, region_id],
				total_hour,
				"household_consumption",
				"地区家庭阶层合并消费结算",
				entries
			):
				region_arrears += paid_total
				paid_total = 0
		account["last_household_spending_centimes"] = paid_total
		account["household_arrears_centimes"] = int(
			account.get("household_arrears_centimes", 0)
		) + region_arrears
		region_accounts[region_id] = account
		spending += paid_total
		arrears += region_arrears
	return {"spending_centimes": spending, "arrears_centimes": arrears}

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


func _settle_site_expenses(
	enterprise_id: String,
	region_id: String,
	market_id: String,
	input_cost: int,
	wage_cost: int,
	maintenance: int,
	tax: int,
	total_hour: int,
	site_id: String
) -> bool:
	var total_expense := input_cost + wage_cost + maintenance + tax
	if total_expense <= 0:
		return true
	var account := region_accounts[region_id] as Dictionary
	var country_id := str(account.get("country_id", ""))
	var treasury_id := str((country_finance[country_id] as Dictionary).get("treasury_id", ""))
	var entries: Array[Dictionary] = [
		{"owner_id": enterprise_id, "delta_centimes": -total_expense},
		{"owner_id": market_id, "delta_centimes": input_cost},
		{"owner_id": CAPITAL_SUPPLIER_ID, "delta_centimes": maintenance},
		{"owner_id": treasury_id, "delta_centimes": tax},
	]
	var allocated := 0
	for stratum_index: int in range(_household_strata.size()):
		var share := (
			wage_cost - allocated
			if stratum_index == _household_strata.size() - 1
			else wage_cost * int((_household_strata[stratum_index] as Dictionary).get("population_bp", 0)) / BASIS_POINTS
		)
		allocated += share
		if share > 0:
			entries.append({
				"owner_id": str((account.get("stratum_ids", []) as Array)[stratum_index]),
				"delta_centimes": share,
			})
	return _post_owner_entries(
		"integration:expenses:%d:%s" % [total_hour, site_id],
		total_hour,
		"commodity_operating_expenses",
		"生产设施原料、工资、维护与税费合并结算",
		entries
	)

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


func _site_output_shortage_bp(site: Dictionary) -> int:
	var recipe := _commodity_market.recipes.get(str(site.get("recipe_id", "")), {}) as Dictionary
	var region_id := str(site.get("region_id", ""))
	var maximum := 0
	var region_state := _commodity_market.region_states.get(region_id, {}) as Dictionary
	var metrics := region_state.get("daily_metrics", {}) as Dictionary
	for output: Dictionary in DataRecordUtils.to_dictionary_array(recipe.get("outputs", [])):
		var commodity_id := str(output.get("commodity_id", ""))
		var demand := float((metrics.get("demand", {}) as Dictionary).get(commodity_id, 0.0))
		var unmet := float((metrics.get("unmet", {}) as Dictionary).get(commodity_id, 0.0))
		if demand > 0.0:
			maximum = maxi(maximum, int(round(clampf(unmet / demand, 0.0, 1.0) * BASIS_POINTS)))
	return maximum


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
		maxi(1, site_ids.size()),
		CAPITAL_SUPPLIER_ID,
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


func _schedule_shortage_shipments(total_hour: int) -> Dictionary:
	var shipment_count := 0
	var shipment_units := 0.0
	var tariff_total := 0
	var freight_total := 0
	var max_suppliers := int(_policies.get("maximum_nearby_suppliers", 8))
	var target_stock_units: Dictionary = {}
	for raw_commodity_id: Variant in _commodity_market.commodities:
		var commodity_id := str(raw_commodity_id)
		for raw_receiver_id: Variant in region_accounts:
			var receiver_id := str(raw_receiver_id)
			var unmet := _metric_value(receiver_id, "unmet", commodity_id)
			if unmet <= 0.0001:
				continue
			var candidates := _nearest_by_origin.get(receiver_id, []) as Array
			var checked := 0
			for route_value: Variant in candidates:
				if unmet <= 0.0001 or checked >= max_suppliers:
					break
				checked += 1
				var route := route_value as Dictionary
				var donor_id := str(route.get("region_id", ""))
				var target_key := "%s|%s" % [donor_id, commodity_id]
				if not target_stock_units.has(target_key):
					target_stock_units[target_key] = _target_stock_units(
						donor_id, commodity_id
					)
				var surplus := maxf(
					0.0,
					_commodity_market.inventory_units(donor_id, commodity_id)
					- float(target_stock_units[target_key]) * 0.85
				)
				if surplus <= 0.0001:
					continue
				var route_capacity := _route_remaining_capacity(route.get("edge_ids", []) as Array)
				var units := minf(unmet, minf(surplus, route_capacity))
				if units <= 0.0001:
					continue
				var created := _create_shipment(
					donor_id, receiver_id, commodity_id, units, route, total_hour
				)
				if not bool(created.get("success", false)):
					continue
				var data := created.get("data", {}) as Dictionary
				var shipment := data.get("shipment", {}) as Dictionary
				var moved := float(shipment.get("units", 0.0))
				if moved <= 0.0:
					continue
				unmet -= moved
				shipment_count += 1
				shipment_units += moved
				tariff_total += int(shipment.get("tariff_centimes", 0))
				freight_total += int(shipment.get("freight_centimes", 0))
	return {
		"shipment_count": shipment_count,
		"shipment_units": shipment_units,
		"tariff_centimes": tariff_total,
		"freight_centimes": freight_total,
	}


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


func _route_remaining_capacity(edge_ids: Array) -> float:
	var capacity := INF
	for raw_edge_id: Variant in edge_ids:
		capacity = minf(capacity, float(_edge_remaining_capacity.get(str(raw_edge_id), 0.0)))
	return 0.0 if is_inf(capacity) else maxf(0.0, capacity)


func _consume_route_capacity(edge_ids: Array[String], units: float) -> void:
	for edge_id: String in edge_ids:
		_edge_remaining_capacity[edge_id] = maxf(
			0.0, float(_edge_remaining_capacity.get(edge_id, 0.0)) - units
		)


func _settle_government_procurement(total_hour: int) -> Dictionary:
	var purchased := 0.0
	var released := 0.0
	for rule: Dictionary in _procurement_rules:
		var country_id := str(rule.get("country_id", ""))
		var commodity_id := str(rule.get("commodity_id", ""))
		var stockpile := government_stockpiles.get(country_id, {}) as Dictionary
		var current := float(stockpile.get(commodity_id, 0.0))
		var target := float(rule.get("target_units", 0.0))
		if current < target:
			var need := minf(target - current, float(rule.get("daily_purchase_limit_units", 0.0)))
			var source := _largest_surplus_region(country_id, commodity_id)
			if not source.is_empty():
				var units := minf(need, _surplus_units(source, commodity_id))
				var market_id := str((region_accounts[source] as Dictionary).get("market_id", ""))
				var treasury_id := str((country_finance[country_id] as Dictionary).get("treasury_id", ""))
				var value := int(round(units * float(_commodity_market.market_price(source, commodity_id))))
				if units > 0.0001 and _safe_transfer(
					"integration:procurement:%d:%s:%s" % [total_hour, country_id, commodity_id],
					total_hour,
					treasury_id,
					market_id,
					value,
					"government_procurement",
					"政府战略物资采购"
				):
					_remove_region_inventory(source, commodity_id, units)
					stockpile[commodity_id] = current + units
					purchased += units
		var shortage_region := _largest_shortage_region(country_id, commodity_id)
		if not shortage_region.is_empty():
			var shortage := _metric_value(shortage_region, "unmet", commodity_id)
			var demand := maxf(1.0, _metric_value(shortage_region, "demand", commodity_id))
			var shortage_bp := int(round(clampf(shortage / demand, 0.0, 1.0) * BASIS_POINTS))
			var available := float(stockpile.get(commodity_id, 0.0))
			if shortage_bp >= int(_policies.get("strategic_release_shortage_bp", 3500)) and available > 0.0:
				var units := minf(available, shortage)
				_add_region_inventory(shortage_region, commodity_id, units)
				stockpile[commodity_id] = available - units
				_record_market_metric(shortage_region, "strategic_release", commodity_id, units)
				released += units
		government_stockpiles[country_id] = stockpile
	return {"purchased_units": purchased, "released_units": released}


func _adjust_exchange_rates() -> void:
	var max_change := int(_policies.get("maximum_daily_fx_change_bp", 120))
	var floor_bp := int(_policies.get("gold_reserve_floor_bp", 1200))
	for raw_country_id: Variant in country_finance:
		var country_id := str(raw_country_id)
		var finance := country_finance[country_id] as Dictionary
		var opening := maxf(1.0, float(finance.get("opening_gold_reserve_grams", 1.0)))
		var reserve := maxf(0.0, float(finance.get("gold_reserve_grams", 0.0)))
		var reserve_bp := int(round(reserve * BASIS_POINTS / opening))
		var rate := int(finance.get("exchange_rate_bp", BASIS_POINTS))
		var change := 0
		if reserve_bp < floor_bp:
			change = max_change
		elif reserve_bp < 7000:
			change = max_change / 2
		elif reserve_bp > 12000:
			change = -max_change / 3
		finance["exchange_rate_bp"] = clampi(rate + change, 6000, 18000)
		finance["reserve_ratio_bp"] = reserve_bp
		country_finance[country_id] = finance


func _sync_labor_market() -> void:
	var enterprise_workers: Dictionary = {}
	var enterprise_capacity: Dictionary = {}
	for raw_site_id: Variant in _commodity_market.production_sites:
		var site_id := str(raw_site_id)
		var site := _commodity_market.production_sites[site_id] as Dictionary
		var enterprise_id := str(site_enterprise.get(site_id, ""))
		var capacity := int(site.get("workers_capacity", 0))
		var active := int(round(float(capacity) * float(site.get("last_operating_bp", 0)) / float(BASIS_POINTS)))
		enterprise_workers[enterprise_id] = int(enterprise_workers.get(enterprise_id, 0)) + active
		enterprise_capacity[enterprise_id] = int(enterprise_capacity.get(enterprise_id, 0)) + capacity
	for raw_enterprise_id: Variant in enterprise_workers:
		var enterprise_id := str(raw_enterprise_id)
		var state := _enterprise.enterprises.get(enterprise_id, {}) as Dictionary
		if state.is_empty():
			continue
		var active := int(enterprise_workers[enterprise_id])
		var capacity := int(enterprise_capacity.get(enterprise_id, active))
		state["background_employee_count"] = active
		state["commodity_worker_capacity"] = capacity
		state["commodity_vacancies"] = maxi(0, capacity - active)
		_enterprise.enterprises[enterprise_id] = state
	for raw_job_id: Variant in _labor.jobs:
		var job_id := str(raw_job_id)
		var job := _labor.jobs[job_id] as Dictionary
		var employer_id := str(job.get("employer_id", ""))
		if not enterprise_capacity.has(employer_id):
			continue
		var capacity := int(enterprise_capacity[employer_id])
		var active := int(enterprise_workers.get(employer_id, 0))
		var vacancies := maxi(0, capacity - active)
		job["openings"] = vacancies
		job["labor_demand_index"] = 0 if capacity <= 0 else clampi(vacancies * 100 / capacity, 0, 100)
		job["active"] = str((_enterprise.enterprises[employer_id] as Dictionary).get("status", "")) in AlphaEnterpriseService.ACTIVE_ENTERPRISE_STATUSES
		_labor.jobs[job_id] = job


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


func _surplus_units(region_id: String, commodity_id: String) -> float:
	var inventory := _commodity_market.inventory_units(region_id, commodity_id)
	return maxf(0.0, inventory - _target_stock_units(region_id, commodity_id) * 0.85)


func _target_stock_units(region_id: String, commodity_id: String) -> float:
	var commodity := _commodity_market.commodities.get(commodity_id, {}) as Dictionary
	var target_days := int(commodity.get("target_stock_days", 10))
	var demand := _commodity_market.daily_household_demand(region_id, commodity_id)
	var industrial := float(
		(_industrial_need_capacity.get(region_id, {}) as Dictionary).get(commodity_id, 0.0)
	)
	return maxf(0.0, (demand + industrial) * float(target_days))


func _producer_for(region_id: String, commodity_id: String) -> String:
	var producer := str(
		(_producer_by_region_commodity.get(region_id, {}) as Dictionary).get(commodity_id, "")
	)
	if not producer.is_empty():
		return producer
	var candidates := (_document.get("enterprise_assignment", {}) as Dictionary).get("region_enterprises", {}) as Dictionary
	var ids := DataRecordUtils.to_string_array(candidates.get(region_id, []))
	return ids[0] if not ids.is_empty() else ""


func _largest_surplus_region(country_id: String, commodity_id: String) -> String:
	var selected := ""
	var largest := 0.0
	for raw_region_id: Variant in region_accounts:
		var region_id := str(raw_region_id)
		if str((region_accounts[region_id] as Dictionary).get("country_id", "")) != country_id:
			continue
		var surplus := _surplus_units(region_id, commodity_id)
		if surplus > largest:
			largest = surplus
			selected = region_id
	return selected


func _largest_shortage_region(country_id: String, commodity_id: String) -> String:
	var selected := ""
	var largest := 0.0
	for raw_region_id: Variant in region_accounts:
		var region_id := str(raw_region_id)
		if str((region_accounts[region_id] as Dictionary).get("country_id", "")) != country_id:
			continue
		var shortage := _metric_value(region_id, "unmet", commodity_id)
		if shortage > largest:
			largest = shortage
			selected = region_id
	return selected


func _metric_value(region_id: String, metric_name: String, commodity_id: String) -> float:
	var state := _commodity_market.region_states.get(region_id, {}) as Dictionary
	var metrics := state.get("daily_metrics", {}) as Dictionary
	return float((metrics.get(metric_name, {}) as Dictionary).get(commodity_id, 0.0))


func _record_market_metric(
	region_id: String, metric_name: String, commodity_id: String, units: float
) -> void:
	var state := _commodity_market.region_states[region_id] as Dictionary
	var metrics := state.get("daily_metrics", {}) as Dictionary
	var values := metrics.get(metric_name, {}) as Dictionary
	values[commodity_id] = float(values.get(commodity_id, 0.0)) + units
	metrics[metric_name] = values
	state["daily_metrics"] = metrics
	_commodity_market.region_states[region_id] = state


func _add_region_inventory(region_id: String, commodity_id: String, units: float) -> void:
	_commodity_market.set_inventory(
		region_id,
		commodity_id,
		_commodity_market.inventory_units(region_id, commodity_id) + maxf(0.0, units)
	)


func _remove_region_inventory(region_id: String, commodity_id: String, units: float) -> void:
	_commodity_market.set_inventory(
		region_id,
		commodity_id,
		maxf(0.0, _commodity_market.inventory_units(region_id, commodity_id) - maxf(0.0, units))
	)


func _limit_by_gold_reserve(
	importer_country: String,
	exporter_country: String,
	origin_region: String,
	commodity_id: String,
	units: float
) -> float:
	if importer_country == exporter_country:
		return units
	var finance := country_finance[importer_country] as Dictionary
	var reserve := float(finance.get("gold_reserve_grams", 0.0))
	var opening := maxf(1.0, float(finance.get("opening_gold_reserve_grams", 1.0)))
	var floor := opening * float(_policies.get("gold_reserve_floor_bp", 1200)) / float(BASIS_POINTS)
	var available_gold := maxf(0.0, reserve - floor)
	var parity := maxf(1.0, float(finance.get("parity_centimes_per_gram", 1.0)))
	var exchange_rate := maxf(1.0, float(finance.get("exchange_rate_bp", BASIS_POINTS)))
	var unit_value := float(_commodity_market.market_price(origin_region, commodity_id)) * exchange_rate / float(BASIS_POINTS)
	var maximum_units := available_gold * parity / maxf(1.0, unit_value)
	return minf(units, maximum_units)


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


func _refund_escrow(shipment_id: String, buyer_id: String, amount: int, total_hour: int) -> void:
	if amount <= 0:
		return
	_safe_transfer(
		"integration:shipment:refund:%s" % shipment_id,
		total_hour,
		ESCROW_ID,
		buyer_id,
		mini(amount, _economy.ledger.owner_cash(ESCROW_ID)),
		"commodity_trade_refund",
		"未交付货物托管退款"
	)


func _post_owner_entries(
	key: String,
	total_hour: int,
	category: String,
	description: String,
	owner_entries: Array[Dictionary]
) -> bool:
	var by_account: Dictionary = {}
	for owner_entry: Dictionary in owner_entries:
		var delta := int(owner_entry.get("delta_centimes", 0))
		if delta == 0:
			continue
		var account_id := _economy.ledger.cash_account_id(str(owner_entry.get("owner_id", "")))
		if account_id.is_empty():
			return false
		by_account[account_id] = int(by_account.get(account_id, 0)) + delta
	var entries: Array[Dictionary] = []
	for raw_account_id: Variant in by_account:
		var account_id := str(raw_account_id)
		var delta := int(by_account[account_id])
		if delta != 0:
			entries.append({"account_id": account_id, "delta_centimes": delta})
	if entries.is_empty():
		return true
	if entries.size() < 2:
		return false
	return bool(_economy.ledger.post(
		key,
		total_hour,
		category,
		"fact:%s" % key,
		entries,
		description
	).get("success", false))


func _safe_transfer(
	key: String,
	total_hour: int,
	from_id: String,
	to_id: String,
	amount: int,
	category: String,
	description: String
) -> bool:
	if amount <= 0:
		return true
	var result := _economy.ledger.transfer(
		key,
		total_hour,
		from_id,
		to_id,
		amount,
		category,
		"fact:%s" % key,
		description
	)
	return bool(result.get("success", false))


func _ensure_entity(
	entity_id: String,
	entity_type: String,
	opening_cash: int,
	profile: Dictionary
) -> bool:
	if _economy.entity_profiles.has(entity_id):
		return true
	return bool(_economy.register_entity(
		entity_id, entity_type, opening_cash, profile
	).get("success", false))


func _trade_key(exporter_country: String, importer_country: String) -> String:
	return "%s>%s" % [exporter_country, importer_country]


func _gold_reserve_summary() -> Dictionary:
	var result: Dictionary = {}
	for raw_country_id: Variant in country_finance:
		var country_id := str(raw_country_id)
		var finance := country_finance[country_id] as Dictionary
		result[country_id] = {
			"gold_reserve_grams": float(finance.get("gold_reserve_grams", 0.0)),
			"exchange_rate_bp": int(finance.get("exchange_rate_bp", BASIS_POINTS)),
			"trade_balance_centimes": int(finance.get("cumulative_trade_balance_centimes", 0)),
		}
	return result


func _trim_history() -> void:
	var shipment_limit := int(_policies.get("shipment_history_limit", HISTORY_LIMIT_FALLBACK))
	var decision_limit := int(_policies.get("decision_history_limit", 256))
	while shipment_history.size() > shipment_limit:
		shipment_history.pop_front()
	while decision_history.size() > decision_limit:
		decision_history.pop_front()


func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "data": data}


func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message}


func _fail_initialize(message: String) -> bool:
	initialization_error = message
	return false
