extends RefCounted
## Optional primary program coordinated by AssetMarket. Shares stay in its
## registry; subscriptions only reference original Ledger reservations.
const ACTIONS: Array[String] = ["publish_share_issue","subscribe_share_issue","cancel_share_issue","settle_share_issue"]
var owner_ref: WeakRef
var economy_ref: WeakRef
var config: Dictionary = {}
var issues: Dictionary = {}
var subscriptions: Dictionary = {}
var settlements: Dictionary = {}
var error: String = ""
func market() -> EconomyAssetMarket: return owner_ref.get_ref() as EconomyAssetMarket
func economy() -> EconomyR1Slice: return economy_ref.get_ref() as EconomyR1Slice
func enabled() -> bool: return not config.is_empty()
func bind(owner: RefCounted, settings: Dictionary, e: RefCounted) -> void:
	owner_ref=weakref(owner); economy_ref=weakref(e) if e!=null else null
	config=settings.get("equity_primary",{}).duplicate(true)

static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	if not settings.has("equity_primary"): return true
	var c: Variant=settings["equity_primary"]
	if not c is Dictionary or not FormalLedgerState.exact_fields(c,["basis","asset_id","issuer","controller","authority_id","max_new_shares","price","minimum","duration_days","start","end","template_id","issuer_policy","max_per_investor","npc_quantity","npc_target","consenting_holders","dilution_basis"]): return false
	if c["basis"]!="GENERATED_SIMULATION_ASSUMPTION_PRIMARY_PROGRAM" or c["dilution_basis"]!="ALL_FOUNDERS_CONSENT_BOUNDED_PROGRAM_NO_PREEMPTION" or c["issuer_policy"] not in ["PLAYER","PROJECT_GAP"] or not settings.has("equity_call_market") or not c["consenting_holders"] is Array: return false
	if c["asset_id"]!=settings["equity_call_market"]["asset_id"] or not spec["firms"].has(c["issuer"]) or c["controller"] not in ["HOST_SELECTED_PLAYER",spec["firms"][c["issuer"]].get("manager")]: return false
	for k: String in ["max_new_shares","price","minimum","duration_days","start","end","max_per_investor","npc_quantity","npc_target"]:
		if not FormalLedgerState.valid_amount(c[k]): return false
	if c["max_new_shares"]<1 or c["max_new_shares"]>100 or c["price"]<1 or c["minimum"]<1 or c["minimum"]>c["max_new_shares"] or c["max_per_investor"]<1 or c["max_per_investor"]>c["max_new_shares"] or c["npc_quantity"]<1 or c["npc_quantity"]>c["max_per_investor"] or c["duration_days"]<2 or c["duration_days"]>14 or c["end"]<=c["start"] or c["end"]>90*1440 or c["price"]>FormalLedgerState.MAX_AMOUNT/c["max_new_shares"]: return false
	var found:=false
	for t: Dictionary in settings.get("capital_investment",{}).get("templates",[]):
		if t["id"]==c["template_id"] and t["firm"]==c["issuer"]: found=true
	if not found or not c["authority_id"] is String or not c["authority_id"].begins_with("authority:development:primary:"): return false
	for a: Dictionary in settings.get("assets",[]):
		if a["id"]==c["asset_id"]:
			var holders: Array=a["holders"].keys();holders.sort()
			var consent: Array=c["consenting_holders"].duplicate();consent.sort()
			return a["issuer"]==c["issuer"] and holders==consent
	return false

func terms_ok(p: Dictionary, at: int) -> bool:
	return FormalLedgerState.exact_fields(p,["asset_id","project_id","quantity","price","minimum","valid_minutes","denomination"]) and p["asset_id"]==config["asset_id"] and p["project_id"] is String and p["price"]==config["price"] and p["minimum"]==config["minimum"] and p["valid_minutes"]==int(config["duration_days"])*1440 and p["denomination"]==FormalLedgerState.DENOMINATION and FormalLedgerState.valid_amount(p["quantity"]) and p["quantity"]>=p["minimum"] and p["quantity"]<=config["max_new_shares"] and at>=int(config["start"]) and closing_minute(at)<=int(config["end"])

func closing_minute(at: int) -> int: return ((at+1439)/1440+int(config["duration_days"]))*1440

func project_ok(id: String, at: int, native: Dictionary={}) -> bool:
	var p: Dictionary=native.get("capital_formation",{}).get("projects",economy()._capital.projects).get(id,{})
	if p.is_empty() or p["firm"]!=config["issuer"] or p["template_id"]!=config["template_id"] or p["accepted_minute"]>at or (p["completed_minute"]>=0 and p["completed_minute"]<=at) or p["kind"] in ["MAINTENANCE","DISMANTLE","HANDOVER","REINSTALL"]: return false
	var latest: int=-1;var state: String="ACTIVE"
	for change: Dictionary in native.get("capital_formation",{}).get("changes",economy()._capital.changes).values():
		if change["kind"]=="investment_status" and change["status"]=="APPLIED" and change["payload"]["project_id"]==id and change["effective_minute"]<=at and change["effective_minute"]>latest:
			latest=change["effective_minute"];state=change["payload"]["status"]
	return state not in ["PAUSED","CANCELLED"]

func authority(actor: String, quantity: int, at: int) -> Dictionary:
	var e:=economy();var representative: String=actor
	if actor==config["issuer"] and config["issuer_policy"]=="PROJECT_GAP": representative=e.firm_manager_at(actor,at)
	if representative!=config["controller"] or not e._world.person_overlay.has_person(representative) or not e._manager_at(representative,config["issuer"],at) or (actor==config["issuer"] and representative==e._world.player_state.player_id()): return {}
	var scope: Dictionary={"operation":"economy.equity.issue","target":config["issuer"],"place":e._place(e._primary_site(config["issuer"])),"category":config["asset_id"],"amount":quantity}
	var context:=e._cargo_fulfilment._available_context(representative,config["issuer"],scope,config["authority_id"])
	var result:=e._cargo_fulfilment._authorize(representative,config["issuer"],scope["operation"],scope["target"],scope["place"],scope["category"],quantity,{str(config["issuer"])+"|economy.equity.issue|"+str(config["asset_id"]):context})
	return result.get("proof",{}) if result.get("ok",false) and result.get("proof",{}).get("authority_id")==config["authority_id"] else {}

func proof_ok(proof: Variant, actor: String, quantity: int, at: int) -> bool:
	return proof is Dictionary and economy()._cargo_fulfilment._saved_authority(proof) and proof.get("authority_id")==config["authority_id"] and proof.get("actor")==config["controller"] and actor in [config["controller"],config["issuer"]] and (actor!=config["issuer"] or config["issuer_policy"]=="PROJECT_GAP") and proof.get("operation")=="economy.equity.issue" and proof.get("subject")==config["issuer"] and proof.get("target")==config["issuer"] and proof.get("category")==config["asset_id"] and proof.get("amount")==quantity and proof.get("minute")==at

func publish(actor: String,p: Dictionary,at: int,action: String) -> Dictionary:
	if not enabled() or not terms_ok(p,at): return reject("PRIMARY_TERMS_OR_AUTHORIZED_QUOTA")
	if not issues.is_empty(): return reject("PRIMARY_PROGRAM_ALREADY_COMMITTED")
	if not project_ok(p["project_id"],at) or economy()._firm_winding_down(config["issuer"]) or economy().firm_finished(config["issuer"]): return reject("PRIMARY_REQUIRES_ACTIVE_REAL_INVESTMENT")
	var proof:=authority(actor,p["quantity"],at)
	if proof.is_empty(): return reject("NO_SEPARATE_SHARE_ISSUANCE_AUTHORITY")
	var id: String="primary_issue:"+action
	issues[id]=new_issue(id,actor,p,at,action,proof)
	for participant: Dictionary in market().call_market.config["participants"]:
		economy()._messages.append(notice(issues[id],participant["actor"]))
	return {"accepted":true,"reason":"PRIMARY_TERMS_PUBLISHED_NO_SHARES_OR_CASH_YET","issue_id":id}

func new_issue(id: String,actor: String,p: Dictionary,at: int,action: String,proof: Dictionary) -> Dictionary:
	return {"id":id,"actor":actor,"issuer":config["issuer"],"asset_id":p["asset_id"],"project_id":p["project_id"],"quantity":p["quantity"],"price":p["price"],"minimum":p["minimum"],"denomination":p["denomination"],"opened_minute":at,"close_minute":closing_minute(at),"action_id":action,"authority":proof.duplicate(true),"status":"OPEN","closed_minute":-1,"closed_action":"","cancellation_authority":{},"subscriptions":[]}

func notice(i: Dictionary,actor: String) -> Dictionary:
	return {"id":"primary_notice:"+str(i["id"])+":"+actor,"actor":actor,"kind":"equity_issue","candidate":i["id"],"observed_day":int(i["opened_minute"])/1440,"delivery_day":int(i["opened_minute"])/1440+1}
