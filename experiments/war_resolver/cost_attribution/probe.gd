extends RefCounted
## Opt-in bounded scalar evidence. Never retain a world, unit, job or result.
const GLOBAL_CAP: int = 32
const STAGE_CAP: int = 8
const CALL_CAP: int = 2048
const BUCKET_CAP: int = 64
const DETAIL_STAGES: Array[String] = ["prepare:candidates", "apply:apply_units", "apply_start", "release_jobs", "due"]
var run_id: String = ""
var sample_id: String = ""
var level1_enabled: bool = true
var level2_enabled: bool = false
var level2_top: Array[Dictionary] = []
var level2_stats: Dictionary = {}
const SUB_STAGES: Array[String] = ["decision_context", "decision_copy_and_provider", "decision_validation", "decision_issue_and_callback", "decision_cycle_and_result"]
var stats: Dictionary = {}
var top: Array[Dictionary] = []
var stage_top: Dictionary = {}
var calls: Array[Dictionary] = []
var open_rows: Array[Dictionary] = []
var last_call: Dictionary = {}
var call_count: int = 0
var next_job: int = 0
var ring_dropped: int = 0
var calls_without_retained_primitive: int = 0
var global_not_retained: int = 0
var stage_not_retained: int = 0
var bucket_dropped: int = 0
var callback_usec: int = 0
var callback_count: int = 0
var finalizer_usec: int = 0
var api_cleanup_usec: int = 0
var call_id: int = 0
var primitive_id: int = 0
var job_id: int = 0
var scope_id: String = ""
var unit_id: String = ""
var event_id: String = ""
var event_kind: String = ""
var subphase: String = ""
var game_start: float = 0.0
var target_time: float = 0.0
var committed_time: float = 0.0
var quota: int = 0
var units_before: int = 0
var contacts_before: int = 0
var candidate_count: int = 0
var contact_work: int = 0
var write_work: int = 0
var live: int = 0
var route_items: int = 0
var copy_items: int = 0
var cleanup_items: int = 0
var carried_items: int = 0
var pending: int = 0
var context_observed: bool = false

func begin_call(requested: float, allowance: int, start_time: float) -> void:
	call_count += 1
	call_id = call_count
	target_time = requested
	quota = allowance
	game_start = start_time

func new_job_id() -> int:
	next_job += 1
	return next_job

func before(work: RefCounted, label: String) -> void:
	primitive_id = work.total_steps + 1
	context_observed = true
	committed_time = work.committed
	live = work.state.units.size()
	pending = work.state.events.size()
	units_before = int(work.state.counters.units_examined)
	contacts_before = int(work.state.counters.contacts_resolved)
	job_id = 0
	scope_id = ""
	unit_id = ""
	event_id = ""
	event_kind = ""
	subphase = label
	candidate_count = 0
	contact_work = 0
	write_work = 0
	route_items = 0
	copy_items = 0
	cleanup_items = 0
	carried_items = 0
	if work.job != null:
		job_id = work.job.cost_job_id
		scope_id = work.job.area_id
		carried_items = work.job.incoming_losses.size() + work.job.incoming_pressure.size()
		if work.job.i < work.job.ids.size():
			unit_id = work.job.ids[work.job.i]
		if label == "prepare:candidates":
			candidate_count = int(work.job.j < work.job.candidates.size())
		elif label == "apply:incoming_targets":
			contact_work = int(work.job.j < work.job.plan.contacts.size())
		elif label == "apply:apply_units" and not unit_id.is_empty():
			write_work = 1
			copy_items = work.state.units[unit_id].size()
			route_items = work.state.units[unit_id].get("spatial", {}).get("traversed", []).size()
		if label == "clear_delta" and work.cursor >= work.ids.size() and work.boundary >= work.target:
			cleanup_items = carried_items
		elif label == "scope_capacity" and work.cursor >= work.ids.size():
			cleanup_items = carried_items
		elif label == "apply_start" and work.scope_index < work.scopes.size():
			cleanup_items = carried_items
	if label == "release_jobs" and work.release_index < work.release_ids.size():
		scope_id = work.release_ids[work.release_index]
		job_id = work.jobs[scope_id].cost_job_id
		cleanup_items = int(work.release_plan_index < work.jobs[scope_id].ids.size())
		if cleanup_items == 0 and not work.state.contacts.has(scope_id) and not work.jobs[scope_id].contact_records.is_empty():
			cleanup_items = 1
		if work.release_plan_index < work.jobs[scope_id].ids.size():
			unit_id = work.jobs[scope_id].ids[work.release_plan_index]
	if label == "due" and work.state.next_event_time() <= work.boundary:
		job_id = 0
		scope_id = ""
		unit_id = ""
		event_id = str(work.state.events[0].id)
		event_kind = str(work.state.events[0].kind)
		if event_kind == "decision":
			var decision_id: String = str(work.state.events[0].payload.decision_id)
			scope_id = str(work.state.decision_port.get_ref()._events[decision_id].person_id)
		if work.state.information_port != null and int(work.state.events[0].get("phase", 0)) >= 5 and work.state.information_port.get_ref().has_due_report(work.boundary):
			event_id = "due_report_before_" + event_id
			event_kind = "report"
		subphase = "due:" + event_kind

