class_name ActionPanel
extends PanelContainer
## Formal player entry for long actions. All mutations go through authoritative services.

signal close_requested
signal action_state_changed

const ACTION_ORDER: Array[String] = [
	"action:study_skill",
	"action:perform_work",
	"action:build_relationship",
	"action:join_organization",
	"action:seek_position",
	"action:investigate_character",
	"action:promote_policy",
	"action:support_control",
]
const ACTION_PURPOSE: Dictionary = {
	"study_skill": "投入时间系统训练一项能力，为后续行动积累可靠优势。",
	"perform_work": "完成本职工作，赚取财富并维持社会声誉。",
	"build_relationship": "接触一名人物，建立或加深可用于合作与继承的真实联系。",
	"join_organization": "向本国组织提交加入申请，成功后获得入口职位。",
	"seek_position": "在已加入的组织中争取下一层空缺职位与相应权限。",
	"investigate_character": "调查人物背景，形成可在人物档案中查看的可靠认知。",
	"promote_policy": "凭借组织职位推动辖区政策，改变地区社会影响。",
	"support_control": "动员政府或军队资源支援前线控制与巩固。",
}
const ACTION_SHORT_NAMES: Dictionary = {
	"action:study_skill": "学习技能",
	"action:perform_work": "从事工作",
	"action:build_relationship": "建立关系",
	"action:join_organization": "加入组织",
	"action:seek_position": "争取职位",
	"action:investigate_character": "调查人物",
	"action:promote_policy": "推动政策",
	"action:support_control": "支持控制",
}
const SKILL_USES: Dictionary = {
	"administration": "影响工作、政策推动与组织治理。",
	"engineering": "影响技术工作和后续工程类行动。",
	"finance": "影响工作收益与资源判断。",
	"investigation": "影响人物调查与情报准备。",
	"military_command": "影响地区控制支援。",
	"personal_combat": "影响个人安全与后续战斗行动。",
	"political_activity": "影响职位争取与政策活动。",
	"public_speaking": "影响建立关系、调查与公共动员。",
	"social_organization": "影响加入组织、关系经营与控制支援。",
}
const PERMISSION_LABELS: Dictionary = {
	"organization_member": "组织成员身份",
	"organization_support": "组织动员权限",
	"regional_policy": "地区政策权限",
	"regional_control_support": "地区控制支援权限",
}
const INTERRUPTION_LABELS: Dictionary = {
	"detained": "人物正被拘留",
	"incapacitated": "人物健康不足以行动",
	"unemployed": "人物当前失业，无法从事本职工作",
}

@onready var close_button: Button = %CloseButton
@onready var action_scroll: ScrollContainer = %ActionScroll
@onready var action_buttons: GridContainer = %ActionButtons
@onready var action_list: ItemList = %ActionList
@onready var action_description: RichTextLabel = %ActionDescription
@onready var target_label: Label = %TargetLabel
@onready var target_option: OptionButton = %TargetOption
@onready var target_details: Label = %TargetDetails
@onready var study_section: VBoxContainer = %StudySection
@onready var study_skill_option: OptionButton = %StudySkillOption
@onready var skill_details: Label = %SkillDetails
@onready var funding_summary: Label = %FundingSummary
@onready var investment_spin: SpinBox = %InvestmentSpin
@onready var context_label: RichTextLabel = %ContextLabel
@onready var begin_reason_label: Label = %BeginReasonLabel
@onready var begin_button: Button = %BeginButton
@onready var pause_button: Button = %PauseButton
@onready var cancel_button: Button = %CancelButton
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var summary_label: RichTextLabel = %SummaryLabel
@onready var recent_result_header: HBoxContainer = %RecentResultHeader
@onready var recent_result_label: RichTextLabel = %RecentResultLabel
@onready var dismiss_recent_button: Button = %DismissRecentButton
@onready var action_log_label: RichTextLabel = %ActionLogLabel
@onready var message_label: Label = %MessageLabel

