extends SceneTree
## Behavioral regression for population, AI, economy, lifecycle, control and continuity.

var _checks: int = 0
var _failures: int = 0
var _view: Control
var _clock: SimulationClock
var _map: MapControlService
var _society: SocietySimulationService


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LogService.set_minimum_level(LogService.Level.ERROR)
	GameSessionService.clear()
	var player: CharacterData = _make_test_player()
	_expect(player != null, "可创建模拟质量测试人物")
	if player == null:
		_finish()
		return
	GameSessionService.set_player(player)
	var packed: Resource = load("res://scenes/map/strategic_map_view.tscn")
	_view = (packed as PackedScene).instantiate() as Control if packed is PackedScene else null
	_expect(_view != null, "战略地图可实例化")
	if _view == null:
		_finish()
		return
	get_root().add_child(_view)
	current_scene = _view
	await process_frame
	_clock = GameSessionService.world_clock
	_map = GameSessionService.world_map_service
	_society = GameSessionService.society_service
	_expect(_clock != null and _map != null and _society != null, "权威世界服务已建立")
	if _clock == null or _map == null or _society == null:
		_finish()
		return

	_test_population_sampling()
	_test_active_investment()
	_test_policy_jurisdiction()
	_test_organization_economy()
	_test_npc_long_action_and_relationship_bootstrap()
	_test_control_modifiers()
	_test_lifecycle()
	_test_succession_merge_and_membership_limit()
	await _test_profile_clock_continuity()

	GameSessionService.clear()
	_finish()


func _test_population_sampling() -> void:
	var country_population: Dictionary = {}
	var total_population: int = 0
	for raw_group: Variant in _map.data_set.population_groups.values():
		var group: PopulationGroupData = raw_group as PopulationGroupData
		var region: RegionData = _map.data_set.regions[group.region_id] as RegionData
		country_population[region.de_jure_country_id] = int(
			country_population.get(region.de_jure_country_id, 0)
		) + group.population_count
		total_population += group.population_count
	var character_counts: Dictionary = {}
	var farmer_total: int = 0
	var agricultural_farmers: int = 0
	for character_id: String in _society.roster.get_living_ids():
		if character_id == _society.roster.player_character_id:
			continue
		var character: Variant = _society.roster.get_public_character(character_id)
		character_counts[str(character.country_id)] = int(
			character_counts.get(str(character.country_id), 0)
		) + 1
		if str(character.occupation_id) == "farmer":
			farmer_total += 1
			if str(character.current_status.get("population_category", "")) == "agricultural":
				agricultural_farmers += 1
	var simulated_total: int = 0
	for raw_count: Variant in character_counts.values():
		simulated_total += int(raw_count)
	_expect(simulated_total == _society.rules.background_character_count, "人口抽样保持配置化世界人物总量")
	for raw_country_id: Variant in country_population:
		var country_id: String = str(raw_country_id)
		var expected_ratio: float = float(country_population[country_id]) / float(total_population)
		var actual_ratio: float = float(character_counts.get(country_id, 0)) / float(maxi(simulated_total, 1))
		_expect(absf(actual_ratio - expected_ratio) < 0.20, "背景人物国家分布接近真实人口权重：%s" % country_id)
	_expect(farmer_total > 0, "全人口抽样可生成农民职业")
	_expect(float(agricultural_farmers) / float(maxi(farmer_total, 1)) > 0.60, "农民主要来自农业人口群体")
	_expect(
		_society.roster.get_persistent_state() == _society.roster.get_persistent_state(),
		"人口抽样状态读取保持确定性"
	)


func _test_active_investment() -> void:
	var rules := ActionRulesConfig.new()
	_expect(rules.load_from_file() == OK, "主动投入行动规则可加载")
	var context_service := PlayerActionContextService.new(rules, _society, _map)
	var definition: ActionDefinitionData = _map.data_set.actions["action:study_skill"] as ActionDefinitionData
	var player: CharacterData = GameSessionService.player_character
	player.current_status["wealth"] = 500
	player.current_status["intelligence_points"] = 30
	var base_context: Dictionary = context_service.build_context(definition, player, "", 0)
	var invested_context: Dictionary = context_service.build_context(definition, player, "", 10)
	_expect(float(invested_context["preparation"]) > float(base_context["preparation"]), "额外投入实际提高行动准备度")
	_expect(float(invested_context["funding"]) > float(base_context["funding"]), "额外投入实际提高资金支持")
	var wealth_before: int = int(player.current_status["wealth"])
	var action_service := ActionService.new(rules, GameSessionService.action_id_service)
	var started: ActionStartResult = context_service.start_player_action(
		action_service, definition, player, _clock.total_hours, "", 10
	)
	_expect(started.is_success(), "玩家可通过正式入口提交额外投入")
	if started.is_success():
		var expected_cost: int = context_service.get_base_funding_cost(definition) + 10
		_expect(int(player.current_status["wealth"]) == wealth_before - expected_cost, "基础费用和额外投入一次性原子扣除")
		_expect(int(started.action.context["funding_cost"]) == expected_cost, "行动记录保存完整投入审计")
		_expect(bool(started.action.context["funding_committed"]), "正式行动记录资金已承诺")
	player.current_status["wealth"] = wealth_before


func _test_policy_jurisdiction() -> void:
	var rules := ActionRulesConfig.new()
	rules.load_from_file()
	var context_service := PlayerActionContextService.new(rules, _society, _map)
	var definition: ActionDefinitionData = _map.data_set.actions["action:promote_policy"] as ActionDefinitionData
	var player: CharacterData = GameSessionService.player_character
	var own_target: String = _first_unit_for_country(player.country_id)
	var foreign_target: String = _first_unit_for_country(_map.get_other_country_id(player.country_id))
	_expect(
		not context_service.get_target_validation_error(definition, player, own_target).is_empty(),
		"没有正式职位时不能推动地区政策"
	)
	var government_id: String = "organization:loran_government"
	if player.country_id == "country:vesta_union":
		government_id = "organization:vesta_government"
	_expect(_society.organizations.join_organization(player, government_id), "玩家可加入本国政府组织以测试辖区")
	_expect(_society.organizations.assign_position(player, government_id, "regional_official"), "玩家可获得地区政策职位")
	_expect(context_service.get_target_validation_error(definition, player, own_target).is_empty(), "政府地区职位可作用于本国地区")
	_expect(
		context_service.get_target_validation_error(definition, player, foreign_target).contains("本国"),
		"政策行动不能越过国家法理和实际控制边界"
	)


func _test_organization_economy() -> void:
	var organization_id: String = _society.organizations.get_organization_ids()[0]
	var organization: OrganizationData = _society.organizations.get_organization(organization_id)
	organization.resources = 10.0
	var before: float = organization.resources
	var changed: int = _society._apply_monthly_organization_income()
	_expect(changed > 0, "月度组织经济至少更新一个组织")
	_expect(organization.resources > before, "组织获得可持续月度收入")
	_expect(organization.resources <= float(_society.rules.organization_economy["resource_cap"]), "组织资源不超过配置上限")


func _test_npc_long_action_and_relationship_bootstrap() -> void:
	var npc_id: String = _society.ai.get_ai_character_ids()[0]
	var npc: CharacterData = _society.roster.get_active(npc_id)
	for raw_skill: Variant in npc.skills:
		npc.skills[raw_skill] = 100
	npc.current_status["wealth"] = 100
	npc.current_status["intelligence_points"] = 100
	var state: AiStateData = _society.ai.get_state(npc_id)
	state.current_action_record = {}
	state.current_action_id = "action:build_relationship"
	state.candidate_actions = [{"action_id": "action:build_relationship", "weight": 100.0}]
	var relationship_count_before: int = _society.relationships.get_for_character(npc_id).size()
	var wealth_before: int = int(npc.current_status["wealth"])
	_expect(_society._execute_ai_daily_actions() > 0, "NPC 可从有限候选开始正式长期行动")
	_expect(not state.current_action_record.is_empty(), "NPC 长期行动保存完整行动实例而非瞬时效果")
	_expect(_society.relationships.get_for_character(npc_id).size() == relationship_count_before, "建立关系行动开始时不会立即生成关系")
	var definition: ActionDefinitionData = _map.data_set.actions["action:build_relationship"] as ActionDefinitionData
	var context_service := PlayerActionContextService.new(_society._action_rules, _society, _map)
	_expect(int(npc.current_status["wealth"]) == wealth_before - context_service.get_base_funding_cost(definition), "NPC 支付与玩家相同的行动基础费用")
	var restored_state := AiStateData.from_dict(state.to_dict())
	_expect(restored_state.current_action_record == state.current_action_record, "NPC 进行中行动可随 AI 状态往返持久化")
	_clock.advance_hours(6 * 24)
	_expect(_society.relationships.get_for_character(npc_id).size() > relationship_count_before, "NPC 可从空关系网络主动建立第一条关系")
	_expect(not state.last_action_result.is_empty(), "NPC 调试状态记录长期行动结果")


