class_name FormalWorldEconomyService
extends RefCounted
## Formal 1900 world economy. Political existence is injected by the formal
## composition root; this service owns only economic aggregates and their mapping.
## One economy may cover several runtime polities, as with the Australian colonies.
## The retired two-country/eight-region Alpha world is never loaded here.

const HOURS_PER_DAY: int = 24
const BASIS_POINTS: int = 10000
const HISTORY_LIMIT: int = 366
const MAX_SHIPMENTS_PER_DAY: int = 96
const MAX_SUPPLIERS_PER_SHORTAGE: int = 4
const EXPECTED_MAJOR_ROSTER_COUNT: int = 50
const PRIMARY_PLAYABLE_LIMIT: int = 30
const STATE_SCHEMA_ID: String = "formal_world_economy_state_v6"

var initialization_error: String = ""
## Internal authoritative containers. FormalWorldSimulation never exposes this
## service; consumers receive FormalWorldEconomyView copies only.
var market_states: Dictionary = {}
var economy_polity_ids: Dictionary = {}
var economy_by_polity_id: Dictionary = {}
var routes: Array[Dictionary] = []
var shipments: Array[Dictionary] = []
var history: Array[Dictionary] = []

var _authoritative_hour_source: Callable = Callable()
var total_hour: int:
	get:
		assert(
			_authoritative_hour_source.is_valid(),
			"FormalWorldEconomyService requires the formal simulation hour source"
		)
		return int(_authoritative_hour_source.call())

var _commodities: Dictionary = {}
var _routes_by_country: Dictionary = {}
var _crosswalk_records: Dictionary = {}
## Non-authoritative calculation cache pinned to the injected static and
## population fingerprints. It avoids per-day copies and is never persisted.
var _calculation_inputs: Dictionary = {}
var _political_registry: RuntimePoliticalEntityView = null
var _market_registry: FormalWorldMarketView = null
var _static_evidence: FormalWorldEconomicStaticView = null
var _population_input: FormalWorldPopulationInputView = null
var _next_shipment_sequence: int = 1
var _last_day_index: int = -1
var _political_unit_count: int = 0
var _state_revision: int = 0
var _configured: bool = false


func configure(
	political_registry: RuntimePoliticalEntityView,
	market_registry: FormalWorldMarketView,
	static_evidence: FormalWorldEconomicStaticView,
	population_input: FormalWorldPopulationInputView
) -> bool:
	if _configured:
		return _fail("Formal economy is already initialized")
	market_states.clear()
	economy_polity_ids.clear()
	economy_by_polity_id.clear()
	routes.clear()
	shipments.clear()
	history.clear()
	_routes_by_country.clear()
	_crosswalk_records.clear()
	_calculation_inputs.clear()
	_commodities.clear()
	_last_day_index = -1
	_next_shipment_sequence = 1
	_political_unit_count = 0
	_political_registry = political_registry
	_market_registry = market_registry
	_static_evidence = static_evidence
	_population_input = population_input
	_state_revision = 0
	initialization_error = ""
	if _political_registry == null or not _political_registry.is_configured():
		return _fail("正式经济需要已配置的 runtime political registry")
	if _market_registry == null or not _market_registry.is_configured():
		return _fail("正式经济需要已配置的 market registry")
	if _static_evidence == null or not _static_evidence.is_configured():
		return _fail("正式经济需要已配置的静态经济证据")
	if _population_input == null or not _population_input.is_configured():
		return _fail("正式经济需要已配置的只读人口输入")
	_political_unit_count = _political_registry.entity_count()
	if not _load_injected_inputs():
		return false
	for record: Dictionary in _static_evidence.countries():
		_cache_calculation_input(record)
		_initialize_country(record)
	_build_routes()
	if market_states.size() != EXPECTED_MAJOR_ROSTER_COUNT:
		return _fail(
			"正式市场目录应为%d，当前为%d：%s" % [
				EXPECTED_MAJOR_ROSTER_COUNT,
				market_states.size(),
				initialization_error,
			]
		)
	if _market_registry.market_count() != market_states.size():
		return _fail("Market registry 与经济市场状态不一致")
	if _political_unit_count <= market_states.size():
		return _fail("世界政治单元目录不得等同于主要政权目录")
	if _commodities.is_empty():
		return _fail("正式世界商品目录为空")
	_configured = _validate_state()
	return _configured


