extends Control
## Main menu presentation. Game and simulation logic must remain outside this script.

const UiStrings = preload("res://scripts/ui/ui_strings.gd")

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var milestone_label: Label = %MilestoneLabel
@onready var new_game_button: Button = %NewGameButton
@onready var load_game_button: Button = %LoadGameButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var footer_label: Label = %FooterLabel


func _ready() -> void:
	title_label.text = UiStrings.APP_TITLE
	subtitle_label.text = UiStrings.APP_SUBTITLE
	milestone_label.text = UiStrings.MILESTONE_LABEL
	new_game_button.text = UiStrings.MENU_NEW_GAME
	load_game_button.text = UiStrings.MENU_LOAD_GAME
	settings_button.text = UiStrings.MENU_SETTINGS
	quit_button.text = UiStrings.MENU_QUIT
	footer_label.text = UiStrings.FOOTER

	new_game_button.disabled = false
	new_game_button.tooltip_text = ""
	load_game_button.disabled = not FileAccess.file_exists(GameSaveService.MANUAL_PATH)
	load_game_button.tooltip_text = "没有手动存档" if load_game_button.disabled else "加载手动存档"
	settings_button.tooltip_text = UiStrings.FUTURE_FEATURE_TOOLTIP
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	LogService.info("MainMenu", "基础主菜单已就绪")


func _on_new_game_pressed() -> void:
	var change_error: Error = get_tree().change_scene_to_file(
		"res://scenes/character/character_setup_view.tscn"
	)
	if change_error != OK:
		LogService.error("MainMenu", "无法打开人物创建界面：%s" % error_string(change_error))


func _on_load_game_pressed() -> void:
	GameSessionService.clear()
	GameSessionService.pending_load_path = GameSaveService.MANUAL_PATH
	var change_error: Error = get_tree().change_scene_to_file("res://scenes/map/strategic_map_view.tscn")
	if change_error != OK:
		GameSessionService.pending_load_path = ""
		LogService.error("MainMenu", "无法打开存档地图：%s" % error_string(change_error))


func _on_quit_pressed() -> void:
	LogService.info("MainMenu", "收到退出请求")
	get_tree().quit()
