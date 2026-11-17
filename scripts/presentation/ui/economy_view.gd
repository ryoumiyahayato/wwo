class_name EconomyPage
extends RefCounted
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
const Chart = preload("res://scripts/presentation/ui/market_chart.gd")
const FranceMarketGoods = preload("res://scripts/content/france_market_goods.gd")
var _polity: Dictionary = {}
var _native_observation: Dictionary = {}
var market: Dictionary = {}
var polity_id: String = ""
var scope_label: String = ""
var personal_market: bool = false
var market_scope: String = "domestic"
var content: String = "quotes"
var goods_group: String = "all"
var region_id: String = ""
var chart_good: String = "bread"
var chart_site: String = ""
var chart_kind: String = "price"
var window_days: int = 30
var chooser: String = ""
var country_choices: Array[Dictionary] = []
var public_regions: Array[Dictionary] = [] # Public map identities, never seller knowledge.
var public_region_polity: String = ""
var country_source_id: String = ""
var seller_page: int = 0
var commodity_page: int = 0
var selected_commodity_id: String = ""
var selected_seller_site_id: String = ""
var quantity_milli: int = 1
var quote: Dictionary = {}
var item: Dictionary = {}
var native_managed: bool = false
var show_native_statistics: bool = false
var native_statistics_page: int = 0
var cohort_statistics_page: int = 0
var _preferred_height: float = 402.0

static func market_page_size(_height: float) -> int: return 96
static func known_market_page_size(_height: float) -> int: return 96
static func _dictionary(value: Variant) -> Dictionary: return value if value is Dictionary else {}

func refresh(polity: Dictionary, _economy: FormalWorldEconomyView, selected_id: String, _rows: Array[Dictionary], offer: Dictionary, selected_item: Dictionary, native_person: bool = false, native_observation: Dictionary = {}) -> void:
	polity_id=selected_id;_polity=polity;native_managed=native_person
	_native_observation=native_observation;market=native_observation.get("market",{})
	quote=offer;item=selected_item
	if not good_in_scope(chart_good): chart_good="grain"
	var offers: Array[Dictionary]=visible_offers()
	if chart_good.is_empty() and not offers.is_empty(): chart_good=str(offers[0].good)
	var sellers: Array[Dictionary]=visible_offers(chart_good)
	if not sellers.any(func(row: Dictionary)->bool:return str(row.seller_site)==chart_site):
		chart_site=str(sellers[0].seller_site) if not sellers.is_empty() else ""
	_preferred_height=_measure_height()

func _place(id: String) -> Dictionary:
	for row: Dictionary in public_regions:
		if str(row.place_id)==id: return row
	for row: Dictionary in market.get("places",[]):
		if str(row.place_id)==id: return row
	return {}

func _in_scope(place_id: String) -> bool:
	if market_scope=="international": return true
	if market_scope=="regional": return place_id==region_id
	var place := _place(place_id)
	return str(place.get("polity_id",""))==polity_id if place.has("polity_id") else str(place.get("parent_country_id",""))==country_source_id

func good_in_scope(id: String) -> bool:
	return market_scope!="international" or id in ["grain","fiber"] or FranceMarketGoods.is_bulk(id)

func visible_offers(good: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for row: Dictionary in market.get("offers",[]):
		if not good_in_scope(str(row.good)): continue
		if _in_scope(str(row.place_id)) and (good.is_empty() or str(row.good)==good): result.append(row)
	return result

func region_choices() -> Array[Dictionary]:
	var result: Array[Dictionary]=public_regions.duplicate()
	for row: Dictionary in market.get("places",[]):
		var place := _place(str(row.place_id))
		var same_country: bool=str(place.get("polity_id",""))==polity_id if place.has("polity_id") else str(place.get("parent_country_id",""))==country_source_id
		if not same_country or result.any(func(known: Dictionary)->bool:return str(known.place_id)==str(row.place_id)): continue
		result.append(row)
	return result

func _samples(seller: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if seller.is_empty(): return result
	for row: Dictionary in market.get("history",[]):
		if str(row.good)!=chart_good or str(row.seller_site)!=chart_site or row.denomination!=seller.denomination: continue
		if chart_kind=="supply" and (row.get("quantity")==null or row.kind!="quote"): continue
		result.append({"minute":row.minute,"value":float(row.price_milli)/1000.0 if chart_kind=="price" else float(row.quantity)})
	var current: Variant = _ask_price(seller) if chart_kind=="price" else float(seller.inventory)
	if current!=null: result.append({"minute":market.get("minute",0),"value":current})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return int(a.minute)<int(b.minute))
	return result

static func _ask_price(offer: Dictionary) -> Variant:
	var price: Variant = offer.get("price")
	if price==null: return null
	return float(offer.get("price_milli",int(price)*1000))/1000.0

func panel_height() -> float:
	return 403.0 if not selected_commodity_id.is_empty() else _preferred_height

func _measure_height() -> float:
	if content=="quotes":
		var goods: Dictionary = {}
		for offer: Dictionary in visible_offers(): goods[offer.good]=true
		return minf(550.0,301.0+35.0*maxi(1,goods.size()))
	if content=="good":
		var sellers := visible_offers(chart_good)
		for seller: Dictionary in sellers:
			if str(seller.seller_site)==chart_site and _has_chart_history(_samples(seller)): return 550.0
		return minf(550.0,395.0+31.0*maxi(1,sellers.size()))
	if content=="activity": return minf(520.0,270.0+78.0*maxi(1,_orders_in_scope().size()))
	if content=="transport": return minf(520.0,270.0+92.0*maxi(1,market.get("logistics",{}).get("nodes",[]).size()))
	return 520.0

func _has_chart_history(samples: Array[Dictionary]) -> bool:
	var now := int(market.get("minute",0))
	var from := maxi(0,now-window_days*1440)
	var first := -1
	for sample: Dictionary in samples:
		var minute := int(sample.minute)
		if minute<from or minute>now: continue
		if first>=0 and first!=minute: return true
		first=minute
	return false

func draw(shell: MainShell, rect: Rect2) -> void:
	if not selected_commodity_id.is_empty():
		shell.folio_title(rect,"商品交易",23)
		_draw_commodity(shell,rect)
		return
	var at := rect.position
	var width := rect.size.x-40.0
	var names := {"international":"国际大宗市场","domestic":"国内市场","regional":"区域市场"}
	var title := str(names[market_scope])
	if market_scope=="domestic": title=UILocale.field(_polity,"short_name",UILocale.name(_polity))+" · "+title
	elif market_scope=="regional": title=str(_place(region_id).get("name_zh","选择地区"))+" · "+title
	shell.folio_title(rect,title,22)
	for index: int in 3:
		var id: String = ["international","domestic","regional"][index]
		shell.button(Rect2(at+Vector2(20+index*width/3.0,61),Vector2(width/3.0-4,25)),names[id],"market:scope:"+id,true,market_scope==id,12,"folio_tab")
	if market_scope=="international":
		shell.button(Rect2(at+Vector2(20,94),Vector2(width*.58-4,25)),"选择国家 ▾","market:choose:country",true,chooser=="country",12,"folio_control")
	else:
		shell.button(Rect2(at+Vector2(20,94),Vector2(width*.58-4,25)),UILocale.name(_polity)+" ▾","market:choose:country",true,chooser=="country",12,"folio_control")
		shell.button(Rect2(at+Vector2(20+width*.58,94),Vector2(width*.42,25)),str(_place(region_id).get("name_zh","选择区域"))+" ▾","market:choose:region",true,chooser=="region",12,"folio_control")
	for index: int in 4:
		var id: String = ["quotes","goods","transport","activity"][index]
		var selected := content==id or (id=="quotes" and content=="good")
		shell.button(Rect2(at+Vector2(20+index*width/4.0,128),Vector2(width/4.0-4,27)),["报价簿","商品目录","仓储与运输","活动记录"][index],"market:view:"+id,true,selected,12,"folio_tab")
	UIDrawing.folio_rail(shell,Rect2(at+Vector2(17,157),Vector2(rect.size.x-34,3)))
	var body := Rect2(at+Vector2(20,166),Vector2(width,rect.size.y-203))
	var managed: bool = not market.get("managed_firms",[]).is_empty()
	if managed and content in ["transport","activity"]: body.size.y-=24.0
	match content:
		"good": _draw_good(shell,body)
		"quotes","goods": _draw_quote_book(shell,body)
		_: _draw_content(shell,body)
	if managed:
		shell.button(Rect2(rect.end.x-118,rect.end.y-61,98,23),"企业经营","market:choose:supply",true,false,11,"folio_control")
	_draw_chooser(shell,Rect2(at+Vector2(20,120),Vector2(width,minf(310,rect.size.y-150))))

func _draw_quote_book(shell: MainShell, area: Rect2) -> void:
	var offers_by_good: Dictionary = {}
	var currencies: Dictionary = {}
	var ready := 0
	for offer: Dictionary in visible_offers():
		var id := str(offer.good)
		if not offers_by_good.has(id): offers_by_good[id]=[]
		(offers_by_good[id] as Array).append(offer)
		if _ask_price(offer)!=null: currencies[str(offer.denomination)]=true
		if int(offer.inventory)>0: ready+=1
	var ids: Array[String] = []
	var p := area.position
	var width := area.size.x
	var y := p.y
	if content=="goods":
		var groups := ["all",FranceMarketGoods.STAPLES,FranceMarketGoods.INDUSTRIAL,FranceMarketGoods.RAW]
		var labels := ["全部","粮食","工业品","其他原料"]
		for index: int in groups.size():
			shell.button(Rect2(p.x+index*width*.25,y,width*.25-4,25),labels[index],"market:goods_group:"+groups[index],true,goods_group==groups[index],11,"folio_tab")
		for good: Dictionary in market.get("goods",[]):
			var id := str(good.good)
			if good_in_scope(id) and (goods_group=="all" or EconomicText.trade_origin(id)==goods_group): ids.append(id)
		y+=36
	else:
		ids.assign(offers_by_good.keys())
		var orders := _orders_in_scope()
		var summary := UILocale.text("%d 种报价商品    ·    %d 条可购报价    ·    %d 笔可见订单") % [ids.size(),ready,orders.size()]
		shell.draw_rect(Rect2(p,Vector2(width,30)),UIDrawing.FOLIO_SHADE)
		shell.label(p+Vector2(9,20),summary,12,UIDrawing.FOLIO_INK,width-18)
		y+=38
	var price_x := p.x+width*.40
	var supply_x := p.x+width*.72
	shell.label(Vector2(p.x+7,y+15),"商品",12,UIDrawing.FOLIO_MUTED)
	shell.label(Vector2(price_x,y+15),"已知报价",12,UIDrawing.FOLIO_MUTED,width*.31)
	shell.label(Vector2(supply_x,y+15),"单笔可购上限",12,UIDrawing.FOLIO_MUTED,width*.27)
	shell.draw_line(Vector2(p.x,y+22),Vector2(area.end.x,y+22),UIDrawing.FOLIO_RULE,1.0,true)
	y+=25
	var count := maxi(1,int((area.end.y-y-24)/35.0))
	commodity_page=clampi(commodity_page,0,maxi(0,(ids.size()-1)/count))
	var first := commodity_page*count
	for index: int in range(first,mini(ids.size(),first+count)):
		var id := ids[index]
		var offers: Array = offers_by_good.get(id,[])
		var terms := _book_terms(offers)
		var row := Rect2(p.x,y,width,34)
		if (index-first)%2==0: shell.draw_rect(row,Color(UIDrawing.FOLIO_SHADE,.57))
		shell.button(row,EconomicText.good(id),"market:good:"+id,true,false,13,"folio_row")
		shell.label(Vector2(price_x,y+20),terms.price,12,UIDrawing.FOLIO_INK,width*.31-5)
		shell.label(Vector2(supply_x,y+15),terms.quantity,13,UIDrawing.BRASS_LIGHT if terms.available else UIDrawing.FOLIO_MUTED,width*.27)
		shell.label(Vector2(supply_x,y+30),terms.supply,10,UIDrawing.FOLIO_MUTED,width*.27)
		y+=35
	if ids.is_empty(): shell.label(Vector2(p.x+7,y+23),"此范围暂无已知卖家报价。" if content=="quotes" else "此类暂无登记商品",12,UIDrawing.FOLIO_MUTED,width)
	if ids.size()>count:
		shell.button(Rect2(p.x,area.end.y-24,34,22),"‹","market:book_page:previous",commodity_page>0,false,12,"folio_control")
		shell.button(Rect2(p.x+41,area.end.y-24,34,22),"›","market:book_page:next",first+count<ids.size(),false,12,"folio_control")
	if content=="quotes":
		var basis := EconomicText.currency(str(currencies.keys()[0])) if currencies.size()==1 else "仅列已知报价"
		var note_inset := 87.0 if ids.size()>count else 7.0
		var footer_controls := 105.0 if not market.get("managed_firms",[]).is_empty() else 0.0
		shell.label(Vector2(p.x+note_inset,area.end.y-9),UILocale.text("需求未公开")+" · "+basis,11,UIDrawing.FOLIO_MUTED,width-note_inset-footer_controls)

func _book_terms(offers: Array) -> Dictionary:
	var low := INF
	var high := -INF
	var ready := 0
	var maximum := 0
	var currencies: Dictionary = {}
	for offer: Dictionary in offers:
		var quantity := int(offer.inventory)
		if quantity>0: ready+=1
		maximum=maxi(maximum,quantity)
		var ask: Variant = _ask_price(offer)
		if ask==null: continue
		low=minf(low,ask)
		high=maxf(high,ask)
		currencies[str(offer.denomination)]=true
	var price := "—"
	if currencies.size()>1: price="多币种"
	elif currencies.size()==1:
		price="%.3f" % low if is_equal_approx(low,high) else "%.3f–%.3f" % [low,high]
		price+=" / "+str(offers[0].get("unit_name_zh",""))
	return {"price":price,"available":maximum>0,"quantity":str(maximum) if maximum>0 else "—","supply":UILocale.text("%d 可购 / %d 已知") % [ready,offers.size()]}

func _orders_in_scope() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for order: Dictionary in market.get("activity",{}).get("orders",[]):
		if good_in_scope(str(order.good)) and (_in_scope(str(order.from_place_id)) or _in_scope(str(order.to_place_id))):
			rows.append(order)
	return rows

func _draw_good(shell: MainShell, area: Rect2) -> void:
	var at := area.position
	var width := area.size.x
	var sellers := visible_offers(chart_good)
	var current: Dictionary = {}
	for seller: Dictionary in sellers:
		if str(seller.seller_site)==chart_site: current=seller;break
	shell.label(at+Vector2(3,26),EconomicText.good(chart_good),23,UIDrawing.FOLIO_INK,width-138)
	shell.button(Rect2(at.x+width-126,at.y+3,126,26),"‹ 返回报价簿","market:view:quotes",true,false,12,"folio_control")
	var ask: Variant = _ask_price(current)
	if ask!=null:
		var price := "%.3f  %s / %s" % [ask,EconomicText.currency(str(current.denomination)),str(current.unit_name_zh)]
		shell.label(at+Vector2(3,52),price,14,UIDrawing.FOLIO_INK,width)
		if int(current.get("freight_per_unit",0))>0:
			shell.label(at+Vector2(3,73),UILocale.text("含运费 %.3f")%(float(current.landed_milli)/1000.0),11,UIDrawing.FOLIO_MUTED,width)
	shell.button(Rect2(at.x,at.y+82,84,24),"产地价格","market:chart:price",true,chart_kind=="price",11,"folio_tab")
	shell.button(Rect2(at.x+86,at.y+82,84,24),"可见供给","market:chart:supply",true,chart_kind=="supply",11,"folio_tab")
	for index: int in 3:
		var days: int = [7,30,90][index]
		shell.button(Rect2(at.x+width-139+index*46,at.y+82,43,24),str(days)+UILocale.text("日"),"market:window:"+str(days),true,window_days==days,10,"folio_tab")
	var y := at.y+119.0
	var now := int(market.get("minute",0))
	var samples := _samples(current)
	var from := maxi(0,now-window_days*1440)
	var timestamps: Dictionary = {}
	for sample: Dictionary in samples:
		var minute := int(sample.minute)
		if minute>=from and minute<=now: timestamps[minute]=true
	if _has_chart_history(samples):
		var plot := Rect2(at.x+42,y+4,width-47,clampf(area.size.y-246.0,48.0,104.0))
		Chart.draw(shell,plot,samples,now,window_days,chart_kind=="supply")
		y=plot.end.y+33
	else:
		shell.label(Vector2(at.x+3,y+11),"该期间暂无可见记录" if timestamps.is_empty() else "只有一个记录时点",12,UIDrawing.FOLIO_MUTED,width)
		y+=27
	shell.label(Vector2(at.x+3,y+12),"实际卖家",13,UIDrawing.FOLIO_INK,width*.58)
	shell.label(Vector2(area.end.x-146,y+12),"可购数量",11,UIDrawing.FOLIO_MUTED,75)
	shell.draw_line(Vector2(at.x,y+18),Vector2(area.end.x,y+18),UIDrawing.FOLIO_RULE,1.0,true)
	y+=22
	var count := maxi(1,int((area.end.y-y-27.0)/31.0))
	seller_page=clampi(seller_page,0,maxi(0,(sellers.size()-1)/count))
	for index: int in range(seller_page*count,mini(sellers.size(),(seller_page+1)*count)):
		var seller: Dictionary = sellers[index]
		var row_title := str(_place(str(seller.place_id)).get("name_zh",""))+" · "+EconomicText.firm(str(seller.seller))
		shell.button(Rect2(at.x,y,width-159,29),row_title,"market:seller:"+str(seller.seller_site),true,chart_site==str(seller.seller_site),12,"folio_row")
		shell.number(Vector2(area.end.x-155,y+20),str(seller.inventory),65,13,UIDrawing.FOLIO_INK)
		var can_buy := int(seller.inventory)>0
		shell.button(Rect2(area.end.x-82,y,82,29),"购买" if can_buy else "查看","commodity:select:"+str(seller.commodity_id)+"|"+str(seller.seller_site),true,false,12,"folio_primary" if can_buy else "folio_control")
		y+=31
	if sellers.is_empty(): shell.label(Vector2(at.x+3,y+15),"此范围暂无已知卖家报价。",12,UIDrawing.FOLIO_MUTED,width)
	if sellers.size()>count:
		shell.button(Rect2(at.x,area.end.y-23,34,22),"‹","market:sellers:previous",seller_page>0,false,12,"folio_control")
		shell.button(Rect2(at.x+41,area.end.y-23,34,22),"›","market:sellers:next",(seller_page+1)*count<sellers.size(),false,12,"folio_control")

func _draw_content(shell: MainShell, area: Rect2) -> void:
	var rows: Array=[]
	if content=="transport":
		var logistics: Dictionary=market.get("logistics",{})
		for city: Dictionary in logistics.get("nodes",[]):
			var id := str(city.place_id)
			var details := Array(EconomicText.logistics_brief(city,logistics.get("units",{})).split("\n"))
			var name := str(_place(id).get("name_zh",id))
			rows.append({"name_zh":name,"details":details,"actions":[{"text":"查看当地市场","action":"market:region:"+id}]})
			for terms: Dictionary in city.get("warehouse_terms",[]):
				var capacity := UILocale.text("空余仓位 %d / %d") % [int(terms.free_capacity),int(terms.capacity)]
				var fee := UILocale.text("每仓位每日 %d %s") % [int(terms.price),EconomicText.currency(str(terms.denomination))]
				rows.append({"name_zh":name+" · "+UILocale.text("仓储报价"),"details":[capacity+"  ·  "+fee]})
		if rows.is_empty(): rows.append({"name_zh":"暂无可查看的仓储或运输记录","details":["只显示本人及有权经营企业的货物与合同。"]})
	else:
		for order: Dictionary in market.get("activity",{}).get("orders",[]):
			if not good_in_scope(str(order.good)): continue
			if not _in_scope(str(order.from_place_id)) and not _in_scope(str(order.to_place_id)): continue
			var awaiting := int(order.awaiting_quantity)
			var description := UILocale.text("待发 %s · 合同在途 %s · 已交付 %s")%[str(order.pending),str(int(order.transit)-awaiting),str(order.delivered)]
			if awaiting>0: description+=UILocale.text(" · 已到站待领 %s")%str(awaiting)
			if int(order.cancelled)>0: description+=" · "+UILocale.text("已取消 %s")%str(order.cancelled)
			var origin := str(_place(str(order.from_place_id)).get("name_zh","已知地点"))
			var destination := str(_place(str(order.to_place_id)).get("name_zh","已知地点"))
			var actions: Array=[]
			if not str(order.managed_firm).is_empty(): actions.append({"text":"经营详情","action":"work:firm:"+str(order.managed_firm)})
			else: actions.append({"text":"个人订单" if awaiting==0 else "查看提货","action":"work:records:orders"})
			var unit := ""
			for good: Dictionary in market.get("goods",[]):
				if str(good.good)==str(order.good): unit=str(good.get("unit_name_zh",""));break
			var payments := UILocale.text("已付货款 %s · 运费 %s")%[str(order.paid_goods_amount),str(order.paid_freight_amount)]
			rows.append({"name_zh":EconomicText.good(str(order.good))+(" · "+unit if not unit.is_empty() else "")+" · "+origin+" — "+destination,"details":[description,payments+" "+EconomicText.currency(str(order.denomination))],"actions":actions})
		if rows.is_empty(): rows.append({"name_zh":"此范围暂无本人或获准企业的订单记录","details":[]})
	shell.draw_administration_drawer(area,rows,true)

func _draw_chooser(shell: MainShell, area: Rect2) -> void:
	if chooser.is_empty(): return
	var rows: Array[Dictionary]=[]
	if chooser=="region":
		for place: Dictionary in region_choices(): rows.append({"label":str(place.name_zh),"action":"market:region:"+str(place.place_id)})
	elif chooser=="supply":
		for firm: String in market.get("managed_firms",[]): rows.append({"label":EconomicText.firm(firm),"action":"work:firm:"+firm})
	else:
		for country: Dictionary in country_choices: rows.append({"label":str(country.name_zh),"action":"market:country:"+str(country.id)})
	var h: float=minf(area.size.y,maxf(48,ceil(rows.size()/(2.0 if area.size.x-16>=500 else 1.0))*34+16))
	var bounds := Rect2(area.position,Vector2(area.size.x,h))
	UIDrawing.folio(shell,bounds,0.0,UIDrawing.Folio.MARKET)
	if rows.is_empty(): shell.label(area.position+Vector2(12,28),"暂无已知地区",12,UIDrawing.FOLIO_MUTED)
	for row: Dictionary in rows: row["name_zh"]=row.label
	shell.draw_administration_drawer(bounds.grow(-8),rows,true)

func _draw_commodity(shell: MainShell, rect: Rect2) -> void:
	var x := rect.position.x+24
	var y := rect.position.y+118
	shell.button(Rect2(x,rect.position.y+67,86,25),"返回行情","back",true,false,11,"folio_control")
	var price: Variant = "%.3f"%(float(quote.price_milli)/1000.0) if quote.has("price_milli") else item.get("price")
	shell.label(Vector2(x,y),EconomicText.good(selected_commodity_id) if native_managed else str(item.get("name_zh","商品未记录")),27,UIDrawing.FOLIO_INK,rect.size.x-48)
	shell.label(Vector2(x,y+32),"单位 "+str(item.get("unit_name_zh","未记录"))+" · 单价 "+(str(price) if price!=null else "未记录")+" "+(EconomicText.currency(str(item.get("denomination",FormalLedgerState.DENOMINATION))) if native_managed else str(item.get("denomination","模拟分币"))),13,UIDrawing.FOLIO_MUTED)
	shell.draw_line(Vector2(x,y+52),Vector2(rect.end.x-24,y+52),UIDrawing.FOLIO_RULE,1.0,true)
	shell.quantity_input(Rect2(x,y+76,154,29),quantity_milli,"economy:"+selected_commodity_id,int(item.get("quantity_scale",1000)))
	shell.label(Vector2(x+174,y+99),"应付 "+str(quote.get("amount","未取得报价"))+" "+EconomicText.currency(str(quote.get("denomination",FormalLedgerState.DENOMINATION))),19,UIDrawing.FOLIO_INK,rect.size.x-224)
	if bool(item.get("sale_supported",false)): shell.button(Rect2(x,y+119,132,29),"购买","purchase",bool(quote.get("success",false)),false,12,"folio_primary")
	if native_managed and quote.get("success",false):
		var breakdown := UILocale.text("货款 %s · 运费 %s")%[str(quote.goods_amount),str(quote.freight_amount)]
		if int(quote.quoted_quantity)<int(quote.quantity): breakdown+=UILocale.text(" · 当前可接 %s")%str(quote.quoted_quantity)
		shell.label(Vector2(x,y+159),breakdown,11,UIDrawing.FOLIO_MUTED,rect.size.x-48)
	if not bool(quote.get("success",false)):
		var reason := str(quote.get("error","当前不可购买。"))
		shell.wrapped(Vector2(x,y+172),EconomicText.reason(reason),rect.size.x-48,12,3,UIDrawing.FOLIO_INK)
	elif native_managed: shell.label(Vector2(x,y+172),"现场交付后取得。" if quote.get("fulfilment")=="ONSITE_REAL_STOCK_HANDOVER" else "接受后预留资金；实际到货后取得物品。",11,UIDrawing.FOLIO_MUTED)
	if native_managed and quote.get("success",false):
		var seller := EconomicText.firm(str(quote.get("seller","")))
		var site := EconomicText.site(str(quote.get("seller_site","")))
		shell.label(Vector2(x,y+198),"卖方："+seller+(" · "+site if site!=seller else ""),10,UIDrawing.FOLIO_MUTED,rect.size.x-48)
