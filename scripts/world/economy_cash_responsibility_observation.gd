extends RefCounted
## Detached decision observation. Every amount is reconstructed from original
## contracts, command prefix and Ledger receipts; this object is never saved.
const BASIS: String="CROSS_BUSINESS_CASH_PROTECTION_V1"
var e: EconomyR1Slice
var ledger: FormalLedgerState
var native: Dictionary
var commands: Dictionary={}
var txs: Dictionary={}
var releases: Dictionary={}
var rows: Array=[]
var blockers: Array=[]
var expected: Dictionary={}
var firm: String
var currency: String=FormalLedgerState.DENOMINATION
var at: int

func accepted(id: String) -> bool: return commands.get(id,{}).get("result",{}).get("accepted",false)
func actions(kind: String,key: String,value: String) -> Array:
	return commands.values().filter(func(c: Dictionary)->bool:return c["result"]["accepted"] and c["envelope"]["command"]["kind"]==kind and c["envelope"]["command"]["payload"].get(key)==value)
func paid(id: String,kind: String="",payer: String="") -> int:
	var total:=0
	for t: Dictionary in txs.values():
		if t["reference_id"]==id and (kind=="" or t["kind"]==kind) and (payer=="" or t["from_account_id"]==e._account(payer,t["denomination"])): total+=int(t["amount"])
	return total
func block(domain: String,id: String,reason: String,needs: String,known: Dictionary={}) -> void:
	blockers.append({"domain":domain,"id":id,"reason":reason,"needs":needs,"amount":null,"payer":null,"denomination":null,"known":known})
func row(domain: String,id: String,payer: String,payee: String,denomination: String,total: int,incurred: int,due: int,settled: int,released: int,held: int,future: int,stage: String,refs: Array) -> void:
	if payer!=firm and payee!=firm: return
	var debt:=maxi(0,incurred-settled)
	var extra_debt:=maxi(0,debt-held) if payer==firm else 0
	var extra_future:=maxi(0,future-maxi(0,held-debt)) if payer==firm else 0
	if held<0 or future<0 or released<0 or settled<0: block(domain,id,"NEGATIVE_CONTRACT_REMAINDER","Original payment/release boundary")
	if payer==firm and held>0: expected[id]={"account_id":e._account(payer,denomination),"amount":held}
	if payer==firm and denomination!=currency and extra_debt+extra_future>0: block(domain,id,"UNFUNDED_OTHER_CURRENCY_RESPONSIBILITY","Same-currency funding; no invented exchange rate")
	var payment_ids: Array=[]
	for t: Dictionary in txs.values():
		if t["reference_id"]==id or t["transaction_id"]==id: payment_ids.append(t["transaction_id"])
	rows.append({"domain":domain,"id":id,"payer":payer,"payee":payee,"denomination":denomination,"contract_amount":total,"incurred":incurred,"due":due,"paid":settled,"released":released,"reserved":held,"reservation_id":id if held>0 else "","unpaid":debt,"future_commitment":future,"unreserved_debt":extra_debt,"future_protection":extra_future,"distribution_impact":extra_debt+extra_future if denomination==currency else 0,"stage":stage,"sources":refs,"ledger_payments":payment_ids,"receivable_is_not_cash":payee==firm})

