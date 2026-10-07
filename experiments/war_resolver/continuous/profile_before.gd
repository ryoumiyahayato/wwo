extends SceneTree
const F = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
class Probe:
	extends "res://experiments/war_resolver/aggregation/indexed_resolver.gd"
	var peak: Dictionary = {"prepare_usec": 0, "apply_usec": 0, "due_usec": 0}
	func _prepare_area(state: State, id: String) -> Dictionary:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = super._prepare_area(state, id)
		peak.prepare_usec = maxi(int(peak.prepare_usec), Time.get_ticks_usec()-start)
		return result
	func _apply_area(state: State, id: String, plans: Dictionary, minutes: float, log: Array[Dictionary], changes: Dictionary) -> Array[Dictionary]:
		var start: int = Time.get_ticks_usec()
		var result: Array[Dictionary] = super._apply_area(state, id, plans, minutes, log, changes)
		peak.apply_usec = maxi(int(peak.apply_usec), Time.get_ticks_usec()-start)
		return result
	func _process_due(state: State, log: Array[Dictionary], changes: Dictionary, areas: Dictionary) -> void:
		var start: int = Time.get_ticks_usec()
		super._process_due(state, log, changes, areas)
		peak.due_usec = maxi(int(peak.due_usec), Time.get_ticks_usec()-start)

func _initialize() -> void:
	var evidence: Array[Dictionary] = []
	for count: int in [100, 400]:
		for repeat: int in range(6):
			var start: int = Time.get_ticks_usec()
			var state: State = F.battle(count)
			var owner: Authority = Authority.new()
			owner.configure(state)
			var probe: Probe = Probe.new()
			owner._kernel = probe
			var built: int = Time.get_ticks_usec()
			var result: Dictionary = owner.advance(300.0)
			var advanced: int = Time.get_ticks_usec()
			var summary: Dictionary = owner.macro_summary()
			var queried: int = Time.get_ticks_usec()
			var encoded: String = JSON.stringify(summary)
			var finished: int = Time.get_ticks_usec()
			assert(result.ok and not encoded.is_empty())
			if repeat > 0:
				evidence.append({"case": "dense_%d" % count, "sample": repeat, "input_build_ms": (built-start)/1000.0, "advance_ms": (advanced-built)/1000.0,
					"query_ms": (queried-advanced)/1000.0, "serialize_ms": (finished-queried)/1000.0, "peak": probe.peak, "work": owner.counters()})
	var batch: State = F.battle(4)
	var batch_owner: Authority = Authority.new()
	batch_owner.configure(batch)
	var batch_probe: Probe = Probe.new()
	batch_owner._kernel = batch_probe
	for index: int in range(1000):
		assert(batch.schedule_event("same_%04d" % index, 10.0, "area_change", {"area_id": "field", "cover": 0.1}))
	assert(batch_owner.advance(30.0).ok)
	evidence.append({"case": "1000_same_time_before", "peak": batch_probe.peak, "events": batch.counters.events_processed})
	print("CONTINUOUS_BEFORE_JSON=" + JSON.stringify(evidence))
	print("Task9 peak baseline: %d checks, 0 failures" % evidence.size())
	quit(0)
