extends SceneTree
const F = preload("res://experiments/war_resolver/structure/fixtures.gd")

func _initialize() -> void:
	_run.call_deferred()

static func difference(a: Dictionary, b: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in a:
		result[key] = int(a[key]) - int(b.get(key, 0))
	return result

func _run() -> void:
	for config: Dictionary in [
		{"case": "detailed_company_split", "count": 40, "sleeping": 0, "aggregate": false, "kind": "split"},
		{"case": "aggregate_leaf_detachment", "count": 40, "sleeping": 0, "aggregate": true, "kind": "split_leaf"},
		{"case": "40_aggregate_one_attachment", "count": 40, "sleeping": 0, "aggregate": true, "kind": "attach"},
		{"case": "100_aggregate_one_attachment", "count": 100, "sleeping": 0, "aggregate": true, "kind": "attach"},
		{"case": "40_aggregate_sleeping_attachment", "count": 40, "sleeping": 10000, "aggregate": true, "kind": "attach"},
		{"case": "attachment_expiry", "count": 40, "sleeping": 0, "aggregate": true, "kind": "expiry"}]:
		var env: Dictionary = F.setup(int(config.count), int(config.sleeping), bool(config.aggregate))
		assert(env.lod.advance(120.0).ok)
		if config.kind == "expiry":
			assert(env.commands.regiment.apply(F.request("attachment", "attach", 120.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 157.0})).ok)
			assert(env.lod.advance(156.0).ok)
		var structure_before: Dictionary = env.service.work.duplicate()
		var lod_before: Dictionary = env.lod.counters()
		var combat_before: Dictionary = env.state.counters.duplicate()
		var clock: float = float(env.state.time)
		var start: int = Time.get_ticks_usec()
		if config.kind == "split":
			assert(env.commands.battalion.apply(F.company_split(env)).ok)
		elif config.kind == "split_leaf":
			assert(env.commands.regiment.apply(F.split_request(env)).ok)
		elif config.kind == "attach":
			assert(env.commands.regiment.apply(F.request("attachment", "attach", 120.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 157.0})).ok)
		assert(env.lod.advance(157.0 if config.kind == "expiry" else 120.0).ok)
		assert(env.service.history[-1].outcome.ok)
		var elapsed: int = Time.get_ticks_usec() - start
		print("TASK5_BENCHMARK_JSON=" + JSON.stringify({"case": config.case, "underlying_squads": config.count,
			"sleeping_areas": config.sleeping, "sleeping_squads": int(config.sleeping) * 3,
			"structure_work": difference(env.service.work, structure_before),
			"lod_work": difference(env.lod.counters(), lod_before), "combat_work": difference(env.state.counters, combat_before),
			"time_before": clock, "time_after": env.state.time, "wall_ms": float(elapsed) / 1000.0,
			"outcome": env.service.history[-1], "active_sides": env.lod.macro_summary().sides}))
	quit(0)
