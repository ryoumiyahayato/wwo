extends RefCounted
## Committed query projections. Diagnostic truth never enters Context.
const LIMIT: int = 4096
var _state: WeakRef
var enabled: bool = true
var debug_records: Array[Dictionary] = []
var person_records: Array[Dictionary] = []
var dropped: int = 0
var _physical_ids: Dictionary = {}
var _physical_time: float = -INF

func configure(state: RefCounted) -> void:
	_state = weakref(state)

func record(value: Dictionary, holder: String = "") -> void:
	if not enabled:
		return
	var diagnostic: Dictionary = value.duplicate(true)
	diagnostic.view = "DEBUG_TRUTH"
	debug_records.append(diagnostic)
	if debug_records.size() > LIMIT:
		debug_records.pop_front()
		dropped += 1
	if not holder.is_empty():
		var visible: Dictionary = value.duplicate(true)
		visible.view = "PERSON_VISIBLE"
		visible.holder_ref = holder
		person_records.append(visible)
		if person_records.size() > LIMIT:
			person_records.pop_front()
			dropped += 1

func on_gameplay(value: Dictionary) -> void:
	if value.get("view", "") == "PERSON_VISIBLE":
		record(value, str(value.actor_ref))
	else:
		record(value)

func on_observation(value: Dictionary) -> void:
	if not enabled:
		return
	record({"event_id": "observed_" + str(value.id), "effective_time": value.observed_at, "learned_time": null,
		"phase": -1, "kind": "observation_produced", "subject_ref": value.subject_ref, "actor_ref": value.observer_ref,
		"cause_refs": [value.source_ref], "detail": value.duplicate(true)})

func on_message(value: Dictionary) -> void:
	if not enabled:
		return
	var pending: bool = value.status == "PENDING"
	var command: bool = value.kind == "COMMAND"
	var time: float = float(value.sent_at if pending else value.get("processed_at", value.delivery_time))
	var causes: Array[String] = []
	if not pending:
		causes.append(str(value.id) + "_sent")
	elif not command:
		for claim: Dictionary in value.claims:
			causes.append("observed_" + str(claim.id))
	var detail: Dictionary = {"status": value.status, "sender_ref": value.sender_ref, "recipient_ref": value.recipient_ref,
		"delivery_time": value.delivery_time, "outcome": value.get("outcome", {}).duplicate(true)}
	if command:
		detail.command = value.command.duplicate(true)
	elif not pending and value.status == "DELIVERED":
		detail.claims = value.claims.duplicate(true)
	var actor: String = str(value.sender_ref) if pending or command else str(value.recipient_ref)
	# A sender knows what they transmitted. Only the recipient gets report contents.
	record({"event_id": str(value.id) + ("_sent" if pending else "_received"), "effective_time": time,
		"learned_time": time, "phase": 6 if command and not pending else 5,
		"kind": ("command_sent" if pending else "command_feedback") if command else ("report_sent" if pending else "report_received"),
		"subject_ref": value.recipient_ref, "actor_ref": actor, "cause_refs": causes, "detail": detail}, actor)

func physical(value: Dictionary) -> void:
	if not enabled:
		return
	if value.kind == "decision":
		var decision: Dictionary = value.get("result", {})
		if decision.get("status", "") == "REJECTED" and decision.has("context"):
			input(str(decision.person_id), str(decision.id), float(value.time), decision.proposal, decision.context, {"creation_validation": decision.creation_validation})
		return
	if value.kind in ["communication", "gameplay"]:
		return
	if float(value.time) != _physical_time:
		_physical_ids.clear()
		_physical_time = float(value.time)
	var subject: String = str(value.get("unit_id", value.get("area_id", "world")))
	var base: String = "%s@%.9f:%s" % [value.kind, float(value.time), str(value.get("id", subject))]
	var count: int = int(_physical_ids.get(base, 0))
	_physical_ids[base] = count + 1
	# Identity is the logical boundary/kind/subject, not a collection sequence.
	record({"event_id": base + ":%d" % count, "effective_time": value.time, "learned_time": null,
		"phase": -2, "kind": value.kind, "subject_ref": subject,
		"cause_refs": [str(value.get("cause_ref", value.get("id", "shared_kernel")))], "detail": value.duplicate(true)})

func input(actor: String, id: String, at: float, proposal: Dictionary, context: Dictionary, result: Dictionary) -> void:
	if not enabled:
		return
	var claims: Array[String] = []
	for claim: Dictionary in context.get("received_claims", []):
		claims.append(str(claim.entry_id))
	record({"event_id": "submitted_" + id, "effective_time": at, "learned_time": at, "phase": 5,
		"kind": "person_intent", "actor_ref": actor, "subject_ref": actor, "cause_refs": claims,
		"detail": {"proposal": proposal.duplicate(true), "known_claim_refs": claims, "authority_targets": context.get("authority_targets", {}).duplicate(true), "result": result.duplicate(true)}}, actor)

static func before(a: Dictionary, b: Dictionary) -> bool:
	if a.effective_time != b.effective_time:
		return float(a.effective_time) < float(b.effective_time)
	if a.phase != b.phase:
		return int(a.phase) < int(b.phase)
	return str(a.event_id) < str(b.event_id)

func person(actor: String, offset: int = 0, limit: int = 256) -> Dictionary:
	if _state.get_ref().public_pending():
		return _state.get_ref().pending_view()
	if offset < 0 or limit < 1 or limit > 256:
		return {"ok": false, "error": "invalid_page"}
	var selected: Array[Dictionary] = []
	for value: Dictionary in person_records:
		if value.holder_ref == actor:
			selected.append(value.duplicate(true))
	selected.sort_custom(before)
	return {"ok": true, "view": "PERSON_VISIBLE", "holder_ref": actor, "time": _state.get_ref().time,
		"total": selected.size(), "records": selected.slice(offset, mini(offset + limit, selected.size())), "dropped": dropped}

func truth() -> Dictionary:
	if _state.get_ref().public_pending():
		return _state.get_ref().pending_view()
	var ordered: Array[Dictionary] = debug_records.duplicate(true)
	ordered.sort_custom(before)
	return {"ok": true, "view": "DEBUG_TRUTH", "time": _state.get_ref().time, "records": ordered, "dropped": dropped,
		"ordering": "logical time, boundary phase and stable ID; cause_refs define dependencies within a boundary"}
