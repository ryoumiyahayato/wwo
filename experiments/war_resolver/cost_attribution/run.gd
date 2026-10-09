extends SceneTree
const Scenario = preload("res://experiments/war_resolver/continuity/scenario.gd")
const Probe = preload("res://experiments/war_resolver/cost_attribution/probe.gd")

func _initialize() -> void:
	var options: Dictionary = {"seed": "71", "seconds": "1800", "quota": "7", "diagnostic": "off", "sample-id": "", "output": "", "aggregate": "true", "level2": "off"}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() % 2 != 0:
		quit(1)
		return
	for index: int in range(0, args.size(), 2):
		var key: String = args[index].trim_prefix("--")
		if not options.has(key):
			quit(1)
			return
		options[key] = args[index+1]
	var scenario: Scenario = Scenario.new()
	var build_started: int = Time.get_ticks_usec()
	if not scenario.configure(int(options.seed), {"aggregate": options.aggregate == "true"}):
		quit(1)
		return
	var build_usec: int = Time.get_ticks_usec() - build_started
	var probe: Probe = null
	if options.diagnostic == "on":
		probe = Probe.new()
		probe.run_id = "20261009T191132-step-cost"
		probe.sample_id = options["sample-id"]
		probe.level2_enabled = options.level2 == "on"
		probe.level1_enabled = not probe.level2_enabled
		scenario.env.lod.cost_probe = probe
		scenario.env.decisions.cost_probe = probe
	var call_count: int = 0
	var api_total: int = 0
	var caller_replace: int = 0
	var max_api: int = 0
	var api_samples: Array[int] = []
	var pending_boundary_peak: int = scenario.env.state.events.size() + scenario.env.information._report_heap.size()
	var output: Dictionary = {}
	var loop_started: int = Time.get_ticks_usec()
	if int(options.quota) == 0:
		var started: int = Time.get_ticks_usec()
		output = scenario.advance(float(options.seconds))
		api_total = Time.get_ticks_usec()-started
		max_api = api_total
		call_count = 1
	else:
		while call_count < 10000000:
			var started: int = Time.get_ticks_usec()
			var returned: Dictionary = scenario.env.lod.advance_bounded(float(options.seconds), int(options.quota))
			var elapsed: int = Time.get_ticks_usec()-started
			if probe != null:
				probe.outer_return(elapsed)
			api_total += elapsed
			max_api = maxi(max_api, elapsed)
			if api_samples.size() < 4096:
				api_samples.append(elapsed)
			else:
				api_samples[call_count % 4096] = elapsed
			var replace_started: int = Time.get_ticks_usec()
			output = returned
			caller_replace += Time.get_ticks_usec()-replace_started
			pending_boundary_peak = maxi(pending_boundary_peak, scenario.env.state.events.size() + scenario.env.information._report_heap.size())
			call_count += 1
			if not output.ok or output.status != "PENDING":
				break
	var loop_usec: int = Time.get_ticks_usec()-loop_started
	if not output.ok or int(options.quota) > 0 and output.status != "COMPLETE":
		print("ATTRIBUTION_FAILURE=" + str(output))
		quit(1)
		return
	var query_started: int = Time.get_ticks_usec()
	var public: Dictionary = {"physical": scenario.physical(), "knowledge": scenario.env.information._knowledge.duplicate(true),
		"messages": scenario.env.information._messages.duplicate(true), "decisions": scenario.env.decisions.snapshot(),
		"structure": scenario.env.structure.snapshot(), "logistics": scenario.env.logistics.snapshot(),
		"work": {"kernel": scenario.env.state.counters.duplicate(), "lod": scenario.env.lod.counters(), "spatial": scenario.env.space.work.duplicate(), "information": scenario.env.information.work.duplicate(), "decisions": scenario.env.decisions.work.duplicate()}}
	var trace: Array = scenario.trace.export()
	var diagnostic: Dictionary = {} if probe == null else probe.export()
	var result: Dictionary = {"schema": "WWO_STEP_COST_RUN_V1", "sample_id": options["sample-id"], "seed": int(options.seed),
		"seconds": float(options.seconds), "quota": int(options.quota), "diagnostic_on": probe != null, "aggregate": options.aggregate,
		"public": public, "raw_mixed_trace": trace, "diagnostic": diagnostic, "ledger_balanced": scenario.ledger_balanced(),
		"result_status": output.get("status", "COMPLETE"), "phase_work_counts": output.get("phase_work_counts", {}),
		"original_global_primitive_max": {"usec": output.get("max_primitive_usec", 0), "label": output.get("max_primitive", ""), "scope": "one continuation global maximum; never subtract from an unrelated API maximum"},
		"backlog": {"pending_event_and_report_peak_at_api_boundaries": pending_boundary_peak,
			"pending_events_at_end": scenario.env.state.events.size(), "pending_reports_at_end": scenario.env.information._report_heap.size(),
			"final_commit_lag_seconds": float(options.seconds)-scenario.env.state.time, "scope": "API-boundary observations; not every transient internal queue peak"},
		"timing_usec": {"input_build": build_usec, "api_sum": api_total, "api_max": max_api, "caller_result_replacement": caller_replace,
			"advance_loop_inclusive": loop_usec}, "calls": call_count, "query_usec": Time.get_ticks_usec()-query_started}
	if not api_samples.is_empty():
		api_samples.sort()
		result.api_ring = {"count": api_samples.size(), "median": api_samples[api_samples.size()/2], "maximum": max_api, "scope": "last at most4096 calls; max covers all calls"}
	var cleanup_started: int = Time.get_ticks_usec()
	output = {}
	scenario = null
	result.timing_usec.end_world_cleanup = Time.get_ticks_usec()-cleanup_started
	var serialize_started: int = Time.get_ticks_usec()
	var encoded: String = JSON.stringify(result)
	var serialize_usec: int = Time.get_ticks_usec()-serialize_started
	var file: FileAccess = FileAccess.open(str(options.output), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(encoded + "\n")
	print("ATTRIBUTION_RUN=" + JSON.stringify({"sample_id": result.sample_id, "seed": result.seed, "diagnostic_on": result.diagnostic_on,
		"calls": call_count, "api_sum_usec": api_total, "api_max_usec": max_api, "end_cleanup_usec": result.timing_usec.end_world_cleanup,
		"query_usec": result.query_usec, "serialization_usec": serialize_usec, "result_bytes": encoded.to_utf8_buffer().size(), "ledger_balanced": result.ledger_balanced}))
	quit(0 if result.ledger_balanced else 1)
