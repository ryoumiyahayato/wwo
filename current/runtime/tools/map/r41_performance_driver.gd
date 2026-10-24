extends Node
## Finite R41 comparison, loaded externally by a temporary override.cfg.
## Not exported. No save/load calls. The real menu and world remain in use.

var output: String = OS.get_environment("WWO_PERF_OUTPUT")
var configuration: String = OS.get_environment("WWO_PERF_CASE")
var phase: String = "engine_boot"
var frames: Array = []
var events: Array = []
var snapshots: Array = []
var last_tick: int = 0
var renderer: Object
var controller: Object
var world_scene: Object
var started: int = 0
var initial_date: Dictionary = {}
var failed: bool = false
var region_requested: bool = false
var region_presented: bool = false

func _ready() -> void:
	started = Time.get_ticks_usec()
	last_tick = started
	if not OS.get_user_data_dir().get_file().begins_with("WWO_R41_Perf_"):
		push_error("R41 measurement refused: user data is not isolated")
		get_tree().quit(2)
		return
	_process_run.call_deferred()

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	frames.append([now,phase,(now-last_tick)/1000.0,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	last_tick = now
	if phase=="world_region_zoom" and renderer!=null and controller!=null:
		var active: bool = bool(controller.get("region_camera").get("active"))
		if active and not region_requested:
			region_requested = true
			event("first_region_requested")
		if active and not region_presented and renderer.get("region_view").container.visible and not bool(renderer.get("_map_canvas_dirty")):
			region_presented = true
			event("first_region_canvas_visible")

func event(label: String, details: Dictionary = {}) -> void:
	var row: Dictionary = {"event":label,"ticks_us":Time.get_ticks_usec(),"unix":Time.get_unix_time_from_system(),"details":details}
	events.append(row)
	FileAccess.open(output+"/progress.json",FileAccess.WRITE).store_string(JSON.stringify(row))
	print("R41_PERF ",label," ",JSON.stringify(row))

func wait_seconds(seconds: float) -> void:
	var end: int = Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec()<end: await get_tree().process_frame

func _process_run() -> void:
	event("isolation",{"user_dir":OS.get_user_data_dir(),"case":configuration,"renderer":RenderingServer.get_video_adapter_name(),"backend":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()})
	get_tree().current_scene = null # Keep only this external observer across normal scene changes.
	get_tree().change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: Object = get_tree().current_scene
	event("menu_usable",{"window":str(get_window().size)})
	await wait_seconds(0.25)
	phase = "selection_loading"
	event("start_clicked")
	menu.call("_show_page","selection")
	var deadline: int = Time.get_ticks_usec()+90000000
	var first_visible: bool = false
	var last_stage: String = ""
	while Time.get_ticks_usec()<deadline:
		await get_tree().process_frame
		var stage: String = str(menu.get("_preview_stage"))
		if stage!=last_stage:
			last_stage = stage
			event("selection_stage",{"stage":stage})
		renderer = menu.get("_renderer")
		if renderer==null: continue
		if not first_visible and bool(menu.get("_preview_ready")):
			first_visible = true
			event("sphere_first_visible")
		var status: Dictionary = renderer.call("current_view_map_status")
		if bool(menu.get("_preview_ready")) and str(status.get("state"))=="installed": break
		if not str(menu.get("_preview_error")).is_empty():
			event("failure",{"reason":menu.get("_preview_error")})
			failed = true
			break
	if renderer==null or not bool(menu.get("_preview_ready")):
		event("failure",{"reason":"selection timeout"})
		finish()
		return
	controller = renderer.get("controller")
	event("political_interactive",resource_snapshot())
	phase = "selection_stable"
	await wait_seconds(1.0)
	var renderer_id: int = renderer.get_instance_id()
	phase = "world_loading"
	event("enter_clicked")
	menu.call("_enter_world","new",0)
	deadline = Time.get_ticks_usec()+60000000
	while Time.get_ticks_usec()<deadline:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene!=null and scene!=menu and scene.get("_world")!=null and scene.get("_simulation_step")!=null:
			world_scene = scene
			break
	if world_scene==null:
		event("failure",{"reason":"formal world timeout"})
		finish()
		return
	renderer = world_scene.get("map_renderer")
	controller = world_scene.get("map_controller")
	var time_control: Object = world_scene.get("time_control")
	if not bool(time_control.get("paused")): time_control.call("toggle_pause")
	initial_date = world_scene.get("_world").game_clock.current_date()
	world_scene.get("main_shell").call("set_page","map")
	event("world_usable",{"same_renderer":renderer.get_instance_id()==renderer_id,"date":initial_date,"paused":time_control.get("paused")})
	if configuration=="C":
		renderer.call("set_internal_load_test",true)
		event("high_load_explicitly_enabled")
	phase = "world_still"
	await wait_seconds(1.5)
	snapshot("world_before_tour")
	await world_rotation()
	await scale_trip()
	for region: Array in [["germany",10.5,50.8],["france",2.5,48.5]]:
		phase = "admin_"+str(region[0])
		controller.call("focus_region",unit(float(region[1]),float(region[2])),renderer.get("size")*0.5,0.5,0.0,renderer.get("size"))
		await wait_seconds(1.5)
		snapshot(phase)
	# Keep the same political map purpose in all three measured routes. R40's
	# geographic overlay empty-array error is not allowed to bias this comparison.
	var places: Array = [
		["paris",2.2945,48.858333,"place:paris"],
		["pont_iena",2.292324,48.860151,"place:paris"],
		["gare_du_nord",2.3553,48.8809,"place:paris"],
		["london",-0.1246,51.5007,"place:london"],
		["westminster_bridge",-0.121778,51.500898,"place:london"],
		["zermatt",7.703304,46.010743,"geographic_region:zermatt_west_reference"],
		["giza",31.131557,29.976122,"landmark:giza_pyramids_1900"],
		["friedrichstrasse",13.388,52.52,"place:berlin"]]
	for place: Array in places: await visit(place,true)
	var new_places: Array = [
		["orange",4.808417,44.135722,"landmark:orange_reference"],
		["pisa",10.396389,43.723056,"landmark:pisa_reference"],
		["parthenon",23.72618,37.97087,"landmark:parthenon_reference"],
		["petra",35.45154,30.32208,"landmark:petra_reference"],
		["taj_mahal",78.04222,27.17417,"landmark:taj_mahal_reference"],
		["temple_heaven",116.406667,39.882167,"landmark:temple_heaven_reference"],
		["hagia_sophia",28.98,41.00833,"landmark:hagia_sophia_reference"]]
	for place: Array in new_places:
		if configuration!="A": await visit(place,false)
		else:
			phase = str(place[0])+"_no_R40_asset"
			controller.call("focus_region",unit(float(place[1]),float(place[2])),renderer.get("size")*0.5,0.003,0.0,renderer.get("size"))
			await wait_seconds(0.4)
			event("R40_asset_not_present",{"place":place[0]})
	await visit(["paris_revisit",2.2945,48.858333,"place:paris"],true)
	if configuration!="A":
		phase = "geographic_fix_check"
		controller.call("set_map_mode","geographic")
		await wait_seconds(0.5)
		controller.call("set_map_mode","political")
	controller.call("focus",unit(2.5,48.5))
	controller.call("set_world_zoom",0.86)
	controller.call("set_map_mode","political")
	phase = "world_after_tour"
	await wait_seconds(2.5)
	snapshot("world_after_tour")
	await world_rotation()
	event("simulation_unchanged",{"before":initial_date,"after":world_scene.get("_world").game_clock.current_date(),"paused":time_control.get("paused")})
	# Exercise the existing no-save departure, then let its normal release run.
	world_scene.set("_departure_target","menu")
	world_scene.call("_leave_world")
	phase = "return_menu"
	await wait_seconds(2.0)
	renderer = null
	controller = null
	snapshot("menu_after_world_release")
	event("finished")
	finish()

func unit(lon: float,lat: float) -> Vector3:
	var x: float = deg_to_rad(lon)
	var y: float = deg_to_rad(lat)
	return Vector3(cos(y)*sin(x),sin(y),cos(y)*cos(x))

func drag(delta: Vector2, count: int) -> void:
	var position: Vector2 = renderer.get("size")*Vector2(0.48,0.45)
	var press := InputEventMouseButton.new()
	press.position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	renderer.call("_gui_input",press)
	for i: int in range(count):
		var motion := InputEventMouseMotion.new()
		motion.relative = delta
		position += delta
		motion.position = position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		renderer.call("_gui_input",motion)
		await get_tree().process_frame
	press.pressed = false
	press.position = position
	renderer.call("_gui_input",press)
	controller.call("suspend_motion")

func world_rotation() -> void:
	controller.call("focus",unit(2.5,48.5))
	controller.call("set_world_zoom",0.86)
	phase = "world_rotation"
	event("rotation_begin")
	await drag(Vector2(4.5,0),60)
	await drag(Vector2(-4.5,0),60)
	snapshot("rotation_end")

func scale_trip() -> void:
	phase = "world_region_zoom"
	event("zoom_begin")
	for direction: int in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		for i: int in range(13):
			var wheel := InputEventMouseButton.new()
			wheel.position = renderer.get("size")*0.5
			wheel.pressed = true
			wheel.button_index = direction
			renderer.call("_gui_input",wheel)
			await wait_seconds(0.06)
	snapshot("zoom_end")

func visit(place: Array, pan: bool) -> void:
	var name: String = str(place[0])
	var id: String = str(place[3])
	phase = name+"_install"
	event("local_requested",{"place":name,"id":id})
	controller.call("focus_region",unit(float(place[1]),float(place[2])),renderer.get("size")*0.5,0.003,0.0,renderer.get("size"))
	var admitted: bool = bool(controller.call("enter_local",unit(float(place[1]),float(place[2])),renderer.get("size")*0.5,renderer.get("size"),id,2.0))
	var deadline: int = Time.get_ticks_usec()+15000000
	var first_model: bool = false
	var last_pending: int = -1
	while Time.get_ticks_usec()<deadline:
		await get_tree().process_frame
		var view: Object = renderer.get("region_view")
		var pending: Dictionary = view.get("_landmark_pending")
		if pending.size()!=last_pending:
			last_pending = pending.size()
			event("local_read_queue",{"place":name,"pending":last_pending})
		var instances: Dictionary = view.get("_landmark_instances")
		var presented: Dictionary = view.get("_landmark_presented")
		if not first_model and not presented.is_empty():
			first_model = true
			event("local_first_model",{"place":name,"models":presented.keys()})
		if not admitted or (not instances.is_empty() or not str(view.get("_surface_presented_key")).is_empty()) and not bool(view.call("landmark_preparing")):
			break
	event("local_ready",{"place":name,"admitted":admitted,"has_model":first_model,"resources":resource_snapshot()})
	phase = name+"_steady"
	await wait_seconds(0.8)
	if pan:
		phase = name+"_pan"
		await drag(Vector2(0.5,0),24)
		await drag(Vector2(-0.5,0),24)
		snapshot(name+"_after_pan")
	if OS.get_environment("WWO_PERF_SCREENSHOTS")=="1" and name in ["paris","pont_iena","london","zermatt","gare_du_nord","friedrichstrasse","taj_mahal","petra","temple_heaven"]:
		phase = "capture_excluded"
		get_viewport().get_texture().get_image().save_png(output+"/"+name+".png")

func resource_snapshot() -> Dictionary:
	var result: Dictionary = {"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	if renderer==null or not is_instance_valid(renderer): return result
	var view: Object = renderer.get("region_view")
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	var node_count: int = 0
	var instance_count: int = 0
	var instances_in_window: int = 0
	var queue: Array = []
	var root: Node = view.get("_landmark_root")
	if root!=null: queue.append(root)
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		queue.append_array(node.get_children())
		if not node is GeometryInstance3D or not node.is_visible_in_tree(): continue
		if node in [view.get("_local_surface"),view.get("_surface_lines"),view.get("_surface_cover")]: continue
		var mesh: Mesh
		if node is MeshInstance3D:
			mesh = node.mesh
			instance_count += 1
		elif node is MultiMeshInstance3D and node.multimesh!=null:
			mesh = node.multimesh.mesh
			instance_count += node.multimesh.instance_count
		if mesh==null: continue
		var transforms: Array[Transform3D] = []
		if node is MultiMeshInstance3D:
			for i: int in range(node.multimesh.instance_count): transforms.append(node.global_transform*node.multimesh.get_instance_transform(i))
		else: transforms.append(node.global_transform)
		for transform: Transform3D in transforms:
			var bounds: Rect2 = Rect2()
			for corner: int in range(8):
				var point: Vector2 = view.call("_chart_pixel",transform*mesh.get_aabb().get_endpoint(corner))
				bounds = bounds.expand(point) if corner>0 else Rect2(point,Vector2.ZERO)
			if Rect2(Vector2.ZERO,renderer.get("size")).intersects(bounds): instances_in_window += 1
		node_count += 1
		meshes[mesh.get_instance_id()] = true
		for i: int in range(mesh.get_surface_count()):
			var material: Material = mesh.surface_get_material(i)
			if node.material_override!=null: material = node.material_override
			if material!=null: materials[material.get_instance_id()] = true
	result.merge({"local_nodes":node_count,"local_instances":instance_count,"instances_intersect_window":instances_in_window,"local_meshes":meshes.size(),"local_materials":materials.size(),"model_roots":(view.get("_landmark_instances") as Dictionary).keys(),"model_pending":(view.get("_landmark_pending") as Dictionary).size(),"scene_cache":(view.get("_landmark_scenes") as Dictionary).size(),"surface":view.get("_local_surface_key")})
	var camera: Object = controller.get("region_camera")
	result["region"] = camera.get("active")
	result["local"] = camera.get("local_active")
	result["mpp"] = float(camera.get("km_per_pixel"))*1000.0
	var helper: Object = view.get("_internal_scene_load")
	result["test_extra_instances"] = int(helper.get("extra_instances")) if helper!=null else 0
	result["test_base_instances"] = int(helper.get("base_instances")) if helper!=null else 0
	for name: String in ["_world_layer","_region_layer"]:
		var layer: Object = renderer.get(name)
		result[name+"_batches"] = (layer.get("_batches") as Array).size()
		result[name+"_fallback"] = (layer.get("_fallback_batches") as Array).size()
	return result

func snapshot(label: String) -> void:
	var row: Dictionary = resource_snapshot()
	row["label"] = label
	row["ticks_us"] = Time.get_ticks_usec()
	snapshots.append(row)
	event("snapshot",row)

func finish() -> void:
	set_process(false)
	FileAccess.open(output+"/events.json",FileAccess.WRITE).store_string(JSON.stringify(events,"\t"))
	FileAccess.open(output+"/resources.json",FileAccess.WRITE).store_string(JSON.stringify(snapshots,"\t"))
	var file: FileAccess = FileAccess.open(output+"/frames.csv",FileAccess.WRITE)
	file.store_csv_line(["ticks_us","phase","frame_interval_ms","draw_calls"])
	for row: Array in frames: file.store_csv_line(row)
	file.close()
	get_tree().quit(1 if failed else 0)
