extends SceneTree
## No per-frame population scans, bounded histories and long-run smoke.
##
## Local runs retain the strict wall-clock budget. Shared CI runners receive a
## wider but still finite budget because download/extraction and host load can
## temporarily contend for CPU and disk. Structural limits and peak-hour work
## remain identical in both environments.

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
	var ci_run: bool = not OS.get_environment("CI").is_empty()
	var thirty_day_budget_msec: int = 30000 if ci_run else 10000
	var year_budget_msec: int = 180000 if ci_run else 90000
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "长期性能回归环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 performance guard")
		return
	var start_msec: int = Time.get_ticks_msec()
	simulation.run_days(30)
	var thirty_day_msec: int = Time.get_ticks_msec() - start_msec
	test.equal(simulation.v2_3_hours_processed, 30 * 24, "30 日权威小时完整推进")
	test.expect(
		thirty_day_msec < thirty_day_budget_msec,
		"30 日离线模拟在 %d 毫秒预算内完成" % thirty_day_budget_msec
	)
	simulation = null
	var year_simulation := V23ProductSimulationV2.new()
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
	test.expect(
		year_msec < year_budget_msec,
		"一年正式产品社会模拟在 %d 毫秒预算内完成" % year_budget_msec
	)
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
	test.expect(
		year_simulation.social_sandbox.event_ledger.size() <= 1024,
		"一年后社会事件账本保持上限"
	)
	test.expect(
		year_simulation.social_sandbox.tasks.size() <= 256
		and year_simulation.social_sandbox.intents.size() <= 256,
		"一年后社会任务与意图历史保持上限"
	)
	test.expect(
		year_simulation.social_sandbox.pending_reactions.size() <= 128,
		"一年后延迟反应队列保持上限"
	)
	test.expect(
		V23SaveService.new().validate_snapshot(
			V23SaveService.new().build_snapshot(year_simulation)
		).is_empty(),
		"一年状态仍可形成有效产品快照"
	)
	print(
		(
			"V2.3 performance: 30d=%dms/%dms 365d=%dms/%dms max_hour=%dus "
			+ "activities=%d messages=%d travel_plans=%d ci=%s"
		) % [
			thirty_day_msec, thirty_day_budget_msec,
			year_msec, year_budget_msec,
			year_simulation.maximum_hour_processing_usec,
			year_simulation.schedule.recent_completed_activities.size(),
			year_simulation.communication.messages.size(),
			year_simulation.travel_execution.travel_plans.size(),
			str(ci_run),
		]
	)
	test.finish(self, "V2.3 performance guard")


static func _source(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()
