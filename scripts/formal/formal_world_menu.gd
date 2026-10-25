class_name FormalWorldMenu
extends Control

const WORLD_SCENE: String = "res://scenes/formal/formal_world_main.tscn"
const MAP_SCENE = preload("res://scenes/presentation/map/globe_renderer.tscn")
const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
const PREPARED_WORLD_META: StringName = &"formal_world_prepared_build"
const PREPARED_MAP_META: StringName = &"formal_world_prepared_map"
const PREPARED_CONTROLLER_META: StringName = &"formal_world_prepared_controller"
const PREPARED_LOADING_META: StringName = &"formal_world_prepared_loading"
const PREPARED_CONTENT_META: StringName = &"formal_world_prepared_content"
const LIVELIHOOD_META: StringName = &"formal_world_livelihood"
const NATIVE_ECONOMY_META: StringName = &"formal_world_native_economy"
const SETTINGS = preload("res://scripts/presentation/ui/interface_settings.gd")
const MAP_ACCEPTANCE = preload("res://scripts/presentation/ui/map_resource_acceptance.gd")
var _map_acceptance: Control
var _map_acceptance_requested: bool = false
@onready var _controller: GlobeController = $GlobeController
var _renderer: GlobeRenderer
var _page: String = "home"
var _entering: bool = false
var _preview_ready: bool = false
var _preview_error: String = ""
var _content: HistoricalLoader
var _politics: RuntimePoliticalEntityView
var _evidence: HistoricalPoliticalEvidenceView
var _countries: Array[Dictionary] = []
var _country_id: String = "state:country_fra"
var _preferences: Dictionary = {}
var _panel: PanelContainer
var _column: VBoxContainer
var _footer: VBoxContainer
var _status: Label
var _country_choice: OptionButton
var _country_name: Label
var _flag: TextureRect
var _brief: Label
var _person_note: Label
var _person_choice: OptionButton
var _enter_button: Button
var _worker: Thread
var _launch_mode: String = ""
var _preview_worker: Thread
var _loading_layer: Control
var _loading_label: Label
var _launch_presentation: Dictionary = {}
var _preview_mutex := Mutex.new()
var _preview_generation: int = 0
var _preview_stage: String = ""
var _displayed_preview_stage: String = ""
var _preview_stage_since: int = 0
var _preview_waiting: bool = false
var _preview_installing: bool = false
var _preview_display_waiting: bool = false
var _preview_checking_display: bool = false
var _pending_preview: Dictionary = {}
var _pending_launch: WorldBuildResult
var _loading_back: Button
var _map_status_generation: int = 0


func _ready() -> void:
	get_window().min_size = Vector2i(960,640)
	get_tree().auto_accept_quit = true
	theme = UIDrawing.shell_theme()
	_preferences = SETTINGS.load_preferences()
	SETTINGS.apply(_preferences)
	_controller.labels_enabled = bool(_preferences.get("labels",false))
	var visual := SETTINGS.theme_parameters()
	($Painting as TextureRect).texture = visual.background as Texture2D
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://shaders/presentation/ui/menu_painting.gdshader")
	paint.set_shader_parameter("motion",visual.menu_motion)
	($Painting as TextureRect).material = paint
	($Version as Label).text = "v"+str(ProjectSettings.get_setting("application/config/version",""))
	($Version as Label).theme = theme
	_controller.selection_changed.connect(_map_country_selected)
	resized.connect(_position_panel)
	set_process(false)
	_show_page("home")
	if "--map-resource-acceptance" in OS.get_cmdline_user_args(): _open_map_acceptance.call_deferred()
	if OS.has_feature("editor") and "--map-resource-review" in OS.get_cmdline_user_args():
		var observer := load("res://tools/map/r57_visual_driver.gd").new() as Node
		observer.set("acceptance", "resource-review")
		add_child(observer)

func _open_map_acceptance() -> void:
	if not OS.has_feature("editor") and not OS.has_feature("map_resource_acceptance"): return
	if _entering or is_instance_valid(_map_acceptance): return
	_map_acceptance_requested = true
	_show_page("selection")
	if _preview_ready: _install_map_acceptance.call_deferred()

func _install_map_acceptance() -> void:
	if not _map_acceptance_requested or not _preview_ready or not is_instance_valid(_renderer) or is_instance_valid(_map_acceptance): return
	_map_acceptance = MAP_ACCEPTANCE.new()
	_map_acceptance.configure(_renderer, _controller)
	_map_acceptance.closed.connect(func() -> void:
		_map_acceptance = null
		_map_acceptance_requested = false
		_show_page("home"))
	_panel.hide()
	add_child(_map_acceptance)
	_controller.appearance_changed.emit()

func _prepare_preview() -> void:
	if _renderer!=null or _entering or _preview_waiting: return
	if _preview_worker!=null:
		_preview_error = "上一地图请求仍在结束，请稍后点击重新准备。"
		_show_page("selection")
		return
	_preview_error = ""
	_preview_waiting = true
	_preview_ready = false
	_preview_mutex.lock()
	_preview_generation += 1
	var generation := _preview_generation
	_preview_mutex.unlock()
	_report_preview_stage("正在读取地图资料",generation)
	_displayed_preview_stage = ""
	_set_loading(true,"正在读取地图资料")
	_preview_worker = Thread.new()
	var error := _preview_worker.start(_read_preview.bind(generation))
	if error!=OK:
		_preview_worker = null
		_fail_preview("无法启动地图准备线程："+error_string(error))
	else: set_process(true)

func _preview_current(generation: int) -> bool:
	_preview_mutex.lock()
	var active := generation==_preview_generation
	_preview_mutex.unlock()
	return active

func _report_preview_stage(stage: String, generation: int) -> void:
	# Worker writes plain status only. UI and scene-tree operations stay here.
	_preview_mutex.lock()
	if generation==_preview_generation: _preview_stage = stage
	_preview_mutex.unlock()

func _read_preview(generation: int) -> Dictionary:
	var stage := _report_preview_stage.bind(generation)
	var current := _preview_current.bind(generation)
	var provenance := HistoricalProvenanceFoundation.new()
	if not provenance.load_current(): return {"error":provenance.initialization_error}
	if not current.call(): return {"cancelled":true}
	var prepared := WorldBootstrap.prepare_presentation_content(provenance,stage,current)
	if not current.call(): return {"cancelled":true}
	if not prepared.loaded or not prepared.errors.is_empty(): return {"error":"\n".join(prepared.errors)}
	stage.call("正在准备历史国家")
	var catalog := HistoricalPoliticalEvidenceCatalog.new()
	var identities := RuntimePoliticalEntityRegistry.new()
	if not catalog.configure(HistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,provenance.gate()): return {"error":catalog.initialization_error}
	if not identities.configure(catalog): return {"error":identities.initialization_error}
	if not current.call(): return {"cancelled":true}
	stage.call("正在准备历史范围与边界")
	var meshes := GlobeRenderer.prepare_source_geometry(prepared.geometry_content)
	if not current.call(): return {"cancelled":true}
	var politics := RuntimePoliticalEntityView.new(identities.snapshot())
	var evidence := HistoricalPoliticalEvidenceView.new(catalog.read_only_snapshot())
	var date := GameClock.new().current_date()
	stage.call("正在读取国家旗帜与显示资料")
	var display := prepared.resolve_map(date,CurrentWorldPoliticalProjection.map_units(politics,evidence))
	if not current.call(): return {"cancelled":true}
	return {"error":"","content":prepared,"politics":politics,"evidence":evidence,"meshes":meshes,"date":date,"display":display}

static func _preview_result_error(value: Variant) -> String:
	if not value is Dictionary: return "地图准备线程未返回有效结果，请查看游戏错误日志。"
	var prepared := value as Dictionary
	if not prepared.get("error") is String: return "地图准备结果缺少明确的完成状态。"
	if not str(prepared.error).is_empty(): return str(prepared.error)
	if not prepared.get("content") is HistoricalLoader: return "地图准备结果缺少历史资料。"
	var loaded_content := prepared.content as HistoricalLoader
	if not loaded_content.errors.is_empty(): return "\n".join(loaded_content.errors)
	if not loaded_content.loaded or loaded_content.geometry_content==null: return "必需历史地图尚未准备成功。"
	if not prepared.get("politics") is RuntimePoliticalEntityView or not prepared.get("evidence") is HistoricalPoliticalEvidenceView:
		return "地图准备结果缺少历史国家身份。"
	if not prepared.get("meshes") is Dictionary: return "地图准备结果缺少历史几何。"
	if prepared.has("display") and not prepared.display is ResolvedMapContent: return "国家显示资料返回类型无效。"
	if prepared.has("date"):
		if not prepared.date is Dictionary: return "地图准备结果的日期格式无效。"
		for key: String in ["year","month","day"]:
			if typeof((prepared.date as Dictionary).get(key)) not in [TYPE_INT,TYPE_FLOAT]: return "地图准备结果缺少日期字段："+key
	var meshes := prepared.meshes as Dictionary
	var ids := loaded_content.geometry_content.feature_ids()
	if ids.is_empty(): return "必需历史地图没有有效的地理要素。"
	for id: String in ids:
		if not meshes.get(id) is Dictionary: return "历史地图缺少几何："+id
		var mesh := meshes[id] as Dictionary
		if not mesh.get("parts") is Array or not mesh.get("borders") is Array or not mesh.get("uv_bounds") is Rect2 or not mesh.get("flag_bounds") is Rect2:
			return "历史地图几何准备未完成："+id
		if (mesh.parts as Array).is_empty(): return "历史地图没有可用的查询多边形："+id
	return ""

func _fail_preview(reason: String) -> void:
	_preview_ready = false
	_preview_waiting = false
	_preview_installing = false
	_preview_display_waiting = false
	_preview_checking_display = false
	_pending_preview = {}
	_pending_launch = null
	_launch_presentation = {}
	_entering = false
	_preview_error = "地图准备失败："+reason
	# Release input before renderer cleanup can invoke any of its callbacks.
	_set_loading(false)
	if is_instance_valid(_status):
		_status.text = _preview_error
		_status.visible = true
	_countries.clear()
	_politics = null
	_evidence = null
	_content = null
	if is_instance_valid(_renderer):
		_renderer.hide()
		_renderer.queue_free()
	_renderer = null
	_show_page(_page)
	set_process(_preview_worker!=null or _worker!=null)

func _retry_preview() -> void:
	if _entering: return
	_prepare_preview()

func _leave_preview_preparation() -> void:
	if _entering or not _preview_waiting: return
	_preview_mutex.lock()
	_preview_generation += 1
	_preview_mutex.unlock()
	_preview_waiting = false
	_preview_display_waiting = false
	_pending_preview = {}
	_preview_error = "地图准备已取消，可重新准备；旧线程结束前不会启动新请求。"
	_set_loading(false)
	if is_instance_valid(_renderer):
		_renderer.hide()
		_renderer.queue_free()
		_renderer = null
	_preview_ready = false
	_show_page("home")
	# Cooperative cancellation only. Never join/kill a live worker on this path.
	set_process(_preview_worker!=null)

func _install_preview(prepared: Dictionary) -> bool:
	var error := _preview_result_error(prepared)
	if not error.is_empty():
		_fail_preview(error)
		return false
	_content = prepared.content as HistoricalLoader
	_politics = prepared.politics as RuntimePoliticalEntityView
	_evidence = prepared.evidence as HistoricalPoliticalEvidenceView
	_renderer = MAP_SCENE.instantiate() as GlobeRenderer
	if _renderer==null:
		_fail_preview("无法创建地图显示节点。")
		return false
	_renderer.modulate = Color(0.80,0.83,0.79)
	add_child(_renderer)
	move_child(_renderer,1)
	_renderer.relief.decode_asset = GeographyLoader.decode_relief
	_renderer.input_blocked = _blocks_map
	_renderer.map_notice.connect(func(message: String) -> void:
		if _preview_ready and _page=="selection" and is_instance_valid(_status):
			_show_map_status(message))
	_renderer.label_exclusions = _map_occlusions
	_renderer.configure(_content.geometry_content,_controller)
	_renderer.install_source_geometry(prepared.meshes)
	_renderer.local_content = _content.local_spatial
	_renderer.strategic_content = _content.strategic_spatial
	var date := prepared.get("date",GameClock.new().current_date()) as Dictionary
	var units := CurrentWorldPoliticalProjection.map_units(_politics,_evidence)
	# Scene installation is synchronous. The next normal frame will draw it;
	# menu readiness must not depend on a RenderingServer signal.
	var display := prepared.display as ResolvedMapContent if prepared.has("display") else _content.resolve_map(date,units)
	_renderer.refresh(_politics,_evidence,null,[],date,display)
	_countries.clear()
	for unit: Dictionary in units:
		if not str(unit.get("geometry_feature_id","")).is_empty(): _countries.append(unit)
	_countries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.get("name_zh","")) < str(b.get("name_zh","")))
	# refresh clears this existing flag only after source binding completes.
	if _countries.is_empty() or _renderer.political.records.is_empty() or _renderer._source_dirty or not _renderer.is_node_ready():
		_fail_preview("历史国家或显示几何未完整安装，请查看游戏错误日志。")
		return false
	_controller.select(_country_id)
	# Establish the actual initial demand before observing installation.
	# The focus button remains disabled until the same demand is committed.
	if not _entering:
		var anchor := _renderer.political.anchors.get(_country_id,Vector3.ZERO) as Vector3
		if not anchor.is_zero_approx():
			_controller.focus(anchor)
			_controller.set_world_zoom(0.86)
	_preview_display_waiting = true
	_renderer.queue_redraw()
	return true

func _set_loading(enabled: bool, text: String = "正在进入世界") -> void:
	if _loading_layer==null:
		_loading_layer = Control.new()
		_loading_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_loading_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		_loading_layer.z_index = 100
		_loading_layer.theme = UIDrawing.shell_theme()
		add_child(_loading_layer)
		var painting := TextureRect.new()
		painting.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		painting.texture = SETTINGS.theme_parameters().background as Texture2D
		painting.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		painting.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		painting.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_loading_layer.add_child(painting)
		var shade := ColorRect.new()
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.color = Color(0.01,0.02,0.02,0.60)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_loading_layer.add_child(shade)
		_loading_label = Label.new()
		_loading_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_loading_label.offset_left = 48
		_loading_label.offset_right = -48
		_loading_label.offset_top = -74
		_loading_label.offset_bottom = -43
		_loading_layer.add_child(_loading_label)
		var strip := ColorRect.new()
		strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		strip.offset_left = 48
		strip.offset_right = -48
		strip.offset_top = -38
		strip.offset_bottom = -35
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/presentation/ui/loading_strip.gdshader")
		strip.material = material
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_loading_layer.add_child(strip)
		_loading_back = Button.new()
		_loading_back.text = "返回主菜单"
		_loading_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_loading_back.offset_left = -200
		_loading_back.offset_top = -110
		_loading_back.offset_right = -48
		_loading_back.offset_bottom = -76
		_loading_back.pressed.connect(_leave_preview_preparation)
		_loading_layer.add_child(_loading_back)
	_loading_label.text = text
	_loading_layer.visible = enabled
	_loading_back.visible = false # Normal preparation has no redundant return button.

