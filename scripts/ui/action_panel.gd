class_name ActionPanel
extends PanelContainer
## UI adapter for one player action. Formula and progression stay in ActionService.

signal close_requested

@onready var close_button: Button = %CloseButton
@onready var action_option: OptionButton = %ActionOption
@onready var target_label: Label = %TargetLabel
@onready var target_option: OptionButton = %TargetOption
@onready var preparation_input: SpinBox = %PreparationInput
@onready var organization_input: SpinBox = %OrganizationInput
@onready var relationship_input: SpinBox = %RelationshipInput
@onready var funding_input: SpinBox = %FundingInput
@onready var resistance_input: SpinBox = %ResistanceInput
@onready var permission_check: CheckBox = %PermissionCheck
@onready var begin_button: Button = %BeginButton
@onready var pause_button: Button = %PauseButton
@onready var cancel_button: Button = %CancelButton
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var summary_label: RichTextLabel = %SummaryLabel
@onready var message_label: Label = %MessageLabel

var clock: SimulationClock
var map_service: MapControlService
var action_service: ActionService
var rules: ActionRulesConfig
var target_id: String = ""
var map_target_id: String = ""
var _definition_ids: Array[String] = []


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	action_option.item_selected.connect(_on_action_selected)
	target_option.item_selected.connect(_on_target_selected)
	begin_button.pressed.connect(_on_begin_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	for input: SpinBox in [preparation_input, organization_input, relationship_input, funding_input, resistance_input]:
		input.value_changed.connect(_on_context_changed)
	permission_check.toggled.connect(_on_context_changed.unbind(1))
	_refresh()


func setup(simulation_clock: SimulationClock, control_service: MapControlService) -> bool:
	clock = simulation_clock
	map_service = control_service
	rules = ActionRulesConfig.new()
	if rules.load_from_file() != OK:
		message_label.text = rules.error_message
		begin_button.disabled = true
		return false
	action_service = ActionService.new(rules, GameSessionService.action_id_service)
	clock.time_changed.connect(_on_time_changed)
	_populate_actions()
	_refresh()
	return true


func set_target(control_unit_id: String) -> void:
	map_target_id = control_unit_id
	_populate_targets(_get_selected_definition())
	_refresh()


func refresh_permissions() -> void:
	_on_action_selected(action_option.selected)


func _populate_actions() -> void:
	action_option.clear()
	_definition_ids.clear()
	for raw_id: Variant in map_service.data_set.actions:
		_definition_ids.append(str(raw_id))
	_definition_ids.sort()
	for definition_id: String in _definition_ids:
		var definition: ActionDefinitionData = map_service.data_set.actions[definition_id] as ActionDefinitionData
		action_option.add_item(definition.name)
		action_option.set_item_metadata(action_option.item_count - 1, definition_id)
	_on_action_selected(action_option.selected)


func _on_action_selected(_index: int) -> void:
	var definition: ActionDefinitionData = _get_selected_definition()
	if definition == null:
		return
	var permissions: Array[String] = _get_player_permissions()
	permission_check.text = (
		("已具备职位权限：%s" if permissions.has(definition.position_permission_required) else "缺少职位权限：%s") % definition.position_permission_required
		if not definition.position_permission_required.is_empty()
		else "此行动不要求职位权限"
	)
	permission_check.disabled = true
	permission_check.button_pressed = definition.position_permission_required.is_empty() or permissions.has(definition.position_permission_required)
	_populate_targets(definition)
	_refresh()


func _populate_targets(definition: ActionDefinitionData) -> void:
	var previous_id: String = target_id
	target_option.clear()
	target_id = ""
	if definition == null:
		return
	var society: SocietySimulationService = GameSessionService.society_service
	match definition.category:
		"build_relationship":
			target_label.text = "目标人物"
			if society != null:
				for character_id: String in society.roster.get_background_ids():
					var character: BackgroundCharacterData = society.roster.get_background(character_id)
					_add_target(character.name, character_id, previous_id)
				for character_id: String in society.roster.get_active_ids(false):
					_add_target(society.roster.get_active(character_id).name, character_id, previous_id)
		"investigate_character":
			target_label.text = "目标人物"
			if society != null:
				for character_id: String in society.roster.get_active_ids(false):
					_add_target(society.roster.get_active(character_id).name, character_id, previous_id)
		"join_organization":
			target_label.text = "目标组织"
			if society != null:
				for organization_id: String in society.organizations.get_organization_ids():
					var organization: OrganizationData = society.organizations.get_organization(organization_id)
					if organization.country_id == GameSessionService.player_character.country_id and not organization.member_ids.has(GameSessionService.player_character.id):
						_add_target(organization.name, organization_id, previous_id)
		"seek_position":
			target_label.text = "目标组织"
			if society != null:
				for organization_id: String in GameSessionService.player_character.organization_ids:
					var organization: OrganizationData = society.organizations.get_organization(organization_id)
					if organization != null:
						_add_target(organization.name, organization_id, previous_id)
		"promote_policy", "support_control":
			target_label.text = "目标控制单元"
			_add_target(map_target_id, map_target_id, previous_id)
		_:
			target_label.text = "此行动无需目标"
	if target_option.item_count > 0:
		target_id = str(target_option.get_item_metadata(target_option.selected))
	target_option.visible = target_option.item_count > 0


func _add_target(label: String, id: String, selected_id: String) -> void:
	if id.is_empty():
		return
	target_option.add_item(label)
	target_option.set_item_metadata(target_option.item_count - 1, id)
	if id == selected_id:
		target_option.select(target_option.item_count - 1)


func _on_target_selected(index: int) -> void:
	if index >= 0 and index < target_option.item_count:
		target_id = str(target_option.get_item_metadata(index))


func _on_begin_pressed() -> void:
	if action_service == null or not GameSessionService.has_player():
		message_label.text = "需要先创建玩家人物。"
		return
	if GameSessionService.current_action != null and not GameSessionService.current_action.is_terminal():
		message_label.text = "每个人物同时只能进行一个主要行动。"
		return
	var definition: ActionDefinitionData = _get_selected_definition()
	var result: ActionStartResult = action_service.start_action(
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		_build_context(definition)
	)
	if not result.is_success():
		message_label.text = "\n".join(result.errors)
		return
	GameSessionService.current_action = result.action
	message_label.text = "行动已开始。"
	_refresh()


func _on_pause_pressed() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null:
		return
	var definition: ActionDefinitionData = map_service.data_set.actions[action.definition_id] as ActionDefinitionData
	if action.status == ActionInstanceData.STATUS_ACTIVE:
		action_service.pause_action(action, definition, GameSessionService.player_character, clock.total_hours, map_service)
	elif action.status == ActionInstanceData.STATUS_PAUSED:
		action_service.resume_action(action, definition, GameSessionService.player_character, clock.total_hours)
	_refresh()


func _on_cancel_pressed() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null:
		return
	var definition: ActionDefinitionData = map_service.data_set.actions[action.definition_id] as ActionDefinitionData
	action_service.cancel_action(action, definition, GameSessionService.player_character, clock.total_hours, map_service)
	_refresh()


func _on_context_changed(_value: float = 0.0) -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null or action.is_terminal() or action_service == null:
		_refresh()
		return
	var definition: ActionDefinitionData = map_service.data_set.actions[action.definition_id] as ActionDefinitionData
	action_service.update_context(
		action, definition, GameSessionService.player_character, clock.total_hours,
		_build_context(definition), map_service
	)
	_refresh()


func _on_time_changed(_snapshot: Dictionary) -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action != null and not action.is_terminal():
		var definition: ActionDefinitionData = map_service.data_set.actions[action.definition_id] as ActionDefinitionData
		action_service.update_to_hour(
			action, definition, GameSessionService.player_character, clock.total_hours, map_service
		)
	_refresh()


func _refresh() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	_apply_domain_effect_if_ready(action)
	var has_player: bool = GameSessionService.has_player()
	var selected_definition: ActionDefinitionData = _get_selected_definition()
	begin_button.disabled = not has_player or action_service == null or (action != null and not action.is_terminal()) or (_definition_requires_target(selected_definition) and target_id.is_empty())
	pause_button.disabled = action == null or action.is_terminal()
	cancel_button.disabled = action == null or action.is_terminal()
	if action == null:
		progress_bar.value = 0.0
		summary_label.text = "尚无当前行动。\n\n准备、支持和资金可提高效率与成功把握；正式界面不显示精确成功概率。"
		return
	progress_bar.value = action.get_progress_ratio() * 100.0
	pause_button.text = "恢复行动" if action.status == ActionInstanceData.STATUS_PAUSED else "暂停行动"
	var definition: ActionDefinitionData = map_service.data_set.actions.get(action.definition_id) as ActionDefinitionData if map_service != null else null
	var name: String = definition.name if definition != null else action.definition_id
	var estimate: String = "暂停/已结束" if action.estimated_completion_hour < 0 else "第 %d 小时" % action.estimated_completion_hour
	var result_line: String = "\n结果：%s" % action.result_description if not action.result_description.is_empty() else ""
	summary_label.text = "[font_size=18]%s[/font_size]\n状态：%s\n进度：%.1f / %.1f\n成功把握：%s\n预计完成：%s\n目标：%s%s" % [
		name, _status_label(action.status), action.accumulated_work, action.total_work,
		action.outlook, estimate, action.target_id, result_line,
	]


func _apply_domain_effect_if_ready(action: ActionInstanceData) -> void:
	if action == null or action.status != ActionInstanceData.STATUS_COMPLETED or map_service == null or GameSessionService.society_service == null:
		return
	var definition: ActionDefinitionData = map_service.data_set.actions.get(
		action.definition_id
	) as ActionDefinitionData
	if definition != null:
		GameSessionService.society_service.apply_action_domain_effect(
			action, definition, map_service
		)


func _build_context(definition: ActionDefinitionData) -> Dictionary:
	var permissions: Array[String] = _get_player_permissions()
	return {
		"target_id": target_id,
		"position_permissions": permissions,
		"organization_support": organization_input.value,
		"relationship_support": relationship_input.value,
		"funding": funding_input.value,
		"preparation": preparation_input.value,
		"target_resistance": resistance_input.value,
	}


func _get_player_permissions() -> Array[String]:
	if GameSessionService.society_service == null or GameSessionService.society_service.organizations == null or not GameSessionService.has_player():
		return []
	return GameSessionService.society_service.organizations.get_character_permissions(
		GameSessionService.player_character.id
	)


func _get_selected_definition() -> ActionDefinitionData:
	if map_service == null or action_option.item_count == 0:
		return null
	var definition_id: String = str(action_option.get_item_metadata(action_option.selected))
	return map_service.data_set.actions.get(definition_id) as ActionDefinitionData


static func _definition_requires_target(definition: ActionDefinitionData) -> bool:
	return definition != null and definition.category in [
		"build_relationship", "join_organization", "seek_position",
		"investigate_character", "promote_policy", "support_control",
	]


static func _status_label(status: String) -> String:
	return {
		ActionInstanceData.STATUS_ACTIVE: "进行中",
		ActionInstanceData.STATUS_PAUSED: "已暂停",
		ActionInstanceData.STATUS_COMPLETED: "已完成",
		ActionInstanceData.STATUS_CANCELLED: "已取消",
		ActionInstanceData.STATUS_INTERRUPTED: "已中断",
	}.get(status, status)
