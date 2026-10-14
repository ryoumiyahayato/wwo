extends RefCounted
## Data-only envelope: received claims and authority metadata, never combat facts.
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
var _information: RefCounted
var _structure: RefCounted

func configure(information: RefCounted, structure: RefCounted) -> void:
	_information = information
	_structure = structure

func build(person: String, time: float, definition: Dictionary, next_time: float, ready: float) -> Dictionary:
	var received: Dictionary = _information.knowledge(person)
	if not received.ok:
		return received
	var position: Dictionary = _structure.command_person(person)
	var rank: int = Roles.ROLES.find(str(position.role))
	var targets: Dictionary = {}
	var command_targets: Array[String] = []
	for id: String in definition.targets:
		if not _structure.active(id) or not _structure._contains(str(position.formation_id), id):
			continue
		var node: Dictionary = _structure._nodes[id]
		targets[id] = {"echelon": node.echelon, "unit_ref": node.get("unit_id", "")}
		if rank == 1 and id == position.formation_id or rank >= 2 and (id == position.formation_id and rank >= 3 or _structure.parent(id) == position.formation_id):
			command_targets.append(id)
	var kinds: Array[String] = ["keep"]
	if _information._state.gameplay_port != null and _information._state.gameplay_port.get_ref().participants._units.has(person):
		kinds.append("local_action")
	if rank >= 1:
		kinds.append("command")
	if rank >= 2:
		kinds.append("logistics_request")
		kinds.append("report_forward")
	if rank >= 3 or rank >= 1 and _structure.member_adjustments:
		kinds.append("structure_request")
	var own_air: Array = []
	var own_vessels: Array = []
	var sea_transports: Array = []
	var land_transports: Array = []
	var operations: Array = []
	var known_routes: Dictionary = {}
	var unit_reports: Dictionary = {}
	var supply_requests: Array = []
	var contacts: Dictionary = {}
	var ports: Dictionary = {}
	if _information._state.gameplay_port != null:
		var service: RefCounted = _information._state.gameplay_port.get_ref()
		operations = service.operations.known_view(person)
		known_routes = service._known.get(person, {}).duplicate(true)
		if rank >= 2:
			land_transports = service.land.known_view(person)
		for target: Dictionary in targets.values():
			var unit: String = str(target.unit_ref)
			if unit.is_empty() or unit_reports.size() >= 8:
				continue
			var updates: Array = []
			for fact: String in ["unit_state", "objective"]:
				updates.append_array(_information.knowledge(person, "unit", unit, fact, 1).get("entries", []))
			updates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.observed_at) < float(b.observed_at) if a.observed_at != b.observed_at else int(a.claimed_value.get("report_revision", 0)) < int(b.claimed_value.get("report_revision", 0)))
			var known: Dictionary = {}
			for update: Dictionary in updates:
				if float(update.reliability) > 0.0:
					known.merge(update.claimed_value, true)
					known.observed_at = update.observed_at
					known.claim_ref = update.entry_id
			unit_reports[unit] = known
			var expected: float = INF
			for task: Dictionary in operations:
				if task.has("task_ref") and task.status not in ["COMPLETE", "FAILED", "CANCELLED"] and (task.get("unit_ref", "") == unit or task.get("intent", {}).get("values", {}).get("unit_ref", "") == unit):
					expected = minf(expected, float(task.started_at))
			contacts["unit:" + unit] = _information.contact_status(person, "unit", unit, expected if is_finite(expected) else 0.0)
			supply_requests.append_array(_information.knowledge(person, "unit", unit, "supply_request", 4).get("entries", []))
	if rank >= 3 and _information._state.gameplay_port != null:
		var gameplay: RefCounted = _information._state.gameplay_port.get_ref()
		own_air = gameplay.air.own_view(person)
		own_vessels = gameplay.sea.own_view(person)
		sea_transports = gameplay.sea.freight.known_view(person)
		land_transports = gameplay.land.known_view(person)
		for vessel: Dictionary in own_vessels:
			contacts["vessel:" + str(vessel.vessel_ref)] = _information.contact_status(person, "vessel", str(vessel.vessel_ref))
			var initial: Dictionary = vessel.get("initial_port_observation", {})
			if not initial.is_empty() and not ports.has(initial.port_ref):
				ports[initial.port_ref] = initial.duplicate(true)
			var port: Dictionary = vessel.get("port_observation", {})
			if not port.is_empty() and float(port.observed_at) >= float(ports.get(port.port_ref, {}).get("observed_at", -INF)):
				ports[port.port_ref] = port.duplicate(true)
	for claim: Dictionary in received.entries:
		var port: Dictionary = claim.claimed_value.get("port_observation", {}) if claim.fact_kind == "sea_status" else claim.claimed_value if claim.fact_kind == "depot_status" else {}
		if port.is_empty() or not port.has("port_ref") or float(claim.reliability) <= 0.0:
			continue
		var previous: Dictionary = ports.get(port.port_ref, {})
		if float(port.get("observed_at", claim.observed_at)) > float(previous.get("observed_at", -INF)) or port.get("observed_at", claim.observed_at) == previous.get("observed_at", -INF) and int(port.get("report_revision", 0)) >= int(previous.get("report_revision", 0)):
			ports[port.port_ref] = port.duplicate(true)
	return {"ok": true, "person_id": person, "role": position.role, "position_ref": position.formation_id,
		"operations": operations, "known_routes": known_routes, "unit_reports": unit_reports, "supply_requests": supply_requests, "contact_states": contacts, "known_ports": ports, "communications": _information.communication_view(person),
		"owned_air": own_air, "owned_vessels": own_vessels, "sea_transports": sea_transports, "land_transports": land_transports,
		"command_ready_at": _information._roles[person]._next_input.get(person, 0.0),
		"command_issue_ready_at": _information._next_issue.get(person, 0.0),
		"decision_time": time, "received_claims": received.entries, "knowledge_total": received.total_matching,
		"authority_targets": targets, "command_targets": command_targets, "output_kinds": kinds,
		"coordination_kinds": (["coordination", "reserve_intent", "air_intent", "naval_intent", "land_intent", "operation_intent", "tactical_intent"] if rank >= 3 else ["coordination", "operation_intent", "tactical_intent"] if rank >= 2 else ["tactical_intent"] if rank == 1 else []) if _information._state.gameplay_port != null else [],
		"command_kind": definition.get("command_kind", "tactical_intent" if rank == 1 else "mission"), "standing_orders": definition.standing_orders.duplicate(true),
		"cadence_seconds": definition.cadence, "next_opportunity": next_time, "ready_at": ready}
