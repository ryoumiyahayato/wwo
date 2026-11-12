extends Node
## Root-viewport capture and optional bounded observation. No extra viewport.
const Catalog = preload("res://scripts/presentation/ui/map_resource_catalog.gd")
const OUTPUT: String = "user://screenshots"
signal completed(result: Dictionary)
var renderer: GlobeRenderer
var busy: bool = false
var last_result: Dictionary = {}
var _timing: bool = false
var _timing_previous: int = 0
var _timing_frames: Array = []
var _timing_begin: Dictionary = {}
var _timing_inputs: Array = []
var _timing_injected: Array = []
var _observe_file: String = ""
var _observe_id: String = ""
var _observing: bool = false
var _observe_mouse_inside: bool = false
var _observe_resources: bool = false
var _timing_path: String = ""
var _sequence_timer: Timer
var _sequence_path: String = ""
var _sequence_frames: Array = []
var _development: RefCounted

static func observation_requested() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--observe-file="): return true
	return false

func _observe_poll() -> void:
	if _development!=null: _development.call("poll")
	if _observing or not FileAccess.file_exists(_observe_file): return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_observe_file))!=OK: return
	var command: Variant=parser.data
	if not command is Dictionary or str(command.get("id","")) in ["",_observe_id]: return
	_observing=true;_observe_id=str(command.id)
	_observe_resources = bool(command.get("resources",false))
	var result: Dictionary={"input_source":"engine_viewport; no OS cursor or focus", "id":_observe_id}
	var action: String=str(command.get("action","state"))
	if _development!=null and action in ["click","wheel","drag"]:
		get_tree().set_meta("dev_preview_input_until_msec",Time.get_ticks_msec()+15000)
	if action=="dev" and _development!=null:
		result["dev"] = await _development.call("execute",command)
	elif action=="capture": result["capture"]=await capture(str(command.get("label","observation")))
	elif action=="timing":
		_toggle_timing()
		result["timing_file"] = _timing_path if not _timing else ""
	elif action=="sequence":
		if _sequence_timer==null:
			_sequence_path=ProjectSettings.globalize_path(OUTPUT).path_join("sequence-"+str(Time.get_ticks_usec()))
			DirAccess.make_dir_recursive_absolute(_sequence_path)
			_sequence_frames.clear()
			_sequence_timer=Timer.new();_sequence_timer.wait_time=.1
			_sequence_timer.timeout.connect(_sequence_frame);add_child(_sequence_timer);_sequence_timer.start()
		else: _sequence_stop()
		result["sequence_directory"]=_sequence_path
	elif action=="settle":
		var deadline := Time.get_ticks_msec()+15000
		while _pending() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		for frame: int in clampi(int(command.get("frames",30)),2,120): await get_tree().process_frame
	elif action=="isolate" and is_instance_valid(renderer):
		for layer: LocalSpatialLayer in [renderer._world_layer,renderer._region_layer,renderer.local_layer]: layer.observation_hidden_kinds.assign(command.get("hide",[]))
		for city_layer: CityMiniature in renderer.region_view.city_views():
			for item: Dictionary in city_layer._context_items.values():
				RenderingServer.canvas_item_set_modulate(item.item as RID,Color(1,1,1,0 if "settlement_context" in command.get("hide",[]) else 1))
		renderer.region_view.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		renderer._invalidate_spatial_display()
	elif action in ["click","wheel","drag"]:
		var viewport := get_tree().root
		if not _observe_mouse_inside:
			viewport.notify_mouse_entered();_observe_mouse_inside=true
		var point := Vector2(float(command.get("x",0)),float(command.get("y",0)))
		var button: int=int(command.get("button",MOUSE_BUTTON_LEFT))
		var move := InputEventMouseMotion.new();move.position=point;move.global_position=point
		var dispatched: int=Time.get_ticks_usec()
		viewport.push_input(move,true)
		var press := InputEventMouseButton.new()
		press.position=point;press.global_position=point;press.button_index=button;press.pressed=true
		press.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else 0
		viewport.push_input(press,true)
		var dispatch_us: int=Time.get_ticks_usec()-dispatched
		await get_tree().process_frame
		if action=="drag":
			var end := Vector2(float(command.get("to_x",point.x)),float(command.get("to_y",point.y)))
			var steps := clampi(int(command.get("frames",30)),1,180)
			for i: int in steps:
				var at := point.lerp(end,float(i+1)/steps)
				var motion := InputEventMouseMotion.new()
				motion.position=at;motion.global_position=at;motion.relative=(end-point)/steps;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
				var motion_began: int=Time.get_ticks_usec()
				viewport.push_input(motion,true)
				dispatch_us+=Time.get_ticks_usec()-motion_began
				await get_tree().process_frame
			press.position=end;press.global_position=end
		press.pressed=false;press.button_mask=0
		var release_began: int=Time.get_ticks_usec()
		viewport.push_input(press,true)
		dispatch_us+=Time.get_ticks_usec()-release_began
		result["input_dispatch_us"]=dispatch_us
		if _timing and _timing_injected.size()<4096: _timing_injected.append({"began_us":dispatched,"finished_us":Time.get_ticks_usec(),"action":action,"dispatch_us":dispatch_us})
		await get_tree().process_frame
	elif action=="quit":
		FileAccess.open(_observe_file+".response.json",FileAccess.WRITE).store_string(JSON.stringify(result))
		_observing=false
		get_tree().quit.call_deferred()
		return
	# Development requests use their bounded projection; full map inventories
	# remain available through the original explicit observation commands.
	if action!="dev": result["state"]=_observation_state()
	FileAccess.open(_observe_file+".response.json",FileAccess.WRITE).store_string(JSON.stringify(result))
	_observing=false

func _sequence_frame() -> void:
	# Optional bounded root capture on the existing observer. Never used during
	# performance sampling; JPEG write/readback time is part of this recording.
	if _timing or busy or not get_tree().root.can_draw(): return
	var image := get_tree().root.get_texture().get_image()
	if image==null or image.is_empty(): return
	var frame := _sequence_frames.size()
	var name := "%05d.jpg" % frame
	image.save_jpg(_sequence_path.path_join(name),.82)
	var row: Dictionary={"file":name,"time_us":Time.get_ticks_usec()}
	if is_instance_valid(renderer) and renderer.controller!=null:
		row["mpp"]=renderer._strategic_mpp()
		row["local"]=renderer.controller.region_camera.local_active
		row["water"]=renderer.region_view.city.water_state()
	_sequence_frames.append(row)
	if _sequence_frames.size()>=900: _sequence_stop()

func _sequence_stop() -> void:
	_sequence_timer.stop();_sequence_timer.queue_free();_sequence_timer=null
	FileAccess.open(_sequence_path.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify({"input":"engine_viewport; no OS cursor", "nominal_hz":10,"frames":_sequence_frames}))
	_sequence_frames.clear()

func _observation_state() -> Dictionary:
	var result := metadata() if is_instance_valid(renderer) and renderer.controller!=null else {}
	if is_instance_valid(renderer): result["map_costs"]=renderer.observation_costs
	result["viewport_pixels"]=[get_tree().root.size.x,get_tree().root.size.y]
	result["visible_controls"]=[]
	_collect_controls(get_tree().root,result.visible_controls)
	return result

func _resource_inventory() -> Dictionary:
	var result: Dictionary = {"map": [], "city": [], "loaded_city_sources": [], "viewports": [], "landmark_scenes": [], "active_3d": [], "overlays": [], "pending": {}, "timing_arrays":[_timing_frames.size(),_timing_inputs.size(),_timing_injected.size()]}
	for entry: Array in [["world",renderer._world_layer],["region",renderer._region_layer],["local",renderer.local_layer]]:
		var layer: LocalSpatialLayer = entry[1]
		for b: Dictionary in layer._batches + layer._fallback_batches:
			var mesh: Mesh = b.geometry.mesh
			var row := _mesh_record(mesh, str(entry[0])+":"+str(b.kind), str(b.get("source_feature_id","")), b.material.get_instance_id())
			row["visible"] = b.get("visible",false)
			if b.geometry is GlobeBoundaryBatch and b.geometry.data!=null:
				row["line_texture"] = b.geometry.data.get_rid().get_id()
				row["line_texture_bytes"] = b.geometry.data.get_width()*b.geometry.data.get_height()*16
			result["map"].append(row)
		var pending := layer.diagnostic_state()
		pending["last_result"] = (pending.get("last_result",{}) as Dictionary).duplicate()
		var request: Dictionary = (pending.last_result.get("request",{}) as Dictionary).duplicate()
		if request.get("features") is Array: request["features"] = (request.features as Array).size()
		pending.last_result["request"] = request
		pending["cpu_ready_sets"] = layer._cpu_ready.size()
		pending["fallback_batches"] = layer._fallback_batches.size()
		result["pending"][entry[0]] = pending
	var pending_cities: Array=[]
	for city: CityMiniature in renderer.region_view.city_views():
		for path: String in city._mesh_cache:
			var row: Dictionary = _mesh_record(city._mesh_cache[path],"city",path,0)
			row["declared_geometry_bytes"] = city._mesh_bytes.get(path,0)
			result["city"].append(row)
		var index: Dictionary = CityMiniature._profile(str(city.profile.get("presentation_index","")))
		var paths: Dictionary = {}
		for part: Dictionary in index.get("foundation",[]): paths[str(part.path)]=true
		for part: Dictionary in index.get("water_lods",{}).get("levels",[]): paths[str(part.path)]=true
		if index.has("overview"): paths[str(index.overview.path)]=true
		if index.get("schema","")=="national_cartographic_context_v1":
			for path: String in city._mesh_cache: paths[path]=true
		else:
			for tile: Dictionary in index.get("tiles",[]):
				for lod: Dictionary in tile.lods.values(): paths[str(lod.path)]=true
		for path: String in paths:
			var mesh := ResourceLoader.get_cached_ref(path) as ArrayMesh
			if mesh!=null:
				var row := _mesh_record(mesh,"source_cache",path,0)
				row["city_owned"] = city._mesh_cache.has(path)
				result["loaded_city_sources"].append(row)
		pending_cities.append_array(city._pending_meshes.keys())
	for path: String in renderer.region_view._landmark_scenes:
		result["landmark_scenes"].append({"path":path,"object":renderer.region_view._landmark_scenes[path].get_instance_id()})
	for id: String in renderer._overlay_batches:
		for batch: Dictionary in renderer._overlay_batches[id]:
			result["overlays"].append(_mesh_record(batch.geometry.mesh,"overlay",id,batch.material.get_instance_id()))
	_collect_3d(get_tree().root,result["active_3d"])
	_collect_viewports(get_tree().root,result["viewports"])
	result["pending"]["city"] = pending_cities
	result["pending"]["landmarks"] = renderer.region_view._landmark_pending.keys()
	result["pending"]["overlay_uploads"] = renderer._overlay_uploads.size()
	result["pending"]["overlay_batches"] = renderer._overlay_batches.size()
	result["pending"]["overlay_retiring"] = renderer._overlay_retiring.size()
	result["pending"]["overlay_installing"] = renderer._overlay_installing.size()
	result["pending"]["surface_cpu_ready"] = not renderer.region_view._surface_cpu_ready.is_empty()
	result["pending"]["city_cache_budget"] = 48*1024*1024
	result["city_layers"] = renderer.region_view.city_states()
	result["pending"]["landmark_cache_budget_scenes"] = renderer.region_view.MAX_CACHED_LANDMARK_SCENES
	if renderer.spatial_world!=null:
		result["pending"]["administrative_index"] = {"revision":renderer.spatial_world._administrative_display_revision,"cached_revision":renderer.spatial_world._admin_member_view_revision,"groups":renderer.spatial_world._admin_member_view.size(),"facts":renderer.spatial_world._land_facts.size()}
	return result

func _collect_3d(node: Node, rows: Array) -> void:
	var mesh: Mesh
	var multimesh: MultiMesh
	if node is MeshInstance3D: mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		multimesh = (node as MultiMeshInstance3D).multimesh
		if multimesh!=null: mesh = multimesh.mesh
	if mesh!=null and mesh is ArrayMesh:
		var row := _mesh_record(mesh,"scene_3d",str(node.get_path()),0)
		if multimesh!=null:
			row["multimesh_rid"] = multimesh.get_rid().get_id()
			row["instances"] = multimesh.instance_count
			row["instance_payload_bytes"] = multimesh.instance_count*(48+16*int(multimesh.use_colors)+16*int(multimesh.use_custom_data))
		rows.append(row)
	for child: Node in node.get_children(): _collect_3d(child,rows)

func _mesh_record(mesh: Mesh, owner: String, path: String, material: int) -> Dictionary:
	var vertices: int = 0; var indices: int = 0; var bytes: int = 0
	for surface: int in mesh.get_surface_count():
		var count: int = mesh.surface_get_array_len(surface)
		var elements: int = mesh.surface_get_array_index_len(surface)
		var format: int = mesh.surface_get_format(surface)
		vertices += count; indices += elements
		bytes += count*(RenderingServer.mesh_surface_get_format_vertex_stride(format,count)+RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)+RenderingServer.mesh_surface_get_format_attribute_stride(format,count)+RenderingServer.mesh_surface_get_format_skin_stride(format,count))
		bytes += elements*RenderingServer.mesh_surface_get_format_index_stride(format,count)
	return {"owner":owner,"path":path,"object":mesh.get_instance_id(),"rid":mesh.get_rid().get_id(),"material":material,"vertices":vertices,"indices":indices,"base_payload_bytes":bytes}

func _collect_viewports(node: Node, rows: Array) -> void:
	if node is Viewport:
		var v: Viewport = node
		rows.append({"path":str(v.get_path()),"object":v.get_instance_id(),"rid":v.get_viewport_rid().get_id(),"texture":v.get_texture().get_rid().get_id(),"size":TerrainPixelSource.serial(v.get_visible_rect().size)})
	for child: Node in node.get_children(): _collect_viewports(child,rows)

func _collect_controls(node: Node, rows: Array) -> void:
	if node is BaseButton and (node as BaseButton).is_visible_in_tree():
		var rect := (node as Control).get_global_rect()
		var row := {"text":str(node.get("text")),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"disabled":(node as BaseButton).disabled}
		if _development!=null and node is OptionButton:
			var option := node as OptionButton
			row["path"]=str(node.get_path());row["selected"]=option.selected;row["items"]=[]
			for index: int in mini(option.item_count,64):
				row.items.append({"text":option.get_item_text(index),"disabled":option.is_item_disabled(index)})
		rows.append(row)
	for child: Node in node.get_children(): _collect_controls(child,rows)

func _process(_delta: float) -> void:
	if not is_instance_valid(renderer):
		_timing=false;_timing_frames.clear();set_process(false)
		return
	var now := Time.get_ticks_usec()
	var target: SubViewport=renderer.region_view._local_viewport
	var costs: Dictionary=renderer.observation_costs if int(renderer.observation_costs.get("frame",-1))==Engine.get_process_frames() else {}
	if _timing_previous>0 and not busy:
		_timing_frames.append([now,now-_timing_previous,Performance.get_monitor(Performance.TIME_PROCESS)*1000000.0,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),get_window().has_focus(),renderer.controller.camera_motion_active(),renderer._has_pending_preparation(),renderer.region_view.city_node_count(),renderer._strategic_mpp(),target.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if target!=null else 0,renderer.region_view.city_pending_count(),costs.get("preparation_us",0),costs.get("view_us",0),costs.get("commit_us",0),costs.get("map_us",0),costs])
	_timing_previous=now
	if _timing_frames.size()>=7200: _toggle_timing()

