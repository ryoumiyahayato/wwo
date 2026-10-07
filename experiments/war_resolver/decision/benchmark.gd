extends SceneTree
const F = preload("res://experiments/war_resolver/decision/fixtures.gd")

func _initialize() -> void:
	for name: String in ["single_scheduled", "report_later_decision", "urgent_wake", "delayed_command", "authority_invalidated", "conflicting_knowledge", "1000_persons_3_due", "100_aggregate_commander", "40_sleeping_decision", "player_autonomous_same_context"]:
		var start: int = Time.get_ticks_usec()
		var env: Dictionary = F.setup(100 if name == "100_aggregate_commander" else 40, 10000 if name == "40_sleeping_decision" else 0, true, 71, true, 1000 if name == "1000_persons_3_due" else 8)
		var construction_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		if name == "1000_persons_3_due":
			for person: String in env.people:
				assert(F.opportunity(env, "person_" + person, person, 10.0 if person in ["platoon", "company", "soldier"] else 100000.0).ok)
		else:
			if name == "100_aggregate_commander":
				assert(F.InfoF.observation(env, "macro", "company", "formation", "blue_company", "status").ok)
				assert(F.InfoF.report(env, "report", "macro", "company", "company", "instant").ok)
				F.policy(env, "company", "keep")
			elif name != "single_scheduled":
				assert(F.claim(env, "report", "platoon", "status", {}, "delayed" if name in ["report_later_decision", "urgent_wake"] else "instant").ok)
			if name == "conflicting_knowledge":
				assert(F.claim(env, "conflict", "platoon", "status", {"states": ["withdraw"]}, "instant", "external_division").ok)
			assert(F.opportunity(env, "decision", "company" if name == "100_aggregate_commander" else "platoon", 200.0 if name == "urgent_wake" else (60.0 if name == "report_later_decision" else 10.0)).ok)
			if name == "urgent_wake":
				assert(env.decisions.admit_urgent("platoon", "report").ok)
			if name == "authority_invalidated":
				assert(env.commands.regiment.apply({"id": "attach", "kind": "attach", "effective_time": 15.0, "values": {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0}}).ok)
		var admission_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		var admission: Dictionary = env.decisions.work.duplicate()
		env.decisions.reset_work()
		start = Time.get_ticks_usec()
		assert(env.lod.advance(120.0).ok)
		var wall_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		var parity: bool = true
		if name == "player_autonomous_same_context":
			var player: F.Adapter = F.Adapter.new()
			assert(player.configure("player", F.Policy.new()))
			var context: Dictionary = env.decisions.result("decision").context
			parity = player.evaluate(context) == env.adapters.platoon.evaluate(context)
		print("TASK8_BENCHMARK_JSON=" + JSON.stringify({"case": name, "construction_wall_ms": construction_ms, "admission_wall_ms": admission_ms, "resolve_wall_ms": wall_ms,
			"admission_work": admission, "decision_work": env.decisions.work.duplicate(), "information_work": env.information.work.duplicate(),
			"combat_work": env.state.counters.duplicate(), "lod_work": env.lod.counters(), "structure_work": env.service.work.duplicate(), "logistics_work": env.logistics.work.duplicate(),
			"stocks": F.LogF.stocks(env), "active_sides": env.lod.macro_summary().sides, "pending_events": env.state.events.size(), "parity": parity,
			"decision": env.decisions.result("decision") if name != "1000_persons_3_due" else {}}))
	quit(0)
