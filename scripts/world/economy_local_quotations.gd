extends RefCounted
## Optional sandbox experiment. R1 still owns orders, messages, cash and lots.
## Quote versions are immutable terms, not a second market or price simulator.
var host: WeakRef
var quotes: Dictionary = {}
var saved_receipts: Dictionary = {}
var error: String = ""

func bind(value: RefCounted) -> void:
	host = weakref(value)

func economy() -> EconomyR1Slice:
	return host.get_ref() as EconomyR1Slice

static func valid_configuration(config: Dictionary, spec: Dictionary) -> bool:
	if not config.has("local_quotation_experiment"): return true
	var cfg: Variant = config["local_quotation_experiment"]
	if not cfg is Dictionary or not FormalLedgerState.exact_fields(cfg,["basis","npc_enabled","rules"]) or cfg["basis"] != "GENERATED_SIMULATION_ASSUMPTION_LOCAL_QUOTATIONS" or not cfg["npc_enabled"] is bool or not cfg["rules"] is Array or cfg["rules"].is_empty() or cfg["rules"].size()>8: return false
	var seen: Dictionary = {}
	for row: Variant in cfg["rules"]:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["firm","site","good","period","window","tick","tight","volume","idle_cover","notice_days","valid_days","authority_basis"]): return false
		if not spec["sites"].has(row["site"]) or spec["sites"][row["site"]]["firm_id"] != row["firm"] or not spec["sites"][row["site"]]["prices"].has(row["good"]) or int(spec["sites"][row["site"]]["prices"][row["good"]])<=0 or row["authority_basis"] != "DEVELOPMENT_FIRM_SALES_MANDATE": return false
		for field: String in ["period","window","tick","tight","volume","idle_cover","notice_days","valid_days"]:
			if typeof(row[field]) != TYPE_INT or int(row[field])<1 or int(row[field])>90: return false
		if int(row["valid_days"])<=int(row["period"])+int(row["notice_days"]): return false
		var key: String = row["site"]+"|"+row["good"]
		if seen.has(key): return false
		seen[key]=true
		for policy: Dictionary in config.get("price_policies",[]):
			if policy["firm"]==row["firm"] and policy["good"]==row["good"] and policy.get("site_id",row["site"])==row["site"] and policy["mode"]!="N2": return false
	return true

func rules() -> Array:
	return economy().config.get("local_quotation_experiment",{}).get("rules",[])

func rule(site: String, good: String) -> Dictionary:
	for row: Dictionary in rules():
		if row["site"]==site and row["good"]==good: return row
	return {}

func initialize() -> void:
	var e := economy()
	for r: Dictionary in rules():
		var id: String = "goods_quote:"+r["site"]+":"+r["good"]+":0"
		quotes[id]={"id":id,"site":r["site"],"good":r["good"],"version":0,"price":e._spec["sites"][r["site"]]["prices"][r["good"]],"action_id":"","posted_minute":0,"effective_day":0,"expires_day":r["valid_days"]}
	announce_known()

func current(site: String, good: String, minute: int = -1) -> Dictionary:
	if minute<0: minute=economy()._world.game_clock.total_minutes()
	var found: Dictionary = {}
	for q: Dictionary in quotes.values():
		if q["site"]==site and q["good"]==good and int(q["effective_day"])*1440<=minute and (found.is_empty() or int(q["version"])>int(found["version"])): found=q
	return found

func source_receipt(observer: String, q: Dictionary, receipts: Dictionary) -> String:
	var e := economy()
	for id: String in receipts:
		var m: Dictionary = receipts[id]
		if m.get("kind")!="supplier" or e._inventory_key(m["actor"])!=observer: continue
		var c := e._candidate(m["candidate"])
		if c["site"]==q["site"] and c["good"]==q["good"]: return id
	return ""

func announce_known() -> void:
	var e := economy()
	for q: Dictionary in quotes.values():
		if int(q["expires_day"])<=e.day: continue
		for receipt: Dictionary in e._receipts.values().duplicate():
			if receipt.get("kind")!="supplier": continue
			var c := e._candidate(receipt["candidate"])
			if c["site"]!=q["site"] or c["good"]!=q["good"]: continue
			var actor: String = receipt["actor"]
			var id: String = "notice:"+q["id"]+":"+actor
			if e._receipts.has(id): continue
			var pending: bool = false
			for m: Dictionary in e._messages:
				if m["id"]==id: pending=true; break
			if pending: continue
			e._messages.append({"id":id,"actor":actor,"kind":"goods_quote","candidate":q["id"],"observed_day":e.day,"delivery_day":e.day+int(rule(q["site"],q["good"])["notice_days"]),"source_receipt":receipt["id"]})

func known(observer: String, site: String, good: String, minute: int = -1) -> Dictionary:
	var e := economy()
	if minute<0: minute=e._world.game_clock.total_minutes()
	var found: Dictionary = {}
	var receipts: Dictionary = saved_receipts if not saved_receipts.is_empty() else e._receipts
	for m: Dictionary in receipts.values():
		if m.get("kind")!="goods_quote" or e._inventory_key(m["actor"])!=observer or int(m["delivery_day"])*1440>minute or not quotes.has(m["candidate"]): continue
		var q: Dictionary = quotes[m["candidate"]]
		if q["site"]==site and q["good"]==good and int(q["effective_day"])*1440<=minute and (found.is_empty() or int(q["version"])>int(found["version"])): found=q
	return found

func reason(observer: String, site: String, good: String, minute: int = -1) -> String:
	if rule(site,good).is_empty(): return ""
	var q := known(observer,site,good,minute)
	if q.is_empty(): return "GOODS_QUOTE_NOT_RECEIVED"
	if minute<0: minute=economy()._world.game_clock.total_minutes()
	if minute>=int(q["expires_day"])*1440: return "GOODS_QUOTE_EXPIRED"
	return "GOODS_QUOTE_SUPERSEDED" if q!=current(site,good,minute) else ""

func offer(observer: String, value: Dictionary) -> Dictionary:
	if rule(value["seller_site"],value["good"]).is_empty(): return value
	var q := known(observer,value["seller_site"],value["good"])
	var why := reason(observer,value["seller_site"],value["good"])
	value["published_quote_id"]=q.get("id","")
	value["quote_id"]+="|"+str(q.get("id","unknown"))
	value["price"]=q.get("price",null)
	if not why.is_empty(): value["quantity"]=0; value["reason"]=why
	return value

func request(actor: String, payload: Dictionary, action: String) -> Dictionary:
	var e := economy()
	if not FormalLedgerState.exact_fields(payload,["site","good","price"]): return e._result(false,"MALFORMED_GOODS_QUOTE")
	var r := rule(str(payload["site"]),str(payload["good"]))
	if r.is_empty() or actor!=r["firm"]: return e._result(false,"NO_EXPERIMENTAL_SALES_MANDATE")
	if not e._site_selling(r["site"]): return e._result(false,"FIRM_STOPPED_NEW_BUSINESS")
	if typeof(payload["price"])!=TYPE_INT or int(payload["price"])<1 or int(payload["price"])>FormalLedgerState.MAX_AMOUNT: return e._result(false,"INVALID_GOODS_PRICE")
	var version: int = 0
	for q: Dictionary in quotes.values():
		if q["site"]==r["site"] and q["good"]==r["good"]:
			version=maxi(version,int(q["version"])+1)
			if int(q["posted_minute"])/1440==e.day and int(q["version"])>0: return e._result(false,"GOODS_QUOTE_ALREADY_POSTED_TODAY")
	var id: String = "goods_quote:"+r["site"]+":"+r["good"]+":"+str(version)
	quotes[id]={"id":id,"site":r["site"],"good":r["good"],"version":version,"price":payload["price"],"action_id":action,"posted_minute":e._world.game_clock.total_minutes(),"effective_day":e.day+1,"expires_day":e.day+1+int(r["valid_days"])}
	announce_known()
	return {"accepted":true,"reason":"FUTURE_GOODS_QUOTE_PUBLISHED","quote_id":id,"price":payload["price"],"effective_day":e.day+1}