func _test_control_modifiers() -> void:
	var world_before: Dictionary = _map.get_persistent_state()
	var attacking_country: String = GameSessionService.player_character.country_id
	_expect(
		_map.declare_war(
			[attacking_country, _map.get_other_country_id(attacking_country)],
			0,
			{
				attacking_country: "保卫边境",
				_map.get_other_country_id(attacking_country): "争夺边境",
			}
		),
		"控制倍率测试显式建立战争状态"
	)
	var target: ControlUnitData = _best_enemy_frontier_target(attacking_country)
	_expect(target != null, "存在用于控制倍率测试的敌方前线单元")
	if target == null:
		return
	var region: RegionData = _map.data_set.regions[target.region_id] as RegionData
	var defender_country: String = target.controller_country_id
	region.social_influence[attacking_country] = 0.5
	region.social_influence[defender_country] = 0.5
	var neutral_multiplier: float = _map.get_control_pressure_multiplier(target.id, attacking_country)
	region.social_influence[attacking_country] = 0.9
	region.social_influence[defender_country] = 0.1
	var supported_multiplier: float = _map.get_control_pressure_multiplier(target.id, attacking_country)
	_expect(supported_multiplier > neutral_multiplier, "地区社会支持提高同国控制压力")

	var rail_state: Dictionary = {}
	for neighbor_id: String in target.neighbor_ids:
		var neighbor: ControlUnitData = _map.get_unit(neighbor_id)
		rail_state[neighbor_id] = neighbor.railroad_neighbor_ids.duplicate()
		neighbor.railroad_neighbor_ids.erase(target.id)
	rail_state[target.id] = target.railroad_neighbor_ids.duplicate()
	target.railroad_neighbor_ids.clear()
	var no_rail_multiplier: float = _map.get_control_pressure_multiplier(target.id, attacking_country)
	var attacking_neighbor: ControlUnitData
	for neighbor_id: String in target.neighbor_ids:
		var neighbor: ControlUnitData = _map.get_unit(neighbor_id)
		if neighbor.controller_country_id == attacking_country:
			attacking_neighbor = neighbor
			break
	_expect(attacking_neighbor != null, "前线目标存在进攻方邻接单元")
	if attacking_neighbor != null:
		target.railroad_neighbor_ids.append(attacking_neighbor.id)
		attacking_neighbor.railroad_neighbor_ids.append(target.id)
		var rail_multiplier: float = _map.get_control_pressure_multiplier(target.id, attacking_country)
		_expect(rail_multiplier > no_rail_multiplier, "进攻铁路连接提高控制压力倍率")
	for raw_id: Variant in rail_state:
		var unit: ControlUnitData = _map.get_unit(str(raw_id))
		unit.railroad_neighbor_ids = DataRecordUtils.to_string_array(rail_state[raw_id])

	for neighbor_id: String in target.neighbor_ids:
		var neighbor: ControlUnitData = _map.get_unit(neighbor_id)
		_map.set_control_state(neighbor.id, attacking_country, 1.0, 0.0)
	_expect(_map.is_surrounded(target.id), "目标全部邻接被敌方控制时形成包围")
	var surrounded_multiplier: float = _map.get_control_pressure_multiplier(target.id, attacking_country)
	_expect(surrounded_multiplier > supported_multiplier, "包围和多方向进攻进一步提高控制压力")
	_map.restore_persistent_state(world_before)


func _test_lifecycle() -> void:
	var lifecycle: Dictionary = _society.rules.lifecycle_rules
	var player: CharacterData = GameSessionService.player_character
	var npc_id: String = _society.ai.get_ai_character_ids()[0]
	var npc: CharacterData = _society.roster.get_active(npc_id)
	var background_id: String = _society.roster.get_background_ids(player.country_id)[0]
	var background: BackgroundCharacterData = _society.roster.get_background(background_id)
	player.age = int(lifecycle["retirement_age"]) - 1
	npc.age = int(lifecycle["retirement_age"]) - 1
	background.age = int(lifecycle["background_exit_age"]) - 1
	player.current_status["health"] = 100
	npc.current_status["health"] = 100
	background.current_status["health"] = 100
	var total_before: int = _society.roster.get_total_character_count()
	var exits: int = _society._run_annual_lifecycle()
	_expect(player.age == int(lifecycle["retirement_age"]), "年度生命周期自然增加玩家年龄")
	_expect(bool(player.current_status.get("succession_required", false)), "达到退休年龄后玩家进入继承准备状态")
	_expect(_society.roster.get_exited(npc_id) != null, "活跃 NPC 达到退休年龄后退出活跃社会")
	_expect(_society.roster.get_exited(background_id) != null, "背景人物达到退出年龄后进入历史记录")
	_expect(exits >= 2, "年度生命周期报告自然退出数量")
	_expect(_society.roster.get_total_character_count() == total_before, "自然退出保留世界人物历史身份总数")
	_society._fill_vacant_leadership()


