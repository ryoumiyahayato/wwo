class_name EconomyProcurementBudget
extends RefCounted
## Appropriations are not cash. Accepted commitments retain their original window
## until settlement/cancellation, even after a manager or window changes.
var rules: Array[Dictionary] = []
var subject_aliases: Dictionary = {}
var claims: Dictionary = {}
var settlements: Dictionary = {}
var _used: Dictionary = {} # Derived from claims, never saved.

static func valid_rules(raw: Variant) -> bool:
	if not raw is Array or raw.size() > 256: return false
	var seen: Dictionary = {}
	for r: Variant in raw:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r, ["id", "subject", "root_authority", "denomination", "category", "start_minute", "end_minute", "limit", "carryover", "priority", "basis"]): return false
		for k: String in ["id", "subject", "root_authority", "category", "basis"]:
			if not r[k] is String or r[k].is_empty(): return false
		if seen.has(r["id"]) or not FormalLedgerState.currency_id(r["denomination"]) or r["carryover"] != "RETAIN_ORIGINAL_WINDOW" or not FormalLedgerState.valid_amount(r["limit"]) or not FormalLedgerState.valid_amount(r["start_minute"]) or not FormalLedgerState.valid_amount(r["end_minute"]) or int(r["end_minute"]) <= int(r["start_minute"]) or r["priority"] != "EXISTING_ACTION_ORDER": return false
		for other: Dictionary in seen.values():
			if other["subject"] == r["subject"] and other["denomination"] == r["denomination"] and other["category"] == r["category"] and int(r["start_minute"]) < int(other["end_minute"]) and int(other["start_minute"]) < int(r["end_minute"]): return false
		seen[r["id"]] = r
	return true

func configure(raw: Array) -> void:
	rules.assign(raw.duplicate(true))

func plan(subject: String, currency: String, category: String, amount: int, minute: int) -> Dictionary:
	if not FormalLedgerState.valid_amount(amount) or not FormalLedgerState.valid_amount(minute): return {"ok": false, "reason": "INVALID_BUDGET_AMOUNT_OR_TIME"}
	subject = str(subject_aliases.get(subject, subject))
	var covered := false
	for r: Dictionary in rules:
		if r["subject"] != subject or r["denomination"] != currency or r["category"] != category: continue
		covered = true
		if minute < int(r["start_minute"]) or minute >= int(r["end_minute"]): continue
		if amount > int(r["limit"])-int(_used.get(r["id"], 0)): return {"ok": false, "reason": "CUMULATIVE_BUDGET_EXCEEDED"}
		return {"ok": true, "rule_id": r["id"], "subject": subject, "root_authority": r["root_authority"], "denomination": currency, "category": category, "amount": amount, "minute": minute}
	return {"ok": not covered, "reason": "NO_EXPLICIT_BUDGET_WINDOW" if covered else "UNCONFIGURED_BUDGET_POLICY"}

func commit(order_id: String, components: Array[Dictionary]) -> bool:
	if claims.has(order_id): return false
	var prepared: Array[Dictionary] = []
	var additional: Dictionary = {}
	for p: Dictionary in components:
		if not p.get("ok", false): return false
		if not p.has("rule_id"): continue
		var r := rule(p["rule_id"])
		var next := int(additional.get(p["rule_id"], 0))+int(p["amount"])
		if r.is_empty() or int(_used.get(p["rule_id"], 0))+next > int(r["limit"]): return false
		additional[p["rule_id"]] = next
		prepared.append({"rule_id": p["rule_id"], "category": p["category"], "total": p["amount"], "spent": 0, "released": 0})
	claims[order_id] = prepared
	for id: String in additional: _used[id] = int(_used.get(id, 0))+int(additional[id])
	return true

func rule(id: String) -> Dictionary:
	for r: Dictionary in rules:
		if r["id"] == id: return r
	return {}

func change_ready(order_id: String, cumulative_delivered: int, cumulative_cancelled: int, quantity: int) -> bool:
	if not FormalLedgerState.valid_amount(quantity) or quantity <= 0 or not FormalLedgerState.valid_amount(cumulative_delivered) or not FormalLedgerState.valid_amount(cumulative_cancelled) or cumulative_delivered > quantity-cumulative_cancelled: return false
	for c: Dictionary in claims.get(order_id, []):
		var spent := share(c["total"], cumulative_delivered, quantity)
		var released := share(c["total"], cumulative_cancelled, quantity)
		if spent < int(c["spent"]) or released < int(c["released"]): return false
	return true

