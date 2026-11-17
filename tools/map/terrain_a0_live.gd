extends RefCounted
# Finite real-map comparison through the existing no-focus native launcher.
class A0Relief extends MapRelief:
	var a0_decode: Callable
	func _start_decode() -> void:
		# Menu/world wiring resets decode_asset. Keep the existing worker/cache
		# implementation, restoring the same comparison callable at dispatch.
		decode_asset = a0_decode
		super._start_decode()

var driver: Node
var renderer: Control
var controller: Object
var mode: String
var manifest_path: String
var samples: Dictionary = {}
var by_path: Dictionary = {}
var calls: Array[Dictionary] = []
var calls_mutex := Mutex.new()
var installed: Array[Dictionary] = []
var began_usec: int = 0
var phase: String = "startup"
var checked: Dictionary = {}

func configure() -> bool:
	began_usec = Time.get_ticks_usec()
	mode = OS.get_environment("WWO_TERRAIN_A0")
	manifest_path = OS.get_environment("WWO_TERRAIN_A0_MANIFEST")
	if mode in ["production-legacy","production-compact"]: return true
	if mode not in ["original","flat_webp"] or manifest_path.is_empty(): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary: return false
	var document := parsed as Dictionary
	if int(document.get("schema",0))!=1 or not document.get("files") is Array: return false
	for row: Dictionary in document.files:
		var asset := row.asset as Dictionary
		by_path[str(asset.path)] = row
		by_path["res://"+str(row.candidate_path).trim_prefix("res://")] = row
		samples[str(asset.id).get_slice(":",1)] = row
	return not by_path.is_empty()

func install(node: Node) -> void:
	if not node is GlobeRenderer: return
	var relief: MapRelief = node.get("relief")
	if not relief is A0Relief:
		assert(relief._thread==null and relief._assets.is_empty() and relief.textures.is_empty(),"A0 must attach before first request")
		relief = A0Relief.new()
		node.set("relief",relief)
	(relief as A0Relief).a0_decode = decode
	relief.decode_asset = decode
	installed.append({"renderer":node.get_instance_id(),"at_us":Time.get_ticks_usec()-began_usec,"before_ready":not node.is_node_ready()})

func selected(asset: Dictionary) -> Dictionary:
	var result := asset.duplicate()
	var row := by_path.get(str(asset.get("path","")),{}) as Dictionary
	if mode=="flat_webp" and not row.is_empty():
		result["format"] = row.chosen_format
		result["path"] = "res://"+str(row.candidate_path).trim_prefix("res://")
		result["bytes"] = int(row.chosen_bytes)
	return result

func decode(level: String, admitted: Dictionary) -> Dictionary:
	var began := Time.get_ticks_usec()
	var request := admitted
	var asset: Dictionary = {}
	if admitted.has(level):
		asset = selected(admitted[level] as Dictionary)
		# Copy only the immutable record being decoded, never the world catalogue.
		request = {level:asset}
	var result: Dictionary
	var read_us: int = -1
	var decode_us: int = -1
	var decoded_bytes := 0
	var storage := ""
	if mode in ["production-legacy","production-compact"]:
		result = GeographyLoader.decode_relief(level,request,Callable(),true)
		read_us = int(result.get("read_us",-1))
		decode_us = int(result.get("decode_us",-1))
		if result.has("image"): decoded_bytes = (result.image as Image).get_data_size()
		storage = str(result.get("storage","legacy"))
	elif not asset.is_empty():
		var stamp := Time.get_ticks_usec()
		var buffer := FileAccess.get_file_as_bytes(str(asset.path))
		read_us = Time.get_ticks_usec()-stamp
		stamp = Time.get_ticks_usec()
		result = GeographyLoader.decode_relief_buffer(buffer,asset)
		decode_us = Time.get_ticks_usec()-stamp
	else:
		result = GeographyLoader.decode_relief(level,request)
	if result.has("assets"):
		var values := (result.assets as Dictionary).duplicate()
		for id: String in values: values[id] = selected(values[id] as Dictionary)
		result["assets"] = values
	calls_mutex.lock()
	calls.append({"id":level,"phase":phase,"began_us":began-began_usec,"us":Time.get_ticks_usec()-began,"read_us":read_us,"decode_us":decode_us,"image":result.has("image"),"path":asset.get("path",""),"format":asset.get("format",""),"bytes":asset.get("bytes",0),"decoded_bytes":decoded_bytes,"storage":storage,"width":asset.get("width",0),"source_lod_degrees":asset.get("surface_lod_degrees",2 if asset.get("surface_role","")=="detail" else 0),"errors":result.get("errors",[])})
	calls_mutex.unlock()
	return result

