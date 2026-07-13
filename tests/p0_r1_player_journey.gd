extends SceneTree
## Player-journey regression: drives visible public UI controls instead of fabricating completed actions.

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
	var action_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/ActionButton") as Button
	var save_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SaveButton") as Button
	_expect(clock != null and map_service != null and society != null, "公共地图建立权威世界会话")
	if clock == null or map_service == null or society == null:
		_finish()
		return
	_expect(not (view.get_node("RootMargin/Layout/Content/SidePanel/SideMargin/SideContent/PressureButton") as Button).visible, "普通模式隐藏地图直接压力入口")
	if not _press_button(action_button, "顶栏长期行动入口"):
		_finish()
		return
	_expect(action_panel.visible and action_panel.is_visible_in_tree(), "点击顶栏后长期行动面板真实显示")
	_expect(action_panel.action_option.is_visible_in_tree() and not action_panel.action_option.disabled, "行动类型选择控件可见且可用")
	_expect(action_panel.action_option.item_count == 8, "长期行动面板列出八类行动")
	_expect(action_panel.get_node_or_null("Margin/Root/Scroll/Content/PreparationInput") == null, "正式行动面板不再包含可任意填写的准备值")
	if not action_panel.visible or not action_panel.is_visible_in_tree():
		_finish()
		return

	var government_id: String = "organization:loran_government"
	var government: OrganizationData = society.organizations.get_organization(government_id)
	_expect(government != null, "本国政府组织存在")
	if government == null:
		_finish()
		return
	var leader_id: String = government.leader_character_id
	_expect(not leader_id.is_empty(), "本国政府存在真实组织领导")
	if leader_id.is_empty():
		_finish()
		return

	if not _run_action(action_panel, "action:build_relationship", leader_id, clock, 500):
		_finish()
		return
	if not _run_action(action_panel, "action:build_relationship", leader_id, clock, 500):
		_finish()
		return
	_expect(society.relationships.get_between(player.id, leader_id) != null, "玩家通过两次正式长期行动建立真实关系")

	if not _run_action(action_panel, "action:join_organization", government_id, clock, 500):
		_finish()
		return
	_expect(government.member_ids.has(player.id), "加入组织行动把玩家写入正式成员索引")
	var entry_position: String = society.organizations.get_position_id(player.id, government_id)
	_expect(not entry_position.is_empty(), "加入组织后获得入口职位")

	if not _run_action(action_panel, "action:seek_position", government_id, clock, 500):
		_finish()
		return
	var promoted_position: String = society.organizations.get_position_id(player.id, government_id)
	_expect(promoted_position != entry_position, "争取职位行动授予更高空缺职位")
	_expect(society.organizations.has_permission(player.id, government_id, "regional_policy"), "晋升后获得地区政策权限")

	var target_unit_id: String = "control:r3_c4"
	var target_unit: ControlUnitData = map_service.get_unit(target_unit_id)
	_expect(target_unit != null, "地区政策目标控制单元存在")
	if target_unit == null:
		_finish()
		return
	var target_region: RegionData = map_service.data_set.regions[target_unit.region_id] as RegionData
	var influence_before: float = float(target_region.social_influence[player.country_id])
	if not _run_action(action_panel, "action:promote_policy", target_unit_id, clock, 800):
		_finish()
		return
	_expect(float(target_region.social_influence[player.country_id]) > influence_before, "地区政策行动改变权威社会影响")

	if not _select_action(action_panel, "action:study_skill", ""):
		_finish()
		return
	var begin_button: Button = action_panel.get_node("Margin/Root/Scroll/Content/BeginButton") as Button
	if not _press_button(begin_button, "学习行动开始按钮"):
		_finish()
		return
	var pending_action: ActionInstanceData = GameSessionService.current_action
	_expect(pending_action != null and pending_action.definition_id == "action:study_skill", "通过可用按钮开始跨页面行动")
	if pending_action == null or pending_action.definition_id != "action:study_skill":
		_finish()
		return
	clock.advance_hours(1)
	var pending_work: float = pending_action.accumulated_work
	var clock_reference: SimulationClock = clock
	var map_reference: MapControlService = map_service

	var character_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/CharacterButton") as Button
	if not _press_button(character_button, "人物信息入口"):
		_finish()
		return
	await process_frame
	await process_frame
	var profile: Control = current_scene as Control
	_expect(profile != null and profile.name == "CharacterProfileView", "人物信息入口切换到人物页面")
	if profile == null or profile.name != "CharacterProfileView":
		_finish()
		return
	var profile_back: Button = profile.get_node("Margin/Root/Bottom/BackButton") as Button
	if not _press_button(profile_back, "人物页面返回按钮"):
		_finish()
		return
	await process_frame
	await process_frame
	view = current_scene as Control
	_expect(view != null and view.name == "StrategicMapView", "人物页面返回战略地图")
	if view == null or view.name != "StrategicMapView":
		_finish()
		return
	_expect(GameSessionService.world_clock == clock_reference, "返回地图后复用同一权威时钟")
	_expect(GameSessionService.world_map_service == map_reference, "返回地图后复用同一权威地图")
	_expect(GameSessionService.current_action == pending_action, "返回地图后保留进行中行动")
	clock_reference.advance_hours(1)
	_expect(pending_action.accumulated_work > pending_work, "跨页面返回后行动继续推进")

	var social_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SocialButton") as Button
	if not _press_button(social_button, "社会系统入口"):
		_finish()
		return
	var social_panel: SocialSystemPanel = view.get_node("SocialSystemPanel") as SocialSystemPanel
	_expect(social_panel.visible and social_panel.is_visible_in_tree(), "点击顶栏后社会系统面板真实显示")
	if not social_panel.visible or not social_panel.is_visible_in_tree():
		_finish()
		return
	var prepare_succession: Button = social_panel.get_node("Margin/Root/Scroll/Content/PrepareSuccessionButton") as Button
	if not _press_button(prepare_succession, "继承候选入口"):
		_finish()
		return
	var succession_option: OptionButton = social_panel.get_node("Margin/Root/Scroll/Content/SuccessionOption") as OptionButton
	if not _select_option(succession_option, leader_id, "继承者选择"):
		_finish()
		return
	var exit_option: OptionButton = social_panel.get_node("Margin/Root/Scroll/Content/ExitReasonOption") as OptionButton
	if not _select_option(exit_option, "retirement", "退休原因选择"):
		_finish()
		return
	var confirm_succession: Button = social_panel.get_node("Margin/Root/Scroll/Content/ConfirmSuccessionButton") as Button
	if not _press_button(confirm_succession, "退休继承确认按钮"):
		_finish()
		return
	_expect(GameSessionService.player_character.id == leader_id, "玩家通过正式社会界面完成退休继承")
	_expect(GameSessionService.world_clock == clock_reference and GameSessionService.world_map_service == map_reference, "继承保持同一权威世界")

	var saved_player_id: String = GameSessionService.player_character.id
	var saved_hour: int = clock_reference.total_hours
	var saved_influence: float = float(target_region.social_influence[player.country_id])
	save_button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SaveButton") as Button
	if not _press_button(save_button, "保存游戏入口"):
		_finish()
		return
	_expect(FileAccess.file_exists(GameSaveService.MANUAL_PATH), "普通保存按钮写入手动存档")
	_expect(save_button.text == "已保存", "普通保存按钮提供成功反馈")

	var back_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/BackButton") as Button
	if not _press_button(back_button, "返回主菜单入口"):
		_finish()
		return
	await process_frame
	await process_frame
	var menu: Control = current_scene as Control
	_expect(menu != null and menu.name == "MainMenu", "返回主菜单入口切换到主菜单")
	if menu == null or menu.name != "MainMenu":
		_finish()
		return
	var load_button: Button = menu.get_node("SafeMargin/Center/Card/CardMargin/Content/LoadGameButton") as Button
	if not _press_button(load_button, "加载游戏入口"):
		_finish()
		return
	await process_frame
	await process_frame
	await process_frame
	view = current_scene as Control
	_expect(view != null and view.name == "StrategicMapView", "加载游戏返回战略地图")
	if view == null or view.name != "StrategicMapView":
		_finish()
		return
	_expect(GameSessionService.player_character != null and GameSessionService.player_character.id == saved_player_id, "加载恢复继承后的玩家人物")
	_expect(GameSessionService.world_clock != null and GameSessionService.world_clock.total_hours == saved_hour, "加载恢复权威时间")
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
) -> bool:
	var panel_ready: bool = panel != null and panel.visible and panel.is_visible_in_tree()
	_expect(panel_ready, "行动面板在开始 %s 前保持可见" % definition_id)
	if not panel_ready or not _select_action(panel, definition_id, target_id):
		return false
	var begin_button: Button = panel.get_node("Margin/Root/Scroll/Content/BeginButton") as Button
	if not _press_button(begin_button, "%s 的开始按钮" % definition_id):
		return false
	var action: ActionInstanceData = GameSessionService.current_action
	var started: bool = action != null and action.definition_id == definition_id
	_expect(started, "通过正式行动面板开始 %s" % definition_id)
	if not started:
		return false
	clock.advance_hours(hours)
	_expect(action.status == ActionInstanceData.STATUS_COMPLETED, "%s 随权威时间完成" % definition_id)
	_expect(action.outcome_code != "failure", "%s 在测试人物条件下成功" % definition_id)
	return action.status == ActionInstanceData.STATUS_COMPLETED and action.outcome_code != "failure"


