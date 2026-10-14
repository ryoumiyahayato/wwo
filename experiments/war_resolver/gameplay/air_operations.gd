extends RefCounted
## Bounded aviation motion and sensor events on the existing world clock.
## Speed/altitude/fuel and observation bands are replaceable synthetic inputs.
var _owner: WeakRef
var assets: Dictionary = {}
var missions: Dictionary = {}
var _tickets: Dictionary = {}
var _serial: int = 0
const Support = preload("res://experiments/war_resolver/gameplay/air_support.gd")
const Defense = preload("res://experiments/war_resolver/gameplay/air_defense.gd")
const Recovery = preload("res://experiments/war_resolver/gameplay/air_recovery.gd")
var support: Support = Support.new()
var defense: Defense = Defense.new()
var recovery: Recovery = Recovery.new()
var rules: Dictionary = {"contact_seconds": 5.0, "takeoff_seconds": 10.0, "observe_seconds": 20.0,
	"intercept_seconds": 60.0, "landing_seconds": 10.0, "descent_km_s": 0.03,
	"glide_km_s": 0.015, "return_integrity": 0.55, "flight_integrity": 0.2,
	"sensor_integrity": 0.35, "weapon_integrity": 0.25, "report_interval_seconds": 30.0}
const MAX_ASSETS: int = 2
const MAX_SORTIES: int = 64
const MAX_LEGS: int = 4
const MAX_SENSOR_READS: int = 16
const MAX_CONTACTS: int = 8

func configure(gameplay: RefCounted) -> void:
	_owner = weakref(gameplay)
	support.configure(self)
	defense.configure(gameplay)
	recovery.configure(self)

func admit(id: String, owner: String, base: String, depot: String, fuel: float, load: float, interceptor: bool = false) -> bool:
	var g: RefCounted = _owner.get_ref()
	var information: RefCounted = g._state.information_port.get_ref()
	if g._state.time != 0.0 or assets.size() >= MAX_ASSETS or assets.has(id) or g.sea.vessels.has(id) or g._state.identity_reserved(id) or g._state.structure_port.get_ref()._people.has(id) or information._outboxes.has(id) or information._platform_sources.size() >= 6 or not information._channels.has("report") or not g._space._nodes.has(base) or not g._state.structure_port.get_ref().active(owner):
		return false
	var logistics: RefCounted = g._state.logistics_port.get_ref()
	var load_capacity: float = 12.0 if interceptor else 4.0
	if fuel > 6.0 or load > load_capacity or not logistics._depots.has(depot) or not g._state.structure_port.get_ref()._contains(str(logistics._depots[depot].allocation_scope), owner):
		return false
	var supplied: Dictionary = logistics.admit_air_asset(id, depot, fuel, load)
	if not supplied.ok:
		return false
	assets[id] = {"id": id, "owner": owner, "base": base, "node": base, "xy": g._space._nodes[base].xy.duplicate(),
		"altitude_km": 0.0, "speed_km_s": 0.03, "cruise_altitude_km": 0.3, "fuel_per_second": 0.01,
		"sensor_radius_km": 0.18, "precision_km": 0.04, "cloud_visibility": 0.8, "flight_allowed": true,
		"stock": supplied.stock, "status": "LANDED", "serviceable": true, "version": 0, "mission_ref": "", "integrity": 1.0,
		"service_ref": "", "maneuver": 0.7, "interceptor": interceptor, "next_air_fire": 0.0, "fuel_capacity": 6.0, "load_capacity": load_capacity, "sensor_altitude_difference_km": 0.3,
		"air_weapon": {"range_km": 0.18, "altitude_difference_km": 0.15, "arc_degrees": 160.0, "rounds": 3.0, "damage_per_round": 0.12, "interval_seconds": 15.0},
		"weapon": {"rounds_per_pass": 4.0, "lethality": 0.008, "surface_damage_per_round": 0.12, "radius_km": 0.05, "minimum_altitude": 0.2, "maximum_altitude": 0.5}}
	assets[id].initial_report = {"asset_ref": id, "base": base, "node_ref": base, "xy": assets[id].xy.duplicate(),
		"altitude_km": 0.0, "status": "LANDED", "fuel": fuel, "load": load, "equipment": supplied.stock.equipment,
		"serviceable": true, "integrity": 1.0, "mission_ref": "", "service_ref": "", "interceptor": interceptor,
		"recovery_ref": "", "landing": {}, "observed_at": 0.0}
	return g._state.information_port.get_ref().register_air_source(id, owner, self)

func _authorized(actor: String, asset: Dictionary) -> bool:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	var person: Dictionary = s.command_person(actor)
	return s.Roles.ROLES.find(str(person.role)) >= 3 and g.participants.can_intend(actor) and s._contains(str(person.formation_id), str(asset.owner))

func validate(actor: String, target: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if not values.get("asset_ref") is String or not assets.has(values.asset_ref):
		return _reject("existing_air_asset_required")
	var asset: Dictionary = assets[values.asset_ref]
	if not _authorized(actor, asset) or target != g._state.structure_port.get_ref().command_person(actor).formation_id:
		return _reject("air_task_requires_current_owning_commander")
	if values.get("operation", "") == "service":
		return support.validate(asset, values, id)
	if values.get("operation", "") in ["recover", "recover_land"]:
		return recovery.validate(actor, asset, values, id)
	if values.get("operation", "") == "cancel_recovery":
		return {"ok": true} if values.size() == 2 and asset.get("recovery_ref", "") != "" and (asset.status == "RECOVERING" or g.land.jobs.has(asset.recovery_ref)) else _reject("active_ground_air_recovery_required")
	if values.get("operation", "") == "abort":
		return {"ok": true} if values.size() == 2 and asset.status in ["TAKING_OFF", "OUTBOUND", "OBSERVING", "RETURNING", "LANDING"] else _reject("active_returnable_sortie_required")
	for key: String in values:
		if key not in ["asset_ref", "operation", "target_node", "target_ref", "outbound", "inbound", "observe_unit", "observe_vessel", "survey_edges"]:
			return _reject("unknown_air_sortie_parameter")
	if missions.size() >= MAX_SORTIES or missions.has(id) or values.get("operation", "") not in ["recon", "strike", "intercept"] or not values.get("outbound") is Array or not values.get("inbound") is Array or not values.get("target_node") is String or not values.get("target_ref") is String:
		return _reject("explicit_bounded_air_sortie_required")
	if not values.get("survey_edges", []) is Array or values.get("survey_edges", []).size() > 4 or not values.get("observe_unit", "") is String or not values.get("observe_vessel", "") is String or (values.has("observe_unit") or values.has("observe_vessel") or values.has("survey_edges")) and values.operation != "recon":
		return _reject("bounded_recon_observation_scope_required")
	if not str(values.get("observe_vessel", "")).is_empty() and (not g.sea.vessels.has(values.observe_vessel) or not g.sea._authorized(actor, g.sea.vessels[values.observe_vessel])):
		return _reject("recovery_observation_requires_owned_vessel_identity")
	if not str(values.get("observe_unit", "")).is_empty():
		var s: RefCounted = g._state.structure_port.get_ref()
		if not s._contains(str(s.command_person(actor).formation_id), str(s._unit_nodes.get(values.observe_unit, ""))):
			return _reject("recovery_observation_requires_owned_known_identity")
	for edge: Variant in values.get("survey_edges", []):
		if not edge is String or not g._space._edges.has(edge):
			return _reject("existing_known_survey_segment_required")
		var known: bool = false
		for paths: Array in g._known.get(actor, {}).values():
			for path: Array in paths:
				known = known or edge in path
		if not known:
			return _reject("survey_segment_not_in_person_map")
	if not asset.serviceable or float(asset.stock.equipment) <= 0.0 or asset.status not in ["LANDED", "READY"] or not asset.flight_allowed or float(asset.stock.fuel) <= 0.0 or not support.usable(asset):
		return _reject("aircraft_not_available_for_takeoff")
	if values.outbound.is_empty() or values.inbound.is_empty() or values.outbound.size() > MAX_LEGS or values.inbound.size() > MAX_LEGS or values.outbound.back() != values.target_node or values.inbound.back() != asset.base:
		return _reject("actual_outbound_and_base_return_route_required")
	for node: Variant in values.outbound + values.inbound:
		if not node is String or not g._space._nodes.has(node) or not g._known.get(actor, {}).has(node):
			return _reject("air_task_requires_known_spatial_points")
	if g._space.combat_ids(str(g._space._nodes[values.target_node].cell)).size() > MAX_SENSOR_READS:
		return _reject("air_sensor_local_scope_capacity")
	if values.operation == "strike":
		if float(asset.stock.ammunition) <= 0.0 or not _received_target(actor, str(values.target_ref), str(values.target_node)):
			return _reject("finite_load_and_received_target_information_required")
	elif values.operation == "intercept":
		if not asset.interceptor or float(asset.stock.ammunition) <= 0.0 or not _received_target(actor, str(values.target_ref), str(values.target_node), "air_track"):
			return _reject("interceptor_and_received_air_track_required")
	elif not str(values.target_ref).is_empty():
		return _reject("recon_has_no_truth_target_reference")
	return {"ok": true}

func _received_target(actor: String, unit: String, node: String, fact: String = "air_contact") -> bool:
	var g: RefCounted = _owner.get_ref()
	for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).get("entries", []):
		if (claim.fact_kind == fact or fact == "air_contact" and claim.fact_kind == "sea_contact") and claim.subject_ref == unit and claim.claimed_value.get("node_ref", "") == node and float(claim.reliability) > 0.0:
			return true
	return false

