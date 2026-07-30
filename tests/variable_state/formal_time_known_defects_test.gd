extends SceneTree
## KNOWN DEFECT CHARACTERIZATION
## NOT A LONG-TERM CORRECTNESS CONTRACT
## These assertions prove the current D01 defects. The implementation PR must
## replace them with consistency assertions when the defects are corrected.

const SUPPORT = preload("res://tests/variable_state/formal_time_test_support.gd")
const EXPECTED_OFFSET_HOURS: int = 1688

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup: Dictionary = SUPPORT.backup_formal_save()
	_check(not bool(backup.get("read_error", false)), "现有正式存档如存在则可安全备份")
	_check(SUPPORT.cleanup_formal_save(), "已知缺陷测试开始前清理隔离user://正式存档")
	_test_initial_time_offset()
	_test_offset_persists_through_real_ticks()
	_test_invalid_hemisphere_calendar()
	_test_formal_load_does_not_sync_hemisphere()
	await _test_continue_game_does_not_sync_hemisphere()
	_test_inconsistent_persistent_time_is_accepted()
	_check(SUPPORT.restore_formal_save(backup), "已知缺陷测试结束后恢复原有存档或保持隔离目录为空")
	print("Formal time known defects: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_initial_time_offset() -> void:
	var application := FormalWorldApplication.new()
	_check(
		application.formal_simulation.initialize(),
		"初始错位测试可初始化正式模拟"
	)
	if not application.formal_simulation.initialized:
		application.free()
		return
	_equal(application.sim_year, 1900, "半球初始年份为1900")
	_equal(application.sim_month, 3, "半球初始月份为3")
	_equal(application.sim_day, 12, "半球初始日期为12")
	_equal(application.sim_hour, 8, "半球初始小时为8")
	_equal(application.sim_minute, 0, "半球初始分钟为0")
	var formal: Dictionary = application.formal_simulation.date_time()
	_equal(int(formal.get("year", 0)), 1900, "正式模拟初始年份为1900")
	_equal(int(formal.get("month", 0)), 1, "正式模拟初始月份为1")
	_equal(int(formal.get("day", 0)), 1, "正式模拟初始日期为1")
	_equal(int(formal.get("hour", -1)), 0, "正式模拟初始小时为0")
	_equal(int(formal.get("minute", -1)), 0, "正式模拟初始分钟为0")
	var hemisphere_hour: int = SUPPORT.hemisphere_total_hour(application)
	_equal(
		hemisphere_hour - application.formal_simulation.economy.total_hour,
		EXPECTED_OFFSET_HOURS,
		"当前初始半球时间比正式模拟时间晚70天8小时即1688小时"
	)
	application.free()


func _test_offset_persists_through_real_ticks() -> void:
	var application := FormalWorldApplication.new()
	_check(
		application.formal_simulation.initialize(),
		"持续错位测试可初始化正式模拟"
	)
	if not application.formal_simulation.initialized:
		application.free()
		return
	var hemisphere_before: int = SUPPORT.hemisphere_total_minute(application)
	var formal_before: int = application.formal_simulation.total_minutes
	application.sim_paused = false
	application.sim_speed = 1
	for _tick: int in range(4):
		application._on_clock_timer_timeout()
	var hemisphere_after: int = SUPPORT.hemisphere_total_minute(application)
	var formal_after: int = application.formal_simulation.total_minutes
	_equal(hemisphere_after - hemisphere_before, 60, "四个真实tick推进半球展示60分钟")
	_equal(formal_after - formal_before, 60, "四个真实tick推进正式模拟60分钟")
	_check(hemisphere_after != formal_after, "真实tick后半球与正式模拟仍不是同一时间事实")
	_equal(
		int((hemisphere_after - formal_after) / 60),
		EXPECTED_OFFSET_HOURS,
		"双表示分别推进后原有1688小时错位仍然存在"
	)
	application.free()


func _test_invalid_hemisphere_calendar() -> void:
	var application := FormalWorldApplication.new()
	SUPPORT.set_hemisphere_time(application, 1900, 2, 28, 23, 45)
	application._advance_clock(15)
	_equal(application.sim_year, 1900, "无效公历证据保持1900年")
	_equal(application.sim_month, 2, "无效公历证据保持2月")
	_equal(application.sim_day, 29, "当前半球时钟从1900-02-28生成1900-02-29")
	_equal(application.sim_hour, 0, "当前半球时钟跨日后小时归零")
	_equal(application.sim_minute, 0, "当前半球时钟跨日后分钟归零")
	_equal(
		V2DateTime.to_total_hour({
			"year": application.sim_year,
			"month": application.sim_month,
			"day": application.sim_day,
			"hour": application.sim_hour,
		}),
		-1,
		"V2DateTime判定1900-02-29为无效公历日期"
	)
	application.free()


func _test_formal_load_does_not_sync_hemisphere() -> void:
	_check(SUPPORT.cleanup_formal_save(), "界面读取缺陷测试前隔离存档为空")
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "界面读取缺陷测试存档源可初始化")
	if not source.initialized:
		return
	source.advance_minutes(125)
	var saved: Dictionary = SUPPORT.simulation_state(source)
	_check(source.save_to_user(), "界面读取缺陷测试通过生产方法保存非零正式时间")
	var application := FormalWorldApplication.new()
	_check(
		application.formal_simulation.initialize(),
		"界面读取缺陷测试应用正式模拟可初始化"
	)
	if not application.formal_simulation.initialized:
		application.free()
		return
	application.formal_simulation.advance_minutes(600)
	SUPPORT.set_hemisphere_time(application, 1901, 7, 4, 12, 30)
	var hemisphere_before: Dictionary = SUPPORT.hemisphere_state(application)
	application._activate_button("formal_load")
	_equal(
		SUPPORT.simulation_state(application.formal_simulation),
		saved,
		"当前formal_load界面路径恢复正式模拟状态"
	)
	_equal(
		SUPPORT.hemisphere_state(application),
		hemisphere_before,
		"当前formal_load界面路径不恢复半球sim_*显示时间"
	)
	_equal(application._formal_status, "正式世界存档已恢复。", "界面读取路径报告正式存档已恢复")
	application.free()
	_check(SUPPORT.cleanup_formal_save(), "界面读取缺陷测试删除自己产生的正式存档")


