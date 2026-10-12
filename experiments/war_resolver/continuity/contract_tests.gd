extends SceneTree
## Contract tests precede the opt-in route/cycle implementation.
const F = preload("res://experiments/war_resolver/spatial/fixtures.gd")
const Info = preload("res://experiments/war_resolver/information/service.gd")
const Decisions = preload("res://experiments/war_resolver/decision/service.gd")
const Adapter = preload("res://experiments/war_resolver/decision/adapter.gd")
const Keep = preload("res://experiments/war_resolver/decision/test_policy.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_delayed_route()
	_cycles()
	_urgent_cycle()
	print("Task9 continuity contracts: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func setup() -> Dictionary:
	var env: Dictionary = F.setup()
	var info: Info = Info.new()
	var channel: Dictionary = {"senders": ["company", "platoon", "squad"], "recipients": ["company", "platoon", "squad"], "latency": 15.0, "available": true, "quality": 1.0, "command_scope": "blue_company"}
	var source: Dictionary = {"observer_ref": "company", "scope_ref": "blue_company", "origin": "EXTERNAL", "quality": 0.5, "precision_km": 0.1, "fact_kinds": ["status"]}
	check(info.configure(env.state, env.lod, env.structure, env.logistics, env.roles, {"old": source}, {"command": channel}), "shared information admission")
	env.information = info
	return env

func request(id: String, target: String = "blue_platoon", path: Array = ["AB", "bridge_BD"]) -> Dictionary:
	return {"id": id, "channel_ref": "command", "command": {"id": id, "kind": "route_intent", "target": target, "values": {"path": path, "return_to_start": false}}}

func _delayed_route() -> void:
	var env: Dictionary = setup()
	check(not env.space.set_path("unit_000", ["AB"]).ok, "information-bound route cannot bypass delivery")
	var created: Dictionary = env.information.issue_command("company", request("route"))
	check(created.ok, "finite route intent accepted by existing command admission")
	check(env.state.units.unit_000.spatial.path.is_empty() and env.lod.work.leaf_records_materialized == 0, "admission changes no movement or representation")
	env.lod.advance(14.999)
	check(env.state.units.unit_000.distance_moved == 0.0, "delay does not execute early")
	env.lod.advance(15.0)
	check(created.ok and env.information._messages.route.status == "EXECUTED" if env.information._messages.has("route") else false, "exact delivered route execution")
	env.lod.advance(25.0)
	check(absf(float(env.state.units.unit_000.distance_moved) - 0.1) < 0.00000001, "delivered path uses hand-computed old movement/fuel kernel")
	var hidden: Dictionary = setup()
	hidden.space.schedule_fact("closed", 0.0, "bridge_BD", false)
	hidden.lod.advance(0.0)
	check(hidden.information.issue_command("company", request("unseen_closed")).ok, "admission does not reveal unknown edge availability")
	check(not hidden.information.issue_command("squad", request("illegal", "blue_platoon")).ok, "wrong scope rejected")
	var invalid: Dictionary = setup()
	var before: Dictionary = invalid.state.snapshot()
	check(not invalid.information.issue_command("company", request("unknown", "blue_platoon", ["unknown"])).ok, "unknown route rejected")
	check(not invalid.information.issue_command("company", request("disconnected", "blue_platoon", ["CD"])).ok, "noncontiguous route rejected")
	check(before == invalid.state.snapshot(), "invalid route is atomic")

func _cycles() -> void:
	var env: Dictionary = setup()
	var decisions: Decisions = Decisions.new()
	check(decisions.configure(env.state, env.information, env.structure, env.logistics), "shared decision admission")
	var policy: Keep = Keep.new()
	policy.mode = "keep"
	var provider: Adapter = Adapter.new()
	provider.configure("autonomous", policy)
	check(decisions.enroll("company", {"cadence": 300.0, "targets": ["blue_platoon"], "standing_orders": {}, "urgent": true}, provider), "registered finite person")
	check(decisions.has_method("start_cycle"), "bounded recurring opportunity contract exists")
	if not decisions.has_method("start_cycle"):
		return
	check(not decisions.start_cycle("company", "bad", 10.0, NAN, 1000.0, 3).ok, "NaN period rejected")
	check(not decisions.start_cycle("company", "bad", 10.0, 1.0, 1000.0, 3).ok, "period cannot evade cadence")
	check(decisions.start_cycle("company", "regular", 10.0, 315.0, 1000.0, 3).ok, "one regular opportunity admitted")
	check(not decisions.start_cycle("company", "duplicate", 10.0, 315.0, 1000.0, 3).ok and decisions._pending.size() == 1, "one current opportunity per person")
	env.lod.advance(1000.0)
	check(decisions.work.persons_examined == 3 and decisions._pending.is_empty(), "three actual evaluations and bounded end")
	check(decisions.result("regular_0").context.decision_time == 10.0 and decisions.result("regular_1").context.decision_time == 325.0 and decisions.result("regular_2").context.decision_time == 640.0, "explicit recurrence times preserved")
	check(not decisions.start_cycle("company", "expired", 1001.0, 315.0, 1000.0, 3).ok, "expired window rejected")
	check(decisions.start_cycle("company", "paused", 1100.0, 315.0, 3000.0, 3).ok and decisions.pause_cycle("company").ok, "explicit pause")
	env.lod.advance(3000.0)
	check(decisions.work.persons_examined == 3 and decisions._pending.is_empty(), "paused cycle does not invoke provider")
	check(decisions.start_cycle("company", "retiring", 3100.0, 315.0, 5000.0, 3).ok, "cycle admitted before retirement")
	env.structure._retired.blue_company = true
	env.lod.advance(5000.0)
	check(decisions.work.persons_examined == 3 and decisions._pending.is_empty(), "retired position never runs provider")
	check(not decisions.start_cycle("company", "retired", 5100.0, 315.0, 6000.0, 3).ok, "retired cycle admission rejected")

func _urgent_cycle() -> void:
	var env: Dictionary = setup()
	var decisions: Decisions = Decisions.new()
	check(decisions.configure(env.state, env.information, env.structure, env.logistics), "urgent shared decision admission")
	var policy: Keep = Keep.new()
	policy.mode = "keep"
	var provider: Adapter = Adapter.new()
	provider.configure("autonomous", policy)
	decisions.enroll("company", {"cadence": 300.0, "targets": ["blue_platoon"], "standing_orders": {}, "urgent": true}, provider)
	check(decisions.start_cycle("company", "regular", 200.0, 315.0, 1000.0, 3).ok, "regular future cycle")
	check(env.information.admit_external_observation({"id": "urgent", "source_ref": "old", "subject_kind": "unit", "subject_ref": "unit_000", "fact_kind": "status", "value": {"states": ["hold"]}, "observed_at": 0.0}).ok, "urgent source admitted")
	var admissions: int = 0
	for index: int in range(20):
		var id: String = "urgent_report_%d" % index
		check(env.information.send_report("company", {"id": id, "recipient_ref": "company", "channel_ref": "command", "observation_ids": ["urgent"]}).ok, "related received-message source")
		admissions += int(decisions.admit_urgent("company", id).ok)
	check(admissions == 1 and decisions._pending.size() == 1, "same-time emergency messages merge into one current ticket")
	env.lod.advance(1000.0)
	check(decisions.work.persons_examined == 3 and decisions.work.superseded_events_processed == 1 and decisions._pending.is_empty(), "urgent replacement preserves finite evaluation limit")
