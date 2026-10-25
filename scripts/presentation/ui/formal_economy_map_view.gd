class_name FormalEconomyMapView
extends Control
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
## UI over the installed GlobeRenderer. No map foundation or Runtime is created.
## Order/cargo formatting reused from the frozen economy-consumer-access view.
signal query_requested(subject: String, offset: int)
signal focus_requested(place_id: String)
signal selection_requested(place_id: String)
signal back_requested
signal expand_requested
signal links_changed(rows: Array[Dictionary])
signal business_requested(subject_id: String, site_id: String)
signal statistics_requested
const GOODS = EconomicText.GOODS
var snapshot: Dictionary = {}
var network: Dictionary = {}
var contacts: Dictionary = {}
var catalog: VNextSpatialCatalog
var selected_place: String = "place:paris"
var selected_site: String = ""
var selected_order: String = ""
var selected_good: String = "all"
var full: bool = false
var show_contacts: bool = false
var show_receipts: bool = true
var _updating: bool = false
var _toolbar: HBoxContainer
var _side: PanelContainer
var _heading: Label
var _details: RichTextLabel
var _subjects: OptionButton
var _places: OptionButton
var _orders: OptionButton
var _goods_select: OptionButton
var _page: Label
var _expand: Button
var _previous: Button
var _next: Button
var _business: Button
var _return_map: Button
var _managed_subject: bool = false
var _detail_toggle: Button
var _details_collapsed: bool = false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=UIDrawing.shell_theme()
	_toolbar=HBoxContainer.new();add_child(_toolbar)
	# Keep one compact primary row. City shortcuts remain in its native menu.
	_toolbar.theme=theme.duplicate(true)
	_toolbar.theme.default_font_size=14
	for state:String in ["normal","hover","pressed","disabled","focus"]:
		var box:=_toolbar.theme.get_stylebox(state,"Button") as StyleBoxFlat
		box.content_margin_top=5;box.content_margin_bottom=5
		box.content_margin_left=10;box.content_margin_right=10
	_button(_toolbar,"定位所选",func():focus_requested.emit(selected_place))
	var locations:=MenuButton.new();locations.text="地点";locations.flat=false
	locations.tooltip_text="巴黎 / 里昂 / 马赛；只定位镜头。";_toolbar.add_child(locations)
	var places:Array[String]=[]
	for p: Array in [["巴黎","place:paris"],["里昂","place:lyon"],["马赛","place:marseille"]]:
		places.append(str(p[1]));locations.get_popup().add_item(str(p[0]),places.size()-1)
	locations.get_popup().id_pressed.connect(func(id:int):focus_requested.emit(places[id]))
	_detail_toggle=_button(_toolbar,"收起详情",_toggle_details)
	_return_map=_button(_toolbar,"返回政治地图",func():back_requested.emit())
	_toolbar.minimum_size_changed.connect(_layout)
	_side=PanelContainer.new();add_child(_side);_side.mouse_filter=Control.MOUSE_FILTER_STOP
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",5);_side.add_child(column)
	_heading=Label.new();_heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_heading)
	var actions:=HBoxContainer.new();column.add_child(actions)
	_expand=_button(actions,"完整经济地图",func():expand_requested.emit())
	_button(actions,"关闭详情",func():back_requested.emit())
	var navigation:=HBoxContainer.new();column.add_child(navigation)
	_business=_button(navigation,"经营所选站点",func():business_requested.emit(str(snapshot.get("subject","")),selected_site))
	_button(navigation,"正式市场页",func():statistics_requested.emit())
	_subjects=OptionButton.new();_subjects.fit_to_longest_item=false;column.add_child(_subjects)
	_subjects.item_selected.connect(func(index:int):
		if not _updating:query_requested.emit(str(_subjects.get_item_metadata(index)),0))
	_places=OptionButton.new();_places.fit_to_longest_item=false;column.add_child(_places)
	_places.item_selected.connect(func(index:int):
		if not _updating:
			var row:Dictionary=_places.get_item_metadata(index)
			selected_site=str(row.get("site_id",""))
			select_place(str(row.place_id));selection_requested.emit(selected_place))
	_orders=OptionButton.new();_orders.fit_to_longest_item=false;column.add_child(_orders)
	_orders.item_selected.connect(func(index:int):
		if not _updating:selected_order=str(_orders.get_item_metadata(index));_detail())
	_goods_select=OptionButton.new();_goods_select.add_item("全部商品");_goods_select.set_item_metadata(0,"all");column.add_child(_goods_select)
	_goods_select.item_selected.connect(func(index:int):selected_good=str(_goods_select.get_item_metadata(index));_detail())
	var options:=HBoxContainer.new();column.add_child(options)
	var known:=CheckButton.new();known.text="已知报价联系";options.add_child(known)
	known.toggled.connect(func(on:bool):show_contacts=on;_publish_links())
	var receipts:=CheckButton.new();receipts.text="本页近7日到货";receipts.button_pressed=true;options.add_child(receipts)
	receipts.toggled.connect(func(on:bool):show_receipts=on;_publish_links())
	_details=RichTextLabel.new();_details.custom_minimum_size=Vector2(300,90);_details.size_flags_vertical=Control.SIZE_EXPAND_FILL;_details.scroll_active=true;column.add_child(_details)
	var pages:=HBoxContainer.new();column.add_child(pages)
	_previous=_button(pages,"上一页",func():query_requested.emit(str(snapshot.get("subject","")),maxi(0,int(snapshot.get("offset",0))-32)))
	_page=Label.new();_page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pages.add_child(_page)
	_next=_button(pages,"下一页",func():query_requested.emit(str(snapshot.get("subject","")),int(snapshot.get("offset",0))+32))
	resized.connect(_layout);_layout();hide()

func _button(parent:Control,text:String,action:Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=26;parent.add_child(button);button.pressed.connect(action);return button

func _layout() -> void:
	if _side==null:return
	_toolbar.position=Vector2(124,66);_toolbar.size=_toolbar.get_combined_minimum_size()
	_side.position=Vector2(maxf(12,size.x-348),142);_side.size=Vector2(332,maxf(230,size.y-236))

func _toggle_details() -> void:
	_details_collapsed=not _details_collapsed
	_side.visible=not _details_collapsed
	_detail_toggle.text="展开详情" if _details_collapsed else "收起详情"
	_layout()
	# Refresh the existing label exclusions without querying or advancing a world.
	_publish_links()

func occlusions() -> Array[Rect2]:
	var rows:Array[Rect2]=[]
	if visible:
		if _side.visible:rows.append(Rect2(_side.position,_side.size))
		if full:rows.append(Rect2(_toolbar.position,_toolbar.size))
	return rows

func present(value:Dictionary, source_catalog:VNextSpatialCatalog, expanded:bool, return_mode:String="political") -> void:
	catalog=source_catalog;full=expanded;_updating=true
	# Already detached and bounded by the host observation adapter.
	snapshot=value;network=value.get("market_network",{});contacts=value.get("market_contacts",{})
	_toolbar.visible=full;_expand.visible=not full
	_side.visible=not full or not _details_collapsed
	_return_map.text="返回地理地图" if return_mode=="geographic" else "返回政治地图"
	_subjects.clear()
	_business.disabled=true
	_managed_subject=false
	for row:Dictionary in value.get("subjects",[]):
		_subjects.add_item(str(row.name));_subjects.set_item_metadata(_subjects.item_count-1,str(row.id))
		if row.id==value.get("subject",""):
			_subjects.select(_subjects.item_count-1)
			_managed_subject=row.kind=="firm"
	_places.clear();var ids:Array=network.get("nodes",{}).keys()
	for id:String in contacts.get("nodes",{}):
		if id not in ids:ids.append(id)
	if selected_place not in ids:ids.push_front(selected_place)
	for id:String in ids.slice(0,64):
		if _places.item_count>=64:break
		var located:bool=catalog.get_place(id).get("lon_lat") is Array
		var sites:Array=network.get("nodes",{}).get(id,{}).get("known_own_sites",[])
		if sites.is_empty():
			_places.add_item(place_name(id)+(" · 未定位" if not located else " · 只读"));_places.set_item_metadata(_places.item_count-1,{"place_id":id,"site_id":""})
		else:
			for site:String in sites:
				if _places.item_count>=64:break
				_places.add_item(place_name(id)+" · "+site);_places.set_item_metadata(_places.item_count-1,{"place_id":id,"site_id":site})
	_sync_site_selection()
	_orders.clear();_orders.add_item("地点详情／选择订单");_orders.set_item_metadata(0,"")
	for id:String in network.get("edges",{}):
		var edge:Dictionary=network.edges[id]
		_orders.add_item(id+" · "+_edge_status(edge));_orders.set_item_metadata(_orders.item_count-1,id)
		if id==selected_order:_orders.select(_orders.item_count-1)
	if not network.get("edges",{}).has(selected_order):selected_order=""
	_goods_select.clear();_goods_select.add_item("全部商品");_goods_select.set_item_metadata(0,"all")
	var goods:Dictionary={}
	for row:Dictionary in value.get("firm",{}).get("offers",[]):goods[str(row.get("good",""))]=true
	for edge:Dictionary in network.get("edges",{}).values():goods[str(edge.good)]=true
	for operation:Dictionary in value.get("firm",{}).get("operations",[]):
		for good:String in operation.get("inventory",{}):goods[good]=true
	for good:String in (value.get("macro",{}).get("inventory",{}) as Dictionary):goods[good]=true
	for good:String in goods:
		_goods_select.add_item(str(GOODS.get(good,good)));_goods_select.set_item_metadata(_goods_select.item_count-1,good)
		if good==selected_good:_goods_select.select(_goods_select.item_count-1)
	var date:=value.get("date",{}) as Dictionary
	_heading.text="当前正式世界 · %04d-%02d-%02d %02d:%02d\n经济观察 · "+("完整专题" if full else "政治地图补充详情")
	_heading.text=_heading.text % [int(date.get("year",1900)),int(date.get("month",1)),int(date.get("day",1)),int(date.get("hour",0)),int(date.get("minute",0))]
	_page.text="%d / %d条"%[mini(int(value.get("offset",0))+32,int(value.get("orders_total",0))),int(value.get("orders_total",0))]
	_previous.disabled=int(value.get("offset",0))==0
	_next.disabled=int(value.get("offset",0))+32>=int(value.get("orders_total",0))
	_updating=false;_detail();show()

func clear_observation() -> void:
	hide();snapshot={};network={};contacts={};catalog=null
	_details_collapsed=false
	_detail_toggle.text="收起详情"
	_managed_subject=false;_business.disabled=true
	_subjects.clear();_places.clear();_orders.clear();_details.clear()
	var empty: Array[Dictionary] = []
	links_changed.emit(empty)

func select_place(id:String) -> void:
	selected_place=FormalEconomicMapObservation.canonical_place(id);selected_order=""
	_sync_site_selection()
	if not _updating:_detail()

func _sync_site_selection() -> void:
	var owned:Array=network.get("nodes",{}).get(selected_place,{}).get("known_own_sites",[])
	if selected_site not in owned:selected_site=str(owned[0]) if not owned.is_empty() else ""
	var personal:bool=snapshot.get("subject","")==snapshot.get("observer","") and not snapshot.get("firm",{}).is_empty()
	_business.text="岗位与个人订单" if personal else "经营所选站点"
	_business.disabled=not personal and (not _managed_subject or selected_site.is_empty())
	_business.tooltip_text="当前人物的原岗位页；地图浏览不移动人物或授予企业权限。" if personal else "只读观察；当前地点没有获准经营的本站点。" if _business.disabled else "原经营页 · "+selected_site
	for index:int in range(_places.item_count):
		var row:Dictionary=_places.get_item_metadata(index)
		if row.place_id==selected_place and str(row.site_id)==selected_site:_places.select(index);break

func follow_order(id:String, place_id:String, site_id:String) -> void:
	selected_place=FormalEconomicMapObservation.canonical_place(place_id)
	selected_site=site_id;selected_order=id

func place_name(id:String) -> String:
	if catalog==null:return id
	var place:=catalog.get_place(id)
	return str(place.get("name_zh",place.get("name",id)))

func _detail() -> void:
	if _details==null:return
	var lines:Array[String]=[]
	var macro:=snapshot.get("macro",{}) as Dictionary
	if str(snapshot.get("subject","")).begins_with("aggregate:"):
		var totals:=macro.get("daily_totals",{}) as Dictionary
		lines.append("国家统计（不是城市或企业库存）")
		if totals.is_empty() or float(totals.get("fulfillment_bp",-1))<0:lines.append("尚无已结算统计。未知值不按零显示。")
		else:lines.append("满足率 %.1f%%\n需求 %s · 消费 %s\n实际生产 %s · 未满足 %s"%[float(totals.get("fulfillment_bp",0))/100.0,str(totals.get("demand_units","未知")),str(totals.get("consumed_units","未知")),str(totals.get("produced_units","未知")),str(totals.get("unmet_units","未知"))])
		var stock:=macro.get("inventory",{}) as Dictionary
		for good:String in stock:
			if selected_good in ["all",good]:lines.append(str(GOODS.get(good,good))+" · 国家统计库存 "+str(stock[good]))
		if not bool(snapshot.get("native_enabled",false)):lines.append("当前世界未安装原生企业经营；研究槽位的企业、订单和库存不属于此世界。")
	elif not selected_order.is_empty():
		var order:=_raw_order(selected_order)
		lines.append("所选已知订单 · "+_edge_status(network.get("edges",{}).get(selected_order,{})))
		lines.append("%s → %s\n商品 %s · 待发 %s／在途责任 %s／已到货 %s"%[place_name(str(order.get("from_place_id",""))),place_name(str(order.get("to_place_id",""))),str(GOODS.get(str(order.get("good","")),order.get("good",""))),str(order.get("pending","未知")),str(order.get("transit","未知")),str(order.get("delivered","未知"))])
		lines.append(_cargo_text(selected_order))
		lines.append("订单联系示意，不是铁路／公路或实时货运位置。")
	else:
		lines.append(place_name(selected_place)+" · 城市级锚点，不是厂房地籍坐标。")
		var own:=snapshot.get("firm",{}) as Dictionary
		if own.has("cash") and own.has("reserved"):lines.append("获准主体账面现金 %s · 预留 %s（原记账单位）"%[str(own.cash),str(own.reserved)])
		var personal:=own.get("participation",{}) as Dictionary
		if not personal.is_empty():
			lines.append("当前控制人物（本人）"+"\n人物所在地 "+place_name(str(personal.current_place_id)))
			var employment:=personal.get("employment",{}) as Dictionary
			if not employment.is_empty():lines.append("雇主 "+EconomicText.firm(str(personal.get("employer",{}).get("employer_id","")))+"\n工作地点 "+place_name(str(employment.get("work_place_id","")))+" · 时薪 "+str(employment.get("wage_per_hour",0)))
			else:lines.append("尚无劳动合同 · 已知岗位 "+str(own.get("known_jobs",[]).size()))
			for job: Dictionary in (own.get("known_jobs",[]) as Array).slice(0,2):
				if job.has("vacancies"): lines.append("本地已知岗位空额 %d / %d · %s" % [int(job["vacancies"]),int(job["positions"]),EconomicText.firm(job["employer"])+" · "+EconomicText.job(job["id"])])
				lines.append("时薪%d · 每期%d小时 · 日结后延迟%d日 · 技能%d：%s" % [int(job["wage_per_hour"]),int(job["hours"]),int(job["wage_delay"]),int(job["skill"]),"符合" if job.get("qualified",false) else "不符"])
			lines.append("实际工作 %s小时 · 已付收入 %s · 未付工资 %s"%[str(own.get("totals",{}).get("work_hours",0)),str(own.get("totals",{}).get("income",0)),str(own.get("wage_outstanding",0))])
		var operation:Dictionary={}
		for row:Dictionary in own.get("operations",[]):
			if str(row.get("site_id",""))==selected_site:operation=row;break
		if not operation.is_empty():
			lines.append("获准站点 "+selected_site+"\n在库："+_goods(operation.get("inventory",{})))
			lines.append("自由："+_goods(operation.get("free_inventory",{}))+"\n承诺："+_goods(operation.get("committed_inventory",{})))
			var pending_messages:Array=operation.get("pending_directory_results",[])
			if not pending_messages.is_empty():lines.append("已提出的供货查询 %d 项仍在等待；尚未作为已收到报价或成交。"%pending_messages.size())
		else:lines.append("没有获准查看的自有站点库存，不推定其他企业库存。")
		lines.append(_cargo_text("",selected_place))
		var count:=0
		for offer:Dictionary in contacts.get("contacts",[]):
			if selected_good not in ["all",str(offer.good)] or selected_place not in [str(offer.from_place_id),str(offer.to_place_id)]:continue
			lines.append("已知报价：%s · %s → %s\n单价 %s · 单位运费 %s · 可报价 %s\n%s（不是已成交运输）"%[str(GOODS.get(str(offer.good),offer.good)),place_name(str(offer.from_place_id)),place_name(str(offer.to_place_id)),str(offer.get("price","未知")),str(offer.get("freight_per_unit","未知")),str(offer.get("quantity","未知")),str(offer.get("reason","未知"))])
			count+=1
			if count>=8:break
		for edge:Dictionary in network.get("edges",{}).values():
			if selected_place in [str(edge.from_node),str(edge.to_node)] and selected_good in ["all",str(edge.good)]:lines.append(str(edge.order_id)+" · "+_edge_status(edge))
	if full and not network.is_empty():lines.append("线条表示经济联系，不是交通线路。报价未成交；下单权限见经营详情。")
	_details.text="\n\n".join(lines);_publish_links()

func _publish_links() -> void:
	var rows:Array[Dictionary]=[]
	if full:
		for edge:Dictionary in network.get("edges",{}).values():
			if selected_good not in ["all",str(edge.good)]:continue
			if not selected_order.is_empty() and str(edge.order_id)!=selected_order:continue
			if selected_order.is_empty() and selected_place not in [str(edge.from_node),str(edge.to_node)]:continue
			rows.append({"id":str(edge.order_id),"from":str(edge.from_node),"to":str(edge.to_node),"kind":"contract","state":_edge_status(edge)})
			if rows.size()>=12:break
		if show_receipts and selected_good!="all":
			for flow:Dictionary in contacts.get("flows",{}).values():
				if rows.size()>=12:break
				if flow.good!=selected_good or int(flow.get("received_in_window",0))<=0 or selected_place not in [str(flow.from_place_id),str(flow.to_place_id)]:continue
				rows.append({"id":"receipt:"+str(flow.from_place_id)+":"+str(flow.to_place_id)+":"+str(flow.good),"from":str(flow.from_place_id),"to":str(flow.to_place_id),"kind":"receipt","state":"本页近7日实际到货 · 非当前在途"})
		if show_contacts:
			for offer:Dictionary in contacts.get("contacts",[]):
				if rows.size()>=12:break
				if selected_good not in ["all",str(offer.good)] or selected_place not in [str(offer.from_place_id),str(offer.to_place_id)]:continue
				rows.append({"id":str(offer.get("quote_id","")),"from":str(offer.from_place_id),"to":str(offer.to_place_id),"kind":"offer","state":"候选报价 · 未发生交易／未核验下单权限","available":bool(offer.get("quoted_quantity_positive",false))})
	links_changed.emit(rows)

func _edge_status(edge: Dictionary) -> String:
	var raw: Dictionary=_raw_order(str(edge.order_id))
	if int(edge.get("transit_responsibility",0))>0:return "在途责任"
	if int(edge.get("pending_responsibility",0))>0:return "已接受／待发"
	var loss: Variant=raw.get("unresolved_loss_quantity")
	if loss is int and loss>0:return "待处理损失"
	return "已到货／历史关系" if int(edge.get("delivered",0))>0 else "已关闭关系"

func _raw_order(id: String) -> Dictionary:
	var firm: Dictionary=snapshot.get("firm",{})
	for key: String in ["orders","sales_orders"]:
		var rows: Variant=firm.get(key,[])
		if rows is Array:
			for order: Dictionary in rows:
				if order.get("id")==id:return order
	return {}

func _goods(values: Dictionary) -> String:
	var rows: Array[String]=[]
	for good: String in values:
		if values[good]!=0:rows.append("%s %s"%[GOODS.get(good,good),values[good]])
	return "、".join(rows) if not rows.is_empty() else "0（已有视图）"

func _money(values: Dictionary) -> String:
	var rows: Array[String]=[]
	for denomination: String in values:
		var label: String=EconomicText.currency(denomination)
		rows.append("%s（%s）"%[values[denomination],label])
	return "、".join(rows) if not rows.is_empty() else "0（已有收据）"

func _cargo_text(order_id: String="",place_id: String="") -> String:
	var rows: Array[String]=[]
	for id: String in network.get("cargo",{}):
		var cargo: Dictionary=network.cargo[id]
		if not order_id.is_empty() and cargo.order_id!=order_id:continue
		if not place_id.is_empty() and cargo.from_node!=place_id and cargo.to_node!=place_id and cargo.place_id!=place_id:continue
		if not cargo.get("physical_quantity") is int or int(cargo.physical_quantity)<=0:continue
		rows.append("%s · %s %s · 阶段 %s\n所涉 %s → %s；已知地点 %s\n精确位置未知；不作实时移动"%[id,GOODS.get(cargo.good,cargo.good),cargo.physical_quantity,cargo.stage,place_name(cargo.from_node),place_name(cargo.to_node),place_name(cargo.place_id) if not str(cargo.place_id).is_empty() else "未知"])
		if cargo.get("earliest_arrival_day")!=null:rows.append("最早到货下限：第%s天（非保证到达）"%str(int(cargo.earliest_arrival_day)+1))
		if not str(cargo.get("arrival_blocked_reason","")).is_empty():rows.append("阻塞："+str(cargo.arrival_blocked_reason))
	return "\n".join(rows) if not rows.is_empty() else "当前没有已确认在途货批"