func message_valid(m: Dictionary) -> bool:
	return enabled() and issues.has(m.get("candidate")) and not market().call_market.participant(m.get("actor","")).is_empty() and m==notice(issues[m["candidate"]],m["actor"])
func known(id: String,actor: String,receipts: Variant=null,at: int=-1) -> bool:
	if at<0: at=economy()._world.game_clock.total_minutes()
	var r: Dictionary=(economy()._receipts if receipts==null else receipts).get("primary_notice:"+id+":"+actor,{})
	return message_valid(r) and int(r["delivery_day"])*1440<=at
func committed(i: Dictionary,rows: Dictionary={}) -> int:
	var total:=0
	for id: String in i["subscriptions"]: total+=int((subscriptions if rows.is_empty() else rows)[id]["quantity"])
	return total
func investor_ok(actor: String,i: Dictionary,at: int,historical: bool=false) -> bool:
	var p:=market().call_market.participant(actor)
	return (historical or not economy()._spec["firms"].has(actor) or (not economy()._firm_winding_down(actor) and not economy().firm_finished(actor))) and not p.is_empty() and p["buy"] and actor!=config["issuer"] and at>=p["start"] and at<p["end"] and market()._known(actor,i["asset_id"]) and not market()._ledger.owner_account(actor,i["denomination"]).is_empty()

func subscribe(actor: String,p: Dictionary,at: int,action: String) -> Dictionary:
	if not enabled() or not FormalLedgerState.exact_fields(p,["issue_id","quantity","price","denomination"]) or not p["issue_id"] is String or not FormalLedgerState.valid_amount(p["quantity"]) or p["quantity"]<1: return reject("INVALID_PRIMARY_SUBSCRIPTION")
	var i: Dictionary=issues.get(p["issue_id"],{})
	if i.is_empty() or not known(i["id"],actor): return reject("PRIMARY_NOTICE_NOT_RECEIVED")
	if i["status"]!="OPEN" or at>=i["close_minute"]: return reject("PRIMARY_SUBSCRIPTION_CLOSED")
	if not investor_ok(actor,i,at) or p["price"]!=i["price"] or p["denomination"]!=i["denomination"] or p["quantity"]>config["max_per_investor"]: return reject("PRIMARY_INVESTOR_OR_TERMS")
	for s: Dictionary in subscriptions.values():
		if s["issue_id"]==i["id"] and s["buyer"]==actor: return reject("INVESTOR_ALREADY_SUBSCRIBED")
	if committed(i)+int(p["quantity"])>int(i["quantity"]): return reject("PRIMARY_AVAILABLE_QUANTITY_EXCEEDED")
	var id: String="primary_subscription:"+action
	var account:=market()._ledger.owner_account(actor,i["denomination"])
	var cash: int=int(p["quantity"])*int(i["price"])
	if not market()._ledger.reserve(id,account,cash): return reject("PRIMARY_INVESTOR_FUNDS_UNAVAILABLE")
	subscriptions[id]={"id":id,"issue_id":i["id"],"buyer":actor,"account_id":account,"quantity":p["quantity"],"minute":at,"action_id":action,"status":"RESERVED"}
	i["subscriptions"].append(id)
	return {"accepted":true,"reason":"SUBSCRIPTION_CASH_RESERVED_NOT_ISSUED","subscription_id":id,"reserved":cash}

func release_issue(i: Dictionary,status: String,at: int,action: String) -> bool:
	for id: String in i["subscriptions"]:
		var s: Dictionary=subscriptions[id]
		if s["status"]!="RESERVED" or market()._ledger._reservations.get(id)!={"account_id":s["account_id"],"amount":int(s["quantity"])*int(i["price"])}: return false
	for id: String in i["subscriptions"]:
		var s: Dictionary=subscriptions[id]
		var released: bool=market()._ledger.release(id,int(s["quantity"])*int(i["price"]))
		assert(released) # Release runs in both debug and release exports.
		s["status"]="RELEASED"
	i["status"]=status;i["closed_minute"]=at;i["closed_action"]=action
	return true
