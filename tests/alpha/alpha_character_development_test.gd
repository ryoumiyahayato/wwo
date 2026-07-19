extends SceneTree
## Alpha D-stage creation, aptitude, skill, experience, qualification and delegation.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var alpha_config := AlphaConfig.new()
	test.equal(alpha_config.load_all(), OK, "Alpha 人物和预设配置可载入")
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	test.expect(loaded.is_success(), "人物创建复用既有两国八区核心数据")
	if not loaded.is_success():
		test.finish(self, "Alpha character and development")
		return
	var generation := CharacterGenerationConfig.load_from_file()
	test.expect(generation.is_valid(), "既有人物生成配置有效")
	var rules := SocietyRulesConfig.new()
	test.equal(rules.load_from_file(), OK, "既有分层人物规则有效")
	var economy := AlphaEconomyService.new()
	test.expect(economy.configure(alpha_config), "人物连接统一经济权威")
	var labor := AlphaLaborService.new()
	test.expect(labor.configure(alpha_config, economy), "人物连接统一劳动权威")
	var characters := AlphaCharacterService.new()
	test.expect(
		characters.configure(
			loaded.data_set, generation, alpha_config, economy, labor
		),
		"Alpha 人物服务复用 CharacterData 与生成器"
	)
	test.equal(
		(alpha_config.presets().get("creation_modes", []) as Array).size(),
		4,
		"人物创建提供四种模式"
	)
	test.equal(
		(alpha_config.presets().get("categories", []) as Array).size(),
		7,
		"分类随机提供七类背景"
	)
	for mode: String in AlphaCharacterService.CREATION_MODES:
		var category: String = "professional" if mode in [
			"category_random", "custom_background"
		] else ""
		var created: Dictionary = characters.create_character(
			"country:loran_federation",
			"region:loran_dawnbay",
			"city:dawnharbor",
			mode,
			category,
			1000 + AlphaCharacterService.CREATION_MODES.find(mode),
			{
				"name": "自定义人物",
				"summary": "成年专业履历",
				"skill_adjustments": {"finance": 5},
			}
		)
		test.expect(bool(created.get("success", false)), "创建模式可用：%s" % mode)
	for category: String in AlphaCharacterService.CATEGORY_MAP:
		var categorized: Dictionary = characters.create_character(
			"country:vesta_union",
			"region:vesta_silverfield",
			"city:starhold",
			"category_random",
			category,
			2000 + AlphaCharacterService.CATEGORY_MAP.keys().find(category)
		)
		test.expect(bool(categorized.get("success", false)), "分类随机可用：%s" % category)
		var categorized_character: CharacterData = (
			categorized.get("data", {}) as Dictionary
		).get("character") as CharacterData
		test.expect(
			categorized_character.domain_experience.has(category),
			"分类只保证相关经历：%s" % category
		)
	var deterministic_a: Dictionary = characters.create_character(
		"country:loran_federation",
		"region:loran_riverback",
		"city:ironford",
		"full_random",
		"",
		314159
	)
	var deterministic_b: Dictionary = characters.create_character(
		"country:loran_federation",
		"region:loran_riverback",
		"city:ironford",
		"full_random",
		"",
		314159
	)
	var character_a: CharacterData = (
		deterministic_a.get("data", {}) as Dictionary
	).get("character") as CharacterData
	var character_b: CharacterData = (
		deterministic_b.get("data", {}) as Dictionary
	).get("character") as CharacterData
	test.equal(
		character_a.hidden_aptitudes,
		character_b.hidden_aptitudes,
		"隐藏资质由确定性种子生成"
	)
	var preset_result: Dictionary = characters.create_from_preset(
		"preset:partner_supported"
	)
	test.expect(bool(preset_result.get("success", false)), "正式玩家预设可直接建立")
	var player: CharacterData = (preset_result.get("data", {}) as Dictionary).get(
		"character"
	) as CharacterData
	test.expect(player.age >= 18, "玩家控制已有成年履历的人物")
	test.expect(not player.background_history.is_empty(), "人物保存出身和既往经历")
	test.expect(not player.domain_experience.is_empty(), "人物保存领域经验")
	test.expect(player.drives.size() == 5, "人物保存五项基础驱动力")
	test.expect(not player.current_agendas.is_empty(), "人物最多保存少量当前议程")
	var public_view: Dictionary = characters.public_character_view(player)
	test.expect(
		not public_view.has("hidden_aptitudes"),
		"普通人物界面不泄露精确隐藏资质"
	)
	test.expect(
		characters.public_character_view(player, true).has("hidden_aptitudes"),
		"开发模式可查看精确隐藏资质"
	)
	player.skills["finance"] = 18
	player.domain_experience["trade"] = 8
	player.hidden_aptitudes["reasoning"] = 25
	player.hidden_aptitudes["learning"] = 30
	var low_assessment: Dictionary = characters.assess_action(
		player,
		"operate_enterprise",
		"finance",
		"trade",
		72,
		24,
		5000
	)
	test.expect(bool(low_assessment.get("can_attempt", false)), "低能力人物仍可尝试经营")
	test.expect(
		int(low_assessment.get("error_risk", 0)) >= 50,
		"低技能和资质表现为正式错误风险"
	)
	test.expect(
		str(low_assessment.get("dependence", "")) == "assistance_advised",
		"低能力提高对他人帮助的依赖"
	)
	var qualification_assessment: Dictionary = characters.assess_action(
		player,
		"sign_audited_accounts",
		"finance",
		"trade",
		55,
		8,
		600,
		"bookkeeping"
	)
	test.expect(
		bool(qualification_assessment.get("institutionally_blocked", false)),
		"资格只限制现实制度要求的行为"
	)
	test.equal(
		(qualification_assessment.get("bypass_methods", []) as Array).size(),
		7,
		"资格限制可通过雇佣、签署、协助、伪造、行贿、非法进入或换制度处理"
	)
	var helper_result: Dictionary = characters.create_character(
		"country:loran_federation",
		"region:loran_dawnbay",
		"city:dawnharbor",
		"category_random",
		"professional",
		271828
	)
	var helper: CharacterData = (helper_result.get("data", {}) as Dictionary).get(
		"character"
	) as CharacterData
	helper.skills["finance"] = 82
	helper.hidden_aptitudes["reasoning"] = 78
	var assisted: Dictionary = characters.assess_action(
		player,
		"operate_enterprise",
		"finance",
		"trade",
		72,
		24,
		5000,
		"",
		helper
	)
	test.expect(
		int(assisted.get("method_reliability", 0))
		> int(low_assessment.get("method_reliability", 0)),
		"专业人物实际改善方法可靠性"
	)
	var low_estimate: Dictionary = characters.estimate_unknown_value(
		player, "fact:cash_runway", 1700, "finance", 70
	)
	var low_estimate_data: Dictionary = low_estimate.get("data", {}) as Dictionary
	player.skills["finance"] = 82
	player.hidden_aptitudes["reasoning"] = 80
	var high_estimate: Dictionary = characters.estimate_unknown_value(
		player, "fact:cash_runway", 1700, "finance", 70
	)
	var high_estimate_data: Dictionary = high_estimate.get("data", {}) as Dictionary
	test.expect(
		int(high_estimate_data.get("estimate_upper", 0))
		- int(high_estimate_data.get("estimate_lower", 0))
		< int(low_estimate_data.get("estimate_upper", 0))
		- int(low_estimate_data.get("estimate_lower", 0)),
		"能力更高时未知事实估计区间更窄"
	)
	test.expect(
		not high_estimate_data.has("objective_value"),
		"普通估计结果不泄露客观真实值"
	)
	test.expect(
		bool(economy.register_entity(
			"organization:course_provider", "organization", 5000
		).get("success", false)),
		"课程提供者具有正式账本账户"
	)
	var skill_before: int = int(player.skills.get("finance", 0))
	var module_access_before: bool = bool(
		characters.assess_action(
			player, "create_enterprise", "finance", "trade", 65, 24, 2000
		).get("can_attempt", false)
	)
	var plan_result: Dictionary = characters.schedule_development(
		"development:test:course",
		player,
		"finance",
		"formal_course",
		100,
		40,
		600,
		"location:dawnharbor:organization",
		"organization:course_provider",
		"",
		80,
		35
	)
	test.expect(bool(plan_result.get("success", false)), "个人发展保存时间、金钱、方法、地点和风险")
	var plan: Dictionary = (plan_result.get("data", {}) as Dictionary).get(
		"plan", {}
	) as Dictionary
	var plan_id: String = str(plan.get("plan_id", ""))
	test.expect(
		not str(plan.get("schedule_activity_id", "")).is_empty(),
		"个人发展具有正式日程活动 ID"
	)
	test.expect(
		bool(characters.settle_development(
			"development_settle:test:course", player, plan_id, 140, 40
		).get("success", false)),
		"个人发展按正式时间边界结算"
	)
	test.expect(
		int(player.skills.get("finance", 0)) > skill_before,
		"发展提高方法可靠性所用技能"
	)
	var module_access_after: bool = bool(
		characters.assess_action(
			player, "create_enterprise", "finance", "trade", 65, 24, 2000
		).get("can_attempt", false)
	)
	test.equal(
		module_access_after,
		module_access_before,
		"个人发展不解锁或隐藏整个经营模块"
	)
	player.skills["administration"] = 70
	player.hidden_aptitudes["reasoning"] = 70
	var exam_plan_result: Dictionary = characters.schedule_development(
		"development:test:exam",
		player,
		"administration",
		"exam",
		200,
		8,
		200,
		"location:dawnharbor:government",
		"organization:course_provider",
		"",
		90,
		20,
		"civil_exam"
	)
	var exam_plan: Dictionary = (exam_plan_result.get("data", {}) as Dictionary).get(
		"plan", {}
	) as Dictionary
	test.expect(
		bool(characters.settle_development(
			"development_settle:test:exam",
			player,
			str(exam_plan.get("plan_id", "")),
			208,
			8
		).get("success", false)),
		"考试是发展方式而非模块解锁器"
	)
	test.expect("civil_exam" in player.qualifications, "通过考试取得正式资格")
	var invalid_depth: Dictionary = characters.create_authorization(
		"authorization:test:recursive",
		player.id,
		helper.id,
		"",
		["trade"],
		1000,
		2,
		300,
		400,
		2
	)
	test.expect(
		not bool(invalid_depth.get("success", false)),
		"代理授权拒绝无限递归层级"
	)
	var authorization_result: Dictionary = characters.create_authorization(
		"authorization:test:valid",
		player.id,
		helper.id,
		"",
		["trade", "contract_review"],
		1000,
		2,
		300,
		400
	)
	test.expect(bool(authorization_result.get("success", false)), "代理人在有限范围内获得授权")
	var authorization: Dictionary = (
		authorization_result.get("data", {}) as Dictionary
	).get("authorization", {}) as Dictionary
	test.expect(
		bool(characters.authorize_item(
			"authorization_item:test:valid",
			str(authorization.get("authorization_id", "")),
			"contract_review",
			"item:contract_review",
			200,
			320
		).get("success", false)),
		"代理事项受范围、预算、期限和并发约束"
	)
	var roster := CharacterRosterService.new(loaded.data_set, generation, rules)
	test.expect(roster.initialize_background_population(), "既有分层人物服务建立背景人口")
	test.equal(roster.background_characters.size(), 120, "背景人物数量为一百二十")
	test.expect(roster.register_player(player), "玩家进入同一正式人物名册")
	var promoted_id: String = roster.get_background_ids()[0]
	var promoted: CharacterData = roster.promote(promoted_id)
	test.expect(promoted != null, "背景人物可升级为高精度人物")
	promoted.domain_experience["alpha_test"] = 77
	var demoted: BackgroundCharacterData = roster.demote(promoted_id)
	test.expect(demoted != null, "高精度人物可降级为背景人物")
	var promoted_again: CharacterData = roster.promote(promoted_id)
	test.equal(
		int(promoted_again.domain_experience.get("alpha_test", 0)),
		77,
		"精度降级和升级保留领域经验"
	)
	test.expect(
		roster.active_characters.size() <= 20,
		"同时高精度人物不超过二十"
	)
	var saved: Dictionary = characters.get_persistent_state()
	test.expect(
		characters.restore_persistent_state(saved),
		"发展计划、评估和代理授权可保存恢复"
	)
	test.finish(self, "Alpha character and development")
