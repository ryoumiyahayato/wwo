class_name SocialSystemPanel
extends PanelContainer
## Player-centered organization, relationship and succession navigation.

signal close_requested
signal society_changed
signal request_action(action_id: String, target_id: String)

const PERMISSION_LABELS: Dictionary = {
	"organization_member": "组织成员",
	"organization_support": "组织动员",
	"regional_policy": "地区政策",
	"regional_control_support": "地区控制支援",
}

@onready var close_button: Button = %CloseButton
@onready var player_social_summary: Label = %PlayerSocialSummary
@onready var social_tabs: TabContainer = %SocialTabs
@onready var organization_option: OptionButton = %OrganizationOption
@onready var organization_label: RichTextLabel = %OrganizationLabel
@onready var find_organization_button: Button = %FindOrganizationButton
@onready var join_action_button: Button = %JoinActionButton
@onready var position_action_button: Button = %PositionActionButton
@onready var policy_action_button: Button = %PolicyActionButton
@onready var control_action_button: Button = %ControlActionButton
@onready var organization_hint: Label = %OrganizationHint
@onready var relationship_summary: RichTextLabel = %RelationshipSummary
@onready var relationship_option: OptionButton = %RelationshipOption
@onready var relationship_target_label: Label = %RelationshipTargetLabel
@onready var build_relationship_button: Button = %BuildRelationshipButton
@onready var deepen_relationship_button: Button = %DeepenRelationshipButton
@onready var investigate_action_button: Button = %InvestigateActionButton
@onready var succession_status_label: Label = %SuccessionStatusLabel
@onready var exit_reason_option: OptionButton = %ExitReasonOption
@onready var inheritance_ratio_label: Label = %InheritanceRatioLabel
@onready var prepare_succession_button: Button = %PrepareSuccessionButton
@onready var succession_option: OptionButton = %SuccessionOption
@onready var succession_label: Label = %SuccessionLabel
@onready var confirm_succession_button: Button = %ConfirmSuccessionButton
@onready var developer_toggle: CheckButton = %DeveloperToggle
@onready var developer_section: PanelContainer = %DeveloperSection
@onready var dev_organization_option: OptionButton = %DevOrganizationOption
@onready var dev_join_button: Button = %DevJoinButton
@onready var dev_position_option: OptionButton = %DevPositionOption
@onready var dev_position_button: Button = %DevPositionButton
@onready var dev_relationship_option: OptionButton = %DevRelationshipOption
@onready var dev_relationship_button: Button = %DevRelationshipButton
@onready var background_option: OptionButton = %BackgroundOption
@onready var promote_button: Button = %PromoteButton
@onready var active_option: OptionButton = %ActiveOption
@onready var demote_button: Button = %DemoteButton
@onready var ai_option: OptionButton = %AiOption
@onready var ai_label: RichTextLabel = %AiLabel
@onready var message_label: Label = %MessageLabel

var clock: SimulationClock
var society: SocietySimulationService


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	organization_option.item_selected.connect(_on_organization_selected)
	find_organization_button.pressed.connect(_on_find_organization_pressed)
	join_action_button.pressed.connect(_emit_organization_action.bind("action:join_organization"))
	position_action_button.pressed.connect(_emit_organization_action.bind("action:seek_position"))
	policy_action_button.pressed.connect(_emit_regional_action.bind("action:promote_policy"))
	control_action_button.pressed.connect(_emit_regional_action.bind("action:support_control"))
	relationship_option.item_selected.connect(_on_relationship_selected)
	build_relationship_button.pressed.connect(_emit_relationship_action.bind("action:build_relationship"))
	deepen_relationship_button.pressed.connect(_emit_relationship_action.bind("action:build_relationship"))
	investigate_action_button.pressed.connect(_emit_relationship_action.bind("action:investigate_character"))
	exit_reason_option.item_selected.connect(_on_exit_reason_selected)
	prepare_succession_button.pressed.connect(_on_prepare_succession_pressed)
	confirm_succession_button.pressed.connect(_on_confirm_succession_pressed)
	developer_toggle.toggled.connect(_on_developer_toggled)
	dev_organization_option.item_selected.connect(_populate_dev_positions)
	dev_join_button.pressed.connect(_on_dev_join_pressed)
	dev_position_button.pressed.connect(_on_dev_position_pressed)
	dev_relationship_button.pressed.connect(_on_dev_relationship_pressed)
	promote_button.pressed.connect(_on_promote_pressed)
	demote_button.pressed.connect(_on_demote_pressed)
	ai_option.item_selected.connect(func(_index: int) -> void: _refresh_ai())
	refresh_developer_mode()


func setup(simulation_clock: SimulationClock, simulation: SocietySimulationService) -> bool:
	clock = simulation_clock
	society = simulation
	if society == null or society.initialization_error != "":
		message_label.text = "社会系统未初始化。"
		return false
	_refresh_all()
	return true


func refresh_view() -> void:
	if society != null:
		_refresh_all()


func focus_organization(organization_id: String) -> bool:
	if society == null:
		return false
	_populate_organizations()
	for index: int in range(organization_option.item_count):
		if str(organization_option.get_item_metadata(index)) == organization_id:
			organization_option.select(index)
			_on_organization_selected(index)
			social_tabs.current_tab = 0
			return true
	return false


func focus_character(character_id: String) -> bool:
	if society == null:
		return false
	_populate_relationships()
	for index: int in range(relationship_option.item_count):
		if str(relationship_option.get_item_metadata(index)) == character_id:
			relationship_option.select(index)
			_on_relationship_selected(index)
			social_tabs.current_tab = 1
			return true
	return false


func refresh_developer_mode() -> void:
	if not is_node_ready():
		return
	developer_toggle.visible = GameSessionService.developer_mode
	if not GameSessionService.developer_mode:
		developer_toggle.set_pressed_no_signal(false)
	developer_section.visible = GameSessionService.developer_mode and developer_toggle.button_pressed
	if developer_section.visible:
		_refresh_ai()


func _refresh_all() -> void:
	if society == null or not GameSessionService.has_player():
		return
	var player: CharacterData = GameSessionService.player_character
	var relationships: Array[RelationshipData] = society.relationships.get_for_character(player.id)
	var permissions: Array[String] = society.organizations.get_character_permissions(player.id)
	var permission_names: Array[String] = []
	for permission: String in permissions:
		permission_names.append(str(PERMISSION_LABELS.get(permission, permission)))
	player_social_summary.text = "已加入组织 %d · 真实关系 %d · 权限：%s" % [
		player.organization_ids.size(),
		relationships.size(),
		"、".join(permission_names) if not permission_names.is_empty() else "暂无",
	]
	_populate_organizations()
	_populate_relationships()
	_populate_exit_reasons()
	_populate_developer_controls()
	refresh_developer_mode()


func _populate_organizations() -> void:
	var selected_id: String = _selected_metadata(organization_option)
	organization_option.clear()
	var player: CharacterData = GameSessionService.player_character
	for organization_id: String in society.organizations.get_organization_ids():
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		if organization == null or organization.country_id != player.country_id:
			continue
		var membership: String = "已加入" if organization.member_ids.has(player.id) else "可申请"
		organization_option.add_item("%s · %s" % [organization.name, membership])
		organization_option.set_item_metadata(organization_option.item_count - 1, organization_id)
		if organization_id == selected_id:
			organization_option.select(organization_option.item_count - 1)
	_on_organization_selected(organization_option.selected)


func _on_organization_selected(_index: int) -> void:
	var organization: OrganizationData = _selected_organization()
	var player: CharacterData = GameSessionService.player_character
	if organization == null or player == null:
		organization_label.text = "没有可查看的本国组织。"
		return
	var is_member: bool = organization.member_ids.has(player.id)
	var position_name: String = society.organizations.get_position_name(player.id, organization.id)
	var permissions: Array[String] = []
	if is_member:
		var position_id: String = society.organizations.get_position_id(player.id, organization.id)
		var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
		permissions = DataRecordUtils.to_string_array((positions.get(position_id, {}) as Dictionary).get("permissions", []))
	var permission_names: Array[String] = []
	for permission: String in permissions:
		permission_names.append(str(PERMISSION_LABELS.get(permission, permission)))
	var next_position: Dictionary = _next_position(organization, player.id)
	organization_label.text = "[font_size=18][b]%s[/b][/font_size]\n%s · %s\n当前身份：%s · 当前职位：%s\n当前权限：%s\n资源 %.0f · 影响力 %.0f%% · 公开立场：%s\n下一职位：%s" % [
		organization.name,
		_type_label(organization.type),
		_region_name(organization.region_id),
		"组织成员" if is_member else "非成员",
		position_name if not position_name.is_empty() else "无",
		"、".join(permission_names) if not permission_names.is_empty() else "暂无",
		organization.resources,
		organization.influence * 100.0,
		organization.public_stance,
		str(next_position.get("name", "暂无更高空缺")),
	]
	var entry_available: bool = _entry_position_available(organization)
	join_action_button.disabled = is_member or not entry_available
	position_action_button.disabled = not is_member or next_position.is_empty()
	policy_action_button.disabled = not society.organizations.has_permission(player.id, organization.id, "regional_policy")
	var map_service: MapControlService = GameSessionService.world_map_service
	var control_permission: bool = society.organizations.has_permission(
		player.id, organization.id, "regional_control_support"
	)
	control_action_button.disabled = (
		not control_permission
		or map_service == null
		or not map_service.is_war_active()
	)
	var hints: Array[String] = []
	if is_member:
		hints.append("你已经加入该组织。")
	elif not entry_available:
		hints.append("入口职位当前没有空位。")
	else:
		hints.append("可通过长期行动提交加入申请。")
	if not is_member:
		hints.append("加入后才能争取职位。")
	elif next_position.is_empty():
		hints.append("当前没有更高的空缺职位。")
	if policy_action_button.disabled:
		hints.append("推动政策需要地区政策权限。")
	if control_action_button.disabled:
		if map_service == null or not map_service.is_war_active():
			hints.append("当前无战争或没有合法前线目标。")
		else:
			hints.append("支持控制需要政府或军队的地区控制支援权限。")
	organization_hint.text = " ".join(hints)


func _on_find_organization_pressed() -> void:
	if organization_option.item_count == 0:
		return
	var player_id: String = GameSessionService.player_character.id
	var start: int = organization_option.selected
	for offset: int in range(1, organization_option.item_count + 1):
		var index: int = (start + offset) % organization_option.item_count
		var organization: OrganizationData = society.organizations.get_organization(str(organization_option.get_item_metadata(index)))
		if organization != null and not organization.member_ids.has(player_id):
			organization_option.select(index)
			_on_organization_selected(index)
			return
	message_label.text = "你已经加入全部本国组织，或没有可申请的组织。"


func _emit_organization_action(action_id: String) -> void:
	var target: String = _selected_metadata(organization_option)
	if not target.is_empty():
		request_action.emit(action_id, target)


func _emit_regional_action(action_id: String) -> void:
	var organization: OrganizationData = _selected_organization()
	if organization == null:
		return
	var target: String = _preferred_unit_for_action(action_id, organization.region_id)
	request_action.emit(action_id, target)


func _populate_relationships() -> void:
	var selected_id: String = _selected_metadata(relationship_option)
	relationship_option.clear()
	var player: CharacterData = GameSessionService.player_character
	for character_id: String in society.roster.get_background_ids():
		var background: BackgroundCharacterData = society.roster.get_background(character_id)
		if background.country_id != player.country_id:
			continue
		relationship_option.add_item("%s · %s" % [background.name, background.occupation])
		relationship_option.set_item_metadata(relationship_option.item_count - 1, character_id)
		if character_id == selected_id:
			relationship_option.select(relationship_option.item_count - 1)
	for character_id: String in society.roster.get_active_ids(false):
		var active: CharacterData = society.roster.get_active(character_id)
		if active.country_id != player.country_id:
			continue
		relationship_option.add_item("%s · %s" % [active.name, active.occupation])
		relationship_option.set_item_metadata(relationship_option.item_count - 1, character_id)
		if character_id == selected_id:
			relationship_option.select(relationship_option.item_count - 1)
	var known: Array[RelationshipData] = society.relationships.get_for_character(player.id)
	var lines: Array[String] = []
	for relationship: RelationshipData in known:
		var other_id: String = relationship.character_b_id if relationship.character_a_id == player.id else relationship.character_a_id
		var other: Variant = society.roster.get_public_character(other_id)
		var name: String = str(other.name) if other != null else "未知人物"
		var occupation: String = str(other.occupation) if other != null else "未知职业"
		lines.append("[b]%s[/b] · %s\n熟悉 %.0f%% · 信任 %s · %s · %s · 最近互动：%s" % [
			name,
			occupation,
			relationship.familiarity * 100.0,
			_signed_relation(relationship.trust),
			_affinity_label(relationship.affinity),
			"公开关系" if relationship.is_public else "私人关系",
			"第 %d 小时" % relationship.last_interaction_hour if relationship.last_interaction_hour >= 0 else "无记录",
		])
	relationship_summary.text = "\n\n".join(lines) if not lines.is_empty() else "尚未建立真实关系。完成“建立关系”行动后，关系会在这里出现。"
	_on_relationship_selected(relationship_option.selected)