func apply(actor: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var asset: Dictionary = assets[values.asset_ref]
	if values.operation == "cancel_recovery":
		recovery.interrupt(asset, "RECOVERY_CANCELLED_AT_ACTUAL_POSITION")
		return {"ok": true, "state_delta": {"air_recovery": {"status": asset.status}}}
	if values.operation in ["recover", "recover_land"]:
		recovery.start(actor, asset, values, id)
		return {"ok": true, "state_delta": {"air_recovery": {"job_ref": id, "status": asset.status}}}
	if values.operation == "service":
		support.start(actor, asset, values, id)
		return {"ok": true, "state_delta": {"air_service": {"job_ref": id, "status": asset.status}}}
	if values.operation == "abort":
		var old: Dictionary = missions[asset.mission_ref]
		old.abort_requested = true
		old.status = "ABORTED_RETURNING"
		if asset.status in ["RETURNING", "LANDING"]:
			return {"ok": true, "state_delta": {"air_task": {"status": old.status, "mission_ref": old.id}}}
		_checkpoint(asset)
		asset.version += 1
		old.return_index = 0
		if asset.status in ["TAKING_OFF", "LANDING"]:
			_begin(asset, "LANDING", asset.xy, maxf(1.0, float(asset.altitude_km) / float(rules.descent_km_s)))
		else:
			_leg(asset, old, true)
		return {"ok": true, "state_delta": {"air_task": {"status": old.status, "mission_ref": old.id}}}
	asset.version += 1
	var mission: Dictionary = {"id": id, "issuer": actor, "asset_ref": asset.id, "operation": values.operation,
		"target_node": values.target_node, "target_ref": values.target_ref, "outbound": values.outbound.duplicate(),
		"inbound": values.inbound.duplicate(), "out_index": 0, "return_index": 0, "started_at": g._state.time, "status": "TAKING_OFF"}
	mission.observe_unit = str(values.get("observe_unit", ""))
	mission.observe_vessel = str(values.get("observe_vessel", ""))
	mission.survey_edges = values.get("survey_edges", []).duplicate()
	missions[id] = mission
	asset.mission_ref = id
	_begin(asset, "TAKING_OFF", asset.xy, float(rules.takeoff_seconds))
	return {"ok": true, "state_delta": {"air_task": {"status": mission.status, "mission_ref": id}}}

func _begin(asset: Dictionary, mode: String, destination: Array, seconds: float, node: String = "") -> void:
	var g: RefCounted = _owner.get_ref()
	var duration: float = maxf(1.0, seconds)
	var available: float = float(asset.stock.fuel) / float(asset.fuel_per_second)
	var fuel_limited: bool = mode != "EMERGENCY_DESCENT" and available + 0.0000001 < duration
	var until: float = minf(duration, available) if fuel_limited else duration
	asset.leg = {"from": asset.xy.duplicate(), "to": destination.duplicate(), "started_at": g._state.time,
		"duration": duration, "due": g._state.time + maxf(0.000001, until), "node": node, "fuel_limited": fuel_limited}
	asset.leg.altitude_from = asset.altitude_km
	asset.leg.altitude_to = asset.cruise_altitude_km if mode == "TAKING_OFF" else (0.0 if mode in ["LANDING", "EMERGENCY_DESCENT"] else asset.altitude_km)
	asset.status = mode
	asset.leg.serial = _serial + 1
	_ticket(asset, "STAGE", float(asset.leg.due), {"leg_serial": asset.leg.serial})
	_contact_ticket(asset, g._state.time + minf(float(rules.contact_seconds), duration * 0.5))
	if missions.has(asset.mission_ref):
		_status_report(asset, str(missions[asset.mission_ref].issuer), "air_navigation_%d" % _serial, "air_status", mode)

func _ticket(asset: Dictionary, kind: String, due: float, extra: Dictionary = {}) -> void:
	var g: RefCounted = _owner.get_ref()
	_serial += 1
	var ticket: String = "air_%d" % _serial
	_tickets[ticket] = {"asset_ref": asset.id, "version": asset.version, "due": due, "kind": kind}
	_tickets[ticket].merge(extra)
	assert(g._state.schedule_event(ticket, due, "gameplay", {"air_id": ticket}))

func _contact_ticket(asset: Dictionary, due: float) -> void:
	if airborne(str(asset.id)) and due + 0.0000001 < float(asset.leg.due):
		_ticket(asset, "CONTACT", due, {"leg_serial": asset.leg.serial})

func _leg(asset: Dictionary, mission: Dictionary, returning: bool) -> void:
	var g: RefCounted = _owner.get_ref()
	var path: Array = mission.inbound if returning else mission.outbound
	var index: int = int(mission.return_index if returning else mission.out_index)
	if index >= path.size():
		if returning:
			_begin(asset, "LANDING", asset.xy, float(rules.landing_seconds))
		else:
			_begin(asset, "OBSERVING", asset.xy, float(rules.intercept_seconds) if mission.operation == "intercept" else float(rules.observe_seconds))
		return
	var node: String = str(path[index])
	var point: Array = g._space._nodes[node].xy
	_begin(asset, "RETURNING" if returning else "OUTBOUND", point, _distance(asset.xy, point) / speed(asset), node)

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and payload.get("air_id", "") == id and _tickets.has(id) and _tickets[id].due == due

func process_event(event: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var ticket: Dictionary = _tickets[event.id]
	_tickets.erase(event.id)
	var asset: Dictionary = assets[ticket.asset_ref]
	if int(ticket.version) != int(asset.version):
		return {"changed": [], "retired": [], "record": {"kind": "obsolete_air_event"}}
	if ticket.kind == "SERVICE":
		support.process(asset, ticket)
		return {"changed": [], "retired": [], "record": {"kind": "air_service_stage", "asset_ref": asset.id, "status": asset.status}}
	if ticket.kind == "RECOVERY":
		return recovery.process(asset, ticket)
	if not asset.has("leg") or ticket.leg_serial != asset.leg.serial:
		return {"changed": [], "retired": [], "record": {"kind": "obsolete_air_leg"}}
	if ticket.kind == "CONTACT":
		var affected: Dictionary = defense.engage(asset, str(event.id))
		if int(ticket.version) == int(asset.version):
			_air_contact(asset, str(event.id))
		if int(ticket.version) == int(asset.version):
			_contact_ticket(asset, g._state.time + float(rules.contact_seconds))
		affected.record = {"kind": "air_contact_opportunity", "asset_ref": asset.id, "time": g._state.time}
		return affected
	var mode: String = str(asset.status)
	var mission: Dictionary = missions[asset.mission_ref]
	_checkpoint(asset)
	if asset.leg.fuel_limited:
		mission.status = "INTERRUPTED_FUEL_EXHAUSTED"
		_emergency(asset)
		return {"changed": [], "retired": [], "record": {"kind": "air_fuel_interruption", "asset_ref": asset.id}}
	if not str(asset.leg.node).is_empty():
		asset.node = asset.leg.node
	var changes: Dictionary = {"changed": [], "retired": []}
	match mode:
		"TAKING_OFF":
			asset.altitude_km = asset.cruise_altitude_km
			mission.status = "OUTBOUND"
			_leg(asset, mission, false)
		"OUTBOUND":
			mission.out_index += 1
			_leg(asset, mission, false)
		"OBSERVING":
			if float(asset.integrity) >= float(rules.sensor_integrity):
				_sensor(asset, mission, str(event.id))
			if mission.operation == "strike" and float(asset.integrity) >= float(rules.weapon_integrity):
				changes = _strike(asset, mission, str(event.id))
			mission.status = "RETURNING"
			_leg(asset, mission, true)
		"RETURNING":
			mission.return_index += 1
			_leg(asset, mission, true)
		"LANDING":
			asset.altitude_km = 0.0
			asset.serviceable = float(asset.integrity) >= float(rules.return_integrity)
			asset.status = "LANDED" if support.usable(asset) else "AWAITING_RECOVERY"
			if asset.status == "AWAITING_RECOVERY":
				asset.landing = g._space.landing_site(asset.xy, str(asset.node))
				asset.node = asset.landing.node_ref
				asset.serviceable = false
			mission.status = ("ABORTED" if mission.get("abort_requested", false) else "RETURNED") if asset.status == "LANDED" else "BASE_UNAVAILABLE_LANDED"
			_status_report(asset, str(mission.issuer), str(event.id), "air_status", str(mission.status))
		"EMERGENCY_DESCENT":
			asset.status = "AWAITING_RECOVERY"
			asset.altitude_km = 0.0
			asset.landing = g._space.landing_site(asset.xy, str(asset.node))
			asset.node = asset.landing.node_ref
			asset.landing.landed_at = g._state.time
			mission.status = "INTERRUPTED_LANDED_AWAY_FROM_BASE"
			_status_report(asset, str(mission.issuer), str(event.id), "air_status", str(mission.status))
	changes.record = {"kind": "air_stage", "asset_ref": asset.id, "mission_ref": mission.id, "status": asset.status, "time": g._state.time}
	return changes

func _sensor(asset: Dictionary, mission: Dictionary, cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var claims: Array[Dictionary] = []
	var side: String = str(g._state.structure_port.get_ref()._nodes[asset.owner].side)
	var cell: String = str(g._space._nodes[mission.target_node].cell)
	var recipients: Array[String] = [str(mission.issuer)]
	var commander: String = str(g._state.structure_port.get_ref()._positions.get(asset.owner, {}).get("person", ""))
	if not commander.is_empty() and commander not in recipients and _authorized(commander, asset):
		recipients.append(commander)
	for unit_id: String in g._space.combat_ids(cell):
		if claims.size() >= MAX_CONTACTS:
			break
		var unit: Dictionary = g._state.units[unit_id]
		var ground: Dictionary = g._space.terrain(unit)
		var quality: float = float(asset.cloud_visibility) * float(ground.visibility) * (1.0 - float(ground.concealment))
		var point: Array = g._space.xy(unit)
		if (unit.side == side and unit_id != mission.get("observe_unit", "")) or unit.side != side and float(unit.effective) <= 0.0 or _distance(asset.xy, point) > float(asset.sensor_radius_km) or quality <= 0.0:
			continue
		var precision: float = float(asset.precision_km) / maxf(0.1, quality)
		var band: Array = [floorf(float(point[0]) / precision) * precision, floorf(float(point[1]) / precision) * precision]
		claims.append({"id": cause + "_" + unit_id, "source_ref": asset.id, "subject_kind": "unit", "subject_ref": unit_id,
			"fact_kind": ("unit_condition" if float(unit.effective) <= 0.001 else "friendly_contact") if unit.side == side else "air_contact",
			"value": {"node_ref": unit.spatial.node, "area_ref": unit.area_id, "xy_band": [band, [float(band[0]) + precision, float(band[1]) + precision]], "states": [unit.action], "condition": "INCAPACITATED" if float(unit.effective) <= 0.001 else "PRESENT", "mission_ref": mission.id},
			"observed_at": g._state.time, "observer_ref": asset.id, "origin": "AIR_RECON", "quality": quality, "precision": "air_sensor_band"})
	for vessel_id: String in g.sea.vessels:
		var vessel: Dictionary = g.sea.vessels[vessel_id]
		var sea_node: Dictionary = g._space._nodes[g.sea.contact_node(vessel_id)]
		var quality: float = float(asset.cloud_visibility) * float(asset.integrity) * float(sea_node.get("sea_visibility", 1.0))
		var friendly: bool = g._state.structure_port.get_ref()._nodes[vessel.owner].side == side
		if claims.size() >= MAX_CONTACTS or vessel.status == "SUNK" or friendly and vessel_id != mission.get("observe_vessel", "") or quality <= 0.0 or _distance(asset.xy, g.sea.position(vessel_id)) > float(asset.sensor_radius_km):
			continue
		if friendly:
			claims.append({"id": cause + "_friendly_" + vessel_id, "source_ref": asset.id, "subject_kind": "vessel", "subject_ref": vessel_id,
				"fact_kind": "friendly_sea_contact", "value": {"node_ref": g.sea.contact_node(vessel_id), "mission_ref": mission.id, "condition": "PRESENT", "coverage": "LOCAL_SENSOR_ONLY"},
				"observed_at": g._state.time, "observer_ref": asset.id, "origin": "AIR_SEA_RECON", "quality": quality, "precision": "local_presence_only"})
		else:
			claims.append(g.sea.contact_claim(str(asset.id), vessel_id, cause, quality, "AIR_SEA_RECON"))
	if mission.operation == "recon":
		var surveyed: Array[Dictionary] = []
		for edge_ref: String in mission.get("survey_edges", []):
			var edge: Dictionary = g._space._edges[edge_ref]
			# A flyover can describe an entry. Traversability requires a ground traversal.
			for node: String in [str(edge.from), str(edge.to)]:
				var point: Array = g._space._nodes[node].xy
				var quality: float = float(asset.cloud_visibility) * float(asset.integrity) * float(g._space._nodes[node].ground.visibility)
				if quality > 0.0 and _distance(asset.xy, point) <= float(asset.sensor_radius_km):
					surveyed.append({"id": cause + "_route_" + edge_ref + "_" + node, "source_ref": asset.id, "subject_kind": "route", "subject_ref": edge_ref,
						"fact_kind": "route_observation", "value": {"edge_ref": edge_ref, "node_ref": node, "state": "ENTRY_OBSERVED", "coverage": "LOCAL_AERIAL_ENTRY", "mission_ref": mission.id},
						"observed_at": g._state.time, "observer_ref": asset.id, "origin": "AIR_ROUTE_SURVEY", "quality": quality, "precision": "entry_visibility_only"})
		for recipient: String in recipients:
			if not surveyed.is_empty():
				g._state.information_port.get_ref().send_air_report(self, str(asset.id), recipient, "air_routes_" + cause + "_" + recipient, surveyed)
		# An empty contact set reports sensor coverage, never proof of a safe node.
		var summary: Array[Dictionary] = [{"id": cause + "_coverage", "source_ref": asset.id, "subject_kind": "area", "subject_ref": cell,
			"fact_kind": "recon_result", "value": {"node_ref": mission.target_node, "mission_ref": mission.id, "contacts_sampled": claims.filter(func(c: Dictionary) -> bool: return c.fact_kind in ["air_contact", "sea_contact"]).size(), "recovery_contacts": claims.filter(func(c: Dictionary) -> bool: return c.fact_kind in ["friendly_contact", "friendly_sea_contact", "unit_condition"]).size(), "coverage": "LOCAL_SENSOR_ONLY", "sought_unit": mission.get("observe_unit", ""), "sought_vessel": mission.get("observe_vessel", ""), "subject_confirmed": claims.any(func(c: Dictionary) -> bool: return c.subject_ref in [mission.get("observe_unit", ""), mission.get("observe_vessel", "")])},
			"observed_at": g._state.time, "observer_ref": asset.id, "origin": "AIR_RECON", "quality": float(asset.cloud_visibility) * float(asset.integrity), "precision": "bounded_sensor_coverage"}]
		for recipient: String in recipients:
			g._state.information_port.get_ref().send_air_report(self, str(asset.id), recipient, "recon_coverage_" + cause + "_" + recipient, summary)
	if not claims.is_empty():
		var sent: Dictionary = g._state.information_port.get_ref().send_air_report(self, str(asset.id), str(mission.issuer), "air_report_" + cause, claims)
		mission.report_status = "IN_TRANSIT" if sent.ok else str(sent.error)
		mission.report_ref = sent.get("message_id", "")
		for recipient: String in recipients:
			if recipient != mission.issuer:
				g._state.information_port.get_ref().send_air_report(self, str(asset.id), recipient, "air_report_" + cause + "_" + recipient, claims)
	else:
		mission.report_status = "NO_OBSERVATION_OPPORTUNITY"

func _strike(asset: Dictionary, mission: Dictionary, cause: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var target: String = str(mission.target_ref)
	if g.sea.vessels.has(target):
		var vessel: Dictionary = g.sea.vessels[target]
		var node: Dictionary = g._space._nodes[g.sea.contact_node(target)]
		if vessel.status == "SUNK" or g._state.structure_port.get_ref()._nodes[vessel.owner].side == g._state.structure_port.get_ref()._nodes[asset.owner].side or _distance(asset.xy, g.sea.position(target)) > float(asset.weapon.radius_km) or float(asset.altitude_km) < float(asset.weapon.minimum_altitude) or float(asset.altitude_km) > float(asset.weapon.maximum_altitude) or float(node.get("sea_visibility", 1.0)) * float(asset.cloud_visibility) <= 0.0:
			mission.strike_status = "NO_ACTUAL_SURFACE_ATTACK_OPPORTUNITY"
			return {"changed": [], "retired": []}
		var surface_rounds: float = g._state.logistics_port.get_ref().consume_air(str(asset.id), "ammunition", float(asset.weapon.rounds_per_pass))
		g.sea.damage(target, surface_rounds * float(asset.weapon.surface_damage_per_round) * float(asset.integrity) * float(asset.cloud_visibility), cause)
		mission.strike_status = "ACTUAL_SURFACE_FIRE_APPLIED"
		return {"changed": [], "retired": []}
	if not g._state.knows_unit(target):
		mission.strike_status = "TARGET_NO_LONGER_REPRESENTED"
		return {"changed": [], "retired": []}
	var unit: Dictionary = g._state.units[target] if g._state.units.has(target) else g._lod.preview_leaf(target)
	var location: Dictionary = {}
	for candidate: Dictionary in g.tactics.ground_sources(unit):
		if _distance(asset.xy, g._space.xy(candidate)) <= float(asset.weapon.radius_km) and float(g._space.terrain(candidate).visibility) > 0.0:
			location = candidate
			break
	if location.is_empty() or float(asset.altitude_km) < float(asset.weapon.minimum_altitude) or float(asset.altitude_km) > float(asset.weapon.maximum_altitude):
		mission.strike_status = "TARGET_OUTSIDE_ACTUAL_ATTACK_OPPORTUNITY"
		return {"changed": [], "retired": []}
	var materialized: Dictionary = {"changed": [], "retired": []}
	if not g._state.units.has(target):
		materialized = g._lod.materialize_leaf(target, "actual_air_ground_effect")
		unit = g._state.units[target]
	var rounds: float = g._state.logistics_port.get_ref().consume_air(str(asset.id), "ammunition", minf(float(asset.stock.ammunition), float(asset.weapon.rounds_per_pass)))
	var kernel: RefCounted = g._lod._kernel
	kernel.direct_fire(g._state, unit, rounds, float(asset.weapon.lethality), cause, g._space.xy(location))
	mission.strike_status = "ACTUAL_FIRE_APPLIED"
	var changed: Array = materialized.get("changed", [])
	if target not in changed:
		changed.append(target)
	return {"changed": changed, "retired": materialized.get("retired", [])}

func position(id: String) -> Array:
	var g: RefCounted = _owner.get_ref()
	var asset: Dictionary = assets[id]
	if asset.get("recovery_ref", "") != "" and g.land.jobs.has(asset.recovery_ref):
		return g.land.aircraft_position(asset)
	if asset.get("recovery_ref", "") != "" and g.sea.recovery.jobs.has(asset.recovery_ref):
		return g.sea.recovery.position(asset)
	if asset.status == "RECOVERING":
		return recovery.position(asset)
	if not airborne(id) or not asset.has("leg"):
		return asset.xy.duplicate()
	var fraction: float = clampf((g._state.time - float(asset.leg.started_at)) / float(asset.leg.duration), 0.0, 1.0)
	return [lerpf(float(asset.leg.from[0]), float(asset.leg.to[0]), fraction), lerpf(float(asset.leg.from[1]), float(asset.leg.to[1]), fraction)]

func altitude(id: String) -> float:
	var asset: Dictionary = assets[id]
	if not asset.has("leg") or asset.status not in ["TAKING_OFF", "LANDING", "EMERGENCY_DESCENT"]:
		return float(asset.altitude_km)
	var fraction: float = clampf((_owner.get_ref()._state.time - float(asset.leg.started_at)) / float(asset.leg.duration), 0.0, 1.0)
	return lerpf(float(asset.leg.altitude_from), float(asset.leg.altitude_to), fraction)

func own_view(actor: String) -> Array[Dictionary]:
	var g: RefCounted = _owner.get_ref()
	var result: Array[Dictionary] = []
	for id: String in assets:
		var asset: Dictionary = assets[id]
		if not _authorized(actor, asset) and missions.get(asset.mission_ref, {}).get("issuer", "") != actor:
			continue
		var known: Dictionary = asset.initial_report.duplicate(true)
		var updates: Array[Dictionary] = []
		for fact: String in ["air_status", "air_service", "air_recovery", "land_supply_status", "sea_recovery_status", "water_recovery_contact"]:
			updates.append_array(g._state.information_port.get_ref().knowledge(actor, "aircraft", id, fact).get("entries", []))
		updates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.observed_at) < float(b.observed_at) if a.observed_at != b.observed_at else float(a.received_at) < float(b.received_at))
		for claim: Dictionary in updates:
			if float(claim.reliability) <= 0.0:
				continue
			var value: Dictionary = claim.claimed_value
			for field: String in ["base", "node_ref", "xy", "altitude_km", "fuel", "load", "equipment", "integrity", "serviceable", "mission_ref", "service_ref", "recovery_ref"]:
				if value.has(field):
					known[field] = value[field]
			if value.has("asset_status"):
				known.status = value.asset_status
			if value.has("surface"):
				known.landing = {"surface": value.surface, "node_ref": value.get("node_ref", ""), "xy": value.get("xy", []).duplicate()}
			known.observed_at = claim.observed_at
			known.received_at = claim.received_at
			if value.get("surface", "") == "WATER" and not value.has("xy"):
				known.xy = []
				known.xy_band = value.get("xy_band", [])
		known.classification = "LAST_RECEIVED_OWN_AIR_STATUS"
		result.append(known)
	return result

func airborne(id: String) -> bool:
	return assets.has(id) and assets[id].status in ["TAKING_OFF", "OUTBOUND", "OBSERVING", "RETURNING", "LANDING", "EMERGENCY_DESCENT"]

func speed(asset: Dictionary) -> float:
	return float(asset.speed_km_s) * (0.35 + 0.65 * float(asset.integrity))

func _checkpoint(asset: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	var here: Array = position(str(asset.id))
	var height: float = altitude(str(asset.id))
	if airborne(str(asset.id)) and asset.status != "EMERGENCY_DESCENT" and asset.has("leg"):
		var since: float = float(asset.leg.get("settled_at", asset.leg.started_at))
		g._state.logistics_port.get_ref().consume_air(str(asset.id), "fuel", maxf(0.0, g._state.time - since) * float(asset.fuel_per_second))
		asset.leg.settled_at = g._state.time
	asset.xy = here
	asset.altitude_km = height

func _emergency(asset: Dictionary) -> void:
	asset.serviceable = false
	asset.version += 1
	var dx: float = float(asset.leg.to[0]) - float(asset.leg.from[0])
	var dy: float = float(asset.leg.to[1]) - float(asset.leg.from[1])
	var norm: float = maxf(0.000001, sqrt(dx * dx + dy * dy))
	var seconds: float = maxf(1.0, float(asset.altitude_km) / float(rules.descent_km_s))
	_begin(asset, "EMERGENCY_DESCENT", [float(asset.xy[0]) + dx / norm * float(rules.glide_km_s) * seconds,
		float(asset.xy[1]) + dy / norm * float(rules.glide_km_s) * seconds], seconds)

func damage(id: String, dose: float, cause: String) -> void:
	if not assets.has(id) or assets[id].status == "DESTROYED" or dose <= 0.0:
		return
	var g: RefCounted = _owner.get_ref()
	var asset: Dictionary = assets[id]
	var flying: bool = airborne(id)
	var mode: String = str(asset.status)
	var old_speed: float = speed(asset)
	_checkpoint(asset)
	asset.integrity = maxf(0.0, float(asset.integrity) - dose)
	asset.last_damage = {"cause_ref": cause, "at": g._state.time, "dose": dose}
	asset.serviceable = float(asset.integrity) >= float(rules.return_integrity)
	if float(asset.integrity) <= 0.0:
		asset.version += 1
		asset.status = "DESTROYED"
		asset.serviceable = false
		g._state.logistics_port.get_ref().destroy_asset(id)
		support.interrupt(asset, "AIRCRAFT_DESTROYED")
		recovery.interrupt(asset, "AIRCRAFT_DESTROYED")
		if missions.has(asset.mission_ref):
			missions[asset.mission_ref].status = "AIRCRAFT_DESTROYED"
			_status_report(asset, str(missions[asset.mission_ref].issuer), cause, "air_status", "AIRCRAFT_DESTROYED")
		return
	if not flying or mode == "EMERGENCY_DESCENT":
		return
	var mission: Dictionary = missions[asset.mission_ref]
	if float(asset.integrity) <= float(rules.flight_integrity) or float(asset.stock.fuel) <= 0.0:
		mission.status = "FLIGHT_DISABLED_DESCENDING"
		_emergency(asset)
		return
	asset.version += 1
	if not asset.serviceable and mode not in ["RETURNING", "LANDING"]:
		mission.status = "DAMAGE_FORCED_RETURN"
		mission.abort_requested = true
		mission.return_index = 0
		_leg(asset, mission, true)
	else:
		var destination: Array = asset.leg.to.duplicate()
		var node: String = str(asset.leg.node)
		var remaining: float = maxf(0.000001, float(asset.leg.duration) - (g._state.time - float(asset.leg.started_at)))
		if mode in ["OUTBOUND", "RETURNING"]:
			remaining *= old_speed / speed(asset)
		_begin(asset, mode, destination, remaining, node)

func contact_node(id: String) -> String:
	var asset: Dictionary = assets[id]
	if not airborne(id):
		return str(asset.node)
	var next: String = str(asset.get("leg", {}).get("node", ""))
	if next.is_empty():
		return str(asset.node)
	var space: RefCounted = _owner.get_ref()._space
	return next if _distance(position(id), space._nodes[next].xy) < _distance(position(id), space._nodes[asset.node].xy) else str(asset.node)

func track_claim(observer: String, target: String, cause: String, quality: float, origin: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var point: Array = position(target)
	var precision: float = float(assets[target].precision_km) / maxf(0.1, quality)
	var band: Array = [floorf(float(point[0]) / precision) * precision, floorf(float(point[1]) / precision) * precision]
	return {"id": cause + "_" + target, "source_ref": observer, "subject_kind": "aircraft", "subject_ref": target, "fact_kind": "air_track",
		"value": {"node_ref": contact_node(target), "xy_band": [band, [float(band[0]) + precision, float(band[1]) + precision]], "altitude_band": [floorf(altitude(target) / 0.1) * 0.1, floorf(altitude(target) / 0.1) * 0.1 + 0.1]},
		"observed_at": g._state.time, "observer_ref": observer, "origin": origin, "quality": quality, "precision": "air_sensor_band"}

func _air_contact(asset: Dictionary, cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if not airborne(str(asset.id)) or float(asset.integrity) < float(rules.sensor_integrity):
		return
	var mission: Dictionary = missions[asset.mission_ref]
	var side: String = str(g._state.structure_port.get_ref()._nodes[asset.owner].side)
	for other_id: String in assets:
		var other: Dictionary = assets[other_id]
		if other_id == asset.id or not airborne(other_id) or g._state.structure_port.get_ref()._nodes[other.owner].side == side:
			continue
		var range_now: float = _distance(position(str(asset.id)), position(other_id))
		var quality: float = float(asset.cloud_visibility) * float(asset.integrity)
		if range_now > float(asset.sensor_radius_km) or absf(altitude(str(asset.id)) - altitude(other_id)) > float(asset.sensor_altitude_difference_km) or quality <= 0.0:
			continue
		if g._state.time >= float(mission.get("next_track_report", 0.0)):
			g._state.information_port.get_ref().send_platform_report(self, str(asset.id), str(mission.issuer), "track_" + cause, [track_claim(str(asset.id), other_id, cause, quality, "AIR_VISUAL")])
			mission.next_track_report = g._state.time + float(rules.report_interval_seconds)
		if mission.operation != "intercept" or mission.target_ref != other_id or not asset.interceptor or float(asset.integrity) < float(rules.weapon_integrity) or g._state.time < float(asset.next_air_fire):
			continue
		var weapon: Dictionary = asset.air_weapon
		var height_difference: float = absf(altitude(str(asset.id)) - altitude(other_id))
		if range_now > float(weapon.range_km) or height_difference > float(weapon.altitude_difference_km) or not _forward_arc(asset, position(other_id), float(weapon.arc_degrees)):
			continue
		var rounds: float = g._state.logistics_port.get_ref().consume_air(str(asset.id), "ammunition", float(weapon.rounds))
		if rounds <= 0.0:
			continue
		asset.next_air_fire = g._state.time + float(weapon.interval_seconds)
		var closure: float = speed(asset) / maxf(0.000001, speed(asset) + speed(other))
		var aim: float = quality * (1.0 - 0.5 * range_now / float(weapon.range_km)) * (1.0 - 0.5 * height_difference / float(weapon.altitude_difference_km))
		var maneuver_factor: float = (0.5 + closure * float(asset.maneuver)) / (1.0 + float(other.maneuver))
		damage(other_id, rounds * float(weapon.damage_per_round) * aim * maneuver_factor, cause + "_air_fire_" + str(asset.id))
		mission.last_engagement = {"at": g._state.time, "target": other_id, "rounds": rounds}

func _forward_arc(asset: Dictionary, target: Array, degrees: float) -> bool:
	var direction: Array = [float(asset.leg.to[0]) - float(asset.leg.from[0]), float(asset.leg.to[1]) - float(asset.leg.from[1])]
	if absf(float(direction[0])) + absf(float(direction[1])) <= 0.000001:
		direction = asset.get("heading", [1.0, 0.0])
	else:
		asset.heading = direction
	var here: Array = position(str(asset.id))
	var bearing: float = atan2(float(target[1]) - float(here[1]), float(target[0]) - float(here[0]))
	var heading: float = atan2(float(direction[1]), float(direction[0]))
	return absf(wrapf(bearing - heading, -PI, PI)) <= deg_to_rad(degrees * 0.5)

func _status_report(asset: Dictionary, recipient: String, cause: String, fact: String, status: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var value: Dictionary = {"node_ref": contact_node(str(asset.id)), "status": status, "asset_status": asset.status,
		"base": asset.base, "surface": asset.get("landing", {}).get("surface", "UNKNOWN"), "integrity": asset.integrity,
		"fuel": asset.stock.fuel, "load": asset.stock.ammunition, "serviceable": asset.serviceable, "recovery_ref": asset.get("recovery_ref", ""),
		"equipment": asset.stock.equipment, "altitude_km": altitude(str(asset.id)), "mission_ref": asset.mission_ref, "service_ref": asset.service_ref}
	if value.surface != "WATER":
		value.xy = position(str(asset.id))
	var claim: Dictionary = {"id": cause + "_status", "source_ref": asset.id, "subject_kind": "aircraft", "subject_ref": asset.id,
		"fact_kind": fact, "value": value, "observed_at": g._state.time,
		"observer_ref": asset.id, "origin": "PLATFORM_STATUS", "quality": 1.0, "precision": "own_status"}
	g._state.information_port.get_ref().send_platform_report(self, str(asset.id), recipient, "status_" + cause, [claim])
	var commander: String = str(g._state.structure_port.get_ref()._positions.get(asset.owner, {}).get("person", ""))
	if not commander.is_empty() and commander != recipient and _authorized(commander, asset):
		g._state.information_port.get_ref().send_platform_report(self, str(asset.id), commander, "status_" + cause + "_current_" + commander, [claim])

static func _distance(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["assets", "missions", "_tickets", "_serial", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
