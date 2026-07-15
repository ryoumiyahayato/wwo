class_name CharacterProfilePanel
extends PanelContainer
## Compact public character profile embedded in the persistent map drawer.

signal close_requested

const GOVERNANCE_SKILLS: Array[String] = [
	"administration", "finance", "political_activity", "public_speaking", "social_organization",
]
const OTHER_SKILLS: Array[String] = [
	"military_command", "personal_combat", "engineering", "investigation",
]

@onready var close_button: Button = %CloseButton
@onready var identity_label: Label = %IdentityLabel
@onready var status_grid: GridContainer = %StatusGrid
@onready var governance_skills: VBoxContainer = %GovernanceSkills
@onready var other_skills: VBoxContainer = %OtherSkills
@onready var organizations_label: RichTextLabel = %OrganizationsLabel
@onready var relationships_label: RichTextLabel = %RelationshipsLabel
@onready var development_label: Label = %DevelopmentLabel

var _config: CharacterGenerationConfig
var _society: SocietySimulationService
var _action_rules: ActionRulesConfig
var _context_service: PlayerActionContextService
var _evaluator: ActionService


func _ready() -> void:
	_config = CharacterGenerationConfig.load_from_file()
	close_button.pressed.connect(func() -> void: close_requested.emit())


func setup(simulation: SocietySimulationService) -> bool:
	_society = simulation
	_action_rules = ActionRulesConfig.new()
	if _action_rules.load_from_file() == OK and _society != null:
		_context_service = PlayerActionContextService.new(
			_action_rules, _society, GameSessionService.world_map_service
		)
		_evaluator = ActionService.new(_action_rules, StableIdService.new())
	refresh_view()
	return _config != null and _config.is_valid() and GameSessionService.has_player()


func refresh_view() -> void:
	if not is_node_ready():
		return
	if not GameSessionService.has_player() or _config == null or not _config.is_valid():
		identity_label.text = "请先创建玩家人物。"
		return
	var character: CharacterData = GameSessionService.player_character
	identity_label.text = "%s · %d 岁\n%s · %s\n%s" % [
		character.name,
		character.age,
		character.occupation,
		_region_name(character.region_id),
		character.public_position if not character.public_position.is_empty() else "暂无正式职位",
	]
	_render_status(character)
	_render_skill_group(governance_skills, "治理与社会", GOVERNANCE_SKILLS, character)
	_render_skill_group(other_skills, "军事、技术与调查", OTHER_SKILLS, character)
	_render_organizations(character)
	_render_relationships(character)
	development_label.text = "\n".join(get_development_suggestions(character))


func get_development_suggestions(character: CharacterData) -> Array[String]:
	var suggestions: Array[String] = []
	if (
		character == null
		or _society == null
		or _context_service == null
		or _evaluator == null
	):
		return ["当前发展状态尚未就绪。", "请返回地图后重新打开人物页。"]
	var current_action: ActionInstanceData = GameSessionService.current_action
	if current_action != null and current_action.status in [
		ActionInstanceData.STATUS_ACTIVE, ActionInstanceData.STATUS_PAUSED,
	]:
		suggestions.append("• 当前阻挡：已有进行中行动，需先完成或结束该行动。")
	elif bool(character.current_status.get("detained", false)):
		suggestions.append("• 当前阻挡：人物正被拘押，长期行动暂不可用。")
	elif character.organization_ids.is_empty():
		suggestions.append("• 当前缺口：尚未加入正式组织，可先经营关系并申请入口职位。")
	elif _society.relationships.get_for_character(character.id).is_empty():
		suggestions.append("• 当前缺口：尚未建立社会关系。")
	else:
		suggestions.append("• 当前基础：已有关系和组织路径，可继续积累职位条件。")

	var relationship_target: Dictionary = _best_relationship_target(character)
	if not relationship_target.is_empty():
		suggestions.append("• 最容易接触：%s（%s · %s，%s）" % [
			str(relationship_target["name"]),
			str(relationship_target["occupation"]),
			str(relationship_target["region"]),
			str(relationship_target["outlook"]),
		])

	var organization_target: Dictionary = _best_organization_target(character)
	if not organization_target.is_empty():
		suggestions.append("• 最匹配组织：%s（%s，%s）" % [
			str(organization_target["name"]),
			str(organization_target["region"]),
			str(organization_target["outlook"]),
		])

	var recommended_skills: Array[String] = _recommended_skill_ids(character)
	var skill_labels: Array[String] = []
	for skill_id: String in recommended_skills:
		skill_labels.append(_config.get_label("skills", skill_id))
	suggestions.append("• 推荐能力：%s" % "、".join(skill_labels))
	while suggestions.size() > 4:
		suggestions.pop_back()
	return suggestions


func _best_relationship_target(character: CharacterData) -> Dictionary:
	var map_service: MapControlService = GameSessionService.world_map_service
	var definition: ActionDefinitionData = map_service.data_set.actions.get(
		"action:build_relationship"
	) as ActionDefinitionData
	var best: Dictionary = {}
	for target_id: String in _society.roster.get_living_ids(character.country_id):
		if target_id == character.id or not _context_service.get_target_validation_error(
			definition, character, target_id
		).is_empty():
			continue
		var target: Variant = _society.roster.get_public_character(target_id)
		if target == null:
			continue
		var context: Dictionary = _context_service.build_context(
			definition, character, target_id, 0
		)
		var effective: float = _evaluator.calculate_effective_value(
			definition, character, context
		)
		if best.is_empty() or effective > float(best["effective"]):
			best = {
				"id": target_id,
				"name": str(target.name),
				"occupation": str(target.occupation),
				"region": _region_name(str(target.region_id)),
				"effective": effective,
				"outlook": _action_rules.get_outlook(
					effective,
					definition.guaranteed_success_threshold,
					definition.success_threshold
				),
			}
	return best


