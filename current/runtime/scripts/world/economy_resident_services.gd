class_name EconomyResidentServices
extends RefCounted
## On-site execution rules inside EconomyServiceMarket. Contracts/receipts remain
## in that market; these maps are rebuilt query indexes, never wallets or stock.
const KINDS: Array[String]=["DINING","HAIRCUT"]
var _ref: WeakRef
var error: String=""
var _next_receipt: int=1
var _food_days: Dictionary={}
var _target_spans: Dictionary={}
var _restore_receipts: Array[Dictionary]=[]
func bind(m: RefCounted) -> void: _ref=weakref(m)
static func _may_discover(actor: String, id: String, settings: Dictionary, offers: Dictionary) -> bool:
	# Policy eligibility is not knowledge. Runtime still requires a delivered receipt.
	var facility: String=offers[id]["facility_id"]
	var place:=""
	for f: Dictionary in settings.get("service_market",{}).get("facilities",[]):
		if f["id"]==facility:
			for firm: Dictionary in settings["firms"]:
				for site: Dictionary in firm.get("sites",[]):
					if site["id"]==f["site_id"]: place=site["place_id"]
	for channel: Dictionary in settings.get("commercial_information",{}).get("channels",[]):
		if actor in channel["recipients"] and channel["place_id"]==place: return true
	return false
func market() -> RefCounted: return _ref.get_ref()
func economy() -> RefCounted: return market().economy()
static func valid_terms(o: Dictionary, settings: Dictionary, spec: Dictionary) -> bool:
	var t: Variant=o.get("resident_terms")
	if not t is Dictionary or not FormalLedgerState.exact_fields(t,["materials","hours_per_unit","need_id","units_per_service","time_basis"]) or t["time_basis"]!="NEXT_DAY_ON_SITE_NO_WORK_SHARE" or not t["materials"] is Dictionary or not t["need_id"] is String or not FormalLedgerState.valid_amount(t["hours_per_unit"]) or t["hours_per_unit"]<1 or t["hours_per_unit"]>8 or not FormalLedgerState.valid_amount(t["units_per_service"]) or t["units_per_service"]!=1: return false
	for good: String in t["materials"]:
		if good not in spec["good_ids"] or not FormalLedgerState.valid_amount(t["materials"][good]) or t["materials"][good]<1 or t["materials"][good]>1000: return false
	if o["kind"]=="DINING":
		var food:=0
		for good: String in t["materials"]: food+=int(t["materials"][good])*int(EconomySliceConfig.consumption(settings).get(good,{}).get("food",0))
		return t["need_id"]=="food" and spec["categories"].get("food",{}).get("mode")=="flow" and food>=t["units_per_service"]
	return t["materials"].is_empty() and not t["need_id"].is_empty() and t["need_id"]!="food"
static func valid_policies(v: Dictionary, settings: Dictionary, spec: Dictionary, offers: Dictionary) -> bool:
	for key: String in ["resident_targets","resident_policies"]:
		if not v.get(key,[]) is Array or v.get(key,[]).size()>128: return false
	var targets: Dictionary={}
	for t: Variant in v.get("resident_targets",[]):
		if not t is Dictionary or not FormalLedgerState.exact_fields(t,["customer","need_id","period_days","start_minute","basis"]) or not t["customer"] is String or (not spec["actors"].has(t["customer"]) and not (t["customer"]=="HOST_SELECTED_PLAYER" and settings.get("host_personal_accounts",false))) or not t["need_id"] is String or t["need_id"].is_empty() or t["need_id"]=="food" or not FormalLedgerState.valid_amount(t["period_days"]) or t["period_days"]<1 or t["period_days"]>365 or not FormalLedgerState.valid_amount(t["start_minute"]) or t["start_minute"]%1440!=0 or t["basis"]!="EXPLICIT_DEVELOPMENT_RESIDENT_SERVICE_TARGET": return false
		var key:=str(t["customer"])+"|"+str(t["need_id"])
		if targets.has(key): return false
		targets[key]=true
	for p: Variant in v.get("resident_policies",[]):
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["customer","offer_ids","quantity_limit","budget_limit","budget_window_days","priority","basis"]) or not spec["actors"].has(p.get("customer")) or spec["actors"][p["customer"]]["control"]!="automatic" or not p["offer_ids"] is Array or p["offer_ids"].size()>8 or p["priority"]!="SERVICE_FIRST_KNOWN_LOCAL_WITHIN_BUDGET" or p["basis"]!="EXPLICIT_DEVELOPMENT_RESIDENT_SERVICE_DEMAND": return false
		for key: String in ["quantity_limit","budget_limit","budget_window_days"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]<1 or p[key]>1000000: return false
		if p["budget_window_days"]>365: return false
		for id: Variant in p["offer_ids"]:
			if not id is String or not offers.has(id) or offers[id]["kind"] not in KINDS or (p["customer"] not in offers[id]["known_to"] and not _may_discover(p["customer"],id,settings,offers)): return false
	return true
func target(actor: String, need: String) -> Dictionary:
	for t: Dictionary in economy().config.get("service_market",{}).get("resident_targets",[]):
		if t["customer"]==actor and t["need_id"]==need: return t
	return {}
func window(actor: String, need: String, minute: int) -> Vector2i:
	var t:=target(actor,need)
	if t.is_empty() or minute<int(t["start_minute"]): return Vector2i(-1,-1)
	var size:=int(t["period_days"])*1440
	var start:=int(t["start_minute"])+(minute-int(t["start_minute"]))/size*size
	return Vector2i(start,start+size)
func _key(actor: String,need: String,start: int) -> String: return actor+"|"+need+"|"+str(start)
func _free(members: int, occupied: Array[Vector2i]) -> Vector2i:
	occupied.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.x<b.x)
	var cursor:=0
	for span: Vector2i in occupied:
		if span.x>cursor: return Vector2i(cursor,span.x-cursor)
		cursor=maxi(cursor,span.y)
	return Vector2i(cursor,maxi(0,members-cursor))
func _spans(c: Dictionary) -> Dictionary: return c["resident"]["bookings"].back()
func _customer(actor: String, minute: int) -> bool:
	var e:=economy()
	return e._spec["actors"].has(actor) and e.subject_active_at(actor,minute) and e._spec["actors"][actor]["control"]!="dormant" and (not e._declared_named(actor) or e._world.person_overlay.is_alive(actor))
func can_book(actor: String, offer: Dictionary, minute: int) -> bool:
	return _customer(actor,minute) and economy()._at_place(actor,economy()._place(market()._facilities[offer["facility_id"]]["site_id"]))
func free_members(actor: String, scheduled: int, prefer_need: String="") -> Vector2i:
	var e:=economy()
	var occupied: Array[Vector2i]=[]
	if e._declared_named(actor):
		if e._work_queue.has(actor): occupied.append(Vector2i(0,1))
	else:
		for c: Dictionary in e._contract_rows(e._contracts.get(actor,{})):
			occupied.append(Vector2i(int(c.get("labor_start",0)),int(c.get("labor_start",0))+int(c["workers"])))
	for id: String in market()._active:
		var c:=market().contracts[id] as Dictionary
		if c["client"]!=actor or c["kind"] not in KINDS or c["status"]!="ACCEPTED": continue
		var b:=_spans(c)
		if b["scheduled_minute"]==scheduled: occupied.append(Vector2i(b["member_start"],int(b["member_start"])+int(b["quantity"])))
	if not prefer_need.is_empty():
		var w:=window(actor,prefer_need,scheduled)
		var preferred:=occupied.duplicate()
		preferred.append_array(_target_spans.get(_key(actor,prefer_need,w.x),[]))
		var space:=_free(e._actors[actor]["members"],preferred)
		if space.y>0: return space
	return _free(e._actors[actor]["members"],occupied)
func booked(actor: String) -> bool:
	for id: String in market()._active:
		var c:=market().contracts[id] as Dictionary
		if c["client"]==actor and c["kind"] in KINDS and c["status"]=="ACCEPTED" and _spans(c)["scheduled_minute"]>economy()._world.game_clock.total_minutes(): return true
	return false
func work_conflict(actor: String, job: String, date: int, allocation: Dictionary = {}) -> bool:
	var e:=economy()
	# Candidate validation runs before live employment is installed. Its caller
	# supplies the already validated saved allocation, including labor_start.
	var c: Dictionary=allocation if not allocation.is_empty() else e._contract_for(actor,job)
	var start:=int(c.get("labor_start",0));var end:=start+int(c.get("workers",1))
	for id: String in market()._active:
		var s:=market().contracts[id] as Dictionary
		if s["client"]!=actor or s["kind"] not in KINDS or s["status"]!="ACCEPTED": continue
		var b:=_spans(s)
		if b["scheduled_minute"]==date*1440 and start<int(b["member_start"])+int(b["quantity"]) and int(b["member_start"])<end: return true
	return false
func occupied(c: Dictionary, scheduled: int) -> int:
	if c["status"]!="ACCEPTED": return 0
	var b:=_spans(c)
	return int(b["quantity"]) if b["scheduled_minute"]==scheduled else 0
func available(facility: String, scheduled: int) -> int:
	var used:=0
	for id: String in market()._active:
		var c:=market().contracts[id] as Dictionary
		if c["facility_id"]==facility and c["kind"] in KINDS: used+=occupied(c,scheduled)
	return maxi(0,int(market()._facilities[facility]["capacity"])-used)
