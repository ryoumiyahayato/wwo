class_name EconomyWindDown
extends RefCounted
## Voluntary operational closure. Decisions live in enterprise_changes/commands;
## money, claims, property, employment and contracts keep their original owners.
var _ref: WeakRef
var error: String = ""
func economy() -> RefCounted: return _ref.get_ref()
func bind(e: RefCounted) -> void: _ref=weakref(e)
func controls(firm: String) -> bool:
	for p: Dictionary in economy().config.get("wind_down",{}).get("authorities",[]):
		if p["firm"]==firm: return true
	return false
static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	if not settings.has("wind_down"): return true
	var v: Variant=settings["wind_down"]
	if not v is Dictionary or not FormalLedgerState.exact_fields(v,["basis","authorities","npc_policies"]) or v["basis"]!="EXPLICIT_DEVELOPMENT_VOLUNTARY_WIND_DOWN" or not v["authorities"] is Array or not v["npc_policies"] is Array or v["authorities"].size()>32 or v["npc_policies"].size()>16: return false
	var seen: Dictionary={}
	for p: Variant in v["authorities"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["id","firm","controller","operations","limit","start_minute","end_minute","root_authority","basis"]) or not p.get("id") is String or p["id"].is_empty() or seen.has(p["id"]) or not spec["firms"].has(p.get("firm")) or not p["controller"] is String or (p["controller"]!="HOST_SELECTED_PLAYER" and p["controller"]!=p["firm"] and not spec["actors"].has(p["controller"])) or not p["root_authority"] is String or p["basis"]!="EXPLICIT_DEVELOPMENT_VOLUNTARY_WIND_DOWN_AUTHORITY" or not p["operations"] is Array or p["operations"].is_empty(): return false
		var ops: Dictionary={}
		for op: Variant in p["operations"]:
			if op not in ["decide","dispose_inventory","settle","resume"] or ops.has(op): return false
			ops[op]=true
		for key: String in ["limit","start_minute","end_minute"]:
			if not FormalLedgerState.valid_amount(p[key]): return false
		if p["end_minute"]<=p["start_minute"] or p["limit"]<1: return false
		seen[p["id"]]=true
	seen.clear()
	for p: Variant in v["npc_policies"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["firm","repayment_order","max_payment_per_currency_day","cash_floor","review_days","basis"]) or not spec["firms"].has(p.get("firm")) or seen.has(p["firm"]) or p["basis"]!="EXPLICIT_DEVELOPMENT_SETTLEMENT_ORDER_NOT_LEGAL_PRIORITY" or not p["repayment_order"] is Array: return false
		var kinds: Dictionary={}
		for kind: Variant in p["repayment_order"]:
			if kind not in ["WAGE","RENT","LOAN"] or kinds.has(kind): return false
			kinds[kind]=true
		for key: String in ["max_payment_per_currency_day","cash_floor","review_days"]:
			if not FormalLedgerState.valid_amount(p[key]): return false
		if p["review_days"]<1 or p["review_days"]>30 or p["max_payment_per_currency_day"]<1: return false
		seen[p["firm"]]=true
	return true
func permission(actor: String, firm: String, op: String, amount: int=0) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if e.firm_manager_at(firm,now)!=actor: return {"ok":false,"reason":"CURRENT_WIND_DOWN_CONTROLLER_REQUIRED"}
	var organization: String=e._spec["firms"].get(firm,{}).get("host_organization_id","")
	if not organization.is_empty() and not e._world.organization_state.is_organization_active(organization): return {"ok":false,"reason":"WIND_DOWN_ORGANIZATION_INACTIVE"}
	for p: Dictionary in e.config.get("wind_down",{}).get("authorities",[]):
		if p["firm"]!=firm or p["controller"]!=actor or op not in p["operations"] or amount>p["limit"] or now<p["start_minute"] or now>=p["end_minute"]: continue
		var proof:={"ok":true,"actor":actor,"firm":firm,"operation":op,"amount":amount,"minute":now,"before_boundary":e.processing,"source":p.duplicate(true)}
		if not p["root_authority"].is_empty():
			var operation:="economy.wind_down."+op
			var scope:={"operation":operation,"target":firm,"place":e._place(e._primary_site(firm)),"category":"wind_down","amount":amount}
			var context: Dictionary=e._cargo_fulfilment._available_context(actor,firm,scope,p["root_authority"])
			var authorized: Dictionary=e._cargo_fulfilment._authorize(actor,firm,operation,firm,scope["place"],"wind_down",amount,{firm+"|"+operation+"|wind_down":context})
			if not authorized["ok"] or authorized["proof"].get("authority_id")!=p["root_authority"]: continue
			proof["root_proof"]=authorized["proof"]
		return proof
	return {"ok":false,"reason":"NO_SEPARATE_WIND_DOWN_"+op.to_upper()+"_AUTHORITY"}
