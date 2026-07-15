extends Control
## Binds the persistent authoritative world session to presentation controls.

const UiStrings = preload("res://scripts/ui/ui_strings.gd")
const DRAWER_ANIMATION_SECONDS: float = 0.22
const DRAWER_OPEN_X: float = 14.0

@onready var world_controller: MapWorldController = %MapWorldController
@onready var clock_runner: SimulationRunner = %SimulationRunner
@onready var map_canvas: StrategicMapCanvas = %MapCanvas
@onready var title_label: Label = %TitleLabel
@onready var date_label: Label = %DateLabel
@onready var clock_status_label: Label = %ClockStatusLabel
@onready var war_status_label: Label = %WarStatusLabel
@onready var player_summary_label: Label = %PlayerSummaryLabel
@onready var action_status_label: Label = %ActionStatusLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_1_button: Button = %Speed1Button
@onready var speed_2_button: Button = %Speed2Button
@onready var speed_4_button: Button = %Speed4Button
@onready var speed_8_button: Button = %Speed8Button
@onready var save_button: Button = %SaveButton
@onready var more_button: MenuButton = %MoreButton
@onready var character_button: Button = %CharacterButton
@onready var character_panel: CharacterProfilePanel = %CharacterProfilePanel
@onready var action_button: Button = %ActionButton
@onready var action_panel: ActionPanel = %ActionPanel
@onready var social_button: Button = %SocialButton
@onready var social_panel: SocialSystemPanel = %SocialSystemPanel
@onready var world_activity_button: Button = %WorldActivityButton
@onready var world_activity_panel: WorldActivityPanel = %WorldActivityPanel
@onready var developer_panel: DeveloperPanel = %DeveloperPanel
@onready var modal_layer: Control = %ModalLayer
@onready var modal_backdrop: ColorRect = %ModalBackdrop
@onready var selection_title: Label = %SelectionTitle
@onready var details_label: RichTextLabel = %DetailsLabel
@onready var pressure_button: Button = %PressureButton
@onready var transfer_button: Button = %TransferButton
@onready var zoom_label: Label = %ZoomLabel

var _clock: SimulationClock
var _map_service: MapControlService
var _selected_unit_id: String = ""
var _autosave: AutosaveCoordinator
var _active_drawer: Control
var _drawer_tween: Tween


func _ready() -> void:
	title_label.text = UiStrings.MAP_TITLE
	pause_button.pressed.connect(_on_pause_pressed)
	speed_1_button.pressed.connect(_on_speed_pressed.bind(1))
	speed_2_button.pressed.connect(_on_speed_pressed.bind(2))
	speed_4_button.pressed.connect(_on_speed_pressed.bind(4))
	speed_8_button.pressed.connect(_on_speed_pressed.bind(8))
	save_button.pressed.connect(_on_save_pressed)
	_refresh_more_menu()
	more_button.get_popup().id_pressed.connect(_on_more_item_pressed)
	character_button.pressed.connect(_on_character_pressed)
	action_button.pressed.connect(_on_action_pressed)
	social_button.pressed.connect(_on_social_pressed)
	world_activity_button.pressed.connect(_on_world_activity_pressed)
	character_button.disabled = not GameSessionService.has_player()
	action_button.disabled = not GameSessionService.has_player()
	social_button.disabled = not GameSessionService.has_player()
	world_activity_button.disabled = not GameSessionService.has_player()
	character_panel.close_requested.connect(_on_character_panel_close_requested)
	action_panel.close_requested.connect(_on_action_panel_close_requested)
	action_panel.action_state_changed.connect(_on_action_state_changed)
	social_panel.close_requested.connect(_on_social_panel_close_requested)
	social_panel.request_action.connect(_on_social_action_requested)
	world_activity_panel.close_requested.connect(_on_world_activity_panel_close_requested)
	developer_panel.close_requested.connect(_on_developer_panel_close_requested)
	developer_panel.developer_mode_changed.connect(_on_developer_mode_changed)
	social_panel.society_changed.connect(action_panel.refresh_permissions)
	pressure_button.pressed.connect(_on_pressure_pressed)
	transfer_button.pressed.connect(_on_transfer_pressed)
	map_canvas.unit_selected.connect(_on_unit_selected)
	modal_backdrop.gui_input.connect(_on_modal_backdrop_input)
	_close_primary_panel(false)

	_bind_persistent_clock()
	if _clock == null:
		_show_world_error("权威游戏时钟未初始化。")
		return
	_bind_persistent_map()
	if _map_service == null:
		_show_world_error(world_controller.initialization_error)
		return

	_map_service.control_unit_changed.connect(_on_control_unit_changed)
	_map_service.war_state_changed.connect(_on_war_state_changed)
	if not _restore_pending_save():
		return
	_initialize_society()
	_initialize_autosave()
	GameSessionService.set_world_services(_clock, _map_service, _autosave)

	developer_panel.setup(_clock, _map_service, _autosave)
	map_canvas.setup(_map_service)
	map_canvas.select_unit("control:r3_c4")
	action_panel.setup(_clock, _map_service)
	action_panel.set_target(_selected_unit_id)
	if GameSessionService.society_service != null:
		character_panel.setup(GameSessionService.society_service)
		social_panel.setup(_clock, GameSessionService.society_service)
		world_activity_panel.refresh_view()
	zoom_label.text = UiStrings.MAP_HELP
	_apply_developer_visibility()
	_refresh_war_status()
	_refresh_player_status()


func _bind_persistent_clock() -> void:
	if GameSessionService.world_clock != null:
		clock_runner.clock = GameSessionService.world_clock
	_clock = clock_runner.clock
	if _clock == null:
		return
	_clock.time_changed.connect(_on_clock_changed)
	_clock.pause_changed.connect(_on_pause_changed)
	_clock.speed_changed.connect(_on_speed_changed)
	_refresh_clock()


func _bind_persistent_map() -> void:
	if GameSessionService.world_map_service != null:
		world_controller.control_service = GameSessionService.world_map_service
		world_controller.data_set = GameSessionService.world_map_service.data_set
		world_controller.rules = GameSessionService.world_map_service.rules
	_map_service = world_controller.control_service


func _restore_pending_save() -> bool:
	if GameSessionService.pending_load_path.is_empty():
		return true
	var pending_path: String = GameSessionService.pending_load_path
	GameSessionService.pending_load_path = ""
	var previous_clock_state: Dictionary = _clock.get_persistent_state()
	var previous_world_state: Dictionary = _map_service.get_persistent_state()
	var save_service := GameSaveService.new()
	var loaded: SaveOperationResult = save_service.load_from_path(pending_path)
	if loaded.success:
		loaded = save_service.restore_snapshot(loaded.snapshot, _clock, _map_service)
	if loaded.success:
		return true
	_map_service.restore_persistent_state(previous_world_state)
	_clock.restore_persistent_state(previous_clock_state)
	var message: String = "加载存档失败：%s" % loaded.message
	LogService.error("StrategicMapView", message)
	GameSessionService.clear()
	GameSessionService.pending_menu_message = message
	var change_error: Error = get_tree().change_scene_to_file(
		"res://scenes/menu/main_menu.tscn"
	)
	if change_error != OK:
		_show_world_error("%s\n无法返回主菜单：%s" % [message, error_string(change_error)])
	return false


func _initialize_society() -> void:
	if not GameSessionService.has_player():
		return
	if GameSessionService.society_service == null:
		GameSessionService.society_service = SocietySimulationService.new()
		if not GameSessionService.society_service.initialize(
			GameSessionService.player_character, _map_service.data_set
		):
			LogService.error("StrategicMapView", GameSessionService.society_service.initialization_error)
	GameSessionService.society_service.attach_clock(_clock)
	var influence_service: RegionalInfluenceService = GameSessionService.society_service.regional_influence
	if influence_service != null and not influence_service.social_influence_changed.is_connected(
		_on_social_influence_changed
	):
		influence_service.social_influence_changed.connect(_on_social_influence_changed)
	character_button.disabled = false
	action_button.disabled = false
	social_button.disabled = false
	world_activity_button.disabled = false


func _initialize_autosave() -> void:
	if GameSessionService.world_autosave == null:
		GameSessionService.world_autosave = AutosaveCoordinator.new()
	_autosave = GameSessionService.world_autosave
	_autosave.attach(_clock, _map_service)


func _on_unit_selected(unit_id: String) -> void:
	_selected_unit_id = unit_id
	action_panel.set_target(unit_id)
	_refresh_selection_panel()


func _on_control_unit_changed(unit_id: String) -> void:
	if unit_id == _selected_unit_id:
		_refresh_selection_panel()


func _on_war_state_changed() -> void:
	_refresh_war_status()
	_refresh_selection_panel()


func _on_social_influence_changed(region_id: String) -> void:
	if _map_service == null:
		return
	var unit: ControlUnitData = _map_service.get_unit(_selected_unit_id)
	if unit != null and unit.region_id == region_id:
		_refresh_selection_panel()


func _refresh_selection_panel() -> void:
	var unit: ControlUnitData = _map_service.get_unit(_selected_unit_id)
	if unit == null:
		return
	var region: RegionData = _map_service.data_set.regions[unit.region_id] as RegionData
	var legal_country: CountryData = (
		_map_service.data_set.countries[unit.de_jure_country_id] as CountryData
	)
	var controller_country: CountryData = (
		_map_service.data_set.countries[unit.controller_country_id] as CountryData
	)
	var summary: Dictionary = _map_service.get_region_summary(unit.region_id)
	var control_lines: Array[String] = []
	var percentages: Dictionary = summary["control_percentages"] as Dictionary
	var country_ids: Array[String] = []
	for raw_id: Variant in percentages:
		country_ids.append(str(raw_id))
	country_ids.sort()
	for country_id: String in country_ids:
		var country: CountryData = _map_service.data_set.countries[country_id] as CountryData
		control_lines.append("%s %.0f%%" % [country.name, float(percentages[country_id]) * 100.0])
	var city_suffix: String = " · %s" % unit.city_name if not unit.city_name.is_empty() else ""
	selection_title.text = "%s%s" % [region.name, city_suffix]
	var administration_label: String = "军事控制" if _map_service.is_war_active() else "实际管辖"
	var stage_label: String = "控制阶段" if _map_service.is_war_active() else "地区状态"
	var strength_label: String = "控制强度" if _map_service.is_war_active() else "治理强度"
	var contested_label: String = "争夺程度" if _map_service.is_war_active() else "地方动荡"
	var summary_label: String = "地区控制" if _map_service.is_war_active() else "地区管辖"
	var average_label: String = "平均争夺" if _map_service.is_war_active() else "平均动荡"
	details_label.text = """控制单元  %s
网格坐标  (%d, %d)

法理归属  %s
%s  %s
%s  %s
%s  %.0f%%
%s  %.0f%%
社会支持  %.0f%%

地区人口  %s
%s  %s
%s  %.0f%%
铁路状态  %s（%d 条地区连接）
社会影响  %s""" % [
		unit.id,
		unit.grid_x,
		unit.grid_y,
		legal_country.name,
		administration_label,
		controller_country.name,
		stage_label,
		_stage_text(_map_service.get_control_stage(unit.id)),
		strength_label,
		unit.control_strength * 100.0,
		contested_label,
		unit.contested_level * 100.0,
		unit.social_support * 100.0,
		_format_integer(int(summary["population_total"])),
		summary_label,
		" / ".join(control_lines),
		average_label,
		float(summary["average_contested"]) * 100.0,
		_infrastructure_state_text(unit.infrastructure_state),
		int(summary["railroad_connections"]),
		_format_social_influence(summary["social_influence"] as Dictionary),
	]
	pressure_button.disabled = false
	transfer_button.disabled = false
	_apply_developer_visibility()


