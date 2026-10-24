extends Node
## One retained local solver. The globe is a read-only presentation host.
var globe: Control
var global_ui: Control
var local_container: SubViewportContainer
var local_viewport: SubViewport
var local_shell: Node
var mode := "global"
var loading := false
var view_entries: Array = []
var snapshots: Array = []
var input_observations: Dictionary = {}
var samples: Array = []
var selected_info: Label
var state_info: Label
var progress: Label
var enter_button: Button
var heading: Label
var caption: Label
var output_dir := "user://globe_captures"
var tick := 0.0
var startup_tick := 0
var shared_ready_ms := 0
var first_local_ms := 0
var active_caption := ""
var runtime_catalog: VNextSpatialCatalog
var runtime_anchor_place_id := "place:paris"

func _enter_tree() -> void:
	if "--background-record" in OS.get_cmdline_user_args():
		get_window().unfocusable=true;get_window().position=Vector2i(6000,6000)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;get_tree().auto_accept_quit=false
	startup_tick=Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output_dir=arg.trim_prefix("--capture-dir=")
	local_container=SubViewportContainer.new();local_container.stretch=true;local_container.size=Vector2(1280,720);local_container.hide();add_child(local_container)
	local_viewport=SubViewport.new();local_viewport.size=Vector2i(1280,720);local_viewport.own_world_3d=true;local_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;local_container.add_child(local_viewport)
	_build_global_ui()
	globe.loaded.connect(func() -> void:
		shared_ready_ms=Time.get_ticks_msec()-startup_tick
		progress.text="WWO全球底图已就绪 · 24分片 / %d面"%globe.face_count
		if "--globe-tour" in OS.get_cmdline_user_args():
			var tour: Node=load("res://global_link/tour.gd").new();tour.host=self;add_child(tour))
	globe.region_selected.connect(func(available: bool) -> void:
		enter_button.disabled=not available or loading
		selected_info.text=_selected_text() if available else "当前位置未开放局部战场。\n可选择巴黎旁的训练放置区域。")
	globe.coordinate_selected.connect(func(ll: Vector2) -> void:progress.text="选点 %.5f°E / %.5f°N；选择不改变人物位置。"%[ll.x,ll.y])

func _build_global_ui() -> void:
	var canvas:=CanvasLayer.new();canvas.layer=120;add_child(canvas)
	global_ui=Control.new();global_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(global_ui)
	var theme:=Theme.new();theme.default_font=load("res://cedar/system_font.tres");theme.default_font_size=16;global_ui.theme=theme
	var bg:=ColorRect.new();bg.color=Color("081820");bg.size=Vector2(1280,720);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;global_ui.add_child(bg)
	heading=_label(Vector2(24,10),Vector2(1225,30),24);heading.text="WWO 全球军事地图 · 正式地理底图 / 隔离接续宿主"
	_button("军事观察",Vector2(24,49),Vector2(118,31),func() -> void:globe.set_military(true))
	_button("行政参考",Vector2(151,49),Vector2(118,31),func() -> void:globe.set_military(false))
	_button("地球全貌",Vector2(294,49),Vector2(118,31),func() -> void:globe.whole_earth())
	_button("定位巴黎入口",Vector2(422,49),Vector2(148,31),func() -> void:globe.focus_training(false))
	_button("查看50公里范围",Vector2(579,49),Vector2(166,31),func() -> void:globe.focus_training(true))
	_button("F9 截图",Vector2(759,49),Vector2(118,31),capture)
	globe=load("res://global_link/shared_globe.gd").new();globe.runtime_catalog=runtime_catalog;globe.anchor_place_id=runtime_anchor_place_id;globe.position=Vector2(0,86);globe.size=Vector2(940,590);global_ui.add_child(globe)
	var panel:=ColorRect.new();panel.position=Vector2(950,96);panel.size=Vector2(312,548);panel.color=Color("102d35");panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;global_ui.add_child(panel)
	selected_info=_label(Vector2(968,112),Vector2(275,215),16);selected_info.text="从WWO球面选择入口。\n\n拖动旋转 / 滚轮缩放\n\n巴黎旁有一处50公里训练区域。\n局部地形不代表真实巴黎地貌。"
	enter_button=_button("进入局部军事视图",Vector2(968,336),Vector2(275,42),enter_local);enter_button.disabled=true
	state_info=_label(Vector2(968,396),Vector2(275,226),15);state_info.text="局部战场尚未装配。\n首次进入后保留同一实例。"
	progress=_label(Vector2(24,681),Vector2(1230,25),14)
	caption=_label(Vector2(250,643),Vector2(850,31),19)

func _selected_text() -> String:
	return "训练入口 · Paris / 巴黎\nplace:paris\n%.4f°E / %.4f°N\n\n50×50 km · X东 / Z南\nRidgevale等为训练布局\n未做真实地理配准"%[globe.anchor_ll.x,globe.anchor_ll.y]

func _label(at: Vector2,extent: Vector2,pixels: int) -> Label:
	var label:=Label.new();label.position=at;label.size=extent;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_color_override("font_color",Color("f0e5c8"));label.add_theme_font_size_override("font_size",pixels);global_ui.add_child(label);return label

func _button(text: String,at: Vector2,extent: Vector2,action: Callable) -> Button:
	var button:=Button.new();button.text=text;button.position=at;button.size=extent;button.pressed.connect(action);global_ui.add_child(button);return button

func enter_local() -> void:
	if not globe.is_loaded or not globe.selected or loading:return
	print("GLOBE_LOCAL_ENTER_REQUEST")
	var begin:=Time.get_ticks_msec();loading=true;enter_button.disabled=true;globe.controller.suspend_motion()
	if local_shell==null:
		progress.text="装配原局部战场；不创建第二份人物或弹药owner。"
		local_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		local_shell=load("res://continuous/main.tscn").instantiate();configure_local_shell(local_shell);local_viewport.add_child(local_shell)
		await local_shell.prepared
		local_shell.global_requested.connect(return_global)
		local_shell.navigation.span=50000;local_shell.navigation.target_span=50000
		first_local_ms=Time.get_ticks_msec()-begin
	local_shell.navigation.observation_enabled=true
	local_shell.battle.battle_controls.map_observing=local_shell.navigation.span>160
	mode="local";loading=false;global_ui.hide();local_container.show();local_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	globe.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var entry: Dictionary={"action":"enter_local","ms":Time.get_ticks_msec()-begin,"first":view_entries.is_empty(),"same_shell":local_shell.get_instance_id()}
	view_entries.append(entry)
	enter_button.disabled=false
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		entry["first_draw_ms"]=Time.get_ticks_msec()-begin
	entry["presented_mode"]=mode

func return_global() -> void:
	if local_shell==null or mode!="local":return
	var begin:=Time.get_ticks_msec()
	local_shell.navigation.observation_enabled=false
	local_shell.battle.battle_controls.drive=Vector2.ZERO
	local_shell.battle.battle_controls.map_observing=true
	local_shell.battle.battle_controls._pointer(-1,Vector2.ZERO,false)
	local_container.hide();local_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	global_ui.show();globe.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;mode="global"
	globe.local_available=true;globe.vehicle_local=local_shell.battle.hero.position;globe.person_local=local_shell.navigation.controlled_position();globe.commander_dismounted=local_shell.battle.player_infantry_controller.active();globe.whole_earth()
	var entry: Dictionary={"action":"return_global","ms":Time.get_ticks_msec()-begin,"same_shell":local_shell.get_instance_id()}
	view_entries.append(entry)
	progress.text="已回同一球面位置。局部模拟继续；观察不重置人物、弹药或事件。"
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		entry["first_draw_ms"]=Time.get_ticks_msec()-begin
	entry["presented_mode"]=mode

func configure_local_shell(_shell: Node) -> void:
	pass

