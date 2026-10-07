extends SceneTree
## Expected values come from geometry, finite-stock arithmetic and transformations.
const F = preload("res://experiments/war_resolver/spatial/fixtures.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func _initialize() -> void:
	_reference()
	_attributes()
	_bridge()
	_contact()
	_locality()
	_rejections()
	_dynamic_and_retreat()
	_long_retreat_and_dependency()
	print("SPATIAL_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task9 spatial: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func near(a: float, b: float, label: String, tolerance: float = 0.00000001) -> void:
	check(absf(a - b) <= tolerance, label + " got=" + str(a) + " expected=" + str(b))

func balanced(env: Dictionary) -> bool:
	var ledger: Dictionary = env.logistics.audit()
	for key: String in ledger.initial:
		if absf(float(ledger.initial[key]) - float(ledger.current_plus_spent_and_transit[key])) > 0.000001:
			return false
	return true

func _reference() -> void:
	var env: Dictionary = F.setup()
	check(env.space.inject_path("unit_000", ["AB"]).ok, "explicit initial path")
	check(env.lod.advance(10.0).ok, "hand reference advance")
	var unit: Dictionary = env.state.units.unit_000
	# 0.1 km / 0.6 km/min = 10 s; 12 equipment * 0.2 fuel/km * 0.1 km.
	near(unit.distance_moved, 0.1, "hand-computed distance")
	near(unit.fuel_spent, 0.24, "Task6 actual fuel")
	near(unit.fuel, 7.76, "finite stock remainder")
	check(unit.spatial.node == "B" and unit.area_id == env.graph.nodes.B.cell, "actual arrival")
	check(env.state.missions[unit.mission_id].status == "complete", "end of explicit route")
	check(balanced(env), "resource ledger after movement")
	var fork: Dictionary = F.setup(false)
	check(fork.space.inject_path("unit_000", ["AC", "CD"]).ok, "alternative branch")
	fork.lod.advance(25.0)
	near(fork.state.units.unit_000.distance_moved, 0.2, "two-edge total distance")
	check(fork.state.units.unit_000.spatial.node == "D", "alternative reaches D")
	evidence.hand_reference = {"distance_km": unit.distance_moved, "fuel_spent": unit.fuel_spent, "time": env.state.time}

func _attributes() -> void:
	var reference: Dictionary = {}
	for label: String in ["plain", "mountain", "forest", "desert", "swamp", "urban", "coast"]:
		var env: Dictionary = F.setup(false)
		env.space._edges.AB.ground.label = label
		env.space.inject_path("unit_000", ["AB"])
		env.lod.advance(10.0)
		var result: Dictionary = env.state.units.unit_000.duplicate(true)
		check(reference.is_empty() or result == reference, "same attributes different label " + label)
		reference = result
	var foot: Dictionary = F.setup(false)
	var motor: Dictionary = F.setup(true)
	for env: Dictionary in [foot, motor]:
		env.space._edges.AB.ground = F.ground("wet_slope", 0.0, 0.8, 0.4)
		env.space.inject_path("unit_000", ["AB"])
		env.lod.advance(10.0)
	check(foot.state.units.unit_000.distance_moved > 0.0 and motor.state.units.unit_000.distance_moved == 0.0, "wet/steep FOOT vs MOTORIZED")
	near(motor.state.units.unit_000.fuel_spent, 0.0, "blocked movement cannot spend travel fuel")
	var bare: Dictionary = F.setup(false, true)
	var cover: Dictionary = F.setup(false, true)
	var hidden: Dictionary = F.setup(false, true)
	cover.space._nodes.D.ground.cover = 0.8
	hidden.space._nodes.D.ground.concealment = 1.0
	for env: Dictionary in [bare, cover, hidden]:
		env.lod.advance(10.0)
	check(cover.state.units.unit_002.casualties < bare.state.units.unit_002.casualties, "physical cover changes incoming losses")
	near(cover.state.units.unit_000.ammo_spent, bare.state.units.unit_000.ammo_spent, "cover alone does not conceal")
	near(hidden.state.units.unit_000.ammo_spent, 0.0, "full target concealment prevents outgoing detected fire")
	check(hidden.state.units.unit_002.ammo_spent > 0.0, "concealed target still can observe exposed opponent")
	var varied: Dictionary = F.setup(false, true, false, 71, true)
	varied.space._nodes.C.ground.concealment = 0.5
	varied.lod.advance(10.0)
	var fire: Dictionary = {}
	for contact: Dictionary in varied.state.contacts[varied.graph.nodes.A.cell]:
		if contact.source == "unit_000":
			fire[contact.target] = contact.usable_fire_per_minute
	near(fire.unit_002, 2.0 * float(fire.unit_003), "diagnostic fire respects independent target detection")

func _bridge() -> void:
	var env: Dictionary = F.setup()
	env.space.inject_path("unit_000", ["AB", "bridge_BD"])
	check(env.space.schedule_fact("cut", 15.0, "bridge_BD", false).ok, "prepared external closure")
	check(not env.space.schedule_fact("cut", 15.0, "bridge_BD", false).ok, "duplicate fact rejected")
	env.lod.advance(15.0)
	var stopped: float = env.state.units.unit_000.distance_moved
	var fuel: float = env.state.units.unit_000.fuel
	check(stopped > 0.1 and stopped < 0.2 and env.state.units.unit_000.spatial.edge == "bridge_BD", "bridge cut while in transit")
	env.lod.advance(120.0)
	near(env.state.units.unit_000.distance_moved, stopped, "no teleport/refund on closure")
	near(env.state.units.unit_000.fuel, fuel, "no fuel refund")
	check(env.state.units.unit_000.spatial.blocked_edge == "bridge_BD", "execution creates blocked fact")
	check(env.space.set_path("unit_000", ["AB", "AC", "CD"], true).ok, "explicit return before alternative")
	env.lod.advance(180.0)
	check(env.state.units.unit_000.spatial.node == "D", "return and detour complete physically")
	check(env.state.units.unit_000.distance_moved > 0.3 and balanced(env), "detour includes sunk outward/return movement")
	var before: Dictionary = F.setup()
	before.space.inject_path("unit_000", ["AB", "bridge_BD"])
	before.space.schedule_fact("cut_before", 0.0, "bridge_BD", false)
	before.lod.advance(120.0)
	near(before.state.units.unit_000.distance_moved, 0.1, "closure before entering bridge")
	evidence.in_transit = {"stopped_distance": stopped, "remaining_fuel": fuel, "final_distance": env.state.units.unit_000.distance_moved}

func _contact() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		var a: Dictionary = F.setup(false, true, false, seed_value)
		var b: Dictionary = F.setup(false, true, true, seed_value)
		a.lod.advance(120.0)
		b.lod.advance(120.0)
		for id: String in a.state.units:
			for key: String in ["casualties", "ammo_spent", "equipment_lost", "suppression"]:
				near(a.state.units[id][key], b.state.units[id][key], "physical contact invariant under cell IDs " + key, 0.0)
		check(a.state.units.unit_000.ammo_spent > 0.0, "legal cross-cell contact")
		var reordered: Dictionary = F.setup(false, true, false, seed_value, false, true)
		reordered.lod.advance(120.0)
		check(a.state.units == reordered.state.units and a.state.totals == reordered.state.totals, "input ID insertion order is physically neutral")
	var river: Dictionary = F.setup(true, true)
	river.space._edges.bridge_BD.open = false
	river.lod.advance(10.0)
	check(river.state.units.unit_000.ammo_spent > 0.0, "closed movement edge does not block fire")
	var wall: Dictionary = F.setup(true, true)
	for key: String in wall.space._lanes:
		wall.space._lanes[key].fire = false
	wall.space.inject_path("unit_000", ["AB"])
	wall.lod.advance(10.0)
	near(wall.state.totals.ammo_spent, 0.0, "wall blocks fire")
	near(wall.state.units.unit_000.distance_moved, 0.1, "wall does not disconnect movement")

func _locality() -> void:
	var env: Dictionary = F.setup()
	var stocks: Dictionary = env.state.totals.duplicate(true)
	var unit: Dictionary = env.state.units.unit_000.duplicate(true)
	env.space.reset_work()
	env.space.schedule_fact("local_cut", 0.0, "bridge_BD", false)
	env.lod.advance(0.0)
	check(env.space.work.fact_nodes_updated == 3 and env.space.work.fact_ancestors_updated == 2, "one facility updates one cell and two ancestors")
	check(stocks == env.state.totals and unit == env.state.units.unit_000, "closure does not change inventory or unit knowledge")
	check(env.space.load_cell(env.graph.nodes.B.cell).ok and env.space.unload_cell(env.graph.nodes.B.cell).ok, "local geometry loading")
	check(env.space.load_cell(env.graph.nodes.B.cell).ok and not env.space.edge_view("bridge_BD").open, "damage survives unload/reload")
	var future: Dictionary = F.setup()
	var all_admitted: bool = true
	for index: int in range(1000):
		all_admitted = future.space.schedule_fact("future_%04d" % index, 1.0 if index < 3 else 10000.0 + index, "bridge_BD", index % 2 == 0).ok and all_admitted
	check(all_admitted, "1000 future facts admitted as one fixture")
	future.space.reset_work()
	future.lod.advance(1.0)
	check(future.space.work.spatial_events_processed == 3 and future.space.work.future_facts_examined == 0 and future.state.events.size() == 997, "three due do not scan 997 future facts")
	var idle: Dictionary = F.setup()
	idle.lod.advance(120.0)
	idle.space.reset_work()
	var counters: Dictionary = idle.state.counters.duplicate()
	idle.lod.advance(86400.0)
	check(counters == idle.state.counters and idle.space.work.route_records_examined == 0, "idle world skips space work")
	var grouped: Dictionary = F.setup(false)
	var ids: Array[String] = ["unit_000", "unit_001"]
	check(grouped.lod.coalesce("blue_platoon", ids).ok, "same static footprint can coalesce")
	check(grouped.lod.zoom_in(grouped.graph.nodes.A.cell).materialized == 2, "local LOD preserves identities")
	check(balanced(grouped), "materialization preserves extended stocks")
	var moving: Dictionary = F.setup(false)
	for id: String in ["unit_000", "unit_001"]:
		moving.space.inject_path(id, ["AB", "bridge_BD"])
	var merged: Dictionary = moving.lod.coalesce("blue_platoon", ids)
	check(merged.ok, "compatible moving route coalesces")
	moving.lod.advance(15.0)
	var route: Dictionary = moving.state.units[merged.aggregate_id].spatial.duplicate(true)
	check(moving.lod.preview_leaf("unit_000").spatial == route, "lazy leaf inherits current progress, never frozen path")
	check(moving.lod.zoom_in(moving.graph.nodes.B.cell).materialized == 2, "moving aggregate index follows destination cell")
	check(moving.state.units.has("unit_000") and moving.state.units.unit_000.spatial == route and moving.state.time == 15.0 and balanced(moving), "local extraction does not replay past movement")
	var incompatible: Dictionary = F.setup(false)
	incompatible.space.inject_path("unit_000", ["AB"])
	incompatible.space.inject_path("unit_001", ["AC"])
	check(not incompatible.lod.coalesce("blue_platoon", ids).ok, "different routes retain distinct representations")

func _rejections() -> void:
	var env: Dictionary = F.setup()
	var before: Dictionary = env.state.snapshot()
	check(not env.space.inject_path("unit_000", ["unknown"]).ok, "unknown route rejected")
	check(not env.space.inject_path("unit_000", ["CD"]).ok, "noncontiguous route rejected")
	check(not env.space.schedule_fact("nan", NAN, "AB", false).ok, "NaN time rejected")
	check(not env.space.schedule_fact("negative", -1.0, "AB", false).ok, "negative time rejected")
	check(not env.state.schedule_event("unprepared", 1.0, "spatial", {"fact_id": "missing"}), "unprepared spatial ticket denied")
	check(before == env.state.snapshot(), "malformed input is atomic")

func _dynamic_and_retreat() -> void:
	var retreat: Dictionary = F.setup()
	retreat.space.inject_path("unit_000", ["AB", "bridge_BD"])
	retreat.lod.advance(5.0)
	# Minimal kernel counterexample, not a scenario assigning a battle outcome.
	retreat.state.units.unit_000.cohesion = 0.1
	retreat.lod.advance(20.0)
	check(retreat.state.units.unit_000.spatial.node == "A" and retreat.state.missions[retreat.state.units.unit_000.mission_id].status == "withdrawn", "existing cohesion withdrawal uses occupied known geometry")
	near(retreat.state.units.unit_000.distance_moved, 0.1, "withdrawal travels out and back without refund")
	check(balanced(retreat), "withdrawal conserves actual fuel")
	var changed: Dictionary = F.setup()
	changed.space.inject_path("unit_000", ["AB"])
	check(changed.space.schedule_ground("soften", 5.0, "edge", "AB", F.ground("mud", 1.0)).ok, "validated exact ground event")
	changed.lod.advance(10.0)
	var fatigue_at_five: float = 0.004 * 5.0 / 60.0
	near(changed.state.units.unit_000.distance_moved, 0.05 + 0.3 * (1.0 - fatigue_at_five * 0.5) * 5.0 / 60.0, "old speed before fact, new resistance afterward")
	check(balanced(changed), "dynamic ground consumes only actual travel")

func _long_retreat_and_dependency() -> void:
	var retreat: Dictionary = F.setup()
	retreat.space._edges.AB.length_km = 0.6
	retreat.space.inject_path("unit_000", ["AB"])
	retreat.lod.advance(65.0)
	check(retreat.state.units.unit_000.spatial.node == "B", "known completed previous leg")
	check(retreat.space.set_path("unit_000", ["bridge_BD"]).ok, "new task at current endpoint")
	retreat.state.units.unit_000.cohesion = 0.1
	retreat.lod.advance(200.0)
	check(retreat.state.units.unit_000.spatial.node == "A", "retreat direction stays consistent across several segments")
	near(retreat.state.units.unit_000.distance_moved, 1.2, "known 0.6-km leg out and back")
	check(balanced(retreat), "long retreat preserves actual fuel")
	var state: F.State = F.State.new()
	for cell: String in ["cell_037", "cell_038", "cell_062", "cell_063", "cell_099"]:
		state.add_area(F.Data.area(cell))
	state.add_mission(F.Data.mission("lead", "advance"))
	state.add_mission(F.Data.mission("follow", "advance", 1.0, 0.1))
	for pair: Array in [["lead_unit", "cell_037", "lead"], ["follow_unit", "cell_099", "follow"]]:
		var unit: Dictionary = F.Data.unit(pair[0], "blue", pair[1], pair[2])
		unit.mobility = 0.6
		unit.ammunition = 0.0
		unit.weapon.range_km = 0.0
		state.add_unit(unit)
	state.set_coordination("follow_unit", {"after": ["lead"], "role": "advance"})
	var lod: F.Authority = F.Authority.new()
	check(lod.configure(state), "one owner for cross-area dependency")
	var graph: Dictionary = F.topology()
	graph.edges.AB.length_km = 0.6
	var space: F.Space = F.Space.new()
	check(space.configure(state, lod, graph.nodes, graph.edges, graph.lanes) and space.admit_unit("lead_unit", "A", "FOOT"), "mixed legacy/spatial dependency fixture")
	space.inject_path("lead_unit", ["AB"])
	lod.advance(80.0)
	check(state.missions.lead.status == "complete" and state.missions.follow.status == "complete", "spatial completion wakes sleeping prerequisite follower")
	near(state.units.follow_unit.position, 0.1, "released follower performs its old-kernel movement")
