class_name FormalWorldEconomyState
extends RefCounted
## Current market results, detached reads and persistence. No settlement algorithms.
## Market identities and historical inputs remain supplied by the composition root.

const HOURS_PER_DAY: int = 24
const BASIS_POINTS: int = 10000
const PRIMARY_PLAYABLE_LIMIT: int = 30
const STATE_SCHEMA_ID: String = "formal_world_economy_state_v6"

var initialization_error: String = ""
## Internal authoritative containers. FormalWorldApplication never exposes this
## state; consumers receive FormalWorldEconomyView copies only.
var market_states: Dictionary = {}
# Only markets that have received personal payments have custody accounts.
var _personal_sale_accounts: Dictionary = {}
# WorldState owns personal state. This query reference must not retain an old
# personal/native economy after installing a restored world.
var _personal_economy_ref: WeakRef
var _personal_economy: FormalPersonalEconomyState:
	get:
		return _personal_economy_ref.get_ref() as FormalPersonalEconomyState if _personal_economy_ref != null else null
	set(value):
		_personal_economy_ref = weakref(value) if value != null else null
var _native_economy_ref: WeakRef
var _personal_ledger: FormalLedgerState
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
			"FormalWorldEconomyState requires the formal simulation hour source"
		)
		return int(_authoritative_hour_source.call())

var _commodities: Dictionary = {}
var _crosswalk_records: Dictionary = {}
## Prepared immutable economic lookup shared by reads and settlement. Current
## population is queried separately; it must never be cached in this lookup.
var _resolved_inputs: Dictionary = {}
## Non-authoritative settled-day projection cache. Rows are derived only from
## daily_metrics, are never persisted, and can be rebuilt deterministically.
var _daily_shortage_rows_by_market_id: Dictionary = {}
var _political_registry: RuntimePoliticalEntityView = null
var _market_registry: FormalWorldMarketView = null
var _static_evidence: FormalWorldEconomicStaticView = null
var _population_input: FormalWorldPopulationInputView = null
var _population_state: FormalWorldPopulationState = null
var _next_shipment_sequence: int = 1
var _last_day_index: int = -1
var _political_unit_count: int = 0
var _state_revision: int = 0
var _configured: bool = false


var _inputs_ready: bool = false


func configure(
	political_registry: RuntimePoliticalEntityView,
	market_registry: FormalWorldMarketView,
	static_evidence: FormalWorldEconomicStaticView,
	population_input: FormalWorldPopulationInputView,
	population_state: FormalWorldPopulationState = null
) -> bool:
	if _configured:
		return _fail("Formal economy is already initialized")
	market_states.clear()
	economy_polity_ids.clear()
	economy_by_polity_id.clear()
	routes.clear()
	shipments.clear()
	history.clear()
	_crosswalk_records.clear()
	_resolved_inputs.clear()
	_daily_shortage_rows_by_market_id.clear()
	_commodities.clear()
	_last_day_index = -1
	_next_shipment_sequence = 1
	_political_unit_count = 0
	_political_registry = political_registry
	_market_registry = market_registry
	_static_evidence = static_evidence
	_population_input = population_input
	_population_state = population_state
	_state_revision = 0
	initialization_error = ""
	_inputs_ready = false
	if _political_registry == null or not _political_registry.is_configured():
		return _fail("正式经济需要已配置的 runtime political registry")
	if _market_registry == null or not _market_registry.is_configured():
		return _fail("正式经济需要已配置的 market registry")
	if _static_evidence == null or not _static_evidence.is_configured():
		return _fail("正式经济需要已配置的静态经济证据")
	if _population_input == null or not _population_input.is_configured():
		return _fail("正式经济需要已配置的只读人口输入")
	if _population_state != null:
		for record: Dictionary in _static_evidence.countries():
			var economy_id := str(record["entity_id"])
			if _population_state.population(economy_id) != _population_input.population(economy_id):
				return _fail("Current initial Population differs from demographic evidence")
	_political_unit_count = _political_registry.entity_count()
	if not _load_injected_inputs():
		return false
	for record: Dictionary in _static_evidence.countries():
		_cache_resolved_input(record)
	_inputs_ready = true
	return true


func validate_initial_state() -> bool:
	if not _inputs_ready or _configured:
		return _fail("Formal economy initial state cannot be validated")
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
		var static_record := _resolved_inputs[economy_id] as Dictionary
		population += current_population(economy_id)
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


