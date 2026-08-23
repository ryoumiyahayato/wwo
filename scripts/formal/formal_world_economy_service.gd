class_name FormalWorldEconomyService
extends RefCounted
## Formal 1900 world economy. The historical map contains every dated political
## unit, while only the ranked major-economy roster receives high-detail economy.
## One economy may cover several map units, as with the six Australian colonies.
## The retired two-country/eight-region Alpha world is never loaded here.

const HOURS_PER_DAY: int = 24
const BASIS_POINTS: int = 10000
const HISTORY_LIMIT: int = 366
const MAX_SHIPMENTS_PER_DAY: int = 96
const MAX_SUPPLIERS_PER_SHORTAGE: int = 4
const EXPECTED_MAJOR_ROSTER_COUNT: int = 50
const PRIMARY_PLAYABLE_LIMIT: int = 30
const COMMODITY_CATALOG_PATH: String = "res://data/alpha/commodity_market_1900.json"
const POLITICAL_UNITS_PATH: String = "res://data/world_map/historical/political_units_1900.json"
const CROSSWALK_PATH: String = "res://data/world_map/historical/major_economy_polity_crosswalk_1900.json"

var country_states: Dictionary = {}
var polity_records: Dictionary = {}
var economy_polity_ids: Dictionary = {}
var economy_by_polity_id: Dictionary = {}
var routes: Array[Dictionary] = []
var shipments: Array[Dictionary] = []
var history: Array[Dictionary] = []
var initialization_error: String = ""

var _authoritative_hour_source: Callable = Callable()
var total_hour: int:
	get:
		assert(
			_authoritative_hour_source.is_valid(),
			"FormalWorldEconomyService requires the formal simulation hour source"
		)
		return int(_authoritative_hour_source.call())

var _historical := AlphaHistoricalWorldEconomyData.new()
var _commodities: Dictionary = {}
var _routes_by_country: Dictionary = {}
var _crosswalk_records: Dictionary = {}
var _next_shipment_sequence: int = 1
var _last_day_index: int = -1
var _political_unit_count: int = 0


func configure() -> bool:
	country_states.clear()
	polity_records.clear()
	economy_polity_ids.clear()
	economy_by_polity_id.clear()
	routes.clear()
	shipments.clear()
	history.clear()
	_routes_by_country.clear()
	_crosswalk_records.clear()
	_commodities.clear()
	_last_day_index = -1
	_next_shipment_sequence = 1
	_political_unit_count = 0
	initialization_error = ""
	if not _historical.configure():
		return _fail(_historical.initialization_error)
	if not _load_commodity_catalog():
		return false
	if not _load_polity_registry():
		return false
	if not _load_crosswalk():
		return false
	for record: Dictionary in _historical.simulation_countries():
		_initialize_country(record)
	_build_routes()
	if country_states.size() != EXPECTED_MAJOR_ROSTER_COUNT:
		return _fail(
			"主要政权高细节经济目录应为%d，当前为%d：%s" % [
				EXPECTED_MAJOR_ROSTER_COUNT,
				country_states.size(),
				initialization_error,
			]
		)
	if _political_unit_count <= country_states.size():
		return _fail("世界政治单元目录不得等同于主要政权目录")
	if _commodities.is_empty():
		return _fail("正式世界商品目录为空")
	return _validate_state()


func bind_authoritative_hour_source(source: Callable) -> void:
	_authoritative_hour_source = source


func settle_hour_range(
	previous_total_hour: int, current_total_hour: int
) -> Dictionary:
	if previous_total_hour < 0 or current_total_hour <= previous_total_hour:
		return world_summary()
	assert(current_total_hour == total_hour)
	for crossed_hour: int in range(previous_total_hour + 1, current_total_hour + 1):
		if crossed_hour % HOURS_PER_DAY == 0:
			_settle_day(crossed_hour)
	return world_summary()


func world_summary() -> Dictionary:
	var population := 0
	var demand := 0.0
	var consumed := 0.0
	var unmet := 0.0
	var verified := 0
	var bounded := 0
	var leading_power_count := 0
	var great_power_count := 0
	var major_power_count := 0
	var primary_playable_count := 0
	var secondary_roster_count := 0
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
		match str(state.get("playability_tier", "")):
			"leading_power": leading_power_count += 1
			"great_power": great_power_count += 1
			"major_power": major_power_count += 1
			"primary_playable": primary_playable_count += 1
			"secondary_roster": secondary_roster_count += 1
	return {
		"total_hour": total_hour,
		# Compatibility alias. This is the high-detail economy roster, not world total.
		"country_count": country_states.size(),
		"major_economy_count": country_states.size(),
		"world_political_unit_count": _political_unit_count,
		"detailed_polity_unit_count": economy_by_polity_id.size(),
		"background_polity_count": maxi(
			0, _political_unit_count - economy_by_polity_id.size()
		),
		"primary_playable_count": (
			leading_power_count
			+ great_power_count
			+ major_power_count
			+ primary_playable_count
		),
		"secondary_roster_count": secondary_roster_count,
		"leading_power_count": leading_power_count,
		"great_power_count": great_power_count,
		"major_power_count": major_power_count,
		"crosswalk_exception_count": _crosswalk_records.size(),
		"population": population,
		"commodity_count": _commodities.size(),
		"active_shipments": shipments.size(),
		"route_count": routes.size(),
		"verified_country_count": verified,
		"bounded_country_count": bounded,
		"demand_units": demand,
		"consumed_units": consumed,
		"unmet_units": unmet,
		"fulfillment_bp": BASIS_POINTS if demand <= 0.0 else int(
			round(clampf(consumed / demand, 0.0, 1.0) * BASIS_POINTS)
		),
		"top_shortages": _top_world_shortages(8),
	}


func country_summary(entity_id: String) -> Dictionary:
	var economy_id := entity_id
	if not country_states.has(economy_id):
		economy_id = economy_entity_for_polity(entity_id)
	var state := country_states.get(economy_id, {}) as Dictionary
	if state.is_empty():
		return {}
	var result := state.duplicate(true)
	result["top_shortages"] = _top_country_shortages(state, 8)
	result["active_shipments"] = _shipment_count_for(economy_id)
	return result


func polity_summary(entity_id: String) -> Dictionary:
	var polity := polity_records.get(entity_id, {}) as Dictionary
	if polity.is_empty():
		return {}
	var result := polity.duplicate(true)
	var economy_id := economy_entity_for_polity(entity_id)
	var detailed := not economy_id.is_empty() and country_states.has(economy_id)
	result["has_detailed_economy"] = detailed
	result["economy_entity_id"] = economy_id
	if detailed:
		result["economy"] = country_summary(economy_id)
	return result


func has_polity(entity_id: String) -> bool:
	return polity_records.has(entity_id)


func first_polity_id() -> String:
	var ids: Array[String] = []
	for raw_id: Variant in polity_records.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func has_detailed_economy(entity_id: String) -> bool:
	return not economy_entity_for_polity(entity_id).is_empty()


func economy_entity_for_polity(polity_id: String) -> String:
	return str(economy_by_polity_id.get(polity_id, ""))


func economy_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in country_states.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func transport_routes() -> Array[Dictionary]:
	return routes.duplicate(true)


func polity_ids_for_economy(economy_id: String) -> Array[String]:
	return DataRecordUtils.to_string_array(economy_polity_ids.get(economy_id, []))


func formal_verified_countries() -> Array[Dictionary]:
	return _historical.formal_countries()


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": "formal_world_economy_state_v3",
		"total_hour": total_hour,
		"country_states": country_states.duplicate(true),
		"shipments": shipments.duplicate(true),
		"history": history.duplicate(true),
		"next_shipment_sequence": _next_shipment_sequence,
		"last_day_index": _last_day_index,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in [
			"formal_world_economy_state_v1",
			"formal_world_economy_state_v2",
			"formal_world_economy_state_v3",
		]
		or not state.get("country_states", {}) is Dictionary
		or not state.get("shipments", []) is Array
		or not state.get("history", []) is Array
	):
		return false
	var saved_total_hour := int(state.get("total_hour", -1))
	if saved_total_hour < 0 or saved_total_hour != total_hour:
		return false
	var candidate_country_states: Dictionary = (
		(state.get("country_states", {}) as Dictionary).duplicate(true)
	)
	if candidate_country_states.size() != country_states.size():
		return false
	for raw_id: Variant in candidate_country_states:
		var economy_id := str(raw_id)
		if (
			not country_states.has(economy_id)
			or not candidate_country_states[economy_id] is Dictionary
		):
			return false
		var restored_state := candidate_country_states[economy_id] as Dictionary
		if not restored_state.get("polity_ids", []) is Array:
			restored_state["polity_ids"] = polity_ids_for_economy(economy_id)
			candidate_country_states[economy_id] = restored_state
	var candidate_shipments: Array[Dictionary] = (
		DataRecordUtils.to_dictionary_array(state.get("shipments", []))
	)
	var candidate_history: Array[Dictionary] = (
		DataRecordUtils.to_dictionary_array(state.get("history", []))
	)
	var candidate_next_shipment_sequence: int = maxi(
		1, int(state.get("next_shipment_sequence", 1))
	)
	var expected_last_day_index := (
		-1
		if saved_total_hour < HOURS_PER_DAY
		else int(saved_total_hour / HOURS_PER_DAY)
	)
	var candidate_last_day_index: int = int(
		state.get("last_day_index", expected_last_day_index)
	)
	while candidate_history.size() > HISTORY_LIMIT:
		candidate_history.pop_front()
	if not _validate_candidate_state(
		candidate_country_states,
		candidate_shipments,
		candidate_last_day_index,
		saved_total_hour
	):
		return false
	country_states = candidate_country_states
	shipments = candidate_shipments
	history = candidate_history
	_next_shipment_sequence = candidate_next_shipment_sequence
	_last_day_index = candidate_last_day_index
	return true


func _load_commodity_catalog() -> bool:
	var document := _read_document(COMMODITY_CATALOG_PATH)
	if document.is_empty():
		return false
	if str(document.get("schema_id", "")) != "alpha_commodity_market_1900_v1":
		return _fail("1900商品目录 Schema 无效")
	for raw_commodity: Variant in document.get("commodities", []) as Array:
		if not raw_commodity is Dictionary:
			continue
		var commodity := (raw_commodity as Dictionary).duplicate(true)
		var commodity_id := str(commodity.get("commodity_id", ""))
		if not commodity_id.is_empty():
			_commodities[commodity_id] = commodity
	return not _commodities.is_empty()


func _load_polity_registry() -> bool:
	var document := _read_document(POLITICAL_UNITS_PATH)
	if document.is_empty():
		return false
	var units := document.get("units", []) as Array
	_political_unit_count = int(document.get("unit_count", units.size()))
	for raw_unit: Variant in units:
		if not raw_unit is Dictionary:
			continue
		var unit := (raw_unit as Dictionary).duplicate(true)
		var entity_id := str(unit.get("id", ""))
		if entity_id.is_empty():
			continue
		unit["entity_id"] = entity_id
		unit["playability_tier"] = "background_npc"
		unit["playability_tier_zh"] = "背景政治单元"
		unit["major_roster"] = false
		unit["primary_playable"] = false
		unit["economy_entity_id"] = ""
		polity_records[entity_id] = unit
	if polity_records.size() != _political_unit_count:
		return _fail(
			"1900政治单元目录计数不一致：声明%d，加载%d" % [
				_political_unit_count, polity_records.size(),
			]
		)
	return true


func _load_crosswalk() -> bool:
	var document := _read_document(CROSSWALK_PATH)
	if document.is_empty():
		return false
	if str(document.get("schema_id", "")) != "major_economy_polity_crosswalk_1900_v1":
		return _fail("主要经济体与政治单元交叉表 Schema 无效")
	for raw_record: Variant in document.get("records", []) as Array:
		if not raw_record is Dictionary:
			return _fail("主要经济体交叉表记录格式无效")
		var record := (raw_record as Dictionary).duplicate(true)
		var economy_id := str(record.get("economy_entity_id", ""))
		var polity_ids := DataRecordUtils.to_string_array(record.get("polity_ids", []))
		if economy_id.is_empty() or polity_ids.is_empty():
			return _fail("主要经济体交叉表记录缺少ID")
		for polity_id: String in polity_ids:
			if not polity_records.has(polity_id):
				return _fail("交叉表引用未知政治单元：%s" % polity_id)
		_crosswalk_records[economy_id] = record
	return true


func _initialize_country(record: Dictionary) -> void:
	var entity_id := str(record.get("entity_id", ""))
	if entity_id.is_empty():
		return
	var polity_ids := _resolve_polity_ids(entity_id)
	if polity_ids.is_empty():
		_fail("主要经济体未映射到1900政治地图：%s" % entity_id)
		return
	for polity_id: String in polity_ids:
		if economy_by_polity_id.has(polity_id):
			_fail(
				"政治单元重复映射到主要经济体：%s" % polity_id
			)
			return
	var rank := int(record.get("rank", 0))
	var tier := _tier_for_rank(rank)
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
	var coverage := record.get("coverage", {}) as Dictionary
	country_states[entity_id] = {
		"entity_id": entity_id,
		"polity_ids": polity_ids.duplicate(),
		"rank": rank,
		"playability_tier": str(tier.get("id", "secondary_roster")),
		"playability_tier_zh": str(tier.get("name_zh", "次要目录")),
		"primary_playable": rank > 0 and rank <= PRIMARY_PLAYABLE_LIMIT,
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
		"verified_dimensions": (
			coverage.get("verified_dimensions", []) as Array
		).duplicate(),
		"inventory": inventory,
		"prices": prices,
		"daily_metrics": daily_metrics,
		"daily_totals": {},
		"gold_reserve_units": _opening_gold_units(record),
		"trade_balance_centimes": 0,
		"tariff_revenue_centimes": 0,
		"last_settlement_hour": 0,
	}
	economy_polity_ids[entity_id] = polity_ids.duplicate()
	for polity_id: String in polity_ids:
		economy_by_polity_id[polity_id] = entity_id
		var polity := polity_records[polity_id] as Dictionary
		polity["rank"] = rank
		polity["playability_tier"] = str(tier.get("id", "secondary_roster"))
		polity["playability_tier_zh"] = str(
			tier.get("name_zh", "次要目录")
		)
		polity["major_roster"] = true
		polity["primary_playable"] = rank > 0 and rank <= PRIMARY_PLAYABLE_LIMIT
		polity["economy_entity_id"] = entity_id
		polity_records[polity_id] = polity


func _resolve_polity_ids(economy_id: String) -> Array[String]:
	if polity_records.has(economy_id):
		return [economy_id]
	var crosswalk := _crosswalk_records.get(economy_id, {}) as Dictionary
	return DataRecordUtils.to_string_array(crosswalk.get("polity_ids", []))


func _tier_for_rank(rank: int) -> Dictionary:
	if rank >= 1 and rank <= 2:
		return {"id": "leading_power", "name_zh": "领先列强"}
	if rank <= 7:
		return {"id": "great_power", "name_zh": "列强"}
	if rank <= 18:
		return {"id": "major_power", "name_zh": "主要政权"}
	if rank <= PRIMARY_PLAYABLE_LIMIT:
		return {"id": "primary_playable", "name_zh": "可玩次级政权"}
	return {"id": "secondary_roster", "name_zh": "次要政权候选"}


func _build_routes() -> void:
	for record: Dictionary in _historical.maritime_corridors:
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
	for record: Dictionary in _historical.river_corridors:
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
				country_states[origin_id] = origin
				var price := int(
					(origin.get("prices", {}) as Dictionary).get(commodity_id, 1)
				)
				var value := maxi(1, int(round(units * float(price))))
				shipments.append({
					"shipment_id": "formal_shipment:%d" % _next_shipment_sequence,
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
				_next_shipment_sequence += 1
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
			destination["trade_balance_centimes"] = int(
				destination.get("trade_balance_centimes", 0)
			) - value
			country_states[destination_id] = destination
		if country_states.has(origin_id):
			var origin := country_states[origin_id] as Dictionary
			origin["trade_balance_centimes"] = int(
				origin.get("trade_balance_centimes", 0)
			) + value
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
		"military_good",
		"processed_food",
		"textile",
	]:
		return clampf(industry, 0.03, 2.4)
	return clampf((agriculture + industry) * 0.5, 0.05, 1.8)


func _opening_gold_units(record: Dictionary) -> float:
	var population := float(
		(record.get("population", {}) as Dictionary).get("value", 0)
	)
	var income := float(
		(record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary).get(
			"value", 0
		)
	)
	var confidence := float(record.get("overall_confidence_bp", 0)) / float(
		BASIS_POINTS
	)
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
				"name_zh": str(
					(_commodities.get(commodity_id, {}) as Dictionary).get(
						"name_zh", commodity_id
					)
				),
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
	return _validate_candidate_state(
		country_states,
		shipments,
		_last_day_index,
		total_hour
	)


func _validate_candidate_state(
	candidate_country_states: Dictionary,
	candidate_shipments: Array[Dictionary],
	candidate_last_day_index: int,
	expected_total_hour: int
) -> bool:
	if _political_unit_count != polity_records.size():
		return false
	if expected_total_hour < 0:
		return false
	var expected_last_day_index := (
		-1
		if expected_total_hour < HOURS_PER_DAY
		else int(expected_total_hour / HOURS_PER_DAY)
	)
	if candidate_last_day_index != expected_last_day_index:
		return false
	if candidate_country_states.size() != EXPECTED_MAJOR_ROSTER_COUNT:
		return false
	for raw_id: Variant in candidate_country_states:
		var economy_id := str(raw_id)
		if not candidate_country_states[economy_id] is Dictionary:
			return false
		var state := candidate_country_states[economy_id] as Dictionary
		var polity_ids := DataRecordUtils.to_string_array(state.get("polity_ids", []))
		if (
			str(state.get("entity_id", "")) != economy_id
			or int(state.get("population", 0)) <= 0
			or polity_ids.is_empty()
		):
			return false
		for polity_id: String in polity_ids:
			if (
				not polity_records.has(polity_id)
				or str(economy_by_polity_id.get(polity_id, "")) != economy_id
				or not bool(
					(polity_records[polity_id] as Dictionary).get(
						"major_roster", false
					)
				)
			):
				return false
		for value: Variant in (state.get("inventory", {}) as Dictionary).values():
			if float(value) < 0.0:
				return false
	for shipment: Dictionary in candidate_shipments:
		var origin_id := str(shipment.get("origin_entity_id", ""))
		var destination_id := str(shipment.get("destination_entity_id", ""))
		var dispatch_hour := int(shipment.get("dispatch_hour", -1))
		var arrival_hour := int(shipment.get("arrival_hour", -1))
		if (
			float(shipment.get("units", 0.0)) <= 0.0
			or not candidate_country_states.has(origin_id)
			or not candidate_country_states.has(destination_id)
			or dispatch_hour < 0
			or dispatch_hour > expected_total_hour
			or arrival_hour <= dispatch_hour
		):
			return false
	return true


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取正式世界数据：%s" % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		_fail(
			"正式世界数据无效：%s:%d %s" % [
				path, parser.get_error_line(), parser.get_error_message(),
			]
		)
		return {}
	if not parser.data is Dictionary:
		_fail("正式世界数据根节点必须是对象：%s" % path)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