func _process(delta: float) -> void:
	tick+=delta
	if is_instance_valid(caption):caption.text=active_caption
	if tick<.25:return
	tick=0
	if not globe.is_loaded:progress.text=globe.status
	if local_shell!=null and local_shell.ready_battle:
		var body: Dictionary=local_shell.battle.player_combat.crew[0]
		var ammo: Dictionary=local_shell.battle.vehicle_ammo.status("player_vehicle","primary")
		var p: Vector3=local_shell.navigation.controlled_position()
		var arm: String=str(body.parts.left_arm)
		var arm_text: String="受伤" if arm=="injured" else "完好" if arm=="healthy" else arm
		globe.vehicle_local=local_shell.battle.hero.position;globe.person_local=p;globe.commander_dismounted=local_shell.battle.player_infantry_controller.active();globe.commander_name=body.display_name;globe.local_available=true
		var ll:=RegionProjection.lon_lat(globe.unit_from_local(p))
		state_info.text="原车组状态\n%s\nplayer_vehicle / 车组5人\nHP %.0f · 左臂%s\n主炮 %d · 装填 %.1f秒\n事件 %d · 局部 t %.2f秒\n%s\n训练映射 %.5f / %.5f\nX %.1f / Z %.1f m"%[body.person_id,body.hp,arm_text,ammo.total,ammo.get("remaining",0.0),local_shell.battle.shot_audit.size(),local_shell.battle.elapsed,"明确暂停" if get_tree().paused else "持续计算",ll.x,ll.y,p.x,p.z]
	if samples.size()<600:
		samples.append({"mode":mode,"at_ms":Time.get_ticks_msec()-startup_tick,"fps":Engine.get_frames_per_second(),"static_memory":OS.get_static_memory_usage(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"local_loaded":local_shell!=null})

func capture(stage: String="manual") -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output_dir);DirAccess.make_dir_recursive_absolute(path)
	get_viewport().get_texture().get_image().save_png(path+"/%s_%s_%s.png"%[stage,Time.get_datetime_string_from_system().replace(":","-"),mode])

func record(name: String) -> void:
	var row: Dictionary={"name":name,"mode":mode,"paused":get_tree().paused,"selected":globe.selected,"anchor_place_id":"place:paris","anchor_lon_lat":[globe.anchor_ll.x,globe.anchor_ll.y],"globe_orientation":str(globe.controller.orientation()),"regional":globe.controller.region_camera.active,"region_origin":[globe.controller.region_camera.origin.x,globe.controller.region_camera.origin.y],"region_km_per_pixel":globe.controller.region_camera.km_per_pixel}
	var footprint_ll: Array=[]
	for i: int in [0,8,16,24]:
		var ll:=RegionProjection.lon_lat(globe.footprint()[i]);footprint_ll.append([ll.x,ll.y])
	row["training_footprint_lon_lat"]=footprint_ll
	if local_shell!=null and local_shell.ready_battle:
		row["state"]=local_shell.port.snapshot(local_shell.battle)
		row["shell_instance"]=local_shell.get_instance_id();row["observer_instance"]=local_shell.navigation.camera.get_instance_id();row["range"]=local_shell.navigation.span
		var p: Vector3=local_shell.battle.hero.position;var unit: Vector3=globe.unit_from_local(p);var ll:=RegionProjection.lon_lat(unit);var back:=RegionProjection.forward(unit,globe.anchor_frame)
		row["training_mapped_lon_lat"]=[ll.x,ll.y];row["projection_return_metres"]=[back.x*1000,-back.y*1000]
	snapshots.append(row)

func save_observations() -> void:
	var file:=FileAccess.open("user://globe_local_observation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"shared_ready_ms":shared_ready_ms,"shared_map_load_ms":globe.load_ms,"first_local_ms":first_local_ms,"material_update_max_ms":globe.material_ms,"relief_switch_max_ms":globe.relief_switch_max_ms,"input_observations":input_observations,"view_entries":view_entries,"samples":samples,"stages":snapshots},"\t"))

func _input(event: InputEvent) -> void:
	if mode=="global" and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F9:capture();get_viewport().set_input_as_handled()
		if event.keycode==KEY_P and local_shell!=null:local_shell.toggle_pause();get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if globe!=null and globe.is_loaded:record("window_closed");save_observations()
		get_tree().quit()
