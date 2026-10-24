extends Node
signal prepared
signal global_requested
signal host_returned(result: Dictionary)
var battle: Node3D
var region: Node3D
var navigation: Control
var port := preload("res://triple/port.gd").new()
var ready_battle := false
var explicitly_paused := false
var summary: Label
var information: Label
var notice: Label
var slider: HSlider
var pause_button: Button
var globe_button: Button
var tick := 0.0
var view_tick := 0.0
var startup_ms := 0
var samples: Array = []
var stage_snapshots: Array = []
var request_path := "res://triple/default_request.json"
var return_path := "user://host_return.json"
var output_dir := "user://captures"
var initial: Dictionary = {}
var status_message := ""
var source_note := ""
var vehicle_caption := ""

func _enter_tree() -> void:
	if "--background-record" in OS.get_cmdline_user_args():
		get_window().unfocusable=true
		get_window().position=Vector2i(6000,6000)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit=false
	var begin:=Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--host-request="):request_path=arg.trim_prefix("--host-request=")
		if arg.begins_with("--host-return="):return_path=arg.trim_prefix("--host-return=")
		if arg.begins_with("--capture-dir="):output_dir=arg.trim_prefix("--capture-dir=")
	if not port.read_request(request_path):
		push_error(port.error);return
	battle=preload("res://triple/battle.gd").new();battle.process_mode=Node.PROCESS_MODE_PAUSABLE;add_child(battle)
	battle.map_requested.connect(func() -> void: navigation.locate(true))
	battle.choose_game_mode("skirmish")
	for i: int in 30:
		await get_tree().physics_frame
		if battle.crew_host.person_ids.size()==5:break
	if not port.install(battle):push_error(port.error);return
	for child: Node in battle.find_children("*","",true,false):
		if child.process_mode==Node.PROCESS_MODE_ALWAYS:child.process_mode=Node.PROCESS_MODE_PAUSABLE
	for child: Node in battle.get_children():
		if child is WorldEnvironment:
			child.environment.fog_enabled=false
			child.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
			child.environment.ambient_light_color=Color("abb8bf")
			child.environment.ambient_light_energy=.7
	battle.battle_controls.request_camera_snap()
	region=preload("res://continuous/region_world.gd").new();add_child(region);region.build()
	for material: ShaderMaterial in [battle.terrain_damage.close_material,battle.terrain_damage.far_material]:
		material.shader=preload("res://continuous/ground.gdshader")
		material.set_shader_parameter("region_color",load("res://continuous/assets/region_color.png"))
		material.set_shader_parameter("region_normal",load("res://continuous/assets/region_normal.png"))
		material.set_shader_parameter("native_terrain",true)
		material.set_shader_parameter("land_control",load("res://ridgevale/assets/land_control.png"))
		material.set_shader_parameter("grass_detail",load("res://cedar/assets/grass_detail.png"))
		material.set_shader_parameter("detail_coverage",battle.terrain_damage.coverage_texture)
	battle.terrain_damage.far_material.set_shader_parameter("far_mesh",true)
	_build_ui()
	ready_battle=true
	initial=port.snapshot(battle)
	_refresh_ui()
	startup_ms=Time.get_ticks_msec()-begin
	region.update_view(Vector2.ZERO,14)
	prepared.emit()
	if "--tour" in OS.get_cmdline_user_args() or "--input-tour" in OS.get_cmdline_user_args():
		var tour:=preload("res://continuous/tour.gd").new();tour.shell=self;add_child(tour)

func _build_ui() -> void:
	var canvas:=CanvasLayer.new();canvas.layer=110;add_child(canvas)
	navigation=preload("res://continuous/navigation.gd").new();canvas.add_child(navigation);navigation.setup(self)
	var theme:=Theme.new();theme.default_font=load("res://cedar/system_font.tres");theme.default_font_size=15;navigation.theme=theme
	var top:=ColorRect.new();top.color=Color(.035,.07,.075,.95);top.position=Vector2.ZERO;top.size=Vector2(1280,78);navigation.add_child(top)
	summary=_label(Vector2(20,8),Vector2(780,26),19)
	globe_button=_button("返回球面 / Tab",Vector2(930,4),Vector2(155,30),func() -> void:global_requested.emit())
	battle.battle_controls.presentation_exclusions.append(Rect2(0,0,1280,78))
	_label(Vector2(20,44),Vector2(270,23),14).text="滚轮缩放 · 中键/远景拖动平移"
	_button("5 km",Vector2(310,42),Vector2(68,30),func() -> void:navigation.set_range(5000))
	_button("25 km",Vector2(385,42),Vector2(75,30),func() -> void:navigation.set_range(25000))
	_button("50 km",Vector2(467,42),Vector2(75,30),func() -> void:navigation.set_range(50000))
	_button("定位车长 / Home",Vector2(550,42),Vector2(151,30),func() -> void:navigation.locate(true))
	slider=HSlider.new();slider.position=Vector2(725,48);slider.size=Vector2(230,20);slider.min_value=log(14);slider.max_value=log(50000);slider.step=.001;navigation.add_child(slider)
	slider.value_changed.connect(func(value: float) -> void:navigation.set_range(exp(value)))
	pause_button=_button("暂停 / P",Vector2(980,42),Vector2(106,30),toggle_pause)
	_button("F9 截图",Vector2(1100,42),Vector2(140,30),capture)
	_button("交还宿主",Vector2(1100,4),Vector2(140,30),return_to_host)
	information=_label(Vector2(897,96),Vector2(365,158),15)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.03,.075,.075,.85);style.content_margin_left=12;style.content_margin_top=8;style.set_corner_radius_all(8);information.add_theme_stylebox_override("normal",style)
	notice=_label(Vector2(270,690),Vector2(980,26),14)

