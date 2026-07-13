extends SceneTree

const PROBE_PATH: String = "user://saves/p0_r1_logic_probe.json"
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_probe()
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可创建逻辑回归人物")
	if player == null:
		_finish()
		return
	GameSessionService.set_player(player)
	var packed: Resource = load("res://scenes/map/strategic_map_view.tscn")
	var view: Control = (packed as PackedScene).instantiate() as Control if packed is PackedScene else null
	_expect(view != null, "战略地图可实例化")
	if view == null:
		_finish()
		return
	get_root().add_child(view)
	current_scene = view
	await process_frame
	var clock: SimulationClock = GameSessionService.world_clock
	var map_service: MapControlService = GameSessionService.world_map_service
	var society: SocietySimulationService = GameSessionService.society_service
	_expect(clock != null and map_service != null and society != null, "权威世界服务已建立")
	if clock == null or map_service == null or society == null:
		_finish()
		return
	if GameSessionService.world_autosave != null:
		GameSessionService.world_autosave.autosave_path = PROBE_PATH

	_test_occupational_position_is_valid(society)
	_test_policy_domain_effect(society, map_service, clock)
	_test_hourly_action_and_autosave(society, map_service, clock)
	_test_interruption_before_progress(society, map_service, clock)
	_test_background_investigation(society, map_service, clock)
	_test_position_vacancy(society, map_service)
	_test_frontline_rules(map_service, player.country_id)
	_test_save_consistency(map_service, clock, society)

	GameSessionService.clear()
	_finish()


func _test_occupational_position_is_valid(society: SocietySimulationService) -> void:
	_expect(
		SocialSaveValidator.new().validate(society).is_empty(),
		"未加入组织的人物职业称谓不会被误判为组织职位损坏"
	)


func _test_policy_domain_effect(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var definition: ActionDefinitionData = map_service.data_set.actions["action:promote_policy"] as ActionDefinitionData
	var unit: ControlUnitData = map_service.get_unit("control:r3_c4")
	var region: RegionData = map_service.data_set.regions[unit.region_id] as RegionData
	var before: Dictionary = region.social_influence.duplicate(true)
	var action: ActionInstanceData = _completed_action(definition, unit.id, clock.total_hours)
	action.applied_effects = definition.success_result.duplicate(true)
	var applied: bool = society.apply_action_domain_effect(action, definition, map_service)
	_expect(applied, "政策领域结果实际执行")
	_expect(action.domain_effect_applied, "政策结果在执行后标记为已消费")
	_expect(region.social_influence != before, "政策行动改变地区社会影响")
	region.social_influence = before


func _test_hourly_action_and_autosave(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var definition: ActionDefinitionData = map_service.data_set.actions["action:study_skill"] as ActionDefinitionData
	var rules := ActionRulesConfig.new()
	_expect(rules.load_from_file() == OK, "行动规则可加载")
	var context := PlayerActionContextService.new(rules, society, map_service)
	var service := ActionService.new(rules, GameSessionService.action_id_service)
	var started: ActionStartResult = service.start_action(
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		context.build_context(definition, GameSessionService.player_character, "")
	)
	_expect(started.is_success(), "可开始小时推进测试行动")
	if not started.is_success():
		return
	GameSessionService.current_action = started.action
	var hours_to_week: int = SimulationClock.HOURS_PER_WEEK - (clock.total_hours % SimulationClock.HOURS_PER_WEEK)
	clock.advance_hours(hours_to_week)
	_expect(started.action.status == ActionInstanceData.STATUS_COMPLETED, "批量推进仍按小时完成行动")
	_expect(started.action.last_update_hour <= clock.total_hours, "行动更新时间不晚于权威时间")
	var loaded: SaveOperationResult = GameSaveService.new().load_from_path(PROBE_PATH)
	_expect(loaded.success, "周边界生成隔离自动存档")
	if loaded.success and loaded.snapshot["current_action"] is Dictionary:
		var saved_action: Dictionary = loaded.snapshot["current_action"] as Dictionary
		_expect(str(saved_action.get("status", "")) == ActionInstanceData.STATUS_COMPLETED, "自动档包含同小时已完成行动")
	GameSessionService.current_action = null


func _test_interruption_before_progress(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var definition: ActionDefinitionData = map_service.data_set.actions["action:study_skill"] as ActionDefinitionData
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var context := PlayerActionContextService.new(rules, society, map_service)
	var service := ActionService.new(rules, GameSessionService.action_id_service)
	var started: ActionStartResult = service.start_action(
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		context.build_context(definition, GameSessionService.player_character, "")
	)
	if not started.is_success():
		_expect(false, "可开始中断测试行动")
		return
	GameSessionService.current_action = started.action
	GameSessionService.player_character.current_status["detained"] = true
	clock.advance_hours(1)
	_expect(started.action.status == ActionInstanceData.STATUS_INTERRUPTED, "拘押在进度结算前中断行动")
	_expect(is_zero_approx(started.action.accumulated_work), "被中断小时不获得行动进度")
	GameSessionService.player_character.current_status["detained"] = false
	GameSessionService.current_action = null


func _test_background_investigation(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var background_ids: Array[String] = society.roster.get_background_ids()
	_expect(not background_ids.is_empty(), "存在背景人物调查目标")
	if background_ids.is_empty():
		return
	var definition: ActionDefinitionData = map_service.data_set.actions["action:investigate_character"] as ActionDefinitionData
	var action: ActionInstanceData = _completed_action(definition, background_ids[0], clock.total_hours)
	action.applied_effects = definition.success_result.duplicate(true)
	var applied: bool = society.apply_action_domain_effect(action, definition, map_service)
	var dossiers: Variant = GameSessionService.player_character.current_status.get("investigation_dossiers", {})
	_expect(applied and dossiers is Dictionary, "背景人物调查生成正式档案")
	if dossiers is Dictionary:
		var dossier: Variant = (dossiers as Dictionary).get(background_ids[0], {})
		_expect(dossier is Dictionary and not ((dossier as Dictionary).get("tendencies", {}) as Dictionary).is_empty(), "背景人物档案包含可定性展示的倾向")


func _test_position_vacancy(
	society: SocietySimulationService,
	map_service: MapControlService
) -> void:
	var player: CharacterData = GameSessionService.player_character
	var organization_id: String = "organization:loran_government"
	var organization: OrganizationData = society.organizations.get_organization(organization_id)
	society.organizations.join_organization(player, organization_id)
	society.organizations.assign_position(player, organization_id, "regional_official")
	var definition: ActionDefinitionData = map_service.data_set.actions["action:seek_position"] as ActionDefinitionData
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var context := PlayerActionContextService.new(rules, society, map_service)
	var error: String = context.get_target_validation_error(definition, player, organization_id)
	_expect(error.contains("空缺职位"), "没有更高空位时不能开始争取职位")
	_expect(not organization.leader_character_id.is_empty(), "最高职位确由现任领导占用")


func _test_frontline_rules(map_service: MapControlService, country_id: String) -> void:
	var world_before: Dictionary = map_service.get_persistent_state()
	_expect(not map_service.is_valid_control_support_target("control:r0_c9", country_id), "远离本国控制区的敌方腹地不是合法目标")
	_expect(map_service.is_valid_control_support_target("control:r0_c5", country_id), "与本国接壤的敌方前线是合法目标")
	var target: ControlUnitData = map_service.get_unit("control:r0_c5")
	for _index: int in range(20):
		if target.controller_country_id == country_id:
			break
		map_service.apply_frontline_control_pressure(target.id, country_id, 1.0)
	_expect(target.controller_country_id == country_id, "持续前线压力可以触发控制易手")
	_expect(target.contested_level < map_service.rules.contested_threshold, "控制易手后进入巩固而非继续高度争夺")
	_expect(is_zero_approx(target.enemy_pressure), "控制易手后清除旧进攻方压力")
	map_service.restore_persistent_state(world_before)


func _test_save_consistency(
	map_service: MapControlService,
	clock: SimulationClock,
	society: SocietySimulationService
) -> void:
	GameSessionService.current_action = null
	var service := GameSaveService.new()
	var snapshot: Dictionary = service.build_snapshot(clock, map_service)
	var normal: SaveOperationResult = service.restore_snapshot(snapshot.duplicate(true), clock, map_service)
	_expect(normal.success, "正常职业人物存档可恢复")

	var wrong_player: Dictionary = snapshot.duplicate(true)
	(wrong_player["characters"] as Dictionary)["player_character_id"] = "character:other"
	var errors: Array[String] = service.validate_snapshot(wrong_player)
	_expect("; ".join(errors).contains("玩家 ID"), "顶层与名册玩家 ID 不一致被明确拒绝")

	var wrong_country: Dictionary = snapshot.duplicate(true)
	wrong_country["selected_country_id"] = map_service.get_other_country_id(GameSessionService.player_character.country_id)
	var result: SaveOperationResult = service.restore_snapshot(wrong_country, clock, map_service)
	_expect(not result.success and result.message.contains("人物国家"), "所选国家与玩家国家不一致被明确拒绝")

	var wrong_time: Dictionary = snapshot.duplicate(true)
	(wrong_time["game_time"] as Dictionary)["total_hours"] = clock.total_hours + 1
	result = service.restore_snapshot(wrong_time, clock, map_service)
	_expect(not result.success and result.message.contains("累计小时"), "日历与累计小时不一致被明确拒绝")

	var wrong_influence: Dictionary = snapshot.duplicate(true)
	var regions: Dictionary = (wrong_influence["world"] as Dictionary)["regions"] as Dictionary
	var first_region: Dictionary = regions[regions.keys()[0]] as Dictionary
	var influence: Dictionary = first_region["social_influence"] as Dictionary
	influence.erase(influence.keys()[0])
	result = service.restore_snapshot(wrong_influence, clock, map_service)
	_expect(not result.success and result.message.contains("地图状态"), "地区影响缺少国家键时拒绝恢复")

	var other_id: String = society.roster.get_background_ids()[0]
	society.create_player_relationship(other_id, clock.total_hours)
	var relationship_snapshot: Dictionary = service.build_snapshot(clock, map_service)
	((relationship_snapshot["relationships"] as Dictionary)["id_state"] as Dictionary)["relationship"] = 0
	result = service.restore_snapshot(relationship_snapshot, clock, map_service)
	_expect(not result.success and result.message.contains("关系 ID"), "关系计数器落后于记录时拒绝恢复")


func _completed_action(
	definition: ActionDefinitionData,
	target_id: String,
	current_hour: int
) -> ActionInstanceData:
	var action := ActionInstanceData.new()
	action.id = "action_instance:99999999"
	action.definition_id = definition.id
	action.actor_character_id = GameSessionService.player_character.id
	action.target_id = target_id
	action.start_hour = current_hour
	action.last_update_hour = current_hour
	action.completion_hour = current_hour
	action.total_work = definition.total_work
	action.accumulated_work = definition.total_work
	action.status = ActionInstanceData.STATUS_COMPLETED
	action.estimated_completion_hour = current_hour
	action.outcome_code = "success"
	action.result_applied = true
	action.result_description = "测试完成"
	return action


func _make_test_player() -> CharacterData:
	var world: CoreDataLoadResult = CoreDataLoader.new().load_from_file("res://data/world/demo_world.json")
	var config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	if not world.is_success() or not config.is_valid():
		return null
	var generator := CharacterGenerator.new(world.data_set, config, DeterministicRandomService.new(19000101), StableIdService.new())
	var result: CharacterGenerationResult = generator.generate_character("country:loran_federation", CharacterGenerator.MODE_STANDARD)
	if not result.is_success():
		return null
	var player: CharacterData = result.character
	for raw_skill: Variant in player.skills:
		player.skills[raw_skill] = 100
	player.current_status["wealth"] = 500
	player.current_status["intelligence_points"] = 100
	player.current_status["detained"] = false
	return player


func _cleanup_probe() -> void:
	var absolute: String = ProjectSettings.globalize_path(PROBE_PATH)
	for candidate: String in [absolute, absolute + ".tmp", absolute + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		printerr("[FAIL] %s" % description)


func _finish() -> void:
	_cleanup_probe()
	if _failures > 0:
		printerr("P0-R1 LOGIC REGRESSION FAILED: %d/%d" % [_failures, _checks])
		quit(1)
	else:
		print("P0-R1 LOGIC REGRESSION PASSED: %d checks" % _checks)
		quit(0)
