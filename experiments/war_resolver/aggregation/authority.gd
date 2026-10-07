extends RefCounted
## Owns one BattleState/time. Suspended leaf images are explicitly unresolved,
## not another current state. No caller receives the settlement capability.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Kernel = preload("res://experiments/war_resolver/aggregation/indexed_resolver.gd")
const Spatial = preload("res://experiments/war_resolver/aggregation/spatial_hierarchy.gd")
const AdvanceWork = preload("res://experiments/war_resolver/continuous/advance_work.gd")
const STOCKS: Array[String] = Spatial.STOCKS
const CONDITIONS: Array[String] = ["readiness", "fatigue", "cohesion", "suppression", "mobility"]
const LEVELS: Array[String] = ["platoon", "company", "battalion"]
const POSITION_SPAN_KM: float = 0.02
const CONDITION_SPREAD: float = 0.02
var work: Dictionary = {"formations_built": 0, "formation_records_examined": 0,
	"leaf_records_examined": 0, "leaf_records_materialized": 0, "input_leaf_records_examined": 0}
var spatial: Spatial = Spatial.new()
var _state: State
var _token: RefCounted = RefCounted.new()
var _kernel: Kernel = Kernel.new()
var _owners: Dictionary = {}
var _groups: Dictionary = {}
var _area_groups: Dictionary = {}
var _serial: int = 0
var _generations: Dictionary = {}
var _observed_areas: Dictionary = {}
var materialization_events: Array[Dictionary] = []
var _continuation: AdvanceWork = null
var _last_continuation: AdvanceWork = null
var physical_event_sink: Callable

func configure(state: State) -> bool:
	if _state != null or state.settlement_owner != null:
		return false
	_state = state
	_state.settlement_owner = _token
	_state.materialization_port = weakref(self)
	_state.lod_work = work
	spatial.configure()
	spatial.settlement_state = weakref(state)
	_observed_areas = state.active_areas.duplicate()
	# Synthetic hierarchy admission is input work, never an hourly global scan.
	for cell: String in spatial.leaf_descendants("region_50"):
		if state.areas.has(cell):
			var stocks: Dictionary = {}
			for key: String in stock_keys():
				stocks[key] = 0.0
			for id: String in state.area_units[cell]:
				work.input_leaf_records_examined += 1
				for key: String in stock_keys():
					stocks[key] += float(state.units[id][key])
			spatial.update_leaf(cell, stocks, str(state.areas[cell].control))
	spatial.clear_dirty()
	spatial.counters = {"spatial_nodes_examined": 0, "parent_nodes_updated": 0}
	return true

func stock_keys() -> Array[String]:
	return STOCKS + _state.logistics_port.get_ref().EXTRA_STOCKS if _state.logistics_port != null else STOCKS

func owns_state(state: State) -> bool:
	return state == _state

func has_leaf(id: String) -> bool:
	return _state.units.has(id) and not _state.units[id].has("contact_weight") or _owners.has(id)

