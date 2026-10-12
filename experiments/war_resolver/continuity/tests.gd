extends SceneTree
## Integrated assertions follow the preregistered facts and causal controls.
const Scenario = preload("res://experiments/war_resolver/continuity/scenario.gd")
const Policy = preload("res://experiments/war_resolver/continuity/policy.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func _initialize() -> void:
	_main()
	_information_controls()
	_resource_and_read_controls()
	_repeated_keep_cost()
	_trace()
	print("CONTINUITY_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task9 continuity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func make(seed_value: int = 71, options: Dictionary = {}) -> Scenario:
	var scenario: Scenario = Scenario.new()
	check(scenario.configure(seed_value, options), "synthetic combined admission")
	return scenario

func _main() -> void:
	var scenario: Scenario = make()
	var env: Dictionary = scenario.env
	check(scenario.advance(120.0).ok, "exact external bridge fact")
	check(env.information._messages.stale_order.status == "REJECTED" and env.information._messages.stale_order.outcome.reason == "wrong_owner_or_layer", "Task5 attachment rejects Task7 old command at delivery")
	check(env.structure.parent("node_unit_001") == "blue_destination" and env.structure._nodes.node_unit_001.parent == "blue_platoon", "effective relation differs from permanent membership")
	var route: Dictionary = env.state.units.unit_000.spatial.duplicate(true)
	check(route.edge == "bridge_BD" and float(route.progress) > 0.0 and float(route.progress) < 0.1, "bridge fact occurs during actual travel")
	var inventory: Dictionary = env.logistics.audit()
	scenario.advance(200.0)
	check(env.state.units.unit_000.spatial.progress == route.progress and inventory == env.logistics.audit(), "blocked travel consumes no extra distance or fuel")
	check(scenario.feedback.size() >= 2 and scenario.feedback[-1].kind == "BLOCKED" and scenario.feedback[-1].report_admitted, "qualified local source actually observes blockage")
	var blocked: Dictionary = env.information._observations[scenario.feedback[-1].id]
	check(blocked.value.state == "BLOCKED" and blocked.value.cause_ref == "bridge_cut", "observation has actual fact cause")
	scenario.advance(325.0)
	var second: Dictionary = env.decisions.result("regular_1")
	check(second.status == "ACCEPTED" and second.proposal.intent.kind == "command" and second.proposal.intent.values.path == ["AB", "AC", "CD"], "received blockage changes next finite-knowledge decision")
	check(second.command_delivery.status == "PENDING" and env.state.units.unit_000.spatial.progress == route.progress, "decision does not bypass transmission delay")
	check(second.context.received_claims[0].observed_at == 0.0, "old claim provenance never silently refreshed")
	scenario.advance(340.0)
	check(env.decisions.result("regular_1").command_delivery.status == "EXECUTED" and env.state.units.unit_000.spatial.returning, "delayed legal route begins real return along occupied leg")
	scenario.advance(670.0)
	var third: Dictionary = env.decisions.result("regular_2")
	check(third.status == "ACCEPTED" and third.proposal.intent.kind == "logistics_request" and third.issued_input.result.ok, "third round goes through original finite logistics request")
	check(scenario.host_receipts.size() == 1 and env.logistics._deliveries.allocation_input_regular_2.status == "RECEIVED", "finite external ETA response actually delivers once")
	check(env.logistics._depots.source.stock.AMMUNITION == 90.0, "actual warehouse stock reduced by ten")
	var final_output: Dictionary = scenario.advance(1800.0)
	check(final_output.ok and env.state.time == 1800.0 and env.decisions.work.persons_examined == 6 and env.decisions._pending.is_empty(), "registered officer completes finite multi-round run")
	check(env.state.units.unit_000.spatial.node == "D" and env.state.units.unit_000.distance_moved > 0.4, "actual route detour arrives without teleport or fuel refund")
	check(env.structure.parent("node_unit_001") == "blue_platoon" and env.structure.history.size() == 2, "temporary attachment expires with history")
	check(scenario.ledger_balanced(), "resource ledger conserved across all combined domains")
	check(env.information.work.leaves_materialized_for_information == 0 and env.lod.work.leaf_records_materialized == 2, "information is pure and structure/commands materialize only necessary leaves")
	check(env.decisions.work.commands_issued_from_decision == 2 and env.decisions.work.requests_issued_from_decision == 1, "repeated same task/report does not create command storm")
	evidence.main = {"physical": scenario.physical(), "decisions": env.decisions.snapshot(), "feedback": scenario.feedback, "logistics": env.logistics.snapshot(), "structure_history": env.structure.history, "last_events": final_output.events}

func _information_controls() -> void:
	var hidden: Scenario = make()
	var open: Scenario = make(71, {"bridge_cut": false})
	hidden.advance(140.0)
	open.advance(140.0)
	var known: Dictionary = hidden.env.decisions.preview("company")
	check(known == open.env.decisions.preview("company"), "hidden physical truth does not enter copied context")
	var a: Policy = Policy.new()
	var b: Policy = Policy.new()
	check(a.evaluate(known) == b.evaluate(open.env.decisions.preview("company")), "same knowledge gives same fresh provider input/output")
	var fast: Scenario = make()
	var slow: Scenario = make(71, {"report_latency": 347.0})
	for scenario: Scenario in [fast, slow]:
		scenario.advance(325.0)
	check(fast.env.decisions.result("regular_1").proposal.intent.kind == "command" and slow.env.decisions.result("regular_1").proposal.intent.kind != "command", "only report timing changes availability of reroute decision")
	check(slow.env.state.units.unit_000.spatial.blocked_edge == "bridge_BD" and slow.env.state.units.unit_000.spatial.returning == false, "slow knowledge cannot read truth and reroute early")
	for scenario: Scenario in [fast, slow]:
		scenario.advance(1800.0)
	check(slow.env.decisions.result("regular_2").proposal.intent.kind == "command", "later received report enters next legal opportunity")
	check(fast.ledger_balanced() and slow.ledger_balanced(), "report timing does not create inventory")
	evidence.information_control = {"fast_second": fast.env.decisions.result("regular_1"), "slow_second": slow.env.decisions.result("regular_1"), "slow_third": slow.env.decisions.result("regular_2"), "hidden_context_equal": true}

func _resource_and_read_controls() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		var supplied: Scenario = make(seed_value)
		var unsupplied: Scenario = make(seed_value, {"supply": false})
		var previewed: Scenario = make(seed_value)
		var before: Dictionary = previewed.env.state.snapshot()
		var counters: Dictionary = previewed.env.lod.counters()
		var context: Dictionary = previewed.env.decisions.preview("company")
		context.standing_orders.initial_path[0] = "forged"
		for index: int in range(5):
			previewed.env.decisions.preview("company")
		check(before == previewed.env.state.snapshot() and counters == previewed.env.lod.counters(), "preview has no physical side effect seed%d" % seed_value)
		for scenario: Scenario in [supplied, unsupplied, previewed]:
			scenario.advance(1800.0)
		check(supplied.physical() == previewed.physical(), "same-platform replay and pure preview exact seed%d" % seed_value)
		check(supplied.ledger_balanced() and unsupplied.ledger_balanced(), "finite resource control conserved seed%d" % seed_value)
		check(unsupplied.env.logistics._depots.source.stock.AMMUNITION == 100.0 and unsupplied.env.logistics._deliveries.is_empty(), "cancelled external supply keeps warehouse stock seed%d" % seed_value)
		check(float(supplied.env.state.units.unit_000.ammo_spent) > float(unsupplied.env.state.units.unit_000.ammo_spent), "combat ammo consequence comes from external supply seed%d" % seed_value)
	var reported: Scenario = make(71, {"bridge_cut": false, "observer": true})
	var silent: Scenario = make(71, {"bridge_cut": false, "observer": false})
	for scenario: Scenario in [reported, silent]:
		scenario.advance(1800.0)
	check(reported.physical() == silent.physical(), "no-cut physical reference unaffected by pure reports")
	var spam: Scenario = make()
	var claim: String = "old_bridge"
	for index: int in range(20):
		check(spam.env.information.send_report("company", {"id": "duplicate_%d" % index, "recipient_ref": "company", "channel_ref": "instant", "observation_ids": [claim]}).ok, "bounded repeated old claim admitted")
	spam.advance(1800.0)
	check(spam.env.decisions.work.commands_issued_from_decision == 2 and spam.env.decisions.work.requests_issued_from_decision == 1, "repeated semantic reports do not multiply inputs")

func _repeated_keep_cost() -> void:
	var cycling: Scenario = make(71, {"bridge_cut": false, "keep_only": true})
	var disabled: Scenario = make(71, {"bridge_cut": false, "keep_only": true, "repeated": false})
	for scenario: Scenario in [cycling, disabled]:
		scenario.advance(1800.0)
	var worst: float = 0.0
	for id: String in cycling.env.state.units:
		for key: String in ["effective", "casualties", "ammo_spent", "distance_moved"]:
			var lhs: float = float(cycling.env.state.units[id][key])
			var rhs: float = float(disabled.env.state.units[id][key])
			worst = maxf(worst, absf(lhs - rhs) / maxf(1.0, absf(rhs)))
	check(worst <= 0.02, "keep opportunity slicing stays within existing caller partition tolerance")
	check(cycling.ledger_balanced() and disabled.ledger_balanced(), "keep/disabled resource conservation")
	evidence.keep_cost = {"worst_relative": worst, "cycling_segments": cycling.env.state.counters.segments, "disabled_segments": disabled.env.state.counters.segments, "note": "keep is an explicit causal boundary; zero numerical cost is not claimed"}

func _trace() -> void:
	var scenario: Scenario = make()
	scenario.advance(1800.0)
	var records: Array[Dictionary] = scenario.trace.export()
	var ids: Dictionary = {}
	for record: Dictionary in records:
		ids[record.id] = record
	check(ids.has("bridge_cut") and ids.bridge_cut.time == 120.0, "trace identifies actual bridge time")
	check(ids.has("executed_stale_order") and ids.executed_stale_order.execution == "REJECTED" and ids.executed_stale_order.time == 47.0, "trace identifies delivered-time authority rejection")
	check(ids.has("regular_1") and ids.regular_1.cause_refs.size() == 1 and ids.has(ids.regular_1.cause_refs[0]), "decision references actually received claim")
	check(ids.has("executed_input_regular_1") and ids.executed_input_regular_1.time == 340.0 and ids.executed_input_regular_1.cause_refs == ["input_regular_1"], "trace separates issue and delivery")
	var known_block: bool = false
	for record: Dictionary in records:
		if record.kind == "report_received" and record.subject == "company" and record.id.begins_with("received_report_local_"):
			known_block = known_block or record.time > 120.0 and record.time < 325.0
	check(known_block and scenario.trace.timeline().contains("人物收到报告"), "readable timeline generated from actual facts")
	check(not scenario.trace.page(0, 257).ok and not scenario.trace.page(-1, 10).ok, "trace queries require bounded valid range")
	var timeline: String = scenario.trace.timeline()
	var before: Dictionary = scenario.env.state.snapshot()
	for index: int in range(5000):
		scenario.trace.append({"id": "diagnostic_%d" % index, "time": 1800.0, "subject": "diagnostic", "kind": "sample", "cause_refs": []})
	var page: Dictionary = scenario.trace.page()
	check(page.retained == 4096 and page.diagnostic_overwritten > 0 and scenario.env.state.snapshot() == before, "diagnostic ring bounded without deleting authority state")
	evidence.trace = {"records": records, "timeline": timeline, "diagnostic_capacity": 4096}
