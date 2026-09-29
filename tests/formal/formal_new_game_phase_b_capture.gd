extends Node

const MENU_SCENE := "res://scenes/formal/formal_world_menu.tscn"
const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_person_entry/phase_b"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var menu := (load(MENU_SCENE) as PackedScene).instantiate() as FormalWorldMenu
	add_child(menu)
	await _settle_frames(12)
	_save_viewport("B01_title_new_load_quit.png")

	menu._on_new_game_pressed()
	await _settle_frames(10)
	_save_viewport("B02_character_origin.png")

	menu._on_next_pressed()
	await _settle_frames(10)
	_save_viewport("B03_candidate_cards.png")
	if menu._candidates.is_empty():
		push_error("Phase B capture: no candidates")
		get_tree().quit(1)
		return
	menu._on_candidate_pressed(0)
	await _settle_frames(8)
	_save_viewport("B04_confirm.png")

	var candidate := menu._candidates[0]
	var result := menu._new_game_service.create_new_game(
		str(candidate.get("candidate_token", "")), "capture:phase_b"
	)
	if not bool(result.get("success", false)):
		push_error("Phase B capture: %s" % str(result.get("message", "create failed")))
		get_tree().quit(1)
		return
	var world := result.get("world") as FormalWorldSimulation
	menu.queue_free()
	await _settle_frames(2)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(28)
	application.economy_panel_open = false
	application.active_hud_panel = "character"
	application.queue_redraw()
	await _settle_frames(10)
	if application.formal_simulation.player_person_id() != world.player_person_id():
		push_error("Phase B capture: delivered world changed player")
		get_tree().quit(1)
		return
	_save_viewport("B05_new_player_home.png")
	application.queue_free()
	get_tree().quit(0)


func _save_viewport(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		push_error("Phase B capture failed: %s" % error_string(error))
		get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame
