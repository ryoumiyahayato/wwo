extends RefCounted
## The inherited segment equations, executed as resumable deterministic primitives.
const State = preload("res://experiments/war_resolver/battle_state.gd")
var kernel: RefCounted
var state: State
var area_id: String
var area: Dictionary
var ids: Array[String] = []
var plans: Dictionary = {}
var side_frontage: Dictionary = {}
var contact_records: Array[Dictionary] = []
var incoming_losses: Dictionary = {}
var incoming_pressure: Dictionary = {}
var transfers: Array[Dictionary] = []
var remains_active: bool = false
var minutes: float = 0.0
var log: Array[Dictionary] = []
var changes: Dictionary = {}
var phase: String = "units"
var i: int = 0
var j: int = 0
var unit: Dictionary = {}
var plan: Dictionary = {}
var targets: Array[String] = []
var detected: Dictionary = {}
var candidates: Array[String] = []
var detection: float = 0.0
var target_weight: float = 0.0
var rounds: float = 0.0
var spent: float = 0.0
var ratio: float = 0.0
var bounded: bool = false
var candidate_cursor: RefCounted = null
var candidate_probes: int = 0
var cost_job_id: int = 0
var body_targets: Dictionary = {}
var body_ids: Array[String] = []

func configure_prepare(service: RefCounted, world: State, cell: String, selected: Array[String]) -> void:
	kernel = service
	state = world
	area_id = cell
	area = state.areas[cell]
	ids = selected
	if world.gameplay_port != null and world.spatial_port != null:
		body_targets = world.gameplay_port.get_ref().participants.detached_targets(cell)
		body_targets.merge(world.gameplay_port.get_ref().tactics.part_targets(cell))
	state.counters.areas_examined += 1
	state.touched_areas[area_id] = true

func prepare_step() -> bool:
	match phase:
		"units":
			if i < ids.size():
				_prepare_unit(ids[i])
				i += 1
			else:
				i = 0
				phase = "source"
		"source":
			if i >= ids.size():
				i = 0
				phase = "finish"
			else:
				unit = state.examine_unit(ids[i])
				area = kernel._terrain(state, unit)
				plan = plans[ids[i]]
				targets = []
				detected = {}
				if bounded:
					candidate_cursor = kernel.begin_candidate_cursor(state, ids, unit)
					candidate_probes = int(kernel._index.probes)
				else:
					candidates = kernel._candidate_ids(state, ids, unit)
				j = 0
				phase = "candidate_query" if bounded else "candidates"
		"candidate_query":
			if candidate_cursor.step():
				candidates = candidate_cursor.result
				kernel.work.range_probes += int(kernel._index.probes) - candidate_probes
				kernel.work.candidate_contacts_examined += candidates.size()
				phase = "candidates"
		"candidates":
			if j < candidates.size():
				_candidate(candidates[j])
				j += 1
			else:
				for body_id: String in State.sorted_ids(body_targets):
					var body: Dictionary = body_targets[body_id]
					var factor: float = state.spatial_port.get_ref().detection_at(unit, body)
					if body.side != unit.side and factor > 0.0:
						targets.append(body_id)
						detected[body_id] = factor
				detection = float(area.visibility) * (1.0 - float(area.concealment))
				if detection <= 0.0 and state.spatial_port == null:
					targets.clear()
				plan.contacts = targets
				target_weight = 0.0
				j = 0
				phase = "weights"
		"weights":
			if j < targets.size():
				target_weight += _weight(targets[j])
				j += 1
			else:
				plan.target_weight = target_weight
				if targets.is_empty() and plans[unit.id].get("weapon_components", []).is_empty() and (state.gameplay_port == null or not state.gameplay_port.get_ref().tactics.fire_orders.has(unit.id)):
					i += 1
					phase = "source"
				elif state.spatial_port != null:
					detection = 0.0
					j = 0
					phase = "detection"
				else:
					phase = "rounds"
		"detection":
			if j < targets.size():
				detection += float(detected[targets[j]]) * _weight(targets[j]) / target_weight
				j += 1
			else:
				plan.contact_factors = {}
				j = 0
				phase = "factors"
		"factors":
			if j < targets.size():
				plan.contact_factors[targets[j]] = float(detected[targets[j]]) / detection
				j += 1
			else:
				phase = "rounds"
		"rounds":
			var capacity: float = minf(1.0, float(area.frontage) / maxf(0.001, float(side_frontage[unit.side])))
			rounds = float(plan.commitment) * capacity * float(unit.weapon.rounds_per_minute) * detection
			if plan.posture == "support":
				rounds *= 1.1
			plan.rounds = rounds
			if state.gameplay_port != null:
				plan.tactical_frontage = float(side_frontage[unit.side])
				var rates: Dictionary = {}
				for target: String in targets:
					rates[target] = rounds / maxf(0.000001, target_weight) * _weight(target) * float(plan.get("contact_factors", {}).get(target, 1.0))
				state.gameplay_port.get_ref().tactics.build_fire(unit, plan, targets, detected, rates)
			j = 0
			phase = "fire"
		"fire":
			if j < targets.size():
				var other_id: String = targets[j]
				var target_plan: Dictionary = body_targets[other_id] if body_targets.has(other_id) else plans[other_id]
				var fire: float = rounds / maxf(0.000001, target_weight) * _weight(other_id) * float(plan.get("contact_factors", {}).get(other_id, 1.0))
				state.counters.contacts_resolved += 1
				contact_records.append({"source": ids[i], "target": other_id, "target_unit": str(target_plan.get("unit_ref", state.gameplay_port.get_ref().participants._units.get(target_plan.get("actor_ref", ""), other_id))) if state.gameplay_port != null else other_id, "detection": detection, "usable_fire_per_minute": fire, "exposure": target_plan.exposure})
				j += 1
			else:
				i += 1
				phase = "source"
		"finish":
			if i < ids.size():
				_finish_plan(ids[i])
				i += 1
			else:
				if bounded and not state.contacts.get(area_id, []).is_empty():
					phase = "release_old_contacts"
				else:
					state.contacts[area_id] = contact_records
					phase = "prepared"
		"release_old_contacts":
			# Retiring a dense old diagnostic array is also real work, one record
			# per step. Public ports remain PENDING while this internal array changes.
			if not state.contacts[area_id].is_empty():
				state.contacts[area_id].pop_back()
			else:
				state.contacts[area_id] = contact_records
				phase = "prepared"
	return phase == "prepared"

func _candidate(other_id: String) -> void:
	var other: Dictionary = state.examine_unit(other_id)
	if state.gameplay_port != null and state.gameplay_port.get_ref().tactics.manoeuvre_active(other_id):
		return # Its parts and detached bodies are the only target positions.
	var allowed: bool = absf(float(unit.position) - float(other.position)) <= float(unit.weapon.range_km) if state.spatial_port == null else state.spatial_port.get_ref().detection(unit, other) > 0.0
	var living_body: bool = state.gameplay_port != null and state.gameplay_port.get_ref().participants.living_exposure(other)
	if plans.get(other_id, {}).has("personal_ledger") and float(plans[other_id].personal_ledger.exposure_capacity) <= 0.000001:
		return
	if other.side != unit.side and (float(other.effective) > kernel._effective_epsilon(state, other) or living_body) and allowed:
		targets.append(other_id)
		if state.spatial_port != null:
			detected[other_id] = state.spatial_port.get_ref().detection(unit, other)

func _prepare_unit(id: String) -> void:
	var unit: Dictionary = state.examine_unit(id)
	if state.gameplay_port != null:
		state.gameplay_port.get_ref().note_unit(id)
	area = kernel._terrain(state, unit)
	var posture: String = kernel._posture(state, unit)
	if state.gameplay_port != null and state.gameplay_port.get_ref().tactics.manoeuvre_active(id):
		posture = "hold"
	var commitment: float = minf(float(unit.effective), float(unit.get("serviceable_equipment", unit.equipment))) * float(unit.readiness)
	commitment *= float(unit.cohesion) * (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
	if posture in ["idle", "reserve", "withdraw"]:
		commitment = 0.0
	var exposure: float = (1.15 if posture == "advance" else 0.65) * (1.0 - float(area.cover))
	plans[id] = {"posture": posture, "commitment": commitment, "exposure": exposure,
		"rounds": 0.0, "speed": 0.0, "contacts": [], "advance_inhibited": false, "body_targets": body_targets, "segment_units": ids}
	if state.gameplay_port != null:
		state.gameplay_port.get_ref().participants.prepare(unit, plans[id])
		state.gameplay_port.get_ref().land.prepare(unit, plans[id])
		state.gameplay_port.get_ref().tactics.prepare(unit, plans[id])
	side_frontage[unit.side] = float(side_frontage.get(unit.side, 0.0)) + float(plans[id].get("part_frontage", plans[id].commitment))

func _finish_plan(id: String) -> void:
	var unit: Dictionary = state.examine_unit(id)
	area = kernel._terrain(state, unit)
	var mission: Dictionary = state.missions[unit.mission_id]
	var plan: Dictionary = plans[id]
	if float(unit.effective) <= kernel._effective_epsilon(state, unit):
		return
	if float(unit.cohesion) < float(mission.withdraw_cohesion) and (not mission.has("goal_v1") and not mission.get("summary_goal_policy", false) or mission.status == "active"):
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
	if unit.has("spatial"):
		plan.side_frontage = float(side_frontage[unit.side])
		state.spatial_port.get_ref().prepare_movement(unit, plan)
	if state.gameplay_port != null:
		state.gameplay_port.get_ref().participants.constrain_movement(plan)
		state.gameplay_port.get_ref().land.constrain(unit, plan)
		if plan.get("gun_deployed", false):
			plan.speed = 0.0
		state.gameplay_port.get_ref().tactics.constrain_manoeuvre(unit, plan)
	if unit.has("supply_capability"):
		state.logistics_port.get_ref().prepare_activity(unit, plan)
	plan.tactical_frontage = float(side_frontage[unit.side])

func configure_apply(service: RefCounted, world: State, cell: String, prepared: Dictionary, duration: float, output_log: Array[Dictionary], output_changes: Dictionary) -> void:
	kernel = service
	state = world
	area_id = cell
	area = state.areas[cell]
	plans = prepared
	ids = State.sorted_ids(plans)
	body_targets = plans[ids[0]].get("body_targets", {}) if not ids.is_empty() else {}
	body_ids = State.sorted_ids(body_targets)
	minutes = duration
	log = output_log
	changes = output_changes
	phase = "incoming_init"
	i = 0

func apply_step() -> bool:
	match phase:
		"incoming_init":
			if i < ids.size():
				incoming_losses[ids[i]] = 0.0
				incoming_pressure[ids[i]] = 0.0
				i += 1
			else:
				i = 0
				phase = "incoming_source"
		"incoming_source":
			if i >= ids.size():
				i = 0
				phase = "apply_units"
			else:
				unit = state.examine_unit(ids[i])
				plan = plans[ids[i]]
				var wanted: float = float(plan.rounds) * minutes
				spent = minf(float(unit.ammunition), wanted)
				if plan.has("fire_components"):
					spent = state.gameplay_port.get_ref().tactics.spend(unit, plan, minutes)
				ratio = spent / wanted if wanted > 0.0 else 0.0
				j = 0
				phase = "incoming_targets"
		"incoming_targets":
			if j < plan.contacts.size():
				_incoming(str(plan.contacts[j]))
				j += 1
			else:
				plan.spent = spent
				i += 1
				phase = "incoming_source"
		"apply_units":
			if i < ids.size():
				_apply_unit(ids[i])
				i += 1
			else:
				i = 0
				phase = "apply_part_motion"
		"apply_part_motion":
			if i < ids.size():
				if state.gameplay_port != null:
					state.gameplay_port.get_ref().tactics.apply_part_movement(state.units[ids[i]], plans[ids[i]], minutes, log)
				i += 1
			else:
				i = 0
				phase = "apply_bodies"
		"apply_bodies":
			if i < body_ids.size():
				var body: Dictionary = body_targets[body_ids[i]]
				if body.get("damage_owner", "") == "PART":
					state.gameplay_port.get_ref().tactics.apply_part_damage(str(body.unit_ref), str(body.part_ref), float(body.incoming), float(body.incoming_pressure), minutes, "part_segment_%.9f_%s" % [state.time, body_ids[i]])
					changes[body.unit_ref] = state.units[body.unit_ref].duplicate(true)
					i += 1
					return false
				var members: RefCounted = state.gameplay_port.get_ref().participants
				var member: Dictionary = members._member(str(body.actor_ref))
				var decay: float = exp(-kernel.SUPPRESSION_DECAY * minutes)
				var prior: float = float(member.get("local_suppression", 0.0)) * exp(-kernel.SUPPRESSION_DECAY * maxf(0.0, state.time - minutes * 60.0 - float(member.get("pressure_at", state.time - minutes * 60.0))) / 60.0)
				member.local_suppression = clampf(prior * decay + float(body.get("incoming_pressure", 0.0)) / kernel.SUPPRESSION_DECAY * (1.0 - decay), 0.0, 1.0)
				member.pressure_at = state.time
				if member.state in ["LOCAL_MOVING", "LOCAL_ENTERING"] and float(member.local_suppression) >= float(state.missions[state.units[body.unit_ref].mission_id].stop_suppression):
					members.interrupt_action(str(body.actor_ref), "actual_local_fire_pressure")
				if float(body.incoming) > 0.0:
					var result: Dictionary = state.gameplay_port.get_ref().participants.external_damage(str(body.actor_ref), float(body.incoming), "body_segment_%.9f_%s" % [state.time, body_ids[i]], "shared_incoming_fire")
					for id: String in result.changed:
						changes[id] = state.units[id].duplicate(true)
						state.touched_units[id] = true
				i += 1
			else:
				i = 0
				phase = "part_feedback"
		"part_feedback":
			if i < ids.size():
				if state.gameplay_port != null and plans[ids[i]].has("manoeuvre_ref"):
					state.gameplay_port.get_ref().tactics.after_manoeuvre_movement(state.units[ids[i]])
					changes[ids[i]] = state.units[ids[i]].duplicate(true)
				i += 1
			else:
				i = 0
				phase = "contact_diagnostics"
		"contact_diagnostics":
			if i < state.contacts[area_id].size():
				_contact_diagnostic(state.contacts[area_id][i])
				i += 1
			else:
				_finish_activity()
				phase = "applied"
	return phase == "applied"

func _incoming(target_id: String) -> void:
	var id: String = ids[i]
	var target_plan: Dictionary = body_targets[target_id] if body_targets.has(target_id) else plans[target_id]
	var variation: float = state.variation(id + ":" + target_id, int(floorf((state.time - minutes * 60.0) / float(kernel.INTERVALS["AGGREGATE"]))))
	var fire: float = float(plan.rounds) / maxf(0.000001, float(plan.target_weight)) * _weight(target_id) * ratio * float(plan.get("contact_factors", {}).get(target_id, 1.0))
	var lethal: float = fire * float(unit.weapon.lethality) * minutes
	var pressure: float = fire * float((unit.get("supply_capability", {}) as Dictionary).get("suppression_per_round", kernel.SUPPRESSION_PER_ROUND))
	if plan.has("fire_doses"):
		var dose: Dictionary = plan.fire_doses.get(target_id, {})
		fire = float(dose.get("rounds", 0.0)) / maxf(0.000001, minutes)
		lethal = float(dose.get("lethal", 0.0))
		pressure = float(dose.get("pressure", 0.0)) / maxf(0.000001, minutes)
	if body_targets.has(target_id):
		target_plan.incoming += lethal * float(target_plan.exposure) * variation
		target_plan.incoming_pressure += pressure * float(target_plan.exposure)
		return
	incoming_losses[target_id] += lethal * float(target_plan.exposure) * variation
	if target_plan.has("personal_ledger"):
		state.gameplay_port.get_ref().participants.incoming(target_plan, lethal * variation)
	incoming_pressure[target_id] += pressure * float(target_plan.exposure) / maxf(kernel._contact_weight(state, target_id), float(state.examine_unit(target_id).effective))

func _apply_unit(id: String) -> void:
	var unit: Dictionary = state.examine_unit(id)
	var plan: Dictionary = plans[id]
	var mission: Dictionary = state.missions[unit.mission_id]
	var old_action: String = str(unit.action)
	var prior_fuel_spent: float = float(unit.get("fuel_spent", 0.0))
	if state.coordination.has(id):
		var old_status: String = str(state.coordination[id].get("status", ""))
		state.coordination[id].status = "waiting" if plan.posture == "reserve" else "assigned"
		if old_status != state.coordination[id].status:
			log.append({"time": state.time, "kind": "coordination_changed", "unit_id": id, "status": state.coordination[id].status})
	var loss: float = minf(float(unit.effective), float(incoming_losses[id]))
	if plan.has("personal_ledger"):
		loss = state.gameplay_port.get_ref().participants.settle(unit, plan)
	var equipment_loss: float = kernel.apply_capacity_loss(state, unit, loss)
	unit.ammunition = maxf(0.0, float(unit.ammunition) - float(plan.spent))
	unit.ammo_spent += float(plan.spent)
	state.totals.ammo_spent += float(plan.spent)
	var decay: float = exp(-kernel.SUPPRESSION_DECAY * minutes)
	unit.suppression = clampf(float(unit.suppression) * decay + float(incoming_pressure[id]) / kernel.SUPPRESSION_DECAY * (1.0 - decay), 0.0, 1.0)
	unit.cohesion = clampf(float(unit.cohesion) - loss / maxf(float(unit.get("contact_weight", unit.get("tactical_weight", 1.0))), float(unit.personnel_total)) * kernel.COHESION_PER_LOSS, 0.0, 1.0)
	unit.action = str(plan.posture)
	if float(unit.effective) <= kernel._effective_epsilon(state, unit):
		unit.action = "disabled"
		if state.gameplay_port != null and old_action != "disabled":
			state.gameplay_port.get_ref().on_unit_unavailable(id)
	elif plan.posture == "advance" and float(plan.speed) == 0.0:
		unit.action = "stalled"
	var movement: float = float(plan.speed) * minutes if unit.action != "disabled" else 0.0
	var old_position: float = float(unit.position)
	var travelled: float
	if unit.has("spatial"):
		var prior_status: String = str(mission.status)
		travelled = state.spatial_port.get_ref().move(unit, plan, minutes, log)
		if mission.status != prior_status and mission.status in ["complete", "withdrawn"]:
			kernel._wake_dependents(state, str(mission.id))
	else:
		unit.position = clampf(old_position + movement, 0.0, float(area.size_km))
		travelled = absf(float(unit.position) - old_position)
	unit.distance_moved += travelled
	if unit.has("supply_capability"):
		state.logistics_port.get_ref().consume_activity(unit, plan, travelled)
	if state.gameplay_port != null:
		state.gameplay_port.get_ref().participants.after_movement(unit, plan)
		state.gameplay_port.get_ref().land.after_unit(unit, travelled, prior_fuel_spent, plan)
	var front_moving: bool = state.gameplay_port != null and state.gameplay_port.get_ref().tactics.manoeuvre_active(id) and state.gameplay_port.get_ref().tactics.manoeuvres[id].phase in ["FRONT_MOVING", "FRONT_RETURNING"]
	if movement != 0.0 or float(plan.spent) > 0.0 or front_moving:
		unit.fatigue = clampf(float(unit.fatigue) + kernel.FATIGUE_PER_MINUTE * minutes, 0.0, 1.0)
	# Mission completion is after all fire was planned, never a faction update advantage.
	if not unit.has("spatial") and mission.status == "active" and plan.posture in ["advance", "withdraw"] and absf(float(unit.position) - float(mission.objective)) < 0.00001:
		unit.position = float(mission.objective)
		mission.status = "complete"
		kernel._wake_dependents(state, str(mission.id))
		log.append({"time": state.time, "kind": "mission_complete", "unit_id": id, "mission_id": mission.id})
		if not str(mission.destination).is_empty() and (area.links as Dictionary).has(mission.destination):
			transfers.append({"unit_id": id, "destination": str(mission.destination)})
	elif not unit.has("spatial") and mission.status == "active" and plan.posture == "withdraw" and mission.posture != "withdraw":
		if float(unit.position) <= 0.00001 or float(unit.position) >= float(area.size_km) - 0.00001:
			unit.position = 0.0 if float(unit.position) <= 0.00001 else float(area.size_km)
			mission.status = "withdrawn"
			kernel._wake_dependents(state, str(mission.id))
			unit.action = "withdrawn"
			log.append({"time": state.time, "kind": "mission_withdrawn", "unit_id": id, "mission_id": mission.id})
	if loss > 0.0:
		log.append({"time": state.time, "kind": "losses", "unit_id": id, "personnel": loss, "equipment": equipment_loss})
	if old_action != unit.action:
		var reason: String = "mission"
		if state.tactical_intents.has(id):
			reason = "squad_tactical_intent"
		if unit.action == "stalled":
			reason = "suppression" if plan.advance_inhibited else "mobility"
		elif unit.action == "withdraw" and mission.posture != "withdraw":
			reason = "cohesion"
		log.append({"time": state.time, "kind": "action_changed", "unit_id": id,
			"action": unit.action, "reason": reason, "suppression": unit.suppression})
	changes[id] = unit.duplicate(true)
	state.touched_units[id] = true
	var next_posture: String = kernel._posture(state, unit)
	var has_fire: bool = not (plan.contacts as Array).is_empty() and float(unit.ammunition) > 0.0 and float(unit.effective) > kernel._effective_epsilon(state, unit)
	if plan.has("fire_components"):
		has_fire = float(plan.rounds) > 0.000001 and float(unit.effective) > kernel._effective_epsilon(state, unit)
	# A completed dependency can release a reserve in this same simultaneous step.
	# Keep that area awake so its freshly eligible mission is evaluated next.
	var moving: bool = mission.status == "active" and next_posture in ["advance", "withdraw"] and float(unit.effective) > kernel._effective_epsilon(state, unit) and float(unit.mobility) > 0.0 and float(unit.readiness) > 0.0 and float(area.movement_modifier) > 0.0
	if unit.has("supply_capability"):
		has_fire = has_fire and float(unit.serviceable_equipment) > 0.0
		if unit.supply_capability.fuel_dependent:
			moving = moving and float(unit.fuel) > 0.0000001 and float(unit.serviceable_equipment) > 0.0
	if unit.has("spatial"):
		moving = moving and state.spatial_port.get_ref().can_move(unit)
		# A versioned route must produce its first local obstruction feedback before
		# sleeping. Later identical obstruction stays asleep until a real wake.
		if (mission.has("goal_v1") or mission.get("summary_goal_policy", false)) and mission.status == "active" and not unit.spatial.path.is_empty() and str(unit.spatial.blocked_edge).is_empty() and not state.spatial_port.get_ref().can_move(unit):
			moving = true
	if state.gameplay_port != null and state.gameplay_port.get_ref().tactics.manoeuvre_active(id):
		moving = not plan.get("part_moves", {}).is_empty()
	# Reserves sleep until an indexed dependency notification or release event.
	remains_active = remains_active or has_fire or moving or float(unit.suppression) > kernel.SLEEP_EPSILON

func _contact_diagnostic(contact: Dictionary) -> void:
	if plans[contact.source].has("fire_doses"):
		contact.time = state.time
		contact.usable_fire_per_minute = float(plans[contact.source].fire_doses.get(contact.target, {}).get("rounds", 0.0)) / maxf(0.000001, minutes)
		return
	if body_targets.has(contact.target):
		contact.time = state.time
		contact.usable_fire_per_minute = float(plans[contact.source].spent) / minutes / float(plans[contact.source].target_weight) * _weight(str(contact.target)) * float(plans[contact.source].get("contact_factors", {}).get(contact.target, 1.0))
		return
	var target: Dictionary = state.examine_unit(str(contact.target))
	var source_plan: Dictionary = plans[contact.source]
	contact.time = state.time
	contact.usable_fire_per_minute = float(source_plan.spent) / minutes / float(source_plan.target_weight) * float(target.get("contact_weight", target.get("tactical_weight", 1.0))) * float(source_plan.get("contact_factors", {}).get(contact.target, 1.0))
	contact.suppression = target.suppression
	contact.movement_km_per_minute = plans[contact.target].speed
	contact.advance_inhibited = target.action == "stalled"
	contact.disengaging = target.action in ["withdraw", "withdrawn"]

func _weight(id: String) -> float:
	return float(body_targets[id].weight) if body_targets.has(id) else kernel._contact_weight(state, id)

func _finish_activity() -> void:
	if not remains_active:
		if state.spatial_port != null:
			for cell: String in state.spatial_port.get_ref().scope_cells(area_id):
				state.active_areas.erase(cell)
		else:
			state.active_areas.erase(area_id)
		state.contacts.erase(area_id)
