extends RefCounted
## Stateless helpers for formal-time behavior tests only.


static func backup_formal_save() -> Dictionary:
	var result := {
		"exists": false,
		"read_error": false,
		"bytes": PackedByteArray(),
	}
	var path: String = FormalWorldSimulation.SAVE_PATH
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["exists"] = true
		result["read_error"] = true
		return result
	result["exists"] = true
	result["bytes"] = file.get_buffer(file.get_length())
	file.close()
	return result


static func cleanup_formal_save() -> bool:
	var success := true
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = FormalWorldSimulation.SAVE_PATH + suffix
		if not FileAccess.file_exists(path):
			continue
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			success = false
	return success


static func restore_formal_save(backup: Dictionary) -> bool:
	if not cleanup_formal_save():
		return false
	if not bool(backup.get("exists", false)):
		return true
	if bool(backup.get("read_error", false)):
		return false
	var file := FileAccess.open(FormalWorldSimulation.SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(backup.get("bytes", PackedByteArray()) as PackedByteArray)
	file.flush()
	file.close()
	return true


static func hemisphere_state(application: FormalWorldApplication) -> Dictionary:
	return {
		"year": application.sim_year,
		"month": application.sim_month,
		"day": application.sim_day,
		"hour": application.sim_hour,
		"minute": application.sim_minute,
		"paused": application.sim_paused,
		"speed": application.sim_speed,
	}


static func set_hemisphere_time(
	application: FormalWorldApplication,
	year: int,
	month: int,
	day: int,
	hour: int,
	minute: int
) -> void:
	application.sim_year = year
	application.sim_month = month
	application.sim_day = day
	application.sim_hour = hour
	application.sim_minute = minute


static func hemisphere_total_hour(application: FormalWorldApplication) -> int:
	return V2DateTime.to_total_hour({
		"year": application.sim_year,
		"month": application.sim_month,
		"day": application.sim_day,
		"hour": application.sim_hour,
	})


static func hemisphere_total_minute(application: FormalWorldApplication) -> int:
	var total_hour := hemisphere_total_hour(application)
	return -1 if total_hour < 0 else total_hour * 60 + application.sim_minute


static func simulation_state(simulation: FormalWorldSimulation) -> Dictionary:
	return simulation.get_persistent_state().duplicate(true)
