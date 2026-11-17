extends RefCounted
## Projection only. The host authenticates actor; supplied IDs grant no rights.
const FORMAT: String = "economy_read_v1"
const Process = preload("res://scripts/world/economy_production_process.gd")
const ElectricalProject = preload("res://scripts/content/technology_pilot.gd")

## Shared external projection for personal, managed-firm and read-contract views.
## actor is the actual observer, never the enterprise's configured place.
static func order_view(e: RefCounted, actor: String, order: Dictionary) -> Dictionary:
	var row: Dictionary = e._order_view(order)
	var known: Dictionary = e._cargo_fulfilment.visible(actor, order["id"])
	row["cargo_fulfilment"] = known
	# Redaction must not depend on whether an unseen loss actually exists.
	# One received notice never unlocks subsequent remote physical outcomes.
	row["unresolved_loss_quantity"] = null
	row["physical_tracking"] = "LOCAL_OBSERVATION_AND_RECEIVED_LOSS_RECORDS_ONLY"
	var known_unresolved: int = 0
	for loss: Dictionary in known.get("losses", []):
		if loss["status"] == "ADOPTED": known_unresolved += maxi(0, int(loss["quantity"]) - int(loss["resolved"]))
	row["known_unresolved_loss_quantity"] = known_unresolved
	if actor != order["buyer"]: row.erase("travel_quote")
	if not e._at_place(actor, str(row["to_place_id"])):
		row["collectable_quantity"] = null
		row["can_collect"] = false
		row["can_collect_to_storage"] = false
	for cargo: Dictionary in row["shipments"]:
		if cargo.get("stage") == "TRANSIT" or not e._at_place(actor, str(cargo.get("place_id", ""))):
			cargo["physical_quantity"] = null
			cargo["unresolved_loss_quantity"] = null
			cargo["collectable_quantity"] = null
			cargo["physical_tracking"] = "AWAITING_LOCAL_OBSERVATION_OR_SPECIFIC_NOTICE"
	return row

static func _activities(e: RefCounted, site: String) -> Array[Dictionary]:
	var activities: Array[Dictionary] = []
	for activity: Dictionary in e._spec.sites[site].activities:
		var state: Dictionary = e._site_state[site].activities[activity.id]
		var plan: Dictionary = e._plans.get(site, {}).get("activities", {}).get(activity.id, {})
		var actual: int = int(plan.get("actual", 0))
		var inputs: Dictionary = {}
		var outputs: Dictionary = {}
		var rejects: Dictionary = {}
		for good: String in activity.materials: inputs[good] = actual * int(activity.materials[good])
		for good: String in activity.outputs:
			outputs[good] = actual * int(activity.outputs[good])
			rejects[good] = actual * int(activity.get("process", {}).get("rejects", {}).get(good, 0))
		var reason: String = Process.reason(activity, e.day, int(state.batches))
		var planned: int = int(plan.get("schedule", [{"quantity": 0}])[0].quantity)
		var capacity: int = e._capital.capacity(site, e._production_minute(), activity.id)
		var constraints: Array[String] = []
		if reason not in ["ELIGIBLE", "LEGACY_UNSPECIFIED"]: constraints.append(reason)
		if planned > actual:
			if int(e._labor.get(site, 0)) < planned * int(activity.hours): constraints.append("LABOR_HOURS_BOUND")
			if capacity < planned * int(activity.capacity_units): constraints.append("CAPACITY_BOUND")
			# End-of-day stock is an observation, not reconstructed start stock.
			for good: String in activity.materials:
				if int(activity.materials[good]) > 0 and int(e._stocks[site][good]) < int(activity.materials[good]): constraints.append("CURRENT_MATERIAL_SHORTAGE:" + good)
		activities.append({"id": activity.id, "recipe": activity.duplicate(true), "process_status": reason, "planned_batches": planned, "actual_batches": actual, "cumulative_batches": state.batches, "actual_inputs": inputs, "actual_outputs": outputs, "declared_non_saleable_rejects": rejects, "allocated_person_hours": actual * int(activity.hours), "capacity_available_units": capacity, "capacity_used_units": actual * int(activity.capacity_units), "capacity_utilization": float(actual * int(activity.capacity_units)) / capacity if capacity > 0 else null, "observed_constraints": constraints})
	return activities

static func _observer_allowed(e: RefCounted, observer: String) -> bool:
	return e._world != null and observer == e._world.player_state.player_id() and e._world.person_overlay.is_alive(observer) and e.manages_person(observer)

## A local program visible to its authorized operator. Report original dates,
## including after an asset is stopped. Current capacity uses the live pool.
static func technology(e: RefCounted, observer: String) -> Dictionary:
	var spec := ElectricalProject
	var site: String = spec.SITE
	var firm: String = spec.FIRM
	if not _observer_allowed(e,observer) or e._capital.template(spec.LAB).is_empty() or not e._manager(observer,firm):
		return {}
	var minute: int = e._world.game_clock.total_minutes()
	var lab: Dictionary = {}
	var installation: Dictionary = {}
	for id: String in e._capital._site_projects.get(site,[]):
		var project: Dictionary = e._capital.projects[id]
		if project.status=="CANCELLED": continue
		if project.template_id==spec.LAB: lab=project
		elif project.template_id==spec.INSTALL: installation=project
	var motor_source: Dictionary = {}
	var available: Array = e._lots.selection("SITE|"+site,spec.MOTOR,1)
	for input: Dictionary in available if not available.is_empty() else installation.get("material_sources",[]):
		var source: Dictionary = e._lots.sources.get(input.source_id,{})
		if source.get("good")==spec.MOTOR:
			motor_source=source
			break
	var completed: int = int(installation.get("completed_minute",-1))
	var mill: Dictionary = e._site_state[site]["activities"][spec.MILL]
	var live_capacity: int = e._capital.capacity(site,minute,spec.MILL) if mill.enabled and e._site_producing(site,minute) else 0
	var base_capacity: int = int(e._spec["sites"][site]["capacity"])
	var asset_id := str(installation.get("asset_id",""))
	var asset: Dictionary = e._capital.asset_state(asset_id,minute) if completed>=0 else {}
	var adopted: bool = live_capacity>base_capacity and asset.get("status")=="ACTIVE" and asset.get("installed_site")==site and e._capital.service_available(asset_id,minute)
	var trial_capacity: int = e._capital.capacity(site,minute,spec.TRIAL)
	var trial: Dictionary = e._site_state[site]["activities"][spec.TRIAL]
	var milestones: Array[Dictionary] = []
	if int(motor_source.get("formed_minute",0))>0:
		milestones.append({"id":"motor","minute":motor_source.formed_minute,
			"kind":"工艺验证","title":"磨粉电机样机通过校核","effect":"实物样机已形成，可用于原设备安装项目。"})
	if completed>0:
		milestones.append({"id":"drive","minute":completed,
			"kind":"工业采用","title":"巴黎磨坊投用电力传动","effect":"安装为原磨粉工艺增加 2 单位日生产能力。"})
	var option: String = ""
	var template_id: String = ""
	var status: String = ""
	var work: int = 0
	if completed>=0:
		status="电力设备在用" if adopted else "电力设备当前不可用"
	elif not installation.is_empty():
		status="电力设备安装中"
		work=e._capital.work_hours(installation)
	elif not motor_source.is_empty() and not available.is_empty():
		status="样机已验证"
		option="install_drive"
		template_id=spec.INSTALL
	elif trial.enabled:
		status="样机试制中"
	elif int(lab.get("completed_minute",-1))>=0:
		status="试验台就绪" if trial_capacity>=spec.TRIAL_CAPACITY else "试验台当前不可用"
		if trial_capacity>=spec.TRIAL_CAPACITY: option="authorize_trial"
	elif not lab.is_empty():
		status="试验台建设中"
		work=e._capital.work_hours(lab)
	else:
		status="已有工场与技术人员，可建设试验台"
		option="build_lab"
		template_id=spec.LAB
	var blocker := ""
	if not template_id.is_empty():
		var terms: Dictionary = e._capital.template(template_id)
		blocker=e._capital.starting_blocker(terms,int(terms["budget"]))
	return {"firm":firm,"site":site,"capacity":live_capacity,"base_capacity":base_capacity,"adopted":adopted,
		"status":status,"opportunity":option,"work":work,"milestones":milestones,
		"flour":int(e._physical_totals[site]["produced"]["flour"]),"blocker":blocker}

