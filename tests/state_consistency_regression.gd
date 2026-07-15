extends SceneTree
## Regression coverage for authoritative state consistency repairs.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可创建状态一致性测试人物")
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

	_test_background_core_continuity(society)
	_test_atomic_organization_join(map_service)
	_test_atomic_action_funding(society, map_service, clock)
	_test_action_dependency_revalidation(society, map_service, clock)
	_test_domain_failure_replaces_generic_success(society, map_service, clock)
	_test_authoritative_action_save_validation(society, map_service, clock)
	_test_succession_rollback(society, clock)
	_test_succession_at_active_limit(society, clock)

	GameSessionService.clear()
	_finish()


func _test_background_core_continuity(society: SocietySimulationService) -> void:
	var ids: Array[String] = society.roster.get_background_ids()
	_expect(not ids.is_empty(), "存在可用于层级切换的背景人物")
	if ids.is_empty():
		return
	var character_id: String = ids.back()
	var active: CharacterData = society.promote_background(character_id)
	_expect(active != null, "背景人物可升级为活跃人物")
	if active == null:
		return
	active.skills["administration"] = 97
	active.tendencies["government_support"] = -73
	active.hidden_aptitudes["learning"] = 91
	var demoted: BackgroundCharacterData = society.demote_active(character_id)
	_expect(demoted != null, "非领导活跃人物可降级")
	if demoted == null:
		return
	var restored: CharacterData = society.promote_background(character_id)
	_expect(restored != null, "降级人物可再次升级")
	if restored == null:
		return
	_expect(int(restored.skills.get("administration", -1)) == 97, "人物技能跨降级保持连续")
	_expect(int(restored.tendencies.get("government_support", 0)) == -73, "人物真实倾向跨降级保持连续")
	_expect(int(restored.hidden_aptitudes.get("learning", -1)) == 91, "人物隐藏资质跨降级保持连续")


func _test_atomic_organization_join(map_service: MapControlService) -> void:
	var service := OrganizationService.new(map_service.data_set.organizations)
	var organization: OrganizationData = service.get_organization("organization:loran_government")
	_expect(organization != null, "组织原子性测试目标存在")
	if organization == null:
		return
	var entry_id: String = str(organization.position_structure.get("entry_position", ""))
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	var entry: Dictionary = positions.get(entry_id, {}) as Dictionary
	var slots: int = int(entry.get("slots", 0))
	var all_joined: bool = true
	for index: int in range(slots):
		var member := CharacterData.new()
		member.id = "character:atomic_member_%03d" % index
		member.country_id = organization.country_id
		member.organization_ids = []
		member.relationship_ids = []
		if not service.join_organization(member, organization.id):
			all_joined = false
			break
	_expect(all_joined, "全部入口职位空缺均可原子加入组织")
	var rejected := CharacterData.new()
	rejected.id = "character:atomic_rejected"
	rejected.country_id = organization.country_id
	rejected.organization_ids = []
	rejected.relationship_ids = []
	_expect(not service.join_organization(rejected, organization.id), "入口职位满员时拒绝加入组织")
	_expect(not organization.member_ids.has(rejected.id), "加入失败不会留下幽灵成员")
	_expect(not rejected.organization_ids.has(organization.id), "加入失败不会污染人物组织索引")


