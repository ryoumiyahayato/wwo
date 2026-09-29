extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_observation_r1/o1"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var service := FormalNewGameService.new()
	var preview := service.preview_player_candidates({
		"population_origin_id": "country_fra",
		"start_place_id": "place:lille",
		"birth_year_min": 1860,
		"birth_year_max": 1882,
		"random_origin": false,
		"locked_fields": {},
		"seed": 19000101,
		"rules_version": FormalNewGameService.RULES_VERSION,
		"draft_index": 0,
	})
	if not bool(preview.get("success", false)):
		_fail("preview failed")
		return
	var candidate := (preview.get("candidates", []) as Array)[0] as Dictionary
	var created := service.create_new_game(str(candidate.get("candidate_token", "")), "capture:observation:o1")
	if not bool(created.get("success", false)):
		_fail(str(created.get("message", "create failed")))
		return
	var world := created.get("world") as FormalWorldSimulation
	world.advance_minutes(30 * 24 * 60)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(32)
	if application.formal_simulation.player_person_id() != world.player_person_id():
		_fail("delivered world changed player")
		return
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_ECONOMY)
	await _settle_frames(5)
	_save_viewport("O1_01_economy_overview.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_MARKETS)
	await _settle_frames(4)
	_save_viewport("O1_02_market_browser.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_COMMODITIES)
	await _settle_frames(4)
	_save_viewport("O1_03_commodity_browser.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_SHORTAGES)
	await _settle_frames(4)
	_save_viewport("O1_04_shortages.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_TRANSPORT)
	await _settle_frames(4)
	_save_viewport("O1_05_transport.png")
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_FULFILLMENT)
	await _settle_frames(36)
	_save_viewport("O1_06_map_fulfillment.png")
	application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_SHORTAGE)
	await _settle_frames(8)
	_save_viewport("O1_07_map_shortage.png")
	application.queue_free()
	get_tree().quit(0)


func _save_viewport(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		_fail("capture smaller than 1280x720")
		return
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		_fail(error_string(error))


func _fail(message: String) -> void:
	push_error("O1 capture: %s" % message)
	get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame
