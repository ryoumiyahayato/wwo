extends SceneTree
## Long-term formal-time consistency checks replacing the former defect
## characterization. Formal product time has one writable authority.

const SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup: Dictionary = SUPPORT.backup_formal_save()
	_check(not bool(backup.get("read_error", false)), "现有正式存档如存在则可安全备份")
	_check(SUPPORT.cleanup_formal_save(), "一致性测试开始前清理隔离user://正式存档")
	_test_gregorian_formal_calendar()
	_test_inconsistent_persistent_time_is_rejected()
	_test_economy_restore_day_boundaries()
	_test_legacy_save_time_compatibility()
	_check(SUPPORT.restore_formal_save(backup), "一致性测试结束后恢复原有存档或保持隔离目录为空")
	print("Formal time known defects: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_gregorian_formal_calendar() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "正式公历测试可初始化")
	if not simulation.success:
		return
	var february_end_hour := GameCalendar.to_total_hour({
		"year": 1900,
		"month": 2,
		"day": 28,
		"hour": 23,
	})
	_check(february_end_hour >= 0, "1900-02-28 23:00是有效公历时间")
	simulation.simulation_step.advance_minutes(february_end_hour * 60 + 45)
	_equal(simulation.world.game_clock.current_date(), {
		"year": 1900,
		"month": 2,
		"day": 28,
		"hour": 23,
		"weekday": 2,
		"minute": 45,
	}, "正式时间到达1900-02-28 23:45")
	simulation.simulation_step.advance_minutes(15)
	var value := simulation.world.game_clock.current_date()
	_equal(int(value.get("year", 0)), 1900, "二月月末后年份仍为1900")
	_equal(int(value.get("month", 0)), 3, "1900非闰年二月后进入三月")
	_equal(int(value.get("day", 0)), 1, "1900-02-28后直接进入三月一日")
	_equal(int(value.get("hour", -1)), 0, "跨月后小时归零")
	_equal(int(value.get("minute", -1)), 0, "跨月后分钟归零")
	_check(GameCalendar.to_total_hour({"year": 1900, "month": 2, "day": 29, "hour": 0}) < 0, "1900-02-29始终无效")


func _test_inconsistent_persistent_time_is_rejected() -> void:
	_check(SUPPORT.cleanup_formal_save(), "矛盾存档测试前隔离存档为空")
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "矛盾存档拒绝测试可初始化")
	if not simulation.success:
		return
	simulation.simulation_step.advance_minutes(125)
	var before := SUPPORT.simulation_state(simulation)

	var wrong_remainder := before.duplicate(true)
	wrong_remainder["minute_remainder"] = 6
	_assert_rejected_without_mutation(simulation, wrong_remainder, before, "分钟余数与权威分钟矛盾")

	var wrong_hour := before.duplicate(true)
	var wrong_economy := wrong_hour.get("economy", {}) as Dictionary
	wrong_economy["total_hour"] = 99
	wrong_hour["economy"] = wrong_economy
	_assert_rejected_without_mutation(simulation, wrong_hour, before, "经济小时与权威分钟矛盾")

	var missing_authority := before.duplicate(true)
	missing_authority.erase("total_minutes")
	_assert_rejected_without_mutation(simulation, missing_authority, before, "V2存档缺少权威分钟")

	var file := FileAccess.open(FormalPersistence.SAVE_PATH, FileAccess.WRITE)
	_check(file != null, "可写入损坏时间存档测试文件")
	if file != null:
		file.store_string(JSON.stringify(wrong_hour))
		file.close()
	var candidate_1 := simulation.persistence.load_from_user()
	if candidate_1.success:
		simulation = candidate_1
	_check(not candidate_1.operation.success, "真实磁盘读取拒绝矛盾时间字段")
	_equal(SUPPORT.simulation_state(simulation), before, "磁盘恢复失败前后完整状态相等")
	_check(SUPPORT.cleanup_formal_save(), "矛盾存档测试删除自己产生的存档")


func _test_economy_restore_day_boundaries() -> void:
	var simulation := WorldBootstrap.new().build()
	_check(simulation.success, "经济日结边界恢复测试可初始化")
	if not simulation.success:
		return
	var previous_total_hour := 0
	for boundary: Dictionary in [
		{"total_hour": 0, "last_day_index": -1},
		{"total_hour": 23, "last_day_index": -1},
		{"total_hour": 24, "last_day_index": 1},
		{"total_hour": 25, "last_day_index": 1},
		{"total_hour": 48, "last_day_index": 2},
	]:
		var total_hour := int(boundary.get("total_hour", 0))
		var expected_last_day_index := int(boundary.get("last_day_index", -99))
		if total_hour > previous_total_hour:
			simulation.simulation_step.advance_minutes((total_hour - previous_total_hour) * 60)
		previous_total_hour = total_hour
		var saved_world := simulation.persistence.snapshot()
		var saved := saved_world.get("economy", {}) as Dictionary
		_equal(
			int(saved.get("last_day_index", -99)),
			expected_last_day_index,
			"%d小时持久状态日结索引为%d" % [
				total_hour, expected_last_day_index,
			]
		)
		var candidate_2 := simulation.persistence.restore_candidate(saved_world)
		if candidate_2.success:
			simulation = candidate_2
		_check(
			candidate_2.success,
			"%d小时合法经济状态可恢复" % total_hour
		)
		_equal(
			int(
				(simulation.persistence.snapshot().get("economy", {}) as Dictionary).get(
					"last_day_index", -99
				)
			),
			expected_last_day_index,
			"%d小时恢复后日结索引保持%d" % [
				total_hour, expected_last_day_index,
			]
		)
		if total_hour == 23:
			var legacy_world := saved_world.duplicate(true)
			var legacy := simulation.world.economy_state.legacy_regression_snapshot()
			legacy["schema_id"] = "formal_world_economy_state_v1"
			legacy.erase("last_day_index")
			legacy_world["economy"] = legacy
			var candidate_3 := simulation.persistence.restore_candidate(legacy_world)
			if candidate_3.success:
				simulation = candidate_3
			_check(
				candidate_3.success,
				"23小时旧经济schema缺少日结字段时可恢复"
			)
			_equal(
				int(
					(simulation.persistence.snapshot().get("economy", {}) as Dictionary).get(
						"last_day_index", -99
					)
				),
				-1,
				"23小时旧经济schema缺字段时派生为-1"
			)
		if total_hour == 25:
			var before := simulation.persistence.snapshot()
			var too_large := before.duplicate(true)
			var too_large_economy := too_large.get("economy", {}) as Dictionary
			too_large_economy["last_day_index"] = 2
			too_large["economy"] = too_large_economy
			_assert_economy_rejected_without_mutation(
				simulation,
				too_large,
				before,
				"25小时last_day_index过大"
			)
			var too_small := before.duplicate(true)
			var too_small_economy := too_small.get("economy", {}) as Dictionary
			too_small_economy["last_day_index"] = 0
			too_small["economy"] = too_small_economy
			_assert_economy_rejected_without_mutation(
				simulation,
				too_small,
				before,
				"25小时last_day_index过小"
			)


func _test_legacy_save_time_compatibility() -> void:
	var source := WorldBootstrap.new().build()
	_check(source.success, "旧存档兼容源可初始化")
	if not source.success:
		return
	source.simulation_step.advance_minutes(125)
	var legacy := SUPPORT.simulation_state(source)
	legacy["schema_id"] = "formal_world_simulation_v1"
	var target := WorldBootstrap.new().build()
	_check(target.success, "旧存档兼容目标可初始化")
	var candidate_4 := target.persistence.restore_candidate(legacy)
	if candidate_4.success:
		target = candidate_4
	_check(candidate_4.success, "一致的V1正式存档仍可读取")
	_equal(target.world.game_clock.total_minutes(), 125, "V1存档恢复权威分钟")
	_equal(FormalWorldEconomyView.new(target.world.economy_state.read_only_snapshot()).total_hour, 2, "V1存档经济小时由权威分钟派生")

	var boundary_source := WorldBootstrap.new().build()
	_check(boundary_source.success, "旧小时边界存档源可初始化")
	boundary_source.simulation_step.advance_minutes(120)
	var sparse_legacy := SUPPORT.simulation_state(boundary_source)
	sparse_legacy["schema_id"] = "formal_world_simulation_v1"
	sparse_legacy.erase("total_minutes")
	sparse_legacy.erase("minute_remainder")
	var boundary_target := WorldBootstrap.new().build()
	_check(boundary_target.success, "旧小时边界存档目标可初始化")
	var candidate_5 := boundary_target.persistence.restore_candidate(sparse_legacy)
	if candidate_5.success:
		boundary_target = candidate_5
	_check(candidate_5.success, "V1小时边界存档可从经济小时恢复")
	_equal(boundary_target.world.game_clock.total_minutes(), 120, "V1小时边界恢复为120权威分钟")


func _assert_economy_rejected_without_mutation(
	simulation: WorldBuildResult,
	rejected: Dictionary,
	before: Dictionary,
	label: String
) -> void:
	var candidate_6 := simulation.persistence.restore_candidate(rejected)
	if candidate_6.success:
		simulation = candidate_6
	_check(not candidate_6.success, "%s被拒绝" % label)
	_equal(simulation.persistence.snapshot(), before, "%s拒绝后经济状态完全一致" % label)


func _assert_rejected_without_mutation(
	simulation: WorldBuildResult,
	rejected: Dictionary,
	before: Dictionary,
	label: String
) -> void:
	var candidate_7 := simulation.persistence.restore_candidate(rejected)
	if candidate_7.success:
		simulation = candidate_7
	_check(not candidate_7.success, "%s被拒绝" % label)
	_equal(SUPPORT.simulation_state(simulation), before, "%s拒绝后完整状态原子回滚" % label)


func _has_property(value: Object, property_name: String) -> bool:
	for record: Dictionary in value.get_property_list():
		if str(record.get("name", "")) == property_name:
			return true
	return false


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
