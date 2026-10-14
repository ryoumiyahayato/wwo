extends RefCounted
## Four bounded standing-order conditions, indexed by their stable subjects.
var _owner: WeakRef
var _units: Dictionary = {}
var _missions: Dictionary = {}
var _edges: Dictionary = {}
var _notifications: Dictionary = {}
var _serial: int = 0

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func validate(actor: String, unit: Dictionary, dependencies: Variant) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	if not dependencies is Array or dependencies.size() > 4:
		return _reject("bounded_common_dependencies_required")
	var seen: Dictionary = {}
	for item: Variant in dependencies:
		if not item is Dictionary or not item.get("kind") is String:
			return _reject("explicit_dependency_kind_required")
		var key: String = str(item)
		if seen.has(key):
			return _reject("duplicate_dependency")
		seen[key] = true
		if item.kind == "unit_arrived":
			if item.size() != 3 or not item.get("unit_ref") is String or item.unit_ref == unit.id or not g._lod.has_leaf(item.unit_ref) or not item.get("node_ref") is String or not g._known.get(actor, {}).has(item.node_ref):
				return _reject("known_arrival_unit_and_node_required")
			var s: RefCounted = g._state.structure_port.get_ref()
			var prerequisite_unit: Dictionary = g._lod.preview_leaf(item.unit_ref)
			if not prerequisite_unit.has("spatial"):
				return _reject("arrival_dependency_requires_existing_spatial_unit")
			var known: bool = s._contains(str(s.command_person(actor).formation_id), str(s._unit_nodes.get(item.unit_ref, "")))
			for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).entries:
				known = known or claim.subject_ref == item.unit_ref
			if not known or prerequisite_unit.side != unit.side:
				return _reject("arrival_unit_not_in_registered_scope_or_received_reports")
		elif item.kind in ["support_started", "support_complete"]:
			if item.size() != 2 or not item.get("mission_ref") is String or not g._state.missions.has(item.mission_ref) or item.mission_ref == unit.mission_id:
				return _reject("distinct_known_support_task_required")
			var mission: Dictionary = g._state.missions[item.mission_ref]
			var known: bool = mission.get("goal_v1", {}).get("actor", "") == actor
			for claim: Dictionary in g._state.information_port.get_ref().knowledge(actor).entries:
				known = known or claim.claimed_value.get("mission_ref", "") == item.mission_ref
			if not mission.has("goal_v1") or not known:
				return _reject("support_task_not_in_person_received_information")
		elif item.kind == "route_open":
			if item.size() != 2 or not item.get("edge_ref") is String or not g._space._edges.has(item.edge_ref) or not _known_edge(g._known.get(actor, {}), item.edge_ref):
				return _reject("known_route_dependency_required")
		elif item.kind != "new_route" or item.size() != 1:
			return _reject("special_dependency_policy_not_implemented")
	return {"ok": true}

func register(mission: Dictionary) -> void:
	var goal: Dictionary = mission.goal_v1
	for dependency: Dictionary in goal.dependencies:
		dependency.satisfied = false
		var index: Dictionary = _index(dependency.kind)
		var subject: String = _subject(dependency)
		if subject.is_empty():
			continue
		if not index.has(subject):
			index[subject] = {}
		index[subject][mission.id] = true

func unregister(mission: Dictionary) -> void:
	for dependency: Dictionary in mission.goal_v1.get("dependencies", []):
		var index: Dictionary = _index(dependency.kind)
		var subject: String = _subject(dependency)
		if index.has(subject):
			index[subject].erase(mission.id)
			if index[subject].is_empty():
				index.erase(subject)
	_notifications.erase(mission.id)

func status(unit: Dictionary, mission: Dictionary) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var waiting: String = ""
	for dependency: Dictionary in mission.goal_v1.get("dependencies", []):
		if dependency.get("satisfied", false):
			continue
		var ready: bool = false
		if dependency.kind == "unit_arrived":
			if not g._lod.has_leaf(dependency.unit_ref):
				return {"state": "IMPOSSIBLE", "reason": "arrival_unit_retired"}
			var other: Dictionary = g._lod.preview_leaf(dependency.unit_ref)
			if float(other.effective) <= 0.000001:
				return {"state": "IMPOSSIBLE", "reason": "arrival_unit_incapacitated"}
			# The executor observes a rendezvous locally; no hidden remote coordinates.
			var arrived: bool = str(other.spatial.edge).is_empty() and other.spatial.node == dependency.node_ref
			arrived = arrived or float(dependency.get("arrived_at", -1.0)) >= float(mission.goal_v1.started_at)
			ready = arrived and g._space.observation(unit, other) > 0.0
		elif dependency.kind in ["support_started", "support_complete"]:
			var support: Dictionary = g._state.missions[dependency.mission_ref]
			ready = support.status == "complete" if dependency.kind == "support_complete" else (support.goal_v1.get("support_started", false) or support.status == "complete")
			if not ready and support.status in ["failed", "cancelled", "withdrawn"]:
				return {"state": "IMPOSSIBLE", "reason": "support_task_ended_without_prerequisite"}
		elif dependency.kind == "route_open":
			# This standing condition uses the same passage fact as actual movement.
			ready = bool(g._space._edges[dependency.edge_ref].open)
		if not ready:
			if waiting.is_empty():
				waiting = "waiting_" + str(dependency.kind)
		else:
			dependency.satisfied = true
	return {"state": "READY" if waiting.is_empty() else "WAITING", "reason": waiting}

func on_goal(record: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	var unit_id: String = str(record.subject_ref)
	notify(_units.get(unit_id, {}))
	var mission_id: String = str(record.detail.get("mission_id", ""))
	if mission_id.is_empty() and g._lod.has_leaf(unit_id):
		mission_id = str(g._lod.preview_leaf(unit_id).mission_id)
	notify(_missions.get(mission_id, {}))

func on_route(unit_id: String, kind: String, _cause: String) -> void:
	var g: RefCounted = _owner.get_ref()
	if g._lod._groups.has(unit_id):
		for leaf: String in g._lod._groups[unit_id].leaf_refs:
			if kind == "ARRIVED":
				_note_arrival(leaf, str(g._state.units[unit_id].spatial.node))
			notify(_units.get(leaf, {}))
	else:
		if kind == "ARRIVED":
			_note_arrival(unit_id, str(g._state.units[unit_id].spatial.node))
		notify(_units.get(unit_id, {}))

func _note_arrival(unit_id: String, node_id: String) -> void:
	var g: RefCounted = _owner.get_ref()
	for mission_id: String in _units.get(unit_id, {}):
		for dependency: Dictionary in g._state.missions[mission_id].goal_v1.dependencies:
			if dependency.kind == "unit_arrived" and dependency.unit_ref == unit_id and dependency.node_ref == node_id:
				dependency.arrived_at = g._state.time

func on_edge(edge_id: String) -> void:
	notify(_edges.get(edge_id, {}))

func on_retired(unit_id: String) -> void:
	notify(_units.get(unit_id, {}))

func notify(waiters: Dictionary) -> void:
	var g: RefCounted = _owner.get_ref()
	for mission_id: String in waiters.keys():
		var mission: Dictionary = g._state.missions[mission_id]
		if mission.status != "active" or _notifications.has(mission_id):
			continue
		_serial += 1
		_notifications[mission_id] = true
		# A future epsilon keeps a callback from sorting before the event being popped.
		g._schedule(str(mission.goal_v1.unit_id), mission_id, "prerequisite_%d" % _serial, g._state.time + 0.000001)

func processed(mission_id: String) -> void:
	_notifications.erase(mission_id)

func _index(kind: String) -> Dictionary:
	return _units if kind == "unit_arrived" else (_edges if kind == "route_open" else _missions)

static func _subject(dependency: Dictionary) -> String:
	return str(dependency.get("unit_ref", dependency.get("edge_ref", dependency.get("mission_ref", ""))))

static func _known_edge(known: Dictionary, edge_id: String) -> bool:
	for alternatives: Array in known.values():
		for path: Array in alternatives:
			if edge_id in path:
				return true
	return false

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

const RUNTIME_FIELDS: Array[String] = ["_units", "_missions", "_edges", "_notifications", "_serial"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