func cancel(actor: String,p: Dictionary,at: int,action: String) -> Dictionary:
	var i: Dictionary=issues.get(p.get("issue_id",""),{})
	if not FormalLedgerState.exact_fields(p,["issue_id"]) or i.is_empty() or i["status"]!="OPEN" or at>=i["close_minute"]: return reject("PRIMARY_CANNOT_CANCEL_OR_NO_AUTHORITY")
	var proof:=authority(actor,i["quantity"],at)
	if proof.is_empty(): return reject("PRIMARY_CANNOT_CANCEL_OR_NO_AUTHORITY")
	if not release_issue(i,"CANCELLED",at,action): return reject("PRIMARY_RELEASE_COMMITMENT_MISMATCH")
	i["cancellation_authority"]=proof
	return {"accepted":true,"reason":"UNISSUED_SUBSCRIPTIONS_RELEASED","issue_id":i["id"]}

func legs(i: Dictionary,rows: Dictionary={}) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id: String in i["subscriptions"]:
		var s: Dictionary=(subscriptions if rows.is_empty() else rows)[id]
		result.append({"transaction_id":"primary_payment:"+id,"from_account_id":s["account_id"],"to_account_id":market()._ledger.owner_account(config["issuer"],i["denomination"]),"amount":int(s["quantity"])*int(i["price"]),"kind":"equity_issue","reference_id":i["id"]})
	return result
func releases(i: Dictionary,rows: Dictionary={}) -> Dictionary:
	var result: Dictionary={}
	for id: String in i["subscriptions"]: result[id]=int((subscriptions if rows.is_empty() else rows)[id]["quantity"])*int(i["price"])
	return result

func settle(actor: String,p: Dictionary,at: int,action: String) -> Dictionary:
	var i: Dictionary=issues.get(p.get("issue_id",""),{})
	if not enabled() or not FormalLedgerState.exact_fields(p,["issue_id"]) or actor!=config["issuer"] or economy().phase!="EQUITY_CLEARING" or i.is_empty() or i["status"]!="OPEN" or at<i["close_minute"] or at%1440!=0: return reject("NO_PRIMARY_CLOSING_BOUNDARY")
	var quantity:=committed(i);var id: String="primary_settlement:"+action
	var status: String="ISSUED" if quantity>=int(i["minimum"]) else "FAILED"
	if status=="ISSUED":
		if quantity>i["quantity"] or market()._assets[i["asset_id"]]["total_shares"]>FormalLedgerState.MAX_AMOUNT-quantity: return reject("PRIMARY_ISSUED_TOTAL_BOUNDS")
		if not market()._ledger.batch_payment(id,legs(i),at,releases(i)): return reject("PRIMARY_ATOMIC_PAYMENT_FAILED")
		var asset: Dictionary=market()._assets[i["asset_id"]]
		asset["total_shares"]+=quantity
		for sub: String in i["subscriptions"]:
			var s: Dictionary=subscriptions[sub]
			asset["holders"][s["buyer"]]=int(asset["holders"].get(s["buyer"],0))+int(s["quantity"]);s["status"]="ALLOTTED"
		i["status"]=status;i["closed_minute"]=at;i["closed_action"]=action
	elif not release_issue(i,status,at,action): return reject("PRIMARY_RELEASE_COMMITMENT_MISMATCH")
	settlements[id]={"id":id,"issue_id":i["id"],"minute":at,"action_id":action,"status":status,"quantity":quantity if status=="ISSUED" else 0,"cash":quantity*int(i["price"]) if status=="ISSUED" else 0}
	return {"accepted":true,"reason":"PRIMARY_ATOMICALLY_ISSUED" if status=="ISSUED" else "PRIMARY_MINIMUM_NOT_MET_RELEASED","settlement_id":id,"quantity":settlements[id]["quantity"],"cash":settlements[id]["cash"]}

func clear_day() -> void:
	if not enabled(): return
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	for i: Dictionary in issues.values():
		if i["status"]=="OPEN" and now>=i["close_minute"]: e._npc_submit(config["issuer"],"settle_share_issue",{"issue_id":i["id"]},"primary_close:"+str(i["id"]),{"basis":"ORIGINAL_ACCEPTED_PRIMARY_CLOSING_TERMS"})

func npc_decisions() -> void:
	if not enabled(): return
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if not market().corporate.enabled() and config["issuer_policy"]=="PROJECT_GAP" and issues.is_empty() and config["controller"]!=e._world.player_state.player_id():
		for p: Dictionary in e._capital.projects.values():
			if not project_ok(p["id"],now): continue
			var protected: int=e._capital_cash_protected(config["issuer"],e._capital.template(config["template_id"]))
			var gap: int=int(p["budget"])+protected-market()._ledger.available_balance(e._account(config["issuer"]))
			if gap>0: e._npc_submit(config["issuer"],"publish_share_issue",{"asset_id":config["asset_id"],"project_id":p["id"],"quantity":config["max_new_shares"],"minimum":config["minimum"],"price":config["price"],"denomination":FormalLedgerState.DENOMINATION,"valid_minutes":int(config["duration_days"])*1440},"primary_project_gap",{"project_id":p["id"],"gap":gap,"basis":"OWN_REAL_PROJECT_AND_PROTECTED_CASH"})
	for p: Dictionary in market().call_market.config["participants"]:
		var actor: String=p["actor"]
		if p["policy"]!="HOLDING" or e.day%int(p["period"])!=0: continue
		var report:=market().call_market.report_known(actor)
		if report.is_empty() or report["summary"]["delivered"]<=0 or report["summary"]["goods_receipts"]<report["summary"]["wages_incurred"]: continue
		for i: Dictionary in issues.values():
			if i["status"]!="OPEN" or not known(i["id"],actor) or not investor_ok(actor,i,now) or i["price"]>p["bid_limit"] or now>=i["close_minute"]: continue
			var prior:=false
			for s: Dictionary in subscriptions.values():
				if s["buyer"]==actor and s["issue_id"]==i["id"]: prior=true
			if prior: continue
			var free: int=market()._ledger.available_balance(e._account(actor));var due: int=e._mature_wage_position(actor,FormalLedgerState.DENOMINATION)["amount"]+e._due_credit_amount(actor,FormalLedgerState.DENOMINATION)
			var own: int=market()._assets[i["asset_id"]]["holders"].get(actor,0)
			var quantity: int=mini(int(config["npc_quantity"]),mini(int(config["npc_target"])-own,mini(int(i["quantity"])-committed(i),maxi(0,free-int(p["cash_floor"])-due)/int(i["price"]))))
			if quantity>0: e._npc_submit(actor,"subscribe_share_issue",{"issue_id":i["id"],"quantity":quantity,"price":i["price"],"denomination":i["denomination"]},"primary_subscription:"+str(i["id"]),{"report_id":report["id"],"issue_id":i["id"],"own_cash":free,"due":due,"basis":"RECEIVED_REPORT_OWN_CASH_AND_PORTFOLIO_LIMIT"})

func reservations() -> Dictionary:
	var result: Dictionary={}
	for s: Dictionary in subscriptions.values():
		if s["status"]=="RESERVED": result[s["id"]]={"account_id":s["account_id"],"amount":int(s["quantity"])*int(issues[s["issue_id"]]["price"])}
	return result
func snapshot() -> Dictionary: return {"format":"EQUITY_PRIMARY_EXPERIMENT_V1","issues":issues.duplicate(true),"subscriptions":subscriptions.duplicate(true),"settlements":settlements.duplicate(true)}
func prepare(value: Variant) -> bool:
	if not enabled(): return value==null
	if not value is Dictionary or not FormalLedgerState.exact_fields(value,["format","issues","subscriptions","settlements"]) or value["format"]!="EQUITY_PRIMARY_EXPERIMENT_V1" or not value["issues"] is Dictionary or not value["subscriptions"] is Dictionary or not value["settlements"] is Dictionary or value["issues"].size()>1 or value["subscriptions"].size()>4: return fail("Invalid primary containers")
	issues=value["issues"].duplicate(true);subscriptions=value["subscriptions"].duplicate(true);settlements=value["settlements"].duplicate(true)
	for i: Variant in issues.values():
		if not i is Dictionary or not FormalLedgerState.exact_fields(i,["id","actor","issuer","asset_id","project_id","quantity","price","minimum","denomination","opened_minute","close_minute","action_id","authority","status","closed_minute","closed_action","cancellation_authority","subscriptions"]) or not i["subscriptions"] is Array or not i["authority"] is Dictionary: return fail("Malformed primary issue")
		for field: String in ["id","actor","issuer","asset_id","project_id","denomination","action_id","status","closed_action"]:
			if not i[field] is String: return fail("Invalid primary identity")
		for field: String in ["quantity","price","minimum","opened_minute","close_minute"]:
			if not FormalLedgerState.valid_amount(i[field]): return fail("Invalid primary amount or time")
		if i["quantity"]<1 or i["quantity"]>config["max_new_shares"] or i["price"]!=config["price"] or i["minimum"]!=config["minimum"] or not i["closed_minute"] is int or not i["cancellation_authority"] is Dictionary or i["subscriptions"].size()>4 or i["status"] not in ["OPEN","ISSUED","FAILED","CANCELLED"] or issues.get(i["id"])!=i: return fail("Invalid primary bounds")
		for id: Variant in i["subscriptions"]:
			if not id is String or not subscriptions.has(id): return fail("Invalid subscription reference")
	for s: Variant in subscriptions.values():
		if not s is Dictionary or not FormalLedgerState.exact_fields(s,["id","issue_id","buyer","account_id","quantity","minute","action_id","status"]) or not FormalLedgerState.valid_amount(s["quantity"]) or s["quantity"]<1 or not issues.has(s["issue_id"]): return fail("Malformed primary subscription")
		for field: String in ["id","issue_id","buyer","account_id","action_id","status"]:
			if not s[field] is String: return fail("Invalid subscription identity")
		if s["quantity"]>config["max_per_investor"] or not FormalLedgerState.valid_amount(s["minute"]) or s["status"] not in ["RESERVED","ALLOTTED","RELEASED"] or subscriptions.get(s["id"])!=s: return fail("Invalid subscription bounds")
	for s: Variant in settlements.values():
		if not s is Dictionary or not FormalLedgerState.exact_fields(s,["id","issue_id","minute","action_id","status","quantity","cash"]) or not s["id"] is String or not s["action_id"] is String or not issues.has(s["issue_id"]) or settlements.get(s["id"])!=s: return fail("Malformed primary settlement")
		for field: String in ["minute","quantity","cash"]:
			if not FormalLedgerState.valid_amount(s[field]): return fail("Invalid primary settlement amount")
	return true

