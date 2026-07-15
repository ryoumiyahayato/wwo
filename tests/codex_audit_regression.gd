extends SceneTree
## Focused regression for the 2026-07-13 Codex audit findings.

var _checks: int = 0
var _failures: int = 0
var _view: Control
var _clock: SimulationClock
var _map: MapControlService
var _society: SocietySimulationService
var _rules: ActionRulesConfig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LogService.set_minimum_level(LogService.Level.ERROR)
	GameSessionService.clear()
	var player: CharacterData = _make_character(
		19000101, CharacterGenerator.MODE_STANDARD
	)
	_expect(player != null, "可创建 Codex 审计回归人物")
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
	_expect(_view != null, "战略地图及强类型依赖可实例化")
	if _view == null:
		_finish()
		return
	get_root().add_child(_view)
	current_scene = _view
	await process_frame
	_clock = GameSessionService.world_clock
	_map = GameSessionService.world_map_service
	_society = GameSessionService.society_service
	_rules = ActionRulesConfig.new()
	_expect(
		_clock != null
		and _map != null
		and _society != null
		and _rules.load_from_file() == OK,
		"权威世界与行动规则已建立"
	)
	if _clock == null or _map == null or _society == null or not _rules.is_valid():
		GameSessionService.clear()
		_finish()
		return

	_test_fixed_action_button_layout()
	await _test_drawer_navigation()
	_test_non_map_context_isolation()
	_test_peace_war_and_border_state()
	await _test_world_activity_notifications()
	_test_character_development_guidance()
	_test_standard_study_and_work_reachability()
	_test_standard_relationship_reachability()
	_test_selectable_skill_growth()
	_test_practical_skill_growth()
	_test_cross_seed_guaranteed_reachability()
	_test_authoritative_succession_reasons()
	_test_npc_elapsed_interval_uses_old_context()
	_test_save_runtime_invariants()

	GameSessionService.current_action = null
	GameSessionService.clear()
	_finish()


func _test_fixed_action_button_layout() -> void:
	var panel: ActionPanel = _view.find_child("ActionPanel", true, false) as ActionPanel
	_expect(panel != null, "地图模态层包含正式行动面板")
	var button: Button = (
		panel.get_node("Margin/Root/BeginButton") as Button if panel != null else null
	)
	_expect(button != null, "开始行动按钮固定在滚动区外")
	var ancestor: Node = button.get_parent() if button != null else null
	var inside_scroll: bool = false
	while ancestor != null and ancestor != panel:
		if ancestor is ScrollContainer:
			inside_scroll = true
			break
		ancestor = ancestor.get_parent()
	_expect(not inside_scroll, "1280×720 下开始行动按钮不依赖滚动到页尾")


func _test_drawer_navigation() -> void:
	var character_button: Button = _view.find_child("CharacterButton", true, false) as Button
	var action_button: Button = _view.find_child("ActionButton", true, false) as Button
	var social_button: Button = _view.find_child("SocialButton", true, false) as Button
	var activity_button: Button = _view.find_child("WorldActivityButton", true, false) as Button
	var save_button: Button = _view.find_child("SaveButton", true, false) as Button
	var character_panel: Control = _view.find_child("CharacterProfilePanel", true, false) as Control
	var action_panel: Control = _view.find_child("ActionPanel", true, false) as Control
	var social_panel: Control = _view.find_child("SocialSystemPanel", true, false) as Control
	var activity_panel: Control = _view.find_child("WorldActivityPanel", true, false) as Control
	var modal_layer: Control = _view.find_child("ModalLayer", true, false) as Control
	_expect(
		character_button != null
		and action_button != null
		and social_button != null
		and activity_button != null
		and save_button != null,
		"地图顶栏提供四个玩法入口和独立保存工具入口"
	)
	_expect(
		character_button.get_parent() == action_button.get_parent()
		and action_button.get_parent() == social_button.get_parent()
		and save_button.get_parent() != character_button.get_parent(),
		"玩法入口与工具入口使用独立顶栏分组"
	)
	character_button.pressed.emit()
	_expect(character_panel.visible and character_panel.position.x < 0.0, "人物抽屉从左侧开始滑入")
	await create_timer(0.35).timeout
	_expect(
		is_equal_approx(character_panel.position.x, 14.0)
		and character_panel.size.x >= 440.0
		and character_panel.size.x <= 520.0,
		"人物抽屉停靠左侧且宽度处于 440～520 像素：%s" % character_panel.get_global_rect()
	)
	action_button.pressed.emit()
	await create_timer(0.35).timeout
	_expect(
		action_panel.visible
		and not character_panel.visible
		and not social_panel.visible
		and not activity_panel.visible,
		"切换玩法入口时抽屉保持互斥"
	)
	action_button.pressed.emit()
	await create_timer(0.35).timeout
	_expect(not action_panel.visible and not modal_layer.visible, "再次点击当前入口反向收起抽屉")
	social_button.pressed.emit()
	await create_timer(0.35).timeout
	_expect(social_panel.visible and modal_layer.visible, "社会抽屉可从同一左侧位置打开")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await create_timer(0.35).timeout
	_expect(not social_panel.visible and not modal_layer.visible, "Esc 关闭当前左侧抽屉")
	activity_button.pressed.emit()
	await create_timer(0.35).timeout
	_expect(activity_panel.visible and modal_layer.visible, "世界动态使用统一左侧抽屉")
	activity_button.pressed.emit()
	await create_timer(0.24).timeout


func _test_non_map_context_isolation() -> void:
	var panel: ActionPanel = _view.find_child("ActionPanel", true, false) as ActionPanel
	var player: CharacterData = GameSessionService.player_character
	var unit_ids: Array[String] = _map.get_sorted_unit_ids()
	_expect(unit_ids.size() >= 2, "地图具有两个可用于作用域回归的地区单元")
	if panel == null or unit_ids.size() < 2:
		return
	var first_unit_id: String = unit_ids[0]
	var second_unit_id: String = unit_ids[unit_ids.size() - 1]
	var study: ActionDefinitionData = _map.data_set.actions.get(
		"action:study_skill"
	) as ActionDefinitionData
	var work: ActionDefinitionData = _map.data_set.actions.get(
		"action:perform_work"
	) as ActionDefinitionData
	panel.prefill_action(study.id)
	panel.set_target(first_unit_id)
	var study_a: Dictionary = panel.context_service.build_context(
		study, player, first_unit_id, 5, "administration"
	)


	panel.set_target(second_unit_id)
	var study_b: Dictionary = panel.context_service.build_context(
		study, player, second_unit_id, 5, "administration"
	)
	_expect(
		panel.target_id.is_empty()
		and str(study_a.get("target_id", "invalid")).is_empty()
		and study_a == study_b,
		"切换地图地区后学习行动完整上下文保持一致且目标为空"
	)
	panel.prefill_action(work.id)
	panel.set_target(first_unit_id)
	var work_a: Dictionary = panel.context_service.build_context(
		work, player, first_unit_id, 5
	)
	panel.set_target(second_unit_id)
	var work_b: Dictionary = panel.context_service.build_context(
		work, player, second_unit_id, 5
	)
	_expect(
		panel.target_id.is_empty()
		and str(work_a.get("target_id", "invalid")).is_empty()
		and work_a == work_b,
		"切换地图地区后工作行动完整上下文保持一致且目标为空"
	)
	_expect(
		PlayerActionContextService.get_target_domain("build_relationship")
		== PlayerActionContextService.TARGET_DOMAIN_CHARACTER
		and PlayerActionContextService.get_target_domain("investigate_character")
		== PlayerActionContextService.TARGET_DOMAIN_CHARACTER
		and PlayerActionContextService.get_target_domain("join_organization")
		== PlayerActionContextService.TARGET_DOMAIN_ORGANIZATION
		and PlayerActionContextService.get_target_domain("seek_position")
		== PlayerActionContextService.TARGET_DOMAIN_ORGANIZATION
		and PlayerActionContextService.get_target_domain("promote_policy")
		== PlayerActionContextService.TARGET_DOMAIN_MAP
		and PlayerActionContextService.get_target_domain("support_control")
		== PlayerActionContextService.TARGET_DOMAIN_MAP,
		"人物、组织和地图行动具有显式且互不混用的目标域"
	)


func _test_peace_war_and_border_state() -> void:
	_expect(not _map.is_war_active(), "标准世界以权威和平状态开始")
	var peace_state: Dictionary = _map.get_persistent_state()
	var war_state: Dictionary = _map.get_war_state()
	_expect(
		str(war_state.get("status", "")) == MapControlService.WAR_STATUS_PEACE
		and str(war_state.get("stalemate_reason", "")) == "当前无战争。",
		"和平状态明确记录状态与无战争原因"
	)
	var war_label: Label = _view.find_child("WarStatusLabel", true, false) as Label
	_expect(
		war_label != null
		and war_label.text.contains("当前无战争")
		and war_label.text.contains("国境/控制边界"),
		"正式地图明确显示无战争且边界不是前线"
	)
	_expect(_map.get_border_edges() == _map.get_frontline_edges(), "相邻控制区以国境/控制边界接口公开")
	var units_before: Dictionary = (
		peace_state.get("control_units", {}) as Dictionary
	).duplicate(true)
	_society._execute_ai_monthly_world_actions()
	var units_after: Dictionary = (
		_map.get_persistent_state().get("control_units", {}) as Dictionary
	).duplicate(true)
	_expect(units_after == units_before, "和平期 NPC 月度行动不产生军事控制压力或边界变化")
	var support: ActionDefinitionData = _map.data_set.actions.get(
		"action:support_control"
	) as ActionDefinitionData
	var context_service := PlayerActionContextService.new(_rules, _society, _map)
	var support_error: String = context_service.get_target_validation_error(
		support, GameSessionService.player_character, _map.get_sorted_unit_ids()[0]
	)
	_expect(
		support_error == "当前无战争或没有合法前线目标。",
		"和平期支持控制行动以明确统一原因禁用"
	)
	var legacy_state: Dictionary = peace_state.duplicate(true)
	legacy_state.erase("war_state")
	_expect(
		_map.restore_persistent_state(legacy_state) and not _map.is_war_active(),
		"缺少战争字段的旧存档兼容迁移为和平状态"
	)
	var participants: Array[String] = _map.get_country_ids()
	_expect(
		_map.declare_war(
			participants,
			_clock.total_hours,
			{participants[0]: "保卫边境", participants[1]: "争夺边境"}
		),
		"战争必须通过包含参战国、开始时间和目标的权威状态显式建立"
	)
	var active_state: Dictionary = _map.get_war_state()
	_expect(
		_map.is_war_active()
		and (active_state.get("participant_country_ids", []) as Array).size() == 2
		and int(active_state.get("start_hour", -1)) == _clock.total_hours
		and not (active_state.get("objectives", {}) as Dictionary).is_empty()
		and not str(active_state.get("stalemate_reason", "")).is_empty(),
		"战时状态包含参战国、开始时间、战争目标和可观察僵持原因"
	)
	var active_snapshot: Dictionary = _map.get_persistent_state()
	_expect(_map.end_war(), "显式战争可以结束并恢复和平")
	_expect(
		_map.restore_persistent_state(active_snapshot)
		and _map.get_war_state() == active_state,
		"战争权威状态可随世界存档完整往返"
	)
	_expect(_map.restore_persistent_state(peace_state), "和平世界状态可在战争测试后恢复")


