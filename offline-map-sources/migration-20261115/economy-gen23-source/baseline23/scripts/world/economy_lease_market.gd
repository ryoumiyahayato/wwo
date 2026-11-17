class_name EconomyLeaseMarket
extends RefCounted
## Usage grants and fixed-term obligations only. No land, stock, wallet or clock.
const FORMAT := "economy_lease_market_v1"
const RESIDENTIAL := "RESIDENTIAL_SPACE"
const COMMERCIAL := "COMMERCIAL_PREMISES"
const TERMS := "FIRST_PERIOD_SECURED_RENT_AFTER_USE_NO_DEPOSIT"
const CONTRACT_FIELDS: Array[String] = ["id","action_id","actor","tenant","lessor","object_id","offer_id","site_id","kind","quantity","member_start","accepted_minute","start_minute","end_minute","entered_minute","ended_minute","returned_minute","last_boundary","state","reason","total","first_reserve","cash_released","rent_units","accrued","due","paid","released","permission","supply_permission","events","periods","payments","predecessor"]
var contracts: Dictionary = {}
var error: String = ""
var _ref: WeakRef
var _objects: Dictionary = {}
var _offers: Dictionary = {}
var _gates: Dictionary = {}
var _active: Dictionary = {}
var _by_subject: Dictionary = {}
var _by_object: Dictionary = {}
var _site_history: Dictionary = {}
var _site_days: Dictionary = {}
var _indexed_uses: Dictionary = {}
var _days: Dictionary = {}
var _housing: Dictionary = {}
var _payments: Dictionary = {}
var _blueprints: Dictionary = {}
var _built_assets: Dictionary = {}
var offer_changes: Dictionary = {}
var _offer_history: Dictionary = {}
var _offer_current: Dictionary = {}
var _last_offer_accept: Dictionary = {}
func economy() -> RefCounted: return _ref.get_ref()
func bind(e: RefCounted) -> void:
	_ref=weakref(e)
	for o: Dictionary in e.config.get("lease_market",{}).get("objects",[]):
		_objects[o["id"]]=o
		for site: String in o["eligible_sites"]: _gates[site]=o["id"]
	for o: Dictionary in e.config.get("lease_market",{}).get("offers",[]): _offers[o["id"]]=o
	for t:Dictionary in e.config.get("capital_investment",{}).get("templates",[]):
		if not t.has("building"):continue
		var o:=t["building"]["object"] as Dictionary
		_objects[o["id"]]=o;_blueprints[o["id"]]=t["id"]
		var offer:=t["building"]["offer"] as Dictionary;_offers[offer["id"]]=offer
		for site:String in o["eligible_sites"]:_gates[site]=o["id"]
static func valid_configuration(settings: Dictionary,spec: Dictionary) -> bool:
	if not settings.has("lease_market"): return true
	var v: Variant=settings["lease_market"].duplicate(true) if settings["lease_market"] is Dictionary else settings["lease_market"]
	if not v is Dictionary or not FormalLedgerState.exact_fields(v,["objects","offers","authorities","housing_targets","npc_policies","basis"]) or v["basis"]!="EXPLICIT_DEVELOPMENT_LEASE_MARKET": return false
	for key: String in ["objects","offers","authorities","housing_targets","npc_policies"]:
		if not v[key] is Array or v[key].size()>64: return false
	spec=spec.duplicate(true)
	for option:Dictionary in settings.get("runtime_expansions",[]):
		for entry:Dictionary in option.get("extension",{}).get("sites",[]):
			if not spec["sites"].has(entry["site"]["id"]):
				var future:Dictionary=entry["site"].duplicate(true);future["firm_id"]=entry["firm_id"];spec["sites"][future["id"]]=future
	var blueprints:Dictionary={}
	for t:Dictionary in settings.get("capital_investment",{}).get("templates",[]):
		if not t.has("building"):continue
		var b:Dictionary=t["building"]
		blueprints[b["object"]["id"]]=t["id"]
		v["objects"].append(b["object"]);v["offers"].append(b["offer"])
	var objects: Dictionary={}; var sources: Dictionary={}; var sites: Dictionary={}; var offers: Dictionary={}
	for o: Variant in v["objects"]:
		if not o is Dictionary or not FormalLedgerState.exact_fields(o,["id","place_id","kind","lessor","capacity","unit","rights_source","capital_asset_id","eligible_sites","valid_from","valid_until","capacity_basis"]): return false
		for key: String in ["id","place_id","lessor","unit","capital_asset_id"]:
			if not o[key] is String: return false
		if not str(o["id"]).begins_with("lease_object:") or objects.has(o["id"]) or not spec["firms"].has(o["lessor"]) or not EconomySliceConfig._place(o["place_id"]) or o["kind"] not in [RESIDENTIAL,COMMERCIAL] or not o["eligible_sites"] is Array or o["capacity_basis"]!=("CAPITAL_ASSET_CAPACITY_PROJECTION" if blueprints.has(o["id"]) else "DEDICATED_DEVELOPMENT_SPACE_NO_STORAGE_EQUIVALENCE"): return false
		for key: String in ["capacity","valid_from","valid_until"]:
			if not FormalLedgerState.valid_amount(o[key]): return false
		if o["capacity"]<1 or o["capacity"]>1000000 or o["valid_from"]%1440!=0 or o["valid_until"]%1440!=0 or o["valid_until"]<=o["valid_from"]: return false
		var r: Variant=o["rights_source"]
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","holder","basis","note"]) or not r["id"] is String or r["id"].is_empty() or sources.has(r["id"]) or r["holder"]!=o["lessor"] or r["basis"]!=("COMPLETED_CAPITAL_PROJECT_REQUIRED" if blueprints.has(o["id"]) else "EXPLICIT_DEVELOPMENT_INITIAL_USE_RIGHT_GRANT") or not r["note"] is String or r["note"].is_empty(): return false
		if o["kind"]==RESIDENTIAL:
			if not o["eligible_sites"].is_empty() or o["unit"]!="development_person_place": return false
		else:
			if o["eligible_sites"].is_empty() or o["capacity"]!=1 or o["unit"]!="development_exclusive_premises": return false
			for site: Variant in o["eligible_sites"]:
				if not site is String or not spec["sites"].has(site) or sites.has(site) or spec["sites"][site]["place_id"]!=o["place_id"] or spec["sites"][site]["firm_id"]==o["lessor"]: return false
				sites[site]=true
		objects[o["id"]]=o; sources[r["id"]]=true
	for o: Variant in v["offers"]:
		if not o is Dictionary or not FormalLedgerState.exact_fields(o,["id","object_id","denomination","rent_per_unit","period_days","max_days","valid_from","valid_until","known_to","notice_minute","payment_rule","cancel_rule","due_priority","billing_rule","housing_rule"]): return false
		if not o["id"] is String or offers.has(o["id"]) or not objects.has(o["object_id"]) or not FormalLedgerState.currency_id(o["denomination"]) or not o["known_to"] is Array or o["payment_rule"]!=TERMS or o["cancel_rule"]!="TENANT_MAY_END_AT_DAILY_BOUNDARY_RETURN_REQUIRED" or o["due_priority"]!="AFTER_EXISTING_WAGES_AND_DEBT_BEFORE_NEW_PROCUREMENT" or o["billing_rule"]!="CUMULATIVE_AVAILABLE_UNIT_MINUTES_FLOOR" or o["housing_rule"]!="LOCAL_AT_DAILY_BOUNDARY": return false
		for key: String in ["rent_per_unit","period_days","max_days","valid_from","valid_until","notice_minute"]:
			if not FormalLedgerState.valid_amount(o[key]): return false
		if o["rent_per_unit"]<1 or o["rent_per_unit"]>1000000 or o["period_days"]<1 or o["period_days"]>30 or o["max_days"]<o["period_days"] or o["max_days"]>365 or o["valid_until"]<=o["valid_from"]: return false
		for party: Variant in o["known_to"]:
			if not party is String: return false
			if objects[o["object_id"]]["kind"]==RESIDENTIAL:
				if not spec["actors"].has(party) and not (party=="HOST_SELECTED_PLAYER" and settings.get("host_personal_accounts",false)): return false
			elif not spec["firms"].has(party): return false
		offers[o["id"]]=o
	var seen: Dictionary={}
	for a: Variant in v["authorities"]:
		if not a is Dictionary or not FormalLedgerState.exact_fields(a,["id","firm","controller","operations","denomination","limit","start_minute","end_minute","root_authority","basis"]) or not a["id"] is String or seen.has(a["id"]) or not spec["firms"].has(a["firm"]) or not a["controller"] is String or not a["root_authority"] is String or not a["operations"] is Array or a["operations"].is_empty() or a["basis"]!="EXPLICIT_DEVELOPMENT_LEASE_AUTHORITY" or not FormalLedgerState.currency_id(a["denomination"]): return false
		for key: String in ["limit","start_minute","end_minute"]:
			if not FormalLedgerState.valid_amount(a[key]): return false
		if a["end_minute"]<=a["start_minute"]: return false
		for op: Variant in a["operations"]:
			if op not in ["rent","let","manage"]: return false
		seen[a["id"]]=true
	seen.clear()
	for t: Variant in v["housing_targets"]:
		if not t is Dictionary or not FormalLedgerState.exact_fields(t,["customer","basis","initial_housing"]) or not t["customer"] is String or seen.has(t["customer"]) or (not spec["actors"].has(t["customer"]) and not (t["customer"]=="HOST_SELECTED_PLAYER" and settings.get("host_personal_accounts",false))) or t["basis"]!="EXPLICIT_DEVELOPMENT_HOUSING_USE_TARGET" or t["initial_housing"]!="UNSPECIFIED_NOT_A_HOMELESSNESS_CLASSIFICATION": return false
		seen[t["customer"]]=true
	for p: Variant in v["npc_policies"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["tenant","offer_ids","quantity","term_days","max_total","priority","auto_handover","auto_return_on_end","no_new_if_overdue","basis"]) or not p["offer_ids"] is Array or p["offer_ids"].size()>8 or p["priority"] not in ["BEFORE_OPTIONAL_SERVICES_AND_GOODS","AFTER_GOODS"] or p["basis"]!="EXPLICIT_DEVELOPMENT_LEASE_DEMAND": return false
		if not spec["firms"].has(p["tenant"]) and (not spec["actors"].has(p["tenant"]) or spec["actors"][p["tenant"]]["control"]!="automatic"): return false
		for key: String in ["quantity","term_days","max_total"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]<1: return false
		for key: String in ["auto_handover","auto_return_on_end","no_new_if_overdue"]:
			if not p[key] is bool: return false
		for id: Variant in p["offer_ids"]:
			if not offers.has(id) or p["tenant"] not in offers[id]["known_to"]: return false
	return true
func validate_host() -> bool:
	for o: Dictionary in _objects.values():
		if not economy()._world.spatial_catalog.has_place(o["place_id"]) or economy()._cargo_fulfilment._host_organization(o["lessor"]).is_empty(): return _fail("Lease object lacks admitted place or commercial lessor")
	return true
func _permission(actor: String,firm: String,op: String,currency: String,amount: int,obj: String) -> Dictionary:
	var e:=economy(); var now: int=e._world.game_clock.total_minutes()
	if not e._manager(actor,firm): return {"ok":false,"reason":"NOT_CURRENT_LEASE_ENTERPRISE_MANAGER"}
	var organization: String=e._cargo_fulfilment._host_organization(firm)
	if organization.is_empty() or not e._world.organization_state.is_organization_active(organization): return {"ok":false,"reason":"LEASE_ORGANIZATION_NOT_ACTIVE"}
	for a: Dictionary in e.config.get("lease_market",{}).get("authorities",[]):
		if a["firm"]!=firm or a["controller"]!=actor or op not in a["operations"] or currency!=a["denomination"] or amount>a["limit"] or now<a["start_minute"] or now>=a["end_minute"]: continue
		var proof:={"ok":true,"actor":actor,"firm":firm,"operation":op,"amount":amount,"denomination":currency,"minute":now,"authority_id":a["id"],"source":a.duplicate(true)}
		if not a["root_authority"].is_empty():
			var operation:="economy.procure" if op=="rent" else "economy.lease."+op
			var category:="lease:"+str(_objects[obj]["kind"]).to_lower()
			var request:={"operation":operation,"target":obj,"place":_objects[obj]["place_id"],"category":category,"amount":amount}
			var ctx: Dictionary=e._cargo_fulfilment._available_context(actor,firm,request,a["root_authority"])
			var checked: Dictionary=e._cargo_fulfilment._authorize(actor,firm,operation,obj,request["place"],category,amount,{firm+"|"+operation+"|"+category:ctx})
			if not checked["ok"] or checked["proof"].get("authority_id")!=a["root_authority"]: continue
			proof["root_proof"]=checked["proof"]
		return proof
	return {"ok":false,"reason":"NO_EXPLICIT_LEASE_"+op.to_upper()+"_AUTHORITY"}
func _asset_available(o: Dictionary,minute: int) -> bool:
	var id:=_asset_id(o)
	if id.is_empty(): return not _blueprints.has(o["id"])
	var a: Dictionary=economy()._capital.assets.get(id,{})
	if a.is_empty() or a["firm"]!=o["lessor"] or economy()._place(a["site_id"])!=o["place_id"]: return false
	var state:=""
	for event: Dictionary in a["events"]:
		if event["minute"]<=minute: state=event["status"]
	return state=="ACTIVE"
func _available(o: Dictionary,minute: int) -> bool:
	return minute>=o["valid_from"] and minute<o["valid_until"] and _asset_available(o,minute)
func _index(c: Dictionary) -> void:
	_last_offer_accept[c["offer_id"]]=maxi(int(_last_offer_accept.get(c["offer_id"],-1)),int(c["accepted_minute"]))
	for party: String in [c["tenant"],c["lessor"]]:
		if not _by_subject.has(party): _by_subject[party]=[]
		if c["id"] not in _by_subject[party]: _by_subject[party].append(c["id"])
	if not _by_object.has(c["object_id"]): _by_object[c["object_id"]]={}
	if not c["site_id"].is_empty():
		if not _site_history.has(c["site_id"]): _site_history[c["site_id"]]=[]
		if c["id"] not in _site_history[c["site_id"]]: _site_history[c["site_id"]].append(c["id"])
	if c["entered_minute"]>=0 and not c["site_id"].is_empty() and not _indexed_uses.has(c["id"]):
		_indexed_uses[c["id"]]=true
		if not _site_days.has(c["site_id"]): _site_days[c["site_id"]]={}
		for date: int in range(int(c["entered_minute"])/1440,int(c["end_minute"])/1440):
			if not _site_days[c["site_id"]].has(date): _site_days[c["site_id"]][date]={}
			_site_days[c["site_id"]][date][c["id"]]=true
	if c["state"] not in ["CANCELLED","RETURNED"] or c["paid"]<c["due"]: _active[c["id"]]=true
	else: _active.erase(c["id"])
	if c["state"] in ["RESERVED","ACTIVE","ENDED_OCCUPIED"]: _by_object[c["object_id"]][c["id"]]=true
	else: _by_object[c["object_id"]].erase(c["id"])
func available(obj: String) -> int:
	var used:=0
	for id: String in _by_object.get(obj,{}): used+=int(contracts[id]["quantity"])
	return maxi(0,_physical_capacity(obj,economy()._world.game_clock.total_minutes())-used) if _available(_objects[obj],economy()._world.game_clock.total_minutes()) else 0
func _member_start(tenant: String,q: int) -> int:
	var spans: Array[Vector2i]=[]
	for id: String in _active:
		var c:=contracts[id] as Dictionary
		if c["tenant"]==tenant and c["kind"]==RESIDENTIAL and c["state"] not in ["CANCELLED","RETURNED"]: spans.append(Vector2i(c["member_start"],int(c["member_start"])+int(c["quantity"])))
	spans.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.x<b.x)
	var cursor:=0
	for span: Vector2i in spans:
		if span.x-cursor>=q: return cursor
		cursor=maxi(cursor,span.y)
	return cursor if cursor+q<=int(economy()._actors[tenant]["members"]) else -1
func _party(actor: String,tenant: String) -> bool:
	var e:=economy()
	if e._spec["firms"].has(tenant): return e._manager(actor,tenant)
	return actor==tenant and e._actors.has(tenant) and e.subject_active_at(tenant,e._world.game_clock.total_minutes()) and (not e._declared_named(tenant) or e._world.person_overlay.is_alive(tenant))
func _targeted(actor: String) -> bool:
	for t: Dictionary in economy().config.get("lease_market",{}).get("housing_targets",[]):
		if t["customer"]==actor: return true
	return false
func snapshot() -> Dictionary:
	var result:={"format":FORMAT,"contracts":contracts.duplicate(true)}
	if not offer_changes.is_empty():result["offer_changes"]=offer_changes.duplicate(true)
	return result
func _reject(reason: String) -> Dictionary: return {"accepted":false,"reason":reason}
func _fail(reason: String) -> bool: error=reason; return false

func request(actor:String,kind:String,p:Dictionary,action:String,preview:bool=false)->Dictionary:
	var e:=economy();var now:int=e._world.game_clock.total_minutes()
	if kind=="request_lease":return _accept(actor,p,action,preview)
	if kind=="set_lease_offer":return _set_offer(actor,p,action)
	if not FormalLedgerState.exact_fields(p,["lease_id"]) or not contracts.has(p.get("lease_id")):return _reject("UNKNOWN_LEASE")
	var c:=contracts[p["lease_id"]] as Dictionary;var o:=_objects[c["object_id"]] as Dictionary
	if not _party(actor,c["tenant"]):return _reject("NOT_CURRENT_LEASE_TENANT_OR_MANAGER")
	if now%1440!=0:return _reject("LEASE_ACTION_REQUIRES_DAILY_BOUNDARY")
	var proof:Dictionary={}
	if kind!="pay_lease" and c["kind"]==COMMERCIAL:
		proof=_permission(actor,c["tenant"],"manage",_offers[c["offer_id"]]["denomination"],0,c["object_id"])
		if not proof["ok"]:return _reject(proof["reason"])
	if kind=="handover_lease":
		if c["state"]!="RESERVED" or now<c["start_minute"] or now>=c["end_minute"] or not _available(o,now):return _reject("LEASE_NOT_DELIVERABLE_NOW")
		if c["kind"]==RESIDENTIAL and not e._at_place(c["tenant"],o["place_id"]):return _reject("HOUSING_REQUIRES_ACTUAL_LOCAL_PRESENCE")
		c["entered_minute"]=now;c["last_boundary"]=now;c["state"]="ACTIVE";c["reason"]=""
	elif kind=="end_lease":
		if c["state"] not in ["RESERVED","ACTIVE"]:return _reject("LEASE_USE_ALREADY_ENDED")
		_settle(c,now);_end(c,now)
	elif kind=="return_lease":
		if c["state"]!="ENDED_OCCUPIED":return _reject("END_USE_BEFORE_ACTUAL_RETURN")
		var reason:=return_reason(c)
		if not reason.is_empty():return _reject(reason)
		c["returned_minute"]=now;c["state"]="RETURNED";c["reason"]="USE_RETURNED_RENT_DEBT_RETAINED"
	elif kind=="pay_lease":
		if c["due"]<=c["paid"]:return _reject("NO_DUE_RENT")
		if e._wind_down.controls(c["tenant"]) and e._firm_winding_down(c["tenant"]):
			var amount:=mini(int(c["due"])-int(c["paid"]),e._world.ledger_state.available_balance(e._account(c["tenant"],_offers[c["offer_id"]]["denomination"])))
			var result: Dictionary=e._wind_down.request(actor,{"firm":c["tenant"],"kind":"RENT","reference":c["id"],"amount":amount},action)
			if result["accepted"]: result["paid_delta"]=result["amount"]
			return result
		var before:=int(c["paid"]);_pay(c,now,FormalLedgerState.MAX_AMOUNT,false)
		_index(c)
		return {"accepted":c["paid"]>before,"reason":"RENT_PAID" if c["paid"]>before else "RENT_REMAINS_PAYABLE_NO_CASH","paid_delta":int(c["paid"])-before}
	else:return _reject("UNKNOWN_LEASE_ACTION")
	c["events"].append({"id":action,"kind":kind,"minute":now,"actor":actor,"permission":proof})
	_pay(c,now);_index(c)
	return {"accepted":true,"reason":"LEASE_"+str(c["state"]),"lease_id":c["id"]}
func _accept(actor:String,p:Dictionary,action:String,preview:bool)->Dictionary:
	var e:=economy();var now:int=e._world.game_clock.total_minutes()
	if not EconomySliceConfig._fields(p,["tenant","offer_id","site_id","quantity","term_days","start_minute","max_total"],["predecessor"]) or not p["tenant"] is String or not _offers.has(p.get("offer_id")) or not _party(actor,p["tenant"]):return _reject("INVALID_LEASE_TENANT_OR_ACTION")
	var quote:=_offers[p["offer_id"]] as Dictionary;var obj:=_objects[quote["object_id"]] as Dictionary
	for key:String in ["quantity","term_days","start_minute","max_total"]:
		if not FormalLedgerState.valid_amount(p[key]):return _reject("INVALID_LEASE_QUANTITY_OR_TIME")
	if now%1440!=0 or p["start_minute"]%1440!=0 or p["start_minute"]<now or p["start_minute"]>now+30*1440 or p["term_days"]<quote["period_days"] or p["term_days"]>quote["max_days"] or p["quantity"]<1 or p["quantity"]>obj["capacity"]:return _reject("LEASE_REQUIRES_FINITE_DAILY_TERM_AND_SPACE")
	var end:=int(p["start_minute"])+int(p["term_days"])*1440
	if p["tenant"] in quote["known_to"] and now>=quote["notice_minute"] and _blueprints.has(obj["id"]) and not _asset_available(obj,now):
		return _reject("BUILDING_NOT_COMPLETED_OR_DELIVERED" if _asset_id(obj).is_empty() else "BUILDING_UNAVAILABLE_EXISTING_LEASE_DUTIES_RETAINED")
	if end>FormalLedgerState.MAX_AMOUNT or p["start_minute"]<obj["valid_from"] or end>obj["valid_until"] or now<quote["valid_from"] or now>=quote["valid_until"] or now<quote["notice_minute"] or not _offer_enabled_at(quote["id"],now) or p["tenant"] not in quote["known_to"] or not _available(obj,now):return _reject("NO_CURRENT_KNOWN_VALID_LEASE_OFFER")
	if p["quantity"]>available(obj["id"]):return _reject("LEASE_SPACE_STILL_RESERVED_OR_NOT_RETURNED")
	var member:=-1;var permission:Dictionary={}
	var total:=int(quote["rent_per_unit"])*int(p["quantity"])*int(p["term_days"])/int(quote["period_days"])
	if total<1 or not FormalLedgerState.valid_amount(total) or total>p["max_total"]:return _reject("LOCKED_LEASE_RENT_EXCEEDS_LIMIT")
	if obj["kind"]==RESIDENTIAL:
		if not e._actors.has(p["tenant"]) or p["site_id"]!="" or not _targeted(p["tenant"]):return _reject("RESIDENT_HOUSING_SCOPE_NOT_CONFIGURED")
		member=_member_start(p["tenant"],p["quantity"])
		if member<0:return _reject("HOUSING_EXCEEDS_UNCOMMITTED_MEMBER_SHARES")
		permission={"basis":"OWN_RESIDENT_IDENTITY_AND_LEDGER_ACCOUNT","actor":actor,"account_id":e._account(p["tenant"],quote["denomination"])}
	else:
		if not p["site_id"] is String or not e._spec["sites"].has(p["site_id"]) or p["site_id"] not in obj["eligible_sites"] or e._owner(p["site_id"])!=p["tenant"] or p["quantity"]!=1 or e.site_closed(p["site_id"]) or e._firm_winding_down(p["tenant"]):return _reject("LEASE_DOES_NOT_ADMIT_THIS_EXISTING_SITE")
		permission=_permission(actor,p["tenant"],"rent",quote["denomination"],total,obj["id"])
		if not permission["ok"]:return _reject(permission["reason"])
	if not e._firm_operating(obj["lessor"]) or e._firm_winding_down(obj["lessor"]) or e.firm_finished(obj["lessor"]):return _reject("LESSOR_NOT_ACCEPTING_NEW_LEASES")
	var supply:=_permission(e.firm_manager_at(obj["lessor"],now),obj["lessor"],"let",quote["denomination"],total,obj["id"])
	if not supply["ok"]:return _reject(supply["reason"])
	var predecessor:Variant=p.get("predecessor","")
	if not predecessor is String:return _reject("INVALID_PREVIOUS_LEASE")
	if not predecessor.is_empty():
		var previous:Dictionary=contracts.get(predecessor,{})
		if previous.is_empty() or previous["tenant"]!=p["tenant"] or previous["object_id"]!=obj["id"] or previous["state"]!="RETURNED":return _reject("RENEWAL_REQUIRES_PRIOR_LEASE_RETURN_NEW_TERMS")
	var first:=mini(total,int(quote["rent_per_unit"])*int(p["quantity"]))
	var account:String=e._account(p["tenant"],quote["denomination"])
	for party: String in [p["tenant"],obj["lessor"]]:
		var actual: Dictionary=e._world.ledger_state.account(e._account(party,quote["denomination"]))
		if actual.get("owner_id")!=party or actual.get("denomination")!=quote["denomination"]:return _reject("LEASE_REQUIRES_EXISTING_PARTY_CURRENCY_ACCOUNTS")
	if e._world.ledger_state.account(account).get("owner_id")!=p["tenant"] or e._world.ledger_state.available_balance(account)<first:return _reject("FIRST_LEASE_PERIOD_CASH_NOT_AVAILABLE")
	var category:="lease:"+str(obj["kind"]).to_lower()
	var budget:Dictionary=e._budgets.plan(p["tenant"],quote["denomination"],category,total,now)
	if not budget["ok"]:return _reject(budget["reason"])
	if budget.has("rule_id"):
		var rule:=e._budgets.rule(budget["rule_id"]) as Dictionary
		if permission.get("authority_id")!=rule["root_authority"] and permission.get("root_proof",{}).get("authority_id")!=rule["root_authority"]:return _reject("LEASE_BUDGET_REQUIRES_ITS_ORIGINAL_AUTHORIZATION")
	if preview:return {"accepted":true,"reason":"FIRST_PERIOD_SECURED_FUTURE_RENT_CAN_BECOME_PAYABLE"}
	var id:="lease:"+action
	if not e._world.ledger_state.reserve(id,account,first):return _reject("FIRST_LEASE_PERIOD_CASH_NOT_AVAILABLE")
	var plans:Array[Dictionary]=[budget]
	if not e._budgets.commit(id,plans):
		var undone:bool=e._world.ledger_state.release(id,first)
		assert(undone)
		return _reject("LEASE_BUDGET_CHANGED")
	contracts[id]={"id":id,"action_id":action,"actor":actor,"tenant":p["tenant"],"lessor":obj["lessor"],"object_id":obj["id"],"offer_id":quote["id"],"site_id":p["site_id"],"kind":obj["kind"],"quantity":p["quantity"],"member_start":member,"accepted_minute":now,"start_minute":p["start_minute"],"end_minute":end,"entered_minute":-1,"ended_minute":-1,"returned_minute":-1,"last_boundary":-1,"state":"RESERVED","reason":"AWAITING_ACTUAL_HANDOVER","total":total,"first_reserve":first,"cash_released":0,"rent_units":0,"accrued":0,"due":0,"paid":0,"released":0,"permission":permission,"supply_permission":supply,"events":[],"periods":[],"payments":[],"predecessor":predecessor}
	_index(contracts[id])
	return {"accepted":true,"reason":"LEASE_RESERVED_NOT_YET_HANDED_OVER","lease_id":id,"locked_total":total,"first_period_reserved":first}
func _add_day(c:Dictionary,date:int)->void:
	for party:String in [c["tenant"],c["lessor"]]:
		if not _days.has(party):_days[party]={}
		if not _days[party].has(date):_days[party][date]={}
		_days[party][date][c["id"]]=true
func _settle(c:Dictionary,now:int)->void:
	if c["entered_minute"]<0:return
	var until:=mini(now,int(c["end_minute"]))
	if c["ended_minute"]>=0:until=mini(until,int(c["ended_minute"]))
	var quote:=_offers[c["offer_id"]] as Dictionary;var obj:=_objects[c["object_id"]] as Dictionary
	while c["last_boundary"]<until:
		var start:=int(c["last_boundary"]);var end:=mini(until,start+1440)
		var usable:=_available(obj,end-1)
		var units:=int(c["quantity"])*(end-start) if usable else 0
		c["rent_units"]+=units
		var next:=int(quote["rent_per_unit"])*int(c["rent_units"])/(int(quote["period_days"])*1440)
		var housing:=int(c["quantity"]) if usable and c["kind"]==RESIDENTIAL and economy()._at_place(c["tenant"],obj["place_id"]) else 0
		if (end-int(c["start_minute"]))%(int(quote["period_days"])*1440)==0 or end==c["end_minute"]:c["due"]=next
		var row:={"from":start,"to":end,"usable":usable,"unit_minutes":units,"rent_delta":next-int(c["accrued"]),"cumulative_accrued":next,"due":c["due"],"housing_people":housing}
		c["periods"].append(row);c["accrued"]=next;c["last_boundary"]=end
		_add_day(c,end/1440)
		if housing>0:_housing_day(c,end/1440,housing)
func _housing_day(c:Dictionary,date:int,quantity:int)->void:
	if not _housing.has(c["tenant"]):_housing[c["tenant"]]={}
	_housing[c["tenant"]][date]=int(_housing[c["tenant"]].get(date,0))+quantity
func _cash_left(c:Dictionary)->int:
	var remaining:=int(c["first_reserve"])-int(c["cash_released"])
	for row:Dictionary in c["payments"]:remaining-=int(row["release_amount"])
	return remaining
func _end(c:Dictionary,now:int)->void:
	c["ended_minute"]=now;c["due"]=c["accrued"]
	c["state"]="ENDED_OCCUPIED" if c["entered_minute"]>=0 else "CANCELLED"
	c["released"]=int(c["total"])-int(c["accrued"])
	var left:=_cash_left(c)
	if left>0:
		var freed:bool=economy()._world.ledger_state.release(c["id"],left)
		assert(freed)
		c["cash_released"]+=left
	var settled:bool=economy()._budgets.settle("lease_end:"+str(c["id"]),c["id"],c["paid"],c["released"],c["total"])
	assert(settled)
	c["reason"]="RETURN_REQUIRED_NO_AUTOMATIC_EVICTION" if c["state"]=="ENDED_OCCUPIED" else "UNUSED_LEASE_ENDED"
func _pay(c:Dictionary,now:int,limit:int=FormalLedgerState.MAX_AMOUNT,automatic:bool=true)->void:
	var due:=mini(limit,int(c["due"])-int(c["paid"]))
	if due<=0:return
	var e:=economy();var currency:String=_offers[c["offer_id"]]["denomination"]
	var account:String=e._account(c["tenant"],currency);var held:=_cash_left(c)
	var free:=maxi(0,e._world.ledger_state.available_balance(account))
	if automatic and e._wind_down.controls(c["tenant"]) and e._firm_winding_down(c["tenant"]): free=0
	var pay:=mini(due,free+held)
	if pay<1:c["reason"]="RENT_PAYABLE_CASH_NOT_AVAILABLE";return
	var release:=mini(pay,held);var releases:Dictionary={}
	if release>0:releases[c["id"]]=release
	var id:="lease_payment:"+str(c["id"])+":"+str(int(c["paid"])+pay)
	var legs:Array[Dictionary]=[{"transaction_id":id,"from_account_id":account,"to_account_id":e._account(c["lessor"],currency),"amount":pay,"kind":"lease_rent","reference_id":c["id"]}]
	if not e._world.ledger_state.batch_payment(id,legs,now,releases):c["reason"]="RENT_PAYABLE_"+str(e._world.ledger_state.error);return
	c["paid"]+=pay;c["payments"].append({"id":id,"minute":now,"amount":pay,"cumulative_paid":c["paid"],"release_amount":release});_payments[id]=c["id"]
	_add_day(c,now/1440)
	var settled:bool=e._budgets.settle(id,c["id"],c["paid"],c["released"],c["total"])
	assert(settled)
func advance_day()->void:
	var now:int=economy()._world.game_clock.total_minutes()
	for id:String in _active.keys():
		var c:=contracts[id] as Dictionary
		_settle(c,now)
		if c["ended_minute"]<0 and now>=c["end_minute"]:_end(c,c["end_minute"])
		_pay(c,now);_index(c)
func site_allowed(site:String,minute:int=-1)->bool:
	if not _gates.has(site):return true
	if minute<0:minute=economy()._world.game_clock.total_minutes()
	var ids: Dictionary=_site_days.get(site,{}).get(minute/1440,{})
	for id:String in ids:
		var c:=contracts[id] as Dictionary
		if c["site_id"]==site and c["entered_minute"]>=0 and minute>=c["entered_minute"] and minute<c["end_minute"] and (c["ended_minute"]<0 or minute<c["ended_minute"]) and _available(_objects[c["object_id"]],minute):return true
	return false
func return_reason(c:Dictionary)->String:
	if c["kind"]==RESIDENTIAL:return "" if economy()._at_place(c["tenant"],_objects[c["object_id"]]["place_id"]) else "HOUSING_RETURN_REQUIRES_LOCAL_TENANT"
	return economy()._site_close_reason(c["site_id"],false)
func keeper_reason(subject:String)->String:
	for id:String in _active:
		var c:=contracts[id] as Dictionary
		if subject in [c["tenant"],c["lessor"],c["site_id"]]:return "LEASE_OCCUPANCY_OR_RENT_OBLIGATION_REQUIRES_SETTLEMENT"
	return ""
func cash_reservations()->Dictionary:
	var rows:Dictionary={}
	for c:Dictionary in contracts.values():
		var amount:=_cash_left(c)
		if amount>0:rows[c["id"]]={"account_id":economy()._account(c["tenant"],_offers[c["offer_id"]]["denomination"]),"amount":amount}
	return rows
func budget_contracts()->Dictionary:
	var rows:Dictionary={}
	for c:Dictionary in contracts.values():rows[c["id"]]={"id":c["id"],"kind":"LEASE","buyer":c["tenant"],"denomination":_offers[c["offer_id"]]["denomination"],"accepted_minute":c["accepted_minute"],"category":"lease:"+str(c["kind"]).to_lower(),"price":1,"quantity":c["total"],"delivered":c["paid"],"cancelled":c["released"],"route_legs":[]}
	return rows

func housing_view(actor:String)->Dictionary:
	if not _targeted(actor) or not economy()._actors.has(actor):return {}
	var now:int=economy()._world.game_clock.total_minutes();var usable:=0;var occupied:=0
	for id:String in _active:
		var c:=contracts[id] as Dictionary
		if c["tenant"]!=actor or c["kind"]!=RESIDENTIAL:continue
		if c["entered_minute"]>=0 and c["returned_minute"]<0:occupied+=int(c["quantity"])
		if c["state"]=="ACTIVE" and now<c["end_minute"] and _available(_objects[c["object_id"]],now) and economy()._at_place(actor,_objects[c["object_id"]]["place_id"]):usable+=int(c["quantity"])
	var people:=int(economy()._actors[actor]["members"])
	return {"required_people":people,"current_usable_people":usable,"last_day_satisfied":int(_housing.get(actor,{}).get(economy().day,0)),"uncovered_target_people":people-usable,"retained_occupancy":occupied,"day":economy().day,"basis":"EXPLICIT_TARGET_LOCAL_USABLE_RIGHT_NOT_HOMELESSNESS_OR_RESIDENCE_REGISTRATION"}
func finance_view(subject:String,window:int)->Dictionary:
	var result:={"rent_incurred":{},"rent_paid":{},"rent_payable":{},"rent_income_fulfilled":{},"rent_cash_received":{},"rent_receivable":{},"site_expenses":{},"incurred_not_yet_due":{},"future_unearned_commitment":{},"linked_asset_maintenance":{},"deposits":"NOT_CONFIGURED","prepayment":"NOT_SUPPORTED_FIRST_PERIOD_IS_CASH_RESERVATION","basis":"PERIOD_USAGE_RENT_SEPARATE_FROM_DIRECT_PRODUCT_COST_NOT_NET_PROFIT"}
	var first:=maxi(0,economy().day-window+1);var ids:Dictionary={}
	for date:int in range(first,economy().day+1):
		for id:String in _days.get(subject,{}).get(date,{}):ids[id]=true
	for id:String in _active:
		if subject in [contracts[id]["tenant"],contracts[id]["lessor"]]:ids[id]=true
	for id:String in ids:
		var c:=contracts[id] as Dictionary;var currency:String=_offers[c["offer_id"]]["denomination"]
		var incurred:=0;var paid:=0
		for row:Dictionary in c["periods"]:
			if row["to"]>=first*1440:incurred+=int(row["rent_delta"])
		for row:Dictionary in c["payments"]:
			if row["minute"]>=first*1440:paid+=int(row["amount"])
		for key:String in (["rent_incurred","rent_paid","rent_payable"] if c["tenant"]==subject else ["rent_income_fulfilled","rent_cash_received","rent_receivable"]):
			var amount:=incurred if key in ["rent_incurred","rent_income_fulfilled"] else paid if key in ["rent_paid","rent_cash_received"] else int(c["due"])-int(c["paid"])
			result[key][currency]=int(result[key].get(currency,0))+amount
		for field:String in ["incurred_not_yet_due","future_unearned_commitment"]:
			var amount:=int(c["accrued"])-int(c["due"]) if field=="incurred_not_yet_due" else int(c["total"])-int(c["accrued"])-int(c["released"])
			result[field][currency]=int(result[field].get(currency,0))+amount
		var asset:String=_asset_id(_objects[c["object_id"]])
		if subject==c["lessor"] and not asset.is_empty() and economy()._capital.assets.has(asset):
			result["linked_asset_maintenance"][asset]=economy()._costs.asset_cost(asset)["maintenance_cost"] if economy()._costs.enabled else {"unknown":["COST_ACCOUNTING_NOT_ENABLED"]}
		if c["tenant"]==subject and not c["site_id"].is_empty():
			if not result["site_expenses"].has(c["site_id"]):result["site_expenses"][c["site_id"]]={}
			var values:=result["site_expenses"][c["site_id"]] as Dictionary
			values[currency]=int(values.get(currency,0))+incurred
	return result
func quotes(subject:String)->Array[Dictionary]:
	var result:Array[Dictionary]=[];var now:int=economy()._world.game_clock.total_minutes()
	for q:Dictionary in _offers.values():
		if subject not in q["known_to"] or now<q["notice_minute"]:continue
		var o:=_objects[q["object_id"]] as Dictionary
		result.append({"id":q["id"],"object_id":o["id"],"kind":o["kind"],"place_id":o["place_id"],"lessor":o["lessor"],"unit":o["unit"],"available":available(o["id"]),"rent_per_unit":q["rent_per_unit"],"period_days":q["period_days"],"max_days":q["max_days"],"denomination":q["denomination"],"valid":now>=q["valid_from"] and now<q["valid_until"] and _available(o,now) and _offer_enabled_at(q["id"],now),"capital_asset_id":_asset_id(o),"rights_source":o["rights_source"].duplicate(true)})
	return result
func view(actor:String,tenant:String,site:String="")->Dictionary:
	var e:=economy()
	if not _party(actor,tenant):return {}
	var result:={"enabled":false,"quotes":quotes(tenant),"contracts":[],"actions":[],"housing":housing_view(tenant),"finance":finance_view(tenant,7)}
	result["enabled"]=not result["quotes"].is_empty() or _by_subject.has(tenant)
	for q:Dictionary in _offers.values():
		var o:=_objects[q["object_id"]] as Dictionary
		if o["lessor"]!=tenant:continue
		result["enabled"]=true
		var permission:=_permission(actor,tenant,"let",q["denomination"],0,o["id"])
		result["actions"].append({"kind":"set_lease_offer","payload":{"offer_id":q["id"],"enabled":not _offer_enabled_at(q["id"],e._world.game_clock.total_minutes())},"label":("暂停出租报价 " if _offer_enabled_at(q["id"],e._world.game_clock.total_minutes()) else "恢复约定出租报价 ")+str(o["place_id"]),"can_execute":permission["ok"],"reason":permission.get("reason","EXISTING_LEASES_REMAIN_UNCHANGED")})
	for q:Dictionary in result["quotes"]:
		var p:={"tenant":tenant,"offer_id":q["id"],"site_id":site if q["kind"]==COMMERCIAL else "","quantity":1,"term_days":mini(q["max_days"],int(q["period_days"])*2),"start_minute":e._world.game_clock.total_minutes(),"max_total":int(q["rent_per_unit"])*2}
		var checked:=_accept(actor,p,"",true)
		result["actions"].append({"kind":"request_lease","payload":p,"label":"申请 "+str(q["place_id"])+" · "+str(q["rent_per_unit"])+" / "+str(q["period_days"])+"日","can_execute":checked["accepted"],"reason":checked["reason"]})
	for id:String in _by_subject.get(tenant,[]).slice(-8):
		var c:=contracts[id] as Dictionary
		var row:=c.duplicate(true);row.erase("permission");row.erase("supply_permission")
		for event:Dictionary in row["events"]:event.erase("permission")
		row["unavailable_periods"]=c["periods"].filter(func(period:Dictionary)->bool:return not period["usable"]).size()
		row["facility_use_dispute"]="NO_AUTOMATIC_REFUND_OR_COMPENSATION" if row["unavailable_periods"]>0 else ""
		row["asset_available"]=_asset_available(_objects[c["object_id"]],e._world.game_clock.total_minutes());row["place_id"]=_objects[c["object_id"]]["place_id"];row["denomination"]=_offers[c["offer_id"]]["denomination"];row["payable"]=int(c["due"])-int(c["paid"])
		result["contracts"].append(row)
		if c["tenant"]!=tenant:continue
		var action:="handover_lease" if c["state"]=="RESERVED" else "end_lease" if c["state"]=="ACTIVE" else "return_lease" if c["state"]=="ENDED_OCCUPIED" else ""
		if not action.is_empty():result["actions"].append({"kind":action,"payload":{"lease_id":id},"label":{"handover_lease":"确认实际交付","end_lease":"按条款结束未来使用","return_lease":"交还空间"}[action],"can_execute":e._world.game_clock.total_minutes()%1440==0,"reason":return_reason(c) if action=="return_lease" else "ACTUAL_SITE_AUTHORITY_AND_TIME_RECHECK_REQUIRED"})
		if c["state"]=="RESERVED":result["actions"].append({"kind":"end_lease","payload":{"lease_id":id},"label":"取消尚未交付的租约","can_execute":e._world.game_clock.total_minutes()%1440==0,"reason":"RELEASE_UNUSED_COMMITMENT"})
		if row["payable"]>0:result["actions"].append({"kind":"pay_lease","payload":{"lease_id":id},"label":"支付已到期租金","can_execute":true,"reason":"EXISTING_OBLIGATION_REAL_CASH_ONLY"})
		if c["state"]=="RETURNED":
			var q:=_offers[c["offer_id"]] as Dictionary
			var again:={"tenant":tenant,"offer_id":q["id"],"site_id":c["site_id"],"quantity":c["quantity"],"term_days":mini(int(q["max_days"]),int(q["period_days"])*2),"start_minute":e._world.game_clock.total_minutes(),"max_total":int(q["rent_per_unit"])*int(c["quantity"])*2,"predecessor":id}
			var check:=_accept(actor,again,"",true)
			result["actions"].append({"kind":"request_lease","payload":again,"label":"交还后按当前条款重新承租","can_execute":check["accepted"],"reason":check["reason"]})
	return result
func npc_decisions(priority:String)->void:
	var e:=economy();var now:int=e._world.game_clock.total_minutes()
	for p:Dictionary in e.config.get("lease_market",{}).get("npc_policies",[]):
		if p["priority"]!=priority:continue
		var tenant:=str(p["tenant"]);var actor:String=e.firm_manager_at(tenant,now) if e._spec["firms"].has(tenant) else tenant
		if (actor!=tenant and not (e._assets.corporate.enabled() and e._assets.corporate.config["issuer"]==tenant and e._assets.corporate.managed(now))) or not _party(actor,tenant):continue
		var occupied:=false;var overdue:=false
		for id:String in _active.keys():
			var c:=contracts[id] as Dictionary
			if c["tenant"]!=tenant:continue
			if c["due"]>c["paid"]:overdue=true
			if c["state"] in ["RESERVED","ACTIVE","ENDED_OCCUPIED"]:occupied=true
			if c["state"]=="RESERVED" and p["auto_handover"] and now>=c["start_minute"]:e._accept(actor,e._auto_command(actor,"handover_lease",{"lease_id":id},id),true)
			elif c["state"]=="ENDED_OCCUPIED" and p["auto_return_on_end"] and return_reason(c).is_empty():e._accept(actor,e._auto_command(actor,"return_lease",{"lease_id":id},id),true)
		if occupied or (overdue and p["no_new_if_overdue"]) or (e._spec["firms"].has(tenant) and e._firm_winding_down(tenant)):continue
		for quote:Dictionary in quotes(tenant):
			if quote["id"] not in p["offer_ids"] or not quote["valid"]:continue
			var obj:=_objects[quote["object_id"]] as Dictionary;var site:=""
			if obj["kind"]==COMMERCIAL:
				for id:String in obj["eligible_sites"]:
					if e._spec["sites"].has(id) and e._owner(id)==tenant:site=id;break
				if site.is_empty():
					_prepare_rental_site(actor,tenant,obj["eligible_sites"])
					continue
			var payload:={"tenant":tenant,"offer_id":quote["id"],"site_id":site,"quantity":p["quantity"],"term_days":p["term_days"],"start_minute":now,"max_total":p["max_total"]}
			var accepted:Dictionary=e._accept(actor,e._auto_command(actor,"request_lease",payload,quote["id"]),true)
			if accepted.get("accepted",false):
				if p["auto_handover"]:e._accept(actor,e._auto_command(actor,"handover_lease",{"lease_id":accepted["lease_id"]},accepted["lease_id"]),true)
				break

func _command(saved:Dictionary,id:String,actor:String,kind:String,minute:int)->Dictionary:
	var c:Dictionary=saved.get("commands",{}).get(id,{})
	if not c.get("result",{}).get("accepted",false) or c.get("envelope",{}).get("actor")!=actor or c["envelope"]["command"].get("kind")!=kind or c["envelope"]["command"].get("minute")!=minute:return {}
	return c["envelope"]["command"]
func _party_at(actor:String,tenant:String,minute:int)->bool:
	var e:=economy()
	return e._manager_at(actor,tenant,minute) if e._spec["firms"].has(tenant) else actor==tenant and e._spec["actors"].has(tenant) and e.subject_active_at(tenant,minute)
func _proof_valid(proof:Variant,actor:String,firm:String,op:String,amount:int,minute:int,currency:String,obj:String)->bool:
	if not proof is Dictionary or not EconomySliceConfig._fields(proof,["ok","actor","firm","operation","amount","denomination","minute","authority_id","source"],["root_proof"]) or proof["ok"]!=true or proof["actor"]!=actor or proof["firm"]!=firm or proof["operation"]!=op or proof["amount"]!=amount or proof["minute"]!=minute or proof["denomination"]!=currency or not economy()._manager_at(actor,firm,minute):return false
	var valid:=false
	for a:Dictionary in economy().config.get("lease_market",{}).get("authorities",[]):
		if proof["source"]==a and proof["authority_id"]==a["id"] and a["firm"]==firm and a["controller"]==actor and op in a["operations"] and amount<=a["limit"] and a["denomination"]==currency and minute>=a["start_minute"] and minute<a["end_minute"]:valid=true
	if not valid:return false
	if proof["source"]["root_authority"].is_empty():return not proof.has("root_proof")
	var root:Variant=proof.get("root_proof")
	return root is Dictionary and economy()._cargo_fulfilment._saved_authority(root) and root.get("authority_id")==proof["source"]["root_authority"] and root.get("subject")==firm and root.get("actor")==actor and root.get("amount")==amount and root.get("minute")==minute and root.get("operation")==("economy.procure" if op=="rent" else "economy.lease."+op) and root.get("target")==obj and root.get("place")==_objects[obj]["place_id"] and root.get("category")=="lease:"+str(_objects[obj]["kind"]).to_lower()
func valid_payment_batch(id:String)->bool:
	var contract:String=str(_payments.get(id,""))
	if contract.is_empty():return false
	var c:=contracts[contract] as Dictionary
	for payment:Dictionary in c["payments"]:
		if payment["id"]!=id:continue
		var e:=economy();var currency:String=_offers[c["offer_id"]]["denomination"]
		var tx:Dictionary=e._world.ledger_state.transaction(id);var batch:Dictionary=e._world.ledger_state.payment_batch(id)
		var releases:Dictionary={}
		if payment["release_amount"]>0:releases[c["id"]]=payment["release_amount"]
		return tx.get("kind")=="lease_rent" and tx.get("reference_id")==c["id"] and tx.get("amount")==payment["amount"] and tx.get("effective_minute")==payment["minute"] and tx.get("denomination")==currency and tx.get("from_account_id")==e._account(c["tenant"],currency) and tx.get("to_account_id")==e._account(c["lessor"],currency) and batch.get("transactions")==[id] and batch.get("minute")==payment["minute"] and batch.get("releases")==releases
	return false
func restore(raw:Variant,saved:Dictionary)->bool:
	_built_assets.clear()
	for id:String in economy()._capital.assets:register_completed_asset(id)
	if raw==null:return true
	if not raw is Dictionary or not EconomySliceConfig._fields(raw,["format","contracts"],["offer_changes"]) or raw["format"]!=FORMAT or not raw["contracts"] is Dictionary:return _fail("Invalid lease snapshot")
	var e:=economy();var now:int=e._world.game_clock.total_minutes()
	if not _restore_offer_changes(raw.get("offer_changes",{}),saved,now):return false
	contracts=raw["contracts"].duplicate(true);_active.clear();_by_subject.clear();_by_object.clear();_site_history.clear();_site_days.clear();_indexed_uses.clear();_days.clear();_housing.clear();_payments.clear();_last_offer_accept.clear()
	for id:String in contracts:
		var c:Variant=contracts[id]
		if not c is Dictionary or not FormalLedgerState.exact_fields(c,CONTRACT_FIELDS):return _fail("Invalid lease contract fields")
		for key:String in ["id","action_id","actor","tenant","lessor","object_id","offer_id","site_id","kind","state","reason","predecessor"]:
			if not c[key] is String:return _fail("Invalid lease identity")
		if c["id"]!=id or id!="lease:"+str(c["action_id"]) or not _offers.has(c["offer_id"]) or not _objects.has(c["object_id"]):return _fail("Lease lost its configured object or offer")
		var o:=_objects[c["object_id"]] as Dictionary;var q:=_offers[c["offer_id"]] as Dictionary
		for party: String in [c["tenant"],c["lessor"]]:
			var actual: Dictionary=e._world.ledger_state.account(e._account(party,q["denomination"]))
			if actual.get("owner_id")!=party or actual.get("denomination")!=q["denomination"]:return _fail("Lease lost its actual party/currency account")
		for key:String in ["quantity","accepted_minute","start_minute","end_minute","total","first_reserve","cash_released","rent_units","accrued","due","paid","released"]:
			if not FormalLedgerState.valid_amount(c[key]):return _fail("Invalid lease amount or time")
		for key:String in ["member_start","entered_minute","ended_minute","returned_minute","last_boundary"]:
			if not c[key] is int or c[key]<-1 or c[key]>now:return _fail("Invalid actual lease boundary")
		for key:String in ["events","periods","payments"]:
			if not c[key] is Array:return _fail("Invalid lease facts")
		if q["object_id"]!=o["id"] or c["lessor"]!=o["lessor"] or c["kind"]!=o["kind"] or c["tenant"] not in q["known_to"] or c["tenant"]==c["lessor"] or c["accepted_minute"]>now or c["accepted_minute"]%1440!=0 or c["start_minute"]%1440!=0 or c["start_minute"]<c["accepted_minute"] or c["start_minute"]>int(c["accepted_minute"])+30*1440 or c["end_minute"]%1440!=0 or c["end_minute"]<=c["start_minute"] or c["start_minute"]<o["valid_from"] or c["end_minute"]>o["valid_until"] or c["accepted_minute"]<q["valid_from"] or c["accepted_minute"]>=q["valid_until"] or c["accepted_minute"]<q["notice_minute"] or not _offer_enabled_at(q["id"],c["accepted_minute"]) or not _available(o,c["accepted_minute"]):return _fail("Invalid lease scope, period or rights source")
		var days:=(int(c["end_minute"])-int(c["start_minute"]))/1440
		if c["quantity"]<1 or c["quantity"]>o["capacity"] or days<q["period_days"] or days>q["max_days"] or c["total"]!=int(q["rent_per_unit"])*int(c["quantity"])*days/int(q["period_days"]) or c["first_reserve"]!=mini(int(c["total"]),int(q["rent_per_unit"])*int(c["quantity"])) or not _party_at(c["actor"],c["tenant"],c["accepted_minute"]):return _fail("Lease lost original quantity, rent or tenant authority")
		var command:=_command(saved,c["action_id"],c["actor"],"request_lease",c["accepted_minute"])
		var p:Dictionary=command.get("payload",{})
		if command.is_empty() or not EconomySliceConfig._fields(p,["tenant","offer_id","site_id","quantity","term_days","start_minute","max_total"],["predecessor"]) or p["tenant"]!=c["tenant"] or p["offer_id"]!=c["offer_id"] or p["site_id"]!=c["site_id"] or p["quantity"]!=c["quantity"] or p["term_days"]!=days or p["start_minute"]!=c["start_minute"] or not FormalLedgerState.valid_amount(p["max_total"]) or p["max_total"]<c["total"] or p.get("predecessor","")!=c["predecessor"] or saved["commands"][c["action_id"]]["result"].get("lease_id")!=id:return _fail("Lease differs from original accepted action")
		if c["kind"]==RESIDENTIAL:
			var member:Variant=saved.get("actors",{}).get(c["tenant"],{})
			if not member is Dictionary or not FormalLedgerState.valid_amount(member.get("members")) or c["member_start"]<0 or int(c["member_start"])+int(c["quantity"])>member["members"] or not _targeted(c["tenant"]) or c["site_id"]!="" or c["permission"]!={"basis":"OWN_RESIDENT_IDENTITY_AND_LEDGER_ACCOUNT","actor":c["tenant"],"account_id":e._account(c["tenant"],q["denomination"])}:return _fail("Housing lost its actual resident shares or account")
		elif c["member_start"]!=-1 or c["quantity"]!=1 or c["site_id"] not in o["eligible_sites"] or e._owner(c["site_id"])!=c["tenant"] or not _proof_valid(c["permission"],c["actor"],c["tenant"],"rent",c["total"],c["accepted_minute"],q["denomination"],o["id"]):return _fail("Commercial lease lost independent rent authority or site")
		if not c["supply_permission"] is Dictionary or not _proof_valid(c["supply_permission"],str(c["supply_permission"].get("actor","")),c["lessor"],"let",c["total"],c["accepted_minute"],q["denomination"],o["id"]):return _fail("Lease lost original lessor authorization")
		if not c["predecessor"].is_empty():
			var previous:Variant=contracts.get(c["predecessor"])
			if not previous is Dictionary or previous.get("tenant")!=c["tenant"] or previous.get("object_id")!=c["object_id"] or previous.get("state")!="RETURNED" or not previous.get("returned_minute") is int or previous["returned_minute"]>c["accepted_minute"] or c["predecessor"]==id:return _fail("Lease renewal rewrites an unreturned predecessor")
		if not _restore_events(c,saved,now):return false
		if not _restore_periods(c,now):return false
		if not _restore_payments(c,now):return false
		_index(c)
	return _validate_occupancy(now)
func _restore_events(c:Dictionary,saved:Dictionary,now:int)->bool:
	var entered:=-1;var ended:=-1;var returned:=-1;var prior:=int(c["accepted_minute"])
	var q:=_offers[c["offer_id"]] as Dictionary
	for event:Variant in c["events"]:
		if not event is Dictionary or not FormalLedgerState.exact_fields(event,["id","kind","minute","actor","permission"]) or not event["id"] is String or not event["actor"] is String or not FormalLedgerState.valid_amount(event["minute"]) or event["minute"]<prior or event["minute"]>now or event["minute"]%1440!=0 or event["kind"] not in ["handover_lease","end_lease","return_lease"]:return _fail("Invalid lease use event")
		var cmd:=_command(saved,event["id"],event["actor"],event["kind"],event["minute"])
		if cmd.get("payload")!={"lease_id":c["id"]} or not _party_at(event["actor"],c["tenant"],event["minute"]):return _fail("Lease use event lacks original authorized action")
		if c["kind"]==COMMERCIAL:
			if not _proof_valid(event["permission"],event["actor"],c["tenant"],"manage",0,event["minute"],q["denomination"],c["object_id"]):return _fail("Lease use change lacks management authority")
		elif event["permission"]!={}:return _fail("Resident lease borrows enterprise authority")
		prior=event["minute"]
		if event["kind"]=="handover_lease":
			if entered>=0 or ended>=0 or event["minute"]<c["start_minute"] or event["minute"]>=c["end_minute"] or not _available(_objects[c["object_id"]],event["minute"]):return _fail("Repeated or unavailable lease handover")
			entered=event["minute"]
		elif event["kind"]=="end_lease":
			if ended>=0 or returned>=0 or event["minute"]>c["end_minute"]:return _fail("Repeated lease termination")
			ended=event["minute"]
		else:
			if ended<0:
				if event["minute"]<c["end_minute"]:return _fail("Premature return without end of use")
				ended=c["end_minute"]
			if entered<0 or returned>=0 or event["minute"]<ended:return _fail("Lease return lacks actual occupancy or end")
			returned=event["minute"]
	if ended<0 and now>=c["end_minute"]:ended=c["end_minute"]
	var state:="RESERVED" if entered<0 else "ACTIVE"
	if ended>=0:state="CANCELLED" if entered<0 else "ENDED_OCCUPIED"
	if returned>=0:state="RETURNED"
	if c["entered_minute"]!=entered or c["ended_minute"]!=ended or c["returned_minute"]!=returned or c["state"]!=state:return _fail("Lease state differs from handover, end and actual return")
	return true
func _restore_periods(c:Dictionary,now:int)->bool:
	var cursor:=int(c["entered_minute"]);var units:=0;var accrued:=0;var due:=0
	var q:=_offers[c["offer_id"]] as Dictionary;var o:=_objects[c["object_id"]] as Dictionary
	for p:Variant in c["periods"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["from","to","usable","unit_minutes","rent_delta","cumulative_accrued","due","housing_people"]) or not p["usable"] is bool:return _fail("Invalid lease period")
		for key:String in ["from","to","unit_minutes","rent_delta","cumulative_accrued","due","housing_people"]:
			if not FormalLedgerState.valid_amount(p[key]):return _fail("Invalid lease period amount/time")
		var until:=mini(now/1440*1440,int(c["end_minute"]))
		if c["ended_minute"]>=0:until=mini(until,int(c["ended_minute"]))
		if cursor<0 or p["from"]!=cursor or p["to"]!=cursor+1440 or p["to"]>until or p["usable"]!=_available(o,int(p["to"])-1) or p["unit_minutes"]!=(int(c["quantity"])*1440 if p["usable"] else 0) or (p["housing_people"]!=0 and (not p["usable"] or c["kind"]!=RESIDENTIAL or p["housing_people"]!=c["quantity"])):return _fail("Lease period lacks actual use or available space")
		units+=int(p["unit_minutes"])
		var next:=int(q["rent_per_unit"])*units/(int(q["period_days"])*1440)
		if (int(p["to"])-int(c["start_minute"]))%(int(q["period_days"])*1440)==0 or p["to"]==c["end_minute"]:due=next
		if p["rent_delta"]!=next-accrued or p["cumulative_accrued"]!=next or p["due"]!=due:return _fail("Lease rent re-counted or differs from cumulative integer period")
		accrued=next;cursor=p["to"];_add_day(c,cursor/1440)
		if p["housing_people"]>0:_housing_day(c,cursor/1440,p["housing_people"])
	var through:=-1 if c["entered_minute"]<0 else mini(now/1440*1440,int(c["end_minute"]))
	if through>=0 and c["ended_minute"]>=0:through=mini(through,int(c["ended_minute"]))
	if c["ended_minute"]>=0:due=accrued
	if cursor!=through or c["last_boundary"]!=cursor or c["rent_units"]!=units or c["accrued"]!=accrued or c["due"]!=due or c["released"]!=(int(c["total"])-accrued if c["ended_minute"]>=0 else 0):return _fail("Lease lost an incurred period or forgave unpaid rent")
	return true
func _restore_payments(c:Dictionary,now:int)->bool:
	var paid:=0;var released:=0;var prior:=int(c["accepted_minute"])
	for p:Variant in c["payments"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["id","minute","amount","cumulative_paid","release_amount"]) or not p["id"] is String:return _fail("Invalid lease payment receipt")
		for key:String in ["minute","amount","cumulative_paid","release_amount"]:
			if not FormalLedgerState.valid_amount(p[key]):return _fail("Invalid rent payment amount/time")
		var due:=0
		for period:Dictionary in c["periods"]:
			if period["to"]<=p["minute"]:due=period["due"]
		if c["ended_minute"]>=0 and c["ended_minute"]<=p["minute"]:due=c["accrued"]
		if p["amount"]<1 or p["minute"]<prior or p["minute"]>now or p["minute"]%1440!=0 or int(p["amount"])+paid>due:return _fail("Rent paid before actual due use")
		var cash:=0 if c["ended_minute"]>=0 and c["ended_minute"]<=p["minute"] else int(c["first_reserve"])-released
		if p["release_amount"]!=mini(int(p["amount"]),cash):return _fail("Rent cash reservation released twice")
		paid+=int(p["amount"]);released+=int(p["release_amount"]);prior=p["minute"]
		if p["cumulative_paid"]!=paid or p["id"]!="lease_payment:"+str(c["id"])+":"+str(paid):return _fail("Rent payment identity or cumulative amount differs")
		_payments[p["id"]]=c["id"]
		if not valid_payment_batch(p["id"]):return _fail("Rent payment differs from original Ledger batch")
		_add_day(c,p["minute"]/1440)
	if c["paid"]!=paid or paid>c["due"] or c["cash_released"]!=(int(c["first_reserve"])-released if c["ended_minute"]>=0 else 0):return _fail("Rent paid, reserved or released totals differ")
	return true
func _held_at(c:Dictionary,minute:int)->bool:
	return minute>=c["accepted_minute"] and (c["returned_minute"]<0 or minute<c["returned_minute"]) and not (c["entered_minute"]<0 and c["ended_minute"]>=0 and minute>=c["ended_minute"])
func _validate_occupancy(now:int)->bool:
	var dates:Dictionary={now:true}
	for c:Dictionary in contracts.values():
		dates[c["accepted_minute"]]=true
		if c["returned_minute"]>=0:dates[c["returned_minute"]]=true
		if c["ended_minute"]>=0:dates[c["ended_minute"]]=true
	for minute:int in dates:
		var used:Dictionary={};var spans:Dictionary={}
		for c:Dictionary in contracts.values():
			if not _held_at(c,minute):continue
			used[c["object_id"]]=int(used.get(c["object_id"],0))+int(c["quantity"])
			if used[c["object_id"]]>_physical_capacity(c["object_id"],minute):return _fail("Same lease space committed twice before actual return")
			if c["kind"]==RESIDENTIAL:
				if not spans.has(c["tenant"]):spans[c["tenant"]]=[]
				var span:=Vector2i(c["member_start"],int(c["member_start"])+int(c["quantity"]))
				for other:Vector2i in spans[c["tenant"]]:
					if span.x<other.y and other.x<span.y:return _fail("Same cohort housing share allocated twice")
				spans[c["tenant"]].append(span)
	return true
func validate_presence()->bool:
	var e:=economy()
	for c:Dictionary in contracts.values():
		if c["kind"]!=RESIDENTIAL:continue
		var place:String=_objects[c["object_id"]]["place_id"]
		for event:Dictionary in c["events"]:
			if event["kind"] in ["handover_lease","return_lease"] and not e._service_market._resident._present_at(c["tenant"],place,event["minute"]):return _fail("Housing handover/return lacks actual resident presence")
		for period:Dictionary in c["periods"]:
			var actual:=int(c["quantity"]) if period["usable"] and e._service_market._resident._present_at(c["tenant"],place,period["to"]) else 0
			if period["housing_people"]!=actual:return _fail("Housing target satisfied from a remote or unavailable place")
	return true


func _asset_id(o:Dictionary)->String:
	return str(_built_assets.get(o["id"],"")) if _blueprints.has(o["id"]) else str(o["capital_asset_id"])
func _physical_capacity(obj:String,minute:int)->int:
	var o:=_objects[obj] as Dictionary
	if not _blueprints.has(obj):return int(o["capacity"])
	var a:Dictionary=economy()._capital.assets.get(_asset_id(o),{})
	return int(a["capacity"]) if not a.is_empty() and a["in_service_minute"]<=minute else 0
func register_completed_asset(id:String)->void:
	var e:=economy();var a:Dictionary=e._capital.assets.get(id,{})
	if a.is_empty():return
	var t:Dictionary=e._capital.template(a["template_id"])
	if not t.has("building"):return
	var obj:String=t["building"]["object"]["id"]
	# This is a reference projection; CapitalFormation remains the only asset fact.
	assert(_blueprints.get(obj)==t["id"] and a["firm"]==_objects[obj]["lessor"] and a["capacity"]==t["capacity"] and e._place(a["site_id"])==_objects[obj]["place_id"] and (not _built_assets.has(obj) or _built_assets[obj]==id))
	_built_assets[obj]=id
func own_vacancy(firm:String)->int:
	var total:=0
	for o:Dictionary in _objects.values():
		if o["lessor"]==firm:total+=available(o["id"])
	return total
func asset_view(id:String)->Dictionary:
	var e:=economy();var a:Dictionary=e._capital.assets.get(id,{})
	if a.is_empty() or not e._capital.template(a["template_id"]).has("building"):return {}
	var t:Dictionary=e._capital.template(a["template_id"]);var o:Dictionary=t["building"]["object"]
	var result:={"asset_id":id,"object_id":o["id"],"place_id":o["place_id"],"kind":o["kind"],"capacity":a["capacity"],"unit":o["unit"],"available":available(o["id"]),"fulfilled_rent":{},"received_cash":{},"rent_receivable":{},"retained_occupancy":0,"depreciation":"NOT_CONFIGURED","basis":"COMPLETED_PROJECT_AND_ACTUAL_LEASE_OBSERVATION_NOT_FULL_ROI"}
	for lease:String in _by_subject.get(a["firm"],[]):
		var c:=contracts[lease] as Dictionary
		if c["object_id"]!=o["id"]:continue
		var currency:String=_offers[c["offer_id"]]["denomination"]
		for field:String in ["fulfilled_rent","received_cash","rent_receivable"]:
			var amount:=int(c["accrued"]) if field=="fulfilled_rent" else int(c["paid"]) if field=="received_cash" else int(c["due"])-int(c["paid"])
			result[field][currency]=int(result[field].get(currency,0))+amount
		if c["state"] in ["ACTIVE","ENDED_OCCUPIED"]:result["retained_occupancy"]+=int(c["quantity"])
	if e._costs.enabled:result["construction_cost"]=e._costs.project_cost(a["project_id"])
	result["enterprise_credit_contracts"]=e._credit.visible(a["firm"],e._known_credit_lenders(a["firm"]),e._world.game_clock.total_minutes(),true).get("loans",[])
	return result
func _offer_enabled_at(id:String,minute:int)->bool:
	if minute==economy()._world.game_clock.total_minutes():return bool(_offer_current.get(id,true))
	var enabled:=true
	for key:String in _offer_history.get(id,[]):
		var c:=offer_changes[key] as Dictionary
		if c["minute"]>minute:break
		enabled=c["enabled"]
	return enabled
func _index_offer(c:Dictionary)->void:
	if not _offer_history.has(c["offer_id"]):_offer_history[c["offer_id"]]=[]
	_offer_history[c["offer_id"]].append(c["id"]);_offer_current[c["offer_id"]]=c["enabled"]
func _set_offer(actor:String,p:Dictionary,action:String)->Dictionary:
	if not FormalLedgerState.exact_fields(p,["offer_id","enabled"]) or not _offers.has(p.get("offer_id")) or not p["enabled"] is bool:return _reject("INVALID_LEASE_OFFER_CONTROL")
	var q:=_offers[p["offer_id"]] as Dictionary;var o:=_objects[q["object_id"]] as Dictionary
	var proof:=_permission(actor,o["lessor"],"let",q["denomination"],0,o["id"])
	if not proof["ok"]:return _reject(proof["reason"])
	var now:int=economy()._world.game_clock.total_minutes()
	if _offer_enabled_at(q["id"],now)==p["enabled"]:return _reject("LEASE_OFFER_ALREADY_IN_REQUESTED_STATE")
	if _last_offer_accept.get(q["id"],-1)==now:return _reject("LEASE_OFFER_CHANGE_AFTER_ACCEPTANCE_REQUIRES_NEXT_BOUNDARY")
	offer_changes[action]={"id":action,"actor":actor,"offer_id":q["id"],"minute":now,"enabled":p["enabled"],"permission":proof}
	_index_offer(offer_changes[action])
	return {"accepted":true,"reason":"LEASE_OFFER_UPDATED_EXISTING_CONTRACTS_RETAINED"}
func _restore_offer_changes(raw:Variant,saved:Dictionary,now:int)->bool:
	if not raw is Dictionary:return _fail("Invalid rental offer controls")
	offer_changes={};_offer_history.clear();_offer_current.clear();var prior:=-1
	for id:Variant in raw:
		var c:Variant=raw[id]
		if not c is Dictionary or not FormalLedgerState.exact_fields(c,["id","actor","offer_id","minute","enabled","permission"]) or c["id"]!=id or not c["actor"] is String or not _offers.has(c["offer_id"]) or not FormalLedgerState.valid_amount(c["minute"]) or c["minute"]<prior or c["minute"]>now or not c["enabled"] is bool:return _fail("Invalid rental offer control identity/time")
		var q:=_offers[c["offer_id"]] as Dictionary;var o:=_objects[q["object_id"]] as Dictionary
		if not _proof_valid(c["permission"],c["actor"],o["lessor"],"let",0,c["minute"],q["denomination"],o["id"]) or _command(saved,id,c["actor"],"set_lease_offer",c["minute"]).get("payload")!={"offer_id":c["offer_id"],"enabled":c["enabled"]} or _offer_enabled_at(c["offer_id"],c["minute"])==c["enabled"]:return _fail("Rental quote changed without original lessor authority")
		offer_changes[id]=c.duplicate(true);_index_offer(offer_changes[id]);prior=c["minute"]
	return true

func _prepare_rental_site(actor:String,tenant:String,eligible:Array)->void:
	var e:=economy()
	for option:Dictionary in e.config.get("runtime_expansions",[]):
		var extension:Dictionary=option.get("extension",{})
		if extension.keys()!=["sites"] or extension["sites"].size()!=1:continue
		var item:Dictionary=extension["sites"][0]
		if item["firm_id"]!=tenant or item["site"]["id"] not in eligible or e._spec["sites"].has(item["site"]["id"]):continue
		for pending:Dictionary in e._scope_requests.values():
			if pending["kind"]=="EXPAND" and pending["payload"]==extension:return
		e._accept(actor,e._auto_command(actor,"expand_configured_scope",{"extension_id":option["id"]},option["id"]),true)
		return