var clock: SimulationClock
var map_service: MapControlService
var action_service: ActionService
var context_service: PlayerActionContextService
var rules: ActionRulesConfig
var generation_config: CharacterGenerationConfig
var target_id: String = ""
var map_target_id: String = ""


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	action_list.item_selected.connect(_on_action_selected)
	target_option.item_selected.connect(_on_target_selected)
	study_skill_option.item_selected.connect(_on_study_skill_selected)
	investment_spin.value_changed.connect(_on_investment_changed)
	begin_button.pressed.connect(_on_begin_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	dismiss_recent_button.pressed.connect(_on_dismiss_recent_pressed)
	_refresh()


func setup(simulation_clock: SimulationClock, control_service: MapControlService) -> bool:
	clock = simulation_clock
	map_service = control_service
	rules = ActionRulesConfig.new()
	if rules.load_from_file() != OK:
		message_label.text = rules.error_message
		begin_button.disabled = true
		return false
	generation_config = CharacterGenerationConfig.load_from_file()
	if not generation_config.is_valid():
		message_label.text = generation_config.error_message
		begin_button.disabled = true
		return false
	action_service = ActionService.new(rules, GameSessionService.action_id_service)
	context_service = PlayerActionContextService.new(
		rules, GameSessionService.society_service, map_service
	)
	investment_spin.max_value = context_service.get_max_extra_funding()
	if not clock.time_changed.is_connected(_on_time_changed):
		clock.time_changed.connect(_on_time_changed)
	_populate_actions()
	_refresh()
	return true


func set_target(control_unit_id: String) -> void:
	map_target_id = control_unit_id
	var definition: ActionDefinitionData = _get_selected_definition()
	if definition != null and PlayerActionContextService.get_target_domain(
		definition.category
	) == PlayerActionContextService.TARGET_DOMAIN_MAP:
		_populate_targets(definition, control_unit_id)
	_refresh()


func prefill_action(action_id: String, requested_target_id: String = "") -> bool:
	for index: int in range(action_list.item_count):
		if str(action_list.get_item_metadata(index)) != action_id:
			continue
		action_list.select(index)
		_on_action_selected(index)
		if not requested_target_id.is_empty():
			_select_target(requested_target_id)
		_refresh()
		return true
	return false


func refresh_permissions() -> void:
	if rules == null:
		return
	context_service = PlayerActionContextService.new(
		rules, GameSessionService.society_service, map_service
	)
	var definition: ActionDefinitionData = _get_selected_definition()
	_populate_targets(definition, target_id)
	_refresh()


func _populate_actions() -> void:
	action_list.clear()
	for child: Node in action_buttons.get_children():
		child.free()
	if map_service == null:
		return
	for definition_id: String in ACTION_ORDER:
		var definition: ActionDefinitionData = map_service.data_set.actions.get(
			definition_id
		) as ActionDefinitionData
		if definition == null:
			continue
		action_list.add_item(str(ACTION_SHORT_NAMES.get(definition_id, definition.name)))
		var item_index: int = action_list.item_count - 1
		action_list.set_item_metadata(item_index, definition_id)
		action_list.set_item_tooltip(item_index, "%s：%s" % [definition.name, str(ACTION_PURPOSE.get(definition.category, ""))])
		var action_button := Button.new()
		action_button.name = "ActionChoice%d" % item_index
		action_button.custom_minimum_size = Vector2(114, 26)
		action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_button.toggle_mode = true
		action_button.text = str(ACTION_SHORT_NAMES.get(definition_id, definition.name))
		action_button.tooltip_text = action_list.get_item_tooltip(item_index)
		action_button.pressed.connect(_on_action_button_pressed.bind(item_index))
		action_buttons.add_child(action_button)
	if action_list.item_count > 0:
		action_list.select(0)
		_on_action_selected(0)


func _on_action_button_pressed(index: int) -> void:
	action_list.select(index)
	_on_action_selected(index)


func _on_action_selected(_index: int) -> void:
	_sync_action_buttons()
	var definition: ActionDefinitionData = _get_selected_definition()
	if definition == null:
		_refresh()
		return
	investment_spin.set_value_no_signal(0.0)
	_populate_study_skills(definition)
	var preferred_target_id: String = (
		map_target_id
		if PlayerActionContextService.get_target_domain(definition.category)
		== PlayerActionContextService.TARGET_DOMAIN_MAP
		else target_id
	)
	_populate_targets(definition, preferred_target_id)
	message_label.text = ""
	_refresh()


func _sync_action_buttons() -> void:
	var selected_items: PackedInt32Array = action_list.get_selected_items()
	var selected_index: int = selected_items[0] if not selected_items.is_empty() else -1
	for index: int in range(action_buttons.get_child_count()):
		var button := action_buttons.get_child(index) as Button
		if button != null:
			button.set_pressed_no_signal(index == selected_index)


func _populate_study_skills(definition: ActionDefinitionData) -> void:
	study_skill_option.clear()
	study_section.visible = definition != null and definition.category == "study_skill"
	if not study_section.visible or generation_config == null or not GameSessionService.has_player():
		return
	for skill_id: String in generation_config.skill_keys:
		if not GameSessionService.player_character.skills.has(skill_id):
			continue
		study_skill_option.add_item(generation_config.get_label("skills", skill_id))
		study_skill_option.set_item_metadata(study_skill_option.item_count - 1, skill_id)
		if skill_id == "administration":
			study_skill_option.select(study_skill_option.item_count - 1)
	_on_study_skill_selected(study_skill_option.selected)


func _on_study_skill_selected(_index: int) -> void:
	var skill_id: String = _get_selected_study_skill_id()
	if skill_id.is_empty() or not GameSessionService.has_player():
		skill_details.text = "请选择要训练的能力。"
	else:
		var current_value: int = int(GameSessionService.player_character.skills.get(skill_id, 0))
		var definition: ActionDefinitionData = _get_selected_definition()
		var success_growth: int = int(definition.success_result.get("skill_delta", 0)) if definition != null else 0
		var failure_growth: int = int(definition.failure_result.get("skill_delta", 0)) if definition != null else 0
		skill_details.text = "当前 %d · 本次可能成长 +%d（未达目标仍可 +%d）\n%s" % [
			current_value,
			success_growth,
			failure_growth,
			str(SKILL_USES.get(skill_id, "影响对应领域行动。")),
		]
	_refresh()


func _populate_targets(
	definition: ActionDefinitionData, preferred_id: String = ""
) -> void:
	var previous_id: String = preferred_id if not preferred_id.is_empty() else target_id
	var candidates: Array[Dictionary] = []
	target_option.clear()
	target_id = ""
	target_label.visible = true
	target_details.visible = true
	target_details.text = "此行动不需要目标。"
	if definition == null:
		return
	var society: SocietySimulationService = GameSessionService.society_service
	match definition.category:
		"build_relationship", "investigate_character":
			target_label.text = "目标人物"
			if society != null:
				for character_id: String in society.roster.get_background_ids():
					var background: BackgroundCharacterData = society.roster.get_background(character_id)
					_append_eligible_target(candidates, definition, "%s · %s" % [background.name, background.occupation], character_id)
				for character_id: String in society.roster.get_active_ids(false):
					var active: CharacterData = society.roster.get_active(character_id)
					_append_eligible_target(candidates, definition, "%s · %s" % [active.name, active.occupation], character_id)
		"join_organization":
			target_label.text = "目标组织"
			if society != null:
				for organization_id: String in society.organizations.get_organization_ids():
					var organization: OrganizationData = society.organizations.get_organization(organization_id)
					_append_eligible_target(candidates, definition, "%s · %s" % [organization.name, _organization_type_label(organization.type)], organization_id)
		"seek_position":
			target_label.text = "目标组织"
			if society != null and GameSessionService.has_player():
				for organization_id: String in GameSessionService.player_character.organization_ids:
					var organization: OrganizationData = society.organizations.get_organization(organization_id)
					if organization != null:
						_append_eligible_target(candidates, definition, organization.name, organization_id)
		"promote_policy", "support_control":
			target_label.text = "目标地区"
			if map_service != null:
				for unit_id: String in map_service.get_sorted_unit_ids():
					var unit: ControlUnitData = map_service.get_unit(unit_id)
					var region: RegionData = map_service.data_set.regions.get(unit.region_id) as RegionData
					var label: String = "%s%s · 支持 %.0f%%" % [
						region.name if region != null else unit.region_id,
						(" / %s" % unit.city_name if not unit.city_name.is_empty() else ""),
						unit.social_support * 100.0,
					]
					_append_eligible_target(candidates, definition, label, unit_id)
		_:
			target_label.text = "行动目标"
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (
			str(a["id"]) < str(b["id"])
			if is_equal_approx(float(a["effective"]), float(b["effective"]))
			else float(a["effective"]) > float(b["effective"])
		)
	)
	for candidate: Dictionary in candidates:
		target_option.add_item("%s · 有效 %.0f" % [
			str(candidate["label"]), float(candidate["effective"]),
		])
		target_option.set_item_metadata(
			target_option.item_count - 1, str(candidate["id"])
		)
	if target_option.item_count > 0:
		if not _select_target(previous_id):
			target_option.select(0)
			target_id = str(target_option.get_item_metadata(0))
		target_option.visible = true
		_refresh_target_details()
	else:
		target_option.visible = false
		if definition.category in ["study_skill", "perform_work"]:
			target_label.visible = false
			target_details.visible = false
		else:
			target_details.text = "当前没有符合条件的目标。"


