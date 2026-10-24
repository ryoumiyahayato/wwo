class_name EconomyBilateralCredit
extends RefCounted
## One funded contract shared by lender and borrower. Cash stays in FormalLedgerState.
## Interest is a fixed amount, discharged before principal; there is no accrual.

const SCHEMA_ID: String = "economy_bilateral_credit_v1"
const ACTIONS: Array[String] = ["offer_credit", "accept_credit", "repay_loan", "impair_loan", "forgive_loan"]
const TERM_FIELDS: Array[String] = ["borrower", "principal_limit", "denomination", "interest", "duration_days", "valid_days", "requires_job"]
const OFFER_FIELDS: Array[String] = ["id", "lender", "lender_account", "borrower", "principal_limit", "denomination", "interest", "duration_days", "valid_days", "requires_job", "offered_minute", "expires_minute", "action_id"]
const LOAN_FIELDS: Array[String] = ["id", "offer_id", "lender", "lender_account", "borrower", "borrower_account", "denomination", "principal", "interest", "issued_minute", "due_day", "repaid", "forgiven", "creditor_carrying_value", "action_id"]

var error: String = ""
var next_offer: int = 1
var next_loan: int = 1
var _ledger: FormalLedgerState
var _offers: Dictionary = {}
var _loans: Dictionary = {}
# Derived indexes; no second balance or obligation is persisted.
var _offers_by_party: Dictionary = {}
var _loans_by_party: Dictionary = {}
var _active_loans_by_party: Dictionary = {}
var _lent_by_offer: Dictionary = {}
var _due_by_day: Dictionary = {}
var _overdue: Dictionary = {}

func bind(ledger: FormalLedgerState) -> void:
	_ledger = ledger

static func valid_terms(value: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(value, TERM_FIELDS) or not value["borrower"] is String or not FormalLedgerState.currency_id(value["denomination"]) or not value["requires_job"] is bool:
		return false
	for key: String in ["principal_limit", "interest", "duration_days", "valid_days"]:
		if not FormalLedgerState.valid_amount(value[key]):
			return false
	return int(value["principal_limit"]) > 0 and int(value["principal_limit"]) <= FormalLedgerState.MAX_AMOUNT - int(value["interest"]) and int(value["duration_days"]) > 0 and int(value["duration_days"]) <= int(FormalLedgerState.MAX_AMOUNT / 1440) and int(value["valid_days"]) > 0 and int(value["valid_days"]) <= int(FormalLedgerState.MAX_AMOUNT / 1440)

func offer(lender: String, account_id: String, terms: Dictionary, minute: int, action_id: String) -> Dictionary:
	if not valid_terms(terms) or terms["borrower"] == lender or _ledger.account(account_id).get("owner_id") != lender or _ledger.account(account_id).get("denomination") != terms["denomination"]:
		return _result(false, "INVALID_CREDIT_TERMS")
	if not FormalLedgerState.valid_amount(minute) or minute > FormalLedgerState.MAX_AMOUNT - int(terms["valid_days"]) * 1440 or minute > FormalLedgerState.MAX_AMOUNT - int(terms["duration_days"]) * 1440 or next_offer >= FormalLedgerState.MAX_AMOUNT:
		return _result(false, "CREDIT_TIME_OR_ID_LIMIT")
	var id := "credit_offer:" + str(next_offer)
	var record := terms.duplicate(true)
	record.merge({"id": id, "lender": lender, "lender_account": account_id, "offered_minute": minute, "expires_minute": minute + int(terms["valid_days"]) * 1440, "action_id": action_id})
	_offers[id] = record
	next_offer += 1
	_append(_offers_by_party, lender, id)
	_append(_offers_by_party, str(terms["borrower"]), id)
	return {"accepted": true, "reason": "ACCEPTED", "offer_id": id}

func offer_currency(id: String) -> String:
	return str(_offers.get(id, {}).get("denomination", ""))

func accept(borrower: String, account_id: String, payload: Dictionary, known_lenders: Array[String], employed: bool, minute: int, action_id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["offer_id", "amount"]) or not payload["offer_id"] is String or not _positive(payload["amount"]):
		return _result(false, "INVALID_LOAN_REQUEST")
	var terms: Dictionary = _offers.get(payload["offer_id"], {})
	if terms.is_empty() or not _visible_offer(borrower, terms, known_lenders) or terms["lender"] == borrower:
		return _result(false, "UNKNOWN_CREDIT_OFFER")
	if minute < int(terms["offered_minute"]) or minute >= int(terms["expires_minute"]):
		return _result(false, "CREDIT_OFFER_EXPIRED")
	if terms["requires_job"] and not employed:
		return _result(false, "NO_CURRENT_JOB")
	var amount := int(payload["amount"])
	if amount > int(terms["principal_limit"]) - int(_lent_by_offer.get(terms["id"], 0)):
		return _result(false, "CREDIT_OFFER_EXHAUSTED")
	if _ledger.account(account_id).get("owner_id") != borrower or _ledger.account(account_id).get("denomination") != terms["denomination"]:
		return _result(false, "INVALID_BORROWER_ACCOUNT")
	if _ledger.available_balance(terms["lender_account"]) < amount:
		return _result(false, "LENDER_FUNDS")
	if next_loan >= FormalLedgerState.MAX_AMOUNT or not FormalLedgerState.valid_amount(minute) or minute > FormalLedgerState.MAX_AMOUNT - int(terms["duration_days"]) * 1440:
		return _result(false, "CREDIT_TIME_OR_ID_LIMIT")
	var id := "loan:" + str(next_loan)
	var transaction_id := "r1:loan_issue:" + id
	if not _ledger.transaction(transaction_id).is_empty():
		return _result(false, "LOAN_ID_CONFLICT")
	var loan := {"id": id, "offer_id": terms["id"], "lender": terms["lender"], "lender_account": terms["lender_account"], "borrower": borrower, "borrower_account": account_id, "denomination": terms["denomination"], "principal": amount, "interest": terms["interest"], "issued_minute": minute, "due_day": int(minute / 1440) + int(terms["duration_days"]), "repaid": 0, "forgiven": 0, "creditor_carrying_value": amount + int(terms["interest"]), "action_id": action_id}
	# All contract conditions are resolved before the existing atomic transfer.
	# The remaining operations install this prebuilt record and derived indexes.
	if not _ledger.transfer(transaction_id, terms["lender_account"], account_id, amount, minute, "loan_issue", id):
		return {"accepted": false, "reason": "LOAN_TRANSFER_FAILED", "message": _ledger.error}
	_loans[id] = loan
	next_loan += 1
	_index_loan(loan, int(minute / 1440))
	return {"accepted": true, "reason": "ACCEPTED", "loan_id": id, "amount": amount, "transaction_id": transaction_id}

func repay(borrower: String, payload: Dictionary, minute: int, action_id: String) -> Dictionary:
	if not _valid_payment(payload):
		return _result(false, "INVALID_LOAN_PAYMENT")
	var loan: Dictionary = _loans.get(payload["loan_id"], {})
	if loan.is_empty() or loan["borrower"] != borrower:
		return _result(false, "NOT_LOAN_BORROWER")
	var amount := int(payload["amount"])
	if amount > _remaining(loan):
		return _result(false, "PAYMENT_EXCEEDS_DEBT")
	if _ledger.available_balance(loan["borrower_account"]) < amount:
		return _result(false, "BORROWER_FUNDS")
	var transaction_id := "r1:loan_repayment:" + action_id
	if not _ledger.transaction(transaction_id).is_empty():
		return _result(false, "PAYMENT_ALREADY_RECORDED")
	var interest_paid := mini(amount, _interest_remaining(loan))
	if not _ledger.transfer(transaction_id, loan["borrower_account"], loan["lender_account"], amount, minute, "loan_repayment", str(loan["id"])):
		return {"accepted": false, "reason": "LOAN_TRANSFER_FAILED", "message": _ledger.error}
	loan["repaid"] = int(loan["repaid"]) + amount
	loan["creditor_carrying_value"] = mini(int(loan["creditor_carrying_value"]), _remaining(loan))
	_remove_settled(loan)
	return {"accepted": true, "reason": "ACCEPTED", "loan_id": loan["id"], "amount": amount, "interest_paid": interest_paid, "principal_paid": amount - interest_paid, "transaction_id": transaction_id}

func adjust(lender: String, payload: Dictionary, forgive: bool) -> Dictionary:
	if not _valid_payment(payload):
		return _result(false, "INVALID_CREDIT_ADJUSTMENT")
	var loan: Dictionary = _loans.get(payload["loan_id"], {})
	if loan.is_empty() or loan["lender"] != lender:
		return _result(false, "NOT_LOAN_LENDER")
	var amount := int(payload["amount"])
	if amount > (_remaining(loan) if forgive else int(loan["creditor_carrying_value"])):
		return _result(false, "ADJUSTMENT_EXCEEDS_RESPONSIBILITY")
	if forgive:
		loan["forgiven"] = int(loan["forgiven"]) + amount
		loan["creditor_carrying_value"] = mini(int(loan["creditor_carrying_value"]), _remaining(loan))
		_remove_settled(loan)
	else:
		# Valuation loss does not release the borrower's legal obligation.
		loan["creditor_carrying_value"] = int(loan["creditor_carrying_value"]) - amount
	return {"accepted": true, "reason": "ACCEPTED", "loan_id": loan["id"], "amount": amount}

func advance_day(current_day: int) -> void:
	# Only today's open maturities are visited; no payment is authorized here.
	for id: String in _due_by_day.get(current_day, []):
		_overdue[id] = true
	_due_by_day.erase(current_day)

func known_lenders(actor: String) -> Array[String]:
	# A directly received quote identifies its author even after expiry.
	var result: Array[String] = []
	for id: String in _offers_by_party.get(actor, []):
		var terms := _offers[id] as Dictionary
		if terms["borrower"] == actor and not result.has(terms["lender"]):
			result.append(terms["lender"])
	return result

func visible(actor: String, known_lenders: Array[String], minute: int, active_only: bool = false) -> Dictionary:
	var offers: Array[Dictionary] = []
	var ids: Array = _offers_by_party.get(actor, []).duplicate()
	for id: String in _offers_by_party.get("", []):
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for id: String in ids:
		var terms := _offers[id] as Dictionary
		if terms["lender"] != actor and not _visible_offer(actor, terms, known_lenders):
			continue
		if minute >= int(terms["expires_minute"]):
			continue
		var row := terms.duplicate(true)
		row["available_quantity"] = mini(int(terms["principal_limit"]) - int(_lent_by_offer.get(id, 0)), maxi(0, _ledger.available_balance(terms["lender_account"])))
		row["interest_rule"] = "FIXED_AMOUNT"
		row["due_rule"] = "ISSUE_DAY_PLUS_DURATION"
		row["payment_order"] = "INTEREST_FIRST"
		offers.append(row)
	var loans: Array[Dictionary] = []
	var own: Array = _active_loans_by_party.get(actor, {}).keys() if active_only else _loans_by_party.get(actor, []).duplicate()
	own.sort()
	for id: String in own:
		var loan := _loans[id] as Dictionary
		var row := loan.duplicate(true)
		row["remaining_interest"] = _interest_remaining(loan)
		row["remaining_principal"] = _remaining(loan) - int(row["remaining_interest"])
		row["remaining"] = _remaining(loan)
		row["overdue_amount"] = _remaining(loan) if _overdue.has(id) else 0
		row["status"] = "SETTLED" if _remaining(loan) == 0 else "OVERDUE" if _overdue.has(id) else "ACTIVE"
		row["interest_rule"] = "FIXED_AMOUNT"
		row["payment_order"] = "INTEREST_FIRST"
		if loan["lender"] != actor:
			row.erase("creditor_carrying_value")
		loans.append(row)
	return {"offers": offers, "loans": loans}

func snapshot() -> Dictionary:
	return {"schema_id": SCHEMA_ID, "next_offer": next_offer, "next_loan": next_loan, "offers": _offers.duplicate(true), "loans": _loans.duplicate(true)}

func restore(value: Variant, commands: Dictionary, subjects: Dictionary, information_dates: Dictionary, minute: int) -> bool:
	# An absent block is an old save, not permission to discard unknown data.
	if value == null:
		value = {"schema_id": SCHEMA_ID, "next_offer": 1, "next_loan": 1, "offers": {}, "loans": {}}
	if not value is Dictionary or not FormalLedgerState.exact_fields(value, ["schema_id", "next_offer", "next_loan", "offers", "loans"]) or value["schema_id"] != SCHEMA_ID or not value["offers"] is Dictionary or not value["loans"] is Dictionary:
		return _fail("Unsupported credit snapshot")
	for key: String in ["next_offer", "next_loan"]:
		if not _positive(value[key]):
			return _fail("Invalid credit next ID")
	if value["offers"].size() != int(value["next_offer"]) - 1 or value["loans"].size() != int(value["next_loan"]) - 1:
		return _fail("Missing credit records")
	var offers := value["offers"] as Dictionary
	var loans := value["loans"] as Dictionary
	for number: int in range(1, int(value["next_offer"])):
		var id := "credit_offer:" + str(number)
		var row: Variant = offers.get(id)
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, OFFER_FIELDS):
			return _fail("Invalid credit offer record")
		var terms: Dictionary = {}
		for key: String in TERM_FIELDS:
			terms[key] = row[key]
		if not valid_terms(terms) or row["id"] != id or not _party(row["lender"], row["lender_account"], subjects, row["denomination"]) or (row["borrower"] != "" and (not subjects.has(row["borrower"]) or row["borrower"] == row["lender"])):
			return _fail("Invalid credit offer parties or terms")
		if not FormalLedgerState.valid_amount(row["offered_minute"]) or not FormalLedgerState.valid_amount(row["expires_minute"]) or int(row["offered_minute"]) > minute or int(row["offered_minute"]) > FormalLedgerState.MAX_AMOUNT - int(row["valid_days"]) * 1440 or int(row["offered_minute"]) > FormalLedgerState.MAX_AMOUNT - int(row["duration_days"]) * 1440 or row["expires_minute"] != int(row["offered_minute"]) + int(row["valid_days"]) * 1440:
			return _fail("Invalid credit offer dates")
		var action := _action(commands, row["action_id"], "offer_credit", row["lender"])
		if action.is_empty() or action["envelope"]["command"]["payload"] != terms or action["envelope"]["command"]["minute"] != row["offered_minute"] or action["result"].get("offer_id") != id:
			return _fail("Credit offer lacks its authorized action")
	var lent: Dictionary = {}
	for number: int in range(1, int(value["next_loan"])):
		var id := "loan:" + str(number)
		var row: Variant = loans.get(id)
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, LOAN_FIELDS) or row["id"] != id or not offers.has(row["offer_id"]):
			return _fail("Invalid loan record or offer reference")
		var terms := offers[row["offer_id"]] as Dictionary
		if not _party(row["lender"], row["lender_account"], subjects, row["denomination"]) or not _party(row["borrower"], row["borrower_account"], subjects, row["denomination"]) or row["borrower"] == row["lender"] or row["lender"] != terms["lender"] or row["lender_account"] != terms["lender_account"] or row["denomination"] != terms["denomination"] or row["interest"] != terms["interest"] or (terms["borrower"] != "" and row["borrower"] != terms["borrower"]):
			return _fail("Loan parties or locked terms conflict")
		for key: String in ["principal", "interest", "issued_minute", "due_day", "repaid", "forgiven", "creditor_carrying_value"]:
			if not FormalLedgerState.valid_amount(row[key]):
				return _fail("Invalid loan amount or date")
		if int(row["principal"]) <= 0 or int(row["principal"]) > int(terms["principal_limit"]) or int(row["principal"]) > FormalLedgerState.MAX_AMOUNT - int(row["interest"]) or int(row["issued_minute"]) < int(terms["offered_minute"]) or int(row["issued_minute"]) >= int(terms["expires_minute"]) or int(row["issued_minute"]) > minute or int(row["issued_minute"]) > FormalLedgerState.MAX_AMOUNT - int(terms["duration_days"]) * 1440 or row["due_day"] != int(int(row["issued_minute"]) / 1440) + int(terms["duration_days"]):
			return _fail("Loan quantity or maturity conflict")
		var total := int(row["principal"]) + int(row["interest"])
		if int(row["repaid"]) > total or int(row["forgiven"]) > total - int(row["repaid"]) or int(row["creditor_carrying_value"]) > _remaining(row):
			return _fail("Loan responsibility conflict")
		var action := _action(commands, row["action_id"], "accept_credit", row["borrower"])
		if action.is_empty() or action["envelope"]["command"]["payload"] != {"offer_id": row["offer_id"], "amount": row["principal"]} or action["envelope"]["command"]["minute"] != row["issued_minute"] or action["result"].get("loan_id") != id or action["result"].get("amount") != row["principal"] or action["result"].get("transaction_id") != "r1:loan_issue:" + id:
			return _fail("Loan lacks its accepted borrowing action")
		lent[row["offer_id"]] = int(lent.get(row["offer_id"], 0)) + int(row["principal"])
		if int(lent[row["offer_id"]]) > int(terms["principal_limit"]):
			return _fail("Credit offer allocation exceeded")
	if not _reconcile(loans, offers, commands, information_dates, minute):
		return false
	_offers = offers.duplicate(true)
	_loans = loans.duplicate(true)
	next_offer = int(value["next_offer"])
	next_loan = int(value["next_loan"])
	_offers_by_party.clear()
	_loans_by_party.clear()
	_active_loans_by_party.clear()
	_lent_by_offer.clear()
	_due_by_day.clear()
	_overdue.clear()
	for row: Dictionary in _offers.values():
		_append(_offers_by_party, str(row["lender"]), str(row["id"]))
		_append(_offers_by_party, str(row["borrower"]), str(row["id"]))
	for row: Dictionary in _loans.values():
		_index_loan(row, int(minute / 1440))
	return true

func _reconcile(loans: Dictionary, offers: Dictionary, commands: Dictionary, information_dates: Dictionary, minute: int) -> bool:
	# Reconcile stored obligations and action receipts. Restore never calls transfer.
	var issued: Dictionary = {}
	var paid: Dictionary = {}
	for transaction: Dictionary in _ledger.transactions():
		if transaction["kind"] not in ["loan_issue", "loan_repayment"]:
			continue
		var id := str(transaction["reference_id"])
		if not loans.has(id) or int(transaction["effective_minute"]) > minute:
			return _fail("Unexplained credit transfer")
		var loan := loans[id] as Dictionary
		if transaction["kind"] == "loan_issue":
			if issued.has(id) or not _payment_matches(transaction, "r1:loan_issue:" + id, loan["lender_account"], loan["borrower_account"], int(loan["principal"]), int(loan["issued_minute"])):
				return _fail("Loan funding differs from Ledger")
			issued[id] = true
		else:
			var action_id := str(transaction["transaction_id"]).trim_prefix("r1:loan_repayment:")
			var action := _action(commands, action_id, "repay_loan", loan["borrower"])
			if action.is_empty() or action["envelope"]["command"]["payload"] != {"loan_id": id, "amount": transaction["amount"]} or int(transaction["effective_minute"]) < int(loan["issued_minute"]) or action["result"].get("transaction_id") != transaction["transaction_id"] or not _payment_matches(transaction, "r1:loan_repayment:" + action_id, loan["borrower_account"], loan["lender_account"], int(action["result"].get("amount", -1)), int(action["envelope"]["command"]["minute"])):
				return _fail("Loan repayment lacks its actual action or payment")
			paid[action_id] = true
	if issued.size() != loans.size():
		return _fail("Unfunded loan contract")
	# Dictionary insertion order is retained by the host's exact Variant save.
	# It resolves adjustments at the same minute without a research sequence.
	var balances: Dictionary = {}
	var posted: Dictionary = {}
	var employed: Dictionary = {}
	for action_id: String in commands:
		var entry := commands[action_id] as Dictionary
		var command := entry["envelope"]["command"] as Dictionary
		var actor := str(entry["envelope"]["actor"])
		if command["kind"] == "apply" and entry["result"]["accepted"]:
			employed[actor] = int(command["minute"])
		if command["kind"] not in ACTIONS or not entry["result"]["accepted"]:
			continue
		var payload := command["payload"] as Dictionary
		if command["kind"] == "offer_credit":
			var id := str(entry["result"].get("offer_id", ""))
			if not offers.has(id) or offers[id]["action_id"] != action_id:
				return _fail("Accepted offer has no credit record")
			posted[id] = true
			continue
		if command["kind"] == "accept_credit":
			var id := str(entry["result"].get("loan_id", ""))
			if not loans.has(id) or loans[id]["action_id"] != action_id or balances.has(id):
				return _fail("Accepted borrowing has no unique loan")
			var loan := loans[id] as Dictionary
			var terms := offers[loan["offer_id"]] as Dictionary
			if not posted.has(loan["offer_id"]) or (terms["requires_job"] and (not employed.has(actor) or int(employed[actor]) > int(loan["issued_minute"]))) or not _known_at_issue(loan, terms, posted, offers, information_dates):
				return _fail("Borrowing lacks received terms or required employment")
			var total := int(loans[id]["principal"]) + int(loans[id]["interest"])
			balances[id] = {"remaining": total, "carrying": total, "repaid": 0, "forgiven": 0, "last_minute": loan["issued_minute"]}
			continue
		if not _valid_payment(payload) or not balances.has(payload["loan_id"]):
			return _fail("Credit adjustment precedes or lacks its loan")
		var id := str(payload["loan_id"])
		var state := balances[id] as Dictionary
		var amount := int(payload["amount"])
		if entry["result"].get("loan_id") != id or entry["result"].get("amount") != amount or int(command["minute"]) < int(state["last_minute"]):
			return _fail("Credit action result conflict")
		state["last_minute"] = command["minute"]
		if command["kind"] == "impair_loan":
			if actor != loans[id]["lender"] or amount > int(state["carrying"]):
				return _fail("Invalid creditor impairment")
			state["carrying"] = int(state["carrying"]) - amount
		else:
			if amount > int(state["remaining"]) or (command["kind"] == "repay_loan" and (actor != loans[id]["borrower"] or not paid.has(action_id))) or (command["kind"] == "forgive_loan" and actor != loans[id]["lender"]):
				return _fail("Invalid legal debt reduction")
			if command["kind"] == "repay_loan":
				var interest_paid := mini(amount, maxi(0, int(loans[id]["interest"]) - int(state["repaid"]) - int(state["forgiven"])))
				if entry["result"].get("interest_paid") != interest_paid or entry["result"].get("principal_paid") != amount - interest_paid:
					return _fail("Loan repayment allocation conflict")
			var key := "repaid" if command["kind"] == "repay_loan" else "forgiven"
			state[key] = int(state[key]) + amount
			state["remaining"] = int(state["remaining"]) - amount
			state["carrying"] = mini(int(state["carrying"]), int(state["remaining"]))
	for id: String in loans:
		if not balances.has(id) or balances[id]["repaid"] != loans[id]["repaid"] or balances[id]["forgiven"] != loans[id]["forgiven"] or balances[id]["carrying"] != loans[id]["creditor_carrying_value"]:
			return _fail("Loan responsibility differs from its accepted actions")
	return true

