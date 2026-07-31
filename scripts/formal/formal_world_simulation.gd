class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. It owns the 151-unit historical political
## world and the separate 50-polity high-detail economy roster.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v2"

var economy := FormalWorldEconomyService.new()
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
	return economy.polity_summary(entity_id)


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


func save_to_user() -> bool:
	if not initialized:
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(get_persistent_state()))
	file.flush()
	file.close()
	state_changed.emit({"saved": true})
	return true


func load_from_user() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed is Dictionary and restore_persistent_state(parsed as Dictionary)


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
