class_name EconomyCommercialInformation
extends RefCounted
## Publication facts only. Delivery and knowledge use the kernel's original
## messages/receipts; paid contracts, labor and cash stay in ServiceMarket.
const FORMAT := "economy_commercial_information_v1"
var publications: Dictionary = {}
var error: String = ""
var _ref: WeakRef
var _channels: Dictionary = {}
var _boards: Dictionary = {}
var _expiry: Dictionary = {}
var _sent: Dictionary = {}
var _service_known: Dictionary = {}
var _received: Dictionary = {}
var _days: Dictionary = {}
var _limits: Dictionary = {}
var _last: Dictionary = {}
var _policy_enabled: Dictionary = {}
func economy() -> RefCounted: return _ref.get_ref()
func bind(e: RefCounted) -> void:
	_ref=weakref(e)
	for c: Dictionary in e.config.get("commercial_information",{}).get("channels",[]): _channels[c["id"]]=c
	for p: Dictionary in policies(): _policy_enabled[p["id"]]=true
func policies() -> Array: return economy().config.get("commercial_information",{}).get("npc_policies",[])
static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	if not settings.has("commercial_information"): return true
	var v: Variant=settings["commercial_information"]
	if not v is Dictionary or not FormalLedgerState.exact_fields(v,["channels","npc_policies","basis"]) or v["basis"]!="EXPLICIT_DEVELOPMENT_COMMERCIAL_INFORMATION" or not v["channels"] is Array or v["channels"].size()>16 or not v["npc_policies"] is Array: return false
	var channels: Dictionary={};var offers: Dictionary={};var facilities: Dictionary={}
	for f: Dictionary in settings.get("service_market",{}).get("facilities",[]): facilities[f["id"]]=f
	for o: Dictionary in settings.get("service_market",{}).get("offers",[]): offers[o["id"]]=o
	for c: Variant in v["channels"]:
		if not c is Dictionary or not FormalLedgerState.exact_fields(c,["id","kind","place_id","service_offer","recipients","recipient_limit","delay_days","cooldown_days","window_days","window_limit","basis","audience_basis"]): return false
		if not c["id"] is String or c["id"].is_empty() or channels.has(c["id"]) or c["kind"] not in ["SITE_BOARD","PAID_LOCAL_PUBLICATION"] or c["basis"]!="EXPLICIT_DEVELOPMENT_PUBLICATION_CHANNEL" or c["audience_basis"]!="LOCAL_NAMED_PERSON_OR_POOLED_PURCHASING_DESK_NOT_MEMBER_KNOWLEDGE" or not EconomySliceConfig._place(c["place_id"]) or not c["recipients"] is Array or c["recipients"].size()>16: return false
		for key: String in ["recipient_limit","delay_days","cooldown_days","window_days","window_limit"]:
			if not FormalLedgerState.valid_amount(c[key]) or c[key]<1 or c[key]>30: return false
		if c["recipient_limit"]>c["recipients"].size(): return false
		var seen: Dictionary={}
		for actor: Variant in c["recipients"]:
			if not actor is String or seen.has(actor) or (not spec["actors"].has(actor) and not spec["sites"].has(actor) and actor!="HOST_SELECTED_PLAYER"): return false
			seen[actor]=true
		if c["kind"]=="SITE_BOARD":
			if c["service_offer"]!="": return false
		elif not offers.has(c["service_offer"]) or offers[c["service_offer"]]["kind"]!="ANNOUNCEMENT" or offers[c["service_offer"]]["announcement_terms"]["channel_id"]!=c["id"]: return false
		channels[c["id"]]=c
	var ids: Dictionary={}
	for p: Variant in v["npc_policies"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["id","firm","site_id","kind","item","channel_id","valid_days","minimum_stock","sales_window","sales_at_most","max_fee","cash_floor","basis"]) or not p.get("id") is String or p["id"].is_empty() or ids.has(p.get("id")) or not spec["firms"].has(p.get("firm")) or not spec["sites"].has(p.get("site_id")) or spec["sites"][p["site_id"]]["firm_id"]!=p["firm"] or not channels.has(p.get("channel_id")) or p["kind"] not in ["GOODS","SERVICE"] or p["basis"]!="EXPLICIT_DEVELOPMENT_OWN_SALES_PUBLICITY_POLICY": return false
		if (p["kind"]=="GOODS" and not spec["sites"][p["site_id"]]["prices"].has(p["item"])) or (p["kind"]=="SERVICE" and not offers.has(p["item"])): return false
		if p["kind"]=="SERVICE" and (offers[p["item"]]["kind"]=="ANNOUNCEMENT" or not facilities.has(offers[p["item"]]["facility_id"]) or facilities[offers[p["item"]]["facility_id"]]["site_id"]!=p["site_id"]): return false
		for key: String in ["valid_days","minimum_stock","sales_window","sales_at_most","max_fee","cash_floor"]:
			if not FormalLedgerState.valid_amount(p[key]): return false
		if p["valid_days"]<1 or p["valid_days"]>30 or p["sales_window"]<1 or p["sales_window"]>30: return false
		ids[p["id"]]=true
	return true
func _publication_fields(p: Dictionary) -> bool:
	return FormalLedgerState.exact_fields(p,["site_id","kind","item","channel_id","valid_days"]) and p["site_id"] is String and p["item"] is String and p["kind"] in ["GOODS","SERVICE"] and _channels.has(p["channel_id"]) and FormalLedgerState.valid_amount(p["valid_days"]) and p["valid_days"]>=1 and p["valid_days"]<=30
func _staff(site: String) -> Array[String]:
	var e:=economy();var ids: Array[String]=[]
	for id: String in e._capital_work_ids:
		var work: Dictionary=e._work_records[id]
		if work["day"]==e.day and e._job(work["job"])["site_id"]==site: ids.append(id)
	return ids