func proof_valid(proof: Variant, actor: String, firm: String, op: String, amount: int, minute: int) -> bool:
	if not proof is Dictionary or not EconomySliceConfig._fields(proof,["ok","actor","firm","operation","amount","minute","before_boundary","source"],["root_proof"]) or proof["ok"]!=true or proof["actor"]!=actor or proof["firm"]!=firm or proof["operation"]!=op or proof["amount"]!=amount or proof["minute"]!=minute or not proof["before_boundary"] is bool: return false
	var e:=economy();var p: Variant=proof["source"]
	if not p is Dictionary or not e.config.get("wind_down",{}).get("authorities",[]).has(p) or p["controller"]!=actor or p["firm"]!=firm or op not in p["operations"] or amount>p["limit"] or minute<p["start_minute"] or minute>=p["end_minute"] or e.firm_manager_at(firm,maxi(0,minute-1) if proof["before_boundary"] else minute)!=actor: return false
	if p["root_authority"].is_empty(): return not proof.has("root_proof")
	var root:=proof.get("root_proof",{}) as Dictionary
	return e._cargo_fulfilment._saved_authority(root) and root.get("authority_id")==p["root_authority"] and root.get("actor")==actor and root.get("subject")==firm and root.get("operation")=="economy.wind_down."+op and root.get("target")==firm and root.get("place")==e._place(e._primary_site(firm)) and root.get("category")=="wind_down" and root.get("amount")==amount and root.get("minute")==minute
func selling(site: String) -> bool:
	var e:=economy();var firm: String=e._owner(site)
	return not e._firm_winding_down(firm) or not controls(firm) or permission(e.firm_manager_at(firm,e._world.game_clock.total_minutes()),firm,"dispose_inventory")["ok"]
func restriction(actor: String, kind: String, p: Dictionary) -> String:
	var e:=economy();var firm:=str(p.get("firm",actor))
	if kind=="set_job_offer": firm=e._spec["jobs"].get(p.get("job_id"),{}).get("employer","")
	if kind=="finance_investment": firm=e._capital.projects.get(p.get("project_id"),{}).get("firm","")
	if kind in ["capital_status","investment_status"]:
		firm=e._capital.assets.get(p.get("asset_id"),{}).get("firm","") if kind=="capital_status" else e._capital.projects.get(p.get("project_id"),{}).get("firm","")
	if kind=="set_service_offer": firm=e._service_market._facilities.get(e._service_market._offers.get(p.get("offer_id"),{}).get("facility_id"),{}).get("provider","")
	if not controls(firm) or not e._firm_winding_down(firm): return ""
	if (kind=="set_job_offer" and p.get("recruiting",false)) or kind in ["finance_investment","offer_credit","accept_credit","sell_shares","accept_share_order","pay_dividend","expand_scope","expand_configured_scope"] or (kind=="finance_firm" and p.get("operation")!="repay_loan") or (kind=="set_service_offer" and p.get("enabled",false)) or (kind=="investment_status" and p.get("status")=="ACTIVE") or (kind=="set_activity_enabled" and p.get("enabled",false)): return "VOLUNTARY_WIND_DOWN_STOPS_NEW_DISCRETIONARY_COMMITMENT"
	return ""
