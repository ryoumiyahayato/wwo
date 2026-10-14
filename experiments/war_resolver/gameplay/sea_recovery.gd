extends RefCounted
## One explicitly equipped vessel can recover one actual floating aircraft.
var _sea: WeakRef
var capabilities: Dictionary = {}
var shore_links: Dictionary = {}
var jobs: Dictionary = {}
var _serial: int = 0
var rules: Dictionary = {"local_radius_km": 0.03, "handling_seconds": 90.0,
	"spares": 0.25, "minimum_integrity": 0.4, "minimum_crew": 0.4, "shore_speed_km_s": 0.0005}

func configure(sea: RefCounted) -> void:
	_sea = weakref(sea)

func admit(vessel_ref: String) -> bool:
	var sea: RefCounted = _sea.get_ref()
	if sea._owner.get_ref()._state.time != 0.0 or capabilities.size() >= 1 or capabilities.has(vessel_ref) or not sea.vessels.has(vessel_ref):
		return false
	capabilities[vessel_ref] = {"aircraft_slots": 1, "lifting_equipment": true}
	sea.vessels[vessel_ref].recovery_ref = ""
	return true

func admit_shore(port_ref: String, land_node: String) -> bool:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	if g._state.time != 0.0 or shore_links.size() >= 3 or not sea.support.ports.has(port_ref) or not g._space._nodes.has(land_node) or g._space._nodes[port_ref].get("land_supply_node", "") != land_node or g._space._nodes[land_node].get("water", false):
		return false
	# Synthetic port infrastructure declares this particular quay-to-land connection.
	shore_links[port_ref] = {"land_node": land_node, "from": g._space._nodes[port_ref].xy.duplicate(),
		"to": g._space._nodes[land_node].xy.duplicate(), "handling_slots": 1}
	return true

func _available(vessel: Dictionary) -> bool:
	var sea: RefCounted = _sea.get_ref()
	return capabilities.has(vessel.id) and vessel.status != "SUNK" and float(vessel.integrity) >= float(rules.minimum_integrity) and float(vessel.stock.equipment) > 0.0 and sea.support.available_crew(vessel) >= float(rules.minimum_crew)

func validate(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	if values.get("operation", "") == "recover_aircraft":
		if values.size() != 7 or not values.get("asset_ref") is String or not g.air.assets.has(values.asset_ref) or not values.get("pickup_node") is String or not values.get("destination_port") is String or not values.get("path") is Array or not values.get("return_path") is Array:
			return sea._reject("explicit_aircraft_water_pickup_port_and_two_water_routes_required")
		var asset: Dictionary = g.air.assets[values.asset_ref]
		if jobs.size() >= 64 or jobs.has(id) or sea.missions.size() >= sea.MAX_MISSIONS or not _available(vessel) or not sea.mobile(vessel) or float(vessel.stock.fuel) <= 0.0 or float(vessel.stock.spares) < float(rules.spares) or vessel.cargo_ref != "" or vessel.get("recovery_ref", "") != "" or vessel.status not in ["DOCKED", "ANCHORED", "SUPPLY_EXHAUSTED"]:
			return sea._reject("finite_free_equipped_recovery_vessel_and_onboard_materials_required")
		if asset.status != "AWAITING_RECOVERY" or asset.get("recovery_ref", "") != "" or asset.owner != vessel.owner or float(asset.integrity) <= 0.0 or float(asset.stock.equipment) <= 0.0 or asset.get("landing", {}).get("surface", "UNKNOWN") != "WATER":
			return sea._reject("actual_recoverable_floating_own_aircraft_required")
		if not shore_links.has(values.destination_port) or sea.support.ports[values.destination_port].owner != vessel.owner:
			return sea._reject("declared_own_quay_and_land_unloading_connection_required")
		var received: bool = false
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor, "aircraft", str(asset.id), "water_recovery_contact").get("entries", []):
			if claim.claimed_value.get("node_ref", "") == values.pickup_node and float(claim.reliability) > 0.0:
				received = true
		if not received:
			return sea._reject("delivered_actual_water_observation_required")
		var valid: Dictionary = sea.validate_route(actor, vessel, values.path, str(values.pickup_node))
		if not valid.ok:
			return valid
		var projected: Dictionary = vessel.duplicate(true)
		projected.node = values.pickup_node
		projected.xy = g._space._nodes[values.pickup_node].xy.duplicate()
		projected.erase("leg")
		return sea.validate_route(actor, projected, values.return_path, str(values.destination_port))
	if vessel.get("recovery_ref", "") == "" or not jobs.has(vessel.recovery_ref):
		return sea._reject("active_actual_water_recovery_required")
	var job: Dictionary = jobs[vessel.recovery_ref]
	if vessel.port_job_ref != "":
		return sea._reject("finish_actual_port_work_before_changing_recovery_navigation")
	if values.operation == "stop_recovery":
		return {"ok": true} if values.size() == 2 else sea._reject("explicit_water_recovery_stop_required")
	var learned: bool = false
	for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor, "aircraft", str(job.asset_ref), "sea_recovery_status").get("entries", []):
		if claim.claimed_value.get("recovery_ref", "") == job.id and claim.claimed_value.get("phase", "") == job.phase and float(claim.reliability) > 0.0:
			learned = true
	if not learned:
		return sea._reject("delivered_water_recovery_interruption_or_port_report_required")
	if values.operation == "unload_aircraft":
		return {"ok": true} if values.size() == 2 and job.loaded and sea.support.port_at(vessel) == job.destination_port and _available(vessel) and sea.support.ports[job.destination_port].busy == "" else sea._reject("actual_available_declared_unloading_port_required")
	if values.operation != "resume_recovery" or values.size() != 4 or not values.get("path") is Array or not values.get("target_node") is String or not _available(vessel) or not sea.mobile(vessel) or float(vessel.stock.fuel) <= 0.0 or job.phase not in ["STOPPED", "BLOCKED", "FUEL_EXHAUSTED", "STRANDED_ABOARD", "WAITING_PORT"]:
		return sea._reject("paused_water_recovery_actual_capacity_fuel_and_route_required")
	var target: String = str(job.destination_port) if job.loaded else str(job.pickup_node)
	return sea.validate_route(actor, vessel, values.path, target) if values.target_node == target else sea._reject("resume_keeps_actual_recovery_destination")

func start(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	if values.operation == "recover_aircraft":
		jobs[id] = {"id": id, "issuer": actor, "asset_ref": values.asset_ref, "vessel_ref": vessel.id,
			"pickup_node": values.pickup_node, "destination_port": values.destination_port, "return_path": values.return_path.duplicate(),
			"loaded": false, "phase": "APPROACHING", "started_at": g._state.time}
		g.air.assets[values.asset_ref].recovery_ref = id
		vessel.recovery_ref = id
		sea.missions[id] = {"id": id, "issuer": actor, "operation": "recover_aircraft", "path": values.path.duplicate(),
			"index": 0, "target_node": values.pickup_node, "target_ref": values.asset_ref, "status": "SAILING", "started_at": g._state.time}
		vessel.mission_ref = id
		vessel.version += 1
		sea._next(vessel, sea.missions[id])
		_report(jobs[id], "RECOVERY_VESSEL_DISPATCHED")
		return
	var job: Dictionary = jobs[vessel.recovery_ref]
	sea._checkpoint(vessel)
	vessel.version += 1
	if values.operation == "stop_recovery":
		_pause(job, "STOPPED")
	elif values.operation == "unload_aircraft":
		_unload(job)
	else:
		var mission: Dictionary = sea.missions[job.id]
		mission.path = values.path.duplicate()
		mission.index = 0
		mission.target_node = values.target_node
		job.phase = "RETURNING" if job.loaded else "APPROACHING"
		var anchor: Array = g._space._nodes[vessel.node].xy
		if sea._distance(vessel.xy, anchor) > 0.000001 and vessel.get("leg", {}).get("lane", "") not in g._space._waterways:
			job.after_local_return = job.phase
			job.phase = "LOCAL_RETURN"
			sea._begin(vessel, "SAILING", anchor, sea._distance(vessel.xy, anchor) / sea._speed(vessel), "", str(vessel.node))
		else:
			sea._next(vessel, mission)
		_report(job, "RECOVERY_RESUMED")

func contacts(vessel: Dictionary, cause: String) -> Array[Dictionary]:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var result: Array[Dictionary] = []
	var node: Dictionary = g._space._nodes[sea.contact_node(str(vessel.id))]
	for id: String in g.air.assets:
		var asset: Dictionary = g.air.assets[id]
		if asset.status not in ["AWAITING_RECOVERY", "SEA_LOADING"] or asset.get("landing", {}).get("surface", "UNKNOWN") != "WATER":
			continue
		var distance: float = sea._distance(sea.position(str(vessel.id)), asset.xy)
		var lane: Dictionary = g._space._lanes.get(sea.contact_node(str(vessel.id)) + ":" + str(asset.node), {})
		if distance > float(vessel.sensor_range_km) or not lane.get("observe", false) or float(node.get("sea_visibility", 0.0)) <= 0.0:
			continue
		var precision: float = float(vessel.precision_km)
		var band: Array = [floorf(float(asset.xy[0]) / precision) * precision, floorf(float(asset.xy[1]) / precision) * precision]
		var value: Dictionary = {"node_ref": asset.node, "surface": "WATER", "state": "RECOVERABLE",
			"xy_band": [band, [float(band[0]) + precision, float(band[1]) + precision]]}
		if distance <= float(rules.local_radius_km):
			value.xy = asset.xy.duplicate()
		result.append({"id": cause + "_air_" + id, "source_ref": vessel.id, "observer_ref": vessel.id,
			"subject_kind": "aircraft", "subject_ref": id, "fact_kind": "water_recovery_contact", "value": value,
			"observed_at": g._state.time, "origin": "SEA_VISUAL", "quality": float(node.sea_visibility) * float(vessel.integrity), "precision": "actual_water_visual"})
	return result

func arrive(vessel: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var job: Dictionary = jobs[vessel.recovery_ref]
	var asset: Dictionary = g.air.assets[job.asset_ref]
	var mission: Dictionary = sea.missions[job.id]
	if job.phase == "LOCAL_RETURN":
		job.phase = job.get("after_local_return", "RETURNING")
		sea._next(vessel, mission)
		return
	if job.loaded:
		_unload(job)
		return
	if not _available(vessel) or asset.status not in ["AWAITING_RECOVERY", "SEA_LOADING"] or asset.get("recovery_ref", "") != job.id or asset.landing.surface != "WATER":
		_interrupt(job, "AIRCRAFT_OR_RECOVERY_CAPACITY_UNAVAILABLE")
		return
	var here: Array = sea.position(str(vessel.id))
	var bounds: Array = g._space._nodes[job.pickup_node].get("surface_bounds_km", [])
	if asset.node != job.pickup_node or bounds.size() != 4 or not _inside(here, bounds) or not _inside(asset.xy, bounds) or sea._distance(here, asset.xy) > float(rules.local_radius_km) or float(g._space._nodes[job.pickup_node].get("sea_visibility", 0.0)) <= 0.0:
		_pause(job, "BLOCKED")
		_report(job, "AIRCRAFT_NOT_LOCALLY_FOUND_AT_REPORTED_WATER_NODE")
		return
	if sea._distance(here, asset.xy) > 0.000001:
		job.phase = "LOCAL_APPROACH"
		sea._begin(vessel, "SAILING", asset.xy, sea._distance(here, asset.xy) / sea._speed(vessel), "", str(job.pickup_node))
		return
	if float(vessel.stock.spares) < float(rules.spares):
		_pause(job, "STRANDED_ABOARD")
		return
	g._state.logistics_port.get_ref().consume_air(str(vessel.id), "spares", float(rules.spares))
	job.phase = "LOADING"
	asset.status = "SEA_LOADING"
	asset.serviceable = false
	vessel.status = "RECOVERY_LOADING"
	vessel.version += 1
	sea._ticket(vessel, "AIR_PICKUP", g._state.time + float(rules.handling_seconds), {"recovery_job": job.id})
	_report(job, "AIRCRAFT_LOADING_AT_ACTUAL_WATER_POSITION")

func continue_local(vessel: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var job: Dictionary = jobs[vessel.recovery_ref]
	var target: Array = g._space._nodes[vessel.node].xy if job.phase == "LOCAL_RETURN" else g.air.assets[job.asset_ref].xy
	if sea._distance(vessel.xy, target) <= 0.000001:
		arrive(vessel)
	else:
		sea._begin(vessel, "SAILING", target, sea._distance(vessel.xy, target) / sea._speed(vessel), "", str(vessel.node))

func process(vessel: Dictionary, ticket: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var job: Dictionary = jobs[ticket.recovery_job]
	var asset: Dictionary = g.air.assets[job.asset_ref]
	if vessel.get("recovery_ref", "") != job.id or not _available(vessel):
		if vessel.get("recovery_ref", "") == job.id:
			_interrupt(job, "RECOVERY_CAPACITY_LOST_DURING_HANDLING")
		return
	if ticket.kind == "AIR_PICKUP":
		if job.phase != "LOADING" or asset.status != "SEA_LOADING" or asset.recovery_ref != job.id or sea._distance(sea.position(str(vessel.id)), asset.xy) > 0.000001:
			_interrupt(job, "ACTUAL_AIRCRAFT_LOADING_INTERRUPTED")
			return
		job.loaded = true
		asset.status = "CARRIED_SEA"
		asset.xy = sea.position(str(vessel.id))
		job.phase = "LOCAL_RETURN"
		job.after_local_return = "RETURNING"
		var mission: Dictionary = sea.missions[job.id]
		mission.path = job.return_path.duplicate()
		mission.index = 0
		mission.target_node = job.destination_port
		var anchor: Array = g._space._nodes[job.pickup_node].xy
		if sea._distance(vessel.xy, anchor) > 0.000001:
			sea._begin(vessel, "SAILING", anchor, sea._distance(vessel.xy, anchor) / sea._speed(vessel), "", str(job.pickup_node))
		else:
			job.phase = "RETURNING"
			sea._next(vessel, mission)
		_report(job, "AIRCRAFT_CARRIED_BY_ACTUAL_VESSEL")
		return
	if job.phase != "UNLOADING" or asset.status != "SHORE_UNLOADING" or sea.support.port_at(vessel) != job.destination_port or sea.support.ports[job.destination_port].busy != job.id:
		_interrupt(job, "ACTUAL_SHORE_UNLOADING_INTERRUPTED")
		return
	asset.xy = job.shore_to.duplicate()
	asset.node = shore_links[job.destination_port].land_node
	asset.landing = {"surface": "LAND", "node_ref": asset.node, "xy": asset.xy.duplicate(), "landed_at": g._state.time}
	asset.status = "AWAITING_RECOVERY"
	if g.air.support.bases.has(asset.node) and g.air.support.bases[asset.node].owner == asset.owner and g._space._nodes[asset.node].get("airfield_open", false):
		asset.base = asset.node
		asset.status = "GROUNDED"
	asset.serviceable = false
	asset.recovery_ref = ""
	job.loaded = false
	job.phase = "UNLOADED_AT_ACTUAL_LAND_NODE"
	job.finished_at = g._state.time
	sea.support.ports[job.destination_port].busy = ""
	vessel.recovery_ref = ""
	vessel.status = "DOCKED" if sea.mobile(vessel) else "IMMOBILE"
	sea.missions[job.id].status = "COMPLETED"
	_report(job, str(job.phase))

func _unload(job: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var vessel: Dictionary = sea.vessels[job.vessel_ref]
	var asset: Dictionary = g.air.assets[job.asset_ref]
	if sea.support.port_at(vessel) != job.destination_port or sea.support.ports[job.destination_port].busy != "" or not _available(vessel):
		_pause(job, "WAITING_PORT")
		return
	var link: Dictionary = shore_links[job.destination_port]
	job.shore_from = sea.position(str(vessel.id))
	job.shore_to = link.to.duplicate()
	job.shore_started_at = g._state.time + float(rules.handling_seconds)
	job.shore_due = job.shore_started_at + sea._distance(job.shore_from, job.shore_to) / float(rules.shore_speed_km_s)
	job.phase = "UNLOADING"
	asset.status = "SHORE_UNLOADING"
	vessel.status = "RECOVERY_UNLOADING"
	vessel.version += 1
	sea.support.ports[job.destination_port].busy = job.id
	sea._ticket(vessel, "AIR_SHORE_UNLOAD", float(job.shore_due), {"recovery_job": job.id})
	_report(job, "AIRCRAFT_MOVING_THROUGH_DECLARED_SHORE_CONNECTION")

func position(asset: Dictionary) -> Array:
	var sea: RefCounted = _sea.get_ref()
	var job: Dictionary = jobs[asset.recovery_ref]
	if asset.status == "SHORE_UNLOADING":
		var fraction: float = clampf((sea._owner.get_ref()._state.time - float(job.shore_started_at)) / maxf(0.000001, float(job.shore_due) - float(job.shore_started_at)), 0.0, 1.0)
		return [lerpf(float(job.shore_from[0]), float(job.shore_to[0]), fraction), lerpf(float(job.shore_from[1]), float(job.shore_to[1]), fraction)]
	return sea.position(str(job.vessel_ref)) if job.loaded else asset.xy.duplicate()

func _pause(job: Dictionary, status: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var vessel: Dictionary = sea.vessels[job.vessel_ref]
	if job.phase == "UNLOADING":
		_interrupt(job, status)
		return
	sea._checkpoint(vessel)
	if vessel.port_job_ref == "":
		vessel.version += 1
		vessel.status = "ANCHORED" if sea.mobile(vessel) else "IMMOBILE"
	job.phase = status
	sea.missions[job.id].status = status
	_report(job, status)

func _interrupt(job: Dictionary, reason: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var vessel: Dictionary = sea.vessels[job.vessel_ref]
	var asset: Dictionary = g.air.assets[job.asset_ref]
	var ashore: bool = asset.status == "SHORE_UNLOADING"
	if job.loaded and not ashore and vessel.status != "SUNK" and asset.status != "DESTROYED":
		_pause(job, "STRANDED_ABOARD")
		return
	if asset.status != "DESTROYED":
		asset.xy = position(asset)
		asset.landing = g._space.landing_site(asset.xy, str(vessel.node))
		asset.node = asset.landing.node_ref
		if job.loaded and vessel.status == "SUNK" and asset.landing.surface != "LAND":
			asset.recovery_ref = ""
			g.air.damage(str(asset.id), maxf(1.0, float(asset.integrity)), "lost_with_" + str(vessel.id))
		else:
			asset.status = "AWAITING_RECOVERY"
			asset.serviceable = false
	asset.recovery_ref = ""
	if sea.support.ports[job.destination_port].busy == job.id:
		sea.support.ports[job.destination_port].busy = ""
	vessel.recovery_ref = ""
	if vessel.status != "SUNK" and vessel.port_job_ref == "":
		sea._checkpoint(vessel)
		vessel.version += 1
		vessel.status = "DOCKED" if sea._at_port(vessel) else "ANCHORED"
	job.phase = reason
	job.finished_at = g._state.time
	sea.missions[job.id].status = reason
	_report(job, reason)

func on_damage(vessel: Dictionary) -> void:
	if vessel.get("recovery_ref", "") == "":
		return
	var job: Dictionary = jobs[vessel.recovery_ref]
	if not _available(vessel):
		_interrupt(job, "RECOVERY_CAPACITY_LOST_AT_ACTUAL_POSITION")

func on_sunk(vessel: Dictionary) -> void:
	if vessel.get("recovery_ref", "") != "":
		_interrupt(jobs[vessel.recovery_ref], "RECOVERY_VESSEL_SUNK")

func note_status(vessel: Dictionary, status: String) -> void:
	if vessel.get("recovery_ref", "") == "":
		return
	var job: Dictionary = jobs[vessel.recovery_ref]
	if vessel.status in ["BLOCKED", "FUEL_EXHAUSTED", "IMMOBILE"]:
		job.phase = "STRANDED_ABOARD" if job.loaded and vessel.status == "IMMOBILE" else str(vessel.status)
	_report(job, status)

func on_site(node: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	for vessel_ref: String in capabilities:
		var vessel: Dictionary = sea.vessels[vessel_ref]
		if vessel.get("recovery_ref", "") == "":
			continue
		var job: Dictionary = jobs[vessel.recovery_ref]
		if job.phase == "UNLOADING" and job.destination_port == node and not sea._owner.get_ref()._space._nodes[node].get("port_open", true):
			_interrupt(job, "PORT_CLOSED_DURING_AIRCRAFT_UNLOADING")

func _report(job: Dictionary, status: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var asset: Dictionary = g.air.assets[job.asset_ref]
	_serial += 1
	var value: Dictionary = {"recovery_ref": job.id, "vessel_ref": job.vessel_ref, "status": status, "asset_status": asset.status,
		"node_ref": asset.node, "surface": asset.get("landing", {}).get("surface", "UNKNOWN"), "destination_port": job.destination_port,
		"phase": job.phase, "integrity": asset.integrity, "base": asset.base, "serviceable": asset.serviceable}
	if job.loaded or value.surface == "LAND":
		value.xy = position(asset) if asset.recovery_ref == job.id else asset.xy.duplicate()
		if job.loaded and asset.status != "SHORE_UNLOADING":
			value.node_ref = sea.contact_node(str(job.vessel_ref))
	var claim: Dictionary = {"id": "water_recovery_%d" % _serial, "source_ref": job.vessel_ref, "observer_ref": job.vessel_ref,
		"subject_kind": "aircraft", "subject_ref": job.asset_ref, "fact_kind": "sea_recovery_status", "value": value,
		"observed_at": g._state.time, "origin": "ACTUAL_VESSEL_RECOVERY", "quality": 1.0, "precision": "reported_recovery_position"}
	g._state.information_port.get_ref().send_platform_report(sea, str(job.vessel_ref), str(job.issuer), "water_recovery_report_%d" % _serial, [claim])

static func _inside(point: Array, bounds: Array) -> bool:
	return float(point[0]) >= float(bounds[0]) and float(point[1]) >= float(bounds[1]) and float(point[0]) <= float(bounds[2]) and float(point[1]) <= float(bounds[3])

const RUNTIME_FIELDS: Array[String] = ["capabilities", "shore_links", "jobs", "_serial", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