func _append_eligible_target(
	candidates: Array[Dictionary],
	definition: ActionDefinitionData,
	label: String,
	id: String
) -> void:
	if id.is_empty() or context_service == null or not GameSessionService.has_player():
		return
	var error: String = context_service.get_target_validation_error(
		definition, GameSessionService.player_character, id
	)
	if not error.is_empty():
		return
	var context: Dictionary = context_service.build_context(
		definition,
		GameSessionService.player_character,
		id,
		roundi(investment_spin.value),
		_get_selected_study_skill_id()
	)
	if context.is_empty():
		return
	candidates.append({
		"id": id,
		"label": label,
		"effective": action_service.calculate_effective_value(
			definition, GameSessionService.player_character, context
		),
	})


func _select_target(requested_id: String) -> bool:
	if requested_id.is_empty():
		return false
	for index: int in range(target_option.item_count):
		if str(target_option.get_item_metadata(index)) == requested_id:
			target_option.select(index)
			target_id = requested_id
			_refresh_target_details()
			return true
	return false


func _on_target_selected(index: int) -> void:
	if index >= 0 and index < target_option.item_count:
		target_id = str(target_option.get_item_metadata(index))
	_refresh_target_details()
	_refresh()


func _on_investment_changed(_value: float) -> void:
	var definition: ActionDefinitionData = _get_selected_definition()
	if definition != null and PlayerActionContextService.get_target_domain(
		definition.category
	) != PlayerActionContextService.TARGET_DOMAIN_NONE:
		_populate_targets(definition, target_id)
	_refresh()