# A generated collective custody rule over the existing finite market stock.
# This is not a historical retailer, a city inventory or an extra price system.
func bind_personal_ledger(ledger: FormalLedgerState) -> void:
	_personal_ledger = ledger


func commodity_for_person(commodity_id: String, market_id: String = "") -> Dictionary:
	var value := _commodities.get(commodity_id,{}) as Dictionary
	if value.is_empty(): return {}
	var category := str(value.get("category",""))
	var item := {"commodity_id":commodity_id,"name_zh":str(value.get("name_zh",commodity_id)),"unit_name_zh":str(value.get("unit_name_zh","")),"consumable":category in ["agricultural_food","processed_food","colonial_consumable","household_consumable"],"sale_supported":category != "local_service" and not str(value.get("unit_name_zh","")).is_empty()}

	if not market_id.is_empty():
		var state := market_states.get(market_id,{}) as Dictionary
		item["price"] = (state.get("prices",{}) as Dictionary).get(commodity_id)
		item["inventory"] = (state.get("inventory",{}) as Dictionary).get(commodity_id)
	return item


static func personal_sale_account_id(market_id: String) -> String:
	return "account:market_receipts:"+market_id


func personal_sale_accounts() -> Dictionary:
	return _personal_sale_accounts.duplicate(true)


func personal_purchase_quote(market_id: String, commodity_id: String, quantity_milli: int, buyer_account_id: String, accessible_aggregate_id: String) -> Dictionary:
	if _personal_economy != null and _personal_economy.manages_account(buyer_account_id):
		return {"success": false, "error": "此人物由原生订单及地点库存管理，不能从统计库存出售。"}
	var item := commodity_for_person(commodity_id)
	var state := market_states.get(market_id,{}) as Dictionary
	var reason := ""
	if _personal_ledger == null or state.is_empty(): reason = "没有正式市场或收款关系。"
	elif accessible_aggregate_id.is_empty() or economic_aggregate_id_for_market(market_id) != accessible_aggregate_id: reason = "人物所在地不能访问此统计市场；浏览资料不提供远程购买。"
	elif item.is_empty() or not bool(item.sale_supported): reason = "该项是服务或缺少商品单位，不能作为持有物品购买。"
	elif quantity_milli <= 0 or quantity_milli > FormalLedgerState.MAX_AMOUNT: reason = "购买数量必须为正，精确到商品单位的千分之一。"
	if not reason.is_empty(): return {"success":false,"error":reason}
	var stock: Variant = (state.get("inventory",{}) as Dictionary).get(commodity_id)
	var price: Variant = (state.get("prices",{}) as Dictionary).get(commodity_id)
	if stock == null or price == null or not is_finite(float(stock)) or float(stock) < 0 or typeof(price) != TYPE_INT or int(price) <= 0:
		return {"success":false,"error":"市场没有有效库存或当前价格。"}
	# One calibrated model centime charges one existing simulation minor unit.
	# Round a fractional minor unit upward; never charge zero for positive goods.
	if quantity_milli > (FormalLedgerState.MAX_AMOUNT-999)/int(price): return {"success":false,"error":"应付金额超过账务整数范围。"}
	var amount: int = (quantity_milli*int(price)+999)/1000
	if float(quantity_milli)/1000.0 > float(stock): return {"success":false,"error":"市场可售库存不足。","amount":amount,"unit_price":int(price)}
	var buyer := _personal_ledger.account(buyer_account_id)
	if buyer.is_empty() or str(buyer.get("role","")) != "personal_cash": return {"success":false,"error":"买方个人账户不存在。"}
	if int(buyer.balance) < amount: return {"success":false,"error":"个人现金不足；需要 %d 模拟单位。" % amount,"amount":amount,"unit_price":int(price)}
	var seller_account_id := personal_sale_account_id(market_id)
	var seller := _personal_ledger.account(seller_account_id)
	if not seller.is_empty() and (str(seller.get("owner_id","")) != market_id or str(seller.get("role","")) != "market_receipts" or int(seller.balance) > FormalLedgerState.MAX_AMOUNT-amount):
		return {"success":false,"error":"市场收款账户无效或余额超过范围。"}
	return {"success":true,"market_id":market_id,"seller_id":market_id,"seller_account_id":seller_account_id,"buyer_account_id":buyer_account_id,"accessible_aggregate_id":accessible_aggregate_id,"commodity_id":commodity_id,"quantity_milli":quantity_milli,"unit_price":int(price),"amount":amount,"name_zh":item.name_zh,"unit_name_zh":item.unit_name_zh,"basis":"GENERATED_SIMULATION_ASSUMPTION"}


