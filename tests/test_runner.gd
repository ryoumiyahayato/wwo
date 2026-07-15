extends SceneTree
## Dependency-free project tests, executed directly by the Godot command line.

const REQUIRED_DOCS: PackedStringArray = [
	"res://AGENTS.md",
	"res://README.md",
	"res://CHANGELOG.md",
	"res://docs/PRODUCT_VISION.md",
	"res://docs/DEMO_SCOPE.md",
	"res://docs/GAME_DESIGN.md",
	"res://docs/ARCHITECTURE.md",
	"res://docs/DATA_MODEL.md",
	"res://docs/SIMULATION_RULES.md",
	"res://docs/PERFORMANCE_BUDGET.md",
	"res://docs/SAVE_FORMAT.md",
	"res://docs/TEST_PLAN.md",
	"res://docs/ROADMAP.md",
	"res://docs/PLANS.md",
	"res://docs/DECISIONS.md",
	"res://docs/KNOWN_ISSUES.md",
]

var _failures: int = 0
var _checks: int = 0
var _clock_config: SimulationClockConfig
var _map_rules: MapRulesConfig
var _character_config: CharacterGenerationConfig
var _world_data: CoreDataSet
var _action_rules: ActionRulesConfig
var _society_rules: SocietyRulesConfig
var _society: SocietySimulationService
var _continuity_rules: ContinuityRulesConfig


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	LogService.set_minimum_level(LogService.Level.ERROR)
	_test_project_configuration()
	_test_required_documentation()
	_test_log_service()
	_test_main_menu_scene()
	_test_simulation_clock_config()
	_test_clock_start_pause_speed_and_step()
	_test_clock_frame_chunk_independence()
	_test_clock_calendar_and_periodic_events()
	_test_clock_year_boundary_and_baseline()
	_test_clock_event_queue()
	_test_clock_event_order()
	_test_simulation_clock_view()
	_test_stable_id_service()
	_test_random_service_config_and_determinism()
	_test_random_service_state_restore()
	_test_random_service_baseline()
	_test_core_data_loader_valid_fixture()
	_test_core_data_loader_invalid_fixtures()
	_test_core_data_loader_baseline()
	_test_m3_world_data_and_topology()
	_test_m3_frontline_control_changes()
	_test_m3_pressure_capture_and_consolidation()
	_test_m3_isolated_surrounded_and_empty_unit()
	_test_m3_region_summary()
	_test_m3_strategic_map_scene()
	_test_m3_world_performance_baseline()
	_test_m4_generation_config_and_country_requirement()
	_test_m4_same_seed_same_character()
	_test_m4_random_modes_and_age_rules()
	_test_m4_hidden_information_boundary()
	_test_m4_dynamic_tendencies()
	_test_m4_character_scenes()
	_test_m4_generation_performance_baseline()
	_test_m5_action_definitions_and_rules()
	_test_m5_start_permissions_and_effective_value()
	_test_m5_progress_frame_independence()
	_test_m5_dependency_recalculation()
	_test_m5_pause_resume_cancel_and_interrupt()
	_test_m5_thresholds_and_result_application()
	_test_m5_control_result_application()
	_test_m5_action_panel_scene()
	_test_m5_action_performance_baseline()
	_test_m6_society_rules_and_organizations()
	_test_m6_population_tiers_and_determinism()
	_test_m6_membership_positions_and_permissions()
	_test_m6_sparse_relationships()
	_test_m6_promotion_demotion_and_limit()
	_test_m6_ai_frequency_and_determinism()
	_test_m6_social_panel_scene()
	_test_m6_society_performance_baseline()
	_test_m7_continuity_rules()
	_test_m7_social_and_military_influence_separation()
	_test_m7_organization_support_channels()
	_test_m7_action_domain_effect()
	_test_m7_candidate_sources_and_order()
	_test_m7_exit_reasons()
	_test_m7_partial_succession_and_continuity()
	_test_m7_succession_panel_scene()
	_test_m7_succession_performance_baseline()
	_test_m8_clock_and_queue_roundtrip()
	_test_m8_save_load_roundtrip()
	_test_m8_invalid_save_and_safe_replace()
	_test_m8_autosave_log_and_performance()
	_test_m8_developer_tools_and_panel()
	_test_m9_integrated_core_loop()
	_test_m9_thirty_day_and_year_stability()
	_test_m9_desktop_configuration()
	_finish()


func _test_project_configuration() -> void:
	var rendering_method: String = str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", ""
	))
	_expect_equal(rendering_method, "gl_compatibility", "Compatibility 渲染器已固定")

	var main_scene_path: String = str(ProjectSettings.get_setting(
		"application/run/main_scene", ""
	))
	_expect_equal(
		main_scene_path,
		"res://scenes/menu/main_menu.tscn",
		"主场景配置正确"
	)


func _test_required_documentation() -> void:
	for document_path: String in REQUIRED_DOCS:
		_expect_true(FileAccess.file_exists(document_path), "核心文档存在：%s" % document_path)


func _test_log_service() -> void:
	LogService.set_minimum_level(LogService.Level.WARNING)
	_expect_true(not LogService.should_log(LogService.Level.INFO), "日志等级可过滤低级消息")
	_expect_true(LogService.should_log(LogService.Level.ERROR), "日志等级保留高级消息")
	_expect_equal(
		LogService.format_message("INFO", "Test", "message"),
		"[INFO] [Test] message",
		"日志格式稳定"
	)


func _test_main_menu_scene() -> void:
	var scene_resource: Resource = load("res://scenes/menu/main_menu.tscn")
	_expect_true(scene_resource is PackedScene, "主菜单场景可加载")
	if not scene_resource is PackedScene:
		return

	var packed_scene: PackedScene = scene_resource as PackedScene
	var menu: Node = packed_scene.instantiate()
	get_root().add_child(menu)
	_expect_true(menu is Control, "主菜单根节点是 Control")
	_expect_true(menu.get_node_or_null("SafeMargin/Center/Card") != null, "主菜单卡片存在")
	_expect_true(
		menu.get_node_or_null("SafeMargin/Center/Card/CardMargin/Content/QuitButton") is Button,
		"退出按钮存在"
	)
	var new_game_button: Button = menu.get_node(
		"SafeMargin/Center/Card/CardMargin/Content/NewGameButton"
	) as Button
	_expect_true(not new_game_button.disabled, "新游戏按钮可进入当前里程碑流程")
	menu.queue_free()


func _test_simulation_clock_config() -> void:
	_clock_config = SimulationClockConfig.new()
	var load_error: Error = _clock_config.load_from_file()
	_expect_equal(load_error, OK, "时间配置可加载")
	_expect_equal(_clock_config.start_year, 1900, "时间配置从 1900 年开始")
	_expect_approx(
		_clock_config.real_seconds_per_game_hour,
		1.0,
		0.000001,
		"现实秒到游戏小时的换算已配置"
	)
	_expect_equal(
		_clock_config.allowed_speed_multipliers,
		[1, 2, 4, 8],
		"允许速度为 1/2/4/8 倍"
	)


func _test_clock_start_pause_speed_and_step() -> void:
	var clock: SimulationClock = _create_clock()
	_expect_clock_datetime(clock, 1900, 1, 1, 0, "权威时钟起始时间正确")
	_expect_true(clock.is_paused, "权威时钟默认暂停")
	_expect_equal(clock.advance_real_seconds(10.0), 0, "暂停时现实时间不推进游戏时间")
	_expect_equal(clock.total_hours, 0, "暂停保持累计小时不变")
	_expect_true(clock.set_speed(8), "8 倍速度可设置")
	_expect_true(not clock.set_speed(3), "未配置的 3 倍速度被拒绝")
	_expect_equal(clock.speed_multiplier, 8, "非法速度不改变当前速度")

	clock.step_one_hour()
	_expect_clock_datetime(clock, 1900, 1, 1, 1, "暂停状态可单步一小时")
	clock.set_paused(false)
	_expect_equal(clock.advance_real_seconds(0.5), 4, "8 倍速度按配置推进整小时")
	_expect_clock_datetime(clock, 1900, 1, 1, 5, "倍速推进后的日期正确")


func _test_clock_frame_chunk_independence() -> void:
	var large_chunk_clock: SimulationClock = _create_clock()
	var small_chunk_clock: SimulationClock = _create_clock()
	for clock: SimulationClock in [large_chunk_clock, small_chunk_clock]:
		clock.set_speed(4)
		clock.set_paused(false)

	large_chunk_clock.advance_real_seconds(2.5)
	for _frame: int in range(25):
		small_chunk_clock.advance_real_seconds(0.1)

	_expect_equal(
		large_chunk_clock.get_snapshot(),
		small_chunk_clock.get_snapshot(),
		"相同现实时间在不同帧分块下产生相同权威状态"
	)
	_expect_approx(
		large_chunk_clock.get_real_seconds_remainder(),
		small_chunk_clock.get_real_seconds_remainder(),
		0.000001,
		"不同帧分块保留相同时间余量"
	)


func _test_clock_calendar_and_periodic_events() -> void:
	var clock: SimulationClock = _create_clock()
	var counts: Array[int] = [0, 0, 0, 0]
	clock.hour_advanced.connect(func(_total_hours: int) -> void: counts[0] += 1)
	clock.day_advanced.connect(
		func(_year: int, _month: int, _day: int) -> void: counts[1] += 1
	)
	clock.week_advanced.connect(func(_week: int) -> void: counts[2] += 1)
	clock.month_advanced.connect(
		func(_year: int, _month: int) -> void: counts[3] += 1
	)

	clock.advance_hours(31 * 24)
	_expect_clock_datetime(clock, 1900, 2, 1, 0, "一月边界推进到二月一日")
	_expect_equal(counts, [744, 31, 4, 1], "小时/日/周/月事件按边界触发")

	clock.advance_hours(28 * 24)
	_expect_clock_datetime(clock, 1900, 3, 1, 0, "1900 年按世纪规则不是闰年")
	_expect_equal(counts[3], 2, "跨二月边界触发第二个月事件")


func _test_clock_year_boundary_and_baseline() -> void:
	var clock: SimulationClock = _create_clock()
	var started_at_usec: int = Time.get_ticks_usec()
	clock.advance_hours(365 * 24)
	var elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_clock_datetime(clock, 1901, 1, 1, 0, "1900 全年推进到 1901 年元旦")
	print("[PERF] 仅时钟推进 8760 小时：%.3f ms" % (float(elapsed_usec) / 1000.0))


func _test_clock_event_queue() -> void:
	var clock: SimulationClock = _create_clock()
	var received_ids: Array[String] = []
	var received_values: Array[int] = []
	clock.scheduled_event_due.connect(
		func(event_id: String, _due_hour: int, payload: Dictionary) -> void:
			received_ids.append(event_id)
			received_values.append(int(payload.get("value", -1)))
	)

	var mutable_payload: Dictionary = {"value": 1}
	_expect_true(clock.schedule_event_in_hours("alpha", 2, mutable_payload), "队列接受未来事件")
	mutable_payload["value"] = 99
	_expect_true(clock.schedule_event_in_hours("beta", 2, {"value": 2}), "队列接受同小时事件")
	_expect_true(clock.schedule_event_in_hours("cancelled", 3), "队列接受可取消事件")
	_expect_true(not clock.schedule_event_in_hours("alpha", 4), "队列拒绝重复事件 ID")
	_expect_true(not clock.schedule_event_in_hours("now", 0), "队列拒绝非未来延迟")
	_expect_true(clock.cancel_scheduled_event("cancelled"), "队列事件可取消")
	clock.advance_hours(3)
	_expect_equal(received_ids, ["alpha", "beta"], "同小时事件按插入顺序触发")
	_expect_equal(received_values, [1, 2], "队列深拷贝事件载荷")
	_expect_equal(clock.get_scheduled_event_count(), 0, "到期和取消后队列为空")


func _test_clock_event_order() -> void:
	var clock: SimulationClock = _create_clock()
	var event_order: Array[String] = []
	clock.hour_advanced.connect(
		func(total: int) -> void:
			if total == 24:
				event_order.append("hour")
	)
	clock.day_advanced.connect(
		func(_year: int, _month: int, _day: int) -> void: event_order.append("day")
	)
	clock.scheduled_event_due.connect(
		func(_id: String, _due: int, _payload: Dictionary) -> void:
			event_order.append("scheduled")
	)
	clock.schedule_event_in_hours("boundary", 24)
	clock.advance_hours(24)
	_expect_equal(event_order, ["hour", "day", "scheduled"], "边界事件顺序固定")


func _test_simulation_clock_view() -> void:
	var scene_resource: Resource = load("res://scenes/world/simulation_clock_view.tscn")
	_expect_true(scene_resource is PackedScene, "M1 时间界面场景可加载")
	if not scene_resource is PackedScene:
		return
	var view: Node = (scene_resource as PackedScene).instantiate()
	get_root().add_child(view)
	var date_label: Label = view.get_node(
		"SafeMargin/Center/Panel/PanelMargin/Content/DateTimeLabel"
	) as Label
	_expect_equal(date_label.text, "1900年01月01日 00:00", "时间界面显示权威起始时间")
	var runner: SimulationRunner = view.get_node("SimulationRunner") as SimulationRunner
	_expect_true(runner != null, "时间界面使用独立 Runner")
	var content_path: String = "SafeMargin/Center/Panel/PanelMargin/Content"
	var pause_button: Button = view.get_node(content_path + "/Controls/PauseButton") as Button
	var step_button: Button = view.get_node(content_path + "/Controls/StepButton") as Button
	var speed_8_button: Button = view.get_node(content_path + "/Speeds/Speed8Button") as Button
	pause_button.pressed.emit()
	_expect_true(not runner.clock.is_paused, "继续按钮解除暂停")
	speed_8_button.pressed.emit()
	_expect_equal(runner.clock.speed_multiplier, 8, "8 倍按钮设置权威速度")
	step_button.pressed.emit()
	_expect_true(runner.clock.is_paused, "单步按钮先暂停时钟")
	_expect_equal(runner.clock.total_hours, 1, "单步按钮只推进一个游戏小时")
	view.queue_free()


func _test_stable_id_service() -> void:
	var ids := StableIdService.new()
	_expect_equal(ids.next_id("character"), "character:00000001", "稳定 ID 从命名空间序号 1 开始")
	_expect_equal(ids.next_id("character"), "character:00000002", "稳定 ID 在命名空间内递增")
	_expect_equal(ids.next_id("organization"), "organization:00000001", "不同命名空间独立计数")
	_expect_true(StableIdService.is_valid_id("country:test_republic"), "静态稳定 ID 格式有效")
	_expect_true(not StableIdService.is_valid_id("Country:Invalid"), "稳定 ID 拒绝大写和非法格式")
	_expect_equal(ids.next_id("invalid-prefix"), "", "生成器拒绝非法命名空间")

	var saved_state: Dictionary = ids.get_state()
	var expected_next: String = ids.next_id("character")
	var restored_ids := StableIdService.new()
	_expect_true(restored_ids.restore_state(saved_state), "稳定 ID 计数器状态可恢复")
	_expect_equal(restored_ids.next_id("character"), expected_next, "恢复后继续相同 ID 序列")
	_expect_true(not restored_ids.restore_state({"Bad": -1}), "稳定 ID 拒绝无效计数器状态")


func _test_random_service_config_and_determinism() -> void:
	var config := RandomServiceConfig.new()
	_expect_equal(config.load_from_file(), OK, "随机服务配置可加载")
	_expect_equal(config.default_seed, 19000101, "默认随机种子来自配置")

	var first := DeterministicRandomService.new(config.default_seed)
	var second := DeterministicRandomService.new(config.default_seed)
	var first_sequence: Array[int] = []
	var second_sequence: Array[int] = []
	for _index: int in range(32):
		first_sequence.append(first.next_int(-1000, 1000))
		second_sequence.append(second.next_int(-1000, 1000))
	_expect_equal(first_sequence, second_sequence, "相同种子和调用顺序产生相同整数序列")
	_expect_equal(
		first.shuffled_copy(["a", "b", "c", "d", "e"]),
		second.shuffled_copy(["a", "b", "c", "d", "e"]),
		"相同随机状态产生相同洗牌结果"
	)
	_expect_equal(first.pick([]), null, "空集合随机选取安全返回 null")


func _test_random_service_state_restore() -> void:
	var random := DeterministicRandomService.new(424242)
	var initial_sequence: Array[int] = []
	for _index: int in range(4):
		initial_sequence.append(random.next_int(0, 999999))
	var saved_state: int = random.get_state()
	var expected_follow_up: Array[int] = []
	for _index: int in range(6):
		expected_follow_up.append(random.next_int(0, 999999))
	random.restore_state(saved_state)
	var restored_follow_up: Array[int] = []
	for _index: int in range(6):
		restored_follow_up.append(random.next_int(0, 999999))
	_expect_equal(restored_follow_up, expected_follow_up, "恢复 RNG 状态后继续相同随机序列")

	random.set_seed(424242)
	var repeated_initial: Array[int] = []
	for _index: int in range(4):
		repeated_initial.append(random.next_int(0, 999999))
	_expect_equal(repeated_initial, initial_sequence, "重设相同种子重放初始序列")


func _test_random_service_baseline() -> void:
	var random := DeterministicRandomService.new(19000101)
	var checksum: int = 0
	var started_at_usec: int = Time.get_ticks_usec()
	for _index: int in range(100000):
		checksum = checksum ^ random.next_int(0, 2147483647)
	var elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(checksum != 0, "批量随机序列产生有效校验值")
	print("[PERF] 统一随机服务生成 100000 个整数：%.3f ms" % (
		float(elapsed_usec) / 1000.0
	))


func _test_core_data_loader_valid_fixture() -> void:
	var loader := CoreDataLoader.new()
	var result: CoreDataLoadResult = loader.load_from_file(
		"res://tests/fixtures/core_data_valid.json"
	)
	_expect_true(result.is_success(), "有效核心数据 fixture 可加载：%s" % [result.errors])
	if not result.is_success():
		return
	_expect_equal(
		result.data_set.get_counts(),
		{
			"countries": 1,
			"regions": 1,
			"control_units": 2,
			"population_groups": 1,
			"characters": 2,
			"organizations": 1,
			"relationships": 1,
			"actions": 1,
		},
		"有效 fixture 实例化全部核心模型"
	)
	_expect_equal(result.data_set.get_total_entity_count(), 10, "核心数据集总实体数正确")
	_expect_true(
		result.data_set.countries["country:test_republic"] is CountryData,
		"国家记录转换为强类型模型"
	)
	_expect_true(
		result.data_set.control_units["control:test_a"] is ControlUnitData,
		"控制单元记录转换为强类型模型"
	)
	_expect_true(
		result.data_set.population_groups["population:test_workers"] is PopulationGroupData,
		"人口群体记录转换为强类型模型"
	)
	_expect_true(
		result.data_set.characters["character:test_anna"] is CharacterData,
		"人物记录转换为强类型模型"
	)
	_expect_true(
		result.data_set.organizations["organization:test_union"] is OrganizationData,
		"组织记录转换为强类型模型"
	)
	_expect_true(
		result.data_set.relationships["relationship:test_anna_bo"] is RelationshipData,
		"关系记录转换为强类型模型"
	)
	_expect_true(
		result.data_set.actions["action:test_study"] is ActionDefinitionData,
		"行动记录转换为强类型模型"
	)
	var action: ActionDefinitionData = result.data_set.actions["action:test_study"] as ActionDefinitionData
	_expect_equal(
		action.interruption_conditions,
		["detained", "incapacitated"],
		"行动模型保留数据化中断条件"
	)

	var country: CountryData = result.data_set.countries["country:test_republic"] as CountryData
	var serialized: Dictionary = country.to_dict()
	serialized["public_status"]["stability"] = "mutated"
	_expect_equal(country.public_status["stability"], "stable", "模型序列化返回深拷贝数据")


func _test_core_data_loader_invalid_fixtures() -> void:
	var loader := CoreDataLoader.new()
	var duplicate_result: CoreDataLoadResult = loader.load_from_file(
		"res://tests/fixtures/core_data_duplicate_id.json"
	)
	_expect_true(not duplicate_result.is_success(), "重复 ID 数据被拒绝")
	_expect_true(duplicate_result.has_error_containing("重复 ID"), "重复 ID 错误可定位")

	var reference_result: CoreDataLoadResult = loader.load_from_file(
		"res://tests/fixtures/core_data_broken_reference.json"
	)
	_expect_true(not reference_result.is_success(), "断裂引用数据被拒绝")
	_expect_true(reference_result.has_error_containing("不存在的 ID"), "断裂引用错误可定位")

	var type_result: CoreDataLoadResult = loader.load_from_file(
		"res://tests/fixtures/core_data_invalid_type.json"
	)
	_expect_true(not type_result.is_success(), "错误字段类型数据被拒绝")
	_expect_true(type_result.has_error_containing("age 必须是整数"), "字段类型错误可定位")

	var malformed_result: CoreDataLoadResult = loader.load_from_file(
		"res://tests/fixtures/core_data_malformed.json"
	)
	_expect_true(not malformed_result.is_success(), "畸形 JSON 被拒绝")
	_expect_true(malformed_result.has_error_containing("JSON 无效"), "JSON 解析错误可定位")

	var missing_result: CoreDataLoadResult = loader.load_from_file(
		"res://tests/fixtures/does_not_exist.json"
	)
	_expect_true(not missing_result.is_success(), "缺失数据文件被安全处理")
	_expect_true(missing_result.has_error_containing("无法读取"), "缺失文件错误可定位")


func _test_core_data_loader_baseline() -> void:
	var loader := CoreDataLoader.new()
	var started_at_usec: int = Time.get_ticks_usec()
	var last_result: CoreDataLoadResult
	for _index: int in range(100):
		last_result = loader.load_from_file("res://tests/fixtures/core_data_valid.json")
	var elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(last_result.is_success(), "重复加载后核心数据仍有效")
	print("[PERF] 加载并验证 10 实体 fixture 100 次：%.3f ms" % (
		float(elapsed_usec) / 1000.0
	))


func _test_m3_world_data_and_topology() -> void:
	_map_rules = MapRulesConfig.new()
	_expect_equal(_map_rules.load_from_file(), OK, "M3 地图规则可加载")
	var load_result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	_expect_true(load_result.is_success(), "M3 正式世界数据可通过核心验证：%s" % [
		load_result.errors
	])
	if not load_result.is_success():
		return
	var data_set: CoreDataSet = load_result.data_set
	_expect_equal(data_set.countries.size(), 2, "正式世界包含 2 个架空国家")
	_expect_equal(data_set.regions.size(), 8, "正式世界包含 8 个行政地区")
	_expect_equal(data_set.control_units.size(), 80, "正式世界包含 80 个控制单元")
	_expect_equal(data_set.population_groups.size(), 8, "每个地区具有人口群体摘要")

	var city_count: int = 0
	var railroad_edges: Dictionary = {}
	var grid_positions: Dictionary = {}
	var adjacency_is_symmetric: bool = true
	for unit_value: Variant in data_set.control_units.values():
		var unit: ControlUnitData = unit_value as ControlUnitData
		grid_positions["%d,%d" % [unit.grid_x, unit.grid_y]] = true
		if not unit.city_name.is_empty():
			city_count += 1
		for neighbor_id: String in unit.neighbor_ids:
			var neighbor: ControlUnitData = data_set.control_units[neighbor_id] as ControlUnitData
			if not neighbor.neighbor_ids.has(unit.id):
				adjacency_is_symmetric = false
		for rail_neighbor_id: String in unit.railroad_neighbor_ids:
			var edge_ids: Array[String] = [unit.id, rail_neighbor_id]
			edge_ids.sort()
			railroad_edges["%s|%s" % edge_ids] = true
	_expect_equal(grid_positions.size(), 80, "80 个控制单元使用唯一网格坐标")
	_expect_equal(city_count, 4, "正式世界包含 4 座主要城市")
	_expect_equal(railroad_edges.size(), 23, "铁路拓扑包含 23 条唯一相邻连接")
	_expect_true(adjacency_is_symmetric, "所有控制单元邻接关系双向对称")
	_expect_equal(
		(data_set.control_units["control:r0_c0"] as ControlUnitData).neighbor_ids.size(),
		2,
		"地图角落单元只有两个有效邻居"
	)
	_expect_equal(
		(data_set.control_units["control:r0_c4"] as ControlUnitData).neighbor_ids.size(),
		3,
		"地图边缘单元只有三个有效邻居"
	)
	_expect_equal(
		(data_set.control_units["control:r3_c3"] as ControlUnitData).neighbor_ids.size(),
		4,
		"地图内部单元具有四个邻居"
	)
	for country_value: Variant in data_set.countries.values():
		_expect_equal(
			(country_value as CountryData).region_ids.size(),
			4,
			"每个国家拥有 4 个法理地区"
		)


func _test_m3_frontline_control_changes() -> void:
	var service: MapControlService = _create_map_service()
	_expect_true(service != null, "地图控制服务可从正式数据创建")
	if service == null:
		return
	_expect_equal(service.get_frontline_edges().size(), 8, "初始国境自动生成 8 条前线边")
	var frontline_signals: Array[int] = [0]
	service.frontlines_changed.connect(func() -> void: frontline_signals[0] += 1)

	var isolated_id: String = "control:r3_c2"
	var original_legal_owner: String = service.get_unit(isolated_id).de_jure_country_id
	_expect_true(
		service.set_control_state(isolated_id, "country:vesta_union", 0.3, 0.2),
		"控制单元可显式易手"
	)
	_expect_equal(
		service.get_unit(isolated_id).de_jure_country_id,
		original_legal_owner,
		"军事易手不改变法理归属"
	)
	_expect_equal(
		service.get_frontline_edge_count_for_unit(isolated_id),
		4,
		"孤立占领自动生成四条包围前线"
	)
	_expect_true(service.is_surrounded(isolated_id), "孤立敌方控制单元被识别为包围")
	_expect_equal(
		service.get_control_stage(isolated_id),
		MapControlService.STAGE_ENEMY_OCCUPATION,
		"低强度敌方控制显示敌方占领阶段"
	)

	service.set_control_state(isolated_id, "country:vesta_union", 0.82, 0.1)
	_expect_equal(
		service.get_control_stage(isolated_id),
		MapControlService.STAGE_CONSOLIDATING,
		"高强度敌方控制显示巩固阶段"
	)
	service.set_control_state(isolated_id, original_legal_owner, 0.92, 0.08)
	_expect_equal(service.get_frontline_edge_count_for_unit(isolated_id), 0, "恢复控制后局部前线消失")
	_expect_equal(service.get_frontline_edges().size(), 8, "恢复控制不影响原始国境前线")
	_expect_true(frontline_signals[0] >= 2, "控制者变化增量发出前线更新信号")

	service.set_control_state(isolated_id, original_legal_owner, 0.4, 0.1)
	_expect_equal(
		service.get_control_stage(isolated_id),
		MapControlService.STAGE_WEAKENING,
		"低法理控制强度显示控制减弱"
	)
	service.set_control_state(isolated_id, original_legal_owner, 0.7, 0.6)
	_expect_equal(
		service.get_control_stage(isolated_id),
		MapControlService.STAGE_CONTESTED,
		"高争夺度显示争夺阶段"
	)

	for unit_id: String in service.get_sorted_unit_ids():
		service.set_control_state(unit_id, "country:vesta_union", 0.8, 0.1)
	_expect_equal(service.get_frontline_edges().size(), 0, "统一军事控制后全部前线自动移除")


func _test_m3_pressure_capture_and_consolidation() -> void:
	var service: MapControlService = _create_map_service()
	if service == null:
		_expect_true(false, "压力测试需要有效地图服务")
		return
	var unit_id: String = "control:r4_c2"
	var defender: String = service.get_unit(unit_id).controller_country_id
	var attacker: String = service.get_other_country_id(defender)
	var iterations: int = 0
	while service.get_unit(unit_id).controller_country_id == defender and iterations < 12:
		service.apply_control_pressure(unit_id, attacker)
		iterations += 1
	_expect_equal(service.get_unit(unit_id).controller_country_id, attacker, "重复压力达到阈值后控制易手")
	_expect_true(iterations <= 12, "控制易手在有限压力次数内完成")
	_expect_equal(
		service.get_unit(unit_id).de_jure_country_id,
		defender,
		"压力占领仍保持法理与军事控制分离"
	)
	for _index: int in range(6):
		service.apply_control_pressure(unit_id, attacker)
	_expect_equal(
		service.get_control_stage(unit_id),
		MapControlService.STAGE_CONSOLIDATING,
		"占领方继续投入后进入控制巩固"
	)


