class_name FormalWorldEconomyService
extends RefCounted
## Country-level formal-world economy driven by the source-bounded 1900 dataset.
## Records that are not fully verified remain visible as bounded estimates and
## carry their confidence; they are never returned by formal_verified_countries().

const HOURS_PER_DAY: int = 24
const BASIS_POINTS: int = 10000
const HISTORY_LIMIT: int = 366
const MAX_SHIPMENTS_PER_DAY: int = 96
const MAX_SUPPLIERS_PER_SHORTAGE: int = 4

var country_states: Dictionary = {}
var routes: Array[Dictionary] = []
var shipments: Array[Dictionary] = []
var history: Array[Dictionary] = []
var total_hour: int = 0
var initialization_error: String = ""

var _historical := AlphaHistoricalWorldEconomyData.new()
var _commodity_config := AlphaConfig.new()
var _commodities: Dictionary = {}
var _routes_by_country: Dictionary = {}
var _next_shipment_sequence: int = 1
var _last_day_index: int = -1


func configure() -> bool:
	country_states.clear()
	routes.clear()
	shipments.clear()
	history.clear()
	_routes_by_country.clear()
	_commodities.clear()
	total_hour = 0
	_last_day_index = -1
	_next_shipment_sequence = 1
	initialization_error = ""
	if not _historical.configure():
		return _fail(_historical.initialization_error)
	if _commodity_config.load_all() != OK:
		return _fail("正式世界商品目录无法加载：%s" % "; ".join(_commodity_config.errors))
	for raw_commodity: Variant in _commodity_config.commodity_records():
		if not raw_commodity is Dictionary:
			continue
		var commodity := (raw_commodity as Dictionary).duplicate(true)
		var commodity_id := str(commodity.get("commodity_id", ""))
		if not commodity_id.is_empty():
			_commodities[commodity_id] = commodity
	for record: Dictionary in _historical.simulation_countries():
		_initialize_country(record)
	_build_routes()
	if country_states.size() != 50:
		return _fail("正式世界经济必须加载50个历史政治实体，当前为%d" % country_states.size())
	if _commodities.is_empty():
		return _fail("正式世界商品目录为空")
	return true


func advance_hours(hours: int) -> Dictionary:
	if hours <= 0:
		return world_summary()
	var target_hour := total_hour + hours
	while total_hour < target_hour:
		total_hour += 1
		if total_hour % HOURS_PER_DAY == 0:
			_settle_day(total_hour)
	return world_summary()


func world_summary() -> Dictionary:
	var population := 0
	var demand := 0.0
	var consumed := 0.0
	var unmet := 0.0
	var verified := 0
	var bounded := 0
	for raw_state: Variant in country_states.values():
		var state := raw_state as Dictionary
		population += int(state.get("population", 0))
		var totals := state.get("daily_totals", {}) as Dictionary
		demand += float(totals.get("demand_units", 0.0))
		consumed += float(totals.get("consumed_units", 0.0))
		unmet += float(totals.get("unmet_units", 0.0))
		if str(state.get("admission_status", "")) == "verified":
			verified += 1
		else:
			bounded += 1
	return {
		"total_hour": total_hour,
		"country_count": country_states.size(),
		"population": population,
		"commodity_count": _commodities.size(),
		"active_shipments": shipments.size(),
		"route_count": routes.size(),
		"verified_country_count": verified,
		"bounded_country_count": bounded,
		"demand_units": demand,
		"consumed_units": consumed,
		"unmet_units": unmet,
		"fulfillment_bp": BASIS_POINTS if demand <= 0.0 else int(round(clampf(consumed / demand, 0.0, 1.0) * BASIS_POINTS)),
		"top_shortages": _top_world_shortages(8),
	}


func country_summary(entity_id: String) -> Dictionary:
	var state := country_states.get(entity_id, {}) as Dictionary
	if state.is_empty():
		return {}
	var result := state.duplicate(true)
	result["top_shortages"] = _top_country_shortages(state, 8)
	result["active_shipments"] = _shipment_count_for(entity_id)
	return result