func _show_page(page: String) -> void:
	if _entering: return
	_page = page
	_country_choice = null
	_country_name = null
	_enter_button = null
	_person_choice = null
	if page=="selection" and _renderer==null and _preview_error.is_empty() and not _preview_waiting: _prepare_preview.call_deferred()
	($Painting as TextureRect).visible = page!="selection" or not _preview_ready
	($Shade as ColorRect).visible = page!="selection" or not _preview_ready
	($Version as Label).visible = page=="home"
	if _renderer != null: _renderer.visible = page=="selection"
	if _panel != null:
		remove_child(_panel)
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.z_index = 20
	var frame := StyleBoxFlat.new()
	frame.bg_color = SETTINGS.theme_parameters().panel as Color
	frame.bg_color.a = 0.94 if page=="selection" else 0.87
	frame.border_color = Color(0.60,0.51,0.31,0.45)
	frame.set_border_width_all(1 if page!="home" else 0)
	frame.content_margin_left = 22
	frame.content_margin_right = 22
	frame.content_margin_top = 22
	frame.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel",frame)
	add_child(_panel)
	_panel.minimum_size_changed.connect(_position_panel,CONNECT_DEFERRED)
	var frame_column := VBoxContainer.new()
	frame_column.add_theme_constant_override("separation",8 if page=="selection" else 12)
	_panel.add_child(frame_column)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation",10)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_column.add_child(_column)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation",8)
	frame_column.add_child(_footer)
	match page:
		"home":
			_text("1900",int(SETTINGS.theme_parameters().title_size))
			_button("开始",_show_page.bind("selection"))
			_button("加载",_show_page.bind("load"))
			if OS.has_feature("editor") or OS.has_feature("map_resource_acceptance"):
				_button("地图 / 资源验收（开发）", _open_map_acceptance)
			_button("主题管理",_show_page.bind("themes"))
			_button("设置",_show_page.bind("settings"))
			_button("退出",get_tree().quit)
		"selection":
			if not _preview_error.is_empty():
				_button("重新准备地图",_retry_preview)
				_button("返回首页",_show_page.bind("home"))
			var flag_row := HBoxContainer.new()
			_column.add_child(flag_row)
			_flag = TextureRect.new()
			_flag.custom_minimum_size = Vector2(62,42)
			_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			flag_row.add_child(_flag)
			_country_name = Label.new()
			_country_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_country_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_country_name.add_theme_font_size_override("font_size",21)
			flag_row.add_child(_country_name)
			_country_choice = OptionButton.new()
			_country_choice.fit_to_longest_item = false
			_country_choice.clip_text = true
			_column.add_child(_country_choice)
			for country: Dictionary in _countries:
				_country_choice.add_item(str(country.get("name_zh","名称未记录")))
				_country_choice.set_item_metadata(_country_choice.item_count-1,str(country.id))
			_country_choice.item_selected.connect(_country_chosen)
			_brief = _text("",14)
			_text("身份",16)
			_person_choice = OptionButton.new()
			_column.add_child(_person_choice)
			_person_note = _text("",13)
			_column = _footer
			_enter_button = _button("进入世界",_enter_world.bind("new",1),false)
			_update_country()
		"load":
			_text("加载",25)
			var rows := FormalPersistence.slot_summaries()
			var any_save := false
			for row: Dictionary in rows:
				if not bool(row.empty): any_save = true
			if not any_save: _text("暂无正式存档。",14)
			for row: Dictionary in rows:
				var actions := HBoxContainer.new()
				_column.add_child(actions)
				var load_button := _button(str(row.name),_enter_world.bind("load",int(row.slot)),not bool(row.empty))
				load_button.reparent(actions)
				load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var info_button := _button("资料",_show_slot_info.bind(row),not bool(row.empty))
				info_button.reparent(actions)
				info_button.custom_minimum_size.x = 54
				var detail := _text(FormalPersistence.summary_text(row),11)
				detail.custom_minimum_size.y = 28
				detail.max_lines_visible = 2
				detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				detail.tooltip_text = FormalPersistence.details_text(row)
			_button("返回",_show_page.bind("home"))
		"themes":
			_text("主题管理",25)
			_button("● "+str(SETTINGS.theme_parameters().name),_select_theme)
			_text(str(SETTINGS.theme_parameters().design_name),13)
			_text("古斯塔夫·卡耶博特\n《雨天的巴黎街道》· 1877",14)
			_text("芝加哥艺术博物馆 · CC0",12)
			_button("返回",_show_page.bind("home"))
		"settings":
			_text("设置",25)
			_text("主音量",16)
			var volume := HSlider.new()
			volume.min_value = 0
			volume.max_value = 100
			volume.value = float(_preferences.volume)*100
			_column.add_child(volume)
			volume.value_changed.connect(_volume_changed)
			if AudioServer.get_bus_index("BGM")>=0:
				var bgm := CheckButton.new()
				bgm.text = "BGM"
				bgm.button_pressed = bool(_preferences.bgm)
				_column.add_child(bgm)
				bgm.toggled.connect(_bgm_changed)
			var fullscreen := CheckButton.new()
			fullscreen.text = "全屏"
			fullscreen.button_pressed = bool(_preferences.fullscreen)
			_column.add_child(fullscreen)
			fullscreen.toggled.connect(_fullscreen_changed)
			for setting: Dictionary in [{"key":"labels","name":"地图名称"}]:
				var toggle := CheckButton.new()
				toggle.text = str(setting.name)
				toggle.button_pressed = bool(_preferences.get(str(setting.key),true))
				_column.add_child(toggle)
				toggle.toggled.connect(_map_preference_changed.bind(str(setting.key)))
			_button("返回",_show_page.bind("home"))
	_status = _text(_preview_error if page=="selection" else "",12)
	_status.visible = not _status.text.is_empty()
	_position_panel()
	_controller.suspend_motion()
	_controller.appearance_changed.emit()

func _show_map_status(message: String) -> void:
	if _status.text==message and _status.visible: return
	_map_status_generation += 1
	_status.text = message
	_status.tooltip_text = message
	_status.visible = not message.is_empty()
	var failed := "失败" in message or "无法" in message or "未安装" in message
	if failed or "正在" in message or message.is_empty(): return
	var generation := _map_status_generation
	var label := _status
	get_tree().create_timer(3.0,true,false,true).timeout.connect(func() -> void:
		if generation==_map_status_generation and is_instance_valid(label) and label==_status:
			label.visible = false)

func _text(value: String,font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	_column.add_child(label)
	return label

func _show_slot_info(row: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = str(row.name)+" · 存档资料"
	dialog.dialog_text = FormalPersistence.details_text(row)
	dialog.dialog_autowrap = true
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(620,int(size.x)-40),mini(440,int(size.y)-40)))

