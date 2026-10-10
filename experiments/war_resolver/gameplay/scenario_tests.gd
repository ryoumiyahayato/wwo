extends SceneTree
const Scenario = preload("res://experiments/war_resolver/gameplay/scenario.gd")
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")
const Policy = preload("res://experiments/war_resolver/gameplay/policy.gd")
var checks: int = 0
var failures: int = 0
var rows: Array[Dictionary] = []

func _initialize() -> void:
	var seeds: Array[int] = [71, 109]
	if "--holdout" in OS.get_cmdline_user_args():
		seeds.assign([347, 2027])
	for seed_value: int in seeds:
		_main(seed_value)
	if not "--holdout" in OS.get_cmdline_user_args():
		_information()
		_resources_and_pause()
		_projected_scope()
		_query_lod_world()
		_quota()
	print("GAMEPLAY_SCENARIOS=" + JSON.stringify(rows))
	print("Gameplay scenarios: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _run(name: String, variant: String, seed_value: int, quota: int = 0) -> Scenario:
	var scenario: Scenario = Scenario.new()
	print("RUN %s/%s seed=%d quota=%d" % [name, variant, seed_value, quota])
	check(scenario.configure(name, seed_value, {"variant": variant}), name + " input admission " + variant)
	check(scenario.advance(1800.0, quota).ok, name + " 1800s multiple feedback opportunities " + variant)
	check(scenario.balanced(), name + " finite-resource and member capacity ledger " + variant)
	check(scenario.observation.dropped == 0, name + " bounded complete scenario observation " + variant)
	var mission: Dictionary = F.current(scenario.env)
	rows.append({"scene": name, "variant": variant, "seed": seed_value, "quota": quota, "time": scenario.env.state.time,
		"primary": {"mission": mission.status, "goal": mission.goal_v1.duplicate(true), "xy": scenario.env.space.xy(scenario.env.state.units.unit_000),
			"distance": scenario.env.state.units.unit_000.distance_moved, "loss": scenario.env.state.units.unit_000.casualties,
			"ammo": scenario.env.state.units.unit_000.ammunition, "spent": scenario.env.state.units.unit_000.ammo_spent},
		"personal": scenario.env.gameplay.participants.view("soldier") if name == "S3" else {},
		"commands": _commands(scenario), "remote_groups": scenario.env.lod._groups.size(), "truth_events": scenario.observation.debug_records.size()})
	return scenario

func _commands(scenario: Scenario) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for message: Dictionary in scenario.env.information._messages.values():
		if message.kind == "COMMAND":
			result.append({"id": message.id, "sent": message.sent_at, "due": message.delivery_time, "status": message.status, "outcome": message.get("outcome", {})})
	return result

func _core(scenario: Scenario) -> Dictionary:
	var physical: Dictionary = scenario.physical()
	return {"units": physical.units, "missions": physical.missions, "totals": physical.totals}

func _main(seed_value: int) -> void:
	for name: String in ["S1", "S2", "S3"]:
		var automatic: Scenario = _run(name, "autonomous", seed_value)
		var valid: Scenario = _run(name, "valid", seed_value)
		var invalid: Scenario = _run(name, "invalid", seed_value)
		var changed: Scenario = _run(name, "condition", seed_value)
		check(_core(invalid) == _core(automatic), name + " rejected intent has zero physical effect under same opportunity clock")
		check(valid.env.decisions.work.world_truth_reads_for_decision == 0, name + " decision input has no world-truth reads")
		check(valid.env.lod._groups.size() == 2 and valid.env.lod.work.leaf_records_materialized == 0, name + " high-level or personal inputs do not expand remote armies")
		if name == "S1":
			check(float(automatic.env.state.units.unit_000.distance_moved) == 0.0 and F.current(automatic.env).status == "complete", "S1 zero player input completes local guard")
			check(automatic.env.state.areas.field.control == "contested" and F.current(automatic.env).goal_v1.local_condition, "S1 distant enemies and local guard coexist")
			check(float(valid.env.state.units.unit_000.distance_moved) > 0.0 and float(valid.env.state.units.unit_001.distance_moved) == 0.0, "S1 one squad intent changes only its actual deployment")
			check(float(changed.env.state.units.unit_000.casualties) == 0.0 and float(valid.env.state.units.unit_000.casualties) > 0.0, "S1 zero local ammunition changes main squad risk while remote war continues")
			var reserve: Scenario = _run(name, "reserve", seed_value)
			check(float(reserve.env.state.units.unit_001.distance_moved) > 0.0 and float(valid.env.state.units.unit_001.distance_moved) == 0.0, "S1 company assignment deploys existing reserve while squad choice retains it")
			check(float(reserve.env.state.totals.personnel) == float(valid.env.state.totals.personnel), "S1 reserve assignment cannot create personnel")
			reserve.dispose()
		elif name == "S2":
			check(F.current(automatic.env).status == "failed" and automatic.env.state.units.unit_000.spatial.node == "B", "S2 autonomous old known route actually blocks and terminates")
			check(F.current(valid.env).status == "complete" and valid.env.state.units.unit_000.spatial.node == "D", "S2 received report then one known fallback executes")
			check(F.current(changed.env).status == "complete" and float(changed.env.state.units.unit_000.distance_moved) < float(valid.env.state.units.unit_000.distance_moved), "S2 removing actual bridge interruption avoids detour cost")
			check(valid.env.information._messages.old_authority.status == "REJECTED" and float(valid.env.state.units.unit_001.distance_moved) == 0.0, "S2 attachment invalidates delivered old command without reversing accepted issue")
			var slow: Scenario = _run(name, "slow_reports", seed_value)
			var wait: Scenario = _run(name, "wait", seed_value)
			check(_last_command_time(slow) > _last_command_time(valid), "S2 slow information delays actual replanning command")
			check(wait.env.state.units.unit_000.spatial.node == "B" and F.current(wait.env).goal_v1.local_condition, "S2 wait choice changes task and retains actual blocked-node position")
			check(_last_command_time(valid) >= _first_block_received(valid), "S2 valid replan follows actual received report")
			slow.dispose()
			wait.dispose()
		else:
			var a: Dictionary = automatic.env.gameplay.participants.view("soldier")
			var b: Dictionary = valid.env.gameplay.participants.view("soldier")
			check(float(b.injury) > 0.0 and float(b.injury) < float(a.injury), "S3 one personal cover input lowers actual injury without immunity")
			check(F.current(valid.env).goal_v1.route_complete and not F.current(valid.env).goal_v1.effective_incoming_contact, "S3 extraction and true disengagement occur")
			check(F.current(changed.env).goal_v1.route_complete and F.current(changed.env).goal_v1.effective_incoming_contact, "S3 greater actual enemy reach means completed extraction still receives fire")
			var before: float = float(valid.env.state.units.unit_000.casualties)
			check(valid.advance(3600.0).ok and float(valid.env.state.units.unit_000.casualties) == before, "S3 no damage from obsolete contact after disengagement")
			check(not valid.env.space.edge_view("bridge_BD").open and valid.env.structure.history.size() >= 2, "S3 bridge damage and later actual structure transitions persist")
		automatic.dispose()
		valid.dispose()
		invalid.dispose()
		changed.dispose()

func _last_command_time(scenario: Scenario) -> float:
	var latest: float = -1.0
	for message: Dictionary in scenario.env.information._messages.values():
		if message.kind == "COMMAND" and message.id != "old_authority":
			latest = maxf(latest, float(message.sent_at))
	return latest

func _first_block_received(scenario: Scenario) -> float:
	for claim: Dictionary in scenario.env.information._knowledge.platoon:
		if claim.fact_kind == "route" and claim.claimed_value.state == "BLOCKED":
			return float(claim.received_at)
	return INF

func _information() -> void:
	var blocked: Scenario = Scenario.new()
	var clear: Scenario = Scenario.new()
	var same_script: Array = [{"id": "received_route_choice", "at": 10.0, "require_route_state": "BLOCKED", "subject": "unit_000", "intent": Scenario._goal(F.intent("advance", "D", ["AB", "AC", "CD"]))}]
	check(blocked.configure("S2", 71, {"variant": "valid"}) and clear.configure("S2", 109, {"variant": "condition", "inputs": {"platoon": same_script}}), "hidden-condition context pair")
	check(blocked.advance(100.0).ok and clear.advance(100.0).ok, "physical hidden interruption has happened before commander knows")
	var a: Dictionary = blocked.env.decisions.preview("platoon")
	var b: Dictionary = clear.env.decisions.preview("platoon")
	check(a == b, "same received knowledge and permission yield identical provider inputs despite different truth and seed")
	var policy_a: Policy = Policy.new()
	var policy_b: Policy = Policy.new()
	check(policy_a.evaluate(a) == policy_b.evaluate(b), "hidden truth cannot select a known best detour")
	check(blocked.advance(1800.0).ok, "feedback world finishes")
	var no_supply: Scenario = _run("S2", "no_supply", 71)
	var count: int = 0
	var first: float = INF
	for value: Dictionary in no_supply.env.information._observations.values():
		if value.fact_kind == "route" and value.value.state == "BLOCKED":
			count += 1
			first = minf(first, float(value.observed_at))
	check(count == 4 and first < 300.0, "first route obstruction is reported locally once per recipient without supply wake")
	check(no_supply.env.logistics._deliveries.is_empty(), "no-supply request policy never creates stock")
	blocked.dispose()
	clear.dispose()
	no_supply.dispose()

func _resources_and_pause() -> void:
	for fuel: float in [0.0, 8.0]:
		var env: Dictionary = F.setup(71, {"motor": true, "fuel": fuel, "range_km": 0.0, "blue_ammunition": 0.0, "red_ammunition": 0.0})
		check(env.gameplay.admit_standing("unit_000", "fuel_goal", "squad", F.intent("advance", "C", ["AC"])).ok, "finite fuel goal")
		check(F.advance(env, 900.0).ok, "fuel execution result")
		check(float(env.state.units.unit_000.distance_moved) == 0.0 if fuel == 0.0 else float(env.state.units.unit_000.distance_moved) > 0.0, "fuel shortage changes actual movement")
		if fuel == 0.0:
			check(F.current(env).goal_v1.reason == "fuel_exhausted", "fuel failure is explicitly located")
	var suppressed: Dictionary = F.setup(71, {"blue_ammunition": 0.0, "red_ammunition": 400.0, "range_km": 0.5})
	for id: String in ["unit_002", "unit_003"]:
		suppressed.state.units[id].weapon.rounds_per_minute = 20.0
		suppressed.state.units[id].weapon.lethality = 0.0
	check(suppressed.gameplay.admit_standing("unit_000", "pressure", "squad", F.intent("advance", "C", ["AC"])).ok, "physical suppression fixture")
	check(F.advance(suppressed, 60.0).ok and suppressed.state.units.unit_000.action == "stalled", "actual fire pressure pauses advance")
	check(F.advance(suppressed, 1200.0).ok and float(suppressed.state.units.unit_000.distance_moved) > 0.0, "finite enemy rounds allow automatic later recovery")
	var env: Dictionary = F.setup(71)
	var before: Dictionary = env.state.snapshot()
	var bad: Dictionary = F.intent("advance", "B", ["AB"])
	bad.casualties = 99.0
	check(not F.command(env, "squad", "outcome_setter", bad).ok and env.state.snapshot() == before, "intent cannot specify outcomes or produce denied physical effects")

func _query_lod_world() -> void:
	var baseline: Scenario = Scenario.new()
	var observed: Scenario = Scenario.new()
	check(baseline.configure("S3", 71, {"variant": "valid"}) and observed.configure("S3", 71, {"variant": "valid"}), "query and LOD worlds")
	check(baseline.advance(600.0).ok and observed.advance(600.0).ok, "committed observation boundary")
	var before: Dictionary = _core(observed)
	var random_before: Dictionary = observed.env.state.random_state.duplicate()
	for actor: String in ["soldier", "company", "squad"]:
		var query: Dictionary = observed.observation.person(actor)
		query.records.clear()
		observed.env.roles[actor].report()
		observed.env.roles[actor].command_scope()
	check(observed.env.space.load_cell("field").ok and observed.env.space.unload_cell("field").ok, "geometry view opens and closes locally")
	check(before == _core(observed) and random_before == observed.env.state.random_state, "pure query and focus preserve physical state and RNG")
	check(observed.env.lod.zoom_in("cell_038").ok, "one remote cell expands through existing LOD authority")
	check(not observed.env.space.edge_view("bridge_BD").open, "view and LOD cannot restore bridge damage")
	check(observed.advance(1800.0).ok and baseline.advance(1800.0).ok, "unobserved and observed regions continue")
	check(observed.env.state.units.unit_000 == baseline.env.state.units.unit_000, "remote LOD switch cannot reward not observing local battlefield")
	check(observed.balanced() and baseline.balanced(), "LOD cannot restore resources or personal capacity")
	check(float(observed.env.state.totals.casualties) > float(before.totals.casualties), "other active area continues after local disengagement and closing view")
	baseline.dispose()
	observed.dispose()

func _projected_scope() -> void:
	var env: Dictionary = F.setup(71, {"reserve_posture": "hold", "extra_local": 16})
	var ids: Array[String] = ["unit_000", "unit_001"]
	for index: int in range(16):
		ids.append("local_extra_%02d" % index)
	check(env.lod.coalesce("blue_platoon", ids, "platoon").ok, "capacity counterexample starts with legal remote-style proxy")
	var before: Dictionary = env.state.snapshot()
	var result: Dictionary = F.command(env, "company", "too_many_local", F.intent("hold", "A"), "blue_platoon")
	check(not result.ok and result.error == "gameplay_scope_capacity_after_materialization", "batch admission checks resulting detail count, not just pre-command proxies")
	check(env.state.snapshot() == before and env.lod.work.leaf_records_materialized == 0, "over-envelope high input rejects atomically before materialization")

func _quota() -> void:
	for name: String in ["S1", "S2", "S3"]:
		var reference: Dictionary = {}
		for quota: int in [0, 1, 7, 31]:
			var scenario: Scenario = _run(name, "valid", 71, quota)
			var physical: Dictionary = scenario.physical()
			for key: String in ["world_counters", "gameplay_work", "personal_work"]:
				physical.erase(key)
			if quota == 0:
				reference = physical
			else:
				check(physical == reference, name + " normal/quota formal physical, knowledge, permissions and ledger results exact")
			scenario.dispose()
	var pending: Scenario = Scenario.new()
	check(pending.configure("S3", 71, {"variant": "valid"}), "pending query world")
	var result: Dictionary = pending.env.lod.advance_bounded(1800.0, 1)
	check(result.status == "PENDING" and pending.observation.person("soldier").status == "PENDING" and pending.env.gameplay.participants.view("soldier").status == "PENDING", "PENDING never exposes a half settled person or timeline")
	check(F.advance(pending.env, 1800.0, 31).ok, "pending world remains resumable")
	pending.dispose()
