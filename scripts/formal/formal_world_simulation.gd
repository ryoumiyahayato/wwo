class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. It owns the 151-unit historical political
## world and the separate 50-polity high-detail economy roster.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v2"

var economy := FormalWorldEconomyService.new()
var authority := HistoricalAuthorityModel.new()
var initialized: bool = false
var initialization_error: String = ""
var total_minutes: int = 0
var _minute_remainder: int:
	get:
		return total_minutes % 60


func _init() -> void:
	economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)


func initialize() -> bool:
	initialization_error = ""
	total_minutes = 0
	if not economy.configure():
		initialization_error = economy.initialization_error
		initialized = false
		return false
	if not authority.configure_from_path(FormalWorldEconomyService.POLITICAL_UNITS_PATH):
		initialization_error = authority.initialization_error
		initialized = false
		return false
	initialized = true
	state_changed.emit({"initialized": true})
	return true


func advance_minutes(minutes: int) -> Dictionary:
	if not initialized or minutes <= 0:
		return economy.world_summary()
	var previous_total_hour := _authoritative_total_hour()
	total_minutes += minutes
	var current_total_hour := _authoritative_total_hour()
	var elapsed_hours := current_total_hour - previous_total_hour
	if elapsed_hours > 0:
		var summary := economy.settle_hour_range(
			previous_total_hour, current_total_hour
		)
		state_changed.emit({
			"time": true,
			"economy": true,
			"hours": elapsed_hours,
		})
		return summary
	state_changed.emit({"time": true, "economy": false, "hours": 0})
	return economy.world_summary()


func world_summary() -> Dictionary:
	return economy.world_summary()


func country_summary(entity_id: String) -> Dictionary:
	return economy.country_summary(entity_id)


func polity_summary(entity_id: String) -> Dictionary:
	var result := economy.polity_summary(entity_id)
	if result.is_empty():
		return result
	# controller_id remains a deterministic presentation compatibility value.
	# sovereign_id is populated only from an explicit sovereign relation.
	result["controller_id"] = authority.legacy_presentation_controller(entity_id)
	result["sovereign_id"] = authority.first_sovereign_id(entity_id)
	return result


func get_authority_relations(entity_id: String) -> Array[Dictionary]:
	return authority.get_authority_relations(entity_id)


func get_relations_by_type(
	entity_id: String, relationship_type: String
) -> Array[Dictionary]:
	return authority.get_relations_by_type(entity_id, relationship_type)


func get_sovereigns(entity_id: String) -> Array[Dictionary]:
	return authority.get_sovereigns(entity_id)


func get_protectors(entity_id: String) -> Array[Dictionary]:
	return authority.get_protectors(entity_id)


func get_administrators(entity_id: String) -> Array[Dictionary]:
	return authority.get_administrators(entity_id)


func get_occupiers(entity_id: String) -> Array[Dictionary]:
	return authority.get_occupiers(entity_id)


func get_de_facto_controllers(entity_id: String) -> Array[Dictionary]:
	return authority.get_de_facto_controllers(entity_id)


func get_foreign_relations_controllers(entity_id: String) -> Array[Dictionary]:
	return authority.get_foreign_relations_controllers(entity_id)


func get_claimants(entity_id: String) -> Array[Dictionary]:
	return authority.get_claimants(entity_id)


func get_active_relations(entity_id: String, date: String) -> Array[Dictionary]:
	return authority.get_active_relations(entity_id, date)


func legacy_presentation_controller(entity_id: String) -> String:
	return authority.legacy_presentation_controller(entity_id)


func has_polity(entity_id: String) -> bool:
	return economy.has_polity(entity_id)


func first_polity_id() -> String:
	return economy.first_polity_id()


