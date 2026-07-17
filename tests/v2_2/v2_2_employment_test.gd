extends SceneTree
## Attendance, leave, absence, overtime and idempotent pay.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "就业测试模拟可初始化")
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var start_cash: int = int(simulation.households.household_for_person(pierre).get("cash_centimes", 0))
	var first_pay_hour: int = int(simulation.employment.contract_for_person(pierre).get("next_pay_hour", -1))
	simulation.advance_hours(first_pay_hour - simulation.clock.total_hours + 1)
	var wage_transactions: Array[Dictionary] = []
	for transaction: Dictionary in simulation.ledger.transactions:
		if str(transaction.get("category", "")) == "wage" and str(transaction.get("person_id", "")) == pierre:
			wage_transactions.append(transaction)
	test.equal(wage_transactions.size(), 1, "完整首周工资只到账一次")
	test.equal(int(wage_transactions[0].get("amount_centimes", -1)), 2400, "完整出勤周薪准确为2400生丁")
	var duplicate: V2LifeLoopResult = simulation.employment.force_settle("contract:pierre_lille_mechanical", first_pay_hour, simulation.households, simulation.ledger, simulation.notifications)
	test.expect(not duplicate.success and duplicate.error_code == "duplicate_wage", "同一周工资重复结算被拒绝")
	test.expect(int(simulation.households.household_for_person(pierre).get("cash_centimes", 0)) >= start_cash, "工资进入个人住户现金")
	var leave_sim := V2LifeLoopSimulation.new()
	leave_sim.initialize()
	var leave_start: int = V2DateTime.total_hour_from_iso("1900-03-12T07:00:00")
	test.expect(leave_sim.request_activity(pierre, "authorized_leave", leave_start, 5).success, "上午无薪请假自动批准")
	var leave_pay: int = int(leave_sim.employment.contract_for_person(pierre).get("next_pay_hour", -1))
	leave_sim.advance_hours(leave_pay - leave_sim.clock.total_hours + 1)
	var paid: int = 0
	for transaction: Dictionary in leave_sim.ledger.transactions:
		if str(transaction.get("category", "")) == "wage" and str(transaction.get("person_id", "")) == pierre:
			paid = int(transaction.get("amount_centimes", 0))
	test.equal(paid, 2400 - 5 * 45, "5小时授权无薪请假按每小时45生丁扣除")
	var summary: Dictionary = leave_sim.employment.today_summary(pierre, leave_pay)
	test.expect(leave_sim.employment.employment_risk(pierre) == 0, "授权请假不增加无故缺勤风险")
	var overtime_sim := V2LifeLoopSimulation.new()
	overtime_sim.initialize()
	test.expect(overtime_sim.request_activity(pierre, "overtime", V2DateTime.total_hour_from_iso("1900-03-12T17:00:00"), 2).success, "工作日17:00可安排2小时加班")
	test.expect(not overtime_sim.request_activity(pierre, "overtime", V2DateTime.total_hour_from_iso("1900-03-13T17:00:00"), 3).success, "每日加班超过2小时被拒绝")
	var overtime_pay_hour: int = int(
		overtime_sim.employment.contract_for_person(pierre).get("next_pay_hour", -1)
	)
	overtime_sim.advance_hours(overtime_pay_hour - overtime_sim.clock.total_hours + 1)
	var overtime_payment: int = 0
	for transaction: Dictionary in overtime_sim.ledger.transactions:
		if (
			str(transaction.get("category", "")) == "overtime_wage"
			and str(transaction.get("person_id", "")) == pierre
		):
			overtime_payment += int(transaction.get("amount_centimes", 0))
	test.equal(overtime_payment, 112, "2小时加班按每小时56生丁独立入账")
	var fatigue_sim := V2LifeLoopSimulation.new()
	fatigue_sim.initialize()
	test.expect(fatigue_sim.set_condition(pierre, "fatigue", 950).success, "开发命令可把疲劳设为950")
	var blocked_overtime: V2LifeLoopResult = fatigue_sim.request_activity(
		pierre, "overtime", V2DateTime.total_hour_from_iso("1900-03-12T17:00:00"), 1
	)
	test.expect(
		not blocked_overtime.success and blocked_overtime.error_code == "fatigue_too_high",
		"疲劳达到950时权威层拒绝加班"
	)
	var absence_sim := V2LifeLoopSimulation.new()
	absence_sim.initialize()
	test.expect(
		absence_sim.request_activity(
			pierre, "absence", V2DateTime.total_hour_from_iso("1900-03-12T07:00:00"), 5
		).success,
		"开发缺勤可覆盖5小时正式义务"
	)
	absence_sim.advance_hours(
		V2DateTime.total_hour_from_iso("1900-03-12T17:00:00")
		- absence_sim.clock.total_hours + 1
	)
	test.equal(absence_sim.employment.employment_risk(pierre), 125, "5小时无故缺勤增加125就业风险")
	absence_sim.advance_hours(24)
	test.equal(absence_sim.employment.employment_risk(pierre), 115, "随后完整出勤日降低10就业风险")
	var absence_pay_hour: int = int(
		absence_sim.employment.contract_for_person(pierre).get("next_pay_hour", -1)
	)
	absence_sim.advance_hours(absence_pay_hour - absence_sim.clock.total_hours + 1)
	var absence_wage: int = 0
	for transaction: Dictionary in absence_sim.ledger.transactions:
		if (
			str(transaction.get("category", "")) == "wage"
			and str(transaction.get("person_id", "")) == pierre
		):
			absence_wage = int(transaction.get("amount_centimes", 0))
	test.equal(absence_wage, 2175, "5小时无故缺勤同样按每小时45生丁扣薪")
	var minimum_wage_sim := V2LifeLoopSimulation.new()
	minimum_wage_sim.initialize()
	for day: int in range(12, 18):
		test.expect(
			minimum_wage_sim.request_activity(
				pierre,
				"absence",
				V2DateTime.total_hour_from_iso("1900-03-%02dT07:00:00" % day),
				10
			).success,
			"3月%d日全班缺勤可安排" % day
		)
	var minimum_pay_hour: int = int(
		minimum_wage_sim.employment.contract_for_person(pierre).get("next_pay_hour", -1)
	)
	minimum_wage_sim.advance_hours(
		minimum_pay_hour - minimum_wage_sim.clock.total_hours + 1
	)
	var minimum_wage: int = -1
	for transaction: Dictionary in minimum_wage_sim.ledger.transactions:
		if (
			str(transaction.get("category", "")) == "wage"
			and str(transaction.get("person_id", "")) == pierre
		):
			minimum_wage = int(transaction.get("amount_centimes", -1))
	test.equal(minimum_wage, 0, "缺勤扣款大于周薪时基本工资下限保持0")
	test.finish(self, "V2.2 employment")