func _test_m3_isolated_surrounded_and_empty_unit() -> void:
	var isolated_service: MapControlService = _create_map_service()
	if isolated_service == null:
		_expect_true(false, "孤立测试需要有效地图服务")
		return
	isolated_service.set_control_state(
		"control:r5_c2", "country:vesta_union", 0.3, 0.2
	)
	_expect_true(isolated_service.is_surrounded("control:r5_c2"), "敌方孤立控制区检测正确")

	var surrounded_service: MapControlService = _create_map_service()
	var center_id: String = "control:r3_c2"
	var center: ControlUnitData = surrounded_service.get_unit(center_id)
	for neighbor_id: String in center.neighbor_ids:
		surrounded_service.set_control_state(
			neighbor_id, "country:vesta_union", 0.8, 0.1
		)
	_expect_true(surrounded_service.is_surrounded(center_id), "四邻敌对时法理控制区检测为被包围")
	_expect_equal(
		surrounded_service.get_frontline_edge_count_for_unit(center_id),
		4,
		"被包围单元具有四条前线边"
	)

	var empty_data_set := CoreDataSet.new()
	var empty_neighbor_unit := ControlUnitData.new()
	empty_neighbor_unit.id = "control:no_neighbors"
	empty_neighbor_unit.region_id = "region:none"
	empty_neighbor_unit.grid_x = 0
	empty_neighbor_unit.grid_y = 0
	empty_neighbor_unit.city_name = ""
	empty_neighbor_unit.neighbor_ids = []
	empty_neighbor_unit.de_jure_country_id = "country:none"
	empty_neighbor_unit.controller_country_id = "country:none"
	empty_neighbor_unit.railroad_neighbor_ids = []
	empty_data_set.control_units[empty_neighbor_unit.id] = empty_neighbor_unit
	var empty_service := MapControlService.new(empty_data_set, _map_rules)
	_expect_equal(empty_service.get_frontline_edges().size(), 0, "无邻居单元不会生成错误前线")
	_expect_true(not empty_service.is_surrounded(empty_neighbor_unit.id), "无邻居单元不被误判为包围")


func _test_m3_region_summary() -> void:
	var service: MapControlService = _create_map_service()
	if service == null:
		_expect_true(false, "地区摘要测试需要有效地图服务")
		return
	var summary: Dictionary = service.get_region_summary("region:loran_riverback")
	_expect_equal(summary["unit_count"], 10, "地区摘要包含 10 个控制单元")
	_expect_equal(summary["population_total"], 206000, "地区摘要汇总人口群体")
	_expect_true(int(summary["railroad_connections"]) > 0, "地区摘要报告铁路连接")
	_expect_approx(
		float((summary["control_percentages"] as Dictionary)["country:loran_federation"]),
		1.0,
		0.000001,
		"初始地区军事控制比例为 100%"
	)
	_expect_true(
		(summary["social_influence"] as Dictionary).has("country:vesta_union"),
		"地区摘要保留独立社会影响数据"
	)


func _test_m3_strategic_map_scene() -> void:
	var scene_resource: Resource = load("res://scenes/map/strategic_map_view.tscn")
	_expect_true(scene_resource is PackedScene, "M3 战略地图场景可加载")
	if not scene_resource is PackedScene:
		return
	var view: Node = (scene_resource as PackedScene).instantiate()
	get_root().add_child(view)
	var controller: MapWorldController = view.get_node("MapWorldController") as MapWorldController
	var canvas: StrategicMapCanvas = view.get_node(
		"RootMargin/Layout/Content/MapPanel/MapCanvas"
	) as StrategicMapCanvas
	_expect_true(controller.control_service != null, "地图场景加载正式世界控制服务")
	_expect_equal(canvas.get_world_size(), Vector2(860.0, 544.0), "地图画布尺寸匹配 10×8 网格")
	_expect_equal(canvas.selected_unit_id, "control:r3_c4", "地图场景默认选择边境单元")
	var selection_title: Label = view.get_node(
		"RootMargin/Layout/Content/SidePanel/SideMargin/SideContent/SelectionTitle"
	) as Label
	_expect_true(not selection_title.text.is_empty(), "地区信息面板显示选中地区")
	var details_label: RichTextLabel = view.get_node(
		"RootMargin/Layout/Content/SidePanel/SideMargin/SideContent/DetailsLabel"
	) as RichTextLabel
	_expect_true(details_label.text.contains("铁路状态"), "地区信息面板显示铁路状态")

	canvas.set_zoom(99.0)
	_expect_approx(canvas.get_zoom(), controller.rules.max_zoom, 0.000001, "缩放上限受配置约束")
	canvas.set_zoom(0.01)
	_expect_approx(canvas.get_zoom(), controller.rules.min_zoom, 0.000001, "缩放下限受配置约束")
	canvas.pan_by(Vector2(100000.0, -100000.0))
	var pan: Vector2 = canvas.get_pan_offset()
	_expect_true(is_finite(pan.x) and is_finite(pan.y), "极端拖动后平移状态保持有限")

	var selected_before: String = controller.control_service.get_unit(
		canvas.selected_unit_id
	).controller_country_id
	var transfer_button: Button = view.get_node(
		"RootMargin/Layout/Content/SidePanel/SideMargin/SideContent/TransferButton"
	) as Button
	transfer_button.pressed.emit()
	_expect_true(
		controller.control_service.get_unit(canvas.selected_unit_id).controller_country_id
		!= selected_before,
		"信息面板的模拟易手按钮更新权威控制数据"
	)
	view.queue_free()


func _test_m3_world_performance_baseline() -> void:
	var loader := CoreDataLoader.new()
	var started_at_usec: int = Time.get_ticks_usec()
	var last_result: CoreDataLoadResult
	for _index: int in range(20):
		last_result = loader.load_from_file("res://data/world/demo_world.json")
	var load_elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(last_result.is_success(), "正式世界重复加载后仍通过验证")

	var service := MapControlService.new(last_result.data_set, _map_rules)
	started_at_usec = Time.get_ticks_usec()
	var country_ids: Array[String] = service.get_country_ids()
	var unit_ids: Array[String] = service.get_sorted_unit_ids()
	for index: int in range(800):
		var unit_id: String = unit_ids[index % unit_ids.size()]
		service.set_control_state(
			unit_id,
			country_ids[index % country_ids.size()],
			0.6,
			0.2
		)
	var control_elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	print("[PERF] 加载并验证 98 实体正式世界 20 次：%.3f ms" % (
		float(load_elapsed_usec) / 1000.0
	))
	print("[PERF] 80 单元地图执行 800 次增量控制更新：%.3f ms" % (
		float(control_elapsed_usec) / 1000.0
	))


func _test_m4_generation_config_and_country_requirement() -> void:
	_character_config = CharacterGenerationConfig.load_from_file()
	_expect_true(_character_config.is_valid(), "M4 人物生成配置有效")
	_expect_equal(_character_config.occupations.size(), 10, "人物生成配置包含 10 类职业")
	_expect_equal(_character_config.get_category_ids().size(), 5, "分类随机包含 5 类人物")
	_expect_approx(_character_config.growth_modifier(0), 0.8, 0.000001, "最低潜质成长修正为 0.8")
	_expect_approx(_character_config.growth_modifier(100), 1.2, 0.000001, "最高潜质成长修正为 1.2")
	var world_result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	_expect_true(world_result.is_success(), "M4 生成器可加载正式世界")
	_world_data = world_result.data_set
	var invalid: CharacterGenerationResult = _make_character_generator(1).generate_character(
		"", CharacterGenerator.MODE_STANDARD
	)
	_expect_true(not invalid.is_success(), "未明确选择国家时拒绝生成")
	_expect_true(invalid.errors[0].contains("明确选择"), "国家必选错误可读")


func _test_m4_same_seed_same_character() -> void:
	var first: CharacterGenerationResult = _make_character_generator(19000101).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	var second: CharacterGenerationResult = _make_character_generator(19000101).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	_expect_true(first.is_success() and second.is_success(), "固定种子人物生成成功")
	_expect_equal(first.character.to_dict(), second.character.to_dict(), "同国家、模式和种子生成完全相同人物")
	var other: CharacterGenerationResult = _make_character_generator(19000102).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	_expect_true(other.is_success(), "不同种子人物生成成功")
	_expect_true(first.character.to_dict() != other.character.to_dict(), "不同种子产生不同人物")
	_expect_equal(first.character.hidden_aptitudes.size(), 6, "人物包含 6 项隐藏潜质")
	_expect_equal(first.character.skills.size(), 9, "人物包含 9 项可见技能")


func _test_m4_random_modes_and_age_rules() -> void:
	var standard: CharacterGenerationResult = _make_character_generator(42).generate_character(
		"country:vesta_union", CharacterGenerator.MODE_STANDARD
	)
	_expect_true(standard.is_success(), "标准随机模式可生成人物")
	_expect_true(not standard.character.is_challenge_start, "标准随机排除困难人口职业")
	var category: CharacterGenerationResult = _make_character_generator(43).generate_character(
		"country:vesta_union", CharacterGenerator.MODE_CATEGORY, "military"
	)
	_expect_true(category.is_success(), "分类随机模式可生成指定类别")
	_expect_equal(category.character.occupation_id, "junior_officer", "军方类别只生成军方职业")
	var found_challenge: bool = false
	for seed_value: int in range(1, 80):
		var full: CharacterGenerationResult = _make_character_generator(seed_value).generate_character(
			"country:vesta_union", CharacterGenerator.MODE_FULL_POPULATION
		)
		if full.is_success() and full.character.is_challenge_start:
			found_challenge = true
			break
	_expect_true(found_challenge, "全人口随机能够抽中困难开局")

	var generator: CharacterGenerator = _make_character_generator(9)
	var weights: Dictionary = {}
	for index: int in range(_character_config.trait_keys.size()):
		weights[_character_config.trait_keys[index]] = index * 10
	_expect_equal(generator._manifest_traits(17, weights).size(), 0, "18 岁前性格表现不显现")
	var young_count: int = generator._manifest_traits(18, weights).size()
	_expect_true(young_count >= 1 and young_count <= 2, "18 至 24 岁显现 1 至 2 项性格")
	var adult_count: int = generator._manifest_traits(25, weights).size()
	_expect_true(adult_count >= 2 and adult_count <= 4, "25 岁起显现 2 至 4 项性格")


func _test_m4_hidden_information_boundary() -> void:
	var generated: CharacterGenerationResult = _make_character_generator(77).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	var public_data: Dictionary = generated.character.to_public_dict()
	for hidden_key: String in ["hidden_aptitudes", "temperament_weights", "tendencies", "generation_seed", "random_state"]:
		_expect_true(not public_data.has(hidden_key), "正式人物数据不包含隐藏字段：%s" % hidden_key)
	_expect_true(public_data.has("skills") and public_data.has("known_tendencies"), "正式人物数据保留技能和已知倾向")
	var public_copy: Dictionary = public_data["skills"] as Dictionary
	public_copy["administration"] = -1
	_expect_true(int(generated.character.skills["administration"]) >= 0, "正式人物数据返回深拷贝")


func _test_m4_dynamic_tendencies() -> void:
	var generated: CharacterGenerationResult = _make_character_generator(88).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	var character: CharacterData = generated.character
	var before: int = int(character.tendencies["government_support"])
	var service := CharacterTendencyService.new(_character_config)
	_expect_true(service.apply_event(character, "propaganda"), "配置事件可更新人物倾向")
	_expect_equal(int(character.tendencies["government_support"]), clampi(before + 8, -100, 100), "宣传事件按配置改变政府倾向")
	_expect_equal(character.known_tendencies["government_support"], _character_config.describe_tendency("government_support", int(character.tendencies["government_support"])), "倾向变化后刷新公开定性描述")
	_expect_true(not service.apply_event(character, "missing_event"), "未知倾向事件被安全拒绝")


func _test_m4_character_scenes() -> void:
	var setup_resource: Resource = load("res://scenes/character/character_setup_view.tscn")
	_expect_true(setup_resource is PackedScene, "M4 人物创建场景可加载")
	if setup_resource is PackedScene:
		var setup: Node = (setup_resource as PackedScene).instantiate()
		get_root().add_child(setup)
		var country_option: OptionButton = setup.get_node("Margin/Root/Columns/ControlsPanel/ControlsMargin/Controls/CountryOption") as OptionButton
		var enter_button: Button = setup.get_node("Margin/Root/Bottom/EnterButton") as Button
		var generate_button: Button = setup.get_node("Margin/Root/Columns/ControlsPanel/ControlsMargin/Controls/GenerateButton") as Button
		var preview_label: RichTextLabel = setup.get_node("Margin/Root/Columns/PreviewPanel/PreviewMargin/PreviewLabel") as RichTextLabel
		_expect_equal(str(country_option.get_item_metadata(0)), "", "人物创建默认不预选国家")
		_expect_true(enter_button.disabled, "生成人物前不能进入地图")
		country_option.select(1)
		generate_button.pressed.emit()
		_expect_true(not enter_button.disabled, "明确选择国家后可生成并进入地图")
		_expect_true(preview_label.text.contains("可见技能"), "生成预览显示正式人物技能")
		setup.queue_free()

	var generated: CharacterGenerationResult = _make_character_generator(99).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	GameSessionService.set_player(generated.character)
	var profile_resource: Resource = load("res://scenes/character/character_profile_view.tscn")
	_expect_true(profile_resource is PackedScene, "M4 人物信息场景可加载")
	if profile_resource is PackedScene:
		var profile: Node = (profile_resource as PackedScene).instantiate()
		get_root().add_child(profile)
		var developer_panel: PanelContainer = profile.get_node("Margin/Root/Columns/DeveloperPanel") as PanelContainer
		var public_label: RichTextLabel = profile.get_node("Margin/Root/Columns/PublicPanel/PublicMargin/PublicLabel") as RichTextLabel
		var developer_toggle: CheckButton = profile.get_node("Margin/Root/Top/DeveloperToggle") as CheckButton
		_expect_true(not developer_panel.visible, "开发者隐藏数据面板默认关闭")
		_expect_true(not public_label.text.contains("潜质"), "正式人物面板不泄露隐藏潜质")
		developer_toggle.button_pressed = true
		_expect_true(developer_panel.visible, "开发者开关可显式显示隐藏数据")
		profile.queue_free()
	GameSessionService.clear()


func _test_m4_generation_performance_baseline() -> void:
	var started_at_usec: int = Time.get_ticks_usec()
	var last_result: CharacterGenerationResult
	for seed_value: int in range(1000, 2000):
		last_result = _make_character_generator(seed_value).generate_character(
			"country:loran_federation", CharacterGenerator.MODE_FULL_POPULATION
		)
	var elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(last_result.is_success(), "连续生成 1000 人物后结果仍有效")
	print("[PERF] 生成 1000 个完整随机人物：%.3f ms" % (float(elapsed_usec) / 1000.0))


