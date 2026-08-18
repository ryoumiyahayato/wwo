class_name FormalWorldMenu
extends Control
## Product title for the formal hemisphere world. It does not instantiate or
## migrate the retired V2.3 flat-map product scene.

const WORLD_SCENE: String = "res://scenes/formal/formal_world_main.tscn"
const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
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
	prompt_label.text = "按任意键进入正式世界"
	status_label.text = "已有正式世界存档，将自动继续。" if _formal_save_exists() else "将建立新的1900世界。"
	grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	_enter_world("load" if _formal_save_exists() else "new")
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _enter_world(mode: String) -> void:
	if _entering:
		return
	_entering = true
	get_tree().set_meta(LAUNCH_MODE_META, mode)
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error == OK:
		return
	_entering = false
	status_label.text = "无法打开正式世界：%s" % error_string(error)
	status_label.add_theme_color_override("font_color", Color("#c57b67"))


func _formal_save_exists() -> bool:
	return FileAccess.file_exists(FormalWorldSimulation.SAVE_PATH)
