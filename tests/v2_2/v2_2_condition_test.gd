extends SceneTree
## Activity effects, sleep, deficits, bounds and causal explanations.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "状态测试模拟可初始化")
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var before: Dictionary = simulation.conditions.get_state(pierre)
	simulation.conditions.apply_activity(pierre, "work", simulation.clock.total_hours)
	var after_work: Dictionary = simulation.conditions.get_state(pierre)
	test.equal(int(after_work.get("fatigue", 0)) - int(before.get("fatigue", 0)), 35, "工作1小时疲劳+35")
	test.equal(int(after_work.get("stress", 0)) - int(before.get("stress", 0)), 12, "工作1小时压力+12")
	simulation.conditions.apply_activity(pierre, "overtime", simulation.clock.total_hours + 1)
	var after_overtime: Dictionary = simulation.conditions.get_state(pierre)
	test.equal(int(after_overtime.get("fatigue", 0)) - int(after_work.get("fatigue", 0)), 55, "加班疲劳影响高于正常工作")
	simulation.conditions.apply_activity(pierre, "sleep", simulation.clock.total_hours + 2)
	var after_sleep: Dictionary = simulation.conditions.get_state(pierre)
	test.expect(int(after_sleep.get("fatigue", 0)) < int(after_overtime.get("fatigue", 0)), "睡眠降低疲劳")
	test.expect(int(after_sleep.get("stress", 0)) < int(after_overtime.get("stress", 0)), "睡眠降低压力")
	simulation.conditions.settle_food_need(pierre, true, simulation.clock.total_hours + 3)
	simulation.conditions.settle_food_need(pierre, true, simulation.clock.total_hours + 27)
	var deficit: Dictionary = simulation.conditions.get_state(pierre)
	test.equal(int(deficit.get("consecutive_food_deficit_days", 0)), 2, "连续食品不足计数达到2天")
	test.expect(int(deficit.get("health", 1000)) < int(after_sleep.get("health", 0)), "连续食品不足影响健康")
	simulation.conditions.settle_food_need(pierre, false, simulation.clock.total_hours + 51)
	test.equal(int(simulation.conditions.get_state(pierre).get("consecutive_food_deficit_days", -1)), 0, "恢复食品后连续缺口归零")
	simulation.set_condition(pierre, "fatigue", 1000)
	test.equal(int(simulation.conditions.get_state(pierre).get("fatigue", -1)), 1000, "状态上限为1000")
	var indicator: Dictionary = simulation.conditions.indicator(pierre, "fatigue", simulation.clock.total_hours + 51)
	test.equal(str(indicator.get("symbol", "")), "×", "疲劳950以上显示×")
	test.expect(not str(indicator.get("reason", "")).is_empty(), "状态悬停原因来自真实因果记录")
	test.finish(self, "V2.2 condition")
