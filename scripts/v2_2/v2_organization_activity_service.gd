class_name V2OrganizationActivityService
extends RefCounted
## Minimal union participation state, separate from organization politics.

var memberships: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _rules: Dictionary = {}
var _processed_key_order: Array[String] = []

const MAX_PROCESSED_KEYS: int = 128


func configure(records: Array, rules: Dictionary) -> void:
	memberships.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_rules = rules.duplicate(true)
	for raw_record: Variant in records:
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		memberships[_key(
			str(record.get("person_id", "")),
			str(record.get("organization_id", ""))
		)] = record


func can_attend(
	person_id: String,
	organization_id: String,
	start_hour: int,
	fatigue: int
) -> V2LifeLoopResult:
	if not memberships.has(_key(person_id, organization_id)):
		return V2LifeLoopResult.fail(
			"not_union_member", "当前人物不是该工会成员", organization_id,
			[person_id, organization_id]
		)
	var value: Dictionary = V2DateTime.from_total_hour(start_hour)
	if (
		int(value["weekday"]) != int(_rules.get("weekday_monday_zero", 2))
		or int(value["hour"]) != int(_rules.get("start_hour", 19))
	):
		return V2LifeLoopResult.fail(
			"invalid_union_time", "工会例会只能安排在星期三 19:00",
			V2DateTime.iso_from_total_hour(start_hour), [person_id, organization_id]
		)
	if fatigue >= 950:
		return V2LifeLoopResult.fail(
			"fatigue_too_high", "疲劳达到 950，不能参加工会活动",
			"fatigue=%d" % fatigue, [person_id, organization_id]
		)
	return V2LifeLoopResult.ok("可以参加工会例会", {}, [person_id, organization_id])


func complete_activity(
	person_id: String,
	organization_id: String,
	total_hour: int,
	activity_id: String,
	notifications: V2NotificationService
) -> V2LifeLoopResult:
	var date: String = V2DateTime.date_from_total_hour(total_hour)
	var event_id: String = str(_rules.get("event_id", "union_event"))
	var key: String = "person:%s:union:%s:%s" % [person_id, event_id, date]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.fail(
			"duplicate_union_activity", "该次工会活动已经结算", key,
			[person_id, organization_id]
		)
	var membership_key: String = _key(person_id, organization_id)
	if not memberships.has(membership_key):
		return V2LifeLoopResult.fail(
			"not_union_member", "当前人物不是该工会成员", membership_key,
			[person_id, organization_id]
		)
	var membership: Dictionary = memberships[membership_key] as Dictionary
	var delta: int = int(_rules.get("participation_delta", 5))
	membership["participation"] = clampi(
		int(membership.get("participation", 0)) + delta, 0, 1000
	)
	var history: Array = membership.get("recent_activities", []) as Array
	history.append({
		"activity_id": activity_id,
		"event_id": event_id,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"participation_delta": delta,
	})
	while history.size() > 12:
		history.pop_front()
	membership["recent_activities"] = history
	memberships[membership_key] = membership
	_remember_processed_key(key)
	notifications.add(
		"organization", "event", "工会活动完成",
		"工会参与度 +%d" % delta, total_hour,
		"union_activity:%s" % person_id, [person_id, organization_id]
	)
	return V2LifeLoopResult.ok(
		"工会例会已完成",
		{"membership": membership.duplicate(true), "idempotency_key": key},
		[person_id, organization_id]
	)


func get_membership(person_id: String, organization_id: String) -> Dictionary:
	var value: Variant = memberships.get(_key(person_id, organization_id), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func get_persistent_state() -> Dictionary:
	return {
		"memberships": memberships.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("memberships", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
	):
		return false
	memberships = (state["memberships"] as Dictionary).duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_key_order.clear()
	var raw_order: Variant = state.get("processed_key_order", [])
	if not raw_order is Array:
		return false
	for raw_key: Variant in raw_order as Array:
		var key: String = str(raw_key)
		if not processed_idempotency_keys.has(key):
			return false
		_processed_key_order.append(key)
	if _processed_key_order.size() != processed_idempotency_keys.size():
		return false
	return true


func _remember_processed_key(key: String) -> void:
	processed_idempotency_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > MAX_PROCESSED_KEYS:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


static func _key(person_id: String, organization_id: String) -> String:
	return "%s|%s" % [person_id, organization_id]
