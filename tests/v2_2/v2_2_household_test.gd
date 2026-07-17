extends SceneTree
## Integer-money purchase, daily consumption, rent and ledger consistency.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "住户测试模拟可初始化")
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var household: Dictionary = simulation.households.household_for_person(pierre)
	test.equal(int(household.get("cash_centimes", -1)), 1800, "皮埃尔初始现金1800生丁")
	test.equal(int(household.get("food_stock_person_days", -1)), 3, "皮埃尔初始食品3人日")
	test.equal(int(household.get("essentials_stock_person_days", -1)), 5, "皮埃尔初始用品5人日")
	var purchase_hour: int = V2DateTime.total_hour_from_iso("1900-03-12T18:00:00")
	test.expect(simulation.request_activity(pierre, "purchase_food", purchase_hour, 1).success, "营业时间可安排食品购买")
	simulation.advance_hours(purchase_hour - simulation.clock.total_hours + 1)
	household = simulation.households.household_for_person(pierre)
	test.equal(int(household.get("cash_centimes", -1)), 1240, "食品购买准确扣除560生丁")
	test.equal(int(household.get("food_stock_person_days", -1)), 9, "日消费后购买增加7人日食品")
	test.expect(simulation.ledger_consistency().success, "购买后账本与现金一致")
	var essentials_sim := V2LifeLoopSimulation.new()
	essentials_sim.initialize()
	test.expect(
		essentials_sim.request_activity(
			pierre, "purchase_essentials", purchase_hour, 1
		).success,
		"营业时间可安排生活用品购买"
	)
	essentials_sim.advance_hours(
		purchase_hour - essentials_sim.clock.total_hours + 1
	)
	var essentials_household: Dictionary = essentials_sim.households.household_for_person(pierre)
	test.equal(
		int(essentials_household.get("cash_centimes", -1)),
		1660,
		"生活用品购买准确扣除140生丁"
	)
	test.equal(
		int(essentials_household.get("essentials_stock_person_days", -1)),
		11,
		"日消费后生活用品购买增加7人日库存"
	)
	test.expect(essentials_sim.ledger_consistency().success, "生活用品购买后账本一致")
	var poor := V2LifeLoopSimulation.new()
	poor.initialize()
	poor.set_household_cash(pierre, 0)
	test.expect(not poor.request_activity(pierre, "purchase_food", purchase_hour, 1).success, "现金不足不能安排购买且报告结构化失败")
	var poor_household: Dictionary = poor.households.household_for_person(pierre)
	test.equal(int(poor_household.get("food_stock_person_days", -1)), 3, "现金不足不改变食品库存")
	var household_id: String = poor.households.household_id_for_person(pierre)
	var mutable: Dictionary = poor.households.households[household_id] as Dictionary
	mutable["next_rent_due_hour"] = poor.clock.total_hours
	poor.households.households[household_id] = mutable
	var rent_results: Array[V2LifeLoopResult] = poor.households.settle_due_rent(poor.clock.total_hours, poor.ledger, poor.conditions, poor.notifications)
	test.expect(not rent_results.is_empty() and rent_results[0].success, "现金不足房租使用全额欠款规则完成结算")
	poor_household = poor.households.household_for_person(pierre)
	test.equal(int(poor_household.get("cash_centimes", -1)), 0, "欠租不把现金变为负数")
	test.equal(int(poor_household.get("rent_arrears_centimes", -1)), 600, "欠租增加600生丁")
	test.expect(poor.ledger_consistency().success, "欠租后现金与账本仍一致")
	var rent_sim := V2LifeLoopSimulation.new()
	rent_sim.initialize()
	var rent_household_id: String = rent_sim.households.household_id_for_person(pierre)
	var rent_household: Dictionary = rent_sim.households.households[rent_household_id] as Dictionary
	rent_household["next_rent_due_hour"] = rent_sim.clock.total_hours
	rent_household["next_rent_due_datetime"] = V2DateTime.iso_from_total_hour(
		rent_sim.clock.total_hours
	)
	rent_sim.households.households[rent_household_id] = rent_household
	var paid_rent_results: Array[V2LifeLoopResult] = rent_sim.households.settle_due_rent(
		rent_sim.clock.total_hours,
		rent_sim.ledger,
		rent_sim.conditions,
		rent_sim.notifications
	)
	test.expect(
		not paid_rent_results.is_empty() and paid_rent_results[0].success,
		"现金充足时租金正常支付"
	)
	rent_household = rent_sim.households.household_for_person(pierre)
	test.equal(int(rent_household.get("cash_centimes", -1)), 1200, "支付600生丁租金后现金正确")
	test.equal(
		int(rent_household.get("next_rent_due_hour", -1)),
		rent_sim.clock.total_hours + 168,
		"周租支付后下一到期日推进7天"
	)
	var rent_transaction_count: int = 0
	for transaction: Dictionary in rent_sim.ledger.transactions:
		if str(transaction.get("category", "")) == "rent":
			rent_transaction_count += 1
	test.equal(rent_transaction_count, 1, "一次到期只产生一笔租金流水")
	var mutable_paid: Dictionary = rent_sim.households.households[rent_household_id] as Dictionary
	mutable_paid["next_rent_due_hour"] = rent_sim.clock.total_hours
	rent_sim.households.households[rent_household_id] = mutable_paid
	var duplicate_rent: Array[V2LifeLoopResult] = rent_sim.households.settle_due_rent(
		rent_sim.clock.total_hours,
		rent_sim.ledger,
		rent_sim.conditions,
		rent_sim.notifications
	)
	test.expect(
		not duplicate_rent.is_empty()
		and not duplicate_rent[0].success
		and duplicate_rent[0].error_code == "duplicate_rent",
		"同一租期重复结算被幂等键拒绝"
	)
	test.expect(rent_sim.ledger_consistency().success, "正常租金与重复拒绝后账本一致")
	test.finish(self, "V2.2 household")
