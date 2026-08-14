extends RefCounted
## Stateless helpers for formal-time behavior tests only.

const FORMAL_SAVE_ARTIFACT_SUFFIXES: Array[String] = ["", ".bak", ".tmp"]


static func backup_formal_save() -> Dictionary:
	var result := {
		"exists": false,
		"read_error": false,
		"bytes": PackedByteArray(),
		"artifacts": {},
	}
	var artifacts: Dictionary = result["artifacts"] as Dictionary
	for suffix: String in FORMAL_SAVE_ARTIFACT_SUFFIXES:
		var path: String = FormalWorldSimulation.SAVE_PATH + suffix
		var artifact := {
			"exists": FileAccess.file_exists(path),
			"read_error": false,
			"bytes": PackedByteArray(),
		}
		if bool(artifact["exists"]):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				artifact["read_error"] = true
				result["read_error"] = true
			else:
				artifact["bytes"] = file.get_buffer(file.get_length())
				file.close()
		artifacts[suffix] = artifact
		if suffix.is_empty():
			result["exists"] = bool(artifact["exists"])
			result["bytes"] = artifact["bytes"]
	return result


static func cleanup_formal_save() -> bool:
	var success := true
	for suffix: String in FORMAL_SAVE_ARTIFACT_SUFFIXES:
		var path: String = FormalWorldSimulation.SAVE_PATH + suffix
		if not FileAccess.file_exists(path):
			continue
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			success = false
	return success


static func restore_formal_save(backup: Dictionary) -> bool:
	if not backup.has("exists") and not backup.has("artifacts"):
		return false
	if bool(backup.get("read_error", false)):
		return false
	if not cleanup_formal_save():
		return false
	var artifacts := backup.get("artifacts", {}) as Dictionary
	if artifacts.is_empty():
		return _restore_formal_save_artifact(
			"",
			bool(backup.get("exists", false)),
			backup.get("bytes", PackedByteArray()) as PackedByteArray
		)
	for suffix: String in FORMAL_SAVE_ARTIFACT_SUFFIXES:
		var artifact := artifacts.get(suffix, {}) as Dictionary
		if bool(artifact.get("read_error", false)):
			return false
		if not bool(artifact.get("exists", false)):
			continue
		if not _restore_formal_save_artifact(
			suffix,
			true,
			artifact.get("bytes", PackedByteArray()) as PackedByteArray
		):
			return false
	return true


static func _restore_formal_save_artifact(
	suffix: String, exists: bool, bytes: PackedByteArray
) -> bool:
	if not exists:
		return true
	var file := FileAccess.open(FormalWorldSimulation.SAVE_PATH + suffix, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
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
