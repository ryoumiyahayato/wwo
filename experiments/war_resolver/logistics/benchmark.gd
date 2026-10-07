extends SceneTree
const F = preload("res://experiments/war_resolver/logistics/fixtures.gd")
const Base = preload("res://experiments/war_resolver/structure/fixtures.gd")

func _initialize() -> void:
	for name: String in ["detailed_unit", "40_formation", "100_formation", "100_specific_leaf", "40_attachment", "split_delivery", "retired_delivery", "1000_future", "40_formation_sleeping"]:
		var build_start: int = Time.get_ticks_usec()
		var count: int = 100 if name in ["100_formation", "100_specific_leaf"] else 40
		var env: Dictionary = F.setup(count, 10000 if name == "40_formation_sleeping" else 0, name != "detailed_unit")
		var built_ms: float = float(Time.get_ticks_usec() - build_start) / 1000.0
		var start: int = Time.get_ticks_usec()
		var kind: String = "unit" if name in ["detailed_unit", "100_specific_leaf", "40_attachment", "split_delivery", "retired_delivery"] else "formation"
		var target: String = "unit_000" if kind == "unit" else "blue_company"
		if name == "retired_delivery":
			target = "unit_001"
		assert(F.delivery(env, "primary", kind, target).ok)
		if name == "40_attachment":
			assert(env.commands.regiment.apply(Base.request("attach", "attach", 60.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0})).ok)
		if name == "split_delivery":
			assert(env.commands.company.apply(F.split(env)).ok)
		if name == "retired_delivery":
			assert(env.commands.company.apply(Base.request("merge", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"})).ok)
		if name == "1000_future":
			for index: int in range(999):
				assert(F.delivery(env, "future_%04d" % index, "formation", "blue_company", "AMMUNITION", 1.0, 60.0 if index < 2 else 100000.0 + float(index)).ok)
		var admission_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		var admission: Dictionary = env.logistics.work.duplicate()
		env.logistics.reset_work()
		start = Time.get_ticks_usec()
		assert(env.lod.advance(120.0).ok)
		var resolve_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		var relation: Dictionary = env.logistics.responsibility("unit_000")
		print("TASK6_BENCHMARK_JSON=" + JSON.stringify({"case": name, "underlying_squads": count,
			"sleeping_areas": 10000 if name == "40_formation_sleeping" else 0, "construction_wall_ms": built_ms,
			"allocation_wall_ms": admission_ms, "resolve_wall_ms": resolve_ms, "admission_work": admission,
			"logistics_work": env.logistics.work.duplicate(), "lod_work": env.lod.counters(),
			"structure_work": env.service.work.duplicate(), "combat_work": env.state.counters.duplicate(),
			"active_stocks": F.stocks(env), "active_sides": env.lod.macro_summary().sides,
			"relation": relation, "pending_events": env.state.events.size(), "audit": env.logistics.audit()}))
	quit(0)
