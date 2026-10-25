class_name MainShell
extends Control
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
signal action_requested(action: String)
signal refresh_requested
var PANEL_FILL: Color = InterfaceSettings.theme_parameters().panel as Color
var PANEL_BORDER: Color = InterfaceSettings.theme_parameters().brass as Color
var INK: Color = InterfaceSettings.theme_parameters().ink as Color
var _hud_style: Dictionary = InterfaceSettings.theme_parameters().hud as Dictionary
const SETTINGS = preload("res://scripts/presentation/ui/interface_settings.gd")
var current_page: String = "map"
var status_message: String = ""
var feedback_action: String = ""
var _messages_open: bool = false
var _messages: Array[Dictionary] = []
const MESSAGE_HISTORY_LIMIT: int = 64
const MESSAGE_DRAWER_WIDTH: float = 320.0
var _message_sequence: int = 0
var _message_list_dirty: bool = true
var _message_drawer: Control
var _message_handle: Control
var _message_scroll: ScrollContainer
var _message_rows: VBoxContainer
var _message_drawer_bounds := Rect2()
var _message_handle_bounds := Rect2()
var _drawer_tween: Tween
var _drawer_outside_press := Vector2(INF,INF)
var _notice_canvas: Control
var _notice_title: Label
var _notice_body: Label
var _notice_link: Button
var _notice_tween: Tween
var _notice_visible: bool = false
var _notice_bounds := Rect2()
var _system_open: bool = false
var _settings_open: bool = false
var _last_map_message: String = ""
var _preferences: Dictionary = {}
var _navigation_open: bool = false
var _context_open: bool = true
var _hover_action: String = ""
var _hover_tooltip: String = ""
var _tooltip_visible: bool = false
var _tooltip_timer: Timer
@onready var _hud_layout: Control = $HUDMargins/HUDLayout
var _map_modes_open: bool = false
var _slot_mode: String = ""
var _slots: Array[Dictionary] = []
var _confirmation: Dictionary = {}
var _saving: bool = false
var _slot_error: String = ""
var _hits: Array[Dictionary] = []
var _blocks: Array[Rect2] = []
var _history: Array[Dictionary] = []
var _quantity_input: SpinBox
var _quantity_used: bool = false
var _quantity_context: String = ""
var _quantity_scale: int = 1000
var _button_font := UIDrawing.create_font()
var _font: Font = preload("res://assets/fonts/map/EBGaramond-Medium.ttf")
var _text_fonts: Dictionary = {}
var _wrapped_text_cache: Dictionary = {}
var _instrument_item: RID
var _instrument_material: ShaderMaterial
var _instrument_rect := Rect2()
var _instrument_basis := Basis()
var _instrument_oriented: bool = false
var _clock_frame: Control
var _clock_values: Control
var _track_frame: Control
var _track_marker: Control
var _clock_rect := Rect2()
var _track_rect := Rect2()
var _clock_draw_state: Array = []
var _flag_canvas: TextureRect
var _person_canvas: Control
var _person_draw_state: Array = []
var _date: Dictionary = {}
var _content_errors: Array[String] = []
var _view_polity: Dictionary = {}
var _view_flag: Texture2D
var _controller: GlobeController
var _time: TimeControl
var person_page := PersonView.new()
var economy_page := EconomyPage.new()
var economic_map: FormalEconomyMapView
var economic_data_available: bool = false
var economic_hint_available: bool = false
var organization_page := OrganizationPage.new()
var world_page := WorldPage.new()

func _ready() -> void:
	_font = _font.duplicate() as FontFile
	(_font as FontFile).allow_system_fallback = false
	var text_font := preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf") as FontFile
	text_font.allow_system_fallback = false
	_font.fallbacks = [text_font]
	_quantity_input = SpinBox.new()
	_quantity_input.min_value = 0.001
	_quantity_input.max_value = float(FormalLedgerState.MAX_AMOUNT)/float(_quantity_scale)
	_quantity_input.step = 0.001
	_quantity_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_quantity_input.visible = false
	add_child(_quantity_input)
	_quantity_input.value_changed.connect(_on_quantity_changed)
	_quantity_input.get_line_edit().text_changed.connect(_on_quantity_text_changed)
	_quantity_input.theme = UIDrawing.shell_theme()
	_preferences = SETTINGS.load_preferences()
	SETTINGS.apply(_preferences)
	_tooltip_timer = Timer.new()
	_tooltip_timer.one_shot = true
	_tooltip_timer.wait_time = 1.7
	add_child(_tooltip_timer)
	_tooltip_timer.timeout.connect(func() -> void: _tooltip_visible = true; queue_redraw())
	PANEL_BORDER.a = 0.30
	_flag_canvas = TextureRect.new()
	_flag_canvas.name = "CountryFlag"
	_flag_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flag_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_flag_canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag_canvas.stretch_mode = TextureRect.STRETCH_SCALE
	_flag_canvas.visible = false
	add_child(_flag_canvas)
	_clock_frame = _hud_canvas("ClockFrame",_draw_clock_frame)
	_clock_values = _hud_canvas("ClockValues",_draw_clock_values)
	_track_frame = _hud_canvas("HistoryFrame",_draw_track_frame)
	_track_marker = _hud_canvas("HistoryTime",_draw_track_marker)
	_person_canvas = _hud_canvas("PortraitCameo",_draw_person_contents)
	_initialize_messages()
	economic_map = FormalEconomyMapView.new()
	economic_map.name = "EconomicMapObservation"
	add_child(economic_map)
	resized.connect(refresh)

func _hud_canvas(node_name: String, paint: Callable) -> Control:
	var canvas := Control.new()
	canvas.name = node_name
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(paint)
	add_child(canvas)
	return canvas

func _exit_tree() -> void:
	if _notice_tween!=null: _notice_tween.kill()
	if _drawer_tween!=null: _drawer_tween.kill()
	if _instrument_item.is_valid(): RenderingServer.free_rid(_instrument_item)

func _update_instrument(center: Vector2, radius: float) -> void:
	if not _instrument_item.is_valid():
		_instrument_material = ShaderMaterial.new()
		_instrument_material.shader = preload("res://shaders/presentation/ui/instrument_hemisphere.gdshader")
		_instrument_material.set_shader_parameter("land_mask",preload("res://assets/maps/instrument/land_coarse.png"))
		_instrument_item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_instrument_item,get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(_instrument_item,true)
		RenderingServer.canvas_item_set_material(_instrument_item,_instrument_material.get_rid())
	var rect := Rect2(center-Vector2(radius,radius),Vector2(radius*2.0,radius))
	if rect!=_instrument_rect:
		_instrument_rect = rect
		RenderingServer.canvas_item_clear(_instrument_item)
		RenderingServer.canvas_item_add_rect(_instrument_item,rect,Color.WHITE)
		_instrument_material.set_shader_parameter("instrument_center",center)
		_instrument_material.set_shader_parameter("instrument_radius",radius)
	var basis := _controller.observation_basis(size)
	if not _instrument_oriented or _instrument_basis.get_rotation_quaternion().angle_to(basis.get_rotation_quaternion())>=deg_to_rad(0.35):
		_instrument_basis = basis
		_instrument_oriented = true
		_instrument_material.set_shader_parameter("view_basis",basis)

func configure(content_errors: Array[String], controller: GlobeController, time: TimeControl) -> void:
	var changed_errors := content_errors!=_content_errors
	_content_errors = content_errors.duplicate()
	_controller = controller
	_time = time
	if not controller.view_changed.is_connected(queue_redraw): controller.view_changed.connect(queue_redraw)
	if changed_errors and not _content_errors.is_empty(): show_feedback("地图资料读取失败："+"; ".join(_content_errors),"","map","error")

func set_date(value: Dictionary) -> void:
	if _date==value: return
	_date = value.duplicate()
	refresh_clock()
	if _hover_action=="history:current":
		_hover_tooltip = "当前世界时间\n"+date_text()
		if _tooltip_visible: queue_redraw()

func refresh_clock() -> void:
	if _time==null or _clock_values==null: return
	var state: Array = [_date,_time.paused,_time.speed,_hover_action,_system_open,_settings_open]
	if state==_clock_draw_state: return
	_clock_draw_state = state.duplicate(true)
	_clock_values.queue_redraw()
	_track_marker.queue_redraw()

func set_view_polity(polity: Dictionary, flag: Texture2D) -> void:
	_view_polity = polity
	_view_flag = flag

func show_feedback(message: String, action: String = "", source: String = "system", level: String = "info", feedback_id: String = "") -> void:
	status_message = message
	feedback_action = action
	# Slot dialogs cover ordinary notices. Keep a failed read visible there.
	if level=="error" and not _slot_mode.is_empty(): _slot_error = message
	if message.is_empty():
		if _notice_tween!=null: _notice_tween.kill()
		_hide_notice()
		return
	# Re-delivery of an explicitly identified feedback can be ignored. Without
	# such a reference, two equal messages are still two real notifications.
	if not feedback_id.is_empty() and not _messages.is_empty():
		var previous := _messages.back() as Dictionary
		if str(previous.feedback_id)==feedback_id and str(previous.source)==source and str(previous.message)==message and str(previous.action)==action: return
	_message_sequence += 1
	_messages.append({"sequence":_message_sequence,"message":message,"action":action,"source":source,"level":level,"feedback_id":feedback_id,"received_at":date_text()})
	if _messages.size()>MESSAGE_HISTORY_LIMIT: _messages.pop_front()
	_message_list_dirty = true
	if _messages_open: _rebuild_message_rows()
	if _notice_canvas!=null: _present_notice()
	queue_redraw()

func show_map_feedback(message: String) -> void:
	if message==_last_map_message: return
	_last_map_message = message
	var level := "error" if "失败" in message or "无法" in message or "未安装" in message else "info"
	# Preparation/installation of the same map is a changing status, not a
	# stream of new events. Preserve errors and all domain notifications.
	if level!="error" and not _messages.is_empty() and str(_messages.back().source)=="map" and str(_messages.back().level)!="error":
		_messages.back()["message"] = message
		status_message = message
		_message_list_dirty = true
		if _messages_open: _rebuild_message_rows()
		_present_notice()
		return
	show_feedback(message,"","map",level,"map_status")

func refresh() -> void:
	refresh_requested.emit()
	queue_redraw()

func remember_page() -> void:
	var entry := {"page":current_page,"organization":organization_page.selected_id,
		"organization_scope":organization_page.own_only,"organization_country":organization_page.country_id,"organization_page":organization_page.page,
		"native_tab":person_page.native_tab,"selected_job":person_page.selected_job_id,"wage_page":person_page.native_wage_page,"person_section":person_page.section,"account_page":person_page.account_page,"inventory_page":person_page.inventory_page,"living_page":person_page.living_page,"holding":person_page.selected_commodity_id,"living_record":person_page.selected_record_id,
		"world_index":world_page.index_open,"world_category":world_page.index_category,
		"economy_polity":economy_page.polity_id,"economy_scope":economy_page.scope_label,"personal_market":economy_page.personal_market,"commodity_page":economy_page.commodity_page,"commodity":economy_page.selected_commodity_id,"seller_site":economy_page.selected_seller_site_id}
	if _history.is_empty() or _history.back()!=entry: _history.append(entry)
	if _history.size() > 24: _history.pop_front()

func set_page(page: String, remember: bool = true) -> void:
	if page not in ["person","economy","organization","map","world","administration"]: return
	if current_page != page and remember: remember_page()
	current_page = page
	_close_popups()
	action_requested.emit("page_changed")
	refresh()
	if _controller != null: _controller.appearance_changed.emit()

func go_back() -> void:
	if _history.is_empty():
		set_page("map",false)
		return
	var previous := _history.pop_back() as Dictionary
	current_page = str(previous.page)
	organization_page.selected_id = str(previous.organization)
	organization_page.own_only = bool(previous.organization_scope)
	organization_page.country_id = str(previous.get("organization_country",""))
	organization_page.page = int(previous.organization_page)
	person_page.section = str(previous.person_section)
	person_page.native_tab = str(previous.get("native_tab","jobs"))
	person_page.selected_job_id = str(previous.get("selected_job",""))
	person_page.native_wage_page = int(previous.get("wage_page",0))
	person_page.account_page = int(previous.account_page)
	person_page.inventory_page = int(previous.inventory_page)
	person_page.living_page = int(previous.living_page)
	person_page.selected_commodity_id = str(previous.holding)
	person_page.selected_record_id = str(previous.living_record)
	world_page.index_open = bool(previous.get("world_index",false))
	world_page.index_category = str(previous.get("world_category","home"))
	economy_page.polity_id = str(previous.economy_polity)
	economy_page.scope_label = str(previous.economy_scope)
	economy_page.personal_market = bool(previous.get("personal_market",false))
	economy_page.commodity_page = int(previous.commodity_page)
	economy_page.selected_commodity_id = str(previous.commodity)
	economy_page.selected_seller_site_id = str(previous.get("seller_site",""))
	_close_popups()
	action_requested.emit("page_changed")
	refresh()
	if _controller != null: _controller.appearance_changed.emit()

func _close_popups() -> void:
	_navigation_open = false
	_system_open = false
	_settings_open = false
	_map_modes_open = false
	_set_messages_open(false)

func map_selection_changed() -> void:
	_context_open = _controller!=null and (not _controller.selected_polity_id.is_empty() or not _controller.selected_place_id.is_empty())
	if not _context_open: world_page.clear_selection()
	world_page.index_open = false
	world_page.selected_admin_id = ""
	refresh()
	if _controller != null: _controller.appearance_changed.emit()

func _hud_bounds() -> Rect2:
	return Rect2(_hud_layout.get_global_rect().position-get_global_position(),_hud_layout.size)

func _left_width() -> float:
	return minf(280.0,_hud_bounds().size.x*0.29)

func _polity_rect() -> Rect2:
	return Rect2(_hud_bounds().position,Vector2(92,64))

func _person_rect() -> Rect2:
	var bounds := _hud_bounds()
	return Rect2(bounds.position.x,bounds.end.y-144,108,144)

func _time_rect() -> Rect2:
	var radius := minf(float(_hud_style.clock_radius),size.x*0.22)
	return Rect2(size.x-radius,0,radius,radius)

func _history_rect() -> Rect2:
	var left := _polity_rect().end.x+44.0
	var right := _time_rect().position.x-36.0
	var width := minf(560.0,right-left)
	return Rect2((left+right-width)*0.5,24,width,20)

func _message_drawer_rect() -> Rect2:
	var width := minf(MESSAGE_DRAWER_WIDTH,size.x*0.34)
	var top := _time_rect().end.y+20.0
	var bottom := size.y-120.0
	var height := minf(430.0,maxf(200.0,bottom-top))
	return Rect2(size.x-width,top+(bottom-top-height)*0.5,width,height)

func _message_handle_rect() -> Rect2:
	return Rect2(size.x-22.0,_message_drawer_rect().get_center().y-36.0,22.0,72.0)

func _notice_rect() -> Rect2:
	return Rect2(size.x-minf(300.0,size.x*0.34)-12.0,size.y-100.0,minf(300.0,size.x*0.34),88.0)

func _instrument_radius() -> float:
	return clampf(size.x*0.056,52.0,78.0)

func _dock_rect() -> Rect2:
	var radius := _instrument_radius()
	var padding := 24.0*radius/64.0
	return Rect2(size.x*0.5-radius-padding,size.y-radius-padding,(radius+padding)*2.0,radius+padding)

func _context_rect() -> Rect2:
	var bounds := _hud_bounds()
	return Rect2(bounds.position+Vector2(0,72),Vector2(_left_width(),minf(world_page.card_height(),_person_rect().position.y-bounds.position.y-84)))

func workspace_rect() -> Rect2:
	var bounds := _hud_bounds()
	# Keep existing pages clear of the quadrant and taller portrait at 960x640.
	var width := minf(900,bounds.size.x-_time_rect().size.x-12)
	var height := maxf(300,bounds.size.y-248)
	if current_page in ["person","economy"] and size.y>=700: height += 84
	if current_page=="organization":
		height = minf(height,340.0 if not organization_page.selected_id.is_empty() else 190.0+ceil(float(mini(9,organization_page.record_count()))/3.0)*66.0)
	elif current_page=="world" and world_page.index_open and world_page.index_category in ["home","help","layers"]:
		var pilot_layers := world_page.index_category=="layers" and not LocalSpatialLoader.internal_landmark_sources().is_empty()
		height = minf(height,360.0 if pilot_layers else 310.0)
	var right := minf(bounds.get_center().x+width*0.5,_time_rect().position.x-12)
	return Rect2(right-width,bounds.position.y+94,width,height)

func _map_menu_rect() -> Rect2:
	var height := 269.0+(104.0 if _controller.map_mode in ["economic","fulfillment","shortage"] else 0.0)
	var dock := _dock_rect()
	return Rect2(size.x*0.5-165,maxf(12.0,dock.position.y-height-10),330,height)

func _system_rect() -> Rect2:
	var time := _time_rect()
	var extent := Vector2(minf(280.0,size.x-24.0),332.0 if _settings_open else 252.0)
	return Rect2(Vector2(size.x-extent.x-12.0,clampf(time.end.y+10.0,12.0,maxf(12.0,size.y-extent.y-12.0))),extent)

func _country_menu_rect() -> Rect2:
	return Rect2(_polity_rect().position+Vector2(0,74),Vector2(_left_width(),200))

func _slot_rect() -> Rect2:
	return Rect2(size*0.5-Vector2(250,230),Vector2(500,460))

func _confirm_rect() -> Rect2:
	var height := 260.0 if not str(_confirmation.get("error","")).is_empty() else 208.0
	return Rect2(size*0.5-Vector2(220,height*0.5),Vector2(440,height))

func map_occlusions() -> Array[Rect2]:
	var result: Array[Rect2] = [_polity_rect(),_person_rect(),_time_rect(),_message_handle_rect(),_dock_rect()]
	if economic_map!=null: result.append_array(economic_map.occlusions())
	if _messages_open: result.append(Rect2(_message_drawer.position,_message_drawer.size))
	if _notice_visible and _notice_canvas.visible: result.append(_notice_rect())
	if not _confirmation.is_empty() or not _slot_mode.is_empty(): return [Rect2(Vector2.ZERO,size)]
	if current_page != "map": result.append(workspace_rect())
	elif world_page.has_selection() and _context_open: result.append(_context_rect())
	if _map_modes_open: result.append(_map_menu_rect())
	if _navigation_open: result.append(_country_menu_rect())
	if _system_open or _settings_open: result.append(_system_rect())
	return result

func _draw() -> void:
	_hits.clear()
	_blocks.clear()
	_quantity_used = false
	if _controller == null: return
	if current_page != "map":
		var rect := workspace_rect()
		block_panel(rect)
		match current_page:
			"person": person_page.draw(self,rect)
			"economy": economy_page.draw(self,rect)
			"organization": organization_page.draw(self,rect)
			"world":
				if world_page.index_open: world_page.draw_index(self,rect)
				else: world_page.draw_details(self,rect)
			"administration": world_page.draw_administration(self,rect)
		button(Rect2(rect.end.x-80,rect.position.y+12,64,26),"返回","back")
		if current_page in ["person","economy"]:
			button(Rect2(rect.end.x-178,rect.position.y+12,88,26),"返回地图","page:map",true,false,12)
	elif world_page.has_selection() and _context_open and not economic_map.visible:
		var rect := _context_rect()
		world_page.draw_card(self,rect)
		button(Rect2(rect.end.x-34,rect.position.y+8,24,24),"×","context:close")
	_draw_polity_hud()
	_draw_person_hud()
	_draw_time_bar()
	_draw_history_track()
	_draw_feedback()
	_draw_map_dock()
	if current_page=="map" and _controller.map_mode in ["fulfillment","shortage"]:
		label(Vector2(124,size.y-22),"国家商品统计 · 已结算资料；无资料地区保留地理底图" if economic_data_available else "国家商品统计 · 尚无当前国家日结资料；保留地理底图",12,INK)
	elif current_page=="map" and _controller.map_mode in ["political","geographic"] and _controller.economic_supplements_enabled and economic_hint_available:
		label(Vector2(124,size.y-38),"经济提示：青点·获准站点  金点·已知供货  蓝点·国家统计；点击地点查看",11,INK)
	if _navigation_open: _draw_navigation()
	if _map_modes_open: _draw_map_menus()
	if _settings_open: _draw_settings()
	elif _system_open: _draw_system_menu()
	if not _slot_mode.is_empty(): _draw_slots()
	if not _confirmation.is_empty(): _draw_confirmation()
	_quantity_input.visible = _quantity_used and _slot_mode.is_empty() and _confirmation.is_empty() and not _system_open and not _settings_open and not _navigation_open and not _map_modes_open
	_draw_tooltip()

func _draw_polity_hud() -> void:
	var rect := _polity_rect()
	_blocks.append(rect)
	_flag_canvas.visible = _view_flag!=null
	if _view_flag!=null:
		var texture_size := _view_flag.get_size()
		var flag_size := (texture_size*minf(76.0/texture_size.x,48.0/texture_size.y)).round()
		_flag_canvas.position = (rect.get_center()-flag_size*0.5).round()
		_flag_canvas.size = flag_size
		if _flag_canvas.texture!=_view_flag: _flag_canvas.texture = _view_flag
	_hits.append({"rect":rect,"action":"navigation","enabled":not _view_polity.is_empty(),"tooltip":str(_view_polity.get("name_zh","国家资料未记录"))+"\n国家资料 · 市场 · 行政 · 组织架构"})

func _draw_navigation() -> void:
	var rect := _country_menu_rect()
	block_panel(rect)
	label(rect.position+Vector2(12,25),str(_view_polity.get("name_zh","国家资料")),14,INK,rect.size.x-24)
	var items: Array[Dictionary] = [{"name":"国家资料","action":"encyclopedia:country:"+str(_view_polity.get("id",""))},{"name":"市场","action":"country:market"},{"name":"行政资料","action":"map:home_administration"},{"name":"组织架构","action":"country:organizations"}]
	for index: int in range(items.size()):
		button(Rect2(rect.position+Vector2(12,38+index*38),Vector2(rect.size.x-24,30)),str(items[index].name),str(items[index].action))

func _draw_person_hud() -> void:
	var rect := _person_rect()
	var portrait := Rect2(rect.position+Vector2(16,0),Vector2(76,112))
	var hover := _hover_action if _hover_action in ["page:person","person:accounts","person:organizations"] else ""
	var state: Array = [rect,hover,current_page=="person"]
	if state!=_person_draw_state:
		_person_draw_state = state
		_person_canvas.queue_redraw()
	_hits.append({"rect":portrait,"action":"page:person","enabled":true,"ellipse_center":portrait.get_center(),"ellipse_radii":portrait.size*0.5,"tooltip":"人物详情"})
	var actions: Array[Dictionary] = [{"kind":"details","action":"page:person","hint":"人物详情"},{"kind":"accounts","action":"person:accounts","hint":"财产与账务"},{"kind":"relations","action":"person:organizations","hint":"人物关系"}]
	var centers: Array[Vector2] = [Vector2(20,115),Vector2(54,130),Vector2(88,115)]
	for index: int in range(actions.size()):
		var item := actions[index]
		var center := rect.position+centers[index]
		_hits.append({"rect":Rect2(center-Vector2(14,14),Vector2(28,28)),"action":item.action,"enabled":true,"circle_center":center,"circle_radius":14.0,"tooltip":item.hint})

func _draw_person_contents() -> void:
	var rect := _person_rect()
	UIDrawing.portrait_cameo(_person_canvas,Rect2(rect.position+Vector2(16,0),Vector2(76,112)),_hud_style,_hover_action=="page:person" or current_page=="person")
	var actions: Array[Dictionary] = [{"kind":"details","action":"page:person"},{"kind":"accounts","action":"person:accounts"},{"kind":"relations","action":"person:organizations"}]
	var centers: Array[Vector2] = [Vector2(20,115),Vector2(54,130),Vector2(88,115)]
	# The three controls share the cameo's lower rim, outside the silhouette.
	var bridge := PackedVector2Array([rect.position+Vector2(20,115),rect.position+Vector2(31,103),rect.position+Vector2(54,111),rect.position+Vector2(77,103),rect.position+Vector2(88,115)])
	_person_canvas.draw_polyline(bridge,_hud_style.bronze as Color,2.0,true)
	for index: int in range(actions.size()):
		var item := actions[index]
		var center := rect.position+centers[index]
		UIDrawing.portrait_action(_person_canvas,center,_hud_style,str(item.kind),_hover_action==str(item.action))

func _time_buttons() -> Array[Dictionary]:
	var corner := Vector2(_time_rect().end.x,0)
	var items: Array[Dictionary] = [{"rect":Rect2(corner+Vector2(-99,58),Vector2(47,25)),"text":"继续" if _time.paused else "暂停","action":"time:pause","selected":_time.paused,"tooltip":"继续时间" if _time.paused else "暂停时间"},{"rect":Rect2(corner+Vector2(-47,58),Vector2(41,25)),"text":"菜单","action":"system","selected":_system_open or _settings_open,"tooltip":"系统菜单 · Esc"}]
	for index: int in range(3):
		var speed: int = [1,2,4][index]
		items.append({"rect":Rect2(corner+Vector2(-84+index*28,90),Vector2(26,24)),"text":str(speed)+"×","action":"time:"+str(speed),"selected":_time.speed==speed,"tooltip":"时间速度 "+str(speed)+" 倍"})
	return items

func _draw_time_bar() -> void:
	var rect := _time_rect()
	if rect!=_clock_rect:
		_clock_rect = rect
		_clock_frame.queue_redraw()
		_clock_draw_state.clear()
	var corner := Vector2(rect.end.x,0)
	_hits.append({"rect":rect,"action":"clock:face","enabled":false,"circle_center":corner,"circle_radius":rect.size.x})
	for item: Dictionary in _time_buttons():
		_hits.append({"rect":item.rect,"action":item.action,"enabled":true,"tooltip":item.tooltip})
	refresh_clock()

func _draw_clock_frame() -> void:
	if _clock_rect.size.x<=0: return
	UIDrawing.quarter_clock_frame(_clock_frame,Vector2(_clock_rect.end.x,0),_clock_rect.size.x,_hud_style)

func _draw_clock_values() -> void:
	if _time==null or _clock_rect.size.x<=0: return
	var corner := Vector2(_clock_rect.end.x,0)
	var minute := int(_date.get("hour",0))*60+int(_date.get("minute",0))
	UIDrawing.quarter_clock_indicator(_clock_values,corner,_clock_rect.size.x,_hud_style,minute,_time.paused)
	UIDrawing.label(_clock_values,_font,corner+Vector2(-112,12),"CHRONOMÈTRE",8,_hud_style.muted as Color,116)
	var day := "日期读取中" if _date.is_empty() else "%04d年%02d月%02d日" % [int(_date.year),int(_date.month),int(_date.day)]
	UIDrawing.label(_clock_values,_font,corner+Vector2(-116,29),day,12,_hud_style.ivory as Color,112)
	var hour := "—" if _date.is_empty() else "%02d:%02d" % [int(_date.hour),int(_date.get("minute",0))]
	UIDrawing.label(_clock_values,_font,corner+Vector2(-80,54),hour,20,_hud_style.ivory as Color,75)
	_clock_values.draw_circle(corner+Vector2(-101,47),2,_hud_style.status as Color if _time.paused else _hud_style.teal as Color)
	for item: Dictionary in _time_buttons():
		var rect := item.rect as Rect2
		UIDrawing.instrument_button(_clock_values,rect,_hud_style,_hover_action==str(item.action),bool(item.selected))
		var text := str(item.text)
		var width := _button_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		UIDrawing.label(_clock_values,_button_font,rect.position+Vector2((rect.size.x-width)*0.5,rect.size.y*0.5+4),text,11,_hud_style.ivory as Color,rect.size.x-6)

func _draw_history_track() -> void:
	var rect := _history_rect()
	if rect!=_track_rect:
		_track_rect = rect
		_track_frame.queue_redraw()
		_track_marker.queue_redraw()
	var anchor := Vector2(rect.end.x,rect.position.y)
	_hits.append({"rect":Rect2(anchor-Vector2(10,10),Vector2(20,25)),"action":"history:current","enabled":false,"tooltip":"当前世界时间\n"+date_text()})

func _draw_track_frame() -> void:
	if _track_rect.size.x<=0: return
	UIDrawing.history_track_frame(_track_frame,_track_rect,_hud_style)
	UIDrawing.label(_track_frame,_font,Vector2(_track_rect.get_center().x-26,_track_rect.position.y-7),"HISTOIRE",9,_hud_style.muted as Color,70)

func _draw_track_marker() -> void:
	if _track_rect.size.x<=0: return
	UIDrawing.history_track_indicator(_track_marker,_track_rect,_hud_style,int(_date.get("hour",0))*60+int(_date.get("minute",0)))

func _draw_feedback() -> void:
	_sync_message_layout()
	var modal := not _confirmation.is_empty() or not _slot_mode.is_empty() or _system_open or _settings_open or _navigation_open or _map_modes_open
	_message_handle.visible = not modal
	_message_drawer.visible = _messages_open and not modal
	_notice_canvas.visible = _notice_visible and not modal
	if modal: return
	_hits.append({"rect":_message_handle_rect(),"action":"messages:toggle","enabled":true,"tooltip":"消息记录"})
	if _messages_open: _blocks.append(Rect2(_message_drawer.position,_message_drawer.size))
	if _notice_visible and _notice_link.visible: _blocks.append(_notice_rect())
	var handle_hover := _hover_action=="messages:toggle"
	if _message_handle.get_meta("hovered",false)!=handle_hover:
		_message_handle.set_meta("hovered",handle_hover)
		_message_handle.queue_redraw()

func _initialize_messages() -> void:
	_message_drawer = Control.new()
	_message_drawer.name = "MessageArchive"
	_message_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_message_drawer.clip_contents = true
	_message_drawer.theme = UIDrawing.shell_theme()
	_message_drawer.visible = false
	_message_drawer.draw.connect(func() -> void: UIDrawing.archive_drawer(_message_drawer,Rect2(Vector2.ZERO,_message_drawer.size),_hud_style))
	add_child(_message_drawer)
	var margin := MarginContainer.new()
	_message_drawer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	for side: String in ["left","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	margin.add_theme_constant_override("margin_right",36)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",9)
	margin.add_child(column)
	column.add_child(_message_label("ARCHIVES · 消息记录",14,_hud_style.ivory))
	column.add_child(_message_label("当前会话 · 最近记录",10,_hud_style.muted))
	_message_scroll = ScrollContainer.new()
	_message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_message_scroll)
	_message_rows = VBoxContainer.new()
	_message_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_rows.add_theme_constant_override("separation",13)
	_message_scroll.add_child(_message_rows)
	column.add_child(_message_button("百科 / 帮助","encyclopedia"))
	_message_handle = _hud_canvas("MessageArchiveHandle",func() -> void: UIDrawing.archive_handle(_message_handle,Rect2(Vector2.ZERO,_message_handle.size),_hud_style,_messages_open,bool(_message_handle.get_meta("hovered",false))))
	_notice_canvas = Control.new()
	_notice_canvas.name = "ImmediateNotice"
	_notice_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_notice_canvas.clip_contents = true
	_notice_canvas.visible = false
	_notice_canvas.draw.connect(func() -> void: UIDrawing.archive_notice(_notice_canvas,Rect2(Vector2.ZERO,_notice_canvas.size),_hud_style,not _messages.is_empty() and str(_messages.back().level)=="error"))
	add_child(_notice_canvas)
	_notice_title = _message_label("",10,_hud_style.muted)
	_notice_body = _message_label("",12,_hud_style.ivory)
	_notice_canvas.add_child(_notice_title)
	_notice_canvas.add_child(_notice_body)
	_notice_body.max_lines_visible = 2
	_notice_link = _message_button("查看","")
	_notice_link.pressed.connect(func() -> void:
		if not _messages.is_empty() and not str(_messages.back().action).is_empty(): _activate(str(_messages.back().action)))
	_notice_canvas.add_child(_notice_link)
	_sync_message_layout()
	if not _messages.is_empty(): _present_notice()

func _message_label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_override("font",_font)
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	return result

func _message_button(text: String, action: String) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 26
	result.add_theme_font_override("font",_button_font)
	result.add_theme_font_size_override("font_size",11)
	result.add_theme_color_override("font_color",_hud_style.ivory)
	var normal := StyleBoxFlat.new()
	normal.bg_color = _hud_style.seam
	normal.border_color = (_hud_style.metal as Color)*Color(1,1,1,0.35)
	normal.border_width_bottom = 1
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	result.add_theme_stylebox_override("normal",normal)
	var hovered := normal.duplicate() as StyleBoxFlat
	hovered.bg_color = Color(0.07,0.12,0.14,0.97)
	result.add_theme_stylebox_override("hover",hovered)
	result.add_theme_stylebox_override("pressed",hovered)
	if not action.is_empty(): result.pressed.connect(_activate.bind(action))
	return result

func _sync_message_layout() -> void:
	var drawer := _message_drawer_rect()
	if drawer!=_message_drawer_bounds:
		if _drawer_tween!=null: _drawer_tween.kill()
		_message_drawer_bounds = drawer
		_message_drawer.position = drawer.position
		_message_drawer.size = drawer.size
		_message_drawer.queue_redraw()
	var handle := _message_handle_rect()
	if handle!=_message_handle_bounds:
		_message_handle_bounds = handle
		_message_handle.position = handle.position
		_message_handle.size = handle.size
		_message_handle.queue_redraw()
	var notice := _notice_rect()
	if notice!=_notice_bounds:
		_notice_bounds = notice
		_notice_canvas.position = notice.position
		_notice_canvas.size = notice.size
		_notice_title.position = Vector2(16,9)
		_notice_title.size = Vector2(notice.size.x-32,16)
		_notice_body.position = Vector2(16,30)
		_notice_body.size = Vector2(notice.size.x-32,36)
		_notice_link.position = Vector2(notice.size.x-62,notice.size.y-27)
		_notice_link.size = Vector2(48,24)
		_notice_canvas.queue_redraw()

func _set_messages_open(value: bool) -> void:
	var changed := value!=_messages_open
	_messages_open = value
	if _message_drawer==null: return
	if not changed: return
	_drawer_outside_press = Vector2(INF,INF)
	if _drawer_tween!=null: _drawer_tween.kill()
	_message_drawer.visible = value
	if value and _message_list_dirty: _rebuild_message_rows()
	if value:
		_message_drawer.position.x = size.x
		_drawer_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
		_drawer_tween.tween_property(_message_drawer,"position:x",_message_drawer_rect().position.x,0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_drawer_tween.tween_callback(queue_redraw)
	_message_handle.queue_redraw()
	queue_redraw()

func _native_feedback_at(point: Vector2) -> bool:
	return (_message_drawer.visible and Rect2(_message_drawer.position,_message_drawer.size).has_point(point) and not _message_handle_rect().has_point(point)) or (_notice_canvas.visible and _notice_link.visible and _notice_rect().has_point(point))

func _message_source_name(source: String) -> String:
	return str({"system":"系统反馈","map":"地图反馈","domain":"状态提示"}.get(source,"操作反馈"))

func _rebuild_message_rows() -> void:
	if _message_rows==null: return
	var previous_scroll := _message_scroll.scroll_vertical
	for child: Node in _message_rows.get_children():
		_message_rows.remove_child(child)
		child.queue_free()
	if _messages.is_empty(): _message_rows.add_child(_message_label("暂无消息。",12,_hud_style.muted))
	for index: int in range(_messages.size()-1,-1,-1):
		var record := _messages[index]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation",5)
		_message_rows.add_child(row)
		row.add_child(_message_label(_message_source_name(str(record.source))+" · 接收于 "+str(record.received_at),10,_hud_style.muted))
		row.add_child(_message_label(str(record.message),12,_hud_style.ivory))
		if not str(record.action).is_empty(): row.add_child(_message_button("查看",str(record.action)))
		var separator := HSeparator.new()
		separator.modulate = Color(0.58,0.47,0.29,0.28)
		row.add_child(separator)
	_message_scroll.set_deferred("scroll_vertical",previous_scroll)
	_message_list_dirty = false

func _present_notice() -> void:
	if _notice_tween!=null: _notice_tween.kill()
	var record := _messages.back() as Dictionary
	_notice_title.text = _message_source_name(str(record.source))
	_notice_body.text = str(record.message)
	_notice_canvas.tooltip_text = str(record.message)
	_notice_link.visible = not str(record.action).is_empty()
	_notice_canvas.mouse_filter = Control.MOUSE_FILTER_STOP if _notice_link.visible else Control.MOUSE_FILTER_IGNORE
	_notice_body.size.y = 29.0 if _notice_link.visible else 46.0
	_notice_visible = true
	_notice_canvas.visible = true
	_notice_canvas.modulate.a = 0.0
	_notice_canvas.queue_redraw()
	# Visual time is independent of GameClock and continues while it is paused.
	_notice_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_notice_tween.tween_property(_notice_canvas,"modulate:a",1.0,0.2).set_trans(Tween.TRANS_SINE)
	_notice_tween.tween_interval(2.5 if str(record.source)=="map" and str(record.level)!="error" else 6.0)
	_notice_tween.tween_property(_notice_canvas,"modulate:a",0.0,0.8).set_trans(Tween.TRANS_SINE)
	_notice_tween.tween_callback(_hide_notice)

func _hide_notice() -> void:
	_notice_visible = false
	if _notice_canvas!=null: _notice_canvas.visible = false
	queue_redraw()

func _draw_map_dock() -> void:
	var rect := _dock_rect()
	_blocks.append(rect)
	var radius := _instrument_radius()
	var center := Vector2(size.x*0.5,size.y)
	var glow := 0.0 if _controller.region_camera.active else 1.0-smoothstep(1.0,2.8,_controller.zoom)
	_update_instrument(center,radius)
	UIDrawing.nautical_globe(self,center,radius,glow)
	_hits.append({"rect":rect,"action":"map:mode_menu","enabled":true,"hemisphere_center":center,"hemisphere_radius":rect.size.x*0.5})

func _draw_map_menus() -> void:
	var rect := _map_menu_rect()
	block_panel(rect)
	label(rect.position+Vector2(12,24),"地图模式",15,INK)
	var y := rect.position.y+38
	button(Rect2(rect.position.x+12,y,rect.size.x-24,27),"地理地图","map_mode:geographic",true,_controller.map_mode=="geographic")
	y += 32
	button(Rect2(rect.position.x+12,y,rect.size.x-24,27),"政治地图","map_mode:political",true,_controller.administrative_map_active())
	y += 32
	var economic := _controller.map_mode in ["economic","fulfillment","shortage"]
	button(Rect2(rect.position.x+12,y,rect.size.x-24,27),"经济地图","map:economy_mode",true,_controller.map_mode=="economic")
	y += 32
	if economic:
		button(Rect2(rect.position.x+28,y,rect.size.x-40,26),"商品供应满足率","map_mode:fulfillment",true,_controller.map_mode=="fulfillment")
		button(Rect2(rect.position.x+28,y+30,rect.size.x-40,26),"商品供应缺口","map_mode:shortage",true,_controller.map_mode=="shortage")
		label(Vector2(rect.position.x+28,y+76),"国家统计范围 · 无资料不着色",10,INK)
		label(Vector2(rect.position.x+28,y+94),"满足率：棕→绿；缺口：绿→红",10,INK)
		y += 104
	button(Rect2(rect.position.x+12,y,rect.size.x-24,27),"经济补充提示 · "+("开启" if _controller.economic_supplements_enabled else "关闭"),"map:economic_supplements",true,_controller.economic_supplements_enabled)
	y += 32
	for text: String in ["人口地图 · 不可用","军事地图 · 不可用","资源与产出地图 · 不可用"]:
		button(Rect2(rect.position.x+12,y,rect.size.x-24,23),text,"",false)
		y += 26

func _draw_system_menu() -> void:
	var rect := _system_rect()
	block_panel(rect)
	label(rect.position+Vector2(12,25),"系统菜单",15,INK)
	var items: Array[Dictionary] = [{"name":"保存","action":"save"},{"name":"加载","action":"load"},{"name":"设置","action":"settings:open"},{"name":"返回主菜单","action":"system:main_menu"},{"name":"退出","action":"system:quit"}]
	for index: int in range(items.size()):
		button(Rect2(rect.position+Vector2(12,40+index*39),Vector2(rect.size.x-24,30)),str(items[index].name),str(items[index].action))

func _draw_settings() -> void:
	var rect := _system_rect()
	block_panel(rect)
	label(rect.position+Vector2(12,27),"设置",15,INK)
	label(rect.position+Vector2(12,61),"主音量 · %d%%" % int(round(float(_preferences.volume)*100)),13,INK)
	var volume_width := (rect.size.x-36.0)*0.5
	button(Rect2(rect.position+Vector2(12,73),Vector2(volume_width,28)),"− 10%","settings:quieter")
	button(Rect2(rect.position+Vector2(24+volume_width,73),Vector2(volume_width,28)),"＋ 10%","settings:louder")
	if AudioServer.get_bus_index("BGM")>=0:
		button(Rect2(rect.position+Vector2(12,112),Vector2(rect.size.x-24,29)),"BGM · "+("开启" if bool(_preferences.bgm) else "关闭"),"settings:bgm",true,bool(_preferences.bgm))
	button(Rect2(rect.position+Vector2(12,154),Vector2(rect.size.x-24,29)),"全屏" if bool(_preferences.fullscreen) else "窗口","settings:fullscreen")
	button(Rect2(rect.position+Vector2(12,196),Vector2(rect.size.x-24,28)),"地图名称 · "+("开启" if _controller.labels_enabled else "关闭"),"settings:labels")
	button(Rect2(rect.position+Vector2(12,232),Vector2(rect.size.x-24,25)),"活动刷新 · %d FPS" % int(_preferences.get("active_fps",60)),"settings:fps")
	button(Rect2(rect.position+Vector2(12,261),Vector2(rect.size.x-24,25)),"菜单空闲省电 · "+("开启" if bool(_preferences.get("idle_power",true)) else "关闭"),"settings:idle_power")
	button(Rect2(rect.position+Vector2(12,290),Vector2(rect.size.x-24,29)),"返回","settings:back")

func open_slots(mode: String) -> void:
	_close_popups()
	_slot_mode = mode
	_slot_error = ""
	_slots = FormalPersistence.slot_summaries()
	queue_redraw()
	_controller.suspend_motion()
	_controller.appearance_changed.emit()

func close_slots() -> void:
	_slot_mode = ""
	_confirmation = {}
	queue_redraw()
	_controller.appearance_changed.emit()

func show_departure(target: String) -> void:
	_confirmation = {"kind":"departure","target":target,"title":"保存当前游戏？"}
	_close_popups()
	queue_redraw()
	_controller.appearance_changed.emit()

func close_confirmation() -> void:
	_confirmation = {}
	queue_redraw()
	_controller.appearance_changed.emit()

func _draw_slots() -> void:
	_quantity_used = false
	_hits.clear()
	_blocks = [Rect2(Vector2.ZERO,size)]
	draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,0.48))
	var rect := _slot_rect()
	block_panel(rect)
	label(rect.position+Vector2(20,32),"保存" if _slot_mode=="save" else "加载",23,INK)
	if not _slot_error.is_empty(): wrapped(rect.position+Vector2(90,28),_slot_error,rect.size.x-115,10,1)
	var y := rect.position.y+58
	for row: Dictionary in _slots:
		if _slot_mode=="save" and int(row.slot)==0: continue
		button(Rect2(rect.position.x+20,y,rect.size.x-104,36),str(row.name),"slot:choose:"+str(row.slot),not _saving and (_slot_mode=="save" or not bool(row.empty)))
		button(Rect2(rect.end.x-76,y,56,36),"资料","slot:info:"+str(row.slot),not _saving and not bool(row.empty))
		label(Vector2(rect.position.x+26,y+55),FormalPersistence.summary_text(row),11,INK,rect.size.x-52)
		y += 70
	button(Rect2(rect.end.x-84,rect.end.y-39,64,26),"返回","slots:close",not _saving)

func _show_slot_info(row: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = str(row.name)+" · 存档资料"
	dialog.dialog_text = FormalPersistence.details_text(row)
	dialog.dialog_autowrap = true
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(620,int(size.x)-40),mini(440,int(size.y)-40)))

func _draw_confirmation() -> void:
	_quantity_used = false
	_hits.clear()
	_blocks = [Rect2(Vector2.ZERO,size)]
	draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,0.48))
	var rect := _confirm_rect()
	block_panel(rect)
	label(rect.position+Vector2(20,37),str(_confirmation.title),21,INK)
	var offset := 0.0
	if not str(_confirmation.get("error","")).is_empty():
		wrapped(rect.position+Vector2(20,61),str(_confirmation.error),rect.size.x-40,11,2)
		offset = 52.0
	if str(_confirmation.kind)=="employment":
		wrapped(rect.position+Vector2(20,66),str(_confirmation.get("body","")),rect.size.x-40,13,3)
		button(Rect2(rect.position+Vector2(20,126),Vector2(rect.size.x-40,30)),"确认提交","confirm:employment",true,false,13)
		button(Rect2(rect.position+Vector2(20,168),Vector2(rect.size.x-40,28)),"取消","confirm:cancel",true,false,13)
		return
	var departure := str(_confirmation.kind)=="departure"
	var verb := "返回" if str(_confirmation.get("target",""))=="menu" else "退出"
	button(Rect2(rect.position+Vector2(20,66+offset),Vector2(rect.size.x-40,30)),("保存并"+verb) if departure else ("覆盖"+str(_confirmation.get("slot_name",""))),("departure:save" if departure else "slot:save:"+str(_confirmation.slot)),not _saving)
	if departure: button(Rect2(rect.position+Vector2(20,108+offset),Vector2(rect.size.x-40,30)),"不保存并"+verb,"departure:discard",not _saving)
	button(Rect2(rect.position+Vector2(20,160+offset),Vector2(rect.size.x-40,28)),"取消","confirm:cancel",not _saving)

func _draw_tooltip() -> void:
	if not _tooltip_visible: return
	for hit: Dictionary in _hits:
		if str(hit.action)==_hover_action and hit.has("tooltip"):
			_hover_tooltip = str(hit.tooltip)
			break
	var text := _hover_tooltip if not _hover_tooltip.is_empty() else str({"save":"F5","load":"F9","back":"Backspace · 返回；Esc · 关闭","system":"Esc","context:close":"Esc","map:mode_menu":"地图模式"}.get(_hover_action,""))
	if text.is_empty(): return
	var lines := text.split("\n")
	var width := 180.0
	for line: String in lines:
		var font := GlobeLabels.font_for_name(_font,line)
		width = maxf(width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+20)
	width = minf(width,size.x-24)
	var height := 12.0+float(lines.size())*20.0
	var pos := get_local_mouse_position()+Vector2(12,16)
	pos.x = clampf(pos.x,12,size.x-width-12)
	pos.y = clampf(pos.y,12,size.y-height-12)
	var rect := Rect2(pos,Vector2(width,height))
	panel(rect,PANEL_FILL,PANEL_BORDER)
	for index: int in range(lines.size()):
		label(pos+Vector2(10,22+index*20),lines[index],11,INK,width-20)

func _back_layer(open_system: bool = true) -> bool:
	if not _confirmation.is_empty():
		if _saving: return true
		_confirmation = {}
		action_requested.emit("departure:cancel")
	elif not _slot_mode.is_empty():
		if _saving: return true
		_slot_mode = ""
	elif _settings_open:
		_settings_open = false
		_system_open = true
	elif _system_open: _system_open = false
	elif _map_modes_open: _map_modes_open = false
	elif _navigation_open: _navigation_open = false
	elif _messages_open:
		_set_messages_open(false)
		return true
	elif current_page=="person" and not person_page.selected_record_id.is_empty():
		if not _history.is_empty(): go_back()
		else: person_page.selected_record_id = ""
	elif current_page=="person" and not person_page.selected_commodity_id.is_empty():
		if not _history.is_empty(): go_back()
		else: person_page.selected_commodity_id = ""
	elif current_page=="organization" and not organization_page.selected_id.is_empty():
		if not _history.is_empty() and str((_history.back() as Dictionary).get("page",""))=="organization": go_back()
		else: organization_page.selected_id = ""
	elif current_page=="economy" and economy_page.show_native_statistics:
		economy_page.show_native_statistics = false
	elif current_page=="economy" and not economy_page.selected_commodity_id.is_empty():
		economy_page.selected_commodity_id = ""
	elif current_page=="administration" and not world_page.selected_admin_id.is_empty():
		action_requested.emit("admin:list")
	elif current_page=="world" and world_page.index_open and world_page.index_category!="home":
		world_page.index_category = "home"
	elif economic_map!=null and economic_map.visible:
		economic_map.back_requested.emit()
	elif current_page!="map": go_back()
	elif world_page.has_selection() and _context_open: _context_open = false
	elif open_system: _system_open = true
	else: return false
	refresh()
	_controller.appearance_changed.emit()
	return true

func _input(event: InputEvent) -> void:
	if _controller == null: return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index==MOUSE_BUTTON_LEFT and not mouse.pressed and is_finite(_drawer_outside_press.x):
			var click := mouse.position.distance_to(_drawer_outside_press)<=6.0
			_drawer_outside_press = Vector2(INF,INF)
			_set_messages_open(false)
			if click:
				_controller.suspend_motion()
				get_viewport().set_input_as_handled()
				return
		if mouse.button_index==MOUSE_BUTTON_LEFT and mouse.pressed:
			var popup := _country_menu_rect() if _navigation_open else _map_menu_rect() if _map_modes_open else _system_rect()
			if (_navigation_open or _map_modes_open or _system_open or _settings_open) and _slot_mode.is_empty() and _confirmation.is_empty() and not popup.has_point(mouse.position):
				_close_popups()
				queue_redraw()
				_controller.appearance_changed.emit()
				get_viewport().set_input_as_handled()
				return
			if _messages_open and not _native_feedback_at(mouse.position) and not _message_handle_rect().has_point(mouse.position) and not blocks_map(mouse.position):
				# Outside dragging remains map input. A simple dismissal click does
				# not replace or clear the current geographic selection.
				_drawer_outside_press = mouse.position
			if _native_feedback_at(mouse.position) or _native_economic_at(mouse.position):
				_controller.suspend_motion()
				return
			if _quantity_input.visible and _quantity_input.get_global_rect().has_point(mouse.position):
				_controller.suspend_motion()
				return
			for index: int in range(_hits.size()-1,-1,-1):
				var hit := _hits[index]
				if _hit_contains(hit,mouse.position):
					get_viewport().set_input_as_handled()
					if bool(hit.enabled): _activate(str(hit.action))
					return
		# Let native scroll/buttons process GUI input inside these regions. The
		# renderer's input_blocked callback excludes exactly the same bounds.
		if _native_feedback_at(mouse.position) or _native_economic_at(mouse.position):
			_controller.suspend_motion()
			return
		if blocks_map(mouse.position):
			_controller.suspend_motion()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var hovered := ""
		var hint := ""
		for index: int in range(_hits.size()-1,-1,-1):
			if (bool(_hits[index].enabled) or _hits[index].has("tooltip")) and _hit_contains(_hits[index],(event as InputEventMouseMotion).position):
				hovered = str(_hits[index].action)
				hint = str(_hits[index].get("tooltip",""))
				break
		if hovered != _hover_action:
			_hover_action = hovered
			_hover_tooltip = hint
			_tooltip_visible = false
			_tooltip_timer.stop()
			if not hovered.is_empty(): _tooltip_timer.start()
			queue_redraw()
		elif hint!=_hover_tooltip:
			_hover_tooltip = hint
			if _tooltip_visible: queue_redraw()
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo: return
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			if key.keycode!=KEY_ESCAPE: return
			focus.release_focus()
			get_viewport().set_input_as_handled()
			return
		if not _slot_mode.is_empty() or not _confirmation.is_empty():
			if key.keycode not in [KEY_ESCAPE,KEY_BACKSPACE]:
				get_viewport().set_input_as_handled()
				return
		match key.keycode:
			KEY_ESCAPE: _back_layer()
			KEY_BACKSPACE: _back_layer(false)
			KEY_F5: action_requested.emit("save")
			KEY_F9: action_requested.emit("load")
			KEY_SPACE: action_requested.emit("time:pause")
			_: return
		queue_redraw()
		_controller.appearance_changed.emit()
		get_viewport().set_input_as_handled()

func _activate(action: String) -> void:
	if (action in ["purchase","consume","consumption:daily"] or action.begins_with("native:business_buy:")) and (action != "consumption:daily" or not person_page.daily_enabled) and _quantity_input.visible:
		var text := _quantity_input.get_line_edit().text.strip_edges()
		if not text.is_valid_float():
			show_feedback("数量必须是正数，并符合商品数量精度。")
			return
		var value := float(text)
		if not is_finite(value) or value <= 0 or value > float(FormalLedgerState.MAX_AMOUNT)/float(_quantity_scale) or absf(value*float(_quantity_scale)-round(value*float(_quantity_scale))) > 0.000001:
			show_feedback("数量无效；请使用此商品允许的数量精度。")
			return
		if _quantity_context.begins_with("economy:"): economy_page.quantity_milli = int(round(value*float(_quantity_scale)))
		else: person_page.quantity_milli = int(round(value*float(_quantity_scale)))
	if action == "navigation":
		_set_messages_open(false)
		_settings_open = false
		_navigation_open = not _navigation_open
		_system_open = false
		_map_modes_open = false
	elif action == "messages:toggle":
		var opened := not _messages_open
		_close_popups()
		_set_messages_open(opened)
	elif action == "back": _back_layer(false)
	elif action == "map:mode_menu":
		_set_messages_open(false)
		_settings_open = false
		_map_modes_open = not _map_modes_open
		_system_open = false
		_navigation_open = false
	elif action == "map:economy_mode":
		_map_modes_open = false
		action_requested.emit("map_mode:economic")
	elif action == "map:economic_supplements":
		_controller.toggle_economic_supplements()
	elif action == "country:market":
		economy_page.polity_id = str(_view_polity.get("id",""))
		economy_page.selected_commodity_id = ""
		economy_page.scope_label = ""
		economy_page.personal_market = false
		economy_page.selected_seller_site_id = ""
		economy_page.commodity_page = 0
		economy_page.show_native_statistics = false
		set_page("economy")
	elif action == "country:organizations":
		organization_page.country_id = str(_view_polity.get("id",""))
		organization_page.own_only = false
		organization_page.selected_id = ""
		organization_page.page = 0
		set_page("organization")
	elif action == "encyclopedia":
		world_page.index_open = true
		world_page.index_category = "home"
		set_page("world")
	elif action.begins_with("encyclopedia:category:"):
		world_page.index_category = action.trim_prefix("encyclopedia:category:")
		world_page.index_page = 0
		refresh()
	elif action in ["encyclopedia:previous","encyclopedia:next"]:
		world_page.index_page = maxi(0,world_page.index_page+(-1 if action=="encyclopedia:previous" else 1))
		refresh()
	elif action == "slots:close": close_slots()
	elif action == "confirm:cancel":
		close_confirmation()
		action_requested.emit("departure:cancel")
	elif action.begins_with("slot:info:"):
		_show_slot_info(_slots[int(action.trim_prefix("slot:info:"))])
	elif action.begins_with("slot:choose:"):
		var slot := int(action.trim_prefix("slot:choose:"))
		if _slot_mode=="load": action_requested.emit("slot:load:"+str(slot))
		elif not bool(_slots[slot].empty):
			_confirmation = {"kind":"overwrite","slot":slot,"slot_name":str(_slots[slot].name),"title":"覆盖已有存档？"}
		else: action_requested.emit("slot:save:"+str(slot))
	elif action == "context:close": _context_open = false
	elif action.begins_with("map_mode:"):
		_system_open = false
		_settings_open = false
		_navigation_open = false
		action_requested.emit(action)
	elif action == "page:person":
		if current_page != "person": remember_page()
		person_page.section = "situation"
		set_page("person",false)
	elif action.begins_with("page:"): set_page(action.trim_prefix("page:"))
	elif action == "system":
		_set_messages_open(false)
		_settings_open = false
		_system_open = not _system_open
		_navigation_open = false
		_map_modes_open = false
	elif action.begins_with("settings:"):
		if action=="settings:open":
			_settings_open = true
			_system_open = false
		elif action=="settings:back":
			_settings_open = false
			_system_open = true
		else:
			if action=="settings:bgm": _preferences.bgm = not bool(_preferences.bgm)
			elif action=="settings:fullscreen": _preferences.fullscreen = not bool(_preferences.fullscreen)
			elif action=="settings:fps": _preferences.active_fps=30 if int(_preferences.get("active_fps",60))==60 else 60
			elif action=="settings:idle_power": _preferences.idle_power=not bool(_preferences.get("idle_power",true))
			elif action=="settings:labels":
				_controller.toggle_labels()
				_preferences.labels = _controller.labels_enabled
			else: _preferences.volume = clampf(float(_preferences.volume)+(0.1 if action=="settings:louder" else -0.1),0,1)
			var error := SETTINGS.save(_preferences)
			if error!=OK: show_feedback("设置保存失败："+error_string(error))
		_controller.appearance_changed.emit()
	elif action == "person:business":
		person_page.business_mode=not person_page.business_mode
		person_page.capital_mode=false
		refresh()
	elif action=="person:business_finance":
		person_page.business_finance_mode=not person_page.business_finance_mode
	elif action in ["person:business_procurement","person:business_operations"]:
		person_page.business_procurement_mode=action=="person:business_procurement"
		refresh()
	elif action.begins_with("person:business_credit_"):
		person_page.business_finance_page=maxi(0,person_page.business_finance_page+(-1 if action.ends_with("previous") else 1))
	elif action=="person:business_reset":
		person_page.business_firm_id=""
		person_page.business_site_id=""
		person_page.business_firm_index=0
		person_page.business_site_index=0
		refresh()
	elif action.begins_with("person:business_"):
		var change := -1 if action.ends_with("previous") else 1
		if action.contains("firm_"):
			person_page.business_firm_id=""
			person_page.business_site_id=""
			person_page.business_firm_index=maxi(0,person_page.business_firm_index+change)
			person_page.business_site_index=0
			person_page.business_offer_page=0
			person_page.business_activity_page=0
		elif action.contains("site_"):
			person_page.business_site_id=""
			person_page.business_site_index=maxi(0,person_page.business_site_index+change)
			person_page.business_offer_page=0
			person_page.business_activity_page=0
		elif action.contains("offer_"): person_page.business_offer_page=maxi(0,person_page.business_offer_page+change)
		elif action.contains("activity_"): person_page.business_activity_page=maxi(0,person_page.business_activity_page+change)
		refresh()
	elif action == "person:capital":
		person_page.capital_mode = not person_page.capital_mode
		person_page.business_mode = false
		refresh()
	elif action in ["person:capital_previous", "person:capital_next"]:
		person_page.capital_page = maxi(0, person_page.capital_page+(-1 if action=="person:capital_previous" else 1))
		refresh()
	elif action.begins_with("person:living_tab:"):
		person_page.native_tab=action.trim_prefix("person:living_tab:")
		person_page.native_scope_expanded=false
		if person_page.native_tab!="other":
			person_page.business_mode=false
			person_page.lease_mode=false
			person_page.resident_services_mode=false
		refresh()
	elif action.begins_with("person:job_select:"):
		person_page.selected_job_id=action.trim_prefix("person:job_select:")
		person_page.native_tab="job_detail"
		refresh()
	elif action=="person:job_diagnostics":
		person_page.native_diagnostics=not person_page.native_diagnostics
	elif action.begins_with("person:job_request:"):
		var id:=action.trim_prefix("person:job_request:")
		var job:=person_page.job_row(id)
		if not person_page.can_apply(job):
			show_feedback(person_page.job_reason(job))
		else:
			person_page.selected_job_id=id
			_confirmation={"kind":"employment","title":"申请"+EconomicText.firm(job["employer"])+"工作？","body":"完成每期%d小时后应计%d %s；日结后延迟%d日到期。申请不等于已工作或已领薪。" % [int(job["hours"]),int(job["hours"])*int(job["wage_per_hour"]),EconomicText.currency(job["denomination"]),int(job["wage_delay"])],"action":"native:apply:"+id+"|"+str(job.get("job_quote_id",""))}
	elif action=="person:leave_request":
		var contract:=person_page._personal.get("employment",{}) as Dictionary
		if not contract.is_empty() and not contract.get("end_pending",false):
			_confirmation={"kind":"employment","title":"申请结束当前劳动合同？","body":"下次正式日界生效；此前仍占用岗位。已形成工资和已接受责任保留，不由其他雇主代偿。","action":"native:leave_job"}
	elif action=="confirm:employment":
		if _confirmation.get("kind")=="employment":
			var request:=str(_confirmation.get("action",""))
			_confirmation.clear()
			_hits.clear()
			action_requested.emit(request)
	elif action in ["person:wage_previous","person:wage_next"]:
		person_page.native_wage_page=maxi(0,person_page.native_wage_page+(-1 if action=="person:wage_previous" else 1))
		refresh()
	elif action == "person:native_scope":
		person_page.native_scope_expanded = not person_page.native_scope_expanded
		refresh()
	elif action in ["person:native_jobs_previous", "person:native_jobs_next"]:
		person_page.native_jobs_page = maxi(0,person_page.native_jobs_page+(-1 if action=="person:native_jobs_previous" else 1))
		refresh()
	elif action in ["person:native_order_previous", "person:native_order_next"]:
		person_page.native_order_page = maxi(0,person_page.native_order_page+(-1 if action=="person:native_order_previous" else 1))
		refresh()
	elif action in ["person:accounts","person:goods","person:records","person:native"]:
		var section := str({"person:accounts":"accounts","person:goods":"goods","person:records":"records","person:native":"native"}[action])
		if current_page != "person": remember_page()
		person_page.section = section
		if section == "records": person_page.selected_record_id = ""
		set_page("person",false)
	elif action.begins_with("holding:select:"):
		var id := action.trim_prefix("holding:select:")
		if current_page!="person" or person_page.selected_commodity_id!=id: remember_page()
		person_page.selected_commodity_id = id
		person_page.section = "goods"
		set_page("person",false)
	elif action.begins_with("living:record:"):
		var id := action.trim_prefix("living:record:")
		if current_page!="person" or person_page.selected_record_id!=id: remember_page()
		person_page.selected_record_id = id
		person_page.section = "records"
		set_page("person",false)
	elif action in ["inventory:previous","inventory:next"]:
		person_page.inventory_page = maxi(0,person_page.inventory_page+(-1 if action=="inventory:previous" else 1))
		refresh()
	elif action in ["living:previous","living:next"]:
		person_page.living_page = maxi(0,person_page.living_page+(-1 if action=="living:previous" else 1))
		refresh()

	elif action.begins_with("commodity:select:"):
		var selection := action.trim_prefix("commodity:select:").split("|")
		economy_page.selected_commodity_id = selection[0]
		economy_page.selected_seller_site_id = selection[1] if selection.size() > 1 else ""
		refresh()
	elif action in ["economy:native_statistics", "economy:native_previous", "economy:native_next"]:
		if action == "economy:native_statistics": economy_page.show_native_statistics = true
		elif action == "economy:native_previous": economy_page.native_statistics_page = maxi(0,economy_page.native_statistics_page-1)
		else: economy_page.native_statistics_page += 1
		refresh()
	elif action in ["economy:cohort_previous", "economy:cohort_next"]:
		economy_page.cohort_statistics_page = maxi(0,economy_page.cohort_statistics_page+(-1 if action == "economy:cohort_previous" else 1))
		economy_page.native_statistics_page = 0
		refresh()
	elif action == "person:situation":
		person_page.section = "situation"
		refresh()
	elif action == "person:organizations":
		remember_page()
		organization_page.own_only = true
		organization_page.page = 0
		organization_page.selected_id = ""
		set_page("organization",false)
	elif action in ["person:previous","person:next"]:
		person_page.account_page = maxi(0,person_page.account_page+(-1 if action=="person:previous" else 1))
		refresh()
	elif action in ["organization:previous","organization:next"]:
		organization_page.page = maxi(0,organization_page.page+(-1 if action=="organization:previous" else 1))
	elif action in ["economy:previous","economy:next"]:
		economy_page.commodity_page = maxi(0,economy_page.commodity_page+(-1 if action=="economy:previous" else 1))
		refresh()
	elif action in ["admin:previous","admin:next"]:
		world_page.admin_page = maxi(0,world_page.admin_page+(-1 if action=="admin:previous" else 1))
	elif action.begins_with("admin:select:"):
		world_page.admin_member_page = 0
		_context_open = true
		action_requested.emit(action)
	elif action == "admin:list": action_requested.emit(action)
	elif action in ["admin:members_previous","admin:members_next"]:
		world_page.admin_member_page = maxi(0,world_page.admin_member_page+(-1 if action=="admin:members_previous" else 1))
	else: action_requested.emit(action)
	queue_redraw()
	if action in ["navigation","system","map:mode_menu","map:economy_mode","messages:toggle","encyclopedia","context:close"]: _controller.appearance_changed.emit()

