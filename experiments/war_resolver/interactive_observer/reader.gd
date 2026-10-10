extends RefCounted
## Received Knowledge and own feedback only. No snapshot or leaf read.
const PAGE: int = 20
const HISTORY: int = 256
var actor: String = ""
var env: Dictionary
var known_map: Dictionary = {}
var timeline: Array[Dictionary] = []
var cursor: int = 0
var dropped: int = 0
var work: Dictionary = {"knowledge_records": 0, "personal_records": 0, "timeline_records": 0, "receipt_records": 0,
	"unit_table_scans": 0, "world_exports": 0, "materializations": 0, "reads": 0}

func configure(world: Dictionary, person: String) -> void:
	env = world.duplicate()
	actor = person
	known_map = env.gameplay._known[actor].duplicate(true)
	# One construction seed from the same lawful bounded API; not DEBUG_TRUTH.
	for claim: Dictionary in env.information.knowledge(actor, "", "", "", PAGE).entries:
		_add({"kind": "report_received", "event_id": claim.entry_id, "effective_time": claim.observed_at,
			"learned_time": claim.received_at, "source_ref": claim.source_ref, "claim": claim.duplicate(true)})
	for message: Dictionary in env.information.outbox(actor, PAGE).messages:
		if message.kind == "COMMAND":
			on_message(message)
	env.information.message_transition.connect(on_message)
	env.gameplay.transition.connect(on_person)

func _add(record: Dictionary) -> void:
	record.view = "PERSON_VISIBLE"
	record.holder_ref = actor
	record.cursor = cursor
	cursor += 1
	timeline.append(record)
	if timeline.size() > HISTORY:
		timeline.pop_front()
		dropped += 1

func on_message(message: Dictionary) -> void:
	if message.kind == "REPORT" and message.status == "DELIVERED" and message.recipient_ref == actor:
		for index: int in range(message.claims.size()):
			var claim: Dictionary = message.claims[index]
			_add({"kind": "report_received", "event_id": str(message.id) + ":%d" % index,
				"effective_time": claim.observed_at, "learned_time": message.delivery_time,
				"source_ref": claim.source_ref, "claim": claim.duplicate(true)})
	elif message.kind == "COMMAND" and message.sender_ref == actor:
		_add({"kind": "command_feedback", "event_id": message.id, "effective_time": message.get("processed_at", message.sent_at),
			"learned_time": message.get("processed_at", message.sent_at), "status": message.status,
			"sent_at": message.sent_at, "delivery_time": message.delivery_time,
			"accepted": message.get("outcome", {}).get("ok", null), "reason": safe_reason(message.get("outcome", {}).get("reason", ""))})

func on_person(record: Dictionary) -> void:
	if record.get("view", "") == "PERSON_VISIBLE" and record.get("actor_ref", "") == actor:
		_add(record.duplicate(true))

func own_input(id: String, time: float, choice: Dictionary) -> void:
	_add({"kind": "person_input", "event_id": id, "effective_time": time, "learned_time": time, "intent": choice.duplicate(true)})

static func safe_reason(reason: String) -> String:
	return reason if reason in ["wrong_owner_or_layer", "executed_existing_role_input", "person_incapacitated", "input_not_due"] else ("intent_not_admitted" if not reason.is_empty() else "")

func events(before: int = -1) -> Dictionary:
	var oldest: int = cursor - timeline.size()
	var end: int = cursor if before == -1 else mini(before, cursor)
	if before < -1 or before > cursor:
		return {"ok": false, "error": "invalid_cursor"}
	var start: int = maxi(oldest, end - PAGE)
	var records: Array[Dictionary] = []
	for index: int in range(start, maxi(start, end)):
		work.timeline_records += 1
		records.append(timeline[index - oldest].duplicate(true))
	return {"ok": true, "records": records, "next_before": start if start > oldest else -1,
		"dropped": dropped, "cursor_lost": end < oldest, "ordering": "cursor is a page position; use learned/effective time and cause_refs for facts"}

func view(receipts: Array, focus: String = "") -> Dictionary:
	work.reads += 1
	var knowledge: Dictionary = env.information.knowledge(actor, "", "", "", PAGE)
	work.knowledge_records += knowledge.entries.size()
	if not focus.is_empty() and focus != actor:
		var subject: String = {"node_unit_000": "unit_000", "node_unit_001": "unit_001"}.get(focus, focus)
		var selected: Array[Dictionary] = []
		for claim: Dictionary in knowledge.entries:
			if claim.subject_ref == subject:
				selected.append(claim)
		knowledge.entries = selected
		knowledge.focus_scope = "filter within the selected bounded page; no global search"
	var body: Dictionary = {"state": "UNKNOWN", "reason": "no_personal_overlay_for_this_officer"}
	if env.gameplay.participants._units.has(actor):
		body = env.gameplay.participants.view(actor)
		work.personal_records += 1
	work.receipt_records += receipts.size()
	return {"view": "PERSON_VISIBLE", "person_id": actor, "role": env.people[actor].role, "time": env.state.time,
		"personal": body, "reports": knowledge, "events": events(), "own_receipts": receipts.duplicate(true),
		"known_map": known_map.duplicate(true), "focus": focus,
		"attemptable": ["wait", "take_cover"] if env.people[actor].role == "ordinary_soldier" else ["hold", "advance", "withdraw", "cancel"],
		"known_targets": ["node_unit_000"] if actor == "squad" else (["node_unit_000", "node_unit_001"] if actor == "platoon" else (["blue_platoon", "blue_destination", "blue_company"] if actor == "company" else [])),
		"input_note": "attempts still require existing cooldown, scope, delivery and execution checks"}

func reports(before: int = -1) -> Dictionary:
	var result: Dictionary = env.information.knowledge(actor, "", "", "", PAGE, before)
	work.knowledge_records += result.get("entries", []).size()
	return result

func dispose() -> void:
	env.information.message_transition.disconnect(on_message)
	env.gameplay.transition.disconnect(on_person)
	env.clear()
