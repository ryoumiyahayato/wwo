class_name FormalEconomicMapObservation
extends RefCounted
## Detached observer projections. No clock, stock, account or routing authority.
const Network = preload("res://scripts/presentation/map/economy/observed_market_network.gd")
const Contacts = preload("res://scripts/presentation/map/economy/observed_market_contacts.gd")
const ORDER_PAGE = 32
const NODE_BUDGET = 128
const PLACE_BUDGET = 96
const FACT_BUDGET = 64
const CITY_SITUATION_BUDGET = 8
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

static func _player_context(world: WorldState, authorized: Dictionary) -> Dictionary:
	var observer:=world.player_state.player_id()
	var context:Dictionary={"subject_id":observer,"current_place_id":world.person_overlay.current_place(observer),"managed_firms_listed":0}
	if world.person_travel!=null and not str(context.current_place_id).is_empty():context["present_at_recorded_place"]=world.person_travel.is_present(observer,str(context.current_place_id))
	for row:Dictionary in authorized.values():
		if str(row.get("kind",""))=="firm":context["managed_firms_listed"]+=1
	if world.economy_r1==null:return context
	# Zero orders: original personal/local stock and account projection only.
	var page:=world.economy_r1.economy_map_view(observer,observer,"",0,0)
	var personal:Dictionary=page.get("firm",{})
	for key:String in ["denomination","cash","reserved","available","inventory_basis"]:
		if personal.has(key):context[key]=personal[key]
	if personal.get("inventory") is Dictionary:context["inventory"]=(personal["inventory"] as Dictionary).duplicate(true)
	return context

static func _city_situations(world: WorldState, city: Dictionary, place_id: String, authorized: Dictionary, preferred_site: String = "", preferred_firm: String = "") -> Dictionary:
	var rows:Array[Dictionary]=[]
	var seen:Dictionary={}
	var candidates:Array[Dictionary]=[]
	var preferred_index:int=-1
	if world.economy_r1!=null:
		for node:Dictionary in city.get("nodes",[]):
			var firm:=str(node.get("firm_id",""));var site:=str(node.get("site_id",""))
			if str(node.get("kind",""))!="site" or str(node.get("place_id",""))!=place_id or site.is_empty() or seen.has(site):continue
			if not authorized.has(firm) or str(authorized[firm].get("kind",""))!="firm":continue
			seen[site]=true
			if site==preferred_site and (preferred_firm.is_empty() or firm==preferred_firm):preferred_index=candidates.size()
			elif preferred_index<0 and firm==preferred_firm:preferred_index=candidates.size()
			candidates.append(node)
		if preferred_index>0:
			var preferred:Dictionary=candidates.pop_at(preferred_index)
			candidates.push_front(preferred)
		for index:int in range(mini(CITY_SITUATION_BUDGET,candidates.size())):
			var node:Dictionary=candidates[index]
			var situation:=world.economy_r1.business_situation(world.player_state.player_id(),str(node.get("firm_id","")),str(node.get("site_id","")))
			if not situation.is_empty():rows.append(situation)
	return {"rows":rows,"limit":CITY_SITUATION_BUDGET,"truncated":candidates.size()>CITY_SITUATION_BUDGET or bool(city.get("truncated",false))}

static func _page_has_order(page: Dictionary, id: String) -> bool:
	if id.is_empty():return false
	for order:Dictionary in page.get("firm",{}).get("orders",[]):
		if str(order.get("id",""))==id:return true
	return false

static func overview(world: WorldState, polity_id: String, place_id: String = "", subject: String = "") -> Dictionary:
	if world==null:return {}
	var world_case:=str(world.economy_r1.config.get("case_id","")) if world.economy_r1!=null else "FORMAL_COUNTRY_STATISTICS"
	var notice:="开发情景：非历史企业；禀赋、配方、工资与运力为开发假设。" if world_case.contains("DEVELOPMENT") else "巴黎普通开局企业为有限模拟、非历史企业。" if world_case.contains("PARIS") else "身份按现有公开或已收到资料列示。"
	var known_hubs:=hubs(world)
	return {"world_id":world.get_instance_id(),"minute":world.game_clock.total_minutes(),"date":world.game_clock.current_date(),"world_case":world_case,"observer":world.player_state.player_id(),"subject":subject,"selected_place":place_id,"authorized_subjects":subjects(world,polity_id),"subjects":[],"hubs":known_hubs,"node_network":{},"firm":{},"market_network":{},"market_contacts":{},"production_details":{},"macro":{},"orders_total":0,"offset":0,"next_offset":0,"page_size":ORDER_PAGE,"native_enabled":world.economy_r1!=null,"details_loaded":false,"identity_notice":notice,"read_scope":{"kind":"HUB_IDENTITIES_ONLY","identity_limit":PLACE_BUDGET,"identity_truncated":known_hubs.get("truncated")}}

