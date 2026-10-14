class_name FormalWorldEconomySimulation
extends RefCounted
## Initializes and settles the injected economy state. No persistence or UI API.

const HOURS_PER_DAY: int = FormalWorldEconomyState.HOURS_PER_DAY
const BASIS_POINTS: int = FormalWorldEconomyState.BASIS_POINTS
const HISTORY_LIMIT: int = 366
const MAX_SHIPMENTS_PER_DAY: int = 96
const MAX_SUPPLIERS_PER_SHORTAGE: int = 4

var _state: FormalWorldEconomyState
## Algorithm lookup only; route records themselves belong to the current state.
var _routes_by_country: Dictionary = {}

func _init(state: FormalWorldEconomyState) -> void:
	_state = state
	if _state != null:
		for index: int in _state.routes.size():
			_index_route(_state.routes[index], index)

func initialize_state() -> bool:
	if _state == null or not _state._inputs_ready or _state.is_configured():
		return false
	_routes_by_country.clear()
	for record: Dictionary in _state._static_evidence.countries():
		_initialize_country(record)
	_build_routes()
	return _state.validate_initial_state()


func settle_hour_range(
	previous_total_hour: int, current_total_hour: int
) -> Dictionary:
	if previous_total_hour < 0 or current_total_hour <= previous_total_hour:
		return _state.world_summary()
	assert(current_total_hour == _state.total_hour)
	for crossed_hour: int in range(previous_total_hour + 1, current_total_hour + 1):
		if crossed_hour % HOURS_PER_DAY == 0:
			_settle_day(crossed_hour)
	return _state.world_summary()


func _initialize_country(record: Dictionary) -> void:
	var entity_id := str(record.get("entity_id", ""))
	if entity_id.is_empty():
		return
	var market_id := _state._market_registry.market_id_for_economic_aggregate(entity_id)
	if market_id.is_empty() or _state.market_states.has(market_id):
		_state._fail("主要经济聚合缺少唯一 Market identity：%s" % entity_id)
		return
	var polity_ids := _state._resolve_polity_ids(entity_id)
	if polity_ids.is_empty():
		_state._fail("主要经济体未映射到1900政治地图：%s" % entity_id)
		return
	for polity_id: String in polity_ids:
		if _state.economy_by_polity_id.has(polity_id):
			_state._fail(
				"政治单元重复映射到主要经济体：%s" % polity_id
			)
			return
	var population := _state.current_population(entity_id)
	var income_record := record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary
	var inventory: Dictionary = {}
	var prices: Dictionary = {}
	var daily_metrics: Dictionary = {}
	for raw_id: Variant in _state._commodities:
		var commodity_id := str(raw_id)
		var commodity := _state._commodities[commodity_id] as Dictionary
		var base_price := maxi(1, int(commodity.get("base_price_centimes", 1)))
		var demand := _daily_demand_for(
			population,
			int(income_record.get("value", 0)),
			commodity
		)
		var capacity_factor := _production_factor(record, commodity)
		var opening_days := 8.0 + 22.0 * capacity_factor
		inventory[commodity_id] = maxf(
			demand * opening_days, capacity_factor * 40.0
		)
		prices[commodity_id] = base_price
		daily_metrics[commodity_id] = {
			"demand": 0.0,
			"produced": 0.0,
			"consumed": 0.0,
			"unmet": 0.0,
			"imports": 0.0,
			"exports": 0.0,
		}
	_state.market_states[market_id] = {
		"market_id": market_id,
		"source_economic_aggregate_id": entity_id,
		"inventory": inventory,
		"prices": prices,
		"daily_metrics": daily_metrics,
		"daily_totals": {},
		"gold_reserve_units": _opening_gold_units(
			record, population
		),
		"trade_balance_centimes": 0,
		"tariff_revenue_centimes": 0,
		"last_settlement_hour": 0,
	}


	_state.economy_polity_ids[entity_id] = polity_ids.duplicate()
	for polity_id: String in polity_ids:
		_state.economy_by_polity_id[polity_id] = entity_id


