extends RefCounted
## AssetMarket-owned cash distribution obligations. No share or cash balances.
const ACTIONS: Array[String]=["declare_share_distribution","settle_share_distribution"]
const CashObservation=preload("res://scripts/world/economy_cash_responsibility_observation.gd")
var owner_ref: WeakRef
var economy_ref: WeakRef
var config: Dictionary={}
var plans: Dictionary={}
var error: String=""
func market() -> EconomyAssetMarket: return owner_ref.get_ref() as EconomyAssetMarket
func economy() -> EconomyR1Slice: return economy_ref.get_ref() as EconomyR1Slice
func enabled() -> bool: return not config.is_empty()
func bind(owner: RefCounted,settings: Dictionary,e: RefCounted) -> void:
	owner_ref=weakref(owner);economy_ref=weakref(e) if e!=null else null
	config=settings.get("equity_distribution",{}).duplicate(true)
static func valid_configuration(settings: Dictionary,spec: Dictionary) -> bool:
	if not settings.has("equity_distribution"): return true
	var c: Variant=settings["equity_distribution"]
	if not c is Dictionary or not FormalLedgerState.exact_fields(c,["basis","asset_id","issuer","controller","authority_id","max_total","max_per_share","cash_floor","delay_days","start","end","consenting_holders"]): return false
	if c["basis"]!="GENERATED_SIMULATION_ASSUMPTION_SHAREHOLDER_CASH_DISTRIBUTION" or not settings.has("equity_primary") or c["issuer"]!=settings["equity_primary"]["issuer"] or c["asset_id"]!=settings["equity_primary"]["asset_id"] or c["controller"]!=settings["equity_primary"]["controller"] or c["consenting_holders"]!=settings["equity_primary"]["consenting_holders"] or not spec["firms"].has(c["issuer"]): return false
	for k: String in ["max_total","max_per_share","cash_floor","delay_days","start","end"]:
		if not FormalLedgerState.valid_amount(c[k]): return false
	return c["max_total"]>0 and c["max_total"]<=10000 and c["max_per_share"]>0 and c["max_per_share"]<=10 and c["delay_days"]>=1 and c["delay_days"]<=7 and c["end"]>c["start"] and c["end"]<=90*1440 and c["authority_id"] is String and c["authority_id"].begins_with("authority:development:distribution:")
func authority(actor: String,total: int) -> Dictionary:
	var e:=economy()
	var representative: String=e.firm_manager_at(actor,e._world.game_clock.total_minutes()) if actor==config["issuer"] and market().corporate.enabled() else actor
	if representative!=config["controller"] or not e._manager_at(representative,config["issuer"],e._world.game_clock.total_minutes()) or (actor==config["issuer"] and (representative==e._world.player_state.player_id() or not market().corporate.managed(e._world.game_clock.total_minutes()))): return {}
	var scope: Dictionary={"operation":"economy.equity.distribute","target":config["issuer"],"place":e._place(e._primary_site(config["issuer"])),"category":config["asset_id"],"amount":total}
	var context:=e._cargo_fulfilment._available_context(representative,config["issuer"],scope,config["authority_id"])
	var r:=e._cargo_fulfilment._authorize(representative,config["issuer"],scope["operation"],scope["target"],scope["place"],scope["category"],total,{str(config["issuer"])+"|economy.equity.distribute|"+str(config["asset_id"]):context})
	return r.get("proof",{}) if r.get("ok",false) else {}
func context() -> Dictionary:
	var e:=economy()
	return {"orders":e._orders,"wages":e._wages,"commands":e._commands,"capital_formation":e._capital.snapshot(),"credit":e._credit.snapshot(),"service_market":e._service_market.snapshot(),"lease_market":e._leases.snapshot(),"capital_transport":e._capital_transport.tasks,"procurement_budget":e._budgets.snapshot(),"cargo_fulfilment":e._cargo_fulfilment.snapshot(),"assets":market().snapshot()}
func protection(at: int,native: Dictionary,cursor: int,count: int) -> Dictionary:
	return CashObservation.new().evaluate(self,at,native,cursor,count)
