extends "res://experiments/war_resolver/interactive_observer/reader.gd"
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
var authority: Dictionary = {}
var authority_dirty: bool = true
var continuity_work: Dictionary = {"cache_invalidations": 0, "authority_candidates_read": 0, "authority_refreshes": 0}

func configure(world: Dictionary, person: String) -> void:
	super.configure(world, person)
	env.structure.transition.connect(on_structure)

func on_structure(record: Dictionary) -> void:
	if not record.outcome.ok or record.outcome.get("kind", "") == "stale_expiry_noop":
		return
	var target: String = str(record.outcome.get("target", record.outcome.get("values", {}).get("target", "")))
	var definition: Dictionary = env.decisions._persons[actor].definition
	var affected: bool = target in definition.targets or target == str(env.structure.command_person(actor).formation_id) or actor in record.outcome.get("moved_people", []) or actor in record.outcome.get("position_people", []) or actor in record.outcome.get("movement_people", [])
	for node: String in record.outcome.get("affected_nodes", []):
		affected = affected or node in definition.targets
	if affected:
		authority_dirty = true
		continuity_work.cache_invalidations += 1
	if actor in record.outcome.get("moved_people", []):
		_add({"kind": "own_membership_changed", "event_id": record.id, "effective_time": record.time,
			"learned_time": record.time, "formation_ref": env.structure._people[actor].formation_id})
	if record.actor == actor:
		_add({"kind": "own_structure_result", "event_id": record.id, "effective_time": record.time,
			"learned_time": record.time, "status": record.outcome.kind, "source_ref": actor,
			"note": "own request result; authority metadata is separate from received war reports"})

func view(receipts: Array, selected_focus: String = "") -> Dictionary:
	if env.state.public_pending():
		return env.state.pending_view()
	var result: Dictionary = super.view(receipts, selected_focus)
	if authority_dirty:
		var position: Dictionary = env.structure.command_person(actor)
		var owner: String = str(position.formation_id)
		var rank: int = Roles.ROLES.find(str(position.role))
		var targets: Array[String] = []
		var positions: Dictionary = {}
		for id: String in env.decisions._persons[actor].definition.targets:
			continuity_work.authority_candidates_read += 1
			if not env.structure.active(id) or not env.structure._contains(owner, id):
				continue
			if rank > Roles.ECHELONS.find(str(env.structure._nodes[id].echelon)) + 1 or id == owner and rank > 0:
				var office: Dictionary = env.structure._positions.get(id, {})
				positions[id] = {"person": office.get("person", ""), "acting": office.get("acting", false)}
			if rank == 1 and id == owner or rank >= 2 and (id == owner and rank >= 3 or env.structure.parent(id) == owner):
				targets.append(id)
		authority = {"classification": "CURRENT_AUTHORITY_METADATA", "position_ref": owner,
			"relation": env.structure.relation(owner), "command_targets": targets, "positions": positions,
			"war_information": "UNKNOWN unless present in received reports"}
		authority_dirty = false
		continuity_work.authority_refreshes += 1
	result.known_targets = authority.command_targets.duplicate()
	result.authority = authority.duplicate(true)
	result.current_position = env.structure.command_person(actor)
	result.movements = env.structure.movements.own_records(actor)
	result.air_assets = env.gameplay.air.own_view(actor)
	result.vessels = env.gameplay.sea.own_view(actor)
	result.sea_transports = env.gameplay.sea.freight.known_view(actor)
	result.land_transports = env.gameplay.land.known_view(actor)
	result.operations = env.gameplay.operations.known_view(actor)
	result.contact_states = {}
	result.communications = env.information.communication_view(actor)
	result.field_work = {}
	result.tactical_reports = {}
	for claim: Dictionary in env.information.knowledge(actor).get("entries", []):
		if claim.fact_kind == "unit_state" and float(claim.reliability) > 0.0 and claim.claimed_value.has("tactical"):
			var prior: Dictionary = result.tactical_reports.get(claim.subject_ref, {})
			if float(claim.observed_at) >= float(prior.get("observed_at", -INF)):
				result.tactical_reports[claim.subject_ref] = {"tactical": claim.claimed_value.tactical.duplicate(true), "observed_at": claim.observed_at, "received_at": claim.received_at}
		if claim.fact_kind != "unit_state" or float(claim.reliability) <= 0.0 or not claim.claimed_value.has("ground_work"):
			continue
		var previous: Dictionary = result.field_work.get(claim.subject_ref, {})
		if float(claim.observed_at) > float(previous.get("observed_at", -INF)) or claim.observed_at == previous.get("observed_at", -INF) and int(claim.claimed_value.get("report_revision", 0)) > int(previous.get("report_revision", 0)):
			result.field_work[claim.subject_ref] = {"work": claim.claimed_value.ground_work.duplicate(true), "observed_at": claim.observed_at, "received_at": claim.received_at,
				"node_ref": claim.claimed_value.node_ref, "report_revision": claim.claimed_value.get("report_revision", 0)}
	for node: String in env.decisions._persons[actor].definition.targets:
		var unit: String = str(env.structure._nodes.get(node, {}).get("unit_id", ""))
		if unit.is_empty() or not env.structure._contains(str(result.current_position.formation_id), node) or result.contact_states.size() >= 8:
			continue
		result.contact_states["unit:" + unit] = env.information.contact_status(actor, "unit", unit)
	for vessel: Dictionary in result.vessels:
		result.contact_states["vessel:" + str(vessel.vessel_ref)] = env.information.contact_status(actor, "vessel", str(vessel.vessel_ref))
	result.attemptable = []
	if env.gameplay.participants._units.has(actor):
		result.attemptable.append_array(["wait", "take_cover", "body", "person_report"])
		result.attemptable.append_array(["observe", "watch", "fire", "cease_fire", "reload", "release_weapon", "combat_report"])
		if env.gameplay.medical._trained.has(actor):
			result.attemptable.append("aid")
	var rank: int = Roles.ROLES.find(str(result.current_position.role))
	if rank >= 1:
		result.attemptable.append_array(["hold", "advance", "withdraw", "cancel", "vacate_position", "task"])
		result.attemptable.append("tactics")
	if rank >= 2:
		result.attemptable.append_array(["operation", "forward"])
		result.attemptable.append_array(["transfer", "split_members", "merge_members", "detach_children", "coarsen", "propose_move", "propose_transport", "approve_move", "cancel_move", "accept_move", "redirect_move", "appoint"])
	if rank >= 3:
		result.attemptable.append("reserve")
		result.attemptable.append("air")
		result.attemptable.append("naval")
		result.attemptable.append("land")
	result.continuity_candidates = env.gameplay.focus_continuity.candidates(actor)
	if not env.gameplay.participants.can_intend(actor):
		result.attemptable.clear()
	if not result.continuity_candidates.is_empty():
		result.attemptable.append("continue_as")
	return result

func dispose() -> void:
	env.structure.transition.disconnect(on_structure)
	super.dispose()