func formal_verified_countries() -> Array[Dictionary]:
	return _historical.formal_countries()


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": "formal_world_economy_state_v1",
		"total_hour": total_hour,
		"country_states": country_states.duplicate(true),
		"shipments": shipments.duplicate(true),
		"history": history.duplicate(true),
		"next_shipment_sequence": _next_shipment_sequence,
		"last_day_index": _last_day_index,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		str(state.get("schema_id", "")) != "formal_world_economy_state_v1"
		or not state.get("country_states", {}) is Dictionary
		or not state.get("shipments", []) is Array
		or not state.get("history", []) is Array
	):
		return false
	var restored := (state.get("country_states", {}) as Dictionary).duplicate(true)
	if restored.size() != country_states.size():
		return false
	for raw_id: Variant in restored:
		if not country_states.has(str(raw_id)):
			return false
	country_states = restored
	shipments = DataRecordUtils.to_dictionary_array(state.get("shipments", []))
	history = DataRecordUtils.to_dictionary_array(state.get("history", []))
	total_hour = int(state.get("total_hour", 0))
	_next_shipment_sequence = maxi(1, int(state.get("next_shipment_sequence", 1)))
	_last_day_index = int(state.get("last_day_index", total_hour / HOURS_PER_DAY))
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	return _validate_state()


func _initialize_country(record: Dictionary) -> void:
	var entity_id := str(record.get("entity_id", ""))
	if entity_id.is_empty():
		return
	var population_record := record.get("population", {}) as Dictionary
	var income_record := record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary
	var urban_record := record.get("urban_population_share_bp", {}) as Dictionary
	var production := record.get("production", {}) as Dictionary
	var infrastructure := record.get("infrastructure", {}) as Dictionary
	var inventory: Dictionary = {}
	var prices: Dictionary = {}
	var daily_metrics: Dictionary = {}
	for raw_id: Variant in _commodities:
		var commodity_id := str(raw_id)
		var commodity := _commodities[commodity_id] as Dictionary
		var base_price := maxi(1, int(commodity.get("base_price_centimes", 1)))
		var demand := _daily_demand_for(
			int(population_record.get("value", 0)),
			int(income_record.get("value", 0)),
			commodity
		)
		var capacity_factor := _production_factor(record, commodity)
		var opening_days := 8.0 + 22.0 * capacity_factor
		inventory[commodity_id] = maxf(demand * opening_days, capacity_factor * 40.0)
		prices[commodity_id] = base_price
		daily_metrics[commodity_id] = {
			"demand": 0.0,
			"produced": 0.0,
			"consumed": 0.0,
			"unmet": 0.0,
			"imports": 0.0,
			"exports": 0.0,
		}
	var coverage := record.get("coverage", {}) as Dictionary
	country_states[entity_id] = {
		"entity_id": entity_id,
		"rank": int(record.get("rank", 0)),
		"primary_iso3": str(record.get("primary_iso3", "")),
		"population": int(population_record.get("value", 0)),
		"population_bounds": population_record.duplicate(true),
		"income_per_capita": int(income_record.get("value", 0)),
		"income_bounds": income_record.duplicate(true),
		"urban_share_bp": int(urban_record.get("value", 0)),
		"production": production.duplicate(true),
		"infrastructure": infrastructure.duplicate(true),
		"overall_confidence_bp": int(record.get("overall_confidence_bp", 0)),
		"admission_status": str(coverage.get("status", "bounded_estimate")),
		"verified_dimensions": (coverage.get("verified_dimensions", []) as Array).duplicate(),
		"inventory": inventory,
		"prices": prices,
		"daily_metrics": daily_metrics,
		"daily_totals": {},
		"gold_reserve_units": _opening_gold_units(record),
		"trade_balance_centimes": 0,
		"tariff_revenue_centimes": 0,
		"last_settlement_hour": 0,
	}


func _build_routes() -> void:
	for record: Dictionary in _historical.maritime_corridors:
		_add_route({
			"route_id": str(record.get("corridor_id", "")),
			"from": str(record.get("origin_entity_id", "")),
			"to": str(record.get("destination_entity_id", "")),
			"duration_hours": maxi(HOURS_PER_DAY, int(record.get("duration_days", 1)) * HOURS_PER_DAY),
			"capacity_units_per_day": maxf(10.0, float(record.get("capacity_index", 1)) * 18.0),
			"mode": str(record.get("mode", "steamship")),
			"confidence_bp": int(record.get("confidence_bp", 0)),
		})
	for record: Dictionary in _historical.river_corridors:
		var ids := DataRecordUtils.to_string_array(record.get("entity_ids", []))
		for index: int in range(ids.size() - 1):
			_add_route({
				"route_id": "%s:%d" % [str(record.get("corridor_id", "river")), index],
				"from": ids[index],
				"to": ids[index + 1],
				"duration_hours": 3 * HOURS_PER_DAY,
				"capacity_units_per_day": maxf(8.0, float(record.get("capacity_index", 1)) * 12.0),
				"mode": "river",
				"confidence_bp": 5000,
			})


