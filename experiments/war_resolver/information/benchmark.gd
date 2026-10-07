extends SceneTree
const F = preload("res://experiments/war_resolver/information/fixtures.gd")

func _initialize() -> void:
	for name: String in ["instant_report", "delayed_report", "delayed_command", "authority_invalidated", "100_formation_report", "100_leaf_report", "1000_pending_3_due", "40_sleeping_report", "conflicting_reports", "multiple_persons"]:
		var build: int = Time.get_ticks_usec()
		var env: Dictionary = F.setup(100 if name in ["100_formation_report", "100_leaf_report"] else 40, 10000 if name == "40_sleeping_report" else 0)
		var build_ms: float = float(Time.get_ticks_usec() - build) / 1000.0
		var start: int = Time.get_ticks_usec()
		if name in ["delayed_command", "authority_invalidated"]:
			assert(F.command(env).ok)
			if name == "authority_invalidated":
				assert(env.commands.regiment.apply(F.Structure.request("attach", "attach", 30.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0})).ok)
		elif name == "100_leaf_report":
			assert(F.observation(env, "observation", "soldier", "unit", "unit_000").ok)
			assert(F.report(env, "report", "observation", "soldier", "soldier").ok)
		elif name == "conflicting_reports":
			assert(F.external(env, "a").ok and F.external(env, "b", "external_division", "position", {"area_ref": "other_claimed_area", "band_km": [2.0, 3.0], "precision_km": 1.0}).ok)
			assert(F.report(env, "report_a", "a").ok and F.report(env, "report_b", "b", "division", "division").ok)
		elif name == "multiple_persons":
			for person: String in env.people:
				assert(F.external(env, "for_" + person).ok)
				assert(F.report(env, "report_" + person, "for_" + person, "company", person).ok)
		else:
			assert(F.observation(env).ok)
			if name == "1000_pending_3_due":
				for index: int in range(1000):
					assert(F.report(env, "message_%04d" % index, "observation", "company", "division", "delayed" if index < 3 else "later").ok)
			else:
				assert(F.report(env, "report", "observation", "company", "division", "instant" if name == "instant_report" else "delayed").ok)
		var admission_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		var admission: Dictionary = env.information.work.duplicate()
		env.information.reset_work()
		start = Time.get_ticks_usec()
		assert(env.lod.advance(120.0).ok)
		var resolve_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		var holder: String = "soldier" if name == "100_leaf_report" else "division"
		var knowledge: Dictionary = env.readers[holder].knowledge()
		print("TASK7_BENCHMARK_JSON=" + JSON.stringify({"case": name, "construction_wall_ms": build_ms, "admission_wall_ms": admission_ms, "resolve_wall_ms": resolve_ms,
			"admission_work": admission, "information_work": env.information.work.duplicate(), "lod_work": env.lod.counters(), "combat_work": env.state.counters.duplicate(),
			"structure_work": env.service.work.duplicate(), "logistics_work": env.logistics.work.duplicate(), "active_stocks": F.Base.stocks(env), "active_sides": env.lod.macro_summary().sides,
			"knowledge": knowledge, "pending_reports": env.information._report_heap.size(), "pending_causal_events": env.state.events.size()}))
	quit(0)