func accept(actor: String,p: Dictionary,action: String,preview: bool=false) -> Dictionary:
	var m:=market();var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if not FormalLedgerState.exact_fields(p,["customer","offer_id","quantity","max_amount"]) or p["customer"]!=actor or not m._offers.has(p["offer_id"]) or not FormalLedgerState.valid_amount(p["quantity"]) or p["quantity"]<1 or not FormalLedgerState.valid_amount(p["max_amount"]): return m._reject("INVALID_OWN_RESIDENT_SERVICE_REQUEST")
	var o:=m._offers[p["offer_id"]] as Dictionary
	if o["kind"] not in KINDS or not can_book(actor,o,now): return m._reject("RESIDENT_NOT_PRESENT_AT_SERVICE_PLACE")
	if now>FormalLedgerState.MAX_AMOUNT-1440: return m._reject("SERVICE_TIME_BOUNDS")
	if now%1440!=0: return m._reject("RESIDENT_SERVICE_REQUIRES_DAILY_BOOKING_BOUNDARY")
	var f:=m._facilities[o["facility_id"]] as Dictionary
	if not m._enabled[o["id"]] or not m.known(actor,o["id"],now) or now<o["valid_from"] or now>=o["valid_until"] or not e._site_accepting(f["site_id"]) or e._firm_winding_down(f["provider"]): return m._reject("NO_CURRENT_KNOWN_LEGAL_SERVICE_OFFER")
	var quantity:=int(p["quantity"])
	var span:=free_members(actor,now+1440,str(o["resident_terms"]["need_id"]) if o["kind"]=="HAIRCUT" else "")
	if quantity>span.y: return m._reject("RESIDENT_MEMBERS_ALREADY_BOOKED_FOR_WORK_OR_SERVICE")
	if quantity>available(f["id"],now+1440): return m._reject("RESIDENT_SERVICE_SLOT_FULL")
	if o["kind"]=="HAIRCUT" and window(actor,o["resident_terms"]["need_id"],now+1440).x<0: return m._reject("NO_CONFIGURED_PERSONAL_SERVICE_TARGET")
	var total:=int(o["price"])*quantity
	if not FormalLedgerState.valid_amount(total) or total>p["max_amount"]: return m._reject("SERVICE_LOCKED_COST_EXCEEDS_LIMIT")
	var supply: Dictionary=m._permission(e.firm_manager_at(f["provider"],now),f["provider"],"supply",o["denomination"],total,actor,e._place(f["site_id"]),{},"service:"+str(o["kind"]).to_lower())
	if not supply["ok"]: return m._reject(supply["reason"])
	var account: String=e._account(actor,o["denomination"])
	if e._world.ledger_state.account(account).get("owner_id")!=actor or e._world.ledger_state.available_balance(account)<total: return m._reject("SERVICE_CASH_NOT_AVAILABLE")
	if preview: return {"accepted":true,"reason":"OWN_RESIDENT_ACCOUNT_LOCAL_DAILY_SLOT"}
	var id:="service:"+action
	var plan: Dictionary=e._budgets.plan(actor,o["denomination"],"service:"+str(o["kind"]).to_lower(),total,now)
	if not plan["ok"]: return m._reject(plan["reason"])
	if plan.has("rule_id"): return m._reject("RESIDENT_IS_NOT_ORGANIZATION_PROCUREMENT_AUTHORITY")
	if not e._world.ledger_state.reserve(id,account,total): return m._reject("SERVICE_CASH_NOT_AVAILABLE")
	var plans: Array[Dictionary]=[plan]
	var committed: bool=e._budgets.commit(id,plans)
	assert(committed)
	m.contracts[id]={"id":id,"action_id":action,"actor":actor,"client":actor,"payer":actor,"provider":f["provider"],"provider_site":f["site_id"],"offer_id":o["id"],"facility_id":f["id"],"kind":o["kind"],"source_site":"","good":"","quantity":quantity,"periods_count":0,"asset_id":"","accepted_minute":now,"started_minute":-1,"end_minute":now+1440,"last_boundary":-1,"repair_result_minute":-1,"status":"ACCEPTED","reason":"","paused":false,"total":total,"earned":0,"paid":0,"released":0,"charge_numerator":0,"work":[],"material_sources":[],"material_minute":-1,"custody_events":[],"periods":[],"payments":[],"permission":{"basis":"OWN_RESIDENT_IDENTITY_AND_LEDGER_ACCOUNT","actor":actor,"account_id":account},"supply_permission":supply,"resident":{"fulfilled":0,"bookings":[{"action_id":action,"minute":now,"scheduled_minute":now+1440,"member_start":span.x,"quantity":quantity}],"receipts":[]}}
	m._index(m.contracts[id])
	return {"accepted":true,"reason":"RESIDENT_SERVICE_RESERVED_NOT_YET_CONSUMED","service_id":id,"locked_amount":total}
func reschedule(actor: String,c: Dictionary,action: String) -> Dictionary:
	var e:=economy();var m:=market();var now: int=e._world.game_clock.total_minutes()
	if c["client"]!=actor or c["status"]!="WAITING" or now%1440!=0 or not can_book(actor,m._offers[c["offer_id"]],now): return m._reject("RESIDENT_RESCHEDULE_REQUIRES_OWNER_LOCAL_DAILY_BOUNDARY")
	var q:=int(c["quantity"])-int(c["resident"]["fulfilled"])
	var offer:=m._offers[c["offer_id"]] as Dictionary
	var span:=free_members(actor,now+1440,offer["resident_terms"]["need_id"] if c["kind"]=="HAIRCUT" else "")
	if q>span.y or q>available(c["facility_id"],now+1440): return m._reject("RESIDENT_RESCHEDULE_WORK_OR_SLOT_CONFLICT")
	c["resident"]["bookings"].append({"action_id":action,"minute":now,"scheduled_minute":now+1440,"member_start":span.x,"quantity":q})
	c["end_minute"]=now+1440;c["status"]="ACCEPTED";c["reason"]=""
	m._index(c)
	return {"accepted":true,"reason":"SAME_SERVICE_COMMITMENT_RESCHEDULED"}
func cancel_allowed(c: Dictionary) -> bool: return c["resident"]["fulfilled"]==0
func materials_needed(c: Dictionary,good: String) -> int:
	return (int(c["quantity"])-int(c["resident"]["fulfilled"]))*int(market()._offers[c["offer_id"]]["resident_terms"]["materials"].get(good,0)) if c["status"]=="ACCEPTED" else 0
