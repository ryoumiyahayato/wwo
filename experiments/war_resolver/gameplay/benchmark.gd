extends SceneTree
## Requested bounded feature cost comparisons; no performance pass threshold.
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")
var checks: int = 0
var failures: int = 0
var _reference: Dictionary = {}

func _initialize() -> void:
	for sample: int in range(6):
		var cases: Array[String] = ["off", "goals", "sleeping", "senior", "person", "lod", "burst"]
		if sample % 2 == 1:
			cases.reverse()
		for name: String in cases:
			_run(name, sample)
	print("Gameplay costs: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _run(name: String, sample: int) -> void:
	var memory_start: int = OS.get_static_memory_usage()
	var started: int = Time.get_ticks_usec()
	var env: Dictionary = F.setup(71, {"background": true, "sleeping_areas": 10000 if name == "sleeping" else 0,
		"gameplay_enabled": name != "off", "personal": name in ["person", "burst"]})
	var construction: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for side: String in ["blue", "red"]:
		var ids: Array[String] = ["remote_" + side + "_0", "remote_" + side + "_1"]
		check(env.lod.coalesce("remote_" + side + "_platoon", ids, "platoon").ok, "bounded background admission")
	if name != "off":
		check(env.gameplay.admit_standing("unit_000", "same_guard", "squad", F.intent("hold", "A")).ok, "same optional goal admission")
	var admission: int = Time.get_ticks_usec() - started
	var built_memory: int = OS.get_static_memory_usage() - memory_start
	var input_cost: int = 0
	if name in ["person", "burst"]:
		check(F.report(env, "soldier", "soldier_local", "cover", "actual_cover", "soldier"), "bounded own cover knowledge")
		check(F.advance(env, 0.0).ok, "own actual receipt")
		started = Time.get_ticks_usec()
		check(F.local(env, "soldier", "one_person", "take_cover" if name == "person" else "wait").ok, "one person input")
		input_cost += Time.get_ticks_usec() - started
	if name == "senior":
		started = Time.get_ticks_usec()
		check(F.command(env, "company", "senior_assignment", F.intent("advance", "B", ["AB"]), "blue_platoon").ok, "existing high-role assignment")
		input_cost += Time.get_ticks_usec() - started
	if name == "burst":
		started = Time.get_ticks_usec()
		check(F.command(env, "squad", "one_squad", F.intent("hold", "A")).ok, "same-clock squad input")
		check(F.command(env, "platoon", "one_platoon", F.intent("advance", "B", ["AB"])).ok, "same-clock platoon input")
		check(F.command(env, "company", "one_company", F.intent("advance", "B", ["AB"]), "blue_platoon").ok, "same-clock high input")
		input_cost += Time.get_ticks_usec() - started
	# Optional narrow counters are ON only in this cost driver, OFF in demos.
	env.gameplay.measure_cost = true
	env.gameplay.participants.measure_cost = true
	started = Time.get_ticks_usec()
	check(F.advance(env, 600.0).ok, "first ordinary advance")
	var advance_usec: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	if name == "lod":
		check(env.lod.zoom_in("cell_038").ok, "one cell LOD conversion")
	var lod_usec: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	check(F.advance(env, 1800.0).ok, "second ordinary advance")
	advance_usec += Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var units: Dictionary = {}
	for id: String in ["unit_000", "unit_001", "unit_002", "unit_003"]:
		units[id] = env.state.units[id].duplicate(true)
	var comparison: Dictionary = {"units": units, "counters": env.state.counters.duplicate(), "goal_work": env.gameplay.work.duplicate(), "person_work": env.gameplay.participants.work.duplicate(), "random": env.state.random_state.duplicate()}
	if name == "goals":
		_reference = comparison.duplicate(true)
	if name == "sleeping":
		check(comparison == _reference, "10000 sleeping areas and 30000 squads add zero active work or outcome changes")
	var ledger: Dictionary = env.logistics.audit()
	var ledger_ok: bool = true
	for key: String in ledger.initial:
		ledger_ok = ledger_ok and absf(float(ledger.initial[key]) - float(ledger.current_plus_spent_and_transit[key])) < 0.000001
	check(ledger_ok, "cost case conserves actual inventories")
	var row: Dictionary = {"case": name, "sample": sample, "warmup": sample == 0, "construction_usec": construction, "admission_usec": admission,
		"advance_usec": advance_usec, "input_issue_usec": input_cost, "intent_delivery_usec": env.gameplay.cost_usec.goal_delivery,
		"goal_commit_usec": env.gameplay.cost_usec.goal_commit, "person_processing_usec": env.gameplay.participants.cost_usec.duplicate(),
		"lod_conversion_usec": lod_usec, "result_preparation_usec": 0, "cleanup_usec": 0, "output_serialization_usec": 0,
		"built_static_memory_delta_bytes": built_memory, "core_work": env.state.counters.duplicate(), "new_goal_work": env.gameplay.work.duplicate(),
		"new_person_work": env.gameplay.participants.work.duplicate(), "person_count": env.gameplay.participants._units.size(), "active_representations": env.state.units.size() - (30000 if name == "sleeping" else 0),
		"summary_state_bytes": JSON.stringify(units).to_utf8_buffer().size(), "ledger_balanced": ledger_ok}
	row.result_preparation_usec = Time.get_ticks_usec() - started
	var world: WeakRef = weakref(env.state)
	started = Time.get_ticks_usec()
	env.clear()
	row.cleanup_usec = Time.get_ticks_usec() - started
	row.world_handle_released = world.get_ref() == null
	check(row.world_handle_released, "explicit caller handle release without new strong-reference retention")
	started = Time.get_ticks_usec()
	var encoded: String = JSON.stringify(row)
	row.output_serialization_usec = Time.get_ticks_usec() - started
	row.output_bytes = encoded.to_utf8_buffer().size()
	print("GAMEPLAY_COST=" + JSON.stringify(row))