func _on_pressure_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var unit: ControlUnitData = _map_service.get_unit(_selected_unit_id)
	if unit == null:
		return
	var attacker: String = _map_service.get_other_country_id(unit.controller_country_id)
	_map_service.apply_control_pressure(unit.id, attacker)


func _on_transfer_pressed() -> void:
	if not _debug_mutation_allowed():
		return
	var unit: ControlUnitData = _map_service.get_unit(_selected_unit_id)
	if unit == null:
		return
	var new_controller: String = _map_service.get_other_country_id(unit.controller_country_id)
	_map_service.set_control_state(unit.id, new_controller, 0.3, 0.62)


func _debug_mutation_allowed() -> bool:
	return GameSessionService.developer_mode or (
		DisplayServer.get_name() == "headless" and OS.has_feature("editor")
	)


func _on_pause_pressed() -> void:
	if _clock != null:
		_clock.set_paused(not _clock.is_paused)


func _on_speed_pressed(multiplier: int) -> void:
	if _clock != null and _clock.set_speed(multiplier):
		_clock.set_paused(false)


func _on_save_pressed() -> void:
	var result: SaveOperationResult = GameSaveService.new().save_manual(_clock, _map_service)
	save_button.text = "已保存" if result.success else "保存失败"
	save_button.tooltip_text = (
		"手动存档已写入" if result.success else "%s：%s" % [result.error_code, result.message]
	)


func _on_clock_changed(_snapshot: Dictionary) -> void:
	_refresh_clock()
	_refresh_player_status()


func _on_pause_changed(_paused: bool) -> void:
	_refresh_clock()


func _on_speed_changed(_speed: int) -> void:
	_refresh_clock()


func _refresh_clock() -> void:
	if _clock == null:
		return
	date_label.text = "%04d年%02d月%02d日 %02d:00" % [
		_clock.year, _clock.month, _clock.day, _clock.hour
	]
	pause_button.text = UiStrings.CLOCK_RESUME if _clock.is_paused else UiStrings.CLOCK_PAUSE
	clock_status_label.text = "%s · %d×" % [
		"已暂停" if _clock.is_paused else "运行中",
		_clock.speed_multiplier,
	]
	var speeds: Array[int] = [1, 2, 4, 8]
	var buttons: Array[Button] = [
		speed_1_button, speed_2_button, speed_4_button, speed_8_button
	]
	for index: int in range(buttons.size()):
		buttons[index].button_pressed = speeds[index] == _clock.speed_multiplier


func _refresh_war_status() -> void:
	if _map_service == null:
		return
	var state: Dictionary = _map_service.get_war_state()
	if not _map_service.is_war_active():
		war_status_label.text = UiStrings.MAP_PEACE_STATUS
		war_status_label.tooltip_text = "和平期间不会产生军事控制压力。"
		return
	var participants: Array[String] = DataRecordUtils.to_string_array(
		state.get("participant_country_ids", [])
	)
	var names: Array[String] = []
	for country_id: String in participants:
		var country: CountryData = _map_service.data_set.countries.get(country_id) as CountryData
		if country != null:
			names.append(country.name)
	war_status_label.text = "战争进行中 · %s" % " / ".join(names)
	war_status_label.tooltip_text = str(state.get("stalemate_reason", "等待军事决策。"))


func _on_back_pressed() -> void:
	var change_error: Error = get_tree().change_scene_to_file(
		"res://scenes/menu/main_menu.tscn"
	)
	if change_error != OK:
		LogService.error("StrategicMapView", "无法返回主菜单：%s" % error_string(change_error))


func _on_character_pressed() -> void:
	if character_panel.visible:
		_close_primary_panel()
	else:
		character_panel.refresh_view()
		_open_primary_panel(character_panel)


func _on_character_panel_close_requested() -> void:
	_close_primary_panel()


func _on_action_pressed() -> void:
	if action_panel.visible:
		_close_primary_panel()
	else:
		_open_primary_panel(action_panel)


func _on_action_panel_close_requested() -> void:
	_close_primary_panel()


func _on_action_state_changed() -> void:
	_refresh_player_status()
	if social_panel.visible:
		social_panel.refresh_view()


func _on_social_pressed() -> void:
	if social_panel.visible:
		_close_primary_panel()
	else:
		_open_primary_panel(social_panel)
		social_panel.refresh_view()


func _on_social_panel_close_requested() -> void:
	_close_primary_panel()


func _on_world_activity_pressed() -> void:
	if world_activity_panel.visible:
		_close_primary_panel()
	else:
		world_activity_panel.refresh_view()
		_open_primary_panel(world_activity_panel)


func _on_world_activity_panel_close_requested() -> void:
	_close_primary_panel()


func _on_developer_pressed() -> void:
	if developer_panel.visible:
		_close_primary_panel(false)
	else:
		_open_tool_panel(developer_panel)


func _on_developer_panel_close_requested() -> void:
	_close_primary_panel()


func _on_developer_mode_changed(_enabled: bool) -> void:
	_apply_developer_visibility()
	_refresh_more_menu()
	social_panel.refresh_developer_mode()
	if not GameSessionService.developer_mode and developer_panel.visible:
		_close_primary_panel(false)


func _apply_developer_visibility() -> void:
	var visible_to_developer: bool = GameSessionService.developer_mode
	pressure_button.visible = visible_to_developer
	transfer_button.visible = visible_to_developer


func _open_primary_panel(panel: Control) -> void:
	if _drawer_tween != null:
		_drawer_tween.kill()
	_hide_drawers_except(panel)
	developer_panel.visible = false
	_active_drawer = panel
	modal_layer.visible = true
	panel.visible = true
	panel.position.x = -panel.size.x - 16.0
	_drawer_tween = create_tween()
	_drawer_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drawer_tween.tween_property(
		panel, "position:x", DRAWER_OPEN_X, DRAWER_ANIMATION_SECONDS
	)
	panel.grab_focus()


func _open_tool_panel(panel: Control) -> void:
	if _drawer_tween != null:
		_drawer_tween.kill()
	_hide_drawers_except(null)
	_active_drawer = null
	developer_panel.visible = panel == developer_panel
	modal_layer.visible = true
	panel.grab_focus()


func _close_primary_panel(animated: bool = true) -> void:
	developer_panel.visible = false
	if _drawer_tween != null:
		_drawer_tween.kill()
	if animated and _active_drawer != null and _active_drawer.visible:
		var closing_panel: Control = _active_drawer
		_drawer_tween = create_tween()
		_drawer_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_drawer_tween.tween_property(
			closing_panel,
			"position:x",
			-closing_panel.size.x - 16.0,
			DRAWER_ANIMATION_SECONDS
		)
		_drawer_tween.finished.connect(_finish_drawer_close.bind(closing_panel))
		return
	_hide_drawers_except(null)
	_active_drawer = null
	modal_layer.visible = false


func _finish_drawer_close(panel: Control) -> void:
	if _active_drawer != panel:
		return
	panel.visible = false
	panel.position.x = DRAWER_OPEN_X
	_active_drawer = null
	modal_layer.visible = false


func _hide_drawers_except(panel: Control) -> void:
	for drawer: Control in [
		character_panel, action_panel, social_panel, world_activity_panel,
	]:
		drawer.visible = drawer == panel
		if drawer != panel:
			drawer.position.x = DRAWER_OPEN_X


func _on_modal_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
		_close_primary_panel()
		get_viewport().set_input_as_handled()


func _on_more_item_pressed(item_id: int) -> void:
	match item_id:
		1:
			_on_back_pressed()
		2:
			if GameSessionService.developer_mode:
				_on_developer_pressed()


