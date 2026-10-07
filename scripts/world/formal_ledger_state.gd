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


func configure(scenario_budget: int) -> bool:
	if _scenario_budget >= 0 or not valid_amount(scenario_budget):
		return _fail("Invalid or repeated scenario endowment")
	_scenario_budget = scenario_budget
	# Only the finite scenario source receives a genesis endowment. Personal and
	# payer accounts start at zero and are funded by recorded normal transfers.
	_accounts[SOURCE_ACCOUNT] = {"account_id": SOURCE_ACCOUNT, "owner_id": SOURCE_OWNER, "role": "opening_source", "denomination": DENOMINATION, "balance": scenario_budget}
	return true


func open_account(account_id: String, owner_id: String, role: String) -> bool:
	if _scenario_budget < 0 or not account_id.begins_with("account:") or account_id.length() <= 8 or owner_id.is_empty() or _accounts.has(account_id):
		return _fail("Invalid or duplicate account")
	if role not in ["personal_cash", "background_payer"]:
		return _fail("Unsupported account role")
	if role == "personal_cash":
		for existing: Dictionary in _accounts.values():
			if existing["role"] == role and existing["owner_id"] == owner_id:
				return _fail("Person already has a personal cash account")
	_accounts[account_id] = {"account_id": account_id, "owner_id": owner_id, "role": role, "denomination": DENOMINATION, "balance": 0}
	error = ""
	return true


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


func transfer(transaction_id: String, source_id: String, destination_id: String, amount: int, effective_minute: int, kind: String, reference_id: String) -> bool:
	if transaction_id.is_empty() or reference_id.is_empty() or not valid_amount(amount) or amount <= 0 or effective_minute < 0 or kind not in ["opening_cash", "employer_reserve", "wage"]:
		return _fail("Invalid transaction")
	var receipt := {"transaction_id": transaction_id, "from_account_id": source_id, "to_account_id": destination_id, "amount": amount, "denomination": DENOMINATION, "effective_minute": effective_minute, "kind": kind, "reference_id": reference_id, "basis": "GENERATED_SIMULATION_ASSUMPTION"}
	if _transactions_by_id.has(transaction_id):
		if _transactions_by_id[transaction_id] != receipt:
			return _fail("Idempotency key conflicts with an existing transaction")
		error = ""
		return true
	if source_id == destination_id or not _accounts.has(source_id) or not _accounts.has(destination_id):
		return _fail("Transaction accounts are unavailable")
	var source := _accounts[source_id] as Dictionary
	var destination := _accounts[destination_id] as Dictionary
	if source["denomination"] != destination["denomination"] or int(source["balance"]) < amount or int(destination["balance"]) > MAX_AMOUNT - amount:
		return _fail("Insufficient funds or incompatible denomination/numeric bounds")
	if not _transactions.is_empty() and effective_minute < int(_transactions.back()["effective_minute"]):
		return _fail("Transaction time precedes the recorded ledger")
	source["balance"] = int(source["balance"]) - amount
	destination["balance"] = int(destination["balance"]) + amount
	_transactions.append(receipt)
	_transactions_by_id[transaction_id] = receipt
	error = ""
	return true


func snapshot() -> Dictionary:
	var accounts: Array[Dictionary] = []
	for account_id: String in account_ids():
		accounts.append(account(account_id))
	return {"schema_id": SCHEMA_ID, "denomination": DENOMINATION, "scenario_budget": _scenario_budget, "accounts": accounts, "transactions": transactions()}


## Replaying a detached ledger proves balances and prevents unexplained credits.
func restore(value: Dictionary) -> bool:
	if not exact_fields(value, ["schema_id", "denomination", "scenario_budget", "accounts", "transactions"]) or value.get("schema_id") != SCHEMA_ID or value.get("denomination") != DENOMINATION or not valid_amount(value.get("scenario_budget")):
		return _fail("Invalid ledger snapshot header")
	if not value["accounts"] is Array or not value["transactions"] is Array:
		return _fail("Invalid ledger snapshot containers")
	var candidate := FormalLedgerState.new()
	if not candidate.configure(int(value["scenario_budget"])):
		return _fail(candidate.error)
	var seen: Dictionary = {}
	for raw: Variant in value["accounts"]:
		if not raw is Dictionary:
			return _fail("Invalid ledger account")
		var record := raw as Dictionary
		if not exact_fields(record, ACCOUNT_FIELDS) or not record["account_id"] is String or not record["owner_id"] is String or not record["role"] is String or record["denomination"] != DENOMINATION or not valid_amount(record["balance"]) or seen.has(record["account_id"]):
			return _fail("Invalid or duplicate ledger account")
		seen[record["account_id"]] = true
		if record["account_id"] == SOURCE_ACCOUNT:
			if record["owner_id"] != SOURCE_OWNER or record["role"] != "opening_source":
				return _fail("Invalid opening source")
		elif not candidate.open_account(record["account_id"], record["owner_id"], record["role"]):
			return _fail(candidate.error)
	if not seen.has(SOURCE_ACCOUNT):
		return _fail("Missing finite scenario source")
	seen.clear()
	for raw: Variant in value["transactions"]:
		if not raw is Dictionary:
			return _fail("Invalid ledger transaction")
		var record := raw as Dictionary
		if not exact_fields(record, TRANSACTION_FIELDS) or not valid_amount(record["amount"]) or typeof(record["effective_minute"]) != TYPE_INT or record["denomination"] != DENOMINATION or record["basis"] != "GENERATED_SIMULATION_ASSUMPTION":
			return _fail("Invalid ledger transaction fields")
		for field: String in ["transaction_id", "from_account_id", "to_account_id", "kind", "reference_id"]:
			if not record[field] is String:
				return _fail("Invalid ledger transaction reference")
		if seen.has(record["transaction_id"]):
			return _fail("Duplicate transaction in ledger snapshot")
		seen[record["transaction_id"]] = true
		if not candidate.transfer(record["transaction_id"], record["from_account_id"], record["to_account_id"], int(record["amount"]), int(record["effective_minute"]), record["kind"], record["reference_id"]):
			return _fail(candidate.error)
	if candidate.snapshot() != value:
		return _fail("Balances do not match recorded transactions")
	_scenario_budget = candidate._scenario_budget
	_accounts = candidate._accounts
	_transactions = candidate._transactions
	_transactions_by_id = candidate._transactions_by_id
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