func state() -> Dictionary:
	var relief: MapRelief = renderer.get("relief")
	var residents: Array[Dictionary] = []
	for id: String in relief.textures:
		var asset := relief._assets.get(id,{}) as Dictionary
		var row := by_path.get(str(asset.get("path","")),samples.get(id,{})) as Dictionary
		residents.append({"id":id,"instance":(relief.textures[id] as Texture2D).get_instance_id(),"path":asset.get("path",""),"width":(relief.textures[id] as Texture2D).get_width(),"source_lod_degrees":asset.get("surface_lod_degrees",2 if asset.get("surface_role","")=="detail" else 0),"role":asset.get("surface_role",""),"format":asset.get("format",""),"source_bytes":row.get("source_bytes",0),"chosen_bytes":row.get("chosen_bytes",0)})
	var queued := 0
	for id: String in relief._wanted:
		if not relief.textures.has(id) and not relief._attempted.has(id): queued += 1
	return {"queued_images":queued,"decode_active":relief._thread!=null,"center_lon_lat":TerrainPixelSource.serial(RegionProjection.lon_lat(controller.region_camera.unit_at(renderer.size*.5))),"mpp":controller.region_camera.km_per_pixel*1000.0,"regional":controller.region_camera.active,"local":controller.region_camera.local_active,"resident":residents,"wanted":relief._wanted.duplicate(),"active":relief._surface_active.duplicate(),"pending":renderer.call("_has_pending_preparation"),"relief_preparing":relief.preparing(),"decode_level":relief._level if relief.preparing() else "","texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"errors":relief.errors.duplicate()}

func mark(label: String) -> void:
	calls_mutex.lock()
	phase = label
	calls_mutex.unlock()
	driver.call("acceptance_save","phase",{"phase":label,"mode":mode,"unix_ms":Time.get_unix_time_from_system()*1000.0})

func settle() -> Dictionary:
	var start := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec()+45000
	var quiet := 0
	while Time.get_ticks_msec()<deadline:
		await driver.get_tree().process_frame
		if not renderer.call("_has_pending_preparation") and not controller.call("camera_motion_active"):
			quiet += 1
		else: quiet = 0
		if quiet>=8: break
	return {"us":Time.get_ticks_usec()-start,"quiet_frames":quiet,"state":state()}

func sample(drag: bool, wheel: bool = false, hot_wheel: bool = false, local_zoom_band: bool = false) -> Dictionary:
	await driver.get_tree().process_frame
	var before := state()
	calls_mutex.lock()
	var decode_before := calls.size()
	calls_mutex.unlock()
	var begin := Time.get_unix_time_from_system()*1000.0
	var previous := Time.get_ticks_usec()
	var intervals: Array[int] = []
	var position := renderer.size*.5
	var pending_frames := 0
	var transitions: Array[Dictionary] = []
	var previous_demand: Array = []
	var press_us:=0
	var input_times: Array[int]=[]
	var long_intervals: Array[Dictionary]=[]
	var minimum_mpp:=float(before.mpp)
	var maximum_mpp:=float(before.mpp)
	var closer_in_band:=true
	if drag:
		var press := InputEventMouseButton.new()
		press.position=position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
		var press_begin:=Time.get_ticks_usec()
		renderer.call("_gui_input",press)
		press_us=Time.get_ticks_usec()-press_begin
	for i: int in range(120):
		var input_begin:=Time.get_ticks_usec()
		if drag:
			# Cross a real 2-degree seam and return, rather than jitter one pixel.
			var delta := Vector2(4.0 if i<60 else -4.0,0)
			var motion := InputEventMouseMotion.new()
			position+=delta;motion.position=position;motion.relative=delta;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
			renderer.call("_gui_input",motion)
		if wheel and i%6==0 or hot_wheel and i%12==0:
			var event := InputEventMouseButton.new()
			var closer := i%24==0 if hot_wheel else i<60
			if local_zoom_band:
				var band_mpp: float=controller.region_camera.km_per_pixel*1000.0
				if band_mpp<8.5:closer_in_band=false
				elif band_mpp>11.5:closer_in_band=true
				closer=closer_in_band
			event.position=renderer.size*.5;event.button_index=MOUSE_BUTTON_WHEEL_UP if closer else MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true
			renderer.call("_gui_input",event)
		input_times.append(Time.get_ticks_usec()-input_begin)
		await driver.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var actual_mpp: float=controller.region_camera.km_per_pixel*1000.0
		minimum_mpp=minf(minimum_mpp,actual_mpp);maximum_mpp=maxf(maximum_mpp,actual_mpp)
		if now-previous>80000 and long_intervals.size()<32:long_intervals.append({"frame":i,"us":now-previous,"input_us":input_times[-1],"unix_ms":Time.get_unix_time_from_system()*1000.0})
		intervals.append(now-previous);previous=now
		if renderer.call("_has_pending_preparation"): pending_frames += 1
		var relief: MapRelief = renderer.get("relief")
		var demand: Array = [relief._wanted,relief._surface_active,relief.textures.keys()]
		if demand!=previous_demand:
			transitions.append({"frame":i,"state":state()})
			previous_demand=demand.duplicate(true)
	if drag:
		var release := InputEventMouseButton.new()
		release.position=position;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
		renderer.call("_gui_input",release)
	intervals.sort()
	input_times.sort()
	calls_mutex.lock()
	var new_decodes := calls.size()-decode_before
	calls_mutex.unlock()
	return {"begin":before,"new_decodes":new_decodes,"unix_begin_ms":begin,"unix_end_ms":Time.get_unix_time_from_system()*1000.0,"mpp_min":minimum_mpp,"mpp_max":maximum_mpp,"p95_us":intervals[113],"max_us":intervals[-1],"press_us":press_us,"input_p95_us":input_times[113],"input_max_us":input_times[-1],"long_intervals":long_intervals,"long33":intervals.filter(func(x: int)->bool:return x>33000).size(),"pending_frames":pending_frames,"transitions":transitions,"end":state()}

func gpu_samples() -> Array[Dictionary]:
	# At most two representative readbacks, always outside timed phases.
	var result: Array[Dictionary] = []
	var relief: MapRelief = renderer.get("relief")
	for id: String in relief.textures:
		if checked.size()>=2: break
		if checked.has(id): continue
		var original_asset: Dictionary
		if mode in ["production-legacy","production-compact"]:
			original_asset = (relief._assets[id] as Dictionary).duplicate()
			var name := str(original_asset.path).get_file().get_basename()+".wcm"
			if not FileAccess.file_exists("res://assets/maps/compact/relief/"+name): continue
		else:
			if not samples.has(id): continue
			var row := samples[id] as Dictionary
			if str(row.chosen_format)!="RGBA8_MIP_FRA0": continue
			original_asset = (row.asset as Dictionary).duplicate()
		checked[id]=true
		var gpu := (relief.textures[id] as ImageTexture).get_image()
		var source_root := OS.get_environment("WWO_TERRAIN_A0_SOURCE_ROOT")
		if not source_root.is_empty(): original_asset["path"] = source_root.path_join(str(original_asset.path).trim_prefix("res://"))
		var original := GeographyLoader.decode_relief(id,{id:original_asset})
		if not original.has("image"):
			result.append({"id":id,"error":original.get("errors",[])});continue
		var reference := original.image as Image
		var bytes := int(original_asset.width)*int(original_asset.height)*4
		result.append({"id":id,"top_equal":gpu.get_data().slice(0,bytes)==reference.get_data().slice(0,bytes),"full_mips_equal":gpu.get_data()==reference.get_data(),"mips":gpu.get_mipmap_count(),"format":gpu.get_format()})
	return result

func run(owner: Node, host: Object, authority: Dictionary, save_path: String, save_before: PackedByteArray) -> void:
	driver=owner;renderer=driver.get("renderer");controller=driver.get("controller")
	if OS.get_environment("WWO_LOCAL_CONTINUITY_REVIEW")=="1":
		await continuity_run(host,authority,save_path,save_before)
		return
	var report: Dictionary = {"mode":mode,"main_pack":OS.get_environment("WWO_VISUAL_MAIN_PACK"),"user_dir":OS.get_user_data_dir(),"manifest":manifest_path,"hook_installations":installed,"cases":[],"gpu_readback":[],"cold_start":"Fresh process and empty runtime texture cache; OS file cache is not flushed or claimed cold."}
	driver.call("acceptance_image","a0-world-political")
	controller.call("set_map_mode","geographic")
	mark("world/first_install")
	report["startup"] = {"elapsed_from_boot_us":Time.get_ticks_usec()-began_usec,"settle":await settle()}
	for point: Array in [["plain",2.01,46.8],["alps",8.01,46.8],["sahara",10.01,25.0]]:
		for km_per_pixel: float in [.075,.35,1.2,2.5]:
			var label := "%s/%dmpp" % [point[0],roundi(km_per_pixel*1000)]
			mark(label+"/entry")
			controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(point[1],point[2])),renderer.size*.5,km_per_pixel,0.0,renderer.size)
			var row: Dictionary = {"label":label,"load":await settle()}
			mark(label+"/drag")
			row["drag"] = await sample(true)
			row["settle_after_drag"] = await settle()
			if km_per_pixel==.35:
				mark(label+"/continuous_wheel")
				row["wheel"] = await sample(false,true)
				row["settle_after_wheel"] = await settle()
			(report.cases as Array).append(row)
			driver.call("acceptance_save","observations",report)
			if km_per_pixel==1.2:
				mark(str(point[0])+"/readback_outside_timing")
				(report.gpu_readback as Array).append_array(gpu_samples())
				driver.call("acceptance_image","a0-"+str(point[0])+"-region")
	mark("plain/hot_same_lod_entry")
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(1.0,46.8)),renderer.size*.5,.075,0.0,renderer.size)
	report["hot_entry"] = await settle()
	mark("plain/hot_same_lod_wheel")
	report["hot_wheel"] = await sample(false,false,true)
	report["hot_wheel_settle"] = await settle()
	mark("world/retire")
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)))
	controller.call("set_world_zoom",.86)
	report["far"] = await settle()
	mark("plain/reenter")
	controller.call("focus_region",GlobeProjection.lon_lat_to_unit(Vector2(1.99,46.8)),renderer.size*.5,.075,0.0,renderer.size)
	report["reenter"] = {"load":await settle(),"drag":await sample(true)}
	mark("zermatt/legacy_local")
	var unit := GlobeProjection.lon_lat_to_unit(Vector2(7.7063088,46.0079880))
	controller.call("focus_region",unit,renderer.size*.5,.002,0.0,renderer.size)
	controller.call("enter_local",unit,renderer.size*.5,renderer.size,"geographic_region:zermatt_west_reference",2.0)
	renderer.get("region_view").call("set_inspection_elevation",55.0)
	controller.view_changed.emit()
	var local: Dictionary = {"load":await settle(),"idle":await sample(false)}
	var surface := renderer.get("region_view").get("_surface_reference") as Dictionary
	var context := (surface.get("presentation",{}) as Dictionary).get("context_height_asset",{}) as Dictionary
	local["context_asset"] = context
	var legacy_path := "res://assets/maps/relief/france_r42_46_+6.bin"
	var legacy := FileAccess.open(legacy_path,FileAccess.READ)
	local["original_header"] = legacy.get_buffer(5).get_string_from_ascii() if legacy!=null else "missing"
	local["mesh_installed"] = renderer.get("region_view").get("_local_surface_mesh")!=null
	local["original_path_and_format"] = context.get("path","")==legacy_path and context.get("format","")=="RGBA8_MIP_DEFLATE" and local.original_header=="FRT42"
	report["local"] = local
	driver.call("acceptance_image","a0-zermatt-local")
	mark("world/final_retire")
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)))
	controller.call("set_world_zoom",.86)
	report["final_far"] = await settle()
	calls_mutex.lock()
	report["decodes"] = calls.duplicate(true)
	calls_mutex.unlock()
	report["save_input_present"] = not save_path.is_empty()
	report["save_unchanged"] = save_path.is_empty() or save_before==FileAccess.get_file_as_bytes(save_path)
	report["authority_unchanged"] = authority==driver.call("economic_authority_state",host)
	report["paused"] = host.get("time_control").get("paused")
	var settles: Array = [report.startup.settle,report.hot_entry,report.hot_wheel_settle,report.far,report.reenter.load,local.load,report.final_far]
	var states: Array = []
	for row: Dictionary in report.cases:
		settles.append(row.load);settles.append(row.settle_after_drag)
		if row.has("settle_after_wheel"): settles.append(row.settle_after_wheel)
		for key: String in ["drag","wheel"]:
			if not row.has(key): continue
			states.append(row[key].begin);states.append(row[key].end)
			for change: Dictionary in row[key].transitions: states.append(change.state)
	var settled_ok := true
	for result: Dictionary in settles:
		states.append(result.state)
		settled_ok = settled_ok and not bool(result.state.pending) and (result.state.errors as Array).is_empty()
	var resident_lods: Dictionary = {}
	var active_lods: Dictionary = {}
	for snapshot: Dictionary in states:
		for resident: Dictionary in snapshot.resident:
			var lod := str(roundi(float(resident.source_lod_degrees))) if resident.role=="detail" else "base"
			if not resident_lods.has(lod): resident_lods[lod]={}
			resident_lods[lod][str(resident.id)] = true
			if (snapshot.active as Array).has(resident.id):
				if not active_lods.has(lod): active_lods[lod]={}
				active_lods[lod][str(resident.id)] = true
	report["resident_lod_ids"] = resident_lods
	report["active_lod_ids"] = active_lods
	report["settled_without_pending_errors"] = settled_ok
	report["lod_page_coverage_verified"] = active_lods.has("2") and active_lods.has("8") and active_lods.has("16")
	driver.call("acceptance_save","observations",report)
	var ok := settled_ok and bool(report.lod_page_coverage_verified) and not (report.gpu_readback as Array).is_empty() and bool(local.original_path_and_format) and bool(local.mesh_installed) and bool(report.authority_unchanged) and bool(report.save_unchanged) and bool(report.paused)
	for row: Dictionary in report.gpu_readback: ok = ok and bool(row.get("top_equal",false)) and bool(row.get("full_mips_equal",false))
	print("A0_LIVE_DONE ",mode," ok=",ok)
	driver.get_tree().quit(0 if ok else 5)

