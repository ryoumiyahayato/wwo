extends SceneTree
## Alpha E-stage organization, position, faction, policy, corruption and investigation.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "Alpha 组织政治配置可载入")
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	test.expect(loaded.is_success(), "既有组织权威可载入")
	if not loaded.is_success():
		test.finish(self, "Alpha organization and politics")
		return
	var world := AlphaWorldService.new()
	test.expect(world.configure(loaded.data_set, config), "政策连接正式地区世界状态")
	var organizations := OrganizationService.new(loaded.data_set.organizations)
	var economy := AlphaEconomyService.new()
	test.expect(economy.configure(config), "政治预算连接统一账本")
	var labor := AlphaLaborService.new()
	test.expect(labor.configure(config, economy), "组织人物连接统一劳动档案")
	var enterprise := AlphaEnterpriseService.new()
	test.expect(
		enterprise.configure(config, economy, labor, organizations, 0),
		"政治利益连接十二家正式企业"
	)
	var politics := AlphaPoliticsService.new()
	test.expect(
		politics.configure(config, organizations, economy, world),
		"组织、职位、议题、政策和腐败服务完成配置"
	)
	var type_counts: Dictionary = {}
	for raw_organization: Variant in organizations.organizations.values():
		var organization: OrganizationData = raw_organization as OrganizationData
		type_counts[organization.type] = int(type_counts.get(organization.type, 0)) + 1
	test.expect(int(type_counts.get("enterprise", 0)) >= 12, "统一组织中至少十二家企业")
	test.expect(int(type_counts.get("union", 0)) >= 4, "统一组织中至少四个工会或职业组织")
	test.expect(int(type_counts.get("government", 0)) >= 6, "两国各至少三个政府机构")
	test.expect(int(type_counts.get("political", 0)) >= 4, "两国各至少两个政治组织")
	test.expect(int(type_counts.get("press", 0)) >= 2, "两国各至少一个报社或公共组织")
	test.expect(int(type_counts.get("military", 0)) >= 2, "两国各有聚合军事组织")
	var generation := CharacterGenerationConfig.load_from_file()
	var characters := AlphaCharacterService.new()
	test.expect(
		characters.configure(
			loaded.data_set, generation, config, economy, labor
		),
		"政治人物继续使用统一人物服务"
	)
	var actor_result: Dictionary = characters.create_from_preset(
		"preset:local_official"
	)
	test.expect(bool(actor_result.get("success", false)), "地方官员预设可建立")
	var actor: CharacterData = (actor_result.get("data", {}) as Dictionary).get(
		"character"
	) as CharacterData
	actor.skills["political_activity"] = 88
	actor.skills["public_speaking"] = 82
	actor.skills["investigation"] = 60
	actor.hidden_aptitudes["social_perception"] = 78
	var supporter_result: Dictionary = characters.create_character(
		"country:loran_federation",
		"region:loran_dawnbay",
		"city:dawnharbor",
		"category_random",
		"organization",
		8181,
		{},
		"character:supporter"
	)
	var supporter: CharacterData = (
		supporter_result.get("data", {}) as Dictionary
	).get("character") as CharacterData
	supporter.skills["political_activity"] = 55
	var investigator_result: Dictionary = characters.create_character(
		"country:loran_federation",
		"region:loran_dawnbay",
		"city:dawnharbor",
		"category_random",
		"professional",
		9191,
		{},
		"character:investigator"
	)
	var investigator: CharacterData = (
		investigator_result.get("data", {}) as Dictionary
	).get("character") as CharacterData
	investigator.skills["investigation"] = 92
	investigator.hidden_aptitudes["reasoning"] = 84
	var political_org: String = "organization:loran_civic_league"
	for join_result: Dictionary in [
		politics.join_organization(
			"join:political:actor", actor, political_org, 10
		),
		politics.join_organization(
			"join:political:supporter", supporter, political_org, 10
		),
	]:
		test.expect(bool(join_result.get("success", false)), "人物可加入政治组织")
	var faction_result: Dictionary = politics.create_faction(
		"faction:test:reform",
		political_org,
		actor,
		"工资与商事改革派",
		["issue:loran_wage_floor", "issue:loran_license_reform"],
		12
	)
	test.expect(bool(faction_result.get("success", false)), "政治成员可围绕实际议题建立派别")
	var faction: Dictionary = (faction_result.get("data", {}) as Dictionary).get(
		"faction", {}
	) as Dictionary
	test.expect(
		bool(politics.join_faction(
			"faction_join:test:supporter",
			str(faction.get("faction_id", "")),
			supporter
		).get("success", false)),
		"其他实际成员可加入派别"
	)
	test.expect(
		bool(politics.campaign_for_support(
			"campaign:test:political",
			actor,
			supporter,
			political_org,
			"issue:loran_wage_floor",
			100
		).get("success", false)),
		"候选人可围绕争议议题争取成员支持"
	)
	var political_contest: Dictionary = politics.contest_position(
		"contest:test:political",
		actor,
		political_org,
		"chair",
		20
	)
	test.equal(
		str((political_contest.get("data", {}) as Dictionary).get("result", "")),
		"won",
		"成员支持和人物能力可赢得政治组织负责人职位"
	)
	test.equal(
		organizations.get_position_id(actor.id, political_org),
		"chair",
		"职位持有者由统一组织权威保存"
	)
	var government_org: String = "organization:loran_commerce_registry"
	for join_result: Dictionary in [
		politics.join_organization(
			"join:government:actor", actor, government_org, 24
		),
		politics.join_organization(
			"join:government:investigator", investigator, government_org, 24
		),
	]:
		test.expect(bool(join_result.get("success", false)), "人物可加入政府机构")
	test.expect(
		bool(politics.campaign_for_support(
			"campaign:test:government",
			actor,
			investigator,
			government_org,
			"issue:loran_license_reform",
			100
		).get("success", false)),
		"行政职位竞争读取实际成员支持"
	)
	var government_contest: Dictionary = politics.contest_position(
		"contest:test:government",
		actor,
		government_org,
		"registrar",
		30
	)
	test.equal(
		str((government_contest.get("data", {}) as Dictionary).get("result", "")),
		"won",
		"人物可取得具有预算和政策权限的行政负责人职位"
	)
	var package: Dictionary = politics.position_packages[
		"%s|registrar" % government_org
	] as Dictionary
	for field: String in [
		"jurisdiction",
		"information_access",
		"budget_limit_centimes",
		"command_levels",
		"appointment_right",
		"removal_right",
		"contract_signing",
		"policy_permissions",
		"responsibilities",
		"term_hours",
		"gain_conditions",
		"loss_conditions",
	]:
		test.expect(package.has(field), "职位权限包保存字段：%s" % field)
	test.equal(politics.issues.size(), 8, "两国各有四项可争议议题")
	test.equal(politics.policies.size(), 8, "两国各有四项可实施政策")
	test.equal(
		(politics.organization_states[government_org] as Dictionary).get(
			"budget_fields", []
		).size(),
		3,
		"政府组织具有三个预算领域"
	)
	var wage_before: int = int(
		(world.regions["region:loran_dawnbay"] as Dictionary).get(
			"wage_index", 0
		)
	)
	var proposal_result: Dictionary = politics.propose_policy(
		"policy_propose:test:wage",
		actor,
		government_org,
		"policy:loran_wage_floor",
		["region:loran_dawnbay", "region:loran_riverback"],
		40
	)
	test.expect(bool(proposal_result.get("success", false)), "职位法定权限可提出劳动政策")
	var implementation: Dictionary = (
		proposal_result.get("data", {}) as Dictionary
	).get("implementation", {}) as Dictionary
	var implementation_id: String = str(
		implementation.get("implementation_id", "")
	)
	test.expect(
		bool(politics.fund_and_start_policy(
			"policy_fund:test:wage", implementation_id, 41
		).get("success", false)),
		"政策从组织正式账本调用预算"
	)
	var advanced: Dictionary = politics.advance_policy(
		"policy_advance:test:wage", implementation_id, 12 * 7 * 24, 12
	)
	test.expect(bool(advanced.get("success", false)), "政策按周推进执行")
	var completed: Dictionary = (
		advanced.get("data", {}) as Dictionary
	).get("implementation", {}) as Dictionary
	test.equal(str(completed.get("status", "")), "completed", "政策经过完整落实链后完成")
	for factor: String in [
		"legal_permission",
		"actual_compliance",
		"execution_capacity",
		"funding_ratio",
		"staffing",
		"infrastructure",
		"external_resistance",
	]:
		test.expect(completed.has(factor), "政策落实保存判断：%s" % factor)
	test.equal(
		int((world.regions["region:loran_dawnbay"] as Dictionary).get(
			"wage_index", 0
		)),
		wage_before + 5,
		"政策实际改变地区工资正式数据"
	)
	test.expect(
		not (completed.get("support_reactions", []) as Array).is_empty()
		and not (completed.get("opposition_reactions", []) as Array).is_empty(),
		"政策支持和反对来自实际利益冲突"
	)
	test.expect(
		bool(politics.political_exchange(
			"exchange:test:political",
			actor.id,
			supporter.id,
			political_org,
			"支持工资议题",
			"支持负责人连任",
			100
		).get("success", false)),
		"政治交换形成有参与方和文件的正式约定"
	)
	var beneficiary_id: String = "organization:loran_dawnbay_trade"
	var beneficiary_cash_before: int = economy.ledger.owner_cash(beneficiary_id)
	var corrupt_result: Dictionary = politics.perform_corruption(
		"corruption:test:steer",
		"corruption:steer_contract",
		actor,
		government_org,
		beneficiary_id,
		1800,
		120,
		[investigator.id],
		{"relationship": "关联企业"}
	)
	test.expect(bool(corrupt_result.get("success", false)), "职位持有者可将合同交给关联企业")
	var corruption_case: Dictionary = (
		corrupt_result.get("data", {}) as Dictionary
	).get("corruption_case", {}) as Dictionary
	var corruption_id: String = str(corruption_case.get("case_id", ""))
	test.expect(
		economy.ledger.owner_cash(beneficiary_id) == beneficiary_cash_before + 1800,
		"腐败收益形成可追踪资金流"
	)
	for evidence_field: String in [
		"transaction_id",
		"beneficiary_id",
		"document_id",
		"witness_ids",
		"evidence_ids",
		"obligation_key",
	]:
		test.expect(
			not corruption_case.get(evidence_field, null) in [null, "", []],
			"腐败留下正式证据字段：%s" % evidence_field
		)
	var investigation_result: Dictionary = politics.investigate_corruption(
		"investigation:test:steer",
		corruption_id,
		investigator,
		government_org,
		140
	)
	test.expect(bool(investigation_result.get("success", false)), "另一人物可正式调查腐败")
	var investigation: Dictionary = (
		investigation_result.get("data", {}) as Dictionary
	).get("investigation", {}) as Dictionary
	test.equal(
		str(investigation.get("status", "")),
		"substantiated",
		"高能力调查者从资金、文件和知情者发现充分证据"
	)
	var resolution: Dictionary = politics.resolve_investigation(
		"resolution:test:steer",
		str(investigation.get("investigation_id", "")),
		actor,
		150
	)
	test.expect(bool(resolution.get("success", false)), "充分证据产生政治、法律、关系和资产后果")
	test.equal(
		organizations.get_position_id(actor.id, government_org),
		"clerk",
		"违法行为使职位持有者失去行政负责人权限"
	)
	test.expect(
		not politics.public_events.is_empty(),
		"腐败调查形成具体公开丑闻事件"
	)
	test.expect(
		bool(politics.lose_position(
			"resign:test:political",
			actor,
			political_org,
			"resignation",
			160
		).get("success", false)),
		"政治组织职位可以主动辞去"
	)
	test.equal(
		organizations.get_position_id(actor.id, political_org),
		"member",
		"辞职后人物保留普通成员身份但失去职位权限"
	)
	test.expect(
		bool(politics.validate_integrity().get("success", false)),
		"组织、职位、政策、资金、腐败和证据引用闭合"
	)
	test.expect(
		bool(economy.validate_integrity().get("success", false)),
		"政策与腐败闭环后统一经济权威仍一致"
	)
	var saved: Dictionary = politics.get_persistent_state()
	test.expect(
		politics.restore_persistent_state(saved),
		"组织扩展、职位任期、政策、腐败和调查可保存恢复"
	)
	test.finish(self, "Alpha organization and politics")
