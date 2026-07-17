extends SceneTree
## Compound ledger writes, retained idempotency and priority schedule semantics.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_atomic_ledger_batch()
	_test_trimmed_ledger_idempotency()
	_test_schedule_terminal_status_and_system_priority()
	_test_organization_completion_time()
	test.finish(self, "V2.2 atomicity")


func _test_atomic_ledger_batch() -> void:
	var ledger := V2LedgerService.new()
	ledger.configure(32)
	var households: Dictionary = {
		"household:test": {
			"cash_centimes": 1000,
			"income_current_period_centimes": 0,
			"expense_current_period_centimes": 0,
			"recent_transaction_ids": [],
		}
	}
	ledger.register_household("household:test", 1000)
	var seed: V2LifeLoopResult = ledger.post(
		households, "household:test", "person:test", 0, "income", "seed",
		0, "test", "seed", "key:collision", "幂等碰撞种子"
	)
	test.expect(seed.success, "可建立已处理幂等键")
	var cash_before: int = int((households["household:test"] as Dictionary)["cash_centimes"])
	var count_before: int = ledger.transactions.size()
	var failed: V2LifeLoopResult = ledger.post_batch(
		households,
		[
			_entry("key:first", 200, "income", "salary"),
			_entry("key:collision", 80, "income", "allowance"),
		],
		"应当整体拒绝"
	)
	test.expect(not failed.success, "复合交易任一幂等键冲突时整体拒绝")
	test.equal(
		int((households["household:test"] as Dictionary)["cash_centimes"]),
		cash_before,
		"复合交易失败不改变现金"
	)
	test.equal(ledger.transactions.size(), count_before, "复合交易失败不写入部分账本")
	test.expect(not ledger.has_key("key:first"), "复合交易失败不消耗其他幂等键")

	var small_ledger := V2LedgerService.new()
	small_ledger.configure(32)
	var small_households: Dictionary = {
		"household:test": {
			"cash_centimes": 100,
			"income_current_period_centimes": 0,
			"expense_current_period_centimes": 0,
			"recent_transaction_ids": [],
		}
	}
	small_ledger.register_household("household:test", 100)
	var transient_negative: V2LifeLoopResult = small_ledger.post_batch(
		small_households,
		[
			_entry("key:expense:1", 80, "expense", "test_expense"),
			_entry("key:expense:2", 80, "expense", "test_expense"),
			_entry("key:income:later", 100, "income", "test_income"),
		],
		"不允许中途负现金"
	)
	test.expect(not transient_negative.success, "复合交易任何中间步骤都不能让现金为负")
	test.equal(
		int((small_households["household:test"] as Dictionary)["cash_centimes"]),
		100,
		"中途负现金批次整体回滚"
	)
	test.equal(small_ledger.transactions.size(), 0, "中途负现金批次不写入流水")

	var success: V2LifeLoopResult = ledger.post_batch(
		households,
		[
			_entry("key:salary", 1200, "income", "salary"),
			_entry("key:allowance", 80, "income", "allowance"),
		],
		"月薪与津贴到账"
	)
	test.expect(success.success, "合法复合交易整体成功")
	test.equal(
		int((households["household:test"] as Dictionary)["cash_centimes"]),
		cash_before + 1280,
		"复合交易一次增加全部金额"
	)
	test.equal(ledger.transactions.size(), count_before + 2, "复合交易保留两个工资组成项")
	test.expect(ledger.validate_balances(households).success, "复合交易后账本链一致")


