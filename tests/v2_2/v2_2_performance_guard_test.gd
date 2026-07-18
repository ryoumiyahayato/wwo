extends SceneTree
## Bounded hourly work and accepted world-map architecture guard.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "性能守卫模拟可初始化")
	var started_usec: int = Time.get_ticks_usec()
	simulation.run_days(30)
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	test.expect(elapsed_usec < 5_000_000, "Headless 30日生活模拟少于5秒：%dµs" % elapsed_usec)
	test.expect(simulation.maximum_hour_processing_usec < 50_000, "单小时结算峰值少于50ms：%dµs" % simulation.maximum_hour_processing_usec)
	test.expect(simulation.schedule.recent_completed_activities.size() <= 256, "完成活动历史保持有界")
	test.expect(simulation.notifications.notifications.size() <= 160, "通知历史保持有界")
	test.expect(simulation.conditions.causal_events.size() <= 512, "因果历史保持有界")
	var map_source: String = _read_text("res://scripts/world_map/internal/world_map_canvas_impl.gd")
	var life_source: String = _read_text("res://scripts/v2_2/v2_life_loop_simulation.gd")
	test.expect(not life_source.contains("PrototypeV2MapCanvas"), "生活模拟不引用地图画布")
	test.expect(not life_source.contains("queue_redraw"), "逐小时生活结算不触发地图重绘")
	var map_modes: Dictionary = JSON.parse_string(
		_read_text("res://data/world_map/map_modes.json")
	) as Dictionary
	test.equal(
		int((map_modes.get("zoom", {}) as Dictionary).get("maximum", 0)),
		96,
		"地图最大缩放仍为96"
	)
	test.expect(map_source.contains("PrototypeV2SpatialIndex"), "统一空间索引实现仍保留")
	test.expect(map_source.contains("_request_layer_redraw"), "批绘图层增量重绘仍保留")
	var region_data: Variant = JSON.parse_string(_read_text("res://data/world_map/regions.json"))
	var administrative_units: Array = (region_data as Dictionary).get("administrative_units", []) as Array
	var department_count: int = 0
	for raw_unit: Variant in administrative_units:
		if str((raw_unit as Dictionary).get("administrative_level", "")) == "departement":
			department_count += 1
	test.equal(
		int(((region_data as Dictionary).get("coverage", {}) as Dictionary).get(
			"metropolitan_department_count", 0
		)),
		96,
		"法国本土省级覆盖声明仍为96"
	)
	test.equal(department_count, 96, "法国96个省级行政区仍保留")

	for removed_path: String in [
		"res://scenes/menu/main_menu.tscn",
		"res://scenes/character/character_setup_view.tscn",
		"res://scenes/map/strategic_map_view.tscn",
		"res://scenes/prototype_v2/prototype_v2_main.tscn",
		"res://data/prototype_v2/prototype_map_modes.json",
	]:
		test.expect(not FileAccess.file_exists(removed_path), "已删除不合格旧入口：%s" % removed_path)
	test.expect(FileAccess.file_exists("res://scripts/world_map/world_map_canvas.gd"), "正式世界地图画布入口存在")
	test.expect(FileAccess.file_exists("res://data/world_map/map_geometry_cache.json"), "正式世界地图几何缓存存在")

	var retained_schedule_count: int = 0
	for raw_schedule: Variant in simulation.schedule.schedules.values():
		retained_schedule_count += (raw_schedule as Array).size()
	test.expect(retained_schedule_count < 192, "30日后仅保留近期及未来日程")
	var year_simulation := V2LifeLoopSimulation.new()
	test.expect(year_simulation.initialize(), "一年长跑模拟可初始化")
	var year_started_usec: int = Time.get_ticks_usec()
	year_simulation.run_days(365)
	var year_elapsed_usec: int = Time.get_ticks_usec() - year_started_usec
	test.expect(
		year_elapsed_usec < 30_000_000,
		"Headless一年生活模拟少于30秒：%dµs" % year_elapsed_usec
	)
	test.expect(year_simulation.ledger_consistency().success, "一年后账本与现金一致")
	test.expect(
		(year_simulation.get_persistent_state().get("processed_hour_keys", []) as Array).size()
		<= 168,
		"逐小时幂等窗口保持168项上限"
	)
	test.expect(
		year_simulation.households.processed_idempotency_keys.size()
		<= V2HouseholdService.MAX_PROCESSED_KEYS,
		"住户幂等历史保持固定上限"
	)
	test.expect(
		year_simulation.relationships.processed_idempotency_keys.size()
		<= V2RelationshipProgressService.MAX_PROCESSED_KEYS,
		"关系幂等历史保持固定上限"
	)
	test.expect(
		year_simulation.organizations.processed_idempotency_keys.size()
		<= V2OrganizationActivityService.MAX_PROCESSED_KEYS,
		"组织幂等历史保持固定上限"
	)
	test.expect(year_simulation.employment.attendance_records.size() <= 512, "出勤历史保持固定上限")
	test.expect(year_simulation.ledger.transactions.size() <= 512, "两住户账本流水保持固定上限")
	var bounded_ledger := V2LedgerService.new()
	bounded_ledger.configure(256)
	var fake_households: Dictionary = {
		"household:test": {
			"cash_centimes": 1000,
			"income_current_period_centimes": 0,
			"expense_current_period_centimes": 0,
			"recent_transaction_ids": [],
		},
	}
	bounded_ledger.register_household("household:test", 1000)
	for index: int in range(300):
		var post_result: V2LifeLoopResult = bounded_ledger.post(
			fake_households,
			"household:test",
			"person:test",
			1,
			"income",
			"test_income",
			index,
			"test",
			"test:%d" % index,
			"test:%d" % index,
			"边界账本测试"
		)
		if not post_result.success:
			test.expect(false, "第%d笔边界账本流水可写入" % index)
			break
	test.equal(bounded_ledger.transactions.size(), 256, "单住户账本仅保留最近256笔")
	test.equal(
		int((fake_households["household:test"] as Dictionary).get("cash_centimes", -1)),
		1300,
		"裁剪账本不改变权威现金"
	)
	test.expect(bounded_ledger.validate_balances(fake_households).success, "裁剪后账本链仍可验证")
	test.finish(self, "V2.2 performance guard")


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
