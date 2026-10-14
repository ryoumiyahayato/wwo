extends SceneTree

const SAVE_SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")
const FRA: String = "country_fra"
const DEU: String = "german_empire"
var test := FormalTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var built := WorldBootstrap.new().build()
	test.expect(built.success, "Formal Population world builds: " + built.error)
	if not built.success:
		test.finish(self, "Formal Population integration")
		return
	var world := built.world
	var population := world.population_state
	var initial_total: int = 0
	for unit_id: String in population.unit_ids():
		test.equal(population.population(unit_id), world.population_input_view.population(unit_id), "Initial total matches admitted input: " + unit_id)
		test.equal(world.economy_state.current_population(unit_id), population.population(unit_id), "Economy reads same statistical unit: " + unit_id)
		initial_total += population.population(unit_id)
	test.equal(initial_total, 1_411_020_000, "Supported total excludes eight residual aggregates")
	test.equal(population.unit(FRA)["named_person_count"], 1, "Existing player covers one historical person")
	test.equal(population.unit(FRA)["remaining_background_population"], 40_699_999, "Existing player consumes background, not new population")
	_conservation(population)
	test.equal(population.unit_for_place("place:paris"), FRA, "Paris resolves to France aggregate without city allocation")
	test.equal(population.unit_for_polity("cshapes_gw_901"), "australia_colonies_1900", "Explicit six-colony crosswalk resolves")
	test.equal(population.unit_for_polity("grand_duchy_of_luxembourg"), "kingdom_of_luxembourg", "Explicit Luxembourg alias resolves")
	test.equal(population.population("residual:french_indochina"), -1, "Unsupported residual has unavailable total, not zero")
	test.equal(population.unit("place:paris"), {}, "No fabricated Paris statistical total")
	test.equal(population.place_support("place:unknown"), "UNKNOWN", "Unknown place is explicitly unknown")
	test.equal(population.place_support("place:london"), "UNSUPPORTED", "Existing London place has no admitted explicit alias for its british_empire parent")
	test.equal(population.unit_for_place("place:london"), "", "Unsupported real place is not guessed from name or modern ISO")
	test.expect(not world.person_overlay.materialize("person:unsupported", "claim:unsupported", "british_isles_1900", {"basis": "generated"}, "place:london", {"basis": "generated"}), "Unsupported real place cannot materialize against a guessed population mapping")
	var partial := FormalWorldPopulationState.new()
	test.expect(partial.configure({"fingerprint": "fixture", "records": [{"economy_entity_id": "fixture", "population": {"value": 1}}]}, {}, {"place:known": "fixture", "place:unmapped": ""}), "Partial population fixture builds")
	test.equal(partial.place_support("place:unmapped"), "UNSUPPORTED", "Known unmapped place is explicitly unsupported")
	test.expect(partial.materialize_named_person("person:one", "fixture", "place:known"), "One-person population can be materialized")
	var exhausted := partial.snapshot()
	test.expect(not partial.materialize_named_person("person:two", "fixture", "place:known"), "Exhausted background rejects materialization")
	test.equal(partial.snapshot(), exhausted, "Failed materialization cannot create negative background")
	var person_id := world.player_state.player_id()
	var person := world.person_overlay.person(person_id)
	test.equal(person["population_territory_id"], population.unit_for_place(person["current_place_id"]), "Person claim and Spatial place share population identity")
	var before := population.snapshot()
	test.expect(not population.materialize_named_person(person_id, FRA, "place:paris"), "Repeated player initialization rejects duplicate coverage")
	test.expect(not population.transfer_population(FRA, DEU, 40_700_000), "Transfer cannot move reserved named coverage")
	test.expect(not population.transfer_population(FRA, "unknown", 1), "Unknown destination cannot acquire fabricated population")
	test.equal(population.snapshot(), before, "Failed operations are atomic")
	test.expect(not world.person_overlay.materialize("person:wrong_place", "claim:wrong", FRA, {"basis": "generated"}, "place:berlin", {"basis": "generated"}), "Person cannot claim France while residing in Berlin")
	test.equal(population.snapshot(), before, "Invalid Person creation leaves Population unchanged")
	test.expect(world.person_overlay.materialize("person:second", "claim:second", FRA, {"basis": "generated"}, "place:paris", {"basis": "generated"}), "Formal overlay materializes directly into current Population")
	test.equal(population.unit(FRA)["named_person_count"], 2, "Materialization increments named coverage")
	test.equal(population.population(FRA), 40_700_000, "Materialization preserves historical total")
	var registry := VNextTerritorySourceRegistry.new()
	test.expect(registry.configure_from_path(), "Existing territory source policy loads")
	test.equal(registry.admitted_sources().size(), 1, "Qualified Paris pilot does not change Population authority")
	before = population.snapshot()
	test.expect(world.territory_state.set_controller("paris", DEU), "Current controller can change independently")
	test.equal(population.snapshot(), before, "Controller change leaves all Population facts unchanged")
	var baseline := WorldBootstrap.new().build()
	test.expect(baseline.success, "Unchanged economy comparison world builds")
	test.expect(population.transfer_population(FRA, DEU, 1_000_000), "Explicit background transfer conserves global population")
	test.equal(world.population_input_view.population(FRA), 40_700_000, "Historical evidence remains immutable")
	test.equal(world.economy_state.current_population(FRA), 39_700_000, "Economy reads changed current total immediately")
	built.simulation_step.advance_minutes(24 * 60)
	baseline.simulation_step.advance_minutes(24 * 60)
	var market_id := world.market_registry.market_id_for_economic_aggregate(FRA)
	var current_metrics: Dictionary = world.economy_state.market_states[market_id]["daily_metrics"]
	var baseline_metrics: Dictionary = baseline.world.economy_state.market_states[market_id]["daily_metrics"]
	for commodity_id: String in current_metrics:
		test.expect(is_equal_approx(float(current_metrics[commodity_id]["demand"]), float(baseline_metrics[commodity_id]["demand"]) * 39_700_000.0 / 40_700_000.0), "Next settlement demand uses changed total: " + commodity_id)
	_conservation(population)
	var saved := built.persistence.snapshot()
	var restored := built.persistence.restore_candidate(saved)
	test.expect(restored.success, "Changed Population and additional Person restore together: " + restored.error)
	if restored.success:
		test.equal(restored.persistence.snapshot(), saved, "Save/load exactly preserves changed population and coverage")
		test.equal(restored.persistence.authoritative_fingerprint(), built.persistence.authoritative_fingerprint(), "Population participates in exact world fingerprint")
		_conservation(restored.world.population_state)
	for corruption: String in ["missing_population", "background", "place", "named", "old_v12"]:
		var invalid := saved.duplicate(true)
		match corruption:
			"missing_population": invalid.erase("population")
			"background": invalid["population"]["records"][0]["remaining_background_population"] = -1
			"place": invalid["persons"]["persons"][0]["current_place_id"] = "place:berlin"
			"named": invalid["population"]["named_person_units"].erase(person_id)
			"old_v12": invalid["schema_id"] = "formal_world_simulation_v12"
		var rejected := built.persistence.restore_candidate(invalid)
		test.expect(not rejected.success, "Invalid candidate rejected: " + corruption)
		test.equal(built.persistence.snapshot(), saved, "Rejected candidate leaves installed world exact: " + corruption)
	await _player_journey()
	test.finish(self, "Formal Population integration")


func _conservation(population: FormalWorldPopulationState) -> void:
	for unit_id: String in population.unit_ids():
		var row := population.unit(unit_id)
		test.expect(int(row["remaining_background_population"]) >= 0 and int(row["population_total"]) == int(row["named_person_count"]) + int(row["remaining_background_population"]), "Total = named + background: " + unit_id)


func _player_journey() -> void:
	var backup := SAVE_SUPPORT.backup_formal_save()
	test.expect(not bool(backup["read_error"]), "Existing save files safely preserved for actual application journey")
	if bool(backup["read_error"]):
		return
	root.size = Vector2i(1280, 720)
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	var app := scene.instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	app.main_shell.set_page("person")
	app._refresh_ui()
	var world := app.get("_world") as WorldState
	test.expect(world != null, "Actual new-game application installs Population")
	if world != null:
		test.equal(app.main_shell.person_page.get("_person"), world.person_overlay.person(world.player_state.player_id()), "Person page displays player from installed world")
		test.equal((app.main_shell.person_page.get("_place") as Dictionary)["place_id"], "place:paris", "Person page displays Paris")
		test.expect(not (app.main_shell.person_page.get("_polity") as Dictionary).is_empty(), "Person page displays local political entity")
		app._advance_world(3 * 24 * 60 + 7)
		_conservation(world.population_state)
		var persistence := app.get("_persistence") as FormalPersistence
		test.expect(persistence.save_to_user().success, "Actual application journey writes verified exact save")
		var saved := persistence.snapshot()
		app._advance_world(24 * 60)
		app._load_world()
		var loaded := app.get("_world") as WorldState
		test.expect(loaded != world, "Actual file load installs new validated candidate")
		test.equal((app.get("_persistence") as FormalPersistence).snapshot(), saved, "Actual file load restores exact world")
		_conservation(loaded.population_state)
		test.equal(loaded.population_state.unit(FRA)["named_person_count"], 1, "Load never deducts player twice")
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://local-artifacts/population-r1")
			root.get_texture().get_image().save_png("res://local-artifacts/population-r1/person-journey.png")
	app.queue_free()
	await process_frame
	test.expect(SAVE_SUPPORT.restore_formal_save(backup), "Actual journey restores prior user saves")
