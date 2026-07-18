extends SceneTree
## Atomic save, backup fallback, restore and integrity validation.

const TEST_PATH: String = "user://tests/v2_3_save_load_test.json"

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "存读测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 save load")
		return
	var service := V23SaveService.new()
	var first: SaveOperationResult = service.save(simulation, TEST_PATH)
	test.expect(first.success, "首次 V2.3 存档原子写入")
	var first_time: String = str(first.snapshot.get("current_datetime", ""))
	simulation.advance_hours(2)
	var second: SaveOperationResult = service.save(simulation, TEST_PATH)
	test.expect(second.success, "第二次写入保留上一份有效备份")
	test.expect(FileAccess.file_exists(TEST_PATH + ".bak"), "上一份主存档成为 .bak")
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{corrupt")
	file.close()
	var fallback: SaveOperationResult = service.load(TEST_PATH)
	test.expect(fallback.success, "主存档损坏时读取有效备份")
	test.equal(
		fallback.snapshot.get("current_datetime"), first_time,
		"备份内容是覆盖前的最后有效状态"
	)
	var restored_simulation := V23LifeLoopSimulation.new()
	test.expect(restored_simulation.initialize(), "恢复目标环境初始化")
	var restored: SaveOperationResult = service.restore(
		fallback.snapshot, restored_simulation
	)
	test.expect(restored.success, "校验后恢复 V2.3 全域状态")
	test.equal(
		V2DateTime.iso_from_total_hour(restored_simulation.clock.total_hours),
		first_time,
		"恢复后的权威时钟与备份一致"
	)
	var tampered: Dictionary = fallback.snapshot.duplicate(true)
	tampered["selected_person_id"] = V2LifeLoopSimulation.ALBERT_ID
	test.expect(
		not service.validate_snapshot(tampered).is_empty(),
		"篡改内容因完整性摘要不匹配而拒绝"
	)
	test.expect(
		not FileAccess.file_exists(TEST_PATH + ".tmp"),
		"原子写入不遗留临时文件"
	)
	_cleanup()
	test.finish(self, "V2.3 save load")


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var absolute: String = ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(TEST_PATH + suffix):
			DirAccess.remove_absolute(absolute)
