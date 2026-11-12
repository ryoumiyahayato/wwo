extends RefCounted
signal market_closed(window: Dictionary)
## Optional local quotation rules and the finite formal resource-market policy.
## R1 owns orders, messages, cash and lots; accepted prices remain immutable.
var host: WeakRef
var quotes: Dictionary = {}
var saved_receipts: Dictionary = {}
var error: String = ""
var market: Dictionary = {} # References, fractional asks, open inquiries and window totals only.

func bind(value: RefCounted) -> void:
	host = weakref(value)

func economy() -> EconomyR1Slice:
	return host.get_ref() as EconomyR1Slice

static func valid_configuration(config: Dictionary, spec: Dictionary) -> bool:
	if config.has("unified_market"):
		var m: Variant = config["unified_market"]
		if not m is Dictionary or not FormalLedgerState.exact_fields(m, ["period_days", "request_days", "eta_permille", "damping_permille", "deadband_permille", "maximum_price"]): return false
		for key: String in m:
			if typeof(m[key]) != TYPE_INT or int(m[key]) < 1 or int(m[key]) > 1000000: return false
		if int(m["eta_permille"]) > 100 or int(m["damping_permille"]) > 1000 or int(m["deadband_permille"]) > 1000: return false
		for firm: Dictionary in spec["firms"].values():
			if firm.get("denomination", FormalLedgerState.DENOMINATION) != config.get("settlement_currency", FormalLedgerState.DENOMINATION): return false
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
	initialize_market()
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
	if market_enabled():
		value["price_milli"] = market_rate(value["seller_site"], value["good"])
		value["goods_amount"] = goods_amount(value["seller_site"], value["good"], int(value["quantity"]))
		value["price_basis"] = "INTEGER_UNIT_CEILING_WITH_LOCKED_LOT_TOTAL"
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
	if not EconomySliceConfig._fields(payload,["site","good","price"],["price_quantity"]): return e._result(false,"MALFORMED_GOODS_QUOTE")
	if market_enabled():
		var site: String = str(payload["site"])
		var key: String = site + "|" + str(payload["good"])
		if not market_sellers().has(key) or (actor != e._owner(site) and not e._manager(actor, e._owner(site))): return e._result(false, "NO_SALES_AUTHORITY")
		if typeof(payload["price"]) != TYPE_INT or int(payload["price"]) < 1 or int(payload["price"]) > int(e.config["unified_market"]["maximum_price"]): return e._result(false, "INVALID_GOODS_PRICE")
		var quantity: Variant = payload.get("price_quantity", 1)
		if typeof(quantity) != TYPE_INT or int(quantity) < 1 or int(quantity) > 1000000 or int(payload["price"]) * 1000 % int(quantity) != 0: return e._result(false, "INVALID_QUOTE_LOT")
		var rate: int = int(payload["price"]) * 1000 / int(quantity)
		if rate < 1000: return e._result(false, "PRICE_BELOW_CURRENT_MILLI_LOT_RULE")
		var terms: Array = market["terms"][key]
		if int(terms.back()["day"]) == e.day + 1: return e._result(false, "GOODS_QUOTE_ALREADY_POSTED_TODAY")
		market["asks"][key] = rate
		terms.append({"day": e.day + 1, "price": (rate + 999) / 1000, "milli": rate})
		return {"accepted": true, "reason": "FUTURE_GOODS_QUOTE_PUBLISHED", "effective_day": e.day + 1, "price": payload["price"], "price_quantity": quantity}
	if payload.has("price_quantity"): return e._result(false, "LOT_QUOTE_REQUIRES_UNIFIED_MARKET")
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

func market_enabled() -> bool:
	return economy().config.has("unified_market")

func market_sellers() -> Dictionary:
	var result: Dictionary = {}
	var e := economy()
	for site: String in e._site_ids():
		for good: String in e._spec["sites"][site]["prices"]: result[site + "|" + good] = int(e._spec["sites"][site]["prices"][good])
	for row: Dictionary in e.config.get("resource_producers", []): result[str(row["actor"]) + "|" + str(row["good"])] = int(row["price"])
	return result