func _refresh_more_menu() -> void:
	var popup: PopupMenu = more_button.get_popup()
	popup.clear()
	popup.add_item("返回主菜单", 1)
	if GameSessionService.developer_mode:
		popup.add_separator()
		popup.add_item("开发者工具", 2)


func _on_social_action_requested(action_id: String, requested_target_id: String) -> void:
	_open_primary_panel(action_panel)
	action_panel.prefill_action(action_id, requested_target_id)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal_layer.visible:
			_close_primary_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_pause") and not _text_input_has_focus():
		_on_pause_pressed()
		get_viewport().set_input_as_handled()


func _text_input_has_focus() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _refresh_player_status() -> void:
	if not GameSessionService.has_player():
		player_summary_label.text = "尚未创建玩家人物"
		action_status_label.text = "当前行动：无"
		return
	var player: CharacterData = GameSessionService.player_character
	var role: String = player.public_position if not player.public_position.is_empty() else player.occupation
	player_summary_label.text = "%s · %s · 财富 %d" % [
		player.name,
		role,
		int(player.current_status.get("wealth", 0)),
	]
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null or action.is_terminal():
		action_status_label.text = "当前行动：无"
		return
	var definition: ActionDefinitionData = (
		_map_service.data_set.actions.get(action.definition_id) as ActionDefinitionData
		if _map_service != null
		else null
	)
	var action_name: String = definition.name if definition != null else "长期行动"
	action_status_label.text = "当前行动：%s · %.0f%%" % [
		action_name,
		action.get_progress_ratio() * 100.0,
	]


func _show_world_error(message: String) -> void:
	selection_title.text = UiStrings.MAP_LOAD_ERROR
	details_label.text = message
	pressure_button.disabled = true
	transfer_button.disabled = true


func _stage_text(stage: String) -> String:
	if not _map_service.is_war_active():
		var peace_labels: Dictionary = {
			MapControlService.STAGE_STABLE: UiStrings.MAP_PEACE_STAGE_STABLE,
			MapControlService.STAGE_WEAKENING: UiStrings.MAP_PEACE_STAGE_WEAKENING,
			MapControlService.STAGE_CONTESTED: UiStrings.MAP_PEACE_STAGE_CONTESTED,
			MapControlService.STAGE_ENEMY_OCCUPATION: UiStrings.MAP_PEACE_STAGE_OCCUPIED,
			MapControlService.STAGE_CONSOLIDATING: UiStrings.MAP_PEACE_STAGE_CONSOLIDATING,
		}
		return str(peace_labels.get(stage, stage))
	var labels: Dictionary = {
		MapControlService.STAGE_STABLE: UiStrings.MAP_STAGE_STABLE,
		MapControlService.STAGE_WEAKENING: UiStrings.MAP_STAGE_WEAKENING,
		MapControlService.STAGE_CONTESTED: UiStrings.MAP_STAGE_CONTESTED,
		MapControlService.STAGE_ENEMY_OCCUPATION: UiStrings.MAP_STAGE_OCCUPIED,
		MapControlService.STAGE_CONSOLIDATING: UiStrings.MAP_STAGE_CONSOLIDATING,
	}
	return str(labels.get(stage, stage))


func _format_social_influence(influence: Dictionary) -> String:
	var parts: Array[String] = []
	var ids: Array[String] = []
	for raw_id: Variant in influence:
		ids.append(str(raw_id))
	ids.sort()
	for country_id: String in ids:
		if _map_service.data_set.countries.has(country_id):
			var country: CountryData = _map_service.data_set.countries[country_id] as CountryData
			parts.append("%s %.0f%%" % [country.name, float(influence[country_id]) * 100.0])
	return " / ".join(parts)


static func _format_integer(value: int) -> String:
	var digits: String = str(value)
	var output: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			output += ","
		output += digits[index]
	return output


static func _infrastructure_state_text(state: String) -> String:
	return (
		UiStrings.MAP_RAIL_OPERATIONAL
		if state == "operational"
		else UiStrings.MAP_RAIL_DISRUPTED
	)
