extends RefCounted
## Company and higher offices retain/release actual units, not combat multipliers.
const MAX_UNITS: int = 4
var _owner: WeakRef

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func units(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if values.get("policy", "") == "retain":
		for id: String in values.get("units", []):
			result.append(id)
	else:
		for task: Dictionary in values.get("tasks", []):
			result.append(str(task.unit_ref))
	return result

func validate(actor: String, target: String, values: Dictionary, input_id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var s: RefCounted = g._state.structure_port.get_ref()
	var position: Dictionary = s.command_person(actor)
	if s.Roles.ROLES.find(str(position.role)) < 3 or target != position.formation_id:
		return _reject("reserve_requires_company_or_higher_current_office")
	if values.size() != 2 or values.get("policy", "") not in ["retain", "release"]:
		return _reject("explicit_reserve_policy_required")
	var retaining: bool = values.policy == "retain"
	var selected: Variant = values.get("units" if retaining else "tasks")
	if not selected is Array or selected.is_empty() or selected.size() > MAX_UNITS:
		return _reject("bounded_existing_reserve_units_required")
	var ids: Array[String] = []
	var added: int = 0
	for item: Variant in selected:
		if retaining and not item is String or not retaining and (not item is Dictionary or item.size() != 2 or not item.get("unit_ref") is String or not item.get("goal") is Dictionary):
			return _reject("explicit_reserve_unit_and_release_goal_required")
		var id: String = str(item) if retaining else str(item.unit_ref)
		if g.air.recovery._unit_jobs.has(id) or g.land._unit_jobs.has(id):
			return _reject("cancel_local_air_recovery_before_reassigning_its_crew")
		if id in ids or not s._unit_nodes.has(id) or not s.active(str(s._unit_nodes[id])) or not s._contains(str(position.formation_id), str(s._unit_nodes[id])) or not g._lod.has_leaf(id):
			return _reject("reserve_outside_current_office")
		if s.movements._units.has(id):
			return _reject("movement_agreement_must_be_handled_explicitly")
		var unit: Dictionary = g._lod.preview_leaf(id)
		if not unit.has("spatial") or float(unit.effective) <= s.MIN_REMAINDER:
			return _reject("actual_able_reserve_unit_required")
		var assignment: Dictionary = g._state.coordination.get(id, {})
		if retaining:
			if not assignment.is_empty() and not assignment.get("retained", false):
				return _reject("existing_coordination_must_be_handled_explicitly")
		else:
			if not assignment.get("retained", false) or item.goal.get("intent", "") == "cancel":
				return _reject("retained_unit_and_actual_release_task_required")
			var valid: Dictionary = g.validate_goal(actor, unit, item.goal)
			if not valid.ok:
				return valid
			if g._state.missions.has("goal_" + input_id + "_" + id):
				return _reject("goal_identity_collision")
			added += int(not g._goals.has(id))
		ids.append(id)
	if not retaining and (g._history_count + ids.size() > g.MAX_HISTORY or g._goals.size() + added > g.MAX_GOALS or g.participants._actions.size() + ids.size() * g.participants.MAX_PER_UNIT > g.participants.MAX_ACTIONS):
		return _reject("reserve_release_task_capacity")
	return s._members._representation_capacity(ids)

func apply(actor: String, values: Dictionary, input_id: String) -> Dictionary:
	var g: RefCounted = _owner.get_ref()
	var delta: Dictionary = {"units": {}, "missions": {}, "coordination": {}}
	for id: String in units(values):
		if values.policy == "retain":
			g._state.coordination[id] = {"role": "local_reserve", "retained": true, "retained_by": actor, "input_ref": input_id, "status": "waiting"}
			if g._goals.has(id) and g._state.missions[g._goals[id]].status == "active":
				var mission: Dictionary = g._state.missions[g._goals[id]]
				g._schedule(id, str(mission.id), "reserve", maxf(g._state.time + 0.000001, minf(float(mission.goal_v1.deadline), float(mission.goal_v1.dependency_deadline))))
				g._evaluate(id)
		else:
			g._state.coordination.erase(id)
			for task: Dictionary in values.tasks:
				if task.unit_ref == id:
					g.apply_goal(id, input_id, actor, task.goal)
		var unit: Dictionary = g._state.units[id]
		g._state.wake(str(unit.area_id))
		delta.units[id] = unit.duplicate(true)
		delta.missions[unit.mission_id] = g._state.missions[unit.mission_id].duplicate(true)
		delta.coordination[id] = g._state.coordination.get(id, {}).duplicate(true)
	return delta

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
