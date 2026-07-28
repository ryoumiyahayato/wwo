class_name AlphaEconomicClosureService
extends RefCounted
## Connects physical commodity flows to cash, enterprise, labor and routed logistics.

const HOUSEHOLD_PREFIX := "aggregate:households:"
const ENTERPRISE_PREFIX := "aggregate:site:"
const CARRIER_PREFIX := "aggregate:carrier:"
const TREASURY_PREFIX := "aggregate:treasury:"
const HISTORY_LIMIT := 128
const BASIS_POINTS := 10000

var economy: AlphaEconomyService
var commodity_market: AlphaCommodityMarketService
var enterprise_service: AlphaEnterpriseService
var labor_service: AlphaLaborService
var route_neighbors: Dictionary = {}
var route_capacity_units: Dictionary = {}
var site_finance: Dictionary = {}
var in_transit: Array[Dictionary] = []
var bilateral_trade: Array[Dictionary] = []
var daily_history: Array[Dictionary] = []
var initialization_error := ""
var _last_day_index := -1


func configure(
	p_economy: AlphaEconomyService,
	p_market: AlphaCommodityMarketService,
	p_enterprise: AlphaEnterpriseService,
	p_labor: AlphaLaborService
) -> bool:
	economy = p_economy
	commodity_market = p_market
	enterprise_service = p_enterprise
	labor_service = p_labor
	route_neighbors.clear()
	route_capacity_units.clear()
	site_finance.clear()
	in_transit.clear()
	bilateral_trade.clear()
	daily_history.clear()
	_last_day_index = -1
	if economy == null or commodity_market == null:
		return _fail_initialize("经济服务或商品市场缺失")
	_register_aggregate_accounts()
	_build_sparse_route_network()
	_initialize_site_finance()
	return validate_integrity().get("success", false)


func settle_day(total_hour: int) -> Dictionary:
	var day_index := total_hour / 24
	if day_index <= _last_day_index:
		return _ok({"duplicate": true, "day_index": day_index})
	_deliver_due_shipments(day_index)
	var household_spending := _settle_household_consumption(total_hour, day_index)
	var enterprise_result := _settle_enterprises(total_hour, day_index)
	var logistics_result := _plan_sparse_logistics(day_index)
	var trade_result := _record_bilateral_trade(day_index)
	_last_day_index = day_index
	var summary := {
		"day_index": day_index,
		"total_hour": total_hour,
		"household_spending_centimes": household_spending,
		"wages_centimes": int(enterprise_result.get("wages_centimes", 0)),
		"maintenance_centimes": int(enterprise_result.get("maintenance_centimes", 0)),
		"enterprise_revenue_centimes": int(enterprise_result.get("revenue_centimes", 0)),
		"new_shipments": int(logistics_result.get("new_shipments", 0)),
		"in_transit_count": in_transit.size(),
		"bilateral_trade_count": int(trade_result.get("trade_count", 0)),
	}
	daily_history.append(summary.duplicate(true))
	while daily_history.size() > HISTORY_LIMIT:
		daily_history.pop_front()
	return _ok(summary)


func _register_aggregate_accounts() -> void:
	for region_id: String in commodity_market.region_states.keys():
		_register_if_missing(HOUSEHOLD_PREFIX + region_id, "household_aggregate", 5_000_000, region_id)
		_register_if_missing(CARRIER_PREFIX + region_id, "carrier_aggregate", 500_000, region_id)
		_register_if_missing(TREASURY_PREFIX + region_id, "regional_treasury", 1_000_000, region_id)
	for site_id: String in commodity_market.production_sites.keys():
		var site := commodity_market.production_sites[site_id] as Dictionary
		_register_if_missing(ENTERPRISE_PREFIX + site_id, "production_enterprise", 750_000, str(site.get("region_id", "")))


func _register_if_missing(entity_id: String, entity_type: String, opening_cash: int, region_id: String) -> void:
	if economy.entity_profiles.has(entity_id):
		return
	economy.register_entity(entity_id, entity_type, opening_cash, {
		"region_id": region_id,
		"income_monthly_centimes": 0,
		"reputation": 50,
	})


func _build_sparse_route_network() -> void:
	var ids: Array[String] = []
	for raw_id: Variant in commodity_market.region_states.keys():
		ids.append(str(raw_id))
	ids.sort()
	for region_id: String in ids:
		route_neighbors[region_id] = []
	if ids.size() < 2:
		return
	# Deterministic sparse ring plus one cross-link. Complexity is O(E * goods), E≈2R.
	for index: int in range(ids.size()):
		_connect(ids[index], ids[(index + 1) % ids.size()], 12000)
		if ids.size() > 3:
			_connect(ids[index], ids[(index + ids.size() / 2) % ids.size()], 6000)


func _connect(a: String, b: String, capacity: int) -> void:
	if a == b:
		return
	var a_neighbors := route_neighbors.get(a, []) as Array
	if b not in a_neighbors:
		a_neighbors.append(b)
		route_neighbors[a] = a_neighbors
	var b_neighbors := route_neighbors.get(b, []) as Array
	if a not in b_neighbors:
		b_neighbors.append(a)
		route_neighbors[b] = b_neighbors
	route_capacity_units[_route_key(a, b)] = capacity


func _initialize_site_finance() -> void:
	for site_id: String in commodity_market.production_sites.keys():
		var site := commodity_market.production_sites[site_id] as Dictionary
		site_finance[site_id] = {
			"owner_id": ENTERPRISE_PREFIX + site_id,
			"region_id": str(site.get("region_id", "")),
			"book_value_centimes": maxi(10000, int(float(site.get("capacity_batches_per_day", 1.0)) * 5000.0)),
			"maintenance_rate_bp": 35,
			"wage_per_worker_centimes": 8,
			"arrears_centimes": 0,
			"insolvent_days": 0,
		}


func _settle_household_consumption(total_hour: int, day_index: int) -> int:
	var total_spending := 0
	for region_id: String in commodity_market.region_states.keys():
		var state := commodity_market.region_states[region_id] as Dictionary
		var metrics := state.get("daily_metrics", {}) as Dictionary
		var goods_metrics := metrics.get("commodities", {}) as Dictionary
		var household_id := HOUSEHOLD_PREFIX + region_id
		var producers := _site_ids_for_region(region_id)
		if producers.is_empty():
			continue
		var producer_index := 0
		for commodity_id: String in goods_metrics.keys():
			var row := goods_metrics[commodity_id] as Dictionary
			var consumed := float(row.get("household_consumed_units", 0.0))
			if consumed <= 0.0:
				continue
			var price := commodity_market.market_price(region_id, commodity_id)
			var amount := maxi(1, int(round(consumed * float(price))))
			var seller_id := ENTERPRISE_PREFIX + producers[producer_index % producers.size()]
			producer_index += 1
			var available := economy.ledger.owner_cash(household_id)
			amount = mini(amount, available)
			if amount <= 0:
				continue
			var result := economy.ledger.transfer(
				"closure:household:%d:%s:%s" % [day_index, region_id, commodity_id],
				total_hour, household_id, seller_id, amount,
				"household_consumption", "fact:commodity_consumption:%d:%s:%s" % [day_index, region_id, commodity_id],
				"居民购买%s" % commodity_id
			)
			if bool(result.get("success", false)):
				total_spending += amount
	return total_spending


func _settle_enterprises(total_hour: int, day_index: int) -> Dictionary:
	var wages := 0
	var maintenance := 0
	var revenue := 0
	for site_id: String in site_finance.keys():
		var finance := site_finance[site_id] as Dictionary
		var site := commodity_market.production_sites.get(site_id, {}) as Dictionary
		var owner_id := str(finance.get("owner_id", ""))
		var region_id := str(finance.get("region_id", ""))
		var workers := maxi(0, int(site.get("last_workers", site.get("last_employed", 0))))
		if workers == 0:
			workers = maxi(1, int(float(site.get("last_batches", 0.0)) * 12.0))
		var wage_amount := workers * int(finance.get("wage_per_worker_centimes", 8))
		var upkeep := int(finance.get("book_value_centimes", 0)) * int(finance.get("maintenance_rate_bp", 35)) / BASIS_POINTS
		var cash := economy.ledger.owner_cash(owner_id)
		var payable_wage := mini(wage_amount, cash)
		if payable_wage > 0 and _transfer(total_hour, day_index, site_id, owner_id, HOUSEHOLD_PREFIX + region_id, payable_wage, "wages"):
			wages += payable_wage
		cash = economy.ledger.owner_cash(owner_id)
		var payable_upkeep := mini(upkeep, cash)
		if payable_upkeep > 0 and _transfer(total_hour, day_index, site_id, owner_id, CARRIER_PREFIX + region_id, payable_upkeep, "maintenance"):
			maintenance += payable_upkeep
		var arrears := wage_amount + upkeep - payable_wage - payable_upkeep
		finance["arrears_centimes"] = int(finance.get("arrears_centimes", 0)) + maxi(0, arrears)
		finance["insolvent_days"] = int(finance.get("insolvent_days", 0)) + (1 if arrears > 0 else -1)
		finance["insolvent_days"] = maxi(0, int(finance["insolvent_days"]))
		if int(finance["insolvent_days"]) >= 7:
			site["operating_target_bp"] = maxi(1500, int(site.get("operating_target_bp", BASIS_POINTS)) - 750)
		commodity_market.production_sites[site_id] = site
		site_finance[site_id] = finance
		revenue += maxi(0, economy.ledger.owner_cash(owner_id))
	return {"wages_centimes": wages, "maintenance_centimes": maintenance, "revenue_centimes": revenue}


func _transfer(total_hour: int, day_index: int, site_id: String, from_id: String, to_id: String, amount: int, category: String) -> bool:
	var result := economy.ledger.transfer(
		"closure:%s:%d:%s" % [category, day_index, site_id], total_hour,
		from_id, to_id, amount, category,
		"fact:%s:%d:%s" % [category, day_index, site_id], category
	)
	return bool(result.get("success", false))


func _plan_sparse_logistics(day_index: int) -> Dictionary:
	var created := 0
	for origin_id: String in route_neighbors.keys():
		var origin := commodity_market.region_states[origin_id] as Dictionary
		var inventory := origin.get("inventory", {}) as Dictionary
		for destination_id: String in route_neighbors[origin_id] as Array:
			if origin_id > destination_id:
				continue
			var destination := commodity_market.region_states[destination_id] as Dictionary
			var destination_inventory := destination.get("inventory", {}) as Dictionary
			var capacity := int(route_capacity_units.get(_route_key(origin_id, destination_id), 0))
			var remaining := float(capacity)
			for commodity_id: String in commodity_market.commodities.keys():
				if remaining <= 0.0:
					break
				var origin_stock := float(inventory.get(commodity_id, 0.0))
				var destination_stock := float(destination_inventory.get(commodity_id, 0.0))
				var difference := origin_stock - destination_stock
				if absf(difference) < 20.0:
					continue
				var amount := minf(absf(difference) * 0.05, remaining)
				if amount <= 0.0:
					continue
				in_transit.append({
					"shipment_id": "shipment:%d:%d" % [day_index, in_transit.size()],
					"origin_id": origin_id if difference > 0.0 else destination_id,
					"destination_id": destination_id if difference > 0.0 else origin_id,
					"commodity_id": commodity_id,
					"units": amount,
					"depart_day": day_index,
					"arrival_day": day_index + 1,
					"loss_bp": 75,
				})
				remaining -= amount
				created += 1
	return {"new_shipments": created}


func _deliver_due_shipments(day_index: int) -> void:
	var remaining: Array[Dictionary] = []
	for shipment: Dictionary in in_transit:
		if int(shipment.get("arrival_day", 0)) > day_index:
			remaining.append(shipment)
			continue
		var destination_id := str(shipment.get("destination_id", ""))
		var commodity_id := str(shipment.get("commodity_id", ""))
		var delivered := float(shipment.get("units", 0.0)) * float(BASIS_POINTS - int(shipment.get("loss_bp", 0))) / BASIS_POINTS
		commodity_market.set_inventory(destination_id, commodity_id, commodity_market.inventory_units(destination_id, commodity_id) + delivered)
	in_transit = remaining