func _button(value: String,callback: Callable,enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = value
	button.disabled = not enabled
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	_column.add_child(button)
	return button

func _position_panel() -> void:
	if _panel == null: return
	var width := minf(350,size.x*0.36) if _page=="selection" else 360.0
	_panel.size = Vector2(width,0)
	var height := minf(_panel.get_combined_minimum_size().y,size.y-64)
	_panel.position = Vector2(size.x-width-32 if _page=="selection" else 48,maxf(32,(size.y-height)*0.5))
	_panel.size = Vector2(width,height)
	if _controller != null: _controller.appearance_changed.emit()

func _blocks_map(point: Vector2) -> bool:
	if is_instance_valid(_map_acceptance): return _map_acceptance.blocks_map(point)
	return _entering or (_loading_layer!=null and _loading_layer.visible) or _page!="selection" or (_panel != null and _panel.get_global_rect().has_point(point))

func _map_occlusions() -> Array[Rect2]:
	if is_instance_valid(_map_acceptance): return _map_acceptance.occlusions()
	var result: Array[Rect2] = []
	if _panel != null: result.append(Rect2(_panel.position,_panel.size))
	return result

func _country_chosen(index: int) -> void:
	if _entering: return
	_controller.select(str(_country_choice.get_item_metadata(index)))
	_focus_country()

func _map_country_selected() -> void:
	if _politics == null or not _politics.has_entity(_controller.selected_polity_id): return
	_country_id = _controller.selected_polity_id
	_update_country()

func _update_country() -> void:
	if _country_name == null or _politics == null: return
	var polity := CurrentWorldPoliticalProjection.polity_summary(_country_id,_politics,_evidence)
	var content := _content.resolve_world_page(GameClock.new().current_date(),polity)
	_country_name.text = str(polity.get("name_zh","名称未记录"))
	_flag.texture = content.texture()
	_brief.text = str(content.profile().get("opening_brief_zh",""))
	if _brief.text.is_empty(): _brief.text = AdministrativeLoader.identity_introduction(polity)
	_brief.tooltip_text = str(content.profile().get("opening_source_title","1900 年历史政治身份资料"))+"\n"+str(content.profile().get("opening_source_url","https://icr.ethz.ch/data/cshapes/"))
	_brief.visible = not _brief.text.is_empty()
	for index: int in range(_country_choice.item_count):
		if str(_country_choice.get_item_metadata(index))==_country_id: _country_choice.select(index); break
	_country_choice.text = "选择国家"
	var opening := WorldBootstrap.opening_profile(_politics.source_historical_id(_country_id))
	var playable := not opening.is_empty()
	_person_choice.clear()
	if playable:
		_person_choice.add_item(str(opening.place_name)+" · 普通开局人物")
		_person_choice.set_item_metadata(0,str(opening.person_id))
	_person_choice.disabled = not playable
	_person_choice.visible = playable
	_person_note.text = "游戏生成的普通人物，居住于"+str(opening.place_name)+"，暂无正式就业。"+("进入后可自愿申请本地工坊岗位。" if opening.get("source_id")=="country_fra" else "") if playable else "该地区暂无可选人物。"
	_enter_button.disabled = not playable or not _preview_ready
	_position_panel.call_deferred()

func _focus_country() -> void:
	if _entering or not _preview_ready: return
	var anchor := _renderer.political.anchors.get(_country_id,Vector3.ZERO) as Vector3
	if anchor.is_zero_approx(): return
	_controller.focus(anchor)
	_controller.set_world_zoom(0.86)

func _enter_world(mode: String,slot: int) -> void:
	if is_instance_valid(_map_acceptance): return
	if _entering: return
	if _preview_worker!=null or _preview_waiting or _preview_installing:
		_status.visible = true
		_status.text = "上一地图请求仍在结束，请稍后再进入世界。"
		return
	var source_id := _politics.source_historical_id(_country_id) if _politics!=null else ""
	var opening := WorldBootstrap.opening_profile(source_id)
	if mode=="new" and (opening.is_empty() or _person_choice==null or _person_choice.item_count==0 or str(_person_choice.get_selected_metadata())!=str(opening.person_id)): return
	if mode=="load" and FormalPersistence.existing_slot_path(slot).is_empty(): return
	_entering = true
	_launch_mode = mode
	_status.visible = true
	_status.text = "正在进入世界。"
	_controller.suspend_motion()
	_set_loading(true)
	_worker = Thread.new()
	var error := _worker.start(_build_world.bind(mode,slot,_renderer==null,source_id))
	if error!=OK:
		_worker = null
		_entering = false
		_set_loading(false)
		_status.text = "无法准备世界："+error_string(error)
	else: set_process(true)

func _build_world(mode: String,slot: int, prepare_map: bool, source_id: String) -> WorldBuildResult:
	var native_settings: Dictionary = EconomyDevelopmentConfig.formal_stratified_request() if mode=="new" and (OS.get_cmdline_user_args().has("--formal-capital-transport") or OS.get_cmdline_user_args().has("--formal-npc-capital-trade") or OS.get_cmdline_user_args().has("--formal-npc-capital-competition") or OS.get_cmdline_user_args().has("--formal-npc-capital-recirculation") or (EconomyDevelopmentConfig.player_capital_requested() or OS.get_cmdline_user_args().has("--formal-economy-feedback"))) else FormalEconomicOpening.for_source(source_id) if mode=="new" else {}
	var prepared_sources: HistoricalProvenanceFoundation = _content.provenance if _content!=null and _content.loaded else null
	var built := FormalPersistence.new().load_from_user(slot) if mode=="load" else WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,native_settings,source_id,prepared_sources)
	if built.success and prepare_map:
		var prepared := WorldBootstrap.prepare_presentation_content(built.world.provenance)
		if not prepared.loaded or not prepared.errors.is_empty():
			built.success = false
			built.error = "地图资料准备失败："+"\n".join(prepared.errors)
			return built
		_launch_presentation = {"error":"","content":prepared,"date":built.world.game_clock.current_date(),
			"politics":RuntimePoliticalEntityView.new(built.world.political_registry.snapshot()),
			"evidence":built.world.historical_evidence_view,"meshes":GlobeRenderer.prepare_source_geometry(prepared.geometry_content)}
	return built

