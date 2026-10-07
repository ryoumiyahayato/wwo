extends SceneTree
var test := FormalTestCase.new()
var observations: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _wait(renderer: GlobeRenderer) -> void:
	var deadline := Time.get_ticks_msec()+15000
	while (not renderer.local_layer.ready or renderer.local_layer.preparing or renderer.region_view.preparing) and Time.get_ticks_msec()<deadline:
		await create_timer(0.01).timeout
	test.expect(renderer.local_layer.ready and not renderer.local_layer.preparing,"Requested LOD finishes finite preparation")
	await process_frame

func _right(renderer: GlobeRenderer, pixel: Vector2, amount: float) -> void:
	var button := InputEventMouseButton.new()
	button.position = pixel
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	renderer._gui_input(button)
	var motion := InputEventMouseMotion.new()
	motion.position = pixel+Vector2(amount,0.0)
	motion.relative = Vector2(amount,0.0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	renderer._gui_input(motion)
	button.pressed = false
	renderer._gui_input(button)

func _run() -> void:
	root.size = Vector2i(1280,720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	var controller := app.map_controller
	var camera := controller.region_camera
	var layer := renderer.local_layer
	var pixel := renderer.size*0.5
	var paris := GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR)
	var saved := (app.get("_persistence") as FormalPersistence).snapshot()
	controller.select("state:country_fra","place:paris")
	controller.labels_enabled = true
	controller.focus(paris)
	renderer._ensure_view()
	var picked_pixel := pixel+Vector2(60.0,25.0)
	var picked := renderer.unit_at(picked_pixel)
	var zoom := controller.zoom
	_right(renderer,picked_pixel,40.0)
	var world_anchor_error := renderer.screen_point(picked).distance_to(picked_pixel)
	test.expect(world_anchor_error<0.02,"WORLD right drag fixes off-centre geographic anchor")
	test.equal(controller.zoom,zoom,"Right drag preserves zoom")
	var attitude := controller.orientation()
	_right(renderer,picked_pixel,0.0)
	test.equal(controller.orientation(),attitude,"Right click has no rotation")
	var world_bearing := RegionProjection.world_bearing(paris,controller.orientation())
	# Actual existing scale handoff keeps the rotated WORLD attitude.
	var restored := RegionProjection.restore_world(paris,pixel,pixel,5.3,world_bearing)
	controller._orientation = (restored.orientation as Basis).get_rotation_quaternion()
	controller.zoom = float(restored.radius)/minf(renderer.size.y/2.55,renderer.size.x*.49)
	controller.view_changed.emit()
	renderer.set("_last_pointer",pixel)
	renderer._evaluate_scale()
	await create_timer(3.0).timeout
	test.expect(camera.active,"Rotated WORLD enters REGION")
	test.expect(absf(wrapf(camera.bearing-world_bearing,-PI,PI))<0.002,"WORLD to REGION preserves right-drag bearing")
	camera.km_per_pixel = 4.5
	controller.view_changed.emit()
	renderer._ensure_view()
	renderer._evaluate_scale()
	await _wait(renderer)
	test.equal(layer.available_lods.keys(),["coarse"],"FAR prepares only needed GPU LOD")
	test.equal((layer.metrics.lod_stats as Dictionary).keys(),["coarse"],"FAR does not simplify or prepare future LODs")
	test.expect(MapScaleStyle.physical_weight("river",4500)>0.05 and MapScaleStyle.physical_weight("coast",4500)>0.2,"FAR physical structure starts visibly")
	test.expect(MapScaleStyle.physical_weight("rail",2000)>0.8,"MID early already has readable rail weight")
	var regional_point := pixel+Vector2(110,25)
	var regional_anchor := camera.unit_at(regional_point)
	_right(renderer,regional_point,30.0)
	test.expect(camera.project(regional_anchor).distance_to(regional_point)<0.02,"REGION right drag fixes off-centre anchor")
	var regional_bearing := camera.bearing
	var prepares := layer.prepare_count
	for scale: float in [1.2,0.35,0.188]:
		camera.km_per_pixel = scale
		controller.view_changed.emit()
		renderer._ensure_view()
		renderer._evaluate_scale()
		await _wait(renderer)
		renderer._evaluate_scale()
		test.equal(layer.available_lods.size(),1,"Active-only steady GPU bound is one LOD")
		test.equal(layer.active_lod,MapScaleStyle.lod(scale*1000.0),"Prepared LOD matches current actual scale")
		test.expect(layer.resident_buffer_bytes()>0,"Current area retains its drawable batch")
	test.expect(camera.local_active,"Ready supported 188 mpp enters LOCAL")
	test.equal(camera.bearing,regional_bearing,"REGION right drag remains continuous at LOCAL entry")
	var bearing := camera.bearing
	var before_point := camera.unit_at(pixel+Vector2(110,25))
	var glyphs := renderer.region_view.glyph_submit_count
	var local_uploads := (layer.metrics.lod_upload_counts as Dictionary).duplicate()
	var geometry_queries := renderer.cpu_projection_count
	_right(renderer,pixel+Vector2(110,25),30.0)
	var planar_anchor_error := camera.project(before_point).distance_to(pixel+Vector2(110,25))
	test.expect(planar_anchor_error<0.02,"Planar right drag fixes off-centre anchor")
	test.expect(camera.bearing!=bearing,"Right drag adjusts sole planar bearing")
	test.equal(layer.metrics.lod_upload_counts,local_uploads,"Bearing never rebuilds or uploads line geometry")
	test.equal(renderer.region_view.glyph_submit_count,glyphs,"Bearing never rebuilds label sources")
	test.equal(renderer.cpu_projection_count,geometry_queries,"Bearing never CPU-projects all geography")
	observations.append({"world_anchor_error_px":world_anchor_error,"planar_anchor_error_px":planar_anchor_error,"new_geometry_queries":renderer.cpu_projection_count-geometry_queries,"new_label_glyphs":renderer.region_view.glyph_submit_count-glyphs})
	var draw_count := renderer.render_draw_count
	await create_timer(.1).timeout
	draw_count = renderer.render_draw_count
	var view_count := renderer.view_update_count
	await create_timer(.2).timeout
	test.equal(renderer.render_draw_count,draw_count,"Idle has no map redraw")
	test.equal(renderer.view_update_count,view_count,"Idle has no view/uniform/label work")
	test.equal(layer.prepare_count,prepares,"LOD transitions keep one source preparation owner")
	test.equal(app.historical_content.local_spatial.load_count,1,"LOD transitions never reparse sources")
	var exit_bearing := camera.bearing
	camera.km_per_pixel = .30
	controller.view_changed.emit()
	renderer.set("_last_pointer",camera.project(paris))
	renderer._ensure_view()
	renderer._evaluate_scale()
	test.expect(not camera.local_active and camera.active,"Rotated LOCAL exits into REGION")
	test.equal(camera.bearing,exit_bearing,"LOCAL exit keeps bearing exactly")
	camera.km_per_pixel = 7.1
	controller.view_changed.emit()
	renderer.set("_last_pointer",camera.project(paris))
	renderer._ensure_view()
	renderer._evaluate_scale()
	await create_timer(.4).timeout
	test.expect(not camera.active,"Rotated REGION exits into WORLD")
	test.expect(absf(wrapf(RegionProjection.world_bearing(paris,controller.orientation())-exit_bearing,-PI,PI))<.002,"RMB bearing survives complete round trip")
	# Leaving the active area releases all line and glyph GPU resources.
	camera.enter(GlobeProjection.lon_lat_to_unit(Vector2(116.4074,39.9042)),pixel,0.188,0.0,renderer.size)
	controller.view_changed.emit()
	renderer.set("_last_pointer",pixel)
	renderer._ensure_view()
	renderer._evaluate_scale()
	await process_frame
	test.equal(layer.resident_buffer_bytes(),0,"Unsupported area holds no Paris GPU lines")
	test.expect(layer.visible_places.is_empty() and not camera.local_active,"Paris cannot leak into Beijing")
	test.expect(app.historical_content.local_spatial.content!=null,"Single parsed CPU shard retained for cheap return")
	camera.enter(paris,pixel,0.188,0.0,renderer.size)
	controller.view_changed.emit()
	renderer._ensure_view()
	renderer._evaluate_scale()
	await _wait(renderer)
	renderer._evaluate_scale()
	test.expect(camera.local_active,"Returning area reuploads and restores supported LOCAL")
	test.equal(app.historical_content.local_spatial.load_count,1,"Return reuses canonical CPU data")
	# Deliberately distant chart is a supported pointer but invalid LOCAL chart.
	camera.enter(GlobeProjection.lon_lat_to_unit(Vector2(15.0,48.85)),pixel,0.188,0.0,renderer.size)
	camera.origin = pixel - RegionProjection.screen_axes(camera.bearing)*(RegionProjection.forward(paris,camera.tangent_frame)/camera.km_per_pixel)
	controller.view_changed.emit()
	renderer.set("_last_pointer",pixel)
	renderer._ensure_view()
	renderer._evaluate_scale()
	test.expect(not camera.local_active,"188 mpp retains REGION if chart offset exceeds 500 km")
	observations.append({"mpp":188,"local_ready":layer.available_lods.has("local"),"supported":LocalSpatialLoader.covers(RegionProjection.lon_lat(camera.unit_at(pixel))),"chart_offset_km":RegionProjection.forward(paris,camera.tangent_frame).length(),"result":"REGION"})
	test.equal(controller.selected_place_id,"place:paris","Bearing and lifecycle preserve selection")
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(),saved,"Camera/resource changes preserve entire v14 snapshot")
	DirAccess.make_dir_recursive_absolute("res://local-artifacts/map-resource-r2")
	var file := FileAccess.open("res://local-artifacts/map-resource-r2/anchor-and-handoff.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(observations,"  "))
	app.queue_free()
	await process_frame
	test.finish(self,"Map resource efficiency R2")
