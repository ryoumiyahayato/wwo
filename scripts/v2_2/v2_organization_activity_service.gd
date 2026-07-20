class_name V2OrganizationActivityService
extends RefCounted
## Minimal union participation state, separate from organization politics.

var memberships: Dictionary = {}
var organizations: Dictionary = {}
var positions: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _rules: Dictionary = {}
var _processed_key_order: Array[String] = []

const MAX_PROCESSED_KEYS: int = 128


func configure(records: Array, rules: Dictionary) -> void:
	memberships.clear()
	organizations.clear()
	positions.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_rules = rules.duplicate(true)
	for raw_record: Variant in records:
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		memberships[_key(
			str(record.get("person_id", "")),
			str(record.get("organization_id", ""))
		)] = record


func configure_social_structure(
	organization_records: Array,
	membership_records: Array,
	position_records: Array
) -> V2LifeLoopResult:
	var next_organizations: Dictionary = {}
	for raw_organization: Variant in organization_records:
		if not raw_organization is Dictionary:
			return V2LifeLoopResult.fail(
				"invalid_organization", "组织记录必须是对象"
			)
		var organization: Dictionary = (
			raw_organization as Dictionary
		).duplicate(true)
		var organization_id: String = str(
			organization.get("organization_id", "")
		)
		if organization_id.is_empty() or next_organizations.has(organization_id):
			return V2LifeLoopResult.fail(
				"invalid_organization", "组织 ID 缺失或重复", organization_id
			)
		next_organizations[organization_id] = organization
	var next_memberships: Dictionary = memberships.duplicate(true)
	for raw_membership: Variant in membership_records:
		if not raw_membership is Dictionary:
			return V2LifeLoopResult.fail(
				"invalid_membership", "组织成员记录必须是对象"
			)
		var membership: Dictionary = (
			raw_membership as Dictionary
		).duplicate(true)
		var person_id: String = str(membership.get("person_id", ""))
		var organization_id: String = str(
			membership.get("organization_id", "")
		)
		if (
			person_id.is_empty()
			or not next_organizations.has(organization_id)
		):
			return V2LifeLoopResult.fail(
				"invalid_membership", "组织成员引用无效",
				"%s/%s" % [person_id, organization_id]
			)
		var membership_key: String = _key(person_id, organization_id)
		var previous: Dictionary = next_memberships.get(
			membership_key, {}
		) as Dictionary
		if previous.has("recent_activities"):
			membership["recent_activities"] = (
				previous.get("recent_activities", []) as Array
			).duplicate(true)
		membership["participation"] = clampi(
			int(membership.get(
				"participation", previous.get("participation", 0)
			)),
			0,
			1000
		)
		membership["status"] = str(membership.get("status", "active"))
		membership["recent_activities"] = (
			membership.get("recent_activities", []) as Array
		).duplicate(true)
		next_memberships[membership_key] = membership
	var next_positions: Dictionary = {}
	var held_by_person: Dictionary = {}
	for raw_position: Variant in position_records:
		if not raw_position is Dictionary:
			return V2LifeLoopResult.fail(
				"invalid_position", "组织职位记录必须是对象"
			)
		var position: Dictionary = (
			raw_position as Dictionary
		).duplicate(true)
		var position_id: String = str(position.get("position_id", ""))
		var organization_id: String = str(
			position.get("organization_id", "")
		)
		var holder_id: String = str(position.get("holder_person_id", ""))
		if (
			position_id.is_empty()
			or next_positions.has(position_id)
			or not next_organizations.has(organization_id)
		):
			return V2LifeLoopResult.fail(
				"invalid_position", "组织职位 ID 或组织引用无效", position_id
			)
		if (
			not holder_id.is_empty()
			and not next_memberships.has(_key(holder_id, organization_id))
		):
			return V2LifeLoopResult.fail(
				"position_holder_not_member", "职位持有人不是组织成员",
				position_id, [holder_id, organization_id]
			)
		var unique_person_key: String = "%s|%s" % [
			organization_id, holder_id,
		]
		if (
			not holder_id.is_empty()
			and bool(position.get("unique", true))
			and held_by_person.has(unique_person_key)
		):
			return V2LifeLoopResult.fail(
				"duplicate_position_holder", "人物重复占有唯一职位",
				position_id, [holder_id, organization_id]
			)
		if not holder_id.is_empty():
			held_by_person[unique_person_key] = position_id
		position["history"] = (
			position.get("history", []) as Array
		).duplicate(true)
		next_positions[position_id] = position
	organizations = next_organizations
	memberships = next_memberships
	positions = next_positions
	return V2LifeLoopResult.ok(
		"组织结构已接入现有组织服务",
		{
			"organization_count": organizations.size(),
			"membership_count": memberships.size(),
			"position_count": positions.size(),
		}
	)


