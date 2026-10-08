extends SceneTree
## Existing-world display fixtures: exact shared-chart handoff, finite domain,
## honest unsupported anchors, actual stable place picking and no fact mutation.

var test := FormalTestCase.new()
var rows: Array[Dictionary] = []
var max_inverse_error_km: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _wheel(renderer: GlobeRenderer, point: Vector2, up: bool) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	renderer._gui_input(wheel)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	var controller := app.map_controller
	var world := app.get("_world") as WorldState
	var persistence := app.get("_persistence") as FormalPersistence
	var before := persistence.snapshot()
	var camera := controller.region_camera
	var pixel := Vector2(495.0, 240.0)
	var fixtures: Array[Dictionary] = [
		{"id": "place:paris", "point": Vector2(2.3522, 48.8566), "mode": "political"},
		{"id": "place:beijing", "point": Vector2(116.4074, 39.9042), "mode": "fulfillment"},
		{"id": "place:new_york", "point": Vector2(-74.006, 40.7128), "mode": "shortage"}]
	for fixture: Dictionary in fixtures:
		var unit := GlobeProjection.lon_lat_to_unit(fixture.point as Vector2)
		camera.enter(unit, pixel, 0.24, 0.38, renderer.size)
		controller.select("state:country_fra", str(fixture.id))
		controller.set_map_mode(str(fixture.mode))
		controller.labels_enabled = true
		controller.view_changed.emit()
		renderer.set("_region_labels_dirty", true)
		renderer._ensure_view()
		for index: int in range(30):
			await process_frame
		test.expect(renderer.region_view.ready, "Prepared existing planar canvas")
		var geometry: Variant = (renderer.region_view.surfaces.values()[0] as Dictionary).geometry
		var label_count := renderer.region_view.label_prepare_count
		var glyph_count := renderer.region_view.glyph_submit_count
		var frame := camera.tangent_frame
		_wheel(renderer, pixel, true)
		await process_frame
		if fixture.id != "place:paris":
			for index: int in range(5):
				_wheel(renderer, pixel, true)
			test.expect(not camera.local_active and camera.active, "Unsupported fixture stays REGION")
			test.equal(controller.selected_place_id, fixture.id, "Unsupported anchor selection remains")
			test.equal(controller.map_mode, fixture.mode, "Unsupported anchor mode remains")
			test.equal(camera.km_per_pixel, RegionCamera.MIN_KM_PER_PIXEL, "Unsupported anchor stops at finest REGION scale")
			continue
		var deadline := Time.get_ticks_msec() + 10000
		while not camera.local_active and Time.get_ticks_msec() < deadline:
			await create_timer(0.005).timeout
		test.expect(camera.local_active, "Wheel enters bounded LOCAL fixture")
		test.equal(camera.local_place_id, fixture.id, "Scope uses current place stable ID")
		var entry_delta := renderer.screen_point(unit) - pixel
		test.expect(entry_delta.length() < 0.02, "Entry anchor within 0.02 px")
		test.equal(camera.tangent_frame, frame, "Handoff preserves fixed geographic chart")
		test.equal(camera.bearing, 0.38, "Bearing unchanged")
		test.equal(controller.selected_place_id, fixture.id, "Selection survives")
		test.equal(controller.map_mode, fixture.mode, "Mode survives")
		test.expect(controller.labels_enabled, "Labels survives")
		test.equal(renderer.political.display_date, "1900-01-01", "Date survives")
		test.equal(renderer._place_at(renderer.screen_point(unit)), fixture.id, "Picking returns actual place ID")
		var click := InputEventMouseButton.new()
		click.position = renderer.screen_point(unit)
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		renderer._gui_input(click)
		click.pressed = false
		renderer._gui_input(click)
		test.equal(controller.selected_place_id, fixture.id, "Click retains place independently of unresolved polity")
		if fixture.id == "place:new_york":
			test.equal(controller.selected_polity_id, "", "No guessed New York political crosswalk")
		test.equal((renderer.region_view.surfaces.values()[0] as Dictionary).geometry, geometry, "No new GPU geometry")
		test.equal(renderer.region_view.label_prepare_count, label_count, "No label preparation at handoff")
		test.equal(renderer.region_view.glyph_submit_count, glyph_count, "No glyph resubmission at handoff")
		test.expect(not renderer.is_processing(), "LOCAL idle does not process")
		for distance: float in [0.0, 50.0, 150.0, 299.0]:
			for angle: float in [0.0, 1.3, 3.2, 5.0]:
				var km := camera.local_center_km + Vector2(cos(angle), sin(angle)) * distance
				var sample := RegionProjection.inverse(km, camera.tangent_frame)
				var error := (camera.local_metric(sample) - (km - camera.local_center_km)).length()
				max_inverse_error_km = maxf(max_inverse_error_km, error)
				test.expect(error < 0.002, "LOCAL coordinates invert within 2m")
		var beyond := RegionProjection.inverse(camera.local_center_km + Vector2(301.0, 0.0), frame)
		test.expect(camera.unit_at(camera.project(beyond)).is_zero_approx(), "Outside Local circle has no pick")
		_wheel(renderer, pixel, false)
		test.expect(camera.local_active, "Hysteresis retains Local above entry threshold")
		_wheel(renderer, pixel, false)
		await process_frame
		test.expect(not camera.local_active and camera.active, "Wheel returns REGION")
		var exit_delta := renderer.screen_point(unit) - pixel
		test.expect(exit_delta.length() < 0.02, "Exit anchor within 0.02 px")
		renderer._evaluate_scale()
		test.expect(not camera.local_active, "Exit does not immediately re-enter")
		rows.append({"place_id": fixture.id, "entry_dx": entry_delta.x, "entry_dy": entry_delta.y, "exit_dx": exit_delta.x, "exit_dy": exit_delta.y})
		camera.km_per_pixel = 0.19
		camera.origin = pixel
		controller.view_changed.emit()
		renderer._ensure_view()
		renderer.set("_last_pointer", pixel)
		renderer._evaluate_scale()
		test.expect(camera.local_active, "Re-enter supported fixture")
		for delta: Vector2 in [Vector2(1000000, 1000000), Vector2(-2000000, -2000000)]:
			camera.pan(delta, renderer.size)
			for corner: Vector2 in [Vector2.ZERO, Vector2(renderer.size.x, 0.0), renderer.size, Vector2(0.0, renderer.size.y)]:
				test.expect(not camera.unit_at(corner).is_zero_approx(), "Pan stops at finite boundary with viewport inside")
			test.expect(camera.local_metric(camera.unit_at(renderer.size * 0.5)).length() <= RegionCamera.LOCAL_RADIUS_KM, "Pan cannot reach another continent")
		# Pan/zoom never rebuild static data. Hidden view never prepares or renders.
		controller.view_changed.emit()
		await process_frame
		test.equal(renderer.region_view.label_prepare_count, label_count, "Pan preserves label metadata")
		app.main_shell.set_page("person")
		await process_frame
		test.expect(not renderer.is_processing(), "Hidden LOCAL no process")
		test.equal(renderer.region_view.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "Hidden LOCAL no render")
		app.main_shell.set_page("map")
		await process_frame
		camera.leave_local()
	# No admitted detail file means no fallback to GeoNames or fabricated objects.
	var ocean := GlobeProjection.lon_lat_to_unit(Vector2(-140.0, 0.0))
	camera.enter(ocean, pixel, 0.19, 0.0, renderer.size)
	controller.view_changed.emit()
	renderer.set("_region_labels_dirty", true)
	renderer._ensure_view()
	renderer.set("_last_pointer", pixel)
	renderer._evaluate_scale()
	test.expect(not camera.local_active, "No nearby world place stays REGION")
	var distant := RegionProjection.inverse(Vector2(501.0, 0.0), camera.tangent_frame)
	test.expect(not camera.enter_local(distant, pixel, renderer.size, "place:paris"), "No large-chart distortion accepted")
	test.expect(not camera.enter_local(ocean, pixel, renderer.size, ""), "Unknown place does not invent support")
	var paris := GlobeProjection.lon_lat_to_unit(Vector2(2.3522, 48.8566))
	camera.enter(paris, pixel, 0.19, 0.0, renderer.size)
	controller.view_changed.emit()
	renderer._ensure_view()
	renderer.region_view.ready = false
	renderer.set("_last_pointer", pixel)
	renderer._evaluate_scale()
	test.expect(not camera.local_active, "Unready canvas remains REGION")
	renderer.region_view.ready = true
	test.equal(persistence.snapshot(), before, "Every camera operation leaves all world/save facts identical")
	test.equal(FormalPersistence.SCHEMA_ID, "formal_world_simulation_v15", "Save schema unchanged")
	test.equal(renderer.political.places.size(), 40, "No extra modern cities or fabricated nodes")
	DirAccess.make_dir_recursive_absolute("res://local-artifacts/local-foundation-r1")
	var output := FileAccess.open("res://local-artifacts/local-foundation-r1/anchor-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"maximum_inverse_error_km": max_inverse_error_km, "fixtures": rows}, "  "))
	app.queue_free()
	await process_frame
	test.finish(self, "Formal map Local foundation")