func _select_action(panel: ActionPanel, definition_id: String, target_id: String) -> bool:
	if not _select_option(panel.action_option, definition_id, "行动类型 %s" % definition_id):
		return false
	if target_id.is_empty():
		return true
	return _select_option(panel.target_option, target_id, "%s 的目标 %s" % [definition_id, target_id])


func _select_option(option: OptionButton, metadata: String, description: String) -> bool:
	var usable: bool = option != null and option.is_visible_in_tree() and not option.disabled
	_expect(usable, "%s 控件真实可见且可用" % description)
	if not usable:
		return false
	var index: int = _option_index(option, metadata)
	_expect(index >= 0, "%s 提供预期选项" % description)
	if index < 0:
		return false
	option.select(index)
	option.item_selected.emit(index)
	return str(option.get_item_metadata(option.selected)) == metadata


func _press_button(button: Button, description: String) -> bool:
	var usable: bool = button != null and button.is_visible_in_tree() and not button.disabled
	_expect(usable, "%s真实可见且可用" % description)
	if not usable:
		return false
	var button_rect: Rect2 = button.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, get_root().size)
	var on_screen: bool = button_rect.size.x > 0.0 and button_rect.size.y > 0.0 and viewport_rect.intersects(button_rect)
	_expect(on_screen, "%s位于可交互视口内" % description)
	if not on_screen:
		return false
	button.pressed.emit()
	return true


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