func _best_organization_target(character: CharacterData) -> Dictionary:
	var map_service: MapControlService = GameSessionService.world_map_service
	var definition: ActionDefinitionData = map_service.data_set.actions.get(
		"action:join_organization"
	) as ActionDefinitionData
	var best: Dictionary = {}
	for organization_id: String in _society.organizations.get_organization_ids():
		var organization: OrganizationData = _society.organizations.get_organization(
			organization_id
		)
		if (
			organization == null
			or organization.member_ids.has(character.id)
			or not _context_service.get_target_validation_error(
				definition, character, organization_id
			).is_empty()
		):
			continue
		var context: Dictionary = _context_service.build_context(
			definition, character, organization_id, 0
		)
		var effective: float = _evaluator.calculate_effective_value(
			definition, character, context
		)
		if best.is_empty() or effective > float(best["effective"]):
			best = {
				"id": organization_id,
				"name": organization.name,
				"region": _region_name(organization.region_id),
				"effective": effective,
				"outlook": _action_rules.get_outlook(
					effective,
					definition.guaranteed_success_threshold,
					definition.success_threshold
				),
			}
	return best


func _recommended_skill_ids(character: CharacterData) -> Array[String]:
	var mapping: Dictionary = _action_rules.player_context_rules.get(
		"work_skill_by_occupation", {}
	) as Dictionary
	var candidates: Array[String] = [
		str(mapping.get(character.occupation_id, "social_organization")),
		"public_speaking",
		"social_organization",
	]
	var recommended: Array[String] = []
	for skill_id: String in candidates:
		if character.skills.has(skill_id) and not recommended.has(skill_id):
			recommended.append(skill_id)
		if recommended.size() >= 2:
			break
	return recommended


func _render_status(character: CharacterData) -> void:
	_clear_children(status_grid)
	var fields: Array[Dictionary] = [
		{"id": "health", "label": "健康"},
		{"id": "fatigue", "label": "疲劳"},
		{"id": "stress", "label": "压力"},
		{"id": "wealth", "label": "财富"},
		{"id": "reputation", "label": "声望"},
		{"id": "employment_status", "label": "就业"},
	]
	for field: Dictionary in fields:
		var label := Label.new()
		label.text = str(field["label"])
		label.add_theme_color_override("font_color", Color(0.55, 0.74, 0.8))
		status_grid.add_child(label)
		var value := Label.new()
		var field_id: String = str(field["id"])
		var raw_value: Variant = character.current_status.get(field_id, 0)
		value.text = _format_status_value(field_id, raw_value)
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
	header.add_theme_color_override("font_color", Color(0.72, 0.84, 0.88))
	container.add_child(header)
	for skill_id: String in skill_ids:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(92, 22)
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
	if _society == null or character.organization_ids.is_empty():
		organizations_label.text = "尚未加入正式组织。"
		return
	var lines: Array[String] = []
	for organization_id: String in character.organization_ids:
		var organization: OrganizationData = _society.organizations.get_organization(organization_id)
		if organization == null:
			continue
		var position_id: String = _society.organizations.get_position_id(character.id, organization_id)
		var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
		var position: Dictionary = positions.get(position_id, {}) as Dictionary
		lines.append("[b]%s[/b] · %s" % [organization.name, str(position.get("name", "成员"))])
	organizations_label.text = "\n".join(lines) if not lines.is_empty() else "尚未加入正式组织。"


func _render_relationships(character: CharacterData) -> void:
	if _society == null:
		relationships_label.text = "社会系统尚未就绪。"
		return
	var lines: Array[String] = []
	for relationship: RelationshipData in _society.relationships.get_for_character(character.id):
		var other_id: String = (
			relationship.character_b_id
			if relationship.character_a_id == character.id
			else relationship.character_a_id
		)
		var other: Variant = _society.roster.get_public_character(other_id)
		if other != null:
			lines.append("[b]%s[/b] · 熟悉 %.0f%% · 信任 %.0f%%" % [
				str(other.name),
				relationship.familiarity * 100.0,
				relationship.trust * 100.0,
			])
	relationships_label.text = "\n".join(lines) if not lines.is_empty() else "尚未建立社会关系。"


func _region_name(region_id: String) -> String:
	var map_service: MapControlService = GameSessionService.world_map_service
	if map_service == null:
		return "未知地区"
	var region: RegionData = map_service.data_set.regions.get(region_id) as RegionData
	return region.name if region != null else "未知地区"


func _format_status_value(field_id: String, raw_value: Variant) -> String:
	match field_id:
		"health", "fatigue", "stress":
			return "%d / 100" % int(raw_value)
		"employment_status":
			return _config.get_label("status_values", str(raw_value).to_lower())
		_:
			return str(raw_value)


static func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		child.free()