static func _known_at_issue(loan: Dictionary, terms: Dictionary, posted: Dictionary, offers: Dictionary, information_dates: Dictionary) -> bool:
	if terms["borrower"] == loan["borrower"]:
		return true
	var known: Dictionary = information_dates.get(loan["borrower"], {})
	if known.has(loan["lender"]) and int(known[loan["lender"]]) <= int(loan["issued_minute"]):
		return true
	for id: String in posted:
		if offers[id]["borrower"] == loan["borrower"] and offers[id]["lender"] == loan["lender"] and int(offers[id]["offered_minute"]) <= int(loan["issued_minute"]):
			return true
	return false

func _index_loan(loan: Dictionary, current_day: int) -> void:
	var id := str(loan["id"])
	_append(_loans_by_party, str(loan["lender"]), id)
	_append(_loans_by_party, str(loan["borrower"]), id)
	_lent_by_offer[loan["offer_id"]] = int(_lent_by_offer.get(loan["offer_id"], 0)) + int(loan["principal"])
	if _remaining(loan) > 0:
		for party: String in [loan["lender"], loan["borrower"]]:
			if not _active_loans_by_party.has(party): _active_loans_by_party[party] = {}
			_active_loans_by_party[party][id] = true
		if int(loan["due_day"]) <= current_day:
			_overdue[id] = true
		else:
			_append(_due_by_day, int(loan["due_day"]), id)

