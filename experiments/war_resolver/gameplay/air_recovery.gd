extends RefCounted
## Local ground handling uses an existing unit. No implicit heavy road transport.
var _air: WeakRef
var crews: Dictionary = {}
var jobs: Dictionary = {}
var _unit_jobs: Dictionary = {}
const MAX_JOBS: int = 64
var rules: Dictionary = {"radius_km": 0.03, "crew": 2.0, "equipment": 1.0,
	"spares": 0.25, "handling_seconds": 60.0, "drag_speed_km_s": 0.0005}

func configure(air: RefCounted) -> void:
	_air = weakref(air)

func admit(unit: String) -> bool:
	var g: RefCounted = _air.get_ref()._owner.get_ref()
	if g._state.time != 0.0 or crews.size() >= 2 or crews.has(unit) or not g._lod.has_leaf(unit):
		return false
	crews[unit] = {"local_ground_handling": true, "heavy_transport": false}
	return true

func validate(actor: String, asset: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var air: RefCounted = _air.get_ref()
	var g: RefCounted = air._owner.get_ref()
	if values.get("operation", "") == "recover_land":
		return _validate_land(actor, asset, values, id)
	if values.size() != 4 or not values.get("unit_ref") is String or not values.get("base_ref") is String or not crews.has(values.unit_ref) or not air.support.bases.has(values.base_ref) or jobs.has(id) or jobs.size() >= MAX_JOBS:
		return air._reject("explicit_existing_local_recovery_unit_and_base_required")
	if asset.status != "AWAITING_RECOVERY" or float(asset.stock.equipment) <= 0.0 or float(asset.integrity) <= 0.0 or asset.get("landing", {}).get("surface", "UNKNOWN") != "LAND":
		return air._reject("recoverable_actual_land_landing_required")
	var s: RefCounted = g._state.structure_port.get_ref()
	var base: Dictionary = air.support.bases[values.base_ref]
	if base.owner != asset.owner or not s._contains(str(s.command_person(actor).formation_id), str(s._unit_nodes.get(values.unit_ref, ""))) or not g._known.get(actor, {}).has(values.base_ref):
		return air._reject("known_own_base_and_commanded_recovery_unit_required")
	if not _available(str(values.unit_ref), asset, str(values.base_ref), true):
		return air._reject("same_land_node_nearby_crew_equipment_spares_and_open_base_required")
	return {"ok": true}

func _available(unit_id: String, asset: Dictionary, base: String, starting: bool) -> bool:
	var air: RefCounted = _air.get_ref()
	var g: RefCounted = air._owner.get_ref()
	if not g._state.units.has(unit_id) or not g._lod.has_leaf(unit_id) or not g._state.structure_port.get_ref().active(str(asset.owner)):
		return false
	var unit: Dictionary = g._state.units[unit_id]
	var local_crew: float = float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))
	if starting and (_unit_jobs.has(unit_id) or g.land._unit_jobs.has(unit_id) or g.operations.occupied_ground(unit_id) or g.tactics.occupied(unit_id) or not g._state.coordination.get(unit_id, {}).is_empty()):
		return false
	return unit.has("spatial") and str(unit.spatial.edge).is_empty() and unit.spatial.path.is_empty() and unit.spatial.node == base and asset.landing.node_ref == base and not g._space._nodes[base].get("water", false) and g._space._nodes[base].get("airfield_open", true) and local_crew >= float(rules.crew) and float(unit.serviceable_equipment) >= float(rules.equipment) and (not starting or float(unit.spares) >= float(rules.spares)) and air._distance(g._space.xy(unit), asset.xy) <= float(rules.radius_km)

func start(actor: String, asset: Dictionary, values: Dictionary, id: String) -> void:
	var air: RefCounted = _air.get_ref()
	var g: RefCounted = air._owner.get_ref()
	if values.operation == "recover_land":
		asset.recovery_ref = id
		asset.serviceable = false
		asset.version += 1
		g.land.start_aircraft(actor, id, str(values.unit_ref), str(asset.id), str(values.pickup_node), str(values.base_ref), values.approach_path, values.path)
		return
	var unit: Dictionary = g._state.units[values.unit_ref]
	var seconds: float = float(rules.handling_seconds) + air._distance(asset.xy, g._space._nodes[values.base_ref].xy) / float(rules.drag_speed_km_s)
	jobs[id] = {"id": id, "asset_ref": asset.id, "unit_ref": values.unit_ref, "base_ref": values.base_ref,
		"issuer": actor, "from": asset.xy.duplicate(), "to": g._space._nodes[values.base_ref].xy.duplicate(),
		"started_at": g._state.time, "due": g._state.time + seconds, "status": "RECOVERING"}
	unit.spares -= float(rules.spares)
	unit.spares_spent += float(rules.spares)
	g._state.logistics_ledger.spares_spent += float(rules.spares)
	_unit_jobs[values.unit_ref] = id
	g._state.coordination[values.unit_ref] = {"role": "local_air_recovery", "retained": true, "recovery_ref": id, "status": "waiting"}
	g._state.wake(str(unit.area_id))
	asset.recovery_ref = id
	asset.version += 1
	asset.serviceable = false
	asset.status = "RECOVERING"
	air._ticket(asset, "RECOVERY", g._state.time + seconds, {"job_ref": id})

func position(asset: Dictionary) -> Array:
	var job: Dictionary = jobs[asset.recovery_ref]
	var now: float = _air.get_ref()._owner.get_ref()._state.time
	var moving_since: float = float(job.started_at) + float(rules.handling_seconds)
	var fraction: float = clampf((now - moving_since) / maxf(0.000001, float(job.due) - moving_since), 0.0, 1.0)
	return [lerpf(float(job.from[0]), float(job.to[0]), fraction), lerpf(float(job.from[1]), float(job.to[1]), fraction)]

