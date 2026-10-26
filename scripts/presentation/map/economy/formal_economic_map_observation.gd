class_name FormalEconomicMapObservation
extends RefCounted
## Adapts the existing formal owners to the frozen merchant display contracts.
## No Runtime, clock, stock, order, account or mutable cross-domain database.
const Network = preload("res://scripts/presentation/map/economy/observed_market_network.gd")
const Contacts = preload("res://scripts/presentation/map/economy/observed_market_contacts.gd")
const ORDER_PAGE = 32
const NODE_BUDGET = 128
const PLACE_BUDGET = 96
const FACT_BUDGET = 64
# One detached content projection and one current viewport projection only.
# Camera signals may query another window; draw calls never scan the economy.
static var _network_stamp: Array = []
static var _known_network: Dictionary = {}
static var _window_places: Array[String] = []
static var _window_network: Dictionary = {}

static func node_network(world: WorldState, places: Array[String] = []) -> Dictionary:
	if world==null or world.economy_r1==null: return {}
	var key := stamp(world)
	if _network_stamp!=key:
		_network_stamp=key
		_known_network=world.economy_r1.network_view(world.player_state.player_id(),[],NODE_BUDGET)
		_window_places.clear()
		_window_network.clear()
	if places.is_empty(): return _known_network
	if _window_places!=places or _window_network.is_empty():
		_window_places=places.duplicate()
		_window_network=world.economy_r1.network_view(world.player_state.player_id(),places,NODE_BUDGET)
	return _window_network

static func stamp(world: WorldState) -> Array:
	if world==null: return []
	var native := world.economy_r1
	return [world.get_instance_id(),world.player_state.player_id(),world.game_clock.total_minutes(),world.organization_state.revision(),world.economy_state._state_revision,native._commands.size() if native!=null else 0,native.next_order if native!=null else 0,native.next_shipment if native!=null else 0,native.network_revision() if native!=null else 0]

static func canonical_place(id: String) -> String:
	return VNextSpatialCatalog.map_id_to_place_id(VNextSpatialCatalog.place_query_to_map_id(id))

static func known_places(world: WorldState) -> Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	if world==null or world.economy_r1==null:return rows
	var seen:Dictionary={}
	# Only identities admitted by the observer boundary. A public establishment
	# is not permission to read its account, stock, orders or unreceived messages.
	for source:Dictionary in node_network(world).get("nodes",[]):
		var id:=str(source.get("place_id",""))
		if id.is_empty() or seen.has(id):continue
		var record:=world.spatial_catalog.get_place(id)
		if not _coordinates(record):continue
		var point:=record.duplicate()
		point["id"]=id
		point["display_name"]=str(record.get("name_zh",record.get("name",id)))
		rows.append(point);seen[id]=true
		if rows.size()>=PLACE_BUDGET:break
	return rows

static func _coordinates(place: Dictionary) -> bool:
	var coordinates:Variant=place.get("lon_lat")
	if not coordinates is Array or coordinates.size()!=2:return false
	if not (coordinates[0] is int or coordinates[0] is float) or not (coordinates[1] is int or coordinates[1] is float):return false
	var ll:=Vector2(float(coordinates[0]),float(coordinates[1]))
	return ll.is_finite() and absf(ll.x)<=180 and absf(ll.y)<=90

static func brief(world: WorldState, places: Array[String], polity_id: String, capital: Dictionary) -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	if world==null: return facts
	var observer := world.player_state.player_id()
	if world.economy_r1!=null:
		var groups:Dictionary={}
		for node:Dictionary in node_network(world,places).get("nodes",[]):
			var id:=str(node.get("place_id",""))
			if id not in places:continue
			if not groups.has(id):groups[id]={"source_id":"nodes:"+id,"subject_id":observer,"place_id":id,"kind":"place","node_ids":[],"node_kinds":[],"site_count":0,"transport_count":0,"identity_bases":[],"known_activity":[],"basis":"OBSERVER_AUTHORIZED_NODE_IDENTITIES","priority":50}
			var group:Dictionary=groups[id]
			group.node_ids.append(str(node.get("id","")))
			var kind:=str(node.get("kind",""))
			if kind not in group.node_kinds:group.node_kinds.append(kind)
			var basis:=str(node.get("identity_basis",node.get("basis","")))
			if not basis.is_empty() and basis not in group.identity_bases:group.identity_bases.append(basis)
			if kind=="site":
				group.site_count+=1;group.kind="site";group.priority=80
				if str(node.get("subject_id",observer))!=observer:group.subject_id=str(node.subject_id)
			elif kind=="transport_node":
				group.transport_count+=1
				if group.kind=="place":group.kind="transport_node"
		# Retain received labour/supplier activity, not another firm's private plan.
		for row:Dictionary in world.economy_r1.map_site_summaries(observer,places,16):
			var id:=str(row.place_id)
			if groups.has(id):groups[id].known_activity.append(str(row.get("state","")))
		for id:String in groups:
			var group:Dictionary=groups[id]
			group["state"]="合法地点"+(" · %d企业站点"%int(group.site_count) if int(group.site_count)>0 else "")+(" · 物流节点" if int(group.transport_count)>0 else "")
			var fact:=_fact(world,group,world.spatial_catalog.get_place(id))
			if not fact.is_empty():facts.append(fact)
			if facts.size()>=FACT_BUDGET-1:break
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
	if not _coordinates(place):return {}
	var coordinates:Array=place.lon_lat
	var fact := row.duplicate()
	fact.merge({"id":"economy:"+str(row.source_id),"domain":"economy","observer":world.player_state.player_id(),"world_id":world.get_instance_id(),"world_minute":world.game_clock.total_minutes(),"lon_lat":coordinates.duplicate(),"position_kind":"CITY_ANCHOR_NOT_PARCEL","knowledge":"PUBLIC_OR_RECEIVED_IDENTITY_NOT_PRIVATE_BUSINESS_DATA","maps":["political","economic","geographic"]},true)
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
	result["node_network"]=node_network(world)
	result["identity_notice"]="显式开发情景；企业、初始禀赋与配方/工资/运力为开发假设，不是历史企业或历史统计。" if str(result.world_case).contains("DEVELOPMENT") else "当前正式世界身份；巴黎开局企业为有限模拟、非历史企业。合法地点不等于人口、库存或厂房地籍。" if str(result.world_case).contains("PARIS") else "合法地点与企业身份按现有来源列示；未提供的历史身份、私有财产和未收到信息不推定。"
	if result.world_case == "FORMAL_ECONOMIC_NODE_NETWORK_DEVELOPMENT":
		result["identity_notice"] += " 法英同币种开发贸易；海峡段占用正式共享运力，其他段为开发业务运量。未验收外汇、关税或禁运制度。"
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
	result["production_details"]={}
	if subject!=world.player_state.player_id(): # query_firm above already authenticated the current manager.
		for operation:Dictionary in own["operations"]:
			var site:=str(operation.get("site_id",""))
			if site.is_empty():continue
			var production:=world.economy_r1.economy_read_view(world.player_state.player_id(),subject,site)
			if not production.is_empty():
				result["production_details"][site]={"site_id":site,"activities":production.get("activities",[]),"units":production.get("units",{}),"inventory_status":production.get("inventory_status",{}),"configuration_source":production.get("configuration_source",{})}
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