func build(c: Dictionary,used: Dictionary,now: int) -> void:
	if c["status"]!="ACCEPTED" or _spans(c)["scheduled_minute"]!=now: return
	var e:=economy();var m:=market();var o:=m._offers[c["offer_id"]] as Dictionary
	if not can_book(c["client"],o,now) or not m._enabled[o["id"]] or not e._site_operating(c["provider_site"],maxi(0,now-1)): c["status"]="WAITING";c["reason"]="RESIDENT_OR_PROVIDER_UNAVAILABLE_RESCHEDULE_REQUIRED";return
	var t:=o["resident_terms"] as Dictionary
	var q:=mini(int(_spans(c)["quantity"]),m._hours_available(c,used)/int(t["hours_per_unit"]))
	q=mini(q,int(o["hours_per_day"])/int(t["hours_per_unit"]))
	for good: String in t["materials"]: q=mini(q,e.capital_free_goods(c["provider_site"],good)/int(t["materials"][good]))
	if q<1: c["status"]="WAITING";c["reason"]="WAITING_REAL_SERVICE_MATERIALS_OR_WORK_RESCHEDULE_REQUIRED";return
	var rows: Array[Dictionary]=[];var materials: Dictionary={}
	for good: String in t["materials"]:
		materials[good]=q*int(t["materials"][good])
		if int(e._physical_totals[c["provider_site"]]["used"][good])>FormalLedgerState.MAX_AMOUNT-int(materials[good]): c["status"]="WAITING";c["reason"]="SERVICE_MATERIAL_BOUNDS";return
		rows.append_array(e._lots.selection("SITE|"+c["provider_site"],good,materials[good]))
	if not rows.is_empty() and not e._lots.ready(rows): c["status"]="WAITING";c["reason"]="SERVICE_SOURCE_CHANGED";return
	if e._costs.enabled: e._costs.service_inputs(c["id"],rows,true)
	if not materials.is_empty():
		var taken: bool=e.capital_take_goods(c["provider_site"],materials)
		assert(taken)
	var before: int=c["work"].size()
	var worked: int=m._work(c,q*int(t["hours_per_unit"]),"RESIDENT",used)
	assert(worked==q*int(t["hours_per_unit"]))
	var receipt:={"id":"service_receipt:"+str(_next_receipt),"sequence":_next_receipt,"contract_id":c["id"],"customer":c["client"],"kind":c["kind"],"minute":now,"quantity":q,"member_start":int(_spans(c)["member_start"]),"materials":rows.duplicate(true),"work_from":before,"work_count":c["work"].size()-before,"need_id":t["need_id"],"service_units":q*int(t["units_per_service"]),"window_start":now,"window_end":now+1440,"target_satisfied":0}
	if c["kind"]=="HAIRCUT":
		var w:=window(c["client"],t["need_id"],now)
		receipt["window_start"]=w.x;receipt["window_end"]=w.y
		receipt["target_satisfied"]=_new_coverage(receipt)
	_index_receipt(receipt);_next_receipt+=1
	c["resident"]["receipts"].append(receipt);c["resident"]["fulfilled"]+=q
	c["material_sources"].append_array(rows)
	if not rows.is_empty() and c["material_minute"]<0: c["material_minute"]=now
	if c["started_minute"]<0: c["started_minute"]=_spans(c)["minute"]
	c["last_boundary"]=now;c["earned"]+=q*int(o["price"])
	c["status"]="COMPLETED" if c["resident"]["fulfilled"]==c["quantity"] else "WAITING"
	c["reason"]="" if c["status"]=="COMPLETED" else "PARTIAL_SERVICE_REMAINDER_REQUIRES_RESCHEDULE"
func _new_coverage(r: Dictionary) -> int:
	var covered: Array=_target_spans.get(_key(r["customer"],r["need_id"],r["window_start"]),[])
	var begin:=int(r["member_start"]);var end:=begin+int(r["quantity"]);var already:=0
	# Stored coverage is a disjoint union, not one entry per inhabitant.
	for s: Vector2i in covered: already+=maxi(0,mini(end,s.y)-maxi(begin,s.x))
	return end-begin-already
func _index_receipt(r: Dictionary) -> void:
	if r["kind"]=="DINING":
		if not _food_days.has(r["customer"]): _food_days[r["customer"]]={}
		var date:=int(r["minute"])/1440
		_food_days[r["customer"]][date]=int(_food_days[r["customer"]].get(date,0))+int(r["service_units"])
	else:
		var key:=_key(r["customer"],r["need_id"],r["window_start"])
		var spans: Array[Vector2i]=[];spans.assign(_target_spans.get(key,[]));spans.append(Vector2i(r["member_start"],int(r["member_start"])+int(r["quantity"])))
		spans.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.x<b.x)
		var merged: Array[Vector2i]=[]
		for span: Vector2i in spans:
			if not merged.is_empty() and merged.back().y>=span.x: merged[merged.size()-1].y=maxi(merged.back().y,span.y)
			else: merged.append(span)
		_target_spans[key]=merged
func food_units(actor: String,date: int) -> int: return int(_food_days.get(actor,{}).get(date,0))
func food_total(actor: String,through: int) -> int:
	var total:=0
	for date: int in _food_days.get(actor,{}):
		if date<=through: total+=mini(food_units(actor,date),economy()._need_on_day(actor,"food",date))
	return total
func planning_cover(actor: String) -> int:
	var amount:=food_units(actor,economy().day)
	for id: String in market()._active:
		var c:=market().contracts[id] as Dictionary
		if c["kind"]=="DINING" and c["client"]==actor and c["status"]=="ACCEPTED": amount+=int(_spans(c)["quantity"])
	return amount