func _test_trimmed_ledger_idempotency() -> void:
	var ledger := V2LedgerService.new()
	ledger.configure(32)
	var households: Dictionary = {
		"household:trim": {
			"cash_centimes": 0,
			"income_current_period_centimes": 0,
			"expense_current_period_centimes": 0,
			"recent_transaction_ids": [],
		}
	}
	ledger.register_household("household:trim", 0)
	for index: int in range(40):
		var result: V2LifeLoopResult = ledger.post(
			households, "household:trim", "person:trim", 1, "income", "test",
			index, "test", "event:%d" % index, "trim:key:%d" % index,
			"长期账本测试"
		)
		test.expect(result.success, "第 %d 笔长期交易成功" % index)
	test.equal(ledger.transactions.size(), 32, "账本展示历史按配置裁剪")
	test.expect(ledger.has_key("trim:key:0"), "裁剪展示历史不会重新开放旧交易幂等键")
	test.expect(ledger.validate_balances(households).success, "裁剪后起始余额与账本链一致")


func _test_schedule_terminal_status_and_system_priority() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "日程原子性模拟可初始化")
	if not simulation.initialized:
		return
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var rest_hour: int = V2DateTime.total_hour_from_iso("1900-03-12T19:00:00")
	var player_rest: V2LifeLoopResult = simulation.request_activity(
		pierre, "rest", rest_hour, 1
	)
	test.expect(player_rest.success, "空闲时段可安排玩家休息")
	var rest_id: String = str((player_rest.data.get("activity", {}) as Dictionary).get("activity_id", ""))
	test.expect(simulation.cancel_activity(pierre, rest_id).success, "未开始玩家休息可取消")
	var cancelled_visible: bool = false
	for segment: Dictionary in simulation.schedule.timeline_for_day(
		pierre, rest_hour, simulation.clock.total_hours
	):
		if str(segment.get("activity_id", "")) == rest_id:
			cancelled_visible = str(segment.get("display_status", "")) == "cancelled"
	test.expect(cancelled_visible, "日程时间线保留取消状态而不伪装成已完成")

	var union_hour: int = V2DateTime.total_hour_from_iso("1900-03-14T19:00:00")
	var union_result: V2LifeLoopResult = simulation.request_activity(
		pierre, "union_activity", union_hour, 2
	)
	test.expect(union_result.success, "可安排星期三工会例会")
	var forced: V2LifeLoopResult = simulation.schedule.schedule_rule_activity(
		pierre, "rest", union_hour, 2, "location:pierre_home", "system"
	)
	test.expect(forced.success, "强制健康休息可覆盖未来玩家活动")
	test.equal(
		str(simulation.schedule.activity_for_hour(pierre, union_hour).get("source", "")),
		"system",
		"系统健康安排在权威选择中高于玩家活动"
	)

	var two_hour_slot: int = simulation.schedule.find_available_hour(
		pierre,
		V2DateTime.total_hour_from_iso("1900-03-13T18:00:00"),
		V2DateTime.total_hour_from_iso("1900-03-14T06:00:00"),
		0,
		24,
		2
	)
	test.expect(two_hour_slot >= 0, "可按完整持续时间查找连续空闲时段")
	if two_hour_slot >= 0:
		for offset: int in range(2):
			test.equal(
				str(simulation.schedule.activity_for_hour(pierre, two_hour_slot + offset).get("source", "")),
				"default_routine",
				"连续空闲时段第 %d 小时没有合同或玩家冲突" % (offset + 1)
			)


func _test_organization_completion_time() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "组织完成校验模拟可初始化")
	if not simulation.initialized:
		return
	var invalid: V2LifeLoopResult = simulation.organizations.complete_activity(
		V2LifeLoopSimulation.PIERRE_ID,
		V2LifeLoopSimulation.UNION_ID,
		V2DateTime.total_hour_from_iso("1900-03-13T20:00:00"),
		"activity:invalid",
		simulation.notifications
	)
	test.expect(
		not invalid.success and invalid.error_code == "invalid_union_time",
		"工会活动完成时重新校验例会起始时间"
	)


static func _entry(
	key: String, amount: int, direction: String, category: String
) -> Dictionary:
	return {
		"household_id": "household:test",
		"person_id": "person:test",
		"amount_centimes": amount,
		"direction": direction,
		"category": category,
		"total_hour": 1,
		"source_entity_id": "source:test",
		"source_event_id": "event:test",
		"idempotency_key": key,
		"description": "测试交易",
	}