func _label(at: Vector2,extent: Vector2,pixels: int) -> Label:
	var label:=Label.new();label.position=at;label.size=extent;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_size_override("font_size",pixels);label.add_theme_color_override("font_color",Color("fff4d5"));navigation.add_child(label);return label

func _button(text: String,at: Vector2,extent: Vector2,action: Callable) -> Button:
	var button:=Button.new();button.text=text;button.position=at;button.size=extent;button.pressed.connect(action);navigation.add_child(button);return button

func toggle_pause() -> void:
	if port.closed:return
	explicitly_paused=not explicitly_paused
	get_tree().paused=explicitly_paused
	pause_button.text="继续 / P" if explicitly_paused else "暂停 / P"

func return_to_host() -> void:
	if not ready_battle or port.closed:return
	if port.export_return(battle,return_path):
		explicitly_paused=true;get_tree().paused=true
		status_message="状态已交还外部宿主。租约关闭；请由宿主签发后续请求。"
		host_returned.emit(port.returned)
	else:status_message=port.error

func _process(delta: float) -> void:
	if not ready_battle:return
	view_tick+=delta;tick+=delta
	if view_tick>.2:
		view_tick=0;region.update_view(navigation.center,navigation.span)
	if tick<.25:return
	tick=0
	_refresh_ui()

func _refresh_ui() -> void:
	var body: Dictionary=battle.player_combat.crew[0]
	var ammo: Dictionary=battle.vehicle_ammo.status("player_vehicle","primary")
	var p: Vector3=navigation.controlled_position()
	var arm: String=str(body.parts.get("left_arm","unknown"))
	var arm_text: String={"healthy":"无伤","injured":"受伤","destroyed":"损毁"}.get(arm,arm)
	var identity_text: String=str(body.person_id)
	if identity_text.length()>34:identity_text=identity_text.substr(0,30)+"\n"+identity_text.substr(30)
	summary.text="WWO 连续军事地形  ·  观察范围 %.2f km  ·  %s"%[navigation.span/1000,"车辆/步战近景" if navigation.span<160 else "同一位置 / 地理观察"]
	information.text="%s\n%s\n原车 player_vehicle · 车组5人\nHP %.0f · 左臂%s  |  主炮 %d\n本地 X %.1f / Z %.1f m\n模拟 t %.2f s · 事件 %d\n%s · 近景块 %d / 中景块 %d"%[body.display_name,identity_text,body.hp,arm_text,ammo.total,p.x,p.z,battle.elapsed,battle.shot_audit.size(),"明确暂停" if explicitly_paused else "持续计算",battle.terrain_damage.chunks.size(),region.loaded_mid]
	if not vehicle_caption.is_empty():information.text=information.text.replace("原车 player_vehicle · 车组5人",vehicle_caption)
	notice.text="训练地理：外围概略地形与布局，仅观察；Ridgevale 5 km可驾驶。未写入正式WWO。G显示索引。"
	if not source_note.is_empty():notice.text=source_note
	if not status_message.is_empty():notice.text=status_message
	slider.set_value_no_signal(log(navigation.target_span))
	if samples.size()<360:
		samples.append({"span":navigation.span,"time":battle.elapsed,"fps":Engine.get_frames_per_second(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"static_memory":OS.get_static_memory_usage(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"mid_tiles":region.loaded_mid,"native_chunks":battle.terrain_damage.chunks.size()})

func capture() -> void:
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(path)
	get_viewport().get_texture().get_image().save_png(path+"/map_%s_%.0fm.png"%[Time.get_datetime_string_from_system().replace(":","-"),navigation.span])

func record_stage(name: String) -> void:
	stage_snapshots.append({"name":name,"range":navigation.span,"center":[navigation.center.x,navigation.center.y],"observer_instance":navigation.camera.get_instance_id(),"stage_instance":battle.stage.get_instance_id(),"terrain_instance":battle.terrain_damage.get_instance_id(),"state":port.snapshot(battle),"paused":get_tree().paused})

func save_observations(path: String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"startup_ms":startup_ms,"region_build_ms":region.build_ms,"maximum_mid_install_ms":region.maximum_install_ms,"samples":samples,"stages":stage_snapshots,"initial":initial,"final":port.snapshot(battle)},"\t"))

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if ready_battle:save_observations("user://last_observation.json")
		get_tree().paused=false;get_tree().quit()