func _refresh_target_details() -> void:
	if target_id.is_empty():
		return
	var society: SocietySimulationService = GameSessionService.society_service
	if society != null:
		var public_character: Variant = society.roster.get_public_character(target_id)
		if public_character is CharacterData or public_character is BackgroundCharacterData:
			var name: String = str(public_character.name)
			var occupation: String = str(public_character.occupation)
			var region_id: String = str(public_character.region_id)
			var relation: RelationshipData = society.relationships.get_between(
				GameSessionService.player_character.id, target_id
			)
			target_details.text = "%s · %s · %s · %s" % [
				name,
				occupation,
				_region_name(region_id),
				"已有关系" if relation != null else "尚无关系",
			]
			return
		var organization: OrganizationData = society.organizations.get_organization(target_id)
		if organization != null:
			var player_id: String = GameSessionService.player_character.id
			var entry_available: bool = _entry_position_available(organization)
			target_details.text = "%s · %s · %s · %s · 入口职位%s空位" % [
				organization.name,
				_organization_type_label(organization.type),
				_region_name(organization.region_id),
				"当前为成员" if organization.member_ids.has(player_id) else "当前非成员",
				"有" if entry_available else "无",
			]
			return
	if map_service != null:
		var unit: ControlUnitData = map_service.get_unit(target_id)
		if unit != null:
			var controller: CountryData = map_service.data_set.countries.get(unit.controller_country_id) as CountryData
			target_details.text = "%s · 当前控制：%s · 社会支持 %.0f%% · %s" % [
				_region_name(unit.region_id),
				controller.name if controller != null else unit.controller_country_id,
				unit.social_support * 100.0,
				"在当前职位辖区内",
			]


func _on_begin_pressed() -> void:
	var blocked: String = _get_start_block_reason()
	if not blocked.is_empty():
		message_label.text = blocked
		return
	var definition: ActionDefinitionData = _get_selected_definition()
	var result: ActionStartResult = context_service.start_player_action(
		action_service,
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		target_id,
		roundi(investment_spin.value),
		_get_selected_study_skill_id()
	)
	if not result.is_success():
		message_label.text = "\n".join(result.errors)
		_refresh()
		return
	GameSessionService.current_action = result.action
	message_label.text = "行动已开始；基础费用与额外投入已扣除。"
	action_state_changed.emit()
	_refresh()


func _on_pause_pressed() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null or action.is_terminal():
		return
	var definition: ActionDefinitionData = map_service.data_set.actions.get(
		action.definition_id
	) as ActionDefinitionData
	if action.status == ActionInstanceData.STATUS_ACTIVE:
		action_service.pause_action(action, definition, GameSessionService.player_character, clock.total_hours, map_service)
	elif action.status == ActionInstanceData.STATUS_PAUSED:
		action_service.resume_action(action, definition, GameSessionService.player_character, clock.total_hours)
	message_label.text = "行动已暂停。" if action.status == ActionInstanceData.STATUS_PAUSED else "行动已继续。"
	action_state_changed.emit()
	_refresh()


