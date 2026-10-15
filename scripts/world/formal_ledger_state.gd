class_name FormalLedgerState
extends RefCounted
## The sole personal-money balance owner. Transfers validate both sides before
## mutation; receipts are also the idempotency record. No aggregate money stock.

const SCHEMA_ID: String = "formal_ledger_state_v1"
const DENOMINATION: String = "denomination:formal_simulation_minor_v1"
const SOURCE_ACCOUNT: String = "account:scenario_livelihood_r1"
const SOURCE_OWNER: String = "scenario:livelihood_r1"
const MAX_AMOUNT: int = 9007199254740991
const ACCOUNT_FIELDS: Array[String] = ["account_id", "owner_id", "role", "denomination", "balance"]
const TRANSACTION_FIELDS: Array[String] = ["transaction_id", "from_account_id", "to_account_id", "amount", "denomination", "effective_minute", "kind", "reference_id", "basis"]

var error: String = ""
var _scenario_budget: int = -1
var _accounts: Dictionary = {}
var _transactions: Array[Dictionary] = []
var _transactions_by_id: Dictionary = {}
var _transactions_by_account: Dictionary = {}
var _transactions_by_owner: Dictionary = {}
var _accounts_by_owner: Dictionary = {}
var _r1_enabled: bool = false
var _reservations: Dictionary = {}
var _reserved_by_account: Dictionary = {}
var _currency_budgets: Dictionary = {}
var _batches: Dictionary = {}


func enable_economy_r1() -> bool:
	if _r1_enabled:
		return true
	_r1_enabled = true
	return true


func available_balance(account_id: String) -> int:
	return int(balance(account_id)) - int(_reserved_by_account.get(account_id, 0)) if _accounts.has(account_id) else -1


func reserved_balance(account_id: String) -> int:
	return int(_reserved_by_account.get(account_id, 0))


func reserve(reservation_id: String, account_id: String, amount: int) -> bool:
	if not _r1_enabled or reservation_id.is_empty() or not valid_amount(amount) or amount <= 0 or not _accounts.has(account_id):
		return _fail("Invalid R1 reservation")
	if _reservations.has(reservation_id):
		return _reservations[reservation_id] == {"account_id": account_id, "amount": amount}
	if amount > available_balance(account_id):
		return _fail("Insufficient available funds")
	_reservations[reservation_id] = {"account_id": account_id, "amount": amount}
	_reserved_by_account[account_id] = reserved_balance(account_id) + amount
	return true


func release(reservation_id: String, amount: int) -> bool:
	if not _reservations.has(reservation_id) or amount <= 0 or amount > int(_reservations[reservation_id]["amount"]):
		return _fail("Invalid reservation release")
	var account_id := str(_reservations[reservation_id]["account_id"])
	_reservations[reservation_id]["amount"] = int(_reservations[reservation_id]["amount"]) - amount
	_reserved_by_account[account_id] = reserved_balance(account_id) - amount
	if int(_reservations[reservation_id]["amount"]) == 0:
		_reservations.erase(reservation_id)
	return true


func pay_reserved(reservation_id: String, transaction_id: String, destination_id: String, amount: int, minute: int, reference_id: String) -> bool:
	if _transactions_by_id.has(transaction_id):
		return _fail("Reserved payment already settled")
	if not _reservations.has(reservation_id) or not valid_amount(amount) or amount <= 0 or amount > int(_reservations[reservation_id]["amount"]) or not _accounts.has(destination_id):
		return _fail("Invalid reserved payment")
	var source_id := str(_reservations[reservation_id]["account_id"])
	if source_id == destination_id or int(balance(destination_id)) > MAX_AMOUNT - amount:
		return _fail("Invalid reserved payment parties or bounds")
	var previous := (_reservations[reservation_id] as Dictionary).duplicate()
	if not release(reservation_id, amount):
		return false
	if not transfer(transaction_id, source_id, destination_id, amount, minute, "goods", reference_id):
		_reservations[reservation_id] = previous
		_reserved_by_account[source_id] = reserved_balance(source_id) + amount
		return false
	return true