func _hit_contains(hit: Dictionary, point: Vector2) -> bool:
	if not (hit.rect as Rect2).has_point(point): return false
	if hit.has("circle_center"):
		return point.distance_squared_to(hit.circle_center as Vector2)<=pow(float(hit.circle_radius),2.0)
	if hit.has("ellipse_center"):
		var offset := (point-(hit.ellipse_center as Vector2))/(hit.ellipse_radii as Vector2)
		return offset.length_squared()<=1.0
	if hit.has("hemisphere_center"):
		var center := hit.hemisphere_center as Vector2
		return point.y<=center.y and point.distance_squared_to(center)<=pow(float(hit.hemisphere_radius),2.0)
	return true

func blocks_map(point: Vector2) -> bool:
	if economic_map!=null:
		for rect: Rect2 in economic_map.occlusions():
			if rect.has_point(point): return true
	if _message_handle!=null and _message_handle.visible and _message_handle_rect().has_point(point): return true
	if _message_drawer!=null and _native_feedback_at(point): return true
	if _notice_canvas!=null and _notice_canvas.visible and _notice_rect().has_point(point): return true
	for rect: Rect2 in _blocks:
		if rect.has_point(point): return true
	for hit: Dictionary in _hits:
		if _hit_contains(hit,point): return true
	return false

func _native_economic_at(point: Vector2) -> bool:
	if economic_map==null: return false
	for rect: Rect2 in economic_map.occlusions():
		if rect.has_point(point): return true
	return false

func date_text() -> String:
	if _date.is_empty(): return "日期读取中"
	return "%04d年%02d月%02d日 %02d:%02d" % [int(_date.get("year",0)),int(_date.get("month",0)),int(_date.get("day",0)),int(_date.get("hour",0)),int(_date.get("minute",0))]

func panel(rect: Rect2, fill: Color, border: Color) -> void:
	UIDrawing.panel(self,rect,fill,border)

func block_panel(rect: Rect2) -> void:
	_blocks.append(rect)
	panel(rect,PANEL_FILL,PANEL_BORDER)

func label(point: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90,0.91,0.84,1.0), width: float = -1.0) -> void:
	if not _text_fonts.has(text):
		if _text_fonts.size() >= 512: _text_fonts.clear()
		_text_fonts[text] = GlobeLabels.font_for_name(_font,text)
	UIDrawing.label(self,_text_fonts[text] as Font,point,text,font_size,color,width)

func wrapped(point: Vector2, text: String, width: float, font_size: int = 12, max_lines: int = 4) -> void:
	var key := str(width)+"|"+str(font_size)+"|"+str(max_lines)+"|"+text
	if not _wrapped_text_cache.has(key):
		var lines: Array[String] = []
		var line := ""
		var font := GlobeLabels.font_for_name(_font,text)
		for index: int in range(text.length()):
			var character := text.substr(index,1)
			if character=="\n" or (not line.is_empty() and font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width):
				lines.append(line)
				line=""
				if lines.size()>=max_lines: break
			if character!="\n": line+=character
		if not line.is_empty() and lines.size()<max_lines: lines.append(line)
		if _wrapped_text_cache.size()>=256: _wrapped_text_cache.clear()
		_wrapped_text_cache[key]=lines
	var rows:=_wrapped_text_cache[key] as Array
	for row: int in rows.size(): label(point+Vector2(0,row*20),rows[row],font_size,Color(0.82,0.86,0.79),width)

func button(rect: Rect2, text: String, action: String, enabled: bool = true, selected: bool = false, font_size: int = 11) -> void:
	_hits.append({"rect":rect,"action":action,"enabled":enabled})
	var hovered := enabled and _hover_action == action
	panel(rect,Color(0.13,0.14,0.10,0.96) if selected else Color(0.07,0.10,0.08,0.96) if hovered else Color(0.035,0.052,0.043,0.88),Color(0.76,0.65,0.43,0.7) if selected or hovered else PANEL_BORDER)
	UIDrawing.label(self,_button_font,rect.position+Vector2(9,minf(20,rect.size.y-4)),text,font_size,INK if enabled else Color(0.42,0.48,0.44),rect.size.x-18)

func heading(rect: Rect2, title: String, subtitle: String) -> void:
	label(rect.position+Vector2(20,38),title,21,Color(0.96,0.88,0.67),rect.size.x-110)
	wrapped(rect.position+Vector2(20,61),subtitle,rect.size.x-40,10,2)
	draw_line(rect.position+Vector2(20,88),Vector2(rect.end.x-20,rect.position.y+88),Color(0.64,0.56,0.33,0.26),1)

func card(rect: Rect2, title: String) -> void:
	draw_rect(rect,Color(0.03,0.044,0.038,0.55))
	label(rect.position+Vector2(14,28),title,13,Color(0.91,0.82,0.57),rect.size.x-28)

func lines(point: Vector2, values: Array[String], width: float) -> void:
	var y := point.y
	for text: String in values:
		label(Vector2(point.x,y),text,12,Color(0.82,0.86,0.79),width)
		y += 24

func quantity_input(rect: Rect2, quantity_milli: int, context: String, scale: int = 1000) -> void:
	_quantity_used = true
	_quantity_input.position = rect.position
	_quantity_input.size = rect.size
	if _quantity_context != context or _quantity_scale != scale:
		_quantity_input.set_block_signals(true)
		_quantity_input.get_line_edit().set_block_signals(true)
		_quantity_context = context
		_quantity_scale = maxi(1,scale)
		_quantity_input.min_value = 1.0/float(_quantity_scale)
		_quantity_input.max_value = float(FormalLedgerState.MAX_AMOUNT)/float(_quantity_scale)
		_quantity_input.step = 1.0/float(_quantity_scale)
		_quantity_input.set_value_no_signal(float(quantity_milli)/float(_quantity_scale))
		_quantity_input.get_line_edit().set_block_signals(false)
		_quantity_input.set_block_signals(false)

func _on_quantity_changed(value: float) -> void:
	var quantity := int(round(value*float(_quantity_scale)))
	if _quantity_context.begins_with("economy:"):
		if economy_page.quantity_milli == quantity: return
		economy_page.quantity_milli = quantity
	else:
		if person_page.quantity_milli == quantity: return
		person_page.quantity_milli = quantity
	refresh()

func _on_quantity_text_changed(text: String) -> void:
	if text.is_valid_float() and is_finite(float(text)) and absf(float(text)) <= float(FormalLedgerState.MAX_AMOUNT)/float(_quantity_scale): _on_quantity_changed(float(text))

func number(point: Vector2,text: String,width: float,font_size: int = 12,color: Color = Color(0.90,0.91,0.84,1.0)) -> void:
	var font := GlobeLabels.font_for_name(_font,text)
	draw_string(font,point,text,HORIZONTAL_ALIGNMENT_RIGHT,width,font_size,color)

func set_save_pending(value: bool) -> void:
	_saving = value
	queue_redraw()

func show_save_error(message: String) -> void:
	_slot_error = message
	if not _confirmation.is_empty(): _confirmation["error"] = message
	show_feedback(message,"","system","error")
