class_name V2NotificationService
extends RefCounted
## Bounded, category-aware and aggregating V2.2 notification history.

var notifications: Array[Dictionary] = []
var _next_sequence: int = 1
var _maximum_entries: int = 160


func configure(maximum_entries: int) -> void:
	_maximum_entries = maxi(16, maximum_entries)


func add(
	category: String,
	kind: String,
	title: String,
	detail: String,
	total_hour: int,
	aggregation_key: String,
	entity_ids: Array[String] = []
) -> Dictionary:
	var date: String = V2DateTime.date_from_total_hour(total_hour)
	for index: int in range(notifications.size() - 1, -1, -1):
		var existing: Dictionary = notifications[index]
		if (
			str(existing.get("aggregation_key", "")) == aggregation_key
			and str(existing.get("date", "")) == date
		):
			existing["group_count"] = int(existing.get("group_count", 1)) + 1
			existing["detail"] = detail
			existing["total_hour"] = total_hour
			existing["datetime"] = V2DateTime.iso_from_total_hour(total_hour)
			existing["read"] = false
			notifications[index] = existing
			return existing.duplicate(true)
	var record: Dictionary = {
		"notification_id": "notification:v2_2:%d" % _next_sequence,
		"category": category,
		"kind": kind,
		"title": title,
		"detail": detail,
		"total_hour": total_hour,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"date": date,
		"aggregation_key": aggregation_key,
		"group_count": 1,
		"read": false,
		"affected_entity_ids": entity_ids.duplicate(),
	}
	_next_sequence += 1
	notifications.append(record)
	while notifications.size() > _maximum_entries:
		notifications.pop_front()
	return record.duplicate(true)


func latest(limit: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(notifications.size() - 1, maxi(-1, notifications.size() - limit - 1), -1):
		result.append(notifications[index].duplicate(true))
	return result


func unread_count() -> int:
	var count: int = 0
	for record: Dictionary in notifications:
		if not bool(record.get("read", false)):
			count += 1
	return count


func get_persistent_state() -> Dictionary:
	return {
		"next_sequence": _next_sequence,
		"maximum_entries": _maximum_entries,
		"notifications": notifications.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if not state.get("notifications", []) is Array:
		return false
	var next_sequence: int = int(state.get("next_sequence", 0))
	if next_sequence < 1:
		return false
	var restored: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_record: Variant in state["notifications"] as Array:
		if not raw_record is Dictionary:
			return false
		var record: Dictionary = raw_record as Dictionary
		var record_id: String = str(record.get("notification_id", ""))
		if record_id.is_empty() or seen.has(record_id):
			return false
		seen[record_id] = true
		restored.append(record.duplicate(true))
	_next_sequence = next_sequence
	_maximum_entries = maxi(16, int(state.get("maximum_entries", 160)))
	notifications = restored
	return true