func evaluate(d: RefCounted,minute: int,saved: Dictionary,cursor: int,count: int) -> Dictionary:
	e=d.economy();ledger=d.market()._ledger;native=saved;firm=d.config["issuer"];at=minute
	var n:=0
	for id: String in native["commands"]:
		if n>=count: break
		commands[id]=native["commands"][id];n+=1
	var balance: int=ledger.balance(e._account(firm))
	for index: int in ledger._transactions.size():
		var t: Dictionary=ledger._transactions[index]
		if index<cursor: txs[t["transaction_id"]]=t
		else:
			if t["from_account_id"]==e._account(firm): balance+=int(t["amount"])
			if t["to_account_id"]==e._account(firm): balance-=int(t["amount"])
	for batch: Dictionary in ledger._batches.values():
		if batch["minute"]<=at and batch["transactions"].all(func(id: String)->bool:return txs.has(id)):
			for id: String in batch["releases"]: releases[id]=int(releases.get(id,0))+int(batch["releases"][id])
	_orders();_services();_leases();_equipment();_cargo();_wages_and_credit();_projects();_share_cash();_distributions()
	var locked:=0;var debts:=0;var future:=0;var wages:=0;var credit:=0;var rent:=0;var due_rent:=0;var services:=0;var projects:=0
	for r: Dictionary in rows:
		if r["payer"]!=firm or r["denomination"]!=currency: continue
		locked+=int(r["reserved"]);debts+=int(r["unreserved_debt"]);future+=int(r["future_protection"])
		if r["domain"]=="WAGE": wages+=int(r["unreserved_debt"])
		if r["domain"]=="CREDIT": credit+=int(r["unreserved_debt"])
		if r["domain"]=="LEASE":
			rent+=int(r["unreserved_debt"]);due_rent+=maxi(0,int(r["due"])-int(r["paid"])-int(r["reserved"]))
		if r["domain"]=="SERVICE": services+=int(r["unreserved_debt"])
		if r["domain"]=="CAPITAL_PROJECT": projects+=int(r["future_protection"])
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["domain"]+a["id"]<b["domain"]+b["id"])
	var sources: Array=rows.filter(func(r: Dictionary)->bool:return r["reserved"]>0 or r["distribution_impact"]>0 or r["released"]>0 or r["domain"] in ["SERVICE","LEASE","CAPITAL_TRADE","CAPITAL_FREIGHT","CARGO_PAYMENT"])
	blockers.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["domain"]+a["id"]+a["reason"]<b["domain"]+b["id"]+b["reason"])
	return {"basis":BASIS,"balance":balance,"reserved":locked,"available":balance-locked,"unpaid_wages":wages,"due_credit":credit,"rent_unpaid_unreserved":rent,"due_rent_unreserved":due_rent,"service_unpaid_unreserved":services,"future_project_budget":projects,"unreserved_debt":debts,"future_protection":future,"cash_floor":d.config["cash_floor"],"distributable":maxi(0,balance-locked-debts-future-int(d.config["cash_floor"])),"sources":sources,"unsupported":blockers,"reservation_sources":expected}

func _orders() -> void:
	for o: Dictionary in native["orders"].values():
		if not accepted(o["action_id"]) or firm not in [o["buyer"],o["seller"]]: continue
		var cancelled:=0;var refs: Array=[o["action_id"]]
		for c: Dictionary in actions("cancel","order_id",o["id"]):
			var id: String="cancel:"+str(c["envelope"]["command"]["action_id"])
			var fact: Dictionary=native.get("procurement_budget",{}).get("settlements",{}).get(id,{})
			if fact.is_empty(): block("ORDER",o["id"],"MISSING_CANCELLATION_RELEASE",id)
			else: cancelled=maxi(cancelled,int(fact["cancelled"]));refs.append(id)
		for disposition: Dictionary in native.get("cargo_fulfilment",{}).get("dispositions",{}).values():
			if disposition["terms"]["mode"]!="RELEASE" or actions("execute_cargo_disposition","disposition_id",disposition["id"]).is_empty(): continue
			var fact: Dictionary=native.get("procurement_budget",{}).get("settlements",{}).get("loss_release:"+str(disposition["id"]),{})
			if fact.get("order_id")==o["id"]: cancelled=maxi(cancelled,int(fact["cancelled"]));refs.append("loss_release:"+str(disposition["id"]))
		var unit: int=int(o["price"])+e._freight(o["route_legs"])
		var released: int=cancelled*unit;var total: int=int(o["quantity"])*unit
		var settled: int=paid(o["id"],"goods",o["buyer"])+paid(o["id"],"freight",o["buyer"])
		var held: int=total-released-int(releases.get(o["id"],0))
		row("ORDER",o["id"],o["buyer"],o["seller"],o["denomination"],total,settled,settled,settled,released,held,maxi(0,held),"OPEN" if held>0 else "SETTLED_OR_RELEASED",refs)