static func details(world: WorldState, polity_id: String, requested_subject: String, offset: int = 0, requested_order: String = "", place_id: String = "", site_id: String = "", research: bool = false) -> Dictionary:
	var result:=overview(world,polity_id,place_id,requested_subject)
	if result.is_empty():return result
	result["details_loaded"]=true;result["research"]=research;result["selected_site"]=""
	result["pending_cancellation"]={};result["follow_order_id"]="";result["follow_notice"]=""
	var city:=node_network(world,[place_id]) if not place_id.is_empty() else {}
	result["node_network"]=city
	result["read_scope"]={"kind":"CITY_PLAYER_AND_AUTHORIZED_SITE_SITUATIONS","observed_minute":world.game_clock.total_minutes(),"identity_limit":NODE_BUDGET,"identity_truncated":city.get("truncated"),"city_situation_limit":CITY_SITUATION_BUDGET,"personal_order_limit":0}
	var choices:Array[Dictionary]=[{"id":"","name":"城市总览","kind":"hub"}]
	var authorized:Dictionary={}
	for row:Dictionary in result.authorized_subjects:authorized[str(row.id)]=row
	result["player_context"]=_player_context(world,authorized)
	var situations:=_city_situations(world,city,place_id,authorized,site_id,requested_subject)
	result["city_business_situations"]=situations["rows"]
	result["city_situation_limit"]=situations["limit"];result["city_situations_truncated"]=situations["truncated"]
	var seen:Dictionary={}
	for node:Dictionary in city.get("nodes",[]):
		var firm:=str(node.get("firm_id",""))
		var producer:bool=str(node.get("kind",""))=="local_producer"
		if producer:firm=str(node.get("id",""))
		if str(node.get("place_id",""))!=place_id or firm.is_empty() or seen.has(firm):continue
		seen[firm]=true
		var label:=FormalEconomicText.firm(firm)
		if producer and label=="企业（名称未记录）":label="本地生产者（已知身份）"
		choices.append({"id":firm,"name":label,"kind":"firm" if authorized.has(firm) else "public_firm"})
	for row:Dictionary in result.authorized_subjects:
		if row.kind in ["person","aggregate"]:choices.append(row)
	var subject:=requested_subject
	if not choices.any(func(row:Dictionary)->bool:return str(row.id)==subject):subject=""
	result["subject"]=subject;result["subjects"]=choices
	if subject.begins_with("aggregate:"):
		result["macro"]=world.economy_state.country_summary(subject.trim_prefix("aggregate:"));return result
	if world.economy_r1==null or subject.is_empty() or not authorized.has(subject):
		if not requested_order.is_empty():result["follow_notice"]="目标订单不在本次授权范围；未沿用旧私账或推定货位。"
		return result
	var requested_site:=""
	if subject!=world.player_state.player_id():
		var city_sites:Array[String]=[]
		for node:Dictionary in city.get("nodes",[]):
			if str(node.get("firm_id",""))==subject and str(node.get("kind",""))=="site" and str(node.get("place_id",""))==place_id:
				var known_site:=str(node.get("site_id",""))
				if not known_site.is_empty():city_sites.append(known_site)
		if city_sites.is_empty():
			result["follow_notice"]="本次本城身份页未确认获权站点；未改读别城库存或推定地点。";return result
		requested_site=site_id if site_id in city_sites else city_sites[0]
		if not site_id.is_empty() and site_id not in city_sites:result["follow_notice"]="原站点未在本次本城身份页确认；已回本城获权站点，未沿用旧私账。"
	var native:=world.economy_r1
	var observer:=world.player_state.player_id()
	var page:=native.economy_map_view(observer,subject,requested_site,maxi(0,offset),ORDER_PAGE)
	if page.is_empty():return result
	if not requested_order.is_empty():
		if not _page_has_order(page,requested_order):
			# Borrow only the already-authorized subject's ID index. No copy/sort,
			# global order scan, raw order DTO or inferred site/location.
			var ids:Array=native._orders_by_subject.get(subject,[])
			var position:int=ids.find(requested_order)
			if position>=0:
				var focused:=native.economy_map_view(observer,subject,requested_site,ids.size()-1-position,ORDER_PAGE)
				if _page_has_order(focused,requested_order):page=focused
		if _page_has_order(page,requested_order):
			result["follow_order_id"]=requested_order
			result["pending_cancellation"]=native.cancel_pending_view(observer,requested_order)
		else:result["follow_notice"]="目标未出现在当前本站授权页；未改变城市/站点或推定货位。可在原订单页继续查看。"
	var own:Dictionary=page.get("firm",{})
	result["orders_total"]=int(page.get("orders_total",0));result["offset"]=int(page.get("offset",0));result["next_offset"]=int(page.get("next_offset",0));result["truncated"]=bool(page.get("truncated",false))
	result["selected_site"]=requested_site
	if subject!=observer and not requested_site.is_empty():
		var production:=native.economy_production_view(observer,subject,requested_site)
		if not production.is_empty():result["production_details"][requested_site]=production
	result["firm"]=own;result["market_network"]=Network.project(own)
	result["read_scope"]={"kind":"AUTHORIZED_ORDER_PAGE","observed_minute":world.game_clock.total_minutes(),"place_id":place_id,"site_id":requested_site,"page_limit":ORDER_PAGE,"orders_returned":(result["market_network"].get("edges",{}) as Dictionary).size(),"orders_truncated":page.get("truncated"),"indexed_orders_total":page.get("orders_total"),"identity_limit":NODE_BUDGET,"identity_truncated":city.get("truncated"),"city_situation_limit":CITY_SITUATION_BUDGET}
	var received:Array[Dictionary]=[]
	result["market_contacts"]=Contacts.project(own,received,world.game_clock.total_minutes())
	return result