func _test_world_activity_notifications() -> void:
	var activity: WorldActivityService = _society.world_activity
	var center: WorldNotificationCenter = _view.find_child(
		"WorldNotificationCenter", true, false
	) as WorldNotificationCenter
	var panel: WorldActivityPanel = _view.find_child(
		"WorldActivityPanel", true, false
	) as WorldActivityPanel
	_expect(
		activity != null and center != null and panel != null,
		"正式世界动态服务、历史抽屉和右下角通知中心已建立"
	)
	if activity == null or center == null or panel == null:
		return
	var added_events: Array[Dictionary] = []
	for index: int in range(6):
		added_events.append(activity.add_event(
			"test_public_event",
			"公开动态 %d" % (index + 1),
			"用于验证正式通知的有界显示与过期。",
			_clock.total_hours,
			WorldActivityService.IMPORTANCE_NORMAL
		))
	_expect(
		center.get_visible_count() == WorldNotificationCenter.MAX_VISIBLE,
		"右下角通知同时最多显示 4 条"
	)
	_expect(
		panel.event_list.get_child_count() == activity.size(),
		"世界动态抽屉与通知中心消费同一份公开事件历史"
	)
	var newest: Dictionary = added_events[added_events.size() - 1]
	_expect(
		center.expire_notification(str(newest["id"]), false)
		and center.get_visible_count() == WorldNotificationCenter.MAX_VISIBLE - 1,
		"正式通知可按事件 ID 过期且立即释放显示槽"
	)
	var persistent_state: Dictionary = activity.get_persistent_state()
	var restored := WorldActivityService.new()
	_expect(
		restored.restore_persistent_state(persistent_state, _clock.total_hours)
		and restored.get_persistent_state() == persistent_state,
		"世界动态历史与事件 ID 可随存档完整往返"
	)
	var invalid_state: Dictionary = persistent_state.duplicate(true)
	var invalid_events: Array = invalid_state["events"] as Array
	(invalid_events[invalid_events.size() - 1] as Dictionary)["world_hour"] = (
		_clock.total_hours + 1
	)
	_expect(
		not WorldActivityService.new().restore_persistent_state(
			invalid_state, _clock.total_hours
		),
		"世界动态恢复拒绝来自未来的事件"
	)
	var membership_recorded: bool = false
	for character_id: String in _society.ai.get_ai_character_ids():
		var character: CharacterData = _society.roster.get_active(character_id)
		for organization_id: String in _society.organizations.get_organization_ids():
			var organization: OrganizationData = _society.organizations.get_organization(
				organization_id
			)
			if (
				organization.country_id != character.country_id
				or organization.member_ids.has(character.id)
				or not _society.organizations.has_entry_vacancy(organization.id)
			):
				continue
			var before_membership_event: int = activity.size()
			membership_recorded = _society.organizations.join_organization(
				character, organization.id
			)
			membership_recorded = (
				membership_recorded
				and activity.size() == before_membership_event + 1
				and str(activity.get_recent(1)[0].get("category", ""))
				== "organization_membership"
			)
			break
		if membership_recorded:
			break
	_expect(membership_recorded, "NPC 加入组织会生成正式公开动态与通知")
	for event: Dictionary in activity.get_recent():
		_expect(
			not event.has("random_state")
			and not event.has("generation_seed")
			and not event.has("population_category"),
			"正式世界动态不暴露内部字段：%s" % str(event.get("id", ""))
		)


func _test_character_development_guidance() -> void:
	var panel: CharacterProfilePanel = _view.find_child(
		"CharacterProfilePanel", true, false
	) as CharacterProfilePanel
	var player: CharacterData = GameSessionService.player_character
	_expect(panel != null, "人物抽屉提供当前发展卡片")
	if panel == null:
		return
	panel.refresh_view()
	var suggestions: Array[String] = panel.get_development_suggestions(player)
	_expect(
		suggestions.size() >= 2 and suggestions.size() <= 4,
		"人物当前发展卡片只显示 2～4 条实时建议"
	)
	var guidance_text: String = "\n".join(suggestions)
	var relationship_target: Dictionary = panel._best_relationship_target(player)
	var organization_target: Dictionary = panel._best_organization_target(player)
	_expect(
		not relationship_target.is_empty()
		and guidance_text.contains(str(relationship_target["name"])),
		"当前发展指出按实际把握计算的最容易人物目标"
	)
	_expect(
		not organization_target.is_empty()
		and guidance_text.contains(str(organization_target["name"])),
		"当前发展指出按实际把握计算且有入口空位的匹配组织"
	)
	_expect(
		guidance_text.contains("推荐能力")
		and not guidance_text.contains("将在")
		and not guidance_text.contains("教程"),
		"当前发展给出紧凑能力建议且不显示占位文字或长教程"
	)
	var previous_action: ActionInstanceData = GameSessionService.current_action
	var blocking_action := ActionInstanceData.new()
	blocking_action.id = "action_instance:guidance_probe"
	blocking_action.status = ActionInstanceData.STATUS_ACTIVE
	GameSessionService.current_action = blocking_action
	var blocked_text: String = "\n".join(panel.get_development_suggestions(player))
	GameSessionService.current_action = previous_action
	_expect(blocked_text.contains("当前阻挡：已有进行中行动"), "当前发展明确指出进行中行动阻挡")


func _test_standard_study_and_work_reachability() -> void:
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	var context_service := PlayerActionContextService.new(_rules, null, null)
	var evaluator := ActionService.new(_rules, StableIdService.new())
	var study: ActionDefinitionData = _map.data_set.actions.get(
		"action:study_skill"
	) as ActionDefinitionData
	var work: ActionDefinitionData = _map.data_set.actions.get(
		"action:perform_work"
	) as ActionDefinitionData
	var countries: Array[String] = [
		"country:loran_federation", "country:vesta_union",
	]
	var study_reachable: int = 0
	var work_base_near_line: int = 0
	var work_reachable: int = 0
	var work_skill_matched: int = 0
	var worst_study: float = INF
	var worst_work: float = INF
	for seed_value: int in range(1, 201):
		var generator := CharacterGenerator.new(
			_map.data_set,
			config,
			DeterministicRandomService.new(seed_value),
			StableIdService.new()
		)
		var generated: CharacterGenerationResult = generator.generate_character(
			countries[(seed_value - 1) % countries.size()],
			CharacterGenerator.MODE_STANDARD
		)
		if not generated.is_success():
			continue
		var character: CharacterData = generated.character
		var weakest_skill_id: String = config.skill_keys[0]
		for skill_id: String in config.skill_keys:
			if int(character.skills[skill_id]) < int(character.skills[weakest_skill_id]):
				weakest_skill_id = skill_id
		var study_context: Dictionary = context_service.build_context(
			study, character, "control:r0_c0", 20, weakest_skill_id
		)
		var study_effective: float = evaluator.calculate_effective_value(
			study, character, study_context
		)
		worst_study = minf(worst_study, study_effective)
		if study_effective >= study.success_threshold:
			study_reachable += 1
		var base_work_context: Dictionary = context_service.build_context(
			work, character, "control:r0_c0", 0
		)
		var full_work_context: Dictionary = context_service.build_context(
			work, character, "control:r0_c0", 20
		)
		var base_work_effective: float = evaluator.calculate_effective_value(
			work, character, base_work_context
		)
		var full_work_effective: float = evaluator.calculate_effective_value(
			work, character, full_work_context
		)
		worst_work = minf(worst_work, full_work_effective)
		if base_work_effective >= work.success_threshold - 10.0:
			work_base_near_line += 1
		if full_work_effective >= work.success_threshold:
			work_reachable += 1
		var expected_work_skill: String = str(
			(_rules.player_context_rules["work_skill_by_occupation"] as Dictionary).get(
				character.occupation_id, ""
			)
		)
		if str(full_work_context.get("work_skill_id", "")) == expected_work_skill:
			work_skill_matched += 1
	_expect(study_reachable == 200, "200 个常规开局的最低能力满额学习均达到成功线（最差 %.2f）" % worst_study)
	_expect(work_base_near_line == 200, "200 个常规开局的本职工作基础条件均不低于成功线 10 点")
	_expect(work_reachable == 200, "200 个常规开局的本职工作满额投入均达到成功线（最差 %.2f）" % worst_work)
	_expect(work_skill_matched == 200, "本职工作对 200 个常规开局均读取职业匹配主能力")


