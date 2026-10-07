extends SceneTree
const F = preload("res://experiments/war_resolver/information/fixtures.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func _initialize() -> void:
	_reports()
	_queries_and_lod()
	_commands()
	_scaling_and_parity()
	_interactions_and_phases()
	_invalid()
	_mailbox_and_future_guard()
	print("TASK7_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task7 information: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func _reports() -> void:
	var env: Dictionary = F.setup()
	check(F.observation(env).ok and F.report(env).ok, "A report admission")
	check(env.readers.division.knowledge().entries.is_empty(), "B pending not knowledge")
	check(env.lod.advance(46.999).ok and env.readers.division.knowledge().entries.is_empty(), "B T minus epsilon")
	check(env.lod.advance(47.0).ok, "B exact report due")
	var entries: Array = env.readers.division.knowledge().entries
	check(entries.size() == 1 and entries[0].observed_at == 0.0 and entries[0].received_at == 47.0, "C preserved observation vs receipt")
	var old: Dictionary = env.lod.preview_leaf("unit_000")
	check(env.lod.advance(120.0).ok, "A truth advances")
	check(old.position != env.lod.preview_leaf("unit_000").position, "A physical truth changed")
	check(entries == env.readers.division.knowledge().entries, "A knowledge not refreshed")
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup()
	for item: Dictionary in [a, b]:
		check(F.observation(item).ok and F.report(item).ok, "B comparison admission")
	check(a.lod.advance(47.0).ok and a.lod.advance(120.0).ok and b.lod.advance(120.0).ok, "B segmented arrival")
	check(a.readers.division.knowledge().entries == b.readers.division.knowledge().entries, "B same delivered knowledge")
	# Two source claims disagree; even a known wrong value is not truth-corrected.
	check(F.external(env, "wrong").ok and F.report(env, "wrong_message", "wrong", "company", "division", "instant").ok, "D wrong external claim")
	check(F.external(env, "better", "external_division", "position", {"area_ref": "claimed_new_area", "band_km": [2.0, 3.0], "precision_km": 1.0}, 100.0).ok and F.report(env, "better_message", "better", "division", "division", "instant").ok and env.lod.advance(120.0).ok, "D conflicting claim receipt")
	entries = env.readers.division.knowledge().entries
	check(entries.size() == 3 and entries[1].claimed_value.area_ref == "claimed_new_area" and entries[2].claimed_value.area_ref == "claimed_old_area", "D conflicting history retained in stable message-ID order")
	check(entries[1].source_ref != entries[2].source_ref and entries[1].observed_at != entries[2].observed_at and entries[1].reliability != entries[2].reliability, "E source/time/quality distinct")
	var before: Dictionary = env.state.snapshot()
	check(F.external(env, "same_low", "external_company", "status", {"states": ["hold"]}, 120.0).ok and F.external(env, "same_high", "external_division", "status", {"states": ["hold"]}, 120.0).ok, "E equal value different quality")
	check(before == env.state.snapshot(), "E reliability never changes truth")
	check(F.report(env, "same_low_message", "same_low", "company", "division", "instant").ok and F.report(env, "same_high_message", "same_high", "division", "division", "instant").ok and env.lod.advance(120.0).ok, "E source reports delivered")
	entries = env.readers.division.knowledge().entries
	check(entries[-2].claimed_value == entries[-1].claimed_value and entries[-2].reliability != entries[-1].reliability, "E equal claims quality retained")
	var count: int = entries.size()
	check(not F.report(env).ok, "N duplicate message admission")
	env.information._receive_report(env.information._messages.report)
	check(env.readers.division.knowledge().entries.size() == count, "N replayed delivery idempotent")
	evidence.A_B_C_D_E_N = {"entries": entries, "knowledge_unchanged_without_new_report": true, "exact_delivery": 47.0}
	var failed: Dictionary = F.setup()
	check(F.observation(failed).ok and F.report(failed, "failed", "observation", "company", "division", "failed").ok and failed.lod.advance(47.0).ok, "channel failure at ETA")
	check(failed.information._messages.failed.status == "FAILED" and failed.readers.division.knowledge().entries.is_empty(), "unavailable channel no knowledge")

func _queries_and_lod() -> void:
	var env: Dictionary = F.setup(100)
	var before: Dictionary = env.state.snapshot()
	var lod_before: Dictionary = env.lod.counters()
	check(F.observation(env).ok, "G formation fact")
	check(F.observation(env, "leaf", "soldier", "unit", "unit_000", "position").ok, "H specific leaf estimate")
	check(env.information._observations.leaf.precision == "proxy_derived_estimate", "H explicit unresolved precision")
	check(env.state.snapshot() == before and env.lod.counters() == lod_before, "G H generation no observer effect")
	check(env.information.work.leaves_materialized_for_information == 0 and env.lod.work.leaf_records_materialized == 0, "G H zero leaves expanded")
	check(F.report(env, "direct", "leaf", "soldier", "soldier", "instant").ok and env.lod.advance(0.0).ok, "F direct receipt")
	before = env.state.snapshot()
	lod_before = env.lod.counters()
	var stored: Array = env.readers.soldier.knowledge().entries
	for index: int in range(100):
		var view: Dictionary = env.readers.soldier.knowledge()
		view.entries[0].claimed_value.area_ref = "mutated_copy"
		check(env.roles.soldier.report().knowledge.entries == stored, "F bounded role report no truth fallback")
	check(before == env.state.snapshot() and lod_before == env.lod.counters(), "F exact state/time/random/combat/materialization unchanged")
	check(not F.observation(env, "forbidden", "soldier", "formation", "blue_division").ok, "ordinary soldier no division truth")
	check(env.readers.division.knowledge().entries.is_empty(), "higher officer not automatically omniscient")
	var unobserved: Dictionary = F.setup(100, 0, true, 71, false)
	var observed: Dictionary = F.setup(100)
	check(F.observation(observed).ok and F.report(observed).ok, "R pure observation admission")
	check(unobserved.lod.advance(600.0).ok and observed.lod.advance(600.0).ok, "R observed/unobserved resolve")
	check(unobserved.state.snapshot() == observed.state.snapshot() and unobserved.lod.counters() == observed.lod.counters(), "R complete truth and operation equality at off-grid report ETA")
	evidence.F_G_H_R = {"formation_fact_reads": env.information.work.fact_records_examined, "information_materialized": env.information.work.leaves_materialized_for_information, "query_count": 100, "observed_unobserved_exact": true}

func _commands() -> void:
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup()
	var mission: String = str(a.lod.preview_leaf("unit_000").mission_id)
	for env: Dictionary in [a, b]:
		check(F.command(env).ok, "I issue command")
		check(env.lod.preview_leaf("unit_000").mission_id == mission, "I issue not effect")
		check(not env.roles.platoon.apply({"id": "bypass", "kind": "mission", "target": "node_unit_000", "values": {"posture": "hold", "objective": 0.0, "direction": 1.0}}).ok, "I direct role bypass rejected")
	check(a.lod.advance(30.0).ok and a.lod.preview_leaf("unit_000").mission_id == mission, "I old mission before ETA")
	check(a.lod.advance(47.0).ok, "K exact command delivery")
	check(a.information._messages.command.status == "EXECUTED" and a.state.missions[a.state.units.unit_000.mission_id].posture == "withdraw", "K existing mission input executed")
	check(a.lod.advance(120.0).ok and b.lod.advance(120.0).ok and F.causal(a) == F.causal(b), "K one-shot segmented causal state")
	var before: Dictionary = a.state.snapshot()
	check(not F.command(a).ok, "N duplicate command message")
	var duplicate: Dictionary = a.information.process_command({"id": "communication_command", "time": 120.0, "payload": {"message_id": "command"}})
	check(not duplicate.record.ok and before == a.state.snapshot(), "N duplicate command processing no execution")
	var invalid: Dictionary = F.setup()
	check(F.command(invalid).ok and invalid.commands.regiment.apply(F.Structure.request("attach", "attach", 30.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0})).ok and invalid.lod.advance(47.0).ok, "J authority changes before ETA")
	check(invalid.information._messages.command.status == "REJECTED" and invalid.state.missions[invalid.state.units.unit_000.mission_id].posture == "advance", "J delivered authority revalidated")
	var retired: Dictionary = F.setup(40, 0, false)
	F.Base.idle(retired)
	check(F.command(retired, "donor", "delayed", "platoon", "node_unit_001").ok and retired.commands.company.apply(F.Structure.request("merge", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"})).ok and retired.lod.advance(47.0).ok, "L command recipient retires")
	check(retired.information._messages.donor.status == "REJECTED" and retired.information._messages.donor.outcome.reason == "retired_recipient", "L explicit rejection no survivor redirect")
	evidence.I_J_K_L = {"valid": a.information._messages.command.duplicate(true), "authority_invalidated": invalid.information._messages.command.duplicate(true), "retired": retired.information._messages.donor.duplicate(true)}

func _scaling_and_parity() -> void:
	var local: Dictionary = F.setup()
	var world: Dictionary = F.setup(40, 10000)
	for env: Dictionary in [local, world]:
		check(F.observation(env).ok and F.report(env).ok and env.lod.advance(120.0).ok, "P sleeping comparison")
	check(local.information.work == world.information.work and local.state.counters == world.state.counters and local.lod.counters() == world.lod.counters(), "P active counters exact")
	var many: Dictionary = F.setup()
	check(F.observation(many).ok, "O one admitted source fact")
	for index: int in range(1000):
		check(F.report(many, "message_%04d" % index, "observation", "company", "division", "delayed" if index < 3 else "later").ok, "O pending admission")
	many.information.reset_work()
	check(many.lod.advance(120.0).ok, "O few due resolve")
	check(many.information.work.messages_delivered == 3 and many.information.work.future_messages_examined == 0 and many.information._report_heap.size() == 997, "O due-only work")
	var player: F.Decision = F.Decision.new()
	var autonomous: F.Decision = F.Decision.new()
	check(player.configure(local.readers.division) and autonomous.configure(world.readers.division), "Q identical reader capability")
	check(player.decision_input() == autonomous.decision_input(), "Q player AI knowledge parity")
	var input: Dictionary = player.decision_input()
	local.state.units[local.lod.representation_of("unit_000")].position = 1.75
	check(input == player.decision_input(), "Q hidden truth unavailable to decision path")
	evidence.O_P_Q = {"future_work": many.information.work.duplicate(), "pending": many.information._report_heap.size(), "sleeping_work_equal": true, "player_autonomous_input_equal": true}

func _interactions_and_phases() -> void:
	var env: Dictionary = F.setup(40, 0, false)
	F.Base.idle(env)
	check(F.observation(env, "old_leaf", "company", "unit", "unit_001", "status").ok and F.report(env, "history", "old_leaf", "company", "company", "instant").ok and env.lod.advance(0.0).ok, "S historical live subject report")
	var history: Array = env.readers.company.knowledge().entries
	check(F.observation(env, "private", "company", "unit", "unit_000", "position").ok and F.report(env, "personal", "private", "company", "platoon").ok, "M stable private recipient")
	check(env.commands.regiment.apply(F.Structure.request("move_office", "attach", 30.0, {"target": "platoon_000", "parent": "blue_company_b", "until": 90.0})).ok and env.lod.advance(47.0).ok, "M position effective relation changes")
	check(env.readers.platoon.knowledge().entries.size() == 1 and env.readers.recipient.knowledge().entries.is_empty(), "M person keeps private receipt no successor redirect")
	check(env.lod.advance(90.0).ok and env.commands.company.apply(F.Structure.request("merge", "merge", 90.0, {"survivor": "unit_000", "donor": "unit_001"})).ok and env.lod.advance(90.0).ok, "S identity retired")
	check(history == env.readers.company.knowledge().entries, "S historical identity survives retirement")
	check(not F.observation(env, "live_again", "company", "unit", "unit_001", "status").ok, "S retired subject not live truth")
	var stock: Dictionary = F.Base.stocks(env)
	check(F.external(env, "ample", "external_company", "ammunition", {"level": "AVAILABLE"}, 90.0).ok and F.report(env, "ample_report", "ample", "company", "company", "instant").ok and env.lod.advance(90.0).ok, "T logistics claim receipt")
	check(stock == F.Base.stocks(env), "T claim never modifies inventory")
	for fact: String in ["ammunition", "fuel", "readiness"]:
		check(F.observation(env, "logistics_" + fact, "company", "unit", "unit_000", fact).ok, "T actual bounded logistics observation")
	var historical_before: Array = env.readers.company.knowledge().entries
	check(env.commands.company.apply(F.Base.split(env)).ok and env.lod.advance(90.0).ok, "S real split with historical knowledge")
	check(historical_before == env.readers.company.knowledge().entries and F.observation(env, "new_identity", "company", "unit", "detachment", "status").ok, "S old history survives; new subject has real identity")
	check(env.commands.company.apply(F.Structure.request("rejoin", "merge", 90.0, {"survivor": "unit_000", "donor": "detachment"})).ok and env.lod.advance(90.0).ok, "S split merge identity continuation")
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup()
	for pair: Array in [[a, false], [b, true]]:
		var item: Dictionary = pair[0]
		if pair[1]:
			check(F.command(item).ok, "V command admitted first")
		check(F.observation(item).ok and F.report(item).ok, "V report due same timestamp")
		check(F.Base.delivery(item, "logistics", "unit", "unit_000", "AMMUNITION", 10.0, 47.0).ok, "V logistics same timestamp")
		check(item.commands.regiment.apply(F.Structure.request("attach", "attach", 47.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0})).ok, "V structure same timestamp")
		if not pair[1]:
			check(F.command(item).ok, "V command admitted last")
		check(item.lod.advance(47.0).ok, "V common boundary")
	check(F.causal(a) == F.causal(b) and a.readers.division.knowledge().entries == b.readers.division.knowledge().entries, "V insertion-order independent state/knowledge")
	check(a.information._messages.command.status == "REJECTED" and a.logistics._deliveries.logistics.status == "RECEIVED", "V old phases before command revalidation")
	evidence.M_S_T_V = {"historical_entries": history, "private_person_recipient": "platoon", "same_time_command": a.information._messages.command.status, "same_time_logistics": a.logistics._deliveries.logistics.status, "phase_insertion_order_equal": true}

func _invalid() -> void:
	var env: Dictionary = F.setup()
	var before: Dictionary = env.state.snapshot()
	check(not F.external(env, "future", "external_company", "position", {}, 1.0).ok, "future observation rejected")
	for value: Variant in [NAN, true, "1", -1.0, INF]:
		check(not env.information.admit_external_observation({"id": "invalid", "source_ref": "external_company", "subject_kind": "unit", "subject_ref": "unit_000", "fact_kind": "position", "value": {"area_ref": "x", "band_km": [value, 1.0], "precision_km": 0.5}, "observed_at": 0.0}).ok, "invalid bounded payload")
	check(not F.command(env, "soldier_order", "delayed", "soldier").ok, "ordinary soldier cannot issue officer mission")
	check(not env.state.schedule_event("smuggled", 47.0, "communication", {"message_id": "unknown"}), "forged command ticket")
	check(before == env.state.snapshot(), "invalid inputs do not mutate world")
	check(F.observation(env).ok, "history pagination source")
	for index: int in range(130):
		check(F.report(env, "history_%03d" % index, "observation", "company", "division", "instant").ok, "bounded historical admission")
	check(env.lod.advance(0.0).ok, "history pagination receipt")
	var page: Dictionary = env.readers.division.knowledge()
	check(page.entries.size() == 64 and page.total_matching == 130, "bounded newest knowledge page")
	page = env.readers.division.knowledge(int(page.next_before))
	check(page.entries.size() == 64 and page.next_before == 2, "bounded older history page")
	page = env.readers.division.knowledge(int(page.next_before))
	check(page.entries.size() == 2 and page.entries[0].message_id == "history_000", "oldest provenance still traceable")

func _mailbox_and_future_guard() -> void:
	var env: Dictionary = F.setup()
	check(F.observation(env).ok and F.report(env).ok and F.command(env).ok, "message center pending admission")
	var before: Dictionary = env.state.snapshot()
	env.information.deliver_reports_through(100000.0)
	env.information._receive_report(env.information._messages.report)
	check(env.readers.division.knowledge().entries.is_empty() and before == env.state.snapshot(), "future receipt cannot bypass world clock")
	check(env.readers.platoon.outbox().messages[0].status == "PENDING", "command pending status exposed only to sender")
	check(env.readers.soldier.outbox().messages.is_empty(), "personal outbox no other person commands")
	check(env.lod.advance(47.0).ok and env.readers.platoon.outbox().messages[0].status == "EXECUTED", "command outcome future presentation contract")
	var copied: Dictionary = env.readers.platoon.outbox()
	copied.messages[0].status = "forged"
	check(env.readers.platoon.outbox().messages[0].status == "EXECUTED", "outbox copy cannot modify delivery")
	var failed: Dictionary = F.setup()
	check(F.observation(failed).ok and F.report(failed, "failed_report", "observation", "company", "division", "failed").ok and F.command(failed, "failed_command", "failed").ok, "failed channel messages admitted")
	check(failed.lod.advance(47.0).ok and failed.readers.division.knowledge().entries.is_empty(), "failed report does not grant knowledge")
	check(failed.readers.company.outbox().messages[0].status == "FAILED" and failed.readers.platoon.outbox().messages[0].status == "REJECTED", "failure statuses explicit to sender")
	evidence.mailbox = {"failed_report": failed.readers.company.outbox().messages[0], "failed_command": failed.readers.platoon.outbox().messages[0], "future_guard": true}