func _on_relationship_selected(_index: int) -> void:
	var target_id: String = _selected_metadata(relationship_option)
	if target_id.is_empty():
		relationship_target_label.text = "没有可联系的人物。"
		build_relationship_button.disabled = true
		deepen_relationship_button.disabled = true
		investigate_action_button.disabled = true
		return
	var target: Variant = society.roster.get_public_character(target_id)
	var relation: RelationshipData = society.relationships.get_between(GameSessionService.player_character.id, target_id)
	relationship_target_label.text = "%s · %s · %s · %s" % [
		str(target.name),
		str(target.occupation),
		_region_name(str(target.region_id)),
		"已有关系，可继续加深" if relation != null else "尚无关系，可建立新联系",
	]
	build_relationship_button.disabled = relation != null
	deepen_relationship_button.disabled = relation == null
	investigate_action_button.disabled = false


func _emit_relationship_action(action_id: String) -> void:
	var target: String = _selected_metadata(relationship_option)
	if not target.is_empty():
		request_action.emit(action_id, target)


func _populate_exit_reasons() -> void:
	var selected_id: String = _selected_metadata(exit_reason_option)
	exit_reason_option.clear()
	succession_option.clear()
	confirm_succession_button.disabled = true
	var player: CharacterData = GameSessionService.player_character
	var reason_ids: Array[String] = society.succession.get_valid_exit_reason_ids(player)
	for reason_id: String in reason_ids:
		exit_reason_option.add_item(society.continuity_rules.get_exit_label(reason_id))
		exit_reason_option.set_item_metadata(exit_reason_option.item_count - 1, reason_id)
		if reason_id == selected_id:
			exit_reason_option.select(exit_reason_option.item_count - 1)
	prepare_succession_button.disabled = reason_ids.is_empty()
	exit_reason_option.visible = not reason_ids.is_empty()
	var health: int = int(player.current_status.get("health", 0))
	var detained: bool = bool(player.current_status.get("detained", false))
	var reputation: int = int(player.current_status.get("reputation", 0))
	var valid_text: String = "、".join(_exit_reason_labels(reason_ids)) if not reason_ids.is_empty() else "暂无"
	succession_status_label.text = "当前年龄 %d · 健康 %d · %s · 声望 %d\n当前合法退出原因：%s\n继承候选来自真实关系或共同组织，服务会在确认时重新验证人物状态。" % [
		player.age,
		health,
		"被拘留" if detained else "未被拘留",
		reputation,
		valid_text,
	]
	if reason_ids.is_empty():
		inheritance_ratio_label.text = "当前没有合法退出原因，因此不会显示无意义的继承选项。"
		succession_label.text = "继续经营关系与组织身份；达到合法条件后可在此安排继承。"
	else:
		_on_exit_reason_selected(exit_reason_option.selected)


func _on_exit_reason_selected(_index: int) -> void:
	var reason_id: String = _selected_metadata(exit_reason_option)
	var reason: Dictionary = society.continuity_rules.exit_reasons.get(reason_id, {}) as Dictionary
	if reason.is_empty():
		inheritance_ratio_label.text = "请选择合法退出原因。"
		return
	inheritance_ratio_label.text = "继承摘要：财富 %.0f%% · 声望 %.0f%% · 情报 %.0f%% · 盟友关系 %.0f%% · 敌对关系 %.0f%% · 职位%s继承" % [
		float(reason.get("wealth_ratio", 0.0)) * 100.0,
		float(reason.get("reputation_ratio", 0.0)) * 100.0,
		float(reason.get("intelligence_ratio", 0.0)) * 100.0,
		float(reason.get("ally_relationship_ratio", 0.0)) * 100.0,
		float(reason.get("enemy_relationship_ratio", 0.0)) * 100.0,
		"可按条件" if bool(reason.get("position_inheritance", false)) else "不可",
	]


func _on_prepare_succession_pressed() -> void:
	_populate_exit_reasons()
	var reason_id: String = _selected_metadata(exit_reason_option)
	if reason_id.is_empty():
		return
	var exit_error: String = society.succession.get_exit_reason_validation_error(GameSessionService.player_character, reason_id)
	if not exit_error.is_empty():
		succession_label.text = exit_error
		return
	var candidates: Array[SuccessionCandidateData] = society.succession.get_candidates(GameSessionService.player_character.id)
	for candidate: SuccessionCandidateData in candidates:
		succession_option.add_item("%s · %s" % [candidate.name, candidate.role_label])
		succession_option.set_item_metadata(succession_option.item_count - 1, candidate.character_id)
	confirm_succession_button.disabled = candidates.is_empty()
	succession_label.text = "没有符合条件的继承者；请先建立可信关系或加入组织。" if candidates.is_empty() else "找到 %d 名合法候选；确认时将再次验证退出原因。" % candidates.size()


func _on_confirm_succession_pressed() -> void:
	var result: SuccessionResult = society.execute_player_succession(
		_selected_metadata(succession_option),
		_selected_metadata(exit_reason_option),
		clock.total_hours
	)
	if not result.is_success():
		message_label.text = "\n".join(result.errors)
		_refresh_all()
		return
	message_label.text = "继承完成：%s 接续世界。财富 +%d，声望 +%d，关系 %d 条，职位 %d 个。" % [
		result.successor.name,
		result.inherited_wealth,
		result.inherited_reputation,
		result.inherited_relationship_count,
		result.inherited_position_count,
	]
	society_changed.emit()
	_refresh_all()


func _populate_developer_controls() -> void:
	dev_organization_option.clear()
	dev_relationship_option.clear()
	background_option.clear()
	active_option.clear()
	ai_option.clear()
	for organization_id: String in society.organizations.get_organization_ids():
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		dev_organization_option.add_item(organization.name)
		dev_organization_option.set_item_metadata(dev_organization_option.item_count - 1, organization_id)
	for character_id: String in society.roster.get_background_ids():
		var background: BackgroundCharacterData = society.roster.get_background(character_id)
		background_option.add_item("%s · %s" % [background.name, background.occupation])
		background_option.set_item_metadata(background_option.item_count - 1, character_id)
		dev_relationship_option.add_item("%s · %s" % [background.name, background.occupation])
		dev_relationship_option.set_item_metadata(dev_relationship_option.item_count - 1, character_id)
	for character_id: String in society.roster.get_active_ids(false):
		var active: CharacterData = society.roster.get_active(character_id)
		active_option.add_item("%s · %s" % [active.name, active.public_position])
		active_option.set_item_metadata(active_option.item_count - 1, character_id)
		ai_option.add_item(active.name)
		ai_option.set_item_metadata(ai_option.item_count - 1, character_id)
	_populate_dev_positions(dev_organization_option.selected)


func _populate_dev_positions(_index: int) -> void:
	if not is_node_ready() or society == null:
		return
	dev_position_option.clear()
	var organization: OrganizationData = society.organizations.get_organization(_selected_metadata(dev_organization_option))
	if organization == null:
		return
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	for raw_id: Variant in positions:
		var position_id: String = str(raw_id)
		var position: Dictionary = positions[position_id] as Dictionary
		dev_position_option.add_item("%s（%d级）" % [position.get("name", position_id), position.get("level", 0)])
		dev_position_option.set_item_metadata(dev_position_option.item_count - 1, position_id)


func _on_developer_toggled(enabled: bool) -> void:
	if not GameSessionService.developer_mode:
		developer_toggle.set_pressed_no_signal(false)
		developer_section.visible = false
		return
	developer_section.visible = enabled
	if enabled:
		_refresh_ai()


func _on_dev_join_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var organization: OrganizationData = society.organizations.get_organization(_selected_metadata(dev_organization_option))
	var player: CharacterData = GameSessionService.player_character
	if organization == null:
		return
	var changed: bool = society.organizations.leave_organization(player, organization.id) if organization.member_ids.has(player.id) else society.organizations.join_organization(player, organization.id)
	message_label.text = "开发者组织成员状态已更新。" if changed else "开发者修改失败。"
	if changed:
		society_changed.emit()
	_refresh_all()


func _on_dev_position_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var changed: bool = society.organizations.assign_position(
		GameSessionService.player_character,
		_selected_metadata(dev_organization_option),
		_selected_metadata(dev_position_option)
	)
	message_label.text = "开发者职位已更新。" if changed else "开发者职位修改失败。"
	if changed:
		society_changed.emit()
	_refresh_all()


func _on_dev_relationship_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var relationship: RelationshipData = society.create_player_relationship(_selected_metadata(dev_relationship_option), clock.total_hours)
	message_label.text = "开发者关系已更新。" if relationship != null else "开发者关系修改失败。"
	if relationship != null:
		society_changed.emit()
	_refresh_all()


func _on_promote_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var character: CharacterData = society.promote_background(_selected_metadata(background_option))
	message_label.text = "人物已升级为活跃层。" if character != null else "活跃人物已达上限。"
	_refresh_all()


func _on_demote_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var character: BackgroundCharacterData = society.demote_active(_selected_metadata(active_option))
	message_label.text = "人物已降级为背景层。" if character != null else "玩家或组织领导不能降级。"
	_refresh_all()


func _refresh_ai() -> void:
	if not developer_section.visible or ai_option.item_count == 0 or society == null:
		return
	var state: AiStateData = society.ai.get_state(_selected_metadata(ai_option))
	if state == null:
		ai_label.text = "此人物没有活跃 AI。"
		return
	var progress_line: String = "无进行中长期行动"
	if not state.current_action_record.is_empty():
		var action := ActionInstanceData.from_dict(state.current_action_record)
		progress_line = "%s · %.1f / %.1f · %s" % [action.definition_id, action.accumulated_work, action.total_work, action.outlook]
	ai_label.text = "[color=#efb96a]活跃 AI 调试[/color]\n长期目标：%s（%.1f）\n当前选择：%s\n行动进度：%s\n上次结果：%s" % [
		society.rules.get_goal_label(state.current_goal),
		state.goal_priority,
		state.current_action_id,
		progress_line,
		state.last_action_result,
	]


func _preferred_unit_for_action(action_id: String, preferred_region_id: String) -> String:
	var map_service: MapControlService = GameSessionService.world_map_service
	if map_service == null:
		return ""
	var action_rules := ActionRulesConfig.new()
	if action_rules.load_from_file() != OK:
		return ""
	var context := PlayerActionContextService.new(action_rules, society, map_service)
	var definition: ActionDefinitionData = map_service.data_set.actions.get(action_id) as ActionDefinitionData
	var fallback: String = ""
	for unit_id: String in map_service.get_sorted_unit_ids():
		if not context.get_target_validation_error(definition, GameSessionService.player_character, unit_id).is_empty():
			continue
		if fallback.is_empty():
			fallback = unit_id
		if map_service.get_unit(unit_id).region_id == preferred_region_id:
			return unit_id
	return fallback


func _next_position(organization: OrganizationData, character_id: String) -> Dictionary:
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	var current_id: String = society.organizations.get_position_id(character_id, organization.id)
	var current_level: int = int((positions.get(current_id, {}) as Dictionary).get("level", 0))
	var candidates: Array[Dictionary] = []
	for raw_id: Variant in positions:
		var position_id: String = str(raw_id)
		var position: Dictionary = (positions[position_id] as Dictionary).duplicate(true)
		var holders: Array[String] = DataRecordUtils.to_string_array(position.get("holder_ids", []))
		if int(position.get("level", 0)) > current_level and holders.size() < int(position.get("slots", 0)):
			position["id"] = position_id
			candidates.append(position)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 0)) < int(b.get("level", 0)))
	return {} if candidates.is_empty() else candidates[0]


func _entry_position_available(organization: OrganizationData) -> bool:
	var society: SocietySimulationService = GameSessionService.society_service
	return (
		organization != null
		and society != null
		and society.organizations.has_entry_vacancy(organization.id)
	)


func _selected_organization() -> OrganizationData:
	return society.organizations.get_organization(_selected_metadata(organization_option)) if organization_option.item_count > 0 else null


func _region_name(region_id: String) -> String:
	var map_service: MapControlService = GameSessionService.world_map_service
	if map_service == null:
		return "未知地区"
	var region: RegionData = map_service.data_set.regions.get(region_id) as RegionData
	return region.name if region != null else "未知地区"


func _exit_reason_labels(reason_ids: Array[String]) -> Array[String]:
	var labels: Array[String] = []
	for reason_id: String in reason_ids:
		labels.append(society.continuity_rules.get_exit_label(reason_id))
	return labels


func _debug_mutation_allowed() -> bool:
	return GameSessionService.developer_mode


static func _selected_metadata(option: OptionButton) -> String:
	return "" if option == null or option.item_count == 0 or option.selected < 0 else str(option.get_item_metadata(option.selected))


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


static func _signed_relation(value: float) -> String:
	return "信任 %.0f%%" % (value * 100.0) if value >= 0.0 else "戒备 %.0f%%" % (absf(value) * 100.0)


static func _affinity_label(value: float) -> String:
	if value >= 0.35:
		return "关系亲近"
	if value <= -0.2:
		return "关系敌对"
	return "关系中性"