func _add_route(route: Dictionary) -> void:
	var origin := str(route.get("from", ""))
	var destination := str(route.get("to", ""))
	if (
		origin.is_empty()
		or destination.is_empty()
		or origin == destination
		or not country_states.has(origin)
		or not country_states.has(destination)
	):
		return
	routes.append(route.duplicate(true))
	for country_id: String in [origin, destination]:
		var indexes := _routes_by_country.get(country_id, []) as Array
		indexes.append(routes.size() - 1)
		_routes_by_country[country_id] = indexes


func _settle_day(settlement_hour: int) -> void:
	var day_index := settlement_hour / HOURS_PER_DAY
	if day_index <= _last_day_index:
		return
	_deliver_shipments(settlement_hour)
	for raw_id: Variant in country_states:
		_settle_country(str(raw_id), settlement_hour)
	_schedule_shortage_shipments(settlement_hour)
	_last_day_index = day_index
	var summary := world_summary()
	summary["day_index"] = day_index
	history.append(summary)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()


func _settle_country(entity_id: String, settlement_hour: int) -> void:
	var state := country_states[entity_id] as Dictionary
	var inventory := state.get("inventory", {}) as Dictionary
	var prices := state.get("prices", {}) as Dictionary
	var metrics := state.get("daily_metrics", {}) as Dictionary
	var demand_total := 0.0
	var produced_total := 0.0
	var consumed_total := 0.0
	var unmet_total := 0.0
	for raw_id: Variant in _commodities:
		var commodity_id := str(raw_id)
		var commodity := _commodities[commodity_id] as Dictionary
		var row := metrics.get(commodity_id, {}) as Dictionary
		row["imports"] = 0.0
		row["exports"] = 0.0
		var demand := _daily_demand_for(
			int(state.get("population", 0)),
			int(state.get("income_per_capita", 0)),
			commodity
		)
		var production_factor := _production_factor(state, commodity)
		var produced := maxf(0.0, demand * production_factor)
		inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + produced
		var consumed := minf(demand, float(inventory.get(commodity_id, 0.0)))
		inventory[commodity_id] = maxf(0.0, float(inventory.get(commodity_id, 0.0)) - consumed)
		var unmet := maxf(0.0, demand - consumed)
		row["demand"] = demand
		row["produced"] = produced
		row["consumed"] = consumed
		row["unmet"] = unmet
		metrics[commodity_id] = row
		demand_total += demand
		produced_total += produced
		consumed_total += consumed
		unmet_total += unmet
		var base_price := maxi(1, int(commodity.get("base_price_centimes", 1)))
		var previous := maxi(1, int(prices.get(commodity_id, base_price)))
		var shortage_bp := 0 if demand <= 0.0 else int(round(clampf(unmet / demand, 0.0, 1.0) * 5500.0))
		var target_price := maxi(1, base_price * (BASIS_POINTS + shortage_bp) / BASIS_POINTS)
		prices[commodity_id] = clampi((previous * 3 + target_price) / 4, previous * 82 / 100, previous * 118 / 100)
	state["inventory"] = inventory
	state["prices"] = prices
	state["daily_metrics"] = metrics
	state["daily_totals"] = {
		"demand_units": demand_total,
		"produced_units": produced_total,
		"consumed_units": consumed_total,
		"unmet_units": unmet_total,
		"fulfillment_bp": BASIS_POINTS if demand_total <= 0.0 else int(round(clampf(consumed_total / demand_total, 0.0, 1.0) * BASIS_POINTS)),
	}
	state["last_settlement_hour"] = settlement_hour
	country_states[entity_id] = state


