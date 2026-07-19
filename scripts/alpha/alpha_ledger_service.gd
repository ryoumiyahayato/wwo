class_name AlphaLedgerService
extends RefCounted
## Double-entry ledger and the only Alpha service allowed to mutate cash balances.

const SYSTEM_OPENING_ACCOUNT: String = "account:system:opening"
const DEFAULT_HISTORY_LIMIT: int = 8192
const PROCESSED_KEY_MULTIPLIER: int = 8

var accounts: Dictionary = {}
var transactions: Array[Dictionary] = []
var opening_balances: Dictionary = {}
var _transactions_by_key: Dictionary = {}
var _processed_key_order: Array[String] = []
var _next_sequence: int = 1
var _history_limit: int = DEFAULT_HISTORY_LIMIT


func configure(history_limit: int = DEFAULT_HISTORY_LIMIT) -> void:
	accounts.clear()
	transactions.clear()
	opening_balances.clear()
	_transactions_by_key.clear()
	_processed_key_order.clear()
	_next_sequence = 1
	_history_limit = maxi(256, history_limit)
	_register_account(SYSTEM_OPENING_ACCOUNT, "system:opening", "system", true)


func register_cash_account(
	owner_id: String,
	owner_type: String,
	opening_cash_centimes: int,
	account_id: String = ""
) -> Dictionary:
	if owner_id.is_empty() or opening_cash_centimes < 0:
		return _fail("invalid_account", "账户所有者或期初现金无效")
	var resolved_id: String = account_id
	if resolved_id.is_empty():
		resolved_id = "account:cash:%s" % owner_id
	if accounts.has(resolved_id):
		var existing: Dictionary = accounts[resolved_id] as Dictionary
		if str(existing.get("owner_id", "")) != owner_id:
			return _fail("account_conflict", "账户 ID 已被其他对象占用")
		return _ok({"account": existing.duplicate(true), "existing": true})
	_register_account(resolved_id, owner_id, owner_type, false)
	if opening_cash_centimes > 0:
		var posted: Dictionary = post(
			"ledger:opening:%s" % resolved_id,
			0,
			"opening_balance",
			"fact:opening:%s" % owner_id,
			[
				{"account_id": SYSTEM_OPENING_ACCOUNT, "delta_centimes": -opening_cash_centimes},
				{"account_id": resolved_id, "delta_centimes": opening_cash_centimes},
			],
			"期初现金"
		)
		if not bool(posted.get("success", false)):
			accounts.erase(resolved_id)
			opening_balances.erase(resolved_id)
			return posted
	return _ok({"account": (accounts[resolved_id] as Dictionary).duplicate(true)})


func cash_account_id(owner_id: String) -> String:
	var expected: String = "account:cash:%s" % owner_id
	if accounts.has(expected):
		return expected
	for raw_account: Variant in accounts.values():
		var account: Dictionary = raw_account as Dictionary
		if (
			str(account.get("owner_id", "")) == owner_id
			and str(account.get("kind", "")) == "cash"
		):
			return str(account.get("account_id", ""))
	return ""


func balance(account_id: String) -> int:
	var account: Dictionary = accounts.get(account_id, {}) as Dictionary
	return int(account.get("balance_centimes", 0))


func owner_cash(owner_id: String) -> int:
	return balance(cash_account_id(owner_id))


func transfer(
	idempotency_key: String,
	total_hour: int,
	from_owner_id: String,
	to_owner_id: String,
	amount_centimes: int,
	category: String,
	fact_id: String,
	description: String
) -> Dictionary:
	if amount_centimes < 0:
		return _fail("invalid_amount", "转账金额不能为负")
	var from_account: String = cash_account_id(from_owner_id)
	var to_account: String = cash_account_id(to_owner_id)
	if from_account.is_empty() or to_account.is_empty():
		return _fail("account_missing", "转账双方必须具有正式现金账户")
	return post(
		idempotency_key,
		total_hour,
		category,
		fact_id,
		[
			{"account_id": from_account, "delta_centimes": -amount_centimes},
			{"account_id": to_account, "delta_centimes": amount_centimes},
		],
		description
	)


func post(
	idempotency_key: String,
	total_hour: int,
	category: String,
	fact_id: String,
	entries: Array,
	description: String
) -> Dictionary:
	if idempotency_key.is_empty() or fact_id.is_empty():
		return _fail("invalid_transaction", "账本分录必须具有幂等键和事实引用")
	if _transactions_by_key.has(idempotency_key):
		var existing_index: int = int(_transactions_by_key[idempotency_key])
		if existing_index >= 0 and existing_index < transactions.size():
			return _ok({
				"duplicate": true,
				"transaction": transactions[existing_index].duplicate(true),
			})
		return _fail("duplicate_pruned_transaction", "该交易已经结算且历史摘要仍保留")
	if entries.size() < 2:
		return _fail("invalid_transaction", "双边账本至少需要两条分录")
	var normalized: Array[Dictionary] = []
	var projected: Dictionary = {}
	var total_delta: int = 0
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			return _fail("invalid_transaction", "账本分录格式无效")
		var entry: Dictionary = raw_entry as Dictionary
		var account_id: String = str(entry.get("account_id", ""))
		var delta: int = int(entry.get("delta_centimes", 0))
		if account_id.is_empty() or not accounts.has(account_id) or delta == 0:
			return _fail("invalid_transaction", "账本分录引用未知账户或零金额")
		if not projected.has(account_id):
			projected[account_id] = balance(account_id)
		projected[account_id] = int(projected[account_id]) + delta
		var account: Dictionary = accounts[account_id] as Dictionary
		if (
			not bool(account.get("allow_negative", false))
			and int(projected[account_id]) < 0
		):
			return _fail(
				"insufficient_cash",
				"%s 现金不足" % str(account.get("owner_id", account_id))
			)
		total_delta += delta
		normalized.append({
			"account_id": account_id,
			"delta_centimes": delta,
		})
	if total_delta != 0:
		return _fail("unbalanced_transaction", "双边账本借贷不平衡")
	var transaction: Dictionary = {
		"transaction_id": "transaction:alpha:%d" % _next_sequence,
		"idempotency_key": idempotency_key,
		"total_hour": total_hour,
		"category": category,
		"fact_id": fact_id,
		"description": description,
		"entries": normalized,
	}
	_next_sequence += 1
	for entry: Dictionary in normalized:
		var account_id: String = str(entry["account_id"])
		var account: Dictionary = accounts[account_id] as Dictionary
		account["balance_centimes"] = (
			int(account.get("balance_centimes", 0))
			+ int(entry["delta_centimes"])
		)
		accounts[account_id] = account
	transactions.append(transaction)
	_transactions_by_key[idempotency_key] = transactions.size() - 1
	_processed_key_order.append(idempotency_key)
	_trim_history()
	_trim_processed_keys()
	return _ok({"transaction": transaction.duplicate(true), "duplicate": false})


func validate_balances() -> Dictionary:
	var projected: Dictionary = opening_balances.duplicate(true)
	var seen_ids: Dictionary = {}
	var seen_keys: Dictionary = {}
	for transaction: Dictionary in transactions:
		var transaction_id: String = str(transaction.get("transaction_id", ""))
		var key: String = str(transaction.get("idempotency_key", ""))
		if (
			transaction_id.is_empty()
			or key.is_empty()
			or seen_ids.has(transaction_id)
			or seen_keys.has(key)
		):
			return _fail("ledger_identity_error", "账本存在缺失或重复交易标识")
		seen_ids[transaction_id] = true
		seen_keys[key] = true
		var transaction_total: int = 0
		for raw_entry: Variant in transaction.get("entries", []) as Array:
			if not raw_entry is Dictionary:
				return _fail("ledger_entry_error", "账本包含无效分录")
			var entry: Dictionary = raw_entry as Dictionary
			var account_id: String = str(entry.get("account_id", ""))
			var delta: int = int(entry.get("delta_centimes", 0))
			if not accounts.has(account_id) or not projected.has(account_id):
				return _fail("ledger_reference_error", "账本分录引用未知账户")
			projected[account_id] = int(projected[account_id]) + delta
			transaction_total += delta
		if transaction_total != 0:
			return _fail("ledger_unbalanced", "历史交易借贷不平衡")
	for raw_account_id: Variant in accounts:
		var account_id: String = str(raw_account_id)
		var account: Dictionary = accounts[account_id] as Dictionary
		if int(projected.get(account_id, 0)) != int(account.get("balance_centimes", 0)):
			return _fail("ledger_balance_mismatch", "现金余额与账本轨迹不一致")
		if (
			not bool(account.get("allow_negative", false))
			and int(account.get("balance_centimes", 0)) < 0
		):
			return _fail("negative_cash", "正式现金账户出现负余额")
	return _ok({
		"account_count": accounts.size(),
		"transaction_count": transactions.size(),
	})


