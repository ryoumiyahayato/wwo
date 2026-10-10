extends SceneTree
const Session = preload("res://experiments/war_resolver/interactive_observer/session.gd")
const Audit = preload("res://experiments/war_resolver/interactive_observer/audit.gd")
var rows: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	for label: String in ["headless_no_projection", "host_no_input", "host_input", "host_100_reads", "host_pages", "company_summary", "sleep_10000"]:
		for sample: int in range(6):
			measure(label, sample)
	print("INTERACTIVE_COSTS=" + JSON.stringify({"rows": rows, "warmups": 1, "measured_samples": 5,
		"diagnostic_calculations": "OFF", "timing_scope": "same process; kernel and projection separated; final audit excluded from look; serialized bytes are payload sizes not allocator RSS", "failures": failures}))
	print("Interactive cost checks: %d samples, %d failures" % [rows.size(), failures])
	quit(1 if failures else 0)

func ready(s: Session) -> void:
	while s.world.env.state.public_pending():
		s.request("resume", {"calls": 64})

func measure(label: String, sample: int) -> void:
	var s: Session = Session.new()
	var actor: String = "company" if label == "company_summary" else "squad"
	var started: int = Time.get_ticks_usec()
	var options: Dictionary = {"measure": true, "projection": label != "headless_no_projection", "sleeping_areas": 10000 if label == "sleep_10000" else 0}
	if not s.configure("S1", 71, actor, "bench", 31, options):
		failures += 1
		return
	var construction: int = Time.get_ticks_usec() - started
	var units: int = s.world.env.state.units.size()
	s.request("advance", {"seconds": 10.0})
	ready(s)
	var input: int = 0
	if label not in ["headless_no_projection", "host_no_input"]:
		started = Time.get_ticks_usec()
		s.request("intent", {"id": "move", "target": "blue_platoon" if actor == "company" else "node_unit_000", "intent": "advance", "node": "B", "path": ["AB"]})
		ready(s)
		input = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	s.request("auto", {"until": 1800.0, "step": 30.0})
	while s.mode == "AUTO" or s.world.env.state.public_pending():
		s.request("tick", {"calls": 64})
	var advance: int = Time.get_ticks_usec() - started
	var reads: int = 100 if label == "host_100_reads" or label == "sleep_10000" else (20 if label == "host_pages" else 1)
	var before_work: Dictionary = s.reader.work.duplicate()
	var before_lod: Dictionary = s.world.env.lod.work.duplicate()
	var before_state: Dictionary = s.world.env.state.counters.duplicate()
	var before_rng: Dictionary = s.world.env.state.random_state.duplicate()
	var before_info: int = s.world.env.information.work.knowledge_records_examined
	var before_size: Array = [s.receipts.size(), s.reader.timeline.size(), s.world.env.decisions._events.size()]
	started = Time.get_ticks_usec()
	for index: int in range(reads):
		s.request("look", {})
		if label == "host_pages":
			s.request("reports", {"before": 0})
			s.request("events", {"before": 0})
			s.request("receipts", {"before": 0})
	var read_usec: int = Time.get_ticks_usec() - started
	var delta: Dictionary = {}
	for key: String in before_work:
		delta[key] = s.reader.work[key] - before_work[key]
	var invariants: bool = before_lod == s.world.env.lod.work and before_state == s.world.env.state.counters and before_rng == s.world.env.state.random_state and before_size == [s.receipts.size(), s.reader.timeline.size(), s.world.env.decisions._events.size()]
	if not invariants:
		failures += 1
	var examined: int = s.world.env.information.work.knowledge_records_examined - before_info
	started = Time.get_ticks_usec()
	var audit: Dictionary = Audit.collect(s)
	var export_bytes: int = JSON.stringify(audit).to_utf8_buffer().size()
	var export_usec: int = Time.get_ticks_usec() - started
	if not audit.ledger_balanced:
		failures += 1
	var persistent: Dictionary = audit.persistent_host.duplicate()
	var clock: float = s.world.env.state.time
	var calls: int = s.calls
	audit.clear()
	s.dispose()
	rows.append({"case": label, "sample": sample, "warmup": sample == 0, "units": units, "construction_usec": construction,
		"input_including_due_work_usec": input, "reads": reads, "read_usec": read_usec, "work_delta": delta,
		"actual_information_records_examined": examined, "read_world_unchanged": invariants, "auto_interval_usec": advance,
		"bounded_calls": calls, "time": clock, "costs": s.costs.duplicate(), "export_copy_and_serialize_usec": export_usec,
		"export_bytes": export_bytes, "persistent_host": persistent})
