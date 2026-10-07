extends RefCounted
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Base = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
const Service = preload("res://experiments/war_resolver/structure/service.gd")
const Commands = preload("res://experiments/war_resolver/structure/commands.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")

static func setup(count: int = 40, sleeping: int = 0, aggregate: bool = true, seed_value: int = 71) -> Dictionary:
	var state: State = Base.battle(count, seed_value, sleeping, "cell_037")
	var nodes: Dictionary = {}
	for side: String in ["blue", "red"]:
		for echelon: String in ["division", "regiment", "battalion", "company"]:
			var id: String = side + "_" + echelon
			var rank: int = Roles.ECHELONS.find(echelon)
			nodes[id] = {"echelon": echelon, "side": side, "parent": "" if rank == 5 else side + "_" + Roles.ECHELONS[rank + 1]}
		nodes[side + "_battalion_b"] = {"echelon": "battalion", "side": side, "parent": side + "_regiment"}
		nodes[side + "_company_b"] = {"echelon": "company", "side": side, "parent": side + "_battalion_b"}
		nodes[side + "_destination"] = {"echelon": "platoon", "side": side, "parent": side + "_company_b"}
	for index: int in range(count):
		var side: String = "blue" if index < count / 2 else "red"
		var group: String = "platoon_%03d" % (index / 10 * 10)
		if not nodes.has(group):
			nodes[group] = {"echelon": "platoon", "side": side, "parent": side + "_company"}
		var unit: String = "unit_%03d" % index
		nodes["node_" + unit] = {"echelon": "squad", "side": side, "parent": group, "unit_id": unit}
	var people: Dictionary = {"soldier": {"role": "ordinary_soldier", "formation_id": "node_unit_000"},
		"squad": {"role": "squad_leader", "formation_id": "node_unit_000"},
		"platoon": {"role": "platoon_leader", "formation_id": "platoon_000"},
		"company": {"role": "company_commander", "formation_id": "blue_company"},
		"battalion": {"role": "battalion_commander", "formation_id": "blue_battalion"},
		"recipient": {"role": "battalion_commander", "formation_id": "blue_battalion_b"},
		"regiment": {"role": "regiment_commander", "formation_id": "blue_regiment"},
		"division": {"role": "division_commander", "formation_id": "blue_division"}}
	var lod: Authority = Authority.new()
	assert(lod.configure(state))
	var service: Service = Service.new()
	assert(service.configure(state, lod, nodes, people))
	var roles: Dictionary = {}
	var commands: Dictionary = {}
	for person: String in State.sorted_ids(people):
		var role: Roles = Roles.new()
		assert(role.configure(state, nodes, people, person))
		assert(role.bind_lod(lod) and role.bind_structure(service))
		roles[person] = role
		var adapter: Commands = Commands.new()
		assert(adapter.configure(service, person))
		commands[person] = adapter
	if aggregate:
		for start: int in range(0, count, 10):
			var ids: Array[String] = []
			for index: int in range(start, mini(start + 10, count)):
				ids.append("unit_%03d" % index)
			assert(lod.coalesce("platoon_%03d" % start, ids).ok)
	service.work.structure_records_examined = 0
	return {"state": state, "lod": lod, "service": service, "roles": roles, "commands": commands, "nodes": nodes, "people": people}

static func request(id: String, kind: String, time: float, values: Dictionary) -> Dictionary:
	return {"id": id, "kind": kind, "effective_time": time, "values": values}

static func split_request(env: Dictionary, id: String = "split", fraction: float = 0.25, source: String = "unit_000", fresh: String = "detachment") -> Dictionary:
	var unit: Dictionary = env.lod.preview_leaf(source)
	var allocation: Dictionary = {}
	for key: String in Service.Stocks:
		allocation[key] = float(unit[key]) * fraction
	return request(id, "split", float(env.state.time), {"source": source, "new_id": fresh, "new_node": "node_" + fresh, "allocation": allocation})

static func company_split(env: Dictionary, fraction: float = 0.25) -> Dictionary:
	var allocation: Dictionary = {}
	for key: String in Service.Stocks:
		allocation[key] = 0.0
	for leaf: String in env.service.leaves("blue_company"):
		var unit: Dictionary = env.lod.preview_leaf(str(env.service.node(leaf).unit_id))
		for key: String in Service.Stocks:
			allocation[key] += float(unit[key]) * fraction
	return request("company_detachment", "split", float(env.state.time), {"source": "blue_company",
		"new_id": "detached_company", "new_node": "detached_company", "allocation": allocation})
