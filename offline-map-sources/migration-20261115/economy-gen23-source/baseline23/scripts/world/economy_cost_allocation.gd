class_name EconomyCostAllocation
extends RefCounted
## Cost provenance and allocations only. Lots, wages, contracts and Ledger remain
## the physical and financial authorities. No cost record supplies money or goods.
const FORMAT := "economy_cost_allocation_v1"
var enabled: bool = false
var start_minute: int = 0
var bases: Dictionary = {}
var bindings: Dictionary = {}
var productions: Dictionary = {}
var sales: Dictionary = {}
var capital_materials: Dictionary = {}
var loss_allocations: Dictionary = {}
var work_allocations: Dictionary = {}
var service_materials: Dictionary = {}
var _service_work: Dictionary = {}
var _ref: WeakRef
var _sales_days: Dictionary = {}
var _production_days: Dictionary = {}
var _project_work: Dictionary = {}
var _work_days: Dictionary = {}
var _firm_projects: Dictionary = {}
var _loss_days: Dictionary = {}
var _handling_work: Dictionary = {} # Derived from actual wage allocations.
var _asset_maintenance: Dictionary = {}
var _scores_cache: Dictionary = {}

func economy() -> RefCounted:
	return _ref.get_ref() if _ref != null else null

static func valid_configuration(settings: Dictionary) -> bool:
	if not settings.has("cost_accounting"): return true
	var c: Variant = settings["cost_accounting"]
	if not c is Dictionary or not FormalLedgerState.exact_fields(c,["freight_treatment","joint_allocations","npc_policies","basis"]) or c["freight_treatment"] not in ["SEPARATE_EXPENSE","BUYER_ACQUISITION"] or c["basis"]!="EXPLICIT_DEVELOPMENT_COST_POLICY": return false
	if not c["joint_allocations"] is Array or c["joint_allocations"].size()>64 or not c["npc_policies"] is Array or c["npc_policies"].size()>32: return false
	var sites: Dictionary = {}
	var firms: Dictionary = {}
	if not settings.get("firms") is Array: return false
	for f: Variant in settings["firms"]:
		if not f is Dictionary or not f.get("id") is String or not f.get("sites") is Array: return false
		firms[f["id"]]=true
		for s: Variant in f["sites"]:
			if not s is Dictionary or not s.get("id") is String or not s.get("activities") is Array: return false
			sites[s["id"]]=s
	var ids: Dictionary = {}
	for r: Variant in c["joint_allocations"]:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["site","activity","weights","basis"]) or not r["site"] is String or not r["activity"] is String or not sites.has(r["site"]) or r["basis"]!="EXPLICIT_JOINT_COST_WEIGHTS" or not r["weights"] is Dictionary: return false
		var key: String=r["site"]+"|"+r["activity"]
		if ids.has(key): return false
		ids[key]=true
		var outputs: Dictionary = {}
		for a: Dictionary in sites[r["site"]]["activities"]:
			if a["id"]==r["activity"]: outputs=a["outputs"]
		if outputs.size()<2 or r["weights"].size()!=outputs.size(): return false
		for good: String in outputs:
			if not FormalLedgerState.valid_amount(r["weights"].get(good)) or int(r["weights"][good])<1 or int(r["weights"][good])>1000: return false
	ids.clear()
	for r: Variant in c["npc_policies"]:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["firm","window_days","rank_production","block_known_loss_investment","basis"]) or not firms.has(r.get("firm")) or ids.has(r["firm"]) or not FormalLedgerState.valid_amount(r["window_days"]) or int(r["window_days"])<1 or int(r["window_days"])>30 or not r["rank_production"] is bool or not r["block_known_loss_investment"] is bool or r["basis"]!="EXPLICIT_DEVELOPMENT_COST_RESPONSE": return false
		ids[r["firm"]]=true
	return true

func bind(kernel: RefCounted) -> void:
	_ref=weakref(kernel)
	enabled=kernel.config.has("cost_accounting")
	# Disabled accounting has no historical window; keep its projection stable on restore.
	# Enabled accounting still uses the actual boundary and restores recorded provenance.
	start_minute=kernel._world.game_clock.total_minutes() if enabled else 0

func policy(firm: String) -> Dictionary:
	for p: Dictionary in economy().config.get("cost_accounting",{}).get("npc_policies",[]):
		if p["firm"]==firm: return p
	return {}

func observe_work(id: String) -> void:
	if not enabled: return
	var w:=economy()._wages[id] as Dictionary
	if int(w["work_day"])*1440<=start_minute and start_minute>0: return
	if not _work_days.has(w["employer"]): _work_days[w["employer"]]={}
	if not _work_days[w["employer"]].has(w["work_day"]): _work_days[w["employer"]][w["work_day"]]=[]
	_work_days[w["employer"]][w["work_day"]].append(id)

## Exact cumulative integer allocation without floating point or overflowing a*b.
static func fraction(amount: int, numerator: int, denominator: int) -> int:
	assert(amount>=0 and numerator>=0 and numerator<=denominator and denominator>0)
	var bits: Array[int]=[]
	var n:=numerator
	while n>0:
		bits.append(n%2)
		n/=2
	var q:=0
	var remainder:=0
	for i: int in range(bits.size()-1,-1,-1):
		q*=2
		remainder*=2
		if remainder>=denominator:
			q+=1
			remainder-=denominator
		if bits[i]==1:
			q+=amount/denominator
			remainder+=amount%denominator
			if remainder>=denominator:
				q+=1
				remainder-=denominator
	return q

static func empty_cost() -> Dictionary:
	return {"amounts":{},"unknown":[]}

static func combine(target: Dictionary, part: Dictionary) -> void:
	for currency: String in part["amounts"]:
		var value:=int(part["amounts"][currency])
		if value>FormalLedgerState.MAX_AMOUNT-int(target["amounts"].get(currency,0)):
			if not target["unknown"].has("COST_AMOUNT_OUT_OF_RANGE"): target["unknown"].append("COST_AMOUNT_OUT_OF_RANGE")
		else: target["amounts"][currency]=int(target["amounts"].get(currency,0))+value
	for reason: String in part["unknown"]:
		if not target["unknown"].has(reason): target["unknown"].append(reason)

func _basis(id: String, kind: String, owner: String, quantity: int, cost: Dictionary, refs: Dictionary, minute: int) -> void:
	assert(not bases.has(id) and quantity>0)
	bases[id]={"id":id,"kind":kind,"owner":owner,"quantity":quantity,"minute":minute,"amounts":cost["amounts"].duplicate(true),"unknown":cost["unknown"].duplicate(),"refs":refs.duplicate(true)}

func portion_added(p: Dictionary) -> void:
	if not enabled: return
	var parent:=str(p["parent_portion_id"])
	if bindings.has(parent):
		var prior:=economy()._lots.portions[parent] as Dictionary
		bindings[p["id"]]={"basis":bindings[parent]["basis"],"offset":int(bindings[parent]["offset"])+int(prior["quantity"])-int(prior["remaining"])-int(p["quantity"])}
	else:
		var id: String="unknown:"+str(p["id"])
		_basis(id,"UNKNOWN",p["owner"],p["quantity"],{"amounts":{},"unknown":["OPENING_OR_PRE_COST_SOURCE_UNKNOWN"]},{"portion":p["id"]},maxi(start_minute,int(p["opened_minute"])))
		bindings[p["id"]]={"basis":id,"offset":0}

func ranges(rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var selected: Dictionary={}
	if not enabled: return result
	for row: Dictionary in rows:
		var p:=economy()._lots.portions[row["portion_id"]] as Dictionary
		var binding:=bindings[p["id"]] as Dictionary
		result.append({"portion":p["id"],"basis":binding["basis"],"offset":int(binding["offset"])+int(p["quantity"])-int(p["remaining"])+int(selected.get(p["id"],0)),"quantity":row["quantity"]})
		selected[p["id"]]=int(selected.get(p["id"],0))+int(row["quantity"])
	return result

func cost_of(rows: Array) -> Dictionary:
	var result:=empty_cost()
	for r: Dictionary in rows:
		var b:=bases[r["basis"]] as Dictionary
		var part:={"amounts":{},"unknown":b["unknown"]}
		for currency: String in b["amounts"]:
			part["amounts"][currency]=fraction(b["amounts"][currency],int(r["offset"])+int(r["quantity"]),b["quantity"])-fraction(b["amounts"][currency],r["offset"],b["quantity"])
		combine(result,part)
	return result

func _assign(rows: Array[Dictionary], basis: String) -> void:
	var offset:=0
	for r: Dictionary in rows:
		bindings[r["portion_id"]]={"basis":basis,"offset":offset}
		offset+=int(r["quantity"])
	assert(offset==int(bases[basis]["quantity"]))

func assigned_hours(work: String) -> int:
	var hours:=0
	for r: Dictionary in work_allocations.get(work,[]): hours+=int(r["hours"])
	return hours

func assign_work(work: String, hours: int, purpose: String, reference: String) -> Dictionary:
	var e:=economy()
	var offset:=assigned_hours(work)
	var claim:=e._wages[work] as Dictionary
	assert(hours>0 and hours<=int(claim["hours"])-offset)
	var value:=fraction(claim["amount"],offset+hours,claim["hours"])-fraction(claim["amount"],offset,claim["hours"])
	var r:={"work":work,"hours":hours,"offset":offset,"purpose":purpose,"reference":reference}
	if not work_allocations.has(work): work_allocations[work]=[]
	work_allocations[work].append(r)
	if purpose=="CAPITAL":
		_index_project(reference)
		if not _project_work.has(reference): _project_work[reference]=[]
		_project_work[reference].append(r)
	elif purpose=="HANDLING":
		if not _handling_work.has(reference): _handling_work[reference]=[]
		_handling_work[reference].append(r)
	elif purpose=="SERVICE":
		if not _service_work.has(reference): _service_work[reference]=[]
		_service_work[reference].append(r)
	return {"amounts":{str(claim["denomination"]):value},"unknown":[]}

func production(site: String, activity: String, batches: int, inputs: Array[Dictionary]) -> String:
	if not enabled or batches<=0: return ""
	var e:=economy()
	var id:="production:"+str(e.day)+":"+site+":"+activity
	var selected:=ranges(inputs)
	var cost:=cost_of(selected)
	var hours:=batches*int(e._activity(site,activity)["hours"])
	for work: String in e._capital_work_ids:
		if e._spec["jobs"][e._work_records[work]["job"]]["site_id"]!=site: continue
		var q:=mini(hours,int(e._work_records[work]["hours"])-assigned_hours(work))
		if q<=0: continue
		combine(cost,assign_work(work,q,"PRODUCTION",id))
		hours-=q
		if hours==0: break
	if hours>0: cost["unknown"].append("PRODUCTION_WORK_ALLOCATION_MISSING")
	productions[id]={"site":site,"activity":activity,"day":e.day,"batches":batches,"inputs":selected,"cost":cost,"outputs":{}}
	_index_production(id)
	return id

func output(production_id: String, source: String) -> void:
	if not enabled or production_id.is_empty(): return
	var e:=economy()
	var p:=productions[production_id] as Dictionary
	var s:=e._lots.sources[source] as Dictionary
	p["outputs"][s["good"]]=source
	var outputs:=e._activity(p["site"],p["activity"])["outputs"] as Dictionary
	var cost:=p["cost"] as Dictionary
	var weights: Dictionary={}
	if outputs.size()>1:
		for r: Dictionary in e.config["cost_accounting"]["joint_allocations"]:
			if r["site"]==p["site"] and r["activity"]==p["activity"]: weights=r["weights"]
		if weights.is_empty(): cost={"amounts":{},"unknown":["JOINT_OUTPUT_ALLOCATION_UNCONFIGURED"]}
		else:
			var goods: Array=outputs.keys()
			goods.sort()
			var total:=0
			var before:=0
			for good: String in goods: total+=int(weights[good])
			for good: String in goods:
				if good==s["good"]: break
				before+=int(weights[good])
			cost={"amounts":{},"unknown":p["cost"]["unknown"]}
			for currency: String in p["cost"]["amounts"]:
				var amount:=int(p["cost"]["amounts"][currency])
				cost["amounts"][currency]=fraction(amount,before+int(weights[s["good"]]),total)-fraction(amount,before,total)
	var id:="output:"+source
	_basis(id,"OUTPUT",e._owner(p["site"]),s["quantity"],cost,{"production":production_id,"source":source,"weights":weights},s["formed_minute"])
	var portion:="portion:"+str(e._lots.next_id-1)
	bases.erase("unknown:"+portion) # No acquisition or use occurred before this adoption.
	bindings[portion]={"basis":id,"offset":0}

func delivery(id: String, order: Dictionary, prior: Array[Dictionary], moved: Array[Dictionary]) -> void:
	if not enabled: return
	var e:=economy()
	var receipt:=e._delivery_receipts[id] as Dictionary
	var q:=int(receipt["quantity"])
	if order["kind"]=="SALE":
		sales[id]=prior.duplicate(true)
		_index_sale(id)
	if order["kind"]=="PERSONAL_FREIGHT": return
	var cost:=empty_cost() if order["kind"]=="SALE" else cost_of(prior)
	if order["kind"]=="SALE": cost["amounts"][order["denomination"]]=q*int(order["price"])
	var capitalize: bool=e.config["cost_accounting"]["freight_treatment"]=="BUYER_ACQUISITION"
	if capitalize:
		combine(cost,_freight_cost(order,q))
	var basis:="acquisition:"+id
	_basis(basis,"ACQUISITION",order["buyer"],q,cost,{"receipt":id,"prior":prior,"capitalized_freight":capitalize},receipt["delivered_minute"])
	_assign(moved,basis)

func _freight_cost(order: Dictionary, quantity: int) -> Dictionary:
	var result:=empty_cost()
	var amount:=0
	for leg: Dictionary in order["route_legs"]:
		if int(leg["freight_per_unit"])==0: continue
		if leg["carrier_account"]==order["buyer_account"]:
			if not result["unknown"].has("OWN_CARRIER_COST_ALLOCATION_UNCONFIGURED"): result["unknown"].append("OWN_CARRIER_COST_ALLOCATION_UNCONFIGURED")
		else: amount+=quantity*int(leg["freight_per_unit"])
	if amount>0: result["amounts"][order["denomination"]]=amount
	return result

func capital_inputs(project: String, inputs: Array[Dictionary]) -> void:
	if enabled:
		capital_materials[project]=ranges(inputs)
		_index_project(project)

func lost(id: String, rows: Array[Dictionary]) -> void:
	if enabled:
		_scores_cache.clear()
		loss_allocations[id]=ranges(rows)
		_index_loss(id,economy()._world.game_clock.total_minutes())

func _index_loss(id: String, minute: int) -> void:
	var owners: Dictionary={}
	for row: Dictionary in economy()._lots.losses.get(id,{}).get("portions",[]): owners[economy()._lots.portions[row["portion_id"]]["owner"]]=true
	# During physical adoption StockLots has not yet published the loss row.
	for row: Dictionary in loss_allocations.get(id,[]): owners[economy()._lots.portions[row["portion"]]["owner"]]=true
	for owner: String in owners:
		if not _loss_days.has(owner): _loss_days[owner]={}
		var date:=minute/1440
		if not _loss_days[owner].has(date): _loss_days[owner][date]=[]
		_loss_days[owner][date].append(id)

func _index_project(project: String) -> void:
	var p:=economy()._capital.projects[project] as Dictionary
	var firm:=str(p["firm"])
	if not _firm_projects.has(firm): _firm_projects[firm]=[]
	if not _firm_projects[firm].has(project): _firm_projects[firm].append(project)
	if p["kind"]=="MAINTENANCE":
		if not _asset_maintenance.has(p["asset_id"]): _asset_maintenance[p["asset_id"]]=[]
		if not _asset_maintenance[p["asset_id"]].has(project): _asset_maintenance[p["asset_id"]].append(project)

func _index_sale(id: String) -> void:
	_scores_cache.clear()
	var e:=economy()
	var r:=e._delivery_receipts[id] as Dictionary
	var o:=e._orders[r["order_id"]] as Dictionary
	var key:=str(o["seller_site"])
	if not _sales_days.has(key): _sales_days[key]={}
	if not _sales_days[key].has(r["delivered_day"]): _sales_days[key][r["delivered_day"]]=[]
	_sales_days[key][r["delivered_day"]].append(id)

func _index_production(id: String) -> void:
	var p:=productions[id] as Dictionary
	var key:=str(p["site"])
	if not _production_days.has(key): _production_days[key]={}
	if not _production_days[key].has(p["day"]): _production_days[key][p["day"]]=[]
	_production_days[key][p["day"]].append(id)

func view(firm: String, window: int) -> Dictionary:
	var result:={"enabled":enabled,"start_minute":start_minute,"basis":"KNOWN_DIRECT_COST_AND_LIMITED_GROSS_CONTRIBUTION_NOT_NET_PROFIT","sales_revenue":{},"comparable_revenue":{},"sold_known_cost":{},"contribution":{},"unknown_sales":0,"inventory":{},"joint_outputs":[],"production_batches":[],"capital_projects":[],"loss_known_cost":{},"unallocated_wages":{}}
	if not enabled: return result
	var e:=economy()
	result["unknown_loss_events"]=0
	result["incomparable_sales"]=0
	for id: String in e._lots._by_owner.get(firm,{}):
		var p:=e._lots.portions[id] as Dictionary
		if not result["inventory"].has(p["good"]): result["inventory"][p["good"]]={"known_cost":{},"unknown_portions":0,"owned_quantity":0,"available_at_site":0,"reserved_quantity":0,"cargo_quantity":0,"unknown_cost_quantity":0}
		var stock:=result["inventory"][p["good"]] as Dictionary
		stock["owned_quantity"]+=int(p["remaining"])
		if str(p["location"]).begins_with("SITE|") and str(p["reserved_for"]).is_empty(): stock["available_at_site"]+=int(p["remaining"])
		if not str(p["reserved_for"]).is_empty(): stock["reserved_quantity"]+=int(p["remaining"])
		if str(p["location"]).begins_with("CARGO|"): stock["cargo_quantity"]+=int(p["remaining"])
		var cost:=cost_of(ranges([{ "portion_id":id,"source_id":p["source_id"],"quantity":p["remaining"] }]))
		for currency: String in cost["amounts"]: result["inventory"][p["good"]]["known_cost"][currency]=int(result["inventory"][p["good"]]["known_cost"].get(currency,0))+int(cost["amounts"][currency])
		if not cost["unknown"].is_empty():
			stock["unknown_portions"]+=1
			stock["unknown_cost_quantity"]+=int(p["remaining"])
	for site: String in e._site_ids():
		if e._owner(site)!=firm: continue
		for date: int in range(maxi(0,e.day-window+1),e.day+1):
			for id: String in _sales_days.get(site,{}).get(date,[]):
				var r:=e._delivery_receipts[id] as Dictionary
				var o:=e._orders[r["order_id"]] as Dictionary
				var currency:=str(o["denomination"])
				var revenue:=int(r["quantity"])*int(o["price"])
				result["sales_revenue"][currency]=int(result["sales_revenue"].get(currency,0))+revenue
				var cost:=cost_of(sales[id])
				for unit: String in cost["amounts"]: result["sold_known_cost"][unit]=int(result["sold_known_cost"].get(unit,0))+int(cost["amounts"][unit])
				if not cost["unknown"].is_empty():
					result["unknown_sales"]+=1
					continue
				if cost["amounts"].size()>1 or (cost["amounts"].size()==1 and not cost["amounts"].has(currency)):
					result["incomparable_sales"]+=1
					continue
				result["comparable_revenue"][currency]=int(result["comparable_revenue"].get(currency,0))+revenue
				var margin:=revenue-int(cost["amounts"].get(currency,0))
				result["contribution"][currency]=int(result["contribution"].get(currency,0))+margin
			for id: String in _production_days.get(site,{}).get(date,[]):
				var p:=productions[id] as Dictionary
				if result["production_batches"].size()<8: result["production_batches"].append({"id":id,"site":site,"activity":p["activity"],"day":p["day"],"batches":p["batches"],"cost":p["cost"].duplicate(true),"output_sources":p["outputs"].duplicate()})
				if p["outputs"].size()>1 and result["joint_outputs"].size()<8: result["joint_outputs"].append({"id":id,"outputs":p["outputs"],"total_direct_cost":p["cost"],"allocation":"EXPLICIT_WEIGHTS" if _has_weights(site,p["activity"]) else "UNCONFIGURED"})
	var projects: Array=_firm_projects.get(firm,[])
	for index: int in range(maxi(0,projects.size()-8),projects.size()):
		var project:=str(projects[index])
		var p:=e._capital.projects[project] as Dictionary
		if result["capital_projects"].size()<8: result["capital_projects"].append({"id":project,"cost":project_cost(project),"kind":p["kind"],"cost_classification":"MAINTENANCE_EXPENSE_UNCAPITALIZED" if p["kind"]=="MAINTENANCE" else "CAPITAL_FORMATION","asset_id":p.get("asset_id",""),"status":p["status"]})
	result["loss_records"]=[]
	result["loss_basis"]="PHYSICAL_OWNER_COST_NOT_FINAL_CONTRACT_LIABILITY"
	for date: int in range(maxi(0,e.day-window+1),e.day+1):
		for id: String in _loss_days.get(firm,{}).get(date,[]):
			if not _known_loss(firm,id): continue
			var selected: Array=[]
			for r: Dictionary in loss_allocations.get(id,[]):
				if e._lots.portions[r["portion"]]["owner"]==firm: selected.append(r)
			var cost:=cost_of(selected) if loss_allocations.has(id) else {"amounts":{},"unknown":["LEGACY_LOSS_COST_UNRECORDED"]}
			if not cost["unknown"].is_empty(): result["unknown_loss_events"]+=1
			for currency: String in cost["amounts"]: result["loss_known_cost"][currency]=int(result["loss_known_cost"].get(currency,0))+int(cost["amounts"][currency])
			if result["loss_records"].size()<8: result["loss_records"].append(loss_view(id))
		for work: String in _work_days.get(firm,{}).get(date,[]):
			var claim:=e._wages[work] as Dictionary
			var remaining:=int(claim["hours"])-assigned_hours(work)
			if remaining>0:
				var amount:=int(claim["amount"])-fraction(claim["amount"],assigned_hours(work),claim["hours"])
				result["unallocated_wages"][claim["denomination"]]=int(result["unallocated_wages"].get(claim["denomination"],0))+amount
	result["activity_observations"]={}
	for site: String in e._spec["firms"][firm]["sites"]: result["activity_observations"][site]=activity_scores(site,window)
	result["sales_refunds_paid"]={}
	result["contribution_after_known_refunds"]=result["contribution"].duplicate()
	result["refunds_without_comparable_sale"]={}
	result["separate_transport_expense"]={}
	result["handling_wages_incurred"]={}
	result["acquisition_refunds_received"]={}
	result["unfulfilled_purchase_obligations"]={}
	result["delivered_sale_payment_basis"]="ORIGINAL_LEDGER_BATCH_PAYMENT_BEFORE_PHYSICAL_ADOPTION"
	for id: String in e._active_by_buyer.get(firm,{}):
		var order:=e._orders[id] as Dictionary
		var amount: int=(int(order["pending"])+int(order["transit"]))*int(order["price"])
		result["unfulfilled_purchase_obligations"][order["denomination"]]=int(result["unfulfilled_purchase_obligations"].get(order["denomination"],0))+amount
	for tx: Dictionary in e._world.ledger_state.own_transactions(firm,maxi(0,e.day-window+1)*1440):
		var currency:=str(tx["denomination"])
		if tx["kind"]=="cargo_refund" and tx["to_account_id"]==e._account(firm,currency): result["acquisition_refunds_received"][currency]=int(result["acquisition_refunds_received"].get(currency,0))+int(tx["amount"])
		if tx["from_account_id"]!=e._account(firm,currency): continue
		if tx["to_account_id"]==tx["from_account_id"]: continue
		if tx["kind"] in ["cargo_extra_freight","freight"] and _transport_treatment(tx)=="SEPARATE_EXPENSE":
			result["separate_transport_expense"][currency]=int(result["separate_transport_expense"].get(currency,0))+int(tx["amount"])
		if tx["kind"]!="cargo_refund": continue
		var disposition:=e._cargo_fulfilment.dispositions.get(tx["reference_id"],{}) as Dictionary
		var original:=e._world.ledger_state.transaction(disposition.get("terms",{}).get("payment",{}).get("original_transaction_id","")) as Dictionary
		if original.get("kind")!="goods": continue # Freight refunds are distinct.
		var receipt_id:=str(original["transaction_id"]).trim_prefix("r1:goods:")
		result["sales_refunds_paid"][currency]=int(result["sales_refunds_paid"].get(currency,0))+int(tx["amount"])
		if sales.has(receipt_id) and int(e._delivery_receipts[receipt_id]["delivered_day"])>=maxi(0,e.day-window+1):
			var cost:=cost_of(sales[receipt_id])
			if cost["unknown"].is_empty() and (cost["amounts"].is_empty() or (cost["amounts"].size()==1 and cost["amounts"].has(currency))):
				result["contribution_after_known_refunds"][currency]=int(result["contribution_after_known_refunds"].get(currency,0))-int(tx["amount"])
				continue
		result["refunds_without_comparable_sale"][currency]=int(result["refunds_without_comparable_sale"].get(currency,0))+int(tx["amount"])
	for date: int in range(maxi(0,e.day-window+1),e.day+1):
		for id: String in _work_days.get(firm,{}).get(date,[]):
			for r: Dictionary in work_allocations.get(id,[]):
				if r["purpose"]!="HANDLING": continue
				for currency: String in _work_cost(r)["amounts"]: result["handling_wages_incurred"][currency]=int(result["handling_wages_incurred"].get(currency,0))+int(_work_cost(r)["amounts"][currency])
	_lifecycle_view(firm,window,result)
	result["services"]=service_view(firm,window)
	result["leases"]=e._leases.finance_view(firm,window)
	return result

func _known_loss(firm: String, id: String) -> bool:
	var e:=economy()
	return not e._cargo_fulfilment.losses.has(id) or e._cargo_fulfilment.knows_loss(e.firm_manager_at(firm,e._world.game_clock.total_minutes()),id)

func loss_view(id: String) -> Dictionary:
	var e:=economy()
	var physical:=e._lots.losses[id] as Dictionary
	var fact:=e._cargo_fulfilment.losses.get(id,{}) as Dictionary
	var first:=e._lots.portions[physical["portions"][0]["portion_id"]] as Dictionary
	var cost:=cost_of(loss_allocations[id]) if loss_allocations.has(id) else {"amounts":{},"unknown":["LEGACY_LOSS_COST_UNRECORDED"]}
	var result:={"id":id,"minute":physical["minute"],"good":first["good"],"unit":first["unit"],"owner":first["owner"],"custodian":first["custodian"],"location":first["location"],"quantity":_range_quantity(physical["portions"]),"cost":cost,"order_id":fact.get("order_id",""),"shipment_id":fact.get("shipment_id",""),"stage":fact.get("stage","STORAGE"),"unresolved_quantity":int(fact.get("quantity",0))-int(fact.get("resolved",0)),"liability_basis":"FINAL_BEARER_UNDETERMINED","dispositions":[]}
	for d_id: String in e._cargo_fulfilment._dispositions_by_order.get(result["order_id"],[]):
		var d:=e._cargo_fulfilment.dispositions[d_id] as Dictionary
		if d["loss_id"]==id: result["dispositions"].append({"id":d_id,"mode":d["terms"]["mode"],"status":d["status"],"quantity":d["terms"]["quantity"],"payment":d["terms"].get("payment",{}).duplicate(true)})
	return result

func _freight_context(tx: Dictionary) -> Dictionary:
	var e:=economy()
	if str(tx["transaction_id"]).begins_with("capital_freight_payment:"):
		var task:=e._capital_transport.tasks[tx["reference_id"]] as Dictionary
		var parts:=str(tx["transaction_id"]).split(":")
		var index:=int(parts[parts.size()-1])
		return {"order_id":"","transport_id":task["id"],"asset_id":task["asset_id"],"disposition_id":"","loss_id":"","edge_id":e._capital_transport.offer(task["offer_id"])["legs"][index]["edge_id"],"classification":"EQUIPMENT_ACQUISITION_FREIGHT","contract_role":"BUYER_CAPITAL_DELIVERY","payer":task["payer"],"receipt_id":""}
	if tx["kind"]=="cargo_extra_freight":
		var d:=e._cargo_fulfilment.dispositions[tx["reference_id"]] as Dictionary
		var index:=int(str(tx["transaction_id"]).get_slice(":",str(tx["transaction_id"]).get_slice_count(":")-1))
		var fee:=d["terms"]["fees"][index] as Dictionary
		var order:=e._orders[e._cargo_fulfilment.losses[d["loss_id"]]["order_id"]] as Dictionary
		return {"order_id":order["id"],"disposition_id":d["id"],"loss_id":d["loss_id"],"edge_id":fee["edge_id"],"classification":"REPLACEMENT_FREIGHT","contract_role":"SELLER_DELIVERY" if fee["payer"]==order["seller"] and order["kind"]=="SALE" else "BUYER_TRANSPORT" if fee["payer"]==order["buyer"] else "OTHER_CONFIRMED_PAYER","payer":fee["payer"],"recipient":fee["recipient"],"receipt_id":""}
	var order:=e._orders[tx["reference_id"]] as Dictionary
	var id:=str(tx["transaction_id"]).trim_prefix("r1:freight:")
	var index:=0
	if order["route_legs"].size()>1:
		index=int(id.get_slice(":",id.get_slice_count(":")-1))
		id=id.trim_suffix(":"+str(index))
	return {"order_id":order["id"],"disposition_id":"","loss_id":"","edge_id":order["route_legs"][index]["edge_id"],"classification":"INTERNAL_TRANSFER_FREIGHT" if order["kind"]=="TRANSFER" else "PERSONAL_FREIGHT_SERVICE" if order["kind"]=="PERSONAL_FREIGHT" else "ACQUISITION_FREIGHT","contract_role":"ORIGINAL_BUYER_PAYMENT_AT_COLLECTION","payer":order["buyer"],"receipt_id":id}

func _transport_treatment(tx: Dictionary) -> String:
	if tx["from_account_id"]==tx["to_account_id"]: return "OWN_CARRIER_COST_UNDETERMINED"
	var context:=_freight_context(tx)
	if context["classification"] in ["PERSONAL_FREIGHT_SERVICE","REPLACEMENT_FREIGHT","EQUIPMENT_ACQUISITION_FREIGHT"]: return "SEPARATE_EXPENSE"
	var b:=bases.get("acquisition:"+str(context["receipt_id"]),{}) as Dictionary
	if b.is_empty() and economy().config["cost_accounting"]["freight_treatment"]=="BUYER_ACQUISITION": return "PRE_COST_TREATMENT_UNRECORDED"
	return "CAPITALIZED_BY_EXPLICIT_ACQUISITION_POLICY" if b.get("refs",{}).get("capitalized_freight",false) else "SEPARATE_EXPENSE"

func _add_amount(target: Dictionary, currency: String, amount: int) -> void:
	target[currency]=int(target.get(currency,0))+amount

func _lifecycle_view(firm: String, window: int, result: Dictionary) -> void:
	var e:=economy()
	var first:=maxi(0,e.day-window+1)
	result["transport_by_purpose"]={}
	result["transport_records"]=[]
	result["handling_allocations"]=[]
	result["refunds_confirmed_payable"]={}
	result["damages_confirmed_payable"]={}
	result["damages_paid"]={}
	result["damages_received"]={}
	result["sales_refunds_confirmed"]={}
	result["contribution_after_confirmed_refunds"]=result["contribution"].duplicate()
	result["confirmed_refunds_without_comparable_sale"]={}
	result["contract_dispositions"]=[]
	result["unresolved_dispositions"]=0
	for tx: Dictionary in e._world.ledger_state.own_transactions(firm,first*1440):
		var currency:=str(tx["denomination"])
		if tx["kind"]=="cargo_damages":
			_add_amount(result["damages_paid"] if tx["from_account_id"]==e._account(firm,currency) else result["damages_received"],currency,tx["amount"])
		if tx["kind"] not in ["freight","cargo_extra_freight"] or tx["from_account_id"]!=e._account(firm,currency): continue
		var row:=_freight_context(tx)
		row.merge({"transaction_id":tx["transaction_id"],"payer_account":tx["from_account_id"],"recipient_account":tx["to_account_id"],"amount":tx["amount"],"currency":currency,"treatment":_transport_treatment(tx)},true)
		var category:=str(row["classification"])
		if not result["transport_by_purpose"].has(category): result["transport_by_purpose"][category]={"paid":{},"capitalized":{},"separate_expense":{}}
		if row["treatment"]!="OWN_CARRIER_COST_UNDETERMINED":
			_add_amount(result["transport_by_purpose"][category]["paid"],currency,tx["amount"])
			if row["treatment"]!="PRE_COST_TREATMENT_UNRECORDED": _add_amount(result["transport_by_purpose"][category]["capitalized" if row["treatment"]=="CAPITALIZED_BY_EXPLICIT_ACQUISITION_POLICY" else "separate_expense"],currency,tx["amount"])
		if result["transport_records"].size()<12: result["transport_records"].append(row)
	for date: int in range(first,e.day+1):
		var refs: Dictionary={}
		for work: String in _work_days.get(firm,{}).get(date,[]):
			for r: Dictionary in work_allocations.get(work,[]):
				if r["purpose"]=="HANDLING": refs[r["reference"]]=true
		for id: String in refs:
			var h:=e._shared.handling[id] as Dictionary
			var cost:=empty_cost()
			for r: Dictionary in _handling_work.get(id,[]): combine(cost,_work_cost(r))
			if result["handling_allocations"].size()<8: result["handling_allocations"].append({"id":id,"edge_id":h["edge_id"],"operation":h.get("operation","DEPARTURE"),"allocated_hours":h["hours"],"used_hours":h["used"],"standby_hours":int(h["hours"])-int(h["used"]),"incurred_cost":cost,"basis":"ACTUAL_ALLOCATED_WORK_WAGES_INCLUDING_STANDBY_NOT_PRODUCT_CAPITALIZATION"})
	for d: Dictionary in e._cargo_fulfilment.cost_dispositions(firm,first):
		var terms:=d["terms"] as Dictionary
		if d["status"]!="EXECUTED": result["unresolved_dispositions"]+=1
		if result["contract_dispositions"].size()<8: result["contract_dispositions"].append({"id":d["id"],"loss_id":d["loss_id"],"order_id":e._cargo_fulfilment.losses[d["loss_id"]]["order_id"],"mode":terms["mode"],"status":d["status"],"payment":terms.get("payment",{}).duplicate(true),"fees":terms.get("fees",[]).duplicate(true),"paid":d["payments"].duplicate(true),"replacement_sources":d["replacement_portions"].duplicate(true)})
		if terms["mode"] not in ["REFUND","DAMAGES"] or d["status"]=="PROPOSED": continue
		var pay:=terms["payment"] as Dictionary
		if pay["payer"]!=firm: continue
		if d["status"]!="EXECUTED": _add_amount(result["refunds_confirmed_payable"] if terms["mode"]=="REFUND" else result["damages_confirmed_payable"],pay["denomination"],pay["amount"])
		if terms["mode"]!="REFUND": continue
		var original:=e._world.ledger_state.transaction(pay["original_transaction_id"]) as Dictionary
		if original["kind"]!="goods": continue
		_add_amount(result["sales_refunds_confirmed"],pay["denomination"],pay["amount"])
		var receipt_id:=str(original["transaction_id"]).trim_prefix("r1:goods:")
		if sales.has(receipt_id) and int(e._delivery_receipts[receipt_id]["delivered_day"])>=first:
			var cost:=cost_of(sales[receipt_id])
			if cost["unknown"].is_empty() and (cost["amounts"].is_empty() or (cost["amounts"].size()==1 and cost["amounts"].has(pay["denomination"]))):
				_add_amount(result["contribution_after_confirmed_refunds"],pay["denomination"],-int(pay["amount"]))
				continue
		_add_amount(result["confirmed_refunds_without_comparable_sale"],pay["denomination"],pay["amount"])
	result["capital_assets"]=[]
	for id: String in e._capital.assets:
		if e._capital.asset_state(id)["owner"]==firm and result["capital_assets"].size()<8: result["capital_assets"].append(asset_cost(id))
	result["capital_equipment_cash"]={"sale_proceeds":{},"acquisition_paid":{},"unpaid_reserved_contracts":[]}
	for trade: Dictionary in e._capital.resale_trades.values():
		if firm not in [trade["seller"],trade["buyer"]]: continue
		var quote:=e._capital.resale_offers[trade["offer_id"]] as Dictionary
		if trade["state"]=="DELIVERED": _add_amount(result["capital_equipment_cash"]["sale_proceeds" if firm==trade["seller"] else "acquisition_paid"],quote["denomination"],quote["price"])
		elif trade["state"]=="ACCEPTED": result["capital_equipment_cash"]["unpaid_reserved_contracts"].append(trade["id"])
	result["depreciation_basis"]="NOT_CONFIGURED_NO_IMPUTED_RESIDUAL_VALUE"

func asset_cost(id: String) -> Dictionary:
	var e:=economy()
	var asset:=e._capital.assets[id] as Dictionary
	var result:={"id":id,"status":asset["status"],"usable_capacity":asset["capacity"] if asset["status"]=="ACTIVE" and e._site_operating(e._capital.asset_state(id)["site_id"]) else 0,"origin_cost":project_cost(asset["project_id"]),"maintenance_cost":empty_cost(),"maintenance_projects":[],"residual_value":null,"depreciation":"UNCONFIGURED","latest_event":asset["events"].back().duplicate(true)}
	if e._capital.template(asset["template_id"])["kind"] in e._capital.BUILD_KINDS:
		result["usable_capacity"]=0
		result["rental_use"]=e._leases.asset_view(id)
	for project: String in _asset_maintenance.get(id,[]):
		combine(result["maintenance_cost"],project_cost(project))
		result["maintenance_projects"].append(project)
	result["current_use"]=e._capital.asset_state(id)
	result["equipment_transactions"]=e._capital.mobility_costs(id)
	var external: Dictionary=e._service_market.asset_maintenance_cost(id)
	combine(result["maintenance_cost"],{"amounts":external["amounts"],"unknown":[]})
	result["external_maintenance_contracts"]=external["contracts"]
	return result

func service_inputs(id: String, rows: Array[Dictionary], append: bool=false) -> void:
	if not enabled: return
	var allocated:=ranges(rows)
	if append and service_materials.has(id): service_materials[id].append_array(allocated)
	else: service_materials[id]=allocated
func service_cost(id: String) -> Dictionary:
	var c:=economy()._service_market.contracts[id] as Dictionary
	var result:=cost_of(service_materials.get(id,[]))
	if not c["material_sources"].is_empty() and not service_materials.has(id): result["unknown"].append("LEGACY_SERVICE_MATERIAL_COST_UNRECORDED")
	var hours:=0
	for row: Dictionary in _service_work.get(id,[]): combine(result,_work_cost(row)); hours+=int(row["hours"])
	if hours<economy()._service_market.work_hours(c): result["unknown"].append("LEGACY_SERVICE_LABOR_COST_UNRECORDED")
	return result
func service_view(firm: String, window: int) -> Dictionary:
	var e:=economy()
	var result:={"fulfilled_revenue":{},"client_expense_incurred":{},"advertising_expense_incurred":{},"advertising_cash_paid":{},"publication_revenue":{},"known_contract_contribution":{},"completed_contracts":[],"unknown_contracts":0,"excluded":["DEPRECIATION","FACILITY_RENT","GENERAL_OVERHEADS"],"basis":"KNOWN_DIRECT_SERVICE_CONTRIBUTION_NOT_NET_PROFIT"}
	var first:=maxi(0,e.day-window+1)*1440
	for id: String in e._service_market.recent_contracts(firm,first):
		var c:=e._service_market.contracts[id] as Dictionary
		var currency:=str(e._service_market._offers[c["offer_id"]]["denomination"])
		var earned:=int(c["earned"]) if c["kind"]=="REPAIR" and c["repair_result_minute"]>=first else 0
		if c["kind"] in ["STORAGE","ANNOUNCEMENT"]:
			for p: Dictionary in c["periods"]:
				if p["minute"]>=first: earned+=int(p["earned_delta"])
		if c["kind"] in ["DINING","HAIRCUT"]:
			for receipt: Dictionary in c["resident"]["receipts"]:
				if receipt["minute"]>=first: earned+=int(receipt["quantity"])*int(e._service_market._offers[c["offer_id"]]["price"])
		if c["kind"]=="ANNOUNCEMENT":
			if c["client"]==firm:
				_add_amount(result["advertising_expense_incurred"],currency,earned)
				for payment: Dictionary in c["payments"]:
					if payment["minute"]>=first: _add_amount(result["advertising_cash_paid"],currency,payment["amount"])
			if c["provider"]==firm: _add_amount(result["publication_revenue"],currency,earned)
		if c["provider"]==firm: _add_amount(result["fulfilled_revenue"],currency,earned)
		if c["client"]==firm: _add_amount(result["client_expense_incurred"],currency,earned)
		if c["provider"]!=firm or c["status"]!="COMPLETED" or maxi(int(c["last_boundary"]),int(c["repair_result_minute"]))<first: continue
		var cost:=service_cost(id)
		var comparable: bool=cost["unknown"].is_empty() and (cost["amounts"].is_empty() or (cost["amounts"].size()==1 and cost["amounts"].has(currency)))
		if comparable: _add_amount(result["known_contract_contribution"],currency,int(c["earned"])-int(cost["amounts"].get(currency,0)))
		else: result["unknown_contracts"]+=1
		if result["completed_contracts"].size()<8: result["completed_contracts"].append({"id":id,"scope":"WHOLE_COMPLETED_CONTRACT","earned":c["earned"],"paid":c["paid"],"cost":cost,"comparable":comparable})
	return result

func activity_scores(site: String, window: int) -> Dictionary:
	var e:=economy()
	var cache_key: String=str(e._world.game_clock.total_minutes())+"|"+site+"|"+str(window)+"|"+e.firm_manager_at(e._owner(site),e._world.game_clock.total_minutes())
	if _scores_cache.has(cache_key): return _scores_cache[cache_key].duplicate(true)
	# At most the current finite site/window queries are cached, never history.
	if _scores_cache.size()>128: _scores_cache.clear()
	var scores: Dictionary={}
	for date: int in range(maxi(0,e.day-window+1),e.day+1):
		for id: String in _sales_days.get(site,{}).get(date,[]):
			var receipt:=e._delivery_receipts[id] as Dictionary
			var order:=e._orders[receipt["order_id"]] as Dictionary
			for r: Dictionary in sales[id]:
				var b:=bases[r["basis"]] as Dictionary
				if b["kind"]!="OUTPUT": continue
				var p:=productions[b["refs"]["production"]] as Dictionary
				var a:=e._activity(site,p["activity"]) as Dictionary
				if p["site"]!=site or a["outputs"].size()!=1: continue
				var cost:=cost_of([r])
				var currency:=str(order["denomination"])
				var key:=str(p["activity"])
				if not scores.has(key): scores[key]={"currency":currency,"margin":0,"units":0,"output_per_batch":a["outputs"][order["good"]],"hours_per_batch":a["hours"],"has_unknown_cost":false}
				if not cost["unknown"].is_empty() or cost["amounts"].size()!=1 or not cost["amounts"].has(currency):
					scores[key]["has_unknown_cost"]=true
					continue
				if scores[key]["currency"]!=currency:
					scores[key]["currency"]="INCOMPARABLE_CURRENCIES"
					continue
				scores[key]["margin"]+=int(r["quantity"])*int(order["price"])-int(cost["amounts"][currency])
				scores[key]["units"]+=int(r["quantity"])
	for d: Dictionary in e._cargo_fulfilment.cost_dispositions(e._owner(site),maxi(0,e.day-window+1)):
		if d["status"]=="PROPOSED" or d["terms"]["mode"]!="REFUND" or d["terms"]["payment"]["payer"]!=e._owner(site): continue
		var pay:=d["terms"]["payment"] as Dictionary
		var original:=e._world.ledger_state.transaction(pay["original_transaction_id"]) as Dictionary
		if original.get("kind")!="goods": continue
		var id:=str(original["transaction_id"]).trim_prefix("r1:goods:")
		if not sales.has(id) or int(e._delivery_receipts[id]["delivered_day"])<maxi(0,e.day-window+1): continue
		var before:=0
		var quantity:=int(e._delivery_receipts[id]["quantity"])
		for r: Dictionary in sales[id]:
			var refund:=fraction(pay["amount"],before+int(r["quantity"]),quantity)-fraction(pay["amount"],before,quantity)
			before+=int(r["quantity"])
			var b:=bases[r["basis"]] as Dictionary
			if b["kind"]!="OUTPUT": continue
			var p:=productions[b["refs"]["production"]] as Dictionary
			if p["site"]==site and scores.has(p["activity"]): scores[p["activity"]]["margin"]-=refund
	_contract_scores(site,window,scores)
	_scores_cache[cache_key]=scores.duplicate(true)
	return scores

func _contract_scores(site: String, window: int, scores: Dictionary) -> void:
	var e:=economy()
	var firm: String=e._owner(site)
	var first:=maxi(0,e.day-window+1)
	# A known destroyed OUTPUT share is attributed only to its actual activity.
	# It remains a physical-owner loss, never a presumed final damages liability.
	for date: int in range(first,e.day+1):
		for id: String in _loss_days.get(firm,{}).get(date,[]):
			if not _known_loss(firm,id): continue
			for r: Dictionary in loss_allocations.get(id,[]):
				var b:=bases[r["basis"]] as Dictionary
				if b["kind"]!="OUTPUT": continue
				var p:=productions[b["refs"]["production"]] as Dictionary
				if p["site"]!=site or not scores.has(p["activity"]): continue
				_adjust_score(scores[p["activity"]],cost_of([r]),"known_physical_loss")
	for d: Dictionary in e._cargo_fulfilment.cost_dispositions(firm,first):
		if d["status"]!="EXECUTED" or d["terms"]["mode"]!="REPLACE" or int(d["executed_minute"])/1440<first: continue
		var order:=e._orders[e._cargo_fulfilment.losses[d["loss_id"]]["order_id"]] as Dictionary
		if order["seller_site"]!=site: continue
		var activity:=""
		var comparable:=true
		for row: Dictionary in d["replacement_portions"]:
			var b:=bases[bindings[row["portion_id"]]["basis"]] as Dictionary
			if b["kind"]!="OUTPUT": comparable=false; break
			var p:=productions[b["refs"]["production"]] as Dictionary
			if p["site"]!=site or (not activity.is_empty() and activity!=p["activity"]): comparable=false; break
			activity=p["activity"]
		if not comparable or not scores.has(activity): continue # No invented joint split.
		for fee: Dictionary in d["terms"]["fees"]:
			if fee["payer"]==firm and fee["recipient"]!=firm: _adjust_score(scores[activity],{"amounts":{str(fee["denomination"]):fee["amount"]},"unknown":[]},"replacement_freight")

func _adjust_score(score: Dictionary, cost: Dictionary, field: String) -> void:
	if not cost["unknown"].is_empty() or cost["amounts"].size()>1 or (cost["amounts"].size()==1 and not cost["amounts"].has(score["currency"])):
		score["has_unknown_cost"]=true
		return
	var amount:=int(cost["amounts"].get(score["currency"],0))
	score["margin"]-=amount
	score[field]=int(score.get(field,0))+amount

func rank(site: String, original: Array[String]) -> Array[String]:
	var e:=economy()
	var p:=policy(e._owner(site))
	if not enabled or p.is_empty() or not p["rank_production"] or e.firm_manager_at(e._owner(site),e._world.game_clock.total_minutes())!=e._owner(site): return original.duplicate()
	var scores:=activity_scores(site,p["window_days"])
	var currency:=""
	for id: String in original:
		if not scores.has(id) or scores[id]["currency"]=="INCOMPARABLE_CURRENCIES" or scores[id]["has_unknown_cost"] or int(scores[id]["units"])==0: return original.duplicate()
		if not currency.is_empty() and currency!=scores[id]["currency"]: return original.duplicate()
		currency=scores[id]["currency"]
	var ranked:=original.duplicate()
	ranked.sort_custom(func(a: String,b: String) -> bool:
		var x:=float(scores[a]["margin"])*float(scores[a]["output_per_batch"])/(float(scores[a]["units"])*float(scores[a]["hours_per_batch"]))
		var y:=float(scores[b]["margin"])*float(scores[b]["output_per_batch"])/(float(scores[b]["units"])*float(scores[b]["hours_per_batch"]))
		return x>y if x!=y else original.find(a)<original.find(b))
	return ranked

func investment_allowed(site: String) -> bool:
	var p:=policy(economy()._owner(site))
	if not enabled or p.is_empty() or not p["block_known_loss_investment"]: return true
	var scores:=activity_scores(site,p["window_days"])
	if scores.is_empty(): return true # Unknown costs retain the existing strategy.
	for id: String in economy()._spec["sites"][site]["activity_order"]:
		if not scores.has(id): return true
	var currency:=""
	var margin:=0
	for r: Dictionary in scores.values():
		if r["currency"]=="INCOMPARABLE_CURRENCIES" or r["has_unknown_cost"] or int(r["units"])==0 or (not currency.is_empty() and currency!=r["currency"]): return true
		currency=r["currency"]
		margin+=int(r["margin"])
	var burden:=_site_burden(site,p["window_days"])
	if not burden["unknown"].is_empty() or burden["amounts"].size()>1 or (burden["amounts"].size()==1 and not burden["amounts"].has(currency)): return true
	margin-=int(burden["amounts"].get(currency,0))
	return margin>=0

func _site_burden(site: String, window: int) -> Dictionary:
	var e:=economy()
	var firm: String=e._owner(site)
	var first:=maxi(0,e.day-window+1)
	var result:=empty_cost()
	for date: int in range(first,e.day+1):
		for id: String in _work_days.get(firm,{}).get(date,[]):
			if e._spec["jobs"][e._work_records[id]["job"]]["site_id"]!=site: continue
			for r: Dictionary in work_allocations.get(id,[]):
				if r["purpose"]=="HANDLING": combine(result,_work_cost(r))
	for tx: Dictionary in e._world.ledger_state.own_transactions(firm,first*1440):
		if tx["kind"]!="freight" or tx["from_account_id"]!=e._account(firm,tx["denomination"]): continue
		if str(tx["transaction_id"]).begins_with("capital_freight_payment:"): continue # Asset acquisition is separate from current production.
		var o:=e._orders[tx["reference_id"]] as Dictionary
		if o["buyer_site"]==site and _transport_treatment(tx)=="SEPARATE_EXPENSE": combine(result,{"amounts":{str(tx["denomination"]):tx["amount"]},"unknown":[]})
	for d: Dictionary in e._cargo_fulfilment.cost_dispositions(firm,first):
		if d["status"]=="PROPOSED" or d["terms"]["mode"]!="DAMAGES" or d["terms"]["payment"]["payer"]!=firm: continue
		var o:=e._orders[e._cargo_fulfilment.losses[d["loss_id"]]["order_id"]] as Dictionary
		if (o["seller"]==firm and o["seller_site"]==site) or (o["buyer"]==firm and o["buyer_site"]==site):
			var pay:=d["terms"]["payment"] as Dictionary
			combine(result,{"amounts":{str(pay["denomination"]):pay["amount"]},"unknown":[]})
	return result

func _has_weights(site: String, activity: String) -> bool:
	for row: Dictionary in economy().config["cost_accounting"]["joint_allocations"]:
		if row["site"]==site and row["activity"]==activity: return true
	return false

func _work_cost(row: Dictionary) -> Dictionary:
	var w:=economy()._wages[row["work"]] as Dictionary
	return {"amounts":{str(w["denomination"]):fraction(w["amount"],int(row["offset"])+int(row["hours"]),w["hours"])-fraction(w["amount"],row["offset"],w["hours"])},"unknown":[]}

func project_cost(id: String) -> Dictionary:
	var result:=empty_cost()
	if not enabled:
		result["unknown"].append("COST_ACCOUNTING_NOT_ENABLED")
		return result
	if capital_materials.has(id): result=cost_of(capital_materials[id])
	elif not economy()._capital.projects[id]["materials"].is_empty(): result["unknown"].append("PRE_COST_CAPITAL_MATERIALS_UNKNOWN")
	var actual_hours: int=economy()._capital.work_hours(economy()._capital.projects[id])
	var allocated:=0
	for row: Dictionary in _project_work.get(id,[]): allocated+=int(row["hours"])
	if allocated<actual_hours: result["unknown"].append("PRE_COST_CAPITAL_LABOR_UNRECORDED")
	for row: Dictionary in _project_work.get(id,[]): combine(result,_work_cost(row))
	return result

func snapshot() -> Dictionary:
	return {"format":FORMAT,"start_minute":start_minute,"bases":bases.duplicate(true),"bindings":bindings.duplicate(true),"productions":productions.duplicate(true),"sales":sales.duplicate(true),"capital_materials":capital_materials.duplicate(true),"loss_allocations":loss_allocations.duplicate(true),"work_allocations":work_allocations.duplicate(true),"service_materials":service_materials.duplicate(true)}

func _ranges_valid(rows: Variant) -> bool:
	if not rows is Array: return false
	var portions: Dictionary={}
	var spans: Dictionary={}
	for r: Variant in rows:
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["portion","basis","offset","quantity"]) or not economy()._lots.portions.has(r["portion"]) or not bases.has(r["basis"]) or not FormalLedgerState.valid_amount(r["offset"]) or not FormalLedgerState.valid_amount(r["quantity"]) or int(r["quantity"])<=0 or int(r["offset"])+int(r["quantity"])>int(bases[r["basis"]]["quantity"]): return false
		var p:=economy()._lots.portions[r["portion"]] as Dictionary
		var b:=bindings.get(r["portion"],{}) as Dictionary
		if b.get("basis")!=r["basis"] or int(r["offset"])<int(b["offset"]) or int(r["offset"])+int(r["quantity"])>int(b["offset"])+int(p["quantity"]): return false
		portions[r["portion"]]=int(portions.get(r["portion"],0))+int(r["quantity"])
		if portions[r["portion"]]>int(p["quantity"]): return false
		for prior: Dictionary in spans.get(r["portion"],[]):
			if int(r["offset"])<int(prior["offset"])+int(prior["quantity"]) and int(prior["offset"])<int(r["offset"])+int(r["quantity"]): return false
		if not spans.has(r["portion"]): spans[r["portion"]]=[]
		spans[r["portion"]].append(r)
	return true

func _range_quantity(rows: Array) -> int:
	var q:=0
	for r: Dictionary in rows: q+=int(r["quantity"])
	return q

func _matches_physical(rows: Array, physical: Array) -> bool:
	if rows.size()!=physical.size(): return false
	for i: int in rows.size():
		if rows[i]["portion"]!=physical[i]["portion_id"] or rows[i]["quantity"]!=physical[i]["quantity"]: return false
	return true

func restore(raw: Variant) -> bool:
	if not enabled: return raw==null
	var e:=economy()
	if raw==null:
		start_minute=e._world.game_clock.total_minutes()
		bases.clear()
		bindings.clear()
		for p: Dictionary in e._lots.portions.values():
			# A legacy boundary has no historical cost allocation. Never infer it.
			var id:="unknown:"+str(p["id"])
			_basis(id,"UNKNOWN",p["owner"],p["quantity"],{"amounts":{},"unknown":["LEGACY_COST_UNRECORDED"]},{"portion":p["id"]},start_minute)
			bindings[p["id"]]={"basis":id,"offset":0}
		for id: String in e._lots.losses: _index_loss(id,e._lots.losses[id]["minute"])
		for id: String in e._capital.projects: _index_project(id)
		return true
	var fields: Array[String]=[]
	fields.assign(snapshot().keys())
	if raw is Dictionary and not raw.has("service_materials"): raw=raw.duplicate(true); raw["service_materials"]={}
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw,fields) or raw["format"]!=FORMAT or not FormalLedgerState.valid_amount(raw["start_minute"]) or raw["start_minute"]>e._world.game_clock.total_minutes(): return false
	for key: String in ["bases","bindings","productions","sales","capital_materials","loss_allocations","work_allocations","service_materials"]:
		if not raw[key] is Dictionary: return false
	start_minute=raw["start_minute"]
	bases=raw["bases"].duplicate(true)
	bindings=raw["bindings"].duplicate(true)
	productions=raw["productions"].duplicate(true)
	sales=raw["sales"].duplicate(true)
	capital_materials=raw["capital_materials"].duplicate(true)
	loss_allocations=raw["loss_allocations"].duplicate(true)
	work_allocations=raw["work_allocations"].duplicate(true)
	service_materials=raw["service_materials"].duplicate(true)
	_service_work.clear()
	_sales_days.clear()
	_production_days.clear()
	_project_work.clear()
	_work_days.clear()
	_firm_projects.clear()
	_loss_days.clear()
	_handling_work.clear()
	_asset_maintenance.clear()
	for id: String in bases:
		var b: Variant=bases[id]
		if not b is Dictionary or not FormalLedgerState.exact_fields(b,["id","kind","owner","quantity","minute","amounts","unknown","refs"]) or b["id"]!=id or b["kind"] not in ["UNKNOWN","OUTPUT","ACQUISITION"] or b["owner"] not in e._physical_owners() or not FormalLedgerState.valid_amount(b["quantity"]) or b["quantity"]<1 or not FormalLedgerState.valid_amount(b["minute"]) or b["minute"]<start_minute or b["minute"]>e._world.game_clock.total_minutes() or not b["amounts"] is Dictionary or not b["unknown"] is Array or not b["refs"] is Dictionary: return false
		for currency: String in b["amounts"]:
			if not FormalLedgerState.currency_id(currency) or not FormalLedgerState.valid_amount(b["amounts"][currency]): return false
		for reason: Variant in b["unknown"]:
			if not reason is String or reason not in ["OPENING_OR_PRE_COST_SOURCE_UNKNOWN","LEGACY_COST_UNRECORDED","JOINT_OUTPUT_ALLOCATION_UNCONFIGURED","COST_AMOUNT_OUT_OF_RANGE","PRODUCTION_WORK_ALLOCATION_MISSING","OWN_CARRIER_COST_ALLOCATION_UNCONFIGURED"]: return false
	for id: String in bindings:
		var r: Variant=bindings[id]
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["basis","offset"]) or not bases.has(r["basis"]) or not e._lots.portions.has(id) or not FormalLedgerState.valid_amount(r["offset"]) or int(r["offset"])+int(e._lots.portions[id]["quantity"])>int(bases[r["basis"]]["quantity"]) or bases[r["basis"]]["owner"]!=e._lots.portions[id]["owner"]: return false
	if bindings.size()!=e._lots.portions.size(): return false
	var cost_by_reference: Dictionary={}
	var hours_by_reference: Dictionary={}
	for work: String in work_allocations:
		if not e._work_records.has(work) or not e._wages.has(work) or not work_allocations[work] is Array: return false
		var offset:=0
		for r: Variant in work_allocations[work]:
			if not r is Dictionary or not FormalLedgerState.exact_fields(r,["work","hours","offset","purpose","reference"]) or r["work"]!=work or r["offset"]!=offset or not FormalLedgerState.valid_amount(r["hours"]) or r["hours"]<1 or r["purpose"] not in ["PRODUCTION","CAPITAL","HANDLING","SERVICE","RETAIL"]: return false
			offset+=int(r["hours"])
			if offset>int(e._work_records[work]["hours"]): return false
			var key:=str(r["purpose"])+"|"+str(r["reference"])
			if not cost_by_reference.has(key): cost_by_reference[key]=empty_cost()
			combine(cost_by_reference[key],_work_cost(r))
			hours_by_reference[key]=int(hours_by_reference.get(key,0))+int(r["hours"])
			if r["purpose"]=="CAPITAL":
				if not e._capital.projects.has(r["reference"]): return false
				var actual:=0
				for row: Dictionary in e._capital.projects[r["reference"]]["work"]:
					if row["id"]==work: actual+=int(row["hours"])
				var assigned:=0
				for row: Dictionary in work_allocations[work]:
					if row["purpose"]=="CAPITAL" and row["reference"]==r["reference"]: assigned+=int(row["hours"])
				if assigned!=actual: return false
				if not _project_work.has(r["reference"]): _project_work[r["reference"]]=[]
				_project_work[r["reference"]].append(r)
				_index_project(r["reference"])
			elif r["purpose"]=="PRODUCTION":
				var p: Variant=productions.get(r["reference"])
				if not p is Dictionary or not p.get("site") is String or not e._spec["jobs"].has(e._work_records[work]["job"]) or p["site"]!=e._spec["jobs"][e._work_records[work]["job"]]["site_id"] or p.get("day")!=e._work_records[work]["day"]: return false
			elif r["purpose"]=="RETAIL":
				var window: Dictionary=e._retail.windows.get(r["reference"],{})
				if window.is_empty(): return false
				var actual:=0
				for row: Dictionary in window["work"]:
					if row["id"]==work: actual+=int(row["hours"])
				if actual!=r["hours"]: return false
			elif r["purpose"]=="SERVICE":
				if not e._service_market.contracts.has(r["reference"]): return false
				var actual:=0
				for row: Dictionary in e._service_market.contracts[r["reference"]]["work"]:
					if row["id"]==work: actual+=int(row["hours"])
				var assigned:=0
				for row: Dictionary in work_allocations[work]:
					if row["purpose"]=="SERVICE" and row["reference"]==r["reference"]: assigned+=int(row["hours"])
				if assigned!=actual: return false
				if not _service_work.has(r["reference"]): _service_work[r["reference"]]=[]
				_service_work[r["reference"]].append(r)
			elif r["purpose"]=="HANDLING" and not e._shared.handling.has(r["reference"]): return false
			elif r["purpose"]=="HANDLING":
				var actual:=0
				for row: Dictionary in e._shared.handling[r["reference"]]["work"]:
					if row["work_id"]==work: actual+=int(row["hours"])
				if actual!=r["hours"]: return false
				if not _handling_work.has(r["reference"]): _handling_work[r["reference"]]=[]
				_handling_work[r["reference"]].append(r)
	for window: Dictionary in e._retail.windows.values():
		if window["minute"]<start_minute: continue
		for work: Dictionary in window["work"]:
			var allocated:=0
			for r: Dictionary in work_allocations.get(work["id"],[]):
				if r["purpose"]=="RETAIL" and r["reference"]==window["id"]: allocated+=int(r["hours"])
			if allocated!=work["hours"]: return false
	for id: String in productions:
		var p: Variant=productions[id]
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["site","activity","day","batches","inputs","cost","outputs"]) or not e._spec["sites"].has(p["site"]) or not e._site_state[p["site"]]["activities"].has(p["activity"]) or not FormalLedgerState.valid_amount(p["day"]) or p["day"]>e.day or not FormalLedgerState.valid_amount(p["batches"]) or p["batches"]<1 or id!="production:"+str(p["day"])+":"+str(p["site"])+":"+str(p["activity"]) or not _ranges_valid(p["inputs"]) or not p["outputs"] is Dictionary: return false
		var expected:=cost_of(p["inputs"])
		var key:="PRODUCTION|"+id
		combine(expected,cost_by_reference.get(key,empty_cost()))
		var activity:=e._activity(p["site"],p["activity"]) as Dictionary
		if hours_by_reference.get(key,0)!=int(p["batches"])*int(activity["hours"]) or p["outputs"].size()!=activity["outputs"].size(): return false
		if p["cost"]!=expected: return false
		for good: String in p["outputs"]:
			var source:=e._lots.sources.get(p["outputs"][good],{}) as Dictionary
			if source.is_empty() or not activity["outputs"].has(good) or source["good"]!=good or source["quantity"]!=int(activity["outputs"][good])*int(p["batches"]) or not _matches_physical(p["inputs"],source["inputs"]): return false
		var material_quantities: Dictionary={}
		for r: Dictionary in p["inputs"]:
			var portion:=e._lots.portions[r["portion"]] as Dictionary
			if portion["owner"]!=e._owner(p["site"]) or portion["location"]!="SITE|"+str(p["site"]): return false
			material_quantities[portion["good"]]=int(material_quantities.get(portion["good"],0))+int(r["quantity"])
		for good: String in activity["materials"]:
			if material_quantities.get(good,0)!=int(p["batches"])*int(activity["materials"][good]): return false
		_index_production(id)
	for id: String in sales:
		if not e._delivery_receipts.has(id) or e._orders[e._delivery_receipts[id]["order_id"]]["kind"]!="SALE" or not _ranges_valid(sales[id]): return false
		if _range_quantity(sales[id])!=int(e._delivery_receipts[id]["quantity"]): return false
		_index_sale(id)
	for project: String in capital_materials:
		if not e._capital.projects.has(project) or not _ranges_valid(capital_materials[project]): return false
		if not _matches_physical(capital_materials[project],e._capital.projects[project].get("material_sources",[])): return false
		_index_project(project)
	for id: String in loss_allocations:
		if not e._lots.losses.has(id) or not _ranges_valid(loss_allocations[id]): return false
		if not _matches_physical(loss_allocations[id],e._lots.losses[id]["portions"]): return false
		_index_loss(id,e._lots.losses[id]["minute"])
	for id: String in service_materials:
		if not e._service_market.contracts.has(id) or not _ranges_valid(service_materials[id]) or not _matches_physical(service_materials[id],e._service_market.contracts[id]["material_sources"]): return false
	for id: String in e._lots.losses:
		if int(e._lots.losses[id]["minute"])>start_minute and not loss_allocations.has(id): return false
		if not loss_allocations.has(id): _index_loss(id,e._lots.losses[id]["minute"])
	for id: String in e._capital.projects: _index_project(id)
	if not _validate_terminal_ranges(): return false
	for id: String in e._wages: observe_work(id)
	if not _validate_basis_references(): return false
	for id: String in bindings:
		var p:=e._lots.portions[id] as Dictionary
		var binding:=bindings[id] as Dictionary
		var b:=bases[binding["basis"]] as Dictionary
		var good:=""
		if b["kind"]=="UNKNOWN": good=e._lots.portions[b["refs"]["portion"]]["good"]
		elif b["kind"]=="OUTPUT": good=e._lots.sources[b["refs"]["source"]]["good"]
		else: good=e._orders[e._delivery_receipts[b["refs"]["receipt"]]["order_id"]]["good"]
		if good!=p["good"]: return false
		var parent:=str(p["parent_portion_id"])
		if parent.is_empty():
			if binding["offset"]!=0 or b["kind"]=="ACQUISITION": return false
			if b["kind"]=="OUTPUT" and b["refs"]["source"]!=p["source_id"]: return false
			continue
		if b["kind"]=="UNKNOWN" and b["refs"]["portion"]==id and b["minute"]==start_minute: continue
		var original:=e._lots.portions[parent] as Dictionary
		if b["kind"]=="ACQUISITION" and p["acquisition_id"]==b["refs"]["receipt"]:
			var receipt:=e._delivery_receipts[b["refs"]["receipt"]] as Dictionary
			var order: Dictionary=e._orders[receipt["order_id"]]
			if original["location"]==_acquisition_origin(order,receipt) and p["opened_minute"]==receipt["delivered_minute"]: continue
		if binding["basis"]!=bindings[parent]["basis"] or int(binding["offset"])<int(bindings[parent]["offset"]) or int(binding["offset"])+int(p["quantity"])>int(bindings[parent]["offset"])+int(original["quantity"]): return false
	return true

## A portion's sale, consumption and loss cannot allocate the same original
## monetary range twice. Physical history remains the source of each reference.
func _validate_terminal_ranges() -> bool:
	var spans: Dictionary={}
	var groups: Array=[]
	groups.append_array(sales.values())
	groups.append_array(loss_allocations.values())
	groups.append_array(capital_materials.values())
	groups.append_array(service_materials.values())
	for p: Dictionary in productions.values(): groups.append(p["inputs"])
	for rows: Array in groups:
		for r: Dictionary in rows:
			for prior: Dictionary in spans.get(r["portion"],[]):
				if int(r["offset"])<int(prior["offset"])+int(prior["quantity"]) and int(prior["offset"])<int(r["offset"])+int(r["quantity"]): return false
			if not spans.has(r["portion"]): spans[r["portion"]]=[]
			spans[r["portion"]].append(r)
	return true

func _validate_basis_references() -> bool:
	var e:=economy()
	for b: Dictionary in bases.values():
		var r:=b["refs"] as Dictionary
		if b["kind"]=="UNKNOWN":
			if not FormalLedgerState.exact_fields(r,["portion"]) or not e._lots.portions.has(r["portion"]) or not b["amounts"].is_empty() or b["unknown"].is_empty() or b["quantity"]!=e._lots.portions[r["portion"]]["quantity"] or b["owner"]!=e._lots.portions[r["portion"]]["owner"]: return false
		elif b["kind"]=="OUTPUT":
			if not FormalLedgerState.exact_fields(r,["production","source","weights"]) or not productions.has(r["production"]) or not e._lots.sources.has(r["source"]) or not r["weights"] is Dictionary: return false
			var p:=productions[r["production"]] as Dictionary
			var source:=e._lots.sources[r["source"]] as Dictionary
			if p["outputs"].get(source["good"])!=r["source"] or b["id"]!="output:"+str(r["source"]) or b["owner"]!=e._owner(p["site"]) or b["quantity"]!=source["quantity"] or b["minute"]!=source["formed_minute"]: return false
			var expected:=p["cost"] as Dictionary
			var weights: Dictionary={}
			if p["outputs"].size()>1:
				for rule: Dictionary in e.config["cost_accounting"]["joint_allocations"]:
					if rule["site"]==p["site"] and rule["activity"]==p["activity"]: weights=rule["weights"]
				if weights.is_empty(): expected={"amounts":{},"unknown":["JOINT_OUTPUT_ALLOCATION_UNCONFIGURED"]}
				else:
					var goods: Array=p["outputs"].keys()
					goods.sort()
					var total:=0
					var before:=0
					for good: String in goods: total+=int(weights[good])
					for good: String in goods:
						if good==source["good"]: break
						before+=int(weights[good])
					expected={"amounts":{},"unknown":p["cost"]["unknown"]}
					for currency: String in p["cost"]["amounts"]:
						expected["amounts"][currency]=fraction(p["cost"]["amounts"][currency],before+int(weights[source["good"]]),total)-fraction(p["cost"]["amounts"][currency],before,total)
			if r["weights"]!=weights or b["amounts"]!=expected["amounts"] or b["unknown"]!=expected["unknown"]: return false
		elif b["kind"]=="ACQUISITION":
			if not FormalLedgerState.exact_fields(r,["receipt","prior","capitalized_freight"]) or not e._delivery_receipts.has(r["receipt"]) or not _ranges_valid(r["prior"]) or not r["capitalized_freight"] is bool: return false
			var receipt:=e._delivery_receipts[r["receipt"]] as Dictionary
			var order:=e._orders[receipt["order_id"]] as Dictionary
			if b["id"]!="acquisition:"+str(r["receipt"]) or b["minute"]!=receipt["delivered_minute"] or order["kind"]=="PERSONAL_FREIGHT" or _range_quantity(r["prior"])!=receipt["quantity"] or r["capitalized_freight"]!=(e.config["cost_accounting"]["freight_treatment"]=="BUYER_ACQUISITION"): return false
			if order["kind"]=="SALE" and sales.get(r["receipt"])!=r["prior"]: return false
			for portion: Dictionary in r["prior"]:
				var physical:=e._lots.portions[portion["portion"]] as Dictionary
				if physical["owner"]!=order["seller"] or physical["good"]!=order["good"] or physical["location"]!=_acquisition_origin(order,receipt): return false
			var expected:=empty_cost() if order["kind"]=="SALE" else cost_of(r["prior"])
			if order["kind"]=="SALE": expected["amounts"][order["denomination"]]=int(receipt["quantity"])*int(order["price"])
			if r["capitalized_freight"]: combine(expected,_freight_cost(order,receipt["quantity"]))
			if b["quantity"]!=receipt["quantity"] or b["amounts"]!=expected["amounts"] or b["unknown"]!=expected["unknown"] or b["owner"]!=order["buyer"]: return false
	for id: String in e._delivery_receipts:
		var receipt:=e._delivery_receipts[id] as Dictionary
		var order:=e._orders[receipt["order_id"]] as Dictionary
		if int(receipt["delivered_minute"])<=start_minute or order["kind"]=="PERSONAL_FREIGHT": continue
		if not bases.has("acquisition:"+id) or (order["kind"]=="SALE" and not sales.has(id)): return false
	return true

func _acquisition_origin(order: Dictionary, receipt: Dictionary) -> String:
	return "SITE|"+str(order["seller_site"]) if str(order["route_id"]).begins_with("onsite:") else "CARGO|"+str(receipt.get("shipment_id",receipt["id"]))
