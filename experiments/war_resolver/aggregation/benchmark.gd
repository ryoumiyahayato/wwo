extends SceneTree
const Fixtures = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")

func _initialize() -> void:
	_run.call_deferred()

func _difference(after: Dictionary, before: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for key: String in after:
		delta[key] = int(after[key]) - int(before.get(key, 0))
	return delta

func _run() -> void:
	var cases: Array[Dictionary] = [
		{"case": "10_detailed", "count": 10, "aggregate": false, "sleeping": 0},
		{"case": "40_detailed", "count": 40, "aggregate": false, "sleeping": 0},
		{"case": "40_formation", "count": 40, "aggregate": true, "sleeping": 0},
		{"case": "100_formation", "count": 100, "aggregate": true, "sleeping": 0},
		{"case": "100_sparse", "count": 100, "aggregate": false, "sparse": true, "sleeping": 0},
		{"case": "40_formation_sleeping", "count": 40, "aggregate": true, "sleeping": 10000},
		{"case": "100_sparse_sleeping", "count": 100, "aggregate": false, "sparse": true, "sleeping": 10000},
		{"case": "100_dense_real_contacts", "count": 100, "aggregate": false, "sleeping": 0}]
	for config: Dictionary in cases:
		var build_start: int = Time.get_ticks_usec()
		var state: State = Fixtures.battle(int(config.count), 71, int(config.sleeping), "field", bool(config.get("sparse", false)))
		var owner: Authority = Authority.new()
		assert(owner.configure(state))
		if config.aggregate:
			Fixtures.coalesce_sides(owner, state, int(config.count), 10)
		var build_usec: int = Time.get_ticks_usec() - build_start
		var before: Dictionary = owner.counters()
		var start: int = Time.get_ticks_usec()
		owner.advance(3600.0)
		var elapsed: int = Time.get_ticks_usec() - start
		print("TASK4_BENCHMARK_JSON=" + JSON.stringify({"case": config.case,
			"underlying_squads": config.count, "sleeping_areas": config.sleeping,
			"sleeping_squads": int(config.sleeping) * 3, "construction_work": before,
			"resolution_work": _difference(owner.counters(), before), "input_build_ms": float(build_usec) / 1000.0,
			"wall_ms": float(elapsed) / 1000.0, "summary": owner.macro_summary()}))
	var state: State = Fixtures.hierarchy()
	var owner: Authority = Authority.new()
	owner.configure(state)
	var before: Dictionary = owner.counters()
	var start: int = Time.get_ticks_usec()
	owner.advance(3600.0)
	var elapsed: int = Time.get_ticks_usec() - start
	print("TASK4_BENCHMARK_JSON=" + JSON.stringify({"case": "100_cells_one_active",
		"construction_work": before, "resolution_work": _difference(owner.counters(), before), "dirty_nodes": State.sorted_ids(owner.spatial.dirty),
		"wall_ms": float(elapsed) / 1000.0, "summary": owner.macro_summary()}))
	var world: State = Fixtures.hierarchy(true)
	var zoom: Authority = Authority.new()
	zoom.configure(world)
	for cell: int in range(100):
		Fixtures.coalesce_cell(zoom, "cell_%03d" % cell)
	zoom.advance(120.0)
	before = zoom.counters()
	start = Time.get_ticks_usec()
	var result: Dictionary = zoom.zoom_in("cell_037")
	elapsed = Time.get_ticks_usec() - start
	print("TASK4_BENCHMARK_JSON=" + JSON.stringify({"case": "50km_to_one_5km_zoom",
		"setup_work": before, "transition_work": _difference(zoom.counters(), before), "result": result,
		"world_time_before": 120.0, "world_time_after": world.time, "wall_ms": float(elapsed) / 1000.0}))
	quit(0)
