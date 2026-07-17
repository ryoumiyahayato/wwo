class_name V2HouseholdService
extends RefCounted
## Owns household inventory, rent, debt and all non-employment cash commands.

var households: Dictionary = {}
var person_to_household: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var living_costs: Dictionary = {}
var _processed_key_order: Array[String] = []

const MAX_PROCESSED_KEYS: int = 1024


func configure(
	household_records: Array,
	costs: Dictionary,
	ledger: V2LedgerService
) -> void:
	households.clear()
	person_to_household.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	living_costs = costs.duplicate(true)
	for record_variant: Variant in household_records:
		var household: Dictionary = (record_variant as Dictionary).duplicate(true)
		var household_id: String = str(household.get("household_id", ""))
		household["next_rent_due_hour"] = V2DateTime.total_hour_from_iso(
			str(household.get("first_rent_due_datetime", ""))
		)
		household["next_rent_due_datetime"] = V2DateTime.iso_from_total_hour(
			int(household["next_rent_due_hour"])
		)
		household["income_current_period_centimes"] = 0
		household["expense_current_period_centimes"] = 0
		household["current_financial_status"] = "stable"
		household["unmet_needs"] = []
		household["last_daily_consumption_date"] = ""
		household["recent_transaction_ids"] = []
		households[household_id] = household
		ledger.register_household(household_id, int(household.get("cash_centimes", 0)))
		for member_id_variant: Variant in household.get("member_ids", []) as Array:
			person_to_household[str(member_id_variant)] = household_id


func household_for_person(person_id: String) -> Dictionary:
	var household_id: String = str(person_to_household.get(person_id, ""))
	var value: Variant = households.get(household_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func household_id_for_person(person_id: String) -> String:
	return str(person_to_household.get(person_id, ""))


func settle_daily_consumption(
	total_hour: int,
	conditions: V2ConditionService,
	notifications: V2NotificationService
) -> Array[V2LifeLoopResult]:
	var results: Array[V2LifeLoopResult] = []
	var date: String = V2DateTime.date_from_total_hour(total_hour)
	for household_id_variant: Variant in households.keys():
		var household_id: String = str(household_id_variant)
		var key: String = "%s:consumption:%s" % [household_id, date]
		if processed_idempotency_keys.has(key):
			results.append(V2LifeLoopResult.fail(
				"duplicate_daily_consumption", "当日住户消费已经结算", key, [household_id]
			))
			continue
		var household: Dictionary = households[household_id] as Dictionary
		var active_member_ids: Array = household.get("member_ids", []) as Array
		var required: int = active_member_ids.size()
		var food_before: int = int(household.get("food_stock_person_days", 0))
		var essentials_before: int = int(household.get("essentials_stock_person_days", 0))
		var food_deficit: bool = food_before < required
		var essentials_deficit: bool = essentials_before < required
		household["food_stock_person_days"] = maxi(0, food_before - required)
		household["essentials_stock_person_days"] = maxi(0, essentials_before - required)
		household["last_daily_consumption_date"] = date
		var unmet: Array[String] = []
		if food_deficit:
			unmet.append("food")
		if essentials_deficit:
			unmet.append("essentials")
		household["unmet_needs"] = unmet
		household["current_financial_status"] = (
			"needs_unmet" if not unmet.is_empty()
			else ("arrears" if int(household.get("rent_arrears_centimes", 0)) > 0 else "stable")
		)
		households[household_id] = household
		_remember_processed_key(key)
		for person_id_variant: Variant in active_member_ids:
			var person_id: String = str(person_id_variant)
			conditions.settle_food_need(person_id, food_deficit, total_hour)
			conditions.settle_essentials_need(person_id, essentials_deficit, total_hour)
		if food_deficit:
			notifications.add(
				"personal", "notification", "食品不足",
				"%s 当天食品库存不足" % household_id,
				total_hour, "food_deficit:%s" % household_id, [household_id]
			)
		if essentials_deficit:
			notifications.add(
				"personal", "notification", "生活用品不足",
				"%s 当天生活用品库存不足" % household_id,
				total_hour, "essentials_deficit:%s" % household_id, [household_id]
			)
		results.append(V2LifeLoopResult.ok(
			"已结算当日住户消费",
			{
				"idempotency_key": key,
				"food_deficit": food_deficit,
				"essentials_deficit": essentials_deficit,
			},
			[household_id]
		))
	return results


func settle_due_rent(
	total_hour: int,
	ledger: V2LedgerService,
	conditions: V2ConditionService,
	notifications: V2NotificationService
) -> Array[V2LifeLoopResult]:
	var results: Array[V2LifeLoopResult] = []
	for household_id_variant: Variant in households.keys():
		var household_id: String = str(household_id_variant)
		var household: Dictionary = households[household_id] as Dictionary
		var due_hour: int = int(household.get("next_rent_due_hour", -1))
		if due_hour != total_hour:
			continue
		var key: String = "%s:rent:%s" % [
			household_id, V2DateTime.iso_from_total_hour(due_hour),
		]
		if processed_idempotency_keys.has(key):
			results.append(V2LifeLoopResult.fail(
				"duplicate_rent", "该期房租已经结算", key, [household_id]
			))
			continue
		var amount: int = int(household.get("rent_amount_centimes", 0))
		var members: Array = household.get("member_ids", []) as Array
		var person_id: String = str(members[0]) if not members.is_empty() else ""
		if int(household.get("cash_centimes", 0)) >= amount:
			var posted: V2LifeLoopResult = ledger.post(
				households, household_id, person_id, amount, "expense", "rent",
				total_hour, household_id, key, key, "房租支付"
			)
			if not posted.success:
				results.append(posted)
				continue
			notifications.add(
				"personal", "event", "房租已支付",
				"已支付 %d 生丁" % amount, total_hour,
				"rent_paid:%s" % household_id, [household_id, person_id]
			)
			results.append(posted)
		else:
			household = households[household_id] as Dictionary
			household["rent_arrears_centimes"] = (
				int(household.get("rent_arrears_centimes", 0)) + amount
			)
			household["current_financial_status"] = "arrears"
			households[household_id] = household
			if not person_id.is_empty():
				conditions.apply_rent_arrears(person_id, total_hour)
			notifications.add(
				"personal", "notification", "房租欠付",
				"现金不足，%d 生丁全部计入欠款" % amount, total_hour,
				"rent_arrears:%s" % household_id, [household_id, person_id]
			)
			results.append(V2LifeLoopResult.ok(
				"现金不足，房租已全部计入欠款",
				{"arrears_added_centimes": amount, "idempotency_key": key},
				[household_id, person_id]
			))
		_remember_processed_key(key)
		household = households[household_id] as Dictionary
		if str(household.get("rent_period", "")) == "days:7":
			household["next_rent_due_hour"] = due_hour + 168
		else:
			household["next_rent_due_hour"] = V2DateTime.next_month_hour(due_hour, 1, 18)
		household["next_rent_due_datetime"] = V2DateTime.iso_from_total_hour(
			int(household["next_rent_due_hour"])
		)
		households[household_id] = household
	return results


func purchase(
	person_id: String,
	item_type: String,
	total_hour: int,
	activity_id: String,
	ledger: V2LedgerService,
	notifications: V2NotificationService
) -> V2LifeLoopResult:
	if item_type not in ["food", "essentials"]:
		return V2LifeLoopResult.fail("invalid_purchase", "未知购买类型", item_type, [person_id])
	var household_id: String = household_id_for_person(person_id)
	var key: String = "activity:%s:purchase" % activity_id
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.fail(
			"duplicate_purchase", "该购买活动已经结算", key, [person_id, household_id]
		)
	var package_key: String = "%s_package" % item_type
	var package: Dictionary = living_costs.get(package_key, {}) as Dictionary
	var price: int = int(package.get("price_centimes", 0))
	var posted: V2LifeLoopResult = ledger.post(
		households, household_id, person_id, price, "expense",
		"food_purchase" if item_type == "food" else "essentials_purchase",
		total_hour, str(living_costs.get("purchase_location_id", "")),
		activity_id, key, "购买食品" if item_type == "food" else "购买生活用品"
	)
	if not posted.success:
		notifications.add(
			"personal", "notification", "购买失败",
			posted.user_message, total_hour, "purchase_failed:%s" % person_id,
			[person_id, household_id]
		)
		return posted
	var household: Dictionary = households[household_id] as Dictionary
	var stock_field: String = "%s_stock_person_days" % item_type
	household[stock_field] = (
		int(household.get(stock_field, 0))
		+ int(package.get("stock_person_days", 0))
	)
	households[household_id] = household
	_remember_processed_key(key)
	notifications.add(
		"personal", "event", "购买成功",
		"%s增加 %d 人日" % [
			"食品" if item_type == "food" else "生活用品",
			int(package.get("stock_person_days", 0)),
		],
		total_hour, "purchase_success:%s" % person_id, [person_id, household_id]
	)
	posted.data["stock_after"] = int(household[stock_field])
	return posted


func get_persistent_state() -> Dictionary:
	return {
		"households": households.duplicate(true),
		"person_to_household": person_to_household.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("households", {}) is Dictionary
		or not state.get("person_to_household", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
	):
		return false
	var restored_households: Dictionary = state["households"] as Dictionary
	for raw_household: Variant in restored_households.values():
		if not raw_household is Dictionary:
			return false
		var household: Dictionary = raw_household as Dictionary
		for field: String in [
			"cash_centimes", "food_stock_person_days", "essentials_stock_person_days",
			"rent_arrears_centimes",
		]:
			if int(household.get(field, -1)) < 0:
				return false
	households = restored_households.duplicate(true)
	person_to_household = (state["person_to_household"] as Dictionary).duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_key_order.clear()
	var raw_order: Variant = state.get("processed_key_order", [])
	if not raw_order is Array:
		return false
	for raw_key: Variant in raw_order as Array:
		var key: String = str(raw_key)
		if not processed_idempotency_keys.has(key):
			return false
		_processed_key_order.append(key)
	if _processed_key_order.size() != processed_idempotency_keys.size():
		return false
	while _processed_key_order.size() > MAX_PROCESSED_KEYS:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())
	return true


func _remember_processed_key(key: String) -> void:
	processed_idempotency_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > MAX_PROCESSED_KEYS:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())
