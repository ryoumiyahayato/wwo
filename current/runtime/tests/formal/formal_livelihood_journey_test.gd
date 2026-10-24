extends SceneTree

const SAVE_SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")
var test := FormalTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := SAVE_SUPPORT.backup_formal_save()
	test.expect(not bool(backup["read_error"]), "Player journeys preserve existing save artifacts")
	if bool(backup["read_error"]):
		test.finish(self, "Formal livelihood player journeys")
		return
	root.size = Vector2i(1280, 720)
	await _journey(0, "a")
	await _journey(1, "b")
	test.expect(SAVE_SUPPORT.restore_formal_save(backup), "Player journeys restore prior save artifacts")
	test.finish(self, "Formal livelihood player journeys")


func _journey(choice: int, prefix: String) -> void:
	var menu := (load("res://scenes/formal/formal_world_menu.tscn") as PackedScene).instantiate() as FormalWorldMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	test.equal(menu.livelihood_choice.item_count, 2, "New Game offers precisely two livelihoods")
	menu.livelihood_choice.select(choice)
	await _capture(prefix + "-new-game")
	menu.new_game_button.pressed.emit()
	await process_frame
	await process_frame
	var app := current_scene as FormalWorldApplication
	test.expect(app != null, "Menu New Game enters actual Formal application")
	if app == null:
		return
	app.main_shell.set_page("person")
	app._refresh_ui()
	var world := app.get("_world") as WorldState
	var player_id := world.player_state.player_id()
	var initial_population := world.population_state.snapshot()
	var initial := world.personal_economy_state.person_economy(player_id)
	test.equal(world.population_state.unit_for_place("place:paris"), "country_fra", "Paris player shares current France population")
	test.equal(world.population_state.unit("country_fra")["named_person_count"], 1, "New Game materializes player exactly once")
	test.equal(initial["cash"], 2500, "Actual new player receives recorded opening cash")
	test.equal(app.main_shell.person_page.personal_economy(), initial, "Person page queries authoritative personal economy")
	await _capture(prefix + "-person-opening")
	if DisplayServer.get_name() != "headless":
		var hits := app.main_shell.get("_hits") as Array
		for hit: Dictionary in hits:
			var action := str(hit["action"])
			var rect := hit["rect"] as Rect2
			if action.begins_with("time:") or action == "system":
				test.expect(rect.position.x > 640.0 and rect.end.y < 90.0, "Rendered global control stays top right: " + action)
			elif action == "page:person":
				test.expect(rect.position.x < 640.0, "Rendered primary person entry remains on the left")
		if choice == 1:
			app.main_shell._activate("system")
			await _capture("b-system-top-right")
			app.main_shell._activate("system")
	var employed := choice == 1
	test.equal(initial["livelihood"], FormalPersonalEconomyState.GENERAL_WAGE_LABOR if employed else FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, "Menu livelihood reaches runtime without UI state copy")
	if employed:
		test.equal(initial["payer_balance"], 12000, "Actual wage payer starts with finite reserve")
		test.equal(initial["employment"]["next_pay_boundary"], 10080, "Actual employment first boundary is seven days")
	else:
		test.equal(initial["employment"], {}, "Unemployed page has no fabricated employment")
		test.equal(initial["employer"], {}, "Unemployed page has no fabricated employer")
	app._advance_world(7 * 24 * 60)
	var paid := world.personal_economy_state.person_economy(player_id)
	test.equal(paid["cash"], 3500 if employed else 2500, "Actual time advance credits wages only to employed player")
	test.equal(app.main_shell.person_page.personal_economy(), paid, "Person page reads changed ledger balance directly")
	if employed:
		test.equal(paid["payer_balance"], 11000, "Actual payer debit equals player wage credit")
		test.equal(paid["recent_wage_transaction"]["amount"], 1000, "Recent Wage displays an actual ledger transaction")
	await _capture(prefix + "-person-week-one")
	test.equal(world.population_state.snapshot(), initial_population, "Employment and wages preserve total/named/background population")
	app._on_action_requested("save")
	var persistence := app.get("_persistence") as FormalPersistence
	var saved := persistence.snapshot()
	test.expect(FileAccess.file_exists(FormalPersistence.SAVE_PATH), "Actual Save action writes formal save")
	app._advance_world(24 * 60)
	app._on_action_requested("load")
	world = app.get("_world") as WorldState
	test.equal((app.get("_persistence") as FormalPersistence).snapshot(), saved, "Actual Load action restores exact world and wage periods")
	test.equal(world.personal_economy_state.settle_due_wages()["paid_periods"], 0, "Reentering loaded period cannot pay twice")
	test.equal(world.personal_economy_state.person_economy(player_id), paid, "Load keeps account and employment observations exact")
	await _capture(prefix + "-person-loaded")
	app._advance_world(7 * 24 * 60)
	var next := world.personal_economy_state.person_economy(player_id)
	test.equal(next["cash"], 4500 if employed else 2500, "Next pay period pays once or leaves unemployed cash unchanged")
	if employed:
		test.equal(next["payer_balance"], 10000, "Next actual period consumes finite payer reserve again")
	app.queue_free()
	await process_frame


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://local-artifacts/livelihood-r1/" + name + ".png"
	test.equal(root.get_texture().get_image().save_png(path), OK, "Rendered screenshot: " + name)