func _on_cancel_pressed() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null or action.is_terminal():
		return
	var definition: ActionDefinitionData = map_service.data_set.actions.get(
		action.definition_id
	) as ActionDefinitionData
	action_service.cancel_action(action, definition, GameSessionService.player_character, clock.total_hours, map_service)
	GameSessionService.archive_current_action(GameSessionService.player_character)
	message_label.text = "行动已取消；已发生的时间和投入不会回退。"
	action_state_changed.emit()
	_refresh()


func _on_time_changed(_snapshot: Dictionary) -> void:
	_refresh()


func _on_dismiss_recent_pressed() -> void:
	GameSessionService.dismiss_recent_action_result()
	_refresh_recent_result()


func _refresh() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	_apply_domain_effect_if_ready(action)
	if action != null and action.is_terminal():
		GameSessionService.archive_current_action(GameSessionService.player_character)
	action = GameSessionService.current_action
	var has_player: bool = GameSessionService.has_player()
	var definition: ActionDefinitionData = _get_selected_definition()
	_update_investment_limit(definition, has_player)
	var can_edit_setup: bool = action == null or action.is_terminal()
	action_list.mouse_filter = Control.MOUSE_FILTER_STOP if can_edit_setup else Control.MOUSE_FILTER_IGNORE
	target_option.disabled = not can_edit_setup
	study_skill_option.disabled = not can_edit_setup
	investment_spin.editable = can_edit_setup
	pause_button.disabled = action == null or action.is_terminal()
	cancel_button.disabled = action == null or action.is_terminal()
	_refresh_action_description(definition)
	_refresh_funding(definition)
	_refresh_forecast(definition)
	var blocked: String = _get_start_block_reason()
	begin_button.disabled = not blocked.is_empty()
	begin_reason_label.text = "可以开始：确认目标、费用和条件后提交。" if blocked.is_empty() else "暂时不能开始：%s" % blocked
	_refresh_current_action(action)
	_refresh_recent_result()
	_refresh_action_log()


func _refresh_action_description(definition: ActionDefinitionData) -> void:
	if definition == null or generation_config == null:
		action_description.text = "选择行动后查看用途和条件。"
		return
	var primary_skill_id: String = context_service.get_action_primary_skill_id(
		definition,
		GameSessionService.player_character,
		_get_selected_study_skill_id()
	)
	var primary_label: String = generation_config.get_label(
		"skills", primary_skill_id
	)
	var permission: String = (
		"无需职位权限"
		if definition.position_permission_required.is_empty()
		else "需要%s" % _permission_label(definition.position_permission_required)
	)
	var base_hours: int = ceili(definition.total_work / maxf(definition.base_progress_per_hour, 0.01))
	var eligibility: String = _definition_eligibility_reason(definition)
	action_description.text = "[font_size=18][b]%s[/b][/font_size]\n%s\n主要能力：%s · 基础费用：%d 财富 · 基础耗时：约 %d 小时\n%s · [color=%s]%s[/color]" % [
		definition.name,
		str(ACTION_PURPOSE.get(definition.category, "推进人物的长期目标。")),
		primary_label,
		context_service.get_base_funding_cost(definition) if context_service != null else 0,
		base_hours,
		permission,
		"#9bd3a7" if eligibility.is_empty() else "#efaa70",
		"当前条件满足" if eligibility.is_empty() else eligibility,
	]


func _refresh_funding(definition: ActionDefinitionData) -> void:
	if definition == null or context_service == null or not GameSessionService.has_player():
		funding_summary.text = "财富与费用尚未就绪。"
		return
	var wealth: int = int(GameSessionService.player_character.current_status.get("wealth", 0))
	var base_cost: int = context_service.get_base_funding_cost(definition)
	var extra: int = roundi(investment_spin.value)
	var total: int = context_service.get_funding_cost(definition, extra)
	var context: Dictionary = context_service.build_context(
		definition,
		GameSessionService.player_character,
		target_id,
		extra,
		_get_selected_study_skill_id()
	)
	var preparation: float = float(context.get("preparation", 0.0))
	var funding: float = float(context.get("funding", 0.0))
	funding_summary.text = "当前财富 %d · 基础费用 %d · 额外投入 %d · 总费用 %d\n本次准备度 %.0f · 资金支持 %.0f" % [
		wealth, base_cost, extra, total, preparation, funding,
	]


func _refresh_forecast(definition: ActionDefinitionData) -> void:
	if definition == null or context_service == null or action_service == null or not GameSessionService.has_player():
		context_label.text = "行动条件尚未就绪。"
		return
	var context: Dictionary = context_service.build_context(
		definition,
		GameSessionService.player_character,
		target_id,
		roundi(investment_spin.value),
		_get_selected_study_skill_id()
	)
	if context.is_empty():
		context_label.text = "请完成技能与目标选择。"
		return
	var primary_skill_id: String = context_service.get_action_primary_skill_id(
		definition,
		GameSessionService.player_character,
		_get_selected_study_skill_id()
	)
	var ability: int = int(GameSessionService.player_character.skills.get(primary_skill_id, 0))
	var effective: float = action_service.calculate_effective_value(definition, GameSessionService.player_character, context)
	var efficiency: float = action_service.calculate_efficiency(definition, effective)
	var hours: int = ceili(definition.total_work / maxf(efficiency, 0.01))
	var outlook: String = rules.get_outlook(
		effective,
		definition.guaranteed_success_threshold,
		definition.success_threshold
	)
	var success_gap: float = maxf(definition.success_threshold - effective, 0.0)
	var guarantee_gap: float = maxf(
		definition.guaranteed_success_threshold - effective, 0.0
	)
	context_label.text = "[b]能力[/b] %d　[b]准备[/b] %.0f　[b]资金支持[/b] %.0f\n[b]关系支持[/b] %.0f　[b]组织支持[/b] %.0f　[b]目标匹配[/b] %.0f　[b]目标阻力[/b] %.0f\n────────────\n[b]当前有效值[/b] %.0f　[b]成功线[/b] %.0f　[b]保证线[/b] %.0f\n当前把握：[color=#9bd3a7]%s[/color]\n距成功线：%.0f　距保证线：%.0f\n预计用时：约 %d 小时" % [
		ability,
		float(context.get("preparation", 0.0)),
		float(context.get("funding", 0.0)),
		float(context.get("relationship_support", 0.0)),
		float(context.get("organization_support", 0.0)),
		float(context.get("social_match_bonus", 0.0))
		+ float(context.get("organization_match_bonus", 0.0)),
		float(context.get("target_resistance", 0.0)),
		effective,
		definition.success_threshold,
		definition.guaranteed_success_threshold,
		outlook,
		success_gap,
		guarantee_gap,
		hours,
	]


func _refresh_current_action(action: ActionInstanceData) -> void:
	if action == null:
		progress_bar.value = 0.0
		summary_label.text = "尚无当前行动。设置区会保留在上方；行动开始后可在此查看进度、暂停、继续或取消。"
		return
	progress_bar.value = action.get_progress_ratio() * 100.0
	pause_button.text = "继续行动" if action.status == ActionInstanceData.STATUS_PAUSED else "暂停行动"
	var definition: ActionDefinitionData = (
		map_service.data_set.actions.get(action.definition_id) as ActionDefinitionData
		if map_service != null
		else null
	)
	var name: String = definition.name if definition != null else "长期行动"
	var target_text: String = _target_display_name(action.target_id)
	var study_line: String = ""
	if definition != null and definition.category == "study_skill":
		var skill_id: String = str(action.context.get("study_skill_id", definition.primary_skill))
		study_line = "\n学习能力：%s" % (
			generation_config.get_label("skills", skill_id)
			if generation_config != null
			else skill_id
		)
	var result_line: String = ""
	if not action.result_description.is_empty():
		result_line = "\n结果：%s" % action.result_description
	var estimate: String = "暂停或已结束"
	if action.estimated_completion_hour >= 0:
		estimate = _format_world_hour(action.estimated_completion_hour)
	summary_label.text = "[font_size=18][b]%s[/b][/font_size]\n状态：%s · 开始：%s\n进度：%.1f / %.1f · 当前效率 %.2f\n预计完成：%s · 当前把握：%s\n目标：%s%s%s" % [
		name,
		_status_label(action.status),
		_format_world_hour(action.start_hour),
		action.accumulated_work,
		action.total_work,
		action.current_efficiency,
		estimate,
		action.outlook,
		target_text,
		study_line,
		result_line,
	]


func _refresh_recent_result() -> void:
	var result: Dictionary = GameSessionService.recent_action_result
	var has_result: bool = not result.is_empty()
	recent_result_header.visible = has_result
	recent_result_label.visible = has_result
	if not has_result or map_service == null or generation_config == null:
		return
	var definition: ActionDefinitionData = map_service.data_set.actions.get(
		str(result.get("definition_id", ""))
	) as ActionDefinitionData
	var action_name: String = definition.name if definition != null else "长期行动"
	var target_text: String = _result_target_text(result)
	var skill_text: String = "无"
	var skill_id: String = str(result.get("skill_id", ""))
	var skill_delta: int = int(result.get("skill_delta", 0))
	if not skill_id.is_empty() and skill_delta != 0:
		skill_text = "%s %+d" % [
			generation_config.get_label("skills", skill_id), skill_delta,
		]
	recent_result_label.text = "[b]%s[/b] · %s\n目标：%s\n结果：%s\n技能成长：%s · 财富变化：%+d\n用时：%d 小时 · 完成：%s" % [
		action_name,
		_status_label(str(result.get("status", ""))),
		target_text,
		str(result.get("result_description", "")),
		skill_text,
		int(result.get("wealth_delta", 0)),
		int(result.get("duration_hours", 0)),
		_format_world_hour(int(result.get("completion_hour", 0))),
	]


func _refresh_action_log() -> void:
	if GameSessionService.action_history.is_empty():
		action_log_label.text = "尚无行动记录。"
		return
	if map_service == null:
		action_log_label.text = "行动日志正在加载。"
		return
	var lines: Array[String] = []
	var first_index: int = maxi(GameSessionService.action_history.size() - 10, 0)
	for index: int in range(GameSessionService.action_history.size() - 1, first_index - 1, -1):
		var record: Dictionary = GameSessionService.action_history[index]
		var definition: ActionDefinitionData = map_service.data_set.actions.get(
			str(record.get("definition_id", ""))
		) as ActionDefinitionData
		lines.append("%s · %s · %s" % [
			_format_world_hour(int(record.get("completion_hour", 0))),
			definition.name if definition != null else "长期行动",
			str(record.get("result_description", "")),
		])
	action_log_label.text = "\n".join(lines)


func _result_target_text(result: Dictionary) -> String:
	var study_skill_id: String = str(result.get("study_skill_id", ""))
	if not study_skill_id.is_empty():
		return generation_config.get_label("skills", study_skill_id)
	return _target_display_name(str(result.get("target_id", "")))


func _get_start_block_reason() -> String:
	if not GameSessionService.has_player():
		return "需要先创建玩家人物"
	if action_service == null or context_service == null or clock == null:
		return "行动服务尚未就绪"
	var action: ActionInstanceData = GameSessionService.current_action
	if action != null and not action.is_terminal():
		return "当前已有进行中的行动"
	var definition: ActionDefinitionData = _get_selected_definition()
	if definition == null:
		return "尚未选择行动"
	var interruption: String = action_service.get_interruption_reason(
		definition, GameSessionService.player_character
	)
	if not interruption.is_empty():
		return str(INTERRUPTION_LABELS.get(interruption, interruption))
	var eligibility: String = _definition_eligibility_reason(definition)
	if not eligibility.is_empty():
		return eligibility
	if definition.category == "study_skill" and _get_selected_study_skill_id().is_empty():
		return "尚未选择要学习的技能"
	var target_error: String = context_service.get_target_validation_error(
		definition, GameSessionService.player_character, target_id
	)
	if not target_error.is_empty():
		return "没有合法目标：%s" % target_error
	if not context_service.can_afford(
		definition, GameSessionService.player_character, roundi(investment_spin.value)
	):
		return "财富不足，无法支付总费用"
	return ""


func _definition_eligibility_reason(definition: ActionDefinitionData) -> String:
	if definition == null or not GameSessionService.has_player():
		return "人物尚未就绪"
	if not definition.position_permission_required.is_empty() and not _get_player_permissions().has(definition.position_permission_required):
		return "缺少%s" % _permission_label(definition.position_permission_required)
	return ""


func _update_investment_limit(
	definition: ActionDefinitionData, has_player: bool
) -> void:
	if context_service == null or definition == null or not has_player:
		investment_spin.max_value = 0.0
		investment_spin.set_value_no_signal(0.0)
		return
	var wealth: int = int(GameSessionService.player_character.current_status.get("wealth", 0))
	var available_extra: int = maxi(wealth - context_service.get_base_funding_cost(definition), 0)
	investment_spin.max_value = mini(context_service.get_max_extra_funding(), available_extra)
	if investment_spin.value > investment_spin.max_value:
		investment_spin.set_value_no_signal(investment_spin.max_value)


func _apply_domain_effect_if_ready(action: ActionInstanceData) -> void:
	if action == null or action.status != ActionInstanceData.STATUS_COMPLETED or action.domain_effect_applied or map_service == null or GameSessionService.society_service == null:
		return
	var definition: ActionDefinitionData = map_service.data_set.actions.get(action.definition_id) as ActionDefinitionData
	if definition == null:
		action.domain_effect_applied = true
		return
	var applied: bool = GameSessionService.society_service.apply_action_domain_effect(action, definition, map_service)
	if applied:
		refresh_permissions()
	action_state_changed.emit()


func _get_selected_study_skill_id() -> String:
	if not study_section.visible or study_skill_option.item_count == 0 or study_skill_option.selected < 0:
		return ""
	return str(study_skill_option.get_item_metadata(study_skill_option.selected))


func _get_player_permissions() -> Array[String]:
	if GameSessionService.society_service == null or not GameSessionService.has_player():
		return []
	return GameSessionService.society_service.organizations.get_character_permissions(
		GameSessionService.player_character.id
	)


func _get_selected_definition() -> ActionDefinitionData:
	if map_service == null:
		return null
	var selected: PackedInt32Array = action_list.get_selected_items()
	if selected.is_empty():
		return null
	var definition_id: String = str(action_list.get_item_metadata(selected[0]))
	return map_service.data_set.actions.get(definition_id) as ActionDefinitionData


func _target_display_name(id: String) -> String:
	if id.is_empty():
		return "无需目标"
	var society: SocietySimulationService = GameSessionService.society_service
	if society != null:
		var public_character: Variant = society.roster.get_public_character(id)
		if public_character is CharacterData or public_character is BackgroundCharacterData:
			return str(public_character.name)
		var organization: OrganizationData = society.organizations.get_organization(id)
		if organization != null:
			return organization.name
	if map_service != null:
		var unit: ControlUnitData = map_service.get_unit(id)
		if unit != null:
			return "%s%s" % [_region_name(unit.region_id), " / %s" % unit.city_name if not unit.city_name.is_empty() else ""]
	return id


func _region_name(region_id: String) -> String:
	if map_service == null:
		return "未知地区"
	var region: RegionData = map_service.data_set.regions.get(region_id) as RegionData
	return region.name if region != null else "未知地区"


func _entry_position_available(organization: OrganizationData) -> bool:
	var society: SocietySimulationService = GameSessionService.society_service
	return (
		organization != null
		and society != null
		and society.organizations.has_entry_vacancy(organization.id)
	)


func _format_world_hour(total_hour: int) -> String:
	if clock == null:
		return "第 %d 小时" % total_hour
	var delta: int = total_hour - clock.total_hours
	var year_value: int = clock.year
	var month_value: int = clock.month
	var day_value: int = clock.day
	var hour_value: int = clock.hour + delta
	while hour_value >= 24:
		hour_value -= 24
		day_value += 1
		var days_in_month: int = _days_in_month(year_value, month_value)
		if day_value > days_in_month:
			day_value = 1
			month_value += 1
			if month_value > 12:
				month_value = 1
				year_value += 1
	while hour_value < 0:
		hour_value += 24
		day_value -= 1
		if day_value < 1:
			month_value -= 1
			if month_value < 1:
				month_value = 12
				year_value -= 1
			day_value = _days_in_month(year_value, month_value)
	return "%04d年%02d月%02d日 %02d:00" % [year_value, month_value, day_value, hour_value]


static func _days_in_month(year_value: int, month_value: int) -> int:
	if month_value == 2:
		return 29 if year_value % 400 == 0 or (year_value % 4 == 0 and year_value % 100 != 0) else 28
	return 30 if month_value in [4, 6, 9, 11] else 31


static func _permission_label(permission_id: String) -> String:
	return str(PERMISSION_LABELS.get(permission_id, permission_id))


static func _organization_type_label(type_id: String) -> String:
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


static func _status_label(status: String) -> String:
	return str({
		ActionInstanceData.STATUS_ACTIVE: "进行中",
		ActionInstanceData.STATUS_PAUSED: "已暂停",
		ActionInstanceData.STATUS_COMPLETED: "已完成",
		ActionInstanceData.STATUS_CANCELLED: "已取消",
		ActionInstanceData.STATUS_INTERRUPTED: "已中断",
	}.get(status, "未知"))
