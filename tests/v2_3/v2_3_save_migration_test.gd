extends SceneTree
## Deterministic, non-destructive V2.2 to V2.3 migration.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source_simulation := V2LifeLoopSimulationPolish.new()
	test.expect(source_simulation.initialize(), "V2.2 迁移源初始化")
	if not source_simulation.initialized:
		test.finish(self, "V2.3 save migration")
		return
	source_simulation.advance_hours(36)
	var source_snapshot: Dictionary = GameSaveService.new().build_v2_2_snapshot(
		source_simulation
	)
	var source_text: String = JSON.stringify(source_snapshot, "", true)
	var migrated: V2LifeLoopResult = V23SaveMigration.new().migrate_snapshot(
		source_snapshot
	)
	test.expect(migrated.success, "有效 V2.2 存档可确定性迁移")
	if not migrated.success:
		push_error(migrated.technical_message)
		test.finish(self, "V2.3 save migration")
		return
	test.equal(
		JSON.stringify(source_snapshot, "", true), source_text,
		"迁移过程不修改源快照"
	)
	var snapshot: Dictionary = migrated.data.get("snapshot", {}) as Dictionary
	test.equal(
		snapshot.get("schema_version"),
		V23LifeLoopSimulation.V2_3_SCHEMA_VERSION,
		"迁移结果使用 V2.3 schema"
	)
	test.equal(
		snapshot.get("current_datetime"), source_snapshot.get("current_datetime"),
		"权威时间原样迁移"
	)
	test.equal(
		(snapshot.get("migration", {}) as Dictionary).get("source_file_modified"),
		false,
		"迁移摘要明确源文件未修改"
	)
	test.equal(
		(snapshot.get("household_state", {}) as Dictionary).get("households"),
		(source_snapshot.get("household_state", {}) as Dictionary).get("households"),
		"家庭现金、库存、欠租与周期状态保持"
	)
	test.equal(
		V23SaveService.new().validate_snapshot(snapshot).size(), 0,
		"迁移结果通过完整 V2.3 存档校验"
	)
	var migrated_schedule: Dictionary = snapshot.get("schedule_state", {}) as Dictionary
	var active_fixed_commutes: int = 0
	var migrated_hour: int = V2DateTime.total_hour_from_iso(
		str(snapshot.get("current_datetime", ""))
	)
	for raw_schedule: Variant in (
		migrated_schedule.get("schedules", {}) as Dictionary
	).values():
		for raw_activity: Variant in raw_schedule as Array:
			var activity: Dictionary = raw_activity as Dictionary
			if (
				str(activity.get("activity_type", ""))
				in ["commute_to_work", "commute_home"]
				and str(activity.get("status", "")) in ["planned", "active"]
				and int(activity.get("start_hour", -1)) >= migrated_hour
			):
				active_fixed_commutes += 1
	test.equal(active_fixed_commutes, 0, "迁移后的未来固定通勤全部替换为正式路线")
	var invalid: Dictionary = source_snapshot.duplicate(true)
	invalid["schema_version"] = "broken"
	test.equal(
		V23SaveMigration.new().migrate_snapshot(invalid).error_code,
		"invalid_v2_2_save",
		"不兼容源存档明确拒绝而非猜测修复"
	)
	test.finish(self, "V2.3 save migration")
