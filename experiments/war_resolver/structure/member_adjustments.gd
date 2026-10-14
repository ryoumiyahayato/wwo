extends RefCounted
## Real membership edits over the existing structure event and capacity ledger.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const KINDS: Array[String] = ["transfer_person", "split_members", "merge_members", "detach_children", "coarsen"]
const RESOURCES: Array[String] = ["equipment", "ammunition", "fuel", "spares"]
var _owner: WeakRef

func configure(service: RefCounted) -> void:
	_owner = weakref(service)

func validate(request: Dictionary, executing: bool) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	if executing and float(request.effective_time) != service._state.time:
		return _reject("wrong_time_boundary")
	var person: Dictionary = service.command_person(str(request.person_id))
	var owner: String = str(person.formation_id)
	if Roles.ROLES.find(str(person.role)) < 2 or not service.active(owner):
		return _reject("member_adjustment_requires_commander")
	var values: Dictionary = request.values
	if service._state.gameplay_port == null:
		return _reject("gameplay_member_capacity_required")
	for field: String in ["source", "destination", "survivor", "donor"]:
		if service._state.gameplay_port.get_ref().tactics.manoeuvre_active(str(values.get(field, ""))):
			return _reject("regroup_actual_road_parts_before_permanent_member_edits")
		if service._state.gameplay_port.get_ref().air.recovery._unit_jobs.has(str(values.get(field, ""))) or service._state.gameplay_port.get_ref().land._unit_jobs.has(str(values.get(field, ""))):
			return _reject("local_air_recovery_crew_is_busy")
	if request.kind == "coarsen":
		if values.size() != 3 or not service._keys(values, ["source", "leaves", "level"]) or not values.get("leaves") is Array or values.leaves.size() < 2 or values.leaves.size() > 16 or values.get("level") not in service._lod.LEVELS or not service._contains(owner, str(values.get("source", ""))):
			return _reject("bounded_coarsening_scope_required")
		var ids: Array[String] = []
		for leaf: Variant in values.leaves:
			if not leaf is String or leaf in ids:
				return _reject("explicit_unique_live_leaves_required")
			ids.append(leaf)
		return {"ok": true} if service.can_coalesce(str(values.source), ids) else _reject("outside_coarsening_formation")
	if request.kind == "split_members":
		return _validate_split(request, owner)
	if request.kind == "merge_members":
		return _validate_merge(request, owner)
	if request.kind == "detach_children":
		return _validate_children(request, owner)
	if request.kind == "transfer_person":
		if values.size() < 3 or values.size() > 4 or not service._keys(values, ["person", "source", "destination", "weapon_disposition"]):
			return _reject("invalid_member_transfer")
		var actor: String = str(values.get("person", ""))
		var source: String = str(values.get("source", ""))
		var destination: String = str(values.get("destination", ""))
		if source == destination or not _leaf_scope(owner, source) or not _leaf_scope(owner, destination):
			return _reject("outside_member_adjustment_scope")
		if service.movements._units.has(source) or service.movements._units.has(destination):
			return _reject("active_movement_member_edits_require_acceptance_or_cancellation")
		var gameplay: RefCounted = service._state.gameplay_port.get_ref()
		if not service._people.has(actor) or gameplay.participants._units.get(actor, "") != source:
			return _reject("existing_counted_member_required")
		if not gameplay.participants.can_intend(actor):
			return _reject("casualty_requires_actual_transport")
		if gameplay.participants._member(actor).has("command_post"):
			return _reject("command_post_body_uses_personal_relocation")
		if service.movements._people.has(actor) and service.movements.records[service.movements._people[actor]].departed:
			return _reject("travelling_member_requires_acceptance_or_cancellation")
		var a: Dictionary = service._lod.preview_leaf(source)
		var b: Dictionary = service._lod.preview_leaf(destination)
		var place: Dictionary = _handover(a, b)
		if not place.ok:
			return place
		# Both stable units remain live; their existing tasks and unit events stay.
		if b.get("gameplay_personnel", {}).get("members", {}).size() >= gameplay.participants.MAX_PER_UNIT:
			return _reject("destination_named_member_capacity")
		var health: float = float(gameplay.participants._member(actor).health)
		if float(a.effective) - health <= service.MIN_REMAINDER:
			return _reject("source_current_capacity_would_be_empty")
		if gameplay.participants._distance(gameplay.participants.position(actor), gameplay._space.xy(b)) > float(gameplay.participants.rules.local_radius_km):
			return _reject("person_outside_actual_handover_position")
		var weapon_transfer: Dictionary = gameplay.tactics.validate_member_transfer(actor, destination, str(values.get("weapon_disposition", "carry")))
		if not weapon_transfer.ok:
			return weapon_transfer
		return _representation_capacity([source, destination])
	return _reject("unknown_member_adjustment")

func apply(request: Dictionary, changed: Dictionary, retired: Dictionary) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	var values: Dictionary = request.values
	var merge_people: Array[String] = []
	if request.kind == "merge_members":
		var selected: Dictionary = service._node_people[service._unit_nodes[values.donor]].duplicate()
		selected.merge(service._lod.preview_leaf(str(values.donor)).get("gameplay_personnel", {}).get("members", {}))
		merge_people = State.sorted_ids(selected)
	if request.kind == "coarsen":
		var ids: Array[String] = []
		for id: String in values.leaves:
			ids.append(id)
		var result: Dictionary = service._lod.coalesce(str(values.source), ids, str(values.level))
		if not result.ok:
			return result
		changed[result.aggregate_id] = true
		for id: String in ids:
			retired[id] = true
			changed.erase(id)
		return {"ok": true, "kind": request.kind, "values": values.duplicate(true), "affected_nodes": [values.source], "representation_only": true}
	if request.kind == "split_members":
		_split(request, changed, retired)
	elif request.kind == "merge_members":
		_merge(request, changed, retired)
	elif request.kind == "detach_children":
		_detach_children(request, changed, retired)
	if request.kind == "transfer_person":
		var source: String = str(values.source)
		var destination: String = str(values.destination)
		service._materialize(str(service._unit_nodes[source]), changed, retired)
		service._materialize(str(service._unit_nodes[destination]), changed, retired)
		var state: State = service._state
		var participants: RefCounted = state.gameplay_port.get_ref().participants
		var a: Dictionary = state.units[source]
		var b: Dictionary = state.units[destination]
		var actor: String = str(values.person)
		var health: float = float(participants._member(actor).health)
		if not b.has("gameplay_personnel"):
			b.gameplay_personnel = {"anonymous": float(b.effective), "members": {}}
		# Transfer current capacity only. Historical casualties and spent stocks stay.
		var measure: float = float(a.get("tactical_weight", 1.0)) * health / float(a.personnel_total)
		var recovery_credit: float = float(a.personnel_recovered) * health / float(a.personnel_total)
		a.personnel_recovered -= recovery_credit
		b.personnel_recovered += recovery_credit
		for key: String in ["effective", "personnel_total"]:
			a[key] -= health
			b[key] += health
		a.tactical_weight = float(a.get("tactical_weight", 1.0)) - measure
		b.tactical_weight = float(b.get("tactical_weight", 1.0)) + measure
		participants.rebind_member(actor, destination, str(values.get("weapon_disposition", "carry")), false, str(request.id))
		service.move_person(actor, str(service._unit_nodes[destination]))
		changed[source] = true
		changed[destination] = true
		state.contacts.erase(a.area_id)
		state.wake(str(a.area_id))
		service.work.relations_changed += 1
	var affected: Array[String] = []
	var created: Array[String] = []
	var moved: Array[String] = []
	for key: String in ["source", "destination", "survivor", "donor"]:
		if values.has(key):
			affected.append(str(service._unit_nodes.get(values[key], values[key])))
	if request.kind in ["split_members", "detach_children"]:
		created.append(str(values.new_node))
		if request.kind == "split_members":
			for actor: String in values.members:
				moved.append(actor)
	if request.kind == "transfer_person":
		moved.append(str(values.person))
	if request.kind == "merge_members":
		moved.append_array(merge_people)
	return {"ok": true, "kind": request.kind, "values": values.duplicate(true), "affected_nodes": affected, "created_nodes": created, "moved_people": moved}

func _validate_split(request: Dictionary, owner: String) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	var state: State = service._state
	var v: Dictionary = request.values
	if v.size() != 8 or not service._keys(v, ["source", "new_id", "new_node", "members", "anonymous", "allocation", "keep_goal", "other_task"]) or not v.get("members") is Array or not v.get("allocation") is Dictionary or v.get("keep_goal") not in ["source", "new"]:
		return _reject("explicit_split_members_resources_and_tasks_required")
	var source: String = str(v.get("source", ""))
	if not _leaf_scope(owner, source):
		return _reject("outside_member_adjustment_scope")
	var dependencies: Dictionary = _dependencies(source)
	if not dependencies.ok:
		return dependencies
	if not _fresh_identity(v.get("new_id"), v.get("new_node")):
		return _reject("identity_collision")
	if not _unattached(source):
		return _reject("split_attachment_resolution_required")
	var unit: Dictionary = service._lod.preview_leaf(source)
	var place: Dictionary = _handover(unit, unit)
	if not place.ok:
		return place
	var participants: RefCounted = state.gameplay_port.get_ref().participants
	if v.members.size() > participants.MAX_PER_UNIT or not service._number(v.anonymous) or float(v.anonymous) < 0.0:
		return _reject("invalid_current_member_allocation")
	var anonymous: float = float(unit.get("gameplay_personnel", {}).get("anonymous", unit.effective))
	if float(v.anonymous) > anonymous:
		return _reject("anonymous_capacity_unavailable")
	var selected: Dictionary = {}
	var capacity: float = float(v.anonymous)
	for actor: Variant in v.members:
		if not actor is String or selected.has(actor) or not service._people.has(actor) or participants._units.get(actor, "") != source:
			return _reject("exact_existing_members_required")
		selected[actor] = true
		if participants._member(actor).has("command_post"):
			return _reject("command_post_share_cannot_become_frontline_detachment")
		if participants.dead(actor):
			return _reject("dead_person_cannot_form_travelling_detachment")
		capacity += float(participants._member(actor).health)
	if capacity <= service.MIN_REMAINDER or float(unit.effective) - capacity <= service.MIN_REMAINDER:
		return _reject("empty_or_full_current_detachment")
	if v.allocation.size() != RESOURCES.size() or not service._keys(v.allocation, RESOURCES):
		return _reject("explicit_resource_allocation_required")
	for key: String in RESOURCES:
		if not service._number(v.allocation.get(key)) or float(v.allocation[key]) < 0.0 or float(v.allocation[key]) > float(unit.get(key, 0.0)):
			return _reject("resource_allocation_unavailable")
	var tactics: RefCounted = state.gameplay_port.get_ref().tactics
	var carried_equipment: float = 0.0
	var carried_ready: float = 0.0
	for actor: String in selected:
		var weapon: Dictionary = tactics.weapons.get(actor, {})
		if not weapon.is_empty() and weapon.unit_ref == source and weapon.get("holder_ref", actor) == actor:
			carried_equipment += float(weapon.profile.equipment_share)
			carried_ready += float(weapon.ready)
	var serviceable: float = float(unit.get("serviceable_equipment", unit.equipment))
	var allocated_serviceable: float = serviceable * float(v.allocation.equipment) / maxf(0.000001, float(unit.equipment))
	if allocated_serviceable + 0.000001 < carried_equipment or serviceable - allocated_serviceable + 0.000001 < tactics._equipment_claims(source) - carried_equipment or float(v.allocation.ammunition) + 0.000001 < carried_ready or float(unit.ammunition) - float(v.allocation.ammunition) + 0.000001 < tactics.prepared_total(source) - carried_ready:
		return _reject("split_allocation_must_include_existing_weapon_and_prepared_claims")
	if state.missions.has("structure_" + str(request.id) + "_idle"):
		return _reject("mission_identity_collision")
	var capacity_result: Dictionary = _representation_capacity([source], 1)
	if not capacity_result.ok:
		return capacity_result
	if v.other_task is String and v.other_task == "idle":
		return {"ok": true}
	if not v.other_task is Dictionary or v.other_task.get("intent") == "cancel":
		return _reject("other_unit_requires_idle_or_explicit_goal")
	if owner != service.parent(str(service._unit_nodes[source])):
		return _reject("new_local_task_requires_owning_platoon_input")
	var gameplay: RefCounted = state.gameplay_port.get_ref()
	if gameplay._goals.size() >= gameplay.MAX_GOALS:
		return _reject("gameplay_goal_capacity")
	var other: Dictionary = unit.duplicate(true)
	other.id = v.new_id if v.keep_goal == "source" else source
	var task: Dictionary = gameplay.validate_goal(str(request.person_id), other, v.other_task)
	if not task.ok:
		return task
	if not v.other_task.path.is_empty():
		var regrouping: int = 0
		for actor: String in unit.get("gameplay_personnel", {}).get("members", {}):
			if (actor in v.members) != (v.keep_goal == "source"):
				continue
			var member: Dictionary = participants._member(actor)
			regrouping += int(member.actionable and member.state != "FOLLOWING")
		if participants._actions.size() + regrouping > participants.MAX_ACTIONS:
			return _reject("personal_regroup_capacity")
	if state.missions.has("goal_structure_" + str(request.id) + "_" + str(other.id)):
		return _reject("goal_identity_collision")
	return {"ok": true}

func _split(request: Dictionary, changed: Dictionary, retired: Dictionary) -> void:
	var service: RefCounted = _owner.get_ref()
	var state: State = service._state
	var gameplay: RefCounted = state.gameplay_port.get_ref()
	var v: Dictionary = request.values
	var source_id: String = str(v.source)
	service._materialize(str(service._unit_nodes[source_id]), changed, retired)
	var source: Dictionary = state.units[source_id]
	var fresh: Dictionary = source.duplicate(true)
	var capacity: float = float(v.anonymous)
	for actor: String in v.members:
		capacity += float(gameplay.participants._member(actor).health)
	var fraction: float = capacity / float(source.personnel_total)
	fresh.id = v.new_id
	fresh.erase("gameplay_personnel")
	for key: String in service.stock_keys():
		fresh[key] = 0.0
	fresh.personnel_total = capacity
	fresh.effective = capacity
	fresh.personnel_recovered = float(source.personnel_recovered) * fraction
	for key: String in RESOURCES:
		fresh[key] = float(v.allocation[key])
	# Equipment damage composition follows the explicit equipment quantity.
	var equipment_fraction: float = float(fresh.equipment) / float(source.equipment) if float(source.equipment) > 0.0 else 0.0
	for key: String in ["serviceable_equipment", "damaged_equipment"]:
		if source.has(key):
			fresh[key] = float(source[key]) * equipment_fraction
	for key: String in ["personnel_total", "effective", "personnel_recovered"] + RESOURCES + ["serviceable_equipment", "damaged_equipment"]:
		if source.has(key):
			source[key] -= float(fresh[key])
	var measure: float = float(source.get("tactical_weight", 1.0))
	fresh.tactical_weight = measure * fraction
	source.tactical_weight = measure - float(fresh.tactical_weight)
	if source.has("gameplay_personnel"):
		source.gameplay_personnel.anonymous -= float(v.anonymous)
	fresh.gameplay_personnel = {"anonymous": float(v.anonymous), "members": {}}
	fresh.structure_provenance = {"from": source_id, "event": request.id, "time": state.time}
	state.units[fresh.id] = fresh
	state.area_units[fresh.area_id][fresh.id] = true
	var source_node: String = str(service._unit_nodes[source_id])
	var parent: String = service.parent(source_node)
	service._nodes[v.new_node] = {"echelon": "squad", "side": source.side, "parent": parent, "unit_id": fresh.id, "provenance": fresh.structure_provenance.duplicate(true)}
	service._unit_nodes[fresh.id] = v.new_node
	service._used_nodes[v.new_node] = true
	service._used_units[fresh.id] = true
	service._children[v.new_node] = {}
	service._leaves[v.new_node] = {v.new_node: true}
	service._node_people[v.new_node] = {}
	service._children[parent][v.new_node] = true
	for ancestor: String in service._path(parent):
		service._leaves[ancestor][v.new_node] = true
		service.work.authority_scopes_updated += 1
	for actor: String in v.members:
		gameplay.participants.rebind_member(actor, str(fresh.id), "carry", true, str(request.id))
		if not request.get("defer_membership", false):
			service.move_person(actor, str(v.new_node))
	if fresh.gameplay_personnel.members.is_empty():
		fresh.erase("gameplay_personnel")
	var original_mission: String = str(source.mission_id)
	var other: Dictionary = fresh if v.keep_goal == "source" else source
	if v.keep_goal == "new":
		fresh.mission_id = original_mission
		gameplay.transfer_goal(source_id, str(fresh.id))
	_idle(other, "structure_" + str(request.id) + "_idle")
	if v.other_task is Dictionary:
		gameplay.assign_structural_task(str(other.id), "structure_" + str(request.id), str(request.person_id), v.other_task)
	if v.keep_goal == "new":
		gameplay.on_goal_executor_changed(str(fresh.id), str(request.id))
	changed[source_id] = true
	changed[fresh.id] = true
	service.work.relations_changed += 1
	state.contacts.erase(source.area_id)
	state.wake(str(source.area_id))

func _validate_merge(request: Dictionary, owner: String) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	var state: State = service._state
	var v: Dictionary = request.values
	if v.size() < 4 or v.size() > 5 or not service._keys(v, ["survivor", "donor", "keep_goal", "discard_other", "vacate_donor"]) or not v.get("discard_other") is bool or not v.get("vacate_donor", false) is bool or v.get("keep_goal") not in ["survivor", "donor"]:
		return _reject("explicit_merge_survivor_and_task_choice_required")
	var survivor: String = str(v.get("survivor", ""))
	var donor: String = str(v.get("donor", ""))
	if survivor == donor or not _leaf_scope(owner, survivor) or not _leaf_scope(owner, donor):
		return _reject("outside_member_adjustment_scope")
	if not _unattached(survivor) or not _unattached(donor):
		return _reject("merge_attachment_resolution_required")
	for id: String in [survivor, donor]:
		var dependencies: Dictionary = _dependencies(id)
		if not dependencies.ok:
			return dependencies
	var x: String = str(service._unit_nodes[survivor])
	var y: String = str(service._unit_nodes[donor])
	if str(service._positions.get(y, {}).get("person", "")) != "" and not v.get("vacate_donor", false):
		return _reject("explicit_donor_office_handover_required")
	if service._nodes[x].parent != service._nodes[y].parent or service.parent(x) != service.parent(y):
		return _reject("merge_requires_compatible_real_parent")
	var a: Dictionary = service._lod.preview_leaf(survivor)
	var b: Dictionary = service._lod.preview_leaf(donor)
	for current: Dictionary in [a, b]:
		for actor: String in current.get("gameplay_personnel", {}).get("members", {}):
			if state.gameplay_port.get_ref().participants._member(actor).has("command_post"):
				return _reject("command_post_holder_merge_requires_explicit_office_and_capacity_transfer")
	var place: Dictionary = _handover(a, b)
	if not place.ok:
		return place
	for key: String in ["type", "weapon", "readiness", "mobility"]:
		if a[key] != b[key]:
			return _reject("incompatible_merge_capability")
	if a.spatial != b.spatial or state.logistics_port != null and not state.logistics_port.get_ref().compatible(a, b, false):
		return _reject("incompatible_route_or_supply_capability")
	var participants: RefCounted = state.gameplay_port.get_ref().participants
	if a.get("gameplay_personnel", {}).get("members", {}).size() + b.get("gameplay_personnel", {}).get("members", {}).size() > participants.MAX_PER_UNIT:
		return _reject("merged_named_member_capacity")
	for actor: String in service._node_people[y]:
		if participants._units.has(actor) and participants._units[actor] != donor:
			return _reject("absent_member_admin_merge_requires_actual_handover_or_regroup")
		if service._people[actor].role != "ordinary_soldier":
			if service._person_positions.get(actor, "") == y and not v.get("vacate_donor", false):
				return _reject("explicit_donor_office_handover_required")
			continue
		if participants._units.get(actor, "") != donor:
			return _reject("named_member_missing_capacity_ledger")
	var other: Dictionary = state.missions[b.mission_id if v.keep_goal == "survivor" else a.mission_id]
	if a.mission_id != b.mission_id and other.status == "active" and other.posture != "idle" and not v.discard_other:
		return _reject("active_other_task_requires_explicit_cancel")
	return _representation_capacity([survivor, donor], 0, 1)

