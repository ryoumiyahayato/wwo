extends SceneTree
## Native production scene and wheel-input journey; screenshots are not mockups.
const OUT: String = "res://local-artifacts/map-scale-utilization-r1/visual/"
var app: FormalWorldApplication
var records: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
	var renderer := app.map_renderer
	var camera := app.map_controller.region_camera
	var mpp := camera.km_per_pixel*1000.0 if camera.active else RegionProjection.world_scale(RegionProjection.world_unit(renderer.size*0.5,renderer.size*0.5,float(renderer.get("_radius")),app.map_controller.orientation()),app.map_controller.orientation(),float(renderer.get("_radius")))*1000.0
	records.append({"name":name,"mpp":mpp,"band":MapScaleStyle.band(mpp,camera.active,camera.local_active),"flag_weight":MapScaleStyle.flag_weight(mpp),"political_weight":MapScaleStyle.political_weight(mpp),"lod":renderer.local_layer.active_lod,"shard_places_visible":renderer.local_layer.visible_places.size(),"load_count":app.historical_content.local_spatial.load_count,"prepare_count":renderer.local_layer.prepare_count,"local_active":camera.local_active,"mode":app.map_controller.map_mode})

func _wheel(up: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = app.map_renderer.size*0.5
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	app.map_renderer._gui_input(event)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUT)
	app = (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var before := (app.get("_persistence") as FormalPersistence).snapshot()
	var renderer := app.map_renderer
	var camera := app.map_controller.region_camera
	var unit := GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR)
	var pixel := renderer.size*0.5
	app.map_controller.focus(unit)
	app.map_controller.zoom = 1.5
	app.map_controller.labels_enabled = true
	app.map_controller.select("state:country_fra","place:paris")
	app.map_controller.view_changed.emit()
	for i: int in range(20):
		await process_frame
	await _capture("01-world")
	# Reach the actual runtime handoff through its existing wheel handler.
	for i: int in range(10):
		await _wheel(true)
		if camera.active:
			break
	while not renderer.region_view.ready:
		await process_frame
	renderer._evaluate_scale()
	await _capture("02-world-region")
	var deadline := Time.get_ticks_msec()+15000
	while not renderer.local_layer.ready and Time.get_ticks_msec()<deadline:
		await process_frame
	for band: Dictionary in [{"name":"03-region-far","scale":4.0},{"name":"04-region-mid","scale":1.2},{"name":"05-region-near","scale":0.36},{"name":"06-local-far","scale":0.18},{"name":"07-local-close","scale":0.05}]:
		camera.enter(unit,pixel,float(band.scale),0.0,renderer.size)
		app.map_controller.view_changed.emit()
		renderer.set("_last_pointer",pixel)
		renderer._ensure_view()
		renderer._evaluate_scale()
		for i: int in range(15):
			await process_frame
		await _capture(str(band.name))
	camera.pan(Vector2(500.0,150.0),renderer.size)
	app.map_controller.view_changed.emit()
	await process_frame
	await _capture("08-local-pan")
	app.map_controller.set_map_mode("fulfillment")
	await process_frame
	await _capture("09-economy-reference")
	app.map_controller.set_map_mode("political")
	for i: int in range(10):
		await _wheel(false)
		if not camera.local_active:
			break
	await _capture("10-region-restored")
	for fixture: Dictionary in [{"name":"beijing","point":Vector2(116.4074,39.9042)},{"name":"new-york","point":Vector2(-74.006,40.7128)}]:
		camera.enter(GlobeProjection.lon_lat_to_unit(fixture.point as Vector2),pixel,1.2,0.0,renderer.size)
		app.map_controller.select("")
		app.map_controller.view_changed.emit()
		renderer._ensure_view()
		await process_frame
		await _capture(str(fixture.name)+"-region-mid")
		for i: int in range(12):
			await _wheel(true)
		await _capture(str(fixture.name)+"-no-local")
	records.append({"save_unchanged":before==(app.get("_persistence") as FormalPersistence).snapshot(),"schema":FormalPersistence.SCHEMA_ID,"load":renderer.local_layer.metrics})
	var output := FileAccess.open(OUT+"journey.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(records,"  "))
	app.queue_free()
	await process_frame
	quit(0)