func legacy_protection(at: int,native: Dictionary,cursor: int,count: int) -> Dictionary:
	var e:=economy();var ledger:=market()._ledger;var account:=e._account(config["issuer"])
	var txs: Array=ledger._transactions;var prefix: Dictionary={};var n:=0
	for id: String in native["commands"]:
		if n>=count: break
		prefix[id]=native["commands"][id];n+=1
	var balance: int=ledger.balance(account);var paid: Dictionary={};var repaid: Dictionary={};var paid_wages: Dictionary={}
	for j: int in txs.size():
		var t: Dictionary=txs[j]
		if j>=cursor:
			if t["to_account_id"]==account: balance-=int(t["amount"])
			if t["from_account_id"]==account: balance+=int(t["amount"])
		elif t["from_account_id"]==account:
			var map: Dictionary=paid_wages if t["kind"]=="wage" else repaid if t["kind"]=="loan_repayment" else paid
			map[t["reference_id"]]=int(map.get(t["reference_id"],0))+int(t["amount"])
	var rows: Array=[];var reserved:=0;var wages:=0;var loans:=0;var future:=0;var unsupported: Array=[]
	for id: String in native["orders"]:
		var o: Dictionary=native["orders"][id]
		if o["buyer"]!=config["issuer"] or not prefix.has(o["action_id"]): continue
		var released:=0
		for cmd: Dictionary in prefix.values():
			if cmd["result"]["accepted"] and cmd["envelope"]["command"]["kind"]=="cancel" and cmd["envelope"]["command"]["payload"].get("order_id")==id: unsupported.append("CANCELLED_ORDER_HISTORY:"+id)
		var amount: int=int(o["quantity"])*(int(o["price"])+e._freight(o["route_legs"]))-int(paid.get(id,0))-released
		if amount>0:
			reserved+=amount;rows.append({"kind":"ORDER_AND_BUDGET","id":id,"amount":amount,"covered_by_reservation":amount})
	for w: Dictionary in native["wages"].values():
		if w["employer"]!=config["issuer"] or w["denomination"]!=FormalLedgerState.DENOMINATION or int(w["work_day"])*1440>at: continue
		var amount: int=int(w["amount"])-int(paid_wages.get(w["id"],0))
		if amount>0: wages+=amount;rows.append({"kind":"UNPAID_WAGE","id":w["id"],"amount":amount,"covered_by_reservation":0})
	for l: Dictionary in native.get("credit",{}).get("loans",{}).values():
		if l["borrower"]!=config["issuer"] or l["denomination"]!=FormalLedgerState.DENOMINATION or not prefix.has(l["action_id"]) or l["due_day"]>at/1440: continue
		var forgiven:=0
		for cmd: Dictionary in prefix.values():
			if cmd["result"]["accepted"] and cmd["envelope"]["command"]["kind"]=="forgive_loan" and cmd["envelope"]["command"]["payload"].get("loan_id")==l["id"]: forgiven+=int(cmd["envelope"]["command"]["payload"]["amount"])
		var amount: int=maxi(0,int(l["principal"])+int(l["interest"])-int(repaid.get(l["id"],0))-forgiven)
		if amount>0: loans+=amount;rows.append({"kind":"DUE_CREDIT","id":l["id"],"amount":amount,"covered_by_reservation":0})
	for p: Dictionary in native.get("capital_formation",{}).get("projects",{}).values():
		if p["firm"]!=config["issuer"] or not prefix.has(p["action_id"]) or (p["completed_minute"]>=0 and p["completed_minute"]<=at): continue
		var cancelled:=false;var committed:=0
		for change: Dictionary in native.get("capital_formation",{}).get("changes",{}).values():
			if change["kind"]=="investment_status" and change["status"]=="APPLIED" and change["effective_minute"]<=at and change["payload"]["project_id"]==p["id"] and change["payload"]["status"]=="CANCELLED": cancelled=true
		if cancelled: continue
		for id: String in p["orders"]:
			var o: Dictionary=native["orders"][id]
			if prefix.has(o["action_id"]): committed+=int(o["quantity"])*(int(o["price"])+e._freight(o["route_legs"]))
		for w: Dictionary in p["work"]:
			var claim: Dictionary=native["wages"].get(w["id"],{})
			if not claim.is_empty() and int(claim["work_day"])*1440<=at: committed+=int(w["hours"])*int(claim["amount"])/int(claim["hours"])
		var amount: int=maxi(0,int(p["budget"])-committed)
		future+=amount;rows.append({"kind":"UNCOMMITTED_PROJECT_BUDGET","id":p["id"],"amount":amount,"covered_by_reservation":0})
	# Claims for ordinary purchases share their existing order reservation. Other
	# contract families are conservatively blocked until their historical release
	# boundaries can be reconciled, rather than being counted as free funds.
	for cmd: Dictionary in prefix.values():
		if cmd["result"]["accepted"] and cmd["envelope"]["actor"] in [config["issuer"],config["controller"]] and cmd["envelope"]["command"]["kind"] in ["request_lease","request_service","commission_capital_transport","accept_capital_offer","execute_cargo_disposition"]: unsupported.append("COMPLEX_CONTRACT_HISTORY:"+str(cmd["envelope"]["command"]["action_id"]))
	for family: String in ["service_market","lease_market"]:
		for contract: Dictionary in native.get(family,{}).get("contracts",{}).values():
			var payer: String=contract["payer"] if family=="service_market" else contract["tenant"]
			if payer==config["issuer"] and prefix.has(contract["action_id"]): unsupported.append("CONTRACT_RELEASE_HISTORY_NOT_SUPPORTED:"+str(contract["id"]))
	for task: Dictionary in native.get("capital_transport",{}).values():
		if task["payer"]==config["issuer"] and prefix.has(task["action_id"]): unsupported.append("EQUIPMENT_CARRIAGE_HISTORY_NOT_SUPPORTED:"+str(task["id"]))
	unsupported.sort()
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return str(a["kind"])+str(a["id"])<str(b["kind"])+str(b["id"]))
	return {"balance":balance,"reserved":reserved,"available":balance-reserved,"unpaid_wages":wages,"due_credit":loans,"future_project_budget":future,"cash_floor":config["cash_floor"],"distributable":maxi(0,balance-reserved-wages-loans-future-int(config["cash_floor"])),"sources":rows,"unsupported":unsupported}
func declare(actor: String,p: Dictionary,at: int,action: String) -> Dictionary:
	if not enabled() or not FormalLedgerState.exact_fields(p,["asset_id","per_share","denomination"]) or p["asset_id"]!=config["asset_id"] or p["denomination"]!=FormalLedgerState.DENOMINATION or not FormalLedgerState.valid_amount(p["per_share"]) or p["per_share"]<1 or p["per_share"]>config["max_per_share"]: return reject("INVALID_CASH_DISTRIBUTION_TERMS")
	if not plans.is_empty(): return reject("DISTRIBUTION_PROGRAM_ALREADY_DECIDED")
	if at%1440!=0 or at<config["start"] or at>=config["end"] or economy().phase!="READY": return reject("DISTRIBUTION_REQUIRES_READY_DAILY_REGISTRATION_BOUNDARY")
	var a: Dictionary=market()._assets[config["asset_id"]];var total: int=int(a["total_shares"])*int(p["per_share"])
	if total>config["max_total"]: return reject("DISTRIBUTION_AUTHORIZED_AMOUNT_EXCEEDED")
	var proof:=authority(actor,total)
	if proof.is_empty(): return reject("NO_SEPARATE_CASH_DISTRIBUTION_AUTHORITY")
	if economy()._firm_winding_down(config["issuer"]) or economy().firm_finished(config["issuer"]): return reject("DISTRIBUTION_ISSUER_NOT_OPERATING")
	var cursor: int=market()._ledger._transactions.size();var count: int=economy()._commands.size()
	var guard:=protection(at,context(),cursor,count)
	var actual: Dictionary={}
	for id: String in market()._ledger._reservations:
		var r: Dictionary=market()._ledger._reservations[id]
		if r["account_id"]==economy()._account(config["issuer"]): actual[id]=r
	var expected: Dictionary={}
	for id: String in guard["reservation_sources"]:
		if guard["reservation_sources"][id]["account_id"]==economy()._account(config["issuer"]): expected[id]=guard["reservation_sources"][id]
	if actual!=expected: guard["unsupported"].append({"domain":"LEDGER","id":economy()._account(config["issuer"]),"reason":"CONTRACT_RESERVATION_SOURCE_MISMATCH","needs":"Reconcile actual reservation IDs with original contracts","actual":actual,"expected":expected})
	if not guard["unsupported"].is_empty(): return {"accepted":false,"reason":"DISTRIBUTION_UNRECONCILED_CONTRACT_PROTECTION","protection":guard}
	if total>guard["distributable"]: return {"accepted":false,"reason":"DISTRIBUTION_EXCEEDS_PROTECTED_CASH","protection":guard}
	var recipients: Dictionary={};var holders: Array=a["holders"].keys();holders.sort()
	for holder: String in holders:
		var q: int=a["holders"][holder]
		if q==0: continue
		var account:=market()._ledger.owner_account(holder,p["denomination"])
		if holder==config["issuer"] or account.is_empty(): return reject("DISTRIBUTION_RECIPIENT_ACCOUNT_OR_SELF_HOLDING")
		recipients[holder]={"shares":q,"account_id":account,"amount":q*int(p["per_share"])}
	var id: String="share_distribution:"+action
	if not market()._ledger.reserve(id,economy()._account(config["issuer"]),total): return reject("DISTRIBUTION_REAL_CASH_RESERVATION_FAILED")
	plans[id]={"id":id,"asset_id":p["asset_id"],"issuer":config["issuer"],"actor":actor,"action_id":action,"record_minute":at,"command_cursor":count,"ledger_cursor":cursor,"issued_shares":a["total_shares"],"per_share":p["per_share"],"denomination":p["denomination"],"source_account":economy()._account(config["issuer"]),"recipients":recipients,"total":total,"protection":guard,"authority":proof,"due_minute":at+int(config["delay_days"])*1440,"status":"RESERVED","paid_minute":-1,"payment_action":"","payment_batch":""}
	for participant: Dictionary in market().call_market.config["participants"]: economy()._messages.append(notice(plans[id],participant["actor"]))
	return {"accepted":true,"reason":"REGISTERED_SHAREHOLDERS_AND_FULL_CASH_RESERVED","distribution_id":id,"total":total,"record_minute":at}
func notice(r: Dictionary,actor: String) -> Dictionary:
	return {"id":"distribution_notice:"+str(r["id"])+":"+actor,"actor":actor,"kind":"share_distribution","candidate":r["id"],"observed_day":int(r["record_minute"])/1440,"delivery_day":int(r["record_minute"])/1440+1}
func message_valid(m: Dictionary) -> bool:
	return enabled() and plans.has(m.get("candidate")) and not market().call_market.participant(m.get("actor","")).is_empty() and m==notice(plans[m["candidate"]],m["actor"])
func legs(r: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for holder: String in r["recipients"]:
		var rec: Dictionary=r["recipients"][holder]
		result.append({"transaction_id":"share_distribution_payment:"+str(r["id"])+":"+holder,"from_account_id":r["source_account"],"to_account_id":rec["account_id"],"amount":rec["amount"],"kind":"dividend","reference_id":r["id"]})
	return result
func settle(actor: String,p: Dictionary,at: int,action: String) -> Dictionary:
	var r: Dictionary=plans.get(p.get("distribution_id",""),{})
	if not enabled() or not FormalLedgerState.exact_fields(p,["distribution_id"]) or actor!=config["issuer"] or economy().phase!="EQUITY_CLEARING" or r.is_empty() or r["status"]!="RESERVED" or at<r["due_minute"] or at%1440!=0: return reject("NO_UNPAID_DISTRIBUTION_AT_PAYMENT_BOUNDARY")
	var batch: String="share_distribution_batch:"+action
	if not market()._ledger.batch_payment(batch,legs(r),at,{str(r["id"]):r["total"]}): return reject("DISTRIBUTION_PAYMENT_WAITING_OR_INVALID_ACCOUNT")
	r["status"]="PAID";r["paid_minute"]=at;r["payment_action"]=action;r["payment_batch"]=batch
	return {"accepted":true,"reason":"REGISTERED_SHAREHOLDERS_ATOMICALLY_PAID","distribution_id":r["id"],"total":r["total"],"payment_batch":batch}
func clear_day() -> void:
	if not enabled(): return
	for r: Dictionary in plans.values():
		if r["status"]=="RESERVED" and economy()._world.game_clock.total_minutes()>=r["due_minute"]: economy()._npc_submit(config["issuer"],"settle_share_distribution",{"distribution_id":r["id"]},"distribution_due:"+str(r["id"]),{"basis":"EXECUTE_ORIGINAL_REGISTERED_FULLY_FUNDED_OBLIGATION"})
func reservations() -> Dictionary:
	var result: Dictionary={}
	for r: Dictionary in plans.values():
		if r["status"]=="RESERVED": result[r["id"]]={"account_id":r["source_account"],"amount":r["total"]}
	return result
func snapshot() -> Dictionary: return {"format":"SHAREHOLDER_CASH_DISTRIBUTION_V1","plans":plans.duplicate(true)}
func prepare(value: Variant) -> bool:
	if not enabled(): return value==null
	if not value is Dictionary or not FormalLedgerState.exact_fields(value,["format","plans"]) or value["format"]!="SHAREHOLDER_CASH_DISTRIBUTION_V1" or not value["plans"] is Dictionary or value["plans"].size()>1: return fail("Invalid cash distribution containers")
	plans=value["plans"].duplicate(true)
	for r: Variant in plans.values():
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","asset_id","issuer","actor","action_id","record_minute","command_cursor","ledger_cursor","issued_shares","per_share","denomination","source_account","recipients","total","protection","authority","due_minute","status","paid_minute","payment_action","payment_batch"]): return fail("Malformed cash distribution")
		for field: String in ["id","asset_id","issuer","actor","action_id","denomination","source_account","status","payment_action","payment_batch"]:
			if not r[field] is String: return fail("Invalid distribution identity")
		for field: String in ["record_minute","command_cursor","ledger_cursor","issued_shares","per_share","total","due_minute"]:
			if not FormalLedgerState.valid_amount(r[field]): return fail("Invalid distribution amount or time")
		if not r["recipients"] is Dictionary or not r["protection"] is Dictionary or not r["authority"] is Dictionary or not r["paid_minute"] is int or r["status"] not in ["RESERVED","PAID"] or plans.get(r["id"])!=r or r["total"]<1 or r["total"]>config["max_total"]: return fail("Invalid distribution obligation")
		for holder: Variant in r["recipients"]:
			var rec: Variant=r["recipients"][holder]
			if not holder is String or not rec is Dictionary or not FormalLedgerState.exact_fields(rec,["shares","account_id","amount"]) or not FormalLedgerState.valid_amount(rec["shares"]) or not FormalLedgerState.valid_amount(rec["amount"]) or rec["shares"]<1 or not rec["account_id"] is String: return fail("Malformed registered distribution recipient")
	return true
func registration_valid(action: String,asset: Dictionary) -> bool:
	var r: Dictionary=plans.get("share_distribution:"+action,{})
	if r.is_empty() or r["issued_shares"]!=asset["total_shares"]: return fail("Distribution issued total does not match registration ownership")
	var recipients: Dictionary={}
	var holders: Array=asset["holders"].keys();holders.sort()
	for holder: String in holders:
		var q: int=asset["holders"][holder]
		if q>0: recipients[holder]={"shares":q,"account_id":market()._ledger.owner_account(holder,r["denomination"]),"amount":q*int(r["per_share"])}
	return recipients==r["recipients"] or fail("Distribution registered holders or accounts conflict with ownership history")
func validate(value: Variant,commands: Dictionary,minute: int,native: Dictionary) -> bool:
	if not prepare(value): return false
	if not enabled(): return true
	var seen: Dictionary={};var paid: Dictionary={};var index:=0
	for action: String in commands:
		var entry: Dictionary=commands[action];var c: Dictionary=entry["envelope"]["command"];var result: Dictionary=entry["result"].duplicate(true);result.erase("decision")
		if result["accepted"] and c["kind"] in ACTIONS:
			var p: Dictionary=c["payload"];var actor: String=entry["envelope"]["actor"];var at: int=c["minute"]
			if c["kind"]=="declare_share_distribution":
				var id: String="share_distribution:"+action;var r: Dictionary=plans.get(id,{})
				var boundaries: Array=native.get("assets",{}).get("call_market",{}).get("clearings",[])
				if at>0 and (at/1440>boundaries.size() or index<int(boundaries[at/1440-1]["command_count"])): return fail("Distribution registration precedes the original daily equity call")
				if not seen.is_empty() or r.is_empty() or not FormalLedgerState.exact_fields(p,["asset_id","per_share","denomination"]) or p["asset_id"]!=config["asset_id"] or (actor!=config["controller"] and not (actor==config["issuer"] and market().corporate.enabled())) or p["per_share"]<1 or p["per_share"]>config["max_per_share"] or p["denomination"]!=FormalLedgerState.DENOMINATION or at%1440!=0 or at<config["start"] or at>=config["end"] or r["record_minute"]!=at or r["due_minute"]!=at+int(config["delay_days"])*1440 or r["command_cursor"]!=index or r["action_id"]!=action or r["actor"]!=actor or r["issuer"]!=config["issuer"] or r["asset_id"]!=p["asset_id"] or r["per_share"]!=p["per_share"] or r["denomination"]!=p["denomination"] or r["source_account"]!=economy()._account(config["issuer"]) or r["total"]!=int(r["issued_shares"])*int(p["per_share"]): return fail("Distribution original decision, registration time or amount conflict")
				var proof: Dictionary=r["authority"]
				if not economy()._cargo_fulfilment._saved_authority(proof) or proof.get("actor")!=config["controller"] or proof.get("operation")!="economy.equity.distribute" or proof.get("authority_id")!=config["authority_id"] or proof.get("subject")!=config["issuer"] or proof.get("target")!=config["issuer"] or proof.get("category")!=config["asset_id"] or proof.get("amount")!=r["total"] or proof.get("minute")!=at: return fail("Distribution lacks separate historical authority")
				if r["ledger_cursor"]>market()._ledger._transactions.size(): return fail("Distribution has a future Ledger cursor")
				for j: int in market()._ledger._transactions.size():
					var tx: Dictionary=market()._ledger._transactions[j]
					if (j<r["ledger_cursor"] and tx["effective_minute"]>at) or (j>=r["ledger_cursor"] and tx["effective_minute"]<at): return fail("Distribution Ledger boundary precedes or skips history")
				var guard:=protection(at,native,r["ledger_cursor"],index) if r["protection"].get("basis")==CashObservation.BASIS else legacy_protection(at,native,r["ledger_cursor"],index)
				if guard!=r["protection"] or not guard["unsupported"].is_empty() or r["total"]>guard["distributable"]: return fail("Distribution violates historical cash protection")
				if result!={"accepted":true,"reason":"REGISTERED_SHAREHOLDERS_AND_FULL_CASH_RESERVED","distribution_id":id,"total":r["total"],"record_minute":at}: return fail("Distribution decision receipt conflict")
				seen[id]=true
			else:
				var id: String=p.get("distribution_id","");var r: Dictionary=plans.get(id,{})
				var clearings: Array=native.get("assets",{}).get("call_market",{}).get("clearings",[])
				if not FormalLedgerState.exact_fields(p,["distribution_id"]) or not seen.has(id) or paid.has(id) or actor!=config["issuer"] or at%1440!=0 or at/1440>clearings.size() or index!=clearings[at/1440-1]["command_count"] or at<r["due_minute"] or r["status"]!="PAID" or r["paid_minute"]!=at or r["payment_action"]!=action or r["payment_batch"]!="share_distribution_batch:"+action: return fail("Distribution payment lacks original due responsibility")
				var ids: Array[String]=[]
				for leg: Dictionary in legs(r):
					var expected:=leg.duplicate(true);expected.merge({"denomination":r["denomination"],"effective_minute":at,"basis":"GENERATED_SIMULATION_ASSUMPTION"})
					if market()._ledger.transaction(leg["transaction_id"])!=expected: return fail("Distribution payee or amount differs from Ledger")
					ids.append(leg["transaction_id"])
				if market()._ledger.payment_batch(r["payment_batch"])!={"transactions":ids,"releases":{id:r["total"]},"minute":at} or result!={"accepted":true,"reason":"REGISTERED_SHAREHOLDERS_ATOMICALLY_PAID","distribution_id":id,"total":r["total"],"payment_batch":r["payment_batch"]}: return fail("Distribution lacks original atomic batch or receipt")
				paid[id]=true
		index+=1
	if seen.size()!=plans.size(): return fail("Orphan distribution")
	for r: Dictionary in plans.values():
		if (r["status"]=="PAID")!=paid.has(r["id"]): return fail("Distribution payment lost its original accepted action")
		if r["status"]=="RESERVED" and (r["paid_minute"]!=-1 or r["payment_action"]!="" or r["payment_batch"]!=""): return fail("Unpaid distribution claims payment")
		for p: Dictionary in market().call_market.config["participants"]:
			var n:=notice(r,p["actor"]);var found: Variant=native.get("receipts",{}).get(n["id"])
			if found==null:
				for m: Dictionary in native.get("messages",[]):
					if m["id"]==n["id"]: found=m
			if found!=n: return fail("Distribution disclosure lost actual recipient")
	return true
func explain_payments(receipts: Dictionary) -> void:
	for r: Dictionary in plans.values():
		if r["status"]=="PAID":
			for leg: Dictionary in legs(r): receipts[leg["transaction_id"]]=true
func visible(actor: String) -> Dictionary:
	if not enabled(): return {}
	var now: int=economy()._world.game_clock.total_minutes()
	var manager: bool=actor==config["controller"] and economy()._manager_at(actor,config["issuer"],now)
	var rows: Array=[]
	for r: Dictionary in plans.values():
		var entitled: Dictionary=r["recipients"].get(actor,{})
		var received: bool=economy()._receipts.has("distribution_notice:"+str(r["id"])+":"+actor)
		if not manager and entitled.is_empty() and not received: continue
		var row:=r.duplicate(true);row.erase("authority");row.erase("ledger_cursor");row.erase("command_cursor")
		row["own_record_shares"]=entitled.get("shares",0);row["own_due"]=entitled.get("amount",0);row["notice_received"]=received
		row["payments"]=legs(r).map(func(l: Dictionary)->Dictionary:return market()._ledger.transaction(l["transaction_id"])) if r["status"]=="PAID" else []
		if not manager:
			row.erase("recipients");row.erase("protection");row["payments"]=row["payments"].filter(func(t: Dictionary)->bool:return t["to_account_id"]==market()._ledger.owner_account(actor))
		rows.append(row)
	if not manager and rows.is_empty(): return {}
	var guard: Dictionary=protection(now,context(),market()._ledger._transactions.size(),economy()._commands.size()) if manager and now%1440==0 else {}
	# Presentation annotations are detached and never added to the adopted proof.
	# Fee settlement and actual return of property are separate contract facts.
	for source: Dictionary in guard.get("sources",[]):
		var id: String=source["id"]
		if source["domain"]=="SERVICE": source["current_stage"]=economy()._service_market.contracts[id]["status"]
		elif source["domain"]=="LEASE": source["current_stage"]=economy()._leases.contracts[id]["state"]
		elif source["domain"]=="CAPITAL_TRADE": source["current_stage"]=economy()._capital.resale_trades[id]["state"]
		elif source["domain"]=="CAPITAL_FREIGHT": source["current_stage"]=economy()._capital_transport.tasks[id]["stage"]
	var flows: Dictionary={"cash_distribution_received":0,"secondary_sales_received":0,"secondary_purchases_paid":0,"primary_subscriptions_paid":0}
	var account:=market()._ledger.owner_account(actor)
	for t: Dictionary in market()._ledger.own_transactions(actor):
		if t["kind"]=="dividend" and t["to_account_id"]==account: flows["cash_distribution_received"]+=int(t["amount"])
		elif t["kind"]=="equity_issue" and t["from_account_id"]==account: flows["primary_subscriptions_paid"]+=int(t["amount"])
		elif t["kind"]=="asset_trade": flows["secondary_sales_received" if t["to_account_id"]==account else "secondary_purchases_paid"]+=int(t["amount"])
	return {"own_flows":flows,"plans":rows,"program":config.duplicate(true) if manager else {},"can_decide":manager and plans.is_empty() and now%1440==0 and not authority(actor,1).is_empty(),"protection":guard,"company_available":market()._ledger.available_balance(economy()._account(config["issuer"])) if manager else null,"current_shares":market()._assets[config["asset_id"]]["holders"].get(actor,0),"issued_shares":market()._assets[config["asset_id"]]["total_shares"],"basis":"CASH_DISTRIBUTION_NOT_NET_PROFIT_OR_TOTAL_INVESTMENT_RETURN"}
func reject(why: String) -> Dictionary: return {"accepted":false,"reason":why}
func fail(why: String) -> bool: error=why;return false
