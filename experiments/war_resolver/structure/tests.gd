extends SceneTree
const F = preload("res://experiments/war_resolver/structure/fixtures.gd")
const S = preload("res://experiments/war_resolver/structure/service.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Kernel = preload("res://experiments/war_resolver/resolver.gd")
const Data = preload("res://experiments/war_resolver/data.gd")
const Base = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
var checks: int = 0
var failures: int = 0
var evidence: Array[Dictionary] = []

func _initialize() -> void:
	_split_merge()
	_company_split()
	_attachment_scope()
	_lod_boundaries()
	_rejection_and_exploits()
	_events()
	_sleeping_and_order()
	_contract_edges()
	print("TASK5_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task5 structure: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func stock_sum(env: Dictionary) -> Dictionary:
	var total: Dictionary = {}
	for key: String in S.Stocks:
		total[key] = 0.0
	for unit: Dictionary in env.state.units.values():
		for key: String in S.Stocks:
			total[key] += float(unit[key])
	return total

func conserved(a: Dictionary, b: Dictionary, label: String) -> void:
	for key: String in S.Stocks:
		check(absf(float(a[key]) - float(b[key])) <= S.EPS, label + ":" + key)

func atomic(env: Dictionary, command: Dictionary, actor: String, label: String) -> void:
	var before: Dictionary = env.lod.snapshot()
	var structure: Dictionary = env.service.snapshot()
	var count: Dictionary = env.service.work.duplicate()
	check(not env.commands[actor].apply(command).ok, label)
	check(env.lod.snapshot() == before and env.service.snapshot() == structure, label + " atomic")
	check(env.service.work.leaves_materialized_for_structure == count.leaves_materialized_for_structure, label + " no expansion")

func execute(env: Dictionary, command: Dictionary, actor: String = "regiment") -> bool:
	var accepted: Dictionary = env.commands[actor].apply(command)
	check(accepted.ok, "submit " + str(command.id) + ":" + str(accepted))
	if not accepted.ok:
		return false
	var result: Dictionary = env.lod.advance(float(command.effective_time))
	check(result.ok, "advance " + str(command.id))
	var outcome: Dictionary = env.service.history[-1].outcome
	check(outcome.ok, "commit " + str(command.id) + ":" + str(outcome))
	return outcome.ok

func worn(env: Dictionary) -> void:
	var u: Dictionary = env.state.units.unit_000
	u.effective = 8.0
	u.casualties = 4.0
	u.equipment = 7.0
	u.equipment_lost = 5.0
	u.ammunition = 500.0
	u.ammo_spent = 460.0
	u.fatigue = 0.4
	u.suppression = 0.6
	u.cohesion = 0.45
	u.readiness = 0.7
	env.state.totals.casualties += 4.0
	env.state.totals.equipment_lost += 5.0
	env.state.totals.ammo_spent += 460.0

func _split_merge() -> void:
	var env: Dictionary = F.setup(40, 0, false)
	worn(env)
	var before: Dictionary = stock_sum(env)
	var ledger: Dictionary = env.state.totals.duplicate()
	var source: Dictionary = env.state.units.unit_000.duplicate(true)
	check(execute(env, F.split_request(env)), "A split")
	conserved(before, stock_sum(env), "A strict stocks")
	for key: String in ["readiness", "suppression", "cohesion", "fatigue", "position", "distance_moved", "mobility"]:
		check(env.state.units.detachment[key] == source[key] and env.state.units.unit_000[key] == source[key], "B continuity " + key)
	check(env.state.units.detachment.structure_provenance.from == "unit_000", "B provenance")
	check(env.state.missions[env.state.units.detachment.mission_id].status == env.state.missions[source.mission_id].status, "B mission")
	check(execute(env, F.request("merge", "merge", 0.0, {"survivor": "unit_000", "donor": "detachment"})), "C merge")
	conserved(before, stock_sum(env), "C strict stocks")
	check(env.state.totals == ledger, "C ledger not reinjected")
	check(not env.state.units.has("detachment") and env.state.identity_reserved("detachment") and not env.state.knows_unit("detachment"), "C retired identity reserved without commandable combat record")
	check(env.service.snapshot().retired_history_not_current.node_detachment.into == "unit_000", "C historical link")
	for cycle: int in range(20):
		var id: String = "repeat_%02d" % cycle
		check(execute(env, F.split_request(env, "split_" + id, 0.2, "unit_000", id)), "D repeat split")
		check(execute(env, F.request("merge_" + id, "merge", 0.0, {"survivor": "unit_000", "donor": id})), "D repeat merge")
		conserved(before, stock_sum(env), "D no drift")
		for key: String in ["fatigue", "suppression", "cohesion", "readiness"]:
			check(env.state.units.unit_000[key] == source[key], "D no restoration " + key)
		check(env.state.units.unit_000.tactical_weight == 1.0, "D no tactical footprint creation")
	check(not env.roles.soldier.apply({"id": "structure", "kind": "split", "target": "node_unit_000", "values": {}}).ok, "J legacy role no structure bypass")
	evidence.append({"test": "A_B_C_D_P", "cycles": 20, "before": before, "after": stock_sum(env), "time": env.state.time, "work": env.service.work.duplicate()})

func mission_command(id: String, target: String) -> Dictionary:
	return {"id": id, "kind": "mission", "target": target, "values": {"posture": "hold", "direction": 1.0, "objective": 2.0}}

func _company_split() -> void:
	var env: Dictionary = F.setup(40, 0, false)
	var before: Dictionary = stock_sum(env)
	var request: Dictionary = F.company_split(env)
	atomic(env, request, "company", "company split requires superior scope")
	check(execute(env, request, "battalion"), "real company split")
	conserved(before, stock_sum(env), "company stocks")
	check(env.service.node("detached_company").provenance.from == "blue_company", "company stable provenance")
	check(env.service.leaves("detached_company").size() == 20 and env.service.leaves("blue_company").size() == 20, "company real resource-bearing leaves")
	check(env.service.relation("detached_company").permanent_parent == "blue_battalion", "company detachment permanent membership")
	check(env.roles.battalion.command_scope().targets.mission.has("detached_company"), "company new superior scope")
	check(not env.roles.company.command_scope().targets.mission.has("detached_company"), "company no peer authority")
	check(env.roles.battalion.report().formations.detached_company.effective == 60.0, "company report actual allocated personnel")
	for leaf: String in env.service.leaves("detached_company"):
		var unit: Dictionary = env.lod.preview_leaf(str(env.service.node(leaf).unit_id))
		check(unit.personnel_total == 3.0 and unit.fatigue == 0.0 and unit.cohesion == 0.95 and unit.position == 0.5, "company physical inheritance")
	check(env.service.work.leaves_materialized_for_structure == 0, "detailed company no LOD expansion")
	check(not env.state.schedule_event("invalid_company_order", 1.0, "order", {"unit_id": "detached_company", "mission_id": "mission_unit_000"}), "P structural company identity is not a combat proxy")
	evidence.append({"test": "A_B_company", "before": before, "after": stock_sum(env), "work": env.service.work.duplicate()})

func _attachment_scope() -> void:
	var env: Dictionary = F.setup()
	var permanent: String = str(env.service.relation("blue_company").permanent_parent)
	var before: Dictionary = stock_sum(env)
	check(execute(env, F.request("attach_company", "attach", 17.0, {"target": "blue_company", "parent": "blue_battalion_b", "until": 77.0})), "E company attach")
	var relation: Dictionary = env.service.relation("blue_company")
	check(relation.permanent_parent == permanent and relation.effective_parent == "blue_battalion_b", "E permanent/effective distinction")
	check(relation.supply_responsibility_reference == "blue_battalion_b", "E responsibility reference")
	check(not env.roles.battalion.command_scope().targets.mission.has("blue_company"), "E old scope removed")
	check(env.roles.recipient.command_scope().targets.mission.has("blue_company"), "E new scope granted")
	check(not env.roles.battalion.report().formations.has("blue_company") and env.roles.recipient.report().formations.has("blue_company"), "E reports follow relation")
	var snap: Dictionary = env.lod.snapshot()
	check(not env.roles.battalion.apply(mission_command("old", "blue_company")).ok, "J old parent rejected")
	check(env.lod.snapshot() == snap, "J rejection atomic")
	check(env.roles.recipient.apply(mission_command("new", "blue_company")).ok, "J new parent mission applied")
	check(env.roles.recipient.report().formations.blue_company.squads == 20, "E report count")
	check(env.lod.advance(77.0).ok, "E expiry")
	check(env.service.relation("blue_company").effective_parent == permanent, "E restoration exact time")
	check(env.roles.battalion.command_scope().targets.mission.has("blue_company") and not env.roles.recipient.command_scope().targets.mission.has("blue_company"), "E scopes restored")
	check(env.service.work.leaves_materialized_for_structure == 20, "E necessary company subtree only")
	check(env.state.time == 77.0, "I one clock")
	check(stock_sum(env).personnel_total == before.personnel_total, "E attachment no spawn")
	check(env.service.history[-1].outcome.kind == "attachment_expired", "E expiry event recorded")
	evidence.append({"test": "E_J", "relation": relation, "reverted": env.service.relation("blue_company"), "work": env.service.work.duplicate()})

func _lod_boundaries() -> void:
	var env: Dictionary = F.setup()
	check(env.lod.advance(120.0).ok, "G prior aggregate combat")
	var before: Dictionary = stock_sum(env)
	var counters: Dictionary = env.state.counters.duplicate()
	var request: Dictionary = F.request("attach_leaf", "attach", 120.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 180.0})
	check(execute(env, request), "G suspended attach")
	conserved(before, stock_sum(env), "G attachment resources")
	check(env.service.work.leaves_materialized_for_structure == 1 and env.service.work.aggregate_memberships_rebuilt == 1, "G one leaf/one aggregate")
	check(env.state.counters.segments == counters.segments and env.state.counters.contacts_resolved == counters.contacts_resolved, "I no historical combat")
	check(env.state.time == 120.0, "I materialize no time")
	check(env.lod.representation_of("unit_000") == "unit_000" and env.lod.representation_of("unit_001") != "unit_001", "H unique extraction")
	var transferred: Array[String] = ["unit_000", "unit_001"]
	check(not env.lod.coalesce("platoon_000", transferred).ok, "H old parent cannot aggregate transferred leaf")
	check(not Kernel.new().resolve_until(env.state, 120.0).ok, "I independent kernel rejected")
	check(env.lod.advance(180.0).ok, "K autonomous continuation/expiry")
	check(env.service.relation("node_unit_000").effective_parent == "platoon_000", "E leaf expiry restored")
	check(env.service.work.leaves_materialized_for_structure == 1, "expiry does not expand unrelated leaves")
	var env2: Dictionary = F.setup()
	check(env2.lod.advance(120.0).ok, "G split prehistory")
	var pre: Dictionary = stock_sum(env2)
	var old_units: Array = env2.state.units.keys()
	check(execute(env2, F.split_request(env2)), "G suspended split")
	conserved(pre, stock_sum(env2), "G split macro stocks")
	check(env2.service.work.leaves_materialized_for_structure == 1, "G split extracts one")
	check(env2.state.units.size() == old_units.size() + 2, "G residual aggregate retained")
	check(env2.state.time == 120.0, "I split no time reset")
	var materialized: Dictionary = env2.state.units.unit_000.duplicate(true)
	check(env2.lod.advance(240.0).ok, "K split continues combat")
	check(env2.state.units.unit_000.fatigue >= materialized.fatigue, "K autonomous state advancement")
	check(State.sorted_ids(env2.lod.spatial.dirty) == ["cell_037", "parent_01", "region_50"], "M localized ancestors")
	evidence.append({"test": "G_H_I_K_M", "attachment_work": env.service.work.duplicate(), "split_work": env2.service.work.duplicate(), "dirty": State.sorted_ids(env2.lod.spatial.dirty)})

func _rejection_and_exploits() -> void:
	var env: Dictionary = F.setup()
	atomic(env, F.split_request(env, "zero", 0.0), "regiment", "P zero")
	atomic(env, F.split_request(env, "full", 1.0), "regiment", "P all resources")
	atomic(env, F.split_request(env, "tiny", 0.000000001), "regiment", "P too small")
	atomic(env, F.split_request(env, "duplicate", 0.25, "unit_000", "unit_001"), "regiment", "P duplicate identity")
	atomic(env, F.split_request(env, "soldier"), "soldier", "J soldier authority")
	var malformed: Dictionary = F.split_request(env, "bad_amount")
	malformed.values.allocation.ammunition += 20.0
	atomic(env, malformed, "regiment", "P allocation mismatch")
	malformed = F.split_request(env, "nan")
	malformed.values.allocation.personnel_total = NAN
	atomic(env, malformed, "regiment", "P NaN")
	atomic(env, F.request("merge_space", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_020"}), "division", "P enemy merge")
	check(execute(env, F.request("a", "attach", 0.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 600.0})), "P attach")
	atomic(env, F.request("overlap", "attach", 1.0, {"target": "node_unit_000", "parent": "platoon_010", "until": 60.0}), "regiment", "F overlap")
	atomic(env, F.split_request(env, "direct_attached"), "regiment", "P direct attachment split migration rejected")
	for cycle: int in range(12):
		check(execute(env, F.request("revoke_%d" % cycle, "revoke", 0.0, {"target": "node_unit_000"})), "P revoke")
		var unit: Dictionary = env.lod.preview_leaf("unit_000")
		check(execute(env, F.request("reattach_%d" % cycle, "attach", 0.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 600.0})), "P reattach")
		check(env.lod.preview_leaf("unit_000") == unit, "P attach/revoke cannot heal/teleport")
	check(execute(env, F.request("final_revoke", "revoke", 0.0, {"target": "node_unit_000"})), "P final revoke")
	check(env.lod.advance(600.0).ok, "P stale expiry")
	check(env.service.relation("node_unit_000").effective_parent == "platoon_000", "P stale expiry cannot change relation")
	var detailed: Dictionary = F.setup(40, 0, false)
	detailed.state.units.unit_001.position += 0.01
	atomic(detailed, F.request("space", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"}), "company", "P spatial incompatibility")
	detailed.state.units.unit_001.position = detailed.state.units.unit_000.position
	detailed.state.missions[detailed.state.units.unit_001.mission_id].posture = "hold"
	atomic(detailed, F.request("mission", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"}), "company", "P incompatible mission")
	evidence.append({"test": "F_P", "cycles": 12, "work": env.service.work.duplicate()})

func _events() -> void:
	var env: Dictionary = F.setup()
	var old: Dictionary = stock_sum(env)
	check(env.commands.regiment.apply(F.request("z_attach", "attach", 17.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 47.0})).ok, "N queued attachment")
	env.state.add_mission(Data.mission("new_order", "hold"))
	check(env.state.schedule_event("a_order", 17.0, "order", {"unit_id": "unit_000", "mission_id": "new_order"}), "N queued order")
	check(env.state.schedule_event("b_reinforcement", 17.0, "reinforcement", {"unit": Data.unit("reinforced", "blue", "cell_037", "new_order")}), "N queued reinforcement")
	check(env.state.schedule_event("c_terrain", 17.0, "area_change", {"area_id": "cell_037", "cover": 0.8}), "N queued terrain")
	check(env.lod.advance(16.0).ok, "N before boundary")
	check(env.service.relation("node_unit_000").effective_parent == "platoon_000", "N no early effect")
	var result: Dictionary = env.lod.advance(17.0)
	var ids: Array[String] = []
	for event: Dictionary in result.events:
		if event.has("id"):
			ids.append(str(event.id))
	check(ids == ["structure_z_attach", "a_order", "b_reinforcement", "c_terrain"], "N phase then stable ID, independent input naming")
	check(env.state.units.unit_000.mission_id == "new_order" and env.state.units.has("reinforced"), "N order after attachment")
	check(env.service.history[0].time == 17.0, "N exact event time")
	check(stock_sum(env).personnel_total == float(old.personnel_total) + 12.0, "N reinforcement ledger once")
	check(env.state.unit_event_counts.is_empty(), "N pending-reference index consumed")
	evidence.append({"test": "N", "order": ids, "history": env.service.history.duplicate(true)})
	var due: Dictionary = F.setup()
	check(due.commands.company.apply(F.split_request(due, "future_authority")).ok, "J queue authorized")
	# Both at t=0: lexicographically earlier relation change revokes old actor's scope.
	check(due.commands.regiment.apply(F.request("a_transfer", "attach", 0.0, {"target": "blue_company", "parent": "blue_battalion_b", "until": 50.0})).ok, "J prior structure event")
	# Company keeps its own command through transfer: ancestor office does not.
	check(due.lod.advance(0.0).ok and due.service.history[-1].outcome.ok, "J subordinate office retains own scope")
	var revoked: Dictionary = F.setup()
	check(revoked.commands.battalion.apply(F.split_request(revoked, "z_old_parent")).ok, "J old parent queued")
	check(revoked.commands.regiment.apply(F.request("a_transfer", "attach", 0.0, {"target": "blue_company", "parent": "blue_battalion_b", "until": 50.0})).ok, "J transfer queued")
	check(revoked.lod.advance(0.0).ok, "J revalidate at delivery")
	check(not revoked.service.history[-1].outcome.ok and not revoked.state.units.has("detachment"), "J stale authority rejected before mutation")
	var adjacent: Dictionary = F.setup()
	check(adjacent.commands.regiment.apply(F.request("first", "attach", 0.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 30.0})).ok, "N first interval")
	check(adjacent.commands.regiment.apply(F.request("second", "attach", 30.0, {"target": "node_unit_000", "parent": "platoon_010", "until": 60.0})).ok, "N adjacent interval accepted")
	check(adjacent.lod.advance(30.0).ok and adjacent.service.relation("node_unit_000").effective_parent == "platoon_010", "N expiry before next begin")

func _sleeping_and_order() -> void:
	var fingerprints: Array[String] = []
	var active_work: Array[Dictionary] = []
	for sleep: int in [0, 10000]:
		var env: Dictionary = F.setup(40, sleep)
		check(env.commands.regiment.apply(F.request("attachment", "attach", 77.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 157.0})).ok, "L submit")
		check(env.lod.advance(300.0).ok, "L advance")
		active_work.append({"combat": env.state.counters.duplicate(), "lod": env.lod.counters(), "structure": env.service.work.duplicate()})
		fingerprints.append(JSON.stringify(env.lod.macro_summary().sides).sha256_text())
	check(active_work[0] == active_work[1], "L sleeping exact counters")
	check(fingerprints[0] == fingerprints[1], "L sleeping exact outcomes")
	evidence.append({"test": "L", "work": active_work[0], "outcome_hash": fingerprints[0]})
	var hashes: Array[String] = []
	for reverse: bool in [false, true]:
		var env: Dictionary = F.setup()
		var a: Dictionary = F.request("b_one", "attach", 17.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 77.0})
		var b: Dictionary = F.request("a_two", "attach", 17.0, {"target": "node_unit_001", "parent": "blue_destination", "until": 77.0})
		for command: Dictionary in ([b, a] if reverse else [a, b]):
			check(env.commands.regiment.apply(command).ok, "N insertion order submit")
		check(env.lod.advance(300.0).ok, "N insertion order advance")
		hashes.append(JSON.stringify({"lod": env.lod.snapshot(), "structure": env.service.snapshot()}).sha256_text())
	check(hashes[0] == hashes[1], "N insertion order deterministic")
	evidence.append({"test": "N_order", "hashes": hashes})

func _contract_edges() -> void:
	var stale_env: Dictionary = F.setup(40, 0, false)
	var stale: Roles = Roles.new()
	check(stale.configure(stale_env.state, stale_env.nodes, stale_env.people, "battalion"), "J unbound adapter admission")
	check(execute(stale_env, F.request("stale_transfer", "attach", 0.0, {"target": "blue_company", "parent": "blue_battalion_b", "until": 30.0})), "J transfer with unbound adapter present")
	var state_before: Dictionary = stale_env.lod.snapshot()
	check(not stale.apply(mission_command("bypass", "blue_company")).ok and stale_env.lod.snapshot() == state_before, "J stale static adapter cannot bypass current scope")
	check(not stale.report().ok and not stale.command_scope().ok, "J stale reports and selection denied")
	check(not stale.bind_structure(stale_env.service), "J late stale snapshot admission rejected")
	var idle: Dictionary = F.setup(40, 0, false)
	var bare: State = Base.battle(40, 71, 0, "cell_037")
	var lod: Authority = Authority.new()
	check(lod.configure(bare), "K independent baseline admission")
	check(idle.lod.advance(300.0).ok and lod.advance(300.0).ok, "K no player input")
	check(idle.state.snapshot() == bare.snapshot(), "K no structural events exactly Task4 autonomous result")
	var env: Dictionary = F.setup(40, 0, false)
	var a: Dictionary = env.state.units.unit_000
	var b: Dictionary = env.state.units.unit_001
	a.fatigue = 0.3
	b.fatigue = 0.7
	a.suppression = 0.8
	b.suppression = 0.2
	a.cohesion = 0.5
	b.cohesion = 0.9
	check(execute(env, F.request("worst_merge", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"})), "B conservative merge states")
	check(a.fatigue == 0.7 and a.suppression == 0.8 and a.cohesion == 0.5, "B merge cannot recover condition")
	var attempted: Dictionary = Data.unit("unit_001", "blue", "cell_037", a.mission_id)
	check(not env.state.schedule_event("resurrection", 1.0, "reinforcement", {"unit": attempted}), "P retired ID cannot be reinforced anew")
	check(not env.state.schedule_event("dead_order", 1.0, "order", {"unit_id": "unit_001", "mission_id": a.mission_id}), "P retired unit is not commandable")
	check(not env.state.schedule_event("dead_release", 1.0, "coordination_release", {"unit_id": "unit_001"}), "P retired unit has no future release")
	atomic(env, F.split_request(env, "reuse_retired", 0.2, "unit_000", "unit_001"), "company", "P retired identity cannot be reused")
	check(not env.roles.platoon.command_scope().targets.mission.has("node_unit_001"), "J retired commander target filtered")
	var pending: Dictionary = F.setup()
	check(pending.state.schedule_event("pending_order", 10.0, "order", {"unit_id": "unit_000", "mission_id": "mission_unit_000"}), "P pending reference index")
	atomic(pending, F.split_request(pending, "pending_split"), "regiment", "P reject unresolved dependency migration")
	atomic(pending, {"id": "missing_kind", "values": {}, "effective_time": 0.0}, "regiment", "P malformed schema")
	var bad: Dictionary = F.request("cycle", "attach", 0.0, {"target": "blue_battalion", "parent": "blue_company", "until": 10.0})
	atomic(pending, bad, "regiment", "P backwards hierarchy rejected")
	var tiny: Dictionary = F.setup(40, 0, false)
	check(execute(tiny, F.split_request(tiny, "tiny_valid", 0.000001 / 12.0)), "P bounded tiny remnant valid")
	var plans: Dictionary = Kernel.new()._prepare_area(tiny.state, "cell_037")
	check((plans.unit_020.contacts as Array).has("detachment") and float(plans.detachment.rounds) > 0.0 and float(plans.detachment.speed) > 0.0, "P tiny remnant remains targetable/active by preserved measure")
	check(execute(tiny, F.request("tiny_merge", "merge", 0.0, {"survivor": "unit_000", "donor": "detachment"})), "P tiny merge")
	check(absf(tiny.state.units.unit_000.personnel_total - 12.0) <= S.EPS, "P tiny conservation")
	var tickets: Dictionary = F.setup()
	check(tickets.commands.regiment.apply(F.split_request(tickets, "ticket")).ok, "P prepared ticket")
	check(not tickets.state.schedule_event("fake", 0.0, "structure", {"request_id": "ticket"}), "P ticket cannot be replayed under arbitrary event ID")
	check(not tickets.state.schedule_event("structure_expiry_ticket", 0.0, "structure", {"request_id": "ticket", "expiry": true}), "P non-attachment expiry rejected safely")
	check(not tickets.state.schedule_event("structure_ticket", 0.0, "structure", {"request_id": "ticket", "expiry": "true"}), "P malformed expiry rejected safely")
	var current_missions: Dictionary = F.setup()
	check(current_missions.lod.materialize_leaf("unit_000").ok, "P one detailed current mission")
	var proxy: String = current_missions.lod.representation_of("unit_001")
	current_missions.state.missions[current_missions.state.units[proxy].mission_id].status = "complete"
	atomic(current_missions, F.request("macro_mission", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"}), "company", "P compare current macro mission, not old template")
	var membership: Dictionary = F.setup()
	for i: int in [0, 1]:
		check(execute(membership, F.request("move_%d" % i, "attach", 0.0, {"target": "node_unit_%03d" % i, "parent": "blue_destination", "until": 60.0})), "H relocate")
	var leaves: Array[String] = ["unit_000", "unit_001"]
	check(membership.lod.coalesce("blue_destination", leaves).ok, "H new effective formation can coalesce")
	var image: Dictionary = membership.lod.snapshot()
	for id: String in leaves:
		var count: int = 0
		for aggregate: Dictionary in image.unresolved.values():
			count += int(aggregate.leaf_refs.has(id))
		check(count == 1 and not membership.state.units.has(id), "H exactly one owner")
	check(membership.lod.advance(60.0).ok, "H expiry from new aggregate")
	check(membership.service.work.leaves_materialized_for_structure == 4, "H only changed two extracted twice")
	evidence.append({"test": "H_K_P_edges", "work": membership.service.work.duplicate(), "no_input_exact_equivalence": true})
