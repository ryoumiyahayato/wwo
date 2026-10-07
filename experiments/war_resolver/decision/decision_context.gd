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
	var position: Dictionary = _structure._people[person]
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
	if rank >= 1:
		kinds.append("command")
	if rank >= 2:
		kinds.append("logistics_request")
	if rank >= 3:
		kinds.append("structure_request")
	return {"ok": true, "person_id": person, "role": position.role, "position_ref": position.formation_id,
		"command_ready_at": _information._roles[person]._next_input.get(person, 0.0),
		"command_issue_ready_at": _information._next_issue.get(person, 0.0),
		"decision_time": time, "received_claims": received.entries, "knowledge_total": received.total_matching,
		"authority_targets": targets, "command_targets": command_targets, "output_kinds": kinds,
		"command_kind": "tactical_intent" if rank == 1 else "mission", "standing_orders": definition.standing_orders.duplicate(true),
		"cadence_seconds": definition.cadence, "next_opportunity": next_time, "ready_at": ready}
