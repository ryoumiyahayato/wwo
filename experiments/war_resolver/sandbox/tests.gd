extends SceneTree
const Session = preload("res://experiments/war_resolver/sandbox/session.gd")
const Sandbox = preload("res://experiments/war_resolver/sandbox/sandbox.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Scenarios = preload("res://experiments/war_resolver/sandbox/fixtures.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const RoleScenarios = preload("res://experiments/war_resolver/role_scenarios.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	_authority_selection()
	_observer_equivalence()
	_command_equivalence()
	_fixture_observations()
	await _scene_smoke()
	print("War sandbox: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _authority_selection() -> void:
	var unconfigured: Roles = Roles.new()
	_check(unconfigured.command_scope().error == "not_configured", "unconfigured selection rejected")
	for role: String in Roles.ROLES:
		var session: Session = Session.new()
		_check(session.reset("open_field_attack", 71, role), "role admission " + role)
		var before: Dictionary = session.states[Resolver.DETAILED].snapshot()
		var scope: Dictionary = session.scope()
		_check(scope.person_id == role and scope.role == role, "bound individual selection " + role)
		for kind: String in scope.targets:
			for target: String in scope.targets[kind]:
				var fresh: Session = Session.new()
				fresh.reset("open_field_attack", 71, role)
				var values: Dictionary = _values(kind)
				var result: Dictionary = fresh.submit(kind, target, values)
				_check(result[Resolver.DETAILED].ok and result[Resolver.AGGREGATE].ok, "authority eligible " + role + kind + target)
		var copied_scope: Dictionary = session.scope()
		copied_scope.targets.clear()
		_check(not session.scope().targets.is_empty(), "scope result detached")
		var rejected: Dictionary = session.submit("mission", "squad_defend_00", RoleScenarios.mission_values())
		_check(not rejected[Resolver.DETAILED].ok and rejected[Resolver.DETAILED].error == "wrong_owner_or_layer", "foreign scope rejected " + role)
		_check(before == session.states[Resolver.DETAILED].snapshot(), "selection/rejected commands read-only " + role)


static func _values(kind: String) -> Dictionary:
	if kind == "local_action":
		return {"action": "take_cover"}
	if kind == "tactical_intent":
		return {"posture": "support"}
	if kind == "coordination":
		return {"posture": "advance", "release_after": 600.0}
	return RoleScenarios.mission_values()


func _observer_equivalence() -> void:
	var resolver: Resolver = Resolver.new()
	for seed: int in [7, 71, 733]:
		for name: String in Scenarios.NAMES:
			var session: Session = Session.new()
			session.reset(name, seed, "ordinary_soldier")
			_check(session.states[Resolver.DETAILED].snapshot() == session.states[Resolver.AGGREGATE].snapshot(), "equivalent cloned inputs")
			var references: Dictionary = {}
			for policy: String in Session.POLICIES:
				references[policy] = Scenarios.create(name, seed)
			var initial: Dictionary = session.states[Resolver.DETAILED].snapshot()
			session.tick(16)
			_check(initial == session.states[Resolver.DETAILED].snapshot(), "paused scheduler has no authority")
			for sample: int in range(60):
				session.advance_samples()
				for policy: String in Session.POLICIES:
					var state: State = session.states[policy]
					resolver.resolve_until(references[policy], float(sample + 1) * Session.SAMPLE_SECONDS, policy)
					_check(state.snapshot() == references[policy].snapshot(), "observer equals direct resolver " + name + policy)
					var before: Dictionary = state.snapshot()
					var view: Dictionary = session.view(policy)
					view.state.units.clear()
					view.observation.tracks.clear()
					_check(state.snapshot() == before and not session.observations[policy].tracks.is_empty(), "view copy has no write authority")
			for policy: String in Session.POLICIES:
				var state: State = session.states[policy]
				_check(session.observations[policy].trace.size() <= Session.TRACE_LIMIT, "bounded trace")
				for id: String in State.sorted_ids(state.units):
					var unit: Dictionary = state.units[id]
					var origin: float = 0.5 if unit.side == "blue" else 3.5
					_check(is_equal_approx(float(unit.distance_moved), absf(float(unit.position) - origin)), "no default scenario movement loops " + name + id)
					_check(session.observations[policy].tracks[id].reversals == 0, "no default sampled reversals")
					_check(session.observations[policy].tracks[id].trail.size() <= Session.TRAIL_LIMIT, "bounded trail")
					_check(session.observations[policy].tracks[id].action_changes <= 4, "no repeated default command/action flipping " + name + id)
			if name == "road_bottleneck":
				while session.states[Resolver.DETAILED].time < 86400.0:
					var samples: int = mini(16, int((86400.0 - session.states[Resolver.DETAILED].time) / 120.0))
					session.advance_samples(samples)
				for policy: String in Session.POLICIES:
					for index: int in range(6):
						_check(session.states[policy].missions["mission_attack_%02d" % index].status == "complete", "bottleneck progresses without mission deadlock")
	var isolated: Session = Session.new()
	isolated.reset("open_field_attack", 71, "ordinary_soldier")
	isolated.states[Resolver.DETAILED].units.attack_00.position = 0.75
	_check(isolated.states[Resolver.AGGREGATE].units.attack_00.position == 0.5, "nested clones independent")


func _command_equivalence() -> void:
	var resolver: Resolver = Resolver.new()
	for role: String in Roles.ROLES:
		var session: Session = Session.new()
		session.reset("open_field_attack", 71, role)
		var scope: Dictionary = session.scope()
		var kind: String = str(scope.targets.keys()[0])
		var target: String = str(scope.targets[kind][0])
		var values: Dictionary = _values(kind)
		var accepted: Dictionary = session.submit(kind, target, values)
		for policy: String in Session.POLICIES:
			var state: State = Scenarios.create("open_field_attack", 71)
			var authority: Roles = Roles.new()
			authority.configure(state, RoleScenarios.hierarchy(), RoleScenarios.people(), role)
			_check(accepted[policy] == authority.apply(RoleScenarios.command("sandbox_0001", kind, target, values)), "same command result as direct authority")
			resolver.resolve_until(state, 3600.0, policy)
			# Matching partitions ensure rendering introduces no new settlement boundary.
			var reference: State = Scenarios.create("open_field_attack", 71)
			var partitioned: Roles = Roles.new()
			partitioned.configure(reference, RoleScenarios.hierarchy(), RoleScenarios.people(), role)
			partitioned.apply(RoleScenarios.command("sandbox_0001", kind, target, values))
			for step: int in range(30):
				resolver.resolve_until(reference, float(step + 1) * 120.0, policy)
			# Existing resource partition tolerances are covered by resolver/role suites.
			_check(absf(float(state.totals.casualties) - float(reference.totals.casualties)) < 0.01, "120s observation cadence compatible")
			var before: Dictionary = session.states[policy].snapshot()
			var snapshot: Dictionary = session.authorities[policy].snapshot()
			var blocked: Dictionary = session.authorities[policy].apply(RoleScenarios.command("early", kind, target, values))
			_check(not blocked.ok and blocked.error == "input_not_due", "role input cooldown")
			_check(before == session.states[policy].snapshot() and snapshot == session.authorities[policy].snapshot(), "early command atomic")
			# Save reference for comparison after common session advance.
			accepted[policy] = reference
		session.advance_samples(16)
		session.advance_samples(14)
		for policy: String in Session.POLICIES:
			_check(session.states[policy].snapshot() == accepted[policy].snapshot(), "input preserves autonomous resolver " + role)


func _fixture_observations() -> void:
	for policy: String in Session.POLICIES:
		var suppressed: Session = Session.new()
		suppressed.reset("suppression_recovery", 71, "ordinary_soldier")
		suppressed.advance_samples()
		_check(suppressed.states[policy].units.attack_00.action == "stalled", "suppression stalls exposed advance")
		for sample: int in range(59):
			suppressed.advance_samples()
		_check(suppressed.states[policy].missions.mission_attack_00.status == "complete", "suppression recovery avoids permanent wait")
		var withdrawal: Session = Session.new()
		withdrawal.reset("cohesion_withdrawal", 71, "ordinary_soldier")
		for sample: int in range(60):
			withdrawal.advance_samples()
		_check(withdrawal.states[policy].missions.mission_attack_00.status == "withdrawn" and withdrawal.states[policy].units.attack_00.position == 0.0, "cohesion retreat terminates at boundary")
		var reserve: Session = Session.new()
		reserve.reset("dependent_reserve", 71, "platoon_leader")
		var rejected: Dictionary = reserve.submit("mission", "squad_attack_01", RoleScenarios.mission_values())
		_check(not rejected[policy].ok and rejected[policy].error == "mission_has_dependents", "sandbox exposes dependency replacement limit")
		reserve.advance_samples(5)
		_check(reserve.states[policy].units.attack_00.action == "reserve" and reserve.states[policy].units.attack_00.position == 0.5, "time release cannot bypass mission dependency")
		for sample: int in range(55):
			reserve.advance_samples()
		_check(reserve.states[policy].missions.mission_attack_00.status == "complete", "dependent reserve eventually advances autonomously")


func _scene_smoke() -> void:
	var scene: PackedScene = load("res://experiments/war_resolver/sandbox/sandbox.tscn")
	var sandbox: Sandbox = scene.instantiate()
	# --script gives the dummy Window a 64px size; test real logical layout explicitly.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	viewport.add_child(sandbox)
	await process_frame
	await process_frame
	_check(sandbox.session.paused, "scene starts paused")
	_check(sandbox.panels[Resolver.AGGREGATE].canvas.get_global_rect().end.x <= viewport.size.x, "comparison panels fit 1280px logical viewport width")
	var initial: Dictionary = sandbox.session.states[Resolver.DETAILED].snapshot()
	sandbox.refresh()
	sandbox._on_tick()
	_check(initial == sandbox.session.states[Resolver.DETAILED].snapshot(), "render refresh and paused timer read-only")
	sandbox.role_choice.select(1)
	sandbox.reset_from_controls()
	_check(sandbox.session.role == "squad_leader" and sandbox.target_choice.get_item_text(0) == "squad_attack_00", "UI selection uses authority scope")
	sandbox.submit_from_controls()
	_check(sandbox.session.command_results[Resolver.DETAILED].ok, "UI accepted intent")
	sandbox.submit_from_controls()
	_check(sandbox.session.command_results[Resolver.DETAILED].error == "input_not_due", "UI exposes early rejection")
	sandbox.probe_rejection()
	_check(sandbox.panels[Resolver.DETAILED].detail.text.contains("REJECTED: wrong_owner_or_layer"), "UI exposes foreign rejection")
	sandbox.step_once()
	_check(sandbox.session.states[Resolver.DETAILED].time == 120.0, "single step uses resolver time")
	sandbox.toggle_pause()
	sandbox.speed_choice.select(1)
	sandbox._on_tick()
	_check(sandbox.session.states[Resolver.DETAILED].time == 600.0, "run/speed scheduler")
	sandbox.seed_input.text = "bad seed"
	sandbox.reset_from_controls()
	_check(sandbox.session.states[Resolver.DETAILED].time == 600.0 and sandbox.status.text.contains("RESET REJECTED"), "bad seed does not replace battle")
	sandbox.seed_input.text = "733"
	sandbox.scenario_choice.select(5)
	sandbox.role_choice.select(6)
	sandbox.reset_from_controls()
	_check(sandbox.session.seed == 733 and sandbox.session.scenario == "communication_delay" and sandbox.session.paused, "scenario/seed/person reset")
	_check(sandbox.session.states[Resolver.DETAILED].time == 0.0 and sandbox.session.authorities[Resolver.DETAILED].snapshot().accepted_ids.is_empty(), "new authority on reset")
	viewport.queue_free()
	await process_frame