func _test_continue_game_does_not_sync_hemisphere() -> void:
	_check(SUPPORT.cleanup_formal_save(), "继续游戏缺陷测试前隔离存档为空")
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "继续游戏缺陷测试存档源可初始化")
	if not source.initialized:
		return
	source.advance_minutes(185)
	var saved: Dictionary = SUPPORT.simulation_state(source)
	_check(source.save_to_user(), "继续游戏缺陷测试通过生产方法保存非零正式时间")
	root.content_scale_size = Vector2i(1280, 720)
	set_meta(FormalWorldApplication.LAUNCH_MODE_META, "load")
	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "继续游戏测试可加载正式产品场景")
	if scene == null:
		return
	var application := scene.instantiate() as FormalWorldApplication
	_check(application != null, "继续游戏测试可实例化正式产品场景")
	if application == null:
		return
	root.add_child(application)
	await process_frame
	await process_frame
	_equal(
		SUPPORT.simulation_state(application.formal_simulation),
		saved,
		"launch_mode=load真实产品路径恢复正式模拟状态"
	)
	_equal(application._formal_status, "正式世界存档已恢复。", "继续游戏产品路径确认正式存档恢复")
	_equal(
		SUPPORT.hemisphere_state(application),
		{
			"year": 1900,
			"month": 3,
			"day": 12,
			"hour": 8,
			"minute": 0,
			"paused": true,
			"speed": 1,
		},
		"继续游戏恢复正式模拟但半球sim_*仍保持场景初始值"
	)
	application.queue_free()
	await process_frame
	_check(SUPPORT.cleanup_formal_save(), "继续游戏缺陷测试删除自己产生的正式存档")


func _test_inconsistent_persistent_time_is_accepted() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "存档内部时间不一致测试可初始化")
	if not simulation.initialized:
		return
	var inconsistent: Dictionary = SUPPORT.simulation_state(simulation)
	inconsistent["total_minutes"] = 125
	inconsistent["minute_remainder"] = 5
	var economy_state: Dictionary = inconsistent.get("economy", {}) as Dictionary
	economy_state["total_hour"] = 99
	inconsistent["economy"] = economy_state
	_check(
		simulation.restore_persistent_state(inconsistent),
		"当前restore_persistent_state接受彼此不一致的分钟与经济小时"
	)
	_equal(simulation.total_minutes, 125, "不一致恢复后total_minutes为125")
	_equal(simulation._minute_remainder, 5, "不一致恢复后minute_remainder为5")
	_equal(simulation.economy.total_hour, 99, "不一致恢复后economy.total_hour为99")
	_check(
		simulation.economy.total_hour != int(simulation.total_minutes / 60),
		"恢复后正式累计分钟与经济小时可以长期不一致"
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