func _toggle_timing() -> void:
	if not is_instance_valid(renderer) or renderer.controller==null: return
	_timing=not _timing
	renderer.observation_profile=_timing
	set_process(_timing)
	if _timing:
		_timing_frames.clear();_timing_inputs.clear();_timing_injected.clear();_timing_previous=0;_timing_begin=metadata()
		return
	var folder := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("performance-"+Time.get_datetime_string_from_system().replace(":","-")+".json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"begin":_timing_begin,"end":metadata(),"columns":["time_us","interval_us","process_us","draw_calls","texture_bytes","buffer_bytes","focused","camera_motion","pending_preparation","city_nodes","mpp","local_draw_calls","pending_city_meshes","map_preparation_us","map_view_us","map_commit_us","map_us","map_phases"],"inputs":_timing_inputs,"injected_inputs":_timing_injected,"frames":_timing_frames}))
	_timing_path=path
	_timing_frames.clear();_timing_inputs.clear();_timing_injected.clear();_timing_begin.clear();_timing_previous=0
	print("NATIVE_PLAYER_TIMING ",path)

func _ready() -> void:
	set_process(false)
	process_priority=1000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--observe-file="): _observe_file=arg.trim_prefix("--observe-file=")
	if not _observe_file.is_empty():
		if "--dev-preview" in OS.get_cmdline_user_args():
			_development = load("res://scripts/presentation/ui/debug_preview_session.gd").new() as RefCounted
			_development.call("configure",self)
		if _development==null or bool(get_tree().get_meta("dev_preview_background","--dev-background" in OS.get_cmdline_user_args())):
			get_window().unfocusable=true
			get_window().keep_title_visible=false
			get_window().set_position.call_deferred(Vector2i(10000,10000))
		if FileAccess.file_exists(_observe_file):
			var previous := JSON.new()
			if previous.parse(FileAccess.get_file_as_string(_observe_file))==OK and previous.data is Dictionary: _observe_id=str(previous.data.get("id",""))
		var timer := Timer.new();timer.wait_time=.1
		timer.timeout.connect(_observe_poll);add_child(timer);timer.start()
		if _development!=null:
			FileAccess.open(_observe_file+".ready.json",FileAccess.WRITE).store_string(JSON.stringify({"pid":OS.get_process_id(),"instance":OS.get_environment("WWO_DEV_INSTANCE")}))

func _input(event: InputEvent) -> void:
	if _timing and event is InputEventMouseButton and _timing_inputs.size()<4096:
		_timing_inputs.append([Time.get_ticks_usec(),event.button_index,event.pressed,event.position.x,event.position.y])
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F10:
		get_viewport().set_input_as_handled()
		_toggle_timing()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F12:
		get_viewport().set_input_as_handled()
		if not busy: capture.call_deferred()

func _pending() -> bool:
	if not is_instance_valid(renderer) or renderer.controller==null: return false
	if not renderer.is_visible_in_tree(): return false
	return renderer._has_pending_preparation() or renderer.region_view._landmark_render_pending or renderer._map_canvas_dirty or renderer._view_dirty or renderer._local_display_dirty or renderer._resource_demand_dirty or renderer._strategic_content_dirty or renderer._transition_elapsed>=0.0 or renderer.controller.camera_motion_active()

func capture(label: String = "F12") -> Dictionary:
	if busy: return {"ok":false,"error":"capture_busy"}
	busy = true
	var began := Time.get_ticks_usec()
	var root := get_tree().root
	var result: Dictionary = {"ok":false,"label":label,"window":{"visible":root.visible,"mode":root.mode,"focused":root.has_focus()}}
	# Reject unavailable roots. Native-hidden main windows can still be drawable
	# on Compatibility; the finite driver tests that separately against a visible
	# control. Never restore, show, raise or focus a window for a screenshot.
	if not root.visible or root.mode==Window.MODE_MINIMIZED or not root.can_draw():
		result["error"]="root_hidden_or_minimized"
	else:
		var deadline := Time.get_ticks_msec()+30000
		var stable := 0
		while Time.get_ticks_msec()<deadline and stable<3:
			await get_tree().process_frame
			if not root.visible or root.mode==Window.MODE_MINIMIZED or not root.can_draw(): break
			# Complete the existing LOCAL child, then allow its ready signal to
			# publish into REGION and the root on subsequent process/draw cycles.
			RenderingServer.force_draw(false)
			stable = 0 if _pending() else stable+1
		if stable<3:
			result["error"]="map_not_drawn_or_window_unavailable"
		else:
			var readback := Time.get_ticks_usec()
			var image := root.get_texture().get_image()
			result["readback_us"]=Time.get_ticks_usec()-readback
			if image==null or image.is_empty(): result["error"]="empty_root_image"
			else:
				var stem := Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_usec())
				var folder := ProjectSettings.globalize_path(OUTPUT)
				var error := DirAccess.make_dir_recursive_absolute(folder)
				var png := folder.path_join(stem+".png")
				var json := folder.path_join(stem+".json")
				var report := _observation_state()
				report["label"]=label
				report["viewport_pixels"]=[image.get_width(),image.get_height()]
				var write_began := Time.get_ticks_usec()
				if error==OK: error=image.save_png(png)
				result["png_write_us"]=Time.get_ticks_usec()-write_began
				result["image_bytes"]=image.get_data_size()
				result["capture_us"]=Time.get_ticks_usec()-began
				report["capture"]={"readback_us":result.readback_us,"png_write_us":result.png_write_us,"elapsed_us":result.capture_us,"image_bytes":result.image_bytes}
				if error==OK:
					var file := FileAccess.open(json,FileAccess.WRITE)
					if file==null: error=FileAccess.get_open_error()
					else:
						file.store_string(JSON.stringify(report,"\t"))
						file.close()
				result.merge({"ok":error==OK,"error":error_string(error),"png":png,"json":json,"metadata":report},true)
	result["elapsed_us"]=Time.get_ticks_usec()-began
	busy = false
	last_result = result
	completed.emit(result)
	print("WWO_SCREENSHOT ",JSON.stringify(result))
	return result

