extends Control
## Structured public profile. Diagnostics are isolated behind developer mode.

const GOVERNANCE_SKILLS: Array[String] = [
	"administration", "finance", "political_activity", "public_speaking", "social_organization",
]
const MILITARY_SKILLS: Array[String] = ["military_command", "personal_combat", "engineering"]
const INVESTIGATION_SKILLS: Array[String] = ["investigation"]
const STATUS_FIELDS: Array[Dictionary] = [
	{"id": "health", "label": "健康"},
	{"id": "fatigue", "label": "疲劳"},
	{"id": "stress", "label": "压力"},
	{"id": "wealth", "label": "财富"},
	{"id": "reputation", "label": "声望"},
	{"id": "intelligence_points", "label": "情报点"},
	{"id": "employment_status", "label": "就业"},
	{"id": "detained", "label": "被拘留"},
	{"id": "injury", "label": "伤势"},
]
const PERMISSION_LABELS: Dictionary = {
	"organization_member": "组织成员",
	"organization_support": "组织动员",
	"regional_policy": "地区政策",
	"regional_control_support": "地区控制支援",
}

@onready var clock_runner: SimulationRunner = %SimulationRunner
@onready var title_label: Label = %TitleLabel
@onready var clock_label: Label = %ClockLabel
@onready var pause_button: Button = %PauseButton
@onready var developer_toggle: CheckButton = %DeveloperToggle
@onready var back_button: Button = %BackButton
@onready var identity_label: Label = %IdentityLabel
@onready var status_grid: GridContainer = %StatusGrid
@onready var governance_skills: VBoxContainer = %GovernanceSkills
@onready var military_skills: VBoxContainer = %MilitarySkills
@onready var investigation_skills: VBoxContainer = %InvestigationSkills
@onready var traits_label: Label = %TraitsLabel
@onready var organizations_label: RichTextLabel = %OrganizationsLabel
@onready var relationships_label: RichTextLabel = %RelationshipsLabel
@onready var cognition_label: RichTextLabel = %CognitionLabel
@onready var developer_panel: PanelContainer = %DeveloperPanel
@onready var developer_label: RichTextLabel = %DeveloperLabel
@onready var event_button: Button = %EventButton

var _config: CharacterGenerationConfig
var _clock: SimulationClock


func _ready() -> void:
	_config = CharacterGenerationConfig.load_from_file()
	_clock = clock_runner.clock
	developer_panel.visible = false
	developer_toggle.visible = GameSessionService.developer_mode
	event_button.visible = GameSessionService.developer_mode
	developer_toggle.toggled.connect(_on_developer_toggled)
	event_button.pressed.connect(_on_event_pressed)
	pause_button.pressed.connect(_toggle_pause)
	back_button.pressed.connect(_on_back_pressed)
	if _clock != null:
		_clock.time_changed.connect(_on_clock_changed)
		_clock.pause_changed.connect(func(_paused: bool) -> void: _refresh_clock())
	_refresh_clock()
	if not GameSessionService.has_player() or not _config.is_valid():
		title_label.text = "没有可显示的人物"
		identity_label.text = "请先从主菜单创建随机人物。"
		developer_toggle.disabled = true
		event_button.disabled = true
		return
	_render()


func _render() -> void:
	var character: CharacterData = GameSessionService.player_character
	title_label.text = "%s · 人物信息" % character.name
	identity_label.text = "姓名：%s\n年龄：%d 岁\n职业：%s\n地区：%s\n主要职位：%s\n开局类型：%s" % [
		character.name,
		character.age,
		character.occupation,
		_region_name(character.region_id),
		character.public_position if not character.public_position.is_empty() else "暂无正式职位",
		"困难开局" if character.is_challenge_start else "常规开局",
	]
	_render_status(character)
	_render_skill_group(governance_skills, "治理与社会", GOVERNANCE_SKILLS, character)
	_render_skill_group(military_skills, "军事与技术", MILITARY_SKILLS, character)
	_render_skill_group(investigation_skills, "调查", INVESTIGATION_SKILLS, character)
	traits_label.text = _format_traits(character.manifested_traits)
	_render_organizations(character)
	_render_relationships(character)
	_render_cognition(character)
	developer_label.text = "种子：%d · RNG 状态：%d\n\n潜质\n%s\n\n气质权重\n%s\n\n完整倾向\n%s" % [
		character.generation_seed,
		character.random_state,
		_format_values(character.hidden_aptitudes, "aptitudes"),
		_format_values(character.temperament_weights, "traits"),
		_format_values(character.tendencies, "tendencies"),
	]


func _render_status(character: CharacterData) -> void:
	_clear_children(status_grid)
	for field: Dictionary in STATUS_FIELDS:
		var label := Label.new()
		label.text = str(field["label"])
		label.add_theme_color_override("font_color", Color(0.55, 0.74, 0.8))
		status_grid.add_child(label)
		var value := Label.new()
		value.text = _format_status_value(str(field["id"]), character.current_status.get(str(field["id"]), _status_default(str(field["id"]))))
		value.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
		status_grid.add_child(value)


func _render_skill_group(
	container: VBoxContainer,
	title: String,
	skill_ids: Array[String],
	character: CharacterData
) -> void:
	_clear_children(container)
	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", Color(0.75, 0.84, 0.88))
	container.add_child(header)
	for skill_id: String in skill_ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.custom_minimum_size = Vector2(82, 22)
		label.text = _config.get_label("skills", skill_id)
		row.add_child(label)
		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(0, 22)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.max_value = 100.0
		progress.value = float(character.skills.get(skill_id, 0))
		progress.show_percentage = true
		row.add_child(progress)
		container.add_child(row)


func _render_organizations(character: CharacterData) -> void:
	var society: SocietySimulationService = GameSessionService.society_service
	if society == null or character.organization_ids.is_empty():
		organizations_label.text = "尚未加入组织。可从地图的“社会”页面寻找组织并提交加入行动。"
		return
	var sections: Array[String] = []
	for organization_id: String in character.organization_ids:
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		if organization == null:
			continue
		var position_id: String = society.organizations.get_position_id(character.id, organization_id)
		var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
		var position: Dictionary = positions.get(position_id, {}) as Dictionary
		var permissions: Array[String] = DataRecordUtils.to_string_array(position.get("permissions", []))
		var permission_names: Array[String] = []
		for permission: String in permissions:
			permission_names.append(str(PERMISSION_LABELS.get(permission, permission)))
		sections.append("[b]%s[/b] · %s\n职位：%s · 权限：%s" % [
			organization.name,
			_type_label(organization.type),
			str(position.get("name", "无")),
			"、".join(permission_names) if not permission_names.is_empty() else "暂无",
		])
	organizations_label.text = "\n\n".join(sections) if not sections.is_empty() else "尚未加入组织。"


func _render_relationships(character: CharacterData) -> void:
	var society: SocietySimulationService = GameSessionService.society_service
	if society == null:
		relationships_label.text = "社会系统尚未就绪。"
		return
	var relationships: Array[RelationshipData] = society.relationships.get_for_character(character.id)
	var sections: Array[String] = []
	for relationship: RelationshipData in relationships:
		var other_id: String = relationship.character_b_id if relationship.character_a_id == character.id else relationship.character_a_id
		var other: Variant = society.roster.get_public_character(other_id)
		if other == null:
			continue
		sections.append("[b]%s[/b] · %s\n熟悉 %.0f%% · 信任 %.0f%% · %s" % [
			str(other.name),
			str(other.occupation),
			relationship.familiarity * 100.0,
			relationship.trust * 100.0,
			"亲近" if relationship.affinity >= 0.35 else ("敌对" if relationship.affinity <= -0.2 else "中性"),
		])
	relationships_label.text = "\n\n".join(sections) if not sections.is_empty() else "尚未建立关系。可从“社会”页面选择人物并开始建立关系行动。"


func _render_cognition(character: CharacterData) -> void:
	var cognition_lines: Array[String] = []
	var tendency_ids: Array[String] = []
	for raw_id: Variant in character.known_tendencies:
		tendency_ids.append(str(raw_id))
	tendency_ids.sort()
	for tendency_id: String in tendency_ids:
		cognition_lines.append("%s：%s" % [
			_config.get_label("tendencies", tendency_id),
			str(character.known_tendencies[tendency_id]),
		])
	var raw_dossiers: Variant = character.current_status.get("investigation_dossiers", {})
	var dossiers: Dictionary = raw_dossiers as Dictionary if raw_dossiers is Dictionary else {}
	cognition_label.text = "[b]对自身立场的认知[/b]\n%s\n\n[b]调查档案[/b]\n%s" % [
		"\n".join(cognition_lines) if not cognition_lines.is_empty() else "暂无明确认知。",
		_format_dossiers(dossiers),
	]


func _format_dossiers(dossiers: Dictionary) -> String:
	if dossiers.is_empty():
		return "尚无档案。完成“调查人物”行动后，可靠信息会在这里出现。"
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
			for raw_key: Variant in raw_tendencies:
				var tendency_id: String = str(raw_key)
				tendency_lines.append("%s：%s" % [
					_config.get_label("tendencies", tendency_id),
					_config.describe_tendency(tendency_id, int((raw_tendencies as Dictionary)[raw_key])),
				])
		sections.append("[b]%s[/b]，%d岁 · %s\n职位：%s · 特质：%s\n%s" % [
			str(dossier.get("name", "未知人物")),
			int(dossier.get("age", 0)),
			str(dossier.get("occupation", "未知职业")),
			str(dossier.get("public_position", "无")) if not str(dossier.get("public_position", "")).is_empty() else "无",
			_format_traits(DataRecordUtils.to_string_array(dossier.get("traits", []))),
			"；".join(tendency_lines) if not tendency_lines.is_empty() else "倾向信息不足",
		])
	return "\n\n".join(sections) if not sections.is_empty() else "尚无有效档案。"


func _format_traits(keys: Array[String]) -> String:
	var output: Array[String] = []
	for key: String in keys:
		output.append(_config.get_label("traits", key))
	return "、".join(output) if not output.is_empty() else "目前没有明显表现出的特质"


func _format_values(values: Dictionary, label_group: String) -> String:
	var keys: Array[String] = []
	for raw_key: Variant in values:
		keys.append(str(raw_key))
	keys.sort()
	var lines: Array[String] = []
	for key: String in keys:
		lines.append("%s  %s" % [_config.get_label(label_group, key), str(values[key])])
	return "\n".join(lines) if not lines.is_empty() else "无"


func _format_status_value(field_id: String, raw_value: Variant) -> String:
	match field_id:
		"health", "fatigue", "stress":
			return "%d / 100" % int(raw_value)
		"employment_status", "injury":
			return _config.get_label("status_values", str(raw_value).to_lower())
		"detained":
			return "是" if bool(raw_value) else "否"
		_:
			return str(raw_value)


func _status_default(field_id: String) -> Variant:
	match field_id:
		"employment_status":
			return "unemployed"
		"injury":
			return "none"
		"detained":
			return false
		_:
			return 0


func _region_name(region_id: String) -> String:
	var map_service: MapControlService = GameSessionService.world_map_service
	if map_service == null:
		return "未知地区"
	var region: RegionData = map_service.data_set.regions.get(region_id) as RegionData
	return region.name if region != null else "未知地区"


func _refresh_clock() -> void:
	if _clock == null:
		clock_label.text = "世界时间尚未就绪"
		pause_button.disabled = true
		return
	clock_label.text = "%04d年%02d月%02d日 %02d:00 · %s · %d×" % [
		_clock.year,
		_clock.month,
		_clock.day,
		_clock.hour,
		"已暂停" if _clock.is_paused else "运行中",
		_clock.speed_multiplier,
	]
	pause_button.text = "继续" if _clock.is_paused else "暂停"


func _on_clock_changed(_snapshot: Dictionary) -> void:
	_refresh_clock()
	if GameSessionService.has_player():
		_render()


func _toggle_pause() -> void:
	if _clock != null:
		_clock.set_paused(not _clock.is_paused)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause") and not _text_input_has_focus():
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _text_input_has_focus() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _on_developer_toggled(enabled: bool) -> void:
	developer_panel.visible = enabled and GameSessionService.developer_mode


func _on_event_pressed() -> void:
	if not GameSessionService.developer_mode:
		return
	CharacterTendencyService.new(_config).apply_event(GameSessionService.player_character, "propaganda")
	_render()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/strategic_map_view.tscn")


static func _type_label(type_id: String) -> String:
	return str({
		"government": "政府机构",
		"military": "军队",
		"enterprise": "综合企业",
		"industrial": "工业企业",
		"commercial": "商业组织",
		"union": "工会",
		"education": "教育机构",
		"news": "新闻机构",
	}.get(type_id, "组织"))


static func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		child.free()
