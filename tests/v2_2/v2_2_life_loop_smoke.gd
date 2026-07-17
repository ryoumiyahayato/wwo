extends SceneTree
## Full V2.2 service and 30-day unattended-life smoke.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "V2.2 生活模拟可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.2 life loop smoke")
		return
	test.equal(simulation.clock.total_hours, V2DateTime.total_hour_from_iso("1900-03-12T05:00:00"), "起始时间为 1900-03-12 05:00")
	test.equal(int(V2DateTime.from_total_hour(simulation.clock.total_hours)["weekday"]), 0, "1900-03-12 为星期一")
	test.equal(simulation.person_states.size(), 2, "正式模拟同时包含两个人物")
	test.equal(simulation.selected_person_id, V2LifeLoopSimulation.PIERRE_ID, "默认观察人物为皮埃尔")
	for person_id: String in [V2LifeLoopSimulation.PIERRE_ID, V2LifeLoopSimulation.ALBERT_ID]:
		test.expect(simulation.schedule.get_future_horizon(person_id, simulation.clock.total_hours) >= 48, "%s 具有未来48小时日程" % person_id)
		test.expect(not simulation.schedule.activity_for_hour(person_id, simulation.clock.total_hours).is_empty(), "%s 当前小时有唯一活动" % person_id)
	var initial_albert: Dictionary = simulation.get_person_state(V2LifeLoopSimulation.ALBERT_ID)
	var switch_time: int = simulation.clock.total_hours
	test.expect(simulation.select_person(V2LifeLoopSimulation.ALBERT_ID).success, "评审模式可切换到阿尔贝")
	test.equal(simulation.clock.total_hours, switch_time, "切换观察人物不重置时间")
	test.equal(simulation.get_person_state(V2LifeLoopSimulation.ALBERT_ID), initial_albert, "切换观察人物不重置阿尔贝状态")
	simulation.select_person(V2LifeLoopSimulation.PIERRE_ID)
	var uncovered_person_hours: int = 0
	var first_uncovered: Array[String] = []
	for _hour: int in range(720):
		for person_id: String in [
			V2LifeLoopSimulation.PIERRE_ID,
			V2LifeLoopSimulation.ALBERT_ID,
		]:
			if simulation.schedule.activity_for_hour(
				person_id, simulation.clock.total_hours
			).is_empty():
				uncovered_person_hours += 1
				if first_uncovered.size() < 8:
					first_uncovered.append(
						"%s@%s" % [
							person_id,
							V2DateTime.iso_from_total_hour(
								simulation.clock.total_hours
							),
						]
					)
		simulation.advance_hours(1)
	test.equal(simulation.clock.total_hours, switch_time + 720, "无操作连续运行30日不漏小时")
	test.equal(simulation.hours_processed, 720, "30日逐小时结算720次")
	test.equal(uncovered_person_hours, 0, "30日内两人物每个小时都有唯一主要活动")
	if uncovered_person_hours > 0:
		print("FIRST_UNCOVERED: %s" % ", ".join(first_uncovered))
	test.expect(simulation.ledger_consistency().success, "30日后现金与账本一致")
	test.expect((simulation.households.household_for_person(V2LifeLoopSimulation.PIERRE_ID).get("cash_centimes", -1) as int) >= 0, "皮埃尔现金不为负数")
	test.expect((simulation.households.household_for_person(V2LifeLoopSimulation.ALBERT_ID).get("cash_centimes", -1) as int) >= 0, "阿尔贝现金不为负数")
	test.expect(simulation.employment.processed_pay_period_ids.size() >= 5, "30日内周薪和月薪均形成幂等结算")
	test.expect(simulation.households.processed_idempotency_keys.size() >= 60, "两住户日消费和房租均持久记录幂等键")
	for person_id: String in [V2LifeLoopSimulation.PIERRE_ID, V2LifeLoopSimulation.ALBERT_ID]:
		var condition: Dictionary = simulation.conditions.get_state(person_id)
		for stat: String in ["health", "fatigue", "stress"]:
			test.expect(int(condition.get(stat, -1)) >= 0 and int(condition.get(stat, 1001)) <= 1000, "%s 的 %s 保持0—1000" % [person_id, stat])
		test.expect(simulation.schedule.get_future_horizon(person_id, simulation.clock.total_hours) >= 24, "%s 30日后仍有可解释未来日程" % person_id)
	test.expect(simulation.notifications.notifications.size() <= 160, "通知历史有界且不会无限刷屏")
	test.expect(simulation.conditions.causal_events.size() <= 512, "因果历史有界")
	test.expect(simulation.schedule.recent_completed_activities.size() <= 256, "完成活动历史有界")
	test.expect(load("res://scenes/v2_2/v2_2_life_loop_main.tscn") is PackedScene, "唯一 V2.2 评审场景可加载")
	test.finish(self, "V2.2 life loop smoke")
