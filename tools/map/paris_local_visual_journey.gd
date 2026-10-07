extends SceneTree
## Native viewport captures using the production scene and input handler.

const OUT: String = "res://local-artifacts/paris-local-r1/visual/"
var app: FormalWorldApplication
var journeys: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")

func _wheel(point: Vector2, up: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	app.map_renderer._gui_input(event)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	app = (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	var controller := app.map_controller
	var camera := controller.region_camera
	var pixel := Vector2(620.0, 265.0)
	var before := (app.get("_persistence") as FormalPersistence).snapshot()
	for fixture: Dictionary in [{"name":"paris", "id":"place:paris", "point":LocalSpatialLoader.ANCHOR}, {"name":"beijing", "id":"place:beijing", "point":Vector2(116.4074,39.9042)}, {"name":"new-york", "id":"place:new_york", "point":Vector2(-74.006,40.7128)}]:
		var unit := GlobeProjection.lon_lat_to_unit(fixture.point as Vector2)
		camera.enter(unit, pixel, 0.36, 0.0, renderer.size)
		controller.select("state:country_fra" if fixture.name=="paris" else "", str(fixture.id))
		controller.set_map_mode("political")
		controller.labels_enabled = true
		controller.view_changed.emit()
		renderer.set("_region_labels_dirty", true)
		renderer.set("_last_pointer", pixel)
		renderer._ensure_view()
		renderer._evaluate_scale()
		for i: int in range(100):
			await process_frame
		await _capture(str(fixture.name)+"-region")
		for i: int in range(3):
			await _wheel(pixel, true)
		var started := Time.get_ticks_usec()
		if fixture.name == "paris":
			while not camera.local_active and Time.get_ticks_usec()-started<15000000:
				await process_frame
		else:
			for i: int in range(4):
				await _wheel(pixel, true)
		for i: int in range(4):
			await process_frame
		await _capture(str(fixture.name)+"-local-attempt")
		journeys.append({"fixture":fixture.name, "local_active":camera.local_active,"meters_per_pixel":camera.km_per_pixel*1000.0,"loader_count":app.historical_content.local_spatial.load_count,"anchor_delta":renderer.screen_point(unit)-pixel})
		if fixture.name != "paris":
			continue
		for i: int in range(5):
			await _wheel(pixel, true)
		await _capture("paris-close")
		controller.set_map_mode("fulfillment")
		await process_frame
		await _capture("paris-economy")
		controller.set_map_mode("political")
		# Show the larger network and the northern coastal edge without reloading.
		camera.km_per_pixel = 0.18
		camera.origin = pixel
		camera.pan(Vector2(400.0, 300.0), renderer.size)
		controller.view_changed.emit()
		await process_frame
		await _capture("paris-network")
		var havre := GlobeProjection.lon_lat_to_unit(Vector2(0.10785,49.49346))
		camera.origin += renderer.size*0.5-camera.project(havre)
		camera.constrain(renderer.size)
		controller.view_changed.emit()
		await process_frame
		await _capture("channel-coast")
		camera.pan(Vector2(1000000.0, 1000000.0), renderer.size)
		controller.view_changed.emit()
		await process_frame
		await _capture("paris-boundary")
		for i: int in range(3):
			await _wheel(renderer.size*0.5, false)
		await _capture("paris-region-restored")
	journeys.append({"save_unchanged":before==(app.get("_persistence") as FormalPersistence).snapshot(),"schema":FormalPersistence.SCHEMA_ID,"load_metrics":renderer.local_layer.metrics})
	var output := FileAccess.open(OUT+"journey.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(journeys,"  "))
	app.queue_free()
	await process_frame
	quit(0)
