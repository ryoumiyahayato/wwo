extends SceneTree
## Frozen M3 target: admitted inputs, not scenario-assigned outcomes.
const Scenario = preload("res://experiments/war_resolver/continuity/scenario.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)
func _initialize() -> void:
	var scenario: Scenario = Scenario.new()
	check(scenario.configure(71, {"long_run": true}), "long synthetic admission")
	check(scenario.env.lod.has_leaf("bg_000_0") and scenario.env.lod.has_leaf("bg_099_3"), "400-leaf synthetic factory is present")
	if failures == 0:
		_long_run(scenario, 71)
		var second: Scenario = Scenario.new()
		check(second.configure(109, {"long_run": true}), "second fixed seed admission")
		_long_run(second, 109)
	print("LONG_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task9 long: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _long_run(scenario: Scenario, seed_value: int) -> void:
	var initial: Dictionary = storage(scenario)
	check(initial.underlying_leaves == 400 and scenario.env.state.areas.size() == 100, "100 cells and exactly 400 unique leaf identities")
	check(scenario.env.state.active_areas.size() >= 10 and scenario.env.state.active_areas.size() <= 20, "initial active local envelope is 10..20 cells")
	check(scenario.env.space._loaded.size() == 2 and scenario.env.state.units.size() < 220, "two geometric focus cells with most leaves aggregated")
	check(scenario.env.background.coalescing.rejected.size() == 1 and scenario.env.background.coalescing.rejected[0].result.error == "incompatible_cohort", "heterogeneous pair explicitly remains detailed")
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = scenario.advance(86400.0)
	var normal_ms: float = (Time.get_ticks_usec()-started)/1000.0
	check(result.ok and scenario.env.state.time == 86400.0 and scenario.ledger_balanced(), "normal reference actually completes 24h with finite conserved stock")
	check(scenario.env.state.active_areas.size() >= 10 and scenario.env.state.active_areas.size() <= 20, "24h retains 10..20 active cells, not an idle-world shortcut")
	check(scenario.env.decisions.work.decision_events_processed >= 274 and scenario.env.logistics.work.deliveries_processed >= 4 and scenario.env.structure.history.size() >= 10, "long run continues original decisions, reports, deliveries and structure")
	var physical: Dictionary = scenario.physical()
	var knowledge: Dictionary = scenario.env.information._knowledge.duplicate(true)
	var messages: Dictionary = scenario.env.information._messages.duplicate(true)
	var decisions: Dictionary = scenario.env.decisions.snapshot()
	var comparisons: Array[Dictionary] = []
	for quota: int in [1, 7, 31]:
		var bounded: Scenario = Scenario.new()
		check(bounded.configure(seed_value, {"long_run": true}), "quota long admission")
		var calls: int = 0
		var measured: Dictionary = {}
		var maximum: int = 0
		started = Time.get_ticks_usec()
		while calls < 10000000:
			measured = bounded.env.lod.advance_bounded(86400.0, quota)
			maximum = maxi(maximum, int(measured.work_units))
			calls += 1
			if not measured.ok or measured.status != "PENDING":
				break
		check(measured.ok and measured.status == "COMPLETE" and bounded.env.state.time == 86400.0, "small quota actually completes 24h")
		check(maximum <= quota and physical == bounded.physical(), "24h quota preserves exact physical results")
		check(knowledge == bounded.env.information._knowledge and messages == bounded.env.information._messages and decisions == bounded.env.decisions.snapshot(), "24h quota preserves information, input, delivery and decision times")
		check(bounded.ledger_balanced() and storage(bounded).underlying_leaves == 400, "24h no resource duplication or representation overlap")
		var after: Dictionary = storage(bounded)
		check(after.diagnostic_retained <= 4096 and after.pending == 0 and after.static_memory_bytes <= 512*1024*1024, "bounded diagnostics, no backlog and registered capacity respected")
		comparisons.append({"quota": quota, "calls": calls, "wall_ms": (Time.get_ticks_usec()-started)/1000.0, "last_call": measured, "storage": after})
		print("LONG_PROGRESS seed=%d quota=%d calls=%d status=%s" % [seed_value, quota, calls, measured.status])
	evidence[str(seed_value)] = {"normal_ms": normal_ms, "physical_sha256": JSON.stringify(physical).sha256_text(), "initial_storage": initial, "final_storage": storage(scenario), "coalescing": scenario.env.background.coalescing, "comparisons": comparisons}

static func storage(scenario: Scenario) -> Dictionary:
	var env: Dictionary = scenario.env
	var leaves: Dictionary = {}
	var overlap: bool = false
	for id: String in env.state.units:
		if not env.state.units[id].has("contact_weight"):
			leaves[id] = true
	for id: String in env.lod._owners:
		overlap = overlap or leaves.has(id)
		leaves[id] = true
	var knowledge_count: int = 0
	for person: String in env.information._knowledge:
		knowledge_count += env.information._knowledge[person].size()
	return {"underlying_leaves": leaves.size() if not overlap else -1, "live_representations": env.state.units.size(), "active_cells": env.state.active_areas.size(), "geometry_focus_cells": env.space._loaded.size(),
		"cohorts": env.lod._groups.size(), "pending": env.state.events.size() + env.information._report_heap.size(),
		"event_identity_records": env.state.event_ids.size(), "information_identity_records": env.information._entry_ids.size(),
		"observations": env.information._observations.size(), "messages": env.information._messages.size(), "knowledge_claims": knowledge_count,
		"decision_history": env.decisions._events.size(), "structure_history": env.structure.history.size(), "logistics_identity_records": env.logistics._used.size(),
		"diagnostic_retained": scenario.trace.page().retained, "diagnostic_total": scenario.trace.total,
		"static_memory_bytes": OS.get_static_memory_usage()}
