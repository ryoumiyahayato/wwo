extends RefCounted
const Base = preload("res://experiments/war_resolver/structure/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Service = preload("res://experiments/war_resolver/logistics/service.gd")
const Commands = preload("res://experiments/war_resolver/logistics/commands.gd")

static func setup(count: int = 40, sleeping: int = 0, aggregate: bool = true,
		motor: bool = true, fuel: float = 8.0, serviceability: float = 0.75,
		ammo: float = 1200.0, seed_value: int = 71, wear: float = 0.01) -> Dictionary:
	var env: Dictionary = Base.setup(count, sleeping, false, seed_value)
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
	var service: Service = Service.new()
	var depots: Dictionary = {"source": {"owner_ref": "external_warehouse_owner", "allocation_scope": "blue_company", "stock": {"AMMUNITION": 1000000.0, "FUEL": 100000.0, "SPARES": 100000.0}},
		"recipient_source": {"owner_ref": "other_warehouse_owner", "allocation_scope": "blue_company_b", "stock": {"AMMUNITION": 1000000.0, "FUEL": 100000.0, "SPARES": 100000.0}}}
	assert(service.configure(env.state, env.lod, env.service, facts, depots, {"workshop": {"remaining": 1000.0, "scope": "blue_company"}, "other_workshop": {"remaining": 1000.0, "scope": "blue_company_b"}}))
	env.logistics = service
	env.supply_commands = {}
	for person: String in State.sorted_ids(env.people):
		var adapter: Commands = Commands.new()
		assert(adapter.configure(service, person))
		env.supply_commands[person] = adapter
	if aggregate:
		for start: int in range(0, count, 10):
			var ids: Array[String] = []
			for index: int in range(start, mini(start + 10, count)):
				ids.append("unit_%03d" % index)
			assert(env.lod.coalesce("platoon_%03d" % start, ids).ok)
	service.reset_work()
	return env

static func delivery(env: Dictionary, id: String = "delivery", kind: String = "formation", target: String = "blue_company",
		resource: String = "AMMUNITION", quantity: float = 100.0, time: float = 60.0, person: String = "company", source: String = "source") -> Dictionary:
	var requested: Dictionary = env.supply_commands[person].submit({"id": "request_" + id, "kind": "request", "target_kind": kind, "target": target, "resource_class": resource, "quantity": quantity})
	if not requested.ok:
		return requested
	return env.supply_commands[person].submit({"id": id, "kind": "allocate", "request_id": "request_" + id, "source_ref": source, "delivery_time": time})

static func repair(env: Dictionary, id: String = "repair", kind: String = "formation", target: String = "blue_company", quantity: float = 1.0, time: float = 60.0) -> Dictionary:
	return env.supply_commands.company.submit({"id": id, "kind": "maintenance", "target_kind": kind, "target": target, "quantity": quantity, "capacity_ref": "workshop", "effective_time": time})

static func split(env: Dictionary, id: String = "split", source: String = "unit_000", fresh: String = "detachment") -> Dictionary:
	var unit: Dictionary = env.lod.preview_leaf(source)
	var allocation: Dictionary = {}
	for key: String in env.service.stock_keys():
		allocation[key] = float(unit.get(key, 0.0)) * 0.25
	return Base.request(id, "split", float(env.state.time), {"source": source, "new_id": fresh, "new_node": "node_" + fresh, "allocation": allocation})

static func idle(env: Dictionary) -> void:
	for id: String in env.state.missions:
		env.state.missions[id].posture = "idle"
	for id: String in env.state.units:
		var unit: Dictionary = env.state.units[id]
		env.state.missions[unit.mission_id].posture = "idle"
		unit.suppression = 0.0
	env.state.active_areas.clear()

static func stocks(env: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in env.lod.stock_keys():
		result[key] = 0.0
	for id: String in env.state.area_units.cell_037:
		for key: String in result:
			result[key] += float(env.state.units[id].get(key, 0.0))
	return result