func date_time() -> Dictionary:
	var value := V2DateTime.from_total_hour(_authoritative_total_hour())
	value["minute"] = _minute_remainder
	return value


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"total_minutes": total_minutes,
		"minute_remainder": _minute_remainder,
		"economy": economy.get_persistent_state(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in ["formal_world_simulation_v1", SCHEMA_ID]
		or not state.get("economy", {}) is Dictionary
	):
		return false
	var validated_time := _validated_time_state(state, schema_id)
	if validated_time.is_empty():
		return false
	var previous_total_minutes := total_minutes
	var previous_initialized := initialized
	var previous_economy := economy.get_persistent_state()
	total_minutes = int(validated_time.get("total_minutes", -1))
	if not economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	):
		total_minutes = previous_total_minutes
		economy.restore_persistent_state(previous_economy)
		initialized = previous_initialized
		return false
	initialized = true
	state_changed.emit({"restored": true})
	return true


func save_to_user() -> SaveOperationResult:
	if not initialized:
		return SaveOperationResult.fail(
			"not_initialized",
			"正式世界尚未初始化，无法保存。",
			SAVE_PATH
		)
	var snapshot := get_persistent_state()
	var write_error := AtomicJsonFileStore.write_verified(
		SAVE_PATH,
		snapshot,
		Callable(self, "_verify_temporary_save"),
		true
	)
	if not write_error.is_empty():
		return SaveOperationResult.fail(
			"write_error",
			"正式世界保存失败：%s" % write_error,
			SAVE_PATH
		)
	state_changed.emit({"saved": true})
	var result := SaveOperationResult.ok(SAVE_PATH, snapshot)
	result.message = "正式世界已保存。"
	return result


func _verify_temporary_save(absolute_path: String) -> String:
	var loaded := _read_snapshot_file(absolute_path)
	if not loaded.success:
		return "临时存档校验失败：%s" % loaded.message
	var candidate := FormalWorldSimulation.new()
	if not candidate.initialize():
		return "临时存档校验失败：正式世界初始化失败：%s" % (
			candidate.initialization_error
		)
	if not candidate.restore_persistent_state(loaded.snapshot):
		return "临时存档校验失败：正式世界状态无效"
	return ""


func load_from_user() -> SaveOperationResult:
	var primary := _restore_snapshot_file(SAVE_PATH)
	if primary.success:
		primary.message = "正式世界存档已恢复。"
		return primary
	var backup_path := SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	var backup := _restore_snapshot_file(backup_path)
	if backup.success:
		backup.path = SAVE_PATH
		backup.message = "主存档不可用，已读取安全备份"
		return backup
	return SaveOperationResult.fail(
		"load_error",
		"主存档不可用：%s；安全备份不可用：%s" % [
			primary.message,
			backup.message,
		],
		SAVE_PATH
	)


func _restore_snapshot_file(path: String) -> SaveOperationResult:
	var loaded := _read_snapshot_file(path)
	if not loaded.success:
		return loaded
	if not restore_persistent_state(loaded.snapshot):
		return SaveOperationResult.fail(
			"restore_error",
			"存档状态校验或恢复失败",
			path
		)
	return loaded


func _read_snapshot_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "存档不存在", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error",
			error_string(FileAccess.get_open_error()),
			path
		)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			],
			path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"存档根节点必须是对象",
			path
		)
	return SaveOperationResult.ok(path, parser.data as Dictionary)


func _authoritative_total_hour() -> int:
	return int(total_minutes / 60)


func _validated_time_state(state: Dictionary, schema_id: String) -> Dictionary:
	var economy_state := state.get("economy", {}) as Dictionary
	var saved_total_hour := int(economy_state.get("total_hour", -1))
	if saved_total_hour < 0:
		return {}
	if schema_id == SCHEMA_ID and (
		not state.has("total_minutes") or not state.has("minute_remainder")
	):
		return {}
	var has_total_minutes := state.has("total_minutes")
	var has_minute_remainder := state.has("minute_remainder")
	var total := int(state.get("total_minutes", saved_total_hour * 60))
	var remainder := int(state.get("minute_remainder", posmod(total, 60)))
	if not has_total_minutes and has_minute_remainder:
		total = saved_total_hour * 60 + remainder
	if (
		total < 0
		or remainder < 0
		or remainder > 59
		or posmod(total, 60) != remainder
		or int(total / 60) != saved_total_hour
	):
		return {}
	return {
		"total_minutes": total,
		"minute_remainder": remainder,
	}
