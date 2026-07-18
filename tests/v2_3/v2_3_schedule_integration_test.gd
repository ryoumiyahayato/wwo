extends SceneTree
## Existing schedule integration and authoritative activity-location conditions.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "日程集成环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 schedule integration")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var schedule_records: Array = simulation.schedule.schedules[person_id] as Array
	var fixed_commute_count: int = 0
	var formal_travel_count: int = 0
	for raw_activity: Variant in schedule_records:
		var activity: Dictionary = raw_activity as Dictionary
		var activity_type: String = str(activity.get("activity_type", ""))
		if (
			activity_type in ["commute_to_work", "commute_home"]
			and str(activity.get("status", "")) in ["planned", "active"]
		):
			fixed_commute_count += 1
		if activity_type in V23LifeLoopSimulation.TRAVEL_TYPES:
			formal_travel_count += 1
	test.equal(fixed_commute_count, 0, "V2.2 固定通勤已从未来日程移除")
	test.expect(formal_travel_count > 0, "上下班已由正式路线活动替换")
	var start_hour: int = simulation.clock.total_hours + 12
	var created: V2LifeLoopResult = simulation.travel_execution.create_plan(
		person_id, "location_lille_wazemmes_market", "cheapest", start_hour,
		9999, 0
	)
	test.expect(created.success, "可为既有日程创建额外旅行")
	if not created.success:
		test.finish(self, "V2.3 schedule integration")
		return
	var plan: Dictionary = created.data.get("travel_plan", {}) as Dictionary
	var scheduled: V2LifeLoopResult = simulation.travel_execution.schedule_plan(
		str(plan.get("travel_plan_id", "")), simulation.schedule,
		simulation.clock.total_hours, "system"
	)
	test.expect(scheduled.success, "等待和旅行块原子写入同一个日程服务")
	if not scheduled.success:
		test.finish(self, "V2.3 schedule integration")
		return
	var blocks: Array = scheduled.data.get("scheduled_blocks", []) as Array
	test.expect(not blocks.is_empty(), "正式路线生成至少一个日程块")
	var committed_plan: Dictionary = scheduled.data.get("travel_plan", {}) as Dictionary
	var scheduled_ids: Array = committed_plan.get(
		"scheduled_activity_ids", []
	) as Array
	test.expect(not scheduled_ids.is_empty(), "旅行计划保存已写入的活动 ID")
	if scheduled_ids.is_empty():
		test.finish(self, "V2.3 schedule integration")
		return
	var first_activity_id: String = str(
		scheduled_ids[0]
	)
	var metadata_found: bool = false
	for raw_activity: Variant in simulation.schedule.schedules[person_id] as Array:
		var activity: Dictionary = raw_activity as Dictionary
		if str(activity.get("activity_id", "")) == first_activity_id:
			metadata_found = (
				str(activity.get("travel_plan_id", ""))
				== str(plan.get("travel_plan_id", ""))
				and int(activity.get("route_segment_index", -1)) == 0
			)
	test.expect(metadata_found, "日程块保留旅行计划与路段稳定关联")
	simulation.schedule.cancel_future_activity_types(
		person_id, V23LifeLoopSimulation.TRAVEL_TYPES,
		simulation.clock.total_hours, "location_authority_test"
	)
	simulation.spatial_locations.force_set_at_location(
		person_id, "location_lille_pierre_home", simulation.clock.total_hours
	)
	simulation.advance_hours(2)
	var attendance: Dictionary = simulation.employment.today_summary(
		person_id, simulation.clock.total_hours
	)
	test.expect(
		int(attendance.get("unauthorized_absence", 0)) >= 1,
		"人物不在工厂时即使日程写着工作也按缺勤结算"
	)
	test.finish(self, "V2.3 schedule integration")
