extends SceneTree
## Review only: the real Formal scene, its existing map controls, no time advance.
const OUTPUT: String = "res://local-artifacts/territory-closure"
var app: FormalWorldApplication

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	app = (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	if app.get("_world") == null or not app.historical_content.errors.is_empty():
		push_error("Formal scene/content initialization failed")
		quit(1)
		return
	app.main_shell.set_page("map")
	app.map_controller.select("")
	app.map_controller.suspend_motion()
	var before := "before" in OS.get_cmdline_user_args()
	var phase := "before" if before else "after"
	var counts := {"feature_count": app.map_renderer.content.feature_ids().size(), "loader_count": 0, "projection_count": 0, "render_count": 0}
	counts["source_feature_count"] = 0
	counts["source_count"] = 0
	for source_path: String in [GeographyLoader.GEOMETRY_PATH, GeographyLoader.SUPPLEMENT_PATH]:
		var source := JSON.parse_string(FileAccess.get_file_as_string(source_path)) as Dictionary
		for feature: Dictionary in source.get("features", []) as Array:
			counts.source_feature_count += 1
			var geometry := feature.geometry as Dictionary
			counts.source_count += 1 if str(geometry.type) == "Polygon" else (geometry.coordinates as Array).size()
	for feature_id: String in app.map_renderer.content.feature_ids():
		counts.loader_count += app.map_renderer.content.parts(feature_id).size()
		var components: Dictionary = {}
		for triangle: Dictionary in (app.map_renderer._source_meshes[feature_id] as Dictionary).triangles:
			components[int(triangle.component_index)] = true
		counts.projection_count += components.size()
		counts.render_count += components.size()
	counts["geometry_lost"] = int(counts.loader_count) - int(counts.projection_count)
	if int(counts.loader_count) < 1604 or int(counts.geometry_lost) != 0 or counts.source_count != counts.loader_count or counts.source_feature_count != counts.feature_count:
		push_error("Geometry accounting regression; capture stopped")
		quit(1)
		return
	var output := {"phase": phase, "date": (app.get("_world") as WorldState).game_clock.current_date(), "geometry": counts, "records": app.map_renderer.political.records, "visuals": app.map_renderer.political.resolved_visuals, "screenshots": []}
	output["checkpoints"] = {}
	var checkpoints := {"Riyadh / Nejd": Vector2(46.675, 24.713), "Hail": Vector2(41.683, 27.521), "Aden": Vector2(45.03, 12.78), "Hadramaut": Vector2(49.1, 15.9), "Kuwait": Vector2(47.98, 29.37), "Qatar": Vector2(51.53, 25.29), "Bahrain": Vector2(50.586, 26.223)}
	for name: String in checkpoints:
		var matched: Array[String] = []
		for feature_id: String in app.map_renderer.content.feature_ids():
			for part: Dictionary in app.map_renderer.content.parts(feature_id):
				if not Geometry2D.is_point_in_polygon(checkpoints[name], part.outer):
					continue
				var in_hole := false
				for hole: PackedVector2Array in part.holes:
					in_hole = in_hole or Geometry2D.is_point_in_polygon(checkpoints[name], hole)
				if not in_hole and not matched.has(feature_id):
					matched.append(feature_id)
		output.checkpoints[name] = matched
	var shots: Array[Dictionary] = [
		{"name": "arabia_gulf", "center": Vector2(47.0, 23.0), "zoom": 3.4},
		{"name": "southern_africa", "center": Vector2(25.0, -24.5), "zoom": 2.7},
	]
	if not before:
		shots.append_array([
			{"name": "riyadh_nejd", "center": Vector2(44.5, 26.0), "zoom": 5.0},
			{"name": "aden_hadramaut", "center": Vector2(48.0, 15.0), "zoom": 5.5},
			{"name": "qatar_bahrain_kuwait", "center": Vector2(50.0, 27.7), "zoom": 6.0},
			{"name": "rhodesia", "center": Vector2(28.0, -16.5), "zoom": 4.3},
			{"name": "world_scale", "center": Vector2(15.0, 8.0), "zoom": 1.0},
			{"name": "white_visual_note", "center": Vector2(72.0, 33.0), "zoom": 3.5},
		])
	for shot: Dictionary in shots:
		var close_review := not before and str(shot.name) in ["riyadh_nejd", "aden_hadramaut", "qatar_bahrain_kuwait", "rhodesia"]
		if app.map_controller.labels_enabled != close_review:
			app.map_controller.toggle_labels()
		app.map_controller.focus(GlobeProjection.lon_lat_to_unit(shot.center))
		app.map_controller.zoom = float(shot.zoom)
		app.map_controller.view_changed.emit()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := OUTPUT.path_join(phase + "_" + str(shot.name) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Screenshot save failed: " + path)
			quit(1)
			return
		(output.screenshots as Array).append(path)
		print("SCREENSHOT=" + path)
	var file := FileAccess.open(OUTPUT.path_join(phase + "_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  "))
	print("GEOMETRY_COUNTS=" + JSON.stringify(counts))
	app.queue_free()
	await process_frame
	quit(0)
