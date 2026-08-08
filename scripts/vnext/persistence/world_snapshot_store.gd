class_name VNextWorldSnapshotStore
extends RefCounted
## File boundary for VNextWorldRuntime snapshots.
## Runtime state stays owned by VNextWorldRuntime; atomic file mechanics stay
## owned by AtomicJsonFileStore.


func save(runtime: VNextWorldRuntime, path: String) -> SaveOperationResult:
	if runtime == null:
		return SaveOperationResult.fail(
			"invalid_runtime", "vNext runtime is required", path
		)
	if path.is_empty():
		return SaveOperationResult.fail(
			"invalid_path", "vNext snapshot path is empty", path
		)

	var snapshot_value: Dictionary = runtime.snapshot()
	var write_error: String = AtomicJsonFileStore.write_verified(
		path,
		snapshot_value,
		Callable(self, "_verify_temporary_snapshot"),
		true
	)
	if not write_error.is_empty():
		return SaveOperationResult.fail(
			"write_error",
			"vNext snapshot save failed: %s" % write_error,
			path
		)

	var result := SaveOperationResult.ok(path, snapshot_value)
	result.message = "vNext snapshot saved."
	return result


func load(runtime: VNextWorldRuntime, path: String) -> SaveOperationResult:
	if runtime == null:
		return SaveOperationResult.fail(
			"invalid_runtime", "vNext runtime is required", path
		)
	if path.is_empty():
		return SaveOperationResult.fail(
			"invalid_path", "vNext snapshot path is empty", path
		)

	var primary := _validate_snapshot_file(path)
	if primary.success:
		return _restore_validated_snapshot(
			runtime, primary, path, "vNext snapshot loaded."
		)

	var backup_path: String = path + AtomicJsonFileStore.BACKUP_SUFFIX
	var backup := _validate_snapshot_file(backup_path)
	if backup.success:
		return _restore_validated_snapshot(
			runtime,
			backup,
			path,
			"Primary vNext snapshot invalid; loaded backup."
		)

	return SaveOperationResult.fail(
		"load_error",
		"Primary vNext snapshot unavailable: %s; backup unavailable: %s" % [
			primary.message,
			backup.message,
		],
		path
	)


func _verify_temporary_snapshot(absolute_path: String) -> String:
	var result := _validate_snapshot_file(absolute_path)
	if result.success:
		return ""
	return "vNext temporary snapshot verification failed: %s" % result.message


func _validate_snapshot_file(path: String) -> SaveOperationResult:
	var loaded := _read_snapshot_file(path)
	if not loaded.success:
		return loaded

	var candidate := VNextWorldRuntime.new()
	if not candidate.restore(loaded.snapshot):
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"vNext snapshot schema or state is invalid",
			path
		)
	return SaveOperationResult.ok(path, candidate.snapshot())


func _restore_validated_snapshot(
	runtime: VNextWorldRuntime,
	validated: SaveOperationResult,
	result_path: String,
	message: String
) -> SaveOperationResult:
	if not runtime.restore(validated.snapshot):
		return SaveOperationResult.fail(
			"restore_error",
			"validated vNext snapshot could not be restored",
			result_path
		)
	var result := SaveOperationResult.ok(result_path, runtime.snapshot())
	result.message = message
	return result


func _read_snapshot_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "snapshot file not found", path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error", error_string(FileAccess.get_open_error()), path
		)

	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"line %d: %s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			],
			path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot", "snapshot root must be an object", path
		)
	return SaveOperationResult.ok(path, parser.data as Dictionary)
