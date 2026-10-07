extends Node
## Copied into isolated measurement exports; never included in the product pack.
var app: FormalWorldApplication
var output: String
var rows: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var origin_usec: int
var opened_usec: int
var last_row: int = 0
var stage_name: String = "startup"
var saved: Dictionary
var transitions: Array[Dictionary] = []
var drawing_baseline: int = 0

func _ready() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(1280, 720)
	origin_usec = Time.get_ticks_usec()
	app = (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	add_child(app)
	await get_tree().process_frame
	saved = (app.get("_persistence") as FormalPersistence).snapshot()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_record)
	add_child(timer)
	timer.start()
	_run()

func _record() -> void:
	var row := _row()
	row["render_draw_count"] = app.map_renderer.get("render_draw_count")
	row["view_update_count"] = app.map_renderer.get("view_update_count")
	row["cpu_projection_count"] = app.map_renderer.get("cpu_projection_count")
	row["last_submit_usec"] = app.map_renderer.get("last_submit_usec")
	row["submit_parts"] = app.map_renderer.get("last_submit_parts")
	row["engine_fps"] = Performance.get_monitor(Performance.TIME_FPS)
	row["process_frames"] = Engine.get_process_frames()
	row["process_seconds"] = Performance.get_monitor(Performance.TIME_PROCESS)
	rows.append(row)
	var live := FileAccess.open(output+"/live.json",FileAccess.WRITE)
	live.store_string(JSON.stringify(row))

func _row() -> Dictionary:
	var renderer := app.map_renderer
	var camera := app.map_controller.region_camera
	return {"t_sec":(Time.get_ticks_usec()-origin_usec)/1000000.0,"stage":stage_name,"pid":OS.get_process_id(),"tracked_ram":OS.get_static_memory_usage(),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"frames_drawn":Engine.get_frames_drawn(),"load_count":app.historical_content.local_spatial.load_count,"prepare_count":renderer.local_layer.prepare_count,"available_lods":renderer.local_layer.available_lods.duplicate(),"preparing":renderer.local_layer.preparing,"ready":renderer.local_layer.ready,"lod":renderer.local_layer.active_lod,"local":camera.local_active,"mpp":camera.km_per_pixel*1000.0,"places":renderer.local_layer.visible_places.size(),"load_metrics":renderer.local_layer.metrics.duplicate(true)}

func _sample(name: String, duration: float, action: String = "") -> void:
	stage_name = name
	print("STAGE ",name)
	var started := Time.get_ticks_usec()
	var previous := started
	var intervals: Array[int] = []
	var index: int = 0
	var pixel := app.map_renderer.size*0.5
	if action == "right":
		_button(MOUSE_BUTTON_RIGHT,true,pixel)
	while Time.get_ticks_usec()-started < int(duration*1000000.0):
		var direction := 1.0 if index%240<120 else -1.0
		if action == "pan" or action == "zoom":
			var camera := app.map_controller.region_camera
			if camera.active:
				if action == "pan": camera.pan(Vector2(direction,0.0),app.map_renderer.size)
				else: camera.zoom_at(pixel,pow(1.001,direction),app.map_renderer.size)
			else:
				if action == "pan": app.map_controller._rotate_view(Vector2(direction*0.001,0.0))
				else: app.map_controller.zoom *= pow(1.001,direction)
			app.map_controller.view_changed.emit()
		elif action == "right":
			var motion := InputEventMouseMotion.new()
			motion.position = pixel+Vector2(direction,0.0)
			motion.relative = Vector2(direction,0.0)
			motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
			app.map_renderer._gui_input(motion)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		intervals.append(now-previous)
		previous = now
		index += 1
	if action == "right": _button(MOUSE_BUTTON_RIGHT,false,pixel)
	intervals.sort()
	stages.append({"name":name,"duration_sec":(Time.get_ticks_usec()-started)/1000000.0,"frames":intervals.size(),"p50_usec":intervals[intervals.size()/2],"p95_usec":intervals[int(intervals.size()*.95)],"p99_usec":intervals[int(intervals.size()*.99)],"max_usec":intervals[-1],"start_sec":(started-origin_usec)/1000000.0,"end":_row()})
	_store()

