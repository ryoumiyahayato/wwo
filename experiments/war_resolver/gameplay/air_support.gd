extends RefCounted
## Stationary base facts and finite ground handling; stocks stay in Task6 depots.
var _air: WeakRef
var bases: Dictionary = {}
var jobs: Dictionary = {}
const MAX_BASES: int = 2
const MAX_JOBS: int = 64
var rules: Dictionary = {"fuel_per_second": 0.2,
	"rounds_per_second": 0.2, "repair_per_second": 0.002, "spares_per_integrity": 2.0,
	"minimum_seconds": 5.0, "position_radius_km": 0.01}

func configure(air: RefCounted) -> void:
	_air = weakref(air)

func admit(node: String, owner: String, depot: String, slots: int = 1, repair: bool = true) -> bool:
	var g: RefCounted = _air.get_ref()._owner.get_ref()
	var logistics: RefCounted = g._state.logistics_port.get_ref()
	if g._state.time != 0.0 or bases.size() >= MAX_BASES or bases.has(node) or slots < 1 or slots > 2 or not g._space._nodes.has(node) or not logistics._depots.has(depot) or not g._state.structure_port.get_ref()._contains(str(logistics._depots[depot].allocation_scope), owner):
		return false
	# A depot is bound to one real point. It is not copied into base inventory.
	if logistics._depots[depot].get("node_ref", node) != node:
		return false
	logistics._depots[depot].node_ref = node
	bases[node] = {"node": node, "owner": owner, "depot": depot, "slots": slots, "repair": repair, "busy": [], "queue": []}
	return true

func usable(asset: Dictionary) -> bool:
	var g: RefCounted = _air.get_ref()._owner.get_ref()
	if not bases.has(asset.base):
		return false
	var base: Dictionary = bases[asset.base]
	return g._state.structure_port.get_ref().active(str(base.owner)) and g._space._nodes[base.node].get("airfield_open", true) and base.owner == asset.owner and _air.get_ref()._distance(_air.get_ref().position(str(asset.id)), g._space._nodes[base.node].xy) <= float(rules.position_radius_km)

func validate(asset: Dictionary, values: Dictionary, id: String) -> Dictionary:
	if values.size() != 5 or not values.get("refuel") is bool or not values.get("rearm") is bool or not values.get("repair") is bool or not (values.refuel or values.rearm or values.repair):
		return {"ok": false, "error": "explicit_service_selection_required"}
	if jobs.size() >= MAX_JOBS or jobs.has(id) or asset.status not in ["LANDED", "WAITING_SUPPLY", "READY", "GROUNDED"] or asset.get("service_ref", "") != "" or float(asset.stock.equipment) <= 0.0 or not usable(asset):
		return {"ok": false, "error": "actual_available_base_and_parked_aircraft_required"}
	if values.repair and not bases[asset.base].repair:
		return {"ok": false, "error": "base_has_no_repair_capability"}
	return {"ok": true}

func start(actor: String, asset: Dictionary, values: Dictionary, id: String) -> void:
	var job: Dictionary = {"id": id, "asset_ref": asset.id, "issuer": actor, "base": asset.base,
		"refuel": values.refuel, "rearm": values.rearm, "repair": values.repair, "status": "WAITING_GROUND_CREW"}
	jobs[id] = job
	asset.service_ref = id
	asset.status = "WAITING_SUPPLY"
	bases[asset.base].queue.append(id)
	_dispatch(str(asset.base))

func _dispatch(node: String) -> void:
	var air: RefCounted = _air.get_ref()
	var base: Dictionary = bases[node]
	while base.busy.size() < int(base.slots) and not base.queue.is_empty():
		var id: String = str(base.queue.pop_front())
		var asset: Dictionary = air.assets[jobs[id].asset_ref]
		if asset.service_ref != id:
			continue
		if not usable(asset) or float(asset.stock.equipment) <= 0.0:
			_finish(asset, jobs[id], "BASE_OR_AIRCRAFT_UNAVAILABLE", false)
			continue
		base.busy.append(id)
		_next(asset, jobs[id])

func _next(asset: Dictionary, job: Dictionary) -> void:
	var air: RefCounted = _air.get_ref()
	var g: RefCounted = air._owner.get_ref()
	var logistics: RefCounted = g._state.logistics_port.get_ref()
	var depot: String = str(bases[job.base].depot)
	var quantity: float = 0.0
	var seconds: float = 0.0
	if job.refuel and float(asset.stock.fuel) < float(asset.fuel_capacity):
		job.phase = "REFUELING"
		quantity = minf(float(asset.fuel_capacity) - float(asset.stock.fuel), logistics.available_stock(depot, "FUEL"))
		seconds = quantity / float(rules.fuel_per_second)
	elif job.rearm and float(asset.stock.ammunition) < float(asset.load_capacity):
		job.phase = "LOADING"
		quantity = minf(float(asset.load_capacity) - float(asset.stock.ammunition), logistics.available_stock(depot, "AMMUNITION"))
		seconds = quantity / float(rules.rounds_per_second)
	elif job.repair and float(asset.integrity) < 1.0:
		job.phase = "REPAIRING"
		quantity = minf(1.0 - float(asset.integrity), logistics.available_stock(depot, "SPARES") / float(rules.spares_per_integrity))
		seconds = quantity / float(rules.repair_per_second)
	else:
		_finish(asset, job, "COMPLETED", true)
		return
	if quantity <= 0.0:
		_wait_supply(asset, job)
		return
	job.quantity = quantity
	job.status = job.phase
	asset.status = job.phase
	air._ticket(asset, "SERVICE", g._state.time + maxf(float(rules.minimum_seconds), seconds), {"job_ref": job.id})

func process(asset: Dictionary, ticket: Dictionary) -> void:
	var g: RefCounted = _air.get_ref()._owner.get_ref()
	var job: Dictionary = jobs[ticket.job_ref]
	if asset.service_ref != job.id or not usable(asset) or float(asset.stock.equipment) <= 0.0:
		_finish(asset, job, "SERVICE_INTERRUPTED", false)
		return
	var logistics: RefCounted = g._state.logistics_port.get_ref()
	var depot: String = str(bases[job.base].depot)
	var moved: float = 0.0
	match str(job.phase):
		"REFUELING":
			moved = logistics.replenish_asset(str(asset.id), depot, "FUEL", float(job.quantity))
			job.refuel = float(asset.stock.fuel) < float(asset.fuel_capacity) - 0.000001
		"LOADING":
			moved = logistics.replenish_asset(str(asset.id), depot, "AMMUNITION", float(job.quantity))
			job.rearm = float(asset.stock.ammunition) < float(asset.load_capacity) - 0.000001
		"REPAIRING":
			moved = logistics.consume_depot_spares(depot, float(job.quantity) * float(rules.spares_per_integrity)) / float(rules.spares_per_integrity)
			asset.integrity = minf(1.0, float(asset.integrity) + moved)
			job.repair = float(asset.integrity) < 1.0 - 0.000001
	if moved + 0.0000001 < float(job.quantity):
		if job.phase == "REFUELING":
			job.refuel = true
		elif job.phase == "LOADING":
			job.rearm = true
		else:
			job.repair = true
		_next(asset, job)
	else:
		_next(asset, job)

func _wait_supply(asset: Dictionary, job: Dictionary) -> void:
	job.wait_episode = int(job.get("wait_episode", 0)) + 1
	job.status = "WAITING_ACTUAL_BASE_STOCK"
	asset.status = "WAITING_SUPPLY"
	bases[job.base].busy.erase(job.id)
	_air.get_ref()._status_report(asset, str(job.issuer), "waiting_" + str(job.id) + "_%d" % int(job.wait_episode), "air_service", str(job.status))
	_dispatch(str(job.base))

func on_depot_stock(depot: String) -> void:
	# Only an actual stock-arrival event resumes already requested base work.
	for node: String in bases:
		if bases[node].depot != depot:
			continue
		for id: String in jobs:
			var job: Dictionary = jobs[id]
			if job.base == node and job.status == "WAITING_ACTUAL_BASE_STOCK":
				job.status = "WAITING_GROUND_CREW"
				bases[node].queue.append(id)
		_dispatch(node)

func interrupt(asset: Dictionary, reason: String) -> void:
	if not str(asset.service_ref).is_empty():
		_finish(asset, jobs[asset.service_ref], reason, false)

func _finish(asset: Dictionary, job: Dictionary, status: String, completed: bool) -> void:
	var air: RefCounted = _air.get_ref()
	job.status = status
	job.finished_at = air._owner.get_ref()._state.time
	asset.service_ref = ""
	asset.serviceable = float(asset.integrity) >= float(air.rules.return_integrity) and float(asset.stock.equipment) > 0.0
	asset.status = "READY" if completed and asset.serviceable and float(asset.stock.fuel) > 0.0 else "WAITING_SUPPLY"
	if float(asset.stock.equipment) <= 0.0:
		asset.status = "DESTROYED"
	bases[job.base].busy.erase(job.id)
	bases[job.base].queue.erase(job.id)
	air._status_report(asset, str(job.issuer), "base_" + str(job.id), "air_service", status)
	_dispatch(str(job.base))

const RUNTIME_FIELDS: Array[String] = ["bases", "jobs", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
