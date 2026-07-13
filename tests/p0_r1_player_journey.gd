extends SceneTree
## Player-journey regression: drives visible public UI controls with viewport mouse input.

var _checks: int = 0
var _failures: int = 0
var _preserved_save_slots: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_preserve_save_slots()
	_cleanup_test_saves()
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
	if not (await _click_button(action_button, "顶栏长期行动入口")):
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

	if not (await _run_action(action_panel, "action:build_relationship", leader_id, clock, 500)):
		_finish()
		return
	if not (await _run_action(action_panel, "action:build_relationship", leader_id, clock, 500)):
		_finish()
		return
	_expect(society.relationships.get_between(player.id, leader_id) != null, "玩家通过两次正式长期行动建立真实关系")

	if not (await _run_action(action_panel, "action:join_organization", government_id, clock, 500)):
		_finish()
		return
	_expect(government.member_ids.has(player.id), "加入组织行动把玩家写入正式成员索引")
	var entry_position: String = society.organizations.get_position_id(player.id, government_id)
	_expect(not entry_position.is_empty(), "加入组织后获得入口职位")

	if not (await _run_action(action_panel, "action:seek_position", government_id, clock, 500)):
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
	if not (await _run_action(action_panel, "action:promote_policy", target_unit_id, clock, 800)):
		_finish()
		return
	_expect(float(target_region.social_influence[player.country_id]) > influence_before, "地区政策行动改变权威社会影响")

	if not _select_action(action_panel, "action:study_skill", ""):
		_finish()
		return
	var begin_button: Button = action_panel.get_node("Margin/Root/Scroll/Content/BeginButton") as Button
	if not (await _click_button(begin_button, "学习行动开始按钮")):
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
	if not (await _click_button(character_button, "人物信息入口")):
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
	if not (await _click_button(profile_back, "人物页面返回按钮")):
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
	if not (await _click_button(social_button, "社会系统入口")):
		_finish()
		return
	var social_panel: SocialSystemPanel = view.get_node("SocialSystemPanel") as SocialSystemPanel
	_expect(social_panel.visible and social_panel.is_visible_in_tree(), "点击顶栏后社会系统面板真实显示")
	if not social_panel.visible or not social_panel.is_visible_in_tree():
		_finish()
		return
	var prepare_succession: Button = social_panel.get_node("Margin/Root/Scroll/Content/PrepareSuccessionButton") as Button
	if not (await _click_button(prepare_succession, "继承候选入口")):
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
	if not (await _click_button(confirm_succession, "退休继承确认按钮")):
		_finish()
		return
	_expect(GameSessionService.player_character.id == leader_id, "玩家通过正式社会界面完成退休继承")
	_expect(GameSessionService.world_clock == clock_reference and GameSessionService.world_map_service == map_reference, "继承保持同一权威世界")

	var saved_player_id: String = GameSessionService.player_character.id
	var saved_hour: int = clock_reference.total_hours
	var saved_influence: float = float(target_region.social_influence[player.country_id])
	save_button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SaveButton") as Button
	if not (await _click_button(save_button, "保存游戏入口")):
		_finish()
		return
	_expect(FileAccess.file_exists(GameSaveService.MANUAL_PATH), "普通保存按钮写入手动存档")
	_expect(save_button.text == "已保存", "普通保存按钮提供成功反馈")
	var autosave_result: SaveOperationResult = GameSaveService.new().save_autosave(
		clock_reference, map_reference
	)
	_expect(autosave_result.success, "当前世界可写入自动存档槽")

	var back_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/BackButton") as Button
	if not (await _click_button(back_button, "返回主菜单入口")):
		_finish()
		return
	await process_frame
	await process_frame
	var menu: Control = current_scene as Control
	_expect(menu != null and menu.name == "MainMenu", "返回主菜单入口切换到主菜单")
	if menu == null or menu.name != "MainMenu":
		_finish()
		return
	var manual_load_button: Button = menu.get_node("SafeMargin/Center/Card/CardMargin/Content/LoadGameButton") as Button
	var autosave_load_button: Button = menu.get_node("SafeMargin/Center/Card/CardMargin/Content/LoadAutosaveButton") as Button
	_expect(manual_load_button.is_visible_in_tree() and not manual_load_button.disabled, "主菜单显示可用的手动存档入口")
	if not (await _click_button(autosave_load_button, "加载自动存档入口")):
		_finish()
		return
	await process_frame
	await process_frame
	await process_frame
	view = current_scene as Control
	if not _verify_loaded_world(view, saved_player_id, saved_hour, target_unit_id, player.country_id, saved_influence, "自动存档"):
		_finish()
		return

	back_button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/BackButton") as Button
	if not (await _click_button(back_button, "自动存档返回主菜单入口")):
		_finish()
		return
	await process_frame
	await process_frame
	menu = current_scene as Control
	manual_load_button = menu.get_node("SafeMargin/Center/Card/CardMargin/Content/LoadGameButton") as Button
	if not (await _click_button(manual_load_button, "加载手动存档入口")):
		_finish()
		return
	await process_frame
	await process_frame
	await process_frame
	view = current_scene as Control
	if not _verify_loaded_world(view, saved_player_id, saved_hour, target_unit_id, player.country_id, saved_influence, "手动存档"):
		_finish()
		return

	GameSessionService.clear()
	_finish()


func _verify_loaded_world(
	view: Control,
	saved_player_id: String,
	saved_hour: int,
	target_unit_id: String,
	country_id: String,
	saved_influence: float,
	label: String
) -> bool:
	var valid_view: bool = view != null and view.name == "StrategicMapView"
	_expect(valid_view, "%s加载后返回战略地图" % label)
	if not valid_view:
		return false
	var player_restored: bool = (
		GameSessionService.player_character != null
		and GameSessionService.player_character.id == saved_player_id
	)
	_expect(player_restored, "%s恢复继承后的玩家人物" % label)
	var time_restored: bool = (
		GameSessionService.world_clock != null
		and GameSessionService.world_clock.total_hours == saved_hour
	)
	_expect(time_restored, "%s恢复权威时间" % label)
	if not player_restored or not time_restored or GameSessionService.world_map_service == null:
		return false
	var loaded_unit: ControlUnitData = GameSessionService.world_map_service.get_unit(target_unit_id)
	if loaded_unit == null:
		_expect(false, "%s恢复地区目标" % label)
		return false
	var loaded_region: RegionData = GameSessionService.world_map_service.data_set.regions[loaded_unit.region_id] as RegionData
	var influence_restored: bool = is_equal_approx(
		float(loaded_region.social_influence[country_id]), saved_influence
	)
	_expect(influence_restored, "%s恢复地区社会影响" % label)
	return player_restored and time_restored and influence_restored


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
	if not (await _click_button(begin_button, "%s 的开始按钮" % definition_id)):
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


func _click_button(button: Button, description: String) -> bool:
	var usable: bool = button != null and button.is_visible_in_tree() and not button.disabled
	_expect(usable, "%s真实可见且可用" % description)
	if not usable:
		return false
	if not (await _scroll_control_into_view(button, description)):
		return false
	var button_rect: Rect2 = button.get_global_rect()
	var center: Vector2 = button_rect.get_center()
	_move_pointer(center)
	await process_frame
	var hovered: Control = get_root().gui_get_hovered_control()
	var receives_pointer: bool = hovered == button or (
		hovered != null and button.is_ancestor_of(hovered)
	)
	_expect(receives_pointer, "%s未被其他控件遮挡" % description)
	if not receives_pointer:
		return false

	var triggered: Array[bool] = [false]
	var observer: Callable = func() -> void:
		triggered[0] = true
	button.pressed.connect(observer, CONNECT_ONE_SHOT)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	get_root().push_input(press, true)
	await process_frame

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.position = center
	release.global_position = center
	release.pressed = false
	get_root().push_input(release, true)
	await process_frame

	var actually_pressed: bool = triggered[0]
	_expect(actually_pressed, "%s通过真实鼠标按下与释放触发" % description)
	if is_instance_valid(button) and button.pressed.is_connected(observer):
		button.pressed.disconnect(observer)
	return actually_pressed