func _services() -> void:
	for c: Dictionary in native.get("service_market",{}).get("contracts",{}).values():
		if not accepted(c["action_id"]) or firm not in [c["payer"],c["provider"]]: continue
		var earned:=0;var ended:=false;var refs: Array=[c["action_id"]]
		for period: Dictionary in c["periods"]:
			if period["minute"]<=at:
				earned+=int(period["earned_delta"])
		# A same-minute withdrawal after billing does not retroactively finish
		# that billing interval. Use the original final period/release boundary.
		if c["kind"]=="STORAGE" and not c["periods"].is_empty():
			var last: Dictionary=c["periods"].back()
			var release_exists: bool=native.get("procurement_budget",{}).get("settlements",{}).has("service_release:end:"+str(c["id"]))
			ended=last["minute"]<=at and (last["to"]==c["end_minute"] or release_exists)
		if c["kind"]=="REPAIR" and c["repair_result_minute"]>=0 and c["repair_result_minute"]<=at: earned=int(c["total"])
		var cancelled:=not actions("cancel_service","service_id",c["id"]).is_empty()
		var released: int=int(c["total"])-earned if cancelled or ended else 0
		if released>0:
			var release_id: String="service_release:"+(str(actions("cancel_service","service_id",c["id"])[0]["envelope"]["command"]["action_id"]) if cancelled else "end:"+str(c["id"]))
			var fact: Dictionary=native.get("procurement_budget",{}).get("settlements",{}).get(release_id,{})
			if fact.get("order_id")!=c["id"] or fact.get("cancelled")!=released: block("SERVICE",c["id"],"MISSING_SERVICE_RELEASE_SOURCE",release_id)
			refs.append(release_id)
		var settled:=paid(c["id"],"service_fee",c["payer"])
		var held: int=int(c["total"])-settled-released
		var stage: String="CANCELLED" if cancelled else "COMPLETED_OR_EXPIRED_CUSTODY" if ended or earned==c["total"] else "WORKING_OR_WAITING" if c["started_minute"]>=0 and c["started_minute"]<=at else "ACCEPTED_NOT_STARTED"
		row("SERVICE",c["id"],c["payer"],c["provider"],e._service_market._offers[c["offer_id"]]["denomination"],c["total"],earned,earned,settled,released,held,int(c["total"])-earned-released,stage,refs)

func _leases() -> void:
	for c: Dictionary in native.get("lease_market",{}).get("contracts",{}).values():
		if not accepted(c["action_id"]) or firm not in [c["tenant"],c["lessor"]]: continue
		var accrued:=0;var due:=0
		for period: Dictionary in c["periods"]:
			if period["to"]<=at: accrued=int(period["cumulative_accrued"]);due=int(period["due"])
		var ended: bool=int(c["end_minute"])<=at or not actions("end_lease","lease_id",c["id"]).is_empty()
		if ended: due=accrued
		var held: int=0 if ended else int(c["first_reserve"])-int(releases.get(c["id"],0))
		var released: int=int(c["total"])-accrued if ended else 0
		var settled:=paid(c["id"],"lease_rent",c["tenant"])
		var stage: String="RETURNED" if not actions("return_lease","lease_id",c["id"]).is_empty() else "ENDED_OCCUPIED_OR_CANCELLED" if ended else "ACTIVE" if c["entered_minute"]>=0 and c["entered_minute"]<=at else "RESERVED"
		if ended:
			var fact: Dictionary=native.get("procurement_budget",{}).get("settlements",{}).get("lease_end:"+str(c["id"]),{})
			if fact.get("order_id")!=c["id"] or fact.get("cancelled")!=released: block("LEASE",c["id"],"MISSING_LEASE_END_RELEASE_SOURCE","lease_end:"+str(c["id"]))
		row("LEASE",c["id"],c["tenant"],c["lessor"],e._leases._offers[c["offer_id"]]["denomination"],c["total"],accrued,due,settled,released,held,int(c["total"])-accrued-released,stage,[c["action_id"],"FIXED_REMAINING_TERM_CASH_PROTECTION_NOT_ACCRUED_DEBT"])

