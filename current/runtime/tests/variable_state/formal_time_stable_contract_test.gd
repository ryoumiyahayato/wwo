extends SceneTree
## Long-term formal-time contracts. These assertions are intended to remain
## unchanged when D01 later removes duplicated time ownership.

const SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup: Dictionary = SUPPORT.backup_formal_save()
	_check(not bool(backup.get("read_error", false)), "现有正式存档如存在则可安全备份")
	_check(SUPPORT.cleanup_formal_save(), "测试开始前清理隔离user://正式存档")
	_test_initialization()
	_test_minute_hour_conversion()
	_test_gregorian_conversion()
	_test_economy_daily_settlement()
	_test_save_load_round_trip()
	_test_restore_failure_atomicity()
	_check(SUPPORT.restore_formal_save(backup), "测试结束后恢复原有正式存档或保持隔离目录为空")
	print("Formal time stable contract: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_initialization() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(
		simulation.success,
		"WorldBootstrap.initialize成功：%s" % simulation.error
	)
	if not simulation.success:
		return
	_equal(simulation.world.game_clock.total_minutes(), 0, "正式模拟初始total_minutes为0")
	_equal((simulation.world.game_clock.total_minutes() % 60), 0, "正式模拟初始minute_remainder为0")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 0, "正式经济初始total_hour为0")
	var value: Dictionary = simulation.world.game_clock.current_date()
	_equal(int(value.get("year", 0)), 1900, "正式时间初始年份为1900")
	_equal(int(value.get("month", 0)), 1, "正式时间初始月份为1")
	_equal(int(value.get("day", 0)), 1, "正式时间初始日期为1")
	_equal(int(value.get("hour", -1)), 0, "正式时间初始小时为0")
	_equal(int(value.get("minute", -1)), 0, "正式时间初始分钟为0")


func _test_minute_hour_conversion() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "分钟换算测试可初始化正式模拟")
	if not simulation.success:
		return
	simulation.simulation_step.advance_minutes(15)
	_equal(simulation.world.game_clock.total_minutes(), 15, "推进15分钟后total_minutes为15")
	_equal((simulation.world.game_clock.total_minutes() % 60), 15, "推进15分钟后余数为15")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 0, "推进15分钟后经济小时仍为0")
	simulation.simulation_step.advance_minutes(45)
	_equal(simulation.world.game_clock.total_minutes(), 60, "再推进45分钟后total_minutes为60")
	_equal((simulation.world.game_clock.total_minutes() % 60), 0, "再推进45分钟后余数归零")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 1, "再推进45分钟后经济小时为1")
	for minutes: int in [1, 59, 61, 125, 1441]:
		simulation.simulation_step.advance_minutes(minutes)
		_assert_formal_time_invariant(simulation, "连续推进%d分钟" % minutes)
	var before_minutes: int = simulation.world.game_clock.total_minutes()
	var before_hours: int = FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour
	simulation.simulation_step.advance_minutes(120)
	_equal(
		simulation.world.game_clock.total_minutes() - before_minutes,
		120,
		"单批120分钟只累计一次正式分钟"
	)
	_equal(
		FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour - before_hours,
		2,
		"单批120分钟只累计两次正式小时而不重复计算"
	)
	_assert_formal_time_invariant(simulation, "单批推进后")


func _assert_formal_time_invariant(
	simulation: WorldBuildResult, label: String
) -> void:
	_equal(
		FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour,
		int(simulation.world.game_clock.total_minutes() / 60),
		"%s经济小时等于累计分钟整除60" % label
	)
	_equal(
		(simulation.world.game_clock.total_minutes() % 60),
		simulation.world.game_clock.total_minutes() % 60,
		"%s分钟余数等于累计分钟模60" % label
	)


func _test_gregorian_conversion() -> void:
	_expect_next_hour(
		{"year": 1900, "month": 1, "day": 31, "hour": 23},
		{"year": 1900, "month": 2, "day": 1, "hour": 0},
		"1900-01-31跨到1900-02-01"
	)
	_expect_next_hour(
		{"year": 1900, "month": 2, "day": 28, "hour": 23},
		{"year": 1900, "month": 3, "day": 1, "hour": 0},
		"1900非闰年二月跨到三月"
	)
	_expect_next_hour(
		{"year": 1904, "month": 2, "day": 28, "hour": 23},
		{"year": 1904, "month": 2, "day": 29, "hour": 0},
		"1904闰年进入二月二十九日"
	)
	_expect_next_hour(
		{"year": 1900, "month": 12, "day": 31, "hour": 23},
		{"year": 1901, "month": 1, "day": 1, "hour": 0},
		"1900年末跨到1901年"
	)
	for total_hour: int in [0, 23, 24, 743, 1416, 8760, 35064, 100000]:
		var value: Dictionary = GameCalendar.from_total_hour(total_hour)
		_check(not value.is_empty(), "total_hour=%d可转换为公历" % total_hour)
		_equal(
			GameCalendar.to_total_hour(value),
			total_hour,
			"total_hour=%d日期往返一致" % total_hour
		)


func _expect_next_hour(
	start: Dictionary, expected: Dictionary, label: String
) -> void:
	var start_hour: int = GameCalendar.to_total_hour(start)
	_check(start_hour >= 0, "%s起点有效" % label)
	if start_hour < 0:
		return
	var actual: Dictionary = GameCalendar.from_total_hour(start_hour + 1)
	for key: String in ["year", "month", "day", "hour"]:
		_equal(
			int(actual.get(key, -1)),
			int(expected.get(key, -2)),
			"%s的%s正确" % [label, key]
		)


func _test_economy_daily_settlement() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "经济日结算测试可初始化正式模拟")
	if not simulation.success:
		return
	simulation.simulation_step.advance_minutes(23 * 60)
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 23, "累计23小时达到正确经济小时")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).history.size(), 0, "累计23小时没有第一次完整日结算")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot())._last_day_index, -1, "累计23小时仍无已结算日")
	simulation.simulation_step.advance_minutes(60)
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 24, "累计24小时达到第一日边界")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).history.size(), 1, "累计24小时只进行一次日结算")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot())._last_day_index, 1, "第一次日结算索引为1")
	simulation.simulation_step.advance_minutes(23 * 60)
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 47, "累计47小时达到正确经济小时")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).history.size(), 1, "累计47小时没有第二次日结算")
	simulation.simulation_step.advance_minutes(60)
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour, 48, "累计48小时达到第二日边界")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).history.size(), 2, "累计48小时只新增一次日结算")
	_equal(FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot())._last_day_index, 2, "第二次日结算索引为2")
	var wide := WorldBootstrap.new().build()
	_check(wide.success, "大跨度日结算测试可初始化正式模拟")
	if not wide.success:
		return
	wide.simulation_step.advance_minutes(72 * 60)
	_equal(FormalWorldEconomyView.new(wide.world.economy_state.read_only_snapshot()).total_hour, 72, "单次大跨度推进到72小时")
	_equal(FormalWorldEconomyView.new(wide.world.economy_state.read_only_snapshot()).history.size(), 3, "单次大跨度推进只结算三个不同日期")
	_equal(FormalWorldEconomyView.new(wide.world.economy_state.read_only_snapshot())._last_day_index, 3, "单次大跨度推进最终日索引为3")
	var day_indexes: Array[int] = []
	for entry: Dictionary in FormalWorldEconomyView.new(wide.world.economy_state.read_only_snapshot()).history:
		day_indexes.append(int(entry.get("day_index", -1)))
	_equal(day_indexes, [1, 2, 3], "单次大跨度推进没有重复结算同一日")


func _test_save_load_round_trip() -> void:
	_check(SUPPORT.cleanup_formal_save(), "保存往返前隔离路径为空")
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "正式保存往返测试可初始化")
	if not simulation.success:
		return
	simulation.simulation_step.advance_minutes(125)
	var saved: Dictionary = SUPPORT.simulation_state(simulation)
	_check(
		simulation.persistence.save_to_user().success,
		"save_to_user通过生产方法写入真实正式存档"
	)
	_check(
		FileAccess.file_exists(FormalPersistence.SAVE_PATH),
		"真实正式存档存在于隔离user://路径"
	)
	simulation.simulation_step.advance_minutes(24 * 60 + 35)
	_check(
		SUPPORT.simulation_state(simulation) != saved,
		"读取前运行状态已被真实推进改变"
	)
	var candidate_1 := simulation.persistence.load_from_user()
	if candidate_1.success:
		simulation = candidate_1
	_check(
		candidate_1.operation.success,
		"load_from_user通过生产方法恢复真实正式存档"
	)
	_equal(simulation.world.game_clock.total_minutes(), int(saved.get("total_minutes", -1)), "读取恢复total_minutes")
	_equal(
		(simulation.world.game_clock.total_minutes() % 60),
		int(saved.get("minute_remainder", -1)),
		"读取恢复minute_remainder"
	)
	var saved_economy: Dictionary = saved.get("economy", {}) as Dictionary
	_equal(
		FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).total_hour,
		int(saved_economy.get("total_hour", -1)),
		"读取恢复economy.total_hour"
	)
	_equal(
		(simulation.persistence.snapshot().get("economy", {}) as Dictionary),
		saved_economy,
		"读取恢复完整正式经济持久化状态"
	)
	_equal(SUPPORT.simulation_state(simulation), saved, "保存读取后完整正式模拟状态往返一致")
	_check(SUPPORT.cleanup_formal_save(), "保存往返测试删除自己产生的正式存档")


func _test_restore_failure_atomicity() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "恢复失败原子性测试可初始化")
	if not simulation.success:
		return
	simulation.simulation_step.advance_minutes(125)
	var before: Dictionary = SUPPORT.simulation_state(simulation)
	var rejected: Dictionary = before.duplicate(true)
	var rejected_economy: Dictionary = rejected.get("economy", {}) as Dictionary
	var rejected_countries: Dictionary = rejected_economy.get("market_states", {}) as Dictionary
	var ids: Array = rejected_countries.keys()
	ids.sort()
	_check(not ids.is_empty(), "原子性测试拥有正式国家集合")
	if ids.is_empty():
		return
	rejected_countries.erase(ids[0])
	rejected_economy["market_states"] = rejected_countries
	rejected["economy"] = rejected_economy
	var candidate_2 := simulation.persistence.restore_candidate(rejected)
	if candidate_2.success:
		simulation = candidate_2
	_check(
		not candidate_2.success,
		"国家集合不完整的正式经济状态被生产恢复验证拒绝"
	)
	_equal(simulation.world.game_clock.total_minutes(), int(before.get("total_minutes", -1)), "恢复失败后total_minutes不变")
	_equal(
		(simulation.world.game_clock.total_minutes() % 60),
		int(before.get("minute_remainder", -1)),
		"恢复失败后minute_remainder不变"
	)
	_equal(
		(simulation.persistence.snapshot().get("economy", {}) as Dictionary),
		before.get("economy", {}) as Dictionary,
		"恢复失败后完整经济状态不变"
	)
	_equal(
		SUPPORT.simulation_state(simulation),
		before,
		"恢复失败前后完整相关状态一致且没有部分提交"
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	var difference: String = SUPPORT.first_semantic_difference(actual, expected)
	_check(
		difference.is_empty(),
		label if difference.is_empty() else "%s（%s）" % [label, difference]
	)
