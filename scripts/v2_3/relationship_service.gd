class_name V23RelationshipService
extends RefCounted
## Indexed, directed dynamic relationships with causal, idempotent changes.

const DIMENSIONS: PackedStringArray = [
	"familiarity", "trust", "affinity", "tension", "obligation", "reciprocity",
]

var relationships: Dictionary = {}
var person_pair_index: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _rules: Dictionary = {}
var _people: Dictionary = {}
var _history_limit: int = 32
var _key_limit: int = 1024


func configure(
	records: Array, rules: Dictionary, people: Array, key_limit: int = 1024
) -> V2LifeLoopResult:
	relationships.clear()
	person_pair_index.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_rules = rules.duplicate(true)
	_people.clear()
	_history_limit = maxi(8, int(rules.get("history_limit_per_relationship", 32)))
	_key_limit = maxi(128, key_limit)
	for raw_person: Variant in people:
		if raw_person is Dictionary:
			var person: Dictionary = (raw_person as Dictionary).duplicate(true)
			_people[str(person.get("person_id", ""))] = person
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			return V2LifeLoopResult.fail("invalid_relationship", "关系记录无效")
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		var result: V2LifeLoopResult = _insert_relation(record)
		if not result.success:
			return result
	return V2LifeLoopResult.ok(
		"动态关系已建立", {"relationship_count": relationships.size()}
	)


func get_relationship(person_id: String, target_id: String) -> Dictionary:
	var relation_id: String = str(person_pair_index.get(_pair_key(person_id, target_id), ""))
	var value: Variant = relationships.get(relation_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func has_relationship(person_id: String, target_id: String) -> bool:
	return person_pair_index.has(_pair_key(person_id, target_id))


func contact_candidates(
	person_id: String, knowledge: KnowledgeService
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_relation_id: Variant in relationships.keys():
		var relation: Dictionary = relationships[raw_relation_id] as Dictionary
		if str(relation.get("person_id", "")) != person_id:
			continue
		var target_id: String = str(relation.get("target_id", ""))
		if not knowledge.knows_person(person_id, target_id):
			continue
		if (relation.get("known_contact_channels", []) as Array).is_empty():
			continue
		var decorated: Dictionary = relation.duplicate(true)
		var target: Dictionary = _people.get(target_id, {}) as Dictionary
		decorated["display_name_zh"] = str(target.get("display_name_zh", target_id))
		decorated["native_name"] = str(target.get("native_name", ""))
		result.append(decorated)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("target_id", "")) < str(right.get("target_id", ""))
	)
	return result


func can_contact(
	person_id: String,
	target_id: String,
	channel: String,
	total_hour: int,
	knowledge: KnowledgeService,
	reply_to_message: bool = false
) -> V2LifeLoopResult:
	if not knowledge.knows_person(person_id, target_id) and not reply_to_message:
		return V2LifeLoopResult.fail(
			"unknown_contact", "当前人物并不认识该联系人", target_id,
			[person_id, target_id]
		)
	var relation: Dictionary = get_relationship(person_id, target_id)
	if relation.is_empty() and not reply_to_message:
		return V2LifeLoopResult.fail(
			"unknown_relationship", "尚未建立可联系关系", target_id,
			[person_id, target_id]
		)
	if (
		not reply_to_message
		and channel not in (relation.get("known_contact_channels", []) as Array)
	):
		return V2LifeLoopResult.fail(
			"channel_unavailable", "当前关系没有该通信渠道", channel,
			[person_id, target_id]
		)
	var last_contact: String = str(relation.get("last_contact_datetime", ""))
	if not last_contact.is_empty():
		var last_hour: int = V2DateTime.total_hour_from_iso(last_contact)
		if total_hour - last_hour < int(_rules.get("contact_cooldown_hours", 24)):
			return V2LifeLoopResult.fail(
				"contact_cooldown", "联系人仍在冷却期",
				"next=%s" % V2DateTime.iso_from_total_hour(
					last_hour + int(_rules.get("contact_cooldown_hours", 24))
				),
				[person_id, target_id]
			)
	return V2LifeLoopResult.ok("联系人和渠道可用", {}, [person_id, target_id])


func apply_interaction(
	person_id: String,
	target_id: String,
	interaction_type: String,
	interaction_id: String,
	total_hour: int,
	cause: String
) -> V2LifeLoopResult:
	var key: String = "relationship:%s:%s" % [
		_pair_key(person_id, target_id), interaction_id,
	]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok(
			"该关系变化已经结算",
			{"relationship": get_relationship(person_id, target_id), "already_settled": true},
			[person_id, target_id]
		)
	var relation: Dictionary = get_relationship(person_id, target_id)
	if relation.is_empty():
		if interaction_type != "introduction":
			return V2LifeLoopResult.fail(
				"unknown_relationship", "关系尚未建立", target_id, [person_id, target_id]
			)
		var create: V2LifeLoopResult = create_relationship(
			person_id, target_id, "newly_introduced", ["local_letter", "face_to_face"]
		)
		if not create.success:
			return create
		relation = create.data.get("relationship", {}) as Dictionary
	var effects: Dictionary = (
		_rules.get("effects", {}) as Dictionary
	).get(interaction_type, {}) as Dictionary
	if effects.is_empty():
		return V2LifeLoopResult.fail(
			"unknown_relationship_effect", "找不到关系变化规则", interaction_type
		)
	var deltas: Dictionary = {}
	for dimension: String in DIMENSIONS:
		var delta: int = int(effects.get(dimension, 0))
		deltas[dimension] = delta
		relation[dimension] = _clamp_dimension(
			dimension, int(relation.get(dimension, 0)) + delta
		)
	relation["last_interaction_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	relation["last_contact_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	var history: Array = relation.get("interaction_history", []) as Array
	history.append({
		"interaction_id": interaction_id,
		"interaction_type": interaction_type,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"cause": cause,
		"deltas": deltas,
		"idempotency_key": key,
	})
	while history.size() > _history_limit:
		history.pop_front()
	relation["interaction_history"] = history
	relationships[str(relation.get("relationship_id", ""))] = relation
	_remember_key(key)
	return V2LifeLoopResult.ok(
		"关系已根据实际互动更新",
		{"relationship": relation.duplicate(true), "deltas": deltas, "cause": cause},
		[person_id, target_id, str(relation.get("relationship_id", ""))]
	)


func create_relationship(
	person_id: String,
	target_id: String,
	status: String,
	channels: Array
) -> V2LifeLoopResult:
	if not _people.has(person_id) or not _people.has(target_id) or person_id == target_id:
		return V2LifeLoopResult.fail(
			"invalid_relationship_people", "关系人物无效",
			"%s -> %s" % [person_id, target_id], [person_id, target_id]
		)
	if has_relationship(person_id, target_id):
		return V2LifeLoopResult.ok(
			"关系已经存在",
			{"relationship": get_relationship(person_id, target_id), "already_exists": true},
			[person_id, target_id]
		)
	var record: Dictionary = {
		"person_id": person_id,
		"target_id": target_id,
		"familiarity": 0,
		"trust": 0,
		"affinity": 0,
		"tension": 0,
		"obligation": 0,
		"reciprocity": 0,
		"last_interaction_datetime": "",
		"last_contact_datetime": "",
		"interaction_history": [],
		"relationship_status": status,
		"known_contact_channels": channels.duplicate(),
	}
	var inserted: V2LifeLoopResult = _insert_relation(record)
	if not inserted.success:
		return inserted
	return V2LifeLoopResult.ok(
		"新关系已建立",
		{"relationship": get_relationship(person_id, target_id)},
		[person_id, target_id]
	)


func set_dimensions(
	person_id: String, target_id: String, values: Dictionary
) -> V2LifeLoopResult:
	var relation: Dictionary = get_relationship(person_id, target_id)
	if relation.is_empty():
		return V2LifeLoopResult.fail(
			"unknown_relationship", "关系不存在", target_id, [person_id, target_id]
		)
	for dimension: String in DIMENSIONS:
		if values.has(dimension):
			relation[dimension] = _clamp_dimension(dimension, int(values[dimension]))
	relationships[str(relation.get("relationship_id", ""))] = relation
	return V2LifeLoopResult.ok("关系数值已调整", {"relationship": relation})


func get_persistent_state() -> Dictionary:
	return {
		"relationships": relationships.duplicate(true),
		"person_pair_index": person_pair_index.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	for field: String in [
		"relationships", "person_pair_index", "processed_idempotency_keys",
	]:
		if not state.get(field, {}) is Dictionary:
			return false
	if not state.get("processed_key_order", []) is Array:
		return false
	var restored: Dictionary = state["relationships"] as Dictionary
	for raw_id: Variant in restored.keys():
		if not restored[raw_id] is Dictionary:
			return false
		var relation: Dictionary = restored[raw_id] as Dictionary
		if str(raw_id) != str(relation.get("relationship_id", "")):
			return false
		for dimension: String in DIMENSIONS:
			var value: int = int(relation.get(dimension, 999999))
			var bounds: Array = (
				(_rules.get("bounds", {}) as Dictionary).get(dimension, []) as Array
			)
			if bounds.size() != 2 or value < int(bounds[0]) or value > int(bounds[1]):
				return false
	relationships = restored.duplicate(true)
	person_pair_index = (state["person_pair_index"] as Dictionary).duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_key_order.clear()
	for raw_key: Variant in state["processed_key_order"] as Array:
		var key: String = str(raw_key)
		if key.is_empty() or not processed_idempotency_keys.has(key):
			return false
		_processed_key_order.append(key)
	return true


func _insert_relation(raw_record: Dictionary) -> V2LifeLoopResult:
	var person_id: String = str(raw_record.get("person_id", ""))
	var target_id: String = str(raw_record.get("target_id", ""))
	if not _people.has(person_id) or not _people.has(target_id) or person_id == target_id:
		return V2LifeLoopResult.fail(
			"invalid_relationship_people", "关系引用未知或相同人物",
			"%s -> %s" % [person_id, target_id], [person_id, target_id]
		)
	var pair: String = _pair_key(person_id, target_id)
	if person_pair_index.has(pair):
		return V2LifeLoopResult.fail(
			"duplicate_relationship", "人物关系重复", pair, [person_id, target_id]
		)
	var relation: Dictionary = raw_record.duplicate(true)
	var relation_id: String = "relationship:%s:%s" % [person_id, target_id]
	relation["relationship_id"] = relation_id
	for dimension: String in DIMENSIONS:
		relation[dimension] = _clamp_dimension(
			dimension, int(relation.get(dimension, 0))
		)
	relation["last_interaction_datetime"] = str(
		relation.get("last_interaction_datetime", "")
	)
	relation["last_contact_datetime"] = str(relation.get("last_contact_datetime", ""))
	relation["interaction_history"] = (
		relation.get("interaction_history", []) as Array
	).duplicate(true)
	relation["known_contact_channels"] = (
		relation.get("known_contact_channels", []) as Array
	).duplicate()
	relationships[relation_id] = relation
	person_pair_index[pair] = relation_id
	return V2LifeLoopResult.ok("关系记录已建立", {"relationship": relation})


func _clamp_dimension(dimension: String, value: int) -> int:
	var bounds: Array = (
		(_rules.get("bounds", {}) as Dictionary).get(dimension, [0, 1000]) as Array
	)
	return clampi(value, int(bounds[0]), int(bounds[1]))


func _remember_key(key: String) -> void:
	processed_idempotency_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > _key_limit:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


static func _pair_key(person_id: String, target_id: String) -> String:
	return "%s|%s" % [person_id, target_id]
