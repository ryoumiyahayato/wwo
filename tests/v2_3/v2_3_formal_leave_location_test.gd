extends SceneTree
## Leave releases work obligations; travel and person UI use the same actual spatial state.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23FormalSimulation.new()
	test.expect(simulation.initialize(), "正式请假与位置测试环境可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 formal leave and location")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var suggestion: V2LifeLoopResult = simulation.suggest_next_activity(
		person_id, "authorized_leave"
	)
	test.expect(suggestion.success, "可找到下一段实际合同工作义务")
	var start_hour: int = int(suggestion.data.get("start_hour", -1))
	var duration: int = int(suggestion.data.get("duration_hours", 0))
	test.expect(start_hour >= simulation.clock.total_hours and duration > 0, "请假建议使用合同工时而非固定上午按钮")
	var leave_result: V2LifeLoopResult = simulation.request_activity(
		person_id, "authorized_leave", start_hour, duration
	)
	test.expect(leave_result.success, "正式请假申请可批准")
	var record: Dictionary = leave_result.data.get("leave_authorization", {}) as Dictionary
	test.expect(not record.is_empty(), "请假形成劳动义务豁免记录")
	test.expect(int(record.get("covered_hour_count", 0)) > 0, "豁免记录保存实际合同工时")
	var has_leave_activity: bool = false
	for raw_activity: Variant in simulation.schedule.schedules.get(person_id, []) as Array:
		var activity: Dictionary = raw_activity as Dictionary
		if (
			str(activity.get("activity_type", "")) == "authorized_leave"
			and str(activity.get("status", "")) in ["planned", "active"]
		):
			has_leave_activity = true
	test.expect(not has_leave_activity, "请假不生成占用时间的日程活动")
	for raw_hour: Variant in record.get("covered_contract_hours", []) as Array:
		var covered_hour: int = int(raw_hour)
		var selected: Dictionary = simulation.schedule.activity_for_hour(person_id, covered_hour)
		test.expect(
			str(selected.get("source", "")) != "contract",
			"被批准时段不再保留合同工作块：%s" % V2DateTime.iso_from_total_hour(covered_hour)
		)
	var travel_result: V2LifeLoopResult = simulation.request_travel(
		person_id, "location_lille_centre", "fastest", simulation.clock.total_hours + 1
	)
	test.expect(travel_result.success, "请假释放后可在原工作日程中安排旅行")
	var active_plan: Dictionary = travel_result.data.get(
		"travel_plan", {}
	) as Dictionary
	test.expect(
		not active_plan.is_empty()
		and str(active_plan.get("destination_id", ""))
		== "location_lille_centre",
		"旅行使用请求返回的正式计划而不是其他自动通勤计划"
	)
	var arrival_hour: int = int(
		active_plan.get(
			"expected_arrival_hour", simulation.clock.total_hours + 1
		)
	)
	simulation.advance_hours(arrival_hour - simulation.clock.total_hours)
	var position: Dictionary = simulation.spatial_locations.position_for(person_id)
	test.equal(str(position.get("current_location_id", "")), "location_lille_centre", "旅行完成后空间权威位于里尔市中心")
	test.equal(str(position.get("location_state", "")), "at_location", "到达后人物不再处于途中")
	var binding := V23FormalUiBinding.new(simulation, true)
	var person_view: Dictionary = binding.person_view(person_id)
	test.equal(str(person_view.get("current_location", "")), "里尔市中心", "人物概览读取实际空间位置")
	test.expect(
		str(person_view.get("current_work", "")).contains("里尔市中心")
		and not str(person_view.get("current_work", "")).contains("皮埃尔住所"),
		"当前活动摘要不再用默认日程地点覆盖实际位置"
	)
	var covered_end: int = int(record.get("end_hour", arrival_hour))
	if simulation.clock.total_hours < covered_end:
		simulation.advance_hours(covered_end - simulation.clock.total_hours)
	var covered_set: Dictionary = {}
	for raw_hour: Variant in record.get("covered_contract_hours", []) as Array:
		covered_set[int(raw_hour)] = true
	var leave_hours: int = 0
	for attendance: Dictionary in simulation.employment.attendance_records:
		if (
			str(attendance.get("person_id", "")) == person_id
			and bool(attendance.get("authorized_leave", false))
			and covered_set.has(int(attendance.get("total_hour", -1)))
		):
			leave_hours += 1
	test.equal(leave_hours, int(record.get("covered_hour_count", 0)), "被解除的合同工时按授权请假记入考勤")
	test.equal(simulation.employment.employment_risk(person_id), 0, "授权请假不产生无故缺勤风险")
	var save_service := V23SaveService.new()
	var snapshot: Dictionary = save_service.build_snapshot(simulation)
	test.equal(save_service.validate_snapshot(snapshot).size(), 0, "请假与实际位置快照通过校验")
	var restored := V23FormalSimulation.new()
	test.expect(restored.initialize(), "可建立正式恢复目标")
	test.expect(save_service.restore(snapshot, restored).success, "请假记录与实际位置可恢复")
	test.equal(
		str(restored.spatial_locations.position_for(person_id).get("current_location_id", "")),
		"location_lille_centre",
		"载入后实际位置仍为里尔市中心"
	)
	test.equal(restored.leave.records_for_person(person_id).size(), 1, "载入后保留一份请假豁免记录")

	var legacy := V23LifeLoopSimulation.new()
	test.expect(legacy.initialize(), "可建立旧 V2.3 占时请假存档")
	var legacy_start: int = V2DateTime.total_hour_from_iso("1900-03-12T07:00:00")
	test.expect(
		legacy.request_activity(person_id, "authorized_leave", legacy_start, 5).success,
		"旧实现可生成待迁移的占时请假活动"
	)
	var legacy_snapshot: Dictionary = save_service.build_snapshot(legacy)
	var migrated := V23FormalSimulation.new()
	test.expect(migrated.initialize(), "可建立旧存档迁移目标")
	test.expect(save_service.restore(legacy_snapshot, migrated).success, "旧占时请假存档可载入正式实现")
	var legacy_activity_remains: bool = false
	for raw_activity: Variant in migrated.schedule.schedules.get(person_id, []) as Array:
		if str((raw_activity as Dictionary).get("activity_type", "")) == "authorized_leave":
			legacy_activity_remains = true
	test.expect(not legacy_activity_remains, "旧存档中的请假活动块已被清除")
	test.equal(migrated.leave.records_for_person(person_id).size(), 1, "旧请假活动迁移为劳动义务豁免记录")

	var packed: PackedScene = load("res://scenes/v2_3/v2_3_life_loop_main.tscn") as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "正式场景可实例化")
	if view != null:
		root.add_child(view)
		await process_frame
		await process_frame
		test.expect(view.interface is V23FormalScheduleInterface, "正式场景使用不占时请假界面")
		view.queue_free()
		await process_frame
	test.finish(self, "V2.3 formal leave and location")