func obligations(firm: String) -> Array[Dictionary]:
	var e:=economy();var rows: Array[Dictionary]=[]
	var lenders: Array[String]=[]
	for id: String in e._open_wages_by_employer.get(firm,{}):
		var w:=e._wages[id] as Dictionary
		rows.append({"kind":"WAGE","reference":id,"creditor":w["worker"],"currency":w["denomination"],"remaining":w["remaining"],"due_day":w["due_day"],"state":"DUE" if w["due_day"]<=e.day else "NOT_DUE"})
	for l: Dictionary in e._credit.visible(firm,lenders,e._world.game_clock.total_minutes(),true)["loans"]:
		if l["borrower"]==firm and l["remaining"]>0: rows.append({"kind":"LOAN","reference":l["id"],"creditor":l["lender"],"currency":l["denomination"],"remaining":l["remaining"],"remaining_principal":l["remaining_principal"],"remaining_interest":l["remaining_interest"],"due_day":l["due_day"],"state":"DUE" if l["due_day"]<=e.day else "NOT_DUE"})
	for id: String in e._leases._active:
		var c:=e._leases.contracts[id] as Dictionary
		if c["tenant"]==firm or c["lessor"]==firm:
			rows.append({"kind":"RENT" if c["tenant"]==firm else "LESSOR_CONTRACT","reference":id,"creditor":c["lessor"],"currency":e._leases._offers[c["offer_id"]]["denomination"],"remaining":int(c["due"])-int(c["paid"]),"due_day":e.day,"state":c["state"],"direction":"PAYABLE" if c["tenant"]==firm else "RECEIVABLE_AND_OCCUPANCY_DUTY","return_reason":e._leases.return_reason(c) if c["tenant"]==firm and c["state"]=="ENDED_OCCUPIED" else ""})
	for id: String in e._service_market._active:
		var c:=e._service_market.contracts[id] as Dictionary
		if firm in [c["payer"],c["provider"]]: rows.append({"kind":"SERVICE_PAYABLE" if c["payer"]==firm else "SERVICE_DELIVERY","reference":id,"creditor":c["provider"],"currency":e._service_market._offers[c["offer_id"]]["denomination"],"remaining":int(c["earned"])-int(c["paid"]) if c["payer"]==firm else 0,"due_day":e.day,"state":c["status"]})
	for id: String in e._active_orders:
		var o:=e._orders[id] as Dictionary
		if firm in [o["buyer"],o["seller"]]: rows.append({"kind":"PURCHASE_COMMITMENT" if o["buyer"]==firm else "GOODS_DELIVERY","reference":id,"creditor":o["seller"],"currency":o["denomination"],"remaining":(int(o["pending"])+int(o["transit"]))*int(o["price"]) if o["buyer"]==firm else 0,"due_day":o["accepted_day"],"state":"RESERVED_NOT_UNSECURED_DEBT","pending":o["pending"],"transit":o["transit"]})
	for id: String in e._cargo_fulfilment._open_dispositions.get(firm,{}):
		var d:=e._cargo_fulfilment.dispositions[id] as Dictionary;var pay:=d["terms"].get("payment",{}) as Dictionary
		rows.append({"kind":d["terms"]["mode"],"reference":id,"creditor":pay.get("recipient",""),"currency":pay.get("denomination",""),"remaining":int(pay.get("amount",0)) if pay.get("payer")==firm and d["status"] in ["AGREED","PAYABLE"] else 0,"due_day":int(d["minute"])/1440,"state":d["status"]})
	for t: Dictionary in e._capital_transport.tasks.values():
		if t["stage"]=="DELIVERED": continue
		var offer: Dictionary=e._capital_transport.offer(t["offer_id"])
		for leg: Dictionary in offer["legs"]:
			if firm in [t["payer"],leg["carrier"]]: rows.append({"kind":"EQUIPMENT_CARRIAGE","reference":t["id"],"creditor":leg["carrier"],"currency":offer["denomination"],"remaining":t["total_fee"]-t["paid"] if firm==t["payer"] else 0,"due_day":t["minute"]/1440,"state":t["stage"]})
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["due_day"]<b["due_day"] if a["due_day"]!=b["due_day"] else a["reference"]<b["reference"])
	return rows
