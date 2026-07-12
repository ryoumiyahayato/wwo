class_name SettlementLogService
extends RefCounted
## Bounded, event-level simulation log. It intentionally never records each hour.

const DEFAULT_MAX_ENTRIES: int = 200

var max_entries: int = DEFAULT_MAX_ENTRIES
var entries: Array[Dictionary] = []


func _init(entry_limit: int = DEFAULT_MAX_ENTRIES) -> void:
	max_entries = maxi(entry_limit, 1)


func add(category: String, message: String, total_hour: int, details: Dictionary = {}) -> void:
	entries.append({
		"category": category,
		"message": message,
		"total_hour": total_hour,
		"details": details.duplicate(true),
	})
	while entries.size() > max_entries:
		entries.pop_front()


func get_entries(category: String = "") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if category.is_empty() or str(entry.get("category", "")) == category:
			output.append(entry.duplicate(true))
	return output


func restore_state(state: Dictionary) -> bool:
	var raw_entries: Variant = state.get("entries", [])
	var limit: int = int(state.get("max_entries", DEFAULT_MAX_ENTRIES))
	if not raw_entries is Array or limit < 1:
		return false
	var restored: Array[Dictionary] = []
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			return false
		var entry: Dictionary = raw_entry as Dictionary
		if str(entry.get("category", "")).is_empty() or int(entry.get("total_hour", -1)) < 0 or not entry.get("details", {}) is Dictionary:
			return false
		restored.append(entry.duplicate(true))
	max_entries = limit
	entries = restored.slice(maxi(0, restored.size() - limit))
	return true


func get_state() -> Dictionary:
	return {"max_entries": max_entries, "entries": entries.duplicate(true)}
