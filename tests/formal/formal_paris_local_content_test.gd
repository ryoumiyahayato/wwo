extends SceneTree
## Dated admission, corruption rejection, lazy scope and world/save isolation.

var test := FormalTestCase.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var shard := LocalSpatialLoader._load()
	var errors: Array[String] = []
	var document := ContentDocument.read(LocalSpatialLoader.PARIS_PATH, errors)
	for source: Dictionary in document.source_registry.sources as Array:
		for field: String in ["title", "publisher", "version", "license", "locator"]:
			test.expect(not str(source.get(field, "")).is_empty(), "Complete source " + field)
		for field: String in ["source_date", "retrieved_on", "retrieval_information", "source_type", "data_transformation", "historical_applicability", "uncertainty"]:
			test.expect(not str(source.access_metadata.get(field, "")).is_empty(), "Complete source metadata " + field)
	test.equal(shard.errors, [], "Paris sources and facts pass existing provenance contracts")
	test.expect(shard.active_on("1900-01-01"), "1900 snapshot active")
	test.expect(shard.active_on("1900-12-31"), "1900 final day active")
	test.expect(not shard.active_on("1899-12-31") and not shard.active_on("1901-01-01"), "No invented historical validity outside snapshot")
	var ids: Dictionary = {}
	var counts: Dictionary = {"settlement": 0, "rail": 0, "river": 0, "coast": 0}
	for feature: Dictionary in shard.features:
		test.expect(not ids.has(str(feature.id)), "Unique stable ID: " + str(feature.id))
		ids[str(feature.id)] = feature
		counts[str(feature.kind)] += 1
		test.expect(LocalSpatialLoader._valid_feature(feature), "Valid dated geometry: " + str(feature.id))
		if str(feature.kind) == "settlement":
			test.expect(str(feature.source_id).begins_with("baedeker_") and str(feature.source_reference).contains("/page/n"), "Settlement has independent contemporary citation")
			test.expect(feature.has("coordinate_record_id") and not feature.has("population"), "Modern locator carries no population claim")
		else:
			test.expect(not feature.has("parent_country_id") and not feature.has("owner"), "Physical lines carry no political ownership")
		if str(feature.kind) == "rail":
			test.equal(feature.geometry_status, "BOUNDED_HISTORICAL_CORRIDOR_REFERENCE", "Rail accuracy is explicitly bounded")
			test.expect(int(feature.estimated_spatial_error_m) >= 1000, "Modern survey accuracy not claimed for 1900")
			for distance: Variant in (feature.place_distance_m as Dictionary).values():
				test.expect(float(distance) < 6500.0, "Named city lies reasonably near corridor")
	for kind: String in counts:
		test.equal(int(counts[kind]), int(shard.metadata.counts[kind]), "Declared count matches admitted " + kind)
	test.equal(shard.metadata.admin_status, "ADMIN_BOUNDARY_DATA_GAP", "Missing admin is explicit; no modern replacement")
	test.equal(shard.metadata.roads_status, "DEFER", "Modern roads not admitted")
	var paris := ids.get("place:paris", {}) as Dictionary
	test.equal(paris.identity_status, "REUSED", "Paris retains existing stable identity")
	var wrong := paris.duplicate(true)
	wrong["owner"] = "state:country_fra"
	test.expect(not LocalSpatialLoader._valid_feature(wrong), "Political ownership injection rejected")
	wrong = paris.duplicate(true)
	wrong.geometry.coordinates = [2.0, NAN]
	test.expect(not LocalSpatialLoader._valid_feature(wrong), "NaN geometry rejected")
	wrong.geometry = {"type": "Polygon", "coordinates": []}
	test.expect(not LocalSpatialLoader._valid_feature(wrong), "Modern admin polygon cannot masquerade as line")
	var copy := shard.dated_features("1900-01-01")
	copy.clear()
	test.expect(not shard.dated_features("1900-01-01").is_empty(), "Dated features are detached")
	root.size = Vector2i(1280, 720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	var world := app.get("_world") as WorldState
	var before := (app.get("_persistence") as FormalPersistence).snapshot()
	var renderer := app.map_renderer
	var loader := app.historical_content.local_spatial
	test.equal(loader.load_count, 0, "Game startup reads no Paris geometry")
	app.main_shell.set_page("map")
	var camera := app.map_controller.region_camera
	var pixel := renderer.size * 0.5
	for point: Vector2 in [Vector2(116.4074, 39.9042), Vector2(-74.006, 40.7128)]:
		camera.enter(GlobeProjection.lon_lat_to_unit(point), pixel, 0.19, 0.0, renderer.size)
		app.map_controller.view_changed.emit()
		renderer.set("_last_pointer", pixel)
		renderer._ensure_view()
		renderer._evaluate_scale()
		await process_frame
		test.expect(not camera.local_active, "Unloaded unsupported region remains REGION")
		test.equal(loader.load_count, 0, "East Asia/America cannot load Paris geometry")
	var unit := GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR)
	camera.enter(unit, pixel, 0.38, 0.0, renderer.size)
	app.map_controller.view_changed.emit()
	renderer._ensure_view()
	renderer._evaluate_scale()
	test.equal(loader.load_count, 1, "Paris prewarms near threshold")
	camera.km_per_pixel = 0.18
	app.map_controller.view_changed.emit()
	renderer._evaluate_scale()
	test.expect(not camera.local_active, "Unready shard remains REGION")
	var deadline := Time.get_ticks_msec() + 15000
	while not camera.local_active and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	test.expect(camera.local_active and renderer.local_layer.ready, "Admitted prepared shard enters LOCAL")
	camera.zoom_at(pixel, 0.5, renderer.size)
	app.map_controller.view_changed.emit()
	renderer.local_layer.update(camera, app.map_controller, "1900-01-01", renderer.size)
	var visible_points := renderer.local_layer.visible_places.values()
	test.expect(visible_points.size() >= 5, "Paris view contains nearby evidenced settlements")
	var unique_points: Dictionary = {}
	for point: Vector2 in visible_points:
		unique_points[point] = true
	test.equal(unique_points.size(), visible_points.size(), "Settlement points project to distinct positions")
	var versailles_point := renderer.local_layer.visible_places.get("place:versailles", Vector2.ZERO) as Vector2
	test.expect(not versailles_point.is_zero_approx(), "New Content settlement is visible")
	var click := InputEventMouseButton.new()
	click.position = versailles_point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	renderer._gui_input(click)
	click.pressed = false
	renderer._gui_input(click)
	test.equal(app.map_controller.selected_place_id, "place:versailles", "New settlement picking retains stable place ID")
	var page := app.historical_content.resolve_world_page(world.game_clock.current_date(), FormalWorldPresenter.selected_world_polity(world, app.map_controller), "place:versailles")
	test.equal(page.place().get("name"), "Versailles", "New settlement dossier resolves through Content")
	var place_copy := page.place()
	place_copy["name"] = "mutated"
	test.equal(page.place().get("name"), "Versailles", "Settlement dossier is detached")
	test.expect(not renderer.is_processing(), "Ready Local idle stops processing")
	var load_count := loader.load_count
	var chunks := loader.content.line_chunks.size()
	for index: int in range(20):
		camera.pan(Vector2(1.0, 0.0), renderer.size)
		camera.zoom_at(pixel, 0.997, renderer.size)
		app.map_controller.view_changed.emit()
		await process_frame
	test.equal(loader.load_count, load_count, "Pan/zoom do not read/parse sources again")
	test.equal(loader.content.line_chunks.size(), chunks, "Pan/zoom reuse prepared geometry")
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(), before, "All population/economy/personal/save facts remain identical")
	test.equal(world, app.get("_world"), "Same sole WorldState")
	test.equal(FormalPersistence.SCHEMA_ID, "formal_world_simulation_v14", "v14 unchanged")
	# Dated presentation refresh rejects expired Local data without advancing
	# the simulation or creating a test-only world-state exception.
	var future := app.historical_content.resolve_map({"year": 1901, "month": 1, "day": 1}, FormalWorldPresenter.map_units(world))
	FormalWorldPresenter.refresh_map(world, renderer, future)
	test.expect(not camera.local_active, "Expired date returns to REGION")
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(), before, "Display-date query changes no WorldState")
	app.queue_free()
	await process_frame
	test.finish(self, "Paris Local Content R1")
