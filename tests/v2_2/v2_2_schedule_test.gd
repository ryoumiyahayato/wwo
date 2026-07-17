extends SceneTree
## Schedule priority, conflict, cross-midnight and review-person switching.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "日程测试模拟可初始化")
	var now: int = simulation.clock.total_hours
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now).get("activity_type", "")), "sleep", "05:00 正在睡眠")
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now + 1).get("activity_type", "")), "commute_to_work", "06:00 开始通勤")
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now + 2).get("activity_type", "")), "work", "07:00 开始工作")
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now + 7).get("activity_type", "")), "meal_break", "12:00 午间休息")
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now + 8).get("activity_type", "")), "work", "13:00 恢复工作")
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now + 12).get("activity_type", "")), "commute_home", "17:00 通勤回家")
	test.expect(not simulation.request_activity(pierre, "rest", now - 1, 1).success, "不能安排过去活动")
	test.expect(not simulation.request_activity(pierre, "rest", now + 2, 1).success, "普通休息不能覆盖合同工作")
	var leave: V2LifeLoopResult = simulation.request_activity(pierre, "authorized_leave", now + 2, 5)
	test.expect(leave.success, "未来7日内上午无薪请假可安排")
	test.equal(str(simulation.schedule.activity_for_hour(pierre, now + 2).get("activity_type", "")), "authorized_leave", "玩家请假优先于合同工作")
	var leave_id: String = str((leave.data.get("activity", {}) as Dictionary).get("activity_id", ""))
	test.expect(simulation.cancel_activity(pierre, leave_id).success, "未开始玩家活动可取消")
	var sleep: V2LifeLoopResult = simulation.request_activity(pierre, "sleep", _next_hour(now, 22), 8)
	test.expect(sleep.success, "跨午夜8小时睡眠可作为连续活动安排")
	test.equal(int((sleep.data.get("activity", {}) as Dictionary).get("end_hour", 0)) - int((sleep.data.get("activity", {}) as Dictionary).get("start_hour", 0)), 8, "跨午夜睡眠持续时间正确")
	var sunday_hour: int = V2DateTime.total_hour_from_iso("1900-03-18T08:00:00")
	test.expect(not simulation.employment.is_required_work_hour(pierre, sunday_hour), "星期日没有皮埃尔合同工作义务")
	var before_schedule: Dictionary = simulation.schedule.get_persistent_state()
	simulation.select_person(V2LifeLoopSimulation.ALBERT_ID)
	test.equal(simulation.schedule.get_persistent_state(), before_schedule, "切换观察人物不重置任何人物日程")
	simulation.select_person(pierre)
	var cancellable: V2LifeLoopResult = simulation.request_activity(
		pierre, "rest", now + 14, 1
	)
	test.expect(cancellable.success, "未来空闲时段可安排玩家休息")
	var cancellable_id: String = str(
		(cancellable.data.get("activity", {}) as Dictionary).get("activity_id", "")
	)
	simulation.advance_hours(14)
	var started_cancel: V2LifeLoopResult = simulation.cancel_activity(
		pierre, cancellable_id
	)
	test.expect(
		not started_cancel.success and started_cancel.error_code == "activity_started",
		"已经开始的玩家活动不能取消"
	)
	var invalid_state: Dictionary = simulation.schedule.get_persistent_state()
	var pierre_schedule: Array = (
		(invalid_state.get("schedules", {}) as Dictionary).get(pierre, []) as Array
	)
	if not pierre_schedule.is_empty():
		pierre_schedule.append((pierre_schedule[0] as Dictionary).duplicate(true))
	test.expect(
		not simulation.schedule.restore_persistent_state(invalid_state),
		"恢复时拒绝全局重复活动ID"
	)
	test.finish(self, "V2.2 schedule")


func _next_hour(start_hour: int, target: int) -> int:
	for candidate: int in range(start_hour, start_hour + 48):
		if int(V2DateTime.from_total_hour(candidate)["hour"]) == target:
			return candidate
	return -1