func need_view(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var now: int=economy()._world.game_clock.total_minutes()
	for t: Dictionary in economy().config.get("service_market",{}).get("resident_targets",[]):
		if t["customer"]!=actor: continue
		var w:=window(actor,t["need_id"],now);var satisfied:=0
		for span: Vector2i in _target_spans.get(_key(actor,t["need_id"],w.x),[]): satisfied+=span.y-span.x
		var required:=int(economy()._actors[actor]["members"])
		result.append({"need_id":t["need_id"],"required_people":required,"satisfied_people":satisfied,"unmet_people":required-satisfied,"window_start":w.x,"window_end":w.y,"basis":"AGGREGATE_MEMBER_SHARES_NOT_INDIVIDUAL_WELFARE"})
	return result
func npc_decisions() -> void:
	var e:=economy();var m:=market();var now: int=e._world.game_clock.total_minutes()
	for p: Dictionary in e.config.get("service_market",{}).get("resident_policies",[]):
		var actor:=str(p["customer"])
		if not _customer(actor,now): continue
		for id: String in m._active.keys():
			var c:=m.contracts[id] as Dictionary
			if c["client"]==actor and c["kind"] in KINDS and c["status"]=="WAITING": e._accept(actor,e._auto_command(actor,"reschedule_service",{"service_id":id},id),true)
		var size:=int(p["budget_window_days"])*1440;var start:=now/size*size;var spent:=0
		for id: String in m.recent_contracts(actor,start):
			var c:=m.contracts[id] as Dictionary
			if c["kind"] in KINDS and c["accepted_minute"]>=start: spent+=int(c["total"])-int(c["released"])
		for id: String in p["offer_ids"]:
			if not m.known(actor,id,now): continue
			var o:=m._offers[id] as Dictionary
			var pending:=false
			for active: String in m._active:
				var open:=m.contracts[active] as Dictionary
				if open["client"]==actor and open["offer_id"]==id and open["status"] in ["ACCEPTED","WAITING"]: pending=true;break
			if pending: continue
			var space:=free_members(actor,now+1440,o["resident_terms"]["need_id"] if o["kind"]=="HAIRCUT" else "")
			var q:=mini(space.y,int(p["quantity_limit"]))
			if o["kind"]=="DINING":
				var food:=e._household_position(actor,true).get("food",{}) as Dictionary
				q=mini(q,maxi(0,int(food.get("uncovered",0))))
			else:
				for n: Dictionary in need_view(actor):
					if n["need_id"]==o["resident_terms"]["need_id"]: q=mini(q,int(n["unmet_people"]))
			q=mini(q,maxi(0,int(p["budget_limit"])-spent)/int(o["price"]))
			if q<1: continue
			var r: Dictionary=e._accept(actor,e._auto_command(actor,"request_service",{"customer":actor,"offer_id":id,"quantity":q,"max_amount":q*int(o["price"])},id),true)
			if r.get("accepted",false): spent+=int(r["locked_amount"])
func personal_view(actor: String,quantity: int=1) -> Dictionary:
	var e:=economy();var m:=market();var result:={"enabled":false,"offers":[],"contracts":[],"targets":need_view(actor),"actions":[],"time_basis":"DAILY_ON_SITE_NO_OVERLAPPING_WORK_SHARE"}
	if not e._actors.has(actor): return result
	for o: Dictionary in m.quotes(actor):
		if o["kind"] not in KINDS: continue
		result["enabled"]=true
		var public_offer: Dictionary={}
		for key: String in ["id","kind","denomination","price","place_id","valid_from","valid_until","notice_minute","available_capacity","enabled","valid"]: public_offer[key]=o[key]
		result["offers"].append(public_offer)
		var p:={"customer":actor,"offer_id":o["id"],"quantity":quantity,"max_amount":quantity*int(o["price"])}
		var test:=accept(actor,p,"",true)
		result["actions"].append({"kind":"request_service","payload":p,"label":("现场用餐" if o["kind"]=="DINING" else "理发预约")+" ×"+str(quantity)+" · "+str(o["price"])+" "+str(o["denomination"]),"can_execute":test["accepted"],"reason":test["reason"]})
	for id: String in m._by_firm.get(actor,[]).slice(-8):
		var c:=m.contracts[id] as Dictionary
		if c["kind"] not in KINDS: continue
		var row:=c.duplicate(true);row.erase("supply_permission");row.erase("permission");row.erase("work");row.erase("material_sources")
		for receipt: Dictionary in row["resident"]["receipts"]:
			receipt.erase("materials");receipt.erase("work_from");receipt.erase("work_count")
		row["denomination"]=m._offers[c["offer_id"]]["denomination"];result["contracts"].append(row)
		if c["status"]=="WAITING": result["actions"].append({"kind":"reschedule_service","payload":{"service_id":id},"label":"重新预约未履行部分","can_execute":e._world.game_clock.total_minutes()%1440==0,"reason":c["reason"]})
		if c["resident"]["fulfilled"]==0 and c["status"] not in ["COMPLETED","CANCELLED"]: result["actions"].append({"kind":"cancel_service","payload":{"service_id":id},"label":"取消未开始服务","can_execute":true,"reason":"RELEASE_UNFULFILLED_COMMITMENT_ONLY"})
	return result
func reset_restore() -> void:
	error="";_next_receipt=1;_food_days.clear();_target_spans.clear();_restore_receipts.clear()
func fail(reason: String) -> bool: error=reason;return false

func _command(saved: Dictionary,id: String,actor: String,kind: String,minute: int) -> bool:
	var cmd: Dictionary=saved["commands"].get(id,{})
	return cmd.get("result",{}).get("accepted",false) and cmd.get("envelope",{}).get("actor")==actor and cmd["envelope"]["command"].get("kind")==kind and cmd["envelope"]["command"].get("minute")==minute
func restore_contract(c: Dictionary,saved: Dictionary,all_work: Dictionary,material_use: Dictionary) -> bool:
	var e:=economy();var m:=market();var now: int=e._world.game_clock.total_minutes()
	if not c["action_id"] is String or not saved.get("actors") is Dictionary or not saved["actors"].get(c["client"]) is Dictionary or not FormalLedgerState.valid_amount(saved["actors"][c["client"]].get("members")): return fail("Invalid resident identity reference")
	var o:=m._offers[c["offer_id"]] as Dictionary;var f:=m._facilities[o["facility_id"]] as Dictionary
	if o["kind"]!=c["kind"] or c["facility_id"]!=f["id"] or c["provider"]!=f["provider"] or c["provider_site"]!=f["site_id"] or not saved["actors"].has(c["client"]) or c["actor"]!=c["client"] or c["payer"]!=c["client"] or not market().known(c["client"],o["id"],c["accepted_minute"]): return fail("Invalid resident service identity or knowledge")
	if not c.get("resident") is Dictionary or not FormalLedgerState.exact_fields(c["resident"],["fulfilled","bookings","receipts"]) or not c["resident"]["bookings"] is Array or c["resident"]["bookings"].is_empty() or not c["resident"]["receipts"] is Array: return fail("Invalid resident booking/fulfilment state")
	for key: String in ["quantity","accepted_minute","total","earned","paid","released","periods_count","charge_numerator"]:
		if not FormalLedgerState.valid_amount(c[key]): return fail("Invalid resident service quantity/money")
	for key: String in ["started_minute","end_minute","last_boundary","repair_result_minute","material_minute"]:
		if not c[key] is int or c[key]<-1 or c[key]>now+1440: return fail("Invalid resident service boundary")
	var members:=int(saved["actors"][c["client"]]["members"])
	if c["quantity"]<1 or c["quantity"]>members or c["total"]!=int(c["quantity"])*int(o["price"]) or c["accepted_minute"]%1440!=0 or c["accepted_minute"]>now or c["accepted_minute"]<o["valid_from"] or c["accepted_minute"]>=o["valid_until"] or c["accepted_minute"]<o["notice_minute"] or not e.subject_active_at(c["client"],c["accepted_minute"]): return fail("Resident contract exceeds identity, quote or member scope")
	if c["status"] not in ["ACCEPTED","WAITING","COMPLETED","CANCELLED"] or not c["paused"] is bool or c["paused"]!=false or not c["reason"] is String or c["periods_count"]!=0 or c["charge_numerator"]!=0 or c["repair_result_minute"]!=-1 or c["source_site"]!="" or c["good"]!="" or c["asset_id"]!="": return fail("Resident contract has incompatible state")
	for key: String in ["work","material_sources","custody_events","periods","payments"]:
		if not c[key] is Array: return fail("Invalid resident service facts")
	if not c["periods"].is_empty(): return fail("Resident service contains warehouse periods")
	var proof:={"basis":"OWN_RESIDENT_IDENTITY_AND_LEDGER_ACCOUNT","actor":c["client"],"account_id":e._account(c["client"],o["denomination"])}
	if not c["supply_permission"] is Dictionary or c["permission"]!=proof or e._world.ledger_state.account(proof["account_id"]).get("owner_id")!=c["client"] or not m._proof_valid(c["supply_permission"],str(c["supply_permission"].get("actor","")),c["provider"],"supply",c["total"],c["accepted_minute"],o["denomination"],c["client"],e._place(c["provider_site"]),"service:"+str(c["kind"]).to_lower()): return fail("Resident or provider authority invalid")
	var command:=saved["commands"].get(c["action_id"],{}) as Dictionary
	var payload: Dictionary=command.get("envelope",{}).get("command",{}).get("payload",{})
	if not _command(saved,c["action_id"],c["client"],"request_service",c["accepted_minute"]) or not FormalLedgerState.exact_fields(payload,["customer","offer_id","quantity","max_amount"]) or payload["customer"]!=c["client"] or payload["offer_id"]!=c["offer_id"] or payload["quantity"]!=c["quantity"] or not FormalLedgerState.valid_amount(payload["max_amount"]) or payload["max_amount"]<c["total"] or command["result"].get("service_id")!=c["id"]: return fail("Resident contract lacks accepted source action")
	var prior:=-1;var bookings: Dictionary={}
	for b: Variant in c["resident"]["bookings"]:
		if not b is Dictionary or not FormalLedgerState.exact_fields(b,["action_id","minute","scheduled_minute","member_start","quantity"]) or not b["action_id"] is String: return fail("Invalid resident booking")
		for key: String in ["minute","scheduled_minute","member_start","quantity"]:
			if not FormalLedgerState.valid_amount(b[key]): return fail("Invalid resident span or time")
		if b["minute"]<=prior or b["minute"]%1440!=0 or b["scheduled_minute"]!=int(b["minute"])+1440 or b["minute"]>now or b["quantity"]<1 or int(b["member_start"])+int(b["quantity"])>members: return fail("Resident booking exceeds member/time scope")
		if prior<0:
			if b["minute"]!=c["accepted_minute"] or b["action_id"]!=c["action_id"] or b["quantity"]!=c["quantity"]: return fail("Initial booking differs from contract")
		elif not _command(saved,b["action_id"],c["client"],"reschedule_service",b["minute"]) or saved["commands"][b["action_id"]]["envelope"]["command"]["payload"]!={"service_id":c["id"]}: return fail("Reschedule lacks owner action")
		bookings[b["scheduled_minute"]]=b;prior=b["minute"]
	if c["end_minute"]!=int(prior)+1440: return fail("Service end differs from latest booking")
	var fulfilled:=0;var work_cursor:=0;var last:=-1;var materials: Array[Dictionary]=[]
	for r: Variant in c["resident"]["receipts"]:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","sequence","contract_id","customer","kind","minute","quantity","member_start","materials","work_from","work_count","need_id","service_units","window_start","window_end","target_satisfied"]): return fail("Invalid resident receipt")
		for key: String in ["sequence","minute","quantity","member_start","work_from","work_count","service_units","window_start","window_end","target_satisfied"]:
			if not FormalLedgerState.valid_amount(r[key]): return fail("Invalid resident receipt amount/time")
		if r["sequence"]<1 or r["id"]!="service_receipt:"+str(r["sequence"]) or r["contract_id"]!=c["id"] or r["customer"]!=c["client"] or r["kind"]!=c["kind"] or not bookings.has(r["minute"]) or r["minute"]>now or r["minute"]<=last or r["quantity"]<1 or r["quantity"]>bookings[r["minute"]]["quantity"] or r["member_start"]!=bookings[r["minute"]]["member_start"] or r["service_units"]!=r["quantity"] or r["need_id"]!=o["resident_terms"]["need_id"] or not r["materials"] is Array or r["work_from"]!=work_cursor: return fail("Receipt exceeds actual booking")
		var totals: Dictionary={};var physical:=saved["stock_lots"]["portions"] as Dictionary
		for row: Variant in r["materials"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row,["portion_id","source_id","quantity"]) or not physical.has(row.get("portion_id")) or not FormalLedgerState.valid_amount(row["quantity"]) or row["quantity"]<1: return fail("Meal lacks real material source")
			var item:=physical[row["portion_id"]] as Dictionary
			if item["source_id"]!=row["source_id"] or item["owner"]!=c["provider"] or item["location"]!="SITE|"+str(c["provider_site"]) or item["opened_minute"]>r["minute"]: return fail("Service material owner/site/time invalid")
			material_use[item["id"]]=int(material_use.get(item["id"],0))+int(row["quantity"])
			if material_use[item["id"]]>item["consumed"]: return fail("Service reuses consumed material")
			totals[item["good"]]=int(totals.get(item["good"],0))+int(row["quantity"])
		var required: Dictionary={}
		for good: String in o["resident_terms"]["materials"]: required[good]=int(o["resident_terms"]["materials"][good])*int(r["quantity"])
		if totals!=required or int(r["work_from"])+int(r["work_count"])>c["work"].size(): return fail("Receipt material/labor scope differs")
		var hours:=0
		for i: int in range(r["work_from"],int(r["work_from"])+int(r["work_count"])):
			var row: Variant=c["work"][i]
			if not row is Dictionary or not FormalLedgerState.exact_fields(row,["id","hours","minute","purpose"]) or not saved["work_records"].has(row.get("id")) or not FormalLedgerState.valid_amount(row["hours"]) or row["hours"]<1 or row["minute"]!=r["minute"] or row["purpose"]!="RESIDENT": return fail("Invalid resident service work")
			var work:=saved["work_records"][row["id"]] as Dictionary
			if work["job"] not in o["job_ids"] or int(work["day"])*1440!=row["minute"]: return fail("Service lacks qualified real work")
			all_work[row["id"]]=int(all_work.get(row["id"],0))+int(row["hours"])
			if all_work[row["id"]]>work["hours"]: return fail("Service reuses existing work")
			hours+=int(row["hours"])
			m._labor[c["provider_site"]]=int(m._labor.get(c["provider_site"],0))+int(row["hours"])
			if not m._labor_days.has(c["provider_site"]): m._labor_days[c["provider_site"]]={}
			m._labor_days[c["provider_site"]][work["day"]]=int(m._labor_days[c["provider_site"]].get(work["day"],0))+int(row["hours"])
		if hours!=int(r["quantity"])*int(o["resident_terms"]["hours_per_unit"]) or hours>o["hours_per_day"]: return fail("Service revenue lacks actual work")
		work_cursor+=int(r["work_count"]);fulfilled+=int(r["quantity"]);last=r["minute"];materials.append_array(r["materials"])
		_restore_receipts.append(r)
	if not FormalLedgerState.valid_amount(c["resident"]["fulfilled"]) or c["resident"]["fulfilled"]!=fulfilled or fulfilled>c["quantity"] or work_cursor!=c["work"].size() or materials!=c["material_sources"] or c["earned"]!=fulfilled*int(o["price"]) or c["last_boundary"]!=last or c["material_minute"]!=(-1 if materials.is_empty() else c["resident"]["receipts"][0]["minute"]) or c["started_minute"]!=(-1 if fulfilled==0 else int(c["resident"]["receipts"][0]["minute"])-1440): return fail("Resident totals differ from actual receipts")
	if (c["status"]=="COMPLETED")!=(fulfilled==c["quantity"]) or (c["status"]=="ACCEPTED" and c["end_minute"]<=now): return fail("Service stage differs from actual progress")
	for b: Dictionary in c["resident"]["bookings"]:
		var before:=0
		for r: Dictionary in c["resident"]["receipts"]:
			if r["minute"]<=b["minute"]: before+=int(r["quantity"])
		if b["quantity"]!=int(c["quantity"])-before: return fail("Reschedule duplicates fulfilled shares")
	if c["status"]=="CANCELLED":
		if fulfilled!=0 or c["custody_events"].size()!=1: return fail("Cancellation erases incurred service")
		var event: Variant=c["custody_events"][0]
		if not event is Dictionary or not FormalLedgerState.exact_fields(event,["id","kind","minute","quantity","portions"]) or event["kind"]!="CANCEL" or event["quantity"]!=c["quantity"] or not FormalLedgerState.valid_amount(event["minute"]) or event["minute"]<c["accepted_minute"] or event["minute"]>now or event["portions"]!=[] or not _command(saved,event["id"],c["client"],"cancel_service",event["minute"]) or saved["commands"][event["id"]]["envelope"]["command"]["payload"]!={"service_id":c["id"]}: return fail("Cancellation lacks owner action")
	elif not c["custody_events"].is_empty(): return fail("Resident service creates physical customer inventory")
	return m.restore_payments(c,now) or fail(m.error)
func finish_restore(_saved: Dictionary) -> bool:
	_restore_receipts.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["sequence"]<b["sequence"])
	for r: Dictionary in _restore_receipts:
		if r["sequence"]!=_next_receipt: return fail("Service receipt sequence duplicated or missing")
		var w:=Vector2i(r["minute"],int(r["minute"])+1440) if r["kind"]=="DINING" else window(r["customer"],r["need_id"],r["minute"])
		if w.x<0 or r["window_start"]!=w.x or r["window_end"]!=w.y or r["target_satisfied"]!=(0 if r["kind"]=="DINING" else _new_coverage(r)): return fail("Resident target duplicated or wrong window")
		_index_receipt(r);_next_receipt+=1
		for party: String in [r["customer"],market().contracts[r["contract_id"]]["provider"]]:
			if not market()._days.has(party): market()._days[party]={}
			var date:=int(r["minute"])/1440
			if not market()._days[party].has(date): market()._days[party][date]={}
			market()._days[party][date][r["contract_id"]]=true
	# History is checked once at candidate recovery; live scheduling uses active rows.
	for c: Dictionary in market().contracts.values():
		if c["kind"] not in KINDS: continue
		var date:=int(c["accepted_minute"])/1440
		if not market()._days[c["client"]].has(date): market()._days[c["client"]][date]={}
		market()._days[c["client"]][date][c["id"]]=true
		for b: Dictionary in c["resident"]["bookings"]:
			var capacity:=0;var spans: Array[Vector2i]=[]
			for other: Dictionary in market().contracts.values():
				if other["kind"] not in KINDS: continue
				var cancelled:=false
				for event: Dictionary in other["custody_events"]:
					if event["minute"]<=b["minute"]: cancelled=true
				if cancelled: continue
				for ob: Dictionary in other["resident"]["bookings"]:
					if ob["minute"]>b["minute"] or ob["scheduled_minute"]!=b["scheduled_minute"]: continue
					if other["facility_id"]==c["facility_id"]: capacity+=int(ob["quantity"])
					if other["client"]==c["client"]: spans.append(Vector2i(ob["member_start"],int(ob["member_start"])+int(ob["quantity"])))
			if capacity>market()._facilities[c["facility_id"]]["capacity"]: return fail("Resident service facility oversold")
			spans.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.x<b.x)
			var end:=-1
			for span: Vector2i in spans:
				if span.x<end: return fail("Resident member share booked twice")
				end=span.y
	return true

