extends RefCounted
## Bounded operating judgments only. Original commands preserve observations;
## AssetMarket, contracts and Ledger retain all property and payment facts.
const BASIS: String="GENERATED_SIMULATION_ASSUMPTION_CORPORATE_FINANCE"
var owner_ref: WeakRef
var economy_ref: WeakRef
var config: Dictionary={}
var elapsed_us: int=0
var review_ids: Array[String]=[]
var error: String=""
func market() -> EconomyAssetMarket: return owner_ref.get_ref() as EconomyAssetMarket
func economy() -> EconomyR1Slice: return economy_ref.get_ref() as EconomyR1Slice
func bind(owner: RefCounted,settings: Dictionary,e: RefCounted) -> void:
	owner_ref=weakref(owner);economy_ref=weakref(e) if e!=null else null
	config=settings.get("corporate_decisions",{}).duplicate(true)
	review_ids.clear()
func enabled() -> bool:return not config.is_empty()
static func valid_configuration(settings: Dictionary,spec: Dictionary) -> bool:
	if not settings.has("corporate_decisions"):return true
	var c: Variant=settings["corporate_decisions"]
	if not c is Dictionary or not FormalLedgerState.exact_fields(c,["basis","issuer","controller","period_days","issue_enabled","distribution_enabled","plan_investment","retained_surplus","per_share","max_dilution_percent"]):return false
	if c["basis"]!=BASIS or not spec["firms"].has(c["issuer"]) or not settings.has("equity_primary") or not settings.has("equity_distribution") or c["issuer"]!=settings["equity_primary"]["issuer"]:return false
	if c["controller"]!="HOST_NPC_MANAGER" and (not spec["actors"].has(c["controller"]) or spec["actors"][c["controller"]]["control"]!="automatic" or spec["actors"][c["controller"]]["kind"]!="named" or spec["firms"][c["issuer"]].get("manager")!=c["controller"]):return false
	for k: String in ["issue_enabled","distribution_enabled","plan_investment"]:
		if not c[k] is bool:return false
	for k: String in ["period_days","retained_surplus","per_share","max_dilution_percent"]:
		if not FormalLedgerState.valid_amount(c[k]):return false
	return c["period_days"]>=1 and c["period_days"]<=14 and c["per_share"]>=1 and c["per_share"]<=settings["equity_distribution"]["max_per_share"] and c["max_dilution_percent"]>=1 and c["max_dilution_percent"]<=25
func managed(at: int) -> bool:
	if not enabled():return false
	var e:=economy();var person: String=config["controller"]
	if person==e._world.player_state.player_id() or not e._world.person_overlay.has_person(person) or not e._world.person_overlay.is_alive(person) or e.firm_manager_at(config["issuer"],at)!=person:return false
	var organization: String=e._spec["firms"][config["issuer"]].get("host_organization_id","")
	if not e._world.organization_state.is_organization_active(organization):return false
	for appointment: Dictionary in e._world.organization_state.appointments_for_person(person):
		if appointment["organization_id"]==organization and appointment["position_id"]=="economic_operator":return true
	return false
func can_plan(firm: String) -> bool:
	return enabled() and config["issuer"]==firm and config["plan_investment"] and managed(economy()._world.game_clock.total_minutes()) and not market().primary.authority(firm,market().primary.config["minimum"],economy()._world.game_clock.total_minutes()).is_empty()
func known_own_producer(site: String,good: String) -> bool:
	if not can_plan(economy()._owner(site)):return false
	for a: Dictionary in economy()._spec["sites"][site]["activities"]:
		if a["enabled"] and int(a["outputs"].get(good,0))>0:return true
	return false
func context() -> Dictionary:
	var n:=market().distribution.context()
	n["work_records"]=economy()._work_records
	n["enterprise_changes"]=economy()._enterprise_changes
	return n
