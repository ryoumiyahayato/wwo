class_name EconomyCurrencyExchange
extends RefCounted
## Configured directed quotes from finite dealers. Cash has no owner here.

const SCHEMA_ID: String = "economy_currency_exchange_v1"
const ACTIONS: Array[String] = ["exchange_currency"]
const OFFER_FIELDS: Array[String] = ["id", "dealer", "traders", "source_currency", "target_currency", "rate_numerator", "rate_denominator", "fee", "fee_recipient", "min_source", "max_source", "source_limit", "offered_minute", "expires_minute"]
const DEAL_FIELDS: Array[String] = ["id", "action_id", "quote_id", "actor", "source_amount", "target_amount", "source_cost", "minute"]

var error: String = ""
var _ledger: FormalLedgerState
var _offers: Dictionary = {}
var _deals: Dictionary = {}
var _used: Dictionary = {}
var next_deal: int = 1

func bind(ledger: FormalLedgerState, settings: Dictionary) -> void:
	_ledger = ledger
	_offers.clear()
	for row: Dictionary in settings.get("fx_offers", []):
		_offers[row["id"]] = row.duplicate(true)

static func valid_offer(row: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(row, OFFER_FIELDS):
		return false
	for field: String in ["id", "dealer", "fee_recipient"]:
		if not row[field] is String or str(row[field]).is_empty():
			return false
	if not row["traders"] is Array or row["traders"].is_empty() or not FormalLedgerState.currency_id(row["source_currency"]) or not FormalLedgerState.currency_id(row["target_currency"]) or row["source_currency"] == row["target_currency"]:
		return false
	for field: String in ["rate_numerator", "rate_denominator", "fee", "min_source", "max_source", "source_limit", "offered_minute", "expires_minute"]:
		if not FormalLedgerState.valid_amount(row[field]):
			return false
	return int(row["rate_numerator"]) > 0 and int(row["rate_denominator"]) > 0 and int(row["min_source"]) > 0 and int(row["max_source"]) >= int(row["min_source"]) and int(row["source_limit"]) >= int(row["max_source"]) and int(row["max_source"]) <= FormalLedgerState.MAX_AMOUNT - int(row["fee"]) and int(row["expires_minute"]) > int(row["offered_minute"])

func _known(actor: String, row: Dictionary, minute: int) -> bool:
	return row["traders"].has(actor) and minute >= int(row["offered_minute"]) and minute < int(row["expires_minute"])

func _output(row: Dictionary, amount: int) -> int:
	# numerator/denominator are TARGET minor units per SOURCE minor unit.
	var value := FormalLedgerState.ratio(amount, int(row["rate_numerator"]), int(row["rate_denominator"]))
	return int(value["quotient"]) if not value.is_empty() else -1

func required_source(actor: String, quote_id: String, target: int, minute: int) -> Dictionary:
	var row: Dictionary = _offers.get(quote_id, {})
	if row.is_empty() or not _known(actor, row, minute) or not FormalLedgerState.valid_amount(target) or target <= 0:
		return _result(false, "UNKNOWN_QUOTE_OR_TARGET")
	var value := FormalLedgerState.ratio(target, int(row["rate_denominator"]), int(row["rate_numerator"]))
	if value.is_empty() or (int(value["remainder"]) > 0 and int(value["quotient"]) == FormalLedgerState.MAX_AMOUNT):
		return _result(false, "FX_AMOUNT_BOUNDS")
	var source := maxi(int(row["min_source"]), int(value["quotient"]) + (1 if int(value["remainder"]) > 0 else 0))
	if source > int(row["max_source"]) or source > int(row["source_limit"]) - int(_used.get(quote_id, 0)) or source > FormalLedgerState.MAX_AMOUNT - int(row["fee"]) or _output(row, source) < target:
		return _result(false, "FX_QUOTE_LIMIT")
	return {"accepted": true, "reason": "CALCULATED", "quote_id": quote_id, "source_amount": source, "source_cost": source + int(row["fee"]), "target_amount": _output(row, source), "fee": row["fee"], "fee_currency": row["source_currency"], "executable": _funded(actor, row, source)}

func _funded(actor: String, row: Dictionary, amount: int) -> bool:
	var target := _output(row, amount)
	return target > 0 and _funding_bounds(actor, row, amount, target)

func _funding_bounds(actor: String, row: Dictionary, amount: int, target: int) -> bool:
	var source_account := _ledger.owner_account(actor, row["source_currency"])
	var target_account := _ledger.owner_account(actor, row["target_currency"])
	var dealer_source := _ledger.owner_account(row["dealer"], row["source_currency"])
	var dealer_target := _ledger.owner_account(row["dealer"], row["target_currency"])
	var fee_account := _ledger.owner_account(row["fee_recipient"], row["source_currency"])
	var fee := int(row["fee"])
	if actor == row["dealer"] or source_account.is_empty() or target_account.is_empty() or dealer_source.is_empty() or dealer_target.is_empty() or fee_account.is_empty() or (fee > 0 and fee_account == source_account): return false
	if amount > FormalLedgerState.MAX_AMOUNT - fee or _ledger.available_balance(source_account) < amount + fee or _ledger.available_balance(dealer_target) < target: return false
	var dealer_receipt := amount + (fee if fee_account == dealer_source else 0)
	if int(_ledger.balance(dealer_source)) > FormalLedgerState.MAX_AMOUNT - dealer_receipt or int(_ledger.balance(target_account)) > FormalLedgerState.MAX_AMOUNT - target: return false
	return fee == 0 or fee_account == dealer_source or int(_ledger.balance(fee_account)) <= FormalLedgerState.MAX_AMOUNT - fee

func accept(actor: String, payload: Dictionary, minute: int, action_id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["quote_id", "source_amount", "min_target"]) or not payload["quote_id"] is String or not FormalLedgerState.valid_amount(payload["source_amount"]) or not FormalLedgerState.valid_amount(payload["min_target"]):
		return _result(false, "INVALID_EXCHANGE")
	var row: Dictionary = _offers.get(payload["quote_id"], {})
	if row.is_empty() or not _known(actor, row, minute) or row["dealer"] == actor:
		return _result(false, "UNKNOWN_OR_EXPIRED_FX_QUOTE")
	var amount := int(payload["source_amount"])
	var target := _output(row, amount)
	if amount < int(row["min_source"]) or amount > int(row["max_source"]) or amount > int(row["source_limit"]) - int(_used.get(row["id"], 0)) or target <= 0 or target < int(payload["min_target"]) or next_deal >= FormalLedgerState.MAX_AMOUNT:
		return _result(false, "FX_LIMIT_OR_SLIPPAGE")
	if not _funded(actor, row, amount):
		return _result(false, "FX_PARTICIPANT_FUNDS_OR_ACCOUNT")
	var id := "fx_deal:" + str(next_deal)
	var deal := {"id": id, "action_id": action_id, "quote_id": row["id"], "actor": actor, "source_amount": amount, "target_amount": target, "source_cost": amount + int(row["fee"]), "minute": minute}
	if not _ledger.batch_payment("fx:" + id, _legs(deal, row), minute):
		return {"accepted": false, "reason": "FX_PAYMENT_FAILED", "message": _ledger.error}
	_deals[id] = deal
	_used[row["id"]] = int(_used.get(row["id"], 0)) + amount
	next_deal += 1
	return {"accepted": true, "reason": "ACCEPTED", "deal_id": id, "source_cost": deal["source_cost"], "target_amount": target}

func _legs(deal: Dictionary, row: Dictionary) -> Array[Dictionary]:
	var id := str(deal["id"])
	var actor := str(deal["actor"])
	var source := _ledger.owner_account(actor, row["source_currency"])
	var result: Array[Dictionary] = [
		{"transaction_id": id + ":source", "from_account_id": source, "to_account_id": _ledger.owner_account(row["dealer"], row["source_currency"]), "amount": deal["source_amount"], "kind": "fx_principal", "reference_id": id},
		{"transaction_id": id + ":target", "from_account_id": _ledger.owner_account(row["dealer"], row["target_currency"]), "to_account_id": _ledger.owner_account(actor, row["target_currency"]), "amount": deal["target_amount"], "kind": "fx_target", "reference_id": id}
	]
	if int(row["fee"]) > 0:
		result.append({"transaction_id": id + ":fee", "from_account_id": source, "to_account_id": _ledger.owner_account(row["fee_recipient"], row["source_currency"]), "amount": row["fee"], "kind": "fx_fee", "reference_id": id})
	return result

func known_offers(actor: String, minute: int, execution_limits: bool = true) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for row: Dictionary in _offers.values():
		if not _known(actor, row, minute):
			continue
		var view := row.duplicate(true)
		view.erase("traders")
		view["fee_currency"] = row["source_currency"]
		if not execution_limits:
			offers.append(view)
			continue
		var lo: int = 0
		var hi := mini(int(row["max_source"]), int(row["source_limit"]) - int(_used.get(row["id"], 0)))
		while lo < hi:
			var mid: int = lo + (hi - lo + 1) / 2
			# Funding alone is monotone; a zero rounded output is handled below.
			var output := _output(row, mid)
			if output >= 0 and _funding_bounds(actor, row, mid, output):
				lo = mid
			else:
				hi = mid - 1
		view["executable_source"] = lo if lo >= int(row["min_source"]) and _funded(actor, row, lo) else 0
		offers.append(view)
	return offers

func visible(actor: String, minute: int) -> Dictionary:
	var offers := known_offers(actor, minute)
	var deals: Array[Dictionary] = []
	for row: Dictionary in _deals.values():
		if row["actor"] == actor or _offers[row["quote_id"]]["dealer"] == actor:
			deals.append(row.duplicate(true))
	return {"offers": offers, "deals": deals}

func snapshot() -> Dictionary:
	return {"schema_id": SCHEMA_ID, "offers": _offers.duplicate(true), "deals": _deals.duplicate(true), "next_deal": next_deal}

func restore(value: Variant, commands: Dictionary, minute: int) -> bool:
	if value == null:
		value = {"schema_id": SCHEMA_ID, "offers": {}, "deals": {}, "next_deal": 1}
	if not value is Dictionary or not FormalLedgerState.exact_fields(value, ["schema_id", "offers", "deals", "next_deal"]) or value["schema_id"] != SCHEMA_ID or value["offers"] != _offers or not value["deals"] is Dictionary or not FormalLedgerState.valid_amount(value["next_deal"]) or int(value["next_deal"]) < 1 or value["deals"].size() != int(value["next_deal"]) - 1:
		return _fail("Invalid saved FX state")
	var used: Dictionary = {}
	var expected: Dictionary = {}
	var accepted: Dictionary = {}
	for number: int in range(1, int(value["next_deal"])):
		var id := "fx_deal:" + str(number)
		var deal: Variant = value["deals"].get(id)
		if not deal is Dictionary or not FormalLedgerState.exact_fields(deal, DEAL_FIELDS) or deal["id"] != id or not _offers.has(deal["quote_id"]) or not deal["actor"] is String or not deal["action_id"] is String or accepted.has(deal["action_id"]):
			return _fail("Invalid saved FX deal")
		for key: String in ["source_amount", "target_amount", "source_cost", "minute"]:
			if not FormalLedgerState.valid_amount(deal[key]):
				return _fail("Invalid FX amount or date")
		var row := _offers[deal["quote_id"]] as Dictionary
		var action: Variant = commands.get(deal["action_id"])
		if not _known(deal["actor"], row, int(deal["minute"])) or int(deal["minute"]) > minute or not action is Dictionary or action["envelope"]["actor"] != deal["actor"] or action["envelope"]["command"]["kind"] != "exchange_currency" or not action["result"]["accepted"]:
			return _fail("FX deal lacks its accepted action")
		var payload := action["envelope"]["command"]["payload"] as Dictionary
		if not FormalLedgerState.exact_fields(payload, ["quote_id", "source_amount", "min_target"]) or not FormalLedgerState.valid_amount(payload["min_target"]) or payload["quote_id"] != row["id"] or payload["source_amount"] != deal["source_amount"] or action["envelope"]["command"]["minute"] != deal["minute"] or action["result"].get("deal_id") != id or action["result"].get("target_amount") != deal["target_amount"] or action["result"].get("source_cost") != deal["source_cost"] or int(deal["source_amount"]) < int(row["min_source"]) or int(deal["source_amount"]) > int(row["max_source"]) or deal["target_amount"] != _output(row, int(deal["source_amount"])) or int(deal["target_amount"]) <= 0 or int(payload["min_target"]) > int(deal["target_amount"]) or deal["source_cost"] != int(deal["source_amount"]) + int(row["fee"]):
			return _fail("FX locked conditions conflict")
		used[row["id"]] = int(used.get(row["id"], 0)) + int(deal["source_amount"])
		if int(used[row["id"]]) > int(row["source_limit"]):
			return _fail("FX finite quote exhausted")
		var ids: Array[String] = []
		for leg: Dictionary in _legs(deal, row):
			var receipt := leg.duplicate(true)
			receipt.merge({"denomination": _ledger.account(leg["from_account_id"]).get("denomination"), "effective_minute": deal["minute"], "basis": "GENERATED_SIMULATION_ASSUMPTION"})
			if _ledger.transaction(leg["transaction_id"]) != receipt:
				return _fail("FX receipt differs from actual cash")
			expected[leg["transaction_id"]] = true
			ids.append(leg["transaction_id"])
		if _ledger.payment_batch("fx:" + id) != {"transactions": ids, "releases": {}, "minute": deal["minute"]}:
			return _fail("FX lacks atomic settlement")
		accepted[deal["action_id"]] = true
	for row: Dictionary in _ledger.transactions():
		if row["kind"] in ["fx_principal", "fx_target", "fx_fee"] and not expected.has(row["transaction_id"]):
			return _fail("Unexplained FX payment")
	for id: String in commands:
		if commands[id]["envelope"]["command"]["kind"] == "exchange_currency" and commands[id]["result"]["accepted"] and not accepted.has(id):
			return _fail("Accepted FX action lost its deal")
	_deals = value["deals"].duplicate(true)
	_used = used
	next_deal = int(value["next_deal"])
	return true

static func _result(accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "reason": reason}

func _fail(message: String) -> bool:
	error = message
	return false
