extends RefCounted
## Optional sandbox experiment. R1 still owns orders, messages, cash and lots.
## Quote versions are immutable terms, not a second market or price simulator.
const MAX_RULES: int = 11 # Existing ten regional rules plus one terminal-sales research rule.
var host: WeakRef
var quotes: Dictionary = {}
var saved_receipts: Dictionary = {}
# Bounded latest state only; the original R1 command archive is the sole history.
var sales_controls: Dictionary = {}
var restored_sales_boundaries: Array[Dictionary] = []
var error: String = ""

func bind(value: RefCounted) -> void:
	host = weakref(value)

func economy() -> EconomyR1Slice:
	return host.get_ref() as EconomyR1Slice

static func valid_configuration(config: Dictionary, spec: Dictionary) -> bool:
	if not config.has("local_quotation_experiment"): return true
	var cfg: Variant = config["local_quotation_experiment"]
	if not cfg is Dictionary or not EconomySliceConfig._fields(cfg,["basis","npc_enabled","rules"],["renew_same_terms"]) or cfg["basis"] != "GENERATED_SIMULATION_ASSUMPTION_LOCAL_QUOTATIONS" or not cfg["npc_enabled"] is bool or not cfg["rules"] is Array or cfg["rules"].is_empty() or cfg["rules"].size()>MAX_RULES: return false
	if cfg.has("renew_same_terms") and not cfg.renew_same_terms is bool:return false
	var seen: Dictionary = {}
	for row: Variant in cfg["rules"]:
		if not row is Dictionary or not EconomySliceConfig._fields(row,["firm","site","good","period","window","tick","tight","volume","idle_cover","notice_days","valid_days","authority_basis"],["renew_same_terms"]): return false
		if row.has("renew_same_terms") and not row.renew_same_terms is bool:return false
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
	var why := "GOODS_NEW_SALES_PAUSED" if sales_paused(value["seller_site"],value["good"]) else reason(observer,value["seller_site"],value["good"])
	value["published_quote_id"]=q.get("id","")
	value["quote_expires_minute"]=int(q["expires_day"])*1440 if not q.is_empty() else null
	value["quote_id"]+="|"+str(q.get("id","unknown"))
	value["price"]=q.get("price",null)
	if not why.is_empty(): value["quantity"]=0; value["transport_quantity"]=0; value["reason"]=why
	return value

func managed_authority(actor: String, payload: Dictionary, minute: int) -> bool:
	var e := economy()
	if not FormalLedgerState.exact_fields(payload,["firm","site","good","price","authorization_context"]): return false
	for field: String in ["firm","site","good"]:
		if not payload[field] is String: return false
	if not payload["authorization_context"] is Dictionary or typeof(payload["price"])!=TYPE_INT or int(payload["price"])<1 or int(payload["price"])>FormalLedgerState.MAX_AMOUNT: return false
	var r := rule(payload["site"],payload["good"])
	if r.is_empty() or r["firm"]!=payload["firm"] or actor==r["firm"] or not e._manager_at(actor,r["firm"],minute): return false
	var organization: String = e._spec["firms"][r["firm"]].get("host_organization_id","")
	var context: Dictionary = payload["authorization_context"]
	if organization.is_empty() or context.get("person_id")!=actor or context.get("represented_organization_id")!=organization or e._world.authorization_check==null: return false
	var proof := e._world.authorization_check.resolve_authority(context,"economy.goods.quote",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,r["firm"],e._place(r["site"]),"goods:"+r["good"],float(payload["price"]),minute/60)
	return proof.get("status")==AuthorizationCheck.ALLOWED


func sales_paused(site: String, good: String) -> bool:
	return bool(sales_controls.get(site+"|"+good,{}).get("paused",false))

func sales_control_authority(actor: String, payload: Dictionary, minute: int) -> bool:
	if not FormalLedgerState.exact_fields(payload,["firm","site","good","paused","authorization_context"]) or not payload["paused"] is bool: return false
	for field: String in ["firm","site","good"]:
		if not payload[field] is String: return false
	var q := current(payload["site"],payload["good"],minute)
	if q.is_empty(): return false
	var proof := payload.duplicate(true)
	proof.erase("paused"); proof["price"]=q["price"]
	return managed_authority(actor,proof,minute)

func request_sales_control(actor: String, payload: Dictionary, action: String) -> Dictionary:
	var e := economy()
	var minute: int=e._world.game_clock.total_minutes()
	if not sales_control_authority(actor,payload,minute): return e._result(false,"NO_MANAGED_GOODS_SALES_AUTHORITY")
	var q := current(payload["site"],payload["good"],minute)
	if not payload["paused"]:
		if not e._site_selling(payload["site"]): return e._result(false,"FIRM_STOPPED_NEW_BUSINESS")
		if minute>=int(q["expires_day"])*1440: return e._result(false,"GOODS_QUOTE_EXPIRED")
	var row := {"action_id":action,"paused":payload["paused"],"effective_minute":minute,"adoption_sequence":e._commands.size(),"order_cursor":e.next_order,"quote_id":q["id"]}
	sales_controls[payload["site"]+"|"+payload["good"]]=row
	var result := row.duplicate(true)
	result.merge({"accepted":true,"reason":"GOODS_NEW_SALES_PAUSED" if payload["paused"] else "GOODS_NEW_SALES_RESUMED","site":payload["site"],"good":payload["good"]})
	return result

# The order cursor is the original R1 acceptance boundary, including same-minute
# orders. No current flag is used to invalidate a previously accepted sale.
func valid_sale_boundary(order: Dictionary) -> bool:
	var number: int=int(str(order["id"]).trim_prefix("order:"))
	var paused := false
	for row: Dictionary in restored_sales_boundaries:
		if row["site"]==order["seller_site"] and row["good"]==order["good"] and int(row["order_cursor"])<=number:
			paused=row["paused"]
	return not paused

func valid_supply_acceptance(site: String, good: String, minute: int, result: Dictionary) -> bool:
	# New contract acceptances carry their R1 journal position. Legacy accepted
	# contracts predate the optional feature and keep their original meaning.
	if result.has("sales_adoption_sequence") and not FormalLedgerState.valid_amount(result["sales_adoption_sequence"]): return false
	var sequence: int=int(result.get("sales_adoption_sequence",-1))
	var paused := false
	for row: Dictionary in restored_sales_boundaries:
		if row["site"]!=site or row["good"]!=good: continue
		if int(row["effective_minute"])<minute or (int(row["effective_minute"])==minute and sequence>=0 and int(row["adoption_sequence"])<sequence): paused=row["paused"]
	return not paused

func _restore_sales_controls(value: Dictionary, native: Dictionary) -> bool:
	var controls: Variant=value.get("sales_controls",{})
	if not controls is Dictionary or controls.size()>MAX_RULES: return _fail("Invalid bounded sales controls")
	var expected: Dictionary={}
	var sequences: Dictionary={}
	for id: String in native["commands"]:
		var entry: Dictionary=native["commands"][id]
		var cmd: Dictionary=entry["envelope"]["command"]
		if cmd.get("kind")!="set_managed_goods_sales" or not entry["result"].get("accepted",false): continue
		if not FormalLedgerState.valid_amount(cmd.get("minute")) or not cmd.get("payload") is Dictionary or cmd.get("action_id")!=id: return _fail("Malformed sales control command")
		var r: Dictionary=entry["result"]
		var p: Dictionary=cmd.get("payload",{})
		if not FormalLedgerState.exact_fields(r,["action_id","paused","effective_minute","adoption_sequence","order_cursor","quote_id","accepted","reason","site","good"]) or not r.get("paused") is bool or not sales_control_authority(entry["envelope"]["actor"],p,cmd["minute"]): return _fail("Sales control lost original quote authority")
		for key: String in ["effective_minute","adoption_sequence","order_cursor"]:
			if not FormalLedgerState.valid_amount(r[key]): return _fail("Invalid sales control adoption boundary")
		var q := current(p["site"],p["good"],cmd["minute"])
		if r["action_id"]!=id or r["paused"]!=p["paused"] or r["site"]!=p["site"] or r["good"]!=p["good"] or r["effective_minute"]!=cmd["minute"] or r["quote_id"]!=q["id"] or r["reason"]!=("GOODS_NEW_SALES_PAUSED" if p["paused"] else "GOODS_NEW_SALES_RESUMED"): return _fail("Sales control differs from its adopted command")
		if int(r["adoption_sequence"])>=native["commands"].size() or sequences.has(r["adoption_sequence"]) or int(r["order_cursor"])<1 or int(r["order_cursor"])>int(native.get("next_order",0)): return _fail("Invalid sales control command or order cursor")
		if not p["paused"] and int(cmd["minute"])>=int(q["expires_day"])*1440: return _fail("Sales resumed with expired quote")
		# This validates the persisted boundary against original order times. The
		# explicit cursor resolves orders accepted at the same minute.
		var cursor: int=int(r["order_cursor"])
		var prior: Dictionary=native.get("orders",{}).get("order:"+str(cursor-1),{})
		var following: Dictionary=native.get("orders",{}).get("order:"+str(cursor),{})
		if (not prior.is_empty() and int(prior["accepted_minute"])>int(cmd["minute"])) or (not following.is_empty() and int(following["accepted_minute"])<int(cmd["minute"])): return _fail("Sales control boundary contradicts order chronology")
		sequences[r["adoption_sequence"]]=true
		restored_sales_boundaries.append(r.duplicate(true))
	restored_sales_boundaries.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a["adoption_sequence"])<int(b["adoption_sequence"]))
	var last_minute := -1
	var last_cursor := 1
	for r: Dictionary in restored_sales_boundaries:
		if int(r["effective_minute"])<last_minute or int(r["order_cursor"])<last_cursor: return _fail("Sales control adoption chronology reversed")
		last_minute=int(r["effective_minute"]); last_cursor=int(r["order_cursor"])
		var row := r.duplicate(true)
		for key: String in ["accepted","reason","site","good"]: row.erase(key)
		expected[r["site"]+"|"+r["good"]]=row
	if controls!=expected: return _fail("Latest sales controls differ from original R1 commands")
	sales_controls=controls.duplicate(true)
	return true

func request_managed(actor: String, payload: Dictionary, action: String) -> Dictionary:
	if not managed_authority(actor,payload,economy()._world.game_clock.total_minutes()): return economy()._result(false,"NO_MANAGED_GOODS_QUOTE_AUTHORITY")
	return _publish(payload,action)

func request(actor: String, payload: Dictionary, action: String) -> Dictionary:
	var e := economy()
	if not EconomySliceConfig._fields(payload,["site","good","price"],["renewal_of"]): return e._result(false,"MALFORMED_GOODS_QUOTE")
	var r := rule(str(payload["site"]),str(payload["good"]))
	if r.is_empty() or actor!=r["firm"]: return e._result(false,"NO_EXPERIMENTAL_SALES_MANDATE")
	return _publish(payload,action)

func _publication_effective_day(payload: Dictionary,minute: int) -> int:
	if not payload.has("renewal_of"):return minute/1440+1
	if not rule(payload.site,payload.good).get("renew_same_terms",economy().config.get("local_quotation_experiment",{}).get("renew_same_terms",false)) or not payload.renewal_of is String:return -1
	var previous: Dictionary=current(payload.site,payload.good,minute)
	if previous.is_empty() or previous.id!=payload.renewal_of or previous.price!=payload.price or int(previous.expires_day)<=minute/1440:return -1
	return int(previous.expires_day)

