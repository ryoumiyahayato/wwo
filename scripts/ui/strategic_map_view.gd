extends Control
## Binds the persistent authoritative world session to presentation controls.

const UiStrings = preload("res://scripts/ui/ui_strings.gd")

@onready var world_controller: MapWorldController = %MapWorldController
@onready var clock_runner: SimulationRunner = %SimulationRunner
@onready var map_canvas: StrategicMapCanvas = %MapCanvas
@onready var title_label: Label = %TitleLabel
@onready var date_label: Label = %DateLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_1_button: Button = %Speed1Button
@onready var speed_2_button: Button = %Speed2Button
@onready var speed_4_button: Button = %Speed4Button
@onready var speed_8_button: Button = %Speed8Button
@onready var save_button: Button = %SaveButton
@onready var back_button: Button = %BackButton
@onready var character_button: Button = %CharacterButton
@onready var action_button: Button = %ActionButton
@onready var action_panel: ActionPanel = %ActionPanel
@onready var social_button: Button = %SocialButton
@onready var social_panel: SocialSystemPanel = %SocialSystemPanel
@onready var developer_button: Button = %DeveloperButton
@onready var developer_panel: DeveloperPanel = %DeveloperPanel
@onready var selection_title: Label = %SelectionTitle
@onready var details_label: RichTextLabel = %DetailsLabel
@onready var pressure_button: Button = %PressureButton
@onready var transfer_button: Button = %TransferButton
@onready var zoom_label: Label = %ZoomLabel

var _clock: SimulationClock
var _map_service: MapControlService
var _selected_unit_id: String = ""
var _autosave: AutosaveCoordinator


func _ready() -> void:
	title_label.text = UiStrings.MAP_TITLE
	back_button.text = UiStrings.MAP_BACK
	character_button.text = UiStrings.MAP_CHARACTER
	action_button.text = UiStrings.MAP_ACTION
	social_button.text = UiStrings.MAP_SOCIETY
	save_button.text = UiStrings.MAP_SAVE
	pause_button.pressed.connect(_on_pause_pressed)
	speed_1_button.pressed.connect(_on_speed_pressed.bind(1))
	speed_2_button.pressed.connect(_on_speed_pressed.bind(2))
	speed_4_button.pressed.connect(_on_speed_pressed.bind(4))
	speed_8_button.pressed.connect(_on_speed_pressed.bind(8))
	save_button.pressed.connect(_on_save_pressed)
	back_button.pressed.connect(_on_back_pressed)
	character_button.pressed.connect(_on_character_pressed)
	action_button.pressed.connect(_on_action_pressed)
	social_button.pressed.connect(_on_social_pressed)
	developer_button.pressed.connect(_on_developer_pressed)
	character_button.disabled = not GameSessionService.has_player()
	action_button.disabled = not GameSessionService.has_player()
	social_button.disabled = not GameSessionService.has_player()
	action_panel.close_requested.connect(_on_action_panel_close_requested)
	social_panel.close_requested.connect(_on_social_panel_close_requested)
	developer_panel.close_requested.connect(_on_developer_panel_close_requested)
	developer_panel.developer_mode_changed.connect(_on_developer_mode_changed)
	social_panel.society_changed.connect(action_panel.refresh_permissions)
	pressure_button.pressed.connect(_on_pressure_pressed)
	transfer_button.pressed.connect(_on_transfer_pressed)
	map_canvas.unit_selected.connect(_on_unit_selected)

	_bind_persistent_clock()
	if _clock == null:
		_show_world_error("权威游戏时钟未初始化。")
		return
	_bind_persistent_map()
	if _map_service == null:
		_show_world_error(world_controller.initialization_error)
		return

	_map_service.control_unit_changed.connect(_on_control_unit_changed)
	_restore_pending_save()
	_initialize_society()
	_initialize_autosave()
	GameSessionService.set_world_services(_clock, _map_service, _autosave)

	developer_panel.setup(_clock, _map_service, _autosave)
	map_canvas.setup(_map_service)
	map_canvas.select_unit("control:r3_c4")
	action_panel.setup(_clock, _map_service)
	action_panel.set_target(_selected_unit_id)
	if GameSessionService.society_service != null:
		social_panel.setup(_clock, GameSessionService.society_service)
	zoom_label.text = UiStrings.MAP_HELP
	_apply_developer_visibility()


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


func _restore_pending_save() -> void:
	if GameSessionService.pending_load_path.is_empty():
		return
	var pending_path: String = GameSessionService.pending_load_path
	GameSessionService.pending_load_path = ""
	var save_service := GameSaveService.new()
	var loaded: SaveOperationResult = save_service.load_from_path(pending_path)
	if loaded.success:
		loaded = save_service.restore_snapshot(loaded.snapshot, _clock, _map_service)
	if not loaded.success:
		LogService.error("StrategicMapView", "加载存档失败：%s" % loaded.message)


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
	character_button.disabled = false
	action_button.disabled = false
	social_button.disabled = false


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
	details_label.text = """控制单元  %s
网格坐标  (%d, %d)

法理归属  %s
军事控制  %s
控制阶段  %s
控制强度  %.0f%%
争夺程度  %.0f%%
社会支持  %.0f%%

地区人口  %s
地区控制  %s
平均争夺  %.0f%%
铁路状态  %s（%d 条地区连接）
社会影响  %s""" % [
		unit.id,
		unit.grid_x,
		unit.grid_y,
		legal_country.name,
		controller_country.name,
		_stage_text(_map_service.get_control_stage(unit.id)),
		unit.control_strength * 100.0,
		unit.contested_level * 100.0,
		unit.social_support * 100.0,
		_format_integer(int(summary["population_total"])),
		" / ".join(control_lines),
		float(summary["average_contested"]) * 100.0,
		_infrastructure_state_text(unit.infrastructure_state),
		int(summary["railroad_connections"]),
		_format_social_influence(summary["social_influence"] as Dictionary),
	]
	pressure_button.disabled = false
	transfer_button.disabled = false
	_apply_developer_visibility()


func _on_pressure_pressed() -> void:
	if not GameSessionService.developer_mode:
		return
	var unit: ControlUnitData = _map_service.get_unit(_selected_unit_id)
	if unit == null:
		return
	var attacker: String = _map_service.get_other_country_id(unit.controller_country_id)
	_map_service.apply_control_pressure(unit.id, attacker)


func _on_transfer_pressed() -> void:
	if not GameSessionService.developer_mode:
		return
	var unit: ControlUnitData = _map_service.get_unit(_selected_unit_id)
	if unit == null:
		return
	var new_controller: String = _map_service.get_other_country_id(unit.controller_country_id)
	_map_service.set_control_state(unit.id, new_controller, 0.3, 0.62)


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
	var speeds: Array[int] = [1, 2, 4, 8]
	var buttons: Array[Button] = [
		speed_1_button, speed_2_button, speed_4_button, speed_8_button
	]
	for index: int in range(buttons.size()):
		buttons[index].button_pressed = speeds[index] == _clock.speed_multiplier


func _on_back_pressed() -> void:
	var change_error: Error = get_tree().change_scene_to_file(
		"res://scenes/menu/main_menu.tscn"
	)
	if change_error != OK:
		LogService.error("StrategicMapView", "无法返回主菜单：%s" % error_string(change_error))


func _on_character_pressed() -> void:
	var change_error: Error = get_tree().change_scene_to_file(
		"res://scenes/character/character_profile_view.tscn"
	)
	if change_error != OK:
		LogService.error("StrategicMapView", "无法打开人物信息：%s" % error_string(change_error))


func _on_action_pressed() -> void:
	action_panel.visible = not action_panel.visible
	social_panel.visible = false
	developer_panel.visible = false


func _on_action_panel_close_requested() -> void:
	action_panel.visible = false


func _on_social_pressed() -> void:
	social_panel.visible = not social_panel.visible
	action_panel.visible = false
	developer_panel.visible = false
	social_panel.refresh_developer_mode()


func _on_social_panel_close_requested() -> void:
	social_panel.visible = false


func _on_developer_pressed() -> void:
	developer_panel.visible = not developer_panel.visible
	action_panel.visible = false
	social_panel.visible = false


func _on_developer_panel_close_requested() -> void:
	developer_panel.visible = false


func _on_developer_mode_changed(_enabled: bool) -> void:
	_apply_developer_visibility()
	social_panel.refresh_developer_mode()


func _apply_developer_visibility() -> void:
	var visible_to_developer: bool = GameSessionService.developer_mode
	pressure_button.visible = visible_to_developer
	transfer_button.visible = visible_to_developer


func _show_world_error(message: String) -> void:
	selection_title.text = UiStrings.MAP_LOAD_ERROR
	details_label.text = message
	pressure_button.disabled = true
	transfer_button.disabled = true


func _stage_text(stage: String) -> String:
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