func _merge(request: Dictionary, changed: Dictionary, retired: Dictionary) -> void:
	var service: RefCounted = _owner.get_ref()
	var state: State = service._state
	var gameplay: RefCounted = state.gameplay_port.get_ref()
	var v: Dictionary = request.values
	var survivor: String = str(v.survivor)
	var donor: String = str(v.donor)
	service._materialize(str(service._unit_nodes[survivor]), changed, retired)
	service._materialize(str(service._unit_nodes[donor]), changed, retired)
	var a: Dictionary = state.units[survivor]
	var b: Dictionary = state.units[donor]
	var history: Dictionary = b.duplicate(true)
	var donor_node: String = str(service._unit_nodes[donor])
	var survivor_node: String = str(service._unit_nodes[survivor])
	var other_id: String = donor if v.keep_goal == "survivor" else survivor
	var other_mission: Dictionary = state.missions[state.units[other_id].mission_id]
	if a.mission_id != b.mission_id:
		gameplay.cancel_structural_goal(other_id, str(request.id))
		if other_mission.status == "active":
			other_mission.status = "cancelled"
			other_mission.structure_cancel_ref = request.id
	if v.keep_goal == "donor":
		a.mission_id = b.mission_id
		gameplay.transfer_goal(donor, survivor)
	var moving: Dictionary = service._node_people[donor_node].duplicate()
	moving.merge(b.get("gameplay_personnel", {}).get("members", {}))
	var donor_people: Array[String] = State.sorted_ids(moving)
	if b.has("gameplay_personnel") or a.has("gameplay_personnel"):
		if not a.has("gameplay_personnel"):
			a.gameplay_personnel = {"anonymous": float(a.effective), "members": {}}
		a.gameplay_personnel.anonymous += float(b.get("gameplay_personnel", {}).get("anonymous", b.effective))
	for actor: String in donor_people:
		if gameplay.participants._units.has(actor):
			gameplay.participants.rebind_member(actor, survivor, "carry", true, str(request.id))
		service.move_person(actor, survivor_node)
	if v.get("vacate_donor", false):
		service.vacate_node(donor_node, "explicit_merge_handover", str(request.id))
	service._merge(request, changed, retired)
	gameplay.medical.on_unit_merge(donor, survivor)
	service._retired[donor_node].historical_unit_not_current = history
	if v.keep_goal == "donor":
		gameplay.on_goal_executor_changed(survivor, str(request.id))

func _validate_children(request: Dictionary, owner: String) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	var v: Dictionary = request.values
	var source: String = str(v.get("source", ""))
	if v.size() != 3 or not service._keys(v, ["source", "new_node", "children"]) or not v.get("children") is Array or v.children.is_empty() or v.children.size() > 16 or not service.active(source) or service._nodes[source].echelon not in ["platoon", "company"]:
		return _reject("existing_children_detachment_required")
	var parent: String = str(service._nodes[source].parent)
	if parent.is_empty() or not service._contains(owner, source) or not service._contains(owner, parent) or service._attachments.has(source) or not service._pending.get(source, {}).is_empty():
		return _reject("detachment_requires_real_superior_scope")
	if not v.get("new_node") is String or str(v.new_node).is_empty() or service._used_nodes.has(v.new_node) or service._used_units.has(v.new_node) or service._state.knows_unit(str(v.new_node)):
		return _reject("identity_collision")
	var selected: Dictionary = {}
	var leaves: int = 0
	var ids: Array[String] = []
	for child: Variant in v.children:
		if not child is String or selected.has(child) or not service.active(child) or not service._children[source].has(child) or service._nodes[child].parent != source or service._attachments.has(child) or not service._pending.get(child, {}).is_empty():
			return _reject("explicit_real_direct_children_required")
		selected[child] = true
		leaves += service._leaves[child].size()
		if leaves <= 16:
			for leaf: String in service._leaves[child]:
				ids.append(str(service._nodes[leaf].unit_id))
	if leaves == 0 or leaves > 16:
		return _reject("detachment_local_leaf_capacity")
	return _representation_capacity(ids)

func _representation_capacity(ids: Array[String], added: int = 0, removed: int = 0) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	var gameplay: RefCounted = service._state.gameplay_port.get_ref()
	var counts: Dictionary = {}
	var proxies: Dictionary = {}
	var first_scope: String = ""
	for id: String in ids:
		var unit: Dictionary = service._lod.preview_leaf(id)
		var scope: String = str(gameplay._space._cell_scope.get(str(unit.area_id), unit.area_id))
		if first_scope.is_empty():
			first_scope = scope
		if not counts.has(scope):
			counts[scope] = gameplay._space.combat_ids(str(unit.area_id)).size()
		var representation: String = service._lod.representation_of(id)
		if representation != id:
			if not proxies.has(representation):
				proxies[representation] = {"count": 0, "scope": scope}
			proxies[representation].count += 1
	for representation: String in proxies:
		var selection: Dictionary = proxies[representation]
		counts[selection.scope] += int(selection.count) - int(int(selection.count) == service._lod._groups[representation].leaf_refs.size())
	if not first_scope.is_empty():
		counts[first_scope] += added - removed
	for count: int in counts.values():
		if count > gameplay.SCOPE_LIMIT:
			return _reject("local_representation_capacity_after_adjustment")
	return {"ok": true}

