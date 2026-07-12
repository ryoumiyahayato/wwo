extends SceneTree
## Player-journey regression: drives public UI controls instead of fabricating completed actions.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_manual_save()
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可创建玩家旅程测试人物")
	if player == null:
		_finish()
		return
	GameSessionService.set_player(player)

	var view: Control = _instantiate_scene("res://scenes/map/strategic_map_view.tscn") as Control
	_expect(view != null, "战略地图场景可实例化")
	if view == null:
		_finish()
		return
	get_root().add_child(view)
	current_scene = view
	await process_frame

	var clock: SimulationClock = GameSessionService.world_clock
	var map_service: MapControlService = GameSessionService.world_map_service
	var society: SocietySimulationService = GameSessionService.society_service
	var action_panel: ActionPanel = view.get_node("ActionPanel") as ActionPanel
	_expect(clock != null and map_service != null and society != null, "公共地图建立权威世界会话")
	_expect((view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SaveButton") as Button).visible, "正式顶栏显示保存游戏入口")
	_expect(not (view.get_node("RootMargin/Layout/Content/SidePanel/SideMargin/SideContent/PressureButton") as Button).visible, "普通模式隐藏地图直接压力入口")
	_expect(action_panel.action_option.item_count == 8, "长期行动面板列出八类行动")
	_expect(action_panel.get_node_or_null("Margin/Root/Scroll/Content/PreparationInput") == null, "正式行动面板不再包含可任意填写的准备值")

	var government_id: String = "organization:loran_government"
	var government: OrganizationData = society.organizations.get_organization(government_id)
	var leader_id: String = government.leader_character_id
	_expect(not leader_id.is_empty(), "本国政府存在真实组织领导")

	_run_action(action_panel, "action:build_relationship", leader_id, clock, 500)
	_run_action(action_panel, "action:build_relationship", leader_id, clock, 500)
	_expect(society.relationships.get_between(player.id, leader_id) != null, "玩家通过两次正式长期行动建立真实关系")

	_run_action(action_panel, "action:join_organization", government_id, clock, 500)
	_expect(government.member_ids.has(player.id), "加入组织行动把玩家写入正式成员索引")
	var entry_position: String = society.organizations.get_position_id(player.id, government_id)
	_expect(not entry_position.is_empty(), "加入组织后获得入口职位")

	_run_action(action_panel, "action:seek_position", government_id, clock, 500)
	var promoted_position: String = society.organizations.get_position_id(player.id, government_id)
	_expect(promoted_position != entry_position, "争取职位行动授予更高空缺职位")
	_expect(society.organizations.has_permission(player.id, government_id, "regional_policy"), "晋升后获得地区政策权限")

	var target_unit_id: String = "control:r3_c4"
	var target_unit: ControlUnitData = map_service.get_unit(target_unit_id)
	var target_region: RegionData = map_service.data_set.regions[target_unit.region_id] as RegionData
	var influence_before: float = float(target_region.social_influence[player.country_id])
	action_panel.set_target(target_unit_id)
	_run_action(action_panel, "action:promote_policy", target_unit_id, clock, 800)
	_expect(float(target_region.social_influence[player.country_id]) > influence_before, "地区政策行动改变权威社会影响")

	_select_action(action_panel, "action:study_skill", "")
	(action_panel.get_node("Margin/Root/Scroll/Content/BeginButton") as Button).pressed.emit()
	var pending_action: ActionInstanceData = GameSessionService.current_action
	clock.advance_hours(1)
	var pending_work: float = pending_action.accumulated_work
	var clock_reference: SimulationClock = clock
	var map_reference: MapControlService = map_service

	(view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/CharacterButton") as Button).pressed.emit()
	await process_frame
	await process_frame
	var profile: Control = current_scene as Control
	_expect(profile != null and profile.name == "CharacterProfileView", "人物信息入口切换到人物页面")
	(profile.get_node("Margin/Root/Bottom/BackButton") as Button).pressed.emit()
	await process_frame
	await process_frame
	view = current_scene as Control
	_expect(GameSessionService.world_clock == clock_reference, "返回地图后复用同一权威时钟")
	_expect(GameSessionService.world_map_service == map_reference, "返回地图后复用同一权威地图")
	_expect(GameSessionService.current_action == pending_action, "返回地图后保留进行中行动")
	clock_reference.advance_hours(1)
	_expect(pending_action.accumulated_work > pending_work, "跨页面返回后行动继续推进")

	var social_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SocialButton") as Button
	social_button.pressed.emit()
	var social_panel: SocialSystemPanel = view.get_node("SocialSystemPanel") as SocialSystemPanel
	(social_panel.get_node("Margin/Root/Scroll/Content/PrepareSuccessionButton") as Button).pressed.emit()
	var succession_option: OptionButton = social_panel.get_node("Margin/Root/Scroll/Content/SuccessionOption") as OptionButton
	var leader_candidate_index: int = _option_index(succession_option, leader_id)
	_expect(leader_candidate_index >= 0, "真实关系与共同组织生成组织领导继承候选")
	if leader_candidate_index >= 0:
		succession_option.select(leader_candidate_index)
	var exit_option: OptionButton = social_panel.get_node("Margin/Root/Scroll/Content/ExitReasonOption") as OptionButton
	var retirement_index: int = _option_index(exit_option, "retirement")
	if retirement_index >= 0:
		exit_option.select(retirement_index)
	(social_panel.get_node("Margin/Root/Scroll/Content/ConfirmSuccessionButton") as Button).pressed.emit()
	_expect(GameSessionService.player_character.id == leader_id, "玩家通过正式社会界面完成退休继承")
	_expect(GameSessionService.world_clock == clock_reference and GameSessionService.world_map_service == map_reference, "继承保持同一权威世界")

	var saved_player_id: String = GameSessionService.player_character.id
	var saved_hour: int = clock_reference.total_hours
	var saved_influence: float = float(target_region.social_influence[player.country_id])
	var save_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SaveButton") as Button
	save_button.pressed.emit()
	_expect(FileAccess.file_exists(GameSaveService.MANUAL_PATH), "普通保存按钮写入手动存档")
	_expect(save_button.text == "已保存", "普通保存按钮提供成功反馈")

	(view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/BackButton") as Button).pressed.emit()
	await process_frame
	await process_frame
	var menu: Control = current_scene as Control
	var load_button: Button = menu.get_node("SafeMargin/Center/Card/CardMargin/Content/LoadGameButton") as Button
	_expect(not load_button.disabled, "主菜单发现手动存档并启用加载")
	load_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	view = current_scene as Control
	_expect(view != null and view.name == "StrategicMapView", "加载游戏返回战略地图")
	_expect(GameSessionService.player_character.id == saved_player_id, "加载恢复继承后的玩家人物")
	_expect(GameSessionService.world_clock.total_hours == saved_hour, "加载恢复权威时间")
	var loaded_unit: ControlUnitData = GameSessionService.world_map_service.get_unit(target_unit_id)
	var loaded_region: RegionData = GameSessionService.world_map_service.data_set.regions[loaded_unit.region_id] as RegionData
	_expect(is_equal_approx(float(loaded_region.social_influence[player.country_id]), saved_influence), "加载恢复地区社会影响")

	_cleanup_manual_save()
	GameSessionService.clear()
	_finish()


func _run_action(
	panel: ActionPanel,
	definition_id: String,
	target_id: String,
	clock: SimulationClock,
	hours: int
) -> void:
	_select_action(panel, definition_id, target_id)
	var begin_button: Button = panel.get_node("Margin/Root/Scroll/Content/BeginButton") as Button
	begin_button.pressed.emit()
	var action: ActionInstanceData = GameSessionService.current_action
	_expect(action != null and action.definition_id == definition_id, "通过正式行动面板开始 %s" % definition_id)
	if action == null:
		return
	clock.advance_hours(hours)
	_expect(action.status == ActionInstanceData.STATUS_COMPLETED, "%s 随权威时间完成" % definition_id)
	_expect(action.outcome_code != "failure", "%s 在测试人物条件下成功" % definition_id)


func _select_action(panel: ActionPanel, definition_id: String, target_id: String) -> void:
	var index: int = _option_index(panel.action_option, definition_id)
	_expect(index >= 0, "行动列表包含 %s" % definition_id)
	if index < 0:
		return
	panel.action_option.select(index)
	panel.action_option.item_selected.emit(index)
	if target_id.is_empty():
		return
	var target_index: int = _option_index(panel.target_option, target_id)
	_expect(target_index >= 0, "%s 提供目标 %s" % [definition_id, target_id])
	if target_index >= 0:
		panel.target_option.select(target_index)
		panel.target_option.item_selected.emit(target_index)


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
	for raw_aptitude: Variant in player.hidden_aptitudes:
		player.hidden_aptitudes[raw_aptitude] = 50
	player.current_status["wealth"] = 500
	player.current_status["reputation"] = 50
	player.current_status["intelligence_points"] = 100
	player.current_status["health"] = 90
	player.current_status["fatigue"] = 0
	player.current_status["stress"] = 0
	player.current_status["detained"] = false
	player.current_status["employment_status"] = "employed"
	return player


func _instantiate_scene(path: String) -> Node:
	var resource: Resource = load(path)
	return null if not resource is PackedScene else (resource as PackedScene).instantiate()


static func _option_index(option: OptionButton, metadata: String) -> int:
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1


func _cleanup_manual_save() -> void:
	var absolute: String = ProjectSettings.globalize_path(GameSaveService.MANUAL_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	if FileAccess.file_exists(absolute + ".tmp"):
		DirAccess.remove_absolute(absolute + ".tmp")
	if FileAccess.file_exists(absolute + ".bak"):
		DirAccess.remove_absolute(absolute + ".bak")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
		return
	_failures += 1
	printerr("[FAIL] %s" % description)


func _finish() -> void:
	if _failures > 0:
		printerr("P0-R1 PLAYER JOURNEY FAILED: %d/%d checks failed" % [_failures, _checks])
		quit(1)
		return
	print("P0-R1 PLAYER JOURNEY PASSED: %d checks" % _checks)
	quit(0)
