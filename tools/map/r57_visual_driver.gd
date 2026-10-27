extends Node
## Finite ordinary-window capture through the real menu/world and existing probe.
## External entry only; never exported or used by normal play. Save calls are
## confined to the explicit economic-action route's dedicated user directory.
var renderer: Object
var controller: Object
var output: String = OS.get_environment("WWO_VISUAL_OUTPUT")
var results: Array = []
var tracking: bool = false
var last_state: Array = []
var changes: Array = []
var decode_events: Array = []
var decode_mutex := Mutex.new()
var window_started: int = 0
var last_tick: int = 0
var intervals: Array[float] = []
var taking_point: bool = false
var selection_ms: int = 0
var dynamic_recording: bool = false
var dynamic_frames: Array = []
var dynamic_states: Array = []
var dynamic_key: String = ""
var dynamic_previous: Dictionary = {}
var dynamic_ring: Array = []
var dynamic_captures: Array = []
var dynamic_pending: Dictionary = {}
var dynamic_case: String = ""
var dynamic_phase: String = ""
var dynamic_cases_captured: Dictionary = {}
var dynamic_readback: Array = []
var dynamic_capture_view: SubViewport
var dynamic_marker: ColorRect
var dynamic_pre: Dictionary = {}
var dynamic_sync_errors: int = 0
var dynamic_root_offset: int = -1
var dynamic_calibration: Array = []
var dynamic_world_exits: Array = []
var acceptance: String = OS.get_environment("WWO_VISUAL_ACCEPTANCE")
var acceptance_phase: String = ""
var slow_frames: Array = []
var acceptance_idle: Array = []
var acceptance_unfocused_frames: int = 0
var perf_recording: bool = false
var perf_phase: String = ""
var perf_started: int = 0
var perf_previous: int = 0
var perf_frames: Array = []
var perf_phases: Array = []
var perf_inputs: Array = []
var perf_pre_draw: int = 0
var perf_draw_us: int = 0
var perf_last_input: int = 0
var perf_pending_input: int = -1
var perf_relief: MapRelief
var perf_region: LocalSpatialLayer
var perf_world: LocalSpatialLayer
var perf_local: LocalSpatialLayer
var perf_last_state: Array = []
var perf_events: Array = []
var perf_begin_snapshot: Dictionary = {}
var perf_binding_variant: String = "candidate"
var perf_comparison_scene: PackedScene
var perf_comparison_script: GDScript
var perf_profile_inventories: Array = []

func _process(_delta: float) -> void:
	if perf_recording: performance_tick()
	if not tracking or renderer==null: return
	if not get_window().has_focus(): acceptance_unfocused_frames+=1
	var now := Time.get_ticks_usec()
	if last_tick>0 and not taking_point: intervals.append((now-last_tick)/1000.0)
	if last_tick>0 and not taking_point and now-last_tick>33000 and not acceptance.is_empty() and slow_frames.size()<2000:
		slow_frames.append({"ms":Time.get_ticks_msec(),"duration_ms":(now-last_tick)/1000.0,"phase":acceptance_phase,"preparing":(renderer.get("relief") as MapRelief).preparing(),"geometry_preparing":renderer.get("_region_layer").get("preparing")})
	last_tick = now
	var relief: MapRelief = renderer.get("relief")
	var residents: Array = []
	for id: String in relief.textures: residents.append([id,(relief.textures[id] as Texture2D).get_instance_id()])
	residents.sort_custom(func(a: Array,b: Array) -> bool: return str(a[0])<str(b[0]))
	var state: Array = [relief._wanted.duplicate(),relief._surface_active.duplicate(),residents,relief._level if relief.preparing() else "",relief._surface_refinement_weight,(renderer.get("_region_layer") as LocalSpatialLayer).active_lod]
	if state!=last_state:
		changes.append({"ms":Time.get_ticks_msec()-window_started,"state":state})
		last_state=state

func tracked_decode(level: String, admitted: Dictionary) -> Dictionary:
	var now := Time.get_ticks_msec()
	var result := GeographyLoader.decode_relief(level,admitted)
	decode_mutex.lock()
	decode_events.append({"id":level,"began_ms":now,"finished_ms":Time.get_ticks_msec(),"image":result.has("image"),"errors":result.errors})
	decode_mutex.unlock()
	return result

func _ready() -> void:
	if acceptance=="terrain-region":
		set_process(false)
		terrain_region_run.call_deferred()
		return
	if not OS.get_user_data_dir().get_file().begins_with("WWO_R57_Visual_") or output.is_empty():
		get_tree().quit(2)
		return
	run.call_deferred()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and acceptance=="performance":
		print("R57_PERFORMANCE_WINDOW_CLOSE_REQUEST phase=",perf_phase)

func _exit_tree() -> void:
	if acceptance!="performance" or not perf_recording: return
	perf_recording=false
	acceptance_save("interrupted_phase",{"phase":perf_phase,"frames":perf_frames,"inputs":perf_inputs,"events":perf_events,"reason":"Observer exited before finite route completion; excluded from completed runs"})
	var scope_path := OS.get_environment("WWO_PERF_SCOPE")
	if not scope_path.is_empty():acceptance_save("function_costs_partial",load(scope_path).call("snapshot"))

func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func run() -> void:
	if acceptance=="performance" and not performance_binding_comparison():
		get_tree().quit(7)
		return
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: Object = get_tree().current_scene
	var selection_started := Time.get_ticks_msec()
	if not acceptance.is_empty():
		get_window().grab_focus();await wait_seconds(.4)
		for attempt: int in range(3):
			for button: Node in menu.find_children("*","Button",true,false):
				if (button as Button).text=="开始" and (button as Button).is_visible_in_tree() and not (button as Button).disabled:
					selection_started=Time.get_ticks_msec()
					await mouse_button((button as Button).get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
					await mouse_button((button as Button).get_global_rect().get_center(),MOUSE_BUTTON_LEFT,false)
					break
			await wait_seconds(.2)
			if str(menu.get("_page"))!="home":break
	else: menu.call("_show_page","selection")
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		renderer = menu.get("_renderer")
		if renderer!=null and bool(menu.get("_preview_ready")) and str(renderer.call("current_view_map_status").get("state"))=="installed": break
	if renderer==null or not bool(menu.get("_preview_ready")):
		acceptance_save("menu_failure",{"page":menu.get("_page"),"preview_error":menu.get("_preview_error"),"preview_ready":menu.get("_preview_ready"),"focused":get_window().has_focus()})
		acceptance_image("menu_failure");get_tree().quit(3);return
	selection_ms=Time.get_ticks_msec()-selection_started
	if acceptance=="startup":
		controller=menu.get("_controller")
		await acceptance_startup(menu)
		return
	if OS.get_environment("WWO_MATERIAL_RESUME")=="1": menu.call("_enter_world","load",4)
	elif not OS.get_environment("WWO_LIVING_UI").is_empty() or OS.get_environment("WWO_MATERIAL_TRADE")=="1":
		# Preview installation rebuilds the selection panel. Let its deferred
		# container layout finish before using the visible button's coordinates.
		await get_tree().process_frame
		await wait_seconds(.3)
		for attempt: int in range(2):
			if not is_instance_valid(menu) or bool(menu.get("_entering")): break
			var enter: Button = menu.get("_enter_button")
			if enter==null or enter.disabled:
				acceptance_save("entry_failure",{"stage":"button_unavailable","page":menu.get("_page"),"preview_ready":menu.get("_preview_ready")})
				get_tree().quit(4); return
			print("LIVING_ENTER_CLICK ",enter.get_global_rect())
			await mouse_button(enter.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
			await mouse_button(enter.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,false)
			await wait_seconds(.3)
	elif OS.get_environment("WWO_CONTINUOUS_RESUME")=="1": menu.call("_enter_world","load",3)
	else: menu.call("_enter_world","new",0)
	var world: Object
	deadline = Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene!=null and scene!=menu and scene.get("_simulation_step")!=null: world=scene; break
	if world==null:
		acceptance_save("entry_failure",{"stage":"world_timeout","scene":str(get_tree().current_scene),"page":menu.get("_page") if is_instance_valid(menu) else "freed","entering":menu.get("_entering") if is_instance_valid(menu) else false})
		get_tree().quit(4); return
	renderer = world.get("map_renderer")
	controller = world.get("map_controller")
	if acceptance=="repair": get_window().title="WWO R57 定点回归 · 自动结束"
	var time_control: Object = world.get("time_control")
	if not OS.get_environment("WWO_LIVING_UI").is_empty() and acceptance=="economic-action":
		await acceptance_living_ui(world)
		return
	if not bool(time_control.get("paused")): time_control.call("toggle_pause")
	world.get("main_shell").call("set_page","map")
	controller.call("set_map_mode","geographic")
	if acceptance=="economic":
		await acceptance_economic_integration(world)
		return
	if acceptance=="economic-action":
		if OS.get_environment("WWO_MATERIAL_TRADE")=="1" and world.get("_world").economy_r1.config.case_id=="FORMAL_PARIS_TWO_EMPLOYERS_OPENING_R1":
			await acceptance_material_trade(world)
		elif not OS.get_environment("WWO_EMPLOYMENT_CASE").is_empty():
			await acceptance_multi_employer(world)
		elif not OS.get_environment("WWO_RESIDENT_CASE").is_empty():
			await acceptance_ordinary_residents(world)
		elif world.get("_world").get("economy_r1")!=null and world.get("_world").get("economy_r1").get("config").get("case_id")=="FORMAL_PARIS_WORKSHOP_OPENING_R1":
			await acceptance_economic_participation(world)
		else:await acceptance_economic_action(world)
		return
	if acceptance=="performance":
		await acceptance_interaction_performance(world)
		return
	if acceptance=="visual":
		await acceptance_visual(world)
		return
	if acceptance=="features":
		await acceptance_features(world)
		return
	if acceptance=="repair":
		await acceptance_repair(world)
		return
	if acceptance in ["dynamic","rapid-entry"]:
		if OS.get_environment("WWO_VISUAL_PLACES")=="source-trace":
			await acceptance_source_trace(world)
			return
		await dynamic_run(world)
		return
	if OS.get_environment("WWO_VISUAL_FOUNDATION")=="1":
		await foundation_review(world)
		return
	if OS.get_environment("WWO_VISUAL_DYNAMIC")=="1":
		await dynamic_run(world)
		return
	if OS.get_environment("WWO_VISUAL_MODE_REVIEW")=="1":
		await mode_review(world)
		return
	if OS.get_environment("WWO_VISUAL_STABILITY")=="1":
		await stability_run(world)
		return
	var places: Array = [] if OS.get_environment("WWO_VISUAL_UI_ONLY")=="1" else [["spain",-7.5,42.5,400.0],["vienna",16.4,48.0,400.0],["swiss",6.5,46.6,300.0],["russia",36.5,56.0,400.0],["benelux",4.9,51.7,400.0]]
	var water_only := OS.get_environment("WWO_VISUAL_WATER_ONLY")=="1"
	if water_only: places=places.filter(func(p: Array) -> bool: return str(p[0])=="benelux")
	for place: Array in places:
		print("R57_VISUAL begin ",place[0])
		var began := Time.get_ticks_msec()
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"))
		await wait_seconds(2.0)
		print("R57_VISUAL settling ",place[0])
		deadline = Time.get_ticks_msec()+25000
		while Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
			var relief: Object = renderer.get("relief")
			var loading: Object = renderer.get("strategic_content")
			var layer: Object = renderer.get("_region_layer")
			if not bool(relief.call("preparing")) and not bool(loading.call("preparing")) and not bool(layer.get("preparing")) and not bool(renderer.get("_map_canvas_dirty")): break
		await wait_seconds(.8)
		if water_only:
			await settle()
			await wait_seconds(10)
		print("R57_VISUAL draw ",place[0])
		# A static cached window need not schedule another frame. This finite
		# observer explicitly requests one GPU frame rather than awaiting an
		# unsolicited post_draw forever. Normal game rendering is unchanged.
		RenderingServer.force_draw(false)
		if not water_only: get_viewport().get_texture().get_image().save_png(output+"/"+str(place[0])+".png")
		var points: Array = []
		for fraction: Vector2 in ([] if water_only else [Vector2(.35,.45),Vector2(.5,.5),Vector2(.7,.65)]):
			renderer.call("_dump_terrain_point",renderer.get("size")*fraction)
			RenderingServer.force_draw(false)
			var report: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://r57_terrain_point.json"))
			points.append(report)
		var layer: LocalSpatialLayer = renderer.get("_region_layer")
		var water := {"features":0,"draw_batches":0,"visible_batches":0,"historical_sea_visible":false}
		if layer.content_reference()!=null:
			for feature: Dictionary in layer.content_reference().features:
				if "benelux_hydro_overview_r46" in str(feature.id): water.features+=1
		for batch: Dictionary in layer._batches:
			if "benelux" not in str(batch.get("source_feature_id","")) and str(batch.get("water_class",""))!="historical_sea_reference": continue
			water.draw_batches+=1
			if bool(batch.get("visible",false)): water.visible_batches+=1
			if "zuiderzee" in str(batch.get("source_feature_id","")) and bool(batch.get("visible",false)): water.historical_sea_visible=true
		if water_only:
			var state := layer.diagnostic_state()
			water["geometry"]={"active":state.active,"content_regions":state.content_regions,"published":state.published,"preparing":state.preparing,"error":state.error}
			water["loader_preparing"]=renderer.get("strategic_content").call("preparing")
			water["failure"]=str(renderer.get("_strategic_failure"))
		results.append({"place":place,"probe":points,"settle_and_capture_ms":Time.get_ticks_msec()-began,"benelux":water})
		if water_only: print("R57_VISUAL Benelux ",JSON.stringify(water))
		print("R57_VISUAL captured ",place[0])
	if not results.is_empty(): FileAccess.open(output+"/bindings.json",FileAccess.WRITE).store_string(JSON.stringify(results))
	if not places.is_empty() and not water_only:
		for direction: int in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			for i: int in range(35 if direction==MOUSE_BUTTON_WHEEL_UP else 10):
				var wheel := InputEventMouseButton.new()
				wheel.position = renderer.get("size")*.5
				wheel.button_index = direction
				wheel.pressed = true
				renderer.call("_gui_input",wheel)
				await wait_seconds(.03)
			print("R57_ZOOM ",direction," mpp=",controller.region_camera.km_per_pixel*1000.0," local=",controller.region_camera.local_active)
	await check_ui(world.get("main_shell"))
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.5,48.5)))
	controller.call("set_world_zoom",.86)
	await wait_seconds(1.0)
	print("R57_VISUAL WORLD textures=",renderer.get("relief").get("textures").keys())
	world.set("_departure_target","menu")
	world.call("_leave_world")
	await wait_seconds(.5)
	get_tree().quit(0)

func acceptance_save(name: String, value: Variant) -> void:
	var archive:=OS.get_environment("WWO_VISUAL_RECORD_ARCHIVE")
	if not archive.is_empty():
		var records: Dictionary = {}
		if FileAccess.file_exists(archive):
			var previous: Variant=JSON.parse_string(FileAccess.get_file_as_bytes(archive).decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
			if not previous is Dictionary: push_error("Cannot read compact run records");return
			records=previous
		records[output.get_file()+"/"+name]=value
		FileAccess.open(archive,FileAccess.WRITE).store_buffer(JSON.stringify(records).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
		return
	FileAccess.open(output+"/"+name+".json",FileAccess.WRITE).store_string(JSON.stringify(value))

func acceptance_performance() -> Dictionary:
	var sorted:=intervals.duplicate();sorted.sort()
	return {"frames":sorted.size(),"unfocused_frames":acceptance_unfocused_frames,"p50_ms":sorted[int(sorted.size()*.5)] if not sorted.is_empty() else 0,"p95_ms":sorted[int((sorted.size()-1)*.95)] if not sorted.is_empty() else 0,"max_ms":sorted.back() if not sorted.is_empty() else 0,"over500":slow_frames.filter(func(v:Dictionary)->bool:return float(v.duration_ms)>500).duplicate(),"slow_over33":slow_frames.duplicate(),"scope":"Normal process intervals; endpoint point-probe readback excluded; no dynamic GPU observer"}

func acceptance_startup(menu: Object) -> void:
	tracking=true;last_tick=0;intervals.clear();slow_frames.clear();acceptance_phase="selection_world_input"
	var beginning: Vector3=controller.orientation()*Vector3.FORWARD
	for cycle: int in range(3):
		var pos: Vector2=renderer.get("size")*Vector2(.4,.5)
		var press:=InputEventMouseButton.new();press.position=pos;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;renderer.call("_gui_input",press)
		var motion:=InputEventMouseMotion.new();motion.position=pos+Vector2(45,10);motion.relative=Vector2(45,10);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;renderer.call("_gui_input",motion)
		press.position=motion.position;press.pressed=false;renderer.call("_gui_input",press)
		for direction: int in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var wheel:=InputEventMouseButton.new();wheel.position=pos;wheel.button_index=direction;wheel.pressed=true;renderer.call("_gui_input",wheel);await wait_seconds(.3)
		await wait_seconds(1)
	tracking=false
	acceptance_save("startup",{"selection_ms":selection_ms,"renderer":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"window":TerrainPixelSource.serial(get_viewport().get_visible_rect().size),"isolation":OS.get_user_data_dir(),"ready":menu.get("_preview_ready"),"preview_error":menu.get("_preview_error"),"world_rotation_changed":beginning!=controller.orientation()*Vector3.FORWARD,"world_zoom":controller.zoom,"textures":(renderer.get("relief") as MapRelief).textures.keys(),"performance":acceptance_performance()})
	print("R57_ACCEPT startup selection_ms=",selection_ms)
	get_tree().quit(0)

func acceptance_image(label: String) -> void:
	var requested:=OS.get_environment("WWO_VISUAL_IMAGE_LABELS").split(",",false)
	if OS.get_environment("WWO_VISUAL_NO_IMAGES")=="1" and requested.is_empty(): return
	if not requested.is_empty() and label not in requested:return
	RenderingServer.force_draw(false)
	var image:=get_viewport().get_texture().get_image()
	if OS.get_environment("WWO_VISUAL_ACCEPTANCE") not in ["economic","economic-action"]:image.resize(800,450,Image.INTERPOLATE_BILINEAR)
	image.save_png(output+"/"+label+".png")

func acceptance_visual(world: Object) -> void:
	var places: Array=[
		["oceania_interior",133.88,-23.7,500.0],["oceania_join",178.3,-17.8,1500.0],["oceania_coast",113.7,-25.0,500.0],
		["south_america_interior",-62.0,-5.0,500.0],["south_america_join",-64.0,14.8,1500.0],["south_america_coast",-70.6693,-33.4489,500.0],
		["africa_interior",23.0,-4.0,500.0],["africa_join",18.0,15.8,1500.0],["africa_coast",18.4241,-33.9249,500.0],
		["south_asia_interior",77.209,28.6139,500.0],["south_asia_join",90.0,30.1,500.0],["south_asia_coast",139.76,35.68,500.0],
		["north_america_interior",-105.27,39.74,500.0],["north_america_join",-60.0,58.8,1500.0],["north_america_coast",-122.42,37.775,500.0],
		["north_asia_interior",104.286,52.287,500.0],["north_asia_join",64.1,56.0,500.0],["north_asia_coast",131.885,43.115,500.0],
		["paris",2.3522,48.8566,250.0],["spain",-7.5,42.5,250.0],["vienna",16.4,48.2,500.0],["alps",8.0,46.5,500.0],
		["warsaw",21.0122,52.2297,500.0],["petersburg",30.3351,59.9343,250.0],["east",31.6,59.95,150.0],["ladoga",31.5,60.35,150.0],
		["benelux",4.9,51.7,500.0],["greenland_center",-42.0,73.5,1500.0],["greenland_west",-49.5,69.2,1500.0]]
	var requested:=OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty():places=places.filter(func(v:Array)->bool:return str(v[0]) in requested)
	for place: Array in places:
		world.get("main_shell").set("_context_open",false)
		acceptance_phase=str(place[0])+"_first_entry";tracking=true;last_tick=0;intervals.clear();slow_frames.clear()
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,2.6,0.0,renderer.get("size"))
		await settle()
		var floor_mpp:float=(renderer.get("relief") as MapRelief).minimum_observation_mpp(Vector2(place[1],place[2]))
		var scale:=maxf(float(place[3]),floor_mpp*1.001)
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,scale*.001,0.0,renderer.get("size"))
		var prepared_ms:=await settle();await wait_seconds(1)
		var point:=state_point(str(place[0]));point["requested_mpp"]=place[3];point["center_floor_mpp"]=floor_mpp;point["prepared_ms"]=prepared_ms
		acceptance_phase=str(place[0])+"_installed"
		if str(place[0]).begins_with("greenland") or place[0]=="africa_join":
			await wait_seconds(10);point["idle10"]=state_point(str(place[0])+"_10")
			await wait_seconds(20);point["idle30"]=state_point(str(place[0])+"_30")
		else: await wait_seconds(2)
		point["snapshot"]=dynamic_snapshot()
		if str(place[0]).begins_with("greenland") or place[0]=="africa_join":
			point["seam_probes"]=[]
			var coordinates:Array=[Vector2(-48.2,73.5),Vector2(-48.0,73.5),Vector2(-47.8,73.5),Vector2(-47.625,73.5),Vector2(-47.4,73.5)] if str(place[0]).begins_with("greenland") else [Vector2(18,17.5),Vector2(18,18.0),Vector2(18,18.25),Vector2(18,18.5),Vector2(18,19.0)]
			for coordinate:Vector2 in coordinates:
				var probe_pixel:Vector2=controller.region_camera.project(GlobeProjection.lon_lat_to_unit(coordinate))
				if not Rect2(Vector2.ZERO,renderer.get("size")).has_point(probe_pixel):continue
				point.seam_probes.append(state_point("seam_"+str(coordinate),probe_pixel))
		tracking=false;point["performance"]=acceptance_performance()
		acceptance_image(str(place[0]))
		controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(1.5)
		point["world_exit"]={"textures":(renderer.get("relief") as MapRelief).textures.keys(),"texture_mem":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"video_mem":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
		results.append(point);acceptance_save("visual",{"selection_ms":selection_ms,"device":RenderingServer.get_video_adapter_name(),"windows":results})
		print("R57_ACCEPT visual ",place[0]," actual_mpp=",point.mpp," active=",point.active," errors=",point.errors)
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func acceptance_features(world: Object) -> void:
	var shell:MainShell=world.get("main_shell")
	if OS.get_environment("WWO_FEATURE_LABELS_ONLY")=="1":
		controller.call("set_map_mode","political")
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await settle()
		var was_enabled:bool=controller.labels_enabled
		if not was_enabled:controller.call("toggle_labels")
		await settle();await wait_seconds(1)
		var label_result:Dictionary={"enabled":controller.labels_enabled,"symbols":(renderer.get("_symbol_layout") as Array).size(),"labels":(renderer.get("_symbol_text") as Array).size()}
		var center:Vector2=renderer.get("size")*.5
		await mouse_button(center,MOUSE_BUTTON_LEFT,true)
		var motion:=InputEventMouseMotion.new();motion.position=center;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		for delta:Vector2 in [Vector2(60,0),Vector2(-60,0)]:
			motion.relative=delta;motion.position+=delta;renderer.call("_gui_input",motion);await wait_seconds(.07)
		await mouse_button(motion.position,MOUSE_BUTTON_LEFT,false);await settle()
		label_result["labels_after_pan"]=(renderer.get("_symbol_text") as Array).size()
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await settle();await wait_seconds(1)
		label_result["point"]=state_point("paris_labels_on")
		label_result["names"]=(renderer.get("_symbol_text") as Array).map(func(row:Dictionary)->String:return str(row.name))
		label_result["valid_fonts"]=(renderer.get("_symbol_text") as Array).all(func(row:Dictionary)->bool:return row.font is Font)
		acceptance_image("paris_labels_on")
		if not was_enabled:controller.call("toggle_labels")
		controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)));controller.call("set_world_zoom",.86);await settle();await wait_seconds(.3)
		label_result["world_textures"]=(renderer.get("relief") as MapRelief).textures.keys()
		label_result["region_batches"]=(renderer.get("_region_layer").get("_batches") as Array).size()
		acceptance_save("features-labels",label_result)
		world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0);return
	var observed:Array=[]
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.5,0.0,renderer.get("size"));await settle()
	tracking=true;last_tick=0;intervals.clear();slow_frames.clear()
	for cycle:int in range(3):
		for mode:String in ["geographic","political","fulfillment","shortage"]:
			acceptance_phase="mode_"+mode
			shell.call("_activate","map_mode:"+mode);shell.set("_context_open",false);await settle();await wait_seconds(.5)
			var point:=state_point(mode+"_"+str(cycle));point["snapshot"]=dynamic_snapshot();point["admin_active"]=controller.call("administrative_layer_active")
			point["economic_available"]=[]
			for owner:String in renderer.get("political").get("economies"):
				if renderer.get("political").call("economic_available",owner):point.economic_available.append(owner)
			observed.append(point)
			if cycle==0:acceptance_image("mode_"+mode)
	tracking=false
	var feature_result:Dictionary={"mode_points":observed,"mode_performance":acceptance_performance()}
	shell.call("_activate","map_mode:political");await settle();shell.set("_map_modes_open",true);shell.call("queue_redraw");await wait_seconds(.2)
	feature_result["menu_actions"]=[]
	for hit:Dictionary in shell._hits:
		if str(hit.action).begins_with("map"):feature_result.menu_actions.append(hit.action)
	acceptance_image("political_menu");shell.set("_map_modes_open",false);shell.call("queue_redraw")
	var pixel:Vector2=renderer.get("size")*Vector2(.62,.55)
	await settle();await wait_seconds(.3)
	feature_result["country_query"]=renderer.call("_polity_at",pixel)
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=pixel;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;renderer.call("_gui_input",event);await get_tree().process_frame
	feature_result["country_selected"]=controller.selected_polity_id
	feature_result["country_attempts"]=[]
	for fraction:Vector2 in [Vector2(.5,.35),Vector2(.4,.45),Vector2(.65,.4)]:
		if controller.selected_polity_id==str(feature_result.country_query):break
		shell.set("_context_open",false);await wait_seconds(.25)
		var target:Vector2=renderer.get("size")*fraction
		var expected:String=renderer.call("_polity_at",target)
		await mouse_button(target,MOUSE_BUTTON_LEFT,true);await mouse_button(target,MOUSE_BUTTON_LEFT,false);await wait_seconds(.2)
		feature_result.country_attempts.append({"query":expected,"selected":controller.selected_polity_id,"place":controller.selected_place_id,"pixel":TerrainPixelSource.serial(target)})
		feature_result["country_selected"]=controller.selected_polity_id
	shell.set("_context_open",false)
	feature_result["place_pick"]={}
	for id:String in renderer.get("_symbol_hits"):
		var box:Rect2=renderer.get("_symbol_hits")[id]
		if not Rect2(Vector2(100,140),Vector2(1050,400)).has_point(box.get_center()):continue
		var expected:String=renderer.call("_place_at",box.get_center())
		if expected.is_empty():continue
		for pressed:bool in [true,false]:
			var event:=InputEventMouseButton.new();event.position=box.get_center();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;renderer.call("_gui_input",event);await get_tree().process_frame
		feature_result.place_pick={"expected":expected,"selected":controller.selected_place_id};break
	shell.set("_context_open",false)
	await check_ui(shell)
	shell.call("_set_messages_open",false);shell.call("set_page","map")
	var time_control:TimeControl=world.get("time_control")
	var clock:GameClock=world.get("_world").get("game_clock")
	var before:int=clock.total_minutes();await wait_seconds(1);var paused_after:int=clock.total_minutes()
	time_control.call("set_speed",1);await wait_seconds(1);time_control.call("toggle_pause")
	var running_after:int=clock.total_minutes()
	feature_result["clock"]={"before":before,"paused_after":paused_after,"running_after":running_after,"paused":time_control.paused}
	acceptance_phase="formal_daily_settlement";tracking=true;last_tick=0;intervals.clear();slow_frames.clear()
	time_control.call("set_speed",4)
	var deadline:int=Time.get_ticks_msec()+60000
	while clock.total_minutes()<1440 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not time_control.paused:time_control.call("toggle_pause")
	tracking=false
	feature_result["settlement"]={"minutes":clock.total_minutes(),"date":clock.current_date(),"performance":acceptance_performance()}
	feature_result["settled_modes"]=[]
	for mode:String in ["fulfillment","shortage"]:
		shell.call("_activate","map_mode:"+mode);shell.set("_context_open",false);await settle();await wait_seconds(.5)
		var row:=state_point("settled_"+mode);row["available_totals"]={};row["snapshot"]=dynamic_snapshot()
		for owner:String in renderer.get("political").get("economies"):
			if renderer.get("political").call("economic_available",owner):row.available_totals[owner]=(renderer.get("political").get("economies")[owner] as Dictionary).get("daily_totals",{})
		feature_result.settled_modes.append(row);acceptance_image("settled_"+mode)
	shell.call("_activate","map_mode:geographic")
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(4.9,51.7)),renderer.get("size")*.5,.5,0.0,renderer.get("size"));await settle();await wait_seconds(10)
	var layer:LocalSpatialLayer=renderer.get("_region_layer")
	var water:Dictionary={"features":0,"batches":0,"zuiderzee_visible":false}
	if layer.content_reference()!=null:
		for feature:Dictionary in layer.content_reference().features:
			if "benelux_hydro_overview_r46" in str(feature.id):water.features+=1
	for batch:Dictionary in layer._batches:
		if "benelux" in str(batch.get("source_feature_id","")) or str(batch.get("water_class",""))=="historical_sea_reference":water.batches+=1
		if "zuiderzee" in str(batch.get("source_feature_id","")) and bool(batch.get("visible",false)):water.zuiderzee_visible=true
	water["geometry"]=layer.diagnostic_state();(water.geometry as Dictionary).erase("last_result")
	feature_result["water"]=water
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.5,48.5)));controller.call("set_world_zoom",.86);await wait_seconds(2)
	feature_result["world_remaining"]=(renderer.get("relief") as MapRelief).textures.keys()
	acceptance_save("features",feature_result);print("R57_ACCEPT features saved")
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func state_point(label: String, point_pixel: Vector2 = Vector2(-1,-1)) -> Dictionary:
	taking_point=true
	# Away from the capital star and centre label; preserve the exact inverse
	# projected coordinate, not an assumed city-centre terrain colour.
	var probe_pixel:Vector2=renderer.get("size")*Vector2(.62,.55) if point_pixel.x<0 else point_pixel
	renderer.call("_dump_terrain_point",probe_pixel)
	RenderingServer.force_draw(false)
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string("user://r57_terrain_point.json"))
	var point: Dictionary = raw[0] if not raw.is_empty() else {}
	var layers: Array = []
	for layer: Dictionary in point.get("layers",[]):
		var precision := (layer.precision as Dictionary).duplicate()
		for key: String in ["dem_cells","cover_cells"]:
			var cells := precision.get(key,[]) as Array
			precision[key+"_total"]=cells.size()
			precision[key]=cells.filter(func(cell: Dictionary) -> bool:
				var b := cell.bounds as Array
				return point.lon_lat[0]>=b[0] and point.lon_lat[0]<=b[2] and point.lon_lat[1]>=b[1] and point.lon_lat[1]<=b[3])
		layers.append({"id":layer.id,"path":layer.path,"encoding":layer.encoding,"precision":precision,"output_m":layer.display_grid_m_ns,"weight":layer.spatial_weight,"cover_weight":layer.cover_weight,"rgba":layer.sample_rgba,"decoded":layer.decoded,"cpu_mip_estimate":layer.cpu_isotropic_mip_estimate})
	var result := {"label":label,"ms":Time.get_ticks_msec()-window_started,"mpp":point.get("mpp"),"ll":point.get("lon_lat"),"center":point.get("camera_center"),"viewport":point.get("viewport"),"bearing":point.get("bearing"),"mode":point.get("map_mode"),"framebuffer":point.get("framebuffer"),"layers":layers,"wanted":point.get("relief_wanted"),"active":point.get("relief_active"),"geometry":point.get("geometry"),"errors":point.get("relief_errors"),"selector":point.get("selector_explanation"),"minimum_mpp":(renderer.get("relief") as MapRelief).minimum_observation_mpp(Vector2(point.lon_lat[0],point.lon_lat[1])),"focused":get_window().has_focus(),"gpu_mip":"无法直接取得"}
	result["texture_instances"]={}
	for id: String in (renderer.get("relief") as MapRelief).textures:
		result.texture_instances[id]=((renderer.get("relief") as MapRelief).textures[id] as Texture2D).get_instance_id()
	# Full source-cell inventories remain in the existing catalogue/probe.
	# Keep only publication state and local contributions in the finite log.
	for state: Dictionary in (result.geometry as Dictionary).values():
		if state.has("last_result"): (state.last_result as Dictionary).erase("request")
	(result.selector as Dictionary).erase("replaced_ids")
	taking_point=false
	last_tick=Time.get_ticks_usec()
	return result

