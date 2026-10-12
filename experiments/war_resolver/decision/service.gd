extends RefCounted
## Explicit opportunities produce intents, then submit to existing domain ports.
const Context = preload("res://experiments/war_resolver/decision/decision_context.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
var _state: State
var _information: RefCounted
var _structure: RefCounted
var _logistics: RefCounted
var _context: Context = Context.new()
var _persons: Dictionary = {}
var _events: Dictionary = {}
var _pending: Dictionary = {}
var _ready: Dictionary = {}
var work: Dictionary = {"decision_events_processed": 0, "decision_contexts_built": 0,
	"knowledge_records_examined_for_decision": 0, "persons_examined": 0, "commands_issued_from_decision": 0,
	"requests_issued_from_decision": 0, "urgent_decision_wakes": 0, "authority_checks": 0,
	"world_truth_reads_for_decision": 0, "future_persons_examined": 0, "superseded_events_processed": 0}

func configure(state: State, information: RefCounted, structure: RefCounted, logistics: RefCounted) -> bool:
	if _state != null or state.decision_port != null or not state.events.is_empty() or state.information_port == null or state.information_port.get_ref() != information or not structure.owns_state(state) or state.logistics_port.get_ref() != logistics:
		return false
	_state = state
	_information = information
	_structure = structure
	_logistics = logistics
	_context.configure(information, structure)
	state.decision_port = weakref(self)
	return true

func enroll(person: String, definition: Dictionary, provider: RefCounted) -> bool:
	if _state == null or _persons.has(person) or not _information._roles.has(person) or not definition.get("cadence") is float or not is_finite(definition.cadence) or float(definition.cadence) <= 0.0 or not definition.get("targets") is Array or definition.targets.size() > 64 or not definition.get("standing_orders") is Dictionary or not definition.get("urgent") is bool or provider == null:
		return false
	for target: Variant in definition.targets:
		if not target is String or not _structure._nodes.has(target):
			return false
	_persons[person] = {"definition": definition.duplicate(true), "provider": provider}
	_ready[person] = _state.time
	return true

func reset_work() -> void:
	for key: String in work:
		work[key] = 0

func schedule(person: String, id: String, due: float) -> Dictionary:
	if _state == null or not _persons.has(person) or id.is_empty() or _events.has(id) or _pending.has(person) or not is_finite(due) or due < _state.time or due < float(_ready[person]):
		return _reject("invalid_opportunity_or_cooldown")
	return _schedule(person, id, due, "")

func _schedule(person: String, id: String, due: float, urgent_message: String) -> Dictionary:
	_events[id] = {"id": id, "person_id": person, "due": due, "status": "PENDING", "urgent_message": urgent_message}
	if not _state.schedule_event("decision_" + id, due, "decision", {"decision_id": id}):
		_events.erase(id)
		return _reject("schedule_failed")
	_pending[person] = id
	return {"ok": true, "id": id, "decision_time": due}

func admit_urgent(person: String, message_id: String) -> Dictionary:
	# Explicit host admission of one received-message wake, never all-message scans.
	if not _persons.has(person) or not _persons[person].definition.urgent or not _information._messages.has(message_id):
		return _reject("unadmitted_urgent_source")
	var message: Dictionary = _information._messages[message_id]
	var id: String = "urgent_" + person + "_" + message_id
	if message.kind != "REPORT" or message.recipient_ref != person or _events.has(id):
		return _reject("urgent_recipient_or_duplicate")
	var due: float = maxf(maxf(float(message.delivery_time) + 5.0, _state.time + 5.0), float(_ready[person]))
	if _pending.has(person) and due >= float(_events[_pending[person]].due):
		return _reject("not_an_earlier_opportunity")
	var previous: String = str(_pending.get(person, ""))
	var result: Dictionary = _schedule(person, id, due, message_id)
	if result.ok:
		if not previous.is_empty():
			_events[previous].status = "SUPERSEDED"
		work.urgent_decision_wakes += 1
	return result

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	if payload.size() != 1 or not payload.get("decision_id") is String or not _events.has(payload.decision_id):
		return false
	var record: Dictionary = _events[payload.decision_id]
	return id == "decision_" + str(record.id) and due == float(record.due) and record.status in ["PENDING", "SUPERSEDED"]

func preview(person: String) -> Dictionary:
	if not _persons.has(person):
		return _reject("unknown_decision_person")
	var next_time: float = float(_events[_pending[person]].due) if _pending.has(person) else -1.0
	return _context.build(person, _state.time, _persons[person].definition, next_time, float(_ready[person]))

func process_event(event: Dictionary) -> Dictionary:
	if float(event.time) != _state.time or not accepts_event(str(event.id), event.payload, float(event.time)):
		return _transition(_reject("invalid_decision_ticket"))
	var record: Dictionary = _events[event.payload.decision_id]
	work.decision_events_processed += 1
	if record.status == "SUPERSEDED":
		record.status = "SKIPPED_SUPERSEDED"
		work.superseded_events_processed += 1
		return _transition(record.duplicate(true))
	var person: String = str(record.person_id)
	_pending.erase(person)
	if not str(record.urgent_message).is_empty() and _information._messages[record.urgent_message].status != "DELIVERED":
		record.status = "SKIPPED_UNDELIVERED_REPORT"
		return _transition(record.duplicate(true))
	work.persons_examined += 1
	var context: Dictionary = preview(person)
	work.decision_contexts_built += 1
	if not context.ok:
		record.status = "REJECTED_CONTEXT"
		return _transition(record.duplicate(true))
	work.knowledge_records_examined_for_decision += context.received_claims.size()
	record.context = context.duplicate(true)
	var proposal: Dictionary = _persons[person].provider.evaluate(context.duplicate(true))
	record.decision_source = _persons[person].provider.source
	record.proposal = proposal.duplicate(true)
	work.authority_checks += 1
	var validated: Dictionary = _validate(person, str(record.id), proposal.intent, context) if proposal.get("intent") is Dictionary else _reject("invalid_intent_shape")
	_ready[person] = _state.time + float(_persons[person].definition.cadence)
	record.status = "ACCEPTED" if validated.ok else "REJECTED"
	record.creation_validation = validated.duplicate(true)
	if validated.ok:
		record.issued_input = _issue(person, str(record.id), proposal.intent)
	return _transition(record.duplicate(true))

func _validate(person: String, id: String, intent: Dictionary, context: Dictionary) -> Dictionary:
	if not intent.get("kind") in context.output_kinds:
		return _reject("role_output_kind_forbidden")
	if intent.kind == "keep":
		return {"ok": true} if intent.size() == 1 else _reject("invalid_keep_intent")
	if intent.kind == "command":
		if intent.size() != 5 or intent.get("command_kind") != context.command_kind or intent.get("target") not in context.command_targets or not intent.get("values") is Dictionary or not intent.get("channel_ref") is String:
			return _reject("invalid_bounded_command_intent")
		return _information.validate_intent(person, {"id": "input_" + id, "kind": intent.command_kind, "target": intent.target, "values": intent.values})
	if intent.kind == "logistics_request":
		if intent.size() != 4 or not context.authority_targets.has(intent.get("target", "")) or intent.get("resource_class") not in _logistics.CLASSES or not (intent.get("quantity") is float or intent.get("quantity") is int) or not is_finite(float(intent.quantity)) or float(intent.quantity) <= 0.0 or float(intent.quantity) > 100.0 or not _logistics._allowed(person, "formation", str(intent.target), 2):
			return _reject("invalid_logistics_intent")
		return {"ok": true}
	if intent.size() != 2 or not intent.get("values") is Dictionary:
		return _reject("invalid_structure_intent")
	var values: Dictionary = intent.values
	if values.size() != 4 or not context.authority_targets.has(values.get("target", "")) or not context.authority_targets.has(values.get("parent", "")) or not (values.get("delay") is float or values.get("delay") is int) or not is_finite(float(values.delay)) or float(values.delay) < 1.0 or not (values.get("duration") is float or values.get("duration") is int) or not is_finite(float(values.duration)) or float(values.duration) <= 0.0:
		return _reject("invalid_future_attachment")
	var request: Dictionary = _structure_request(id, values)
	request.person_id = person
	return _structure._validate(request, false)

func _structure_request(id: String, values: Dictionary) -> Dictionary:
	return {"id": "input_" + id, "kind": "attach", "effective_time": _state.time + float(values.delay),
		"values": {"target": values.target, "parent": values.parent, "until": _state.time + float(values.delay) + float(values.duration)}}

func _issue(person: String, id: String, intent: Dictionary) -> Dictionary:
	if intent.kind == "keep":
		return {"domain": "NONE", "status": "STANDING_ORDER_CONTINUES"}
	work.authority_checks += 1
	var result: Dictionary
	var domain: String
	if intent.kind == "command":
		domain = "COMMUNICATION"
		result = _information.issue_command(person, {"id": "input_" + id, "channel_ref": intent.channel_ref,
			"command": {"id": "input_" + id, "kind": intent.command_kind, "target": intent.target, "values": intent.values}})
		work.commands_issued_from_decision += int(result.ok)
	elif intent.kind == "logistics_request":
		domain = "LOGISTICS"
		result = _logistics.submit(person, {"id": "input_" + id, "kind": "request", "target_kind": "formation", "target": intent.target, "resource_class": intent.resource_class, "quantity": intent.quantity})
		work.requests_issued_from_decision += int(result.ok)
	else:
		domain = "STRUCTURE"
		result = _structure.submit(person, _structure_request(id, intent.values))
		work.requests_issued_from_decision += int(result.ok)
	return {"domain": domain, "id": "input_" + id, "issued_at": _state.time, "result": result}

func result(id: String) -> Dictionary:
	if not _events.has(id):
		return _reject("unknown_decision")
	var record: Dictionary = _events[id].duplicate(true)
	if record.has("issued_input") and record.issued_input.domain == "COMMUNICATION" and _information._messages.has(record.issued_input.id):
		record.command_delivery = {"status": _information._messages[record.issued_input.id].status,
			"processed_at": _information._messages[record.issued_input.id].get("processed_at", -1.0), "outcome": _information._messages[record.issued_input.id].get("outcome", {}).duplicate(true)}
	return record

func snapshot() -> Dictionary:
	return {"events": _events.duplicate(true), "pending": _pending.duplicate(), "ready": _ready.duplicate(), "work": work.duplicate()}

static func _transition(record: Dictionary) -> Dictionary:
	return {"changed": [], "retired": [], "record": record}

static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}
