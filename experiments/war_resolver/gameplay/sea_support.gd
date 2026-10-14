extends RefCounted
## Timed damage control and port repair consume the same Task6 stock/capacity.
var _sea: WeakRef
var ports: Dictionary = {}
var jobs: Dictionary = {}
var rules: Dictionary = {"damage_seconds": 30.0, "flood_loss_per_second": 0.003,
	"fire_loss_per_second": 0.004, "flood_per_hit": 0.25, "fire_per_hit": 0.15,
	"system_per_hit": 0.5, "control_effort": 0.6, "control_spares": 0.1,
	"flood_control_per_second": 0.002, "fire_control_per_second": 0.004,
	"repair_per_second": 0.002, "repair_spares_per_integrity": 2.0, "spares_capacity": 2.0}

func configure(sea: RefCounted) -> void:
	_sea = weakref(sea)

func admit_port(node: String, owner: String, depot: String, capacity: String) -> bool:
	var g: RefCounted = _sea.get_ref()._owner.get_ref()
	var l: RefCounted = g._state.logistics_port.get_ref()
	if g._state.time != 0.0 or ports.size() >= 4 or ports.has(node) or not g._space._nodes.has(node) or not g._space._nodes[node].get("port", false) or not l._depots.has(depot) or not l._capacities.has(capacity):
		return false
	if g._space._nodes[node].get("land_supply_node", "") != l._depots[depot].get("node_ref", "") or not g._state.structure_port.get_ref()._contains(str(l._depots[depot].allocation_scope), owner) or not g._state.structure_port.get_ref()._contains(str(l._capacities[capacity].scope), owner):
		return false
	ports[node] = {"node": node, "owner": owner, "depot": depot, "capacity_ref": capacity, "busy": ""}
	return true

func port_at(vessel: Dictionary) -> String:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	for node: String in ports:
		var port: Dictionary = ports[node]
		if s.active(str(port.owner)) and s.active(str(vessel.owner)) and s._nodes[port.owner].side == s._nodes[vessel.owner].side and g._space._nodes[node].get("port_open", true) and sea._distance(sea.position(str(vessel.id)), g._space._nodes[node].xy) <= 0.000001:
			return node
	return ""

func available_crew(vessel: Dictionary) -> float:
	return float(vessel.damage_control_capacity) * float(vessel.integrity) * float(vessel.stock.equipment)

func local_observation(vessel: Dictionary) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	var l: RefCounted = g._state.logistics_port.get_ref()
	for node: String in ports:
		var port: Dictionary = ports[node]
		if not s.active(str(port.owner)) or s._nodes[port.owner].side != s._nodes[vessel.owner].side or sea._distance(sea.position(str(vessel.id)), g._space._nodes[node].xy) > 0.000001:
			continue
		var stock: Dictionary = {}
		for resource: String in l.CLASSES:
			stock[resource] = l.available_stock(str(port.depot), resource)
		return {"port_ref": node, "depot_ref": port.depot, "node_ref": g._space._nodes[node].land_supply_node,
			"open": g._space._nodes[node].get("port_open", true), "busy": port.busy, "available_stock": stock, "observed_at": g._state.time}
	return {}

func on_depot_stock(depot: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	for vessel: Dictionary in sea.vessels.values():
		if vessel.status == "SUNK" or float(vessel.stock.equipment) <= 0.0 or local_observation(vessel).get("depot_ref", "") != depot:
			continue
		var person: String = sea.current_commander(vessel)
		if not person.is_empty():
			sea.request_status(person, str(vessel.id), "actual_port_stock_arrived")

func effort(vessel: Dictionary) -> float:
	return float(vessel.control_effort) if _sea.get_ref()._owner.get_ref()._state.time < float(vessel.control_until) else 0.0

func validate(vessel: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	if vessel.status == "SUNK" or float(vessel.stock.equipment) <= 0.0:
		return sea._reject("sunk_vessel_cannot_be_serviced")
	if values.operation == "damage_control":
		if values.size() != 3 or not values.get("active") is bool:
			return sea._reject("explicit_damage_control_selection_required")
		if not values.active:
			return {"ok": true}
		return {"ok": true} if vessel.status not in ["REPAIRING", "LOADING", "UNLOADING", "SERVICING"] and (float(vessel.flooding) > 0.0 or float(vessel.fire) > 0.0) and available_crew(vessel) > 0.1 and float(vessel.stock.spares) >= float(rules.control_spares) else sea._reject("actual_damage_crew_and_onboard_materials_required")
	var node: String = port_at(vessel)
	if values.size() != 2 or node.is_empty() or vessel.status not in ["DOCKED", "ANCHORED", "IMMOBILE", "SUPPLY_EXHAUSTED", "WAITING_PORT", "CARGO_WAITING"] or ports[node].busy != "" or jobs.size() >= 64 or jobs.has(id):
		return sea._reject("stationary_available_own_port_and_crew_required")
	if values.operation == "repair":
		if float(vessel.flooding) > 0.0 or float(vessel.fire) > 0.0 or repair_amount(vessel, node) <= 0.0:
			return sea._reject("stabilized_hull_finite_port_capacity_and_spares_required")
	return {"ok": true}

func repair_amount(vessel: Dictionary, node: String) -> float:
	var l: RefCounted = _sea.get_ref()._owner.get_ref()._state.logistics_port.get_ref()
	var deficit: float = maxf(1.0 - float(vessel.integrity), maxf(float(vessel.mobility_damage), float(vessel.weapon_damage)))
	return minf(deficit, minf(float(l._capacities[ports[node].capacity_ref].remaining), l.available_stock(str(ports[node].depot), "SPARES") / float(rules.repair_spares_per_integrity)))

func start(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	settle(vessel)
	if values.operation == "damage_control":
		vessel.control_active = values.active
		vessel.control_effort = 0.0
		vessel.control_until = g._state.time
		if values.active:
			_fund_control(vessel)
		_schedule_damage(vessel)
		sea._refresh_motion(vessel)
		sea._report_status(vessel, actor, id, "DAMAGE_CONTROL_STARTED" if values.active else "DAMAGE_CONTROL_STOPPED")
		return
	var node: String = port_at(vessel)
	ports[node].busy = id
	var job: Dictionary = {"id": id, "issuer": actor, "vessel_ref": vessel.id, "port_ref": node, "operation": values.operation, "status": "WORKING", "started_at": g._state.time}
	jobs[id] = job
	vessel.port_job_ref = id
	vessel.version += 1
	vessel.control_active = false
	vessel.control_effort = 0.0
	vessel.control_until = g._state.time
	var seconds: float = float(sea.rules.port_service_seconds)
	if values.operation == "repair":
		job.quantity = repair_amount(vessel, node)
		seconds = maxf(5.0, float(job.quantity) / float(rules.repair_per_second))
	vessel.status = "REPAIRING" if values.operation == "repair" else "SERVICING"
	sea._ticket(vessel, "PORT_WORK", g._state.time + seconds, {"job_ref": id})

func process_port(vessel: Dictionary, ticket: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var job: Dictionary = jobs[ticket.job_ref]
	if vessel.port_job_ref != job.id or port_at(vessel) != job.port_ref or vessel.status == "SUNK":
		interrupt_port(vessel, "PORT_WORK_INTERRUPTED")
		return
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	var port: Dictionary = ports[job.port_ref]
	if job.operation == "repair":
		var restored: float = minf(float(job.quantity), repair_amount(vessel, str(job.port_ref)))
		restored = l.consume_depot_spares(str(port.depot), restored * float(rules.repair_spares_per_integrity)) / float(rules.repair_spares_per_integrity)
		l._capacities[port.capacity_ref].remaining -= restored
		vessel.integrity = minf(1.0, float(vessel.integrity) + restored)
		vessel.mobility_damage = maxf(0.0, float(vessel.mobility_damage) - restored)
		vessel.weapon_damage = maxf(0.0, float(vessel.weapon_damage) - restored)
		job.restored = restored
		job.status = "COMPLETED" if restored + 0.0000001 >= float(job.quantity) else "REPAIR_SUPPLY_CHANGED"
	else:
		job.fuel = l.replenish_asset(str(vessel.id), str(port.depot), "FUEL", maxf(0.0, float(sea.rules.fuel_capacity) - float(vessel.stock.fuel)))
		job.ammunition = l.replenish_asset(str(vessel.id), str(port.depot), "AMMUNITION", maxf(0.0, float(sea.rules.ammo_capacity) - float(vessel.stock.ammunition)))
		job.spares = l.replenish_asset(str(vessel.id), str(port.depot), "SPARES", maxf(0.0, float(rules.spares_capacity) - float(vessel.stock.spares)))
		job.status = "COMPLETED" if float(job.fuel) + float(job.ammunition) + float(job.spares) > 0.0 else "SUPPLY_EXHAUSTED"
	vessel.port_job_ref = ""
	port.busy = ""
	job.finished_at = sea._owner.get_ref()._state.time
	vessel.status = "DOCKED" if sea.mobile(vessel) else "IMMOBILE"
	sea._report_status(vessel, str(job.issuer), str(job.id), str(job.status))

func interrupt_port(vessel: Dictionary, reason: String) -> void:
	var id: String = str(vessel.port_job_ref)
	if id.is_empty():
		return
	var job: Dictionary = jobs[id]
	job.status = reason
	ports[job.port_ref].busy = ""
	vessel.port_job_ref = ""
	vessel.version += 1
	if vessel.status != "SUNK":
		vessel.status = "DOCKED" if _sea.get_ref().mobile(vessel) else "IMMOBILE"
	_sea.get_ref()._report_status(vessel, str(job.issuer), id, reason)

func on_hit(vessel: Dictionary, dose: float, cause: String) -> void:
	vessel.flooding = minf(1.0, float(vessel.flooding) + dose * float(rules.flood_per_hit))
	vessel.fire = minf(1.0, float(vessel.fire) + dose * float(rules.fire_per_hit))
	vessel.mobility_damage = minf(1.0, float(vessel.mobility_damage) + dose * float(rules.system_per_hit))
	vessel.weapon_damage = minf(1.0, float(vessel.weapon_damage) + dose * float(rules.system_per_hit))
	vessel.damage_cause_ref = cause
	_schedule_damage(vessel)

func settle(vessel: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var now: float = sea._owner.get_ref()._state.time
	var since: float = float(vessel.damage_last_at)
	var elapsed: float = maxf(0.0, now - since)
	if elapsed <= 0.0 or vessel.status == "SUNK":
		return
	var controlled: float = clampf(float(vessel.control_until) - since, 0.0, elapsed)
	var used_effort: float = float(vessel.control_effort)
	var flood: float = maxf(0.0, float(vessel.flooding) - controlled * used_effort * float(rules.flood_control_per_second))
	var fire: float = maxf(0.0, float(vessel.fire) - controlled * used_effort * float(rules.fire_control_per_second))
	# Integral of a bounded linear reduction, followed by unmanaged time.
	var flood_time: float = minf(controlled, float(vessel.flooding) / maxf(0.0000001, used_effort * float(rules.flood_control_per_second)))
	var fire_time: float = minf(controlled, float(vessel.fire) / maxf(0.0000001, used_effort * float(rules.fire_control_per_second)))
	var flood_integral: float = (float(vessel.flooding) + flood) * 0.5 * flood_time * (1.0 - 0.8 * used_effort) + flood * (elapsed - controlled)
	var fire_integral: float = (float(vessel.fire) + fire) * 0.5 * fire_time * (1.0 - 0.8 * used_effort) + fire * (elapsed - controlled)
	vessel.flooding = flood
	vessel.fire = fire
	vessel.damage_last_at = now
	var loss: float = flood_integral * float(rules.flood_loss_per_second) + fire_integral * float(rules.fire_loss_per_second)
	if loss > 0.0:
		sea.sustained_damage(vessel, loss, str(vessel.damage_cause_ref))

func _fund_control(vessel: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var assigned: float = minf(float(rules.control_effort), available_crew(vessel))
	if not vessel.control_active or assigned <= 0.1 or float(vessel.stock.spares) < float(rules.control_spares) or float(vessel.flooding) + float(vessel.fire) <= 0.0:
		vessel.control_active = false
		vessel.control_effort = 0.0
		vessel.control_until = g._state.time
		return
	g._state.logistics_port.get_ref().consume_air(str(vessel.id), "spares", float(rules.control_spares))
	vessel.control_effort = assigned
	vessel.control_until = g._state.time + float(rules.damage_seconds)

func _schedule_damage(vessel: Dictionary) -> void:
	vessel.damage_version += 1
	if vessel.status != "SUNK" and float(vessel.flooding) + float(vessel.fire) > 0.0:
		var now: float = _sea.get_ref()._owner.get_ref()._state.time
		var due: float = now + float(rules.damage_seconds)
		if float(vessel.control_until) > now:
			due = minf(due, float(vessel.control_until))
		_sea.get_ref()._ticket(vessel, "DAMAGE", due, {"damage_version": vessel.damage_version})

func process_damage(vessel: Dictionary, ticket: Dictionary) -> void:
	if ticket.damage_version != vessel.damage_version or vessel.status == "SUNK":
		return
	settle(vessel)
	if vessel.status == "SUNK":
		return
	_fund_control(vessel)
	_schedule_damage(vessel)
	_sea.get_ref()._refresh_motion(vessel)
	if float(vessel.flooding) + float(vessel.fire) <= 0.0:
		_sea.get_ref()._report_to_issuer(vessel, "damage_stable", "DAMAGE_STABILIZED")

const RUNTIME_FIELDS: Array[String] = ["ports", "jobs", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
