extends SceneTree
## Finite warmup + five actual samples; no per-device frame-rate guarantee.
const F = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}
func _initialize() -> void:
	for size: int in [100, 400]:
		var runs: Array[Dictionary] = []
		for sample: int in range(6):
			var result: Dictionary = measure(size)
			if sample > 0:
				runs.append(result)
			checks += 1
			if result.status != "COMPLETE" or result.max_work_units > 256:
				failures += 1
		evidence[str(size)] = runs
	print("AFTER_PROFILE_JSON=" + JSON.stringify(evidence))
	print("Task9 profile: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func measure(size: int) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var state: F.State = F.battle(size)
	var owner: F.Authority = F.Authority.new()
	owner.configure(state)
	var built: int = Time.get_ticks_usec()
	var samples: Array[int] = []
	var last: Dictionary = {}
	var maximum: int = 0
	for call_index: int in range(1000000):
		var begin: int = Time.get_ticks_usec()
		last = owner.advance_bounded(60.0, 256)
		samples.append(Time.get_ticks_usec()-begin)
		maximum = maxi(maximum, int(last.work_units))
		if not last.ok or last.status != "PENDING":
			break
	var advanced: int = Time.get_ticks_usec()
	var counters: Dictionary = state.counters.duplicate()
	var summary: Dictionary = owner.spatial.view("region_50")
	var queried: int = Time.get_ticks_usec()
	var serialized: String = JSON.stringify({"summary": summary, "counters": counters, "last_call": last})
	var ended: int = Time.get_ticks_usec()
	samples.sort()
	return {"size": size, "game_seconds": 60, "status": last.status, "quota": 256, "calls": samples.size(), "max_work_units": maximum,
		"input_build_ms": (built-start)/1000.0, "advance_ms": (advanced-built)/1000.0, "query_ms": (queried-advanced)/1000.0,
		"serialize_ms": (ended-queried)/1000.0, "serialized_bytes": serialized.to_utf8_buffer().size(),
		"call_usec": {"p50": samples[int(samples.size()*0.50)], "p95": samples[mini(samples.size()-1, int(samples.size()*0.95))], "max": samples.back()},
		"largest_primitive_usec": last.max_primitive_usec, "largest_primitive": last.max_primitive, "largest_native_id_snapshot": last.max_native_id_snapshot,
		"kernel": state.counters.duplicate(), "work": owner.counters(), "static_memory_bytes": OS.get_static_memory_usage()}
