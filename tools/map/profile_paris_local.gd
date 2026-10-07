extends SceneTree
## Native frame sampling of the production renderer; no simulation advances.

var results: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _samples(app: FormalWorldApplication, action: String) -> Dictionary:
	var samples: Array[int] = []
	var renderer := app.map_renderer
	var camera := app.map_controller.region_camera
	for index: int in range(180):
		var started := Time.get_ticks_usec()
		if action == "pan":
			camera.pan(Vector2(2.0 if index % 60 < 30 else -2.0, 0.0), renderer.size)
			app.map_controller.view_changed.emit()
		elif action == "zoom":
			camera.zoom_at(renderer.size * 0.5, 0.997 if index % 60 < 30 else 1.0 / 0.997, renderer.size)
			app.map_controller.view_changed.emit()
		await process_frame
		samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	return {"p50_usec": samples[90], "p95_usec": samples[171], "max_usec": samples[179], "frames": samples.size()}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	var camera := app.map_controller.region_camera
	var pixel := renderer.size * 0.5
	var unit := GlobeProjection.lon_lat_to_unit(Vector2(2.3522, 48.8566))
	camera.enter(unit, pixel, 0.24, 0.0, renderer.size)
	app.map_controller.view_changed.emit()
	renderer.set("_last_pointer", pixel)
	renderer._ensure_view()
	var preparation_frames: Array[int] = []
	for index: int in range(120):
		var started := Time.get_ticks_usec()
		await process_frame
		preparation_frames.append(Time.get_ticks_usec() - started)
	preparation_frames.sort()
	results["prewarm_frames"] = {"frames": preparation_frames.size(), "p95_usec": preparation_frames[114], "max_usec": preparation_frames[119], "over_100ms": preparation_frames.filter(func(value: int) -> bool: return value >= 100000).size()}
	camera.zoom_at(pixel, 0.75, renderer.size)
	app.map_controller.view_changed.emit()
	renderer._evaluate_scale()
	for index: int in range(180):
		await process_frame
	results["local_active"] = camera.local_active
	results["transition"] = renderer.local_transition_metrics
	for action: String in ["idle", "pan", "zoom"]:
		results[action] = await _samples(app, action)
	if "--after" in OS.get_cmdline_user_args():
		camera.zoom_at(pixel, 0.14, renderer.size)
		app.map_controller.view_changed.emit()
		await process_frame
		results["close_meters_per_pixel"] = camera.km_per_pixel * 1000.0
		results["close_pan"] = await _samples(app, "pan")
		results["close_zoom"] = await _samples(app, "zoom")
		results["load"] = renderer.local_layer.metrics
	var suffix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	var output := FileAccess.open("res://local-artifacts/paris-local-r1/performance-" + suffix + ".json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "  "))
	print("Paris native profile: ", JSON.stringify(results))
	app.queue_free()
	await process_frame
	quit(0)