func request(actor: String,p: Dictionary,action: String) -> Dictionary:
	var e:=economy()
	if not FormalLedgerState.exact_fields(p,["firm","kind","reference","amount"]) or not p.get("firm") is String or not p.get("reference") is String or p.get("kind") not in ["WAGE","RENT"] or not FormalLedgerState.valid_amount(p.get("amount")) or p["amount"]<1 or not controls(p["firm"]) or not e._firm_winding_down(p["firm"]): return reject("INVALID_WIND_DOWN_PAYMENT")
	var proof:=permission(actor,p["firm"],"settle",p["amount"])
	if not proof["ok"]: return reject(proof["reason"])
	var currency:="";var remaining:=0;var creditor:=""
	if p["kind"]=="WAGE":
		var w:=e._wages.get(p["reference"],{}) as Dictionary
		if w.is_empty() or w["employer"]!=p["firm"] or w["due_day"]>e.day: return reject("NO_MATURED_OWN_WAGE_CLAIM")
		remaining=w["remaining"];currency=w["denomination"];creditor=w["worker"]
	else:
		var c:=e._leases.contracts.get(p["reference"],{}) as Dictionary
		if c.is_empty() or c["tenant"]!=p["firm"]: return reject("NO_OWN_RENT_CLAIM")
		remaining=int(c["due"])-int(c["paid"]);currency=e._leases._offers[c["offer_id"]]["denomination"];creditor=c["lessor"]
	if p["amount"]>remaining or p["amount"]>e._world.ledger_state.available_balance(e._account(p["firm"],currency)): return reject("PAYMENT_EXCEEDS_CLAIM_OR_AVAILABLE_CASH")
	var receipt:=""
	if p["kind"]=="WAGE":
		receipt="r1:wage:"+str(p["reference"])+":"+str(e._wages[p["reference"]]["paid"])
		if not e._pay_wage_claim(p["reference"],p["amount"]): return reject("WAGE_PAYMENT_FAILED")
	else:
		var c:=e._leases.contracts[p["reference"]] as Dictionary;var before:=int(c["paid"])
		e._leases._pay(c,e._world.game_clock.total_minutes(),p["amount"],false);e._leases._index(c)
		if int(c["paid"])-before!=p["amount"]: return reject("RENT_PAYMENT_FAILED")
		receipt=c["payments"].back()["id"]
	return {"accepted":true,"reason":"ORIGINAL_DEBT_PARTIALLY_OR_FULLY_PAID","permission":proof,"transaction_id":receipt,"amount":p["amount"],"currency":currency,"creditor":creditor}
func npc_decisions() -> void:
	var e:=economy()
	for p: Dictionary in e.config.get("wind_down",{}).get("npc_policies",[]):
		var firm: String=p["firm"]
		if not e._firm_winding_down(firm) or e.firm_manager_at(firm,e._world.game_clock.total_minutes())!=firm or e.day%int(p["review_days"])!=0: continue
		var rows:=obligations(firm)
		var spent: Dictionary={}
		for tx: Dictionary in e._world.ledger_state.own_transactions(firm,e.day*1440,(e.day+1)*1440):
			if tx["from_account_id"]==e._account(firm,tx["denomination"]) and tx["kind"] in ["wage","lease_rent","loan_repayment"]: spent[tx["denomination"]]=int(spent.get(tx["denomination"],0))+int(tx["amount"])
		var handled:=false
		for kind: String in p["repayment_order"]:
			for row: Dictionary in rows:
				if row["kind"]!=kind or row["remaining"]<=0 or row["due_day"]>e.day: continue
				var cash: int=e._world.ledger_state.available_balance(e._account(firm,row["currency"]))
				var amount:=mini(int(row["remaining"]),mini(maxi(0,int(p["max_payment_per_currency_day"])-int(spent.get(row["currency"],0))),maxi(0,cash-int(p["cash_floor"]))))
				if amount<1: continue
				if not permission(firm,firm,"settle",amount)["ok"]: continue
				if kind=="LOAN":
					if not e._firm_credit_permission(firm,firm,"repay_loan",{"loan_id":row["reference"],"amount":amount},true)["ok"]: continue
					e._npc_submit(firm,"repay_loan",{"loan_id":row["reference"],"amount":amount},"wind_down:"+row["reference"],{"purpose":p["basis"],"repayment_order":p["repayment_order"]})
				else: e._npc_submit(firm,"pay_enterprise_debt",{"firm":firm,"kind":kind,"reference":row["reference"],"amount":amount},"wind_down:"+row["reference"],{"purpose":p["basis"],"repayment_order":p["repayment_order"]})
				handled=true;break
			if handled: break
		# No repeated failed close requests: only submit after the real keeper checks pass.
		for site: String in e._spec["firms"][firm]["sites"]:
			if not e.site_closed(site) and e._site_close_reason(site).is_empty(): e._npc_submit(firm,"close_site",{"firm":firm,"site_id":site},site,{"purpose":"VOLUNTARY_EMPTY_SITE_CLOSE"})
		if e._firm_finish_reason(firm).is_empty(): e._npc_submit(firm,"finish_firm",{"firm":firm},firm,{"purpose":"LIMITED_OPERATIONAL_CLOSE_IDENTITY_RETAINED"})
