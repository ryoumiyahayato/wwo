extends RefCounted
## Bounded weapon allocations inside the original personnel/ammunition accounts.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const LOCAL_ACTIONS: Array[String] = ["observe", "watch", "fire", "cease_fire", "reload", "release_weapon", "claim_weapon"]
const FIRE_MODES: Array[String] = ["concentrate", "suppress", "cover_move", "watch", "cease", "resume"]
var _owner: WeakRef
var weapons: Dictionary = {}
var guns: Dictionary = {}
var fire_orders: Dictionary = {}
var manoeuvres: Dictionary = {}
var ammunition_custody: Dictionary = {} # Claims inside unit.ammunition, not another stock.
var supply_jobs: Dictionary = {} # At most one contact operation per original unit.
const CARRY_AMMUNITION: float = 4.0 # Synthetic capacity per available member share.
const HANDLING_SECONDS: float = 5.0
var _tickets: Dictionary = {}
var _serial: int = 0

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func _g() -> RefCounted:
	return _owner.get_ref()

func admit_weapon(actor: String, profile: Dictionary = {}) -> bool:
	var g: RefCounted = _g()
	if g._state.time != 0.0 or not g.participants._units.has(actor) or weapons.has(actor) or weapons.size() >= 6:
		return false
	var unit: Dictionary = g.participants._physical_unit(actor)
	var cap: Dictionary = {"role": "rifle", "magazine": 4.0, "reload_seconds": 10.0, "aim_seconds": 5.0,
		"rounds_per_minute": float(unit.weapon.rounds_per_minute), "range_km": float(unit.weapon.range_km),
		"lethality": float(unit.weapon.lethality), "suppression_per_round": 0.12, "equipment_share": 1.0}
	for key: String in profile:
		if not cap.has(key):
			return false
		cap[key] = profile[key]
	if cap.role not in ["rifle", "automatic", "precision"]:
		return false
	var differentiated: Dictionary = {"automatic": {"magazine": 12.0, "reload_seconds": 18.0, "aim_seconds": 6.0,
		"rounds_per_minute": float(unit.weapon.rounds_per_minute) * 1.8, "lethality": float(unit.weapon.lethality) * 0.5, "suppression_per_round": 0.2},
		"precision": {"magazine": 2.0, "reload_seconds": 12.0, "aim_seconds": 20.0, "rounds_per_minute": float(unit.weapon.rounds_per_minute) * 0.3,
			"lethality": float(unit.weapon.lethality) * 1.3, "suppression_per_round": 0.04}}
	for key: String in differentiated.get(cap.role, {}):
		if not profile.has(key):
			cap[key] = differentiated[cap.role][key]
	for key: String in cap:
		if key != "role" and not _positive(cap[key]):
			return false
	if float(cap.range_km) > float(unit.weapon.range_km):
		return false # Direct roles remain inside the current kernel's contact envelope.
	if _equipment_claims(str(unit.id)) + float(cap.equipment_share) > float(unit.get("serviceable_equipment", unit.equipment)):
		return false
	weapons[actor] = {"id": "weapon_" + actor, "actor_ref": actor, "unit_ref": unit.id, "source_ref": unit.id,
		"holder_ref": actor, "location_ref": "person:" + actor, "custody": "HELD", "binding_revision": 0, "profile": cap, "ready": 0.0,
		"mode": "RELEASED" if cap.role == "rifle" else "GROUP", "status": "UNPREPARED", "revision": 0, "spent": 0.0}
	return true

func admit_gun(id: String, unit_id: String, cap: Dictionary) -> bool:
	var g: RefCounted = _g()
	if g._state.time != 0.0 or id.is_empty() or guns.size() >= 2 or guns.has(id) or not g._state.units.has(unit_id) or not g._state.units[unit_id].has("spatial"):
		return false
	for key: String in ["crew", "equipment_share", "range_km", "deploy_seconds", "reload_seconds", "cycle_seconds", "rounds_per_mission", "lethality", "radius_km"]:
		if not _positive(cap.get(key)):
			return false
	var unit: Dictionary = g._state.units[unit_id]
	if _equipment_claims(unit_id) + float(cap.equipment_share) > float(unit.get("serviceable_equipment", unit.equipment)) or _gun_crew(unit_id) + float(cap.crew) > float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective)):
		return false
	guns[id] = {"id": id, "unit_ref": unit_id, "node_ref": unit.spatial.node, "profile": cap.duplicate(true), "state": "PACKED", "revision": 0, "ready": 0.0, "spent": 0.0, "fire_ref": ""}
	return true

func _equipment_claims(unit: String) -> float:
	var total: float = 0.0
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == unit:
			total += float(weapon.profile.equipment_share)
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit:
			total += float(gun.profile.equipment_share)
	return total

func _gun_crew(unit: String) -> float:
	var total: float = 0.0
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit and gun.state not in ["PACKED", "INTERRUPTED"]:
			total += float(gun.profile.crew)
	return total

func occupied(unit: String) -> bool:
	if fire_orders.has(unit) or manoeuvre_active(unit):
		return true
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == unit and weapon.mode not in ["RELEASED", "GROUP"]:
			return true
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit and gun.state != "PACKED":
			return true
	return false

func requires_detail(unit: String) -> bool:
	if supply_jobs.has(unit) or _carried_total(unit) > 0.000001:
		return true
	var physical: Dictionary = _g()._state.units.get(unit, {})
	if physical.has("spatial") and (str(physical.spatial.get("local_edge", "")) != "" or _g()._space.local_place(physical.spatial) != "node:" + str(physical.spatial.node)):
		return true # Current aggregation cannot replace a local site with a node.
	if manoeuvres.has(unit) and not manoeuvre_active(unit):
		var parts: Dictionary = manoeuvres[unit].parts
		if absf(float(parts.front.fatigue) - float(parts.rear.fatigue)) > _g()._lod.CONDITION_SPREAD or absf(float(parts.front.cohesion) - float(parts.rear.cohesion)) > _g()._lod.CONDITION_SPREAD or absf(part_pressure(parts.front) - part_pressure(parts.rear)) > _g()._lod.CONDITION_SPREAD:
			return true
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == unit and (weapon.mode != "RELEASED" or float(weapon.ready) > 0.000001 or weapon.get("custody", "HELD") == "LEFT"):
			return true
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit:
			return true
	return occupied(unit)

func protected_equipment(unit: String) -> float:
	if manoeuvre_active(unit):
		return float(manoeuvres[unit].parts.front.equipment) + float(manoeuvres[unit].parts.rear.equipment)
	var result: float = 0.0
	for person: String in weapons:
		var weapon: Dictionary = weapons[person]
		if weapon.unit_ref == unit and weapon.get("holder_ref", "") == person and (separated_actor(person) or StateDistance(_g().participants.position(person), _g()._space.xy(_g().participants._physical_unit(person))) > float(_g().participants.rules.local_radius_km)):
			result += float(weapon.profile.equipment_share)
	return result

func residual_capacity(unit: String) -> float:
	if manoeuvre_active(unit):
		return 0.0 # All current capacity has a part or body position.
	var result: float = float(_g()._state.units[unit].effective)
	if manoeuvre_active(unit):
		for person: String in manoeuvres[unit].movers:
			if _g().participants._units.get(person, "") == unit:
				result -= float(_g().participants._member(person).health)
	return maxf(0.0, result)

func ammunition_at_unit(unit: Dictionary) -> float:
	if manoeuvre_active(str(unit.id)):
		return float(manoeuvres[unit.id].parts[manoeuvres[unit.id].stock_part].ammunition)
	var carried: float = 0.0
	for person: String in weapons:
		var weapon: Dictionary = weapons[person]
		if weapon.unit_ref == unit.id and weapon.get("holder_ref", "") == person and (separated_actor(person) or StateDistance(_g().participants.position(person), _g()._space.xy(unit)) > float(_g().participants.rules.local_radius_km)):
			carried += float(weapon.ready)
	return maxf(0.0, float(unit.ammunition) - carried - _carried_total(str(unit.id)))

func on_unit(unit: String) -> void:
	_update_custody(unit)
	if _g()._state.units.has(unit):
		_sync_part_stock(_g()._state.units[unit])
	_update_manoeuvre(unit)
	_update_cover_move(unit)
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref != unit or weapon.mode == "RELEASED" or not _g()._state.units.has(unit):
			continue
		var actual: Dictionary = _g()._state.units[unit]
		var body: Dictionary = _g().participants._member(str(weapon.actor_ref))
		if body.state == "FOLLOWING" and (weapon.mode != "CEASE" or weapon.status in ["RELOADING", "AIMING"]) and (str(actual.spatial.edge) != "" or not actual.spatial.path.is_empty()):
			if not (manoeuvre_active(unit) and weapon.mode == "GROUP" and weapon.status not in ["RELOADING", "AIMING"]):
				_stop(weapon, "GROUP" if manoeuvre_active(unit) and weapon.mode == "GROUP" else "CEASE")
	for gun: Dictionary in guns.values():
		if gun.unit_ref != unit or gun.state in ["PACKED", "INTERRUPTED"]:
			continue
		var actual: Dictionary = _g()._state.units.get(unit, {})
		if actual.is_empty() or not _crew_available(gun) or not _free(actual) or actual.spatial.node != gun.get("node_ref", "") or str(actual.spatial.edge) != "" or not actual.spatial.path.is_empty() and gun.state != "PACKING":
			gun.revision += 1
			gun.state = "INTERRUPTED"
			gun.reason = "actual_crew_position_equipment_or_duty_changed"

func _update_cover_move(unit: String) -> void:
	var order: Dictionary = fire_orders.get(unit, {})
	if order.get("fire_mode", "") != "cover_move" or not _g()._state.units.has(unit):
		return
	var pending: Array[String] = []
	for actor: String in order.get("moving", {}):
		var movement: Dictionary = order.moving[actor]
		if movement.status == "PENDING":
			pending.append(actor)
	if pending.is_empty():
		order.phase = "MOVEMENT_FINISHED"
		order.fire_mode = "resume"
		return
	var actual: Dictionary = _g()._state.units[unit]
	var capacity: float = float(actual.effective) - _gun_crew(unit)
	for actor: String in pending:
		capacity -= float(_g().participants._member(actor).health)
	if capacity <= 0.000001 or _unreserved(actual) <= 0.000001 or float(actual.suppression) >= 0.8 or not _free(actual):
		for actor: String in pending:
			_g().participants.interrupt_action(actor, "covering_capacity_or_ammunition_unavailable")
		order.phase = "INTERRUPTED"
		order.fire_mode = "resume"
		_g()._emit(unit, "cover_move_interrupted", str(order.input_ref), {"moving": order.moving.duplicate(true)})

func _free(unit: Dictionary) -> bool:
	var g: RefCounted = _g()
	return not g.land._unit_jobs.has(unit.id) and not g.air.recovery._unit_jobs.has(unit.id) and not g.operations.occupied_ground(str(unit.id)) and not g._state.coordination.get(unit.id, {}).get("retained", false)

func _body_source(actor: String, range_km: float) -> Dictionary:
	var g: RefCounted = _g()
	var body: Dictionary = g.participants._member(actor)
	var unit: Dictionary = g.participants._physical_unit(actor).duplicate(true)
	unit.weapon.range_km = range_km
	unit.weapon.observation_range_km = range_km
	unit.spatial.node = g.participants._physical_unit(actor).spatial.node if body.state == "FOLLOWING" else body.anchor_node
	unit.spatial.edge = g.participants._physical_unit(actor).spatial.edge if body.state == "FOLLOWING" else body.get("anchor_edge", "")
	unit.spatial.point_xy = g.participants.position(actor)
	unit.spatial.path = []
	var actual: Dictionary = g.participants.body_spatial(actor)
	for field: String in ["local_ref", "local_edge", "entered_site_ref"]:
		unit.spatial.erase(field)
		if actual.has(field):
			unit.spatial[field] = actual[field]
	return unit

func visible(actor: String, target: String, firing: bool = false) -> bool:
	var g: RefCounted = _g()
	if not g.participants._units.has(actor) or not g.participants.can_intend(actor) or not g._state.units.has(target):
		return false
	var own: Dictionary = g.participants._physical_unit(actor)
	var other: Dictionary = g._state.units[target]
	var range_km: float = float(weapons[actor].profile.range_km) if firing and weapons.has(actor) else float(own.weapon.get("observation_range_km", own.weapon.range_km))
	if other.side == own.side:
		return false
	var source: Dictionary = _body_source(actor, range_km)
	return not visible_targets(source, target, firing).is_empty()

func validate_person(actor: String, values: Dictionary) -> Dictionary:
	var g: RefCounted = _g()
	if g._state.public_pending():
		return g._state.pending_view()
	var action: String = str(values.get("action", ""))
	if action not in LOCAL_ACTIONS or not g.participants._units.has(actor) or not g.participants.can_intend(actor):
		return _reject("able_existing_person_and_combat_action_required")
	var body: Dictionary = g.participants._member(actor)
	var unit: Dictionary = g.participants._physical_unit(actor)
	var part: Dictionary = actor_part(actor)
	if not str(body.action_ref).is_empty() or float(body.get("combat_busy_until", 0.0)) > g._state.time or body.state in ["ENTERING", "RETURNING", "RELOCATING", "PART_MOVING"]:
		return _reject("body_action_occupied")
	if _tickets.size() > 60:
		return _reject("finite_tactical_event_capacity")
	if action in ["observe", "watch"]:
		var local_node: String = str(unit.spatial.node) if body.state == "FOLLOWING" else str(body.anchor_node)
		var direction: String = str(values.get("node_ref", local_node))
		var actual: Dictionary = g.participants.body_spatial(actor)
		var local_point: bool = g._space._local_sites.has(g._space.local_place(actual)) or g._space._local_edges.has(actual.get("local_edge", ""))
		var at_node: bool = direction == local_node and g._space._nodes.has(local_node) and (local_point or StateDistance(g.participants.position(actor), g._space._nodes[local_node].xy) <= float(g.participants.rules.local_radius_km))
		if not at_node and not g._known.get(actor, {}).has(direction):
			return _reject("known_observation_direction_required")
		if action == "watch" and body.state == "FOLLOWING" and (str(unit.spatial.edge) != "" or not unit.spatial.path.is_empty()):
			return _reject("watch_requires_actual_stationary_local_position")
		return {"ok": true}
	if action == "claim_weapon":
		var left: Dictionary = weapons.get(actor, {})
		if left.is_empty() or left.get("custody", "") != "LEFT" or left.unit_ref != unit.id or str(unit.spatial.edge) != "" or not unit.spatial.path.is_empty() or StateDistance(g.participants.position(actor), g._space.xy(unit)) > float(g.participants.rules.local_radius_km):
			return _reject("left_weapon_requires_actual_holder_contact")
		return {"ok": true}
	if not weapons.has(actor) or weapons[actor].unit_ref != unit.id or weapons[actor].get("holder_ref", actor) != actor:
		return _reject("actual_allocated_weapon_required")
	var weapon: Dictionary = weapons[actor]
	if action == "release_weapon" and not stock_contact(actor):
		return _reject("prepared_claim_release_requires_actual_unit_stock_contact")
	if action in ["fire", "reload"] and (not _free(unit) or (float(unit.get("serviceable_equipment", unit.equipment)) < _equipment_claims(str(unit.id)) if part.is_empty() else float(part.serviceable) < _part_weapon_equipment(part))):
		return _reject("weapon_equipment_or_unit_duty_unavailable")
	if action == "reload" and not stock_contact(actor) and _carried_amount(actor) <= 0.000001:
		return _reject("weapon_and_unit_ammunition_must_be_at_actual_person_location")
	if action == "fire" and body.state == "FOLLOWING" and (str(unit.spatial.edge) != "" or not unit.spatial.path.is_empty()):
		return _reject("precise_weapon_action_requires_stationary_group")
	if action == "fire" and float(weapon.ready) <= 0.000001:
		return _reject("actual_carried_prepared_ammunition_required")
	if weapon.status in ["RELOADING", "AIMING"] and action not in ["cease_fire", "release_weapon"]:
		return _reject("weapon_operation_in_progress")
	if action == "fire" and (not visible(actor, str(values.get("target_ref", "")), true) or not _positive(values.get("seconds", 60.0)) or float(values.get("seconds", 60.0)) > 300.0):
		return _reject("current_visible_reachable_target_and_bounded_fire_required")
	if action == "reload" and _reload_available(actor) <= 0.000001:
		return _reject("no_compatible_unallocated_unit_ammunition")
	return {"ok": true}

func personal(actor: String, id: String, values: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_person(actor, values)
	if not valid.ok:
		return valid
	var g: RefCounted = _g()
	var changed: Dictionary = g._lod.materialize_leaf(str(g.participants._units[actor]), "explicit_weapon_action")
	var action: String = str(values.action)
	if weapons.has(actor):
		weapons[actor].group_assignment_ref = "" # Later personal intent owns its weapon operation.
	if action in ["observe", "watch"]:
		if weapons.has(actor):
			_stop(weapons[actor], "WATCH")
		var body: Dictionary = g.participants._member(actor)
		var local_node: String = str(g.participants._physical_unit(actor).spatial.node) if body.state == "FOLLOWING" else str(body.anchor_node)
		_queue("OBSERVE", actor, id, 5.0, {"node_ref": values.get("node_ref", local_node)})
		g.participants._member(actor).combat_busy_until = g._state.time + 5.0
		if action == "watch":
			body.xy = g.participants.position(actor)
			if body.state == "FOLLOWING":
				body.anchor_node = g.participants._physical_unit(actor).spatial.node
				body.anchor_edge = g.participants._physical_unit(actor).spatial.edge
				body.state = "STATIONARY"
	elif action in ["cease_fire", "release_weapon"]:
		_stop(weapons[actor], ("RELEASED" if weapons[actor].profile.role == "rifle" else "GROUP") if action == "release_weapon" else "CEASE")
		if action == "release_weapon":
			if g.participants._member(actor).get("local_duty", false):
				_ammunition_pack(actor).amount += float(weapons[actor].ready)
			weapons[actor].ready = 0.0
	elif action == "claim_weapon":
		var weapon: Dictionary = weapons[actor]
		_stop(weapon, "CEASE")
		weapon.holder_ref = actor
		weapon.location_ref = "person:" + actor
		weapon.custody = "HELD"
		weapon.binding_revision += 1
		weapon.last_claim = {"at": g._state.time, "cause_ref": id, "xy": g.participants.position(actor)}
	elif action == "reload":
		_start_reload(actor, id)
	else:
		var weapon: Dictionary = weapons[actor]
		weapon.revision += 1
		weapon.mode = "FIRE"
		weapon.fire_owner_ref = id
		weapon.target_ref = values.target_ref
		weapon.until = g._state.time + float(values.get("seconds", 60.0))
		weapon.status = "AIMING"
		_queue("AIM", actor, id, float(weapon.profile.aim_seconds), {"revision": weapon.revision})
		_queue("CEASE", actor, id, float(values.get("seconds", 60.0)), {"revision": weapon.revision})
	g.participants._emit(actor, "personal_combat_intent", id, values)
	g._state.wake(str(g.participants._physical_unit(actor).area_id))
	return {"ok": true, "status": action, "changed": changed.get("changed", []), "retired": changed.get("retired", [])}

func _stop(weapon: Dictionary, mode: String) -> void:
	if weapon.status in ["RELOADING", "AIMING"] or weapon.mode == "FIRE":
		weapon.last_interruption = {"at": _g()._state.time, "status": weapon.status,
			"operation_ref": weapon.get("operation_ref", ""), "elapsed": maxf(0.0, _g()._state.time - float(weapon.get("started_at", _g()._state.time)))}
	weapon.revision += 1
	weapon.mode = mode
	weapon.status = "READY" if float(weapon.ready) > 0.000001 else "EMPTY"
	weapon.operation_ref = ""
	weapon.fire_owner_ref = ""

func _start_reload(actor: String, cause: String) -> void:
	var weapon: Dictionary = weapons[actor]
	weapon.revision += 1
	weapon.status = "RELOADING"
	if weapon.mode == "RELEASED":
		weapon.mode = "CEASE"
	_queue("RELOAD", actor, cause, float(weapon.profile.reload_seconds), {"revision": weapon.revision})

func _unreserved(unit: Dictionary) -> float:
	if manoeuvre_active(str(unit.id)):
		var part: Dictionary = manoeuvres[unit.id].parts[manoeuvres[unit.id].stock_part]
		return maxf(0.0, float(part.ammunition) - _part_ready(part))
	var ready: float = 0.0
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == unit.id:
			ready += float(weapon.ready)
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit.id:
			ready += float(gun.ready)
	return maxf(0.0, float(unit.ammunition) - ready - _carried_total(str(unit.id)))

func _ammunition_pack(actor: String) -> Dictionary:
	if not ammunition_custody.has(actor):
		ammunition_custody[actor] = {"id": "carry_ammunition:" + actor, "source_ref": _g().participants._units[actor],
			"unit_ref": _g().participants._units[actor], "holder_ref": actor, "amount": 0.0, "status": "HELD", "revision": 0,
			"received": 0.0, "handed_over": 0.0, "last_action_ref": ""}
	return ammunition_custody[actor]

func _carried_amount(actor: String) -> float:
	var cargo: Dictionary = ammunition_custody.get(actor, {})
	return float(cargo.get("amount", 0.0)) if cargo.get("status", "") == "HELD" else 0.0

func _carried_total(unit: String) -> float:
	var total: float = 0.0
	for cargo: Dictionary in ammunition_custody.values():
		if cargo.unit_ref == unit:
			total += float(cargo.amount)
	return total

func _detached_ready(unit: String) -> float:
	var total: float = 0.0
	for actor: String in weapons:
		if weapons[actor].unit_ref == unit and _g().participants._member(actor).get("local_duty", false):
			total += float(weapons[actor].ready)
	return total

func begin_local_duty(actor: String) -> void:
	var body: Dictionary = _g().participants._member(actor)
	if body.get("local_duty", false):
		return
	var part: Dictionary = roster_part(actor)
	if not part.is_empty():
		_stop_manoeuvre(str(part.unit_ref), "local_support_duty", actor)
		part.ammunition -= float(weapons.get(actor, {}).get("ready", 0.0))
		body.local_duty = true
		body.local_duty_part_ref = part.id

func rejoin_local_duty(actor: String) -> void:
	var p: RefCounted = _g().participants
	var body: Dictionary = p._member(actor)
	var part: Dictionary = roster_part(actor)
	if not body.get("local_duty", false) or part.is_empty() or not body.actionable or not str(body.action_ref).is_empty() or not str(body.get("carrying_ref", "")).is_empty() or _carried_amount(actor) > 0.000001:
		return
	if StateDistance(p.position(actor), _g()._space.xy(part_source(p._physical_unit(actor), part))) > 0.000001 or str(p.body_spatial(actor).get("local_edge", "")) != "":
		return
	part.ammunition += float(weapons.get(actor, {}).get("ready", 0.0))
	body.erase("local_duty")
	body.erase("local_duty_part_ref")

func _update_custody(unit: String) -> void:
	var p: RefCounted = _g().participants
	for actor: String in ammunition_custody:
		var cargo: Dictionary = ammunition_custody[actor]
		if cargo.unit_ref == unit and cargo.status == "HELD" and (not p._member(actor).actionable or float(p._member(actor).health) < float(p.rules.minimum_carrier_health)):
			cargo.xy = p.position(actor)
			cargo.spatial = p.body_spatial(actor).duplicate(true)
			cargo.spatial.point_xy = cargo.xy.duplicate()
			cargo.status = "STRANDED"
			cargo.holder_ref = "ground:" + str(cargo.id)
			cargo.revision += 1
			p._emit(actor, "ammunition_stranded", str(cargo.last_action_ref), {"cargo_ref": cargo.id, "quantity": cargo.amount, "xy": cargo.xy})
	if supply_jobs.has(unit) and not _supply_contact(supply_jobs[unit]):
		_finish_supply(unit, false, "actual_contact_or_handling_capacity_lost")

func _supply_point(unit: String, reference: String) -> Dictionary:
	var g: RefCounted = _g()
	var actual: Dictionary = g._state.units.get(unit, {})
	if actual.is_empty():
		return {}
	if reference == "unit":
		if manoeuvre_active(unit):
			return _supply_point(unit, "part:" + str(manoeuvres[unit].stock_part))
		return {"xy": g._space.xy(actual), "spatial": actual.spatial, "available": _unreserved(actual), "room": INF,
			"able": _free(actual) and str(actual.spatial.edge) == "" and actual.spatial.path.is_empty(), "revision": 0}
	if reference.begins_with("part:"):
		var part: Dictionary = manoeuvres.get(unit, {}).get("parts", {}).get(reference.trim_prefix("part:"), {}) if manoeuvre_active(unit) else {}
		if part.is_empty():
			return {}
		return {"xy": g._space.xy(part_source(actual, part)), "spatial": part.spatial, "available": maxf(0.0, float(part.ammunition) - _part_ready(part)),
			"room": maxf(0.0, part_capacity(part) * CARRY_AMMUNITION - float(part.ammunition)),
			"able": part.role not in ["MOVING", "ENTERING"] and part_pressure(part) < 0.8, "revision": part.revision, "part_ref": part.id}
	var stranded: bool = reference.begins_with("stranded:")
	var actor: String = reference.trim_prefix("stranded:" if stranded else "person:")
	if stranded:
		var cargo: Dictionary = ammunition_custody.get(actor, {})
		if cargo.get("unit_ref", "") != unit or cargo.get("status", "") != "STRANDED":
			return {}
		return {"xy": cargo.xy, "spatial": cargo.spatial, "available": cargo.amount, "room": 0.0, "able": true, "revision": cargo.revision}
	if not reference.begins_with("person:") or g.participants._units.get(actor, "") != unit:
		return {}
	var body: Dictionary = g.participants._member(actor)
	return {"xy": g.participants.position(actor), "spatial": g.participants.body_spatial(actor), "available": _carried_amount(actor),
		"room": maxf(0.0, float(body.health) * CARRY_AMMUNITION - _carried_amount(actor)), "revision": int(body.get("combat_revision", 0)),
		"able": body.actionable and float(body.health) >= float(g.participants.rules.minimum_carrier_health) and body.state not in ["PART_MOVING", "PART_ENTERING", "LOCAL_MOVING", "LOCAL_ENTERING", "RELOCATING", "TRANSPORTED", "MEDICATING", "PICKING_UP"] and str(body.get("carrying_ref", "")).is_empty()}

func _supply_contact(job: Dictionary) -> bool:
	var a: Dictionary = _supply_point(str(job.unit_ref), str(job.source_ref))
	var b: Dictionary = _supply_point(str(job.unit_ref), str(job.target_ref))
	if a.is_empty() or b.is_empty() or not a.able or not b.able:
		return false
	for person: String in job.get("people", []):
		var p: RefCounted = _g().participants
		if p._actions.get(p._member(person).action_ref, {}).get("supply_ref", "") != job.id:
			return false
	for reference: String in job.get("part_refs", []):
		var found: bool = false
		for part: Dictionary in manoeuvres.get(job.unit_ref, {}).get("parts", {}).values():
			found = found or part.id == reference
		if not found:
			return false
	return a.spatial.node == b.spatial.node and _g()._space.local_place(a.spatial) == _g()._space.local_place(b.spatial) and str(a.spatial.get("local_edge", "")) == "" and str(b.spatial.get("local_edge", "")) == "" and StateDistance(a.xy, b.xy) <= float(_g().participants.rules.local_radius_km)

func validate_ammunition(actor: String, unit: String, values: Dictionary, command: bool = false) -> Dictionary:
	var g: RefCounted = _g()
	if values.get("ammo_action", "") == "move":
		return _validate_part_delivery(actor, unit, values) if command else _reject("part_delivery_requires_current_squad_command")
	if not g._state.units.has(unit) or supply_jobs.has(unit) or supply_jobs.size() >= 4 or _tickets.size() >= 58 or not _free(g._state.units[unit]) or g._state.units[unit].spatial.mode != "FOOT":
		return _reject("existing_free_foot_unit_and_handling_slot_required")
	if manoeuvre_active(unit) and manoeuvres[unit].phase != "STOPPED":
		return _reject("stop_parts_before_actual_contact_handover")
	var mode: String = str(values.get("ammo_action", ""))
	if mode not in ["take", "handover", "recover"] or not _positive(values.get("quantity")):
		return _reject("explicit_ammunition_action_and_quantity_required")
	for field: String in values:
		if field not in ["action", "ammo_action", "source_ref", "target_ref", "quantity"]:
			return _reject("unsupported_ammunition_action_field")
	var source: String = str(values.get("source_ref", "unit" if mode == "take" else "person:" + actor))
	var target: String = str(values.get("target_ref", "person:" + actor))
	if not command and (g.participants._units.get(actor, "") != unit or not g.participants.can_intend(actor) or not str(g.participants._member(actor).action_ref).is_empty() or float(g.participants._member(actor).get("combat_busy_until", 0.0)) > g._state.time or (target != "person:" + actor if mode in ["take", "recover"] else source != "person:" + actor)):
		return _reject("personal_action_controls_only_own_actual_cargo")
	if source == target or mode == "recover" and not source.begins_with("stranded:") or target.begins_with("stranded:"):
		return _reject("distinct_actual_source_and_legal_receiver_required")
	var job: Dictionary = {"unit_ref": unit, "source_ref": source, "target_ref": target}
	if not _supply_contact(job):
		return _reject("stationary_actual_contact_required")
	var a: Dictionary = _supply_point(unit, source)
	var b: Dictionary = _supply_point(unit, target)
	if target.begins_with("person:"):
		var receiver: String = target.trim_prefix("person:")
		var cargo: Dictionary = ammunition_custody.get(receiver, {})
		if cargo.get("status", "") == "STRANDED" and float(cargo.amount) > 0.000001 and source != "stranded:" + receiver:
			return _reject("settle_receivers_existing_stranded_cargo_first")
	if float(a.available) <= 0.000001 or float(b.room) <= 0.000001:
		return _reject("existing_uncommitted_ammunition_and_carrier_capacity_required")
	for reference: String in [source, target]:
		if reference.begins_with("person:"):
			var person: String = reference.trim_prefix("person:")
			if not str(g.participants._member(person).action_ref).is_empty() or weapons.get(person, {}).get("status", "") in ["AIMING", "RELOADING"]:
				return _reject("receiver_or_carrier_has_unfinished_personal_operation")
	return {"ok": true, "source_ref": source, "target_ref": target, "quantity": minf(float(values.quantity), minf(float(a.available), float(b.room)))}

func ammunition_action(actor: String, unit: String, id: String, values: Dictionary, command: bool = false) -> Dictionary:
	var valid: Dictionary = validate_ammunition(actor, unit, values, command)
	if not valid.ok:
		return valid
	if values.ammo_action == "move":
		var order: Dictionary = manoeuvres[unit]
		order.revision += 1
		order.prior_delivery_route = {"path": order.path.duplicate(), "leg_index": order.leg_index, "travel_kind": order.travel_kind, "destination": order.destination_node}
		order.travel_kind = "LOCAL"
		order.path = values.local_path.duplicate()
		order.leg_index = 0
		order.edge_ref = ""
		order.lead_part = values.part_ref
		order.destination_node = values.destination_ref
		order.supply_only = true
		order.last_command_ref = id
		order.phase = "PREPARE"
		order.returning = false
		order.reason = ""
		_prepare_manoeuvre(order)
		return {"ok": true, "status": order.phase, "changed": [unit], "retired": []}
	var changed: Dictionary = _g()._lod.materialize_leaf(unit, "local_ammunition_handling")
	var job: Dictionary = {"id": id, "issuer": actor, "unit_ref": unit, "source_ref": valid.source_ref, "target_ref": valid.target_ref,
		"quantity": valid.quantity, "status": "PENDING", "started_at": _g()._state.time, "due": _g()._state.time + HANDLING_SECONDS + float(valid.quantity), "part_refs": [], "people": [], "handlers": [], "event_ref": ""}
	for reference: String in [str(valid.source_ref), str(valid.target_ref)]:
		if reference.begins_with("person:"):
			var person: String = reference.trim_prefix("person:")
			if person not in job.people:
				job.people.append(person)
			begin_local_duty(person)
			_g().participants._start(person, id, "AMMO_HANDLING", _g().participants.position(person), "", float(job.due) - _g()._state.time)
			_g().participants._actions[_g().participants._member(person).action_ref].supply_ref = id
			_g().participants._member(person).supply_job_ref = id
			if person not in job.handlers:
				job.handlers.append(person)
		if reference.begins_with("part:") or reference == "unit" and manoeuvre_active(unit):
			var key: String = reference.trim_prefix("part:") if reference != "unit" else str(manoeuvres[unit].stock_part)
			var part: Dictionary = manoeuvres[unit].parts[key]
			part.role = "WATCH"
			job.part_refs.append(part.id)
			for person: String in part.members:
				if not _g().participants._member(person).get("local_duty", false):
					_g().participants._member(person).combat_busy_until = job.due
					_g().participants._member(person).supply_job_ref = id
					if person not in job.handlers:
						job.handlers.append(person)
					if weapons.has(person):
						_stop(weapons[person], "CEASE")
	supply_jobs[unit] = job
	_queue("SUPPLY_HANDOVER", unit, id, float(job.due) - _g()._state.time, {"supply_ref": id})
	job.event_ref = "tactical_%d" % _serial
	_g()._emit(unit, "local_ammunition_handling_started", id, {"source_ref": valid.source_ref, "target_ref": valid.target_ref, "quantity": valid.quantity})
	return {"ok": true, "status": "PENDING_CONTACT_HANDOVER", "changed": changed.get("changed", [unit]), "retired": changed.get("retired", [])}

func _validate_part_delivery(actor: String, unit: String, values: Dictionary) -> Dictionary:
	var g: RefCounted = _g()
	if not manoeuvre_active(unit) or manoeuvres[unit].phase != "STOPPED" or supply_jobs.has(unit) or _tickets.size() > 52 or g._state.time >= float(manoeuvres[unit].deadline) or not _free(g._state.units[unit]):
		return _reject("stopped_original_parts_with_remaining_deadline_required")
	if values.size() != 4 or values.get("part_ref", "") not in ["front", "rear"] or not values.get("local_path") is Array or values.local_path.is_empty() or values.local_path.size() > 4 or not values.get("destination_ref") is String:
		return _reject("one_existing_part_and_bounded_local_delivery_route_required")
	var part: Dictionary = manoeuvres[unit].parts[values.part_ref]
	for section: Dictionary in manoeuvres[unit].parts.values():
		if str(section.spatial.get("edge", "")) != "" or str(section.spatial.get("local_edge", "")) != "":
			return _reject("both_parts_require_explained_endpoints_before_new_delivery_route")
	if float(part.ammunition) <= 0.000001 or float(part.ammunition) > part_capacity(part) * CARRY_AMMUNITION or str(part.spatial.get("edge", "")) != "" or str(part.spatial.get("local_edge", "")) != "":
		return _reject("actual_endpoint_and_limited_existing_carried_ammunition_required")
	if not g._known.get(actor, {}).get("local:" + str(values.destination_ref), []).has(values.local_path) or g._space.local_path_end(g._space.local_place(part.spatial), values.local_path) != values.destination_ref:
		return _reject("known_connected_local_delivery_route_required")
	for reference: Variant in values.local_path:
		if not g._space._local_edges.has(reference) or not g._space._local_edges[reference].open:
			return _reject("local_delivery_path_not_open")
	for person: String in part.members:
		if _member_conflict(person, manoeuvres[unit]):
			return _reject("part_has_another_actual_personal_or_support_duty")
	return {"ok": true}

func _adjust_custody(unit: String, reference: String, amount: float, cause: String) -> void:
	if reference == "unit" and manoeuvre_active(unit):
		reference = "part:" + str(manoeuvres[unit].stock_part)
	if reference.begins_with("part:"):
		var part: Dictionary = manoeuvres[unit].parts[reference.trim_prefix("part:")]
		part.ammunition += amount
		part.ammunition_received = float(part.get("ammunition_received", 0.0)) + maxf(0.0, amount)
		part.ammunition_handed_over = float(part.get("ammunition_handed_over", 0.0)) + maxf(0.0, -amount)
		part.last_ammunition_handover = {"cause_ref": cause, "at": _g()._state.time, "quantity": amount}
	elif reference.begins_with("person:") or reference.begins_with("stranded:"):
		var person: String = reference.trim_prefix("person:").trim_prefix("stranded:")
		var pack: Dictionary = _ammunition_pack(person)
		pack.amount += amount
		pack.received += maxf(0.0, amount)
		pack.handed_over += maxf(0.0, -amount)
		pack.revision += 1
		pack.last_action_ref = cause
		if amount > 0.0 and reference.begins_with("person:"):
			pack.status = "HELD"
			pack.holder_ref = person
	# Unallocated unit stock is the residual, so no unit.ammunition debit here.

func _finish_supply(unit: String, success: bool, reason: String = "") -> void:
	if not supply_jobs.has(unit):
		return
	var job: Dictionary = supply_jobs[unit]
	var quantity: float = 0.0
	if success and _supply_contact(job):
		quantity = minf(float(job.quantity), minf(float(_supply_point(unit, str(job.source_ref)).available), float(_supply_point(unit, str(job.target_ref)).room)))
		_adjust_custody(unit, str(job.source_ref), -quantity, str(job.id))
		_adjust_custody(unit, str(job.target_ref), quantity, str(job.id))
	job.status = "HANDED_OVER" if quantity > 0.000001 else "INTERRUPTED"
	job.delivered = quantity
	job.finished_at = _g()._state.time
	job.reason = reason
	if _g()._state.units.has(unit):
		_g()._state.units[unit].local_ammunition_handover = {"id": job.id, "source_ref": job.source_ref, "target_ref": job.target_ref, "requested": job.quantity, "delivered": quantity, "status": job.status, "finished_at": job.finished_at, "reason": reason}
	supply_jobs.erase(unit) # Retire before callbacks; stale tickets cannot repeat it.
	for person: String in job.handlers:
		var body: Dictionary = _g().participants._member(person)
		if body.get("supply_job_ref", "") == job.id:
			body.erase("supply_job_ref")
			if float(body.get("combat_busy_until", 0.0)) == float(job.due):
				body.combat_busy_until = _g()._state.time
	for person: String in job.people:
		var p: RefCounted = _g().participants
		var body: Dictionary = p._member(person)
		var action: Dictionary = p._actions.get(body.action_ref, {})
		if action.get("supply_ref", "") == job.id:
			action.status = job.status
			action.supply_result = job.duplicate(true)
			body.action_ref = ""
			body.state = "STATIONARY" if body.actionable else body.state
			p._emit(person, "local_ammunition_handover_result", str(job.id), {"delivered": quantity, "status": job.status, "reason": reason})
			rejoin_local_duty(person)
	_g()._emit(unit, "local_ammunition_handover_result", str(job.id), {"delivered": quantity, "status": job.status, "reason": reason})

func prepare(unit: Dictionary, plan: Dictionary) -> void:
	var g: RefCounted = _g()
	_sync_part_stock(unit)
	var held: float = 0.0
	var detailed: float = 0.0
	plan.weapon_components = []
	for actor: String in State.sorted_ids(weapons):
		var weapon: Dictionary = weapons[actor]
		if weapon.unit_ref != unit.id:
			continue
		# Prepared rounds are a claim inside current stock, including after external use.
		var part: Dictionary = actor_part(actor)
		if not part.is_empty():
			_clip_part_ready(part)
		else:
			weapon.ready = minf(float(weapon.ready), maxf(0.0, float(unit.ammunition) - held - _carried_total(str(unit.id))))
		held += float(weapon.ready)
		if weapon.mode == "RELEASED" or weapon.get("custody", "HELD") == "LEFT":
			continue
		var body: Dictionary = g.participants._member(actor)
		if g.participants._physical_unit(actor).id != unit.id or not body.actionable:
			_stop(weapon, "CEASE")
			detailed += float(body.health)
			continue
		if weapon.mode == "FIRE" and g._state.time >= float(weapon.get("until", INF)):
			_stop(weapon, "CEASE")
		var grouped: bool = StateDistance(g.participants.position(actor), g._space.xy(unit)) <= float(g.participants.rules.local_radius_km)
		if not part.is_empty():
			grouped = StateDistance(g.participants.position(actor), g._space.xy(part_source(unit, part))) <= float(g.participants.rules.local_radius_km)
		if weapon.mode == "GROUP" and grouped and body.actionable and str(body.action_ref).is_empty() and str(body.get("carrying_ref", "")).is_empty() and body.state not in ["ENTERING", "RETURNING", "RELOCATING", "LOCAL_MOVING", "LOCAL_ENTERING", "PART_MOVING", "PART_ENTERING"] and stock_contact(actor) and _free(unit) and float(weapon.ready) <= 0.000001 and weapon.status not in ["RELOADING", "AIMING"] and _reload_available(actor) > 0.000001 and _tickets.size() < 60:
			_start_reload(actor, "group_weapon_prepare")
		if grouped and not separated_actor(actor) and str(body.action_ref).is_empty() and str(body.get("carrying_ref", "")).is_empty() and body.state not in ["ENTERING", "RETURNING", "RELOCATING"] and float(body.get("combat_busy_until", 0.0)) <= g._state.time:
			detailed += float(body.health)
		if weapon.mode not in ["FIRE", "GROUP"] or weapon.status != "READY" or weapon.mode == "GROUP" and not grouped or not str(body.action_ref).is_empty() or body.state in ["ENTERING", "RETURNING", "RELOCATING", "PART_MOVING", "PART_ENTERING"] or body.state == "FOLLOWING" and (str(unit.spatial.edge) != "" or not unit.spatial.path.is_empty()) or not _free(unit) or float(weapon.ready) <= 0.000001 or part.is_empty() and float(unit.get("serviceable_equipment", unit.equipment)) < _equipment_claims(str(unit.id)):
			continue
		if not part.is_empty() and float(part.serviceable) < _part_weapon_equipment(part):
			continue
		if weapon.mode == "FIRE" and not visible(actor, str(weapon.get("target_ref", "")), true) or weapon.mode == "GROUP" and plan.posture in ["idle", "reserve", "withdraw"]:
			continue
		var rate: float = float(weapon.profile.rounds_per_minute) * float(body.health) * float(unit.readiness) * float(unit.cohesion) * (1.0 - float(unit.suppression)) * (1.0 - float(unit.fatigue) * 0.5)
		if not part.is_empty():
			rate = float(weapon.profile.rounds_per_minute) * float(body.health) * float(unit.readiness) * float(part.cohesion) * (1.0 - part_pressure(part)) * (1.0 - float(part.fatigue) * 0.5)
		rate *= 1.0 - g.participants.body_suppression(actor)
		plan.weapon_components.append({"actor_ref": actor, "target_ref": weapon.get("target_ref", ""), "group_controlled": weapon.mode == "GROUP", "rate": rate, "ready": weapon.ready,
			"lethality": weapon.profile.lethality, "pressure": weapon.profile.suppression_per_round})
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit.id:
			gun.ready = minf(float(gun.ready), maxf(0.0, float(unit.ammunition) - held - _carried_total(str(unit.id))))
			held += float(gun.ready)
	var crew: float = _gun_crew(str(unit.id))
	var available: float = float(plan.get("personal_ledger", {}).get("group_capacity", unit.effective))
	plan.commitment *= maxf(0.0, available - detailed - crew) / maxf(0.000001, available)
	var dedicated_equipment: float = 0.0
	for weapon: Dictionary in weapons.values():
		var remote_held: bool = weapon.get("holder_ref", "") == weapon.actor_ref and StateDistance(g.participants.position(str(weapon.actor_ref)), g._space.xy(unit)) > float(g.participants.rules.local_radius_km)
		if weapon.unit_ref == unit.id and (weapon.mode != "RELEASED" or float(weapon.ready) > 0.000001 or remote_held):
			dedicated_equipment += float(weapon.profile.equipment_share)
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit.id:
			dedicated_equipment += float(gun.profile.equipment_share)
	var remaining_equipment: float = maxf(0.0, float(unit.get("serviceable_equipment", unit.equipment)) - dedicated_equipment)
	var condition: float = float(unit.readiness) * float(unit.cohesion) * (1.0 - float(unit.fatigue) * 0.5) * (1.0 - float(unit.suppression))
	plan.commitment = minf(float(plan.commitment), remaining_equipment * condition)
	plan.unreserved_ammo = maxf(0.0, float(unit.ammunition) - held - _carried_total(str(unit.id)))
	plan.protected_equipment = protected_equipment(str(unit.id))
	plan.fire_order = fire_orders.get(unit.id, {}).duplicate(true)
	if manoeuvre_active(str(unit.id)):
		plan.action_parts = true
		plan.part_frontage = minf(float(unit.effective), float(unit.serviceable_equipment)) * float(unit.readiness)
		plan.commitment = 0.0
		plan.exposure = 0.0
		plan.personal_ledger.anonymous = 0.0
		plan.personal_ledger.exposure_capacity = 0.0
		plan.personal_ledger.group_capacity = 0.0
	if manoeuvre_active(str(unit.id)) and manoeuvres[unit.id].phase in ["REAR_MOVING", "REAR_RETURNING"]:
		# The residual part moves through the original unit route, without firing
		# its stationary anonymous quota. The front's owned components remain.
		plan.commitment = 0.0
	if plan.fire_order.get("fire_mode", "") in ["watch", "cease"]:
		plan.commitment = 0.0
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit.id and gun.state != "PACKED":
			plan.gun_deployed = true

func build_fire(unit: Dictionary, plan: Dictionary, contacts: Array, detected: Dictionary, anonymous_rates: Dictionary) -> void:
	plan.fire_components = []
	plan.fire_exhaustion_seconds = INF
	var order: Dictionary = plan.fire_order
	var selected: Array = []
	for target: String in contacts:
		if order.is_empty() or order.get("fire_mode", "") in ["watch", "cease"] or target_unit(target, plan.body_targets) == order.get("target_ref", "") or _g()._state.units.get(target, {}).get("spatial", {}).get("node", "") == order.get("node_ref", ""):
			selected.append(target)
	var total: float = 0.0
	for rate: Variant in anonymous_rates.values():
		total += float(rate)
	var rates: Dictionary = {}
	if order.is_empty() or order.get("fire_mode", "") in ["watch", "cease"]:
		rates = anonymous_rates.duplicate()
	elif not selected.is_empty():
		for target: String in selected:
			rates[target] = total / float(selected.size())
	# A known direction without a visible contact can be fired upon, but no hidden
	# unit is selected and no casualty is manufactured.
	elif order.get("fire_mode", "") == "suppress":
		total = float(plan.commitment) * float(unit.weapon.rounds_per_minute) * 0.5
	else:
		total = 0.0
	if manoeuvre_active(str(unit.id)):
		total = 0.0
		build_part_fire(unit, plan, contacts, detected)
	if total > 0.0 and float(plan.unreserved_ammo) > 0.000001:
		plan.fire_components.append({"actor_ref": "", "rate": total, "ready": plan.unreserved_ammo, "targets": rates,
			"lethality": float(unit.weapon.lethality) * (0.5 if order.get("fire_mode", "") in ["suppress", "cover_move"] else 1.0),
			"pressure": float(unit.get("supply_capability", {}).get("suppression_per_round", 0.12)) * (1.5 if order.get("fire_mode", "") in ["suppress", "cover_move"] else 1.0)})
	for component: Dictionary in plan.weapon_components:
		var actor: String = str(component.actor_ref)
		var weapon: Dictionary = weapons[actor]
		var source: Dictionary = _body_source(actor, float(weapon.profile.range_km))
		var subjects: Array[String] = []
		if component.get("group_controlled", false):
			if order.get("fire_mode", "") in ["watch", "cease"]:
				continue
			if order.get("target_ref", "") != "" and not _component_targets(source, str(order.target_ref), plan).is_empty():
				subjects.append(str(order.target_ref))
			for reference: String in contacts:
				var subject: String = target_unit(reference, plan.body_targets)
				if (order.is_empty() or reference in selected) and subject not in subjects and not _component_targets(source, subject, plan).is_empty():
					subjects.append(subject)
			if subjects.is_empty():
				continue
			if weapon.get("group_target", "") != subjects[0] and _tickets.size() < 60:
				weapon.group_target = subjects[0]
				weapon.revision += 1
				weapon.status = "AIMING"
				_queue("AIM", actor, "group_weapon_aim", float(weapon.profile.aim_seconds), {"revision": weapon.revision})
				continue
			if weapon.profile.role == "precision":
				subjects = [subjects[0]]
		else:
			subjects = [str(component.target_ref)]
		var owned: Dictionary = component.duplicate(true)
		owned.targets = {}
		owned.rate = 0.0
		for subject: String in subjects:
			var factors: Dictionary = _component_targets(source, subject, plan)
			for reference: String in factors:
				var rate: float = float(component.rate) * float(factors[reference]) / float(subjects.size())
				owned.targets[reference] = rate
				owned.rate += rate
				if reference not in contacts:
					contacts.append(reference)
					detected[reference] = float(factors[reference])
		if float(owned.rate) <= 0.0:
			continue
		if order.get("fire_mode", "") in ["suppress", "cover_move"] or manoeuvre_active(str(unit.id)) and weapon.get("fire_owner_ref", "") == manoeuvres[unit.id].id:
			owned.lethality *= 0.5
			owned.pressure *= 1.5
		plan.fire_components.append(owned)
	plan.rounds = 0.0
	for component: Dictionary in plan.fire_components:
		plan.rounds += float(component.rate)
		plan.fire_exhaustion_seconds = minf(float(plan.fire_exhaustion_seconds), float(component.ready) / float(component.rate) * 60.0)

func spend(unit: Dictionary, plan: Dictionary, minutes: float) -> float:
	var spent: float = 0.0
	plan.fire_doses = {}
	plan.part_spent = {}
	for component: Dictionary in plan.fire_components:
		var used: float = minf(float(component.ready), minf(float(component.rate) * minutes, maxf(0.0, float(unit.ammunition) - spent)))
		spent += used
		if component.actor_ref != "":
			var weapon: Dictionary = weapons[component.actor_ref]
			weapon.ready = maxf(0.0, float(weapon.ready) - used)
			weapon.spent += used
			if float(weapon.ready) <= 0.000001:
				weapon.status = "EMPTY"
		var part: Dictionary = actor_part(str(component.actor_ref)) if component.actor_ref != "" else manoeuvres.get(unit.id, {}).get("parts", {}).get(component.get("part_key", ""), {})
		if not part.is_empty():
			part.ammunition = maxf(0.0, float(part.ammunition) - used)
			part.ammo_spent += used
			plan.part_spent[part.id] = float(plan.part_spent.get(part.id, 0.0)) + used
		for target: String in component.targets:
			var amount: float = used * float(component.targets[target]) / float(component.rate)
			var dose: Dictionary = plan.fire_doses.get(target, {"rounds": 0.0, "lethal": 0.0, "pressure": 0.0})
			dose.rounds += amount
			dose.lethal += amount * float(component.lethality)
			dose.pressure += amount * float(component.pressure)
			plan.fire_doses[target] = dose
	return spent

func validate_squad(actor: String, unit_id: String, values: Dictionary) -> Dictionary:
	if values.has("rescue_order"):
		if values.size() != 2 or not values.get("carrier_ref") is String or not values.rescue_order is Dictionary or _g().participants._units.get(values.carrier_ref, "") != unit_id:
			return _reject("existing_owned_helper_and_explicit_rescue_order_required")
		return _g().participants.validate_rescue(str(values.carrier_ref), values.rescue_order, actor)
	if values.has("ammo_action"):
		return validate_ammunition(actor, unit_id, values, true)
	var g: RefCounted = _g()
	if g._state.public_pending():
		return g._state.pending_view()
	if values.has("manoeuvre_action"):
		return validate_manoeuvre(actor, unit_id, values)
	if manoeuvre_active(unit_id) and values.get("fire_mode", "") not in ["watch", "cease", "resume"]:
		return _reject("existing_road_parts_require_stop_or_regroup_before_reassignment")
	if manoeuvre_active(unit_id) and values.get("fire_mode", "") == "resume" and _tickets.size() > 52:
		return _reject("finite_part_fire_preparation_capacity")
	if _tickets.size() > 60 or not g._state.units.has(unit_id) or not _free(g._state.units[unit_id]) or values.get("fire_mode", "") not in FIRE_MODES:
		return _reject("available_squad_and_fire_mode_required")
	var mode: String = str(values.fire_mode)
	var direction: String = str(values.get("node_ref", ""))
	if mode in ["concentrate", "suppress", "cover_move"]:
		if not _positive(values.get("seconds", 60.0)) or float(values.get("seconds", 60.0)) > 300.0:
			return _reject("bounded_fire_duration_required")
		var target: String = str(values.get("target_ref", ""))
		var node: String = str(values.get("node_ref", ""))
		var known: bool = g._known.get(actor, {}).has(node)
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).get("entries", []):
			if claim.subject_ref == target and claim.fact_kind in ["air_contact", "ground_contact"] and float(claim.reliability) > 0.0:
				known = true
				if direction == "":
					direction = str(claim.claimed_value.get("node_ref", ""))
		if not known:
			return _reject("known_fire_direction_or_received_contact_required")
		if mode == "suppress":
			var actual: Dictionary = g._state.units[unit_id]
			if not g._space._nodes.has(direction) or StateDistance(g._space.xy(actual), g._space._nodes[direction].xy) > float(actual.weapon.range_km) or not g._space._lanes.get(str(actual.spatial.node) + ":" + direction, {}).get("fire", false):
				return _reject("suppression_direction_outside_actual_weapon_geometry")
		if mode == "cover_move":
			if not values.get("movers") is Array or values.movers.is_empty() or values.movers.size() > 4 or float(g._state.units[unit_id].effective) <= float(values.movers.size()):
				return _reject("existing_partial_moving_group_and_remaining_covering_capacity_required")
			var seen: Dictionary = {}
			var moving_health: float = 0.0
			for person: Variant in values.movers:
				if not person is String or seen.has(person) or g.participants._units.get(person, "") != unit_id or not g.participants.validate_action(person, "take_cover").ok:
					return _reject("local_movers_must_have_actual_known_nearby_cover")
				seen[person] = true
				moving_health += float(g.participants._member(person).health)
			var actual: Dictionary = g._state.units[unit_id]
			var crew: float = _gun_crew(unit_id)
			if float(actual.effective) - moving_health - crew <= 0.000001 or _unreserved(actual) <= 0.000001 or float(actual.get("serviceable_equipment", actual.equipment)) - _equipment_claims(unit_id) <= 0.000001:
				return _reject("actual_remaining_covering_personnel_equipment_and_ammunition_required")
	return {"ok": true, "direction_node": direction}

func squad(actor: String, unit: String, id: String, values: Dictionary) -> Dictionary:
	if values.has("rescue_order"):
		var rescue_check: Dictionary = validate_squad(actor, unit, values)
		if not rescue_check.ok:
			return rescue_check
		return _g().participants.apply_rescue(str(values.carrier_ref), id, values.rescue_order, actor)
	if values.has("ammo_action"):
		return ammunition_action(actor, unit, id, values, true)
	var valid: Dictionary = validate_squad(actor, unit, values)
	if not valid.ok:
		return valid
	if values.has("manoeuvre_action"):
		return manoeuvre(actor, unit, id, values)
	if values.fire_mode == "resume":
		if manoeuvre_active(unit):
			_set_rear_fire(manoeuvres[unit])
			for key: String in ["front", "rear"]:
				if manoeuvres[unit].parts[key].role != "MOVING":
					_guard_part(manoeuvres[unit], key)
		else:
			fire_orders.erase(unit)
	else:
		if values.fire_mode in ["cease", "watch"]:
			for weapon: Dictionary in weapons.values():
				if weapon.unit_ref == unit and weapon.mode == "FIRE":
					_stop(weapon, "CEASE")
			for gun: Dictionary in guns.values():
				if gun.unit_ref == unit and gun.state in ["FIRING", "RELOADING"] and int(gun.get("remaining", 0)) > 0:
					gun.revision += 1
					gun.state = "READY"
					gun.reason = "unit_cease_order_received"
		fire_orders[unit] = values.duplicate(true)
		if values.fire_mode == "suppress":
			fire_orders[unit].node_ref = valid.direction_node
		fire_orders[unit].issuer = actor
		fire_orders[unit].input_ref = id
		if values.fire_mode in ["concentrate", "suppress", "cover_move"]:
			_queue("SQUAD_END", unit, id, float(values.get("seconds", 60.0)), {"input_ref": id})
		if values.fire_mode == "cover_move":
			fire_orders[unit].moving = {}
			fire_orders[unit].phase = "MOVING_UNDER_EXISTING_FIRE"
			for person: String in values.movers:
				_g().participants.apply_action(person, id + "_" + person, "take_cover")
				fire_orders[unit].moving[person] = {"action_ref": _g().participants._member(person).action_ref, "status": "PENDING", "at": _g()._state.time}
	_g()._state.wake(str(_g()._state.units[unit].area_id))
	return {"ok": true}

func manoeuvre_active(unit: String) -> bool:
	return manoeuvres.has(unit) and manoeuvres[unit].phase not in ["COMPLETE", "REGROUPED"]

func actor_part(actor: String) -> Dictionary:
	if _g().participants._units.has(actor) and _g().participants._member(actor).get("local_duty", false):
		return {}
	return roster_part(actor)

func roster_part(actor: String) -> Dictionary:
	var unit: String = str(_g().participants._units.get(actor, ""))
	if manoeuvre_active(unit):
		for part: Dictionary in manoeuvres[unit].parts.values():
			if actor in part.members:
				return part
	return {}

func separated_actor(actor: String) -> bool:
	if _g().participants._units.has(actor) and _g().participants._member(actor).get("local_duty", false):
		return true
	if not actor_part(actor).is_empty():
		return true
	if not _g().participants._units.has(actor):
		return false
	var body: Dictionary = _g().participants.body_spatial(actor)
	var unit: Dictionary = _g().participants._physical_unit(actor)
	return str(body.get("local_edge", "")) != "" or _g()._space.local_place(body) != _g()._space.local_place(unit.spatial)

func parent_presence(unit: Dictionary) -> float:
	if manoeuvre_active(str(unit.id)):
		return 0.0
	var ledger: Dictionary = unit.get("gameplay_personnel", {})
	var result: float = float(ledger.get("anonymous", unit.effective))
	for person: String in ledger.get("members", {}):
		if not separated_actor(person) and StateDistance(_g().participants.position(person), _g()._space.xy(unit)) <= float(_g().participants.rules.local_radius_km):
			result += float(_g().participants._member(person).health)
	return result

func has_separated_bodies(unit: String) -> bool:
	for person: String in _g()._state.units[unit].get("gameplay_personnel", {}).get("members", {}):
		if separated_actor(person):
			return true
	return false

func part_source(unit: Dictionary, part: Dictionary) -> Dictionary:
	# Transient geometry/capacity view; no second unit or stock account.
	var view: Dictionary = unit.duplicate()
	view.spatial = part.spatial.duplicate(true)
	view.effective = part_capacity(part)
	view.equipment = part.equipment
	view.serviceable_equipment = part.serviceable
	view.fatigue = part.fatigue
	view.cohesion = part.cohesion
	view.suppression = part_pressure(part)
	return view

func part_capacity(part: Dictionary) -> float:
	var result: float = float(part.anonymous)
	for actor: String in part.members:
		if _g().participants._units.get(actor, "") == part.unit_ref and not _g().participants._member(actor).get("local_duty", false):
			result += float(_g().participants._member(actor).health)
	return result

func part_pressure(part: Dictionary) -> float:
	return float(part.suppression) * exp(-_g()._lod._kernel.SUPPRESSION_DECAY * maxf(0.0, _g()._state.time - float(part.pressure_at)) / 60.0)

static func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

func _part_spec(unit: Dictionary, values: Dictionary) -> Dictionary:
	var ledger: Dictionary = unit.get("gameplay_personnel", {"anonymous": unit.effective, "members": {}})
	var specs: Dictionary = {}
	if values.has("parts"):
		if not values.parts is Dictionary or values.parts.size() != 2 or not values.parts.has("front") or not values.parts.has("rear"):
			return _reject("two_explicit_front_rear_parts_required")
		specs = values.parts.duplicate(true)
	else:
		if not values.get("movers") is Array or values.movers.is_empty() or values.movers.size() > 4:
			return _reject("two_parts_or_existing_named_movers_required")
		var rear: Array = []
		for person: String in ledger.members:
			if person not in values.movers:
				rear.append(person)
		specs = {"front": {"members": values.movers.duplicate(), "anonymous": 0.0}, "rear": {"members": rear, "anonymous": ledger.anonymous}}
	var seen: Dictionary = {}
	var anonymous: float = 0.0
	var named_equipment: Dictionary = {"front": 0.0, "rear": 0.0}
	var ready: Dictionary = {"front": 0.0, "rear": 0.0}
	var capacities: Dictionary = {}
	for key: String in ["front", "rear"]:
		if not specs[key] is Dictionary:
			return _reject("part_allocation_required")
		var spec: Dictionary = specs[key]
		for field: String in spec:
			if field not in ["members", "anonymous", "ammunition", "equipment"]:
				return _reject("unsupported_part_allocation_field")
		if not spec.get("members", []) is Array or spec.get("members", []).size() > 4 or not _nonnegative(spec.get("anonymous", 0.0)):
			return _reject("bounded_existing_members_and_nonnegative_capacity_required")
		spec.members = spec.get("members", []).duplicate()
		spec.anonymous = float(spec.get("anonymous", 0.0))
		anonymous += float(spec.anonymous)
		capacities[key] = float(spec.anonymous)
		for person: Variant in spec.members:
			if not person is String or seen.has(person) or not ledger.members.has(person):
				return _reject("unique_members_from_original_capacity_required")
			seen[person] = true
			capacities[key] += float(ledger.members[person].health)
			var weapon: Dictionary = weapons.get(person, {})
			if not weapon.is_empty():
				if weapon.get("holder_ref", "") != person or weapon.unit_ref != unit.id:
					return _reject("actual_carried_weapon_relationship_required")
				named_equipment[key] += float(weapon.profile.equipment_share)
				ready[key] += float(weapon.ready)
		if float(capacities[key]) <= 0.000001:
			return _reject("each_part_requires_actual_remaining_capacity")
	if seen.size() != ledger.members.size() or absf(anonymous - float(ledger.anonymous)) > 0.000001:
		return _reject("partition_current_capacity_without_recreating_losses")
	var spare_equipment: float = maxf(0.0, float(unit.equipment) - float(named_equipment.front) - float(named_equipment.rear))
	var spare_serviceable: float = maxf(0.0, float(unit.serviceable_equipment) - float(named_equipment.front) - float(named_equipment.rear))
	var ratio: float = float(capacities.front) / maxf(0.000001, float(unit.effective))
	var front_eq: Variant = specs.front.get("equipment", spare_equipment * ratio)
	var rear_eq: Variant = specs.rear.get("equipment", spare_equipment - float(front_eq) if _nonnegative(front_eq) else -1.0)
	if not _nonnegative(front_eq) or not _nonnegative(rear_eq) or absf(float(front_eq) + float(rear_eq) - spare_equipment) > 0.000001:
		return _reject("anonymous_equipment_must_partition_actual_unassigned_equipment")
	var free_ammo: float = maxf(0.0, float(unit.ammunition) - float(ready.front) - float(ready.rear))
	var front_ammo: Variant = specs.front.get("ammunition", float(ready.front) + free_ammo * ratio)
	var rear_ammo: Variant = specs.rear.get("ammunition", float(unit.ammunition) - float(front_ammo) if _nonnegative(front_ammo) else -1.0)
	if not _nonnegative(front_ammo) or not _nonnegative(rear_ammo) or float(front_ammo) < float(ready.front) or float(rear_ammo) < float(ready.rear) or absf(float(front_ammo) + float(rear_ammo) - float(unit.ammunition)) > 0.000001:
		return _reject("part_ammunition_includes_personal_ready_and_partitions_stock")
	for key: String in ["front", "rear"]:
		var share: float = float(front_eq if key == "front" else rear_eq)
		specs[key].equipment = share + float(named_equipment[key])
		specs[key].serviceable = (spare_serviceable * share / spare_equipment if spare_equipment > 0.000001 else 0.0) + float(named_equipment[key])
		specs[key].ammunition = float(front_ammo if key == "front" else rear_ammo)
	return {"ok": true, "parts": specs}

func _manoeuvre_edges(order: Dictionary) -> Dictionary:
	return _g()._space._local_edges if order.get("travel_kind", "ROAD") == "LOCAL" else _g()._space._edges

func _part_place(part: Dictionary, local: bool) -> String:
	return _g()._space.local_place(part.spatial) if local else str(part.spatial.node)

func _part_arrived(order: Dictionary, part: Dictionary) -> bool:
	return _g()._space.local_arrived(part.spatial, str(part.destination_node)) if order.get("travel_kind", "ROAD") == "LOCAL" else str(part.spatial.edge) == "" and part.spatial.node == part.destination_node

func _validate_manoeuvre_route(actor: String, unit: Dictionary, values: Dictionary) -> Dictionary:
	var g: RefCounted = _g()
	var local: bool = values.has("local_path")
	if local and values.has("path"):
		return _reject("one_declared_local_or_road_path_required")
	var path: Variant = values.get("local_path", values.get("path"))
	if not path is Array or path.is_empty() or path.size() > 4:
		return _reject("at_most_four_explicit_movement_legs_required")
	var destination: String = str(values.get("destination_ref" if local else "destination_node", ""))
	var known_key: String = "local:" + destination if local else destination
	if path not in g._known.get(actor, {}).get(known_key, []):
		return _reject("commander_known_route_required")
	if local:
		if str(unit.spatial.get("local_edge", "")) != "" or g._space.local_path_end(g._space.local_place(unit.spatial), path) != destination:
			return _reject("explicit_local_access_and_connected_path_required")
		return {"ok": true}
	if str(unit.spatial.get("local_edge", "")) != "" or g._space.local_place(unit.spatial) != "node:" + str(unit.spatial.node):
		return _reject("actual_local_regroup_at_road_access_required")
	var node: String = str(unit.spatial.node)
	var cells: Array[String] = g._space.scope_cells(str(unit.area_id))
	for edge_id: Variant in path:
		if not edge_id is String or not g._space._edges.has(edge_id):
			return _reject("existing_road_edge_required")
		var edge: Dictionary = g._space._edges[edge_id]
		if node not in [edge.from, edge.to] or edge.kind not in ["road", "bridge"] or "FOOT" not in edge.modes:
			return _reject("connected_declared_foot_road_required")
		node = str(edge.to if node == edge.from else edge.from)
		if not g._known.get(actor, {}).has(node) or str(g._space._nodes[node].cell) not in cells:
			return _reject("known_endpoint_in_existing_resolution_scope_required")
	return {"ok": true} if node == destination else _reject("road_manoeuvre_destination_mismatch")

func validate_manoeuvre(actor: String, unit_id: String, values: Dictionary) -> Dictionary:
	if not manoeuvre_active(unit_id) and (_carried_total(unit_id) > 0.000001 or supply_jobs.has(unit_id)):
		return _reject("handover_existing_local_cargo_before_new_capacity_partition")
	var g: RefCounted = _g()
	var action: String = str(values.get("manoeuvre_action", ""))
	if not g._state.knows_unit(unit_id) or not g.operations.permits_ground_fire(unit_id, actor):
		return _reject("current_squad_executor_required")
	if action in ["stop", "resume", "regroup"]:
		if values.size() != 1 or not manoeuvre_active(unit_id):
			return _reject("existing_road_manoeuvre_required")
		if action != "stop" and manoeuvres[unit_id].phase != "STOPPED":
			return _reject("stop_current_movement_before_resuming_or_regrouping")
		if action != "stop" and _tickets.size() > 56:
			return _reject("finite_action_event_capacity")
		if action != "stop":
			for part: Dictionary in manoeuvres[unit_id].parts.values():
				for person: String in part.members:
					if _member_conflict(person, manoeuvres[unit_id]):
						return _reject("existing_personal_or_body_duty_must_finish_before_group_resume")
		return {"ok": true}
	if action not in ["advance", "withdraw"] or manoeuvre_active(unit_id) or manoeuvres.size() >= 4 and not manoeuvres.has(unit_id):
		return _reject("one_bounded_two_part_task_per_existing_squad")
	var unit: Dictionary = g._state.units[unit_id] if g._state.units.has(unit_id) else g._lod.preview_leaf(unit_id)
	if not _free(unit) or movement_blocked(unit_id) or unit.spatial.mode != "FOOT" or str(unit.spatial.edge) != "" or g._state.missions[unit.mission_id].status != "active":
		return _reject("stationary_free_foot_squad_required")
	if unit.get("supply_capability", {}).get("fuel_dependent", false):
		return _reject("fuel_dependent_equipment_outside_foot_part_carrying")
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit_id:
			return _reject("configured_gun_crew_outside_two_part_foot_allocation")
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == unit_id and (weapon.get("custody", "HELD") != "HELD" or weapon.status in ["AIMING", "RELOADING"]):
			return _reject("resolve_weapon_custody_or_preparation_before_distribution")
	var route_valid: Dictionary = _validate_manoeuvre_route(actor, unit, values)
	if not route_valid.ok:
		return route_valid
	var allocation: Dictionary = _part_spec(unit, values)
	if not allocation.ok:
		return allocation
	var duration: Variant = values.get("seconds", 600.0)
	if not _positive(duration) or float(duration) > 3600.0 or _tickets.size() > 52:
		return _reject("bounded_deadline_and_existing_event_capacity_required")
	for person: String in unit.get("gameplay_personnel", {}).get("members", {}):
		var body: Dictionary = g.participants._member(person)
		if not g.participants.can_intend(person) or body.has("command_post") or not str(body.action_ref).is_empty() or float(body.get("combat_busy_until", 0.0)) > g._state.time or not str(body.get("carrying_ref", "")).is_empty() or StateDistance(g.participants.position(person), g._space.xy(unit)) > 0.000001:
			return _reject("actual_free_members_at_start_without_other_body_work_required")
	if float(unit.mobility) <= 0.0 or float(unit.readiness) <= 0.0 or float(unit.serviceable_equipment) < _equipment_claims(unit_id):
		return _reject("actual_movement_and_equipment_capacity_required")
	var target: String = str(values.get("target_ref", ""))
	if not target.is_empty():
		var known: bool = false
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).get("entries", []):
			if claim.subject_ref == target and claim.fact_kind in ["ground_contact", "air_contact"] and float(claim.reliability) > 0.0:
				known = true
		if not known:
			return _reject("received_or_observed_cover_target_required")
	if values.get("require_cover", not target.is_empty()) and target.is_empty():
		return _reject("fire_cover_requires_an_identified_known_target")
	return allocation

func manoeuvre(actor: String, unit_id: String, id: String, values: Dictionary) -> Dictionary:
	var g: RefCounted = _g()
	var action: String = str(values.manoeuvre_action)
	if action == "stop":
		_stop_manoeuvre(unit_id, "received_stop", id)
	elif action in ["resume", "regroup"]:
		var order: Dictionary = manoeuvres[unit_id]
		order.revision += 1
		order.last_command_ref = id
		order.reason = ""
		order.returning = action == "regroup" or bool(order.returning)
		if action == "regroup":
			order.supply_only = false
		order.phase = "RETURN_PREPARE" if order.returning else "PREPARE"
		if not order.returning and g._state.time >= float(order.deadline):
			order.phase = "STOPPED"
			order.reason = "original_deadline_expired"
		else:
			_prepare_manoeuvre(order)
	else:
		var unit: Dictionary = g._state.units[unit_id]
		var local: bool = values.has("local_path")
		var path: Array = values.get("local_path", values.get("path", []))
		var destination: String = str(values.get("destination_ref" if local else "destination_node", ""))
		var allocation: Dictionary = _part_spec(unit, values)
		if not allocation.ok:
			return allocation
		if not unit.has("gameplay_personnel"):
			unit.gameplay_personnel = {"anonymous": unit.effective, "members": {}}
		var tail: Array = unit.spatial.path.duplicate()
		var prefix: bool = not local and tail.size() >= path.size() and tail.slice(0, path.size()) == path
		var order: Dictionary = {"id": id, "unit_ref": unit_id, "issuer": actor, "mission_ref": unit.mission_id,
			"revision": 0, "phase": "PREPARE", "kind": action, "travel_kind": "LOCAL" if local else "ROAD", "path": path.duplicate(), "leg_index": 0,
			"origin_node": unit.spatial.node, "leg_from": unit.spatial.node, "leg_to": "", "edge_ref": "",
			"destination_node": destination, "started_at": g._state.time, "deadline": g._state.time + float(values.get("seconds", 600.0)),
			"parts": {}, "lead_part": "front", "moving_part": "", "guard_part": "rear", "stock_part": "rear",
			"movers": [], "roster": State.sorted_ids(unit.gameplay_personnel.members), "moving": {},
			"target_ref": str(values.get("target_ref", "")), "require_cover": bool(values.get("require_cover", not str(values.get("target_ref", "")).is_empty())),
			"returning": false, "reason": "", "check_ref": "", "continuation_path": tail.slice(path.size()) if prefix else [],
			"prior_path": tail, "last_command_ref": id}
		for key: String in ["front", "rear"]:
			var spec: Dictionary = allocation.parts[key]
			var spatial: Dictionary = unit.spatial.duplicate(true)
			spatial.path = []
			order.parts[key] = {"id": unit_id + ":" + id + ":" + key, "unit_ref": unit_id, "source_ref": unit_id, "members": spec.members,
				"anonymous": spec.anonymous, "initial_anonymous": spec.anonymous, "anonymous_loss": 0.0,
				"equipment": spec.equipment, "serviceable": spec.serviceable, "equipment_lost": 0.0,
				"ammunition": spec.ammunition, "ammo_spent": 0.0, "spatial": spatial, "role": "WATCH", "action_ref": "",
				"revision": 0, "fatigue": unit.fatigue, "cohesion": unit.cohesion, "suppression": unit.suppression, "pressure_at": g._state.time,
				"ready_at": g._state.time, "distance_moved": 0.0, "movement_seconds": 0.0, "settled_at": g._state.time}
			for person: String in spec.members:
				var body: Dictionary = g.participants._member(person)
				body.xy = g.participants.position(person)
				body.state = "STATIONARY"
				body.anchor_node = unit.spatial.node
				body.part_ref = order.parts[key].id
		order.movers = order.roster.duplicate()
		manoeuvres[unit_id] = order
		unit.spatial.path.clear()
		_queue("MANOEUVRE_DEADLINE", unit_id, id, float(values.get("seconds", 600.0)), {"manoeuvre_ref": id})
		_prepare_manoeuvre(order)
	_manoeuvre_feedback(manoeuvres[unit_id], "road_manoeuvre_command")
	return {"ok": true}

func _prepare_manoeuvre(order: Dictionary) -> void:
	var g: RefCounted = _g()
	if order.edge_ref == "":
		order.edge_ref = order.path[int(order.leg_index)]
		order.leg_from = _part_place(order.parts[order.lead_part], order.get("travel_kind", "ROAD") == "LOCAL")
		var edge: Dictionary = _manoeuvre_edges(order)[order.edge_ref]
		order.leg_to = edge.to if edge.from == order.leg_from else edge.from
	_set_rear_fire(order)
	var wait: float = 5.0
	for part: Dictionary in order.parts.values():
		part.role = "PREPARING"
		part.ready_at = g._state.time + 5.0
		if order.get("supply_only", false) and part.id != order.parts[order.lead_part].id:
			continue # Stationary patients/other duties are not moved by this carrier.
		for person: String in part.members:
			if not _g().participants.can_intend(person) or not str(g.participants._member(person).action_ref).is_empty():
				_stop_manoeuvre(str(order.unit_ref), "member_has_other_body_duty", str(order.id))
				return
			if StateDistance(g.participants.position(person), g._space.xy(part_source(g._state.units[order.unit_ref], part))) > 0.000001:
				_stop_manoeuvre(str(order.unit_ref), "member_not_at_own_part_position", str(order.id))
				return
			if weapons.has(person):
				var weapon: Dictionary = weapons[person]
				weapon.group_assignment_ref = order.id
				_stop(weapon, "CEASE")
				if order.require_cover and not order.returning and float(weapon.ready) <= 0.000001 and stock_contact(person) and _reload_available(person) > 0.000001:
					_start_reload(person, str(order.id))
					wait = maxf(wait, float(weapon.profile.reload_seconds) + 1.0)
	order.prepare_until = g._state.time + wait
	_schedule_manoeuvre(order, wait)

func stock_contact(actor: String) -> bool:
	var part: Dictionary = actor_part(actor)
	var unit: Dictionary = _g().participants._physical_unit(actor)
	var source: Dictionary = unit if part.is_empty() else part_source(unit, part)
	if part.is_empty():
		var body: Dictionary = _g().participants.body_spatial(actor)
		if str(body.get("local_edge", "")) != "" or _g()._space.local_place(body) != _g()._space.local_place(source.spatial):
			return false
	var stopped: bool = str(source.spatial.edge) == "" if part.is_empty() else part.role != "MOVING"
	return stopped and source.spatial.path.is_empty() and StateDistance(_g().participants.position(actor), _g()._space.xy(source)) <= float(_g().participants.rules.local_radius_km)

func _part_ready(part: Dictionary) -> float:
	var result: float = 0.0
	for person: String in part.members:
		if weapons.has(person) and weapons[person].unit_ref == part.unit_ref and not _g().participants._member(person).get("local_duty", false):
			result += float(weapons[person].ready)
	return result

func _reload_available(actor: String) -> float:
	var part: Dictionary = actor_part(actor)
	var result: float = _carried_amount(actor)
	if stock_contact(actor):
		result += _unreserved(_g().participants._physical_unit(actor)) if part.is_empty() else maxf(0.0, float(part.ammunition) - _part_ready(part))
	return result

func _schedule_manoeuvre(order: Dictionary, seconds: float = 1.0) -> void:
	if _tickets.has(order.check_ref) and _tickets[order.check_ref].get("revision", -1) == order.revision or _tickets.size() >= 60:
		return
	_queue("MANOEUVRE_CHECK", str(order.unit_ref), str(order.id), seconds, {"manoeuvre_ref": order.id, "revision": order.revision})
	order.check_ref = "tactical_%d" % _serial

func _set_rear_fire(order: Dictionary) -> void:
	fire_orders[order.unit_ref] = {"fire_mode": "concentrate" if order.require_cover else "watch", "target_ref": order.target_ref,
		"input_ref": order.id, "issuer": order.issuer, "manoeuvre_ref": order.id}

func _guard_part(order: Dictionary, key: String) -> void:
	var g: RefCounted = _g()
	var part: Dictionary = order.parts[key]
	part.role = "FIRE" if order.require_cover and not order.returning else "WATCH"
	part.ready_at = g._state.time + 5.0
	for person: String in part.members:
		if not weapons.has(person) or _g().participants._member(person).get("local_duty", false) or not _g().participants.can_intend(person) or not str(_g().participants._member(person).action_ref).is_empty():
			continue
		var weapon: Dictionary = weapons[person]
		if weapon.get("group_assignment_ref", "") != order.id:
			continue
		_stop(weapon, "CEASE")
		if part.role == "FIRE":
			weapon.mode = "FIRE"
			weapon.fire_owner_ref = order.id
			weapon.target_ref = order.target_ref
			weapon.until = order.deadline
			weapon.status = "AIMING"
			_queue("AIM", person, str(order.id), float(weapon.profile.aim_seconds), {"revision": weapon.revision})
			part.ready_at = maxf(float(part.ready_at), g._state.time + float(weapon.profile.aim_seconds))

func _start_part(order: Dictionary, key: String, second: bool) -> void:
	var g: RefCounted = _g()
	var part: Dictionary = order.parts[key]
	var destination: String = str(order.leg_from if order.returning else order.leg_to)
	part.revision += 1
	part.action_ref = str(part.id) + ":r%d" % int(part.revision)
	part.destination_node = destination
	part.role = "MOVING"
	if order.get("travel_kind", "ROAD") == "LOCAL":
		part.spatial.local_returning = order.returning and str(part.spatial.get("local_edge", "")) != ""
		part.spatial.local_path = [order.edge_ref] if str(part.spatial.get("local_edge", "")) == "" and _g()._space.local_place(part.spatial) != destination else []
		part.spatial.erase("entered_site_ref")
	else:
		part.spatial.returning = order.returning and str(part.spatial.edge) != ""
		part.spatial.path = [order.edge_ref] if str(part.spatial.edge) == "" and part.spatial.node != destination else []
	part.started_at = g._state.time
	order.moving_part = key
	order.guard_part = "rear" if key == "front" else "front"
	order.phase = ("REAR_RETURNING" if second else "FRONT_RETURNING") if order.returning else ("REAR_MOVING" if second else "FRONT_MOVING")
	order.moving = {}
	for person: String in part.members:
		var body: Dictionary = g.participants._member(person)
		if weapons.has(person):
			_stop(weapons[person], "CEASE")
		body.part_action_ref = part.action_ref
		body.part_revision = part.revision
		body.combat_revision = int(body.get("combat_revision", 0)) + 1
		body.state = "PART_MOVING"
		body.cover_ref = ""
		body.erase("entered_site_ref")
		order.moving[person] = {"status": "PENDING", "action_ref": part.action_ref}
	_manoeuvre_feedback(order, "road_part_started")
	if _part_arrived(order, part):
		_schedule_manoeuvre(order)

func _enter_part(order: Dictionary, part: Dictionary) -> bool:
	var g: RefCounted = _g()
	if order.get("travel_kind", "ROAD") != "LOCAL" or not g._space._local_sites.has(str(part.destination_node)):
		return false
	if not g._space.local_enterable(part.spatial):
		_stop_manoeuvre(str(order.unit_ref), "actual_position_not_usable", str(order.id))
		return true
	part.role = "ENTERING"
	for person: String in part.members:
		var body: Dictionary = g.participants._member(person)
		body.state = "PART_ENTERING"
		body.part_entry_ref = part.id
	part.ready_at = g._state.time + float(g._space._local_sites[part.destination_node].enter_seconds)
	order.phase = "REAR_ENTERING" if str(order.phase).begins_with("REAR") else "FRONT_ENTERING"
	_schedule_manoeuvre(order, float(part.ready_at) - g._state.time)
	_manoeuvre_feedback(order, "local_position_entry_started")
	return true

func _adopt_part_arrival(order: Dictionary, second: bool) -> void:
	if order.get("supply_only", false) and not order.returning:
		if int(order.leg_index) + 1 < order.path.size():
			order.leg_index += 1
			order.edge_ref = ""
			order.phase = "PREPARE"
			_prepare_manoeuvre(order)
		else:
			_stop_manoeuvre(str(order.unit_ref), "local_ammunition_carrier_arrived_requires_handover", str(order.last_command_ref))
		return
	if second:
		_finish_manoeuvre(order, bool(order.returning))
	else:
		_guard_part(order, str(order.lead_part))
		order.phase = "FRONT_PREPARING_FIRE"
		_schedule_manoeuvre(order, maxf(1.0, float(order.parts[order.lead_part].ready_at) - _g()._state.time))

func _local_contested(order: Dictionary) -> bool:
	var g: RefCounted = _g()
	var site: Dictionary = g._space._local_sites.get(str(order.leg_to if not order.returning else order.leg_from), {})
	if site.is_empty():
		return false
	var unit: Dictionary = g._state.units[order.unit_ref]
	for id: String in g._space.combat_ids(str(unit.area_id)):
		var other: Dictionary = g._state.units[id]
		if other.side == unit.side or float(other.effective) <= 0.000001:
			continue
		for source: Dictionary in ground_sources(other):
			if float(source.effective) > 0.000001 and StateDistance(g._space.xy(source), site.xy) <= float(site.radius_km):
				return true
	for anchor: Dictionary in g.participants.detached_targets(str(unit.area_id)).values():
		if anchor.side != unit.side and g.participants._member(str(anchor.actor_ref)).actionable and StateDistance(anchor.xy, site.xy) <= float(site.radius_km):
			return true
	return false

func _cover_available(order: Dictionary, key: String) -> bool:
	if not order.require_cover or order.returning:
		return true # Watch/return grants no suppression or protection bonus.
	if fire_orders.get(order.unit_ref, {}).get("fire_mode", "watch") in ["cease", "watch"]:
		return false
	var part: Dictionary = order.parts[key]
	if part.role != "FIRE" or _g()._state.time < float(part.ready_at) or float(part.ammunition) <= 0.000001 or float(part.serviceable) < _part_weapon_equipment(part):
		return false
	var source: Dictionary = part_source(_g()._state.units[order.unit_ref], part)
	if _anonymous_fire_capacity(part) > 0.000001 and float(part.ammunition) - _part_ready(part) > 0.000001 and not visible_targets(source, str(order.target_ref)).is_empty():
		return true
	for person: String in part.members:
		var weapon: Dictionary = weapons.get(person, {})
		if _g().participants.can_intend(person) and weapon.get("mode", "") == "FIRE" and weapon.get("fire_owner_ref", "") == order.id and weapon.get("status", "") == "READY" and float(weapon.get("ready", 0.0)) > 0.000001 and visible(person, str(order.target_ref), true):
			return true
	return false

func _member_conflict(person: String, order: Dictionary) -> bool:
	var body: Dictionary = _g().participants._member(person)
	if body.get("local_duty", false) or supply_jobs.has(str(order.unit_ref)):
		return true
	if not body.actionable or not str(body.action_ref).is_empty() or not str(body.get("carrying_ref", "")).is_empty() or float(body.get("combat_busy_until", 0.0)) > _g()._state.time:
		return true
	var weapon: Dictionary = weapons.get(person, {})
	if weapon.is_empty():
		return false
	if weapon.status in ["AIMING", "RELOADING"] and _tickets.get(weapon.get("operation_ref", ""), {}).get("cause_ref", "") != order.id:
		return true
	return weapon.mode == "FIRE" and weapon.get("fire_owner_ref", "") != order.id and float(weapon.get("until", 0.0)) > _g()._state.time

func _update_manoeuvre(unit_id: String) -> void:
	if not manoeuvre_active(unit_id) or manoeuvres[unit_id].phase == "STOPPED":
		return
	var g: RefCounted = _g()
	var order: Dictionary = manoeuvres[unit_id]
	var unit: Dictionary = g._state.units.get(unit_id, {})
	if unit.is_empty() or not order.returning and (unit.mission_id != order.mission_ref or g._state.missions[unit.mission_id].status != "active") or not _free(unit) or movement_blocked(unit_id) or float(unit.effective) <= 0.000001 or float(unit.mobility) <= 0.0 or float(unit.readiness) <= 0.0:
		_stop_manoeuvre(unit_id, "actual_mobility_equipment_or_duty_changed", str(order.id))
		return
	for part: Dictionary in order.parts.values():
		if order.get("supply_only", false) and part.id != order.parts[order.lead_part].id:
			continue
		if order.get("supply_only", false) and float(part.ammunition) > part_capacity(part) * CARRY_AMMUNITION + 0.000001:
			_stop_manoeuvre(unit_id, "actual_ammunition_carrying_capacity_lost", str(order.last_command_ref))
			return
		if part_capacity(part) <= 0.000001 or part_pressure(part) >= float(g._state.missions[unit.mission_id].stop_suppression) or float(part.cohesion) < float(g._state.missions[unit.mission_id].withdraw_cohesion) and not order.returning:
			_stop_manoeuvre(unit_id, "part_capacity_pressure_or_cohesion_changed", str(order.id))
			return
		for person: String in part.members:
			var body: Dictionary = g.participants._member(person)
			if g.participants._units.get(person, "") != unit_id or _member_conflict(person, order) or g.participants.body_suppression(person) >= float(g._state.missions[unit.mission_id].stop_suppression):
				_stop_manoeuvre(unit_id, "member_loss_transfer_pressure_or_other_body_duty", str(order.id))
				return
	if not order.returning and g._state.time >= float(order.deadline):
		_stop_manoeuvre(unit_id, "original_deadline_expired", str(order.id))
		return
	var local: bool = order.get("travel_kind", "ROAD") == "LOCAL"
	var edge: Dictionary = _manoeuvre_edges(order)[order.edge_ref]
	var closed: bool = not edge.open
	if closed and order.returning and local:
		for part: Dictionary in order.parts.values():
			if str(part.spatial.get("local_edge", "")) == "" and not g._space.local_arrived(part.spatial, str(order.leg_from)):
				_stop_manoeuvre(unit_id, "closed_local_leg_cannot_be_entered_for_return", str(order.id))
				return
	if closed and not order.returning or g._space.movement_factor(edge.ground, "FOOT") <= 0.0:
		_stop_manoeuvre(unit_id, "actual_local_path_blocked" if local else "actual_road_blocked", str(order.id))
		return
	var lead: String = str(order.lead_part)
	var other: String = "rear" if lead == "front" else "front"
	match str(order.phase):
		"PREPARE", "RETURN_PREPARE":
			if g._state.time < float(order.prepare_until):
				return
			for person: String in order.roster:
				if weapons.get(person, {}).get("status", "") == "RELOADING":
					return
			_guard_part(order, other)
			order.phase = "GUARD_PREPARING_FIRE"
			_schedule_manoeuvre(order, maxf(1.0, float(order.parts[other].ready_at) - g._state.time))
		"GUARD_PREPARING_FIRE":
			if g._state.time < float(order.parts[other].ready_at):
				return
			if not _cover_available(order, other):
				_stop_manoeuvre(unit_id, "guard_cover_unavailable", str(order.id))
				return
			_start_part(order, lead, false)
		"FRONT_MOVING", "FRONT_RETURNING", "REAR_MOVING", "REAR_RETURNING":
			if not _cover_available(order, str(order.guard_part)):
				_stop_manoeuvre(unit_id, "guard_cover_lost", str(order.id))
				return
			var part: Dictionary = order.parts[order.moving_part]
			if not _part_arrived(order, part):
				return
			_end_part_motion(order, part)
			var second: bool = str(order.phase).begins_with("REAR")
			if not _enter_part(order, part):
				_adopt_part_arrival(order, second)
		"FRONT_ENTERING", "REAR_ENTERING":
			var part: Dictionary = order.parts[order.moving_part]
			if not g._space.local_enterable(part.spatial):
				_stop_manoeuvre(unit_id, "position_damaged_during_entry", str(order.id))
				return
			if not _cover_available(order, str(order.guard_part)):
				_stop_manoeuvre(unit_id, "guard_cover_lost_during_entry", str(order.id))
				return
			if g._state.time < float(part.ready_at):
				return
			part.spatial.entered_site_ref = part.destination_node
			part.role = "WATCH"
			for person: String in part.members:
				var body: Dictionary = g.participants._member(person)
				body.entered_site_ref = part.destination_node
				body.erase("part_entry_ref")
				body.state = "STATIONARY"
			_sync_stock_anchor(unit, order.parts[order.stock_part])
			_manoeuvre_feedback(order, "local_position_entered")
			_adopt_part_arrival(order, str(order.phase).begins_with("REAR"))
		"FRONT_PREPARING_FIRE":
			if g._state.time < float(order.parts[lead].ready_at):
				return
			if not _cover_available(order, lead):
				_stop_manoeuvre(unit_id, "lead_has_no_prepared_cover_at_actual_stop", str(order.id))
				return
			if g._space.observation_at(part_source(unit, order.parts[other]), _part_target(unit, order.parts[lead])) <= 0.0:
				_stop_manoeuvre(unit_id, "role_signal_not_observed", str(order.id))
				return
			_start_part(order, other, true)
			_manoeuvre_feedback(order, "road_roles_changed")

func _end_part_motion(order: Dictionary, part: Dictionary) -> void:
	part.role = "WATCH"
	for person: String in part.members:
		var body: Dictionary = _g().participants._member(person)
		if body.get("part_action_ref", "") == part.action_ref:
			body.erase("part_action_ref")
			body.state = "STATIONARY"
			order.moving[person] = {"status": "EXECUTED", "action_ref": part.action_ref, "at": _g()._state.time}
	part.action_ref = ""
	_manoeuvre_feedback(order, "road_part_arrived")

func constrain_manoeuvre(unit: Dictionary, plan: Dictionary) -> void:
	if not manoeuvre_active(str(unit.id)):
		return
	var order: Dictionary = manoeuvres[unit.id]
	plan.manoeuvre_ref = order.id
	plan.manoeuvre_return = order.returning
	plan.speed = 0.0
	plan.part_moves = {}
	plan.part_movement_seconds = INF
	for key: String in ["front", "rear"]:
		var part: Dictionary = order.parts[key]
		if part.role != "MOVING" or order.phase == "STOPPED":
			continue
		var source: Dictionary = part_source(unit, part)
		var motion: Dictionary = {"posture": "advance", "advance_inhibited": false, "side_frontage": plan.get("side_frontage", 1.0), "manoeuvre_ref": order.id, "manoeuvre_return": order.returning, "action_part": part.id, "part_revision": part.revision}
		_g()._space.prepare_movement(source, motion)
		var native_speed: float = float(motion.speed)
		var health_cap: float = 1.0
		for person: String in part.members:
			var body: Dictionary = _g().participants._member(person)
			health_cap = minf(health_cap, float(body.health) * (1.0 - _g().participants.body_suppression(person)))
		motion.speed = native_speed * health_cap
		if not part.members.is_empty():
			var local_limit: float = float(_g().participants.rules.local_speed_km_s) * 60.0 * absf(native_speed) / maxf(0.000001, float(unit.mobility)) * health_cap
			motion.speed = signf(native_speed) * minf(absf(float(motion.speed)), local_limit)
		if source.get("supply_capability", {}).get("fuel_dependent", false):
			_g()._state.logistics_port.get_ref().prepare_activity(source, motion)
		if _part_arrived(order, part):
			motion.speed = 0.0
		plan.part_moves[key] = motion
		motion.capacity_share = part_capacity(part) / maxf(0.000001, float(unit.effective))
		plan.part_movement_seconds = minf(float(plan.part_movement_seconds), _g()._space.movement_eta(source, motion))
		if float(motion.get("fuel_rate", 0.0)) > 0.0:
			plan.part_movement_seconds = minf(float(plan.part_movement_seconds), float(unit.fuel) / float(motion.fuel_rate) * 60.0)

func apply_part_movement(unit: Dictionary, plan: Dictionary, minutes: float, log: Array[Dictionary]) -> void:
	if not manoeuvre_active(str(unit.id)):
		return
	var g: RefCounted = _g()
	var order: Dictionary = manoeuvres[unit.id]
	for key: String in plan.get("part_moves", {}):
		var part: Dictionary = order.parts[key]
		var motion: Dictionary = plan.part_moves[key]
		# This plan belongs to the interval just settled, even when its incoming
		# losses interrupted future movement. Never grant an extra arrival later.
		var source: Dictionary = part_source(unit, part)
		source.action = "advance"
		var travelled: float = g._space.move(source, motion, minutes, log)
		part.spatial = source.spatial
		part.distance_moved += travelled
		part.movement_seconds += minutes * 60.0 if travelled > 0.0 else 0.0
		part.settled_at = g._state.time
		unit.distance_moved += travelled * float(motion.get("capacity_share", 1.0))
		if unit.has("supply_capability"):
			var before: float = float(unit.serviceable_equipment)
			motion.protected_equipment = maxf(0.0, before - float(part.serviceable))
			motion.fuel_per_km = float(part.serviceable) * float(unit.supply_capability.fuel_per_equipment_km)
			g._state.logistics_port.get_ref().consume_activity(unit, motion, travelled)
			part.serviceable = maxf(0.0, float(part.serviceable) - (before - float(unit.serviceable_equipment)))
		for person: String in part.members:
			var body: Dictionary = g.participants._member(person)
			# An incapacitated or reassigned body retains its last settled location;
			# only members owned by this interval's movement are advanced.
			if body.get("part_action_ref", "") != part.action_ref or body.get("part_revision", -1) != motion.part_revision:
				continue
			body.xy = g._space.xy(source)
			body.anchor_node = part.spatial.node
			body.anchor_edge = part.spatial.edge
			for field: String in ["local_ref", "local_edge", "local_from", "local_to", "local_progress", "local_returning", "entered_site_ref"]:
				body.erase(field)
				if part.spatial.has(field):
					body[field] = part.spatial[field]
			body.distance_moved = float(body.get("distance_moved", 0.0)) + travelled
			body.movement_seconds = float(body.get("movement_seconds", 0.0)) + (minutes * 60.0 if travelled > 0.0 else 0.0)
		if key == order.stock_part:
			_sync_stock_anchor(unit, part)
	for key: String in ["front", "rear"]:
		var part: Dictionary = order.parts[key]
		if absf(float(plan.get("part_moves", {}).get(key, {}).get("speed", 0.0))) > 0.0 or float(plan.get("part_spent", {}).get(part.id, 0.0)) > 0.0:
			part.fatigue = clampf(float(part.fatigue) + g._lod._kernel.FATIGUE_PER_MINUTE * minutes, 0.0, 1.0)
	unit.fatigue = maxf(float(order.parts.front.fatigue), float(order.parts.rear.fatigue))
	_sync_part_stock(unit)

func _sync_stock_anchor(unit: Dictionary, part: Dictionary) -> void:
	var g: RefCounted = _g()
	var previous: String = str(unit.area_id)
	unit.spatial = part.spatial.duplicate(true)
	unit.spatial.path = []
	unit.position = float(g._space.xy(unit)[0])
	var destination: String = str(g._space._nodes[unit.spatial.node].cell)
	if destination != previous:
		g._state.area_units[previous].erase(unit.id)
		g._state.area_units[destination][unit.id] = true
		unit.area_id = destination
		g._lod.on_spatial_transfer(str(unit.id), previous, destination)
		g._state.wake(destination)

func _sync_part_stock(unit: Dictionary) -> void:
	if not manoeuvre_active(str(unit.id)):
		return
	var order: Dictionary = manoeuvres[unit.id]
	var delta: float = float(unit.ammunition) - float(order.parts.front.ammunition) - float(order.parts.rear.ammunition) - _carried_total(str(unit.id)) - _detached_ready(str(unit.id))
	if delta > 0.000001:
		order.parts[order.stock_part].ammunition += delta
	elif delta < -0.000001:
		for key: String in [str(order.stock_part), "front" if order.stock_part == "rear" else "rear"]:
			var taken: float = minf(float(order.parts[key].ammunition), -delta)
			order.parts[key].ammunition -= taken
			delta += taken
			_clip_part_ready(order.parts[key])
	var equipment: float = float(order.parts.front.equipment) + float(order.parts.rear.equipment)
	var serviceable: float = float(order.parts.front.serviceable) + float(order.parts.rear.serviceable)
	if float(unit.equipment) > equipment + 0.000001:
		order.parts[order.stock_part].equipment += float(unit.equipment) - equipment
	if float(unit.serviceable_equipment) > serviceable + 0.000001:
		order.parts[order.stock_part].serviceable += float(unit.serviceable_equipment) - serviceable

func _clip_part_ready(part: Dictionary) -> void:
	var available: float = float(part.ammunition)
	for person: String in part.members:
		if weapons.has(person) and not _g().participants._member(person).get("local_duty", false):
			weapons[person].ready = minf(float(weapons[person].ready), available)
			available -= float(weapons[person].ready)

func after_manoeuvre_movement(unit: Dictionary) -> void:
	# Arrival is adopted from each part after the original simultaneous settlement.
	if manoeuvre_active(str(unit.id)) and not manoeuvres[unit.id].get("parts", {}).is_empty():
		var order: Dictionary = manoeuvres[unit.id]
		unit.suppression = maxf(part_pressure(order.parts.front), part_pressure(order.parts.rear))
		unit.cohesion = minf(float(order.parts.front.cohesion), float(order.parts.rear.cohesion))
		_update_manoeuvre(str(unit.id))

