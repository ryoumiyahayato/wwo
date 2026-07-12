extends Control
## Public profile by default; hidden diagnostics are not visible in formal play.

@onready var title_label: Label = %TitleLabel
@onready var public_label: RichTextLabel = %PublicLabel
@onready var developer_toggle: CheckButton = %DeveloperToggle
@onready var developer_panel: PanelContainer = %DeveloperPanel
@onready var developer_label: RichTextLabel = %DeveloperLabel
@onready var event_button: Button = %EventButton
@onready var back_button: Button = %BackButton

var _config: CharacterGenerationConfig


func _ready() -> void:
	_config = CharacterGenerationConfig.load_from_file()
	developer_panel.visible = false
	developer_toggle.visible = GameSessionService.developer_mode
	event_button.visible = GameSessionService.developer_mode
	developer_toggle.toggled.connect(_on_developer_toggled)
	event_button.pressed.connect(_on_event_pressed)
	back_button.pressed.connect(_on_back_pressed)
	if not GameSessionService.has_player() or not _config.is_valid():
		title_label.text = "没有可显示的人物"
		public_label.text = "请先从主菜单创建随机人物。"
		developer_toggle.disabled = true
		event_button.disabled = true
		return
	_render()


func _render() -> void:
	var character: CharacterData = GameSessionService.player_character
	title_label.text = "%s · 人物信息" % character.name
	public_label.text = "[font_size=18]%s，%d岁[/font_size]\n%s · %s\n\n公开职位：%s\n性格表现：%s\n\n当前状态\n%s\n\n可见技能\n%s\n\n已知倾向\n%s" % [
		character.name,
		character.age,
		character.occupation,
		("困难开局" if character.is_challenge_start else "常规开局"),
		(character.public_position if not character.public_position.is_empty() else "无"),
		_format_traits(character.manifested_traits),
		_format_values(character.current_status, "current_status"),
		_format_values(character.skills, "skills"),
		_format_values(character.known_tendencies, "tendencies"),
	]
	developer_label.text = "[color=#efb96a]开发者隐藏数据[/color]\n种子 %d · RNG 状态 %d\n\n潜质（影响成长，不在正式信息中显示）\n%s\n\n气质权重\n%s\n\n真实倾向\n%s" % [
		character.generation_seed,
		character.random_state,
		_format_values(character.hidden_aptitudes, "aptitudes"),
		_format_values(character.temperament_weights, "traits"),
		_format_values(character.tendencies, "tendencies"),
	]


func _format_traits(keys: Array[String]) -> String:
	var output: Array[String] = []
	for key: String in keys:
		output.append(_config.get_label("traits", key))
	return "、".join(output) if not output.is_empty() else "尚未显现"


func _format_values(values: Dictionary, label_group: String) -> String:
	var keys: Array[String] = []
	for raw_key: Variant in values:
		keys.append(str(raw_key))
	keys.sort()
	var lines: Array[String] = []
	for key: String in keys:
		var label: String = _config.get_label(label_group, key) if not label_group.is_empty() else key
		var value_text: String = str(values[key])
		if label_group == "current_status":
			value_text = _config.get_label("status_values", value_text.to_lower())
		lines.append("%s  %s" % [label, value_text])
	return "\n".join(lines)


func _on_developer_toggled(enabled: bool) -> void:
	developer_panel.visible = enabled


func _on_event_pressed() -> void:
	if not GameSessionService.developer_mode:
		return
	CharacterTendencyService.new(_config).apply_event(
		GameSessionService.player_character, "propaganda"
	)
	_render()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/strategic_map_view.tscn")
