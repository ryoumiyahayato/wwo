extends RefCounted
## Small purpose/task catalogue. Orders and feedback still travel through Information.
const MAX_OPERATIONS: int = 8
const MAX_TASKS: int = 8
const TERMINAL: Array[String] = ["COMPLETE", "FAILED", "CANCELLED"]
var _owner: WeakRef
var _active: bool = false
var _records: Dictionary = {}
var _known: Dictionary = {}
var _resources: Dictionary = {}
var _commands: Dictionary = {}
var _serial: int = 0
var _field_sources: Dictionary = {}
var _field_spares: Dictionary = {}
var _field_last: Dictionary = {}
var _field_readers: Dictionary = {}
var _office_orders: Dictionary = {}
var engineers: Dictionary = {}
var _work_units: Dictionary = {}
var _work_tickets: Dictionary = {}
var _work_results: Dictionary = {}
var _special_units: Dictionary = {}
var rules: Dictionary = {"ammo_warning_per_equipment": 2.0}

func ammunition_level(unit: Dictionary) -> String:
	var tactics: RefCounted = _owner.get_ref().tactics
	var local_equipment: float = maxf(0.0, float(unit.get("serviceable_equipment", unit.equipment)) - tactics.protected_equipment(str(unit.id)))
	if tactics.manoeuvre_active(str(unit.id)):
		local_equipment = float(tactics.manoeuvres[unit.id].parts.rear.serviceable)
	return "LOW" if tactics.ammunition_at_unit(unit) < maxf(1.0, local_equipment * float(rules.ammo_warning_per_equipment)) else "AVAILABLE"

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func activate() -> void:
	if _active:
		return
	_active = true
	_owner.get_ref()._state.information_port.get_ref().message_transition.connect(_on_message)
	_owner.get_ref()._space.route_feedback.connect(_on_route)

func admit_office_orders(scope: String, orders: Dictionary) -> void:
	if _owner.get_ref()._state.time == 0.0:
		_office_orders[scope] = orders.duplicate(true)

func office_orders(scope: String) -> Dictionary:
	return _office_orders.get(scope, {}).duplicate(true)

func admit_engineer(unit: String, capability: Dictionary) -> bool:
	var g: RefCounted = _owner.get_ref()
	if g._state.time != 0.0 or engineers.size() >= 2 or engineers.has(unit) or not g._state.units.has(unit) or not g._state.units[unit].has("spatial"):
		return false
	for key: String in ["minimum_crew", "minimum_equipment", "clear_seconds", "repair_seconds", "clear_spares", "repair_spares"]:
		if not _number(capability.get(key)) or float(capability[key]) <= 0.0:
			return false
	if capability.has("positions"):
		if not capability.positions is Dictionary or capability.positions.size() > 3:
			return false
		for kind: String in capability.positions:
			var profile: Variant = capability.positions[kind]
			if kind not in ["personal", "squad", "weapon"] or not profile is Dictionary or not _number(profile.get("seconds")) or not _number(profile.get("spares")) or float(profile.seconds) <= 0.0 or float(profile.spares) <= 0.0:
				return false
	engineers[unit] = capability.duplicate(true)
	return true

func occupied_ground(unit: String) -> bool:
	return _work_units.has(unit) or _special_units.has(unit)

func dispose() -> void:
	if _active:
		_owner.get_ref()._state.information_port.get_ref().message_transition.disconnect(_on_message)
		_owner.get_ref()._space.route_feedback.disconnect(_on_route)
		_active = false

func admit_field_observer(unit_id: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	if g._state.time != 0.0 or _field_sources.size() >= 4 or not s._unit_nodes.has(unit_id) or not g._state.units.has(unit_id):
		return false
	var source: String = "field_" + unit_id
	if not g._state.information_port.get_ref().register_platform_source(source, str(s._unit_nodes[unit_id]), self):
		return false
	_field_sources[unit_id] = source
	return true

func report_air_track(producer: RefCounted, unit_id: String, recipient: String, id: String, observation: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if producer != g.air.defense or not producer.defenders.has(unit_id) or not _field_sources.has(unit_id):
		return {"ok": false, "error": "actual_field_reporting_capability_required"}
	var source: String = str(_field_sources[unit_id])
	var claim: Dictionary = observation.duplicate(true)
	claim.source_ref = source
	# The existing unit platform conveys a real AA observation; it is no new radio.
	var claims: Array[Dictionary] = [claim]
	return g._state.information_port.get_ref().send_platform_report(self, source, recipient, id, claims)

func on_unit(unit_id: String, force: bool = false) -> void:
	var g: RefCounted = _owner.get_ref()
	_ground_work(unit_id)
	if not _field_sources.has(unit_id) or not g._state.units.has(unit_id):
		return
	var unit: Dictionary = g._state.units[unit_id]
	if not unit.has("spatial") or float(unit.effective) <= 0.001:
		return
	if g.tactics.manoeuvre_active(unit_id) and g.tactics.part_capacity(g.tactics.manoeuvres[unit_id].parts.rear) <= 0.001:
		return
	var mission: Dictionary = g._state.missions[unit.mission_id]
	var value: Dictionary = {"node_ref": unit.spatial.node, "edge_ref": unit.spatial.edge, "blocked_edge": unit.spatial.blocked_edge, "blocked_at": unit.spatial.get("blocked_at", 0.0), "from_node": unit.spatial.get("from", ""),
		"path": unit.spatial.path.duplicate(), "state": unit.action, "mission_ref": unit.mission_id,
		"ammunition_level": ammunition_level(unit),
		"fuel_level": "LOW" if unit.get("supply_capability", {}).get("fuel_dependent", false) and float(unit.get("fuel", 0.0)) <= 0.0 else "AVAILABLE",
		"spares_level": "LOW" if float(unit.get("damaged_equipment", 0.0)) > 0.0 and float(unit.get("spares", 0.0)) < float(unit.get("supply_capability", {}).get("spares_per_repair", 1.0)) else "AVAILABLE",
		"capability": "UNAVAILABLE" if float(unit.effective) <= 0.001 else ("IMMOBILE" if float(unit.get("serviceable_equipment", unit.equipment)) <= 0.0 else "AVAILABLE"),
		"available_crew": minf(float(unit.effective), float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))), "available_equipment": unit.get("serviceable_equipment", unit.equipment),
		"reason": "route_blocked" if not str(unit.spatial.blocked_edge).is_empty() else "",
		"retained": g._state.coordination.get(unit_id, {}).get("retained", false),
		"occupied": g.land._unit_jobs.has(unit_id) or g.air.recovery._unit_jobs.has(unit_id)}
	if g.land.carriers.has(unit_id):
		value.transport_capacity = g.land.capacity(unit)
	value.tactical = g.tactics.unit_fact(unit_id)
	value.occupied = bool(value.occupied) or g.tactics.manoeuvre_active(unit_id)
	value.xy = g._space.xy(unit)
	value.local_place_ref = g._space.local_place(unit.spatial)
	value.local_edge_ref = str(unit.spatial.get("local_edge", ""))
	value.entered_site_ref = str(unit.spatial.get("entered_site_ref", ""))
	value.suppression_level = "HIGH" if float(unit.suppression) >= 0.5 else "LOW"
	if g.tactics.manoeuvre_active(unit_id):
		var part: Dictionary = g.tactics.manoeuvres[unit_id].parts.rear
		value.available_crew = part.anonymous
		value.available_equipment = part.serviceable
		value.suppression_level = "HIGH" if g.tactics.part_pressure(part) >= 0.5 else "LOW"
		value.distribution_partial = true
	if engineers.has(unit_id):
		value.engineering_capability = engineers[unit_id].duplicate()
		value.engineering_spares = float(unit.get("spares", 0.0))
		if float(unit.get("spares", 0.0)) < maxf(float(engineers[unit_id].clear_spares), float(engineers[unit_id].repair_spares)):
			value.spares_level = "LOW"
	if _work_units.has(unit_id):
		value.ground_work = _work_units[unit_id].duplicate(true)
		value.occupied = true
	elif _work_results.has(unit_id):
		value.ground_work = _work_results[unit_id].duplicate(true)
	value.field_report_capabilities = 1 + _field_spares.get(unit_id, []).size()
	if mission.has("goal_v1"):
		var subjects: Array[String] = [unit_id]
		value.merge(g.visible_fact(subjects, "objective"), true)
	else:
		value.status = mission.status
	var s: RefCounted = g._state.structure_port.get_ref()
	var recipients: Array[String] = []
	for node: String in s._path(str(s._unit_nodes[unit_id])):
		var person: String = str(s._positions.get(node, {}).get("person", ""))
		if not person.is_empty() and person not in recipients:
			recipients.append(person)
	if not force and _field_last.get(unit_id, {}) == value and _field_readers.get(unit_id, []) == recipients:
		return
	_field_last[unit_id] = value.duplicate(true)
	_field_readers[unit_id] = recipients.duplicate()
	_serial += 1
	value.report_revision = _serial
	var claims: Array[Dictionary] = [{"id": "field_claim_%d" % _serial, "source_ref": _field_sources[unit_id], "subject_kind": "unit", "subject_ref": unit_id,
		"fact_kind": "unit_state", "value": value, "observed_at": g._state.time, "observer_ref": unit_id,
		"origin": "SUBORDINATE_REPORT", "quality": 1.0, "precision": "own_unit_discrete_status"}]
	for recipient: String in recipients:
		g._state.information_port.get_ref().send_platform_report(self, str(_field_sources[unit_id]), recipient, "field_report_%d_%s" % [_serial, recipient], claims)
	_survey(unit_id, "", "")

func _on_route(unit_id: String, kind: String, _cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if not g._state.units.has(unit_id):
		return
	var spatial: Dictionary = g._state.units[unit_id].spatial
	var edge: String = str(spatial.blocked_edge) if kind == "BLOCKED" else (str(spatial.traversed.back()) if kind == "ARRIVED" and not spatial.traversed.is_empty() else "")
	if kind == "BLOCKED" and _field_sources.has(unit_id) and g._space._edges.has(edge):
		_serial += 1
		var claim: Dictionary = {"id": "route_obstruction_%d" % _serial, "source_ref": _field_sources[unit_id], "subject_kind": "route", "subject_ref": edge,
			"fact_kind": "route_observation", "value": {"edge_ref": edge, "node_ref": spatial.node, "state": "BLOCKED", "coverage": "LOCAL_ENTRY", "obstruction": g._space._edges[edge].get("obstruction", "unclassified")},
			"observed_at": g._state.time, "observer_ref": unit_id, "origin": "ACTUAL_ROUTE_OBSTRUCTION", "quality": 1.0, "precision": "local_blocked_facility"}
		var structure: RefCounted = g._state.structure_port.get_ref()
		for scope: String in structure._path(str(structure._unit_nodes.get(unit_id, ""))):
			var recipient: String = str(structure._positions.get(scope, {}).get("person", ""))
			if recipient != "" and float(g._state.units[unit_id].effective) >= 1.0:
				g._state.information_port.get_ref().send_platform_report(self, str(_field_sources[unit_id]), recipient, "route_obstruction_%d_%s" % [_serial, recipient], [claim])
	_survey(unit_id, edge, kind)

func _survey(unit_id: String, edge: String, event: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if not _field_sources.has(unit_id) or not g._state.units.has(unit_id) or float(g._state.units[unit_id].effective) < 1.0:
		return
	var unit: Dictionary = g._state.units[unit_id]
	for record: Dictionary in _records.values():
		for task: Dictionary in record.tasks.values():
			if task.domain != "GROUND" or task.get("unit_ref", "") != unit_id or task.get("mission_ref", "") != unit.mission_id or task.status not in ["EXECUTING", "BLOCKED"]:
				continue
			var claims: Array[Dictionary] = []
			_serial += 1
			if not edge.is_empty() and edge in task.get("survey_edges", []) and event in ["ARRIVED", "BLOCKED"]:
				claims.append({"id": "route_survey_%d" % _serial, "source_ref": _field_sources[unit_id], "subject_kind": "route", "subject_ref": edge,
					"fact_kind": "route_observation", "value": {"edge_ref": edge, "node_ref": unit.spatial.node, "state": "PASSABLE" if event == "ARRIVED" else "BLOCKED", "obstruction": g._space._edges[edge].get("obstruction", "unclassified") if event == "BLOCKED" else "NONE",
						"coverage": "TRAVERSED_SEGMENT" if event == "ARRIVED" else "LOCAL_ENTRY", "operation_ref": record.id, "task_ref": task.task_ref},
					"observed_at": g._state.time, "observer_ref": unit_id, "origin": "GROUND_ROUTE_SURVEY", "quality": 1.0, "precision": "actual_route_event"})
			var subject: String = str(task.get("survey_unit", ""))
			if g._state.units.has(subject):
				var other: Dictionary = g._state.units[subject]
				var quality: float = g._space.observation(unit, other)
				if other.side == unit.side and quality > 0.0:
					var condition: String = "INCAPACITATED" if float(other.effective) <= 0.001 else "PRESENT"
					var sample: Dictionary = {"node_ref": other.spatial.node, "condition": condition, "operation_ref": record.id, "observer_ref": unit_id}
					if str(unit.spatial.edge).is_empty() and str(other.spatial.edge).is_empty() and g._space.xy(unit) == g._space.xy(other):
						sample.field_report_capabilities = int(_field_sources.has(subject)) + _field_spares.get(subject, []).size()
					if task.get("last_contact_sample", {}) != sample:
						task.last_contact_sample = sample.duplicate(true)
						claims.append({"id": "ground_contact_%d" % _serial, "source_ref": _field_sources[unit_id], "subject_kind": "unit", "subject_ref": subject,
							"fact_kind": "unit_condition" if condition == "INCAPACITATED" else "friendly_contact", "value": sample,
							"observed_at": g._state.time, "observer_ref": unit_id, "origin": "GROUND_LOCAL_OBSERVATION", "quality": quality, "precision": "local_presence_only"})
			var recipients: Array[String] = [str(task.executor)]
			if record.issuer not in recipients:
				recipients.append(str(record.issuer))
			for recipient: String in recipients:
				if not claims.is_empty():
					g._state.information_port.get_ref().send_platform_report(self, str(_field_sources[unit_id]), recipient, "survey_%d_%s" % [_serial, recipient], claims)

func validate(actor: String, target: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	var position: Dictionary = s.command_person(actor)
	if not _active or s.Roles.ROLES.find(str(position.role)) < 2 or not s._contains(str(position.formation_id), target):
		return _reject("purpose_requires_current_command_scope")
	if values.get("operation", "") == "reduce_supply_request":
		var reference: String = str(values.get("request_ref", ""))
		var learned: bool = false
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).get("entries", []):
			learned = learned or float(claim.reliability) > 0.0 and (claim.claimed_value.get("request_ref", "") == reference or claim.claimed_value.get("request_balance", {}).get("request_ref", "") == reference)
		return g._state.logistics_port.get_ref().reduce_uncommitted(actor, reference, values.get("quantity")) if learned and values.size() == 3 else _reject("received_request_and_explicit_future_quantity_required")
	if values.get("operation", "") == "request_report":
		var subject: String = str(values.get("subject_ref", ""))
		var kind: String = str(values.get("subject_kind", ""))
		if kind == "unit" and s._unit_nodes.has(subject) and s._contains(target, str(s._unit_nodes[subject])):
			return {"ok": true}
		if kind == "vessel" and g.sea.vessels.has(subject) and g.sea._authorized(actor, g.sea.vessels[subject]):
			return {"ok": true}
		return _reject("report_request_requires_existing_owned_subject")
	if values.get("operation", "") == "transfer_observer":
		var source: String = str(values.get("source_unit", ""))
		var destination: String = str(values.get("unit_ref", ""))
		if not _field_sources.has(source) or _field_sources.has(destination) or not g._state.units.has(source) or not g._state.units.has(destination) or not s._contains(target, str(s._unit_nodes.get(source, ""))) or not s._contains(target, str(s._unit_nodes.get(destination, ""))):
			return _reject("owned_existing_field_capability_and_receiving_unit_required")
		var a: Dictionary = g._state.units[source]
		var b: Dictionary = g._state.units[destination]
		if not a.has("spatial") or not b.has("spatial") or float(a.effective) < 1.0 or float(b.effective) < 1.0 or a.spatial.node != b.spatial.node or not str(a.spatial.edge).is_empty() or not str(b.spatial.edge).is_empty() or g._space.xy(a) != g._space.xy(b):
			return _reject("field_capability_requires_actual_crewed_rendezvous")
		return {"ok": true}
	if values.get("operation", "") == "reassign":
		return _validate_reassignment(actor, target, values)
	if values.get("operation", "") in ["cancel", "priority"]:
		var reference: String = str(values.get("operation_ref", ""))
		if not _records.has(reference) or _records[reference].scope != target or _records[reference].status in TERMINAL:
			return _reject("active_owned_purpose_required")
		if values.operation == "priority" and not _priority(values.get("priority")):
			return _reject("bounded_priority_required")
		return {"ok": true}
	if values.get("operation", "") != "begin" or _records.has(id) or values.get("purpose", "") not in ["hold", "advance", "route_security", "supply", "recon_support", "withdraw"] or not g._known.get(actor, {}).has(values.get("target_node", "")) or not _priority(values.get("priority")) or not _number(values.get("deadline_seconds")) or float(values.deadline_seconds) < 60.0 or float(values.deadline_seconds) > 86400.0:
		return _reject("explicit_bounded_purpose_required")
	if not values.get("tasks") is Array or values.tasks.is_empty() or values.tasks.size() > MAX_TASKS:
		return _reject("one_to_eight_actual_tasks_required")
	if values.has("supports_operation_ref"):
		var supported: bool = false
		for known: Dictionary in known_view(actor):
			if known.operation_ref == values.supports_operation_ref and (known.scope == target or s._contains(str(known.scope), target)):
				supported = true
		if not supported:
			return _reject("recovery_requires_received_supported_purpose")
	if values.has("predecessor_ref"):
		var informed: bool = false
		for previous: Dictionary in known_view(actor):
			if not previous.has("task_ref") and previous.operation_ref == values.predecessor_ref and previous.scope == target and previous.status in TERMINAL:
				informed = true
		if not informed:
			return _reject("followup_requires_received_predecessor_result")
	var ongoing: int = 0
	for operation: Dictionary in _records.values():
		ongoing += int(operation.status not in TERMINAL or _has_open_tasks(operation))
	if ongoing >= MAX_OPERATIONS:
		return _reject("active_purpose_capacity")
	var seen: Dictionary = {}
	var necessary: bool = false
	for task: Variant in values.tasks:
		if not task is Dictionary or not task.get("task_ref") is String or str(task.task_ref).is_empty() or seen.has(task.task_ref) or task.get("domain", "") not in ["GROUND", "AIR", "NAVAL", "LAND", "SUPPLY", "REPORT"] or not _priority(task.get("priority")) or not task.get("required") is bool or not task.get("after", []) is Array:
			return _reject("bounded_task_identity_domain_priority_required")
		for dependency: Variant in task.get("after", []):
			if not dependency is String or not seen.has(dependency):
				return _reject("dependencies_must_reference_earlier_tasks")
		if task.domain == "GROUND":
			var unit: String = str(task.get("unit_ref", ""))
			if not s._unit_nodes.has(unit) or not s._contains(target, str(s._unit_nodes[unit])) or not task.get("goal") is Dictionary or task.goal.get("intent", "") not in ["hold", "advance", "withdraw"] or not g._known[actor].has(task.goal.get("target_node", "")) or not task.goal.get("path") is Array or not g._known[actor][task.goal.target_node].has(task.goal.path):
				return _reject("actual_subordinate_and_known_goal_required")
			if not task.get("survey_edges", []) is Array or task.get("survey_edges", []).size() > 4 or not task.get("require_route_reports", []) is Array or task.get("require_route_reports", []).size() > 4:
				return _reject("bounded_route_survey_required")
			for edge: Variant in task.get("survey_edges", []) + task.get("require_route_reports", []):
				if not edge is String or edge not in task.goal.path:
					return _reject("survey_only_declared_known_task_segments")
			if task.has("survey_unit") and not s._contains(target, str(s._unit_nodes.get(task.survey_unit, ""))):
				return _reject("survey_requires_owned_subject_identity")
			if task.has("relay_deployment") or task.has("engineering"):
				var specialized: Dictionary = _validate_ground_work(actor, task)
				if not specialized.ok:
					return specialized
			if task.has("fire_support"):
				var support: Variant = task.fire_support
				if task.has("engineering") or task.has("relay_deployment") or not support is Dictionary or not g.tactics.guns.has(support.get("gun_ref", "")) or g.tactics.guns[support.gun_ref].unit_ref != unit or not g._known[actor].has(support.get("target_node", "")) or not _number(support.get("missions", 1)) or int(support.get("missions", 1)) < 1 or int(support.get("missions", 1)) > 8:
					return _reject("existing_owned_gun_and_known_finite_fire_support_target_required")
		else:
			if task.domain == "LAND":
				if not task.get("require_route_reports", []) is Array or task.get("require_route_reports", []).size() > 4:
					return _reject("bounded_required_land_route_reports")
				for edge: Variant in task.get("require_route_reports", []):
					var known: bool = false
					for paths: Array in g._known.get(actor, {}).values():
						for path: Array in paths:
							known = known or edge in path
					if not edge is String or not known:
						return _reject("required_land_survey_segment_not_known")
			if task.has("recovery_carriers") and (task.domain != "LAND" or not task.recovery_carriers is Array or task.recovery_carriers.size() > MAX_TASKS):
				return _reject("bounded_declared_ground_recovery_candidates_required")
			for carrier: Variant in task.get("recovery_carriers", []):
				if not carrier is String or not g.land.carriers.has(carrier) or not s._contains(target, str(s._unit_nodes.get(carrier, ""))):
					return _reject("existing_owned_recovery_carrier_required")
			if not task.get("intent") is Dictionary or task.intent.get("kind", "") not in ["command", "logistics_request"]:
				return _reject("existing_support_input_required")
			var expected: Dictionary = {"AIR": "air_intent", "NAVAL": "naval_intent", "LAND": "land_intent", "REPORT": "operation_intent"}
			if task.domain == "SUPPLY":
				if task.intent.kind != "logistics_request" or not s._contains(target, str(task.intent.get("target", ""))):
					return _reject("supply_request_in_current_scope_required")
			elif task.intent.kind != "command" or task.intent.get("command_kind", "") != expected[task.domain] or task.intent.get("target", "") != position.formation_id or not task.intent.get("values") is Dictionary:
				return _reject("support_uses_existing_owned_domain_command")
			if task.domain == "REPORT" and (task.intent.values.get("operation", "") != "request_report" or not validate(actor, target, task.intent.values, id).ok):
				return _reject("report_task_uses_owned_status_request_only")
			if task.has("transport_ref") and task.domain in ["LAND", "NAVAL"]:
				var continuation: Dictionary = _validate_continuation(actor, target, task)
				if not continuation.ok:
					return continuation
		seen[task.task_ref] = true
		necessary = necessary or task.required
	return {"ok": true} if necessary else _reject("at_least_one_necessary_task_required")

func apply(actor: String, target: String, values: Dictionary, id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var info: RefCounted = g._state.information_port.get_ref()
	if info._gate != "delivery" or info._actor != actor:
		return _reject("delivered_purpose_command_required")
	if values.operation == "reduce_supply_request":
		var l: RefCounted = g._state.logistics_port.get_ref()
		var result: Dictionary = l.reduce_uncommitted(actor, str(values.request_ref), values.quantity, true)
		if result.ok:
			info.report_supply_request(g._state.decision_port.get_ref(), actor, str(values.request_ref), l._requests[values.request_ref])
		return result
	if values.operation == "request_report":
		if values.subject_kind == "unit":
			on_unit(str(values.subject_ref), true)
			if g.land._unit_jobs.has(values.subject_ref) and float(g._state.units[values.subject_ref].effective) > 0.001:
				g.land._report(g.land.jobs[g.land._unit_jobs[values.subject_ref]], "REQUESTED_CURRENT_STATUS", true)
		else:
			g.sea.request_status(actor, str(values.subject_ref), id)
		# Delivery acknowledges the request, not the undisclosed condition of its source.
		return {"ok": true, "state_delta": {"report_request_ref": id}}
	if values.operation == "transfer_observer":
		_transfer_observer(str(values.source_unit), str(values.unit_ref))
		return {"ok": true, "state_delta": {"field_observer_unit": values.unit_ref}}
	if values.operation == "reassign":
		var existing: Dictionary = _records[values.operation_ref]
		var task: Dictionary = existing.tasks[values.task_ref]
		var old_resource: String = _resource(task)
		if _resources.get(old_resource, "") == task.id:
			_resources.erase(old_resource)
		task.previous_executor = task.executor
		task.previous_unit = task.unit_ref
		task.unit_ref = values.unit_ref
		task.goal = values.goal.duplicate(true)
		task.assignment_revision = int(task.get("assignment_revision", 0)) + 1
		task.executor = _executor(actor, target, task)
		for key: String in ["executed_at", "payload_ref", "executed_intent", "cancel_requested", "followup_status"]:
			task.erase(key)
		task.command_ref = ""
		task.mission_ref = ""
		task.phase = "ASSIGN"
		existing.status = "ACTIVE"
		_set_task(existing, task, "QUEUED", "same_task_reassigned_after_received_failure")
		_dispatch(existing)
		_publish_status(existing)
		return {"ok": true, "state_delta": {"operation_ref": existing.id, "task_ref": task.task_ref, "unit_ref": task.unit_ref}}
	if values.operation != "begin":
		var existing: Dictionary = _records[values.operation_ref]
		if values.operation == "cancel":
			existing.status = "CANCELLED"
			for task: Dictionary in existing.tasks.values():
				if task.status not in TERMINAL:
					_cancel(existing, task, "purpose_cancel_requested")
		else:
			existing.priority = int(values.priority)
			for task: Dictionary in existing.tasks.values():
				_publish_task(existing, task)
		_publish_status(existing)
		return {"ok": true, "state_delta": {"operation_ref": existing.id, "status": existing.status}}
	var record: Dictionary = {"id": id, "issuer": actor, "scope": target, "purpose": values.purpose, "target_node": values.target_node,
		"priority": int(values.priority), "started_at": g._state.time, "deadline": g._state.time + float(values.deadline_seconds), "status": "ACTIVE", "tasks": {}}
	record.predecessor_ref = str(values.get("predecessor_ref", ""))
	record.supports_operation_ref = str(values.get("supports_operation_ref", ""))
	_records[id] = record
	for specification: Dictionary in values.tasks:
		var task: Dictionary = specification.duplicate(true)
		if record.purpose == "route_security" and task.domain == "GROUND" and not task.has("survey_edges"):
			task.survey_edges = task.goal.path.slice(0, 4)
		task.id = id + ":" + str(task.task_ref)
		task.status = "QUEUED"
		task.executor = _executor(actor, target, task)
		task.command_ref = ""
		task.mission_ref = ""
		task.phase = "ASSIGN"
		task.reason = ""
		if task.has("transport_ref") and task.domain in ["LAND", "NAVAL"]:
			if task.domain == "LAND":
				task.actual_carrier_ref = g.land.jobs[task.transport_ref].unit_ref
			_release_previous_transport(task)
		record.tasks[task.task_ref] = task
	_dispatch(record)
	_publish_status(record)
	_prune()
	return {"ok": true, "state_delta": {"operation_ref": id, "status": record.status}}

func _validate_ground_work(actor: String, task: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var unit: String = str(task.unit_ref)
	if task.has("engineering") and task.has("relay_deployment") or g.land._unit_jobs.has(unit) or g.air.recovery._unit_jobs.has(unit) or g.tactics.occupied(unit):
		return _reject("one_ground_work_and_free_actual_unit_required")
	if task.has("relay_deployment"):
		if not task.relay_deployment is Dictionary:
			return _reject("explicit_relay_deployment_required")
		var relay: Dictionary = task.relay_deployment
		var platform: String = str(relay.get("platform_ref", ""))
		if _field_sources.get(unit, "") != platform or relay.get("recipient_ref", "") != actor:
			return _reject("existing_owned_relay_platform_and_requesting_recipient_required")
		var source: String = str(relay.get("source_ref", ""))
		var learned: bool = false
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).get("entries", []):
			learned = learned or claim.source_ref == source and float(claim.reliability) > 0.0
		if not learned or not g._state.information_port.get_ref().relay_deployment(self, platform, source, actor, str(relay.get("channel_ref", "report"))).get("supported", false):
			return _reject("received_source_and_configured_physical_relay_required")
	else:
		if not task.engineering is Dictionary:
			return _reject("explicit_engineering_action_required")
		var engineering: Dictionary = task.engineering
		if engineering.get("action", "") == "build":
			var kind: String = str(engineering.get("position_kind", ""))
			var node: String = str(task.goal.target_node)
			var point: Variant = engineering.get("xy", g._space._nodes[node].xy)
			if not engineers.has(unit) or not engineers[unit].get("positions", {}).has(kind) or kind not in g._space._position_sites.get(node, []) or not engineering.get("position_ref") is String or str(engineering.position_ref).is_empty() or not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) or g._space._distance(point, g._space._nodes[node].xy) > 0.02:
				return _reject("declared_engineer_known_buildable_site_and_finite_position_required")
			var existing: Dictionary = g._space._positions.get(engineering.position_ref, {})
			if not existing.is_empty() and (existing.node_ref != node or existing.kind != kind or existing.xy != point):
				return _reject("existing_position_identity_and_location_must_be_preserved")
			if existing.is_empty() and (g._space._positions.size() >= 16 or kind == "personal" and g.participants._covers.size() >= 16):
				return _reject("finite_position_capacity")
			return {"ok": true}
		var edge: String = str(engineering.get("edge_ref", ""))
		var action: String = str(engineering.get("action", ""))
		var facility: Dictionary = g._space._edges.get(edge, {}).get("engineering", {})
		if not engineers.has(unit) or action not in ["clear", "repair"] or action not in facility.get("actions", []) or task.goal.target_node not in facility.get("work_nodes", []):
			return _reject("declared_engineer_repairable_existing_edge_and_work_site_required")
		var learned: bool = false
		for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor, "route", edge, "route_observation").get("entries", []):
			learned = learned or float(claim.reliability) > 0.0 and claim.claimed_value.get("state", "") == "BLOCKED" and claim.claimed_value.get("obstruction", "") == ("debris" if action == "clear" else "limited_damage")
		if not learned:
			return _reject("received_local_obstruction_report_required")
	return {"ok": true}

func _ground_work(unit_id: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if not g._state.units.has(unit_id):
		return
	var unit: Dictionary = g._state.units[unit_id]
	if _work_units.has(unit_id):
		var work: Dictionary = _work_units[unit_id]
		if work.mission_ref != unit.mission_id or not _work_condition(unit, work):
			_finish_work(unit_id, "INTERRUPTED", "actual_crew_equipment_site_or_mission_changed")
		return
	for record: Dictionary in _records.values():
		for task: Dictionary in record.tasks.values():
			if task.domain != "GROUND" or task.get("unit_ref", "") != unit_id or not (task.has("engineering") or task.has("relay_deployment")) or task.get("work_started", false) or task.status in TERMINAL:
				continue
			var mission: String = "goal_" + str(task.get("payload_ref", "")) + "_" + unit_id
			if mission != unit.mission_id or str(unit.spatial.edge) != "" or unit.spatial.node != task.goal.target_node or not unit.spatial.path.is_empty():
				continue
			task.work_started = true
			var work: Dictionary = {"task_id": task.id, "operation_ref": record.id, "task_ref": task.task_ref, "mission_ref": mission,
				"node_ref": unit.spatial.node, "status": "WORKING", "started_at": g._state.time, "actual_seconds": 0.0, "elapsed_seconds": 0.0, "spares_spent": 0.0}
			if task.has("relay_deployment"):
				work.kind = "RELAY"
				work.relay = task.relay_deployment.duplicate(true)
				_work_units[unit_id] = work
				var link: Dictionary = g._state.information_port.get_ref().relay_deployment(self, str(work.relay.platform_ref), str(work.relay.source_ref), str(work.relay.recipient_ref), str(work.relay.get("channel_ref", "report")))
				_finish_work(unit_id, "COMPLETE" if link.get("ready", false) else "BLOCKED", "actual_relay_links_available" if link.get("ready", false) else "deployed_position_does_not_bridge_links")
			else:
				if task.engineering.get("action", "") == "build":
					work.kind = "POSITION"
					work.position_ref = task.engineering.position_ref
					work.position_kind = task.engineering.position_kind
					var profile: Dictionary = engineers[unit_id].positions[work.position_kind]
					work.seconds = float(profile.seconds)
					work.spares = float(profile.spares)
					work.action = "build"
					_work_units[unit_id] = work
					if not g._space.prepare_position(self, str(work.position_ref), str(work.node_ref), str(work.position_kind), task.engineering.get("xy", g._space._nodes[work.node_ref].xy)) or not _work_condition(unit, work):
						_finish_work(unit_id, "BLOCKED", "construction_site_or_actual_crew_unavailable")
					else:
						work.seconds *= maxf(0.000001, 1.0 - float(g._space._positions[work.position_ref].progress))
						work.spares *= maxf(0.0, 1.0 - float(g._space._positions[work.position_ref].progress))
						work.full_seconds = float(profile.seconds)
						_schedule_work(unit_id)
					return
				work.kind = "ENGINEERING"
				work.edge_ref = task.engineering.edge_ref
				work.action = task.engineering.action
				work.edge_revision = g._space._edges[work.edge_ref].get("last_fact_id", "")
				work.seconds = float(engineers[unit_id][str(work.action) + "_seconds"])
				work.spares = float(engineers[unit_id][str(work.action) + "_spares"])
				_work_units[unit_id] = work
				if not _work_condition(unit, work) or float(unit.get("spares", 0.0)) < float(work.spares):
					_finish_work(unit_id, "BLOCKED", "actual_engineering_resources_or_conditions_unavailable")
				else:
					_schedule_work(unit_id)
			return

func _work_condition(unit: Dictionary, work: Dictionary) -> bool:
	var g: RefCounted = _owner.get_ref()
	if str(unit.spatial.edge) != "" or unit.spatial.node != work.node_ref or not unit.spatial.path.is_empty() or float(unit.effective) < 1.0 or g._state.missions[unit.mission_id].status in ["failed", "cancelled"]:
		return false
	if work.kind not in ["ENGINEERING", "POSITION"]:
		return true
	var cap: Dictionary = engineers[unit.id]
	if work.kind == "POSITION":
		return unit.action not in ["withdrawn", "disabled"] and minf(float(unit.effective), float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))) >= float(cap.minimum_crew) and float(unit.get("serviceable_equipment", unit.equipment)) >= float(cap.minimum_equipment) and float(unit.suppression) < 0.5 and not g._state.missions[unit.mission_id].get("goal_v1", {}).get("effective_incoming_contact", false) and not g._state.coordination.get(unit.id, {}).get("retained", false)
	var edge: Dictionary = g._space._edges[work.edge_ref]
	return unit.action not in ["withdrawn", "disabled"] and minf(float(unit.effective), float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))) >= float(cap.minimum_crew) and float(unit.get("serviceable_equipment", unit.equipment)) >= float(cap.minimum_equipment) and float(unit.get("suppression", 0.0)) < 0.5 and not g._state.missions[unit.mission_id].get("goal_v1", {}).get("effective_incoming_contact", false) and not edge.open and edge.get("obstruction", "") == ("debris" if work.action == "clear" else "limited_damage") and edge.get("last_fact_id", "") == work.edge_revision and not g._state.coordination.get(unit.id, {}).get("retained", false)

func _schedule_work(unit_id: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var work: Dictionary = _work_units[unit_id]
	var seconds: float = minf(60.0, float(work.seconds) - float(work.elapsed_seconds))
	var cost: float = float(work.spares) * seconds / float(work.seconds)
	var unit: Dictionary = g._state.units[unit_id]
	if float(unit.spares) + 0.000001 < cost:
		_finish_work(unit_id, "INTERRUPTED", "engineering_materials_exhausted")
		return
	unit.spares -= cost
	unit.spares_spent += cost
	g._state.logistics_ledger.spares_spent += cost
	work.spares_spent += cost
	_serial += 1
	var id: String = "operation_work_%d" % _serial
	work.ticket_ref = id
	work.chunk_started_at = g._state.time
	_work_tickets[id] = {"unit_ref": unit_id, "task_id": work.task_id, "seconds": seconds, "due": g._state.time + seconds}
	assert(g._state.schedule_event(id, g._state.time + seconds, "gameplay", {"operation_work": id}))

func accepts_work(id: String, payload: Dictionary, due: float) -> bool:
	return payload.size() == 1 and payload.get("operation_work", "") == id and _work_tickets.has(id) and _work_tickets[id].due == due

func process_work(event: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var ticket: Dictionary = _work_tickets[event.id]
	_work_tickets.erase(event.id)
	var unit: String = str(ticket.unit_ref)
	if not _work_units.has(unit) or _work_units[unit].get("ticket_ref", "") != event.id:
		return {"changed": [], "retired": [], "record": {"status": "OBSOLETE"}}
	var work: Dictionary = _work_units[unit]
	if not g._state.units.has(unit):
		_finish_work(unit, "INTERRUPTED", "engineering_unit_no_longer_exists")
		return {"changed": [], "retired": [], "record": {"status": "ENGINEERING_UNIT_REMOVED"}}
	if not _work_condition(g._state.units[unit], work):
		_finish_work(unit, "INTERRUPTED", "engineering_conditions_changed")
	else:
		work.elapsed_seconds += float(ticket.seconds)
		work.actual_seconds += float(ticket.seconds)
		work.chunk_started_at = g._state.time
		if work.kind == "POSITION":
			if not g._space.construct_position(self, str(work.position_ref), float(ticket.seconds), float(work.full_seconds), str(event.id)):
				_finish_work(unit, "INTERRUPTED", "position_work_not_applied")
			elif float(work.elapsed_seconds) + 0.000001 >= float(work.seconds):
				_finish_work(unit, "COMPLETE", "actual_position_constructed")
			else:
				_schedule_work(unit)
		elif float(work.elapsed_seconds) + 0.000001 >= float(work.seconds):
			g._space.finish_engineering(self, str(work.edge_ref), str(work.edge_revision), str(work.task_id))
		else:
			_schedule_work(unit)
	on_unit(unit, true)
	return {"changed": [unit], "retired": [], "record": {"status": "ENGINEERING_BOUNDARY", "unit_ref": unit}}

func permits_position(position: String, reference: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	for unit: String in _work_units:
		var work: Dictionary = _work_units[unit]
		if work.kind == "POSITION" and work.position_ref == position and work.ticket_ref == reference and g._state.units.has(unit) and _work_condition(g._state.units[unit], work):
			return true
	return false

func permits_engineering(edge: String, reference: String) -> bool:
	var g: RefCounted = _owner.get_ref()
	for unit: String in _work_units:
		var work: Dictionary = _work_units[unit]
		if work.kind == "ENGINEERING" and work.task_id == reference and work.edge_ref == edge and float(work.elapsed_seconds) >= float(work.seconds) and g._state.units.has(unit) and _work_condition(g._state.units[unit], work):
			return true
	return false

func engineering_applied(reference: String, applied: bool) -> void:
	for unit: String in _work_units.keys():
		if _work_units[unit].task_id == reference:
			if applied and _field_sources.has(unit):
				var g: RefCounted = _owner.get_ref()
				var work: Dictionary = _work_units[unit]
				_serial += 1
				var claim: Dictionary = {"id": "engineering_route_%d" % _serial, "source_ref": _field_sources[unit], "subject_kind": "route", "subject_ref": work.edge_ref,
					"fact_kind": "route_observation", "value": {"edge_ref": work.edge_ref, "node_ref": work.node_ref, "state": "PASSABLE", "coverage": "REPAIRED_LOCAL_FACILITY", "engineering_task_ref": reference},
					"observed_at": g._state.time, "observer_ref": unit, "origin": "ON_SITE_ENGINEERING", "quality": 1.0, "precision": "facility_open_only"}
				var task: Dictionary = _records[work.operation_ref].tasks[work.task_ref]
				var readers: Array[String] = [str(task.executor)]
				var commander: String = _current_owner(_records[work.operation_ref])
				if commander != "" and commander not in readers:
					readers.append(commander)
				for reader: String in readers:
					g._state.information_port.get_ref().send_platform_report(self, str(_field_sources[unit]), reader, "engineering_route_%d_%s" % [_serial, reader], [claim])
			_finish_work(unit, "COMPLETE" if applied else "INTERRUPTED", "facility_opened" if applied else "newer_facility_fact_preserved")
			on_unit(unit, true)
			return

func _finish_work(unit: String, status: String, reason: String) -> void:
	var work: Dictionary = _work_units[unit]
	work.actual_seconds += maxf(0.0, _owner.get_ref()._state.time - float(work.get("chunk_started_at", work.started_at)))
	work.status = status
	work.reason = reason
	_work_results[unit] = work.duplicate(true)
	_work_units.erase(unit)

func _validate_continuation(actor: String, scope: String, task: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var reference: String = str(task.transport_ref)
	var learned: bool = false
	var reports: Array = g.land.known_view(actor) if task.domain == "LAND" else g.sea.freight.known_view(actor)
	for report: Dictionary in reports:
		if report.get("transport_ref", "") == reference and report.get("status", "") not in ["RECEIVED", "LOST", "CARGO_LOST", "VESSEL_SUNK", "RETURNED_TO_SOURCE", "CANCELLED_BEFORE_LOADING"]:
			learned = true
	if not learned:
		return _reject("received_unfinished_transport_report_required")
	if task.domain == "LAND":
		if not g.land.jobs.has(reference) or g.land.jobs[reference].payload_kind != "CARGO" or not g._state.structure_port.get_ref()._contains(scope, str(g._state.structure_port.get_ref()._unit_nodes.get(g.land.jobs[reference].unit_ref, ""))):
			return _reject("unfinished_cargo_carrier_in_current_scope_required")
		if task.intent.values.get("transport_ref", "") != reference or task.intent.values.get("operation", "") not in ["continue_transport", "resume_transport", "redirect_transport", "stop_transport", "unload", "recover_cargo"]:
			return _reject("existing_land_transport_command_required")
	else:
		var vessel: String = str(task.intent.values.get("vessel_ref", ""))
		if not g.sea.vessels.has(vessel) or not g.sea._authorized(actor, g.sea.vessels[vessel]) or g.sea.vessels[vessel].cargo_ref != reference:
			return _reject("current_authorized_onboard_carrier_required")
	var key: String = "unit:" + str(g.land.jobs[reference].unit_ref) if task.domain == "LAND" else _resource(task)
	if _resources.has(key):
		for record: Dictionary in _records.values():
			for previous: Dictionary in record.tasks.values():
				if previous.id != _resources[key]:
					continue
				if record.status not in TERMINAL:
					return _reject("transport_still_assigned_to_active_purpose")
				for pending: Dictionary in _commands.values():
					if pending.operation_ref == record.id and pending.task_ref == previous.task_ref:
						return _reject("earlier_transport_command_still_in_transit")
	return {"ok": true}

func _release_previous_transport(task: Dictionary) -> void:
	var key: String = _resource(task)
	for record: Dictionary in _records.values():
		if record.status not in TERMINAL:
			continue
		for previous: Dictionary in record.tasks.values():
			if previous.domain != task.domain or _resource(previous) != key or previous.get("transport_ref", previous.get("payload_ref", "")) != task.transport_ref:
				continue
			task.predecessor_task_ref = previous.id
			task.assignment_revision = int(previous.get("assignment_revision", 0)) + 1
			_set_task(record, previous, "CANCELLED", "physical_responsibility_continued_by_" + str(task.id))

func _validate_reassignment(actor: String, scope: String, values: Dictionary) -> Dictionary:
	var reference: String = str(values.get("operation_ref", ""))
	var selected: String = str(values.get("task_ref", ""))
	var g: RefCounted = _owner.get_ref()
	if not _records.has(reference) or _records[reference].scope != scope or _records[reference].status == "CANCELLED" or g._state.time >= float(_records[reference].deadline) or not _records[reference].tasks.has(selected):
		return _reject("owned_unexpired_task_required")
	var task: Dictionary = _records[reference].tasks[selected]
	if task.domain != "GROUND" or task.status not in ["FAILED", "CANCELLED", "QUEUED", "WAITING_RESOURCE", "ASSIGNED"] or not str(task.command_ref).is_empty() and task.status == "ASSIGNED":
		return _reject("unfinished_physical_order_must_finish_before_reassignment")
	for dependency: String in task.get("after", []):
		if _records[reference].tasks[dependency].status != "COMPLETE":
			return _reject("replacement_keeps_original_task_dependencies")
	for pending: Dictionary in _commands.values():
		if pending.operation_ref == reference and pending.task_ref == selected:
			return _reject("previous_task_command_still_in_transit")
	var informed: bool = false
	for known: Dictionary in known_view(actor):
		if known.get("operation_ref", "") == reference and known.get("task_ref", "") == selected and known.status == task.status and int(known.get("assignment_revision", 0)) == int(task.get("assignment_revision", 0)):
			informed = true
	if not informed:
		return _reject("delivered_current_task_feedback_required")
	var s: RefCounted = g._state.structure_port.get_ref()
	var unit: String = str(values.get("unit_ref", ""))
	if unit == task.unit_ref or not s.active(str(s._unit_nodes.get(unit, ""))) or not s._contains(scope, str(s._unit_nodes[unit])) or not g._state.units.has(unit) or not values.get("goal") is Dictionary:
		return _reject("different_actual_subordinate_and_known_goal_required")
	if _resources.has("unit:" + unit) or g.land._unit_jobs.has(unit) or g.air.recovery._unit_jobs.has(unit):
		return _reject("replacement_unit_already_assigned")
	var current: Dictionary = g._state.units[unit]
	if float(current.effective) <= 0.001 or not str(current.get("spatial", {}).get("edge", "")).is_empty():
		return _reject("replacement_unit_cannot_take_task_now")
	return g.validate_goal(actor, current, values.goal)

func _transfer_observer(source: String, destination: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var spare: bool = not _field_spares.get(source, []).is_empty()
	var platform: String = str(_field_spares[source].back()) if spare else str(_field_sources[source])
	if not g._state.information_port.get_ref().transfer_field_source(self, platform, str(g._state.structure_port.get_ref()._unit_nodes[destination])):
		return
	if spare:
		_field_spares[source].pop_back()
	else:
		_field_sources.erase(source)
	_field_sources[destination] = platform
	_field_last.erase(source)
	_field_readers.erase(source)
	_field_last.erase(destination)
	_field_readers.erase(destination)
	on_unit(destination)
	if spare:
		on_unit(source)

func _merge_observers(source: String, destination: String) -> void:
	var g: RefCounted = _owner.get_ref()
	var sources: Array = _field_spares.get(source, []).duplicate()
	if _field_sources.has(source):
		sources.append(_field_sources[source])
	for platform: String in sources:
		g._state.information_port.get_ref().transfer_field_source(self, platform, str(g._state.structure_port.get_ref()._unit_nodes[destination]))
		if not _field_sources.has(destination):
			_field_sources[destination] = platform
		else:
			if not _field_spares.has(destination):
				_field_spares[destination] = []
			_field_spares[destination].append(platform)
	_field_sources.erase(source)
	_field_spares.erase(source)
	_field_last.erase(source)
	_field_readers.erase(source)
	on_unit(destination)

func _executor(actor: String, scope: String, task: Dictionary) -> String:
	if task.domain != "GROUND" or task.get("retain_before_execution", false):
		return actor
	var s: RefCounted = _owner.get_ref()._state.structure_port.get_ref()
	var cursor: String = str(s._unit_nodes[task.unit_ref])
	var selected: String = actor
	while not cursor.is_empty():
		if cursor == scope:
			break
		var holder: String = str(s._positions.get(cursor, {}).get("person", ""))
		if not holder.is_empty():
			selected = holder
		cursor = s.parent(cursor)
	return selected

func _resource(task: Dictionary) -> String:
	if task.domain == "GROUND":
		return "unit:" + str(task.unit_ref)
	var values: Dictionary = task.get("intent", {}).get("values", {})
	if task.domain == "REPORT":
		return "report:" + str(values.subject_kind) + ":" + str(values.subject_ref)
	if task.domain == "LAND":
		return "unit:" + str(task.get("actual_carrier_ref", values.get("unit_ref", "")))
	if task.domain == "AIR":
		return "air:" + str(values.get("asset_ref", ""))
	if task.domain == "NAVAL":
		return "vessel:" + str(values.get("vessel_ref", ""))
	return ""

func permits_carrier_recovery(unit: String, command: String) -> bool:
	var key: String = "unit:" + unit
	if not _resources.has(key):
		return true
	if not _commands.has(command):
		return false
	var binding: Dictionary = _commands[command]
	return _records[binding.operation_ref].tasks[binding.task_ref].id == _resources[key] and binding.phase == "RECOVER"

func permits_ground_fire(unit: String, actor: String) -> bool:
	var reference: String = str(_resources.get("unit:" + unit, ""))
	if reference == "":
		return true
	for record: Dictionary in _records.values():
		for task: Dictionary in record.tasks.values():
			if task.id == reference:
				return task.executor == actor and task.status not in TERMINAL
	return false

func _second_resource(task: Dictionary) -> String:
	var values: Dictionary = task.get("intent", {}).get("values", {})
	if task.domain != "NAVAL":
		return ""
	var receiver: String = str(values.get("recipient_vessel_ref", task.get("transfer_receiver_ref", task.get("meeting_partner_ref", ""))))
	return "vessel:" + receiver if receiver != "" else ""

func permits_vessel_transfer(source: String, receiver: String, command: String) -> bool:
	var occupied: String = str(_resources.get("vessel:" + receiver, ""))
	if occupied == "" or occupied == _resources.get("vessel:" + source, "__unassigned"):
		return true
	if not _commands.has(command):
		return false
	var binding: Dictionary = _commands[command]
	return _records[binding.operation_ref].tasks[binding.task_ref].id == occupied and binding.phase == "TRANSFER"

func permits_vessel_navigation(vessel: String, command: String, actor: String) -> bool:
	var occupied: String = str(_resources.get("vessel:" + vessel, ""))
	if occupied == "":
		return true
	if _commands.has(command):
		var binding: Dictionary = _commands[command]
		return _records[binding.operation_ref].tasks[binding.task_ref].id == occupied
	# Preflight precedes on_decision's message binding. The existing executor
	# may redirect its own assignment; a different assignment stays occupied.
	for record: Dictionary in _records.values():
		for task: Dictionary in record.tasks.values():
			if task.id == occupied:
				return task.executor == actor and task.status not in TERMINAL
	return false

func _dispatch(record: Dictionary) -> void:
	if record.status in TERMINAL and record.status != "COMPLETE":
		return
	var candidates: Array = record.tasks.values()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) > int(b.priority) if a.priority != b.priority else str(a.task_ref) < str(b.task_ref))
	for task: Dictionary in candidates:
		if task.status not in ["QUEUED", "WAITING_RESOURCE"]:
			continue
		var ready: bool = true
		for dependency: String in task.get("after", []):
			var status: String = str(record.tasks[dependency].status)
			if status in ["FAILED", "CANCELLED"]:
				_set_task(record, task, "FAILED", "necessary_task_unavailable")
				ready = false
				break
			ready = ready and status == "COMPLETE"
		if not ready:
			continue
		var key: String = _resource(task)
		var second: String = _second_resource(task)
		if second != "" and _resources.has(second) and _resources[second] != task.id:
			_set_task(record, task, "WAITING_RESOURCE", "receiving_vessel_assigned_to_another_task")
			continue
		if not key.is_empty() and _higher_waiting(record, task, key):
			_set_task(record, task, "WAITING_RESOURCE", "higher_priority_waiting_task")
			continue
		if not key.is_empty() and _resources.has(key) and _resources[key] != task.id:
			if task.status != "WAITING_RESOURCE":
				_set_task(record, task, "WAITING_RESOURCE", "resource_assigned_to_another_task")
			continue
		if not key.is_empty():
			_resources[key] = task.id
		if task.domain == "GROUND" and (task.has("engineering") or task.has("relay_deployment")):
			_special_units[task.unit_ref] = task.id
		if second != "":
			_resources[second] = task.id
		_set_task(record, task, "ASSIGNED", "awaiting_subordinate_received_intent")

func _higher_waiting(record: Dictionary, task: Dictionary, resource: String) -> bool:
	var score: int = int(record.priority) * 10 + int(task.priority)
	for other: Dictionary in _records.values():
		if other.status in ["FAILED", "CANCELLED"]:
			continue
		for candidate: Dictionary in other.tasks.values():
			if candidate.id == task.id or candidate.status not in ["QUEUED", "WAITING_RESOURCE"] or _resource(candidate) != resource:
				continue
			var eligible: bool = true
			for dependency: String in candidate.get("after", []):
				eligible = eligible and other.tasks[dependency].status == "COMPLETE"
			var priority: int = int(other.priority) * 10 + int(candidate.priority)
			if eligible and (priority > score or priority == score and float(other.deadline) < float(record.deadline)):
				return true
	return false

func on_decision(person: String, proposal: Dictionary, validation: Dictionary, issued: Dictionary) -> void:
	if not _active:
		return
	var reference: String = str(proposal.get("operation_ref", ""))
	var selected: String = str(proposal.get("task_ref", ""))
	if _records.has(reference) and _records[reference].tasks.has(selected):
		var record: Dictionary = _records[reference]
		var task: Dictionary = record.tasks[selected]
		if task.executor == person and int(proposal.get("assignment_revision", 0)) == int(task.get("assignment_revision", 0)) and (task.status not in TERMINAL or proposal.get("task_phase", "") == "FOLLOW"):
			if validation.get("ok", false) and issued.get("result", {}).get("ok", false):
				task.command_ref = str(issued.id)
				task.command_issued_at = _owner.get_ref()._state.time
				task.phase = str(proposal.get("task_phase", "EXECUTE"))
				if task.phase in ["FIRE_EXECUTE", "FIRE_RESUME"]:
					task.fire_command_ref = str(issued.id)
				if task.phase == "MEET":
					task.meeting_ref = proposal.intent.values.rendezvous_ref
					task.meeting_partner_ref = proposal.intent.values.partner_ref
					task.meeting_node_ref = proposal.intent.values.target_node
					task.meeting_routes = proposal.meeting_routes.duplicate(true)
					_resources[_second_resource(task)] = task.id
				if task.phase == "TRANSFER":
					task.transfer_receiver_ref = proposal.intent.values.recipient_vessel_ref
					_resources[_second_resource(task)] = task.id
				if task.phase == "RECOVER":
					task.pending_carrier_ref = str(proposal.intent.values.unit_ref)
					_resources["unit:" + str(task.pending_carrier_ref)] = task.id
				if task.phase == "EXECUTE" or task.domain == "NAVAL" and task.phase == "REROUTE":
					task.payload_ref = str(issued.id)
					task.executed_intent = proposal.intent.duplicate(true)
				if issued.domain == "COMMUNICATION":
					_commands[issued.id] = {"operation_ref": reference, "task_ref": selected, "phase": task.phase}
					if task.phase != "FOLLOW":
						_set_task(record, task, "COMMAND_PENDING", "normal_command_in_transit")
				else:
					task.request_ref = str(issued.id)
					task.executed_at = _owner.get_ref()._state.time
					_set_task(record, task, "EXECUTING", "existing_request_submitted")
			elif proposal.get("intent", {}).get("kind", "") != "keep":
				_set_task(record, task, "BLOCKED", str(validation.get("error", issued.get("result", {}).get("error", "input_not_admitted"))))
	# Only purposes involving this enrolled person are examined at its deadline.
	for record: Dictionary in _records.values():
		if record.status in TERMINAL and not _has_open_tasks(record):
			continue
		var involved: bool = record.issuer == person
		for task: Dictionary in record.tasks.values():
			involved = involved or task.executor == person
		if involved:
			_refresh(record)
	_dispatch_waiting()

func _on_message(message: Dictionary) -> void:
	if message.kind == "COMMAND" and message.status in ["EXECUTED", "REJECTED", "UNCONFIRMED"] and _commands.has(message.id):
		var binding: Dictionary = _commands[message.id]
		_commands.erase(message.id)
		var record: Dictionary = _records[binding.operation_ref]
		var task: Dictionary = record.tasks[binding.task_ref]
		if message.status == "EXECUTED":
			task.executed_at = message.processed_at
		if binding.get("phase", "") == "FOLLOW":
			task.followup_status = message.status
			_publish_task(record, task)
			return
		if task.status in TERMINAL:
			return
		if message.status == "UNCONFIRMED":
			if task.get("progress_confirmed", false):
				task.command_receipt_status = "UNCONFIRMED"
				_publish_task(record, task)
				return
			_set_task(record, task, "AWAITING_CONFIRMATION", "command_receipt_overdue_not_confirmed_failure")
			return
		if record.status in TERMINAL and _cargo_task(task):
			_set_task(record, task, "CANCELLED", "purpose_ended_physical_responsibility_retained")
			return
		if message.status == "EXECUTED" and task.phase == "RECOVER":
			var previous: String = _resource(task)
			if _resources.get(previous, "") == task.id:
				_resources.erase(previous)
			task.actual_carrier_ref = task.pending_carrier_ref
			task.intent.values.unit_ref = task.actual_carrier_ref
			task.erase("pending_carrier_ref")
			_resources[_resource(task)] = task.id
		if message.status == "REJECTED":
			if task.phase == "RECOVER" and task.has("pending_carrier_ref"):
				var pending: String = "unit:" + str(task.pending_carrier_ref)
				if _resources.get(pending, "") == task.id:
					_resources.erase(pending)
				task.erase("pending_carrier_ref")
			_set_task(record, task, "CANCEL_PENDING" if task.get("cancel_requested", false) else "BLOCKED", str(message.outcome.reason))
		elif task.get("cancel_requested", false) and task.phase != "CANCEL":
			_set_task(record, task, "CANCEL_PENDING", "earlier_command_delivered_cancellation_still_required")
		elif task.phase == "CANCEL":
			_set_task(record, task, "CANCELLING" if task.domain == "AIR" else "CANCELLED", "existing_domain_cancel_executed")
		elif task.phase == "RETAIN":
			_set_task(record, task, "RETAINED", "actual_reserve_retained")
		elif task.phase == "PAUSE":
			_set_task(record, task, "PAUSED", "actual_hold_or_reserve_waiting_changed_information")
		elif task.phase == "SERVICE":
			task.executed_at = message.processed_at
			_set_task(record, task, "WAITING_SERVICE", "actual_domain_service_in_progress")
		elif task.phase == "RECOVER":
			_set_task(record, task, "BLOCKED", "same_loaded_cargo_recovered_waiting_known_route")
		elif task.phase == "FIRE_PACK_MOVE":
			_set_task(record, task, "ASSIGNED", "packing_command_received_waiting_actual_packed_report")
		else:
			task.executed_at = message.processed_at
			if task.domain == "GROUND" and task.phase != "REROUTE" and not str(task.phase).begins_with("FIRE_"):
				task.mission_ref = "goal_" + str(message.id) + "_" + str(task.unit_ref)
			_set_task(record, task, "EXECUTING", "normal_command_executed_waiting_observed_result")
		if message.status == "EXECUTED" and task.status in ["EXECUTING", "BLOCKED", "WAITING_SERVICE"]:
			for entry: Dictionary in _owner.get_ref()._state.information_port.get_ref().knowledge(str(task.executor)).get("entries", []):
				if float(entry.observed_at) >= float(task.executed_at) and float(entry.reliability) > 0.0:
					_observed(record, task, {"subject_ref": entry.subject_ref, "subject_kind": entry.subject_kind, "fact_kind": entry.fact_kind, "value": entry.claimed_value, "observed_at": entry.observed_at})
		return
	if message.kind != "REPORT" or message.status != "DELIVERED":
		return
	var person: String = str(message.recipient_ref)
	for claim: Dictionary in message.claims:
		if float(claim.quality) * float(message.get("received_quality", 1.0)) <= 0.0:
			continue
		if claim.fact_kind in ["operation_task", "operation_status"]:
			if not _known.has(person):
				_known[person] = {}
			var value: Dictionary = claim.value.duplicate(true)
			value.learned_at = message.received_at
			value.observed_at = claim.observed_at
			value.claim_ref = str(message.id)
			var key: String = str(value.operation_ref) + ":" + str(value.get("task_ref", "status"))
			var previous: Dictionary = _known[person].get(key, {})
			if float(previous.get("observed_at", -1.0)) > float(value.observed_at) or previous.get("observed_at", -1.0) == value.observed_at and int(previous.get("report_revision", 0)) > int(value.get("report_revision", 0)):
				continue
			_known[person][key] = value
			while _known[person].size() > MAX_OPERATIONS * (MAX_TASKS + 1):
				_known[person].erase(_known[person].keys()[0])
	for record: Dictionary in _records.values():
		if record.status in TERMINAL and not _has_open_tasks(record):
			continue
		for task: Dictionary in record.tasks.values():
			if task.executor == person and task.status in ["COMMAND_PENDING", "AWAITING_CONFIRMATION"]:
				for claim: Dictionary in message.claims:
					if float(claim.observed_at) < float(task.get("command_issued_at", INF)) or float(claim.quality) * float(message.get("received_quality", 1.0)) <= 0.0:
						continue
					var value: Dictionary = claim.value
					var confirms: bool = task.domain == "GROUND" and claim.subject_ref == task.unit_ref and value.get("mission_ref", "") == "goal_" + str(task.get("payload_ref", "")) + "_" + str(task.unit_ref)
					if task.domain == "GROUND" and str(task.phase).begins_with("FIRE_"):
						confirms = false
						for gun: Dictionary in value.get("tactical", {}).get("guns", []):
							confirms = confirms or claim.subject_ref == task.unit_ref and gun.get("fire_ref", "") == task.command_ref
					confirms = confirms or task.domain in ["LAND", "NAVAL"] and value.get("transport_ref", "__none") == task.get("transport_ref", task.get("payload_ref", "")) or task.domain in ["AIR", "NAVAL"] and value.get("mission_ref", "__none") == task.get("payload_ref", "")
					if task.domain == "NAVAL" and task.phase in ["MEET", "MEET_PARTNER"]:
						confirms = value.get("rendezvous_ref", "__none") == task.get("meeting_ref", "") and claim.subject_ref == (task.intent.values.vessel_ref if task.phase == "MEET" else task.get("meeting_partner_ref", ""))
					if task.domain == "NAVAL" and task.intent.values.get("operation", "") == "reassign_cargo" and task.phase == "EXECUTE":
						confirms = false
						for update: Dictionary in value.get("allocation_updates", []):
							confirms = confirms or update.id == task.get("payload_ref", "")
					if confirms or task.domain == "REPORT":
						task.executed_at = claim.observed_at
						task.progress_confirmed = true
						_set_task(record, task, "EXECUTING", "received_actual_progress_before_command_receipt")
			if task.executor != person or task.status not in ["EXECUTING", "BLOCKED", "PAUSED", "WAITING_SERVICE", "CANCEL_PENDING", "CANCELLING"] and not (task.domain == "REPORT" and task.status in ["ASSIGNED", "WAITING_RESOURCE", "QUEUED"]):
				continue
			for claim: Dictionary in message.claims:
				if float(claim.observed_at) < float(task.get("executed_at", record.started_at if task.domain == "REPORT" else INF)) or float(claim.quality) * float(message.get("received_quality", 1.0)) <= 0.0:
					continue
				_observed(record, task, claim)
		_refresh(record)
	_dispatch_waiting()

func _dispatch_waiting() -> void:
	# Resource release can wake a different purpose within this bounded catalogue.
	for record: Dictionary in _records.values():
		_dispatch(record)

func _observed(record: Dictionary, task: Dictionary, claim: Dictionary) -> void:
	var value: Dictionary = claim.value
	if task.domain == "REPORT":
		if claim.subject_ref == task.intent.values.subject_ref and claim.subject_kind == task.intent.values.subject_kind and claim.fact_kind in ["unit_state", "sea_status"]:
			_set_task(record, task, "COMPLETE", "new_source_report_actually_received")
		return
	if task.get("cancel_requested", false):
		if task.domain == "AIR" and claim.subject_ref == task.intent.values.asset_ref and value.get("asset_status", "") in ["LANDED", "READY", "DESTROYED", "AWAITING_RECOVERY"]:
			_set_task(record, task, "CANCELLED", "aircraft_no_longer_executing_cancelled_sortie")
		return
	if task.domain == "AIR" and task.phase == "SERVICE" and claim.fact_kind == "air_service" and claim.subject_ref == task.intent.values.asset_ref:
		if value.get("asset_status", "") == "READY" and value.get("service_ref", "") == "":
			_set_task(record, task, "ASSIGNED", "actual_service_report_received")
		elif value.get("status", "") in ["SERVICE_INTERRUPTED", "AIRCRAFT_DESTROYED"]:
			_set_task(record, task, "FAILED", str(value.status))
		return
	if task.domain == "GROUND" and claim.subject_ref == task.unit_ref and claim.fact_kind == "unit_condition" and value.get("condition", "") == "INCAPACITATED":
		_set_task(record, task, "FAILED", "received_local_observation_of_subordinate_incapacity")
		return
	if task.domain == "GROUND" and claim.fact_kind in ["objective", "unit_state"] and claim.subject_ref == task.unit_ref and value.get("mission_ref", "") == task.mission_ref:
		if task.has("fire_support"):
			for gun: Dictionary in value.get("tactical", {}).get("guns", []):
				if gun.id != task.fire_support.gun_ref:
					continue
				if gun.get("last_fire", {}).get("command_ref", "__none") == task.get("fire_command_ref", "") and int(gun.get("remaining", 1)) <= 0:
					_set_task(record, task, "COMPLETE", "received_actual_finite_gun_mission_completion")
					return
				elif gun.state == "INTERRUPTED" and gun.get("fire_ref", "__none") == task.get("fire_command_ref", ""):
					_set_task(record, task, "FAILED", "received_gun_crew_action_interrupted")
			if value.get("reason", "") == "route_blocked":
				_set_task(record, task, "BLOCKED", "gun_approach_route_blocked")
			return
		if task.has("engineering") or task.has("relay_deployment"):
			var work: Dictionary = value.get("ground_work", {})
			if work.get("task_id", "") == task.id and work.get("status", "") in ["COMPLETE", "BLOCKED", "INTERRUPTED"]:
				_set_task(record, task, "COMPLETE" if work.status == "COMPLETE" else "FAILED", str(work.reason))
			elif value.get("reason", "") == "route_blocked":
				_set_task(record, task, "BLOCKED", "deployment_approach_blocked")
			elif value.get("status", "") in ["failed", "cancelled"]:
				_set_task(record, task, "FAILED", "deployment_goal_unavailable")
			return
		if task.phase == "PAUSE":
			return
		if value.status == "complete":
			_set_task(record, task, "COMPLETE", "subordinate_observed_goal_complete")
		elif value.status in ["failed", "cancelled"]:
			_set_task(record, task, "FAILED", str(value.get("reason", "goal_failed")))
		elif value.get("reason", "") in ["route_blocked", "fuel_exhausted", "suppression"] or value.get("fire_reason", "") == "ammunition_exhausted":
			_set_task(record, task, "BLOCKED", str(value.get("reason", value.get("fire_reason", ""))))
		elif task.status == "BLOCKED":
			_set_task(record, task, "EXECUTING", "received_execution_recovered")
	elif task.domain == "AIR" and claim.fact_kind == "air_status" and claim.subject_ref == task.intent.values.asset_ref and value.get("mission_ref", "") == task.get("payload_ref", ""):
		var status: String = str(value.get("mission_status", value.get("status", "")))
		if status == "RETURNED":
			_set_task(record, task, "COMPLETE", "actual_sortie_return_report")
		elif status in ["AIRCRAFT_DESTROYED", "DESTROYED", "ABORTED", "INTERRUPTED_LANDED_AWAY_FROM_BASE", "BASE_UNAVAILABLE_LANDED"]:
			_set_task(record, task, "FAILED", status)
	elif task.domain in ["NAVAL", "LAND", "SUPPLY"] and claim.fact_kind in ["sea_status", "land_supply_status", "supply_status"]:
		var matches: bool = claim.subject_ref == str(task.get("intent", {}).get("values", {}).get("vessel_ref", "")) or value.get("carrier_ref", "") == str(task.get("intent", {}).get("values", {}).get("unit_ref", "__no_carrier")) or not str(task.get("request_ref", "")).is_empty() and value.get("request_ref", "") == task.request_ref
		matches = matches or task.domain == "NAVAL" and value.get("transport_ref", "__none") == task.get("transport_ref", task.get("payload_ref", ""))
		if task.domain == "LAND":
			matches = value.get("carrier_ref", "") == task.get("actual_carrier_ref", task.intent.values.get("unit_ref", "")) and value.get("transport_ref", "") == task.get("transport_ref", task.get("payload_ref", ""))
			var expected: String = str(task.get("request_ref", task.intent.values.get("request_ref", "")))
			if matches and expected != "" and value.get("request_ref", "") != expected:
				_set_task(record, task, "CANCELLED", "same_cargo_leg_redirected_from_previous_request")
				return
		if not matches:
			return
		if task.domain == "NAVAL" and task.has("transport_ref") and value.get("transport_ref", "") != task.transport_ref:
			return
		if task.domain == "NAVAL" and task.intent.values.get("operation", "") == "rendezvous" and claim.subject_ref == task.intent.values.vessel_ref:
			if value.get("rendezvous_ref", "") == task.intent.values.rendezvous_ref and value.get("rendezvous_status", "") == "RENDEZVOUS_READY":
				_set_task(record, task, "COMPLETE", "both_real_ships_ready_at_known_meeting_site")
			elif value.get("rendezvous_status", "") == "RENDEZVOUS_EXPIRED_AT_ACTUAL_POSITION":
				_set_task(record, task, "FAILED", "meeting_deadline_retains_real_position_and_cargo")
			return
		if task.domain == "NAVAL" and task.phase == "TRANSFER" and value.get("transfer_ref", "") == task.command_ref and str(value.get("mission_status", "")).contains("TRANSFER"):
			if value.get("transfer_status", "") == "COMPLETE" and claim.subject_ref == value.get("transfer_source_ref", "") and task.get("actual_vessel_ref", "") != value.get("transfer_recipient_ref", "") and _owner.get_ref().sea.freight.cargo_quantity(value.get("cargo", {})) <= 0.000001:
				var old_resource: String = _resource(task)
				if _resources.get(old_resource, "") == task.id:
					_resources.erase(old_resource)
				task.intent.values.vessel_ref = value.transfer_recipient_ref
				task.actual_vessel_ref = value.transfer_recipient_ref
				task.transport_ref = value.transport_ref
				task.assignment_revision = int(task.get("assignment_revision", 0)) + 1
				task.erase("transfer_receiver_ref")
				task.erase("meeting_partner_ref")
				_resources[_resource(task)] = task.id
				_set_task(record, task, "BLOCKED", "cargo_transferred_waiting_received_receiver_route")
			elif value.get("transfer_status", "") == "INTERRUPTED":
				var second: String = _second_resource(task)
				if _resources.get(second, "") == task.id:
					_resources.erase(second)
				task.erase("transfer_receiver_ref")
				task.erase("meeting_partner_ref")
				_set_task(record, task, "BLOCKED", "transfer_interrupted_actual_portions_retained")
			return
		if task.domain == "NAVAL" and task.intent.values.get("operation", "") == "transship_cargo":
			if value.get("transfer_ref", "") == task.get("payload_ref", ""):
				if value.get("transfer_status", "") == "COMPLETE":
					_set_task(record, task, "COMPLETE", "actual_ship_transfer_completed")
				elif value.get("transfer_status", "") == "INTERRUPTED":
					_set_task(record, task, "BLOCKED", "actual_ship_transfer_interrupted")
			return
		if task.domain == "NAVAL" and value.get("mission_ref", "") == task.get("payload_ref", ""):
			if value.get("mission_status", "") == "COMPLETED":
				_set_task(record, task, "COMPLETE", "actual_surface_mission_completion_report")
				return
			if value.get("mission_status", "") in ["WATERWAY_BLOCKED", "FUEL_EXHAUSTED_AT_ACTUAL_POSITION", "MOBILITY_LOST_AT_ACTUAL_POSITION"]:
				_set_task(record, task, "BLOCKED", str(value.mission_status))
				return
		var status: String = str(value.get("transport_status", value.get("status", "")))
		if task.domain == "NAVAL" and status == "PORTION_RECEIVED" and claim.subject_ref == task.intent.values.vessel_ref and value.get("node_ref", "") == value.get("destination_port", "__none"):
			_set_task(record, task, "COMPLETE", "actual_carrier_portion_unloaded_other_portions_keep_responsibility")
			return
		if task.domain == "NAVAL" and status == "RETURNED_TO_SOURCE":
			_set_task(record, task, "COMPLETE" if task.get("completion", "") == "return" else "CANCELLED", "actual_source_return_keeps_front_demand_unfulfilled")
			return
		if task.domain == "NAVAL" and status == "RECEIVED" and value.get("request_ref", "") != "":
			task.request_ref = value.request_ref
		if status == "RECEIVED" or task.get("completion", "") == "arrival" and status in ["ARRIVED", "DOCKED", "ANCHORED"]:
			_set_task(record, task, "COMPLETE", "actual_delivery_or_arrival_report")
		elif status in ["SUNK", "VESSEL_SUNK", "CARGO_LOST", "LOST"]:
			_set_task(record, task, "FAILED", status)
		elif status in ["BLOCKED", "PORTION_LOST", "FUEL_EXHAUSTED", "CAPACITY_LOST", "STRANDED", "TEMPORARILY_IMMOBILE", "MOBILITY_LOST_AT_ACTUAL_POSITION", "WAITING_RECIPIENT", "PARTIAL_CARGO_LOSS"]:
			_set_task(record, task, "BLOCKED", status)

func _refresh(record: Dictionary) -> void:
	if record.status in TERMINAL and not _has_open_tasks(record):
		return
	var g: RefCounted = _owner.get_ref()
	if g._state.time >= float(record.deadline):
		for task: Dictionary in record.tasks.values():
			if task.status not in TERMINAL and not task.get("cancel_requested", false):
				_cancel(record, task, "purpose_decision_deadline")
		if record.status not in TERMINAL:
			record.status = "FAILED"
			_publish_status(record)
	_dispatch(record)
	var required: int = 0
	var complete: int = 0
	var failed: int = 0
	var blocked: int = 0
	for task: Dictionary in record.tasks.values():
		if task.required:
			required += 1
			complete += int(task.status == "COMPLETE")
			failed += int(task.status in ["FAILED", "CANCELLED"])
			blocked += int(task.status in ["BLOCKED", "WAITING_RESOURCE"])
	var status: String = "COMPLETE" if required > 0 and complete == required else ("FAILED" if required > 0 and failed + complete == required and failed > 0 else ("BLOCKED" if blocked + failed > 0 else "ACTIVE"))
	if record.status not in TERMINAL and record.status != status:
		record.status = status
		_publish_status(record)
	if record.status in TERMINAL:
		for task: Dictionary in record.tasks.values():
			if task.status not in TERMINAL and _cargo_task(task) and task.status != "COMMAND_PENDING":
				_set_task(record, task, "CANCELLED", "purpose_ended_physical_responsibility_retained")

func _set_task(record: Dictionary, task: Dictionary, status: String, reason: String) -> void:
	if task.status == status and task.reason == reason:
		return
	task.status = status
	task.reason = reason
	if status in TERMINAL:
		if task.domain == "GROUND" and _special_units.get(task.get("unit_ref", ""), "") == task.id:
			_special_units.erase(task.unit_ref)
		var key: String = _resource(task)
		if _resources.get(key, "") == task.id:
			_resources.erase(key)
		var second: String = _second_resource(task)
		if _resources.get(second, "") == task.id:
			_resources.erase(second)
		var pending: String = "unit:" + str(task.get("pending_carrier_ref", ""))
		if _resources.get(pending, "") == task.id:
			_resources.erase(pending)
	_publish_task(record, task)

func _cargo_task(task: Dictionary) -> bool:
	var values: Dictionary = task.get("intent", {}).get("values", {})
	if task.domain == "NAVAL":
		return values.get("operation", "") in ["transport", "continue_transport", "resume_transport", "unload", "transship_cargo", "reassign_cargo"] or values.get("operation", "") == "rendezvous" and _owner.get_ref().sea.vessels.get(values.get("vessel_ref", ""), {}).get("cargo_ref", "") != ""
	if task.domain == "LAND":
		var job: Dictionary = _owner.get_ref().land.jobs.get(task.get("transport_ref", task.get("payload_ref", "")), {})
		return job.get("payload_kind", "") == "CARGO" or values.get("operation", "") == "transport"
	return false

func _cancel(record: Dictionary, task: Dictionary, reason: String) -> void:
	task.cancel_requested = true
	if task.status == "AWAITING_CONFIRMATION":
		_set_task(record, task, "CANCELLED", reason + "_unconfirmed_order_keeps_independent_physical_results")
		return
	if _cargo_task(task) and not _commands.has(task.command_ref):
		_set_task(record, task, "CANCELLED", reason + "_physical_responsibility_retained")
		return
	if str(task.command_ref).is_empty() or task.domain in ["SUPPLY", "REPORT"] or not task.has("executed_at") and not _commands.has(task.command_ref):
		_set_task(record, task, "CANCELLED", reason + "_no_physical_order_to_cancel")
	else:
		_set_task(record, task, "CANCEL_PENDING", reason)

func _publish_task(record: Dictionary, task: Dictionary) -> void:
	task.report_revision = int(task.get("report_revision", 0)) + 1
	var value: Dictionary = task.duplicate(true)
	value.erase("work_started")
	value.operation_ref = record.id
	value.reporter_ref = _current_owner(record)
	value.purpose = record.purpose
	value.operation_priority = record.priority
	value.deadline = record.deadline
	value.started_at = record.started_at
	value.scope = record.scope
	value.issuer = record.issuer
	value.predecessor_ref = record.get("predecessor_ref", "")
	value.supports_operation_ref = record.get("supports_operation_ref", "")
	value.target_node = record.target_node
	var recipients: Array[String] = [str(task.executor)]
	if not str(task.get("previous_executor", "")).is_empty() and task.previous_executor not in recipients:
		recipients.append(str(task.previous_executor))
	var holder: String = _current_owner(record)
	if not holder.is_empty() and holder not in recipients:
		recipients.append(holder)
	for recipient: String in recipients:
		_send(record, recipient, "operation_task", value)

func _current_owner(record: Dictionary) -> String:
	return str(_owner.get_ref()._state.structure_port.get_ref()._positions.get(record.scope, {}).get("person", record.issuer))

func _publish_status(record: Dictionary) -> void:
	record.report_revision = int(record.get("report_revision", 0)) + 1
	var states: Dictionary = {}
	for task: Dictionary in record.tasks.values():
		states[task.task_ref] = task.status
	var recipient: String = _current_owner(record)
	if not recipient.is_empty():
		_send(record, recipient, "operation_status", {"operation_ref": record.id, "purpose": record.purpose,
			"scope": record.scope, "issuer": record.issuer, "reporter_ref": recipient, "predecessor_ref": record.get("predecessor_ref", ""), "supports_operation_ref": record.get("supports_operation_ref", ""), "report_revision": record.report_revision, "target_node": record.target_node, "status": record.status, "priority": record.priority, "deadline": record.deadline, "tasks": states})

func _send(record: Dictionary, recipient: String, fact: String, value: Dictionary) -> void:
	_serial += 1
	_owner.get_ref()._state.information_port.get_ref().send_task_report(self, str(record.id), recipient,
		"purpose_report_%d" % _serial, fact, value)

func permits_report(reference: String, recipient: String) -> bool:
	if not _records.has(reference):
		return false
	var record: Dictionary = _records[reference]
	if recipient == _current_owner(record) or recipient == record.issuer:
		return true
	for task: Dictionary in record.tasks.values():
		if task.executor == recipient or task.get("previous_executor", "") == recipient:
			return true
	return false

func known_view(person: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in _known.get(person, {}).values():
		result.append(value.duplicate(true))
	return result

func on_position_changed(person: String, _node: String) -> void:
	if not _active:
		return
	for record: Dictionary in _records.values():
		for task: Dictionary in record.tasks.values():
			if task.status in TERMINAL and (not task.get("followup", true) or task.has("followup_status")):
				continue
			var executor: String = _executor(_current_owner(record), str(record.scope), task)
			if executor != task.executor:
				var previous: String = str(task.executor)
				task.previous_executor = previous
				task.executor = executor
				# The same task and physical mission survive an office handover.
				if not previous.is_empty():
					_owner.get_ref()._state.decision_port.get_ref().note_change(previous, "task_authority_changed", str(task.id))
				_publish_task(record, task)
		if _current_owner(record) == person:
			_publish_status(record)
	for unit: String in _field_sources:
		on_unit(unit)

func on_structure(change: Dictionary) -> void:
	if not _active:
		return
	var outcome: Dictionary = change.get("outcome", {})
	if outcome.get("kind", "") == "merge":
		var source: String = str(outcome.values.donor)
		var survivor: String = str(outcome.values.survivor)
		if _work_units.has(source):
			_finish_work(source, "INTERRUPTED", "working_unit_merged_equipment_not_duplicated")
		if engineers.has(source) and not engineers.has(survivor):
			engineers[survivor] = engineers[source].duplicate(true)
		engineers.erase(source)
		if _field_sources.has(source):
			_merge_observers(source, survivor)
	var s: RefCounted = _owner.get_ref()._state.structure_port.get_ref()
	for record: Dictionary in _records.values():
		if record.status in TERMINAL:
			continue
		for task: Dictionary in record.tasks.values():
			if task.domain == "GROUND" and task.status not in TERMINAL and (not s.active(str(s._unit_nodes.get(task.unit_ref, ""))) or not s._contains(str(record.scope), str(s._unit_nodes.get(task.unit_ref, "")))):
				if _work_units.has(str(task.unit_ref)):
					_finish_work(str(task.unit_ref), "INTERRUPTED", "working_unit_left_task_scope")
				_set_task(record, task, "FAILED", "executor_left_current_purpose_scope")
		_refresh(record)
	on_position_changed("", "")

func _prune() -> void:
	if _records.size() <= MAX_OPERATIONS * 2:
		return
	for id: String in _records.keys():
		if _records[id].status in TERMINAL and not _has_open_tasks(_records[id]):
			_records.erase(id)
			if _records.size() <= MAX_OPERATIONS * 2:
				break

func _has_open_tasks(record: Dictionary) -> bool:
	for task: Dictionary in record.tasks.values():
		if task.status not in TERMINAL:
			return true
	return false

static func _priority(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= 0.0 and float(value) <= 5.0

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["_active", "_records", "_known", "_resources", "_commands", "_serial", "_field_sources", "_field_spares", "_field_last", "_field_readers", "_office_orders", "engineers", "_work_units", "_work_tickets", "_work_results", "_special_units", "rules"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
