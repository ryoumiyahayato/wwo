extends RefCounted
## Snapshot admission and bounded stock transactions on the existing world clock.
## Depots are current source facts. BattleState live representations own unit stocks.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const EXTRA_STOCKS: Array[String] = ["fuel", "fuel_spent", "spares", "spares_spent",
	"serviceable_equipment", "damaged_equipment", "wear_damage", "repair_restored", "medical", "medical_spent"]
const CLASSES: Dictionary = {"AMMUNITION": "ammunition", "FUEL": "fuel", "SPARES": "spares", "MEDICAL": "medical"}
const EPS: float = 0.0000001
var _state: State
var _lod: RefCounted
var _structure: RefCounted
var _depots: Dictionary = {}
var _capacities: Dictionary = {}
var _requests: Dictionary = {}
var _deliveries: Dictionary = {}
var _maintenance: Dictionary = {}
var _used: Dictionary = {}
var _paths: Dictionary = {}
var _node_reps: Dictionary = {}
var _rep_counts: Dictionary = {}
var _initial: Dictionary = {}
var _assets: Dictionary = {} # Air and surface units alias these finite stock records.
var _reserved: Dictionary = {} # Sea loading reservations remain at their source depot.
var _port_sources: Dictionary = {}
var _port_report_serial: int = 0
var history: Array[Dictionary] = []
var work: Dictionary = {"inventory_records_examined": 0, "deliveries_processed": 0,
	"future_deliveries_examined": 0, "allocations_processed": 0, "serviceability_records_updated": 0,
	"leaves_materialized_for_logistics": 0, "proxy_edits": 0, "responsibility_queries": 0,
	"logistics_events_processed": 0, "representation_index_edits": 0, "heap_event_comparisons": 0}

func configure(state: State, lod: RefCounted, structure: RefCounted, facts: Dictionary,
		depots: Dictionary, capacities: Dictionary) -> bool:
	if _state != null or state.logistics_port != null or not lod.owns_state(state) or not structure.owns_state(state) or not state.events.is_empty() or facts.is_empty():
		return false
	# Complete validation precedes all admission mutations.
	for id: String in facts:
		if not state.units.has(id) or state.units[id].has("contact_weight") or not structure._unit_nodes.has(id) or not _valid_fact(facts[id], state.units[id]):
			return false
	for id: String in depots:
		var depot: Dictionary = depots[id]
		if id.is_empty() or not depot.get("owner_ref") is String or str(depot.owner_ref).is_empty() or not structure.active(str(depot.get("allocation_scope", ""))) or not depot.get("stock") is Dictionary:
			return false
		for resource: String in depot.stock:
			if not CLASSES.has(resource):
				return false
		for resource: String in CLASSES:
			if not _nonnegative(depot.stock.get(resource, 0.0)) or resource != "MEDICAL" and not depot.stock.has(resource):
				return false
	for id: String in capacities:
		if not _nonnegative(capacities[id].get("remaining")) or not structure.active(str(capacities[id].get("scope", ""))):
			return false
	_state = state
	_lod = lod
	_structure = structure
	_depots = depots.duplicate(true)
	_capacities = capacities.duplicate(true)
	_initial = {"AMMUNITION": float(state.totals.ammunition), "FUEL": 0.0, "SPARES": 0.0, "MEDICAL": 0.0}
	for id: String in State.sorted_ids(facts):
		var unit: Dictionary = state.units[id]
		for key: String in EXTRA_STOCKS:
			unit[key] = float(facts[id].get(key, 0.0))
		unit.supply_capability = facts[id].capability.duplicate(true)
		_initial.FUEL += float(unit.fuel) + float(unit.fuel_spent)
		_initial.SPARES += float(unit.spares) + float(unit.spares_spent)
		_initial.MEDICAL += float(unit.medical) + float(unit.medical_spent)
		_index(id, id, structure._path(str(structure._unit_nodes[id])))
	for id: String in _depots:
		_depots[id].stock.MEDICAL = float(_depots[id].stock.get("MEDICAL", 0.0))
		for resource: String in CLASSES:
			_initial[resource] += float(_depots[id].stock[resource])
	state.logistics_ledger = {"fuel_spent": 0.0, "spares_spent": 0.0, "wear_damage": 0.0, "repair_restored": 0.0, "medical_spent": 0.0}
	state.logistics_ledger.cargo_lost = {"AMMUNITION": 0.0, "FUEL": 0.0, "SPARES": 0.0, "MEDICAL": 0.0}
	state.logistics_port = weakref(self)
	lod.spatial.extend_stocks(EXTRA_STOCKS)
	var cells: Dictionary = {}
	for id: String in facts:
		cells[state.units[id].area_id] = true
	for cell: String in cells:
		var stocks: Dictionary = {}
		for id: String in state.area_units[cell]:
			for key: String in lod.stock_keys():
				stocks[key] = float(stocks.get(key, 0.0)) + float(state.units[id].get(key, 0.0))
		lod.spatial.update_leaf(cell, stocks, str(state.areas[cell].control))
	reset_work()
	return true

static func _valid_fact(fact: Dictionary, unit: Dictionary) -> bool:
	for key: String in EXTRA_STOCKS:
		if not _nonnegative(fact.get(key, 0.0)) or key not in ["medical", "medical_spent"] and not fact.has(key):
			return false
	if absf(float(fact.serviceable_equipment) + float(fact.damaged_equipment) - float(unit.equipment)) > EPS or not fact.get("capability") is Dictionary:
		return false
	var cap: Dictionary = fact.capability
	if not cap.get("fuel_dependent") is bool:
		return false
	for key: String in ["fuel_per_equipment_km", "spares_per_repair", "wear_per_km", "suppression_per_round"]:
		if not _nonnegative(cap.get(key)):
			return false
	return float(cap.spares_per_repair) > 0.0 and ((cap.fuel_dependent and float(cap.fuel_per_equipment_km) > 0.0) or (not cap.fuel_dependent and float(cap.fuel_per_equipment_km) == 0.0 and float(fact.fuel) == 0.0))

func reset_work() -> void:
	for key: String in work:
		work[key] = 0

func compatible(a: Dictionary, b: Dictionary, coalescing: bool) -> bool:
	if a.has("supply_capability") != b.has("supply_capability"):
		return false
	if not a.has("supply_capability"):
		return true
	if a.supply_capability != b.supply_capability:
		return false
	if coalescing:
		# Homogeneous stock intensities are essential: averaging an exhausted leaf
		# with a supplied leaf would invent capabilities, not just a representation.
		for key: String in _lod.stock_keys():
			if absf(float(a[key]) / float(a.personnel_total) - float(b[key]) / float(b.personnel_total)) > 0.000000001:
				return false
	return true

func prepare_activity(unit: Dictionary, plan: Dictionary) -> void:
	work.inventory_records_examined += 1
	var cap: Dictionary = unit.supply_capability
	plan.fuel_per_km = float(unit.serviceable_equipment) * float(cap.fuel_per_equipment_km)
	if cap.fuel_dependent and (float(unit.fuel) <= EPS or float(unit.serviceable_equipment) <= 0.0):
		plan.speed = 0.0
	plan.fuel_rate = absf(float(plan.speed)) * float(plan.fuel_per_km) if cap.fuel_dependent else 0.0

func lose_equipment(unit: Dictionary, loss: float, protected_serviceable: float = 0.0, protected_equipment: float = -1.0) -> void:
	var available: float = maxf(0.0, float(unit.equipment) - (protected_serviceable if protected_equipment < 0.0 else protected_equipment))
	var share: float = maxf(0.0, float(unit.serviceable_equipment) - protected_serviceable) / available if available > 0.0 else 0.0
	unit.serviceable_equipment = maxf(0.0, float(unit.serviceable_equipment) - loss * share)
	unit.damaged_equipment = maxf(0.0, float(unit.damaged_equipment) - loss * (1.0 - share))
	if loss > 0.0:
		work.serviceability_records_updated += 1

func consume_activity(unit: Dictionary, plan: Dictionary, distance: float) -> void:
	var fuel_spent: float = minf(float(unit.fuel), distance * float(plan.get("fuel_per_km", 0.0))) if unit.supply_capability.fuel_dependent else 0.0
	unit.fuel -= fuel_spent
	unit.fuel_spent += fuel_spent
	_state.logistics_ledger.fuel_spent += fuel_spent
	var wear: float = maxf(0.0, float(unit.serviceable_equipment) - float(plan.get("protected_equipment", 0.0))) * minf(1.0, distance * float(unit.supply_capability.wear_per_km))
	unit.serviceable_equipment -= wear
	unit.damaged_equipment += wear
	unit.wear_damage += wear
	_state.logistics_ledger.wear_damage += wear
	if wear > 0.0:
		work.serviceability_records_updated += 1

func _index(id: String, representation: String, path: Array[String]) -> void:
	_paths[id] = path.duplicate()
	_rep_counts[representation] = int(_rep_counts.get(representation, 0)) + 1
	for node_id: String in path:
		if not _node_reps.has(node_id):
			_node_reps[node_id] = {}
		_node_reps[node_id][representation] = int(_node_reps[node_id].get(representation, 0)) + 1
		work.representation_index_edits += 1

func _unindex(id: String, representation: String) -> Array[String]:
	var path: Array[String] = _paths[id]
	for node_id: String in path:
		_node_reps[node_id][representation] -= 1
		if int(_node_reps[node_id][representation]) == 0:
			_node_reps[node_id].erase(representation)
		work.representation_index_edits += 1
	_rep_counts[representation] -= 1
	if int(_rep_counts[representation]) == 0:
		_rep_counts.erase(representation)
	_paths.erase(id)
	return path

func on_coalesce(aggregate_id: String, ids: Array[String]) -> void:
	for id: String in ids:
		if _paths.has(id):
			var path: Array[String] = _unindex(id, id)
			_index(id, aggregate_id, path)

func on_materialize(id: String, aggregate_id: String) -> void:
	if _paths.has(id):
		var path: Array[String] = _unindex(id, aggregate_id)
		_index(id, id, path)

func on_structure(result: Dictionary) -> void:
	# Structure materializes only its causal subtree before mutating relations.
	for id: String in result.get("retired", []):
		if _paths.has(id):
			_unindex(id, id)
	for id: String in result.get("changed", []):
		if not _structure._unit_nodes.has(id) or not _state.units.has(id) or not _state.units[id].has("supply_capability"):
			continue
		if _paths.has(id):
			_unindex(id, id)
		_index(id, id, _structure._path(str(_structure._unit_nodes[id])))

func responsibility(unit_id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	work.responsibility_queries += 1
	return _structure.relation(str(_structure._unit_nodes.get(unit_id, "")))

func _allowed(person_id: String, target_kind: String, target: String, rank: int) -> bool:
	if not _structure._people.has(person_id):
		return false
	var person: Dictionary = _structure.command_person(person_id)
	if Roles.ROLES.find(str(person.role)) < rank or not _structure.active(str(person.formation_id)):
		return false
	var node_id: String = str(_structure._unit_nodes.get(target, "")) if target_kind == "unit" else target
	if target_kind == "depot":
		node_id = str(_depots.get(target, {}).get("allocation_scope", ""))
	return _structure._contains(str(person.formation_id), node_id)

func submit(person_id: String, command: Dictionary) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state == null or not command.get("id") is String or str(command.id).is_empty() or not command.get("kind") is String or _used.has(command.id):
		return _reject("invalid_or_duplicate_request")
	if command.kind == "request":
		if command.size() != 6 or not _keys(command, ["id", "kind", "target_kind", "target", "resource_class", "quantity"]) or not command.get("target") is String or command.get("target_kind") not in ["unit", "formation", "depot"] or command.get("resource_class") not in CLASSES or not _positive(command.get("quantity")):
			return _reject("invalid_supply_request")
		if not _allowed(person_id, str(command.target_kind), str(command.target), 2):
			return _reject("outside_request_scope")
		var recipients: Dictionary = _recipients(str(command.target_kind), str(command.target), false)
		if not recipients.ok or not _resource_compatible(recipients, str(command.resource_class)):
			return _reject("incompatible_recipient")
		var request: Dictionary = command.duplicate(true)
		request.actor = person_id
		request.status = "REQUESTED"
		request.issue_time = _state.time
		_requests[command.id] = request
		_used[command.id] = true
		return {"ok": true, "status": request.status}
	if command.kind == "allocate":
		if command.size() != 5 or not _keys(command, ["id", "kind", "request_id", "source_ref", "delivery_time"]) or not command.get("request_id") is String or not command.get("source_ref") is String or not _number(command.get("delivery_time")) or float(command.delivery_time) < _state.time or not _requests.has(command.request_id) or not _depots.has(command.source_ref) or _state.event_ids.has("logistics_delivery_" + str(command.id)):
			return _reject("invalid_allocation")
		var request: Dictionary = _requests[command.request_id]
		if request.get("land_delivery_ref", "") != "":
			return _reject("explicit_physical_land_request_requires_actual_remaining_cargo_leg")
		if request.get("sea_required", false) and request.get("sea_delivery_ref", "") == "":
			return _reject("explicit_sea_request_has_no_actual_carrier_allocation")
		if request.get("sea_delivery_ref", "") != "":
			var sea_delivery: Dictionary = _deliveries[request.sea_delivery_ref]
			if sea_delivery.status != "RECEIVED" or command.source_ref != sea_delivery.recipient_ref:
				return _reject("seaborne_request_requires_actual_destination_port_stock")
			if sea_port_remaining(str(request.sea_delivery_ref), str(request.resource_class)) + EPS < float(request.quantity):
				return _reject("partial_port_batch_requires_physical_land_manifest")
			if request.target_kind != "unit" or not _lod.has_leaf(str(request.target)):
				return _reject("bounded_port_local_unit_recipient_required")
			var local_unit: Dictionary = _lod.preview_leaf(str(request.target))
			if not local_unit.has("spatial") or local_unit.spatial.node != _depots[command.source_ref].get("node_ref", "") or not str(local_unit.spatial.edge).is_empty():
				return _reject("sea_cargo_waits_for_actual_port_local_recipient")
		if request.status != "REQUESTED" or not _allowed(person_id, str(request.target_kind), str(request.target), 3) or not _allowed(person_id, "depot", str(command.source_ref), 3):
			return _reject("outside_allocation_scope_or_already_allocated")
		var recipients: Dictionary = _recipients(str(request.target_kind), str(request.target), false)
		if not recipients.ok or not _resource_compatible(recipients, str(request.resource_class)):
			return _reject("incompatible_recipient")
		var depot: Dictionary = _depots[command.source_ref]
		work.inventory_records_examined += 1
		if available_stock(str(command.source_ref), str(request.resource_class)) < float(request.quantity):
			return _reject("insufficient_source_stock")
		var delivery: Dictionary = {"delivery_id": command.id, "source_ref": command.source_ref,
			"recipient_ref": request.target, "recipient_kind": request.target_kind, "resource_class": request.resource_class,
			"quantity": request.quantity, "issue_time": _state.time, "delivery_time": command.delivery_time,
			"status": "IN_TRANSIT", "allocation_actor": person_id, "request_id": request.id}
		_deliveries[command.id] = delivery
		if request.get("sea_delivery_ref", "") != "":
			delivery.transport_mode = "PORT_LOCAL"
			delivery.required_node = _depots[command.source_ref].node_ref
		if not _state.schedule_event("logistics_delivery_" + str(command.id), float(command.delivery_time), "logistics", {"delivery_id": command.id}):
			_deliveries.erase(command.id)
			return _reject("schedule_failed")
		depot.stock[request.resource_class] -= float(request.quantity)
		if delivery.get("transport_mode", "") == "PORT_LOCAL":
			var sea: Dictionary = _deliveries[request.sea_delivery_ref]
			if not sea.has("forwarded_cargo"):
				sea.forwarded_cargo = {}
			sea.forwarded_cargo[request.resource_class] = float(sea.forwarded_cargo.get(request.resource_class, 0.0)) + float(request.quantity)
			delivery.sea_delivery_ref = request.sea_delivery_ref
			request.land_delivery_ref = command.id
		request.status = "ALLOCATED"
		_used[command.id] = true
		work.allocations_processed += 1
		return {"ok": true, "status": delivery.status}
	if command.kind == "maintenance":
		if command.size() != 7 or not _keys(command, ["id", "kind", "target_kind", "target", "quantity", "capacity_ref", "effective_time"]) or not command.get("target") is String or command.get("target_kind") not in ["unit", "formation"] or not _positive(command.get("quantity")) or not _number(command.get("effective_time")) or float(command.effective_time) < _state.time or not command.get("capacity_ref") is String or not _capacities.has(command.capacity_ref) or _state.event_ids.has("logistics_maintenance_" + str(command.id)):
			return _reject("invalid_maintenance")
		if not _allowed(person_id, str(command.target_kind), str(command.target), 3) or not _structure._contains(str(_structure._people[person_id].formation_id), str(_capacities[command.capacity_ref].scope)):
			return _reject("outside_maintenance_scope")
		var request: Dictionary = command.duplicate(true)
		request.actor = person_id
		request.status = "SCHEDULED"
		_maintenance[command.id] = request
		if not _state.schedule_event("logistics_maintenance_" + str(command.id), float(command.effective_time), "logistics", {"maintenance_id": command.id}):
			_maintenance.erase(command.id)
			return _reject("schedule_failed")
		_used[command.id] = true
		return {"ok": true, "status": "SCHEDULED"}
	return _reject("unknown_logistics_action")

func accepts_event(event_id: String, payload: Dictionary, due: float) -> bool:
	if payload.size() != 1:
		return false
	if payload.get("delivery_id") is String and _deliveries.has(payload.delivery_id):
		var delivery: Dictionary = _deliveries[payload.delivery_id]
		if delivery.get("transport_mode", "ABSTRACT") in ["SEA", "LAND"]:
			return false
		return event_id == "logistics_delivery_" + str(delivery.delivery_id) and due == float(delivery.delivery_time) and delivery.status == "IN_TRANSIT"
	if payload.get("maintenance_id") is String and _maintenance.has(payload.maintenance_id):
		var request: Dictionary = _maintenance[payload.maintenance_id]
		return event_id == "logistics_maintenance_" + str(request.id) and due == float(request.effective_time) and request.status == "SCHEDULED"
	return false

func _recipients(kind: String, target: String, materialize: bool) -> Dictionary:
	if kind == "depot":
		return {"ok": _depots.has(target), "depot": target, "ids": [], "changed": [], "retired": []}
	if kind == "unit":
		if not _paths.has(target) or not _state.knows_unit(target):
			return _reject("retired_or_unmanaged_recipient")
		var represented: String = _lod.representation_of(target)
		if materialize:
			var result: Dictionary = _lod.materialize_leaf(target, "specific_logistics_input")
			work.leaves_materialized_for_logistics += int(result.materialized)
			result.ids = [target]
			return result
		return {"ok": true, "ids": [represented], "changed": [], "retired": []}
	if not _structure.active(target) or not _node_reps.has(target) or _node_reps[target].is_empty():
		return _reject("empty_or_inactive_formation")
	var ids: Array[String] = State.sorted_ids(_node_reps[target])
	for id: String in ids:
		if int(_node_reps[target][id]) != int(_rep_counts[id]):
			return _reject("partial_proxy_scope_requires_explicit_leaf_target")
	return {"ok": true, "ids": ids, "changed": [], "retired": []}

func _resource_compatible(recipients: Dictionary, resource: String) -> bool:
	if recipients.has("depot") or resource != "FUEL":
		return true
	for id: String in recipients.ids:
		work.inventory_records_examined += 1
		if not _state.units[id].supply_capability.fuel_dependent:
			return false
	return true

func process_event(event: Dictionary) -> Dictionary:
	if float(event.time) != _state.time or not accepts_event(str(event.id), event.payload, float(event.time)):
		return {"changed": [], "retired": [], "record": _reject("stale_or_invalid_ticket")}
	work.logistics_events_processed += 1
	if event.payload.has("delivery_id"):
		return _receive(_deliveries[event.payload.delivery_id])
	return _repair(_maintenance[event.payload.maintenance_id])

func _receive(delivery: Dictionary) -> Dictionary:
	if delivery.get("transport_mode", "ABSTRACT") in ["SEA", "LAND"]:
		return {"changed": [], "retired": [], "record": {"kind": "physical_sea_receipt_requires_unloading"}}
	if delivery.has("required_node"):
		var valid_local: bool = _state.knows_unit(str(delivery.recipient_ref)) and _lod.has_leaf(str(delivery.recipient_ref))
		if valid_local:
			var unit: Dictionary = _lod.preview_leaf(str(delivery.recipient_ref))
			valid_local = unit.has("spatial") and unit.spatial.node == delivery.required_node and str(unit.spatial.edge).is_empty()
			if valid_local and _state.spatial_port != null:
				var space: RefCounted = _state.spatial_port.get_ref()
				valid_local = str(unit.spatial.get("local_edge", "")) == "" and space._distance(space.xy(unit), space._nodes[delivery.required_node].xy) <= 0.000001
		if not valid_local:
			delivery.status = "REJECTED_RETURNED"
			delivery.reason = "recipient_left_actual_port_supply_node"
			_depots[delivery.source_ref].stock[delivery.resource_class] += float(delivery.quantity)
			_requests[delivery.request_id].status = "REQUESTED"
			_report_port_receipt(delivery)
			return _record(delivery, {"changed": [], "retired": []})
	work.deliveries_processed += 1
	var recipients: Dictionary = _recipients(str(delivery.recipient_kind), str(delivery.recipient_ref), false)
	if not recipients.ok or not _resource_compatible(recipients, str(delivery.resource_class)):
		delivery.status = "REJECTED_RETURNED"
		delivery.reason = recipients.get("error", "incompatible_capability")
		_depots[delivery.source_ref].stock[delivery.resource_class] += float(delivery.quantity)
		if delivery.get("transport_mode", "") == "PORT_LOCAL":
			_requests[delivery.request_id].status = "REQUESTED"
			_report_port_receipt(delivery)
		return _record(delivery, {"changed": [], "retired": []})
	recipients = _recipients(str(delivery.recipient_kind), str(delivery.recipient_ref), true)
	if recipients.has("depot"):
		_depots[recipients.depot].stock[delivery.resource_class] += float(delivery.quantity)
	else:
		var weight: float = 0.0
		for id: String in recipients.ids:
			work.inventory_records_examined += 1
			weight += float(_state.units[id].personnel_total)
		for id: String in recipients.ids:
			var unit: Dictionary = _state.units[id]
			unit[CLASSES[delivery.resource_class]] += float(delivery.quantity) * float(unit.personnel_total) / weight
			if unit.has("contact_weight"):
				work.proxy_edits += 1
			_state.wake(str(unit.area_id))
		if delivery.resource_class == "AMMUNITION":
			_state.totals.ammunition += float(delivery.quantity)
		recipients.changed = _union(recipients.get("changed", []), recipients.ids)
	delivery.status = "RECEIVED"
	delivery.receipt_time = _state.time
	if delivery.get("transport_mode", "") == "PORT_LOCAL":
		_requests[delivery.request_id].status = "RECEIVED"
	_report_port_receipt(delivery)
	if recipients.has("depot"):
		_physical_stock_arrived(str(recipients.depot))
	return _record(delivery, recipients)

func _local_repair_damage(unit: Dictionary) -> float:
	if _state.gameplay_port != null:
		var tactics: RefCounted = _state.gameplay_port.get_ref().tactics
		if tactics.manoeuvre_active(str(unit.id)):
			var part: Dictionary = tactics.manoeuvres[unit.id].parts.rear
			if part.role == "MOVING" or tactics.part_capacity(part) <= 0.000001:
				return 0.0
			return maxf(0.0, float(part.equipment) - float(part.serviceable))
	return float(unit.damaged_equipment)

func _repair(request: Dictionary) -> Dictionary:
	# Revalidate both authority and every bounded stock before materialization.
	var recipients: Dictionary = _recipients(str(request.target_kind), str(request.target), false)
	if not recipients.ok or not _allowed(str(request.actor), str(request.target_kind), str(request.target), 3):
		request.status = "REJECTED"
		request.reason = "recipient_or_authority_changed"
		return _record(request, {"changed": [], "retired": []})
	var damaged: float = 0.0
	var images: Dictionary = {}
	for id: String in recipients.ids:
		work.inventory_records_examined += 1
		var unit: Dictionary = _lod.preview_leaf(str(request.target)) if request.target_kind == "unit" else _state.units[id]
		images[id] = unit
		damaged += _local_repair_damage(unit)
	var capacity: Dictionary = _capacities[request.capacity_ref]
	var valid: bool = float(request.quantity) <= damaged and float(request.quantity) <= float(capacity.remaining) and _structure._contains(str(_structure._people[request.actor].formation_id), str(capacity.scope))
	for id: String in images:
		var unit: Dictionary = images[id]
		var amount: float = float(request.quantity) * _local_repair_damage(unit) / damaged if damaged > 0.0 else INF
		valid = valid and amount * float(unit.supply_capability.spares_per_repair) <= float(unit.spares)
	if not valid:
		request.status = "REJECTED"
		request.reason = "insufficient_damage_spares_or_capacity"
		return _record(request, {"changed": [], "retired": []})
	recipients = _recipients(str(request.target_kind), str(request.target), true)
	for id: String in recipients.ids:
		var unit: Dictionary = _state.units[id]
		var amount: float = float(request.quantity) * _local_repair_damage(unit) / damaged
		var cost: float = amount * float(unit.supply_capability.spares_per_repair)
		unit.spares -= cost
		unit.spares_spent += cost
		unit.damaged_equipment -= amount
		unit.serviceable_equipment += amount
		unit.repair_restored += amount
		if _state.gameplay_port != null and _state.gameplay_port.get_ref().tactics.manoeuvre_active(id):
			_state.gameplay_port.get_ref().tactics.manoeuvres[id].parts.rear.serviceable += amount
		_state.logistics_ledger.spares_spent += cost
		_state.logistics_ledger.repair_restored += amount
		work.serviceability_records_updated += 1
		if unit.has("contact_weight"):
			work.proxy_edits += 1
		_state.wake(str(unit.area_id))
	capacity.remaining -= float(request.quantity)
	request.status = "COMPLETED"
	request.completion_time = _state.time
	recipients.changed = _union(recipients.get("changed", []), recipients.ids)
	return _record(request, recipients)

func _record(record: Dictionary, result: Dictionary) -> Dictionary:
	history.append(record.duplicate(true))
	return {"changed": result.get("changed", []), "retired": result.get("retired", []), "record": record.duplicate(true)}

func admit_air_asset(id: String, depot: String, fuel: float, ammunition: float) -> Dictionary:
	if _state.time != 0.0 or _assets.size() >= 4 or _assets.has(id) or not _depots.has(depot) or fuel < 0.0 or ammunition < 0.0 or float(_depots[depot].stock.FUEL) < fuel or float(_depots[depot].stock.AMMUNITION) < ammunition:
		return {"ok": false, "error": "finite_initial_air_stock_unavailable"}
	_depots[depot].stock.FUEL -= fuel
	_depots[depot].stock.AMMUNITION -= ammunition
	_assets[id] = {"fuel": fuel, "fuel_spent": 0.0, "ammunition": ammunition, "ammo_spent": 0.0, "spares": 0.0, "spares_spent": 0.0, "equipment": 1.0, "equipment_lost": 0.0}
	_state.totals.ammunition += ammunition
	_state.totals.equipment += 1.0 # One explicitly admitted synthetic vehicle.
	return {"ok": true, "stock": _assets[id]}

func consume_air(id: String, resource: String, amount: float) -> float:
	var stock: Dictionary = _assets[id]
	var quantity: float = minf(maxf(0.0, amount), float(stock[resource]))
	stock[resource] -= quantity
	if resource == "fuel":
		stock.fuel_spent += quantity
		_state.logistics_ledger.fuel_spent += quantity
	elif resource == "spares":
		stock.spares_spent += quantity
		_state.logistics_ledger.spares_spent += quantity
	else:
		stock.ammo_spent += quantity
		_state.totals.ammo_spent += quantity
	return quantity

func replenish_asset(id: String, depot: String, resource: String, quantity: float) -> float:
	if not _assets.has(id) or not _depots.has(depot) or resource not in ["FUEL", "AMMUNITION", "SPARES"]:
		return 0.0
	var moved: float = minf(maxf(0.0, quantity), available_stock(depot, resource))
	_depots[depot].stock[resource] -= moved
	_assets[id][CLASSES[resource]] += moved
	if resource == "AMMUNITION":
		_state.totals.ammunition += moved
	return moved

func consume_depot_spares(depot: String, quantity: float) -> float:
	var spent: float = minf(maxf(0.0, quantity), available_stock(depot, "SPARES"))
	_depots[depot].stock.SPARES -= spent
	_state.logistics_ledger.spares_spent += spent
	return spent

func destroy_asset(id: String) -> void:
	var stock: Dictionary = _assets[id]
	var lost: float = float(stock.equipment)
	stock.equipment = 0.0
	stock.equipment_lost += lost
	_state.totals.equipment_lost += lost
	# Destroyed cargo leaves the same resource ledger once; it cannot be reloaded.
	consume_air(id, "fuel", float(stock.fuel))
	consume_air(id, "ammunition", float(stock.ammunition))
	consume_air(id, "spares", float(stock.spares))

func available_stock(depot: String, resource: String) -> float:
	if not _depots.has(depot) or not CLASSES.has(resource):
		return 0.0
	return maxf(0.0, float(_depots[depot].stock[resource]) - float(_reserved.get(depot, {}).get(resource, 0.0)))

func reserve_land(actor: String, id: String, source: String, kind: String, recipient: String, cargo: Dictionary, carrier: String, node: String, request_ref: String = "") -> void:
	if not _reserved.has(source):
		_reserved[source] = {}
	for resource: String in cargo:
		_reserved[source][resource] = float(_reserved[source].get(resource, 0.0)) + float(cargo[resource])
	_deliveries[id] = {"delivery_id": id, "transport_mode": "LAND", "source_ref": source,
		"recipient_kind": kind, "recipient_ref": recipient, "carrier_ref": carrier, "required_node": node,
		"cargo": cargo.duplicate(), "requested_cargo": cargo.duplicate(), "status": "RESERVED_AT_SOURCE",
		"allocation_actor": actor, "request_id": request_ref, "issue_time": _state.time}
	if request_ref != "":
		_requests[request_ref].status = "ALLOCATED_LAND"
		_requests[request_ref].land_delivery_ref = id
		_deliveries[id].sea_delivery_ref = _requests[request_ref].get("sea_delivery_ref", "")

func load_land(id: String) -> bool:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status != "RESERVED_AT_SOURCE":
		return false
	var sea_ref: String = str(delivery.get("sea_delivery_ref", ""))
	if not sea_ref.is_empty():
		for resource: String in delivery.cargo:
			if float(delivery.cargo[resource]) > sea_port_remaining(sea_ref, resource, str(delivery.request_id), str(delivery.source_ref)) + EPS:
				return false
	for resource: String in delivery.cargo:
		if float(_depots[delivery.source_ref].stock.get(resource, 0.0)) < float(delivery.cargo[resource]):
			return false
	for resource: String in delivery.cargo:
		_reserved[delivery.source_ref][resource] -= float(delivery.cargo[resource])
		_depots[delivery.source_ref].stock[resource] -= float(delivery.cargo[resource])
		if not sea_ref.is_empty():
			var sea: Dictionary = _deliveries[sea_ref]
			if not sea.has("forwarded_cargo"):
				sea.forwarded_cargo = {}
			sea.forwarded_cargo[resource] = float(sea.forwarded_cargo.get(resource, 0.0)) + float(delivery.cargo[resource])
			if sea.has("sea_assignments"):
				var key: String = str(delivery.request_id) + ":" + str(delivery.source_ref)
				if not sea.has("forwarded_by_assignment"):
					sea.forwarded_by_assignment = {}
				if not sea.forwarded_by_assignment.has(key):
					sea.forwarded_by_assignment[key] = {}
				sea.forwarded_by_assignment[key][resource] = float(sea.forwarded_by_assignment[key].get(resource, 0.0)) + float(delivery.cargo[resource])
	delivery.status = "ONBOARD"
	delivery.loaded_at = _state.time
	return true

func cancel_land_reservation(id: String) -> void:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status != "RESERVED_AT_SOURCE":
		return
	for resource: String in delivery.cargo:
		_reserved[delivery.source_ref][resource] -= float(delivery.cargo[resource])
	delivery.cargo = {}
	delivery.status = "CANCELLED_BEFORE_LOADING"
	if delivery.request_id != "":
		_requests[delivery.request_id].status = "REQUESTED"

func lose_land_cargo(id: String, fraction: float, position: Dictionary) -> void:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status not in ["ONBOARD", "STRANDED"]:
		return
	if not delivery.has("lost_cargo"):
		delivery.lost_cargo = {}
	for resource: String in delivery.cargo:
		var lost: float = float(delivery.cargo[resource]) * clampf(fraction, 0.0, 1.0)
		delivery.cargo[resource] -= lost
		delivery.lost_cargo[resource] = float(delivery.lost_cargo.get(resource, 0.0)) + lost
		_state.logistics_ledger.cargo_lost[resource] += lost
		if not str(delivery.get("request_id", "")).is_empty() and resource == _requests[delivery.request_id].get("resource_class", ""):
			var request: Dictionary = _requests[delivery.request_id]
			request.confirmed_loss_quantity = float(request.get("confirmed_loss_quantity", 0.0)) + lost
	delivery.actual_position = position.duplicate(true)

func receive_land(id: String) -> Dictionary:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status != "ONBOARD":
		return _reject("actual_loaded_land_cargo_required")
	var recipients: Dictionary = _recipients(str(delivery.recipient_kind), str(delivery.recipient_ref), false)
	if not recipients.ok:
		return recipients
	if recipients.has("depot"):
		if _depots[recipients.depot].get("node_ref", "") != delivery.required_node:
			return _reject("actual_depot_handover_node_required")
	else:
		var unit: Dictionary = _lod.preview_leaf(str(delivery.recipient_ref))
		if not unit.has("spatial") or unit.spatial.node != delivery.required_node or str(unit.spatial.edge) != "" or float(unit.effective) <= 0.0:
			return _reject("recipient_waits_for_actual_rendezvous")
		if _state.spatial_port != null:
			var space: RefCounted = _state.spatial_port.get_ref()
			if str(unit.spatial.get("local_edge", "")) != "" or space._distance(space.xy(unit), space._nodes[delivery.required_node].xy) > 0.000001:
				return _reject("physical_delivery_requires_actual_declared_road_handover_point")
		for resource: String in delivery.cargo:
			if not _resource_compatible(recipients, resource):
				return _reject("recipient_resource_capability_required")
		recipients = _recipients(str(delivery.recipient_kind), str(delivery.recipient_ref), true)
	for resource: String in delivery.cargo:
		if recipients.has("depot"):
			_depots[recipients.depot].stock[resource] += float(delivery.cargo[resource])
		else:
			var unit: Dictionary = _state.units[delivery.recipient_ref]
			unit[CLASSES[resource]] += float(delivery.cargo[resource])
			_state.wake(str(unit.area_id))
			if resource == "AMMUNITION":
				_state.totals.ammunition += float(delivery.cargo[resource])
	delivery.received_cargo = delivery.cargo.duplicate()
	delivery.cargo = {}
	delivery.status = "RECEIVED"
	delivery.receipt_time = _state.time
	if delivery.request_id != "":
		var request: Dictionary = _requests[delivery.request_id]
		request.received_quantity = float(request.get("received_quantity", 0.0)) + float(delivery.received_cargo.get(request.resource_class, 0.0))
		request.status = "RECEIVED" if float(request.received_quantity) >= float(request.quantity) - 0.000001 else "REQUESTED"
	recipients.changed = _union(recipients.get("changed", []), recipients.ids)
	if recipients.has("depot"):
		_physical_stock_arrived(str(recipients.depot))
	return recipients

func _physical_stock_arrived(depot: String) -> void:
	if _state.gameplay_port != null:
		_state.gameplay_port.get_ref().air.support.on_depot_stock(depot)
		_state.gameplay_port.get_ref().sea.support.on_depot_stock(depot)
		if _port_sources.has(depot):
			var sea: RefCounted = _state.gameplay_port.get_ref().sea
			for port: Dictionary in sea.support.ports.values():
				if port.depot != depot:
					continue
				var person: String = str(_state.structure_port.get_ref()._positions.get(port.owner, {}).get("person", ""))
				if person.is_empty():
					continue
				var stock: Dictionary = {}
				for resource: String in CLASSES:
					stock[resource] = available_stock(depot, resource)
				_port_report_serial += 1
				var id: String = "port_stock_%d" % _port_report_serial
				var platform: String = str(_port_sources[depot])
				var claim: Dictionary = {"id": id, "source_ref": platform, "subject_kind": "depot", "subject_ref": depot, "fact_kind": "depot_status",
					"value": {"port_ref": port.node, "depot_ref": depot, "node_ref": _depots[depot].node_ref, "available_stock": stock, "busy": port.busy,
						"open": _state.spatial_port.get_ref()._nodes[port.node].get("port_open", true), "observed_at": _state.time, "report_revision": _port_report_serial},
					"observed_at": _state.time, "observer_ref": platform, "origin": "ACTUAL_PORT_STOCK", "quality": 1.0, "precision": "port_warehouse_status"}
				_state.information_port.get_ref().send_platform_report(self, platform, person, id, [claim])

func sea_port_remaining(delivery_ref: String, resource: String, request_ref: String = "", depot: String = "") -> float:
	var delivery: Dictionary = _deliveries.get(delivery_ref, {})
	if delivery.get("status", "") not in ["RECEIVED", "ONBOARD"]:
		return 0.0
	if delivery.has("sea_assignments"):
		var request: String = str(delivery.get("front_request_ref", "")) if request_ref == "" else request_ref
		var warehouse: String = str(_requests.get(request, {}).get("sea_port_depot_ref", delivery.recipient_ref)) if depot == "" else depot
		var key: String = request + ":" + warehouse
		return maxf(0.0, float(delivery.get("unloaded_by_assignment", {}).get(key, {}).get(resource, 0.0)) - float(delivery.get("forwarded_by_assignment", {}).get(key, {}).get(resource, 0.0)))
	return maxf(0.0, float(delivery.get("unloaded_cargo", {}).get(resource, 0.0)) - float(delivery.get("forwarded_cargo", {}).get(resource, 0.0)))

func reduce_uncommitted(actor: String, reference: String, quantity: Variant, apply_change: bool = false) -> Dictionary:
	var request: Dictionary = _requests.get(reference, {})
	if request.get("target_kind", "") != "unit" or not _number(quantity) or float(quantity) < 0.0 or not _allowed(actor, "unit", str(request.get("target", "")), 3):
		return _reject("authorized_existing_unit_request_and_remaining_quantity_required")
	var balance: Dictionary = physical_balance(reference)
	var committed: float = float(request.quantity) - float(balance.uncommitted_quantity)
	if float(quantity) < committed - EPS or float(quantity) > float(request.quantity) + EPS:
		return _reject("only_uncommitted_future_demand_can_be_reduced")
	if apply_change:
		if not request.has("original_quantity"):
			request.original_quantity = request.quantity
		request.quantity = float(quantity)
		request.request_revision = int(request.get("request_revision", 0)) + 1
		request.adjusted_at = _state.time
		if float(quantity) <= float(balance.received_quantity) + EPS:
			request.status = "RECEIVED" if float(quantity) > 0.0 else "CANCELLED"
	return {"ok": true, "request_ref": reference, "quantity": quantity, "committed_quantity": committed}

func physical_balance(request_ref: String) -> Dictionary:
	# A local projection of existing delivery facts; quantities are not another stock.
	var request: Dictionary = _requests.get(request_ref, {})
	if request.get("target_kind", "") != "unit" or not request.has("resource_class"):
		return {}
	var resource: String = str(request.resource_class)
	var sea: Dictionary = _deliveries.get(request.get("sea_delivery_ref", ""), {})
	var land: Dictionary = _deliveries.get(request.get("land_delivery_ref", ""), {})
	var received: float = float(request.get("received_quantity", request.quantity if request.status == "RECEIVED" else 0.0))
	var port: float = sea_port_remaining(str(request.get("sea_delivery_ref", "")), resource, request_ref)
	var afloat: float = float(sea.get("cargo", {}).get(resource, 0.0)) if sea.get("status", "") in ["RESERVED_AT_SOURCE", "ONBOARD"] else 0.0
	if sea.has("sea_assignments"):
		afloat = 0.0
		for vessel: String in sea.sea_assignments:
			if sea.sea_assignments[vessel].request_ref == request_ref:
				afloat += float(sea_carried(str(sea.delivery_id), vessel).get(resource, 0.0))
	var ground: float = float(land.get("cargo", {}).get(resource, 0.0)) if land.get("status", "") in ["RESERVED_AT_SOURCE", "ONBOARD", "STRANDED"] else 0.0
	if land.get("transport_mode", "") == "PORT_LOCAL" and land.get("status", "") != "RECEIVED":
		ground = float(land.get("quantity", 0.0))
	# A LAND reservation at the port overlaps that port batch, until actual loading.
	var committed: float = afloat + port + (ground if land.get("status", "") != "RESERVED_AT_SOURCE" or str(land.get("sea_delivery_ref", "")).is_empty() else 0.0)
	return {"request_ref": request_ref, "status": request.status, "resource_class": resource, "quantity": request.quantity, "received_quantity": received,
		"sea_delivery_ref": request.get("sea_delivery_ref", ""), "sea_status": sea.get("status", ""), "land_delivery_ref": request.get("land_delivery_ref", ""), "land_status": land.get("status", ""),
		"sea_committed": afloat, "port_remaining": port, "land_committed": ground, "confirmed_loss_quantity": request.get("confirmed_loss_quantity", 0.0),
		"uncommitted_quantity": maxf(0.0, float(request.quantity) - received - committed), "port_depot_ref": request.get("sea_port_depot_ref", sea.get("recipient_ref", ""))}

func validate_sea_allocation(actor: String, id: String, source: String, destination: String, cargo: Dictionary) -> Dictionary:
	if id.is_empty() or _used.has(id) or _deliveries.size() >= 128 or source == destination or not _depots.has(source) or not _depots.has(destination) or cargo.is_empty() or cargo.size() > CLASSES.size():
		return _reject("bounded_distinct_existing_sea_depots_required")
	if not _allowed(actor, "depot", source, 3) or not _allowed(actor, "depot", destination, 3):
		return _reject("sea_allocation_outside_depot_authority")
	for resource: Variant in cargo:
		if not resource is String or not CLASSES.has(resource) or not _positive(cargo[resource]) or available_stock(source, str(resource)) + EPS < float(cargo[resource]):
			return _reject("explicit_finite_available_sea_cargo_required")
	return {"ok": true}

func reserve_sea(actor: String, id: String, vessel: String, source: String, destination: String, cargo: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_sea_allocation(actor, id, source, destination, cargo)
	if not valid.ok:
		return valid
	if not _reserved.has(source):
		_reserved[source] = {}
	for resource: String in cargo:
		_reserved[source][resource] = float(_reserved[source].get(resource, 0.0)) + float(cargo[resource])
	_requests[id] = {"id": id, "actor": actor, "target_kind": "depot", "target": destination, "status": "ALLOCATED_SEA", "cargo": cargo.duplicate(), "issue_time": _state.time}
	_deliveries[id] = {"delivery_id": id, "request_id": id, "source_ref": source, "recipient_ref": destination, "recipient_kind": "depot",
		"vessel_ref": vessel, "transport_mode": "SEA", "status": "RESERVED_AT_SOURCE", "cargo": cargo.duplicate(),
		"requested_cargo": cargo.duplicate(), "allocation_actor": actor, "issue_time": _state.time}
	_used[id] = true
	return {"ok": true, "delivery": _deliveries[id]}

func load_sea(id: String) -> bool:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status != "RESERVED_AT_SOURCE":
		return false
	var depot: String = str(delivery.source_ref)
	for resource: String in delivery.cargo:
		if float(_depots[depot].stock[resource]) + EPS < float(delivery.cargo[resource]):
			return false
	for resource: String in delivery.cargo:
		_reserved[depot][resource] -= float(delivery.cargo[resource])
		_depots[depot].stock[resource] -= float(delivery.cargo[resource])
	delivery.status = "ONBOARD"
	delivery.loaded_at = _state.time
	return true

func cancel_sea_reservation(id: String) -> void:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status != "RESERVED_AT_SOURCE":
		return
	for resource: String in delivery.cargo:
		_reserved[delivery.source_ref][resource] -= float(delivery.cargo[resource])
	delivery.cargo = {}
	delivery.status = "CANCELLED_BEFORE_LOADING"
	_requests[id].status = delivery.status

func sea_carried(id: String, vessel: String) -> Dictionary:
	var delivery: Dictionary = _deliveries[id]
	if delivery.has("cargo_by_vessel"):
		return delivery.cargo_by_vessel.get(vessel, {}).duplicate()
	return delivery.cargo.duplicate() if str(delivery.vessel_ref) == vessel else {}

func sea_assignment(id: String, vessel: String) -> Dictionary:
	var delivery: Dictionary = _deliveries[id]
	return delivery.get("sea_assignments", {}).get(vessel, {"request_ref": delivery.get("front_request_ref", ""), "recipient_ref": delivery.recipient_ref}).duplicate(true)

func reassign_sea(actor: String, id: String, vessel: String, request_ref: String, depot: String, command: String) -> Dictionary:
	var delivery: Dictionary = _deliveries[id]
	var cargo: Dictionary = sea_carried(id, vessel)
	var previous: Dictionary = sea_assignment(id, vessel)
	var request: Dictionary = _requests.get(request_ref, {})
	if delivery.status != "ONBOARD" or cargo.is_empty() or not _allowed(actor, "depot", depot, 3) or request.get("target_kind", "") != "unit" or not _allowed(actor, "unit", str(request.get("target", "")), 3) or cargo.size() != 1 or not cargo.has(request.get("resource_class", "")):
		return _reject("compatible_actual_onboard_portion_and_request_authority_required")
	if previous.request_ref == request_ref and previous.recipient_ref == depot:
		return _reject("cargo_already_has_this_assignment")
	if delivery.get("assignment_history", []).size() >= 8:
		return _reject("finite_cargo_assignment_revision_capacity")
	var quantity: float = float(cargo[request.resource_class])
	if quantity <= EPS:
		return _reject("positive_actual_carried_portion_required")
	var balance: Dictionary = physical_balance(request_ref)
	if previous.request_ref != request_ref and (request.status != "REQUESTED" or quantity > float(balance.uncommitted_quantity) + EPS or float(balance.sea_committed) + float(balance.port_remaining) + float(balance.land_committed) > EPS):
		return _reject("uncommitted_existing_new_request_required")
	if previous.request_ref != "" and not _allowed(actor, "unit", str(_requests[previous.request_ref].target), 3):
		return _reject("old_request_responsibility_outside_current_command")
	# One request retains one receiving warehouse while any of its goods are pending.
	if previous.request_ref == request_ref and previous.recipient_ref != depot:
		var others: float = float(balance.sea_committed) + float(balance.port_remaining) - quantity
		if others > EPS or float(balance.land_committed) > EPS:
			return _reject("other_portions_or_ground_handover_keep_original_request_port")
	return {"ok": true, "cargo": cargo, "previous": previous, "quantity": quantity, "request_ref": request_ref, "depot_ref": depot, "command_ref": command}

func apply_sea_reassignment(id: String, vessel: String, assignment: Dictionary) -> void:
	var delivery: Dictionary = _deliveries[id]
	if not delivery.has("sea_assignments"):
		delivery.sea_assignments = {}
		if not delivery.has("cargo_by_vessel"):
			delivery.cargo_by_vessel = {delivery.vessel_ref: delivery.cargo.duplicate()}
		for carrier: String in delivery.cargo_by_vessel:
			delivery.sea_assignments[carrier] = {"request_ref": delivery.get("front_request_ref", ""), "recipient_ref": delivery.recipient_ref}
		var old_key: String = str(delivery.get("front_request_ref", "")) + ":" + str(delivery.recipient_ref)
		delivery.unloaded_by_assignment = {old_key: delivery.get("unloaded_cargo", {}).duplicate()}
		delivery.forwarded_by_assignment = {old_key: delivery.get("forwarded_cargo", {}).duplicate()}
		delivery.assignment_history = []
		delivery.request_baselines = {}
	var previous: Dictionary = assignment.previous
	for ref: String in [str(previous.request_ref), str(assignment.request_ref)]:
		if ref == "" or delivery.request_baselines.has(ref):
			continue
		var request: Dictionary = _requests[ref]
		delivery.request_baselines[ref] = {"received": request.get("received_quantity", 0.0), "loss": request.get("confirmed_loss_quantity", 0.0), "quantity": request.quantity,
			"manifest": delivery.requested_cargo.duplicate() if ref == delivery.get("front_request_ref", "") else {}}
		if ref == delivery.get("front_request_ref", ""):
			delivery.request_baselines[ref].received = delivery.get("received_before_batch", 0.0)
			delivery.request_baselines[ref].loss = delivery.get("loss_before_batch", 0.0)
	delivery.sea_assignments[vessel] = {"request_ref": assignment.request_ref, "recipient_ref": assignment.depot_ref}
	delivery.assignment_history.append({"id": assignment.command_ref, "vessel_ref": vessel, "old_request_ref": previous.request_ref, "request_ref": assignment.request_ref,
		"old_depot_ref": previous.recipient_ref, "depot_ref": assignment.depot_ref, "cargo": assignment.cargo.duplicate(), "at": _state.time})
	delivery.carriage_revision = int(delivery.get("carriage_revision", 0)) + 1
	var request: Dictionary = _requests[assignment.request_ref]
	request.sea_delivery_ref = id
	request.sea_required = true
	request.sea_port_depot_ref = assignment.depot_ref

func transfer_sea_cargo(id: String, source: String, recipient: String, cargo: Dictionary) -> bool:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status != "ONBOARD" or source == recipient:
		return false
	if delivery.has("sea_assignments"):
		var receiving_quantity: float = 0.0
		for amount: Variant in sea_carried(id, recipient).values():
			receiving_quantity += float(amount)
		if receiving_quantity > EPS and sea_assignment(id, source) != sea_assignment(id, recipient):
			return false
		delivery.sea_assignments[recipient] = sea_assignment(id, source)
	var carried: Dictionary = sea_carried(id, source)
	for resource: String in cargo:
		if not CLASSES.has(resource) or not _positive(cargo[resource]) or float(cargo[resource]) > float(carried.get(resource, 0.0)) + EPS:
			return false
	if not delivery.has("cargo_by_vessel"):
		delivery.cargo_by_vessel = {source: delivery.cargo.duplicate()}
	if not delivery.cargo_by_vessel.has(recipient):
		delivery.cargo_by_vessel[recipient] = {}
	for resource: String in cargo:
		delivery.cargo_by_vessel[source][resource] -= float(cargo[resource])
		delivery.cargo_by_vessel[recipient][resource] = float(delivery.cargo_by_vessel[recipient].get(resource, 0.0)) + float(cargo[resource])
	# cargo remains the aggregate of this same delivery, not a new reservation.
	delivery.carriage_revision = int(delivery.get("carriage_revision", 0)) + 1
	return true

func _sea_result(delivery: Dictionary) -> void:
	var remaining: float = 0.0
	for amount: float in delivery.cargo.values():
		remaining += amount
	if remaining > EPS:
		delivery.status = "ONBOARD"
	else:
		delivery.status = "RECEIVED" if not delivery.get("unloaded_cargo", {}).is_empty() else "RETURNED_TO_SOURCE" if not delivery.get("returned_cargo", {}).is_empty() else "LOST_WITH_VESSEL"
	_requests[delivery.request_id].status = "SEA_PORTIONS_SETTLED" if delivery.has("sea_assignments") and remaining <= EPS else delivery.status

func unload_sea(id: String, depot: String, vessel: String = "") -> bool:
	var delivery: Dictionary = _deliveries[id]
	var carrier: String = str(delivery.vessel_ref) if vessel.is_empty() else vessel
	var assignment: Dictionary = sea_assignment(id, carrier)
	if delivery.status != "ONBOARD" or depot not in [delivery.source_ref, assignment.recipient_ref]:
		return false
	var cargo: Dictionary = sea_carried(id, carrier)
	if cargo.is_empty():
		return false
	var field: String = "unloaded_cargo" if depot == assignment.recipient_ref else "returned_cargo"
	if not delivery.has(field):
		delivery[field] = {}
	for resource: String in cargo:
		_depots[depot].stock[resource] += float(cargo[resource])
		delivery[field][resource] = float(delivery[field].get(resource, 0.0)) + float(cargo[resource])
		if delivery.has("sea_assignments") and field == "unloaded_cargo":
			var key: String = str(assignment.request_ref) + ":" + depot
			if not delivery.unloaded_by_assignment.has(key):
				delivery.unloaded_by_assignment[key] = {}
			delivery.unloaded_by_assignment[key][resource] = float(delivery.unloaded_by_assignment[key].get(resource, 0.0)) + float(cargo[resource])
		delivery.cargo[resource] = maxf(0.0, float(delivery.cargo[resource]) - float(cargo[resource]))
	if delivery.has("cargo_by_vessel"):
		delivery.cargo_by_vessel.erase(carrier)
	_sea_result(delivery)
	delivery.receipt_time = _state.time
	_physical_stock_arrived(depot)
	return true

func lose_sea_cargo(id: String, cause: String, vessel: String = "") -> void:
	var delivery: Dictionary = _deliveries[id]
	if delivery.status == "RESERVED_AT_SOURCE":
		cancel_sea_reservation(id)
		return
	if delivery.status != "ONBOARD":
		return
	var carrier: String = str(delivery.vessel_ref) if vessel.is_empty() else vessel
	var cargo: Dictionary = sea_carried(id, carrier)
	if not delivery.has("lost_cargo"):
		delivery.lost_cargo = {}
	for resource: String in cargo:
		delivery.lost_cargo[resource] = float(delivery.lost_cargo.get(resource, 0.0)) + float(cargo[resource])
		_state.logistics_ledger.cargo_lost[resource] += float(cargo[resource])
		var original: String = str(sea_assignment(id, carrier).request_ref)
		if not original.is_empty() and _requests[original].get("resource_class", "") == resource:
			_requests[original].confirmed_loss_quantity = float(_requests[original].get("confirmed_loss_quantity", 0.0)) + float(cargo[resource])
		delivery.cargo[resource] = maxf(0.0, float(delivery.cargo[resource]) - float(cargo[resource]))
	if delivery.has("cargo_by_vessel"):
		delivery.cargo_by_vessel.erase(carrier)
	_sea_result(delivery)
	delivery.loss_time = _state.time
	delivery.cause_ref = cause

func allocate_port_local(actor: String, id: String, request_id: String, depot: String, node: String, due: float, notify: Array = []) -> Dictionary:
	if not _requests.has(request_id) or _requests[request_id].status != "REQUESTED" or _requests[request_id].target_kind != "unit" or not _depots.has(depot) or _depots[depot].get("node_ref", "") != node or not _lod.has_leaf(str(_requests[request_id].target)):
		return _reject("waiting_unit_request_and_actual_port_depot_required")
	var unit: Dictionary = _lod.preview_leaf(str(_requests[request_id].target))
	if not unit.has("spatial") or unit.spatial.node != node or not str(unit.spatial.edge).is_empty():
		return _reject("cargo_stays_in_port_until_unit_reaches_supply_node")
	var allocation: Dictionary = submit(actor, {"id": id, "kind": "allocate", "request_id": request_id, "source_ref": depot, "delivery_time": due})
	if allocation.ok:
		_deliveries[id].transport_mode = "PORT_LOCAL"
		_deliveries[id].required_node = node
		_deliveries[id].report_recipients = notify.duplicate()
	return allocation

func admit_port_report_source(depot: String, platform: String, owner: String) -> bool:
	if _state.time != 0.0 or not _depots.has(depot) or _port_sources.has(depot):
		return false
	if not _state.information_port.get_ref().register_platform_source(platform, owner, self):
		return false
	_port_sources[depot] = platform
	return true

func _report_port_receipt(delivery: Dictionary) -> void:
	if delivery.get("transport_mode", "") != "PORT_LOCAL" or not _port_sources.has(delivery.source_ref):
		return
	var recipients: Array = delivery.get("report_recipients", []).duplicate()
	for recipient: String in [str(delivery.allocation_actor), str(_requests[delivery.request_id].actor)]:
		if recipient not in recipients:
			recipients.append(recipient)
	var platform: String = str(_port_sources[delivery.source_ref])
	for recipient: String in recipients:
		_port_report_serial += 1
		var id: String = "port_supply_report_%d" % _port_report_serial
		var claim: Dictionary = {"id": id, "source_ref": platform, "subject_kind": "unit", "subject_ref": delivery.recipient_ref,
			"fact_kind": "supply_status", "value": {"node_ref": delivery.required_node, "delivery_ref": delivery.delivery_id, "request_ref": delivery.request_id,
				"transport_ref": _requests[delivery.request_id].get("sea_delivery_ref", ""), "status": delivery.status,
				"resource_class": delivery.resource_class, "quantity": delivery.quantity if delivery.status == "RECEIVED" else 0.0, "request_balance": physical_balance(str(delivery.request_id))},
			"observed_at": _state.time, "observer_ref": platform, "origin": "PORT_SUPPLY_HANDOVER", "quality": 1.0, "precision": "actual_local_receipt"}
		_state.information_port.get_ref().send_platform_report(self, platform, recipient, id, [claim])

func audit() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	# Explicit diagnostic export; this global scan is never a resolver dependency.
	var mass: Dictionary = {"AMMUNITION": 0.0, "FUEL": 0.0, "SPARES": 0.0, "MEDICAL": 0.0}
	for id: String in _depots:
		for resource: String in CLASSES:
			mass[resource] += float(_depots[id].stock[resource])
	for id: String in _deliveries:
		var delivery: Dictionary = _deliveries[id]
		if delivery.status == "IN_TRANSIT":
			mass[delivery.resource_class] += float(delivery.quantity)
		elif delivery.get("transport_mode", "") == "SEA" and delivery.status == "ONBOARD":
			for resource: String in delivery.cargo:
				mass[resource] += float(delivery.cargo[resource])
	for id: String in _state.units:
		var unit: Dictionary = _state.units[id]
		mass.AMMUNITION += float(unit.ammunition) + float(unit.ammo_spent)
		mass.FUEL += float(unit.get("fuel", 0.0)) + float(unit.get("fuel_spent", 0.0))
		mass.SPARES += float(unit.get("spares", 0.0)) + float(unit.get("spares_spent", 0.0))
		mass.MEDICAL += float(unit.get("medical", 0.0)) + float(unit.get("medical_spent", 0.0))
	for stock: Dictionary in _assets.values():
		mass.AMMUNITION += float(stock.ammunition) + float(stock.ammo_spent)
		mass.FUEL += float(stock.fuel) + float(stock.fuel_spent)
		mass.SPARES += float(stock.spares) + float(stock.spares_spent)
	for resource: String in CLASSES:
		mass[resource] += float(_state.logistics_ledger.get("cargo_lost", {}).get(resource, 0.0))
	return {"initial": _initial.duplicate(), "current_plus_spent_and_transit": mass}

func snapshot() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	return {"time": _state.time, "depots": _depots.duplicate(true), "maintenance_capacities": _capacities.duplicate(true),
		"requests": _requests.duplicate(true), "deliveries": _deliveries.duplicate(true), "maintenance": _maintenance.duplicate(true),
		"history": history.duplicate(true), "initial": _initial.duplicate(), "ledger": _state.logistics_ledger.duplicate(), "work": work.duplicate()}

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0

static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0

static func _keys(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if key not in allowed:
			return false
	return true

static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}

static func _union(a: Array, b: Array) -> Array[String]:
	var result: Dictionary = {}
	for id: String in a + b:
		result[id] = true
	return State.sorted_ids(result)

const RUNTIME_FIELDS: Array[String] = ["_depots", "_capacities", "_requests", "_deliveries", "_maintenance", "_used", "_paths", "_node_reps", "_rep_counts", "_initial", "_assets", "_reserved", "_port_sources", "_port_report_serial", "history", "work"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)

func bind_runtime(state: State, lod: RefCounted, structure: RefCounted) -> void:
	_state = state
	_lod = lod
	_structure = structure
	state.logistics_port = weakref(self)
