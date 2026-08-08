extends SceneTree

const TEST_PATH: String = "user://vnext_world_snapshot_store_test.json"

var checks: int = 0
var failures: int = 0
var store := VNextWorldSnapshotStore.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_files()
	_test_save_load_round_trip()
	_test_second_save_and_backup_fallback()
	_test_double_corruption_is_atomic()
	_test_wrong_schema_is_rejected()
	_test_new_runtime_equivalence()
	_cleanup_test_files()
	_check(not FileAccess.file_exists(TEST_PATH), "test primary file is cleaned up")
	_check(
		not FileAccess.file_exists(TEST_PATH + AtomicJsonFileStore.BACKUP_SUFFIX),
		"test backup file is cleaned up"
	)
	_check(
		not FileAccess.file_exists(TEST_PATH + AtomicJsonFileStore.TEMPORARY_SUFFIX),
		"test temporary file is cleaned up"
	)
	print("VNext world snapshot store: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_save_load_round_trip() -> void:
	_cleanup_test_files()
	var source := VNextWorldRuntime.new()
	_check(source.advance_minutes(137), "save source can advance")
	var expected: Dictionary = source.snapshot()

	var save_result := store.save(source, TEST_PATH)
	_check(save_result.success, "save succeeds")
	_equal(save_result.path, TEST_PATH, "save result returns caller path")
	_equal(save_result.snapshot, expected, "save result returns runtime snapshot")
	_check(FileAccess.file_exists(TEST_PATH), "save creates primary file")
	_check(
		not FileAccess.file_exists(TEST_PATH + AtomicJsonFileStore.TEMPORARY_SUFFIX),
		"successful save leaves no temporary file"
	)

	var target := VNextWorldRuntime.new()
	_check(target.advance_minutes(999), "load target can differ before load")
	var load_result := store.load(target, TEST_PATH)
	_check(load_result.success, "load succeeds")
	_equal(target.snapshot(), expected, "snapshot round trip restores complete state")
	_equal(load_result.snapshot, expected, "load result reports restored snapshot")
	_cleanup_test_files()


func _test_second_save_and_backup_fallback() -> void:
	_cleanup_test_files()
	var source := VNextWorldRuntime.new()
	_check(source.advance_minutes(60), "backup fixture first state can advance")
	var first_snapshot: Dictionary = source.snapshot()
	var first_save := store.save(source, TEST_PATH)
	_check(first_save.success, "first backup fixture save succeeds")
	var first_primary_text: String = FileAccess.get_file_as_string(TEST_PATH)

	_check(source.advance_minutes(30), "backup fixture second state can advance")
	var second_save := store.save(source, TEST_PATH)
	_check(second_save.success, "second save succeeds")
	var backup_path: String = TEST_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	_check(FileAccess.file_exists(backup_path), "second save creates backup")
	_equal(
		FileAccess.get_file_as_string(backup_path),
		first_primary_text,
		"backup preserves previous valid primary byte-for-byte"
	)

	_check(_write_text_file(TEST_PATH, "{broken"), "primary can be corrupted for fallback test")
	var backup_before_load: String = FileAccess.get_file_as_string(backup_path)
	var recovered := VNextWorldRuntime.new()
	_check(recovered.advance_minutes(500), "fallback target can differ before load")
	var recovered_result := store.load(recovered, TEST_PATH)
	_check(recovered_result.success, "corrupt primary falls back to backup")
	_equal(recovered.snapshot(), first_snapshot, "backup restores previous valid snapshot")
	_equal(
		FileAccess.get_file_as_string(TEST_PATH),
		"{broken",
		"fallback does not delete or repair corrupt primary"
	)
	_equal(
		FileAccess.get_file_as_string(backup_path),
		backup_before_load,
		"fallback does not overwrite backup"
	)
	_cleanup_test_files()


func _test_double_corruption_is_atomic() -> void:
	_cleanup_test_files()
	var backup_path: String = TEST_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	_check(_write_text_file(TEST_PATH, "{broken"), "double-corrupt primary fixture is written")
	_check(_write_text_file(backup_path, "[]"), "double-corrupt backup fixture is written")

	var target := VNextWorldRuntime.new()
	_check(target.advance_minutes(321), "double-corrupt target has existing state")
	var before: Dictionary = target.snapshot()
	var result := store.load(target, TEST_PATH)
	_check(not result.success, "primary and backup corruption returns failure")
	_equal(result.error_code, "load_error", "double corruption returns load_error")
	_equal(target.snapshot(), before, "failed double-corrupt load leaves runtime unchanged")
	_equal(FileAccess.get_file_as_string(TEST_PATH), "{broken", "failed load preserves corrupt primary")
	_equal(FileAccess.get_file_as_string(backup_path), "[]", "failed load preserves corrupt backup")
	_cleanup_test_files()


func _test_wrong_schema_is_rejected() -> void:
	_cleanup_test_files()
	var wrong_schema := {
		"schema_id": "vnext_world_runtime_v0",
		"total_minutes": 12,
	}
	_check(
		_write_text_file(TEST_PATH, JSON.stringify(wrong_schema)),
		"wrong-schema fixture is written"
	)

	var target := VNextWorldRuntime.new()
	_check(target.advance_minutes(47), "wrong-schema target has existing state")
	var before: Dictionary = target.snapshot()
	var result := store.load(target, TEST_PATH)
	_check(not result.success, "wrong schema is rejected")
	_equal(target.snapshot(), before, "wrong-schema failure leaves runtime unchanged")
	_cleanup_test_files()


func _test_new_runtime_equivalence() -> void:
	_cleanup_test_files()
	var source := VNextWorldRuntime.new()
	for minutes: int in [1, 59, 60, 1440]:
		_check(source.advance_minutes(minutes), "equivalence source accepts %d minutes" % minutes)
	var expected: Dictionary = source.snapshot()
	_check(store.save(source, TEST_PATH).success, "equivalence source saves")

	var fresh := VNextWorldRuntime.new()
	var result := store.load(fresh, TEST_PATH)
	_check(result.success, "fresh runtime loads saved snapshot")
	_equal(fresh.snapshot(), expected, "fresh runtime is equivalent after load")
	_cleanup_test_files()


func _write_text_file(path: String, content: String) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if make_error != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	return true


func _cleanup_test_files() -> void:
	_remove_if_present(TEST_PATH)
	_remove_if_present(TEST_PATH + AtomicJsonFileStore.BACKUP_SUFFIX)
	_remove_if_present(TEST_PATH + AtomicJsonFileStore.TEMPORARY_SUFFIX)


func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
