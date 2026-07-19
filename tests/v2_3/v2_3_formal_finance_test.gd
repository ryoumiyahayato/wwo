extends SceneTree
## Formal Lille credit uses the V2 household ledger and never the quarantined grid world.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23FormalSimulation.new()
	test.expect(simulation.initialize(), "正式 V2.3 金融环境可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 formal finance")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var initial_household: Dictionary = simulation.households.household_for_person(person_id)
	var initial_cash: int = int(initial_household.get("cash_centimes", 0))
	var remote_result: V2LifeLoopResult = simulation.submit_loan_application(
		person_id, "loan_product:lille_wage_advance", 1000
	)
	test.expect(
		not remote_result.success and remote_result.error_code == "not_at_lender",
		"不在正式办理地点时借款申请被客观拒绝"
	)
	test.expect(
		simulation.spatial_locations.force_set_at_location(
			person_id, "location_lille_centre", simulation.clock.total_hours
		).success,
		"测试通过正式地点服务进入里尔市中心"
	)
	simulation.advance_hours(3)
	var submitted: V2LifeLoopResult = simulation.submit_loan_application(
		person_id, "loan_product:lille_wage_advance", 1000
	)
	test.expect(submitted.success, "营业时间内可提交工资担保借款申请")
	test.equal(
		int(simulation.households.household_for_person(person_id).get("cash_centimes", 0)),
		initial_cash,
		"提交申请本身不直接生成现金"
	)
	simulation.advance_hours(1)
	var applications: Array[Dictionary] = simulation.finance.applications_for_person(person_id)
	test.equal(applications.size(), 1, "正式金融服务保存一份申请")
	var application: Dictionary = applications[0]
	test.equal(str(application.get("status", "")), "offered", "推进时间后形成具体借款条件")
	var application_id: String = str(application.get("application_id", ""))
	var accepted: V2LifeLoopResult = simulation.accept_loan_offer(application_id)
	test.expect(accepted.success, "人物可接受已经形成的借款条件")
	test.equal(
		int(simulation.households.household_for_person(person_id).get("cash_centimes", 0)),
		initial_cash + 1000,
		"放款只通过现有住户账本增加现金"
	)
	test.equal(simulation.finance.total_debt_for_person(person_id), 1000, "放款同时形成正式债务")
	var duplicate_accept: V2LifeLoopResult = simulation.accept_loan_offer(application_id)
	test.expect(duplicate_accept.success, "重复接受调用返回幂等结果")
	test.equal(
		int(simulation.households.household_for_person(person_id).get("cash_centimes", 0)),
		initial_cash + 1000,
		"重复接受不会重复生成现金"
	)
	var contracts: Array[Dictionary] = simulation.finance.contracts_for_person(person_id)
	test.equal(contracts.size(), 1, "只形成一份借款合同")
	var contract_id: String = str(contracts[0].get("contract_id", ""))
	var repaid: V2LifeLoopResult = simulation.repay_personal_loan(contract_id, 500)
	test.expect(repaid.success, "可从现有住户现金偿还借款")
	test.equal(
		int(simulation.households.household_for_person(person_id).get("cash_centimes", 0)),
		initial_cash + 500,
		"还款只通过现有住户账本扣除现金"
	)
	test.equal(simulation.finance.total_debt_for_person(person_id), 500, "还款降低正式合同余额")
	test.expect(
		simulation.ledger.validate_balances(simulation.households.households).success,
		"借款与还款后现有住户账本余额链仍一致"
	)
	var finance_json: String = JSON.stringify(simulation.finance.get_persistent_state())
	test.expect(
		not finance_json.contains("loran_")
		and not finance_json.contains("vesta_")
		and not finance_json.contains("control:"),
		"正式金融状态不引用已隔离架空网格 ID"
	)
	var save_service := V23SaveService.new()
	var snapshot: Dictionary = save_service.build_snapshot(simulation)
	test.equal(save_service.validate_snapshot(snapshot).size(), 0, "含金融状态的正式快照通过校验")
	var restored := V23FormalSimulation.new()
	test.expect(restored.initialize(), "可建立独立正式金融恢复目标")
	test.expect(save_service.restore(snapshot, restored).success, "正式金融状态可随 V2.3 存档恢复")
	test.equal(
		restored.finance.total_debt_for_person(person_id),
		simulation.finance.total_debt_for_person(person_id),
		"恢复保持借款合同余额"
	)
	test.equal(
		int(restored.households.household_for_person(person_id).get("cash_centimes", 0)),
		int(simulation.households.household_for_person(person_id).get("cash_centimes", 0)),
		"恢复保持唯一住户现金"
	)
	test.expect(
		restored.ledger.validate_balances(restored.households.households).success,
		"恢复后住户账本继续闭合"
	)
	test.finish(self, "V2.3 formal finance")