func _build_routes() -> void:
	for record: Dictionary in _state._static_evidence.maritime_corridors():
		_add_route({
			"route_id": str(record.get("corridor_id", "")),
			"from": str(record.get("origin_entity_id", "")),
			"to": str(record.get("destination_entity_id", "")),
			"duration_hours": maxi(
				HOURS_PER_DAY, int(record.get("duration_days", 1)) * HOURS_PER_DAY
			),
			"capacity_units_per_day": maxf(
				10.0, float(record.get("capacity_index", 1)) * 18.0
			),
			"mode": str(record.get("mode", "steamship")),
			"confidence_bp": int(record.get("confidence_bp", 0)),
		})
	for record: Dictionary in _state._static_evidence.river_corridors():
		var ids := DataRecordUtils.to_string_array(record.get("entity_ids", []))
		for index: int in range(ids.size() - 1):
			_add_route({
				"route_id": "%s:%d" % [str(record.get("corridor_id", "river")), index],
				"from": ids[index],
				"to": ids[index + 1],
				"duration_hours": 3 * HOURS_PER_DAY,
				"capacity_units_per_day": maxf(
					8.0, float(record.get("capacity_index", 1)) * 12.0
				),
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
		or not _state._has_economic_aggregate(origin)
		or not _state._has_economic_aggregate(destination)
	):
		return
	_state.routes.append(route.duplicate(true))
	_index_route(route, _state.routes.size() - 1)


func _index_route(route: Dictionary, index: int) -> void:
	for country_id: String in [str(route.get("from", "")), str(route.get("to", ""))]:
		var indexes := _routes_by_country.get(country_id, []) as Array
		indexes.append(index)
		_routes_by_country[country_id] = indexes


func _settle_day(settlement_hour: int) -> void:
	var day_index := settlement_hour / HOURS_PER_DAY
	if day_index <= _state._last_day_index:
		return
	_deliver_shipments(settlement_hour)
	for economy_id: String in _state._economic_aggregate_ids():
		_settle_country(economy_id, settlement_hour)
	_schedule_shortage_shipments(settlement_hour)
	_state._last_day_index = day_index
	var summary := _state.world_summary()
	# Bulk advancement must record the boundary being settled, not the final
	# composition-root hour that is visible while the range is processed.
	summary["total_hour"] = settlement_hour
	summary["day_index"] = day_index
	_state.history.append(summary)
	while _state.history.size() > HISTORY_LIMIT:
		_state.history.pop_front()
	_state._state_revision += 1


func _settle_country(entity_id: String, settlement_hour: int) -> void:
	var market_id := _state._market_registry.market_id_for_economic_aggregate(entity_id)
	var state := _state.market_states[market_id] as Dictionary
	var calculation_input := _state._resolved_inputs[entity_id] as Dictionary
	var population := _state.consumption_population(entity_id)
	if population < 0:
		push_error(_state.initialization_error)
		return
	var income_per_capita := int(calculation_input.get("income_per_capita", 0))
	var production := calculation_input.get("production", {}) as Dictionary
	var inventory := state.get("inventory", {}) as Dictionary
	var prices := state.get("prices", {}) as Dictionary
	var metrics := state.get("daily_metrics", {}) as Dictionary
	var demand_total := 0.0
	var produced_total := 0.0
	var consumed_total := 0.0
	var unmet_total := 0.0
	for raw_id: Variant in _state._commodities:
		var commodity_id := str(raw_id)
		var commodity := _state._commodities[commodity_id] as Dictionary
		var row := metrics.get(commodity_id, {}) as Dictionary
		row["imports"] = 0.0
		row["exports"] = 0.0
		var demand := _daily_demand_for(
			population,
			income_per_capita,
			commodity
		)
		var production_factor := _production_factor_for_capabilities(
			production, commodity
		)
		var produced := maxf(0.0, demand * production_factor)
		inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + produced
		var consumed := minf(demand, float(inventory.get(commodity_id, 0.0)))
		inventory[commodity_id] = maxf(
			0.0, float(inventory.get(commodity_id, 0.0)) - consumed
		)
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
		var shortage_bp := 0 if demand <= 0.0 else int(
			round(clampf(unmet / demand, 0.0, 1.0) * 5500.0)
		)
		var target_price := maxi(
			1, base_price * (BASIS_POINTS + shortage_bp) / BASIS_POINTS
		)
		prices[commodity_id] = clampi(
			(previous * 3 + target_price) / 4,
			previous * 82 / 100,
			previous * 118 / 100
		)
	state["inventory"] = inventory
	state["prices"] = prices
	state["daily_metrics"] = metrics
	state["daily_totals"] = {
		"demand_units": demand_total,
		"produced_units": produced_total,
		"consumed_units": consumed_total,
		"unmet_units": unmet_total,
		"fulfillment_bp": BASIS_POINTS if demand_total <= 0.0 else int(
			round(clampf(consumed_total / demand_total, 0.0, 1.0) * BASIS_POINTS)
		),
	}
	state["last_settlement_hour"] = settlement_hour
	_state.market_states[market_id] = state
	_state._rebuild_daily_shortage_rows(market_id, state)


func _schedule_shortage_shipments(settlement_hour: int) -> void:
	var created := 0
	var receiver_ids := _state._economic_aggregate_ids()
	receiver_ids.sort()
	for receiver_id: String in receiver_ids:
		if created >= MAX_SHIPMENTS_PER_DAY:
			break
		var receiver_market_id := (
			_state._market_registry.market_id_for_economic_aggregate(receiver_id)
		)
		var receiver := _state.market_states[receiver_market_id] as Dictionary
		for shortage: Dictionary in _state._top_country_shortages(receiver, 10):
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
				var origin_market_id := (
					_state._market_registry.market_id_for_economic_aggregate(origin_id)
				)
				var origin := _state.market_states[origin_market_id] as Dictionary
				var origin_inventory := origin.get("inventory", {}) as Dictionary
				var available := float(origin_inventory.get(commodity_id, 0.0))
				var origin_demand := float(
					((origin.get("daily_metrics", {}) as Dictionary).get(
						commodity_id, {}
					) as Dictionary).get("demand", 0.0)
				)
				var surplus := maxf(0.0, available - origin_demand * 10.0)
				var units := minf(
					remaining,
					minf(surplus, float(route.get("capacity_units_per_day", 0.0)))
				)
				if units <= 0.0001:
					continue
				origin_inventory[commodity_id] = available - units
				var origin_metrics := origin.get("daily_metrics", {}) as Dictionary
				var origin_row := origin_metrics.get(commodity_id, {}) as Dictionary
				origin_row["exports"] = float(origin_row.get("exports", 0.0)) + units
				origin_metrics[commodity_id] = origin_row
				origin["inventory"] = origin_inventory
				origin["daily_metrics"] = origin_metrics
				_state.market_states[origin_market_id] = origin
				var price := int(
					(origin.get("prices", {}) as Dictionary).get(commodity_id, 1)
				)
				var value := maxi(1, int(round(units * float(price))))
				_state.shipments.append({
					"shipment_id": "formal_shipment:%d" % _state._next_shipment_sequence,
					"origin_entity_id": origin_id,
					"destination_entity_id": receiver_id,
					"commodity_id": commodity_id,
					"units": units,
					"value_centimes": value,
					"dispatch_hour": settlement_hour,
					"arrival_hour": settlement_hour + int(
						route.get("duration_hours", HOURS_PER_DAY)
					),
					"route_id": str(route.get("route_id", "")),
					"status": "in_transit",
				})
				_state._next_shipment_sequence += 1
				remaining -= units
				created += 1


func _deliver_shipments(settlement_hour: int) -> void:
	for index: int in range(_state.shipments.size() - 1, -1, -1):
		var shipment := _state.shipments[index] as Dictionary
		if int(shipment.get("arrival_hour", 0)) > settlement_hour:
			continue
		var destination_id := str(shipment.get("destination_entity_id", ""))
		var origin_id := str(shipment.get("origin_entity_id", ""))
		var commodity_id := str(shipment.get("commodity_id", ""))
		var units := float(shipment.get("units", 0.0))
		var value := int(shipment.get("value_centimes", 0))
		if _state._has_economic_aggregate(destination_id):
			var destination_market_id := (
				_state._market_registry.market_id_for_economic_aggregate(destination_id)
			)
			var destination := _state.market_states[destination_market_id] as Dictionary
			var inventory := destination.get("inventory", {}) as Dictionary
			inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + units
			var metrics := destination.get("daily_metrics", {}) as Dictionary
			var row := metrics.get(commodity_id, {}) as Dictionary
			row["imports"] = float(row.get("imports", 0.0)) + units
			metrics[commodity_id] = row
			destination["inventory"] = inventory
			destination["daily_metrics"] = metrics
			destination["trade_balance_centimes"] = int(
				destination.get("trade_balance_centimes", 0)
			) - value
			_state.market_states[destination_market_id] = destination
		if _state._has_economic_aggregate(origin_id):
			var origin_market_id := (
				_state._market_registry.market_id_for_economic_aggregate(origin_id)
			)
			var origin := _state.market_states[origin_market_id] as Dictionary
			origin["trade_balance_centimes"] = int(
				origin.get("trade_balance_centimes", 0)
			) + value
			_state.market_states[origin_market_id] = origin
		_state.shipments.remove_at(index)


func _candidate_suppliers(receiver_id: String, commodity_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_index: Variant in _routes_by_country.get(receiver_id, []) as Array:
		var route := _state.routes[int(raw_index)] as Dictionary
		var origin := str(route.get("from", ""))
		var destination := str(route.get("to", ""))
		var other := destination if origin == receiver_id else origin
		if other == receiver_id or not _state._has_economic_aggregate(other):
			continue
		var other_market_id := _state._market_registry.market_id_for_economic_aggregate(other)
		var state := _state.market_states[other_market_id] as Dictionary
		var available := float(
			(state.get("inventory", {}) as Dictionary).get(commodity_id, 0.0)
		)
		var demand := float(
			((state.get("daily_metrics", {}) as Dictionary).get(
				commodity_id, {}
			) as Dictionary).get("demand", 0.0)
		)
		var surplus := maxf(0.0, available - demand * 10.0)
		if surplus > 0.0001:
			result.append({
				"country_id": other,
				"surplus": surplus,
				"route": route.duplicate(true),
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("surplus", 0.0)) > float(b.get("surplus", 0.0))
	)
	if result.size() > MAX_SUPPLIERS_PER_SHORTAGE:
		result.resize(MAX_SUPPLIERS_PER_SHORTAGE)
	return result


func _daily_demand_for(
	population: int, income_per_capita: int, commodity: Dictionary
) -> float:
	var rate := float(commodity.get("base_daily_units_per_million", 0.0))
	if rate <= 0.0 or population <= 0:
		return 0.0
	var income_index := clampf(float(income_per_capita) / 2200.0, 0.25, 3.0)
	var elasticity := float(commodity.get("income_elasticity_bp", 0)) / float(
		BASIS_POINTS
	)
	var income_factor := clampf(
		1.0 + (income_index - 1.0) * elasticity, 0.3, 3.5
	)
	return rate * float(population) / 1000000.0 * income_factor


func _production_factor(record: Dictionary, commodity: Dictionary) -> float:
	var production := record.get("production", {}) as Dictionary
	return _production_factor_for_capabilities(production, commodity)


func _production_factor_for_capabilities(
	production: Dictionary, commodity: Dictionary
) -> float:
	var category := str(commodity.get("category", ""))
	var commodity_id := str(commodity.get("commodity_id", ""))
	var agriculture := float(production.get("agriculture_capacity_index", 0)) / 100.0
	var industry := float(production.get("industrial_capacity_index", 0)) / 100.0
	var mineral := production.get("mineral_capacity_index", {}) as Dictionary
	if commodity_id in ["coal", "iron_ore", "copper", "petroleum", "timber"]:
		return clampf(float(mineral.get(commodity_id, 0)) / 70.0, 0.0, 2.5)
	if category in ["agricultural_food", "agricultural_input"]:
		return clampf(agriculture, 0.05, 2.2)
	if category in [
		"industrial_material",
		"capital_good",
		"manufactured_good",
		"processed_food",
		"textile",
	]:
		return clampf(industry, 0.03, 2.4)
	return clampf((agriculture + industry) * 0.5, 0.05, 1.8)


func _opening_gold_units(record: Dictionary, population_value: int) -> float:
	var population := float(population_value)
	var income := float(
		(record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary).get(
			"value", 0
		)
	)
	var confidence := float(record.get("overall_confidence_bp", 0)) / float(
		BASIS_POINTS
	)
	return maxf(1.0, population * income * maxf(0.1, confidence) / 1000000.0)