func _rate_ready(firm: String, channel: Dictionary, date: int) -> bool:
	var key:=firm+"|"+str(channel["id"])
	if date-int(_last.get(key,-1000))<int(channel["cooldown_days"]): return false
	var start:=date/int(channel["window_days"])*int(channel["window_days"])
	var total:=0
	for d: int in range(start,date+1): total+=int(_limits.get(key,{}).get(d,0))
	return total<int(channel["window_limit"])
func prepare(actor: String, firm: String, p: Dictionary, action: String) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if not _publication_fields(p) or not e._spec["sites"].has(p["site_id"]) or e._owner(p["site_id"])!=firm or not e._manager(actor,firm): return _reject("INVALID_PUBLICATION_OR_NOT_CURRENT_MANAGER")
	var channel:=_channels[p["channel_id"]] as Dictionary;var site: String=p["site_id"]
	if not e._site_accepting(site) or e._firm_winding_down(firm) or e._place(site)!=channel["place_id"]: return _reject("PUBLICATION_REQUIRES_LEGAL_LOCAL_OPERATING_SITE")
	if not _rate_ready(firm,channel,e.day) or publications.size()>=4096: return _reject("PUBLICITY_COOLDOWN_OR_CUMULATIVE_ISSUE_LIMIT")
	var staff:=_staff(site)
	if channel["kind"]=="SITE_BOARD" and (staff.is_empty() or (e._retail.has_site(site) and e._retail.allocated_hours(site,e.day)<=0)): return _reject("SITE_BOARD_REQUIRES_ACTUAL_STAFFED_BUSINESS")
	if e._retail.has_site(site) and (e._retail.allocated_hours(site,e.day)<1 or e._retail.limit(site)<1): return _reject("NO_CURRENT_STAFFED_RETAIL_PUBLICATION_CAPABILITY")
	var quote: Dictionary={};var until:=now+int(p["valid_days"])*1440
	if p["kind"]=="GOODS":
		if "sales" not in e._spec["sites"][site]["roles"] or not e._spec["sites"][site]["prices"].has(p["item"]): return _reject("NO_LEGAL_GOODS_QUOTE_AT_SITE")
		var quantity:=mini(10,maxi(0,int(e._stocks[site][p["item"]])-e._committed(site,p["item"])))
		if quantity<1: return _reject("NO_ACTUAL_UNCOMMITTED_GOODS_TO_ANNOUNCE")
		quote={"id":"publication_quote:"+action,"kind":"GOODS","price":e._price(site,p["item"]),"denomination":e._sale_currency(firm),"quantity":quantity,"offer_id":"","sources":e._lots.selection("SITE|"+site,p["item"],quantity)}
	else:
		var m: RefCounted=e._service_market;var o: Dictionary=m._offers.get(p["item"],{})
		if o.is_empty() or o["kind"]=="ANNOUNCEMENT" or m._facilities[o["facility_id"]]["site_id"]!=site or not m._enabled[o["id"]] or now<o["valid_from"] or now>=o["valid_until"] or m.available(o["facility_id"])<1: return _reject("NO_CURRENT_LOCAL_SERVICE_CAPABILITY")
		var supply: Dictionary=m._permission(actor,firm,"supply",o["denomination"],0,o["id"],e._place(site))
		if not supply["ok"]: return _reject(supply["reason"])
		until=mini(until,int(o["valid_until"]))
		quote={"id":"publication_quote:"+action,"kind":"SERVICE","price":o["price"],"denomination":o["denomination"],"quantity":m.available(o["facility_id"]),"offer_id":o["id"],"sources":[]}
	var a:={"id":"announcement:"+action,"action_id":action,"actor":actor,"firm":firm,"site_id":site,"kind":p["kind"],"item":p["item"],"channel_id":p["channel_id"],"published_minute":now,"valid_days":p["valid_days"],"valid_until":until,"released_minute":-1,"service_id":"","quote":quote,"staff_refs":staff,"withdrawn_minute":-1,"withdrawal_action":""}
	return {"accepted":true,"reason":"PUBLICATION_PREPARED","publication":a}
func _index(a: Dictionary) -> void:
	var date:=int(a["published_minute"])/1440;var key:=str(a["firm"])+"|"+str(a["channel_id"])
	_last[key]=maxi(int(_last.get(key,-1000)),date)
	if not _limits.has(key): _limits[key]={}
	_limits[key][date]=int(_limits[key].get(date,0))+1
	if not _days.has(a["firm"]): _days[a["firm"]]={}
	if not _days[a["firm"]].has(date): _days[a["firm"]][date]=[]
	_days[a["firm"]][date].append(a["id"])
func adopt(a: Dictionary, service: String="") -> void:
	a["service_id"]=service;publications[a["id"]]=a;_index(a)
	if service.is_empty(): release(a,economy()._world.game_clock.total_minutes())
func request(actor: String, kind: String, p: Dictionary, action: String) -> Dictionary:
	var e:=economy()
	if kind=="set_publicity_policy":
		if not FormalLedgerState.exact_fields(p,["policy_id","enabled"]) or not p["enabled"] is bool: return _reject("INVALID_PUBLICITY_POLICY_CONTROL")
		for policy: Dictionary in policies():
			if policy["id"]==p["policy_id"] and e._manager(actor,policy["firm"]): _policy_enabled[policy["id"]]=p["enabled"];return {"accepted":true,"reason":"FUTURE_PUBLICITY_POLICY_CHANGED"}
		return _reject("NOT_PUBLICITY_POLICY_MANAGER")
	if kind=="withdraw_announcement":
		if not FormalLedgerState.exact_fields(p,["announcement_id"]) or not publications.has(p["announcement_id"]): return _reject("UNKNOWN_PUBLICATION")
		var a:=publications[p["announcement_id"]] as Dictionary
		if not e._manager(actor,a["firm"]) or a["withdrawn_minute"]>=0 or a["released_minute"]<0: return _reject("PUBLICATION_NOT_CURRENTLY_WITHDRAWABLE")
		a["withdrawn_minute"]=e._world.game_clock.total_minutes();a["withdrawal_action"]=action
		_boards.get(e._place(a["site_id"]),{}).erase(a["id"])
		return {"accepted":true,"reason":"FUTURE_PUBLICATION_CONTACT_STOPPED_PRIOR_MESSAGES_RETAINED"}
	if not EconomySliceConfig._fields(p,["firm","site_id","kind","item","channel_id","valid_days"],[]) or not p["firm"] is String or not e._spec["firms"].has(p["firm"]): return _reject("INVALID_SITE_NOTICE")
	var data:=p.duplicate(true);data.erase("firm")
	var result:=prepare(actor,p["firm"],data,action)
	if not result["accepted"]: return result
	if _channels[p["channel_id"]]["kind"]!="SITE_BOARD": return _reject("PAID_CHANNEL_REQUIRES_ORIGINAL_SERVICE_CONTRACT")
	adopt(result["publication"])
	var adopted: Dictionary={"accepted":true,"reason":"SITE_NOTICE_PUBLISHED_NOT_A_SALE","announcement_id":result["publication"]["id"]}
	if result.publication.kind=="GOODS":adopted["observed_goods_quote"]=result.publication.quote.duplicate(true)
	return adopted
func _eligible(actor: String, channel: Dictionary) -> bool:
	var e:=economy()
	if e._actors.has(actor): return e.subject_active_at(actor,e._world.game_clock.total_minutes()) and e._at_place(actor,channel["place_id"])
	return e._spec["sites"].has(actor) and e._place(actor)==channel["place_id"] and e._site_operating(actor)
func _queue(a: Dictionary, actor: String, now: int) -> void:
	var e:=economy();var channel:=_channels[a["channel_id"]] as Dictionary
	if actor not in channel["recipients"] or now>=a["valid_until"] or (a["withdrawn_minute"]>=0 and now>=a["withdrawn_minute"]) or not _eligible(actor,channel) or not e._site_accepting(a["site_id"]): return
	if channel["kind"]=="SITE_BOARD" and e._firm_winding_down(a["firm"]): return
	if _sent.get(a["id"],{}).has(actor) or _sent.get(a["id"],{}).size()>=int(channel["recipient_limit"]): return
	var message:={"id":"message:commercial:"+str(a["id"])+":"+actor,"actor":actor,"kind":"supplier" if a["kind"]=="GOODS" else "service_offer","candidate":str(a["firm"])+"|"+str(a["item"])+"|"+str(a["site_id"]) if a["kind"]=="GOODS" else a["item"],"observed_day":int(a["published_minute"])/1440,"delivery_day":now/1440+int(channel["delay_days"]),"source":"commercial","announcement_id":a["id"],"channel_id":a["channel_id"],"contact_minute":now,"audience_basis":channel["audience_basis"]}
	e._messages.append(message)
	if not _sent.has(a["id"]): _sent[a["id"]]={}
	_sent[a["id"]][actor]=true
func release(a: Dictionary, now: int) -> void:
	if a["released_minute"]>=0: return
	a["released_minute"]=now
	var channel:=_channels[a["channel_id"]] as Dictionary
	if channel["kind"]=="SITE_BOARD":
		if not _boards.has(channel["place_id"]): _boards[channel["place_id"]]={}
		_boards[channel["place_id"]][a["id"]]=true
		var expiry: int=(int(a["valid_until"])+1439)/1440
		if not _expiry.has(expiry): _expiry[expiry]=[]
		_expiry[expiry].append(a["id"])
	for actor: String in channel["recipients"]: _queue(a,actor,now)
func contact_local(actor: String) -> void:
	economy()._labor_market.observe_person(actor)
	var e:=economy();var place: String=e._place(actor)
	for id: String in _boards.get(place,{}).keys():
		var a:=publications[id] as Dictionary;var channel:=_channels[a["channel_id"]] as Dictionary
		if actor in channel["recipients"]: _queue(a,actor,e._world.game_clock.total_minutes())
func advance_day() -> void:
	var e:=economy()
	for date: Variant in _expiry.keys():
		if date>e.day: continue
		for id: String in _expiry[date]: _boards[_channels[publications[id]["channel_id"]]["place_id"]].erase(id)
		_expiry.erase(date)
	for place: String in _boards:
		for id: String in _boards[place].keys():
			var a:=publications[id] as Dictionary
			for actor: String in _channels[a["channel_id"]]["recipients"]: _queue(a,actor,e._world.game_clock.total_minutes())
func adopted_message(message: Dictionary) -> void:
	var actor: String=message["actor"];var candidate: String=message["candidate"]
	if not _received.has(actor): _received[actor]=[]
	_received[actor].append(message["id"])
	if message["kind"]=="service_offer":
		if not _service_known.has(actor): _service_known[actor]={}
		_service_known[actor][candidate]=mini(int(_service_known[actor].get(candidate,FormalLedgerState.MAX_AMOUNT)),int(message["delivery_day"])*1440)
func knows_service(actor: String, offer: String, minute: int) -> bool:
	if int(_service_known.get(actor,{}).get(offer,FormalLedgerState.MAX_AMOUNT))<=minute: return true
	var e:=economy()
	if e._spec["firms"].has(actor):
		for site: String in e._spec["firms"][actor]["sites"]:
			if int(_service_known.get(site,{}).get(offer,FormalLedgerState.MAX_AMOUNT))<=minute: return true
	return false