func _test_succession_merge_and_membership_limit() -> void:
	var old_player: CharacterData = GameSessionService.player_character
	var successor_id: String = _society.roster.get_background_ids(old_player.country_id)[0]
	var other_id: String = _society.roster.get_background_ids(old_player.country_id)[1]
	var successor: CharacterData = _society.promote_background(successor_id)
	_expect(successor != null, "继承关系合并测试候选可升级")
	if successor == null:
		return
	_set_relationship(_society.relationships.create_or_update(old_player.id, successor_id, _clock.total_hours), 1.0, 1.0, 1.0)
	_set_relationship(_society.relationships.create_or_update(old_player.id, other_id, _clock.total_hours), 0.8, 0.6, 0.6)
	_set_relationship(_society.relationships.create_or_update(successor_id, other_id, _clock.total_hours), 0.9, 0.8, 0.7)
	var union_id: String = "organization:loran_union"
	if old_player.country_id == "country:vesta_union":
		union_id = "organization:vesta_union"
	_society.organizations.join_organization(successor, union_id)
	for organization_id: String in _society.organizations.get_organization_ids():
		var organization: OrganizationData = _society.organizations.get_organization(organization_id)
		if organization.country_id == old_player.country_id and not organization.member_ids.has(old_player.id):
			_society.organizations.join_organization(old_player, organization_id)
	var result: SuccessionResult = _society.execute_player_succession(successor_id, "retirement", _clock.total_hours)
	_expect(result.is_success(), "高强度真实关系可完成退休继承")
	if not result.is_success():
		return
	var merged: RelationshipData = _society.relationships.get_between(successor_id, other_id)
	_expect(merged.trust >= 0.8 and merged.affinity >= 0.7, "继承关系与继承者原有关系合并而非覆盖")
	var maximum_new: int = int(_society.continuity_rules.candidate["maximum_inherited_organizations"])
	_expect(result.successor.organization_ids.has(union_id), "继承不删除继承者原有组织身份")
	_expect(result.successor.organization_ids.size() <= maximum_new + 1, "继承新增组织身份受配置上限约束")


func _test_profile_clock_continuity() -> void:
	_view.queue_free()
	await process_frame
	var packed: Resource = load("res://scenes/character/character_profile_view.tscn")
	var profile: Control = (packed as PackedScene).instantiate() as Control if packed is PackedScene else null
	_expect(profile != null, "人物页面可实例化")
	if profile == null:
		return
	get_root().add_child(profile)
	current_scene = profile
	await process_frame
	var runner: SimulationRunner = profile.get_node("SimulationRunner") as SimulationRunner
	_expect(runner != null and runner.clock == _clock, "人物页面复用同一权威世界时钟")
	profile.queue_free()
	await process_frame


func _first_unit_for_country(country_id: String) -> String:
	for unit_id: String in _map.get_sorted_unit_ids():
		var unit: ControlUnitData = _map.get_unit(unit_id)
		if unit.controller_country_id == country_id:
			return unit_id
	return ""


func _best_enemy_frontier_target(country_id: String) -> ControlUnitData:
	var candidates: Array[ControlUnitData] = []
	for unit_id: String in _map.get_sorted_unit_ids():
		var unit: ControlUnitData = _map.get_unit(unit_id)
		if unit.controller_country_id != country_id and _map.is_valid_control_support_target(unit_id, country_id):
			candidates.append(unit)
	candidates.sort_custom(func(a: ControlUnitData, b: ControlUnitData) -> bool:
		return a.id < b.id if a.neighbor_ids.size() == b.neighbor_ids.size() else a.neighbor_ids.size() > b.neighbor_ids.size()
	)
	return null if candidates.is_empty() else candidates[0]


func _set_relationship(
	relationship: RelationshipData,
	familiarity: float,
	trust: float,
	affinity: float
) -> void:
	if relationship == null:
		return
	relationship.familiarity = familiarity
	relationship.trust = trust
	relationship.affinity = affinity


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
		printerr("SIMULATION QUALITY REGRESSION FAILED: %d/%d" % [_failures, _checks])
		quit(1)
	else:
		print("SIMULATION QUALITY REGRESSION PASSED: %d checks" % _checks)
		quit(0)
