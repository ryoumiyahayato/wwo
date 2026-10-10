extends RefCounted
## Synthetic inputs only. No result, loss or victory is assigned by this builder.
const F = preload("res://experiments/war_resolver/spatial/fixtures.gd")
const Goals = preload("res://experiments/war_resolver/gameplay/service.gd")
const Info = preload("res://experiments/war_resolver/information/service.gd")
const Decisions = preload("res://experiments/war_resolver/decision/service.gd")

static func intent(kind: String, node: String, path: Array = [], returning: bool = false) -> Dictionary:
	return {"intent": kind, "target_node": node, "path": path.duplicate(), "return_to_start": returning}

static func setup(seed_value: int = 71, config: Dictionary = {}) -> Dictionary:
	var state: F.State = F.State.new()
	state.seed = seed_value
	state.add_area(F.Data.area("field"))
	var graph: Dictionary = F.topology()
	for id: String in graph.nodes:
		graph.nodes[id].cell = "field"
	graph.nodes.A.xy = [0.0, 0.0]
	graph.nodes.B.xy = [0.12, 0.0]
	graph.nodes.C.xy = [0.0, 0.3]
	graph.nodes.D.xy = [0.12, 0.08]
	graph.edges.AB.length_km = 0.12
	graph.edges.bridge_BD.length_km = 0.08
	graph.edges.AC.length_km = 0.3
	graph.edges.CD.length_km = 0.26
	var nodes: Dictionary = {"blue_company": {"echelon": "company", "parent": "", "side": "blue"},
		"blue_platoon": {"echelon": "platoon", "parent": "blue_company", "side": "blue"},
		"blue_destination": {"echelon": "platoon", "parent": "blue_company", "side": "blue"},
		"red_company": {"echelon": "company", "parent": "", "side": "red"},
		"red_platoon": {"echelon": "platoon", "parent": "red_company", "side": "red"}}
	for index: int in range(4):
		var id: String = "unit_%03d" % index
		var mission: Dictionary = F.Data.mission("mission_" + id, "hold" if index != 1 else str(config.get("reserve_posture", "idle")))
		state.add_mission(mission)
		var unit: Dictionary = F.Data.unit(id, "blue" if index < 2 else "red", "field", str(mission.id))
		unit.mobility = 0.08
		unit.ammunition = float(config.get("blue_ammunition", 80.0)) if index < 2 else float(config.get("red_ammunition", 160.0))
		unit.weapon.range_km = float(config.get("range_km", 0.16))
		if config.has("observation_range_km"):
			unit.weapon.observation_range_km = float(config.observation_range_km)
		state.add_unit(unit)
		nodes["node_" + id] = {"echelon": "squad", "parent": "blue_platoon" if index < 2 else "red_platoon", "side": unit.side, "unit_id": id}
	var extra_local: int = int(config.get("extra_local", 0))
	assert(extra_local >= 0 and extra_local <= 16)
	for index: int in range(extra_local):
		var id: String = "local_extra_%02d" % index
		var mission: Dictionary = F.Data.mission("mission_" + id, "hold")
		state.add_mission(mission)
		var unit: Dictionary = F.Data.unit(id, "blue", "field", str(mission.id))
		unit.ammunition = float(config.get("blue_ammunition", 80.0))
		unit.weapon.range_km = float(config.get("range_km", 0.16))
		state.add_unit(unit)
		nodes["node_" + id] = {"echelon": "squad", "parent": "blue_platoon", "side": "blue", "unit_id": id}
	if config.get("background", false):
		state.add_area(F.Data.area("cell_038"))
		for side: String in ["blue", "red"]:
			nodes["remote_" + side + "_company"] = {"echelon": "company", "parent": "", "side": side}
			nodes["remote_" + side + "_platoon"] = {"echelon": "platoon", "parent": "remote_" + side + "_company", "side": side}
			for index: int in range(2):
				var id: String = "remote_" + side + "_%d" % index
				var mission: Dictionary = F.Data.mission("mission_" + id, "hold")
				state.add_mission(mission)
				var unit: Dictionary = F.Data.unit(id, side, "cell_038", str(mission.id), 0.0 if side == "blue" else 0.08)
				unit.ammunition = 2000.0
				unit.weapon.range_km = 0.1
				state.add_unit(unit)
				nodes["node_" + id] = {"echelon": "squad", "parent": "remote_" + side + "_platoon", "side": side, "unit_id": id}
	var managed: Array[String] = F.State.sorted_ids(state.units)
	var sleeping: int = int(config.get("sleeping_areas", 0))
	if sleeping > 0:
		state.add_mission(F.Data.mission("sleeping_standing", "idle"))
		for index: int in range(sleeping):
			var area_id: String = "sleep_area_%05d" % index
			state.add_area(F.Data.area(area_id))
			for member: int in range(3):
				var unit: Dictionary = F.Data.unit("sleep_%05d_%d" % [index, member], "blue", area_id, "sleeping_standing")
				unit.ammunition = 0.0
				state.add_unit(unit)
	var people: Dictionary = {"soldier": {"role": "ordinary_soldier", "formation_id": "node_unit_000"},
		"scout": {"role": "ordinary_soldier", "formation_id": "node_unit_001"},
		"squad": {"role": "squad_leader", "formation_id": "node_unit_000"},
		"platoon": {"role": "platoon_leader", "formation_id": "blue_platoon"},
		"recipient": {"role": "platoon_leader", "formation_id": "blue_destination"},
		"company": {"role": "company_commander", "formation_id": "blue_company"}}
	if config.get("npc", false):
		people.npc = {"role": "ordinary_soldier", "formation_id": "node_unit_000"}
	var lod: F.Authority = F.Authority.new()
	assert(lod.configure(state))
	var structure: F.Structure = F.Structure.new()
	assert(structure.configure(state, lod, nodes, people))
	var roles: Dictionary = {}
	for person: String in people:
		var role: F.Roles = F.Roles.new()
		assert(role.configure(state, nodes, people, person) and role.bind_lod(lod) and role.bind_structure(structure))
		roles[person] = role
	var stocks: Dictionary = {}
	for id: String in managed:
		var motor: bool = bool(config.get("motor", false)) and state.units[id].side == "blue"
		stocks[id] = {"fuel": float(config.get("fuel", 8.0)) if motor else 0.0, "fuel_spent": 0.0,
			"spares": 4.0, "spares_spent": 0.0, "serviceable_equipment": 12.0, "damaged_equipment": 0.0,
			"wear_damage": 0.0, "repair_restored": 0.0, "capability": {"fuel_dependent": motor,
				"fuel_per_equipment_km": 0.2 if motor else 0.0, "spares_per_repair": 1.0, "wear_per_km": 0.0, "suppression_per_round": 0.12}}
	var logistics: F.Logistics = F.Logistics.new()
	assert(logistics.configure(state, lod, structure, stocks, {"source": {"owner_ref": "synthetic_warehouse", "allocation_scope": "blue_company", "stock": {"AMMUNITION": 100.0, "FUEL": 40.0, "SPARES": 20.0}}}, {}))
	var space: F.Space = F.Space.new()
	assert(space.configure(state, lod, graph.nodes, graph.edges, graph.lanes))
	for index: int in range(4):
		var point: String = str(config.get("blue_point", "A")) if index == 0 else ("A" if index == 1 else str(config.get("red_point", "D")))
		assert(space.admit_unit("unit_%03d" % index, point, "MOTORIZED" if config.get("motor", false) and index < 2 else "FOOT"))
	for index: int in range(extra_local):
		assert(space.admit_unit("local_extra_%02d" % index, "A", "FOOT"))
	var paths: Dictionary = {"A": [[], ["AB"], ["AC"]], "B": [[], ["AB"], ["bridge_BD"]],
		"C": [[], ["AC"], ["AB", "AC"], ["CD"]], "D": [[], ["AB", "bridge_BD"], ["AC", "CD"], ["AB", "AC", "CD"], ["bridge_BD"], ["CD"]]}
	var known: Dictionary = {}
	for person: String in people:
		known[person] = paths.duplicate(true)
	var gameplay: Goals = Goals.new()
	var enabled: bool = bool(config.get("gameplay_enabled", true))
	var covers: Dictionary = {"cover_A": {"node": "A", "xy": [0.01, 0.0], "available": true}, "cover_B": {"node": "B", "xy": [0.13, 0.0], "available": true}}
	if enabled:
		assert(gameplay.configure(state, lod, space, known, config.get("rules", {}), covers, config.get("personal_rules", {})))
	if config.get("personal", false):
		assert(gameplay.participants.admit("soldier").ok)
	if config.get("npc", false):
		assert(gameplay.participants.admit("npc").ok)
	var information: Info = Info.new()
	var persons: Array[String] = F.State.sorted_ids(people)
	var sources: Dictionary = {"local": {"observer_ref": "squad", "scope_ref": "node_unit_000", "origin": "DIRECT", "quality": 0.9, "precision_km": 0.02, "fact_kinds": ["route", "ammunition", "objective", "contact"]}}
	if not enabled:
		sources.local.fact_kinds = ["route", "ammunition"]
	for person: String in people:
		if enabled and people[person].role == "ordinary_soldier":
			sources[person + "_local"] = {"observer_ref": person, "scope_ref": people[person].formation_id, "origin": "DIRECT", "quality": 1.0, "precision_km": 0.02, "fact_kinds": ["cover", "contact"]}
	var channels: Dictionary = {"command": {"senders": persons.duplicate(), "recipients": persons.duplicate(), "latency": 15.0, "available": true, "quality": 1.0, "command_scope": "blue_company"},
		"instant": {"senders": persons.duplicate(), "recipients": persons.duplicate(), "latency": 0.0, "available": true, "quality": 1.0, "command_scope": "blue_company"}}
	channels.command.latency = float(config.get("command_latency", 15.0))
	channels.report = {"senders": persons.duplicate(), "recipients": persons.duplicate(), "latency": float(config.get("report_latency", 47.0)), "available": true, "quality": 1.0, "command_scope": "blue_company"}
	assert(information.configure(state, lod, structure, logistics, roles, sources, channels))
	var decisions: Decisions = Decisions.new()
	assert(decisions.configure(state, information, structure, logistics))
	return {"state": state, "lod": lod, "space": space, "structure": structure, "logistics": logistics, "roles": roles, "people": people, "nodes": nodes, "graph": graph, "gameplay": gameplay, "information": information, "decisions": decisions, "managed_units": managed}

static func report(env: Dictionary, actor: String, source: String, fact: String, id: String, recipient: String, channel: String = "instant", subject: String = "unit_000") -> bool:
	if not env.information.observe(actor, {"id": id, "source_ref": source, "subject_kind": "unit", "subject_ref": subject, "fact_kind": fact}).ok:
		return false
	return env.information.send_report(actor, {"id": "report_" + id, "recipient_ref": recipient, "channel_ref": channel, "observation_ids": [id]}).ok

static func local(env: Dictionary, actor: String, id: String, action: String, target: String = "") -> Dictionary:
	return env.information.perform_local_action(actor, {"id": id, "kind": "local_action", "target": actor if target.is_empty() else target, "values": {"action": action}})

static func command(env: Dictionary, actor: String, id: String, values: Dictionary, target: String = "node_unit_000", channel: String = "command") -> Dictionary:
	return env.information.issue_command(actor, {"id": id, "channel_ref": channel, "command": {"id": id, "kind": "goal_intent", "target": target, "values": values}})

static func advance(env: Dictionary, target: float, quota: int = 0) -> Dictionary:
	if quota == 0:
		return env.lod.advance(target)
	var output: Dictionary = {}
	for index: int in range(100000):
		output = env.lod.advance_bounded(target, quota)
		if output.get("status", "") != "PENDING":
			return output
	return {"ok": false, "error": "test_call_limit", "status": "BLOCKED"}

static func current(env: Dictionary, id: String = "unit_000") -> Dictionary:
	return env.state.missions[env.state.units[id].mission_id]
