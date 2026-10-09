extends SceneTree
## Actual presentation transitions, finite camera and source geometry identity.

var test := FormalTestCase.new()
var evidence: Array[Dictionary] = []
var maximum_inverse_error_km: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for center: Vector2 in [Vector2(2.35, 48.85), Vector2(116.4, 39.9), Vector2(-74.0, 40.7), Vector2(20.0, 78.0), Vector2(179.5, 15.0), Vector2(0.0, 90.0), Vector2(0.0, -90.0)]:
		var frame := RegionProjection.frame(center)
		for distance: float in [0.0, 1.0, 1000.0, 3000.0, 6000.0, 8000.0]:
			for angle: float in [0.0, 0.9, 2.2, 4.5]:
				var km := Vector2(cos(angle), sin(angle)) * distance
				var unit := RegionProjection.inverse(km, frame)
				var error := RegionProjection.forward(unit, frame).distance_to(km)
				maximum_inverse_error_km = maxf(maximum_inverse_error_km, error)
				test.expect(error < 0.02, "Forward/inverse within 20 metres, including poles and date line")
		for pixel: Vector2 in [Vector2(380.0, 210.0), Vector2(900.0, 410.0)]:
			for bearing: float in [-1.7, 0.0, 2.8]:
				var restored := RegionProjection.restore_world(frame.z, pixel, Vector2(640.0, 275.0), 7.2, bearing)
				var attitude := restored.orientation as Basis
				var radius := float(restored.radius)
				test.expect(GlobeProjection.sphere_screen(attitude * frame.z, Vector2(640.0, 275.0), radius).distance_to(pixel) < 0.01, "Restored WORLD anchor within 0.01 pixel")
				test.expect(absf(RegionProjection.world_scale(frame.z, attitude, radius) - 7.2) < 0.00001, "Restored WORLD actual local scale")
				test.expect(absf(wrapf(RegionProjection.world_bearing(frame.z, attitude) - bearing, -PI, PI)) < 0.00001, "Restored WORLD local north bearing")
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	var controller := app.map_controller
	var world := app.get("_world") as WorldState
	var before := (app.get("_persistence") as FormalPersistence).snapshot()
	controller.select("state:country_fra", "place:paris")
	controller.labels_enabled = true
	var modes: Array[String] = ["political", "fulfillment", "shortage", "political", "fulfillment"]
	var targets: Array[Vector2] = [Vector2(2.35, 48.85), Vector2(116.4, 39.9), Vector2(-74.0, 40.7), Vector2(20.0, 78.0), Vector2(179.5, 15.0)]
	for index: int in range(targets.size()):
		var unit := GlobeProjection.lon_lat_to_unit(targets[index])
		var pixel := Vector2(495.0, 240.0)
		var attitude := RegionProjection.restore_world(unit, pixel, renderer.size * 0.5, 5.3, 0.38)
		controller.region_camera.active = false
		controller._orientation = (attitude.orientation as Basis).get_rotation_quaternion()
		controller.zoom = float(attitude.radius) / minf(renderer.size.y / 2.55, renderer.size.x * 0.49)
		controller.set_map_mode(modes[index])
		controller.hover("state:country_fra", "place:paris")
		controller.view_changed.emit()
		renderer._ensure_view()
		renderer.set("_last_pointer", pixel)
		var original_pixel := renderer.screen_point(unit)
		var original_basis := controller.orientation()
		var world_texture := renderer.get("_viewport") as SubViewport
		renderer._evaluate_scale()
		test.equal((renderer.get("_container") as SubViewportContainer).modulate.a, 1.0, "Crossfade keeps the lower WORLD canvas opaque")
		if index == 0:
			test.expect(not controller.region_camera.active, "WORLD remains displayed while preparation is incomplete")
		for frame_index: int in range(35):
			await process_frame
		test.expect(controller.region_camera.active and renderer.region_view.ready, "Actual WORLD to REGION completion")
		test.expect(int(renderer.transition_metrics.get("elapsed_usec", 0)) >= int(GlobeRenderer.TRANSITION_SECONDS * 1000000.0), "Entry fade respects actual elapsed time")
		var delta := renderer.screen_point(unit) - original_pixel
		test.expect(delta.length() < 0.02, "Off-centre geographic anchor stays at its original screen pixel")
		test.equal(controller.selected_polity_id, "state:country_fra", "Selection independent of camera anchor")
		test.equal(controller.selected_place_id, "place:paris", "Place selection survives even outside this region")
		test.equal(controller.map_mode, modes[index], "Current mode survives")
		test.expect(controller.labels_enabled, "Labels switch survives")
		test.equal(renderer.political.display_date, "1900-01-01", "Display date survives")
		# Local and global physical content can finish after the camera fade.
		# Idle is asserted only after all finite preparation has terminated.
		if renderer.is_processing():
			test.expect(renderer.is_processing(), "Finite Region content preparation has a scheduler")
			var preparation_deadline := Time.get_ticks_msec() + 30000
			while renderer.is_processing() and Time.get_ticks_msec() < preparation_deadline:
				await create_timer(0.005).timeout
			test.expect(not renderer.is_processing(), "Finite Region preparation terminates within its deadline")
		test.expect(not renderer.is_processing(), "REGION idle has no preparation/transition process")
		test.expect(not (renderer.get("_container") as SubViewportContainer).visible, "Inactive WORLD is hidden after fade")
		test.equal(world_texture.render_target_update_mode, SubViewport.UPDATE_DISABLED, "Inactive WORLD does not render")
		var batches := renderer.get("_surface_batches") as Dictionary
		for owner: String in renderer.region_view.surfaces:
			test.expect((renderer.region_view.surfaces[owner] as Dictionary).geometry == (batches[owner] as Dictionary).geometry, "REGION shares immutable WORLD geometry")
		var sampled := 0
		for owner: String in batches:
			if owner.is_empty():
				continue
			var geometry := (batches[owner] as Dictionary).geometry as GlobeSurfaceBatch
			for chunk: Dictionary in geometry.get("_pick_chunks") as Array:
				for entry: Dictionary in chunk.faces:
					var points := (entry.face as Dictionary).points as PackedVector3Array
					var centroid := (controller.region_camera.project(points[0]) + controller.region_camera.project(points[1]) + controller.region_camera.project(points[2])) / 3.0
					if Rect2(Vector2(20.0, 20.0), renderer.size - Vector2(40.0, 40.0)).has_point(centroid):
						test.equal(renderer._polity_at(centroid), str((renderer.political.records[owner] as Dictionary).get("runtime_entity_id", owner)), "Regional exact polygon picking returns current stable identity")
						sampled += 1
						break
				if sampled >= 15:
					break
			if sampled >= 15:
				break
		var entry_delta := delta
		var camera := controller.region_camera
		var prepared_labels := renderer.region_view.label_prepare_count
		var submitted_glyphs := renderer.region_view.glyph_submit_count
		renderer.region_view.update_labels(camera, controller, renderer.get("_font") as Font, renderer.size)
		test.equal(renderer.region_view.glyph_submit_count, submitted_glyphs, "Repeated regional redraw reuses text glyph commands")
		camera.pan(Vector2(1.0, 0.0), renderer.size)
		controller.view_changed.emit()
		await process_frame
		test.equal(renderer.region_view.label_prepare_count, prepared_labels, "Camera pan does not prepare geographical labels or reshape text")
		camera.pan(Vector2(100000.0, -100000.0), renderer.size)
		test.expect(camera.origin.distance_to(renderer.size * 0.5) + renderer.size.length() * 0.5 <= camera.extent_km / camera.km_per_pixel + 0.1, "Pan cannot leave the finite region")
		camera.origin = pixel
		camera.km_per_pixel = 7.2
		controller.view_changed.emit()
		renderer._ensure_view()
		var exit_pixel := renderer.screen_point(unit)
		renderer._evaluate_scale()
		for frame_index: int in range(35):
			await process_frame
		test.expect(not camera.active, "Actual REGION to WORLD completion")
		test.expect(int(renderer.transition_metrics.get("elapsed_usec", 0)) >= int(GlobeRenderer.TRANSITION_SECONDS * 1000000.0), "Exit fade respects actual elapsed time")
		delta = renderer.screen_point(unit) - exit_pixel
		test.expect(delta.length() < 0.02, "Exit anchor screen pixel continuity")
		test.expect(absf(RegionProjection.world_bearing(unit, controller.orientation()) - 0.38) < 0.002, "Round trip local bearing stays continuous")
		test.expect(not renderer.region_view.container.visible, "Inactive REGION hidden after fade")
		test.equal(renderer.region_view.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "Inactive REGION does not render")
		# Returning to the same scale recovers the initial globe attitude.
		var round_trip := RegionProjection.restore_world(unit, pixel, renderer.size * 0.5, 5.3, RegionProjection.world_bearing(unit, controller.orientation()))
		var attitude_error := (original_basis.x - (round_trip.orientation as Basis).x).length()
		test.expect(attitude_error < 0.002, "Round trip camera attitude recovers at the same spatial scale")
		evidence.append({"lon_lat": targets[index], "entry_dx": entry_delta.x, "entry_dy": entry_delta.y, "exit_dx": delta.x, "exit_dy": delta.y, "bearing_error_rad": RegionProjection.world_bearing(unit, controller.orientation()) - 0.38, "attitude_error": attitude_error, "extent_km": camera.extent_km})
		renderer._evaluate_scale()
		test.expect(not camera.active, "Hysteresis prevents immediate re-entry at the exit scale")
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(), before, "Presentation round trips change no world fact or saved field")
	test.equal(FormalPersistence.SCHEMA_ID, "formal_world_simulation_v15", "Schema unchanged")
	test.expect(world == app.get("_world"), "No new WorldState is constructed")
	var afghan := ""
	for unit: Dictionary in FormalWorldPresenter.map_units(world):
		if str(unit.get("flag_id", "")) == "afghanistan_1880":
			afghan = str(unit.id)
	controller.focus(renderer.political.anchors.get(afghan, Vector3.ZERO) as Vector3)
	controller.zoom = RegionProjection.EARTH_RADIUS_KM / (5.3 * minf(renderer.size.y / 2.55, renderer.size.x * 0.49))
	controller.view_changed.emit()
	renderer.set("_last_pointer", renderer.size * 0.5)
	renderer._evaluate_scale()
	for frame_index: int in range(30):
		await process_frame
	test.expect(controller.region_camera.active and renderer.political.visual_textures.has(afghan), "REGION has current 1900 Afghanistan flag")
	app._advance_world(365 * 24 * 60)
	for frame_index: int in range(30):
		await process_frame
	test.equal(renderer.political.display_date, "1901-01-01", "REGION receives the sole clock's new date")
	test.expect(controller.region_camera.active and renderer.region_view.ready, "Year refresh retains REGION with newly bound shared geometry")
	test.expect(not renderer.political.visual_textures.has(afghan), "REGION drops expired flags through the same Content resolution")
	if OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("res://local-artifacts/map-scale-r1")
		var output := FileAccess.open("res://local-artifacts/map-scale-r1/anchor-tests.json", FileAccess.WRITE)
		output.store_string(JSON.stringify({"maximum_inverse_error_km": maximum_inverse_error_km, "anchors": evidence}, "  "))
	app.queue_free()
	await process_frame
	test.finish(self, "Formal map scale transition")
