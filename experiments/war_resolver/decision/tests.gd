extends SceneTree
const F = preload("res://experiments/war_resolver/decision/fixtures.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func _initialize() -> void:
	_isolation()
	_timing()
	_authority()
	_urgent()
	_domains()
	_scaling()
	_player_and_rejections()
	print("TASK8_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task8 decision: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func _isolation() -> void:
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup()
	for env: Dictionary in [a, b]:
		check(F.claim(env).ok and env.lod.advance(0.0).ok, "A known status receipt")
	b.state.units[b.lod.representation_of("unit_000")].position = 4.7
	b.state.units[b.lod.representation_of("unit_000")].ammunition = 0.0
	b.state.units[b.lod.representation_of("unit_000")].action = "withdraw"
	b.state.seed = 999
	var context: Dictionary = a.decisions.preview("platoon")
	check(context == b.decisions.preview("platoon"), "A no hidden truth context")
	check(a.adapters.platoon.evaluate(context) == b.adapters.platoon.evaluate(b.decisions.preview("platoon")), "A same knowledge same policy output")
	var before: Dictionary = a.state.snapshot()
	var lod: Dictionary = a.lod.counters()
	for index: int in range(100):
		var view: Dictionary = a.decisions.preview("platoon")
		view.received_claims[0].claimed_value.states[0] = "forged"
		check(a.readers.platoon.knowledge().entries[0].claimed_value.states[0] == "hold", "D query copy preserves knowledge")
	check(before == a.state.snapshot() and lod == a.lod.counters() and a.information._messages.size() == 1 and a.decisions.work.decision_events_processed == 0, "D no query action/time/random/materialization")
	var contexts: Dictionary = {}
	for person: String in ["soldier", "squad", "platoon", "company", "battalion", "regiment", "division"]:
		contexts[person] = a.decisions.preview(person)
		check(contexts[person].received_claims.is_empty() if person != "platoon" else contexts[person].received_claims.size() == 1, "G personal bounded information")
	check(contexts.soldier.output_kinds == ["keep"] and contexts.squad.command_kind == "tactical_intent" and "structure_request" in contexts.company.output_kinds, "G role output spaces")
	var player: F.Adapter = F.Adapter.new()
	check(player.configure("player", F.Policy.new()), "H player adapter")
	check(player.evaluate(context) == a.adapters.platoon.evaluate(context), "H same context same capability with nonempty knowledge")
	var proposal: Dictionary = a.adapters.platoon.evaluate(context)
	var reversed: Dictionary = context.duplicate(true)
	reversed.received_claims.reverse()
	check(proposal == player.evaluate(reversed), "H no reader/truth object in provider data")
	var plain: Dictionary = F.setup(40, 0, true, 71, false)
	var previewed: Dictionary = F.setup()
	for index: int in range(50):
		check(previewed.decisions.preview("division").ok, "S preview context")
	check(plain.lod.advance(120.0).ok and previewed.lod.advance(120.0).ok and plain.state.snapshot() == previewed.state.snapshot() and plain.lod.counters() == previewed.lod.counters(), "S complete observation invariance")
	evidence.A_D_G_H_S = {"role_contexts": contexts, "pure_preview_exact_world": true, "truth_reads": a.decisions.work.world_truth_reads_for_decision, "information_leaves": a.lod.work.leaf_records_materialized}

func _timing() -> void:
	var env: Dictionary = F.setup()
	check(F.claim(env).ok and F.opportunity(env).ok, "C E explicit opportunity admission")
	var mission: String = str(env.lod.preview_leaf("unit_000").mission_id)
	check(env.lod.advance(9.999).ok and env.decisions.work.decision_events_processed == 0, "C T epsilon no decision")
	check(env.lod.advance(10.0).ok, "C exact deadline")
	var decision: Dictionary = env.decisions.result("decision")
	check(decision.status == "ACCEPTED" and decision.command_delivery.status == "PENDING" and decision.context.decision_time == 10.0, "E decision accepted differs from delivered")
	check(env.lod.work.leaf_records_materialized == 0 and env.lod.preview_leaf("unit_000").mission_id == mission, "E decision zero materialization and old mission")
	check(float(env.lod.preview_leaf("unit_000").distance_moved) > 0.0 and decision.context.received_claims[0].observed_at == 0.0 and decision.proposal.intent.values.posture == "hold", "I moving current truth does not refresh stale hold claim")
	check(env.lod.advance(24.999).ok and env.lod.preview_leaf("unit_000").mission_id == mission, "E mission before delivery")
	check(env.lod.advance(25.0).ok and env.decisions.result("decision").command_delivery.status == "EXECUTED", "E Task7 exact transmission delivery")
	check(env.state.missions[env.state.units.unit_000.mission_id].posture == "hold", "E existing mission consequence")
	var old: Array = decision.context.received_claims
	check(F.claim(env, "newer", "platoon", "status", {"states": ["withdraw"]}, "instant", "external_company", 25.0).ok and env.lod.advance(25.0).ok, "B actual newer receipt")
	check(env.decisions.preview("platoon").command_ready_at == 145.0, "delivery execution cooldown remains visible personal authority metadata")
	check(F.opportunity(env, "next", "platoon", 145.0).ok and env.lod.advance(145.0).ok, "B later opportunity after both command cooldowns")
	check(env.decisions.result("next").status == "ACCEPTED" and env.decisions.result("next").context.received_claims.size() == 2 and old[0].observed_at == 0.0 and env.decisions.result("next").proposal.intent.values.posture == "withdraw", "B I new knowledge with old provenance")
	check(not F.opportunity(env, "too_soon", "platoon", 146.0).ok, "cadence boundary rejects early followup")
	var no_deadline: Dictionary = F.setup()
	check(F.claim(no_deadline).ok and no_deadline.lod.advance(120.0).ok and no_deadline.decisions.work.commands_issued_from_decision == 0 and no_deadline.lod.preview_leaf("unit_000").mission_id == mission, "K report has no automatic mission reaction")
	check(float(no_deadline.lod.preview_leaf("unit_000").distance_moved) > 0.0, "M standing mission continues")
	var conflict: Dictionary = F.setup()
	check(F.claim(conflict, "low", "platoon", "status", {"states": ["withdraw"]}).ok and F.claim(conflict, "high", "platoon", "status", {"states": ["hold"]}, "instant", "external_division").ok and conflict.lod.advance(0.0).ok, "J conflicting receipts")
	var history: Array = conflict.readers.platoon.knowledge().entries
	var context: Dictionary = conflict.decisions.preview("platoon")
	var expected: Dictionary = conflict.adapters.platoon.evaluate(context)
	context.received_claims.reverse()
	check(expected == conflict.adapters.platoon.evaluate(context) and expected.intent.values.posture == "hold" and history == conflict.readers.platoon.knowledge().entries, "J quality then times then stable ID; no history edits")
	for index: int in range(context.received_claims.size()):
		context.received_claims[index].reliability = 0.5
		context.received_claims[index].observed_at = 0.0
		context.received_claims[index].received_at = 0.0
	var tied: Dictionary = conflict.adapters.platoon.evaluate(context)
	context.received_claims.reverse()
	check(tied == conflict.adapters.platoon.evaluate(context), "J equal quality/time tie remains stable under reversed container")
	evidence.B_C_E_I_J_K_M = {"first": decision, "second": env.decisions.result("next"), "conflict_selected": expected, "standing_order_continues": true}

func _authority() -> void:
	var env: Dictionary = F.setup()
	check(F.claim(env).ok and F.opportunity(env).ok and env.lod.advance(10.0).ok, "F legal decision")
	check(env.commands.regiment.apply({"id": "move", "kind": "attach", "effective_time": 15.0, "values": {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0}}).ok and env.lod.advance(25.0).ok, "F before-delivery attachment")
	var result: Dictionary = env.decisions.result("decision")
	check(result.status == "ACCEPTED" and result.command_delivery.status == "REJECTED" and result.command_delivery.outcome.reason == "wrong_owner_or_layer", "F Task7 delivered-time authority retained")
	check(not env.state.schedule_event("fake", 30.0, "decision", {"decision_id": "unknown"}), "forged deadline rejected")
	var before: Dictionary = env.state.snapshot()
	check(not env.decisions.process_event({"id": "decision_decision", "time": 25.0, "payload": {"decision_id": "decision"}}).record.ok and before == env.state.snapshot(), "duplicate decision no execution")
	var soldier: Dictionary = F.setup()
	soldier.adapters.soldier._proposal = {"kind": "command", "command_kind": "mission", "target": "node_unit_000", "values": {"posture": "hold", "objective": 0.0, "direction": 1.0}, "channel_ref": "decision_channel"}
	soldier.adapters.soldier.source = "player"
	check(F.opportunity(soldier, "illegal", "soldier").ok and soldier.lod.advance(10.0).ok and soldier.decisions.result("illegal").status == "REJECTED" and soldier.decisions.work.commands_issued_from_decision == 0, "creation authority rejects ordinary officer intent")
	evidence.F = result

func _urgent() -> void:
	var env: Dictionary = F.setup()
	check(F.opportunity(env, "scheduled", "platoon", 200.0).ok and F.opportunity(env, "other", "company", 200.0).ok and F.claim(env, "urgent", "platoon", "status", {}, "delayed").ok, "L future person records")
	check(env.decisions.admit_urgent("platoon", "urgent").ok and not env.decisions.admit_urgent("company", "urgent").ok and not env.decisions.admit_urgent("platoon", "urgent").ok, "L explicit related-person bounded admission")
	check(env.decisions.preview("platoon").next_opportunity == 52.0 and env.decisions.preview("company").next_opportunity == 200.0 and env.decisions.work.urgent_decision_wakes == 1, "L only one person wake")
	check(env.lod.advance(47.0).ok and env.decisions.work.persons_examined == 0, "L report receipt not decision")
	check(env.lod.advance(51.999).ok and env.decisions.work.persons_examined == 0 and env.lod.advance(52.0).ok and env.decisions.work.persons_examined == 1, "L urgent lag exact separate opportunity")
	check(env.lod.advance(200.0).ok and env.decisions.work.persons_examined == 2 and env.decisions.work.superseded_events_processed == 1, "L superseded future event skips provider")
	evidence.L = env.decisions.snapshot()

func _domains() -> void:
	var logistics: Dictionary = F.setup()
	F.LogF.idle(logistics)
	F.policy(logistics, "company", "ammo")
	check(F.claim(logistics, "ammo_low", "company", "ammunition", {"level": "LOW"}).ok and logistics.lod.advance(0.0).ok, "N known ammo low")
	var before: Dictionary = F.LogF.stocks(logistics)
	check(F.opportunity(logistics, "supply", "company").ok and logistics.lod.advance(10.0).ok and F.LogF.stocks(logistics) == before, "N request no invented inventory")
	check(logistics.logistics._requests.input_supply.status == "REQUESTED", "N actual Task6 request")
	check(logistics.supply_commands.company.submit({"id": "shipment", "kind": "allocate", "request_id": "input_supply", "source_ref": "source", "delivery_time": 25.0}).ok and F.LogF.stocks(logistics) == before, "N Task6 shipment pending")
	check(logistics.lod.advance(25.0).ok and absf(F.LogF.stocks(logistics).ammunition - float(before.ammunition) - 10.0) < 0.000001, "N only Task6 receipt changes inventory")
	var structure: Dictionary = F.setup()
	F.LogF.idle(structure)
	F.policy(structure, "regiment", "attach")
	check(F.opportunity(structure, "attachment", "regiment").ok and structure.lod.advance(10.0).ok and structure.service.parent("node_unit_000") == "platoon_000" and structure.lod.work.leaf_records_materialized == 0, "O decision submission no relation/materialization")
	check(structure.lod.advance(19.999).ok and structure.service.parent("node_unit_000") == "platoon_000" and structure.lod.advance(20.0).ok and structure.service.parent("node_unit_000") == "blue_destination", "O Task5 exact future event")
	evidence.N_O = {"logistics": logistics.decisions.result("supply"), "structure": structure.decisions.result("attachment")}

func _scaling() -> void:
	var many: Dictionary = F.setup(40, 0, true, 71, true, 1000)
	for person: String in many.people:
		check(F.opportunity(many, "person_" + person, person, 10.0 if person in ["company", "platoon", "soldier"] else 100000.0).ok, "P distinct person pending")
	many.decisions.reset_work()
	check(many.lod.advance(120.0).ok and many.decisions.work.persons_examined == 3 and many.decisions.work.decision_events_processed == 3 and many.decisions.work.future_persons_examined == 0 and many.state.events.size() == 997, "P three due no person table scan")
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup(40, 10000)
	for env: Dictionary in [a, b]:
		check(F.claim(env).ok and F.opportunity(env).ok and env.lod.advance(120.0).ok, "Q active decision")
	check(a.decisions.work == b.decisions.work and a.state.counters == b.state.counters and a.lod.counters() == b.lod.counters() and F.LogF.stocks(a) == F.LogF.stocks(b), "Q exact sleeping world counters/outcomes")
	evidence.P_Q = {"1000_persons_work": many.decisions.work.duplicate(), "pending": many.state.events.size(), "sleeping_world_exact": true, "active_work": a.decisions.work.duplicate()}

func _player_and_rejections() -> void:
	var player: Dictionary = F.setup()
	var autonomous: Dictionary = F.setup()
	for env: Dictionary in [player, autonomous]:
		check(F.claim(env).ok and env.lod.advance(0.0).ok, "H actual nonempty source input")
	player.adapters.platoon.source = "player"
	player.adapters.platoon._proposal = player.adapters.platoon._policy.evaluate(player.decisions.preview("platoon")).intent
	for env: Dictionary in [player, autonomous]:
		check(F.opportunity(env).ok and env.lod.advance(120.0).ok, "H both source paths execute explicit deadline")
	check(player.decisions.result("decision").context == autonomous.decisions.result("decision").context and player.state.snapshot() == autonomous.state.snapshot(), "H identical context and causal effect; only source differs")
	check(player.decisions.result("decision").decision_source == "player" and autonomous.decisions.result("decision").decision_source == "autonomous", "H decision source distinct from input capability")
	for bad: Dictionary in [{"kind": "WIN_BATTLE"}, {"kind": "command", "command_kind": "mission", "target": "node_unit_000", "values": {"posture": "hold", "objective": NAN, "direction": -1.0}, "channel_ref": "decision_channel"}, {"kind": "keep", "combat_bonus": 1.0}]:
		var env: Dictionary = F.setup()
		env.adapters.platoon.source = "player"
		env.adapters.platoon._proposal = bad
		check(F.opportunity(env).ok and env.lod.advance(10.0).ok and env.decisions.result("decision").status == "REJECTED" and env.decisions.work.commands_issued_from_decision == 0 and env.lod.work.leaf_records_materialized == 0, "invalid/omniscient bonus output rejected before issue")
	var failed: Dictionary = F.setup()
	failed.information._channels.delayed.available = false
	check(F.opportunity(failed, "later", "platoon", 200.0).ok and F.claim(failed, "unavailable", "platoon", "status", {}, "delayed").ok and failed.decisions.admit_urgent("platoon", "unavailable").ok and failed.lod.advance(52.0).ok, "urgent unavailable fixture")
	check(failed.decisions.work.persons_examined == 0 and failed.decisions.work.commands_issued_from_decision == 0 and failed.decisions.result("urgent_platoon_unavailable").status == "SKIPPED_UNDELIVERED_REPORT", "undelivered report supplies no urgent decision input")
	evidence.H_extra = {"actual_player_autonomous_context_equal": true, "actual_player_autonomous_world_equal": true, "invalid_outputs_rejected": 3, "undelivered_urgent_skipped": true}
