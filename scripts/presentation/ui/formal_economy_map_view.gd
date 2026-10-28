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
signal demand_changed
signal flow_animation_changed(enabled: bool)
signal personal_market_requested
signal pending_cancellation_requested(order_id: String)
const GOODS = EconomicText.GOODS
var snapshot: Dictionary = {}
var network: Dictionary = {}
var contacts: Dictionary = {}
var public_network: Dictionary = {}
var selected_node: String = ""
const LINK_BUDGET = 48
const PLACE_MENU_BUDGET = 128
const RECEIPT_BUDGET = 256
var catalog: VNextSpatialCatalog
var selected_place: String = "place:paris"
var selected_site: String = ""
var selected_order: String = ""
var selected_good: String = "all"
var full: bool = false
var show_contacts: bool = false
var show_routes: bool = true
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
var _details_collapsed: bool = true
var research_expanded: bool = false
var flow_animation_enabled: bool = true
var _research_toggle: Button
var _flow_toggle: CheckButton
var _menu_key: Array = []
var _receipt_facts: Array[Dictionary] = []
var _flow_subject: String = ""
var _flow_observer: String = ""
var _flow_world_id: int = 0
var _flow_scope: Dictionary = {}
var _order_index: Dictionary = {}
var _receipt_source_count: int = 0
var _receipt_truncated: bool = false
var _page_offsets: Array[int] = []
var _jobs: Button
var _personal_market: Button
var _cancel_pending: Button
var _navigation_pending: Dictionary = {}

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
	_detail_toggle=_button(_toolbar,"展开详情",_toggle_details)
	_return_map=_button(_toolbar,"返回政治地图",func():back_requested.emit())
	_toolbar.minimum_size_changed.connect(_layout)
	_side=PanelContainer.new();add_child(_side);_side.mouse_filter=Control.MOUSE_FILTER_STOP
	# A compact local theme: do not shrink the installed shell or map toolbar.
	_side.theme=theme.duplicate(true);_side.theme.default_font_size=13
	for type:String in ["Button","OptionButton","CheckButton"]:
		for state:String in ["normal","hover","pressed","disabled","focus"]:
			var box:=_side.theme.get_stylebox(state,"Button").duplicate() as StyleBoxFlat
			box.content_margin_top=4;box.content_margin_bottom=4
			box.content_margin_left=5;box.content_margin_right=5
			_side.theme.set_stylebox(state,type,box)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",4);_side.add_child(column)
	_heading=Label.new();_heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_heading)
	var actions:=HBoxContainer.new();column.add_child(actions)
	_expand=_button(actions,"完整经济地图",func():expand_requested.emit())
	_button(actions,"关闭详情",func():back_requested.emit())
	var navigation:=HBoxContainer.new();column.add_child(navigation)
	_business=_button(navigation,"经营所选站点",func():business_requested.emit(str(snapshot.get("subject","")),selected_site))
	_button(navigation,"国家统计",func():statistics_requested.emit())
	_jobs=_button(navigation,"本人岗位",func():business_requested.emit(str(snapshot.get("observer","")),""))
	_personal_market=_button(navigation,"已知报价",func():personal_market_requested.emit())
	_jobs.tooltip_text="原人物岗位与订单页；不因浏览城市而移动人物或获得经营权。"
	_personal_market.tooltip_text="本人已知报价；按真实所在地和原规则复核，不是所看城市的全市场。"
	_subjects=OptionButton.new();_subjects.fit_to_longest_item=false;column.add_child(_subjects)
	_subjects.item_selected.connect(func(index:int):
		if not _updating:
			selected_site="";selected_order="";_page_offsets.clear()
			query_requested.emit(str(_subjects.get_item_metadata(index)),0))
	_places=OptionButton.new();_places.fit_to_longest_item=false;column.add_child(_places)
	_places.item_selected.connect(func(index:int):
		if not _updating:
			var row:Dictionary=_places.get_item_metadata(index)
			selected_node=str(row.get("node_id",""));selected_site=str(row.get("site_id",""))
			selected_place=str(row.place_id);selected_order=""
			_sync_site_selection()
			var subject:=str(row.get("subject_id",snapshot.get("subject","")))
			if subject!=str(snapshot.get("subject","")):query_requested.emit(subject,0)
			else:demand_changed.emit())
	_orders=OptionButton.new();_orders.fit_to_longest_item=false;column.add_child(_orders)
	_orders.item_selected.connect(func(index:int):
		if not _updating:
			selected_order=str(_orders.get_item_metadata(index));_detail();demand_changed.emit())
	_goods_select=OptionButton.new();_goods_select.add_item("全部商品");_goods_select.set_item_metadata(0,"all");column.add_child(_goods_select)
	_goods_select.item_selected.connect(func(index:int):selected_good=str(_goods_select.get_item_metadata(index));_detail())
	var options:=HBoxContainer.new();column.add_child(options)
	var routes:=CheckButton.new();routes.text="通路";routes.tooltip_text="已知通路/开发交通许可；不推定当前畅通、剩余运力或成交。";routes.button_pressed=true;options.add_child(routes)
	routes.toggled.connect(func(on:bool):show_routes=on;_publish_links())
	_flow_toggle=CheckButton.new();_flow_toggle.text="流动";_flow_toggle.button_pressed=flow_animation_enabled
	_flow_toggle.tooltip_text="近7日已确认交付的方向脉冲，不是当前货批位置。只随世界时间变化，暂停冻结。";options.add_child(_flow_toggle)
	_flow_toggle.toggled.connect(set_flow_animation)
	var receipts:=CheckButton.new();receipts.text="到货7日";receipts.tooltip_text="本页授权订单近7日实际到货收据；不是当前在途。";receipts.button_pressed=true;options.add_child(receipts)
	receipts.toggled.connect(func(on:bool):show_receipts=on;_publish_links())
	_details=RichTextLabel.new();_details.custom_minimum_size=Vector2(0,140);_details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_details.size_flags_vertical=Control.SIZE_EXPAND_FILL;_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_details.scroll_active=true;column.add_child(_details)
	_cancel_pending=_button(column,"取消本单未发部分",_request_pending_cancellation)
	_cancel_pending.visible=false;_cancel_pending.disabled=true
	for selector:OptionButton in [_subjects,_places,_orders,_goods_select]:
		selector.clip_text=true;selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var pages:=HBoxContainer.new();column.add_child(pages)
	_previous=_button(pages,"上一页",func():
		var previous:int=_page_offsets.pop_back() if not _page_offsets.is_empty() else 0
		query_requested.emit(str(snapshot.get("subject","")),previous))
	_page=Label.new();_page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pages.add_child(_page)
	_next=_button(pages,"下一页",func():
		_page_offsets.append(int(snapshot.get("offset",0)))
		query_requested.emit(str(snapshot.get("subject","")),int(snapshot.get("next_offset",0))))
	_research_toggle=_button(column,"展开研发细节",func():
		research_expanded=not research_expanded
		_research_toggle.text="收起研发细节" if research_expanded else "展开研发细节"
		_menu_key.clear();_detail())
	resized.connect(_layout);_layout();hide()

func _button(parent:Control,text:String,action:Callable) -> Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=26;parent.add_child(button);button.pressed.connect(action);return button

func _layout() -> void:
	if _side==null:return
	_toolbar.position=Vector2(124,66);_toolbar.size=_toolbar.get_combined_minimum_size()
	_side.position=Vector2(maxf(12,size.x-348),142);_side.size=Vector2(332,maxf(360,size.y-154))

func _toggle_details() -> void:
	set_details_open(_details_collapsed)

func set_details_open(open: bool) -> void:
	if _details_collapsed==(not open):return
	_details_collapsed=not open
	_side.visible=open
	_detail_toggle.text="收起详情" if open else "展开详情"
	_layout();demand_changed.emit()

func set_flow_animation(enabled: bool) -> void:
	if flow_animation_enabled==enabled:return
	flow_animation_enabled=enabled
	if _flow_toggle!=null:_flow_toggle.set_pressed_no_signal(enabled)
	flow_animation_changed.emit(enabled)

func details_requested() -> bool:
	return not _details_collapsed

func _hub() -> Dictionary:
	for hub:Dictionary in snapshot.get("hubs",{}).get("hubs",[]):
		if str(hub.get("place_id",""))==selected_place:return hub
	return {}

func occlusions() -> Array[Rect2]:
	var rows:Array[Rect2]=[]
	if visible:
		if _side.visible:rows.append(Rect2(_side.position,_side.size))
		if full:rows.append(Rect2(_toolbar.position,_toolbar.size))
	return rows

func navigation_state() -> Dictionary:
	# Identifiers/preferences only. Never retain the old observation in history.
	var source:Dictionary=_navigation_pending if not _navigation_pending.is_empty() else snapshot
	return {"world_id":int(source.get("world_id",_flow_world_id)),"observer":str(source.get("observer",_flow_observer)),"subject":str(source.get("subject","")),"place":selected_place,"site":selected_site,"order":selected_order,"offset":int(source.get("offset",0)),"details":not _details_collapsed,"research":research_expanded,"expanded":full}

func restore_navigation(state:Dictionary) -> void:
	_navigation_pending={"world_id":int(state.get("world_id",0)),"observer":str(state.get("observer","")),"subject":str(state.get("subject","")),"offset":maxi(0,int(state.get("offset",0)))}
	selected_place=FormalEconomicMapObservation.canonical_place(str(state.get("place","place:paris")))
	selected_site=str(state.get("site",""));selected_order=str(state.get("order",""));selected_node=""
	_details_collapsed=not bool(state.get("details",false));research_expanded=bool(state.get("research",false));full=bool(state.get("expanded",false))
	_page_offsets.clear();_menu_key.clear()
	if not is_node_ready():return
	_subjects.clear();_places.clear();_orders.clear();_goods_select.clear();_details.text=""
	_business.disabled=true;_jobs.disabled=true;_personal_market.disabled=true
	_cancel_pending.visible=false;_cancel_pending.disabled=true
	_detail_toggle.text="展开详情" if _details_collapsed else "收起详情"
	_research_toggle.text="收起研发细节" if research_expanded else "展开研发细节"
	_side.visible=not _details_collapsed;_toolbar.visible=full
	# No show(), signals, observer reads, focus or world mutation here.

func present(value:Dictionary, source_catalog:VNextSpatialCatalog, expanded:bool, return_mode:String="political") -> void:
	catalog=source_catalog;full=expanded;_updating=true
	var subject:=str(value.get("subject",""));var observer:=str(value.get("observer",""))
	var authorized:bool=false
	for row:Dictionary in value.get("authorized_subjects",[]):
		if str(row.id)==subject:authorized=true;break
	var world_id:=int(value.get("world_id",0))
	if not _navigation_pending.is_empty():
		if world_id!=int(_navigation_pending.get("world_id",0)) or observer!=str(_navigation_pending.get("observer","")):
			selected_site="";selected_order="";selected_node="";research_expanded=false;_details_collapsed=true
		_navigation_pending.clear()
	_jobs.disabled=observer.is_empty();_personal_market.disabled=observer.is_empty()
	_cancel_pending.visible=false;_cancel_pending.disabled=true
	var source_changed:bool=world_id==0 or world_id!=_flow_world_id or observer!=_flow_observer
	if source_changed:
		public_network={};_menu_key.clear();_page_offsets.clear()
		_subjects.clear();_places.clear();_orders.clear();_goods_select.clear()
		_heading.text="";_page.text=""
	if source_changed or subject!=_flow_subject or not authorized:
		network={};contacts={};_receipt_facts.clear();_order_index.clear();_flow_scope.clear()
		_receipt_source_count=0;_receipt_truncated=false
		_details.text="";_managed_subject=false;_business.disabled=true
	_flow_subject=subject;_flow_observer=observer;_flow_world_id=world_id
	snapshot=value;selected_place=str(value.get("selected_place",selected_place))
	if bool(value.get("details_loaded",false)):
		network=value.get("market_network",{});contacts=value.get("market_contacts",{});public_network=value.get("node_network",{})
		selected_site=str(value.get("selected_site",selected_site))
		_flow_scope=(value.get("read_scope",{}) as Dictionary).duplicate(true)
		_flow_scope["date"]=(value.get("date",{}) as Dictionary).duplicate()
		_rebuild_order_index();_collect_receipts()
		var follow:=str(value.get("follow_order_id",""))
		if not follow.is_empty() and _order_index.has(follow):selected_order=follow
	_detail_toggle.text="展开详情" if _details_collapsed else "收起详情"
	_research_toggle.text="收起研发细节" if research_expanded else "展开研发细节"
	_toolbar.visible=full;_expand.visible=not full;_side.visible=not _details_collapsed
	_return_map.text="返回地理地图" if return_mode=="geographic" else "返回政治地图"
	if not _details_collapsed:
		_update_menus(value)
		var date:Dictionary=value.get("date",{})
		_heading.text=place_name(selected_place)+" · 城市经济\n%04d-%02d-%02d %02d:%02d"%[int(date.get("year",1900)),int(date.get("month",1)),int(date.get("day",1)),int(date.get("hour",0)),int(date.get("minute",0))]
		_page.text="本页%d条%s"%[(network.get("edges",{}) as Dictionary).size()," · 还有后页" if bool(value.get("truncated",false)) else ""]
		_page.tooltip_text="相关主体逆序索引%d条；本站页可能继续扫描，索引不是本站或全市场订单总量。"%int(value.get("orders_total",0))
		_previous.disabled=_page_offsets.is_empty()
		_next.disabled=not bool(value.get("truncated",false))
		_detail()
	_updating=false
	if _details_collapsed:_publish_links() # Open details already publish once in _detail().
	show()

func _update_menus(value:Dictionary) -> void:
	var subject:=str(value.get("subject",""))
	var order_rows:Array=[]
	for id:String in network.get("edges",{}):
		var edge:Dictionary=network.edges[id]
		order_rows.append([id,str(edge.good),_edge_status(edge)])
	var key:Array=[value.get("subjects",[]),public_network.get("nodes",[]),subject,selected_site,selected_order,order_rows,_hub().get("known_goods",[]),research_expanded]
	if key==_menu_key:return
	_menu_key=key
	_subjects.clear();_managed_subject=false
	for row:Dictionary in value.get("subjects",[]):
		_subjects.add_item(str(row.name));_subjects.set_item_metadata(_subjects.item_count-1,str(row.id))
		if str(row.id)==subject:_subjects.select(_subjects.item_count-1);_managed_subject=str(row.kind)=="firm"
	var authorized:Dictionary={}
	for row:Dictionary in value.get("authorized_subjects",[]):
		if str(row.get("kind",""))=="firm":authorized[str(row.get("id",""))]=true
	_places.clear();_places.add_item("选择本城有权站点" if subject.is_empty() else "本站点／公开身份")
	_places.set_item_metadata(0,{"place_id":selected_place,"site_id":"","node_id":"","subject_id":subject})
	for node:Dictionary in public_network.get("nodes",[]):
		if str(node.get("kind",""))!="site" or str(node.get("place_id",""))!=selected_place:continue
		var firm:=str(node.get("firm_id",""))
		if (subject.is_empty() and not authorized.has(firm)) or (not subject.is_empty() and firm!=subject):continue
		if _places.item_count>=PLACE_MENU_BUDGET:break
		_places.add_item(EconomicText.site(str(node.get("site_id",""))))
		_places.set_item_metadata(_places.item_count-1,{"place_id":selected_place,"site_id":str(node.get("site_id","")),"node_id":str(node.get("id","")),"subject_id":firm})
	_sync_site_selection()
	_orders.clear();_orders.add_item("经营概要／选择订单");_orders.set_item_metadata(0,"")
	for row:Array in order_rows:
		_orders.add_item(EconomicText.good(str(row[1]))+" · "+str(row[2])+(" · "+str(row[0]) if research_expanded else ""));_orders.set_item_metadata(_orders.item_count-1,str(row[0]))
		if str(row[0])==selected_order:_orders.select(_orders.item_count-1)
	if not network.get("edges",{}).has(selected_order):selected_order=""
	var goods:Dictionary={}
	for good:String in _hub().get("known_goods",[]):goods[good]=true
	for row:Array in order_rows:goods[str(row[1])]=true
	for operation:Dictionary in value.get("firm",{}).get("operations",[]):
		for good:String in operation.get("inventory",{}):goods[good]=true
	if selected_good!="all" and not goods.has(selected_good):selected_good="all"
	_goods_select.clear();_goods_select.add_item("全部商品");_goods_select.set_item_metadata(0,"all")
	for good:String in goods:
		_goods_select.add_item(EconomicText.good(good));_goods_select.set_item_metadata(_goods_select.item_count-1,good)
		if good==selected_good:_goods_select.select(_goods_select.item_count-1)

func clear_observation() -> void:
	hide();snapshot={};network={};contacts={};public_network={};selected_node="";catalog=null
	_details_collapsed=true;research_expanded=false
	_detail_toggle.text="展开详情";_research_toggle.text="展开研发细节"
	_menu_key.clear();_receipt_facts.clear();_page_offsets.clear();_flow_subject="";_flow_observer="";_flow_world_id=0
	_order_index.clear();_flow_scope.clear();_receipt_source_count=0;_receipt_truncated=false;_navigation_pending.clear()
	_cancel_pending.visible=false;_cancel_pending.disabled=true;_jobs.disabled=true;_personal_market.disabled=true
	selected_place="place:paris";selected_site="";selected_order="";selected_good="all"
	_managed_subject=false;_business.disabled=true
	_subjects.clear();_places.clear();_orders.clear();_goods_select.clear();_details.text=""
	_heading.text="";_page.text="";_business.tooltip_text=""
	var empty: Array[Dictionary] = []
	links_changed.emit(empty)

func select_place(id:String) -> void:
	selected_place=FormalEconomicMapObservation.canonical_place(id);selected_order="";selected_node="";selected_site=""
	_page_offsets.clear();_menu_key.clear()
	# The next demanded city read replaces the body; do not relabel old private
	# content as if it belonged to the newly selected city.

func _sync_site_selection() -> void:
	var owned:Array=network.get("nodes",{}).get(selected_place,{}).get("known_own_sites",[])
	var node:=_node(selected_node)
	if not node.is_empty() and str(node.get("place_id",""))==selected_place:
		selected_site=str(node.get("site_id",""))
	else:
		selected_node=""
		if selected_site not in owned:selected_site=str(owned[0]) if not owned.is_empty() else ""
	var personal:bool=snapshot.get("subject","")==snapshot.get("observer","") and not snapshot.get("firm",{}).is_empty()
	_business.text="岗位与个人订单" if personal else "经营所选站点"
	_business.disabled=not personal and (not _managed_subject or selected_site.is_empty() or selected_site not in owned)
	_business.tooltip_text="当前人物的原岗位页；地图浏览不移动人物或授予企业权限。" if personal else "只读观察；当前地点没有获准经营的本站点。" if _business.disabled else "原经营页 · "+selected_site
	for index:int in range(_places.item_count):
		var row:Dictionary=_places.get_item_metadata(index)
		if row.place_id==selected_place and ((not selected_node.is_empty() and str(row.get("node_id",""))==selected_node) or (selected_node.is_empty() and str(row.site_id)==selected_site)):_places.select(index);break

func follow_order(id:String, place_id:String, site_id:String) -> void:
	selected_place=FormalEconomicMapObservation.canonical_place(place_id)
	selected_site=site_id;selected_order=id;selected_node=""

func place_name(id:String) -> String:
	if catalog==null:return id
	var place:=catalog.get_place(id)
	return str(place.get("name_zh",place.get("name",id)))

func _node(id:String) -> Dictionary:
	if id.is_empty():return {}
	for node:Dictionary in public_network.get("nodes",[]):
		if str(node.get("id",""))==id:return node
	return {}

func _node_name(node:Dictionary) -> String:
	var label:=str(node.get("label",node.get("name","")))
	if not label.is_empty() and label!=str(node.get("id","")):return label
	var kind:=str(node.get("kind",""))
	if kind=="site":return EconomicText.site(str(node.get("site_id",node.get("id",""))))
	if kind=="firm":return EconomicText.firm(str(node.get("firm_id",node.get("id",""))))
	return place_name(str(node.get("place_id","")))

func _public_place_text() -> String:
	var rows:Array[String]=[]
	var count:=0
	for node:Dictionary in public_network.get("nodes",[]):
		if str(node.get("place_id",""))!=selected_place:continue
		if not selected_node.is_empty() and str(node.get("id",""))!=selected_node:continue
		var kind:=str(node.get("kind",""))
		if kind=="firm" and selected_node.is_empty():continue # Its identity is listed with the real site, not counted as another establishment.
		rows.append(EconomicText.node_kind(kind)+" · "+_node_name(node)+"\n身份 "+str(node.get("id","")))
		rows.append(EconomicText.identity(str(node.get("identity_basis",node.get("basis","")))))
		if kind=="site":rows.append("所属企业 "+EconomicText.firm(str(node.get("firm_id",""))))
		var source:=str(node.get("source_id",node.get("source","")))
		if not source.is_empty() and source!=str(node.get("id","")):rows.append("身份来源 "+source)
		count+=1
		if count>=12:rows.append("同地更多身份可在节点选择器查看。");break
	if rows.is_empty():rows.append("此地点当前没有收到或获准查看的企业身份；不推定企业不存在。")
	rows.append("公共企业身份不授予经营权；他企私账、库存、内部订单与未收到信息不显示。")
	var corridors:=0
	for edge:Dictionary in public_network.get("edges",[]):
		if str(edge.get("kind",""))!="transport" or selected_place not in [str(edge.get("from_place_id","")),str(edge.get("to_place_id",""))]:continue
		rows.append("已知通路：%s → %s\n%s · %s"%[place_name(str(edge.get("from_place_id",""))),place_name(str(edge.get("to_place_id",""))),str(edge.get("source_id",edge.get("id",""))),_route_status(edge)])
		var parameters:Array[String]=[]
		for pair:Array in [["capacity","配置运力"],["delay","时延（日）"],["freight_per_unit","单位运费"]]:
			if edge.has(pair[0]):parameters.append(str(pair[1])+" "+str(edge[pair[0]]))
		if not parameters.is_empty():rows.append(" · ".join(parameters)+"（已知配置，不是实际货量）")
		corridors+=1
		if corridors>=8:break
	return "\n".join(rows)

func _route_status(edge:Dictionary) -> String:
	if edge.get("available") is bool:return "已知当前开放；不代表有货/有订单" if bool(edge.available) else "已知当前受阻/关闭"
	if edge.get("closed") is bool:return "已知当前关闭" if bool(edge.closed) else "已知当前开放；不代表有货/有订单"
	return "已知可达联系；未据此推定当前畅通、余量或成交"

func _flow_scope_text() -> String:
	var date:Dictionary=_flow_scope.get("date",{})
	var observed:=int(_flow_scope.get("observed_minute",snapshot.get("minute",0)))
	var observed_time:="世界第%d分钟"%observed
	if not date.is_empty():observed_time="%04d-%02d-%02d %02d:%02d"%[int(date.get("year",1900)),int(date.get("month",1)),int(date.get("day",1)),int(date.get("hour",0)),int(date.get("minute",0))]
	var site:=str(_flow_scope.get("site_id",selected_site))
	var scope:="本人授权订单页" if str(snapshot.get("subject",""))==str(snapshot.get("observer","")) else EconomicText.site(site)+"授权订单页"
	var text:="观察于%s · %s\n每页至多%d单；不是全城或全市场总量。"%[observed_time,scope,int(_flow_scope.get("page_limit",snapshot.get("page_size",32)))]
	if _flow_scope.get("orders_truncated")==true:text+="还有后页；未显示的记录未计入摘要。"
	if _flow_scope.get("identity_truncated")==true:text+="本城身份/通路列表受显示预算截断。"
	text+="\n图上至多%d组联系，已聚合；未绘出不代表不存在。"%LINK_BUDGET
	return text

func _flow_quantities(values:Dictionary) -> String:
	var rows:Array[String]=[]
	var goods:Array=values.keys();goods.sort()
	for good:String in goods:rows.append("%s %s"%[EconomicText.good(good),str(values[good])])
	return "、".join(rows)+"（各按原商品单位）"

func _freight_summary() -> String:
	# Only already received page DTOs. No world query, clock or stock mutation.
	var orders:int=0;var pending:int=0;var transit:int=0
	var seen_shipments:Dictionary={};var stages:Dictionary={};var local_goods:Dictionary={}
	var local_records:int=0;var unknown_records:int=0
	for order:Dictionary in _order_index.values():
		var id:=str(order.get("id",""));var good:=str(order.get("good",""))
		if (not selected_order.is_empty() and id!=selected_order) or selected_good not in ["all",good]:continue
		orders+=1
		if order.get("pending") is int and int(order.pending)>0:pending+=1
		if order.get("transit") is int and int(order.transit)>0:transit+=1
		for shipment:Dictionary in order.get("shipments",[]):
			var sid:=str(shipment.get("id",""))
			if sid.is_empty() or seen_shipments.has(sid):continue
			seen_shipments[sid]=true
			var stage:=str(shipment.get("stage","UNKNOWN"))
			stages[stage]=int(stages.get(stage,0))+1
			var physical:Variant=shipment.get("physical_quantity")
			if physical is int and physical>=0 and stage!="TRANSIT":
				local_records+=1;local_goods[good]=int(local_goods.get(good,0))+int(physical)
			else:unknown_records+=1
	var rows:Array[String]=["本页货流 · 当前商品/订单筛选","合同责任：%d单，其中含待发%d单、在途责任%d单（可重叠；不是实物量）。"%[orders,pending,transit]]
	var state_rows:Array[String]=[]
	var stage_ids:Array=stages.keys();stage_ids.sort()
	for stage:String in stage_ids:
		var label:=EconomicText.cargo_stage(stage)
		if label==stage:label="未说明的分段状态"
		state_rows.append(label+" "+str(stages[stage])+"条")
	if not state_rows.is_empty():rows.append("分段状态记录："+"、".join(state_rows)+"。状态不提供货物实时定位。")
	if local_records>0:rows.append("可见本地实物记录%d条：%s。"%[local_records,_flow_quantities(local_goods)])
	else:rows.append("本页未见可核实的本地实物记录；不表示实物为零。")
	if unknown_records>0:rows.append("另%d条分段记录的实物量/当前位置未知，未用合同责任代替。"%unknown_records)
	var quantities:Dictionary={};var receipt_count:int=0;var same_place:int=0;var cross_place:int=0;var unknown_direction:int=0
	var now:=int(snapshot.get("minute",0))
	for receipt:Dictionary in _receipt_facts:
		if int(receipt.minute)>now or now-int(receipt.minute)>7*1440:continue
		if selected_good not in ["all",str(receipt.good)] or (not selected_order.is_empty() and str(receipt.order_id)!=selected_order):continue
		receipt_count+=1;quantities[str(receipt.good)]=int(quantities.get(str(receipt.good),0))+int(receipt.quantity)
		if str(receipt.from).is_empty() or str(receipt.to).is_empty():unknown_direction+=1
		elif str(receipt.from)==str(receipt.to):same_place+=1
		else:cross_place+=1
	rows.append("近7日所示交付回执%d条 · 同地点%d / 跨地点%d%s"%[receipt_count,same_place,cross_place," / 方向未知%d"%unknown_direction if unknown_direction>0 else ""])
	if not quantities.is_empty():rows.append("确认交付："+_flow_quantities(quantities)+"；不同商品不相加。")
	if _receipt_truncated:rows.append("收据已截断：本页全部商品有效回执%d条，仅保留最新%d条；本摘要/地图只汇总所保留记录。"%[_receipt_source_count,RECEIPT_BUDGET])
	else:rows.append("回执仅来自本页授权订单，最多保留%d条；未见不等于其他订单没有交付。"%RECEIPT_BUDGET)
	rows.append("通路仅表示已知联系；流动只表示交付历史方向，远程/TRANSIT实物与精确位置仍未知。")
	return "\n".join(rows)

func _production_goods(values:Dictionary,units:Dictionary) -> String:
	var rows:Array[String]=[]
	for good:String in values:
		if int(values[good])==0:continue
		var unit:=str(units.get(good,"单位未知"))
		rows.append("%s %s%s"%[GOODS.get(good,good),str(values[good]),{"development_kg":"开发千克","development_m":"开发米","development_piece":"开发件"}.get(unit,unit)])
	return "、".join(rows) if not rows.is_empty() else "0（已有视图）"

func _production_summary(value:Dictionary) -> String:
	if value.is_empty():return ""
	var rows:Array[String]=["获准生产 · "+EconomicText.site(selected_site)]
	var units:Dictionary=value.get("units",{}).get("goods",{})
	for activity:Dictionary in (value.get("activities",[]) as Array).slice(0,8):
		rows.append("计划/实际 %s/%s批 · 实际产出 %s"%[str(activity.get("planned_batches","未知")),str(activity.get("actual_batches","未知")),_production_goods(activity.get("actual_outputs",{}),units)])
		var utilization:Variant=activity.get("capacity_utilization")
		rows.append("劳动 %s人时 · 产能利用 %s"%[str(activity.get("allocated_person_hours","未知")),"%.1f%%"%(float(utilization)*100.0) if utilization is int or utilization is float else "未知"])
		var reasons:Array[String]=[]
		for code:String in activity.get("observed_constraints",[]):reasons.append(EconomicText.constraint(code))
		rows.append("约束："+("、".join(reasons) if not reasons.is_empty() else "本次观察未报告限制"))
	if (value.get("activities",[]) as Array).is_empty():rows.append("本站未声明生产活动；库存不是产量。")
	return "\n".join(rows)

func _production_text(value:Dictionary) -> String:
	if value.is_empty():return ""
	var units:Dictionary=value.get("units",{}).get("goods",{})
	var rows:Array[String]=["获准站点生产 · "+EconomicText.site(str(value.get("site_id",""))),"来源case "+str(value.get("configuration_source",{}).get("case_id","未知"))]
	for activity:Dictionary in (value.get("activities",[]) as Array).slice(0,8):
		var recipe:Dictionary=activity.get("recipe",{})
		var utilization:Variant=activity.get("capacity_utilization")
		rows.append("配方/批：%s → %s；每批%s人时/%s产能单位（日额度口径）"%[_production_goods(recipe.get("materials",{}),units),_production_goods(recipe.get("outputs",{}),units),str(recipe.get("hours","未知")),str(recipe.get("capacity_units","未知"))])
		rows.append("计划/实际批次 %s/%s · 累计%s\n实际投入 %s\n净输出 %s · 不可售reject %s"%[str(activity.get("planned_batches","未知")),str(activity.get("actual_batches","未知")),str(activity.get("cumulative_batches","未知")),_production_goods(activity.get("actual_inputs",{}),units),_production_goods(activity.get("actual_outputs",{}),units),_production_goods(activity.get("declared_non_saleable_rejects",{}),units)])
		rows.append("生产采用劳动 %s人时 · 占用/可用产能 %s/%s · 利用率 %s"%[str(activity.get("allocated_person_hours","未知")),str(activity.get("capacity_used_units","未知")),str(activity.get("capacity_available_units","未知")),"%.1f%%"%(float(utilization)*100.0) if utilization is float or utilization is int else "未知"])
		rows.append("工艺状态 %s · 观察到约束 %s"%[str(activity.get("process_status","未知")),str(activity.get("observed_constraints",[]))])
	if (value.get("activities",[]) as Array).is_empty():rows.append("本站没有已声明生产活动；不把贸易站库存当作产出。")
	for good:String in value.get("inventory_status",{}):
		if selected_good not in ["all",good]:continue
		var stock:Dictionary=value["inventory_status"][good]
		rows.append("%s：在库%s/预留%s · 在途合同责任入%s/出%s（%s）"%[GOODS.get(good,good),str(stock.get("at_site_quantity","未知")),str(stock.get("reserved_at_site_quantity","未知")),str(stock.get("incoming_order_transit_quantity","未知")),str(stock.get("outgoing_order_transit_quantity","未知")),str(units.get(good,"单位未知"))])
	rows.append("在途为已接受合同责任，不替代未确认的远程实货量；参数/配方按来源case，不是历史产能。")
	return "\n".join(rows)

func _player_situation_text() -> String:
	var person:Dictionary=snapshot.get("player_context",{})
	var current_place:=str(person.get("current_place_id",""))
	var location:=place_name(current_place) if not current_place.is_empty() else "未知"
	if person.get("present_at_recorded_place")==false:location="原人物记录为"+location+"，但按旅行规则当前不可确认为在场；不推定途中坐标。"
	var rows:Array[String]=["正在查看："+place_name(selected_place)+"；本人所在地："+location]
	if person.has("managed_firms_listed"):
		rows.append("本页已列示微观经营授权 %d 家；受雇/工资看原岗位页，浏览城市不会移动本人。"%int(person.managed_firms_listed))
	if person.has("available"):
		rows.append("本人可用 %s · 预留 %s %s"%[str(person.available),str(person.get("reserved","未知")),EconomicText.currency(str(person.get("denomination","")))])
	if person.has("inventory"):rows.append("本人当前可见本地持有："+_goods(person.get("inventory",{}))+"（不含未知远程实物）。")
	rows.append("可用上方‘本人岗位’或‘已知报价’行动；按本人原所在地与权限复核。")
	return "\n".join(rows)

func _business_situations_text() -> String:
	var rows:Array[String]=[]
	var subject:=str(snapshot.get("subject",""));var shown:int=0;var matched:int=0
	for situation:Dictionary in snapshot.get("city_business_situations",[]):
		if not subject.is_empty() and (str(situation.get("firm_id",""))!=subject or str(situation.get("site_id",""))!=selected_site):continue
		matched+=1
		if shown>=3:continue
		shown+=1
		rows.append(EconomicText.site(str(situation.get("site_id","")))+" · "+("经营中" if situation.get("operating")==true else "经营已停")+" / "+("生产开" if situation.get("production_enabled")==true else "生产停")+" / "+("接新业务" if situation.get("accepting_business")==true else "不接新业务"))
		var cash:Dictionary=situation.get("cash",{})
		for currency:String in cash:
			var account:Dictionary=cash[currency]
			rows.append("企业可用 %s · 预留 %s %s"%[str(account.get("available","未知")),str(account.get("reserved","未知")),EconomicText.currency(currency)])
		var activities:Array=situation.get("activities",[])
		var count:int=0
		for activity:Dictionary in activities:
			if count>=2:break
			count+=1
			var actual:Variant=activity.get("actual_batches")
			var batches:Variant=activity.get("material_batches_available")
			rows.append(EconomicText.activity(activity)+" · "+("活动开" if activity.get("enabled")==true else "活动停")+"；最近已结算 "+(str(actual)+" 批" if actual is int else "批次尚未知"))
			rows.append("当前原料支持 "+(str(batches)+" 批（不是保证产量）" if batches is int else "无原料投入项" if activity.has("material_batches_available") else "批次未知"))
			var material_count:int=0
			var materials:Array=activity.get("materials",[])
			for material:Dictionary in materials:
				if material_count>=4:break
				material_count+=1
				rows.append("  %s：每批%s · 本站可用%s · 合同供给%s"%[EconomicText.good(str(material.get("good",""))),str(material.get("per_batch","未知")),str(material.get("free","未知")),str(material.get("incoming","未知"))])
			if materials.size()>material_count:rows.append("  另 %d 项投入，原经营页可查；上方支持批次仍按原领域全部投入计算。"%(materials.size()-material_count))
			var constraints:Array[String]=[]
			for code:String in activity.get("next_batch_constraints",[]):constraints.append(EconomicText.constraint(code))
			rows.append("下一批限制："+("、".join(constraints) if not constraints.is_empty() else "当前未报告；劳动、时序等仍由原日结裁决。"))
		if activities.size()>2:rows.append("另有 %d 项生产活动，进入原经营页查看。"%(activities.size()-2))
		var automation:Dictionary=situation.get("automation",{})
		rows.append("按活动原料规则自动补货；没有独立自动采购开关。" if str(automation.get("mode",""))=="ACTIVITY_DRIVEN_INPUTS" else "本站按既有库存目标补货，不把贸易库存当产出。")
		rows.append("停产不取消原订单/工资；维护、服务投入仍按各自规则。合同供给不等于到货实物。")
	if matched>shown:rows.append("另有 %d 个本城获权站点，请在站点下拉选择查看。"%(matched-shown))
	if bool(snapshot.get("city_situations_truncated",false)) and (matched>0 or subject.is_empty()):rows.append("处境最多读本城 %d 个获权站点，身份页或处境已截断；未见不等于没有。"%int(snapshot.get("city_situation_limit",8)))
	return "\n".join(rows)

func _identity_notice_text() -> String:
	var producers:int=0
	for node:Dictionary in public_network.get("nodes",[]):
		if str(node.get("kind",""))=="local_producer" and str(node.get("place_id",""))==selected_place:producers+=1
	if producers==0:return ""
	return "本次已知身份页列示地方生产者 %d 个（公开/已知身份不是经营授权）。未提供原消息日期或家庭成交记录；页头是观察时刻，不能当成交新闻。私账与私有买卖仍不可见。"%producers

func _pending_preview() -> Dictionary:
	var preview:Dictionary=snapshot.get("pending_cancellation",{})
	if selected_order.is_empty() or str(preview.get("order_id",""))!=selected_order or not _order_index.has(selected_order):return {}
	if not preview.get("minute") is int or preview.get("minute")!=snapshot.get("minute"):return {}
	return preview

func _request_pending_cancellation() -> void:
	var preview:=_pending_preview()
	if preview.get("can_cancel_pending")==true:pending_cancellation_requested.emit(selected_order)

func _cancellation_text() -> String:
	var preview:=_pending_preview()
	_cancel_pending.visible=not selected_order.is_empty()
	_cancel_pending.disabled=preview.get("can_cancel_pending")!=true
	_cancel_pending.tooltip_text="仅提交取消本单未发部分；原领域执行时再次复核，已采用运输不能撤回。"
	if preview.is_empty():return "尚未取得当前订单的取消预览；未推算可释放金额。"
	var amount:Variant=preview.get("releasable_amount")
	var text:="合同未发 %s；取消预览释放 %s %s。"%[str(preview.get("quantity_pending","未知")),str(amount) if amount is int else "金额未知",EconomicText.currency(str(preview.get("denomination","")))]
	if preview.get("can_cancel_pending")!=true:text+="\n当前不可取消："+EconomicText.reason(str(preview.get("reason","")))
	return text+"\n只处理未发责任；在途、装卸和已交付不撤回。执行仍由原规则复核。"

func _order_waiting_text(order:Dictionary) -> String:
	var reasons:Dictionary={}
	var pending:=str(order.get("pending_waiting_reason",""))
	if not pending.is_empty():reasons[pending]=true
	for cargo:Dictionary in order.get("shipments",[]):
		for key:String in ["waiting_reason","arrival_blocked_reason"]:
			var code:=str(cargo.get(key,""))
			if not code.is_empty():reasons[code]=true
	var labels:Dictionary={"SHARED_RESOURCE_REQUIRES_EXPLICIT_BINDING":"尚无Shared资源的明确绑定","HOST_CONNECTION_UNAVAILABLE":"原订单所需宿主连接当前不可用","NOT_READY":"最早可发运时点尚未到","WAITING_EXPLICIT_HOST_ENTRY_WINDOW":"等待正式Shared入场窗口","SHARED_LINK_VEHICLE_OR_HANDLING_LIMIT":"当前车辆/装卸服务量不足","EDGE_CLOSED":"原订单报告路段当前关闭；重开时点未知","EDGE_CAPACITY":"本期路段剩余运力不足","NODE_CAPACITY":"本期节点承接量不足","QUEUED_NEXT_DISPATCH":"等待下一次正式调度","EXPLICIT_OWNER_COLLECTION_REQUIRED":"须本人按原规则到收货地正式领取","FUTURE_HOST_ENTRY_ALLOCATION_REQUIRED":"后续Shared服务尚待正式分配，不保证到达时点","BATCH_EXCEEDS_ACTIVE_CAPACITY":"现批次超过当前后续路段能力"}
	var rows:Array[String]=[]
	for code:String in reasons:
		var label:=str(labels[code]) if labels.has(code) else EconomicText.reason(code)
		rows.append(label if label!=code else "存在原订单已报告的等待条件，原运输页可查。")
	return "原订单报告的等待/后续条件："+"、".join(rows)+"（不据此推断货物精确位置）。" if not rows.is_empty() else ""

func _sales_text() -> String:
	var subject:=str(snapshot.get("subject",""));var observer:=str(snapshot.get("observer",""))
	if subject.is_empty() or subject==observer:return ""
	var delivered:Dictionary={}
	for receipt:Dictionary in _receipt_facts:
		var id:=str(receipt.get("order_id",""));var order:=_raw_order(id)
		if str(order.get("kind",""))!="SALE" or str(order.get("seller",""))!=subject or str(order.get("buyer","")) in [subject,observer]:continue
		if not selected_order.is_empty() and selected_order!=id:continue
		if selected_good not in ["all",str(receipt.get("good",""))]:continue
		delivered[id]=int(delivered.get(id,0))+int(receipt.get("quantity",0))
	var rows:Array[String]=[];var shown:int=0
	for id:String in delivered:
		if shown>=3:break
		shown+=1
		var order:=_raw_order(id);var buyer:=EconomicText.firm(str(order.get("buyer","")))
		if buyer=="企业（名称未记录）":buyer="其他已知买方"
		rows.append("%s购入 %s %s；实际交付 %s → %s。"%[buyer,str(delivered[id]),EconomicText.good(str(order.get("good",""))),place_name(str(order.get("from_place_id",""))),place_name(str(order.get("to_place_id","")))])
		if order.get("paid_goods_amount") is int:rows.append("该单累计已结货款 %s %s（非利润，非仅7日合计）。"%[str(order.paid_goods_amount),EconomicText.currency(str(order.get("denomination","")))])
	if rows.is_empty():return ""
	if delivered.size()>shown:rows.append("另 %d 单有交付，选择订单查看。"%(delivered.size()-shown))
	return "近7日本页对外销售的真实交付（非全城；不猜买方内部策略）\n"+"\n".join(rows)

func _detail() -> void:
	if _details==null or _details_collapsed:return
	_cancel_pending.visible=false;_cancel_pending.disabled=true
	var lines:Array[String]=[_player_situation_text()]
	var subject:=str(snapshot.get("subject",""));var hub:=_hub()
	var follow_notice:=str(snapshot.get("follow_notice",""))
	if not follow_notice.is_empty():lines.append(follow_notice)
	if subject.begins_with("aggregate:"):
		var totals:Dictionary=snapshot.get("macro",{}).get("daily_totals",{})
		lines.append("国家统计（非城市或企业库存）")
		if totals.has("fulfillment_bp") and float(totals.fulfillment_bp)>=0:lines.append("已结算满足率 %.1f%%"%(float(totals.fulfillment_bp)/100.0))
		else:lines.append("尚无可用的已结算统计。")
	elif not selected_order.is_empty():
		var order:=_raw_order(selected_order)
		lines.append(EconomicText.good(str(order.get("good","")))+" · "+_edge_status(network.get("edges",{}).get(selected_order,{})))
		lines.append("%s → %s\n待发%s · 在途责任%s · 确认交付%s"%[place_name(str(order.get("from_place_id",""))),place_name(str(order.get("to_place_id",""))),str(order.get("pending","未知")),str(order.get("transit","未知")),str(order.get("delivered","未知"))])
		lines.append(_cancellation_text())
		var waiting:=_order_waiting_text(order)
		if not waiting.is_empty():lines.append(waiting)
		lines.append("合同在途责任不等于已核实远程实货。精确位置未知。")
		var sales:=_sales_text()
		if not sales.is_empty():lines.append(sales)
		lines.append(_freight_summary())
		if research_expanded:lines.append(_flow_scope_text()+"\n"+str(order.get("id",""))+"\n"+_cargo_text(selected_order))
	elif subject.is_empty():
		var situations:=_business_situations_text()
		if not situations.is_empty():lines.append("本城获权站点处境\n"+situations)
		lines.append("在站点下拉选择本城有权设施，再用‘经营所选站点’进入原采购/生产页。未列示处境不表示不存在企业或库存为零。")
		lines.append("公开身份范围：已知主体 %s · 已知站点 %s"%[str(hub.get("known_subject_count","未知")),str(hub.get("known_site_count","未知"))])
		var goods:Array[String]=[]
		for good:String in hub.get("known_goods",[]):goods.append(EconomicText.good(good))
		if not goods.is_empty():lines.append("已知经营商品（不是当前成交/产量）："+"、".join(goods))
		lines.append("公开身份不是经营授权；未知的库存、利润与产能不推定为零。")
	else:
		var subject_name: String="已知主体"
		for choice:Dictionary in snapshot.get("subjects",[]):
			if str(choice.id)==subject:subject_name=str(choice.name);break
		lines.append(subject_name if subject!=snapshot.get("observer","") else "当前人物 · 本地财产与本人订单")
		var own:Dictionary=snapshot.get("firm",{})
		if own.is_empty():lines.append("仅收到公开身份；没有本站经营授权，私账/库存/内部订单不可见。")
		else:
			var situation:=_business_situations_text()
			if not situation.is_empty():lines.append(situation)
			elif own.has("cash") and subject!=snapshot.get("observer",""):lines.append("企业可用 %s · 预留 %s（原记账单位）"%[str(own.get("available","未知")),str(own.get("reserved","未知"))])
			var sales:=_sales_text()
			if not sales.is_empty():lines.append(sales)
			var production:Dictionary=snapshot.get("production_details",{}).get(selected_site,{})
			if not production.is_empty():
				if research_expanded:lines.append(_production_text(production))
				elif situation.is_empty():lines.append(_production_summary(production))
			for operation:Dictionary in own.get("operations",[]):
				if str(operation.get("site_id",""))!=selected_site:continue
				lines.append("本站在库："+_goods(operation.get("inventory",{}))+"\n可用："+_goods(operation.get("free_inventory",{}))+" · 已承诺："+_goods(operation.get("committed_inventory",{})))
			lines.append(_freight_summary())
			lines.append("本页授权订单 %d；报价/岗位/工资见原人物或经营页，不能推定别家私账。"%(network.get("edges",{}) as Dictionary).size())
			if research_expanded:lines.append(_flow_scope_text())
	var identity_notice:=_identity_notice_text()
	if not identity_notice.is_empty():lines.append(identity_notice)
	if research_expanded:lines.append(_public_place_text())
	lines.append("地图仅城市锚点。虚线为已知通路/合同责任；流动脉冲仅表示本页近7日已确认交付方向，不是实时货物坐标。")
	lines.append(str(snapshot.get("identity_notice","")))
	_details.text="\n\n".join(lines);_publish_links()

func _rebuild_order_index() -> void:
	_order_index.clear()
	var firm:Dictionary=snapshot.get("firm",{})
	for key:String in ["orders","sales_orders"]:
		for order:Dictionary in firm.get(key,[]):
			var id:=str(order.get("id",""))
			if not id.is_empty() and not _order_index.has(id):_order_index[id]=order

func _collect_receipts() -> void:
	_receipt_facts.clear();_receipt_source_count=0;_receipt_truncated=false
	var seen:Dictionary={}
	var now:=int(snapshot.get("minute",0))
	for order:Dictionary in _order_index.values():
		for receipt:Dictionary in order.get("deliveries",[]):
			var id:=str(receipt.get("id",""));var minute:Variant=receipt.get("delivered_minute");var quantity:Variant=receipt.get("quantity")
			if id.is_empty() or seen.has(id) or not minute is int or not quantity is int or quantity<=0:continue
			if minute>now or now-int(minute)>7*1440:continue
			seen[id]=true
			_receipt_facts.append({"id":id,"order_id":str(order.get("id","")),"from":str(order.get("from_place_id","")),"to":str(order.get("to_place_id","")),"good":str(order.get("good","")),"minute":minute,"quantity":quantity})
	_receipt_facts.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.minute)>int(b.minute) if int(a.minute)!=int(b.minute) else str(a.id)<str(b.id))
	_receipt_source_count=_receipt_facts.size();_receipt_truncated=_receipt_source_count>RECEIPT_BUDGET
	if _receipt_truncated:_receipt_facts.resize(RECEIPT_BUDGET)

func _add_link(rows:Array[Dictionary], row:Dictionary, budget:int) -> void:
	if str(row.get("from","")).is_empty() or str(row.get("to","")).is_empty():return
	for existing:Dictionary in rows:
		if [existing.from,existing.to,existing.kind,existing.get("good",""),existing.get("status","")]==[row.from,row.to,row.kind,row.get("good",""),row.get("status","")]:
			var known_quantity:Variant=existing.get("quantity");var incoming:Variant=row.get("quantity")
			if known_quantity is int and incoming is int:existing["quantity"]=int(known_quantity)+int(incoming)
			else:existing.erase("quantity") # Missing/unknown is not a physical zero.
			existing["source_count"]=int(existing.get("source_count",1))+int(row.get("source_count",1))
			if row.get("observed_minute") is int:existing["observed_minute"]=maxi(int(existing.get("observed_minute",row.observed_minute)),int(row.observed_minute))
			return
	if rows.size()<budget:
		row["source_count"]=int(row.get("source_count",1));rows.append(row)

func _publish_links() -> void:
	var rows:Array[Dictionary]=[]
	var activity_budget:=LINK_BUDGET-16 if show_routes else LINK_BUDGET
	var now:=int(snapshot.get("minute",0))
	if full:
		if show_receipts:
			for receipt:Dictionary in _receipt_facts:
				if int(receipt.minute)>now or now-int(receipt.minute)>7*1440:continue
				if selected_good not in ["all",str(receipt.good)] or (not selected_order.is_empty() and str(receipt.order_id)!=selected_order):continue
				_add_link(rows,{"id":str(receipt.id),"from":str(receipt.from),"to":str(receipt.to),"good":str(receipt.good),"kind":"receipt","status":"DELIVERED","state":"近7日已确认交付 · 非当前在途","directed":true,"quantity":receipt.quantity,"observed_minute":receipt.minute,"animate":true},activity_budget)
		# Local physical facts are never animated as a remote position.
		if bool(snapshot.get("details_loaded",false)):
			var seen_cargo:Dictionary={}
			for cargo:Dictionary in network.get("cargo",{}).values():
				var sid:=str(cargo.get("cargo_id",""));var physical:Variant=cargo.get("physical_quantity")
				if sid.is_empty() or seen_cargo.has(sid) or not physical is int or str(cargo.get("stage",""))=="TRANSIT":continue
				if selected_good not in ["all",str(cargo.good)] or int(physical)<=0:continue
				if not selected_order.is_empty() and str(cargo.order_id)!=selected_order:continue
				seen_cargo[sid]=true
				_add_link(rows,{"id":sid,"from":str(cargo.get("leg_from_node","")),"to":str(cargo.get("leg_to_node","")),"good":str(cargo.good),"kind":"cargo","status":str(cargo.stage),"state":"授权本地实物观察 · "+EconomicText.cargo_stage(str(cargo.stage))+"（段联系非位置）","directed":true,"quantity":physical,"animate":false},activity_budget)
		for edge:Dictionary in network.get("edges",{}).values():
			if selected_good not in ["all",str(edge.good)] or (not selected_order.is_empty() and str(edge.order_id)!=selected_order):continue
			_add_link(rows,{"id":str(edge.order_id),"from":str(edge.from_node),"to":str(edge.to_node),"good":str(edge.good),"kind":"contract","status":str(edge.get("status","UNKNOWN")),"state":"上次授权页观察到的合同责任（非实物） · "+_edge_status(edge),"directed":true,"animate":false},activity_budget)
		if show_routes:
			var corridor_count:=0
			for edge:Dictionary in public_network.get("edges",[]):
				if corridor_count>=16:break
				if str(edge.get("kind",""))!="transport" or str(edge.get("from_place_id",""))==str(edge.get("to_place_id","")):continue
				_add_link(rows,{"id":str(edge.get("id","")),"from":str(edge.get("from_place_id","")),"to":str(edge.get("to_place_id","")),"kind":"transport","status":"KNOWN_CORRIDOR_NOT_A_TRADE","state":_route_status(edge),"directed":true},LINK_BUDGET);corridor_count+=1
	links_changed.emit(rows)

func _edge_status(edge: Dictionary) -> String:
	var raw: Dictionary=_raw_order(str(edge.get("order_id","")))
	var stage:=str(edge.get("status",""))
	if stage in ["WAITING_TRANSFER","AWAITING_RECIPIENT"]:return EconomicText.cargo_stage(stage)
	if int(edge.get("transit_responsibility",0))>0:return "在途责任（实货见分段）"
	if int(edge.get("pending_responsibility",0))>0:return "已接受／待发"
	var loss: Variant=edge.get("known_unresolved_loss_quantity",raw.get("known_unresolved_loss_quantity"))
	if loss is int and loss>0:return "待处理损失"
	return "已到货／历史关系" if int(edge.get("delivered",0))>0 else "已关闭关系"

func _raw_order(id: String) -> Dictionary:
	return _order_index.get(id,{})

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
		rows.append("%s · %s %s · %s\n合同 %s → %s；已知地点 %s\n精确位置未知；不作实时移动"%[id,GOODS.get(cargo.good,cargo.good),cargo.physical_quantity,EconomicText.cargo_stage(str(cargo.stage)),place_name(cargo.from_node),place_name(cargo.to_node),place_name(cargo.place_id) if not str(cargo.place_id).is_empty() else "未知"])
		if not str(cargo.get("leg_from_node","")).is_empty():rows.append("当前/待行段 %s → %s\n当前边 %s · 下一边 %s"%[place_name(str(cargo.leg_from_node)),place_name(str(cargo.leg_to_node)),str(cargo.get("current_edge_id","")),str(cargo.get("next_edge_id",""))])
		if not str(cargo.get("waiting_reason","")).is_empty():rows.append("等待原因："+str(cargo.waiting_reason))
		if cargo.get("earliest_arrival_day")!=null:rows.append("最早到货下限：第%s天（非保证到达）"%str(int(cargo.earliest_arrival_day)+1))
		if not str(cargo.get("arrival_blocked_reason","")).is_empty():rows.append("阻塞："+str(cargo.arrival_blocked_reason))
	return "\n".join(rows) if not rows.is_empty() else "本页没有可见本地实货记录；远程/TRANSIT实物量与当前位置未知。"