func process(asset: Dictionary, ticket: Dictionary) -> Dictionary:
	var job: Dictionary = jobs[ticket.job_ref]
	var valid: bool = asset.status == "RECOVERING" and asset.recovery_ref == job.id and _available(str(job.unit_ref), asset, str(job.base_ref), false) and _air.get_ref()._owner.get_ref()._state.coordination.get(job.unit_ref, {}).get("recovery_ref", "") == job.id
	_finish(asset, job, "RECOVERED_AT_BASE" if valid else "RECOVERY_INTERRUPTED", valid)
	return {"changed": [job.unit_ref], "retired": [], "record": {"kind": "air_recovery", "job_ref": job.id, "status": job.status}}

func on_unit(id: String) -> void:
	if not _unit_jobs.has(id):
		return
	var job: Dictionary = jobs[_unit_jobs[id]]
	var asset: Dictionary = _air.get_ref().assets[job.asset_ref]
	var g: RefCounted = _air.get_ref()._owner.get_ref()
	if not _available(id, asset, str(job.base_ref), false) or g._state.coordination.get(id, {}).get("recovery_ref", "") != job.id:
		_finish(asset, job, "RECOVERY_CREW_UNAVAILABLE", false)

func interrupt(asset: Dictionary, reason: String) -> void:
	var g: RefCounted = _air.get_ref()._owner.get_ref()
	if g.sea.recovery.jobs.has(asset.get("recovery_ref", "")):
		g.sea.recovery._interrupt(g.sea.recovery.jobs[asset.recovery_ref], reason)
		return
	if g.land.jobs.has(asset.get("recovery_ref", "")):
		g.land._end(g.land.jobs[asset.recovery_ref], reason)
		return
	if asset.get("recovery_ref", "") != "":
		_finish(asset, jobs[asset.recovery_ref], reason, false)

func _validate_land(actor: String, asset: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var air: RefCounted = _air.get_ref()
	var g: RefCounted = air._owner.get_ref()
	if values.size() != 7 or not values.get("unit_ref") is String or not values.get("pickup_node") is String or not values.get("base_ref") is String or not values.get("approach_path") is Array or not values.get("path") is Array:
		return air._reject("explicit_ground_pickup_base_and_two_known_road_legs_required")
	if asset.status != "AWAITING_RECOVERY" or asset.get("recovery_ref", "") != "" or float(asset.integrity) <= 0.0 or float(asset.stock.equipment) <= 0.0 or asset.get("landing", {}).get("surface", "UNKNOWN") != "LAND":
		return air._reject("recoverable_actual_land_aircraft_required")
	if not g.land.carriers.get(values.unit_ref, {}).get("heavy_aircraft", false) or not g.land._free(actor, str(values.unit_ref)) or g.land.jobs.size() >= 64 or g.land.jobs.has(id) or not air.support.bases.has(values.base_ref) or air.support.bases[values.base_ref].owner != asset.owner or not g._space._nodes.has(values.pickup_node) or g._space._nodes[values.pickup_node].get("water", false):
		return air._reject("finite_heavy_ground_carrier_and_own_receiving_base_required")
	var unit: Dictionary = g._state.units[values.unit_ref]
	if g.land.capacity(unit) < float(g.land.rules.aircraft_load) or float(unit.spares) < float(g.land.rules.aircraft_spares) or air._distance(asset.xy, g._space._nodes[values.pickup_node].xy) > float(g.land.rules.local_radius_km) or asset.landing.node_ref != values.pickup_node:
		return air._reject("actual_local_access_to_declared_road_pickup_required")
	var known: bool = false
	for fact: String in ["air_status", "air_recovery", "sea_recovery_status", "land_supply_status"]:
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor, "aircraft", str(asset.id), fact).get("entries", []):
			if claim.claimed_value.get("node_ref", "") == values.pickup_node and float(claim.reliability) > 0.0:
				known = true
	if not known:
		return air._reject("delivered_aircraft_ground_location_report_required")
	var valid: Dictionary = g.land.route(actor, unit, str(values.pickup_node), values.approach_path)
	if not valid.ok:
		return valid
	var projected: Dictionary = unit.duplicate(true)
	projected.spatial.node = values.pickup_node
	projected.spatial.edge = ""
	return g.land.route(actor, projected, str(values.base_ref), values.path)

func _finish(asset: Dictionary, job: Dictionary, status: String, completed: bool) -> void:
	var air: RefCounted = _air.get_ref()
	var g: RefCounted = air._owner.get_ref()
	asset.xy = position(asset) if asset.status == "RECOVERING" else asset.xy
	asset.version += 1
	asset.recovery_ref = ""
	job.status = status
	job.finished_at = g._state.time
	_unit_jobs.erase(job.unit_ref)
	if g._state.coordination.get(job.unit_ref, {}).get("recovery_ref", "") == job.id:
		g._state.coordination.erase(job.unit_ref)
	if g._state.units.has(job.unit_ref):
		g._state.wake(str(g._state.units[job.unit_ref].area_id))
	if asset.status != "DESTROYED":
		asset.status = "GROUNDED" if completed else "AWAITING_RECOVERY"
		asset.serviceable = false
		if completed:
			asset.xy = job.to.duplicate()
			asset.base = job.base_ref
			asset.node = job.base_ref
			asset.erase("leg")
			asset.landing.recovered_at = g._state.time
	air._status_report(asset, str(job.issuer), "recovery_" + str(job.id), "air_recovery", status)

const RUNTIME_FIELDS: Array[String] = ["crews", "jobs", "_unit_jobs", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
