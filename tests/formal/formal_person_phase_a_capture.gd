extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_person_entry/phase_a"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(28)
	if application == null or not application.formal_simulation.initialized:
		push_error("Phase A capture: Formal application failed to initialize")
		get_tree().quit(1)
		return
	application.economy_panel_open = false
	application.active_hud_panel = ""
	application.queue_redraw()
	await _settle_frames(10)
	_save_viewport("A01_default_formal_person_home.png")

	application.active_hud_panel = "character"
	application.queue_redraw()
	await _settle_frames(10)
	_save_viewport("A02_formal_person_detail.png")

	application.active_hud_panel = ""
	application.selected_country_id = "state:german_empire"
	application.economy_panel_open = true
	application._set_info_open(true)
	application._mark_projection_dirty()
	application.queue_redraw()
	await _settle_frames(12)
	if application.formal_simulation.player_person_id() != application.player_card_person_id():
		push_error("Phase A capture: map selection changed visible player identity")
		get_tree().quit(1)
		return
	_save_viewport("A03_other_polity_player_unchanged.png")
	application.queue_free()
	get_tree().quit(0)


func _save_viewport(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		push_error("Phase A capture failed: %s" % error_string(error))
		get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame
