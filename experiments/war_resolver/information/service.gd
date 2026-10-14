extends RefCounted
## Military contract only. Knowledge is received claims, never a truth snapshot.
signal observation_recorded(record: Dictionary)
signal message_transition(record: Dictionary)
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const FACTS: Array[String] = ["position", "status", "ammunition", "fuel", "readiness", "person_status"]
const SPATIAL_FACTS: Array[String] = ["route"]
const GAMEPLAY_FACTS: Array[String] = ["cover", "objective", "contact"]
const MAX_CLAIMS: int = 8
const MAX_QUERY: int = 64
var _state: State
var _lod: RefCounted
var _structure: RefCounted
var _logistics: RefCounted
var _roles: Dictionary = {}
var _sources: Dictionary = {}
var _person_sources: Dictionary = {}
var _channels: Dictionary = {}
var _observations: Dictionary = {}
var _messages: Dictionary = {}
var _report_heap: Array[Dictionary] = []
var _knowledge: Dictionary = {}
var _subjects: Dictionary = {}
var _inboxes: Dictionary = {}
var _outboxes: Dictionary = {}
var _platform_sources: Dictionary = {}
var _communication_devices: Dictionary = {}
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

const RUNTIME_FIELDS: Array[String] = ["_sources", "_person_sources", "_channels", "_observations", "_messages", "_knowledge", "_inboxes", "_outboxes", "_communication_devices", "_entry_ids", "_next_issue", "work"]

func _runtime_producers() -> Dictionary:
	var g: RefCounted = _state.gameplay_port.get_ref()
	return {"air": g.air, "sea": g.sea, "land": g.land, "field": g.operations, "air_defense": g.air.defense, "port": _logistics}

func runtime_state() -> Dictionary:
	if _state.settlement_pending or not _gate.is_empty():
		return {"ok": false, "status": "PENDING"}
	var result: Dictionary = {"fields": State.capture_runtime_fields(self, RUNTIME_FIELDS), "platforms": {}, "report_heap": []}
	for id: String in _platform_sources:
		var record: Dictionary = _platform_sources[id]
		var producer_id: String = ""
		for key: String in _runtime_producers():
			if record.producer.get_ref() == _runtime_producers()[key]:
				producer_id = key
		if producer_id.is_empty():
			return {"ok": false, "error": "unsupported_report_producer"}
		result.platforms[id] = {"owner": record.owner, "producer": producer_id}
	for message: Dictionary in _report_heap:
		result.report_heap.append(message.id)
	return result

func restore_runtime(state: State, lod: RefCounted, structure: RefCounted, logistics: RefCounted, roles: Dictionary, image: Dictionary) -> bool:
	if not image.get("fields") is Dictionary or not image.get("platforms") is Dictionary or not image.get("report_heap") is Array or not State.restore_runtime_fields(self, image.fields, RUNTIME_FIELDS):
		return false
	_state = state
	_lod = lod
	_structure = structure
	_logistics = logistics
	_roles = roles
	state.information_port = weakref(self)
	for id: String in image.platforms:
		var platform: Dictionary = image.platforms[id]
		if not _runtime_producers().has(platform.get("producer", "")):
			return false
		_platform_sources[id] = {"owner": platform.owner, "producer": weakref(_runtime_producers()[platform.producer])}
	for id: Variant in image.report_heap:
		if not id is String or not _messages.has(id):
			return false
		_report_heap.append(_messages[id])
	_subjects.clear()
	for person: String in _knowledge:
		if not roles.has(person):
			return false
		_subjects[person] = {}
		for entry: Dictionary in _knowledge[person]:
			if not _entry_ids.has(entry.entry_id):
				return false
			var key: String = str(entry.subject_kind) + ":" + str(entry.subject_ref) + ":" + str(entry.fact_kind)
			if not _subjects[person].has(key):
				_subjects[person][key] = []
			_subjects[person][key].append(entry)
	return true

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
			if fact not in FACTS and not (state.spatial_port != null and fact in SPATIAL_FACTS) and not (state.gameplay_port != null and fact in GAMEPLAY_FACTS):
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
	for id: String in _sources:
		var observer: String = str(_sources[id].observer_ref)
		if not _person_sources.has(observer):
			_person_sources[observer] = []
		_person_sources[observer].append(id)
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

func on_member_move(person: String, previous: String, destination: String) -> void:
	# Only future direct observation follows the body. Received claims stay intact.
	for id: String in _person_sources.get(person, []):
		var source: Dictionary = _sources[id]
		if source.origin == "DIRECT" and source.scope_ref == previous:
			source.scope_ref = destination

func _source_allowed(actor: String, source_id: String, subject_kind: String, subject: String, fact: String) -> bool:
	if not _sources.has(source_id) or not _roles.has(actor) or subject_kind not in ["unit", "formation", "person"]:
		return false
	if _state.gameplay_port != null and not _state.gameplay_port.get_ref().participants.can_intend(actor):
		return false
	var source: Dictionary = _sources[source_id]
	if source.observer_ref != actor or fact not in source.fact_kinds:
		return false
	if subject_kind == "person":
		return fact == "person_status" and source.origin == "DIRECT" and _state.gameplay_port != null and _state.gameplay_port.get_ref().participants._units.has(subject)
	if fact == "person_status":
		return false
	if fact in GAMEPLAY_FACTS:
		if _state.gameplay_port == null or subject_kind != "unit":
			return false
		var participants: RefCounted = _state.gameplay_port.get_ref().participants
		var own_unit: String = str(participants._units.get(actor, _structure._nodes[_structure._people[actor].formation_id].get("unit_id", "")))
		if own_unit != subject:
			return false
		if not _state.gameplay_port.get_ref().participants.observation_opportunity(actor, subject):
			return false
	var node_id: String = str(_structure._unit_nodes.get(subject, "")) if subject_kind == "unit" else subject
	return _structure._contains(str(source.scope_ref), node_id)

func observe(actor: String, request: Dictionary) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if request.size() != 5 or not _keys(request, ["id", "source_ref", "subject_kind", "subject_ref", "fact_kind"]) or not request.get("id") is String or str(request.id).is_empty() or _observations.has(request.id) or not _source_allowed(actor, str(request.get("source_ref", "")), str(request.get("subject_kind", "")), str(request.get("subject_ref", "")), str(request.get("fact_kind", ""))):
		return _reject("invalid_observation_or_scope")
	var ids: Array[String] = []
	if request.subject_kind == "person":
		ids.append(str(request.subject_ref))
	elif request.subject_kind == "unit":
		if not _state.knows_unit(str(request.subject_ref)):
			return _reject("not_live_subject")
		ids.append(str(request.subject_ref) if request.fact_kind == "objective" else _lod.representation_of(str(request.subject_ref)))
	else:
		ids = State.sorted_ids(_logistics._node_reps.get(request.subject_ref, {}))
		for id: String in ids:
			if int(_logistics._node_reps[request.subject_ref][id]) != int(_logistics._rep_counts[id]):
				return _reject("partial_proxy_subject_requires_explicit_leaf_estimate")
	if ids.is_empty() or ids.size() > MAX_QUERY:
		return _reject("bounded_macro_fact_unavailable")
	var value: Dictionary = _state.gameplay_port.get_ref().participants.visible_person(actor, str(request.subject_ref)) if request.subject_kind == "person" else _fact(ids, str(request.fact_kind), float(_sources[request.source_ref].precision_km))
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
	observation_recorded.emit(record.duplicate(true))
	# A producer gets a receipt reference, not hidden truth for the decision path.
	return {"ok": true, "observation_id": request.id}

func record_person_observation(producer: RefCounted, actor: String, patient: String, id: String) -> Dictionary:
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().participants or _observations.has(id) or _messages.has(id) or not _inboxes.has(actor):
		return _reject("existing_local_body_observation_required")
	var value: Dictionary = producer.visible_person(actor, patient)
	if value.is_empty():
		return _reject("actual_visible_body_required")
	var record: Dictionary = {"id": id, "source_ref": actor + "_body", "subject_kind": "person", "subject_ref": patient,
		"fact_kind": "person_status", "value": value, "observed_at": _state.time, "observer_ref": actor,
		"origin": "DIRECT", "quality": 1.0, "precision": "local_visible_body"}
	_observations[id] = record
	var message: Dictionary = {"id": id, "kind": "REPORT", "sender_ref": actor, "recipient_ref": actor, "claims": [record],
		"created_at": _state.time, "sent_at": _state.time, "delivery_time": _state.time, "received_at": _state.time,
		"channel_ref": "report", "status": "DELIVERED", "unread": true, "local_observation": true}
	_messages[id] = message
	_inboxes[actor].append(id)
	_store_claims(message, actor, _state.time, false, true)
	work.messages_admitted += 1
	work.messages_delivered += 1
	return {"ok": true}

func record_ground_observation(producer: RefCounted, actor: String, target: String, id: String, fact: String = "ground_contact") -> Dictionary:
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().tactics or _observations.has(id) or _messages.has(id) or fact not in ["ground_contact", "cover"]:
		return _reject("actual_personal_observation_required")
	var participants: RefCounted = _state.gameplay_port.get_ref().participants
	if fact == "ground_contact" and not producer.visible(actor, target) or fact == "cover" and (not participants._units.has(actor) or participants._physical_unit(actor).id != target or not participants.observation_opportunity(actor, target)):
		return _reject("actual_personal_observation_required")
	var unit: Dictionary = _state.units[target]
	var value: Dictionary = producer.observed_local_scene(actor) if fact == "cover" else producer.observed_ground_target(actor, target)
	var record: Dictionary = {"id": id, "source_ref": actor + "_body", "subject_kind": "unit", "subject_ref": target,
		"fact_kind": fact, "value": value,
		"observed_at": _state.time, "observer_ref": actor, "origin": "DIRECT", "quality": 1.0, "precision": "local_visible_group"}
	_observations[id] = record
	# Direct perception is local to this body. Remote recipients still require
	# send_report/forward and the existing real communication channel.
	var message: Dictionary = {"id": id, "kind": "REPORT", "sender_ref": actor, "recipient_ref": actor, "claims": [record],
		"created_at": _state.time, "sent_at": _state.time, "delivery_time": _state.time, "received_at": _state.time,
		"channel_ref": "report", "status": "DELIVERED", "unread": true, "local_observation": true}
	_messages[id] = message
	_inboxes[actor].append(id)
	_store_claims(message, actor, _state.time, false, true)
	work.messages_admitted += 1
	work.messages_delivered += 1
	observation_recorded.emit(record.duplicate(true))
	message_transition.emit(message.duplicate(true))
	return {"ok": true, "observation_id": id}

func _fact(ids: Array[String], kind: String, precision: float) -> Dictionary:
	if kind in GAMEPLAY_FACTS and _state.gameplay_port != null:
		work.fact_records_examined += ids.size()
		return _state.gameplay_port.get_ref().visible_fact(ids, kind)
	if kind == "route":
		if ids.size() != 1 or not _state.units[ids[0]].has("spatial"):
			return {}
		work.fact_records_examined += 1
		var route: Dictionary = _state.units[ids[0]].spatial
		return {"edge_ref": route.blocked_edge if not str(route.blocked_edge).is_empty() else route.edge,
			"node_ref": route.node, "state": "BLOCKED" if not str(route.blocked_edge).is_empty() else ("TRAVELLING" if not str(route.edge).is_empty() else "ARRIVED"), "cause_ref": route.cause_ref}
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
	if _state != null and _state.public_pending():
		return _state.pending_view()
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
	observation_recorded.emit(stored.duplicate(true))
	return {"ok": true, "observation_id": record.id}

static func _valid_value(kind: String, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if kind == "cover":
		if value.size() != 2 or not value.get("node_ref") is String or not value.get("cover_refs") is Array or value.cover_refs.size() > 16:
			return false
		for id: Variant in value.cover_refs:
			if not id is String or str(id).length() > 128:
				return false
		return true
	if kind == "contact":
		if value.size() != 1 or not value.get("observed_unit_refs") is Array or value.observed_unit_refs.size() > 16:
			return false
		for id: Variant in value.observed_unit_refs:
			if not id is String or str(id).length() > 128:
				return false
		return true
	if kind == "objective":
		return value.size() == 4 and value.get("target_node") is String and value.get("route_complete") is bool and value.get("local_condition") is bool and value.get("status") in ["active", "complete", "failed", "cancelled"]
	if kind == "route":
		if value.size() != 4 or not _keys(value, ["edge_ref", "node_ref", "state", "cause_ref"]) or value.get("state") not in ["AVAILABLE", "BLOCKED", "TRAVELLING", "ARRIVED"]:
			return false
		for key: String in ["edge_ref", "node_ref", "cause_ref"]:
			if not value.get(key) is String or str(value[key]).length() > 128:
				return false
		return not str(value.node_ref).is_empty() and (value.state not in ["AVAILABLE", "BLOCKED", "TRAVELLING"] or not str(value.edge_ref).is_empty())
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
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state.gameplay_port != null and not _state.gameplay_port.get_ref().participants.can_intend(actor):
		return _reject("report_sender_unavailable")
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
	message_transition.emit(message.duplicate(true))
	return {"ok": true, "message_id": message.id, "issued_at": message.sent_at, "delivery_time": message.delivery_time}

func register_air_source(id: String, owner: String, producer: RefCounted) -> bool:
	return register_platform_source(id, owner, producer)

func register_platform_source(id: String, owner: String, producer: RefCounted) -> bool:
	if _state.time != 0.0 or _platform_sources.size() >= 12 or _platform_sources.has(id) or _outboxes.has(id) or not _structure.active(owner) or not _channels.has("report"):
		return false
	_platform_sources[id] = {"owner": owner, "producer": weakref(producer)}
	_outboxes[id] = []
	return true

func send_air_report(producer: RefCounted, platform: String, recipient: String, id: String, claims: Array[Dictionary]) -> Dictionary:
	return send_platform_report(producer, platform, recipient, id, claims)

func transfer_field_source(producer: RefCounted, platform: String, owner: String) -> bool:
	# Move an admitted reporting capability; retain its identity and old messages.
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().operations or not _platform_sources.has(platform) or _platform_sources[platform].producer.get_ref() != producer or not _structure.active(owner):
		return false
	_platform_sources[platform].owner = owner
	return true

func send_platform_report(producer: RefCounted, platform: String, recipient: String, id: String, claims: Array[Dictionary]) -> Dictionary:
	if not _platform_sources.has(platform) or _platform_sources[platform].producer.get_ref() != producer or not _roles.has(recipient) or _messages.has(id) or claims.is_empty() or claims.size() > MAX_CLAIMS or recipient not in _channels.report.recipients:
		return _reject("invalid_actual_platform_observation_report")
	# Called only by the actual sensor event. It grants no private observation to
	# the human commander before the same report heap delivers it.
	var message: Dictionary = _message(platform, {"id": id, "recipient_ref": recipient, "channel_ref": "report"}, "REPORT")
	message.claims = claims.duplicate(true)
	_messages[id] = message
	_push_report(message)
	_outboxes[platform].append(id)
	work.messages_admitted += 1
	message_transition.emit(message.duplicate(true))
	return {"ok": true, "message_id": id, "delivery_time": message.delivery_time}

func _channel_allowed(actor: String, id: String, recipient: String, command: bool) -> bool:
	if not _channels.has(id) or actor not in _channels[id].senders:
		return false
	return _structure._contains(str(_channels[id].command_scope), recipient) if command else recipient in _channels[id].recipients

func validate_forward(actor: String, source: String, recipient: String) -> Dictionary:
	if not _roles.has(actor) or not _roles.has(recipient) or not _messages.has(source):
		return _reject("received_report_and_actual_recipient_required")
	var position: Dictionary = _structure.command_person(actor)
	var message: Dictionary = _messages[source]
	var received: bool = message.status == "DELIVERED" and message.recipient_ref == actor
	for receipt: Dictionary in message.get("relay_receipts", []):
		received = received or receipt.person_ref == actor
	if Roles.ROLES.find(str(position.role)) < 2 or message.kind != "REPORT" or not received or not _structure._contains(str(position.formation_id), str(_structure.command_person(recipient).formation_id)) or not _channel_allowed(actor, "report", recipient, false):
		return _reject("received_report_forward_outside_current_command")
	if _state.gameplay_port != null and not _state.gameplay_port.get_ref().participants.can_intend(actor):
		return _reject("report_sender_unavailable")
	return {"ok": true}

func report_supply_request(producer: RefCounted, actor: String, reference: String, request: Dictionary) -> void:
	if _state.decision_port == null or _state.decision_port.get_ref() != producer or not _logistics._requests.has(reference):
		return
	request = _logistics._requests[reference]
	var node: String = str(_structure._unit_nodes.get(request.target, "")) if request.target_kind == "unit" else str(request.target)
	var recipients: Array[String] = [actor]
	for scope: String in _structure._path(node):
		var person: String = str(_structure._positions.get(scope, {}).get("person", ""))
		if not person.is_empty() and person not in recipients:
			recipients.append(person)
	for person: String in recipients:
		if not _channel_allowed(actor, "report", person, false):
			continue
		var id: String = "request_report_" + reference + "_" + person + ("_revision_%d" % int(request.request_revision) if request.has("request_revision") else "")
		if _messages.has(id):
			continue
		var message: Dictionary = _message(actor, {"id": id, "recipient_ref": person, "channel_ref": "report"}, "REPORT")
		message.claims = [{"id": id + "_claim", "source_ref": actor, "subject_kind": str(request.target_kind), "subject_ref": str(request.target),
			"fact_kind": "supply_request", "value": {"request_ref": reference, "requester_ref": request.actor, "target_kind": request.target_kind, "target_ref": request.target, "resource_class": request.resource_class, "quantity": request.quantity, "status": request.status, "request_revision": request.get("request_revision", 0)},
			"observed_at": _state.time, "observer_ref": actor, "origin": "SUBORDINATE_REPORT", "quality": 1.0, "precision": "actual_submitted_request"}]
		_messages[id] = message
		_push_report(message)
		_outboxes[actor].append(id)
		work.messages_admitted += 1
		message_transition.emit(message.duplicate(true))

func forward_report(actor: String, source: String, recipient: String, id: String) -> Dictionary:
	var admitted: Dictionary = validate_forward(actor, source, recipient)
	if not admitted.ok or _messages.has(id):
		return admitted if not admitted.ok else _reject("duplicate_report")
	var message: Dictionary = _message(actor, {"id": id, "recipient_ref": recipient, "channel_ref": "report"}, "REPORT")
	message.claims = _messages[source].claims.duplicate(true)
	for claim: Dictionary in message.claims:
		claim.quality = float(claim.quality) * float(_messages[source].get("received_quality", _channels[_messages[source].channel_ref].quality))
	message.relay_ref = source
	# Original observation time, source and quality survive the additional delay.
	_messages[id] = message
	_push_report(message)
	_outboxes[actor].append(id)
	work.messages_admitted += 1
	message_transition.emit(message.duplicate(true))
	return {"ok": true, "message_id": id, "delivery_time": message.delivery_time}

func send_task_report(producer: RefCounted, reference: String, recipient: String, id: String, fact: String, value: Dictionary) -> Dictionary:
	# Assignment and acknowledgements are command facts, not fabricated observations.
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().operations or not producer.permits_report(reference, recipient) or not _roles.has(recipient) or not _channels.has("report") or recipient not in _channels.report.recipients or _messages.has(id) or fact not in ["operation_task", "operation_status"]:
		return _reject("existing_purpose_report_required")
	var sender: String = str(value.get("reporter_ref", value.get("issuer", recipient)))
	if not _outboxes.has(sender):
		sender = str(value.get("issuer", recipient))
	var message: Dictionary = _message(sender, {"id": id, "recipient_ref": recipient, "channel_ref": "report"}, "REPORT")
	message.claims = [{"id": id + "_claim", "source_ref": reference, "subject_kind": "formation", "subject_ref": str(value.get("scope", _structure.command_person(recipient).formation_id)),
		"fact_kind": fact, "value": value.duplicate(true), "observed_at": _state.time, "observer_ref": sender,
		"origin": "HQ_REPORT", "quality": 1.0, "precision": "issued_task_or_received_feedback"}]
	_messages[id] = message
	_push_report(message)
	_outboxes[sender].append(id)
	work.messages_admitted += 1
	message_transition.emit(message.duplicate(true))
	return {"ok": true, "message_id": id, "delivery_time": message.delivery_time}

func _message(actor: String, request: Dictionary, kind: String) -> Dictionary:
	var message: Dictionary = {"id": request.id, "kind": kind, "sender_ref": actor, "recipient_ref": request.recipient_ref,
		"created_at": _state.time, "sent_at": _state.time, "delivery_time": _state.time + float(_channels[request.channel_ref].latency),
		"channel_ref": request.channel_ref, "status": "PENDING", "unread": true}
	if _channels[request.channel_ref].has("physical"):
		message.communication_holder = actor
		message.communication_status = "AWAITING_LINK"
		message.communication_attempt = 0
		message.relay_receipts = []
		message.delivery_time = minf(float(message.delivery_time), _state.time + float(_channels[request.channel_ref].physical.wait_seconds))
	return message

func enable_local_communications(channels: Array, devices: Dictionary, rules: Dictionary) -> bool:
	if _state.time != 0.0 or devices.size() > 12 or channels.size() > 4 or not _positive(rules.get("contact_km")) or not _positive(rules.get("short_range_km")) or not _positive(rules.get("retry_seconds")) or float(rules.retry_seconds) < 30.0 or not _positive(rules.get("wait_seconds")) or not rules.get("relay_people", []) is Array or rules.get("relay_people", []).size() > 2:
		return false
	if not rules.get("relay_platforms", []) is Array or rules.get("relay_platforms", []).size() + rules.get("relay_people", []).size() > 2:
		return false
	for channel: Variant in channels:
		if not channel is String or not _channels.has(channel):
			return false
	for platform: String in devices:
		if not devices[platform] is Dictionary or not _platform_sources.has(platform) or not _positive(devices[platform].get("range_km")) or devices[platform].get("kind", "") not in ["field", "unit", "vessel", "aircraft", "depot"]:
			return false
	for person: Variant in rules.get("relay_people", []):
		if not person is String or not _roles.has(person):
			return false
	for platform: Variant in rules.get("relay_platforms", []):
		if not platform is String or not devices.has(platform) or not _platform_sources.has(platform):
			return false
	_communication_devices = devices.duplicate(true)
	for channel: String in channels:
		_channels[channel].physical = rules.duplicate(true)
	return true

func relay_deployment(producer: RefCounted, platform: String, source: String, recipient: String, channel: String) -> Dictionary:
	# This is an on-site capability result, never a remote intelligence query.
	if _state.gameplay_port == null or producer != _state.gameplay_port.get_ref().operations:
		return {"supported": false}
	var rules: Dictionary = _channels.get(channel, {}).get("physical", {})
	if rules.is_empty() or platform not in rules.get("relay_platforms", []) or not _communication_devices.has(platform):
		return {"supported": false}
	var message: Dictionary = {"sender_ref": source, "channel_ref": channel}
	var allowed: bool = (_platform_sources.has(source) or _roles.has(source)) and (_platform_sources.has(recipient) or _roles.has(recipient) or recipient.begins_with("unit:"))
	allowed = allowed and _relay_allowed(platform, message, recipient)
	return {"supported": true, "ready": allowed and _link(source, platform, rules) and _link(platform, recipient, rules)}

func _device_endpoint(platform: String) -> Dictionary:
	if not _communication_devices.has(platform) or not _platform_sources.has(platform) or _state.gameplay_port == null:
		return {}
	var g: RefCounted = _state.gameplay_port.get_ref()
	var device: Dictionary = _communication_devices[platform]
	var reference: String = str(device.get("subject_ref", platform))
	var point: Array = []
	var ground: Dictionary = {}
	if device.kind in ["field", "unit"]:
		if device.kind == "field":
			reference = str(_structure._nodes.get(_platform_sources[platform].owner, {}).get("unit_id", ""))
		if not _state.units.has(reference) or not _state.units[reference].has("spatial") or float(_state.units[reference].effective) <= 0.001:
			return {}
		var unit: Dictionary = _state.units[reference]
		if g.tactics.manoeuvre_active(reference):
			unit = g.tactics.part_source(unit, g.tactics.manoeuvres[reference].parts.rear)
			if float(unit.effective) <= 0.001:
				return {}
		point = g._space.xy(unit)
		if float(unit.get("serviceable_equipment", 0.0)) <= 0.0:
			return {"xy": point, "range_km": 0.0, "open": false, "platform_ref": platform}
		ground = g._space._edges[unit.spatial.edge].ground if g._space._edges.has(unit.spatial.edge) else g._space._nodes[unit.spatial.node].ground
		ground = ground.duplicate()
		ground.communication_open = ground.get("communication_open", true) and g._space._nodes[unit.spatial.node].get("communication_open", true)
	elif device.kind == "vessel":
		if not g.sea.vessels.has(reference) or g.sea.vessels[reference].status == "SUNK" or float(g.sea.vessels[reference].stock.equipment) <= 0.0:
			return {}
		point = g.sea.position(reference)
		ground = g._space._nodes[g.sea.contact_node(reference)]
	elif device.kind == "aircraft":
		if not g.air.assets.has(reference) or g.air.assets[reference].status == "DESTROYED":
			return {}
		point = g.air.position(reference)
	elif device.kind == "depot":
		if not _logistics._depots.has(reference):
			return {}
		var node: String = str(_logistics._depots[reference].get("node_ref", ""))
		if not g._space._nodes.has(node):
			return {}
		point = g._space._nodes[node].xy
		ground = g._space._nodes[node]
	var factor: float = clampf(float(ground.get("visibility", 1.0)) * (1.0 - 0.5 * float(ground.get("concealment", 0.0))), 0.1, 1.0)
	return {"xy": point, "range_km": float(device.range_km) * factor, "open": ground.get("communication_open", true), "platform_ref": platform}

func _endpoint(reference: String, rules: Dictionary) -> Dictionary:
	if _platform_sources.has(reference):
		return _device_endpoint(reference)
	if reference.begins_with("unit:") and _state.gameplay_port != null:
		var unit: String = reference.trim_prefix("unit:")
		if not _state.units.has(unit) or not _state.units[unit].has("spatial") or float(_state.units[unit].effective) <= 0.001:
			return {}
		var g: RefCounted = _state.gameplay_port.get_ref()
		var node: String = str(_state.units[unit].spatial.node)
		if g.tactics.manoeuvre_active(unit) and g.tactics.part_capacity(g.tactics.manoeuvres[unit].parts.rear) <= 0.001:
			return {}
		return {"xy": g._space.xy(_state.units[unit]), "range_km": rules.short_range_km, "open": g._space._nodes[node].get("communication_open", true)}
	if not _roles.has(reference) or _state.gameplay_port == null:
		return {}
	var p: RefCounted = _state.gameplay_port.get_ref().participants
	if not p._units.has(reference) or not p.can_intend(reference):
		return {}
	var point: Array = p.position(reference)
	var node: String = str(p._physical_unit(reference).spatial.node) if p._member(reference).state == "FOLLOWING" else str(p._member(reference).anchor_node)
	var endpoint: Dictionary = {"xy": point, "range_km": rules.short_range_km, "open": p.body_ground(reference).get("communication_open", true) and _state.gameplay_port.get_ref()._space._nodes[node].get("communication_open", true)}
	var scope: String = str(_structure.command_person(reference).formation_id)
	for platform: String in _communication_devices:
		var owner: String = str(_platform_sources[platform].owner)
		if not _structure._contains(scope, owner) and not _structure._contains(owner, scope):
			continue
		var device: Dictionary = _device_endpoint(platform)
		if not device.is_empty() and device.open and _distance(point, device.xy) <= float(rules.contact_km):
			endpoint.range_km = maxf(float(endpoint.range_km), float(device.range_km))
	return endpoint

func _message_recipient(message: Dictionary) -> String:
	if message.get("return_receipt", false):
		return str(message.sender_ref)
	if message.kind == "REPORT" or _state.gameplay_port == null:
		return str(message.recipient_ref)
	var g: RefCounted = _state.gameplay_port.get_ref()
	var values: Dictionary = message.command.get("values", {})
	if values.get("operation", "") == "request_report":
		if values.get("subject_kind", "") == "vessel":
			return str(values.subject_ref)
		return str(g.operations._field_sources.get(values.subject_ref, "unit:" + str(values.subject_ref)))
	if message.command.kind == "naval_intent":
		return str(values.get("vessel_ref", ""))
	if message.command.kind == "air_intent":
		return str(values.get("asset_ref", ""))
	var unit: String = str(values.get("unit_ref", ""))
	if message.command.kind == "tactical_intent" and values.has("gun_ref"):
		unit = str(g.tactics.guns.get(values.gun_ref, {}).get("unit_ref", ""))
	if message.command.kind == "land_intent" and values.has("transport_ref"):
		unit = str(g.land.jobs.get(values.transport_ref, {}).get("unit_ref", ""))
	if unit == "":
		unit = str(_structure._nodes.get(message.recipient_ref, {}).get("unit_id", ""))
	if unit != "":
		return str(g.operations._field_sources.get(unit, "unit:" + unit))
	return str(_structure._positions.get(message.recipient_ref, {}).get("person", ""))

func _link(a: String, b: String, rules: Dictionary) -> bool:
	var first: Dictionary = _endpoint(a, rules)
	var second: Dictionary = _endpoint(b, rules)
	if first.is_empty() or second.is_empty():
		return false
	var distance: float = _distance(first.xy, second.xy)
	return distance <= float(rules.contact_km) or first.open and second.open and distance <= minf(float(first.range_km), float(second.range_km))

func _command_links(holder: String, message: Dictionary, rules: Dictionary) -> bool:
	if message.kind != "COMMAND" or message.get("return_receipt", false) or _state.gameplay_port == null or message.command.kind not in ["mission", "coordination", "reserve_intent", "tactical_intent", "goal_intent"]:
		return true
	for leaf: String in _roles[message.sender_ref].delivery_leaves(message.command):
		var unit: String = str(_structure._nodes[leaf].unit_id)
		var receiver: String = str(_state.gameplay_port.get_ref().operations._field_sources.get(unit, "unit:" + unit))
		if not _link(holder, receiver, rules):
			return false
	return true

func _relay_allowed(person: String, message: Dictionary, recipient: String) -> bool:
	var platform: bool = _platform_sources.has(person)
	if not platform and (not _roles.has(person) or Roles.ROLES.find(str(_structure.command_person(person).role)) < 2 or person not in _channels[message.channel_ref].get("senders", [])):
		return false
	var sender_scope: String = str(_platform_sources[message.sender_ref].owner) if _platform_sources.has(message.sender_ref) else str(_structure.command_person(str(message.sender_ref)).formation_id)
	var relay_scope: String = str(_platform_sources[person].owner) if platform else str(_structure.command_person(person).formation_id)
	var receiver_scope: String = str(_platform_sources[recipient].owner) if _platform_sources.has(recipient) else str(_structure._unit_nodes.get(recipient.trim_prefix("unit:"), "")) if recipient.begins_with("unit:") else str(_structure.command_person(recipient).formation_id) if _roles.has(recipient) else ""
	if not _structure.active(receiver_scope):
		return false
	if platform and (not _communication_devices.has(person) or float(_device_endpoint(person).get("range_km", 0.0)) <= 0.0):
		return false
	var related: bool = _structure._contains(relay_scope, sender_scope) or _structure._contains(sender_scope, relay_scope)
	if platform:
		for scope: String in _structure._path(sender_scope):
			if _structure._contains(scope, relay_scope) and _structure._contains(scope, receiver_scope) and scope in _structure._positions:
				var commander: String = str(_structure._positions[scope].get("person", ""))
				related = related or not commander.is_empty() and _roles.has(commander) and Roles.ROLES.find(str(_structure.command_person(commander).role)) >= 2
	return _structure._nodes[relay_scope].side == _structure._nodes[sender_scope].side and _structure._nodes[relay_scope].side == _structure._nodes[receiver_scope].side and related

func _communication_step(message: Dictionary) -> String:
	var channel: Dictionary = _channels[message.channel_ref]
	if not message.has("communication_holder"):
		return "ARRIVED"
	var rules: Dictionary = channel.physical
	var expires: float = float(message.sent_at) + float(rules.wait_seconds)
	if _state.time >= expires:
		message.communication_status = "FAILED"
		return "FAILED"
	var recipient: String = _message_recipient(message)
	var holder: String = str(message.communication_holder)
	if channel.available and _link(holder, recipient, rules) and _command_links(holder, message, rules):
		message.communication_status = "ARRIVED"
		message.delivery_time = _state.time
		return "ARRIVED"
	if channel.available:
		var relays: Array = rules.get("relay_people", []).duplicate()
		relays.append_array(rules.get("relay_platforms", []))
		for relay: String in relays:
			var visited: bool = relay == holder or relay == message.sender_ref or relay == recipient
			for receipt: Dictionary in message.relay_receipts:
				visited = visited or receipt.person_ref == relay
			if not visited and _relay_allowed(relay, message, recipient) and _link(holder, relay, rules):
				message.relay_receipts.append({"person_ref": relay, "received_at": _state.time, "from_ref": holder})
				message.communication_holder = relay
				message.communication_status = "RELAYING"
				if message.kind == "REPORT" and _roles.has(relay):
					_store_claims(message, relay, _state.time, true)
					var receipt: Dictionary = message.duplicate(true)
					receipt.recipient_ref = relay
					receipt.received_at = _state.time
					receipt.received_quality = channel.quality
					receipt.status = "DELIVERED"
					receipt.hop_delivery = true
					message_transition.emit(receipt)
				message.delivery_time = minf(expires, _state.time + maxf(5.0, float(channel.latency)))
				return "WAIT"
	if _state.time >= float(message.sent_at) + float(rules.wait_seconds):
		message.communication_status = "FAILED"
		return "FAILED"
	var previous: String = str(message.communication_status)
	message.communication_status = "WAITING_LINK"
	message.delivery_time = minf(expires, _state.time + float(rules.retry_seconds))
	if previous != "WAITING_LINK":
		message_transition.emit(message.duplicate(true))
	return "WAIT"

func communication_view(person: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _state.public_pending():
		return result
	var sent: Array = _outboxes.get(person, [])
	for index: int in range(maxi(0, sent.size() - 8), sent.size()):
		var message: Dictionary = _messages[sent[index]]
		if message.has("communication_status"):
			var state: String = str(message.communication_status)
			if message.kind == "COMMAND" and message.status == "PENDING":
				state = "AWAITING_RECEIPT"
			elif message.kind == "REPORT" and message.communication_holder != person:
				state = "HANDED_TO_RELAY"
			result.append({"message_ref": message.id, "kind": message.kind, "recipient_ref": message.recipient_ref, "status": "SENT" if state == "HANDED_TO_RELAY" else message.status,
				"communication_status": state, "sent_at": message.sent_at, "next_attempt_at": message.delivery_time if state not in ["AWAITING_RECEIPT", "HANDED_TO_RELAY"] else null})
	return result

static func _distance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))

func reported_supply_balance(person: String, reference: String, actual: Dictionary, local_facts: Dictionary) -> Dictionary:
	# A split carrier reports its own custody and local paperwork. It cannot
	# announce another distant carrier's loss from the authoritative cargo book.
	var sea: Dictionary = _logistics._deliveries.get(actual.get("sea_delivery_ref", ""), {})
	if not sea.has("cargo_by_vessel"):
		return actual.duplicate(true)
	var previous: Dictionary = {}
	var observed: float = -INF
	var revision: int = -1
	var requested: float = float(sea.get("request_quantity_at_batch", actual.quantity))
	var baseline: Dictionary = sea.get("request_baselines", {}).get(reference, {})
	var updates: Dictionary = {}
	if not baseline.is_empty():
		requested = float(baseline.quantity)
	var request_time: float = -INF
	for claim: Dictionary in knowledge(person).get("entries", []):
		var value: Dictionary = claim.claimed_value
		if claim.fact_kind == "supply_request" and value.get("request_ref", "") == reference and float(claim.reliability) > 0.0 and float(claim.observed_at) >= request_time:
			requested = float(value.quantity)
			request_time = claim.observed_at
		var balance: Dictionary = value.get("request_balance", {})
		if balance.get("request_ref", "") != reference:
			balance = value.get("allocation_balances", {}).get(reference, {})
		if value.get("transport_ref", "") == actual.get("sea_delivery_ref", "") and float(claim.reliability) > 0.0:
			for update: Dictionary in value.get("allocation_updates", []):
				updates[update.id] = update
		if balance.get("request_ref", "") == reference and float(claim.reliability) > 0.0 and (float(claim.observed_at) > observed or claim.observed_at == observed and int(value.get("report_revision", 0)) >= revision):
			previous = balance
			observed = claim.observed_at
			revision = int(value.get("report_revision", 0))
	var result: Dictionary = actual.duplicate(true)
	for update: Dictionary in local_facts.get("allocation_updates", []):
		updates[update.id] = update
	result.quantity = requested
	result.land_delivery_ref = local_facts.get("land_delivery_ref", previous.get("land_delivery_ref", ""))
	result.land_status = local_facts.get("land_status", previous.get("land_status", "UNREPORTED"))
	result.received_quantity = local_facts.get("received_quantity", previous.get("received_quantity", baseline.get("received", sea.get("received_before_batch", 0.0))))
	result.port_remaining = local_facts.get("port_remaining", previous.get("port_remaining", 0.0))
	result.land_committed = local_facts.get("land_committed", previous.get("land_committed", 0.0))
	result.confirmed_loss_quantity = maxf(float(previous.get("confirmed_loss_quantity", baseline.get("loss", sea.get("loss_before_batch", 0.0)))), float(local_facts.get("confirmed_loss_quantity", 0.0)))
	var batch_received: float = maxf(0.0, float(result.received_quantity) - float(baseline.get("received", sea.get("received_before_batch", 0.0))))
	var batch_lost: float = maxf(0.0, float(result.confirmed_loss_quantity) - float(baseline.get("loss", sea.get("loss_before_batch", 0.0))))
	var manifest: Dictionary = baseline.get("manifest", sea.requested_cargo)
	var assigned: float = float(manifest.get(result.resource_class, 0.0))
	for update: Dictionary in updates.values():
		if update.old_request_ref != update.request_ref:
			var amount: float = float(update.cargo.get(result.resource_class, 0.0))
			assigned += amount if update.request_ref == reference else (-amount if update.old_request_ref == reference else 0.0)
	var expected: float = maxf(0.0, assigned - batch_received - batch_lost - float(result.port_remaining) - float(result.land_committed) - float(local_facts.get("returned_quantity", 0.0)))
	expected = maxf(expected, float(local_facts.get("sea_committed", 0.0)))
	result.sea_committed = expected
	result.uncommitted_quantity = maxf(0.0, float(result.quantity) - float(result.received_quantity) - expected - float(result.port_remaining) - float(result.land_committed))
	result.sea_status = "UNCONFIRMED_REMAINDER" if expected > 0.000001 else "RECEIVED"
	if float(result.received_quantity) < float(result.quantity) and result.status == "RECEIVED":
		result.status = "REQUESTED"
	result.balance_basis = "received_reports_and_current_local_custody"
	if local_facts.has("port_depot_ref"):
		result.port_depot_ref = local_facts.port_depot_ref
	elif not previous.is_empty():
		result.port_depot_ref = previous.get("port_depot_ref", "")
	return result

func issue_command(actor: String, request: Dictionary) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
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
	_next_issue[actor] = _state.time + Roles.INPUT_SECONDS[Roles.ROLES.find(str(_structure.command_person(actor).role))]
	_outboxes[actor].append(message.id)
	work.messages_admitted += 1
	message_transition.emit(message.duplicate(true))
	return {"ok": true, "message_id": request.id, "issued_at": _state.time, "delivery_time": message.delivery_time}

func allows_role_delivery(role: RefCounted, token: RefCounted, validate_only: bool) -> bool:
	return token == _token and _roles.get(_actor) == role and (_gate == "preflight" if validate_only else _gate == "delivery")

func validate_intent(actor: String, command: Dictionary) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	# Authority admission only; the provider never receives physical state.
	if not _roles.has(actor) or command.get("kind") == "local_action" and _state.gameplay_port == null:
		return _reject("invalid_decision_actor_or_kind")
	_actor = actor
	_gate = "preflight"
	work.authority_revalidations += 1
	var result: Dictionary = _roles[actor].apply(command, _token, true)
	_actor = ""
	_gate = ""
	return result

func perform_local_action(actor: String, command: Dictionary) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if _state.gameplay_port == null or command.get("kind") != "local_action":
		return _reject("personal_gameplay_not_enabled")
	var valid: Dictionary = validate_intent(actor, command)
	if not valid.ok:
		return valid
	_actor = actor
	_gate = "delivery"
	var result: Dictionary = _roles[actor].apply(command, _token)
	_gate = ""
	_actor = ""
	return result

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	if payload.size() != 1 or not payload.get("message_id") is String or not _messages.has(payload.message_id):
		return false
	var message: Dictionary = _messages[payload.message_id]
	return (message.kind == "COMMAND" or message.kind == "REPORT" and message.has("communication_holder")) and message.status == "PENDING" and id == message.get("event_ref", "communication_" + str(message.id)) and due == float(message.delivery_time)

func process_command(event: Dictionary) -> Dictionary:
	if float(event.time) != _state.time or not accepts_event(str(event.id), event.payload, float(event.time)):
		return {"changed": [], "retired": [], "record": _reject("stale_command")}
	var message: Dictionary = _messages[event.payload.message_id]
	if message.kind == "REPORT":
		_receive_report(message)
		return {"changed": [], "retired": [], "record": {"message_id": message.id, "status": message.status}}
	var execution_recipient: String = _message_recipient(message)
	var progress: String = _communication_step(message)
	if progress == "WAIT":
		message.communication_attempt += 1
		message.event_ref = "information_command_hop_" + str(message.id) + "_%d" % int(message.communication_attempt)
		_state.schedule_event(str(message.event_ref), float(message.delivery_time), "communication", {"message_id": message.id})
		return {"changed": [], "retired": [], "record": {"message_id": message.id, "status": "PENDING", "communication_status": message.communication_status}}
	if message.get("return_receipt", false):
		var known: Dictionary = message.execution_receipt
		message.status = known.status if progress == "ARRIVED" else "UNCONFIRMED"
		message.outcome = known.outcome.duplicate(true) if progress == "ARRIVED" else {"ok": false, "reason": "acknowledgement_overdue"}
		message.processed_at = known.processed_at if progress == "ARRIVED" else _state.time
		message.received_at = _state.time
		message.erase("execution_receipt")
		message_transition.emit(message.duplicate(true))
		return {"changed": [], "retired": [], "record": message.duplicate(true)}
	work.command_deliveries_processed += 1
	work.communication_events_processed += 1
	var result: Dictionary = _reject("communication_unreachable" if progress == "FAILED" else "channel_unavailable")
	var changed: Dictionary = {}
	var retired: Dictionary = {}
	if not _structure.active(str(message.recipient_ref)):
		result = _reject("retired_recipient")
	elif progress == "ARRIVED" and _channels[message.channel_ref].available:
		# All issue checks run again against the actual delivered-time authority.
		work.authority_revalidations += 1
		_actor = str(message.sender_ref)
		_gate = "preflight"
		result = _roles[_actor].apply(message.command, _token, true)
		if result.ok:
			var leaves: Array[String] = _roles[_actor].delivery_leaves(message.command)
			var prior: Dictionary = {}
			for leaf: String in leaves:
				var unit_id: String = str(_structure._nodes[leaf].unit_id)
				prior[_lod.representation_of(unit_id)] = true
			var before: int = int(_lod.work.leaf_records_materialized)
			_gate = "delivery"
			result = _roles[_actor].apply(message.command, _token)
			work.leaves_materialized_for_commands += int(_lod.work.leaf_records_materialized) - before
			if result.ok:
				for leaf: String in leaves:
					changed[_structure._nodes[leaf].unit_id] = true
					if _state.gameplay_port != null:
						var g: RefCounted = _state.gameplay_port.get_ref()
						var commanded: Dictionary = _state.units[_structure._nodes[leaf].unit_id]
						for member: String in commanded.get("gameplay_personnel", {}).get("members", {}):
							g.focus_continuity.event_relation(_actor, member, "delivered_command", str(message.id))
				for id: String in prior:
					if _state.units.has(id):
						changed[id] = true
					else:
						retired[id] = true
		_gate = ""
		_actor = ""
	message.status = "EXECUTED" if result.ok else "REJECTED"
	if message.has("communication_holder") and progress == "FAILED":
		message.status = "UNCONFIRMED"
	message.processed_at = _state.time
	message.outcome = {"ok": result.ok, "reason": "communication_receipt_overdue" if message.status == "UNCONFIRMED" else result.get("error", "executed_existing_role_input")}
	work.messages_delivered += int(result.ok)
	work.messages_failed += int(not result.ok)
	if message.has("communication_holder") and progress == "ARRIVED":
		message.execution_receipt = {"status": message.status, "outcome": message.outcome.duplicate(true), "processed_at": message.processed_at}
		message.status = "PENDING"
		message.erase("outcome")
		message.erase("processed_at")
		message.return_receipt = true
		message.outward_relay_receipts = message.relay_receipts
		message.relay_receipts = []
		message.communication_holder = execution_recipient
		message.communication_status = "AWAITING_RECEIPT"
		message.delivery_time = minf(float(message.sent_at) + float(_channels[message.channel_ref].physical.wait_seconds), _state.time + maxf(5.0, float(_channels[message.channel_ref].latency)))
		message.communication_attempt += 1
		message.event_ref = "information_command_hop_" + str(message.id) + "_%d" % int(message.communication_attempt)
		_state.schedule_event(str(message.event_ref), float(message.delivery_time), "communication", {"message_id": message.id})
		return {"changed": State.sorted_ids(changed), "retired": State.sorted_ids(retired), "record": {"message_id": message.id, "status": "PENDING", "communication_status": "AWAITING_RECEIPT"}}
	message_transition.emit(message.duplicate(true))
	return {"changed": State.sorted_ids(changed), "retired": State.sorted_ids(retired), "record": message.duplicate(true)}

func _report_before(a: Dictionary, b: Dictionary) -> bool:
	work.report_heap_comparisons += 1
	return float(a.delivery_time) < float(b.delivery_time) or a.delivery_time == b.delivery_time and str(a.id) < str(b.id)

func _push_report(message: Dictionary) -> void:
	if message.has("communication_holder"):
		# Physical hops must settle at their actual world deadline. Old fixed-delay
		# notifications keep the original noncausal heap contract.
		message.communication_attempt += 1
		message.event_ref = "information_report_hop_" + str(message.id) + "_%d" % int(message.communication_attempt)
		_state.schedule_event(str(message.event_ref), float(message.delivery_time), "communication", {"message_id": message.id})
		return
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
	while deliver_one_report(time):
		pass

func has_due_report(time: float) -> bool:
	return not _report_heap.is_empty() and float(_report_heap[0].delivery_time) <= time

func deliver_one_report(time: float) -> bool:
	if time != _state.time or not has_due_report(time):
		return false
	_receive_report(_pop_report())
	return true

func _receive_report(message: Dictionary) -> void:
	if message.status != "PENDING" or float(message.delivery_time) > _state.time:
		return
	var progress: String = _communication_step(message)
	if progress == "WAIT":
		_push_report(message)
		return
	if progress == "FAILED":
		message.status = "FAILED"
		message.failed_at = _state.time
		message.reason = "communication_unreachable"
		work.messages_failed += 1
		message_transition.emit(message.duplicate(true))
		return
	work.communication_events_processed += 1
	if _state.gameplay_port != null:
		var p: RefCounted = _state.gameplay_port.get_ref().participants
		var recipient: String = str(message.recipient_ref)
		if p.dead(recipient) and float(message.delivery_time) >= float(p._member(recipient).death.time):
			message.status = "FAILED"
			message.failed_at = message.delivery_time
			message.reason = "recipient_dead"
			work.messages_failed += 1
			message_transition.emit(message.duplicate(true))
			return
	if not _channels[message.channel_ref].available:
		message.status = "FAILED"
		message.failed_at = message.delivery_time
		message.reason = "channel_unavailable"
		work.messages_failed += 1
		message_transition.emit(message.duplicate(true))
		return
	message.status = "DELIVERED"
	message.received_at = message.delivery_time
	message.received_quality = float(_channels[message.channel_ref].quality)
	work.messages_delivered += 1
	var person: String = str(message.recipient_ref)
	_inboxes[person].append(message.id)
	_store_claims(message, person, float(message.delivery_time))
	message_transition.emit(message.duplicate(true))

func _store_claims(message: Dictionary, person: String, received_at: float, relayed: bool = false, direct: bool = false) -> void:
	for index: int in range(message.claims.size()):
		var claim: Dictionary = message.claims[index]
		var entry_id: String = str(message.id) + ("@" + person if relayed else "") + ":%d" % index
		if _entry_ids.has(entry_id):
			continue
		var entry: Dictionary = {"entry_id": entry_id, "holder_ref": person,
			"subject_ref": claim.subject_ref, "subject_kind": claim.subject_kind, "fact_kind": claim.fact_kind,
			"claimed_value": claim.value.duplicate(true), "observed_at": claim.observed_at,
			"created_at": message.created_at, "sent_at": message.sent_at, "received_at": received_at,
			"source_ref": claim.source_ref, "origin": claim.origin, "message_id": message.id,
			"reliability": float(claim.quality) * (1.0 if direct else float(_channels[message.channel_ref].quality)), "precision": claim.precision}
		_knowledge[person].append(entry)
		_entry_ids[entry.entry_id] = true
		var key: String = str(claim.subject_kind) + ":" + str(claim.subject_ref) + ":" + str(claim.fact_kind)
		if not _subjects[person].has(key):
			_subjects[person][key] = []
		_subjects[person][key].append(entry)
		work.knowledge_records_updated += 1

func knowledge(person: String, subject_kind: String = "", subject: String = "", fact: String = "", limit: int = MAX_QUERY, before: int = -1) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
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

func contact_status(person: String, kind: String, subject: String, expected_since: float = 0.0, fresh_seconds: float = 600.0, missing_seconds: float = 1200.0) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	# Missing reports describe this person's knowledge, never the subject's body.
	var latest: Dictionary = {}
	var previous: float = -1.0
	var observation: Dictionary = {}
	var facts: Array = ["unit_state", "objective"] if kind == "unit" else (["sea_status"] if kind == "vessel" else ["air_status", "air_service"])
	for fact: String in facts:
		for entry: Dictionary in knowledge(person, kind, subject, fact, 4).get("entries", []):
			if float(entry.reliability) <= 0.0:
				continue
			if float(entry.observed_at) > float(latest.get("observed_at", -1.0)):
				previous = maxf(previous, float(latest.get("observed_at", -1.0)))
				latest = entry
			elif entry.observed_at == latest.get("observed_at", -1.0) and int(entry.claimed_value.get("report_revision", 0)) > int(latest.get("claimed_value", {}).get("report_revision", 0)):
				latest = entry
			elif float(entry.observed_at) < float(latest.get("observed_at", -1.0)):
				previous = maxf(previous, float(entry.observed_at))
	for fact: String in ["friendly_contact", "unit_condition"] if kind == "unit" else ["friendly_sea_contact"] if kind == "vessel" else []:
		for entry: Dictionary in knowledge(person, kind, subject, fact, 4).get("entries", []):
			if float(entry.reliability) > 0.0 and float(entry.observed_at) > float(observation.get("observed_at", -1.0)):
				observation = entry
	var observed: float = float(latest.get("observed_at", -1.0))
	var age: float = _state.time - (observed if observed >= 0.0 else expected_since)
	var status: String = "UNREPORTED" if latest.is_empty() else "FRESH"
	if age >= missing_seconds:
		status = "OUT_OF_CONTACT"
	elif age >= fresh_seconds:
		status = "STALE" if not latest.is_empty() else "UNREPORTED"
	var value: Dictionary = latest.get("claimed_value", {})
	if value.get("status", "") == "SUNK" or value.get("asset_status", "") == "DESTROYED" or value.get("confirmed_loss", false):
		status = "CONFIRMED_LOSS"
	elif value.get("capability", "") == "UNAVAILABLE" or value.get("condition", "") == "INCAPACITATED":
		status = "CONFIRMED_UNAVAILABLE"
	elif age <= fresh_seconds and previous >= 0.0 and observed - previous > missing_seconds:
		status = "RECOVERED"
	if status in ["STALE", "OUT_OF_CONTACT", "UNREPORTED"] and not observation.is_empty() and _state.time - float(observation.observed_at) <= fresh_seconds:
		status = "OBSERVED_ONLY"
	if not observation.is_empty() and float(observation.observed_at) >= observed:
		if observation.claimed_value.get("condition", "") == "INCAPACITATED":
			status = "CONFIRMED_UNAVAILABLE"
		elif observation.claimed_value.get("confirmed_loss", false):
			status = "CONFIRMED_LOSS"
		elif int(observation.claimed_value.get("field_report_capabilities", -1)) == 0 and status == "OBSERVED_ONLY":
			status = "REPORT_SOURCE_UNAVAILABLE"
	if value.get("communication_status", "") == "FAILED" and status in ["STALE", "OUT_OF_CONTACT", "UNREPORTED"]:
		status = "COMMUNICATION_FAILED"
	var failure: String = ""
	var own: Array = _outboxes.get(person, [])
	for index: int in range(maxi(0, own.size() - 8), own.size()):
		var message: Dictionary = _messages[own[index]]
		var command: Dictionary = message.get("command", {})
		if message.kind == "COMMAND" and message.status == "REJECTED" and command.get("values", {}).get("subject_ref", "") == subject and message.get("outcome", {}).get("reason", "") in ["channel_unavailable", "communication_unreachable"] and float(message.get("processed_at", -1.0)) > observed:
			failure = str(message.id)
	if not failure.is_empty() and status in ["STALE", "OUT_OF_CONTACT", "UNREPORTED"]:
		status = "COMMUNICATION_FAILED"
	return {"status": status, "subject_kind": kind, "subject_ref": subject, "ever_reported": not latest.is_empty(),
		"report_observed_at": observed, "received_at": latest.get("received_at", -1.0), "source_ref": latest.get("source_ref", ""),
		"last_value": value.duplicate(true), "latest_observation": observation.get("claimed_value", {}).duplicate(true),
		"observation_time": observation.get("observed_at", -1.0), "failure_ref": failure,
		"stale_at": (observed if observed >= 0.0 else expected_since) + fresh_seconds,
		"missing_at": (observed if observed >= 0.0 else expected_since) + missing_seconds}

func inbox(person: String, limit: int = MAX_QUERY) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if not _roles.has(person) or limit < 1 or limit > MAX_QUERY:
		return _reject("invalid_mailbox_query")
	var result: Array[Dictionary] = []
	var ids: Array = _inboxes[person]
	for index: int in range(maxi(0, ids.size() - limit), ids.size()):
		work.knowledge_records_examined += 1
		result.append(_messages[ids[index]].duplicate(true))
	return {"ok": true, "holder_ref": person, "messages": result, "total_received": ids.size()}

func role_report(role: RefCounted) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	var person: String = role._player_id
	if _roles.get(person) != role or not role._binding_current():
		return _reject("information_binding_required")
	return {"person_id": person, "role": _structure._people[person].role, "current_position": _structure.command_person(person), "mode": "information_aware",
		"knowledge": knowledge(person), "inbox": inbox(person), "outbox": outbox(person)}

func outbox(person: String, limit: int = MAX_QUERY) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if not _roles.has(person) or limit < 1 or limit > MAX_QUERY:
		return _reject("invalid_outbox_query")
	var result: Array[Dictionary] = []
	var ids: Array = _outboxes[person]
	for index: int in range(maxi(0, ids.size() - limit), ids.size()):
		work.knowledge_records_examined += 1
		var metadata: Dictionary = _messages[ids[index]].duplicate(true)
		metadata.erase("claims")
		metadata.erase("command")
		metadata.erase("execution_receipt")
		metadata.erase("outward_relay_receipts")
		metadata.erase("relay_receipts")
		metadata.erase("event_ref")
		metadata.erase("communication_attempt")
		if metadata.kind == "COMMAND" and metadata.has("communication_status") and metadata.status == "PENDING":
			metadata.communication_status = "AWAITING_RECEIPT"
			metadata.erase("delivery_time")
		metadata.erase("return_receipt")
		if metadata.kind == "REPORT" and _messages[ids[index]].get("communication_holder", person) != person:
			metadata.status = "SENT"
			metadata.communication_status = "HANDED_TO_RELAY"
			metadata.erase("reason")
			metadata.erase("failed_at")
			metadata.erase("received_at")
			metadata.erase("delivery_time")
		metadata.erase("communication_holder")
		result.append(metadata)
	return {"ok": true, "holder_ref": person, "messages": result, "total_sent": ids.size()}

func snapshot() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
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
