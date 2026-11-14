extends RefCounted
## Presents the current player's original market read model and accepts one displayed quote.
const Text = preload("res://scripts/presentation/ui/formal_economic_text.gd")
const Goods = preload("res://scripts/content/france_market_goods.gd")
var opened := false
var serial := 0
var displayed: Dictionary = {}
var last_result := ""
var current_world := 0
var focus_serial := 0
var focus: Dictionary = {}

func action(app: FormalWorldApplication, request: Dictionary) -> void:
	_sync_world(app)
	var verb := str(request.get("verb",""))
	var id := str(request.get("id",""))
	var site := str(request.get("site",""))
	var page := app.main_shell.economy_page
	var previous_scope := page.market_scope
	var previous_polity := page.polity_id
	var previous_region := page.region_id
	if verb=="open":
		if id.begins_with("state:") and app._ui_politics.has_entity(id):
			app._handle_market("market:country:"+id)
		else:
			app._handle_market("market:open")
		opened=app.main_shell.current_page=="economy"
		if opened: _update_focus(app, request)
		last_result=""
		return
	if not opened or app.main_shell.current_page!="economy": return
	if verb=="buy":
		if displayed.is_empty() or int(request.get("token",0))!=serial or not displayed.get("success",false):
			last_result="报价已失效，请查看最新报价。"
			return
		var quote := displayed
		displayed={}
		serial+=1
		page.quote=quote
		app._on_action_requested("purchase")
		last_result=app.main_shell.status_message
		app._refresh_ui()
		return
	if verb=="close":
		opened=false
		displayed={}
		app._handle_market("market:close")
		return
	if verb=="collect":
		var person := app._world.player_state.player_id()
		var options := _collections(LivelihoodAction.query(app._world,person).get("orders",[]))
		var quantity := int(request.get("quantity",0))
		if not options.any(func(row: Dictionary)->bool: return row.shipment==id and row.quantity==quantity): return
		app.main_shell.person_page.quantity_milli=quantity
		app._on_action_requested("native:collect:"+id)
		last_result=app.main_shell.status_message
		app._refresh_ui()
		return
	if verb=="offer":
		if not page.visible_offers().any(func(row: Dictionary)->bool: return str(row.commodity_id)==id and str(row.seller_site)==site): return
		page.quantity_milli=1
		app.main_shell._activate("commodity:select:"+id+"|"+site)
	elif verb=="quantity":
		var quantity := int(request.get("quantity",0))
		if page.selected_commodity_id.is_empty() or quantity<=0 or quantity>1000000: return
		page.quantity_milli=quantity
	elif verb=="quote_back":
		page.selected_commodity_id=""
		page.selected_seller_site_id=""
	elif verb=="scope" and id in ["international","domestic","regional"]:
		app._handle_market("market:scope:"+id)
	elif verb=="region" and page.region_choices().any(func(row: Dictionary)->bool: return str(row.place_id)==id):
		app._handle_market("market:region:"+id)
	elif verb=="country" and id.begins_with("state:") and app._ui_politics.has_entity(id):
		app._handle_market("market:country:"+id)
	elif verb=="view" and id in ["quotes","goods","transport","activity"]:
		app._handle_market("market:view:"+id)
	elif verb=="goods_group" and id in ["all",Goods.STAPLES,Goods.INDUSTRIAL,Goods.RAW]:
		app._handle_market("market:goods_group:"+id)
	elif verb=="good":
		var quoted := page.visible_offers().any(func(row: Dictionary)->bool: return str(row.good)==id)
		var catalogued: bool = page.content=="goods" and page.good_in_scope(id) and page.market.get("goods",[]).any(func(row: Dictionary)->bool: return str(row.good)==id)
		if not quoted and not catalogued: return
		app._handle_market("market:good:"+id)
	elif verb=="seller" and page.visible_offers(page.chart_good).any(func(row: Dictionary)->bool: return str(row.seller_site)==id):
		app._handle_market("market:seller:"+id)
	elif verb=="chart" and id in ["price","supply"]:
		app._handle_market("market:chart:"+id)
	elif verb=="window" and id in ["7","30","90"]:
		app._handle_market("market:window:"+id)
	else: return
	displayed={}
	app._refresh_ui()
	if previous_scope!=page.market_scope or previous_polity!=page.polity_id or previous_region!=page.region_id:
		_update_focus(app, request)

func _update_focus(app: FormalWorldApplication, request: Dictionary) -> void:
	focus.clear()
	var viewport: Variant = request.get("viewport")
	if not viewport is Array or viewport.size()!=2: return
	var size := Vector2(float(viewport[0]),float(viewport[1]))
	if not size.is_finite() or size.x<=0 or size.y<=0: return
	var page := app.main_shell.economy_page
	var edge := 18.0+minf(580.0,size.x*.46)
	var shift := (edge-18.0)*.5
	var anchor: Vector3 = app.map_renderer.political.anchors.get(page.polity_id,Vector3.ZERO)
	var scale := .05
	match page.market_scope:
		"regional":
			var place := app._world.spatial_catalog.get_place(page.region_id)
			var ll: Array = place.get("lon_lat",[])
			if ll.size()!=2: return
			anchor = GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1])))
		"international":
			scale = RegionProjection.EARTH_RADIUS_KM/minf(size.y/2.55,size.x*.49)
			shift = size.x*.12
		_:
			var target := app.map_renderer.country_observation(page.polity_id,Vector2(size.x-edge-65,size.y-180))
			anchor = target.anchor
			scale = float(target.scale)
	if anchor.is_zero_approx(): return
	var point := RegionProjection.lon_lat(anchor)
	focus_serial += 1
	focus = {"serial":focus_serial,"point":[point.x,point.y],"mpp":maxf(.008,scale)*1000.0,"shift":shift}

func view(app: FormalWorldApplication) -> Variant:
	_sync_world(app)
	if not opened or app.main_shell.current_page!="economy": return null
	var page := app.main_shell.economy_page
	var offers: Array[Dictionary]=[]
	var grouped: Dictionary={}
	for row: Dictionary in page.visible_offers():
		var good := str(row.good)
		if not grouped.has(good): grouped[good]=[]
		grouped[good].append(row)
		var price: Variant=EconomyPage._ask_price(row)
		offers.append({"good":good,"commodity":row.commodity_id,"site":row.seller_site,
			"place":row.place_id,"seller":Text.firm(str(row.seller)),"location":str(page._place(str(row.place_id)).get("name_zh",row.place_id)),
			"price":"—" if price==null else "%.3f"%float(price),"currency":str(row.get("denomination","")),
			"unit":str(row.get("unit_name_zh","")),"available":int(row.inventory)})
	var book: Array[Dictionary]=[]
	for good: String in grouped:
		book.append(_book_row(page,good,grouped[good]))
	var catalog: Array[Dictionary]=[]
	if page.content=="goods":
		for row: Dictionary in page.market.get("goods",[]):
			var good := str(row.good)
			if page.good_in_scope(good) and (page.goods_group=="all" or Text.trade_origin(good)==page.goods_group):
				catalog.append(_book_row(page,good,grouped.get(good,[])))
	var orders: Array[Dictionary]=[]
	var personal_orders: Array=[]
	if page.content=="activity":
		personal_orders=LivelihoodAction.query(app._world,app._world.player_state.player_id()).get("orders",[])
	var collections := _collections(personal_orders)
	for row: Dictionary in page._orders_in_scope():
		orders.append({"id":row.id,"good":Text.good(str(row.good)),"buyer":str(row.buyer),"seller":str(row.seller),
			"from":str(page._place(str(row.from_place_id)).get("name_zh",row.from_place_id)),
			"to":str(page._place(str(row.to_place_id)).get("name_zh",row.to_place_id)),
			"pending":int(row.pending),"transit":int(row.transit)-int(row.awaiting_quantity),"arrived":int(row.awaiting_quantity),
			"delivered":int(row.delivered),"cancelled":int(row.cancelled),"goods_amount":int(row.paid_goods_amount),
			"freight_amount":int(row.paid_freight_amount),"currency":str(row.denomination)})
	var places: Array[Dictionary]=[]
	for row: Dictionary in page.region_choices():
		places.append({"id":str(row.place_id),"label":str(row.get("name_zh",row.place_id))})
	var countries: Array[Dictionary]=[]
	for row: Dictionary in page.market.get("countries",[]):
		countries.append({"id":str(row.id),"label":str(row.name_zh)})
	var logistics: Array[Dictionary]=[]
	var transport: Dictionary=page.market.get("logistics",{})
	for row: Dictionary in transport.get("nodes",[]):
		logistics.append({"name":str(page._place(str(row.place_id)).get("name_zh",row.place_id)),
			"details":Text.logistics_brief(row,transport.get("units",{}))})
	var chart: Array[Dictionary]=[]
	for row: Dictionary in page.visible_offers(page.chart_good):
		if str(row.seller_site)==page.chart_site:
			chart=page._samples(row)
			break
	var quote: Variant=null
	if not page.selected_commodity_id.is_empty():
		if page.quote!=displayed:
			serial+=1
			displayed=page.quote.duplicate(true)
		var value := displayed
		quote={"token":serial,"accepted":bool(value.get("success",false)),"commodity":page.selected_commodity_id,
			"site":page.selected_seller_site_id,"name":Text.good(page.selected_commodity_id),"quantity":page.quantity_milli,
			"scale":int(value.get("quantity_scale",page.item.get("quantity_scale",1))),"quoted_quantity":int(value.get("quoted_quantity",0)),
			"amount":value.get("amount"),"goods_amount":value.get("goods_amount"),"freight_amount":value.get("freight_amount"),
			"currency":str(value.get("denomination","")),"currency_name":Text.currency(str(value.get("denomination",""))),
			"error":Text.reason(str(value.get("error",""))),"onsite":value.get("fulfilment")=="ONSITE_REAL_STOCK_HANDOVER"}
	return {"scope":page.market_scope,"content":page.content,"polity":page.polity_id,"country":str(page._polity.get("name_zh","")),
		"market_id":app._ui_economy.market_id_for_economic_aggregate(app._ui_economy.economy_entity_for_polity(page.polity_id)),
		"region":page.region_id,"good":page.chart_good,"site":page.chart_site,"window_days":page.window_days,"chart_kind":page.chart_kind,
		"minute":int(page.market.get("minute",0)),"book":book,"catalog":catalog,"goods_group":page.goods_group,
		"good_label":Text.good(page.chart_good),"offers":offers,"orders":orders,"places":places,"countries":countries,
		"logistics":logistics,"chart":chart,"quote":quote,"result":last_result,"collections":collections,
		"focus":focus if not focus.is_empty() else null}

func _book_row(page: EconomyPage, good: String, offers: Array) -> Dictionary:
	var terms := page._book_terms(offers)
	return {"id":good,"label":Text.good(good),"price":str(terms.price),
		"supply":str(terms.supply),"quantity":str(terms.quantity)}

func _collections(orders: Array) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for row: Dictionary in orders:
		if not row.get("can_collect",false): continue
		for cargo: Dictionary in row.get("shipments",[]):
			var quantity: Variant=cargo.get("collectable_quantity")
			if quantity!=null and int(quantity)>0:
				result.append({"order":str(row.id),"shipment":str(cargo.id),"quantity":int(quantity)})
	return result

func _sync_world(app: FormalWorldApplication) -> void:
	var id := app._world.get_instance_id()
	if id==current_world: return
	current_world=id
	displayed={}
	serial+=1
	last_result=""
