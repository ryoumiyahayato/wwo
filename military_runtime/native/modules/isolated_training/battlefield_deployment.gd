extends RefCounted
## Reproducible scene data only. Original actors/Combat/weapons remain authoritative.
## Three simultaneous fronts: west village flank, central saddle, east wooded flank.
const PROFILE: String = "field_170"
const VEHICLES: int = 20 # Includes the original player vehicle, not a target decoration.
const INFANTRY: int = 150 # Excludes all 62 seated crew in this Scout deployment.
const LANES: Array[float] = [-260.0, 0.0, 260.0]

static func vehicle_rows(terrain: Node3D) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for team: String in ["blue", "red"]:
		for lane: int in range(3):
			for rank: int in range(3):
				var slot: int = lane * 3 + rank
				var x: float = LANES[lane] + (float(rank) - 1.0) * 16.0
				var z: float = 46.0 + float(rank) * 22.0 if team == "blue" else 190.0 + float(rank) * 22.0
				var point: Vector3 = _ground(terrain, Vector3(x, 0.0, z))
				rows.append({"id": "field_%s_vehicle_%02d" % [team, slot], "team": team, "position": point})
	# The former original target is one real enemy, retaining its Combat instance.
	rows.append({"id": "training_red_0", "team": "red", "position": _ground(terrain, Vector3(30.0, 0.0, 155.0)), "existing": true})
	return rows

static func infantry_rows(terrain: Node3D) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for team: String in ["blue", "red"]:
		var forward: float = 1.0 if team == "blue" else -1.0
		for lane: int in range(3):
			for squad: int in range(5):
				var squad_id: String = "field_%s_squad_%02d" % [team, lane * 5 + squad]
				var z: float = 6.0 + float(squad) * 13.0 if team == "blue" else 142.0 + float(squad) * 13.0
				for member: int in range(5):
					var lateral: float = (float(member) - 2.0) * 3.0
					var point: Vector3 = _ground(terrain, Vector3(LANES[lane] + lateral, 0.0, z))
					var flank: float = -16.0 if member < 2 else 16.0
					var objective_z: float = 100.0 if team == "blue" else 88.0
					var route: Array[Vector3] = [
						_ground(terrain, Vector3(point.x + flank, 0.0, z + forward * 9.0)),
						_ground(terrain, Vector3(LANES[lane] + lateral + flank, 0.0, objective_z)),
						_ground(terrain, Vector3(LANES[lane] + lateral - flank, 0.0, objective_z + forward * 12.0))
					]
					rows.append({"id": "%s_member_%d" % [squad_id, member], "team": team, "position": point, "route": route, "squad_id": squad_id, "member": member})
	return rows

static func _ground(terrain: Node3D, point: Vector3) -> Vector3:
	return Vector3(point.x, float(terrain.call("sample_height", point.x, point.z)), point.z)
