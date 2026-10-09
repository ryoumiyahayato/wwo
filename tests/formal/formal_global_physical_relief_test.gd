extends SceneTree
var test := FormalTestCase.new()

func _initialize() -> void:
	_run.call_deferred()

func _settle(renderer: GlobeRenderer) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 15000
	while renderer.relief.preparing() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	await create_timer(0.10).timeout
	test.expect(not renderer.relief.preparing(), "Relief finite preparation settles")
	test.expect(renderer.relief.errors.is_empty(), "Relief source and image admitted")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var errors: Array[String] = []
	var document := ContentDocument.read(GeographyLoader.RELIEF_PATH, errors)
	var sources := HistoricalSourceRegistry.new()
	var facts := HistoricalEvidenceCatalog.new()
	test.expect(sources.load_document(document.source_registry as Dictionary), "Existing source contract")
	test.expect(facts.load_document(document.evidence_catalog as Dictionary), "Existing fact contract")
	var fact := facts.fact("physical_relief:etopo_2022")
	var gate := HistoricalProvenanceGate.new(sources, facts)
	test.expect(gate.admit_runtime_fact(fact.fact_id, "physical_reference_content", fact.output_material()), "Physical reference through existing provenance gate")
	var source := sources.source(fact.source_id)
	test.equal(source.license, "CC0-1.0", "Redistributable licensed source")
	var metadata := source.access_metadata as Dictionary
	for key: String in ["resolution", "coverage", "vertical_datum", "polar_coverage", "known_gaps", "ocean_handling", "historical_applicability", "uncertainty", "data_transformation", "source_assets", "retrieved_on"]:
		test.expect(metadata.has(key), "Source includes " + key)
	test.equal((fact.value as Dictionary).status, "PHYSICAL_REFERENCE", "Not historical terrain evidence")
	var regional_image := Image.new()
	for asset: Dictionary in (fact.value as Dictionary).assets:
		var bytes := FileAccess.get_file_as_bytes(str(asset.path))
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		test.equal(hash.finish().hex_encode(), asset.sha256, "Runtime asset source-bound bytes")
		var image := Image.new()
		test.equal(image.load_png_from_buffer(bytes), OK, "Offline PNG decodes")
		test.equal(image.get_size(), Vector2i(int(asset.width), int(asset.height)), "Finite LOD dimensions")
		for y: int in [0, image.get_height()-1]:
			for x: int in range(0, image.get_width(), 97):
				test.equal(image.get_pixel(x,y), image.get_pixel(0,y), "Every LOD has longitude-invariant pole samples")
		if str(asset.id) == "physical_relief:region": regional_image = image
	for row: int in [0, 1, 2, 2045, 2046, 2047]:
		for x: int in range(0, regional_image.get_width(), 97):
			test.equal(regional_image.get_pixel(x, row).r, regional_image.get_pixel(0, row).r, "Pole longitude invariance")
			test.equal(regional_image.get_pixel(x, row).g, regional_image.get_pixel(0, row).g, "Pole background height invariance")
	var rejected := GeographyLoader.decode_relief("world", {"world": {"path": "res://assets/maps/relief/world.bin", "sha256": "invalid"}})
	test.expect(not (rejected.errors as Array).is_empty() and not rejected.has("image"), "Corrupt byte binding fails closed")
	for scale: float in [50, 75, 188, 350, 1200, 4500, 8000, 16000]:
		var weight := MapScaleStyle.relief_weight(scale, "political")
		test.expect(weight >= 0.0 and weight <= 0.65, "Restrained relief blend")
		test.expect(absf(weight-MapScaleStyle.relief_weight(scale+0.01, "political")) < 0.001, "Continuous scale blend")
		test.expect(MapScaleStyle.relief_weight(scale, "economy_fulfillment") < weight, "Economy colors remain dominant")
	test.expect(MapScaleStyle.relief_weight(75, "political") < MapScaleStyle.relief_weight(1200, "political"), "Local cannot imply finer terrain")
	var shader_text := FileAccess.get_file_as_string("res://shaders/presentation/map/political_surface.gdshader")
	test.expect(not shader_text.contains("TIME"), "Static shader has no time dependency")
	test.expect(shader_text.contains("transpose(globe_basis)") and shader_text.contains("repeat_enable"), "Shared inverse projection and periodic longitude")
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	var saved := (app.get("_persistence") as FormalPersistence).snapshot()
	var renderer := app.map_renderer
	var controller := app.map_controller
	var camera := controller.region_camera
	test.expect(renderer.relief.textures.is_empty(), "Person startup does not load map textures")
	app.main_shell.set_page("map")
	controller.focus(GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR))
	await _settle(renderer)
	test.equal(renderer.relief.textures.keys(), ["world"], "WORLD only needs coarse LOD")
	test.equal(int(renderer.relief.metrics.resident_bytes), 2*1024*512, "WORLD bounded texture payload")
	for batch: Dictionary in (renderer.get("_surface_batches") as Dictionary).values():
		test.equal((batch.material as ShaderMaterial).get_shader_parameter("relief_world"), renderer.relief.textures.world, "World batches bind prepared shared texture")
	var pixel := renderer.size*0.5
	camera.enter(GlobeProjection.lon_lat_to_unit(Vector2(86, 29)), pixel, 1.5, 0.2, renderer.size)
	controller.view_changed.emit()
	renderer.set("_last_pointer", pixel)
	renderer._ensure_view()
	renderer._evaluate_scale()
	await _settle(renderer)
	test.equal(int(renderer.relief.metrics.resident_bytes), 2*(1024*512+4096*2048), "Region finite pair shared by canvases")
	test.equal(int(renderer.relief.metrics.source_resolutions), 1, "Single source admission")
	for batch: Dictionary in renderer.region_view.surfaces.values():
		test.equal((batch.material as ShaderMaterial).get_shader_parameter("relief_region"), renderer.relief.textures.region, "Prepared regional batches inherit current residency")
	var loads := (renderer.relief.metrics.loads as Dictionary).duplicate(true)
	var projections := renderer.cpu_projection_count
	for coordinate: Vector2 in [Vector2(10,46), Vector2(137,36), Vector2(-110,42), Vector2(-70,-25), Vector2(179.9,65), Vector2(-179.9,65), Vector2(0,89.9), Vector2(0,-89.9), Vector2(10,46)]:
		camera.enter(GlobeProjection.lon_lat_to_unit(coordinate), pixel, 1.5, 0.0, renderer.size)
		controller.view_changed.emit()
		renderer._ensure_view()
		await process_frame
		test.equal(int(renderer.relief.metrics.resident_bytes), 2*(1024*512+4096*2048), "Global travel does not accumulate textures")
		var one := (renderer.relief.metrics.loads as Dictionary).get("region", []) as Array
		test.equal(one.size(), (loads.region as Array).size(), "Global travel needs no re-decode")
	test.equal(renderer.cpu_projection_count, projections, "Travel does not CPU-reproject source geography")
	# The relief texture is already resident, but changing regions also starts
	# finite physical-vector preparation. Observe idle after that work finishes.
	var content_deadline := Time.get_ticks_msec() + 30000
	while renderer.is_processing() and Time.get_ticks_msec() < content_deadline:
		await create_timer(0.005).timeout
	test.expect(not renderer.is_processing(), "Regional content preparation terminates within its deadline")
	await create_timer(0.3).timeout
	var redraws := renderer.render_draw_count
	var updates := renderer.view_update_count
	await create_timer(0.3).timeout
	test.equal(renderer.render_draw_count, redraws, "Static relief has no repeated map redraw")
	test.equal(renderer.view_update_count, updates, "Static relief has no repeated view work")
	test.expect(not renderer.is_processing(), "Renderer processing switches off")
	controller.focus(GlobeProjection.lon_lat_to_unit(Vector2(86, 29)))
	await create_timer(0.4).timeout
	test.equal(renderer.relief.textures.keys(), ["world"], "Leaving fine scale releases regional texture")
	for batch: Dictionary in renderer.region_view.surfaces.values():
		test.equal((batch.material as ShaderMaterial).get_shader_parameter("relief_region"), renderer.relief.textures.world, "Hidden material cannot pin released high LOD")
	test.equal((renderer.region_view.background.material as ShaderMaterial).get_shader_parameter("relief_region"), renderer.relief.textures.world, "Background cannot pin released high LOD")
	app.main_shell.set_page("person")
	await process_frame
	test.expect(renderer.relief.textures.is_empty(), "Leaving map releases relief texture resources")
	test.equal((renderer.region_view.background.material as ShaderMaterial).get_shader_parameter("relief_world"), null, "Hidden background clears texture reference")
	test.equal(saved, (app.get("_persistence") as FormalPersistence).snapshot(), "Relief leaves exact authoritative save unchanged")
	test.equal(FormalPersistence.SCHEMA_ID, "formal_world_simulation_v15", "Save schema unchanged")
	app.queue_free()
	await process_frame
	test.finish(self, "Global physical relief R1")
