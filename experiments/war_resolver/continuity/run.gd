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
	if not is_finite(seconds) or seconds < 0.0 or seconds > 604800.0 or int(options.quota) != 0:
		_abort("M2 supports finite time 0..604800 and quota=0 only; bounded quota awaits M3")
		return
	var inputs: Dictionary = {}
	match str(options.scenario):
		"main": pass
		"no-cut": inputs.bridge_cut = false
		"slow-reports": inputs.report_latency = 347.0
		"no-supply": inputs.supply = false
		"keep": inputs = {"bridge_cut": false, "keep_only": true}
		"cycles-disabled": inputs = {"bridge_cut": false, "keep_only": true, "repeated": false}
		_:
			_abort("Unknown synthetic scenario")
			return
	var scenario: Scenario = Scenario.new()
	var start: int = Time.get_ticks_usec()
	if not scenario.configure(int(options.seed), inputs):
		_abort("Synthetic admission failed")
		return
	var built: int = Time.get_ticks_usec()
	var output: Dictionary = scenario.advance(seconds)
	var advanced: int = Time.get_ticks_usec()
	if not output.ok:
		_abort(str(output))
		return
	var result: Dictionary = {"schema": "WWO_TASK9_CAUSAL_V0", "synthetic": true, "scenario": options.scenario, "seed": int(options.seed),
		"game_time": scenario.env.state.time, "engine": Engine.get_version_info().string, "platform": OS.get_name(),
		"physical": scenario.physical(), "ledger_balanced": scenario.ledger_balanced(), "decisions": scenario.env.decisions.snapshot(),
		"work": {"kernel": scenario.env.state.counters, "lod": scenario.env.lod.counters(), "spatial": scenario.env.space.work, "information": scenario.env.information.work, "decisions": scenario.env.decisions.work},
		"trace": scenario.trace.export(), "timeline": scenario.trace.timeline(), "diagnostic_retained": scenario.trace.page().retained,
		"wall_ms": {"input_build": (built-start)/1000.0, "advance": (advanced-built)/1000.0}, "quota": 0,
		"limits": ["finite local encounter envelope", "synthetic scope and test policy", "external supply ETA independent of routes", "M3 bounded continuation NOT IMPLEMENTED"]}
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