func purchase_from_existing_stock(quote: Dictionary, transaction_id: String, reference_id: String, minute: int) -> Dictionary:
	# The personal owner calls this immediately after a fresh quote, on the same
	# formal action path. No asynchronous mutation can interleave this operation.
	if _personal_ledger == null: return {"success":false,"error":"正式账务尚未绑定。"}
	if not _personal_ledger.transaction(transaction_id).is_empty(): return {"success":false,"error":"此购买编号已处理，不重复扣减库存。"}
	if not bool(quote.get("success",false)): return {"success":false,"error":"没有有效购买报价。"}
	var fresh := personal_purchase_quote(str(quote.market_id),str(quote.commodity_id),int(quote.quantity_milli),str(quote.buyer_account_id),str(quote.accessible_aggregate_id))
	if not bool(fresh.get("success",false)): return fresh
	if int(fresh.amount) != int(quote.amount) or int(fresh.unit_price) != int(quote.unit_price): return {"success":false,"error":"当前价格已改变，请重新查看报价。"}
	var market_id := str(fresh.market_id)
	var account_id := str(fresh.seller_account_id)
	if _personal_ledger.account(account_id).is_empty():
		if not _personal_ledger.open_account(account_id,market_id,"market_receipts"):
			return {"success":false,"error":_personal_ledger.error}
	_personal_sale_accounts[market_id] = {"market_id":market_id,"account_id":account_id,"inventory_owner_id":market_id,"stock_scope":"existing_market_inventory","basis":"GENERATED_SIMULATION_ASSUMPTION"}
	if not _personal_ledger.transfer(transaction_id,str(fresh.buyer_account_id),account_id,int(fresh.amount),minute,"purchase",reference_id):
		return {"success":false,"error":_personal_ledger.error}
	var inventory := (market_states[market_id] as Dictionary).inventory as Dictionary
	inventory[str(fresh.commodity_id)] = float(inventory[str(fresh.commodity_id)])-float(fresh.quantity_milli)/1000.0
	_state_revision += 1
	return {"success":true}


func read_only_market_rows(market_id: String, limit: int, offset: int) -> Array[Dictionary]:
	var state := market_states.get(market_id,{}) as Dictionary
	var inventory := state.get("inventory",{}) as Dictionary
	var prices := state.get("prices",{}) as Dictionary
	var ids := inventory.keys()
	for commodity_id: String in prices:
		if not inventory.has(commodity_id): ids.append(commodity_id)
	ids.sort()
	var rows: Array[Dictionary] = []
	for index: int in range(maxi(0,offset),mini(ids.size(),maxi(0,offset)+maxi(0,limit))):
		var id := str(ids[index])
		var commodity := _commodities.get(id,{}) as Dictionary
		rows.append({"commodity_id":id,"name_zh":str(commodity.get("name_zh","名称未记录")),"inventory":inventory.get(id),"price":prices.get(id),"unit_name_zh":str(commodity.get("unit_name_zh","未记录"))})
	return rows


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
		"domain_owner": "FormalWorldEconomyState",
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


func read_only_presentation_snapshot() -> Dictionary:
	# Panels and map colours need summaries and market identities, not copied
	# commodity inventories, shipments, routes or the entire settlement history.
	var summaries: Dictionary = {}
	var aggregates: Dictionary = {}
	var markets: Dictionary = {}
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		var record := _resolved_inputs[economy_id] as Dictionary
		var rank := int(record.get("rank", 0))
		var tier := _tier_for_rank(rank)
		var population_fact := _population_input.fact(economy_id)
		summaries[economy_id] = {
			"economic_aggregate_id": economy_id, "market_id": market_id,
			"rank": rank, "playability_tier": tier.id, "playability_tier_zh": tier.name_zh,
			"primary_playable": rank > 0 and rank <= PRIMARY_PLAYABLE_LIMIT,
			"population": current_population(economy_id),
			"income_per_capita": int(record.get("income_per_capita", 0)),
			"urban_share_bp": int((population_fact.get("urban_population_share_bp", {}) as Dictionary).get("value", 0)),
			"admission_status": str(record.get("admission_status", "bounded_estimate")),
			"daily_totals": ((market_states[market_id] as Dictionary).get("daily_totals", {}) as Dictionary).duplicate(true),
			"active_shipments": _shipment_count_for(economy_id),
		}
		aggregates[economy_id] = {"pricing_market_id": market_id}
		markets[market_id] = {"market_id": market_id, "source_economic_aggregate_id": economy_id}
	return {
		"schema_id": "formal_world_economy_observation_v2",
		"domain_owner": "FormalWorldEconomyState",
		"state_revision": _state_revision,
		"total_hour": total_hour,
		"country_summaries": summaries,
		"world_summary": world_summary(),
		"economy_by_polity_id": economy_by_polity_id.duplicate(true),
		"economy_polity_ids": economy_polity_ids.duplicate(true),
		"economic_aggregate_states": aggregates,
		"market_states": markets,
	}