func _test_standard_relationship_reachability() -> void:
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	var evaluator := ActionService.new(_rules, StableIdService.new())
	var definition: ActionDefinitionData = _map.data_set.actions.get(
		"action:build_relationship"
	) as ActionDefinitionData
	var join_definition: ActionDefinitionData = _map.data_set.actions.get(
		"action:join_organization"
	) as ActionDefinitionData
	var countries: Array[String] = [
		"country:loran_federation", "country:vesta_union",
	]
	var anchors_present: int = 0
	var base_reachable: int = 0
	var full_guaranteed: int = 0
	var worst_base: float = INF
	var worst_full: float = INF
	var organization_base_reachable: int = 0
	var organization_full_guaranteed: int = 0
	var organization_occupation_matched: int = 0
	var actual_join_completed: bool = false
	var worst_organization_base: float = INF
	var worst_organization_full: float = INF
	for seed_value: int in range(1, 201):
		var generator := CharacterGenerator.new(
			_map.data_set,
			config,
			DeterministicRandomService.new(seed_value),
			StableIdService.new()
		)
		var generated: CharacterGenerationResult = generator.generate_character(
			countries[(seed_value - 1) % countries.size()],
			CharacterGenerator.MODE_STANDARD
		)
		if not generated.is_success():
			continue
		var character: CharacterData = generated.character
		var society := SocietySimulationService.new()
		if not society.initialize(character, _map.data_set):
			continue
		var anchors: Array[RelationshipData] = society.relationships.get_for_character(
			character.id
		)
		if anchors.size() >= 1 and anchors.size() <= 2:
			anchors_present += 1
		var context_service := PlayerActionContextService.new(
			_rules, society, _map
		)
		var affordable_extra: int = mini(
			context_service.get_max_extra_funding(),
			maxi(
				int(character.current_status.get("wealth", 0))
				- context_service.get_base_funding_cost(definition),
				0
			)
		)
		var best_base: float = -INF
		var best_full: float = -INF
		for target_character_id: String in society.roster.get_living_ids(
			character.country_id
		):
			if target_character_id == character.id:
				continue
			if not context_service.get_target_validation_error(
				definition, character, target_character_id
			).is_empty():
				continue
			var base_context: Dictionary = context_service.build_context(
				definition, character, target_character_id, 0
			)
			var full_context: Dictionary = context_service.build_context(
				definition, character, target_character_id, affordable_extra
			)
			best_base = maxf(
				best_base,
				evaluator.calculate_effective_value(
					definition, character, base_context
				)
			)
			best_full = maxf(
				best_full,
				evaluator.calculate_effective_value(
					definition, character, full_context
				)
			)
		worst_base = minf(worst_base, best_base)
		worst_full = minf(worst_full, best_full)
		if best_base >= definition.success_threshold:
			base_reachable += 1
		if best_full >= definition.guaranteed_success_threshold:
			full_guaranteed += 1
		var best_organization_base: float = -INF
		var best_organization_full: float = -INF
		var best_organization_match: float = 0.0
		var best_organization_id: String = ""
		var join_affordable_extra: int = mini(
			context_service.get_max_extra_funding(),
			maxi(
				int(character.current_status.get("wealth", 0))
				- context_service.get_base_funding_cost(join_definition),
				0
			)
		)
		for organization_id: String in society.organizations.get_organization_ids():
			if not context_service.get_target_validation_error(
				join_definition, character, organization_id
			).is_empty():
				continue
			var organization_base_context: Dictionary = context_service.build_context(
				join_definition, character, organization_id, 0
			)
			var organization_full_context: Dictionary = context_service.build_context(
				join_definition, character, organization_id, join_affordable_extra
			)
			var organization_base: float = evaluator.calculate_effective_value(
				join_definition, character, organization_base_context
			)
			var organization_full: float = evaluator.calculate_effective_value(
				join_definition, character, organization_full_context
			)
			if organization_full > best_organization_full:
				best_organization_id = organization_id
				best_organization_base = organization_base
				best_organization_full = organization_full
				best_organization_match = float(
					organization_full_context.get("organization_match_bonus", 0.0)
				)
		worst_organization_base = minf(
			worst_organization_base, best_organization_base
		)
		worst_organization_full = minf(
			worst_organization_full, best_organization_full
		)
		if best_organization_base >= join_definition.success_threshold - 10.0:
			organization_base_reachable += 1
		if best_organization_full >= join_definition.guaranteed_success_threshold:
			organization_full_guaranteed += 1
		if best_organization_match >= 68.0:
			organization_occupation_matched += 1
		if seed_value == 1 and not best_organization_id.is_empty():
			var started: ActionStartResult = context_service.start_player_action(
				evaluator,
				join_definition,
				character,
				0,
				best_organization_id,
				join_affordable_extra
			)
			if started.is_success():
				evaluator.update_to_hour(
					started.action, join_definition, character, 10000
				)
				actual_join_completed = (
					started.action.status == ActionInstanceData.STATUS_COMPLETED
					and started.action.outcome_code != "failure"
					and society.apply_character_action_domain_effect(
						started.action,
						join_definition,
						character,
						_map
					)
					and society.organizations.get_position_id(
						character.id, best_organization_id
					).is_empty() == false
				)
	_expect(anchors_present == 200, "200 个常规开局均生成 1～2 条真实弱关系")
	_expect(base_reachable == 200, "200 个常规开局均有基础条件达到成功线的关系目标（最差 %.2f）" % worst_base)
	_expect(full_guaranteed == 200, "200 个常规开局均有实际财富满额投入达到保证线的关系目标（最差 %.2f）" % worst_full)
	_expect(organization_base_reachable == 200, "200 个常规开局均有基础条件不低于成功线 10 点的组织目标（最差 %.2f）" % worst_organization_base)
	_expect(organization_full_guaranteed == 200, "200 个常规开局均有实际财富满额投入达到保证线的组织目标（最差 %.2f）" % worst_organization_full)
	_expect(organization_occupation_matched == 200, "200 个常规开局的最佳组织均匹配国家、职业且入口有空位")
	_expect(actual_join_completed, "常规开局可用真实资金完成加入组织并获得入口职位")
	var labor_organizer: Dictionary = config.get_occupation("union_member")
	_expect(
		str(labor_organizer.get("name", "")) == "劳工组织者"
		and str(labor_organizer.get("position", "")) == "劳工联络员",
		"职业分类不再使用暗示正式组织成员身份的称谓"
	)

	var panel: ActionPanel = _view.find_child("ActionPanel", true, false) as ActionPanel
	_expect(
		panel != null and panel.prefill_action(definition.id),
		"正式行动面板可打开建立关系配置"
	)
	if panel != null:
		var sorted: bool = panel.target_option.item_count > 0
		var last_effective: float = INF
		for index: int in range(panel.target_option.item_count):
			var candidate_id: String = str(panel.target_option.get_item_metadata(index))
			var context: Dictionary = panel.context_service.build_context(
				definition,
				GameSessionService.player_character,
				candidate_id,
				0
			)
			var effective: float = panel.action_service.calculate_effective_value(
				definition, GameSessionService.player_character, context
			)
			if effective > last_effective + 0.0001:
				sorted = false
			last_effective = effective
		_expect(sorted, "人物目标按当前实际有效值从高到低排序")
		_expect(
			panel.target_option.item_count > 0
			and panel.target_id
			== str(panel.target_option.get_item_metadata(0)),
			"建立关系默认选择最容易接触的人物"
		)
		_expect(
			panel.prefill_action(join_definition.id),
			"正式行动面板可打开加入组织配置"
		)
		var organizations_sorted: bool = panel.target_option.item_count > 0
		var last_organization_effective: float = INF
		for index: int in range(panel.target_option.item_count):
			var organization_id: String = str(
				panel.target_option.get_item_metadata(index)
			)
			var organization_context: Dictionary = panel.context_service.build_context(
				join_definition,
				GameSessionService.player_character,
				organization_id,
				0
			)
			var organization_effective: float = (
				panel.action_service.calculate_effective_value(
					join_definition,
					GameSessionService.player_character,
					organization_context
				)
			)
			if organization_effective > last_organization_effective + 0.0001:
				organizations_sorted = false
			last_organization_effective = organization_effective
		_expect(organizations_sorted, "组织目标按当前实际有效值从高到低排序")
		_expect(
			panel.target_option.item_count > 0
			and panel.target_id
			== str(panel.target_option.get_item_metadata(0)),
			"加入组织默认选择当前最匹配的目标"
		)

	var player: CharacterData = GameSessionService.player_character
	var player_relationships: Array[RelationshipData] = (
		_society.relationships.get_for_character(player.id)
	)
	_expect(not player_relationships.is_empty(), "当前玩家开局具有可深化的弱关系")
	if player_relationships.is_empty():
		return
	var anchor: RelationshipData = player_relationships[0]
	var target_id: String = (
		anchor.character_b_id
		if anchor.character_a_id == player.id
		else anchor.character_a_id
	)
	var familiarity_before: float = anchor.familiarity
	for action_index: int in range(2):
		var relationship_action := ActionInstanceData.new()
		relationship_action.id = "action_instance:relationship_%d" % action_index
		relationship_action.definition_id = definition.id
		relationship_action.actor_character_id = player.id
		relationship_action.target_id = target_id
		relationship_action.status = ActionInstanceData.STATUS_COMPLETED
		relationship_action.completion_hour = 100 + action_index
		relationship_action.outcome_code = "success"
		_society.apply_action_domain_effect(
			relationship_action, definition, _map
		)
	_expect(
		anchor.familiarity >= familiarity_before + 0.159,
		"重复成功接触会加深同一条既有关系"
	)
	var total_familiarity_before: float = 0.0
	for relationship: RelationshipData in _society.relationships.get_for_character(
		player.id
	):
		total_familiarity_before += relationship.familiarity
	var work_definition: ActionDefinitionData = _map.data_set.actions.get(
		"action:perform_work"
	) as ActionDefinitionData
	var work_action := ActionInstanceData.new()
	work_action.id = "action_instance:work_contact"
	work_action.definition_id = work_definition.id
	work_action.actor_character_id = player.id
	work_action.status = ActionInstanceData.STATUS_COMPLETED
	work_action.completion_hour = 200
	work_action.outcome_code = "success"
	_expect(
		_society.apply_action_domain_effect(work_action, work_definition, _map),
		"完成本职工作会产生同事关系机会"
	)
	var total_familiarity_after: float = 0.0
	for relationship: RelationshipData in _society.relationships.get_for_character(
		player.id
	):
		total_familiarity_after += relationship.familiarity
	_expect(
		total_familiarity_after > total_familiarity_before,
		"工作机会会新建或深化一条同事关系"
	)


func _test_selectable_skill_growth() -> void:
	var player: CharacterData = GameSessionService.player_character
	var definition: ActionDefinitionData = _map.data_set.actions[
		"action:study_skill"
	] as ActionDefinitionData
	var selected_skill: String = "political_activity"
	player.skills[selected_skill] = 20
	player.skills[definition.primary_skill] = 37
	player.current_status["health"] = 100
	player.current_status["fatigue"] = 0
	player.current_status["stress"] = 0
	var original_selected: int = int(player.skills[selected_skill])
	var original_default: int = int(player.skills[definition.primary_skill])
	var service := ActionService.new(_rules, StableIdService.new())
	var context: Dictionary = _formula_context(definition, 20.0, selected_skill)
	var started: ActionStartResult = service.start_action(
		definition, player, 0, context
	)
	_expect(started.is_success(), "学习行动接受正式选择的技能")
	if not started.is_success():
		return
	service.update_to_hour(started.action, definition, player, 1000)
	_expect(
		int(player.skills[selected_skill]) > original_selected,
		"学习行动提高所选政治活动技能"
	)
	_expect(
		int(player.skills[definition.primary_skill]) == original_default,
		"选择其他技能时不再固定提高调查技能"
	)


func _test_practical_skill_growth() -> void:
	var player: CharacterData = GameSessionService.player_character
	var definition: ActionDefinitionData = _map.data_set.actions[
		"action:build_relationship"
	] as ActionDefinitionData
	player.skills[definition.primary_skill] = 25
	var before: int = int(player.skills[definition.primary_skill])
	var service := ActionService.new(_rules, StableIdService.new())
	var context: Dictionary = _formula_context(definition, 100.0)
	context["target_id"] = "character:practice_target"
	var started: ActionStartResult = service.start_action(
		definition, player, 0, context
	)
	_expect(started.is_success(), "非学习行动可建立实践成长测试")
	if not started.is_success():
		return
	service.update_to_hour(started.action, definition, player, 2000)
	_expect(
		int(player.skills[definition.primary_skill]) > before,
		"完成实际行动会提高该行动的主要技能"
	)


func _test_cross_seed_guaranteed_reachability() -> void:
	var service := ActionService.new(_rules, StableIdService.new())
	var action_ids: Array[String] = []
	for raw_id: Variant in _map.data_set.actions:
		action_ids.append(str(raw_id))
	action_ids.sort()
	var unreachable: Array[String] = []
	var sampled: int = 0
	for mode: String in [
		CharacterGenerator.MODE_STANDARD,
		CharacterGenerator.MODE_FULL_POPULATION,
	]:
		for seed_value: int in range(1, 501):
			var character: CharacterData = _make_character(seed_value, mode)
			if character == null:
				unreachable.append("generation:%s:%d" % [mode, seed_value])
				continue
			for raw_skill: Variant in character.skills:
				character.skills[raw_skill] = int(
					_rules.mastery_guarantee["skill_threshold"]
				)
			character.current_status["health"] = 100
			character.current_status["fatigue"] = 0
			character.current_status["stress"] = 0
			for action_id: String in action_ids:
				var definition: ActionDefinitionData = _map.data_set.actions[
					action_id
				] as ActionDefinitionData
				var context: Dictionary = _formula_context(
					definition,
					100.0,
					definition.primary_skill
				)
				var effective: float = service.calculate_effective_value(
					definition, character, context
				)
				if effective < definition.guaranteed_success_threshold:
					unreachable.append(
						"%s:%d:%s:%.2f<%.2f" % [
							mode,
							seed_value,
							action_id,
							effective,
							definition.guaranteed_success_threshold,
						]
					)
			sampled += 1
	_expect(sampled == 1000, "普通与完整人口模式共抽样 1000 个角色")
	_expect(
		unreachable.is_empty(),
		"角色通过训练、准备和资金可使全部核心行动达到保证线%s" % (
			"" if unreachable.is_empty() else "：" + ", ".join(unreachable.slice(0, mini(5, unreachable.size())))
		)
	)


func _test_authoritative_succession_reasons() -> void:
	var player: CharacterData = GameSessionService.player_character
	player.age = 30
	player.current_status["health"] = 100
	player.current_status["detained"] = false
	player.current_status["reputation"] = 50
	player.current_status.erase("disgraced")
	player.current_status.erase("succession_required")
	player.current_status.erase("succession_reason")
	for reason_id: String in [
		"death", "retirement", "long_imprisonment", "disgrace"
	]:
		_expect(
			not _society.succession.get_exit_reason_validation_error(
				player, reason_id
			).is_empty(),
			"年轻健康人物不能伪造退出原因：%s" % reason_id
		)
	_expect(
		_society.succession.get_exit_reason_validation_error(
			player, "voluntary"
		).is_empty(),
		"自愿退出仍是始终可选的正式退出路径"
	)
	player.age = int(_society.rules.lifecycle_rules["retirement_age"])
	_expect(
		_society.succession.get_exit_reason_validation_error(
			player, "retirement"
		).is_empty(),
		"达到退休年龄后退休原因变为合法"
	)


func _test_npc_elapsed_interval_uses_old_context() -> void:
	var character: CharacterData = _make_character(
		30201, CharacterGenerator.MODE_STANDARD
	)
	var definition: ActionDefinitionData = _map.data_set.actions[
		"action:study_skill"
	] as ActionDefinitionData
	var service := ActionService.new(_rules, StableIdService.new())
	var old_context: Dictionary = _formula_context(
		definition, 0.0, definition.primary_skill
	)
	var started: ActionStartResult = service.start_action(
		definition, character, 0, old_context
	)
	_expect(started.is_success(), "可建立 NPC 旧区间结算测试行动")
	if not started.is_success():
		return
	var action: ActionInstanceData = started.action
	var old_efficiency: float = action.current_efficiency
	var new_context: Dictionary = _formula_context(
		definition, 100.0, definition.primary_skill
	)
	new_context["settle_previous_interval"] = true
	new_context["boundary_invalid_reason"] = "目标在日边界失效"
	_expect(
		service.update_context(
			action, definition, character, action.last_update_hour, new_context
		),
		"NPC 可在边界登记新上下文而不重算旧区间"
	)
	service.update_to_hour(action, definition, character, 24)
	_expect(
		is_equal_approx(action.accumulated_work, old_efficiency * 24.0),
		"NPC 已经过的 24 小时按旧效率结算"
	)
	_expect(
		action.status == ActionInstanceData.STATUS_INTERRUPTED
		and action.last_update_hour == 24,
		"新失效条件只从日边界起中断行动"
	)


