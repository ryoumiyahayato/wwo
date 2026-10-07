extends RefCounted
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Data = preload("res://experiments/war_resolver/data.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")

static func battle(count: int = 40, seed_value: int = 71, sleeping: int = 0,
		cell: String = "field", sparse: bool = false) -> State:
	var state: State = State.new()
	state.seed = seed_value
	state.add_area(Data.area(cell))
	for index: int in range(count):
		var attack: bool = index < count / 2
		var id: String = "unit_%03d" % index
		var mission: Dictionary = Data.mission("mission_" + id, "advance" if attack else "hold", 1.0, 2.0)
		state.add_mission(mission)
		var unit: Dictionary = Data.unit(id, "blue" if attack else "red", cell, mission.id, 0.5 if attack else 3.5)
		if sparse:
			unit.position = float(index) * 0.049
			unit.mobility = 0.0
			unit.weapon.range_km = 0.005
			if index == count / 2:
				unit.position = 0.001
		state.add_unit(unit)
	state.add_mission(Data.mission("sleep", "idle"))
	for area: int in range(sleeping):
		var id: String = "sleep_%06d" % area
		state.add_area(Data.area(id))
		for squad: int in range(3):
			state.add_unit(Data.unit(id + "_%d" % squad, "neutral", id, "sleep"))
	return state

static func coalesce_sides(authority: Authority, state: State, count: int, group_size: int = 10) -> Array[String]:
	var aggregates: Array[String] = []
	for start: int in range(0, count, group_size):
		var ids: Array[String] = []
		for index: int in range(start, mini(count, start + group_size)):
			ids.append("unit_%03d" % index)
		var result: Dictionary = authority.coalesce("formation_%03d" % start, ids)
		assert(result.ok, str(result))
		aggregates.append(str(result.aggregate_id))
	return aggregates

static func hierarchy(all_active: bool = false) -> State:
	var state: State = State.new()
	state.seed = 71
	for cell: int in range(100):
		var area: String = "cell_%03d" % cell
		state.add_area(Data.area(area))
		for index: int in range(4):
			var id: String = area + "_unit_%02d" % index
			var posture: String = "advance" if index < 2 else "hold"
			if not all_active and cell != 37:
				posture = "idle"
			state.add_mission(Data.mission("mission_" + id, posture, 1.0, 2.0))
			state.add_unit(Data.unit(id, "blue" if index < 2 else "red", area, "mission_" + id, 0.5 if index < 2 else 3.5))
	return state

static func coalesce_cell(authority: Authority, cell: String) -> void:
	for start: int in [0, 2]:
		var ids: Array[String] = [cell + "_unit_%02d" % start, cell + "_unit_%02d" % (start + 1)]
		assert(authority.coalesce(cell + "_formation_%02d" % start, ids).ok)