func view(actor: String,firm: String,amount: int=1) -> Dictionary:
	var e:=economy()
	if not controls(firm) or not e._manager(actor,firm): return {}
	var rows:=obligations(firm);var sales: Array[Dictionary]=[];var staff: Array[Dictionary]=[];var actions: Array[Dictionary]=[]
	var winding: bool=e._firm_winding_down(firm)
	for site: String in e._spec["firms"][firm]["sites"]:
		for good: String in e._goods:
			var q: int=e.capital_free_goods(site,good)
			if q>0: sales.append({"site_id":site,"good":good,"free_quantity":q,"unit_price":e._price(site,good),"currency":e._sale_currency(firm),"can_offer":e._site_accepting(site) and selling(site),"cost_basis":"ORIGINAL_SOURCE_LOTS_NOT_CASH"})
	for worker: String in e._contracts:
		for c: Dictionary in e._contract_rows(e._contracts[worker]):
			if e._job(c["job"])["employer"]==firm: staff.append({"worker":worker,"job_id":c["job"],"workers":c["workers"],"termination":"WORKER_OWN_LAWFUL_LEAVE_REQUIRED_WAGES_RETAINED"})
	for op: String in ["decide","resume"]:
		var proof:=permission(actor,firm,op)
		actions.append({"label":"申请自愿经营收尾" if op=="decide" else "申请恢复未来经营","kind":"wind_down_firm" if op=="decide" else "set_firm_operating","payload":{"firm":firm} if op=="decide" else {"firm":firm,"operating":true},"can_execute":proof["ok"] and not e.firm_finished(firm) and (not winding if op=="decide" else winding),"reason":proof.get("reason","")})
	if winding:
		for row: Dictionary in rows:
			if row["kind"] not in ["WAGE","RENT"] or row["remaining"]<1 or row["due_day"]>e.day: continue
			var n:=mini(amount,int(row["remaining"]));var proof:=permission(actor,firm,"settle",n)
			actions.append({"label":"偿付 "+row["kind"]+" "+str(n)+" · "+row["reference"],"kind":"pay_enterprise_debt","payload":{"firm":firm,"kind":row["kind"],"reference":row["reference"],"amount":n},"can_execute":proof["ok"] and n<=e._world.ledger_state.available_balance(e._account(firm,row["currency"])),"reason":proof.get("reason",str(row["creditor"])+" · 尚欠 "+str(row["remaining"])+" "+str(row["currency"]))})
	return {"enabled":true,"phase":"OPERATIONS_CLOSED_IDENTITY_RETAINED" if e.firm_finished(firm) else "SETTLEMENT_PENDING" if winding and not e._firm_finish_reason(firm).is_empty() else "WIND_DOWN" if winding else "ACTIVE" if e._firm_operating(firm) else "PAUSED","finish_reason":e._firm_finish_reason(firm),"obligations":rows,"saleable_stock":sales,"employment":staff,"equipment_disposal":"EXPLICIT_MOVABLE_TYPES_WORKED_LOCAL_HANDOVER_ONLY" if e.config.has("capital_resale") else "NO_CONFIGURED_EQUIPMENT_DISPOSAL","new_commitments":"NO_NEW_PROCUREMENT_INVESTMENT_HIRING_SERVICES_LEASES_OR_PUBLICITY" if winding else "ORIGINAL_DOMAIN_RULES","retained_actions":["EXISTING_FULFILMENT","AUTHORIZED_FREE_STOCK_SALE","ORIGINAL_DEBT_PAYMENT","OWN_LAWFUL_LEAVE","CONTRACT_END_OR_RETURN","CAPITAL_PAUSE_OR_CANCEL"],"priority_basis":"EXPLICIT_DEVELOPMENT_ORDER_ONLY_NO_LEGAL_PRIORITY","actions":actions}