func build_publication(c: Dictionary, used: Dictionary, now: int) -> void:
	if c["status"] in ["COMPLETED","CANCELLED"]: return
	var e:=economy();var m: RefCounted=e._service_market
	var a:=publications[c["announcement_id"]] as Dictionary
	if now>=a["valid_until"]: c["reason"]="PUBLICATION_EXPIRED_BEFORE_WORK_CANCEL_UNSTARTED_CONTRACT"; return
	var current_supply: Dictionary=m._permission(e.firm_manager_at(c["provider"],now),c["provider"],"supply",m._offers[c["offer_id"]]["denomination"],c["total"],c["client"],e._place(c["provider_site"]),{},"service:announcement")
	if not current_supply["ok"]: c["reason"]="WAITING_CURRENT_PUBLICATION_SUPPLY_AUTHORITY"; return
	if not m._enabled[c["offer_id"]] or not e._site_operating(c["provider_site"]) or not e._site_operating(a["site_id"]): c["reason"]="PUBLICATION_PROVIDER_OR_SOURCE_SITE_STOPPED"; return
	var hours:=int(m._offers[c["offer_id"]]["announcement_terms"]["work_hours"])
	if m._hours_available(c,used)<hours: c["reason"]="WAITING_ACTUAL_PUBLICATION_WORK"; return
	# One bounded publication job. No audience, need or sale is fabricated here.
	if m._work(c,hours,"ANNOUNCEMENT",used)!=hours: return
	c["started_minute"]=now;c["end_minute"]=now;c["last_boundary"]=now
	c["periods"].append({"minute":now,"earned_delta":c["total"],"publication_id":a["id"]})
	c["earned"]=c["total"];c["status"]="COMPLETED";c["reason"]="LOCAL_PUBLICATION_WORK_COMPLETED_NO_GUARANTEED_SALE"
	release(a,now)

func valid_contract(c: Dictionary, p: Dictionary) -> bool:
	if not publications.has(c.get("announcement_id")): return false
	var a:=publications[c["announcement_id"]] as Dictionary
	return a["service_id"]==c["id"] and a["action_id"]==c["action_id"] and a["firm"]==c["client"] and p.get("announcement")==_payload(a) and _channels[a["channel_id"]]["service_offer"]==c["offer_id"] and c["total"]==economy()._service_market._offers[c["offer_id"]]["price"] and c["quantity"]==1 and c["periods_count"]==0 and c["asset_id"]=="" and c["source_site"]=="" and c["good"]=="" and c["material_sources"]==[] and c["material_minute"]==-1 and c["repair_result_minute"]==-1 and c["charge_numerator"]==0 and not c["paused"]
func valid_fulfilment(c: Dictionary, day_hours: Dictionary) -> bool:
	var a:=publications[c["announcement_id"]] as Dictionary;var m: RefCounted=economy()._service_market
	if c["started_minute"]<0: return a["released_minute"]==-1 and c["work"]==[] and c["periods"]==[] and c["earned"]==0 and c["end_minute"]==-1 and c["last_boundary"]==-1 and c["status"] in ["ACCEPTED","CANCELLED"]
	var when:=int(c["started_minute"])
	return c["status"]=="COMPLETED" and c["custody_events"]==[] and when>c["accepted_minute"] and when%1440==0 and when<a["valid_until"] and c["end_minute"]==when and c["last_boundary"]==when and a["released_minute"]==when and c["periods"]==[{"minute":when,"earned_delta":c["total"],"publication_id":a["id"]}] and c["earned"]==c["total"] and day_hours=={when/1440:int(m._offers[c["offer_id"]]["announcement_terms"]["work_hours"])}
func _payload(a: Dictionary) -> Dictionary:
	return {"site_id":a["site_id"],"kind":a["kind"],"item":a["item"],"channel_id":a["channel_id"],"valid_days":a["valid_days"]}

func message_valid(message: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(message,["id","actor","kind","candidate","observed_day","delivery_day","source","announcement_id","channel_id","contact_minute","audience_basis"]) or not publications.has(message.get("announcement_id")): return false
	var a:=publications[message["announcement_id"]] as Dictionary;var ch:=_channels[a["channel_id"]] as Dictionary
	var candidate: String=str(a["firm"])+"|"+str(a["item"])+"|"+str(a["site_id"]) if a["kind"]=="GOODS" else a["item"]
	return message["source"]=="commercial" and message["actor"] in ch["recipients"] and message["id"]=="message:commercial:"+str(a["id"])+":"+str(message["actor"]) and message["kind"]==("supplier" if a["kind"]=="GOODS" else "service_offer") and message["candidate"]==candidate and message["channel_id"]==a["channel_id"] and message["audience_basis"]==ch["audience_basis"] and FormalLedgerState.valid_amount(message["contact_minute"]) and a["released_minute"]>=0 and message["contact_minute"]>=a["released_minute"] and message["contact_minute"]<a["valid_until"] and (a["withdrawn_minute"]<0 or message["contact_minute"]<a["withdrawn_minute"]) and message["observed_day"]==int(a["published_minute"])/1440 and message["delivery_day"]==int(message["contact_minute"])/1440+int(ch["delay_days"]) and (ch["kind"]=="SITE_BOARD" or message["contact_minute"]==a["released_minute"])

func snapshot() -> Dictionary: return {"format":FORMAT,"publications":publications.duplicate(true)}
func restore(raw: Variant, saved: Dictionary) -> bool:
	publications.clear();_boards.clear();_expiry.clear();_sent.clear();_service_known.clear();_received.clear();_days.clear();_limits.clear();_last.clear();_policy_enabled.clear();error=""
	for p: Dictionary in policies(): _policy_enabled[p["id"]]=true
	if raw==null: raw={"format":FORMAT,"publications":{}}
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw,["format","publications"]) or raw["format"]!=FORMAT or not raw["publications"] is Dictionary or raw["publications"].size()>4096: return _fail("Invalid commercial publication state")
	if not saved.get("commands") is Dictionary or not saved.get("messages") is Array or not saved.get("receipts") is Dictionary: return _fail("Invalid original commercial message/action containers")
	for entry: Variant in saved["commands"].values():
		if not entry is Dictionary or not entry.get("envelope") is Dictionary or not entry.get("result") is Dictionary: return _fail("Invalid original action record")
		var envelope:=entry["envelope"] as Dictionary
		if not envelope.get("actor") is String or not envelope.get("command") is Dictionary: return _fail("Invalid commercial action envelope")
		var cmd:=envelope["command"] as Dictionary
		if not cmd.get("action_id") is String or not cmd.get("kind") is String or not cmd.get("payload") is Dictionary or not FormalLedgerState.valid_amount(cmd.get("minute")): return _fail("Invalid commercial source command")
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	publications=raw["publications"].duplicate(true)
	var ordered: Array=publications.values()
	for a: Variant in ordered:
		if not a is Dictionary or not a.get("published_minute") is int: return _fail("Invalid publication source time")
	ordered.sort_custom(func(a: Variant,b: Variant)->bool: return int(a.get("published_minute",-1))<int(b.get("published_minute",-1)))
	for a: Variant in ordered:
		if not a is Dictionary or not FormalLedgerState.exact_fields(a,["id","action_id","actor","firm","site_id","kind","item","channel_id","published_minute","valid_days","valid_until","released_minute","service_id","quote","staff_refs","withdrawn_minute","withdrawal_action"]) or publications.get(a.get("id"))!=a or a["id"]!="announcement:"+str(a["action_id"]) or not _publication_fields(_payload(a)): return _fail("Invalid publication identity or fields")
		if not e._spec["sites"].has(a["site_id"]) or e._owner(a["site_id"])!=a["firm"] or not a["actor"] is String or not FormalLedgerState.valid_amount(a["published_minute"]) or a["published_minute"]>now or not e._manager_at(a["actor"],a["firm"],a["published_minute"]): return _fail("Publication lost source site or manager authority")
		var channel:=_channels[a["channel_id"]] as Dictionary
		if e._place(a["site_id"])!=channel["place_id"] or not _rate_ready(a["firm"],channel,int(a["published_minute"])/1440): return _fail("Publication range or cumulative issue limit conflict")
		var command: Dictionary=saved.get("commands",{}).get(a["action_id"],{});var envelope: Dictionary=command.get("envelope",{});var cmd: Dictionary=envelope.get("command",{})
		if not command.get("result",{}).get("accepted",false) or envelope.get("actor")!=a["actor"] or cmd.get("minute")!=a["published_minute"]: return _fail("Publication lacks accepted original action")
		var paid: bool=channel["kind"]=="PAID_LOCAL_PUBLICATION"
		var expected:=_payload(a);expected["firm"]=a["firm"]
		if not paid and (cmd.get("kind")!="publish_notice" or cmd.get("payload")!=expected or a["service_id"]!="" or a["released_minute"]!=a["published_minute"] or command["result"].get("announcement_id")!=a["id"]): return _fail("Site notice differs from source action")
		if paid and (cmd.get("kind")!="request_service" or cmd.get("payload",{}).get("announcement")!=_payload(a) or a["service_id"]!="service:"+str(a["action_id"]) or not saved.get("service_market",{}).get("contracts",{}).has(a["service_id"])): return _fail("Paid publication lost original service contract")
		var quote: Variant=a["quote"]
		if not quote is Dictionary or not FormalLedgerState.exact_fields(quote,["id","kind","price","denomination","quantity","offer_id","sources"]) or quote["id"]!="publication_quote:"+str(a["action_id"]) or quote["kind"]!=a["kind"] or not FormalLedgerState.valid_amount(quote["price"]) or quote["price"]<1 or not FormalLedgerState.valid_amount(quote["quantity"]) or quote["quantity"]<1 or not quote["sources"] is Array: return _fail("Invalid observed commercial quote")
		var until:=int(a["published_minute"])+int(a["valid_days"])*1440
		if a["kind"]=="GOODS":
			var recorded: Variant=command["result"].get("observed_goods_quote")
			if recorded!=null and (not recorded is Dictionary or recorded!=quote):return _fail("Goods notice differs from original adopted price observation")
			var original_price: bool=recorded is Dictionary or e._valid_publication_price(a["site_id"],a["item"],quote["price"],a["published_minute"])
			if not e._spec["sites"][a["site_id"]]["prices"].has(a["item"]) or "sales" not in e._spec["sites"][a["site_id"]]["roles"] or not original_price or quote["denomination"]!=e._sale_currency(a["firm"]) or quote["offer_id"]!="": return _fail("Goods notice has no legal source quote")
			var q:=0;var seen: Dictionary={}
			for row: Variant in quote["sources"]:
				if not row is Dictionary or not FormalLedgerState.exact_fields(row,["portion_id","source_id","quantity"]) or not FormalLedgerState.valid_amount(row["quantity"]) or row["quantity"]<1 or seen.has(row["portion_id"]): return _fail("Invalid publication stock reference")
				var portion: Dictionary=saved.get("stock_lots",{}).get("portions",{}).get(row["portion_id"],{})
				if portion.get("source_id")!=row["source_id"] or portion.get("owner")!=a["firm"] or portion.get("location")!="SITE|"+str(a["site_id"]) or portion.get("good")!=a["item"] or portion.get("opened_minute",now+1)>a["published_minute"] or row["quantity"]>int(portion.get("quantity",0)): return _fail("Publication stock lacks actual owner/site/source")
				seen[row["portion_id"]]=true;q+=int(row["quantity"])
			if q!=quote["quantity"] or q>10: return _fail("Publication announced quantity conflict")
		else:
			var o: Dictionary=e._service_market._offers.get(a["item"],{})
			if o.is_empty() or o["kind"]=="ANNOUNCEMENT" or e._service_market._facilities[o["facility_id"]]["site_id"]!=a["site_id"] or quote["offer_id"]!=a["item"] or quote["price"]!=o["price"] or quote["denomination"]!=o["denomination"] or quote["sources"]!=[] or a["published_minute"]<o["valid_from"] or a["published_minute"]>=o["valid_until"]: return _fail("Service notice has no original facility and offer")
			until=mini(until,int(o["valid_until"]))
		if a["valid_until"]!=until or not a["released_minute"] is int or a["released_minute"]< -1 or a["released_minute"]>now or (a["released_minute"]>=0 and (a["released_minute"]<a["published_minute"] or a["released_minute"]>=until)) or not a["withdrawn_minute"] is int or a["withdrawn_minute"]< -1 or a["withdrawn_minute"]>now: return _fail("Invalid publication time boundaries")
		if not a["staff_refs"] is Array or (not paid and a["staff_refs"].is_empty()): return _fail("Site notice lacks staffed business source")
		for id: Variant in a["staff_refs"]:
			var work: Dictionary=saved.get("work_records",{}).get(id,{})
			if work.get("day")!=int(a["published_minute"])/1440 or not e._spec["jobs"].has(work.get("job")) or e._job(work["job"])["site_id"]!=a["site_id"]: return _fail("Site notice has no actual local work")
		if a["withdrawn_minute"]>=0:
			var withdrawal: Dictionary=saved["commands"].get(a["withdrawal_action"],{})
			if not withdrawal.get("result",{}).get("accepted",false) or withdrawal.get("envelope",{}).get("command",{}).get("kind")!="withdraw_announcement" or withdrawal["envelope"]["command"]["payload"]!={"announcement_id":a["id"]} or withdrawal["envelope"]["command"]["minute"]!=a["withdrawn_minute"] or a["withdrawn_minute"]<a["released_minute"] or a["released_minute"]<0 or not e._manager_at(withdrawal["envelope"]["actor"],a["firm"],a["withdrawn_minute"]): return _fail("Publication withdrawal lacks authorized action")
		elif a["withdrawal_action"]!="": return _fail("Orphan publication withdrawal action")
		_index(a)
		if not paid and a["valid_until"]>now and a["withdrawn_minute"]<0:
			var place: String=channel["place_id"]
			if not _boards.has(place): _boards[place]={}
			_boards[place][a["id"]]=true
			var expiry: int=(int(a["valid_until"])+1439)/1440
			if not _expiry.has(expiry): _expiry[expiry]=[]
			_expiry[expiry].append(a["id"])
	for message: Variant in saved.get("messages",[])+saved.get("receipts",{}).values():
		if not message is Dictionary or message.get("source")!="commercial": continue
		if not message_valid(message) or message["contact_minute"]>now: return _fail("Invalid pending or received commercial message")
		var id: String=message["announcement_id"];var actor: String=message["actor"]
		if not _sent.has(id): _sent[id]={}
		if _sent[id].has(actor): return _fail("Repeated commercial recipient")
		_sent[id][actor]=true
		if _sent[id].size()>_channels[message["channel_id"]]["recipient_limit"]: return _fail("Commercial audience exceeds finite channel")
		if saved.get("receipts",{}).has(message["id"]):
			if int(message["delivery_day"])*1440>now: return _fail("Commercial knowledge predates actual delivery")
			adopted_message(message)
	var controls: Array=e._operating_history(saved.get("commands",{}))
	for command: Dictionary in controls:
		if command.get("result",{}).get("accepted",false) and command.get("envelope",{}).get("command",{}).get("kind")=="publish_notice" and not publications.has(command["result"].get("announcement_id")): return _fail("Accepted publication action lost its announcement")
		if not command.get("result",{}).get("accepted",false) or command.get("envelope",{}).get("command",{}).get("kind")!="set_publicity_policy": continue
		var p: Dictionary=command["envelope"]["command"]["payload"];var found:=false
		for policy: Dictionary in policies():
			if policy["id"]==p.get("policy_id") and FormalLedgerState.exact_fields(p,["policy_id","enabled"]) and p["enabled"] is bool and e._manager_at(command["envelope"]["actor"],policy["firm"],command["envelope"]["command"]["minute"]): _policy_enabled[policy["id"]]=p["enabled"];found=true
		if not found: return _fail("Invalid publicity policy control")
	return true
func validate_presence() -> bool:
	var e:=economy()
	var history:=e._operating_history(e._commands) as Array[Dictionary]
	for a: Dictionary in publications.values():
		if not _legal_site_at(a["site_id"],a["published_minute"],history): return _fail("Publication lacks lawful operating premises at issue time")
		if _channels[a["channel_id"]]["kind"]=="SITE_BOARD" and e._retail.has_site(a["site_id"]) and e._retail.allocated_hours(a["site_id"],int(a["published_minute"])/1440)<1: return _fail("Store board lacks actual adopted business work")
		if a["service_id"]!="" and a["released_minute"]>=0:
			var c:=e._service_market.contracts[a["service_id"]] as Dictionary
			if not _legal_site_at(c["provider_site"],a["released_minute"],history,true) or not _legal_site_at(a["site_id"],a["released_minute"],history,true): return _fail("Publication work lacks lawful provider or source premises")
	for collection: Variant in [e._messages,e._receipts.values()]:
		for message: Dictionary in collection:
			if message.get("source")!="commercial": continue
			var actor: String=message["actor"];var place: String=_channels[message["channel_id"]]["place_id"]
			if e._actors.has(actor):
				if not e.subject_active_at(actor,message["contact_minute"]) or not e._service_market._resident._present_at(actor,place,message["contact_minute"]): return _fail("Commercial contact lacks actual local presence")
			elif e._place(actor)!=place: return _fail("Business notice contact has wrong place")
	return true