func _test_save_runtime_invariants() -> void:
	var save_service := GameSaveService.new()
	GameSessionService.current_action = null
	var baseline: Dictionary = save_service.build_snapshot(_clock, _map)
	_expect(not baseline.is_empty(), "可构建存档不变量测试快照")
	if baseline.is_empty():
		return

	var missing_ai: Dictionary = baseline.duplicate(true)
	var ai_states: Array = missing_ai["ai_states"] as Array
	if not ai_states.is_empty():
		ai_states.remove_at(0)
	var result: SaveOperationResult = save_service.restore_snapshot(
		missing_ai, _clock, _map
	)
	_expect(
		not result.success and result.message.contains("AI"),
		"缺少任一活跃 NPC 的 AI 状态时拒绝恢复"
	)

	var missing_seed: Dictionary = baseline.duplicate(true)
	var seeds: Dictionary = (
		missing_seed["characters"] as Dictionary
	)["activation_seeds"] as Dictionary
	if not seeds.is_empty():
		seeds.erase(seeds.keys()[0])
	result = save_service.restore_snapshot(missing_seed, _clock, _map)
	_expect(
		not result.success and result.message.contains("人物名册"),
		"人物激活种子缺失时拒绝恢复"
	)

	var over_limit: Dictionary = baseline.duplicate(true)
	var character_state: Dictionary = over_limit["characters"] as Dictionary
	var active: Array = character_state["active"] as Array
	var activation_seeds: Dictionary = character_state["activation_seeds"] as Dictionary
	var template: Dictionary = (active[0] as Dictionary).duplicate(true)
	var overflow_index: int = 0
	while active.size() <= _society.rules.active_character_limit:
		var record: Dictionary = template.duplicate(true)
		var character_id: String = "character:overflow_%03d" % overflow_index
		record["id"] = character_id
		record["is_active"] = true
		record["organization_ids"] = []
		record["relationship_ids"] = []
		active.append(record)
		activation_seeds[character_id] = 900000 + overflow_index
		overflow_index += 1
	result = save_service.restore_snapshot(over_limit, _clock, _map)
	_expect(
		not result.success and result.message.contains("上限"),
		"超过活跃人物上限的存档被拒绝"
	)

	var player: CharacterData = GameSessionService.player_character
	var study: ActionDefinitionData = _map.data_set.actions[
		"action:study_skill"
	] as ActionDefinitionData
	player.current_status["wealth"] = 100
	var context_service := PlayerActionContextService.new(
		_rules, _society, _map
	)
	var player_started: ActionStartResult = context_service.start_player_action(
		ActionService.new(_rules, GameSessionService.action_id_service),
		study,
		player,
		_clock.total_hours,
		"",
		0,
		study.primary_skill
	)
	_expect(player_started.is_success(), "可建立玩家行动 ID 唯一性测试")
	if not player_started.is_success():
		return
	GameSessionService.current_action = player_started.action
	var npc_id: String = _society.ai.get_ai_character_ids()[0]
	var npc: CharacterData = _society.roster.get_active(npc_id)
	npc.current_status["wealth"] = 100
	var npc_started: ActionStartResult = context_service.start_player_action(
		ActionService.new(_rules, GameSessionService.action_id_service),
		study,
		npc,
		_clock.total_hours,
		"",
		0,
		study.primary_skill
	)
	_expect(npc_started.is_success(), "可建立 NPC 行动 ID 唯一性测试")
	if npc_started.is_success():
		var state: AiStateData = _society.ai.get_state(npc_id)
		state.current_action_id = study.id
		state.current_action_record = npc_started.action.to_dict()
		var duplicate_id: Dictionary = save_service.build_snapshot(
			_clock, _map
		)
		var duplicate_ai_states: Array = duplicate_id["ai_states"] as Array
		for raw_state: Variant in duplicate_ai_states:
			if (
				raw_state is Dictionary
				and str((raw_state as Dictionary).get("character_id", "")) == npc_id
			):
				var record: Dictionary = (
					raw_state as Dictionary
				)["current_action_record"] as Dictionary
				record["id"] = player_started.action.id
		result = save_service.restore_snapshot(duplicate_id, _clock, _map)
		_expect(
			not result.success and result.message.contains("重复"),
			"玩家与 NPC 行动实例 ID 重复时拒绝恢复"
		)
		state.current_action_id = ""
		state.current_action_record = {}
	GameSessionService.current_action = null


func _formula_context(
	definition: ActionDefinitionData,
	value: float,
	study_skill_id: String = ""
) -> Dictionary:
	var permissions: Array[String] = []
	if not definition.position_permission_required.is_empty():
		permissions.append(definition.position_permission_required)
	return {
		"target_id": "",
		"study_skill_id": (
			study_skill_id if definition.category == "study_skill" else ""
		),
		"position_permissions": permissions,
		"organization_support": value,
		"relationship_support": value,
		"funding": value,
		"preparation": value,
		"target_resistance": 0.0,
		"boundary_invalid_reason": "",
		"settle_previous_interval": false,
		"funding_cost": 0,
		"funding_committed": false,
		"wealth_before_funding": 0,
	}


func _make_character(seed_value: int, mode: String) -> CharacterData:
	var world: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	if not world.is_success() or not config.is_valid():
		return null
	var generator := CharacterGenerator.new(
		world.data_set,
		config,
		DeterministicRandomService.new(seed_value),
		StableIdService.new()
	)
	var result: CharacterGenerationResult = generator.generate_character(
		"country:loran_federation", mode
	)
	return null if not result.is_success() else result.character


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		printerr("[FAIL] %s" % description)


func _finish() -> void:
	if _failures > 0:
		printerr(
			"CODEX AUDIT REGRESSION FAILED: %d/%d" % [
				_failures, _checks
			]
		)
		quit(1)
	else:
		print("CODEX AUDIT REGRESSION PASSED: %d checks" % _checks)
		quit(0)
