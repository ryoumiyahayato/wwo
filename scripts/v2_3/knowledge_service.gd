class_name KnowledgeService
extends RefCounted
## Person-scoped knowledge records separated from authoritative domain state.

const STATUSES: PackedStringArray = [
	"reported", "confirmed", "rumor", "outdated", "contradicted",
]

var records: Dictionary = {}
var person_index: Dictionary = {}
var subject_index: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _rules: Dictionary = {}
var _next_sequence: int = 1
var _history_limit: int = 256


func configure(
	people: Array,
	rules: Dictionary,
	locations: SpatialLocationService,
	start_hour: int
) -> void:
	records.clear()
	person_index.clear()
	subject_index.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_rules = rules.duplicate(true)
	_next_sequence = 1
	_history_limit = maxi(32, int(rules.get("history_limit_per_person", 256)))
	var sorted_people: Array[Dictionary] = []
	for raw_person: Variant in people:
		if raw_person is Dictionary:
			sorted_people.append((raw_person as Dictionary).duplicate(true))
	sorted_people.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("person_id", "")) < str(right.get("person_id", ""))
	)
	for person: Dictionary in sorted_people:
		var person_id: String = str(person.get("person_id", ""))
		person_index[person_id] = []
		subject_index[person_id] = {}
		_seed_identity(person_id, person, start_hour, "self")
		var known_ids: Array[String] = []
		for raw_known_id: Variant in person.get("known_person_ids", []) as Array:
			known_ids.append(str(raw_known_id))
		known_ids.sort()
		for known_id: String in known_ids:
			var known_person: Dictionary = _person_by_id(sorted_people, known_id)
			if not known_person.is_empty():
				_seed_identity(person_id, known_person, start_hour, "initial_relationship")
		for location: Dictionary in locations.known_locations(person_id):
			record_fact(
				person_id,
				"location_identity:%s" % str(location.get("location_id", "")),
				str(location.get("location_id", "")),
				"location_identity",
				{"display_name": str(location.get("display_name", ""))},
				"scenario_initialization",
				"direct_observation",
				start_hour,
				int((_rules.get("confidence", {}) as Dictionary).get("direct_observation", 1000)),
				"confirmed",
				-1,
				"",
				"knowledge:%s:location:%s" % [
					person_id, str(location.get("location_id", "")),
				]
			)


func record_fact(
	person_id: String,
	fact_id: String,
	subject_id: String,
	fact_type: String,
	claim: Variant,
	source_id: String,
	source_kind: String,
	acquired_hour: int,
	confidence: int,
	status: String = "reported",
	expires_hour: int = -1,
	related_message_id: String = "",
	idempotency_key: String = ""
) -> V2LifeLoopResult:
	if not person_index.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到认知主体", person_id, [person_id])
	if fact_id.is_empty() or subject_id.is_empty() or source_id.is_empty():
		return V2LifeLoopResult.fail(
			"invalid_knowledge", "知识必须包含事实、主体和来源", fact_id,
			[person_id, subject_id]
		)
	if status not in STATUSES:
		return V2LifeLoopResult.fail("invalid_knowledge_status", "知识状态无效", status)
	var key: String = idempotency_key
	if key.is_empty():
		key = "knowledge:%s:%s:%s" % [person_id, fact_id, source_id]
	if processed_idempotency_keys.has(key):
		var existing_id: String = str(processed_idempotency_keys[key])
		return V2LifeLoopResult.ok(
			"该来源的知识已经记录",
			{"knowledge": get_record(existing_id), "already_recorded": true},
			[person_id, existing_id]
		)
	var contradictions: Array[String] = []
	for existing: Dictionary in records_for_subject(person_id, subject_id):
		if (
			str(existing.get("fact_id", "")) == fact_id
			and existing.get("claim") != claim
			and str(existing.get("status", "")) != "outdated"
		):
			contradictions.append(str(existing.get("knowledge_id", "")))
	if not contradictions.is_empty():
		status = "contradicted"
		for existing_id: String in contradictions:
			var existing: Dictionary = records[existing_id] as Dictionary
			existing["status"] = "contradicted"
			var links: Array = existing.get("contradicted_fact_ids", []) as Array
			if fact_id not in links:
				links.append(fact_id)
			existing["contradicted_fact_ids"] = links
			records[existing_id] = existing
	var knowledge_id: String = "knowledge:v2_3:%07d" % _next_sequence
	_next_sequence += 1
	var record: Dictionary = {
		"knowledge_id": knowledge_id,
		"person_id": person_id,
		"fact_id": fact_id,
		"subject_id": subject_id,
		"fact_type": fact_type,
		"claim": _copy_variant(claim),
		"source_id": source_id,
		"source_kind": source_kind,
		"acquired_datetime": V2DateTime.iso_from_total_hour(acquired_hour),
		"observed_datetime": V2DateTime.iso_from_total_hour(acquired_hour),
		"confidence": clampi(confidence, 0, 1000),
		"freshness": "current",
		"status": status,
		"expires_datetime": (
			"" if expires_hour < 0 else V2DateTime.iso_from_total_hour(expires_hour)
		),
		"contradicted_fact_ids": contradictions,
		"related_message_id": related_message_id,
		"visibility": "person",
		"idempotency_key": key,
	}
	records[knowledge_id] = record
	var person_records: Array = person_index[person_id] as Array
	person_records.append(knowledge_id)
	person_index[person_id] = person_records
	var subjects: Dictionary = subject_index[person_id] as Dictionary
	var subject_records: Array = subjects.get(subject_id, []) as Array
	subject_records.append(knowledge_id)
	subjects[subject_id] = subject_records
	subject_index[person_id] = subjects
	_remember_key(key, knowledge_id)
	_trim_person(person_id)
	return V2LifeLoopResult.ok(
		"人物获得新知识", {"knowledge": record.duplicate(true)},
		[person_id, subject_id, knowledge_id]
	)


func expire_due(total_hour: int) -> int:
	var changed: int = 0
	for raw_id: Variant in records.keys():
		var knowledge_id: String = str(raw_id)
		var record: Dictionary = records[knowledge_id] as Dictionary
		if str(record.get("status", "")) in ["outdated", "contradicted"]:
			continue
		var expires: String = str(record.get("expires_datetime", ""))
		if expires.is_empty():
			continue
		var expires_hour: int = V2DateTime.total_hour_from_iso(expires)
		if expires_hour >= 0 and total_hour >= expires_hour:
			record["status"] = "outdated"
			record["freshness"] = "expired"
			records[knowledge_id] = record
			changed += 1
	return changed


func confirm(knowledge_id: String, total_hour: int) -> V2LifeLoopResult:
	if not records.has(knowledge_id):
		return V2LifeLoopResult.fail(
			"unknown_knowledge", "找不到知识记录", knowledge_id, [knowledge_id]
		)
	var record: Dictionary = records[knowledge_id] as Dictionary
	record["status"] = "confirmed"
	record["confidence"] = 1000
	record["observed_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	record["freshness"] = "current"
	records[knowledge_id] = record
	return V2LifeLoopResult.ok("知识已确认", {"knowledge": record}, [knowledge_id])


func knows_person(person_id: String, target_id: String) -> bool:
	for record: Dictionary in records_for_subject(person_id, target_id):
		if (
			str(record.get("fact_type", "")) == "person_identity"
			and str(record.get("status", "")) not in ["outdated"]
		):
			return true
	return false


func records_for_person(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id: Variant in person_index.get(person_id, []) as Array:
		var knowledge_id: String = str(raw_id)
		if records.has(knowledge_id):
			result.append((records[knowledge_id] as Dictionary).duplicate(true))
	return result


func records_for_subject(person_id: String, subject_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var subjects: Dictionary = subject_index.get(person_id, {}) as Dictionary
	for raw_id: Variant in subjects.get(subject_id, []) as Array:
		var knowledge_id: String = str(raw_id)
		if records.has(knowledge_id):
			result.append((records[knowledge_id] as Dictionary).duplicate(true))
	return result


func get_record(knowledge_id: String) -> Dictionary:
	var value: Variant = records.get(knowledge_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func get_persistent_state() -> Dictionary:
	return {
		"records": records.duplicate(true),
		"person_index": person_index.duplicate(true),
		"subject_index": subject_index.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	for field: String in [
		"records", "person_index", "subject_index", "processed_idempotency_keys",
	]:
		if not state.get(field, {}) is Dictionary:
			return false
	if not state.get("processed_key_order", []) is Array or int(state.get("next_sequence", 0)) < 1:
		return false
	var restored_records: Dictionary = state["records"] as Dictionary
	var seen_keys: Dictionary = {}
	for raw_id: Variant in restored_records.keys():
		var knowledge_id: String = str(raw_id)
		if not restored_records[knowledge_id] is Dictionary:
			return false
		var record: Dictionary = restored_records[knowledge_id] as Dictionary
		var key: String = str(record.get("idempotency_key", ""))
		if (
			knowledge_id != str(record.get("knowledge_id", ""))
			or str(record.get("status", "")) not in STATUSES
			or key.is_empty() or seen_keys.has(key)
			or int(record.get("confidence", -1)) < 0
			or int(record.get("confidence", -1)) > 1000
		):
			return false
		seen_keys[key] = true
	var restored_person_index: Dictionary = state["person_index"] as Dictionary
	for raw_person_id: Variant in restored_person_index.keys():
		if not restored_person_index[raw_person_id] is Array:
			return false
		for raw_id: Variant in restored_person_index[raw_person_id] as Array:
			if not restored_records.has(str(raw_id)):
				return false
	records = restored_records.duplicate(true)
	person_index = restored_person_index.duplicate(true)
	subject_index = (state["subject_index"] as Dictionary).duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_key_order.clear()
	for raw_key: Variant in state["processed_key_order"] as Array:
		var key: String = str(raw_key)
		if key.is_empty() or not processed_idempotency_keys.has(key):
			return false
		_processed_key_order.append(key)
	_next_sequence = int(state["next_sequence"])
	return true


func _seed_identity(
	owner_id: String, subject: Dictionary, start_hour: int, source: String
) -> void:
	var target_id: String = str(subject.get("person_id", ""))
	record_fact(
		owner_id,
		"person_identity:%s" % target_id,
		target_id,
		"person_identity",
		{
			"display_name_zh": str(subject.get("display_name_zh", "")),
			"native_name": str(subject.get("native_name", "")),
			"role": str(subject.get("role", "")),
		},
		source,
		"direct_observation",
		start_hour,
		1000,
		"confirmed",
		-1,
		"",
		"knowledge:%s:identity:%s:%s" % [owner_id, target_id, source]
	)


func _remember_key(key: String, knowledge_id: String) -> void:
	processed_idempotency_keys[key] = knowledge_id
	_processed_key_order.append(key)
	while _processed_key_order.size() > _history_limit * maxi(1, person_index.size()):
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


func _trim_person(person_id: String) -> void:
	var ids: Array = person_index[person_id] as Array
	while ids.size() > _history_limit:
		var removed_id: String = str(ids.pop_front())
		if not records.has(removed_id):
			continue
		var removed: Dictionary = records[removed_id] as Dictionary
		var subject_id: String = str(removed.get("subject_id", ""))
		var subjects: Dictionary = subject_index[person_id] as Dictionary
		var subject_ids: Array = subjects.get(subject_id, []) as Array
		subject_ids.erase(removed_id)
		subjects[subject_id] = subject_ids
		subject_index[person_id] = subjects
		records.erase(removed_id)
	person_index[person_id] = ids


static func _person_by_id(people: Array[Dictionary], person_id: String) -> Dictionary:
	for person: Dictionary in people:
		if str(person.get("person_id", "")) == person_id:
			return person
	return {}


static func _copy_variant(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