func _button(button: MouseButton, down: bool, pixel: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.button_index = button
	event.pressed = down
	app.map_renderer._gui_input(event)

func _scale(mpp: float) -> void:
	var renderer := app.map_renderer
	var pixel := renderer.size*0.5
	stage_name = "prepare_"+str(mpp)
	var started := Time.get_ticks_usec()
	var before := renderer.local_layer.metrics.duplicate(true)
	var frame_intervals: Array[int] = []
	var previous := started
	app.map_controller.region_camera.enter(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR),pixel,mpp/1000.0,0.0,renderer.size)
	app.map_controller.view_changed.emit()
	renderer.set("_last_pointer",pixel)
	renderer._ensure_view()
	renderer._evaluate_scale()
	var deadline := Time.get_ticks_msec()+15000
	await get_tree().process_frame
	frame_intervals.append(Time.get_ticks_usec()-previous)
	previous = Time.get_ticks_usec()
	while (renderer.local_layer.preparing or not renderer.local_layer.ready) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_intervals.append(now-previous)
		previous = now
	frame_intervals.sort()
	transitions.append({"mpp":mpp,"policy":renderer.local_layer.get("residency_policy"),"elapsed_usec":Time.get_ticks_usec()-started,"start_sec":(started-origin_usec)/1000000.0,"p95_frame_usec":frame_intervals[int(frame_intervals.size()*.95)],"max_frame_usec":frame_intervals[-1],"before":before,"after":renderer.local_layer.metrics.duplicate(true),"local":app.map_controller.region_camera.local_active})
	await get_tree().create_timer(5.0).timeout

func _capture(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(output+"/"+name+".png")

func _store() -> void:
	var file := FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"debug":OS.is_debug_build(),"origin_usec":origin_usec,"opened_usec":opened_usec,"rows":rows,"stages":stages,"transitions":transitions,"save_unchanged":saved==(app.get("_persistence") as FormalPersistence).snapshot(),"schema":FormalPersistence.SCHEMA_ID},"  "))

func _run() -> void:
	if "--comparisons" in OS.get_cmdline_user_args():
		await _comparisons()
		_store()
		get_tree().quit(0)
		return
	if "--quick" in OS.get_cmdline_user_args():
		app.main_shell.set_page("map")
		app.map_controller.focus(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR))
		await _sample("quick_world_idle",5.0)
		await _sample("quick_world_pan",5.0,"pan")
		(app.get_node("Background") as ColorRect).visible = false
		await _sample("quick_world_no_background",5.0,"pan")
		await _scale(1200.0)
		_capture("quick_mid")
		await _sample("quick_region_pan",5.0,"pan")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		await _sample("quick_region_no_vsync",5.0,"pan")
		Engine.max_fps = 0
		await _sample("quick_region_no_cap",5.0,"pan")
		var content_view := app.map_renderer.region_view
		content_view.container.visible = false
		await _sample("quick_region_without_canvas",5.0,"pan")
		content_view.container.visible = true
		await _scale(100.0)
		await _sample("quick_local_pan",5.0,"pan")
		get_tree().quit(0)
		return
	# Allow the external sampler to select and focus this native window before
	# the complete 60-second reference interval begins.
	await get_tree().create_timer(30.0).timeout
	await _sample("person_idle",60.0)
	app.main_shell.set_page("map")
	app.map_controller.labels_enabled = true
	app.map_controller.focus(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR))
	opened_usec = Time.get_ticks_usec()
	await _sample("world_open_timeline",90.0)
	_capture("world")
	for pair: Array in [[4500.0,"far"],[2000.0,"mid_early"],[1200.0,"mid"],[700.0,"mid_near"],[350.0,"near"],[188.0,"handoff"],[75.0,"local"]]:
		await _scale(float(pair[0]))
		_capture(str(pair[1]))
		await _sample(str(pair[1])+"_idle",60.0 if str(pair[1]) in ["far","mid","near","local"] else 2.0)
	for area: String in ["world","region","local"]:
		if area == "world":
			app.map_controller.focus(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR))
			app.map_controller.zoom = 1.55
			app.map_controller.view_changed.emit()
			await get_tree().create_timer(3.0).timeout
		else: await _scale(1200.0 if area=="region" else 100.0)
		for action: String in (["pan","zoom"] if area=="local" else ["pan","zoom","right"]):
			await _sample(area+"_"+action,30.0,action)
	if "--policies" in OS.get_cmdline_user_args():
		await _ablation()
		await _policies()
	_store()
	get_tree().quit(0)

func _ablation() -> void:
	app.map_controller.focus(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR))
	app.map_controller.zoom = 1.55
	app.map_controller.view_changed.emit()
	var background := (app.get_node("Background") as ColorRect).material as ShaderMaterial
	var static_shader := background.shader
	OS.low_processor_usage_mode = false
	await get_tree().create_timer(2.0).timeout
	await _sample("ablation_static_continuous",60.0)
	OS.low_processor_usage_mode = true
	background.shader = load("res://baseline_background.gdshader") as Shader
	await get_tree().create_timer(2.0).timeout
	await _sample("ablation_time_on_demand",60.0)
	background.shader = static_shader
	await get_tree().create_timer(2.0).timeout
	await _sample("ablation_static_on_demand",60.0)

func _policies() -> void:
	for policy: String in ["all","adjacent","active"]:
		app.map_renderer.local_layer.residency_policy = policy
		await _scale(4500.0)
		await _sample("policy_"+policy+"_far",60.0)
		await _scale(1200.0)
		await _sample("policy_"+policy+"_mid",60.0)
		await _scale(188.0)
		await _sample("policy_"+policy+"_local",60.0)
		await _scale(4500.0)
		await _sample("policy_"+policy+"_return",3.0)
	await _scale(350.0)
	for style: int in [0,1,2]:
		app.map_renderer.local_layer.rail_style = style
		app.map_controller.view_changed.emit()
		await get_tree().create_timer(.3).timeout
		_capture("rail_style_"+str(style))
		await _sample("rail_style_"+str(style)+"_pan",30.0,"pan")
	# Actual departure and return expose resource release and reupload timing.
	app.map_controller.region_camera.enter(GlobeProjection.lon_lat_to_unit(Vector2(116.4074,39.9042)),app.map_renderer.size*.5,.188,0.0,app.map_renderer.size)
	app.map_controller.view_changed.emit()
	app.map_renderer._ensure_view()
	app.map_renderer._evaluate_scale()
	await _sample("unsupported_beijing",10.0)
	_capture("beijing")
	app.map_controller.region_camera.enter(GlobeProjection.lon_lat_to_unit(Vector2(-74.006,40.7128)),app.map_renderer.size*.5,.188,0.0,app.map_renderer.size)
	app.map_controller.view_changed.emit()
	app.map_renderer._ensure_view()
	app.map_renderer._evaluate_scale()
	await _sample("unsupported_new_york",10.0)
	_capture("new_york")
	await _scale(188.0)
	await _sample("paris_return",10.0)

func _comparisons() -> void:
	app.main_shell.set_page("map")
	app.map_controller.labels_enabled = true
	app.map_controller.focus(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR))
	# A smooth approach exposes adjacent prefetch, unlike the main direct jump.
	for policy: String in ["all","adjacent","active"]:
		app.map_renderer.local_layer.residency_policy = policy
		app.map_renderer.local_layer.release_gpu()
		await _scale(350.0)
		await _sample("approach_"+policy+"_near",10.0)
		await _scale(188.0)
		await _sample("approach_"+policy+"_local",3.0)
	app.map_renderer.local_layer.residency_policy = "active"
	for style: int in [0,1,2]:
		app.map_renderer.local_layer.rail_style = style
		# Reset the exact camera before each style, including after oscillating pan.
		await _scale(350.0)
		_capture("rail_style_"+str(style))
		await _sample("rail_style_"+str(style)+"_pan",30.0,"pan")