func npc_decisions() -> void:
	var e := economy()
	for r: Dictionary in rules():
		if e.day==0 or e.day%int(r["period"])!=0 or not e._site_selling(r["site"]): continue
		var key: String = r["site"]+"|"+r["good"]
		var delivered: int = 0
		for date: Variant in e._delivery_days.get(key,{}):
			if int(date)>e.day-int(r["window"]): delivered+=int(e._delivery_days[key][date]["quantity"])
		var free: int = maxi(0,int(e._stocks[r["site"]][r["good"]])-e._committed(r["site"],r["good"]))
		var refused: int = 0
		for row: Dictionary in e._request_window.get(key,[]):
			if int(row["day"])>e.day-int(r["window"]): refused+=int(row["cash_refused"])
		var old: int = int(current(r["site"],r["good"])["price"])
		var price: int = old
		var why: String = "FIXED_PRICE_RENEWAL"
		if e.config["local_quotation_experiment"]["npc_enabled"]:
			why="HOLD_INSUFFICIENT_OWN_EVIDENCE"
			if free>maxi(int(r["tight"])*2,delivered*int(r["idle_cover"])):
				price=maxi(1,old-int(r["tick"])); why="OWN_EXCESS_FREE_STOCK"
			elif refused>0: why="HOLD_KNOWN_CASH_REFUSALS"
			elif free<=int(r["tight"]) and delivered>=int(r["volume"]):
				price=old+int(r["tick"]); why="OWN_DELIVERIES_WITH_TIGHT_STOCK"
		var decision := {"policy":"EXPERIMENTAL_LOCAL_QUOTATIONS","reason":why,"free_stock":free,"recent_delivered":delivered,"cash_refused":refused,"window_days":r["window"],"old_price":old,"new_price":price,"authority_basis":r["authority_basis"]}
		e._npc_submit(r["firm"],"post_goods_quote",{"site":r["site"],"good":r["good"],"price":price},key,decision)