func bind_runtime_political_view(
	political_registry: RuntimePoliticalEntityView
) -> bool:
	if political_registry == null or not political_registry.is_configured():
		return false
	if (
		_political_unit_count > 0
		and _political_unit_count != political_registry.entity_count()
	):
		return false
	_political_registry = political_registry
	_political_unit_count = political_registry.entity_count()
	return true


func is_configured() -> bool:
	return _configured


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
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		var state := market_states[market_id] as Dictionary
		var static_record := _calculation_inputs[economy_id] as Dictionary
		population += int(static_record.get("population", 0))
		var totals := state.get("daily_totals", {}) as Dictionary
		demand += float(totals.get("demand_units", 0.0))
		consumed += float(totals.get("consumed_units", 0.0))
		unmet += float(totals.get("unmet_units", 0.0))
		if str(static_record.get("admission_status", "bounded_estimate")) == "verified":
			verified += 1
		else:
			bounded += 1
		match str(static_record.get("playability_tier", "")):
			"leading_power": leading_power_count += 1
			"great_power": great_power_count += 1
			"major_power": major_power_count += 1
			"primary_playable": primary_playable_count += 1
			"secondary_roster": secondary_roster_count += 1
	return {
		"total_hour": total_hour,
		# Compatibility alias. This is the high-detail economy roster, not world total.
		"country_count": market_states.size(),
		"major_economy_count": market_states.size(),
		"market_count": market_states.size(),
		"market_revision": _market_registry.revision(),
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
	if _market_registry.market_id_for_economic_aggregate(economy_id).is_empty():
		economy_id = economy_entity_for_polity(entity_id)
	var market_id := _market_registry.market_id_for_economic_aggregate(economy_id)
	var state := market_states.get(market_id, {}) as Dictionary
	if state.is_empty():
		return {}
	var result := _project_country_state(economy_id, state)
	result["economic_aggregate_id"] = economy_id
	result["market_id"] = market_id
	result["top_shortages"] = _top_country_shortages(state, 8)
	result["active_shipments"] = _shipment_count_for(economy_id)
	return result


func has_detailed_economy(entity_id: String) -> bool:
	return not economy_entity_for_polity(entity_id).is_empty()


func economy_entity_for_polity(polity_id: String) -> String:
	return str(economy_by_polity_id.get(polity_id, ""))


func polity_ids_for_economy(economy_id: String) -> Array[String]:
	return DataRecordUtils.to_string_array(economy_polity_ids.get(economy_id, []))


func formal_verified_countries() -> Array[Dictionary]:
	return _static_evidence.formal_verified_countries()


func market_id_for_economic_aggregate(economic_aggregate_id: String) -> String:
	return _market_registry.market_id_for_economic_aggregate(economic_aggregate_id)


func economic_aggregate_id_for_market(market_id: String) -> String:
	return _market_registry.economic_aggregate_id_for_market(market_id)


func _has_economic_aggregate(economic_aggregate_id: String) -> bool:
	var market_id := _market_registry.market_id_for_economic_aggregate(
		economic_aggregate_id
	)
	return not market_id.is_empty() and market_states.has(market_id)


func _economic_aggregate_ids() -> Array[String]:
	var result: Array[String] = []
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var economic_aggregate_id := _market_registry.economic_aggregate_id_for_market(
			market_id
		)
		if not economic_aggregate_id.is_empty() and market_states.has(market_id):
			result.append(economic_aggregate_id)
	return result


func read_only_snapshot() -> Dictionary:
	var summaries: Dictionary = {}
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		summaries[economy_id] = country_summary(economy_id)
	return {
		"schema_id": "formal_world_economy_observation_v2",
		"domain_owner": "FormalWorldEconomyService",
		"state_revision": _state_revision,
		"total_hour": total_hour,
		"fact_sources": {
			"static_evidence_revision": _static_evidence.revision(),
			"static_evidence_fingerprint": _static_evidence.fingerprint(),
			"population_revision": _population_input.revision(),
			"population_fingerprint": _population_input.fingerprint(),
			"market_revision": _market_registry.revision(),
			"market_mapping_fingerprint": _market_registry.mapping_fingerprint(),
		},
		"market_registry": {
			"revision": _market_registry.revision(),
			"mapping_fingerprint": _market_registry.mapping_fingerprint(),
			"markets": _market_registry.markets(),
		},
		"economic_aggregate_states": _economic_aggregate_observation_snapshot(),
		"market_states": _market_observation_snapshot(),
		# Compatibility projection for existing product/UI consumers. It is derived
		# from explicit aggregate-to-market mapping and is never persisted as v6.
		"country_states": _projected_country_states(),
		"economy_polity_ids": economy_polity_ids.duplicate(true),
		"economy_by_polity_id": economy_by_polity_id.duplicate(true),
		"routes": routes.duplicate(true),
		"shipments": shipments.duplicate(true),
		"history": history.duplicate(true),
		"last_day_index": _last_day_index,
		"world_summary": world_summary(),
		"country_summaries": summaries,
	}


func legacy_regression_snapshot() -> Dictionary:
	## The golden harness hashes the trusted v4 shape so formula regressions stay
	## detectable while the production save schema excludes static/derived data.
	return {
		"schema_id": "formal_world_economy_state_v4",
		"total_hour": total_hour,
		"country_states": _projected_country_states(),
		"shipments": shipments.duplicate(true),
		"history": _legacy_history_snapshot(),
		"next_shipment_sequence": _next_shipment_sequence,
		"last_day_index": _last_day_index,
	}


func _legacy_history_snapshot() -> Array[Dictionary]:
	var result := DataRecordUtils.to_dictionary_array(history)
	for row: Dictionary in result:
		row.erase("market_count")
		row.erase("market_revision")
		var shortages := DataRecordUtils.to_dictionary_array(
			row.get("top_shortages", [])
		)
		for shortage: Dictionary in shortages:
			shortage.erase("market_id")
		row["top_shortages"] = shortages
	return result


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": STATE_SCHEMA_ID,
		"total_hour": total_hour,
		"static_evidence": {
			"revision": _static_evidence.revision(),
			"fingerprint": _static_evidence.fingerprint(),
		},
		"population_input": {
			"revision": _population_input.revision(),
			"fingerprint": _population_input.fingerprint(),
		},
		"market_states": _market_states_snapshot(),
		"shipments": shipments.duplicate(true),
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
			"formal_world_economy_state_v4",
			"formal_world_economy_state_v5",
			STATE_SCHEMA_ID,
		]
		or not state.get("shipments", []) is Array
	):
		return false
	var saved_state_field := (
		"market_states" if schema_id == STATE_SCHEMA_ID else "country_states"
	)
	if not state.get(saved_state_field, {}) is Dictionary:
		return false
	if schema_id == STATE_SCHEMA_ID and not _references_match(state):
		return false
	var saved_total_hour := int(state.get("total_hour", -1))
	if saved_total_hour < 0 or saved_total_hour != total_hour:
		return false
	var saved_states: Dictionary = (
		(state.get(saved_state_field, {}) as Dictionary).duplicate(true)
	)
	if saved_states.size() != market_states.size():
		return false
	var candidate_market_states: Dictionary = {}
	for raw_id: Variant in saved_states:
		var saved_id := str(raw_id)
		if not saved_states[saved_id] is Dictionary:
			return false
		var market_id := saved_id
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		if schema_id != STATE_SCHEMA_ID:
			economy_id = saved_id
			market_id = _market_registry.market_id_for_economic_aggregate(economy_id)
		if market_id.is_empty() or not market_states.has(market_id):
			return false
		var saved_economic_state := saved_states[saved_id] as Dictionary
		if schema_id == STATE_SCHEMA_ID and (
			str(saved_economic_state.get("market_id", "")) != market_id
			or str(
				saved_economic_state.get("source_economic_aggregate_id", "")
			) != economy_id
		):
			return false
		if schema_id != STATE_SCHEMA_ID and not _legacy_static_matches(
			economy_id, saved_economic_state, schema_id
		):
			return false
		candidate_market_states[market_id] = _compose_market_state(
			market_id, saved_economic_state
		)
	var candidate_shipments: Array[Dictionary] = (
		DataRecordUtils.to_dictionary_array(state.get("shipments", []))
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
	if not _validate_candidate_state(
		candidate_market_states,
		candidate_shipments,
		candidate_last_day_index,
		saved_total_hour
	):
		return false
	market_states = candidate_market_states
	shipments = candidate_shipments
	history.clear()
	_next_shipment_sequence = candidate_next_shipment_sequence
	_last_day_index = candidate_last_day_index
	_state_revision += 1
	return true
func _load_injected_inputs() -> bool:
	for commodity: Dictionary in _static_evidence.commodities():
		var commodity_id := str(commodity.get("commodity_id", ""))
		if not commodity_id.is_empty():
			_commodities[commodity_id] = commodity.duplicate(true)
	for record: Dictionary in _static_evidence.crosswalk_records():
		var economy_id := str(record.get("economy_entity_id", ""))
		var polity_ids := DataRecordUtils.to_string_array(record.get("polity_ids", []))
		if economy_id.is_empty() or polity_ids.is_empty():
			return _fail("主要经济体交叉表记录缺少ID")
		for polity_id: String in polity_ids:
			if _political_registry.runtime_id_for_source(polity_id).is_empty():
				return _fail("交叉表引用未知政治单元：%s" % polity_id)
		_crosswalk_records[economy_id] = record.duplicate(true)
	return not _commodities.is_empty()


func _initialize_country(record: Dictionary) -> void:
	var entity_id := str(record.get("entity_id", ""))
	if entity_id.is_empty():
		return
	var market_id := _market_registry.market_id_for_economic_aggregate(entity_id)
	if market_id.is_empty() or market_states.has(market_id):
		_fail("主要经济聚合缺少唯一 Market identity：%s" % entity_id)
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
	var population_fact := _population_input.fact(entity_id)
	var population_record := population_fact.get("population", {}) as Dictionary
	var income_record := record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary
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
	market_states[market_id] = {
		"market_id": market_id,
		"source_economic_aggregate_id": entity_id,
		"inventory": inventory,
		"prices": prices,
		"daily_metrics": daily_metrics,
		"daily_totals": {},
		"gold_reserve_units": _opening_gold_units(
			record, int(population_record.get("value", 0))
		),
		"trade_balance_centimes": 0,
		"tariff_revenue_centimes": 0,
		"last_settlement_hour": 0,
	}


	economy_polity_ids[entity_id] = polity_ids.duplicate()
	for polity_id: String in polity_ids:
		economy_by_polity_id[polity_id] = entity_id


func _cache_calculation_input(record: Dictionary) -> void:
	var economy_id := str(record.get("entity_id", ""))
	if economy_id.is_empty():
		return
	var income := record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary
	var coverage := record.get("coverage", {}) as Dictionary
	var tier := _tier_for_rank(int(record.get("rank", 0)))
	_calculation_inputs[economy_id] = {
		"rank": int(record.get("rank", 0)),
		"population": _population_input.population(economy_id),
		"playability_tier": str(tier.get("id", "secondary_roster")),
		"income_per_capita": int(income.get("value", 0)),
		"production": (record.get("production", {}) as Dictionary).duplicate(true),
		"admission_status": str(coverage.get("status", "bounded_estimate")),
	}


func _resolve_polity_ids(economy_id: String) -> Array[String]:
	var direct_runtime_id := _political_registry.runtime_id_for_source(economy_id)
	if not direct_runtime_id.is_empty():
		return [direct_runtime_id]
	var crosswalk := _crosswalk_records.get(economy_id, {}) as Dictionary
	var result: Array[String] = []
	for source_id: String in DataRecordUtils.to_string_array(
		crosswalk.get("polity_ids", [])
	):
		var runtime_id := _political_registry.runtime_id_for_source(source_id)
		if runtime_id.is_empty():
			return []
		result.append(runtime_id)
	return result


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
	for record: Dictionary in _static_evidence.maritime_corridors():
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
	for record: Dictionary in _static_evidence.river_corridors():
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
		or not _has_economic_aggregate(origin)
		or not _has_economic_aggregate(destination)
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
	for economy_id: String in _economic_aggregate_ids():
		_settle_country(economy_id, settlement_hour)
	_schedule_shortage_shipments(settlement_hour)
	_last_day_index = day_index
	var summary := world_summary()
	# Bulk advancement must record the boundary being settled, not the final
	# composition-root hour that is visible while the range is processed.
	summary["total_hour"] = settlement_hour
	summary["day_index"] = day_index
	history.append(summary)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	_state_revision += 1


func _settle_country(entity_id: String, settlement_hour: int) -> void:
	var market_id := _market_registry.market_id_for_economic_aggregate(entity_id)
	var state := market_states[market_id] as Dictionary
	var calculation_input := _calculation_inputs[entity_id] as Dictionary
	var population := int(calculation_input.get("population", 0))
	var income_per_capita := int(calculation_input.get("income_per_capita", 0))
	var production := calculation_input.get("production", {}) as Dictionary
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
	market_states[market_id] = state


func _schedule_shortage_shipments(settlement_hour: int) -> void:
	var created := 0
	var receiver_ids := _economic_aggregate_ids()
	receiver_ids.sort()
	for receiver_id: String in receiver_ids:
		if created >= MAX_SHIPMENTS_PER_DAY:
			break
		var receiver_market_id := (
			_market_registry.market_id_for_economic_aggregate(receiver_id)
		)
		var receiver := market_states[receiver_market_id] as Dictionary
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
				var origin_market_id := (
					_market_registry.market_id_for_economic_aggregate(origin_id)
				)
				var origin := market_states[origin_market_id] as Dictionary
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
				market_states[origin_market_id] = origin
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
		if _has_economic_aggregate(destination_id):
			var destination_market_id := (
				_market_registry.market_id_for_economic_aggregate(destination_id)
			)
			var destination := market_states[destination_market_id] as Dictionary
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
			market_states[destination_market_id] = destination
		if _has_economic_aggregate(origin_id):
			var origin_market_id := (
				_market_registry.market_id_for_economic_aggregate(origin_id)
			)
			var origin := market_states[origin_market_id] as Dictionary
			origin["trade_balance_centimes"] = int(
				origin.get("trade_balance_centimes", 0)
			) + value
			market_states[origin_market_id] = origin
		shipments.remove_at(index)


func _candidate_suppliers(receiver_id: String, commodity_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_index: Variant in _routes_by_country.get(receiver_id, []) as Array:
		var route := routes[int(raw_index)] as Dictionary
		var origin := str(route.get("from", ""))
		var destination := str(route.get("to", ""))
		var other := destination if origin == receiver_id else origin
		if other == receiver_id or not _has_economic_aggregate(other):
			continue
		var other_market_id := _market_registry.market_id_for_economic_aggregate(other)
		var state := market_states[other_market_id] as Dictionary
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


func _top_country_shortages(state: Dictionary, limit: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var metrics := state.get("daily_metrics", {}) as Dictionary
	for raw_id: Variant in metrics:
		var commodity_id := str(raw_id)
		var row := metrics[commodity_id] as Dictionary
		var unmet := float(row.get("unmet", 0.0))
		if unmet > 0.0001:
			rows.append({
				"entity_id": str(
					state.get("source_economic_aggregate_id", "")
				),
				"market_id": str(state.get("market_id", "")),
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
	for raw_state: Variant in market_states.values():
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
		market_states,
		shipments,
		_last_day_index,
		total_hour
	)


func _validate_candidate_state(
	candidate_market_states: Dictionary,
	candidate_shipments: Array[Dictionary],
	candidate_last_day_index: int,
	expected_total_hour: int
) -> bool:
	if (
		_political_registry == null
		or not _political_registry.is_configured()
		or _market_registry == null
		or not _market_registry.is_configured()
		or _political_unit_count != _political_registry.entity_count()
	):
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
	if (
		candidate_market_states.size() != EXPECTED_MAJOR_ROSTER_COUNT
		or candidate_market_states.size() != _market_registry.market_count()
	):
		return false
	for raw_id: Variant in candidate_market_states:
		var market_id := str(raw_id)
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		if economy_id.is_empty() or not candidate_market_states[market_id] is Dictionary:
			return false
		var state := candidate_market_states[market_id] as Dictionary
		var polity_ids := polity_ids_for_economy(economy_id)
		if (
			str(state.get("market_id", "")) != market_id
			or str(state.get("source_economic_aggregate_id", "")) != economy_id
			or _population_input.population(economy_id) <= 0
			or _static_evidence.country(economy_id).is_empty()
			or polity_ids.is_empty()
		):
			return false
		for polity_id: String in polity_ids:
			if (
				not _political_registry.has_entity(polity_id)
				or str(economy_by_polity_id.get(polity_id, "")) != economy_id
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
			or not candidate_market_states.has(
				_market_registry.market_id_for_economic_aggregate(origin_id)
			)
			or not candidate_market_states.has(
				_market_registry.market_id_for_economic_aggregate(destination_id)
			)
			or dispatch_hour < 0
			or dispatch_hour > expected_total_hour
			or arrival_hour <= dispatch_hour
		):
			return false
	return true


func _same_string_set(left: Array[String], right: Array[String]) -> bool:
	var sorted_left := left.duplicate()
	var sorted_right := right.duplicate()
	sorted_left.sort()
	sorted_right.sort()
	return sorted_left == sorted_right


func _references_match(state: Dictionary) -> bool:
	if (
		not state.get("static_evidence", {}) is Dictionary
		or not state.get("population_input", {}) is Dictionary
	):
		return false
	var static_reference := state.get("static_evidence", {}) as Dictionary
	var population_reference := state.get("population_input", {}) as Dictionary
	return (
		str(static_reference.get("revision", "")) == _static_evidence.revision()
		and str(static_reference.get("fingerprint", ""))
		== _static_evidence.fingerprint()
		and str(population_reference.get("revision", ""))
		== _population_input.revision()
		and str(population_reference.get("fingerprint", ""))
		== _population_input.fingerprint()
	)


func _market_states_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var state := market_states[market_id] as Dictionary
		var snapshot := _dynamic_state_from(state)
		snapshot["market_id"] = market_id
		snapshot["source_economic_aggregate_id"] = str(
			state.get("source_economic_aggregate_id", "")
		)
		result[market_id] = snapshot
	return result


func _market_observation_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var state := market_states[market_id] as Dictionary
		var snapshot := {
			"market_id": market_id,
			"source_economic_aggregate_id": str(
				state.get("source_economic_aggregate_id", "")
			),
		}
		for key: String in [
			"inventory", "prices", "daily_metrics", "daily_totals",
			"last_settlement_hour",
		]:
			var value: Variant = state.get(key)
			snapshot[key] = (
				value.duplicate(true) if value is Dictionary or value is Array else value
			)
		result[market_id] = snapshot
	return result


func _economic_aggregate_observation_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for economy_id: String in _economic_aggregate_ids():
		var market_id := _market_registry.market_id_for_economic_aggregate(economy_id)
		var state := market_states[market_id] as Dictionary
		result[economy_id] = {
			"economic_aggregate_id": economy_id,
			"pricing_market_id": market_id,
			"gold_reserve_units": float(state.get("gold_reserve_units", 0.0)),
			"trade_balance_centimes": int(
				state.get("trade_balance_centimes", 0)
			),
			"tariff_revenue_centimes": int(
				state.get("tariff_revenue_centimes", 0)
			),
		}
	return result


func _projected_country_states() -> Dictionary:
	var result: Dictionary = {}
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		result[economy_id] = _project_country_state(
			economy_id, market_states[market_id] as Dictionary
		)
	return result


func _project_country_state(economy_id: String, dynamic: Dictionary) -> Dictionary:
	var record := _static_evidence.country(economy_id)
	var population_fact := _population_input.fact(economy_id)
	var population_record := population_fact.get("population", {}) as Dictionary
	var urban_record := (
		population_fact.get("urban_population_share_bp", {}) as Dictionary
	)
	var income_record := (
		record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary
	)
	var coverage := record.get("coverage", {}) as Dictionary
	var rank := int(record.get("rank", 0))
	var tier := _tier_for_rank(rank)
	var result := {
		"entity_id": economy_id,
		"polity_ids": polity_ids_for_economy(economy_id),
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
		"production": (
			(record.get("production", {}) as Dictionary).duplicate(true)
		),
		"infrastructure": (
			(record.get("infrastructure", {}) as Dictionary).duplicate(true)
		),
		"overall_confidence_bp": int(record.get("overall_confidence_bp", 0)),
		"admission_status": str(coverage.get("status", "bounded_estimate")),
		"verified_dimensions": (
			coverage.get("verified_dimensions", []) as Array
		).duplicate(),
	}
	for key: String in [
		"inventory",
		"prices",
		"daily_metrics",
		"daily_totals",
		"gold_reserve_units",
		"trade_balance_centimes",
		"tariff_revenue_centimes",
		"last_settlement_hour",
	]:
		var value: Variant = dynamic.get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func _dynamic_state_from(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in [
		"inventory",
		"prices",
		"daily_metrics",
		"daily_totals",
		"gold_reserve_units",
		"trade_balance_centimes",
		"tariff_revenue_centimes",
		"last_settlement_hour",
	]:
		if state.has(key):
			var value: Variant = state[key]
			result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func _compose_market_state(market_id: String, saved: Dictionary) -> Dictionary:
	var result := (market_states[market_id] as Dictionary).duplicate(true)
	var dynamic := _dynamic_state_from(saved)
	for key_value: Variant in dynamic:
		result[str(key_value)] = dynamic[key_value]
	return result


func _legacy_static_matches(
	economy_id: String, saved: Dictionary, schema_id: String
) -> bool:
	var market_id := _market_registry.market_id_for_economic_aggregate(economy_id)
	var expected := _project_country_state(
		economy_id, market_states[market_id] as Dictionary
	)
	var saved_polity_ids := DataRecordUtils.to_string_array(
		saved.get("polity_ids", [])
	)
	if schema_id == "formal_world_economy_state_v4" and saved_polity_ids.is_empty():
		return false
	if not saved_polity_ids.is_empty():
		var normalized: Array[String] = []
		for saved_id: String in saved_polity_ids:
			var runtime_id := saved_id
			if schema_id != "formal_world_economy_state_v4":
				runtime_id = _political_registry.runtime_id_for_source(saved_id)
				if runtime_id.is_empty() and _political_registry.has_entity(saved_id):
					runtime_id = saved_id
			if runtime_id.is_empty():
				return false
			normalized.append(runtime_id)
		if not _same_string_set(
			normalized, DataRecordUtils.to_string_array(expected.get("polity_ids", []))
		):
			return false
	for key: String in [
		"rank",
		"primary_iso3",
		"population",
		"population_bounds",
		"income_per_capita",
		"income_bounds",
		"urban_share_bp",
		"production",
		"infrastructure",
	]:
		if saved.has(key) and saved[key] != expected.get(key):
			return false
	return true


func _fail(message: String) -> bool:
	initialization_error = message
	return false