func _logistics_metadata() -> Dictionary:
	var value: Dictionary=renderer._logistics_observation.duplicate()
	var rails: Array[Dictionary]=[]
	for rail: Dictionary in value.get("railways",[]):
		rails.append({"id":rail.id,"vertices":(rail.coordinates as Array).size(),"source_id":rail.source_id,"geometry_status":rail.get("geometry_status",""),"flow_directions":rail.get("flow_directions",[])})
	value["railways"]=rails
	value["flow_paths"]=renderer._topic_flow.paths.size() if is_instance_valid(renderer._topic_flow) else 0
	return value

func metadata() -> Dictionary:
	var controller := renderer.controller
	var camera := controller.region_camera
	var view := renderer.region_view
	var center := renderer.unit_at(renderer.size*.5)
	var ll := RegionProjection.lon_lat(center) if not center.is_zero_approx() else Vector2(INF,INF)
	var q := controller.orientation().get_rotation_quaternion()
	var local_camera := view._landmark_camera
	return {"schema_id":"wwo_native_screenshot_v1","captured_at":Time.get_datetime_string_from_system(),"timezone":Time.get_time_zone_from_system(),"project":Catalog.project_version(false),"return_flow":renderer.observation_return.duplicate(),"resources":_resource_inventory() if _observe_resources else {},"observation":{"file_control_enabled":not _observe_file.is_empty(),"window_unfocusable":get_window().unfocusable,"window_position":[get_window().position.x,get_window().position.y],"input_source":"engine_viewport" if not _observe_file.is_empty() else "native_window"},
		"map_mode":controller.map_mode,"camera":{"mode":"LOCAL" if camera.local_active else "REGION" if camera.active else "WORLD","center_lon_lat":[ll.x,ll.y] if ll.is_finite() else [],"world_orientation_quaternion":[q.x,q.y,q.z,q.w],"world_zoom":controller.zoom,"chart_basis":[TerrainPixelSource.serial(camera.tangent_frame.x),TerrainPixelSource.serial(camera.tangent_frame.y),TerrainPixelSource.serial(camera.tangent_frame.z)],"origin_pixels":[camera.origin.x,camera.origin.y],"metres_per_pixel":renderer._strategic_mpp(),"bearing_radians":camera.bearing,"elevation_radians":view.elevation_at(camera),"local_place_id":camera.local_place_id,"native_position":TerrainPixelSource.serial(local_camera.position) if local_camera!=null else [],"native_rotation":TerrainPixelSource.serial(local_camera.rotation) if local_camera!=null else [],"view_only":true},
		"window":{"visible":get_tree().root.visible,"mode":get_tree().root.mode,"focused":get_tree().root.has_focus(),"visibility_source":"Godot Window properties; no OS focus verification"},"display":{"surface_path":view._local_surface_key,"surface_presented":view._surface_presented_key,"local_rect":[view._local_render_rect.position.x,view._local_render_rect.position.y,view._local_render_rect.size.x,view._local_render_rect.size.y],"relief_textures":renderer.relief.textures.keys(),"pending":_pending()},
		"logistics":_logistics_metadata(),
		"city_layers":view.city_states(),
		"city":{"water":view.city.water_state(),"profile":view.city.profile.get("id",""),"grade":view.city.profile.get("scale_grade",0),"instances":view.city.instances,"active_nodes":view.city.nodes.size(),"layout_builds":view.city.build_count,"cached_layouts":view.city.cached.size(),"cached_meshes":view.city._mesh_cache.size(),"pending_meshes":view.city._pending_meshes.size(),"safe_rect":TerrainPixelSource.serial(renderer._city_safe_rect()),"content_bounds":TerrainPixelSource.serial(view.city.bounds),"width_fraction":view.city.bounds.size.x/maxf(1,renderer._city_safe_rect().size.x)},
		"render":{"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"local_draw_calls":view._local_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if view._local_viewport!=null else 0},
		"memory":{"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}}
