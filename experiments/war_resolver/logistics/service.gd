extends RefCounted
## Snapshot admission and bounded stock transactions on the existing world clock.
## Depots are current source facts. BattleState live representations own unit stocks.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const EXTRA_STOCKS: Array[String] = ["fuel", "fuel_spent", "spares", "spares_spent",
	"serviceable_equipment", "damaged_equipment", "wear_damage", "repair_restored"]
const CLASSES: Dictionary = {"AMMUNITION": "ammunition", "FUEL": "fuel", "SPARES": "spares"}
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
		if id.is_empty() or not depot.get("owner_ref") is String or str(depot.owner_ref).is_empty() or not structure.active(str(depot.get("allocation_scope", ""))) or not depot.get("stock") is Dictionary or depot.stock.size() != CLASSES.size():
			return false
		for resource: String in CLASSES:
			if not _nonnegative(depot.stock.get(resource)):
				return false
	for id: String in capacities:
		if not _nonnegative(capacities[id].get("remaining")) or not structure.active(str(capacities[id].get("scope", ""))):
			return false
	_state = state
	_lod = lod
	_structure = structure
	_depots = depots.duplicate(true)
	_capacities = capacities.duplicate(true)
	_initial = {"AMMUNITION": float(state.totals.ammunition), "FUEL": 0.0, "SPARES": 0.0}
	for id: String in State.sorted_ids(facts):
		var unit: Dictionary = state.units[id]
		for key: String in EXTRA_STOCKS:
			unit[key] = float(facts[id].get(key, 0.0))
		unit.supply_capability = facts[id].capability.duplicate(true)
		_initial.FUEL += float(unit.fuel) + float(unit.fuel_spent)
		_initial.SPARES += float(unit.spares) + float(unit.spares_spent)
		_index(id, id, structure._path(str(structure._unit_nodes[id])))
	for id: String in _depots:
		for resource: String in CLASSES:
			_initial[resource] += float(_depots[id].stock[resource])
	state.logistics_ledger = {"fuel_spent": 0.0, "spares_spent": 0.0, "wear_damage": 0.0, "repair_restored": 0.0}
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
		if not _nonnegative(fact.get(key)):
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

func lose_equipment(unit: Dictionary, loss: float) -> void:
	var share: float = float(unit.serviceable_equipment) / float(unit.equipment) if float(unit.equipment) > 0.0 else 0.0
	unit.serviceable_equipment = maxf(0.0, float(unit.serviceable_equipment) - loss * share)
	unit.damaged_equipment = maxf(0.0, float(unit.damaged_equipment) - loss * (1.0 - share))
	if loss > 0.0:
		work.serviceability_records_updated += 1

func consume_activity(unit: Dictionary, plan: Dictionary, distance: float) -> void:
	var fuel_spent: float = minf(float(unit.fuel), distance * float(plan.get("fuel_per_km", 0.0))) if unit.supply_capability.fuel_dependent else 0.0
	unit.fuel -= fuel_spent
	unit.fuel_spent += fuel_spent
	_state.logistics_ledger.fuel_spent += fuel_spent
	var wear: float = float(unit.serviceable_equipment) * minf(1.0, distance * float(unit.supply_capability.wear_per_km))
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
	work.responsibility_queries += 1
	return _structure.relation(str(_structure._unit_nodes.get(unit_id, "")))

func _allowed(person_id: String, target_kind: String, target: String, rank: int) -> bool:
	if not _structure._people.has(person_id):
		return false
	var person: Dictionary = _structure._people[person_id]
	if Roles.ROLES.find(str(person.role)) < rank or not _structure.active(str(person.formation_id)):
		return false
	var node_id: String = str(_structure._unit_nodes.get(target, "")) if target_kind == "unit" else target
	if target_kind == "depot":
		node_id = str(_depots.get(target, {}).get("allocation_scope", ""))
	return _structure._contains(str(person.formation_id), node_id)

func submit(person_id: String, command: Dictionary) -> Dictionary:
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
		if request.status != "REQUESTED" or not _allowed(person_id, str(request.target_kind), str(request.target), 3) or not _allowed(person_id, "depot", str(command.source_ref), 3):
			return _reject("outside_allocation_scope_or_already_allocated")
		var recipients: Dictionary = _recipients(str(request.target_kind), str(request.target), false)
		if not recipients.ok or not _resource_compatible(recipients, str(request.resource_class)):
			return _reject("incompatible_recipient")
		var depot: Dictionary = _depots[command.source_ref]
		work.inventory_records_examined += 1
		if float(depot.stock[request.resource_class]) < float(request.quantity):
			return _reject("insufficient_source_stock")
		var delivery: Dictionary = {"delivery_id": command.id, "source_ref": command.source_ref,
			"recipient_ref": request.target, "recipient_kind": request.target_kind, "resource_class": request.resource_class,
			"quantity": request.quantity, "issue_time": _state.time, "delivery_time": command.delivery_time,
			"status": "IN_TRANSIT", "allocation_actor": person_id, "request_id": request.id}
		_deliveries[command.id] = delivery
		if not _state.schedule_event("logistics_delivery_" + str(command.id), float(command.delivery_time), "logistics", {"delivery_id": command.id}):
			_deliveries.erase(command.id)
			return _reject("schedule_failed")
		depot.stock[request.resource_class] -= float(request.quantity)
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
	work.deliveries_processed += 1
	var recipients: Dictionary = _recipients(str(delivery.recipient_kind), str(delivery.recipient_ref), false)
	if not recipients.ok or not _resource_compatible(recipients, str(delivery.resource_class)):
		delivery.status = "REJECTED_RETURNED"
		delivery.reason = recipients.get("error", "incompatible_capability")
		_depots[delivery.source_ref].stock[delivery.resource_class] += float(delivery.quantity)
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
	return _record(delivery, recipients)

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
		damaged += float(unit.damaged_equipment)
	var capacity: Dictionary = _capacities[request.capacity_ref]
	var valid: bool = float(request.quantity) <= damaged and float(request.quantity) <= float(capacity.remaining) and _structure._contains(str(_structure._people[request.actor].formation_id), str(capacity.scope))
	for id: String in images:
		var unit: Dictionary = images[id]
		var amount: float = float(request.quantity) * float(unit.damaged_equipment) / damaged if damaged > 0.0 else INF
		valid = valid and amount * float(unit.supply_capability.spares_per_repair) <= float(unit.spares)
	if not valid:
		request.status = "REJECTED"
		request.reason = "insufficient_damage_spares_or_capacity"
		return _record(request, {"changed": [], "retired": []})
	recipients = _recipients(str(request.target_kind), str(request.target), true)
	for id: String in recipients.ids:
		var unit: Dictionary = _state.units[id]
		var amount: float = float(request.quantity) * float(unit.damaged_equipment) / damaged
		var cost: float = amount * float(unit.supply_capability.spares_per_repair)
		unit.spares -= cost
		unit.spares_spent += cost
		unit.damaged_equipment -= amount
		unit.serviceable_equipment += amount
		unit.repair_restored += amount
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

func audit() -> Dictionary:
	# Explicit diagnostic export; this global scan is never a resolver dependency.
	var mass: Dictionary = {"AMMUNITION": 0.0, "FUEL": 0.0, "SPARES": 0.0}
	for id: String in _depots:
		for resource: String in CLASSES:
			mass[resource] += float(_depots[id].stock[resource])
	for id: String in _deliveries:
		var delivery: Dictionary = _deliveries[id]
		if delivery.status == "IN_TRANSIT":
			mass[delivery.resource_class] += float(delivery.quantity)
	for id: String in _state.units:
		var unit: Dictionary = _state.units[id]
		mass.AMMUNITION += float(unit.ammunition) + float(unit.ammo_spent)
		mass.FUEL += float(unit.get("fuel", 0.0)) + float(unit.get("fuel_spent", 0.0))
		mass.SPARES += float(unit.get("spares", 0.0)) + float(unit.get("spares_spent", 0.0))
	return {"initial": _initial.duplicate(), "current_plus_spent_and_transit": mass}

func snapshot() -> Dictionary:
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
