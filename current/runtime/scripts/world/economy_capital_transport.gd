class_name EconomyCapitalTransport
extends RefCounted
## Contracts for indivisible equipment. SharedTransport owns all physical entries,
## vehicles, handling work and node uses. CapitalFormation alone owns the asset.
var tasks: Dictionary = {}
var error: String = ""
var _ref: WeakRef

func bind(e: RefCounted) -> void: _ref = weakref(e)
func economy() -> RefCounted: return _ref.get_ref()
func configuration() -> Dictionary: return economy().config.get("capital_transport", {})
func offer(id: String) -> Dictionary:
	for row: Dictionary in configuration().get("offers", []):
		if row["id"] == id: return row
	return {}

static func valid_configuration(settings: Dictionary) -> bool:
	if not settings.has("capital_transport"): return true
	var c: Variant = settings["capital_transport"]
	if not c is Dictionary or not FormalLedgerState.exact_fields(c,["basis","loads","offers"]) or c["basis"] != "EXPLICIT_DEVELOPMENT_UNIQUE_ASSET_CARRIAGE" or not c["loads"] is Array or not c["offers"] is Array or c["loads"].size()>16 or c["offers"].size()>32: return false
	var ids: Dictionary = {}
	for r: Variant in c["loads"]:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["asset_type","unit","numerator","denominator","handling_units","basis"]) or not r["asset_type"] is String or ids.has(r["asset_type"]) or not r["unit"] is String or r["unit"].is_empty() or r["basis"]!="SIMULATION_ENGINEERING_ASSUMPTION_NOT_HISTORICAL_TONNAGE": return false
		for k: String in ["numerator","denominator","handling_units"]:
			if not FormalLedgerState.valid_amount(r[k]) or r[k]<1 or r[k]>1000: return false
		ids[r["asset_type"]]=true
	ids.clear()
	for r: Variant in c["offers"]:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","source_site","target_site","asset_type","legs","known_to","valid_from","valid_until","denomination","basis"]) or not r["id"] is String or ids.has(r["id"]) or not r["source_site"] is String or not r["target_site"] is String or not r["asset_type"] is String or not r["legs"] is Array or r["legs"].is_empty() or r["legs"].size()>8 or not r["known_to"] is Array or not FormalLedgerState.currency_id(r["denomination"]) or not FormalLedgerState.valid_amount(r["valid_from"]) or not FormalLedgerState.valid_amount(r["valid_until"]) or r["valid_until"]<=r["valid_from"] or r["basis"]!="EXPLICIT_DEVELOPMENT_CARRIER_COMMITMENT_PAY_ON_UNLOAD": return false
		for leg: Variant in r["legs"]:
			if not leg is Dictionary or not FormalLedgerState.exact_fields(leg,["edge_id","carrier","fee"]) or not leg["edge_id"] is String or not leg["carrier"] is String or not FormalLedgerState.valid_amount(leg["fee"]) or leg["fee"]>10000: return false
		ids[r["id"]]=true
	return true

func load_rule(asset: String) -> Dictionary:
	var a: Dictionary = economy()._capital.assets.get(asset,{})
	for r: Dictionary in configuration().get("loads",[]):
		if r["asset_type"]==a.get("asset_type"): return r
	return {}

func weight(asset: String, unit: String) -> float:
	var r := load_rule(asset)
	return float(r["numerator"])/float(r["denominator"]) if r.get("unit")==unit else -1.0

func handling_units(asset: String) -> int: return int(load_rule(asset).get("handling_units",0))

func for_trade(trade: String) -> Dictionary:
	for t: Dictionary in tasks.values():
		if t["trade_id"]==trade: return t
	return {}

func compatible(o: Dictionary, asset: String, minute: int, check_window: bool=true) -> bool:
	var e := economy()
	if o.is_empty() or load_rule(asset).is_empty() or e._capital.assets[asset]["asset_type"]!=o["asset_type"] or not e._spec["sites"].has(o["source_site"]) or not e._spec["sites"].has(o["target_site"]): return false
	if check_window and (minute<o["valid_from"] or minute>=o["valid_until"]): return false
	var place: String=e._place(o["source_site"])
	var seen: Dictionary={}
	for leg: Dictionary in o["legs"]:
		var edge: Dictionary=e._all_routes().get(leg["edge_id"],{})
		var b: Dictionary=e._shared.bindings.get(leg["edge_id"],{})
		if edge.get("basis")!="HOST_LINK" or not e._cargo_edge_valid(edge) or edge.get("from_place_id")!=place or edge.get("carrier")!=leg["carrier"] or seen.has(leg["edge_id"]) or not b.has("node_resources") or not b.has("window_minutes") or weight(asset,b["weight_unit"])<=0 or not e._spec["firms"].has(leg["carrier"]) or e._account(leg["carrier"],o["denomination"]).is_empty(): return false
		for key: String in ["origin_handling","origin_berth","destination_handling","destination_berth","destination_storage"]:
			var f: Dictionary=e._shared.facilities[b["node_resources"][key]]
			if o["asset_type"] not in f.get("asset_types",[]) or weight(asset,f["unit"])<=0: return false
		if check_window and not e._shared._has_window(b,minute): return false
		place=edge["to_place_id"];seen[leg["edge_id"]]=true
	return place==e._place(o["target_site"]) and place!=e._place(o["source_site"])

func routes(asset: String, source: String, target: String, buyer: String, minute: int=-1) -> Array[Dictionary]:
	if minute<0: minute=economy()._world.game_clock.total_minutes()
	var result: Array[Dictionary]=[]
	for o: Dictionary in configuration().get("offers",[]):
		if o["source_site"]==source and o["target_site"]==target and buyer in o["known_to"] and compatible(o,asset,minute): result.append(o.duplicate(true))
	return result

func commission_check(actor: String, trade: Dictionary, o: Dictionary) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if trade["state"]!="ACCEPTED" or not for_trade(trade["id"]).is_empty() or tasks.size()>=256 or o not in routes(trade["asset_id"],trade["source_site"],trade["target_site"],trade["buyer"]): return reject("NO_KNOWN_COMPATIBLE_CARRIER_CONTRACT_OR_ALREADY_COMMISSIONED")
	var total:=0
	for leg: Dictionary in o["legs"]:
		if leg["carrier"]==trade["buyer"] and leg["fee"]!=0: return reject("INTERNAL_CARRIAGE_CANNOT_CREATE_EXTERNAL_REVENUE")
		total+=int(leg["fee"])
	var proof: Dictionary=e._capital.move_permission(actor,trade["buyer"],"freight",total)
	var pay: Dictionary=e._capital.move_permission(actor,trade["buyer"],"pay",total)
	var plan: Dictionary=e._budgets.plan(trade["buyer"],o["denomination"],"capital_freight",total,now)
	if not proof["ok"] or not pay["ok"] or not plan.get("ok",false) or not plan.has("rule_id") or plan["root_authority"]!=proof["source"]["id"]: return reject("SEPARATE_CAPITAL_FREIGHT_AUTHORITY_AND_BUDGET_REQUIRED")
	if e._world.ledger_state.available_balance(e._account(trade["buyer"],o["denomination"]))<total: return reject("ACTUAL_FREIGHT_CASH_REQUIRED")
	return {"accepted":true,"reason":"ORIGINAL_FREIGHT_COMMISSION_CHECK_READY","total":total,"authority":proof,"payment_authority":pay,"plan":plan}

func request(actor: String, kind: String, p: Dictionary, action: String) -> Dictionary:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if kind=="commission_capital_transport":
		if not FormalLedgerState.exact_fields(p,["trade_id","offer_id"]) or not e._capital.resale_trades.has(p["trade_id"]): return reject("UNKNOWN_CAPITAL_TRADE")
		var trade: Dictionary=e._capital.resale_trades[p["trade_id"]]
		var o:=offer(p["offer_id"])
		var check:=commission_check(actor,trade,o)
		if not check["accepted"]: return check
		var total: int=check["total"];var proof: Dictionary=check["authority"];var pay: Dictionary=check["payment_authority"];var plan: Dictionary=check["plan"]
		var id:="capital_transport:"+action
		if total>0 and not e._world.ledger_state.reserve(id,e._account(trade["buyer"],o["denomination"]),total): return reject("ACTUAL_FREIGHT_CASH_REQUIRED")
		var plans: Array[Dictionary]=[plan]
		if not e._budgets.commit(id,plans):
			if total>0: e._world.ledger_state.release(id,total)
			return reject("FREIGHT_BUDGET_COMMITMENT_FAILED")
		tasks[id]={"id":id,"asset_id":trade["asset_id"],"trade_id":trade["id"],"offer_id":o["id"],"actor":actor,"action_id":action,"minute":now,"payer":trade["buyer"],"authority":proof,"payment_authority":pay,"dispatch_action":"","dispatch_authority":{},"dispatch_minute":-1,"stage":"COMMISSIONED","leg_index":0,"quantity":1,"place_id":e._place(trade["source_site"]),"loading_end_minute":-1,"arrival_minute":-1,"unloading_end_minute":-1,"completed_legs":[],"paid":0,"total_fee":total,"reason":"WAITING_SELLER_DISPATCH_AUTHORITY"}
		return {"accepted":true,"reason":"FREIGHT_RESERVED_SELLER_TITLE_RETAINED","transport_id":id}
	if kind!="dispatch_capital_transport": return reject("UNKNOWN_CAPITAL_TRANSPORT_ACTION")
	if not FormalLedgerState.exact_fields(p,["transport_id"]) or not tasks.has(p["transport_id"]): return reject("UNKNOWN_CAPITAL_TRANSPORT")
	var t:=tasks[p["transport_id"]] as Dictionary
	var trade: Dictionary=e._capital.resale_trades[t["trade_id"]]
	var state: Dictionary=e._capital.asset_state(t["asset_id"])
	var proof: Dictionary=e._capital.move_permission(actor,trade["seller"],"handover",0)
	if t["stage"]!="COMMISSIONED" or not proof["ok"] or state["owner"]!=trade["seller"] or state["status"]!="DETACHED" or state["site_id"]!=trade["source_site"]: return reject("SELLER_DISPATCH_AUTHORITY_OR_DETACHED_CUSTODY_REQUIRED")
	t["dispatch_action"]=action;t["dispatch_authority"]=proof;t["dispatch_minute"]=now;t["stage"]="WAITING";t["reason"]="WAITING_ACTUAL_LOADING_WINDOW"
	return {"accepted":true,"reason":"DISPATCH_AUTHORIZED_ACTUAL_RESOURCES_REQUIRED","transport_id":t["id"]}

func needed(edge: String, arrival: bool) -> int:
	var total:=0
	for t: Dictionary in tasks.values():
		var o:=offer(t["offer_id"])
		if t["leg_index"]>=o["legs"].size() or o["legs"][t["leg_index"]]["edge_id"]!=edge: continue
		if (arrival and t["stage"] in ["LOADING","TRANSIT","WAITING_UNLOAD"]) or (not arrival and t["stage"]=="WAITING"): total+=handling_units(t["asset_id"])
	return total

func advance() -> bool:
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	for t: Dictionary in tasks.values():
		var o:=offer(t["offer_id"])
		if t["stage"] in ["COMMISSIONED","AWAITING_RECIPIENT","DELIVERED"]: continue
		var leg: Dictionary=o["legs"][t["leg_index"]]
		var b: Dictionary=e._shared.bindings[leg["edge_id"]]
		var load:={"asset_id":t["asset_id"]}
		if t["stage"]=="LOADING" and now>=t["loading_end_minute"]: t["stage"]="TRANSIT";t["place_id"]="";t["reason"]="ACTUAL_TRANSIT"
		if t["stage"]=="TRANSIT" and now>=t["arrival_minute"]: t["stage"]="WAITING_UNLOAD";t["place_id"]=e._all_routes()[leg["edge_id"]]["to_place_id"]
		if t["stage"] in ["WAITING_UNLOAD","UNLOADING"]:
			var arrived: bool=e._shared.arrive(t,{"route_legs":o["legs"],"asset_id":t["asset_id"]})
			if not arrived:
				t["reason"]=e._shared.arrival_wait_reason(t,{"route_legs":o["legs"],"asset_id":t["asset_id"]});continue
			var payment: String="capital_freight_payment:"+t["id"]+":"+str(t["leg_index"])
			if leg["fee"]>0:
				var legs:=payment_legs(t,t["leg_index"])
				if not e._world.ledger_state.batch_payment(payment,legs,now,{t["id"]:leg["fee"]}): return false
			t["paid"]+=int(leg["fee"])
			assert(e._budgets.settle(payment,t["id"],t["paid"],0,maxi(1,t["total_fee"])))
			t["completed_legs"].append({"leg_index":t["leg_index"],"minute":now,"payment_id":payment})
			if t["leg_index"]+1==o["legs"].size(): t["stage"]="AWAITING_RECIPIENT";t["reason"]="BUYER_WORKED_RECEIPT_REQUIRED";continue
			t["leg_index"]+=1;t["stage"]="WAITING";t["loading_end_minute"]=-1;t["arrival_minute"]=-1;t["unloading_end_minute"]=-1
			leg=o["legs"][t["leg_index"]];b=e._shared.bindings[leg["edge_id"]]
		if t["stage"]=="WAITING":
			if not e._shared.enter(t["id"],t["leg_index"],leg["edge_id"],load,1): t["reason"]=waiting_reason(t);continue
			var entry: Dictionary=e._shared.entries["economy_entry:"+t["id"]+":"+str(t["leg_index"])]
			t["stage"]="LOADING";t["loading_end_minute"]=entry["loading_end_minute"];t["arrival_minute"]=entry["arrival_minute"];t["reason"]="ACTUAL_LOADING"
	return true

func payment_legs(t: Dictionary, index: int) -> Array[Dictionary]:
	var o:=offer(t["offer_id"]);var leg:=o["legs"][index] as Dictionary
	return [{"transaction_id":"capital_freight_payment:"+str(t["id"])+":"+str(index),"from_account_id":economy()._account(t["payer"],o["denomination"]),"to_account_id":economy()._account(leg["carrier"],o["denomination"]),"amount":leg["fee"],"kind":"freight","reference_id":t["id"]}]

func delivered(trade: String) -> void:
	var t:=for_trade(trade)
	assert(t.get("stage")=="AWAITING_RECIPIENT")
	t["stage"]="DELIVERED";t["reason"]=""
	economy()._shared.release_storage(t["id"],{"asset_id":t["asset_id"]},1,"capital_delivery:"+trade)

func custody(asset: String, minute: int) -> Dictionary:
	var e:=economy();var latest: Dictionary={};var entered:=-1
	for entry: Dictionary in e._shared.entries.values():
		if entry.get("asset_id")==asset and entry["minute"]<=minute and entry["minute"]>=entered:
			latest=entry;entered=entry["minute"]
	if latest.is_empty(): return {}
	var t:=tasks[latest["shipment_id"]] as Dictionary
	var trade: Dictionary=e._capital.resale_trades[t["trade_id"]]
	if trade["delivered_minute"]>=0 and trade["delivered_minute"]<=minute: return {}
	var b: Dictionary=e._shared.bindings[latest["edge_id"]]
	var edge: Dictionary=e._all_routes()[latest["edge_id"]]
	var end: int=e._shared.node_completion_minute(t["id"],latest["leg_index"])
	var stage:="LOADING" if minute<latest["loading_end_minute"] else "TRANSIT" if minute<latest["arrival_minute"] else "WAITING_UNLOAD" if end<0 else "UNLOADING" if minute<end else "AWAITING_RECIPIENT" if latest["leg_index"]==offer(t["offer_id"])["legs"].size()-1 else "TRANSFER_WAIT"
	return {"custodian":edge["carrier"],"site_id":"" if stage in ["LOADING","TRANSIT","WAITING_UNLOAD","UNLOADING"] else e._shared.facilities[b["node_resources"]["destination_storage"]]["site_id"],"place_id":edge["from_place_id"] if stage=="LOADING" else "" if stage=="TRANSIT" else edge["to_place_id"],"vehicle_id":b["vehicle_id"] if stage in ["LOADING","TRANSIT","WAITING_UNLOAD","UNLOADING"] else "","transport":stage,"transport_id":t["id"]}

func reservations() -> Dictionary:
	var result: Dictionary={}
	for t: Dictionary in tasks.values():
		if t["total_fee"]>t["paid"]: result[t["id"]]={"account_id":economy()._account(t["payer"],offer(t["offer_id"])["denomination"]),"amount":t["total_fee"]-t["paid"]}
	return result

func budget_contracts() -> Dictionary:
	var result: Dictionary={}
	for t: Dictionary in tasks.values(): result[t["id"]]={"kind":"CAPITAL_FREIGHT","budget_amount":t["total_fee"],"buyer":t["payer"],"category":"capital_freight","denomination":offer(t["offer_id"])["denomination"],"quantity":maxi(1,t["total_fee"]),"accepted_minute":t["minute"],"delivered":t["paid"],"cancelled":0,"route_legs":[]}
	return result

func actions(actor: String, firm: String) -> Array[Dictionary]:
	var e:=economy();var rows: Array[Dictionary]=[]
	for trade: Dictionary in e._capital.resale_trades.values():
		if trade["state"]!="ACCEPTED": continue
		var t:=for_trade(trade["id"])
		if t.is_empty() and firm==trade["buyer"]:
			for o: Dictionary in routes(trade["asset_id"],trade["source_site"],trade["target_site"],firm):
				var check:=commission_check(actor,trade,o)
				rows.append({"label":"委托设备承运 "+o["id"],"kind":"commission_capital_transport","payload":{"trade_id":trade["id"],"offer_id":o["id"]},"can_execute":check["accepted"],"reason":check["reason"]})
		elif not t.is_empty() and t["stage"]=="COMMISSIONED" and firm==trade["seller"] and e._capital.move_permission(actor,firm,"handover",0)["ok"]: rows.append({"label":"授权设备实际发运","kind":"dispatch_capital_transport","payload":{"transport_id":t["id"]}})
	return rows

func view(asset: String) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for t: Dictionary in tasks.values():
		if t["asset_id"]!=asset: continue
		var row:=t.duplicate(true);row["contract"]=offer(t["offer_id"]).duplicate(true);row["load"]=load_rule(asset).duplicate(true);row["entries"]=[]
		for entry: Dictionary in economy()._shared.entries.values():
			if entry["shipment_id"]==t["id"]: row["entries"].append(entry.duplicate(true))
		row["nodes"]=economy()._shared.shipment_node_view(t["id"])
		row["handling"]=[]
		for entry: Dictionary in row["entries"]:
			var loading: Dictionary=economy()._shared.handling.get(str(int(entry["minute"])/1440)+"|"+str(entry["edge_id"]),{})
			var arrival: Dictionary=economy()._shared.node_uses.get("node:"+str(t["id"])+":"+str(entry["leg_index"])+":destination_handling",{})
			row["handling"].append({"operation":"LOAD","hours":entry["handling_hours"],"minute":entry["minute"],"shared_work":loading.get("work",[]).duplicate(true)})
			if not arrival.is_empty():
				var unloading: Dictionary=economy()._shared.handling.get(str(int(arrival["minute"])/1440)+"|"+str(entry["edge_id"])+"|arrival",{})
				row["handling"].append({"operation":"UNLOAD","hours":handling_units(t["asset_id"])*int(economy()._shared.bindings[entry["edge_id"]]["node_resources"]["unloading_hours_per_unit"]),"minute":arrival["minute"],"shared_work":unloading.get("work",[]).duplicate(true)})
		rows.append(row)
	return rows

func reject(reason: String) -> Dictionary: return {"accepted":false,"reason":reason}
func fail(reason: String) -> bool: error=reason;return false

func restore_shape(saved: Dictionary) -> bool:
	var raw: Variant=saved.get("capital_transport",{})
	if not raw is Dictionary or raw.size()>256: return fail("Invalid equipment carriage collection")
	for id: Variant in raw:
		var t: Variant=raw[id]
		if not id is String or not t is Dictionary or not FormalLedgerState.exact_fields(t,["id","asset_id","trade_id","offer_id","actor","action_id","minute","payer","authority","payment_authority","dispatch_action","dispatch_authority","dispatch_minute","stage","leg_index","quantity","place_id","loading_end_minute","arrival_minute","unloading_end_minute","completed_legs","paid","total_fee","reason"]): return fail("Malformed equipment carriage")
		for key: String in ["id","asset_id","trade_id","offer_id","actor","action_id","payer","dispatch_action","stage","place_id","reason"]:
			if not t[key] is String: return fail("Invalid carriage reference")
		for key: String in ["minute","dispatch_minute","leg_index","quantity","loading_end_minute","arrival_minute","unloading_end_minute","paid","total_fee"]:
			if not t[key] is int or t[key]<(-1 if key.ends_with("minute") else 0): return fail("Invalid carriage time or amount")
		if t["id"]!=id or id!="capital_transport:"+str(t["action_id"]) or t["quantity"]!=1 or t["stage"] not in ["COMMISSIONED","WAITING","LOADING","TRANSIT","WAITING_UNLOAD","UNLOADING","AWAITING_RECIPIENT","DELIVERED"] or not t["completed_legs"] is Array or not t["authority"] is Dictionary or not t["payment_authority"] is Dictionary or not t["dispatch_authority"] is Dictionary or offer(t["offer_id"]).is_empty(): return fail("Invalid carriage identity or stage")
		for row: Variant in t["completed_legs"]:
			if not row is Dictionary or not FormalLedgerState.exact_fields(row,["leg_index","minute","payment_id"]) or not FormalLedgerState.valid_amount(row["leg_index"]) or not FormalLedgerState.valid_amount(row["minute"]) or not row["payment_id"] is String: return fail("Invalid completed carriage leg")
	tasks=raw.duplicate(true)
	return true

func valid_entry(entry: Dictionary, raw: Dictionary, saved: Dictionary) -> bool:
	var t: Dictionary=tasks.get(entry.get("shipment_id"),{})
	if t.is_empty() or entry.get("asset_id")!=t["asset_id"] or entry.get("quantity")!=1 or not FormalLedgerState.valid_amount(entry.get("leg_index")): return false
	var o:=offer(t["offer_id"]);var index: int=entry["leg_index"]
	if index>=o["legs"].size() or entry["edge_id"]!=o["legs"][index]["edge_id"] or entry["adoption_id"]!="economy_entry:"+str(t["id"])+":"+str(index) or t["dispatch_action"].is_empty() or entry["minute"]<t["dispatch_minute"]: return false
	if index>0:
		var previous: Dictionary=raw["node_uses"].get("node:"+str(t["id"])+":"+str(index-1)+":destination_berth",{})
		if previous.is_empty() or previous["end_minute"]>entry["minute"]: return false
	var trade: Dictionary=saved.get("capital_formation",{}).get("resale",{}).get("trades",{}).get(t["trade_id"],{})
	if trade.is_empty(): return false
	return trade["delivered_minute"]<0 or entry["minute"]<trade["delivered_minute"]

func valid_payment(id: String) -> bool:
	for t: Dictionary in tasks.values():
		for row: Dictionary in t["completed_legs"]:
			if row["payment_id"]!=id: continue
			var leg:=payment_legs(t,row["leg_index"])[0] as Dictionary
			var ledger: FormalLedgerState=economy()._world.ledger_state
			if leg["amount"]==0: return ledger.payment_batch(id).is_empty()
			var tx:=ledger.transaction(id)
			for key: String in leg:
				if tx.get(key)!=leg[key]: return false
			return tx.get("effective_minute")==row["minute"] and tx.get("denomination")==offer(t["offer_id"])["denomination"] and ledger.payment_batch(id)=={"transactions":[id],"releases":{t["id"]:leg["amount"]},"minute":row["minute"]}
	return false

func validate(saved: Dictionary) -> bool:
	var e:=economy();var now: int=e._world.game_clock.total_minutes();var trades: Dictionary={}
	for t: Dictionary in tasks.values():
		var trade: Dictionary=e._capital.resale_trades.get(t["trade_id"],{})
		var o:=offer(t["offer_id"])
		if trade.is_empty() or trades.has(t["trade_id"]) or trade["asset_id"]!=t["asset_id"] or trade["state"]=="CANCELLED" or trade["buyer"]!=t["payer"] or o["source_site"]!=trade["source_site"] or o["target_site"]!=trade["target_site"] or t["payer"] not in o["known_to"] or t["minute"]<trade["accepted_minute"] or t["minute"]>now or not compatible(o,t["asset_id"],t["minute"]): return fail("Carriage lost its original asset, route or accepted trade")
		trades[t["trade_id"]]=true
		var total:=0
		for leg: Dictionary in o["legs"]:
			if leg["carrier"]==t["payer"] and leg["fee"]!=0: return fail("Internal carriage created external revenue")
			total+=int(leg["fee"])
		if t["total_fee"]!=total or not e._capital.move_proof_valid(t["authority"],t["actor"],t["payer"],"freight",total,t["minute"]) or not e._capital.move_proof_valid(t["payment_authority"],t["actor"],t["payer"],"pay",total,t["minute"]): return fail("Carriage lacks separate freight authority")
		var plan: Dictionary=e._budgets.plan(t["payer"],o["denomination"],"capital_freight",0,t["minute"])
		if not plan.has("rule_id") or plan["root_authority"]!=t["authority"]["source"]["id"]: return fail("Carriage lacks original freight budget window")
		var command: Dictionary=saved["commands"].get(t["action_id"],{})
		if not action_matches(command,t["actor"],"commission_capital_transport",{"trade_id":t["trade_id"],"offer_id":t["offer_id"]},t["minute"]) or command["result"].get("transport_id")!=t["id"]: return fail("Carriage lacks buyer commission action")
		if t["dispatch_action"].is_empty():
			if t["dispatch_minute"]!=-1 or not t["dispatch_authority"].is_empty(): return fail("Unconsigned carriage claims seller authority")
		else:
			if not t["dispatch_authority"].get("actor") is String: return fail("Invalid seller dispatch actor")
			var dispatch: Dictionary=saved["commands"].get(t["dispatch_action"],{})
			if t["dispatch_minute"]<t["minute"] or t["dispatch_minute"]>now or not action_matches(dispatch,t["dispatch_authority"].get("actor",""),"dispatch_capital_transport",{"transport_id":t["id"]},t["dispatch_minute"]) or not e._capital.move_proof_valid(t["dispatch_authority"],t["dispatch_authority"].get("actor",""),trade["seller"],"handover",0,t["dispatch_minute"]): return fail("Carriage lacks actual seller release authority")
		var original: Dictionary=e._capital.asset_state(t["asset_id"],t["minute"])
		if original.get("owner")!=trade["seller"] or original.get("status")!="DETACHED": return fail("Equipment was shipped without actual dismantling or seller title")
		var entered:=0;var completed:=0;var paid:=0;var latest: Dictionary={}
		for index: int in o["legs"].size():
			var entry: Dictionary=e._shared.entries.get("economy_entry:"+str(t["id"])+":"+str(index),{})
			if entry.is_empty():
				for later: int in range(index+1,o["legs"].size()):
					if e._shared.entries.has("economy_entry:"+str(t["id"])+":"+str(later)): return fail("Equipment skipped a transport leg")
				break
			entered+=1;latest=entry
			var end: int=e._shared.node_completion_minute(t["id"],index)
			if end>=0 and end<=now:
				if t["completed_legs"].size()<=index: return fail("Unloaded equipment lost its leg completion")
				var row:=t["completed_legs"][index] as Dictionary
				if row!={"leg_index":index,"minute":end,"payment_id":"capital_freight_payment:"+str(t["id"])+":"+str(index)} or not valid_payment(row["payment_id"]): return fail("Carriage completion or fee differs from actual unloading")
				paid+=int(o["legs"][index]["fee"]);completed+=1
		if completed!=t["completed_legs"].size() or paid!=t["paid"]: return fail("Equipment freight fee or completed-leg count differs")
		var expected:="COMMISSIONED" if t["dispatch_action"].is_empty() else "WAITING"
		var index: int=completed if completed<o["legs"].size() else o["legs"].size()-1
		if completed==o["legs"].size(): expected="DELIVERED" if trade["state"]=="DELIVERED" else "AWAITING_RECIPIENT"
		elif entered>completed:
			var end: int=e._shared.node_completion_minute(t["id"],index)
			expected="LOADING" if now<latest["loading_end_minute"] else "TRANSIT" if now<latest["arrival_minute"] else "UNLOADING" if end>now else "WAITING_UNLOAD"
		if t["stage"]!=expected or t["leg_index"]!=index: return fail("Equipment physical stage differs from actual capacity entries")
		var entered_current: bool=entered>index
		for field: String in ["loading_end_minute","arrival_minute"]:
			if t[field]!=(latest[field] if entered_current else -1): return fail("Equipment arrival precedes actual transport time")
		var unload_end: int=e._shared.node_completion_minute(t["id"],index) if entered_current else -1
		if t["unloading_end_minute"]!=unload_end: return fail("Equipment unloading time differs from node work")
		var place: String=e._place(trade["source_site"]) if entered==0 else e._all_routes()[o["legs"][entered-1]["edge_id"]]["from_place_id"] if expected=="LOADING" else "" if expected=="TRANSIT" else e._all_routes()[o["legs"][entered-1]["edge_id"]]["to_place_id"]
		if t["place_id"]!=place: return fail("Equipment claims a second physical location")
		if not trade["delivery_project"].is_empty():
			var p: Dictionary=e._capital.projects[trade["delivery_project"]]
			if completed!=o["legs"].size() or p["accepted_minute"]<t["completed_legs"].back()["minute"]: return fail("Equipment handover precedes actual destination unloading")
		if trade["state"]=="DELIVERED" and expected!="DELIVERED": return fail("Equipment title transferred while still in transport")
	for trade: Dictionary in e._capital.resale_trades.values():
		if e._capital.cross_trade(trade) and (trade["state"]=="DELIVERED" or not trade["delivery_project"].is_empty()) and for_trade(trade["id"]).is_empty(): return fail("Cross-place delivery lacks actual carriage")
	for id: String in saved["commands"]:
		var c:=saved["commands"][id] as Dictionary
		if not c.get("result",{}).get("accepted",false): continue
		if c["envelope"]["command"]["kind"]=="commission_capital_transport" and not tasks.has("capital_transport:"+id): return fail("Accepted equipment carriage was removed")
		if c["envelope"]["command"]["kind"]=="dispatch_capital_transport" and tasks.get(c["envelope"]["command"]["payload"].get("transport_id"),{}).get("dispatch_action")!=id: return fail("Seller dispatch action lost its carriage")
	return true

func action_matches(c: Dictionary, actor: String, kind: String, payload: Dictionary, minute: int) -> bool:
	return c.get("result",{}).get("accepted",false) and c.get("envelope",{}).get("actor")==actor and c["envelope"]["command"].get("kind")==kind and c["envelope"]["command"].get("payload")==payload and c["envelope"]["command"].get("minute")==minute


func waiting_reason(t: Dictionary) -> String:
	var e:=economy();var leg:=offer(t["offer_id"])["legs"][t["leg_index"]] as Dictionary
	var b:=e._shared.bindings[leg["edge_id"]] as Dictionary;var now: int=e._world.game_clock.total_minutes()
	if not e._shared.window_open(b,now): return "WAITING_EXPLICIT_HOST_ENTRY_WINDOW"
	if not e._site_operating(b["handling_site"]): return "WAITING_LAWFUL_ORIGIN_FACILITY"
	var load:={"asset_id":t["asset_id"]};var amount:=weight(t["asset_id"],b["weight_unit"])
	if amount<=0: return "INCOMPATIBLE_EQUIPMENT_LOAD_UNIT"
	if e._shared._vehicle_available(b,now)<amount: return "WAITING_ACTUAL_VEHICLE_PAYLOAD"
	if e._world.spatial_world.remaining_capacity(b["source_link_id"])<amount: return "WAITING_SHARED_SPATIAL_CAPACITY"
	if e._shared._node_entry_limit(b,load,now)<1: return "WAITING_ORIGIN_HANDLING_OR_BERTH"
	return "WAITING_ACTUAL_LOADING_LABOR_OR_FINAL_ADOPTION"
