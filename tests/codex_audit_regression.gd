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
	var panel: ActionPanel = _view.get_node("ActionPanel") as ActionPanel
	var button: Button = panel.get_node("Margin/Root/BeginButton") as Button
	_expect(button != null, "开始行动按钮固定在滚动区外")
	var ancestor: Node = button.get_parent() if button != null else null
	var inside_scroll: bool = false
	while ancestor != null and ancestor != panel:
		if ancestor is ScrollContainer:
			inside_scroll = true
			break
		ancestor = ancestor.get_parent()
	_expect(not inside_scroll, "1280×720 下开始行动按钮不依赖滚动到页尾")


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
