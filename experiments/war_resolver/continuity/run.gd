extends SceneTree
## Reproducible headless entry; outputs facts, never scripted battle outcomes.
const Scenario = preload("res://experiments/war_resolver/continuity/scenario.gd")
func _initialize() -> void:
	var options: Dictionary = {"scenario": "main", "seed": "71", "seconds": "1800", "quota": "0", "output": ""}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() % 2 != 0:
		_abort("Arguments require --name value pairs")
		return
	for index: int in range(0, args.size(), 2):
		var key: String = args[index].trim_prefix("--")
		if not options.has(key):
			_abort("Unknown argument: " + args[index])
			return
		options[key] = args[index + 1]
	if not str(options.seed).is_valid_int() or not str(options.quota).is_valid_int() or not str(options.seconds).is_valid_float():
		_abort("Invalid seed/quota/time")
		return
	var seconds: float = float(options.seconds)
	if not is_finite(seconds) or seconds < 0.0 or seconds > 604800.0 or int(options.quota) < 0 or int(options.quota) > 100000:
		_abort("Finite time 0..604800 and quota 0..100000 required")
		return
	var inputs: Dictionary = {}
	match str(options.scenario):
		"main": pass
		"no-cut": inputs.bridge_cut = false
		"slow-reports": inputs.report_latency = 347.0
		"no-supply": inputs.supply = false
		"keep": inputs = {"bridge_cut": false, "keep_only": true}
		"cycles-disabled": inputs = {"bridge_cut": false, "keep_only": true, "repeated": false}
		"long": inputs.long_run = true
		_:
			_abort("Unknown synthetic scenario")
			return
	var scenario: Scenario = Scenario.new()
	var start: int = Time.get_ticks_usec()
	if not scenario.configure(int(options.seed), inputs):
		_abort("Synthetic admission failed")
		return
	var built: int = Time.get_ticks_usec()
	var output: Dictionary = {}
	var calls: int = 0
	var max_call_usec: int = 0
	var max_units: int = 0
	var samples: Array[int] = []
	if int(options.quota) == 0:
		output = scenario.advance(seconds)
		calls = 1
	else:
		while calls < 10000000:
			var begin: int = Time.get_ticks_usec()
			output = scenario.env.lod.advance_bounded(seconds, int(options.quota))
			var elapsed: int = Time.get_ticks_usec()-begin
			max_call_usec = maxi(max_call_usec, elapsed)
			max_units = maxi(max_units, int(output.work_units))
			if samples.size() < 4096:
				samples.append(elapsed)
			else:
				samples[calls % 4096] = elapsed
			calls += 1
			if not output.ok or output.status != "PENDING":
				break
	var advanced: int = Time.get_ticks_usec()
	if not output.ok or int(options.quota) > 0 and output.status != "COMPLETE":
		_abort(str(output))
		return
	var decision_data: Dictionary = scenario.env.decisions.snapshot()
	if inputs.get("long_run", false):
		var examples: Dictionary = {}
		for index: int in range(6):
			var id: String = "regular_%d" % index
			if decision_data.events.has(id):
				examples[id] = decision_data.events[id]
		decision_data = {"history_count": decision_data.events.size(), "first_six": examples, "cycles": decision_data.get("cycles", {}), "note": "bounded diagnostic examples; full authoritative history retained"}
	var result: Dictionary = {"schema": "WWO_TASK9_CAUSAL_V0", "synthetic": true, "scenario": options.scenario, "seed": int(options.seed),
		"game_time": scenario.env.state.time, "engine": Engine.get_version_info().string, "platform": OS.get_name(),
		"physical": scenario.physical(), "ledger_balanced": scenario.ledger_balanced(), "decisions": decision_data,
		"work": {"kernel": scenario.env.state.counters, "lod": scenario.env.lod.counters(), "spatial": scenario.env.space.work, "information": scenario.env.information.work, "decisions": scenario.env.decisions.work},
		"trace": scenario.trace.export(), "timeline": scenario.trace.timeline(), "diagnostic_retained": scenario.trace.page().retained,
		"wall_ms": {"input_build": (built-start)/1000.0, "advance": (advanced-built)/1000.0}, "quota": int(options.quota),
		"continuation": {"calls": calls, "max_call_usec": max_call_usec, "max_work_units": max_units, "last_result": output if int(options.quota) > 0 else {"status": "COMPLETE", "committed_time": scenario.env.state.time}},
		"storage": {"live_representations": scenario.env.state.units.size(), "cohorts": scenario.env.lod._groups.size(), "underlying_leaves": scenario.env.state.units.size()-scenario.env.lod._groups.size()+scenario.env.lod._owners.size(),
			"pending_events": scenario.env.state.events.size(), "pending_reports": scenario.env.information._report_heap.size(), "observations": scenario.env.information._observations.size(), "messages": scenario.env.information._messages.size(), "event_identity_records": scenario.env.state.event_ids.size(), "decision_history": scenario.env.decisions._events.size(), "diagnostic_total": scenario.trace.total, "geometry_focus_cells": scenario.env.space._loaded.size(), "active_cells": scenario.env.state.active_areas.size(), "static_memory_bytes": OS.get_static_memory_usage()},
		"limits": ["finite local encounter envelope", "synthetic scope and test policy", "external supply ETA independent of routes", "counted work quota; no hard wall-clock frame promise", "capacity backpressure preserves pending facts; authoritative histories grow"]}
	if not samples.is_empty():
		samples.sort()
		result.continuation.recent_sample_usec = {"p50": samples[int(samples.size()*0.5)], "p95": samples[mini(samples.size()-1,int(samples.size()*0.95))], "count": samples.size(), "scope": "last at most4096 calls; overall max measured across all calls"}
	result.wall_ms.query_and_result = (Time.get_ticks_usec()-advanced)/1000.0
	var encoded: String = JSON.stringify(result)
	if not str(options.output).is_empty():
		var file: FileAccess = FileAccess.open(str(options.output), FileAccess.WRITE)
		if file == null:
			_abort("Cannot open authorized result path")
			return
		file.store_string(encoded + "\n")
	print("WAR_CONTINUITY_RESULT_JSON=" + encoded)
	quit(0 if result.ledger_balanced else 1)

func _abort(reason: String) -> void:
	print("WAR_CONTINUITY_ERROR=" + reason)
	quit(1)
