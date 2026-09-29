extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_person_entry/phase_c"


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
	var created := service.create_new_game(str(candidate.get("candidate_token", "")), "capture:phase_c")
	if not bool(created.get("success", false)):
		_fail(str(created.get("message", "creation failed")))
		return
	var world := created.get("world") as FormalWorldSimulation
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(28)
	if application.formal_simulation.player_person_id() != world.player_person_id():
		_fail("delivered world changed player")
		return

	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_PERSON, "C01_person_home.png")
	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_ECONOMY, "C02_work_economy.png")
	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_RELATIONS, "C03_relations_information_unavailable.png")
	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_ORGANIZATION, "C04_organization.png")
	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_POLITICS, "C05_politics.png")
	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_MILITARY, "C06_military_empty.png")
	await _capture_workspace(application, FormalWorldApplication.WORKSPACE_MAP, "C07_map_world.png")
	var player_before := application.formal_simulation.player_person_id()
	application._ensure_projection_cache()
	var target_id := "state:german_empire"
	var anchor := application._country_screen_anchors.get(target_id, Vector2.INF) as Vector2
	if anchor == Vector2.INF:
		_fail("German Empire anchor unavailable")
		return
	application._packaged_probe_mouse_button(anchor, true)
	application._packaged_probe_mouse_button(anchor, false)
	await _settle_frames(10)
	if application.selected_country_id != target_id:
		_fail("map click did not select target polity")
		return
	application.info_open = false
	application.info_progress = 0.0
	application.economy_panel_open = true
	application.queue_redraw()
	await _settle_frames(4)
	if application.formal_simulation.player_person_id() != player_before:
		_fail("selected polity changed player")
		return
	_save_viewport("C08_selected_polity_player_unchanged.png")
	application.queue_free()
	get_tree().quit(0)


func _capture_workspace(application: FormalWorldApplication, workspace_id: String, filename: String) -> void:
	if not application.set_formal_workspace(workspace_id):
		_fail("invalid workspace %s" % workspace_id)
		return
	await _settle_frames(10)
	_save_viewport(filename)


func _save_viewport(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		_fail("capture is smaller than 1280x720")
		return
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		_fail(error_string(error))


func _fail(message: String) -> void:
	push_error("Phase C capture: %s" % message)
	get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame
