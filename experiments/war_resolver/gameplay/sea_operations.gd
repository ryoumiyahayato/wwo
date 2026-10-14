extends RefCounted
## Bounded surface units consume authoritative water connections, not land roads.
var _owner: WeakRef
var vessels: Dictionary = {}
var missions: Dictionary = {}
var _tickets: Dictionary = {}
var _serial: int = 0
var _report_serial: int = 0
const Support = preload("res://experiments/war_resolver/gameplay/sea_support.gd")
const Transport = preload("res://experiments/war_resolver/gameplay/sea_transport.gd")
const Recovery = preload("res://experiments/war_resolver/gameplay/sea_recovery.gd")
var support: Support = Support.new()
var freight: Transport = Transport.new()
var recovery: Recovery = Recovery.new()
const MAX_VESSELS: int = 2
const MAX_MISSIONS: int = 64
const MAX_PATH: int = 8
var rules: Dictionary = {"contact_seconds": 5.0, "observation_seconds": 30.0, "patrol_seconds": 120.0,
	"speed_km_s": 0.01, "fuel_per_second": 0.004, "draft_km": 0.003,
	"sensor_range_km": 0.22, "precision_km": 0.025, "mobility_integrity": 0.2,
	"weapon_integrity": 0.35, "port_service_seconds": 60.0, "fuel_capacity": 8.0, "ammo_capacity": 20.0,
	"rounds": 2.0, "range_km": 0.18, "shore_range_km": 0.2, "arc_degrees": 300.0,
	"fire_interval_seconds": 15.0, "surface_damage_per_round": 0.1, "shore_lethality": 0.008, "report_interval_seconds": 30.0,
	"system_disabled_damage": 0.6, "escort_radius_km": 0.06, "escort_wait_seconds": 10.0, "escort_deadline_seconds": 1200.0}

func configure(gameplay: RefCounted) -> void:
	_owner = weakref(gameplay)
	support.configure(self)
	freight.configure(self)
	recovery.configure(self)

func admit(id: String, owner: String, port: String, depot: String, fuel: float, ammunition: float) -> bool:
	var g: RefCounted = _owner.get_ref()
	var logistics: RefCounted = g._state.logistics_port.get_ref()
	var structure: RefCounted = g._state.structure_port.get_ref()
	var info: RefCounted = g._state.information_port.get_ref()
	if g._state.time != 0.0 or vessels.size() >= MAX_VESSELS or vessels.has(id) or g.air.assets.has(id) or g._state.identity_reserved(id) or structure._people.has(id) or info._outboxes.has(id) or info._platform_sources.size() >= 6 or not structure.active(owner) or not g._space._nodes.has(port) or not g._space._nodes[port].get("port", false) or not logistics._depots.has(depot) or not structure._contains(str(logistics._depots[depot].allocation_scope), owner):
		return false
	var node: Dictionary = g._space._nodes[port]
	if node.get("land_supply_node", "") != logistics._depots[depot].get("node_ref", ""):
		return false
	var supplied: Dictionary = logistics.admit_air_asset(id, depot, fuel, ammunition)
	if not supplied.ok:
		return false
	vessels[id] = {"id": id, "owner": owner, "port": port, "depot": depot, "node": port, "xy": node.xy.duplicate(),
		"stock": supplied.stock, "integrity": 1.0, "status": "DOCKED", "version": 0, "mission_ref": "", "next_fire": 0.0,
		"heading_degrees": 0.0, "draft_km": rules.draft_km, "speed_km_s": rules.speed_km_s,
		"fuel_per_second": rules.fuel_per_second, "sensor_range_km": rules.sensor_range_km, "precision_km": rules.precision_km,
		"flooding": 0.0, "fire": 0.0, "mobility_damage": 0.0, "weapon_damage": 0.0, "damage_last_at": 0.0, "damage_version": 0,
		"damage_cause_ref": "", "damage_control_capacity": 1.0, "control_active": false, "control_effort": 0.0, "control_until": 0.0,
		"cargo_capacity": freight.rules.capacity, "cargo_ref": "", "port_job_ref": ""}
	logistics.replenish_asset(id, depot, "SPARES", float(support.rules.spares_capacity))
	vessels[id].initial_report = _status_value(vessels[id])
	return info.register_platform_source(id, owner, self)

func _authorized(actor: String, vessel: Dictionary) -> bool:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	var person: Dictionary = s.command_person(actor)
	return s.Roles.ROLES.find(str(person.role)) >= 3 and g.participants.can_intend(actor) and s._contains(str(person.formation_id), str(vessel.owner))

func _received(actor: String, target: String, node: String, shore: bool) -> bool:
	var info: RefCounted = _owner.get_ref()._state.information_port.get_ref()
	for entry: Dictionary in info.knowledge(actor).get("entries", []):
		if entry.subject_ref == target and float(entry.reliability) > 0.0 and entry.claimed_value.get("node_ref", "") == node and entry.fact_kind in (["air_contact"] if shore else ["sea_contact"]):
			return true
	return false

