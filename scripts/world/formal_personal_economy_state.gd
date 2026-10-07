class_name FormalPersonalEconomyState
extends RefCounted
## Person/account links and one general wage relation. The Ledger alone owns
## money; the injected GameClock alone owns time. No occupation or enterprise.

const SCHEMA_ID: String = "formal_personal_economy_state_v1"
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
	if not _ledger.configure(person_ids.size() * int(policy["opening_cash"]) + reserve):
		return _fail(_ledger.error)
	for person_id: String in person_ids:
		var account_id := personal_account_id(person_id)
		if _person_scope(person_id).is_empty() or not _ledger.open_account(account_id, person_id, "personal_cash"):
			return _fail("Personal account requires an existing supported named person")
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
		while int(record["next_pay_boundary"]) <= _clock.total_minutes():
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
	var account_id := account_id_for_person(person_id)
	var record := employment(person_id)
	var recent: Dictionary = {}
	if not record.is_empty():
		var periods := record["settled_periods"] as Array
		if not periods.is_empty():
			recent = _ledger.transaction("wage:" + pay_period_id(str(record["employment_id"]), int(periods.back())))
	var payer_balance: Variant = _ledger.balance(str(record.get("payer_account_id", "")))
	var unpaid := not record.is_empty() and int(record["next_pay_boundary"]) <= _clock.total_minutes()
	return {
		"account_id": account_id,
		"cash": _ledger.balance(account_id),
		"denomination": FormalLedgerState.DENOMINATION,
		"opening_basis": str(_policy.get("basis", "")),
		"livelihood": NO_FORMAL_EMPLOYMENT if record.is_empty() else GENERAL_WAGE_LABOR,
		"employment": record,
		"employer": employer(str(record.get("employer_id", ""))),
		"payer_balance": payer_balance,
		"recent_wage_transaction": recent,
		"wage_unpaid": unpaid,
	}


func snapshot() -> Dictionary:
	return {"schema_id": SCHEMA_ID, "policy_fingerprint": _policy_fingerprint, "person_accounts": _person_accounts.duplicate(true), "employers": _employers.duplicate(true), "employments": _employments.duplicate(true)}


func restore(value: Dictionary, player_id: String) -> bool:
	if not FormalLedgerState.exact_fields(value, ["schema_id", "policy_fingerprint", "person_accounts", "employers", "employments"]) or value.get("schema_id") != SCHEMA_ID or value.get("policy_fingerprint") != _policy_fingerprint:
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
		if not _receipt_matches(transaction_id, FormalLedgerState.SOURCE_ACCOUNT, accounts[person_id], int(_policy["opening_cash"]), 0, "opening_cash", person_id):
			return _fail("Missing or invalid opening cash transaction")
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
		var employer_id := "employer:background_wage:" + _person_scope(person_id)
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
		if int(record["next_pay_boundary"]) <= _clock.total_minutes() and int(_ledger.balance(str(record["payer_account_id"]))) >= int(record["wage_amount"]):
			return _fail("Funded due wage period was not settled")
	if used_employers.size() != employers.size() or _ledger.account_ids().size() != accounts.size() + employers.size() + 1:
		return _fail("Unexplained personal account or employer")
	var budget: Variant = _ledger.snapshot()["scenario_budget"]
	if budget != accounts.size() * int(_policy["opening_cash"]) + employers.size() * int(_policy["employer_reserve"]):
		return _fail("Scenario funds do not match finite opening conditions")
	var transactions := _ledger.transactions()
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


func _person_scope(person_id: String) -> String:
	var person := _persons.person(person_id)
	var scope := str(person.get("population_territory_id", ""))
	if not bool(person.get("alive", false)) or _population.unit(scope).is_empty() or _population.unit_for_place(str(person.get("current_place_id", ""))) != scope:
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
