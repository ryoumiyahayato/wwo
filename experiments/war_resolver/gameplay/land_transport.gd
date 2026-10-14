extends RefCounted
## Bounded cargo duties on existing ground units and Task6 delivery records.
var _owner: WeakRef
var carriers: Dictionary = {}
var jobs: Dictionary = {}
var _unit_jobs: Dictionary = {}
var _tickets: Dictionary = {}
var _serial: int = 0
var _report_serial: int = 0
var rules: Dictionary = {"crew": 2.0, "handling_seconds": 30.0, "cargo_per_second": 1.0,
	"loaded_speed_factor": 0.65, "aircraft_load": 30.0, "aircraft_handling_seconds": 90.0,
	"local_radius_km": 0.03, "drag_speed_km_s": 0.0005, "aircraft_spares": 0.25}

func configure(gameplay: RefCounted) -> void:
	_owner = weakref(gameplay)

func admit(unit_ref: String, capacity: float, heavy_aircraft: bool = false) -> bool:
	var g: RefCounted = _owner.get_ref()
	if g._state.time != 0.0 or carriers.size() >= 2 or carriers.has(unit_ref) or not g._state.units.has(unit_ref) or capacity <= 0.0:
		return false
	var unit: Dictionary = g._state.units[unit_ref]
	if not unit.has("spatial") or unit.spatial.mode != "MOTORIZED" or float(unit.serviceable_equipment) < 1.0:
		return false
	carriers[unit_ref] = {"capacity": capacity, "initial_equipment": unit.serviceable_equipment,
		"transport_equipment": 2.0, "heavy_aircraft": heavy_aircraft, "report_source": "land_dispatch_" + unit_ref}
	var s: RefCounted = g._state.structure_port.get_ref()
	return g._state.information_port.get_ref().register_platform_source(str(carriers[unit_ref].report_source), str(s._path(str(s._unit_nodes[unit_ref])).back()), self)

func capacity(unit: Dictionary) -> float:
	if not carriers.has(unit.id) or minf(float(unit.effective), float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))) < float(rules.crew):
		return 0.0
	var fraction: float = minf(1.0, float(unit.serviceable_equipment) / float(carriers[unit.id].initial_equipment))
	return float(carriers[unit.id].capacity) * fraction if float(carriers[unit.id].transport_equipment) * fraction >= 0.5 else 0.0

func _position(unit: Dictionary) -> Dictionary:
	return {"node_ref": unit.spatial.node, "edge_ref": unit.spatial.edge, "progress": unit.spatial.progress,
		"xy": _owner.get_ref()._space.xy(unit).duplicate()}

func _at(unit: Dictionary, node: String) -> bool:
	return str(unit.spatial.edge) == "" and unit.spatial.node == node

func _quantity(cargo: Dictionary) -> float:
	var total: float = 0.0
	for resource: String in cargo:
		total += float(cargo[resource])
	return total

func route(actor: String, unit: Dictionary, node: String, path: Array, returning: bool = false) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if not g._known.get(actor, {}).get(node, []).has(path):
		return g._reject("land_route_not_in_person_known_map")
	if path.is_empty():
		return {"ok": true} if _at(unit, node) or returning and unit.spatial.edge != "" and unit.spatial.from == node else g._reject("actual_route_or_leg_return_required")
	var route_unit: Dictionary = unit
	if str(unit.spatial.edge) != "" and not returning:
		if path[0] != unit.spatial.edge:
			return g._reject("continue_the_actual_road_leg_before_new_connections")
		route_unit = unit.duplicate(true)
		route_unit.spatial.node = unit.spatial.from
		route_unit.spatial.edge = ""
	var valid: Dictionary = g._space.validate_path(route_unit, path, returning)
	if not valid.ok:
		return valid
	var current: String = str(unit.spatial.from) if unit.spatial.edge != "" else str(unit.spatial.node)
	for edge_id: String in path:
		var edge: Dictionary = g._space._edges[edge_id]
		current = str(edge.to) if current == edge.from else str(edge.from)
	return {"ok": true} if current == node else g._reject("land_route_must_reach_handover_node")

func _free(actor: String, unit_ref: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	var l: RefCounted = g._state.logistics_port.get_ref()
	if not carriers.has(unit_ref) or not g._state.units.has(unit_ref) or _unit_jobs.has(unit_ref) or g.air.recovery._unit_jobs.has(unit_ref) or g.operations.occupied_ground(unit_ref) or g.tactics.occupied(unit_ref) or not l._allowed(actor, "unit", unit_ref, 3):
		return false
	var unit: Dictionary = g._state.units[unit_ref]
	return capacity(unit) > 0.0 and float(unit.fuel) > 0.0 and str(unit.spatial.edge) == "" and unit.spatial.path.is_empty() and g._state.coordination.get(unit_ref, {}).is_empty()

func validate(actor: String, target: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var l: RefCounted = g._state.logistics_port.get_ref()
	if target != g._state.structure_port.get_ref().command_person(actor).formation_id:
		return g._reject("land_duty_requires_current_owning_command_position")
	if values.get("operation", "") != "transport":
		return _validate_change(actor, values, id)
	for key: String in values:
		if key not in ["operation", "unit_ref", "source_ref", "recipient_kind", "recipient_ref", "target_node", "approach_path", "path", "cargo", "request_ref", "notify"]:
			return g._reject("unknown_land_transport_parameter")
	if jobs.size() >= 64 or jobs.has(id) or l._deliveries.size() >= 128 or l._deliveries.has(id) or not values.get("unit_ref") is String or not _free(actor, str(values.unit_ref)) or not values.get("source_ref") is String or not l._depots.has(values.source_ref) or not values.get("cargo") is Dictionary or values.cargo.is_empty() or not values.get("approach_path") is Array or not values.get("path") is Array or not values.get("target_node") is String:
		return g._reject("finite_free_ground_carrier_source_manifest_and_routes_required")
	if values.get("recipient_kind", "") not in ["unit", "depot"] or not values.get("recipient_ref") is String or not l._allowed(actor, "depot", str(values.source_ref), 3) or not l._allowed(actor, str(values.recipient_kind), str(values.recipient_ref), 3):
		return g._reject("actual_supply_and_receiver_authority_required")
	var unit: Dictionary = g._state.units[values.unit_ref]
	for resource: String in values.cargo:
		if not l.CLASSES.has(resource) or not l._positive(values.cargo[resource]) or float(values.cargo[resource]) > l.available_stock(str(values.source_ref), resource):
			return g._reject("actual_available_Task6_cargo_required")
		if resource == "FUEL" and values.recipient_kind == "unit" and not g._lod.preview_leaf(str(values.recipient_ref)).get("supply_capability", {}).get("fuel_dependent", false):
			return g._reject("fuel_receiver_capability_required")
	if _quantity(values.cargo) > capacity(unit):
		return g._reject("manifest_exceeds_actual_ground_capacity")
	if values.recipient_kind == "depot" and l._depots[values.recipient_ref].node_ref != values.target_node:
		return g._reject("depot_requires_its_actual_handover_node")
	var source_node: String = str(l._depots[values.source_ref].node_ref)
	var valid: Dictionary = route(actor, unit, source_node, values.approach_path)
	if not valid.ok:
		return valid
	var projected: Dictionary = unit.duplicate(true)
	projected.spatial.node = source_node
	projected.spatial.edge = ""
	valid = route(actor, projected, str(values.target_node), values.path)
	if not valid.ok:
		return valid
	var request_ref: String = str(values.get("request_ref", ""))
	if request_ref != "":
		if not l._requests.has(request_ref):
			return g._reject("existing_supply_request_required")
		var request: Dictionary = l._requests[request_ref]
		if request.status != "REQUESTED" or request.target_kind != values.recipient_kind or request.target != values.recipient_ref or not values.cargo.has(request.resource_class) or float(values.cargo[request.resource_class]) > float(request.quantity) - float(request.get("received_quantity", 0.0)):
			return g._reject("compatible_waiting_request_and_remaining_quantity_required")
		if request.get("sea_required", false):
			var sea_ref: String = str(request.get("sea_delivery_ref", ""))
			if not l._deliveries.has(sea_ref) or l._deliveries[sea_ref].status not in ["RECEIVED", "ONBOARD"] or l.physical_balance(request_ref).get("port_depot_ref", "") != values.source_ref:
				return g._reject("sea_cargo_requires_actual_destination_port_stock")
			for resource: String in values.cargo:
				if float(values.cargo[resource]) > l.sea_port_remaining(sea_ref, resource, request_ref, str(values.source_ref)) + 0.000001:
					return g._reject("land_manifest_must_use_unforwarded_port_batch")
	return _notify_allowed(actor, values.get("notify", []))

func _notify_allowed(actor: String, recipients: Variant) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	if not recipients is Array or recipients.size() > 3:
		return g._reject("bounded_transport_report_recipients_required")
	for person: Variant in recipients:
		if not person is String or not s._people.has(person) or s._nodes[s._people[person].formation_id].side != s._nodes[s.command_person(actor).formation_id].side:
			return g._reject("existing_same_side_report_recipient_required")
	return {"ok": true}

func _validate_change(actor: String, values: Dictionary, command_id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if not values.get("transport_ref") is String or not jobs.has(values.transport_ref):
		return g._reject("existing_land_transport_required")
	var job: Dictionary = jobs[values.transport_ref]
	var l: RefCounted = g._state.logistics_port.get_ref()
	if not l._allowed(actor, "unit", str(job.unit_ref), 3) or job.status in ["RECEIVED", "CANCELLED_BEFORE_LOADING"]:
		return g._reject("current_unfinished_carrier_command_required")
	if values.get("operation", "") == "stop_transport":
		return {"ok": true} if values.size() == 2 else g._reject("explicit_transport_stop_required")
	var subject: String = str(job.asset_ref) if job.payload_kind == "AIRCRAFT" else str(l._deliveries[job.id].recipient_ref)
	var subject_kind: String = "aircraft" if job.payload_kind == "AIRCRAFT" else str(l._deliveries[job.id].recipient_kind)
	var learned: bool = false
	for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor, subject_kind, subject, "land_supply_status").get("entries", []):
		if claim.claimed_value.get("transport_ref", "") == job.id and claim.claimed_value.get("status", "") == job.status and float(claim.reliability) > 0.0:
			learned = true
	if not learned:
		return g._reject("delivered_current_transport_obstruction_or_handover_report_required")
	if values.get("operation", "") == "continue_transport":
		return {"ok": true} if values.size() == 2 and job.payload_kind == "CARGO" and job.status not in ["LOST", "CARGO_LOST"] else g._reject("existing_unfinished_cargo_responsibility_required")
	if values.get("operation", "") == "recover_cargo":
		if values.size() != 3 or job.payload_kind != "CARGO" or job.status != "STRANDED" or not values.get("unit_ref") is String or not _free(actor, str(values.unit_ref)) or not g.operations.permits_carrier_recovery(str(values.unit_ref), command_id):
			return g._reject("stranded_cargo_and_free_actual_recovery_carrier_required")
		var unit: Dictionary = g._state.units[values.unit_ref]
		return {"ok": true} if _at(unit, str(job.stranded_position.node_ref)) and job.stranded_position.edge_ref == "" and g.air._distance(g._space.xy(unit), job.stranded_position.xy) <= 0.000001 and capacity(unit) >= _quantity(l._deliveries[job.id].cargo) else g._reject("actual_stranded_cargo_rendezvous_and_capacity_required")
	if values.get("operation", "") not in ["resume_transport", "redirect_transport", "unload"]:
		return g._reject("unknown_land_transport_operation")
	if values.operation == "unload":
		return {"ok": true} if values.size() == 2 and job.status in ["WAITING_RECIPIENT", "STOPPED", "BLOCKED"] and _at(g._state.units[job.unit_ref], str(job.target_node)) else g._reject("actual_handover_location_required")
	if job.status not in ["BLOCKED", "STOPPED", "WAITING_RECIPIENT", "CAPACITY_LOST", "FUEL_EXHAUSTED", "TEMPORARILY_IMMOBILE"] or not values.get("path") is Array or not values.get("target_node") is String or not values.get("return_to_start", false) is bool:
		return g._reject("stopped_actual_transport_and_explicit_known_route_required")
	var unit: Dictionary = g._state.units[job.unit_ref]
	if capacity(unit) < _load(job) or float(unit.fuel) <= 0.0:
		return g._reject("actual_carrier_capacity_and_fuel_required")
	var leg_target: String = str(job.target_node) if job.loaded else str(job.source_node)
	if job.payload_kind == "AIRCRAFT" and values.target_node != leg_target:
		return g._reject("aircraft_return_keeps_declared_receiving_base")
	if job.payload_kind == "CARGO" and values.operation == "redirect_transport":
		var kind: String = str(values.get("recipient_kind", ""))
		var recipient: String = str(values.get("recipient_ref", ""))
		if kind not in ["unit", "depot"] or not l._allowed(actor, kind, recipient, 3) or kind == "depot" and l._depots[recipient].node_ref != values.target_node:
			return g._reject("explicit_authorized_redirect_receiver_required")
		var reference: String = str(values.get("request_ref", ""))
		if reference != "" and reference != str(l._deliveries[job.id].request_id):
			var request: Dictionary = l._requests.get(reference, {})
			var cargo: Dictionary = l._deliveries[job.id].cargo
			if not job.loaded or request.get("status", "") != "REQUESTED" or request.get("target_kind", "") != kind or request.get("target", "") != recipient or cargo.size() != 1 or not cargo.has(request.get("resource_class", "")) or float(cargo.get(request.get("resource_class", ""), 0.0)) > float(l.physical_balance(reference).get("uncommitted_quantity", 0.0)):
				return g._reject("compatible_uncommitted_request_for_same_actual_loaded_cargo_required")
	elif values.target_node != leg_target:
		return g._reject("resume_preserves_handover_location")
	return route(actor, unit, str(values.target_node), values.path, bool(values.get("return_to_start", false)))

func apply(actor: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if values.operation == "continue_transport":
		var continued: Dictionary = jobs[values.transport_ref]
		continued.previous_issuer = continued.issuer
		continued.issuer = actor
		continued.responsibility_revision = int(continued.get("responsibility_revision", 0)) + 1
		_report(continued, "RESPONSIBILITY_CONTINUED")
		return {"ok": true, "changed": [], "retired": [], "state_delta": {"land_transport": {"transport_ref": continued.id}}}
	if values.operation == "transport":
		g._state.logistics_port.get_ref().reserve_land(actor, id, str(values.source_ref), str(values.recipient_kind), str(values.recipient_ref), values.cargo, str(values.unit_ref), str(values.target_node), str(values.get("request_ref", "")))
		var source_node: String = str(g._state.logistics_port.get_ref()._depots[values.source_ref].node_ref)
		_start(actor, id, str(values.unit_ref), source_node, str(values.target_node), values.approach_path, values.path, "CARGO", "", values.get("notify", []))
	else:
		var job: Dictionary = jobs[values.transport_ref]
		job.issuer = actor
		job.version += 1
		job.pending = ""
		if values.operation == "stop_transport":
			if job.payload_kind == "AIRCRAFT" and not job.loaded:
				_end(job, "CANCELLED_BEFORE_LOADING")
			elif job.payload_kind == "CARGO" and g._state.logistics_port.get_ref()._deliveries[job.id].status == "RESERVED_AT_SOURCE":
				g._state.logistics_port.get_ref().cancel_land_reservation(str(job.id))
				_end(job, "CANCELLED_BEFORE_LOADING")
			else:
				_pause(job, "STOPPED")
		elif values.operation == "recover_cargo":
			_unit_jobs.erase(job.unit_ref)
			job.unit_ref = values.unit_ref
			_unit_jobs[job.unit_ref] = job.id
			g._state.logistics_port.get_ref()._deliveries[job.id].carrier_ref = job.unit_ref
			g._state.logistics_port.get_ref()._deliveries[job.id].status = "ONBOARD"
			job.loaded = true
			job.status = "STOPPED"
			_report(job, "CARGO_RECOVERED_AT_ACTUAL_POSITION")
		elif values.operation == "unload":
			_begin_unload(job)
		else:
			if values.operation == "redirect_transport" and job.payload_kind == "CARGO":
				var delivery: Dictionary = g._state.logistics_port.get_ref()._deliveries[job.id]
				var reference: String = str(values.get("request_ref", delivery.request_id if delivery.recipient_ref == values.recipient_ref else ""))
				if delivery.request_id != "" and delivery.request_id != reference:
					g._state.logistics_port.get_ref()._requests[delivery.request_id].status = "REQUESTED"
					if g._state.logistics_port.get_ref()._requests[delivery.request_id].get("land_delivery_ref", "") == delivery.delivery_id:
						g._state.logistics_port.get_ref()._requests[delivery.request_id].erase("land_delivery_ref")
					if not delivery.has("original_request_ref"):
						delivery.original_request_ref = delivery.request_id
					delivery.previous_request_ref = delivery.request_id
					delivery.request_id = ""
				if reference != "":
					delivery.request_id = reference
					g._state.logistics_port.get_ref()._requests[reference].land_delivery_ref = delivery.delivery_id
					g._state.logistics_port.get_ref()._requests[reference].status = "ALLOCATED_LAND"
				delivery.recipient_kind = values.recipient_kind
				delivery.recipient_ref = values.recipient_ref
				delivery.required_node = values.target_node
			if job.loaded:
				job.target_node = values.target_node
			_move(job, str(values.target_node), values.path, "IN_TRANSIT" if job.loaded else "APPROACHING_SOURCE", bool(values.get("return_to_start", false)))
	return {"ok": true, "changed": [str(values.get("unit_ref", jobs.get(values.get("transport_ref", ""), {}).get("unit_ref", "")))], "retired": [], "state_delta": {"land_transport": {"transport_ref": id if values.operation == "transport" else values.transport_ref}}}

func start_aircraft(actor: String, id: String, unit_ref: String, asset_ref: String, pickup: String, base: String, approach: Array, path: Array) -> void:
	_start(actor, id, unit_ref, pickup, base, approach, path, "AIRCRAFT", asset_ref, [])

func _start(actor: String, id: String, unit_ref: String, source: String, target: String, approach: Array, path: Array, kind: String, asset_ref: String, notify: Array) -> void:
	var g: RefCounted = _owner.get_ref()
	jobs[id] = {"id": id, "issuer": actor, "unit_ref": unit_ref, "source_node": source, "target_node": target,
		"path": path.duplicate(), "payload_kind": kind, "asset_ref": asset_ref, "loaded": false,
		"status": "APPROACHING_SOURCE", "notify": notify.duplicate(), "version": 0, "pending": "",
		"started_at": g._state.time, "fuel_spent": 0.0, "distance_km": 0.0, "loss_notice": false}
	_unit_jobs[unit_ref] = id
	_move(jobs[id], source, approach, "APPROACHING_SOURCE")

func _move(job: Dictionary, node: String, path: Array, status: String, returning: bool = false) -> void:
	var g: RefCounted = _owner.get_ref()
	job.status = status
	job.motion_blocked = false
	job.version += 1
	var result: Dictionary = g._assign(str(job.unit_ref), str(job.id) + "_leg_%d" % int(job.version), str(job.issuer), {"intent": "advance", "target_node": node, "path": path.duplicate(), "return_to_start": returning})
	if not result.ok:
		_pause(job, "BLOCKED")
		return
	job.mission_ref = result.mission_id
	_report(job, status)
	_queue(job, "CHECK", g._state.time + 0.000001)

func _load(job: Dictionary) -> float:
	if job.payload_kind == "AIRCRAFT":
		return float(rules.aircraft_load)
	return _quantity(_owner.get_ref()._state.logistics_port.get_ref()._deliveries[job.id].cargo)

func posture(unit_ref: String) -> String:
	if not _unit_jobs.has(unit_ref):
		return ""
	var job: Dictionary = jobs[_unit_jobs[unit_ref]]
	return "advance" if job.status in ["APPROACHING_SOURCE", "IN_TRANSIT"] else "reserve"

func prepare(unit: Dictionary, plan: Dictionary) -> void:
	if _unit_jobs.has(unit.id):
		plan.commitment = 0.0

func constrain(unit: Dictionary, plan: Dictionary) -> void:
	if not _unit_jobs.has(unit.id):
		return
	var job: Dictionary = jobs[_unit_jobs[unit.id]]
	if job.status not in ["APPROACHING_SOURCE", "IN_TRANSIT"] or capacity(unit) < _load(job):
		plan.speed = 0.0
	elif job.loaded:
		plan.speed *= float(rules.loaded_speed_factor)

func after_unit(unit: Dictionary, travelled: float, spent_before: float, plan: Dictionary) -> void:
	if not _unit_jobs.has(unit.id):
		return
	var job: Dictionary = jobs[_unit_jobs[unit.id]]
	job.distance_km += travelled
	job.fuel_spent += maxf(0.0, float(unit.fuel_spent) - spent_before)
	if job.status in ["APPROACHING_SOURCE", "IN_TRANSIT"] and (unit.spatial.edge != "" or not unit.spatial.path.is_empty()):
		if plan.get("advance_inhibited", false) or plan.posture == "withdraw" or float(unit.mobility) <= 0.0 or float(unit.readiness) <= 0.0 or not _owner.get_ref()._space.can_move(unit):
			job.motion_blocked = true
			_queue(job, "CHECK", _owner.get_ref()._state.time + 0.000001)
	on_unit(str(unit.id))

func on_capacity_loss(unit: Dictionary, equipment_loss: float) -> void:
	if not _unit_jobs.has(unit.id):
		return
	var job: Dictionary = jobs[_unit_jobs[unit.id]]
	if job.loaded and equipment_loss > 0.0:
		if job.payload_kind == "CARGO":
			_owner.get_ref()._state.logistics_port.get_ref().lose_land_cargo(str(job.id), minf(0.5, equipment_loss / maxf(1.0, float(unit.equipment) + equipment_loss)), _position(unit))
		else:
			var asset: Dictionary = _owner.get_ref().air.assets[job.asset_ref]
			_owner.get_ref().air.damage(str(asset.id), 0.1 * equipment_loss / maxf(1.0, float(unit.equipment) + equipment_loss), "ground_transport_loss_" + str(job.id))
		job.loss_notice = true
	on_unit(str(unit.id))

func on_unit(unit_ref: String) -> void:
	if not _unit_jobs.has(unit_ref):
		return
	var g: RefCounted = _owner.get_ref()
	var job: Dictionary = jobs[_unit_jobs[unit_ref]]
	var unit: Dictionary = g._state.units[unit_ref]
	if job.status not in ["APPROACHING_SOURCE", "IN_TRANSIT", "LOADING", "UNLOADING"] and not job.loss_notice:
		return
	var destination: String = str(job.source_node) if not job.loaded else str(job.target_node)
	var handling_interrupted: bool = job.status in ["LOADING", "UNLOADING"] and capacity(unit) < _load(job)
	if handling_interrupted and job.pending != "":
		job.version += 1
		job.pending = ""
	if job.loss_notice or capacity(unit) < _load(job) or job.status in ["APPROACHING_SOURCE", "IN_TRANSIT"] and (float(unit.fuel) <= 0.0 or str(unit.spatial.blocked_edge) != "" or _at(unit, destination)):
		_queue(job, "CHECK", g._state.time + 0.000001)

func _queue(job: Dictionary, kind: String, due: float) -> void:
	if job.pending != "":
		return
	var g: RefCounted = _owner.get_ref()
	_serial += 1
	var id: String = "land_" + str(job.id) + "_%d" % _serial
	_tickets[id] = {"job_ref": job.id, "version": job.version, "kind": kind, "due": due, "status": "PENDING"}
	job.pending = id
	g._state.schedule_event(id, due, "gameplay", {"land_id": id})

func accepts_event(id: String, payload: Dictionary, due: float) -> bool:
	return payload.get("land_id", "") == id and _tickets.has(id) and _tickets[id].status == "PENDING" and _tickets[id].due == due and jobs[_tickets[id].job_ref].version == _tickets[id].version

func process_event(event: Dictionary) -> Dictionary:
	var ticket: Dictionary = _tickets[event.id]
	ticket.status = "PROCESSED"
	var job: Dictionary = jobs[ticket.job_ref]
	job.pending = ""
	var g: RefCounted = _owner.get_ref()
	var unit: Dictionary = g._state.units[job.unit_ref]
	var changed: Array = [job.unit_ref]
	var retired: Array = []
	if job.status in ["RECEIVED", "CANCELLED_BEFORE_LOADING"]:
		return {"changed": [], "retired": [], "record": {"kind": "land_transport", "status": job.status}}
	if job.loss_notice:
		job.loss_notice = false
		_report(job, "PARTIAL_CARGO_LOSS" if job.payload_kind == "CARGO" else "AIRCRAFT_DAMAGED_IN_TRANSIT", true)
	if job.status == "STRANDED":
		return {"changed": changed, "retired": [], "record": {"kind": "land_transport", "status": "STRANDED"}}
	if job.payload_kind == "AIRCRAFT" and g.air.assets[job.asset_ref].status == "DESTROYED":
		_end(job, "AIRCRAFT_DESTROYED")
	elif capacity(unit) < _load(job):
		if capacity(unit) <= 0.0 and job.loaded:
			job.stranded_position = _position(unit)
			if job.payload_kind == "CARGO":
				var delivery: Dictionary = g._state.logistics_port.get_ref()._deliveries[job.id]
				delivery.status = "STRANDED"
				delivery.actual_position = job.stranded_position.duplicate(true)
			else:
				_drop_aircraft(job)
			_pause(job, "STRANDED")
		else:
			_pause(job, "CAPACITY_LOST")
	elif ticket.kind == "LOAD":
		if not _at(unit, str(job.source_node)):
			_pause(job, "LOADING_INTERRUPTED")
		elif job.payload_kind == "CARGO" and not g._state.logistics_port.get_ref().load_land(str(job.id)):
			_pause(job, "LOADING_INTERRUPTED")
		else:
			if job.payload_kind == "AIRCRAFT":
				var asset: Dictionary = g.air.assets[job.asset_ref]
				if asset.status != "GROUND_LOADING" or asset.recovery_ref != job.id:
					_end(job, "AIRCRAFT_LOADING_INTERRUPTED")
					return {"changed": changed, "retired": [], "record": {"status": job.status}}
				asset.xy = g._space.xy(unit)
				asset.status = "CARRIED_LAND"
			job.loaded = true
			_move(job, str(job.target_node), job.path, "IN_TRANSIT")
	elif ticket.kind == "UNLOAD":
		if not _at(unit, str(job.target_node)):
			_pause(job, "UNLOADING_INTERRUPTED")
		elif job.payload_kind == "CARGO":
			var receipt: Dictionary = g._state.logistics_port.get_ref().receive_land(str(job.id))
			if receipt.ok:
				changed.append_array(receipt.get("changed", []))
				retired.append_array(receipt.get("retired", []))
				_end(job, "RECEIVED")
			else:
				_pause(job, "WAITING_RECIPIENT")
		else:
			var asset: Dictionary = g.air.assets[job.asset_ref]
			if not g.air.support.bases.has(job.target_node) or g.air.support.bases[job.target_node].owner != asset.owner or not g._space._nodes[job.target_node].get("airfield_open", false):
				_pause(job, "WAITING_RECIPIENT")
			else:
				asset.xy = g._space.xy(unit)
				asset.node = job.target_node
				asset.base = job.target_node
				asset.status = "GROUNDED"
				asset.serviceable = false
				asset.recovery_ref = ""
				asset.landing.recovered_at = g._state.time
				_end(job, "RECEIVED")
	elif job.status in ["APPROACHING_SOURCE", "IN_TRANSIT"]:
		var destination: String = str(job.source_node) if not job.loaded else str(job.target_node)
		if _at(unit, destination):
			if job.loaded:
				_begin_unload(job)
			else:
				_begin_load(job)
		elif float(unit.fuel) <= 0.0:
			_pause(job, "FUEL_EXHAUSTED")
		elif str(unit.spatial.blocked_edge) != "" or g._state.missions[unit.mission_id].status != "active":
			_pause(job, "BLOCKED")
		elif job.get("motion_blocked", false):
			job.motion_blocked = false
			_pause(job, "TEMPORARILY_IMMOBILE")
	return {"changed": changed, "retired": retired, "record": {"kind": "land_transport", "transport_ref": job.id, "status": job.status}}

func _begin_load(job: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	var seconds: float = float(rules.handling_seconds) + _load(job) / float(rules.cargo_per_second)
	if job.payload_kind == "AIRCRAFT":
		var asset: Dictionary = g.air.assets[job.asset_ref]
		if asset.status != "AWAITING_RECOVERY" or asset.landing.surface != "LAND" or g.air._distance(asset.xy, g._space._nodes[job.source_node].xy) > float(rules.local_radius_km) or g._space.movement_factor(g._space._nodes[job.source_node].ground, "MOTORIZED") <= 0.0:
			_end(job, "AIRCRAFT_NOT_ACCESSIBLE_AT_DECLARED_ROAD_NODE")
			return
		var unit: Dictionary = g._state.units[job.unit_ref]
		if float(unit.spares) < float(rules.aircraft_spares):
			_pause(job, "LOADING_INTERRUPTED")
			return
		unit.spares -= float(rules.aircraft_spares)
		unit.spares_spent += float(rules.aircraft_spares)
		g._state.logistics_ledger.spares_spent += float(rules.aircraft_spares)
		seconds = float(rules.aircraft_handling_seconds) + g.air._distance(asset.xy, g._space._nodes[job.source_node].xy) / float(rules.drag_speed_km_s)
		job.local_from = asset.xy.duplicate()
		job.local_to = g._space._nodes[job.source_node].xy.duplicate()
		job.local_started_at = g._state.time + float(rules.aircraft_handling_seconds)
		job.local_due = g._state.time + seconds
		asset.status = "GROUND_LOADING"
	job.status = "LOADING"
	_report(job, "LOADING")
	_queue(job, "LOAD", g._state.time + seconds)

func _begin_unload(job: Dictionary) -> void:
	job.status = "UNLOADING"
	var seconds: float = float(rules.aircraft_handling_seconds) if job.payload_kind == "AIRCRAFT" else float(rules.handling_seconds) + _load(job) / float(rules.cargo_per_second)
	_report(job, "UNLOADING")
	_queue(job, "UNLOAD", _owner.get_ref()._state.time + seconds)

func _pause(job: Dictionary, status: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if job.payload_kind == "AIRCRAFT" and g.air.assets[job.asset_ref].status == "GROUND_LOADING":
		var asset: Dictionary = g.air.assets[job.asset_ref]
		asset.xy = aircraft_position(asset)
		asset.status = "AWAITING_RECOVERY"
	job.version += 1
	job.pending = ""
	job.status = status
	var unit: Dictionary = g._state.units[job.unit_ref]
	unit.spatial.path = []
	unit.spatial.returning = false
	g._state.wake(str(unit.area_id))
	_report(job, status)

func _end(job: Dictionary, status: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if job.payload_kind == "AIRCRAFT":
		var asset: Dictionary = g.air.assets[job.asset_ref]
		if status != "RECEIVED" and asset.status != "DESTROYED":
			_drop_aircraft(job)
		asset.recovery_ref = ""
		job.loaded = false
	elif status == "RECEIVED":
		job.loaded = false
	_pause(job, status)
	_unit_jobs.erase(job.unit_ref)
	job.finished_at = g._state.time
	var unit: Dictionary = g._state.units[job.unit_ref]
	var mission: Dictionary = g._state.missions[unit.mission_id]
	if mission.status == "active":
		g._finish(unit, mission, "complete" if status == "RECEIVED" else "cancelled", "physical_transport_finished", str(job.id))

func _drop_aircraft(job: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	var asset: Dictionary = g.air.assets[job.asset_ref]
	asset.xy = aircraft_position(asset)
	asset.status = "AWAITING_RECOVERY"
	asset.node = g._space.landing_site(asset.xy, str(g._state.units[job.unit_ref].spatial.node)).node_ref
	asset.landing = {"surface": "LAND", "node_ref": asset.node, "xy": asset.xy.duplicate(), "at": g._state.time}
	asset.recovery_ref = ""

func aircraft_position(asset: Dictionary) -> Array:
	var job: Dictionary = jobs[asset.recovery_ref]
	if asset.status == "GROUND_LOADING":
		var fraction: float = clampf((_owner.get_ref()._state.time - float(job.local_started_at)) / maxf(0.000001, float(job.local_due) - float(job.local_started_at)), 0.0, 1.0)
		return [lerpf(float(job.local_from[0]), float(job.local_to[0]), fraction), lerpf(float(job.local_from[1]), float(job.local_to[1]), fraction)]
	return _owner.get_ref()._space.xy(_owner.get_ref()._state.units[job.unit_ref]) if job.loaded else asset.xy

func _report(job: Dictionary, status: String, force: bool = false) -> void:
	if not force and job.get("reported_status", "") == status:
		return
	job.reported_status = status
	_report_serial += 1
	var g: RefCounted = _owner.get_ref()
	var unit: Dictionary = g._state.units[job.unit_ref]
	var value: Dictionary = _position(unit)
	value.blocked_edge = unit.spatial.blocked_edge
	value.blocked_at = unit.spatial.get("blocked_at", 0.0)
	value.merge({"transport_ref": job.id, "status": status, "target_node": job.target_node, "payload_kind": job.payload_kind,
		"carrier_ref": job.unit_ref, "source_node": job.source_node, "report_revision": _report_serial,
		"transport_status": job.status, "loaded": job.loaded, "fuel_spent": job.fuel_spent, "distance_km": job.distance_km})
	var recipients: Array = job.notify.duplicate()
	if job.issuer not in recipients:
		recipients.append(job.issuer)
	var structure: RefCounted = g._state.structure_port.get_ref()
	for scope: String in structure._path(str(structure._unit_nodes.get(job.unit_ref, ""))):
		var current: String = str(structure._positions.get(scope, {}).get("person", ""))
		if current != "" and current not in recipients:
			recipients.append(current)
	value.responsibility_revision = job.get("responsibility_revision", 0)
	var subject: String = str(job.asset_ref)
	if job.payload_kind == "CARGO":
		var delivery: Dictionary = g._state.logistics_port.get_ref()._deliveries[job.id]
		value.request_ref = delivery.get("request_id", "")
		value.sea_delivery_ref = delivery.get("sea_delivery_ref", "")
		value.delivery_status = delivery.status
		value.source_ref = delivery.source_ref
		value.recipient_ref = delivery.recipient_ref
		value.recipient_kind = delivery.recipient_kind
		value.original_request_ref = delivery.get("original_request_ref", "")
		value.cargo_owner_ref = delivery.source_ref if delivery.status == "RESERVED_AT_SOURCE" else delivery.recipient_ref if delivery.status == "RECEIVED" else job.unit_ref
		value.cargo = delivery.cargo.duplicate()
		value.lost_cargo = delivery.get("lost_cargo", {}).duplicate()
		value.received_cargo = delivery.get("received_cargo", {}).duplicate()
		subject = str(delivery.recipient_ref)
		if delivery.request_id != "":
			var request: Dictionary = g._state.logistics_port.get_ref()._requests[delivery.request_id]
			value.requested_quantity = request.quantity
			value.received_quantity = request.get("received_quantity", 0.0)
			value.cumulative_received_quantity = value.received_quantity
			value.request_balance = g._state.logistics_port.get_ref().physical_balance(str(delivery.request_id))
			value.resource_class = request.resource_class
			var requester: String = str(request.actor)
			if requester not in recipients:
				recipients.append(requester)
	else:
		var asset: Dictionary = g.air.assets[job.asset_ref]
		value.asset_status = asset.status
		value.surface = asset.get("landing", {}).get("surface", "UNKNOWN")
		value.xy = g.air.position(str(asset.id))
		value.integrity = asset.integrity
		value.base = asset.base
		value.serviceable = asset.serviceable
		value.recovery_ref = asset.get("recovery_ref", "")
	var platform: String = str(carriers[job.unit_ref].report_source)
	var claim: Dictionary = {"id": str(job.id) + "_%d" % _report_serial, "source_ref": platform, "observer_ref": platform,
		"subject_kind": str(value.recipient_kind) if job.payload_kind == "CARGO" else "aircraft", "subject_ref": subject,
		"fact_kind": "land_supply_status", "value": value, "observed_at": g._state.time, "precision": "actual_ground_handover", "quality": 1.0, "origin": "GROUND_TRANSPORT"}
	_serial += 1
	for recipient: String in recipients:
		var sent: Dictionary = claim.duplicate(true)
		if job.payload_kind == "CARGO" and value.get("request_ref", "") != "":
			var l: RefCounted = g._state.logistics_port.get_ref()
			var delivery: Dictionary = l._deliveries[job.id]
			var resource: String = str(l._requests[delivery.request_id].resource_class)
			var local: Dictionary = {"land_delivery_ref": delivery.delivery_id, "land_status": delivery.status,
				"land_committed": float(delivery.cargo.get(resource, 0.0)) if delivery.status in ["RESERVED_AT_SOURCE", "ONBOARD", "STRANDED"] else 0.0}
			if delivery.status == "RECEIVED":
				local.received_quantity = l._requests[delivery.request_id].get("received_quantity", 0.0)
			if _at(unit, str(job.source_node)) and delivery.get("sea_delivery_ref", "") != "":
				local.port_remaining = l.sea_port_remaining(str(delivery.sea_delivery_ref), resource, str(delivery.request_id), str(delivery.source_ref))
				local.port_depot_ref = delivery.source_ref
			sent.value.request_balance = g._state.information_port.get_ref().reported_supply_balance(recipient, str(delivery.request_id), value.request_balance, local)
		var claims: Array[Dictionary] = [sent]
		g._state.information_port.get_ref().send_platform_report(self, str(carriers[job.unit_ref].report_source), recipient, "land_report_" + str(job.id) + "_%d_" % _serial + recipient, claims)

func known_view(actor: String) -> Array[Dictionary]:
	var latest: Dictionary = {}
	for claim: Dictionary in _owner.get_ref()._state.information_port.get_ref().knowledge(actor).get("entries", []):
		if claim.fact_kind == "land_supply_status" and float(claim.reliability) > 0.0:
			var id: String = str(claim.claimed_value.transport_ref)
			if not latest.has(id) or float(claim.observed_at) > float(latest[id].observed_at) or float(claim.observed_at) == float(latest[id].observed_at) and int(claim.claimed_value.get("report_revision", 0)) >= int(latest[id].get("report_revision", 0)):
				latest[id] = claim.claimed_value.duplicate(true)
				latest[id].observed_at = claim.observed_at
				latest[id].received_at = claim.received_at
	var result: Array[Dictionary] = []
	for id: String in latest:
		result.append(latest[id])
	return result

const RUNTIME_FIELDS: Array[String] = ["carriers", "jobs", "_unit_jobs", "_tickets", "_serial", "_report_serial", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
