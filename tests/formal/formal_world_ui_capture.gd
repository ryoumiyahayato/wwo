extends Node

const MENU_SCENE := "res://scenes/formal/formal_world_menu.tscn"
const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_ui"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var menu := (load(MENU_SCENE) as PackedScene).instantiate() as Control
	add_child(menu)
	await _settle_frames(8)
	_save_viewport("00_formal_world_title.png")
	menu.queue_free()
	await _settle_frames(3)
	get_tree().set_meta(&"formal_world_launch_mode", "new")
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(main)
	await _settle_frames(24)
	if main == null or not main.formal_simulation.initialized:
		push_error("Formal world capture: formal hemisphere failed to initialize")
		get_tree().quit(1)
		return
	main.economy_panel_open = false
	main.queue_redraw()
	await _settle_frames(12)
	_save_viewport("01_formal_hemisphere_clean.png")
	main.economy_panel_open = true
	main.queue_redraw()
	await _settle_frames(12)
	_save_viewport("02_formal_polity_economy.png")
	main.queue_free()
	get_tree().quit(0)


func _save_viewport(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		push_error("Formal world capture failed: %s" % error_string(error))
		get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame
