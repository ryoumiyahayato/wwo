extends SceneTree
## Runtime independence and installed-world identity, using existing test support.

var test := FormalTestCase.new()
const SAVE_SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var built := WorldBootstrap.new().build()
	test.expect(built.success, "World constructs without a UI scene")
	if not built.success:
		test.finish(self, "Formal application architecture")
		return
	var world: WorldState = built.world
	var step := built.simulation_step
	var persistence := built.persistence
	built = null
	test.expect(not bool(step.advance_minutes(59).get("economy", false)), "Sub-hour advance preserves settlement boundary")
	test.equal(world.game_clock.current_hour(), 0, "59 minutes remains hour zero")
	step.advance_minutes(1)
	test.equal(world.game_clock.current_hour(), 1, "Split advance crosses hour")
	test.equal(world.spatial_world.current_hour(), 1, "Spatial follows clock")
	test.equal(int(world.economy_state.world_summary()["total_hour"]), 1, "Economy follows clock")
	var change := step.advance_minutes(23 * 60 + 7)
	test.equal(int(change["responsibility_review_days"]), 1, "Cross-day advance reviews Organization once")
	test.equal(world.game_clock.current_date()["day"], 2, "Current date crosses day")
	test.equal(world.game_clock.current_date()["minute"], 7, "Minute remainder survives segmented advance")
	test.equal(world.spatial_world.current_hour(), 24, "Spatial follows day boundary")
	test.equal(int(world.economy_state.world_summary()["total_hour"]), 24, "Economy follows day boundary")
	var snapshot := persistence.snapshot()
	test.equal(snapshot.size(), 18, "Current save includes independent Population and personal economy facts")
	test.equal(snapshot["schema_id"], "formal_world_simulation_v14", "Current save schema includes personal accounts and wage periods")
	var candidate := persistence.restore_candidate(snapshot)
	test.expect(candidate.success, "Persistence restores without UI")
	test.expect(candidate.world != world, "Candidate has independent installed-world container")
	test.expect(candidate.world.game_clock != world.game_clock, "Candidate has independent clock owner")
	test.equal(candidate.persistence.snapshot(), snapshot, "Candidate restores exact snapshot")
	var invalid := snapshot.duplicate(true)
	invalid["minute_remainder"] = 8
	var before := persistence.authoritative_fingerprint()
	var rejected := persistence.restore_candidate(invalid)
	test.expect(not rejected.success, "Invalid candidate explicitly rejected")
	test.equal(persistence.authoritative_fingerprint(), before, "Rejected candidate cannot mutate current world")
	var menu := load("res://scenes/formal/formal_world_menu.tscn") as PackedScene
	test.expect(menu != null, "Formal menu scene loads")
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	test.expect(scene != null, "Formal main scene loads")
	var app := scene.instantiate() as FormalWorldApplication
	root.add_child(app)
	await process_frame
	var installed := app.get("_world") as WorldState
	test.expect(installed != null, "Application installs stable WorldState")
	test.expect(app.historical_content.errors.is_empty(), "Content preparation remains successful")
	test.equal((app.main_shell.person_page.get("_person") as Dictionary)["person_id"], installed.player_state.player_id(), "Person page receives installed-world record")
	app._advance_world(24 * 60 + 7)
	test.equal((app.main_shell.get("_date") as Dictionary), installed.game_clock.current_date(), "Time advance refreshes copied UI date")
	app.main_shell.set_page("map")
	test.expect(not app.map_renderer.political.records.is_empty(), "World map has political records")
	var backup: Dictionary = SAVE_SUPPORT.backup_formal_save()
	test.expect(not bool(backup["read_error"]), "Existing save artifacts can be preserved before file test")
	if bool(backup["read_error"]):
		app.queue_free()
		await process_frame
		test.finish(self, "Formal application architecture")
		return
	app._on_action_requested("save")
	var saved := (app.get("_persistence") as FormalPersistence).snapshot()
	var old_view := app.map_renderer.get("_political_view") as RuntimePoliticalEntityView
	app._advance_world(60)
	app._load_world()
	var loaded := app.get("_world") as WorldState
	test.expect(loaded != installed, "Successful load installs candidate world")
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(), saved, "Successful file load restores exact state")
	test.equal(app.main_shell.get("_date"), loaded.game_clock.current_date(), "Successful load refreshes UI date")
	test.expect(app.map_renderer.get("_political_view") != old_view, "Load replaces detached political map input")
	test.equal((app.main_shell.person_page.get("_person") as Dictionary)["person_id"], loaded.player_state.player_id(), "Load refreshes Person page")
	app.queue_free()
	await process_frame
	test.expect(SAVE_SUPPORT.restore_formal_save(backup), "File test restores existing save artifacts")
	test.finish(self, "Formal application architecture")