func coalesce(source_formation: String, leaf_ids: Array[String], level: String = "company") -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state == null or source_formation.is_empty() or level not in LEVELS or leaf_ids.size() < 2:
		return {"ok": false, "error": "invalid_cohort"}
	if _state.structure_port != null and not _state.structure_port.get_ref().can_coalesce(source_formation, leaf_ids):
		return {"ok": false, "error": "outside_effective_formation"}
	var ids: Array[String] = leaf_ids.duplicate()
	ids.sort()
	var images: Dictionary = {}
	var first: Dictionary = {}
	var mission: Dictionary = {}
	var total_personnel: float = 0.0
	for id: String in ids:
		work.leaf_records_examined += 1
		if images.has(id) or not _state.units.has(id) or _state.units[id].has("contact_weight"):
			return {"ok": false, "error": "leaf_not_detailed"}
		var unit: Dictionary = _state.units[id]
		var current: Dictionary = _state.missions[unit.mission_id]
		# Dependencies and pending local ownership remain detailed. No index migration.
		if _state.coordination.has(id) or _state.tactical_intents.has(id) or _state.command_coordination.has(id) or not str(current.destination).is_empty() or not (_state.mission_dependents.get(unit.mission_id, {}) as Dictionary).is_empty():
			return {"ok": false, "error": "causal_detail_required"}
		if first.is_empty():
			first = unit
			mission = current
		for key: String in ["side", "area_id", "weapon", "type"]:
			if unit[key] != first[key]:
				return {"ok": false, "error": "incompatible_cohort"}
		if _state.logistics_port != null and not _state.logistics_port.get_ref().compatible(unit, first, true):
			return {"ok": false, "error": "supply_profile_requires_detail"}
		if unit.get("spatial", {}) != first.get("spatial", {}):
			return {"ok": false, "error": "spatial_route_requires_detail"}
		if not is_equal_approx(float(unit.mobility), float(first.mobility)):
			return {"ok": false, "error": "incompatible_mobility"}
		# A footprint must not straddle a weapon boundary. This v0 admits a small
		# spread only when the weapon covers the entire uniform input cell.
		if absf(float(unit.position) - float(first.position)) > POSITION_SPAN_KM or unit.position != first.position and float(unit.weapon.range_km) < float(_state.areas[unit.area_id].size_km):
			return {"ok": false, "error": "footprint_requires_detail"}
		for key: String in ["posture", "objective", "direction", "status", "stop_suppression", "withdraw_cohesion"]:
			if current[key] != mission[key]:
				return {"ok": false, "error": "incompatible_mission"}
		for key: String in ["readiness", "fatigue", "cohesion", "suppression"]:
			if absf(float(unit.get(key, 0.0)) - float(first[key])) > CONDITION_SPREAD:
				return {"ok": false, "error": "condition_requires_detail"}
		for key: String in ["effective", "equipment", "ammunition"]:
			var ratio: float = float(unit.get(key, 0.0)) / maxf(1.0, float(unit.personnel_total))
			var reference_ratio: float = float(first[key]) / maxf(1.0, float(first.personnel_total))
			if absf(ratio - reference_ratio) > maxf(1.0, reference_ratio) * CONDITION_SPREAD or (float(unit.get(key, 0.0)) <= 0.000001) != (float(first[key]) <= 0.000001):
				return {"ok": false, "error": "stock_profile_requires_detail"}
		if (float(unit.effective) <= Kernel.SLEEP_EPSILON) != (float(first.effective) <= Kernel.SLEEP_EPSILON) or (float(unit.suppression) >= float(current.stop_suppression)) != (float(first.suppression) >= float(mission.stop_suppression)) or (float(unit.cohesion) < float(current.withdraw_cohesion)) != (float(first.cohesion) < float(mission.withdraw_cohesion)):
			return {"ok": false, "error": "threshold_requires_detail"}
		images[id] = unit.duplicate(true)
		total_personnel += float(unit.personnel_total)
	if total_personnel <= 0.0:
		return {"ok": false, "error": "empty_stock"}
	var basis: String = (source_formation + ":" + ":".join(ids)).sha256_text().substr(0, 16)
	var generation: int = int(_generations.get(basis, 0)) + 1
	var aggregate_id: String = "aggregate_" + basis + "_%06d" % generation
	if _state.identity_reserved(aggregate_id) or _state.missions.has(aggregate_id + "_mission"):
		return {"ok": false, "error": "representation_id_collision"}
	_serial += 1
	_generations[basis] = generation
	var aggregate: Dictionary = first.duplicate(true)
	aggregate.id = aggregate_id
	aggregate.source_formation_id = source_formation
	aggregate.spatial_node = first.area_id
	aggregate.resolution_level = level
	aggregate.contact_weight = 0.0
	aggregate.range_envelope_km = first.weapon.range_km
	aggregate.suppression_capability = Kernel.SUPPRESSION_PER_ROUND
	for key: String in stock_keys():
		aggregate[key] = 0.0
	for key: String in CONDITIONS:
		aggregate[key] = 0.0
	aggregate.distance_moved = 0.0
	aggregate.position = 0.0
	for id: String in ids:
		var unit: Dictionary = images[id]
		aggregate.contact_weight += float(unit.get("tactical_weight", 1.0))
		work.leaf_records_examined += 1
		for key: String in stock_keys():
			aggregate[key] += float(unit.get(key, 0.0))
		for key: String in CONDITIONS:
			aggregate[key] += float(unit.get(key, 0.0)) * float(unit.personnel_total)
		aggregate.distance_moved += float(unit.distance_moved) * float(unit.personnel_total)
		aggregate.position += float(unit.position) * float(unit.personnel_total)
	for key: String in CONDITIONS:
		aggregate[key] /= float(aggregate.personnel_total)
	aggregate.distance_moved /= float(aggregate.personnel_total)
	aggregate.position /= float(aggregate.personnel_total)
	var aggregate_mission: Dictionary = mission.duplicate(true)
	aggregate_mission.id = aggregate_id + "_mission"
	aggregate.mission_id = aggregate_mission.id
	_state.add_mission(aggregate_mission)
	_groups[aggregate_id] = {"leaf_refs": images, "base": aggregate.duplicate(true),
		"suspended_at": _state.time, "distribution": "unresolved_proportional_stock_deltas"}
	if not _area_groups.has(first.area_id):
		_area_groups[first.area_id] = {}
	_area_groups[first.area_id][aggregate_id] = true
	for id: String in ids:
		_owners[id] = aggregate_id
		_state.units.erase(id)
		_state.area_units[first.area_id].erase(id)
	_state.units[aggregate_id] = aggregate
	_state.area_units[first.area_id][aggregate_id] = true
	_state.contacts.erase(first.area_id)
	_state.wake(str(first.area_id))
	if _state.logistics_port != null:
		_state.logistics_port.get_ref().on_coalesce(aggregate_id, ids)
	work.formations_built += 1
	return {"ok": true, "aggregate_id": aggregate_id, "leaf_count": ids.size(), "time": _state.time}

func preview_leaf(id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	work.leaf_records_examined += 1
	if _state.units.has(id):
		return _state.units[id].duplicate(true)
	if not _owners.has(id):
		return {}
	var aggregate_id: String = str(_owners[id])
	var group: Dictionary = _groups[aggregate_id]
	var base: Dictionary = group.base
	var macro: Dictionary = _state.units[aggregate_id]
	work.formation_records_examined += 2 # Current and frozen base; no authority mutation.
	var result: Dictionary = group.leaf_refs[id].duplicate(true)
	for pair: Array in [["effective", "casualties"], ["equipment", "equipment_lost"], ["ammunition", "ammo_spent"]]:
		var stock: String = str(pair[0])
		var spent: String = str(pair[1])
		var share: float = float(result[stock]) / float(base[stock]) if float(base[stock]) > 0.0 else 0.0
		var loss: float = minf(float(result[stock]), maxf(0.0, float(macro[spent]) - float(base[spent])) * share)
		result[stock] -= loss
		result[spent] += loss
	if macro.has("supply_capability"):
		var share: float = float(result.personnel_total) / float(base.personnel_total)
		for key: String in stock_keys():
			result[key] = float(macro.get(key, 0.0)) * share
	# Readiness/mobility are immutable capabilities in this kernel. Only elapsed
	# fatigue/cohesion/suppression changes are allocated; do not add roundoff to them.
	for key: String in ["fatigue", "cohesion", "suppression"]:
		result[key] = clampf(float(result[key]) + float(macro[key]) - float(base[key]), 0.0, 1.0)
	result.position = clampf(float(result.position) + float(macro.position) - float(base.position), 0.0, float(_state.areas[result.area_id].size_km))
	if macro.has("spatial"):
		# Admission requires the exact same route footprint. Its current progress
		# is intensive state, not a replay of the frozen member's initial path.
		result.spatial = macro.spatial.duplicate(true)
		result.area_id = macro.area_id
		result.position = macro.position
	result.distance_moved += float(macro.distance_moved) - float(base.distance_moved)
	result.action = macro.action
	result.resolved_through = _state.time
	result.unresolved_history = {"from": group.suspended_at, "to": _state.time,
		"allocation": group.distribution, "no_individual_contact_history": true}
	return result

func read_leaf(id: String) -> Dictionary:
	var result: Dictionary = materialize_leaf(id, "causal_leaf_query")
	return _state.units[id].duplicate(true) if result.ok else result

func materialize_leaf(id: String, reason: String = "leaf_query") -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if _state.units.has(id) and not _state.units[id].has("contact_weight"):
		return {"ok": true, "materialized": 0}
	if not _owners.has(id):
		return {"ok": false, "error": "unknown_leaf"}
	var aggregate_id: String = str(_owners[id])
	var group: Dictionary = _groups[aggregate_id]
	var macro: Dictionary = _state.examine_unit(aggregate_id)
	var result: Dictionary = preview_leaf(id)
	var initial: Dictionary = group.leaf_refs[id]
	work.leaf_records_examined += 1
	var macro_weight: float = float(macro.personnel_total)
	var base_weight: float = float(group.base.personnel_total)
	var weight: float = float(result.personnel_total)
	var current_mission: Dictionary = _state.missions[macro.mission_id]
	var leaf_mission: Dictionary = _state.missions[result.mission_id].duplicate(true)
	leaf_mission.id = "materialized_" + aggregate_id + "_" + id
	leaf_mission.status = current_mission.status
	_state.add_mission(leaf_mission)
	result.mission_id = leaf_mission.id
	for key: String in stock_keys():
		macro[key] -= float(result[key])
		group.base[key] -= float(initial.get(key, 0.0))
	for key: String in CONDITIONS + ["distance_moved", "position"]:
		if macro_weight > weight:
			macro[key] = (float(macro[key]) * macro_weight - float(result[key]) * weight) / (macro_weight - weight)
			group.base[key] = (float(group.base[key]) * base_weight - float(initial.get(key, 0.0)) * weight) / (base_weight - weight)
	if _state.logistics_port != null:
		_state.logistics_port.get_ref().on_materialize(id, aggregate_id)
	group.leaf_refs.erase(id)
	_owners.erase(id)
	macro.contact_weight -= float(initial.get("tactical_weight", 1.0))
	_state.units[id] = result
	_state.area_units[result.area_id][id] = true
	work.leaf_records_materialized += 1
	materialization_events.append({"time": _state.time, "leaf_id": id, "reason": reason, "from": aggregate_id})
	if group.leaf_refs.is_empty():
		_state.units.erase(aggregate_id)
		_state.area_units[result.area_id].erase(aggregate_id)
		_area_groups[result.area_id].erase(aggregate_id)
		_groups.erase(aggregate_id)
	_state.contacts.erase(result.area_id)
	_state.wake(str(result.area_id))
	return {"ok": true, "materialized": 1, "resolved_through": _state.time,
		"retired": [aggregate_id] if group.leaf_refs.is_empty() else [],
		"changed": [id] if group.leaf_refs.is_empty() else [id, aggregate_id]}

func zoom_in(cell_id: String) -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	if not spatial.nodes.has(cell_id) or not spatial.nodes[cell_id].children.is_empty():
		return {"ok": false, "error": "requires_one_5km_cell"}
	var count: int = 0
	for aggregate_id: String in State.sorted_ids(_area_groups.get(cell_id, {})):
		var ids: Array[String] = State.sorted_ids(_groups[aggregate_id].leaf_refs)
		for id: String in ids:
			count += int(materialize_leaf(id, "zoom_in").materialized)
	return {"ok": true, "materialized": count, "time": _state.time}

func representation_of(id: String) -> String:
	return str(_owners.get(id, id))

func on_spatial_transfer(id: String, source: String, destination: String) -> void:
	if not _groups.has(id):
		return
	_area_groups[source].erase(id)
	if not _area_groups.has(destination):
		_area_groups[destination] = {}
	_area_groups[destination][id] = true
	_state.units[id].spatial_node = destination

func prepare_event(event: Dictionary) -> Dictionary:
	if event.kind == "spatial":
		return _state.spatial_port.get_ref().process_event(event)
	if event.kind == "decision":
		return _state.decision_port.get_ref().process_event(event)
	if event.kind == "structure":
		var result: Dictionary = _state.structure_port.get_ref().process_event(event)
		if _state.logistics_port != null:
			_state.logistics_port.get_ref().on_structure(result)
		return result
	if event.kind == "communication":
		return _state.information_port.get_ref().process_command(event)
	if event.kind == "logistics":
		return _state.logistics_port.get_ref().process_event(event)
	if event.kind in ["order", "coordination_release"]:
		var id: String = str(event.payload.unit_id)
		if _owners.has(id):
			return materialize_leaf(id, "event_" + str(event.kind))
	return {"retired": [], "changed": []}

func advance(target: float, policy: String = Kernel.DETAILED) -> Dictionary:
	if _state.settlement_pending:
		return _state.pending_view()
	var output: Dictionary = _kernel.resolve_until(_state, target, policy, _token)
	if not output.ok:
		return output
	var changed_areas: Dictionary = {}
	for id: String in output.state_delta.units:
		changed_areas[output.state_delta.units[id].area_id] = true
	for area_id: String in output.state_delta.areas:
		changed_areas[area_id] = true
	for event: Dictionary in output.events:
		if event.kind == "area_transition":
			changed_areas[event.from] = true
			changed_areas[event.to] = true
	for area_id: String in State.sorted_ids(changed_areas):
		_observed_areas[area_id] = true
		if not spatial.nodes.has(area_id):
			continue
		var stocks: Dictionary = {}
		for key: String in stock_keys():
			stocks[key] = 0.0
		for id: String in State.sorted_ids(_state.area_units[area_id]):
			var unit: Dictionary = _state.examine_unit(id)
			for key: String in stock_keys():
				stocks[key] += float(unit.get(key, 0.0))
		spatial.update_leaf(area_id, stocks, str(_state.areas[area_id].control))
	return output

func advance_bounded(target: float, quota: int, policy: String = Kernel.DETAILED) -> Dictionary:
	if quota < 1 or not is_finite(target) or target < _state.time or not Kernel.INTERVALS.has(policy):
		return {"ok": false, "error": "invalid_bounded_request"}
	if _continuation != null and (target != _continuation.target or policy != _continuation.policy):
		return {"ok": false, "error": "pending_request_must_finish"}
	if _continuation == null:
		_continuation = AdvanceWork.new()
		_continuation.configure(_state, _kernel, self, target, policy)
	var output: Dictionary = _continuation.resume(quota)
	if output.status == "COMPLETE":
		_last_continuation = _continuation
		_last_continuation.jobs.clear()
		_last_continuation.job = null
		_last_continuation.sorter = null
		_continuation = null
	return output

func continuation_ticket_page(start: int = 0, limit: int = 64) -> Dictionary:
	if _state.public_pending():
		return _state.pending_view()
	if _last_continuation == null:
		return {"ok": false, "error": "no_finished_continuation"}
	return _last_continuation.ticket_trace.page(start, limit)

func counters() -> Dictionary:
	var result: Dictionary = work.duplicate()
	result.merge(_kernel.work)
	result.merge(spatial.counters)
	result.actual_contacts_resolved = _state.counters.contacts_resolved
	result.segments = _state.counters.segments
	result.events = _state.counters.events_processed
	return result

func macro_summary() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	var sides: Dictionary = {}
	var selected: Dictionary = {}
	for area_id: String in _observed_areas:
		selected.merge(_state.area_units[area_id])
	for id: String in State.sorted_ids(selected):
		var unit: Dictionary = _state.units[id]
		if not sides.has(unit.side):
			sides[unit.side] = {"effective": 0.0, "casualties": 0.0, "ammo_spent": 0.0,
				"equipment_lost": 0.0, "position_weighted": 0.0, "personnel_total": 0.0,
				"complete": 0, "withdrawn": 0}
		var side: Dictionary = sides[unit.side]
		for key: String in ["effective", "casualties", "ammo_spent", "equipment_lost", "personnel_total"]:
			side[key] += float(unit.get(key, 0.0))
		side.position_weighted += float(unit.position) * float(unit.personnel_total)
		var status: String = str(_state.missions[unit.mission_id].status)
		if status in ["complete", "withdrawn"]:
			side[status] += int(unit.get("contact_weight", 1))
	var controls: Dictionary = {}
	for area_id: String in _observed_areas:
		controls[area_id] = _state.areas[area_id].control
	return {"time": _state.time, "sides": sides, "totals": _state.totals.duplicate(), "control": controls}

func snapshot() -> Dictionary:
	if _state != null and _state.public_pending():
		return _state.pending_view()
	var current: Dictionary = _state.snapshot()
	var live_missions: Dictionary = {}
	for id: String in _state.units:
		var mission_id: String = str(_state.units[id].mission_id)
		live_missions[mission_id] = _state.missions[mission_id].duplicate(true)
	current.missions = live_missions
	return {"current": current, "mission_templates_not_current": _state.missions.duplicate(true), "owners": _owners.duplicate(),
		"unresolved": _groups.duplicate(true), "serial": _serial, "generations": _generations.duplicate()}
