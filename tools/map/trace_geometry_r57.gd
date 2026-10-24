extends SceneTree
## One actual medium package, cancellation result and staged publication.
## No world application, simulation, saves, camera controls, or benchmark.

func _init() -> void:
	call_deferred("_trace")

func _trace() -> void:
	var loader := StrategicSpatialLoader.new()
	loader.request(Vector2(24.5,35.3),100.0,"1900-01-01",75.0,false)
	var deadline := Time.get_ticks_msec()+30000
	while loader.preparing() and Time.get_ticks_msec()<deadline:
		loader.poll()
		await create_timer(.01).timeout
	if loader.content==null or not loader.errors.is_empty(): push_error(str(loader.errors)); loader.release(); quit(1); return
	var requested := loader.physical_demand("medium")
	var layer := LocalSpatialLayer.new()
	var canvas := RenderingServer.canvas_item_create()
	layer.begin(loader.content,canvas,75.0)
	var before := layer.diagnostic_state()
	while layer.preparing and Time.get_ticks_msec()<deadline:
		layer.prepare_step(ThemeDB.fallback_font)
		await create_timer(.01).timeout
	var uploaded := layer.diagnostic_state()
	var complete := layer.can_present_physical(requested,75.0)
	var controller := GlobeController.new()
	var camera := controller.region_camera
	camera.active=true; camera.km_per_pixel=.075; camera.tangent_frame=RegionProjection.frame(Vector2(24.5,35.3)); camera.origin=Vector2(640,360)
	layer.update(camera,controller,"1900-01-01",Vector2(1280,720),true,{"install_physical":true,"display_lod":"medium"})
	var published := layer.diagnostic_state()
	var cancelled := LocalSpatialLod.prepare(loader.content,["medium"],func() -> bool: return false)
	var file := FileAccess.open("res://local-artifacts/terrain-r57/geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"headless finite resource read/CPU preparation/dummy-server installation, not gameplay or real GPU timing","requested":requested,"before":before,"uploaded":uploaded,"can_present_complete":complete,"published":published,"cancelled_result":cancelled},"\t"));file.close()
	layer.dispose();loader.release();controller.free();RenderingServer.free_rid(canvas)
	print("R57 medium publication ",complete," IDs=",requested)
	await _paris()
	quit(0 if complete and published.published_lod=="medium" else 1)

func _paris() -> void:
	var loader := LocalSpatialLoader.new()
	loader.request(Vector2(2.3522,48.8566))
	var deadline := Time.get_ticks_msec()+30000
	while loader.preparing() and Time.get_ticks_msec()<deadline:
		loader.poll()
		await create_timer(.01).timeout
	if loader.content==null:
		push_error("Paris local content unavailable")
		loader.release()
		return
	var layer := LocalSpatialLayer.new()
	var canvas := RenderingServer.canvas_item_create()
	layer.begin(loader.content,canvas,1000.0)
	# Same input path used by scale changes, including a superseded CPU job.
	layer.request_lods(75.0)
	var states: Array = [layer.diagnostic_state()]
	for mpp: float in [75.0,1000.0,75.0]:
		layer.request_lods(mpp)
		while layer.preparing and Time.get_ticks_msec()<deadline:
			layer.prepare_step(ThemeDB.fallback_font)
			await create_timer(.01).timeout
		states.append(layer.diagnostic_state())
	var file := FileAccess.open("res://local-artifacts/terrain-r57/geometry_paris.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":LocalSpatialLoader.PARIS_PATH,"game_scene_run":false,"states":states},"\t"));file.close()
	print("R57 Paris finite LOD states ",states)
	layer.dispose();loader.release();RenderingServer.free_rid(canvas)
