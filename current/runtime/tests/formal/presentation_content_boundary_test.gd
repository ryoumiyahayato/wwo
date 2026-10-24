extends SceneTree
## Exercises the real scene and frozen content across date and load boundaries.

var test := FormalTestCase.new()
const SAVE_SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")
const OUTPUT: String = "res://local-artifacts/b7/visual"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://scenes/formal/formal_world_main.tscn") as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	await process_frame
	var world := app.get("_world") as WorldState
	test.expect(world != null, "Formal scene installs current world")
	if world == null:
		app.queue_free()
		test.finish(self, "Presentation content boundary")
		return
	var content := app.historical_content
	var units := FormalWorldPresenter.map_units(world)
	var date := world.game_clock.current_date()
	var first := content.resolve_map(date, units)
	test.equal(first.date(), "1900-01-01", "Content date derives from GameClock")
	test.equal(content.resolve_map(date, units).display_document(), first.display_document(), "Same-day region resolution is stable")
	test.equal(content.resolve_map(date, units).visual("state:country_fra"), first.visual("state:country_fra"), "Same-day flag evidence is stable")
	var copy := first.units()
	copy[0]["name_zh"] = "mutated copy"
	test.expect(first.units()[0].get("name_zh") != "mutated copy", "Map unit output is detached")
	var visual := first.visual("state:country_fra")
	visual["confidence"] = "mutated copy"
	test.expect(first.visual("state:country_fra").get("confidence") != "mutated copy", "Visual provenance output is detached")
	var feature_id := str(content.geometry_content.feature_ids()[0])
	var parts := content.geometry_content.parts(feature_id)
	parts.clear()
	test.expect(not content.geometry_content.parts(feature_id).is_empty(), "Geometry output is detached")
	var without_france: Array[Dictionary] = []
	for unit: Dictionary in units:
		if str(unit.id) != "state:country_fra":
			without_france.append(unit)
	var recreated := false
	for unit: Dictionary in content.resolve_map(date, without_france).units():
		recreated = recreated or str(unit.id) == "state:country_fra"
	test.expect(not recreated, "Content cannot recreate a runtime polity omitted by current view")
	var uncertain := ResolvedMapContent.new("1900-01-01", [], {}, {"fixture": {"basis": "UNKNOWN", "value": null, "lower_bound": null, "upper_bound": null}})
	test.equal(uncertain.visual("fixture"), {"basis": "UNKNOWN", "value": null, "lower_bound": null, "upper_bound": null}, "Detached output preserves UNKNOWN and null bounds")
	var future := content.resolve_map({"year": 1901, "month": 1, "day": 1}, units)
	test.expect(not first.display_document().is_empty(), "1900 display region document is active")
	test.expect(future.display_document().is_empty(), "1901 excludes expired display region document")
	var afghan := ""
	var afghan_unit: Dictionary = {}
	for unit: Dictionary in units:
		if str(unit.get("flag_id", "")) == "afghanistan_1880":
			afghan = str(unit.id)
			afghan_unit = unit
	test.expect(not afghan.is_empty(), "Existing Afghanistan identity found through current view")
	test.expect(first.texture(afghan) != null, "Dated Afghanistan flag texture is available in 1900")
	test.expect(future.texture(afghan) == null, "Expired Afghanistan flag resolves to texture-free fallback")
	test.equal(future.visual(afghan).get("historical_design_claim"), false, "Fallback does not fabricate a historical flag")
	test.expect(content.resolve_world_page(date, afghan_unit).texture() != null, "Dossier flag uses the current valid interval")
	var expired_page := content.resolve_world_page({"year": 1901, "month": 1, "day": 1}, afghan_unit)
	test.expect(expired_page.texture() == null, "Dossier stops displaying an expired historical flag")
	test.equal(expired_page.flag(), content.evidence.flag_record("afghanistan_1880"), "Expired dossier still retains complete historical evidence")
	app.map_controller.select("state:country_fra")
	var page := content.resolve_world_page(date, FormalWorldPresenter.selected_world_polity(world, app.map_controller))
	var raw_flag := content.evidence.flag_record(str(FormalWorldPresenter.selected_world_polity(world, app.map_controller).get("flag_id", "")))
	test.equal(page.flag(), raw_flag, "Dossier preserves complete flag evidence and source fields")
	test.expect(page.texture() != null, "WorldPage flag texture is prepared by Content")
	test.expect(not page.profile().is_empty(), "Selected polity has profile content")
	test.equal(page.administration().get("coverage_status"), "PARTIAL_IDENTITY_ONLY", "France dossier admits partial historical identities only")
	test.equal(page.administration().get("geometry_status"), "ADMIN_BOUNDARY_DATA_GAP", "Identity evidence cannot imply boundaries")
	app.map_controller.select("state:german_empire")
	var german_page := content.resolve_world_page(date, FormalWorldPresenter.selected_world_polity(world, app.map_controller))
	test.expect(not german_page.administration().is_empty(), "Available German historical administration remains present")
	var detached_admin := german_page.administration()
	detached_admin.clear()
	test.expect(not german_page.administration().is_empty(), "Administration output is detached")
	app.map_controller.select("state:country_fra")
	test.equal((app.main_shell.world_page.get("_polity") as Dictionary)["id"], "state:country_fra", "WorldPage receives selected current polity")
	var previous_date := app.map_renderer.political.display_date
	app._advance_world(59)
	test.equal(app.map_renderer.political.display_date, previous_date, "Same-day sub-hour advance retains dated map content")
	test.equal((app.main_shell.get("_date") as Dictionary)["minute"], 59, "UI minute uses the sole clock")
	app._advance_world(24 * 60 - 59)
	test.equal(app.map_renderer.political.display_date, previous_date, "Hidden map does not prepare cross-day presentation")
	test.equal((app.main_shell.get("_date") as Dictionary)["day"], 2, "Cross-day page date refreshes")
	app.main_shell.set_page("map")
	test.equal(app.map_renderer.political.display_date, "1900-01-02", "Showing map resolves the latest clock date")
	var backup: Dictionary = SAVE_SUPPORT.backup_formal_save()
	test.expect(not bool(backup["read_error"]), "Existing user save can be preserved")
	if not bool(backup["read_error"]):
		app._on_action_requested("save")
		var saved := (app.get("_persistence") as FormalPersistence).snapshot()
		var old_evidence := world.historical_evidence_view
		var old_geometry := app.map_renderer.content
		app._advance_world(364 * 24 * 60)
		test.equal(app.map_renderer.political.display_date, "1901-01-01", "Real one-year clock advance reaches content interval boundary")
		test.expect(not app.map_renderer.political.visual_textures.has(afghan), "Real date advance removes expired map flag")
		app._load_world()
		world = app.get("_world") as WorldState
		test.equal((app.get("_persistence") as FormalPersistence).snapshot(), saved, "Load preserves exact save schema and state")
		test.equal(app.main_shell.get("_date"), world.game_clock.current_date(), "Load refreshes copied UI date")
		test.equal(app.map_renderer.political.display_date, "1900-01-02", "Load resolves content using newly installed date")
		test.expect(app.historical_content != content, "Load replaces content admission bound to previous world")
		test.expect(app.map_renderer.content != old_geometry, "Load replaces detached geometry binding")
		test.expect(world.historical_evidence_view != old_evidence, "Load replaces evidence view")
		test.expect(app.map_renderer.political.visual_textures.has(afghan), "Load restores valid flag from new date")
		test.equal(app.map_controller.selected_polity_id, "state:country_fra", "Load retains valid selected polity")
		test.equal((app.main_shell.world_page.get("_polity") as Dictionary)["id"], "state:country_fra", "Load refreshes selected WorldPage")
		test.equal(app.main_shell.world_page.get("_flag"), page.flag(), "Load restores complete dossier evidence")
		app.map_controller.select("state:country_fra", "place:missing_fixture")
		app._load_world()
		test.equal(app.map_controller.selected_place_id, "", "Load clears a place selection absent from installed Spatial world")
		test.equal(app.map_controller.selected_polity_id, "state:country_fra", "Invalid place cleanup retains a valid polity")
		app.map_controller.select("state:country_fra", "place:paris")
		app._load_world()
		test.equal(app.map_controller.selected_place_id, "place:paris", "Load retains a valid city selection")
		test.equal((app.main_shell.world_page.get("_place") as Dictionary).get("place_id"), "place:paris", "Load refreshes the retained city page record")
		test.expect(SAVE_SUPPORT.restore_formal_save(backup), "Test restores original user save artifacts")
	var cities := 0
	var ports := 0
	for place: Dictionary in app.map_renderer.political.places.values():
		cities += 1 if str(place.get("spatial_kind", "")) == "city" else 0
		ports += 1 if str(place.get("spatial_kind", "")) == "port" else 0
	test.expect(cities > 0, "City records come from current Spatial world")
	test.expect(ports > 0, "Port records come from current Spatial world")
	app.main_shell.set_page("map")
	app.map_controller.focus(GlobeProjection.lon_lat_to_unit(Vector2(2.35, 48.85)))
	app.map_controller.zoom = 4.8
	app.map_controller.view_changed.emit()
	await process_frame
	app.map_renderer._ensure_projection()
	var points := app.map_renderer.get("_place_points") as Dictionary
	var visible_port := false
	for place_id: String in points:
		visible_port = visible_port or str((app.map_renderer.political.places[place_id] as Dictionary).get("spatial_kind", "")) == "port"
	test.expect(visible_port, "Port markers project normally alongside cities")
	test.expect(points.has("place:paris"), "Paris marker projects normally")
	if points.has("place:paris"):
		var point := points["place:paris"] as Vector2
		test.equal(app.map_renderer._place_at(point), "place:paris", "City hit testing retains place ID")
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = point
			app.map_renderer._gui_input(event)
		test.equal(app.map_controller.selected_place_id, "place:paris", "City click selects current city")
		test.equal(app.map_controller.selected_polity_id, "state:country_fra", "City click selects current runtime polity")
		test.equal((app.main_shell.world_page.get("_place") as Dictionary)["place_id"], "place:paris", "City click refreshes WorldPage place record")
	test.expect(not (app.map_renderer.get("_projected_surfaces") as Dictionary).is_empty(), "Map has drawable territory fill")
	test.expect(not app.map_renderer.political.visual_textures.is_empty(), "Map has resolved flag textures")
	test.expect(not (app.main_shell.economy_page.get("_summary") as Dictionary).is_empty(), "Economy page retains detached input")
	test.expect(not (app.main_shell.person_page.get("_person") as Dictionary).is_empty(), "Person page retains detached input")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		for name: String in ["map_city", "person", "economy", "organization", "politics", "administration", "map"]:
			app.main_shell.set_page("map" if name == "map_city" else name)
			if name == "map":
				app.map_controller.select("state:country_fra")
				app.map_controller.zoom = 0.86
				app.map_controller.view_changed.emit()
			elif name == "administration":
				app.map_controller.select("state:german_empire")
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path := OUTPUT.path_join(name + ".png")
			test.equal(root.get_texture().get_image().save_png(path), OK, "Formal UI screenshot: " + name)
			print("B7_SCREENSHOT=" + ProjectSettings.globalize_path(path))
	app.queue_free()
	await process_frame
	test.finish(self, "Presentation content boundary")
