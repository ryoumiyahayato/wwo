extends RefCounted
## Synthetic inputs only. No result, loss or victory is assigned by this builder.
const F = preload("res://experiments/war_resolver/spatial/fixtures.gd")
const Goals = preload("res://experiments/war_resolver/gameplay/service.gd")
const Info = preload("res://experiments/war_resolver/information/service.gd")
const Decisions = preload("res://experiments/war_resolver/decision/service.gd")

static func runtime_state(env: Dictionary) -> Dictionary:
	if env.state.settlement_pending:
		return env.state.pending_view()
	var result: Dictionary = {"ok": true, "version": "war-environment-runtime-v5", "state": env.state.runtime_state(),
		"lod": env.lod.runtime_state(), "structure": env.structure.runtime_state(), "logistics": env.logistics.runtime_state(),
		"space": env.space.runtime_state(), "gameplay": env.gameplay.runtime_state(), "information": env.information.runtime_state(),
		"decisions": env.decisions.runtime_state(), "roles": {}, "metadata": {}}
	for key: String in ["state", "lod", "information", "decisions"]:
		if result[key].get("ok", true) == false:
			return result[key]
	for person: String in env.roles:
		result.roles[person] = env.roles[person].runtime_state()
	for key: String in ["people", "nodes", "graph", "managed_units"]:
		if env.has(key):
			result.metadata[key] = env[key].duplicate(true)
	return result

