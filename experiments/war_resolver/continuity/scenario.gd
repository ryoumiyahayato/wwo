extends RefCounted
## Finite synthetic host: initial inputs, actual local reports and finite ETA response.
const F = preload("res://experiments/war_resolver/spatial/fixtures.gd")
const Info = preload("res://experiments/war_resolver/information/service.gd")
const Decisions = preload("res://experiments/war_resolver/decision/service.gd")
const Adapter = preload("res://experiments/war_resolver/decision/adapter.gd")
const Policy = preload("res://experiments/war_resolver/continuity/policy.gd")
const Trace = preload("res://experiments/war_resolver/continuity/trace.gd")
var env: Dictionary
var options: Dictionary
var feedback: Array[Dictionary] = []
var host_receipts: Array[Dictionary] = []
var _sequence: int = 0
var trace: Trace = Trace.new()

func configure(seed_value: int = 71, supplied: Dictionary = {}) -> bool:
	options = {"bridge_cut": true, "report_latency": 47.0, "command_latency": 15.0, "supply": true, "repeated": true, "observer": true, "aggregate": true, "keep_only": false}
	options.merge(supplied, true)
	env = F.setup(true, true, false, seed_value, false, false, {"mobility": 0.08, "blue_ammunition": 4.0, "range_km": 0.05,
		"edge_ground": {"AC": F.ground("forest", 1.0), "CD": F.ground("slope", 0.0, 0.0, 0.2)}})
	trace.bind_state(env.state)
	env.lod.physical_event_sink = _capture_physical
	if options.aggregate:
		var pair: Array[String] = ["unit_000", "unit_001"]
		if not env.lod.coalesce("blue_platoon", pair).ok:
			return false
	if not options.repeated or options.keep_only:
		# Explicit initial route is trusted scenario input, not a policy truth read.
		var rep: String = env.lod.representation_of("unit_000")
		if not env.space.inject_path(rep, ["AB", "bridge_BD"]).ok:
			return false
	var sources: Dictionary = {"local": {"observer_ref": "squad", "scope_ref": "node_unit_000", "origin": "DIRECT", "quality": 0.9, "precision_km": 0.02, "fact_kinds": ["route", "ammunition"]},
		"old": {"observer_ref": "company", "scope_ref": "blue_company", "origin": "EXTERNAL", "quality": 0.5, "precision_km": 0.5, "fact_kinds": ["route"]}}
	var channels: Dictionary = {}
	var persons: Array[String] = F.State.sorted_ids(env.people)
	for pair: Array in [["instant", 0.0], ["report", options.report_latency], ["command", options.command_latency], ["stale", 47.0]]:
		channels[pair[0]] = {"senders": persons.duplicate(), "recipients": persons.duplicate(), "latency": pair[1], "available": true, "quality": 1.0, "command_scope": "blue_company"}
	var information: Info = Info.new()
	if not information.configure(env.state, env.lod, env.structure, env.logistics, env.roles, sources, channels):
		return false
	env.information = information
	information.observation_recorded.connect(_on_observation)
	information.message_transition.connect(_on_message)
	var decisions: Decisions = Decisions.new()
	if not decisions.configure(env.state, information, env.structure, env.logistics):
		return false
	env.decisions = decisions
	var provider: Adapter = Adapter.new()
	provider.configure("autonomous", Policy.new())
	if not decisions.enroll("company", {"cadence": 300.0, "targets": ["blue_platoon", "blue_destination"], "urgent": true, "command_kind": "route_intent",
		"standing_orders": {"subject": "unit_000", "target": "blue_platoon", "initial_path": ["AB", "bridge_BD"], "fallback_path": ["AB", "AC", "CD"], "keep_only": options.keep_only}}, provider):
		return false
	env.provider = provider
	trace.append({"id": "synthetic_initial_report", "time": 0.0, "subject": "synthetic_input", "kind": "initial_claim", "cause_refs": [], "scope": "bridge_BD"})
	if not information.admit_external_observation({"id": "old_bridge", "source_ref": "old", "subject_kind": "unit", "subject_ref": "unit_000", "fact_kind": "route",
		"value": {"edge_ref": "bridge_BD", "node_ref": "A", "state": "AVAILABLE", "cause_ref": "synthetic_initial_report"}, "observed_at": 0.0}).ok:
		return false
	if not information.send_report("company", {"id": "old_bridge_report", "recipient_ref": "company", "channel_ref": "instant", "observation_ids": ["old_bridge"]}).ok:
		return false
	if not _observe("ammunition", "initial_ammo", "instant"):
		return false
	if options.observer:
		env.space.route_feedback.connect(_on_feedback)
	decisions.input_issued.connect(_on_input)
	if options.repeated and not decisions.start_cycle("company", "regular", 10.0, 315.0, 1800.0, 6).ok:
		return false
	if not information.issue_command("platoon", {"id": "stale_order", "channel_ref": "stale", "command": {"id": "stale_order", "kind": "mission", "target": "node_unit_001", "values": {"posture": "hold", "objective": 0.0, "direction": 1.0}}}).ok:
		return false
	if not env.structure.submit("company", {"id": "temporary_attachment", "kind": "attach", "effective_time": 15.0, "values": {"target": "node_unit_001", "parent": "blue_destination", "until": 1500.0}}).ok:
		return false
	if options.bridge_cut and not env.space.schedule_fact("bridge_cut", 120.0, "bridge_BD", false).ok:
		return false
	return env.lod.advance(0.0).ok

func _observe(fact: String, id: String, channel: String) -> bool:
	var observed: Dictionary = env.information.observe("squad", {"id": id, "source_ref": "local", "subject_kind": "unit", "subject_ref": "unit_000", "fact_kind": fact})
	if not observed.ok:
		return false
	return env.information.send_report("squad", {"id": "report_" + id, "recipient_ref": "company", "channel_ref": channel, "observation_ids": [id]}).ok

func _on_feedback(unit_id: String, kind: String, cause_ref: String) -> void:
	if unit_id != env.lod.representation_of("unit_000"):
		return
	_sequence += 1
	var id: String = "local_%d" % _sequence
	var ok: bool = _observe("route", id, "report") and _observe("ammunition", id + "_ammo", "report")
	feedback.append({"id": id, "time": env.state.time, "subject": "unit_000", "kind": kind, "cause_ref": cause_ref, "report_admitted": ok})
	if feedback.size() > 256:
		feedback.pop_front()

func _on_input(person: String, decision_id: String, issued: Dictionary) -> void:
	var decision: Dictionary = env.decisions.result(decision_id)
	var selected: String = str(decision.proposal.get("selected_claim", ""))
	var causes: Array[String] = []
	if not selected.is_empty():
		causes.append("received_" + selected.split(":")[0])
	trace.append({"id": decision_id, "time": env.state.time, "subject": person, "kind": "decision", "cause_refs": causes,
		"input": decision.proposal.intent.kind, "input_result": issued.duplicate(true), "scope": decision.context.position_ref})
	if issued.domain == "LOGISTICS" and issued.result.ok:
		trace.append({"id": issued.id, "time": env.state.time, "subject": person, "kind": "logistics_request", "cause_refs": [decision_id], "scope": decision.context.position_ref, "execution": issued.result.status})
	if issued.domain != "LOGISTICS" or not issued.result.ok or not options.supply or env.logistics._used.has("allocation_" + str(issued.id)):
		return
	var result: Dictionary = env.logistics.submit(person, {"id": "allocation_" + str(issued.id), "kind": "allocate", "request_id": issued.id, "source_ref": "source", "delivery_time": env.state.time + 30.0})
	host_receipts.append({"id": "allocation_" + str(issued.id), "time": env.state.time, "cause_ref": decision_id, "result": result})
	if host_receipts.size() > 256:
		host_receipts.pop_front()
	trace.append({"id": "allocation_" + str(issued.id), "time": env.state.time, "subject": person, "kind": "allocation", "cause_refs": [decision_id], "execution": result.get("status", result.get("error", "")), "scope": "blue_platoon"})

func _on_observation(record: Dictionary) -> void:
	var causes: Array[String] = []
	if record.fact_kind == "route" and not str(record.value.cause_ref).is_empty():
		causes.append(str(record.value.cause_ref))
	trace.append({"id": "observation_" + str(record.id), "time": record.observed_at, "subject": record.observer_ref, "kind": "observation", "cause_refs": causes,
		"scope": record.subject_ref, "fact_kind": record.fact_kind, "value": record.value.duplicate(true), "source_ref": record.source_ref})

func _on_message(message: Dictionary) -> void:
	var received: bool = message.status != "PENDING"
	var causes: Array[String] = []
	if received:
		causes.append(str(message.id))
	elif message.kind == "REPORT":
		for claim: Dictionary in message.claims:
			causes.append("observation_" + str(claim.id))
	elif str(message.id).begins_with("input_"):
		causes.append(str(message.id).trim_prefix("input_"))
	var kind: String = ("report_received" if received else "report_sent") if message.kind == "REPORT" else ("command_result" if received else "command_sent")
	trace.append({"id": ("received_" if message.kind == "REPORT" and received else ("executed_" if received else "")) + str(message.id),
		"time": message.get("processed_at", message.delivery_time) if received else message.sent_at,
		"subject": message.recipient_ref if received else message.sender_ref, "kind": kind, "cause_refs": causes, "scope": message.recipient_ref,
		"execution": message.status, "outcome": message.get("outcome", {}).duplicate(true), "delivery_time": message.delivery_time})

func advance(target: float) -> Dictionary:
	var output: Dictionary = env.lod.advance(target)
	for event: Dictionary in output.get("events", []):
		_capture_physical(event)
	return output

func _capture_physical(event: Dictionary) -> void:
	if event.kind in ["decision", "communication"]:
		return
	var record: Dictionary = event.duplicate(true)
	var id: String = str(record.get("id", "physical_" + JSON.stringify(record).sha256_text().substr(0, 24)))
	var causes: Array[String] = []
	if record.has("cause_ref") and not str(record.cause_ref).is_empty():
		causes.append(str(record.cause_ref))
	if event.kind == "spatial":
		id = str(event.result.id)
	if event.kind == "logistics" and not str(event.result.get("request_id", "")).is_empty():
		causes.append(str(event.result.request_id))
	trace.append({"id": id, "time": record.time, "subject": record.get("unit_id", record.get("area_id", "world")), "kind": record.kind,
		"cause_refs": causes, "scope": record.get("scope", record.get("node_ref", "")), "execution": record.get("execution", "APPLIED"), "detail": record})

func ledger_balanced() -> bool:
	var ledger: Dictionary = env.logistics.audit()
	for key: String in ledger.initial:
		if absf(float(ledger.initial[key]) - float(ledger.current_plus_spent_and_transit[key])) > 0.000001:
			return false
	return true

func physical() -> Dictionary:
	var units: Dictionary = {}
	for id: String in F.State.sorted_ids(env.state.units):
		units[id] = env.state.units[id].duplicate(true)
	return {"time": env.state.time, "units": units, "totals": env.state.totals.duplicate(), "controls": env.lod.macro_summary().control, "ledger": env.logistics.audit()}
