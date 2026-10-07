extends SceneTree
## Captures the real Formal scene without advancing its simulation.
const OUTPUT: String = "res://local-artifacts/arabia-display-reset-r1"
var app: FormalWorldApplication

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	app = (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	if app.get("_world") == null or not app.historical_content.errors.is_empty():
		push_error("Formal initialization failed: " + str(app.historical_content.errors))
		quit(1)
		return
	app.main_shell.set_page("map")
	app.map_controller.select("")
	app.map_controller.suspend_motion()
	var counts := {"features":0,"source_exteriors":0,"loader":0,"projection_retained":0,"render_retained":0}
	for path: String in [GeographyLoader.GEOMETRY_PATH, GeographyLoader.SUPPLEMENT_PATH]:
		var document := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
		for feature: Dictionary in document.features as Array:
			counts.features += 1
			counts.source_exteriors += 1 if str(feature.geometry.type) == "Polygon" else (feature.geometry.coordinates as Array).size()
	for feature_id: String in app.map_renderer.content.feature_ids():
		counts.loader += app.map_renderer.content.parts(feature_id).size()
		var projected: Dictionary = {}
		var retained: Dictionary = {}
		for face: Dictionary in (app.map_renderer._source_meshes[feature_id] as Dictionary).triangles:
			projected[int(face.component_index)] = true
		for face: Dictionary in app.map_renderer.political.display_faces_by_feature[feature_id] as Array:
			retained[int(face.component_index)] = true
		counts.projection_retained += projected.size()
		counts.render_retained += retained.size()
	counts["geometry_lost"] = int(counts.source_exteriors) - int(counts.render_retained)
	if counts.features != 161 or counts.source_exteriors != 1634 or counts.loader != 1634 or counts.projection_retained != 1634 or counts.geometry_lost != 0:
		push_error("Source geometry accounting changed: " + str(counts))
		quit(1)
		return
	var shots: Array[Dictionary] = [
		{"name":"02_arabia_after_labels_off","center":Vector2(46.5,23.5),"zoom":4.6,"labels":false},
		{"name":"03_central_rashidi","center":Vector2(44.6,26.5),"zoom":6.0,"labels":false},
		{"name":"04_hejaz_hasa","center":Vector2(44.8,25.0),"zoom":5.5,"labels":false},
		{"name":"05_yemen_aden_hadramaut","center":Vector2(47.0,17.0),"zoom":6.0,"labels":false},
		{"name":"06_gulf_oman","center":Vector2(53.0,24.8),"zoom":6.0,"labels":false},
		{"name":"07_labels_on","center":Vector2(46.5,23.5),"zoom":4.6,"labels":true},
		{"name":"08_world_scale","center":Vector2(15,8),"zoom":1.0,"labels":false},
	]
	var output := {"date":(app.get("_world") as WorldState).game_clock.current_date(),"geometry":counts,"screenshots":[],"regions":{}}
	for owner: String in app.map_renderer.political.region_frames:
		if not app.map_renderer.political.visual_textures.has(owner):
			push_error("PoliticalMapRegion has no complete representative flag: "+owner)
			quit(1)
			return
		var visual := app.map_renderer.political.resolved_visuals[owner] as Dictionary
		(output.regions as Dictionary)[owner] = {"visual":visual.id,"asset":visual.display_asset,"frame":app.map_renderer.political.region_frames[owner]}
	for shot: Dictionary in shots:
		if app.map_controller.labels_enabled != bool(shot.labels):
			app.map_controller.toggle_labels()
		app.map_controller.focus(GlobeProjection.lon_lat_to_unit(shot.center))
		app.map_controller.zoom = float(shot.zoom)
		app.map_controller.view_changed.emit()
		app.main_shell.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := OUTPUT.path_join(str(shot.name)+".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Formal screenshot failed: " + path)
			quit(1)
			return
		(output.screenshots as Array).append({"path":path,"labels":shot.labels,"zoom":shot.zoom})
		print("SCREENSHOT="+path)
	var file := FileAccess.open(OUTPUT.path_join("capture_manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"  "))
	print("GEOMETRY="+JSON.stringify(counts))
	app.queue_free()
	await process_frame
	quit(0)
