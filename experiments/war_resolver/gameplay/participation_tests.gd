extends SceneTree
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")
const Policy = preload("res://experiments/war_resolver/gameplay/policy.gd")
var checks: int = 0
var failures: int = 0
var rows: Array[Dictionary] = []

func _initialize() -> void:
	for seed_value: int in [71, 109]:
		_causal_cover(seed_value)
	_information_and_permission()
	_personal_limits()
	_incapacitated_observation()
	_decision_path()
	_quota()
	print("GAMEPLAY_PERSONAL_RESULTS=" + JSON.stringify(rows))
	print("Gameplay participation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _ready(seed_value: int, extra: Dictionary = {}) -> Dictionary:
	var config: Dictionary = {"personal": true, "red_ammunition": 2000.0}
	config.merge(extra, true)
	var env: Dictionary = F.setup(seed_value, config)
	check(env.gameplay.admit_standing("unit_000", "guard", "squad", F.intent("hold", str(env.state.units.unit_000.spatial.node))).ok, "standing goal for personal consequence")
	check(F.report(env, "soldier", "soldier_local", "cover", "own_cover", "soldier"), "cover observed by the actual person")
	check(F.advance(env, 0.0).ok, "own cover receipt delivered")
	return env

func _balanced(env: Dictionary) -> bool:
	var unit: Dictionary = env.state.units.unit_000
	var capacity: float = float(unit.gameplay_personnel.anonymous)
	var injury: float = 0.0
	for member: Dictionary in unit.gameplay_personnel.members.values():
		capacity += float(member.health)
		injury += float(member.injury)
		if absf(float(member.health) + float(member.injury) - 1.0) > 0.0000001:
			return false
	return absf(capacity - float(unit.effective)) < 0.0000001 and injury <= float(unit.casualties) + 0.0000001 and absf(float(unit.effective) + float(unit.casualties) - float(unit.personnel_total)) < 0.0000001

func _causal_cover(seed_value: int) -> void:
	var exposed: Dictionary = _ready(seed_value)
	var covered: Dictionary = _ready(seed_value)
	check(float(covered.state.units.unit_000.effective) == 12.0 and float(covered.state.units.unit_000.gameplay_personnel.anonymous) == 11.0, "existing member is reserved, never added")
	check(F.local(exposed, "soldier", "wait_once", "wait").ok, "ordinary person can keep following")
	check(F.local(covered, "soldier", "cover_once", "take_cover").ok, "ordinary person's one cover intent starts real action")
	check(covered.gameplay.participants.view("soldier").state == "ENTERING", "cover is not instantaneous")
	check(F.advance(covered, 2.5).ok, "partial local movement executes automatically")
	var halfway: Array = covered.gameplay.participants.view("soldier").xy
	check(float(halfway[0]) > 0.0 and float(halfway[0]) < 0.01, "person actually traverses local distance")
	check(F.advance(covered, 5.0).ok and covered.gameplay.participants.view("soldier").state == "COVERED", "five second arrival enables cover exposure")
	check(F.advance(exposed, 1800.0).ok and F.advance(covered, 1800.0).ok, "shared war runs for 1800s without further inputs")
	var a: Dictionary = exposed.gameplay.participants.view("soldier")
	var b: Dictionary = covered.gameplay.participants.view("soldier")
	check(float(b.injury) > 0.0 and float(b.injury) < float(a.injury), "cover changes actual shared-fire personal injury, not a label")
	check(float(b.health) > float(a.health) and float(b.health) < 1.0, "cover is not immunity or healing")
	check(_balanced(exposed) and _balanced(covered), "one named and anonymous casualty ledger conserves existing capacity")
	check(float(covered.state.units.unit_000.ammunition) + float(covered.state.units.unit_000.ammo_spent) == 80.0, "person shares original group ammunition")
	var group_before: float = float(covered.state.units.unit_000.distance_moved)
	check(F.command(covered, "squad", "leave", F.intent("withdraw", "C", ["AC"]), "node_unit_000", "instant").ok, "new group intent admitted")
	check(F.advance(covered, 1800.0).ok and covered.gameplay.participants.view("soldier").state == "RETURNING", "new movement regroups covered member with time cost")
	check(F.advance(covered, 1804.0).ok and float(covered.state.units.unit_000.distance_moved) == group_before, "group cannot teleport covered member")
	check(F.advance(covered, 2700.0).ok and F.current(covered).status == "complete", "return to group then automatic withdrawal completes")
	check(_balanced(covered), "member ledger remains conserved after actual group movement")
	rows.append({"seed": seed_value, "exposed_injury": a.injury, "covered_injury": b.injury, "covered_health": b.health, "after_withdraw": covered.gameplay.participants.view("soldier")})

func _information_and_permission() -> void:
	var env: Dictionary = F.setup(71, {"personal": true, "npc": true})
	check(not F.local(env, "soldier", "blind", "take_cover").ok, "cover knowledge must be actually received")
	check(not F.local(env, "soldier", "wrong_person", "wait", "npc").ok, "ordinary soldier cannot choose another actor")
	check(not F.local(env, "company", "officer_personal", "wait").ok, "officer command authority does not grant a soldier body")
	check(not env.roles.soldier.apply({"id": "bypass", "kind": "local_action", "target": "soldier", "values": {"action": "wait"}}).ok, "debug role adapter cannot bypass person input channel")
	for actor: String in ["soldier", "npc"]:
		check(F.report(env, actor, actor + "_local", "cover", "cover_" + actor, actor), "same local source rules for non-player person")
	check(F.advance(env, 0.0).ok, "two actual receipts")
	check(F.local(env, "soldier", "one", "take_cover").ok and F.local(env, "npc", "two", "take_cover").ok, "both persons use identical action code")
	check(F.advance(env, 1800.0).ok, "non-player and player effects settle together")
	check(env.gameplay.participants.view("soldier").health == env.gameplay.participants.view("npc").health, "no player hidden reduction")
	check(_balanced(env), "two named members do not duplicate losses")
	var no_fire: Dictionary = F.setup(71, {"range_km": 0.0, "observation_range_km": 0.5})
	check(F.report(no_fire, "squad", "local", "contact", "seen", "company"), "visible target has actual observation opportunity")
	check(F.advance(no_fire, 1800.0).ok, "seen but fire range unavailable runs")
	check(no_fire.information.knowledge("company").entries[0].claimed_value.observed_unit_refs.size() == 2, "higher officer only receives actual local sight report")
	check(float(no_fire.state.totals.ammo_spent) == 0.0 and float(no_fire.state.totals.casualties) == 0.0, "observation is distinct from fire permission")

func _personal_limits() -> void:
	var env: Dictionary = _ready(71)
	var pair: Array[String] = ["unit_000", "unit_001"]
	check(not env.lod.coalesce("blue_platoon", pair).ok, "causal member capacity cannot be erased by LOD")
	var initial: float = float(env.state.units.unit_000.effective)
	check(not env.gameplay.participants.admit("soldier").ok and float(env.state.units.unit_000.effective) == initial, "rebinding existing identity cannot create capacity")
	# Lethality is a physical fixture input, not a supplied injury outcome.
	for id: String in ["unit_002", "unit_003"]:
		env.state.units[id].weapon.lethality = 500.0
	check(F.advance(env, 30.0).ok, "physical high incoming dose settles")
	check(not env.gameplay.participants.view("soldier").actionable, "injury capacity can cause real inability to act")
	check(not F.local(env, "soldier", "hurt", "take_cover").ok, "incapacitated person cannot perform local action")
	check(_balanced(env), "overkill is limited once per capacity")

func _decision_path() -> void:
	var env: Dictionary = _ready(109)
	var policy: Policy = Policy.new()
	policy.source = "player"
	check(env.decisions.enroll("soldier", {"cadence": 30.0, "targets": ["node_unit_000"], "urgent": false,
		"standing_orders": {"inputs": [{"id": "personal", "at": 10.0, "intent": {"kind": "local_action", "values": {"action": "take_cover"}}}]}}, policy), "ordinary person enrolled through existing decision input chain")
	check(env.decisions.schedule("soldier", "person_choice", 10.0).ok, "one low frequency opportunity")
	check(F.advance(env, 1800.0).ok, "Decision to Information to Role to local execution works")
	check(env.decisions.result("person_choice").status == "ACCEPTED" and env.gameplay.participants.view("soldier").state == "COVERED", "personal effect is accepted and actually executed")
	check(env.decisions.work.world_truth_reads_for_decision == 0, "provider never reads DEBUG_TRUTH")

func _incapacitated_observation() -> void:
	var env: Dictionary = F.setup(71, {"personal": true, "npc": true, "blue_ammunition": 0.0, "red_ammunition": 7.0})
	for id: String in ["unit_002", "unit_003"]:
		env.state.units[id].weapon.lethality = 3.5
	check(env.gameplay.admit_standing("unit_000", "initial_hold", "squad", F.intent("hold", "A")).ok, "body-position counterexample initial goal")
	check(F.report(env, "npc", "npc_local", "cover", "npc_cover", "npc") and F.advance(env, 0.0).ok, "existing non-player member receives actual cover")
	check(F.local(env, "npc", "npc_cover_action", "take_cover").ok, "same action can preserve non-player member")
	check(F.advance(env, 30.0).ok, "finite actual fire creates member consequences")
	check(not env.gameplay.participants.view("soldier").actionable and env.gameplay.participants.view("npc").actionable, "shared dose can incapacitate exposed member while covered member remains")
	check(F.command(env, "squad", "survivor_extract", F.intent("withdraw", "C", ["AC"])).ok and F.advance(env, 900.0).ok, "surviving existing capacity moves after regrouping")
	check(env.state.units.unit_000.spatial.node == "C" and env.gameplay.participants.view("soldier").xy == [0.0, 0.0], "incapacitated body stays at its actual old position")
	var report: Dictionary = env.information.observe("soldier", {"id": "borrowed_position", "source_ref": "soldier_local", "subject_kind": "unit", "subject_ref": "unit_000", "fact_kind": "contact"})
	check(not report.ok, "incapacitated person cannot borrow distant group position for observation")

func _quota() -> void:
	var reference: Dictionary = {}
	for quota: int in [0, 1, 7, 31]:
		var env: Dictionary = _ready(71)
		check(F.local(env, "soldier", "same", "take_cover").ok, "quota same personal input")
		check(F.advance(env, 1800.0, quota).ok, "bounded personal settlement finishes")
		var result: Dictionary = {"units": env.state.units.duplicate(true), "missions": env.state.missions.duplicate(true), "totals": env.state.totals.duplicate(), "knowledge": env.information._knowledge.duplicate(true)}
		if quota == 0:
			reference = result
		else:
			check(result == reference, "personal causal results normal/quota exact")