func configure(scenario_budget: int) -> bool:
	if _scenario_budget >= 0 or not valid_amount(scenario_budget):
		return _fail("Invalid or repeated scenario endowment")
	_scenario_budget = scenario_budget
	# Only the finite scenario source receives a genesis endowment. Personal and
	# payer accounts start at zero and are funded by recorded normal transfers.
	_accounts[SOURCE_ACCOUNT] = {"account_id": SOURCE_ACCOUNT, "owner_id": SOURCE_OWNER, "role": "opening_source", "denomination": DENOMINATION, "balance": scenario_budget}
	_index_account(SOURCE_ACCOUNT)
	return true


func open_account(account_id: String, owner_id: String, role: String, denomination: String = DENOMINATION) -> bool:
	if _scenario_budget < 0 or not account_id.begins_with("account:") or account_id.length() <= 8 or owner_id.is_empty() or _accounts.has(account_id):
		return _fail("Invalid or duplicate account")
	if role not in ["personal_cash", "background_payer", "market_receipts"] and (not _r1_enabled or role not in ["r1_firm", "r1_cohort", "r1_carrier"]):
		return _fail("Unsupported account role")
	if not has_currency(denomination) or (denomination != DENOMINATION and not _r1_enabled):
		return _fail("Unknown account currency")
	if not owner_account(owner_id, denomination).is_empty():
		return _fail("Owner already has an account in this currency")
	_accounts[account_id] = {"account_id": account_id, "owner_id": owner_id, "role": role, "denomination": denomination, "balance": 0}
	_index_account(account_id)
	error = ""
	return true


static func currency_id(value: Variant) -> bool:
	return value is String and str(value).begins_with("denomination:") and str(value).length() > 13


static func currency_source(denomination: String) -> String:
	return SOURCE_ACCOUNT if denomination == DENOMINATION else "account:scenario_currency:" + denomination


func has_currency(denomination: String) -> bool:
	return denomination == DENOMINATION or _currency_budgets.has(denomination)


func configure_currency(denomination: String, budget: int) -> bool:
	# Only finite configured genesis sources exist. Loading reconstructs these
	# sources before recorded payments; it never endows a participant again.
	if not _r1_enabled or _scenario_budget < 0 or (_transactions.size() > 0 and int(_transactions.back()["effective_minute"]) != 0) or not currency_id(denomination) or has_currency(denomination) or not valid_amount(budget):
		return _fail("Invalid currency endowment")
	_currency_budgets[denomination] = budget
	var id := currency_source(denomination)
	_accounts[id] = {"account_id": id, "owner_id": SOURCE_OWNER, "role": "opening_source", "denomination": denomination, "balance": budget}
	_index_account(id)
	return true


func _index_account(id: String) -> void:
	var row := _accounts[id] as Dictionary
	if not _accounts_by_owner.has(row["owner_id"]): _accounts_by_owner[row["owner_id"]] = {}
	_accounts_by_owner[row["owner_id"]][row["denomination"]] = id

func owner_account(owner: String, denomination: String = DENOMINATION) -> String:
	return str(_accounts_by_owner.get(owner, {}).get(denomination, ""))

func own_accounts(owner: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _accounts_by_owner.get(owner, {}).values()
	ids.sort()
	for id: String in ids: result.append((_accounts[id] as Dictionary).duplicate(true))
	return result


func account(account_id: String) -> Dictionary:
	return (_accounts.get(account_id, {}) as Dictionary).duplicate(true)


func balance(account_id: String) -> Variant:
	return (_accounts[account_id] as Dictionary)["balance"] if _accounts.has(account_id) else null


func account_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_accounts.keys())
	ids.sort()
	return ids


func transaction(transaction_id: String) -> Dictionary:
	return (_transactions_by_id.get(transaction_id, {}) as Dictionary).duplicate(true)


func transactions() -> Array[Dictionary]:
	return _transactions.duplicate(true)

func transactions_for_account(account_id: String, limit: int = 7, offset: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _accounts.has(account_id) or limit <= 0:
		return result
	var receipts := _transactions_by_account.get(account_id,[]) as Array
	for index: int in range(receipts.size()-1-maxi(0,offset),maxi(-1,receipts.size()-1-maxi(0,offset)-limit),-1):
		result.append((receipts[index] as Dictionary).duplicate(true))
	return result



## Receipts are chronological by the existing transfer/batch invariant. Binary
## bounds avoid reading old payments for daily finance and rolling cash flows.
static func _receipt_bound(receipts: Array, minute: int) -> int:
	var lo: int = 0
	var hi: int = receipts.size()
	while lo < hi:
		var mid: int = lo + (hi - lo) / 2
		if int(receipts[mid]["effective_minute"]) < minute: lo = mid + 1
		else: hi = mid
	return lo

func own_transactions(owner: String, from_minute: int = -1, before_minute: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var receipts := _transactions_by_owner.get(owner, []) as Array
	var begin := _receipt_bound(receipts, from_minute) if from_minute >= 0 else 0
	var end := _receipt_bound(receipts, before_minute) if before_minute >= 0 else receipts.size()
	for index: int in range(begin, end): result.append((receipts[index] as Dictionary).duplicate(true))
	return result


func transfer(transaction_id: String, source_id: String, destination_id: String, amount: int, effective_minute: int, kind: String, reference_id: String) -> bool:
	if transaction_id.is_empty() or reference_id.is_empty() or not valid_amount(amount) or amount <= 0 or effective_minute < 0 or not _valid_kind(kind):
		return _fail("Invalid transaction")
	var receipt := {"transaction_id": transaction_id, "from_account_id": source_id, "to_account_id": destination_id, "amount": amount, "denomination": account(source_id).get("denomination", ""), "effective_minute": effective_minute, "kind": kind, "reference_id": reference_id, "basis": "GENERATED_SIMULATION_ASSUMPTION"}
	if _transactions_by_id.has(transaction_id):
		if _transactions_by_id[transaction_id] != receipt:
			return _fail("Idempotency key conflicts with an existing transaction")
		error = ""
		return true
	if source_id == destination_id or not _accounts.has(source_id) or not _accounts.has(destination_id):
		return _fail("Transaction accounts are unavailable")
	var source := _accounts[source_id] as Dictionary
	var destination := _accounts[destination_id] as Dictionary
	if source["denomination"] != destination["denomination"] or available_balance(source_id) < amount or int(destination["balance"]) > MAX_AMOUNT - amount:
		return _fail("Insufficient funds or incompatible denomination/numeric bounds")
	if not _transactions.is_empty() and effective_minute < int(_transactions.back()["effective_minute"]):
		return _fail("Transaction time precedes the recorded ledger")
	source["balance"] = int(source["balance"]) - amount
	destination["balance"] = int(destination["balance"]) + amount
	_transactions.append(receipt)
	_transactions_by_id[transaction_id] = receipt
	_index_transaction(receipt)
	error = ""
	return true


func _valid_kind(kind: String) -> bool:
	return kind in ["opening_cash", "employer_reserve", "wage", "purchase"] or (_r1_enabled and kind in ["goods", "freight", "cargo_refund", "cargo_damages", "cargo_extra_freight", "loan_issue", "loan_repayment", "fx_principal", "fx_target", "fx_fee", "asset_trade", "dividend", "person_travel", "service_fee", "lease_rent"])


func _payment_preparation_error(message: String) -> Dictionary:
	_fail(message)
	return {}

func payment_ready(id: String, legs: Array[Dictionary], minute: int, releases: Dictionary = {}) -> bool:
	return not _prepare_batch_payment(id,legs,minute,releases).is_empty()

func _prepare_batch_payment(id: String, legs: Array[Dictionary], minute: int, releases: Dictionary = {}) -> Dictionary:
	# Gross debits are checked against pre-payment free cash plus only the named
	# reservation releases. Incoming legs cannot finance an unfunded outgoing leg.
	if not _r1_enabled or id.is_empty() or _batches.has(id) or not valid_amount(minute) or legs.size() > 512 or (not _transactions.is_empty() and minute < int(_transactions.back()["effective_minute"])):
		return _payment_preparation_error("Invalid or repeated payment batch")
	var freed: Dictionary = {}
	for key: Variant in releases:
		if not key is String or not _reservations.has(key) or not valid_amount(releases[key]) or int(releases[key]) <= 0 or int(releases[key]) > int(_reservations[key]["amount"]):
			return _payment_preparation_error("Invalid batch reservation release")
		var account_id := str(_reservations[key]["account_id"])
		freed[account_id] = int(freed.get(account_id, 0)) + int(releases[key])
	var debit: Dictionary = {}
	var credit: Dictionary = {}
	var receipts: Array[Dictionary] = []
	var ids: Array[String] = []
	for leg: Dictionary in legs:
		if not exact_fields(leg, ["transaction_id", "from_account_id", "to_account_id", "amount", "kind", "reference_id"]) or not valid_amount(leg["amount"]) or int(leg["amount"]) <= 0:
			return _payment_preparation_error("Invalid payment leg")
		for field: String in ["transaction_id", "from_account_id", "to_account_id", "kind", "reference_id"]:
			if not leg[field] is String or str(leg[field]).is_empty():
				return _payment_preparation_error("Invalid payment reference")
		var tx := str(leg["transaction_id"])
		var source := str(leg["from_account_id"])
		var target := str(leg["to_account_id"])
		var amount := int(leg["amount"])
		if ids.has(tx) or _transactions_by_id.has(tx) or not _valid_kind(leg["kind"]) or not _accounts.has(source) or not _accounts.has(target) or source == target or _accounts[source]["denomination"] != _accounts[target]["denomination"]:
			return _payment_preparation_error("Payment leg conflicts with accounts or receipts")
		if int(debit.get(source, 0)) > MAX_AMOUNT - amount or int(credit.get(target, 0)) > MAX_AMOUNT - amount:
			return _payment_preparation_error("Payment aggregate exceeds amount bounds")
		debit[source] = int(debit.get(source, 0)) + amount
		credit[target] = int(credit.get(target, 0)) + amount
		var receipt := leg.duplicate(true)
		receipt.merge({"denomination": _accounts[source]["denomination"], "effective_minute": minute, "basis": "GENERATED_SIMULATION_ASSUMPTION"})
		receipts.append(receipt)
		ids.append(tx)
	var balances: Dictionary = {}
	for account_id: String in _accounts:
		if not debit.has(account_id) and not credit.has(account_id):
			continue
		var paid := int(debit.get(account_id, 0))
		var received := int(credit.get(account_id, 0))
		var after_debit := int(balance(account_id)) - paid
		if paid > available_balance(account_id) + int(freed.get(account_id, 0)) or after_debit > MAX_AMOUNT - received:
			return _payment_preparation_error("Insufficient free cash or payment bounds")
		balances[account_id] = after_debit + received
	return {"balances":balances,"receipts":receipts,"ids":ids}

func batch_payment(id: String, legs: Array[Dictionary], minute: int, releases: Dictionary = {}) -> bool:
	var prepared := _prepare_batch_payment(id,legs,minute,releases)
	if prepared.is_empty(): return false
	var balances := prepared["balances"] as Dictionary
	var receipts: Array[Dictionary] = []
	receipts.assign(prepared["receipts"])
	var ids: Array[String] = []
	ids.assign(prepared["ids"])
	for reservation_id: String in releases:
		release(reservation_id, int(releases[reservation_id]))
	for account_id: String in balances:
		_accounts[account_id]["balance"] = balances[account_id]
	for receipt: Dictionary in receipts:
		_transactions.append(receipt)
		_transactions_by_id[receipt["transaction_id"]] = receipt
		_index_transaction(receipt)
	_batches[id] = {"transactions": ids, "releases": releases.duplicate(true), "minute": minute}
	error = ""
	return true


func payment_batch(id: String) -> Dictionary:
	return (_batches.get(id, {}) as Dictionary).duplicate(true)


## Exact target minor units per source minor unit; no intermediate float or
## overflowing product. Rounding never creates a second fractional balance.
static func ratio(amount: int, numerator: int, denominator: int) -> Dictionary:
	if not valid_amount(amount) or not valid_amount(numerator) or not valid_amount(denominator) or denominator == 0:
		return {}
	var quotient: int = 0
	var remainder: int = 0
	var term_q: int = amount / denominator
	var term_r: int = amount % denominator
	var multiplier: int = numerator
	while multiplier > 0:
		if multiplier % 2 == 1:
			var carry: int = (remainder + term_r) / denominator
			if term_q > MAX_AMOUNT - quotient - carry:
				return {}
			quotient += term_q + carry
			remainder = (remainder + term_r) % denominator
		multiplier = multiplier / 2
		if multiplier > 0:
			var carry: int = (term_r * 2) / denominator
			if term_q > (MAX_AMOUNT - carry) / 2:
				return {}
			term_q = term_q * 2 + carry
			term_r = (term_r * 2) % denominator
	return {"quotient": quotient, "remainder": remainder}


func snapshot() -> Dictionary:
	var accounts: Array[Dictionary] = []
	for account_id: String in account_ids():
		accounts.append(account(account_id))
	var value := {"schema_id": SCHEMA_ID, "denomination": DENOMINATION, "scenario_budget": _scenario_budget, "accounts": accounts, "transactions": transactions()}
	if _r1_enabled:
		value["r1_reservations"] = _reservations.duplicate(true)
		if not _currency_budgets.is_empty():
			value["currency_budgets"] = _currency_budgets.duplicate(true)
		if not _batches.is_empty():
			value["payment_batches"] = _batches.duplicate(true)
	return value


## Reconstruct balances from real payment receipts on a detached owner.
func restore(value: Dictionary) -> bool:
	var fields: Array[String] = ["schema_id", "denomination", "scenario_budget", "accounts", "transactions"]
	if _r1_enabled:
		fields.append("r1_reservations")
		for field: String in ["currency_budgets", "payment_batches"]:
			if value.has(field):
				fields.append(field)
	if not exact_fields(value, fields) or value.get("schema_id") != SCHEMA_ID or value.get("denomination") != DENOMINATION or not valid_amount(value.get("scenario_budget")):
		return _fail("Invalid ledger snapshot header")
	if not value["accounts"] is Array or not value["transactions"] is Array:
		return _fail("Invalid ledger snapshot containers")
	var candidate := FormalLedgerState.new()
	if _r1_enabled:
		candidate.enable_economy_r1()
	if not candidate.configure(int(value["scenario_budget"])):
		return _fail(candidate.error)
	var budgets: Variant = value.get("currency_budgets", {})
	var batches: Variant = value.get("payment_batches", {})
	if not budgets is Dictionary or not batches is Dictionary:
		return _fail("Invalid currency or payment containers")
	for denomination: Variant in budgets:
		if not currency_id(denomination) or not valid_amount(budgets[denomination]) or not candidate.configure_currency(denomination, budgets[denomination]):
			return _fail("Invalid finite currency source")
	var seen: Dictionary = {}
	for raw: Variant in value["accounts"]:
		if not raw is Dictionary:
			return _fail("Invalid ledger account")
		var record := raw as Dictionary
		if not exact_fields(record, ACCOUNT_FIELDS) or not record["account_id"] is String or not record["owner_id"] is String or not record["role"] is String or not currency_id(record["denomination"]) or not candidate.has_currency(record["denomination"]) or not valid_amount(record["balance"]) or seen.has(record["account_id"]):
			return _fail("Invalid or duplicate ledger account")
		seen[record["account_id"]] = true
		if record["account_id"] == currency_source(record["denomination"]):
			if record["owner_id"] != SOURCE_OWNER or record["role"] != "opening_source":
				return _fail("Invalid opening source")
		elif not candidate.open_account(record["account_id"], record["owner_id"], record["role"], record["denomination"]):
			return _fail(candidate.error)
	if not seen.has(SOURCE_ACCOUNT):
		return _fail("Missing finite scenario source")
	for denomination: String in budgets:
		if not seen.has(currency_source(denomination)):
			return _fail("Missing foreign currency source")
	var batch_by_tx: Dictionary = {}
	for id: Variant in batches:
		var batch: Variant = batches[id]
		if not id is String or str(id).is_empty() or not batch is Dictionary or not exact_fields(batch, ["transactions", "releases", "minute"]) or not batch["transactions"] is Array or not batch["releases"] is Dictionary or not valid_amount(batch["minute"]):
			return _fail("Invalid saved payment batch")
		for tx: Variant in batch["transactions"]:
			if not tx is String or batch_by_tx.has(tx):
				return _fail("Duplicate batch payment leg")
			batch_by_tx[tx] = id
		for reservation: Variant in batch["releases"]:
			if not reservation is String or not valid_amount(batch["releases"][reservation]) or int(batch["releases"][reservation]) <= 0:
				return _fail("Invalid payment reservation record")
	seen.clear()
	for raw: Variant in value["transactions"]:
		if not raw is Dictionary:
			return _fail("Invalid ledger transaction")
		var record := raw as Dictionary
		if not exact_fields(record, TRANSACTION_FIELDS) or not valid_amount(record["amount"]) or typeof(record["effective_minute"]) != TYPE_INT or record["denomination"] != candidate.account(str(record["from_account_id"])).get("denomination") or record["basis"] != "GENERATED_SIMULATION_ASSUMPTION":
			return _fail("Invalid ledger transaction fields")
		for field: String in ["transaction_id", "from_account_id", "to_account_id", "kind", "reference_id"]:
			if not record[field] is String:
				return _fail("Invalid ledger transaction reference")
		if seen.has(record["transaction_id"]):
			return _fail("Duplicate transaction in ledger snapshot")
		seen[record["transaction_id"]] = true
	var index: int = 0
	while index < value["transactions"].size():
		var record := value["transactions"][index] as Dictionary
		var tx := str(record["transaction_id"])
		if batch_by_tx.has(tx):
			var id := str(batch_by_tx[tx])
			var batch := batches[id] as Dictionary
			var legs: Array[Dictionary] = []
			for expected: String in batch["transactions"]:
				if index >= value["transactions"].size() or value["transactions"][index]["transaction_id"] != expected or value["transactions"][index]["effective_minute"] != batch["minute"]:
					return _fail("Noncontiguous or missing atomic payment legs")
				var leg := (value["transactions"][index] as Dictionary).duplicate(true)
				for key: String in ["denomination", "effective_minute", "basis"]:
					leg.erase(key)
				legs.append(leg)
				index += 1
			if not candidate.batch_payment(id, legs, int(batch["minute"])):
				return _fail(candidate.error)
			candidate._batches[id] = batch.duplicate(true)
		else:
			if not candidate.transfer(tx, record["from_account_id"], record["to_account_id"], int(record["amount"]), int(record["effective_minute"]), record["kind"], record["reference_id"]):
				return _fail(candidate.error)
			index += 1
	for id: String in batches:
		if not candidate._batches.has(id):
			if not batches[id]["transactions"].is_empty() or not batches[id]["releases"].is_empty():
				return _fail("Missing atomic payment")
			candidate._batches[id] = batches[id].duplicate(true)
	if _r1_enabled:
		if not value["r1_reservations"] is Dictionary:
			return _fail("Invalid reservation container")
		for id: Variant in value["r1_reservations"]:
			var record: Variant = value["r1_reservations"][id]
			if not id is String or not record is Dictionary or not exact_fields(record, ["account_id", "amount"]) or not record["account_id"] is String or not valid_amount(record["amount"]) or not candidate.reserve(id, record["account_id"], record["amount"]):
				return _fail("Invalid saved reservation")
	if candidate.snapshot() != value:
		return _fail("Balances do not match recorded transactions")
	_scenario_budget = candidate._scenario_budget
	_accounts = candidate._accounts
	_accounts_by_owner = candidate._accounts_by_owner
	_transactions = candidate._transactions
	_transactions_by_id = candidate._transactions_by_id
	_transactions_by_account = candidate._transactions_by_account
	_transactions_by_owner = candidate._transactions_by_owner
	_reservations = candidate._reservations
	_reserved_by_account = candidate._reserved_by_account
	_currency_budgets = candidate._currency_budgets
	_batches = candidate._batches
	error = ""
	return true


static func valid_amount(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_AMOUNT


static func exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _fail(message: String) -> bool:
	error = message
	return false

func _index_transaction(receipt: Dictionary) -> void:
	for account_id: String in [receipt["from_account_id"], receipt["to_account_id"]]:
		if not _transactions_by_account.has(account_id):
			_transactions_by_account[account_id] = []
		_transactions_by_account[account_id].append(receipt)

	var from_owner := str(_accounts[receipt["from_account_id"]]["owner_id"])
	var to_owner := str(_accounts[receipt["to_account_id"]]["owner_id"])
	var owners: Array[String] = [from_owner]
	if to_owner != from_owner: owners.append(to_owner)
	for owner: String in owners:
		if not _transactions_by_owner.has(owner): _transactions_by_owner[owner] = []
		_transactions_by_owner[owner].append(receipt)

## Explicit finite development endowment at creation only. Never on load.
func add_native_genesis(amount: int) -> bool:
	if not _r1_enabled or _scenario_budget < 0 or not valid_amount(amount) or amount > MAX_AMOUNT - _scenario_budget:
		return _fail("Invalid native opening budget")
	for receipt: Dictionary in _transactions:
		if receipt["effective_minute"] != 0 or receipt["kind"] not in ["opening_cash", "employer_reserve"] or str(receipt["transaction_id"]).begins_with("r1:"):
			return _fail("Native endowment requires unused new-world composition")
	_scenario_budget += amount
	_accounts[SOURCE_ACCOUNT]["balance"] = int(_accounts[SOURCE_ACCOUNT]["balance"]) + amount
	return true
