extends SceneTree
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const Fixtures = preload("res://experiments/war_resolver/role_scenarios.gd")
var checks: int = 0
var failures: int = 0
var resolver: RefCounted = Resolver.new()


func _initialize() -> void:
	_admission()
	_permissions()
	_atomic_validation()
	_layers_and_boundaries()
	_no_input_and_scale()
	_consistency()
	_coordination_consistency()
	print("Role overrides: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _audit_state(state: State) -> Dictionary:
	var result: Dictionary = state.snapshot()
	result.event_ids = state.event_ids.duplicate()
	result.area_units = state.area_units.duplicate(true)
	result.touched_units = state.touched_units.duplicate()
	result.touched_areas = state.touched_areas.duplicate()
	return result


func _service(state: State, role: String) -> RefCounted:
	var result: RefCounted = Roles.new()
	_check(result.configure(state, Fixtures.hierarchy(), Fixtures.people(), role), "admit " + role)
	return result


func _admission() -> void:
	for defect: String in ["cycle", "wrong_side", "duplicate_unit", "wrong_position", "duplicate_position", "unknown_player"]:
		var state: State = Scenarios.create()
		var nodes: Dictionary = Fixtures.hierarchy()
		var people: Dictionary = Fixtures.people()
		var player: String = "ordinary_soldier"
		if defect == "cycle": nodes.division_blue.parent = "squad_attack_00"
		if defect == "wrong_side": nodes.squad_attack_00.side = "red"
		if defect == "duplicate_unit": nodes.squad_attack_01.unit_id = "attack_00"
		if defect == "wrong_position": people.ordinary_soldier.formation_id = "company_blue0"
		if defect == "duplicate_position": people.duplicate = people.squad_leader.duplicate(true)
		if defect == "unknown_player": player = "missing"
		var service: RefCounted = Roles.new()
		var before: Dictionary = _audit_state(state)
		_check(not service.configure(state, nodes, people, player), "reject admission " + defect)
		_check(before == _audit_state(state), "admission atomic " + defect)
		_check(service.configure(state, Fixtures.hierarchy(), Fixtures.people(), "ordinary_soldier"), "failed admission retry " + defect)


func _permissions() -> void:
	var own: Dictionary = Fixtures.people()
	for role: String in Roles.ROLES:
		var rank: int = Roles.ROLES.find(role)
		var owner: String = str(own[role].formation_id)
		for kind: String in ["local_action", "tactical_intent", "mission", "coordination", "set_resolution", "spawn_soldier"]:
			var targets: Array[String] = [role, "squad_attack_00", "squad_attack_01", "squad_attack_03", "platoon_blue00", "company_blue0", "battalion_blue", "regiment_blue", "division_blue", "battalion_red", "missing"]
			for target: String in targets:
				var state: State = Scenarios.create()
				var service: RefCounted = _service(state, role)
				var values: Dictionary = Fixtures.mission_values()
				if kind == "local_action": values = {"action": "step_forward"}
				if kind == "tactical_intent": values = {"posture": "hold"}
				if kind == "coordination": values = {"posture": "advance", "release_after": 120.0}
				var nodes: Dictionary = Fixtures.hierarchy()
				var child: bool = nodes.has(target) and nodes[target].get("parent", "") == owner
				var expected: bool = (kind == "local_action" and rank == 0 and target == role or
					kind == "tactical_intent" and rank == 1 and target == owner or
					kind in ["mission", "coordination"] and rank >= 2 and (child or rank >= 3 and target == owner))
				var before: Dictionary = _audit_state(state)
				var adapter_before: Dictionary = service.snapshot()
				var result: Dictionary = service.apply(Fixtures.command("permission", kind, target, values))
				_check(bool(result.ok) == expected, "ownership/layer " + role + " " + kind + " " + target)
				if not expected:
					_check(before == _audit_state(state) and adapter_before == service.snapshot(), "no partial mutation " + role + " " + target)
				else:
					_check(state.units.size() == 10, "command never instantiates combat units")
					_check(result.next_input_at == Roles.INPUT_SECONDS[rank], "rank-specific input interval")
		var state: State = Scenarios.create()
		var service: RefCounted = _service(state, role)
		var report_before: Dictionary = _audit_state(state)
		var report: Dictionary = service.report()
		_check(_audit_state(state) == report_before, "report is read-only " + role)
		_check(report.person_id == role and report.role == role, "report bound person")
		if rank == 0:
			_check(not report.has("formations"), "soldier only own local record")
		else:
			_check(not report.has("units") and not report.has("totals"), "no global or individual dump")
			for target: String in report.formations:
				_check(target == owner or Fixtures.hierarchy()[target].parent == owner, "report only owned/direct child")
				_check(not report.formations[target].has("unit_ids"), "high reports aggregate leaf records")


func _atomic_validation() -> void:
	var invalid: Array[Dictionary] = []
	for field: String in ["objective", "direction"]:
		for value: Variant in [NAN, INF, "2", null, -100.0, 100.0]:
			var values: Dictionary = Fixtures.mission_values()
			values[field] = value
			invalid.append(Fixtures.command("bad", "mission", "company_blue0", values))
	for extra: String in ["policy", "resolution", "spawn", "unit_id", "person_id"]:
		var command: Dictionary = Fixtures.command("bad", "mission", "company_blue0", Fixtures.mission_values())
		command[extra] = "DETAILED"
		invalid.append(command)
	for values: Dictionary in [{}, {"posture": "teleport", "objective": 2.0, "direction": 1.0}, {"posture": "advance", "objective": 2.0, "direction": 1.0, "position": 3.0}]:
		invalid.append(Fixtures.command("bad", "mission", "company_blue0", values))
	for value: Variant in [NAN, INF, -1.0, 86401.0, "0", null]:
		invalid.append(Fixtures.command("bad", "coordination", "company_blue0", {"posture": "advance", "release_after": value}))
	for command: Dictionary in invalid:
		var state: State = Scenarios.create()
		var service: RefCounted = _service(state, "battalion_commander")
		var before: Dictionary = _audit_state(state)
		var adapter_before: Dictionary = service.snapshot()
		_check(not service.apply(command).ok, "reject malformed values")
		_check(before == _audit_state(state) and adapter_before == service.snapshot() and state.event_ids.is_empty(), "malformed command atomic")
	# Collision on the last leaf must not leave earlier leaves modified.
	for kind: String in ["mission", "coordination"]:
		var state: State = Scenarios.create()
		var service: RefCounted = _service(state, "division_commander")
		if kind == "mission":
			state.missions.role_collision_attack_05 = state.missions.mission_attack_05.duplicate(true)
		else:
			state.event_ids.role_release_collision_attack_05 = true
		var before: Dictionary = _audit_state(state)
		var adapter_before: Dictionary = service.snapshot()
		var values: Dictionary = Fixtures.mission_values() if kind == "mission" else {"posture": "advance", "release_after": 120.0}
		_check(not service.apply(Fixtures.command("collision", kind, "regiment_blue", values)).ok, "last leaf collision rejected")
		_check(before == _audit_state(state) and adapter_before == service.snapshot(), "last leaf rejection atomic")
	var state: State = Scenarios.create()
	state.set_coordination("attack_03", {"after": ["mission_attack_05"]})
	var service: RefCounted = _service(state, "division_commander")
	var before: Dictionary = _audit_state(state)
	var adapter_before: Dictionary = service.snapshot()
	var dependent: Dictionary = service.apply(Fixtures.command("prerequisite", "mission", "regiment_blue", Fixtures.mission_values("advance", 1.75)))
	_check(not dependent.ok and dependent.error == "mission_has_dependents", "prerequisite migration rejected explicitly")
	_check(before == _audit_state(state) and adapter_before == service.snapshot(), "last squad dependency rejection atomic")
	resolver.resolve_until(state, 3600.0)
	_check(state.coordination.attack_03.status == "assigned" and float(state.units.attack_03.position) > 0.5, "rejected replacement leaves autonomous dependency release working")


func _layers_and_boundaries() -> void:
	var state: State = Scenarios.create()
	var soldier: RefCounted = _service(state, "ordinary_soldier")
	var before: Dictionary = _audit_state(state)
	_check(soldier.apply(Fixtures.command("local", "local_action", "ordinary_soldier", {"action": "step_forward"})).ok, "own local action accepted")
	_check(before == _audit_state(state), "personal local action cannot move squad or change mission/combat")
	_check(soldier.report().personal_action.position == 0.505, "one personal offset represented")
	var squad: RefCounted = _service(state, "squad_leader")
	var original: String = str(state.units.attack_00.mission_id)
	_check(squad.apply(Fixtures.command("hold", "tactical_intent", "squad_attack_00", {"posture": "hold"})).ok, "squad tactical hold accepted")
	_check(state.units.attack_00.mission_id == original and state.missions[original].objective == 2.0, "tactical intent cannot replace assigned mission")
	resolver.resolve_until(state, 30.0)
	_check(state.units.attack_00.position == 0.5 and float(state.units.attack_01.position) > 0.5, "tactical intent influences only own squad movement")
	var cooldown_before: Dictionary = _audit_state(state)
	var adapter_before: Dictionary = squad.snapshot()
	_check(not squad.apply(Fixtures.command("early", "tactical_intent", "squad_attack_00", {"posture": "advance"})).ok, "early repeated input rejected")
	_check(cooldown_before == _audit_state(state) and adapter_before == squad.snapshot(), "cooldown rejection atomic")
	resolver.resolve_until(state, 60.0)
	_check(squad.apply(Fixtures.command("early", "tactical_intent", "squad_attack_00", {"posture": "advance"})).ok, "rejected ID reusable at exact input boundary")
	_check(not squad.apply(Fixtures.command("early", "tactical_intent", "squad_attack_00", {"posture": "advance"})).ok, "accepted ID never reusable")
	state = Scenarios.create()
	var company: RefCounted = _service(state, "company_commander")
	_check(company.apply(Fixtures.command("reserve", "coordination", "platoon_blue00", {"posture": "advance", "release_after": 317.0})).ok, "platoon reserve accepted")
	resolver.resolve_until(state, 316.0, Resolver.AGGREGATE)
	_check(state.units.attack_00.position == 0.5 and state.units.attack_01.position == 0.5 and float(state.units.attack_02.position) > 0.5, "reserve only scoped platoon and not early")
	var at: Dictionary = resolver.resolve_until(state, 317.0, Resolver.AGGREGATE)
	_check(at.counters.events_processed == 2 and state.units.attack_00.position == 0.5, "exact off-grid reserve release no retroactive movement")
	resolver.resolve_until(state, 360.0, Resolver.AGGREGATE)
	_check(float(state.units.attack_00.position) > 0.5, "AI resumes lower movement after release")
	# Existing mission dependencies remain authoritative even under tactical override.
	state = Scenarios.create()
	state.set_coordination("attack_00", {"after": ["mission_attack_01"]})
	squad = _service(state, "squad_leader")
	_check(squad.apply(Fixtures.command("intent", "tactical_intent", "squad_attack_00", {"posture": "advance"})).ok, "intent submitted with original dependency")
	resolver.resolve_until(state, 120.0)
	_check(state.units.attack_00.position == 0.5, "squad intent cannot bypass superior reserve dependency")
	state = Scenarios.create()
	company = _service(state, "company_commander")
	var old_mission: Dictionary = state.missions.mission_attack_00.duplicate(true)
	state.units.attack_02.mission_id = "mission_attack_00"
	_check(company.apply(Fixtures.command("platoon_mission", "mission", "platoon_blue00", Fixtures.mission_values("advance", 1.75))).ok, "company replaces direct platoon mission")
	_check(state.missions[state.units.attack_00.mission_id].objective == 1.75 and state.missions[state.units.attack_01.mission_id].objective == 1.75, "mission translated to exactly subordinate squads")
	_check(state.missions.mission_attack_00 == old_mission and state.units.attack_02.mission_id == "mission_attack_00" and state.units.attack_03.mission_id == "mission_attack_03", "shared template and other platoon/company untouched")
	_check(state.units.attack_00.mission_id != state.units.attack_01.mission_id, "squad mission status records remain independent")


func _no_input_and_scale() -> void:
	for role: String in Roles.ROLES:
		for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
			var plain: State = Scenarios.create()
			var bound: State = Scenarios.create()
			var service: RefCounted = _service(bound, role)
			var baseline: Dictionary = resolver.resolve_until(plain, 3600.0, policy)
			var no_input: Dictionary = resolver.resolve_until(bound, 3600.0, policy)
			_check(baseline == no_input and plain.snapshot() == bound.snapshot(), "no input keeps exact autonomous AI " + role + policy)
			_check(bound.time == 3600.0 and float(bound.totals.casualties) > 0.0, "war does not pause " + role)
			_check(service.snapshot().accepted_ids.is_empty(), "AI does not create player commands")
	var small: Dictionary = Fixtures.scripted("division_commander", Resolver.AGGREGATE, 0, 2.0)
	var sleeping: Dictionary = Fixtures.scripted("division_commander", Resolver.AGGREGATE, 10000, 2.0)
	_check(small.command.ok and sleeping.command.ok, "division mission translation accepted")
	var small_units: int = small.state.units.size()
	var sleeping_units: int = sleeping.state.units.size()
	var left: Dictionary = resolver.resolve_until(small.state, 3600.0, Resolver.AGGREGATE)
	var right: Dictionary = resolver.resolve_until(sleeping.state, 3600.0, Resolver.AGGREGATE)
	# Sleeping input contributes initial global inventory, but no active outcomes/work.
	_check(left.counters == right.counters and left.state_delta == right.state_delta and left.events == right.events and left.summary.units == right.summary.units and left.summary.missions == right.summary.missions and left.summary.control == right.summary.control, "division override work/outcomes independent of 10000 sleeping areas")
	_check(small_units == 10 and sleeping_units == 30010 and small.state.units.size() == small_units and sleeping.state.units.size() == sleeping_units, "higher control instantiates zero combat/person nodes")
	_check(left.summary.policy == Resolver.AGGREGATE and left.counters.segments == 36 and left.counters.contacts_resolved == 1728, "division command preserves aggregate interval/work")
	print("ROLE_SCALE_COUNTERS=" + JSON.stringify(left.counters))


func _compare(a: State, b: State, tolerance: float, label: String) -> void:
	for id: String in State.sorted_ids(a.units):
		for key: String in ["casualties", "ammo_spent"]:
			_check(absf(float(a.units[id][key]) - float(b.units[id][key])) <= maxf(1.0, float(a.units[id][key])) * tolerance, label + key)
		_check(absf(float(a.units[id].position) - float(b.units[id].position)) <= 0.20, label + "movement")
		_check(a.missions[a.units[id].mission_id].status == b.missions[b.units[id].mission_id].status, label + "mission status")
	_check(a.areas.field.control == b.areas.field.control, label + "control")


func _consistency() -> void:
	for role: String in Roles.ROLES:
		var a: Dictionary = Fixtures.scripted(role, Resolver.DETAILED)
		var b: Dictionary = Fixtures.scripted(role, Resolver.AGGREGATE)
		_check(a.command.ok and b.command.ok, "scripted role accepted " + role)
		resolver.resolve_until(a.state, 3600.0, Resolver.DETAILED)
		resolver.resolve_until(b.state, 3600.0, Resolver.AGGREGATE)
		_compare(a.state, b.state, 0.20, role + " resolution ")
		for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
			var full: Dictionary = Fixtures.scripted(role, policy)
			var chunks: Dictionary = Fixtures.scripted(role, policy)
			resolver.resolve_until(full.state, 3600.0, policy)
			for target: float in [600.0, 1200.0, 1800.0, 2400.0, 3000.0, 3600.0]:
				resolver.resolve_until(chunks.state, target, policy)
			_compare(full.state, chunks.state, 0.01, role + " partition ")
			var offgrid: Dictionary = Fixtures.scripted(role, policy)
			for target: float in [317.0, 911.0, 1703.0, 2411.0, 3007.0, 3600.0]:
				resolver.resolve_until(offgrid.state, target, policy)
			_compare(full.state, offgrid.state, 0.02, role + " off-grid ")


func _reserved(role: String) -> State:
	var state: State = Scenarios.create()
	var service: RefCounted = _service(state, role)
	var targets: Dictionary = {"platoon_leader": "squad_attack_00", "company_commander": "platoon_blue00",
		"battalion_commander": "company_blue0", "regiment_commander": "battalion_blue", "division_commander": "regiment_blue"}
	_check(service.apply(Fixtures.command("reserve", "coordination", targets[role], {"posture": "advance", "release_after": 317.0})).ok, "scoped reserve " + role)
	return state


func _coordination_consistency() -> void:
	for role: String in Roles.ROLES.slice(2):
		var detailed: State = _reserved(role)
		var aggregate: State = _reserved(role)
		resolver.resolve_until(detailed, 3600.0, Resolver.DETAILED)
		resolver.resolve_until(aggregate, 3600.0, Resolver.AGGREGATE)
		_compare(detailed, aggregate, 0.20, role + " reserve resolution ")
		for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
			var full: State = _reserved(role)
			var chunks: State = _reserved(role)
			resolver.resolve_until(full, 3600.0, policy)
			for target: float in [131.0, 317.0, 911.0, 1703.0, 2411.0, 3007.0, 3600.0]:
				resolver.resolve_until(chunks, target, policy)
			_compare(full, chunks, 0.02, role + " reserve off-grid ")
