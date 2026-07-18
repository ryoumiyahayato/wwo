class_name V2LifeLoopMenu
extends Control
## Dedicated V2.2 launcher. It never routes into the legacy P0-R1 menu or grid map.

const LIFE_LOOP_SCENE: String = "res://scenes/v2_2/v2_2_life_loop_main.tscn"
const LAUNCH_MODE_META: StringName = &"v2_2_launch_mode"

@onready var new_button: Button = %NewReviewButton
@onready var load_button: Button = %LoadReviewButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	DisplayServer.window_set_title("《1900》— V2.2 人物生活闭环")
	new_button.pressed.connect(_start_new_review)
	load_button.pressed.connect(_load_review)
	quit_button.pressed.connect(_quit)
	_refresh_load_state()
	new_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		get_viewport().set_input_as_handled()


func _start_new_review() -> void:
	get_tree().set_meta(LAUNCH_MODE_META, "new")
	_open_life_loop()


func _load_review() -> void:
	if load_button.disabled:
		return
	get_tree().set_meta(LAUNCH_MODE_META, "load")
	_open_life_loop()


func _quit() -> void:
	get_tree().quit()


func _open_life_loop() -> void:
	var error: Error = get_tree().change_scene_to_file(LIFE_LOOP_SCENE)
	if error == OK:
		return
	status_label.text = "无法打开 V2.2 世界地图：%s" % error_string(error)
	status_label.add_theme_color_override("font_color", Color("#d88a74"))


func _refresh_load_state() -> void:
	var primary: String = GameSaveService.V2_2_REVIEW_PATH
	var backup: String = primary + ".bak"
	var available: bool = FileAccess.file_exists(primary) or FileAccess.file_exists(backup)
	load_button.disabled = not available
	status_label.text = (
		"检测到 V2.2 评审存档，可直接载入。"
		if available
		else "尚无 V2.2 评审存档；进入世界地图后可随时保存。"
	)
