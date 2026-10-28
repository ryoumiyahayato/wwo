class_name FormalEconomicMapObservation
extends RefCounted
## Detached observer projections. No clock, stock, account or routing authority.
const Network = preload("res://scripts/presentation/map/economy/observed_market_network.gd")
const Contacts = preload("res://scripts/presentation/map/economy/observed_market_contacts.gd")
const ORDER_PAGE = 32
const NODE_BUDGET = 128
const PLACE_BUDGET = 96
const FACT_BUDGET = 64
static var _hub_stamp: Array = []
static var _hub_data: Dictionary = {}
static var _city_stamp: Array = []
static var _city_data: Dictionary = {}

static func stamp(world: WorldState) -> Array:
	if world==null:return []
	var native:=world.economy_r1
	return [world.get_instance_id(),world.player_state.player_id(),world.game_clock.total_minutes(),world.organization_state.revision(),world.economy_state._state_revision,native._commands.size() if native!=null else 0,native.next_order if native!=null else 0,native.next_shipment if native!=null else 0,native.network_revision() if native!=null else 0]

static func identity_stamp(world: WorldState) -> Array:
	if world==null:return []
	var native:=world.economy_r1
	return [world.get_instance_id(),world.player_state.player_id(),world.organization_state.revision(),native.network_revision() if native!=null else 0,native._commands.size() if native!=null else 0,native._receipts.size() if native!=null else 0,native._enterprise_changes.size() if native!=null else 0,native.day if native!=null else 0]

static func hubs(world: WorldState) -> Dictionary:
	if world==null or world.economy_r1==null:return {}
	var key:=identity_stamp(world)
	if key!=_hub_stamp:
		_hub_stamp=key
		_hub_data=world.economy_r1.market_hub_view(world.player_state.player_id(),[],PLACE_BUDGET)
	return _hub_data

static func node_network(world: WorldState, places: Array[String] = []) -> Dictionary:
	# Establishment identities are requested only for the inspected city.
	if world==null or world.economy_r1==null or places.is_empty():return {}
	var key:Array=[identity_stamp(world),places]
	if key!=_city_stamp:
		_city_stamp=key
		_city_data=world.economy_r1.network_view(world.player_state.player_id(),places,NODE_BUDGET)
	return _city_data

static func canonical_place(id: String) -> String:
	return VNextSpatialCatalog.map_id_to_place_id(VNextSpatialCatalog.place_query_to_map_id(id))

static func _coordinates(place: Dictionary) -> bool:
	var coordinates:Variant=place.get("lon_lat")
	if not coordinates is Array or coordinates.size()!=2:return false
	if not (coordinates[0] is int or coordinates[0] is float) or not (coordinates[1] is int or coordinates[1] is float):return false
	var ll:=Vector2(float(coordinates[0]),float(coordinates[1]))
	return ll.is_finite() and absf(ll.x)<=180 and absf(ll.y)<=90

static func known_places(world: WorldState) -> Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	if world==null:return rows
	for hub:Dictionary in hubs(world).get("hubs",[]):
		var id:=str(hub.get("place_id",""))
		var record:=world.spatial_catalog.get_place(id)
		if not _coordinates(record):continue
		var point:=record.duplicate()
		point["id"]=id;point["display_name"]=str(hub.get("label",record.get("name_zh",id)))
		rows.append(point)
	return rows

static func brief(world: WorldState, places: Array[String], polity_id: String, capital: Dictionary) -> Array[Dictionary]:
	var facts:Array[Dictionary]=[]
	if world==null:return facts
	for hub:Dictionary in hubs(world).get("hubs",[]):
		var id:=str(hub.get("place_id",""))
		if id not in places:continue
		var row:Dictionary=hub.duplicate()
		row.merge({"source_id":id,"subject_id":"","kind":"economic_hub","state":"已知经济主体 %s · 站点 %s"%[str(hub.get("known_subject_count","未知")),str(hub.get("known_site_count","未知"))],"basis":"PUBLIC_OR_RECEIVED_CITY_IDENTITIES","priority":70})
		var fact:=_fact(world,row,world.spatial_catalog.get_place(id))
		if not fact.is_empty():facts.append(fact)
		if facts.size()>=FACT_BUDGET-1:break
	if not polity_id.is_empty() and not capital.is_empty():
		var summary:=world.economy_state.country_summary(polity_id)
		var fulfillment:Variant=summary.get("daily_totals",{}).get("fulfillment_bp")
		var place_id:=canonical_place(str(capital.get("id","")))
		if (fulfillment is float or fulfillment is int) and float(fulfillment)>=0 and place_id in places:
			var row:Dictionary={"source_id":str(summary.get("market_id","")),"subject_id":"aggregate:"+polity_id,"place_id":place_id,"kind":"country_statistics","state":"国家统计 · 满足率 %.1f%%"%(float(fulfillment)/100.0),"basis":"FORMAL_SETTLED_COUNTRY_STATISTICS","priority":40}
			var fact:=_fact(world,row,capital)
			if not fact.is_empty():
				fact["position_kind"]="COUNTRY_STATISTIC_AT_CAPITAL_ANCHOR";fact["knowledge"]="PUBLIC_COUNTRY_STATISTICS";facts.append(fact)
	return facts

static func _fact(world: WorldState, row: Dictionary, place: Dictionary) -> Dictionary:
	if not _coordinates(place):return {}
	var fact:=row.duplicate()
	fact.merge({"id":"economy:"+str(row.source_id),"domain":"economy","observer":world.player_state.player_id(),"world_id":world.get_instance_id(),"world_minute":world.game_clock.total_minutes(),"lon_lat":(place.lon_lat as Array).duplicate(),"position_kind":"CITY_ANCHOR_NOT_PARCEL","knowledge":"PUBLIC_OR_RECEIVED_IDENTITY_NOT_PRIVATE_BUSINESS_DATA","maps":["political","economic","geographic"]},true)
	return fact

static func subjects(world: WorldState, polity_id: String) -> Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	if world==null:return rows
	if world.economy_r1!=null:rows.append_array(world.economy_r1.map_subjects(world.player_state.player_id()))
	if not polity_id.is_empty():rows.append({"id":"aggregate:"+polity_id,"name":"国家统计（非城市库存）","kind":"aggregate"})
	return rows

static func overview(world: WorldState, polity_id: String, place_id: String = "", subject: String = "") -> Dictionary:
	if world==null:return {}
	var world_case:=str(world.economy_r1.config.get("case_id","")) if world.economy_r1!=null else "FORMAL_COUNTRY_STATISTICS"
	var notice:="开发情景：非历史企业；禀赋、配方、工资与运力为开发假设。" if world_case.contains("DEVELOPMENT") else "巴黎普通开局企业为有限模拟、非历史企业。" if world_case.contains("PARIS") else "身份按现有公开或已收到资料列示。"
	var known_hubs:=hubs(world)
	return {"world_id":world.get_instance_id(),"minute":world.game_clock.total_minutes(),"date":world.game_clock.current_date(),"world_case":world_case,"observer":world.player_state.player_id(),"subject":subject,"selected_place":place_id,"authorized_subjects":subjects(world,polity_id),"subjects":[],"hubs":known_hubs,"node_network":{},"firm":{},"market_network":{},"market_contacts":{},"production_details":{},"macro":{},"orders_total":0,"offset":0,"next_offset":0,"page_size":ORDER_PAGE,"native_enabled":world.economy_r1!=null,"details_loaded":false,"identity_notice":notice,"read_scope":{"kind":"HUB_IDENTITIES_ONLY","identity_limit":PLACE_BUDGET,"identity_truncated":known_hubs.get("truncated")}}

static func details(world: WorldState, polity_id: String, requested_subject: String, offset: int = 0, requested_order: String = "", place_id: String = "", site_id: String = "", research: bool = false) -> Dictionary:
	var result:=overview(world,polity_id,place_id,requested_subject)
	if result.is_empty():return result
	result["details_loaded"]=true;result["research"]=research
	var city:=node_network(world,[place_id]) if not place_id.is_empty() else {}
	result["node_network"]=city
	result["read_scope"]={"kind":"CITY_IDENTITIES_ONLY","identity_limit":NODE_BUDGET,"identity_truncated":city.get("truncated")}
	var choices:Array[Dictionary]=[{"id":"","name":"城市总览","kind":"hub"}]
	var authorized:Dictionary={}
	for row:Dictionary in result.authorized_subjects:authorized[str(row.id)]=row
	var seen:Dictionary={}
	for node:Dictionary in city.get("nodes",[]):
		var firm:=str(node.get("firm_id",""))
		var producer:bool=str(node.get("kind",""))=="local_producer"
		if producer:firm=str(node.get("id",""))
		if str(node.get("place_id",""))!=place_id or firm.is_empty() or seen.has(firm):continue
		seen[firm]=true
		choices.append({"id":firm,"name":"本地生产者（公开身份）" if producer else FormalEconomicText.firm(firm),"kind":"firm" if authorized.has(firm) else "public_firm"})
	for row:Dictionary in result.authorized_subjects:
		if row.kind in ["person","aggregate"]:choices.append(row)
	var subject:=requested_subject
	if not choices.any(func(row:Dictionary)->bool:return str(row.id)==subject):subject=""
	result["subject"]=subject;result["subjects"]=choices
	if subject.begins_with("aggregate:"):
		result["macro"]=world.economy_state.country_summary(subject.trim_prefix("aggregate:"));return result
	if world.economy_r1==null or subject.is_empty() or not authorized.has(subject):return result
	var requested_site:=site_id
	if requested_site.is_empty() and subject!=world.player_state.player_id():
		for node:Dictionary in city.get("nodes",[]):
			if str(node.get("firm_id",""))==subject and str(node.get("kind",""))=="site" and str(node.get("place_id",""))==place_id:
				requested_site=str(node.get("site_id",""));break
	var page:=world.economy_r1.economy_map_view(world.player_state.player_id(),subject,requested_site,maxi(0,offset),ORDER_PAGE)
	if page.is_empty():return result
	var own:Dictionary=page.get("firm",{})
	result["orders_total"]=int(page.get("orders_total",0));result["offset"]=int(page.get("offset",0));result["next_offset"]=int(page.get("next_offset",0));result["truncated"]=bool(page.get("truncated",false))
	var selected_site:=site_id
	if selected_site.is_empty() and not (own.get("operations",[]) as Array).is_empty():selected_site=str(own["operations"][0].get("site_id",""))
	result["selected_site"]=selected_site
	if subject!=world.player_state.player_id() and not selected_site.is_empty():
		var production:=world.economy_r1.economy_production_view(world.player_state.player_id(),subject,selected_site)
		if not production.is_empty():result["production_details"][selected_site]=production
	# map_subject deliberately does not recompute global offers or wage history.
	result["firm"]=own
	result["market_network"]=Network.project(own)
	result["read_scope"]={"kind":"AUTHORIZED_ORDER_PAGE","observed_minute":world.game_clock.total_minutes(),"place_id":place_id,"site_id":selected_site,"page_limit":ORDER_PAGE,"orders_returned":(result["market_network"].get("edges",{}) as Dictionary).size(),"orders_truncated":page.get("truncated"),"indexed_orders_total":page.get("orders_total"),"identity_limit":NODE_BUDGET,"identity_truncated":city.get("truncated")}
	var received:Array[Dictionary]=[]
	result["market_contacts"]=Contacts.project(own,received,world.game_clock.total_minutes())
	return result