func _legal_site_at(site: String, minute: int, history: Array[Dictionary], before_operating_commit: bool=false) -> bool:
	var e:=economy();var base:=e._spec["sites"][site] as Dictionary
	var enabled: bool=base["enabled"];var accepting: bool=base["accepting_business"];var operating:=true
	var through:=maxi(0,minute-1) if before_operating_commit else minute
	for entry: Dictionary in history:
		if entry["operating_minute"]>through: break
		if not entry["result"].get("accepted",false): continue
		var cmd:=entry["envelope"]["command"] as Dictionary;var p:=cmd["payload"] as Dictionary
		if p.get("firm")!=e._owner(site): continue
		if cmd["kind"]=="set_site_status" and p.get("site_id")==site: enabled=p["enabled"];accepting=p["accepting_business"]
		elif cmd["kind"]=="set_firm_operating": operating=p["operating"]
		elif cmd["kind"] in ["finish_firm","wind_down_firm"] or (cmd["kind"]=="close_site" and p.get("site_id")==site): return false
	return enabled and accepting and operating and e._leases.site_allowed(site,minute)

func visible(actor: String) -> Array[Dictionary]:
	var e:=economy();var result: Array[Dictionary]=[];var ids: Array=_received.get(actor,[]);var now: int=e._world.game_clock.total_minutes()
	for i: int in range(maxi(0,ids.size()-8),ids.size()):
		var message:=e._receipts[ids[i]] as Dictionary;var a:=publications[message["announcement_id"]] as Dictionary
		var quote:=a["quote"].duplicate(true) as Dictionary;quote.erase("sources")
		result.append({"id":a["id"],"firm":a["firm"],"site_id":a["site_id"],"place_id":e._place(a["site_id"]),"kind":a["kind"],"item":a["item"],"observed_quote":quote,"published_minute":a["published_minute"],"delivered_minute":int(message["delivery_day"])*1440,"valid_until":a["valid_until"],"current_notice":now<a["valid_until"] and a["withdrawn_minute"]<0,"basis":message["audience_basis"],"trade_rule":"CURRENT_ORIGINAL_QUOTE_FUNDS_STOCK_LOCATION_AND_CAPACITY_REQUIRED"})
	return result
func business_view(actor: String, firm: String, site: String) -> Dictionary:
	var e:=economy();var actions: Array[Dictionary]=[];var rows: Array[Dictionary]=[];var now: int=e._world.game_clock.total_minutes()
	if not e._manager(actor,firm): return {}
	for channel: Dictionary in _channels.values():
		if channel["place_id"]!=e._place(site): continue
		var items: Array[Dictionary]=[]
		for good: String in e._spec["sites"][site]["prices"]: items.append({"kind":"GOODS","item":good})
		for o: Dictionary in e._service_market._offers.values():
			if o["kind"]!="ANNOUNCEMENT" and e._service_market._facilities[o["facility_id"]]["site_id"]==site: items.append({"kind":"SERVICE","item":o["id"]})
		for item: Dictionary in items:
			var p:={"site_id":site,"kind":item["kind"],"item":item["item"],"channel_id":channel["id"],"valid_days":maxi(3,int(channel["delay_days"])+3) if channel["kind"]=="PAID_LOCAL_PUBLICATION" else 3}
			var result:=prepare(actor,firm,p,"preview")
			var payload:=p.duplicate(true);payload["firm"]=firm
			var kind:="publish_notice";var fee:=0
			if channel["kind"]=="PAID_LOCAL_PUBLICATION":
				fee=int(e._service_market._offers[channel["service_offer"]]["price"]);kind="request_service"
				payload={"firm":firm,"payer":firm,"offer_id":channel["service_offer"],"max_amount":fee,"announcement":p}
				result=e._service_market._accept(actor,payload,"preview",true)
			actions.append({"kind":kind,"label":("地点公告 " if fee==0 else "付费本地公告 ")+str(item["item"])+" · "+str(fee),"payload":payload,"can_execute":result["accepted"],"reason":result["reason"],"delay_days":channel["delay_days"],"recipient_limit":channel["recipient_limit"]})
	var ids: Array=[]
	for date: int in range(maxi(0,e.day-30),e.day+1): ids.append_array(_days.get(firm,{}).get(date,[]))
	for i: int in range(maxi(0,ids.size()-8),ids.size()):
		var a:=publications[ids[i]] as Dictionary;var sent:=_sent.get(a["id"],{}) as Dictionary;var delivered:=0
		for recipient: String in sent:
			if e._receipts.has("message:commercial:"+str(a["id"])+":"+recipient): delivered+=1
		var c: Dictionary=e._service_market.contracts.get(a["service_id"],{})
		rows.append({"id":a["id"],"kind":a["kind"],"item":a["item"],"channel":a["channel_id"],"published_minute":a["published_minute"],"released_minute":a["released_minute"],"valid_until":a["valid_until"],"withdrawn_minute":a["withdrawn_minute"],"scheduled_recipients":sent.size(),"delivered_recipients":delivered,"fee_earned":c.get("earned",0),"fee_paid":c.get("paid",0),"own_sales_observation":_sales_since(a)})
		if a["released_minute"]>=0 and a["withdrawn_minute"]<0 and now<a["valid_until"]: actions.append({"kind":"withdraw_announcement","label":"停止公告后续接触","payload":{"announcement_id":a["id"]},"can_execute":true,"reason":"PRIOR_DELIVERED_MESSAGES_RETAINED"})
	for p: Dictionary in policies():
		if p["firm"]==firm: actions.append({"kind":"set_publicity_policy","label":"暂停后续自主宣传" if _policy_enabled[p["id"]] else "恢复自主宣传","payload":{"policy_id":p["id"],"enabled":not _policy_enabled[p["id"]]},"can_execute":true,"reason":"CURRENT_MANAGER_ONLY"})
	return {"enabled":not _channels.is_empty(),"announcements":rows,"actions":actions,"received":visible(site),"result_basis":"OBSERVED_DELIVERIES_AND_OWN_SALES_NO_ADVERTISING_CAUSAL_RETURN"}
func _sales_since(a: Dictionary) -> Dictionary:
	var e:=economy();var site: String=a["site_id"]
	var first:=maxi(int(a["published_minute"])/1440,maxi(0,e.day-e._request_retention_window(site)+1))
	var quantity:=0;var requests:=0
	if a["kind"]=="GOODS":
		for date: int in range(first,e.day+1): quantity+=int(e._delivery_days.get(site+"|"+str(a["item"]),{}).get(date,{}).get("quantity",0))
		for row: Dictionary in e._request_window.get(site+"|"+str(a["item"]),[]):
			if row["day"]>=first: requests+=1
	return {"from_day":first,"through_day":e.day,"delivered_goods_quantity":quantity,"latest_customer_request_records":requests,"basis":"OWN_DELIVERIES_AND_LATEST_PER_CUSTOMER_REQUESTS_NOT_ADVERTISING_CAUSAL_ATTRIBUTION"}
func observation_days(site: String) -> int:
	var result:=0
	for p: Dictionary in policies():
		if p["site_id"]==site: result=maxi(result,int(p["sales_window"]))
	return result
func npc_decisions() -> void:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	for p: Dictionary in policies():
		var firm: String=p["firm"];var site: String=p["site_id"];var channel:=_channels[p["channel_id"]] as Dictionary
		if not _policy_enabled[p["id"]] or e.firm_manager_at(firm,now)!=firm or not e._site_accepting(site) or e._firm_winding_down(firm) or not _rate_ready(firm,channel,e.day): continue
		var changing:=false
		for id: String in e._pending_enterprise_changes:
			if e._enterprise_changes[id]["firm"]==firm and e._enterprise_changes[id]["boundary_minute"]<=now: changing=true;break
		if changing: continue
		if p["kind"]=="GOODS":
			if int(e._stocks[site][p["item"]])-e._committed(site,p["item"])<p["minimum_stock"]: continue
			var sold:=0
			for date: int in range(maxi(0,e.day-int(p["sales_window"])+1),e.day+1): sold+=int(e._delivery_days.get(site+"|"+str(p["item"]),{}).get(date,{}).get("quantity",0))
			if sold>p["sales_at_most"]: continue
		if p["kind"]=="SERVICE":
			var delivered:=0
			for id: String in e._service_market.recent_contracts(firm,maxi(0,e.day-int(p["sales_window"])+1)*1440):
				var c:=e._service_market.contracts[id] as Dictionary
				if c["provider"]==firm and c["offer_id"]==p["item"] and c["earned"]>0: delivered+=1
			if delivered>p["sales_at_most"]: continue
		var data:={"site_id":site,"kind":p["kind"],"item":p["item"],"channel_id":p["channel_id"],"valid_days":p["valid_days"]}
		var kind:="publish_notice";var payload:=data.duplicate(true);payload["firm"]=firm
		var currency: String=e._sale_currency(firm);var fee:=0
		if channel["kind"]=="PAID_LOCAL_PUBLICATION":
			var o:=e._service_market._offers[channel["service_offer"]] as Dictionary
			currency=o["denomination"];fee=o["price"]
			if fee>p["max_fee"]: continue
			payload={"firm":firm,"payer":firm,"offer_id":o["id"],"max_amount":p["max_fee"],"announcement":data};kind="request_service"
		if e._world.ledger_state.available_balance(e._account(firm,currency))<int(p["cash_floor"])+fee: continue
		e._accept(firm,{"action_id":"auto:"+firm+":publicity:"+str(p["id"])+":"+str(e.day),"minute":now,"kind":kind,"payload":payload},true)
func _reject(reason: String) -> Dictionary: return {"accepted":false,"reason":reason}
func _fail(reason: String) -> bool: error=reason;return false

## The original workplace recruitment channel. It does not license the paid
## goods/services publication offer to sell recruitment advertising.
func publish_recruitment(q: Dictionary, selected_actor: String="") -> void:
	var e:=economy();var job: String=q["job_id"];var now: int=e._world.game_clock.total_minutes()
	if q["status"]!="APPLIED" or now<q["effective_minute"] or now>=q["valid_until"]: return
	var rule:=e._labor_market._rules[job] as Dictionary
	for actor: String in rule["recipients"]:
		if not selected_actor.is_empty() and actor!=selected_actor: continue
		if not e._actors.has(actor) or not e.subject_active_at(actor,now) or not e._at_place(actor,e._spec["jobs"][job]["place"]): continue
		var m:=e._labor_market.message(q,actor,now) as Dictionary
		if e._receipts.has(m["id"]): continue
		var found:=false
		for pending: Dictionary in e._messages:
			if pending["id"]==m["id"]: found=true;break
		if not found: e._messages.append(m)
