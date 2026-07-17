class_name V2LedgerService
extends RefCounted
## The only V2.2 service allowed to mutate household cash.

const MAX_PROCESSED_KEYS: int = 4096

var transactions: Array[Dictionary] = []
var opening_cash: Dictionary = {}
var _processed_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _next_sequence: int = 1
var _maximum_per_household: int = 256


func configure(maximum_per_household: int) -> void:
	transactions.clear()
	opening_cash.clear()
	_processed_keys.clear()
	_processed_key_order.clear()
	_next_sequence = 1
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
	var validation: V2LifeLoopResult = _validate_entry(
		households,
		{
			"household_id": household_id,
			"person_id": person_id,
			"amount_centimes": amount_centimes,
			"direction": direction,
			"category": category,
			"total_hour": total_hour,
			"source_entity_id": source_entity_id,
			"source_event_id": source_event_id,
			"idempotency_key": idempotency_key,
			"description": description,
		}
	)
	if not validation.success:
		return validation
	return _commit_entry(
		households, household_id, person_id, amount_centimes, direction, category,
		total_hour, source_entity_id, source_event_id, idempotency_key, description
	)


func post_batch(
	households: Dictionary,
	entries: Array[Dictionary],
	batch_message: String = "复合交易完成"
) -> V2LifeLoopResult:
	if entries.is_empty():
		return V2LifeLoopResult.fail("empty_transaction_batch", "复合交易不能为空")
	var batch_keys: Dictionary = {}
	var net_by_household: Dictionary = {}
	for entry: Dictionary in entries:
		var validation: V2LifeLoopResult = _validate_entry(households, entry)
		if not validation.success:
			return validation
		var key: String = str(entry.get("idempotency_key", ""))
		if batch_keys.has(key):
			return V2LifeLoopResult.fail(
				"duplicate_transaction", "复合交易包含重复幂等键", key
			)
		batch_keys[key] = true
		var household_id: String = str(entry.get("household_id", ""))
		var signed_amount: int = int(entry.get("amount_centimes", 0))
		if str(entry.get("direction", "")) == "expense":
			signed_amount = -signed_amount
		net_by_household[household_id] = int(net_by_household.get(household_id, 0)) + signed_amount
	for household_id_variant: Variant in net_by_household.keys():
		var household_id: String = str(household_id_variant)
		var household: Dictionary = households[household_id] as Dictionary
		var final_cash: int = int(household.get("cash_centimes", 0)) + int(net_by_household[household_id])
		if final_cash < 0:
			return V2LifeLoopResult.fail(
				"insufficient_cash", "现金不足，复合交易未执行",
				"household=%s final=%d" % [household_id, final_cash], [household_id]
			)
	var committed: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var result: V2LifeLoopResult = _commit_entry(
			households,
			str(entry.get("household_id", "")),
			str(entry.get("person_id", "")),
			int(entry.get("amount_centimes", 0)),
			str(entry.get("direction", "")),
			str(entry.get("category", "")),
			int(entry.get("total_hour", 0)),
			str(entry.get("source_entity_id", "")),
			str(entry.get("source_event_id", "")),
			str(entry.get("idempotency_key", "")),
			str(entry.get("description", ""))
		)
		if not result.success:
			# All mutable failure conditions were checked before the first commit.
			push_error("V2.2 原子复合交易在预检后失败：%s" % result.user_message)
			return result
		committed.append((result.data.get("transaction", {}) as Dictionary).duplicate(true))
	return V2LifeLoopResult.ok(
		batch_message, {"transactions": committed}, _batch_entity_ids(entries)
	)


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
		"processed_key_order": _processed_key_order.duplicate(),
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
	var transaction_keys: Dictionary = {}
	for raw_transaction: Variant in state["transactions"] as Array:
		if not raw_transaction is Dictionary:
			return false
		var transaction: Dictionary = raw_transaction as Dictionary
		var transaction_id: String = str(transaction.get("transaction_id", ""))
		var key: String = str(transaction.get("idempotency_key", ""))
		if (
			transaction_id.is_empty()
			or key.is_empty()
			or seen_ids.has(transaction_id)
			or transaction_keys.has(key)
			or int(transaction.get("amount_centimes", -1)) < 0
			or str(transaction.get("direction", "")) not in ["income", "expense"]
		):
			return false
		seen_ids[transaction_id] = true
		transaction_keys[key] = true
		restored.append(transaction.duplicate(true))
	var next_sequence: int = int(state.get("next_sequence", 0))
	if next_sequence < 1:
		return false
	var processed: Dictionary = (state["processed_keys"] as Dictionary).duplicate(true)
	for key_variant: Variant in transaction_keys.keys():
		if not processed.has(str(key_variant)):
			return false
	var restored_order: Array[String] = []
	var raw_order: Variant = state.get("processed_key_order", processed.keys())
	if not raw_order is Array:
		return false
	for raw_key: Variant in raw_order as Array:
		var key: String = str(raw_key)
		if key.is_empty() or not processed.has(key) or key in restored_order:
			return false
		restored_order.append(key)
	for key_variant: Variant in processed.keys():
		var key: String = str(key_variant)
		if key not in restored_order:
			restored_order.append(key)
	transactions = restored
	opening_cash = (state["opening_cash"] as Dictionary).duplicate(true)
	_processed_keys = processed
	_processed_key_order = restored_order
	_next_sequence = next_sequence
	_maximum_per_household = maxi(32, int(state.get("maximum_per_household", 256)))
	while _processed_key_order.size() > MAX_PROCESSED_KEYS:
		_processed_keys.erase(_processed_key_order.pop_front())
	return true


func _validate_entry(households: Dictionary, entry: Dictionary) -> V2LifeLoopResult:
	var household_id: String = str(entry.get("household_id", ""))
	var person_id: String = str(entry.get("person_id", ""))
	var amount_centimes: int = int(entry.get("amount_centimes", -1))
	var direction: String = str(entry.get("direction", ""))
	var idempotency_key: String = str(entry.get("idempotency_key", ""))
	if amount_centimes < 0 or direction not in ["income", "expense"]:
		return V2LifeLoopResult.fail(
			"invalid_transaction", "交易金额或方向无效", "amount/direction rejected",
			[household_id]
		)
	if idempotency_key.is_empty():
		return V2LifeLoopResult.fail("invalid_transaction", "交易幂等键不能为空")
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
	return V2LifeLoopResult.ok()


func _commit_entry(
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
	var household: Dictionary = households[household_id] as Dictionary
	var before: int = int(household.get("cash_centimes", 0))
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
	_remember_processed_key(idempotency_key)
	_trim_household_history(household_id)
	return V2LifeLoopResult.ok(description, {"transaction": transaction}, [household_id, person_id])


func _remember_processed_key(key: String) -> void:
	_processed_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > MAX_PROCESSED_KEYS:
		_processed_keys.erase(_processed_key_order.pop_front())


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
				transactions.remove_at(index)
				count -= 1
				break


static func _batch_entity_ids(entries: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in entries:
		for field: String in ["household_id", "person_id", "source_entity_id"]:
			var value: String = str(entry.get(field, ""))
			if not value.is_empty() and value not in result:
				result.append(value)
	return result