static func restore_runtime(image: Dictionary) -> Dictionary:
	if not image.get("ok", false) or image.get("version", "") != "war-environment-runtime-v5":
		return {"ok": false, "error": "unsupported_runtime_checkpoint"}
	for key: String in ["state", "lod", "structure", "logistics", "space", "gameplay", "information", "decisions", "roles", "metadata"]:
		if not image.get(key) is Dictionary:
			return {"ok": false, "error": "missing_runtime_module_" + key}
	for key: String in image.metadata:
		if key not in ["people", "nodes", "graph", "managed_units"]:
			return {"ok": false, "error": "unsupported_environment_metadata"}
	var state: F.State = F.State.new()
	var lod: F.Authority = F.Authority.new()
	var structure: F.Structure = F.Structure.new()
	var logistics: F.Logistics = F.Logistics.new()
	var space: F.Space = F.Space.new()
	var gameplay: Goals = Goals.new()
	var information: Info = Info.new()
	var decisions: Decisions = Decisions.new()
	if not state.restore_runtime(image.state) or not lod.restore_runtime(state, image.lod) or not structure.restore_runtime(image.structure):
		return {"ok": false, "error": "invalid_state_lod_or_structure"}
	structure.bind_runtime(state, lod)
	if not logistics.restore_runtime(image.logistics) or not space.restore_runtime(image.space):
		return {"ok": false, "error": "invalid_inventory_or_space"}
	logistics.bind_runtime(state, lod, structure)
	space.bind_runtime(state, lod)
	if not space.valid_local_runtime():
		return {"ok": false, "error": "invalid_local_space_continuation"}
	if not gameplay.restore_runtime(state, lod, space, image.gameplay):
		return {"ok": false, "error": "invalid_body_weapon_or_professional_state"}
	var roles: Dictionary = {}
	for person: String in image.roles:
		var role: F.Roles = F.Roles.new()
		if not structure._people.has(person) or not image.roles[person] is Dictionary or not role.restore_runtime(image.roles[person]) or role._player_id != person:
			return {"ok": false, "error": "invalid_person_command_binding"}
		role.bind_runtime(state, lod, structure)
		roles[person] = role
	if not information.restore_runtime(state, lod, structure, logistics, roles, image.information) or not decisions.restore_runtime(state, information, structure, logistics, image.decisions):
		return {"ok": false, "error": "invalid_message_or_decision_continuation"}
	var operation_active: bool = gameplay.operations._active
	gameplay.operations._active = false
	if operation_active:
		gameplay.operations.activate()
	var queued: Dictionary = {}
	for event: Dictionary in state.events:
		queued[event.id] = event
		var port: RefCounted = {"gameplay": gameplay, "spatial": space, "structure": structure, "logistics": logistics, "communication": information, "decision": decisions}.get(event.kind)
		if port != null and not port.accepts_event(str(event.id), event.payload, float(event.time)):
			return {"ok": false, "error": "event_ticket_binding_missing_" + str(event.id)}
	for id: String in gameplay.tactics._tickets:
		if not queued.has(id):
			return {"ok": false, "error": "unfinished_tactical_event_missing"}
	for action: Dictionary in gameplay.participants._actions.values():
		if action.status == "PENDING" and not queued.has(action.id):
			return {"ok": false, "error": "unfinished_body_event_missing"}
	for source: String in logistics._reserved:
		if not logistics._depots.has(source):
			return {"ok": false, "error": "reserved_source_missing"}
		for resource: String in logistics._reserved[source]:
			var quantity: float = float(logistics._reserved[source][resource])
			if not is_finite(quantity) or quantity < -0.000001 or quantity > float(logistics._depots[source].stock.get(resource, 0.0)) + 0.000001:
				return {"ok": false, "error": "reserved_stock_unavailable"}
	var candidate: Dictionary = {"state": state, "lod": lod, "structure": structure, "logistics": logistics, "space": space,
		"gameplay": gameplay, "information": information, "decisions": decisions, "roles": roles}
	candidate.merge(image.metadata.duplicate(true))
	return {"ok": true, "env": candidate}

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
	if config.get("joint", false):
		graph.nodes.A.airfield_open = true
		graph.nodes.D.airfield_open = true
		for land: String in ["A", "B", "C", "D"]:
			graph.nodes[land].surface_bounds_km = [-1.0, -0.039999, 1.0, 1.0]
		# The shoreline is y=-0.04; the declared water corridor stays below it.
		for point: Array in [["PORT_B", [0.0, -0.06], "A"], ["SEA_M", [0.1, -0.06], ""], ["PORT_R", [0.2, -0.06], "D"], ["PORT_F", [0.12, -0.10], "B"]]:
			graph.nodes[point[0]] = {"xy": point[1], "cell": "field", "scope": graph.nodes.A.scope, "ground": F.ground("water"),
				"water": true, "port": point[2] != "", "port_open": true, "land_supply_node": point[2], "sea_visibility": 0.8, "sea_state": 0.2,
				"surface_bounds_km": [-1.0, -1.0, 1.0, -0.04]}
		for a: String in graph.nodes:
			for b: String in graph.nodes:
				if not graph.lanes.has(a + ":" + b):
					graph.lanes[a + ":" + b] = {"observe": true, "fire": true}
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
	if config.get("joint", false):
		people.red_commander = {"role": "company_commander", "formation_id": "red_company"}
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
		var motor: bool = bool(config.get("motor", false)) and state.units[id].side == "blue" or id in config.get("transport_motor_units", [])
		stocks[id] = {"fuel": float(config.get("fuel", 8.0)) if motor else 0.0, "fuel_spent": 0.0,
			"medical": float(config.get("medical_unit_stock", 0.0)) if id == "unit_001" else 0.0, "medical_spent": 0.0,
			"spares": 4.0, "spares_spent": 0.0, "serviceable_equipment": 12.0, "damaged_equipment": 0.0,
			"wear_damage": 0.0, "repair_restored": 0.0, "capability": {"fuel_dependent": motor,
				"fuel_per_equipment_km": 0.2 if motor else 0.0, "spares_per_repair": 1.0, "wear_per_km": 0.0, "suppression_per_round": 0.12}}
	var logistics: F.Logistics = F.Logistics.new()
	var depots: Dictionary = {"source": {"owner_ref": "synthetic_warehouse", "allocation_scope": "blue_company", "node_ref": "A", "stock": {"AMMUNITION": 100.0, "FUEL": 40.0, "SPARES": 20.0, "MEDICAL": float(config.get("medical_depot_stock", 0.0))}}}
	var capacities: Dictionary = {}
	if config.get("joint", false):
		depots.red_source = {"owner_ref": "synthetic_red_warehouse", "allocation_scope": "red_company", "node_ref": "D", "stock": {"AMMUNITION": 100.0, "FUEL": 40.0, "SPARES": 20.0, "MEDICAL": 0.0}}
		depots.front_source = {"owner_ref": "synthetic_forward_port_warehouse", "allocation_scope": "blue_company", "node_ref": "B", "stock": {"AMMUNITION": 0.0, "FUEL": 0.0, "SPARES": 0.0, "MEDICAL": 0.0}}
		capacities = {"blue_port_repair": {"scope": "blue_company", "remaining": 1.0}, "front_port_repair": {"scope": "blue_company", "remaining": 1.0}, "red_port_repair": {"scope": "red_company", "remaining": 1.0}}
	assert(logistics.configure(state, lod, structure, stocks, depots, capacities))
	var space: F.Space = F.Space.new()
	assert(space.configure(state, lod, graph.nodes, graph.edges, graph.lanes))
	if config.get("joint", false):
		assert(space.admit_waterways({"water_BM": {"from": "PORT_B", "to": "SEA_M", "length_km": 0.1, "open": true, "depth_km": 0.01, "water_only": true},
			"water_MR": {"from": "SEA_M", "to": "PORT_R", "length_km": 0.1, "open": true, "depth_km": 0.01, "water_only": true},
			"water_MF": {"from": "SEA_M", "to": "PORT_F", "length_km": 0.05, "open": true, "depth_km": 0.01, "water_only": true},
			"water_BF": {"from": "PORT_B", "to": "PORT_F", "length_km": 0.18, "open": true, "depth_km": 0.01, "water_only": true}}))
	for index: int in range(4):
		var point: String = str(config.get("blue_point", "A")) if index == 0 else ("A" if index == 1 else str(config.get("red_point", "D")))
		assert(space.admit_unit("unit_%03d" % index, point, "MOTORIZED" if config.get("motor", false) and index < 2 or "unit_%03d" % index in config.get("transport_motor_units", []) else "FOOT"))
	for index: int in range(extra_local):
		assert(space.admit_unit("local_extra_%02d" % index, "A", "FOOT"))
	var paths: Dictionary = {"A": [[], ["AB"], ["AC"]], "B": [[], ["AB"], ["bridge_BD"]],
		"C": [[], ["AC"], ["AB", "AC"], ["CD"]], "D": [[], ["AB", "bridge_BD"], ["AC", "CD"], ["AB", "AC", "CD"], ["bridge_BD"], ["CD"]]}
	var known: Dictionary = {}
	paths.A.append(["bridge_BD", "AB"])
	paths.B.append(["CD", "AC", "AB"])
	paths.A.append(["bridge_BD", "CD", "AC"])
	paths.B.append(["AC", "CD", "bridge_BD"])
	paths.B.append(["CD", "bridge_BD"])
	paths.B.append(["AC", "AB"])
	paths.C.append(["bridge_BD", "CD"])
	if config.get("joint", false):
		for node: String in ["PORT_B", "SEA_M", "PORT_R", "PORT_F"]:
			paths[node] = [[]] # Known point; never a land-road route.
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
	if config.get("joint", false):
		channels.red_command = {"senders": ["red_commander"], "recipients": ["red_commander"], "latency": float(config.get("command_latency", 15.0)), "available": true, "quality": 1.0, "command_scope": "red_company"}
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
	# Finite driver ceiling covers 24h at quota=1; it is not a kernel work quota.
	for index: int in range(10000000):
		output = env.lod.advance_bounded(target, quota)
		if output.get("status", "") != "PENDING":
			return output
	return {"ok": false, "error": "test_call_limit", "status": "BLOCKED"}

static func current(env: Dictionary, id: String = "unit_000") -> Dictionary:
	return env.state.missions[env.state.units[id].mission_id]