func _finish_manoeuvre(order: Dictionary, returning: bool) -> void:
	var g: RefCounted = _g()
	var unit: Dictionary = g._state.units[order.unit_ref]
	var point: Array = g._space.xy(part_source(unit, order.parts.front))
	if order.get("travel_kind", "ROAD") == "LOCAL" and _local_contested(order):
		_stop_manoeuvre(str(unit.id), "actual_local_position_contested", str(order.id))
		return
	if StateDistance(point, g._space.xy(part_source(unit, order.parts.rear))) > 0.000001:
		_stop_manoeuvre(str(unit.id), "actual_parts_not_rejoined", str(order.id))
		return
	for person: String in order.roster:
		if g.participants._member(person).get("local_duty", false) or not str(g.participants._member(person).get("carrying_ref", "")).is_empty() or not g.participants._member(person).actionable or not str(g.participants._member(person).action_ref).is_empty() or StateDistance(g.participants.position(person), point) > 0.000001:
			_stop_manoeuvre(str(unit.id), "rendezvous_requires_actual_bodies_without_other_duties", str(order.id))
			return
	order.revision += 1
	order.phase = "RENDEZVOUS"
	order.moving_part = ""
	_manoeuvre_feedback(order, "road_parts_rejoined")
	if not returning and int(order.leg_index) + 1 < order.path.size():
		order.leg_index += 1
		order.edge_ref = ""
		order.lead_part = "rear" if order.lead_part == "front" else "front"
		order.phase = "PREPARE"
		_prepare_manoeuvre(order)
	else:
		order.phase = "REGROUPED" if returning else "COMPLETE"
		order.finished_at = g._state.time
		for person: String in order.roster:
			var body: Dictionary = g.participants._member(person)
			if weapons.has(person) and weapons[person].get("group_assignment_ref", "") == order.id:
				_stop(weapons[person], "GROUP")
				weapons[person].group_assignment_ref = ""
			body.erase("part_ref")
			body.erase("part_action_ref")
			body.state = "FOLLOWING"
			body.anchor_node = unit.spatial.node
			body.anchor_edge = ""
		unit.spatial.path = [] if returning else order.continuation_path.duplicate()
		var mission: Dictionary = g._state.missions[unit.mission_id]
		if order.get("travel_kind", "ROAD") == "ROAD" and not returning and unit.spatial.path.is_empty() and order.prior_path == order.path and mission.status == "active" and not mission.has("goal_v1") and not mission.get("summary_goal_policy", false):
			mission.status = "complete"
			unit.action = "hold"
			g._lod._kernel._wake_dependents(g._state, str(mission.id))
		if fire_orders.get(order.unit_ref, {}).get("manoeuvre_ref", "") == order.id:
			fire_orders.erase(order.unit_ref)
		_manoeuvre_feedback(order, "road_manoeuvre_finished")

func _stop_manoeuvre(unit_id: String, reason: String, cause: String) -> void:
	if not manoeuvre_active(unit_id):
		return
	var order: Dictionary = manoeuvres[unit_id]
	if order.phase == "STOPPED":
		return
	order.resume_phase = order.phase
	order.phase = "STOPPED"
	order.reason = reason
	order.revision += 1
	order.stopped_at = _g()._state.time
	for part: Dictionary in order.parts.values():
		part.revision += 1
		part.spatial.path.clear()
		part.spatial.local_path = []
		if part.role == "MOVING":
			part.role = "WATCH"
		if part.role == "ENTERING":
			part.role = "WATCH"
		for person: String in part.members:
			if _g().participants._units.get(person, "") != unit_id:
				continue
			var body: Dictionary = _g().participants._member(person)
			if body.get("part_action_ref", "") == part.action_ref:
				body.erase("part_action_ref")
				if body.state == "PART_MOVING":
					body.state = "STATIONARY"
			if body.get("part_entry_ref", "") == part.id:
				body.erase("part_entry_ref")
				if body.state == "PART_ENTERING":
					body.state = "STATIONARY"
			if weapons.has(person) and (weapons[person].get("fire_owner_ref", "") == order.id or _tickets.get(weapons[person].get("operation_ref", ""), {}).get("cause_ref", "") == order.id):
				_stop(weapons[person], "CEASE")
		part.action_ref = ""
	_manoeuvre_feedback(order, "road_manoeuvre_stopped", cause)

func _manoeuvre_feedback(order: Dictionary, kind: String, cause: String = "") -> void:
	var g: RefCounted = _g()
	if g._state.units.has(order.unit_ref):
		g._state.wake(str(g._state.units[order.unit_ref].area_id))
		if g._goals.has(order.unit_ref):
			g._ready[order.unit_ref] = true
		g._emit(str(order.unit_ref), kind, str(order.id) if cause == "" else cause, {"manoeuvre": manoeuvre_fact(str(order.unit_ref))})

func on_local_link(reference: String) -> void:
	# Only the few allocated parts depending on this link are reconsidered.
	_g().participants.interrupt_local_edge(reference)
	for unit_id: String in manoeuvres:
		var order: Dictionary = manoeuvres[unit_id]
		if manoeuvre_active(unit_id) and order.get("travel_kind", "ROAD") == "LOCAL" and order.edge_ref == reference:
			_update_manoeuvre(unit_id)
			_g()._state.wake(str(_g()._state.units[unit_id].area_id))

func manoeuvre_fact(unit_id: String) -> Dictionary:
	return manoeuvres[unit_id].duplicate(true) if manoeuvres.has(unit_id) else {}

func manoeuvre_report(unit_id: String) -> Dictionary:
	var g: RefCounted = _g()
	var order: Dictionary = manoeuvres[unit_id]
	if not manoeuvre_active(unit_id):
		return {"id": order.id, "mission_ref": order.mission_ref, "revision": order.revision, "phase": order.phase, "travel_kind": order.get("travel_kind", "ROAD"), "destination_node": order.destination_node, "finished_at": order.get("finished_at", order.started_at), "distribution_ended": true, "local_objective_complete": order.get("travel_kind", "ROAD") == "LOCAL" and order.phase == "COMPLETE"}
	var unit: Dictionary = g._state.units[unit_id]
	var result: Dictionary = {"id": order.id, "mission_ref": order.mission_ref, "revision": order.revision,
		"phase": order.phase, "reason": order.reason, "deadline": order.deadline, "stopped_at": order.get("stopped_at", 0.0), "destination_node": order.destination_node,
		"edge_ref": order.edge_ref, "leg_index": order.leg_index, "front_members": order.parts.front.members.duplicate(),
		"travel_kind": order.get("travel_kind", "ROAD"), "rear_xy": g._space.xy(unit), "rear_spatial": unit.spatial.duplicate(true), "observed_front": {}, "observed_parts": {}}
	# The existing unit report platform remains with the stock/anchor part.
	var source: Dictionary = part_source(unit, order.parts[order.stock_part])
	for key: String in ["front", "rear"]:
		var part: Dictionary = order.parts[key]
		var anchor: Dictionary = _part_target(unit, part)
		if g._space.observation_at(source, anchor) > 0.0:
			result.observed_parts[key] = {"part_ref": part.id, "xy": anchor.xy, "node_ref": anchor.node, "role": part.role, "local_ref": g._space.local_place(part.spatial), "entered_site_ref": part.spatial.get("entered_site_ref", ""), "observed_at": g._state.time}
			for person: String in part.members:
				if g._space.observation_at(source, {"node": g.participants._member(person).anchor_node, "sight_ref": g._space.sight_ref(g.participants.body_spatial(person)), "xy": g.participants.position(person), "ground": g.participants.body_ground(person)}) > 0.0:
					result.observed_front[person] = {"xy": g.participants.position(person), "observed_at": g._state.time, "state": g.participants._member(person).state}
	if result.observed_parts.size() != 2:
		result.phase = "PART_TASK_UNCONFIRMED" if order.phase not in ["COMPLETE", "REGROUPED"] else order.phase
		result.reason = "part_progress_unconfirmed" if order.reason != "" else ""
	if order.get("travel_kind", "ROAD") == "LOCAL":
		var edge: Dictionary = g._space._local_edges[order.edge_ref]
		var a: Array = g._space.local_endpoint(str(edge.from)).xy
		var b: Array = g._space.local_endpoint(str(edge.to)).xy
		var middle: Array = [(float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5]
		var from: Dictionary = g._space.local_endpoint(str(edge.from))
		var to: Dictionary = g._space.local_endpoint(str(edge.to))
		if g._space.observation_at(source, {"node": source.spatial.node, "sight_ref": "segment:" + str(order.edge_ref), "xy": middle, "ground": edge.ground}) > 0.0 and g._space.observation_at(source, {"node": from.node_ref, "sight_ref": edge.from, "xy": from.xy, "ground": from.ground}) > 0.0 and g._space.observation_at(source, {"node": to.node_ref, "sight_ref": edge.to, "xy": to.xy, "ground": to.ground}) > 0.0:
			result.local_link = {"link_ref": order.edge_ref, "state": "OPEN" if edge.open else "CLOSED", "observed_at": g._state.time}
	return result

func _anonymous_fire_capacity(part: Dictionary) -> float:
	if supply_jobs.has(str(part.unit_ref)) and part.id in supply_jobs[part.unit_ref].get("part_refs", []):
		return 0.0
	var dedicated: float = 0.0
	var collective: float = float(part.anonymous)
	for person: String in part.members:
		if weapons.has(person) and (weapons[person].mode != "RELEASED" or float(weapons[person].ready) > 0.000001):
			dedicated += float(weapons[person].profile.equipment_share)
		else:
			var body: Dictionary = _g().participants._member(person)
			if not body.get("local_duty", false) and body.actionable and str(body.action_ref).is_empty() and str(body.get("carrying_ref", "")).is_empty() and body.state != "PART_MOVING" and float(body.get("combat_busy_until", 0.0)) <= _g()._state.time:
				collective += float(body.health) * (1.0 - _g().participants.body_suppression(person))
	return minf(collective, maxf(0.0, float(part.serviceable) - dedicated))

func _part_weapon_equipment(part: Dictionary) -> float:
	var result: float = 0.0
	for actor: String in part.members:
		if weapons.has(actor) and weapons[actor].get("holder_ref", "") == actor:
			result += float(weapons[actor].profile.equipment_share)
	return result

func _part_target(unit: Dictionary, part: Dictionary) -> Dictionary:
	var source: Dictionary = part_source(unit, part)
	var ground: Dictionary = _g()._space.terrain(source)
	var cover: float = minf(float(ground.cover), 0.35) if part.role == "FIRE" and _g()._space._local_sites.has(_g()._space.local_place(part.spatial)) else float(ground.cover)
	return {"part_ref": part.id, "unit_ref": unit.id, "side": unit.side, "node": part.spatial.node, "sight_ref": _g()._space.sight_ref(part.spatial), "xy": _g()._space.xy(source), "ground": ground,
		"weight": float(unit.get("contact_weight", unit.get("tactical_weight", 1.0))) * float(part.anonymous) / maxf(0.000001, float(unit.personnel_total)),
		"exposure": (1.15 if part.role in ["MOVING", "ENTERING"] else 0.65) * (1.0 - cover), "incoming": 0.0, "incoming_pressure": 0.0, "damage_owner": "PART"}

func part_targets(cell: String) -> Dictionary:
	var result: Dictionary = {}
	var cells: Array[String] = _g()._space.scope_cells(cell)
	for unit_id: String in manoeuvres:
		if not manoeuvre_active(unit_id) or str(_g()._state.units[unit_id].area_id) not in cells:
			continue
		var unit: Dictionary = _g()._state.units[unit_id]
		for part: Dictionary in manoeuvres[unit_id].parts.values():
			if float(part.anonymous) > 0.000001:
				result["part:" + part.id] = _part_target(unit, part)
	return result

func target_unit(reference: String, overlay: Dictionary = {}) -> String:
	if overlay.has(reference):
		return str(overlay[reference].get("unit_ref", _g().participants._units.get(overlay[reference].get("actor_ref", ""), "")))
	return reference

func visible_targets(source: Dictionary, target: String, shooting: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var g: RefCounted = _g()
	if not g._state.units.has(target) or g._state.units[target].side == source.side:
		return result
	if not manoeuvre_active(target):
		var factor: float = g._space.detection(source, g._state.units[target]) if shooting else g._space.observation(source, g._state.units[target])
		if factor > 0.0 and parent_presence(g._state.units[target]) > 0.000001:
			result[target] = {"factor": factor, "weight": g._lod._kernel._contact_weight(g._state, target)}
	else:
		for part: Dictionary in manoeuvres[target].parts.values():
			var anchor: Dictionary = _part_target(g._state.units[target], part)
			var factor: float = g._space.detection_at(source, anchor) if shooting else g._space.observation_at(source, anchor)
			if factor > 0.0 and float(part.anonymous) > 0.000001:
				result["part:" + part.id] = {"factor": factor, "weight": anchor.weight}
	for anchor: Dictionary in g.participants.detached_targets(str(source.area_id)).values():
		if g.participants._units.get(anchor.actor_ref, "") != target:
			continue
		var factor: float = g._space.detection_at(source, anchor) if shooting else g._space.observation_at(source, anchor)
		if factor > 0.0:
			result["body:" + str(anchor.actor_ref)] = {"factor": factor, "weight": anchor.weight}
	return result

func _component_targets(source: Dictionary, subject: String, plan: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if subject not in plan.get("segment_units", []):
		return result
	var detected: Dictionary = visible_targets(source, subject)
	var weight: float = 0.0
	for reference: String in detected:
		if reference == subject or plan.body_targets.has(reference):
			weight += float(detected[reference].weight)
	for reference: String in detected:
		if reference == subject or plan.body_targets.has(reference):
			result[reference] = float(detected[reference].factor) * float(detected[reference].weight) / maxf(0.000001, weight)
	return result

func build_part_fire(unit: Dictionary, plan: Dictionary, contacts: Array, detected: Dictionary) -> void:
	var order: Dictionary = manoeuvres[unit.id]
	for key: String in ["front", "rear"]:
		var part: Dictionary = order.parts[key]
		if part.role != "FIRE" or _g()._state.time < float(part.ready_at) or fire_orders.get(unit.id, {}).get("fire_mode", "watch") in ["watch", "cease"]:
			continue
		var available: float = maxf(0.0, float(part.ammunition) - _part_ready(part))
		var source: Dictionary = part_source(unit, part)
		var rates: Dictionary = _component_targets(source, str(order.target_ref), plan)
		var base: float = _anonymous_fire_capacity(part) * float(unit.readiness) * float(part.cohesion) * (1.0 - float(part.fatigue) * 0.5) * (1.0 - part_pressure(part)) * float(unit.weapon.rounds_per_minute)
		base *= minf(1.0, float(_g()._space.terrain(source).frontage) / maxf(0.001, float(plan.get("tactical_frontage", 1.0))))
		var total: float = 0.0
		for reference: String in rates:
			rates[reference] *= base
			total += float(rates[reference])
			if reference not in contacts:
				contacts.append(reference)
				detected[reference] = 1.0
		if total > 0.0 and available > 0.000001:
			plan.fire_components.append({"actor_ref": "", "part_key": key, "rate": total, "ready": available, "targets": rates,
				"lethality": float(unit.weapon.lethality) * 0.5, "pressure": float(unit.get("supply_capability", {}).get("suppression_per_round", 0.12)) * 1.5})

func apply_part_damage(unit_id: String, part_ref: String, dose: float, pressure: float, minutes: float, cause: String) -> float:
	if not manoeuvre_active(unit_id):
		return 0.0
	var g: RefCounted = _g()
	var unit: Dictionary = g._state.units[unit_id]
	for part: Dictionary in manoeuvres[unit_id].parts.values():
		if part.id != part_ref or part.get("last_damage_ref", "") == cause:
			continue
		part.last_damage_ref = cause
		var loss: float = minf(float(part.anonymous), maxf(0.0, dose))
		part.anonymous -= loss
		part.anonymous_loss += loss
		unit.gameplay_personnel.anonymous = maxf(0.0, float(unit.gameplay_personnel.anonymous) - loss)
		var before: float = float(unit.serviceable_equipment)
		var equipment_loss: float = g._lod._kernel.apply_capacity_loss(g._state, unit, loss, maxf(0.0, float(unit.equipment) - float(part.equipment)), maxf(0.0, float(unit.serviceable_equipment) - float(part.serviceable)))
		part.equipment = maxf(0.0, float(part.equipment) - equipment_loss)
		part.serviceable = maxf(0.0, float(part.serviceable) - (before - float(unit.serviceable_equipment)))
		part.equipment_lost += equipment_loss
		if g._lod._groups.has(unit_id):
			g.participants.settle_sparse(unit, loss, {})
		var decay: float = exp(-g._lod._kernel.SUPPRESSION_DECAY * minutes)
		var pressure_increment: float = pressure / maxf(0.000001, float(part.anonymous) + loss)
		if minutes > 0.0:
			pressure_increment *= (1.0 - decay) / g._lod._kernel.SUPPRESSION_DECAY
		part.suppression = clampf(part_pressure(part) + pressure_increment, 0.0, 1.0)
		part.pressure_at = g._state.time
		part.cohesion = clampf(float(part.cohesion) - loss / maxf(0.000001, float(part.initial_anonymous)) * g._lod._kernel.COHESION_PER_LOSS, 0.0, 1.0)
		g._state.touched_units[unit_id] = true
		g._state.wake(str(unit.area_id))
		return loss
	return 0.0

func ground_positions(unit_id: String, group_only: bool = false) -> Array:
	var result: Array = []
	for source: Dictionary in ground_sources(_g()._state.units[unit_id]):
		if group_only and source.has("body_target_ref"):
			continue
		result.append(_g()._space.xy(source))
	return result

func ground_sources(unit: Dictionary) -> Array:
	var result: Array = []
	if manoeuvre_active(str(unit.id)):
		for part: Dictionary in manoeuvres[unit.id].parts.values():
			if float(part.anonymous) > 0.000001:
				var source: Dictionary = part_source(unit, part)
				source.effective = part.anonymous
				result.append(source)
	elif parent_presence(unit) > 0.000001:
		var source: Dictionary = unit.duplicate()
		source.effective = parent_presence(unit)
		result.append(source)
	for person: String in unit.get("gameplay_personnel", {}).get("members", {}):
		if separated_actor(person) and float(_g().participants._member(person).health) > 0.000001:
			var source: Dictionary = _body_source(person, float(unit.weapon.range_km))
			source.effective = _g().participants._member(person).health
			source.body_target_ref = person
			result.append(source)
	return result

func fire_solution(source: Dictionary, target: String) -> Dictionary:
	for location: Dictionary in ground_sources(_g()._state.units[target]):
		if _g()._space.detection(source, location) > 0.0:
			return {"xy": _g()._space.xy(location), "node_ref": location.spatial.node}
	return {}

func support_fire(unit: Dictionary, rounds: float, lethality: float, cause: String, point: Array, radius: float, include_bodies: bool) -> void:
	var affected: Array[Dictionary] = []
	var weights: float = 0.0
	if manoeuvre_active(str(unit.id)):
		for part: Dictionary in manoeuvres[unit.id].parts.values():
			var anchor: Dictionary = _part_target(unit, part)
			if float(part.anonymous) > 0.000001 and StateDistance(anchor.xy, point) <= radius:
				affected.append(anchor)
				weights += float(anchor.weight)
	elif parent_presence(unit) > 0.000001 and StateDistance(_g()._space.xy(unit), point) <= radius:
		var weight: float = parent_presence(unit) / maxf(0.000001, float(unit.personnel_total))
		affected.append({"damage_owner": "GROUP", "weight": weight})
		weights += weight
	if include_bodies:
		for anchor: Dictionary in _g().participants.detached_targets(str(unit.area_id)).values():
			if anchor.get("unit_ref", "") == unit.id and StateDistance(anchor.xy, point) <= radius:
				affected.append(anchor)
				weights += float(anchor.weight)
	for anchor: Dictionary in affected:
		var portion: float = rounds * float(anchor.weight) / maxf(0.000001, weights)
		if anchor.get("damage_owner", "") == "PART":
			apply_part_damage(str(unit.id), str(anchor.part_ref), portion * lethality * float(anchor.exposure), portion * _g()._lod._kernel.SUPPRESSION_PER_ROUND * float(anchor.exposure), 0.0, cause)
		elif anchor.get("damage_owner", "") == "GROUP":
			_g()._lod._kernel._direct_group_fire(_g()._state, unit, portion, lethality, cause)
		else:
			var body: Dictionary = _g().participants._member(str(anchor.actor_ref))
			body.local_suppression = clampf(_g().participants.body_suppression(str(anchor.actor_ref)) + portion * _g()._lod._kernel.SUPPRESSION_PER_ROUND * float(anchor.exposure), 0.0, 1.0)
			body.pressure_at = _g()._state.time
			_g().participants.external_damage(str(anchor.actor_ref), portion * lethality * float(anchor.exposure), cause, "shared_local_support_fire")
			if body.state in ["LOCAL_MOVING", "LOCAL_ENTERING"] and float(body.local_suppression) >= float(_g()._state.missions[unit.mission_id].stop_suppression):
				_g().participants.interrupt_action(str(anchor.actor_ref), "actual_local_support_pressure")
		_update_manoeuvre(str(unit.id))
	_g()._state.contacts.erase(unit.area_id)

func observed_ground_target(actor: String, target: String) -> Dictionary:
	var own: Dictionary = _g().participants._physical_unit(actor)
	var source: Dictionary = _body_source(actor, float(own.weapon.get("observation_range_km", own.weapon.range_km)))
	var visible_set: Dictionary = visible_targets(source, target, false)
	for reference: String in State.sorted_ids(visible_set):
		if reference.begins_with("part:"):
			for part: Dictionary in manoeuvres[target].parts.values():
				if "part:" + str(part.id) == reference:
					return {"node_ref": part.spatial.node, "xy": _g()._space.xy(part_source(_g()._state.units[target], part)), "local_place_ref": _g()._space.local_place(part.spatial), "part_ref": part.id, "condition": "OBSERVED", "can_fire": visible(actor, target, true), "partial_unit": true}
		elif reference.begins_with("body:"):
			var member: String = reference.trim_prefix("body:")
			return {"node_ref": _g().participants._member(member).anchor_node, "xy": _g().participants.position(member), "local_place_ref": _g()._space.local_place(_g().participants.body_spatial(member)), "condition": "OBSERVED", "can_fire": visible(actor, target, true), "partial_unit": true}
		else:
			var unit: Dictionary = _g()._state.units[target]
			return {"node_ref": unit.spatial.node, "xy": _g()._space.xy(unit), "local_place_ref": _g()._space.local_place(unit.spatial), "condition": "INCAPACITATED" if float(unit.effective) <= 0.001 else "OBSERVED", "can_fire": visible(actor, target, true)}
	return {}

func observed_local_scene(actor: String) -> Dictionary:
	var g: RefCounted = _g()
	var unit: Dictionary = g.participants._physical_unit(actor)
	var source: Dictionary = _body_source(actor, float(unit.weapon.get("observation_range_km", unit.weapon.range_km)))
	var result: Dictionary = {"node_ref": source.spatial.node, "cover_refs": [], "local_sites": [], "xy": g._space.xy(source)}
	for id: String in g._space._local_sites:
		var site: Dictionary = g._space._local_sites[id]
		if str(g._space._nodes[site.node_ref].cell) not in g._space.scope_cells(str(unit.area_id)):
			continue
		if StateDistance(g._space.xy(source), site.xy) > 0.000001 and g._space.observation_at(source, {"node": site.node_ref, "sight_ref": id, "xy": site.xy, "ground": site.ground}) <= 0.0:
			continue
		var available: bool = g._space.local_enterable({"node": site.node_ref, "edge": "", "mode": "FOOT", "local_ref": id, "point_xy": site.xy})
		result.local_sites.append({"site_ref": id, "node_ref": site.node_ref, "xy": site.xy.duplicate(), "position_ref": site.get("position_ref", ""), "cover_ref": site.get("cover_ref", ""), "observed_at": g._state.time,
			"condition": "AVAILABLE" if available else "UNAVAILABLE"})
	# Existing personal covers are discovered only within the body's local radius.
	for id: String in g.participants._covers:
		var cover: Dictionary = g.participants._covers[id]
		if g._space._local_position_refs.has(id):
			var seen: bool = false
			for site: Dictionary in result.local_sites:
				seen = seen or site.get("position_ref", site.get("cover_ref", "")) == id or site.get("cover_ref", "") == id
			if not seen:
				continue
		if cover.node == source.spatial.node and cover.available and StateDistance(g._space.xy(source), cover.xy) <= float(g.participants.rules.local_radius_km):
			result.cover_refs.append(id)
	return result

func validate_gun(actor: String, values: Dictionary) -> Dictionary:
	var g: RefCounted = _g()
	if g._state.public_pending():
		return g._state.pending_view()
	var gun: Dictionary = guns.get(values.get("gun_ref", ""), {})
	if _tickets.size() > 60 or gun.is_empty() or not g._state.units.has(gun.unit_ref) or values.get("gun_action", "") not in ["deploy", "fire", "stop", "pack", "reload"]:
		return _reject("existing_gun_and_supported_crew_action_required")
	var unit: Dictionary = g._state.units[gun.unit_ref]
	if not g.operations.permits_ground_fire(str(unit.id), actor):
		return _reject("gun_unit_is_assigned_to_another_existing_executor")
	if not _free(unit) or not _crew_available(gun) or str(unit.spatial.edge) != "" or not unit.spatial.path.is_empty() and values.gun_action != "pack":
		return _reject("actual_stationary_free_crew_and_equipment_required")
	if values.gun_action in ["deploy", "reload"] and gun.state in ["FIRING", "RELOADING", "DEPLOYING", "PACKING"]:
		return _reject("existing_gun_task_in_progress")
	if values.gun_action == "reload" and (gun.state == "PACKED" or _unreserved(unit) <= 0.000001):
		return _reject("deployed_gun_and_actual_ammunition_required")
	if values.gun_action == "fire":
		if gun.state != "READY" or float(gun.ready) <= 0.000001 or not _positive(values.get("missions", 1)) or int(values.get("missions", 1)) > 8:
			return _reject("prepared_gun_ammunition_and_bounded_missions_required")
		if values.get("direct", false):
			var target: String = str(values.get("target_ref", ""))
			var source: Dictionary = unit.duplicate(true)
			source.weapon.range_km = float(gun.profile.range_km)
			if not g._state.units.has(target) or g._state.units[target].side == unit.side or fire_solution(source, target).is_empty():
				return _reject("direct_gun_fire_requires_actual_visible_target")
			return {"ok": true}
		var claim: Dictionary = _target_claim(actor, str(values.get("claim_ref", "")))
		if claim.is_empty() or not claim.claimed_value.get("node_ref", "") in g._space._nodes or not claim.claimed_value.get("xy") is Array or claim.claimed_value.xy.size() != 2:
			return _reject("received_position_report_required_for_indirect_fire")
		if StateDistance(g._space.xy(unit), claim.claimed_value.xy) > float(gun.profile.range_km):
			return _reject("reported_position_outside_gun_range")
	return {"ok": true}

func _target_claim(actor: String, id: String) -> Dictionary:
	for claim: Dictionary in _g()._state.information_port.get_ref().knowledge(actor).get("entries", []):
		if claim.entry_id == id and claim.fact_kind in ["ground_contact", "air_contact"] and float(claim.reliability) > 0.0:
			return claim
	return {}

func gun_action(actor: String, id: String, values: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_gun(actor, values)
	if not valid.ok:
		return valid
	var gun: Dictionary = guns[values.gun_ref]
	if gun.state == "PACKED" and values.gun_action in ["pack", "stop"]:
		return {"ok": true, "status": "ALREADY_PACKED"}
	_g()._lod.materialize_leaf(str(gun.unit_ref), "actual_gun_crew_task")
	gun.revision += 1
	gun.issuer = actor
	gun.fire_ref = id
	if values.gun_action in ["stop", "pack"]:
		gun.state = "PACKING" if values.gun_action == "pack" else "READY"
		if values.gun_action == "pack":
			_queue("GUN_PACK", str(gun.id), id, float(gun.profile.deploy_seconds) * 0.5, {"revision": gun.revision})
	elif values.gun_action == "deploy":
		gun.state = "DEPLOYING"
		gun.node_ref = _g()._state.units[gun.unit_ref].spatial.node
		_queue("GUN_READY", str(gun.id), id, float(gun.profile.deploy_seconds), {"revision": gun.revision})
	elif values.gun_action == "reload":
		gun.state = "RELOADING"
		_queue("GUN_RELOAD", str(gun.id), id, float(gun.profile.reload_seconds), {"revision": gun.revision})
	else:
		gun.state = "FIRING"
		gun.direct_target = str(values.get("target_ref", "")) if values.get("direct", false) else ""
		gun.claim = {} if values.get("direct", false) else _target_claim(actor, str(values.claim_ref)).duplicate(true)
		gun.remaining = int(values.get("missions", 1))
		_queue("GUN_FIRE", str(gun.id), id, float(gun.profile.cycle_seconds), {"revision": gun.revision})
	_g()._state.wake(str(_g()._state.units[gun.unit_ref].area_id))
	return {"ok": true}

func _crew_available(gun: Dictionary) -> bool:
	var unit: Dictionary = _g()._state.units.get(gun.unit_ref, {})
	return not unit.is_empty() and float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective)) >= _gun_crew(str(unit.id)) + (float(gun.profile.crew) if gun.state in ["PACKED", "INTERRUPTED"] else 0.0) and float(unit.get("serviceable_equipment", unit.equipment)) >= _equipment_claims(str(unit.id)) and float(unit.suppression) < 0.8 and float(unit.effective) > 0.0

func movement_blocked(unit: String) -> bool:
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit and gun.state != "PACKED":
			return true
	return false

func _queue(kind: String, subject: String, cause: String, seconds: float, data: Dictionary) -> void:
	_serial += 1
	var id: String = "tactical_%d" % _serial
	var ticket: Dictionary = {"kind": kind, "subject": subject, "cause_ref": cause, "due": _g()._state.time + maxf(1.0, seconds)}
	ticket.merge(data)
	ticket.started_at = _g()._state.time
	if kind == "OBSERVE":
		var body: Dictionary = _g().participants._member(subject)
		body.combat_revision = int(body.get("combat_revision", 0)) + 1
		ticket.body_revision = body.combat_revision
		ticket.body_unit_ref = _g().participants._units[subject]
	if weapons.has(subject):
		ticket.unit_ref = weapons[subject].unit_ref
		ticket.binding_revision = weapons[subject].get("binding_revision", 0)
		if kind in ["RELOAD", "AIM"]:
			weapons[subject].operation_ref = id
			weapons[subject].started_at = _g()._state.time
	elif guns.has(subject):
		ticket.unit_ref = guns[subject].unit_ref
	_tickets[id] = ticket
	assert(_g()._state.schedule_event(id, float(ticket.due), "gameplay", {"tactical_ref": id}))

func accepts(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and payload.get("tactical_ref", "") == id and _tickets.has(id) and float(_tickets[id].due) == due

func process(event: Dictionary) -> Dictionary:
	var ticket: Dictionary = _tickets[event.id]
	_tickets.erase(event.id)
	var g: RefCounted = _g()
	var changed: Array = []
	if ticket.kind == "SUPPLY_HANDOVER":
		if supply_jobs.get(ticket.subject, {}).get("id", "") == ticket.supply_ref:
			_finish_supply(str(ticket.subject), true)
			changed.append(ticket.subject)
	elif ticket.kind in ["MANOEUVRE_CHECK", "MANOEUVRE_DEADLINE"]:
		var order: Dictionary = manoeuvres.get(ticket.subject, {})
		if not order.is_empty() and order.id == ticket.manoeuvre_ref and manoeuvre_active(str(ticket.subject)):
			if ticket.kind == "MANOEUVRE_DEADLINE":
				if not order.returning:
					_stop_manoeuvre(str(ticket.subject), "original_deadline_expired", str(ticket.cause_ref))
					if fire_orders.get(ticket.subject, {}).get("manoeuvre_ref", "") == order.id:
						fire_orders[ticket.subject].fire_mode = "watch"
			elif order.revision == ticket.revision and order.check_ref == event.id:
				order.check_ref = ""
				_update_manoeuvre(str(ticket.subject))
				if g._state.units.has(ticket.subject):
					after_manoeuvre_movement(g._state.units[ticket.subject])
			elif order.check_ref == event.id:
				order.check_ref = "" # Retire only this stale reference, never a newer check.
			changed.append(ticket.subject)
	elif ticket.kind == "SQUAD_END":
		if fire_orders.get(ticket.subject, {}).get("input_ref", "") == ticket.input_ref:
			fire_orders.erase(ticket.subject)
			changed.append(ticket.subject)
	elif str(ticket.kind).begins_with("GUN_"):
		return _gun_event(ticket, str(event.id))
	elif g.participants._units.has(ticket.subject):
		var actor: String = str(ticket.subject)
		var unit: Dictionary = g.participants._physical_unit(actor)
		changed.append(unit.id)
		if ticket.kind == "OBSERVE":
			var body: Dictionary = g.participants._member(actor)
			if ticket.get("body_unit_ref", "") == g.participants._units[actor] and ticket.get("body_revision", -1) == body.get("combat_revision", 0) and str(body.action_ref).is_empty() and g.participants.can_intend(actor):
				body.combat_busy_until = g._state.time
				_observe(actor, str(ticket.node_ref), str(event.id))
		elif weapons.has(actor) and weapons[actor].revision == ticket.revision and weapons[actor].unit_ref == ticket.get("unit_ref", "") and weapons[actor].get("binding_revision", 0) == ticket.get("binding_revision", -1):
			var weapon: Dictionary = weapons[actor]
			if not g.participants.can_intend(actor) or not str(g.participants._member(actor).action_ref).is_empty() or weapon.unit_ref != unit.id or not _free(unit):
				_stop(weapon, "GROUP" if weapon.mode == "GROUP" else "CEASE")
			elif ticket.kind == "RELOAD":
				var carried: Dictionary = ammunition_custody.get(actor, {})
				if carried.get("status", "") == "HELD":
					var taken: float = minf(maxf(0.0, float(weapon.profile.magazine) - float(weapon.ready)), float(carried.amount))
					carried.amount -= taken
					weapon.ready += taken
					var own_part: Dictionary = actor_part(actor)
					if not own_part.is_empty():
						own_part.ammunition += taken
				if stock_contact(actor):
					weapon.ready += minf(maxf(0.0, float(weapon.profile.magazine) - float(weapon.ready)), _reload_available(actor))
				weapon.status = "READY" if float(weapon.ready) > 0.000001 else "EMPTY"
				rejoin_local_duty(actor)
			elif ticket.kind == "AIM":
				weapon.status = "READY" if float(weapon.ready) > 0.000001 else "EMPTY"
				var target: String = str(weapon.get("group_target", "")) if weapon.mode == "GROUP" else str(weapon.get("target_ref", ""))
				if visible(actor, target):
					g._state.information_port.get_ref().record_ground_observation(self, actor, target, str(event.id) + "_contact")
			elif ticket.kind == "CEASE":
				_stop(weapon, "CEASE")
			g.participants._emit(actor, "weapon_operation_finished", str(ticket.cause_ref), {"weapon": weapon.duplicate(true)})
	for id: String in changed:
		if g._state.units.has(id):
			g._state.wake(str(g._state.units[id].area_id))
	return {"changed": changed, "retired": [], "record": {"kind": ticket.kind, "cause_ref": ticket.cause_ref}}

func _observe(actor: String, node: String, id: String) -> void:
	var g: RefCounted = _g()
	var own: Dictionary = g.participants._physical_unit(actor)
	if g.participants.body_spatial(actor).node == node and g.participants.observation_opportunity(actor, str(own.id)):
		g._state.information_port.get_ref().record_ground_observation(self, actor, str(own.id), id + "_cover", "cover")
	var candidates: Array[String] = g._space.combat_ids(str(g._space._nodes[node].cell))
	var count: int = 0
	for target: String in candidates:
		if count >= 16:
			break
		var other: Dictionary = g._state.units[target]
		if not other.has("spatial") or other.side == own.side:
			continue
		count += 1
		if visible(actor, target):
			g._state.information_port.get_ref().record_ground_observation(self, actor, target, id + "_" + target)
	for person: String in g.participants._units:
		if person != actor and not g.participants.visible_person(actor, person).is_empty():
			g._state.information_port.get_ref().record_person_observation(g.participants, actor, person, id + "_person_" + person)
	g.participants._emit(actor, "personal_observation_completed", id, {"node_ref": node, "observed_at": g._state.time})

func _gun_event(ticket: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _g()
	var gun: Dictionary = guns[ticket.subject]
	var unit: Dictionary = g._state.units.get(gun.unit_ref, {})
	var changed: Array = []
	if gun.revision != ticket.revision or unit.is_empty() or gun.unit_ref != ticket.get("unit_ref", ""):
		return {"changed": [], "retired": [], "record": {"kind": "OBSOLETE_GUN_ACTION"}}
	changed.append(unit.id)
	if not _crew_available(gun) or not _free(unit) or unit.spatial.node != gun.node_ref or str(unit.spatial.edge) != "" or not unit.spatial.path.is_empty() and ticket.kind != "GUN_PACK":
		gun.state = "INTERRUPTED"
		gun.reason = "actual_crew_equipment_position_or_duty_changed"
	elif ticket.kind in ["GUN_READY", "GUN_RELOAD"]:
		gun.ready += minf(float(gun.profile.rounds_per_mission) - float(gun.ready), _unreserved(unit))
		gun.state = "READY" if float(gun.ready) > 0.000001 else "EMPTY"
	elif ticket.kind == "GUN_PACK":
		gun.state = "PACKED"
		gun.ready = 0.0
	elif ticket.kind == "GUN_FIRE":
		if gun.get("direct_target", "") != "":
			var target: String = str(gun.direct_target)
			var source: Dictionary = unit.duplicate(true)
			source.weapon.range_km = float(gun.profile.range_km)
			if not g._state.units.has(target) or fire_solution(source, target).is_empty():
				gun.state = "READY"
				gun.reason = "direct_target_no_longer_visible"
				return {"changed": changed, "retired": [], "record": {"kind": "DIRECT_GUN_TARGET_LOST"}}
			gun.claim = {"claimed_value": fire_solution(source, target), "observed_at": g._state.time, "entry_id": "gun_sight_" + id}
		var used: float = minf(float(gun.ready), minf(float(unit.ammunition), float(gun.profile.rounds_per_mission)))
		if used <= 0.000001:
			gun.state = "EMPTY"
			gun.reason = "actual_ammunition_unavailable"
			g.operations.on_unit(str(unit.id), true)
			return {"changed": changed, "retired": [], "record": {"kind": "GUN_WAITING_AMMUNITION"}}
		gun.ready -= used
		gun.spent += used
		unit.ammunition -= used
		unit.ammo_spent += used
		g._state.totals.ammo_spent += used
		# Impact stays at the received coordinates; targets are examined only inside
		# that local effect area. Hidden coordinates never choose the aim point.
		var point: Array = gun.claim.claimed_value.xy
		var node: String = str(gun.claim.claimed_value.node_ref)
		var local: Array[String] = State.sorted_ids(g._state.area_units[g._space._nodes[node].cell])
		var affected: Array[String] = []
		for target: String in local:
			for location: Array in ground_positions(target, true):
				if StateDistance(location, point) <= float(gun.profile.radius_km):
					affected.append(target)
					break
		var detached: Array[Dictionary] = []
		for body: Dictionary in g.participants.detached_targets(str(g._space._nodes[node].cell)).values():
			if StateDistance(body.xy, point) <= float(gun.profile.radius_km):
				detached.append(body)
		var shares: float = maxf(1.0, float(affected.size() + detached.size()))
		if used > 0.0:
			g._space.damage_positions_at(node, point, float(gun.profile.radius_km), used, id)
			for target: String in affected:
				if g._lod.has_leaf(target):
					var representation: Dictionary = g._lod.materialize_leaf(target, "local_indirect_fire_effect")
					changed.append_array(representation.get("changed", []))
				if g._state.units.has(target):
					g._lod._kernel.direct_fire(g._state, g._state.units[target], used / shares, float(gun.profile.lethality), id, point, float(gun.profile.radius_km), false)
					if target not in changed:
						changed.append(target)
			for body: Dictionary in detached:
				var result: Dictionary = g.participants.external_damage(str(body.actor_ref), used / shares * float(gun.profile.lethality) * float(body.exposure), id, "local_indirect_fire")
				for holder: String in result.changed:
					if holder not in changed:
						changed.append(holder)
		gun.remaining -= 1
		gun.last_fire = {"at": g._state.time, "rounds": used, "aim_xy": point.duplicate(), "observed_at": gun.claim.observed_at, "fire_ref": id, "command_ref": gun.fire_ref}
		gun.last_fire.partial = used + 0.000001 < float(gun.profile.rounds_per_mission)
		gun.state = "EMPTY"
		# Another mission requires actual reload time and remaining ammunition.
		if int(gun.remaining) > 0 and _unreserved(unit) > 0.000001:
			gun.state = "RELOADING"
			_queue("GUN_NEXT", str(gun.id), str(ticket.cause_ref), float(gun.profile.reload_seconds), {"revision": gun.revision})
	elif ticket.kind == "GUN_NEXT":
		gun.ready += minf(float(gun.profile.rounds_per_mission) - float(gun.ready), _unreserved(unit))
		gun.state = "FIRING" if float(gun.ready) > 0.000001 else "EMPTY"
		if gun.state == "FIRING":
			_queue("GUN_FIRE", str(gun.id), str(ticket.cause_ref), float(gun.profile.cycle_seconds), {"revision": gun.revision})
	for target: String in changed:
		if g._state.units.has(target):
			g.operations.on_unit(target, true)
			g._state.wake(str(g._state.units[target].area_id))
	return {"changed": changed, "retired": [], "record": {"kind": "GUN_ACTION", "gun_ref": gun.id, "state": gun.state, "claim_ref": gun.get("claim", {}).get("entry_id", "")}}

func unit_fact(unit: String) -> Dictionary:
	var result: Dictionary = {"fire_order": fire_orders.get(unit, {}).duplicate(true), "guns": [], "weapon_range_km": _g()._state.units[unit].weapon.range_km}
	result.local_support = local_support_report(unit)
	if manoeuvres.has(unit):
		result.manoeuvre = manoeuvre_report(unit)
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit:
			var actual: Dictionary = gun.duplicate(true)
			actual.actual_node_ref = _g()._state.units[unit].spatial.node
			actual.actual_xy = _g()._space.xy(_g()._state.units[unit])
			result.guns.append(actual)
	if not result.guns.is_empty():
		result.unreserved_ammunition = _unreserved(_g()._state.units[unit])
	return result

func local_support_report(unit_id: String) -> Dictionary:
	var g: RefCounted = _g()
	var unit: Dictionary = g._state.units[unit_id]
	var source: Dictionary = unit if not manoeuvre_active(unit_id) else part_source(unit, manoeuvres[unit_id].parts[manoeuvres[unit_id].stock_part])
	var result: Dictionary = {"handling": {}, "parts": {}, "helpers": {}}
	result.last_handover = unit.get("local_ammunition_handover", {}).duplicate(true)
	if supply_jobs.has(unit_id):
		var job: Dictionary = supply_jobs[unit_id]
		result.handling = {"id": job.id, "status": job.status, "source_ref": job.source_ref, "target_ref": job.target_ref}
	if manoeuvre_active(unit_id):
		for key: String in ["front", "rear"]:
			var part: Dictionary = manoeuvres[unit_id].parts[key]
			if StateDistance(g._space.xy(source), g._space.xy(part_source(unit, part))) <= float(g.participants.rules.local_radius_km) and g._space.local_place(source.spatial) == g._space.local_place(part.spatial):
				result.parts[key] = {"part_ref": part.id, "ammunition": part.ammunition, "available": maxf(0.0, float(part.ammunition) - _part_ready(part)), "role": part.role, "xy": g._space.xy(part_source(unit, part))}
	for person: String in g.participants.local_rescues:
		var rescue: Dictionary = g.participants.local_rescues[person]
		if rescue.unit_ref != unit_id:
			continue
		var anchor: Dictionary = {"node": g.participants._member(person).anchor_node, "sight_ref": g._space.sight_ref(g.participants.body_spatial(person)), "xy": g.participants.position(person), "ground": g.participants.body_ground(person)}
		if g._space.observation_at(source, anchor) > 0.0:
			result.helpers[person] = {"id": rescue.id, "status": rescue.status, "patient_ref": rescue.patient_ref, "xy": anchor.xy, "local_ref": g._space.local_place(g.participants.body_spatial(person)), "action_pending": str(g.participants._member(person).action_ref) != ""}
	return result

func validate_member_transfer(actor: String, destination: String, disposition: String = "carry") -> Dictionary:
	if _carried_amount(actor) > 0.000001 or _g().participants._member(actor).get("local_duty", false) or supply_jobs.has(str(_g().participants._units[actor])):
		return _reject("settle_actual_local_cargo_or_duty_before_membership_handover")
	if disposition not in ["carry", "leave"]:
		return _reject("explicit_weapon_carry_or_leave_required")
	if not weapons.has(actor):
		return {"ok": true}
	var weapon: Dictionary = weapons[actor]
	if weapon.get("holder_ref", actor) != actor:
		return {"ok": true} # A left weapon is not acquired by changing membership.
	var source_id: String = str(_g().participants._units[actor])
	var source: Dictionary = _g()._lod.preview_leaf(source_id)
	var target: Dictionary = _g()._lod.preview_leaf(destination) if _g()._lod.has_leaf(destination) else {}
	if weapon.unit_ref != source.id or target.is_empty() or target.side != source.side or str(source.spatial.edge) != "" or str(target.spatial.edge) != "":
		return _reject("weapon_handover_requires_existing_stationary_same_side_holders")
	if StateDistance(_g().participants.position(actor), _g()._space.xy(target)) > float(_g().participants.rules.local_radius_km):
		return _reject("weapon_handover_requires_actual_contact")
	if disposition == "carry" and (float(source.get("serviceable_equipment", source.equipment)) < _equipment_claims(str(source.id)) or prepared_total(str(source.id)) > float(source.ammunition) + 0.000001):
		return _reject("actual_weapon_or_prepared_ammunition_unavailable")
	return {"ok": true}

func prepared_total(unit: String) -> float:
	if manoeuvre_active(unit):
		return float(manoeuvres[unit].parts.front.ammunition) + float(manoeuvres[unit].parts.rear.ammunition) + _carried_total(unit) + _detached_ready(unit)
	var result: float = _carried_total(unit)
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == unit:
			result += float(weapon.ready)
	for gun: Dictionary in guns.values():
		if gun.unit_ref == unit:
			result += float(gun.ready)
	return result

func member_moved(actor: String, source: String, destination: String, disposition: String = "carry", pooled: bool = false, cause: String = "") -> void:
	_stop_manoeuvre(source, "actual_member_reassigned", cause)
	var body: Dictionary = _g().participants._member(actor)
	body.combat_revision = int(body.get("combat_revision", 0)) + 1
	body.combat_busy_until = _g()._state.time
	if not weapons.has(actor):
		return
	var weapon: Dictionary = weapons[actor]
	_stop(weapon, "CEASE")
	weapon.binding_revision = int(weapon.get("binding_revision", 0)) + 1
	if weapon.get("holder_ref", actor) != actor or weapon.unit_ref != source:
		return
	var here: Array = _g().participants.position(actor)
	if disposition == "leave":
		weapon.holder_ref = "unit:" + source
		weapon.custody = "LEFT"
		weapon.location_ref = "unit:" + source
		weapon.location_xy = here # Last handover location, not a second moving position.
		weapon.node_ref = _g()._state.units[source].spatial.node
		weapon.mode = "RELEASED"
	else:
		if not pooled:
			# Prepared ammunition changes ledger owner once; it is never extra stock.
			var a: Dictionary = _g()._state.units[source]
			var b: Dictionary = _g()._state.units[destination]
			var share: float = float(weapon.profile.equipment_share)
			a.equipment -= share
			b.equipment += share
			if a.has("serviceable_equipment"):
				a.serviceable_equipment -= share
				b.serviceable_equipment = float(b.get("serviceable_equipment", b.equipment - share)) + share
			a.ammunition -= float(weapon.ready)
			b.ammunition += float(weapon.ready)
		weapon.unit_ref = destination
		weapon.custody = "HELD"
		weapon.holder_ref = actor
		weapon.location_ref = "person:" + actor
	weapon.last_handover = {"source": source, "destination": destination, "at": _g()._state.time,
		"cause_ref": cause, "disposition": disposition, "prepared": weapon.ready, "equipment_share": weapon.profile.equipment_share, "pooled": pooled, "xy": here}
	_note_cover_mover(actor, "TRANSFERRED")

func unit_merged(source: String, destination: String) -> void:
	_finish_supply(source, false, "actual_unit_merged")
	for cargo: Dictionary in ammunition_custody.values():
		if cargo.unit_ref == source:
			cargo.unit_ref = destination
			cargo.revision += 1
	for weapon: Dictionary in weapons.values():
		if weapon.unit_ref == source:
			_stop(weapon, "CEASE")
			weapon.unit_ref = destination
			weapon.binding_revision = int(weapon.get("binding_revision", 0)) + 1
			if weapon.get("custody", "HELD") == "LEFT":
				weapon.holder_ref = "unit:" + destination
				weapon.location_ref = "unit:" + destination
	for gun: Dictionary in guns.values():
		if gun.unit_ref == source:
			gun.revision += 1
			gun.unit_ref = destination
			if gun.state != "PACKED":
				gun.state = "INTERRUPTED"
			gun.reason = "actual_unit_handover"
	fire_orders.erase(source)

func body_action_started(actor: String) -> void:
	if separated_actor(actor):
		_stop_manoeuvre(str(_g().participants._units[actor]), "member_started_other_body_duty", actor)
	var body: Dictionary = _g().participants._member(actor)
	body.combat_busy_until = _g()._state.time
	body.combat_revision = int(body.get("combat_revision", 0)) + 1
	if not weapons.has(actor) or weapons[actor].mode == "RELEASED":
		return
	var weapon: Dictionary = weapons[actor]
	_stop(weapon, "GROUP" if weapon.mode == "GROUP" else "CEASE")

func _note_cover_mover(actor: String, status: String) -> void:
	for order: Dictionary in fire_orders.values():
		if order.get("moving", {}).has(actor):
			order.moving[actor].status = status
			order.moving[actor].at = _g()._state.time

func body_action_finished(actor: String, action_ref: String, status: String) -> void:
	# Only a real reunion releases the temporary body share; nothing is refilled.
	rejoin_local_duty(actor)
	_update_custody(str(_g().participants._units.get(actor, "")))
	for order: Dictionary in fire_orders.values():
		if order.get("moving", {}).get(actor, {}).get("action_ref", "") == action_ref:
			order.moving[actor].status = status
			order.moving[actor].at = _g()._state.time
	var unit: String = str(_g().participants._units.get(actor, ""))
	if manoeuvre_active(unit):
		var order: Dictionary = manoeuvres[unit]
		if order.get("moving", {}).get(actor, {}).get("action_ref", "") == action_ref:
			order.moving[actor].status = status
			order.moving[actor].at = _g()._state.time
			_schedule_manoeuvre(order)

static func StateDistance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["weapons", "guns", "fire_orders", "manoeuvres", "ammunition_custody", "supply_jobs", "_tickets", "_serial"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)

func validate_runtime() -> bool:
	if weapons.size() > 6 or guns.size() > 2 or manoeuvres.size() > 4 or ammunition_custody.size() > 6 or supply_jobs.size() > 4 or _serial < 0:
		return false
	for actor: String in ammunition_custody:
		var cargo: Dictionary = ammunition_custody[actor]
		if not _g().participants._units.has(actor) or cargo.get("id", "") != "carry_ammunition:" + actor or not _g()._state.knows_unit(str(cargo.get("unit_ref", ""))) or str(cargo.get("source_ref", "")).is_empty() or not _nonnegative(cargo.get("amount")) or int(cargo.get("revision", -1)) < 0 or cargo.get("status", "") not in ["HELD", "STRANDED"]:
			return false
		if cargo.status == "HELD" and (cargo.holder_ref != actor or cargo.unit_ref != _g().participants._units[actor]):
			return false
		if cargo.status == "STRANDED" and (cargo.holder_ref != "ground:" + str(cargo.id) or not cargo.get("xy") is Array or cargo.xy.size() != 2 or not cargo.get("spatial") is Dictionary or not _g()._space.valid_local_spatial(cargo.spatial)):
			return false
	for unit_id: String in supply_jobs:
		var job: Dictionary = supply_jobs[unit_id]
		if job.get("unit_ref", "") != unit_id or not _g()._state.units.has(unit_id) or job.get("status", "") != "PENDING" or not _positive(job.get("quantity")) or not _nonnegative(job.get("started_at")) or not _positive(job.get("due")) or float(job.due) < float(job.started_at) or not job.get("people") is Array or not job.get("part_refs") is Array or not job.get("handlers") is Array or job.handlers.size() > 4:
			return false
		var ticket: Dictionary = _tickets.get(job.get("event_ref", ""), {})
		if ticket.get("supply_ref", "") != job.get("id", "missing") or ticket.get("subject", "") != unit_id or ticket.get("kind", "") != "SUPPLY_HANDOVER" or float(ticket.get("due", -1.0)) != float(job.due):
			return false
		for person: Variant in job.people:
			if not person is String or _g().participants._units.get(person, "") != unit_id:
				return false
			var action: Dictionary = _g().participants._actions.get(_g().participants._member(person).action_ref, {})
			if action.get("supply_ref", "") != job.id or action.get("mode", "") != "AMMO_HANDLING" or action.get("status", "") != "PENDING":
				return false
		for person: Variant in job.handlers:
			if not person is String or _g().participants._units.get(person, "") != unit_id or _g().participants._member(person).get("supply_job_ref", "") != job.id:
				return false
	for unit_id: String in manoeuvres:
		var order: Dictionary = manoeuvres[unit_id]
		if order.get("unit_ref", "") != unit_id or order.get("id", "") == "" or not order.get("path") is Array or order.path.is_empty() or order.path.size() > 4 or int(order.get("leg_index", -1)) < 0 or int(order.leg_index) >= order.path.size():
			return false
		if not order.get("parts") is Dictionary or order.parts.size() != 2 or not order.parts.has("front") or not order.parts.has("rear") or order.get("lead_part", "") not in ["front", "rear"] or order.get("stock_part", "") != "rear":
			return false
		if order.get("travel_kind", "") not in ["ROAD", "LOCAL"] or order.get("phase", "") not in ["PREPARE", "RETURN_PREPARE", "GUARD_PREPARING_FIRE", "FRONT_MOVING", "FRONT_RETURNING", "FRONT_PREPARING_FIRE", "REAR_MOVING", "REAR_RETURNING", "FRONT_ENTERING", "REAR_ENTERING", "STOPPED", "COMPLETE", "REGROUPED"]:
			return false
		if not manoeuvre_active(unit_id):
			continue
		if not _g()._state.units.has(unit_id) or _g()._lod.representation_of(unit_id) != unit_id or not order.get("roster") is Array or not _nonnegative(order.get("started_at")) or not _nonnegative(order.get("deadline")) or float(order.deadline) < float(order.started_at) or int(order.get("revision", -1)) < 0:
			return false
		var unit: Dictionary = _g()._state.units[unit_id]
		var members: Dictionary = {}
		var anonymous: float = 0.0
		var ammo: float = 0.0
		var equipment: float = 0.0
		var serviceable: float = 0.0
		for key: String in ["front", "rear"]:
			if not order.parts[key] is Dictionary:
				return false
			var part: Dictionary = order.parts[key]
			if part.get("id", "") != unit_id + ":" + str(order.id) + ":" + key or part.get("source_ref", "") != unit_id or part.get("unit_ref", "") != unit_id or not part.get("members") is Array or part.members.size() > 4 or not part.get("spatial") is Dictionary or int(part.get("revision", -1)) < 0:
				return false
			if part.get("role", "") not in ["PREPARING", "WATCH", "FIRE", "MOVING", "ENTERING"]:
				return false
			for field: String in ["anonymous", "initial_anonymous", "anonymous_loss", "ammunition", "ammo_spent", "equipment", "serviceable", "equipment_lost", "ready_at", "fatigue", "cohesion", "suppression", "pressure_at", "settled_at", "distance_moved", "movement_seconds"]:
				if not _nonnegative(part.get(field)):
					return false
			if absf(float(part.initial_anonymous) - float(part.anonymous) - float(part.anonymous_loss)) > 0.000001 or float(part.serviceable) > float(part.equipment) + 0.000001 or _part_ready(part) > float(part.ammunition) + 0.000001:
				return false
			if not _g()._space._nodes.has(part.spatial.get("node", "")) or not part.spatial.get("path") is Array or part.spatial.path.size() > 1:
				return false
			if not _g()._space.valid_local_spatial(part.spatial) or part.spatial.get("local_path", []).size() > 1:
				return false
			if part.role in ["MOVING", "ENTERING"] and part.get("destination_node", "") not in [order.leg_from, order.leg_to]:
				return false
			if str(part.spatial.get("local_edge", "")) != "" and (order.travel_kind != "LOCAL" or part.spatial.local_edge != order.edge_ref):
				return false
			if str(part.spatial.get("edge", "")) != "":
				if part.spatial.edge != order.get("edge_ref", "") or not _g()._space._edges.has(part.spatial.edge) or not _nonnegative(part.spatial.get("progress")) or float(part.spatial.progress) > float(_g()._space._edges[part.spatial.edge].length_km):
					return false
			for person: Variant in part.members:
				if not person is String or members.has(person) or _g().participants._units.get(person, "") != unit_id:
					return false
				members[person] = true
				var body: Dictionary = _g().participants._member(person)
				if body.get("part_ref", "") != part.id:
					return false
				if part.role == "MOVING" and (body.get("part_action_ref", "") != part.get("action_ref", "") or body.get("part_revision", -1) != part.revision or body.state != "PART_MOVING"):
					return false
				if part.role == "ENTERING" and (body.state != "PART_ENTERING" or body.get("part_entry_ref", "") != part.id or order.travel_kind != "LOCAL"):
					return false
				if part.role in ["MOVING", "ENTERING"] and StateDistance(_g().participants.position(person), _g()._space.xy(part_source(unit, part))) > 0.000001:
					return false
			anonymous += float(part.anonymous)
			ammo += float(part.ammunition)
			equipment += float(part.equipment)
			serviceable += float(part.serviceable)
		if members.size() != unit.get("gameplay_personnel", {}).get("members", {}).size() or members.size() != order.roster.size() or absf(anonymous - float(unit.get("gameplay_personnel", {}).get("anonymous", -1.0))) > 0.000001 or ammo > float(unit.ammunition) + 0.000001 or equipment > float(unit.equipment) + 0.000001 or serviceable > float(unit.serviceable_equipment) + 0.000001:
			return false
		for edge: Variant in order.path:
			if not _manoeuvre_edges(order).has(edge):
				return false
		var places: bool = not _g()._space.local_endpoint(str(order.get("leg_from", ""))).is_empty() and not _g()._space.local_endpoint(str(order.get("leg_to", ""))).is_empty() if order.travel_kind == "LOCAL" else _g()._space._nodes.has(order.get("leg_from", "")) and _g()._space._nodes.has(order.get("leg_to", ""))
		if not _manoeuvre_edges(order).has(order.get("edge_ref", "")) or not places:
			return false
		if order.get("check_ref", "") != "" and not _tickets.has(order.check_ref):
			return false
	var holdings: Dictionary = {}
	for cargo: Dictionary in ammunition_custody.values():
		holdings[cargo.unit_ref] = true
	for weapon: Dictionary in weapons.values():
		if not _g().participants._units.has(weapon.get("actor_ref", "")) or weapon.get("custody", "") not in ["HELD", "LEFT"] or weapon.get("source_ref", "").is_empty():
			return false
		if weapon.custody == "HELD" and (weapon.holder_ref != weapon.actor_ref or weapon.unit_ref != _g().participants._units[weapon.actor_ref]):
			return false
	for item: Dictionary in weapons.values() + guns.values():
		if not _g()._state.knows_unit(str(item.get("unit_ref", ""))) or not _nonnegative(item.get("ready")):
			return false
		holdings[item.unit_ref] = true
	for unit_id: String in holdings:
		var unit: Dictionary = _g()._state.units[unit_id] if _g()._state.units.has(unit_id) else _g()._lod.preview_leaf(unit_id)
		if prepared_total(unit_id) > float(unit.ammunition) + 0.000001:
			return false
	return true
