extends RefCounted
## Military contract only. Knowledge is received claims, never a truth snapshot.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const FACTS: Array[String] = ["position", "status", "ammunition", "fuel", "readiness"]
const MAX_CLAIMS: int = 8
const MAX_QUERY: int = 64
var _state: State
var _lod: RefCounted
var _structure: RefCounted
var _logistics: RefCounted
var _roles: Dictionary = {}
var _sources: Dictionary = {}
var _channels: Dictionary = {}
var _observations: Dictionary = {}
var _messages: Dictionary = {}
var _report_heap: Array[Dictionary] = []
var _knowledge: Dictionary = {}
var _subjects: Dictionary = {}
var _inboxes: Dictionary = {}
var _outboxes: Dictionary = {}
var _entry_ids: Dictionary = {}
var _next_issue: Dictionary = {}
var _token: RefCounted = RefCounted.new()
var _gate: String = ""
var _actor: String = ""
var work: Dictionary = {"messages_admitted": 0, "messages_delivered": 0, "messages_failed": 0,
	"knowledge_records_examined": 0, "knowledge_records_updated": 0, "future_messages_examined": 0,
	"communication_events_processed": 0, "command_deliveries_processed": 0,
	"leaves_materialized_for_information": 0, "leaves_materialized_for_commands": 0,
	"authority_revalidations": 0, "report_heap_comparisons": 0, "command_heap_comparisons": 0,
	"fact_records_examined": 0}

func configure(state: State, lod: RefCounted, structure: RefCounted, logistics: RefCounted,
		roles: Dictionary, sources: Dictionary, channels: Dictionary) -> bool:
	if _state != null or state.information_port != null or not lod.owns_state(state) or not structure.owns_state(state) or state.logistics_port == null or state.logistics_port.get_ref() != logistics or roles.is_empty():
		return false
	for person: String in roles:
		if not structure._people.has(person) or roles[person]._state != state or roles[person]._player_id != person or not roles[person]._binding_current():
			return false
	for id: String in sources:
		if not sources[id] is Dictionary:
			return false
		var source: Dictionary = sources[id]
		if not roles.has(source.get("observer_ref", "")) or not structure.active(str(source.get("scope_ref", ""))) or source.get("origin") not in ["DIRECT", "SUBORDINATE_REPORT", "HQ_REPORT", "EXTERNAL"] or not _quality(source.get("quality")) or not _positive(source.get("precision_km")) or not source.get("fact_kinds") is Array:
			return false
		for fact: String in source.fact_kinds:
			if fact not in FACTS:
				return false
	for id: String in channels:
		if not channels[id] is Dictionary:
			return false
		var channel: Dictionary = channels[id]
		if not channel.get("senders") is Array or not channel.get("recipients") is Array or not channel.get("available") is bool or not _quality(channel.get("quality")) or not _nonnegative(channel.get("latency")) or not structure.active(str(channel.get("command_scope", ""))):
			return false
		for person: String in channel.senders + channel.recipients:
			if not roles.has(person):
				return false
	_state = state
	_lod = lod
	_structure = structure
	_logistics = logistics
	_roles = roles.duplicate()
	_sources = sources.duplicate(true)
	_channels = channels.duplicate(true)
	for person: String in roles:
		_knowledge[person] = []
		_subjects[person] = {}
		_inboxes[person] = []
		_outboxes[person] = []
	_state.information_port = weakref(self)
	return true

func reset_work() -> void:
	for key: String in work:
		work[key] = 0

func _source_allowed(actor: String, source_id: String, subject_kind: String, subject: String, fact: String) -> bool:
	if not _sources.has(source_id) or not _roles.has(actor) or subject_kind not in ["unit", "formation"]:
		return false
	var source: Dictionary = _sources[source_id]
	if source.observer_ref != actor or fact not in source.fact_kinds:
		return false
	var node_id: String = str(_structure._unit_nodes.get(subject, "")) if subject_kind == "unit" else subject
	return _structure._contains(str(source.scope_ref), node_id)

func observe(actor: String, request: Dictionary) -> Dictionary:
	if request.size() != 5 or not _keys(request, ["id", "source_ref", "subject_kind", "subject_ref", "fact_kind"]) or not request.get("id") is String or str(request.id).is_empty() or _observations.has(request.id) or not _source_allowed(actor, str(request.get("source_ref", "")), str(request.get("subject_kind", "")), str(request.get("subject_ref", "")), str(request.get("fact_kind", ""))):
		return _reject("invalid_observation_or_scope")
	var ids: Array[String] = []
	if request.subject_kind == "unit":
		if not _state.knows_unit(str(request.subject_ref)):
			return _reject("not_live_subject")
		ids.append(_lod.representation_of(str(request.subject_ref)))
	else:
		ids = State.sorted_ids(_logistics._node_reps.get(request.subject_ref, {}))
		for id: String in ids:
			if int(_logistics._node_reps[request.subject_ref][id]) != int(_logistics._rep_counts[id]):
				return _reject("partial_proxy_subject_requires_explicit_leaf_estimate")
	if ids.is_empty() or ids.size() > MAX_QUERY:
		return _reject("bounded_macro_fact_unavailable")
	var value: Dictionary = _fact(ids, str(request.fact_kind), float(_sources[request.source_ref].precision_km))
	if value.is_empty():
		return _reject("multi_area_fact_requires_external_report")
	var record: Dictionary = request.duplicate(true)
	record.value = value
	record.observed_at = _state.time
	record.observer_ref = actor
	record.origin = _sources[request.source_ref].origin
	record.quality = _sources[request.source_ref].quality
	record.precision = "proxy_derived_estimate" if request.subject_kind == "unit" and ids[0] != request.subject_ref else "coarse_current_representation"
	_observations[request.id] = record
	# A producer gets a receipt reference, not hidden truth for the decision path.
	return {"ok": true, "observation_id": request.id}

func _fact(ids: Array[String], kind: String, precision: float) -> Dictionary:
	var weight: float = 0.0
	var position: float = 0.0
	var stock: float = 0.0
	var areas: Dictionary = {}
	var statuses: Dictionary = {}
	for id: String in ids:
		work.fact_records_examined += 1
		# Do not call examine_unit/preview_leaf: observing is not combat work.
		var unit: Dictionary = _state.units[id]
		weight += float(unit.personnel_total)
		position += float(unit.position) * float(unit.personnel_total)
		areas[unit.area_id] = true
		statuses[str(unit.action)] = true
		if kind in ["ammunition", "fuel"]:
			stock += float(unit.get(kind, 0.0))
		elif kind == "readiness":
			stock += float(unit.serviceable_equipment)
	if kind == "position":
		if areas.size() != 1:
			return {}
		var center: float = position / weight
		return {"area_ref": State.sorted_ids(areas)[0], "band_km": [floorf(center / precision) * precision, (floorf(center / precision) + 1.0) * precision], "precision_km": precision}
	if kind == "status":
		return {"states": State.sorted_ids(statuses)}
	return {"level": "LOW" if stock / weight < (1.0 if kind != "readiness" else 0.5) else "AVAILABLE"}

func admit_external_observation(record: Dictionary) -> Dictionary:
	# Trusted source input may be wrong. Validate provenance/time/shape, not truth.
	if record.size() != 7 or not _keys(record, ["id", "source_ref", "subject_kind", "subject_ref", "fact_kind", "value", "observed_at"]) or not record.get("id") is String or str(record.id).is_empty() or _observations.has(record.id) or not _sources.has(record.get("source_ref", "")) or _sources[record.source_ref].origin != "EXTERNAL" or record.get("subject_kind") not in ["unit", "formation"] or not record.get("subject_ref") is String or not _number(record.get("observed_at")) or float(record.observed_at) > _state.time or float(record.observed_at) < 0.0 or record.get("fact_kind") not in _sources[record.source_ref].fact_kinds or not _valid_value(str(record.fact_kind), record.get("value")):
		return _reject("invalid_external_observation")
	var source: Dictionary = _sources[record.source_ref]
	var node_id: String = str(_structure._unit_nodes.get(record.subject_ref, "")) if record.subject_kind == "unit" else str(record.subject_ref)
	if not _structure._nodes.has(node_id) or str(source.scope_ref) not in _structure._path(node_id):
		return _reject("outside_admitted_source_scope")
	var stored: Dictionary = record.duplicate(true)
	stored.observer_ref = source.observer_ref
	stored.origin = source.origin
	stored.quality = source.quality
	stored.precision = "external_claim"
	_observations[record.id] = stored
	return {"ok": true, "observation_id": record.id}

static func _valid_value(kind: String, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if kind == "position":
		return value.size() == 3 and _keys(value, ["area_ref", "band_km", "precision_km"]) and value.get("area_ref") is String and not str(value.area_ref).is_empty() and value.get("band_km") is Array and value.band_km.size() == 2 and _nonnegative(value.band_km[0]) and _nonnegative(value.band_km[1]) and float(value.band_km[1]) >= float(value.band_km[0]) and _positive(value.get("precision_km"))
	if kind == "status":
		if value.size() != 1 or not value.get("states") is Array or value.states.is_empty() or value.states.size() > 8:
			return false
		for status: Variant in value.states:
			if status not in ["idle", "hold", "advance", "support", "withdraw", "withdrawn", "disabled", "stalled", "retired", "reserve"]:
				return false
		return true
	return value.size() == 1 and value.get("level") in ["LOW", "AVAILABLE", "UNKNOWN"]

func send_report(actor: String, request: Dictionary) -> Dictionary:
	if request.size() != 4 or not _keys(request, ["id", "recipient_ref", "channel_ref", "observation_ids"]) or not request.get("id") is String or str(request.id).is_empty() or _messages.has(request.id) or not request.get("recipient_ref") is String or not _roles.has(request.recipient_ref) or not request.get("observation_ids") is Array or request.observation_ids.is_empty() or request.observation_ids.size() > MAX_CLAIMS or not _channel_allowed(actor, str(request.get("channel_ref", "")), str(request.recipient_ref), false):
		return _reject("invalid_report")
	var claims: Array[Dictionary] = []
	var seen: Dictionary = {}
	for id: Variant in request.observation_ids:
		if not id is String or seen.has(id) or not _observations.has(id) or _observations[id].observer_ref != actor:
			return _reject("invalid_observation_reference")
		seen[id] = true
		claims.append(_observations[id].duplicate(true))
	var message: Dictionary = _message(actor, request, "REPORT")
	message.claims = claims
	_messages[request.id] = message
	_push_report(message)
	_outboxes[actor].append(message.id)
	work.messages_admitted += 1
	return {"ok": true, "message_id": message.id, "issued_at": message.sent_at, "delivery_time": message.delivery_time}

func _channel_allowed(actor: String, id: String, recipient: String, command: bool) -> bool:
	if not _channels.has(id) or actor not in _channels[id].senders:
		return false
	return _structure._contains(str(_channels[id].command_scope), recipient) if command else recipient in _channels[id].recipients

func _message(actor: String, request: Dictionary, kind: String) -> Dictionary:
	return {"id": request.id, "kind": kind, "sender_ref": actor, "recipient_ref": request.recipient_ref,
		"created_at": _state.time, "sent_at": _state.time, "delivery_time": _state.time + float(_channels[request.channel_ref].latency),
		"channel_ref": request.channel_ref, "status": "PENDING", "unread": true}

func issue_command(actor: String, request: Dictionary) -> Dictionary:
	if request.size() != 3 or not _keys(request, ["id", "channel_ref", "command"]) or not request.get("id") is String or str(request.id).is_empty() or _messages.has(request.id) or not _roles.has(actor) or not request.get("command") is Dictionary or not request.command.get("target") is String:
		return _reject("invalid_command_message")
	var command: Dictionary = request.command.duplicate(true)
	if command.get("id") != request.id or command.get("kind") == "local_action" or not _channel_allowed(actor, str(request.get("channel_ref", "")), str(command.target), true) or _state.time < float(_next_issue.get(actor, 0.0)):
		return _reject("command_channel_scope_or_input_not_due")
	_actor = actor
	_gate = "preflight"
	work.authority_revalidations += 1
	var valid: Dictionary = _roles[actor].apply(command, _token, true)
	_gate = ""
	_actor = ""
	if not valid.ok:
		return valid
	var message: Dictionary = _message(actor, {"id": request.id, "recipient_ref": command.target, "channel_ref": request.channel_ref}, "COMMAND")
	message.command = command
	_messages[request.id] = message
	if not _state.schedule_event("communication_" + str(request.id), float(message.delivery_time), "communication", {"message_id": request.id}):
		_messages.erase(request.id)
		return _reject("command_schedule_failed")
	_next_issue[actor] = _state.time + Roles.INPUT_SECONDS[Roles.ROLES.find(str(_structure._people[actor].role))]
	_outboxes[actor].append(message.id)
	work.messages_admitted += 1
	return {"ok": true, "message_id": request.id, "issued_at": _state.time, "delivery_time": message.delivery_time}

func allows_role_delivery(role: RefCounted, token: RefCounted, validate_only: bool) -> bool:
	return token == _token and _roles.get(_actor) == role and (_gate == "preflight" if validate_only else _gate == "delivery")

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	if payload.size() != 1 or not payload.get("message_id") is String or not _messages.has(payload.message_id):
		return false
	var message: Dictionary = _messages[payload.message_id]
	return message.kind == "COMMAND" and message.status == "PENDING" and id == "communication_" + str(message.id) and due == float(message.delivery_time)

func process_command(event: Dictionary) -> Dictionary:
	if float(event.time) != _state.time or not accepts_event(str(event.id), event.payload, float(event.time)):
		return {"changed": [], "retired": [], "record": _reject("stale_command")}
	var message: Dictionary = _messages[event.payload.message_id]
	work.command_deliveries_processed += 1
	work.communication_events_processed += 1
	var result: Dictionary = _reject("channel_unavailable")
	var changed: Dictionary = {}
	var retired: Dictionary = {}
	if not _structure.active(str(message.recipient_ref)):
		result = _reject("retired_recipient")
	elif _channels[message.channel_ref].available:
		# All issue checks run again against the actual delivered-time authority.
		work.authority_revalidations += 1
		_actor = str(message.sender_ref)
		_gate = "preflight"
		result = _roles[_actor].apply(message.command, _token, true)
		if result.ok:
			var leaves: Dictionary = _structure.leaves(str(message.recipient_ref))
			var prior: Dictionary = {}
			for leaf: String in State.sorted_ids(leaves):
				var unit_id: String = str(_structure._nodes[leaf].unit_id)
				prior[_lod.representation_of(unit_id)] = true
			var before: int = int(_lod.work.leaf_records_materialized)
			_gate = "delivery"
			result = _roles[_actor].apply(message.command, _token)
			work.leaves_materialized_for_commands += int(_lod.work.leaf_records_materialized) - before
			if result.ok:
				for leaf: String in leaves:
					changed[_structure._nodes[leaf].unit_id] = true
				for id: String in prior:
					if _state.units.has(id):
						changed[id] = true
					else:
						retired[id] = true
		_gate = ""
		_actor = ""
	message.status = "EXECUTED" if result.ok else "REJECTED"
	message.processed_at = _state.time
	message.outcome = {"ok": result.ok, "reason": result.get("error", "executed_existing_role_input")}
	work.messages_delivered += int(result.ok)
	work.messages_failed += int(not result.ok)
	return {"changed": State.sorted_ids(changed), "retired": State.sorted_ids(retired), "record": message.duplicate(true)}

func _report_before(a: Dictionary, b: Dictionary) -> bool:
	work.report_heap_comparisons += 1
	return float(a.delivery_time) < float(b.delivery_time) or a.delivery_time == b.delivery_time and str(a.id) < str(b.id)

func _push_report(message: Dictionary) -> void:
	_report_heap.append(message)
	var index: int = _report_heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _report_before(_report_heap[index], _report_heap[parent]):
			break
		var swap: Dictionary = _report_heap[parent]
		_report_heap[parent] = _report_heap[index]
		_report_heap[index] = swap
		index = parent

func _pop_report() -> Dictionary:
	var result: Dictionary = _report_heap[0]
	var last: Dictionary = _report_heap.pop_back()
	if _report_heap.is_empty():
		return result
	_report_heap[0] = last
	var index: int = 0
	while index * 2 + 1 < _report_heap.size():
		var child: int = index * 2 + 1
		if child + 1 < _report_heap.size() and _report_before(_report_heap[child + 1], _report_heap[child]):
			child += 1
		if not _report_before(_report_heap[child], _report_heap[index]):
			break
		var swap: Dictionary = _report_heap[index]
		_report_heap[index] = _report_heap[child]
		_report_heap[child] = swap
		index = child
	return result

func deliver_reports_through(time: float) -> void:
	if time != _state.time:
		return
	# Noncausal notifications have no combat deadline. They are folded through
	# the same world time, retaining their exact logical arrival timestamps.
	while not _report_heap.is_empty() and float(_report_heap[0].delivery_time) <= time:
		_receive_report(_pop_report())

func _receive_report(message: Dictionary) -> void:
	if message.status != "PENDING" or float(message.delivery_time) > _state.time:
		return
	work.communication_events_processed += 1
	if not _channels[message.channel_ref].available:
		message.status = "FAILED"
		message.failed_at = message.delivery_time
		message.reason = "channel_unavailable"
		work.messages_failed += 1
		return
	message.status = "DELIVERED"
	message.received_at = message.delivery_time
	work.messages_delivered += 1
	var person: String = str(message.recipient_ref)
	_inboxes[person].append(message.id)
	for index: int in range(message.claims.size()):
		var claim: Dictionary = message.claims[index]
		var entry: Dictionary = {"entry_id": str(message.id) + ":%d" % index, "holder_ref": person,
			"subject_ref": claim.subject_ref, "subject_kind": claim.subject_kind, "fact_kind": claim.fact_kind,
			"claimed_value": claim.value.duplicate(true), "observed_at": claim.observed_at,
			"created_at": message.created_at, "sent_at": message.sent_at, "received_at": message.delivery_time,
			"source_ref": claim.source_ref, "origin": claim.origin, "message_id": message.id,
			"reliability": float(claim.quality) * float(_channels[message.channel_ref].quality), "precision": claim.precision}
		_knowledge[person].append(entry)
		_entry_ids[entry.entry_id] = true
		var key: String = str(claim.subject_kind) + ":" + str(claim.subject_ref) + ":" + str(claim.fact_kind)
		if not _subjects[person].has(key):
			_subjects[person][key] = []
		_subjects[person][key].append(entry)
		work.knowledge_records_updated += 1

func knowledge(person: String, subject_kind: String = "", subject: String = "", fact: String = "", limit: int = MAX_QUERY, before: int = -1) -> Dictionary:
	if not _roles.has(person) or limit < 1 or limit > MAX_QUERY:
		return _reject("invalid_bounded_knowledge_query")
	var records: Array = _knowledge[person] if subject.is_empty() else _subjects[person].get(subject_kind + ":" + subject + ":" + fact, [])
	if before < -1 or before > records.size():
		return _reject("invalid_history_cursor")
	var end: int = records.size() if before == -1 else before
	var start: int = maxi(0, end - limit)
	var entries: Array[Dictionary] = []
	for index: int in range(start, end):
		work.knowledge_records_examined += 1
		entries.append(records[index].duplicate(true))
	return {"ok": true, "holder_ref": person, "entries": entries, "total_matching": records.size(), "next_before": start if start > 0 else -1, "scope": "received claims only; no truth refresh; history retained"}

func inbox(person: String, limit: int = MAX_QUERY) -> Dictionary:
	if not _roles.has(person) or limit < 1 or limit > MAX_QUERY:
		return _reject("invalid_mailbox_query")
	var result: Array[Dictionary] = []
	var ids: Array = _inboxes[person]
	for index: int in range(maxi(0, ids.size() - limit), ids.size()):
		work.knowledge_records_examined += 1
		result.append(_messages[ids[index]].duplicate(true))
	return {"ok": true, "holder_ref": person, "messages": result, "total_received": ids.size()}

func role_report(role: RefCounted) -> Dictionary:
	var person: String = role._player_id
	if _roles.get(person) != role or not role._binding_current():
		return _reject("information_binding_required")
	return {"person_id": person, "role": _structure._people[person].role, "mode": "information_aware",
		"knowledge": knowledge(person), "inbox": inbox(person), "outbox": outbox(person)}

func outbox(person: String, limit: int = MAX_QUERY) -> Dictionary:
	if not _roles.has(person) or limit < 1 or limit > MAX_QUERY:
		return _reject("invalid_outbox_query")
	var result: Array[Dictionary] = []
	var ids: Array = _outboxes[person]
	for index: int in range(maxi(0, ids.size() - limit), ids.size()):
		work.knowledge_records_examined += 1
		var metadata: Dictionary = _messages[ids[index]].duplicate(true)
		metadata.erase("claims")
		metadata.erase("command")
		result.append(metadata)
	return {"ok": true, "holder_ref": person, "messages": result, "total_sent": ids.size()}

func snapshot() -> Dictionary:
	return {"time": _state.time, "sources": _sources.duplicate(true), "channels": _channels.duplicate(true),
		"observations": _observations.duplicate(true), "messages": _messages.duplicate(true),
		"knowledge": _knowledge.duplicate(true), "inboxes": _inboxes.duplicate(true), "outboxes": _outboxes.duplicate(true),
		"pending_report_heap": _report_heap.duplicate(true), "next_issue": _next_issue.duplicate(), "work": work.duplicate()}

static func _keys(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if key not in allowed:
			return false
	return true

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0

static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0

static func _quality(value: Variant) -> bool:
	return _nonnegative(value) and float(value) <= 1.0

static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}
