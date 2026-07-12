class_name SimulationEventQueue
extends RefCounted
## Deterministic hour-based queue. Events with the same due hour keep insertion order.

var _events: Array[Dictionary] = []
var _event_ids: Dictionary = {}
var _next_sequence: int = 0


func schedule_event(event_id: String, due_hour: int, payload: Dictionary = {}) -> bool:
	if event_id.is_empty() or due_hour < 0 or _event_ids.has(event_id):
		return false

	var event: Dictionary = {
		"id": event_id,
		"due_hour": due_hour,
		"sequence": _next_sequence,
		"payload": payload.duplicate(true),
	}
	_next_sequence += 1
	_events.append(event)
	_event_ids[event_id] = true
	_events.sort_custom(_event_comes_before)
	return true


func cancel_event(event_id: String) -> bool:
	if not _event_ids.has(event_id):
		return false
	for index: int in range(_events.size()):
		if str(_events[index]["id"]) == event_id:
			_events.remove_at(index)
			_event_ids.erase(event_id)
			return true
	return false


func pop_due_events(current_hour: int) -> Array[Dictionary]:
	var due_events: Array[Dictionary] = []
	while not _events.is_empty() and int(_events[0]["due_hour"]) <= current_hour:
		var event: Dictionary = _events.pop_front()
		_event_ids.erase(str(event["id"]))
		due_events.append(event.duplicate(true))
	return due_events


func has_event(event_id: String) -> bool:
	return _event_ids.has(event_id)


func size() -> int:
	return _events.size()


func clear() -> void:
	_events.clear()
	_event_ids.clear()
	_next_sequence = 0


func get_state() -> Dictionary:
	return {"events": _events.duplicate(true), "next_sequence": _next_sequence}


func restore_state(state: Dictionary) -> bool:
	var raw_events: Variant = state.get("events", [])
	var next_sequence: int = int(state.get("next_sequence", 0))
	if not raw_events is Array or next_sequence < 0:
		return false
	var restored: Array[Dictionary] = []
	var ids: Dictionary = {}
	var max_sequence: int = -1
	for raw_event: Variant in raw_events:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = raw_event as Dictionary
		var event_id: String = str(event.get("id", ""))
		var due_hour: int = int(event.get("due_hour", -1))
		var sequence: int = int(event.get("sequence", -1))
		if event_id.is_empty() or due_hour < 0 or sequence < 0 or ids.has(event_id):
			return false
		if not event.get("payload", {}) is Dictionary:
			return false
		restored.append({"id": event_id, "due_hour": due_hour, "sequence": sequence,
			"payload": (event.get("payload", {}) as Dictionary).duplicate(true)})
		ids[event_id] = true
		max_sequence = maxi(max_sequence, sequence)
	if next_sequence <= max_sequence:
		return false
	restored.sort_custom(_event_comes_before)
	_events = restored
	_event_ids = ids
	_next_sequence = next_sequence
	return true


static func _event_comes_before(left: Dictionary, right: Dictionary) -> bool:
	var left_hour: int = int(left["due_hour"])
	var right_hour: int = int(right["due_hour"])
	if left_hour != right_hour:
		return left_hour < right_hour
	return int(left["sequence"]) < int(right["sequence"])
