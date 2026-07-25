extends Node

const MENU_SCENE := "res://scenes/v2_3/v2_3_life_loop_menu.tscn"
const MAIN_SCENE := "res://scenes/v2_3/v2_3_life_loop_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_ui"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var menu := (load(MENU_SCENE) as PackedScene).instantiate() as Control
	add_child(menu)
	await _settle_frames(8)
	_save_viewport("00_title_v0001.png")
	menu.queue_free()
	await _settle_frames(3)
	get_tree().set_meta(&"v2_3_launch_mode", "new")
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as Control
	add_child(main)
	await _settle_frames(24)
	var interface := main.get_node_or_null("PrototypeInterface") as Control
	if interface == null:
		push_error("Formal UI capture: PrototypeInterface missing")
		get_tree().quit(1)
		return
	_save_method_inventory(interface)
	_save_viewport("01_main_hud_closed.png")
	var overlay := interface.get_node_or_null("MinimalHudOverlay") as Control
	if overlay == null:
		push_error("Formal UI capture: MinimalHudOverlay missing")
		get_tree().quit(1)
		return
	overlay.call("set_field_book_open", true)
	await _settle_frames(30)
	_save_viewport("02_field_book_open.png")
	main.queue_free()
	get_tree().quit(0)


func _save_method_inventory(interface: Object) -> void:
	var names := PackedStringArray()
	for method_value: Variant in interface.get_method_list():
		var method := method_value as Dictionary
		var name := str(method.get("name", ""))
		if name.begins_with("_draw_"):
			names.append(name)
	names.sort()
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("corner_methods.txt"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Formal UI capture: cannot write draw method inventory")
		get_tree().quit(1)
		return
	file.store_string("\n".join(names))


func _save_viewport(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		push_error("Formal UI capture failed: %s" % error_string(error))
		get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame
