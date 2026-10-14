extends RefCounted
## One pending call over the original world clock, not another simulation clock.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Segment = preload("res://experiments/war_resolver/continuous/segment_work.gd")
const Sort = preload("res://experiments/war_resolver/continuous/sort_cursor.gd")
const Trace = preload("res://experiments/war_resolver/continuity/trace.gd")
const SCOPE_CAP: int = 1024
const EVENT_SCOPE_CAP: int = 64
const METADATA_CAP: int = 4096
const CELL_SCOPE_CAP: int = 128
const ROUTE_HISTORY_CAP: int = 4096
const COST_FULL_CONTEXT: Array[String] = ["due", "apply:apply_units", "apply_start", "release_jobs", "clear_delta", "scope_capacity"]
var state: State
var kernel: RefCounted
var _authority: WeakRef
var authority: RefCounted:
	get: return _authority.get_ref()
var target: float
var policy: String
var committed: float
var boundary: float
var segment_start: float
var phase: String = "due"
var status: String = "PENDING"
var blocker: String = ""
var scopes: Array[String] = []
var scope_index: int = 0
var jobs: Dictionary = {}
var job: Segment
var ids: Array[String] = []
var cursor: int = 0
var sorter: Sort
var log: Array[Dictionary] = []
var call_event_count: int = 0
var changes: Dictionary = {}
var area_changes: Dictionary = {}
var control_cells: Dictionary = {}
var control_ids: Array[String] = []
var present: Dictionary = {}
var transfers: Array[Dictionary] = []
var changed_cells: Dictionary = {}
var fold_ids: Array[String] = []
var fold_cells: Array[String] = []
var stocks: Dictionary = {}
var total_steps: int = 0
var max_primitive_usec: int = 0
var max_primitive: String = ""
var max_metadata_ids: int = 0
var primitives: Dictionary = {}
var commit_count: int = 0
var ticket_trace: Trace = Trace.new()
var active_representation_count: int = 0
var release_ids: Array[String] = []
var release_index: int = 0
var release_plan_index: int = 0
var complete_after_release: bool = false

func configure(world: State, service: RefCounted, owner: RefCounted, requested: float, accuracy: String) -> void:
	state = world
	kernel = service
	_authority = weakref(owner)
	target = requested
	policy = accuracy
	committed = state.time
	boundary = committed
	state.touched_units.clear()
	state.touched_areas.clear()
	state.settlement_pending = true
	state.pending_committed_time = committed

func resume(quota: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var active_cost_probe: RefCounted = authority.cost_probe
	var used: int = 0
	var before: int = int(state.counters.units_examined)
	call_event_count = 0
	state.inside_kernel_work = true
	var pending_reports: int = 0 if state.information_port == null else state.information_port.get_ref()._report_heap.size()
	if OS.get_static_memory_usage() > 512 * 1024 * 1024 or state.events.size() + pending_reports > 100000:
		_block("STORAGE_OR_QUEUE_CAPACITY")
	while used < quota and status == "PENDING":
		if maxi(maxi(changes.size(), area_changes.size()), maxi(changed_cells.size(), control_cells.size())) > METADATA_CAP:
			_block("CHANGED_METADATA_CAPACITY")
			break
		var label: String = phase + (":" + str(job.phase) if job != null and phase in ["prepare", "apply"] else "")
		var cost_capture: bool = active_cost_probe != null and ((active_cost_probe.level1_enabled and (label in COST_FULL_CONTEXT or int(primitives.get(label, 0)) % 16 == 0)) or (active_cost_probe.level2_enabled and label == "due"))
		if active_cost_probe != null and active_cost_probe.level2_enabled and label == "due":
			active_cost_probe.primitive_id = total_steps + 1
		if cost_capture:
			active_cost_probe.before(self, label)
		var time_start: int = Time.get_ticks_usec()
		state.time = boundary if phase not in ["select", "scope_capacity", "index_start", "index_records", "index_sort", "prepare", "eta"] else segment_start
		if phase == "due":
			state.time = boundary
		_step()
		var elapsed: int = Time.get_ticks_usec()-time_start
		if cost_capture:
			active_cost_probe.observe(label, elapsed, self)
		if elapsed > max_primitive_usec:
			max_primitive_usec = elapsed
			max_primitive = label
		primitives[label] = int(primitives.get(label, 0)) + 1
		total_steps += 1
		used += 1
		# Only a bounded number of events can arise from one declared primitive.
		call_event_count += log.size()
		var cost_callback_started: int = Time.get_ticks_usec() if active_cost_probe != null and active_cost_probe.level1_enabled and not log.is_empty() else 0
		var cost_callback_count: int = log.size()
		for event: Dictionary in log:
			if event.kind == "area_transition":
				changed_cells[event.from] = true
				changed_cells[event.to] = true
			if authority.physical_event_sink.is_valid():
				authority.physical_event_sink.call(event)
		log.clear()
		if cost_callback_started != 0:
			active_cost_probe.callback_usec += Time.get_ticks_usec() - cost_callback_started
			active_cost_probe.callback_count += cost_callback_count
	var cost_finalizer_started: int = Time.get_ticks_usec() if active_cost_probe != null and active_cost_probe.level1_enabled else 0
	state.inside_kernel_work = false
	state.time = committed
	state.pending_committed_time = committed
	if status == "COMPLETE":
		state.settlement_pending = false
	var result: Dictionary = {"ok": status != "BLOCKED", "status": status, "error": blocker, "requested_time": target,
		"committed_time": committed, "pending_boundary": boundary if status != "COMPLETE" else -1.0,
		"work_units": used, "actual_unit_records_examined": int(state.counters.units_examined)-before,
		"wall_usec": Time.get_ticks_usec()-started, "max_primitive_usec": max_primitive_usec,
		"max_primitive": max_primitive, "max_native_id_snapshot": max_metadata_ids,
		"events": [], "diagnostic_events_produced": call_event_count, "total_work_units": total_steps, "commit_count": commit_count}
	if status == "COMPLETE":
		result.phase_work_counts = primitives.duplicate()
	if cost_finalizer_started != 0:
		active_cost_probe.finalizer_usec += Time.get_ticks_usec() - cost_finalizer_started
	return result

func _step() -> void:
	match phase:
		"due":
			if state.next_event_time() <= boundary:
				if state.information_port != null and int(state.events[0].get("phase", 0)) >= 5 and state.information_port.get_ref().has_due_report(boundary):
					state.information_port.get_ref().deliver_one_report(boundary)
				elif _event_scope(state.events[0]) > EVENT_SCOPE_CAP:
					_block("EVENT_SCOPE_CAPACITY")
				else:
					ticket_trace.append({"id": state.events[0].id, "time": boundary, "subject": "kernel", "kind": state.events[0].kind, "phase": int(state.events[0].get("phase", 0)), "cause_refs": []})
					kernel._process_due_one(state, log, changes, area_changes, false)
			elif state.information_port != null and state.information_port.get_ref().has_due_report(boundary):
				state.information_port.get_ref().deliver_one_report(boundary)
			else:
				ids = State.sorted_ids(changes)
				cursor = 0
				phase = "event_changed_units"
		"event_changed_units":
			if cursor < ids.size():
				changed_cells[state.units[ids[cursor]].area_id] = true
				cursor += 1
			else:
				ids = State.sorted_ids(area_changes)
				cursor = 0
				phase = "event_changed_areas"
		"event_changed_areas":
			if cursor < ids.size():
				changed_cells[ids[cursor]] = true
				cursor += 1
			else:
				fold_cells = State.sorted_ids(changed_cells)
				cursor = 0
				phase = "fold_start"
		"fold_start":
			if cursor < fold_cells.size():
				var cell: String = fold_cells[cursor]
				authority._observed_areas[cell] = true
				if state.area_units[cell].size() > SCOPE_CAP:
					_block("ACTIVE_SCOPE_CAPACITY")
					return
				fold_ids = State.sorted_ids(state.area_units[cell])
				if not _bounded_ids(fold_ids):
					return
				stocks = {}
				for key: String in authority.stock_keys():
					stocks[key] = 0.0
				scope_index = 0
				phase = "fold_units"
			else:
				ids = State.sorted_ids(changes)
				cursor = 0
				phase = "clear_delta"
		"clear_delta":
			if cursor < ids.size():
				changes.erase(ids[cursor])
				cursor += 1
			else:
				committed = boundary
				state.pending_committed_time = committed
				commit_count += 1
				changes.clear()
				area_changes.clear()
				changed_cells.clear()
				if committed >= target:
					_begin_release(true)
				else:
					phase = "select"
		"fold_units":
			if scope_index < fold_ids.size():
				var unit: Dictionary = state.examine_unit(fold_ids[scope_index])
				for key: String in authority.stock_keys():
					stocks[key] += float(unit.get(key, 0.0))
				scope_index += 1
			else:
				var cell: String = fold_cells[cursor]
				if authority.spatial.nodes.has(cell):
					authority.spatial.update_leaf(cell, stocks, str(state.areas[cell].control))
				cursor += 1
				phase = "fold_start"
		"select":
			segment_start = committed
			boundary = minf(target, state.next_event_time())
			if state.active_areas.is_empty():
				phase = "due"
			else:
				var interval: float = float(kernel.INTERVALS[policy])
				boundary = minf(boundary, (floorf(committed/interval)+1.0)*interval)
				if state.active_areas.size() > CELL_SCOPE_CAP:
					_block("ACTIVE_SCOPE_COUNT_CAPACITY")
					return
				ids = State.sorted_ids(state.active_areas)
				cursor = 0
				phase = "scope_capacity"
		"scope_capacity":
			if cursor < ids.size():
				if state.spatial_port != null:
					var space: RefCounted = state.spatial_port.get_ref()
					var scope: String = str(space._cell_scope.get(ids[cursor], ""))
					if not scope.is_empty() and space._scope_cells[scope].size() > CELL_SCOPE_CAP:
						_block("SPATIAL_SCOPE_CELL_CAPACITY")
						return
				cursor += 1
			else:
				scopes = kernel._resolution_scopes(state)
				if scopes.size() > 128:
					_block("ACTIVE_SCOPE_COUNT_CAPACITY")
					return
				max_metadata_ids = maxi(max_metadata_ids, scopes.size())
				scope_index = 0
				control_cells.clear()
				active_representation_count = 0
				_begin_release(false)
		"release_jobs":
			if release_index < release_ids.size():
				var old: Segment = jobs[release_ids[release_index]]
				if release_plan_index < old.ids.size():
					old.plans.erase(old.ids[release_plan_index])
					release_plan_index += 1
				elif not state.contacts.has(old.area_id) and not old.contact_records.is_empty():
					# Sleeping scopes no longer publish this array. Retire its last
					# reference one record at a time, including after the final commit.
					old.contact_records.pop_back()
				else:
					jobs.erase(release_ids[release_index])
					release_index += 1
					release_plan_index = 0
			else:
				if complete_after_release:
					status = "COMPLETE"
				else:
					phase = "index_start"
		"index_start":
			if scope_index >= scopes.size():
				cursor = 0
				scope_index = 0
				phase = "eta"
			else:
				var count: int = 0
				var cells: Array[String] = []
				if state.spatial_port == null:
					cells.append(scopes[scope_index])
				else:
					cells = state.spatial_port.get_ref().scope_cells(scopes[scope_index])
				for cell: String in cells:
					count += state.area_units[cell].size()
				active_representation_count += count
				if count > SCOPE_CAP or active_representation_count > METADATA_CAP:
					_block("ACTIVE_SCOPE_CAPACITY")
					return
				ids = kernel._combat_ids(state, scopes[scope_index])
				if not _bounded_ids(ids):
					return
				kernel._index._records.clear()
				cursor = 0
				phase = "index_records"
		"index_records":
			if cursor < ids.size():
				var unit: Dictionary = state.examine_unit(ids[cursor])
				if unit.get("spatial", {}).get("traversed", []).size() > ROUTE_HISTORY_CAP:
					_block("ROUTE_HISTORY_CAPACITY")
					return
				var x: float = float(unit.position) if state.spatial_port == null else float(state.spatial_port.get_ref().xy(unit)[0])
				kernel._index._records.append({"id": ids[cursor], "x": x})
				kernel.work.index_records_examined += 1
				kernel.work.formations_resolved += 1
				cursor += 1
			else:
				sorter = Sort.new()
				sorter.configure(kernel._index._records, true)
				phase = "index_sort"
		"index_sort":
			if sorter.step():
				kernel._index._records = sorter.sorted
				job = Segment.new()
				if authority.cost_probe != null:
					job.cost_job_id = authority.cost_probe.new_job_id()
				job.configure_prepare(kernel, state, scopes[scope_index], ids)
				job.bounded = true
				jobs[scopes[scope_index]] = job
				phase = "prepare"
		"prepare":
			if job.prepare_step():
				scope_index += 1
				phase = "index_start"
		"eta":
			if scope_index >= scopes.size():
				state.counters.segments += 1
				scope_index = 0
				phase = "apply_start"
			else:
				job = jobs[scopes[scope_index]]
				if cursor < job.ids.size():
					_eta(job.ids[cursor], job.plans[job.ids[cursor]], scopes[scope_index])
					cursor += 1
				else:
					scope_index += 1
					cursor = 0
		"apply_start":
			if scope_index >= scopes.size():
				control_ids = State.sorted_ids(control_cells)
				cursor = 0
				phase = "control_start"
			else:
				var cell: String = scopes[scope_index]
				var prepared: Dictionary = jobs[cell].plans
				job = Segment.new()
				if authority.cost_probe != null:
					job.cost_job_id = authority.cost_probe.new_job_id()
				job.configure_apply(kernel, state, cell, prepared, (boundary-segment_start)/60.0, log, changes)
				control_cells[cell] = true
				if state.spatial_port != null:
					for member: String in state.spatial_port.get_ref().scope_cells(cell):
						control_cells[member] = true
				phase = "apply"
		"apply":
			if job.apply_step():
				transfers.append_array(job.transfers)
				scope_index += 1
				phase = "apply_start"
		"control_start":
			# Legacy arrivals are separate from planning/application, as before.
			if not transfers.is_empty():
				var transfer: Dictionary = transfers.pop_front()
				var unit: Dictionary = state.examine_unit(str(transfer.unit_id))
				var source: String = str(unit.area_id)
				state.area_units[source].erase(unit.id)
				state.area_units[transfer.destination][unit.id] = true
				unit.area_id = transfer.destination
				unit.position = 0.0
				state.wake(transfer.destination)
				if not control_cells.has(transfer.destination):
					control_cells[transfer.destination] = true
					control_ids = State.sorted_ids(control_cells)
				log.append({"time": boundary, "kind": "area_transition", "unit_id": unit.id, "from": source, "to": transfer.destination})
				changed_cells[source] = true
				changed_cells[transfer.destination] = true
			elif cursor < control_ids.size():
				if state.area_units[control_ids[cursor]].size() > SCOPE_CAP:
					_block("ACTIVE_SCOPE_CAPACITY")
					return
				ids = State.sorted_ids(state.area_units[control_ids[cursor]])
				if not _bounded_ids(ids):
					return
				present.clear()
				scope_index = 0
				phase = "control_units"
			else:
				if state.gameplay_port != null:
					state.gameplay_port.get_ref().begin_commit()
					phase = "gameplay_commit"
				else:
					phase = "changed_units"
					ids = State.sorted_ids(changes)
					cursor = 0
		"gameplay_commit":
			if state.gameplay_port.get_ref().commit_step():
				phase = "changed_units"
				ids = State.sorted_ids(changes)
				cursor = 0
		"control_units":
			if scope_index < ids.size():
				var unit: Dictionary = state.examine_unit(ids[scope_index])
				if float(unit.effective) > kernel._effective_epsilon(state, unit):
					present[unit.side] = true
				scope_index += 1
			else:
				var cell: String = control_ids[cursor]
				var control: String = "contested" if present.size()>1 else (str(present.keys()[0]) if present.size()==1 else "")
				if control != state.areas[cell].control:
					state.areas[cell].control = control
					area_changes[cell] = state.areas[cell].duplicate(true)
					log.append({"time": boundary, "kind": "control_changed", "area_id": cell, "control": control})
				cursor += 1
				phase = "control_start"
		"changed_units":
			if cursor < ids.size():
				changed_cells[state.units[ids[cursor]].area_id] = true
				cursor += 1
			else:
				ids = State.sorted_ids(area_changes)
				cursor = 0
				phase = "changed_areas"
		"changed_areas":
			if cursor < ids.size():
				changed_cells[ids[cursor]] = true
				cursor += 1
			else:
				phase = "due"

func _eta(id: String, plan: Dictionary, cell: String) -> void:
	var unit: Dictionary = state.examine_unit(id)
	var mission: Dictionary = state.missions[unit.mission_id]
	var part_eta: float = float(plan.get("part_movement_seconds", INF))
	if part_eta > 0.000001:
		boundary = minf(boundary, segment_start + part_eta)
	var prepared_eta: float = float(plan.get("fire_exhaustion_seconds", INF))
	if prepared_eta > 0.000001:
		boundary = minf(boundary, segment_start + prepared_eta)
	if float(plan.rounds)>0.0 and float(unit.ammunition)>0.000001:
		var exhaustion: float = float(unit.ammunition)/float(plan.rounds)*60.0
		if exhaustion>0.000001:
			boundary = minf(boundary, segment_start+exhaustion)
	if float(plan.get("fuel_rate", 0.0))>0.0:
		var fuel_eta: float = float(unit.fuel)/float(plan.fuel_rate)*60.0
		if fuel_eta>0.000001:
			boundary = minf(boundary, segment_start+fuel_eta)
	if float(plan.speed)!=0.0:
		if unit.has("spatial"):
			boundary = minf(boundary, segment_start+state.spatial_port.get_ref().movement_eta(unit, plan))
		else:
			var objective: float = float(mission.objective)
			if plan.posture=="withdraw" and mission.posture!="withdraw":
				objective = 0.0 if float(plan.speed)<0.0 else float(state.areas[cell].size_km)
			var eta: float = (objective-float(unit.position))/float(plan.speed)*60.0
			if eta>0.000001:
				boundary = minf(boundary, segment_start+eta)

func _bounded_ids(values: Array[String]) -> bool:
	max_metadata_ids = maxi(max_metadata_ids, values.size())
	if values.size()>SCOPE_CAP:
		_block("ACTIVE_SCOPE_CAPACITY")
		return false
	return true

func _begin_release(final: bool) -> void:
	job = null
	sorter = null
	release_ids = State.sorted_ids(jobs)
	release_index = 0
	release_plan_index = 0
	complete_after_release = final
	phase = "release_jobs"

func _block(reason: String) -> void:
	status = "BLOCKED"
	blocker = reason

func _event_scope(event: Dictionary) -> int:
	var payload: Dictionary = event.payload
	if event.kind == "communication":
		var message: Dictionary = state.information_port.get_ref()._messages[payload.message_id]
		if message.command.get("kind", "") in ["air_intent", "naval_intent"]:
			return 1
		if message.command.get("kind", "") == "reserve_intent":
			return maxi(1, state.gameplay_port.get_ref().reserves.units(message.command.values).size())
		return maxi(1, state.structure_port.get_ref()._leaves.get(message.command.get("target", ""), {}).size())
	if event.kind == "structure":
		var service: RefCounted = state.structure_port.get_ref()
		var request: Dictionary = service._requests[payload.request_id]
		var values: Dictionary = request.values
		return service._leaves.get(values.get("target", values.get("source", "")), {}).size()
	if event.kind == "logistics":
		var service: RefCounted = state.logistics_port.get_ref()
		var value: Dictionary = service._deliveries[payload.delivery_id] if payload.has("delivery_id") else service._maintenance[payload.maintenance_id]
		var target_ref: String = str(value.get("recipient_ref", value.get("target", "")))
		return state.structure_port.get_ref()._leaves.get(target_ref, {}).size()
	if event.kind == "decision":
		var service: RefCounted = state.decision_port.get_ref()
		var person: String = str(service._events[payload.decision_id].person_id)
		var affected: int = 0
		for target_ref: String in service._persons[person].definition.targets:
			affected += state.structure_port.get_ref()._leaves.get(target_ref, {}).size()
		return maxi(1, affected)
	return 1
