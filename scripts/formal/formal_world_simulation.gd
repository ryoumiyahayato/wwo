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
var _minute_remainder: int = 0


func initialize() -> bool:
	initialization_error = ""
	total_minutes = 0
	_minute_remainder = 0
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
	total_minutes += minutes
	_minute_remainder += minutes
	var hours := _minute_remainder / 60
	_minute_remainder %= 60
	if hours > 0:
		var summary := economy.advance_hours(hours)
		state_changed.emit({"time": true, "economy": true, "hours": hours})
		return summary
	return economy.world_summary()


func world_summary() -> Dictionary:
	return economy.world_summary()


func country_summary(entity_id: String) -> Dictionary:
	return economy.country_summary(entity_id)


func polity_summary(entity_id: String) -> Dictionary:
	return economy.polity_summary(entity_id)


func date_time() -> Dictionary:
	var value := V2DateTime.from_total_hour(economy.total_hour)
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
	var previous := get_persistent_state()
	if not economy.restore_persistent_state(state.get("economy", {}) as Dictionary):
		economy.restore_persistent_state(previous.get("economy", {}) as Dictionary)
		return false
	total_minutes = int(state.get("total_minutes", economy.total_hour * 60))
	_minute_remainder = clampi(int(state.get("minute_remainder", 0)), 0, 59)
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
	state_changed.emit({"saved": true})
	return true


func load_from_user() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed is Dictionary and restore_persistent_state(parsed as Dictionary)