func _publish(payload: Dictionary, action: String) -> Dictionary:
	var e := economy()
	var r := rule(str(payload["site"]),str(payload["good"]))
	if not e._site_selling(r["site"]): return e._result(false,"FIRM_STOPPED_NEW_BUSINESS")
	if typeof(payload["price"])!=TYPE_INT or int(payload["price"])<1 or int(payload["price"])>FormalLedgerState.MAX_AMOUNT: return e._result(false,"INVALID_GOODS_PRICE")
	var effective: int=_publication_effective_day(payload,e._world.game_clock.total_minutes())
	if effective<0:return e._result(false,"INVALID_SAME_TERMS_RENEWAL_SOURCE")
	var version: int = 0
	for q: Dictionary in quotes.values():
		if q["site"]==r["site"] and q["good"]==r["good"]:
			version=maxi(version,int(q["version"])+1)
			if int(q["posted_minute"])/1440==e.day and int(q["version"])>0: return e._result(false,"GOODS_QUOTE_ALREADY_POSTED_TODAY")
	var id: String = "goods_quote:"+r["site"]+":"+r["good"]+":"+str(version)
	quotes[id]={"id":id,"site":r["site"],"good":r["good"],"version":version,"price":payload["price"],"action_id":action,"posted_minute":e._world.game_clock.total_minutes(),"effective_day":effective,"expires_day":effective+int(r["valid_days"])}
	announce_known()
	return {"accepted":true,"reason":"FUTURE_GOODS_QUOTE_PUBLISHED","quote_id":id,"price":payload["price"],"effective_day":effective}

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
		for row: Dictionary in e._request_pressure_records(r["site"],r["good"]):
			if int(row["day"])>e.day-int(r["window"]): refused+=int(row["cash_refused"])
		var active: Dictionary=current(r["site"],r["good"])
		var old: int = int(active["price"])
		var price: int = old
		var why: String = "FIXED_PRICE_RENEWAL"
		var public_index: Dictionary={}
		if e.config["local_quotation_experiment"]["npc_enabled"] and e.firm_manager_at(r["firm"],e._world.game_clock.total_minutes())!=e._world.player_state.player_id():
			var reference: RefCounted=e._world.economy_state.reference_market
			if reference!=null and r.good=="grain":public_index=reference.received_bulletin(r.firm,"wheat",e.day)
			why="HOLD_INSUFFICIENT_OWN_EVIDENCE"
			if free>maxi(int(r["tight"])*2,delivered*int(r["idle_cover"])):
				price=maxi(1,old-int(r["tick"])); why="OWN_EXCESS_FREE_STOCK"
			elif refused>0: why="HOLD_KNOWN_CASH_REFUSALS"
			elif free<=int(r["tight"]) and delivered>=int(r["volume"]):
				price=old+int(r["tick"]); why="OWN_DELIVERIES_WITH_TIGHT_STOCK"
			# Explicit global research only. This public delayed index is not a quote,
			# new supplier, currency conversion or permission to buy aggregate cover.
			if not public_index.is_empty() and free<=maxi(2,int(r.tight)*3) and delivered>0 and refused==0:
				if not public_index.is_empty():
					var opening: int=int(e._spec.sites[r.site].prices[r.good])
					var target: int=maxi(1,int(round(float(opening)*float(public_index.index)/100.0)))
					if target>old:price=old+int(r.tick);why="DELAYED_PUBLIC_INDEX_AND_OWN_SALES"
					elif target<old:price=maxi(1,old-int(r.tick));why="DELAYED_PUBLIC_INDEX_AND_OWN_SALES"
		var terms: Dictionary={"site":r["site"],"good":r["good"],"price":price}
		if r.get("renew_same_terms",e.config["local_quotation_experiment"].get("renew_same_terms",false)) and price==old:
			var pending: bool=false
			for future: Dictionary in quotes.values():
				if future.site==r.site and future.good==r.good and future.price==price and int(future.effective_day)>e.day and int(future.version)>int(active.version):pending=true;break
			if pending or int(active.expires_day)>e.day+int(r.period)+int(r.notice_days):continue
			if int(active.expires_day)>e.day:
				terms["renewal_of"]=active.id;why="SAME_TERMS_EXPIRY_RENEWAL"
		var decision := {"policy":"EXPERIMENTAL_LOCAL_QUOTATIONS","reason":why,"free_stock":free,"recent_delivered":delivered,"cash_refused":refused,"window_days":r["window"],"old_price":old,"new_price":price,"authority_basis":r["authority_basis"]}
		if not public_index.is_empty():decision["public_reference_bulletin"]=public_index
		e._npc_submit(r["firm"],"post_goods_quote",terms,key,decision)

func valid_message(m: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(m,["id","actor","kind","candidate","observed_day","delivery_day","source_receipt"]) or not quotes.has(m["candidate"]): return false
	var q: Dictionary = quotes[m["candidate"]]
	var receipts: Dictionary = saved_receipts if not saved_receipts.is_empty() else economy()._receipts
	if not receipts.has(m["source_receipt"]): return false
	var s: Dictionary = receipts[m["source_receipt"]]
	if s.get("kind")!="supplier" or not s.get("candidate") is String or str(s["candidate"]).split("|").size()<2: return false
	var c := economy()._candidate(s.get("candidate",""))
	return s.get("kind")=="supplier" and s["actor"]==m["actor"] and c["site"]==q["site"] and c["good"]==q["good"] and int(s["delivery_day"])<=int(m["observed_day"]) and int(m["observed_day"])>=int(q["posted_minute"])/1440 and int(m["delivery_day"])==int(m["observed_day"])+int(rule(q["site"],q["good"])["notice_days"]) and m["id"]=="notice:"+q["id"]+":"+m["actor"]

func valid_locked_price(order: Dictionary) -> bool:
	var minute: int = int(order["accepted_minute"])
	var q := current(order["seller_site"],order["good"],minute)
	return not q.is_empty() and int(order["price"])==int(q["price"]) and reason(economy()._inventory_key(order["buyer"],order["buyer_site"]),order["seller_site"],order["good"],minute).is_empty()

func restore(value: Variant, native: Dictionary) -> bool:
	quotes.clear(); saved_receipts={}; sales_controls={}; restored_sales_boundaries=[]
	if rules().is_empty(): return true if value==null else _fail("Unconfigured experimental quote state")
	if not native.get("receipts") is Dictionary or not native.get("commands") is Dictionary: return _fail("Missing quotation references")
	for m: Variant in native["receipts"].values():
		if not m is Dictionary or not m.get("actor") is String or not m.get("candidate") is String or not FormalLedgerState.valid_amount(m.get("delivery_day")): return _fail("Malformed quotation receipt context")
	saved_receipts=native["receipts"]
	if not value is Dictionary or not EconomySliceConfig._fields(value,["format","quotes"],["sales_controls"]) or value["format"]!="LOCAL_QUOTATIONS_EXPERIMENT_V1" or not value["quotes"] is Dictionary or value["quotes"].size()>4096: return _fail("Invalid local quote history")
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
				if not cmd.get("payload") is Dictionary:return _fail("Invalid quotation command payload")
				var expected_payload: Dictionary={"site":r["site"],"good":r["good"],"price":q["price"]}
				if cmd["payload"].has("renewal_of"):expected_payload["renewal_of"]=cmd["payload"].renewal_of
				var legacy: bool = envelope["actor"]==r["firm"] and cmd["kind"]=="post_goods_quote" and cmd["payload"]==expected_payload
				var managed: bool = cmd["kind"]=="post_managed_goods_quote" and managed_authority(envelope["actor"],cmd["payload"],cmd["minute"]) and cmd["payload"].get("site")==r["site"] and cmd["payload"].get("good")==r["good"] and cmd["payload"].get("price")==q["price"]
				if (not legacy and not managed) or cmd["minute"]!=q["posted_minute"] or adopted!={"accepted":true,"reason":"FUTURE_GOODS_QUOTE_PUBLISHED","quote_id":q["id"],"price":q["price"],"effective_day":q["effective_day"]} or int(q["effective_day"])!=_publication_effective_day(cmd["payload"],int(q["posted_minute"])) or int(q["posted_minute"])<=int(rows[i-1]["posted_minute"]): return _fail("Quote action authority or chronology mismatch")
			if int(q["expires_day"])!=int(q["effective_day"])+int(r["valid_days"]): return _fail("Invalid quote expiry")
			used[q["id"]]=true
	if used.size()!=quotes.size(): return _fail("Unconfigured quote scope")
	for entry: Dictionary in commands.values():
		if entry["envelope"]["command"]["kind"] in ["post_goods_quote","post_managed_goods_quote"] and entry["result"].get("accepted",false) and not used.has(entry["result"].get("quote_id","")): return _fail("Orphan quote action")
	return _restore_sales_controls(value,native)

func _fail(message: String) -> bool:
	error=message
	return false

func snapshot() -> Dictionary:
	var result := {"format":"LOCAL_QUOTATIONS_EXPERIMENT_V1","quotes":quotes.duplicate(true)}
	if not sales_controls.is_empty(): result["sales_controls"]=sales_controls.duplicate(true)
	return result
