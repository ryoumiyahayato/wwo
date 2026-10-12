extends RefCounted
## Replaceable, single-thread transition service; no SceneTree dependency.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const DETAILED: String = "DETAILED"
const AGGREGATE: String = "AGGREGATE"
const INTERVALS: Dictionary = {DETAILED: 30.0, AGGREGATE: 120.0}
const SUPPRESSION_DECAY: float = 0.18
const SUPPRESSION_PER_ROUND: float = 0.12
const FATIGUE_PER_MINUTE: float = 0.004
const COHESION_PER_LOSS: float = 0.5
const SLEEP_EPSILON: float = 0.001


func resolve_until(state: State, target_game_time: float, resolution_policy: String = DETAILED) -> Dictionary:
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
		for area_id: String in State.sorted_ids(state.active_areas):
			plans[area_id] = _prepare_area(state, area_id)
			for unit_id: String in State.sorted_ids(plans[area_id]):
				var plan: Dictionary = plans[area_id][unit_id]
				var unit: Dictionary = state.examine_unit(unit_id)
				var mission: Dictionary = state.missions[unit.mission_id]
				if float(plan.rounds) > 0.0 and float(unit.ammunition) > 0.000001:
					var exhaustion: float = float(unit.ammunition) / float(plan.rounds) * 60.0
					if exhaustion > 0.000001:
						boundary = minf(boundary, state.time + exhaustion)
				if float(plan.speed) != 0.0:
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
		var event: Dictionary = state.pop_event()
		var payload: Dictionary = event.payload
		state.counters.events_processed += 1
		if event.kind == "order":
			var unit: Dictionary = state.examine_unit(str(payload.unit_id))
			unit.mission_id = payload.mission_id
			state.wake(str(unit.area_id))
			changes[unit.id] = unit.duplicate(true)
			state.touched_units[unit.id] = true
		elif event.kind == "reinforcement":
			if state.units.has(payload.unit.id):
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
	return str(assignment.get("role", mission.posture))


func _prepare_area(state: State, area_id: String) -> Dictionary:
	state.counters.areas_examined += 1
	state.touched_areas[area_id] = true
	var area: Dictionary = state.areas[area_id]
	var ids: Array[String] = State.sorted_ids(state.area_units[area_id])
	var plans: Dictionary = {}
	var side_frontage: Dictionary = {}
	for id: String in ids:
		var unit: Dictionary = state.examine_unit(id)
		var posture: String = _posture(state, unit)
		var commitment: float = minf(float(unit.effective), float(unit.equipment)) * float(unit.readiness)
		commitment *= float(unit.cohesion) * (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
		if posture in ["idle", "reserve", "withdraw"]:
			commitment = 0.0
		side_frontage[unit.side] = float(side_frontage.get(unit.side, 0.0)) + commitment
		var exposure: float = (1.15 if posture == "advance" else 0.65) * (1.0 - float(area.cover))
		plans[id] = {"posture": posture, "commitment": commitment, "exposure": exposure,
			"rounds": 0.0, "speed": 0.0, "contacts": [], "advance_inhibited": false}
	var contact_records: Array[Dictionary] = []
	for id: String in ids:
		var unit: Dictionary = state.examine_unit(id)
		var plan: Dictionary = plans[id]
		var targets: Array[String] = []
		for other_id: String in ids:
			var other: Dictionary = state.examine_unit(other_id)
			if other.side != unit.side and float(other.effective) > SLEEP_EPSILON and absf(float(unit.position) - float(other.position)) <= float(unit.weapon.range_km):
				targets.append(other_id)
		var detection: float = float(area.visibility) * (1.0 - float(area.concealment))
		if detection <= 0.0:
			targets.clear()
		plan.contacts = targets
		if targets.is_empty():
			continue
		var capacity: float = minf(1.0, float(area.frontage) / maxf(0.001, float(side_frontage[unit.side])))
		var rounds: float = float(plan.commitment) * capacity * float(unit.weapon.rounds_per_minute) * detection
		if plan.posture == "support":
			rounds *= 1.1
		# The same causal fire rates are used at both resolutions. No microscopic rounds.
		plan.rounds = rounds
		for other_id: String in targets:
			var target_plan: Dictionary = plans[other_id]
			var fire: float = rounds / float(targets.size())
			state.counters.contacts_resolved += 1
			contact_records.append({"source": id, "target": other_id, "detection": detection,
				"usable_fire_per_minute": fire, "exposure": target_plan.exposure})
	for id: String in ids:
		var unit: Dictionary = state.examine_unit(id)
		var mission: Dictionary = state.missions[unit.mission_id]
		var plan: Dictionary = plans[id]
		if float(unit.effective) <= SLEEP_EPSILON:
			continue
		if float(unit.cohesion) < float(mission.withdraw_cohesion):
			plan.posture = "withdraw"
		if plan.posture in ["advance", "withdraw"] and mission.status == "active":
			var inhibited: bool = plan.posture == "advance" and float(unit.suppression) >= float(mission.stop_suppression) and float(plan.exposure) > 0.3
			plan.advance_inhibited = inhibited
			if not inhibited:
				var direction: float = signf(float(mission.objective) - float(unit.position))
				if plan.posture == "withdraw" and mission.posture != "withdraw":
					direction = -float(mission.direction)
				plan.speed = direction * float(unit.mobility) * float(area.movement_modifier) * float(unit.readiness)
				plan.speed *= minf(1.0, float(area.frontage) / maxf(1.0, float(side_frontage[unit.side])))
				plan.speed *= (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
	state.contacts[area_id] = contact_records
	return plans


func _apply_area(state: State, area_id: String, plans: Dictionary, minutes: float,
		log: Array[Dictionary], changes: Dictionary) -> Array[Dictionary]:
	var area: Dictionary = state.areas[area_id]
	# Scale outgoing effects to ammunition actually available during this segment.
	var incoming_losses: Dictionary = {}
	var incoming_pressure: Dictionary = {}
	for id: String in State.sorted_ids(plans):
		incoming_losses[id] = 0.0
		incoming_pressure[id] = 0.0
	for id: String in State.sorted_ids(plans):
		var unit: Dictionary = state.examine_unit(id)
		var plan: Dictionary = plans[id]
		var wanted: float = float(plan.rounds) * minutes
		var spent: float = minf(float(unit.ammunition), wanted)
		var ratio: float = spent / wanted if wanted > 0.0 else 0.0
		for target_id: String in plan.contacts:
			var target_plan: Dictionary = plans[target_id]
			var variation: float = state.variation(id + ":" + target_id, int(floorf((state.time - minutes * 60.0) / float(INTERVALS["AGGREGATE"]))))
			var fire: float = float(plan.rounds) / float(plan.contacts.size()) * ratio
			incoming_losses[target_id] += fire * float(unit.weapon.lethality) * float(target_plan.exposure) * variation * minutes
			incoming_pressure[target_id] += fire * SUPPRESSION_PER_ROUND * float(target_plan.exposure) / maxf(1.0, float(state.examine_unit(target_id).effective))
		plan.spent = spent
	var transfers: Array[Dictionary] = []
	var remains_active: bool = false
	for id: String in State.sorted_ids(plans):
		var unit: Dictionary = state.examine_unit(id)
		var plan: Dictionary = plans[id]
		var mission: Dictionary = state.missions[unit.mission_id]
		var old_action: String = str(unit.action)
		if state.coordination.has(id):
			var old_status: String = str(state.coordination[id].get("status", ""))
			state.coordination[id].status = "waiting" if plan.posture == "reserve" else "assigned"
			if old_status != state.coordination[id].status:
				log.append({"time": state.time, "kind": "coordination_changed", "unit_id": id, "status": state.coordination[id].status})
		var loss: float = minf(float(unit.effective), float(incoming_losses[id]))
		var equipment_loss: float = minf(float(unit.equipment), loss)
		unit.effective = maxf(0.0, float(unit.effective) - loss)
		unit.casualties += loss
		unit.equipment -= equipment_loss
		unit.equipment_lost += equipment_loss
		unit.ammunition = maxf(0.0, float(unit.ammunition) - float(plan.spent))
		unit.ammo_spent += float(plan.spent)
		state.totals.casualties += loss
		state.totals.equipment_lost += equipment_loss
		state.totals.ammo_spent += float(plan.spent)
		var decay: float = exp(-SUPPRESSION_DECAY * minutes)
		unit.suppression = clampf(float(unit.suppression) * decay + float(incoming_pressure[id]) / SUPPRESSION_DECAY * (1.0 - decay), 0.0, 1.0)
		unit.cohesion = clampf(float(unit.cohesion) - loss / maxf(1.0, float(unit.personnel_total)) * COHESION_PER_LOSS, 0.0, 1.0)
		unit.action = str(plan.posture)
		if float(unit.effective) <= SLEEP_EPSILON:
			unit.action = "disabled"
		elif plan.posture == "advance" and float(plan.speed) == 0.0:
			unit.action = "stalled"
		var movement: float = float(plan.speed) * minutes if unit.action != "disabled" else 0.0
		var old_position: float = float(unit.position)
		unit.position = clampf(old_position + movement, 0.0, float(area.size_km))
		unit.distance_moved += absf(float(unit.position) - old_position)
		if movement != 0.0 or float(plan.spent) > 0.0:
			unit.fatigue = clampf(float(unit.fatigue) + FATIGUE_PER_MINUTE * minutes, 0.0, 1.0)
		# Mission completion is after all fire was planned, never a faction update advantage.
		if mission.status == "active" and plan.posture in ["advance", "withdraw"] and absf(float(unit.position) - float(mission.objective)) < 0.00001:
			unit.position = float(mission.objective)
			mission.status = "complete"
			_wake_dependents(state, str(mission.id))
			log.append({"time": state.time, "kind": "mission_complete", "unit_id": id, "mission_id": mission.id})
			if not str(mission.destination).is_empty() and (area.links as Dictionary).has(mission.destination):
				transfers.append({"unit_id": id, "destination": str(mission.destination)})
		elif mission.status == "active" and plan.posture == "withdraw" and mission.posture != "withdraw":
			if float(unit.position) <= 0.00001 or float(unit.position) >= float(area.size_km) - 0.00001:
				unit.position = 0.0 if float(unit.position) <= 0.00001 else float(area.size_km)
				mission.status = "withdrawn"
				_wake_dependents(state, str(mission.id))
				unit.action = "withdrawn"
				log.append({"time": state.time, "kind": "mission_withdrawn", "unit_id": id, "mission_id": mission.id})
		if loss > 0.0:
			log.append({"time": state.time, "kind": "losses", "unit_id": id, "personnel": loss, "equipment": equipment_loss})
		if old_action != unit.action:
			var reason: String = "mission"
			if unit.action == "stalled":
				reason = "suppression" if plan.advance_inhibited else "mobility"
			elif unit.action == "withdraw" and mission.posture != "withdraw":
				reason = "cohesion"
			log.append({"time": state.time, "kind": "action_changed", "unit_id": id,
				"action": unit.action, "reason": reason, "suppression": unit.suppression})
		changes[id] = unit.duplicate(true)
		state.touched_units[id] = true
		var next_posture: String = _posture(state, unit)
		var has_fire: bool = not (plan.contacts as Array).is_empty() and float(unit.ammunition) > 0.0 and float(unit.effective) > SLEEP_EPSILON
		# A completed dependency can release a reserve in this same simultaneous step.
		# Keep that area awake so its freshly eligible mission is evaluated next.
		var moving: bool = mission.status == "active" and next_posture in ["advance", "withdraw"] and float(unit.effective) > SLEEP_EPSILON and float(unit.mobility) > 0.0 and float(unit.readiness) > 0.0 and float(area.movement_modifier) > 0.0
		# Reserves sleep until an indexed dependency notification or release event.
		remains_active = remains_active or has_fire or moving or float(unit.suppression) > SLEEP_EPSILON
	for contact: Dictionary in state.contacts[area_id]:
		var target: Dictionary = state.examine_unit(str(contact.target))
		var source_plan: Dictionary = plans[contact.source]
		contact.time = state.time
		contact.usable_fire_per_minute = float(source_plan.spent) / minutes / float(source_plan.contacts.size())
		contact.suppression = target.suppression
		contact.movement_km_per_minute = plans[contact.target].speed
		contact.advance_inhibited = target.action == "stalled"
		contact.disengaging = target.action in ["withdraw", "withdrawn"]
	if not remains_active:
		state.active_areas.erase(area_id)
		state.contacts.erase(area_id)
	return transfers


func _update_control(state: State, area_id: String, log: Array[Dictionary], area_changes: Dictionary) -> void:
	var present: Dictionary = {}
	for id: String in State.sorted_ids(state.area_units[area_id]):
		var unit: Dictionary = state.examine_unit(id)
		if float(unit.effective) > SLEEP_EPSILON:
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
