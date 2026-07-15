extends SceneTree
## 1280x720 formal-player journey. After the stable new-game character is made,
## all player decisions enter through visible controls and authoritative time.

const MANUAL_PATH: String = GameSaveService.MANUAL_PATH
const VIEWPORT_SIZE := Vector2(1280.0, 720.0)

var _checks: int = 0
var _failures: int = 0
var _preserved_files: Dictionary = {}
var _view: Control
var _clock: SimulationClock
var _map: MapControlService
var _society: SocietySimulationService
var _action_panel: ActionPanel
var _social_panel: SocialSystemPanel


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LogService.set_minimum_level(LogService.Level.ERROR)
	_preserve_manual_files()
	GameSessionService.clear()
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可在进入地图前创建稳定的新游戏人物")
	if player == null:
		_finish()
		return
	GameSessionService.set_player(player)

	var packed: PackedScene = load("res://scenes/map/strategic_map_view.tscn") as PackedScene
	_view = packed.instantiate() as Control if packed != null else null
	_expect(_view != null, "战略地图可实例化")
	if _view == null:
		_finish()
		return
	get_root().content_scale_size = Vector2i(1280, 720)
	get_root().add_child(_view)
	current_scene = _view
	await process_frame
	await process_frame
	_refresh_world_references()
	_expect(
		_clock != null and _map != null and _society != null and _action_panel != null and _social_panel != null,
		"正式地图建立权威世界、行动页与社会页"
	)
	if _clock == null or _map == null or _society == null or _action_panel == null or _social_panel == null:
		_finish()
		return
	_expect(not GameSessionService.developer_mode, "玩家旅程全程关闭开发者模式")

	var government_id: String = "organization:loran_government"
	var government: OrganizationData = _society.organizations.get_organization(government_id)
	_expect(government != null and not government.leader_character_id.is_empty(), "本国政府具有可通过 UI 接触的真实领导人物")
	if government == null or government.leader_character_id.is_empty():
		_finish()
		return
	var leader_id: String = government.leader_character_id

	await _open_action_panel()
	_assert_action_layout()
	_expect(_selected_action_id() == "action:study_skill", "行动列表默认选择学习技能")
	var study_section: VBoxContainer = _action_panel.find_child("StudySection", true, false) as VBoxContainer
	var skill_option: OptionButton = _action_panel.find_child("StudySkillOption", true, false) as OptionButton
	var investment: SpinBox = _action_panel.find_child("InvestmentSpin", true, false) as SpinBox
	var action_scroll: ScrollContainer = _action_panel.find_child("ActionScroll", true, false) as ScrollContainer
	_expect(
		study_section != null
		and study_section.is_visible_in_tree()
		and skill_option != null
		and _rect_inside_rect(skill_option.get_global_rect(), action_scroll.get_global_rect()),
		"学习技能选择器完整位于行动首屏"
	)
	_expect(skill_option != null and skill_option.item_count == 9, "学习页面提供九项人物能力")
	_expect(
		investment != null
		and investment.is_visible_in_tree()
		and _rect_inside_rect(investment.get_global_rect(), action_scroll.get_global_rect()),
		"主动财富投入控件完整位于行动首屏"
	)
	_expect(_select_option_by_metadata(skill_option, "administration"), "可通过技能选择器选择行政")
	var administration_before: int = int(player.skills["administration"])
	_set_investment(20)
	_expect(_start_selected_action(), "通过固定可见按钮开始学习行政")
	_expect(GameSessionService.current_action.context.get("study_skill_id", "") == "administration", "权威行动记录保存所选学习技能")

	var action_pause: Button = _action_panel.find_child("PauseButton", true, false) as Button
	action_pause.pressed.emit()
	_expect(GameSessionService.current_action.status == ActionInstanceData.STATUS_PAUSED, "通过当前行动卡片暂停行动")
	action_pause.pressed.emit()
	_expect(GameSessionService.current_action.status == ActionInstanceData.STATUS_ACTIVE, "通过当前行动卡片继续行动")
	_expect(_complete_current_action(), "学习行动由权威时间推进到完成")
	_expect(int(player.skills["administration"]) > administration_before, "完成学习后行政能力成长")

	_expect(_action_panel.prefill_action("action:perform_work"), "可从行动列表选择从事工作")
	_set_investment(0)
	_expect(_start_selected_action(), "通过正式 UI 开始可取消的工作行动")
	var cancel_button: Button = _action_panel.find_child("CancelButton", true, false) as Button
	cancel_button.pressed.emit()
	_expect(GameSessionService.current_action.status == ActionInstanceData.STATUS_CANCELLED, "通过当前行动卡片取消行动")

	var paused_before: bool = _clock.is_paused
	await _send_input_action("toggle_pause")
	_expect(_clock.is_paused != paused_before, "地图按 Space 切换权威时钟暂停状态")
	await _send_input_action("toggle_pause")
	_expect(_clock.is_paused == paused_before, "再次按 Space 恢复原时钟状态")
	await _send_input_action("ui_cancel")
	_expect(not _action_panel.visible and not _modal_layer().visible, "按 Esc 关闭最上层行动面板")

	await _open_social_panel()
	_assert_social_layout()
	_expect(_social_player_sections_visible(), "社会页可查看我的组织、关系与继承状态")
	await _select_social_tab(1)
	var relationship_option: OptionButton = _social_panel.find_child("RelationshipOption", true, false) as OptionButton
	_expect(_select_option_by_metadata(relationship_option, leader_id), "可在关系页选择政府领导人物")
	var build_relationship: Button = _social_panel.find_child("BuildRelationshipButton", true, false) as Button
	_expect(build_relationship.is_visible_in_tree() and not build_relationship.disabled, "建立新联系入口真实可点击")
	build_relationship.pressed.emit()
	await process_frame
	_expect(_action_panel.visible and not _social_panel.visible, "社会入口跳转到行动页且保持单一主面板")
	_expect(_selected_action_id() == "action:build_relationship" and _selected_target_id() == leader_id, "建立关系行动自动预填人物目标")
	_set_investment(20)
	_expect(_start_selected_action(), "从社会页跳转后通过正式 UI 开始建立关系")
	_expect(_complete_current_action(), "建立关系行动完成")
	_expect(_society.relationships.get_between(player.id, leader_id) != null, "社会服务出现真实双向关系记录")

	await _open_social_panel()
	await _select_social_tab(0)
	var organization_option: OptionButton = _social_panel.find_child("OrganizationOption", true, false) as OptionButton
	_expect(_select_option_by_metadata(organization_option, government_id), "可在我的组织页选择本国政府")
	var join_button: Button = _social_panel.find_child("JoinActionButton", true, false) as Button
	_expect(join_button.is_visible_in_tree() and not join_button.disabled, "申请加入入口真实可点击")
	join_button.pressed.emit()
	await process_frame
	_expect(_selected_action_id() == "action:join_organization" and _selected_target_id() == government_id, "申请加入自动预填组织目标")
	_set_investment(20)
	_expect(_start_selected_action(), "通过正式 UI 开始加入组织")
	_expect(_complete_current_action(), "加入组织行动完成")
	_expect(government.member_ids.has(player.id), "完成后玩家获得组织身份和入口职位")

	await _open_social_panel()
	await _select_social_tab(0)
	_select_option_by_metadata(organization_option, government_id)
	var position_button: Button = _social_panel.find_child("PositionActionButton", true, false) as Button
	_expect(position_button.is_visible_in_tree() and not position_button.disabled, "争取职位入口在成员状态下可点击")
	var old_position_id: String = _society.organizations.get_position_id(player.id, government_id)
	position_button.pressed.emit()
	await process_frame
	_expect(_selected_action_id() == "action:seek_position" and _selected_target_id() == government_id, "争取职位自动预填当前组织")
	_set_investment(20)
	_expect(_start_selected_action(), "通过正式 UI 开始争取职位")
	_expect(_complete_current_action(), "争取职位行动完成")
	var new_position_id: String = _society.organizations.get_position_id(player.id, government_id)
	_expect(not new_position_id.is_empty() and new_position_id != old_position_id, "完成后获得更高职位与地区政策权限")

	await _open_social_panel()
	await _select_social_tab(0)
	_select_option_by_metadata(organization_option, government_id)
	var policy_button: Button = _social_panel.find_child("PolicyActionButton", true, false) as Button
	_expect(policy_button.is_visible_in_tree() and not policy_button.disabled, "获得权限后推动政策入口可点击")
	policy_button.pressed.emit()
	await process_frame
	_expect(_selected_action_id() == "action:promote_policy" and not _selected_target_id().is_empty(), "推动政策自动预填辖区内地区目标")
	var policy_unit: ControlUnitData = _map.get_unit(_selected_target_id())
	var policy_region: RegionData = _map.data_set.regions.get(policy_unit.region_id) as RegionData
	var influence_before: Dictionary = policy_region.social_influence.duplicate(true)
	_set_investment(20)
	_expect(_start_selected_action(), "通过正式 UI 开始地区政策行动")
	_expect(_complete_current_action(), "地区政策行动完成")
	_expect(policy_region.social_influence != influence_before, "政策行动完成后改变权威地区社会影响")

	var hour_before_profile: int = _clock.total_hours
	await _open_profile_and_return()
	_refresh_world_references()
	_expect(_clock.total_hours == hour_before_profile, "人物页往返保持同一权威世界时间")
	_expect(GameSessionService.current_action != null and GameSessionService.current_action.is_terminal(), "页面切换保持行动状态")

	await _open_social_panel()
	await _select_social_tab(2)
	var exit_reason: OptionButton = _social_panel.find_child("ExitReasonOption", true, false) as OptionButton
	_expect(_select_option_by_metadata(exit_reason, "voluntary"), "社会页显示权威服务认可的自愿退出原因")
	var prepare: Button = _social_panel.find_child("PrepareSuccessionButton", true, false) as Button
	_expect(prepare.is_visible_in_tree() and not prepare.disabled, "合法退出条件下可查看继承者")
	prepare.pressed.emit()
	await process_frame
	var successor_option: OptionButton = _social_panel.find_child("SuccessionOption", true, false) as OptionButton
	var confirm: Button = _social_panel.find_child("ConfirmSuccessionButton", true, false) as Button
	_expect(successor_option.item_count > 0 and not confirm.disabled, "真实关系或共同组织产生合法继承候选")
	if successor_option.item_count == 0 or confirm.disabled:
		_finish()
		return
	var old_player_id: String = player.id
	var expected_successor_id: String = str(successor_option.get_item_metadata(successor_option.selected))
	confirm.pressed.emit()
	await process_frame
	_expect(GameSessionService.player_character.id == expected_successor_id and expected_successor_id != old_player_id, "通过可见确认按钮完成人物继承")
	_expect(_society.roster.get_exited(old_player_id) != null, "旧人物保留在退出历史并继续同一世界")

	var save_button: Button = _view.find_child("SaveButton", true, false) as Button
	_expect(save_button != null and save_button.is_visible_in_tree(), "正式保存按钮真实可见")
	var saved_player_id: String = GameSessionService.player_character.id
	var saved_hour: int = _clock.total_hours
	var saved_region_influence: Dictionary = policy_region.social_influence.duplicate(true)
	var saved_policy_unit: Dictionary = policy_unit.to_dict()
	save_button.pressed.emit()
	await process_frame
	_expect(FileAccess.file_exists(ProjectSettings.globalize_path(MANUAL_PATH)), "保存按钮写入手动存档")

	var more_button: MenuButton = _view.find_child("MoreButton", true, false) as MenuButton
	more_button.get_popup().id_pressed.emit(1)
	await process_frame
	await process_frame
	var menu: Node = current_scene
	_expect(menu != null and menu.name == "MainMenu", "通过更多菜单退出到主菜单")
	var load_button: Button = menu.find_child("LoadGameButton", true, false) as Button
	_expect(load_button != null and load_button.is_visible_in_tree() and not load_button.disabled, "主菜单显示可用的手动存档加载入口")
	load_button.pressed.emit()
	await process_frame
	await process_frame
	_view = current_scene as Control
	_refresh_world_references()
	_expect(_view != null and _view.name == "StrategicMapView", "通过主菜单真实加载返回战略地图")
	_expect(GameSessionService.player_character.id == saved_player_id and _clock.total_hours == saved_hour, "加载恢复玩家继承者与权威世界时间")
	var loaded_unit: ControlUnitData = _map.get_unit(str(saved_policy_unit["id"]))
	var loaded_region: RegionData = _map.data_set.regions.get(loaded_unit.region_id) as RegionData
	_expect(loaded_unit.to_dict() == saved_policy_unit, "加载恢复政策目标控制单元")
	_expect(_numeric_dictionary_approx(loaded_region.social_influence, saved_region_influence), "加载恢复地区社会影响")
	_expect(_society.roster.get_exited(old_player_id) != null, "加载恢复关系、组织与退出历史所在的社会状态")

	_finish()


func _refresh_world_references() -> void:
	_clock = GameSessionService.world_clock
	_map = GameSessionService.world_map_service
	_society = GameSessionService.society_service
	if _view != null:
		_action_panel = _view.find_child("ActionPanel", true, false) as ActionPanel
		_social_panel = _view.find_child("SocialSystemPanel", true, false) as SocialSystemPanel


func _open_action_panel() -> void:
	if _action_panel.visible:
		return
	var button: Button = _view.find_child("ActionButton", true, false) as Button
	_expect(button != null and button.is_visible_in_tree(), "长期行动正式入口可见")
	if button != null:
		button.pressed.emit()
		await create_timer(0.24).timeout
	_expect(_action_panel.visible, "长期行动面板已打开")


func _open_social_panel() -> void:
	if _social_panel.visible:
		return
	var button: Button = _view.find_child("SocialButton", true, false) as Button
	_expect(button != null and button.is_visible_in_tree(), "社会系统正式入口可见")
	if button != null:
		button.pressed.emit()
		await create_timer(0.24).timeout
	_expect(_social_panel.visible, "社会系统面板已打开")


func _assert_action_layout() -> void:
	var panel_rect: Rect2 = _action_panel.get_global_rect()
	var scroll: ScrollContainer = _action_panel.find_child("ActionScroll", true, false) as ScrollContainer
	var begin: Button = _action_panel.find_child("BeginButton", true, false) as Button
	var list: ItemList = _action_panel.find_child("ActionList", true, false) as ItemList
	var choices: GridContainer = _action_panel.find_child("ActionButtons", true, false) as GridContainer
	_expect(panel_rect.size.y >= VIEWPORT_SIZE.y * 0.70, "ActionPanel 可见高度至少占窗口 70%")
	_expect(scroll.get_global_rect().size.y > 200.0, "行动内容滚动区高度大于 200")
	var all_choices_visible := choices != null and choices.get_child_count() == 8 and list.item_count == 8
	if all_choices_visible:
		for child: Node in choices.get_children():
			var choice := child as Button
			if choice == null or not choice.is_visible_in_tree() or not _rect_inside_rect(choice.get_global_rect(), scroll.get_global_rect()):
				all_choices_visible = false
				break
	_expect(all_choices_visible, "八类行动以 2×4 按钮完整位于行动首屏")
	_expect(
		_rect_inside_viewport(begin.get_global_rect()),
		"开始行动按钮完整位于 1280×720 窗口内：%s" % begin.get_global_rect()
	)
	_expect(not _social_panel.visible and not (_view.find_child("DeveloperPanel", true, false) as Control).visible, "行动页未被其他主面板遮挡")
	_expect(_modal_layer().visible and (_view.find_child("ModalBackdrop", true, false) as ColorRect).is_visible_in_tree(), "打开主面板时显示半透明模态遮罩")


func _assert_social_layout() -> void:
	var panel_rect: Rect2 = _social_panel.get_global_rect()
	var tabs: TabContainer = _social_panel.find_child("SocialTabs", true, false) as TabContainer
	var dev_section: PanelContainer = _social_panel.find_child("DeveloperSection", true, false) as PanelContainer
	_expect(panel_rect.size.y >= VIEWPORT_SIZE.y * 0.70, "SocialSystemPanel 可见高度至少占窗口 70%")
	_expect(tabs.get_global_rect().size.y > 200.0, "社会系统内容区高度大于 200")
	_expect(
		_rect_inside_viewport(panel_rect),
		"社会系统主要控件完整位于 1280×720 窗口内：%s" % panel_rect
	)
	_expect(not dev_section.is_visible_in_tree(), "正式玩家模式不存在可见的开发者直接修改区")
	_expect(not _action_panel.visible and not (_view.find_child("DeveloperPanel", true, false) as Control).visible, "社会页未被其他主面板遮挡")


func _social_player_sections_visible() -> bool:
	var tabs: TabContainer = _social_panel.find_child("SocialTabs", true, false) as TabContainer
	return tabs != null and tabs.get_tab_count() == 3 and tabs.get_tab_title(0) == "我的组织" and tabs.get_tab_title(1) == "人际关系" and tabs.get_tab_title(2) == "人物继承"


func _select_social_tab(index: int) -> void:
	var tabs: TabContainer = _social_panel.find_child("SocialTabs", true, false) as TabContainer
	tabs.current_tab = index
	await process_frame


func _selected_action_id() -> String:
	var list: ItemList = _action_panel.find_child("ActionList", true, false) as ItemList
	var selected: PackedInt32Array = list.get_selected_items()
	return "" if selected.is_empty() else str(list.get_item_metadata(selected[0]))


func _selected_target_id() -> String:
	var option: OptionButton = _action_panel.find_child("TargetOption", true, false) as OptionButton
	return "" if option == null or option.item_count == 0 or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _set_investment(value: int) -> void:
	var investment: SpinBox = _action_panel.find_child("InvestmentSpin", true, false) as SpinBox
	investment.value = minf(float(value), investment.max_value)
	investment.value_changed.emit(investment.value)


func _start_selected_action() -> bool:
	var begin: Button = _action_panel.find_child("BeginButton", true, false) as Button
	if begin == null or not begin.is_visible_in_tree() or begin.disabled:
		return false
	begin.pressed.emit()
	return GameSessionService.current_action != null and GameSessionService.current_action.definition_id == _selected_action_id()


func _complete_current_action() -> bool:
	var guard: int = 0
	while GameSessionService.current_action != null and not GameSessionService.current_action.is_terminal() and guard < 400:
		_clock.advance_hours(24)
		guard += 1
	return GameSessionService.current_action != null and GameSessionService.current_action.status == ActionInstanceData.STATUS_COMPLETED and GameSessionService.current_action.domain_effect_applied


func _open_profile_and_return() -> void:
	if _modal_layer().visible:
		await _send_input_action("ui_cancel")
	var character_button: Button = _view.find_child("CharacterButton", true, false) as Button
	character_button.pressed.emit()
	await create_timer(0.24).timeout
	var profile: Control = _view.find_child("CharacterProfilePanel", true, false) as Control
	_expect(
		profile != null
		and profile.is_visible_in_tree()
		and current_scene == _view,
		"通过人物按钮打开地图上的结构化人物抽屉"
	)
	if profile == null:
		return
	var visible_text: String = _collect_visible_text(profile)
	for forbidden: String in ["population_category", "generation_seed", "random_state", "可见技能", "已知倾向"]:
		_expect(not visible_text.contains(forbidden), "正式人物抽屉不出现内部或实现视角文本：%s" % forbidden)
	var status_grid: GridContainer = profile.find_child("StatusGrid", true, false) as GridContainer
	var progress_bars: Array[Node] = profile.find_children("*", "ProgressBar", true, false)
	_expect(status_grid != null and status_grid.get_child_count() == 12, "人物抽屉用中文字段展示六项核心状态")
	_expect(progress_bars.size() == 9, "人物抽屉按分组进度条展示九项能力")
	var profile_clock_before: bool = _clock.is_paused
	await _send_input_action("toggle_pause")
	_expect(_clock.is_paused != profile_clock_before, "人物抽屉 Space 操作同一权威时钟")
	await _send_input_action("toggle_pause")
	character_button.pressed.emit()
	await create_timer(0.24).timeout
	_expect(
		not profile.visible and current_scene == _view,
		"再次点击人物入口收起抽屉且地图始终保持可见"
	)


func _send_input_action(action_name: String) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action_name
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventAction.new()
	released.action = action_name
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame
	if action_name == "ui_cancel":
		await create_timer(0.24).timeout


func _modal_layer() -> Control:
	return _view.find_child("ModalLayer", true, false) as Control


func _rect_inside_viewport(rect: Rect2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0 and rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= VIEWPORT_SIZE.x and rect.end.y <= VIEWPORT_SIZE.y


func _rect_inside_rect(rect: Rect2, container: Rect2) -> bool:
	return (
		rect.size.x > 0.0
		and rect.size.y > 0.0
		and rect.position.x >= container.position.x
		and rect.position.y >= container.position.y
		and rect.end.x <= container.end.x
		and rect.end.y <= container.end.y
	)


func _numeric_dictionary_approx(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for raw_key: Variant in expected:
		if not actual.has(raw_key) or not is_equal_approx(float(actual[raw_key]), float(expected[raw_key])):
			return false
	return true


func _collect_visible_text(root: Node) -> String:
	var parts: Array[String] = []
	for node: Node in root.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			continue
		if control is Label:
			parts.append((control as Label).text)
		elif control is RichTextLabel:
			parts.append((control as RichTextLabel).text)
		elif control is Button:
			parts.append((control as Button).text)
	return "\n".join(parts)


func _select_option_by_metadata(option: OptionButton, metadata_value: String) -> bool:
	if option == null:
		return false
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata_value:
			option.select(index)
			option.item_selected.emit(index)
			return true
	return false


func _make_test_player() -> CharacterData:
	var world: CoreDataLoadResult = CoreDataLoader.new().load_from_file("res://data/world/demo_world.json")
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	if not world.is_success() or not config.is_valid():
		return null
	var generator := CharacterGenerator.new(
		world.data_set,
		config,
		DeterministicRandomService.new(19000101),
		StableIdService.new()
	)
	var result: CharacterGenerationResult = generator.generate_character("country:loran_federation", CharacterGenerator.MODE_STANDARD)
	if not result.is_success():
		return null
	var player: CharacterData = result.character
	for raw_skill: Variant in player.skills:
		player.skills[raw_skill] = 100
	player.skills["administration"] = 60
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
		_preserved_files[path] = PackedByteArray() if file == null else file.get_buffer(file.get_length())
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
		printerr("CURRENT PLAYER JOURNEY FAILED: %d/%d" % [_failures, _checks])
		quit(1)
	else:
		print("CURRENT PLAYER JOURNEY PASSED: %d checks" % _checks)
		quit(0)
