extends SceneTree
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
const Data = preload("res://experiments/war_resolver/data.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cases: Array[Dictionary] = [
		{"name": "few_active_detailed", "sleeping": 0, "policy": Resolver.DETAILED},
		{"name": "many_sleeping_detailed", "sleeping": 10000, "policy": Resolver.DETAILED},
		{"name": "same_battle_aggregate", "sleeping": 0, "policy": Resolver.AGGREGATE},
		{"name": "many_sleeping_aggregate", "sleeping": 10000, "policy": Resolver.AGGREGATE},
		{"name": "four_active_groups", "sleeping": 0, "policy": Resolver.DETAILED, "groups": 4},
		{"name": "forty_active_groups", "sleeping": 0, "policy": Resolver.DETAILED, "groups": 40},
		{"name": "six_due_orders", "sleeping": 0, "policy": Resolver.AGGREGATE, "scenario": "communication_delay"}]
	for config: Dictionary in cases:
		var state: State = _active_groups(int(config.groups)) if config.has("groups") else Scenarios.create(str(config.get("scenario", "open_field_attack")), 71, int(config.sleeping))
		var active_count: int = state.units.size() - int(config.sleeping) * 3
		var memory_before: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = Resolver.new().resolve_until(state, 3600.0, str(config.policy))
		var elapsed: int = Time.get_ticks_usec() - start
		var memory_after: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var event_counts: Dictionary = {}
		for event: Dictionary in result.events:
			event_counts[event.kind] = int(event_counts.get(event.kind, 0)) + 1
		print("BENCHMARK_JSON=" + JSON.stringify({"case": config.name,
			"initial_active_areas": 1, "initial_active_units": active_count,
			"sleeping_areas": config.sleeping, "sleeping_units": int(config.sleeping) * 3,
			"simulated_seconds": 3600, "wall_usec": elapsed,
			"static_memory_before": memory_before, "static_memory_after": memory_after,
			"static_memory_delta": memory_after - memory_before,
			"summary": result.summary, "changes": result.state_delta,
			"events_by_kind": event_counts, "event_count": result.events.size()}))
		print("TRACE %s: 60 game minutes; %.3f casualties; %.3f ammunition; %d segments; %d contact evaluations; %d events" % [
			config.name, float(state.totals.casualties), float(state.totals.ammo_spent),
			int(state.counters.segments), int(state.counters.contacts_resolved), result.events.size()])
		var milestones: Array[String] = []
		for event: Dictionary in result.events:
			if event.kind == "losses" or milestones.size() >= 8:
				continue
			if event.kind == "action_changed" and event.action not in ["stalled", "withdraw", "withdrawn", "disabled"]:
				continue
			milestones.append("%.1fs %s %s %s %s" % [float(event.time), str(event.kind),
				str(event.get("unit_id", event.get("area_id", event.get("id", "")))),
				str(event.get("action", "")), str(event.get("reason", ""))])
		print("TRACE_CAUSES %s: %s" % [config.name, "; ".join(milestones)])
	quit(0)


func _active_groups(count: int) -> State:
	var state: State = State.new()
	state.seed = 71
	state.add_area(Data.area("field"))
	for index: int in range(count):
		var attack: bool = index < count / 2
		var id: String = "group_%02d" % index
		var mission: Dictionary = Data.mission("mission_" + id, "advance" if attack else "hold", 1.0, 2.0)
		state.add_mission(mission)
		state.add_unit(Data.unit(id, "blue" if attack else "red", "field", mission.id, 0.5 if attack else 3.5))
	return state