func _schedule_shortage_shipments(settlement_hour: int) -> void:
	var created := 0
	var receiver_ids: Array[String] = []
	for raw_id: Variant in country_states:
		receiver_ids.append(str(raw_id))
	receiver_ids.sort()
	for receiver_id: String in receiver_ids:
		if created >= MAX_SHIPMENTS_PER_DAY:
			break
		var receiver := country_states[receiver_id] as Dictionary
		for shortage: Dictionary in _top_country_shortages(receiver, 10):
			if created >= MAX_SHIPMENTS_PER_DAY:
				break
			var commodity_id := str(shortage.get("commodity_id", ""))
			var remaining := float(shortage.get("unmet", 0.0))
			var suppliers := _candidate_suppliers(receiver_id, commodity_id)
			for supplier: Dictionary in suppliers:
				if remaining <= 0.0001 or created >= MAX_SHIPMENTS_PER_DAY:
					break
				var origin_id := str(supplier.get("country_id", ""))
				var route := supplier.get("route", {}) as Dictionary
				var origin := country_states[origin_id] as Dictionary
				var origin_inventory := origin.get("inventory", {}) as Dictionary
				var available := float(origin_inventory.get(commodity_id, 0.0))
				var origin_demand := float(((origin.get("daily_metrics", {}) as Dictionary).get(commodity_id, {}) as Dictionary).get("demand", 0.0))
				var surplus := maxf(0.0, available - origin_demand * 10.0)
				var units := minf(remaining, minf(surplus, float(route.get("capacity_units_per_day", 0.0))))
				if units <= 0.0001:
					continue
				origin_inventory[commodity_id] = available - units
				var origin_metrics := origin.get("daily_metrics", {}) as Dictionary
				var origin_row := origin_metrics.get(commodity_id, {}) as Dictionary
				origin_row["exports"] = float(origin_row.get("exports", 0.0)) + units
				origin_metrics[commodity_id] = origin_row
				origin["inventory"] = origin_inventory
				origin["daily_metrics"] = origin_metrics
				country_states[origin_id] = origin
				var price := int((origin.get("prices", {}) as Dictionary).get(commodity_id, 1))
				var value := maxi(1, int(round(units * float(price))))
				var shipment := {
					"shipment_id": "formal_shipment:%d" % _next_shipment_sequence,
					"origin_entity_id": origin_id,
					"destination_entity_id": receiver_id,
					"commodity_id": commodity_id,
					"units": units,
					"value_centimes": value,
					"dispatch_hour": settlement_hour,
					"arrival_hour": settlement_hour + int(route.get("duration_hours", HOURS_PER_DAY)),
					"route_id": str(route.get("route_id", "")),
					"status": "in_transit",
				}
				_next_shipment_sequence += 1
				shipments.append(shipment)
				remaining -= units
				created += 1


func _deliver_shipments(settlement_hour: int) -> void:
	for index: int in range(shipments.size() - 1, -1, -1):
		var shipment := shipments[index] as Dictionary
		if int(shipment.get("arrival_hour", 0)) > settlement_hour:
			continue
		var destination_id := str(shipment.get("destination_entity_id", ""))
		var origin_id := str(shipment.get("origin_entity_id", ""))
		var commodity_id := str(shipment.get("commodity_id", ""))
		var units := float(shipment.get("units", 0.0))
		var value := int(shipment.get("value_centimes", 0))
		if country_states.has(destination_id):
			var destination := country_states[destination_id] as Dictionary
			var inventory := destination.get("inventory", {}) as Dictionary
			inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + units
			var metrics := destination.get("daily_metrics", {}) as Dictionary
			var row := metrics.get(commodity_id, {}) as Dictionary
			row["imports"] = float(row.get("imports", 0.0)) + units
			metrics[commodity_id] = row
			destination["inventory"] = inventory
			destination["daily_metrics"] = metrics
			destination["trade_balance_centimes"] = int(destination.get("trade_balance_centimes", 0)) - value
			country_states[destination_id] = destination
		if country_states.has(origin_id):
			var origin := country_states[origin_id] as Dictionary
			origin["trade_balance_centimes"] = int(origin.get("trade_balance_centimes", 0)) + value
			country_states[origin_id] = origin
		shipments.remove_at(index)


