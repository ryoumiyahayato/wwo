extends SceneTree
const Scenario = preload("res://experiments/war_resolver/continuity/scenario.gd")
const Probe = preload("res://experiments/war_resolver/cost_attribution/probe.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func _initialize() -> void:
	for seed_value: int in [71, 109]:
		var reference: Dictionary = measure(seed_value, "off")
		for mode: String in ["broad", "narrow"]:
			var observed: Dictionary = measure(seed_value, mode)
			check(reference.public == observed.public, "diagnostic preserves all public state and original work seed%d %s" % [seed_value, mode])
			check(reference.raw_trace == observed.raw_trace, "same-quota raw diagnostic sequence remains exact")
			check(reference.phase_counts == observed.phase_counts, "diagnostic preserves primitive frequencies")
			check(reference.calls == observed.calls and reference.pending_peak == observed.pending_peak, "same API boundary backlog and call count")
	print("WWO cost attribution: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func measure(seed_value: int, mode: String) -> Dictionary:
	var scenario: Scenario = Scenario.new()
	check(scenario.configure(seed_value), "original continuous scenario admitted")
	check(scenario.env.lod.cost_probe == null and scenario.env.decisions.cost_probe == null, "diagnostics default OFF")
	var probe: Probe = null
	if mode != "off":
		probe = Probe.new()
		probe.run_id = "freeze-validation"
		probe.sample_id = "%d_%s" % [seed_value, mode]
		probe.level1_enabled = mode == "broad"
		probe.level2_enabled = mode == "narrow"
		scenario.env.lod.cost_probe = probe
		scenario.env.decisions.cost_probe = probe
	var output: Dictionary = {}
	var calls: int = 0
	var pending_peak: int = scenario.env.state.events.size() + scenario.env.information._report_heap.size()
	while calls < 100000:
		var started: int = Time.get_ticks_usec()
		output = scenario.env.lod.advance_bounded(1800.0, 7)
		var elapsed: int = Time.get_ticks_usec()-started
		if probe != null:
			probe.outer_return(elapsed)
		pending_peak = maxi(pending_peak, scenario.env.state.events.size() + scenario.env.information._report_heap.size())
		calls += 1
		if not output.ok or output.status != "PENDING":
			break
	check(output.ok and output.status == "COMPLETE" and output.committed_time == 1800.0, "same authority and final committed time")
	check(scenario.ledger_balanced(), "finite resources conserved with probe mode")
	if probe != null:
		var data: Dictionary = probe.export()
		var bounded: bool = data.top.size() <= 32 and data.call_ring.size() <= 2048 and data.stats.size() <= 64 and data.level2_top.size() <= 32 and data.level2_stats.size() <= 5
		for key: String in data.stage_top:
			bounded = bounded and data.stage_top[key].size() <= 8
		check(bounded and data.drops.bucket == 0, "bounded records and fixed stage buckets")
		var correlated: bool = true
		for rows: Array in [data.top, data.level2_top]:
			for row: Dictionary in rows:
				correlated = correlated and row.call_id == row.call_span.call_id and row.used_work <= 7 and row.inclusive_usec <= row.call_span.api_actual_return_usec
		check(correlated, "child and primitive spans join to exact actual caller return")
		check(data.level2_top.size() == 30 if mode == "narrow" else data.level2_top.is_empty(), "selected six decisions each have five child stages")
	return {"public": {"physical": scenario.physical(), "knowledge": scenario.env.information._knowledge.duplicate(true),
		"messages": scenario.env.information._messages.duplicate(true), "decisions": scenario.env.decisions.snapshot(),
		"lod_work": scenario.env.lod.counters(), "kernel_work": scenario.env.state.counters.duplicate()},
		"raw_trace": scenario.trace.export(), "phase_counts": output.phase_work_counts, "calls": calls, "pending_peak": pending_peak}
