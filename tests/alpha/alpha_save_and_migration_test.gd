extends SceneTree
## Alpha atomic save, rollback and V2.2/V2.3 migration-chain regression.

const TEST_PATH: String = "user://tests/alpha_save_migration_test.json"

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	var service := AlphaSaveService.new()
	var simulation := AlphaSimulationService.new()
	test.expect(simulation.initialize(), "Alpha 存档源可初始化")
	if not simulation.initialized:
		test.finish(self, "Alpha save and migration")
		return
	simulation.advance_hours(30)
	var first: SaveOperationResult = service.save(simulation, TEST_PATH)
	if not first.success:
		push_error("Alpha save debug: %s · %s" % [
			first.error_code, first.message,
		])
		_print_round_trip_difference(
			service.build_snapshot(simulation)
		)
	test.expect(first.success, "Alpha 首次通过临时文件验证后原子保存")
	test.expect(FileAccess.file_exists(TEST_PATH), "Alpha 主存档存在")
	test.expect(
		not FileAccess.file_exists(TEST_PATH + ".tmp"),
		"原子保存不遗留临时文件"
	)
	var first_hour: int = simulation.clock.total_hours
	simulation.advance_hours(24)
	var second: SaveOperationResult = service.save(simulation, TEST_PATH)
	if not second.success:
		push_error("Alpha second save debug: %s · %s" % [
			second.error_code, second.message,
		])
	test.expect(second.success, "Alpha 第二次原子保存成功")
	test.expect(FileAccess.file_exists(TEST_PATH + ".bak"), "覆盖前保留有效备份")
	var primary := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if primary != null:
		primary.store_string("{broken")
		primary.close()
	var fallback: SaveOperationResult = service.load(TEST_PATH)
	test.expect(fallback.success, "主存档损坏后自动读取安全备份")
	var restored := AlphaSimulationService.new()
	test.expect(restored.initialize(), "Alpha 恢复目标可初始化")
	test.expect(
		service.restore(fallback.snapshot, restored).success,
		"校验后事务恢复完整 Alpha 状态"
	)
	test.equal(restored.clock.total_hours, first_hour, "安全备份恢复权威小时")
	test.expect(
		bool(restored.validate_alpha_integrity().get("success", false)),
		"恢复后人物、企业、组织、合同和账本引用闭合"
	)
	var before_rejection: Dictionary = restored.get_alpha_persistent_state()
	var tampered: Dictionary = fallback.snapshot.duplicate(true)
	tampered["integrity"] = {"algorithm": "sha256", "digest": "broken"}
	test.expect(
		not service.restore(tampered, restored).success,
		"篡改摘要的存档被拒绝"
	)
	test.equal(
		restored.get_alpha_persistent_state(),
		before_rejection,
		"拒绝损坏存档不改变当前世界"
	)
	var v2_3_source := V23LifeLoopSimulation.new()
	test.expect(v2_3_source.initialize(), "V2.3 迁移源可初始化")
	v2_3_source.advance_hours(36)
	var v2_3_snapshot: Dictionary = V23SaveService.new().build_snapshot(
		v2_3_source
	)
	var v2_3_text: String = JSON.stringify(v2_3_snapshot, "", true)
	var migrated_v2_3: V2LifeLoopResult = (
		AlphaSaveMigration.new().migrate_v2_3_snapshot(v2_3_snapshot)
	)
	test.expect(migrated_v2_3.success, "V2.3 可迁移到 Alpha Schema")
	test.equal(
		JSON.stringify(v2_3_snapshot, "", true),
		v2_3_text,
		"V2.3 迁移不修改源快照"
	)
	if migrated_v2_3.success:
		var alpha_snapshot: Dictionary = migrated_v2_3.data.get(
			"snapshot", {}
		) as Dictionary
		test.equal(
			alpha_snapshot.get("schema_version"),
			AlphaSimulationService.ALPHA_SCHEMA_VERSION,
			"V2.3 迁移目标是 prototype_0_001_alpha_1"
		)
		test.equal(
			alpha_snapshot.get("current_datetime"),
			v2_3_snapshot.get("current_datetime"),
			"V2.3 权威时间原样迁移"
		)
		test.equal(
			service.validate_snapshot(alpha_snapshot).size(),
			0,
			"V2.3 迁移快照通过 Alpha 完整校验"
		)
	var v2_2_source := V2LifeLoopSimulationPolish.new()
	test.expect(v2_2_source.initialize(), "V2.2 迁移源可初始化")
	v2_2_source.advance_hours(36)
	var v2_2_snapshot: Dictionary = GameSaveService.new().build_v2_2_snapshot(
		v2_2_source
	)
	var migrated_v2_2: V2LifeLoopResult = (
		AlphaSaveMigration.new().migrate_v2_2_snapshot(v2_2_snapshot)
	)
	test.expect(
		migrated_v2_2.success,
		"V2.2 经 v2_3_space_cognition_1 迁移到 Alpha"
	)
	if migrated_v2_2.success:
		var migrated_snapshot: Dictionary = migrated_v2_2.data.get(
			"snapshot", {}
		) as Dictionary
		var migration: Dictionary = migrated_snapshot.get(
			"migration", {}
		) as Dictionary
		test.equal(
			migration.get("migration_chain", []),
			[
				V2LifeLoopSimulation.SCHEMA_VERSION,
				V23LifeLoopSimulation.V2_3_SCHEMA_VERSION,
				AlphaSimulationService.ALPHA_SCHEMA_VERSION,
			],
			"存档保留完整 V2.2→V2.3→Alpha 迁移链"
		)
		test.equal(
			service.validate_snapshot(migrated_snapshot).size(),
			0,
			"V2.2 迁移结果通过 Alpha 校验"
		)
	_cleanup()
	test.finish(self, "Alpha save and migration")


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _print_round_trip_difference(snapshot: Dictionary) -> void:
	var encoded: String = JSON.stringify(snapshot, "\t", false)
	var decoded: Variant = JSON.parse_string(encoded)
	if not decoded is Dictionary:
		push_error("Alpha save round trip did not produce a dictionary")
		return
	var before: Dictionary = snapshot.duplicate(true)
	var after: Dictionary = (decoded as Dictionary).duplicate(true)
	before.erase("integrity")
	after.erase("integrity")
	var before_text: String = JSON.stringify(
		AlphaSaveService._canonical(before), "", true
	)
	var after_text: String = JSON.stringify(
		AlphaSaveService._canonical(after), "", true
	)
	var limit: int = mini(before_text.length(), after_text.length())
	for index: int in range(limit):
		if before_text[index] != after_text[index]:
			push_error("Alpha save first round-trip difference at %d: %s <> %s" % [
				index,
				before_text.substr(maxi(0, index - 80), 160),
				after_text.substr(maxi(0, index - 80), 160),
			])
			return
	push_error("Alpha save round-trip lengths %d <> %d" % [
		before_text.length(), after_text.length(),
	])
