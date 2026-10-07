extends SceneTree
const F = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const Scenario = preload("res://experiments/war_resolver/continuity/scenario.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)
func _initialize() -> void:
	_dormancy()
	_sparse()
	_locality()
	_lod()
	_capacity()
	print("LOAD_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task9 load: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func finish(owner: F.Authority, target: float, quota: int = 31) -> Dictionary:
	var result: Dictionary = {}
	for call_index: int in range(3000000):
		result = owner.advance_bounded(target, quota)
		if not result.ok or result.status != "PENDING":
			break
	return result
func active_physical(state: F.State) -> Dictionary:
	var result: Dictionary = {}
	for index: int in range(40):
		var id: String = "unit_%03d" % index
		result[id] = state.units[id].duplicate(true)
	return result
func _dormancy() -> void:
	var values: Array[Dictionary] = []
	var expected: Dictionary = {}
	var counters: Dictionary = {}
	for sleeping: int in [0, 10000]:
		var start: int = Time.get_ticks_usec()
		var state: F.State = F.battle(40, 71, sleeping)
		var owner: F.Authority = F.Authority.new()
		owner.configure(state)
		var built: int = Time.get_ticks_usec()
		var result: Dictionary = finish(owner, 30.0)
		check(result.ok and result.status == "COMPLETE", "dormant-scale continuation completes")
		if sleeping == 0:
			expected = active_physical(state)
			counters = state.counters.duplicate()
		else:
			check(expected == active_physical(state) and counters == state.counters, "10000 sleeping areas/30000 squads add zero active core work")
		values.append({"sleeping_areas": sleeping, "sleeping_squads": sleeping*3, "input_build_ms": (built-start)/1000.0, "active_counters": state.counters.duplicate(), "last_call": result, "static_memory_bytes": OS.get_static_memory_usage()})
	evidence.dormancy = values
func _sparse() -> void:
	var state: F.State = F.battle(400, 71, 0, "field", true)
	var owner: F.Authority = F.Authority.new()
	owner.configure(state)
	check(finish(owner, 30.0).ok, "sparse contact advances")
	check(owner._kernel.work.candidate_contacts_examined < 400*400/10 and state.counters.contacts_resolved > 0, "sparse candidates avoid all-pairs while retaining legal nearby contact")
	evidence.sparse = owner.counters()
func _locality() -> void:
	var scenario: Scenario = Scenario.new()
	check(scenario.configure(71, {"long_run": true}), "locality fixture")
	check(finish(scenario.env.lod, 1800.0).ok, "locality causal checkpoint")
	var before: Dictionary = scenario.env.state.counters.duplicate()
	var materialized: int = scenario.env.lod.work.leaf_records_materialized
	for index: int in range(100):
		scenario.env.lod.spatial.view("region_50")
	check(before == scenario.env.state.counters and materialized == scenario.env.lod.work.leaf_records_materialized, "large summary reads do not settle or materialize")
	var untouched: Dictionary = {}
	for id: String in scenario.env.lod._groups:
		if scenario.env.state.units[id].area_id == "cell_099":
			untouched[id] = scenario.env.lod._groups[id].duplicate(true)
	for index: int in range(4):
		scenario.env.space.unload_cell("cell_037")
		scenario.env.space.load_cell("cell_037")
		scenario.env.lod.zoom_in("cell_037")
	check(scenario.env.space._loaded.size() == 2 and not scenario.env.space.edge_view("bridge_BD").open, "repeated focus reload preserves damage and geometry locality")
	var unchanged: bool = true
	for id: String in untouched:
		unchanged = unchanged and scenario.env.lod._groups.has(id) and scenario.env.lod._groups[id] == untouched[id]
	check(unchanged and untouched.size() == 2, "focus actions preserve unrelated sleeping cohorts")
	check(scenario.ledger_balanced(), "focus operations preserve resources")
	evidence.locality = {"unrelated_cohorts": untouched.size(), "materialized_leaf_delta": scenario.env.lod.work.leaf_records_materialized-materialized, "loaded_cells": scenario.env.space._loaded.size()}
func _project(scenario: Scenario) -> Dictionary:
	var result: Dictionary = {}
	for index: int in range(4):
		var id: String = "unit_%03d" % index
		result[id] = scenario.env.lod.preview_leaf(id)
	return result
func _lod() -> void:
	var worst: Dictionary = {"relative": 0.0, "distance_km": 0.0}
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		for variant: String in ["blue", "red", "both", "zoom90", "zoom730"]:
			var reference: Scenario = Scenario.new()
			var candidate: Scenario = Scenario.new()
			check(reference.configure(seed_value, {"aggregate": false}) and candidate.configure(seed_value, {"aggregate": variant != "red"}), "LOD seed/variant admission")
			if variant in ["red", "both"]:
				var reds: Array[String] = ["unit_002", "unit_003"]
				check(candidate.env.lod.coalesce("red_platoon", reds).ok, "one-sided red aggregation")
			if variant in ["zoom90", "zoom730"]:
				var when: float = 90.0 if variant == "zoom90" else 730.0
				reference.advance(when)
				candidate.advance(when)
				check(candidate.env.lod.materialize_leaf("unit_000", "test_focus").ok, "local leaf materialization at fixed time")
			reference.advance(1800.0)
			candidate.advance(1800.0)
			var lhs: Dictionary = _project(reference)
			var rhs: Dictionary = _project(candidate)
			var compatible: bool = reference.ledger_balanced() and candidate.ledger_balanced()
			for id: String in lhs:
				for key: String in ["effective", "casualties", "ammunition", "ammo_spent", "equipment", "equipment_lost", "fuel", "fuel_spent"]:
					var difference: float = absf(float(lhs[id][key])-float(rhs[id][key]))/maxf(1.0, absf(float(lhs[id][key])))
					compatible = compatible and difference <= 0.20
					if difference > float(worst.relative):
						worst.merge({"relative": difference, "seed": seed_value, "variant": variant, "leaf": id, "key": key}, true)
				var distance: float = absf(float(lhs[id].distance_moved)-float(rhs[id].distance_moved))
				worst.distance_km = maxf(float(worst.distance_km), distance)
				compatible = compatible and distance <= 0.20 and lhs[id].action == rhs[id].action and lhs[id].spatial.node == rhs[id].spatial.node
			check(compatible, "preregistered resource/distance/mission trend LOD tolerance")
	evidence.lod_worst = worst
func _capacity() -> void:
	var state: F.State = F.battle(1025)
	var owner: F.Authority = F.Authority.new()
	owner.configure(state)
	var result: Dictionary = finish(owner, 30.0, 1)
	check(not result.ok and result.status == "BLOCKED" and result.error == "ACTIVE_SCOPE_CAPACITY" and state.time == 0.0 and state.units.size() == 1025, "capacity backpressure retains events, actors and old committed time")
	check(state.snapshot().get("status") == "PENDING", "blocked partial input cannot be queried as current truth")
	evidence.capacity = result