func _test_m5_action_definitions_and_rules() -> void:
	_action_rules = ActionRulesConfig.new()
	_expect_equal(_action_rules.load_from_file(), OK, "M5 行动规则配置可加载")
	_expect_equal(_world_data.actions.size(), 8, "正式世界包含八类基础行动")
	var expected_categories: Array[String] = [
		"build_relationship", "investigate_character", "join_organization",
		"perform_work", "promote_policy", "seek_position", "study_skill",
		"support_control",
	]
	var actual_categories: Array[String] = []
	for raw_action: Variant in _world_data.actions.values():
		var definition: ActionDefinitionData = raw_action as ActionDefinitionData
		actual_categories.append(definition.category)
		_expect_true(definition.total_work > 0.0 and definition.base_progress_per_hour > 0.0, "行动工作量和基础进度有效：%s" % definition.id)
		_expect_true(definition.guaranteed_success_threshold >= definition.success_threshold, "必然成功阈值不低于普通阈值：%s" % definition.id)
	actual_categories.sort()
	_expect_equal(actual_categories, expected_categories, "八类行动类别完整且无重复")
	_expect_equal(_action_rules.get_outlook(1000.0, 100.0), "条件充分，必然成功", "正式把握包含必然成功档")


func _test_m5_start_permissions_and_effective_value() -> void:
	var character: CharacterData = _make_action_character(60, 510)
	var definition: ActionDefinitionData = _world_data.actions["action:seek_position"] as ActionDefinitionData
	var service: ActionService = _make_action_service()
	var denied: ActionStartResult = service.start_action(definition, character, 0, {})
	_expect_true(not denied.is_success(), "缺少职位权限时不能开始受限行动")
	_expect_true(denied.errors[0].contains("职位权限"), "职位权限错误可读")
	var low_context: Dictionary = _action_context(definition, 0.0)
	var high_context: Dictionary = _action_context(definition, 100.0)
	var low_value: float = service.calculate_effective_value(definition, character, low_context)
	var high_value: float = service.calculate_effective_value(definition, character, high_context)
	_expect_true(high_value > low_value, "准备、支持和资金提高行动有效值")
	var started: ActionStartResult = service.start_action(definition, character, 0, high_context)
	_expect_true(started.is_success(), "具备权限与有效上下文时行动可开始")
	_expect_equal(started.action.status, ActionInstanceData.STATUS_ACTIVE, "新行动进入进行中状态")
	_expect_true(started.action.estimated_completion_hour > 0, "行动记录预计完成小时")


func _test_m5_progress_frame_independence() -> void:
	var definition: ActionDefinitionData = _world_data.actions["action:promote_policy"] as ActionDefinitionData
	var first_character: CharacterData = _make_action_character(55, 520)
	var second_character: CharacterData = _make_action_character(55, 520)
	var context: Dictionary = _action_context(definition, 35.0)
	var first_service: ActionService = _make_action_service()
	var second_service: ActionService = _make_action_service()
	var first: ActionInstanceData = first_service.start_action(definition, first_character, 0, context).action
	var second: ActionInstanceData = second_service.start_action(definition, second_character, 0, context).action
	first_service.update_to_hour(first, definition, first_character, 30)
	for hour_value: int in [3, 7, 12, 19, 30]:
		second_service.update_to_hour(second, definition, second_character, hour_value)
	_expect_approx(first.accumulated_work, second.accumulated_work, 0.000001, "相同时间不同查询分块产生相同行动进度")
	_expect_equal(first.status, second.status, "不同查询分块保持相同行动状态")
	_expect_equal(first.estimated_completion_hour, second.estimated_completion_hour, "不同查询分块保持相同预计完成时间")


func _test_m5_dependency_recalculation() -> void:
	var definition: ActionDefinitionData = _world_data.actions["action:study_skill"] as ActionDefinitionData
	var character: CharacterData = _make_action_character(50, 525)
	var service: ActionService = _make_action_service()
	var action: ActionInstanceData = service.start_action(definition, character, 0, {}).action
	var old_efficiency: float = action.current_efficiency
	var high_context: Dictionary = _action_context(definition, 100.0)
	_expect_true(service.update_context(action, definition, character, 10, high_context), "行动依赖项可在进行中更新")
	_expect_approx(action.accumulated_work, old_efficiency * 10.0, 0.000001, "依赖变化前先按旧效率结算时间区间")
	_expect_true(action.current_efficiency > old_efficiency, "追加准备与支持后重新计算更高效率")
	var prepared_efficiency: float = action.current_efficiency
	character.current_status["fatigue"] = 100
	service.update_context(action, definition, character, 10, {})
	_expect_true(action.current_efficiency < prepared_efficiency, "人物状态变化重新计算行动效率")


func _test_m5_pause_resume_cancel_and_interrupt() -> void:
	var definition: ActionDefinitionData = _world_data.actions["action:study_skill"] as ActionDefinitionData
	var character: CharacterData = _make_action_character(45, 530)
	var service: ActionService = _make_action_service()
	var action: ActionInstanceData = service.start_action(definition, character, 0, {}).action
	service.update_to_hour(action, definition, character, 10)
	_expect_true(service.pause_action(action, definition, character, 10), "进行中行动可暂停")
	var paused_work: float = action.accumulated_work
	service.update_to_hour(action, definition, character, 30)
	_expect_approx(action.accumulated_work, paused_work, 0.000001, "暂停期间行动不推进")
	_expect_true(service.resume_action(action, definition, character, 30), "暂停行动可恢复")
	service.update_to_hour(action, definition, character, 40)
	_expect_true(action.accumulated_work > paused_work, "恢复后行动继续推进")
	_expect_true(service.cancel_action(action, definition, character, 40), "未完成行动可取消")
	var cancelled_work: float = action.accumulated_work
	service.update_to_hour(action, definition, character, 100)
	_expect_equal(action.status, ActionInstanceData.STATUS_CANCELLED, "取消状态保持终止")
	_expect_approx(action.accumulated_work, cancelled_work, 0.000001, "取消后不再推进")

	var interrupted_character: CharacterData = _make_action_character(45, 531)
	var interrupted: ActionInstanceData = service.start_action(definition, interrupted_character, 0, {}).action
	service.update_to_hour(interrupted, definition, interrupted_character, 5)
	interrupted_character.current_status["detained"] = true
	service.update_to_hour(interrupted, definition, interrupted_character, 6)
	_expect_equal(interrupted.status, ActionInstanceData.STATUS_INTERRUPTED, "拘押条件触发行动中断")
	_expect_equal(interrupted.interruption_reason, "detained", "行动记录中断原因")


func _test_m5_thresholds_and_result_application() -> void:
	var definition: ActionDefinitionData = _world_data.actions["action:study_skill"] as ActionDefinitionData
	var failure_character: CharacterData = _make_action_character(0, 540)
	var failure_service: ActionService = _make_action_service()
	var failure: ActionInstanceData = failure_service.start_action(definition, failure_character, 0, {}).action
	failure_service.update_to_hour(failure, definition, failure_character, 1000)
	_expect_equal(failure.outcome_code, "failure", "低有效值行动按失败结果结算")
	_expect_equal(int(failure_character.skills[definition.primary_skill]), 1, "失败结果只应用少量技能经验")
	var once_skill: int = int(failure_character.skills[definition.primary_skill])
	failure_service.update_to_hour(failure, definition, failure_character, 2000)
	_expect_equal(int(failure_character.skills[definition.primary_skill]), once_skill, "完成结果不会重复应用")

	var success_character: CharacterData = _make_action_character(80, 541)
	var success_service: ActionService = _make_action_service()
	var success_context: Dictionary = _action_context(definition, 0.0)
	success_context["preparation"] = 100.0
	var success: ActionInstanceData = success_service.start_action(definition, success_character, 0, success_context).action
	success_service.update_to_hour(success, definition, success_character, 1000)
	_expect_equal(success.outcome_code, "success", "达到普通阈值但未达必然阈值时成功")
	_expect_equal(int(success_character.skills[definition.primary_skill]), 84, "成功结果提高主要技能")

	var guaranteed_character: CharacterData = _make_action_character(100, 542)
	var guaranteed_service: ActionService = _make_action_service()
	var guaranteed: ActionInstanceData = guaranteed_service.start_action(definition, guaranteed_character, 0, _action_context(definition, 100.0)).action
	guaranteed_service.update_to_hour(guaranteed, definition, guaranteed_character, 1000)
	_expect_equal(guaranteed.outcome_code, "guaranteed_success", "充分准备和支持达到必然成功")
	_expect_equal(guaranteed.outlook, "条件充分，必然成功", "必然成功只以定性文本呈现")


func _test_m5_control_result_application() -> void:
	var service_map: MapControlService = _create_map_service()
	var definition: ActionDefinitionData = service_map.data_set.actions["action:support_control"] as ActionDefinitionData
	var character: CharacterData = _make_action_character(100, 550)
	character.country_id = "country:loran_federation"
	var society := SocietySimulationService.new()
	_expect_true(
		society.initialize(character, service_map.data_set),
		"地区控制支援夹具可初始化权威社会服务"
	)
	var context: Dictionary = _action_context(definition, 100.0)
	context["target_id"] = "control:r3_c5"
	var unit: ControlUnitData = service_map.get_unit("control:r3_c5")
	var strength_before: float = unit.control_strength
	var service: ActionService = _make_action_service()
	var action: ActionInstanceData = service.start_action(definition, character, 0, context).action
	service.update_to_hour(action, definition, character, 2000, service_map)
	_expect_equal(action.outcome_code, "guaranteed_success", "地区控制支援可达到必然成功")
	_expect_approx(
		unit.control_strength,
		strength_before,
		0.000001,
		"通用行动结算不越权修改地图"
	)
	_expect_true(
		society.apply_character_action_domain_effect(
			action, definition, character, service_map, "player_contact"
		),
		"完成行动可通过社会领域服务写回地图"
	)
	_expect_true(unit.control_strength < strength_before, "成功的地区控制行动应用到目标控制单元")


func _test_m5_action_panel_scene() -> void:
	var character: CharacterData = _make_action_character(60, 560)
	GameSessionService.set_player(character)
	var scene_resource: Resource = load("res://scenes/map/strategic_map_view.tscn")
	var view: Node = (scene_resource as PackedScene).instantiate()
	get_root().add_child(view)
	var action_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/ActionButton") as Button
	var panel: ActionPanel = view.get_node("ActionPanel") as ActionPanel
	_expect_true(not action_button.disabled, "有玩家人物时地图行动入口可用")
	_expect_true(not panel.visible, "长期行动面板默认关闭")
	action_button.pressed.emit()
	_expect_true(panel.visible, "行动入口可打开长期行动面板")
	var action_option: OptionButton = panel.get_node("Margin/Root/Scroll/Content/ActionOption") as OptionButton
	_expect_equal(action_option.item_count, 8, "行动面板列出八类正式行动")
	var begin_button: Button = panel.get_node("Margin/Root/BeginButton") as Button
	begin_button.pressed.emit()
	_expect_true(GameSessionService.current_action != null, "行动面板可开始当前人物行动")
	var runner: SimulationRunner = view.get_node("SimulationRunner") as SimulationRunner
	if GameSessionService.current_action != null:
		var before: float = GameSessionService.current_action.accumulated_work
		runner.clock.advance_hours(1)
		_expect_true(GameSessionService.current_action.accumulated_work > before, "权威时间变化驱动当前行动进度")
	var summary: RichTextLabel = panel.get_node("Margin/Root/Scroll/Content/SummaryLabel") as RichTextLabel
	_expect_true(summary.text.contains("成功把握") and not summary.text.contains("有效值"), "正式行动 UI 显示定性把握且隐藏精确值")
	view.queue_free()
	GameSessionService.clear()


func _test_m5_action_performance_baseline() -> void:
	var definition: ActionDefinitionData = _world_data.actions["action:build_relationship"] as ActionDefinitionData
	var character: CharacterData = _make_action_character(50, 570)
	var service: ActionService = _make_action_service()
	var context: Dictionary = _action_context(definition, 30.0)
	var started_at_usec: int = Time.get_ticks_usec()
	var checksum: float = 0.0
	for _index: int in range(10000):
		checksum += service.calculate_effective_value(definition, character, context)
	var elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(checksum != 0.0, "10000 次行动查询产生有效校验值")
	print("[PERF] 计算 10000 次行动有效值：%.3f ms" % (float(elapsed_usec) / 1000.0))


func _test_m6_society_rules_and_organizations() -> void:
	_society_rules = SocietyRulesConfig.new()
	_expect_equal(_society_rules.load_from_file(), OK, "M6 社会模拟规则可加载")
	_expect_equal(_society_rules.background_character_count, 120, "背景人物目标为 120 人")
	_expect_equal(_society_rules.active_character_limit, 20, "活跃人物硬上限为 20 人")
	_expect_equal(_world_data.organizations.size(), 8, "正式世界包含两国各四类组织")
	var organization_service := OrganizationService.new(_world_data.organizations)
	_expect_equal(
		organization_service.get_types(),
		["enterprise", "government", "military", "union"],
		"政府、军队、企业和工会四类组织完整"
	)
	for organization_id: String in organization_service.get_organization_ids():
		var organization: OrganizationData = organization_service.get_organization(organization_id)
		var positions: Dictionary = organization.position_structure["positions"] as Dictionary
		_expect_true(positions.size() >= 3, "组织具有至少三级职位：%s" % organization_id)
		_expect_true(not organization.organization_relations.has(organization_id), "组织关系不包含自身：%s" % organization_id)


func _test_m6_population_tiers_and_determinism() -> void:
	_society = _make_society(610)
	_expect_true(_society != null, "M6 社会模拟服务可初始化")
	_expect_equal(_society.roster.get_total_character_count(), 121, "120 名世界人物加 1 名玩家身份完整")
	_expect_equal(_society.roster.background_characters.size(), 112, "8 名组织领导升级后保留 112 名背景人物")
	_expect_equal(_society.roster.active_characters.size(), 9, "玩家和 8 名组织领导处于活跃层")
	_expect_true(_society.roster.active_characters.size() <= 20, "初始活跃人物不超过上限")
	for character_id: String in _society.roster.get_background_ids():
		var background: BackgroundCharacterData = _society.roster.get_background(character_id)
		_expect_true(background is RefCounted, "背景人物只使用轻量 RefCounted 数据记录")
		break
	for organization_id: String in _society.organizations.get_organization_ids():
		var organization: OrganizationData = _society.organizations.get_organization(organization_id)
		_expect_true(not organization.leader_character_id.is_empty(), "组织已配置活跃领导：%s" % organization_id)
		_expect_true(_society.roster.get_active(organization.leader_character_id) != null, "组织领导位于活跃层：%s" % organization_id)

	var second: SocietySimulationService = _make_society(610)
	var first_ids: Array[String] = _society.roster.get_background_ids()
	var second_ids: Array[String] = second.roster.get_background_ids()
	_expect_equal(first_ids, second_ids, "相同配置和种子产生相同背景人物 ID 集合")
	for index: int in range(5):
		_expect_equal(
			_society.roster.get_background(first_ids[index]).to_dict(),
			second.roster.get_background(second_ids[index]).to_dict(),
			"背景人物生成可复现：%d" % index
		)