func validate(value: Variant,commands: Dictionary,at: int,native: Dictionary) -> bool:
	if not prepare(value): return false
	if not enabled(): return true
	var expected: Dictionary={};var subs: Dictionary={};var closes: Dictionary={};var index: int=0
	var boundaries: Array=native.get("assets",{}).get("call_market",{}).get("clearings",[])
	for action: String in commands:
		index+=1
		var entry: Dictionary=commands[action];var c: Dictionary=entry["envelope"]["command"];var result: Dictionary=entry["result"].duplicate(true);result.erase("decision")
		if c["kind"] not in ACTIONS or not result["accepted"]: continue
		var actor: String=entry["envelope"]["actor"];var p: Dictionary=c["payload"];var minute: int=c["minute"]
		if c["kind"]=="publish_share_issue":
			var id: String="primary_issue:"+action
			if not expected.is_empty() or not issues.has(id) or not terms_ok(p,minute) or not project_ok(p["project_id"],minute,native) or not proof_ok(issues[id]["authority"],actor,p["quantity"],minute) or result!={"accepted":true,"reason":"PRIMARY_TERMS_PUBLISHED_NO_SHARES_OR_CASH_YET","issue_id":id}: return fail("Primary issuance lacks original program, real project or authority")
			expected[id]=new_issue(id,actor,p,minute,action,issues[id]["authority"])
		elif c["kind"]=="subscribe_share_issue":
			if not FormalLedgerState.exact_fields(p,["issue_id","quantity","price","denomination"]) or not expected.has(p["issue_id"]): return fail("Subscription lost original issue")
			var i: Dictionary=expected[p["issue_id"]];var id: String="primary_subscription:"+action
			if not subscriptions.has(id) or i["status"]!="OPEN" or minute>=i["close_minute"] or not known(i["id"],actor,native.get("receipts",{}),minute) or not investor_ok(actor,i,minute,true) or not FormalLedgerState.valid_amount(p["quantity"]) or p["quantity"]<1 or p["quantity"]>config["max_per_investor"] or p["price"]!=i["price"] or p["denomination"]!=i["denomination"] or committed(i,subs)+int(p["quantity"])>i["quantity"]: return fail("Subscription terms, receipt or allotment limit conflict")
			for prior: Dictionary in subs.values():
				if prior["buyer"]==actor and prior["issue_id"]==i["id"]: return fail("Duplicate primary investor")
			subs[id]={"id":id,"issue_id":i["id"],"buyer":actor,"account_id":market()._ledger.owner_account(actor,i["denomination"]),"quantity":p["quantity"],"minute":minute,"action_id":action,"status":"RESERVED"}
			if result!={"accepted":true,"reason":"SUBSCRIPTION_CASH_RESERVED_NOT_ISSUED","subscription_id":id,"reserved":int(p["quantity"])*int(i["price"])}: return fail("Subscription cash commitment conflict")
			i["subscriptions"].append(id)
		else:
			if not FormalLedgerState.exact_fields(p,["issue_id"]) or not expected.has(p["issue_id"]): return fail("Primary close lost its issue")
			var i: Dictionary=expected[p["issue_id"]]
			if i["status"]!="OPEN": return fail("Repeated primary settlement")
			var status: String="CANCELLED"
			if c["kind"]=="cancel_share_issue":
				if not proof_ok(issues[i["id"]]["cancellation_authority"],actor,i["quantity"],minute) or minute>=i["close_minute"] or result!={"accepted":true,"reason":"UNISSUED_SUBSCRIPTIONS_RELEASED","issue_id":i["id"]}: return fail("Invalid primary cancellation")
				i["cancellation_authority"]=issues[i["id"]]["cancellation_authority"].duplicate(true)
			else:
				if actor!=config["issuer"] or minute<i["close_minute"] or minute%1440!=0 or minute/1440>boundaries.size() or index>int(boundaries[minute/1440-1]["command_count"]) or (minute>1440 and index<=int(boundaries[minute/1440-2]["command_count"])): return fail("Premature primary allotment")
				var quantity:=committed(i,subs);status="ISSUED" if quantity>=i["minimum"] else "FAILED"
				var id: String="primary_settlement:"+action
				closes[id]={"id":id,"issue_id":i["id"],"minute":minute,"action_id":action,"status":status,"quantity":quantity if status=="ISSUED" else 0,"cash":quantity*int(i["price"]) if status=="ISSUED" else 0}
				if result!={"accepted":true,"reason":"PRIMARY_ATOMICALLY_ISSUED" if status=="ISSUED" else "PRIMARY_MINIMUM_NOT_MET_RELEASED","settlement_id":id,"quantity":closes[id]["quantity"],"cash":closes[id]["cash"]}: return fail("Primary allotment result conflict")
				if status=="ISSUED" and not payment_valid(id,i,subs,minute): return false
			i["status"]=status;i["closed_minute"]=minute;i["closed_action"]=action
			for id: String in i["subscriptions"]: subs[id]["status"]="ALLOTTED" if status=="ISSUED" else "RELEASED"
	if expected!=issues or subs!=subscriptions or closes!=settlements: return fail("Primary history, source or remaining responsibility mismatch")
	for i: Dictionary in issues.values():
		if i["status"]=="OPEN" and at>=i["close_minute"]: return fail("Primary close boundary was skipped")
		for p: Dictionary in market().call_market.config["participants"]:
			var n:=notice(i,p["actor"]);var found: Variant=native.get("receipts",{}).get(n["id"])
			if found==null:
				for m: Dictionary in native.get("messages",[]):
					if m["id"]==n["id"]: found=m;break
			if found!=n: return fail("Primary issue lost its directed recipient or notice")
	return true