func _process(_delta: float) -> void:
	# Installation contains no await. If a script error interrupted it, this
	# flag survives to the next normal UI tick, which releases the modal state.
	if _preview_installing or _preview_checking_display:
		_preview_checking_display = false
		_fail_preview("地图安装中断，未完成初始化。请查看游戏错误日志后重试。")
		return
	if not _pending_preview.is_empty():
		var prepared := _pending_preview
		_pending_preview = {}
		_preview_installing = true
		var installed := _install_preview(prepared)
		_preview_installing = false
		if not installed:
			if _preview_error.is_empty(): _fail_preview("地图安装未完成，请查看游戏错误日志后重试。")
			return
	if _preview_display_waiting:
		if not is_instance_valid(_renderer):
			_fail_preview("地图显示节点已经退出，未完成安装。")
			return
		_preview_checking_display = true
		var status := _renderer.current_view_map_status()
		_preview_checking_display = false
		if str(status.state)=="failed":
			_fail_preview(str(status.message))
			return
		_report_preview_stage(str(status.message),_preview_generation)
		if str(status.state)=="installed":
			_preview_display_waiting = false
			_preview_waiting = false
			_preview_ready = true
			if _pending_launch!=null:
				var launching := _pending_launch
				_pending_launch = null
				_finish_world_launch(launching)
				return
			_set_loading(false)
			_show_page(_page)
			if _map_acceptance_requested: _install_map_acceptance.call_deferred()
			if not (status.get("warnings",[]) as Array).is_empty():
				_show_map_status("物理地图已就绪；可选图层失败："+"; ".join(status.warnings as Array))
			elif bool(status.get("political_pending",false)):
				_show_map_status("完整物理地图已就绪，国家着色正在后台准备。")
	if _preview_worker!=null:
		if not _preview_worker.is_started():
			_preview_worker = null
			_fail_preview("地图准备线程未成功启动。")
			return
		if not _preview_worker.is_alive():
			var preview_result: Variant = _preview_worker.wait_to_finish()
			_preview_worker = null
			if _preview_waiting:
				var error := _preview_result_error(preview_result)
				if not error.is_empty():
					_fail_preview(error)
					return
				_pending_preview = preview_result as Dictionary
				_loading_label.text = "正在安装地图"
				return # Allow the stage label to draw; install on the next UI tick.
	if _preview_waiting and (not _entering or _preview_display_waiting):
		_preview_mutex.lock()
		var stage := _preview_stage
		_preview_mutex.unlock()
		if stage!=_displayed_preview_stage:
			_displayed_preview_stage = stage
			_preview_stage_since = Time.get_ticks_msec()
		var prolonged := Time.get_ticks_msec()-_preview_stage_since>=15000
		_loading_label.text = stage+ ("（仍在处理，可取消准备）" if prolonged else "")
		_loading_back.text = "取消准备"
		_loading_back.visible = prolonged and not _entering
	if _worker==null:
		set_process(_preview_worker!=null or not _pending_preview.is_empty() or _preview_display_waiting)
		return
	if not _worker.is_started():
		_worker = null
		_entering = false
		_set_loading(false)
		_status.text = "进入失败：世界准备线程未成功启动。"
		set_process(false)
		return
	if _worker.is_alive(): return
	var world_result: Variant = _worker.wait_to_finish()
	_worker = null
	if not world_result is WorldBuildResult:
		_entering = false
		_set_loading(false)
		_status.text = "进入失败：世界准备线程未返回有效结果。"
		set_process(false)
		return
	var built := world_result as WorldBuildResult
	if not built.success:
		_entering = false
		_set_loading(false)
		_status.text = "进入失败："+built.error
		set_process(false)
		return
	if not _launch_presentation.is_empty():
		_pending_launch = built
		_pending_preview = _launch_presentation
		_launch_presentation = {}
		_preview_waiting = true
		_set_loading(true,"正在安装地图")
		return
	_finish_world_launch(built)

func _finish_world_launch(built: WorldBuildResult) -> void:
	set_process(false)
	var tree := get_tree()
	tree.set_meta(PREPARED_WORLD_META,built)
	# The built world now owns its foundation. Drop the menu handoff reference,
	# including an older preview foundation when this launch restored a save.
	if _content!=null: _content.provenance = null
	tree.set_meta(LAUNCH_MODE_META,"prepared_"+_launch_mode)
	_loading_layer.reparent(tree.root)
	tree.set_meta(PREPARED_LOADING_META,_loading_layer)
	if _renderer!=null and _preview_ready:
		_renderer.preserve_on_reparent = true
		_renderer.input_blocked = Callable()
		_renderer.label_exclusions = Callable()
		_renderer.reparent(tree.root)
		_controller.selection_changed.disconnect(_map_country_selected)
		_controller.select("")
		_controller.reparent(tree.root)
		tree.set_meta(PREPARED_MAP_META,_renderer)
		tree.set_meta(PREPARED_CONTROLLER_META,_controller)
		tree.set_meta(PREPARED_CONTENT_META,_content)
	var error := tree.change_scene_to_file(WORLD_SCENE)
	if error!=OK:
		for key: StringName in [PREPARED_WORLD_META,LAUNCH_MODE_META,PREPARED_MAP_META,PREPARED_CONTROLLER_META,PREPARED_CONTENT_META,PREPARED_LOADING_META]:
			if tree.has_meta(key): tree.remove_meta(key)
		if _renderer!=null and _renderer.get_parent()==tree.root:
			_renderer.reparent(self)
			_controller.reparent(self)
			_controller.selection_changed.connect(_map_country_selected)
			_renderer.preserve_on_reparent = false
			_renderer.input_blocked = _blocks_map
			_renderer.label_exclusions = _map_occlusions
		_loading_layer.reparent(self)
		_set_loading(false)
		_entering = false
		_status.text = "无法打开世界："+error_string(error)

func _select_theme() -> void:
	_preferences.theme = "paris_1877"
	_save_preferences()

func _volume_changed(value: float) -> void:
	_preferences.volume = value/100.0
	_save_preferences()

func _bgm_changed(value: bool) -> void:
	_preferences.bgm = value
	_save_preferences()

func _fullscreen_changed(value: bool) -> void:
	_preferences.fullscreen = value
	_save_preferences()

func _map_preference_changed(value: bool, key: String) -> void:
	_preferences[key] = value
	_controller.labels_enabled = bool(_preferences.labels)
	_save_preferences()

func _save_preferences() -> void:
	var error := SETTINGS.save(_preferences)
	if error != OK and _status!=null:
		_status.visible = true
		_status.text = "设置保存失败："+error_string(error)

func _input(event: InputEvent) -> void:
	if is_instance_valid(_map_acceptance): return
	if _entering or (_loading_layer!=null and _loading_layer.visible): return
	if not event is InputEventKey: return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode not in [KEY_ESCAPE,KEY_BACKSPACE]: return
	var focus := get_viewport().gui_get_focus_owner()
	if key.keycode==KEY_BACKSPACE and (focus is LineEdit or focus is TextEdit): return
	for choice: OptionButton in [_country_choice,_person_choice]:
		if choice != null and choice.get_popup().visible:
			choice.get_popup().hide()
			get_viewport().set_input_as_handled()
			return
	if _page!="home":
		_show_page("home")
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_preview_mutex.lock()
	_preview_generation += 1
	_preview_mutex.unlock()
	if _worker!=null and _worker.is_started(): _worker.wait_to_finish()
	if _preview_worker!=null and _preview_worker.is_started(): _preview_worker.wait_to_finish()
