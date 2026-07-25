class_name V23LifeLoopMenu
extends Control
## Minimal product title. Any non-Escape key enters the best available launch path.

const LIFE_LOOP_SCENE: String = "res://scenes/v2_3/v2_3_life_loop_main.tscn"
const LAUNCH_MODE_META: StringName = &"v2_3_launch_mode"
const DISPLAY_VERSION: String = "V0.001"

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var prompt_label: Label = %PromptLabel
@onready var status_label: Label = %StatusLabel

var _entering: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("1900 · %s" % DISPLAY_VERSION)
	title_label.text = "1900"
	version_label.text = DISPLAY_VERSION
	prompt_label.text = "按任意键进入"
	status_label.text = ""
	_wire_legacy_buttons()
	_refresh_state()
	grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		get_tree().quit()
		get_viewport().set_input_as_handled()
		return
	_enter_world()
	get_viewport().set_input_as_handled()


func accepts_entry_event(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key_event := event as InputEventKey
	return key_event.pressed and not key_event.echo and key_event.keycode != KEY_ESCAPE


func resolved_launch_mode() -> String:
	var current_available: bool = (
		FileAccess.file_exists(V23SaveService.REVIEW_PATH)
		or FileAccess.file_exists(V23SaveService.REVIEW_PATH + ".bak")
	)
	if current_available:
		return "load"
	var previous_available: bool = (
		FileAccess.file_exists(GameSaveService.V2_2_REVIEW_PATH)
		or FileAccess.file_exists(GameSaveService.V2_2_REVIEW_PATH + ".bak")
	)
	return "migrate" if previous_available else "new"


func _open(mode: String) -> void:
	_enter_world(mode)


func _enter_world(forced_mode: String = "") -> void:
	if _entering:
		return
	_entering = true
	get_tree().set_meta(LAUNCH_MODE_META, resolved_launch_mode() if forced_mode.is_empty() else forced_mode)
	var error: Error = get_tree().change_scene_to_file(LIFE_LOOP_SCENE)
	if error == OK:
		return
	_entering = false
	status_label.text = "无法打开游戏：%s" % error_string(error)
	status_label.add_theme_color_override("font_color", Color("#c57b67"))


func _wire_legacy_buttons() -> void:
	var actions: Dictionary = {
		"NewReviewButton": "new",
		"LoadReviewButton": "load",
		"MigrateButton": "migrate",
	}
	for node_name: String in actions.keys():
		var button := find_child(node_name, true, false) as Button
		if button != null:
			button.pressed.connect(_open.bind(str(actions[node_name])))
	var quit_button := find_child("QuitButton", true, false) as Button
	if quit_button != null:
		quit_button.pressed.connect(get_tree().quit)


func _refresh_state() -> void:
	var load_button := find_child("LoadReviewButton", true, false) as Button
	var migrate_button := find_child("MigrateButton", true, false) as Button
	if load_button != null:
		load_button.disabled = not (
			FileAccess.file_exists(V23SaveService.REVIEW_PATH)
			or FileAccess.file_exists(V23SaveService.REVIEW_PATH + ".bak")
		)
	if migrate_button != null:
		migrate_button.disabled = not (
			FileAccess.file_exists(GameSaveService.V2_2_REVIEW_PATH)
			or FileAccess.file_exists(GameSaveService.V2_2_REVIEW_PATH + ".bak")
		)
