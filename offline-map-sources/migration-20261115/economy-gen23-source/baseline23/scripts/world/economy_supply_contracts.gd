extends RefCounted
## Formal future supply responsibility. Physical fulfilment remains original SALE.
## No inventory, money balance, transport queue or delivery receipt is duplicated.
var _owner: WeakRef
var e: RefCounted:
	get:return _owner.get_ref() if _owner!=null else null
var records: Dictionary={}
var error: String=""
var notices: Dictionary={}
var restore_receipts: Dictionary={}

func bind(owner: RefCounted) -> void:_owner=weakref(owner)
func rules() -> Dictionary:return e.config.get("supply_contracts",{})
func snapshot() -> Dictionary:
	if policies().is_empty():return records.duplicate(true)
	return {"format":"SUPPLY_OPPORTUNITIES_V1","contracts":records.duplicate(true),"notices":notices.duplicate(true)}
func policies() -> Array:return e.config.get("supply_opportunity_policies",[])
func mandate(id: String) -> Dictionary:
	if id==rules().get("id"):return rules()
	return notices.get(id,{}).get("terms",{})
func policy(id: String) -> Dictionary:
	for row: Dictionary in policies():
		if row["id"]==id:return row
	return {}


static func valid_configuration(cfg: Dictionary) -> bool:
	if not valid_opportunity_configuration(cfg):return false
	if not cfg.has("supply_contracts"):return true
	var r: Variant=cfg["supply_contracts"]
	if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","buyer","buyer_site","supplier","supplier_site","good","quantity","days","premium","competitor","competitor_site","competitor_target","competitor_batch","basis"]):return false
	for key: String in ["id","buyer","buyer_site","supplier","supplier_site","good","competitor","competitor_site"]:
		if not r[key] is String or r[key].is_empty():return false
	for key: String in ["quantity","days","premium","competitor_target","competitor_batch"]:
		if not FormalLedgerState.valid_amount(r[key]) or r[key]<=0:return false
	if r["quantity"]>1000000 or r["days"]>30 or r["buyer"]==r["supplier"] or r["competitor"] in [r["buyer"],r["supplier"]] or r["basis"]!="EXPLICIT_DEVELOPMENT_CITY_SUPPLY":return false
	var owners: Dictionary={}
	for firm: Dictionary in cfg.get("firms",[]):
		for site: Dictionary in firm["sites"]:owners[site["id"]]={"firm":firm["id"],"place":site["place_id"],"goods":site["stock"]}
	for pair: Array in [["buyer","buyer_site"],["supplier","supplier_site"],["competitor","competitor_site"]]:
		if not owners.has(r[pair[1]]) or owners[r[pair[1]]]["firm"]!=r[pair[0]] or not owners[r[pair[1]]]["goods"].has(r["good"]):return false
	# First supported contract uses a real local freight leg, no virtual handover.
	return owners[r["buyer_site"]]["place"]==owners[r["supplier_site"]]["place"]

func offer(id: String="") -> Dictionary:
	var r: Dictionary=rules() if id.is_empty() else mandate(id)
	if notices.has(id):return notice_offer(id)
	return _priced_offer(r)

func _priced_offer(r: Dictionary) -> Dictionary:
	if r.is_empty():return {}
	var known: Array[Dictionary]=e._offers(r["buyer"],r["buyer_site"],r["good"])
	var reference: int=0
	var evidence: Array[Dictionary]=[]
	for q: Dictionary in known:
		if not FormalLedgerState.valid_amount(q.get("price")) or int(q["price"])<=0 or str(q.get("route_id","")).is_empty() or not e._local_quotes.reason(r["buyer_site"],q["seller_site"],r["good"]).is_empty():continue
		var landed: int=int(q["price"])+int(q.get("freight_per_unit",0))
		if reference==0 or landed<reference:reference=landed
		evidence.append({"seller":q["seller"],"seller_site":q["seller_site"],"quote_id":q["quote_id"],"price":q["price"],"freight":q.get("freight_per_unit",0),"route_id":q["route_id"]})
	var cash: int=e._world.ledger_state.available_balance(e._account(r["buyer"]))
	var price: int=mini(reference+int(r["premium"]),cash/int(r["quantity"])) if reference>0 else 0
	return {"id":r["id"],"buyer":r["buyer"],"buyer_site":r["buyer_site"],"good":r["good"],"quantity":r["quantity"],"days":r["days"],"price":price,"buyer_available":cash,"evidence":evidence,"minute":e._world.game_clock.total_minutes(),"status":"RECRUITING" if e._world.game_clock.total_minutes()<=int(r["days"])*1440 else "OVERDUE","published_minute":0,"deadline":int(r["days"])*1440,"penalty":0,"ready":price>0 and e._world.game_clock.total_minutes()<=int(r["days"])*1440}

func locked_price(id: String) -> int:return int(records.get(id,{}).get("price",0))
func allocated(row: Dictionary,orders: Dictionary) -> int:
	var total: int=0
	for id: String in row["batches"]:total+=int(orders.get(id,{}).get("quantity",0))
	return total
func remaining_money(id: String) -> int:
	var row: Dictionary=records.get(id,{})
	if row.is_empty() or row["ended_minute"]>=0:return 0
	return (int(row["quantity"])-allocated(row,e._orders))*int(row["price"])
func cash_reservations() -> Dictionary:
	var result: Dictionary={}
	for id: String in records:
		var row: Dictionary=records[id]
		var amount: int=(int(row["quantity"])-int(row["allocated"]))*int(row["price"]) if row["ended_minute"]<0 else 0
		if amount>0:result[id]={"account_id":e._account(row["buyer"]),"amount":amount}
	return result
func progress(row: Dictionary,receipts: Dictionary,orders: Dictionary) -> Dictionary:
	var ontime: int=0;var late: int=0;var transit: int=0;var paid: int=0
	for receipt: Dictionary in receipts.values():
		if receipt["order_id"] not in row["batches"]:continue
		var q: int=int(receipt["quantity"])
		if int(receipt.get("delivered_minute",int(receipt["delivered_day"])*1440))<=int(row["deadline"]):ontime+=q
		else:late+=q
		paid+=q*int(row["price"])
	for id: String in row["batches"]:
		var order: Dictionary=orders.get(id,{})
		transit+=int(order.get("pending",0))+int(order.get("transit",0))
	return {"ontime":ontime,"late":late,"in_transit":transit,"paid":paid,"remaining":maxi(0,int(row["quantity"])-ontime),"unallocated":int(row["quantity"])-int(row["allocated"])}
func status(row: Dictionary,p: Dictionary,minute: int) -> String:
	if row["end_reason"]=="TERMINATED":return "TERMINATED"
	if p["ontime"]==row["quantity"]:return "COMPLETED"
	if minute>int(row["deadline"]):return "OVERDUE"
	return "PARTIAL" if p["ontime"]>0 else "ACCEPTED"
func view(actor: String,id: String="") -> Dictionary:
	var r: Dictionary=rules() if id.is_empty() else mandate(id)
	if r.is_empty() or not e._manager(actor,r["supplier"]):return {}
	if notices.has(r["id"]) and not known_notice(r["id"]):return {}
	var result: Dictionary={} if records.has(r["id"]) else offer(r["id"])
	if records.has(r["id"]):
		result=records[r["id"]].duplicate(true)
		var p: Dictionary=progress(result,e._delivery_receipts,e._orders)
		result.merge(p);result["status"]=status(result,p,e._world.game_clock.total_minutes());result["secured_unallocated"]=remaining_money(r["id"])
	result.erase("buyer_available");result.erase("cash_at_accept")
	result["supplier"]=r["supplier"]
	result["supplier_site"]=r["supplier_site"]
	result["free_stock"]=maxi(0,int(e._stocks[r["supplier_site"]][r["good"]])-e._committed(r["supplier_site"],r["good"]))
	# Public competitor offer only. Its private wallet is not player knowledge.
	var base: Dictionary=rules()
	var competitor_price: Variant=e._price(base["competitor_site"],base["good"])
	var competitor_basis: String="SCENARIO_PUBLIC_QUOTATION"
	if not e._local_quotes.rule(base["competitor_site"],base["good"]).is_empty():
		var received: Dictionary=e._local_quotes.known(r["supplier_site"],base["competitor_site"],base["good"])
		competitor_price=received.get("price",null)
		competitor_basis="LAST_RECEIVED_QUOTATION" if not received.is_empty() else "QUOTATION_NOT_RECEIVED"
	result["competitor"]={"firm":base["competitor"],"site":base["competitor_site"],"good":base["good"],"price":competitor_price,"basis":competitor_basis}
	return result

func request(actor: String,kind: String,p: Dictionary,action_id: String) -> Dictionary:
	if kind=="publish_supply_opportunity":return publish(actor,p,action_id)
	var r: Dictionary=mandate(str(p.get("contract_id","")))
	if r.is_empty():return e._result(false,"SUPPLY_FEATURE_OFF")
	if not e._manager(actor,r["supplier"]):return e._result(false,"NOT_SUPPLY_MANAGER")
	if kind=="accept_supply_contract":
		if not FormalLedgerState.exact_fields(p,["contract_id","price"]) or p["contract_id"]!=r["id"] or not FormalLedgerState.valid_amount(p["price"]):return e._result(false,"INVALID_SUPPLY_ACCEPTANCE")
		if records.has(r["id"]):return e._result(false,"SUPPLY_ALREADY_ACCEPTED")
		if e._local_quotes.sales_paused(r["supplier_site"],r["good"]):return e._result(false,"GOODS_NEW_SALES_PAUSED")
		var q: Dictionary=offer(r["id"])
		if not q["ready"] or p["price"]!=q["price"] or (notices.has(r["id"]) and not known_notice(r["id"])):return e._result(false,"SUPPLY_QUOTE_CHANGED_OR_UNFUNDED")
		if not e._site_accepting(r["buyer_site"]) or not e._site_selling(r["supplier_site"]):return e._result(false,"FIRM_STOPPED_NEW_BUSINESS")
		var route: Dictionary=e._route_for(r["buyer"],r["supplier"],"",r["buyer_site"],r["supplier_site"])
		if route.is_empty() or e._freight(e._locked_legs(route,FormalLedgerState.DENOMINATION))!=0:return e._result(false,"SUPPLY_REQUIRES_KNOWN_ZERO_FREIGHT_LOCAL_ROUTE")
		# Total cash security is separate from the physical stock still to procure.
		if not e._world.ledger_state.reserve(r["id"],e._account(r["buyer"]),int(r["quantity"])*int(q["price"])):return e._result(false,"SUPPLY_NOT_FULLY_FUNDED")
		records[r["id"]]={"id":r["id"],"buyer":r["buyer"],"buyer_site":r["buyer_site"],"supplier":r["supplier"],"supplier_site":r["supplier_site"],"good":r["good"],"quantity":r["quantity"],"price":q["price"],"accepted_minute":q["minute"],"deadline":int(r.get("deadline",int(r["days"])*1440)),"accept_action":action_id,"accepted_by":actor,"route_id":route["id"],"evidence":q["evidence"],"cash_at_accept":q["buyer_available"],"batches":[],"allocated":0,"ended_minute":-1,"end_reason":"","end_action":"","penalty":0}
		return {"accepted":true,"reason":"SUPPLY_ACCEPTED_FUNDED","sales_adoption_sequence":e._commands.size(),"contract_id":r["id"],"quantity":r["quantity"],"price":q["price"],"evidence":q["evidence"].duplicate(true),"cash_at_accept":q["buyer_available"]}
	if not p.get("contract_id") is String or not records.has(p["contract_id"]):return e._result(false,"UNKNOWN_SUPPLY_CONTRACT")
	var row: Dictionary=records[p["contract_id"]]
	if row["ended_minute"]>=0:return e._result(false,"SUPPLY_ENDED")
	if kind=="terminate_supply_contract":
		if not FormalLedgerState.exact_fields(p,["contract_id"]):return e._result(false,"INVALID_SUPPLY_TERMINATION")
		_end(row,"TERMINATED",action_id)
		return {"accepted":true,"reason":"SUPPLY_TERMINATED_EXISTING_BATCHES_RETAINED"}
	if not FormalLedgerState.exact_fields(p,["contract_id","quantity"]) or not FormalLedgerState.valid_amount(p["quantity"]) or p["quantity"]<=0:return e._result(false,"INVALID_SUPPLY_BATCH")
	var remaining: int=int(row["quantity"])-int(row["allocated"])
	if remaining<=0:return e._result(false,"SUPPLY_ALL_ALLOCATED")
	if not e._site_selling(row["supplier_site"]):return e._result(false,"FIRM_STOPPED_NEW_BUSINESS")
	var result: Dictionary=e._admit(row["buyer"],row["supplier"],row["good"],mini(remaining,int(p["quantity"])),action_id,row["route_id"],int(row["deadline"])/1440,row["supplier_site"],row["buyer_site"],"",row["id"])
	if result.get("accepted",false):
		row["batches"].append(result["order_id"]);row["allocated"]+=int(result["quantity"])
		result["reason"]="SUPPLY_BATCH_DISPATCH_ACCEPTED";result["contract_id"]=row["id"]
	return result

func _end(row: Dictionary,reason: String,action: String="") -> void:
	var cash: int=remaining_money(row["id"])
	if cash>0:
		var released: bool=e._world.ledger_state.release(row["id"],cash)
		assert(released)
	row["ended_minute"]=e._world.game_clock.total_minutes();row["end_reason"]=reason;row["end_action"]=action
func refresh() -> void:
	for row: Dictionary in records.values():
		if row["ended_minute"]>=0:continue
		var p: Dictionary=progress(row,e._delivery_receipts,e._orders)
		if p["ontime"]==row["quantity"]:_end(row,"COMPLETED")
		elif e._world.game_clock.total_minutes()>int(row["deadline"]):_end(row,"OVERDUE")

# Reconstructed from canonical orders and delivery receipts. No persistent balances.
# Applies to the opportunity scenario only; earlier openings retain their policy.
func competition_observation() -> Dictionary:
	var r: Dictionary=rules()
	if r.is_empty():return {}
	var firm: String=r["competitor"];var site: String=r["competitor_site"];var good: String=r["good"]
	var window: int=4;var cooldown: int=2;var sold: int=0;var received: int=0;var last_buy: int=-100
	var refs: Array[String]=[]
	for order: Dictionary in e._orders.values():
		if order["kind"]!="SALE" or order["good"]!=good:continue
		if order["buyer"]==firm and order["buyer_site"]==site:last_buy=maxi(last_buy,int(order["accepted_minute"])/1440)
	for receipt: Dictionary in e._delivery_receipts.values():
		if int(receipt["delivered_day"])<=e.day-window:continue
		var order: Dictionary=e._orders[receipt["order_id"]]
		if order["kind"]!="SALE" or order["good"]!=good:continue
		if order["seller"]==firm and order["seller_site"]==site:
			sold+=int(receipt["quantity"]);refs.append(receipt["id"])
		if order["buyer"]==firm and order["buyer_site"]==site:
			received+=int(receipt["quantity"]);refs.append(receipt["id"])
	var free: int=maxi(0,int(e._stocks[site][good])-e._committed(site,good))
	var incoming: int=maxi(0,e._exposure(site,good)-int(e._stocks[site][good]))
	# One exploratory batch without sales; replenishment scales only with own actual sales.
	var target: int=mini(int(r["competitor_target"]),maxi(int(r["competitor_batch"]),sold*2))
	var need: int=maxi(0,target-free-incoming)
	var reason: String="OWN_DELIVERED_SALES_REPLENISHMENT" if sold>0 else "LIMITED_EXPLORATORY_STOCK"
	if e.day-last_buy<cooldown:reason="WAIT_PURCHASE_COOLDOWN";need=0
	elif incoming>0:reason="WAIT_EXISTING_PURCHASE_RESPONSIBILITY";need=0
	elif need==0:reason="HOLD_OWN_STOCK_COVERAGE"
	return {"policy":"OWN_HISTORY_RESALE_09","window_days":window,"cooldown_days":cooldown,"recent_sold":sold,"recent_received":received,"free_stock":free,"incoming":incoming,"last_purchase_day":last_buy,"target":target,"need":need,"cash_buffer":6,"reason":reason,"receipt_refs":refs}

func npc_decisions() -> void:
	for p: Dictionary in policies():
		if publication_ready(p):e._npc_submit(p["buyer"],"publish_supply_opportunity",{"policy_id":p["id"]},p["id"],{"basis":"OWN_REAL_INPUT_NEED_AND_FINITE_PROCUREMENT_MANDATE","observed_need":need_quantity(p)})
	var r: Dictionary=rules()
	if r.is_empty():return
	var firm: String=r["competitor"];var site: String=r["competitor_site"]
	if not e._site_accepting(site):return
	var observation: Dictionary=competition_observation() if not policies().is_empty() else {}
	var need: int=maxi(0,int(r["competitor_target"])-e._exposure(site,r["good"])) if observation.is_empty() else int(observation["need"])
	if need<=0:return
	var offers: Array[Dictionary]=e._offers(firm,site,r["good"])
	offers.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a["price"])+int(a["freight_per_unit"])<int(b["price"])+int(b["freight_per_unit"]))
	for q: Dictionary in offers:
		if not FormalLedgerState.valid_amount(q.get("price")) or not FormalLedgerState.valid_amount(q.get("freight_per_unit")):continue
		var unit_cost: int=int(q["price"])+int(q["freight_per_unit"])
		if unit_cost>=e._price(site,r["good"]) or unit_cost<=0:continue
		var quantity: int=mini(need,int(r["competitor_batch"]))
		if not observation.is_empty():
			var cash: int=e._world.ledger_state.available_balance(e._account(firm,q["denomination"]))
			quantity=mini(quantity,maxi(0,cash-int(observation["cash_buffer"]))/unit_cost)
		if quantity<=0:continue
		var payload: Dictionary={"seller":q["seller"],"seller_site":q["seller_site"],"buyer_site":site,"good":r["good"],"quantity":quantity,"quote_id":q["quote_id"],"path_id":q["route_id"],"denomination":q["denomination"],"max_price":q["price"]}
		var decision: Dictionary={"purpose":"FINITE_STOCK_RESALE","target":r["competitor_target"],"known_quote":q["quote_id"]}
		if not observation.is_empty():decision.merge(observation,true)
		var outcome: Dictionary=e._npc_submit(firm,"buy",payload,"city_competition",decision)
		if outcome.get("accepted",false):break

func valid_order(order: Dictionary) -> bool:
	var row: Dictionary=records.get(order.get("supply_contract_id"),{})
	if row.is_empty() or order.get("id") not in row["batches"]:return false
	return order.get("kind")=="SALE" and order.get("buyer")==row["buyer"] and order.get("seller")==row["supplier"] and order.get("buyer_site")==row["buyer_site"] and order.get("seller_site")==row["supplier_site"] and order.get("good")==row["good"] and order.get("price")==row["price"] and order.get("route_id")==row["route_id"] and int(order.get("accepted_minute",-1))>=int(row["accepted_minute"]) and int(order.get("accepted_minute",-1))<=int(row["deadline"]) and (row["ended_minute"]<0 or int(order.get("accepted_minute",-1))<=int(row["ended_minute"]))
func valid_order_action(value: Dictionary,order: Dictionary) -> bool:
	if not valid_order(order):return false
	var entry: Dictionary=value["commands"].get(order["action_id"],{})
	var c: Dictionary=entry.get("envelope",{}).get("command",{})
	var p: Dictionary=c.get("payload",{})
	return c.get("kind")=="submit_supply_batch" and c.get("minute")==order["accepted_minute"] and FormalLedgerState.exact_fields(p,["contract_id","quantity"]) and p["contract_id"]==order["supply_contract_id"] and FormalLedgerState.valid_amount(p["quantity"]) and int(p["quantity"])>=int(order["quantity"]) and e._manager_at(str(entry.get("envelope",{}).get("actor","")),order["seller"],int(order["accepted_minute"])) and entry.get("result",{}).get("accepted",false) and entry["result"].get("order_id")==order["id"] and entry["result"].get("quantity")==order["quantity"]

func restore(saved: Variant,value: Dictionary) -> bool:
	records={};notices={};restore_receipts={};error=""
	if saved==null:return (rules().is_empty() and e._world.ledger_state._reservation_splits.is_empty()) or fail("Missing configured supply contract state")
	if not saved is Dictionary or (rules().is_empty() and not saved.is_empty()):return fail("Invalid supply contract container")
	if saved.has("format"):
		if not FormalLedgerState.exact_fields(saved,["format","contracts","notices"]) or saved["format"]!="SUPPLY_OPPORTUNITIES_V1" or not saved["contracts"] is Dictionary or not saved["notices"] is Dictionary:return fail("Invalid opportunity envelope")
		notices=saved["notices"].duplicate(true);saved=saved["contracts"]
	else:notices={}
	if saved.size()>129:return fail("Supply contract count bound")
	for field: String in ["orders","commands","delivery_receipts","receipts"]:
		if not value.get(field) is Dictionary:return fail("Missing supply context")
	for order: Variant in value["orders"].values():
		if not order is Dictionary:return fail("Malformed supply order context")
	for receipt: Variant in value["delivery_receipts"].values():
		if not receipt is Dictionary or not receipt.get("order_id") is String or not FormalLedgerState.valid_amount(receipt.get("quantity")) or not FormalLedgerState.valid_amount(receipt.get("delivered_day")) or (receipt.has("delivered_minute") and not FormalLedgerState.valid_amount(receipt["delivered_minute"])):return fail("Malformed supply receipt context")
	for command_key: Variant in value["commands"]:
		if not command_key is String:return fail("Invalid supply action key")
	for entry: Variant in value["commands"].values():
		if not entry is Dictionary or not entry.get("envelope") is Dictionary or not entry["envelope"].get("command") is Dictionary or not entry["envelope"]["command"].get("payload") is Dictionary or not entry.get("result") is Dictionary:return fail("Malformed supply action context")
	if not value.get("messages") is Array:return fail("Missing message queue")
	for message: Variant in value["messages"]+value["receipts"].values():
		if not message is Dictionary or not message.get("actor") is String or not message.get("candidate") is String or not FormalLedgerState.valid_amount(message.get("delivery_day")):return fail("Malformed procurement message")
	restore_receipts=value["receipts"]
	if not restore_notices(value):return false
	var expected_splits: Dictionary={}
	var orders: Dictionary=value.get("orders",{});var commands: Dictionary=value.get("commands",{})
	for id: Variant in saved:
		var row: Variant=saved[id]
		var r: Dictionary=mandate(str(id))
		if r.is_empty():return fail("Unknown supply mandate")
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["id","buyer","buyer_site","supplier","supplier_site","good","quantity","price","accepted_minute","deadline","accept_action","accepted_by","route_id","evidence","cash_at_accept","batches","allocated","ended_minute","end_reason","end_action","penalty"]):return fail("Invalid supply terms")
		for field: String in ["id","buyer","buyer_site","supplier","supplier_site","good","accept_action","accepted_by","route_id","end_reason","end_action"]:
			if not row[field] is String:return fail("Invalid supply string")
		for field: String in ["quantity","price","accepted_minute","deadline","allocated","penalty","cash_at_accept"]:
			if not FormalLedgerState.valid_amount(row[field]):return fail("Invalid supply amount")
		if typeof(row["ended_minute"])!=TYPE_INT or row["ended_minute"] < -1 or not row["evidence"] is Array or not row["batches"] is Array:return fail("Invalid supply history")
		for field: String in ["id","buyer","buyer_site","supplier","supplier_site","good","quantity"]:
			if row[field]!=r.get(field):return fail("Supply terms differ from opening mandate")
		if id!=row["id"] or row["price"]<=0 or row["penalty"]!=0 or row["deadline"]!=int(r.get("deadline",int(r["days"])*1440)) or row["accepted_minute"]>row["deadline"] or row["accepted_minute"]>e._world.game_clock.total_minutes():return fail("Supply price or time conflict")
		var accept: Dictionary=commands.get(row["accept_action"],{})
		var action: Dictionary=accept.get("envelope",{}).get("command",{})
		if not e._local_quotes.valid_supply_acceptance(row["supplier_site"],row["good"],row["accepted_minute"],accept.get("result",{})):return fail("New supply accepted while sales paused")
		if action.get("kind")!="accept_supply_contract" or action.get("minute")!=row["accepted_minute"] or action.get("payload")!={"contract_id":id,"price":row["price"]} or accept.get("envelope",{}).get("actor")!=row["accepted_by"] or not accept.get("result",{}).get("accepted",false) or not e._manager_at(row["accepted_by"],row["supplier"],row["accepted_minute"]):return fail("Supply acceptance authority lost")
		var result: Dictionary=accept["result"]
		if result.get("contract_id")!=id or result.get("quantity")!=row["quantity"] or result.get("price")!=row["price"] or result.get("cash_at_accept")!=row["cash_at_accept"] or result.get("evidence")!=row["evidence"]:return fail("Supply acceptance result differs from terms")
		var reference: int=evidence_reference(row["evidence"],int(notices.get(id,{}).get("published_minute",row["accepted_minute"])),value,r)
		if reference<=0 or row["price"]!=(int(notices[id]["price"]) if notices.has(id) else mini(reference+int(r["premium"]),int(row["cash_at_accept"])/int(row["quantity"]))):return fail("Supply price lacks known funded evidence")
		var valid_route: bool=false
		for path: Dictionary in e._paths_for(row["buyer"],e._place(row["supplier_site"]),e._place(row["buyer_site"]),int(row["accepted_minute"])/1440):
			if path["id"]==row["route_id"] and e._freight(e._locked_legs(path,FormalLedgerState.DENOMINATION))==0:valid_route=true
		if not valid_route:return fail("Supply destination route lost")
		if row["batches"].size()>int(row["quantity"]):return fail("Supply batch count exceeds quantity")
		var seen: Dictionary={};var quantity: int=0
		for batch: Variant in row["batches"]:
			if not batch is String or seen.has(batch) or not orders.get(batch) is Dictionary or orders[batch].get("supply_contract_id")!=id:return fail("Supply batch link lost")
			seen[batch]=true;quantity+=int(orders[batch].get("quantity",0))
			expected_splits["supply_split:"+batch]={"source":id,"target":batch,"account_id":e._account(row["buyer"]),"amount":int(orders[batch].get("quantity",0))*int(row["price"])}
			var split: Dictionary=e._world.ledger_state._reservation_splits.get("supply_split:"+batch,{})
			if split!={"source":id,"target":batch,"account_id":e._account(row["buyer"]),"amount":int(orders[batch].get("quantity",0))*int(row["price"])}:return fail("Supply batch funding split lost")
		if quantity!=row["allocated"] or quantity>int(row["quantity"]):return fail("Supply allocation exceeds promise")
		if row["ended_minute"]<0:
			if row["end_reason"]!="" or row["end_action"]!="" or e._world.game_clock.total_minutes()>int(row["deadline"]):return fail("Unresolved expired supply promise")
		elif row["ended_minute"]>e._world.game_clock.total_minutes() or row["ended_minute"]<row["accepted_minute"] or row["end_reason"] not in ["COMPLETED","OVERDUE","TERMINATED"]:return fail("Invalid supply end")
		if row["end_reason"]=="TERMINATED":
			var end: Dictionary=commands.get(row["end_action"],{})
			if end.get("envelope",{}).get("command",{}).get("kind")!="terminate_supply_contract" or end.get("envelope",{}).get("command",{}).get("minute")!=row["ended_minute"] or not end.get("result",{}).get("accepted",false):return fail("Supply termination lacks accepted action")
			var ec: Dictionary=end["envelope"]["command"]
			if ec.get("payload")!={"contract_id":id} or row["ended_minute"]>row["deadline"] or not e._manager_at(str(end["envelope"].get("actor","")),row["supplier"],row["ended_minute"]):return fail("Supply termination authority conflict")
		elif row["end_action"]!="":return fail("Unexpected supply end action")
		var p: Dictionary=progress(row,value.get("delivery_receipts",{}),orders)
		if row["end_reason"]=="COMPLETED" and p["ontime"]!=row["quantity"]:return fail("False supply completion")
		if row["end_reason"]=="OVERDUE" and (row["ended_minute"]<=row["deadline"] or p["ontime"]==row["quantity"]):return fail("False supply default")
		if row["end_reason"]=="COMPLETED":
			for receipt: Dictionary in value["delivery_receipts"].values():
				if receipt["order_id"] in row["batches"] and int(receipt.get("delivered_minute",int(receipt["delivered_day"])*1440))>int(row["ended_minute"]):return fail("Completion precedes actual acceptance")
		records[id]=row.duplicate(true)
	for order: Dictionary in orders.values():
		if order.has("supply_contract_id") and not valid_order(order):return fail("Unowned supply batch")
	if expected_splits!=e._world.ledger_state._reservation_splits:return fail("Orphan supply funding split")
	for action_id: String in commands:
		var entry: Dictionary=commands[action_id]
		var c: Dictionary=entry["envelope"]["command"]
		if not entry["result"].get("accepted",false) or c.get("kind") not in ["accept_supply_contract","submit_supply_batch","terminate_supply_contract"]:continue
		var row: Dictionary=records.get(c.get("payload",{}).get("contract_id"),{})
		if row.is_empty():return fail("Accepted supply action lost its contract")
		if c["kind"]=="accept_supply_contract" and row["accept_action"]!=action_id:return fail("Duplicate supply acceptance")
		if c["kind"]=="terminate_supply_contract" and row["end_action"]!=action_id:return fail("Supply termination journal lost")
		if c["kind"]=="submit_supply_batch":
			var batch: Dictionary=orders.get(entry["result"].get("order_id"),{})
			if batch.is_empty() or batch.get("action_id")!=action_id or batch.get("id") not in row["batches"]:return fail("Supply batch action lost")
	for p: Dictionary in policies():
		if mandate_used(p["id"])>int(p["max_commitment"]):return fail("Cumulative supply mandate exceeded")
	for id: String in records:
		if notices.has(id):
			var m: Dictionary=value["receipts"].get("supply_notice:"+id,{})
			if m.is_empty() or int(m["delivery_day"])*1440>int(records[id]["accepted_minute"]):return fail("Accepted unknown procurement notice")
	restore_receipts={}
	return true
func fail(message: String) -> bool:error=message;return false

func keeper_reason(subject: String) -> String:
	for row: Dictionary in records.values():
		if row["ended_minute"]<0 and subject in [row["buyer"],row["supplier"],row["buyer_site"],row["supplier_site"]]:return "SUPPLY_PROMISE_REQUIRES_TERMINATION_OR_FULFILMENT"
	return ""

func evidence_reference(evidence: Array,minute: int,native: Dictionary,terms: Dictionary={}) -> int:
	if evidence.is_empty() or evidence.size()>64:return 0
	var r: Dictionary=rules() if terms.is_empty() else terms;var best: int=0;var seen: Dictionary={}
	for raw: Variant in evidence:
		if not raw is Dictionary or not FormalLedgerState.exact_fields(raw,["seller","seller_site","quote_id","price","freight","route_id"]):return 0
		for key: String in ["seller","seller_site","quote_id","route_id"]:
			if not raw[key] is String:return 0
		if not FormalLedgerState.valid_amount(raw["price"]) or raw["price"]<=0 or not FormalLedgerState.valid_amount(raw["freight"]) or not e._spec["sites"].has(raw["seller_site"]) or e._owner(raw["seller_site"])!=raw["seller"] or seen.has(raw["quote_id"]):return 0
		seen[raw["quote_id"]]=true
		var introduced: bool=false
		for m: Variant in native["receipts"].values():
			if not m is Dictionary:return 0
			if m.get("actor")==r["buyer_site"] and m.get("kind")=="supplier" and m.get("candidate")==raw["seller"]+"|"+r["good"]+"|"+raw["seller_site"] and int(m.get("delivery_day",999999))*1440<=minute:introduced=true
		if not introduced:return 0
		var freight: int=-1
		for path: Dictionary in e._paths_for(r["buyer"],e._place(raw["seller_site"]),e._place(r["buyer_site"]),minute/1440):
			if path["id"]==raw["route_id"]:freight=e._freight(e._locked_legs(path,FormalLedgerState.DENOMINATION))
		if freight!=raw["freight"]:return 0
		var expected: int=int(e._spec["sites"][raw["seller_site"]]["prices"].get(r["good"],0))
		var quote_id: String=e._quote_id(minute,r["buyer"],raw["seller"],r["good"],raw["route_id"],raw["seller_site"],r["buyer_site"])
		if not e._local_quotes.rule(raw["seller_site"],r["good"]).is_empty():
			var known: Dictionary=e._local_quotes.known(r["buyer_site"],raw["seller_site"],r["good"],minute)
			if known.is_empty() or not e._local_quotes.reason(r["buyer_site"],raw["seller_site"],r["good"],minute).is_empty():return 0
			expected=int(known["price"]);quote_id+="|"+str(known["id"])
		elif not e._price_policy(raw["seller_site"],r["good"]).is_empty() and e._price_policy(raw["seller_site"],r["good"])["mode"]!="N2":return 0
		if expected!=raw["price"] or quote_id!=raw["quote_id"]:return 0
		var landed: int=expected+freight
		if best==0 or landed<best:best=landed
	return best

# Optional 0.8 mandates are finite purchasing authority, never a money balance.
static func valid_opportunity_configuration(cfg: Dictionary) -> bool:
	var policies_value: Variant=cfg.get("supply_opportunity_policies",[])
	if not policies_value is Array or policies_value.size()>8:return false
	if not policies_value.is_empty() and not cfg.has("supply_contracts"):return false
	var sites: Dictionary={};var seen: Dictionary={}
	for f: Dictionary in cfg.get("firms",[]):
		for s: Dictionary in f["sites"]:sites[s["id"]]={"firm":f["id"],"site":s}
	for p: Variant in policies_value:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["id","buyer","buyer_site","supplier","supplier_site","good","max_quantity","days","premium","cooldown_days","notice_days","max_publications","max_commitment","basis"]):return false
		for key: String in ["id","buyer","buyer_site","supplier","supplier_site","good"]:
			if not p[key] is String or p[key].is_empty():return false
		for key: String in ["max_quantity","days","premium","cooldown_days","notice_days","max_publications","max_commitment"]:
			if not FormalLedgerState.valid_amount(p[key]) or p[key]<=0:return false
		if seen.has(p["id"]) or p["basis"]!="EXPLICIT_DEVELOPMENT_PROCUREMENT_MANDATE" or p["days"]>30 or p["max_publications"]>16 or p["max_quantity"]>1000 or p["notice_days"]>=p["days"]:return false
		seen[p["id"]]=true
		if not sites.has(p["buyer_site"]) or not sites.has(p["supplier_site"]) or sites[p["buyer_site"]]["firm"]!=p["buyer"] or sites[p["supplier_site"]]["firm"]!=p["supplier"] or p["buyer"]==p["supplier"]:return false
		var b: Dictionary=sites[p["buyer_site"]]["site"];var s: Dictionary=sites[p["supplier_site"]]["site"]
		if b["place_id"]!=s["place_id"] or not b["stock"].has(p["good"]) or not s["prices"].has(p["good"]):return false
		var needed: bool=int(b["targets"].get(p["good"],0))>0
		for a: Dictionary in b["activities"]:
			if int(a["materials"].get(p["good"],0))>0:needed=true
		if not needed:return false
	return true

func source_receipt(p: Dictionary,receipts: Dictionary) -> String:
	var candidate: String=p["supplier"]+"|"+p["good"]+"|"+p["supplier_site"]
	for id: String in receipts:
		var r: Dictionary=receipts[id]
		if r.get("actor")==p["buyer_site"] and r.get("kind")=="supplier" and r.get("candidate")==candidate:return id
	return ""

func need_quantity(p: Dictionary) -> int:
	var need: Dictionary = e._input_need(p["buyer_site"], p["good"])
	# The published deadline is the offered commitment, never an assurance of
	# earlier delivery. Existing parent and child responsibilities are already
	# accounted once by the native timing observation.
	var due: int = int(p["deadline"]) / 1440 if p.has("deadline") else e.day + int(p["days"])
	return int(e._input_candidate_need(need, due, int(p.get("max_quantity", p.get("quantity", 1000000))))["quantity"])

func mandate_used(policy_id: String) -> int:
	var used: int=0
	for id: String in records:
		if notices.get(id,{}).get("policy_id")==policy_id:used+=int(records[id]["quantity"])*int(records[id]["price"])
	return used

func budget_supported(p: Dictionary) -> bool:
	# Fail closed for richer budget windows until native future-claim splitting exists.
	var subject: String=str(e._budgets.subject_aliases.get(p["buyer"],p["buyer"]))
	for r: Dictionary in e._budgets.rules:
		if r["subject"]==subject and r["category"]=="goods:"+p["good"]:return false
	return true

func publication_ready(p: Dictionary) -> bool:
	if not budget_supported(p) or not e._site_accepting(p["buyer_site"]) or e._firm_winding_down(p["buyer"]) or source_receipt(p,e._receipts).is_empty():return false
	var count: int=0;var last: int=-999999
	for n: Dictionary in notices.values():
		if n["policy_id"]!=p["id"]:continue
		count+=1;last=maxi(last,int(n["published_minute"])/1440)
		if not records.has(n["id"]) and e._world.game_clock.total_minutes()<=int(n["terms"]["deadline"]):return false
	return count<int(p["max_publications"]) and e.day-last>=int(p["cooldown_days"]) and need_quantity(p)>0 and mandate_used(p["id"])<int(p["max_commitment"])

func publish(actor: String,payload: Dictionary,action_id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload,["policy_id"]):return e._result(false,"INVALID_PROCUREMENT_NOTICE")
	var p: Dictionary=policy(str(payload["policy_id"]))
	if p.is_empty() or actor!=p["buyer"] or not publication_ready(p):return e._result(false,"NO_CURRENT_AUTHORIZED_PROCUREMENT_NEED")
	var index: int=1
	for n: Dictionary in notices.values():
		if n["policy_id"]==p["id"]:index+=1
	var id: String=p["id"]+":"+str(index)
	var terms: Dictionary=p.duplicate(true)
	terms["id"]=id;terms["quantity"]=mini(int(p["max_quantity"]),need_quantity(p));terms["deadline"]=(e.day+int(p["days"]))*1440
	var quote: Dictionary=_priced_offer(terms)
	var amount: int=int(quote["price"])*int(terms["quantity"])
	if amount<=0 or amount>int(p["max_commitment"])-mandate_used(p["id"]):return e._result(false,"PROCUREMENT_MANDATE_OR_CASH_LIMIT")
	var route: Dictionary=e._route_for(p["buyer"],p["supplier"],"",p["buyer_site"],p["supplier_site"])
	if route.is_empty() or e._freight(e._locked_legs(route,FormalLedgerState.DENOMINATION))!=0:return e._result(false,"NO_AUTHORIZED_LOCAL_DELIVERY")
	var n: Dictionary={"id":id,"policy_id":p["id"],"terms":terms,"price":quote["price"],"evidence":quote["evidence"],"published_minute":e._world.game_clock.total_minutes(),"publication_action":action_id,"source_receipt":source_receipt(p,e._receipts),"observed_need":need_quantity(p),"cash_at_publication":quote["buyer_available"]}
	notices[id]=n
	e._messages.append({"id":"supply_notice:"+id,"actor":p["supplier_site"],"kind":"supply_opportunity","candidate":id,"observed_day":e.day,"delivery_day":e.day+int(p["notice_days"]),"source_receipt":n["source_receipt"]})
	return {"accepted":true,"reason":"AUTHORIZED_PROCUREMENT_NOTICE_PUBLISHED","notice":n.duplicate(true)}

func known_notice(id: String) -> bool:
	var receipts: Dictionary=restore_receipts if not restore_receipts.is_empty() else e._receipts
	return receipts.has("supply_notice:"+id) and int(receipts["supply_notice:"+id]["delivery_day"])*1440<=e._world.game_clock.total_minutes()

func notice_offer(id: String) -> Dictionary:
	var n: Dictionary=notices[id];var r: Dictionary=n["terms"];var p: Dictionary=policy(n["policy_id"])
	var cash: int=e._world.ledger_state.available_balance(e._account(r["buyer"]))
	var reason: String="RECRUITING"
	if e._world.game_clock.total_minutes()>int(r["deadline"]):reason="OVERDUE"
	elif need_quantity(r)<int(r["quantity"]):reason="NEED_ALREADY_COVERED"
	elif cash<int(r["quantity"])*int(n["price"]):reason="BUYER_FUNDS_UNAVAILABLE"
	elif not budget_supported(p) or mandate_used(p["id"])+int(r["quantity"])*int(n["price"])>int(p["max_commitment"]):reason="PROCUREMENT_MANDATE_EXHAUSTED"
	return {"id":id,"buyer":r["buyer"],"buyer_site":r["buyer_site"],"good":r["good"],"quantity":r["quantity"],"days":r["days"],"price":n["price"],"buyer_available":cash,"evidence":n["evidence"].duplicate(true),"minute":e._world.game_clock.total_minutes(),"status":reason,"published_minute":n["published_minute"],"deadline":r["deadline"],"penalty":0,"ready":reason=="RECRUITING","source":"supply_notice:"+id,"authority_basis":p["basis"]}

func views(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var original: Dictionary=view(actor)
	if not original.is_empty():result.append(original)
	for id: String in notices:
		var row: Dictionary=view(actor,id)
		if not row.is_empty():result.append(row)
	return result

func valid_message(m: Dictionary) -> bool:
	if not FormalLedgerState.exact_fields(m,["id","actor","kind","candidate","observed_day","delivery_day","source_receipt"]) or not notices.has(m["candidate"]):return false
	var n: Dictionary=notices[m["candidate"]];var p: Dictionary=policy(n["policy_id"])
	return m["id"]=="supply_notice:"+n["id"] and m["actor"]==p["supplier_site"] and m["kind"]=="supply_opportunity" and m["source_receipt"]==n["source_receipt"] and m["observed_day"]==int(n["published_minute"])/1440 and m["delivery_day"]==int(m["observed_day"])+int(p["notice_days"])

func restore_notices(value: Dictionary) -> bool:
	if notices.size()>128:return fail("Procurement notice bound")
	var counts: Dictionary={};var last: Dictionary={}
	for id: Variant in notices:
		var n: Variant=notices[id]
		if not n is Dictionary or not FormalLedgerState.exact_fields(n,["id","policy_id","terms","price","evidence","published_minute","publication_action","source_receipt","observed_need","cash_at_publication"]):return fail("Invalid procurement notice")
		for field: String in ["id","policy_id","publication_action","source_receipt"]:
			if not n[field] is String:return fail("Invalid publication identity")
		var p: Dictionary=policy(str(n["policy_id"]))
		if p.is_empty() or not n["terms"] is Dictionary or not n["evidence"] is Array:return fail("Missing purchasing mandate")
		for key: String in ["price","published_minute","observed_need","cash_at_publication"]:
			if not FormalLedgerState.valid_amount(n[key]):return fail("Invalid publication amount")
		var count: int=int(counts.get(p["id"],0))+1;counts[p["id"]]=count
		if count>int(p["max_publications"]) or id!=p["id"]+":"+str(count) or n["id"]!=id:return fail("Publication sequence conflict")
		var terms: Dictionary=p.duplicate(true);terms["id"]=id;terms["quantity"]=mini(int(p["max_quantity"]),int(n["observed_need"]));terms["deadline"]=(int(n["published_minute"])/1440+int(p["days"]))*1440
		if n["terms"]!=terms or terms["quantity"]<=0 or n["published_minute"]>e._world.game_clock.total_minutes() or int(n["published_minute"])/1440-int(last.get(p["id"],-999999))<int(p["cooldown_days"]):return fail("Publication terms or cadence conflict")
		last[p["id"]]=int(n["published_minute"])/1440
		var source: String=source_receipt(p,value.get("receipts",{}))
		if source.is_empty() or source!=n["source_receipt"] or int(value["receipts"][source]["delivery_day"])*1440>int(n["published_minute"]):return fail("Publication lacks legal information source")
		var reference: int=evidence_reference(n["evidence"],n["published_minute"],value,terms)
		if reference<=0 or n["price"]<=0 or n["price"]!=mini(reference+int(p["premium"]),int(n["cash_at_publication"])/int(terms["quantity"])):return fail("Publication lacks funded quotation basis")
		var used_at_publication: int=0
		var native_contracts: Dictionary=value.get("supply_contracts",{}).get("contracts",{})
		for contract: Variant in native_contracts.values():
			if not contract is Dictionary:return fail("Malformed historical supply contract")
			if notices.get(contract.get("id"),{}).get("policy_id")==p["id"] and int(contract.get("accepted_minute",-1))<=int(n["published_minute"]):used_at_publication+=int(contract.get("quantity",0))*int(contract.get("price",0))
		if int(terms["quantity"])*int(n["price"])+used_at_publication>int(p["max_commitment"]):return fail("Publication exceeds remaining procurement mandate")
		var entry: Dictionary=value.get("commands",{}).get(n["publication_action"],{})
		var command: Dictionary=entry.get("envelope",{}).get("command",{})
		if entry.get("envelope",{}).get("actor")!=p["buyer"] or command.get("kind")!="publish_supply_opportunity" or command.get("minute")!=n["published_minute"] or command.get("payload")!={"policy_id":p["id"]} or entry.get("result",{}).get("notice")!=n or not entry.get("result",{}).get("accepted",false):return fail("Publication authority journal lost")
	for entry: Dictionary in value.get("commands",{}).values():
		var command: Dictionary=entry.get("envelope",{}).get("command",{})
		if command.get("kind")=="publish_supply_opportunity" and entry.get("result",{}).get("accepted",false):
			var id: String=str(entry["result"].get("notice",{}).get("id",""))
			if not notices.has(id) or notices[id]["publication_action"]!=command.get("action_id"):return fail("Orphan successful publication")
	for id: String in notices:
		if not budget_supported(policy(notices[id]["policy_id"])):return fail("Unsupported future procurement budget")
		var found: int=0
		for m: Dictionary in value.get("messages",[])+value.get("receipts",{}).values():
			if m.get("kind")=="supply_opportunity" and m.get("candidate")==id:
				if not valid_message(m):return fail("Invalid notice delivery")
				found+=1
		if found!=1:return fail("Missing or duplicated procurement information delivery")
	return true

func procurement_hold(site: String,good: String) -> int:
	# Compatibility total responsibility query. ETA must be evaluated separately;
	# deadlines never make unallocated stock a physically scheduled arrival.
	var held: int = 0
	for row: Dictionary in records.values():
		if row["buyer_site"] == site and row["good"] == good and int(row["ended_minute"]) < 0:
			held += maxi(0, int(row["quantity"]) - int(row["allocated"]))
	return held