func payment_valid(id: String,i: Dictionary,subs: Dictionary,minute: int) -> bool:
	var ids: Array[String]=[]
	for leg: Dictionary in legs(i,subs):
		var expected:=leg.duplicate(true);expected.merge({"denomination":i["denomination"],"effective_minute":minute,"basis":"GENERATED_SIMULATION_ASSUMPTION"})
		if market()._ledger.transaction(leg["transaction_id"])!=expected: return fail("Primary payment account, amount or source differs from Ledger")
		ids.append(leg["transaction_id"])
	return market()._ledger.payment_batch(id)=={"transactions":ids,"releases":releases(i,subs),"minute":minute} or fail("Primary shares lack original atomic payment batch")

func ownership_effect(action: String,assets: Dictionary,receipts: Dictionary) -> void:
	var s: Dictionary=settlements.get("primary_settlement:"+action,{})
	if s.is_empty() or s["status"]!="ISSUED": return
	var i: Dictionary=issues[s["issue_id"]];var asset: Dictionary=assets[i["asset_id"]]
	asset["total_shares"]+=int(s["quantity"])
	for id: String in i["subscriptions"]:
		var sub: Dictionary=subscriptions[id]
		asset["holders"][sub["buyer"]]=int(asset["holders"].get(sub["buyer"],0))+int(sub["quantity"])
		receipts["primary_payment:"+id]=true

