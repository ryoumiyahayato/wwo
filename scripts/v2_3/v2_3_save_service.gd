class_name V23SaveService
extends RefCounted
## Atomic V2.3 save with verified temporary file and retained valid backup.

const SCHEMA_VERSION: String = "v2_3_space_cognition_1"
const REVIEW_PATH: String = "user://saves/v2_3_space_cognition_slot.json"


func build_snapshot(simulation: V23LifeLoopSimulation) -> Dictionary:
	if simulation == null or not simulation.initialized:
		return {}
	var snapshot: Dictionary = simulation.get_persistent_state()
	snapshot["integrity"] = {
		"algorithm": "sha256",
		"digest": _digest(snapshot),
	}
	return snapshot


func save(
	simulation: V23LifeLoopSimulation,
	path: String = REVIEW_PATH
) -> SaveOperationResult:
	return save_snapshot(build_snapshot(simulation), path)


func save_snapshot(
	snapshot: Dictionary,
	path: String = REVIEW_PATH
) -> SaveOperationResult:
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors), path)
	if not _safe_path(path):
		return SaveOperationResult.fail(
			"unsafe_path", "存档只能写入 user:// 下的 JSON 文件", path
		)
	var write_error: String = _write_atomic(path, snapshot)
	if not write_error.is_empty():
		return SaveOperationResult.fail("write_error", write_error, path)
	return SaveOperationResult.ok(path, snapshot)


func load(path: String = REVIEW_PATH) -> SaveOperationResult:
	if not _safe_path(path):
		return SaveOperationResult.fail(
			"unsafe_path", "存档只能从 user:// 下的 JSON 文件读取", path
		)
	var primary: SaveOperationResult = _load_file(path)
	if primary.success:
		return primary
	var backup_path: String = path + ".bak"
	if FileAccess.file_exists(backup_path):
		var backup: SaveOperationResult = _load_file(backup_path)
		if backup.success:
			backup.path = path
			backup.message = "主存档不可用，已读取 V2.3 安全备份"
			return backup
	return primary


func restore(
	snapshot: Dictionary,
	simulation: V23LifeLoopSimulation
) -> SaveOperationResult:
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty() or simulation == null:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"; ".join(errors) if not errors.is_empty() else "V2.3 模拟不可用"
		)
	var result: V2LifeLoopResult = simulation.restore_v2_3_state(snapshot)
	if not result.success:
		return SaveOperationResult.fail(result.error_code, result.user_message)
	return SaveOperationResult.ok(REVIEW_PATH, snapshot)


func validate_snapshot(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(snapshot.get("schema_version", "")) != SCHEMA_VERSION:
		errors.append("不支持的 V2.3 存档版本")
	for field: String in [
		"person_states", "schedule_state", "household_state", "ledgers",
		"condition_state", "spatial_state", "travel_graph_state", "travel_state",
		"communication_state", "knowledge_state", "dynamic_relationship_state",
		"appointment_state", "introduction_state", "npc_spatial_state", "integrity",
	]:
		if not snapshot.get(field) is Dictionary:
			errors.append("V2.3 字段 %s 必须是对象" % field)
	for field: String in [
		"recent_completed_activities", "attendance_records", "processed_hour_keys",
		"background_person_ids",
	]:
		if not snapshot.get(field) is Array:
			errors.append("V2.3 字段 %s 必须是数组" % field)
	for field: String in ["current_datetime", "selected_person_id", "v2_3_scenario_id"]:
		if str(snapshot.get(field, "")).is_empty():
			errors.append("V2.3 字段 %s 不能为空" % field)
	if errors.is_empty():
		var integrity: Dictionary = snapshot["integrity"] as Dictionary
		if (
			str(integrity.get("algorithm", "")) != "sha256"
			or str(integrity.get("digest", "")) != _digest(snapshot)
		):
			errors.append("V2.3 存档完整性校验失败")
	return errors


func _write_atomic(path: String, snapshot: Dictionary) -> String:
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
	var verification: SaveOperationResult = _load_absolute_for_verification(temporary_path)
	if not verification.success:
		DirAccess.remove_absolute(temporary_path)
		return "临时 V2.3 存档校验失败：%s" % verification.message
	var had_primary: bool = FileAccess.file_exists(absolute_path)
	if had_primary:
		if FileAccess.file_exists(backup_path):
			var remove_backup: Error = DirAccess.remove_absolute(backup_path)
			if remove_backup != OK:
				DirAccess.remove_absolute(temporary_path)
				return error_string(remove_backup)
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


func _load_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "V2.3 存档不存在", path)
	return _load_absolute_for_verification(ProjectSettings.globalize_path(path), path)


func _load_absolute_for_verification(
	absolute_path: String, display_path: String = ""
) -> SaveOperationResult:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error", error_string(FileAccess.get_open_error()),
			absolute_path if display_path.is_empty() else display_path
		)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
			absolute_path if display_path.is_empty() else display_path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail("invalid_snapshot", "存档根节点必须是对象")
	var snapshot: Dictionary = _canonical(parser.data) as Dictionary
	var errors: Array[String] = validate_snapshot(snapshot)
	if not errors.is_empty():
		return SaveOperationResult.fail("invalid_snapshot", "; ".join(errors))
	return SaveOperationResult.ok(
		absolute_path if display_path.is_empty() else display_path, snapshot
	)


static func _safe_path(path: String) -> bool:
	return path.begins_with("user://") and path.ends_with(".json")


static func _digest(snapshot: Dictionary) -> String:
	var payload: Dictionary = snapshot.duplicate(true)
	payload.erase("integrity")
	return JSON.stringify(_canonical(payload), "", true).sha256_text()


static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for raw_key: Variant in source.keys():
			keys.append(str(raw_key))
		keys.sort()
		var result: Dictionary = {}
		for key: String in keys:
			result[key] = _canonical(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_canonical(item))
		return result
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value