func _equipment() -> void:
	var capital: Dictionary=native.get("capital_formation",{})
	for t: Dictionary in capital.get("resale",{}).get("trades",{}).values():
		if not accepted(t["action_id"]) or firm not in [t["buyer"],t["seller"]]: continue
		var o: Dictionary=capital["resale"]["offers"][t["offer_id"]]
		var settled:=paid(t["id"],"capital_equipment",t["buyer"])
		var cancelled: bool=accepted(t["cancel_action"])
		var held: int=0 if cancelled else int(o["price"])-settled
		row("CAPITAL_TRADE",t["id"],t["buyer"],t["seller"],o["denomination"],o["price"],settled,settled,settled,o["price"] if cancelled else 0,held,held,"CANCELLED" if cancelled else "DELIVERED" if held==0 else "ACCEPTED_SELLER_TITLE",[t["action_id"],o["id"]])
	for t: Dictionary in native.get("capital_transport",{}).values():
		if not accepted(t["action_id"]): continue
		var offer: Dictionary=e._capital_transport.offer(t["offer_id"])
		var settled:=paid(t["id"],"freight",t["payer"])
		var payees: Array=[]
		for leg: Dictionary in offer["legs"]: payees.append(leg["carrier"])
		row("CAPITAL_FREIGHT",t["id"],t["payer"],",".join(payees),offer["denomination"],t["total_fee"],settled,settled,settled,0,int(t["total_fee"])-settled,int(t["total_fee"])-settled,"SETTLED" if settled==t["total_fee"] else "COMMITTED_CARRIAGE",[t["action_id"],t["trade_id"],t["offer_id"]])

func _cargo() -> void:
	var cargo: Dictionary=native.get("cargo_fulfilment",{})
	for loss: Dictionary in cargo.get("losses",{}).values():
		var keeper: String=e._spec["sites"].get(loss["custodian"],{}).get("firm_id",loss["custodian"])
		if not commands.has(loss["id"]) or firm not in loss["parties"] and firm!=keeper and native["orders"].get(loss["order_id"],{}).get("seller")!=firm and native["orders"].get(loss["order_id"],{}).get("buyer")!=firm: continue
		# A confirmed loss of one's own uncommitted stock is a physical loss, not
		# an invented external payable. Third-party/service/contract losses differ.
		if loss["order_id"]=="" and not loss.has("service_id") and loss["owner"]==keeper and accepted(loss["id"]) and commands[loss["id"]]["result"].get("reason")=="LOSS_ADOPTED_CONTRACT_RETAINED": continue
		var resolved:=0;var explicitly_retained:=0
		for d: Dictionary in cargo.get("dispositions",{}).values():
			if d["loss_id"]==loss["id"] and d["terms"]["mode"] in ["REPLACE","RELEASE"] and not actions("execute_cargo_disposition","disposition_id",d["id"]).is_empty(): resolved+=int(d["terms"]["quantity"])
			if d["loss_id"]==loss["id"] and d["terms"]["mode"]=="KEEP" and not actions("execute_cargo_disposition","disposition_id",d["id"]).is_empty(): explicitly_retained=maxi(explicitly_retained,int(d["terms"]["quantity"]))
		# KEEP leaves the physical order open. Its original cash commitment is
		# still protected by ORDER; it does not invent an additional damages debt.
		if resolved+explicitly_retained<int(loss["quantity"]): block("CARGO_LOSS",loss["id"],"UNRESOLVED_CUSTODY_OR_SHORTFALL","Confirm custody and an executed agreed disposition; amount/liable party not inferred",{"order_id":loss["order_id"],"parties":loss["parties"],"unresolved_quantity":int(loss["quantity"])-resolved})
	for d: Dictionary in cargo.get("dispositions",{}).values():
		if not accepted(d["id"]) or firm not in d["parties"]: continue
		var agreed:=true
		for party: String in d["parties"]:
			var proof: Dictionary=d["confirmed"].get(party,{})
			if proof.is_empty() or proof["minute"]>at: agreed=false;continue
			var known: bool=commands.has(d["id"]) and proof["minute"]==d["minute"] and proof["actor"]==commands[d["id"]]["envelope"]["actor"]
			for action: Dictionary in actions("confirm_cargo_disposition","disposition_id",d["id"]):
				if action["envelope"]["actor"]==proof["actor"] and action["envelope"]["command"]["minute"]==proof["minute"]: known=true
			if not known: agreed=false
		if not agreed: block("CARGO_DISPOSITION",d["id"],"MISSING_COUNTERPARTY_CONSENT","Actual agreement on liable party, amount and release");continue
		var payments: Array=d["terms"].get("fees",[]) if d["terms"]["mode"]=="REPLACE" else [d["terms"]["payment"]] if d["terms"].has("payment") else []
		for index: int in payments.size():
			var p: Dictionary=payments[index]
			var payment_id: String=("cargo_fee:"+str(d["id"])+":"+str(index)) if d["terms"]["mode"]=="REPLACE" else "cargo_payment:"+str(d["id"])
			var settled: int=txs.get(payment_id,{}).get("amount",0)
			var future: int=maxi(0,int(p["amount"])-settled) if d["terms"]["mode"]=="REPLACE" else 0
			row("CARGO_PAYMENT",payment_id,p["payer"],p["recipient"],p["denomination"],p["amount"],settled if future>0 else p["amount"],settled if future>0 else p["amount"],settled,0,0,future,"AGREED" if settled<int(p["amount"]) else "PAID",[d["id"],d["loss_id"]])

