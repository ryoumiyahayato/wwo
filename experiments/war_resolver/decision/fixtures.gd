extends RefCounted
const Base = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
const Service = preload("res://experiments/war_resolver/structure/service.gd")
const Commands = preload("res://experiments/war_resolver/structure/commands.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const Logistics = preload("res://experiments/war_resolver/logistics/service.gd")
const Supply = preload("res://experiments/war_resolver/logistics/commands.gd")
const LogF = preload("res://experiments/war_resolver/logistics/fixtures.gd")
const InfoF = preload("res://experiments/war_resolver/information/fixtures.gd")
const Information = preload("res://experiments/war_resolver/information/service.gd")
const Reader = preload("res://experiments/war_resolver/information/reader.gd")
const Decision = preload("res://experiments/war_resolver/decision/service.gd")
const Policy = preload("res://experiments/war_resolver/decision/test_policy.gd")
const Adapter = preload("res://experiments/war_resolver/decision/adapter.gd")

static func setup(count: int = 40, sleeping: int = 0, aggregate: bool = true, seed_value: int = 71, enabled: bool = true, persons: int = 8) -> Dictionary:
	var motor: bool = true
	var fuel: float = 8.0
	var serviceability: float = 0.75
	var ammo: float = 1200.0
	var wear: float = 0.01
	var env: Dictionary = _military_setup(count, sleeping, false, seed_value, persons)
	var facts: Dictionary = {}
	for index: int in range(count):
		var id: String = "unit_%03d" % index
		var unit: Dictionary = env.state.units[id]
		env.state.totals.ammunition += ammo - float(unit.ammunition)
		unit.ammunition = ammo
		# Broad input capability enables actual fire in the uniform experiment cell.
		unit.weapon.range_km = 5.0
		facts[id] = {"fuel": fuel if motor else 0.0, "fuel_spent": 0.0,
			"spares": 4.0, "spares_spent": 0.0, "serviceable_equipment": float(unit.equipment) * serviceability,
			"damaged_equipment": float(unit.equipment) * (1.0 - serviceability), "wear_damage": 0.0, "repair_restored": 0.0,
			"capability": {"fuel_dependent": motor, "fuel_per_equipment_km": 0.2 if motor else 0.0,
				"spares_per_repair": 1.0, "wear_per_km": wear, "suppression_per_round": 0.12}}
	var service: Logistics = Logistics.new()
	var depots: Dictionary = {"source": {"owner_ref": "external_warehouse_owner", "allocation_scope": "blue_company", "stock": {"AMMUNITION": 1000000.0, "FUEL": 100000.0, "SPARES": 100000.0}},
		"recipient_source": {"owner_ref": "other_warehouse_owner", "allocation_scope": "blue_company_b", "stock": {"AMMUNITION": 1000000.0, "FUEL": 100000.0, "SPARES": 100000.0}}}
	assert(service.configure(env.state, env.lod, env.service, facts, depots, {"workshop": {"remaining": 1000.0, "scope": "blue_company"}, "other_workshop": {"remaining": 1000.0, "scope": "blue_company_b"}}))
	env.logistics = service
	env.supply_commands = {}
	for person: String in State.sorted_ids(env.people):
		var adapter: Supply = Supply.new()
		assert(adapter.configure(service, person))
		env.supply_commands[person] = adapter
	if aggregate:
		for start: int in range(0, count, 10):
			var ids: Array[String] = []
			for index: int in range(start, mini(start + 10, count)):
				ids.append("unit_%03d" % index)
			assert(env.lod.coalesce("platoon_%03d" % start, ids).ok)
	service.reset_work()
	var sources: Dictionary = {}
	for person: String in env.people:
		sources["source_" + person] = {"observer_ref": person, "scope_ref": env.people[person].formation_id,
			"origin": "DIRECT", "quality": 0.9, "precision_km": 0.5, "fact_kinds": Information.FACTS.duplicate()}
	sources.external_company = {"observer_ref": "company", "scope_ref": "blue_division", "origin": "EXTERNAL", "quality": 0.3, "precision_km": 0.5, "fact_kinds": Information.FACTS.duplicate()}
	sources.external_division = {"observer_ref": "division", "scope_ref": "blue_division", "origin": "EXTERNAL", "quality": 0.95, "precision_km": 0.5, "fact_kinds": Information.FACTS.duplicate()}
	var channels: Dictionary = {}
	for pair: Array in [["instant", 0.0], ["delayed", 47.0], ["decision_channel", 15.0]]:
		channels[pair[0]] = {"senders": State.sorted_ids(env.people), "recipients": State.sorted_ids(env.people), "latency": pair[1], "available": true, "quality": 0.8, "command_scope": "blue_division"}
	var information: Information = Information.new()
	assert(information.configure(env.state, env.lod, env.service, env.logistics, env.roles, sources, channels))
	env.information = information
	env.readers = {}
	for person: String in env.people:
		var reader: Reader = Reader.new()
		assert(reader.configure(information, person))
		env.readers[person] = reader
	if enabled:
		var decision: Decision = Decision.new()
		assert(decision.configure(env.state, information, env.service, env.logistics))
		env.decisions = decision
		env.adapters = {}
		for person: String in env.people:
			var provider: Policy = Policy.new()
			var adapter: Adapter = Adapter.new()
			assert(adapter.configure("autonomous", provider))
			assert(decision.enroll(person, definition(person, env.people[person]), adapter))
			env.adapters[person] = adapter
	return env

static func _military_setup(count: int = 40, sleeping: int = 0, aggregate: bool = true, seed_value: int = 71, persons: int = 8) -> Dictionary:
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
	for index: int in range(8, persons):
		people["person_%04d" % index] = {"role": "ordinary_soldier", "formation_id": "node_unit_000"}
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

static func definition(person: String, position: Dictionary) -> Dictionary:
	var rank: int = Roles.ROLES.find(str(position.role))
	var targets: Array[String] = [str(position.formation_id)]
	if rank >= 2:
		targets.append("node_unit_000")
	if rank >= 3:
		targets.append("platoon_000")
	if rank >= 5:
		targets.append("blue_destination")
	return {"targets": targets, "cadence": Roles.INPUT_SECONDS[rank], "urgent": person in ["company", "platoon"],
		"standing_orders": {"target": "blue_company" if person == "company" else "node_unit_000",
			"attachment": {"target": "node_unit_000", "parent": "blue_destination", "delay": 10.0, "duration": 60.0}}}

static func claim(env: Dictionary, id: String = "report", person: String = "platoon", fact: String = "status", value: Dictionary = {}, channel: String = "instant", source: String = "external_company", observed: float = 0.0) -> Dictionary:
	var payload: Dictionary = value if not value.is_empty() else {"states": ["hold"]}
	var producer: String = "company" if source == "external_company" else "division"
	var observation: Dictionary = InfoF.external(env, "observation_" + id, source, fact, payload, observed)
	return InfoF.report(env, id, "observation_" + id, producer, person, channel) if observation.ok else observation

static func opportunity(env: Dictionary, id: String = "decision", person: String = "platoon", time: float = 10.0) -> Dictionary:
	return env.decisions.schedule(person, id, time)

static func policy(env: Dictionary, person: String, mode: String) -> void:
	env.adapters[person]._policy.mode = mode
