extends RefCounted
## One pending call over the original world clock, not another simulation clock.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Segment = preload("res://experiments/war_resolver/continuous/segment_work.gd")
const Sort = preload("res://experiments/war_resolver/continuous/sort_cursor.gd")
const Trace = preload("res://experiments/war_resolver/continuity/trace.gd")
const SCOPE_CAP: int = 1024
const EVENT_SCOPE_CAP: int = 64
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
	var used: int = 0
	var before: int = int(state.counters.units_examined)
	call_event_count = 0
	state.inside_kernel_work = true
	if OS.get_static_memory_usage() > 512 * 1024 * 1024 or state.events.size() > 100000:
		_block("STORAGE_OR_QUEUE_CAPACITY")
	while used < quota and status == "PENDING":
		var label: String = phase + (":" + str(job.phase) if job != null and phase in ["prepare", "apply"] else "")
		var time_start: int = Time.get_ticks_usec()
		state.time = boundary if phase not in ["select", "index_start", "index_records", "index_sort", "prepare", "eta"] else segment_start
		if phase == "due":
			state.time = boundary
		_step()
		var elapsed: int = Time.get_ticks_usec()-time_start
		if elapsed > max_primitive_usec:
			max_primitive_usec = elapsed
			max_primitive = label
		primitives[label] = int(primitives.get(label, 0)) + 1
		total_steps += 1
		used += 1
		# Only a bounded number of events can arise from one declared primitive.
		call_event_count += log.size()
		for event: Dictionary in log:
			if event.kind == "area_transition":
				changed_cells[event.from] = true
				changed_cells[event.to] = true
			if authority.physical_event_sink.is_valid():
				authority.physical_event_sink.call(event)
		log.clear()
	state.inside_kernel_work = false
	state.time = committed
	state.pending_committed_time = committed
	if status == "COMPLETE":
		state.settlement_pending = false
	return {"ok": status != "BLOCKED", "status": status, "error": blocker, "requested_time": target,
		"committed_time": committed, "pending_boundary": boundary if status != "COMPLETE" else -1.0,
		"work_units": used, "actual_unit_records_examined": int(state.counters.units_examined)-before,
		"wall_usec": Time.get_ticks_usec()-started, "max_primitive_usec": max_primitive_usec,
		"max_primitive": max_primitive, "max_native_id_snapshot": max_metadata_ids,
		"events": [], "diagnostic_events_produced": call_event_count, "total_work_units": total_steps, "commit_count": commit_count}

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
				fold_ids = State.sorted_ids(state.area_units[cell])
				if not _bounded_ids(fold_ids):
					return
				stocks = {}
				for key: String in authority.stock_keys():
					stocks[key] = 0.0
				scope_index = 0
				phase = "fold_units"
			else:
				committed = boundary
				state.pending_committed_time = committed
				commit_count += 1
				changes.clear()
				area_changes.clear()
				changed_cells.clear()
				if committed >= target:
					status = "COMPLETE"
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
				scopes = kernel._resolution_scopes(state)
				if scopes.size() > 128:
					_block("ACTIVE_SCOPE_COUNT_CAPACITY")
					return
				max_metadata_ids = maxi(max_metadata_ids, scopes.size())
				scope_index = 0
				jobs.clear()
				control_cells.clear()
				phase = "index_start"
		"index_start":
			if scope_index >= scopes.size():
				cursor = 0
				scope_index = 0
				phase = "eta"
			else:
				ids = kernel._combat_ids(state, scopes[scope_index])
				if not _bounded_ids(ids):
					return
				kernel._index._records.clear()
				cursor = 0
				phase = "index_records"
		"index_records":
			if cursor < ids.size():
				var unit: Dictionary = state.examine_unit(ids[cursor])
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
				ids = State.sorted_ids(state.area_units[control_ids[cursor]])
				if not _bounded_ids(ids):
					return
				present.clear()
				scope_index = 0
				phase = "control_units"
			else:
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

func _block(reason: String) -> void:
	status = "BLOCKED"
	blocker = reason

func _event_scope(event: Dictionary) -> int:
	var payload: Dictionary = event.payload
	if event.kind == "communication":
		var message: Dictionary = state.information_port.get_ref()._messages[payload.message_id]
		return authority._state.structure_port.get_ref()._leaves.get(message.recipient_ref, {}).size()
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
		var maximum: int = 1
		for target_ref: String in service._persons[person].definition.targets:
			maximum = maxi(maximum, state.structure_port.get_ref()._leaves.get(target_ref, {}).size())
		return maximum
	return 1
