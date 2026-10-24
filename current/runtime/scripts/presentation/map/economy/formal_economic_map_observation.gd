class_name FormalEconomicMapObservation
extends RefCounted
## Adapts the existing formal owners to the frozen merchant display contracts.
## No Runtime, clock, stock, order, account or mutable cross-domain database.
const Network = preload("res://scripts/presentation/map/economy/observed_market_network.gd")
const Contacts = preload("res://scripts/presentation/map/economy/observed_market_contacts.gd")
const ORDER_PAGE = 32

static func stamp(world: WorldState) -> Array:
	if world==null: return []
	var native := world.economy_r1
	return [world.get_instance_id(),world.player_state.player_id(),world.game_clock.total_minutes(),world.organization_state.revision(),world.economy_state._state_revision,native._commands.size() if native!=null else 0,native.next_order if native!=null else 0,native.next_shipment if native!=null else 0]

static func canonical_place(id: String) -> String:
	return VNextSpatialCatalog.map_id_to_place_id(VNextSpatialCatalog.place_query_to_map_id(id))

static func known_places(world: WorldState) -> Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	if world==null or world.economy_r1==null:return rows
	var seen:Dictionary={}
	# Bounded identities only. No enterprise stock, price or other-firm truth
	# is requested to admit these already known Catalog anchors to the atlas.
	for source:Dictionary in world.economy_r1.map_site_summaries(world.player_state.player_id(),[],16,true):
		var id:=str(source.place_id)
		if seen.has(id):continue
		var record:=world.spatial_catalog.get_place(id)
		if _fact(world,source,record).is_empty():continue
		var point:=record.duplicate()
		point["id"]=id
		point["display_name"]=str(record.get("name_zh",record.get("name",id)))
		rows.append(point);seen[id]=true
	return rows

static func brief(world: WorldState, places: Array[String], polity_id: String, capital: Dictionary) -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	if world==null: return facts
	var observer := world.player_state.player_id()
	if world.economy_r1!=null:
		for row: Dictionary in world.economy_r1.map_site_summaries(observer,places,12):
			var place := world.spatial_catalog.get_place(str(row.place_id))
			var fact := _fact(world,row,place)
			if not fact.is_empty(): facts.append(fact)
	# A country statistic is labelled as such. Its capital is only a display
	# anchor; it is never evidence of a business, warehouse or city inventory.
	if not polity_id.is_empty() and not capital.is_empty():
		var summary := world.economy_state.country_summary(polity_id)
		var totals := summary.get("daily_totals",{}) as Dictionary
		var fulfillment: Variant = totals.get("fulfillment_bp")
		var place_id := canonical_place(str(capital.get("id","")))
		if fulfillment is float or fulfillment is int:
			if float(fulfillment)>=0 and place_id in places:
				var row := {"source_id":str(summary.get("market_id","")),"subject_id":"aggregate:"+polity_id,"place_id":place_id,"kind":"country_statistics","state":"国家统计 · 满足率 %.1f%%" % (float(fulfillment)/100.0),"basis":"FORMAL_SETTLED_COUNTRY_STATISTICS","priority":40}
				var fact := _fact(world,row,capital)
				if not fact.is_empty():
					fact["position_kind"] = "COUNTRY_STATISTIC_AT_CAPITAL_ANCHOR"
					fact["knowledge"] = "PUBLIC_COUNTRY_STATISTICS"
					facts.append(fact)
	return facts

static func _fact(world: WorldState, row: Dictionary, place: Dictionary) -> Dictionary:
	var coordinates: Variant = place.get("lon_lat")
	if not coordinates is Array or coordinates.size()!=2: return {}
	if not (coordinates[0] is float or coordinates[0] is int) or not (coordinates[1] is float or coordinates[1] is int): return {}
	var ll := Vector2(float(coordinates[0]),float(coordinates[1]))
	if not ll.is_finite() or absf(ll.x)>180 or absf(ll.y)>90: return {}
	var fact := row.duplicate()
	fact.merge({"id":"economy:"+str(row.source_id),"domain":"economy","observer":world.player_state.player_id(),"world_id":world.get_instance_id(),"world_minute":world.game_clock.total_minutes(),"lon_lat":[ll.x,ll.y],"position_kind":"CITY_ANCHOR_NOT_PARCEL","knowledge":"CURRENT_OBSERVER_AUTHORIZED_FACT","maps":["political","economic","geographic"]},true)
	return fact

static func subjects(world: WorldState, polity_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if world==null: return rows
	if world.economy_r1!=null: rows.append_array(world.economy_r1.map_subjects(world.player_state.player_id()))
	if not polity_id.is_empty(): rows.append({"id":"aggregate:"+polity_id,"name":"所选国家 · 统计范围","kind":"aggregate"})
	return rows

static func details(world: WorldState, polity_id: String, requested_subject: String, offset: int = 0, requested_order: String = "") -> Dictionary:
	if world==null: return {}
	var choices := subjects(world,polity_id)
	var subject := requested_subject
	if subject.begins_with("aggregate:"): subject = "aggregate:"+polity_id
	if not choices.any(func(row: Dictionary) -> bool: return row.id==subject): subject = str(choices[0].id) if not choices.is_empty() else ""
	var result := {"world_id":world.get_instance_id(),"minute":world.game_clock.total_minutes(),"date":world.game_clock.current_date(),"world_case":str(world.economy_r1.config.get("case_id","")) if world.economy_r1!=null else "FORMAL_COUNTRY_STATISTICS","observer":world.player_state.player_id(),"subject":subject,"subjects":choices,"source":"当前正式世界 · 只读经济观察","firm":{},"market_network":{},"market_contacts":{},"macro":{},"orders_total":0,"offset":0,"page_size":ORDER_PAGE,"native_enabled":world.economy_r1!=null}
	if subject.begins_with("aggregate:"):
		result["macro"] = world.economy_state.country_summary(subject.trim_prefix("aggregate:"))
		return result
	if world.economy_r1==null or subject.is_empty(): return result
	var observed := LivelihoodAction.query(world,world.player_state.player_id()) if subject==world.player_state.player_id() else LivelihoodAction.query_firm(world,world.player_state.player_id(),subject)
	if observed.is_empty(): return result
	var own: Dictionary = {}
	for key: String in ["day","cash","reserved","inventory","offers","orders","sales_orders","operations","lifecycle","employment","known_jobs","totals","wage_outstanding","wage_matured_unpaid"]:
		if observed.has(key): own[key] = observed[key]
	if subject==world.player_state.player_id():
		own["participation"] = world.personal_economy_state.person_economy(subject)
	# Retain one bounded detail page. Historical records remain in their owner.
	var orders: Array[Dictionary] = []
	var seen: Dictionary = {}
	for key: String in ["orders","sales_orders"]:
		for order: Dictionary in own.get(key,[]):
			if seen.has(str(order.id)): continue
			seen[str(order.id)] = true
			orders.append(order)
	orders.reverse()
	if not requested_order.is_empty():
		for index:int in range(orders.size()):
			if str(orders[index].id)==requested_order:offset=(index/ORDER_PAGE)*ORDER_PAGE;break
	var last_page := (maxi(0,orders.size()-1)/ORDER_PAGE)*ORDER_PAGE
	var start := clampi(offset,0,last_page)
	result["orders_total"] = orders.size()
	result["offset"] = start
	own["orders"] = orders.slice(start,start+ORDER_PAGE)
	own["sales_orders"] = []
	var operations := own.get("operations",[]) as Array
	own["operations"] = operations.slice(0,16)
	var offers := own.get("offers",[]) as Array
	own["offers"] = offers.slice(0,64)
	var received: Array[Dictionary] = []
	for offer: Dictionary in own["offers"]:
		if str(offer.get("from_place_id","")).is_empty() or str(offer.get("to_place_id","")).is_empty(): continue
		var row := offer.duplicate()
		# A quoted quantity is not a procurement permission. The existing
		# business page performs that check when the player requests it.
		row["can_order_one"] = null
		row["quoted_quantity_positive"] = int(row.get("quantity",0))>0
		received.append(row)
	result["firm"] = own
	result["market_network"] = Network.project(own)
	result["market_contacts"] = Contacts.project(own,received,world.game_clock.total_minutes())
	return result
