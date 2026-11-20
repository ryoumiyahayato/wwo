extends RefCounted
## Projection only. The host authenticates actor; caller-supplied IDs grant no rights.
const FORMAT = "economy_read_v1"
const Process = preload("res://scripts/world/economy_production_process.gd")

static func own(e: RefCounted, actor: String, firm: String, site: String) -> Dictionary:
	if not e._spec.firms.has(firm) or not e._manager(actor,firm) or not e._spec.sites.has(site) or e._owner(site)!=firm: return {}
	var now: int = e._world.game_clock.total_minutes()
	var activities: Array = []
	for a: Dictionary in e._spec.sites[site].activities:
		var state: Dictionary = e._site_state[site].activities[a.id]
		var plan: Dictionary = e._plans.get(site,{}).get("activities",{}).get(a.id,{})
		var actual: int = int(plan.get("actual",0))
		var inputs: Dictionary = {};var outputs: Dictionary = {};var rejects: Dictionary = {}
		for g: String in a.materials: inputs[g]=actual*int(a.materials[g])
		for g: String in a.outputs:
			outputs[g]=actual*int(a.outputs[g])
			rejects[g]=actual*int(a.get("process",{}).get("rejects",{}).get(g,0))
		var reason: String = Process.reason(a,e.day,int(state.batches))
		var planned: int = int(plan.get("schedule",[{"quantity":0}])[0].quantity)
		var capacity: int = e._capital.capacity(site,e._production_minute(),a.id)
		var constraints: Array = []
		if reason not in ["ELIGIBLE","LEGACY_UNSPECIFIED"]: constraints.append(reason)
		if planned>actual:
			if int(e._labor.get(site,0))<planned*int(a.hours): constraints.append("LABOR_HOURS_BOUND")
			if capacity<planned*int(a.capacity_units): constraints.append("CAPACITY_BOUND")
			# End-of-day stock is an observation, not reconstructed start-of-work stock.
			for g: String in a.materials:
				if int(a.materials[g])>0 and int(e._stocks[site][g])<int(a.materials[g]): constraints.append("CURRENT_MATERIAL_SHORTAGE:"+g)
		activities.append({"id":a.id,"recipe":a.duplicate(true),"process_status":reason,"planned_batches":planned,"actual_batches":actual,"cumulative_batches":state.batches,"actual_inputs":inputs,"actual_outputs":outputs,"declared_non_saleable_rejects":rejects,"allocated_person_hours":actual*int(a.hours),"capacity_available_units":capacity,"capacity_used_units":actual*int(a.capacity_units),"capacity_utilization":float(actual*int(a.capacity_units))/capacity if capacity>0 else null,"observed_constraints":constraints})
	var orders: Array=[];var prices: Array=[];var decisions: Array=[];var wages: Array=[]
	for o: Dictionary in e._orders.values():
		if o.buyer!=firm and o.seller!=firm: continue
		var row: Dictionary=e._order_view(o).duplicate(true)
		var known: Dictionary=e._cargo_fulfilment.visible(actor,o.id)
		row["cargo_fulfilment"]=known
		if int(row.get("unresolved_loss_quantity",0))>0 and known.losses.is_empty():
			row["unresolved_loss_quantity"]=null
			row["physical_tracking"]="AWAITING_CONFIRMED_LOSS_NOTICE"
			for cargo: Dictionary in row.shipments:
				if not e._at_place(actor,str(cargo.get("place_id",""))):
					cargo["physical_quantity"]=null;cargo["unresolved_loss_quantity"]=null
		orders.append(row)
		if orders.size()>8: orders.pop_front()
	for r: Dictionary in e._delivery_receipts.values():
		var o: Dictionary=e._orders[r.order_id]
		if o.buyer!=firm and o.seller!=firm: continue
		prices.append({"order_id":o.id,"receipt_id":r.id,"good":o.good,"price":o.price,"quantity":r.quantity,"denomination":o.denomination,"delivered_minute":r.delivered_minute})
		if prices.size()>8:prices.pop_front()
	for c: Dictionary in e._commands.values():
		var who: String=str(c.get("envelope",{}).get("actor",{}).get("id","")) if c.get("envelope",{}).get("actor") is Dictionary else str(c.get("envelope",{}).get("actor",""))
		if who!=firm: continue
		decisions.append({"action_id":c.get("envelope",{}).get("command",{}).get("action_id",""),"result":c.result.duplicate(true)})
		if decisions.size()>8:decisions.pop_front()
	for w: Dictionary in e._wages.values():
		if w.employer!=firm:continue
		wages.append(w.duplicate(true))
		if wages.size()>8:wages.pop_front()
	var quotes: Array=[]
	for g: String in e._spec.sites[site].prices:quotes.append(e._managed_listing_view(site,g).duplicate(true))
	var inventory_status: Dictionary={}
	for good: String in e._goods:
		var reserved: int=e._committed(site,good)
		var incoming_transit: int=0;var outgoing_transit: int=0;var delivered_in: int=0;var delivered_out: int=0
		for o: Dictionary in e._orders.values():
			if o.good!=good:continue
			if o.buyer==firm and o.buyer_site==site:incoming_transit+=int(o.transit);delivered_in+=int(o.delivered)
			if o.seller==firm and o.seller_site==site:outgoing_transit+=int(o.transit);delivered_out+=int(o.delivered)
		inventory_status[good]={"at_site_quantity":e._stocks[site][good],"reserved_at_site_quantity":reserved,"unreserved_at_site_quantity":maxi(0,int(e._stocks[site][good])-reserved),"incoming_accepted_quantity":e._incoming_by_key.get(site+"|"+good,0),"incoming_order_transit_quantity":incoming_transit,"outgoing_order_transit_quantity":outgoing_transit,"cumulative_delivered_in":delivered_in,"cumulative_delivered_out":delivered_out,"basis":"FORMAL_LOTS_RESERVATIONS_AND_CONTRACT_STATUS_NOT_UNCONFIRMED_REMOTE_CARGO_PHYSICS"}
	var payments: Array=e._world.ledger_state.own_transactions(firm)
	if payments.size()>8:payments=payments.slice(payments.size()-8)
	return {"format":FORMAT,"minute":now,"day":e.day,"observer":actor,"visibility":"AUTHORIZED_CURRENT_MANAGER_OWN_BUSINESS","firm_id":firm,"site_id":site,"place_id":e._place(site),"configuration_source":{"case_id":e.config.case_id,"identity_basis":e._business_identity_basis(firm),"recipe_source":"EconomySliceConfig normalized activities; process.source or LEGACY_UNSPECIFIED"},"units":{"goods":e._good_units().duplicate(true),"labor":"person_hour","time":"host_game_minute","currency":"denomination-tagged integer minor units","capacity":"capacity_unit_per_eligible_day"},"activities":activities,"physical_totals":e._physical_totals[site].duplicate(true),"inventory":e._inventory_view(site).duplicate(true),"inventory_status":inventory_status,"finance":e._firm_finance_view(firm).duplicate(true),"wage_claims_latest8":wages,"seller_quotes":quotes,"actual_trade_prices_latest8":prices,"orders_latest8":orders,"payments_latest8":payments,"npc_results_latest8":decisions,"truncation":"Latest 8 records per history; aggregates retain source windows","excluded_internal_state":["OTHER_FIRMS_PRIVATE_STOCK_CASH_PLANS","UNRECEIVED_SUPPLIER_INFORMATION","MACRO_ESTIMATED_FLOW_AND_PRICE","UNCONFIRMED_CARGO_OUTCOME"]}
