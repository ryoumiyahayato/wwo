extends SceneTree
## Atomic V2.2 save, retained backup, integrity/version rejection and safe restore.

const TEST_PATH: String = "user://saves/v2_2_test_slot.json"
var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "存档测试模拟可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.2 save/load")
		return
	simulation.run_days(3)
	var first_state: Dictionary = V2DeterminismAudit.digest(simulation)
	var service := V2ReviewSaveService.new()
	var first_saved: SaveOperationResult = service.save_v2_2_review(simulation, TEST_PATH)
	test.expect(first_saved.success, "V2.2 首次原子保存成功")
	test.expect(FileAccess.file_exists(TEST_PATH), "正式存档文件存在")
	test.expect(not FileAccess.file_exists(TEST_PATH + ".tmp"), "成功后不残留临时文件")

	simulation.run_days(1)
	var second_state: Dictionary = V2DeterminismAudit.digest(simulation)
	var second_saved: SaveOperationResult = service.save_v2_2_review(simulation, TEST_PATH)
	test.expect(second_saved.success, "V2.2 第二次原子保存成功")
	test.expect(FileAccess.file_exists(TEST_PATH + ".bak"), "第二次保存保留上一份有效备份")
	var loaded: SaveOperationResult = service.load_v2_2_review(TEST_PATH)
	test.expect(loaded.success, "主存档可读取并通过完整性校验")
	var restored: SaveOperationResult = service.restore_v2_2_review(loaded.snapshot, simulation)
	test.expect(restored.success, "主存档快照可事务式恢复")
	test.equal(
		V2DeterminismAudit.digest(simulation),
		second_state,
		"主存档恢复全部权威日程、账本、通知和幂等状态"
	)

	var primary_absolute: String = ProjectSettings.globalize_path(TEST_PATH)
	var corrupt_file := FileAccess.open(primary_absolute, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{broken")
		corrupt_file.close()
	var backup_loaded: SaveOperationResult = service.load_v2_2_review(TEST_PATH)
	test.expect(backup_loaded.success, "主存档损坏时自动读取安全备份")
	test.equal(backup_loaded.message, "主存档不可用，已读取安全备份", "备份恢复给出明确提示")
	var backup_restored: SaveOperationResult = service.restore_v2_2_review(
		backup_loaded.snapshot, simulation
	)
	test.expect(backup_restored.success, "安全备份可事务式恢复")
	test.equal(
		V2DeterminismAudit.digest(simulation), first_state,
		"安全备份恢复到上一次完整有效状态"
	)

	var wrong_version: Dictionary = backup_loaded.snapshot.duplicate(true)
	wrong_version["schema_version"] = "v2_1"
	test.expect(not service.restore_v2_2_review(wrong_version, simulation).success, "不兼容版本被明确拒绝")
	test.equal(V2DeterminismAudit.digest(simulation), first_state, "版本拒绝不破坏当前运行状态")
	var corrupt: Dictionary = backup_loaded.snapshot.duplicate(true)
	corrupt["integrity"] = {"algorithm": "sha256", "digest": "broken"}
	test.expect(not service.restore_v2_2_review(corrupt, simulation).success, "损坏完整性信息被拒绝")
	test.equal(V2DeterminismAudit.digest(simulation), first_state, "损坏存档拒绝后状态不变")
	_cleanup()
	test.finish(self, "V2.2 save/load")


func _cleanup() -> void:
	var absolute: String = ProjectSettings.globalize_path(TEST_PATH)
	for path: String in [absolute, absolute + ".bak", absolute + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