func read_only_country_observation_snapshot() -> Dictionary:
	## Narrow detached observation for Organization supply-continuity monitoring.
	## Economy remains the sole owner of market state; this projects only the facts
	## the responsibility observer consumes and preserves the existing query view.
	var summaries: Dictionary = {}
	for market_id_value: Variant in market_states:
		var market_id := str(market_id_value)
		var economy_id := _market_registry.economic_aggregate_id_for_market(market_id)
		var state := market_states[market_id] as Dictionary
		var daily_totals := state.get("daily_totals", {}) as Dictionary
		summaries[economy_id] = {
			"economic_aggregate_id": economy_id,
			"daily_totals": {
				"fulfillment_bp": int(daily_totals.get("fulfillment_bp", -1)),
			},
			"top_shortages": _top_country_shortage_identities(state, 8),
		}
	return {
		"schema_id": "formal_world_economy_observation_v2",
		"domain_owner": "FormalWorldEconomyState",
		"state_revision": _state_revision,
		"total_hour": total_hour,
		"economy_by_polity_id": economy_by_polity_id.duplicate(true),
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
		"personal_sale_accounts": _personal_sale_accounts.duplicate(true),
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
	var sale_accounts: Variant = state.get("personal_sale_accounts",{})
	if not sale_accounts is Dictionary: return false
	for market_id: Variant in sale_accounts:
		if not market_id is String or not candidate_market_states.has(market_id) or not sale_accounts[market_id] is Dictionary or _personal_ledger == null: return false
		var record := sale_accounts[market_id] as Dictionary
		var account := _personal_ledger.account(personal_sale_account_id(market_id))
		if not FormalLedgerState.exact_fields(record,["market_id","account_id","inventory_owner_id","stock_scope","basis"]) or record.get("market_id") != market_id or record.get("account_id") != personal_sale_account_id(market_id) or record.get("basis") != "GENERATED_SIMULATION_ASSUMPTION" or record.get("inventory_owner_id") != market_id or record.get("stock_scope") != "existing_market_inventory" or account.get("owner_id") != market_id or account.get("role") != "market_receipts": return false
	_personal_sale_accounts = (sale_accounts as Dictionary).duplicate(true)
	market_states = candidate_market_states
	_daily_shortage_rows_by_market_id.clear()
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


func current_population(economy_id: String) -> int:
	return _population_state.population(economy_id) if _population_state != null else _population_input.population(economy_id)


func _cache_resolved_input(record: Dictionary) -> void:
	var economy_id := str(record.get("entity_id", ""))
	if economy_id.is_empty():
		return
	var income := record.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary
	var coverage := record.get("coverage", {}) as Dictionary
	var tier := _tier_for_rank(int(record.get("rank", 0)))
	_resolved_inputs[economy_id] = {
		"rank": int(record.get("rank", 0)),
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


func _top_country_shortages(state: Dictionary, limit: int) -> Array[Dictionary]:
	var cached_rows := _settled_day_shortage_rows(state)
	var output: Array[Dictionary] = []
	var row_count := mini(maxi(limit, 0), cached_rows.size())
	for index: int in row_count:
		output.append((cached_rows[index] as Dictionary).duplicate(false))
	return output


func _top_country_shortage_identities(
	state: Dictionary, limit: int
) -> Array[Dictionary]:
	var cached_rows := _settled_day_shortage_rows(state)
	var output: Array[Dictionary] = []
	var row_count := mini(maxi(limit, 0), cached_rows.size())
	for index: int in row_count:
		var row := cached_rows[index] as Dictionary
		var commodity_id := str(row.get("commodity_id", ""))
		output.append({
			"commodity_id": commodity_id,
			"name_zh": str(row.get("name_zh", commodity_id)),
		})
	return output


func _settled_day_shortage_rows(state: Dictionary) -> Array:
	var market_id := str(state.get("market_id", ""))
	var settlement_hour := int(state.get("last_settlement_hour", -1))
	var cached := (
		_daily_shortage_rows_by_market_id.get(market_id, {}) as Dictionary
	)
	if (
		not market_id.is_empty()
		and int(cached.get("settlement_hour", -2)) == settlement_hour
		and cached.get("rows", []) is Array
	):
		return cached.get("rows", []) as Array
	var rows := _build_sorted_shortage_rows(state)
	if not market_id.is_empty():
		_daily_shortage_rows_by_market_id[market_id] = {
			"settlement_hour": settlement_hour,
			"rows": rows,
		}
	return rows


func _rebuild_daily_shortage_rows(market_id: String, state: Dictionary) -> void:
	_daily_shortage_rows_by_market_id[market_id] = {
		"settlement_hour": int(state.get("last_settlement_hour", -1)),
		"rows": _build_sorted_shortage_rows(state),
	}


func _build_sorted_shortage_rows(state: Dictionary) -> Array[Dictionary]:
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
	if candidate_market_states.size() != _market_registry.market_count():
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
			or current_population(economy_id) < 0
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
		and str(population_reference.get("revision", ""))
		== _population_input.revision()
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
		"population": current_population(economy_id),
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


func bind_personal_economy(personal: FormalPersonalEconomyState) -> void:
	_personal_economy = personal

## Total population is unchanged. Named personal demand and configured native
## cohorts have one owner; only the remaining responsibility enters macro demand.
func consumption_population(economy_id: String) -> int:
	var total := current_population(economy_id)
	var personal := _personal_economy.managed_population(economy_id) if _personal_economy != null else 0
	if total < 0 or personal < 0 or personal > total:
		_fail("Economic demand responsibility exceeds admitted population")
		return -1
	return total - personal

## Native facts stay separate from the statistical markets and their units.
func bind_native_economy(native: EconomyR1Slice) -> void:
	_native_economy_ref = weakref(native) if native != null else null

func read_only_native_observation(person_id: String) -> Dictionary:
	var native := _native_economy_ref.get_ref() as EconomyR1Slice if _native_economy_ref != null else null
	return native.regional_observation(person_id) if native != null else {}

func read_only_cohort_observation(person_id: String, limit: int = 16, offset: int = 0) -> Dictionary:
	var native := _native_economy_ref.get_ref() as EconomyR1Slice if _native_economy_ref != null else null
	return native.cohort_observation(person_id, limit, offset) if native != null else {}


func read_only_population_responsibility(economy_id: String) -> Dictionary:
	var total := current_population(economy_id)
	if total < 0: return {}
	var personal := _personal_economy.managed_population(economy_id) if _personal_economy != null else 0
	var native := _native_economy_ref.get_ref() as EconomyR1Slice if _native_economy_ref != null else null
	return {"population_total": total, "macro_consumption_population": total-personal, "personal_and_native_population": personal, "native_background_population": native.managed_background_population(economy_id) if native != null else 0, "native_named_population": personal-(native.managed_background_population(economy_id) if native != null else 0), "named_residents": _population_state.unit(economy_id).get("named_person_count", 0) if _population_state != null else 0}


func commodity_definition(commodity_id: String) -> Dictionary:
	return (_commodities.get(commodity_id, {}) as Dictionary).duplicate(true)

func commodity_mapping_observation() -> Dictionary:
	var native := _native_economy_ref.get_ref() as EconomyR1Slice if _native_economy_ref != null else null
	var rows: Array = native.config.get("commodity_mappings", []).duplicate(true) if native != null else []
	var mapped: Dictionary = {}
	for row: Dictionary in rows: mapped[row["legacy_commodity_id"]] = true
	var unknown: Array[String] = []
	for id: String in _commodities:
		if not mapped.has(id): unknown.append(id)
	unknown.sort()
	return {"mappings": rows, "unmapped_legacy_goods": unknown, "macro_inventory_handover": "NO_IDENTIFIED_PROPERTY_OWNER", "price_authority": "ACCEPTED_NATIVE_SELLER_QUOTE_UNCHANGED"}
