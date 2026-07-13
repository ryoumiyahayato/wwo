extends SceneTree
## Current default-branch player journey. Uses formal UI controls and legal
## succession preconditions; no developer mutation controls are used.

const MANUAL_PATH: String = GameSaveService.MANUAL_PATH

var _checks: int = 0
var _failures: int = 0
var _preserved_files: Dictionary = {}
var _view: Control
var _clock: SimulationClock
var _map: MapControlService
var _society: SocietySimulationService
var _action_panel: ActionPanel


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LogService.set_minimum_level(LogService.Level.ERROR)
	_preserve_manual_files()
	GameSessionService.clear()
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可创建当前玩家旅程人物")
	if player == null:
		_finish()
		return
	GameSessionService.set_player(player)

	var packed: Resource = load("res://scenes/map/strategic_map_view.tscn")
	_view = (
		(packed as PackedScene).instantiate() as Control
		if packed is PackedScene
		else null
	)
	_expect(_view != null, "战略地图可实例化")
	if _view == null:
		_finish()
		return
	get_root().content_scale_size = Vector2i(1280, 720)
	get_root().add_child(_view)
	current_scene = _view
	await process_frame

	_clock = GameSessionService.world_clock
	_map = GameSessionService.world_map_service
	_society = GameSessionService.society_service
	_action_panel = _view.find_child("ActionPanel", true, false) as ActionPanel
	_expect(
		_clock != null
		and _map != null
		and _society != null
		and _action_panel != null,
		"当前旅程建立权威世界与正式行动面板"
	)
	if _clock == null or _map == null or _society == null or _action_panel == null:
		_finish()
		return

	var government_id: String = (
		"organization:loran_government"
		if player.country_id == "country:loran_federation"
		else "organization:vesta_government"
	)
	var government: OrganizationData = _society.organizations.get_organization(
		government_id
	)
	_expect(government != null and not government.leader_character_id.is_empty(), "本国政府具有真实领导人物")
	if government == null or government.leader_character_id.is_empty():
		_finish()
		return
	var leader_id: String = government.leader_character_id

	await _open_action_panel()
	_expect(_begin_button_is_visible_and_fixed(), "1280×720 下开始行动按钮可见且位于滚动区外")

	var relation_started: bool = _start_action_via_ui(
		"action:build_relationship", leader_id, 20
	)
	_expect(relation_started, "通过正式 UI 开始建立关系行动")
	if not relation_started:
		_finish()
		return
	_expect(_complete_current_action(), "建立关系行动可由权威时间完成")
	_expect(
		_society.relationships.get_between(player.id, leader_id) != null,
		"完成行动后形成真实关系记录"
	)

	var join_started: bool = _start_action_via_ui(
		"action:join_organization", government_id, 20
	)
	_expect(join_started, "通过正式 UI 开始加入组织行动")
	if not join_started:
		_finish()
		return
	_expect(_complete_current_action(), "加入组织行动可由权威时间完成")
	_expect(
		government.member_ids.has(player.id),
		"完成行动后玩家成为本国政府成员"
	)

	var old_position_id: String = _society.organizations.get_position_id(
		player.id, government_id
	)
	var position_started: bool = _start_action_via_ui(
		"action:seek_position", government_id, 20
	)
	_expect(position_started, "通过正式 UI 开始争取职位行动")
	if not position_started:
		_finish()
		return
	_expect(_complete_current_action(), "争取职位行动可由权威时间完成")
	var new_position_id: String = _society.organizations.get_position_id(
		player.id, government_id
	)
	_expect(
		not new_position_id.is_empty() and new_position_id != old_position_id,
		"完成行动后职位按空缺规则晋升"
	)

	var policy_target_id: String = _first_policy_target(player.country_id)
	_expect(not policy_target_id.is_empty(), "存在合法本国政策目标")
	if policy_target_id.is_empty():
		_finish()
		return
	var policy_unit: ControlUnitData = _map.get_unit(policy_target_id)
	var policy_region: RegionData = _map.data_set.regions[
		policy_unit.region_id
	] as RegionData
	var influence_before: Dictionary = policy_region.social_influence.duplicate(true)
	var policy_started: bool = _start_action_via_ui(
		"action:promote_policy", policy_target_id, 20
	)
	_expect(policy_started, "通过正式 UI 开始地区政策行动")
	if not policy_started:
		_finish()
		return
	_expect(_complete_current_action(), "地区政策行动可由权威时间完成")
	_expect(
		policy_region.social_influence != influence_before,
		"政策行动完成后修改权威地区社会影响"
	)

	player.age = int(_society.rules.lifecycle_rules["retirement_age"])
	await _open_social_panel()
	var social_panel: SocialSystemPanel = _view.find_child(
		"SocialPanel", true, false
	) as SocialSystemPanel
	_expect(social_panel != null and social_panel.visible, "正式社会系统面板可打开")
	if social_panel == null:
		_finish()
		return
	var reason_option: OptionButton = social_panel.find_child(
		"ExitReasonOption", true, false
	) as OptionButton
	_expect(
		_select_option_by_metadata(reason_option, "retirement"),
		"达到退休年龄后正式退出原因出现退休"
	)
	var prepare_button: Button = social_panel.find_child(
		"PrepareSuccessionButton", true, false
	) as Button
	_expect(prepare_button != null and not prepare_button.disabled, "合法退休可准备继承")
	if prepare_button == null or prepare_button.disabled:
		_finish()
		return
	prepare_button.pressed.emit()
	await process_frame
	var successor_option: OptionButton = social_panel.find_child(
		"SuccessionOption", true, false
	) as OptionButton
	_expect(successor_option != null and successor_option.item_count > 0, "真实关系或共同组织产生继承候选")
	if successor_option == null or successor_option.item_count == 0:
		_finish()
		return
	var old_player_id: String = player.id
	var expected_successor_id: String = str(
		successor_option.get_item_metadata(successor_option.selected)
	)
	var confirm_button: Button = social_panel.find_child(
		"ConfirmSuccessionButton", true, false
	) as Button
	_expect(confirm_button != null and not confirm_button.disabled, "继承确认按钮可用")
	if confirm_button == null or confirm_button.disabled:
		_finish()
		return
	confirm_button.pressed.emit()
	await process_frame
	_expect(
		GameSessionService.player_character != null
		and GameSessionService.player_character.id == expected_successor_id
		and GameSessionService.player_character.id != old_player_id,
		"合法退休后玩家切换到所选继承者"
	)
	_expect(
		_society.roster.get_exited(old_player_id) != null,
		"旧玩家保留在退出历史中"
	)

	var save_button: Button = _view.find_child("SaveButton", true, false) as Button
	_expect(save_button != null and save_button.visible, "正式保存按钮可见")
	if save_button == null:
		_finish()
		return
	var saved_player_id: String = GameSessionService.player_character.id
	var saved_hour: int = _clock.total_hours
	save_button.pressed.emit()
	await process_frame
	var save_service := GameSaveService.new()
	var loaded: SaveOperationResult = save_service.load_from_path(MANUAL_PATH)
	_expect(loaded.success, "正式保存按钮写入可读取手动档")
	if loaded.success:
		var restored: SaveOperationResult = save_service.restore_snapshot(
			loaded.snapshot, _clock, _map
		)
		_expect(restored.success, "手动档可恢复到权威会话")
		_expect(
			GameSessionService.player_character.id == saved_player_id
			and _clock.total_hours == saved_hour,
			"恢复后继承者和权威时间保持一致"
		)

	_finish()


func _open_action_panel() -> void:
	var button: Button = _view.find_child("ActionButton", true, false) as Button
	_expect(button != null and button.visible, "长期行动正式入口可见")
	if button != null:
		button.pressed.emit()
		await process_frame
	_expect(_action_panel.visible, "长期行动面板已打开")


func _open_social_panel() -> void:
	var button: Button = _view.find_child("SocialButton", true, false) as Button
	_expect(button != null and button.visible, "社会系统正式入口可见")
	if button != null:
		button.pressed.emit()
		await process_frame


func _begin_button_is_visible_and_fixed() -> bool:
	var button: Button = _action_panel.get_node_or_null(
		"Margin/Root/BeginButton"
	) as Button
	if button == null or not button.is_visible_in_tree():
		return false
	var ancestor: Node = button.get_parent()
	while ancestor != null and ancestor != _action_panel:
		if ancestor is ScrollContainer:
			return false
		ancestor = ancestor.get_parent()
	var rect: Rect2 = button.get_global_rect()
	return (
		rect.size.x > 0.0
		and rect.size.y > 0.0
		and rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= 1280.0
		and rect.end.y <= 720.0
	)


func _start_action_via_ui(
	action_id: String,
	target_id: String,
	extra_funding: int
) -> bool:
	var action_option: OptionButton = _action_panel.find_child(
		"ActionOption", true, false
	) as OptionButton
	if not _select_option_by_metadata(action_option, action_id):
		return false
	await process_frame
	if action_id == "action:promote_policy" or action_id == "action:support_control":
		_action_panel.set_target(target_id)
		await process_frame
	var target_option: OptionButton = _action_panel.find_child(
		"TargetOption", true, false
	) as OptionButton
	if not target_id.is_empty() and not _select_option_by_metadata(
		target_option, target_id
	):
		return false
	var investment: SpinBox = _action_panel.find_child(
		"InvestmentSpin", true, false
	) as SpinBox
	if investment != null:
		investment.value = minf(
			float(extra_funding), investment.max_value
		)
		investment.value_changed.emit(investment.value)
	var begin_button: Button = _action_panel.get_node_or_null(
		"Margin/Root/BeginButton"
	) as Button
	if begin_button == null or begin_button.disabled or not begin_button.is_visible_in_tree():
		return false
	begin_button.pressed.emit()
	return (
		GameSessionService.current_action != null
		and GameSessionService.current_action.definition_id == action_id
	)


