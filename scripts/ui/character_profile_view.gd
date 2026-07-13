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
	var dossiers: Variant = character.current_status.get("investigation_dossiers", {})
	title_label.text = "%s · 人物信息" % character.name
	public_label.text = "[font_size=18]%s，%d岁[/font_size]\n%s · %s\n\n公开职位：%s\n性格表现：%s\n\n当前状态\n%s\n\n可见技能\n%s\n\n已知倾向\n%s\n\n调查档案\n%s" % [
		character.name,
		character.age,
		character.occupation,
		("困难开局" if character.is_challenge_start else "常规开局"),
		(character.public_position if not character.public_position.is_empty() else "无"),
		_format_traits(character.manifested_traits),
		_format_status(character.current_status),
		_format_values(character.skills, "skills"),
		_format_values(character.known_tendencies, "tendencies"),
		_format_dossiers(dossiers as Dictionary if dossiers is Dictionary else {}),
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


func _format_status(values: Dictionary) -> String:
	var filtered: Dictionary = {}
	for raw_key: Variant in values:
		var key: String = str(raw_key)
		if key == "investigation_dossiers":
			continue
		if values[raw_key] is Dictionary or values[raw_key] is Array:
			continue
		filtered[key] = values[raw_key]
	return _format_values(filtered, "current_status")


func _format_dossiers(dossiers: Dictionary) -> String:
	if dossiers.is_empty():
		return "尚无。完成“调查人物”行动后将在此显示定性档案。"
	var ids: Array[String] = []
	for raw_id: Variant in dossiers:
		ids.append(str(raw_id))
	ids.sort()
	var sections: Array[String] = []
	for target_id: String in ids:
		var raw_dossier: Variant = dossiers[target_id]
		if not raw_dossier is Dictionary:
			continue
		var dossier: Dictionary = raw_dossier as Dictionary
		var tendency_lines: Array[String] = []
		var raw_tendencies: Variant = dossier.get("tendencies", {})
		if raw_tendencies is Dictionary:
			var tendency_ids: Array[String] = []
			for raw_key: Variant in raw_tendencies as Dictionary:
				tendency_ids.append(str(raw_key))
			tendency_ids.sort()
			for tendency_id: String in tendency_ids:
				tendency_lines.append("%s：%s" % [
					_config.get_label("tendencies", tendency_id),
					_config.describe_tendency(tendency_id, int((raw_tendencies as Dictionary)[tendency_id])),
				])
		var position: String = str(dossier.get("public_position", ""))
		sections.append("[b]%s[/b]，%d岁 · %s\n公开职位：%s\n性格表现：%s\n倾向判断：%s" % [
			str(dossier.get("name", target_id)),
			int(dossier.get("age", 0)),
			str(dossier.get("occupation", "未知职业")),
			(position if not position.is_empty() else "无"),
			_format_traits(DataRecordUtils.to_string_array(dossier.get("traits", []))),
			("；".join(tendency_lines) if not tendency_lines.is_empty() else "信息不足"),
		])
	return "\n\n".join(sections) if not sections.is_empty() else "尚无有效档案。"


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
	return "\n".join(lines) if not lines.is_empty() else "无"


func _on_developer_toggled(enabled: bool) -> void:
	developer_panel.visible = enabled


func _on_event_pressed() -> void:
	if not GameSessionService.developer_mode:
		return
	CharacterTendencyService.new(_config).apply_event(GameSessionService.player_character, "propaganda")
	_render()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/strategic_map_view.tscn")
