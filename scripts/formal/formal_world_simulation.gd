class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. It owns domain authorities and commits
## cross-domain transitions only after their combined state validates.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v3"

var politics := FormalDatedPoliticalAuthority.new()
var economy := FormalWorldEconomyService.new()
var initialized: bool = false
var initialization_error: String = ""
var last_transition_error: String = ""
var total_minutes: int = 0
var _minute_remainder: int:
	get:
		return total_minutes % 60


func _init() -> void:
	_bind_domain_authorities()


func _bind_domain_authorities() -> void:
	politics.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)
	economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)


func initialize() -> bool:
	initialization_error = ""
	last_transition_error = ""
	total_minutes = 0
	if not politics.configure():
		initialization_error = politics.initialization_error
		initialized = false
		return false
	if not economy.configure(politics):
		initialization_error = economy.initialization_error
		initialized = false
		return false
	if not _validate_composition():
		initialization_error = "正式世界政治与经济权威不兼容"
		initialized = false
		return false
	initialized = true
	state_changed.emit({"initialized": true})
	return true


func advance_minutes(minutes: int) -> Dictionary:
	if not initialized or minutes <= 0:
		return economy.world_summary()
	last_transition_error = ""
	var previous_total_minutes := total_minutes
	var previous_total_hour := _authoritative_total_hour()
	var candidate_total_hour := int((total_minutes + minutes) / 60)
	var economy_will_mutate := (
		int(previous_total_hour / FormalWorldEconomyService.HOURS_PER_DAY)
		!= int(candidate_total_hour / FormalWorldEconomyService.HOURS_PER_DAY)
	)
	var previous_snapshot: Dictionary = (
		get_persistent_state() if economy_will_mutate else {}
	)
	total_minutes += minutes
	var current_total_hour := _authoritative_total_hour()
	if not politics.synchronize():
		return _rollback_failed_transition(
			previous_snapshot,
			previous_total_minutes,
			"政治权威无法推进到候选日期"
		)
	var elapsed_hours := current_total_hour - previous_total_hour
	if elapsed_hours > 0:
		var summary := economy.settle_hour_range(
			previous_total_hour, current_total_hour
		)
		if not _validate_composition():
			return _rollback_failed_transition(
				previous_snapshot,
				previous_total_minutes,
				"候选世界未通过政治/经济兼容性校验"
			)
		state_changed.emit({
			"time": true,
			"politics": true,
			"economy": true,
			"hours": elapsed_hours,
		})
		return summary
	if not _validate_composition():
		return _rollback_failed_transition(
			previous_snapshot,
			previous_total_minutes,
			"分钟推进后的候选世界无效"
		)
	state_changed.emit({
		"time": true,
		"politics": true,
		"economy": false,
		"hours": 0,
	})
	return economy.world_summary()


func world_summary() -> Dictionary:
	return economy.world_summary()


func country_summary(entity_id: String) -> Dictionary:
	return economy.country_summary(entity_id)


func polity_summary(entity_id: String) -> Dictionary:
	return economy.polity_summary(entity_id)


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
		"politics": politics.get_persistent_state(),
		"economy": economy.get_persistent_state(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var candidate := FormalWorldSimulation.new()
	if not candidate.initialize() or not candidate._restore_validated_in_place(state):
		return false
	_adopt_candidate(candidate)
	state_changed.emit({"restored": true})
	return true


func _restore_validated_in_place(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in [
			"formal_world_simulation_v1",
			"formal_world_simulation_v2",
			SCHEMA_ID,
		]
		or not state.get("economy", {}) is Dictionary
		or (
			schema_id == SCHEMA_ID
			and not state.get("politics", {}) is Dictionary
		)
	):
		return false
	var validated_time := _validated_time_state(state, schema_id)
	if validated_time.is_empty():
		return false
	total_minutes = int(validated_time.get("total_minutes", -1))
	if not politics.synchronize():
		return false
	if schema_id == SCHEMA_ID and not politics.restore_persistent_state(
		state.get("politics", {}) as Dictionary
	):
		return false
	if not economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	):
		return false
	initialized = true
	return _validate_composition()


func _adopt_candidate(candidate: FormalWorldSimulation) -> void:
	total_minutes = candidate.total_minutes
	politics = candidate.politics
	economy = candidate.economy
	_bind_domain_authorities()
	assert(politics.synchronize())
	initialized = true
	initialization_error = ""
	last_transition_error = ""


func _rollback_failed_transition(
	previous_snapshot: Dictionary,
	previous_total_minutes: int,
	message: String
) -> Dictionary:
	if previous_snapshot.is_empty():
		total_minutes = previous_total_minutes
		assert(politics.synchronize())
		last_transition_error = message
		return economy.world_summary()
	var rollback := FormalWorldSimulation.new()
	var restored := rollback.initialize() and rollback._restore_validated_in_place(
		previous_snapshot
	)
	assert(restored, "Known-valid formal world snapshot failed rollback")
	if restored:
		_adopt_candidate(rollback)
	last_transition_error = message
	return economy.world_summary()


func _validate_composition() -> bool:
	if not politics.is_configured() or not politics.synchronize():
		return false
	if politics.current_date() != V2DateTime.date_from_total_hour(
		_authoritative_total_hour()
	):
		return false
	return economy.validate_authoritative_state()


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
	if schema_id in ["formal_world_simulation_v2", SCHEMA_ID] and (
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
