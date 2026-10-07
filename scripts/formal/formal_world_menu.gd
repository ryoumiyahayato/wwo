class_name FormalWorldMenu
extends Control
## Product title for the formal hemisphere world. It does not instantiate or
## migrate the retired V2.3 flat-map product scene.

const WORLD_SCENE: String = "res://scenes/formal/formal_world_main.tscn"
const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
const LIVELIHOOD_META: StringName = &"formal_world_livelihood"
const DISPLAY_VERSION: String = "V0.001"

@onready var title_label: Label = %TitleLabel
@onready var version_label: Label = %VersionLabel
@onready var prompt_label: Label = %PromptLabel
@onready var status_label: Label = %StatusLabel
@onready var livelihood_choice: OptionButton = %LivelihoodChoice
@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton

var _entering: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("1900 · %s" % DISPLAY_VERSION)
	title_label.text = "1900"
	version_label.text = DISPLAY_VERSION
	prompt_label.text = "选择生计后建立新世界，或继续已有存档"
	livelihood_choice.add_item("暂无正式工作", 0)
	livelihood_choice.add_item("一般工资劳动", 1)
	new_game_button.pressed.connect(_enter_world.bind("new"))
	continue_button.pressed.connect(_enter_world.bind("load"))
	continue_button.disabled = not _formal_save_exists()
	status_label.text = "可继续读取正式世界存档。" if _formal_save_exists() else "将建立新的1900世界。"
	grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	# Consume the key while this Control still belongs to its viewport. A
	# successful scene change removes the menu before this callback returns.
	get_viewport().set_input_as_handled()
	if key_event.keycode != KEY_ENTER:
		return
	_enter_world("load" if _formal_save_exists() else "new")


func _enter_world(mode: String) -> void:
	if _entering:
		return
	_entering = true
	get_tree().set_meta(LAUNCH_MODE_META, mode)
	if mode == "new":
		get_tree().set_meta(LIVELIHOOD_META, FormalPersonalEconomyState.GENERAL_WAGE_LABOR if livelihood_choice.get_selected_id() == 1 else FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT)
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error == OK:
		return
	_entering = false
	status_label.text = "无法打开正式世界：%s" % error_string(error)
	status_label.add_theme_color_override("font_color", Color("#c57b67"))


func _formal_save_exists() -> bool:
	return FileAccess.file_exists(FormalPersistence.SAVE_PATH)
