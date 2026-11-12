class_name FormalPersonalEconomyState
extends RefCounted

const CommodityMapping = preload("res://scripts/world/formal_commodity_mapping.gd")
## Personal holdings, living records and wage relations. Ledger owns cash;
## Economy owns market stock/prices; GameClock owns elapsed time.

const SCHEMA_ID: String = "formal_personal_economy_state_v3"
const NO_FORMAL_EMPLOYMENT: String = "NO_FORMAL_EMPLOYMENT"
const GENERAL_WAGE_LABOR: String = "GENERAL_WAGE_LABOR"
const POLICY_FIELDS: Array[String] = ["policy_id", "basis", "denomination", "opening_cash", "wage_amount", "pay_period_minutes", "employer_reserve", "employer_label", "notice"]
const EMPLOYER_FIELDS: Array[String] = ["employer_id", "population_unit_id", "economic_aggregate_id", "payer_account_id", "initial_reserve", "label", "basis"]
const EMPLOYMENT_FIELDS: Array[String] = ["employment_id", "person_id", "employer_id", "payer_account_id", "wage_amount", "pay_period_minutes", "start_minute", "next_pay_boundary", "settled_periods"]

var error: String = ""
var _ledger: FormalLedgerState
var _clock: GameClock
var _persons: VNextNamedPersonOverlay
var _population: FormalWorldPopulationState
var _policy: Dictionary = {}
var _policy_fingerprint: String = ""
var _person_accounts: Dictionary = {}
var _employers: Dictionary = {}
var _employments: Dictionary = {}
var _market: FormalWorldEconomyState
var _holdings: Dictionary = {}
var _living_records: Dictionary = {}
var _living_by_id: Dictionary = {}
var _arrangements: Dictionary = {}
var _next_record_sequence: int = 1
var _next_consumption_minute: int = -1
# Native quantities remain in the economic inventory. These lots describe their
# sources; they are never another independently spendable inventory or wallet.
var _native: RefCounted
var _native_lots: Dictionary = {}
var _travel: FormalPersonTravel
var _runtime_accounts: Dictionary = {}
# Accepted livelihood changes retain authority, cutoff and conversion sources.
var _livelihood_changes: Dictionary = {}

func bind_travel(travel: FormalPersonTravel) -> void:
	_travel = travel

func travel_carry_reason(person: String, portable: Array, limit: int) -> String:
	var amount: int = 0
	if manages_native(person):
		var inventory := native_usable_inventory(person, true)
		for good: String in inventory:
			if int(inventory[good]) <= 0: continue
			if not portable.has(good): return "GOODS_REQUIRE_SEPARATE_FREIGHT"
			amount += int(inventory[good])
	for item: Dictionary in _holdings.get(person, {}).values():
		if int(item.get("quantity_milli", 0)) > 0: return "LEGACY_LUGGAGE_PERMISSION_UNSPECIFIED"
	return "PERSONAL_LUGGAGE_LIMIT" if amount > limit else ""

func native_admission_reason(person: String, allow_mapped_property: bool = false) -> String:
	if not _persons.is_alive(person) or _person_scope(person).is_empty(): return "HOST_PERSON_UNAVAILABLE"
	if manages_native(person): return "ALREADY_NATIVE"
	if _persons.is_travelling(person): return "HOST_PERSON_TRAVEL_STILL_ACTIVE"
	if _employments.has(person) and legacy_wage_end(person) < 0: return "LEGACY_WAGE_TERMINATION_NOT_EFFECTIVE"
	for owned: Dictionary in _holdings.get(person, {}).values():
		if int(owned.get("quantity_milli", 0)) > 0 and not allow_mapped_property: return "LEGACY_HOLDINGS_HAVE_NO_NATIVE_GOOD_MAPPING"
	for commodity: String in _arrangements.get(person, {}):
		if not pending_plan_conversion(person, commodity): return "LEGACY_LIVING_ARRANGEMENT_REMAINS_ACTIVE"
	var account := account_id_for_person(person)
	if not account.is_empty() and _ledger.reserved_balance(account) > 0: return "LEGACY_FUNDS_HAVE_UNSETTLED_RESERVATIONS"
	return ""

## The caller has opened an empty real Ledger account, without an endowment.
func admit_runtime_account(person: String, account: String, minute: int) -> void:
	if _person_accounts.has(person): return
	_person_accounts[person] = account
	_runtime_accounts[person] = minute


func configure(policy: Dictionary, ledger: FormalLedgerState, clock: GameClock, persons: VNextNamedPersonOverlay, population: FormalWorldPopulationState, player_id: String, livelihood: String) -> bool:
	if not _policy.is_empty() or ledger == null or clock == null or persons == null or population == null or clock.total_minutes() != 0:
		return _fail("Invalid or repeated personal economy composition")
	if livelihood not in [NO_FORMAL_EMPLOYMENT, GENERAL_WAGE_LABOR] or not persons.has_person(player_id) or not _valid_policy(policy):
		return _fail("Invalid livelihood or opening policy")
	_ledger = ledger
	_clock = clock
	_persons = persons
	_population = population
	_policy = policy.duplicate(true)
	_policy_fingerprint = JSON.stringify(_policy).sha256_text()
	var person_ids := persons.person_ids()
	var reserve := int(policy["employer_reserve"]) if livelihood == GENERAL_WAGE_LABOR else 0
	if person_ids.size() > (FormalLedgerState.MAX_AMOUNT - reserve) / int(policy["opening_cash"]):
		return _fail("Scenario opening budget exceeds integer bounds")
	var zero_opening: Array[String]=[]
	for person_id: String in person_ids:
		if _zero_cash_opening(persons.person(person_id)): zero_opening.append(person_id)
	if not _ledger.configure((person_ids.size()-zero_opening.size()) * int(policy["opening_cash"]) + reserve):
		return _fail(_ledger.error)
	for person_id: String in person_ids:
		var account_id := personal_account_id(person_id)
		if _person_scope(person_id).is_empty() or not _ledger.open_account(account_id, person_id, "personal_cash"):
			return _fail("Personal account requires an existing supported named person")
		if person_id in zero_opening:
			_person_accounts[person_id]=account_id
			_runtime_accounts[person_id]=0
			continue
		if not _ledger.transfer("opening:" + person_id, FormalLedgerState.SOURCE_ACCOUNT, account_id, int(policy["opening_cash"]), 0, "opening_cash", person_id):
			return _fail(_ledger.error)
		_person_accounts[person_id] = account_id
	if livelihood == GENERAL_WAGE_LABOR:
		var scope := _person_scope(player_id)
		var employer_id := "employer:background_wage:" + scope
		var payer_id := "account:background_wage:" + scope
		if not _ledger.open_account(payer_id, employer_id, "background_payer") or not _ledger.transfer("reserve:" + employer_id, FormalLedgerState.SOURCE_ACCOUNT, payer_id, reserve, 0, "employer_reserve", employer_id):
			return _fail(_ledger.error)
		_employers[employer_id] = {"employer_id": employer_id, "population_unit_id": scope, "economic_aggregate_id": scope, "payer_account_id": payer_id, "initial_reserve": reserve, "label": str(policy["employer_label"]), "basis": str(policy["basis"])}
		_employments[player_id] = {"employment_id": "employment:general_wage:" + player_id.trim_prefix("person:"), "person_id": player_id, "employer_id": employer_id, "payer_account_id": payer_id, "wage_amount": int(policy["wage_amount"]), "pay_period_minutes": int(policy["pay_period_minutes"]), "start_minute": 0, "next_pay_boundary": int(policy["pay_period_minutes"]), "settled_periods": []}
	error = ""
	return true


static func _zero_cash_opening(person: Dictionary) -> bool:
	var demographic: Dictionary = person.get("basic_demographic_identity", {})
	if demographic.get("opening_cash_policy") == "ZERO_CASH_DEVELOPMENT_CORPORATE_MANAGER": return true
	if demographic.get("opening_cash_policy") != "ZERO_CASH_GENERATED_RESIDENT": return false
	var opening: String = str(demographic.get("opening_configuration_id", ""))
	if opening in [FormalEconomicOpening.SECOND_WORKER_CASE, FormalEconomicOpening.MATERIAL_RENEWAL_CASE]:
		return person.get("person_id") in ["person:formal_generated_country_fra_0002", "person:formal_generated_country_fra_0003"]
	return person.get("person_id") == "person:formal_generated_country_fra_0002" and opening in ["FORMAL_PARIS_WORKSHOP_OPENING_R1", "FORMAL_PARIS_TWO_EMPLOYERS_OPENING_R1"]

static func personal_account_id(person_id: String) -> String:
	return "account:personal:" + person_id.trim_prefix("person:")


func account_id_for_person(person_id: String) -> String:
	return str(_person_accounts.get(person_id, ""))


func employment(person_id: String) -> Dictionary:
	return (_employments.get(person_id, {}) as Dictionary).duplicate(true)


func employer(employer_id: String) -> Dictionary:
	return (_employers.get(employer_id, {}) as Dictionary).duplicate(true)


## Called only from SimulationStep after advancing the injected formal clock.
## A failed oldest boundary stays pending; no partial pay, refill or skipped pay.
func settle_due_wages() -> Dictionary:
	var paid: int = 0
	var failed: int = 0
	var person_ids: Array = _employments.keys()
	person_ids.sort()
	for person_id: String in person_ids:
		var record := _employments[person_id] as Dictionary
		var end := legacy_wage_end(person_id, true)
		if manages_native(person_id) and end < 0: continue
		var through := mini(_clock.total_minutes(), end) if end >= 0 else _clock.total_minutes()
		while int(record["next_pay_boundary"]) <= through:
			var periods := record["settled_periods"] as Array
			var period_number := periods.size() + 1
			var period_id := pay_period_id(str(record["employment_id"]), period_number)
			if not _ledger.transfer("wage:" + period_id, str(record["payer_account_id"]), account_id_for_person(person_id), int(record["wage_amount"]), int(record["next_pay_boundary"]), "wage", period_id):
				failed += 1
				break
			periods.append(period_number)
			record["next_pay_boundary"] = int(record["next_pay_boundary"]) + int(record["pay_period_minutes"])
			paid += 1
	return {"paid_periods": paid, "failed_periods": failed}


static func pay_period_id(employment_id: String, period_number: int) -> String:
	return employment_id + ":period:" + str(period_number)


## Detached one-person observation. UI queries this instead of keeping balances.
func person_economy(person_id: String) -> Dictionary:
	if manages_native(person_id):
		return _native.call("personal_economy", person_id)
	var account_id := account_id_for_person(person_id)
	var record := employment(person_id)
	var recent: Dictionary = {}
	if not record.is_empty():
		var periods := record["settled_periods"] as Array
		if not periods.is_empty():
			recent = _ledger.transaction("wage:" + pay_period_id(str(record["employment_id"]), int(periods.back())))
	var payer_balance: Variant = _ledger.balance(str(record.get("payer_account_id", "")))
	var cutoff := legacy_wage_end(person_id)
	var unpaid := not record.is_empty() and int(record["next_pay_boundary"]) <= (mini(_clock.total_minutes(), cutoff) if cutoff >= 0 else _clock.total_minutes())
	return {
		"account_id": account_id,
		"cash": _ledger.balance(account_id),
		"denomination": FormalLedgerState.DENOMINATION,
		"opening_basis": str(_policy.get("basis", "")),
		"current_place_id": _persons.current_place(person_id),
		"resident_population_unit_id": _population.unit_for_person(person_id),
		"activity_population_unit_id": _population.unit_for_place(_persons.current_place(person_id)),
		"management_scope_id": "LEGACY_RESIDENT_MACRO_AND_FORMAL_PERSONAL",
		"accounts": _ledger.own_accounts(person_id),
		"livelihood": NO_FORMAL_EMPLOYMENT if record.is_empty() or cutoff >= 0 else GENERAL_WAGE_LABOR,
		"legacy_wage_end_minute": cutoff,
		"employment": record,
		"employer": employer(str(record.get("employer_id", ""))),
		"payer_balance": payer_balance,
		"recent_wage_transaction": recent,
		"wage_unpaid": unpaid,
	}



func bind_market(market: FormalWorldEconomyState) -> void:
	_market = market


func accessible_market_id(person_id: String) -> String:
	if _market == null: return ""
	return _market.market_id_for_economic_aggregate(_person_scope(person_id))


func purchase_quote(person_id: String, market_id: String, commodity_id: String, quantity_milli: int) -> Dictionary:
	if manages_native(person_id):
		return _native.call("personal_purchase_quote", person_id, market_id, commodity_id, quantity_milli)
	if _market == null: return {"success":false,"error":"正式市场出售关系尚未绑定。"}
	if not _persons.has_person(person_id) or not bool(_persons.person(person_id).get("alive",false)): return {"success":false,"error":"买方人物不存在或已不在世。"}
	var existing := holding(person_id,commodity_id)
	if quantity_milli <= 0 or quantity_milli > FormalLedgerState.MAX_AMOUNT-int(existing.get("quantity_milli",0)): return {"success":false,"error":"数量无效或超过个人持有范围。"}
	var quote := _market.personal_purchase_quote(market_id,commodity_id,quantity_milli,account_id_for_person(person_id),_person_scope(person_id))
	if bool(quote.get("success",false)) and not existing.is_empty() and str(existing.unit_name_zh) != str(quote.unit_name_zh): return {"success":false,"error":"商品单位已改变，不能混入原有持有数量。"}
	return quote


func purchase(person_id: String, market_id: String, commodity_id: String, quantity_milli: int, expected_unit_price: int = -1, accepted_quote: Dictionary = {}) -> Dictionary:
	if manages_native(person_id):
		var quote := accepted_quote if not accepted_quote.is_empty() else purchase_quote(person_id, market_id, commodity_id, quantity_milli)
		if not quote.get("success", false):
			if FormalLedgerState.valid_amount(quantity_milli):
				record_native_failure(person_id, commodity_id, quantity_milli, str(quote.get("error", "购买未被接受。")), "purchase_failed")
			return quote
		if expected_unit_price >= 0 and quote.get("unit_price") != expected_unit_price:
			return {"success": false, "error": "当前价格已改变。"}
		var result: Dictionary = _native.call("personal_purchase", person_id, quote, quantity_milli, "life:" + str(_next_record_sequence))
		if result.get("success", false):
			record_native_source(person_id, result["source"], "native_order")
		else:
			record_native_failure(person_id, commodity_id, quantity_milli, str(result.get("error", "购买未被接受。")), "purchase_failed")
		return result

	var quote := purchase_quote(person_id,market_id,commodity_id,quantity_milli)
	if not bool(quote.get("success",false)): return quote
	if expected_unit_price >= 0 and int(quote.unit_price) != expected_unit_price: return {"success":false,"error":"当前价格已改变，请查看新报价后购买。"}
	var id := "personal_life:"+str(_next_record_sequence)
	var transaction_id := "purchase:"+id
	var paid := _market.purchase_from_existing_stock(quote,transaction_id,id,_clock.total_minutes())
	if not bool(paid.get("success",false)): return paid
	var record := quote.duplicate(true)
	record.erase("success")
	record.merge({"record_id":id,"kind":"purchase","person_id":person_id,"effective_minute":_clock.total_minutes(),"transaction_id":transaction_id})
	_add_purchased_holding(_holdings,record)
	_append_living_record(record)
	return {"success":true,"record":record.duplicate(true),"message":"购买 %s %.3f %s，支付 %d 模拟单位。" % [record.name_zh,float(quantity_milli)/1000.0,record.unit_name_zh,int(record.amount)]}


func holding(person_id: String, commodity_id: String) -> Dictionary:
	if manages_native(person_id) and commodity_id.begins_with("native:"):
		var good := commodity_id.trim_prefix("native:")
		var item := commodity_capability(person_id, commodity_id)
		if item.is_empty():
			return {}
		var inventory: Dictionary = _native.call("personal_owned_inventory", person_id)
		var lots: Array = _native_lots.get(person_id, {}).get(good, [])
		item.merge({"quantity": int(native_usable_inventory(person_id).get(good, 0)), "owned_quantity": int(inventory.get(good, 0)), "custody": native_custody_rows(person_id, good), "consumed": int(_native.call("personal_used", person_id, good)), "quantity_scale": 1, "quantity_milli": int(native_usable_inventory(person_id).get(good, 0)), "consumed_milli": int(_native.call("personal_used", person_id, good)), "latest_source": lots.back().duplicate(true) if not lots.is_empty() else {}})
		return item
	var owned := (_holdings.get(person_id,{}) as Dictionary).get(commodity_id,{}) as Dictionary
	if owned.is_empty(): return {}
	var value := owned.duplicate(false)
	var lots := owned.get("lots",[]) as Array
	value.erase("lots")
	value["latest_source"] = (lots.back() as Dictionary).duplicate(false) if not lots.is_empty() else {}
	return value


func holding_rows(person_id: String, limit: int, offset: int) -> Array[Dictionary]:
	var ids: Array = (_holdings.get(person_id, {}) as Dictionary).keys()
	if manages_native(person_id):
		var inventory: Dictionary = _native.call("personal_owned_inventory", person_id)
		for good: String in inventory:
			if int(inventory[good]) > 0 or int(_native.call("personal_used", person_id, good)) > 0:
				ids.append("native:" + good)
	ids.sort()
	var rows: Array[Dictionary] = []
	for index: int in range(maxi(0, offset), mini(ids.size(), maxi(0, offset) + maxi(0, limit))):
		rows.append(holding(person_id, str(ids[index])))
	return rows


func living_records(person_id: String, limit: int, offset: int = 0) -> Array[Dictionary]:
	var values := _living_records.get(person_id,[]) as Array
	var rows: Array[Dictionary] = []
	for index: int in range(values.size()-1-maxi(0,offset),maxi(-1,values.size()-1-maxi(0,offset)-limit),-1): rows.append(_living_view(values[index]))
	return rows


func living_record(person_id: String, record_id: String) -> Dictionary:
	var record := _living_by_id.get(record_id,{}) as Dictionary
	return _living_view(record) if str(record.get("person_id",""))==person_id else {}


func consumption_quote(person_id: String, commodity_id: String, quantity_milli: int) -> Dictionary:
	if manages_native(person_id) and commodity_id.begins_with("native:"):
		return _native.call("personal_consumption_quote", person_id, commodity_id, quantity_milli)
	if _market == null or not _persons.has_person(person_id) or not bool(_persons.person(person_id).get("alive",false)): return {"success":false,"error":"人物或商品关系不可用。"}
	var item := _market.commodity_for_person(commodity_id)
	if item.is_empty() or not bool(item.consumable): return {"success":false,"error":"该商品尚无个人消费规则。"}
	var owned := holding(person_id,commodity_id)
	if not owned.is_empty() and owned.get("unit_name_zh") != item.get("unit_name_zh"):
		return {"success":false,"error":"历史持有单位与当前规则不同；保留历史数量，暂不能消费。"}
	if quantity_milli <= 0 or quantity_milli > FormalLedgerState.MAX_AMOUNT-int(owned.get("consumed_milli",0)): return {"success":false,"error":"消费数量无效或超过记录范围。"}
	if int(owned.get("quantity_milli",0)) < quantity_milli: return {"success":false,"error":"个人持有数量不足；消费不会自动生成物品。"}
	return {"success":true}


func consume(person_id: String, commodity_id: String, quantity_milli: int, source: String = "manual") -> Dictionary:
	if manages_native(person_id) and commodity_id.begins_with("native:"):
		var result: Dictionary = _native.call("personal_consume", person_id, commodity_id, quantity_milli, source, "life:" + str(_next_record_sequence))
		if not result.get("success", false) and FormalLedgerState.valid_amount(quantity_milli):
			record_native_failure(person_id, commodity_id, quantity_milli, str(result.get("error", "消费未完成。")), source)
		return result
	var allowed := consumption_quote(person_id,commodity_id,quantity_milli)
	if not bool(allowed.get("success",false)): return allowed
	var owned := ((_holdings[person_id] as Dictionary)[commodity_id]) as Dictionary
	var remaining := quantity_milli
	var allocations: Array[Dictionary] = []
	for lot: Dictionary in owned.lots as Array:
		var used := mini(remaining,int(lot.remaining_milli))
		if used > 0: allocations.append({"purchase_record_id":lot.purchase_record_id,"quantity_milli":used})
		remaining -= used
		if remaining == 0: break
	var record := {"record_id":"personal_life:"+str(_next_record_sequence),"kind":"consume","person_id":person_id,"effective_minute":_clock.total_minutes(),"commodity_id":commodity_id,"name_zh":owned.name_zh,"unit_name_zh":owned.unit_name_zh,"quantity_milli":quantity_milli,"allocations":allocations,"source":source,"amount":0}
	_apply_consumed_holding(_holdings,record)
	_append_living_record(record)
	return {"success":true,"record":record.duplicate(true),"message":"消费 %s %.3f %s；持有数量已减少。" % [owned.name_zh,float(quantity_milli)/1000.0,owned.unit_name_zh]}


func arrangement(person_id: String, commodity_id: String) -> Dictionary:
	var result := ((_arrangements.get(person_id,{}) as Dictionary).get(commodity_id,{}) as Dictionary).duplicate(true)
	if result.has("quantity"):
		result["quantity_milli"] = result["quantity"]
		result["quantity_scale"] = 1
	return result


func set_daily_consumption(person_id: String, commodity_id: String, quantity_milli: int, enabled: bool, auto_buy_missing: bool = false) -> Dictionary:
	if manages_native(person_id) and commodity_id.begins_with("native:"):
		return _set_native_arrangement(person_id, commodity_id, quantity_milli, enabled, auto_buy_missing)
	var item := _market.commodity_for_person(commodity_id) if _market != null else {}
	var owned := holding(person_id,commodity_id)
	if not enabled:
		var plan := arrangement(person_id,commodity_id)
		if plan.is_empty(): return {"success":false,"error":"没有此商品的每日消费安排。"}
		quantity_milli = int(plan.quantity_milli)
		(_arrangements[person_id] as Dictionary).erase(commodity_id)
	else:
		if item.is_empty() or not bool(item.consumable) or owned.is_empty() or owned.get("unit_name_zh") != item.get("unit_name_zh") or not _persons.has_person(person_id) or not bool(_persons.person(person_id).get("alive",false)) or not FormalLedgerState.valid_amount(quantity_milli) or quantity_milli <= 0: return {"success":false,"error":"仅能安排已购入且支持消费的物品，数量必须为正。"}
		if _clock.total_minutes()>9223372036854774367: return {"success":false,"error":"正式时间已不足以安排下一日消费。"}
		if not _arrangements.has(person_id): _arrangements[person_id] = {}
		var due := int(arrangement(person_id,commodity_id).get("next_due_minute",_clock.total_minutes()+1440))
		(_arrangements[person_id] as Dictionary)[commodity_id] = {"quantity_milli":quantity_milli,"period_minutes":1440,"next_due_minute":due,"auto_buy_missing":auto_buy_missing}
	_recompute_next_consumption()
	_append_living_record({"record_id":"personal_life:"+str(_next_record_sequence),"kind":"arrangement_set" if enabled else "arrangement_cancelled","person_id":person_id,"effective_minute":_clock.total_minutes(),"commodity_id":commodity_id,"name_zh":str(owned.get("name_zh",item.get("name_zh",commodity_id))),"unit_name_zh":str(owned.get("unit_name_zh",item.get("unit_name_zh",""))),"quantity_milli":quantity_milli,"amount":0})
	return {"success":true,"message":"已安排每日消费；使用已持有物品，条件不足记录失败。" if enabled else "已停止每日消费安排。"}


func next_consumption_minute() -> int:
	return _next_consumption_minute


func settle_due_consumption() -> Dictionary:
	var native_result := _settle_native_arrangements() if _native != null else {"completed": 0, "failed": 0}
	var completed := int(native_result["completed"])
	var failed := int(native_result["failed"])
	if _next_consumption_minute < 0 or _next_consumption_minute > _clock.total_minutes(): return {"completed":completed,"failed":failed}
	var person_ids := _arrangements.keys()
	person_ids.sort()
	for person_id: String in person_ids:
		var plans := _arrangements[person_id] as Dictionary
		var commodity_ids := plans.keys()
		commodity_ids.sort()
		for commodity_id: String in commodity_ids:
			if commodity_id.begins_with("native:"):
				continue
			var plan := plans[commodity_id] as Dictionary
			if int(plan.next_due_minute) > _clock.total_minutes(): continue
			var quantity := int(plan.quantity_milli)
			var owned := holding(person_id,commodity_id)
			var reason := ""
			var item := _market.commodity_for_person(commodity_id)
			if item.is_empty() or not bool(item.consumable) or not bool(_persons.person(person_id).get("alive",false)): reason = "人物或消费规则不可用。"
			elif quantity > FormalLedgerState.MAX_AMOUNT-int(owned.get("consumed_milli",0)): reason = "消费记录超过整数范围。"
			if reason.is_empty() and int(owned.get("quantity_milli",0)) < quantity and bool(plan.auto_buy_missing):
				var bought := purchase(person_id,accessible_market_id(person_id),commodity_id,quantity-int(owned.get("quantity_milli",0)))
				if not bool(bought.get("success",false)): reason = str(bought.error)
			if reason.is_empty():
				var consumed := consume(person_id,commodity_id,quantity,"daily")
				if bool(consumed.get("success",false)): completed += 1
				else: reason = str(consumed.error)
			if not reason.is_empty():
				failed += 1
				_append_living_record({"record_id":"personal_life:"+str(_next_record_sequence),"kind":"arrangement_failed","person_id":person_id,"effective_minute":_clock.total_minutes(),"commodity_id":commodity_id,"name_zh":str(owned.get("name_zh",commodity_id)),"unit_name_zh":str(owned.get("unit_name_zh","")),"quantity_milli":quantity,"amount":0,"reason":reason})
			if int(plan.next_due_minute)>9223372036854774367: plans.erase(commodity_id)
			else: plan.next_due_minute = int(plan.next_due_minute)+int(plan.period_minutes)
	_recompute_next_consumption()
	return {"completed":completed,"failed":failed}


func _recompute_next_consumption() -> void:
	_next_consumption_minute = -1
	for plans: Dictionary in _arrangements.values():
		for plan: Dictionary in plans.values():
			var minute := int(plan.next_due_minute)
			if _next_consumption_minute < 0 or minute < _next_consumption_minute: _next_consumption_minute = minute


func _append_living_record(record: Dictionary) -> void:
	var person_id := str(record.person_id)
	if not _living_records.has(person_id): _living_records[person_id] = []
	(_living_records[person_id] as Array).append(record)
	_living_by_id[str(record.record_id)] = record
	_next_record_sequence += 1


static func _add_purchased_holding(holdings: Dictionary, record: Dictionary) -> void:
	var person_id := str(record.person_id)
	var commodity_id := str(record.commodity_id)
	if not holdings.has(person_id): holdings[person_id] = {}
	var values := holdings[person_id] as Dictionary
	if not values.has(commodity_id): values[commodity_id] = {"commodity_id":commodity_id,"name_zh":record.name_zh,"unit_name_zh":record.unit_name_zh,"quantity_milli":0,"consumed_milli":0,"lots":[]}
	var owned := values[commodity_id] as Dictionary
	owned.quantity_milli = int(owned.quantity_milli)+int(record.quantity_milli)
	(owned.lots as Array).append({"purchase_record_id":record.record_id,"market_id":record.market_id,"remaining_milli":record.quantity_milli,"effective_minute":record.effective_minute})


static func _apply_consumed_holding(holdings: Dictionary, record: Dictionary) -> void:
	var owned := ((holdings[str(record.person_id)] as Dictionary)[str(record.commodity_id)]) as Dictionary
	var lots := owned.lots as Array
	for allocation: Dictionary in record.allocations as Array:
		for lot: Dictionary in lots:
			if str(lot.purchase_record_id)==str(allocation.purchase_record_id):
				lot.remaining_milli = int(lot.remaining_milli)-int(allocation.quantity_milli)
				break
	for index: int in range(lots.size()-1,-1,-1):
		if int((lots[index] as Dictionary).remaining_milli)==0: lots.remove_at(index)
	owned.quantity_milli = int(owned.quantity_milli)-int(record.quantity_milli)
	owned.consumed_milli = int(owned.consumed_milli)+int(record.quantity_milli)


func snapshot() -> Dictionary:
	var result := {"schema_id": SCHEMA_ID, "policy_fingerprint": _policy_fingerprint, "person_accounts": _person_accounts.duplicate(true), "employers": _employers.duplicate(true), "employments": _employments.duplicate(true),"holdings":_holdings.duplicate(true),"living_records":_living_records.duplicate(true),"arrangements":_arrangements.duplicate(true),"next_record_sequence":_next_record_sequence,"native_lots":_native_lots.duplicate(true)}
	if not _runtime_accounts.is_empty(): result["runtime_accounts"] = _runtime_accounts.duplicate(true)
	if not _livelihood_changes.is_empty(): result["livelihood_changes"] = _livelihood_changes.duplicate(true)
	return result


func restore(value: Dictionary, player_id: String) -> bool:
	if _native != null and _policy.is_empty():
		return _restore_native(value)
	var fields: Array[String] = ["schema_id","policy_fingerprint","person_accounts","employers","employments"]
	if value.has("livelihood_changes"): fields.append("livelihood_changes")
	if not _restore_livelihood_changes(value.get("livelihood_changes", {}), value.get("employments", {})): return false
	var legacy := str(value.get("schema_id","")) == "formal_personal_economy_state_v1"
	if not legacy: fields.append_array(["holdings","living_records","arrangements","next_record_sequence"])
	if value.get("schema_id") == SCHEMA_ID:
		fields.append("native_lots")
		if _native == null and value.get("native_lots") != {}:
			return _fail("Native lots require their original economic inventory")
	_runtime_accounts = {}
	if value.has("runtime_accounts"):
		fields.append("runtime_accounts")
		if not value["runtime_accounts"] is Dictionary: return _fail("Invalid runtime personal account admission")
		_runtime_accounts = value["runtime_accounts"].duplicate(true)
	if not FormalLedgerState.exact_fields(value,fields) or (not legacy and value.get("schema_id") not in [SCHEMA_ID, "formal_personal_economy_state_v2"]) or value.get("policy_fingerprint") != _policy_fingerprint:
		return _fail("Personal economy snapshot policy or schema mismatch")
	for field: String in ["person_accounts", "employers", "employments"]:
		if not value[field] is Dictionary:
			return _fail("Invalid personal economy snapshot container")
	var accounts := (value["person_accounts"] as Dictionary).duplicate(true)
	var employers := (value["employers"] as Dictionary).duplicate(true)
	var employments := (value["employments"] as Dictionary).duplicate(true)
	# R1 creates only the selected player's livelihood; saved data cannot invent
	# additional employment relations that have no current creation operation.
	if employments.size() > 1 or (not employments.is_empty() and not employments.has(player_id)):
		return _fail("Unsupported employment outside the player livelihood")
	if not accounts.has(player_id):
		return _fail("Player personal account is missing")
	var expected_transactions: Dictionary = {}
	for person_id: Variant in accounts:
		if not person_id is String or not accounts[person_id] is String or _person_scope(person_id).is_empty() or accounts[person_id] != personal_account_id(person_id):
			return _fail("Invalid Person/account mapping")
		var account := _ledger.account(accounts[person_id])
		if account.get("owner_id") != person_id or account.get("role") != "personal_cash":
			return _fail("Personal account owner or role mismatch")
		var transaction_id := "opening:" + str(person_id)
		if _runtime_accounts.has(person_id):
			if not FormalLedgerState.valid_amount(_runtime_accounts[person_id]) or int(_runtime_accounts[person_id]) < 0 or (int(_runtime_accounts[person_id])==0 and not _zero_cash_opening(_persons.person(person_id))) or int(_runtime_accounts[person_id]) > _clock.total_minutes() or not _ledger.transaction(transaction_id).is_empty(): return _fail("Runtime account cannot receive opening cash")
		else:
			if not _receipt_matches(transaction_id, FormalLedgerState.SOURCE_ACCOUNT, accounts[person_id], int(_policy["opening_cash"]), 0, "opening_cash", person_id): return _fail("Missing or invalid opening cash transaction")
			expected_transactions[transaction_id] = true
	for employer_id: Variant in employers:
		if not employer_id is String or not employers[employer_id] is Dictionary:
			return _fail("Invalid employer record")
		var record := employers[employer_id] as Dictionary
		if not FormalLedgerState.exact_fields(record, EMPLOYER_FIELDS):
			return _fail("Invalid employer fields")
		var scope := str(record.get("population_unit_id", ""))
		var payer_id := "account:background_wage:" + scope
		if _population.unit(scope).is_empty() or employer_id != "employer:background_wage:" + scope or record.get("employer_id") != employer_id or record.get("economic_aggregate_id") != scope or record.get("payer_account_id") != payer_id or record.get("initial_reserve") != _policy["employer_reserve"] or typeof(record.get("initial_reserve")) != TYPE_INT or record.get("basis") != _policy["basis"] or record.get("label") != _policy["employer_label"]:
			return _fail("Employer scope, assumption or reserve mismatch")
		var account := _ledger.account(payer_id)
		if account.get("owner_id") != employer_id or account.get("role") != "background_payer":
			return _fail("Employer payer account is invalid")
		var transaction_id := "reserve:" + str(employer_id)
		if not _receipt_matches(transaction_id, FormalLedgerState.SOURCE_ACCOUNT, payer_id, int(_policy["employer_reserve"]), 0, "employer_reserve", employer_id):
			return _fail("Employer reserve transaction is invalid")
		expected_transactions[transaction_id] = true
	var used_employers: Dictionary = {}
	for person_id: Variant in employments:
		if not person_id is String or not accounts.has(person_id) or not employments[person_id] is Dictionary:
			return _fail("Invalid employment person")
		var record := employments[person_id] as Dictionary
		if not FormalLedgerState.exact_fields(record, EMPLOYMENT_FIELDS) or not record.get("settled_periods") is Array:
			return _fail("Invalid employment fields")
		for field: String in ["wage_amount", "pay_period_minutes", "start_minute", "next_pay_boundary"]:
			if not FormalLedgerState.valid_amount(record[field]):
				return _fail("Invalid employment amount or boundary")
		var employer_id := str(record.get("employer_id", ""))
		var original_unit := _population.residence_unit_at(person_id, int(record["start_minute"]))
		if employer_id != "employer:background_wage:"+original_unit: return _fail("Employment differs from its original residence at contract formation")
		var employment_id := "employment:general_wage:" + str(person_id).trim_prefix("person:")
		if record.get("employment_id") != employment_id or record.get("person_id") != person_id or record.get("employer_id") != employer_id or not employers.has(employer_id) or record.get("payer_account_id") != (employers[employer_id] as Dictionary)["payer_account_id"] or record["wage_amount"] != _policy["wage_amount"] or record["pay_period_minutes"] != _policy["pay_period_minutes"] or record["start_minute"] != 0:
			return _fail("Employment does not match its current person/population scope or policy")
		used_employers[employer_id] = true
		var periods := record["settled_periods"] as Array
		var period_minutes := int(record["pay_period_minutes"])
		if periods.size() > FormalLedgerState.MAX_AMOUNT / period_minutes - 1 or int(record["next_pay_boundary"]) != (periods.size() + 1) * period_minutes:
			return _fail("Employment next pay boundary is inconsistent")
		for index: int in periods.size():
			if typeof(periods[index]) != TYPE_INT or int(periods[index]) != index + 1 or (index + 1) * period_minutes > _clock.total_minutes():
				return _fail("Invalid, skipped or future settled pay period")
			var period_id := pay_period_id(employment_id, index + 1)
			var transaction_id := "wage:" + period_id
			if not _receipt_matches(transaction_id, str(record["payer_account_id"]), str(accounts[person_id]), int(record["wage_amount"]), (index + 1) * period_minutes, "wage", period_id):
				return _fail("Settled pay period has no matching wage transfer")
			expected_transactions[transaction_id] = true
		var wage_end := legacy_wage_end(person_id, true)
		if (not manages_native(person_id) or legacy_wage_end(person_id) >= 0) and int(record["next_pay_boundary"]) <= (mini(_clock.total_minutes(), wage_end) if wage_end >= 0 else _clock.total_minutes()) and int(_ledger.balance(str(record["payer_account_id"]))) >= int(record["wage_amount"]):
			return _fail("Funded due wage period was not settled")
	var sales := _market.personal_sale_accounts() if _market != null else {}
	var expected_accounts: Dictionary = {FormalLedgerState.SOURCE_ACCOUNT: true}
	for account_id: String in accounts.values(): expected_accounts[account_id] = true
	for record: Dictionary in employers.values(): expected_accounts[record["payer_account_id"]] = true
	for market_id: String in sales: expected_accounts[FormalWorldEconomyState.personal_sale_account_id(market_id)] = true
	var native_budget: int = 0
	if _native != null:
		for account_id: String in _native.call("host_account_specs"):
			expected_accounts[account_id] = true
		for currency: String in _ledger.snapshot().get("currency_budgets", {}):
			expected_accounts[FormalLedgerState.currency_source(currency)] = true
		native_budget = int(_native.call("_opening_budget"))
	if used_employers.size() != employers.size() or _ledger.account_ids().size() != expected_accounts.size():
		return _fail("Unexplained personal account or employer")
	for account_id: String in _ledger.account_ids():
		if not expected_accounts.has(account_id): return _fail("Unexplained formal/native account")
	var budget: Variant = _ledger.snapshot()["scenario_budget"]
	if budget != (accounts.size()-_runtime_accounts.size()) * int(_policy["opening_cash"]) + employers.size() * int(_policy["employer_reserve"]) + native_budget:
		return _fail("Scenario funds do not match finite opening conditions")
	var living := {} if legacy else value
	if _native != null and not _restore_native(value, true): return false
	if not _restore_living(living,accounts,expected_transactions): return false
	var transactions := _ledger.transactions()
	if _native != null:
		for record: Dictionary in transactions:
			if bool(_native.call("owns_transaction", record)):
				expected_transactions[record["transaction_id"]] = true
	if transactions.size() != expected_transactions.size():
		return _fail("Unexplained ledger transactions")
	for record: Dictionary in transactions:
		if not expected_transactions.has(record["transaction_id"]):
			return _fail("Unexplained ledger transaction")
	_person_accounts = accounts
	_employers = employers
	_employments = employments
	error = ""
	return true


func _restore_living(value: Dictionary, accounts: Dictionary, expected_transactions: Dictionary) -> bool:
	var records: Variant = value.get("living_records",{})
	var saved_holdings: Variant = value.get("holdings",{})
	var plans: Variant = value.get("arrangements",{})
	var sequence: Variant = value.get("next_record_sequence",1)
	if not records is Dictionary or not saved_holdings is Dictionary or not plans is Dictionary or typeof(sequence) != TYPE_INT or int(sequence)<1: return _fail("Invalid personal property containers")
	var rebuilt: Dictionary = {}
	var sales := _market.personal_sale_accounts() if _market != null else {}
	var seen: Dictionary = {}
	for person_id: Variant in records:
		if not person_id is String or not accounts.has(person_id) or not records[person_id] is Array: return _fail("Invalid personal living record owner")
		var last_minute := -1
		for raw: Variant in records[person_id]:
			if not raw is Dictionary: return _fail("Invalid living record")
			var record := raw as Dictionary
			var id := str(record.get("record_id",""))
			var suffix := id.trim_prefix("personal_life:")
			if str(record.get("kind", "")).begins_with("native_") and _native != null:
				seen[id] = true
				continue
			var commodity_id := str(record.get("commodity_id",""))
			if not id.begins_with("personal_life:") or not suffix.is_valid_int() or int(suffix)<=0 or seen.has(id) or record.get("person_id") != person_id or not record.get("commodity_id") is String or commodity_id.is_empty() or not record.get("name_zh") is String or not record.get("unit_name_zh") is String or typeof(record.get("effective_minute")) != TYPE_INT or int(record.effective_minute)<last_minute or int(record.effective_minute)>_clock.total_minutes() or not FormalLedgerState.valid_amount(record.get("quantity_milli")) or int(record.quantity_milli)<=0 : return _fail("Invalid living record identity, date or goods")
			seen[id] = true
			last_minute = int(record.effective_minute)
			match str(record.get("kind","")):
				"purchase":
					var market_id := str(record.get("market_id",""))
					var price: Variant = record.get("unit_price")
					if not FormalLedgerState.valid_amount(price) or int(price)<=0 or int(record.quantity_milli)>(FormalLedgerState.MAX_AMOUNT-999)/int(price): return _fail("Invalid recorded purchase price")
					var amount: int = (int(price)*int(record.quantity_milli)+999)/1000
					var seller_account := FormalWorldEconomyState.personal_sale_account_id(market_id)
					if not sales.has(market_id) or record.get("seller_id") != market_id or record.get("seller_account_id") != seller_account or record.get("buyer_account_id") != accounts[person_id] or record.get("amount") != amount or record.get("transaction_id") != "purchase:"+id or not record.get("name_zh") is String or not record.get("unit_name_zh") is String or str(record.unit_name_zh).is_empty() or record.get("basis") != "GENERATED_SIMULATION_ASSUMPTION" or not _receipt_matches("purchase:"+id,accounts[person_id],seller_account,amount,last_minute,"purchase",id): return _fail("Purchase has no matching market payment")
					var previous := ((rebuilt.get(person_id,{}) as Dictionary).get(commodity_id,{}) as Dictionary)
					if int(record.quantity_milli)>FormalLedgerState.MAX_AMOUNT-int(previous.get("quantity_milli",0)) or (not previous.is_empty() and previous.unit_name_zh != record.unit_name_zh): return _fail("Invalid purchase quantity or unit")
					expected_transactions["purchase:"+id] = true
					_add_purchased_holding(rebuilt,record)
				"consume":
					var owned := ((rebuilt.get(person_id,{}) as Dictionary).get(commodity_id,{}) as Dictionary)
					if owned.is_empty() or record.get("unit_name_zh") != owned.get("unit_name_zh") or not record.get("allocations") is Array or record.get("amount") != 0 or int(record.quantity_milli)>int(owned.quantity_milli) or int(record.quantity_milli)>FormalLedgerState.MAX_AMOUNT-int(owned.consumed_milli): return _fail("Consumption exceeds owned goods")
					var used: Dictionary = {}
					var allocated := 0
					for raw_allocation: Variant in record.allocations:
						if not raw_allocation is Dictionary: return _fail("Invalid consumed purchase reference")
						var allocation := raw_allocation as Dictionary
						var purchase_id := str(allocation.get("purchase_record_id",""))
						if used.has(purchase_id) or not FormalLedgerState.valid_amount(allocation.get("quantity_milli")) or int(allocation.quantity_milli)<=0 or int(allocation.quantity_milli)>int(record.quantity_milli)-allocated: return _fail("Invalid consumed quantity")
						var found := false
						for lot: Dictionary in owned.lots as Array:
							if str(lot.purchase_record_id)==purchase_id and int(lot.remaining_milli)>=int(allocation.quantity_milli): found = true; break
						if not found: return _fail("Consumption has no owned source lot")
						used[purchase_id] = true
						allocated += int(allocation.quantity_milli)
					if allocated != int(record.quantity_milli): return _fail("Consumption source quantities disagree")
					_apply_consumed_holding(rebuilt,record)
				"legacy_handover":
					if _native == null or not record.get("source_id") is String: return _fail("Property handover requires its original native receiver")
					var fact: Dictionary = _native.call("property_handover", record["source_id"])
					var owned := rebuilt.get(person_id, {}).get(commodity_id, {}) as Dictionary
					if fact.is_empty() or record.get("amount") != 0 or record.get("unit_name_zh") != owned.get("unit_name_zh") or record.get("allocations") != fact.get("allocations") or fact.get("person_id") != person_id or fact.get("legacy_commodity_id") != commodity_id or fact.get("legacy_quantity_milli") != record["quantity_milli"] or fact.get("effective_minute") != record["effective_minute"] or record["allocations"] != _legacy_fifo(owned, int(record["quantity_milli"])): return _fail("Property handover loses owned FIFO sources")
					_remove_handed_over_holding(rebuilt, record)
				"arrangement_set", "arrangement_cancelled", "arrangement_failed":
					if record.get("amount") != 0: return _fail("Non-payment living record cannot change cash")
					if record.kind == "arrangement_failed" and not record.get("reason") is String: return _fail("Missing failed arrangement reason")
				_: return _fail("Unsupported personal living record")
	if int(sequence) != seen.size()+1 or rebuilt != saved_holdings: return _fail("Personal property does not match purchase and consumption records")
	for index: int in range(1,int(sequence)):
		if not seen.has("personal_life:"+str(index)): return _fail("Invalid living record sequence")
	for person_id: Variant in plans:
		if not person_id is String or not accounts.has(person_id) or not plans[person_id] is Dictionary: return _fail("Invalid consumption arrangement person")
		for commodity_id: Variant in plans[person_id]:
			if _native != null and str(commodity_id).begins_with("native:"): continue
			if not commodity_id is String or not plans[person_id][commodity_id] is Dictionary: return _fail("Invalid consumption arrangement")
			var plan := plans[person_id][commodity_id] as Dictionary
			if not FormalLedgerState.exact_fields(plan,["quantity_milli","period_minutes","next_due_minute","auto_buy_missing"]) or not FormalLedgerState.valid_amount(plan.get("quantity_milli")) or int(plan.quantity_milli)<=0 or plan.get("period_minutes") != 1440 or typeof(plan.get("next_due_minute")) != TYPE_INT or int(plan.next_due_minute)<=_clock.total_minutes() or int(plan.next_due_minute)-_clock.total_minutes()>1440 or not plan.get("auto_buy_missing") is bool or not (rebuilt.get(person_id,{}) as Dictionary).has(commodity_id) : return _fail("Invalid consumption arrangement quantity or date")
	_holdings = rebuilt
	_living_records = (records as Dictionary).duplicate(true)
	_living_by_id.clear()
	for values: Array in _living_records.values():
		for record: Dictionary in values: _living_by_id[str(record.record_id)] = record
	_arrangements = (plans as Dictionary).duplicate(true)
	_next_record_sequence = int(sequence)
	_recompute_next_consumption()
	return true


func _person_scope(person_id: String) -> String:
	var person := _persons.person(person_id)
	var scope := str(person.get("population_territory_id", ""))
	if not bool(person.get("alive", false)) or _population.unit(scope).is_empty() or _population.unit_for_person(person_id) != scope or _population.place_support(str(person.get("current_place_id", ""))) == "UNKNOWN":
		return ""
	return scope


func _receipt_matches(transaction_id: String, source_id: String, destination_id: String, amount: int, minute: int, kind: String, reference_id: String) -> bool:
	var record := _ledger.transaction(transaction_id)
	return not record.is_empty() and record.get("from_account_id") == source_id and record.get("to_account_id") == destination_id and record.get("amount") == amount and record.get("effective_minute") == minute and record.get("kind") == kind and record.get("reference_id") == reference_id