func _detach_children(request: Dictionary, changed: Dictionary, retired: Dictionary) -> void:
	var service: RefCounted = _owner.get_ref()
	var v: Dictionary = request.values
	var source: String = str(v.source)
	var fresh: String = str(v.new_node)
	var parent: String = str(service._nodes[source].parent)
	service._nodes[fresh] = {"echelon": service._nodes[source].echelon, "side": service._nodes[source].side, "parent": parent,
		"provenance": {"from": source, "event": request.id, "time": service._state.time}}
	service._children[fresh] = {}
	service._leaves[fresh] = {}
	service._node_people[fresh] = {}
	service._used_nodes[fresh] = true
	service._children[parent][fresh] = true
	for child: String in v.children:
		service._materialize(child, changed, retired)
		service._reparent(child, fresh)
		service._nodes[child].parent = fresh

func _idle(unit: Dictionary, id: String) -> void:
	var service: RefCounted = _owner.get_ref()
	var mission: Dictionary = service._state.missions[unit.mission_id].duplicate(true)
	mission.erase("goal_v1")
	mission.id = id
	mission.posture = "idle"
	mission.status = "active"
	mission.destination = ""
	service._state.add_mission(mission)
	unit.mission_id = id
	unit.spatial.path.clear()
	unit.spatial.returning = false
	unit.spatial.retreating = false
	unit.spatial.blocked_edge = ""

func _fresh_identity(id: Variant, node: Variant) -> bool:
	var service: RefCounted = _owner.get_ref()
	return id is String and node is String and not str(id).is_empty() and not str(node).is_empty() and id != node and not service._state.identity_reserved(str(id)) and not service._state.identity_reserved(str(node)) and not service._state.unit_event_counts.has(id)

func _unattached(id: String) -> bool:
	var service: RefCounted = _owner.get_ref()
	var node: String = str(service._unit_nodes[id])
	return not service._attachments.has(node) and service._pending.get(node, {}).is_empty()

func _leaf_scope(owner: String, id: String) -> bool:
	var service: RefCounted = _owner.get_ref()
	return service._unit_nodes.has(id) and service._contains(owner, str(service._unit_nodes[id]))

func _dependencies(id: String, movement_handover: bool = false) -> Dictionary:
	var service: RefCounted = _owner.get_ref()
	var state: State = service._state
	var unit: Dictionary = service._lod.preview_leaf(id)
	if service.movements._units.has(id) and not movement_handover:
		return _reject("active_movement_requires_acceptance_or_cancellation")
	if unit.is_empty():
		return _reject("live_member_unit_required")
	var gameplay: RefCounted = state.gameplay_port.get_ref()
	if gameplay._goals.has(id) and gameplay._goals[id] != unit.mission_id:
		return _reject("legacy_goal_binding_migration_not_supported")
	if state.unit_order_counts.has(id):
		return _reject("legacy_order_migration_not_supported")
	if state.coordination.has(id) and not gameplay.can_transfer_dependencies(id):
		return _reject("cross_unit_preparation_migration_not_supported")
	if state.command_coordination.has(id):
		return _reject("timed_command_coordination_migration_not_supported")
	if state.tactical_intents.has(id):
		return _reject("tactical_intent_migration_not_supported")
	if not (state.mission_dependents.get(unit.mission_id, {}) as Dictionary).is_empty() and not state.missions[unit.mission_id].has("goal_v1"):
		return _reject("dependent_mission_rebinding_not_supported")
	if not str(state.missions[unit.mission_id].destination).is_empty():
		return _reject("legacy_destination_migration_not_supported")
	return {"ok": true}

func _handover(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty() or b.is_empty() or a.side != b.side:
		return _reject("same_side_live_units_required")
	if not a.has("spatial") or not b.has("spatial") or a.area_id != b.area_id or a.position != b.position or a.spatial.node != b.spatial.node or not str(a.spatial.edge).is_empty() or not str(b.spatial.edge).is_empty() or not a.spatial.path.is_empty() or not b.spatial.path.is_empty():
		return _reject("actual_stationary_meeting_required")
	return {"ok": true}

static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
