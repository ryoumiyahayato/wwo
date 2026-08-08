class_name VNextWorldRuntime
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_world_runtime_v1"

var _total_minutes: int = 0


func total_minutes() -> int:
	return _total_minutes


func advance_minutes(minutes: int) -> bool:
	if minutes <= 0:
		return false
	_total_minutes += minutes
	return true


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"total_minutes": _total_minutes,
	}


func restore(snapshot_value: Dictionary) -> bool:
	var candidate_schema_id: Variant = snapshot_value.get("schema_id")
	var has_total_minutes: bool = snapshot_value.has("total_minutes")
	var candidate_total_minutes_value: Variant = snapshot_value.get("total_minutes")

	if candidate_schema_id != SNAPSHOT_SCHEMA_ID:
		return false
	if not has_total_minutes:
		return false

	var candidate_total_minutes: int
	var candidate_total_minutes_type: int = typeof(candidate_total_minutes_value)
	if candidate_total_minutes_type == TYPE_INT:
		candidate_total_minutes = int(candidate_total_minutes_value)
		if candidate_total_minutes < 0:
			return false
	elif candidate_total_minutes_type == TYPE_FLOAT:
		var candidate_total_minutes_float: float = float(candidate_total_minutes_value)
		if not is_finite(candidate_total_minutes_float):
			return false
		if candidate_total_minutes_float < 0.0:
			return false
		if candidate_total_minutes_float != floor(candidate_total_minutes_float):
			return false
		candidate_total_minutes = int(candidate_total_minutes_float)
	else:
		return false

	_total_minutes = candidate_total_minutes
	return true