func _wages_and_credit() -> void:
	for w: Dictionary in native["wages"].values():
		if w["employer"]==firm and int(w["work_day"])*1440<=at:
			row("WAGE",w["id"],firm,w["worker"],w["denomination"],w["amount"],w["amount"],w["amount"] if int(w["due_day"])*1440<=at else 0,paid(w["id"],"wage",firm),0,0,0,"INCURRED",[w["id"]])
	for l: Dictionary in native.get("credit",{}).get("loans",{}).values():
		if l["borrower"]!=firm or not accepted(l["action_id"]) or l["due_day"]>at/1440: continue
		var forgiven:=0
		for c: Dictionary in actions("forgive_loan","loan_id",l["id"]): forgiven+=int(c["envelope"]["command"]["payload"]["amount"])
		var total: int=int(l["principal"])+int(l["interest"])
		row("CREDIT",l["id"],firm,l["lender"],l["denomination"],total,total-forgiven,total-forgiven,paid(l["id"],"loan_repayment",firm),forgiven,0,0,"DUE_CREDIT",[l["action_id"]])
func _projects() -> void:
	for p: Dictionary in native.get("capital_formation",{}).get("projects",{}).values():
		if p["firm"]!=firm or not accepted(p["action_id"]) or (p["completed_minute"]>=0 and p["completed_minute"]<=at): continue
		var cancelled:=false;var committed:=0
		for c: Dictionary in native.get("capital_formation",{}).get("changes",{}).values():
			if c["kind"]=="investment_status" and c["status"]=="APPLIED" and c["effective_minute"]<=at and c["payload"]["project_id"]==p["id"] and c["payload"]["status"]=="CANCELLED": cancelled=true
		if cancelled: continue
		for id: String in p["orders"]:
			for r: Dictionary in rows:
				if r["domain"]=="ORDER" and r["id"]==id: committed+=int(r["contract_amount"])-int(r["released"])
		for w: Dictionary in p["work"]:
			var claim: Dictionary=native["wages"].get(w["id"],{})
			if not claim.is_empty() and int(claim["work_day"])*1440<=at: committed+=int(w["hours"])*int(claim["amount"])/int(claim["hours"])
		row("CAPITAL_PROJECT",p["id"],firm,"",currency,p["budget"],0,0,0,0,0,maxi(0,int(p["budget"])-committed),"EXPLICIT_REMAINING_MANAGER_BUDGET_NOT_DEBT",[p["action_id"]])
func _share_cash() -> void:
	# Issuers are not their own call-market participants. Keep other-company
	# investment commitments mapped if this observation is later reused.
	for b: Dictionary in native.get("assets",{}).get("call_market",{}).get("bids",{}).values():
		if b["buyer"]!=firm or not accepted(b["action_id"]): continue
		var closed: bool=(b["closed_minute"]>=0 and b["closed_minute"]<=at and (b["closed_action"]=="" or accepted(b["closed_action"])))
		var held: int=0 if closed else int(b["quantity"])*int(b["price"])-int(releases.get(b["id"],0))
		row("SHARE_BID",b["id"],firm,"",b["denomination"],int(b["quantity"])*int(b["price"]),0,0,paid(b["id"],"asset_trade",firm),0,held,held,"CLOSED" if closed else "OPEN",[b["action_id"]])
func _distributions() -> void:
	for p: Dictionary in native.get("assets",{}).get("distributions",{}).get("plans",{}).values():
		if p["issuer"]!=firm or not accepted(p["action_id"]): continue
		var settled:=paid(p["id"],"dividend",firm)
		var payees: Array=p["recipients"].keys();payees.sort()
		row("SHARE_DISTRIBUTION",p["id"],firm,",".join(payees),p["denomination"],p["total"],p["total"],p["total"] if p["due_minute"]<=at else 0,settled,0,int(p["total"])-settled,0,"REGISTERED_AND_RESERVED" if settled<int(p["total"]) else "PAID",[p["action_id"]])