func get_persistent_state() -> Dictionary:
	return {
		"accounts": accounts.duplicate(true),
		"transactions": transactions.duplicate(true),
		"opening_balances": opening_balances.duplicate(true),
		"processed_keys": _transactions_by_key.keys(),
		"processed_key_order": _processed_key_order.duplicate(),
		"next_sequence": _next_sequence,
		"history_limit": _history_limit,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("accounts", {}) is Dictionary
		or not state.get("transactions", []) is Array
		or not state.get("opening_balances", {}) is Dictionary
		or not state.get("processed_keys", []) is Array
	):
		return false
	var restored_accounts: Dictionary = (state["accounts"] as Dictionary).duplicate(true)
	var restored_opening: Dictionary = (state["opening_balances"] as Dictionary).duplicate(true)
	if not restored_accounts.has(SYSTEM_OPENING_ACCOUNT):
		return false
	for raw_account_id: Variant in restored_accounts:
		var account_id: String = str(raw_account_id)
		if not restored_accounts[account_id] is Dictionary or not restored_opening.has(account_id):
			return false
	var restored_transactions: Array[Dictionary] = []
	var index: Dictionary = {}
	var restored_order: Array[String] = []
	for raw_transaction: Variant in state["transactions"] as Array:
		if not raw_transaction is Dictionary:
			return false
		var transaction: Dictionary = (raw_transaction as Dictionary).duplicate(true)
		var key: String = str(transaction.get("idempotency_key", ""))
		if key.is_empty() or index.has(key):
			return false
		index[key] = restored_transactions.size()
		restored_transactions.append(transaction)
		restored_order.append(key)
	for raw_key: Variant in state["processed_keys"] as Array:
		var key: String = str(raw_key)
		if key.is_empty():
			return false
		if not index.has(key):
			index[key] = -1
			restored_order.append(key)
	if state.get("processed_key_order", []) is Array:
		restored_order.clear()
		for raw_key: Variant in state.get("processed_key_order", []) as Array:
			var key: String = str(raw_key)
			if key.is_empty() or not index.has(key) or key in restored_order:
				return false
			restored_order.append(key)
		for raw_key: Variant in index:
			var key: String = str(raw_key)
			if key not in restored_order:
				restored_order.append(key)
	accounts = restored_accounts
	transactions = restored_transactions
	opening_balances = restored_opening
	_transactions_by_key = index
	_processed_key_order = restored_order
	_next_sequence = int(state.get("next_sequence", 0))
	_history_limit = maxi(256, int(state.get("history_limit", DEFAULT_HISTORY_LIMIT)))
	if _next_sequence < 1 or not bool(validate_balances().get("success", false)):
		return false
	_trim_processed_keys()
	return true


func _register_account(
	account_id: String, owner_id: String, owner_type: String, allow_negative: bool
) -> void:
	accounts[account_id] = {
		"account_id": account_id,
		"owner_id": owner_id,
		"owner_type": owner_type,
		"kind": "cash",
		"currency": "crown_centime",
		"balance_centimes": 0,
		"allow_negative": allow_negative,
		"status": "active",
	}
	opening_balances[account_id] = 0


func _trim_history() -> void:
	while transactions.size() > _history_limit:
		var removed: Dictionary = transactions.pop_front()
		for entry: Dictionary in removed.get("entries", []) as Array[Dictionary]:
			var account_id: String = str(entry.get("account_id", ""))
			opening_balances[account_id] = (
				int(opening_balances.get(account_id, 0))
				+ int(entry.get("delta_centimes", 0))
			)
		_transactions_by_key[str(removed.get("idempotency_key", ""))] = -1
	for index: int in range(transactions.size()):
		_transactions_by_key[str(transactions[index].get("idempotency_key", ""))] = index


func _trim_processed_keys() -> void:
	var processed_limit: int = _history_limit * PROCESSED_KEY_MULTIPLIER
	while _processed_key_order.size() > processed_limit:
		var oldest_key: String = _processed_key_order.pop_front()
		if int(_transactions_by_key.get(oldest_key, -1)) < 0:
			_transactions_by_key.erase(oldest_key)


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