func valid_message(m: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(m,["id","actor","kind","candidate","observed_day","delivery_day","source_receipt"]) or not quotes.has(m["candidate"]): return false
	var q: Dictionary = quotes[m["candidate"]]
	var receipts: Dictionary = saved_receipts if not saved_receipts.is_empty() else economy()._receipts
	if not receipts.has(m["source_receipt"]): return false
	var s: Dictionary = receipts[m["source_receipt"]]
	if s.get("kind")!="supplier" or not s.get("candidate") is String or str(s["candidate"]).split("|").size()<2: return false
	var c := economy()._candidate(s.get("candidate",""))
	return s.get("kind")=="supplier" and s["actor"]==m["actor"] and c["site"]==q["site"] and c["good"]==q["good"] and int(s["delivery_day"])<=int(m["observed_day"]) and int(m["observed_day"])*1440>=int(q["posted_minute"]) and int(m["delivery_day"])==int(m["observed_day"])+int(rule(q["site"],q["good"])["notice_days"]) and m["id"]=="notice:"+q["id"]+":"+m["actor"]

func valid_locked_price(order: Dictionary) -> bool:
	var minute: int = int(order["accepted_minute"])
	var q := current(order["seller_site"],order["good"],minute)
	return not q.is_empty() and int(order["price"])==int(q["price"]) and reason(economy()._inventory_key(order["buyer"],order["buyer_site"]),order["seller_site"],order["good"],minute).is_empty()

func restore(value: Variant, native: Dictionary) -> bool:
	quotes.clear(); saved_receipts={}
	if rules().is_empty(): return true if value==null else _fail("Unconfigured experimental quote state")
	if not native.get("receipts") is Dictionary or not native.get("commands") is Dictionary: return _fail("Missing quotation references")
	for m: Variant in native["receipts"].values():
		if not m is Dictionary or not m.get("actor") is String or not m.get("candidate") is String or not FormalLedgerState.valid_amount(m.get("delivery_day")): return _fail("Malformed quotation receipt context")
	saved_receipts=native["receipts"]
	if not value is Dictionary or not FormalLedgerState.exact_fields(value,["format","quotes"]) or value["format"]!="LOCAL_QUOTATIONS_EXPERIMENT_V1" or not value["quotes"] is Dictionary or value["quotes"].size()>4096: return _fail("Invalid local quote history")
	quotes=value["quotes"].duplicate(true)
	var commands: Dictionary = native.get("commands",{})
	for entry: Variant in commands.values():
		if not entry is Dictionary or not entry.get("envelope") is Dictionary or not entry["envelope"].get("command") is Dictionary or not entry.get("result") is Dictionary: return _fail("Malformed quotation action context")
	var used: Dictionary = {}
	for r: Dictionary in rules():
		var rows: Array = []
		for q: Variant in quotes.values():
			if not q is Dictionary or not FormalLedgerState.exact_fields(q,["id","site","good","version","price","action_id","posted_minute","effective_day","expires_day"]): return _fail("Invalid quote shape")
			if q["site"]==r["site"] and q["good"]==r["good"]: rows.append(q)
		rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a["version"])<int(b["version"]))
		if rows.is_empty(): return _fail("Missing opening quote")
		for i: int in rows.size():
			var q: Dictionary=rows[i]
			for f: String in ["price","version","posted_minute","effective_day","expires_day"]:
				if typeof(q[f])!=TYPE_INT or int(q[f])<0: return _fail("Invalid quote integer")
			if int(q["price"])<1 or q["version"]!=i or q["id"]!="goods_quote:"+r["site"]+":"+r["good"]+":"+str(i) or not quotes.has(q["id"]) or int(q["posted_minute"])>economy()._world.game_clock.total_minutes(): return _fail("Invalid quote identity or time")
			if i==0:
				if q["price"]!=economy()._spec["sites"][r["site"]]["prices"][r["good"]] or q["action_id"]!="" or q["posted_minute"]!=0 or q["effective_day"]!=0: return _fail("Invalid opening quote")
			else:
				var entry: Dictionary=commands.get(q["action_id"],{})
				if entry.is_empty() or not entry["result"].get("accepted",false): return _fail("Missing quote command")
				var adopted: Dictionary=entry["result"].duplicate(true)
				adopted.erase("decision")
				var envelope: Dictionary=entry["envelope"]
				var cmd: Dictionary=envelope["command"]
				if envelope["actor"]!=r["firm"] or cmd["kind"]!="post_goods_quote" or cmd["minute"]!=q["posted_minute"] or cmd["payload"]!={"site":r["site"],"good":r["good"],"price":q["price"]} or adopted!={"accepted":true,"reason":"FUTURE_GOODS_QUOTE_PUBLISHED","quote_id":q["id"],"price":q["price"],"effective_day":q["effective_day"]} or int(q["effective_day"])!=int(q["posted_minute"])/1440+1 or int(q["posted_minute"])<=int(rows[i-1]["posted_minute"]): return _fail("Quote action authority or chronology mismatch")
			if int(q["expires_day"])!=int(q["effective_day"])+int(r["valid_days"]): return _fail("Invalid quote expiry")
			used[q["id"]]=true
	if used.size()!=quotes.size(): return _fail("Unconfigured quote scope")
	for entry: Dictionary in commands.values():
		if entry["envelope"]["command"]["kind"]=="post_goods_quote" and entry["result"].get("accepted",false) and not used.has(entry["result"].get("quote_id","")): return _fail("Orphan quote action")
	return true

func _fail(message: String) -> bool:
	error=message
	return false

func snapshot() -> Dictionary:
	return {"format":"LOCAL_QUOTATIONS_EXPERIMENT_V1","quotes":quotes.duplicate(true)}
