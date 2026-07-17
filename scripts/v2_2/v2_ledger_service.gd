class_name V2LedgerService
extends RefCounted
## The only V2.2 service allowed to mutate household cash.

var transactions: Array[Dictionary] = []
var opening_cash: Dictionary = {}
var _processed_keys: Dictionary = {}
var _next_sequence: int = 1
var _maximum_per_household: int = 256


func configure(maximum_per_household: int) -> void:
	_maximum_per_household = maxi(32, maximum_per_household)


func register_household(household_id: String, cash_centimes: int) -> void:
	if not opening_cash.has(household_id):
		opening_cash[household_id] = cash_centimes


func post(
	households: Dictionary,
	household_id: String,
	person_id: String,
	amount_centimes: int,
	direction: String,
	category: String,
	total_hour: int,
	source_entity_id: String,
	source_event_id: String,
	idempotency_key: String,
	description: String
) -> V2LifeLoopResult:
	if amount_centimes < 0 or direction not in ["income", "expense"]:
		return V2LifeLoopResult.fail(
			"invalid_transaction", "交易金额或方向无效", "amount/direction rejected",
			[household_id]
		)
	if _processed_keys.has(idempotency_key):
		return V2LifeLoopResult.fail(
			"duplicate_transaction", "该笔交易已经处理", idempotency_key, [household_id]
		)
	if not households.has(household_id):
		return V2LifeLoopResult.fail(
			"unknown_household", "找不到对应住户", household_id, [household_id]
		)
	var household: Dictionary = households[household_id] as Dictionary
	var before: int = int(household.get("cash_centimes", 0))
	if direction == "expense" and before < amount_centimes:
		return V2LifeLoopResult.fail(
			"insufficient_cash",
			"现金不足，还缺 %d 生丁" % (amount_centimes - before),
			"expense rejected before state mutation",
			[household_id, person_id]
		)
	var after: int = before + amount_centimes if direction == "income" else before - amount_centimes
	var transaction: Dictionary = {
		"transaction_id": "transaction:v2_2:%d" % _next_sequence,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"total_hour": total_hour,
		"household_id": household_id,
		"person_id": person_id,
		"amount_centimes": amount_centimes,
		"direction": direction,
		"category": category,
		"source_entity_id": source_entity_id,
		"source_event_id": source_event_id,
		"idempotency_key": idempotency_key,
		"description": description,
		"balance_before_centimes": before,
		"balance_after_centimes": after,
	}
	_next_sequence += 1
	household["cash_centimes"] = after
	if direction == "income":
		household["income_current_period_centimes"] = (
			int(household.get("income_current_period_centimes", 0)) + amount_centimes
		)
	else:
		household["expense_current_period_centimes"] = (
			int(household.get("expense_current_period_centimes", 0)) + amount_centimes
		)
	var recent_ids: Array = household.get("recent_transaction_ids", []) as Array
	recent_ids.append(transaction["transaction_id"])
	while recent_ids.size() > 12:
		recent_ids.pop_front()
	household["recent_transaction_ids"] = recent_ids
	households[household_id] = household
	transactions.append(transaction)
	_processed_keys[idempotency_key] = true
	_trim_household_history(household_id)
	return V2LifeLoopResult.ok(description, {"transaction": transaction}, [household_id, person_id])


func recent_for_household(household_id: String, limit: int = 5) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(transactions.size() - 1, -1, -1):
		var transaction: Dictionary = transactions[index]
		if str(transaction.get("household_id", "")) != household_id:
			continue
		result.append(transaction.duplicate(true))
		if result.size() >= limit:
			break
	return result


func validate_balances(households: Dictionary) -> V2LifeLoopResult:
	for household_id_variant: Variant in opening_cash.keys():
		var household_id: String = str(household_id_variant)
		if not households.has(household_id):
			return V2LifeLoopResult.fail("ledger_household_missing", "账本住户不存在", household_id)
		var expected: int = int(opening_cash[household_id])
		var previous: int = expected
		for transaction: Dictionary in transactions:
			if str(transaction.get("household_id", "")) != household_id:
				continue
			if int(transaction.get("balance_before_centimes", -1)) != previous:
				return V2LifeLoopResult.fail(
					"ledger_chain_broken", "账本余额链不一致",
					str(transaction.get("transaction_id", "")), [household_id]
				)
			var amount: int = int(transaction.get("amount_centimes", 0))
			expected += amount if str(transaction.get("direction", "")) == "income" else -amount
			previous = int(transaction.get("balance_after_centimes", -1))
			if previous != expected:
				return V2LifeLoopResult.fail(
					"ledger_transaction_mismatch", "交易前后余额不一致",
					str(transaction.get("transaction_id", "")), [household_id]
				)
		var household: Dictionary = households[household_id] as Dictionary
		if int(household.get("cash_centimes", -1)) != expected:
			return V2LifeLoopResult.fail(
				"ledger_cash_mismatch", "现金与账本不一致",
				"%s expected=%d" % [household_id, expected], [household_id]
			)
	return V2LifeLoopResult.ok("账本与现金一致")


func has_key(idempotency_key: String) -> bool:
	return _processed_keys.has(idempotency_key)


func get_persistent_state() -> Dictionary:
	return {
		"transactions": transactions.duplicate(true),
		"opening_cash": opening_cash.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_sequence": _next_sequence,
		"maximum_per_household": _maximum_per_household,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("transactions", []) is Array
		or not state.get("opening_cash", {}) is Dictionary
		or not state.get("processed_keys", {}) is Dictionary
	):
		return false
	var restored: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	var seen_keys: Dictionary = {}
	for raw_transaction: Variant in state["transactions"] as Array:
		if not raw_transaction is Dictionary:
			return false
		var transaction: Dictionary = raw_transaction as Dictionary
		var transaction_id: String = str(transaction.get("transaction_id", ""))
		var key: String = str(transaction.get("idempotency_key", ""))
		if transaction_id.is_empty() or key.is_empty() or seen_ids.has(transaction_id) or seen_keys.has(key):
			return false
		seen_ids[transaction_id] = true
		seen_keys[key] = true
		restored.append(transaction.duplicate(true))
	var next_sequence: int = int(state.get("next_sequence", 0))
	if next_sequence < 1:
		return false
	transactions = restored
	opening_cash = (state["opening_cash"] as Dictionary).duplicate(true)
	_processed_keys = (state["processed_keys"] as Dictionary).duplicate(true)
	_next_sequence = next_sequence
	_maximum_per_household = maxi(32, int(state.get("maximum_per_household", 256)))
	return true


func _trim_household_history(household_id: String) -> void:
	var count: int = 0
	for transaction: Dictionary in transactions:
		if str(transaction.get("household_id", "")) == household_id:
			count += 1
	while count > _maximum_per_household:
		for index: int in range(transactions.size()):
			if str(transactions[index].get("household_id", "")) == household_id:
				var removed: Dictionary = transactions[index]
				opening_cash[household_id] = int(
					removed.get("balance_after_centimes", opening_cash[household_id])
				)
				_processed_keys.erase(str(removed.get("idempotency_key", "")))
				transactions.remove_at(index)
				count -= 1
				break