func _remove_settled(loan: Dictionary) -> void:
	if _remaining(loan) != 0:
		return
	for party: String in [loan["lender"], loan["borrower"]]: _active_loans_by_party.get(party, {}).erase(loan["id"])
	_overdue.erase(loan["id"])
	if _due_by_day.has(loan["due_day"]):
		_due_by_day[loan["due_day"]].erase(loan["id"])
		if _due_by_day[loan["due_day"]].is_empty():
			_due_by_day.erase(loan["due_day"])

static func _visible_offer(actor: String, terms: Dictionary, known_lenders: Array[String]) -> bool:
	return terms["borrower"] == actor or (terms["borrower"] == "" and known_lenders.has(terms["lender"]))

static func _remaining(loan: Dictionary) -> int:
	return int(loan["principal"]) + int(loan["interest"]) - int(loan["repaid"]) - int(loan["forgiven"])

static func _interest_remaining(loan: Dictionary) -> int:
	return maxi(0, int(loan["interest"]) - int(loan["repaid"]) - int(loan["forgiven"]))

static func _positive(value: Variant) -> bool:
	return FormalLedgerState.valid_amount(value) and int(value) > 0

static func _valid_payment(payload: Dictionary) -> bool:
	return FormalLedgerState.exact_fields(payload, ["loan_id", "amount"]) and payload["loan_id"] is String and _positive(payload["amount"])

func _party(id: Variant, account_id: Variant, subjects: Dictionary, denomination: Variant) -> bool:
	return id is String and account_id is String and FormalLedgerState.currency_id(denomination) and subjects.has(id) and _ledger.owner_account(id, denomination) == account_id and _ledger.account(account_id).get("owner_id") == id and _ledger.account(account_id).get("denomination") == denomination

static func _action(commands: Dictionary, id: Variant, kind: String, actor: Variant) -> Dictionary:
	if not id is String or not commands.has(id):
		return {}
	var entry := commands[id] as Dictionary
	return entry if entry["envelope"]["actor"] == actor and entry["envelope"]["command"]["kind"] == kind and entry["result"]["accepted"] else {}

static func _payment_matches(payment: Dictionary, id: String, source: String, destination: String, amount: int, minute: int) -> bool:
	return payment["transaction_id"] == id and payment["from_account_id"] == source and payment["to_account_id"] == destination and payment["amount"] == amount and payment["effective_minute"] == minute

static func _append(index: Dictionary, key: Variant, id: String) -> void:
	if not index.has(key):
		index[key] = []
	index[key].append(id)

static func _result(accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "reason": reason}

func _fail(message: String) -> bool:
	error = message
	return false
