class_name EconomyServiceMarket
extends RefCounted
## Bounded business and resident services. Ledger owns money; StockLots owns custody; Capital owns
## equipment. Work references use the existing settled jobs and wage claims.
const Resident = preload("res://scripts/world/economy_resident_services.gd")
const CONTRACT_FIELDS: Array[String]=["id","action_id","actor","client","payer","provider","provider_site","offer_id","facility_id","kind","source_site","good","quantity","periods_count","asset_id","accepted_minute","started_minute","end_minute","last_boundary","repair_result_minute","status","reason","paused","total","earned","paid","released","charge_numerator","work","material_sources","material_minute","custody_events","periods","payments","permission","supply_permission"]
var _resident: Resident=Resident.new()
const FORMAT := "economy_service_market_v1"
var contracts: Dictionary = {}
var changes: Dictionary = {}
var error: String = ""
var _ref: WeakRef
var _offers: Dictionary = {}
var _facilities: Dictionary = {}
var _active: Dictionary = {}
var _by_firm: Dictionary = {}
var _by_facility: Dictionary = {}
var _by_asset: Dictionary = {}
var _labor: Dictionary = {}
var _labor_days: Dictionary = {}
var _last_work: Dictionary = {}
var _enabled: Dictionary = {}
var _last_npc: Dictionary = {}
var _facility_history: Dictionary = {}
var _asset_history: Dictionary = {}
var _days: Dictionary = {}
var _payment_contract: Dictionary = {}

func economy() -> RefCounted: return _ref.get_ref()
func bind(e: RefCounted) -> void:
	_ref=weakref(e)
	_resident.bind(self)
	for f: Dictionary in e.config.get("service_market",{}).get("facilities",[]): _facilities[f["id"]]=f
	for o: Dictionary in e.config.get("service_market",{}).get("offers",[]): _offers[o["id"]]=o; _enabled[o["id"]]=true

static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	if not settings.has("service_market"): return true
	var value: Variant=settings["service_market"]
	if not value is Dictionary or not EconomySliceConfig._fields(value,["facilities","offers","authorities","npc_policies","basis"],["resident_targets","resident_policies"]) or value["basis"]!="EXPLICIT_DEVELOPMENT_SERVICE_MARKET": return false
	for key: String in ["facilities","offers","authorities","npc_policies"]:
		if not value[key] is Array or value[key].size()>64: return false
	var facilities: Dictionary={}
	for f: Variant in value["facilities"]:
		if not f is Dictionary or not FormalLedgerState.exact_fields(f,["id","provider","site_id","kind","capacity","unit","good_units","shared_storage_id","basis"]) or not f["id"] is String or facilities.has(f["id"]) or not spec["sites"].has(f["site_id"]) or spec["sites"][f["site_id"]]["firm_id"]!=f["provider"] or f["kind"] not in ["STORAGE","REPAIR","DINING","HAIRCUT","ANNOUNCEMENT"] or not FormalLedgerState.valid_amount(f["capacity"]) or f["capacity"]<1 or f["capacity"]>1000000 or not f["unit"] is String or f["unit"].is_empty() or not f["good_units"] is Dictionary or not f["shared_storage_id"] is String or f["basis"]!="EXPLICIT_DEVELOPMENT_SERVICE_FACILITY": return false
		for good: String in f["good_units"]:
			if good not in spec["good_ids"] or not FormalLedgerState.valid_amount(f["good_units"][good]) or f["good_units"][good]<1 or f["good_units"][good]>1000: return false
		if f["kind"]!="STORAGE" and (not f["good_units"].is_empty() or not f["shared_storage_id"].is_empty()): return false
		if not f["shared_storage_id"].is_empty():
			var found:=false
			for shared: Dictionary in settings.get("transport_facilities",[]):
				if shared["id"]==f["shared_storage_id"] and shared["site_id"]==f["site_id"] and shared["kind"]=="STORAGE_OCCUPANCY" and shared["unit"]==f["unit"]: found=true
			if not found: return false
			for good: Dictionary in settings["goods"]:
				if f["good_units"].has(good["id"]):
					var weight: Dictionary=good.get("unit_weight",{})
					if weight.get("unit")!=f["unit"] or weight.get("numerator")!=int(f["good_units"][good["id"]])*int(weight.get("denominator",0)): return false
		facilities[f["id"]]=f
		if not str(f["id"]).begins_with("facility:"): return false
	var offers: Dictionary={}
	for o: Variant in value["offers"]:
		if not o is Dictionary or not EconomySliceConfig._fields(o,["id","facility_id","kind","denomination","price","valid_from","valid_until","known_to","notice_minute","job_ids","hours_per_day","cancel_rule","basis"],["storage_terms","repair_terms","resident_terms","announcement_terms"]) or offers.has(o.get("id")) or not o["id"] is String or not facilities.has(o["facility_id"]) or facilities[o["facility_id"]]["kind"]!=o["kind"] or not FormalLedgerState.currency_id(o["denomination"]) or not FormalLedgerState.valid_amount(o["price"]) or o["price"]<1 or o["price"]>1000000 or o["cancel_rule"]!="UNSTARTED_REPAIR_OR_STORAGE_RETURN" or o["basis"]!="EXPLICIT_DEVELOPMENT_SERVICE_OFFER": return false
		for key: String in ["valid_from","valid_until","notice_minute","hours_per_day"]:
			if not FormalLedgerState.valid_amount(o[key]): return false
		if o["valid_until"]<=o["valid_from"] or o["hours_per_day"]<1 or o["hours_per_day"]>24 or not o["job_ids"] is Array or o["job_ids"].is_empty() or not o["known_to"] is Array: return false
		for job: Variant in o["job_ids"]:
			if not job is String or not spec["jobs"].has(job) or spec["jobs"][job]["site_id"]!=facilities[o["facility_id"]]["site_id"]: return false
		for firm: Variant in o["known_to"]:
			if not firm is String or (not spec["firms"].has(firm) and not (o["kind"] in Resident.KINDS and (spec["actors"].has(firm) or (firm=="HOST_SELECTED_PLAYER" and settings.get("host_personal_accounts",false))))): return false
		if o["kind"]!="ANNOUNCEMENT" and o.has("announcement_terms"): return false
		if o["kind"]=="ANNOUNCEMENT":
			var t: Variant=o.get("announcement_terms")
			if o.has("storage_terms") or o.has("repair_terms") or o.has("resident_terms") or not t is Dictionary or not FormalLedgerState.exact_fields(t,["channel_id","work_hours","rule"]) or not t["channel_id"] is String or not FormalLedgerState.valid_amount(t["work_hours"]) or t["work_hours"]<1 or t["work_hours"]>o["hours_per_day"] or t["rule"]!="LOCAL_PUBLICATION_WORK_NO_GUARANTEED_SALE": return false
		elif o["kind"] in Resident.KINDS:
			if o.has("storage_terms") or o.has("repair_terms") or not Resident.valid_terms(o,settings,spec): return false
		elif o["kind"]=="STORAGE":
			var terms: Variant=o.get("storage_terms")
			if o.has("repair_terms") or not terms is Dictionary or not FormalLedgerState.exact_fields(terms,["period_minutes","max_periods","intake_hours","supervision_hours","charge_rule"]) or terms["period_minutes"]!=1440 or terms["charge_rule"]!="CUMULATIVE_UNIT_MINUTES_FLOOR": return false
			for key: String in ["max_periods","intake_hours","supervision_hours"]:
				if not FormalLedgerState.valid_amount(terms[key]) or terms[key]<1 or terms[key]>30: return false
		else:
			var terms: Variant=o.get("repair_terms")
			if o.has("storage_terms") or not terms is Dictionary or not FormalLedgerState.exact_fields(terms,["asset_types","mode","material_owner"]) or not terms["asset_types"] is Array or terms["asset_types"].is_empty() or terms["mode"]!="ON_SITE_SAME_HOST_PLACE" or terms["material_owner"]!="PROVIDER": return false
			for type: Variant in terms["asset_types"]:
				if not type is String or type.is_empty(): return false
		if o["id"].is_empty(): return false
		var unique_jobs: Dictionary={}
		for job: String in o["job_ids"]:
			if unique_jobs.has(job): return false
			unique_jobs[job]=true
		offers[o["id"]]=o
	var ids: Dictionary={}
	for p: Variant in value["authorities"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["id","firm","controller","operations","denomination","limit","start_minute","end_minute","root_authority","basis"]) or ids.has(p.get("id")) or not spec["firms"].has(p.get("firm")) or not p["controller"] is String or not p["root_authority"] is String or not p["operations"] is Array or p["operations"].is_empty() or p["basis"]!="EXPLICIT_DEVELOPMENT_SERVICE_AUTHORITY" or not FormalLedgerState.currency_id(p["denomination"]) or not FormalLedgerState.valid_amount(p["limit"]) or not FormalLedgerState.valid_amount(p["start_minute"]) or not FormalLedgerState.valid_amount(p["end_minute"]) or p["end_minute"]<=p["start_minute"]: return false
		for op: Variant in p["operations"]:
			if op not in ["purchase","supply","control"]: return false
		if not p["id"] is String or p["id"].is_empty() or p["controller"].is_empty(): return false
		ids[p["id"]]=true
	for p: Variant in value["npc_policies"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["firm","storage_offer","source_site","good","trigger_quantity","store_quantity","periods","repair_offer","cooldown_days","basis"]) or not spec["firms"].has(p.get("firm")) or not spec["sites"].has(p.get("source_site")) or spec["sites"][p["source_site"]]["firm_id"]!=p["firm"] or p["good"] not in spec["good_ids"] or not p["storage_offer"] is String or (not p["storage_offer"].is_empty() and not offers.has(p["storage_offer"])) or not p["repair_offer"] is String or (not p["repair_offer"].is_empty() and not offers.has(p["repair_offer"])) or p["basis"]!="EXPLICIT_DEVELOPMENT_SERVICE_DEMAND": return false
		for key: String in ["trigger_quantity","store_quantity","periods","cooldown_days"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]<1 or p[key]>1000000: return false
	return Resident.valid_policies(value,settings,spec,offers)

func _permission(actor: String, firm: String, op: String, currency: String, amount: int, target: String, place: String, context: Dictionary={}, category: String="") -> Dictionary:
	var e:=economy()
	var now: int=e._world.game_clock.total_minutes()
	if not e._manager(actor,firm): return {"ok":false,"reason":"NOT_SERVICE_ENTERPRISE_MANAGER"}
	for p: Dictionary in e.config.get("service_market",{}).get("authorities",[]):
		if p["firm"]!=firm or p["controller"]!=actor or op not in p["operations"] or p["denomination"]!=currency or amount>p["limit"] or now<p["start_minute"] or now>=p["end_minute"]: continue
		var result:={"ok":true,"authority_id":p["id"],"actor":actor,"firm":firm,"operation":op,"amount":amount,"denomination":currency,"minute":now,"source":p.duplicate(true)}
		if not p["root_authority"].is_empty():
			var requirement:={"operation":"economy.procure" if op=="purchase" else "economy.service."+op,"target":target,"place":place,"category":category if not category.is_empty() else "service:"+op,"amount":amount}
			var c: Dictionary=context if not context.is_empty() else e._cargo_fulfilment._available_context(actor,firm,requirement,p["root_authority"])
			var proof: Dictionary=e._cargo_fulfilment._authorize(actor,firm,requirement["operation"],target,place,requirement["category"],amount,{firm+"|"+requirement["operation"]+"|"+requirement["category"]:c})
			if not proof["ok"] or proof["proof"].get("authority_id")!=p["root_authority"]: continue
			result["root_proof"]=proof["proof"]
		return result
	return {"ok":false,"reason":"NO_EXPLICIT_SERVICE_"+op.to_upper()+"_AUTHORITY"}

func _index(c: Dictionary) -> void:
	var date: int=economy()._world.game_clock.total_minutes()/1440
	for firm: String in [c["client"],c["provider"]]:
		if not _days.has(firm): _days[firm]={}
		if not _days[firm].has(date): _days[firm][date]={}
		_days[firm][date][c["id"]]=true
	if not _facility_history.has(c["facility_id"]): _facility_history[c["facility_id"]]=[]
	if not _facility_history[c["facility_id"]].has(c["id"]): _facility_history[c["facility_id"]].append(c["id"])
	for firm: String in [c["client"],c["provider"]]:
		if not _by_firm.has(firm): _by_firm[firm]=[]
		if not _by_firm[firm].has(c["id"]): _by_firm[firm].append(c["id"])
	if not _by_facility.has(c["facility_id"]): _by_facility[c["facility_id"]]={}
	if c["status"] not in ["COMPLETED","CANCELLED"] or c["earned"]>c["paid"]:
		_active[c["id"]]=true
	else: _active.erase(c["id"])
	if _occupied(c)>0: _by_facility[c["facility_id"]][c["id"]]=true
	else: _by_facility[c["facility_id"]].erase(c["id"])
	if c["kind"]=="REPAIR":
		if not _asset_history.has(c["asset_id"]): _asset_history[c["asset_id"]]=[]
		if not _asset_history[c["asset_id"]].has(c["id"]): _asset_history[c["asset_id"]].append(c["id"])
		if c["repair_result_minute"]<0 and c["status"]!="CANCELLED": _by_asset[c["asset_id"]]=c["id"]
		else: _by_asset.erase(c["asset_id"])
	_last_npc[c["client"]]=maxi(int(_last_npc.get(c["client"],0)),int(c["accepted_minute"])/1440)

func asset_busy(id: String) -> bool: return _by_asset.has(id)
func _quantity_at(c: Dictionary, minute: int) -> int:
	var q:=int(c["quantity"])
	for event: Dictionary in c["custody_events"]:
		if event["minute"]<=minute and event["kind"] in ["OUT","LOSS","CANCEL"]: q-=int(event["quantity"])
	return q
func _occupied(c: Dictionary, minute: int=-1) -> int:
	if minute<0: minute=economy()._world.game_clock.total_minutes()
	if minute<c["accepted_minute"]: return 0
	if c["kind"] in Resident.KINDS: return _resident.occupied(c,((minute/1440)+1)*1440)
	if c["kind"]=="STORAGE": return _quantity_at(c,minute)*int(_facilities[c["facility_id"]]["good_units"][c["good"]])
	for event: Dictionary in c["custody_events"]:
		if event["kind"]=="CANCEL" and event["minute"]<=minute: return 0
	if c["kind"]=="ANNOUNCEMENT": return 0 if c["end_minute"]>=0 and minute>=c["end_minute"] else 1
	return 0 if c["repair_result_minute"]>=0 and minute>=c["repair_result_minute"] else 1
func shared_occupancy(id: String, minute: int) -> float:
	var total:=0
	for facility: String in _facilities:
		if _facilities[facility]["shared_storage_id"]!=id: continue
		var ids: Variant=_by_facility.get(facility,{}) if minute>=economy()._world.game_clock.total_minutes() else _facility_history.get(facility,[])
		for key: String in ids: total+=_occupied(contracts[key],minute)
	return float(total)
func available(id: String) -> int:
	var f:=_facilities[id] as Dictionary
	if f["kind"] in Resident.KINDS: return _resident.available(id,(economy()._world.game_clock.current_day()+1)*1440)
	var e:=economy()
	if not e._site_accepting(f["site_id"]): return 0
	var used:=0
	for key: String in _by_facility.get(id,{}): used+=_occupied(contracts[key])
	var amount:=maxi(0,int(f["capacity"])-used)
	if not f["shared_storage_id"].is_empty(): amount=mini(amount,int(floor(e._shared._node_available(f["shared_storage_id"],e._world.game_clock.total_minutes()))))
	return amount

func known(actor: String, offer: String, minute: int) -> bool:
	var o:=_offers[offer] as Dictionary
	return (actor in o["known_to"] and minute>=o["notice_minute"]) or economy()._commercial.knows_service(actor,offer,minute)

func quotes(firm: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var e:=economy()
	var now: int=e._world.game_clock.total_minutes()
	for id: String in _offers:
		var o:=_offers[id] as Dictionary
		var f:=_facilities[o["facility_id"]] as Dictionary
		if not known(firm,id,now) or f["provider"]==firm: continue
		var row:=o.duplicate(true)
		row.merge({"provider":f["provider"],"site_id":f["site_id"],"place_id":e._place(f["site_id"]),"available_capacity":available(f["id"]),"unit":f["unit"],"enabled":_enabled[id],"valid":now>=o["valid_from"] and now<o["valid_until"] and not e._firm_winding_down(f["provider"])},true)
		result.append(row)
	return result

func request(actor: String, kind: String, p: Dictionary, action: String) -> Dictionary:
	if kind=="request_service": return _accept(actor,p,action)
	var e:=economy()
	if kind=="set_service_offer":
		if not FormalLedgerState.exact_fields(p,["offer_id","enabled"]) or not _offers.has(p["offer_id"]) or not p["enabled"] is bool: return _reject("INVALID_SERVICE_OFFER_CONTROL")
		var o:=_offers[p["offer_id"]] as Dictionary
		var f:=_facilities[o["facility_id"]] as Dictionary
		var proof:=_permission(actor,f["provider"],"control",o["denomination"],0,p["offer_id"],e._place(f["site_id"]))
		if not proof["ok"]: return _reject(proof["reason"])
		changes[action]={"actor":actor,"kind":kind,"payload":p.duplicate(true),"minute":e._world.game_clock.total_minutes(),"permission":proof,"sequence":changes.size()}
		_enabled[p["offer_id"]]=p["enabled"]
		return {"accepted":true,"reason":"SERVICE_OFFER_CHANGED"}
	if not p.get("service_id") is String or not contracts.has(p["service_id"]): return _reject("UNKNOWN_SERVICE_CONTRACT")
	var c:=contracts[p["service_id"]] as Dictionary
	var permitted: bool=(actor==c["client"] and _resident._customer(actor,e._world.game_clock.total_minutes())) if c["kind"] in Resident.KINDS else e._manager(actor,c["client"])
	if not permitted: return _reject("NOT_SERVICE_CLIENT_MANAGER_OR_OWNER")
	if kind=="reschedule_service" and c["kind"] in Resident.KINDS:
		if not FormalLedgerState.exact_fields(p,["service_id"]): return _reject("INVALID_RESIDENT_RESCHEDULE")
		return _resident.reschedule(actor,c,action)
	if kind=="withdraw_service_goods":
		if not FormalLedgerState.exact_fields(p,["service_id","quantity"]) or not FormalLedgerState.valid_amount(p["quantity"]) or p["quantity"]<1 or c["kind"]!="STORAGE" or c["started_minute"]<0: return _reject("INVALID_WAREHOUSE_WITHDRAWAL")
		var rows: Array[Dictionary]=e._lots.selection("SERVICE|"+c["id"],c["good"],p["quantity"])
		if not e._lots.ready(rows) or e._place(c["source_site"])!=e._place(c["provider_site"]): return _reject("WAREHOUSE_GOODS_NOT_REACHABLE")
		var moved: Array[Dictionary]=e._lots.move(rows,"SITE|"+c["source_site"],e._place(c["source_site"]),e._world.game_clock.total_minutes(),"","","",c["source_site"])
		assert(not moved.is_empty())
		c["custody_events"].append({"id":action,"kind":"OUT","minute":e._world.game_clock.total_minutes(),"quantity":p["quantity"],"portions":rows})
		if c["status"]=="EXPIRED_CUSTODY" and _quantity_at(c,e._world.game_clock.total_minutes())==0: c["status"]="COMPLETED"
		_index(c)
		return {"accepted":true,"reason":"WAREHOUSE_PROPERTY_RETURNED_DEBT_RETAINED","quantity":p["quantity"]}
	if kind=="cancel_service":
		if not FormalLedgerState.exact_fields(p,["service_id"]) or c["status"] in ["COMPLETED","CANCELLED"]: return _reject("SERVICE_ALREADY_ENDED")
		if c["started_minute"]>=0 or (c["kind"] in Resident.KINDS and not _resident.cancel_allowed(c)): return _reject("STARTED_SERVICE_REQUIRES_RETURN_OR_EXPLICIT_PARTIAL_TERMINATION_TERMS")
		if c["kind"]=="STORAGE":
			var q: int=e._lots.reserved_quantity(c["id"])
			if q>0 and not e._lots.release(c["id"],q,e._world.game_clock.total_minutes()): return _reject("SERVICE_SOURCE_CHANGED")
		c["custody_events"].append({"id":action,"kind":"CANCEL","minute":e._world.game_clock.total_minutes(),"quantity":_quantity_at(c,e._world.game_clock.total_minutes()),"portions":[]})
		c["status"]="CANCELLED"
		_release_future(c,action)
		_index(c)
		return {"accepted":true,"reason":"UNSTARTED_SERVICE_CANCELLED"}
	if kind=="pause_service":
		if not FormalLedgerState.exact_fields(p,["service_id","paused"]) or not p["paused"] is bool or c["kind"]!="REPAIR" or c["status"]=="CANCELLED" or c["repair_result_minute"]>=0: return _reject("INVALID_REPAIR_PAUSE")
		c["paused"]=p["paused"]
		changes[action]={"actor":actor,"kind":kind,"payload":p.duplicate(true),"minute":e._world.game_clock.total_minutes(),"permission":{},"sequence":changes.size()}
		return {"accepted":true,"reason":"REPAIR_FUTURE_WORK_CHANGED"}
	return _reject("UNKNOWN_SERVICE_ACTION")

func _accept(actor: String, p: Dictionary, action: String, preview: bool=false) -> Dictionary:
	if p.has("customer"): return _resident.accept(actor,p,action,preview)
	var e:=economy()
	if not EconomySliceConfig._fields(p,["firm","payer","offer_id","max_amount"],["source_site","good","quantity","periods","asset_id","authorization_context","announcement"]) or not _offers.has(p["offer_id"]) or not e._spec["firms"].has(p["firm"]) or p["payer"]!=p["firm"] or not FormalLedgerState.valid_amount(p["max_amount"]): return _reject("INVALID_SERVICE_OR_UNSUPPORTED_THIRD_PARTY_PAYER")
	if p.has("authorization_context") and not p["authorization_context"] is Dictionary: return _reject("INVALID_SERVICE_AUTHORIZATION_CONTEXT")
	var o:=_offers[p["offer_id"]] as Dictionary
	var f:=_facilities[o["facility_id"]] as Dictionary
	var now: int=e._world.game_clock.total_minutes()
	if not _enabled[o["id"]] or not known(p["firm"],o["id"],now) or now<o["valid_from"] or now>=o["valid_until"] or f["provider"]==p["firm"] or not e._site_accepting(f["site_id"]) or e._firm_winding_down(f["provider"]) or e._firm_winding_down(p["firm"]): return _reject("NO_CURRENT_KNOWN_LEGAL_SERVICE_OFFER")
	if o["kind"] in Resident.KINDS: return _reject("RESIDENT_SERVICE_REQUIRES_OWN_CUSTOMER_IDENTITY")
	var source:=""
	var good:=""
	var asset:=""
	var q:=1
	var periods:=0
	var total:=int(o["price"])
	var rows: Array[Dictionary]=[]
	var publication: Dictionary={}
	if o["kind"]!="ANNOUNCEMENT" and p.has("announcement"): return _reject("WRONG_SERVICE_PUBLICATION_SCOPE")
	if o["kind"]=="ANNOUNCEMENT":
		if not p.get("announcement") is Dictionary or p.has("asset_id") or p.has("source_site") or p.has("good") or p.has("quantity") or p.has("periods") or available(f["id"])<1: return _reject("INVALID_PUBLICATION_OR_NO_PUBLICATION_CAPACITY")
		var prepared: Dictionary=e._commercial.prepare(actor,p["firm"],p["announcement"],action)
		if not prepared["accepted"]: return prepared
		publication=prepared["publication"]
		if e._commercial._channels[publication["channel_id"]]["service_offer"]!=o["id"] or e._place(f["site_id"])!=e._place(publication["site_id"]): return _reject("WRONG_LOCAL_PUBLICATION_CHANNEL")
	elif o["kind"]=="STORAGE":
		if p.has("asset_id") or not e._spec["sites"].has(p.get("source_site")) or e._owner(p["source_site"])!=p["firm"] or not f["good_units"].has(p.get("good")) or not FormalLedgerState.valid_amount(p.get("quantity")) or p["quantity"]<1 or p["quantity"]>1000000 or not FormalLedgerState.valid_amount(p.get("periods")) or p["periods"]<1 or p["periods"]>o["storage_terms"]["max_periods"]: return _reject("INVALID_WAREHOUSE_SCOPE")
		source=p["source_site"]; good=p["good"]; q=p["quantity"]; periods=p["periods"]
		if e._place(source)!=e._place(f["site_id"]): return _reject("TRANSPORT_TO_WAREHOUSE_PLACE_REQUIRED")
		if q*int(f["good_units"][good])>available(f["id"]): return _reject("WAREHOUSE_CAPACITY_RESERVED_OR_USED")
		rows=e._lots.selection("SITE|"+source,good,q)
		if not e._lots.ready(rows): return _reject("WAREHOUSE_LACKS_UNCOMMITTED_CLIENT_PROPERTY")
		total=int(o["price"])*q*periods
	else:
		if p.has("good") or p.has("quantity") or p.has("source_site") or p.has("periods") or not e._capital.assets.has(p.get("asset_id")) or available(f["id"])<1: return _reject("INVALID_REPAIR_ASSET_OR_NO_REPAIR_BAY")
		asset=p["asset_id"]
		var a:=e._capital.assets[asset] as Dictionary
		if e._capital.asset_state(asset)["owner"]!=p["firm"] or e._capital.move_busy(asset) or a["status"] not in ["ACTIVE","PAUSED"] or a["asset_type"] not in o["repair_terms"]["asset_types"] or e._capital.asset_state(asset)["place_id"]!=e._place(f["site_id"]) or asset_busy(asset) or not e._capital.template(a["template_id"]).has("maintenance"): return _reject("ASSET_HAS_NO_LEGAL_SAME_PLACE_EXTERNAL_MAINTENANCE")
		for project: String in e._capital._active:
			if e._capital.projects[project]["asset_id"]==asset: return _reject("ASSET_ALREADY_HAS_INTERNAL_MAINTENANCE")
		for pending: String in e._capital._pending:
			if e._capital.changes[pending]["payload"].get("asset_id")==asset: return _reject("ASSET_CONTROL_ALREADY_PENDING")
	if total>p["max_amount"] or not FormalLedgerState.valid_amount(total): return _reject("SERVICE_LOCKED_COST_EXCEEDS_LIMIT")
	var client_proof:=_permission(actor,p["firm"],"purchase",o["denomination"],total,f["provider"],e._place(f["site_id"]),p.get("authorization_context",{}),"service:"+str(o["kind"]).to_lower())
	var provider_actor: String=e.firm_manager_at(f["provider"],now)
	var supply:=_permission(provider_actor,f["provider"],"supply",o["denomination"],total,p["firm"],e._place(f["site_id"]),{},"service:"+str(o["kind"]).to_lower())
	if not client_proof["ok"] or not supply["ok"]: return _reject(client_proof.get("reason",supply.get("reason","SERVICE_AUTHORITY_FAILED")))
	var plan: Dictionary=e._budgets.plan(p["payer"],o["denomination"],"service:"+str(o["kind"]).to_lower(),total,now)
	if not plan["ok"]: return _reject(plan["reason"])
	if plan.has("rule_id") and e._budgets.rule(plan["rule_id"])["basis"]!="EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY" and client_proof.get("root_proof",{}).get("authority_id")!=plan["root_authority"]: return _reject("SERVICE_BUDGET_ROOT_AUTHORITY_MISMATCH")
	if e._world.ledger_state.available_balance(e._account(p["payer"],o["denomination"]))<total: return _reject("SERVICE_CASH_NOT_AVAILABLE")
	if preview:
		return {"accepted":true,"reason":"KNOWN_SERVICE_WITH_CURRENT_AUTHORITY_FUNDS_AND_CAPACITY","permission":client_proof}
	var id:="service:"+action
	if not e._world.ledger_state.reserve(id,e._account(p["payer"],o["denomination"]),total): return _reject("SERVICE_CASH_NOT_AVAILABLE")
	if not rows.is_empty():
		var adopted: Array[Dictionary]=e._lots.move(rows,"SITE|"+source,e._place(source),now,"","",id)
		assert(not adopted.is_empty())
	var plans: Array[Dictionary]=[plan]
	var committed: bool=e._budgets.commit(id,plans)
	assert(committed)
	contracts[id]={"id":id,"action_id":action,"actor":actor,"client":p["firm"],"payer":p["payer"],"provider":f["provider"],"provider_site":f["site_id"],"offer_id":o["id"],"facility_id":f["id"],"kind":o["kind"],"source_site":source,"good":good,"quantity":q,"periods_count":periods,"asset_id":asset,"accepted_minute":now,"started_minute":-1,"end_minute":-1,"last_boundary":-1,"repair_result_minute":-1,"status":"ACCEPTED","reason":"","paused":false,"total":total,"earned":0,"paid":0,"released":0,"charge_numerator":0,"work":[],"material_sources":[],"material_minute":-1,"custody_events":[],"periods":[],"payments":[],"permission":client_proof,"supply_permission":supply}
	if not publication.is_empty():
		contracts[id]["announcement_id"]=publication["id"]
		e._commercial.adopt(publication,id)
	_index(contracts[id])
	var adopted: Dictionary={"accepted":true,"reason":"SERVICE_ACCEPTED_FUNDS_AND_CAPACITY_COMMITTED","service_id":id,"locked_amount":total}
	if not publication.is_empty() and publication.kind=="GOODS":adopted["observed_goods_quote"]=publication.quote.duplicate(true)
	return adopted

func _work(c: Dictionary, wanted: int, purpose: String, used: Dictionary) -> int:
	var e:=economy()
	var o:=_offers[c["offer_id"]] as Dictionary
	var done:=0
	for id: String in e._capital_work_ids:
		var work:=e._work_records[id] as Dictionary
		if work["job"] not in o["job_ids"]: continue
		var q:=mini(wanted-done,int(work["hours"])-int(used.get(id,0)))
		if q<=0: continue
		c["work"].append({"id":id,"hours":q,"minute":e._world.game_clock.total_minutes(),"purpose":purpose})
		used[id]=int(used.get(id,0))+q
		_last_work[id]=int(_last_work.get(id,0))+q
		_labor[c["provider_site"]]=int(_labor.get(c["provider_site"],0))+q
		if not _labor_days.has(c["provider_site"]): _labor_days[c["provider_site"]]={}
		_labor_days[c["provider_site"]][e.day]=int(_labor_days[c["provider_site"]].get(e.day,0))+q
		e._labor[c["provider_site"]]=int(e._labor.get(c["provider_site"],0))-q
		if e._costs.enabled: e._costs.assign_work(id,q,"SERVICE",c["id"])
		done+=q
		if done==wanted: break
	return done
func _hours_available(c: Dictionary, used: Dictionary) -> int:
	var q:=0
	for id: String in economy()._capital_work_ids:
		var work:=economy()._work_records[id] as Dictionary
		if work["job"] in _offers[c["offer_id"]]["job_ids"]: q+=int(work["hours"])-int(used.get(id,0))
	return q
func work_hours(c: Dictionary, purpose: String="") -> int:
	var q:=0
	for row: Dictionary in c["work"]:
		if purpose.is_empty() or purpose==row["purpose"]: q+=int(row["hours"])
	return q
func allocated_hours(site: String, date: int=-1) -> int: return int(_labor.get(site,0)) if date<0 else int(_labor_days.get(site,{}).get(date,0))
func labor_needed(site: String) -> int:
	var q:=0
	for id: String in _active:
		var c:=contracts[id] as Dictionary
		if c["provider_site"]!=site or c["paused"] or c["status"] in ["COMPLETED","CANCELLED","EXPIRED_CUSTODY"]: continue
		if c["kind"] in Resident.KINDS and c["status"]!="ACCEPTED": continue
		q+=int(_offers[c["offer_id"]]["hours_per_day"])
	return q

func build(capital_used: Dictionary) -> void:
	_last_work.clear()
	var used:=capital_used.duplicate()
	var e:=economy()
	var now: int=e._world.game_clock.total_minutes()
	for id: String in _active.keys():
		var c:=contracts[id] as Dictionary
		if int(c["accepted_minute"])>=now: continue
		if c["kind"] in Resident.KINDS: _resident.build(c,used,now)
		elif c["kind"]=="STORAGE": _storage(c,used,now)
		elif c["kind"]=="ANNOUNCEMENT": e._commercial.build_publication(c,used,now)
		else: _repair(c,used,now)
		_pay(c,now)
		_index(c)

func _storage(c: Dictionary, used: Dictionary, now: int) -> void:
	var e:=economy()
	var o:=_offers[c["offer_id"]] as Dictionary
	var t:=o["storage_terms"] as Dictionary
	if c["status"] in ["CANCELLED","COMPLETED","EXPIRED_CUSTODY"]: return
	var can_work: bool=_enabled[o["id"]] and e._site_operating(c["provider_site"],now if c["started_minute"]<0 else maxi(0,now-1))
	if c["started_minute"]<0:
		var q: int=e._lots.reserved_quantity(c["id"])
		if not can_work or q<=0 or _hours_available(c,used)<t["intake_hours"]: c["reason"]="WAITING_PROPERTY_OR_ACTUAL_INTAKE_WORK"; return
		var shared: String=_facilities[c["facility_id"]]["shared_storage_id"]
		if not shared.is_empty() and not e._shared.service_intake_ready(shared,now): c["reason"]="WAITING_CURRENT_SHARED_STORAGE_WINDOW"; return
		var rows: Array[Dictionary]=e._lots.reserved_selection(c["id"],q)
		if not e._lots.ready(rows): c["reason"]="WAREHOUSE_SOURCE_CHANGED"; return
		_work(c,t["intake_hours"],"INTAKE",used)
		var moved: Array[Dictionary]=e._lots.move(rows,"SERVICE|"+c["id"],e._place(c["provider_site"]),now,"","","",c["provider_site"])
		assert(not moved.is_empty())
		c["started_minute"]=now; c["last_boundary"]=now; c["end_minute"]=now+int(c["periods_count"])*1440
		c["custody_events"].append({"id":"intake:"+c["id"],"kind":"IN","minute":now,"quantity":q,"portions":rows})
		c["status"]="ACTIVE"; c["reason"]=""
		return
	var until:=mini(now,int(c["end_minute"]))
	if until<=c["last_boundary"]: return
	var units:=unit_minutes(c,c["last_boundary"],until)
	var staffed: bool=can_work and _hours_available(c,used)>=t["supervision_hours"]
	if units==0: staffed=true
	if staffed and units>0: _work(c,t["supervision_hours"],"STORAGE",used)
	var previous:=int(c["earned"])
	if staffed:
		c["charge_numerator"]+=units*int(o["price"])
		c["earned"]=int(c["charge_numerator"])/1440
	c["periods"].append({"from":c["last_boundary"],"to":until,"minute":now,"unit_minutes":units,"staffed":staffed,"earned_delta":int(c["earned"])-previous})
	c["last_boundary"]=until
	c["reason"]="" if staffed else "PERIOD_UNSTAFFED_NO_NEW_FEE"
	if until==c["end_minute"] or _quantity_at(c,now)==0:
		c["status"]="COMPLETED" if _quantity_at(c,now)==0 else "EXPIRED_CUSTODY"
		_release_future(c,"end:"+c["id"])

func unit_minutes(c: Dictionary, begin: int, end: int) -> int:
	var cursor:=begin
	var q:=_quantity_at(c,begin)
	var total:=0
	for event: Dictionary in c["custody_events"]:
		if event["minute"]<=begin or event["minute"]>=end or event["kind"] not in ["OUT","LOSS"]: continue
		total+=q*(int(event["minute"])-cursor)
		q-=int(event["quantity"]); cursor=event["minute"]
	return total+q*(end-cursor)

func repair_terms(c: Dictionary) -> Dictionary:
	var asset:=economy()._capital.assets[c["asset_id"]] as Dictionary
	return economy()._capital.template(asset["template_id"])["maintenance"]
func _repair(c: Dictionary, used: Dictionary, now: int) -> void:
	var e:=economy()
	if c["repair_result_minute"]>=0 or c["status"]=="CANCELLED" or c["paused"]: return
	if not _enabled[c["offer_id"]] or not e._site_operating(c["provider_site"],now if c["started_minute"]<0 else maxi(0,now-1)): c["reason"]="REPAIR_PROVIDER_STOPPED"; return
	var terms:=repair_terms(c)
	if c["started_minute"]<0:
		var rows: Array[Dictionary]=[]
		for good: String in terms["materials"]:
			if int(e._physical_totals[c["provider_site"]]["used"][good])>FormalLedgerState.MAX_AMOUNT-int(terms["materials"][good]): c["reason"]="REPAIR_MATERIAL_ACCOUNTING_BOUNDS"; return
			var part: Array[Dictionary]=e._lots.selection("SITE|"+c["provider_site"],good,terms["materials"][good])
			if part.is_empty(): c["reason"]="WAITING_PROVIDER_REPAIR_MATERIALS"; return
			rows.append_array(part)
		if not e._lots.ready(rows) or _hours_available(c,used)<1: c["reason"]="WAITING_ACTUAL_REPAIR_WORK"; return
		if not e._capital.begin_external_maintenance(c): c["reason"]="ASSET_MAINTENANCE_CONDITION_CHANGED"; return
		if e._costs.enabled: e._costs.service_inputs(c["id"],rows)
		var adopted: bool=e.capital_take_goods(c["provider_site"],terms["materials"])
		assert(adopted)
		c["material_sources"]=rows; c["material_minute"]=now; c["started_minute"]=now
		c["status"]="WORKING"; c["reason"]=""
		return # Materials acquired now cannot consume yesterday's repair work.
	var wanted:=mini(int(_offers[c["offer_id"]]["hours_per_day"]),maxi(0,int(terms["hours"])-work_hours(c,"REPAIR")))
	if wanted>0: _work(c,wanted,"REPAIR",used)
	if work_hours(c,"REPAIR")>=terms["hours"] and now-int(c["started_minute"])>=terms["duration_minutes"] and e._capital.complete_external_maintenance(c):
		c["repair_result_minute"]=now; c["earned"]=c["total"]; c["status"]="COMPLETED"; c["reason"]=""
	else: c["reason"]="WAITING_REAL_REPAIR_WORK_OR_TIME"

func _pay(c: Dictionary, now: int) -> void:
	var due:=int(c["earned"])-int(c["paid"])
	if due<=0: return
	var e:=economy()
	var currency:=str(_offers[c["offer_id"]]["denomination"])
	var id:="service_payment:"+str(c["id"])+":"+str(c["earned"])
	var legs: Array[Dictionary]=[{"transaction_id":id,"from_account_id":e._account(c["payer"],currency),"to_account_id":e._account(c["provider"],currency),"amount":due,"kind":"service_fee","reference_id":c["id"]}]
	if not e._world.ledger_state.batch_payment(id,legs,now,{str(c["id"]):due}): c["reason"]="EARNED_SERVICE_FEE_PAYABLE"; return
	c["paid"]=c["earned"]
	c["payments"].append({"id":id,"minute":now,"amount":due,"cumulative_paid":c["paid"]})
	_payment_contract[id]=c["id"]
	var settled: bool=e._budgets.settle(id,c["id"],c["paid"],c["released"],c["total"])
	assert(settled)

func _release_future(c: Dictionary, event: String) -> void:
	var amount:=int(c["total"])-int(c["earned"])-int(c["released"])
	if amount<=0: return
	var e:=economy()
	var released: bool=e._world.ledger_state.release(c["id"],amount)
	assert(released)
	c["released"]+=amount
	var settled: bool=e._budgets.settle("service_release:"+event,c["id"],c["paid"],c["released"],c["total"])
	assert(settled)

func budget_contracts() -> Dictionary:
	var result: Dictionary={}
	for c: Dictionary in contracts.values(): result[c["id"]]={"id":c["id"],"kind":"SERVICE","buyer":c["payer"],"denomination":_offers[c["offer_id"]]["denomination"],"accepted_minute":c["accepted_minute"],"category":"service:"+str(c["kind"]).to_lower(),"price":1,"quantity":c["total"],"delivered":c["paid"],"cancelled":c["released"],"route_legs":[]}
	return result
func cash_reservations() -> Dictionary:
	var result: Dictionary={}
	for c: Dictionary in contracts.values():
		var amount:=int(c["total"])-int(c["paid"])-int(c["released"])
		if amount>0: result[c["id"]]={"account_id":economy()._account(c["payer"],_offers[c["offer_id"]]["denomination"]),"amount":amount}
	return result
func stock_delta(site: String, good: String) -> int:
	var amount:=0
	for c: Dictionary in contracts.values():
		if c["kind"]!="STORAGE" or c["source_site"]!=site or c["good"]!=good: continue
		for event: Dictionary in c["custody_events"]:
			if event["kind"]=="IN": amount-=int(event["quantity"])
			elif event["kind"]=="OUT": amount+=int(event["quantity"])
	return amount
func consumed_goods(site: String, good: String, saved_portions: Dictionary={}) -> int:
	var q:=0
	var portions: Dictionary=economy()._lots.portions if saved_portions.is_empty() else saved_portions
	for c: Dictionary in contracts.values():
		if c["kind"] in ["REPAIR","DINING","HAIRCUT"] and c["provider_site"]==site:
			for row: Dictionary in c["material_sources"]:
				if portions[row["portion_id"]]["good"]==good: q+=int(row["quantity"])
	return q
func keeper_reason(subject: String) -> String:
	for id: String in _active:
		var c:=contracts[id] as Dictionary
		if subject in [c["client"],c["provider"],c["source_site"],c["provider_site"]]: return "SERVICE_CUSTODY_WORK_OR_PAYMENT_REMAINS"
	return ""
func loss_ready(id: String, q: int) -> bool: return contracts.has(id) and contracts[id]["kind"]=="STORAGE" and q<=_quantity_at(contracts[id],economy()._world.game_clock.total_minutes())
func adopted_loss(id: String, loss: String, rows: Array[Dictionary], q: int) -> void:
	var c:=contracts[id] as Dictionary
	c["custody_events"].append({"id":loss,"kind":"LOSS","minute":economy()._world.game_clock.total_minutes(),"quantity":q,"portions":rows.duplicate(true)})
	if c["status"]=="EXPIRED_CUSTODY" and _quantity_at(c,economy()._world.game_clock.total_minutes())==0: c["status"]="COMPLETED"
	_index(c)

func npc_decisions() -> void:
	var e:=economy()
	for id: String in _active.keys():
		var c:=contracts[id] as Dictionary
		if c["kind"]=="STORAGE" and c["status"]=="EXPIRED_CUSTODY" and e.firm_manager_at(c["client"],e._world.game_clock.total_minutes())==c["client"]:
			var q: int=e._lots.quantity_at("SERVICE|"+id,c["good"])
			if q>0: e._accept(c["client"],e._auto_command(c["client"],"withdraw_service_goods",{"service_id":id,"quantity":q},id),true)
			if _quantity_at(c,e._world.game_clock.total_minutes())==0: c["status"]="COMPLETED"; _index(c)
	for p: Dictionary in e.config.get("service_market",{}).get("npc_policies",[]):
		var firm:=str(p["firm"])
		if e._firm_winding_down(firm) or e.firm_manager_at(firm,e._world.game_clock.total_minutes())!=firm or e.day<int(_last_npc.get(firm,-p["cooldown_days"]))+int(p["cooldown_days"]): continue
		for quote: Dictionary in quotes(firm):
			if not quote["valid"] or not quote["enabled"] or quote["available_capacity"]<1: continue
			var payload: Dictionary={"firm":firm,"payer":firm,"offer_id":quote["id"],"max_amount":FormalLedgerState.MAX_AMOUNT}
			if quote["kind"]=="STORAGE" and quote["id"]==p["storage_offer"] and e.capital_free_goods(p["source_site"],p["good"])>=p["trigger_quantity"]:
				payload.merge({"source_site":p["source_site"],"good":p["good"],"quantity":p["store_quantity"],"periods":p["periods"]})
			elif quote["kind"]=="REPAIR" and quote["id"]==p["repair_offer"]:
				for site: String in e._spec["firms"][firm]["sites"]:
					for id: String in e._capital.installed_assets(site):
						if e._capital.assets[id]["status"]=="PAUSED" and not asset_busy(id): payload["asset_id"]=id; break
				if not payload.has("asset_id"): continue
			else: continue
			var result: Dictionary=e._accept(firm,e._auto_command(firm,"request_service",payload,quote["id"]),true)
			if result.get("accepted",false): break

func view(firm: String) -> Dictionary:
	var rows: Array[Dictionary]=[]
	var ids: Array=_by_firm.get(firm,[])
	for index: int in range(maxi(0,ids.size()-8),ids.size()):
		var c:=contracts[ids[index]] as Dictionary
		var row:=c.duplicate(true)
		row.erase("permission"); row.erase("supply_permission")
		var observer: String=economy().firm_manager_at(firm,economy()._world.game_clock.total_minutes())
		var unseen_loss:=0
		var visible_events: Array[Dictionary]=[]
		for event: Dictionary in c["custody_events"]:
			if event["kind"]=="LOSS" and not economy()._cargo_fulfilment.knows_loss(observer,event["id"]): unseen_loss+=int(event["quantity"])
			else: visible_events.append(event.duplicate(true))
		row["custody_events"]=visible_events
		row["remaining_custody_quantity"]=_quantity_at(c,economy()._world.game_clock.total_minutes()) if c["kind"]=="STORAGE" else 0
		if unseen_loss>0:
			row["remaining_custody_quantity"]+=unseen_loss
			row["status"]="AWAITING_CUSTODY_NOTICE"; row["reason"]="WAREHOUSE_CHANGE_NOTICE_NOT_RECEIVED"
		row["payable"]=int(c["earned"])-int(c["paid"])
		row["denomination"]=_offers[c["offer_id"]]["denomination"]
		row["completed_work_hours"]=work_hours(c)
		row["required_work_hours"]=int(c["quantity"])*int(_offers[c["offer_id"]]["resident_terms"]["hours_per_unit"]) if c["kind"] in Resident.KINDS else repair_terms(c)["hours"] if c["kind"]=="REPAIR" else int(_offers[c["offer_id"]]["announcement_terms"]["work_hours"]) if c["kind"]=="ANNOUNCEMENT" else int(_offers[c["offer_id"]]["storage_terms"]["intake_hours"])+int(c["periods_count"])*int(_offers[c["offer_id"]]["storage_terms"]["supervision_hours"])
		if c["provider"]==firm:
			row["direct_cost"]=economy()._costs.service_cost(c["id"]) if economy()._costs.enabled else {"amounts":{},"unknown":["COST_ACCOUNTING_NOT_ENABLED"]}
		else:
			row.erase("work"); row.erase("material_sources")
		rows.append(row)
	return {"enabled":not _offers.is_empty(),"quotes":quotes(firm),"contracts":rows,"basis":"REAL_CUSTODY_AND_EXTERNAL_MAINTENANCE_NOT_GOODS_SALES"}

func materials_needed(site: String, good: String) -> int:
	var q:=0
	for id: String in _active:
		var c:=contracts[id] as Dictionary
		if c["kind"] in Resident.KINDS and c["provider_site"]==site: q+=_resident.materials_needed(c,good)
		if c["kind"]=="REPAIR" and c["provider_site"]==site and c["started_minute"]<0 and c["status"]!="CANCELLED": q+=int(repair_terms(c)["materials"].get(good,0))
	return q
func asset_maintenance_cost(asset: String) -> Dictionary:
	var result:={"amounts":{},"contracts":[]}
	for id: String in _asset_history.get(asset,[]):
		var c:=contracts[id] as Dictionary
		if c["earned"]>0:
			var currency:=str(_offers[c["offer_id"]]["denomination"])
			result["amounts"][currency]=int(result["amounts"].get(currency,0))+int(c["earned"])
			result["contracts"].append(id)
	return result
func valid_payment_batch(id: String) -> bool:
	var e:=economy()
	var key: String=_payment_contract.get(id, str(id.trim_prefix("service_payment:")).rsplit(":",true,1)[0])
	if not contracts.has(key) or not contracts[key].get("payments") is Array: return false
	for c: Dictionary in [contracts[key]]:
		for p: Dictionary in c["payments"]:
			if p["id"]!=id: continue
			var batch: Dictionary=e._world.ledger_state.payment_batch(id)
			var currency:=str(_offers[c["offer_id"]]["denomination"])
			var tx: Dictionary=e._world.ledger_state.transaction(id)
			return batch.get("transactions")==[id] and batch.get("minute")==p["minute"] and batch.get("releases")=={str(c["id"]):p["amount"]} and tx.get("reference_id")==c["id"] and tx.get("kind")=="service_fee" and tx.get("amount")==p["amount"] and tx.get("from_account_id")==e._account(c["payer"],currency) and tx.get("to_account_id")==e._account(c["provider"],currency) and tx.get("denomination")==currency and tx.get("effective_minute")==p["minute"]
	return false

func recent_contracts(firm: String, from_minute: int) -> Array[String]:
	var ids: Dictionary={}
	for date: int in range(from_minute/1440,economy().day+1):
		for id: String in _days.get(firm,{}).get(date,{}): ids[id]=true
	var result: Array[String]=[]
	result.assign(ids.keys())
	result.sort()
	return result

func business_view(actor: String, firm: String, site: String, quantity: int) -> Dictionary:
	var result:=view(firm)
	var actions: Array[Dictionary]=[]
	var e:=economy()
	for quote: Dictionary in result["quotes"]:
		if not quote["enabled"] or not quote["valid"]: continue
		if quote["kind"]=="STORAGE":
			var f:=_facilities[quote["facility_id"]] as Dictionary
			for good: String in f["good_units"]:
				if e._place(site)!=quote["place_id"]: continue
				actions.append({"kind":"request_service","label":"仓储 "+good+" · 每单位每日 "+str(quote["price"]),"payload":{"firm":firm,"payer":firm,"offer_id":quote["id"],"source_site":site,"good":good,"quantity":quantity,"periods":1,"max_amount":int(quote["price"])*quantity}})
		elif quote["kind"]=="REPAIR":
			for asset: String in e._capital.installed_assets(site):
				if not asset_busy(asset) and e._place(site)==quote["place_id"] and e._capital.assets[asset]["status"] in ["ACTIVE","PAUSED"]:
					actions.append({"kind":"request_service","label":"委托维修 "+asset+" · "+str(quote["price"]),"payload":{"firm":firm,"payer":firm,"offer_id":quote["id"],"asset_id":asset,"max_amount":quote["price"]}})
	for row: Dictionary in result["contracts"]:
		if row["client"]!=firm: continue
		if row["kind"]=="STORAGE" and row["started_minute"]>=0 and row["remaining_custody_quantity"]>0: actions.append({"kind":"withdraw_service_goods","label":"取回 "+row["good"],"payload":{"service_id":row["id"],"quantity":mini(quantity,int(row["remaining_custody_quantity"]))}})
		if row["started_minute"]<0 and row["status"]!="CANCELLED": actions.append({"kind":"cancel_service","label":"取消未开始服务","payload":{"service_id":row["id"]}})
		if row["kind"]=="REPAIR" and row["repair_result_minute"]<0 and row["status"]!="CANCELLED": actions.append({"kind":"pause_service","label":"恢复维修" if row["paused"] else "暂停维修","payload":{"service_id":row["id"],"paused":not row["paused"]}})
	for id: String in _offers:
		if _facilities[_offers[id]["facility_id"]]["provider"]==firm: actions.append({"kind":"set_service_offer","label":"暂停接单及新工作 "+id if _enabled[id] else "恢复服务 "+id,"payload":{"offer_id":id,"enabled":not _enabled[id]}})
	for action: Dictionary in actions:
		if action["kind"]=="request_service":
			var preview:=_accept(actor,action["payload"],"",true)
			action["can_execute"]=preview["accepted"]
			action["reason"]=preview["reason"]
			if preview.get("permission",{}).has("root_proof"): action["payload"]["authorization_context"]=preview["permission"]["root_proof"]["context"].duplicate(true)
		elif action["kind"]=="set_service_offer":
			var o:=_offers[action["payload"]["offer_id"]] as Dictionary
			var f:=_facilities[o["facility_id"]] as Dictionary
			var proof:=_permission(actor,firm,"control",o["denomination"],0,o["id"],e._place(f["site_id"]))
			action["can_execute"]=proof["ok"]; action["reason"]=proof.get("reason","CURRENT_SERVICE_CONTROL_AUTHORITY")
		else:
			action["can_execute"]=true; action["reason"]="OWNER_ACTION_DOMAIN_RECHECK_REQUIRED"
	result["actions"]=actions
	return result

func _proof_valid(proof: Variant, actor: String, firm: String, op: String, amount: int, minute: int, currency: String, target: String, place: String, category: String) -> bool:
	if not proof is Dictionary or not EconomySliceConfig._fields(proof,["ok","authority_id","actor","firm","operation","amount","denomination","minute","source"],["root_proof"]) or proof["ok"]!=true or proof["actor"]!=actor or proof["firm"]!=firm or proof["operation"]!=op or proof["amount"]!=amount or proof["minute"]!=minute or proof["denomination"]!=currency or not proof["source"] is Dictionary or not economy()._manager_at(actor,firm,minute): return false
	var found:=false
	for p: Dictionary in economy().config.get("service_market",{}).get("authorities",[]):
		if p==proof["source"] and p["id"]==proof["authority_id"] and p["firm"]==firm and p["controller"]==actor and op in p["operations"] and amount<=p["limit"] and minute>=p["start_minute"] and minute<p["end_minute"] and proof["denomination"]==p["denomination"]: found=true
	if not found: return false
	if proof["source"]["root_authority"].is_empty(): return not proof.has("root_proof")
	return proof.has("root_proof") and economy()._cargo_fulfilment._saved_authority(proof["root_proof"]) and proof["root_proof"].get("authority_id")==proof["source"]["root_authority"] and proof["root_proof"].get("subject")==firm and proof["root_proof"].get("actor")==actor and proof["root_proof"].get("amount")==amount and proof["root_proof"].get("minute")==minute and proof["root_proof"].get("operation")==("economy.procure" if op=="purchase" else "economy.service."+op) and proof["root_proof"].get("target")==target and proof["root_proof"].get("place")==place and proof["root_proof"].get("category")==category

func restore(raw: Variant, saved: Dictionary) -> bool:
	if raw==null: return true
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw,["format","contracts","changes"]) or raw["format"]!=FORMAT or not raw["contracts"] is Dictionary or not raw["changes"] is Dictionary or not saved.get("stock_lots",{}).get("portions") is Dictionary: return _fail("Invalid service snapshot")
	var e:=economy()
	var now: int=e._world.game_clock.total_minutes()
	var physical:=saved["stock_lots"]["portions"] as Dictionary
	# The kernel installs StockLots after domain reference validation. Read the
	# candidate's portions here, never the still-empty candidate runtime projection.
	var custody_quantity: Dictionary={}
	var reserved_quantity: Dictionary={}
	for item: Variant in physical.values():
		if not item is Dictionary or not item.get("location") is String or not item.get("reserved_for") is String or not item.get("good") is String or not FormalLedgerState.valid_amount(item.get("remaining")): return _fail("Invalid candidate service stock reference")
		for key: String in ["id","source_id","owner","custodian","place_id"]:
			if not item.get(key) is String: return _fail("Invalid candidate service source identity")
		for key: String in ["opened_minute","consumed"]:
			if not item.get(key) is int: return _fail("Invalid candidate service portion boundary")
		var location_key:=str(item["location"])+"#"+str(item["good"])
		custody_quantity[location_key]=int(custody_quantity.get(location_key,0))+int(item["remaining"])
		reserved_quantity[item["reserved_for"]]=int(reserved_quantity.get(item["reserved_for"],0))+int(item["remaining"])
	contracts=raw["contracts"].duplicate(true); changes=raw["changes"].duplicate(true)
	_active.clear(); _by_firm.clear(); _by_facility.clear(); _by_asset.clear(); _labor.clear(); _labor_days.clear(); _facility_history.clear(); _asset_history.clear(); _days.clear(); _payment_contract.clear()
	_resident.reset_restore()
	var all_work: Dictionary={}
	for p: Dictionary in saved.get("capital_formation",{}).get("projects",{}).values():
		for row: Dictionary in p["work"]: all_work[row["id"]]=int(all_work.get(row["id"],0))+int(row["hours"])
	for h: Variant in saved.get("shared_transport",{}).get("handling",{}).values():
		if not h is Dictionary or not h.get("work") is Array: return _fail("Invalid candidate handling references")
		for row: Variant in h["work"]:
			if not row is Dictionary or not row.get("work_id") is String or not FormalLedgerState.valid_amount(row.get("hours")): return _fail("Invalid candidate shared work quantity")
			all_work[row["work_id"]]=int(all_work.get(row["work_id"],0))+int(row["hours"])
	var material_use: Dictionary={}
	for id: String in contracts:
		var c: Variant=contracts[id]
		if not c is Dictionary or not EconomySliceConfig._fields(c,CONTRACT_FIELDS,["resident","announcement_id"]) or c["id"]!=id or id!="service:"+str(c["action_id"]) or not _offers.has(c["offer_id"]): return _fail("Invalid service contract identity")
		for key: String in ["actor","client","payer","provider","provider_site","offer_id","facility_id","source_site","good","asset_id"]:
			if not c[key] is String: return _fail("Invalid service party or object identifier")
		if c["kind"] in Resident.KINDS:
			if not _resident.restore_contract(c,saved,all_work,material_use): return _fail(_resident.error)
			_index(c)
			continue
		if c.has("resident") or (c["kind"]!="ANNOUNCEMENT" and c.has("announcement_id")): return _fail("Business service contains wrong specialised fulfilment")
		var o:=_offers[c["offer_id"]] as Dictionary
		var f:=_facilities[o["facility_id"]] as Dictionary
		if c["facility_id"]!=f["id"] or c["kind"]!=o["kind"] or c["provider"]!=f["provider"] or c["provider_site"]!=f["site_id"] or not e._spec["firms"].has(c["client"]) or c["client"]==c["provider"] or c["payer"]!=c["client"] or not known(c["client"],o["id"],c["accepted_minute"]) or not c["paused"] is bool or not c["reason"] is String or c["status"] not in ["ACCEPTED","ACTIVE","WORKING","COMPLETED","CANCELLED","EXPIRED_CUSTODY"]: return _fail("Invalid service party or state")
		for key: String in ["quantity","periods_count","accepted_minute","total","earned","paid","released"]:
			if not FormalLedgerState.valid_amount(c[key]): return _fail("Invalid service quantity or money")
		if c["quantity"]>1000000: return _fail("Service quantity exceeds its admitted scope")
		for key: String in ["started_minute","end_minute","last_boundary","repair_result_minute","material_minute"]:
			if not c[key] is int or c[key]<-1 or c[key]>now: 
				if key!="end_minute" or not c[key] is int or c[key]<0 or c[key]>now+30*1440: return _fail("Invalid service time")
		for key: String in ["work","material_sources","custody_events","periods","payments"]:
			if not c[key] is Array: return _fail("Invalid service records")
		if c["accepted_minute"]>now or c["accepted_minute"]<o["notice_minute"] or c["accepted_minute"]<o["valid_from"] or c["accepted_minute"]>=o["valid_until"] or c["paid"]>c["earned"] or c["earned"]>int(c["total"])-int(c["released"]) or c["total"]<1 or c["quantity"]<1: return _fail("Service amount or quote date conflict")
		var command:=saved["commands"].get(c["action_id"],{}) as Dictionary
		var p:=command.get("envelope",{}).get("command",{}).get("payload",{}) as Dictionary
		if not command.get("result",{}).get("accepted",false) or command["result"].get("service_id")!=id or command["result"].get("locked_amount")!=c["total"] or command["envelope"]["actor"]!=c["actor"] or command["envelope"]["command"]["kind"]!="request_service" or command["envelope"]["command"]["minute"]!=c["accepted_minute"] or p.get("firm")!=c["client"] or p.get("payer")!=c["payer"] or p.get("offer_id")!=c["offer_id"] or p.get("max_amount",0)<c["total"]: return _fail("Service lacks accepted source action")
		if not _proof_valid(c["permission"],c["actor"],c["client"],"purchase",c["total"],c["accepted_minute"],o["denomination"],c["provider"],e._place(c["provider_site"]),"service:"+str(c["kind"]).to_lower()) or not c["supply_permission"] is Dictionary or not _proof_valid(c["supply_permission"],str(c["supply_permission"].get("actor","")),c["provider"],"supply",c["total"],c["accepted_minute"],o["denomination"],c["client"],e._place(c["provider_site"]),"service:"+str(c["kind"]).to_lower()): return _fail("Service lost independent purchase or supply authority")
		if c["kind"]=="STORAGE":
			if not e._spec["sites"].has(c["source_site"]) or e._owner(c["source_site"])!=c["client"] or e._place(c["source_site"])!=e._place(c["provider_site"]) or not f["good_units"].has(c["good"]) or p.get("source_site")!=c["source_site"] or p.get("good")!=c["good"] or p.get("quantity")!=c["quantity"] or p.get("periods")!=c["periods_count"] or c["total"]!=int(o["price"])*int(c["quantity"])*int(c["periods_count"]) or c["periods_count"]<1 or c["periods_count"]>o["storage_terms"]["max_periods"] or not c["material_sources"].is_empty() or c["material_minute"]!=-1 or not c["asset_id"].is_empty() or c["repair_result_minute"]!=-1: return _fail("Invalid warehouse contract scope")
		elif c["kind"]=="ANNOUNCEMENT":
			if not e._commercial.valid_contract(c,p): return _fail("Publication differs from original service contract")
		else:
			var a: Dictionary=saved.get("capital_formation",{}).get("assets",{}).get(c["asset_id"],{})
			if a.is_empty() or e._capital.asset_state(c["asset_id"],c["accepted_minute"])["owner"]!=c["client"] or a["asset_type"] not in o["repair_terms"]["asset_types"] or e._capital.asset_state(c["asset_id"],c["accepted_minute"])["place_id"]!=e._place(c["provider_site"]) or p.get("asset_id")!=c["asset_id"] or c["total"]!=o["price"] or c["quantity"]!=1 or not c["source_site"].is_empty() or not c["good"].is_empty() or not c["periods"].is_empty() or c["periods_count"]!=0: return _fail("Invalid repair asset or amount")
		var last:=int(c["accepted_minute"])
		var intake:=0; var out:=0; var lost:=0; var cancelled:=0; var cancellation_found:=false
		var loss_before_intake:=0
		for event: Variant in c["custody_events"]:
			if not event is Dictionary or not FormalLedgerState.exact_fields(event,["id","kind","minute","quantity","portions"]) or not event["id"] is String or event["kind"] not in ["IN","OUT","LOSS","CANCEL"] or not FormalLedgerState.valid_amount(event["minute"]) or event["minute"]<last or event["minute"]>now or not FormalLedgerState.valid_amount(event["quantity"]) or (event["quantity"]<1 and event["kind"]!="CANCEL") or not event["portions"] is Array: return _fail("Invalid service custody event")
			last=event["minute"]
			var cmd: Dictionary=saved["commands"].get(event["id"],{})
			if event["kind"] in ["OUT","CANCEL"]:
				if not cmd.get("result",{}).get("accepted",false) or cmd.get("envelope",{}).get("command",{}).get("payload",{}).get("service_id")!=id or cmd["envelope"]["command"]["minute"]!=event["minute"] or not e._manager_at(cmd["envelope"]["actor"],c["client"],event["minute"]): return _fail("Custody release lacks owner action")
				if cmd["envelope"]["command"]["kind"]!=("withdraw_service_goods" if event["kind"]=="OUT" else "cancel_service"): return _fail("Wrong service release action")
				if event["kind"]=="OUT" and cmd["envelope"]["command"]["payload"].get("quantity")!=event["quantity"]: return _fail("Returned quantity differs from owner action")
			if event["kind"]=="CANCEL":
				if cancellation_found: return _fail("Repeated service cancellation")
				cancellation_found=true
				cancelled+=event["quantity"]
				if c["started_minute"]!=-1 or not event["portions"].is_empty(): return _fail("Cancellation deletes incurred service")
				continue
			var q:=0
			for row: Variant in event["portions"]:
				if not row is Dictionary or not FormalLedgerState.exact_fields(row,["portion_id","source_id","quantity"]) or not physical.has(row.get("portion_id")) or row["source_id"]!=physical[row["portion_id"]]["source_id"] or not FormalLedgerState.valid_amount(row["quantity"]): return _fail("Service custody lost its actual source")
				var item:=physical[row["portion_id"]] as Dictionary
				if item["owner"]!=c["client"] or item["good"]!=c["good"] or item["place_id"]!=e._place(c["provider_site"]): return _fail("Service custody owner/place conflict")
				if event["kind"]=="IN" and (item["location"]!="SITE|"+str(c["source_site"]) or item["reserved_for"]!=id): return _fail("Warehouse intake lacks reserved client property")
				if event["kind"]=="OUT" and item["location"]!="SERVICE|"+id: return _fail("Warehouse withdrawal lacks actual custody")
				q+=int(row["quantity"])
			if q!=event["quantity"]: return _fail("Warehouse custody quantity conflict")
			if event["kind"]=="IN":
				if intake>0 or event["minute"]!=c["started_minute"] or event["id"]!="intake:"+id or q!=int(c["quantity"])-loss_before_intake: return _fail("Repeated or incomplete warehouse intake")
				intake=q
			elif event["kind"]=="OUT": out+=q
			else:
				var fact: Dictionary=saved["stock_lots"]["losses"].get(event["id"],{})
				if fact.get("portions")!=event["portions"] or fact.get("minute")!=event["minute"] or saved.get("cargo_fulfilment",{}).get("losses",{}).get(event["id"],{}).get("service_id")!=id: return _fail("Warehouse loss lacks adopted physical fact")
				lost+=q
				if intake==0: loss_before_intake+=q
		if out+lost+cancelled>c["quantity"] or (c["status"]=="CANCELLED")!=cancellation_found: return _fail("Warehouse releases more than the client's quantity")
		if c["kind"]=="STORAGE":
			var remaining:=int(c["quantity"])-out-lost-cancelled
			if c["started_minute"]<0:
				if int(reserved_quantity.get(id,0))!=remaining or int(custody_quantity.get("SERVICE|"+id+"#"+str(c["good"]),0))!=0: return _fail("Unstarted warehouse lost its actual reserved property")
			elif int(custody_quantity.get("SERVICE|"+id+"#"+str(c["good"]),0))!=remaining or int(reserved_quantity.get(id,0))!=0: return _fail("Warehouse physical custody differs from contract remainder")
		var day_hours: Dictionary={}
		for row: Variant in c["work"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row,["id","hours","minute","purpose"]) or not saved["work_records"].has(row.get("id")) or not FormalLedgerState.valid_amount(row["hours"]) or row["hours"]<1 or row["purpose"] not in (["INTAKE","STORAGE"] if c["kind"]=="STORAGE" else ["ANNOUNCEMENT"] if c["kind"]=="ANNOUNCEMENT" else ["REPAIR"]): return _fail("Invalid service labor")
			var work:=saved["work_records"][row["id"]] as Dictionary
			if not work.get("job") is String or not FormalLedgerState.valid_amount(work.get("day")) or not FormalLedgerState.valid_amount(work.get("hours")): return _fail("Invalid actual work interval reference")
			if work["job"] not in o["job_ids"] or row["minute"]!=int(work["day"])*1440 or row["minute"]<=c["accepted_minute"] or (row["purpose"]=="REPAIR" and row["minute"]<=c["started_minute"]): return _fail("Service labor lacks qualified actual site and interval")
			all_work[row["id"]]=int(all_work.get(row["id"],0))+int(row["hours"])
			if all_work[row["id"]]>work["hours"]: return _fail("Service reused production/construction/handling work")
			day_hours[work["day"]]=int(day_hours.get(work["day"],0))+int(row["hours"])
			_labor[c["provider_site"]]=int(_labor.get(c["provider_site"],0))+int(row["hours"])
			if not _labor_days.has(c["provider_site"]): _labor_days[c["provider_site"]]={}
			_labor_days[c["provider_site"]][work["day"]]=int(_labor_days[c["provider_site"]].get(work["day"],0))+int(row["hours"])
		if not _validate_fulfilment(c,saved,intake,day_hours,material_use): return false
		if not restore_payments(c,now): return false
		_index(c)
		for firm: String in [c["client"],c["provider"]]:
			for period: Dictionary in c["periods"]:
				var date:=int(period["minute"])/1440
				if not _days[firm].has(date): _days[firm][date]={}
				_days[firm][date][id]=true
			if c["repair_result_minute"]>=0:
				var date:=int(c["repair_result_minute"])/1440
				if not _days[firm].has(date): _days[firm][date]={}
				_days[firm][date][id]=true
	var change_ids: Array=changes.keys()
	change_ids.sort_custom(func(a: String,b: String) -> bool: return int(changes[a].get("sequence",-1))<int(changes[b].get("sequence",-1)))
	var change_sequence:=0
	var change_minute:=0
	for id: String in change_ids:
		var row: Variant=changes[id]
		var cmd: Dictionary=saved["commands"].get(id,{})
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["actor","kind","payload","minute","permission","sequence"]) or not cmd.get("result",{}).get("accepted",false) or cmd["envelope"]["actor"]!=row["actor"] or cmd["envelope"]["command"]["kind"]!=row["kind"] or cmd["envelope"]["command"]["payload"]!=row["payload"] or cmd["envelope"]["command"]["minute"]!=row["minute"]: return _fail("Service control lost action source")
		if not FormalLedgerState.valid_amount(row["sequence"]) or not FormalLedgerState.valid_amount(row["minute"]) or not row["payload"] is Dictionary: return _fail("Invalid service control boundary")
		if row["sequence"]!=change_sequence or row["minute"]<change_minute or row["minute"]>now: return _fail("Service control sequence conflict")
		change_sequence+=1; change_minute=row["minute"]
		if row["kind"]=="set_service_offer":
			var o: Dictionary=_offers.get(row["payload"].get("offer_id"),{})
			if o.is_empty() or not _proof_valid(row["permission"],row["actor"],_facilities[o["facility_id"]]["provider"],"control",0,row["minute"],o["denomination"],o["id"],e._place(_facilities[o["facility_id"]]["site_id"]),"service:control"): return _fail("Service offer control lost authority")
			_enabled[o["id"]]=row["payload"]["enabled"]
		elif row["kind"]!="pause_service" or not contracts.has(row["payload"].get("service_id")) or not e._manager_at(row["actor"],contracts[row["payload"]["service_id"]]["client"],row["minute"]): return _fail("Repair pause lost client authority")
	for c: Dictionary in contracts.values():
		var paused:=false
		for change: String in change_ids:
			var row:=changes[change] as Dictionary
			if row["kind"]=="pause_service" and row["payload"].get("service_id")==c["id"]: paused=row["payload"]["paused"]
		if c["paused"]!=paused: return _fail("Service pause differs from accepted control")
	for facility: String in _facility_history:
		var dates: Dictionary={}
		for id: String in _facility_history[facility]:
			var c:=contracts[id] as Dictionary
			if c["kind"] in Resident.KINDS: continue
			dates[c["accepted_minute"]]=true
			for event: Dictionary in c["custody_events"]: dates[event["minute"]]=true
		for minute: int in dates:
			var occupied:=0
			for id: String in _facility_history[facility]: occupied+=_occupied(contracts[id],minute)
			if occupied>_facilities[facility]["capacity"]: return _fail("Service facility overcommitted")
	for asset: String in _asset_history:
		for id: String in _asset_history[asset]:
			var count:=0
			for other: String in _asset_history[asset]: count+=_occupied(contracts[other],contracts[id]["accepted_minute"])
			if count>1: return _fail("Same equipment has overlapping external repairs")
	if not _resident.finish_restore(saved): return _fail(_resident.error)
	return true