func winding_at(firm: String, minute: int) -> bool:
	var last:=-1;var result:=false
	for row: Dictionary in economy()._enterprise_changes.values():
		if row["firm"]!=firm or row["status"]!="APPLIED" or row["kind"] not in ["wind_down_firm","set_firm_operating"] or row["effective_minute"]>minute or (row["kind"]=="set_firm_operating" and not row["payload"]["operating"]): continue
		if row["effective_minute"]>=last: last=row["effective_minute"];result=row["kind"]=="wind_down_firm"
	return result
func validate(saved: Dictionary) -> bool:
	var e:=economy();var receipts: Dictionary={}
	for entry: Dictionary in saved["commands"].values():
		var command:=entry["envelope"]["command"] as Dictionary;var result:=entry["result"] as Dictionary
		if command["kind"] not in ["pay_enterprise_debt","pay_lease"] or not result.get("accepted",false): continue
		var p: Dictionary=command["payload"].duplicate(true);var actor: String=entry["envelope"]["actor"]
		if command["kind"]=="pay_lease":
			var lease:=e._leases.contracts.get(p.get("lease_id"),{}) as Dictionary
			if lease.is_empty(): return fail("Rent payment has no original lease")
			if not controls(lease["tenant"]) or (not winding_at(lease["tenant"],command["minute"]) and not winding_at(lease["tenant"],maxi(0,int(command["minute"])-1))): continue
			p={"firm":lease["tenant"],"kind":"RENT","reference":lease["id"],"amount":result.get("amount",-1)}
		if not FormalLedgerState.exact_fields(p,["firm","kind","reference","amount"]) or not controls(str(p.get("firm",""))) or not FormalLedgerState.valid_amount(p.get("amount")) or p["amount"]<1 or not proof_valid(result.get("permission"),actor,p["firm"],"settle",p["amount"],command["minute"]) or result.get("amount")!=p["amount"]: return fail("Invalid original wind-down payment authorization")
		if not winding_at(p["firm"],command["minute"]) and not winding_at(p["firm"],maxi(0,int(command["minute"])-1)): return fail("Debt settlement has no actual voluntary closure")
		if not result.get("transaction_id") is String or receipts.has(result["transaction_id"]): return fail("Duplicate wind-down payment adoption")
		receipts[result["transaction_id"]]=true
		var creditor:="";var currency:=""
		if p["kind"]=="WAGE":
			var w:=saved["wages"].get(p["reference"],{}) as Dictionary
			if w.get("employer")!=p["firm"] or int(w.get("due_day",FormalLedgerState.MAX_AMOUNT))*1440>command["minute"]: return fail("Wind-down wage lacks matured original claim")
			creditor=w["worker"];currency=w["denomination"]
		elif p["kind"]=="RENT":
			var c:=e._leases.contracts.get(p["reference"],{}) as Dictionary
			if c.get("tenant")!=p["firm"]: return fail("Wind-down rent lacks original lease")
			creditor=c["lessor"];currency=e._leases._offers[c["offer_id"]]["denomination"]
		else: return fail("Unsupported wind-down claim")
		var tx: Dictionary=e._world.ledger_state.transaction(result.get("transaction_id",""))
		if tx.get("reference_id")!=p["reference"] or tx.get("amount")!=p["amount"] or tx.get("effective_minute")!=command["minute"] or tx.get("from_account_id")!=e._account(p["firm"],currency) or tx.get("to_account_id")!=e._account(creditor,currency) or tx.get("kind")!=("wage" if p["kind"]=="WAGE" else "lease_rent") or result.get("creditor")!=creditor or result.get("currency")!=currency: return fail("Wind-down payment differs from real Ledger receipt")
	return true
func reject(reason: String) -> Dictionary: return {"accepted":false,"reason":reason}
func fail(reason: String) -> bool: error=reason;return false