func _record_bilateral_trade(day_index: int) -> Dictionary:
	var count := 0
	for region_id: String in commodity_market.region_states.keys():
		var state := commodity_market.region_states[region_id] as Dictionary
		var totals := (state.get("daily_metrics", {}) as Dictionary).get("totals", {}) as Dictionary
		var imports := float(totals.get("international_import_units", 0.0))
		var exports := float(totals.get("international_export_units", 0.0))
		if imports <= 0.0 and exports <= 0.0:
			continue
		bilateral_trade.append({
			"trade_id": "trade:%d:%s" % [day_index, region_id],
			"day_index": day_index,
			"importer_region_id": region_id if imports > 0.0 else "international:clearing",
			"exporter_region_id": region_id if exports > 0.0 else "international:clearing",
			"import_units": imports,
			"export_units": exports,
			"tariff_bp": 250,
			"insured": true,
		})
		count += 1
	while bilateral_trade.size() > HISTORY_LIMIT * 4:
		bilateral_trade.pop_front()
	return {"trade_count": count}


func _site_ids_for_region(region_id: String) -> Array[String]:
	var result: Array[String] = []
	for site_id: String in commodity_market.production_sites.keys():
		if str((commodity_market.production_sites[site_id] as Dictionary).get("region_id", "")) == region_id:
			result.append(site_id)
	result.sort()
	return result


func validate_integrity() -> Dictionary:
	if economy == null or commodity_market == null:
		return _fail("service_missing", "经济闭环依赖缺失")
	for region_id: String in commodity_market.region_states.keys():
		if not route_neighbors.has(region_id):
			return _fail("route_region_missing", "地区运输索引缺失")
		for owner_id: String in [HOUSEHOLD_PREFIX + region_id, CARRIER_PREFIX + region_id, TREASURY_PREFIX + region_id]:
			if not economy.entity_profiles.has(owner_id):
				return _fail("aggregate_account_missing", "聚合经济账户缺失")
	for site_id: String in commodity_market.production_sites.keys():
		if not site_finance.has(site_id) or not economy.entity_profiles.has(ENTERPRISE_PREFIX + site_id):
			return _fail("site_finance_missing", "生产设施未绑定企业资产账户")
	return _ok({
		"route_count": route_capacity_units.size(),
		"site_finance_count": site_finance.size(),
		"region_count": route_neighbors.size(),
	})


func get_persistent_state() -> Dictionary:
	return {
		"route_neighbors": route_neighbors.duplicate(true),
		"route_capacity_units": route_capacity_units.duplicate(true),
		"site_finance": site_finance.duplicate(true),
		"in_transit": in_transit.duplicate(true),
		"bilateral_trade": bilateral_trade.duplicate(true),
		"daily_history": daily_history.duplicate(true),
		"last_day_index": _last_day_index,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if not state.get("route_neighbors", {}) is Dictionary or not state.get("site_finance", {}) is Dictionary:
		return false
	route_neighbors = (state.get("route_neighbors", {}) as Dictionary).duplicate(true)
	route_capacity_units = (state.get("route_capacity_units", {}) as Dictionary).duplicate(true)
	site_finance = (state.get("site_finance", {}) as Dictionary).duplicate(true)
	in_transit = (state.get("in_transit", []) as Array).duplicate(true)
	bilateral_trade = (state.get("bilateral_trade", []) as Array).duplicate(true)
	daily_history = (state.get("daily_history", []) as Array).duplicate(true)
	_last_day_index = int(state.get("last_day_index", -1))
	return bool(validate_integrity().get("success", false))


func _route_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _fail_initialize(message: String) -> bool:
	initialization_error = message
	return false


func _ok(data: Dictionary) -> Dictionary:
	return {"success": true, "code": "ok", "data": data}


func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