func visible(actor: String) -> Dictionary:
	if not enabled(): return {}
	var m:=market();var e:=economy();var minute: int=e._world.game_clock.total_minutes();var own: Dictionary=m._assets[config["asset_id"]]
	var rows: Array=[]
	for i: Dictionary in issues.values():
		if actor!=config["controller"] and not known(i["id"],actor): continue
		var row:=i.duplicate(true);row.erase("authority");row.erase("cancellation_authority")
		row["can_cancel"]=i["status"]=="OPEN" and minute<i["close_minute"] and not authority(actor,i["quantity"],minute).is_empty()
		row["committed_quantity"]=committed(i);row["target_cash"]=int(i["quantity"])*int(i["price"])
		row["received_cash"]=0
		row["issued_before"]=m._configured[i["asset_id"]]["total_shares"]
		for s: Dictionary in settlements.values():
			if s["issue_id"]==i["id"]: row["received_cash"]+=int(s["cash"])
		row["own_subscriptions"]=subscriptions.values().filter(func(s: Dictionary)->bool:return s["issue_id"]==i["id"] and s["buyer"]==actor).duplicate(true)
		if i["status"]=="ISSUED": row["dilution"]=dilution(i)
		if actor!=config["controller"]:
			row.erase("subscriptions");row.erase("dilution")
		rows.append(row)
	if actor!=config["controller"] and rows.is_empty(): return {}
	var holders: Array=[]
	for holder: String in own["holders"]:
		if actor==config["controller"] or holder==actor: holders.append({"holder":holder,"quantity":own["holders"][holder],"total":own["total_shares"]})
	var projects: Array=[]
	if actor==config["controller"]:
		for p: Dictionary in e._capital.projects.values():
			if p["firm"]==config["issuer"] and p["template_id"]==config["template_id"]: projects.append(p.duplicate(true))
	var manager: bool=actor==config["controller"]
	var template: Dictionary=e._capital.template(config["template_id"]) if manager else {}
	var public_program:=config.duplicate(true)
	for field: String in ["npc_quantity","npc_target","issuer_policy"]: public_program.erase(field)
	var gap: Variant=null
	if manager:
		gap=0
		for p: Dictionary in projects:
			if project_ok(p["id"],minute): gap=maxi(0,int(p["budget"])+e._capital_cash_protected(config["issuer"],template)-m._ledger.available_balance(e._account(config["issuer"])))
	var payments: Array=[];var spending: Array=[];var allotted: int=-1
	for s: Dictionary in settlements.values():
		if s["status"]=="ISSUED": allotted=int(s["minute"])
	for tx: Dictionary in m._ledger.own_transactions(config["issuer"]):
		if tx["kind"]=="equity_issue" and (manager or tx["from_account_id"]==m._ledger.owner_account(actor)): payments.append(tx)
		elif manager and allotted>=0 and tx["effective_minute"]>allotted and tx["from_account_id"]==e._account(config["issuer"]): spending.append(tx)
	return {"program":public_program,"can_publish":not authority(actor,config["max_new_shares"],minute).is_empty() and issues.is_empty(),"issues":rows,"holders":holders,"projects":projects,"template":template.duplicate(true),"cash_gap":gap,"company_received":settlements.values().reduce(func(total: int,s: Dictionary)->int:return total+int(s["cash"]),0),"company_account":e._account(config["issuer"]),"payments":payments,"subsequent_spending":spending.slice(-12),"funding_note":"UNIFIED_COMPANY_CASH_SUPPORT_NOT_TRACING_INDIVIDUAL_CURRENCY_UNITS"}

func dilution(issue: Dictionary) -> Array:
	# Derive the immediate before/after allocation, excluding later secondary sales.
	var held: Dictionary=market()._configured[issue["asset_id"]]["holders"].duplicate(true)
	for action: String in economy()._commands:
		if action==issue["closed_action"]: break
		var c: Dictionary=economy()._commands[action]
		if not c["result"]["accepted"]: continue
		var trade: Dictionary=market()._trades.get(c["result"].get("trade_id",""),{})
		if trade.is_empty() or trade["asset_id"]!=issue["asset_id"]: continue
		held[trade["seller"]]=int(held.get(trade["seller"],0))-int(trade["quantity"])
		held[trade["buyer"]]=int(held.get(trade["buyer"],0))+int(trade["quantity"])
	var after:=held.duplicate(true)
	for id: String in issue["subscriptions"]:
		var s: Dictionary=subscriptions[id];after[s["buyer"]]=int(after.get(s["buyer"],0))+int(s["quantity"])
	var result: Array=[];var total: int=market()._configured[issue["asset_id"]]["total_shares"]
	for actor: String in after: result.append({"holder":actor,"before":held.get(actor,0),"before_total":total,"after":after[actor],"after_total":total+committed(issue)})
	return result
func reject(why: String) -> Dictionary: return {"accepted":false,"reason":why}
func fail(why: String) -> bool: error=why;return false
