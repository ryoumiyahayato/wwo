extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_observation_r1/o2"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(32)
	if not application.formal_simulation.initialized:
		_fail("Formal world did not initialize")
		return
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_POLITICS)
	application._set_politics_tab(FormalWorldApplication.POLITICS_TAB_LOCAL)
	await _settle_frames(5)
	_save_viewport("O2_01_local_politics.png")
	application.selected_country_id = "state:german_empire"
	application._set_politics_tab(FormalWorldApplication.POLITICS_TAB_OBSERVED)
	await _settle_frames(5)
	_save_viewport("O2_02_observed_other_polity.png")
	application._set_politics_tab(FormalWorldApplication.POLITICS_TAB_COMPARE)
	await _settle_frames(5)
	_save_viewport("O2_03_local_vs_observed.png")
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
	push_error("O2 capture: %s" % message)
	get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame
