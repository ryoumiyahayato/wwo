class_name EconomyLiquidityRules
extends RefCounted
## Bounded explicit decisions. No cash, debt, inventory or clock is owned here.
const ACTIONS: Array[String] = ["offer_credit", "accept_credit", "repay_loan", "impair_loan", "forgive_loan"]

static func valid(settings: Dictionary) -> bool:
	var firms: Dictionary = {}
	var actors: Dictionary = {}
	for row: Dictionary in settings.get("firms",[]): firms[row["id"]]=true
	for row: Dictionary in settings.get("actors",[]): actors[row["id"]]=row
	for name: String in ["liquidity_policies","labor_response_policies","firm_finance_authorities"]:
		if not settings.get(name,[]) is Array or settings.get(name,[]).size()>32: return false
	var seen: Dictionary = {}
	for p: Variant in settings.get("liquidity_policies",[]):
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["firm","currency","cash_floor","protect_due_wages","finance_due_wages","pause_after_days","recover_cash","wind_down_after_days","pause_investment","basis"]): return false
		if not firms.has(p["firm"]) or seen.has(p["firm"]) or not FormalLedgerState.currency_id(p["currency"]) or p["basis"]!="EXPLICIT_DEVELOPMENT_LIQUIDITY_POLICY": return false
		for k: String in ["cash_floor","pause_after_days","recover_cash","wind_down_after_days"]:
			if not FormalLedgerState.valid_amount(p[k]) or p[k]>1000000: return false
		for k: String in ["protect_due_wages","finance_due_wages","pause_investment"]:
			if not p[k] is bool: return false
		if p["pause_after_days"]<1 or (p["wind_down_after_days"]>0 and p["wind_down_after_days"]<=p["pause_after_days"]): return false
		seen[p["firm"]]=true
	seen.clear()
	for p: Variant in settings.get("labor_response_policies",[]):
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["actor","arrears_days","basis"]) or not actors.has(p["actor"]) or seen.has(p["actor"]) or actors[p["actor"]]["control"]!="automatic" or p["basis"]!="EXPLICIT_DEVELOPMENT_LABOR_RESPONSE" or not FormalLedgerState.valid_amount(p["arrears_days"]) or p["arrears_days"]<1 or p["arrears_days"]>90: return false
		seen[p["actor"]]=true
	seen.clear()
	for p: Variant in settings.get("firm_finance_authorities",[]):
		if not p is Dictionary: return false
		var fields: Array[String]=["id","firm","controller","operations","currency","limit","start_minute","end_minute","root_authority","basis"]
		if p.has("borrow_limits"): fields.append("borrow_limits")
		if not FormalLedgerState.exact_fields(p,fields): return false
		if p.has("borrow_limits"):
			if not p["borrow_limits"] is Dictionary or not FormalLedgerState.exact_fields(p["borrow_limits"],["daily_principal","max_debt","max_interest"]): return false
			for amount: Variant in p["borrow_limits"].values():
				if not FormalLedgerState.valid_amount(amount): return false
		if not p["id"] is String or p["id"].is_empty() or seen.has(p["id"]) or not firms.has(p["firm"]) or not p["controller"] is String or (p["controller"]!=p["firm"] and p["controller"]!="HOST_SELECTED_PLAYER" and not actors.has(p["controller"])) or not FormalLedgerState.currency_id(p["currency"]): return false
		if not p["operations"] is Array or p["operations"].is_empty() or p["operations"].size()>ACTIONS.size(): return false
		var operations: Dictionary = {}
		for k: Variant in p["operations"]:
			if k not in ACTIONS or operations.has(k): return false
			operations[k]=true
		for k: String in ["limit","start_minute","end_minute"]:
			if not FormalLedgerState.valid_amount(p[k]): return false
		if p["limit"]<1 or p["end_minute"]<=p["start_minute"] or p["basis"] not in ["EXPLICIT_DEVELOPMENT_FIRM_FINANCE_AUTHORITY","HOST_ORGANIZATION_ROOT_AUTHORITY"] or not p["root_authority"] is String or (p["basis"]=="HOST_ORGANIZATION_ROOT_AUTHORITY" and p["root_authority"].is_empty()): return false
		if p["basis"]=="HOST_ORGANIZATION_ROOT_AUTHORITY" and p["operations"].size()!=1: return false
		seen[p["id"]]=true
	return true

static func policy(settings: Dictionary, firm: String) -> Dictionary:
	for p: Dictionary in settings.get("liquidity_policies",[]):
		if p["firm"]==firm: return p
	return {}

static func labor_policy(settings: Dictionary, actor: String) -> Dictionary:
	for p: Dictionary in settings.get("labor_response_policies",[]):
		if p["actor"]==actor: return p
	return {}