func observe(label: String, elapsed: int, work: RefCounted) -> void:
	if not stats.has(label):
		if stats.size() >= BUCKET_CAP:
			bucket_dropped += 1
			return
		stats[label] = {"count": 0, "inclusive_usec": 0, "max_usec": 0, "histogram": [], "records_read": 0, "candidate_records": 0, "contacts": 0, "records_written": 0, "copy_top_level_items": 0, "route_items_carried_by_copies": 0, "cleanup_record_estimate": 0}
		stats[label].histogram.resize(25)
		stats[label].histogram.fill(0)
	var s: Dictionary = stats[label]
	s.count += 1
	s.inclusive_usec += elapsed
	s.max_usec = maxi(s.max_usec, elapsed)
	var bin_index: int = 0
	var ceiling: int = 1
	while elapsed > ceiling and bin_index < 24:
		ceiling *= 2
		bin_index += 1
	s.histogram[bin_index] += 1
	if not context_observed:
		return
	var reads: int = int(work.state.counters.units_examined) - units_before
	var contacts: int = int(work.state.counters.contacts_resolved) - contacts_before + contact_work
	s.records_read += reads
	s.candidate_records += candidate_count
	s.contacts += contacts
	s.records_written += write_work
	s.copy_top_level_items += copy_items
	s.route_items_carried_by_copies += route_items
	s.cleanup_record_estimate += cleanup_items
	var global_wanted: bool = top.size() < GLOBAL_CAP or elapsed > int(top[-1].inclusive_usec)
	var stage_wanted: bool = false
	if label in DETAIL_STAGES:
		if not stage_top.has(label):
			stage_top[label] = []
		stage_wanted = stage_top[label].size() < STAGE_CAP or elapsed > int(stage_top[label][-1].inclusive_usec)
	if not global_wanted:
		global_not_retained += 1
	if label in DETAIL_STAGES and not stage_wanted:
		stage_not_retained += 1
	if not global_wanted and not stage_wanted:
		return
	var row: Dictionary = {"run_id": run_id, "sample_id": sample_id, "call_id": call_id, "primitive_id": primitive_id,
		"parent_span_id": call_id, "job_id": job_id, "phase": label, "subphase": subphase, "scope_id": scope_id,
		"unit_id": unit_id, "event_id": event_id, "game_time_start": game_start, "boundary_time": work.boundary,
		"target_time": target_time, "committed_time_before": committed_time, "committed_time": work.committed,
		"quota": quota, "total_work_before_primitive": work.total_steps, "return_status": work.status,
		"inclusive_usec": elapsed, "live_representations": live, "candidate_records_examined": candidate_count,
		"actual_contacts_processed": contacts, "records_read": reads, "records_written": write_work,
		"copy_top_level_item_count": copy_items, "route_history_items": route_items,
		"carried_incoming_items": carried_items, "cleanup_release_record_estimate": cleanup_items, "pending_events": pending}
	open_rows.append(row)
	if global_wanted:
		_insert(top, row, GLOBAL_CAP)
	if stage_wanted:
		_insert(stage_top[label], row, STAGE_CAP)

func _insert(values: Array, row: Dictionary, limit: int) -> void:
	var index: int = 0
	while index < values.size() and int(values[index].inclusive_usec) >= int(row.inclusive_usec):
		index += 1
	values.insert(index, row)
	if values.size() > limit:
		values.pop_back()

func end_call(output: Dictionary, elapsed: int) -> void:
	if output.status == "COMPLETE":
		for label: String in stats:
			stats[label].frequency_total = int(output.phase_work_counts.get(label, 0))
			stats[label].sample_inclusive_usec = stats[label].inclusive_usec
			stats[label].estimated_inclusive_usec = float(stats[label].inclusive_usec) * float(stats[label].frequency_total) / float(stats[label].count)
	if open_rows.is_empty():
		calls_without_retained_primitive += 1
		return
	var row: Dictionary = {"call_id": call_id, "game_time_start": game_start, "target_time": target_time,
		"committed_time": output.committed_time, "quota": quota, "used_work": output.work_units,
		"return_status": output.status, "api_before_probe_finalize_usec": elapsed, "primitive_end_id": output.total_work_units}
	last_call = row
	if calls.size() < CALL_CAP:
		calls.append(row)
	else:
		calls[(call_count-1) % CALL_CAP] = row
		ring_dropped += 1
	# Complete the same-call relation before the next call; never retain output.
	for value: Dictionary in open_rows:
		_finish_row(value, row)
	open_rows.clear()

func _finish_row(value: Dictionary, row: Dictionary) -> void:
	value.used_work = row.used_work
	value.return_status = row.return_status
	value.call_span = row
	value.committed_time = row.committed_time

func outer_return(elapsed: int) -> void:
	if int(last_call.get("call_id", 0)) == call_id:
		last_call.api_actual_return_usec = elapsed

func subspan(stage: String, elapsed: int, event: String, person: String, items: int, history_records: int, at_time: float) -> void:
	if not stage in SUB_STAGES:
		return
	if not level2_stats.has(stage):
		level2_stats[stage] = {"count": 0, "inclusive_usec": 0, "max_usec": 0, "items": 0}
	level2_stats[stage].count += 1
	level2_stats[stage].inclusive_usec += elapsed
	level2_stats[stage].max_usec = maxi(elapsed, int(level2_stats[stage].max_usec))
	level2_stats[stage].items += items
	var row: Dictionary = {"run_id": run_id, "sample_id": sample_id, "call_id": call_id, "primitive_id": primitive_id,
		"parent_span_id": primitive_id, "job_id": 0, "phase": "due", "subphase": stage, "scope_id": person,
		"unit_id": "", "event_id": event, "game_time_start": game_start, "event_time": at_time,
		"target_time": target_time, "quota": quota, "inclusive_usec": elapsed,
		"received_claim_count": items, "decision_history_records": history_records}
	if level2_top.size() < GLOBAL_CAP or elapsed > int(level2_top[-1].inclusive_usec):
		_insert(level2_top, row, GLOBAL_CAP)
		open_rows.append(row)

func export() -> Dictionary:
	return {"schema": "WWO_STEP_COST_SCALAR_V1", "run_id": run_id, "sample_id": sample_id, "stats": stats,
		"level1_enabled": level1_enabled, "level2_enabled": level2_enabled, "level2_top": level2_top, "level2_stats": level2_stats,
		"top": top, "stage_top": stage_top, "call_ring": calls, "call_count": call_count, "job_count": next_job,
		"drops": {"call_ring": ring_dropped, "calls_without_retained_primitive": calls_without_retained_primitive, "global_not_retained": global_not_retained, "stage_not_retained": stage_not_retained, "bucket": bucket_dropped},
		"caps": {"global": GLOBAL_CAP, "per_stage": STAGE_CAP, "call_ring": CALL_CAP, "stage_buckets": BUCKET_CAP, "level2_global": GLOBAL_CAP, "level2_buckets": SUB_STAGES.size()},
		"callback_usec": callback_usec, "callback_event_count": callback_count, "resume_finalizer_usec": finalizer_usec, "api_cleanup_usec": api_cleanup_usec,
		"measurement": "frequency_total from original complete phase counters; all due/apply_units/apply_start/release_jobs/clear_delta/scope_capacity timed, first and each16th occurrence elsewhere; sample inclusive sum exact, estimated total = sample mean times original frequency and may have systematic sampling bias; top/max are observed subset; callback/finalizer/API cleanup disjoint; actual API span from caller; histogram median approximate powers-of-two; copy count top-level keys plus separate route items, not bytes or recursive count"}
