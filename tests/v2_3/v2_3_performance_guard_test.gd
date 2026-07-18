extends SceneTree
## No per-frame population scans, bounded histories and long-run smoke.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation_source: String = _source(
		"res://scripts/v2_3/v2_3_life_loop_simulation.gd"
	)
	var npc_source: String = _source(
		"res://scripts/v2_3/spatial_npc_routine_service.gd"
	)
	test.expect(
		not simulation_source.contains("func _process(")
		and not simulation_source.contains("func _physics_process("),
		"V2.3 模拟不在每帧入口遍历人物"
	)
	test.expect(
		not npc_source.contains("func _process(")
		and not npc_source.contains("func _physics_process("),
		"NPC 空间规划不绑定渲染帧"
	)
	test.expect(
		not simulation_source.contains("PrototypeV2MapCanvas"),
		"生活模拟不反向引用地图画布"
	)
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "长期性能回归环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 performance guard")
		return
	var start_msec: int = Time.get_ticks_msec()
	simulation.run_days(30)
	var thirty_day_msec: int = Time.get_ticks_msec() - start_msec
	test.equal(simulation.v2_3_hours_processed, 30 * 24, "30 日权威小时完整推进")
	test.expect(thirty_day_msec < 10000, "30 日离线模拟在回归预算内完成")
	simulation = null
	var year_simulation := V23LifeLoopSimulation.new()
	test.expect(year_simulation.initialize(), "一年模拟独立环境初始化")
	var year_start_msec: int = Time.get_ticks_msec()
	for day_index: int in range(365):
		year_simulation.run_days(1)
		if (day_index + 1) % 30 == 0:
			print(
				"V2.3 year progress: %d days, %dms" % [
					day_index + 1,
					Time.get_ticks_msec() - year_start_msec,
				]
			)
	var year_msec: int = Time.get_ticks_msec() - year_start_msec
	test.equal(
		year_simulation.v2_3_hours_processed, 365 * 24,
		"一年权威小时完整推进"
	)
	test.expect(year_msec < 30000, "一年离线模拟在回归预算内完成")
	test.expect(
		year_simulation.schedule.recent_completed_activities.size() <= 256,
		"已完成活动历史保持上限"
	)
	test.expect(
		year_simulation.communication.messages.size() <= 256,
		"消息历史保持上限"
	)
	test.expect(
		year_simulation.travel_execution.travel_plans.size() <= 128,
		"旅行计划历史保持上限"
	)
	test.expect(
		year_simulation.maximum_hour_processing_usec < 500000,
		"单小时结算无异常全世界深度扫描"
	)
	print(
		(
			"V2.3 performance: 30d=%dms 365d=%dms max_hour=%dus "
			+ "activities=%d messages=%d travel_plans=%d"
		) % [
			thirty_day_msec, year_msec,
			year_simulation.maximum_hour_processing_usec,
			year_simulation.schedule.recent_completed_activities.size(),
			year_simulation.communication.messages.size(),
			year_simulation.travel_execution.travel_plans.size(),
		]
	)
	test.finish(self, "V2.3 performance guard")


static func _source(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()
