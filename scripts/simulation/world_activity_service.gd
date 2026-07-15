class_name WorldActivityService
extends RefCounted
## Bounded player-facing history of public world events.

signal event_added(event: Dictionary)

const MAX_EVENTS: int = 100
const IMPORTANCE_NORMAL: String = "normal"
const IMPORTANCE_IMPORTANT: String = "important"
const VALID_IMPORTANCE: Array[String] = [
	IMPORTANCE_NORMAL, IMPORTANCE_IMPORTANT,
]
const VALID_SUBJECT_TYPES: Array[String] = [
	"", "character", "organization", "region", "war",
]

var _events: Array[Dictionary] = []
var _next_event_id: int = 1


func add_event(
	category: String,
	title: String,
	description: String,
	world_hour: int,
	importance: String = IMPORTANCE_NORMAL,
	subject_type: String = "",
	subject_id: String = ""
) -> Dictionary:
	if (
		category.is_empty()
		or title.is_empty()
		or description.is_empty()
		or world_hour < 0
		or not VALID_IMPORTANCE.has(importance)
		or not VALID_SUBJECT_TYPES.has(subject_type)
		or (subject_type.is_empty() != subject_id.is_empty())
	):
		return {}
	var event: Dictionary = {
		"id": "world_event:%06d" % _next_event_id,
		"category": category,
		"title": title,
		"description": description,
		"world_hour": world_hour,
		"importance": importance,
		"subject_type": subject_type,
		"subject_id": subject_id,
	}
	_next_event_id += 1
	_events.append(event)
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
	event_added.emit(event.duplicate(true))
	return event.duplicate(true)


func get_recent(limit: int = MAX_EVENTS) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var start: int = maxi(_events.size() - maxi(limit, 0), 0)
	for index: int in range(_events.size() - 1, start - 1, -1):
		output.append(_events[index].duplicate(true))
	return output


func size() -> int:
	return _events.size()


func get_persistent_state() -> Dictionary:
	return {
		"next_event_id": _next_event_id,
		"events": _events.duplicate(true),
	}


func restore_persistent_state(state: Dictionary, current_hour: int) -> bool:
	var raw_events: Variant = state.get("events", [])
	var next_event_id: int = int(state.get("next_event_id", 1))
	if not raw_events is Array or next_event_id < 1:
		return false
	if (raw_events as Array).size() > MAX_EVENTS:
		return false
	var restored: Array[Dictionary] = []
	var previous_id: int = 0
	var previous_hour: int = -1
	for raw_event: Variant in raw_events as Array:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = (raw_event as Dictionary).duplicate(true)
		if not _is_valid_event(event, current_hour):
			return false
		var numeric_id: int = _event_numeric_id(str(event["id"]))
		var world_hour: int = int(event["world_hour"])
		if numeric_id <= previous_id or world_hour < previous_hour:
			return false
		previous_id = numeric_id
		previous_hour = world_hour
		restored.append(event)
	if next_event_id <= previous_id:
		return false
	_events = restored
	_next_event_id = next_event_id
	return true


static func empty_persistent_state() -> Dictionary:
	return {"next_event_id": 1, "events": []}


func _is_valid_event(event: Dictionary, current_hour: int) -> bool:
	var required: Array[String] = [
		"id", "category", "title", "description", "world_hour",
		"importance", "subject_type", "subject_id",
	]
	for field: String in required:
		if not event.has(field):
			return false
	var subject_type: String = str(event["subject_type"])
	var subject_id: String = str(event["subject_id"])
	var world_hour: int = int(event["world_hour"])
	return (
		_event_numeric_id(str(event["id"])) > 0
		and not str(event["category"]).is_empty()
		and not str(event["title"]).is_empty()
		and not str(event["description"]).is_empty()
		and world_hour >= 0
		and world_hour <= current_hour
		and VALID_IMPORTANCE.has(str(event["importance"]))
		and VALID_SUBJECT_TYPES.has(subject_type)
		and (subject_type.is_empty() == subject_id.is_empty())
	)


static func _event_numeric_id(event_id: String) -> int:
	if not event_id.begins_with("world_event:"):
		return -1
	var value: String = event_id.get_slice(":", 1)
	return int(value) if value.is_valid_int() else -1
