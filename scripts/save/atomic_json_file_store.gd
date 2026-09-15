class_name AtomicJsonFileStore
extends RefCounted
## Shared file boundary for verified JSON replacement with optional previous-primary backup.

const TEMPORARY_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"


static func write_verified(
	path: String,
	snapshot: Dictionary,
	verify_temporary: Callable,
	retain_previous_primary: bool
) -> String:
	if not verify_temporary.is_valid():
		return "原子写入缺少有效的临时文件校验器"
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if make_error != OK:
		return error_string(make_error)

	var temporary_path: String = absolute_path + TEMPORARY_SUFFIX
	var backup_path: String = absolute_path + BACKUP_SUFFIX
	var cleanup_error: Error = _remove_if_present(temporary_path)
	if cleanup_error != OK:
		return error_string(cleanup_error)

	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(snapshot, "\t", false))
	file.flush()
	file.close()

	var verification_error: String = str(verify_temporary.call(temporary_path))
	if not verification_error.is_empty():
		_remove_if_present(temporary_path)
		return verification_error

	var had_primary: bool = FileAccess.file_exists(absolute_path)
	if had_primary or not retain_previous_primary:
		var remove_backup_error: Error = _remove_if_present(backup_path)
		if remove_backup_error != OK:
			_remove_if_present(temporary_path)
			return error_string(remove_backup_error)
	if had_primary:
		var backup_error: Error = DirAccess.rename_absolute(
			absolute_path, backup_path
		)
		if backup_error != OK:
			_remove_if_present(temporary_path)
			return error_string(backup_error)

	var replace_error: Error = DirAccess.rename_absolute(
		temporary_path, absolute_path
	)
	if replace_error != OK:
		var rollback_error: Error = OK
		if had_primary and FileAccess.file_exists(backup_path):
			rollback_error = DirAccess.rename_absolute(backup_path, absolute_path)
		_remove_if_present(temporary_path)
		if rollback_error != OK:
			return "%s；回滚失败：%s" % [
				error_string(replace_error), error_string(rollback_error),
			]
		return error_string(replace_error)

	if not retain_previous_primary:
		_remove_if_present(backup_path)
	return ""


static func _remove_if_present(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)