static func _units(e: RefCounted) -> Dictionary:
	return {"goods": e._good_units().duplicate(true), "labor": "person_hour", "time": "host_game_minute", "currency": "denomination-tagged integer minor units", "capacity": "capacity_unit_per_eligible_day"}

static func _logistics_city(cities: Dictionary, place: String) -> Dictionary:
	if not cities.has(place): cities[place]={"place_id":place,"stock_sites":0,"warehouses":0,"stock":{},"reserved":{},"custody":{},"pending_ids":{},"transit_ids":{}}
	return cities[place]

static func _logistics_add(target: Dictionary, values: Dictionary) -> void:
	for good: String in values:
		if int(values[good])>0: target[good]=int(target.get(good,0))+int(values[good])

## Current authorized sites and bounded contract responsibility, not a cargo
## position service. No Ledger/history scan and no stock or time mutation.
static func logistics(e: RefCounted, observer: String, places: Array[String], include_warehouse_terms: bool = false) -> Dictionary:
	if not _observer_allowed(e,observer): return {}
	var result: Dictionary={"nodes":[],"links":[],"route_activity":[],"units":e._good_units().duplicate(),"truncated":false,"orders_scanned":0,"minute":e._world.game_clock.total_minutes(),"position_basis":"CITY_ANCHORS_NOT_WAREHOUSE_PARCELS","transport_basis":"AUTHORIZED_CONTRACT_RESPONSIBILITY_NOT_LIVE_POSITIONS"}
	var wanted: Array[String]=[]
	for place: String in places:
		if not wanted.has(place) and wanted.size()<24: wanted.append(place)
	var cities: Dictionary={}
	var subjects: Array[String]=[observer]
	var site_count := 0
	for subject: Dictionary in e.map_subjects(observer):
		var firm := str(subject.id)
		if subject.kind!="firm" or not e._manager(observer,firm): continue
		subjects.append(firm)
		for site: String in e._spec.firms[firm].sites:
			var place: String=e._place(site)
			if place not in wanted: continue
			if site_count>=32: result.truncated=true;break
			site_count+=1
			var city := _logistics_city(cities,place)
			city.stock_sites+=1
			var stock: Dictionary=e._stocks.get(site,{})
			_logistics_add(city.stock,stock)
			for good: String in stock:
				var reserved: int=e._committed(site,good)
				if reserved>0: city.reserved[good]=int(city.reserved.get(good,0))+reserved
	var warehouse_ids: Dictionary={}
	var known_storage_offers: Dictionary={}
	var custody_ids: Dictionary={}
	for facility: Dictionary in e._service_market._facilities.values():
		var place: String=e._place(str(facility.site_id))
		if facility.kind=="STORAGE" and str(facility.provider) in subjects and place in wanted:
			warehouse_ids[str(facility.id)]=true;_logistics_city(cities,place).warehouses+=1
	for subject: String in subjects:
		# Existing service read applies received-notice/loss redaction and bounds
		# custody history to eight contracts. Owned stock stays separate.
		var services: Dictionary=e._service_market.view(subject)
		if (e._service_market._by_firm.get(subject,[]) as Array).size()>8: result.truncated=true
		for quote: Dictionary in services.get("quotes",[]):
			if quote.kind!="STORAGE" or str(quote.place_id) not in wanted: continue
			var city := _logistics_city(cities,str(quote.place_id))
			if not warehouse_ids.has(str(quote.facility_id)):
				warehouse_ids[str(quote.facility_id)]=true
				city.warehouses+=1
			if not include_warehouse_terms or not quote.enabled or not quote.valid or known_storage_offers.has(quote.id): continue
			known_storage_offers[quote.id]=true
			var facility: Dictionary = e._service_market._facilities[quote.facility_id]
			if not city.has("warehouse_terms"): city["warehouse_terms"]=[]
			city.warehouse_terms.append({"site_id":quote.site_id,"free_capacity":quote.available_capacity,"capacity":facility.capacity,
				"price":quote.price,"denomination":quote.denomination})
		for contract: Dictionary in services.get("contracts",[]):
			if contract.kind!="STORAGE" or custody_ids.has(str(contract.id)): continue
			var place: String=e._place(str(contract.provider_site))
			if place not in wanted: continue
			custody_ids[str(contract.id)]=true
			var city := _logistics_city(cities,place)
			if not warehouse_ids.has(str(contract.facility_id)):
				warehouse_ids[str(contract.facility_id)]=true;city.warehouses+=1
			var q := int(contract.get("remaining_custody_quantity",0))
			if q>0: city.custody[str(contract.good)]=int(city.custody.get(str(contract.good),0))+q
	var seen: Dictionary={}
	var groups: Dictionary={}
	var route_activity: Dictionary={}
	for subject: String in subjects:
		var ids: Array=e._orders_by_subject.get(subject,[])
		var active_ids: Array[String]=[]
		for id: String in e._active_by_buyer.get(subject,{}):
			if active_ids.size()>=64: result.truncated=true;break
			active_ids.append(id)
		var active_position := 0
		var position := ids.size()-1
		var scanned := 0
		while (active_position<active_ids.size() or position>=0) and scanned<128 and int(result.orders_scanned)<256:
			var id: String
			if active_position<active_ids.size(): id=active_ids[active_position];active_position+=1
			else: id=str(ids[position]);position-=1
			scanned+=1;result.orders_scanned+=1
			if seen.has(id): continue
			seen[id]=true
			var order: Dictionary=e._orders.get(id,{})
			if order.is_empty() or subject not in [str(order.buyer),str(order.seller)]: continue
			var pending := int(order.get("pending",0))>0
			var transit := int(order.get("transit",0))>0
			if not pending and not transit: continue
			var a := str(order.get("from_place_id",""));var b := str(order.get("to_place_id",""))
			# Accepted route responsibility only. This does not locate a shipment
			# on its current leg, nor disclose a remote physical quantity.
			if transit:
				for leg: Dictionary in order.get("route_legs",[]):
					var edge: Dictionary=e._route_rows.get(str(leg.get("edge_id","")),{})
					var source := str(edge.get("source_link_id",""))
					if not source.begins_with("rail_") and source!="shipping_channel": continue
					var direction := str(edge.get("from_place_id",""))
					var rail_key := source+"|"+direction
					if route_activity.has(rail_key): route_activity[rail_key].orders+=1
					elif route_activity.size()<16: route_activity[rail_key]={"source_link_id":source,"from":direction,"to":str(edge.get("to_place_id","")),"orders":1}
					else: result.truncated=true
			if a not in wanted and b not in wanted: continue
			for place: String in [a,b]:
				if place not in wanted: continue
				var city := _logistics_city(cities,place)
				if pending: city.pending_ids[id]=true
				if transit: city.transit_ids[id]=true
			var status := "TRANSIT" if transit else "PENDING"
			var key := a+"|"+b+"|"+status
			if groups.has(key): groups[key].source_count+=1
			elif groups.size()<16: groups[key]={"id":"logistics:"+key,"from":a,"to":b,"kind":"contract","status":status,"directed":true,"animate":false,"source_count":1,"state":"订单运输联系，非车船位置"}
			else: result.truncated=true
		if position>=0: result.truncated=true
	for city: Dictionary in cities.values():
		city["pending_orders"]=city.pending_ids.size();city["transit_orders"]=city.transit_ids.size()
		city.erase("pending_ids");city.erase("transit_ids");result.nodes.append(city)
	result.links.assign(groups.values())
	result.route_activity.assign(route_activity.values())
	return result

static func _configuration_source(e: RefCounted, firm: String) -> Dictionary:
	return {"case_id": e.config.get("case_id", "LEGACY_UNSPECIFIED"), "identity_basis": e._business_identity_basis(firm), "recipe_source": "EconomySliceConfig normalized activities; process.source or LEGACY_UNSPECIFIED"}

## Market display borrows known offers and received publications. Country is a
## filter over real places, never a pooled inventory or an exchange institution.
static func market(e: RefCounted, observer: String, include_activity: bool = false) -> Dictionary:
	if not _observer_allowed(e,observer): return {}
	var result: Dictionary={"minute":e._world.game_clock.total_minutes(),"offers":[],"history":[],"places":[],"goods":[],"managed_firms":[],"truncated":false,"visibility":"KNOWN_OFFERS_RECEIVED_NOTICES_AND_OWN_DELIVERIES","demand":null}
	var places: Dictionary={}
	var wanted: Array[String]=[]
	var hubs: Dictionary=e.market_hub_view(observer,wanted,96)
	for hub: Dictionary in hubs.get("hubs",hubs.get("places",[])):
		_market_place(e,places,str(hub.get("place_id","")))
	var rows: Array[Dictionary]=e.personal_market_rows(observer,97,0)
	result.truncated=rows.size()>96
	for i: int in mini(rows.size(),96):
		var row: Dictionary=rows[i].duplicate()
		var site: String=str(row.seller_site)
		row["place_id"]=e._place(site);row["seller"]=e._owner(site)
		_market_place(e,places,row.place_id)
		result.offers.append(row)
	for notice: Dictionary in e.commercial_information(observer):
		if notice.get("kind")!="GOODS": continue
		var q: Dictionary=notice.get("observed_quote",{})
		if not q.has("price") or not q.has("denomination"): continue
		_market_place(e,places,str(notice.place_id))
		result.history.append({"minute":notice.delivered_minute,"good":str(notice.item),"seller_site":notice.site_id,"place_id":notice.place_id,"price_milli":q.get("price_milli",int(q.price)*1000),"denomination":q.denomination,"kind":"quote","quantity":q.get("quantity")})
	# Only the observer's original order index. Unrelated firm contracts and
	# undisclosed remote cargo are not a national turnover series.
	var ids: Array=e._orders_by_subject.get(observer,[])
	result.truncated=bool(result.truncated) or ids.size()>64 or bool(hubs.get("truncated",false))
	var receipt_count: int=0
	for i: int in range(ids.size()-1,maxi(-1,ids.size()-65),-1):
		var order: Dictionary=e._orders[ids[i]]
		if order.kind!="SALE" or observer not in [str(order.buyer),str(order.seller)]: continue
		for receipt_id: String in e._deliveries_by_order.get(order.id,[]):
			if receipt_count>=64: result.truncated=true;break
			var receipt: Dictionary=e._delivery_receipts[receipt_id]
			var q: int=int(receipt.quantity)
			if q<=0: continue
			var amount: int=e._receipt_goods_amount(receipt,order)
			var price: float=float(amount)*1000.0/q
			_market_place(e,places,str(order.from_place_id))
			result.history.append({"minute":receipt.get("delivered_minute",int(receipt.delivered_day)*1440),"good":order.good,"seller_site":order.seller_site,"place_id":order.from_place_id,"price_milli":price,"denomination":order.denomination,"kind":"trade","quantity":q})
			receipt_count+=1
	for good: String in e._goods: result.goods.append(e.personal_commodity("native:"+good))
	for subject: Dictionary in e.map_subjects(observer):
		if subject.kind=="firm": result.managed_firms.append(subject.id)
	result.places.assign(places.values())
	if include_activity: result["activity"]=_market_activity(e,observer,result.managed_firms)
	return result

## Bounded projection of existing subject indexes. Never scan all contracts or
## publish another firm's cash/stock. These rows do not become new history.
static func _market_activity(e: RefCounted, observer: String, managed: Array) -> Dictionary:
	var subjects: Array[String]=[observer]
	for firm: String in managed:
		if subjects.size()>=9: break
		subjects.append(firm)
	var rows: Array[Dictionary]=[]
	var seen: Dictionary={}
	var truncated := managed.size()>8
	for subject: String in subjects:
		var ids: Array=e._orders_by_subject.get(subject,[])
		truncated=truncated or ids.size()>16
		for i: int in range(ids.size()-1,maxi(-1,ids.size()-17),-1):
			var order: Dictionary=e._orders[ids[i]]
			if seen.has(order.id) or order.kind!="SALE": continue
			if subject!=observer and not e._manager(observer,subject): continue
			if subject not in [str(order.buyer),str(order.seller)]: continue
			seen[order.id]=true
			var row: Dictionary={}
			for field: String in ["id","buyer","seller","good","quantity","pending","transit","delivered","cancelled","denomination","from_place_id","to_place_id","accepted_minute"]: row[field]=order.get(field)
			row["paid_goods_amount"]=e._goods_total(order,int(order.delivered))
			row["paid_freight_amount"]=int(order.delivered)*e._freight(order.route_legs)
			row["awaiting_quantity"]=0
			if str(order.buyer)==observer:
				for cargo_id: String in e._shipments_by_order.get(order.id,{}):
					var cargo: Dictionary=e._shipments[cargo_id]
					if cargo.stage=="AWAITING_RECIPIENT": row["awaiting_quantity"]+=int(cargo.quantity)
			row["managed_firm"]=subject if subject!=observer else ""
			rows.append(row)
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(str(a.id).trim_prefix("order:"))>int(str(b.id).trim_prefix("order:")))
	if rows.size()>24: rows.resize(24);truncated=true
	return {"orders":rows,"truncated":truncated,"basis":"OWN_AND_CURRENT_MANAGER_CONTRACTS_NOT_GLOBAL_TURNOVER"}

static func _market_place(e: RefCounted, places: Dictionary, id: String) -> void:
	if id.is_empty() or places.has(id) or places.size()>=96: return
	var source: Dictionary=e._world.spatial_catalog.get_place(id)
	if source.is_empty(): return
	places[id]={"place_id":id,"name_zh":source.get("name_zh",source.get("name",id)),"parent_country_id":source.get("parent_country_id",""),"lon_lat":source.get("lon_lat",[])}

## Current inventory and accepted contractual incoming only. No all-order scan or
## unconfirmed remote transit/loss quantity is needed to describe this stock point.
static func _inventory_status(e: RefCounted, key: String, stock: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if stock.is_empty(): return result
	for good: String in e._goods:
		var quantity: int = int(stock.get(good, 0))
		var reserved: int = e._committed(key, good)
		result[good] = {"at_site_quantity": quantity, "reserved_at_site_quantity": reserved, "unreserved_at_site_quantity": maxi(0, quantity - reserved), "incoming_accepted_quantity": e._incoming_by_key.get(key + "|" + good, 0), "basis": "CURRENT_AUTHORIZED_STOCK_RESERVATIONS_AND_ACCEPTED_INCOMING_NOT_REMOTE_CARGO_PHYSICS"}
	return result

## Research details are opt-in. Activities share the existing own() construction,
## but this path never asks Ledger, histories, finance, offers or all orders.
static func production(e: RefCounted, observer: String, firm: String, site: String) -> Dictionary:
	if not _observer_allowed(e, observer) or not e._spec.firms.has(firm) or not e._manager(observer, firm) or not e._spec.sites.has(site) or e._owner(site) != firm or not e._stocks.has(site): return {}
	return {"format": "economy_production_read_v1", "minute": e._world.game_clock.total_minutes(), "day": e.day, "observer": observer, "visibility": "AUTHORIZED_CURRENT_MANAGER_OWN_BUSINESS", "firm_id": firm, "site_id": site, "place_id": e._place(site), "configuration_source": _configuration_source(e, firm), "units": _units(e), "activities": _activities(e, site), "inventory_status": _inventory_status(e, site, e._stocks[site])}

## Offset is a reverse offset into the original subject index, not a count of
## site-matching rows. Each page examines at most 256 IDs and returns at most 32.
## The index is borrowed; do not duplicate or sort an entire subject's history.
static func map_subject(e: RefCounted, observer: String, subject: String, site: String = "", offset: int = 0, limit: int = 32) -> Dictionary:
	if subject.is_empty() or not _observer_allowed(e, observer): return {}
	var managed: bool = e._spec.firms.has(subject) and e._manager(observer, subject)
	if not managed and (subject != observer or not e._actors.has(subject)): return {}
	if not site.is_empty() and (not managed or not e._spec.sites.has(site) or e._owner(site) != subject): return {}
	var account_id: String = e._account(subject)
	var account: Dictionary = e._world.ledger_state.account(account_id)
	if account.is_empty(): return {}
	var stock: Dictionary = {}
	var stock_key: String = ""
	if not site.is_empty():
		stock_key = site
		stock = (e._stocks.get(site, {}) as Dictionary).duplicate(true)
	elif not managed:
		# Personal ownership aggregates include remote stored and freight cargo.
		# Only carried/current-place accessible goods are locally observable here.
		stock_key = subject
		stock = e.personal_inventory(subject)
	var inventory_status: Dictionary = _inventory_status(e, stock_key, stock) if not stock_key.is_empty() else {}
	var free_inventory: Dictionary = {}
	var committed_inventory: Dictionary = {}
	for good: String in inventory_status:
		free_inventory[good] = inventory_status[good]["unreserved_at_site_quantity"]
		committed_inventory[good] = inventory_status[good]["reserved_at_site_quantity"]
	var operations: Array[Dictionary] = []
	if not site.is_empty():
		var state: Dictionary = e._site_state[site]
		operations.append({"firm_id": subject, "site_id": site, "place_id": e._place(site), "stock_place_id": e._place(site), "free_inventory": free_inventory.duplicate(true), "committed_inventory": committed_inventory.duplicate(true), "enabled": state["enabled"], "production_enabled": state["production_enabled"], "accepting_business": state["accepting_business"], "operating": e._site_operating(site), "base_capacity": e._spec.sites[site]["capacity"], "shared_capacity": e.site_capacity(site), "capacity_basis": "CONFIGURED_BASE_PLUS_ACTUAL_SERVICEABLE_INSTALLED_CAPITAL", "inventory": stock.duplicate(true), "inventory_status": inventory_status.duplicate(true)})
	var ids: Array = e._orders_by_subject.get(subject, [])
	var start: int = clampi(offset, 0, ids.size())
	var page_size: int = clampi(limit, 0, 32)
	var position: int = ids.size() - 1 - start
	var scanned: int = 0
	var orders: Array[Dictionary] = []
	while position >= 0 and orders.size() < page_size and scanned < 256:
		var id: String = str(ids[position])
		position -= 1
		scanned += 1
		var order: Dictionary = e._orders.get(id, {})
		if order.is_empty() or (order["buyer"] != subject and order["seller"] != subject): continue
		if not site.is_empty() and not ((order["buyer"] == subject and order.get("buyer_site", "") == site) or (order["seller"] == subject and order.get("seller_site", "") == site)): continue
		orders.append(order_view(e, observer, order))
	var more: bool = position >= 0
	var firm: Dictionary = {"subject_id": subject, "firm_id": subject if managed else "", "site_id": site, "current_place_id": e._place(site if not site.is_empty() else subject), "account_id": account_id, "denomination": account["denomination"], "cash": e._world.ledger_state.balance(account_id), "reserved": e._world.ledger_state.reserved_balance(account_id), "available": e._world.ledger_state.available_balance(account_id), "inventory": stock, "free_inventory": free_inventory, "committed_inventory": committed_inventory, "inventory_status": inventory_status, "inventory_basis": "SELECTED_OWN_SITE" if not site.is_empty() else "CURRENT_PLACE_ACCESSIBLE_PERSONAL_STOCK" if not managed else "SELECT_A_SITE_NO_FIRM_WIDE_STOCK_AGGREGATE", "operations": operations, "orders": orders, "sales_orders": []}
	return {"format": "economy_map_subject_v1", "minute": e._world.game_clock.total_minutes(), "day": e.day, "observer": observer, "subject_id": subject, "site_id": site, "visibility": "AUTHORIZED_CURRENT_MANAGER_OWN_BUSINESS" if managed else "OBSERVER_PERSONAL_LOCAL_STOCK_AND_OWN_CONTRACTS", "firm": firm, "orders_total": ids.size(), "offset": start, "page_size": page_size, "next_offset": start + scanned, "truncated": more, "scanned": scanned, "scan_limit": 256, "pagination_basis": "LATEST_SUBJECT_INDEX_REVERSE_OFFSET_SITE_FILTER_IS_BOUNDED_NOT_A_FILTERED_TOTAL", "physical_tracking": "LOCAL_OBSERVATION_AND_RECEIVED_LOSS_RECORDS_ONLY"}

static func own(e: RefCounted, actor: String, firm: String, site: String) -> Dictionary:
	if not e._spec.firms.has(firm) or not e._manager(actor, firm) or not e._spec.sites.has(site) or e._owner(site) != firm: return {}
	var now: int = e._world.game_clock.total_minutes()
	var activities: Array[Dictionary] = _activities(e, site)
	var orders: Array[Dictionary] = []
	var prices: Array[Dictionary] = []
	var decisions: Array[Dictionary] = []
	var wages: Array[Dictionary] = []
	for order: Dictionary in e._orders.values():
		if order.buyer != firm and order.seller != firm: continue
		orders.append(order_view(e, actor, order))
		if orders.size() > 8: orders.pop_front()
	for receipt: Dictionary in e._delivery_receipts.values():
		var order: Dictionary = e._orders[receipt.order_id]
		if order.buyer != firm and order.seller != firm: continue
		prices.append({"order_id": order.id, "receipt_id": receipt.id, "good": order.good, "price": order.price, "quantity": receipt.quantity, "denomination": order.denomination, "delivered_minute": receipt.delivered_minute})
		if prices.size() > 8: prices.pop_front()
	for command: Dictionary in e._commands.values():
		var who: String = str(command.get("envelope", {}).get("actor", {}).get("id", "")) if command.get("envelope", {}).get("actor") is Dictionary else str(command.get("envelope", {}).get("actor", ""))
		if who != firm: continue
		decisions.append({"action_id": command.get("envelope", {}).get("command", {}).get("action_id", ""), "result": command.result.duplicate(true)})
		if decisions.size() > 8: decisions.pop_front()
	for wage: Dictionary in e._wages.values():
		if wage.employer != firm: continue
		wages.append(wage.duplicate(true))
		if wages.size() > 8: wages.pop_front()
	var quotes: Array[Dictionary] = []
	for good: String in e._spec.sites[site].prices:
		quotes.append({"site_id": site, "good": good, "price": e._price(site, good), "denomination": e._sale_currency(firm), "policy": e._price_policy(site, good).duplicate(true), "state": e._quote_state.get(site + "|" + good, {}).duplicate(true), "published_quote": e._local_quotes.current(site, good).duplicate(true), "basis": "OWN_POSTED_TERMS_NOT_ACCEPTED_TRADE"})
	var inventory_status: Dictionary = {}
	for good: String in e._goods:
		var reserved: int = e._committed(site, good)
		var incoming_transit: int = 0
		var outgoing_transit: int = 0
		var delivered_in: int = 0
		var delivered_out: int = 0
		for order: Dictionary in e._orders.values():
			if order.good != good: continue
			if order.buyer == firm and order.buyer_site == site:
				incoming_transit += int(order.transit)
				delivered_in += int(order.delivered)
			if order.seller == firm and order.seller_site == site:
				outgoing_transit += int(order.transit)
				delivered_out += int(order.delivered)
		inventory_status[good] = {"at_site_quantity": e._stocks[site][good], "reserved_at_site_quantity": reserved, "unreserved_at_site_quantity": maxi(0, int(e._stocks[site][good]) - reserved), "incoming_accepted_quantity": e._incoming_by_key.get(site + "|" + good, 0), "incoming_order_transit_quantity": incoming_transit, "outgoing_order_transit_quantity": outgoing_transit, "cumulative_delivered_in": delivered_in, "cumulative_delivered_out": delivered_out, "basis": "FORMAL_LOTS_RESERVATIONS_AND_CONTRACT_STATUS_NOT_UNCONFIRMED_REMOTE_CARGO_PHYSICS"}
	var payments: Array = e._world.ledger_state.own_transactions(firm)
	if payments.size() > 8: payments = payments.slice(payments.size() - 8)
	return {"format": FORMAT, "minute": now, "day": e.day, "observer": actor, "visibility": "AUTHORIZED_CURRENT_MANAGER_OWN_BUSINESS", "firm_id": firm, "site_id": site, "place_id": e._place(site), "configuration_source": _configuration_source(e, firm), "units": _units(e), "activities": activities, "physical_totals": e._physical_totals[site].duplicate(true), "inventory": e._inventory_view(site).duplicate(true), "inventory_status": inventory_status, "finance": e._firm_finance_view(firm).duplicate(true), "wage_claims_latest8": wages, "seller_quotes": quotes, "actual_trade_prices_latest8": prices, "orders_latest8": orders, "payments_latest8": payments, "npc_results_latest8": decisions, "truncation": "Latest 8 records per history; aggregates retain source windows", "excluded_internal_state": ["OTHER_FIRMS_PRIVATE_STOCK_CASH_PLANS", "UNRECEIVED_SUPPLIER_INFORMATION", "MACRO_ESTIMATED_FLOW_AND_PRICE", "UNCONFIRMED_CARGO_OUTCOME"]}
