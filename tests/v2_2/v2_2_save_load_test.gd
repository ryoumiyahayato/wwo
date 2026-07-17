extends SceneTree
## Atomic V2.2 save, integrity/version rejection and safe restore.

const TEST_PATH: String = "user://saves/v2_2_test_slot.json"
var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "存档测试模拟可初始化")
	simulation.run_days(3)
	var before: Dictionary = simulation.deterministic_digest()
	var service := GameSaveService.new()
	var saved: SaveOperationResult = service.save_v2_2_review(simulation, TEST_PATH)
	test.expect(saved.success, "V2.2 原子保存成功")
	test.expect(FileAccess.file_exists(TEST_PATH), "正式存档文件存在")
	test.expect(not FileAccess.file_exists(TEST_PATH + ".tmp"), "成功后不残留临时文件")
	var loaded: SaveOperationResult = service.load_v2_2_review(TEST_PATH)
	test.expect(loaded.success, "V2.2 存档可读取并通过完整性校验")
	simulation.run_days(2)
	var restored: SaveOperationResult = service.restore_v2_2_review(loaded.snapshot, simulation)
	test.expect(restored.success, "载入快照可事务式恢复")
	test.equal(simulation.deterministic_digest(), before, "载入恢复当前活动、日程、账本、幂等键和状态")
	var wrong_version: Dictionary = loaded.snapshot.duplicate(true)
	wrong_version["schema_version"] = "v2_1"
	test.expect(not service.restore_v2_2_review(wrong_version, simulation).success, "不兼容版本被明确拒绝")
	test.equal(simulation.deterministic_digest(), before, "版本拒绝不破坏当前运行状态")
	var corrupt: Dictionary = loaded.snapshot.duplicate(true)
	corrupt["integrity"] = {"algorithm": "sha256", "digest": "broken"}
	test.expect(not service.restore_v2_2_review(corrupt, simulation).success, "损坏完整性信息被拒绝")
	test.equal(simulation.deterministic_digest(), before, "损坏存档拒绝后状态不变")
	var absolute: String = ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	if FileAccess.file_exists(absolute + ".bak"):
		DirAccess.remove_absolute(absolute + ".bak")
	test.finish(self, "V2.2 save/load")