func _test_m6_membership_positions_and_permissions() -> void:
	var player: CharacterData = _society.roster.get_active(_society.roster.player_character_id)
	var organization_id: String = "organization:loran_government"
	var organization: OrganizationData = _society.organizations.get_organization(organization_id)
	_expect_true(not _society.organizations.has_permission(player.id, organization_id, "regional_policy"), "高技能人物无职位时不获得政策权限")
	for raw_skill: Variant in player.skills:
		player.skills[raw_skill] = 100
	_expect_true(not _society.organizations.has_permission(player.id, organization_id, "regional_policy"), "技能满值仍不能替代正式职位")
	_expect_true(not _society.organizations.join_organization(player, "organization:vesta_government"), "人物不能直接加入外国组织")
	_expect_true(_society.organizations.join_organization(player, organization_id), "玩家可加入本国政府组织")
	_expect_equal(_society.organizations.get_position_id(player.id, organization_id), "clerk", "加入组织获得入口职位")
	_expect_true(_society.organizations.has_permission(player.id, organization_id, "organization_member"), "入口职位授予组织成员权限")
	_expect_true(not _society.organizations.has_permission(player.id, organization_id, "regional_policy"), "入口职位不越级授予政策权限")
	_expect_true(_society.organizations.assign_position(player, organization_id, "regional_official"), "成员可调整到有空位的地区职位")
	_expect_true(_society.organizations.has_permission(player.id, organization_id, "regional_policy"), "地区职位授予政策权限")
	_expect_true(not _society.organizations.assign_position(player, organization_id, "minister"), "已占用的唯一领导职位拒绝第二任职者")
	_expect_true(_society.organizations.leave_organization(player, organization_id), "玩家可离开组织")
	_expect_true(not _society.organizations.has_permission(player.id, organization_id, "organization_member"), "离开组织后职位权限立即移除")
	_expect_true(not organization.member_ids.has(player.id), "离开组织同步移除成员索引")


func _test_m6_sparse_relationships() -> void:
	var player_id: String = _society.roster.player_character_id
	var background_ids: Array[String] = _society.roster.get_background_ids()
	var target_id: String = background_ids[0]
	_expect_equal(_society.relationships.size(), 0, "人物名册不会预建两两关系矩阵")
	_expect_true(_society.relationships.create_or_update(player_id, player_id, 0) == null, "关系服务拒绝人物与自身建立关系")
	var relationship: RelationshipData = _society.relationships.create_or_update(
		player_id, target_id, 10, {"familiarity": 0.2, "trust": 0.1}, "cooperation"
	)
	_expect_true(relationship != null, "实际接触时按需创建关系")
	_expect_equal(_society.relationships.size(), 1, "一次实际接触只创建一个关系记录")
	var same: RelationshipData = _society.relationships.create_or_update(
		target_id, player_id, 20, {"trust": 0.2}, "cooperation"
	)
	_expect_equal(same.id, relationship.id, "反向人物对复用同一稳定关系 ID")
	_expect_approx(same.trust, 0.3, 0.000001, "已有关系按增量更新信任")
	_expect_equal(same.last_interaction_hour, 20, "关系记录最后重要互动小时")
	_expect_true(_society.relationships.get_between(background_ids[1], background_ids[2]) == null, "未接触人物对保持无关系记录")
	_expect_equal(_society.relationships.get_for_character(player_id).size(), 1, "人物关系索引只返回实际联系")
	_expect_true(_society.roster.get_active(player_id).relationship_ids.has(relationship.id), "活跃人物记录同步稳定关系 ID")
	_expect_true(_society.roster.get_background(target_id).relationship_ids.has(relationship.id), "背景人物轻量记录同步关系 ID")


func _test_m6_promotion_demotion_and_limit() -> void:
	var background_id: String = _society.roster.get_background_ids()[0]
	var before: BackgroundCharacterData = _society.roster.get_background(background_id)
	var original_name: String = before.name
	var original_total: int = _society.roster.get_total_character_count()
	var promoted: CharacterData = _society.promote_background(background_id)
	_expect_true(promoted != null, "背景人物可升级为活跃人物")
	_expect_equal(promoted.id, background_id, "升级保持稳定人物 ID")
	_expect_equal(promoted.name, original_name, "升级保持人物姓名和身份")
	_expect_true(promoted.skills.size() == 9 and promoted.hidden_aptitudes.size() == 6, "升级后补全活跃人物数据")
	_expect_true(_society.ai.get_state(background_id) != null, "升级后才创建活跃 AI 状态")
	_expect_equal(_society.roster.get_total_character_count(), original_total, "人物升层不创建同名替代人物")
	var demoted: BackgroundCharacterData = _society.demote_active(background_id)
	_expect_true(demoted != null, "非玩家非领导活跃人物可降级")
	_expect_equal(demoted.id, background_id, "降级继续保持稳定人物 ID")
	_expect_equal(demoted.name, original_name, "降级保持公开身份")
	_expect_true(_society.ai.get_state(background_id) == null, "降级后移除完整 AI 状态")
	_expect_true(_society.demote_active(_society.roster.player_character_id) == null, "玩家人物不可降级")

	var limited: SocietySimulationService = _make_society(620)
	while limited.roster.active_characters.size() < limited.rules.active_character_limit:
		var candidate_ids: Array[String] = limited.roster.get_background_ids()
		_expect_true(limited.promote_background(candidate_ids[0]) != null, "上限以内背景人物可升级")
	var extra_id: String = limited.roster.get_background_ids()[0]
	_expect_true(limited.promote_background(extra_id) == null, "达到 20 人上限后拒绝继续升级")
	_expect_equal(limited.roster.active_characters.size(), 20, "活跃人物严格不超过 20 人")
	_expect_equal(limited.ai.states.size(), 19, "AI 状态只属于除玩家外的活跃人物")
	_expect_true(limited.roster.background_characters.size() >= 100, "达到活跃上限后仍保持背景人物目标规模")


func _test_m6_ai_frequency_and_determinism() -> void:
	var ai_ids: Array[String] = _society.ai.get_ai_character_ids()
	_expect_equal(ai_ids.size(), 8, "初始只有 8 名活跃 NPC 运行 AI")
	var background_id: String = _society.roster.get_background_ids()[0]
	_expect_true(_society.ai.get_state(background_id) == null, "背景人物不运行完整 AI")
	_expect_equal(_society.ai.run_daily_decisions(0), 0, "同一日内不重复执行短期决策")
	_expect_equal(_society.ai.run_daily_decisions(24), 8, "每日边界只评估活跃 NPC")
	_expect_equal(_society.ai.run_long_term_evaluations(719), 0, "长期计划未到月度间隔不执行")
	_expect_equal(_society.ai.run_long_term_evaluations(720), 8, "月度间隔评估活跃 NPC 长期目标")
	var first_state: AiStateData = _society.ai.get_state(ai_ids[0])
	_expect_equal(first_state.daily_decision_count, 2, "AI 调试状态记录每日决策次数")
	_expect_equal(first_state.long_term_evaluation_count, 2, "AI 调试状态记录长期评估次数")
	_expect_true(not first_state.current_goal.is_empty() and not first_state.current_action_id.is_empty(), "活跃 AI 具有目标和最终行动选择")
	_expect_true(not first_state.candidate_actions.is_empty() and first_state.candidate_actions[0].has("weight"), "AI 调试状态保留有限候选及权重")

	var deterministic: SocietySimulationService = _make_society(610)
	var deterministic_state: AiStateData = deterministic.ai.get_state(ai_ids[0])
	deterministic.ai.run_daily_decisions(24)
	deterministic.ai.run_long_term_evaluations(720)
	_expect_equal(first_state.current_goal, deterministic_state.current_goal, "相同人物状态产生相同长期目标")
	_expect_equal(first_state.candidate_actions, deterministic_state.candidate_actions, "相同人物状态产生相同候选权重和排序")

	var tired_character: CharacterData = _society.roster.get_active(ai_ids[0])
	tired_character.current_status["fatigue"] = 100
	tired_character.current_status["stress"] = 100
	_society.ai.run_daily_decisions(48)
	_expect_equal(_society.ai.get_state(ai_ids[0]).current_action_id, "rest", "高疲劳高压力使有限状态机选择恢复")

	var clock_society: SocietySimulationService = _make_society(630)
	var clock: SimulationClock = _create_clock()
	clock_society.attach_clock(clock)
	var clock_ai_id: String = clock_society.ai.get_ai_character_ids()[0]
	var initial_daily: int = clock_society.ai.get_state(clock_ai_id).daily_decision_count
	clock.advance_hours(24)
	_expect_equal(clock_society.ai.get_state(clock_ai_id).daily_decision_count, initial_daily + 1, "权威日事件触发 AI 每日决策")
	clock.advance_hours(720)
	_expect_equal(clock_society.ai.get_state(clock_ai_id).long_term_evaluation_count, 2, "权威月事件触发长期计划评估")
	clock.advance_hours(672)
	_expect_equal(clock_society.ai.get_state(clock_ai_id).long_term_evaluation_count, 3, "二月 28 天月界仍触发长期计划评估")


func _test_m6_social_panel_scene() -> void:
	var player: CharacterData = _make_action_character(60, 640)
	GameSessionService.set_player(player)
	var scene_resource: Resource = load("res://scenes/map/strategic_map_view.tscn")
	var view: Node = (scene_resource as PackedScene).instantiate()
	get_root().add_child(view)
	var social_button: Button = view.get_node("RootMargin/Layout/TopBar/TopMargin/TopControls/SocialButton") as Button
	var panel: SocialSystemPanel = view.get_node("SocialSystemPanel") as SocialSystemPanel
	_expect_true(not social_button.disabled, "有玩家时社会系统入口可用")
	_expect_true(not panel.visible, "社会系统面板默认关闭")
	social_button.pressed.emit()
	_expect_true(panel.visible, "社会入口可打开组织与人物层级面板")
	var organization_option: OptionButton = panel.get_node("Margin/Root/Scroll/Content/OrganizationOption") as OptionButton
	_expect_equal(organization_option.item_count, 8, "组织面板列出八个正式组织")
	var counts: Label = panel.get_node("Margin/Root/CountsLabel") as Label
	_expect_true(counts.text.contains("背景人物 112") and counts.text.contains("活跃人物 9 / 20"), "社会面板显示人物层级预算")
	var ai_section: VBoxContainer = panel.get_node("Margin/Root/Scroll/Content/AiSection") as VBoxContainer
	_expect_true(not ai_section.visible, "AI 调试信息默认隐藏")
	GameSessionService.developer_mode = true
	panel.refresh_developer_mode()
	var developer_toggle: CheckButton = panel.get_node("Margin/Root/Scroll/Content/DeveloperToggle") as CheckButton
	developer_toggle.button_pressed = true
	_expect_true(ai_section.visible, "开发者开关显示活跃 AI 调试视图")
	var ai_label: RichTextLabel = panel.get_node("Margin/Root/Scroll/Content/AiSection/AiLabel") as RichTextLabel
	_expect_true(ai_label.text.contains("候选权重") and ai_label.text.contains("下次每日决策"), "AI 调试视图包含目标、候选和下次决策")
	var relationship_button: Button = panel.get_node("Margin/Root/Scroll/Content/RelationshipButton") as Button
	relationship_button.pressed.emit()
	_expect_equal(GameSessionService.society_service.relationships.size(), 1, "社会面板按实际操作创建关系")
	view.queue_free()
	GameSessionService.clear()


func _test_m6_society_performance_baseline() -> void:
	var started_at_usec: int = Time.get_ticks_usec()
	var society: SocietySimulationService = _make_society(650)
	var initialization_usec: int = Time.get_ticks_usec() - started_at_usec
	started_at_usec = Time.get_ticks_usec()
	for day_index: int in range(1, 31):
		var hour_value: int = day_index * 24
		society.ai.run_daily_decisions(hour_value)
		if hour_value % 720 == 0:
			society.ai.run_long_term_evaluations(hour_value)
	var relationship_targets: Array[String] = society.roster.get_background_ids()
	for index: int in range(100):
		society.create_player_relationship(relationship_targets[index], index * 24)
	var simulation_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_equal(society.relationships.size(), 100, "100 次实际接触只保存 100 条稀疏关系")
	_expect_true(society.ai.states.size() <= 19, "30 日模拟始终只处理活跃 NPC")
	_expect_true(initialization_usec < 250000, "120 人社会初始化低于 250 ms 预算")
	print("[PERF] 初始化 120 人分层社会与 8 组织：%.3f ms" % (float(initialization_usec) / 1000.0))
	print("[PERF] 19 人以内 AI 运行 30 日并创建 100 条关系：%.3f ms" % (float(simulation_usec) / 1000.0))


func _test_m7_continuity_rules() -> void:
	_continuity_rules = ContinuityRulesConfig.new()
	_expect_equal(_continuity_rules.load_from_file(), OK, "M7 连续性规则可加载")
	_expect_equal(
		_continuity_rules.get_exit_reason_ids(),
		["death", "disgrace", "long_imprisonment", "retirement", "voluntary"],
		"死亡、失势、长期监禁、退休和自愿退出五类原因完整"
	)
	for reason_id: String in _continuity_rules.get_exit_reason_ids():
		var reason: Dictionary = _continuity_rules.exit_reasons[reason_id] as Dictionary
		_expect_true(float(reason["wealth_ratio"]) < 1.0, "退出原因不完整复制财富：%s" % reason_id)
		_expect_true(float(reason["reputation_ratio"]) < 1.0, "退出原因不完整复制声望：%s" % reason_id)


func _test_m7_social_and_military_influence_separation() -> void:
	var map_service: MapControlService = _create_map_service()
	var influence := RegionalInfluenceService.new(_continuity_rules)
	var unit: ControlUnitData = map_service.get_unit("control:r3_c4")
	var region: RegionData = map_service.data_set.regions[unit.region_id] as RegionData
	var social_before: float = float(region.social_influence["country:loran_federation"])
	var controller_before: String = unit.controller_country_id
	var strength_before: float = unit.control_strength
	var contested_before: float = unit.contested_level
	var frontlines_before: Array[Dictionary] = map_service.get_frontline_edges()
	_expect_true(influence.apply_policy_action(unit.id, "country:loran_federation", map_service), "政策行动可提高地区社会影响")
	_expect_true(float(region.social_influence["country:loran_federation"]) > social_before, "人物政策行动改变目标国家社会影响")
	_expect_approx(_dictionary_float_total(region.social_influence), 1.0, 0.000001, "地区社会影响变动后保持归一化")
	_expect_equal(unit.controller_country_id, controller_before, "社会影响变化不改变军事控制者")
	_expect_approx(unit.control_strength, strength_before, 0.000001, "社会影响变化不改变控制强度")
	_expect_approx(unit.contested_level, contested_before, 0.000001, "社会影响变化不改变争夺度")
	_expect_equal(map_service.get_frontline_edges(), frontlines_before, "社会影响变化不移动前线")


func _test_m7_organization_support_channels() -> void:
	var society: SocietySimulationService = _make_society(710)
	var map_service: MapControlService = _create_map_service()
	var player: CharacterData = society.roster.get_active(society.roster.player_character_id)
	var government_id: String = "organization:loran_government"
	var government: OrganizationData = society.organizations.get_organization(government_id)
	society.organizations.join_organization(player, government_id)
	society.organizations.assign_position(player, government_id, "regional_official")
	var region: RegionData = map_service.data_set.regions["region:loran_riverback"] as RegionData
	var influence_before: float = float(region.social_influence[player.country_id])
	var government_resources: float = government.resources
	_expect_true(society.regional_influence.apply_organization_social_support(government, player.id, region.id, 1.0, society.organizations, map_service), "有政策权限的组织可投入地区社会活动")
	_expect_true(float(region.social_influence[player.country_id]) > influence_before, "组织社会活动提高本国地区影响")
	_expect_true(government.resources < government_resources, "组织社会活动消耗组织资源")
	_expect_true(not society.regional_influence.apply_organization_control_support(government, player.id, "control:r3_c5", 1.0, society.organizations, map_service), "没有军事控制权限时组织不能扩大控制")

	var military_id: String = "organization:loran_military"
	var military: OrganizationData = society.organizations.get_organization(military_id)
	society.organizations.join_organization(player, military_id)
	society.organizations.assign_position(player, military_id, "officer")
	var target: ControlUnitData = map_service.get_unit("control:r3_c5")
	var target_region: RegionData = map_service.data_set.regions[target.region_id] as RegionData
	var target_social: Dictionary = target_region.social_influence.duplicate(true)
	var military_resources: float = military.resources
	var consolidation_target: ControlUnitData
	for unit_id: String in map_service.get_sorted_unit_ids():
		var candidate: ControlUnitData = map_service.get_unit(unit_id)
		if (
			candidate != null
			and candidate.controller_country_id == player.country_id
			and map_service.is_valid_control_support_target(unit_id, player.country_id)
		):
			consolidation_target = candidate
			break
	_expect_true(consolidation_target != null, "军事组织存在应优先巩固的己方前线单元")
	var consolidation_strength: float = (
		consolidation_target.control_strength if consolidation_target != null else 0.0
	)
	_expect_true(society.regional_influence.apply_organization_control_support(military, player.id, target.id, 1.0, society.organizations, map_service), "有控制权限的军事组织可投入地区控制")
	_expect_true(
		consolidation_target != null
		and consolidation_target.control_strength > consolidation_strength,
		"组织军事支援优先巩固脆弱己方前线"
	)
	_expect_equal(target_region.social_influence, target_social, "组织军事支援不暗改社会影响")
	_expect_true(military.resources < military_resources, "组织军事支援消耗组织资源")


func _test_m7_action_domain_effect() -> void:
	var society: SocietySimulationService = _make_society(720)
	var map_service: MapControlService = _create_map_service()
	var player: CharacterData = society.roster.get_active(society.roster.player_character_id)
	for raw_skill: Variant in player.skills:
		player.skills[raw_skill] = 100
	GameSessionService.set_player(player)
	GameSessionService.society_service = society
	var definition: ActionDefinitionData = map_service.data_set.actions["action:promote_policy"] as ActionDefinitionData
	var context: Dictionary = _action_context(definition, 100.0)
	context["target_id"] = "control:r3_c4"
	var service: ActionService = _make_action_service()
	var action: ActionInstanceData = service.start_action(definition, player, 0, context).action
	service.update_to_hour(action, definition, player, 2000, map_service)
	var unit: ControlUnitData = map_service.get_unit(action.target_id)
	var region: RegionData = map_service.data_set.regions[unit.region_id] as RegionData
	var social_before: float = float(region.social_influence[player.country_id])
	var strength_before: float = unit.control_strength
	_expect_true(society.apply_action_domain_effect(action, definition, map_service), "完成的政策行动连接地区社会影响服务")
	_expect_true(float(region.social_influence[player.country_id]) > social_before, "政策行动结果实际应用社会影响")
	_expect_approx(unit.control_strength, strength_before, 0.000001, "政策行动结果不改变军事强度")
	_expect_true(not society.apply_action_domain_effect(action, definition, map_service), "行动领域效果只应用一次")
	GameSessionService.clear()


func _test_m7_candidate_sources_and_order() -> void:
	var society: SocietySimulationService = _make_society(730)
	var player: CharacterData = society.roster.get_active(society.roster.player_character_id)
	var own_ids: Array[String] = society.roster.get_background_ids(player.country_id)
	var foreign_country: String = "country:vesta_union" if player.country_id == "country:loran_federation" else "country:loran_federation"
	var foreign_id: String = society.roster.get_background_ids(foreign_country)[0]
	var ally_id: String = own_ids[0]
	var weak_id: String = own_ids[1]
	var detained_id: String = own_ids[2]
	_set_relationship_values(society.relationships.create_or_update(player.id, ally_id, 10), 1.0, 0.9, 0.8)
	_set_relationship_values(society.relationships.create_or_update(player.id, weak_id, 10), 0.1, 0.0, 0.0)
	_set_relationship_values(society.relationships.create_or_update(player.id, foreign_id, 10), 1.0, 1.0, 1.0)
	_set_relationship_values(society.relationships.create_or_update(player.id, detained_id, 10), 1.0, 1.0, 1.0)
	society.roster.get_background(detained_id).current_status["detained"] = true

	var organization_id: String = "organization:loran_union"
	if player.country_id == "country:vesta_union":
		organization_id = "organization:vesta_union"
	var organization: OrganizationData = society.organizations.get_organization(organization_id)
	society.organizations.join_organization(player, organization_id)
	var leader: CharacterData = society.roster.get_active(organization.leader_character_id)
	leader.current_status["reputation"] = 100
	var candidates: Array[SuccessionCandidateData] = society.succession.get_candidates(player.id)
	var candidate_ids: Array[String] = []
	for candidate: SuccessionCandidateData in candidates:
		candidate_ids.append(candidate.character_id)
	_expect_true(candidate_ids.has(ally_id), "真实高强度关系进入继承候选")
	_expect_true(candidate_ids.has(leader.id), "共同组织成员可进入继承候选")
	_expect_true(not candidate_ids.has(weak_id), "低于最低评分的弱联系不进入候选")
	_expect_true(not candidate_ids.has(foreign_id), "外国人物不进入当前人物继承候选")
	_expect_true(not candidate_ids.has(detained_id), "被拘押人物不进入继承候选")
	_expect_equal(candidates[0].character_id, ally_id, "候选按可解释关系分数降序排列")
	var repeated: Array[SuccessionCandidateData] = society.succession.get_candidates(player.id)
	_expect_equal(_candidate_dicts(candidates), _candidate_dicts(repeated), "相同关系与组织状态产生稳定候选顺序")


func _test_m7_exit_reasons() -> void:
	for reason_id: String in _continuity_rules.get_exit_reason_ids():
		var society: SocietySimulationService = _make_society(740 + reason_id.length())
		var old_player: CharacterData = society.roster.get_active(society.roster.player_character_id)
		old_player.current_status["wealth"] = 100
		old_player.current_status["reputation"] = 80
		match reason_id:
			"death":
				old_player.current_status["health"] = 0
			"retirement":
				old_player.age = int(_society_rules.lifecycle_rules["retirement_age"])
			"long_imprisonment":
				old_player.current_status["detained"] = true
			"disgrace":
				old_player.current_status["reputation"] = int(
					_continuity_rules.exit_constraints["disgrace_reputation_threshold"]
				)
		var successor_id: String = society.roster.get_background_ids(old_player.country_id)[0]
		_set_relationship_values(society.relationships.create_or_update(old_player.id, successor_id, 1), 1.0, 1.0, 1.0)
		GameSessionService.set_player(old_player)
		GameSessionService.society_service = society
		var result: SuccessionResult = society.execute_player_succession(successor_id, reason_id, 100)
		_expect_true(result.is_success(), "退出原因可完成继承：%s" % reason_id)
		_expect_equal(result.exited_record.reason, reason_id, "已退出记录保存原因：%s" % reason_id)
		_expect_equal(result.inherited_wealth, floori(100.0 * float((_continuity_rules.exit_reasons[reason_id] as Dictionary)["wealth_ratio"])), "退出原因应用财富比例：%s" % reason_id)
		GameSessionService.clear()


func _test_m7_partial_succession_and_continuity() -> void:
	var society: SocietySimulationService = _make_society(760)
	var map_service: MapControlService = _create_map_service()
	var old_player: CharacterData = society.roster.get_active(society.roster.player_character_id)
	old_player.current_status["wealth"] = 100
	old_player.current_status["reputation"] = 80
	old_player.current_status["intelligence_points"] = 40
	old_player.age = int(_society_rules.lifecycle_rules["retirement_age"])
	for raw_skill: Variant in old_player.skills:
		old_player.skills[raw_skill] = 100
	var ids: Array[String] = society.roster.get_background_ids(old_player.country_id)
	var successor_id: String = ids[0]
	var ally_id: String = ids[1]
	var enemy_id: String = ids[2]
	var successor_background: BackgroundCharacterData = society.roster.get_background(successor_id)
	var successor_initial_wealth: int = int(successor_background.current_status.get("wealth", 0))
	var successor_initial_reputation: int = int(successor_background.current_status.get("reputation", 0))
	var successor_initial_intelligence: int = int(successor_background.current_status.get("intelligence_points", 0))
	_set_relationship_values(society.relationships.create_or_update(old_player.id, successor_id, 10), 1.0, 1.0, 1.0)
	_set_relationship_values(society.relationships.create_or_update(old_player.id, ally_id, 10), 0.8, 0.6, 0.8)
	_set_relationship_values(society.relationships.create_or_update(old_player.id, enemy_id, 10), 0.7, -0.5, -0.8)
	var organization_id: String = "organization:loran_government"
	society.organizations.join_organization(old_player, organization_id)
	society.organizations.assign_position(old_player, organization_id, "regional_official")
	GameSessionService.set_player(old_player)
	GameSessionService.society_service = society
	var pending := ActionInstanceData.new()
	pending.status = ActionInstanceData.STATUS_ACTIVE
	GameSessionService.current_action = pending
	var society_reference: SocietySimulationService = society
	var organization_reference: OrganizationService = society.organizations
	var map_controller_before: String = map_service.get_unit("control:r3_c4").controller_country_id
	var result: SuccessionResult = society.execute_player_succession(successor_id, "retirement", 200)
	_expect_true(result.is_success(), "退休后可由真实关系候选继承")
	var successor: CharacterData = result.successor
	_expect_equal(GameSessionService.player_character.id, successor_id, "游戏会话切换到所选稳定人物 ID")
	_expect_true(GameSessionService.society_service == society_reference and society.organizations == organization_reference, "继承不重建社会世界和组织服务")
	_expect_equal(map_service.get_unit("control:r3_c4").controller_country_id, map_controller_before, "继承不重建或改变地图控制状态")
	_expect_true(GameSessionService.current_action == null, "前人物未完成行动在继承时清除")
	_expect_true(society.roster.get_active(old_player.id) == null, "前人物离开活跃层")
	_expect_true(society.roster.get_exited(old_player.id) != null, "前人物保留在已退出历史索引")
	_expect_equal(result.exited_record.successor_character_id, successor_id, "退出记录保存继承者稳定 ID")
	_expect_equal(society.roster.get_total_character_count(), 121, "继承不新增或删除世界人物身份")
	_expect_equal(result.inherited_wealth, 70, "退休按 70% 转移财富")
	_expect_equal(int(old_player.current_status["wealth"]), 30, "已转移财富从前人物扣除")
	_expect_equal(int(successor.current_status["wealth"]), successor_initial_wealth + 70, "继承者获得部分财富")
	_expect_equal(result.inherited_reputation, 48, "退休按 60% 传递声望")
	_expect_equal(int(successor.current_status["reputation"]), successor_initial_reputation + 48, "继承者声望在自身基础上增加而非替换")
	_expect_equal(result.inherited_intelligence, 20, "退休按 50% 传递已积累情报")
	_expect_equal(int(successor.current_status["intelligence_points"]), successor_initial_intelligence + 20, "继承者获得部分情报而非完整复制")
	_expect_true(int(successor.skills["administration"]) < 100, "继承者不复制前人物完整技能")
	_expect_equal(result.inherited_position_count, 1, "高关系退休安排继承原职位")
	_expect_equal(society.organizations.get_position_id(successor.id, organization_id), "regional_official", "继承职位保持组织槽位一致")
	_expect_equal(result.inherited_relationship_count, 2, "盟友和敌对关系均可部分保留")
	_expect_equal(result.inherited_enemy_count, 1, "敌对关系单独记录保留数量")
	var inherited_ally: RelationshipData = society.relationships.get_between(successor.id, ally_id)
	var inherited_enemy: RelationshipData = society.relationships.get_between(successor.id, enemy_id)
	_expect_approx(inherited_ally.affinity, 0.44, 0.000001, "退休盟友关系按 55% 继承")
	_expect_approx(inherited_enemy.affinity, -0.28, 0.000001, "退休敌对关系按 35% 保留")
	_expect_true(society.ai.get_state(successor.id) == null, "继承者成为玩家后不再由 AI 控制")
	GameSessionService.clear()


func _test_m7_succession_panel_scene() -> void:
	var player: CharacterData = _make_action_character(60, 770)
	GameSessionService.set_player(player)
	var scene_resource: Resource = load("res://scenes/map/strategic_map_view.tscn")
	var view: Node = (scene_resource as PackedScene).instantiate()
	get_root().add_child(view)
	var society: SocietySimulationService = GameSessionService.society_service
	var target_id: String = society.roster.get_background_ids(player.country_id)[0]
	_set_relationship_values(society.relationships.create_or_update(player.id, target_id, 0), 1.0, 1.0, 1.0)
	var panel: SocialSystemPanel = view.get_node("SocialSystemPanel") as SocialSystemPanel
	var prepare_button: Button = panel.get_node("Margin/Root/Scroll/Content/PrepareSuccessionButton") as Button
	prepare_button.pressed.emit()
	var succession_option: OptionButton = panel.get_node("Margin/Root/Scroll/Content/SuccessionOption") as OptionButton
	var confirm_button: Button = panel.get_node("Margin/Root/Scroll/Content/ConfirmSuccessionButton") as Button
	_expect_true(succession_option.item_count > 0 and not confirm_button.disabled, "继承面板从真实关系生成可选候选")
	for index: int in range(succession_option.item_count):
		if str(succession_option.get_item_metadata(index)) == target_id:
			succession_option.select(index)
			break
	confirm_button.pressed.emit()
	_expect_equal(GameSessionService.player_character.id, target_id, "继承面板可切换当前玩家人物")
	_expect_equal(society.roster.exited_characters.size(), 1, "继承面板创建一条退出历史记录")
	var counts: Label = panel.get_node("Margin/Root/CountsLabel") as Label
	_expect_true(counts.text.contains("已退出 1"), "社会面板显示已退出人物数量")
	view.queue_free()
	GameSessionService.clear()


func _test_m7_succession_performance_baseline() -> void:
	var society: SocietySimulationService = _make_society(780)
	var player: CharacterData = society.roster.get_active(society.roster.player_character_id)
	var targets: Array[String] = society.roster.get_background_ids()
	for index: int in range(100):
		var relationship: RelationshipData = society.relationships.create_or_update(player.id, targets[index], index)
		_set_relationship_values(relationship, 0.6, 0.4, 0.2)
	var started_at_usec: int = Time.get_ticks_usec()
	var candidates: Array[SuccessionCandidateData] = society.succession.get_candidates(player.id)
	var candidate_elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(not candidates.is_empty(), "100 条稀疏关系可生成继承候选")
	GameSessionService.set_player(player)
	GameSessionService.society_service = society
	started_at_usec = Time.get_ticks_usec()
	var result: SuccessionResult = society.execute_player_succession(candidates[0].character_id, "voluntary", 1000)
	var succession_elapsed_usec: int = Time.get_ticks_usec() - started_at_usec
	_expect_true(result.is_success(), "目标规模关系网络可完成继承")
	_expect_true(candidate_elapsed_usec < 100000 and succession_elapsed_usec < 100000, "候选生成和继承均低于 100 ms 主线程预算")
	print("[PERF] 从 100 条稀疏关系生成继承候选：%.3f ms" % (float(candidate_elapsed_usec) / 1000.0))
	print("[PERF] 应用部分资源、职位与关系继承：%.3f ms" % (float(succession_elapsed_usec) / 1000.0))
	GameSessionService.clear()


func _test_m8_clock_and_queue_roundtrip() -> void:
	var clock: SimulationClock = _create_clock()
	clock.set_speed(4)
	clock.set_paused(false)
	clock.advance_real_seconds(0.35)
	clock.advance_hours(49)
	clock.schedule_event_in_hours("event:m8_alpha", 4, {"value": 7})
	clock.schedule_event_in_hours("event:m8_beta", 4, {"value": 8})
	var saved: Dictionary = clock.get_persistent_state()
	var restored: SimulationClock = _create_clock()
	_expect_true(restored.restore_persistent_state(saved), "M8 时钟与事件队列状态可恢复")
	_expect_equal(restored.get_persistent_state(), saved, "M8 时钟往返保持完整权威状态")
	var due_ids: Array[String] = []
	restored.scheduled_event_due.connect(func(event_id: String, _due: int, _payload: Dictionary) -> void: due_ids.append(event_id))
	restored.advance_hours(4)
	_expect_equal(due_ids, ["event:m8_alpha", "event:m8_beta"], "M8 恢复后同小时事件顺序保持稳定")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["month"] = 13
	_expect_true(not restored.restore_persistent_state(invalid), "M8 时钟拒绝非法日期")


func _test_m8_save_load_roundtrip() -> void:
	var map_service: MapControlService = _create_map_service()
	var clock: SimulationClock = _create_clock()
	var player: CharacterData = _make_action_character(64, 880001)
	GameSessionService.set_player(player)
	var society := SocietySimulationService.new()
	_expect_true(society.initialize(player, map_service.data_set), "M8 往返样本社会可初始化")
	GameSessionService.society_service = society
	society.attach_clock(clock)
	clock.set_speed(8)
	clock.set_paused(false)
	clock.advance_hours(193)
	clock.schedule_event_in_hours("event:m8_pending", 12, {"kind": "test"})
	map_service.set_control_state("control:r3_c4", "country:vesta_union", 0.37, 0.71)
	(map_service.data_set.regions["region:loran_southridge"] as RegionData).social_influence = {
		"country:loran_federation": 0.41, "country:vesta_union": 0.59,
	}
	var other_id: String = society.roster.get_background_ids(player.country_id)[0]
	society.create_player_relationship(other_id, clock.total_hours)
	var exiting_id: String = society.roster.get_background_ids(player.country_id)[1]
	var exiting_character: CharacterData = society.promote_background(exiting_id)
	society.ai.unregister(exiting_id)
	society.roster.exit_active_character(exiting_id, "voluntary", clock.total_hours)
	var action_definition: ActionDefinitionData = map_service.data_set.actions[
		"action:study_skill"
	] as ActionDefinitionData
	var action_service := ActionService.new(
		_action_rules, GameSessionService.action_id_service
	)
	var context_service := PlayerActionContextService.new(
		_action_rules, society, map_service
	)
	var action_result: ActionStartResult = context_service.start_player_action(
		action_service,
		action_definition,
		player,
		180,
		"",
		0,
		action_definition.primary_skill
	)
	_expect_true(action_result.is_success(), "M8 通过权威入口创建进行中行动夹具")
	if not action_result.is_success():
		GameSessionService.clear()
		return
	var current_action: ActionInstanceData = action_result.action
	action_service.update_to_hour(
		current_action, action_definition, player, 193, map_service
	)
	var expected_action_work: float = current_action.accumulated_work
	GameSessionService.current_action = current_action
	var next_action_sequence: int = int(
		GameSessionService.action_id_service.get_state().get("action_instance", 0)
	) + 1
	var expected_next_action_id: String = "action_instance:%08d" % next_action_sequence
	GameSessionService.developer_mode = true
	society.set_settlement_paused("daily_ai", true)
	GameSessionService.settlement_log.add("test", "roundtrip", clock.total_hours)
	GameSessionService.performance_stats.record("simulation_test", 1250)
	var expected_wealth: int = int(player.current_status["wealth"])
	var service := GameSaveService.new()
	var snapshot: Dictionary = service.build_snapshot(clock, map_service)
	_expect_equal(int(snapshot["save_version"]), 1, "M8 存档版本固定为 1")
	_expect_equal((snapshot["characters"] as Dictionary)["background"].size() + (snapshot["characters"] as Dictionary)["active"].size(), 120, "M8 存档包含完整在世人物状态")
	_expect_equal((snapshot["characters"] as Dictionary)["exited"].size(), 1, "M8 存档包含退出人物历史")
	_expect_equal((snapshot["world"] as Dictionary)["control_units"].size(), 80, "M8 存档包含全部控制单元")
	var path: String = "user://tests/m8_roundtrip.json"
	var saved_result: SaveOperationResult = service.save_to_path(path, snapshot)
	_expect_true(saved_result.success, "M8 手动 JSON 存档可安全写入")
	var file_size: int = FileAccess.get_file_as_bytes(path).size()
	_expect_true(file_size > 1000, "M8 存档文件包含实际世界状态")
	clock.advance_hours(30)
	map_service.set_control_state("control:r3_c4", "country:loran_federation", 1.0, 0.0)
	player.current_status["wealth"] = 0
	GameSessionService.developer_mode = false
	var loaded: SaveOperationResult = service.load_from_path(path)
	_expect_true(loaded.success, "M8 已写入存档可解析并通过验证")
	var restored: SaveOperationResult = service.restore_snapshot(loaded.snapshot, clock, map_service)
	_expect_true(restored.success, "M8 存档可恢复到运行服务")
	_expect_equal(clock.total_hours, 193, "M8 加载恢复权威游戏时间")
	_expect_equal(map_service.get_unit("control:r3_c4").controller_country_id, "country:vesta_union", "M8 加载恢复军事控制")
	_expect_approx(map_service.get_unit("control:r3_c4").contested_level, 0.71, 0.0001, "M8 加载恢复争夺度")
	_expect_approx(float((map_service.data_set.regions["region:loran_southridge"] as RegionData).social_influence["country:vesta_union"]), 0.59, 0.0001, "M8 加载恢复独立社会影响")
	_expect_equal(GameSessionService.player_character.current_status["wealth"], expected_wealth, "M8 加载恢复玩家人物状态")
	_expect_true(GameSessionService.developer_mode, "M8 加载恢复开发模式标记")
	_expect_equal(GameSessionService.action_id_service.next_id("action_instance"), expected_next_action_id, "M8 加载后稳定行动 ID 连续")
	_expect_equal(GameSessionService.society_service.relationships.size(), 1, "M8 加载恢复稀疏关系")
	_expect_equal(GameSessionService.society_service.roster.exited_characters.size(), 1, "M8 加载恢复退出人物历史")
	_expect_true(GameSessionService.current_action != null, "M8 加载恢复进行中行动")
	if GameSessionService.current_action != null:
		_expect_approx(GameSessionService.current_action.accumulated_work, expected_action_work, 0.0001, "M8 加载恢复进行中行动进度")
	_expect_true(GameSessionService.society_service.paused_settlement_categories.has("daily_ai"), "M8 加载恢复暂停结算类别")
	_expect_equal(GameSessionService.society_service.roster.get_total_character_count(), 121, "M8 加载保持人物身份总数")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameSessionService.clear()
	print("[PERF] M8 完整存档文件：%.1f KiB" % (float(file_size) / 1024.0))


func _test_m8_invalid_save_and_safe_replace() -> void:
	var map_service: MapControlService = _create_map_service()
	var clock: SimulationClock = _create_clock()
	var player: CharacterData = _make_action_character(50, 880002)
	GameSessionService.set_player(player)
	var society := SocietySimulationService.new()
	society.initialize(player, map_service.data_set)
	GameSessionService.society_service = society
	var service := GameSaveService.new()
	var path: String = "user://tests/m8_safe_replace.json"
	var valid: Dictionary = service.build_snapshot(clock, map_service)
	_expect_true(service.save_to_path(path, valid).success, "M8 安全替换基准存档可写入")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var invalid: Dictionary = valid.duplicate(true)
	invalid["save_version"] = 999
	var rejected: SaveOperationResult = service.save_to_path(path, invalid)
	_expect_true(not rejected.success and rejected.error_code == "invalid_snapshot", "M8 拒绝未来或未知存档版本")
	_expect_true(FileAccess.get_file_as_bytes(path) == original_bytes, "M8 写入失败不破坏已有存档")
	_expect_true(not service.save_to_path("res://forbidden.json", valid).success, "M8 拒绝写入项目与用户存档区外路径")
	var optional_defaults: Dictionary = valid.duplicate(true)
	optional_defaults.erase("developer_mode")
	optional_defaults.erase("settlement_state")
	optional_defaults.erase("settlement_log")
	optional_defaults.erase("performance_metrics")
	_expect_true(service.validate_snapshot(optional_defaults).is_empty(), "M8 新增诊断字段缺失时使用明确默认值")
	var broken_reference: Dictionary = valid.duplicate(true)
	broken_reference["player_character_id"] = "character:missing"
	var broken_result: SaveOperationResult = service.restore_snapshot(broken_reference, clock, map_service)
	_expect_true(not broken_result.success and broken_result.error_code == "invalid_snapshot", "M8 顶层与名册玩家引用不一致时在结构校验阶段拒绝")
	var malformed_path: String = "user://tests/m8_malformed.json"
	var malformed := FileAccess.open(malformed_path, FileAccess.WRITE)
	malformed.store_string("{broken")
	malformed.close()
	var malformed_result: SaveOperationResult = service.load_from_path(malformed_path)
	_expect_true(not malformed_result.success and malformed_result.error_code == "malformed_json", "M8 畸形 JSON 返回可读错误且不崩溃")
	_expect_equal(clock.total_hours, 0, "M8 无效存档不修改现有游戏时间")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
	GameSessionService.clear()


func _test_m8_autosave_log_and_performance() -> void:
	var log_service := SettlementLogService.new(3)
	for index: int in range(5):
		log_service.add("daily", "entry_%d" % index, index)
	_expect_equal(log_service.get_entries().size(), 3, "M8 结算日志按配置保持有界")
	_expect_equal(log_service.get_entries()[0]["message"], "entry_2", "M8 结算日志丢弃最旧条目")
	var performance := PerformanceStatsService.new()
	performance.record("save", 100)
	performance.record("save", 250)
	_expect_equal(performance.get_snapshot()["save"]["count"], 2, "M8 性能统计累计调用次数")
	_expect_equal(performance.get_snapshot()["save"]["max_usec"], 250, "M8 性能统计保留最大耗时")
	var map_service: MapControlService = _create_map_service()
	var clock: SimulationClock = _create_clock()
	var player: CharacterData = _make_action_character(50, 880003)
	GameSessionService.set_player(player)
	var society := SocietySimulationService.new()
	society.initialize(player, map_service.data_set)
	GameSessionService.society_service = society
	var autosave_path: String = "user://tests/m8_autosave.json"
	var autosave := AutosaveCoordinator.new(autosave_path)
	_expect_true(autosave.attach(clock, map_service), "M8 自动存档协调器可接入权威周事件")
	var result: SaveOperationResult = autosave.run_now()
	_expect_true(result.success and FileAccess.file_exists(autosave_path), "M8 单一自动存档槽可写入")
	_expect_true(GameSessionService.performance_stats.get_snapshot().has("save"), "M8 存档耗时进入性能统计")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(autosave_path))
	GameSessionService.clear()


func _test_m8_developer_tools_and_panel() -> void:
	var map_service: MapControlService = _create_map_service()
	var clock: SimulationClock = _create_clock()
	var player: CharacterData = _make_action_character(50, 880004)
	GameSessionService.set_player(player)
	var society := SocietySimulationService.new()
	society.initialize(player, map_service.data_set)
	GameSessionService.society_service = society
	var commands := DeveloperCommandService.new(clock, map_service)
	_expect_true(not commands.set_character_age(player.id, 40), "M8 开发命令默认不能修改权威状态")
	commands.set_enabled(true)
	_expect_true(commands.set_character_age(player.id, 40), "M8 开发模式可调整人物年龄")
	_expect_true(commands.set_character_value(player.id, "wealth", 77), "M8 开发模式可调整人物资源")
	_expect_true(commands.set_character_value(player.id, "administration", 88), "M8 开发模式可调整人物技能")
	_expect_true(commands.set_map_control("control:r3_c4", "country:vesta_union", 0.4, 0.6), "M8 开发模式可调整地图控制")
	_expect_true(commands.step_hours(24), "M8 开发模式可单步一天")
	_expect_true(commands.set_settlement_paused("daily_ai", true), "M8 开发模式可暂停指定结算类别")
	_expect_true(commands.set_true_tendency(player.id, "reform", 66), "M8 开发模式可调整真实倾向")
	_expect_true(commands.force_contested("control:r3_c4"), "M8 开发模式可强制创建争夺区")
	_expect_true(commands.set_game_date(1901, 2, 3, 4), "M8 开发模式可设置权威游戏日期")
	_expect_true(commands.get_hidden_character_state(player.id).has("hidden_aptitudes"), "M8 开发工具可查看隐藏资质与随机状态")
	_expect_true(bool(commands.execute_text_command("inspect %s" % player.id)["success"]), "M8 开发面板命令入口覆盖隐藏信息查看")
	var background_id: String = society.roster.get_background_ids(player.country_id)[0]
	_expect_true(commands.promote_character(background_id), "M8 开发工具可升级人物层级")
	_expect_true(commands.set_relationship(player.id, background_id, 0.8, 0.5), "M8 开发工具可调整人物关系")
	var packed: PackedScene = load("res://scenes/devtools/developer_panel.tscn") as PackedScene
	_expect_true(packed != null, "M8 开发者面板场景可加载")
	var panel: DeveloperPanel = packed.instantiate() as DeveloperPanel
	root.add_child(panel)
	_expect_true(panel != null and not panel.visible, "M8 开发者面板可由宿主默认隐藏")
	panel.queue_free()
	GameSessionService.clear()


func _test_m9_integrated_core_loop() -> void:
	var map_service: MapControlService = _create_map_service()
	var clock: SimulationClock = _create_clock()
	var player: CharacterData = _make_action_character(90, 990001)
	GameSessionService.set_player(player)
	var society := SocietySimulationService.new()
	_expect_true(society.initialize(player, map_service.data_set), "M9 核心闭环社会可初始化")
	GameSessionService.society_service = society
	society.attach_clock(clock)
	var relationship_target_id: String = society.roster.get_background_ids(player.country_id)[0]
	var relationship_action: ActionInstanceData = _completed_domain_action(
		"m9_relationship", "action:build_relationship", player.id, relationship_target_id, 20,
		{"domain_effect": "relationship_contact"}
	)
	_expect_true(society.apply_action_domain_effect(relationship_action, map_service.data_set.actions[relationship_action.definition_id], map_service), "M9 建立关系行动实际创建关系")
	var organization_id: String = "organization:loran_enterprise"
	var join_action: ActionInstanceData = _completed_domain_action(
		"m9_join", "action:join_organization", player.id, organization_id, 40,
		{"domain_effect": "organization_membership"}
	)
	_expect_true(society.apply_action_domain_effect(join_action, map_service.data_set.actions[join_action.definition_id], map_service), "M9 加入组织行动实际登记成员")
	var entry_position: String = society.organizations.get_position_id(player.id, organization_id)
	var position_action: ActionInstanceData = _completed_domain_action(
		"m9_position", "action:seek_position", player.id, organization_id, 80,
		{"domain_effect": "position_award"}
	)
	_expect_true(society.apply_action_domain_effect(position_action, map_service.data_set.actions[position_action.definition_id], map_service), "M9 争取职位行动实际授予更高空缺职位")
	_expect_true(society.organizations.get_position_id(player.id, organization_id) != entry_position, "M9 职位行动改变正式职位索引")
	var action_panel_scene: PackedScene = load("res://scenes/action/action_panel.tscn") as PackedScene
	var action_panel: ActionPanel = action_panel_scene.instantiate() as ActionPanel
	root.add_child(action_panel)
	action_panel.setup(clock, map_service)
	var relationship_index: int = _option_index_for_metadata(action_panel.action_option, "action:build_relationship")
	action_panel.action_option.select(relationship_index)
	action_panel._on_action_selected(relationship_index)
	_expect_true(action_panel.target_option.item_count > 0, "M9 行动面板为关系行动提供人物目标")
	var join_index: int = _option_index_for_metadata(action_panel.action_option, "action:join_organization")
	action_panel.action_option.select(join_index)
	action_panel._on_action_selected(join_index)
	_expect_true(action_panel.target_option.item_count > 0, "M9 行动面板为加入行动提供本国组织目标")
	action_panel.queue_free()
	var government_id: String = "organization:loran_government"
	society.organizations.join_organization(player, government_id)
	society.organizations.assign_position(player, government_id, "regional_official")
	var policy_unit: ControlUnitData = map_service.get_unit("control:r3_c4")
	var region: RegionData = map_service.data_set.regions[policy_unit.region_id] as RegionData
	var influence_before: float = float(region.social_influence[player.country_id])
	var policy_action: ActionInstanceData = _completed_domain_action(
		"m9_policy", "action:promote_policy", player.id, "control:r3_c4", 120,
		{"domain_effect": "regional_policy_support"}
	)
	_expect_true(society.apply_action_domain_effect(policy_action, map_service.data_set.actions[policy_action.definition_id], map_service), "M9 地区政策行动接入社会影响")
	_expect_true(float(region.social_influence[player.country_id]) > influence_before, "M9 玩家可观察地区社会状态变化")
	var relationship: RelationshipData = society.relationships.get_between(player.id, relationship_target_id)
	_set_relationship_values(relationship, 0.9, 0.9, 0.8)
	var candidates: Array[SuccessionCandidateData] = society.succession.get_candidates(player.id)
	_expect_true(not candidates.is_empty(), "M9 核心闭环从真实关系生成继承者")
	player.age = int(_society_rules.lifecycle_rules["retirement_age"])
	var succession: SuccessionResult = society.execute_player_succession(candidates[0].character_id, "retirement", 160)
	_expect_true(succession.is_success(), "M9 人物退出后继承同一世界")
	var save_path: String = "user://tests/m9_core_loop.json"
	var save_service := GameSaveService.new()
	_expect_true(save_service.save_to_path(save_path, save_service.build_snapshot(clock, map_service)).success, "M9 继承后的完整世界可保存")
	clock.advance_hours(48)
	var loaded: SaveOperationResult = save_service.load_from_path(save_path)
	_expect_true(loaded.success and save_service.restore_snapshot(loaded.snapshot, clock, map_service).success, "M9 存档可加载并继续游戏")
	clock.advance_hours(1)
	_expect_equal(clock.total_hours, 1, "M9 加载后权威时间可继续推进")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	GameSessionService.clear()


func _test_m9_thirty_day_and_year_stability() -> void:
	var map_service: MapControlService = _create_map_service()
	var clock: SimulationClock = _create_clock()
	var player: CharacterData = _make_action_character(60, 990002)
	GameSessionService.set_player(player)
	var society := SocietySimulationService.new()
	society.initialize(player, map_service.data_set)
	GameSessionService.society_service = society
	society.attach_clock(clock)
	while society.roster.active_characters.size() < society.rules.active_character_limit:
		var ids: Array[String] = society.roster.get_background_ids()
		if ids.is_empty() or society.promote_background(ids[0]) == null:
			break
	var relationship_ids: Array[String] = society.roster.get_background_ids()
	for index: int in range(mini(100, relationship_ids.size())):
		society.create_player_relationship(relationship_ids[index], 0)
	var autosave_path: String = "user://tests/m9_year_autosave.json"
	var autosave := AutosaveCoordinator.new(autosave_path)
	autosave.attach(clock, map_service)
	clock.set_speed(8)
	clock.set_paused(false)
	var started: int = Time.get_ticks_usec()
	_expect_equal(clock.advance_real_seconds(90.0), 720, "M9 8 倍速度稳定推进 30 个游戏日")
	_expect_equal(clock.total_hours, 720, "M9 30 日权威时间准确")
	_expect_true(society.roster.active_characters.size() <= society.rules.active_character_limit, "M9 30 日模拟保持活跃人物上限")
	_expect_equal(clock.advance_real_seconds(1005.0), 8040, "M9 8 倍速度继续推进至完整一年")
	var elapsed_usec: int = Time.get_ticks_usec() - started
	_expect_equal([clock.year, clock.month, clock.day, clock.hour], [1901, 1, 1, 0], "M9 一年自动模拟到达 1901 年元旦")
	_expect_equal(clock.total_hours, 8760, "M9 一年自动模拟权威小时完整")
	_expect_equal(society.ai.states.size(), society.roster.active_characters.size() - 1, "M9 一年模拟只为活跃 NPC 保持 AI")
	_expect_equal(society.relationships.size(), 100, "M9 一年模拟保持按需稀疏关系规模")
	_expect_true(FileAccess.file_exists(autosave_path), "M9 一年模拟持续更新单一自动档")
	var metrics: Dictionary = GameSessionService.performance_stats.get_snapshot()
	_expect_equal(int((metrics["daily_ai"] as Dictionary)["count"]), 365, "M9 一年执行 365 次每日 AI 结算")
	_expect_equal(int((metrics["monthly_ai"] as Dictionary)["count"]), 12, "M9 一年执行 12 次月度 AI 结算")
	_expect_equal(int((metrics["save"] as Dictionary)["count"]), 52, "M9 一年只在 52 个周边界自动保存")
	for metric_id: String in ["daily_ai", "monthly_ai", "save"]:
		_expect_true(int((metrics[metric_id] as Dictionary)["max_usec"]) < 100000, "M9 %s 单次结算低于 100 ms 预算" % metric_id)
	_expect_true(GameSessionService.settlement_log.entries.size() <= GameSessionService.settlement_log.max_entries, "M9 一年模拟日志保持有界且不逐小时增长")
	_expect_true(elapsed_usec < 10000000, "M9 一年目标规模自动模拟在 10 秒回归预算内")
	var loaded: SaveOperationResult = GameSaveService.new().load_from_path(autosave_path)
	_expect_true(loaded.success and int((loaded.snapshot["game_time"] as Dictionary)["total_hours"]) == 8736, "M9 最终周自动档结构有效且时间正确")
	print("[PERF] M9 20 活跃人物、100 关系、52 次自动档的一年 8 倍模拟：%.3f ms" % (float(elapsed_usec) / 1000.0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(autosave_path))
	GameSessionService.clear()


func _test_m9_desktop_configuration() -> void:
	_expect_equal(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1280, "M9 默认视口宽度为 1280")
	_expect_equal(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720, "M9 默认视口高度为 720")
	var preset_text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect_true(preset_text.contains("platform=\"Windows Desktop\"") and preset_text.contains("binary_format/architecture=\"x86_64\""), "M9 Windows Desktop x86-64 导出预设完整")
	_expect_true(preset_text.contains("platform=\"Linux/BSD\"") and preset_text.contains("name=\"Linux x86-64\""), "M9 提供未声明已验证的 Linux x86-64 预设")
	_expect_true(preset_text.contains("platform=\"macOS\"") and preset_text.contains("name=\"macOS Universal\""), "M9 提供未声明已验证的 macOS Universal 预设")


static func _completed_domain_action(
	id_suffix: String,
	definition_id: String,
	actor_id: String,
	target: String,
	completion_hour: int,
	effects: Dictionary
) -> ActionInstanceData:
	var action := ActionInstanceData.new()
	action.id = "action_instance:%s" % id_suffix
	action.definition_id = definition_id
	action.actor_character_id = actor_id
	action.target_id = target
	action.status = ActionInstanceData.STATUS_COMPLETED
	action.completion_hour = completion_hour
	action.last_update_hour = completion_hour
	action.outcome_code = "success"
	action.applied_effects = effects.duplicate(true)
	action.result_applied = true
	return action


static func _option_index_for_metadata(option: OptionButton, metadata: String) -> int:
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1


static func _dictionary_float_total(values: Dictionary) -> float:
	var total: float = 0.0
	for raw_value: Variant in values.values():
		total += float(raw_value)
	return total


static func _set_relationship_values(
	relationship: RelationshipData,
	familiarity: float,
	trust: float,
	affinity: float
) -> void:
	relationship.familiarity = familiarity
	relationship.trust = trust
	relationship.affinity = affinity


static func _candidate_dicts(
	candidates: Array[SuccessionCandidateData]
) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for candidate: SuccessionCandidateData in candidates:
		output.append(candidate.to_dict())
	return output


func _make_society(seed_value: int) -> SocietySimulationService:
	var player: CharacterData = _make_action_character(55, seed_value)
	var society := SocietySimulationService.new()
	if not society.initialize(player, _world_data):
		return null
	return society


func _make_action_service() -> ActionService:
	return ActionService.new(_action_rules, StableIdService.new())


func _make_action_character(skill_value: int, seed_value: int) -> CharacterData:
	var result: CharacterGenerationResult = _make_character_generator(seed_value).generate_character(
		"country:loran_federation", CharacterGenerator.MODE_STANDARD
	)
	var character: CharacterData = result.character
	for raw_key: Variant in character.skills:
		character.skills[raw_key] = skill_value
	for raw_key: Variant in character.hidden_aptitudes:
		character.hidden_aptitudes[raw_key] = 50
	character.current_status["health"] = 90
	character.current_status["fatigue"] = 0
	character.current_status["stress"] = 0
	character.current_status["detained"] = false
	character.current_status["employment_status"] = "employed"
	return character


func _action_context(definition: ActionDefinitionData, value: float) -> Dictionary:
	var permissions: Array[String] = []
	if not definition.position_permission_required.is_empty():
		permissions.append(definition.position_permission_required)
	return {
		"target_id": "",
		"position_permissions": permissions,
		"organization_support": value,
		"relationship_support": value,
		"funding": value,
		"preparation": value,
		"target_resistance": 0.0,
	}


func _make_character_generator(seed_value: int) -> CharacterGenerator:
	return CharacterGenerator.new(
		_world_data,
		_character_config,
		DeterministicRandomService.new(seed_value),
		StableIdService.new()
	)


func _create_map_service() -> MapControlService:
	var result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	if not result.is_success():
		return null
	if _map_rules == null:
		_map_rules = MapRulesConfig.new()
		if _map_rules.load_from_file() != OK:
			return null
	return MapControlService.new(result.data_set, _map_rules)


func _create_clock() -> SimulationClock:
	return SimulationClock.new(_clock_config)


func _expect_clock_datetime(
	clock: SimulationClock,
	expected_year: int,
	expected_month: int,
	expected_day: int,
	expected_hour: int,
	description: String
) -> void:
	_expect_equal(
		[clock.year, clock.month, clock.day, clock.hour],
		[expected_year, expected_month, expected_day, expected_hour],
		description
	)


func _expect_true(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
		return
	_failures += 1
	printerr("[FAIL] %s" % description)


func _expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	_expect_true(actual == expected, "%s（实际：%s，预期：%s）" % [description, actual, expected])


func _expect_approx(
	actual: float,
	expected: float,
	tolerance: float,
	description: String
) -> void:
	_expect_true(
		absf(actual - expected) <= tolerance,
		"%s（实际：%s，预期：%s）" % [description, actual, expected]
	)


func _finish() -> void:
	if _failures > 0:
		printerr("PROJECT TESTS FAILED: %d/%d checks failed" % [_failures, _checks])
		quit(1)
		return
	print("PROJECT TESTS PASSED: %d checks" % _checks)
	quit(0)
