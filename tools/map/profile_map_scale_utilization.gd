extends SceneTree
## Native frame intervals and engine memory counters; no simulation advances.
const OUT: String = "res://local-artifacts/map-scale-utilization-r1/"
var results: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _samples(app: FormalWorldApplication, action: String) -> Dictionary:
	var samples: Array[int] = []
	for index: int in range(90):
		var started := Time.get_ticks_usec()
		var delta := Vector2(2.0 if index % 30 < 15 else -2.0, 0.0)
		var ratio := 0.996 if index % 30 < 15 else 1.0 / 0.996
		if app.map_controller.region_camera.active:
			if action == "pan":
				app.map_controller.region_camera.pan(delta, app.map_renderer.size)
			elif action == "zoom":
				app.map_controller.region_camera.zoom_at(app.map_renderer.size * 0.5, ratio, app.map_renderer.size)
		else:
			if action == "pan":
				app.map_controller._rotate_view(delta * 0.005)
			elif action == "zoom":
				app.map_controller.zoom *= ratio
		if action != "idle":
			app.map_controller.view_changed.emit()
		await process_frame
		samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	return {"p50_usec": samples[45], "p95_usec": samples[85], "max_usec": samples[89], "over_50ms": samples.filter(func(n: int) -> bool: return n >= 50000).size(), "frames": 90}

func _memory() -> Dictionary:
	return {"tracked_static_ram_bytes": OS.get_static_memory_usage(), "render_video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "render_texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), "render_buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var pixel := app.map_renderer.size * 0.5
	var unit := GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR)
	app.map_controller.focus(unit)
	for i: int in range(30):
		await process_frame
	results["world"] = {}
	for action: String in ["idle", "pan", "zoom"]:
		results.world[action] = await _samples(app, action)
	results["memory_before_shard"] = _memory()
	var camera := app.map_controller.region_camera
	for band: Dictionary in [{"name":"region_far","scale":4.0},{"name":"region_mid","scale":1.2},{"name":"region_near","scale":0.36},{"name":"local_far","scale":0.18},{"name":"local_close","scale":0.025}]:
		camera.enter(unit, pixel, float(band.scale), 0.0, app.map_renderer.size)
		app.map_controller.view_changed.emit()
		app.map_renderer.set("_last_pointer", pixel)
		app.map_renderer._ensure_view()
		app.map_renderer._evaluate_scale()
		for i: int in range(180):
			await process_frame
		results[str(band.name)] = {"local_active": camera.local_active}
		for action: String in ["idle", "pan", "zoom"]:
			results[str(band.name)][action] = await _samples(app, action)
	results["memory_after_shard"] = _memory()
	results["load"] = app.map_renderer.local_layer.metrics
	var suffix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	var file := FileAccess.open(OUT + "performance-" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	app.queue_free()
	await process_frame
	quit(0)