func continuity_local_state() -> Dictionary:
	# Extend the existing requested LOCAL observation; no alternate renderer.
	var view:=renderer.get("region_view") as RegionView
	var result: Dictionary={"installed":view._local_surface!=null,"source_key":view._local_surface_key,"presented_key":view._surface_presented_key,"generation":view._surface_generation,"pending_worker":view._surface_thread!=null,"vertices":view._surface_ray_vertices.size(),"indices":view._surface_indices.size(),"height_samples":view._surface_display_heights.size(),"static_bytes":OS.get_static_memory_usage(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"render_target":str(view._local_render_rect),"texture_cache_count":(renderer.get("relief") as MapRelief).textures.size()}
	if view._surface_reference.is_empty():return result
	result["pick_chunks"]=view._surface_pick_chunks.size()
	var options:=view._surface_reference.get("presentation",{}) as Dictionary
	result["context_source"]=options.get("context_height_asset",{})
	result["strength"]=view._surface_strength(controller.region_camera)
	result["height_bounds"]=TerrainPixelSource.serial(view._surface_height_bounds)
	result["height_texture_bytes"]=view._surface_height_size.x*view._surface_height_size.y*4
	result["water_mask_bytes"]=262144 if view._surface_context_water_mask!=null else 0
	result["geometry_cpu_array_bytes"]=view._surface_ray_vertices.size()*12+view._surface_indices.size()*4+view._surface_vertices.size()*12+view._surface_display_heights.size()*4
	result["triangles"]=view._surface_indices.size()/3
	if view._local_surface_mesh!=null and view._local_surface_mesh.get_surface_count()>0:
		var arrays:=view._local_surface_mesh.surface_get_arrays(0)
		var normals:=arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var bounds:=view._local_surface_mesh.get_aabb()
		result["mesh_bounds_m"]={"position":TerrainPixelSource.serial(bounds.position),"size":TerrainPixelSource.serial(bounds.size)}
		var upward:=0;var min_y:=1.0;var max_y:=-1.0
		for normal: Vector3 in normals:
			min_y=minf(min_y,normal.y);max_y=maxf(max_y,normal.y)
			if normal.y>0.0:upward+=1
		result["normals"]={"count":normals.size(),"upward":upward,"min_y":min_y,"max_y":max_y}
	if view._surface_material!=null:
		result["material"]={"relief_weight":view._surface_material.get_shader_parameter("cartographic_relief_weight"),"ink_weight":view._surface_material.get_shader_parameter("map_ink_weight"),"context":view._surface_material.get_shader_parameter("context_terrain")}
	return result

func continuity_run(host: Object, authority: Dictionary, save_path: String, save_before: PackedByteArray) -> void:
	# Seven user-requested fixed cameras. Reuse the ordinary formal world,
	# native capture, preparation wait and finite frame-cost observation.
	var report: Dictionary={"scope":"NATIVE_FIXED_CAMERA_LOCAL_CONTINUITY_NOT_PLAYER_ACCEPTANCE","cases":[]}
	var shots: Array=[
		["world",2.3522,48.8566,0.0,"",-1.0],
		["region-alps",7.85,46.20,75.0,"",-1.0],
		["region-london",-.30,51.50,75.0,"",-1.0],
		["zermatt-near",7.703304,46.010743,2.0,"geographic_region:zermatt_west_reference",55.0],
		["zermatt-valley",7.716,46.010743,8.0,"geographic_region:zermatt_west_reference",55.0],
		["london-near",-.1246,51.5007,4.0,"place:london",55.0],
		["london-area",-.12,51.51,8.0,"place:london",55.0],
		["zermatt-12",7.716,46.010743,12.0,"geographic_region:zermatt_west_reference",55.0],
		["zermatt-24",7.716,46.010743,24.0,"geographic_region:zermatt_west_reference",55.0],
		["london-12",-.12,51.51,12.0,"place:london",55.0]]
	var requested:=OS.get_environment("WWO_LOCAL_CONTINUITY_CASES").split(",",false)
	if not requested.is_empty():shots=shots.filter(func(shot:Array)->bool:return str(shot[0]) in requested)
	for shot: Array in shots:
		mark(str(shot[0]))
		controller.call("suspend_motion")
		controller.call("leave_local")
		var unit:=GlobeProjection.lon_lat_to_unit(Vector2(float(shot[1]),float(shot[2])))
		controller.call("set_map_mode","political" if shot[0]=="world" else "geographic")
		if shot[0]=="world":
			controller.call("focus",unit);controller.call("set_world_zoom",.86)
		else:
			controller.call("focus_region",unit,renderer.size*.5,float(shot[3])*.001,0.0,renderer.size)
			if not str(shot[4]).is_empty():controller.call("enter_local",unit,renderer.size*.5,renderer.size,str(shot[4]),2.0)
		renderer.get("region_view").call("set_inspection_elevation",float(shot[5]))
		controller.view_changed.emit()
		var loaded:=await settle()
		await driver.get_tree().create_timer(.4).timeout
		var view:=renderer.get("region_view") as RegionView
		var before:=state()
		var row: Dictionary={"name":shot[0],"requested_lon_lat":[shot[1],shot[2]],"requested_mpp":shot[3],"bearing":0,"elevation":shot[5],"load":loaded,"state":before,"native_vertices":view._surface_vertices.size(),"render_vertices":view._surface_ray_vertices.size(),"render_target":str(view._local_render_rect),"static_memory":OS.get_static_memory_usage(),"local_detail":continuity_local_state()}
		row["terrain_installed"]=str(shot[4]).is_empty() or (bool(row.local_detail.installed) and row.local_detail.source_key==row.local_detail.presented_key and str(row.local_detail.source_key).contains("london" if str(shot[4])=="place:london" else "zermatt") and bool(before.local))
		driver.call("acceptance_image",str(shot[0]))
		row["idle"]=await sample(false)
		if not str(shot[4]).is_empty():
			row["pan"]=await sample(true)
			row["pan_settle"]=await settle()
			if shot[0] in ["zermatt-12","zermatt-24","london-12"]:
				row["wheel"]=await sample(false,true,false,str(shot[0]).ends_with("-12"))
				row["wheel_settle"]=await settle()
				row["after_motion"]=continuity_local_state()
		(report.cases as Array).append(row)
		driver.call("acceptance_save","continuity",report)
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)))
	controller.call("set_world_zoom",.86)
	report["retire"]=await settle()
	report["retired_local"]=continuity_local_state()
	var reentry_unit:=GlobeProjection.lon_lat_to_unit(Vector2(7.716,46.010743))
	controller.call("focus_region",reentry_unit,renderer.size*.5,0.008,0.0,renderer.size)
	controller.call("enter_local",reentry_unit,renderer.size*.5,renderer.size,"geographic_region:zermatt_west_reference",2.0)
	renderer.get("region_view").call("set_inspection_elevation",55.0)
	controller.view_changed.emit()
	mark("zermatt/reentry")
	report["reentry"]=await settle()
	report["reentry_local"]=continuity_local_state()
	controller.call("focus",GlobeProjection.lon_lat_to_unit(Vector2(2.3522,48.8566)))
	controller.call("set_world_zoom",.86)
	mark("world/final_retire")
	report["final_retire"]=await settle()
	report["final_retired_local"]=continuity_local_state()
	report["authority_unchanged"]=authority==driver.call("economic_authority_state",host)
	report["save_unchanged"]=save_path.is_empty() or save_before==FileAccess.get_file_as_bytes(save_path)
	report["paused"]=host.get("time_control").get("paused")
	var ok:=bool(report.authority_unchanged) and bool(report.save_unchanged) and bool(report.paused)
	for row: Dictionary in report.cases:ok=ok and bool(row.terrain_installed) and not bool(row.load.state.pending) and (row.load.state.errors as Array).is_empty()
	driver.call("acceptance_save","continuity",report)
	print("LOCAL_CONTINUITY_NATIVE_DONE ok=",ok)
	driver.get_tree().quit(0 if ok else 5)
