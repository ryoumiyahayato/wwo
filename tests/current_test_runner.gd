extends "res://tests/test_runner.gd"
## Current default-branch entry for the historical M0-M9 suite.
## Overrides only fixtures whose assumptions were intentionally invalidated by
## authoritative succession constraints; all other historical checks remain inherited.


func _test_m7_exit_reasons() -> void:
	var fixture: Dictionary = _build_current_succession_fixture(41001)
	var player: CharacterData = fixture.get("player") as CharacterData
	var succession: SuccessionService = fixture.get("succession") as SuccessionService
	var society_rules: SocietyRulesConfig = fixture.get("society_rules") as SocietyRulesConfig
	_expect(player != null and succession != null and society_rules != null, "M7 当前退出原因夹具可建立")
	if player == null or succession == null or society_rules == null:
		return

	player.age = 30
	player.current_status["health"] = 100
	player.current_status["detained"] = false
	player.current_status["reputation"] = 50
	player.current_status.erase("disgraced")
	player.current_status.erase("succession_required")
	player.current_status.erase("succession_reason")
	for reason_id: String in ["death", "retirement", "long_imprisonment", "disgrace"]:
		_expect(
			not succession.get_exit_reason_validation_error(player, reason_id).is_empty(),
			"M7 健康年轻人物不能伪造退出原因：%s" % reason_id
		)
	_expect(
		succession.get_exit_reason_validation_error(player, "voluntary").is_empty(),
		"M7 自愿退出始终合法"
	)

	player.age = int(society_rules.lifecycle_rules["retirement_age"])
	_expect(
		succession.get_exit_reason_validation_error(player, "retirement").is_empty(),
		"M7 达到退休年龄后允许退休"
	)
	player.age = 30
	player.current_status["health"] = 0
	_expect(
		succession.get_exit_reason_validation_error(player, "death").is_empty(),
		"M7 健康归零后允许死亡退出"
	)
	player.current_status["health"] = 100
	player.current_status["detained"] = true
	_expect(
		succession.get_exit_reason_validation_error(player, "long_imprisonment").is_empty(),
		"M7 被拘禁后允许长期监禁退出"
	)
	player.current_status["detained"] = false
	player.current_status["reputation"] = int(
		(fixture["continuity_rules"] as ContinuityRulesConfig).exit_constraints[
			"disgrace_reputation_threshold"
		]
	)
	_expect(
		succession.get_exit_reason_validation_error(player, "disgrace").is_empty(),
		"M7 低声望后允许严重失势退出"
	)


func _test_m7_succession_and_partial_inheritance() -> void:
	var fixture: Dictionary = _build_current_succession_fixture(41002)
	var player: CharacterData = fixture.get("player") as CharacterData
	var roster: CharacterRosterService = fixture.get("roster") as CharacterRosterService
	var relationships: RelationshipService = fixture.get("relationships") as RelationshipService
	var succession: SuccessionService = fixture.get("succession") as SuccessionService
	var society_rules: SocietyRulesConfig = fixture.get("society_rules") as SocietyRulesConfig
	_expect(
		player != null
		and roster != null
		and relationships != null
		and succession != null
		and society_rules != null,
		"M7 当前继承夹具可建立"
	)
	if player == null or roster == null or relationships == null or succession == null or society_rules == null:
		return

	var candidates: Array[String] = roster.get_background_ids(player.country_id)
	_expect(not candidates.is_empty(), "M7 当前继承夹具有背景候选")
	if candidates.is_empty():
		return
	var successor_id: String = candidates[0]
	var relationship: RelationshipData = relationships.create_or_update(
		player.id,
		successor_id,
		0,
		{},
		"trusted_successor"
	)
	_expect(relationship != null, "M7 可建立真实继承关系")
	if relationship == null:
		return
	relationship.familiarity = 1.0
	relationship.trust = 1.0
	relationship.affinity = 1.0

	player.age = int(society_rules.lifecycle_rules["retirement_age"])
	player.current_status["wealth"] = 100
	player.current_status["reputation"] = 80
	player.current_status["intelligence_points"] = 60
	var result: SuccessionResult = succession.execute_succession(
		player.id, successor_id, "retirement", 24
	)
	_expect(result.is_success(), "M7 合法退休可完成事务式继承")
	if not result.is_success():
		return
	_expect(result.successor.id == successor_id, "M7 继承切换到所选真实候选")
	_expect(result.exited_record != null and result.exited_record.reason == "retirement", "M7 旧玩家进入退休历史")
	_expect(result.inherited_wealth == 70, "M7 退休按配置继承部分财富")
	_expect(result.inherited_reputation == 48, "M7 退休按配置继承部分声望")
	_expect(result.inherited_intelligence == 30, "M7 退休按配置继承部分情报")


func _build_current_succession_fixture(seed_value: int) -> Dictionary:
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	var generation: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	var society_rules := SocietyRulesConfig.new()
	var continuity_rules := ContinuityRulesConfig.new()
	if (
		not loaded.is_success()
		or not generation.is_valid()
		or society_rules.load_from_file() != OK
		or continuity_rules.load_from_file() != OK
	):
		return {}
	var generator := CharacterGenerator.new(
		loaded.data_set,
		generation,
		DeterministicRandomService.new(seed_value),
		StableIdService.new()
	)
	var generated: CharacterGenerationResult = generator.generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	if not generated.is_success():
		return {}
	var player: CharacterData = generated.character
	var roster := CharacterRosterService.new(
		loaded.data_set, generation, society_rules
	)
	if not roster.initialize_background_population() or not roster.register_player(player):
		return {}
	var organizations := OrganizationService.new(loaded.data_set.organizations)
	var relationships := RelationshipService.new(
		roster, society_rules.relationship_defaults, StableIdService.new()
	)
	var ai := SimpleAiService.new(roster, society_rules)
	var succession := SuccessionService.new(
		continuity_rules,
		roster,
		organizations,
		relationships,
		ai,
		society_rules
	)
	return {
		"player": player,
		"roster": roster,
		"organizations": organizations,
		"relationships": relationships,
		"ai": ai,
		"succession": succession,
		"society_rules": society_rules,
		"continuity_rules": continuity_rules,
	}
