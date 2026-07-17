class_name V2ReviewSaveService
extends GameSaveService
## V2.2 GameSaveService adapter that retains the previous valid primary as .bak.


func save_v2_2_review(
	simulation: V2LifeLoopSimulation,
	path: String = V2_2_REVIEW_PATH
) -> SaveOperationResult:
	var snapshot: Dictionary = build_v2_2_snapshot(simulation)
	var errors: Array[String] = validate_v2_2_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors), path)
	if not path.begins_with("user://") or not path.ends_with(".json"):
		return SaveOperationResult.fail(
			"unsafe_path", "存档只能写入 user:// 下的 JSON 文件", path
		)
	var write_error: String = _write_review_atomic(path, snapshot)
	if not write_error.is_empty():
		return SaveOperationResult.fail("write_error", write_error, path)
	return SaveOperationResult.ok(path, snapshot)


func _write_review_atomic(path: String, snapshot: Dictionary) -> String:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if make_error != OK:
		return error_string(make_error)
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(snapshot, "\t", false))
	file.flush()
	file.close()
	var verification: SaveOperationResult = _load_v2_2_path_for_verification(temporary_path)
	if not verification.success:
		DirAccess.remove_absolute(temporary_path)
		return "临时存档写入后校验失败：%s" % verification.message

	var had_primary: bool = FileAccess.file_exists(absolute_path)
	if had_primary:
		if FileAccess.file_exists(backup_path):
			var remove_old_backup: Error = DirAccess.remove_absolute(backup_path)
			if remove_old_backup != OK:
				DirAccess.remove_absolute(temporary_path)
				return error_string(remove_old_backup)
		var backup_error: Error = DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return error_string(backup_error)
	var replace_error: Error = DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		if had_primary and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(temporary_path)
		return error_string(replace_error)
	return ""


func _load_v2_2_path_for_verification(absolute_path: String) -> SaveOperationResult:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error", error_string(FileAccess.get_open_error()), absolute_path
		)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
			absolute_path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot", "存档根节点必须是对象", absolute_path
		)
	var normalized: Dictionary = _canonical_value(parser.data) as Dictionary
	var errors: Array[String] = validate_v2_2_snapshot(normalized)
	if not errors.is_empty():
		return SaveOperationResult.fail(
			"invalid_snapshot", "; ".join(errors), absolute_path
		)
	return SaveOperationResult.ok(absolute_path, normalized)


static func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for raw_key: Variant in source.keys():
			keys.append(str(raw_key))
		keys.sort()
		var result: Dictionary = {}
		for key: String in keys:
			result[key] = _canonical_value(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_canonical_value(item))
		return result
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value
