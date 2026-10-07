extends SceneTree
var test := FormalTestCase.new()

func _initialize() -> void:
	_run.call_deferred()

func _settle(renderer: GlobeRenderer) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec()+30000
	while (renderer.strategic_layer.preparing or renderer.strategic_content.preparing() or renderer.region_view.preparing) and Time.get_ticks_msec()<deadline:
		await create_timer(0.01).timeout
	await create_timer(0.1).timeout
	test.expect(not renderer.strategic_layer.preparing and not renderer.strategic_content.preparing(), "Bounded strategic preparation settles")
	test.expect(renderer.strategic_content.errors.is_empty(), "Source and geometry admission")

func _run() -> void:
	var errors: Array[String] = []
	var index := ContentDocument.read(StrategicSpatialLoader.INDEX_PATH, errors)
	var identities: Dictionary = {}
	var all_features: Dictionary = {}
	var counts: Dictionary = {}
	for descriptor: Dictionary in index.regions as Array:
		var selected: Array[String] = [str(descriptor.id)]
		var content := StrategicSpatialLoader._load(index,selected)
		test.expect(content.errors.is_empty(), "Admitted " + str(descriptor.id))
		test.expect(not bool(content.metadata.local_support), "Strategic never grants Local")
		test.expect(content.active_on("1900-01-01") and not content.active_on("1901-01-01"), "Circa1900 snapshot interval is honest")
		for feature: Dictionary in content.features:
			test.expect(not identities.has(str(feature.id)), "Unique global stable ID")
			identities[str(feature.id)] = true
			all_features[str(feature.id)] = feature
			counts[str(feature.kind)] = int(counts.get(str(feature.kind),0))+1
			for key: String in ["source_reference","source_id","source_date","source_type","confidence","uncertainty"]:
				# Physical source references resolve via their admitted source record.
				if key != "source_reference" or str(feature.kind) in ["settlement","rail"]:
					test.expect(feature.has(key), "Evidence metadata " + key)
			for key: String in ["owner","controller_id","polity_id","administrative_region_id"]:
				test.expect(not feature.has(key), "Display geography has no " + key)
		var lods: Array[String] = ["coarse","medium"]
		var prepared := LocalSpatialLod.prepare(content.line_chunks,lods)
		test.expect(not (prepared.chunks as Array).is_empty(), "Prepared finite geometry " + str(descriptor.id))
	for kind: String in counts:
		test.equal(int(counts[kind]),int(index.counts[kind]),"Catalogue count matches admitted " + kind)
	for feature: Dictionary in all_features.values():
		if str(feature.kind) != "rail": continue
		test.equal(feature.geometry_role,"APPROXIMATE_STRATEGIC_CORRIDOR","No surveyed-track claim")
		var points := feature.geometry.coordinates as Array
		test.equal(points.size(),(feature.places as Array).size(),"Corridor topology count")
		for i: int in range(points.size()):
			var id := str(feature.places[i])
			test.expect(all_features.has(id),"Corridor endpoint identity exists")
			test.equal(points[i],(all_features[id] as Dictionary).geometry.coordinates,"Corridor resolves actual declared locator")
	test.expect(all_features.has("lake:caspiansea"),"Caspian physical reference")
	test.expect(not identities.has("global:paris_lille"),"No parallel Paris rail identity")
	var damaged := (all_features["place:paris"] as Dictionary).duplicate(true)
	damaged["owner"] = "france"
	test.expect(not StrategicSpatialLoader.valid_feature(damaged), "Reject physical reference with ownership")
	damaged.erase("owner")
	damaged.geometry.coordinates = [400.0,50.0]
	test.expect(not StrategicSpatialLoader.valid_feature(damaged), "Reject invalid coordinates")
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	var saved := (app.get("_persistence") as FormalPersistence).snapshot()
	var renderer := app.map_renderer
	test.equal(int(renderer.strategic_content.metrics.file_reads),0,"Person startup loads no strategic content")
	app.main_shell.set_page("map")
	for lap: int in range(3):
		for coordinate: Vector2 in [Vector2(10,49),Vector2(114,34),Vector2(-90,40),Vector2(-60,-25),Vector2(25,-10),Vector2(78,23),Vector2(137,36),Vector2(10,49)]:
			app.map_controller.region_camera.enter(GlobeProjection.lon_lat_to_unit(coordinate),renderer.size*0.5,1.2,0,renderer.size)
			app.map_controller.view_changed.emit()
			renderer._ensure_view()
			await _settle(renderer)
			test.expect((renderer.strategic_content.metrics.active_regions as Array).size()<=2,"Region residency bounded")
			test.expect(renderer.strategic_layer.available_lods.size()<=1,"GPU only active strategic LOD")
			test.expect(not app.map_controller.region_camera.local_active,"Global backbone never enters Local")
	var draws := renderer.render_draw_count
	var reads := int(renderer.strategic_content.metrics.file_reads)
	var admissions := int(renderer.strategic_content.metrics.source_admissions)
	var prepares := renderer.strategic_layer.prepare_count
	await create_timer(0.2).timeout
	test.equal(renderer.render_draw_count,draws,"Idle zero map redraw")
	test.equal(int(renderer.strategic_content.metrics.file_reads),reads,"Idle zero file parse")
	test.equal(int(renderer.strategic_content.metrics.source_admissions),admissions,"Idle zero admission")
	test.equal(renderer.strategic_layer.prepare_count,prepares,"Idle zero geometry rebuild")
	test.expect(not renderer.is_processing(),"Idle zero map process")
	app.main_shell.set_page("person")
	await process_frame
	test.expect(renderer.strategic_layer.available_lods.is_empty(),"Hidden GPU resources released")
	test.expect(renderer.strategic_content.content == null,"Hidden CPU region data released")
	test.equal(saved,(app.get("_persistence") as FormalPersistence).snapshot(),"Whole World/save unchanged")
	test.equal(FormalPersistence.SCHEMA_ID,"formal_world_simulation_v14","Save v14 unchanged")
	app.queue_free()
	await process_frame
	test.finish(self,"Global strategic geography R1")