func validate(actor: String, target: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if not values.get("vessel_ref") is String or not vessels.has(values.vessel_ref):
		return _reject("existing_surface_vessel_required")
	var vessel: Dictionary = vessels[values.vessel_ref]
	if not _authorized(actor, vessel) or target != g._state.structure_port.get_ref().command_person(actor).formation_id:
		return _reject("naval_task_requires_current_experiment_owning_commander")
	if vessel.get("transfer_ref", "") != "" and values.get("operation", "") != "cancel_transshipment":
		return _reject("actual_cargo_transfer_occupies_both_vessels")
	if values.get("operation", "") == "rendezvous":
		return freight.validate_rendezvous(actor, vessel, values, id)
	if values.get("operation", "") in ["service", "repair", "damage_control"]:
		return support.validate(vessel, values, id)
	if values.get("operation", "") in ["recover_aircraft", "resume_recovery", "stop_recovery", "unload_aircraft"]:
		return recovery.validate(actor, vessel, values, id)
	if values.get("operation", "") in ["transport", "continue_transport", "resume_transport", "cancel_transport", "unload", "forward_supply", "transship_cargo", "cancel_transshipment", "reassign_cargo"]:
		return freight.validate(actor, vessel, values, id)
	if values.get("operation", "") == "stop":
		return {"ok": true} if values.size() == 2 and missions.has(vessel.mission_ref) and vessel.status in ["SAILING", "PATROLLING", "OBSERVING", "ESCORT_WAITING", "BLOCKED", "FUEL_EXHAUSTED", "IMMOBILE", "DOCKED", "ANCHORED", "CARGO_WAITING", "WAITING_PORT"] else _reject("active_surface_mission_required")
	if values.size() != (6 if values.get("operation", "") == "escort" else 5) or values.get("operation", "") not in ["sail", "patrol", "engage", "intercept", "shore_support", "escort", "blockade"] or not values.get("path") is Array or not values.get("target_node") is String or not values.get("target_ref") is String or values.path.size() > MAX_PATH or missions.size() >= MAX_MISSIONS or missions.has(id):
		return _reject("explicit_bounded_surface_mission_required")
	if vessel.cargo_ref != "" or vessel.get("recovery_ref", "") != "" or vessel.status not in ["DOCKED", "ANCHORED", "BLOCKED", "FUEL_EXHAUSTED", "IMMOBILE", "SUPPLY_EXHAUSTED"] or not mobile(vessel) or float(vessel.stock.fuel) <= 0.0:
		return _reject("vessel_not_available_for_navigation")
	var route: Dictionary = validate_route(actor, vessel, values.path, str(values.target_node))
	if not route.ok:
		return route
	if values.operation == "escort":
		if not values.get("transport_ref") is String or not freight.transports.has(values.transport_ref):
			return _reject("existing_own_transport_reference_required")
		var transport: Dictionary = freight.transports[values.transport_ref]
		var carrier: Dictionary = vessels[transport.vessel_ref]
		if carrier.id == vessel.id or carrier.cargo_ref != transport.id or not _authorized(actor, carrier) or _distance(position(str(carrier.id)), position(str(vessel.id))) > float(rules.escort_radius_km):
			return _reject("distinct_actual_nearby_own_transport_and_escort_required")
	if values.operation in ["engage", "intercept", "shore_support"]:
		if float(vessel.stock.ammunition) <= 0.0:
			return _reject("finite_ship_ammunition_required")
		if not _received(actor, str(values.target_ref), str(values.target_node), values.operation == "shore_support"):
			# Shore target nodes differ from ship destination; use the report's own node.
			if values.operation != "shore_support" or not _received_shore(actor, str(values.target_ref)):
				return _reject("finite_ammunition_and_received_target_required")
	elif not str(values.target_ref).is_empty():
		return _reject("surface_patrol_has_no_truth_target")
	return {"ok": true}

func validate_route(actor: String, vessel: Dictionary, path: Array, destination: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if path.size() > MAX_PATH or not g._known.get(actor, {}).has(destination) or not g._space._nodes.has(destination) or not g._space._nodes[destination].get("water", false):
		return _reject("known_bounded_surface_destination_required")
	var node: String = str(vessel.node)
	if vessel.has("leg") and vessel.leg.get("lane", "") != "" and _distance(position(str(vessel.id)), g._space._nodes[node].xy) > 0.000001:
		if path.is_empty() or path[0] != vessel.leg.lane:
			return _reject("resume_current_water_connection_first")
	for lane_id: Variant in path:
		if not lane_id is String or not g._space._waterways.has(lane_id):
			return _reject("known_water_connection_required")
		var lane: Dictionary = g._space._waterways[lane_id]
		if node not in [lane.from, lane.to] or float(lane.depth_km) < float(vessel.draft_km):
			return _reject("blocked_disconnected_or_shallow_water_connection")
		node = str(lane.to) if node == lane.from else str(lane.from)
		if not g._known.get(actor, {}).has(node):
			return _reject("known_water_route_required")
	return {"ok": true} if node == destination else _reject("surface_route_must_reach_destination")

func _received_shore(actor: String, target: String) -> bool:
	for entry: Dictionary in _owner.get_ref()._state.information_port.get_ref().knowledge(actor).get("entries", []):
		if entry.subject_ref == target and entry.subject_kind == "unit" and entry.fact_kind in ["air_contact", "contact", "position"] and float(entry.reliability) > 0.0:
			return true
	return false

func apply(actor: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var vessel: Dictionary = vessels[values.vessel_ref]
	# Settle the previous damage-control interval before this new action starts.
	support.settle(vessel)
	var available: Dictionary = validate(actor, str(g._state.structure_port.get_ref().command_person(actor).formation_id), values, id)
	if not available.ok:
		_refresh_motion(vessel)
		return available
	if values.operation in ["service", "repair", "damage_control"]:
		support.start(actor, vessel, values, id)
		return {"ok": true, "state_delta": {"naval_support": {"request_ref": id, "status": vessel.status}}}
	if values.operation in ["recover_aircraft", "resume_recovery", "stop_recovery", "unload_aircraft"]:
		recovery.start(actor, vessel, values, id)
		return {"ok": true, "state_delta": {"sea_recovery": {"recovery_ref": vessel.get("recovery_ref", ""), "status": vessel.status}}}
	if values.operation == "rendezvous":
		freight.start_rendezvous(actor, vessel, values, id)
		return {"ok": true, "state_delta": {"naval_rendezvous": {"mission_ref": id, "status": vessel.status}}}
	if values.operation in ["transport", "continue_transport", "resume_transport", "cancel_transport", "unload", "forward_supply", "transship_cargo", "cancel_transshipment", "reassign_cargo"]:
		freight.start(actor, vessel, values, id)
		return {"ok": true, "state_delta": {"sea_transport": {"transport_ref": vessel.cargo_ref, "status": vessel.status}}}
	_checkpoint(vessel)
	vessel.version += 1
	if values.operation == "stop":
		if vessel.cargo_ref != "":
			freight.hold(vessel, "STOPPED_AT_ACTUAL_POSITION")
		else:
			missions[vessel.mission_ref].status = "STOPPED_AT_ACTUAL_POSITION"
			vessel.status = "ANCHORED"
	else:
		var mission: Dictionary = {"id": id, "issuer": actor, "operation": values.operation, "target_ref": values.target_ref,
			"target_node": values.target_node, "path": values.path.duplicate(), "index": 0, "status": "SAILING", "started_at": g._state.time}
		missions[id] = mission
		if values.operation == "escort":
			mission.transport_ref = values.transport_ref
			mission.deadline = g._state.time + float(rules.escort_deadline_seconds)
		vessel.mission_ref = id
		_next(vessel, mission)
	_report_status(vessel, actor, id, "ORDER_APPLIED")
	return {"ok": true, "state_delta": {"naval_task": {"vessel_ref": vessel.id, "mission_ref": vessel.mission_ref, "status": vessel.status}}}

func _speed(vessel: Dictionary) -> float:
	var node: Dictionary = _owner.get_ref()._space._nodes[contact_node(str(vessel.id))]
	var cargo_factor: float = float(freight.rules.loaded_speed_factor) if vessel.cargo_ref != "" else 1.0
	return float(vessel.speed_km_s) * (0.2 + 0.8 * float(vessel.integrity)) * (1.0 - float(vessel.mobility_damage)) * (1.0 - 0.3 * support.effort(vessel)) * cargo_factor * (1.0 - 0.5 * float(node.get("sea_state", 0.0)))

func mobile(vessel: Dictionary) -> bool:
	return vessel.status != "SUNK" and float(vessel.stock.equipment) > 0.0 and float(vessel.integrity) > float(rules.mobility_integrity) and float(vessel.mobility_damage) < float(rules.system_disabled_damage)

func _next(vessel: Dictionary, mission: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	if not mobile(vessel):
		vessel.status = "IMMOBILE"
		mission.status = "MOBILITY_LOST"
		_report_to_issuer(vessel, str(mission.id) + "_immobile", "MOBILITY_LOST")
		return
	if mission.operation == "escort" and not _escort_ready(vessel, mission):
		return
	if mission.operation == "recover_aircraft" and recovery.jobs[mission.id].phase in ["LOCAL_APPROACH", "LOCAL_RETURN"]:
		recovery.continue_local(vessel)
		return
	if int(mission.index) >= mission.path.size():
		if mission.operation == "rendezvous":
			freight.arrive_rendezvous(vessel)
			return
		if mission.operation == "recover_aircraft":
			recovery.arrive(vessel)
			return
		if mission.operation == "transport":
			freight.arrive(vessel)
			return
		var patrolling: bool = mission.operation in ["patrol", "blockade", "escort"]
		mission.status = "PATROLLING" if patrolling else "OBSERVING"
		_begin(vessel, str(mission.status), vessel.xy, float(rules.patrol_seconds) if patrolling else float(rules.observation_seconds))
		return
	var lane_id: String = str(mission.path[mission.index])
	var lane: Dictionary = g._space._waterways[lane_id]
	if not lane.open or float(lane.depth_km) < float(vessel.draft_km):
		vessel.status = "BLOCKED"
		mission.status = "WATERWAY_BLOCKED"
		_report_to_issuer(vessel, str(mission.id) + "_blocked", str(mission.status))
		return
	var node: String = str(lane.to) if vessel.node == lane.from else str(lane.from)
	var point: Array = g._space._nodes[node].xy
	var original_distance: float = _distance(g._space._nodes[lane.from].xy, g._space._nodes[lane.to].xy)
	var remaining: float = _distance(vessel.xy, point) / maxf(0.000001, original_distance)
	_begin(vessel, "SAILING", point, float(lane.length_km) * remaining / _speed(vessel), lane_id, node)

func _begin(vessel: Dictionary, status: String, destination: Array, seconds: float, lane: String = "", node: String = "") -> void:
	var g: RefCounted = _owner.get_ref()
	var duration: float = maxf(0.000001, seconds)
	var burn: float = float(vessel.fuel_per_second) if status == "SAILING" else 0.0
	var available: float = float(vessel.stock.fuel) / burn if burn > 0.0 else duration
	vessel.leg = {"from": vessel.xy.duplicate(), "to": destination.duplicate(), "started_at": g._state.time,
		"duration": duration, "due": g._state.time + maxf(0.000001, minf(duration, available)), "burn": burn,
		"fuel_limited": available + 0.0000001 < duration, "lane": lane, "node": node, "serial": _serial + 1}
	if status == "SAILING":
		vessel.heading_degrees = rad_to_deg(atan2(float(destination[1]) - float(vessel.xy[1]), float(destination[0]) - float(vessel.xy[0])))
	vessel.status = status
	_ticket(vessel, "STAGE", float(vessel.leg.due), {"leg_serial": vessel.leg.serial})
	_contact_ticket(vessel, g._state.time + minf(float(rules.contact_seconds), duration * 0.5))

func _ticket(vessel: Dictionary, kind: String, due: float, extra: Dictionary = {}) -> void:
	var g: RefCounted = _owner.get_ref()
	_serial += 1
	var id: String = "sea_%d" % _serial
	_tickets[id] = {"vessel_ref": vessel.id, "kind": kind, "due": due, "version": vessel.version}
	_tickets[id].merge(extra)
	assert(g._state.schedule_event(id, due, "gameplay", {"sea_id": id}))

func _contact_ticket(vessel: Dictionary, due: float) -> void:
	if due + 0.0000001 < float(vessel.leg.due):
		_ticket(vessel, "CONTACT", due, {"leg_serial": vessel.leg.serial})

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and payload.get("sea_id", "") == id and _tickets.has(id) and _tickets[id].due == due

func process_event(event: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var ticket: Dictionary = _tickets[event.id]
	_tickets.erase(event.id)
	var vessel: Dictionary = vessels[ticket.vessel_ref]
	var result: Dictionary = {"changed": [], "retired": [], "record": {"kind": "surface_event", "vessel_ref": vessel.id, "time": g._state.time}}
	if ticket.kind == "DAMAGE":
		support.process_damage(vessel, ticket)
		result.record.kind = "surface_damage_progress"
		return result
	if ticket.kind == "RENDEZVOUS_DEADLINE":
		freight.expire_rendezvous(vessel, str(ticket.mission_ref))
		return result
	if ticket.version != vessel.version:
		result.record.kind = "obsolete_surface_event"
		return result
	if ticket.kind == "PORT_WORK":
		support.process_port(vessel, ticket)
		return result
	if ticket.kind in ["AIR_PICKUP", "AIR_SHORE_UNLOAD"]:
		recovery.process(vessel, ticket)
		return result
	if ticket.kind in ["CARGO_LOAD", "CARGO_UNLOAD", "CARGO_TRANSFER"]:
		freight.process(vessel, ticket)
		return result
	if ticket.kind == "ESCORT_WAIT":
		_next(vessel, missions[vessel.mission_ref])
		return result
	if not vessel.has("leg") or ticket.leg_serial != vessel.leg.serial:
		result.record.kind = "obsolete_surface_leg"
		return result
	var mission: Dictionary = missions[vessel.mission_ref]
	if ticket.kind == "CONTACT":
		_sensor(vessel, mission, str(event.id))
		if mission.operation in ["engage", "intercept"]:
			_surface_fire(vessel, str(mission.target_ref), str(event.id), true)
		if mission.operation == "blockade":
			_interdict(vessel, str(event.id))
		if mission.operation == "escort":
			_escort_fire(vessel, mission, str(event.id))
		if mission.operation == "shore_support":
			result = _shore_fire(vessel, mission, str(event.id))
			result.record = {"kind": "surface_shore_opportunity", "vessel_ref": vessel.id, "time": g._state.time}
		if ticket.version == vessel.version and ticket.leg_serial == vessel.leg.serial:
			_contact_ticket(vessel, g._state.time + float(rules.contact_seconds))
		return result
	_checkpoint(vessel)
	if vessel.leg.fuel_limited:
		vessel.status = "FUEL_EXHAUSTED"
		mission.status = "FUEL_EXHAUSTED_AT_ACTUAL_POSITION"
		_report_to_issuer(vessel, str(event.id), str(mission.status))
	elif vessel.status == "SAILING":
		vessel.node = vessel.leg.node
		vessel.erase("leg")
		if mission.operation == "recover_aircraft" and recovery.jobs[mission.id].phase in ["LOCAL_APPROACH", "LOCAL_RETURN"]:
			recovery.arrive(vessel)
			return result
		mission.index += 1
		_next(vessel, mission)
	else:
		mission.status = "COMPLETED"
		vessel.status = "DOCKED" if _at_port(vessel) else "ANCHORED"
		_report_status(vessel, str(mission.issuer), str(event.id), mission.status)
	return result

func position(id: String) -> Array:
	var vessel: Dictionary = vessels[id]
	if vessel.status not in ["SAILING", "PATROLLING", "OBSERVING"] or not vessel.has("leg"):
		return vessel.xy.duplicate()
	var fraction: float = clampf((_owner.get_ref()._state.time - float(vessel.leg.started_at)) / float(vessel.leg.duration), 0.0, 1.0)
	return [lerpf(float(vessel.leg.from[0]), float(vessel.leg.to[0]), fraction), lerpf(float(vessel.leg.from[1]), float(vessel.leg.to[1]), fraction)]

func contact_node(id: String) -> String:
	var vessel: Dictionary = vessels[id]
	var next: String = str(vessel.get("leg", {}).get("node", ""))
	if next.is_empty():
		return str(vessel.node)
	var nodes: Dictionary = _owner.get_ref()._space._nodes
	return next if _distance(position(id), nodes[next].xy) < _distance(position(id), nodes[vessel.node].xy) else str(vessel.node)

func _checkpoint(vessel: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	var here: Array = position(str(vessel.id))
	if vessel.status == "SAILING" and vessel.has("leg"):
		g._state.logistics_port.get_ref().consume_air(str(vessel.id), "fuel", maxf(0.0, g._state.time - float(vessel.leg.get("settled_at", vessel.leg.started_at))) * float(vessel.leg.burn))
		vessel.leg.settled_at = g._state.time
	vessel.xy = here

func contact_claim(observer: String, id: String, cause: String, quality: float, origin: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var point: Array = position(id)
	var precision: float = float(vessels[id].precision_km) / maxf(0.1, quality)
	var band: Array = [floorf(float(point[0]) / precision) * precision, floorf(float(point[1]) / precision) * precision]
	return {"id": cause + "_" + id, "source_ref": observer, "subject_ref": id, "subject_kind": "vessel", "fact_kind": "sea_contact",
		"value": {"node_ref": contact_node(id), "xy_band": [band, [float(band[0]) + precision, float(band[1]) + precision]]},
		"observed_at": g._state.time, "observer_ref": observer, "origin": origin, "quality": quality, "precision": "surface_sensor_band"}

func _sensor(vessel: Dictionary, mission: Dictionary, cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if g._state.time < float(mission.get("next_report", 0.0)):
		return
	var claims: Array[Dictionary] = []
	claims.append_array(recovery.contacts(vessel, cause))
	for id: String in vessels:
		var other: Dictionary = vessels[id]
		var quality: float = _visibility(vessel, other)
		if quality > 0.0:
			claims.append(contact_claim(str(vessel.id), id, cause, quality, "SEA_VISUAL"))
	if not claims.is_empty():
		g._state.information_port.get_ref().send_platform_report(self, str(vessel.id), str(mission.issuer), "sea_report_" + cause, claims)
	_report_to_issuer(vessel, cause, "OWN_NAVIGATION_REPORT")
	mission.next_report = g._state.time + float(rules.report_interval_seconds)

func _visibility(vessel: Dictionary, other: Dictionary) -> float:
	var g: RefCounted = _owner.get_ref()
	var sides: Dictionary = g._state.structure_port.get_ref()._nodes
	if vessel.id == other.id or other.status == "SUNK" or sides[vessel.owner].side == sides[other.owner].side or _distance(position(str(vessel.id)), position(str(other.id))) > float(vessel.sensor_range_km):
		return 0.0
	var node: Dictionary = g._space._nodes[contact_node(str(vessel.id))]
	var lane: Dictionary = g._space._lanes.get(contact_node(str(vessel.id)) + ":" + contact_node(str(other.id)), {})
	return float(node.get("sea_visibility", 1.0)) * float(vessel.integrity) if lane.get("observe", false) else 0.0

func _surface_fire(vessel: Dictionary, target: String, cause: String, reply: bool) -> void:
	var g: RefCounted = _owner.get_ref()
	if not vessels.has(target) or not _gun_ready(vessel) or _visibility(vessel, vessels[target]) <= 0.0:
		return
	var other: Dictionary = vessels[target]
	var here: Array = position(str(vessel.id))
	var point: Array = position(target)
	var distance: float = _distance(here, point)
	var lane: Dictionary = g._space._lanes.get(contact_node(str(vessel.id)) + ":" + contact_node(target), {})
	if distance > float(rules.range_km) or not lane.get("fire", false) or not _arc(vessel, point):
		return
	var rounds: float = g._state.logistics_port.get_ref().consume_air(str(vessel.id), "ammunition", float(rules.rounds) * (1.0 - support.effort(vessel)))
	vessel.next_fire = g._state.time + float(rules.fire_interval_seconds)
	var motion: float = _speed(other) if other.status == "SAILING" else 0.0
	var aim: float = _visibility(vessel, other) * (1.0 - 0.5 * distance / float(rules.range_km)) / (1.0 + motion * 20.0)
	damage(target, rounds * float(rules.surface_damage_per_round) * aim, cause + "_" + str(vessel.id))
	if reply and other.status != "SUNK":
		# Local self-defense follows this actual attack, not a global truth order.
		_surface_fire(other, str(vessel.id), cause + "_reply", false)

func _gun_ready(vessel: Dictionary) -> bool:
	return vessel.status not in ["SUNK", "SERVICING", "REPAIRING", "LOADING", "UNLOADING"] and float(vessel.integrity) >= float(rules.weapon_integrity) and float(vessel.weapon_damage) < float(rules.system_disabled_damage) and float(vessel.stock.ammunition) > 0.0 and _owner.get_ref()._state.time >= float(vessel.next_fire)

func _arc(vessel: Dictionary, point: Array) -> bool:
	var here: Array = position(str(vessel.id))
	var bearing: float = rad_to_deg(atan2(float(point[1]) - float(here[1]), float(point[0]) - float(here[0])))
	return absf(wrapf(bearing - float(vessel.heading_degrees), -180.0, 180.0)) <= float(rules.arc_degrees) * 0.5

func _shore_fire(vessel: Dictionary, mission: Dictionary, cause: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var target: String = str(mission.target_ref)
	var result: Dictionary = {"changed": [], "retired": []}
	if not _gun_ready(vessel) or not g._state.knows_unit(target):
		return result
	var unit: Dictionary = g._state.units[target] if g._state.units.has(target) else g._lod.preview_leaf(target)
	var selected: Dictionary = {}
	for location: Dictionary in g.tactics.ground_sources(unit):
		var candidate: Array = g._space.xy(location)
		var lane: Dictionary = g._space._lanes.get(contact_node(str(vessel.id)) + ":" + str(location.spatial.node), {})
		if _distance(position(str(vessel.id)), candidate) <= float(rules.shore_range_km) and lane.get("observe", false) and lane.get("fire", false) and _arc(vessel, candidate) and float(g._space.terrain(location).visibility) > 0.0:
			selected = location
			break
	if unit.side == g._state.structure_port.get_ref()._nodes[vessel.owner].side or selected.is_empty():
		return result
	if not g._state.units.has(target):
		result = g._lod.materialize_leaf(target, "actual_ship_shore_effect")
		unit = g._state.units[target]
	var rounds: float = g._state.logistics_port.get_ref().consume_air(str(vessel.id), "ammunition", float(rules.rounds) * (1.0 - support.effort(vessel)))
	vessel.next_fire = g._state.time + float(rules.fire_interval_seconds)
	g._lod._kernel.direct_fire(g._state, unit, rounds, float(rules.shore_lethality), cause, g._space.xy(selected))
	if target not in result.changed:
		result.changed.append(target)
	mission.last_shore_fire = {"at": g._state.time, "cause_ref": cause, "rounds": rounds}
	return result

func damage(id: String, dose: float, cause: String) -> void:
	if not vessels.has(id) or vessels[id].status == "SUNK" or dose <= 0.0:
		return
	var g: RefCounted = _owner.get_ref()
	var vessel: Dictionary = vessels[id]
	support.settle(vessel)
	if vessel.status == "SUNK":
		return
	_checkpoint(vessel)
	support.interrupt_port(vessel, "ATTACK_INTERRUPTED_PORT_WORK")
	freight.interrupt_transfer(vessel, "ATTACK_INTERRUPTED_TRANSFER")
	if vessel.cargo_ref != "" and vessel.status in ["LOADING", "UNLOADING"]:
		freight.hold(vessel, "ATTACK_INTERRUPTED_CARGO_HANDLING")
	vessel.integrity = maxf(0.0, float(vessel.integrity) - dose)
	vessel.last_damage = {"cause_ref": cause, "at": g._state.time, "dose": dose}
	if float(vessel.integrity) <= 0.0:
		_sink(vessel, cause)
		return
	support.on_hit(vessel, dose, cause)
	_refresh_motion(vessel)
	_report_to_issuer(vessel, cause, "ACTUAL_SHIP_DAMAGE")

func sustained_damage(vessel: Dictionary, loss: float, cause: String) -> void:
	_checkpoint(vessel)
	freight.interrupt_transfer(vessel, "SUSTAINED_DAMAGE_INTERRUPTED_TRANSFER")
	vessel.integrity = maxf(0.0, float(vessel.integrity) - loss)
	vessel.last_sustained_damage = {"cause_ref": cause, "at": _owner.get_ref()._state.time, "dose": loss}
	if float(vessel.integrity) <= 0.0:
		_sink(vessel, cause + "_sustained")
	else:
		recovery.on_damage(vessel)

func _sink(vessel: Dictionary, cause: String) -> void:
	if vessel.status == "SUNK":
		return
	var g: RefCounted = _owner.get_ref()
	_checkpoint(vessel)
	vessel.version += 1
	vessel.damage_version += 1
	vessel.status = "SUNK"
	vessel.sunk_at = g._state.time
	vessel.sunk_xy = vessel.xy.duplicate()
	vessel.sinking_cause_ref = cause
	vessel.control_active = false
	vessel.control_effort = 0.0
	g._state.logistics_port.get_ref().destroy_asset(str(vessel.id))
	support.interrupt_port(vessel, "VESSEL_SUNK")
	freight.on_sunk(vessel, cause)
	recovery.on_sunk(vessel)
	if missions.has(vessel.mission_ref):
		missions[vessel.mission_ref].status = "VESSEL_DESTROYED"
	_report_to_issuer(vessel, cause, "VESSEL_SUNK")

func _refresh_motion(vessel: Dictionary) -> void:
	if vessel.status == "SUNK":
		return
	recovery.on_damage(vessel)
	_checkpoint(vessel)
	if not mobile(vessel) and vessel.status not in ["REPAIRING", "SERVICING", "LOADING", "UNLOADING"]:
		var changed: bool = vessel.status != "IMMOBILE"
		vessel.version += 1
		vessel.status = "IMMOBILE"
		if missions.has(vessel.mission_ref):
			missions[vessel.mission_ref].status = "MOBILITY_LOST_AT_ACTUAL_POSITION"
		if changed:
			_report_to_issuer(vessel, "immobile", "MOBILITY_LOST_AT_ACTUAL_POSITION")
	elif vessel.status == "SAILING":
		vessel.version += 1
		_next(vessel, missions[vessel.mission_ref])

func _escort_ready(vessel: Dictionary, mission: Dictionary) -> bool:
	var g: RefCounted = _owner.get_ref()
	var transport: Dictionary = freight.transports[mission.transport_ref]
	var carrier: Dictionary = vessels[transport.vessel_ref]
	if carrier.status == "SUNK" or carrier.cargo_ref != transport.id or g._state.time >= float(mission.deadline) or float(vessel.stock.fuel) <= 0.0:
		mission.status = "ESCORT_ENDED"
		vessel.status = "DOCKED" if _at_port(vessel) else "ANCHORED"
		_report_to_issuer(vessel, "escort_end", str(mission.status))
		return false
	if carrier.status in ["LOADING", "CARGO_WAITING", "WAITING_PORT", "BLOCKED", "FUEL_EXHAUSTED", "IMMOBILE"] or _distance(position(str(vessel.id)), position(str(carrier.id))) > float(rules.escort_radius_km):
		vessel.status = "ESCORT_WAITING"
		mission.status = "WAITING_FOR_ACTUAL_CARRIER"
		_ticket(vessel, "ESCORT_WAIT", g._state.time + float(rules.escort_wait_seconds))
		return false
	return true

func _escort_fire(vessel: Dictionary, mission: Dictionary, cause: String) -> void:
	var transport: Dictionary = freight.transports[mission.transport_ref]
	var carrier: Dictionary = vessels[transport.vessel_ref]
	if carrier.status == "SUNK" or carrier.cargo_ref != transport.id or _distance(position(str(vessel.id)), position(str(carrier.id))) > float(rules.escort_radius_km):
		if not mission.get("separated_reported", false):
			_report_to_issuer(vessel, cause, "ESCORT_OUTSIDE_ACTUAL_CARRIER_RANGE")
			mission.separated_reported = true
		return
	mission.separated_reported = false
	for id: String in vessels:
		if _visibility(vessel, vessels[id]) > 0.0 and _distance(position(id), position(str(carrier.id))) <= float(rules.range_km):
			_surface_fire(vessel, id, cause + "_escort", true)

func _interdict(vessel: Dictionary, cause: String) -> void:
	# A declared local blockade only fires on actual visible ships in gun range.
	for id: String in vessels:
		if _visibility(vessel, vessels[id]) > 0.0:
			_surface_fire(vessel, id, cause + "_interdict", true)

func on_waterway(id: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if g._space._waterways[id].open:
		return
	for vessel_id: String in vessels:
		var vessel: Dictionary = vessels[vessel_id]
		if vessel.status == "SAILING" and vessel.leg.lane == id:
			_checkpoint(vessel)
			vessel.version += 1
			vessel.status = "BLOCKED"
			missions[vessel.mission_ref].status = "WATERWAY_BLOCKED_AT_ACTUAL_POSITION"
			_report_to_issuer(vessel, "waterway_" + id, "WATERWAY_BLOCKED_AT_ACTUAL_POSITION")

func on_site(node: String) -> void:
	recovery.on_site(node)
	for id: String in vessels:
		var vessel: Dictionary = vessels[id]
		if vessel.get("transfer_ref", "") != "" and contact_node(id) == node:
			var transfer: Dictionary = freight.transfers[vessel.transfer_ref]
			if not freight._stable_pair(vessels[transfer.source_vessel_ref], vessels[transfer.recipient_vessel_ref]):
				freight.interrupt_transfer(vessel, "SITE_CONDITIONS_INTERRUPTED_TRANSFER")
		if vessel.port_job_ref != "" and support.jobs[vessel.port_job_ref].port_ref == node and not _owner.get_ref()._space._nodes[node].get("port_open", true):
			support.interrupt_port(vessel, "PORT_CLOSED_DURING_WORK")
		if vessel.cargo_ref != "":
			var transport: Dictionary = freight.transports[vessel.cargo_ref]
			if vessel.status in ["LOADING", "UNLOADING"] and node in [transport.source_port, transport.destination_port] and not _owner.get_ref()._space._nodes[node].get("port_open", true):
				freight.hold(vessel, "PORT_CLOSED_DURING_CARGO_HANDLING")
			elif vessel.status == "WAITING_PORT" and node in [transport.source_port, transport.destination_port] and _owner.get_ref()._space._nodes[node].get("port_open", true):
				freight.arrive(vessel)
		if vessel.status == "SAILING" and contact_node(id) == node:
			_checkpoint(vessel)
			vessel.version += 1
			_next(vessel, missions[vessel.mission_ref])

func _at_port(vessel: Dictionary) -> bool:
	return not support.port_at(vessel).is_empty()

func _status_value(vessel: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var fuel: float = float(vessel.stock.fuel)
	if vessel.status == "SAILING" and vessel.has("leg"):
		fuel = maxf(0.0, fuel - maxf(0.0, g._state.time - float(vessel.leg.get("settled_at", vessel.leg.started_at))) * float(vessel.leg.burn))
	return {"vessel_ref": vessel.id, "port": vessel.port, "node_ref": vessel.node, "contact_node_ref": contact_node(str(vessel.id)),
		"xy": position(str(vessel.id)), "status": vessel.status, "fuel": fuel, "ammunition": vessel.stock.ammunition,
		"spares": vessel.stock.spares, "integrity": vessel.integrity, "flooding": vessel.flooding, "fire": vessel.fire,
		"mobility_damage": vessel.mobility_damage, "weapon_damage": vessel.weapon_damage, "control_active": vessel.control_active,
		"mission_ref": vessel.mission_ref, "cargo_ref": vessel.cargo_ref, "cargo_capacity": vessel.cargo_capacity, "mobile": mobile(vessel),
		"port_job_ref": vessel.port_job_ref, "transfer_ref": vessel.get("transfer_ref", ""), "cargo": freight.status(vessel), "port_observation": support.local_observation(vessel), "observed_at": g._state.time,
		"waterway_entries": _local_entries(vessel), "sea_state": g._space._nodes[contact_node(str(vessel.id))].get("sea_state", 0.0), "handling_crew": support.available_crew(vessel) * (1.0 - support.effort(vessel)),
		"current_waterway": vessel.get("leg", {}).get("lane", ""), "recovery_ref": vessel.get("recovery_ref", "")}

func _report_to_issuer(vessel: Dictionary, cause: String, status: String) -> void:
	recovery.note_status(vessel, status)
	if vessel.cargo_ref != "":
		freight.note_status(vessel, status)
		return
	var issuer: String = str(missions.get(vessel.mission_ref, {}).get("issuer", ""))
	var commander: String = current_commander(vessel)
	if issuer != "":
		_report_status(vessel, issuer, cause, status)
	if commander != "" and commander != issuer:
		_report_status(vessel, commander, cause, status)

func _local_entries(vessel: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var entries: Dictionary = {}
	if _distance(position(str(vessel.id)), g._space._nodes[vessel.node].xy) > 0.000001:
		return entries
	for reference: String in g._space._waterways:
		var lane: Dictionary = g._space._waterways[reference]
		if entries.size() >= MAX_PATH:
			break
		if vessel.node in [lane.from, lane.to]:
			entries[reference] = "ENTRY_AVAILABLE" if lane.open and float(lane.depth_km) >= float(vessel.draft_km) else "ENTRY_BLOCKED"
	return entries

func current_commander(vessel: Dictionary) -> String:
	var s: RefCounted = _owner.get_ref()._state.structure_port.get_ref()
	var person: String = str(s._positions.get(vessel.owner, {}).get("person", ""))
	return person if person != "" and _authorized(person, vessel) else ""

func request_status(actor: String, vessel_ref: String, cause: String) -> void:
	var vessel: Dictionary = vessels[vessel_ref]
	if vessel.status == "SUNK" or float(vessel.stock.equipment) <= 0.0:
		return
	if not str(vessel.cargo_ref).is_empty():
		freight._report(vessel, freight.transports[vessel.cargo_ref], cause, "REQUESTED_CURRENT_STATUS")
	else:
		_report_status(vessel, actor, cause, "REQUESTED_CURRENT_STATUS")

func _report_status(vessel: Dictionary, issuer: String, cause: String, status: String, detail: Dictionary = {}) -> void:
	var g: RefCounted = _owner.get_ref()
	_report_serial += 1
	var report: String = "sea_status_%d" % _report_serial
	var value: Dictionary = _status_value(vessel)
	value.merge(freight.rendezvous_status(vessel), true)
	value.mission_status = status
	value.cause_ref = cause
	value.report_revision = _report_serial
	if not value.port_observation.is_empty():
		value.port_observation.report_revision = _report_serial
	value.merge(detail, true)
	var claim: Dictionary = {"id": report + "_status", "source_ref": vessel.id, "subject_kind": "vessel", "subject_ref": vessel.id,
		"fact_kind": "sea_status", "value": value, "observed_at": g._state.time,
		"observer_ref": vessel.id, "origin": "PLATFORM_STATUS", "quality": 1.0, "precision": "own_status"}
	g._state.information_port.get_ref().send_platform_report(self, str(vessel.id), issuer, report, [claim])

func own_view(actor: String) -> Array[Dictionary]:
	var g: RefCounted = _owner.get_ref()
	var result: Array[Dictionary] = []
	var received: Array = g._state.information_port.get_ref().knowledge(actor).get("entries", [])
	for id: String in vessels:
		var vessel: Dictionary = vessels[id]
		if not _authorized(actor, vessel):
			continue
		var known: Dictionary = vessel.initial_report.duplicate(true)
		for entry: Dictionary in received:
			if entry.fact_kind == "sea_status" and entry.subject_ref == id and float(entry.reliability) > 0.0 and (float(entry.observed_at) > float(known.observed_at) or entry.observed_at == known.observed_at and int(entry.claimed_value.get("report_revision", 0)) > int(known.get("report_revision", 0))):
				known = entry.claimed_value.duplicate(true)
				known.learned_at = entry.received_at
		known.classification = "LAST_RECEIVED_OWN_NAVIGATION"
		known.initial_port_observation = vessel.initial_report.get("port_observation", {}).duplicate(true)
		result.append(known)
	return result

static func _distance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["vessels", "missions", "_tickets", "_serial", "_report_serial", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
