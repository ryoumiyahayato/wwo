extends Node
## Isolated native measurement scene, excluded from the product release.
var app: FormalWorldApplication
var output: String
var rows: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var origin_usec: int
var stage_name: String = "startup"
var saved: Dictionary

func _ready() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(1280,720)
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

func _strategic() -> Dictionary:
	var loader: Variant = app.map_renderer.get("strategic_content")
	var layer: Variant = app.map_renderer.get("strategic_layer")
	return {} if loader == null or layer == null else {"content":loader.metrics.duplicate(true),"layer":layer.metrics.duplicate(true),"prepares":layer.prepare_count,"lod":layer.active_lod,"ready":layer.ready,"places":layer.visible_places.keys(),"processing":app.map_renderer.is_processing(),"batches":layer.get("_batches").size()}

func _row() -> Dictionary:
	var renderer := app.map_renderer
	return {"t_sec":(Time.get_ticks_usec()-origin_usec)/1000000.0,"stage":stage_name,"pid":OS.get_process_id(),"tracked_ram":OS.get_static_memory_usage(),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"frames_drawn":Engine.get_frames_drawn(),"render_draw_count":renderer.render_draw_count,"view_update_count":renderer.view_update_count,"cpu_projection_count":renderer.cpu_projection_count,"process_seconds":Performance.get_monitor(Performance.TIME_PROCESS),"local":app.map_controller.region_camera.local_active,"mpp":app.map_controller.region_camera.km_per_pixel*1000.0,"strategic":_strategic(),"local_metrics":renderer.local_layer.metrics.duplicate(true),"local_places":renderer.local_layer.visible_places.keys()}

func _record() -> void:
	var row := _row()
	rows.append(row)
	var live := FileAccess.open(output+"/live.json",FileAccess.WRITE)
	live.store_string(JSON.stringify(row))

func _sample(name: String, duration: float, action: String = "") -> void:
	stage_name = name
	print("STAGE ",name)
	var start := _row()
	var started := Time.get_ticks_usec()
	var previous := started
	var intervals: Array[int] = []
	var index: int = 0
	while Time.get_ticks_usec()-started<int(duration*1000000.0):
		var direction := 1.0 if index%240<120 else -1.0
		if action != "":
			var camera := app.map_controller.region_camera
			if camera.active:
				if action == "pan": camera.pan(Vector2(direction,0),app.map_renderer.size)
				else: camera.zoom_at(app.map_renderer.size*0.5,pow(1.001,direction),app.map_renderer.size)
			else:
				if action == "pan": app.map_controller._rotate_view(Vector2(direction*.001,0))
				else: app.map_controller.zoom *= pow(1.001,direction)
			app.map_controller.view_changed.emit()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		intervals.append(now-previous)
		previous = now
		index += 1
	intervals.sort()
	stages.append({"name":name,"duration_sec":(Time.get_ticks_usec()-started)/1000000.0,"start":start,"end":_row(),"frames":intervals.size(),"median_usec":intervals[intervals.size()/2],"p95_usec":intervals[int(intervals.size()*.95)],"p99_usec":intervals[int(intervals.size()*.99)],"max_usec":intervals[-1]})
	_store()

func _settle() -> void:
	var deadline := Time.get_ticks_msec()+25000
	await get_tree().process_frame
	while Time.get_ticks_msec()<deadline:
		var strategic := _strategic()
		if not app.map_renderer.is_processing() and (strategic.is_empty() or bool(strategic.ready)): break
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout

func _region(location: Vector2, mpp: float) -> void:
	stage_name = "prepare"
	var started := Time.get_ticks_usec()
	app.map_controller.region_camera.enter(GlobeProjection.lon_lat_to_unit(location),app.map_renderer.size*.5,mpp/1000.0,0,app.map_renderer.size)
	app.map_controller.view_changed.emit()
	app.map_renderer.set("_last_pointer",app.map_renderer.size*.5)
	app.map_renderer._ensure_view()
	app.map_renderer._evaluate_scale()
	await _settle()
	transitions.append({"location":location,"mpp":mpp,"elapsed_usec":Time.get_ticks_usec()-started,"end":_row()})

func _capture(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(output+"/"+name+".png")

func _store() -> void:
	var file := FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"debug":OS.is_debug_build(),"rows":rows,"stages":stages,"transitions":transitions,"save_unchanged":saved==(app.get("_persistence") as FormalPersistence).snapshot(),"schema":FormalPersistence.SCHEMA_ID},"  "))

func _run() -> void:
	await get_tree().create_timer(8).timeout
	app.main_shell.set_page("map")
	app.map_controller.labels_enabled = true
	if "--caption" in OS.get_cmdline_user_args():
		await _region(Vector2(51,42),1200)
		_capture("caspian_caption")
		await _region(LocalSpatialLoader.ANCHOR,1200)
		for mode: String in ["political","fulfillment","shortage"]:
			app._on_action_requested("map_mode:"+mode)
			await get_tree().create_timer(0.5).timeout
			_capture("paris_"+mode)
		app._on_action_requested("map_mode:political")
		await _region(Vector2(-85,43),1200)
		_capture("final_great_lakes")
		await _sample("delivery_idle",60)
		await _sample("delivery_pan",30,"pan")
		await _sample("delivery_zoom",30,"zoom")
		_store()
		get_tree().quit(0)
		return
	if "--supplement" in OS.get_cmdline_user_args():
		for location: Array in [["moscow_mid",37.62,55.75],["china_north_mid",117,39.5],["india_ganges_mid",82.5,25.5],["argentina_mid",-59.5,-33.5],["egypt_mid",30.5,30],["south_africa_nodes_mid",28,-27],["caspian_mid",51,42],["baikal_mid",107,53],["great_lakes_mid",-85,43],["siberian_corridor_mid",90,54]]:
			await _region(Vector2(float(location[1]),float(location[2])),1200)
			_capture(str(location[0]))
		await _region(Vector2(-85,43),1200)
		await _sample("final_lakes_idle",60)
		await _sample("final_lakes_pan",30,"pan")
		await _sample("final_lakes_zoom",30,"zoom")
		app.map_controller.focus(GlobeProjection.lon_lat_to_unit(Vector2(10,49)))
		await get_tree().create_timer(2).timeout
		await _sample("final_world_idle",60)
		await _sample("final_world_pan",30,"pan")
		await _sample("final_world_zoom",30,"zoom")
		await _region(LocalSpatialLoader.ANCHOR,75)
		_capture("final_paris_local")
		await _sample("final_paris_local_pan",30,"pan")
		await _sample("final_paris_local_zoom",30,"zoom")
		_store()
		get_tree().quit(0)
		return
	if "--quick" in OS.get_cmdline_user_args():
		await _region(Vector2(-85,43),1200)
		_capture("quick")
		await _sample("quick_idle",8)
		await _sample("quick_pan",8,"pan")
		get_tree().quit(0)
		return
	var locations: Array = [["western_europe",10,49],["eastern_europe",35,53],["east_asia",114,34],["japan",137,36],["india",78,23],["north_america",-85,40],["south_america",-59,-24],["north_africa",25,29],["southern_africa",26,-29]]
	for location: Array in locations:
		var coordinate := Vector2(float(location[1]),float(location[2]))
		app.map_controller.focus(GlobeProjection.lon_lat_to_unit(coordinate))
		await get_tree().create_timer(2).timeout
		_capture(str(location[0])+"_world")
		for scale: float in [4500,1200]:
			await _region(coordinate,scale)
			_capture(str(location[0])+("_far" if scale==4500 else "_mid"))
	for lap: int in range(3):
		for location: Array in [["europe",10,49],["east_asia",114,34],["north_america",-85,40],["south_america",-59,-24],["africa",25,-10],["india",78,23],["japan",137,36],["europe",10,49]]:
			await _region(Vector2(float(location[1]),float(location[2])),1200)
			await _sample("travel_"+str(lap)+"_"+str(location[0]),3)
	for location: Array in [["europe",10,49],["east_asia",114,34],["north_america",-85,40]]:
		await _region(Vector2(float(location[1]),float(location[2])),1200)
		await _sample(str(location[0])+"_idle",60)
		await _sample(str(location[0])+"_pan",30,"pan")
		await _sample(str(location[0])+"_zoom",30,"zoom")
	await _region(LocalSpatialLoader.ANCHOR,1200)
	_capture("paris_strategic_detail")
	await _region(LocalSpatialLoader.ANCHOR,188)
	_capture("paris_local_far")
	await _region(LocalSpatialLoader.ANCHOR,75)
	_capture("paris_local_close")
	await _sample("paris_local_idle",60)
	await _sample("paris_local_pan",30,"pan")
	await _sample("paris_local_zoom",30,"zoom")
	await _region(Vector2(116.4,39.9),100)
	_capture("beijing_stays_region")
	await _region(Vector2(-74,40.7),100)
	_capture("new_york_stays_region")
	app.main_shell.set_page("person")
	await _sample("person_return_idle",30)
	_store()
	get_tree().quit(0)