func _complete_current_action() -> bool:
	var guard: int = 0
	while (
		GameSessionService.current_action != null
		and not GameSessionService.current_action.is_terminal()
		and guard < 400
	):
		_clock.advance_hours(24)
		guard += 1
	return (
		GameSessionService.current_action != null
		and GameSessionService.current_action.status == ActionInstanceData.STATUS_COMPLETED
		and GameSessionService.current_action.domain_effect_applied
	)


func _first_policy_target(country_id: String) -> String:
	for unit_id: String in _map.get_sorted_unit_ids():
		var unit: ControlUnitData = _map.get_unit(unit_id)
		var region: RegionData = _map.data_set.regions[unit.region_id] as RegionData
		if (
			unit.controller_country_id == country_id
			and region.de_jure_country_id == country_id
		):
			return unit_id
	return ""


func _select_option_by_metadata(
	option: OptionButton, metadata_value: String
) -> bool:
	if option == null:
		return false
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata_value:
			option.select(index)
			option.item_selected.emit(index)
			return true
	return false


func _make_test_player() -> CharacterData:
	var world: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	if not world.is_success() or not config.is_valid():
		return null
	var generator := CharacterGenerator.new(
		world.data_set,
		config,
		DeterministicRandomService.new(19000101),
		StableIdService.new()
	)
	var result: CharacterGenerationResult = generator.generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	if not result.is_success():
		return null
	var player: CharacterData = result.character
	for raw_skill: Variant in player.skills:
		player.skills[raw_skill] = 100
	player.current_status["wealth"] = 1000
	player.current_status["intelligence_points"] = 100
	player.current_status["health"] = 100
	player.current_status["fatigue"] = 0
	player.current_status["stress"] = 0
	player.current_status["detained"] = false
	return player


func _preserve_manual_files() -> void:
	_preserved_files.clear()
	var absolute: String = ProjectSettings.globalize_path(MANUAL_PATH)
	for path: String in [absolute, absolute + ".tmp", absolute + ".bak"]:
		if not FileAccess.file_exists(path):
			_preserved_files[path] = null
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		_preserved_files[path] = (
			PackedByteArray()
			if file == null
			else file.get_buffer(file.get_length())
		)
		if file != null:
			file.close()


func _restore_manual_files() -> void:
	for raw_path: Variant in _preserved_files:
		var path: String = str(raw_path)
		var stored: Variant = _preserved_files[raw_path]
		if stored == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(stored as PackedByteArray)
			file.close()


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		printerr("[FAIL] %s" % description)


func _finish() -> void:
	_restore_manual_files()
	GameSessionService.clear()
	if _failures > 0:
		printerr(
			"CURRENT PLAYER JOURNEY FAILED: %d/%d" % [
				_failures, _checks
			]
		)
		quit(1)
	else:
		print("CURRENT PLAYER JOURNEY PASSED: %d checks" % _checks)
		quit(0)
