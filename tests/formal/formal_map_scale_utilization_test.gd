extends SceneTree
## LOD provenance, mutable administration seam, scope and camera-only changes.
var test := FormalTestCase.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var last := 0.0
	for mpp: int in range(25, 18001, 25):
		var weight := MapScaleStyle.flag_weight(float(mpp))
		test.expect(weight >= last and weight <= 1.0, "Continuous monotonic flag scale")
		test.expect(absf(weight-last) < 0.03, "No discontinuous flag jump")
		last = weight
	test.equal(MapScaleStyle.flag_weight(180.0), 0.0, "Local has no giant flag")
	test.equal(MapScaleStyle.flag_weight(32000.0), 1.0, "World retains full flag identity")
	test.expect(MapScaleStyle.political_weight(100.0) < MapScaleStyle.political_weight(4000.0), "Political fill recedes near")
	test.equal(MapScaleStyle.physical_weight("rail", 4000.0), 0.0, "Far rail suppressed")
	test.equal(MapScaleStyle.physical_weight("rail", 600.0), 1.0, "Near main corridors visible")
	var cache := AdministrativeBoundaryCache.new()
	cache.membership_changed(["admin:a","admin:b"], 1)
	test.expect(cache.store("admin:a", 1, [{"points":[Vector2.ZERO,Vector2.ONE]}]), "Affected grouping accepts current rebuilt geometry")
	test.expect(cache.store("admin:b", 1, [{"points":[Vector2.ZERO,Vector2.ONE]}]), "Independent grouping cached")
	cache.membership_changed(["admin:a"], 2)
	test.equal(cache.dirty_regions(), ["admin:a"], "Only affected administrative grouping dirtied")
	test.expect(cache.boundaries("admin:a").is_empty() and not cache.boundaries("admin:b").is_empty(), "Changed membership invalidates only its geometry")
	test.expect(not cache.store("admin:a", 1, []), "Old asynchronous union result cannot overwrite new revision")
	test.expect(cache.store("admin:a", 2, []), "Empty or dissolved grouping can be cached")
	root.size = Vector2i(1280,720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	var before := (app.get("_persistence") as FormalPersistence).snapshot()
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	# Explicit all-resident comparison fixture verifies all derived source IDs.
	# Product residency and release behaviour are checked by the R2 runner.
	renderer.local_layer.residency_policy = "all"
	var camera := app.map_controller.region_camera
	var pixel := renderer.size * 0.5
	var unit := GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR)
	camera.enter(unit,pixel,4.0,0.0,renderer.size)
	app.map_controller.labels_enabled = true
	app.map_controller.view_changed.emit()
	renderer.set("_last_pointer",pixel)
	renderer._ensure_view()
	renderer._evaluate_scale()
	var deadline := Time.get_ticks_msec()+20000
	while (not renderer.local_layer.ready or renderer.local_layer.preparing) and Time.get_ticks_msec()<deadline:
		await create_timer(0.005).timeout
	test.expect(renderer.local_layer.ready, "Paris cache prepared in far Region")
	test.expect(not camera.local_active, "Early content does not change runtime scale mode")
	var layer := renderer.local_layer
	var features: Dictionary = {}
	for feature: Dictionary in app.historical_content.local_spatial.content.features:
		features[str(feature.id)] = feature
	for chunk: Dictionary in layer.get("_chunks") as Array[Dictionary]:
		for boundary: Dictionary in chunk.boundaries as Array:
			test.expect(features.has(str(boundary.feature_id)), "Every LOD derives from the same stable feature")
			test.equal(boundary.source_fact_id, "local_spatial:"+str(boundary.feature_id), "LOD is not a second source fact")
	var stats := layer.metrics.lod_stats as Dictionary
	test.expect(int(stats.coarse.segments)<int(stats.medium.segments) and int(stats.medium.segments)<int(stats.local.segments), "Finite caches progressively increase detail")
	var prepare_count := layer.prepare_count
	var loads := app.historical_content.local_spatial.load_count
	var ready_cost := int(layer.metrics.ready_since_load_usec)
	var previous_count: int = 0
	for scale: float in [4.0,1.2,0.36,0.18,0.09]:
		camera.km_per_pixel = scale
		app.map_controller.view_changed.emit()
		renderer._ensure_view()
		layer.update(camera,app.map_controller,"1900-01-01",renderer.size)
		test.equal(layer.active_lod,MapScaleStyle.lod(scale*1000.0),"Scale selects cached geometry")
		var eligible: int = 0
		for feature: Dictionary in features.values():
			if str(feature.kind)=="settlement" and MapScaleStyle.settlement_limit(int(feature.rank),str(feature.id))>=scale*1000.0:
				eligible += 1
		test.expect(eligible>=previous_count,"Eligible city density grows independently of smaller view extent")
		previous_count = eligible
		camera.pan(Vector2(1.0,0.0),renderer.size)
		app.map_controller.view_changed.emit()
		await process_frame
	test.equal(layer.prepare_count,prepare_count,"Camera never rebuilds geometry")
	test.equal(app.historical_content.local_spatial.load_count,loads,"Zoom never reparses shard")
	test.equal(int(layer.metrics.ready_since_load_usec),ready_cost,"No source resolution rerun")
	for point: Vector2 in [Vector2(116.4074,39.9042),Vector2(-74.006,40.7128)]:
		camera.enter(GlobeProjection.lon_lat_to_unit(point),pixel,0.18,0.0,renderer.size)
		app.map_controller.view_changed.emit()
		renderer.set("_last_pointer",pixel)
		renderer._ensure_view()
		renderer._evaluate_scale()
		layer.update(camera,app.map_controller,"1900-01-01",renderer.size)
		test.expect(layer.visible_places.is_empty() and layer.active_lod.is_empty(),"Loaded Paris cannot leak into another region")
		test.expect(not camera.local_active,"Loaded Paris cannot enable unsupported Local")
	test.expect(renderer.administrative_boundaries.dirty_regions().is_empty(),"Camera causes no administrative rebuild")
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(),before,"Presentation changes preserve entire world and v14 save")
	app.queue_free()
	await process_frame
	test.finish(self,"Map visual scale utilization R1")
