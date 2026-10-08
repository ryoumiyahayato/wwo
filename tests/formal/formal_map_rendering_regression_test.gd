extends SceneTree
## Source accounting, small-face picking and detached UI facts after batching.

var test := FormalTestCase.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	var world := app.get("_world") as WorldState
	test.expect(world != null, "Real formal application initializes")
	if world == null:
		app.queue_free()
		test.finish(self, "Formal map rendering regression")
		return
	app.main_shell.set_page("map")
	var renderer := app.map_renderer
	var batches := renderer.get("_surface_batches") as Dictionary
	var boundaries := renderer.get("_boundary_batches") as Array[Dictionary]
	test.equal(boundaries.size(), 3, "Coast and both macro strokes are actually submitted")
	var submitted_faces: int = 0
	for batch: Dictionary in batches.values():
		var mesh := (batch.geometry as GlobeSurfaceBatch).mesh
		submitted_faces += int((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector2Array).size() / GlobeSurfaceBatch.VERTICES_PER_FACE)
	test.equal(submitted_faces, int(renderer.political.display_accounting.display_pieces), "GPU buffers retain every display face")
	test.equal(submitted_faces, 51788, "Current 1900 display tessellation is unchanged")
	var source_segments: Dictionary = {"coast": 0, "macro": 0}
	for boundary: Dictionary in renderer.get("_source_boundaries") as Array:
		source_segments[str(boundary.kind)] += (boundary.points as PackedVector3Array).size() - 1
	test.equal((boundaries[0].geometry as GlobeBoundaryBatch).segment_count, source_segments.coast, "Coast batch retains all source segments")
	test.equal((boundaries[1].geometry as GlobeBoundaryBatch).segment_count, source_segments.macro, "Macro batch retains all source segments")
	test.expect((boundaries[1].geometry as GlobeBoundaryBatch) == (boundaries[2].geometry as GlobeBoundaryBatch), "Both macro strokes share geometry, keeping separate widths")
	var first_mesh := (batches.values()[0] as Dictionary).geometry as GlobeSurfaceBatch
	app._advance_world(60)
	test.expect(((renderer.get("_surface_batches") as Dictionary).values()[0] as Dictionary).geometry == first_mesh, "Economic settlement does not recreate display geometry")
	app.main_shell.set_page("person")
	var displayed_date := renderer.political.display_date
	app._advance_world(24 * 60)
	test.equal(renderer.political.display_date, displayed_date, "Hidden presentation remains unrefreshed")
	test.equal(world.spatial_world.current_hour(), 25, "Hidden map does not stop Spatial")
	test.equal(world.economy_state.total_hour, 25, "Hidden map does not stop Economy")
	app.main_shell.set_page("map")
	test.equal(renderer.political.display_date, "1900-01-02", "Visible map catches up to current date")
	for target: Vector2 in [Vector2(2.35, 48.85), Vector2(45.0, 24.0), Vector2(120.0, 32.0), Vector2(0.0, 89.0)]:
		app.map_controller.focus(GlobeProjection.lon_lat_to_unit(target))
		app.map_controller.zoom = 1.55
		app.map_controller.view_changed.emit()
		renderer._ensure_projection()
		var projected := renderer.get("_projected_surfaces") as Dictionary
		var sampled: int = 0
		for owner: String in projected:
			var faces := projected[owner] as Array
			var face := faces[int(faces.size() / 2)] as Dictionary
			var polygon := face.points as PackedVector2Array
			var point := Vector2.ZERO
			for vertex: Vector2 in polygon:
				point += vertex
			point /= polygon.size()
			test.equal(renderer._polity_at(point), _reference_pick(projected, renderer.political.records, point), "Source-bounded picking agrees with retained screen faces")
			sampled += 1
			if sampled >= 20:
				break
	var tiny_face := {"points": PackedVector3Array([Vector3(0.000001, 0.000001, 1.0), Vector3(0.00003, 0.000001, 1.0), Vector3(0.000001, 0.00003, 1.0)]), "uvs": PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]), "component_index": 0}
	var tiny := GlobeSurfaceBatch.new()
	tiny.prepare([tiny_face])
	var point := Vector2(0.001, -0.001)
	test.expect(tiny.contains_screen_point(Vector3(0.00001, 0.00001, 1.2), Vector3.FORWARD, Basis(), point, Vector2.ZERO, 100.0), "Small faces are not rejected by a 3D ray triangle epsilon")
	var observation := world.economy_state.read_only_presentation_snapshot()
	var full := world.economy_state.read_only_snapshot()
	test.equal(observation.world_summary, full.world_summary, "Narrow presentation retains complete world summary")
	var view := FormalWorldEconomyView.new(observation)
	for economy_id: String in observation.country_summaries:
		var narrow := observation.country_summaries[economy_id] as Dictionary
		var original := full.country_summaries[economy_id] as Dictionary
		for key: String in narrow:
			test.equal(narrow[key], original[key], "Displayed economy fact matches full observation: " + key)
		var market_id := view.market_id_for_economic_aggregate(economy_id)
		test.equal(view.economic_aggregate_id_for_market(market_id), economy_id, "Narrow observation preserves market identity")
	(observation.country_summaries as Dictionary).clear()
	test.equal(view.country_summary("country_fra").population, world.population_state.population("country_fra"), "Detached UI observation keeps current Population total")
	app.queue_free()
	await process_frame
	test.finish(self, "Formal map rendering regression")

func _reference_pick(projected: Dictionary, records: Dictionary, point: Vector2) -> String:
	for owner: String in projected:
		for face: Dictionary in projected[owner]:
			if Geometry2D.is_point_in_polygon(point, face.points as PackedVector2Array):
				return str((records[owner] as Dictionary).get("runtime_entity_id", owner))
	return ""
