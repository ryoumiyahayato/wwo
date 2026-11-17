extends Control
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
## One debug window, original application and original workspace owners.
var _bar: HBoxContainer
var _buttons: Dictionary = {}
var _last: Array = []
var _left: Label
var _right: Label
var _capture: Button
var _diagnostics_open: bool = false

static func enabled() -> bool:
	return OS.has_feature("debug") or "--dev-preview" in OS.get_cmdline_user_args()

func _ready() -> void:
	z_index=10 # Above the map, below MainShell (20), including menus/details.
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar=HBoxContainer.new()
	_bar.add_theme_constant_override("separation",4)
	add_child(_bar)
	_bar.resized.connect(_position)
	var caption := Label.new();caption.text="DEBUG";_bar.add_child(caption)
	for pair: Array in [["map","地图"],["training","坦克训练"],["close_training","结束训练"]]:
		var button := Button.new();button.text=pair[1];button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(_choose.bind(str(pair[0])))
		_bar.add_child(button);_buttons[pair[0]]=button
	var timer := Timer.new();timer.wait_time=.25;timer.timeout.connect(_refresh);add_child(timer);timer.start()
	get_tree().root.size_changed.connect(_position)
	_left=_diagnostic_label();_right=_diagnostic_label()
	_capture=Button.new();_capture.text="截图 F12";_capture.focus_mode=Control.FOCUS_NONE
	_capture.pressed.connect(_screenshot);_bar.add_child(_capture)
	var diagnostics := Button.new()
	diagnostics.text = UILocale.text("诊断")
	diagnostics.toggle_mode = true
	diagnostics.focus_mode = Control.FOCUS_NONE
	diagnostics.toggled.connect(func(open: bool) -> void:
		_diagnostics_open = open
		_diagnostics(get_tree().current_scene as FormalWorldApplication))
	_bar.add_child(diagnostics)
	_position.call_deferred();_refresh()

func _diagnostic_label() -> Label:
	var label := Label.new()
	label.theme=UIDrawing.shell_theme()
	label.add_theme_font_size_override("font_size",11)
	label.add_theme_color_override("font_color",Color(.90,.94,.92))
	label.add_theme_color_override("font_outline_color",Color(0,0,0,.95))
	label.add_theme_constant_override("outline_size",3)
	var background := StyleBoxFlat.new();background.bg_color=Color(.025,.04,.045,.78)
	background.content_margin_left=7;background.content_margin_right=7
	background.content_margin_top=6;background.content_margin_bottom=6
	label.add_theme_stylebox_override("normal",background)
	label.custom_minimum_size.x=290;label.size.x=290
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _position() -> void:
	_bar.position=Vector2(maxf(8,get_tree().root.size.x-_bar.size.x-12),get_tree().root.size.y-_bar.size.y-8)
	_left.position=Vector2(8,158)
	_right.position=Vector2(maxf(8,get_tree().root.size.x-310),158)

func input_rect() -> Rect2:
	return Rect2(_bar.position,_bar.size)

func _screenshot() -> void:
	var app := get_tree().current_scene as FormalWorldApplication
	if app==null:return
	var capture: Node=app.map_renderer.get("screenshot") as Node
	if is_instance_valid(capture) and not bool(capture.get("busy")):
		var result: Dictionary=await capture.call("capture","unified-debug")
		_capture.tooltip_text=str(result.get("png",result.get("error","")))

func _diagnostics(app: FormalWorldApplication) -> void:
	var map_open := app!=null and app.main_shell!=null and app.main_shell.current_page=="map"
	_left.visible = _diagnostics_open and map_open
	_right.visible = _left.visible
	if not _left.visible: return
	if app==null or app._world==null:
		_left.text="DEBUG · "+str(ProjectSettings.get_setting("application/config/build_label",""))
		_right.text=UILocale.text("等待原世界就绪")
		return
	var r := app.map_renderer
	r.observation_profile=true
	var c := app.map_controller.region_camera
	var center := r.unit_at(r.size*.5)
	var ll := RegionProjection.lon_lat(center) if not center.is_zero_approx() else Vector2(INF,INF)
	var local_source := r.local_content.content if r.local_content!=null else null
	var left: Array[String]=["DEBUG · "+UILocale.text("当前源码" if OS.has_feature("editor") else "EXE快照"),
		UILocale.text("世界ID ")+str(app._world.get_instance_id()),UILocale.text("原时钟 %d min · 暂停 %s")%[app._world.game_clock.total_minutes(),app.time_control.paused],
		UILocale.text("工作区 ")+UILocale.text("军事" if is_instance_valid(app._terrain_observation) and not app._debug_terrain_parked else app.main_shell.current_page),
		UILocale.text("相机 ")+("CITY" if c.local_active else "REGION" if c.active else "WORLD"),
		UILocale.text("比例 %.3f m/px")%r._strategic_mpp(),UILocale.text("中心 %.5f, %.5f")%[ll.x,ll.y],
		UILocale.text("相机域 %.1f km")%c.extent_km,UILocale.text("边界受限 %s · local抑制 %s")%[c.boundary_limited,c.local_suppressed],
		UILocale.text("本地源 ")+str(local_source.metadata.get("id",local_source.metadata.get("content_path",UILocale.text("已加载"))) if local_source!=null else UILocale.text("未加载")),
		UILocale.text("最近拒绝 ")+str(r.observation_camera_rejection)]
	var costs := r.observation_costs
	if app.map_controller.map_mode=="military":
		var grid_km := int(r._military_grid_step_m/1000)
		left.append(UILocale.text("军事投影格 %d × %d km") % [grid_km,grid_km])
	var right: Array[String]=["FPS %d · process %.2f ms"%[Engine.get_frames_per_second(),Performance.get_monitor(Performance.TIME_PROCESS)*1000.0],
		UILocale.text("地图CPU %.2f ms")%(float(costs.get("map_us",0))*.001),
		UILocale.text("准备 %.2f / 视图 %.2f / 提交 %.2f ms")%[float(costs.get("preparation_us",0))*.001,float(costs.get("view_us",0))*.001,float(costs.get("commit_us",0))*.001],
		UILocale.text("绘制批次 %d")%Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		UILocale.text("纹理 %.1f / 缓冲 %.1f MiB")%[Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)/1048576.0],
		"WORLD LOD "+r._world_layer.active_lod,"REGION LOD "+r._region_layer.active_lod,
		UILocale.text("地图批次 %d / %d")%[r._world_layer._batches.size(),r._region_layer._batches.size()],
		UILocale.text("区域河线可见 %s")%r._region_layer.has_visible_kind("river"),
		UILocale.text("世界河线可见 %s")%r._world_layer.has_visible_kind("river"),
		UILocale.text("待准备 %s")%r._has_pending_preparation(),
		UILocale.text("边界待退役 %d")%r._overlay_retiring.size(),
		UILocale.text("城市水面 ")+str(r.region_view.city.water_state().get("lod","")),
		UILocale.text("城市网格 %d · 待载 %d")%[r.region_view.city_cache_count(),r.region_view.city_pending_count()],
		UILocale.text("物流 %d 城 · %d 组联系")%[(r._logistics_observation.get("nodes",[]) as Array).size(),(r._logistics_observation.get("links",[]) as Array).size()]]
	if is_instance_valid(app._terrain_observation):
		var terrain := app._terrain_observation
		var training: Node=terrain.get("_training") as Node
		left.append(UILocale.text("训练保留 %s")%app._debug_terrain_parked)
		left.append(UILocale.text(str(terrain.get("_status").get("text"))))
		if training!=null:
			var status: Dictionary=training.call("get_player_status")
			right.append(UILocale.text("训练 ")+str(status.get("state","")))
			right.append(UILocale.text("主炮余弹 ")+str(status.get("ammo",{}).get("total",UILocale.text("未知"))))
	_left.text="\n".join(left)
	_right.text="\n".join(right)

func _refresh() -> void:
	# GUI picking follows tree order, independently of CanvasItem z_index.
	# Keep native dock buttons reachable after a new main scene is installed;
	# z_index still leaves diagnostics below the ordinary shell panels.
	if get_index()!=get_tree().root.get_child_count()-1:
		get_tree().root.move_child(self,get_tree().root.get_child_count()-1)
	var app := get_tree().current_scene as FormalWorldApplication
	_diagnostics(app)
	var ready := app!=null and app._world!=null
	var training := ready and is_instance_valid(app._terrain_observation)
	var state := [ready,training]
	if state==_last:return
	_last=state
	for button: Button in _buttons.values(): button.disabled=not ready
	(_buttons.close_training as Button).visible=training
	_position.call_deferred()

func _choose(workspace: String) -> void:
	var app := get_tree().current_scene as FormalWorldApplication
	if app!=null: app.debug_select_workspace(workspace)
	_refresh()
