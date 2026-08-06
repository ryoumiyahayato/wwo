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
	var value := application.formal_simulation.date_time()
	return {
		"year": int(value.get("year", 0)),
		"month": int(value.get("month", 0)),
		"day": int(value.get("day", 0)),
		"hour": int(value.get("hour", -1)),
		"minute": int(value.get("minute", -1)),
		"paused": application.sim_paused,
		"speed": application.sim_speed,
	}


static func hemisphere_total_hour(application: FormalWorldApplication) -> int:
	return V2DateTime.to_total_hour(application.formal_simulation.date_time())


static func hemisphere_total_minute(application: FormalWorldApplication) -> int:
	return application.formal_simulation.total_minutes


static func simulation_state(simulation: FormalWorldSimulation) -> Dictionary:
	return simulation.get_persistent_state().duplicate(true)


static func first_semantic_difference(
	actual: Variant, expected: Variant, path: String = "$"
) -> String:
	var actual_type: int = typeof(actual)
	var expected_type: int = typeof(expected)
	if _is_number_type(actual_type) and _is_number_type(expected_type):
		var same_value: bool = (
			actual == expected
			if actual_type == TYPE_INT and expected_type == TYPE_INT
			else float(actual) == float(expected)
		)
		var same_json_value: bool = JSON.stringify(actual) == JSON.stringify(expected)
		return "" if same_value or same_json_value else (
			"%s numeric value differs (%s != %s)" % [path, str(actual), str(expected)]
		)
	if actual_type != expected_type:
		return "%s type differs (%s != %s)" % [
			path,
			type_string(actual_type),
			type_string(expected_type),
		]
	if actual is Dictionary:
		var actual_dictionary := actual as Dictionary
		var expected_dictionary := expected as Dictionary
		if actual_dictionary.size() != expected_dictionary.size():
			return "%s dictionary size differs (%d != %d)" % [
				path,
				actual_dictionary.size(),
				expected_dictionary.size(),
			]
		var keys: Array = expected_dictionary.keys()
		keys.sort()
		for key: Variant in keys:
			if not actual_dictionary.has(key):
				return "%s missing key %s" % [path, str(key)]
			var difference := first_semantic_difference(
				actual_dictionary[key],
				expected_dictionary[key],
				"%s.%s" % [path, str(key)]
			)
			if not difference.is_empty():
				return difference
		return ""
	if actual is Array:
		var actual_array := actual as Array
		var expected_array := expected as Array
		if actual_array.size() != expected_array.size():
			return "%s array size differs (%d != %d)" % [
				path,
				actual_array.size(),
				expected_array.size(),
			]
		for index: int in range(expected_array.size()):
			var difference := first_semantic_difference(
				actual_array[index],
				expected_array[index],
				"%s[%d]" % [path, index]
			)
			if not difference.is_empty():
				return difference
		return ""
	return "" if actual == expected else (
		"%s value differs (%s != %s)" % [path, str(actual), str(expected)]
	)


static func _is_number_type(value_type: int) -> bool:
	return value_type == TYPE_INT or value_type == TYPE_FLOAT
