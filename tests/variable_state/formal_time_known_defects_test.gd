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
	_test_initial_time_consistency()
	_test_single_authoritative_tick()
	_test_gregorian_formal_calendar()
	_test_formal_load_restores_visible_time()
	await _test_new_game_product_path()
	await _test_continue_game_restores_visible_time()
	_test_inconsistent_persistent_time_is_rejected()
	_test_economy_restore_day_boundaries()
	_test_legacy_save_time_compatibility()
	_check(SUPPORT.restore_formal_save(backup), "一致性测试结束后恢复原有存档或保持隔离目录为空")
	print("Formal time known defects: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_initial_time_consistency() -> void:
	var application := FormalWorldApplication.new()
	_check(application.formal_simulation.initialize(), "正式应用可初始化唯一时间源")
	if not application.formal_simulation.initialized:
		application.free()
		return
	_equal(
		SUPPORT.hemisphere_state(application),
		{
			"year": 1900,
			"month": 1,
			"day": 1,
			"hour": 0,
			"minute": 0,
			"paused": true,
			"speed": 1,
		},
		"正式模拟、半球与HUD初始时间统一为1900-01-01 00:00"
	)
	_equal(application._format_sim_datetime(), "1900年01月01日 00:00", "正式HUD即时派生初始时间")
	for removed_property: String in ["sim_year", "sim_month", "sim_day", "sim_hour", "sim_minute"]:
		_check(not _has_property(application, removed_property), "正式应用不再持有可写字段%s" % removed_property)
	application.free()


func _test_single_authoritative_tick() -> void:
	var application := FormalWorldApplication.new()
	_check(application.formal_simulation.initialize(), "唯一推进测试可初始化正式模拟")
	if not application.formal_simulation.initialized:
		application.free()
		return
	application.sim_paused = false
	application.sim_speed = 1
	for _tick: int in range(4):
		application._on_clock_timer_timeout()
	_equal(application.formal_simulation.total_minutes, 60, "四个真实tick只推进60权威分钟")
	_equal(application.formal_simulation.economy.total_hour, 1, "经济小时由60权威分钟只读派生")
	_equal(SUPPORT.hemisphere_total_minute(application), 60, "半球显示与权威分钟完全相同")
	_equal(application._format_sim_datetime(), "1900年01月01日 01:00", "HUD显示同一权威时间")
	application.free()


func _test_gregorian_formal_calendar() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "正式公历测试可初始化")
	if not simulation.initialized:
		return
	var february_end_hour := V2DateTime.to_total_hour({
		"year": 1900,
		"month": 2,
		"day": 28,
		"hour": 23,
	})
	_check(february_end_hour >= 0, "1900-02-28 23:00是有效公历时间")
	simulation.advance_minutes(february_end_hour * 60 + 45)
	_equal(simulation.date_time(), {
		"year": 1900,
		"month": 2,
		"day": 28,
		"hour": 23,
		"weekday": 2,
		"minute": 45,
	}, "正式时间到达1900-02-28 23:45")
	simulation.advance_minutes(15)
	var value := simulation.date_time()
	_equal(int(value.get("year", 0)), 1900, "二月月末后年份仍为1900")
	_equal(int(value.get("month", 0)), 3, "1900非闰年二月后进入三月")
	_equal(int(value.get("day", 0)), 1, "1900-02-28后直接进入三月一日")
	_equal(int(value.get("hour", -1)), 0, "跨月后小时归零")
	_equal(int(value.get("minute", -1)), 0, "跨月后分钟归零")
	_check(V2DateTime.to_total_hour({"year": 1900, "month": 2, "day": 29, "hour": 0}) < 0, "1900-02-29始终无效")


func _test_formal_load_restores_visible_time() -> void:
	_check(SUPPORT.cleanup_formal_save(), "界面读取测试前隔离存档为空")
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "界面读取存档源可初始化")
	if not source.initialized:
		return
	source.advance_minutes(125)
	var saved := SUPPORT.simulation_state(source)
	_check(source.save_to_user().success, "通过生产方法保存非零正式时间")
	var application := FormalWorldApplication.new()
	_check(application.formal_simulation.initialize(), "界面读取应用可初始化")
	if not application.formal_simulation.initialized:
		application.free()
		return
	application.formal_simulation.advance_minutes(600)
	application._activate_button("formal_load")
	_equal(SUPPORT.simulation_state(application.formal_simulation), saved, "formal_load恢复完整正式模拟状态")
	_equal(SUPPORT.hemisphere_total_minute(application), 125, "读取后半球立即显示已恢复权威分钟")
	_equal(application._format_sim_datetime(), "1900年01月01日 02:05", "读取后HUD立即显示已恢复时间")
	_equal(application._formal_status, "正式世界存档已恢复。", "界面读取报告成功")
	application.free()
	_check(SUPPORT.cleanup_formal_save(), "界面读取测试删除自己产生的存档")


func _test_new_game_product_path() -> void:
	_check(SUPPORT.cleanup_formal_save(), "新游戏产品路径前隔离存档为空")
	root.content_scale_size = Vector2i(1280, 720)
	set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "新游戏可加载正式产品场景")
	if scene == null:
		return
	var application := scene.instantiate() as FormalWorldApplication
	_check(application != null, "新游戏可实例化正式产品场景")
	if application == null:
		return
	root.add_child(application)
	await process_frame
	await process_frame
	_equal(application.formal_simulation.total_minutes, 0, "新游戏产品路径从0权威分钟开始")
	_equal(SUPPORT.hemisphere_total_minute(application), 0, "新游戏半球立即显示1900-01-01 00:00")
	_equal(application._formal_status, "新的1900正式世界已建立。", "新游戏产品路径报告新世界")
	application.queue_free()
	await process_frame


