class_name V2RelationshipProgressService
extends RefCounted
## Minimal deterministic progression for configured, data-driven relationships.

var relationships: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _rules: Dictionary = {}
var _processed_key_order: Array[String] = []

const MAX_PROCESSED_KEYS: int = 128


func configure(records: Array, rules: Dictionary) -> void:
	relationships.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_rules = rules.duplicate(true)
	for raw_record: Variant in records:
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		var key: String = _key(
			str(record.get("person_id", "")), str(record.get("target_id", ""))
		)
		relationships[key] = record


func contact_candidates(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key_variant: Variant in relationships.keys():
		var relation: Dictionary = relationships[key_variant] as Dictionary
		if str(relation.get("person_id", "")) != person_id:
			continue
		result.append(relation.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return contact_display_name(left) < contact_display_name(right)
	)
	return result


func first_contact_target(person_id: String) -> String:
	var candidates: Array[Dictionary] = contact_candidates(person_id)
	return "" if candidates.is_empty() else str(candidates[0].get("target_id", ""))


func contact_display_name(relation: Dictionary) -> String:
	var display_name: String = str(relation.get("target_display_name_zh", ""))
	if display_name.is_empty():
		display_name = str(relation.get("target_native_name", ""))
	if display_name.is_empty():
		display_name = str(relation.get("target_id", "关系人物"))
	return display_name


func target_display_name(person_id: String, target_id: String) -> String:
	var relation: Dictionary = get_relationship(person_id, target_id)
	return contact_display_name(relation) if not relation.is_empty() else target_id


func can_contact(person_id: String, target_id: String, start_hour: int) -> V2LifeLoopResult:
	var relation_key: String = _key(person_id, target_id)
	if not relationships.has(relation_key):
		return V2LifeLoopResult.fail(
			"unknown_relationship", "当前人物并不认识该联系人", relation_key,
			[person_id, target_id]
		)
	var value: Dictionary = V2DateTime.from_total_hour(start_hour)
	if value.is_empty():
		return V2LifeLoopResult.fail(
			"invalid_contact_time", "联系时间无效", str(start_hour), [person_id, target_id]
		)
	var hour: int = int(value["hour"])
	if hour < int(_rules.get("contact_start_hour", 18)) or hour >= int(_rules.get("contact_end_hour", 21)):
		return V2LifeLoopResult.fail(
			"invalid_contact_time", "联系时间必须在 18:00—21:00",
			V2DateTime.iso_from_total_hour(start_hour), [person_id, target_id]
		)
	var relation: Dictionary = relationships[relation_key] as Dictionary
	var last_contact: String = str(relation.get("last_contact_datetime", ""))
	if not last_contact.is_empty():
		var last_hour: int = V2DateTime.total_hour_from_iso(last_contact)
		if last_hour < 0:
			return V2LifeLoopResult.fail(
				"invalid_relationship_state", "关系中的最近联系时间无效",
				last_contact, [person_id, target_id]
			)
		if start_hour - last_hour < int(_rules.get("contact_cooldown_hours", 24)):
			return V2LifeLoopResult.fail(
				"contact_cooldown", "24 小时内不能重复联系",
				"next=%s" % V2DateTime.iso_from_total_hour(
					last_hour + int(_rules.get("contact_cooldown_hours", 24))
				),
				[person_id, target_id]
			)
	return V2LifeLoopResult.ok("可以联系", {}, [person_id, target_id])


func complete_contact(
	person_id: String,
	target_id: String,
	total_hour: int,
	activity_id: String,
	notifications: V2NotificationService
) -> V2LifeLoopResult:
	var allowed: V2LifeLoopResult = can_contact(person_id, target_id, total_hour)
	if not allowed.success:
		return allowed
	var key: String = "person:%s:contact:%s:%s" % [
		person_id, target_id, V2DateTime.iso_from_total_hour(total_hour),
	]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.fail(
			"duplicate_contact", "该次联系已经结算", key, [person_id, target_id]
		)
	var relation_key: String = _key(person_id, target_id)
	var relation: Dictionary = relationships[relation_key] as Dictionary
	relation["familiarity"] = clampi(
		int(relation.get("familiarity", 0)) + int(_rules.get("familiarity_delta", 5)),
		0, 1000
	)
	relation["trust"] = clampi(
		int(relation.get("trust", 0)) + int(_rules.get("trust_delta", 2)),
		0, 1000
	)
	relation["last_contact_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	var interactions: Array = relation.get("recent_interactions", []) as Array
	interactions.append({
		"activity_id": activity_id,
		"datetime": relation["last_contact_datetime"],
		"familiarity_delta": int(_rules.get("familiarity_delta", 5)),
		"trust_delta": int(_rules.get("trust_delta", 2)),
	})
	while interactions.size() > 12:
		interactions.pop_front()
	relation["recent_interactions"] = interactions
	relationships[relation_key] = relation
	_remember_processed_key(key)
	var target_name: String = contact_display_name(relation)
	notifications.add(
		"personal", "event", "联系完成",
		"与%s联系后熟悉度 +%d、信任 +%d" % [
			target_name,
			int(_rules.get("familiarity_delta", 5)),
			int(_rules.get("trust_delta", 2)),
		],
		total_hour, "contact:%s:%s" % [person_id, target_id], [person_id, target_id]
	)
	return V2LifeLoopResult.ok(
		"已联系%s" % target_name,
		{"relationship": relation.duplicate(true), "idempotency_key": key},
		[person_id, target_id]
	)


func get_relationship(person_id: String, target_id: String) -> Dictionary:
	var value: Variant = relationships.get(_key(person_id, target_id), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func get_persistent_state() -> Dictionary:
	return {
		"relationships": relationships.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("relationships", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
	):
		return false
	var restored_relationships: Dictionary = state["relationships"] as Dictionary
	for relation_key_variant: Variant in restored_relationships.keys():
		var relation_key: String = str(relation_key_variant)
		var raw_relation: Variant = restored_relationships[relation_key]
		if not raw_relation is Dictionary:
			return false
		var relation: Dictionary = raw_relation as Dictionary
		var person_id: String = str(relation.get("person_id", ""))
		var target_id: String = str(relation.get("target_id", ""))
		if relation_key != _key(person_id, target_id) or person_id.is_empty() or target_id.is_empty():
			return false
		if contact_display_name(relation).is_empty():
			return false
		for field: String in ["familiarity", "trust"]:
			var value: int = int(relation.get(field, -1))
			if value < 0 or value > 1000:
				return false
		var last_contact: String = str(relation.get("last_contact_datetime", ""))
		if not last_contact.is_empty() and V2DateTime.total_hour_from_iso(last_contact) < 0:
			return false
		var interactions: Variant = relation.get("recent_interactions", [])
		if not interactions is Array or (interactions as Array).size() > 12:
			return false
		for raw_interaction: Variant in interactions as Array:
			if not raw_interaction is Dictionary:
				return false
			var interaction: Dictionary = raw_interaction as Dictionary
			if (
				str(interaction.get("activity_id", "")).is_empty()
				or V2DateTime.total_hour_from_iso(str(interaction.get("datetime", ""))) < 0
			):
				return false
	var processed: Dictionary = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	var raw_order: Variant = state.get("processed_key_order", [])
	if not raw_order is Array:
		return false
	var restored_order: Array[String] = []
	for raw_key: Variant in raw_order as Array:
		var key: String = str(raw_key)
		if key.is_empty() or not processed.has(key) or key in restored_order:
			return false
		restored_order.append(key)
	if restored_order.size() != processed.size() or restored_order.size() > MAX_PROCESSED_KEYS:
		return false
	relationships = restored_relationships.duplicate(true)
	processed_idempotency_keys = processed
	_processed_key_order = restored_order
	return true


func _remember_processed_key(key: String) -> void:
	processed_idempotency_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > MAX_PROCESSED_KEYS:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


static func _key(person_id: String, target_id: String) -> String:
	return "%s|%s" % [person_id, target_id]
