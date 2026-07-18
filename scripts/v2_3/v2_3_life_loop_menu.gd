class_name V23LifeLoopMenu
extends Control
## Dedicated V2.3 launcher with explicit V2.2 migration.

const LIFE_LOOP_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_main.tscn"
const LAUNCH_MODE_META: StringName = &"v2_3_launch_mode"

@onready var new_button: Button = %NewReviewButton
@onready var load_button: Button = %LoadReviewButton
@onready var migrate_button: Button = %MigrateButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	DisplayServer.window_set_title("《1900》— V2.3 空间与有限认知")
	new_button.pressed.connect(_open.bind("new"))
	load_button.pressed.connect(_open.bind("load"))
	migrate_button.pressed.connect(_open.bind("migrate"))
	quit_button.pressed.connect(get_tree().quit)
	_refresh_state()
	new_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		get_viewport().set_input_as_handled()


func _open(mode: String) -> void:
	get_tree().set_meta(LAUNCH_MODE_META, mode)
	var error: Error = get_tree().change_scene_to_file(LIFE_LOOP_SCENE)
	if error != OK:
		status_label.text = "无法打开 V2.3 世界地图：%s" % error_string(error)
		status_label.add_theme_color_override("font_color", Color("#d88a74"))


func _refresh_state() -> void:
	var v2_3_available: bool = (
		FileAccess.file_exists(V23SaveService.REVIEW_PATH)
		or FileAccess.file_exists(V23SaveService.REVIEW_PATH + ".bak")
	)
	var v2_2_available: bool = (
		FileAccess.file_exists(GameSaveService.V2_2_REVIEW_PATH)
		or FileAccess.file_exists(GameSaveService.V2_2_REVIEW_PATH + ".bak")
	)
	load_button.disabled = not v2_3_available
	migrate_button.disabled = not v2_2_available
	status_label.text = "V2.3 存档：%s · 可迁移 V2.2：%s" % [
		"可用" if v2_3_available else "无",
		"是" if v2_2_available else "否",
	]
