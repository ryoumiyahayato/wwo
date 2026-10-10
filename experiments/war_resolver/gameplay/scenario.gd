extends RefCounted
## Finite synthetic host: initial goals, external facts, qualified reports, intents.
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")
const Policy = preload("res://experiments/war_resolver/gameplay/policy.gd")
const Observation = preload("res://experiments/war_resolver/gameplay/observation.gd")
var env: Dictionary
var observation: Observation = Observation.new()
var name: String = ""
var variant: String = ""
var receipts: Array[Dictionary] = []
var _report_serial: int = 0
var _objective_sent: Dictionary = {}
var costs: Dictionary = {}

func configure(scene_name: String, seed_value: int = 71, supplied: Dictionary = {}) -> bool:
	if not env.is_empty() or scene_name not in ["S1", "S2", "S3"]:
		return false
	name = scene_name
	variant = str(supplied.get("variant", "autonomous"))
	if variant not in ["autonomous", "valid", "invalid", "condition", "reserve", "wait", "slow_reports", "no_supply"]:
		return false
	var config: Dictionary = {"background": true, "sleeping_areas": int(supplied.get("sleeping_areas", 0))}
	if name == "S2":
		config.range_km = 0.05
		config.report_latency = 500.0 if variant == "slow_reports" else 47.0
	if name == "S3":
		config.blue_point = "B"
		config.personal = true
		config.red_ammunition = 2000.0
		if variant == "condition":
			config.range_km = 0.5
	if name == "S1" and variant == "condition":
		config.blue_ammunition = 0.0
		config.red_ammunition = 0.0
	var started: int = Time.get_ticks_usec()
	env = F.setup(seed_value, config)
	costs.construction_admission_ms = (Time.get_ticks_usec() - started) / 1000.0
	observation.configure(env.state)
	env.gameplay.participants.debug_calculations = true
	env.information.observation_recorded.connect(observation.on_observation)
	env.information.message_transition.connect(observation.on_message)
	env.gameplay.transition.connect(observation.on_gameplay)
	env.gameplay.transition.connect(_on_goal)
	env.space.route_feedback.connect(_on_route)
	env.decisions.input_issued.connect(_on_input)
	env.lod.physical_event_sink = observation.physical
	started = Time.get_ticks_usec()
	for side: String in ["blue", "red"]:
		var ids: Array[String] = ["remote_" + side + "_0", "remote_" + side + "_1"]
		if not env.lod.coalesce("remote_" + side + "_platoon", ids, "platoon").ok:
			return false
	costs.initial_lod_ms = (Time.get_ticks_usec() - started) / 1000.0
	var target: String = "D" if name == "S2" else ("B" if name == "S3" else "A")
	var initial: Dictionary = F.intent("advance", target, ["AB", "bridge_BD"]) if name == "S2" else F.intent("hold", target)
	if not env.gameplay.admit_standing("unit_000", "standing_primary", "squad", initial).ok or not env.gameplay.admit_standing("unit_001", "standing_reserve", "platoon", F.intent("hold", "A")).ok:
		return false
	if name == "S2":
		if variant != "condition" and not env.space.schedule_fact("bridge_interruption", 60.0, "bridge_BD", false).ok:
			return false
		# A real delayed order loses authority before its delivery.
		if not F.command(env, "platoon", "old_authority", F.intent("advance", "D", ["AB", "bridge_BD"]), "node_unit_001").ok:
			return false
		if not env.structure.submit("company", {"id": "temporary_assignment", "kind": "attach", "effective_time": 5.0,
			"values": {"target": "node_unit_001", "parent": "blue_destination", "until": 900.0}}).ok:
			return false
	if name == "S3":
		if not F.report(env, "soldier", "soldier_local", "cover", "initial_cover", "soldier"):
			return false
		if not env.space.schedule_fact("persistent_bridge_damage", 60.0, "bridge_BD", false).ok:
			return false
		if not env.structure.submit("company", {"id": "post_withdraw_assignment", "kind": "attach", "effective_time": 900.0,
			"values": {"target": "node_unit_001", "parent": "blue_destination", "until": 1500.0}}).ok:
			return false
	if variant != "no_supply" and not _finite_supply(900.0 if name == "S3" else 300.0):
		return false
	var inputs: Dictionary = {}
	if name == "S1" or name == "S3":
		for actor: String in ["soldier", "squad", "company"]:
			inputs[actor] = [{"id": "standing_keep", "at": 10.0, "intent": {"kind": "keep"}}]
	if name == "S2":
		inputs.platoon = [{"id": "continue_standing", "at": 10.0, "require_route_state": "BLOCKED", "subject": "unit_000", "intent": {"kind": "keep"}}]
	if name == "S1" and variant in ["valid", "condition", "invalid", "reserve"]:
		var actor: String = "soldier" if variant == "invalid" else ("company" if variant == "reserve" else "squad")
		var destination: String = "blue_platoon" if variant == "reserve" else "node_unit_000"
		inputs[actor] = [{"id": "move_choice", "at": 10.0, "intent": _goal(F.intent("advance", "B", ["AB"]), destination)}]
	if name == "S2" and variant in ["valid", "slow_reports", "wait", "invalid"]:
		var actor: String = "platoon"
		var values: Dictionary = F.intent("hold", "B") if variant == "wait" else F.intent("advance", "D", ["AB", "AC", "CD"])
		inputs[actor] = [{"id": "received_route_choice", "at": 10.0, "require_route_state": "BLOCKED", "subject": "unit_000", "intent": _goal(values, "node_unit_002" if variant == "invalid" else "node_unit_000")}]
	if name == "S3":
		var withdraw: Dictionary = F.intent("withdraw", "C", ["AB", "AC"])
		inputs.squad = [{"id": "standing_extraction", "at": 180.0, "intent": _goal(withdraw)}]
		if variant in ["valid", "invalid"]:
			inputs["soldier" if variant == "valid" else "company"] = [{"id": "personal_choice", "at": 10.0, "intent": {"kind": "local_action", "values": {"action": "take_cover"}}}]
	for actor: String in supplied.get("inputs", {}):
		inputs[actor] = supplied.inputs[actor].duplicate(true)
	for actor: String in inputs:
		if not _enroll(actor, inputs[actor]):
			return false
	return advance(0.0).ok

static func _goal(values: Dictionary, target: String = "node_unit_000") -> Dictionary:
	return {"kind": "command", "command_kind": "goal_intent", "target": target, "values": values, "channel_ref": "command"}

func _enroll(actor: String, entries: Array) -> bool:
	if not env.people.has(actor) or entries.is_empty() or entries.size() > 16:
		return false
	var cadence: float = float(F.F.Roles.INPUT_SECONDS[F.F.Roles.ROLES.find(str(env.people[actor].role))])
	var first: float = INF
	var needs_report: bool = false
	for entry: Variant in entries:
		if not entry is Dictionary or not entry.get("id") is String or not (entry.get("at") is float or entry.get("at") is int) or float(entry.at) < 0.0 or not entry.get("intent") is Dictionary:
			return false
		first = minf(first, float(entry.at))
		needs_report = needs_report or entry.has("require_route_state")
	var provider: Policy = Policy.new()
	provider.source = "player" if actor == "soldier" or name != "S3" else "autonomous"
	if not env.decisions.enroll(actor, {"cadence": cadence, "targets": ["node_unit_000", "node_unit_001", "blue_platoon", "blue_destination", "blue_company"],
		"urgent": false, "command_kind": "goal_intent", "standing_orders": {"inputs": entries.duplicate(true)}}, provider):
		return false
	if entries.size() == 1 and not needs_report:
		return env.decisions.schedule(actor, "choice_" + actor, first).ok
	return env.decisions.start_cycle(actor, "opportunity_" + actor, first, cadence + 15.0, 1800.0, 64).ok

func _finite_supply(at: float) -> bool:
	var request: Dictionary = env.logistics.submit("platoon", {"id": "finite_request", "kind": "request", "target_kind": "unit",
		"target": "unit_000", "resource_class": "AMMUNITION", "quantity": 30.0})
	var allocation: Dictionary = env.logistics.submit("company", {"id": "finite_allocation", "kind": "allocate", "request_id": "finite_request", "source_ref": "source", "delivery_time": at}) if request.ok else request
	receipts.append({"request": request, "allocation": allocation, "at": at})
	observation.record({"event_id": "finite_supply_admission", "effective_time": 0.0, "learned_time": 0.0, "phase": 2,
		"kind": "finite_supply_reserved", "subject_ref": "unit_000", "cause_refs": ["finite_request"], "detail": receipts[-1]}, "company")
	return request.ok and allocation.ok

func _on_goal(record: Dictionary) -> void:
	if str(record.subject_ref) != "unit_000" or not record.kind.begins_with("goal_"):
		return
	var subject_ids: Array[String] = ["unit_000"]
	var signature: String = JSON.stringify(env.gameplay.visible_fact(subject_ids, "objective"))
	if _objective_sent.has(signature):
		return
	_objective_sent[signature] = true
	_report_serial += 1
	for recipient: String in ["squad", "platoon", "company"]:
		var id: String = "goal_report_%d_%s" % [_report_serial, recipient]
		assert(F.report(env, "squad", "local", "objective", id, recipient, "instant" if recipient == "squad" else "report"))

func _on_route(unit_id: String, kind: String, cause: String) -> void:
	if unit_id != "unit_000":
		return
	_report_serial += 1
	for recipient: String in ["squad", "platoon", "company", "soldier"]:
		var id: String = "route_report_%d_%s" % [_report_serial, recipient]
		assert(F.report(env, "squad", "local", "route", id, recipient, "instant" if recipient == "squad" else "report"))
	observation.record({"event_id": "route_feedback_%d" % _report_serial, "effective_time": env.state.time, "learned_time": null,
		"phase": -1, "kind": "local_route_feedback", "subject_ref": unit_id, "cause_refs": [cause], "detail": {"kind": kind}})

func _on_input(actor: String, id: String, result: Dictionary) -> void:
	var decision: Dictionary = env.decisions.result(id)
	observation.input(actor, id, env.state.time, decision.proposal, decision.context, {"creation_validation": decision.creation_validation, "issued": result})

func advance(target: float, quota: int = 0) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = F.advance(env, target, quota)
	costs.advance_ms = float(costs.get("advance_ms", 0.0)) + (Time.get_ticks_usec() - started) / 1000.0
	if quota == 0:
		for record: Dictionary in result.get("events", []):
			observation.physical(record)
	return result

func physical() -> Dictionary:
	if env.state.public_pending():
		return env.state.pending_view()
	var units: Dictionary = {}
	for id: String in F.F.State.sorted_ids(env.state.units):
		if not id.begins_with("sleep_"):
			units[id] = env.state.units[id].duplicate(true)
	return {"time": env.state.time, "units": units, "missions": env.state.missions.duplicate(true), "totals": env.state.totals.duplicate(),
		"prototype_rules": {"goals": env.gameplay.rules.duplicate(), "personal": env.gameplay.participants.rules.duplicate()}, "information_sources": env.information._sources.duplicate(true),
		"knowledge": env.information._knowledge.duplicate(true), "messages": env.information._messages.duplicate(true), "ledger": env.logistics.audit(),
		"decision_events": env.decisions._events.duplicate(true), "world_counters": env.state.counters.duplicate(), "gameplay_work": env.gameplay.work.duplicate(), "personal_work": env.gameplay.participants.work.duplicate(),
		"lod_groups": env.lod._groups.size(), "bridge_open": env.space.edge_view("bridge_BD").open}

func balanced() -> bool:
	if env.state.public_pending():
		return false
	var ledger: Dictionary = env.logistics.audit()
	for key: String in ledger.initial:
		if absf(float(ledger.initial[key]) - float(ledger.current_plus_spent_and_transit[key])) > 0.000001:
			return false
	for id: String in env.gameplay.participants._units.values():
		var unit: Dictionary = env.state.units[id]
		var capacity: float = float(unit.gameplay_personnel.anonymous)
		for member: Dictionary in unit.gameplay_personnel.members.values():
			capacity += float(member.health)
		if absf(capacity - float(unit.effective)) > 0.000001:
			return false
	return true

func dispose() -> void:
	env.lod.physical_event_sink = Callable()
	env.information.observation_recorded.disconnect(observation.on_observation)
	env.information.message_transition.disconnect(observation.on_message)
	env.gameplay.transition.disconnect(observation.on_gameplay)
	env.gameplay.transition.disconnect(_on_goal)
	env.space.route_feedback.disconnect(_on_route)
	env.decisions.input_issued.disconnect(_on_input)
	env.clear()