func _valid_policy(policy: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(policy, POLICY_FIELDS) or policy.get("policy_id") != "player_livelihood_r1" or policy.get("basis") != "GENERATED_SIMULATION_ASSUMPTION" or policy.get("denomination") != FormalLedgerState.DENOMINATION:
		return false
	for field: String in ["opening_cash", "wage_amount", "pay_period_minutes", "employer_reserve"]:
		if not FormalLedgerState.valid_amount(policy[field]) or int(policy[field]) <= 0:
			return false
	return int(policy["pay_period_minutes"]) % (24 * 60) == 0 and not str(policy["employer_label"]).is_empty()


func _fail(message: String) -> bool:
	error = message
	return false


func bind_native(economy: RefCounted, ledger: FormalLedgerState, clock: GameClock, persons: VNextNamedPersonOverlay, population: FormalWorldPopulationState) -> bool:
	if economy == null or not economy.has_method("personal_accounts") or ledger == null or clock == null or persons == null or population == null or _native != null:
		return _fail("Native personal ownership requires an explicit, non-overlapping composition")
	_native = economy
	_ledger = ledger
	_clock = clock
	_persons = persons
	_population = population
	for person: String in economy.call("personal_accounts"):
		var account_id: String = economy.call("personal_accounts")[person]
		if _person_accounts.has(person) and _person_accounts[person] != account_id:
			return _fail("Native account differs from the formal personal account")
		_person_accounts[person] = account_id
	return true

func manages_native(person_id: String) -> bool:
	return _native != null and bool(_native.call("manages_person", person_id))

func manages_account(account_id: String) -> bool:
	for person_id: String in _person_accounts:
		if _person_accounts[person_id] == account_id and manages_native(person_id):
			return true
	return false

func managed_population(unit_id: String) -> int:
	var count: int = 0
	for person_id: String in _person_accounts:
		# Account ownership alone does not take over a complete household need.
		if manages_native(person_id) and _population.unit_for_person(person_id) == unit_id:
			count += 1
	if _native != null:
		count += int(_native.call("managed_background_population", unit_id))
	return count

func commodity_capability(person_id: String, commodity_id: String, market_id: String = "") -> Dictionary:
	if manages_native(person_id) and commodity_id.begins_with("native:"):
		return _native.call("personal_commodity", commodity_id)
	var item := _market.commodity_for_person(commodity_id, market_id) if _market != null else {}
	if not item.is_empty():
		item["quantity_scale"] = 1000
	return item

func market_rows(person_id: String, market_id: String, limit: int, offset: int) -> Array[Dictionary]:
	if manages_native(person_id):
		return _native.call("personal_market_rows", person_id, limit, offset)
	return _market.read_only_market_rows(market_id, limit, offset) if _market != null else []

func prepare_native_source(person_id: String, source: Dictionary, kind: String) -> Dictionary:
	if not _persons.has_person(person_id) or kind not in ["native_order", "native_delivery", "native_opening", "native_balance", "native_handover"] or not source.get("source_id") is String or source["source_id"].is_empty() or not source.get("commodity_id") is String or not source["commodity_id"].begins_with("native:") or not FormalLedgerState.valid_amount(source.get("quantity")) or int(source["quantity"]) <= 0 or not FormalLedgerState.valid_amount(source.get("amount")) or not FormalLedgerState.valid_amount(source.get("effective_minute")): return {}
	var record := source.duplicate(true)
	record.merge({"record_id": "personal_life:" + str(_next_record_sequence), "kind": kind, "person_id": person_id, "quantity_scale": 1}, true)
	if kind == "native_order": return {"record":record,"sequence":_next_record_sequence}
	var good := str(source["commodity_id"]).trim_prefix("native:")
	var candidate := {person_id: {good: _native_lots.get(person_id, {}).get(good, []).duplicate(true)}}
	_add_native_lot(candidate, record)
	return {"record": record, "good": good, "lots": candidate[person_id][good], "sequence": _next_record_sequence}

func prepare_native_custody(fact: Dictionary) -> Dictionary:
	if not native_custody_ready(fact): return {}
	var record: Dictionary = _native.call("personal_commodity", fact["commodity_id"])
	record.merge(fact, true)
	record.merge({"record_id": "personal_life:"+str(_next_record_sequence), "kind": "native_custody", "quantity_scale": 1, "amount": 0}, true)
	var person := str(fact["person_id"])
	var good := str(fact["commodity_id"]).trim_prefix("native:")
	var candidate := {person: {good: _native_lots.get(person, {}).get(good, []).duplicate(true)}}
	if not _move_lot_custody(candidate, record): return {}
	return {"record": record, "good": good, "lots": candidate[person][good], "sequence": _next_record_sequence}

func prepare_native_loss(fact: Dictionary) -> Dictionary:
	var person := str(fact.get("person_id", ""))
	var good := str(fact.get("commodity_id", "")).trim_prefix("native:")
	var candidate := {person: {good: _native_lots.get(person, {}).get(good, []).duplicate(true)}}
	if not _loss_sources_ready(candidate, fact): return {}
	var record: Dictionary = _native.call("personal_commodity", fact["commodity_id"])
	record.merge(fact, true)
	record.merge({"record_id": "personal_life:"+str(_next_record_sequence), "kind": "native_loss", "quantity_scale": 1, "amount": 0}, true)
	_use_native_lots(candidate, record)
	return {"record": record, "good": good, "lots": candidate[person][good], "sequence": _next_record_sequence}

static func _loss_sources_ready(lots: Dictionary, fact: Dictionary) -> bool:
	if not fact.get("allocations") is Array or fact["allocations"].is_empty() or not FormalLedgerState.valid_amount(fact.get("quantity")) or int(fact["quantity"]) <= 0: return false
	var available: Dictionary = {}
	for lot: Dictionary in lots.get(fact.get("person_id", ""), {}).get(str(fact.get("commodity_id", "")).trim_prefix("native:"), []): available[lot["purchase_record_id"]] = _lot_positions(lot)
	var total := 0
	for a: Variant in fact["allocations"]:
		if not a is Dictionary or not available.has(a.get("purchase_record_id")) or not a.get("custody_key") is String or not FormalLedgerState.valid_amount(a.get("quantity")) or int(a["quantity"]) <= 0: return false
		var positions := available[a["purchase_record_id"]] as Dictionary
		if int(positions.get(a["custody_key"], 0)) < int(a["quantity"]) or total > int(fact["quantity"])-int(a["quantity"]): return false
		positions[a["custody_key"]] -= int(a["quantity"])
		total += int(a["quantity"])
	return total == int(fact["quantity"])

## Synchronous adoption after business prechecks and Ledger adoption.
func adopt_native_change(prepared: Dictionary) -> void:
	assert(not prepared.is_empty() and prepared["sequence"] == _next_record_sequence)
	if prepared["record"]["kind"] != "native_order":
		var person := str(prepared["record"]["person_id"])
		if not _native_lots.has(person): _native_lots[person] = {}
		_native_lots[person][prepared["good"]] = prepared["lots"]
	_append_living_record(prepared["record"])

func record_native_source(person_id: String, source: Dictionary, kind: String) -> bool:
	var prepared := prepare_native_source(person_id, source, kind)
	if prepared.is_empty(): return _fail("Invalid native source")
	adopt_native_change(prepared)
	return true

static func _add_native_lot(lots: Dictionary, record: Dictionary) -> void:
	var person := str(record["person_id"])
	var good := str(record["commodity_id"]).trim_prefix("native:")
	if not lots.has(person):
		lots[person] = {}
	if not lots[person].has(good):
		lots[person][good] = []
	var lot := {"purchase_record_id": record["record_id"], "source_id": record["source_id"], "remaining": record["quantity"], "effective_minute": record["effective_minute"]}
	if record.get("custody_mode", "") == "STORED": lot["positions"] = {"STORED|" + str(record["custody_place_id"]): record["quantity"]}
	lots[person][good].append(lot)

func native_allocations(person: String, good: String, quantity: int) -> Array[Dictionary]:
	return _lot_allocations(_native_lots, person, good, quantity, _persons.current_place(person), _persons.is_at_place(person, _persons.current_place(person)))

## A lot's positions partition its one remaining quantity. Omitted positions in
## old saves retain the existing carried-property meaning, without freight history.
static func _lot_positions(lot: Dictionary) -> Dictionary:
	return lot.get("positions", {"CARRIED": lot["remaining"]}).duplicate(true)

static func _lot_allocations(lots: Dictionary, person: String, good: String, quantity: int, place: String = "", present: bool = false, custody: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var remaining := quantity
	for lot: Dictionary in lots.get(person, {}).get(good, []):
		var positions := _lot_positions(lot)
		var keys: Array[String] = []
		if not custody.is_empty(): keys.append(custody)
		elif place.is_empty(): keys.assign(positions.keys()) # Historical v3 FIFO.
		else:
			keys.append("CARRIED")
			if present: keys.append("STORED|" + place)
		for key: String in keys:
			var amount := mini(remaining, int(positions.get(key, 0)))
			if amount <= 0: continue
			var allocation := {"purchase_record_id": lot["purchase_record_id"], "quantity": amount}
			if not place.is_empty() or not custody.is_empty(): allocation["custody_key"] = key
			result.append(allocation)
			remaining -= amount
			if remaining == 0: return result
	return []

static func _use_native_lots(lots: Dictionary, record: Dictionary) -> void:
	var owned := lots[record["person_id"]][str(record["commodity_id"]).trim_prefix("native:")] as Array
	for allocation: Dictionary in record["allocations"]:
		for lot: Dictionary in owned:
			if lot["purchase_record_id"] != allocation["purchase_record_id"]: continue
			if lot.has("positions") or allocation.has("custody_key"):
				var positions := _lot_positions(lot)
				var key := str(allocation.get("custody_key", "CARRIED"))
				positions[key] = int(positions.get(key, 0)) - int(allocation["quantity"])
				if positions[key] == 0: positions.erase(key)
				lot["positions"] = positions
			lot["remaining"] = int(lot["remaining"]) - int(allocation["quantity"])
			break
	for index: int in range(owned.size() - 1, -1, -1):
		if int(owned[index]["remaining"]) == 0: owned.remove_at(index)

func native_usable_inventory(person: String, carried_only: bool = false) -> Dictionary:
	if _native != null and _native.has_method("personal_accessible_stock"): return _native.call("personal_accessible_stock", person, carried_only)
	var result: Dictionary = {}
	var place := _persons.current_place(person)
	var present := _persons.is_at_place(person, place)
	for good: String in _native_lots.get(person, {}):
		var amount: int = 0
		for lot: Dictionary in _native_lots[person][good]:
			var positions := _lot_positions(lot)
			amount += int(positions.get("CARRIED", 0))
			if not carried_only and present: amount += int(positions.get("STORED|" + place, 0))
		result[good] = amount
	return result

func native_custody_allocations(person: String, good: String, quantity: int, key: String) -> Array[Dictionary]:
	return _lot_allocations(_native_lots, person, good, quantity, "", false, key)

## Stage all source partitions before touching any lot. Repeated allocations
## against one source are checked cumulatively, including save replay.
static func _custody_changes(lots: Dictionary, record: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if not record.get("allocations") is Array or record["allocations"].is_empty() or not FormalLedgerState.valid_amount(record.get("quantity")) or int(record["quantity"]) <= 0: return changes
	var from_key := str(record.get("from_key", ""))
	var to_key := str(record.get("to_key", ""))
	if from_key.is_empty() or to_key.is_empty() or from_key == to_key: return changes
	var sources: Dictionary = {}
	for lot: Dictionary in lots.get(record.get("person_id", ""), {}).get(str(record.get("commodity_id", "")).trim_prefix("native:"), []):
		sources[lot["purchase_record_id"]] = lot
	var staged: Dictionary = {}
	var total: int = 0
	for allocation: Variant in record["allocations"]:
		if not allocation is Dictionary or not sources.has(allocation.get("purchase_record_id")) or allocation.get("custody_key", from_key) != from_key or not FormalLedgerState.valid_amount(allocation.get("quantity")) or int(allocation["quantity"]) <= 0: return []
		var id := str(allocation["purchase_record_id"])
		if not staged.has(id): staged[id] = _lot_positions(sources[id])
		var positions := staged[id] as Dictionary
		var amount := int(allocation["quantity"])
		if int(positions.get(from_key, 0)) < amount or int(positions.get(to_key, 0)) > FormalLedgerState.MAX_AMOUNT - amount or total > int(record["quantity"]) - amount: return []
		positions[from_key] = int(positions[from_key]) - amount
		if positions[from_key] == 0: positions.erase(from_key)
		positions[to_key] = int(positions.get(to_key, 0)) + amount
		total += amount
	if total != int(record["quantity"]): return []
	for id: String in staged:
		changes.append({"lot": sources[id], "positions": staged[id]})
	return changes

static func _move_lot_custody(lots: Dictionary, record: Dictionary) -> bool:
	var changes := _custody_changes(lots, record)
	if changes.is_empty(): return false
	for change: Dictionary in changes:
		change["lot"]["positions"] = change["positions"]
	return true

func native_custody_ready(fact: Dictionary) -> bool:
	return not _custody_changes(_native_lots, fact).is_empty()

func record_native_custody(fact: Dictionary) -> bool:
	var record: Dictionary = _native.call("personal_commodity", fact["commodity_id"])
	record.merge(fact, true)
	record.merge({"record_id": "personal_life:" + str(_next_record_sequence), "kind": "native_custody", "quantity_scale": 1, "amount": 0}, true)
	if not _move_lot_custody(_native_lots, record): return _fail("Native custody lacks its complete source partitions")
	_append_living_record(record)
	return true

func native_custody_rows(person: String, good: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: String in _native_lots.get(person, {}):
		if not good.is_empty() and item != good: continue
		for lot: Dictionary in _native_lots[person][item]:
			for key: String in _lot_positions(lot):
				var fields := key.split("|", true, 1)
				var row := {"good": item, "purchase_record_id": lot["purchase_record_id"], "source_id": lot["source_id"], "custody_key": key, "state": fields[0], "quantity": _lot_positions(lot)[key], "place_id": _persons.current_place(person) if key == "CARRIED" else fields[1] if fields[0] == "STORED" else ""}
				if fields[0] == "FREIGHT": row.merge(_native.call("personal_freight_custody", person, fields[1]), true)
				result.append(row)
	return result

func record_native_consumption(person: String, good: String, quantity: int, category: String, source: String) -> bool:
	var allocations := native_allocations(person, good, quantity)
	if allocations.is_empty():
		return _fail("Native consumption lacks its actually acquired source lots")
	var record: Dictionary = _native.call("personal_commodity", "native:" + good)
	record.merge({"record_id": "personal_life:" + str(_next_record_sequence), "kind": "native_consume", "person_id": person, "effective_minute": _clock.total_minutes(), "quantity": quantity, "quantity_scale": 1, "allocations": allocations, "activity_place_id": _persons.current_place(person), "present": _persons.is_at_place(person, _persons.current_place(person)), "need_category": category, "source": source, "amount": 0}, true)
	_use_native_lots(_native_lots, record)
	_append_living_record(record)
	return true

func record_native_failure(person: String, commodity: String, quantity: int, reason: String, source: String) -> void:
	var item := commodity_capability(person, commodity)
	_append_living_record({"record_id": "personal_life:" + str(_next_record_sequence), "kind": "native_failed", "person_id": person, "effective_minute": _clock.total_minutes(), "commodity_id": commodity, "name_zh": item.get("name_zh", commodity), "unit_name_zh": item.get("unit_name_zh", ""), "quantity": quantity, "quantity_scale": 1, "amount": 0, "reason": reason, "source": source})

func schedules_category(person: String, category: String) -> bool:
	for key: String in _arrangements.get(person, {}):
		if key.begins_with("native:") and _arrangements[person][key].get("need_category") == category:
			return true
	return false

func _set_native_arrangement(person: String, commodity: String, quantity: int, enabled: bool, auto_buy: bool) -> Dictionary:
	if not bool(_native.call("personal_authorized", person)):
		return {"success": false, "error": "人物没有此安排的行动权限。"}
	var item := commodity_capability(person, commodity)
	var previous := arrangement(person, commodity)
	if enabled:
		if item.is_empty() or not item.get("daily_supported", false) or not FormalLedgerState.valid_amount(quantity) or quantity <= 0:
			return {"success": false, "error": "商品用途或数量不允许此安排。"}
		if _clock.total_minutes() > 9223372036854774367:
			return {"success": false, "error": "没有下一期时间。"}
		if not _arrangements.has(person):
			_arrangements[person] = {}
		var due := int(previous.get("next_due_minute", _clock.total_minutes() + 1440))
		_arrangements[person][commodity] = {"quantity": quantity, "period_minutes": 1440, "next_due_minute": due, "auto_buy_missing": auto_buy, "need_category": item["need_category"], "mode": item["mode"]}
	else:
		if previous.is_empty():
			return {"success": false, "error": "没有此商品安排。"}
		quantity = int(previous["quantity"])
		_arrangements[person].erase(commodity)
	_append_living_record({"record_id": "personal_life:" + str(_next_record_sequence), "kind": "native_arrangement", "person_id": person, "effective_minute": _clock.total_minutes(), "commodity_id": commodity, "name_zh": item.get("name_zh", commodity), "unit_name_zh": item.get("unit_name_zh", ""), "quantity": quantity, "quantity_scale": 1, "amount": 0, "enabled": enabled, "auto_buy_missing": auto_buy})
	_recompute_next_consumption()
	return {"success": true, "message": "已保存消费安排。采购许可与到货条件单独生效。" if enabled else "已取消消费安排。"}

func _settle_native_arrangements() -> Dictionary:
	var completed: int = 0
	var failed: int = 0
	var persons := _arrangements.keys()
	persons.sort()
	for person: String in persons:
		var keys: Array = _arrangements[person].keys()
		keys.sort()
		for commodity: String in keys:
			if not manages_native(person) or not commodity.begins_with("native:"):
				continue
			var plan := _arrangements[person][commodity] as Dictionary
			if int(plan["next_due_minute"]) > _clock.total_minutes():
				continue
			var owned := holding(person, commodity)
			var quantity := int(plan["quantity"])
			var item := commodity_capability(person, commodity)
			var gap := maxi(0, quantity - int(owned.get("quantity", 0)) - int(_native.call("personal_incoming", person, commodity)))
			var result: Dictionary
			if item.get("mode") == "durable":
				var allocations := native_allocations(person, str(item["good"]), quantity)
				result = {"success": bool(_native.call("personal_authorized", person)) and not allocations.is_empty(), "error": "耐用品尚未实际持有或人物无行动权限。"}
				if result["success"]:
					var record := item.duplicate(true)
					record.merge({"record_id": "personal_life:" + str(_next_record_sequence), "kind": "native_holding_use", "person_id": person, "effective_minute": _clock.total_minutes(), "quantity": quantity, "quantity_scale": 1, "allocations": allocations, "activity_place_id": _persons.current_place(person), "present": _persons.is_at_place(person, _persons.current_place(person)), "amount": 0, "source": "daily_holding_target"}, true)
					_append_living_record(record)
				else:
					record_native_failure(person, commodity, quantity, result["error"], "daily")
			else:
				var available := mini(quantity, int(owned.get("quantity", 0)))
				result = consume(person, commodity, available, "daily") if available > 0 else {"success": false, "error": "商品尚未实际到货。"}
				if result.get("success", false) and available < quantity:
					result = {"success": false, "error": "已消费现有持有；剩余数量尚未取得。"}
					record_native_failure(person, commodity, quantity-available, result["error"], "daily")
				elif available == 0:
					record_native_failure(person, commodity, quantity, result["error"], "daily")
			if plan["auto_buy_missing"] and gap > 0:
				purchase(person, "", commodity, gap)
			if result.get("success", false):
				completed += 1
			else:
				failed += 1
			if int(plan["next_due_minute"]) > 9223372036854774367:
				_arrangements[person].erase(commodity)
			else:
				plan["next_due_minute"] = int(plan["next_due_minute"]) + int(plan["period_minutes"])
	_recompute_next_consumption()
	return {"completed": completed, "failed": failed}

func _restore_native(value: Dictionary, mixed: bool = false) -> bool:
	var fields: Array[String] = ["schema_id", "policy_fingerprint", "person_accounts", "employers", "employments", "holdings", "living_records", "arrangements", "next_record_sequence", "native_lots"]
	if value.has("runtime_accounts"): fields.append("runtime_accounts")
	if value.has("livelihood_changes"): fields.append("livelihood_changes")
	if not FormalLedgerState.exact_fields(value, fields) or value["schema_id"] != SCHEMA_ID or (not mixed and (value["policy_fingerprint"] != "" or value["person_accounts"] != _native.call("personal_accounts") or value["employers"] != {} or value["employments"] != {} or value["holdings"] != {})):
		return _fail("Native personal state cannot reinterpret legacy wage or milli-unit property")
	for field: String in ["living_records", "arrangements", "native_lots"]:
		if not value[field] is Dictionary:
			return _fail("Invalid native personal container")
	var rebuilt: Dictionary = {}
	var seen: Dictionary = {}
	var sources: Dictionary = {}
	var custody_sources: Dictionary = {}
	var used: Dictionary = {}
	var account_scope: Dictionary = value["person_accounts"] if mixed else _person_accounts
	for person: Variant in value["living_records"]:
		if not person is String or not account_scope.has(person) or not value["living_records"][person] is Array:
			return _fail("Unknown native living record person")
		var last: int = -1
		for raw: Variant in value["living_records"][person]:
			if not raw is Dictionary:
				return _fail("Invalid native living record")
			var record := raw as Dictionary
			var id := str(record.get("record_id", ""))
			if mixed and not str(record.get("kind", "")).begins_with("native_"):
				seen[id] = true
				continue
			if not id.begins_with("personal_life:") or id != "personal_life:" + str(int(id.trim_prefix("personal_life:"))) or int(id.trim_prefix("personal_life:")) < 1 or seen.has(id) or record.get("person_id") != person or not record.get("kind") is String or not record.get("commodity_id") is String or not record.get("name_zh") is String or not record.get("unit_name_zh") is String or record.get("quantity_scale") != 1 or not FormalLedgerState.valid_amount(record.get("quantity")) or not FormalLedgerState.valid_amount(record.get("effective_minute")) or int(record["effective_minute"]) < last or int(record["effective_minute"]) > _clock.total_minutes():
				return _fail("Invalid native living record identity or date")
			seen[id] = true
			last = int(record["effective_minute"])
			var good := str(record.get("commodity_id", "")).trim_prefix("native:")
			var key := str(person) + "|" + good
			if record["kind"] in ["native_opening", "native_balance", "native_delivery", "native_order", "native_handover"]:
				if not bool(_native.call("valid_personal_source", person, record)) or (record["kind"] != "native_order" and sources.has(record["source_id"])):
					return _fail("Native property source lacks its economic responsibility")
				if record["kind"] != "native_order":
					sources[record["source_id"]] = true
					_add_native_lot(rebuilt, record)
					if record["kind"] == "native_balance":
						used[key] = int(used.get(key, 0)) + int(record["previous_used"])
			elif record["kind"] == "native_custody":
				var fact: Dictionary = _native.call("personal_custody_source", str(record.get("source_id", "")), str(record.get("operation", "")))
				var custody_source := str(record.get("operation", "")) + "|" + str(record.get("source_id", ""))
				if fact.is_empty() or record.get("amount") != 0 or custody_sources.has(custody_source): return _fail("Custody lacks its accepted owner action or original freight responsibility")
				custody_sources[custody_source] = true
				for field: String in fact:
					if record.get(field) != fact[field]: return _fail("Custody differs from its economic source")
				if (record.get("operation") not in ["freight_collect", "freight_cancel"] and record.get("allocations") != _lot_allocations(rebuilt, person, good, int(record["quantity"]), "", false, record["from_key"])) or not _move_lot_custody(rebuilt, record): return _fail("Custody lacks its actual original lots")
			elif record["kind"] == "native_loss":
				var fact: Dictionary = _native.call("personal_loss_source", str(record.get("source_id", "")))
				if fact.is_empty() or record.get("amount") != 0 or custody_sources.has("loss|"+str(record["source_id"])): return _fail("Personal loss lacks adopted physical portions")
				for field: String in fact:
					if record.get(field) != fact[field]: return _fail("Personal loss differs from physical source")
				if not _loss_sources_ready(rebuilt, record): return _fail("Personal loss reuses an unavailable source partition")
				custody_sources["loss|"+str(record["source_id"])] = true
				_use_native_lots(rebuilt, record) # No consumption or need satisfaction.
			elif record["kind"] == "native_consume":
				if record.get("amount") != 0 or record.get("allocations") != _lot_allocations(rebuilt, person, good, int(record["quantity"]), str(record.get("activity_place_id", "")), bool(record.get("present", false))) or record["allocations"].is_empty() or not bool(_native.call("valid_personal_use", record)):
					return _fail("Native consumption lacks its FIFO sources or actual use")
				_use_native_lots(rebuilt, record)
				used[key] = int(used.get(key, 0)) + int(record["quantity"])
			elif record["kind"] == "native_holding_use":
				var item: Dictionary = _native.call("personal_commodity", str(record["commodity_id"]))
				if item.get("mode") != "durable" or record.get("amount") != 0 or record.get("allocations") != _lot_allocations(rebuilt, person, good, int(record["quantity"]), str(record.get("activity_place_id", "")), bool(record.get("present", false))) or record["allocations"].is_empty():
					return _fail("Durable holding target lacks its actually held lots")
			elif record["kind"] == "native_failed":
				if record.get("amount") != 0 or not record.get("reason") is String or not record.get("source") is String:
					return _fail("Invalid native refusal record")
			elif record["kind"] == "native_arrangement":
				if record.get("amount") != 0 or not record.get("enabled") is bool or not record.get("auto_buy_missing") is bool:
					return _fail("Invalid native arrangement record")
			else:
				return _fail("Unsupported native personal record")
	if not FormalLedgerState.valid_amount(value["next_record_sequence"]) or int(value["next_record_sequence"]) != seen.size() + 1 or rebuilt != value["native_lots"]:
		return _fail("Native source lots differ from living records")
	for number: int in range(1, int(value["next_record_sequence"])):
		if not seen.has("personal_life:" + str(number)):
			return _fail("Missing native living record")
	for person: String in _native.call("personal_accounts"):
		var inventory: Dictionary = _native.call("personal_owned_inventory", person)
		for good: String in inventory:
			var quantity: int = 0
			for lot: Dictionary in rebuilt.get(person, {}).get(good, []):
				quantity += int(lot["remaining"])
				var partition: int = 0
				for position: String in _lot_positions(lot):
					var amount: Variant = _lot_positions(lot)[position]
					if not FormalLedgerState.valid_amount(amount) or int(amount) == 0 or not bool(_native.call("valid_personal_custody_key", person, position, good)): return _fail("Invalid property custody position")
					partition += int(amount)
				if partition != int(lot["remaining"]): return _fail("Lot positions duplicate or lose property")
			if quantity != int(inventory[good]) or int(used.get(person + "|" + good, 0)) != int(_native.call("personal_used", person, good)):
				return _fail("Native lots differ from the sole inventory and physical consumption")
	for person: Variant in value["arrangements"]:
		if not account_scope.has(person) or not value["arrangements"][person] is Dictionary:
			return _fail("Invalid native arrangement person")
		for commodity: Variant in value["arrangements"][person]:
			if mixed and not str(commodity).begins_with("native:"): continue
			var plan: Variant = value["arrangements"][person][commodity]
			var item := commodity_capability(person, str(commodity))
			if not commodity is String or not plan is Dictionary or not FormalLedgerState.exact_fields(plan, ["quantity", "period_minutes", "next_due_minute", "auto_buy_missing", "need_category", "mode"]) or not FormalLedgerState.valid_amount(plan["quantity"]) or int(plan["quantity"]) <= 0 or plan["period_minutes"] != 1440 or not FormalLedgerState.valid_amount(plan["next_due_minute"]) or int(plan["next_due_minute"]) <= _clock.total_minutes() or int(plan["next_due_minute"]) > _clock.total_minutes() + 1440 or not plan["auto_buy_missing"] is bool or item.get("need_category") != plan["need_category"] or item.get("mode") != plan["mode"]:
				return _fail("Invalid native arrangement unit, purpose or date")
	for person: String in _native.call("personal_accounts"):
		if not bool(_native.call("valid_personal_freight_lots", person, rebuilt.get(person, {}))): return _fail("Personal freight differs from its original held lots")
	_native_lots = rebuilt
	if mixed: return true
	_living_records = value["living_records"].duplicate(true)
	_living_by_id.clear()
	for records: Array in _living_records.values():
		for record: Dictionary in records:
			_living_by_id[record["record_id"]] = record
	_arrangements = value["arrangements"].duplicate(true)
	_next_record_sequence = int(value["next_record_sequence"])
	_recompute_next_consumption()
	return true

## Old native saves had no per-lot consumption history. Record their existing
## balance with that limitation; do not manufacture purchases or change stock.
func adopt_native_balances() -> void:
	for person: String in _person_accounts:
		var inventory: Dictionary = _native.call("personal_owned_inventory", person)
		for good: String in inventory:
			if int(inventory[good]) > 0 or int(_native.call("personal_used", person, good)) > 0:
				var source: Dictionary = _native.call("personal_balance_source", person, good)
				record_native_source(person, source, "native_balance")


# This alias is a page view only. Native saves retain integer quantity and unit;
# historical v2 quantities keep their original milli-unit meaning.
static func _living_view(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	if result.get("quantity_scale") == 1:
		result["quantity_milli"] = result["quantity"]
	else:
		result["quantity_scale"] = 1000
	return result

## Construction rollback only. Active belongings and wage/order responsibilities
## cannot disappear through rebinding a personal account or deleting selection.
func unbind_native(ledger: FormalLedgerState) -> bool:
	if _native != null and _native.has_method("management_active") and bool(_native.call("management_active")):
		return _fail("Active personal native responsibility requires an explicit business handover")
	_native = null
	_native_lots.clear()
	_ledger = ledger
	return true

func can_carry_on_person_trip(person: String, limits: Dictionary) -> bool:
	for commodity: String in _holdings.get(person, {}):
		var amount := int(_holdings[person][commodity].get("quantity_milli", 0))
		if amount > int(limits.get(commodity, 0)): return false
	if _native != null:
		var inventory := native_usable_inventory(person, true)
		for good: String in inventory:
			if int(inventory[good]) > int(limits.get("native:"+good, 0)): return false
	return true

## Observation only. Older records lacking activity place are left unlocated.
func native_consumption_places(person: String) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in _living_records.get(person, []):
		if record.get("kind") != "native_consume": continue
		var place := str(record.get("activity_place_id", "UNRECORDED_ACTIVITY_PLACE"))
		var good := str(record["commodity_id"]).trim_prefix("native:")
		if not result.has(place): result[place] = {}
		result[place][good] = int(result[place].get(good, 0)) + int(record["quantity"])
	return result


func apply_residence_boundary() -> int:
	var world := _persons._formal_world()
	return _population.apply_residence_boundary(world) if world != null else 0


static func _legacy_fifo(owned: Dictionary, quantity: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var remaining := quantity
	for lot: Dictionary in owned.get("lots", []):
		var taken := mini(remaining, int(lot["remaining_milli"]))
		if taken > 0: result.append({"purchase_record_id": lot["purchase_record_id"], "quantity_milli": taken})
		remaining -= taken
		if remaining == 0: break
	return result if remaining == 0 else []

func owned_handover_plan(person: String, rows: Array) -> Dictionary:
	var facts: Array[Dictionary] = []
	var mapped_totals: Dictionary = {}
	for id: String in _holdings.get(person, {}):
		var owned := _holdings[person][id] as Dictionary
		var quantity := int(owned.get("quantity_milli", 0))
		if quantity == 0: continue
		var mapping := CommodityMapping.find(rows, id)
		var converted := CommodityMapping.to_native(mapping, quantity)
		if not converted.get("success", false) or not mapping.get("operations", []).has("PERSONAL_OWNED_HANDOVER"): return {"success": false, "reason": "PERSONAL_PROPERTY_MAPPING_UNAVAILABLE:"+id+":"+str(converted.get("reason", "OPERATION_NOT_PERMITTED"))}
		if owned["unit_name_zh"] != mapping["legacy_unit_name_zh"]: return {"success": false, "reason": "PERSONAL_PROPERTY_UNIT_DIFFERS:"+id}
		var allocations := _legacy_fifo(owned, quantity)
		if allocations.is_empty(): return {"success": false, "reason": "PERSONAL_PROPERTY_HAS_NO_SOURCE_LOTS"}
		var good := str(mapping["native_good_id"])
		if int(converted["quantity"]) > FormalLedgerState.MAX_AMOUNT-int(mapped_totals.get(good, 0)): return {"success": false, "reason": "MAPPED_PERSONAL_PROPERTY_EXCEEDS_STOCK_BOUNDS"}
		mapped_totals[good] = int(mapped_totals.get(good, 0))+int(converted["quantity"])
		facts.append({"person_id": person, "legacy_commodity_id": id, "legacy_quantity_milli": quantity, "good": mapping["native_good_id"], "quantity": converted["quantity"], "mapping_id": mapping["id"], "allocations": allocations})
	return {"success": true, "facts": facts}

static func _remove_handed_over_holding(holdings: Dictionary, record: Dictionary) -> void:
	var owned := holdings[record["person_id"]][record["commodity_id"]] as Dictionary
	var lots := owned["lots"] as Array
	for allocation: Dictionary in record["allocations"]:
		for lot: Dictionary in lots:
			if lot["purchase_record_id"] == allocation["purchase_record_id"]:
				lot["remaining_milli"] = int(lot["remaining_milli"])-int(allocation["quantity_milli"])
				break
	for index: int in range(lots.size()-1, -1, -1):
		if lots[index]["remaining_milli"] == 0: lots.remove_at(index)
	owned["quantity_milli"] = int(owned["quantity_milli"])-int(record["quantity_milli"])

func commit_owned_handover(fact: Dictionary, source: Dictionary) -> void:
	var person := str(fact["person_id"])
	var owned := _holdings[person][fact["legacy_commodity_id"]] as Dictionary
	var record := {"record_id": "personal_life:"+str(_next_record_sequence), "kind": "legacy_handover", "person_id": person, "commodity_id": fact["legacy_commodity_id"], "name_zh": owned["name_zh"], "unit_name_zh": owned["unit_name_zh"], "quantity_milli": fact["legacy_quantity_milli"], "allocations": fact["allocations"].duplicate(true), "source_id": fact["id"], "effective_minute": fact["effective_minute"], "amount": 0}
	_remove_handed_over_holding(_holdings, record)
	_append_living_record(record)
	record_native_source(person, source, "native_handover")

func native_exit_reason(person: String, restored_history: bool = false) -> String:
	if not _persons.is_alive(person) or _person_scope(person).is_empty() or not _person_accounts.has(person): return "NO_LEGACY_PERSONAL_AND_POPULATION_RECEIVER"
	if _policy.is_empty() or _market == null: return "NO_LEGACY_LIVELIHOOD_CONFIGURATION"
	if _employments.has(person) and legacy_wage_end(person) < 0: return "LEGACY_WAGE_RESPONSIBILITY_REQUIRES_EXPLICIT_HANDOVER"
	if not restored_history and not (_arrangements.get(person, {}) as Dictionary).is_empty(): return "PERSONAL_CONSUMPTION_ARRANGEMENTS_REMAIN_ACTIVE"
	for lot_rows: Array in _native_lots.get(person, {}).values():
		if not lot_rows.is_empty(): return "PERSONAL_PROPERTY_REQUIRES_RECEIVER"
	return ""


func legacy_wage_end(person: String, include_pending: bool = false) -> int:
	for change: Dictionary in _livelihood_changes.values():
		if change["person_id"] == person and change["command"]["kind"] == "terminate_legacy_wage" and (change["status"] == "APPLIED" or include_pending): return int(change["boundary_minute"])
	return -1

func next_livelihood_boundary() -> int:
	var next: int = -1
	for change: Dictionary in _livelihood_changes.values():
		if change["status"] != "QUEUED" or change["command"]["kind"] == "convert_legacy_arrangement": continue
		if next < 0 or int(change["boundary_minute"]) < next: next = int(change["boundary_minute"])
	return next

func request_livelihood_change(person: String, command: Dictionary) -> Dictionary:
	var world := _persons._formal_world()
	if world == null or person != world.player_state.player_id() or not _persons.is_alive(person) or not FormalLedgerState.exact_fields(command, ["action_id", "minute", "kind", "payload"]) or not command["action_id"] is String or command["action_id"].is_empty() or not command["payload"] is Dictionary: return {"accepted": false, "reason": "NO_LIVELIHOOD_ACTION_AUTHORITY"}
	var id := str(command["action_id"])
	if _livelihood_changes.has(id):
		var prior := _livelihood_changes[id] as Dictionary
		return prior["result"].duplicate(true) if prior["person_id"] == person and prior["command"] == command else {"accepted": false, "reason": "ACTION_ID_CONFLICT"}
	if command["minute"] != _clock.total_minutes() or _livelihood_changes.size() >= 128 or world.military_state.active_actions.has(id) or _persons.has_travel_action(id) or (world.economy_r1 != null and world.economy_r1._commands.has(id)): return {"accepted": false, "reason": "STALE_OR_CONFLICTING_LIVELIHOOD_ACTION"}
	var payload := command["payload"] as Dictionary
	var kind := str(command["kind"])
	var boundary: int = (_clock.total_minutes()/1440+1)*1440
	if _clock.total_minutes() > FormalLedgerState.MAX_AMOUNT-10080: return {"accepted": false, "reason": "LIVELIHOOD_TIME_LIMIT"}
	if kind == "terminate_legacy_wage":
		if payload != {} or not _employments.has(person) or legacy_wage_end(person, true) >= 0: return {"accepted": false, "reason": "NO_ACTIVE_LEGACY_WAGE"}
		var contract := _employments[person] as Dictionary
		var period := int(contract["pay_period_minutes"])
		if _clock.total_minutes() > FormalLedgerState.MAX_AMOUNT-period: return {"accepted": false, "reason": "WAGE_CUTOFF_TIME_LIMIT"}
		boundary = (_clock.total_minutes()/period+1)*period
	elif kind in ["cancel_legacy_arrangement", "convert_legacy_arrangement"]:
		var fields: Array[String] = []
		fields.assign(["commodity_id", "auto_buy_missing"] if kind == "convert_legacy_arrangement" else ["commodity_id"])
		if not FormalLedgerState.exact_fields(payload, fields) or not payload["commodity_id"] is String or str(payload["commodity_id"]).begins_with("native:") or arrangement(person, payload["commodity_id"]).is_empty(): return {"accepted": false, "reason": "NO_ACTIVE_LEGACY_ARRANGEMENT"}
		for row: Dictionary in _livelihood_changes.values():
			if row["person_id"] == person and row["status"] == "QUEUED" and row["command"]["payload"].get("commodity_id") == payload["commodity_id"]: return {"accepted": false, "reason": "ARRANGEMENT_CHANGE_ALREADY_PENDING"}
		if kind == "convert_legacy_arrangement":
			if not payload["auto_buy_missing"] is bool: return {"accepted": false, "reason": "AUTO_PURCHASE_AUTHORIZATION_REQUIRED"}
			var conversion := _plan_conversion(person, payload["commodity_id"], payload["auto_buy_missing"])
			if not conversion.get("success", false): return {"accepted": false, "reason": conversion["reason"]}
	else: return {"accepted": false, "reason": "UNKNOWN_LIVELIHOOD_CHANGE"}
	var result := {"accepted": true, "reason": "LIVELIHOOD_CHANGE_QUEUED", "boundary_minute": boundary}
	_livelihood_changes[id] = {"person_id": person, "command": command.duplicate(true), "boundary_minute": boundary, "effective_minute": -1, "status": "QUEUED", "scope_request_id": "", "conversion": {}, "result": result.duplicate(true)}
	return result

func apply_livelihood_boundary() -> void:
	var now := _clock.total_minutes()
	for row: Dictionary in _livelihood_changes.values():
		if row["status"] != "QUEUED" or int(row["boundary_minute"]) > now: continue
		var command := row["command"] as Dictionary
		if command["kind"] == "convert_legacy_arrangement": continue # Only admission commits both sides.
		if command["kind"] == "cancel_legacy_arrangement":
			var commodity := str(command["payload"]["commodity_id"])
			if not arrangement(row["person_id"], commodity).is_empty(): set_daily_consumption(row["person_id"], commodity, 1, false)
		row["status"] = "APPLIED"
		row["effective_minute"] = now

func _plan_conversion(person: String, commodity: String, auto_buy: bool) -> Dictionary:
	if _native == null or _market == null: return {"success": false, "reason": "NO_NATIVE_PLAN_RECEIVER"}
	var mapping := CommodityMapping.find(_native.get("config").get("commodity_mappings", []), commodity)
	var plan := arrangement(person, commodity)
	var converted := CommodityMapping.to_native(mapping, int(plan.get("quantity_milli", 0)))
	var item: Dictionary = _native.call("personal_commodity", "native:"+str(mapping.get("native_good_id", "")))
	var legacy := _market.commodity_for_person(commodity)
	if not converted.get("success", false): return converted
	if not mapping.get("operations", []).has("FUTURE_FLOW_ARRANGEMENT") or not legacy.get("consumable", false) or not item.get("consumable", false) or item.get("mode") != "flow" or item.get("need_category", "").is_empty() or plan.get("period_minutes") != 1440: return {"success": false, "reason": "CONSUMPTION_PURPOSE_OR_PERIOD_HAS_NO_EXPLICIT_MAPPING"}
	return {"success": true, "commodity_id": item["commodity_id"], "mapping_id": mapping["id"], "legacy_quantity_milli": plan["quantity_milli"], "plan": {"quantity": converted["quantity"], "period_minutes": 1440, "next_due_minute": plan["next_due_minute"], "auto_buy_missing": auto_buy, "need_category": item["need_category"], "mode": "flow"}}

func pending_plan_conversion(person: String, commodity: String) -> bool:
	for row: Dictionary in _livelihood_changes.values():
		if row["person_id"] == person and row["status"] == "QUEUED" and row["command"]["kind"] == "convert_legacy_arrangement" and row["command"]["payload"]["commodity_id"] == commodity:
			return bool(_plan_conversion(person, commodity, row["command"]["payload"]["auto_buy_missing"]).get("success", false))
	return false

func commit_native_arrangements(person: String, scope_request: String, minute: int) -> void:
	for row: Dictionary in _livelihood_changes.values():
		if row["person_id"] != person or row["status"] != "QUEUED" or row["command"]["kind"] != "convert_legacy_arrangement": continue
		var payload := row["command"]["payload"] as Dictionary
		var conversion := _plan_conversion(person, payload["commodity_id"], payload["auto_buy_missing"])
		if not conversion.get("success", false): continue # Preparation has already required success.
		_arrangements[person].erase(payload["commodity_id"])
		_arrangements[person][conversion["commodity_id"]] = conversion["plan"].duplicate(true)
		row["conversion"] = conversion
		row["status"] = "APPLIED"
		row["effective_minute"] = minute
		row["scope_request_id"] = scope_request
	_recompute_next_consumption()

func livelihood_view(person: String) -> Dictionary:
	var changes: Array[Dictionary] = []
	for row: Dictionary in _livelihood_changes.values():
		if row["person_id"] == person: changes.append(row.duplicate(true))
	var contract := employment(person)
	var end := legacy_wage_end(person)
	var through := mini(_clock.total_minutes(), end) if end >= 0 else _clock.total_minutes()
	var overdue: int = 0
	if not contract.is_empty() and through >= int(contract["next_pay_boundary"]): overdue = (through-int(contract["next_pay_boundary"]))/int(contract["pay_period_minutes"])+1
	return {"changes": changes, "legacy_wage_end_minute": end, "can_terminate_legacy_wage": not contract.is_empty() and legacy_wage_end(person, true) < 0, "legacy_wage": contract, "overdue_legacy_periods": overdue, "legacy_payer_account_id": contract.get("payer_account_id", ""), "arrangements": (_arrangements.get(person, {}) as Dictionary).duplicate(true), "next_boundary_minute": (_clock.total_minutes()/1440+1)*1440}

func _restore_livelihood_changes(raw: Variant, employments: Variant) -> bool:
	if not raw is Dictionary or raw.size() > 128 or not employments is Dictionary: return _fail("Invalid livelihood change journal")
	var wages: Dictionary = {}
	for id: Variant in raw:
		var row: Variant = raw[id]
		if not id is String or not row is Dictionary or not FormalLedgerState.exact_fields(row, ["person_id", "command", "boundary_minute", "effective_minute", "status", "scope_request_id", "conversion", "result"]) or not row["command"] is Dictionary or not row["conversion"] is Dictionary or not row["result"] is Dictionary: return _fail("Invalid livelihood authority fact")
		var command := row["command"] as Dictionary
		var world := _persons._formal_world()
		if not FormalLedgerState.exact_fields(command, ["action_id", "minute", "kind", "payload"]) or command["action_id"] != id or world == null or row["person_id"] != world.player_state.player_id() or not _persons.is_alive(row["person_id"]) or not command["payload"] is Dictionary or not FormalLedgerState.valid_amount(command["minute"]) or int(command["minute"]) > _clock.total_minutes() or row["status"] not in ["QUEUED", "APPLIED"] or not FormalLedgerState.valid_amount(row["boundary_minute"]) or int(row["boundary_minute"]) <= int(command["minute"]) or typeof(row["effective_minute"]) != TYPE_INT: return _fail("Livelihood change lacks current legal actor and time")
		if row["status"] == "APPLIED":
			if int(row["effective_minute"]) < int(row["boundary_minute"]) or int(row["effective_minute"]) > _clock.total_minutes(): return _fail("Invalid completed livelihood boundary")
		elif row["effective_minute"] != -1 or (command["kind"] != "convert_legacy_arrangement" and int(row["boundary_minute"]) <= _clock.total_minutes()): return _fail("Unprocessed livelihood boundary")
		var payload := command["payload"] as Dictionary
		if command["kind"] == "terminate_legacy_wage":
			if payload != {} or not employments.has(row["person_id"]) or wages.has(row["person_id"]): return _fail("Unrelated or repeated wage termination")
			var period := int(employments[row["person_id"]].get("pay_period_minutes", 0))
			if period <= 0 or row["boundary_minute"] != (int(command["minute"])/period+1)*period: return _fail("Wage termination changes original period semantics")
			wages[row["person_id"]] = true
			if not employments[row["person_id"]].get("settled_periods", []) is Array or employments[row["person_id"]]["settled_periods"].size()*period > int(row["boundary_minute"]): return _fail("Wages paid beyond their retained cutoff")
		elif command["kind"] in ["cancel_legacy_arrangement", "convert_legacy_arrangement"]:
			var fields: Array[String] = []
			fields.assign(["commodity_id", "auto_buy_missing"] if command["kind"] == "convert_legacy_arrangement" else ["commodity_id"])
			if not FormalLedgerState.exact_fields(payload, fields) or not payload["commodity_id"] is String or str(payload["commodity_id"]).begins_with("native:") or int(row["boundary_minute"])%1440 != 0: return _fail("Invalid future arrangement transition")
			if command["kind"] == "convert_legacy_arrangement":
				if not payload["auto_buy_missing"] is bool: return _fail("Conversion has no purchase authorization")
				if row["status"] == "APPLIED":
					if _native == null or not bool(_native.call("valid_plan_admission", row["person_id"], row["scope_request_id"], row["effective_minute"])): return _fail("Conversion lacks real native admission")
					var mapping := CommodityMapping.find(_native.get("config").get("commodity_mappings", []), payload["commodity_id"])
					var fact := row["conversion"] as Dictionary
					if not FormalLedgerState.exact_fields(fact, ["success", "commodity_id", "mapping_id", "legacy_quantity_milli", "plan"]) or fact["success"] != true or not fact["plan"] is Dictionary or not FormalLedgerState.exact_fields(fact["plan"], ["quantity", "period_minutes", "next_due_minute", "auto_buy_missing", "need_category", "mode"]): return _fail("Invalid converted plan source")
					var item: Dictionary = _native.call("personal_commodity", str(fact["commodity_id"]))
					if item.get("mode") != "flow" or not item.get("consumable", false) or item.get("need_category") != fact["plan"]["need_category"] or fact["plan"]["period_minutes"] != 1440 or int(fact["plan"].get("next_due_minute", -1)) > int(row["effective_minute"])+1440: return _fail("Converted plan loses its actual consumption purpose or period")
					var quantity := CommodityMapping.to_native(mapping, int(fact.get("legacy_quantity_milli", 0)))
					if not mapping.get("operations", []).has("FUTURE_FLOW_ARRANGEMENT") or not quantity.get("success", false) or fact.get("mapping_id") != mapping.get("id") or fact.get("commodity_id") != "native:"+str(mapping.get("native_good_id")) or fact.get("plan", {}).get("quantity") != quantity["quantity"] or fact["plan"].get("mode") != "flow" or fact["plan"].get("auto_buy_missing") != payload["auto_buy_missing"] or int(fact["plan"].get("next_due_minute", -1)) <= int(row["effective_minute"]): return _fail("Conversion loses original quantity, purpose or next due time")
		else: return _fail("Unsupported livelihood transition")
		if row["result"] != {"accepted": true, "reason": "LIVELIHOOD_CHANGE_QUEUED", "boundary_minute": row["boundary_minute"]}: return _fail("Livelihood result differs from accepted request")
	_livelihood_changes = raw.duplicate(true)
	return true


func arrangement_conversion_quote(person: String, commodity: String) -> Dictionary:
	return _plan_conversion(person, commodity, bool(arrangement(person, commodity).get("auto_buy_missing", false)))
