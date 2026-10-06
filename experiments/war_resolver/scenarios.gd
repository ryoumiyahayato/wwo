extends RefCounted
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Data = preload("res://experiments/war_resolver/data.gd")
const NAMES: Array[String] = ["open_field_attack", "covered_defense", "village_edge",
	"road_bottleneck", "ammo_shortage", "communication_delay"]


static func create(name: String = "open_field_attack", battle_seed: int = 71,
		sleeping_areas: int = 0, reverse_insertion: bool = false) -> State:
	assert(name in NAMES)
	var state: State = State.new()
	state.seed = battle_seed
	var field: Dictionary = Data.area("field")
	if name == "covered_defense":
		field.cover = 0.75
		field.concealment = 0.35
	if name == "village_edge":
		field.cover = 0.55
		field.movement_modifier = 0.65
	if name == "road_bottleneck":
		field.frontage = 10.0
		field.movement_modifier = 0.5
	state.add_area(field)
	var records: Array[Dictionary] = []
	for index: int in range(6):
		var id: String = "attack_%02d" % index
		var mission: Dictionary = Data.mission("mission_" + id, "advance", 1.0, 2.0)
		state.add_mission(mission)
		var unit: Dictionary = Data.unit(id, "blue", "field", mission.id, 0.5)
		if name == "ammo_shortage":
			unit.ammunition = 3.0
		records.append(unit)
	for index: int in range(4):
		var id: String = "defend_%02d" % index
		var mission: Dictionary = Data.mission("mission_" + id)
		state.add_mission(mission)
		records.append(Data.unit(id, "red", "field", mission.id, 3.5))
	if reverse_insertion:
		records.reverse()
	for unit: Dictionary in records:
		state.add_unit(unit)
	if name == "communication_delay":
		state.add_mission(Data.mission("await_orders", "idle"))
		for index: int in range(6):
			var id: String = "attack_%02d" % index
			state.units[id].mission_id = "await_orders"
			assert(state.schedule_event("order_" + id, 900.0, "order", {"unit_id": id, "mission_id": "mission_" + id}))
	# Input/index construction is intentionally outside benchmark timing/counters.
	state.add_mission(Data.mission("sleep", "idle"))
	for index: int in range(sleeping_areas):
		var area_id: String = "sleep_%06d" % index
		state.add_area(Data.area(area_id))
		for squad: int in range(3):
			state.add_unit(Data.unit(area_id + "_" + str(squad), "neutral", area_id, "sleep"))
	return state