func observe(at: int,native: Dictionary,cursor: int,count: int,adopted: Variant=null) -> Dictionary:
	var e:=economy();var prefix: Dictionary={};var n:=0
	for id: String in native["commands"]:
		if n>=count:break
		prefix[id]=native["commands"][id];n+=1
	var guard:=market().distribution.protection(at,native,cursor,count)
	var projects: Array=[];var missing_contacts: Array=[];var work:=0;var sales:=0
	for p: Dictionary in native["capital_formation"]["projects"].values():
		if prefix.get(p["action_id"],{}).get("result",{}).get("accepted",false) and market().primary.project_ok(p["id"],at,native):projects.append(p["id"])
	projects.sort()
	var t:=e._capital.template(market().primary.config["template_id"])
	# Only the firm's configured supplier contacts and its actual recent work.
	# Their presence is evidence of feasibility, never a promise of future stock.
	for good: String in t["materials"]:
		var known: bool=int(e._spec["sites"][t["site_id"]]["stock"].get(good,0))>=int(t["materials"][good])
		for supplier: String in e._spec["sites"][t["site_id"]]["suppliers"]:
			if supplier.split("|")[1]==good:known=true
		for a: Dictionary in e._spec["sites"][t["site_id"]]["activities"]:
			if a["enabled"] and int(a["outputs"].get(good,0))>0:known=true
		if not known:missing_contacts.append(good)
	missing_contacts.sort()
	for r: Dictionary in native.get("work_records",{}).values():
		if int(r["day"])*1440<=at and int(r["day"])*1440>at-int(config["period_days"])*1440 and e._job(r["job"])["site_id"]==t["site_id"]:work+=int(r["hours"])
	var ledger: Array=market()._ledger._transactions
	for j: int in mini(cursor,ledger.size()):
		var tx: Dictionary=ledger[j]
		if tx["to_account_id"]==e._account(config["issuer"]) and tx["kind"]=="goods" and tx["effective_minute"]>at-int(config["period_days"])*1440:sales+=int(tx["amount"])
	var issues: Array=[];var distributions: Array=[];var total: int=market()._configured[market().primary.config["asset_id"]]["total_shares"]
	for i: Dictionary in native["assets"].get("primary",{}).get("issues",{}).values():
		if prefix.get(i["action_id"],{}).get("result",{}).get("accepted",false):issues.append(i["id"])
	for s: Dictionary in native["assets"].get("primary",{}).get("settlements",{}).values():
		if prefix.get(s["action_id"],{}).get("result",{}).get("accepted",false):total+=int(s["quantity"])
	for d: Dictionary in native["assets"].get("distributions",{}).get("plans",{}).values():
		if prefix.get(d["action_id"],{}).get("result",{}).get("accepted",false):distributions.append(d["id"])
	issues.sort();distributions.sort()
	var gap: int=maxi(0,int(guard["unreserved_debt"])+int(guard["future_protection"])+int(guard["cash_floor"])-int(guard["available"]))
	var quantity: int=mini(int(market().primary.config["max_new_shares"]),maxi(int(market().primary.config["minimum"]),(gap+int(market().primary.config["price"])-1)/int(market().primary.config["price"])))
	var authorities: Dictionary={"issue":market().primary.authority(config["issuer"],quantity,at),"distribution":market().distribution.authority(config["issuer"],total*int(config["per_share"]))} if adopted==null else adopted
	var controlled: bool=managed(at) if adopted==null else e.firm_manager_at(config["issuer"],at)==config["controller"] and config["controller"]!=e._world.player_state.player_id()
	var winding:=false;var finished:=false;var latest: int=-1
	for change: Dictionary in native.get("enterprise_changes",{}).values():
		if change["firm"]!=config["issuer"] or change["status"]!="APPLIED" or change["effective_minute"]>at:continue
		if change["kind"]=="finish_firm":finished=true
		if change["kind"] in ["wind_down_firm","set_firm_operating"] and change["effective_minute"]>=latest:
			if change["kind"]=="set_firm_operating" and not change["payload"]["operating"]:continue
			latest=change["effective_minute"];winding=change["kind"]=="wind_down_firm"
	var choice: String="RETAIN";var reason: String="NO_FINANCIAL_ACTION_REQUIRED";var kind: String="";var payload: Dictionary={}
	if not controlled or winding or finished:reason="NO_CURRENT_NPC_FINANCIAL_CONTROLLER"
	elif not guard["unsupported"].is_empty():reason="UNRESOLVED_OR_UNRECONCILED_RESPONSIBILITY"
	elif not projects.is_empty():
		reason="RETAIN_FOR_REAL_UNFINISHED_PROJECT"
		if gap>0:
			reason="PROJECT_FINANCING_STRATEGY_DISABLED" if not config["issue_enabled"] else "PROJECT_FUNDING_OR_RESOURCE_CONDITION_UNMET"
			var cap: int=market().primary.config["max_new_shares"]
			var contacts: bool=market().call_market.config["participants"].any(func(p: Dictionary)->bool:return p["buy"] and p["policy"]!="PLAYER" and p["actor"]!=config["issuer"])
			if config["issue_enabled"] and issues.is_empty() and cap*int(market().primary.config["price"])>=int(t["budget"]) and quantity<=cap and quantity*100<=total*int(config["max_dilution_percent"]) and missing_contacts.is_empty() and work>0 and contacts and not authorities["issue"].is_empty():
				var pc: Dictionary=market().primary.config
				payload={"asset_id":pc["asset_id"],"project_id":projects[0],"quantity":quantity,"price":pc["price"],"minimum":pc["minimum"],"valid_minutes":int(pc["duration_days"])*1440,"denomination":FormalLedgerState.DENOMINATION}
				if market().primary.terms_ok(payload,at):choice="ISSUE";reason="REAL_PROJECT_PROTECTED_CASH_GAP";kind="publish_share_issue"
	elif distributions.is_empty() and config["distribution_enabled"]:
		var dc: Dictionary=market().distribution.config;var amount: int=total*int(config["per_share"])
		reason="RETAIN_OPERATING_CASH_OR_WAIT_FOR_KNOWN_SALES"
		if sales>0 and int(guard["distributable"])>=amount+int(config["retained_surplus"]) and amount<=dc["max_total"] and at>=dc["start"] and at<dc["end"] and not authorities["distribution"].is_empty():
			choice="DISTRIBUTE";reason="COVERED_RESPONSIBILITIES_AND_DISCLOSED_RETAINED_SURPLUS";kind="declare_share_distribution"
			payload={"asset_id":dc["asset_id"],"per_share":config["per_share"],"denomination":FormalLedgerState.DENOMINATION}
	return {"accepted":true,"reason":reason,"basis":BASIS,"issuer":config["issuer"],"representative":config["controller"],"authorities":authorities,"minute":at,"command_cursor":count,"ledger_cursor":cursor,"protection":guard,"project_ids":projects,"missing_supply_contacts":missing_contacts,"recent_work_hours":work,"recent_goods_receipts":sales,"existing_issues":issues,"existing_distributions":distributions,"issued_total":total,"financing_gap":gap,"requested_financing":quantity*int(market().primary.config["price"]) if choice=="ISSUE" else 0,"full_gap_covered_by_offer":quantity*int(market().primary.config["price"])>=gap,"choice":choice,"action_kind":kind,"action_payload":payload}
func review(actor: String,p: Dictionary,at: int) -> Dictionary:
	if not enabled() or actor!=config["issuer"] or not p.is_empty() or economy().phase!="READY" or at%1440!=0 or (at/1440)%int(config["period_days"])!=0:return {"accepted":false,"reason":"NO_CORPORATE_REVIEW_BOUNDARY_OR_IDENTITY"}
	return observe(at,context(),market()._ledger._transactions.size(),economy()._commands.size())
func npc_decisions() -> void:
	elapsed_us=0
	if not enabled():return
	var e:=economy();var at: int=e._world.game_clock.total_minutes()
	if at%1440!=0 or e.day%int(config["period_days"])!=0:return
	var start:=Time.get_ticks_usec()
	var result:=e._npc_submit(config["issuer"],"review_corporate_finance",{},"corporate_review",{})
	var review_id: String=e._auto_command(config["issuer"],"review_corporate_finance",{},"finance:corporate_review")["action_id"]
	if e._commands.has(review_id) and review_id not in review_ids:review_ids.append(review_id)
	if result.get("accepted",false) and result.get("action_kind","")!="":
		e._npc_submit(config["issuer"],result["action_kind"],result["action_payload"],"corporate_financial_action",{"basis":BASIS,"review_action":e._auto_command(config["issuer"],"review_corporate_finance",{},"finance:corporate_review")["action_id"]})
	elapsed_us=Time.get_ticks_usec()-start
func validate(native: Dictionary) -> bool:
	review_ids.clear()
	var entries: Dictionary=native["commands"];var index:=0
	for id: String in entries:
		var entry: Dictionary=entries[id];var c: Dictionary=entry["envelope"]["command"];var r: Dictionary=entry["result"].duplicate(true);r.erase("decision")
		if c["kind"]=="review_corporate_finance" and r["accepted"]:
			if not enabled() or entry["envelope"]["actor"]!=config["issuer"] or not c["payload"].is_empty() or c["minute"]%1440!=0 or (c["minute"]/1440)%int(config["period_days"])!=0 or r.get("command_cursor")!=index:return fail("Corporate review identity or boundary conflict")
			var cursor: Variant=r.get("ledger_cursor")
			if not FormalLedgerState.valid_amount(cursor) or cursor>market()._ledger._transactions.size():return fail("Corporate review Ledger cursor invalid")
			for j: int in market()._ledger._transactions.size():
				var t: Dictionary=market()._ledger._transactions[j]
				if (j<cursor and t["effective_minute"]>c["minute"]) or (j>=cursor and t["effective_minute"]<c["minute"]):return fail("Corporate observation skips Ledger history")
			if not r.get("authorities") is Dictionary or not FormalLedgerState.exact_fields(r["authorities"],["issue","distribution"]):return fail("Corporate review lost authority observation")
			for operation: String in r["authorities"]:
				var proof: Variant=r["authorities"][operation]
				if not proof is Dictionary:return fail("Invalid corporate authority observation")
				if proof.is_empty():continue
				var program: Dictionary=market().primary.config if operation=="issue" else market().distribution.config
				if not economy()._cargo_fulfilment._saved_authority(proof) or proof.get("actor")!=config["controller"] or proof.get("subject")!=config["issuer"] or proof.get("target")!=config["issuer"] or proof.get("operation")!="economy.equity."+("issue" if operation=="issue" else "distribute") or proof.get("authority_id")!=program["authority_id"] or proof.get("category")!=program["asset_id"] or proof.get("minute")!=c["minute"]:return fail("Corporate review lacks separate historical authority")
				var expected_amount: int=mini(int(market().primary.config["max_new_shares"]),maxi(int(market().primary.config["minimum"]),(int(r["financing_gap"])+int(market().primary.config["price"])-1)/int(market().primary.config["price"]))) if operation=="issue" else int(r["issued_total"])*int(config["per_share"])
				if proof.get("amount")!=expected_amount:return fail("Corporate authority quantity differs from original judgment")
			if r!=observe(c["minute"],native,cursor,index,r["authorities"]):return fail("Corporate review differs from original cash, project or responsibility facts")
			review_ids.append(id)
		if entry["result"].get("decision",{}).get("basis")==BASIS:
			var review_id: String=entry["result"]["decision"].get("review_action","")
			var proof: Dictionary=entries.get(review_id,{}).get("result",{})
			if review_id==id or proof.get("command_cursor",index)>=index or proof.get("minute")!=c["minute"] or proof.get("action_kind")!=c["kind"] or proof.get("action_payload")!=c["payload"] or entry["envelope"]["actor"]!=config["issuer"]:return fail("Corporate action lacks its original operating judgment")
		index+=1
	return true
func fail(message: String) -> bool:error=message;return false
func visible(actor: String,research: bool=false) -> Dictionary:
	if not enabled():return {}
	var e:=economy();var manager: bool=e._manager_at(actor,config["issuer"],e._world.game_clock.total_minutes()) and actor!=config["issuer"]
	if not manager and not research:return {"enabled":true,"internal_observations_disclosed":false}
	var recent: Array=[]
	for id: String in review_ids.slice(maxi(0,review_ids.size()-5)):
		if e._commands.has(id):recent.append(e._commands[id].duplicate(true))
	var projects: Array=e._capital.projects.values().filter(func(p: Dictionary)->bool:return p["firm"]==config["issuer"]).duplicate(true)
	return {"enabled":true,"research_truth":research,"controller":config["controller"],"rules":config.duplicate(true),"reviews":recent,"projects":projects,"recent_company_payments":market()._ledger.own_transactions(config["issuer"],e._world.game_clock.total_minutes()-int(config["period_days"])*1440).slice(-12),"strategy_us":elapsed_us}
