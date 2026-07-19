extends SceneTree
## Three-year unattended world, bounded histories and measured Alpha targets.

const TEST_PATH: String = "user://tests/alpha_three_year_performance.json"

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	var runner := AlphaScenarioRunner.new()
	var result: Dictionary = runner.run("three_year_unattended_world")
	test.expect(
		bool(result.get("success", false)),
		"三年无人干预世界跨系统闭环通过"
	)
	if not bool(result.get("success", false)):
		push_error(JSON.stringify(result, "\t"))
		test.finish(self, "Alpha three-year performance")
		return
	var simulation: AlphaSimulationService = runner.last_simulation
	test.expect(simulation != null, "三年场景保留性能核验目标")
	var trace: Array = result.get("trace", []) as Array
	var world_fact: Dictionary = trace.back() as Dictionary
	var world_data: Dictionary = world_fact.get("data", {}) as Dictionary
	var performance: Dictionary = world_data.get(
		"performance", {}
	) as Dictionary
	var thirty_day_usec: int = int(performance.get("thirty_day_usec", 0))
	var year_usec: int = int(performance.get("year_usec", 0))
	var three_year_usec: int = int(performance.get("three_year_usec", 0))
	test.expect(
		thirty_day_usec <= 5_000_000,
		"30 日无人模拟不超过 5 秒：%dµs" % thirty_day_usec
	)
	test.expect(
		year_usec <= 45_000_000,
		"365 日无人模拟不超过 45 秒：%dµs" % year_usec
	)
	test.expect(
		three_year_usec <= 150_000_000,
		"三年无人模拟不超过 150 秒：%dµs" % three_year_usec
	)
	test.expect(
		simulation.alpha_maximum_hour_usec <= 250_000,
		"单个游戏小时最坏处理不超过 250ms：%dµs"
		% simulation.alpha_maximum_hour_usec
	)
	test.equal(
		simulation.alpha_hours_processed,
		3 * 365 * 24,
		"三年权威小时全部处理且中途恢复不重置历史"
	)
	test.expect(
		simulation.alpha_ai.decisions.size() <= AlphaAiService.HISTORY_LIMIT,
		"AI 决定历史保持固定上限"
	)
	test.expect(
		simulation.world_dynamics.events.size()
		<= AlphaWorldDynamicsService.EVENT_LIMIT,
		"世界事件历史保持固定上限"
	)
	test.expect(
		simulation.economy.external_events.size() <= 128,
		"市场外部事件历史保持固定上限"
	)
	test.expect(
		bool(simulation.validate_alpha_integrity().get("success", false)),
		"三年后统一引用与账本仍闭合"
	)
	var service := AlphaSaveService.new()
	var save_started_usec: int = Time.get_ticks_usec()
	var saved: SaveOperationResult = service.save(simulation, TEST_PATH)
	var save_usec: int = Time.get_ticks_usec() - save_started_usec
	test.expect(saved.success, "三年世界可原子保存")
	var absolute_path: String = ProjectSettings.globalize_path(TEST_PATH)
	var save_file := FileAccess.open(TEST_PATH, FileAccess.READ)
	var save_size_bytes: int = 0 if save_file == null else save_file.get_length()
	if save_file != null:
		save_file.close()
	var load_started_usec: int = Time.get_ticks_usec()
	var loaded: SaveOperationResult = service.load(TEST_PATH)
	var target := AlphaSimulationService.new()
	var target_initialized: bool = target.initialize()
	var restored: SaveOperationResult = (
		service.restore(loaded.snapshot, target)
		if loaded.success and target_initialized
		else SaveOperationResult.fail("load_target_failed", "")
	)
	var load_usec: int = Time.get_ticks_usec() - load_started_usec
	test.expect(loaded.success and restored.success, "三年世界可校验并完整载入")
	test.expect(
		save_usec <= 5_000_000,
		"三年世界存档不超过 5 秒：%dµs" % save_usec
	)
	test.expect(
		load_usec <= 8_000_000,
		"三年世界载入和事务恢复不超过 8 秒：%dµs" % load_usec
	)
	test.equal(
		target.clock.total_hours,
		simulation.clock.total_hours,
		"最终载入保持权威时间"
	)
	test.expect(
		not FileAccess.file_exists(TEST_PATH + ".tmp"),
		"性能存档不遗留临时文件"
	)
	var peak_memory_bytes: int = OS.get_static_memory_peak_usage()
	var counts: Dictionary = simulation.alpha_counts()
	var dynamics_counters: Dictionary = simulation.world_dynamics.counters
	print(
		(
			"ALPHA_PERFORMANCE 30d=%dus 365d=%dus 3y=%dus "
			+ "max_hour=%dus save=%dus load=%dus peak_memory=%dB "
			+ "save_size=%dB active=%d background=%d enterprises=%d "
			+ "organizations=%d contracts=%d debts=%d matters=%d events=%d"
			+ " job_changes=%d migrations=%d bankruptcies=%d defaults=%d policies=%d"
		) % [
			thirty_day_usec,
			year_usec,
			three_year_usec,
			simulation.alpha_maximum_hour_usec,
			save_usec,
			load_usec,
			peak_memory_bytes,
			save_size_bytes,
			int(counts.get("active_people", 0)),
			int(counts.get("background_people", 0)),
			int(counts.get("enterprises", 0)),
			int(counts.get("organizations", 0)),
			int(counts.get("contracts", 0)),
			int(counts.get("debts", 0)),
			int(counts.get("unfinished_matters", 0)),
			int(counts.get("event_history", 0)),
			int(dynamics_counters.get("background_job_changes", 0)),
			int(dynamics_counters.get("background_migrations", 0)),
			int(dynamics_counters.get("enterprise_bankruptcies", 0)),
			int(dynamics_counters.get("loan_defaults", 0)),
			int(dynamics_counters.get("policy_changes", 0)),
		]
	)
	_cleanup()
	test.finish(self, "Alpha three-year performance")


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