func initialize_market() -> void:
	market = {"references": {}, "asks": {}, "terms": {}, "requests": {}, "trades": {}, "input_costs": {}}
	if not market_enabled(): return
	var e := economy()
	var sellers: Dictionary = market_sellers()
	for key: String in sellers:
		var parts := key.split("|")
		var price: int = sellers[key]
		market["asks"][key] = price * 1000
		market["terms"][key] = [{"day": 0, "price": price}]
		var region: String = e._place(parts[0]) + "|" + parts[1]
		if not market["references"].has(region): market["references"][region] = {"milli": price * 1000, "pressure": 0, "day": 0}

func market_price(site: String, good: String, date: int = -1) -> int:
	# Saved milli terms require this ceiling. Keep one quote lookup.
	return (market_rate(site, good, date) + 999) / 1000

func market_rate(site: String, good: String, date: int = -1) -> int:
	if not market_enabled(): return 0
	if date < 0: date = economy().day
	var terms: Array = market["terms"].get(site + "|" + good, [])
	for index: int in range(terms.size() - 1, -1, -1):
		if int(terms[index]["day"]) <= date: return int(terms[index].get("milli", int(terms[index]["price"]) * 1000))
	return 0

func goods_amount(site: String, good: String, quantity: int, date: int = -1) -> int:
	var rate: int = market_rate(site, good, date)
	if rate <= 0: rate = economy()._price(site, good) * 1000
	var amount: Dictionary = FormalLedgerState.ratio(rate, quantity, 1000)
	return int(amount["quotient"]) + (1 if int(amount["remainder"]) >= 500 else 0) if not amount.is_empty() else -1

func affordable(site: String, good: String, freight: int, cash: int, maximum: int) -> int:
	var rate: int = market_rate(site, good)
	if rate == 0: rate = economy()._price(site, good) * 1000
	# Cash is bounded by the original Ledger; avoid cash*1000 overflow.
	var result: Dictionary = FormalLedgerState.ratio(cash, 1000, maxi(1, rate + freight * 1000))
	var quantity: int = mini(maximum, int(result.get("quotient", 0)))
	if quantity < maximum and goods_amount(site, good, quantity + 1) + (quantity + 1) * freight <= cash: quantity += 1
	return quantity

func market_request(buyer: String, seller: String, good: String, requested: int, unit_cost: int, filled: int, need_by: int, legs: Array[Dictionary], category: String = "") -> void:
	if not market_enabled(): return
	var e := economy()
	var owner: String = e._owner(buyer)
	var account: String = e._account(owner, e._sale_currency(e._owner(seller)))
	var funded: int = mini(maxi(0, requested - filled), int(e._world.ledger_state.available_balance(account)) / maxi(1, unit_cost))
	var budgets: Dictionary = {}
	if not e._budgets.rules.is_empty():
		for component: Dictionary in e._budget_plan(owner, e._sale_currency(e._owner(seller)), good, legs, 1, true, e._price(seller, good)):
			if not component.get("ok", false): funded = 0
			elif component.has("rule_id") and int(component["amount"]) > 0:
				var id: String = component["rule_id"]
				budgets[id] = component["amount"]
				funded = mini(funded, maxi(0, int(e._budgets.rule(id)["limit"]) - int(e._budgets._used.get(id, 0))) / int(component["amount"]))
	# One current unresolved quantity per buyer/good, not one wish per attempted seller.
	var key: String = buyer + "|" + good
	market["requests"][key] = {"buyer": buyer, "region": e._place(buyer) + "|" + good, "quantity": funded, "unit_cost": unit_cost, "until": mini(need_by, e.day + int(e.config["unified_market"]["request_days"])), "budgets": budgets}
	if not category.is_empty(): market["requests"][key]["need_category"] = category

func market_delivery(receipt: Dictionary, order: Dictionary) -> void:
	if not market_enabled() or order["kind"] != "SALE": return
	var e := economy()
	var q: int = int(receipt["quantity"])
	var goods: int = e._receipt_goods_amount(receipt, order)
	var landed: int = (goods + q * e._freight(order["route_legs"])) * 1000
	var delivered: int = int(order["delivered"])
	market["input_costs"][e._destination(order) + "|" + str(order["good"])] = (e._goods_total(order, delivered) + delivered * e._freight(order["route_legs"])) * 1000 / delivered
	var seller_region: String = e._place(order["seller_site"]) + "|" + str(order["good"])
	var buyer_region: String = e._place(e._destination(order)) + "|" + str(order["good"])
	for region: String in [seller_region] if seller_region == buyer_region else [seller_region, buyer_region]:
		if not market["references"].has(region): market["references"][region] = {"milli": landed / q, "pressure": 0, "day": e.day}
		if not market["trades"].has(region): market["trades"][region] = {"quantity": 0, "value": 0}
		market["trades"][region]["quantity"] += q
		market["trades"][region]["value"] += goods * 1000 if region == seller_region else landed

func _known_cost(site: String, good: String) -> int:
	var e := economy()
	if not e._spec["sites"].has(site): return 0
	var acquired: int = int(market["input_costs"].get(site + "|" + good, 0))
	for activity: Dictionary in e._spec["sites"][site]["activities"]:
		if not activity["outputs"].has(good): continue
		var cost: int = 0
		for input: String in activity["materials"]:
			if int(activity["materials"][input]) == 0: continue
			if not market["input_costs"].has(site + "|" + input): return acquired
			cost += int(activity["materials"][input]) * int(market["input_costs"][site + "|" + input])
		for job: Dictionary in e._spec["jobs"].values():
			if job["site_id"] == site:
				cost += int(activity["hours"]) * int(job["wage_per_hour"]) * 1000
		return cost / int(activity["outputs"][good])
	return acquired

static func reference_step(ref: Dictionary, supply: int, demand: int, volume: int, value_milli: int, cfg: Dictionary, elapsed_windows: int = 1) -> Dictionary:
	var result: Dictionary = ref.duplicate()
	var prior: int = int(ref["pressure"])
	# Gaps are quiet observation windows, not timeless pressure. At most ten
	# halvings matter at this precision; do not iterate over the world's age.
	while elapsed_windows > 1 and prior != 0:
		prior = prior * int(cfg["damping_permille"]) / 1000
		elapsed_windows -= 1
	if supply + demand + volume == 0:
		result["pressure"] = prior * int(cfg["damping_permille"]) / 1000
		result["residual"] = 0
		return result
	var raw: int = (demand - supply) * 1000 / maxi(1, demand + supply + volume)
	var pressure: int = (prior * int(cfg["damping_permille"]) + raw * (1000 - int(cfg["damping_permille"]))) / 1000
	result["pressure"] = pressure
	var residual: int = int(ref.get("residual", 0))
	if residual * pressure <= 0 or prior != int(ref["pressure"]): residual = 0
	residual += pressure
	var threshold: int = int(cfg["deadband_permille"])
	if absi(pressure) >= threshold: residual = 0
	elif absi(residual) >= threshold: pressure = residual; residual = 0
	else: pressure = 0
	result["residual"] = residual
	var old: int = int(ref["milli"])
	var target: int = old + old * pressure * int(cfg["eta_permille"]) / 1000000
	if volume > 0: target += (value_milli / volume - old) / 4
	result["milli"] = clampi(target, maxi(1, old * 95 / 100), mini(int(cfg["maximum_price"]) * 1000, old * 105 / 100 + 1))
	return result

func _market_inputs() -> Dictionary:
	var e := economy()
	var supply: Dictionary = {}
	var demand: Dictionary = {}
	var sellers: Dictionary = market_sellers()
	for key: String in sellers:
		var parts := key.split("|")
		var region: String = e._place(parts[0]) + "|" + parts[1]
		if not e._site_selling(parts[0]): continue
		supply[region] = int(supply.get(region, 0)) + e._local_producers.sale_available(parts[0], parts[1])
	var available_budgets: Dictionary = {}
	var appropriations: Dictionary = {}
	var household: Dictionary = {}
	var request_keys: Array = market["requests"].keys()
	request_keys.sort_custom(func(a: String, b: String) -> bool:
		var first: Dictionary = market["requests"][a]
		var second: Dictionary = market["requests"][b]
		if first["buyer"] != second["buyer"]: return first["buyer"] < second["buyer"]
		var category: String = first.get("need_category", "")
		if category != second.get("need_category", ""): return category < str(second.get("need_category", ""))
		if not category.is_empty():
			var first_cost: int = int(first["unit_cost"]) * e._service(str(second["region"]).get_slice("|", 1), category)
			var second_cost: int = int(second["unit_cost"]) * e._service(str(first["region"]).get_slice("|", 1), category)
			if first_cost != second_cost: return first_cost < second_cost
		return a < b)
	for key: String in request_keys:
		var r: Dictionary = market["requests"][key]
		if int(r["until"]) < e.day:
			continue
		var account: String = e._account(e._owner(r["buyer"]))
		if not available_budgets.has(account): available_budgets[account] = e._world.ledger_state.available_balance(account)
		var funded: int = mini(int(r["quantity"]), int(available_budgets[account]) / maxi(1, int(r["unit_cost"])))
		if r.has("need_category"):
			var good: String = str(r["region"]).get_slice("|", 1)
			if not household.has(r["buyer"]): household[r["buyer"]] = e._household_position(r["buyer"], true)
			var uncovered: int = int(household[r["buyer"]].get(r["need_category"], {}).get("uncovered", 0))
			funded = mini(funded, (uncovered + e._service(good, r["need_category"]) - 1) / maxi(1, e._service(good, r["need_category"])))
		for id: String in r["budgets"]:
			var rule_row: Dictionary = e._budgets.rule(id)
			if not appropriations.has(id): appropriations[id] = maxi(0, int(rule_row["limit"]) - int(e._budgets._used.get(id, 0))) if e._world.game_clock.total_minutes() >= int(rule_row["start_minute"]) and e._world.game_clock.total_minutes() < int(rule_row["end_minute"]) else 0
			funded = mini(funded, int(appropriations[id]) / int(r["budgets"][id]))
		available_budgets[account] -= funded * int(r["unit_cost"])
		if r.has("need_category") and household[r["buyer"]].has(r["need_category"]):
			var need: Dictionary = household[r["buyer"]][r["need_category"]]
			need["uncovered"] = maxi(0, int(need["uncovered"]) - funded * e._service(str(r["region"]).get_slice("|", 1), r["need_category"]))
		for id: String in r["budgets"]: appropriations[id] -= funded * int(r["budgets"][id])
		demand[r["region"]] = int(demand.get(r["region"], 0)) + funded
	return {"supply": supply, "demand": demand}

func close_market() -> void:
	if not market_enabled(): return
	var e := economy()
	var cfg: Dictionary = e.config["unified_market"]
	if e.day % int(cfg["period_days"]) != 0: return
	var inputs: Dictionary = _market_inputs()
	var supply: Dictionary = inputs["supply"]
	var demand: Dictionary = inputs["demand"]
	var sellers: Dictionary = market_sellers()
	for key: String in market["requests"].keys():
		if int(market["requests"][key]["until"]) < e.day: market["requests"].erase(key)
	for region: String in market["references"]:
		var ref: Dictionary = market["references"][region]
		var trade: Dictionary = market["trades"].get(region, {"quantity": 0, "value": 0})
		var s: int = int(supply.get(region, 0))
		var d: int = int(demand.get(region, 0))
		var v: int = int(trade["quantity"])
		var old: Dictionary = ref.duplicate()
		ref.merge(reference_step(ref, s, d, v, int(trade["value"]), cfg, maxi(1, (e.day - int(ref["day"])) / int(cfg["period_days"]))), true)
		ref["day"] = e.day
		if market_closed.has_connections(): market_closed.emit({"day": e.day, "region": region, "S": s, "D": d, "V": v, "W_milli": int(trade["value"]) / v if v > 0 else 0, "old_R": old["milli"], "old_pressure": old["pressure"], "R": ref["milli"], "pressure": ref["pressure"], "residual": ref.get("residual", 0)})
	for key: String in sellers:
		var parts := key.split("|")
		var region: String = e._place(parts[0]) + "|" + parts[1]
		var old: int = int(market["asks"][key])
		var target: int = int(market["references"][region]["milli"])
		var cost: int = _known_cost(parts[0], parts[1])
		# Cost affects the seller's target; it never creates a guaranteed margin or a floor.
		if cost > 0: target = (target * 3 + cost) / 4
		var next: int = clampi(old + (target - old) / 4, maxi(1000, old * 95 / 100), mini(int(cfg["maximum_price"]) * 1000, old * 105 / 100 + 1))
		market["asks"][key] = next
		var price: int = maxi(1, (next + 999) / 1000) # Unit ceiling for old integer price limits; invoice uses the lot total.
		if next != market_rate(parts[0], parts[1], e.day + 1):
			var terms: Array = market["terms"][key]
			if int(terms.back()["day"]) == e.day + 1: continue
			terms.append({"day": e.day + 1, "price": price, "milli": next})
	market["trades"].clear()

## Internal observation; no UI access grant and no persisted market authority.
func observation(window: int = 7, include_freight: bool = false) -> Dictionary:
	if not market_enabled(): return {}
	window=clampi(window,1,30)
	var e := economy()
	var inputs: Dictionary = _market_inputs()
	var result: Dictionary = {"day": e.day, "window_days": window, "regions": {}, "sellers": {}, "households": {}, "firms": {}, "waiting": {}, "long_wait": {}, "oldest_wait_days": 0, "past_initial_eta": {}}
	var freight_flows: Dictionary = {}
	var freight_units: Dictionary = e._good_units() if include_freight else {}
	for region: String in market["references"]:
		result["regions"][region] = {"S": inputs["supply"].get(region, 0), "D": inputs["demand"].get(region, 0), "V": 0, "value_milli": 0, "W_milli": 0, "R_milli": market["references"][region]["milli"]}
	for key: String in market_sellers():
		var parts := key.split("|")
		var available: int = e._local_producers.sale_available(parts[0], parts[1])
		var sold := 0
		var origin_place: String = e._place(parts[0])
		var good: String = parts[1]
		var origin: String = origin_place+"|"+good
		var days: Dictionary = e._delivery_days.get(key,{})
		for date: int in range(maxi(0, e.day - window + 1), e.day + 1):
			var destinations: Dictionary = days.get(date,{}).get("destinations",{})
			for place: String in destinations:
				var destination: String = place+"|"+good
				for currency: String in destinations[place]:
					var delivery: Dictionary = destinations[place][currency]
					sold += int(delivery["quantity"])
					for region: String in [origin] if origin == destination else [origin, destination]:
						var row: Dictionary = result["regions"][region]
						row["V"] += int(delivery["quantity"])
						row["value_milli"] += (int(delivery["goods"])+(int(delivery["freight"]) if region!=origin else 0))*1000
					if include_freight and origin != destination:
						var flow_key := origin+"|"+place+"|"+currency
						if not freight_flows.has(flow_key):
							freight_flows[flow_key] = {"from_place_id":origin_place,"to_place_id":place,"good":good,
								"unit":freight_units[good],"denomination":currency,"delivered_quantity":0,"paid_freight":0}
						var flow: Dictionary = freight_flows[flow_key]
						flow["delivered_quantity"] += int(delivery["quantity"])
						flow["paid_freight"] += int(delivery["freight"])
		result["sellers"][key] = {"available": available, "sold": sold, "excess_over_30_day_sales": maxi(0, available - sold * 30 / window), "ask_milli": market_rate(parts[0], parts[1])}
	if include_freight:
		var flows := freight_flows.values()
		for flow: Dictionary in flows:
			flow["average_freight_per_unit"] = float(flow["paid_freight"]) / int(flow["delivered_quantity"])
		result["freight_flows"] = flows
	for row: Dictionary in result["regions"].values():
		if int(row["V"]) > 0: row["W_milli"] = int(row["value_milli"]) / int(row["V"])
	for id: String in e._active_orders:
		var order: Dictionary = e._orders[id]
		var quantity: int = int(order["pending"]) + int(order["transit"])
		var age: int = e.day - int(order["accepted_day"])
		var good: String = order["good"]
		result["waiting"][good] = int(result["waiting"].get(good, 0)) + quantity
		result["oldest_wait_days"] = maxi(age, int(result["oldest_wait_days"]))
		if age >= 14: result["long_wait"][good] = int(result["long_wait"].get(good, 0)) + quantity
		if age > 1 + e._travel_days(order["route_legs"]): result["past_initial_eta"][good] = int(result["past_initial_eta"].get(good, 0)) + quantity
	for actor: String in e._actors:
		if e._actors[actor]["control"] == "automatic": result["households"][actor] = e._totals[actor]["categories"].duplicate(true)
	for firm: String in e._spec["firms"]:
		var overdue: int = 0
		for id: String in e._open_wages_by_employer.get(firm, {}):
			if int(e._wages[id]["due_day"]) < e.day: overdue += int(e._wages[id]["remaining"])
		result["firms"][firm] = {"available_cash": e._world.ledger_state.available_balance(e._account(firm)), "overdue_wages": overdue, "recent_costs": e._costs.view(firm, window)}
	return result

func restore_market(raw: Variant, native: Dictionary) -> bool:
	if not market_enabled(): return raw == null
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw, ["references", "asks", "terms", "requests", "trades", "input_costs"]): return false
	for key: String in raw:
		if not raw[key] is Dictionary: return false
	market = raw.duplicate(true)
	var sellers: Dictionary = market_sellers()
	if market["asks"].keys() != sellers.keys() or market["terms"].keys() != sellers.keys(): return false
	for ref: Variant in market["references"].values():
		if not ref is Dictionary or not EconomySliceConfig._fields(ref, ["milli", "pressure", "day"], ["residual"]) or typeof(ref["milli"]) != TYPE_INT or int(ref["milli"]) < 1 or typeof(ref["pressure"]) != TYPE_INT or absi(int(ref["pressure"])) > 1000 or not FormalLedgerState.valid_amount(ref["day"]) or int(ref["day"]) > int(native["day"]): return false
		if typeof(ref.get("residual", 0)) != TYPE_INT or absi(int(ref.get("residual", 0))) >= int(economy().config["unified_market"]["deadband_permille"]): return false
	for key: String in market["terms"]:
		if not market["terms"][key] is Array or market["terms"][key].is_empty() or market["terms"][key][0] != {"day": 0, "price": sellers[key]} or typeof(market["asks"][key]) != TYPE_INT or int(market["asks"][key]) < 1000: return false
		var previous: int = -1
		for term: Variant in market["terms"][key]:
			if not term is Dictionary or not EconomySliceConfig._fields(term, ["day", "price"], ["milli"]) or not FormalLedgerState.valid_amount(term["day"]) or not FormalLedgerState.valid_amount(term["price"]) or int(term["day"]) <= previous or int(term["day"]) > int(native["day"]) + 1 or int(term["price"]) < 1: return false
			if term.has("milli") and (not FormalLedgerState.valid_amount(term["milli"]) or int(term["milli"]) < 1000 or int(term["price"]) != (int(term["milli"]) + 999) / 1000): return false
			previous = int(term["day"])
	for r: Variant in market["requests"].values():
		if not r is Dictionary or not EconomySliceConfig._fields(r, ["buyer", "region", "quantity", "unit_cost", "until", "budgets"], ["need_category"]) or (not economy()._spec["sites"].has(r["buyer"]) and not economy()._spec["actors"].has(r["buyer"])) or not r["budgets"] is Dictionary: return false
		for key: String in ["quantity", "unit_cost", "until"]:
			if not FormalLedgerState.valid_amount(r[key]): return false
		if r.has("need_category") and (not r["need_category"] is String or not economy()._spec["actors"].has(r["buyer"]) or economy()._service(str(r["region"]).get_slice("|", 1), r["need_category"]) <= 0): return false
		if int(r["unit_cost"]) < 1: return false
		for id: String in r["budgets"]:
			if economy()._budgets.rule(id).is_empty() or not FormalLedgerState.valid_amount(r["budgets"][id]) or int(r["budgets"][id]) < 1: return false
	return true
