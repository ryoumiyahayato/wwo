extends RefCounted
## A physical voyage owns a Task6 delivery reference, never a second cargo stock.
var _sea: WeakRef
var transports: Dictionary = {}
var transfers: Dictionary = {}
var rules: Dictionary = {"handling_seconds": 20.0, "cargo_per_second": 1.0,
	"capacity": 40.0, "loaded_speed_factor": 0.8, "local_delivery_seconds": 60.0,
	"transfer_radius_km": 0.005, "transfer_quantum": 10.0, "transfer_max_sea_state": 0.5, "transfer_min_crew": 0.5}

func configure(sea: RefCounted) -> void:
	_sea = weakref(sea)

func validate_rendezvous(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var partner: String = str(values.get("partner_ref", ""))
	if values.size() != 7 or not sea.vessels.has(partner) or partner == vessel.id or not sea._authorized(actor, sea.vessels[partner]) or not values.get("rendezvous_ref") is String or str(values.rendezvous_ref).is_empty() or not values.get("path") is Array or not values.get("target_node") is String:
		return sea._reject("two_existing_owned_ships_explicit_meeting_and_route_required")
	if not (values.get("deadline_seconds") is float or values.get("deadline_seconds") is int) or not is_finite(float(values.deadline_seconds)) or float(values.deadline_seconds) < 60.0 or float(values.deadline_seconds) > 3600.0 or sea.missions.size() >= sea.MAX_MISSIONS or sea.missions.has(id):
		return sea._reject("bounded_rendezvous_identity_and_deadline_required")
	if vessel.status not in ["DOCKED", "ANCHORED", "CARGO_WAITING", "WAITING_PORT", "BLOCKED", "FUEL_EXHAUSTED"] or not sea.mobile(vessel) or float(vessel.stock.fuel) <= 0.0 or vessel.get("recovery_ref", "") != "" or vessel.get("port_job_ref", "") != "":
		return sea._reject("actual_available_navigation_conditions_required")
	var learned: bool = false
	for report: Dictionary in sea.own_view(actor):
		learned = learned or report.vessel_ref == partner
	if not learned:
		return sea._reject("known_partner_required")
	if not sea._owner.get_ref().operations.permits_vessel_navigation(str(vessel.id), id, actor):
		return sea._reject("vessel_is_committed_to_another_task")
	return sea.validate_route(actor, vessel, values.path, str(values.target_node))

func start_rendezvous(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	sea._checkpoint(vessel)
	var predecessor: String = str(vessel.mission_ref)
	if sea.missions.has(predecessor):
		sea.missions[predecessor].status = "REPLACED_BY_RENDEZVOUS"
		sea.missions[predecessor].successor_ref = id
	vessel.version += 1
	sea.missions[id] = {"id": id, "issuer": actor, "operation": "rendezvous", "target_ref": "", "target_node": values.target_node,
		"partner_ref": values.partner_ref, "rendezvous_ref": values.rendezvous_ref, "predecessor_ref": predecessor, "path": values.path.duplicate(), "index": 0, "status": "SAILING", "started_at": sea._owner.get_ref()._state.time}
	vessel.mission_ref = id
	sea._ticket(vessel, "RENDEZVOUS_DEADLINE", sea._owner.get_ref()._state.time + float(values.deadline_seconds), {"mission_ref": id})
	sea._next(vessel, sea.missions[id])
	sea._report_to_issuer(vessel, id, "RENDEZVOUS_ORDER_APPLIED")

func arrive_rendezvous(vessel: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var mission: Dictionary = sea.missions[vessel.mission_ref]
	vessel.erase("leg")
	vessel.status = "CARGO_WAITING" if vessel.cargo_ref != "" else "ANCHORED"
	mission.status = "WAITING_PARTNER"
	var partner: Dictionary = sea.vessels[mission.partner_ref]
	var other: Dictionary = sea.missions.get(partner.mission_ref, {})
	if other.get("operation", "") == "rendezvous" and other.get("status", "") in ["WAITING_PARTNER", "RENDEZVOUS_READY"] and other.get("rendezvous_ref", "") == mission.rendezvous_ref and other.get("partner_ref", "") == vessel.id and partner.node == mission.target_node and vessel.node == mission.target_node and _stable_pair(vessel, partner):
		mission.status = "RENDEZVOUS_READY"
		other.status = "RENDEZVOUS_READY"
		sea._report_to_issuer(partner, str(other.id), "ACTUAL_PARTNER_AT_MEETING_SITE")
	sea._report_to_issuer(vessel, str(mission.id), str(mission.status))

func expire_rendezvous(vessel: Dictionary, reference: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	if vessel.status == "SUNK" or vessel.mission_ref != reference or sea.missions[reference].status == "RENDEZVOUS_READY":
		return
	sea._checkpoint(vessel)
	vessel.version += 1
	sea.missions[reference].status = "RENDEZVOUS_EXPIRED_AT_ACTUAL_POSITION"
	vessel.status = "CARGO_WAITING" if vessel.cargo_ref != "" else "ANCHORED"
	sea._report_to_issuer(vessel, reference, "RENDEZVOUS_EXPIRED_AT_ACTUAL_POSITION")

func rendezvous_status(vessel: Dictionary) -> Dictionary:
	var mission: Dictionary = _sea.get_ref().missions.get(vessel.mission_ref, {})
	if mission.get("operation", "") != "rendezvous":
		return {}
	return {"rendezvous_ref": mission.rendezvous_ref, "rendezvous_partner_ref": mission.partner_ref, "rendezvous_status": mission.status, "rendezvous_node": mission.target_node}

func assignment(transport: Dictionary, vessel: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var local: Dictionary = sea._owner.get_ref()._state.logistics_port.get_ref().sea_assignment(str(transport.delivery_ref), vessel)
	local.destination_port = transport.get("portion_ports", {}).get(vessel, transport.destination_port)
	local.land_required = transport.get("portion_land_required", {}).get(vessel, transport.get("land_required", false))
	return local

func _validate_reallocation(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	for key: String in values:
		if key not in ["operation", "vessel_ref", "supply_request_ref", "destination_port", "path", "land_required"]:
			return sea._reject("explicit_portion_reassignment_parameters_required")
	if vessel.cargo_ref == "" or not transports.has(vessel.cargo_ref) or not values.get("supply_request_ref") is String or not values.get("destination_port") is String or not values.get("path") is Array or not values.get("land_required", true) is bool:
		return sea._reject("actual_carriage_new_request_port_and_route_required")
	if not values.get("land_required", true):
		return sea._reject("reassigned_portions_use_explicit_physical_land_handover")
	if vessel.status not in ["SAILING", "CARGO_WAITING", "WAITING_PORT", "BLOCKED", "DOCKED", "ANCHORED"] or vessel.get("port_job_ref", "") != "" or vessel.get("recovery_ref", "") != "" or not sea.mobile(vessel) or float(vessel.stock.fuel) <= 0.0 or not sea.support.ports.has(values.destination_port):
		return sea._reject("navigation_available_actual_portion_required")
	if not sea._owner.get_ref().operations.permits_vessel_navigation(str(vessel.id), id, actor):
		return sea._reject("loaded_carrier_committed_to_another_current_task")
	var transport: Dictionary = transports[vessel.cargo_ref]
	var learned_cargo: bool = false
	var learned_request: bool = false
	for report: Dictionary in known_view(actor):
		learned_cargo = learned_cargo or report.transport_ref == transport.id and report.vessel_ref == vessel.id and cargo_quantity(report.get("cargo", {})) > 0.0
	for claim: Dictionary in sea._owner.get_ref()._state.information_port.get_ref().knowledge(actor).get("entries", []):
		learned_request = learned_request or float(claim.reliability) > 0.0 and (claim.claimed_value.get("request_ref", "") == values.supply_request_ref or claim.claimed_value.get("request_balance", {}).get("request_ref", "") == values.supply_request_ref)
	if not learned_cargo or not learned_request:
		return sea._reject("received_cargo_and_demand_required")
	var valid: Dictionary = sea.validate_route(actor, vessel, values.path, str(values.destination_port))
	if not valid.ok:
		return valid
	return l.reassign_sea(actor, str(transport.delivery_ref), str(vessel.id), str(values.supply_request_ref), str(sea.support.ports[values.destination_port].depot), id)

func validate(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var l: RefCounted = g._state.logistics_port.get_ref()
	if values.operation == "reassign_cargo":
		return _validate_reallocation(actor, vessel, values, id)
	if values.operation == "cancel_transshipment":
		return {"ok": true} if values.size() == 2 and vessel.get("transfer_ref", "") != "" else sea._reject("active_actual_transshipment_required")
	if values.operation == "transship_cargo":
		return _validate_transfer(actor, vessel, values, id)
	if values.operation == "forward_supply":
		if values.size() != 3 or not values.get("transport_ref") is String or not transports.has(values.transport_ref):
			return sea._reject("existing_received_sea_transport_required")
		var completed: Dictionary = transports[values.transport_ref]
		if completed.supply_request_ref == "" or l._deliveries[completed.delivery_ref].status != "RECEIVED" or l._requests[completed.supply_request_ref].status != "REQUESTED":
			return sea._reject("actual_port_stock_and_waiting_land_request_required")
		var learned: bool = false
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).get("entries", []):
			if claim.fact_kind == "sea_status" and claim.claimed_value.get("transport_ref", "") == completed.id and claim.claimed_value.get("transport_status", "") == "RECEIVED" and float(claim.reliability) > 0.0:
				learned = true
		var depot: String = str(sea.support.ports[completed.destination_port].depot)
		return {"ok": true} if learned and g._space._nodes[completed.destination_port].get("port_open", true) and l._allowed(actor, "depot", depot, 3) and l._allowed(actor, "unit", str(l._requests[completed.supply_request_ref].target), 3) else sea._reject("received_port_report_and_current_supply_authority_required")
	if values.operation == "transport":
		for key: String in values:
			if key not in ["vessel_ref", "operation", "source_port", "destination_port", "path", "cargo", "hold_departure", "supply_request_ref", "notify", "land_required"]:
				return sea._reject("unknown_transport_parameter")
		if not values.get("source_port") is String or not values.get("destination_port") is String or not values.get("cargo") is Dictionary or not values.get("path") is Array or not values.get("hold_departure", false) is bool or not values.get("supply_request_ref", "") is String or not values.get("notify", []) is Array or values.get("notify", []).size() > 3:
			return sea._reject("explicit_source_destination_manifest_and_water_route_required")
		if not values.get("land_required", false) is bool:
			return sea._reject("explicit_land_continuation_flag_required")
		if transports.size() >= 64 or transports.has(id) or sea.missions.size() >= sea.MAX_MISSIONS or sea.missions.has(id) or vessel.cargo_ref != "" or vessel.get("recovery_ref", "") != "" or not sea.mobile(vessel) or float(vessel.stock.fuel) <= 0.0 or vessel.status not in ["DOCKED", "ANCHORED", "SUPPLY_EXHAUSTED"]:
			return sea._reject("available_finite_capacity_carrier_required")
		if not sea.support.ports.has(values.source_port) or not sea.support.ports.has(values.destination_port) or sea.support.port_at(vessel) != values.source_port or sea.support.ports[values.source_port].busy != "":
			return sea._reject("actual_free_loading_port_and_known_destination_port_required")
		var source: String = str(sea.support.ports[values.source_port].depot)
		var destination: String = str(sea.support.ports[values.destination_port].depot)
		var valid: Dictionary = l.validate_sea_allocation(actor, id, source, destination, values.cargo)
		if not valid.ok:
			return valid
		if cargo_quantity(values.cargo) > float(vessel.cargo_capacity):
			return sea._reject("manifest_exceeds_actual_ship_capacity")
		var s: RefCounted = g._state.structure_port.get_ref()
		for recipient: Variant in values.get("notify", []):
			if not recipient is String or not s._people.has(recipient) or s._nodes[s._people[recipient].formation_id].side != s._nodes[vessel.owner].side:
				return sea._reject("existing_same_side_transport_report_recipient_required")
		var request: String = str(values.get("supply_request_ref", ""))
		if not request.is_empty():
			if not l._requests.has(request):
				return sea._reject("existing_waiting_land_supply_request_required")
			var r: Dictionary = l._requests[request]
			var balance: Dictionary = l.physical_balance(request)
			if r.status != "REQUESTED" or r.target_kind != "unit" or values.cargo.size() != 1 or not values.cargo.has(r.resource_class) or float(values.cargo[r.resource_class]) > float(balance.uncommitted_quantity) + 0.000001 or not l._allowed(actor, "unit", str(r.target), 3):
				return sea._reject("compatible_unallocated_land_request_required")
			if r.get("sea_delivery_ref", "") != "" and l._deliveries[r.sea_delivery_ref].status not in ["LOST_WITH_VESSEL", "CANCELLED_BEFORE_LOADING", "RETURNED_TO_SOURCE"]:
				var partial: bool = l._deliveries[r.sea_delivery_ref].status == "RECEIVED" and float(balance.port_remaining) <= 0.000001 and float(balance.land_committed) <= 0.000001 and float(balance.received_quantity) < float(r.quantity)
				partial = partial or l._deliveries[r.sea_delivery_ref].has("sea_assignments") and float(balance.sea_committed) + float(balance.port_remaining) + float(balance.land_committed) <= 0.000001
				if not partial:
					return sea._reject("land_request_already_bound_to_an_actual_sea_delivery")
		return sea.validate_route(actor, vessel, values.path, str(values.destination_port))
	if vessel.cargo_ref == "" or not transports.has(vessel.cargo_ref) or vessel.status == "SUNK":
		return sea._reject("existing_unfinished_ship_cargo_required")
	var transport: Dictionary = transports[vessel.cargo_ref]
	if values.operation == "continue_transport":
		var learned: bool = false
		for report: Dictionary in known_view(actor):
			learned = learned or report.transport_ref == transport.id and report.vessel_ref == vessel.id
		return {"ok": true} if learned and values.size() == 2 and l._deliveries[transport.delivery_ref].status == "ONBOARD" else sea._reject("received_existing_carriage_report_required")
	if values.operation == "cancel_transport":
		return {"ok": true} if values.size() == 2 and vessel.status not in ["REPAIRING", "SERVICING"] else sea._reject("transport_cannot_interrupt_unrelated_port_work")
	if values.operation == "unload":
		return {"ok": true} if values.size() == 2 and can_unload(vessel, transport) else sea._reject("actual_free_arrival_port_and_onboard_cargo_required")
	if values.size() != 4 or not values.get("path") is Array or not values.get("target_node") is String or values.target_node not in [transport.source_port, assignment(transport, str(vessel.id)).destination_port] or vessel.status not in ["CARGO_WAITING", "WAITING_PORT", "BLOCKED", "FUEL_EXHAUSTED", "DOCKED", "ANCHORED"] or not sea.mobile(vessel) or float(vessel.stock.fuel) <= 0.0:
		return sea._reject("explicit_available_cargo_resume_or_return_route_required")
	return sea.validate_route(actor, vessel, values.path, str(values.target_node))

func start(actor: String, vessel: Dictionary, values: Dictionary, id: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	if values.operation == "reassign_cargo":
		var transport: Dictionary = transports[vessel.cargo_ref]
		var valid: Dictionary = _validate_reallocation(actor, vessel, values, id)
		if not valid.ok:
			return
		g._state.logistics_port.get_ref().apply_sea_reassignment(str(transport.delivery_ref), str(vessel.id), valid)
		if not transport.has("portion_ports"):
			transport.portion_ports = {}
			transport.portion_land_required = {}
		transport.portion_ports[vessel.id] = values.destination_port
		transport.portion_land_required[vessel.id] = values.get("land_required", true)
		transport.responsible_actor = actor
		sea._checkpoint(vessel)
		vessel.version += 1
		var mission: Dictionary = sea.missions[vessel.mission_ref]
		mission.operation = "transport"
		mission.path = values.path.duplicate()
		mission.index = 0
		mission.target_node = values.destination_port
		mission.issuer = actor
		transport.status = "CARGO_REASSIGNED"
		_report(vessel, transport, id, "ACTUAL_PORTION_REASSIGNED")
		sea._next(vessel, mission)
		return
	if values.operation == "cancel_transshipment":
		interrupt_transfer(vessel, "TRANSFER_CANCELLED_AT_ACTUAL_POSITION")
		return
	if values.operation == "transship_cargo":
		_start_transfer(actor, vessel, values, id)
		return
	if values.operation == "forward_supply":
		var completed: Dictionary = transports[values.transport_ref]
		completed.land_allocation = g._state.logistics_port.get_ref().allocate_port_local(actor, "land_" + id, str(completed.supply_request_ref), str(sea.support.ports[completed.destination_port].depot), str(g._space._nodes[completed.destination_port].land_supply_node), g._state.time + float(rules.local_delivery_seconds), completed.notify)
		_report(vessel, completed, id, "PORT_LOCAL_ALLOCATION_RESULT")
		return
	if values.operation == "transport":
		var source: String = str(sea.support.ports[values.source_port].depot)
		var destination: String = str(sea.support.ports[values.destination_port].depot)
		var reserved: Dictionary = g._state.logistics_port.get_ref().reserve_sea(actor, id, str(vessel.id), source, destination, values.cargo)
		if not reserved.ok:
			return
		transports[id] = {"id": id, "issuer": actor, "vessel_ref": vessel.id, "source_port": values.source_port, "destination_port": values.destination_port,
			"delivery_ref": id, "status": "LOADING", "hold_departure": values.get("hold_departure", false), "land_required": values.get("land_required", false), "supply_request_ref": values.get("supply_request_ref", ""), "notify": values.get("notify", []).duplicate()}
		if transports[id].supply_request_ref != "":
			var l: RefCounted = g._state.logistics_port.get_ref()
			l._requests[transports[id].supply_request_ref].sea_delivery_ref = id
			l._requests[transports[id].supply_request_ref].sea_port_depot_ref = destination
			l._requests[transports[id].supply_request_ref].sea_required = true
			l._deliveries[id].front_request_ref = transports[id].supply_request_ref
			l._deliveries[id].received_before_batch = l._requests[transports[id].supply_request_ref].get("received_quantity", 0.0)
			l._deliveries[id].loss_before_batch = l._requests[transports[id].supply_request_ref].get("confirmed_loss_quantity", 0.0)
			l._deliveries[id].request_quantity_at_batch = l._requests[transports[id].supply_request_ref].quantity
		sea.missions[id] = {"id": id, "issuer": actor, "operation": "transport", "target_ref": "", "target_node": values.destination_port,
			"path": values.path.duplicate(), "index": 0, "status": "LOADING", "started_at": g._state.time}
		vessel.cargo_ref = id
		vessel.mission_ref = id
		vessel.version += 1
		vessel.status = "LOADING"
		sea.support.ports[values.source_port].busy = id
		sea._ticket(vessel, "CARGO_LOAD", g._state.time + _handling_seconds(values.cargo), {"transport_ref": id})
		_report(vessel, transports[id], id, "LOADING_AT_SOURCE")
		return
	var transport: Dictionary = transports[vessel.cargo_ref]
	if values.operation == "continue_transport":
		transport.responsible_actor = actor
		transport.responsibility_revision = int(transport.get("responsibility_revision", 0)) + 1
		sea.missions[vessel.mission_ref].issuer = actor
		_report(vessel, transport, id, "RESPONSIBILITY_CONTINUED")
		return
	if values.operation == "cancel_transport":
		hold(vessel, "CANCELLED_AT_ACTUAL_POSITION")
	elif values.operation == "unload":
		_arrive(vessel, transport)
	else:
		sea._checkpoint(vessel)
		vessel.version += 1
		var mission: Dictionary = sea.missions[vessel.mission_ref]
		mission.operation = "transport"
		mission.path = values.path.duplicate()
		mission.index = 0
		mission.target_node = values.target_node
		transport.status = "RETURNING_TO_SOURCE" if values.target_node == transport.source_port else "IN_TRANSIT"
		sea._next(vessel, mission)
		_report(vessel, transport, id, str(transport.status))

func _handling_seconds(cargo: Dictionary) -> float:
	return float(rules.handling_seconds) + cargo_quantity(cargo) / float(rules.cargo_per_second)

static func cargo_quantity(cargo: Dictionary) -> float:
	var quantity: float = 0.0
	for resource: String in cargo:
		quantity += float(cargo[resource])
	return quantity

func process(vessel: Dictionary, ticket: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var l: RefCounted = g._state.logistics_port.get_ref()
	if ticket.kind == "CARGO_TRANSFER":
		_transfer_step(ticket)
		return
	var transport: Dictionary = transports[ticket.transport_ref]
	if vessel.cargo_ref != transport.id:
		return
	if ticket.kind == "CARGO_LOAD":
		if vessel.status != "LOADING" or sea.support.port_at(vessel) != transport.source_port or not l.load_sea(str(transport.delivery_ref)):
			hold(vessel, "LOADING_INTERRUPTED")
			return
		sea.support.ports[transport.source_port].busy = ""
		transport.status = "CARGO_LOADED"
		if transport.hold_departure:
			vessel.status = "CARGO_WAITING"
			sea.missions[vessel.mission_ref].status = "WAITING_DEPARTURE_CLEARANCE"
		else:
			transport.status = "IN_TRANSIT"
			sea._next(vessel, sea.missions[vessel.mission_ref])
		_report(vessel, transport, str(ticket.get("transport_ref", "")) + "_loaded", str(transport.status))
		return
	var node: String = sea.support.port_at(vessel)
	if vessel.status != "UNLOADING" or node != ticket.port_ref or sea.support.ports[node].busy != str(transport.id) + ":" + str(vessel.id) or not l.unload_sea(str(transport.delivery_ref), str(sea.support.ports[node].depot), str(vessel.id)):
		hold(vessel, "UNLOADING_INTERRUPTED")
		return
	sea.support.ports[node].busy = ""
	transport.status = str(l._deliveries[transport.delivery_ref].status)
	if transport.status != "ONBOARD":
		transport.finished_at = g._state.time
	var portion: Dictionary = assignment(transport, str(vessel.id))
	sea.missions[vessel.mission_ref].status = "RECEIVED" if node == portion.destination_port else "RETURNED_TO_SOURCE"
	vessel.cargo_ref = ""
	vessel.status = "DOCKED" if sea.mobile(vessel) else "IMMOBILE"
	if node == portion.destination_port and portion.request_ref != "" and not portion.land_required and l._requests[portion.request_ref].status == "REQUESTED":
		transport.land_allocation = l.allocate_port_local(str(transport.get("responsible_actor", transport.issuer)), "land_" + str(transport.id) + "_" + str(vessel.id), str(portion.request_ref), str(sea.support.ports[node].depot), str(g._space._nodes[node].land_supply_node), g._state.time + float(rules.local_delivery_seconds), transport.notify)
	_report(vessel, transport, str(transport.id) + "_unloaded", str(transport.status))

func _stable_pair(source: Dictionary, recipient: Dictionary) -> bool:
	var sea: RefCounted = _sea.get_ref()
	var space: RefCounted = sea._owner.get_ref()._space
	if source.status not in ["CARGO_WAITING", "WAITING_PORT", "BLOCKED", "FUEL_EXHAUSTED", "DOCKED", "ANCHORED", "TRANSFERRING"] or recipient.status not in ["CARGO_WAITING", "WAITING_PORT", "BLOCKED", "FUEL_EXHAUSTED", "DOCKED", "ANCHORED", "TRANSFERRING"] or source.port_job_ref != "" or recipient.port_job_ref != "" or source.get("recovery_ref", "") != "" or recipient.get("recovery_ref", "") != "":
		return false
	for vessel: Dictionary in [source, recipient]:
		if not sea.mobile(vessel) or sea.support.available_crew(vessel) * (1.0 - sea.support.effort(vessel)) < float(rules.transfer_min_crew) or float(vessel.fire) > 0.1 or float(vessel.flooding) > 0.3 or float(space._nodes[sea.contact_node(str(vessel.id))].get("sea_state", 0.0)) > float(rules.transfer_max_sea_state):
			return false
	return sea._distance(sea.position(str(source.id)), sea.position(str(recipient.id))) <= float(rules.transfer_radius_km)

func _validate_transfer(actor: String, source: Dictionary, values: Dictionary, id: String) -> Dictionary:
	var sea: RefCounted = _sea.get_ref()
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	for key: String in values:
		if key not in ["operation", "vessel_ref", "recipient_vessel_ref", "cargo"]:
			return sea._reject("explicit_ship_transfer_parameters_required")
	if not values.get("recipient_vessel_ref") is String or not sea.vessels.has(values.recipient_vessel_ref) or values.recipient_vessel_ref == source.id or source.cargo_ref == "" or transfers.size() >= 64 or transfers.has(id):
		return sea._reject("two_existing_distinct_carriers_and_onboard_delivery_required")
	var recipient: Dictionary = sea.vessels[values.recipient_vessel_ref]
	if not sea._owner.get_ref().operations.permits_vessel_transfer(str(source.id), str(recipient.id), id):
		return sea._reject("receiving_vessel_committed_to_another_current_task")
	if values.has("cargo") and not values.cargo is Dictionary:
		return sea._reject("explicit_finite_transfer_manifest_required")
	if not sea._authorized(actor, recipient) or source.get("transfer_ref", "") != "" or recipient.get("transfer_ref", "") != "" or recipient.cargo_ref not in ["", source.cargo_ref] or not _stable_pair(source, recipient):
		return sea._reject("authorized_actual_stable_rendezvous_required")
	var transport: Dictionary = transports[source.cargo_ref]
	if l._deliveries[transport.delivery_ref].status != "ONBOARD" or recipient.cargo_ref == "" and (sea.missions.size() >= sea.MAX_MISSIONS or sea.missions.has(id)):
		return sea._reject("onboard_cargo_and_finite_receiving_carriage_required")
	var cargo: Dictionary = values.get("cargo", l.sea_carried(str(transport.delivery_ref), str(source.id)))
	var carried: Dictionary = l.sea_carried(str(transport.delivery_ref), str(source.id))
	if l._deliveries[transport.delivery_ref].has("sea_assignments") and cargo_quantity(l.sea_carried(str(transport.delivery_ref), str(recipient.id))) > 0.000001 and l.sea_assignment(str(transport.delivery_ref), str(source.id)) != l.sea_assignment(str(transport.delivery_ref), str(recipient.id)):
		return sea._reject("different_request_or_port_assignments_cannot_merge_in_one_hold")
	if cargo.is_empty() or cargo_quantity(cargo) <= 0.0 or cargo_quantity(cargo) + cargo_quantity(l.sea_carried(str(transport.delivery_ref), str(recipient.id))) > float(recipient.cargo_capacity):
		return sea._reject("finite_receiving_hold_capacity_required")
	for resource: String in cargo:
		if not l.CLASSES.has(resource) or not l._positive(cargo[resource]) or float(cargo[resource]) > float(carried.get(resource, 0.0)):
			return sea._reject("actual_donor_cargo_quantity_required")
	return {"ok": true}

func _start_transfer(actor: String, source: Dictionary, values: Dictionary, id: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var g: RefCounted = sea._owner.get_ref()
	var recipient: Dictionary = sea.vessels[values.recipient_vessel_ref]
	var transport: Dictionary = transports[source.cargo_ref]
	var cargo: Dictionary = values.get("cargo", g._state.logistics_port.get_ref().sea_carried(str(transport.delivery_ref), str(source.id)))
	if recipient.cargo_ref == "":
		sea.missions[id] = {"id": id, "issuer": actor, "operation": "transport", "target_ref": "", "target_node": transport.destination_port, "path": [], "index": 0, "status": "CARGO_WAITING", "started_at": g._state.time}
		recipient.mission_ref = id
	for vessel: Dictionary in [source, recipient]:
		sea._checkpoint(vessel)
		vessel.version += 1
		vessel.transfer_ref = id
		vessel.status = "TRANSFERRING"
	transfers[id] = {"id": id, "transport_ref": transport.id, "source_vessel_ref": source.id, "recipient_vessel_ref": recipient.id,
		"issuer": actor, "remaining": cargo.duplicate(), "transferred": {}, "status": "ACTIVE", "started_at": g._state.time}
	_schedule_transfer(transfers[id], true)
	_report(source, transport, id, "TRANSFER_STARTED")
	_report(recipient, transport, id, "TRANSFER_RECEIVING")

func _schedule_transfer(job: Dictionary, first: bool = false) -> void:
	var sea: RefCounted = _sea.get_ref()
	var quantity: float = minf(float(rules.transfer_quantum), cargo_quantity(job.remaining))
	sea._ticket(sea.vessels[job.source_vessel_ref], "CARGO_TRANSFER", sea._owner.get_ref()._state.time + (float(rules.handling_seconds) if first else 0.0) + quantity / float(rules.cargo_per_second), {"transfer_ref": job.id})

func _transfer_step(ticket: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	var job: Dictionary = transfers[ticket.transfer_ref]
	if job.status != "ACTIVE":
		return
	var source: Dictionary = sea.vessels[job.source_vessel_ref]
	var recipient: Dictionary = sea.vessels[job.recipient_vessel_ref]
	if source.transfer_ref != job.id or recipient.transfer_ref != job.id or not _stable_pair(source, recipient):
		interrupt_transfer(source, "TRANSFER_CONDITIONS_LOST")
		return
	var cargo: Dictionary = {}
	var remaining: float = float(rules.transfer_quantum)
	for resource: String in job.remaining:
		var amount: float = minf(remaining, float(job.remaining[resource]))
		if amount > 0.0:
			cargo[resource] = amount
			remaining -= amount
	var transport: Dictionary = transports[job.transport_ref]
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	if cargo_quantity(l.sea_carried(str(transport.delivery_ref), str(recipient.id))) + cargo_quantity(cargo) > float(recipient.cargo_capacity) or not l.transfer_sea_cargo(str(transport.delivery_ref), str(source.id), str(recipient.id), cargo):
		interrupt_transfer(source, "TRANSFER_CARGO_OR_CAPACITY_CHANGED")
		return
	recipient.cargo_ref = transport.id
	if transport.has("portion_ports"):
		transport.portion_ports[recipient.id] = assignment(transport, str(source.id)).destination_port
		transport.portion_land_required[recipient.id] = assignment(transport, str(source.id)).land_required
	for resource: String in cargo:
		job.remaining[resource] -= float(cargo[resource])
		job.transferred[resource] = float(job.transferred.get(resource, 0.0)) + float(cargo[resource])
	_report(source, transport, str(job.id), "PARTIAL_TRANSFER_COMPLETED")
	_report(recipient, transport, str(job.id), "PARTIAL_TRANSFER_RECEIVED")
	if cargo_quantity(job.remaining) <= 0.000001:
		job.status = "COMPLETE"
		_finish_transfer(job, "TRANSFER_COMPLETE")
	else:
		_schedule_transfer(job)

func interrupt_transfer(vessel: Dictionary, reason: String) -> void:
	var reference: String = str(vessel.get("transfer_ref", ""))
	if reference == "" or not transfers.has(reference) or transfers[reference].status != "ACTIVE":
		return
	transfers[reference].status = "INTERRUPTED"
	_finish_transfer(transfers[reference], reason)

func _finish_transfer(job: Dictionary, reason: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	var transport: Dictionary = transports[job.transport_ref]
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	job.finished_at = sea._owner.get_ref()._state.time
	for reference: String in [str(job.source_vessel_ref), str(job.recipient_vessel_ref)]:
		var vessel: Dictionary = sea.vessels[reference]
		vessel.transfer_ref = ""
		vessel.last_transfer_ref = job.id
		vessel.version += 1
		if cargo_quantity(l.sea_carried(str(transport.delivery_ref), reference)) <= 0.000001:
			vessel.cargo_ref = ""
		if vessel.status != "SUNK":
			vessel.status = ("CARGO_WAITING" if vessel.cargo_ref != "" else "ANCHORED") if sea.mobile(vessel) else "IMMOBILE"
		sea.missions[vessel.mission_ref].operation = "transport"
		_report(vessel, transport, str(job.id), reason)
	var source: Dictionary = sea.vessels[job.source_vessel_ref]
	if source.cargo_ref == "":
		transport.vessel_ref = job.recipient_vessel_ref
		l._deliveries[transport.delivery_ref].vessel_ref = job.recipient_vessel_ref

func can_unload(vessel: Dictionary, transport: Dictionary) -> bool:
	var sea: RefCounted = _sea.get_ref()
	var node: String = sea.support.port_at(vessel)
	return vessel.get("transfer_ref", "") == "" and vessel.status not in ["SAILING", "LOADING", "UNLOADING", "REPAIRING", "SERVICING", "SUNK"] and node in [transport.source_port, assignment(transport, str(vessel.id)).destination_port] and sea.support.ports[node].busy == "" and _sea.get_ref()._owner.get_ref()._state.logistics_port.get_ref()._deliveries[transport.delivery_ref].status == "ONBOARD"

func arrive(vessel: Dictionary) -> void:
	_arrive(vessel, transports[vessel.cargo_ref])

func _arrive(vessel: Dictionary, transport: Dictionary) -> void:
	var sea: RefCounted = _sea.get_ref()
	vessel.status = "CARGO_WAITING"
	if not can_unload(vessel, transport):
		vessel.status = "WAITING_PORT"
		transport.status = "WAITING_ACTUAL_UNLOADING_PORT"
		_report(vessel, transport, str(transport.id) + "_wait", str(transport.status))
		return
	var node: String = sea.support.port_at(vessel)
	vessel.status = "UNLOADING"
	transport.status = "UNLOADING"
	sea.missions[vessel.mission_ref].status = "UNLOADING"
	sea.support.ports[node].busy = str(transport.id) + ":" + str(vessel.id)
	vessel.version += 1
	var delivery: Dictionary = sea._owner.get_ref()._state.logistics_port.get_ref()._deliveries[transport.delivery_ref]
	sea._ticket(vessel, "CARGO_UNLOAD", sea._owner.get_ref()._state.time + _handling_seconds(sea._owner.get_ref()._state.logistics_port.get_ref().sea_carried(str(delivery.delivery_id), str(vessel.id))), {"transport_ref": transport.id, "port_ref": node})

func hold(vessel: Dictionary, reason: String) -> void:
	var sea: RefCounted = _sea.get_ref()
	interrupt_transfer(vessel, reason)
	var transport: Dictionary = transports[vessel.cargo_ref]
	sea._checkpoint(vessel)
	vessel.version += 1
	for node: String in [str(transport.source_port), str(assignment(transport, str(vessel.id)).destination_port)]:
		if sea.support.ports[node].busy in [str(transport.id), str(transport.id) + ":" + str(vessel.id)]:
			sea.support.ports[node].busy = ""
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	if l._deliveries[transport.delivery_ref].status == "RESERVED_AT_SOURCE":
		l.cancel_sea_reservation(str(transport.delivery_ref))
		vessel.cargo_ref = ""
	vessel.status = "CARGO_WAITING" if vessel.cargo_ref != "" else "DOCKED"
	transport.status = reason
	sea.missions[vessel.mission_ref].status = reason
	_report(vessel, transport, str(transport.id) + "_hold", reason)

func on_sunk(vessel: Dictionary, cause: String) -> void:
	interrupt_transfer(vessel, "VESSEL_SUNK")
	if vessel.cargo_ref == "":
		return
	var sea: RefCounted = _sea.get_ref()
	var transport: Dictionary = transports[vessel.cargo_ref]
	for node: String in [str(transport.source_port), str(transport.destination_port)]:
		if sea.support.ports[node].busy in [str(transport.id), str(transport.id) + ":" + str(vessel.id)]:
			sea.support.ports[node].busy = ""
	var l: RefCounted = sea._owner.get_ref()._state.logistics_port.get_ref()
	l.lose_sea_cargo(str(transport.delivery_ref), cause, str(vessel.id))
	transport.status = "VESSEL_SUNK" if l._deliveries[transport.delivery_ref].status == "LOST_WITH_VESSEL" else str(l._deliveries[transport.delivery_ref].status)
	_report(vessel, transport, cause, "CARRIER_PORTION_LOST")
	vessel.cargo_ref = ""
	for other: Dictionary in sea.vessels.values():
		var observer_node: String = sea.contact_node(str(other.id))
		var lost_node: String = sea.contact_node(str(vessel.id))
		var space: RefCounted = sea._owner.get_ref()._space
		var visible: bool = float(space._nodes[observer_node].get("sea_visibility", 1.0)) > 0.0 and (observer_node == lost_node or space._lanes.get(observer_node + ":" + lost_node, {}).get("observe", false))
		if other.id == vessel.id or other.status == "SUNK" or other.cargo_ref != transport.id or sea._distance(sea.position(str(other.id)), vessel.sunk_xy) > minf(float(rules.transfer_radius_km), float(other.sensor_range_km)) or not visible:
			continue
		if not transport.has("witnessed_losses"):
			transport.witnessed_losses = {}
		transport.witnessed_losses[other.id] = l._deliveries[transport.delivery_ref].get("lost_cargo", {}).duplicate()
		_report(other, transport, cause, "WITNESSED_CARRIER_CARGO_LOSS")
		var commander: String = sea.current_commander(other)
		if commander != "":
			var claim: Dictionary = sea.contact_claim(str(other.id), str(vessel.id), cause + "_witness", 1.0, "LOCAL_SURFACE_OBSERVATION")
			claim.fact_kind = "friendly_sea_contact"
			claim.value.confirmed_loss = true
			claim.value.status = "SUNK"
			sea._owner.get_ref()._state.information_port.get_ref().send_platform_report(sea, str(other.id), commander, cause + "_witness_" + str(other.id), [claim])

func status(vessel: Dictionary) -> Dictionary:
	if vessel.cargo_ref == "":
		return {}
	var transport: Dictionary = transports[vessel.cargo_ref]
	var delivery: Dictionary = _sea.get_ref()._owner.get_ref()._state.logistics_port.get_ref()._deliveries[transport.delivery_ref]
	var portion: Dictionary = assignment(transport, str(vessel.id))
	return {"transport_ref": transport.id, "delivery_ref": transport.delivery_ref, "status": transport.status,
		"source_port": transport.source_port, "destination_port": portion.destination_port, "request_ref": portion.request_ref, "cargo": _sea.get_ref()._owner.get_ref()._state.logistics_port.get_ref().sea_carried(str(delivery.delivery_id), str(vessel.id)), "manifest_cargo": delivery.requested_cargo.duplicate()}

func note_status(vessel: Dictionary, state: String) -> void:
	var transport: Dictionary = transports[vessel.cargo_ref]
	if vessel.status in ["BLOCKED", "FUEL_EXHAUSTED", "IMMOBILE"]:
		transport.status = str(vessel.status)
	_report(vessel, transport, "navigation", state)

func known_view(actor: String) -> Array[Dictionary]:
	var latest: Dictionary = {}
	for claim: Dictionary in _sea.get_ref()._owner.get_ref()._state.information_port.get_ref().knowledge(actor).get("entries", []):
		if claim.fact_kind != "sea_status" or float(claim.reliability) <= 0.0 or not claim.claimed_value.has("transport_ref"):
			continue
		var id: String = str(claim.claimed_value.transport_ref) + ":" + str(claim.subject_ref)
		if not latest.has(id) or float(claim.observed_at) > float(latest[id].observed_at) or claim.observed_at == latest[id].observed_at and int(claim.claimed_value.get("report_revision", 0)) > int(latest[id].get("report_revision", 0)):
			latest[id] = claim.claimed_value.duplicate(true)
			latest[id].vessel_ref = claim.subject_ref
			latest[id].status = claim.claimed_value.transport_status
			latest[id].observed_at = claim.observed_at
			latest[id].learned_at = claim.received_at
	var result: Array[Dictionary] = []
	for id: String in latest:
		result.append(latest[id])
	return result

func _report(vessel: Dictionary, transport: Dictionary, cause: String, state: String) -> void:
	var recipients: Array = transport.notify.duplicate()
	var commander: String = _sea.get_ref().current_commander(vessel)
	if commander != "" and commander not in recipients:
		recipients.append(commander)
	if transport.issuer not in recipients:
		recipients.append(transport.issuer)
	if transport.get("responsible_actor", "") != "" and transport.responsible_actor not in recipients:
		recipients.append(transport.responsible_actor)
	var l: RefCounted = _sea.get_ref()._owner.get_ref()._state.logistics_port.get_ref()
	var delivery: Dictionary = l._deliveries[transport.delivery_ref]
	var carried: Dictionary = l.sea_carried(str(delivery.delivery_id), str(vessel.id))
	var portion: Dictionary = assignment(transport, str(vessel.id))
	var updates: Array = []
	var request_refs: Array[String] = []
	if portion.request_ref != "":
		request_refs.append(str(portion.request_ref))
	for update: Dictionary in delivery.get("assignment_history", []):
		if update.vessel_ref != vessel.id:
			continue
		updates.append(update.duplicate(true))
		for ref: String in [str(update.old_request_ref), str(update.request_ref)]:
			if ref != "" and ref not in request_refs:
				request_refs.append(ref)
	var status: String = str(transport.status)
	var mission_status: String = str(_sea.get_ref().missions.get(vessel.mission_ref, {}).get("status", ""))
	if delivery.has("cargo_by_vessel") and delivery.status == "ONBOARD":
		status = "PORTION_LOST" if vessel.status == "SUNK" else ("PORTION_RECEIVED" if cargo_quantity(carried) <= 0.000001 and vessel.cargo_ref == "" and mission_status == "RECEIVED" else "RETURNED_TO_SOURCE" if mission_status == "RETURNED_TO_SOURCE" else "IN_TRANSIT" if vessel.status == "SAILING" else str(vessel.status))
	if delivery.has("cargo_by_vessel") and vessel.cargo_ref == "" and vessel.status != "SUNK" and sea_port(vessel) == portion.destination_port and mission_status == "RECEIVED":
		status = "PORTION_RECEIVED"
	var transfer: Dictionary = transfers.get(vessel.get("transfer_ref", vessel.get("last_transfer_ref", "")), {})
	if transfer.is_empty():
		transfer = transfers.get(vessel.get("last_transfer_ref", ""), {})
	for ref: String in request_refs:
		if l._requests[ref].actor not in recipients:
			recipients.append(l._requests[ref].actor)
	for recipient: String in recipients:
		var witnessed: Dictionary = transport.get("witnessed_losses", {}).get(vessel.id, {})
		var balances: Dictionary = {}
		for ref: String in request_refs:
			var actual: Dictionary = l.physical_balance(ref)
			if actual.get("sea_delivery_ref", "") != delivery.delivery_id:
				continue
			var resource: String = str(l._requests[ref].resource_class)
			var local: Dictionary = {"sea_committed": float(carried.get(resource, 0.0)) if ref == portion.request_ref else 0.0, "allocation_updates": updates}
			if not witnessed.is_empty() and not delivery.has("sea_assignments"):
				local.confirmed_loss_quantity = float(delivery.get("loss_before_batch", 0.0)) + float(witnessed.get(resource, 0.0))
			if ref == portion.request_ref:
				local.port_depot_ref = portion.recipient_ref
			if sea_port(vessel) == portion.destination_port and ref == portion.request_ref:
				local.port_remaining = l.sea_port_remaining(str(delivery.delivery_id), resource, ref, str(portion.recipient_ref))
			if sea_port(vessel) == transport.source_port and not delivery.has("sea_assignments"):
				local.returned_quantity = delivery.get("returned_cargo", {}).get(resource, 0.0)
			balances[ref] = _sea.get_ref()._owner.get_ref()._state.information_port.get_ref().reported_supply_balance(recipient, ref, actual, local)
		var balance: Dictionary = balances.get(portion.request_ref, {})
		_sea.get_ref()._report_status(vessel, recipient, cause, state, {"transport_ref": transport.id, "transport_status": status,
			"delivery_ref": transport.delivery_ref, "source_port": transport.source_port, "destination_port": portion.destination_port,
			"request_ref": portion.request_ref, "land_required": portion.land_required, "allocation_updates": updates, "allocation_balances": balances,
			"responsibility_revision": transport.get("responsibility_revision", 0),
			"transfer_ref": transfer.get("id", ""), "transfer_status": transfer.get("status", ""), "transferred_cargo": transfer.get("transferred", {}).duplicate(),
			"transfer_source_ref": transfer.get("source_vessel_ref", ""), "transfer_recipient_ref": transfer.get("recipient_vessel_ref", ""),
			"cargo": carried, "manifest_cargo": delivery.requested_cargo.duplicate(), "carriage_revision": delivery.get("carriage_revision", 0),
			"unloaded_cargo": delivery.get("unloaded_by_assignment", {}).get(str(portion.request_ref) + ":" + str(portion.recipient_ref), {}).duplicate() if delivery.has("sea_assignments") and sea_port(vessel) == portion.destination_port else (delivery.get("unloaded_cargo", {}).duplicate() if not delivery.has("cargo_by_vessel") or sea_port(vessel) == portion.destination_port else {}),
			"lost_cargo": delivery.get("lost_cargo", {}).duplicate() if not delivery.has("cargo_by_vessel") else witnessed,
			"request_balance": balance,
			"land_allocation": transport.get("land_allocation", {}).duplicate(true)})

func sea_port(vessel: Dictionary) -> String:
	return _sea.get_ref().support.port_at(vessel)

const RUNTIME_FIELDS: Array[String] = ["transports", "transfers", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
