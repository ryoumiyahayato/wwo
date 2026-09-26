extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/formal_observation_r1/o3"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var world := FormalWorldSimulation.new()
	if not world.initialize():
		_fail("Formal world did not initialize")
		return
	world.advance_minutes(30 * 24 * 60)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(32)
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_ORGANIZATION)
	application._set_organization_tab(FormalWorldApplication.ORGANIZATION_TAB_MY_RECORDS)
	await _settle_frames(5)
	_save_viewport("O3_01_my_records.png")
	application._set_organization_tab(FormalWorldApplication.ORGANIZATION_TAB_BROWSER)
	await _settle_frames(5)
	_save_viewport("O3_02_organization_browser.png")
	if not application._select_organization("organization:gov_country_fra"):
		_fail("France governing organization is unavailable")
		return
	await _settle_frames(5)
	_save_viewport("O3_03_organization_detail.png")
	application._set_organization_tab(FormalWorldApplication.ORGANIZATION_TAB_RESPONSIBILITY)
	await _settle_frames(5)
	_save_viewport("O3_04_responsibility.png")
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
	push_error("O3 capture: %s" % message)
	get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame
