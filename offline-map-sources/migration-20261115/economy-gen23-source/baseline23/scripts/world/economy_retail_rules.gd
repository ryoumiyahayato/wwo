class_name EconomyRetailRules
extends RefCounted
## Sales remain EconomyR1Slice orders/receipts. Only storefront staffing facts
## live here; inventory, cash, acquisitions and costs keep their original owners.
const FORMAT := "economy_retail_rules_v1"
var error: String = ""
var windows: Dictionary = {}
var _ref: WeakRef
var _sites: Dictionary = {}
var _used: Dictionary = {}
var _hours: Dictionary = {}
var _days: Dictionary = {}
var last_work: Dictionary = {}
func economy() -> RefCounted: return _ref.get_ref()
func bind(e: RefCounted) -> void:
	_ref=weakref(e)
	for row: Dictionary in e.config.get("retail_sites",[]): _sites[row["site_id"]]=row
static func valid_configuration(settings: Dictionary, spec: Dictionary) -> bool:
	var rows: Variant=settings.get("retail_sites",[])
	if not rows is Array or rows.size()>32: return false
	if rows.is_empty(): return true
	var sites: Dictionary=spec["sites"].duplicate(true)
	var jobs: Dictionary=spec["jobs"].duplicate(true)
	for expansion: Dictionary in settings.get("runtime_expansions",[]):
		for entry: Dictionary in expansion["extension"].get("sites",[]):
			var site: Dictionary=entry["site"].duplicate(true);site["firm_id"]=entry["firm_id"];sites[site["id"]]=site
		for job: Dictionary in expansion["extension"].get("jobs",[]): jobs[job["id"]]=job
	var seen: Dictionary={}
	for row: Variant in rows:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["site_id","firm_id","job_ids","stock_units","stock_capacity","stock_unit","hours_per_day","units_per_hour","daily_limit","open_from","open_until","restock","window_days","onsite_first_for","basis","time_basis"]): return false
		if not row["site_id"] is String or not sites.has(row["site_id"]) or seen.has(row["site_id"]) or not row["firm_id"] is String or not spec["firms"].has(row["firm_id"]): return false
		seen[row["site_id"]]=true
		var site: Dictionary=sites[row["site_id"]]
		if site.get("firm_id",site.get("firm"))!=row["firm_id"] or "sales" not in site["roles"]: return false
		if row["basis"]!="EXPLICIT_DEVELOPMENT_STOREFRONT" or row["time_basis"]!="SETTLED_DAILY_STAFFING_WINDOW" or row["stock_unit"]!="development_dedicated_store_stock_unit": return false
		for key: String in ["stock_capacity","hours_per_day","units_per_hour","daily_limit","window_days"]:
			if not FormalLedgerState.valid_amount(row[key]) or row[key]<1 or row[key]>1000000: return false
		if row["window_days"]>30 or row["hours_per_day"]>64 or not FormalLedgerState.valid_amount(row["open_from"]) or not FormalLedgerState.valid_amount(row["open_until"]) or row["open_from"]>=row["open_until"] or row["open_until"]>1440: return false
		if not row["job_ids"] is Array or row["job_ids"].is_empty() or not row["stock_units"] is Dictionary or row["stock_units"].is_empty() or not row["restock"] is Dictionary: return false
		if not row["onsite_first_for"] is Array: return false
		for actor: Variant in row["onsite_first_for"]:
			if not actor is String or not spec["actors"].has(actor) or spec["actors"][actor]["control"]!="automatic": return false
		var used: Dictionary={}
		for id: Variant in row["job_ids"]:
			if not id is String or used.has(id) or not jobs.has(id) or jobs[id]["site_id"]!=row["site_id"] or jobs[id]["employer"]!=row["firm_id"]: return false
			used[id]=true
		for good: String in row["stock_units"]:
			if good not in spec["good_ids"] or not FormalLedgerState.valid_amount(row["stock_units"][good]) or row["stock_units"][good]<1 or row["stock_units"][good]>1000 or not site["prices"].has(good): return false
		for good: String in row["restock"]:
			var policy: Variant=row["restock"][good]
			if good not in row["stock_units"] or not policy is Dictionary or not FormalLedgerState.exact_fields(policy,["target","threshold","batch_limit","max_price","cash_floor"]): return false
			for value: Variant in policy.values():
				if not FormalLedgerState.valid_amount(value): return false
			if policy["target"]<1 or policy["threshold"]>policy["target"] or policy["batch_limit"]<1 or policy["max_price"]<1 or policy["target"]*int(row["stock_units"][good])>row["stock_capacity"]: return false
	return true
func has_site(site: String) -> bool: return _sites.has(site)
func observation_days(site: String) -> int: return int(_sites.get(site,{}).get("window_days",0))
func labor_needed(site: String) -> int:
	return int(_sites[site]["hours_per_day"]) if has_site(site) and economy()._site_accepting(site) else 0
func allocated_hours(site: String, date: int=-1) -> int:
	return int(_hours.get(site,0)) if date<0 else int(_days.get(site,{}).get(date,0))
func _key(site: String, date: int) -> String: return "retail_window:"+site+":"+str(date)
func _index(w: Dictionary) -> void:
	var site: String=w["site_id"];var date: int=w["day"];var q:=0
	for work: Dictionary in w["work"]: q+=int(work["hours"])
	_hours[site]=int(_hours.get(site,0))+q
	if not _days.has(site): _days[site]={}
	_days[site][date]=int(_days[site].get(date,0))+q
func prepare_labor(prior: Dictionary) -> void:
	last_work.clear()
	var e:=economy();var used:=prior.duplicate()
	for site: String in _sites:
		if not e._spec["sites"].has(site) or not e._site_accepting(site) or not e._site_operating(site,e._production_minute()): continue
		var row:=_sites[site] as Dictionary;var id:=_key(site,e.day)
		if windows.has(id): continue
		var work_rows: Array[Dictionary]=[];var wanted:=int(row["hours_per_day"])
		for work_id: String in e._capital_work_ids:
			var work:=e._work_records[work_id] as Dictionary
			if work["job"] not in row["job_ids"]: continue
			var q:=mini(wanted,int(work["hours"])-int(used.get(work_id,0)))
			if q<=0: continue
			work_rows.append({"id":work_id,"hours":q})
			used[work_id]=int(used.get(work_id,0))+q
			last_work[work_id]=int(last_work.get(work_id,0))+q
			e._labor[site]=int(e._labor.get(site,0))-q
			if e._costs.enabled: e._costs.assign_work(work_id,q,"RETAIL",id)
			wanted-=q
			if wanted==0: break
		var w:={"id":id,"site_id":site,"day":e.day,"minute":e._world.game_clock.total_minutes(),"work":work_rows}
		windows[id]=w;_index(w)
func limit(site: String, minute: int=-1) -> int:
	if not has_site(site): return 0
	var e:=economy()
	if minute<0:
		if not e._site_accepting(site): return 0
		minute=e._world.game_clock.total_minutes()
	var row:=_sites[site] as Dictionary;var date:=minute/1440;var id:=_key(site,date)
	if minute%1440<int(row["open_from"]) or minute%1440>=int(row["open_until"]) or not windows.has(id): return 0
	return maxi(0,mini(int(row["daily_limit"]),int(_days.get(site,{}).get(date,0))*int(row["units_per_hour"]))-int(_used.get(id,0)))
func reason(actor: String, site: String, good: String) -> String:
	var e:=economy()
	if not has_site(site) or good not in _sites[site]["stock_units"]: return "NOT_CONFIGURED_STOREFRONT_GOOD"
	if not e._spec["actors"].has(actor) or not e._at_place(actor,e._place(site)): return "ONSITE_CUSTOMER_NOT_AT_STORE"
	if not e._site_selling(site): return "STORE_PREMISES_OR_BUSINESS_UNAVAILABLE"
	if e._declared_named(actor) and (e._work_queue.has(actor) or e._service_market._resident.booked(actor)): return "ONSITE_CUSTOMER_ACTIVITY_CONFLICT"
	var now: int=e._world.game_clock.total_minutes()
	if now%1440<int(_sites[site]["open_from"]) or now%1440>=int(_sites[site]["open_until"]): return "STORE_CLOSED_AT_CURRENT_TIME"
	if allocated_hours(site,now/1440)<=0: return "STORE_NO_ACTUAL_STAFFING"
	if limit(site)<=0: return "STORE_DAILY_SALES_CAPACITY_EXHAUSTED"
	return "OFFER"
func headroom(site: String, good: String) -> int:
	if not has_site(site): return FormalLedgerState.MAX_AMOUNT
	var row:=_sites[site] as Dictionary
	if good not in row["stock_units"]: return 0
	var occupied:=0
	for item: String in row["stock_units"]: occupied+=economy()._exposure(site,item)*int(row["stock_units"][item])
	return maxi(0,int(row["stock_capacity"])-occupied)/int(row["stock_units"][good])
func target(site: String, good: String) -> int:
	if not has_site(site): return -1
	var policy: Dictionary=_sites[site]["restock"].get(good,{})
	if policy.is_empty(): return 0
	var e:=economy();var exposure: int=e._exposure(site,good)-e._committed(site,good)
	return int(policy["target"]) if exposure<=int(policy["threshold"]) else 0
func procurement_limit(site: String, good: String, offer: Dictionary, wanted: int) -> int:
	if not has_site(site): return wanted
	var policy: Dictionary=_sites[site]["restock"].get(good,{})
	if policy.is_empty() or int(offer["price"])+int(offer["freight_per_unit"])>int(policy["max_price"]): return 0
	var cash: int=economy()._world.ledger_state.available_balance(economy()._account(_sites[site]["firm_id"],offer["denomination"]))
	return mini(wanted,mini(int(policy["batch_limit"]),mini(headroom(site,good),maxi(0,cash-int(policy["cash_floor"]))/maxi(1,int(offer["price"])+int(offer["freight_per_unit"])))))
func adopted(receipt: Dictionary, order: Dictionary) -> void:
	if not onsite(order): return
	var id:=_key(order["seller_site"],int(receipt["delivered_minute"])/1440)
	_used[id]=int(_used.get(id,0))+int(receipt["quantity"])
static func onsite(order: Dictionary) -> bool: return str(order.get("route_id","")).begins_with("onsite:")
func view(site: String) -> Dictionary:
	if not has_site(site): return {}
	var e:=economy();var row:=_sites[site] as Dictionary
	var stock: Dictionary={};var incoming: Dictionary={}
	for good: String in row["stock_units"]:
		stock[good]=maxi(0,int(e._stocks.get(site,{}).get(good,0))-e._committed(site,good)) if e._spec["sites"].has(site) else 0
		incoming[good]=maxi(0,e._exposure(site,good)-int(e._stocks[site][good])) if e._spec["sites"].has(site) else 0
	var recent: Dictionary={}
	var wages: Dictionary={};var first: int=e.day-int(row["window_days"])+1
	for date: int in range(maxi(1,first),e.day+1):
		for work: Dictionary in windows.get(_key(site,date),{}).get("work",[]):
			var claim: Dictionary=e._wages[work["id"]];var cur: String=claim["denomination"]
			wages[cur]=int(wages.get(cur,0))+int(work["hours"])*int(claim["amount"])/int(claim["hours"])
	for good: String in row["stock_units"]:
		var sold:=0
		for date: int in range(maxi(0,first),e.day+1): sold+=int(e._delivery_days.get(site+"|"+good,{}).get(date,{}).get("quantity",0))
		recent[good]=sold
	return {"site_id":site,"operating_result":operating_result(site),"recent_sales":recent,"available_sales_units":limit(site),"allocated_hours":allocated_hours(site,e.day),"inventory":stock,"incoming":incoming,"stock_capacity":row["stock_capacity"],"stock_unit":row["stock_unit"],"restock":row["restock"].duplicate(true),"opening":[row["open_from"],row["open_until"]],"store_wages_by_currency":wages,"premises_allowed":e._site_accepting(site) if e._spec["sites"].has(site) else false,"cost_scope":"STORE_WAGES_SEPARATE_FROM_GOODS_CONTRIBUTION_RENT_AND_FREIGHT_NO_NET_PROFIT"}
func snapshot() -> Dictionary: return {"format":FORMAT,"windows":windows.duplicate(true)}
func restore(raw: Variant, saved: Dictionary) -> bool:
	windows.clear();_hours.clear();_days.clear();_used.clear()
	if raw==null: return not economy().config.has("retail_sites")
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw,["format","windows"]) or raw["format"]!=FORMAT or not raw["windows"] is Dictionary: return _fail("Invalid retail staffing state")
	var e:=economy();var use: Dictionary={}
	for p: Dictionary in saved.get("capital_formation",{}).get("projects",{}).values():
		for r: Dictionary in p["work"]: use[r["id"]]=int(use.get(r["id"],0))+int(r["hours"])
	for c: Dictionary in saved.get("service_market",{}).get("contracts",{}).values():
		for r: Dictionary in c["work"]: use[r["id"]]=int(use.get(r["id"],0))+int(r["hours"])
	for h: Dictionary in saved.get("shared_transport",{}).get("handling",{}).values():
		for r: Dictionary in h["work"]: use[r["work_id"]]=int(use.get(r["work_id"],0))+int(r["hours"])
	for id: Variant in raw["windows"]:
		var w: Variant=raw["windows"][id]
		if not w is Dictionary or not FormalLedgerState.exact_fields(w,["id","site_id","day","minute","work"]) or not _sites.has(w["site_id"]) or not e._spec["sites"].has(w["site_id"]) or not FormalLedgerState.valid_amount(w["day"]) or w["day"]<1 or w["day"]>saved["day"] or w["minute"]!=int(w["day"])*1440 or w["id"]!=id or id!=_key(w["site_id"],w["day"]) or not w["work"] is Array: return _fail("Invalid retail window identity")
		var total:=0;var seen: Dictionary={}
		for r: Variant in w["work"]:
			if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","hours"]) or seen.has(r["id"]) or not saved["work_records"].has(r["id"]) or not FormalLedgerState.valid_amount(r["hours"]) or r["hours"]<1: return _fail("Invalid retail work reference")
			seen[r["id"]]=true
			var work: Dictionary=saved["work_records"][r["id"]]
			if work["job"] not in _sites[w["site_id"]]["job_ids"] or work["day"]!=w["day"]: return _fail("Retail labor differs from actual job or date")
			use[r["id"]]=int(use.get(r["id"],0))+int(r["hours"]);total+=int(r["hours"])
			if use[r["id"]]>work["hours"]: return _fail("Retail duplicates work")
		if total>_sites[w["site_id"]]["hours_per_day"]: return _fail("Retail staffing exceeds policy")
		windows[id]=w.duplicate(true);_index(w)
	for item: Variant in saved["delivery_receipts"].values():
		if not item is Dictionary or not item.get("order_id") is String or not saved["orders"].get(item["order_id"]) is Dictionary: return _fail("Invalid retail delivery reference")
		var receipt:=item as Dictionary
		var order:=saved["orders"][receipt["order_id"]] as Dictionary
		if not onsite(order): continue
		if not order.get("seller_site") is String or not order.get("good") is String or not FormalLedgerState.valid_amount(receipt.get("delivered_minute")) or not FormalLedgerState.valid_amount(receipt.get("quantity")): return _fail("Invalid onsite sale fields")
		var site: String=order["seller_site"];var minute: int=receipt["delivered_minute"]
		if not has_site(site) or minute!=order["accepted_minute"] or receipt["quantity"]!=order["quantity"] or receipt["departures"]!=[] or not _sites[site]["stock_units"].has(order["good"]) or limit(site,minute)<int(receipt["quantity"]): return _fail("Onsite sale exceeds adopted staffing window")
		adopted(receipt,order)
	return true
func validate_presence() -> bool:
	var e:=economy()
	# Replay only the already-validated operating commands once on restore.
	# Later pauses must not invalidate lawful earlier sales or staffing.
	var history: Dictionary={};var flags: Dictionary={}
	for site: String in _sites:
		var base: Dictionary=e._spec["sites"].get(site,{})
		if base.is_empty(): continue
		flags[site]={"enabled":base["enabled"],"accepting":base["accepting_business"],"firm":true,"closed":false}
		history[site]=[{"minute":0,"allowed":bool(base["enabled"]) and bool(base["accepting_business"])}]
	for entry: Dictionary in e._operating_history(e._commands):
		if not entry["result"].get("accepted",false): continue
		var command: Dictionary=entry["envelope"]["command"];var p: Dictionary=command["payload"]
		if command["kind"] not in ["set_site_status","set_firm_operating","close_site","finish_firm","wind_down_firm"]: continue
		for site: String in flags:
			if p.get("firm")!=_sites[site]["firm_id"]: continue
			var row:=flags[site] as Dictionary
			if command["kind"]=="set_site_status" and p.get("site_id")==site: row["enabled"]=p["enabled"];row["accepting"]=p["accepting_business"]
			elif command["kind"]=="set_firm_operating": row["firm"]=p["operating"]
			elif command["kind"]=="close_site" and p.get("site_id")==site: row["closed"]=true
			elif command["kind"]=="finish_firm": row["firm"]=false
			# Wind-down retains lawful stock disposal at the existing staffed store.
			# It does not rewrite the original site acceptance flags.
			history[site].append({"minute":entry["operating_minute"],"allowed":bool(row["enabled"]) and bool(row["accepting"]) and bool(row["firm"]) and not bool(row["closed"])})
	for w: Dictionary in windows.values():
		var minute:=int(w["minute"])-1
		if not _allowed_at(history,w["site_id"],minute) or not e._leases.site_allowed(w["site_id"],minute): return _fail("Retail staffing lacks prior lawful premises")
	for receipt: Dictionary in e._delivery_receipts.values():
		var order: Dictionary=e._orders[receipt["order_id"]]
		if not onsite(order): continue
		var minute: int=receipt["delivered_minute"]
		# Automatic household buying belongs to settle_day, before the host
		# commits queued operating changes at this same minute. Player actions
		# after the boundary still use the new state. Lease expiry is checked at
		# the actual minute, not moved into the preceding lease interval.
		var operating_minute:=minute
		var command: Dictionary=e._commands.get(order["action_id"],{})
		var expected:="auto:"+str(order["buyer"])+":"+str(order["accepted_day"])+":buy:"+str(order["need_category"])+"|"+str(order["seller_site"])+"|"+str(order["good"])+"|"+str(order["route_id"])
		if minute%1440==0 and command.get("source")=="automatic" and e._actors[order["buyer"]]["control"]=="automatic" and order["action_id"]==expected: operating_minute=maxi(0,minute-1)
		if not e._service_market._resident._present_at(order["buyer"],order["to_place_id"],minute) or not e._leases.site_allowed(order["seller_site"],minute) or not _allowed_at(history,order["seller_site"],operating_minute): return _fail("Onsite sale lacks lawful premises or customer presence")
	return true
func _fail(message: String) -> bool: error=message;return false

func prefers(actor: String, offer: Dictionary) -> bool:
	return onsite(offer) and has_site(offer["seller_site"]) and actor in _sites[offer["seller_site"]]["onsite_first_for"] and int(offer["quantity"])>0

func _allowed_at(history: Dictionary, site: String, minute: int) -> bool:
	var allowed:=false
	for row: Dictionary in history.get(site,[]):
		if row["minute"]>minute: break
		allowed=row["allowed"]
	return allowed
func operating_result(site: String) -> Dictionary:
	var e:=economy();var result:={"fulfilled_sales":{},"cash_received":{},"sold_known_cost":{},"comparable_revenue":{},"known_goods_contribution":{},"unknown_sales":0,"incomparable_sales":0,"basis":"GOODS_CONTRIBUTION_BEFORE_STORE_WAGES_RENT_AND_OTHER_OVERHEADS_NOT_NET_PROFIT"}
	if not e._costs.enabled: return result
	for date: int in range(maxi(0,e.day-observation_days(site)+1),e.day+1):
		for id: String in e._costs._sales_days.get(site,{}).get(date,[]):
			var receipt: Dictionary=e._delivery_receipts[id];var order: Dictionary=e._orders[receipt["order_id"]]
			var currency: String=order["denomination"];var revenue:=int(receipt["quantity"])*int(order["price"])
			result["fulfilled_sales"][currency]=int(result["fulfilled_sales"].get(currency,0))+revenue
			var payment: Dictionary=e._world.ledger_state.transaction("r1:goods:"+id)
			result["cash_received"][currency]=int(result["cash_received"].get(currency,0))+int(payment.get("amount",0))
			var cost: Dictionary=e._costs.cost_of(e._costs.sales[id])
			for cur: String in cost["amounts"]: result["sold_known_cost"][cur]=int(result["sold_known_cost"].get(cur,0))+int(cost["amounts"][cur])
			if not cost["unknown"].is_empty(): result["unknown_sales"]+=1;continue
			if cost["amounts"].size()>1 or (cost["amounts"].size()==1 and not cost["amounts"].has(currency)): result["incomparable_sales"]+=1;continue
			result["comparable_revenue"][currency]=int(result["comparable_revenue"].get(currency,0))+revenue
			result["known_goods_contribution"][currency]=int(result["known_goods_contribution"].get(currency,0))+revenue-int(cost["amounts"].get(currency,0))
	return result