func _test_atomic_action_funding(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var definition: ActionDefinitionData = map_service.data_set.actions["action:study_skill"] as ActionDefinitionData
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var context := PlayerActionContextService.new(rules, society, map_service)
	var service := ActionService.new(rules, GameSessionService.action_id_service)
	var player: CharacterData = GameSessionService.player_character
	var wealth_before: int = int(player.current_status.get("wealth", 0))
	var health_before: int = int(player.current_status.get("health", 100))
	player.current_status["health"] = 0
	var result: ActionStartResult = context.start_player_action(
		service, definition, player, clock.total_hours, ""
	)
	_expect(not result.is_success(), "人物状态阻止行动时创建失败")
	_expect(int(player.current_status.get("wealth", 0)) == wealth_before, "行动创建失败会回滚已扣费用")
	player.current_status["health"] = health_before


func _test_action_dependency_revalidation(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var organization_id: String = "organization:loran_union"
	var organization: OrganizationData = society.organizations.get_organization(organization_id)
	if organization == null or organization.member_ids.has(GameSessionService.player_character.id):
		organization_id = "organization:loran_enterprise"
		organization = society.organizations.get_organization(organization_id)
	_expect(organization != null and not organization.member_ids.has(GameSessionService.player_character.id), "存在尚未加入的本国组织")
	if organization == null or organization.member_ids.has(GameSessionService.player_character.id):
		return
	var definition: ActionDefinitionData = map_service.data_set.actions["action:join_organization"] as ActionDefinitionData
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var context := PlayerActionContextService.new(rules, society, map_service)
	var service := ActionService.new(rules, GameSessionService.action_id_service)
	var started: ActionStartResult = context.start_player_action(
		service,
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		organization_id
	)
	_expect(started.is_success(), "可开始依赖重算测试行动")
	if not started.is_success():
		return
	GameSessionService.current_action = started.action
	_expect(society.organizations.join_organization(GameSessionService.player_character, organization_id), "外部权威状态可以先改变目标资格")
	clock.advance_hours(1)
	_expect(started.action.status == ActionInstanceData.STATUS_INTERRUPTED, "目标资格变化会在下一权威小时中断行动")
	_expect(is_zero_approx(started.action.accumulated_work), "权威依赖失效的小时不增加进度")
	GameSessionService.current_action = null
	society.organizations.leave_organization(GameSessionService.player_character, organization_id)


func _test_domain_failure_replaces_generic_success(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var definition: ActionDefinitionData = map_service.data_set.actions["action:promote_policy"] as ActionDefinitionData
	var unit: ControlUnitData = map_service.get_unit("control:r3_c4")
	var region: RegionData = map_service.data_set.regions[unit.region_id] as RegionData
	var influence_before: Dictionary = region.social_influence.duplicate(true)
	region.social_influence[GameSessionService.player_character.country_id] = 1.0
	region.social_influence[map_service.get_other_country_id(GameSessionService.player_character.country_id)] = 0.0
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var service := ActionService.new(rules, GameSessionService.action_id_service)
	var context: Dictionary = {
		"target_id": unit.id,
		"position_permissions": [definition.position_permission_required],
		"organization_support": 100.0,
		"relationship_support": 100.0,
		"funding": 100.0,
		"preparation": 100.0,
		"target_resistance": 0.0,
	}
	var started: ActionStartResult = service.start_action(
		definition, GameSessionService.player_character, clock.total_hours, context
	)
	_expect(started.is_success(), "可创建领域失败结算测试行动")
	if not started.is_success():
		region.social_influence = influence_before
		return
	var player: CharacterData = GameSessionService.player_character
	var skill_before: int = int(player.skills.get(definition.primary_skill, 0))
	var reputation_before: int = int(player.current_status.get("reputation", 0))
	service.update_to_hour(
		started.action, definition, player, clock.total_hours + 100000, map_service
	)
	_expect(started.action.status == ActionInstanceData.STATUS_COMPLETED, "测试行动达到数值成功结算")
	var applied: bool = society.apply_action_domain_effect(started.action, definition, map_service)
	_expect(not applied and started.action.outcome_code == "failure", "领域无变化会把数值成功转换为失败")
	var expected_skill: int = clampi(
		skill_before + int(definition.failure_result.get("skill_delta", 0)), 0, 100
	)
	var expected_reputation: int = maxi(
		reputation_before + int(definition.failure_result.get("reputation_delta", 0)), 0
	)
	_expect(int(player.skills.get(definition.primary_skill, 0)) == expected_skill, "领域失败不会保留成功技能奖励")
	_expect(int(player.current_status.get("reputation", 0)) == expected_reputation, "领域失败不会保留成功声望奖励")
	region.social_influence = influence_before


func _test_authoritative_action_save_validation(
	society: SocietySimulationService,
	map_service: MapControlService,
	clock: SimulationClock
) -> void:
	var target_ids: Array[String] = society.roster.get_background_ids()
	_expect(not target_ids.is_empty(), "存在行动存档验证目标")
	if target_ids.is_empty():
		return
	var definition: ActionDefinitionData = map_service.data_set.actions["action:build_relationship"] as ActionDefinitionData
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var context := PlayerActionContextService.new(rules, society, map_service)
	var service := ActionService.new(rules, GameSessionService.action_id_service)
	var started: ActionStartResult = context.start_player_action(
		service,
		definition,
		GameSessionService.player_character,
		clock.total_hours,
		target_ids[0]
	)
	_expect(started.is_success(), "可创建权威存档验证行动")
	if not started.is_success():
		return
	GameSessionService.current_action = started.action
	var snapshot: Dictionary = GameSaveService.new().build_snapshot(clock, map_service)
	var action_record: Dictionary = snapshot["current_action"] as Dictionary
	var stored_context: Dictionary = action_record["context"] as Dictionary
	stored_context["organization_support"] = minf(
		float(stored_context["organization_support"]) + 1.0, 100.0
	)
	var result: SaveOperationResult = GameSaveService.new().restore_snapshot(
		snapshot, clock, map_service
	)
	_expect(not result.success and result.message.contains("权威状态"), "篡改行动支持值的存档被权威状态校验拒绝")
	GameSessionService.current_action = null


func _test_succession_rollback(
	society: SocietySimulationService,
	clock: SimulationClock
) -> void:
	var candidate_ids: Array[String] = society.roster.get_background_ids(GameSessionService.player_character.country_id)
	_expect(not candidate_ids.is_empty(), "存在继承回滚测试候选")
	if candidate_ids.is_empty():
		return
	var candidate_id: String = candidate_ids[0]
	society.relationships.create_or_update(
		GameSessionService.player_character.id,
		candidate_id,
		clock.total_hours,
		{"familiarity": 1.0, "trust": 1.0, "affinity": 1.0},
		"succession_test"
	)
	GameSessionService.player_character.age = int(
		society.rules.lifecycle_rules["retirement_age"]
	)
	var roster_before: Dictionary = society.roster.get_persistent_state()
	var organizations_before: Array[Dictionary] = society.organizations.get_persistent_state()
	var relationships_before: Dictionary = society.relationships.get_persistent_state()
	var ai_before: Array[Dictionary] = society.ai.get_persistent_state()
	var player_id_before: String = GameSessionService.player_character.id
	var original_limit: int = society.rules.active_character_limit
	society.rules.active_character_limit = 0
	var result: SuccessionResult = society.execute_player_succession(
		candidate_id, "retirement", clock.total_hours
	)
	society.rules.active_character_limit = original_limit
	_expect(result.successor == null, "继承者无法升级时继承失败")
	_expect(GameSessionService.player_character.id == player_id_before, "继承失败恢复原玩家人物")
	_expect(society.roster.get_persistent_state() == roster_before, "继承失败恢复人物名册")
	_expect(society.organizations.get_persistent_state() == organizations_before, "继承失败恢复组织状态")
	_expect(society.relationships.get_persistent_state() == relationships_before, "继承失败恢复关系状态")
	_expect(society.ai.get_persistent_state() == ai_before, "继承失败恢复 AI 状态")


func _test_succession_at_active_limit(
	society: SocietySimulationService,
	clock: SimulationClock
) -> void:
	var candidate_ids: Array[String] = society.roster.get_background_ids(GameSessionService.player_character.country_id)
	_expect(not candidate_ids.is_empty(), "存在满活跃层继承候选")
	if candidate_ids.is_empty():
		return
	var candidate_id: String = candidate_ids.back()
	society.relationships.create_or_update(
		GameSessionService.player_character.id,
		candidate_id,
		clock.total_hours,
		{"familiarity": 1.0, "trust": 1.0, "affinity": 1.0},
		"succession_limit_test"
	)
	for background_id: String in society.roster.get_background_ids():
		if background_id == candidate_id:
			continue
		if society.roster.active_characters.size() >= society.rules.active_character_limit:
			break
		society.promote_background(background_id)
	_expect(society.roster.active_characters.size() == society.rules.active_character_limit, "继承前活跃人物达到配置上限")
	GameSessionService.player_character.age = int(
		society.rules.lifecycle_rules["retirement_age"]
	)
	var result: SuccessionResult = society.execute_player_succession(
		candidate_id, "retirement", clock.total_hours
	)
	_expect(result.successor != null and result.successor.id == candidate_id, "满活跃层时先释放旧玩家槽位再完成继承")
	_expect(society.roster.active_characters.size() <= society.rules.active_character_limit, "继承完成后活跃人物不超过上限")


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
	var result: CharacterGenerationResult = generator.generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	if not result.is_success():
		return null
	var player: CharacterData = result.character
	for raw_skill: Variant in player.skills:
		player.skills[raw_skill] = 100
	player.current_status["wealth"] = 500
	player.current_status["intelligence_points"] = 100
	player.current_status["detained"] = false
	return player


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		printerr("[FAIL] %s" % description)


func _finish() -> void:
	if _failures > 0:
		printerr("STATE CONSISTENCY REGRESSION FAILED: %d/%d" % [_failures, _checks])
		quit(1)
	else:
		print("STATE CONSISTENCY REGRESSION PASSED: %d checks" % _checks)
		quit(0)