func _test_continue_game_restores_visible_time() -> void:
	_check(SUPPORT.cleanup_formal_save(), "继续游戏测试前隔离存档为空")
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "继续游戏存档源可初始化")
	if not source.initialized:
		return
	source.advance_minutes(185)
	var saved := SUPPORT.simulation_state(source)
	_check(source.save_to_user().success, "继续游戏通过生产方法保存非零正式时间")
	root.content_scale_size = Vector2i(1280, 720)
	set_meta(FormalWorldApplication.LAUNCH_MODE_META, "load")
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "继续游戏可加载正式产品场景")
	if scene == null:
		return
	var application := scene.instantiate() as FormalWorldApplication
	_check(application != null, "继续游戏可实例化正式产品场景")
	if application == null:
		return
	root.add_child(application)
	await process_frame
	await process_frame
	_equal(SUPPORT.simulation_state(application.formal_simulation), saved, "继续游戏恢复完整正式模拟状态")
	_equal(SUPPORT.hemisphere_total_minute(application), 185, "继续游戏半球立即读取同一权威时间")
	_equal(application._format_sim_datetime(), "1900年01月01日 03:05", "继续游戏HUD立即显示恢复时间")
	_equal(application._formal_status, "正式世界存档已恢复。", "继续游戏产品路径报告恢复成功")
	application.queue_free()
	await process_frame
	_check(SUPPORT.cleanup_formal_save(), "继续游戏测试删除自己产生的存档")


func _test_inconsistent_persistent_time_is_rejected() -> void:
	_check(SUPPORT.cleanup_formal_save(), "矛盾存档测试前隔离存档为空")
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "矛盾存档拒绝测试可初始化")
	if not simulation.initialized:
		return
	simulation.advance_minutes(125)
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

	var file := FileAccess.open(FormalWorldSimulation.SAVE_PATH, FileAccess.WRITE)
	_check(file != null, "可写入损坏时间存档测试文件")
	if file != null:
		file.store_string(JSON.stringify(wrong_hour))
		file.close()
	_check(not simulation.load_from_user().success, "真实磁盘读取拒绝矛盾时间字段")
	_equal(SUPPORT.simulation_state(simulation), before, "磁盘恢复失败前后完整状态相等")
	_check(SUPPORT.cleanup_formal_save(), "矛盾存档测试删除自己产生的存档")


func _test_economy_restore_day_boundaries() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "经济日结边界恢复测试可初始化")
	if not simulation.initialized:
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
			simulation.advance_minutes((total_hour - previous_total_hour) * 60)
		previous_total_hour = total_hour
		var saved_world := simulation.get_persistent_state()
		var saved := saved_world.get("economy", {}) as Dictionary
		_equal(
			int(saved.get("last_day_index", -99)),
			expected_last_day_index,
			"%d小时持久状态日结索引为%d" % [
				total_hour, expected_last_day_index,
			]
		)
		_check(
			simulation.restore_persistent_state(saved_world),
			"%d小时合法经济状态可恢复" % total_hour
		)
		_equal(
			int(
				(simulation.get_persistent_state().get("economy", {}) as Dictionary).get(
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
			var legacy := (legacy_world.get("economy", {}) as Dictionary).duplicate(true)
			legacy["schema_id"] = "formal_world_economy_state_v1"
			legacy.erase("last_day_index")
			legacy_world["economy"] = legacy
			_check(
				simulation.restore_persistent_state(legacy_world),
				"23小时旧经济schema缺少日结字段时可恢复"
			)
			_equal(
				int(
					(simulation.get_persistent_state().get("economy", {}) as Dictionary).get(
						"last_day_index", -99
					)
				),
				-1,
				"23小时旧经济schema缺字段时派生为-1"
			)
		if total_hour == 25:
			var before := simulation.get_persistent_state()
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
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "旧存档兼容源可初始化")
	if not source.initialized:
		return
	source.advance_minutes(125)
	var legacy := SUPPORT.simulation_state(source)
	legacy["schema_id"] = "formal_world_simulation_v1"
	var target := FormalWorldSimulation.new()
	_check(target.initialize(), "旧存档兼容目标可初始化")
	_check(target.restore_persistent_state(legacy), "一致的V1正式存档仍可读取")
	_equal(target.total_minutes, 125, "V1存档恢复权威分钟")
	_equal(target.economy.total_hour, 2, "V1存档经济小时由权威分钟派生")

	var boundary_source := FormalWorldSimulation.new()
	_check(boundary_source.initialize(), "旧小时边界存档源可初始化")
	boundary_source.advance_minutes(120)
	var sparse_legacy := SUPPORT.simulation_state(boundary_source)
	sparse_legacy["schema_id"] = "formal_world_simulation_v1"
	sparse_legacy.erase("total_minutes")
	sparse_legacy.erase("minute_remainder")
	var boundary_target := FormalWorldSimulation.new()
	_check(boundary_target.initialize(), "旧小时边界存档目标可初始化")
	_check(boundary_target.restore_persistent_state(sparse_legacy), "V1小时边界存档可从经济小时恢复")
	_equal(boundary_target.total_minutes, 120, "V1小时边界恢复为120权威分钟")


func _assert_economy_rejected_without_mutation(
	simulation: FormalWorldSimulation,
	rejected: Dictionary,
	before: Dictionary,
	label: String
) -> void:
	_check(not simulation.restore_persistent_state(rejected), "%s被拒绝" % label)
	_equal(simulation.get_persistent_state(), before, "%s拒绝后经济状态完全一致" % label)


func _assert_rejected_without_mutation(
	simulation: FormalWorldSimulation,
	rejected: Dictionary,
	before: Dictionary,
	label: String
) -> void:
	_check(not simulation.restore_persistent_state(rejected), "%s被拒绝" % label)
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