func restore_payments(c: Dictionary,now: int) -> bool:
	var paid:=0; var payment_minute:=int(c["accepted_minute"])
	for pmt: Variant in c["payments"]:
		if not pmt is Dictionary or not FormalLedgerState.exact_fields(pmt,["id","minute","amount","cumulative_paid"]) or not FormalLedgerState.valid_amount(pmt["amount"]) or pmt["amount"]<1: return _fail("Invalid service payment")
		if not FormalLedgerState.valid_amount(pmt["minute"]) or pmt["minute"]<payment_minute or pmt["minute"]>now: return _fail("Invalid service payment time")
		paid+=int(pmt["amount"])
		var earned_at:=0
		if c["kind"] in Resident.KINDS:
			for receipt: Dictionary in c["resident"]["receipts"]:
				if receipt["minute"]<=pmt["minute"]: earned_at+=int(receipt["quantity"])*int(_offers[c["offer_id"]]["price"])
		elif c["kind"]=="REPAIR": earned_at=c["total"] if c["repair_result_minute"]>=0 and c["repair_result_minute"]<=pmt["minute"] else 0
		else:
			for period: Dictionary in c["periods"]:
				if period["minute"]<=pmt["minute"]: earned_at+=int(period["earned_delta"])
		if paid>earned_at: return _fail("Service paid before actual fulfilment")
		payment_minute=pmt["minute"]
		if pmt["cumulative_paid"]!=paid or pmt["id"]!="service_payment:"+str(c["id"])+":"+str(paid) or not valid_payment_batch(pmt["id"]): return _fail("Service payment differs from original Ledger")
	if paid!=c["paid"]: return _fail("Service paid total differs from receipts")
	for payment: Dictionary in c["payments"]: _payment_contract[payment["id"]]=c["id"]
	var ended: bool=c["status"] in ["COMPLETED","CANCELLED","EXPIRED_CUSTODY"]
	if c["released"]!=(int(c["total"])-int(c["earned"]) if ended else 0): return _fail("Service releases an unresolved future commitment")
	return true

func _validate_fulfilment(c: Dictionary, saved: Dictionary, intake: int, day_hours: Dictionary, material_use: Dictionary) -> bool:
	var e:=economy()
	var o:=_offers[c["offer_id"]] as Dictionary
	var physical:=saved["stock_lots"]["portions"] as Dictionary
	if c["kind"]=="ANNOUNCEMENT": return e._commercial.valid_fulfilment(c,day_hours) or _fail("Publication lacks actual work and release result")
	if c["started_minute"]<0:
		return (c["work"].is_empty() and c["material_sources"].is_empty() and c["earned"]==0 and c["end_minute"]==-1 and c["last_boundary"]==-1 and c["repair_result_minute"]==-1 and c["material_minute"]==-1 and c["status"] in ["ACCEPTED","CANCELLED"]) or _fail("Unstarted service has incurred work or income")
	if c["started_minute"]<=c["accepted_minute"] or c["started_minute"]%1440!=0: return _fail("Service start lacks a legal boundary")
	if c["kind"]=="STORAGE":
		if intake<1 or c["end_minute"]!=int(c["started_minute"])+int(c["periods_count"])*1440 or work_hours(c,"INTAKE")!=o["storage_terms"]["intake_hours"] or c["material_minute"]!=-1 or not c["charge_numerator"] is int or c["charge_numerator"]<0: return _fail("Warehouse start/work conflict")
		var through:=int(c["started_minute"])
		var numerator:=0
		var earned:=0
		for p: Variant in c["periods"]:
			if not p is Dictionary or not FormalLedgerState.exact_fields(p,["from","to","minute","unit_minutes","staffed","earned_delta"]): return _fail("Invalid warehouse period fields")
			for key: String in ["from","to","minute","unit_minutes","earned_delta"]:
				if not FormalLedgerState.valid_amount(p[key]): return _fail("Invalid warehouse period quantity or time")
			if p["from"]!=through or p["to"]!=mini(int(p["minute"]),int(c["end_minute"])) or p["to"]<=p["from"] or p["to"]-p["from"]>1440 or p["minute"]%1440!=0 or p["minute"]>e._world.game_clock.total_minutes() or not p["staffed"] is bool or p["unit_minutes"]!=unit_minutes(c,p["from"],p["to"]): return _fail("Warehouse period lacks actual custody interval")
			var hours:=0
			for row: Dictionary in c["work"]:
				if row["purpose"]=="STORAGE" and row["minute"]==p["minute"]: hours+=int(row["hours"])
			if hours!=(int(o["storage_terms"]["supervision_hours"]) if p["staffed"] and p["unit_minutes"]>0 else 0): return _fail("Warehouse fee lacks actual supervision")
			if p["staffed"]: numerator+=int(p["unit_minutes"])*int(o["price"])
			var next:=numerator/1440
			if p["earned_delta"]!=next-earned: return _fail("Warehouse cumulative fee conflict")
			earned=next; through=p["to"]
		if c["last_boundary"]!=through or c["charge_numerator"]!=numerator or c["earned"]!=earned: return _fail("Warehouse earned fee differs from supplied periods")
		var remaining:=_quantity_at(c,e._world.game_clock.total_minutes())
		if c["status"] not in ["ACTIVE","COMPLETED","EXPIRED_CUSTODY"] or (c["status"]=="COMPLETED" and remaining!=0) or (c["status"]=="EXPIRED_CUSTODY" and (remaining==0 or through!=c["end_minute"])) or (c["status"]=="ACTIVE" and through==c["end_minute"]): return _fail("Warehouse stage differs from actual occupancy and supplied term")
	else:
		var a:=saved["capital_formation"]["assets"][c["asset_id"]] as Dictionary
		var terms:=e._capital.template(a["template_id"])["maintenance"] as Dictionary
		var materials: Dictionary={}
		for row: Variant in c["material_sources"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row,["portion_id","source_id","quantity"]) or not physical.has(row.get("portion_id")) or not FormalLedgerState.valid_amount(row["quantity"]) or row["quantity"]<1: return _fail("Repair material reference invalid")
			var p:=physical[row["portion_id"]] as Dictionary
			if p["owner"]!=c["provider"] or p["location"]!="SITE|"+str(c["provider_site"]) or row["source_id"]!=p["source_id"] or p["opened_minute"]>c["material_minute"]: return _fail("Repair material owner/site/time invalid")
			material_use[p["id"]]=int(material_use.get(p["id"],0))+int(row["quantity"])
			if material_use[p["id"]]>p["consumed"]: return _fail("Repair reused material")
			materials[p["good"]]=int(materials.get(p["good"],0))+int(row["quantity"])
		if materials!=terms["materials"] or c["material_minute"]!=c["started_minute"] or work_hours(c,"REPAIR")>terms["hours"] or c["end_minute"]!=-1 or c["last_boundary"]!=-1 or c["charge_numerator"]!=0: return _fail("Repair scope differs from original equipment maintenance")
		for date: int in day_hours:
			if day_hours[date]>o["hours_per_day"]: return _fail("Repair exceeds advertised daily workforce")
		var start_found:=false; var result_found:=false
		for event: Dictionary in a["events"]:
			if event["source"]!=c["action_id"]: continue
			if event["status"]=="MAINTENANCE" and event["minute"]==c["started_minute"]: start_found=true
			if event["status"]=="ACTIVE" and event["minute"]==c["repair_result_minute"]: result_found=true
		if not start_found or (c["repair_result_minute"]>=0)!=(result_found) or (result_found and (work_hours(c,"REPAIR")!=terms["hours"] or c["repair_result_minute"]-c["started_minute"]<terms["duration_minutes"])) or c["earned"]!=(c["total"] if result_found else 0): return _fail("Repair invoice lacks real Capital result")
		if c["status"]!=("COMPLETED" if result_found else "WORKING"): return _fail("Repair stage differs from actual equipment result")
	return true
func snapshot() -> Dictionary: return {"format":FORMAT,"contracts":contracts.duplicate(true),"changes":changes.duplicate(true)}
func _reject(reason: String) -> Dictionary: return {"accepted":false,"reason":reason}
func _fail(reason: String) -> bool: error=reason; return false