func _candidate_suppliers(receiver_id: String, commodity_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_index: Variant in _routes_by_country.get(receiver_id, []) as Array:
		var route := routes[int(raw_index)] as Dictionary
		var origin := str(route.get("from", ""))
		var destination := str(route.get("to", ""))
		var other := destination if origin == receiver_id else origin
		if other == receiver_id or not country_states.has(other):
			continue
		var state := country_states[other] as Dictionary
		var available := float((state.get("inventory", {}) as Dictionary).get(commodity_id, 0.0))
		var demand := float(((state.get("daily_metrics", {}) as Dictionary).get(commodity_id, {}) as Dictionary).get("demand", 0.0))
		var surplus := maxf(0.0, available - demand * 10.0)
		if surplus > 0.0001:
			result.append({"country_id": other, "surplus": surplus, "route": route.duplicate(true)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("surplus", 0.0)) > float(b.get("surplus", 0.0))
	)
	if result.size() > MAX_SUPPLIERS_PER_SHORTAGE:
		result.resize(MAX_SUPPLIERS_PER_SHORTAGE)
	return result


func _daily_demand_for(population: int, income_per_capita: int, commodity: Dictionary) -> float:
	var rate := float(commodity.get("base_daily_units_per_million", 0.0))
	if rate <= 0.0 or population <= 0:
		return 0.0
	var income_index := clampf(float(income_per_capita) / 2200.0, 0.25, 3.0)
	var elasticity := float(commodity.get("income_elasticity_bp", 0)) / float(BASIS_POINTS)
	var income_factor := clampf(1.0 + (income_index - 1.0) * elasticity, 0.3, 3.5)
	return rate * float(population) / 1000000.0 * income_factor


func _production_factor(record: Dictionary, commodity: Dictionary) -> float:
	var production := record.get("production", {}) as Dictionary
	var category := str(commodity.get("category", ""))
	var commodity_id := str(commodity.get("commodity_id", ""))
	var agriculture := float(production.get("agriculture_capacity_index", 0)) / 100.0
	var industry := float(production.get("industrial_capacity_index", 0)) / 100.0
	var mineral := production.get("mineral_capacity_index", {}) as Dictionary
	if commodity_id in ["coal", "iron_ore", "copper", "petroleum", "timber"]:
		return clampf(float(mineral.get(commodity_id, 0)) / 70.0, 0.0, 2.5)
	if category in ["agricultural_food", "agricultural_input"]:
		return clampf(agriculture, 0.05, 2.2)
	if category in ["industrial_material", "capital_good", "manufactured_good", "processed_food", "textile"]:
		return clampf(industry, 0.03, 2.4)
	return clampf((agriculture + industry) * 0.5, 0.05, 1.8)


func _opening_gold_units(record: Dictionary) -> float:
	var population := float((record.get("population", {}) as Dictionary).get("value", 0))
	var income := float((record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary).get("value", 0))
	var confidence := float(record.get("overall_confidence_bp", 0)) / float(BASIS_POINTS)
	return maxf(1.0, population * income * maxf(0.1, confidence) / 1000000.0)


func _top_country_shortages(state: Dictionary, limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var metrics := state.get("daily_metrics", {}) as Dictionary
	for raw_id: Variant in metrics:
		var commodity_id := str(raw_id)
		var row := metrics[commodity_id] as Dictionary
		var unmet := float(row.get("unmet", 0.0))
		if unmet > 0.0001:
			rows.append({
				"entity_id": str(state.get("entity_id", "")),
				"commodity_id": commodity_id,
				"name_zh": str((_commodities.get(commodity_id, {}) as Dictionary).get("name_zh", commodity_id)),
				"unmet": unmet,
				"demand": float(row.get("demand", 0.0)),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("unmet", 0.0)) > float(b.get("unmet", 0.0))
	)
	if rows.size() > limit:
		rows.resize(limit)
	return rows


func _top_world_shortages(limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw_state: Variant in country_states.values():
		rows.append_array(_top_country_shortages(raw_state as Dictionary, 3))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("unmet", 0.0)) > float(b.get("unmet", 0.0))
	)
	if rows.size() > limit:
		rows.resize(limit)
	return rows


func _shipment_count_for(entity_id: String) -> int:
	var count := 0
	for shipment: Dictionary in shipments:
		if (
			str(shipment.get("origin_entity_id", "")) == entity_id
			or str(shipment.get("destination_entity_id", "")) == entity_id
		):
			count += 1
	return count


func _validate_state() -> bool:
	for raw_state: Variant in country_states.values():
		var state := raw_state as Dictionary
		if int(state.get("population", 0)) <= 0:
			return false
		for value: Variant in (state.get("inventory", {}) as Dictionary).values():
			if float(value) < 0.0:
				return false
	for shipment: Dictionary in shipments:
		if (
			float(shipment.get("units", 0.0)) <= 0.0
			or int(shipment.get("arrival_hour", 0)) <= int(shipment.get("dispatch_hour", 0))
		):
			return false
	return true


func _fail(message: String) -> bool:
	initialization_error = message
	return false
