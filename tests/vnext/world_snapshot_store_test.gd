extends SceneTree

const TEST_PATH: String = "user://vnext_world_snapshot_store_test.json"
const PLAYER_ID: String = "person:store_player"
const START_PLACE_ID: String = "place:store_home"

var checks: int = 0
var failures: int = 0
var store := VNextWorldSnapshotStore.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_files()
	_test_save_load_complete_round_trip()
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
	print("VNext world snapshot store v2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_save_load_complete_round_trip() -> void:
	_cleanup_test_files()
	var source := _runtime_at(137, 123456, "event:disk_round_trip")
	if source == null:
		return
	var expected: Dictionary = source.snapshot()

	var save_result := store.save(source, TEST_PATH)
	_check(save_result.success, "complete v2 save succeeds")
	_equal(save_result.path, TEST_PATH, "save result returns caller path")
	_equal(save_result.snapshot, expected, "save result returns the complete runtime snapshot")
	_check(FileAccess.file_exists(TEST_PATH), "save creates primary file")
	_check(
		not FileAccess.file_exists(TEST_PATH + AtomicJsonFileStore.TEMPORARY_SUFFIX),
		"successful save leaves no temporary file"
	)

	var target := _runtime_at(999, 77)
	if target == null:
		return
	var load_result := store.load(target, TEST_PATH)
	_check(load_result.success, "complete v2 load succeeds")
	_equal(target.snapshot(), expected, "disk round trip restores every composed owner")
	_equal(load_result.snapshot, expected, "load result reports the complete restored snapshot")
	_check(
		target.event_knowledge().has_read_event("event:disk_round_trip"),
		"disk round trip restores event knowledge state"
	)
	_cleanup_test_files()


func _test_second_save_and_backup_fallback() -> void:
	_cleanup_test_files()
	var source := _runtime_at(60, 100, "event:first_save")
	if source == null:
		return
	var first_snapshot: Dictionary = source.snapshot()
	var first_save := store.save(source, TEST_PATH)
	_check(first_save.success, "backup fixture first v2 save succeeds")
	var first_primary_text: String = FileAccess.get_file_as_string(TEST_PATH)

	_check(source.advance_minutes(30), "backup fixture second state can advance")
	_check(source.wallet().credit(50), "backup fixture second state can fund wallet")
	_check(source.record_event("event:second_save"), "backup fixture second state can record event")
	var second_save := store.save(source, TEST_PATH)
	_check(second_save.success, "second complete v2 save succeeds")
	var backup_path: String = TEST_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	_check(FileAccess.file_exists(backup_path), "second save creates backup")
	_equal(
		FileAccess.get_file_as_string(backup_path),
		first_primary_text,
		"backup preserves previous complete primary byte-for-byte"
	)

	_check(_write_text_file(TEST_PATH, "{broken"), "primary can be corrupted for fallback test")
	var backup_before_load: String = FileAccess.get_file_as_string(backup_path)
	var recovered := _runtime_at(500, 1)
	if recovered == null:
		return
	var recovered_result := store.load(recovered, TEST_PATH)
	_check(recovered_result.success, "corrupt primary falls back to backup")
	_equal(recovered.snapshot(), first_snapshot, "backup restores the previous complete snapshot")
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

	var target := _runtime_at(321, 654)
	if target == null:
		return
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
		"schema_id": "vnext_world_runtime_v1",
		"total_minutes": 12,
	}
	_check(
		_write_text_file(TEST_PATH, JSON.stringify(wrong_schema)),
		"wrong-schema fixture is written"
	)

	var target := _runtime_at(47, 654)
	if target == null:
		return
	var before: Dictionary = target.snapshot()
	var result := store.load(target, TEST_PATH)
	_check(not result.success, "v1 runtime schema is rejected by v2 store")
	_equal(target.snapshot(), before, "wrong-schema failure leaves complete runtime unchanged")
	_cleanup_test_files()


func _test_new_runtime_equivalence() -> void:
	_cleanup_test_files()
	var source := _runtime_at(0, 222, "event:fresh_runtime")
	if source == null:
		return
	for minutes: int in [1, 59, 60, 1440]:
		_check(source.advance_minutes(minutes), "equivalence source accepts %d minutes" % minutes)
	var expected: Dictionary = source.snapshot()
	_check(store.save(source, TEST_PATH).success, "equivalence source saves complete state")

	var fresh := VNextWorldRuntime.new()
	var result := store.load(fresh, TEST_PATH)
	_check(result.success, "fresh runtime shell loads saved v2 snapshot")
	_equal(fresh.snapshot(), expected, "fresh runtime is equivalent after complete load")
	_cleanup_test_files()


func _runtime_at(
	minutes: int, balance_minor: int = 0, event_id: String = ""
) -> VNextWorldRuntime:
	var runtime := VNextWorldRuntime.create(PLAYER_ID, START_PLACE_ID)
	_check(runtime != null, "snapshot fixture creates a valid v2 runtime")
	if runtime == null:
		return null
	if minutes > 0:
		_check(runtime.advance_minutes(minutes), "snapshot fixture establishes runtime time")
	if balance_minor > 0:
		_check(runtime.wallet().credit(balance_minor), "snapshot fixture establishes wallet balance")
	if not event_id.is_empty():
		_check(runtime.record_event(event_id), "snapshot fixture records event")
		_check(runtime.reveal_event(event_id), "snapshot fixture reveals event")
		_check(runtime.mark_event_read(event_id), "snapshot fixture reads event")
	return runtime


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
