extends RefCounted
## Sole mutable-world owner. Requests never contain an actor or game timestamp.
const World = preload("res://experiments/war_resolver/interactive_observer/bound_scenario.gd")
const Reader = preload("res://experiments/war_resolver/interactive_observer/reader.gd")
const MAX_IDS: int = 128
const MAX_CALLS: int = 10000000
const FRAME: int = 8192
var world: World = World.new()
var reader: Reader = Reader.new()
var sid: String = ""
var actor: String = ""
var quota: int = 31
var mode: String = "PAUSED"
var target: float = -1.0
var auto_end: float = -1.0
var auto_step: float = 30.0
var pause_requested: bool = false
var calls: int = 0
var focus: String = ""
var cache: Dictionary = {}
var receipts: Dictionary = {}
var receipt_ids: Array[String] = []
var unresolved: Array[String] = []
var last_seq: int = 0
var last_packet: Dictionary = {}
var last_response: Dictionary = {}
var closed: bool = false
var measure: bool = false
var projection: bool = true
var costs: Dictionary = {"construction_usec": 0, "reading_usec": 0, "input_usec": 0, "advance_usec": 0, "cleanup_usec": 0}

func configure(scene: String, seed_value: int, person: String, session_id: String, work_quota: int, options: Dictionary = {}) -> bool:
	if not sid.is_empty() or not valid_id(session_id) or work_quota not in [0, 1, 7, 31]:
		return false
	var started: int = Time.get_ticks_usec()
	actor = person
	sid = session_id
	quota = work_quota
	measure = bool(options.get("measure", false))
	projection = bool(options.get("projection", true))
	if not world.configure_bound(scene, seed_value, actor, options):
		return false
	if projection:
		reader.configure(world.env, actor)
	world.env.information.message_transition.connect(_message)
	world.env.gameplay.transition.connect(_personal)
	_refresh()
	costs.construction_usec = Time.get_ticks_usec() - started
	return true

static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 48:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

func _error(reason: String) -> Dictionary:
	return {"ok": false, "layer": "PROGRAM_STATUS", "error": reason}

func _program() -> Dictionary:
	return {"layer": "PROGRAM_STATUS", "session": sid, "clock": mode, "pending": world.env.state.public_pending(),
		"last_committed_time": cache.get("time", 0.0), "target": target, "auto_end": auto_end,
		"pause_requested": pause_requested, "input_ids": receipts.size(), "input_capacity": MAX_IDS, "closed": closed}

func handle(packet: Dictionary) -> Dictionary:
	if packet.size() != 4 or not packet.get("session") is String or not integer(packet.get("seq")) or not packet.get("op") is String or not packet.get("args") is Dictionary:
		return _error("invalid_envelope")
	if packet.session != sid:
		return _error("wrong_session")
	if packet.seq == last_seq:
		return last_response.duplicate(true) if packet == last_packet else _error("transport_id_conflict")
	if packet.seq != last_seq + 1:
		return _error("stale_or_out_of_order_frame")
	last_seq = int(packet.seq)
	last_packet = packet.duplicate(true)
	var result: Dictionary = request(str(packet.op), packet.args)
	result.program = _program()
	result.session = sid
	result.seq = last_seq
	last_response = result.duplicate(true)
	return result

func request(op: String, args: Dictionary) -> Dictionary:
	if closed:
		return _error("session_closed")
	if op == "quit" and args.is_empty():
		closed = true
		return {"ok": true, "layer": "PROGRAM_STATUS", "status": "CLOSING"}
	if op == "help" and args.is_empty():
		return {"ok": true, "commands": ["look", "status", "reports [before]", "events [before]", "receipts [before]", "focus subject", "personal id wait|take_cover", "intent id target hold|advance|withdraw node [edge,edge]", "intent id target cancel -", "advance seconds", "resume [calls]", "auto until [step]", "tick [calls]", "pause", "quit"]}
	if op in ["look", "status"] and args.is_empty():
		return {"ok": true, "person": cache.duplicate(true) if world.env.state.public_pending() else _read()}
	if op in ["reports", "events", "receipts"]:
		if args.size() != 1 or not integer(args.get("before")) or args.before < -1:
			return _error("invalid_page")
		if world.env.state.public_pending():
			return {"ok": true, "person": cache.duplicate(true), "page_note": "last committed page only while PENDING"}
		var page: Dictionary = reader.reports(args.before) if op == "reports" else (reader.events(args.before) if op == "events" else _receipt_page(args.before))
		return {"ok": true, "page": page} if page.get("ok", true) else _error("invalid_page_cursor")
	if op == "personal" or op == "intent":
		return _input(op, args)
	if op == "pause" and args.is_empty():
		pause_requested = world.env.state.public_pending()
		if not pause_requested:
			mode = "PAUSED"
		return {"ok": true, "status": "PAUSE_AT_COMMIT" if pause_requested else "PAUSED"}
	if world.env.state.public_pending() and op not in ["resume", "tick"]:
		return _error("PENDING_RETRY_WHEN_READY")
	if op == "focus" and args.size() == 1 and args.get("subject") is String:
		if args.subject not in _read().known_targets and args.subject != actor:
			return _error("unknown_focus_in_person_catalog")
		focus = args.subject
		return {"ok": true, "person": _read()}
	if op == "advance" and args.size() == 1 and number(args.get("seconds")):
		var end: float = world.env.state.time + float(args.seconds)
		if args.seconds < 0.0 or end > 86400.0 or mode == "AUTO":
			return _error("invalid_time_or_auto_active")
		target = end
		return _advance(1)
	if op == "auto" and args.size() == 2 and number(args.get("until")) and number(args.get("step")):
		if float(args.until) <= world.env.state.time or float(args.until) > 86400.0 or float(args.step) <= 0.0 or float(args.step) > 300.0:
			return _error("invalid_auto_plan")
		mode = "AUTO"
		auto_end = float(args.until)
		auto_step = float(args.step)
		target = -1.0
		return {"ok": true, "status": "AUTO_ARMED", "multiplier": "as fast as the bounded pump permits"}
	if op in ["resume", "tick"] and args.size() == 1 and integer(args.get("calls")) and args.calls >= 1 and args.calls <= 64:
		if not world.env.state.public_pending():
			if op == "tick" and mode == "AUTO":
				target = minf(auto_end, world.env.state.time + auto_step)
			else:
				return _error("nothing_to_resume")
		return _advance(args.calls)
	return _error("invalid_operation_or_shape")

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer(value: Variant) -> bool:
	return number(value) and absf(float(value)) <= 2147483647.0 and floorf(float(value)) == float(value)

func _input(op: String, args: Dictionary) -> Dictionary:
	if not args.get("id") is String or not valid_id(args.id):
		return _error("invalid_command_id")
	var choice: Dictionary
	if op == "personal":
		if args.size() != 2 or not args.get("action") is String or args.action not in ["wait", "take_cover"]:
			return _error("invalid_personal_shape")
		choice = {"kind": "local_action", "values": {"action": args.action}}
	else:
		if args.size() != 5 or not args.get("target") is String or args.target.length() > 48 or not args.get("intent") is String or args.intent not in ["hold", "advance", "withdraw", "cancel"] or not args.get("node") is String or args.node.length() > 48 or not args.get("path") is Array or args.path.size() > 64:
			return _error("invalid_goal_shape")
		for edge: Variant in args.path:
			if not edge is String or edge.length() > 48:
				return _error("invalid_path")
		choice = World._goal(World.F.intent(args.intent, args.node, args.path), args.target)
	return _submit_choice(op, args, choice)

func _submit_choice(op: String, args: Dictionary, choice: Dictionary) -> Dictionary:
	var id: String = str(args.id)
	var identity: Dictionary = {"op": op, "args": args.duplicate(true)}
	if world.env.state.public_pending():
		return _error("PENDING_RETRY_WHEN_READY")
	if receipts.has(id):
		if receipts[id].get("owner_ref", actor) != actor:
			return _error("command_id_already_used_in_session")
		return {"ok": true, "duplicate": true, "receipt": _visible_receipt(id)} if receipts[id].identity == identity else _error("command_id_conflict")
	if receipts.size() >= MAX_IDS:
		return _error("input_identity_capacity")
	var started: int = Time.get_ticks_usec() if measure else 0
	var event_id: String = "live_" + sid + "_" + id
	var receipt: Dictionary = {"id": id, "identity": identity, "event_id": event_id, "domain_id": "input_" + event_id,
		"owner_ref": actor, "received_at": world.env.state.time, "status": "REQUEST_RECEIVED", "intent": choice.duplicate(true)}
	receipts[id] = receipt
	receipt_ids.append(id)
	if projection:
		reader.own_input(id, world.env.state.time, choice)
	world.provider.proposal = choice.duplicate(true)
	var accepted: Dictionary = world.env.decisions.schedule(actor, event_id, world.env.state.time)
	var acknowledgment: Dictionary = {}
	if accepted.ok:
		receipt.status = "DECISION_SCHEDULED"
		acknowledgment = _visible_receipt(id)
		unresolved.append(id)
		target = world.env.state.time
		_advance(64)
	else:
		world.provider.proposal.clear()
		receipt.status = "INPUT_REJECTED"
		receipt.reason = "opportunity_or_cooldown"
		_refresh()
	if measure:
		costs.input_usec += Time.get_ticks_usec() - started
	return {"ok": true, "receipt": acknowledgment if world.env.state.public_pending() else _visible_receipt(id)}

func _advance(maximum: int) -> Dictionary:
	var started: int = Time.get_ticks_usec() if measure else 0
	var result: Dictionary = {}
	for index: int in range(maximum):
		if calls >= MAX_CALLS:
			mode = "BLOCKED"
			return _error("host_call_capacity")
		calls += 1
		result = world.env.lod.advance(target) if quota == 0 else world.env.lod.advance_bounded(target, quota)
		if not result.ok:
			mode = "BLOCKED"
			break
		if result.get("status", "COMPLETE") != "PENDING":
			_harvest()
			_refresh()
			if pause_requested or mode == "AUTO" and world.env.state.time >= auto_end:
				mode = "PAUSED"
				pause_requested = false
			target = -1.0
			break
	if measure:
		costs.advance_usec += Time.get_ticks_usec() - started
	return {"ok": bool(result.get("ok", false)), "status": "PENDING" if world.env.state.public_pending() else ("READY" if result.get("ok", false) else "BLOCKED"), "committed_time": cache.get("time", 0.0)}

func _harvest() -> void:
	for id: String in unresolved:
		var record: Dictionary = world.env.decisions.result(receipts[id].event_id)
		if record.get("status", "") == "PENDING":
			continue
		receipts[id].accepted_at = world.env.state.time
		receipts[id].accepted = record.get("status", "") == "ACCEPTED"
		receipts[id].status = "INPUT_REJECTED"
		if record.get("status", "") == "ACCEPTED":
			var issued: Dictionary = record.get("issued_input", {})
			var result: Dictionary = issued.get("result", {})
			receipts[id].status = "ISSUED_WAITING" if issued.get("domain", "") == "COMMUNICATION" and result.get("ok", false) else ("LOCAL_ADMITTED" if result.get("ok", false) else "INPUT_REJECTED")
			if result.has("delivery_time"):
				receipts[id].delivery_time = result.delivery_time
			if receipts[id].has("personal_feedback"):
				receipts[id].status = "ACTION_STARTED" if receipts[id].personal_feedback.kind == "personal_action_started" else "ACTION_FINISHED"
		else:
			receipts[id].reason = "intent_not_admitted"
	unresolved.clear()

func _message(message: Dictionary) -> void:
	if message.kind != "COMMAND" or message.sender_ref != actor or message.status == "PENDING":
		return
	for id: String in receipt_ids:
		if receipts[id].domain_id == message.id:
			receipts[id].status = "DELIVERED_ACCEPTED" if message.get("outcome", {}).get("ok", false) else "DELIVERED_REJECTED"
			receipts[id].processed_at = message.get("processed_at", message.delivery_time)
			receipts[id].reason = Reader.safe_reason(message.get("outcome", {}).get("reason", ""))
			break

func _personal(record: Dictionary) -> void:
	if record.get("view", "") != "PERSON_VISIBLE" or record.get("actor_ref", "") != actor:
		return
	for id: String in receipt_ids:
		if receipts[id].domain_id in record.get("cause_refs", []):
			receipts[id].personal_feedback = {"kind": record.kind, "effective_time": record.effective_time, "detail": record.detail.duplicate(true)}
			receipts[id].status = "ACTION_STARTED" if record.kind == "personal_action_started" else "ACTION_FINISHED"
			break

func _visible_receipt(id: String) -> Dictionary:
	var result: Dictionary = receipts[id].duplicate(true)
	result.erase("identity")
	result.erase("domain_id")
	result.erase("event_id")
	return result

func _receipt_page(before: int = -1) -> Dictionary:
	if before < -1 or before > receipt_ids.size():
		return {"ok": false}
	var end: int = receipt_ids.size() if before == -1 else mini(before, receipt_ids.size())
	var start: int = maxi(0, end - Reader.PAGE)
	var records: Array[Dictionary] = []
	for index: int in range(start, end):
		if receipts[receipt_ids[index]].get("owner_ref", actor) == actor:
			records.append(_visible_receipt(receipt_ids[index]))
	return {"records": records, "next_before": start if start > 0 else -1, "total": receipts.size()}

func _read() -> Dictionary:
	if not projection:
		return {"time": world.env.state.time, "view": "REFERENCE_WITHOUT_PROJECTION"}
	var started: int = Time.get_ticks_usec() if measure else 0
	var result: Dictionary = reader.view(_receipt_page().records, focus)
	if measure:
		costs.reading_usec += Time.get_ticks_usec() - started
	return result

func _refresh() -> void:
	cache = _read()

func dispose() -> void:
	var started: int = Time.get_ticks_usec()
	world.env.information.message_transition.disconnect(_message)
	world.env.gameplay.transition.disconnect(_personal)
	if projection:
		reader.dispose()
	world.dispose()
	closed = true
	costs.cleanup_usec = Time.get_ticks_usec() - started
