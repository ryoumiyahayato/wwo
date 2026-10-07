extends SceneTree
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Data = preload("res://experiments/war_resolver/data.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
const Fixtures = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const RoleFixtures = preload("res://experiments/war_resolver/role_scenarios.gd")
var checks: int = 0
var failures: int = 0
var evidence: Array[Dictionary] = []
const CONSERVATION_EPSILON: float = 0.0000001

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL Task4: " + label)

func _owned(state: State) -> Authority:
	var authority: Authority = Authority.new()
	_check(authority.configure(state), "one state admission")
	return authority

func _audit(state: State, label: String) -> void:
	var sums: Dictionary = {}
	for key: String in Authority.STOCKS:
		sums[key] = 0.0
	for id: String in State.sorted_ids(state.units):
		var unit: Dictionary = state.units[id]
		for key: String in Authority.STOCKS:
			sums[key] += float(unit[key])
			_check(float(unit[key]) >= -0.00000001, label + " bounded " + key)
		_check(is_equal_approx(float(unit.personnel_total), float(unit.effective) + float(unit.casualties)), label + " unit personnel")
		_check(float(unit.suppression) >= 0.0 and float(unit.suppression) <= 1.0 and float(unit.fatigue) <= 1.0 and float(unit.cohesion) >= 0.0, label + " condition bounds")
		_check(state.area_units[unit.area_id].has(id), label + " current membership index")
	var indexed: int = 0
	for area_id: String in state.area_units:
		for id: String in state.area_units[area_id]:
			indexed += 1
			_check(state.units.has(id) and state.units[id].area_id == area_id, label + " no stale indexed leaf")
	_check(indexed == state.units.size(), label + " no duplicate represented identity")
	_check(is_equal_approx(float(sums.personnel_total), float(state.totals.personnel)), label + " global personnel")
	_check(is_equal_approx(float(sums.effective) + float(sums.casualties), float(state.totals.personnel)), label + " personnel conservation")
	_check(is_equal_approx(float(sums.equipment) + float(sums.equipment_lost), float(state.totals.equipment)), label + " equipment conservation")
	_check(is_equal_approx(float(sums.ammunition) + float(sums.ammo_spent), float(state.totals.ammunition)), label + " ammo conservation")
	for key: String in ["casualties", "ammo_spent", "equipment_lost"]:
		_check(is_equal_approx(float(sums[key]), float(state.totals[key])), label + " current ledger " + key)
	for pair: Array in [["effective", "casualties", "personnel"], ["equipment", "equipment_lost", "equipment"], ["ammunition", "ammo_spent", "ammunition"]]:
		_check(absf(float(sums[pair[0]]) + float(sums[pair[1]]) - float(state.totals[pair[2]])) <= CONSERVATION_EPSILON, label + " absolute stock drift bound")

func _run() -> void:
	_conservation_transitions()
	_resolution_invariance()
	_structural_conditions()
	_contacts_and_sleep()
	_spatial_and_zoom()
	_events()
	_roles()
	_symmetry()
	_lod_axes()
	print("TASK4_EVIDENCE_JSON=" + JSON.stringify(evidence, "", true, true))
	print("Task4 aggregation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _conservation_transitions() -> void:
	var state: State = Fixtures.battle()
	var authority: Authority = _owned(state)
	var initial: Dictionary = state.totals.duplicate()
	for cycle: int in range(8):
		Fixtures.coalesce_sides(authority, state, 40)
		_check(state.units.size() == 4, "A/B forty identities become four representations")
		_audit(state, "coalesced")
		var before: Dictionary = authority.snapshot()
		_check(not Resolver.new().resolve_until(state, state.time + 30.0).ok, "C direct independent settlement rejected")
		_check(before == authority.snapshot(), "C rejection leaves truth unchanged")
		authority.advance(state.time + 120.0)
		var time: float = state.time
		for index: int in range(40):
			var id: String = "unit_%03d" % index
			_check(authority.materialize_leaf(id).ok, "B materialize stable identity")
			_check(state.units[id].resolved_through == time, "C detail starts at current boundary")
		_check(state.time == time and state.units.size() == 40, "B transition is not elapsed time")
		_audit(state, "materialized")
		_check(not authority.advance(time - 1.0).ok, "C cannot resettle aggregate interval")
	_check(initial.personnel == state.totals.personnel and initial.equipment == state.totals.equipment and initial.ammunition == state.totals.ammunition, "B repeated transitions cannot create stock")
	var snapshot: Dictionary = authority.snapshot()
	var ids: Array[String] = ["unit_000", "unit_020"]
	_check(not authority.coalesce("bad", ids).ok and authority.snapshot() == snapshot, "A incompatible side admission atomic")
	evidence.append({"test": "A_B_C", "cycles": 8, "work": authority.counters(), "summary": authority.macro_summary()})

func _variant(seed_value: int, mode: String, policy: String = Resolver.DETAILED) -> Dictionary:
	var state: State = Fixtures.battle(40, seed_value)
	var authority: Authority = _owned(state)
	if mode in ["aggregate", "zoom_in"]:
		Fixtures.coalesce_sides(authority, state, 40)
	if mode == "zoom_out":
		authority.advance(1800.0, policy)
		Fixtures.coalesce_sides(authority, state, 40)
	elif mode == "zoom_in":
		authority.advance(1800.0, policy)
		for index: int in range(40):
			authority.materialize_leaf("unit_%03d" % index, "observation_boundary")
	_check(authority.advance(3600.0, policy).ok, "D/E autonomous full hour " + mode)
	_audit(state, "D/E " + mode)
	return authority.macro_summary()

func _resolution_invariance() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		var reference: Dictionary = _variant(seed_value, "detailed")
		for mode: String in ["aggregate", "zoom_in", "zoom_out", "aggregate_120s"]:
			var other: Dictionary = _variant(seed_value, "aggregate" if mode == "aggregate_120s" else mode, Resolver.AGGREGATE if mode == "aggregate_120s" else Resolver.DETAILED)
			_check(other.time == reference.time, "D/E one world clock")
			_check(other.control == reference.control, "D/E control tendency")
			for side: String in ["blue", "red"]:
				var a: Dictionary = reference.sides[side]
				var b: Dictionary = other.sides[side]
				for key: String in ["casualties", "ammo_spent"]:
					_check(absf(float(a[key]) - float(b[key])) <= maxf(1.0, float(a[key])) * 0.20, "D/E unchanged resource tolerance " + side + mode + key)
				var x_a: float = float(a.position_weighted) / float(a.personnel_total)
				var x_b: float = float(b.position_weighted) / float(b.personnel_total)
				_check(absf(x_a - x_b) <= 0.20, "D/E movement range/direction")
				_check(a.complete == b.complete and a.withdrawn == b.withdrawn, "D/E mission outcome")
			var advantage_a: float = float(reference.sides.red.casualties) - float(reference.sides.blue.casualties)
			var advantage_b: float = float(other.sides.red.casualties) - float(other.sides.blue.casualties)
			_check(signf(advantage_a) == signf(advantage_b), "D/E side advantage direction")
			evidence.append({"test": "D_E", "seed": seed_value, "mode": mode, "reference": reference, "result": other})

func _contacts_and_sleep() -> void:
	var results: Array[Dictionary] = []
	for count: int in [40, 100]:
		var state: State = Fixtures.battle(count)
		var authority: Authority = _owned(state)
		Fixtures.coalesce_sides(authority, state, count)
		var construction: Dictionary = authority.counters()
		authority.advance(3600.0)
		var work: Dictionary = authority.counters()
		_check(work.leaf_records_examined == construction.leaf_records_examined, "F/G no leaf combat reads after coalescing")
		_check(work.actual_contacts_resolved < (96000 if count == 40 else 600000) / 10, "F/G formation contact reduction")
		results.append(work)
		evidence.append({"test": "F_G", "squads": count, "construction": construction, "work": work})
	var sparse: State = Fixtures.battle(100, 71, 0, "field", true)
	var indexed: Authority = _owned(sparse)
	indexed.advance(30.0)
	var sparse_work: Dictionary = indexed.counters()
	_check(sparse_work.candidate_contacts_examined < 300, "H sparse candidate search not all pairs")
	_check(sparse_work.actual_contacts_resolved == 2, "H only two real directed contacts")
	var dense: State = Fixtures.battle(100)
	var dense_solver: Authority = _owned(dense)
	dense_solver.advance(30.0)
	_check(dense_solver.counters().actual_contacts_resolved == 5000, "I dense real all-to-all opposing contacts retained")
	evidence.append({"test": "H_I", "sparse": sparse_work, "dense": dense_solver.counters()})
	var small: State = Fixtures.battle()
	var large: State = Fixtures.battle(40, 71, 10000)
	var a: Authority = _owned(small)
	var b: Authority = _owned(large)
	Fixtures.coalesce_sides(a, small, 40)
	Fixtures.coalesce_sides(b, large, 40)
	a.advance(3600.0)
	b.advance(3600.0)
	_check(a.counters() == b.counters(), "J sleeping-world counters independent")
	_check(a.macro_summary().sides == b.macro_summary().sides, "J active outcomes independent")
	var idle: State = State.new()
	idle.add_area(Data.area("idle"))
	idle.add_mission(Data.mission("idle", "idle"))
	idle.add_unit(Data.unit("idle", "blue", "idle", "idle"))
	var idle_solver: Authority = _owned(idle)
	idle_solver.advance(86400.0)
	_check(idle_solver.counters().segments == 0 and idle_solver.counters().leaf_records_examined == 0 and idle_solver.counters().candidate_contacts_examined == 0, "J idle day direct jump")
	evidence.append({"test": "J", "small": a.counters(), "sleeping": b.counters()})

func _spatial_and_zoom() -> void:
	var state: State = Fixtures.hierarchy()
	var authority: Authority = _owned(state)
	authority.advance(120.0)
	_check(authority.spatial.dirty.size() == 3 and authority.spatial.dirty.has("cell_037") and authority.spatial.dirty.has("parent_01") and authority.spatial.dirty.has("region_50"), "K only changed cell ancestor path")
	_check(authority.counters().spatial_nodes_examined == 3 and authority.counters().parent_nodes_updated == 2, "K no sibling scans")
	_check(is_equal_approx(float(authority.spatial.nodes.region_50.stocks.casualties), float(state.totals.casualties)), "K parent summaries propagate, no combat duplication")
	var world: State = Fixtures.hierarchy(true)
	var zoom: Authority = _owned(world)
	for index: int in range(100):
		Fixtures.coalesce_cell(zoom, "cell_%03d" % index)
	zoom.advance(120.0)
	var before: Dictionary = zoom.counters()
	var time: float = world.time
	var unrelated: Dictionary = world.units["aggregate_" + ("cell_000_formation_00:cell_000_unit_00:cell_000_unit_01").sha256_text().substr(0, 16) + "_000001"].duplicate(true)
	var result: Dictionary = zoom.zoom_in("cell_037")
	_check(result.ok and result.materialized == 4, "L one cell materializes four leaves, not 400")
	_check(zoom.counters().leaf_records_materialized - int(before.leaf_records_materialized) == 4 and world.time == time, "L bounded branch and no resettlement")
	_check(world.units[unrelated.id] == unrelated, "L unrelated formation remains aggregate/current")
	for key: String in zoom.spatial.nodes.region_50.control_counts:
		_check(int(zoom.spatial.nodes.region_50.control_counts[key]) >= 0, "K control histogram remains nonnegative")
	_audit(world, "L zoom")
	evidence.append({"test": "K_L", "one_leaf_work": authority.counters(), "zoom_materialized": result.materialized, "zoom_delta_reads": int(zoom.counters().leaf_records_examined) - int(before.leaf_records_examined)})
	var transfer: State = State.new()
	transfer.add_area(Data.area("cell_037"))
	transfer.add_area(Data.area("cell_038"))
	transfer.areas.cell_037.links.cell_038 = true
	var crossing: Dictionary = Data.mission("cross", "advance", 1.0, 0.04)
	crossing.destination = "cell_038"
	transfer.add_mission(crossing)
	transfer.add_unit(Data.unit("traveler", "blue", "cell_037", "cross"))
	var cross_owner: Authority = _owned(transfer)
	cross_owner.advance(30.0)
	_check(transfer.units.traveler.area_id == "cell_038", "K exact cross-cell arrival")
	_check(cross_owner.spatial.nodes.cell_037.stocks.personnel_total == 0.0 and cross_owner.spatial.nodes.cell_038.stocks.personnel_total == 12.0 and cross_owner.spatial.nodes.region_50.stocks.personnel_total == 12.0, "K transfer updates both branches even without a source control event")

func _structural_conditions() -> void:
	for condition: String in ["cover", "ammo", "suppression", "low_personnel", "asymmetric_stock"]:
		var records: Array[Dictionary] = []
		for aggregate: bool in [false, true]:
			var state: State = Fixtures.battle()
			if condition == "cover":
				state.areas.field.cover = 0.75
				state.areas.field.concealment = 0.35
			if condition in ["ammo", "low_personnel", "asymmetric_stock"]:
				state.totals.ammunition = 0.0
				state.totals.personnel = 0.0
				state.totals.equipment = 0.0
				for id: String in state.units:
					var unit: Dictionary = state.units[id]
					if condition == "ammo" and unit.side == "blue": unit.ammunition = 3.0
					if condition == "low_personnel":
						unit.personnel_total = 0.5
						unit.effective = 0.5
						unit.equipment = 0.5
						unit.ammunition = 40.0
					if condition == "asymmetric_stock" and unit.side == "red":
						unit.personnel_total = 24.0
						unit.effective = 24.0
						unit.equipment = 24.0
						unit.ammunition = 1920.0
					state.totals.personnel += float(unit.personnel_total)
					state.totals.equipment += float(unit.equipment)
					state.totals.ammunition += float(unit.ammunition)
			if condition == "suppression":
				for index: int in range(20): state.units["unit_%03d" % index].suppression = 0.9
			var owner: Authority = _owned(state)
			if aggregate: Fixtures.coalesce_sides(owner, state, 40)
			owner.advance(3600.0)
			_audit(state, "structural " + condition)
			records.append(owner.macro_summary())
		for side: String in ["blue", "red"]:
			for key: String in ["casualties", "ammo_spent"]:
				_check(absf(float(records[0].sides[side][key]) - float(records[1].sides[side][key])) <= maxf(1.0, float(records[0].sides[side][key])) * 0.20, "same structural cause " + condition + key)
		evidence.append({"test": "structural_conditions", "condition": condition, "detailed": records[0], "aggregate": records[1]})
	var incompatible: State = Fixtures.battle()
	incompatible.units.unit_001.ammunition = 0.0
	var guard: Authority = _owned(incompatible)
	var before: Dictionary = guard.snapshot()
	var ids: Array[String] = ["unit_000", "unit_001"]
	_check(not guard.coalesce("incompatible_supply", ids).ok and guard.snapshot() == before, "ammunition pooling cannot revive a depleted squad")
	var conditions: State = Fixtures.battle()
	for id: String in conditions.units:
		conditions.units[id].fatigue = 0.5
		conditions.units[id].cohesion = 0.7
		conditions.units[id].suppression = 0.6
	var condition_owner: Authority = _owned(conditions)
	Fixtures.coalesce_sides(condition_owner, conditions, 40)
	condition_owner.advance(30.0)
	var proposal: Dictionary = condition_owner.preview_leaf("unit_000")
	var record: Dictionary = condition_owner.read_leaf("unit_000")
	for key: String in Authority.STOCKS + Authority.CONDITIONS + ["id", "position", "distance_moved", "action", "resolved_through"]:
		_check(proposal[key] == record[key], "materialization preserves proposed current fact " + key)
	_check(record.fatigue >= 0.5 and record.cohesion <= 0.7 and record.suppression > 0.0, "materialization does not reset fatigue/cohesion/suppression")
	_check(record.mission_id != proposal.mission_id and conditions.missions[record.mission_id].status == "active", "materialized mission owns status without mutating its shared template")
	_check(record.ammunition < 960.0 and record.casualties > 0.0 and record.unresolved_history.no_individual_contact_history, "materialization carries causal losses without fabricating micro history")

func _events() -> void:
	var state: State = Fixtures.battle()
	var authority: Authority = _owned(state)
	Fixtures.coalesce_sides(authority, state, 40)
	state.add_mission(Data.mission("hold_order", "hold"))
	_check(state.schedule_event("order", 17.0, "order", {"unit_id": "unit_000", "mission_id": "hold_order"}), "M suspended identity accepts exact future order")
	_check(state.schedule_event("reinforce", 21.0, "reinforcement", {"unit": Data.unit("reinforce", "blue", "field", "hold_order")}), "M reinforcement")
	_check(state.schedule_event("terrain", 25.0, "area_change", {"area_id": "field", "cover": 0.75}), "M terrain")
	authority.advance(16.0)
	_check(not state.units.has("unit_000"), "M materialization not early")
	var at: Dictionary = authority.advance(17.0)
	_check(state.units.has("unit_000") and state.units.unit_000.mission_id == "hold_order" and at.counters.events_processed == 1, "M order exactly at boundary")
	_check(authority.counters().leaf_records_materialized == 1, "M order only one leaf materialized")
	authority.advance(24.0)
	_check(state.units.has("reinforce") and state.areas.field.cover == 0.1, "M reinforcement before terrain")
	authority.advance(25.0)
	_check(state.areas.field.cover == 0.75, "M terrain exact boundary")
	for index: int in range(10, 20):
		_check(state.schedule_event("full_%02d" % index, 31.0, "order", {"unit_id": "unit_%03d" % index, "mission_id": "hold_order"}), "M queued full cohort order")
	var full: Dictionary = authority.advance(40.0)
	_check(full.ok and authority.counters().leaf_records_materialized == 11, "M retired aggregate removed from current deltas at event boundary")
	for id: String in full.state_delta.units:
		_check(state.units.has(id), "M delta contains only live representations")
	_audit(state, "M event ledgers")
	var reserves: State = Scenarios.create()
	reserves.set_coordination("attack_00", {"release_time": 317.0, "role": "advance"})
	var reserve_solver: Authority = _owned(reserves)
	var siblings: Array[String] = ["attack_01", "attack_02", "attack_03", "attack_04", "attack_05"]
	_check(reserve_solver.coalesce("other_attacks", siblings).ok, "M incompatible reserve retains necessary detail")
	reserve_solver.advance(316.0, Resolver.AGGREGATE)
	_check(reserves.units.attack_00.position == 0.5, "M reserve not released early")
	reserve_solver.advance(317.0, Resolver.AGGREGATE)
	_check(reserves.units.attack_00.position == 0.5 and reserves.counters.events_processed == 1, "M release no retroactive motion")
	reserve_solver.advance(360.0, Resolver.AGGREGATE)
	_check(float(reserves.units.attack_00.position) > 0.5, "M reserve advances after boundary")
	evidence.append({"test": "M", "event_work": authority.counters(), "materializations": authority.materialization_events})

func _roles() -> void:
	for role: String in Roles.ROLES:
		var state: State = Scenarios.create()
		var service: Roles = Roles.new()
		_check(service.configure(state, RoleFixtures.hierarchy(), RoleFixtures.people(), role), "N original person admission")
		var authority: Authority = _owned(state)
		_check(service.bind_lod(authority), "N bind only owner state")
		var attacks: Array[String] = ["attack_00", "attack_01", "attack_02", "attack_03", "attack_04", "attack_05"]
		_check(authority.coalesce("blue_attacks", attacks).ok, "N coalesce unchanged squad identities")
		var snapshot: Dictionary = authority.snapshot()
		var rejected: Dictionary = service.apply(RoleFixtures.command("bad", "local_action", "foreign_person", {"action": "wait"}))
		_check(not rejected.ok and authority.snapshot() == snapshot and authority.counters().leaf_records_materialized == 0, "N unauthorized command cannot trigger materialization")
		var kind: String = "mission"
		var target: String = str(service.command_scope().targets.get("mission", [""])[0])
		var values: Dictionary = RoleFixtures.mission_values()
		if role == "ordinary_soldier":
			kind = "local_action"
			target = role
			values = {"action": "take_cover"}
		elif role == "squad_leader":
			kind = "tactical_intent"
			target = "squad_attack_00"
			values = {"posture": "hold"}
		var accepted: Dictionary = service.apply(RoleFixtures.command("valid", kind, target, values))
		_check(accepted.ok, "N original legal input " + role)
		var expected: int = 0 if role == "ordinary_soldier" else (1 if role in ["squad_leader", "platoon_leader"] else (3 if role == "company_commander" else 6))
		_check(authority.counters().leaf_records_materialized == expected, "N minimum required subordinate scope " + role)
		snapshot = authority.snapshot()
		_check(not service.apply(RoleFixtures.command("early", kind, target, values)).ok and authority.snapshot() == snapshot, "N cooldown remains atomic")
		if role == "platoon_leader":
			_check(not service.apply(RoleFixtures.command("early_other", "mission", "squad_attack_01", values)).ok and authority.snapshot() == snapshot, "N rejected command preview cannot settle or materialize other subordinate")
		var report_before: Dictionary = authority.snapshot()
		service.report()
		_check(authority.snapshot() == report_before, "N unresolved report projections do not alter truth")
		_check(authority.advance(3600.0).ok and float(state.totals.casualties) > 0.0, "N AI continues under role input")
		_audit(state, "N " + role)
		evidence.append({"test": "N", "role": role, "work": authority.counters()})

func _symmetry() -> void:
	var a: State = Fixtures.battle()
	var b: State = Fixtures.battle()
	var one: Authority = _owned(a)
	var two: Authority = _owned(b)
	Fixtures.coalesce_sides(one, a, 40)
	for start: int in [30, 20, 10, 0]:
		var ids: Array[String] = []
		for index: int in range(start, start + 10):
			ids.append("unit_%03d" % index)
		_check(two.coalesce("formation_%03d" % start, ids).ok, "P reverse construction order")
	one.advance(3600.0)
	two.advance(3600.0)
	_check(one.snapshot() == two.snapshot(), "P exact update/insertion-order symmetry")
	var mirror: State = Fixtures.battle()
	for id: String in mirror.units:
		mirror.units[id].side = "last" if mirror.units[id].side == "blue" else "first"
	var mirrored: Authority = _owned(mirror)
	Fixtures.coalesce_sides(mirrored, mirror, 40)
	mirrored.advance(3600.0)
	for id: String in a.units:
		for key: String in Authority.STOCKS + ["position", "suppression"]:
			_check(a.units[id][key] == mirror.units[id][key], "P faction label symmetry")

func _lod_axes() -> void:
	var summaries: Array[Dictionary] = []
	for level: String in ["platoon", "company", "battalion"]:
		var state: State = Fixtures.hierarchy()
		var owner: Authority = _owned(state)
		for start: int in [0, 2]:
			var ids: Array[String] = ["cell_037_unit_%02d" % start, "cell_037_unit_%02d" % (start + 1)]
			_check(owner.coalesce("same_members_%d" % start, ids, level).ok, "independent formation level in 5km cell")
		var before: Dictionary = owner.snapshot()
		var view: Dictionary = owner.spatial.view("region_50")
		view.stocks.clear()
		_check(owner.snapshot() == before and not owner.spatial.nodes.region_50.stocks.is_empty(), "50km summary view has no war authority or automatic materialization")
		owner.advance(3600.0)
		summaries.append(owner.macro_summary())
	_check(summaries[0] == summaries[1] and summaries[1] == summaries[2], "formation/spatial level labels do not change laws")