func settle(event_id: String, order_id: String, delivered: int, cancelled: int, quantity: int) -> bool:
	var fact := {"order_id": order_id, "delivered": delivered, "cancelled": cancelled, "quantity": quantity}
	if settlements.has(event_id): return settlements[event_id] == fact
	if not change_ready(order_id, delivered, cancelled, quantity): return false
	for c: Dictionary in claims.get(order_id, []):
		var released := share(c["total"], cancelled, quantity)
		_used[c["rule_id"]] = int(_used.get(c["rule_id"], 0))-(released-int(c["released"]))
		c["spent"] = share(c["total"], delivered, quantity)
		c["released"] = released
	settlements[event_id] = fact
	return true

func snapshot() -> Dictionary:
	return {"claims": claims.duplicate(true), "settlements": settlements.duplicate(true)}

func restore(raw: Variant, orders: Dictionary, transactions: FormalLedgerState, extra_contracts: Dictionary = {}) -> bool:
	orders = orders.duplicate(true)
	orders.merge(extra_contracts, false)
	if raw == null: return rules.is_empty()
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw, ["claims", "settlements"]) or not raw["claims"] is Dictionary or not raw["settlements"] is Dictionary: return false
	var used: Dictionary = {}
	for id: String in orders:
		if not order_components(orders[id]).is_empty() and not raw["claims"].has(id): return false
	for id: String in raw["claims"]:
		if not orders.has(id) or not raw["claims"][id] is Array: return false
		var o := orders[id] as Dictionary
		var expected := order_components(o)
		if expected.size() != raw["claims"][id].size(): return false
		for i: int in expected.size():
			var c: Variant = raw["claims"][id][i]
			var p := expected[i] as Dictionary
			if not c is Dictionary or not FormalLedgerState.exact_fields(c, ["rule_id", "category", "total", "spent", "released"]): return false
			var r := rule(str(c["rule_id"]))
			if r.is_empty() or c["rule_id"] != p["rule_id"] or c["category"] != p["category"] or c["total"] != p["amount"] or not FormalLedgerState.valid_amount(c["total"]) or c["spent"] != share(c["total"], o["delivered"], o["quantity"]) or c["released"] != share(c["total"], o["cancelled"], o["quantity"]): return false
			used[r["id"]] = int(used.get(r["id"], 0))+int(c["total"])-int(c["released"])
	for r: Dictionary in rules:
		if int(used.get(r["id"], 0)) > int(r["limit"]): return false
	for id: String in raw["settlements"]:
		var f: Variant = raw["settlements"][id]
		if not f is Dictionary or not FormalLedgerState.exact_fields(f, ["order_id", "delivered", "cancelled", "quantity"]) or not orders.has(f["order_id"]) or not change_shape(f, orders[f["order_id"]]): return false
		if id.begins_with("delivery:"):
			var o := orders[f["order_id"]] as Dictionary
			var payable := int(o["price"])
			for leg: Dictionary in o["route_legs"]: payable += int(leg["freight_per_unit"])
			if payable > 0 and transactions.payment_batch(id).is_empty(): return false
	claims = raw["claims"].duplicate(true)
	settlements = raw["settlements"].duplicate(true)
	_used = used
	return true

func order_components(o: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var categories: Dictionary = {}
	if o["kind"] in ["SERVICE","LEASE","CAPITAL_ASSET"]: categories[o["category"]] = int(o["quantity"])
	if o["kind"]=="CAPITAL_FREIGHT": categories[o["category"]]=int(o["budget_amount"])
	if o["kind"] == "SALE": categories["goods:"+str(o["good"])] = int(o["price"])*int(o["quantity"])
	for leg: Dictionary in o["route_legs"]:
		var category := "freight:"+str(leg["edge_id"])
		categories[category] = int(categories.get(category, 0))+int(leg["freight_per_unit"])*int(o["quantity"])
	for category: String in categories:
		
		# Restore validates contract amounts independently of current usage.
		for r: Dictionary in rules:
			if r["subject"] == subject_aliases.get(o["buyer"], o["buyer"]) and r["denomination"] == o["denomination"] and r["category"] == category and int(o["accepted_minute"]) >= int(r["start_minute"]) and int(o["accepted_minute"]) < int(r["end_minute"]):
				result.append({"rule_id": r["id"], "category": category, "amount": categories[category]})
	return result

static func change_shape(f: Dictionary, o: Dictionary) -> bool:
	return FormalLedgerState.valid_amount(f["delivered"]) and FormalLedgerState.valid_amount(f["cancelled"]) and f["quantity"] == o["quantity"] and int(f["delivered"]) <= int(o["delivered"]) and int(f["cancelled"]) <= int(o["cancelled"])

static func share(total: int, quantity: int, contract_quantity: int) -> int:
	# Reuse Ledger's exact rational arithmetic; total*quantity may overflow int64.
	var value := FormalLedgerState.ratio(total, quantity, contract_quantity)
	return int(value.get("quotient", -1))