func join(
	person_id: String,
	organization_id: String,
	total_hour: int,
	cause_event_id: String
) -> V2LifeLoopResult:
	if not organizations.has(organization_id):
		return V2LifeLoopResult.fail(
			"unknown_organization", "找不到组织", organization_id
		)
	var key: String = "organization:join:%s:%s" % [
		person_id, cause_event_id,
	]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok(
			"加入组织已经结算",
			{"membership": get_membership(person_id, organization_id)}
		)
	var membership_key: String = _key(person_id, organization_id)
	if memberships.has(membership_key):
		var existing: Dictionary = memberships[membership_key] as Dictionary
		if str(existing.get("status", "active")) == "active":
			return V2LifeLoopResult.fail(
				"already_member", "人物已经是组织成员", organization_id
			)
	var membership: Dictionary = {
		"person_id": person_id,
		"organization_id": organization_id,
		"participation": 10,
		"status": "active",
		"joined_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"recent_activities": [],
	}
	memberships[membership_key] = membership
	_remember_processed_key(key)
	return V2LifeLoopResult.ok(
		"人物已加入组织", {"membership": membership.duplicate(true)},
		[person_id, organization_id]
	)


func leave_organization(
	person_id: String,
	organization_id: String,
	total_hour: int,
	cause_event_id: String
) -> V2LifeLoopResult:
	var membership_key: String = _key(person_id, organization_id)
	if not memberships.has(membership_key):
		return V2LifeLoopResult.fail(
			"not_member", "人物不是组织成员", organization_id
		)
	var key: String = "organization:leave:%s:%s" % [
		person_id, cause_event_id,
	]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok("退出组织已经结算")
	for position_id_variant: Variant in positions.keys():
		var position_id: String = str(position_id_variant)
		var position: Dictionary = positions[position_id] as Dictionary
		if (
			str(position.get("organization_id", "")) == organization_id
			and str(position.get("holder_person_id", "")) == person_id
		):
			position["holder_person_id"] = ""
			position["vacated_datetime"] = V2DateTime.iso_from_total_hour(
				total_hour
			)
			positions[position_id] = position
	var membership: Dictionary = memberships[membership_key] as Dictionary
	membership["status"] = "left"
	membership["left_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	memberships[membership_key] = membership
	_remember_processed_key(key)
	return V2LifeLoopResult.ok(
		"人物已退出组织", {"membership": membership.duplicate(true)},
		[person_id, organization_id]
	)


func adjust_participation(
	person_id: String,
	organization_id: String,
	delta: int,
	total_hour: int,
	cause_event_id: String
) -> V2LifeLoopResult:
	var membership_key: String = _key(person_id, organization_id)
	if not memberships.has(membership_key):
		return V2LifeLoopResult.fail(
			"not_member", "人物不是组织成员", organization_id
		)
	var key: String = "organization:participation:%s:%s" % [
		membership_key, cause_event_id,
	]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok(
			"组织参与变化已经结算",
			{"membership": get_membership(person_id, organization_id)}
		)
	var membership: Dictionary = memberships[membership_key] as Dictionary
	membership["participation"] = clampi(
		int(membership.get("participation", 0)) + delta, 0, 1000
	)
	var history: Array = membership.get("recent_activities", []) as Array
	history.append({
		"event_id": cause_event_id,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"participation_delta": delta,
	})
	while history.size() > 12:
		history.pop_front()
	membership["recent_activities"] = history
	memberships[membership_key] = membership
	_remember_processed_key(key)
	return V2LifeLoopResult.ok(
		"组织参与度已变化",
		{"membership": membership.duplicate(true), "delta": delta},
		[person_id, organization_id]
	)


func claim_position(
	person_id: String,
	position_id: String,
	total_hour: int,
	cause_event_id: String
) -> V2LifeLoopResult:
	if not positions.has(position_id):
		return V2LifeLoopResult.fail(
			"unknown_position", "找不到组织职位", position_id
		)
	var position: Dictionary = positions[position_id] as Dictionary
	var organization_id: String = str(position.get("organization_id", ""))
	if not is_active_member(person_id, organization_id):
		return V2LifeLoopResult.fail(
			"position_requires_membership", "争取职位前必须是组织成员",
			position_id, [person_id, organization_id]
		)
	var holder_id: String = str(position.get("holder_person_id", ""))
	if not holder_id.is_empty() and holder_id != person_id:
		return V2LifeLoopResult.fail(
			"position_conflict", "职位已由另一人物占有",
			position_id, [person_id, holder_id]
		)
	var key: String = "organization:position:%s:%s" % [
		position_id, cause_event_id,
	]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok(
			"职位变化已经结算",
			{"position": get_position(position_id)}
		)
	position["holder_person_id"] = person_id
	position["appointed_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	var history: Array = position.get("history", []) as Array
	history.append({
		"person_id": person_id,
		"event_id": cause_event_id,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
	})
	while history.size() > 16:
		history.pop_front()
	position["history"] = history
	positions[position_id] = position
	_remember_processed_key(key)
	return V2LifeLoopResult.ok(
		"人物取得组织职位", {"position": position.duplicate(true)},
		[person_id, organization_id, position_id]
	)


func is_active_member(person_id: String, organization_id: String) -> bool:
	var membership: Dictionary = get_membership(person_id, organization_id)
	return (
		not membership.is_empty()
		and str(membership.get("status", "active")) == "active"
	)


func memberships_for_person(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_membership: Variant in memberships.values():
		var membership: Dictionary = raw_membership as Dictionary
		if str(membership.get("person_id", "")) == person_id:
			result.append(membership.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (
			str(left.get("organization_id", ""))
			< str(right.get("organization_id", ""))
		)
	)
	return result


func get_position(position_id: String) -> Dictionary:
	var value: Variant = positions.get(position_id, {})
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


func organization(organization_id: String) -> Dictionary:
	var value: Variant = organizations.get(organization_id, {})
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


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
	if value.is_empty() or (
		int(value.get("weekday", -1)) != int(_rules.get("weekday_monday_zero", 2))
		or int(value.get("hour", -1)) != int(_rules.get("start_hour", 19))
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
	var duration: int = int(_rules.get("duration_hours", 2))
	var start_hour: int = total_hour - duration + 1
	var timing_check: V2LifeLoopResult = can_attend(
		person_id, organization_id, start_hour, 0
	)
	if not timing_check.success:
		return timing_check
	var date: String = V2DateTime.date_from_total_hour(start_hour)
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
		"datetime": V2DateTime.iso_from_total_hour(start_hour),
		"completed_datetime": V2DateTime.iso_from_total_hour(total_hour + 1),
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
		"organizations": organizations.duplicate(true),
		"positions": positions.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("memberships", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
	):
		return false
	var restored_memberships: Dictionary = state["memberships"] as Dictionary
	for membership_key_variant: Variant in restored_memberships.keys():
		var membership_key: String = str(membership_key_variant)
		var raw_membership: Variant = restored_memberships[membership_key]
		if not raw_membership is Dictionary:
			return false
		var membership: Dictionary = raw_membership as Dictionary
		if membership_key != _key(
			str(membership.get("person_id", "")),
			str(membership.get("organization_id", ""))
		):
			return false
		var participation: int = int(membership.get("participation", -1))
		if participation < 0 or participation > 1000:
			return false
	var restored_organizations: Dictionary = state.get(
		"organizations", organizations
	) as Dictionary
	var restored_positions: Dictionary = state.get(
		"positions", positions
	) as Dictionary
	for position_id_variant: Variant in restored_positions.keys():
		var position_id: String = str(position_id_variant)
		var raw_position: Variant = restored_positions[position_id]
		if not raw_position is Dictionary:
			return false
		var position: Dictionary = raw_position as Dictionary
		if (
			str(position.get("position_id", "")) != position_id
			or not restored_organizations.has(
				str(position.get("organization_id", ""))
			)
		):
			return false
		var holder_id: String = str(position.get("holder_person_id", ""))
		if (
			not holder_id.is_empty()
			and not restored_memberships.has(_key(
				holder_id, str(position.get("organization_id", ""))
			))
		):
			return false
	memberships = restored_memberships.duplicate(true)
	organizations = restored_organizations.duplicate(true)
	positions = restored_positions.duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_key_order.clear()
	var raw_order: Variant = state.get("processed_key_order", [])
	if not raw_order is Array:
		return false
	for raw_key: Variant in raw_order as Array:
		var key: String = str(raw_key)
		if not processed_idempotency_keys.has(key) or key in _processed_key_order:
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
