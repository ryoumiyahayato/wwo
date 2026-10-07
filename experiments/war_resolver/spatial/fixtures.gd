extends RefCounted
## Synthetic input builder. No scenario assigns outcomes after admission.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Data = preload("res://experiments/war_resolver/data.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
const Structure = preload("res://experiments/war_resolver/structure/service.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const Logistics = preload("res://experiments/war_resolver/logistics/service.gd")
const Space = preload("res://experiments/war_resolver/spatial/space.gd")

static func ground(label: String = "plain", resistance: float = 0.0, softness: float = 0.0, slope: float = 0.0, cover: float = 0.0, concealment: float = 0.0) -> Dictionary:
	return {"label": label, "resistance": resistance, "softness": softness, "slope": slope,
		"cover": cover, "concealment": concealment, "visibility": 1.0, "width": 1000.0}

static func topology(renamed: bool = false) -> Dictionary:
	var cells: Array[String] = ["cell_037", "cell_038", "cell_062", "cell_063"]
	if renamed:
		cells = ["cell_011", "cell_013", "cell_079", "cell_081"]
	var nodes: Dictionary = {}
	for index: int in range(4):
		var name: String = ["A", "B", "C", "D"][index]
		nodes[name] = {"xy": [[0.0, 0.0], [0.1, 0.0], [0.0, 0.1], [0.1, 0.1]][index],
			"cell": cells[index], "scope": "local_envelope", "ground": ground()}
	var edges: Dictionary = {}
	for pair: Array in [["AB", "A", "B"], ["bridge_BD", "B", "D"], ["AC", "A", "C"], ["CD", "C", "D"]]:
		edges[pair[0]] = {"from": pair[1], "to": pair[2], "length_km": 0.1, "open": true,
			"kind": "bridge" if pair[0] == "bridge_BD" else "road", "modes": ["FOOT", "MOTORIZED"], "ground": ground(), "capacity": 100.0}
	var lanes: Dictionary = {}
	for a: String in nodes:
		for b: String in nodes:
			lanes[a + ":" + b] = {"observe": true, "fire": true}
	return {"nodes": nodes, "edges": edges, "lanes": lanes}

static func setup(motor: bool = true, combat: bool = false, renamed: bool = false, seed_value: int = 71, split_red: bool = false, reverse_inputs: bool = false, inputs: Dictionary = {}) -> Dictionary:
	var state: State = State.new()
	state.seed = seed_value
	for index: int in range(100):
		state.add_area(Data.area("cell_%03d" % index))
	var graph: Dictionary = topology(renamed)
	for edge: String in inputs.get("edge_ground", {}):
		graph.edges[edge].ground = inputs.edge_ground[edge].duplicate(true)
	if reverse_inputs:
		for key: String in ["nodes", "edges", "lanes"]:
			var reordered: Dictionary = {}
			var ids: Array[String] = State.sorted_ids(graph[key])
			ids.reverse()
			for id: String in ids:
				reordered[id] = graph[key][id]
			graph[key] = reordered
	var nodes: Dictionary = {"blue_company": {"echelon": "company", "side": "blue", "parent": ""},
		"blue_platoon": {"echelon": "platoon", "side": "blue", "parent": "blue_company"},
		"blue_destination": {"echelon": "platoon", "side": "blue", "parent": "blue_company"},
		"red_company": {"echelon": "company", "side": "red", "parent": ""},
		"red_platoon": {"echelon": "platoon", "side": "red", "parent": "red_company"}}
	var unit_order: Array[int] = [0, 1, 2, 3]
	if reverse_inputs:
		unit_order.reverse()
	for index: int in unit_order:
		var id: String = "unit_%03d" % index
		var point: String = "A" if index < 2 else ("C" if split_red and index == 3 else "D")
		var mission: Dictionary = Data.mission("mission_" + id, "advance" if index < 2 else "hold", 1.0, 0.1)
		state.add_mission(mission)
		var unit: Dictionary = Data.unit(id, "blue" if index < 2 else "red", graph.nodes[point].cell, mission.id)
		unit.mobility = float(inputs.get("mobility", 0.6))
		unit.ammunition = float(inputs.get("blue_ammunition", 100.0)) if combat and index < 2 else (100.0 if combat else 0.0)
		unit.weapon.range_km = float(inputs.get("range_km", 0.3)) if combat else 0.0
		state.add_unit(unit)
		nodes["node_" + id] = {"echelon": "squad", "side": unit.side,
			"parent": "blue_platoon" if index < 2 else "red_platoon", "unit_id": id}
	var background: Dictionary = {}
	if inputs.get("background", false):
		background = _background(state, nodes, graph, float(inputs.get("background_mobility", 0.08)))
	var people: Dictionary = {"squad": {"role": "squad_leader", "formation_id": "node_unit_000"},
		"platoon": {"role": "platoon_leader", "formation_id": "blue_platoon"},
		"recipient": {"role": "platoon_leader", "formation_id": "blue_destination"},
		"company": {"role": "company_commander", "formation_id": "blue_company"}}
	var lod: Authority = Authority.new()
	assert(lod.configure(state))
	var structure: Structure = Structure.new()
	assert(structure.configure(state, lod, nodes, people))
	var roles: Dictionary = {}
	for person: String in people:
		var role: Roles = Roles.new()
		assert(role.configure(state, nodes, people, person) and role.bind_lod(lod) and role.bind_structure(structure))
		roles[person] = role
	var facts: Dictionary = {}
	for id: String in state.units:
		var is_motor: bool = motor and state.units[id].side == "blue"
		facts[id] = {"fuel": 8.0 if is_motor else 0.0, "fuel_spent": 0.0,
			"spares": 4.0, "spares_spent": 0.0, "serviceable_equipment": 12.0,
			"damaged_equipment": 0.0, "wear_damage": 0.0, "repair_restored": 0.0,
			"capability": {"fuel_dependent": is_motor, "fuel_per_equipment_km": 0.2 if is_motor else 0.0,
				"spares_per_repair": 1.0, "wear_per_km": 0.0, "suppression_per_round": 0.12}}
	var logistics: Logistics = Logistics.new()
	assert(logistics.configure(state, lod, structure, facts, {"source": {"owner_ref": "synthetic_warehouse",
		"allocation_scope": "blue_company", "stock": {"AMMUNITION": 100.0, "FUEL": 40.0, "SPARES": 20.0}}}, {}))
	var space: Space = Space.new()
	assert(space.configure(state, lod, graph.nodes, graph.edges, graph.lanes))
	for index: int in range(4):
		var point: String = "A" if index < 2 else ("C" if split_red and index == 3 else "D")
		assert(space.admit_unit("unit_%03d" % index, point, "MOTORIZED" if motor and index < 2 else "FOOT"))
	for id: String in background.get("units", {}):
		var spec: Dictionary = background.units[id]
		assert(space.admit_unit(id, spec.node, "MOTORIZED" if spec.blue else "FOOT"))
		if spec.active and spec.blue:
			assert(space.inject_path(id, [spec.edge]).ok)
	return {"state": state, "lod": lod, "service": structure, "structure": structure, "roles": roles,
		"logistics": logistics, "space": space, "graph": graph, "people": people, "nodes": nodes, "background": background}

static func _background(state: State, nodes: Dictionary, graph: Dictionary, mobility: float) -> Dictionary:
	var units: Dictionary = {}
	var groups: Dictionary = {}
	for cell_index: int in range(100):
		var cell: String = "cell_%03d" % cell_index
		var scope: String = "local_envelope" if cell_index in [37, 38, 62, 63] else "scope_" + cell
		var points: Array[String] = ["bg_point_%03d_blue" % cell_index, "bg_point_%03d_red" % cell_index]
		var x: float = float(cell_index % 10) * 5.0 + 0.5
		var y: float = float(cell_index / 10) * 5.0 + 0.5
		for side_index: int in range(2):
			graph.nodes[points[side_index]] = {"xy": [x + 3.0 * side_index, y], "cell": cell, "scope": scope,
				"ground": ground("synthetic_background", 0.0, 0.0, 0.0, 0.1, 0.05)}
		var edge: String = "bg_edge_%03d" % cell_index
		graph.edges[edge] = {"from": points[0], "to": points[1], "length_km": 3.0, "open": true,
			"kind": "road", "modes": ["FOOT", "MOTORIZED"], "ground": ground(), "capacity": 100.0}
		for a: String in points:
			for b: String in points:
				graph.lanes[a + ":" + b] = {"observe": true, "fire": true}
		for index: int in range(4):
			if cell_index == 37 and index < 2 or cell_index == 63 and index >= 2:
				continue # The four main scenario leaves occupy these slots.
			var id: String = "bg_%03d_%d" % [cell_index, index]
			var blue: bool = index < 2
			var active: bool = cell_index < 15
			var side: String = "blue" if blue else "red"
			var parent: String = "bg_" + side + "_%03d" % cell_index
			if not nodes.has(parent):
				nodes[parent] = {"echelon": "platoon", "side": side, "parent": side + "_company"}
				groups[parent] = []
			groups[parent].append(id)
			var mission: Dictionary = Data.mission("mission_" + id, ("advance" if blue else "hold") if active else "idle", 1.0, 3.0)
			state.add_mission(mission)
			var unit: Dictionary = Data.unit(id, side, cell, mission.id)
			unit.mobility = mobility
			unit.ammunition = 20.0 if active else 0.0
			unit.weapon.range_km = 0.2
			if cell_index == 63 and index == 1:
				unit.weapon.rounds_per_minute = 0.9 # Explicit incompatible cohort; must remain detailed.
			state.add_unit(unit)
			nodes["node_" + id] = {"echelon": "squad", "side": side, "parent": parent, "unit_id": id}
			units[id] = {"node": points[0] if blue else points[1], "edge": edge, "blue": blue, "active": active}
	return {"units": units, "groups": groups, "underlying_leaves": 400, "initial_background_active_cells": 15, "mobility_km_per_minute": mobility}
