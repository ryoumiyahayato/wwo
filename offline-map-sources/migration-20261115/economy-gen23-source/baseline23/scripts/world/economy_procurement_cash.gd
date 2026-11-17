extends RefCounted
## Ephemeral current decision view. This does not extend the historical dividend
## proof schema, create reservations, settle claims or choose a payment creditor.
## Original Ledger.available_balance already excludes every real reservation.

static func _source(e: RefCounted, rows: Array, firm: String, currency: String, kind: String, reference: String, denomination: String, due: int, reservation: String, basis: String) -> void:
	if denomination != currency or due <= 0: return
	var held: Dictionary = e._world.ledger_state._reservations.get(reservation, {})
	var reserved: int = int(held.get("amount", 0)) if held.get("account_id", "") == e._account(firm, currency) else 0
	rows.append({"domain": kind, "reference": reference, "currency": currency, "due_remaining": due, "already_reserved": mini(due, reserved), "due_unreserved": maxi(0, due - reserved), "basis": basis})

static func position(e: RefCounted, firm: String, currency: String) -> Dictionary:
	var ledger: FormalLedgerState = e._world.ledger_state
	var account: String = e._account(firm, currency)
	var rows: Array = []
	var unsupported: Array = []
	for id: String in e._open_wages_by_employer.get(firm, {}):
		var wage: Dictionary = e._wages[id]
		if int(wage["due_day"]) <= int(e.day):
			_source(e, rows, firm, currency, "WAGE", id, wage["denomination"], int(wage["remaining"]), "", "ORIGINAL_WORKED_DUE_WAGE_REMAINING")
	var lenders: Array[String] = []
	for loan: Dictionary in e._credit.visible(firm, lenders, e._world.game_clock.total_minutes(), true)["loans"]:
		if loan["borrower"] == firm and int(loan["due_day"]) <= int(e.day):
			_source(e, rows, firm, currency, "CREDIT", loan["id"], loan["denomination"], int(loan["remaining"]), "", "ORIGINAL_FUNDED_DUE_LOAN_REMAINING")
	for id: String in e._leases._active:
		var lease: Dictionary = e._leases.contracts[id]
		if lease["tenant"] == firm:
			_source(e, rows, firm, currency, "LEASE", id, e._leases._offers[lease["offer_id"]]["denomination"], maxi(0, int(lease["due"]) - int(lease["paid"])), id, "ORIGINAL_DUE_NOT_FUTURE_RENT_LESS_MATCHING_RESERVE")
	for id: String in e._service_market._active:
		var service: Dictionary = e._service_market.contracts[id]
		if service["payer"] == firm:
			_source(e, rows, firm, currency, "SERVICE", id, e._service_market._offers[service["offer_id"]]["denomination"], maxi(0, int(service["earned"]) - int(service["paid"])), id, "ORIGINAL_EARNED_UNPAID_LESS_MATCHING_RESERVE")
	for id: String in e._cargo_fulfilment._open_dispositions.get(firm, {}):
		var disposition: Dictionary = e._cargo_fulfilment.dispositions[id]
		if disposition["status"] not in ["AGREED", "PAYABLE"]: continue
		var terms: Dictionary = disposition["terms"]
		if terms["mode"] not in ["REFUND", "DAMAGES"]: continue
		var payment: Dictionary = terms.get("payment", {})
		if payment.get("payer", "") != firm: continue
		var receipt: Dictionary = ledger.transaction("cargo_payment:" + id)
		var unpaid: int = maxi(0, int(payment["amount"]) - int(receipt.get("amount", 0)))
		_source(e, rows, firm, currency, "CARGO_PAYMENT", id, payment["denomination"], unpaid, "cargo_payment:" + id, "ORIGINAL_ALL_PARTY_AGREED_REFUND_OR_DAMAGES")
	# Unagreed losses do not become fabricated money debts. Their original
	# responsibility remains, with an explicit unknown value rather than zero.
	for loss: Dictionary in e._cargo_fulfilment.losses.values():
		if firm not in loss.get("parties", []): continue
		if loss.get("order_id", "").is_empty() and loss.get("service_id", "").is_empty(): continue
		if int(loss.get("quantity", 0)) <= int(loss.get("resolved", 0)): continue
		var money_agreed: bool = false
		for d: Dictionary in e._cargo_fulfilment.dispositions.values():
			if d["loss_id"] == loss["id"] and d["terms"]["mode"] in ["REFUND", "DAMAGES"] and d["status"] in ["AGREED", "PAYABLE", "EXECUTED"]: money_agreed = true
		if not money_agreed:
			unsupported.append({"domain": "CARGO_LOSS", "reference": loss["id"], "amount": null, "physical_status": loss["status"], "reason": "NO_AGREED_ADDITIONAL_MONEY_AMOUNT_PHYSICAL_RESPONSIBILITY_RETAINED"})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["domain"]) + str(a["reference"]) < str(b["domain"]) + str(b["reference"]))
	var due_unreserved: int = 0
	for row: Dictionary in rows: due_unreserved = mini(FormalLedgerState.MAX_AMOUNT, due_unreserved + int(row["due_unreserved"]))
	var original_floor: int = maxi(e._npc_cash_floor(e._finance_policy(firm), currency), e._liquidity_cash_floor(firm, currency))
	var protected: int = maxi(original_floor, due_unreserved)
	var available: int = maxi(0, ledger.available_balance(account))
	return {"basis": "CURRENT_ORIGINAL_DUE_CASH_NO_DOUBLE_RESERVE_V1", "firm": firm, "currency": currency, "balance": ledger.balance(account), "reserved": ledger.reserved_balance(account), "available": available, "due_unreserved": due_unreserved, "original_policy_floor": original_floor, "protected": protected, "spendable": maxi(0, available - protected), "sources": rows, "unknown_responsibilities": unsupported, "scope": "CURRENT_SAME_CURRENCY_DUE_CLAIMS_NOT_ALL_FUTURE_COMMITMENTS_OR_NET_PROFIT"}
