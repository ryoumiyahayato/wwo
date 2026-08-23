class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. It owns daily political evolution for the
## dated historical catalog and the separate detailed economy roster.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v4"

var political_authority := FormalDatedPoliticalAuthority.new()
var economy := FormalWorldEconomyService.new()
var politics := FormalPoliticalSimulationService.new()
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
	if not political_authority.configure(0):
		initialization_error = political_authority.initialization_error
		initialized = false
		return false
	if not economy.configure(political_authority):
		initialization_error = economy.initialization_error
		initialized = false
		return false
	if not politics.configure(_political_inputs(true), 0):
		initialization_error = politics.initialization_error
		initialized = false
		return false
	if not economy.set_political_modifiers(politics.economy_modifiers()):
		initialization_error = "正式政治经济联动初始化失败"
		initialized = false
		return false
	initialized = true
	state_changed.emit({"initialized": true})
	return true


func advance_minutes(minutes: int) -> Dictionary:
	if not initialized or minutes <= 0:
		return world_summary()
	var previous_total_hour := _authoritative_total_hour()
	var target_total_minutes := total_minutes + minutes
	var current_total_hour := int(target_total_minutes / 60)
	var elapsed_hours := current_total_hour - previous_total_hour
	while previous_total_hour < current_total_hour:
		var next_day_hour := (
			int(previous_total_hour / FormalWorldEconomyService.HOURS_PER_DAY) + 1
		) * FormalWorldEconomyService.HOURS_PER_DAY
		var segment_hour := mini(current_total_hour, next_day_hour)
		total_minutes = segment_hour * 60
		economy.settle_hour_range(previous_total_hour, segment_hour)
		if segment_hour % FormalWorldEconomyService.HOURS_PER_DAY == 0:
			var day_index := int(
				segment_hour / FormalWorldEconomyService.HOURS_PER_DAY
			)
			if political_authority.advance_to_day(day_index).is_empty():
				initialization_error = "正式历史政治权威无法推进到当前日期"
				initialized = false
				state_changed.emit({"simulation_error": initialization_error})
				return world_summary()
			if not politics.settle_day(day_index, _political_inputs(false)):
				initialization_error = "正式政治日结算拒绝了正式世界状态"
				initialized = false
				state_changed.emit({"simulation_error": initialization_error})
				return world_summary()
			if not economy.set_political_modifiers(politics.economy_modifiers()):
				initialization_error = "正式政治经济联动状态无效"
				initialized = false
				state_changed.emit({"simulation_error": initialization_error})
				return world_summary()
		previous_total_hour = segment_hour
	total_minutes = target_total_minutes
	state_changed.emit({
		"time": true,
		"economy": elapsed_hours > 0,
		"politics": elapsed_hours > 0,
		"hours": elapsed_hours,
	})
	return world_summary()


func world_summary() -> Dictionary:
	var result := economy.world_summary()
	result.merge(politics.world_summary(), true)
	var simulated_ids := politics.simulated_polity_ids()
	var detailed_count := 0
	for polity_id: String in simulated_ids:
		if economy.has_detailed_economy(polity_id):
			detailed_count += 1
	result["world_political_unit_count"] = simulated_ids.size()
	result["detailed_polity_unit_count"] = detailed_count
	result["background_polity_count"] = maxi(
		0, simulated_ids.size() - detailed_count
	)
	return result


func country_summary(entity_id: String) -> Dictionary:
	var result := economy.country_summary(entity_id)
	if result.is_empty():
		return result
	var political_states: Array[Dictionary] = []
	for polity_id: String in DataRecordUtils.to_string_array(
		result.get("polity_ids", [])
	):
		var political_state := politics.polity_summary(polity_id)
		if not political_state.is_empty():
			political_states.append(political_state)
	result["political_states"] = political_states
	return result


func polity_summary(entity_id: String) -> Dictionary:
	var result := economy.polity_summary(entity_id)
	if not result.is_empty():
		var political_state := politics.polity_summary(entity_id)
		var historical_controller_id := str(result.get("controller_id", ""))
		var effective_controller_id := str(
			political_state.get("effective_controller_id", "")
		)
		result["historical_controller_id"] = historical_controller_id
		result["effective_controller_id"] = effective_controller_id
		# Compatibility alias at the composition boundary means current control.
		result["controller_id"] = effective_controller_id
		result["historically_valid"] = (
			political_authority.is_historically_valid(entity_id)
		)
		result["simulation_active"] = not political_state.is_empty()
		result["politics"] = political_state
	return result


func has_polity(entity_id: String) -> bool:
	return political_authority.has_record(entity_id)


func first_polity_id() -> String:
	var ids := politics.simulated_polity_ids()
	return ids[0] if not ids.is_empty() else ""


func date_time() -> Dictionary:
	var value := V2DateTime.from_total_hour(_authoritative_total_hour())
	value["minute"] = _minute_remainder
	return value


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"total_minutes": total_minutes,
		"minute_remainder": _minute_remainder,
		"political_authority": political_authority.get_persistent_state(),
		"economy": economy.get_persistent_state(),
		"politics": politics.get_persistent_state(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in [
			"formal_world_simulation_v1",
			"formal_world_simulation_v2",
			"formal_world_simulation_v3",
			SCHEMA_ID,
		]
		or not state.get("economy", {}) is Dictionary
		or (schema_id in ["formal_world_simulation_v3", SCHEMA_ID]
			and not state.get("politics", {}) is Dictionary)
		or (schema_id == SCHEMA_ID
			and not state.get("political_authority", {}) is Dictionary)
	):
		return false
	var validated_time := _validated_time_state(state, schema_id)
	if validated_time.is_empty():
		return false
	var previous_total_minutes := total_minutes
	var previous_initialized := initialized
	var previous_economy := economy.get_persistent_state()
	var previous_politics := politics.get_persistent_state()
	var previous_authority := political_authority.get_persistent_state()
	total_minutes = int(validated_time.get("total_minutes", -1))
	if not economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	):
		total_minutes = previous_total_minutes
		economy.restore_persistent_state(previous_economy)
		initialized = previous_initialized
		return false
	var expected_political_day := int(
		_authoritative_total_hour() / FormalWorldEconomyService.HOURS_PER_DAY
	)
	var authority_restored := false
	if schema_id == SCHEMA_ID:
		authority_restored = political_authority.restore_persistent_state(
			state.get("political_authority", {}) as Dictionary,
			expected_political_day
		)
	else:
		authority_restored = not political_authority.advance_to_day(
			expected_political_day
		).is_empty()
	var politics_restored := false
	if schema_id in ["formal_world_simulation_v3", SCHEMA_ID]:
		politics_restored = politics.restore_persistent_state(
			state.get("politics", {}) as Dictionary,
			political_authority.snapshot(false)
		)
	else:
		politics_restored = politics.configure(
			_political_inputs(true),
			int(_authoritative_total_hour() / FormalWorldEconomyService.HOURS_PER_DAY)
		)
	if (
		not authority_restored
		or not politics_restored
		or int(politics.world_summary().get(
			"political_last_day_index", -1
		)) != expected_political_day
		or not economy.set_political_modifiers(politics.economy_modifiers())
	):
		total_minutes = previous_total_minutes
		economy.restore_persistent_state(previous_economy)
		political_authority.restore_persistent_state(
			previous_authority,
			int(
				previous_total_minutes
				/ (60 * FormalWorldEconomyService.HOURS_PER_DAY)
			)
		)
		politics.restore_persistent_state(
			previous_politics, political_authority.snapshot(false)
		)
		initialized = previous_initialized
		return false
	initialized = true
	state_changed.emit({"restored": true})
	return true


func _political_inputs(include_catalog: bool) -> Dictionary:
	var result := economy.political_inputs()
	result["authority"] = political_authority.snapshot(include_catalog)
	return result


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