func _scroll_control_into_view(control: Control, description: String) -> bool:
	for _attempt: int in range(80):
		var target_rect: Rect2 = control.get_global_rect()
		var clip_rect: Rect2 = _get_interactive_clip_rect(control)
		if _rect_fully_inside(target_rect, clip_rect):
			_expect(true, "%s完整位于可交互区域" % description)
			return true
		var scroll: ScrollContainer = _find_scroll_ancestor(control)
		if scroll == null:
			_expect(false, "%s无法滚动到可交互区域" % description)
			return false
		var scroll_center: Vector2 = scroll.get_global_rect().get_center()
		_move_pointer(scroll_center)
		await process_frame
		var wheel := InputEventMouseButton.new()
		wheel.button_index = (
			MOUSE_BUTTON_WHEEL_DOWN
			if target_rect.get_center().y > clip_rect.get_center().y
			else MOUSE_BUTTON_WHEEL_UP
		)
		wheel.position = scroll_center
		wheel.global_position = scroll_center
		wheel.factor = 2.0
		wheel.pressed = true
		get_root().push_input(wheel, true)
		await process_frame
	_expect(false, "%s在滚动后仍不位于可交互区域" % description)
	return false


func _get_interactive_clip_rect(control: Control) -> Rect2:
	var clip_rect: Rect2 = get_root().get_visible_rect()
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			clip_rect = clip_rect.intersection((ancestor as ScrollContainer).get_global_rect())
		ancestor = ancestor.get_parent()
	return clip_rect


func _find_scroll_ancestor(control: Control) -> ScrollContainer:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


static func _rect_fully_inside(target: Rect2, container: Rect2) -> bool:
	if target.size.x <= 0.0 or target.size.y <= 0.0:
		return false
	var top_left: Vector2 = target.position + Vector2.ONE
	var bottom_right: Vector2 = target.position + target.size - Vector2.ONE
	return container.has_point(top_left) and container.has_point(bottom_right)


func _move_pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_root().notify_mouse_entered()
	get_root().push_input(motion, true)


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


func _preserve_save_slots() -> void:
	_preserved_save_slots.clear()
	for path: String in [GameSaveService.MANUAL_PATH, GameSaveService.AUTOSAVE_PATH]:
		_preserved_save_slots[path] = _capture_slot(path)


func _capture_slot(path: String) -> Dictionary:
	var captured: Dictionary = {}
	var absolute: String = ProjectSettings.globalize_path(path)
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate: String = absolute + suffix
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file != null:
			captured[suffix] = file.get_as_text()
			file.close()
	return captured


func _restore_save_slots() -> void:
	for raw_path: Variant in _preserved_save_slots:
		var path: String = str(raw_path)
		_cleanup_slot(path)
		var captured: Dictionary = _preserved_save_slots[path] as Dictionary
		var absolute: String = ProjectSettings.globalize_path(path)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		for raw_suffix: Variant in captured:
			var suffix: String = str(raw_suffix)
			var file := FileAccess.open(absolute + suffix, FileAccess.WRITE)
			if file != null:
				file.store_string(str(captured[suffix]))
				file.close()
	_preserved_save_slots.clear()


func _cleanup_test_saves() -> void:
	for path: String in [GameSaveService.MANUAL_PATH, GameSaveService.AUTOSAVE_PATH]:
		_cleanup_slot(path)


func _cleanup_slot(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	for candidate: String in [absolute, absolute + ".tmp", absolute + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
		return
	_failures += 1
	printerr("[FAIL] %s" % description)


func _finish() -> void:
	_cleanup_test_saves()
	_restore_save_slots()
	if _failures > 0:
		printerr("P0-R1 PLAYER JOURNEY FAILED: %d/%d checks failed" % [_failures, _checks])
		quit(1)
		return
	print("P0-R1 PLAYER JOURNEY PASSED: %d checks" % _checks)
	quit(0)
