extends RefCounted
## Replaceable, single-thread transition service; no SceneTree dependency.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const SegmentWork = preload("res://experiments/war_resolver/continuous/segment_work.gd")
const DETAILED: String = "DETAILED"
const AGGREGATE: String = "AGGREGATE"
const INTERVALS: Dictionary = {DETAILED: 30.0, AGGREGATE: 120.0}
const SUPPRESSION_DECAY: float = 0.18
const SUPPRESSION_PER_ROUND: float = 0.12
const FATIGUE_PER_MINUTE: float = 0.004
const COHESION_PER_LOSS: float = 0.5
const SLEEP_EPSILON: float = 0.001


func resolve_until(state: State, target_game_time: float, resolution_policy: String = DETAILED, owner: RefCounted = null) -> Dictionary:
	if state.settlement_owner != null and state.settlement_owner != owner:
		return {"ok": false, "error": "Settlement belongs to the LOD coordinator"}
	if not INTERVALS.has(resolution_policy) or not is_finite(target_game_time) or target_game_time < state.time:
		return {"ok": false, "error": "Invalid policy or non-monotonic time"}
	var start: float = state.time
	var before: Dictionary = state.totals.duplicate()
	var counters_before: Dictionary = state.counters.duplicate()
	# Output scope is per call: previously active sleeping regions must not turn
	# summary creation into a growing scan of every region ever visited.
	state.touched_units.clear()
	state.touched_areas.clear()
	var changes: Dictionary = {}
	var area_changes: Dictionary = {}
	var output_events: Array[Dictionary] = []
	while true:
		_process_due(state, output_events, changes, area_changes)
		if state.time >= target_game_time:
			break
		if state.active_areas.is_empty():
			state.time = minf(target_game_time, state.next_event_time())
			continue
		var interval: float = float(INTERVALS[resolution_policy])
		# Anchoring accuracy boundaries to world time avoids caller-relative ticks.
		var boundary: float = (floorf(state.time / interval) + 1.0) * interval
		boundary = minf(boundary, minf(target_game_time, state.next_event_time()))
		var plans: Dictionary = {}
		for area_id: String in _resolution_scopes(state):
			plans[area_id] = _prepare_area(state, area_id)
			for unit_id: String in State.sorted_ids(plans[area_id]):
				var plan: Dictionary = plans[area_id][unit_id]
				var unit: Dictionary = state.examine_unit(unit_id)
				var mission: Dictionary = state.missions[unit.mission_id]
				if float(plan.rounds) > 0.0 and float(unit.ammunition) > 0.000001:
					var exhaustion: float = float(unit.ammunition) / float(plan.rounds) * 60.0
					if exhaustion > 0.000001:
						boundary = minf(boundary, state.time + exhaustion)
				if float(plan.get("fuel_rate", 0.0)) > 0.0:
					var fuel_eta: float = float(unit.fuel) / float(plan.fuel_rate) * 60.0
					if fuel_eta > 0.000001:
						boundary = minf(boundary, state.time + fuel_eta)
				if float(plan.speed) != 0.0:
					if unit.has("spatial"):
						boundary = minf(boundary, state.time + state.spatial_port.get_ref().movement_eta(unit, plan))
						continue
					var objective: float = float(mission.objective)
					if plan.posture == "withdraw" and mission.posture != "withdraw":
						objective = 0.0 if float(plan.speed) < 0.0 else float(state.areas[area_id].size_km)
					var eta: float = (objective - float(unit.position)) / float(plan.speed) * 60.0
					if eta > 0.000001:
						boundary = minf(boundary, state.time + eta)
		var minutes: float = (boundary - state.time) / 60.0
		state.time = boundary
		state.counters.segments += 1
		# Every plan reads the same pre-segment state; application cannot affect fire.
		var transfers: Array[Dictionary] = []
		for area_id: String in State.sorted_ids(plans):
			transfers.append_array(_apply_area(state, area_id, plans[area_id], minutes, output_events, changes))
		var control_areas: Dictionary = plans.duplicate()
		if state.spatial_port != null:
			for scope: String in plans:
				for cell: String in state.spatial_port.get_ref().scope_cells(scope):
					control_areas[cell] = true
		# Simultaneous arrivals cannot create transient faction-first control claims.
		for transfer: Dictionary in transfers:
			var unit: Dictionary = state.examine_unit(str(transfer.unit_id))
			state.area_units[unit.area_id].erase(unit.id)
			state.area_units[transfer.destination][unit.id] = true
			var source: String = str(unit.area_id)
			unit.area_id = transfer.destination
			unit.position = 0.0
			state.wake(transfer.destination)
			control_areas[transfer.destination] = true
			changes[unit.id] = unit.duplicate(true)
			output_events.append({"time": state.time, "kind": "area_transition", "unit_id": unit.id, "from": source, "to": transfer.destination})
		for area_id: String in State.sorted_ids(control_areas):
			_update_control(state, area_id, output_events, area_changes)
	var counter_delta: Dictionary = {}
	for key: String in state.counters:
		counter_delta[key] = int(state.counters[key]) - int(counters_before[key])
	var resource_delta: Dictionary = {}
	for key: String in state.totals:
		resource_delta[key] = float(state.totals[key]) - float(before[key])
	var mission_changes: Dictionary = {}
	var coordination_changes: Dictionary = {}
	for id: String in State.sorted_ids(changes):
		var mission_id: String = str(state.units[id].mission_id)
		mission_changes[mission_id] = state.missions[mission_id].duplicate(true)
		if state.coordination.has(id):
			coordination_changes[id] = state.coordination[id].duplicate(true)
	return {"ok": true, "state_delta": {"from_time": start, "to_time": state.time,
		"units": changes, "areas": area_changes, "missions": mission_changes,
		"coordination": coordination_changes, "resources": resource_delta},
		"events": output_events, "summary": summary(state, resolution_policy), "counters": counter_delta}


func _process_due(state: State, log: Array[Dictionary], changes: Dictionary, area_changes: Dictionary) -> void:
	while state.next_event_time() <= state.time:
		if state.information_port != null and int(state.events[0].get("phase", 0)) >= 5:
			state.information_port.get_ref().deliver_reports_through(state.time)
		var transition: Dictionary = {}
		if state.materialization_port != null and state.materialization_port.get_ref() != null:
			transition = state.materialization_port.get_ref().prepare_event(state.events[0])
			for id: String in transition.get("retired", []):
				changes.erase(id)
				state.touched_units.erase(id)
			for id: String in transition.get("changed", []):
				changes[id] = state.units[id].duplicate(true)
				state.touched_units[id] = true
		var event: Dictionary = state.pop_event()
		var payload: Dictionary = event.payload
		state.counters.events_processed += 1
		if event.kind in ["structure", "logistics", "communication", "decision", "spatial"]:
			log.append({"time": state.time, "kind": event.kind, "id": event.id, "result": transition.get("record", {})})
			continue
		if event.kind == "order":
			var unit: Dictionary = state.examine_unit(str(payload.unit_id))
			unit.mission_id = payload.mission_id
			state.wake(str(unit.area_id))
			changes[unit.id] = unit.duplicate(true)
			state.touched_units[unit.id] = true
		elif event.kind == "reinforcement":
			if state.identity_reserved(str(payload.unit.id)):
				log.append({"time": state.time, "kind": "rejected_reinforcement", "id": event.id})
				continue
			state.add_unit(payload.unit)
			state.wake(str(payload.unit.area_id))
			changes[payload.unit.id] = state.units[payload.unit.id].duplicate(true)
			state.touched_units[payload.unit.id] = true
			_update_control(state, str(payload.unit.area_id), log, area_changes)
		elif event.kind == "coordination_release":
			state.wake(str(state.examine_unit(str(payload.unit_id)).area_id))
		else:
			var area: Dictionary = state.areas[payload.area_id]
			for key: String in ["cover", "concealment", "visibility", "frontage", "movement_modifier"]:
				if payload.has(key):
					area[key] = clampf(float(payload[key]), 0.0, 1.0) if key in ["cover", "concealment", "visibility"] else maxf(0.0, float(payload[key]))
			state.wake(str(area.id))
			area_changes[area.id] = area.duplicate(true)
		log.append({"time": state.time, "kind": event.kind, "id": event.id})
	if state.information_port != null:
		state.information_port.get_ref().deliver_reports_through(state.time)


func _posture(state: State, unit: Dictionary) -> String:
	var mission: Dictionary = state.missions[unit.mission_id]
	if mission.status != "active":
		return "hold"
	var assignment: Dictionary = state.coordination.get(unit.id, {})
	for dependency: String in assignment.get("after", []):
		if state.missions[dependency].status != "complete":
			return "reserve"
	if state.time < float(assignment.get("release_time", 0.0)):
		return "reserve"
	var command: Dictionary = state.command_coordination.get(unit.id, {})
	if state.time < float(command.get("release_time", 0.0)):
		return "reserve"
	if state.tactical_intents.has(unit.id):
		return str(state.tactical_intents[unit.id].posture)
	if command.has("posture"):
		return str(command.posture)
	return str(assignment.get("role", mission.posture))


func _candidate_ids(_state: State, ids: Array[String], _unit: Dictionary) -> Array[String]:
	return ids

func _resolution_scopes(state: State) -> Array[String]:
	return State.sorted_ids(state.active_areas) if state.spatial_port == null else state.spatial_port.get_ref().resolution_scopes(state.active_areas)

func _combat_ids(state: State, area: String) -> Array[String]:
	return State.sorted_ids(state.area_units[area]) if state.spatial_port == null else state.spatial_port.get_ref().combat_ids(area)

func _terrain(state: State, unit: Dictionary) -> Dictionary:
	return state.areas[unit.area_id] if state.spatial_port == null else state.spatial_port.get_ref().terrain(unit)


func _contact_weight(state: State, id: String) -> float:
	var unit: Dictionary = state.units[id] if state.settlement_owner == null else state.examine_unit(id)
	return float(unit.get("contact_weight", unit.get("tactical_weight", 1.0)))


func _effective_epsilon(state: State, unit: Dictionary) -> float:
	# Real splits retain their original tactical measure: a tiny detachment must
	# not become untargetable merely because its identity has changed.
	if state.structure_port != null:
		return SLEEP_EPSILON * float(unit.get("contact_weight", unit.get("tactical_weight", 1.0)))
	return SLEEP_EPSILON


func _prepare_area(state: State, area_id: String) -> Dictionary:
	var job: RefCounted = SegmentWork.new()
	job.configure_prepare(self, state, area_id, _combat_ids(state, area_id))
	while not job.prepare_step():
		pass
	return job.plans


func _apply_area(state: State, area_id: String, plans: Dictionary, minutes: float,
		log: Array[Dictionary], changes: Dictionary) -> Array[Dictionary]:
	var job: RefCounted = SegmentWork.new()
	job.configure_apply(self, state, area_id, plans, minutes, log, changes)
	while not job.apply_step():
		pass
	return job.transfers


func _update_control(state: State, area_id: String, log: Array[Dictionary], area_changes: Dictionary) -> void:
	var present: Dictionary = {}
	for id: String in State.sorted_ids(state.area_units[area_id]):
		var unit: Dictionary = state.examine_unit(id)
		if float(unit.effective) > _effective_epsilon(state, unit):
			present[unit.side] = true
	var control: String = "contested" if present.size() > 1 else (str(present.keys()[0]) if present.size() == 1 else "")
	if control != state.areas[area_id].control:
		state.areas[area_id].control = control
		area_changes[area_id] = state.areas[area_id].duplicate(true)
		log.append({"time": state.time, "kind": "control_changed", "area_id": area_id, "control": control})


func _wake_dependents(state: State, mission_id: String) -> void:
	for id: String in State.sorted_ids(state.mission_dependents.get(mission_id, {})):
		state.wake(str(state.examine_unit(id).area_id))


func summary(state: State, policy: String) -> Dictionary:
	var unit_records: Dictionary = {}
	var mission_records: Dictionary = {}
	var control: Dictionary = {}
	for id: String in State.sorted_ids(state.touched_units):
		var unit: Dictionary = state.units[id]
		unit_records[id] = {"side": unit.side, "area_id": unit.area_id,
			"position": unit.position, "distance_moved": unit.distance_moved,
			"effective": unit.effective, "casualties": unit.casualties,
			"ammunition": unit.ammunition, "ammo_spent": unit.ammo_spent,
			"equipment": unit.equipment, "equipment_lost": unit.equipment_lost,
			"suppression": unit.suppression, "fatigue": unit.fatigue,
			"cohesion": unit.cohesion, "action": unit.action}
		mission_records[unit.mission_id] = state.missions[unit.mission_id].duplicate(true)
	for id: String in State.sorted_ids(state.touched_areas):
		control[id] = state.areas[id].control
	return {"version": State.VERSION, "time": state.time, "policy": policy,
		"scope": "units and areas examined or changed during the latest resolve call",
		"seed": state.seed, "totals": state.totals.duplicate(), "units": unit_records,
		"control": control, "missions": mission_records, "counters": state.counters.duplicate()}