func foundation_review(world: Object) -> void:
	var places: Array=[["sydney",151.2093,-33.8688],["andes",-70.6693,-33.4489],["africa",18.4241,-33.9249],["india",77.209,28.6139],["rockies",-105.27,39.74],["tibet_join",90.0,30.1],["siberia",104.286,52.287],["vienna",16.4,48.2],["france",2.3522,48.8566],["spain",-7.5,42.5]]
	var requested:=OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty():places=places.filter(func(p: Array)->bool:return str(p[0]) in requested)
	for place: Array in places:
		for scale: float in ([500.0] if place[0] in ["france","vienna"] else [250.0] if place[0]=="spain" else [2600.0,500.0]):
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,2.6,0.0,renderer.get("size"))
			await settle()
			var floor_mpp: float=(renderer.get("relief") as MapRelief).minimum_observation_mpp(Vector2(place[1],place[2]))
			if scale<floor_mpp:
				results.append({"place":place,"requested_mpp":scale,"minimum_mpp":floor_mpp,"state":"unreachable; no forced zoom"});continue
			tracking=true;intervals.clear();last_tick=0;window_started=Time.get_ticks_msec()
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,scale*.001,0.0,renderer.get("size"))
			await settle();await wait_seconds(2)
			var label: String="%s_%s" % [place[0],int(scale)]
			var point:=state_point(label)
			get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")
			await wait_seconds(2)
			var idle:=state_point(label+"_idle")
			point["idle"]={"active":idle.active,"pixel":idle.framebuffer.rgba,"instances":idle.texture_instances,"errors":idle.errors}
			tracking=false
			if not intervals.is_empty():
				intervals.sort();point["process_interval_ms"]={"p50":intervals[int(intervals.size()/2)],"p95":intervals[int((intervals.size()-1)*.95)],"max":intervals.back(),"scope":"finite process intervals including region preparation, not GPU benchmark"}
			results.append(point)
			print("R57_FOUNDATION ",label," mpp=",point.mpp," active=",point.active," errors=",point.errors)
			FileAccess.open(output+"/bindings.json",FileAccess.WRITE).store_string(JSON.stringify(results))
		controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(.5)
	print("R57_FOUNDATION WORLD ",(renderer.get("relief") as MapRelief).textures.keys())
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func acceptance_repair(world: Object) -> void:
	var places: Array = [["east",31.6,59.95,100.1941],["ladoga",31.5,60.35,100.1941],["greenland_center",-42.0,73.5,1500.0],["greenland_west",-49.5,69.2,1500.0],["africa_join",18.0,15.8,1500.0],["paris",2.3522,48.8566,250.0],["spain",-7.5,42.5,250.0],["warsaw",21.0122,52.2297,250.0],["benelux",4.9,51.7,250.0],["sydney",151.2093,-33.8688,500.0]]
	var requested:=OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty():places=places.filter(func(p:Array)->bool:return str(p[0]) in requested)
	var observations: Array = []
	for place: Array in places:
		for mode: String in ["geographic","political"]:
			get_window().grab_focus()
			world.get("main_shell").set("_context_open",false)
			controller.call("set_map_mode",mode)
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,2.6,0.0,renderer.get("size"));await settle()
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await settle()
			acceptance_phase=str(place[0])+"_"+mode;tracking=true;last_tick=0;intervals.clear();slow_frames.clear();acceptance_unfocused_frames=0
			for cycle: int in range(3):
				for direction: int in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
					for step: int in range(3):
						var wheel:=InputEventMouseButton.new();wheel.position=renderer.get("size")*.5;wheel.button_index=direction;wheel.pressed=true;renderer.call("_gui_input",wheel);await wait_seconds(.07)
				var motion:=InputEventMouseMotion.new();motion.position=renderer.get("size")*.5;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
				var press:=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;renderer.call("_gui_input",press)
				for delta: Vector2 in [Vector2(60,0),Vector2(-60,0)]:motion.relative=delta;motion.position+=delta;renderer.call("_gui_input",motion);await wait_seconds(.07)
				press.position=motion.position;press.pressed=false;renderer.call("_gui_input",press);await settle()
			await wait_seconds(2)
			tracking=false
			var row: Dictionary={"place":place,"mode":mode,"window_focused":get_window().has_focus(),"performance":acceptance_performance(),"after_input":state_point(str(place[0])+"_"+mode),"binding":dynamic_snapshot()}
			# Same original view for the persistent-seam image and30-second check.
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await settle()
			if str(place[0]).begins_with("greenland") or place[0]=="africa_join":
				row["installed"]=state_point(str(place[0])+"_installed")
				await wait_seconds(10);row["idle10"]=state_point(str(place[0])+"_10")
				await wait_seconds(20);row["idle30"]=state_point(str(place[0])+"_30")
				if mode=="geographic":acceptance_image(str(place[0]))
			elif mode=="geographic" or place[0] in ["paris","benelux","east"]:
				acceptance_image(str(place[0])+"_"+mode)
			if place[0]=="benelux":
				var water:Dictionary={"features":0,"zuiderzee_visible":false,"batches":0}
				var layer:LocalSpatialLayer=renderer.get("_region_layer")
				if layer.content_reference()!=null:
					for feature:Dictionary in layer.content_reference().features:
						if "benelux_hydro_overview_r46" in str(feature.id):water.features+=1
				for batch:Dictionary in layer._batches+layer._fallback_batches:
					if "benelux" in str(batch.get("source_feature_id","")):water.batches+=1
					if "zuiderzee" in str(batch.get("source_feature_id","")) and bool(batch.visible):water.zuiderzee_visible=true
				row["benelux"]=water
			controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(1.5)
			row["world_exit"]={"textures":(renderer.get("relief") as MapRelief).textures.keys(),"region_batches":(renderer.get("_region_layer").get("_batches") as Array).size(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
			observations.append(row);acceptance_save("repair",{"windows":observations,"device":RenderingServer.get_video_adapter_name(),"note":"Ordinary process timing excludes point readbacks; no per-frame GPU observer. Other game processes may remain active."})
			print("R57_REPAIR ",place[0]," ",mode," complete")
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func acceptance_source_trace(world: Object) -> void:
	var errors: Array[String] = []
	var index := ContentDocument.read(StrategicSpatialLoader.INDEX_PATH,errors)
	var descriptors: Array[Dictionary] = []
	for parent: Dictionary in index.coast_regions:
		for child: Dictionary in parent.get("medium_regions",[]):
			if str(child.id) in ["physical_2_4_mid_2_2","physical_2_5_mid_2_0"]: descriptors.append(child)
	var selections: Array = []
	for descriptor: Dictionary in descriptors: selections.append([descriptor])
	var lakes: Array[Dictionary] = []
	for descriptor: Dictionary in index.regions:
		if str(descriptor.id) in ["europe","eurasia"]: lakes.append(descriptor)
	selections.append(descriptors+lakes)
	var requested_ids:=OS.get_environment("WWO_VISUAL_SOURCE_IDS").split(",",false)
	if not requested_ids.is_empty():
		var all_descriptors: Array = (index.regions as Array).duplicate()
		for parent:Dictionary in index.coast_regions:
			all_descriptors.append(parent);all_descriptors.append_array(parent.get("medium_regions",[]))
		all_descriptors.append_array(index.get("hydro_regions",[]))
		var full: Array[Dictionary] = []
		for descriptor:Dictionary in all_descriptors:
			if str(descriptor.id) in requested_ids:full.append(descriptor)
		selections.append(full)
	var rows: Array = []
	for selection: Array in selections:
		for ink: bool in [false,true]:
			if selection.size()>4 and not ink:continue
			var selected: Array[Dictionary] = [];selected.assign(selection)
			var content := StrategicSpatialLoader._load(index,selected,Callable(),null,ink)
			var prepared := LocalSpatialLod.prepare(content,["medium"],Callable(),renderer.call("_physical_ink_frames"))
			var hits: Array = []
			for coordinate: Vector2 in [Vector2(31.6,59.95),Vector2(31.5,60.35),Vector2(31.27,60.11),Vector2(31.57,60.44)]:
				var unit := GlobeProjection.lon_lat_to_unit(coordinate)
				var groups: Array = []
				var lake_ordinal := 0
				for chunk: Dictionary in prepared.get("chunks",[]):
					if not chunk.has("face_count"): continue
					if str(chunk.kind)=="lake": lake_ordinal+=1
					var floats: PackedFloat32Array = (chunk.payload.values as PackedByteArray).to_float32_array()
					var count := 0
					for face: int in range(int(chunk.face_count)):
						var points: Array[Vector3] = []
						for corner: int in range(3):
							var offset := (face*6+corner)*4
							points.append(Vector3(floats[offset],floats[offset+1],floats[offset+2]))
						if Geometry3D.ray_intersects_triangle(Vector3.ZERO,unit,points[0],points[1],points[2])!=null: count+=1
					if count>0: groups.append({"kind":chunk.kind,"source":chunk.get("source_feature_id",""),"source_ids":chunk.get("source_feature_ids",[]),"lake_batch_ordinal":lake_ordinal,"hits":count,"faces":chunk.face_count})
				hits.append({"ll":[coordinate.x,coordinate.y],"draw_hits":groups})
			rows.append({"descriptors":selected.map(func(d:Dictionary)->String:return str(d.id)),"compiled":ink,"errors":content.errors,"prepare_error":prepared.get("error",""),"points":hits})
	acceptance_save("source-trace",rows)
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func dynamic_snapshot() -> Dictionary:
	var relief: MapRelief = renderer.get("relief")
	var layer: LocalSpatialLayer = renderer.get("_region_layer")
	var ids := {}
	for id: String in relief.textures: ids[(relief.textures[id] as Texture2D).get_instance_id()]=id
	var material: ShaderMaterial
	var inks: Array=[]
	var visible_land := 0
	var unequal_bindings := 0
	var reference: Variant
	for batch: Dictionary in layer._batches+layer._fallback_batches:
		if str(batch.kind)!="land_reference" or not bool(batch.get("visible",false)): continue
		visible_land+=1
		var mat := batch.material as ShaderMaterial
		if material==null: material=mat;reference=batch.get("surface_reference")
		elif batch.get("surface_reference")!=reference: unequal_bindings+=1
		var ink: Array=[]
		for key: String in ["political_weight","flag_weight","political_base_color","relief_weight","reference_opacity"]: ink.append(TerrainPixelSource.serial(mat.get_shader_parameter(key)))
		if ink not in inks and inks.size()<6: inks.append(ink)
	var binding := {}
	if material!=null:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var name := str(uniform.name)
			if not name.begins_with("surface_"): continue
			var value: Variant = material.get_shader_parameter(name)
			binding[name]=ids.get((value as Texture2D).get_instance_id(),"unregistered") if value is Texture2D else TerrainPixelSource.serial(value)
	var residents := {}
	for id: String in relief.textures: residents[id]=(relief.textures[id] as Texture2D).get_instance_id()
	var lods: Array=[]
	for id: String in relief._surface_active:
		var a := relief._assets[id] as Dictionary
		if str(a.get("surface_role",""))=="detail": lods.append([id,a.get("surface_lod_degrees",2)])
	var water: Dictionary = {}
	if acceptance=="rapid-entry":
		for slot: String in ["_world_layer","_region_layer","local_layer"]:
			var owner: LocalSpatialLayer = renderer.get(slot)
			var rows: Array = []
			var counts: Dictionary = {}
			for batch: Dictionary in owner._batches+owner._fallback_batches:
				var kind := str(batch.kind)
				if kind not in ["lake","water_surface","ocean_reference"]: continue
				counts[kind] = int(counts.get(kind,0))+1
				if rows.size()>=32: continue
				var mat: ShaderMaterial = batch.material
				rows.append({"id":batch.get("source_feature_id",""),"kind":kind,"class":batch.get("water_class",""),"lod":batch.lod,"visible":batch.visible,"complete":batch.complete,"faces":batch.faces,"item":str(batch.item),"shader":mat.shader.resource_path,"color":TerrainPixelSource.serial(mat.get_shader_parameter("water_color")),"local_strength":TerrainPixelSource.serial(mat.get_shader_parameter("local_cover_strength"))})
			water[slot] = {"counts":counts,"batches":rows,"state":owner.diagnostic_state().duplicate(),"physical_key":owner.physical_reference().get("key","")}
			(water[slot].state as Dictionary).erase("last_result")
		water["loader"]={"wanted":renderer.get("strategic_content").get("_wanted"),"loading":renderer.get("strategic_content").get("_loading"),"preparing":renderer.get("strategic_content").call("preparing")}
	return {"wanted":relief._surface_wanted.duplicate(),"active":relief._surface_active.duplicate(),"inflight":relief._level if relief.preparing() else "","residents":residents,"lods":lods,"binding":binding,"inks":inks,"visible_land":visible_land,"unequal_bindings":unequal_bindings,"water":water,"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"geometry":{"target":layer.get("_target"),"active":layer.active_lod,"preparing":layer.preparing,"upload_cursor":layer.get("_cursor"),"upload_total":(layer.get("_upload_chunks") as Array).size(),"available":layer.available_lods.keys(),"error":layer.preparation_error},"canvas_dirty":renderer.get("_map_canvas_dirty"),"transition":renderer.get("_transition_elapsed"),"errors":relief.errors.duplicate()}

func dynamic_pre_draw() -> void:
	if not dynamic_recording:return
	var tag:=Engine.get_frames_drawn()%65536
	dynamic_marker.color=Color(float(tag%256)/255.0,float(tag/256)/255.0,float((tag%256)^(tag/256))/255.0)
	var camera: RegionCamera=controller.region_camera
	var ll := RegionProjection.lon_lat(renderer.call("unit_at",renderer.get("size")*.5)) if camera.active else Vector2.ZERO
	dynamic_pre[tag]={"state":dynamic_snapshot(),"time":Time.get_ticks_usec(),"mpp":camera.km_per_pixel*1000.0,"ll":ll,"mode":controller.map_mode,"case":dynamic_case,"phase":dynamic_phase}
	for old: int in dynamic_pre.keys():
		if (tag-old+65536)%65536>4:dynamic_pre.erase(old)

func dynamic_draw() -> void:
	if not dynamic_recording or dynamic_frames.size()>=(24000 if acceptance=="dynamic" else 12000): return
	var began := Time.get_ticks_usec()
	var read_began := Time.get_ticks_usec()
	var crop := dynamic_capture_view.get_texture().get_image()
	var read_us := Time.get_ticks_usec()-read_began
	var marker:=crop.get_pixel(0,0)
	var low:=roundi(marker.r*255);var high:=roundi(marker.g*255)
	var tag:=low+high*256
	if not dynamic_pre.has(tag) or abs(roundi(marker.b*255)-(low^high))>1:
		dynamic_sync_errors+=1;return
	var frame:=Engine.get_frames_drawn()
	var preview_frame:int=tag+dynamic_root_offset+65536*roundi(float(frame-tag-dynamic_root_offset)/65536.0)
	if dynamic_calibration.size()<6:
		var root_image:=get_viewport().get_texture().get_image()
		var root_marker:=root_image.get_pixel(200,140)
		var root_tag:=roundi(root_marker.r*255)+256*roundi(root_marker.g*255)
		if root_tag>0:
			dynamic_root_offset=frame-root_tag
			dynamic_calibration.append([frame,root_tag,tag,dynamic_root_offset])
	var state := dynamic_snapshot()
	var key := JSON.stringify(state)
	if key!=dynamic_key:
		dynamic_states.append(state)
		dynamic_key=key
	var camera: RegionCamera=controller.region_camera
	var ll := RegionProjection.lon_lat(renderer.call("unit_at",renderer.get("size")*.5)) if camera.active else Vector2.ZERO
	dynamic_readback.append(read_us)
	var small := crop.duplicate() as Image
	small.resize(12,6,Image.INTERPOLATE_BILINEAR)
	var row := [frame,Time.get_ticks_usec(),camera.km_per_pixel*1000.0,ll.x,ll.y,controller.map_mode,dynamic_case,dynamic_phase,dynamic_states.size()-1,read_us,Marshalls.raw_to_base64(small.get_data()),Time.get_ticks_usec()-began,preview_frame]
	dynamic_frames.append(row)
	if not dynamic_pending.is_empty():
		dynamic_pending["frames"].append(frame)
		dynamic_pending["images"].append(dynamic_root_image())
		dynamic_captures.append(dynamic_pending)
		dynamic_pending={}
	# Preserve the first fully replaced rendered frame as well. It can be
	# later than "next" when several source images finish on separate frames.
	for capture: Dictionary in dynamic_captures:
		if capture.case!=dynamic_case or capture.has("complete_frame"):continue
		var ready := true
		for id: String in state.active:
			if id not in state.wanted:ready=false
		if ready and not state.lods.is_empty() and not bool(state.geometry.preparing) and not bool(renderer.get("strategic_content").call("preparing")) and not bool(state.canvas_dirty):capture["complete_frame"]=frame;capture["complete_image"]=dynamic_root_image()
	var spans: Array=[]
	for pair: Array in state.lods:
		if float(pair[1]) not in spans: spans.append(float(pair[1]))
	var active_changed: bool=state.active!=dynamic_previous.get("active",[])
	# A/B/A pixels at an unchanged camera can expose a one-frame material
	# pulse even when resource IDs remain unchanged. Retain only candidates.
	if acceptance=="dynamic" and dynamic_ring.size()>=2 and not dynamic_cases_captured.has(dynamic_case) and dynamic_captures.size()<8:
		var earlier:Dictionary=dynamic_ring[dynamic_ring.size()-2]
		var middle:Dictionary=dynamic_ring.back()
		var pre:Dictionary=dynamic_pre[tag]
		if earlier.mode==pre.mode and middle.mode==pre.mode and absf(float(earlier.mpp)-float(pre.mpp))<.01 and (earlier.ll as Vector2).distance_to(pre.ll as Vector2)<.00001 and absf(float(middle.mpp)-float(pre.mpp))<.01:
			var current_bytes:PackedByteArray=small.get_data()
			var prior_bytes:PackedByteArray=earlier.small
			var middle_bytes:PackedByteArray=middle.small
			var ends:=0.0;var pulse:=0.0
			for index:int in range(4,current_bytes.size()):
				if index%4==3:continue
				ends+=absf(current_bytes[index]-prior_bytes[index])/255.0
				pulse+=absf(middle_bytes[index]-prior_bytes[index])/255.0
			if ends/213.0<.015 and pulse/213.0>.06:
				dynamic_captures.append({"case":dynamic_case,"phase":dynamic_phase,"reason":"one-frame pixel pulse at fixed camera; inspect actual frames","frames":[earlier.source_frame,middle.source_frame,preview_frame],"images":[earlier.image,middle.image,crop]});dynamic_cases_captured[dynamic_case]=true
	# A candidate, not a diagnosis: save actual neighbouring GPU frames when
	# one published set contains different page spans during an active zoom.
	var old_spans: Array=[]
	for pair: Array in dynamic_previous.get("lods",[]):
		if float(pair[1]) not in old_spans:old_spans.append(float(pair[1]))
	var candidate:bool=(spans.size()>1 or not old_spans.is_empty() and spans!=old_spans) and active_changed
	if acceptance=="dynamic":candidate=spans.size()>1 or int(state.unequal_bindings)>0 or not (state.errors as Array).is_empty() or "unregistered" in (state.binding as Dictionary).values()
	if acceptance=="rapid-entry":candidate=dynamic_phase.ends_with("_entry_hold")
	if candidate and not dynamic_ring.is_empty() and not dynamic_cases_captured.has(dynamic_case) and dynamic_captures.size()<8:
		dynamic_pending={"case":dynamic_case,"phase":dynamic_phase,"reason":"unexpected mixed span/binding/error" if acceptance=="dynamic" else "detail-span publication; inspect pixels before classifying","frames":[preview_frame,frame],"images":[crop,dynamic_root_image()]}
		dynamic_cases_captured[dynamic_case]=true
	dynamic_ring.append({"frame":frame,"source_frame":preview_frame,"image":crop,"mpp":dynamic_pre[tag].mpp,"ll":dynamic_pre[tag].ll,"mode":dynamic_pre[tag].mode,"small":small.get_data()})
	if dynamic_ring.size()>3: dynamic_ring.pop_front()
	dynamic_previous=state

func dynamic_root_image() -> Image:
	var image:=get_viewport().get_texture().get_image().get_region(Rect2i(200,140,880,480))
	image.resize(440,240,Image.INTERPOLATE_BILINEAR)
	return image

func dynamic_run(world: Object) -> void:
	var places: Array=[["petersburg",30.3351,59.9343],["east",31.6,59.95],["ladoga",31.5,60.35],["control",21.0122,52.2297],["berlin",13.405,52.52],["sydney",151.2093,-33.8688],["south_america",-70.6693,-33.4489],["tibet_join",90.0,30.1],["vienna",16.4,48.2]]
	if acceptance=="dynamic":places=[["east",31.6,59.95],["ladoga",31.5,60.35],["control",21.0122,52.2297],["tibet_join",90.0,30.1],["greenland",-42.0,73.5]]
	if acceptance=="rapid-entry":places=[["east",31.6,59.95],["ladoga",31.5,60.35]]
	var requested := OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty():places=places.filter(func(p: Array) -> bool:return str(p[0]) in requested)
	(renderer.get("relief") as MapRelief).decode_asset=tracked_decode
	# GPU copy of the actual root viewport, not a second map renderer. Read
	# only440x240 instead of1280x720. A four-pixel marker resolves copy latency.
	dynamic_capture_view=SubViewport.new();dynamic_capture_view.size=Vector2i(440,240);dynamic_capture_view.disable_3d=true;dynamic_capture_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(dynamic_capture_view)
	var screen_copy:=TextureRect.new();screen_copy.size=Vector2(440,240);screen_copy.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;screen_copy.stretch_mode=TextureRect.STRETCH_SCALE
	var atlas:=AtlasTexture.new();atlas.atlas=get_viewport().get_texture();atlas.region=Rect2(200,140,880,480);screen_copy.texture=atlas;dynamic_capture_view.add_child(screen_copy)
	var marker_layer:=CanvasLayer.new();marker_layer.layer=128;add_child(marker_layer)
	dynamic_marker=ColorRect.new();dynamic_marker.position=Vector2(200,140);dynamic_marker.size=Vector2(4,4);dynamic_marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;marker_layer.add_child(dynamic_marker)
	RenderingServer.frame_pre_draw.connect(dynamic_pre_draw)
	RenderingServer.frame_post_draw.connect(dynamic_draw)
	for place: Array in places:
		for mode: String in ["geographic","political"]:
			dynamic_case=str(place[0])+"_"+mode
			dynamic_previous={};dynamic_ring=[]
			world.get("main_shell").call("_activate","map_mode:"+mode)
			world.get("main_shell").set("_context_open",false)
			if acceptance=="rapid-entry":
				controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(1.5)
			else:
				controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,.9,0.0,renderer.get("size"))
				await settle()
			dynamic_recording=true
			for cycle: int in range(3):
				if acceptance=="rapid-entry":
					dynamic_phase="%s_pure_world_zoom" % cycle
					controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(1.5)
					for step:int in range(90):
						var entry_wheel:=InputEventMouseButton.new();entry_wheel.position=renderer.get("size")*.5;entry_wheel.button_index=MOUSE_BUTTON_WHEEL_UP;entry_wheel.pressed=true;renderer.call("_gui_input",entry_wheel);await wait_seconds(.035)
						if controller.region_camera.active and controller.region_camera.km_per_pixel<=.110:break
					dynamic_phase="%s_entry_hold" % cycle
					await settle();await wait_seconds(1)
					acceptance_idle.append({"case":dynamic_case,"cycle":cycle,"phase":"pure_wheel_entry","point":state_point(dynamic_case+"_pure_wheel")})
					continue
				if acceptance=="dynamic":
					dynamic_phase="%s_world_entry" % cycle
					controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(1.5)
					dynamic_world_exits.append({"case":dynamic_case,"cycle":cycle,"textures":(renderer.get("relief") as MapRelief).textures.keys(),"snapshot":dynamic_snapshot()})
					for step:int in range(40):
						if controller.region_camera.active:break
						var entry_wheel:=InputEventMouseButton.new();entry_wheel.position=renderer.get("size")*.5;entry_wheel.button_index=MOUSE_BUTTON_WHEEL_UP;entry_wheel.pressed=true;renderer.call("_gui_input",entry_wheel);await wait_seconds(.07)
					await settle()
					acceptance_idle.append({"case":dynamic_case,"cycle":cycle,"phase":"world_entry","region_entered":controller.region_camera.active,"actual_mpp":controller.region_camera.km_per_pixel*1000})
					world.get("main_shell").call("_activate","map_mode:"+("political" if mode=="geographic" else "geographic"));await wait_seconds(.15)
					world.get("main_shell").call("_activate","map_mode:"+mode);world.get("main_shell").set("_context_open",false)
				var initial_mpp:float=3500.0 if acceptance=="dynamic" and place[0]=="greenland" else 900.0
				controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,initial_mpp*.001,0.0,renderer.get("size"))
				for direction: int in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
					dynamic_phase="%s_%s" % [cycle,"in" if direction==MOUSE_BUTTON_WHEEL_UP else "out"]
					for step: int in range(14):
						var wheel:=InputEventMouseButton.new();wheel.position=renderer.get("size")*.5;wheel.button_index=direction;wheel.pressed=true
						renderer.call("_gui_input",wheel)
						await wait_seconds(.07)
						if step in [8,10]:await wait_seconds(.5)
					await wait_seconds(.4)
				dynamic_phase="pan"
				var motion:=InputEventMouseMotion.new();motion.position=renderer.get("size")*.5;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
				var press:=InputEventMouseButton.new();press.position=motion.position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;renderer.call("_gui_input",press)
				for delta: Vector2 in [Vector2(15,0),Vector2(-15,0)]:motion.relative=delta;motion.position+=delta;renderer.call("_gui_input",motion);await wait_seconds(.08)
				press.position=motion.position;press.pressed=false;renderer.call("_gui_input",press)
				dynamic_phase="idle";await wait_seconds(1)
				if acceptance=="dynamic":
					dynamic_recording=false;dynamic_capture_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
					await settle();var installed:=state_point(dynamic_case+"_installed")
					await wait_seconds(10);var idle10:=state_point(dynamic_case+"_10")
					await wait_seconds(20);var idle30:=state_point(dynamic_case+"_30")
					acceptance_idle.append({"case":dynamic_case,"cycle":cycle,"phase":"idle","points":[installed,idle10,idle30]})
					var retained_mpp:float=controller.region_camera.km_per_pixel
					controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(77.209,28.6139)),renderer.get("size")*.5,2.6,0.0,renderer.get("size"));await settle()
					controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,retained_mpp,0.0,renderer.get("size"));await settle()
					acceptance_idle.append({"case":dynamic_case,"cycle":cycle,"phase":"returned_after_travel","point":state_point(dynamic_case+"_returned")})
					dynamic_capture_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;dynamic_recording=true
			dynamic_recording=false
			print("R57_DYNAMIC ",dynamic_case," frames=",dynamic_frames.size()," candidates=",dynamic_captures.size())
			controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await wait_seconds(1.5)
			dynamic_world_exits.append({"case":dynamic_case,"textures":(renderer.get("relief") as MapRelief).textures.keys(),"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
			if acceptance=="dynamic":acceptance_save("dynamic-progress",{"finished":dynamic_case,"frames":dynamic_frames.size(),"idle_records":acceptance_idle.size(),"world_exits":dynamic_world_exits})
	RenderingServer.frame_post_draw.disconnect(dynamic_draw)
	RenderingServer.frame_pre_draw.disconnect(dynamic_pre_draw)
	var bytes_written:=0
	var png_budget:=15*1024*1024
	if not OS.get_environment("WWO_VISUAL_PNG_BUDGET").is_empty(): png_budget=clampi(OS.get_environment("WWO_VISUAL_PNG_BUDGET").to_int(),0,png_budget)
	var captures: Array=[]
	for index: int in range(dynamic_captures.size()):
		var item:=dynamic_captures[index] as Dictionary
		if item.has("complete_frame"):
			(item.frames as Array).append(item.complete_frame);(item.images as Array).append(item.complete_image)
		var files: Array=[]
		for corner: int in range((item.images as Array).size()):
			var bytes: PackedByteArray=(item.images[corner] as Image).save_png_to_buffer()
			if bytes_written+bytes.size()>png_budget:break
			var name: String="event_%02d_%d.png" % [index,corner];FileAccess.open(output+"/"+name,FileAccess.WRITE).store_buffer(bytes);files.append(name);bytes_written+=bytes.size()
		captures.append({"case":item.case,"phase":item.phase,"reason":item.reason,"frames":item.frames,"files":files})
	var report: Dictionary={"candidate":"Current executable or project supplied by launcher","columns":["render_frame","time_us","mpp","longitude","latitude","mode","case","phase","state_index","readback_us","actual_roi_12x6_rgba_base64","observer_total_us"],"roi":[200,140,880,480],"frames":dynamic_frames,"states":dynamic_states,"decode_returns":decode_events,"captures":captures,"world_remaining":(renderer.get("relief") as MapRelief).textures.keys(),"png_bytes":bytes_written,"notes":"Actual post_draw root viewport. Full viewport GPU readback then bounded ROI; no force_draw, decoder delay or per-frame disk screenshots. Mixed spans are candidates, not proof of a visual fault."}
	report["columns"][12 if (report.columns as Array).size()>12 else 11]="observer_total_us"
	(report.columns as Array).append("preview_source_render_frame")
	report["capture_calibration"]=dynamic_calibration
	report["sync_rejected_frames"]=dynamic_sync_errors
	report["world_exits"]=dynamic_world_exits
	if acceptance in ["dynamic","rapid-entry"]:report["acceptance_idle_and_travel"]=acceptance_idle
	report["notes"]="Actual root viewport cropped200,140,880,480 and GPU copied to440x240. RG frame tag resolves the copy latency. At/next/complete PNGs read the actual root directly; before PNG is the time-aligned GPU copy. No force_draw or decoder delay. Observer totals exclude rare PNG reference readbacks."
	var packed:=JSON.stringify(report).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	if bytes_written+packed.size()>20*1024*1024:get_tree().quit(8);return
	FileAccess.open(output+"/dynamic.json.gz",FileAccess.WRITE).store_buffer(packed)
	print("R57_DYNAMIC saved ",dynamic_frames.size()," frames, ",dynamic_states.size()," states, bytes=",bytes_written+packed.size())
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func mode_review(world: Object) -> void:
	# Same real camera/materials as play; small requested comparison set.
	if OS.get_environment("WWO_VISUAL_ADMIN_OFF")=="1" and controller.has_method("toggle_administrative_lines"):
		controller.call("toggle_administrative_lines")
	var cases: Array = [["france",2.3522,48.8566,500.0],["france",2.3522,48.8566,250.0],["france",2.3522,48.8566,75.0],["spain",-7.5,42.5,500.0],["spain",-7.5,42.5,250.0],["spain",-7.5,42.5,75.0],["petersburg",30.3351,59.9343,500.0],["petersburg",30.3351,59.9343,250.0],["petersburg",30.3351,59.9343,75.0],["moscow",37.6173,55.7558,500.0],["moscow",37.6173,55.7558,250.0],["moscow",37.6173,55.7558,75.0],["berlin",13.405,52.52,250.0]]
	var requested := OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty(): cases=cases.filter(func(p: Array) -> bool: return str(p[0])+"_"+str(int(p[3])) in requested)
	for place: Array in cases:
		world.get("main_shell").set("_context_open",false)
		tracking=true
		window_started=Time.get_ticks_msec()
		last_tick=0
		intervals.clear()
		changes.clear()
		last_state=[]
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"))
		var modes: Array = ["political"] if place[0] in ["petersburg","moscow"] else ["geographic"]
		if place[0]=="france" and place[3]==500.0: modes=["political","geographic","fulfillment","shortage","geographic"]
		for mode: String in modes:
			world.get("main_shell").call("_activate","map_mode:"+mode)
			world.get("main_shell").set("_context_open",false)
			await wait_seconds(.3)
			await settle()
			await wait_seconds(4)
			var label := "%s_%s_%s" % [place[0],int(place[3]),mode]
			var point := state_point(label)
			var styles: Dictionary = renderer.get("_political_ink")
			var counts := {}
			for batch: Dictionary in (renderer.get("_region_layer") as LocalSpatialLayer)._batches:
				if str(batch.kind)!="land_reference" or not bool(batch.get("visible",false)): continue
				var mat := batch.material as ShaderMaterial
				var key := str(batch.get("ink_reference",""))+" / "+str(mat.get_shader_parameter("political_weight"))+" / "+str(mat.get_shader_parameter("political_base_color"))
				counts[key]=int(counts.get(key,0))+1
			point["visible_ink"] = counts
			point["economic_rows"] = {}
			for owner: String in renderer.get("political").get("economies"):
				point.economic_rows[owner]=(renderer.get("political").get("economies")[owner] as Dictionary).get("daily_totals",{})
			point["administrative"] = controller.call("administrative_layer_active")
			point["resident_textures"]=(renderer.get("relief") as MapRelief).textures.size()
			point["region_batches"]=(renderer.get("_region_layer") as LocalSpatialLayer)._batches.size()
			if place[0]=="france" and place[3]==500.0 and mode=="fulfillment" or place[0]=="petersburg" and place[3]==75.0:
				await wait_seconds(10)
				var idle10 := state_point(label+"_idle10")
				await wait_seconds(20)
				var idle30 := state_point(label+"_idle30")
				point["idle10"]={"active":idle10.active,"pixel":idle10.framebuffer.rgba,"errors":idle10.errors,"instances":idle10.texture_instances,"layers":idle10.layers}
				point["idle30"]={"active":idle30.active,"pixel":idle30.framebuffer.rgba,"errors":idle30.errors,"instances":idle30.texture_instances,"layers":idle30.layers}
				if place[0]=="france":
					var residents: Array=[]
					for switch: String in ["geographic","political","shortage","fulfillment","political","geographic","shortage","fulfillment"]:
						world.get("main_shell").call("_activate","map_mode:"+switch)
						await wait_seconds(.2)
						await settle()
						residents.append([(renderer.get("relief") as MapRelief).textures.size(),(renderer.get("_region_layer") as LocalSpatialLayer)._batches.size()])
					point["repeat_mode_residents"]=residents
			if not intervals.is_empty():
				var sorted_intervals := intervals.duplicate()
				sorted_intervals.sort()
				point["process_interval_ms"]={"p95":sorted_intervals[int((sorted_intervals.size()-1)*.95)],"maximum":sorted_intervals.back(),"scope":"Finite process intervals, not GPU timing or a performance benchmark"}
			results.append(point)
			var capture: bool = place[0]=="france" and ((place[3]==500.0 and mode=="fulfillment") or (place[3]==250.0 and mode=="geographic")) or place[0]=="spain" and place[3]==250.0 or place[0]=="petersburg" and place[3] in [500.0,75.0]
			if capture:
				RenderingServer.force_draw(false)
				get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")
			FileAccess.open(output+"/bindings.json",FileAccess.WRITE).store_string(JSON.stringify(results))
			print("R57_MODE ",label," actual_mpp=",point.mpp," active=",point.active," errors=",point.errors)
			if place[0]=="france" and place[3]==500.0 and mode=="political":
				world.get("main_shell").set("_map_modes_open",true)
				world.get("main_shell").call("queue_redraw")
				await wait_seconds(.15)
				RenderingServer.force_draw(false)
				get_viewport().get_texture().get_image().save_png(output+"/political_menu.png")
				world.get("main_shell").set("_map_modes_open",false)
				world.get("main_shell").call("queue_redraw")
	tracking=false
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.5,48.5)))
	controller.call("set_world_zoom",.86)
	await wait_seconds(1)
	print("R57_MODE WORLD textures=",renderer.get("relief").get("textures").keys())
	world.set("_departure_target","menu")
	world.call("_leave_world")
	await wait_seconds(.5)
	get_tree().quit(0)

func settle() -> int:
	var began := Time.get_ticks_msec()
	var deadline := began+30000
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		var relief: MapRelief = renderer.get("relief")
		if not relief.preparing() and not bool(renderer.get("strategic_content").call("preparing")) and not bool(renderer.get("_region_layer").get("preparing")) and not bool(renderer.get("_map_canvas_dirty")) and not bool(renderer.get("_resource_demand_dirty")):
			await wait_seconds(.2)
			if not relief.preparing(): return Time.get_ticks_msec()-began
	return -1

func stability_run(world: Object) -> void:
	var places: Array = [["paris",2.3522,48.8566,400.0],["berlin",13.405,52.52,400.0],["warsaw",21.0122,52.2297,400.0],["petersburg",30.3351,59.9343,400.0],["moscow",37.6173,55.7558,400.0],["finland_baltic",24.9384,60.1699,400.0],["vienna",16.4,48.0,400.0],["spain",-7.5,42.5,400.0]]
	if OS.get_environment("WWO_VISUAL_TERRAIN_BATCH")=="1":
		places.append_array([["petersburg_west",28.0,59.0,500.0],["petersburg_east",32.0,59.0,500.0],["petersburg_north",30.0,62.0,500.0]])
	var requested := OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty(): places=places.filter(func(p: Array) -> bool: return str(p[0]) in requested)
	var common_mpp := OS.get_environment("WWO_VISUAL_MPP").to_float()
	if common_mpp>0:
		for place: Array in places: place[3]=common_mpp
	(renderer.get("relief") as MapRelief).decode_asset=tracked_decode
	for place: Array in places:
		window_started=Time.get_ticks_msec()
		changes=[]; last_state=[]; intervals=[]; last_tick=0
		decode_mutex.lock(); decode_events=[]; decode_mutex.unlock()
		tracking=true
		var unit := GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2]))
		controller.call("focus_region",unit,renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"))
		await get_tree().process_frame
		# Observe after the normal camera/canvas hand-off. At the first tick
		# the cached viewport can still contain the preceding location.
		await wait_seconds(.25)
		var points: Array = [state_point("first")]
		var prepared_ms := await settle()
		points.append(state_point("installed"))
		# Bound screenshot storage; every window still reads its real pixel.
		if output.get_file()!="candidate" and str(place[0]) in ["warsaw","petersburg"]:
			RenderingServer.force_draw(false)
			get_viewport().get_texture().get_image().save_png(output+"/"+str(place[0])+".png")
		print("R57_STABILITY installed ",place[0]," prepare_ms=",prepared_ms)
		await wait_seconds(10)
		points.append(state_point("idle10"))
		await wait_seconds(20)
		points.append(state_point("idle30"))
		var idle_changes := changes.duplicate()
		# Return to the exact camera, then exercise ordinary wheel/drag input.
		controller.call("focus",unit)
		controller.call("set_world_zoom",.86)
		await wait_seconds(.4)
		controller.call("focus_region",unit,renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"))
		var returned_ms := await settle()
		points.append(state_point("returned"))
		for direction: int in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			for i: int in range(3):
				var wheel := InputEventMouseButton.new()
				wheel.position=renderer.get("size")*.5; wheel.pressed=true; wheel.button_index=direction
				renderer.call("_gui_input",wheel)
				await wait_seconds(.08)
		var pos: Vector2=renderer.get("size")*.5
		await mouse_button(pos,MOUSE_BUTTON_LEFT,true)
		for offset: Vector2 in [Vector2(5,0),Vector2(-5,0)]:
			var motion:=InputEventMouseMotion.new()
			pos+=offset; motion.position=pos; motion.relative=offset; motion.button_mask=MOUSE_BUTTON_MASK_LEFT
			renderer.call("_gui_input",motion)
			await get_tree().process_frame
		await mouse_button(pos,MOUSE_BUTTON_LEFT,false)
		await settle()
		points.append(state_point("after_input"))
		tracking=false
		intervals.sort()
		decode_mutex.lock(); var decodes:=decode_events.duplicate(); decode_mutex.unlock()
		results.append({"place":place,"window_started_ms":window_started,"prepared_ms":prepared_ms,"returned_ms":returned_ms,"points":points,"idle_changes":idle_changes,"changes":changes.duplicate(),"decodes":decodes,"frames":{"count":intervals.size(),"p95_ms":intervals[int(intervals.size()*.95)] if not intervals.is_empty() else 0,"max_ms":intervals[-1] if not intervals.is_empty() else 0}})
		FileAccess.open(output+"/stability.json",FileAccess.WRITE).store_string(JSON.stringify({"selection_ms":selection_ms,"isolation":OS.get_user_data_dir(),"renderer":RenderingServer.get_video_adapter_name(),"samples":results}))
		print("R57_STABILITY finished ",place[0]," changes=",changes.size()," decodes=",decodes.size())
	await check_ui(world.get("main_shell"))
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.5,48.5)))
	controller.call("set_world_zoom",.86)
	await wait_seconds(1)
	print("R57_STABILITY WORLD ",(renderer.get("relief") as MapRelief).textures.keys())
	world.set("_departure_target","menu"); world.call("_leave_world")
	await wait_seconds(.5)
	get_tree().quit(0)

func performance_tick() -> void:
	var now := Time.get_ticks_usec()
	var loading: bool = perf_relief.preparing() or perf_region.preparing or perf_local.preparing or renderer.get("strategic_content").preparing() or renderer.get("local_content").preparing() or renderer.get("_overlay_thread")!=null or not (renderer.get("_overlay_uploads") as Array).is_empty() or renderer.get("region_view").landmark_preparing()
	var state: Array = [perf_relief._level if perf_relief.preparing() else "",perf_relief.textures.keys(),perf_relief._surface_active.duplicate(),perf_region._generation,perf_region._cursor,perf_region.preparing,int(renderer.get("strategic_content").get("_request_generation"))]
	if state!=perf_last_state:
		perf_events.append([Engine.get_process_frames(),now,perf_phase,state])
		perf_last_state=state
	if perf_previous>0:
		perf_frames.append([Engine.get_process_frames(),now,now-perf_previous,Performance.get_monitor(Performance.TIME_PROCESS)*1000000,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000,perf_draw_us,loading,controller.camera_motion_active(),get_window().has_focus(),Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	perf_previous=now

func performance_pre_draw() -> void:
	if perf_recording: perf_pre_draw=Time.get_ticks_usec()

func performance_post_draw() -> void:
	if not perf_recording: return
	var now := Time.get_ticks_usec()
	perf_draw_us=now-perf_pre_draw if perf_pre_draw>0 else 0
	if perf_pending_input>=0:
		(perf_inputs[perf_pending_input] as Dictionary)["post_draw_latency_us"]=now-perf_last_input
		perf_pending_input=-1

func performance_snapshot() -> Dictionary:
	var layers: Dictionary={}
	var all_items: Dictionary={};var all_meshes: Dictionary={};var all_materials: Dictionary={}
	for row: Array in [["world",perf_world],["region",perf_region],["local",perf_local]]:
		var layer: LocalSpatialLayer=row[1]
		var visible_count := 0
		for batch: Dictionary in layer._batches+layer._fallback_batches:
			if bool(batch.visible):visible_count+=1
			for field: String in ["item","geometry","material"]:
				var value: Variant=batch.get(field)
				var id: String=str(value.get_rid()) if value is Resource else str(value)
				if field=="item":all_items[id]=true
				elif field=="geometry":all_meshes[id]=true
				else:all_materials[id]=true
		layers[row[0]]={"batches":layer._batches.size(),"fallback_batches":layer._fallback_batches.size(),"visible":visible_count,"generation":layer._generation,"cursor":layer._cursor,"preparing":layer.preparing}
	var textures: Dictionary={}
	for id: String in perf_relief.textures:textures[id]=(perf_relief.textures[id] as Texture2D).get_instance_id()
	var snapshot: Dictionary={"time_us":Time.get_ticks_usec(),"mpp":controller.region_camera.km_per_pixel*1000.0,"regional":controller.region_camera.active,"textures":textures,"wanted":perf_relief._wanted.duplicate(),"active":perf_relief._surface_active.duplicate(),"layers":layers,"owned_batch_item_rids":all_items.size(),"owned_batch_geometry_objects":all_meshes.size(),"owned_batch_material_rids":all_materials.size(),"admin_batches":(renderer.get("_overlay_batches") as Dictionary).size(),"symbols":(renderer.get("_symbol_layout") as Array).size(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"object_count":Performance.get_monitor(Performance.OBJECT_COUNT),"resource_count":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"decode_events":decode_events.duplicate(),"errors":perf_relief.errors.duplicate()}
	var scope_path := OS.get_environment("WWO_PERF_SCOPE")
	if not scope_path.is_empty():
		snapshot["function_counters"]=load(scope_path).call("counters")
	if not scope_path.is_empty() or OS.get_environment("WWO_PERF_CONTENT")=="1" and perf_phase.begins_with("paris/"):
		var inventory: Dictionary={}
		for entry: Array in [["world",perf_world],["region",perf_region],["local",perf_local]]:
			var owner: LocalSpatialLayer=entry[1]
			var rows: Array=[]
			for batch: Dictionary in owner._batches+owner._fallback_batches:
				rows.append([str(batch.item),batch.geometry.get_instance_id(),str(batch.get("source_feature_id",""))])
			inventory[entry[0]]=rows
		var overlays: Array=[]
		for id: String in renderer.get("_overlay_batches"):
			for batch: Dictionary in renderer.get("_overlay_batches")[id]:overlays.append([id,str(batch.item),batch.geometry.get_instance_id()])
		inventory["overlays"]=overlays
		if perf_profile_inventories.is_empty() or inventory!=perf_profile_inventories.back():perf_profile_inventories.append(inventory)
		var symbols: Array=[]
		for row: Dictionary in renderer.get("_symbol_layout"):symbols.append([str(row.id),TerrainPixelSource.serial(row.rect)])
		var labels: Array=[]
		for row: Dictionary in renderer.get("_symbol_text"):labels.append(str(row.id))
		snapshot["profile_content"]={"inventory_index":perf_profile_inventories.size()-1,"symbols":symbols,"labels":labels,"symbol_candidates":(renderer.get("_symbol_place_records") as Dictionary).size(),"overlay_demand":(renderer.get("_overlay_demand") as Array).map(func(row: Dictionary)->String:return str(row.id))}
	snapshot["labels_enabled"]=controller.labels_enabled
	snapshot["mode"]=controller.map_mode
	snapshot["local_active"]=controller.region_camera.local_active
	snapshot["diagnostic_counters"]=renderer.call("current_view_map_status").get("diagnostic_counters",{})
	snapshot["overlay_generation"]=renderer.get("_overlay_generation")
	snapshot["overlay_loading"]=renderer.get("_overlay_thread")!=null
	snapshot["overlay_uploads"]=(renderer.get("_overlay_uploads") as Array).size()
	snapshot["overlay_installing"]=(renderer.get("_overlay_installing") as Dictionary).size()
	return snapshot

func performance_begin(label: String) -> void:
	get_window().grab_focus()
	perf_phase=label;perf_frames=[];perf_events=[];perf_inputs=[];perf_previous=0;perf_draw_us=0;perf_pre_draw=0;perf_pending_input=-1
	perf_begin_snapshot=performance_snapshot();perf_last_state=[];perf_started=Time.get_ticks_usec();perf_recording=true

func performance_end() -> void:
	perf_recording=false
	perf_phases.append({"phase":perf_phase,"started_us":perf_started,"ended_us":Time.get_ticks_usec(),"frames":perf_frames,"events":perf_events,"inputs":perf_inputs,"begin":perf_begin_snapshot,"end":performance_snapshot()})

func performance_input(event: InputEvent) -> void:
	var began := Time.get_ticks_usec()
	renderer.call("_gui_input",event)
	var ended := Time.get_ticks_usec()
	perf_inputs.append({"began_us":began,"call_us":ended-began,"event":event.get_class(),"mpp":controller.region_camera.km_per_pixel*1000.0})
	perf_pending_input=perf_inputs.size()-1;perf_last_input=began

func performance_wheel(direction: MouseButton) -> void:
	var wheel := InputEventMouseButton.new();wheel.position=renderer.get("size")*.5;wheel.button_index=direction;wheel.pressed=true
	performance_input(wheel)

func performance_drag(delta: Vector2,steps: int) -> void:
	var position: Vector2=renderer.get("size")*.5
	var press := InputEventMouseButton.new();press.position=position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	performance_input(press)
	for step: int in range(steps):
		var motion := InputEventMouseMotion.new();motion.position=position+delta;motion.relative=delta;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		performance_input(motion);position=motion.position
		await wait_seconds(.07)
	press.position=position;press.pressed=false;performance_input(press)

func performance_binding_comparison() -> bool:
	# Isolated A/B on the same release executable; no package or source mutation.
	# Both variants use the same derived-script dispatch and formal scene.
	var variant := OS.get_environment("WWO_PERF_BINDING")
	if variant.is_empty(): return true
	if variant not in ["previous","current"]: return false
	perf_comparison_scene=load("res://scenes/presentation/map/globe_renderer.tscn") as PackedScene
	perf_comparison_script=GDScript.new()
	var body := "\tfor layer: LocalSpatialLayer in [_world_layer,_region_layer]: layer.set_reference_window(window)\n" if variant=="previous" else "\tstrategic_layer.set_reference_window(window)\n"
	perf_comparison_script.source_code="extends \"res://scripts/presentation/map/globe_renderer.gd\"\nfunc _bind_relief() -> void:\n\tvar window := _relief_description()\n"+body+"\tregion_view.set_surface_reference(window.surface as Dictionary)\n"
	if perf_comparison_script.reload()!=OK: return false
	var bundle: Dictionary=perf_comparison_scene.get("_bundled").duplicate(true)
	var variants: Array=bundle["variants"]
	var replacements := 0
	for index: int in range(variants.size()):
		if variants[index] is Script and (variants[index] as Script).get_global_name()=="GlobeRenderer":
			variants[index]=perf_comparison_script
			replacements+=1
	if replacements!=1: return false
	bundle["variants"]=variants
	perf_comparison_scene.set("_bundled",bundle)
	perf_binding_variant=variant
	print("R57_PERFORMANCE_BINDING ",variant," same release executable, diagnostic scene script only")
	return true

func acceptance_interaction_performance(world: Object) -> void:
	if perf_binding_variant!="candidate" and renderer.get_script()!=perf_comparison_script:
		push_error("Finite binding comparison was not installed in the formal renderer")
		get_tree().quit(8)
		return
	get_window().title="WWO R57 交互计时 · 自动结束";get_window().grab_focus()
	var scope_path := OS.get_environment("WWO_PERF_SCOPE")
	if not scope_path.is_empty():load(scope_path).call("begin_session")
	perf_relief=renderer.get("relief");perf_region=renderer.get("_region_layer");perf_world=renderer.get("_world_layer");perf_local=renderer.get("local_layer")
	perf_relief.decode_asset=tracked_decode
	RenderingServer.frame_pre_draw.connect(performance_pre_draw)
	RenderingServer.frame_post_draw.connect(performance_post_draw)
	var places: Array=[["paris",2.3522,48.8566,250.0],["spain",-7.5,42.5,250.0],["east",31.6,59.95,100.1941],["ladoga",31.5,60.35,100.1941],["greenland",-42.0,73.5,1500.0],["sydney",151.2093,-33.8688,500.0]]
	var requested := OS.get_environment("WWO_VISUAL_PLACES").split(",",false)
	if not requested.is_empty():places=places.filter(func(p:Array)->bool:return str(p[0]) in requested)
	if OS.get_environment("WWO_PERF_CLOSEOUT")=="1":
		var clock:GameClock=world.get("_world").get("game_clock")
		var control:TimeControl=world.get("time_control")
		if clock.total_minutes()<1440:
			control.call("set_speed",4)
			var deadline:=Time.get_ticks_msec()+60000
			while clock.total_minutes()<1440 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		if not control.paused:control.call("toggle_pause")
		await settle();await wait_seconds(.5)
	for warm: String in OS.get_environment("WWO_PERF_WARMUP").split(",",false):
		if warm=="paris":
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await settle()
	if OS.get_environment("WWO_PERF_ECONOMIC_OVERLAY")=="1":
		await performance_economic_overlay(world)
		RenderingServer.frame_pre_draw.disconnect(performance_pre_draw);RenderingServer.frame_post_draw.disconnect(performance_post_draw)
		world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0);return
	for cycle: int in range(3):
		controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)));controller.call("set_world_zoom",.86);await settle()
		performance_begin("world/%d/idle"%cycle);await wait_seconds(1.2);performance_end()
		performance_begin("world/%d/rotate"%cycle);await performance_drag(Vector2(5,0),8);await wait_seconds(.4);performance_end()
		performance_begin("world/%d/zoom"%cycle)
		for direction: MouseButton in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:performance_wheel(direction);await wait_seconds(.07)
		await wait_seconds(.4);performance_end()
	if OS.get_environment("WWO_PERF_CLOSEOUT")=="1":
		await performance_closeout(world,places)
		if not scope_path.is_empty():acceptance_save("function_costs",load(scope_path).call("snapshot"))
		RenderingServer.frame_pre_draw.disconnect(performance_pre_draw);RenderingServer.frame_post_draw.disconnect(performance_post_draw)
		world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0);return
	for place: Array in places:
		for mode: String in (OS.get_environment("WWO_PERF_MODES").split(",",false) if not OS.get_environment("WWO_PERF_MODES").is_empty() else ["geographic","political"]):
			controller.call("set_map_mode",mode)
			for cycle: int in range(3):
				get_window().grab_focus();world.get("main_shell").set("_context_open",false)
				var prefix: String="%s/%s/%d/"%[place[0],mode,cycle]
				controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await settle()
				performance_begin(prefix+"entry")
				controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,2.6,0.0,renderer.get("size"));await settle()
				controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await settle();performance_end()
				performance_begin(prefix+"installed_idle");await wait_seconds(1.2);performance_end()
				performance_begin(prefix+"wheel")
				for direction: MouseButton in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
					for step: int in range(3):performance_wheel(direction);await wait_seconds(.07)
				await settle();performance_end()
				performance_begin(prefix+"pan");await performance_drag(Vector2(6,0),8);await performance_drag(Vector2(-6,0),8);await settle();performance_end()
				# A zoom-in floor can make the up/down sequence asymmetric.
				# Restore and install the target before timing repeated identical views.
				controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await settle()
				performance_begin(prefix+"repeat_installed")
				for step: int in range(3):
					var began := Time.get_ticks_usec();controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));perf_inputs.append({"event":"focus_same","call_us":Time.get_ticks_usec()-began});await wait_seconds(.1)
				await settle();performance_end()
				performance_begin(prefix+"exit");controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await settle();await wait_seconds(.3);performance_end()
				print("R57_PERFORMANCE ",prefix," complete")
				acceptance_save("performance",{"binding_variant":perf_binding_variant,"profile_inventories":perf_profile_inventories,"repeat_restored_before_timing":true,"columns":["process_frame","time_us","interval_us","engine_process_us","engine_physics_us","render_pre_to_post_wall_us","loading","moving","focused","draw_calls","objects_drawn","primitives"],"phases":perf_phases,"device":RenderingServer.get_video_adapter_name(),"selection_ms":selection_ms,"decode_events":decode_events,"note":"Ordinary frame intervals, no GPU readback. pre/post-draw is CPU wall time, not GPU time. Effective state transitions do not count every request call."})
	if not scope_path.is_empty():acceptance_save("function_costs",load(scope_path).call("snapshot"))
	RenderingServer.frame_pre_draw.disconnect(performance_pre_draw);RenderingServer.frame_post_draw.disconnect(performance_post_draw)
	world.set("_departure_target","menu");world.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func performance_economic_overlay(host:Object) -> void:
	var supported:bool=renderer.has_method("set_topic_facts")
	controller.call("set_map_mode","political")
	if controller.labels_enabled:controller.call("toggle_labels")
	var before:=economic_authority_state(host)
	var authority_reference:=before.duplicate(true)
	for key:String in ["world","renderer","controller","camera","clock_owner","step","native"]:authority_reference.erase(key)
	for cycle:int in range(3):
		var states:Array=[false,true] if supported else [false]
		if cycle==1:states.reverse()
		for enabled:bool in states:
			get_window().grab_focus()
			if supported and bool(controller.get("economic_supplements_enabled"))!=enabled:controller.call("toggle_economic_supplements")
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await performance_closeout_settle()
			host.get("main_shell").set("_context_open",false);await wait_seconds(.5)
			var prefix:="paris/political/supplement_%s/%d/"%["on" if enabled else "off",cycle]
			performance_begin(prefix+"idle");await wait_seconds(1);performance_end()
			performance_begin(prefix+"pan");await performance_drag(Vector2(6,0),8);await performance_drag(Vector2(-6,0),8);await performance_closeout_settle();performance_end()
			performance_begin(prefix+"same_view")
			for repeat:int in range(3):
				if supported:host.call("_request_economic_topic_refresh")
				await wait_seconds(.2)
			performance_end()
			acceptance_save("performance",{"integration_present":supported,"same_authority":economic_authority_state(host)==before,"authority_reference":authority_reference,"profile_inventories":perf_profile_inventories,"columns":["process_frame","time_us","interval_us","engine_process_us","engine_physics_us","render_pre_to_post_wall_us","loading","moving","focused","draw_calls","objects_drawn","primitives"],"phases":perf_phases,"device":RenderingServer.get_video_adapter_name(),"note":"Same250mpp political input; labels off; frozen current formal world. Supplement order alternates by cycle. Ordinary frame timing has no GPU readback."})

func performance_closeout_settle() -> int:
	var began:=Time.get_ticks_msec()
	if await settle()<0:return -1
	while Time.get_ticks_msec()-began<30000:
		await get_tree().process_frame
		var ready:bool=renderer.get("_overlay_thread")==null and (renderer.get("_overlay_uploads") as Array).is_empty() and (renderer.get("_overlay_installing") as Dictionary).is_empty() and not perf_local.preparing and not renderer.get("local_content").preparing() and not renderer.get("region_view").landmark_preparing()
		if ready:
			await wait_seconds(.2)
			if renderer.get("_overlay_thread")==null and (renderer.get("_overlay_uploads") as Array).is_empty():return Time.get_ticks_msec()-began
	return -1

func performance_closeout_save(world:Object, initial_economies:Dictionary, initial_revision:int) -> void:
	var economies:Dictionary={}
	for id:String in renderer.get("political").get("economies"):
		if renderer.get("political").call("economic_available",id):economies[id]=(renderer.get("political").get("economies")[id] as Dictionary).get("daily_totals",{})
	acceptance_save("performance",{"binding_variant":perf_binding_variant,"profile_inventories":perf_profile_inventories,"closeout":true,"columns":["process_frame","time_us","interval_us","engine_process_us","engine_physics_us","render_pre_to_post_wall_us","loading","moving","focused","draw_calls","objects_drawn","primitives"],"phases":perf_phases,"device":RenderingServer.get_video_adapter_name(),"selection_ms":selection_ms,"decode_events":decode_events,"clock_minutes":world.get("_world").get("game_clock").total_minutes(),"economic_totals_initial":initial_economies,"economic_totals":economies,"economic_projection_unchanged":economies==initial_economies,"economic_revision_initial":initial_revision,"economic_revision_final":world.get("_world").get("economy_state").get("_state_revision"),"note":"Actual candidate; ordinary intervals without GPU readback. Switch cycle0 is first at this location; later cycles reuse prepared resources. Labels alternate off/on order by cycle. Economic projection may refresh lazily; authority revision is recorded separately."})

func performance_closeout(world:Object, places:Array) -> void:
	var initial_revision:int=world.get("_world").get("economy_state").get("_state_revision")
	var economies:Dictionary={}
	for id:String in renderer.get("political").get("economies"):
		if renderer.get("political").call("economic_available",id):economies[id]=((renderer.get("political").get("economies")[id] as Dictionary).get("daily_totals",{}) as Dictionary).duplicate(true)
	var shell:MainShell=world.get("main_shell")
	for place:Array in places:
		if controller.labels_enabled:controller.call("toggle_labels")
		controller.call("set_map_mode","geographic")
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await performance_closeout_settle()
		for cycle:int in range(3):
			for mode:String in ["political","fulfillment","shortage","geographic"]:
				performance_begin("%s/switch/%s/%d"%[place[0],mode,cycle])
				var began:=Time.get_ticks_usec();shell.call("_activate","map_mode:"+mode);shell.set("_context_open",false)
				perf_inputs.append({"event":"mode_switch","mode":mode,"call_us":Time.get_ticks_usec()-began})
				await performance_closeout_settle();await wait_seconds(.5);performance_end()
			performance_closeout_save(world,economies,initial_revision)
		for mode:String in ["geographic","political"]:
			controller.call("set_map_mode",mode)
			for cycle:int in range(3):
				var label_states:Array=[false,true] if place[0]=="paris" and mode=="political" else [false]
				if cycle==1:label_states.reverse()
				for labels:bool in label_states:
					if controller.labels_enabled!=labels:controller.call("toggle_labels")
					var prefix:String="%s/%s/%s/%d/"%[place[0],mode,"on" if labels else "off",cycle]
					controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await performance_closeout_settle()
					performance_begin(prefix+"entry")
					controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,2.6,0.0,renderer.get("size"));await performance_closeout_settle()
					controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await performance_closeout_settle();performance_end()
					performance_begin(prefix+"installed_idle");await wait_seconds(1.2);performance_end()
					performance_begin(prefix+"wheel")
					for direction:MouseButton in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
						for step:int in range(3):performance_wheel(direction);await wait_seconds(.07)
					await performance_closeout_settle();performance_end()
					performance_begin(prefix+"pan");await performance_drag(Vector2(6,0),8);await performance_drag(Vector2(-6,0),8);await performance_closeout_settle();performance_end()
					controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await performance_closeout_settle()
					performance_begin(prefix+"repeat_installed")
					for step:int in range(3):controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])),renderer.get("size")*.5,float(place[3])*.001,0.0,renderer.get("size"));await wait_seconds(.1)
					await performance_closeout_settle();performance_end()
					performance_begin(prefix+"exit");controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(place[1],place[2])));controller.call("set_world_zoom",.86);await performance_closeout_settle();await wait_seconds(.3);performance_end()
					performance_closeout_save(world,economies,initial_revision)
					print("R57_CLOSEOUT ",prefix," complete")
	# The single label image is outside every ordinary performance interval.
	if OS.get_environment("WWO_PERF_FINAL_LABEL_IMAGE")=="1":
		controller.call("set_map_mode","political")
		if not controller.labels_enabled:controller.call("toggle_labels")
		controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await performance_closeout_settle();await wait_seconds(.5)
		acceptance_save("closeout-labels",{"point":state_point("paris_day1_labels"),"country_label_rects":renderer.get("region_view").country_label_rects.size(),"symbols":(renderer.get("_symbol_layout") as Array).size(),"names":(renderer.get("_symbol_text") as Array).map(func(row:Dictionary)->String:return str(row.name)),"clock_minutes":world.get("_world").get("game_clock").total_minutes()})
		acceptance_image("paris_day1_labels")
		controller.call("set_world_zoom",.86);await performance_closeout_settle()

func economic_action_clock(host:Object, target:int) -> void:
	var clock:Object=host.get("_world").get("game_clock")
	var control:Object=host.get("time_control")
	control.call("set_speed",4)
	var deadline:=Time.get_ticks_msec()+90000
	while clock.total_minutes()<target and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not control.paused:control.call("toggle_pause")
	await wait_seconds(.3)

func economic_action_trade(host:Object) -> Dictionary:
	var model:WorldState=host.get("_world")
	var observer:=model.player_state.player_id()
	var best:Dictionary={};var best_score:=-1
	for subject:Dictionary in model.economy_r1.map_subjects(observer):
		if subject.kind!="firm":continue
		var own:=LivelihoodAction.query_firm(model,observer,str(subject.id))
		for operation:Dictionary in own.get("operations",[]):
			var site:=str(operation.get("site_id",""))
			for offset:int in range(16):
				var known:=LivelihoodAction.query_business(model,observer,str(subject.id),site,1,offset)
				for offer:Dictionary in known.get("offers",[]):
					if not bool(offer.get("can_order",false)) or offer.get("from_place_id")==offer.get("to_place_id") or offer.get("route_legs",[]).is_empty():continue
					var score:=20 if offer.to_place_id=="place:lyon" else 0
					if offer.from_place_id=="place:marseille":score+=20
					if offer.good=="soap":score+=10
					if score>best_score:
						best_score=score;best={"firm":str(subject.id),"site":site,"offset":offset,"offer":offer.duplicate(true),"business":known.duplicate(true)}
				if offset+1>=int(known.get("offer_total",0)):break
	return best

func economic_action_state(host:Object, trade:Dictionary, order_id:String) -> Dictionary:
	var model:WorldState=host.get("_world");var native:=model.economy_r1
	var quote:Dictionary=trade.offer;var good:=str(quote.good)
	var order:Dictionary=native._orders.get(order_id,{}).duplicate(true)
	var row:Dictionary={"minute":model.game_clock.total_minutes(),"order_id":order_id,"world_order":order,"observer_order":{},"seller_stock":native._stocks.get(str(quote.seller_site),{}).get(good),"seller_committed":native._committed(str(quote.seller_site),good),"buyer_stock":native._stocks.get(str(trade.site),{}).get(good),"buyer_accounts":{},"reservation":model.ledger_state._reservations.get(order_id,{}).duplicate(true),"shipments":{},"delivery_receipts":[],"payments":[],"reserved_portions":[]}
	for id:String in model.ledger_state._accounts:
		var account:Dictionary=model.ledger_state._accounts[id]
		if account.owner_id==trade.firm:row.buyer_accounts[id]={"balance":model.ledger_state.balance(id),"available":model.ledger_state.available_balance(id),"reserved":model.ledger_state.reserved_balance(id),"denomination":account.denomination}
	for id:String in native._shipments:
		if native._shipments[id].get("order_id")==order_id:
			row.shipments[id]=native._shipments[id].duplicate(true)
			row.shipments[id]["physical_quantity"]=native._lots.quantity_at("CARGO|"+id,good)
	for receipt:Dictionary in native._delivery_receipts.values():
		if receipt.get("order_id")==order_id:row.delivery_receipts.append(receipt.duplicate(true))
	for payment:Dictionary in model.ledger_state._transactions:
		if payment.get("reference_id")==order_id:row.payments.append(payment.duplicate(true))
	for id:String in native._lots.portions:
		var portion:Dictionary=native._lots.portions[id]
		if portion.get("reserved_for")==order_id and not order_id.is_empty():row.reserved_portions.append({"id":id,"location":portion.get("location"),"remaining":portion.get("remaining"),"reserved_for":portion.get("reserved_for")})
	for known:Dictionary in LivelihoodAction.query_firm(model,model.player_state.player_id(),str(trade.firm)).get("orders",[]):
		if str(known.id)==order_id:row.observer_order=known;break
	return row

func economic_action_core(host:Object) -> Dictionary:
	var result:=economic_authority_state(host)
	for key:String in ["world","renderer","controller","camera","clock_owner","step","native"]:result.erase(key)
	result["commands"]=host.get("_world").get("economy_r1").get("_commands").duplicate(true)
	return result

func economic_action_profile(label:String, pan:bool=false) -> void:
	performance_begin("economic-action/"+label)
	if pan:
		await performance_drag(Vector2(6,0),8);await performance_drag(Vector2(-6,0),8);await performance_closeout_settle()
	else:await wait_seconds(1.2)
	performance_end()

func economic_action_finish(host:Object, result:Dictionary, status:String, code:int) -> void:
	result["status"]=status;result["performance_phases"]=perf_phases
	result["performance_columns"]=["process_frame","time_us","interval_us","engine_process_us","engine_physics_us","render_pre_to_post_wall_us","loading","moving","focused","draw_calls","objects_drawn","primitives"]
	acceptance_save("economic-action",result)
	if RenderingServer.frame_pre_draw.is_connected(performance_pre_draw):RenderingServer.frame_pre_draw.disconnect(performance_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(performance_post_draw):RenderingServer.frame_post_draw.disconnect(performance_post_draw)
	print("R57_ECONOMIC_ACTION ",status)
	host.set("_departure_target","menu");host.call("_leave_world");await wait_seconds(.5);get_tree().quit(code)

func economic_action_restore(host:Object, trade:Dictionary, order_id:String) -> Dictionary:
	var before:=economic_action_core(host)
	var physical:=economic_action_state(host,trade,order_id)
	host.call("_on_action_requested","slot:save:4")
	var path:=FormalPersistence.slot_path(4)
	var saved:bool=not bool(host.get("_save_dirty")) and FileAccess.file_exists(path)
	var saved_file:=FileAccess.open(path,FileAccess.READ) if saved else null
	var size_bytes:=saved_file.get_length() if saved_file!=null else 0
	if saved_file!=null:saved_file.close()
	if saved:host.call("_on_action_requested","slot:load:4");await wait_seconds(.8)
	var restored:=economic_action_state(host,trade,order_id)
	return {"saved":saved,"path":path,"bytes":size_bytes,"same_authority":saved and economic_action_core(host)==before,"same_cargo_and_reservation":physical.shipments==restored.shipments and physical.reservation==restored.reservation and physical.reserved_portions==restored.reserved_portions,"same_order":physical.world_order==restored.world_order}

func participation_frame(host: Object) -> Dictionary:
	var model:WorldState=host.get("_world")
	var person:=model.player_state.player_id()
	var native:=model.economy_r1
	var observed:=LivelihoodAction.query(model,person)
	return {"minute":model.game_clock.total_minutes(),"person":person,"place":model.person_overlay.current_place(person),"personal":model.personal_economy_state.person_economy(person),"totals":observed.get("totals",{}),"ledger":model.ledger_state._transactions.duplicate(true),"firm_cash":model.ledger_state.balance("account:opening_paris_workshop"),"stock":native._stocks.duplicate(true),"work":native._work_records.duplicate(true),"wages":native._wages.duplicate(true),"orders":native._orders.size(),"shipments":native._shipments.size(),"order_rows":native._orders.duplicate(true),"receipts":native._delivery_receipts.duplicate(true),"holding":model.personal_economy_state.holding(person,"native:bread"),"needs":observed.get("need_today",{}),"living_records":model.personal_economy_state.living_records(person,12)}

func participation_restore(host: Object, slot: int = 4) -> Dictionary:
	var model:WorldState=host.get("_world")
	var before:=participation_frame(host)
	var native:=model.economy_r1.snapshot()
	var organization:=model.organization_state.snapshot()
	var population:=model.population_state.snapshot()
	var persons:=model.person_overlay.snapshot()
	var personal:=model.personal_economy_state.snapshot()
	host.call("_on_action_requested","slot:save:"+str(slot))
	var path:=FormalPersistence.slot_path(slot)
	var saved:=not bool(host.get("_save_dirty")) and FileAccess.file_exists(path)
	var file:=FileAccess.open(path,FileAccess.READ) if saved else null
	var bytes:=file.get_length() if file!=null else 0
	if file!=null:file.close()
	if saved:host.call("_on_action_requested","slot:load:"+str(slot));await wait_seconds(.5)
	model=host.get("_world")
	return {"saved":saved,"bytes":bytes,"same_state":saved and before==participation_frame(host) and native==model.economy_r1.snapshot() and organization==model.organization_state.snapshot() and population==model.population_state.snapshot() and persons==model.person_overlay.snapshot() and personal==model.personal_economy_state.snapshot(),"new_world_instance":model.get_instance_id()!=host.get_meta("participation_initial_world",0)}

func resident_frame(host: Object) -> Dictionary:
	var model: WorldState = host.get("_world")
	var e := model.economy_r1
	var actors: Dictionary = {}
	for person: String in e.personal_accounts():
		actors[person] = {"place":model.person_overlay.current_place(person),"account":e._account(person),"cash":model.ledger_state.balance(e._account(person)),"available":model.ledger_state.available_balance(e._account(person)),"inventory":e.personal_inventory(person),"totals":e._totals[person].duplicate(true),"need":e._needs.get(person,{}).duplicate(true),"contract":e._contracts.get(person,{}).duplicate(true)}
	return {"minute":model.game_clock.total_minutes(),"persons":model.person_overlay.person_ids(),"player":model.player_state.player_id(),"actors":actors,"firm_cash":model.ledger_state.balance("account:opening_paris_workshop"),"site_stock":e._stocks["site:opening_paris_workshop:paris"].duplicate(true),"work_count":e._work_records.size(),"wage_count":e._wages.size(),"orders":e._orders.size(),"shipments":e._shipments.size()}

func acceptance_ordinary_residents(host: Object) -> void:
	get_window().title = "WWO 普通居民七日 · 隔离验证"; get_window().grab_focus()
	var model: WorldState = host.get("_world")
	var shell: MainShell = host.get("main_shell")
	var person := model.player_state.player_id()
	var npc := "person:formal_generated_country_fra_0002"
	var mode := OS.get_environment("WWO_RESIDENT_CASE")
	var r: Dictionary = {"variant":mode,"user_dir":OS.get_user_data_dir(),"policy":"Ordinary oil-painting New World; only GameClock and optional player UI requests; no NPC requests by driver.","opening":model.economy_r1.config.duplicate(true),"initial":resident_frame(host),"days":[],"restores":[]}
	var ok: bool = r.initial.persons==[person,npc] and r.initial.actors[person].cash==2500 and r.initial.actors[npc].cash==0 and r.initial.firm_cash==1200 and r.initial.site_stock.bread==12 and r.initial.site_stock.grain==60
	if not ok: await economic_action_finish(host,r,"RESIDENT_OPENING_INVALID",5); return
	r.restores.append(await participation_restore(host))
	if mode in ["participating","released"]:
		host.call("_open_economic_business",person,""); await wait_seconds(.2)
		ok = await economic_click(shell,"native:apply:job:opening_paris_workshop|") and ok
		ok = await economic_click(shell,"native:work") and ok
	for date: int in range(1,8):
		await economic_action_clock(host,date*1440)
		model=host.get("_world")
		if mode in ["participating","released"] and date==2:
			host.call("_open_economic_business",person,""); await wait_seconds(.2)
			ok = await economic_click(shell,"native:work") and ok
			if mode=="released":
				r["before_release"]=resident_frame(host)
				await economic_action_clock(host,2940)
				ok = await economic_click(shell,"native:leave_job") and ok
				model=host.get("_world")
				r["queued_exit"]=model.economy_r1._employment_ends.duplicate(true)
				r["pending_person_view"]=shell.person_page.get("_personal").duplicate(true)
				r["duplicate_exit_disabled"]=not await economic_click(shell,"native:leave_job")
				acceptance_image("employment_exit_pending")
				r.restores.append(await participation_restore(host))
				await economic_action_clock(host,4260)
				r["before_boundary"]=resident_frame(host)
		if mode=="released" and date==3:
			r["after_release"]=resident_frame(host)
			r["exit_wages"]=model.economy_r1._wages.duplicate(true)
			shell.call("set_page","map"); controller.call("set_map_mode","economic"); await settle()
			host.call("_query_economic_details",person,0); await wait_seconds(.3)
			r["released_map"]=shell.economic_map.snapshot.duplicate(true)
			r["released_map_wages_match"]=r.released_map.get("firm",{}).get("cash")==2506 and r.released_map.get("firm",{}).get("totals",{}).get("work_hours")==4 and r.released_map.get("firm",{}).get("wage_outstanding")==6
			acceptance_image("employment_reopened")
		if mode in ["participating","released"] and date==3:
			shell.call("_activate","person:native"); await wait_seconds(.2)
			ok = await economic_click(shell,"person:market") and ok
			ok = await economic_click(shell,"commodity:select:native:bread|site:opening_paris_workshop:paris") and ok
			ok = await economic_click(shell,"purchase") and ok
			ok = await economic_button(shell,"查看") and ok
			ok = await economic_click(shell,"consume") and ok
			r["player_after_consumption"]=resident_frame(host)
		var frame:=resident_frame(host)
		r.days.append(frame)
		if not r.has("decisions"): r["decisions"]=[]
		r.decisions.append(model.economy_r1._decision_counts.duplicate(true))
		if date in [1,2,3,7] or (mode=="released" and date==5): r.restores.append(await participation_restore(host))
		if date==3:
			# The camera leaves Paris; neither person travels or loses settlement.
			shell.call("set_page","map")
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(4.8357,45.7640)),renderer.get("size")*.5,.5,0.0,renderer.get("size")); await settle()
	model=host.get("_world")
	r["final"]=resident_frame(host)
	r["npc_actions"]=[]
	var player_accepted: int = 0
	var player_requests: int = 0
	for entry: Dictionary in model.economy_r1._commands.values():
		var envelope:=entry.envelope as Dictionary
		if envelope.actor==person: player_requests+=1
		if envelope.actor==person and entry.result.accepted: player_accepted+=1
		if envelope.actor==npc:
			r.npc_actions.append({"command":envelope.command.duplicate(true),"result":entry.result.duplicate(true)})
	r["player_accepted_actions"]=player_accepted
	r["player_requests"]=player_requests
	r["work"]=model.economy_r1._work_records.duplicate(true)
	r["wages"]=model.economy_r1._wages.duplicate(true)
	r["orders"]=model.economy_r1._orders.duplicate(true)
	r["receipts"]=model.economy_r1._delivery_receipts.duplicate(true)
	r["ledger"]=model.ledger_state._transactions.duplicate(true)
	r["npc_batches"]=model.economy_r1.owned_batch_rows(npc,npc)
	r["physical_totals"]=model.economy_r1._physical_totals.duplicate(true)
	r["employment_ends"]=model.economy_r1._employment_ends.duplicate(true)
	var applications: Array=r.npc_actions.filter(func(x:Dictionary)->bool:return x.command.kind=="apply")
	r["application_count"]=applications.size()
	r["capacity_refusals"]=applications.filter(func(x:Dictionary)->bool:return x.result.reason=="NO_VACANCY").size()
	r["accepted_employments"]=applications.filter(func(x:Dictionary)->bool:return x.result.accepted).size()
	var before:=resident_frame(host)
	var owners:=[model.get_instance_id(),model.economy_r1.get_instance_id(),model.game_clock.get_instance_id(),model.ledger_state.get_instance_id()]
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.5,0.0,renderer.get("size"))
	controller.call("set_map_mode","economic"); await settle()
	host.call("_query_economic_details",person,0); await wait_seconds(.2)
	r["public_jobs"]=shell.economic_map.snapshot.get("firm",{}).get("known_jobs",[]).duplicate(true)
	r["npc_not_player_query"]=LivelihoodAction.query(model,npc).is_empty()
	r["return_political"]=await economic_button(shell.economic_map,"返回政治地图")
	await settle()
	r["read_only_same_authority"]=before==resident_frame(host) and owners==[model.get_instance_id(),model.economy_r1.get_instance_id(),model.game_clock.get_instance_id(),model.ledger_state.get_instance_id()]
	r["npc_stayed_paris"]=r.days.all(func(f:Dictionary)->bool:return f.actors[npc].place=="place:paris")
	var n:=r.final.actors[npc] as Dictionary
	r["autonomy_complete"]=n.totals.work_hours>0 and n.totals.income>0 and n.totals.categories.food.satisfied>0 and n.inventory.bread>=0 and player_requests==0 if mode=="idle" else n.totals.work_hours==0 and n.cash==0 and r.final.actors[person].cash==2510 and r.player_after_consumption.actors[person].need.categories.food.satisfied==1 and r.npc_actions.any(func(x:Dictionary)->bool:return x.command.kind=="apply" and x.result.reason=="NO_VACANCY")
	if mode=="participating": r.autonomy_complete=r.autonomy_complete and r.application_count==1 and r.capacity_refusals==1
	if mode=="released":
		r.autonomy_complete=r.before_boundary.actors[person].contract.get("job")=="job:opening_paris_workshop" and r.before_boundary.actors[npc].contract.is_empty() and r.after_release.actors[person].contract.is_empty() and r.after_release.actors[npc].contract.get("job")=="job:opening_paris_workshop" and r.after_release.actors[npc].totals.income==0 and r.exit_wages["work:3:"+person].remaining==6 and r.application_count==2 and r.capacity_refusals==1 and r.accepted_employments==1 and n.totals.work_hours==8 and n.totals.income==18 and n.cash==10 and n.inventory.bread==1 and n.totals.categories.food.satisfied==3 and n.totals.categories.food.unmet==4 and r.final.actors[person].cash==2510 and r.duplicate_exit_disabled and r.pending_person_view.employment.end_pending and not r.pending_person_view.employment.can_work_now and r.employment_ends.values().all(func(x:Dictionary)->bool:return x.status=="APPLIED" and x.effective_minute==4320)
		r.autonomy_complete=r.autonomy_complete and r.released_map_wages_match
	ok = ok and r.autonomy_complete and r.npc_stayed_paris and r.npc_not_player_query and r.read_only_same_authority and r.return_political and r.restores.all(func(x:Dictionary)->bool:return x.saved and x.same_state)
	await economic_action_finish(host,r,"ORDINARY_RESIDENTS_COMPLETE" if ok else "ORDINARY_RESIDENTS_FAILED",0 if ok else 5)

func acceptance_economic_participation(host: Object) -> void:
	get_window().title="WWO 普通人物劳动与消费 · 隔离验证";get_window().grab_focus()
	var model:WorldState=host.get("_world")
	var shell:MainShell=host.get("main_shell")
	var view:FormalEconomyMapView=shell.economic_map
	var person:=model.player_state.player_id()
	var result:Dictionary={"user_dir":OS.get_user_data_dir(),"case":model.economy_r1.config.case_id,"timeline":[],"source":"Oil-painting menu ordinary New World; no development flags, research save or world mutation by driver."}
	result["initial"]=participation_frame(host)
	result["opening_organizations"]=model.economy_r1.config.opening_organizations.duplicate(true)
	result["organization"]=model.organization_state.organization("organization:opening_paris_workshop")
	result["member_and_appointments"]={"memberships":model.organization_state.memberships_for_person(person),"appointments":model.organization_state.appointments_for_person(person)}
	result["opening_stock_sources"]=model.economy_r1._lots.sources.duplicate(true)
	result["initial_identity_valid"]=person==WorldBootstrap.DEFAULT_FORMAL_PERSON_ID and result.initial.place=="place:paris" and result.initial.personal.cash==2500 and result.initial.personal.employment.is_empty() and result.initial.firm_cash==1200 and LivelihoodAction.query(model,person).managed_firms.is_empty()
	result["no_development_flags"]=not Array(OS.get_cmdline_user_args()).any(func(arg:String)->bool:return arg.begins_with("--formal-") and arg!="--formal-single-employer-opening")
	if not result.initial_identity_valid or not result.no_development_flags:await economic_action_finish(host,result,"ORDINARY_OPENING_INVALID",5);return
	host.set_meta("participation_initial_world",model.get_instance_id())
	var owners:={"world":model.get_instance_id(),"native":model.economy_r1.get_instance_id(),"clock":model.game_clock.get_instance_id(),"ledger":model.ledger_state.get_instance_id(),"step":host.get("_simulation_step").get_instance_id()}
	controller.call("set_map_mode","political")
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.5,0.0,renderer.get("size"));await settle();await wait_seconds(.7)
	var baseline:=participation_frame(host)
	result["political_marker"]=false
	for row:Dictionary in renderer.get("_symbol_layout"):
		var id:=str(row.id)
		if not id.begins_with("place:"):id="place:"+id
		if id!="place:paris" or not (renderer.get("_topic_hits") as Dictionary).has(id):continue
		await mouse_button((row.rect as Rect2).get_center(),MOUSE_BUTTON_LEFT,true);await mouse_button((row.rect as Rect2).get_center(),MOUSE_BUTTON_LEFT,false);await wait_seconds(.4)
		result.political_marker=view.visible;break
	result["expanded_from_detail"]=await economic_button(view,"完整经济地图")
	await settle();await wait_seconds(.3)
	result["initial_map"]=view.snapshot.duplicate(true)
	result["map_to_person"]=await economic_button(view,"岗位与个人订单")
	await wait_seconds(.4)
	result["navigation_read_only"]=baseline==participation_frame(host)
	result["same_authority_navigation"]=owners=={"world":model.get_instance_id(),"native":model.economy_r1.get_instance_id(),"clock":model.game_clock.get_instance_id(),"ledger":model.ledger_state.get_instance_id(),"step":host.get("_simulation_step").get_instance_id()}
	if not result.political_marker or not result.expanded_from_detail or not result.map_to_person:acceptance_image("ordinary_navigation_failure");await economic_action_finish(host,result,"ORDINARY_NAVIGATION_INCOMPLETE",5);return
	result["apply_clicked"]=await economic_click(shell,"native:apply:job:opening_paris_workshop|")
	await wait_seconds(.2)
	result["work_clicked"]=await economic_click(shell,"native:work")
	result.timeline.append(participation_frame(host))
	var work_command:Dictionary={}
	for entry:Dictionary in model.economy_r1._commands.values():
		if entry.envelope.command.kind=="work" and entry.result.accepted:work_command=entry.envelope.command.duplicate(true)
	if work_command.is_empty():acceptance_image("ordinary_work_failure");await economic_action_finish(host,result,"ORDINARY_WORK_NOT_ACCEPTED",5);return
	var booked:=model.economy_r1.snapshot()
	result["duplicate_action"]=LivelihoodAction.execute(model,person,work_command)
	result["duplicate_action_unchanged"]=booked==model.economy_r1.snapshot()
	result["second_work_rejected"]=LivelihoodAction.execute_current(model,"work",{"hours":2})
	result["business_denied"]=LivelihoodAction.execute_current(model,"buy",{"firm":"firm:opening_paris_workshop"})
	result["booking_restore"]=await participation_restore(host)
	model=host.get("_world")
	await economic_action_clock(host,1440)
	result.timeline.append(participation_frame(host))
	result["unpaid_restore"]=await participation_restore(host)
	model=host.get("_world")
	await economic_action_clock(host,2880)
	result.timeline.append(participation_frame(host))
	result["paid_restore"]=await participation_restore(host)
	model=host.get("_world")
	result["paid_once"]=result.timeline[1].personal.cash==2500 and result.timeline[2].personal.cash==2506 and result.timeline[2].firm_cash==1194
	# A second explicit work choice proves continued use of the same contract.
	host.call("_open_economic_business",person,"");await wait_seconds(.3)
	result["second_period_work_clicked"]=await economic_click(shell,"native:work")
	await economic_action_clock(host,4320)
	model=host.get("_world")
	host.call("_on_action_requested","person:native");await wait_seconds(.2)
	result["market_clicked"]=await economic_click(shell,"person:market")
	result["bread_clicked"]=await economic_click(shell,"commodity:select:native:bread|site:opening_paris_workshop:paris")
	result["purchase_quote"]=shell.economy_page.quote.duplicate(true)
	result["before_purchase"]=participation_frame(host)
	acceptance_image("ordinary_bread_quote")
	result["purchase_clicked"]=await economic_click(shell,"purchase")
	result["after_purchase"]=participation_frame(host)
	result["double_click_has_no_target"]=not await economic_click(shell,"purchase")
	result["double_click_unchanged"]=result.after_purchase==participation_frame(host)
	result["holding_link_clicked"]=await economic_button(shell,"查看")
	result["purchase_restore"]=await participation_restore(host)
	model=host.get("_world")
	shell.call("_activate","holding:select:native:bread");await wait_seconds(.3)
	result["holding_before_use"]=shell.person_page.get("_property").duplicate(true)
	acceptance_image("ordinary_bread_owned")
	result["consume_clicked"]=await economic_click(shell,"consume")
	result["after_consumption"]=participation_frame(host)
	result["consume_second_click_disabled"]=not await economic_click(shell,"consume")
	result["consume_no_repeat"]=result.after_consumption==participation_frame(host)
	result["consumption_restore"]=await participation_restore(host)
	model=host.get("_world")
	shell.call("_activate","person:native");await wait_seconds(.3)
	acceptance_image("ordinary_food_need_satisfied")
	result["consumer_complete"]=result.holding_link_clicked and result.consume_clicked and result.purchase_quote.get("fulfilment")=="ONSITE_REAL_STOCK_HANDOVER" and result.after_purchase.orders==1 and result.after_purchase.holding.get("quantity")==1 and result.after_purchase.personal.cash==2504 and result.after_purchase.firm_cash==1196 and result.after_purchase.needs==result.before_purchase.needs and result.after_consumption.holding.get("quantity")==0 and result.after_consumption.holding.get("consumed")==1 and result.after_consumption.needs.categories.food.satisfied==1 and result.after_consumption.needs.categories.food.unmet==0 and result.after_consumption.personal.cash==2504 and result.purchase_restore.same_state and result.consumption_restore.same_state and result.double_click_has_no_target and result.double_click_unchanged and result.consume_second_click_disabled and result.consume_no_repeat
	await economic_action_clock(host,5760)
	result["final"]=participation_frame(host)
	result["continued_contract"]=result.final.personal.cash==2510 and result.final.firm_cash==1190 and result.final.totals.income==12 and result.final.totals.work_hours==4 and result.final.work.size()==2 and result.final.wages.size()==2
	shell.call("_activate","person:native");await wait_seconds(.3)
	result["person_page_cash"]=shell.person_page.get("_personal").get("cash")
	acceptance_image("ordinary_work_paid")
	shell.call("set_page","map");controller.call("set_map_mode","economic");await settle();await wait_seconds(.5)
	host.call("_query_economic_details",person,0);await wait_seconds(.3)
	result["final_map"]=view.snapshot.duplicate(true)
	result["map_person_equal"]=result.person_page_cash==result.final.personal.cash and view.snapshot.firm.cash==result.final.personal.cash and view.snapshot.firm.totals==result.final.totals and view.snapshot.firm.participation.employment==result.final.personal.employment and view.snapshot.firm.participation.need_today==result.final.personal.need_today and view.snapshot.firm.participation.owned_inventory==result.final.personal.owned_inventory
	var before_map:=participation_frame(host);var pose:=economic_camera_state()
	result["returned_political"]=await economic_button(view,"返回政治地图");await settle();await wait_seconds(.3)
	result["political_facts"]=renderer.get("_topic_facts").duplicate(true)
	result["return_unchanged"]=before_map==participation_frame(host) and pose==economic_camera_state()
	result["political_own_income"]=result.political_facts.any(func(row:Dictionary)->bool:return row.get("kind")=="employment_site" and str(row.get("state","")).contains("12"))
	result["final_restore"]=await participation_restore(host)
	await economic_action_clock(host,5820)
	var after:=participation_frame(host)
	result["no_duplicate_wages_or_stock"]=after.ledger==result.final.ledger and after.wages==result.final.wages and after.stock==result.final.stock and after.work==result.final.work
	result["no_fabricated_orders"]=after.orders==1 and after.shipments==0 and after.order_rows.values()[0].delivered==1
	var passed:bool=result.apply_clicked and result.work_clicked and result.navigation_read_only and result.same_authority_navigation and result.duplicate_action_unchanged and not result.second_work_rejected.accepted and not result.business_denied.accepted and result.booking_restore.same_state and result.unpaid_restore.same_state and result.paid_restore.same_state and result.final_restore.same_state and result.paid_once and result.continued_contract and result.map_person_equal and result.returned_political and result.return_unchanged and result.political_own_income and result.no_duplicate_wages_or_stock and result.no_fabricated_orders and result.consumer_complete
	await economic_action_finish(host,result,"ORDINARY_PARTICIPATION_COMPLETE" if passed else "ORDINARY_PARTICIPATION_CHECK_FAILED",0 if passed else 5)

func acceptance_economic_action(host:Object) -> void:
	get_window().title="WWO 正式采购闭环 · 隔离验证";get_window().grab_focus()
	var model:WorldState=host.get("_world");var shell:Object=host.get("main_shell");var view:Object=shell.get("economic_map")
	var result:Dictionary={"user_dir":OS.get_user_data_dir(),"variant":OS.get_environment("WWO_ACTION_VARIANT"),"timeline":[],"policy":"Existing formal development configuration; no research Runtime, stock or authority injection."}
	if model.economy_r1==null:await economic_action_finish(host,result,"NO_NATIVE_CONFIGURATION",5);return
	var trade:Dictionary={}
	for day:int in range(4):
		if day>0:await economic_action_clock(host,day*1440)
		trade=economic_action_trade(host)
		if not trade.is_empty():break
	if trade.is_empty():await economic_action_finish(host,result,"NO_AUTHORIZED_EXECUTABLE_KNOWN_ROUTE",5);return
	result["trade"]=trade
	perf_relief=renderer.get("relief");perf_region=renderer.get("_region_layer");perf_world=renderer.get("_world_layer");perf_local=renderer.get("local_layer")
	RenderingServer.frame_pre_draw.connect(performance_pre_draw);RenderingServer.frame_post_draw.connect(performance_post_draw)
	controller.call("set_map_mode","political")
	if controller.labels_enabled:controller.call("toggle_labels")
	for cycle:int in range(0 if OS.get_environment("WWO_ACTION_SKIP_TIMING")=="1" else 3):
		for enabled:bool in ([false,true] if cycle!=1 else [true,false]):
			if bool(controller.get("economic_supplements_enabled"))!=enabled:controller.call("toggle_economic_supplements")
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await performance_closeout_settle()
			await economic_action_profile("political_%s_%d"%["on" if enabled else "off",cycle],true)
	if not controller.get("economic_supplements_enabled"):controller.call("toggle_economic_supplements")
	var place:Dictionary=model.spatial_catalog.get_place(str(trade.offer.to_place_id));var coordinates:Array=place.get("lon_lat",[])
	if coordinates.size()!=2:await economic_action_finish(host,result,"NO_LEGAL_CITY_ANCHOR",5);return
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(coordinates[0],coordinates[1])),renderer.get("size")*.5,.5,0.0,renderer.get("size"));await settle();await wait_seconds(.5)
	result["marker_state"]={"facts":renderer.get("_topic_facts").duplicate(true),"hits":renderer.get("_topic_hits").keys(),"symbols":(renderer.get("_symbol_layout") as Array).map(func(row:Dictionary)->String:return str(row.id)),"topic_places":renderer.call("topic_place_ids"),"mpp":controller.region_camera.km_per_pixel*1000}
	if renderer.has_method("set_topic_places"):
		result.marker_state["known_places"]=renderer.get("_topic_places").duplicate(true)
		result.marker_state["target_record"]=renderer.get("_symbol_place_records").get(str(trade.offer.to_place_id),renderer.get("_symbol_place_records").get(VNextSpatialCatalog.place_query_to_map_id(str(trade.offer.to_place_id)),{}))
		result.marker_state["model_visible"]=renderer.get("region_view").call("settlement_visible",str(trade.offer.to_place_id))
		result.marker_state["landmark_visible"]=renderer.get("region_view").call("landmark_visible",str(trade.offer.to_place_id))
		result.marker_state["source_pixel"]=TerrainPixelSource.serial(renderer.get("_place_points").get(str(trade.offer.to_place_id)))
		result.marker_state["country_rects"]=TerrainPixelSource.serial(renderer.get("region_view").get("country_label_rects"))
		var atlas:Object=renderer.get("_symbol_atlas")
		var icon:String=atlas.call("symbol_id",result.marker_state.target_record,str(trade.offer.to_place_id))
		result.marker_state["icon_spec"]=atlas.get("icons").get(icon,{})
		result.marker_state["location_stamp"]=host.get("_economic_locations_stamp").duplicate()
		var ground:Vector2=renderer.call("screen_point",GlobeProjection.lon_lat_to_unit(Vector2(coordinates[0],coordinates[1])))
		result.marker_state["ground_pixel"]=TerrainPixelSource.serial(ground)
		result.marker_state["nearby_symbols"]=[]
		for row:Dictionary in renderer.get("_symbol_layout"):
			if (row.rect as Rect2).get_center().distance_to(ground)<40:result.marker_state.nearby_symbols.append({"id":row.id,"kind":row.kind,"rect":TerrainPixelSource.serial(row.rect),"model":row.model})
		result.marker_state["nearby_exclusions"]=[]
		for box:Rect2 in renderer.call("_label_exclusions"):
			if box.intersects(Rect2(ground-Vector2(24,24),Vector2(48,48))):result.marker_state.nearby_exclusions.append(TerrainPixelSource.serial(box))
	var picked:=false
	for row:Dictionary in renderer.get("_symbol_layout"):
		if VNextSpatialCatalog.map_id_to_place_id(VNextSpatialCatalog.place_query_to_map_id(str(row.id)))!=str(trade.offer.to_place_id):continue
		if not (renderer.get("_topic_hits") as Dictionary).has(str(trade.offer.to_place_id)):continue
		await mouse_button((row.rect as Rect2).get_center(),MOUSE_BUTTON_LEFT,true);await mouse_button((row.rect as Rect2).get_center(),MOUSE_BUTTON_LEFT,false);await wait_seconds(.4);picked=view.visible;break
	result["political_marker_opened"]=picked
	if not picked:acceptance_image("marker_failure");await economic_action_finish(host,result,"OWN_SITE_MARKER_NOT_REACHABLE",5);return
	await economic_action_profile("political_details")
	result["expanded"]=await economic_button(view,"完整经济地图");await settle();await wait_seconds(.3)
	host.call("_query_economic_details",str(trade.firm),0);await wait_seconds(.4);view.call("select_place",str(trade.offer.to_place_id))
	await economic_action_profile("full_economic_map")
	view.call("select_place",str(trade.offer.from_place_id));await wait_seconds(.2)
	result["external_place_read_only"]=bool(view.get("_business").disabled)
	view.call("select_place",str(trade.offer.to_place_id));await wait_seconds(.2)
	var navigated:=await economic_button(view,"经营所选站点")
	if not navigated:navigated=await economic_button(view,"经营详情")
	await wait_seconds(.4)
	var page:Object=shell.get("person_page")
	result["business_navigation"]={"clicked":navigated,"page":shell.get("current_page"),"native_scope_expanded":page.get("native_scope_expanded"),"firm":page.get("_business").get("firm_id"),"site":page.get("_business").get("site_id"),"target_site":trade.site,"purchase_hits":[]}
	for hit:Dictionary in shell.get("_hits"):
		if str(hit.action).begins_with("native:business_buy:"):result.business_navigation.purchase_hits.append({"action":hit.action,"enabled":hit.enabled})
	if not navigated or not bool(page.get("native_scope_expanded")) or page.get("_business").get("site_id")!=trade.site or result.business_navigation.purchase_hits.is_empty():
		acceptance_image("business_navigation_failure");await economic_action_finish(host,result,"BUSINESS_NAVIGATION_INCOMPLETE",5);return
	if page.get_property_list().any(func(row:Dictionary)->bool:return row.name=="business_firm_id"):
		# UI cursor drift must not select another enterprise or operating site.
		page.set("business_firm_index",999);page.set("business_site_index",999)
		host.call("_refresh_ui");await wait_seconds(.2)
		result["business_identity_pinned"]=page.get("business_firm_id")==trade.firm and page.get("business_site_id")==trade.site and page.get("_business").get("firm_id")==trade.firm and page.get("_business").get("site_id")==trade.site
	page.set("business_offer_page",int(trade.offset));shell.call("refresh");await wait_seconds(.4)
	result["before"]=economic_action_state(host,trade,"")
	var before:=economic_action_core(host)
	result["quantity_input_visible"]=bool(shell.get("_quantity_input").visible)
	shell.get("_quantity_input").get_line_edit().text="1.5"
	shell.call("_activate","native:business_buy:0");await wait_seconds(.2)
	result["fractional_unit_input_rejected"]=before==economic_action_core(host)
	shell.get("_quantity_input").get_line_edit().text=str(page.get("quantity_milli"))
	var invalid:Dictionary=trade.offer.request.duplicate(true);invalid["firm"]=str(trade.offer.seller)
	var seller_managed:bool=model.economy_r1.map_subjects(model.player_state.player_id()).any(func(row:Dictionary)->bool:return row.id==trade.offer.seller)
	result["unauthorized"]=LivelihoodAction.execute(model,"",{"action_id":"invalid_observer_probe","minute":model.game_clock.total_minutes(),"kind":"buy","payload":invalid}) if seller_managed else LivelihoodAction.execute_current(model,"buy",invalid)
	var rejected:=economic_action_core(host);rejected.erase("commands");before.erase("commands")
	result["unauthorized_no_ledger_stock_order_change"]=rejected==before
	var existing:Array=model.economy_r1._orders.keys()
	result["purchase_clicked"]=await economic_click(shell,"native:business_buy:0")
	var added:Array=model.economy_r1._orders.keys().filter(func(id:Variant)->bool:return id not in existing)
	result["new_order_ids"]=added
	if added.size()!=1:await economic_action_finish(host,result,"PURCHASE_NOT_ACCEPTED_EXACTLY_ONCE",5);return
	var order_id:=str(added[0]);result["order_id"]=order_id
	result.timeline.append(economic_action_state(host,trade,order_id))
	var pending:Dictionary=result.timeline.back();var reserved_quantity:=0
	for portion:Dictionary in pending.reserved_portions:reserved_quantity+=int(portion.remaining)
	result["reserved_real_stock"]=pending.seller_stock==result.before.seller_stock and int(pending.seller_committed)-int(result.before.seller_committed)==int(pending.world_order.quantity) and reserved_quantity==int(pending.world_order.quantity)
	result["no_premature_buyer_stock"]=pending.buyer_stock==result.before.buyer_stock and int(pending.world_order.delivered)==0
	result["original_cash_reserved"]=int(pending.reservation.get("amount",0))==int(pending.world_order.quantity)*(int(pending.world_order.price)+int(trade.offer.freight_per_unit))
	acceptance_image("purchase_accepted")
	await economic_action_profile("business_action_result")
	result["business_back"]=await economic_click(shell,"back");await settle();await wait_seconds(.4)
	result["map_follows_order"]=view.get("snapshot").get("market_network",{}).get("edges",{}).has(order_id) and view.get("selected_order")==order_id
	await economic_action_profile("after_action_map_refresh")
	before=economic_action_core(host)
	for repeat:int in range(3):host.call("_request_economic_topic_refresh");await wait_seconds(.2)
	result["repeat_observation_unchanged"]=before==economic_action_core(host)
	var deadline:=Time.get_ticks_msec()+180000;var transit_seen:=false
	host.get("time_control").call("set_speed",4)
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		var order:Dictionary=model.economy_r1._orders[order_id]
		if int(order.transit)>0:transit_seen=true;break
		if int(order.delivered)>0:break
	if not host.get("time_control").paused:host.get("time_control").call("toggle_pause")
	result["transit_seen"]=transit_seen;result.timeline.append(economic_action_state(host,trade,order_id))
	if not transit_seen:await economic_action_finish(host,result,"NO_OBSERVED_TRANSPORT_STAGE",5);return
	var transit_state:Dictionary=result.timeline.back();var actual_cargo:=0
	for shipment:Dictionary in transit_state.shipments.values():actual_cargo+=int(shipment.physical_quantity)
	result["transit_ownership_correct"]=transit_state.buyer_stock==result.before.buyer_stock and actual_cargo==int(transit_state.world_order.transit)
	await wait_seconds(.4);acceptance_image("order_in_transit")
	result["transit_restore"]=await economic_action_restore(host,trade,order_id)
	if not result.transit_restore.same_authority or not result.transit_restore.same_cargo_and_reservation:await economic_action_finish(host,result,"TRANSIT_SAVE_RESTORE_FAILED",5);return
	model=host.get("_world")
	host.call("_query_economic_details",str(trade.firm),0);await wait_seconds(.4)
	# Loading legitimately restores the ordinary political view. Re-enter via
	# its existing button before checking the economic map return operation.
	if controller.map_mode!="economic":await economic_button(view,"完整经济地图");await settle()
	deadline=Time.get_ticks_msec()+180000;host.get("time_control").call("set_speed",4)
	while int(model.economy_r1._orders[order_id].delivered)<int(model.economy_r1._orders[order_id].quantity) and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not host.get("time_control").paused:host.get("time_control").call("toggle_pause")
	result.timeline.append(economic_action_state(host,trade,order_id))
	var delivered:Dictionary=result.timeline.back()
	if int(delivered.world_order.delivered)!=int(delivered.world_order.quantity):await economic_action_finish(host,result,"ORDER_NOT_DELIVERED",5);return
	var paid:=0
	for payment:Dictionary in delivered.payments:paid+=int(payment.amount)
	result["paid_once"]=paid==int(delivered.world_order.quantity)*(int(delivered.world_order.price)+int(trade.offer.freight_per_unit))
	result["reservation_released"]=delivered.reservation.is_empty()
	view.call("follow_order",order_id,str(trade.offer.to_place_id),str(trade.site));host.set("_economic_follow_order",order_id);host.get("_economic_detail_key").clear();host.call("_request_economic_topic_refresh");await wait_seconds(.5)
	result["map_delivered_order"]=view.get("snapshot").get("market_network",{}).get("edges",{}).get(order_id,{})
	acceptance_image("order_delivered")
	result["delivered_restore"]=await economic_action_restore(host,trade,order_id)
	model=host.get("_world");var payments_before:Dictionary=economic_action_state(host,trade,order_id)
	await economic_action_clock(host,model.game_clock.total_minutes()+60)
	var repeated:=economic_action_state(host,trade,order_id)
	result["no_duplicate_delivery_or_payment"]=payments_before.delivery_receipts==repeated.delivery_receipts and payments_before.payments==repeated.payments
	host.call("_query_economic_details",str(trade.firm),0);await wait_seconds(.4)
	if controller.map_mode!="economic":await economic_button(view,"完整经济地图");await settle()
	var return_core:=economic_action_core(host);var return_camera:=economic_camera_state()
	result["returned_political"]=await economic_button(view,"返回政治地图");await settle();await economic_action_profile("return_political",true)
	result["return_same_authority_and_time"]=return_core==economic_action_core(host)
	result["return_camera"]={"before":return_camera,"after":economic_camera_state(),"mode":controller.map_mode}
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(coordinates[0],coordinates[1])));controller.call("set_world_zoom",.86);await settle();await economic_action_profile("return_world")
	result["world_exit"]={"textures":perf_relief.textures.keys(),"regional_batches":perf_region._batches.size(),"detail_released":view.get("snapshot").is_empty(),"links":(renderer.get("_topic_links") as Array).size()}
	var passed:bool=result.quantity_input_visible and result.fractional_unit_input_rejected and result.reserved_real_stock and result.no_premature_buyer_stock and result.transit_ownership_correct and result.original_cash_reserved and result.paid_once and result.reservation_released and result.repeat_observation_unchanged and result.map_follows_order and result.no_duplicate_delivery_or_payment and result.delivered_restore.same_authority and not result.unauthorized.accepted and result.unauthorized_no_ledger_stock_order_change and int(result.map_delivered_order.get("delivered",0))==int(delivered.world_order.quantity) and result.returned_political and controller.map_mode=="political" and result.return_same_authority_and_time and result.world_exit.detail_released and result.world_exit.regional_batches==0 and result.world_exit.links==0
	if model.economy_r1.has_method("opening_participation"):
		# Revoke through the existing organization owner, after the cargo tests.
		# The cached page payload is deliberately left open across revocation.
		var observer:=model.player_state.player_id()
		var cached:=LivelihoodAction.query_business(model,observer,str(trade.firm),str(trade.site),1,int(trade.offset))
		var organization:=str(model.economy_r1._spec.firms[trade.firm].get("host_organization_id",""))
		var removed:=false
		for appointment:Dictionary in model.organization_state.appointments_for_person(observer):
			if appointment.organization_id==organization:
				removed=model.organization_state.remove_appointment(organization,str(appointment.appointment_id)) or removed
		var before_revoke:=economic_action_core(host);before_revoke.erase("commands")
		shell.person_page.refresh_business(cached)
		host.call("_on_action_requested","native:business_buy:0")
		var after_revoke:=economic_action_core(host);after_revoke.erase("commands")
		var denied:Dictionary=model.economy_r1._commands.values().back().result if not model.economy_r1._commands.is_empty() else {}
		host.call("_request_economic_topic_refresh");host.call("_refresh_ui");await wait_seconds(.4)
		result["revoked_open_page"]={"appointment_removed":removed,"cached_payload_present":not cached.get("offers",[]).is_empty(),"result":denied,"no_cash_stock_order_change":before_revoke==after_revoke,"business_query_empty":LivelihoodAction.query_business(model,observer,str(trade.firm),str(trade.site)).is_empty(),"map_firm_removed":not model.economy_r1.map_subjects(observer).any(func(row:Dictionary)->bool:return row.id==trade.firm),"person_firm_removed":not LivelihoodAction.query(model,observer).managed_firms.any(func(row:Dictionary)->bool:return row.firm_id==trade.firm)}
		if page.get_property_list().any(func(row:Dictionary)->bool:return row.name=="business_firm_id"):
			page.set("section","native");page.set("business_mode",true);page.set("native_scope_expanded",true)
			shell.call("set_page","person");host.call("_refresh_ui");await wait_seconds(.2)
			result.revoked_open_page["selection_retained_no_business"]=page.get("business_firm_id")==trade.firm and page.get("business_site_id")==trade.site and page.get("_business").is_empty()
			passed=passed and result.get("business_identity_pinned",false) and result.revoked_open_page.selection_retained_no_business
		passed=passed and removed and not denied.get("accepted",true) and result.revoked_open_page.no_cash_stock_order_change and result.revoked_open_page.business_query_empty and result.revoked_open_page.map_firm_removed and result.revoked_open_page.person_firm_removed
	await economic_action_finish(host,result,"ACTION_LOOP_COMPLETE" if passed else "ACTION_LOOP_CHECK_FAILED",0 if passed else 5)

func economic_authority_state(host: Object) -> Dictionary:
	var model:Object=host.get("_world")
	var native:Object=model.get("economy_r1")
	return {"world":model.get_instance_id(),"renderer":renderer.get_instance_id(),"controller":controller.get_instance_id(),"camera":controller.get("region_camera").get_instance_id(),"clock":model.get("game_clock").total_minutes(),"clock_owner":model.get("game_clock").get_instance_id(),"step":host.get("_simulation_step").get_instance_id(),"native":native.get_instance_id() if native!=null else 0,"ledger":model.get("ledger_state").snapshot(),"market_states":model.get("economy_state").get("market_states").duplicate(true),"macro_shipments":model.get("economy_state").get("shipments").duplicate(true),"native_stocks":native.get("_stocks").duplicate(true) if native!=null else {},"native_orders":native.get("_orders").duplicate(true) if native!=null else {},"native_shipments":native.get("_shipments").duplicate(true) if native!=null else {}}

func economic_camera_state() -> Dictionary:
	var camera:Object=controller.get("region_camera")
	return {"mpp":camera.get("km_per_pixel")*1000.0,"bearing":camera.get("bearing"),"center_unit":TerrainPixelSource.serial(camera.call("unit_at",renderer.get("size")*.5)),"world_zoom":controller.get("zoom"),"active":camera.get("active"),"local":camera.get("local_active")}

func economic_click(shell: Object, action: String) -> bool:
	await get_tree().process_frame
	for hit:Dictionary in shell.get("_hits"):
		if str(hit.get("action",""))==action and bool(hit.get("enabled",false)):
			var point:Vector2=(hit.rect as Rect2).get_center()
			await mouse_button(point,MOUSE_BUTTON_LEFT,true);await mouse_button(point,MOUSE_BUTTON_LEFT,false)
			await wait_seconds(.3);return true
	if not OS.get_environment("WWO_LIVING_UI").is_empty(): print("LIVING_MISSING_CONTROL ",action)
	return false

func economic_button(view: Object, text: String) -> bool:
	for button:Node in view.find_children("*","Button",true,false):
		if (button as Button).text==text and (button as Button).is_visible_in_tree() and not (button as Button).disabled:
			var point:Vector2=(button as Button).get_global_rect().get_center()
			await mouse_button(point,MOUSE_BUTTON_LEFT,true);await mouse_button(point,MOUSE_BUTTON_LEFT,false)
			await wait_seconds(.3);return true
	return false

func acceptance_economic_integration(host: Object) -> void:
	if not renderer.has_method("set_topic_facts"):
		acceptance_save("economic",{"status":"UNVERIFIED","reason":"This package does not contain the economic integration"});get_tree().quit(6);return
	get_window().title="WWO 正式经济地图接入 · 隔离自动验证";get_window().grab_focus()
	var model:Object=host.get("_world")
	var shell:Object=host.get("main_shell")
	var view:Object=shell.get("economic_map")
	var clock:Object=model.get("game_clock")
	var control:Object=host.get("time_control")
	controller.call("set_map_mode","political")
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)),renderer.get("size")*.5,.25,0.0,renderer.get("size"));await settle();await wait_seconds(1)
	var result:Dictionary={"world_id":model.get_instance_id(),"native_case":str(model.get("economy_r1").get("config").get("case_id","")) if model.get("economy_r1")!=null else "NONE","user_dir":OS.get_user_data_dir(),"before_stats_available":shell.get("economic_data_available"),"switches":[],"place_identity":[]}
	var before:=economic_authority_state(host)
	var pose:=economic_camera_state()
	for cycle:int in range(3):
		shell.call("_activate","map:mode_menu");await wait_seconds(.2)
		var clicked:=await economic_click(shell,"map:economy_mode")
		await settle();await wait_seconds(.5)
		var entered:bool=controller.map_mode=="economic" and view.visible and view.get("full")
		var returned:=await economic_button(view,"返回政治地图");await settle();await wait_seconds(.3)
		result.switches.append({"cycle":cycle,"menu_click":clicked,"economic_entered":entered,"return_click":returned,"mode_after":controller.map_mode,"same_authority":economic_authority_state(host)==before,"same_camera_pose":economic_camera_state()==pose})
	# The official clock/step produces statistics; viewing never performs a step.
	var target:=1440
	if not OS.get_environment("WWO_ECONOMIC_TEST_DAYS").is_empty():target=maxi(1440,OS.get_environment("WWO_ECONOMIC_TEST_DAYS").to_int()*1440)
	control.call("set_speed",4)
	var deadline:=Time.get_ticks_msec()+180000
	while clock.total_minutes()<target and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not control.paused:control.call("toggle_pause")
	await settle();await wait_seconds(1)
	result["published_minute"]=clock.total_minutes();result["after_stats_available"]=shell.get("economic_data_available")
	result["topic_facts"]=renderer.get("_topic_facts").duplicate(true)
	result["topic_hits"]=renderer.get("_topic_hits").keys()
	acceptance_image("political_economic_markers")
	var found:=false
	for row:Dictionary in renderer.get("_symbol_layout"):
		var id:String=str(row.id)
		if id.begins_with("place:"):pass
		else:id="place:"+id
		if not (renderer.get("_topic_hits") as Dictionary).has(id):continue
		var point:Vector2=(row.rect as Rect2).get_center()
		await mouse_button(point,MOUSE_BUTTON_LEFT,true);await mouse_button(point,MOUSE_BUTTON_LEFT,false)
		await wait_seconds(.5);found=view.visible and not bool(view.get("full"));break
	result["political_detail_opened"]=found
	result["detail_subject"]=view.get("snapshot").get("subject","")
	result["expanded_from_detail"]=await economic_button(view,"完整经济地图")
	await settle();await wait_seconds(.5)
	var choices:Array=view.get("snapshot").get("subjects",[])
	for choice:Dictionary in choices:
		if choice.kind=="firm":host.call("_query_economic_details",str(choice.id),0);await wait_seconds(.5);break
	result["full_snapshot"]=view.get("snapshot").duplicate(true)
	result["full_mode"]=controller.map_mode;result["view_visible"]=view.visible
	result["business_button_disabled"]=bool(view.get("_business").disabled)
	result["source_order_matches"]=[]
	if model.get("economy_r1")!=null:
		var source_orders:Dictionary=model.get("economy_r1").get("_orders")
		for order:Dictionary in view.get("snapshot").get("firm",{}).get("orders",[]):
			var original:Dictionary=source_orders.get(str(order.id),{})
			result.source_order_matches.append({"id":str(order.id),"present":not original.is_empty(),"pending_equal":original.get("pending")==order.get("pending"),"transit_equal":original.get("transit")==order.get("transit"),"delivered_equal":original.get("delivered")==order.get("delivered")})
	acceptance_image("full_economic_map")
	before=economic_authority_state(host)
	if model.get("economy_r1")!=null and str(view.get("snapshot").get("subject","")).begins_with("firm:"):
		result["business_detail_clicked"]=await economic_button(view,"经营详情")
		await wait_seconds(.5)
		result["business_page_reused"]=shell.get("current_page")=="person" and bool(shell.get("person_page").get("business_mode"))
		result["business_back_clicked"]=await economic_click(shell,"back")
		await wait_seconds(.5)
		result["business_returned_same_world"]=model==host.get("_world") and controller.map_mode=="economic" and view.visible
	for place:String in ["place:paris","place:lyon","place:marseille"]:
		var record:Dictionary=model.get("spatial_catalog").get_place(place)
		view.call("select_place",place)
		result.place_identity.append({"id":place,"catalog_place_id":record.get("place_id",record.get("id","")),"lon_lat":record.get("lon_lat"),"economic_node":view.get("network").get("nodes",{}).get(place,{}),"known_contact_node":view.get("contacts").get("nodes",{}).get(place,{})})
	var bindings_before:=dynamic_snapshot()
	var counters_before:Dictionary=renderer.call("current_view_map_status").get("diagnostic_counters",{}).duplicate()
	for cycle:int in range(3):host.call("_request_economic_topic_refresh");await wait_seconds(.2)
	result["refresh_bindings_before"]=bindings_before
	result["refresh_bindings_after"]=dynamic_snapshot()
	result["refresh_counters_before"]=counters_before
	result["refresh_counters_after"]=renderer.call("current_view_map_status").get("diagnostic_counters",{}).duplicate()
	result["readonly_detail_and_refresh"]=economic_authority_state(host)==before
	result["returned_from_details"]=await economic_button(view,"返回政治地图")
	await settle();await wait_seconds(.5)
	result["same_world_after_return"]=economic_authority_state(host)==before
	result["returned_mode"]=controller.map_mode
	result["detail_references_released"]=view.get("snapshot").is_empty() and view.get("network").is_empty() and (renderer.get("_topic_links") as Array).is_empty()
	acceptance_image("return_political_map")
	# Update the existing official clock with the full economic view open.
	# This is a separate step after the three same-time comparison pictures.
	shell.call("_activate","map_mode:economic");await settle();await wait_seconds(.3)
	var update_from:int=clock.total_minutes()
	control.call("set_speed",1)
	deadline=Time.get_ticks_msec()+30000
	while clock.total_minutes()<update_from+60 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not control.paused:control.call("toggle_pause")
	await wait_seconds(.5)
	result["full_clock_update"]={"from":update_from,"to":clock.total_minutes(),"observed":view.get("snapshot").get("minute",-1),"same_world":model==host.get("_world")}
	result["returned_after_clock_update"]=await economic_button(view,"返回政治地图")
	await wait_seconds(.4)
	result["political_clock_update"]=(renderer.get("_topic_facts") as Array).all(func(row:Dictionary)->bool:return int(row.world_minute)==clock.total_minutes())
	shell.call("_activate","map_mode:fulfillment");await settle();await wait_seconds(.3)
	result["footer_page"]=shell.get("current_page")
	result["settled_footer_available"]=shell.get("economic_data_available")
	result["settled_footer_drawn"]=shell.get("_text_fonts").has("国家商品统计 · 已结算资料；无资料地区保留地理底图")
	controller.call("set_map_mode","political")
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)));controller.call("set_world_zoom",.86);await settle();await wait_seconds(.5)
	result["world_remaining"]=(renderer.get("relief") as MapRelief).textures.keys()
	result["region_batches"]=(renderer.get("_region_layer").get("_batches") as Array).size()
	acceptance_save("economic",result)
	print("R57_ECONOMIC completed ",JSON.stringify({"switches":result.switches,"facts":result.topic_facts.size(),"detail":found,"minute":result.published_minute,"same_authority":result.readonly_detail_and_refresh}))
	host.set("_departure_target","menu");host.call("_leave_world");await wait_seconds(.5);get_tree().quit(0)

func mouse_button(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func check_ui(shell: MainShell) -> void:
	for i: int in range(15): shell.show_feedback("隔离输入检查 "+str(i),"","system")
	shell.call("_set_messages_open",true)
	await wait_seconds(.4)
	var scroll := shell._message_scroll
	var rect := scroll.get_global_rect()
	var mpp: float = controller.region_camera.km_per_pixel
	await mouse_button(rect.get_center(),MOUSE_BUTTON_WHEEL_DOWN,true)
	await mouse_button(rect.get_center(),MOUSE_BUTTON_WHEEL_DOWN,false)
	print("R57_UI wheel=",scroll.scroll_vertical," map_unchanged=",mpp==controller.region_camera.km_per_pixel)
	var bar := scroll.get_v_scroll_bar()
	var start := bar.get_global_rect().position+Vector2(bar.size.x*.5,25)
	await mouse_button(start,MOUSE_BUTTON_LEFT,true)
	var motion := InputEventMouseMotion.new()
	motion.position = start+Vector2(0,80)
	motion.relative = Vector2(0,80)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	await mouse_button(motion.position,MOUSE_BUTTON_LEFT,false)
	print("R57_UI drag=",scroll.scroll_vertical," focus=",get_viewport().gui_get_hovered_control())
	var buttons := shell._message_drawer.find_children("*","Button",true,false)
	var link := buttons.back() as Button
	await mouse_button(link.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
	await mouse_button(link.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,false)
	print("R57_UI encyclopedia page=",shell.current_page," open=",shell.world_page.index_open)
	await get_tree().process_frame
	await get_tree().process_frame
	for hit: Dictionary in shell._hits:
		if str(hit.action)=="encyclopedia:category:help":
			var point := (hit.rect as Rect2).get_center()
			await mouse_button(point,MOUSE_BUTTON_LEFT,true)
			await mouse_button(point,MOUSE_BUTTON_LEFT,false)
			break
	print("R57_UI help=",shell.world_page.index_category)
	var count := shell._messages.size()
	shell.show_map_feedback("正在准备区域细节；全球基础继续跟随相机。")
	shell.show_map_feedback("当前区域细节已安装。")
	shell.show_map_feedback("当前区域细节已安装。")
	print("R57_UI map_status_added=",shell._messages.size()-count)



func multi_frame(host: Object) -> Dictionary:
	var r := resident_frame(host)
	var model: WorldState = host.get("_world")
	var e := model.economy_r1
	r["firm_accounts"] = {}
	for firm: String in e._spec.firms:
		r.firm_accounts[firm] = {"account":e._account(firm),"cash":model.ledger_state.balance(e._account(firm))}
	r["stocks"] = e._stocks.duplicate(true)
	r["jobs"] = {}
	for actor: String in e._actors:
		r.jobs[actor] = []
		for id: String in e._actors[actor].known_jobs: r.jobs[actor].append(e._known_job(actor,id))
	return r

func multi_apply(shell: MainShell, job: String) -> bool:
	if await economic_click(shell,"native:apply:"+job+"|"): return true
	if await economic_click(shell,"person:native_jobs_next"):
		if await economic_click(shell,"native:apply:"+job+"|"): return true
	if await economic_click(shell,"person:native_jobs_previous"): return await economic_click(shell,"native:apply:"+job+"|")
	return false

func acceptance_multi_employer(host: Object) -> void:
	if OS.get_environment("WWO_CONTINUOUS_DAYS")=="30":
		await acceptance_continuous_economy(host)
		return
	get_window().title = "WWO 巴黎两雇主 · 隔离验证"; get_window().grab_focus()
	var model: WorldState = host.get("_world")
	var shell: MainShell = host.get("main_shell")
	var person := model.player_state.player_id()
	var npc := "person:formal_generated_country_fra_0002"
	var low := "job:opening_paris_workshop"
	var high := "job:opening_paris_bakery"
	var mode := OS.get_environment("WWO_EMPLOYMENT_CASE")
	var r: Dictionary = {"variant":mode,"user_dir":OS.get_user_data_dir(),"opening":model.economy_r1.config.duplicate(true),"initial":multi_frame(host),"days":[],"restores":[],"policy":"Oil menu New World; original GameClock and real player UI only. Opportunity/arrears are explicit initial notice/cash variants. No NPC actions submitted by driver."}
	var ok: bool = r.initial.persons==[person,npc] and r.initial.actors[person].cash==2500 and r.initial.actors[npc].cash==0 and model.economy_r1._spec.firms.size()==2 and r.initial.stocks["site:opening_paris_bakery:paris"].bread==0
	if not ok: await economic_action_finish(host,r,"TWO_EMPLOYERS_OPENING_INVALID",5); return
	host.set_meta("participation_initial_world",model.get_instance_id())
	r.restores.append(await participation_restore(host))
	host.call("_open_economic_business",person,""); await wait_seconds(.2)
	r["initial_person_view"] = shell.person_page.get("_personal").duplicate(true)
	acceptance_image("two_employer_jobs")
	if mode in ["occupied","opportunity"]:
		ok = await multi_apply(shell,low if mode=="opportunity" else high) and ok
		ok = await economic_click(shell,"native:work") and ok
		r["after_player_choice"] = multi_frame(host)
		r.restores.append(await participation_restore(host))
	if mode=="opportunity":
		await economic_action_clock(host,60)
		host.call("_open_economic_business",person,""); await wait_seconds(.2)
		ok = await economic_click(shell,"native:leave_job") and ok
		r["pending_exit"] = multi_frame(host)
		r["pending_exit_person_view"] = shell.person_page.get("_personal").duplicate(true)
		r.restores.append(await participation_restore(host))
	var days: int = 14 if mode=="arrears" else 7
	for date: int in range(1,days+1):
		await economic_action_clock(host,date*1440)
		model=host.get("_world")
		if mode=="opportunity" and date==1:
			r["after_exit"] = multi_frame(host)
			r["old_wages_at_exit"] = model.economy_r1._wages.duplicate(true)
			host.call("_open_economic_business",person,""); await wait_seconds(.2)
			ok = await multi_apply(shell,high) and ok
			ok = await economic_click(shell,"native:work") and ok
			r["new_contract"] = multi_frame(host)
			r.restores.append(await participation_restore(host))
		if date==2 and mode in ["occupied","opportunity"]:
			host.call("_open_economic_business",person,""); await wait_seconds(.2)
			ok = await economic_click(shell,"native:work") and ok
		if date==4 and mode in ["occupied","opportunity"]:
			host.call("_open_economic_business",person,""); await wait_seconds(.2)
			ok = await economic_click(shell,"person:market") and ok
			ok = await economic_click(shell,"commodity:select:native:bread|site:opening_paris_workshop:paris") and ok
			ok = await economic_click(shell,"purchase") and ok
			ok = await economic_button(shell,"查看") and ok
			ok = await economic_click(shell,"consume") and ok
			r["player_consumption"] = multi_frame(host)
		if date==4 and mode=="opportunity":
			r["new_notice"] = multi_frame(host)
			await economic_action_clock(host,5820)
			host.call("_open_economic_business",person,""); await wait_seconds(.2)
			ok = await economic_click(shell,"native:leave_job") and ok
			r.restores.append(await participation_restore(host))
		r.days.append(multi_frame(host))
		if date in [1,2,4,7] or (mode=="arrears" and date in [9,11,14]): r.restores.append(await participation_restore(host))
		if date==3:
			# Camera browsing changes no person's real location or existing responsibilities.
			shell.call("set_page","map")
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(4.8357,45.7640)),renderer.get("size")*.5,.5,0.0,renderer.get("size")); await settle()
	model=host.get("_world")
	var e := model.economy_r1
	r["final"] = multi_frame(host)
	r["commands"] = e._commands.duplicate(true)
	r["messages"] = e._receipts.duplicate(true)
	r["work"] = e._work_records.duplicate(true)
	r["wages"] = e._wages.duplicate(true)
	r["orders"] = e._orders.duplicate(true)
	r["receipts"] = e._delivery_receipts.duplicate(true)
	r["ledger"] = model.ledger_state._transactions.duplicate(true)
	r["physical_totals"] = e._physical_totals.duplicate(true)
	r["employment_ends"] = e._employment_ends.duplicate(true)
	r["decision_counts"] = e._decision_counts.duplicate(true)
	var n := r.final.actors[npc] as Dictionary
	var applications: Array = e._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply")
	r["applications"] = applications
	ok = ok and applications.size()<=4 and n.totals.work_hours>0 and n.totals.income>0 and n.totals.categories.food.satisfied>0
	ok = ok and n.contract.get("job")== (high if mode=="idle" else low)
	if mode=="arrears": ok = ok and e._wages.values().any(func(w:Dictionary)->bool:return w.employer=="firm:opening_paris_bakery" and w.remaining>0)
	var before := multi_frame(host)
	var owners := [model.get_instance_id(),e.get_instance_id(),model.game_clock.get_instance_id(),model.ledger_state.get_instance_id()]
	shell.call("set_page","map"); controller.call("set_map_mode","political"); await settle()
	controller.call("set_map_mode","economic"); await settle()
	host.call("_query_economic_details",person,0); await wait_seconds(.2)
	r["map_person"] = shell.economic_map.snapshot.get("firm",{}).duplicate(true)
	r["same_person_map"] = r.map_person.get("cash")==r.final.actors[person].cash and r.map_person.get("known_jobs",[]).size()==2
	r["npc_private_denied"] = LivelihoodAction.query(model,npc).is_empty()
	r["return_political"] = await economic_button(shell.economic_map,"返回政治地图")
	await settle()
	r["read_only_same_authority"] = before==multi_frame(host) and owners==[model.get_instance_id(),e.get_instance_id(),model.game_clock.get_instance_id(),model.ledger_state.get_instance_id()]
	r["npc_stayed_paris"] = r.days.all(func(f:Dictionary)->bool:return f.actors[npc].place=="place:paris")
	acceptance_image("two_employer_result")
	ok = ok and r.same_person_map and r.npc_private_denied and r.return_political and r.read_only_same_authority and r.npc_stayed_paris and r.restores.all(func(x:Dictionary)->bool:return x.saved and x.same_state)
	await economic_action_finish(host,r,"ORDINARY_TWO_EMPLOYERS_COMPLETE" if ok else "ORDINARY_TWO_EMPLOYERS_FAILED",0 if ok else 5)

func continuous_economy_frame(host: Object) -> Dictionary:
	var r := multi_frame(host)
	var model: WorldState = host.get("_world")
	var e := model.economy_r1
	r["day"]=e.day
	r["physical_totals"]=e._physical_totals.duplicate(true)
	r["plans"]=e._plans.duplicate(true)
	r["retail_hours_today"]={}
	r["firm_flows"]={}
	r["total_cash"]=0
	for actor: Dictionary in r.actors.values(): r.total_cash+=int(actor.cash)
	for firm: String in r.firm_accounts:
		r.total_cash+=int(r.firm_accounts[firm].cash)
		var flows: Dictionary={"wages_accrued":0,"wages_paid":0,"not_due":0,"overdue":0,"sales_delivered":0,"sales_value":0}
		for wage: Dictionary in e._wages.values():
			if wage.employer!=firm: continue
			flows.wages_accrued+=int(wage.amount)
			flows.wages_paid+=int(wage.paid)
			if int(wage.due_day)>e.day: flows.not_due+=int(wage.remaining)
			else: flows.overdue+=int(wage.remaining)
		for order: Dictionary in e._orders.values():
			if order.seller==firm:
				flows.sales_delivered+=int(order.delivered)
				flows.sales_value+=int(order.delivered)*int(order.price)
		r.firm_flows[firm]=flows
	for site: String in e._stocks: r.retail_hours_today[site]=e._retail.allocated_hours(site,e.day)
	r["decision_counts"]=e._decision_counts.duplicate(true)
	return r

func acceptance_continuous_economy(host: Object) -> void:
	get_window().title="WWO 普通巴黎30日 · 玩家不参与";get_window().grab_focus()
	var model: WorldState=host.get("_world")
	var person:=model.player_state.player_id()
	var r: Dictionary={"user_dir":OS.get_user_data_dir(),"opening":model.economy_r1.config.duplicate(true),"initial":continuous_economy_frame(host),"days":[],"restores":[],"continuations":[],"policy":"One ordinary 30-day line. Player submits no economic actions. Original GameClock and NPC rules only. Slot3 is isolated; three one-day restore comparisons, no second 30-day control."}
	var start_day: int=1
	var checkpoint: Dictionary={}
	if OS.get_environment("WWO_CONTINUOUS_RESUME")=="1":
		var archive:=OS.get_environment("WWO_VISUAL_RECORD_ARCHIVE")
		var records: Variant=JSON.parse_string(FileAccess.get_file_as_bytes(archive).decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8()) if FileAccess.file_exists(archive) else null
		var key:=output.get_file()+"/economic-action"
		if not records is Dictionary or not records.has(key) or records[key].get("days",[]).is_empty():
			await economic_action_finish(host,r,"CONTINUOUS_RESUME_RECORD_MISSING",5);return
		r=records[key]
		var last: Dictionary=r.days.back()
		var observed:=continuous_economy_frame(host)
		# Archive JSON reads numbers as floats. Compare like serializations.
		# _decision_counts is a transient observer counter, explicitly cleared
		# by EconomyR1Slice.restore; it is absent from the formal snapshot.
		var expected_persisted: Dictionary=last.duplicate(true)
		var observed_persisted: Dictionary=JSON.parse_string(JSON.stringify(observed))
		expected_persisted.erase("decision_counts");observed_persisted.erase("decision_counts")
		var opening_same: bool=JSON.parse_string(JSON.stringify(model.economy_r1.config))==r.opening
		var same: bool=observed_persisted==expected_persisted and opening_same
		r["cold_resume"]={"day":int(last.day),"minute":model.game_clock.total_minutes(),"same_persisted_daily_state":same,"same_opening":opening_same,"observed_daily_state":observed,"excluded_transient_counter":"decision_counts: restore explicitly clears it; not in snapshot","comparison":"JSON number representations normalized; all persisted daily fields retained","source":"Real slot3 loaded by formal menu in a new EXE process"}
		if not same: await economic_action_finish(host,r,"CONTINUOUS_RESUME_STATE_MISMATCH",5);return
		start_day=int(last.day)+1
		checkpoint=host.get("_persistence").snapshot()
	var ok: bool=r.opening.case_id=="FORMAL_PARIS_TWO_EMPLOYERS_OPENING_R1" and r.initial.minute==0 and r.initial.persons.size()==2 and r.initial.firm_accounts.size()==2 and r.initial.total_cash==4300
	if not ok: await economic_action_finish(host,r,"CONTINUOUS_OPENING_INVALID",5);return
	host.set_meta("participation_initial_world",model.get_instance_id())
	for date: int in range(start_day,31):
		await economic_action_clock(host,date*1440)
		if not checkpoint.is_empty():
			var expected: Dictionary=host.get("_persistence").snapshot()
			host.call("_on_action_requested","slot:load:3");await wait_seconds(.5)
			var restored_same: bool=checkpoint==host.get("_persistence").snapshot()
			await economic_action_clock(host,date*1440)
			var continued_same: bool=expected==host.get("_persistence").snapshot()
			r.continuations.append({"from_day":date-1,"to_day":date,"restored_same":restored_same,"full_state_same_after_one_day":continued_same})
			ok=ok and restored_same and continued_same
			checkpoint={}
		var frame:=continuous_economy_frame(host)
		r.days.append(frame)
		ok=ok and frame.minute==date*1440 and frame.total_cash==r.initial.total_cash and frame.persons==r.initial.persons and frame.firm_accounts.keys()==r.initial.firm_accounts.keys()
		ok=ok and frame.actors[person].cash==2500 and frame.actors[person].contract.is_empty() and frame.actors[person].totals.work_hours==0
		if date in [7,15,24,30]:
			var before: Dictionary=host.get("_persistence").snapshot()
			var restored:=await participation_restore(host,3)
			restored["day"]=date
			restored["full_state_same"]=before==host.get("_persistence").snapshot()
			r.restores.append(restored)
			ok=ok and restored.saved and restored.same_state and restored.full_state_same
			if date<30: checkpoint=host.get("_persistence").snapshot()
		print("R57_CONTINUOUS_DAY ",date," minute=",frame.minute," cash=",frame.total_cash)
		# Replace the same compact record. Never save a full world per day.
		r["status"]="RUNNING";acceptance_save("economic-action",r)
		if not ok: await economic_action_finish(host,r,"CONTINUOUS_STATE_MISMATCH",5);return
	model=host.get("_world")
	r["final"]=continuous_economy_frame(host)
	r["commands"]=model.economy_r1._commands.duplicate(true)
	r["wages"]=model.economy_r1._wages.duplicate(true)
	r["ledger"]=model.ledger_state._transactions.duplicate(true)
	r["player_economic_commands"]=model.economy_r1._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==person).size()
	ok=ok and r.player_economic_commands==0
	await economic_action_finish(host,r,"ORDINARY_30_DAYS_COMPLETE" if ok else "ORDINARY_30_DAYS_FAILED",0 if ok else 5)


func material_trace(host: Object, order_id: String) -> Dictionary:
	var e: EconomyR1Slice=host.get("_world").economy_r1
	var r: Dictionary={"order":e._orders.get(order_id,{}).duplicate(true),"receipts":[],"portions":[],"sources":{},"products":[],"payments":[]}
	var receipt_ids: Array=[]
	for receipt: Dictionary in e._delivery_receipts.values():
		if receipt.order_id==order_id:
			r.receipts.append(receipt.duplicate(true));receipt_ids.append(receipt.id)
	var adopted_ids: Array=[]
	for portion: Dictionary in e._lots.portions.values():
		if portion.acquisition_id in receipt_ids and portion.good=="grain":
			r.portions.append(portion.duplicate(true));adopted_ids.append(portion.id)
			r.sources[portion.source_id]=e._lots.sources[portion.source_id].duplicate(true)
			var parent: String=portion.parent_portion_id
			while not parent.is_empty():
				var ancestor: Dictionary=e._lots.portions[parent]
				if not r.portions.any(func(p:Dictionary)->bool:return p.id==parent): r.portions.append(ancestor.duplicate(true))
				parent=ancestor.parent_portion_id
	for source: Dictionary in e._lots.sources.values():
		if source.inputs.any(func(input:Dictionary)->bool:return input.portion_id in adopted_ids): r.products.append(source.duplicate(true))
	for payment: Dictionary in host.get("_world").ledger_state._transactions:
		if payment.get("reference_id")==order_id: r.payments.append(payment.duplicate(true))
	return r

func material_conserved(host: Object) -> bool:
	var e: EconomyR1Slice=host.get("_world").economy_r1
	for good: String in ["grain","bread"]:
		var stock:=0;var used:=0;var made:=0
		for row: Dictionary in e._stocks.values(): stock+=int(row[good])
		for row: Dictionary in e._physical_totals.values(): used+=int(row.used[good]);made+=int(row.produced[good])
		if stock+used-made!=(84 if good=="grain" else 12): return false
	return int(continuous_economy_frame(host).total_cash)==4300

func material_gui_checkpoint(host: Object,r: Dictionary,date: int) -> bool:
	var restored:=await living_ui_restore(host)
	restored["day"]=date
	r.restores.append(restored)
	var ok: bool=restored.visible_controls and restored.same_world_state and restored.selection_same and restored.bytes>0
	if ok: r["checkpoint"]={"day":date,"state":continuous_economy_frame(host)}
	acceptance_save("economic-action",r)
	return ok

func acceptance_material_trade(host: Object) -> void:
	get_window().title="WWO 巴黎企业原料交易 · 玩家劳动分支";get_window().grab_focus()
	var shell: Object=host.get("main_shell")
	if not host.get("time_control").paused: await economic_click(shell,"time:pause")
	var seller:="firm:opening_paris_workshop";var buyer:="firm:opening_paris_bakery"
	var site:="site:opening_paris_workshop:paris";var destination:="site:opening_paris_bakery:paris"
	var r: Dictionary={"user_dir":OS.get_user_data_dir(),"initial":continuous_economy_frame(host),"opening":host.get("_world").economy_r1.config.duplicate(true),"days":[],"restores":[],"policy":"New declared Opening. Real menu and worker UI only. The native firm algorithm chooses procurement. No driver buy, resource injection or day30 baseline write. Private need observations below are test diagnostics, not worker UI permissions."}
	var resuming: bool=OS.get_environment("WWO_MATERIAL_RESUME")=="1"
	var start_day:=1
	if resuming:
		var archive:=OS.get_environment("WWO_VISUAL_RECORD_ARCHIVE")
		var records: Variant=JSON.parse_string(FileAccess.get_file_as_bytes(archive).decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8()) if FileAccess.file_exists(archive) else null
		var key:=output.get_file()+"/economic-action"
		if not records is Dictionary or not records.has(key) or records[key].get("checkpoint",{}).is_empty():
			await economic_action_finish(host,r,"MATERIAL_RESUME_CHECKPOINT_MISSING",5);return
		r=records[key]
		var expected: Dictionary=r.checkpoint.state.duplicate(true)
		var observed: Dictionary=JSON.parse_string(JSON.stringify(continuous_economy_frame(host)))
		expected.erase("decision_counts");observed.erase("decision_counts")
		var same: bool=expected==observed and r.opening==JSON.parse_string(JSON.stringify(host.get("_world").economy_r1.config))
		r["cold_resume"]={"checkpoint_day":r.checkpoint.day,"same_persisted_state":same,"excluded_transient_counter":"decision_counts: restore explicitly clears it; not in snapshot","source":"Formal menu loads real isolated slot4 in a new EXE process"}
		if not same: await economic_action_finish(host,r,"MATERIAL_RESUME_STATE_MISMATCH",5);return
		start_day=int(r.checkpoint.day)+1
		r.days=r.days.filter(func(x:Dictionary)->bool:return int(x.day)<start_day)
	var ok: bool=await economic_click(shell,"page:person")
	ok=await economic_click(shell,"person:native") and ok
	if not resuming:
		ok=await economic_click(shell,"person:job_select:job:opening_paris_workshop") and ok
		ok=await economic_click(shell,"person:job_request:job:opening_paris_workshop") and ok
		ok=await economic_click(shell,"confirm:employment") and ok
	ok=await economic_click(shell,"person:living_tab:wages") and ok
	var original: WorldState=host.get("_world")
	var person:=original.player_state.player_id()
	var booked: bool=original.economy_r1._work_queue.has(person) or original.economy_r1._work_records.values().any(func(w:Dictionary)->bool:return w.actor==person)
	var order_id:="";var delivered_day:=-1;var adopted:=false
	for order: Dictionary in original.economy_r1._orders.values():
		if order.buyer==buyer and order.seller==seller and order.good=="grain": order_id=order.id;break
	if not order_id.is_empty(): delivered_day=int(r.get("delivered_day",original.economy_r1.day))
	else:
		for field: String in ["delivered_day","delivered","trace_delivered","adopted_day","adopted","trace_adopted"]: r.erase(field)
	if resuming and not booked and int(original.economy_r1._input_need(destination,"grain").quantity)>0:
		ok=await economic_click(shell,"native:work") and ok
		booked=true;r["work_booked_minute"]=host.get("_world").game_clock.total_minutes()
	for date: int in range(start_day,46):
		ok=await living_clock(host,date*1440) and ok
		var model: WorldState=host.get("_world");var e:=model.economy_r1
		var need: Dictionary=e._input_need(destination,"grain")
		r.days.append({"day":date,"minute":model.game_clock.total_minutes(),"grain":e._stocks[destination].grain,"need":need.duplicate(true),"bakery_cash":model.ledger_state.balance(e._account(buyer)),"seller_staff_hours":e._retail.allocated_hours(site,date)})
		for order: Dictionary in e._orders.values():
			if order.buyer==buyer and order.seller==seller and order.good=="grain": order_id=order.id;break
		if order_id.is_empty() and int(need.quantity)>0 and not booked:
			r["before_staffing"]={"state":continuous_economy_frame(host),"offers":e._offers(buyer,destination,"grain")}
			ok=await material_gui_checkpoint(host,r,date) and ok
			ok=await economic_click(shell,"person:living_tab:wages") and ok
			ok=await economic_click(shell,"native:work") and ok
			booked=true
			r["work_booked_minute"]=host.get("_world").game_clock.total_minutes()
		if not order_id.is_empty() and delivered_day<0:
			delivered_day=date
			r["delivered_day"]=date;r["delivered"]=continuous_economy_frame(host);r["trace_delivered"]=material_trace(host,order_id)
			ok=await economic_click(shell,"person:living_tab:wages") and ok
			r["worker_view"]=shell.get("person_page").get("_personal").duplicate(true)
			r["worker_handover_visible"]=not r.worker_view.get("workplace_handovers",[]).is_empty()
			acceptance_image("material_delivered")
			ok=await material_gui_checkpoint(host,r,date) and ok
		if not order_id.is_empty() and date>delivered_day:
			var trace:=material_trace(host,order_id)
			adopted=not trace.products.is_empty()
			if adopted:
				r["adopted_day"]=date;r["adopted"]=continuous_economy_frame(host);r["trace_adopted"]=trace
				ok=await material_gui_checkpoint(host,r,date) and ok
				var stable: Dictionary={"ledger":host.get("_world").ledger_state.snapshot(),"stock":host.get("_world").economy_r1._lots.snapshot(),"orders":host.get("_world").economy_r1._orders.duplicate(true)}
				ok=await living_clock(host,date*1440+60) and ok
				r["no_repeat_after_restore"]=stable=={"ledger":host.get("_world").ledger_state.snapshot(),"stock":host.get("_world").economy_r1._lots.snapshot(),"orders":host.get("_world").economy_r1._orders.duplicate(true)}
				break
		print("R57_MATERIAL_DAY ",date," need=",need.quantity," order=",order_id)
		if date in [14,28]: ok=await material_gui_checkpoint(host,r,date) and ok
		r["status"]="RUNNING"
		acceptance_save("economic-action",r)
	var model: WorldState=host.get("_world");var e:=model.economy_r1
	r["final"]=continuous_economy_frame(host)
	r["worker_hours"]=e._work_records.values().filter(func(w:Dictionary)->bool:return w.actor==model.player_state.player_id()).reduce(func(total:int,w:Dictionary)->int:return total+int(w.hours),0)
	r["worker_private_denied"]=LivelihoodAction.query_firm(model,model.player_state.player_id(),buyer).is_empty() and LivelihoodAction.query_business(model,model.player_state.player_id(),seller,site).is_empty()
	r["conserved"]=material_conserved(host)
	r["native_procurement"]=not order_id.is_empty() and e._commands[e._orders[order_id].action_id].source=="firm" and e._commands[e._orders[order_id].action_id].envelope.actor==buyer
	var before: Dictionary=host.get("_persistence").snapshot()
	r["map_roundtrip"]=await living_map_roundtrip(shell)
	r["map_same_authority"]=before==host.get("_persistence").snapshot()
	ok=ok and booked and adopted and r.native_procurement and r.conserved and r.worker_hours==2 and r.worker_private_denied and r.get("worker_handover_visible",false) and r.get("no_repeat_after_restore",false) and r.map_roundtrip and r.map_same_authority
	ok=ok and r.restores.all(func(x:Dictionary)->bool:return x.visible_controls and x.same_world_state and x.selection_same and x.bytes>0)
	await economic_action_finish(host,r,"MATERIAL_TRADE_AND_PRODUCTION_COMPLETE" if ok else "MATERIAL_TRADE_INCOMPLETE",0 if ok else 5)

func living_state(host: Object) -> Dictionary:
	var state := multi_frame(host)
	var model: WorldState=host.get("_world")
	state["wages"]=model.economy_r1._wages.duplicate(true)
	state["orders"]=model.economy_r1._orders.duplicate(true)
	state["employment_ends"]=model.economy_r1._employment_ends.duplicate(true)
	return state

func living_ui_restore(host: Object) -> Dictionary:
	var shell: Object=host.get("main_shell")
	var page: Object=shell.get("person_page")
	var model: WorldState=host.get("_world")
	var before: Dictionary=host.get("_persistence").snapshot()
	var selection: Array=[page.get("selected_job_id"),page.get("native_tab"),page.get("selected_commodity_id")]
	var ok: bool=await economic_click(shell,"system")
	ok=await economic_click(shell,"save") and ok
	ok=await economic_click(shell,"slot:choose:4") and ok
	if shell.get("_confirmation").get("kind")=="overwrite": ok=await economic_click(shell,"slot:save:4") and ok
	await wait_seconds(.3)
	var path:=FormalPersistence.slot_path(4)
	var bytes: int=FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	ok=await economic_click(shell,"system") and ok
	ok=await economic_click(shell,"load") and ok
	ok=await economic_click(shell,"slot:choose:4") and ok
	await wait_seconds(.4)
	return {"visible_controls":ok,"bytes":bytes,"same_world_state":before==host.get("_persistence").snapshot(),"selection_same":selection==[page.get("selected_job_id"),page.get("native_tab"),page.get("selected_commodity_id")],"new_world":model.get_instance_id()!=host.get("_world").get_instance_id()}

func living_clock(host: Object,target: int) -> bool:
	var shell: Object=host.get("main_shell")
	var ok: bool=await economic_click(shell,"time:4")
	var deadline:=Time.get_ticks_msec()+90000
	while host.get("_world").game_clock.total_minutes()<target and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	if not host.get("time_control").paused: ok=await economic_click(shell,"time:pause") and ok
	await wait_seconds(.2)
	return ok and host.get("_world").game_clock.total_minutes()>=target

func living_map_roundtrip(shell: Object) -> bool:
	var ok: bool=await economic_click(shell,"page:map")
	ok=await economic_click(shell,"map:mode_menu") and ok
	ok=await economic_click(shell,"map:economy_mode") and ok
	await wait_seconds(.3)
	ok=await economic_button(shell.get("economic_map"),"返回政治地图") and ok
	ok=await economic_click(shell,"page:person") and ok
	ok=await economic_click(shell,"person:native") and ok
	return ok

func acceptance_living_ui(host: Object) -> void:
	get_window().title="WWO 就业与生活界面 · 隔离验证";get_window().grab_focus()
	var shell: Object=host.get("main_shell")
	var page: Object=shell.get("person_page")
	await wait_seconds(.2)
	if not host.get("time_control").paused: await economic_click(shell,"time:pause")
	var model: WorldState=host.get("_world")
	var player:=model.player_state.player_id()
	var low:="job:opening_paris_workshop"
	var high:="job:opening_paris_bakery"
	var r: Dictionary={"user_dir":OS.get_user_data_dir(),"opening":model.economy_r1.config.duplicate(true),"initial":living_state(host),"timeline":[],"restores":[],"route":"Real oil menu entry, visible navigation/actions/time/save/load only; no developer facts or NPC control."}
	var ok: bool=await economic_click(shell,"page:person")
	ok=await economic_click(shell,"person:native") and ok
	r["two_jobs_visible"]=shell.get("_hits").any(func(x:Dictionary)->bool:return x.action=="person:job_select:"+low) and shell.get("_hits").any(func(x:Dictionary)->bool:return x.action=="person:job_select:"+high)
	r["no_quantity_jobs"]=not shell.get("_quantity_input").visible
	acceptance_image("living_compare")
	var unchanged:=model.economy_r1.snapshot()
	ok=await economic_click(shell,"person:job_select:"+low) and ok
	r["select_only"]=unchanged==model.economy_r1.snapshot() and page.get("selected_job_id")==low
	ok=await economic_click(shell,"person:job_request:"+low) and ok
	ok=await economic_click(shell,"confirm:cancel") and ok
	r["cancel_no_action"]=unchanged==model.economy_r1.snapshot()
	ok=await economic_click(shell,"person:living_tab:orders") and ok
	r["empty_order_no_quantity"]=not shell.get("_quantity_input").visible
	ok=await economic_click(shell,"person:living_tab:jobs") and ok
	if OS.get_environment("WWO_LIVING_UI")=="preview":
		r["preview_only"]=true
		r["map_roundtrip"]=await living_map_roundtrip(shell)
		ok=ok and r.map_roundtrip
		await economic_action_finish(host,r,"LIVING_UI_PREVIEW_COMPLETE" if ok and r.two_jobs_visible and r.select_only and r.cancel_no_action and r.empty_order_no_quantity else "LIVING_UI_PREVIEW_FAILED",0 if ok and r.two_jobs_visible and r.select_only and r.cancel_no_action and r.empty_order_no_quantity else 5)
		return
	r.restores.append(await living_ui_restore(host))
	ok=await economic_click(shell,"person:job_request:"+low) and ok
	ok=await economic_click(shell,"confirm:employment") and ok
	ok=await economic_click(shell,"native:work") and ok
	r["repeat_work_disabled"]=not await economic_click(shell,"native:work")
	r.timeline.append({"stage":"booked_not_completed","state":living_state(host),"view":page.get("_personal").duplicate(true)})
	ok=await living_clock(host,1440) and ok
	ok=await economic_click(shell,"person:living_tab:wages") and ok
	r.timeline.append({"stage":"completed_not_due","state":living_state(host),"view":page.get("_personal").duplicate(true)})
	r.restores.append(await living_ui_restore(host))
	ok=await economic_click(shell,"native:work") and ok
	ok=await living_clock(host,2880) and ok
	ok=await economic_click(shell,"person:living_tab:wages") and ok
	r.timeline.append({"stage":"paid_and_not_due","state":living_state(host),"view":page.get("_personal").duplicate(true)})
	acceptance_image("living_wages")
	ok=await economic_click(shell,"person:market") and ok
	ok=await economic_click(shell,"commodity:select:native:bread|site:opening_paris_workshop:paris") and ok
	r["purchase_quote"]=shell.get("economy_page").get("quote").duplicate(true)
	ok=await economic_click(shell,"purchase") and ok
	ok=await economic_button(shell,"查看") and ok
	ok=await economic_click(shell,"consume") and ok
	# The success link opens the existing goods view for a visible need result.
	ok=await economic_click(shell,"person:goods") and ok
	r.timeline.append({"stage":"purchased_and_consumed","state":living_state(host),"view":page.get("_personal").duplicate(true)})
	acceptance_image("living_consumed")
	r.restores.append(await living_ui_restore(host))
	ok=await economic_click(shell,"person:native") and ok
	ok=await economic_click(shell,"person:living_tab:wages") and ok
	ok=await economic_click(shell,"person:leave_request") and ok
	ok=await economic_click(shell,"confirm:employment") and ok
	r.timeline.append({"stage":"exit_pending_old_claim_retained","state":living_state(host),"view":page.get("_personal").duplicate(true)})
	r["pending_no_work"]=not await economic_click(shell,"native:work")
	r.restores.append(await living_ui_restore(host))
	ok=await living_clock(host,4320) and ok
	ok=await economic_click(shell,"person:living_tab:jobs") and ok
	ok=await economic_click(shell,"person:job_select:"+high) and ok
	r["other_job_full"]=not page.call("can_apply",page.call("job_row",high))
	r["other_job_reason"]=page.call("job_reason",page.call("job_row",high))
	r["other_job_no_click"]=not await economic_click(shell,"person:job_request:"+high)
	r.timeline.append({"stage":"old_contract_ended_other_employer_full","state":living_state(host),"selected_job":page.get("selected_job_id")})
	r.restores.append(await living_ui_restore(host))
	ok=await economic_click(shell,"person:living_tab:jobs") and ok
	ok=await economic_click(shell,"person:job_select:"+low) and ok
	ok=await economic_click(shell,"person:job_request:"+low) and ok
	ok=await economic_click(shell,"confirm:employment") and ok
	ok=await economic_click(shell,"native:work") and ok
	for day: int in range(4,8): ok=await living_clock(host,day*1440) and ok
	ok=await economic_click(shell,"person:living_tab:wages") and ok
	r["final"]=living_state(host)
	r["commands"]=host.get("_world").economy_r1._commands.duplicate(true)
	r["ledger"]=host.get("_world").ledger_state._transactions.duplicate(true)
	r["deliveries"]=host.get("_world").economy_r1._delivery_receipts.duplicate(true)
	r["person_view"]=page.get("_personal").duplicate(true)
	var read_state: Dictionary=host.get("_persistence").snapshot()
	var camera_state: Array=[controller.orientation(),controller.zoom,controller.region_camera.origin,controller.region_camera.km_per_pixel,controller.selected_place_id,controller.selected_polity_id]
	var selected_job: String=page.get("selected_job_id")
	ok=await living_map_roundtrip(shell) and ok
	r["map_return_parts"]={"state":read_state==host.get("_persistence").snapshot(),"selection":selected_job==page.get("selected_job_id"),"camera":camera_state==[controller.orientation(),controller.zoom,controller.region_camera.origin,controller.region_camera.km_per_pixel,controller.selected_place_id,controller.selected_polity_id]}
	r["map_return_context"]=r.map_return_parts.state and r.map_return_parts.selection and r.map_return_parts.camera
	var refresh_us: Array[int]=[]
	for sample: int in range(5):
		var began:=Time.get_ticks_usec()
		host.call("_refresh_ui")
		refresh_us.append(Time.get_ticks_usec()-began)
	r["explicit_page_refresh_us"]=refresh_us
	r["complete"]=r.final.actors[player].totals.work_hours==6 and r.final.actors[player].totals.income==18 and r.final.actors[player].cash==2516 and r.final.actors[player].totals.categories.food.satisfied==1 and r.final.actors[player].inventory.bread==0
	ok=ok and r.complete and r.map_return_context and r.two_jobs_visible and r.select_only and r.cancel_no_action and r.empty_order_no_quantity and r.repeat_work_disabled and r.pending_no_work and r.other_job_full and r.other_job_no_click and r.restores.all(func(x:Dictionary)->bool:return x.visible_controls and x.same_world_state and x.selection_same and x.bytes>0)
	await economic_action_finish(host,r,"LIVING_UI_COMPLETE" if ok else "LIVING_UI_FAILED",0 if ok else 5)

func terrain_region_sample(label: String, seconds: float, target: Control=null) -> Dictionary:
	FileAccess.open(output+"/phase.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":label}))
	var values: Array[float]=[]
	var begin:=Time.get_ticks_usec()
	var previous:=begin
	while Time.get_ticks_usec()-begin<int(seconds*1000000):
		await get_tree().process_frame
		if target!=null and values.size()%6==0:
			if label=="zoom":
				var wheel:=InputEventMouseButton.new()
				wheel.position=Vector2(640,420)
				wheel.button_index=MOUSE_BUTTON_WHEEL_UP if values.size()%48<24 else MOUSE_BUTTON_WHEEL_DOWN
				wheel.pressed=true
				get_viewport().push_input(wheel,true)
				var wheel_up:=wheel.duplicate() as InputEventMouseButton
				wheel_up.pressed=false
				get_viewport().push_input(wheel_up,true)
			elif label=="drag":
				var motion:=InputEventMouseMotion.new()
				motion.position=Vector2(640+values.size(),420)
				motion.relative=Vector2(6,0)
				motion.button_mask=MOUSE_BUTTON_MASK_LEFT
				get_viewport().push_input(motion,true)
		var now:=Time.get_ticks_usec()
		values.append((now-previous)/1000.0)
		previous=now
	values.sort()
	return {"phase":label,"frames":values.size(),"p95_frame_ms":values[mini(values.size()-1,int(values.size()*.95))],"max_frame_ms":values.back(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"static_bytes":OS.get_static_memory_usage(),"window_focused":get_window().has_focus()}

func terrain_region_image(label: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")
	print("REGION_IMAGE ",label)

func terrain_training_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	# The native controller polls physical keys; this is generated ordinary input,
	# not a direct vehicle-position write or a second driving implementation.
	Input.parse_input_event(event)

func terrain_training_aim(target: Node3D, native_camera: Camera3D, controls: Control, aim_height: float = 1.0) -> void:
	for attempt: int in range(4):
		var direction: Vector3 = (target.global_position + Vector3(0, aim_height, 0) - native_camera.global_position).normalized()
		var desired_yaw: float = atan2(-direction.x, -direction.z)
		var desired_pitch: float = asin(clampf(direction.y, -1.0, 1.0))
		var delta_look: Vector2 = Vector2(wrapf(float(controls.get("camera_yaw")) - desired_yaw, -PI, PI), float(controls.get("camera_pitch")) - desired_pitch) / 0.0048
		await mouse_button(Vector2(680,340), MOUSE_BUTTON_LEFT, true)
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = Vector2(680,340)
		motion.relative = delta_look
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		await mouse_button(Vector2(680,340), MOUSE_BUTTON_LEFT, false)
		await wait_seconds(0.8)
	# Observe the original mechanical slew; never snap its desired or actual pose.
	for frame: int in range(480):
		await get_tree().physics_frame
		if not bool(controls.get("main").get("aiming_pending")): break

func terrain_training_crew_roundtrip(session: Node, battle: Node3D, controls: Control) -> Dictionary:
	var hero: Node3D = battle.get("hero") as Node3D
	var crew_host: Node = battle.get("crew_host") as Node
	var pid: String = str(crew_host.call("commander_person_id"))
	var actor: CharacterBody3D = battle.get("ai_host").get("actors")[pid] as CharacterBody3D
	var actor_id: int = actor.get_instance_id()
	var before: Dictionary = session.call("get_status") as Dictionary
	for frame: int in range(180):
		if absf(float(hero.get_meta("vehicle_speed", 0.0))) <= 0.5: break
		await get_tree().physics_frame
	var board_rect: Rect2 = controls.call("board_exit_rect")
	await mouse_button(board_rect.get_center(), MOUSE_BUTTON_LEFT, true)
	await mouse_button(board_rect.get_center(), MOUSE_BUTTON_LEFT, false)
	await wait_seconds(0.25)
	var exited: Dictionary = session.call("get_status") as Dictionary
	var report: Dictionary = {"exited": exited.get("on_foot", false), "after_exit": exited}
	if not bool(report.exited):
		report["ok"] = false
		return report
	var exit_position: Vector3 = actor.global_position
	var yaw: float = float(controls.get("camera_yaw"))
	var forward: Vector3 = Vector3(-sin(yaw),0,-cos(yaw))
	var right: Vector3 = Vector3(cos(yaw),0,-sin(yaw))
	var directions: Array[Vector3] = [forward,-forward,right,-right]
	var codes: Array[Key] = [KEY_W,KEY_S,KEY_D,KEY_A]
	var away: Vector3 = (actor.global_position - hero.global_position) * Vector3(1,0,1)
	var chosen: int = 0
	for index: int in range(1,4):
		if away.dot(directions[index]) > away.dot(directions[chosen]): chosen=index
	terrain_training_key(codes[chosen], true)
	for frame: int in range(360):
		await get_tree().physics_frame
		if actor.global_position.distance_to(hero.global_position)>6.2: break
	terrain_training_key(codes[chosen], false)
	await wait_seconds(0.15)
	report["walked_metres"] = actor.global_position.distance_to(exit_position)
	report["outside_boarding_range_m"] = actor.global_position.distance_to(hero.global_position)
	await terrain_region_image("15-original-commander-on-foot")
	terrain_training_key(codes[chosen ^ 1], true)
	for frame: int in range(300):
		await get_tree().physics_frame
		if actor.global_position.distance_to(hero.global_position)<5.4: break
	terrain_training_key(codes[chosen ^ 1], false)
	await wait_seconds(0.15)
	report["boarding_access"] = crew_host.call("boarding_access", pid)
	board_rect = controls.call("board_exit_rect")
	await mouse_button(board_rect.get_center(), MOUSE_BUTTON_LEFT, true)
	await mouse_button(board_rect.get_center(), MOUSE_BUTTON_LEFT, false)
	await wait_seconds(0.3)
	var returned: Dictionary = session.call("get_status") as Dictionary
	report["after_return"] = returned
	report["same_actor"] = actor_id == (battle.get("ai_host").get("actors")[pid] as Node).get_instance_id()
	report["injury_and_ammo_preserved"] = before.crew[0].hp == returned.crew[0].hp and before.crew[0].parts == returned.crew[0].parts and before.ammo.spent == returned.ammo.spent and before.ammo.total == returned.ammo.total
	report["ok"] = not bool(returned.get("on_foot",true)) and report.same_actor and report.injury_and_ammo_preserved and returned.crew_registry.vehicles.player_vehicle.seats["0"].person_id == pid and float(report.walked_metres)>1.0
	await terrain_region_image("16-original-commander-reboarded")
	return report

func terrain_training_review(observation: Control, phases: Array) -> Dictionary:
	var report: Dictionary = {"requested": true, "ok": false}
	var clicked: bool = await economic_button(observation, "原生坦克训练（隔离）")
	for attempt: int in range(1800):
		var status_data: Dictionary = observation.call("get_training_status") as Dictionary
		if status_data.get("ready", false) or status_data.get("state", "") == "failed": break
		await get_tree().process_frame
	var session: Node = observation.get("_training") as Node
	if not clicked or not is_instance_valid(session):
		report["error"] = "original_training_did_not_start"
		return report
	var first: Dictionary = session.call("get_status") as Dictionary
	if not bool(first.get("ready", false)):
		report["error"] = first
		return report
	var battle: Node3D = session.call("get_native_battle") as Node3D
	var controls: Control = battle.get("battle_controls") as Control
	var hero: Node3D = battle.get("hero") as Node3D
	var target: Node3D = battle.get("target") as Node3D
	var native_camera: Camera3D = session.call("get_native_camera") as Camera3D
	var hero_id: int = hero.get_instance_id()
	report["initial"] = first
	phases.append(await terrain_region_sample("training_idle", 3))
	await terrain_region_image("10-native-training-ready")
	# Aim by the original manual drag. No snap, forced roll, target assignment,
	# damage write, stock grant or instant projectile settlement is used.
	await terrain_training_aim(target, native_camera, controls)
	var before_shot: Dictionary = session.call("get_status") as Dictionary
	terrain_training_key(KEY_SPACE, true)
	await wait_seconds(0.12)
	terrain_training_key(KEY_SPACE, false)
	await terrain_region_image("11-native-cannon-fired")
	phases.append(await terrain_region_sample("training_projectile_impact", 4))
	var after_shot: Dictionary = session.call("get_status") as Dictionary
	report["before_shot"] = before_shot
	report["after_shot"] = after_shot
	await terrain_region_image("12-native-real-impact")
	var drive_start: Vector3 = hero.position
	terrain_training_key(KEY_W, true)
	phases.append(await terrain_region_sample("training_driving", 3))
	terrain_training_key(KEY_A, true)
	phases.append(await terrain_region_sample("training_steering", 1.4))
	terrain_training_key(KEY_W, false)
	terrain_training_key(KEY_A, false)
	await wait_seconds(0.8)
	report["driven_metres"] = drive_start.distance_to(hero.position)
	report["after_drive"] = session.call("get_status")
	await terrain_region_image("13-native-driving-steering")
	# Same AP pool, after actual movement to a different incidence. A blocked first
	# shot is kept as fact; neither penetration nor a crew wound is forced here.
	report["first_shot"] = after_shot
	await terrain_training_aim(target, native_camera, controls, 0.65)
	terrain_training_key(KEY_SPACE, true)
	await wait_seconds(0.12)
	terrain_training_key(KEY_SPACE, false)
	phases.append(await terrain_region_sample("training_second_incidence", 4))
	after_shot = session.call("get_status") as Dictionary
	report["after_shot"] = after_shot
	await terrain_region_image("17-native-second-incidence")
	report["crew_roundtrip"] = await terrain_training_crew_roundtrip(session, battle, controls)
	var native_menu_point: Vector2 = Vector2(controls.size.x - 42.0, 42.0)
	await mouse_button(native_menu_point, MOUSE_BUTTON_LEFT, true)
	await mouse_button(native_menu_point, MOUSE_BUTTON_LEFT, false)
	report["native_menu_accessible"] = bool(controls.get("menu_open"))
	await terrain_region_image("18-native-original-menu")
	await mouse_button(native_menu_point, MOUSE_BUTTON_LEFT, true)
	await mouse_button(native_menu_point, MOUSE_BUTTON_LEFT, false)
	report["paused_by_host_button"] = await economic_button(observation, "隔离训练 · 暂停并观察 / Esc")
	var paused_before: Dictionary = session.call("get_status") as Dictionary
	phases.append(await terrain_region_sample("training_paused_observation", 2))
	var paused_after: Dictionary = session.call("get_status") as Dictionary
	report["paused_state_preserved"] = paused_before.native_ammo == paused_after.native_ammo and paused_before.crew == paused_after.crew and paused_before.target == paused_after.target and paused_before.elapsed == paused_after.elapsed
	report["resumed_by_button"] = await economic_button(observation, "恢复原训练（弹药 / 伤损保留）")
	await wait_seconds(0.5)
	report["same_vehicle_instance"] = hero_id == (session.call("get_native_battle").get("hero") as Node3D).get_instance_id()
	report["same_session"] = first.session_id == (session.call("get_status") as Dictionary).session_id
	await mouse_button(native_menu_point, MOUSE_BUTTON_LEFT, true)
	await mouse_button(native_menu_point, MOUSE_BUTTON_LEFT, false)
	report["returned_by_native_menu"] = await economic_button(observation, "返回观察（保留本次训练）")
	await terrain_region_image("14-observe-after-preserved-training")
	var initial_crew: Array = first.get("crew", []) as Array
	var shot_rows: Array = after_shot.get("shot_audit", []) as Array
	report["original_injury_preserved"] = initial_crew.size() == 5 and int(initial_crew[0].hp) == 7 and initial_crew[0].parts.left_arm == "injured"
	report["legal_cannon_fired"] = shot_rows.any(func(row: Dictionary) -> bool: return row.get("accepted", false) and row.get("weapon", "") == "tank_cannon")
	report["projectile_contact_recorded"] = shot_rows.any(func(row: Dictionary) -> bool: return row.get("flight_state", "") == "impacted" and float(row.get("flight_seconds", 0)) > 0)
	report["target_changed"] = before_shot.target != after_shot.target
	report["ok"] = report.legal_cannon_fired and report.projectile_contact_recorded and report.original_injury_preserved and report.paused_state_preserved and report.same_vehicle_instance and report.same_session and report.native_menu_accessible and report.paused_by_host_button and report.returned_by_native_menu and bool(report.crew_roundtrip.get("ok", false)) and float(report.driven_metres) > 5.0
	return report

func terrain_region_run() -> void:
	if output.is_empty() or not OS.get_user_data_dir().get_file().begins_with("WWO_R57_Visual_Region_"):
		push_error("Region review requires its own explicit output and isolated user directory: "+OS.get_user_data_dir())
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	print("REGION_USER_DIR ",OS.get_user_data_dir())
	FileAccess.open(output.path_join("window-handle.json"),FileAccess.WRITE).store_string(JSON.stringify({"pid":OS.get_process_id(),"hwnd":DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,get_window().get_window_id())}))
	get_window().title="WWO · 原正式世界 → 分层军事地貌"
	await wait_seconds(1)
	var menu: Node=get_tree().current_scene
	var ok:=await economic_button(menu,"开始")
	for attempt: int in range(1800):
		if menu.get("_preview_ready")==true: break
		await get_tree().process_frame
	await wait_seconds(.6)
	await terrain_region_image("01-legal-person-selection")
	ok=await economic_button(menu,"进入世界") and ok
	var host: Node
	for attempt: int in range(1800):
		var candidate:=get_tree().current_scene
		if candidate is FormalWorldApplication and candidate.get("_world")!=null:
			host=candidate
			break
		await get_tree().process_frame
	if host==null:
		push_error("Normal menu could not install its formal world")
		get_tree().quit(3)
		return
	renderer=host.get("map_renderer")
	controller=host.get("map_controller")
	await wait_seconds(3)
	var shell: Object=host.get("main_shell")
	var world: WorldState=host.get("_world")
	var person_id:=world.player_state.player_id()
	var person_before:=world.person_overlay.person(person_id).duplicate(true)
	var facts_before: Dictionary=host.get("_persistence").snapshot()
	var pose_before: Array=[controller.orientation(),controller.zoom,controller.region_camera.origin,controller.region_camera.km_per_pixel,controller.selected_place_id,controller.selected_polity_id]
	await terrain_region_image("02-original-formal-world")
	ok=await economic_click(shell,"map:mode_menu") and ok
	ok=await economic_click(shell,"terrain:open") and ok
	var observation: Control=host.get("_terrain_observation")
	if observation==null:
		push_error("Military terrain visible menu entry did not open")
		get_tree().quit(4)
		return
	var ground: Node3D=observation.get("terrain")
	for attempt: int in range(3600):
		if ground!=null and ground.call("is_ready") and not ground.call("get_status").loading and int(ground.call("get_status").queued_tiles)==0: break
		await get_tree().process_frame
	await wait_seconds(1)
	await terrain_region_image("03-region-50km")
	var phases: Array=[]
	phases.append(await terrain_region_sample("50km_idle",3))
	ok=await economic_button(observation,"25 km") and ok
	await wait_seconds(1)
	await terrain_region_image("04-region-25km")
	ok=await economic_button(observation,"进入选中 5 km") and ok
	phases.append(await terrain_region_sample("enter_5km",3))
	await terrain_region_image("05-native-5km")
	phases.append(await terrain_region_sample("5km_idle",3))
	ok=await economic_button(observation,"村庄 / 道路") and ok
	phases.append(await terrain_region_sample("enter_detail",3))
	await terrain_region_image("06-village-materials")
	phases.append(await terrain_region_sample("village_idle",3))
	phases.append(await terrain_region_sample("zoom",3,observation))
	await mouse_button(Vector2(640,420),MOUSE_BUTTON_LEFT,true)
	phases.append(await terrain_region_sample("drag",3,observation))
	await mouse_button(Vector2(820,420),MOUSE_BUTTON_LEFT,false)
	ok=await economic_button(observation,"步行观察（隔离）") and ok
	for attempt: int in range(1200):
		if observation.get("_walking")==true: break
		await get_tree().process_frame
	var walked:=false
	var start:=Vector3.ZERO
	var finish:=Vector3.ZERO
	var body:=observation.get("_walker") as CharacterBody3D
	if body!=null:
		start=body.position
		var down:=InputEventKey.new();down.keycode=KEY_W;down.pressed=true;get_viewport().push_input(down,true)
		phases.append(await terrain_region_sample("walking_motion",4))
		var up:=InputEventKey.new();up.keycode=KEY_W;up.pressed=false;get_viewport().push_input(up,true)
		await wait_seconds(.5)
		finish=body.position
		walked=start.distance_to(finish)>5 and body.is_on_floor()
	await terrain_region_image("07-isolated-walking")
	phases.append(await terrain_region_sample("walking_still",3))
	var training_report: Dictionary = {"requested": false}
	if OS.get_environment("WWO_VISUAL_MILITARY_TRAINING") == "1":
		training_report = await terrain_training_review(observation, phases)
		ok = bool(training_report.get("ok", false)) and ok
	else:
		ok=await economic_button(observation,"上一级 / Esc") and ok
	ok=await economic_button(observation,"上一级 / Esc") and ok
	phases.append(await terrain_region_sample("return_region",2))
	await terrain_region_image("08-return-selected-region")
	var ground_status: Dictionary=ground.call("get_status")
	ok=await economic_button(observation,"返回正式世界") and ok
	phases.append(await terrain_region_sample("return_formal",2))
	await terrain_region_image("09-return-original-world")
	var facts_after: Dictionary=host.get("_persistence").snapshot()
	ok=ok and host.get("_terrain_observation")==null
	var camera_same:=pose_before==[controller.orientation(),controller.zoom,controller.region_camera.origin,controller.region_camera.km_per_pixel,controller.selected_place_id,controller.selected_polity_id]
	var result: Dictionary={"normal_menu_clicks":ok,"world_same_instance":world==host.get("_world"),"world_snapshot_unchanged":facts_before==facts_after,"person_unchanged":person_before==world.person_overlay.person(person_id),"camera_and_selection_unchanged":camera_same,"person_id":person_id,"minute":world.game_clock.total_minutes(),"isolated_walked_on_collision":walked,"walk_start_m":str(start),"walk_end_m":str(finish),"terrain_status_after_return_to_region":ground_status,"military_training":training_report,"phases":phases,"renderer_method":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"user_dir":OS.get_user_data_dir(),"note":"Native no-focus visible window. Frame/process metrics are not GPU execution time. No saving or formal deployment; combat, when explicitly requested, belongs only to the isolated native training session."}
	var file:=FileAccess.open(output+"/region-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("REGION_REVIEW_RESULT ",JSON.stringify(result))
	get_tree().quit(0 if ok and walked and facts_before==facts_after and camera_same else 5)
