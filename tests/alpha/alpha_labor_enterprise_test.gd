extends SceneTree
## Alpha C-stage employment and enterprise success/failure lifecycle regression.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "Alpha 劳动企业配置可载入")
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	test.expect(loaded.is_success(), "既有统一组织权威数据可载入")
	if not loaded.is_success():
		test.finish(self, "Alpha labor and enterprise")
		return
	var organizations := OrganizationService.new(loaded.data_set.organizations)
	var economy := AlphaEconomyService.new()
	test.expect(economy.configure(config), "企业连接统一经济权威")
	var labor := AlphaLaborService.new()
	test.expect(labor.configure(config, economy), "十二类工作进入统一劳动服务")
	var enterprise := AlphaEnterpriseService.new()
	var enterprise_configured: bool = enterprise.configure(
		config, economy, labor, organizations, 0
	)
	if not enterprise_configured:
		print("ENTERPRISE_BOOTSTRAP_DEBUG organizations=%d entities=%d assets=%d profiles=%s" % [
			organizations.organizations.size(),
			economy.entity_profiles.size(),
			economy.assets.assets.size(),
			economy.entity_profiles.has("organization:enterprise_dawnharbor_freight"),
		])
	test.expect(
		enterprise_configured,
		"十二家初始企业作为统一组织的经营扩展建立"
	)
	test.equal(enterprise.enterprises.size(), 12, "初始正式企业数量为十二")
	var purchasable_count: int = 0
	var indebted_count: int = 0
	var near_bankruptcy_count: int = 0
	for raw_enterprise: Variant in enterprise.enterprises.values():
		var state: Dictionary = raw_enterprise as Dictionary
		if bool(state.get("purchasable", false)):
			purchasable_count += 1
		if economy.total_debt(str(state.get("organization_id", ""))) > 0:
			indebted_count += 1
		if int(state.get("distress", 0)) >= 80:
			near_bankruptcy_count += 1
	test.expect(purchasable_count >= 4, "至少四家企业可购买或接管")
	test.expect(indebted_count >= 3, "至少三家企业具有正式期初债务")
	test.expect(near_bankruptcy_count >= 1, "至少一家企业接近破产")
	test.expect(
		labor.register_person(
			"person:worker",
			{
				"country_id": "country:loran_federation",
				"region_id": "region:loran_riverback",
				"city_id": "city:ironford",
				"skills": {"engineering": 68, "administration": 52},
				"qualifications": [],
				"opening_cash_centimes": 1200,
			}
		),
		"劳动者进入正式人物劳动档案"
	)
	test.expect(
		labor.discover_jobs("person:worker", true).size() >= 12,
		"人物可发现本地和跨地区工作"
	)
	var application_result: Dictionary = labor.apply_for_job(
		"apply:test:worker",
		"person:worker",
		"job:mechanical_worker",
		10
	)
	test.expect(bool(application_result.get("success", false)), "人物可申请具体工作")
	var application: Dictionary = (
		application_result.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	var application_id: String = str(application.get("application_id", ""))
	var decided: Dictionary = labor.employer_decide(
		"decide:test:worker", application_id, 11, 70
	)
	test.expect(bool(decided.get("success", false)), "雇主按能力、资格和用工需求判断")
	var accepted: Dictionary = labor.accept_job_offer(
		"accept:test:worker", application_id, 12
	)
	test.expect(bool(accepted.get("success", false)), "接受工作条件建立正式雇佣合同")
	var employment: Dictionary = (accepted.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var employment_id: String = str(employment.get("contract_id", ""))
	var worker_cash_before: int = economy.ledger.owner_cash("person:worker")
	test.expect(
		bool(labor.work_shift(
			"shift:test:worker:1", employment_id, 20, 8, 9000
		).get("success", false)),
		"实际工作产生工时、经验、状态和交付证据"
	)
	test.expect(
		bool(labor.pay_wage(
			"wage:test:worker:1", employment_id, 7 * 24
		).get("success", false)),
		"已完成工作产生正式工资账本交易"
	)
	test.expect(
		economy.ledger.owner_cash("person:worker") > worker_cash_before,
		"劳动者收到工资"
	)
	test.expect(
		int((labor.person_profiles["person:worker"] as Dictionary).get(
			"fatigue", 0
		)) > 10,
		"工作实际改变人物当前状态"
	)
	test.expect(
		bool(labor.negotiate_terms(
			"negotiate:test:worker", employment_id, 8 * 24, 2900, 44
		).get("success", false)),
		"雇佣条件可协商"
	)
	test.expect(
		bool(labor.promote(
			"promote:test:worker", employment_id, 9 * 24, "工头"
		).get("success", false)),
		"雇佣职位可晋升或调岗"
	)
	test.expect(
		bool(labor.resign(
			"resign:test:worker", employment_id, 10 * 24
		).get("success", false)),
		"人物可辞职并结束雇佣合同"
	)
	test.expect(labor.unemployment.has("person:worker"), "辞职人物进入失业和再求职状态")
	for registration: Dictionary in [
		economy.register_entity(
			"person:founder",
			"person",
			80000,
			{
				"income_monthly_centimes": 8000,
				"reputation": 72,
				"relationship_with_lender": 35,
				"region_id": "region:loran_dawnbay",
			}
		),
		economy.register_entity("person:partner", "person", 30000),
		economy.register_entity("organization:client", "organization", 100000),
		economy.register_entity("organization:supplier", "organization", 100000),
		economy.register_entity("organization:expert", "organization", 10000),
		economy.register_entity("organization:equipment_vendor", "organization", 10000),
	]:
		test.expect(bool(registration.get("success", false)), "企业参与方取得正式账本账户")
	var created: Dictionary = enterprise.create_enterprise(
		"create:test:success",
		"person:founder",
		"远岸纺织合伙社",
		"small_production",
		"region:loran_dawnbay",
		"city:dawnharbor",
		"textiles",
		"timber",
		15000,
		20 * 24
	)
	test.expect(bool(created.get("success", false)), "玩家无需先工作即可直接创建企业")
	var created_state: Dictionary = (created.get("data", {}) as Dictionary).get(
		"enterprise", {}
	) as Dictionary
	var success_enterprise_id: String = str(created_state.get("organization_id", ""))
	test.expect(
		organizations.get_organization(success_enterprise_id) != null,
		"新企业使用统一组织对象"
	)
	test.expect(
		bool(enterprise.establish_partnership(
			"partner:test:success",
			success_enterprise_id,
			"person:founder",
			"person:partner",
			4000,
			2500,
			20 * 24 + 1
		).get("success", false)),
		"合伙合同连接投入、权益、利益和责任"
	)
	var success_equipment_id: String = str(
		((enterprise.enterprises[success_enterprise_id] as Dictionary).get(
			"asset_ids", []
		) as Array)[0]
	)
	test.expect(
		bool(enterprise.borrow_for_operations(
			"borrow:test:success",
			success_enterprise_id,
			"organization:loran_public_credit",
			12000,
			20 * 24 + 2,
			[success_equipment_id]
		).get("success", false)),
		"企业可用资产抵押进行杠杆经营"
	)
	var order_result: Dictionary = enterprise.accept_order(
		"order:test:success",
		success_enterprise_id,
		"organization:client",
		8,
		"region:vesta_silverfield",
		21 * 24,
		4
	)
	test.expect(bool(order_result.get("success", false)), "企业可接受跨地区正式订单")
	var order_contract: Dictionary = (order_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var order_id: String = str(order_contract.get("contract_id", ""))
	test.expect(
		bool(enterprise.procure_inputs(
			"procure:test:success",
			success_enterprise_id,
			"organization:supplier",
			8,
			"region:loran_southridge",
			21 * 24,
			2
		).get("success", false)),
		"企业采购和运输形成正式订单与账本交易"
	)
	test.expect(
		bool(enterprise.produce(
			"produce:test:success",
			success_enterprise_id,
			8,
			23 * 24,
			"person:founder"
		).get("success", false)),
		"企业投入品经执行能力转为产成品"
	)
	var enterprise_cash_before_delivery: int = economy.ledger.owner_cash(
		success_enterprise_id
	)
	test.expect(
		bool(enterprise.deliver_order(
			"deliver:test:success",
			success_enterprise_id,
			order_id,
			25 * 24
		).get("success", false)),
		"企业交付订单并取得收入"
	)
	test.expect(
		economy.ledger.owner_cash(success_enterprise_id) > enterprise_cash_before_delivery,
		"订单收入进入企业正式账本"
	)
	test.expect(
		bool(enterprise.outsource_service(
			"outsource:test:success",
			success_enterprise_id,
			"organization:expert",
			"账本复核",
			800,
			26 * 24
		).get("success", false)),
		"一次专业服务是合同而不是下属关系"
	)
	test.expect(
		bool(enterprise.expand(
			"expand:test:success",
			success_enterprise_id,
			1500,
			4,
			"organization:equipment_vendor",
			27 * 24
		).get("success", false)),
		"盈利企业可购买设备并扩张执行能力"
	)
	test.expect(
		labor.register_person(
			"person:new_employee",
			{
				"country_id": "country:loran_federation",
				"region_id": "region:loran_dawnbay",
				"city_id": "city:dawnharbor",
				"skills": {"administration": 64},
				"opening_cash_centimes": 500,
			}
		),
		"新雇员进入统一劳动档案"
	)
	test.expect(
		bool(enterprise.hire(
			"hire:test:success",
			success_enterprise_id,
			"person:new_employee",
			28 * 24
		).get("success", false)),
		"企业雇员通过正式雇佣合同进入人员结构"
	)
	var success_state: Dictionary = enterprise.enterprises[
		success_enterprise_id
	] as Dictionary
	test.equal(
		str(success_state.get("status", "")),
		"operating",
		"成功企业完成订单后保持经营状态"
	)
	var failed_enterprise_id: String = "organization:vesta_redhill_industry"
	var failed_state: Dictionary = enterprise.enterprises[
		failed_enterprise_id
	] as Dictionary
	var failure_order: Dictionary = enterprise.accept_order(
		"order:test:failure",
		failed_enterprise_id,
		"organization:client",
		60,
		"region:loran_dawnbay",
		30 * 24,
		6
	)
	test.expect(bool(failure_order.get("success", false)), "高风险企业仍可接受超过当前能力的订单")
	var failure_contract: Dictionary = (
		failure_order.get("data", {}) as Dictionary
	).get("contract", {}) as Dictionary
	var failure_order_id: String = str(failure_contract.get("contract_id", ""))
	test.expect(
		bool(economy.contracts.delay(
			"delay:test:failure",
			failure_order_id,
			35 * 24,
			"产能与投入品不足"
		).get("success", false)),
		"订单可进入延期状态"
	)
	var failure_equipment_id: String = str(
		(failed_state.get("asset_ids", []) as Array)[0]
	)
	var refinancing: Dictionary = enterprise.borrow_for_operations(
		"refinance:test:failure",
		failed_enterprise_id,
		"organization:vesta_public_credit",
		5000,
		35 * 24,
		[failure_equipment_id]
	)
	test.expect(bool(refinancing.get("success", false)), "困境企业可用抵押取得新借款")
	var old_loan_id: String = ""
	for contract: Dictionary in economy.contracts.contracts_for_party(
		failed_enterprise_id, false
	):
		if (
			str(contract.get("contract_type", "")) == "loan"
			and bool((contract.get("subject", {}) as Dictionary).get(
				"opening_obligation", false
			))
		):
			old_loan_id = str(contract.get("contract_id", ""))
			break
	test.expect(not old_loan_id.is_empty(), "困境企业保留期初借款合同")
	test.expect(
		bool(economy.repay_loan(
			"repay_old:test:failure", old_loan_id, 35 * 24 + 1, 3000
		).get("success", false)),
		"新借款现金可用于偿还旧借款"
	)
	test.expect(
		bool(enterprise.bankrupt(
			"bankrupt:test:failure",
			failed_enterprise_id,
			50 * 24,
			"订单延期、现金不足且无法继续履约"
		).get("success", false)),
		"高杠杆失败路径进入正式破产"
	)
	test.equal(
		str((enterprise.enterprises[failed_enterprise_id] as Dictionary).get(
			"status", ""
		)),
		"bankrupt",
		"破产结束经营并处置资产与合同"
	)
	test.expect(
		bool(enterprise.dissolve(
			"dissolve:test:failure", failed_enterprise_id, 51 * 24
		).get("success", false)),
		"破产企业可完成解散终态"
	)
	test.equal(
		str((enterprise.enterprises[failed_enterprise_id] as Dictionary).get(
			"status", ""
		)),
		"dissolved",
		"企业生命周期具有解散终点"
	)
	test.expect(
		bool(labor.migrate(
			"migrate:test:worker",
			"person:worker",
			"country:vesta_union",
			"region:vesta_silverfield",
			"city:starhold",
			"organization:vesta_enterprise",
			240,
			60 * 24
		).get("success", false)),
		"失业人物可支付交通成本并跨地区迁移"
	)
	test.equal(
		str((labor.person_profiles["person:worker"] as Dictionary).get(
			"city_id", ""
		)),
		"city:starhold",
		"迁移实际改变人物地区与城市"
	)
	test.expect(
		bool(enterprise.validate_integrity().get("success", false)),
		"企业组织、资产、合同、人员和账本引用闭合"
	)
	test.expect(
		bool(economy.validate_integrity().get("success", false)),
		"成功与失败路径后经济权威仍一致"
	)
	var labor_saved: Dictionary = labor.get_persistent_state()
	var enterprise_saved: Dictionary = enterprise.get_persistent_state()
	test.expect(
		labor.restore_persistent_state(labor_saved),
		"劳动申请、雇佣、失业和迁移可保存恢复"
	)
	test.expect(
		enterprise.restore_persistent_state(enterprise_saved),
		"企业经营、破产和解散可保存恢复"
	)
	test.finish(self, "Alpha labor and enterprise")
