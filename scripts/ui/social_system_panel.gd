class_name SocialSystemPanel
extends PanelContainer
## Player-facing society overview; direct state mutation controls remain hidden outside developer mode.

signal close_requested
signal society_changed

@onready var close_button: Button = %CloseButton
@onready var counts_label: Label = %CountsLabel
@onready var organization_option: OptionButton = %OrganizationOption
@onready var organization_label: RichTextLabel = %OrganizationLabel
@onready var join_button: Button = %JoinButton
@onready var position_option: OptionButton = %PositionOption
@onready var position_button: Button = %PositionButton
@onready var relationship_option: OptionButton = %RelationshipOption
@onready var relationship_button: Button = %RelationshipButton
@onready var relationship_label: Label = %RelationshipLabel
@onready var background_option: OptionButton = %BackgroundOption
@onready var promote_button: Button = %PromoteButton
@onready var active_option: OptionButton = %ActiveOption
@onready var demote_button: Button = %DemoteButton
@onready var exit_reason_option: OptionButton = %ExitReasonOption
@onready var prepare_succession_button: Button = %PrepareSuccessionButton
@onready var succession_option: OptionButton = %SuccessionOption
@onready var succession_label: Label = %SuccessionLabel
@onready var confirm_succession_button: Button = %ConfirmSuccessionButton
@onready var developer_toggle: CheckButton = %DeveloperToggle
@onready var ai_section: VBoxContainer = %AiSection
@onready var ai_option: OptionButton = %AiOption
@onready var ai_label: RichTextLabel = %AiLabel
@onready var message_label: Label = %MessageLabel

var clock: SimulationClock
var society: SocietySimulationService
var _developer_controls: Array[Control] = []


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	organization_option.item_selected.connect(_on_organization_selected)
	join_button.pressed.connect(_on_join_pressed)
	position_button.pressed.connect(_on_position_pressed)
	relationship_button.pressed.connect(_on_relationship_pressed)
	promote_button.pressed.connect(_on_promote_pressed)
	demote_button.pressed.connect(_on_demote_pressed)
	prepare_succession_button.pressed.connect(_on_prepare_succession_pressed)
	confirm_succession_button.pressed.connect(_on_confirm_succession_pressed)
	developer_toggle.toggled.connect(_on_developer_toggled)
	ai_option.item_selected.connect(_on_ai_selected)
	_developer_controls = [
		join_button,
		position_option,
		position_button,
		relationship_option,
		relationship_button,
		background_option,
		promote_button,
		active_option,
		demote_button,
	]
	developer_toggle.text = "开发者：显示直接修改与 AI 调试"
	refresh_developer_mode()


func setup(simulation_clock: SimulationClock, simulation: SocietySimulationService) -> bool:
	clock = simulation_clock
	society = simulation
	if society == null or society.initialization_error != "":
		message_label.text = "社会系统未初始化。"
		return false
	_populate_exit_reasons()
	_refresh_all()
	return true


func refresh_developer_mode() -> void:
	if not is_node_ready():
		return
	var was_visible: bool = developer_toggle.visible
	developer_toggle.visible = GameSessionService.developer_mode
	if was_visible and not GameSessionService.developer_mode:
		developer_toggle.button_pressed = false
	var show_mutations: bool = developer_toggle.button_pressed
	for control: Control in _developer_controls:
		control.visible = show_mutations
	ai_section.visible = show_mutations
	_refresh_ai()


func _refresh_all() -> void:
	counts_label.text = "背景人物 %d · 活跃人物 %d / %d · 已退出 %d · 按需关系 %d" % [
		society.roster.background_characters.size(), society.roster.active_characters.size(),
		society.rules.active_character_limit, society.roster.exited_characters.size(),
		society.relationships.size(),
	]
	_populate_organizations()
	_populate_characters()
	_refresh_relationships()
	refresh_developer_mode()


func _populate_organizations() -> void:
	var selected_id: String = _selected_metadata(organization_option)
	organization_option.clear()
	for organization_id: String in society.organizations.get_organization_ids():
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		organization_option.add_item(organization.name)
		organization_option.set_item_metadata(organization_option.item_count - 1, organization_id)
		if organization_id == selected_id:
			organization_option.select(organization_option.item_count - 1)
	_on_organization_selected(organization_option.selected)


func _on_organization_selected(_index: int) -> void:
	var organization: OrganizationData = _selected_organization()
	if organization == null:
		return
	var player: CharacterData = GameSessionService.player_character
	var position_name: String = society.organizations.get_position_name(player.id, organization.id)
	organization_label.text = "[font_size=18]%s[/font_size]\n类型：%s\n规模：%d · 资源：%.0f · 影响力：%.0f%%\n公开立场：%s\n成员记录：%d\n玩家职位：%s" % [
		organization.name, _type_label(organization.type), int(organization.size),
		organization.resources, organization.influence * 100.0, organization.public_stance,
		organization.member_ids.size(), position_name if not position_name.is_empty() else "非成员",
	]
	join_button.text = "离开组织" if organization.member_ids.has(player.id) else "加入组织"
	join_button.disabled = player.country_id != organization.country_id
	position_option.clear()
	var positions: Dictionary = organization.position_structure["positions"] as Dictionary
	var position_ids: Array[String] = []
	for raw_id: Variant in positions:
		position_ids.append(str(raw_id))
	position_ids.sort_custom(func(a: String, b: String) -> bool:
		return int((positions[a] as Dictionary)["level"]) < int((positions[b] as Dictionary)["level"])
	)
	for position_id: String in position_ids:
		var position: Dictionary = positions[position_id] as Dictionary
		position_option.add_item("%s（%d级）" % [position["name"], position["level"]])
		position_option.set_item_metadata(position_option.item_count - 1, position_id)
	position_button.disabled = not organization.member_ids.has(player.id)


func _on_join_pressed() -> void:
	var organization: OrganizationData = _selected_organization()
	var player: CharacterData = GameSessionService.player_character
	var changed: bool
	if organization.member_ids.has(player.id):
		changed = society.organizations.leave_organization(player, organization.id)
	else:
		changed = society.organizations.join_organization(player, organization.id)
	message_label.text = "组织成员状态已更新。" if changed else "无法更新组织成员状态。"
	if changed:
		society_changed.emit()
	_refresh_all()


func _on_position_pressed() -> void:
	var organization: OrganizationData = _selected_organization()
	var position_id: String = _selected_metadata(position_option)
	var changed: bool = society.organizations.assign_position(
		GameSessionService.player_character, organization.id, position_id
	)
	message_label.text = "职位已更新。" if changed else "职位槽位不可用或人物不是成员。"
	if changed:
		society_changed.emit()
	_refresh_all()


func _on_relationship_pressed() -> void:
	var target_id: String = _selected_metadata(relationship_option)
	var relationship: RelationshipData = society.create_player_relationship(target_id, clock.total_hours)
	message_label.text = "已建立或加深实际联系。" if relationship != null else "无法创建该关系。"
	_refresh_all()


func _on_promote_pressed() -> void:
	var character_id: String = _selected_metadata(background_option)
	var character: CharacterData = society.promote_background(character_id)
	message_label.text = "人物已升级为活跃层。" if character != null else "活跃人物已达上限。"
	_refresh_all()


func _on_demote_pressed() -> void:
	var character_id: String = _selected_metadata(active_option)
	var character: BackgroundCharacterData = society.demote_active(character_id)
	message_label.text = "人物已降级为背景层。" if character != null else "玩家或组织领导不能降级。"
	_refresh_all()


func _populate_exit_reasons() -> void:
	exit_reason_option.clear()
	for reason_id: String in society.continuity_rules.get_exit_reason_ids():
		exit_reason_option.add_item(society.continuity_rules.get_exit_label(reason_id))
		exit_reason_option.set_item_metadata(exit_reason_option.item_count - 1, reason_id)


func _on_prepare_succession_pressed() -> void:
	succession_option.clear()
	var candidates: Array[SuccessionCandidateData] = society.succession.get_candidates(
		GameSessionService.player_character.id
	)
	for candidate: SuccessionCandidateData in candidates:
		succession_option.add_item("%s · %s" % [candidate.name, candidate.role_label])
		succession_option.set_item_metadata(
			succession_option.item_count - 1, candidate.character_id
		)
	confirm_succession_button.disabled = candidates.is_empty()
	succession_label.text = (
		"没有符合条件的继承者；请先通过长期行动建立可信关系或加入组织。"
		if candidates.is_empty()
		else "找到 %d 名来自真实关系或共同组织的候选。" % candidates.size()
	)


func _on_confirm_succession_pressed() -> void:
	var successor_id: String = _selected_metadata(succession_option)
	var reason_id: String = _selected_metadata(exit_reason_option)
	var result: SuccessionResult = society.execute_player_succession(
		successor_id, reason_id, clock.total_hours
	)
	if not result.is_success():
		message_label.text = "\n".join(result.errors)
		return
	message_label.text = "继承完成：%s 接续世界。财富 +%d，声望 +%d，关系 %d 条，职位 %d 个。" % [
		result.successor.name, result.inherited_wealth, result.inherited_reputation,
		result.inherited_relationship_count, result.inherited_position_count,
	]
	succession_option.clear()
	confirm_succession_button.disabled = true
	society_changed.emit()
	_refresh_all()


func _populate_characters() -> void:
	background_option.clear()
	relationship_option.clear()
	for character_id: String in society.roster.get_background_ids():
		var character: BackgroundCharacterData = society.roster.get_background(character_id)
		background_option.add_item("%s · %s" % [character.name, character.occupation])
		background_option.set_item_metadata(background_option.item_count - 1, character_id)
		relationship_option.add_item("%s · %s" % [character.name, character.occupation])
		relationship_option.set_item_metadata(relationship_option.item_count - 1, character_id)
	active_option.clear()
	ai_option.clear()
	for character_id: String in society.roster.get_active_ids(false):
		var character: CharacterData = society.roster.get_active(character_id)
		active_option.add_item("%s · %s" % [character.name, character.public_position])
		active_option.set_item_metadata(active_option.item_count - 1, character_id)
		ai_option.add_item(character.name)
		ai_option.set_item_metadata(ai_option.item_count - 1, character_id)
	promote_button.disabled = background_option.item_count == 0 or society.roster.active_characters.size() >= society.rules.active_character_limit
	demote_button.disabled = active_option.item_count == 0
	relationship_button.disabled = relationship_option.item_count == 0


func _refresh_relationships() -> void:
	var player_id: String = GameSessionService.player_character.id
	var known: Array[RelationshipData] = society.relationships.get_for_character(player_id)
	relationship_label.text = "玩家已知实际关系：%d（通过长期行动建立）" % known.size()


func _on_developer_toggled(enabled: bool) -> void:
	for control: Control in _developer_controls:
		control.visible = enabled
	ai_section.visible = enabled
	_refresh_ai()


func _on_ai_selected(_index: int) -> void:
	_refresh_ai()


func _refresh_ai() -> void:
	if not ai_section.visible or ai_option.item_count == 0 or society == null:
		return
	var character_id: String = _selected_metadata(ai_option)
	var state: AiStateData = society.ai.get_state(character_id)
	if state == null:
		ai_label.text = "此人物没有活跃 AI。"
		return
	var candidates: Array[String] = []
	for candidate: Dictionary in state.candidate_actions:
		candidates.append("%s：%.3f" % [candidate["action_id"], candidate["weight"]])
	ai_label.text = "[color=#efb96a]活跃 AI 调试[/color]\n长期目标：%s（%.1f）\n当前选择：%s\n下次每日决策：%d\n下次长期评估：%d\n候选权重：\n%s" % [
		society.rules.get_goal_label(state.current_goal), state.goal_priority,
		state.current_action_id, state.next_daily_decision_hour,
		state.next_long_term_hour, "\n".join(candidates),
	]


func _selected_organization() -> OrganizationData:
	return society.organizations.get_organization(_selected_metadata(organization_option)) if organization_option.item_count > 0 else null


static func _selected_metadata(option: OptionButton) -> String:
	return "" if option.item_count == 0 else str(option.get_item_metadata(option.selected))


static func _type_label(type_id: String) -> String:
	return {"government": "政府机构", "military": "军队", "enterprise": "企业", "union": "工会"}.get(type_id, type_id)