func validate_presence() -> bool:
	var e:=economy()
	for c: Dictionary in market().contracts.values():
		if c["kind"] not in KINDS: continue
		var place: String=e._place(c["provider_site"])
		for b: Dictionary in c["resident"]["bookings"]:
			if not _present_at(c["client"],place,b["minute"]): return fail("Resident booking lacks actual presence")
		for r: Dictionary in c["resident"]["receipts"]:
			if not _present_at(c["client"],place,r["minute"]): return fail("Resident receipt lacks actual presence")
			for work: Dictionary in e._work_records.values():
				if work["actor"]!=c["client"] or int(work["day"])*1440!=r["minute"]: continue
				if e._declared_named(c["client"]): return fail("Person worked and received on-site service in same booked interval")
				var span:=_historical_worker_span(c["client"],work["job"],work["action_id"],work)
				if span.x<0 or (span.x<int(r["member_start"])+int(r["quantity"]) and int(r["member_start"])<span.y): return fail("Cohort service reuses working member shares")
	return true
func _historical_worker_span(actor: String,job: String,work_id: String,work: Dictionary) -> Vector2i:
	var e:=economy();var work_command:=e._commands[work_id]["envelope"]["command"] as Dictionary
	var time: int=work_command["minute"]
	if work.has("employment_action_id"):
		var c:=e._labor_market.work_contract(work,work_command,e._commands) as Dictionary
		return Vector2i(c.get("labor_start",-1),int(c.get("labor_start",-1))+int(c.get("workers",0)))
	var best:=-1;var result:=Vector2i(-1,-1)
	for cmd: Dictionary in e._commands.values():
		var command:=cmd["envelope"]["command"] as Dictionary
		if cmd["envelope"]["actor"]!=actor or not cmd["result"].get("accepted",false) or command["kind"]!="apply" or command["payload"].get("job_id")!=job or command["minute"]>time or command["minute"]<best: continue
		best=command["minute"];result=Vector2i(cmd["result"].get("labor_start",0),int(cmd["result"].get("labor_start",0))+int(cmd["result"].get("workers",0)))
	return result
func _present_at(actor: String,place: String,minute: int) -> bool:
	var e:=economy()
	if not e._declared_named(actor): return e._place(actor)==place
	var trips: Array[Dictionary]=[]
	if e._world.person_travel!=null:
		for action: Dictionary in e._world.person_travel._actions.values():
			var original:=action["result"]["journey"] as Dictionary
			if original["person_id"]!=actor: continue
			var trip: Dictionary=action.get("completion",e._world.person_travel._journeys.get(actor,original))
			if trip["id"]!=original["id"]: trip=original
			trips.append(trip)
	trips.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["departed_minute"]<b["departed_minute"])
	var current: String=e._spec["actors"][actor]["place_id"]
	for trip: Dictionary in trips:
		if trip["departed_minute"]>=minute: break
		if trip["arrived_minute"]<0 or trip["arrived_minute"]>minute: return false
		current=trip["destination"]
	return current==place
