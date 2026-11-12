extends RefCounted
## Static presentation/obstacle poses only; never deform the authoritative field.

static func pose(row: Dictionary, terrain: Object) -> Transform3D:
	var coordinates: Array = row.position
	var point: Vector3 = Vector3(float(coordinates[0]), 0.0, float(coordinates[2]))
	point.y = float(terrain.call("sample_height", point.x, point.z)) + float(row.get("ground_offset_m", 0.0))
	var scale_factor: float = float(row.scale)
	var basis: Basis = Basis(Vector3.UP, float(row.yaw))
	var kind: String = str(row.kind)
	if point.is_finite() and kind == "wall_4m":
		# Horizontal 4m wall segments left an end hovering on sloped native ground.
		# Tilt art AND its collider together; buildings remain upright.
		var left: float = float(terrain.call("sample_height", point.x - 2.0, point.z))
		var right: float = float(terrain.call("sample_height", point.x + 2.0, point.z))
		var back: float = float(terrain.call("sample_height", point.x, point.z - 2.0))
		var front: float = float(terrain.call("sample_height", point.x, point.z + 2.0))
		if is_finite(left) and is_finite(right) and is_finite(back) and is_finite(front):
			var up: Vector3 = Vector3(left - right, 4.0, back - front).normalized()
			var axis_z: Vector3 = (basis.z - up * basis.z.dot(up)).normalized()
			basis = Basis(up.cross(axis_z).normalized(), up, axis_z)
	if kind.begins_with("rock_"):
		point.y -= 0.08 * scale_factor
	return Transform3D(basis.scaled(Vector3.ONE * scale_factor), point)

static func route_rows() -> Array[Dictionary]:
	# Fictional encounter dressing, opt-in ONLY. Original large deployment is intact.
	# Existing source GLBs/collider specs; keep the 10m central road unobstructed.
	var rows: Array[Dictionary] = []
	var stones: Array[Vector3] = [Vector3(-19, 0, 24), Vector3(22, 0, 42), Vector3(-25, 0, 87), Vector3(27, 0, 115), Vector3(-21, 0, 142), Vector3(19, 0, 161)]
	for index: int in range(stones.size()):
		var point: Vector3 = stones[index]
		rows.append({"id": "encounter_stone_%d" % index, "kind": "rock_%d" % (index % 3), "position": [point.x, point.y, point.z], "yaw": float(index) * 1.3, "scale": 0.55 + float(index % 2) * 0.15})
	for index: int in range(4):
		rows.append({"id": "encounter_wall_%d" % index, "kind": "wall_4m", "position": [-34.0, 0.0, 65.0 + index * 4.0], "yaw": PI * 0.5, "scale": 1.0})
	for index: int in range(3):
		rows.append({"id": "encounter_hay_%d" % index, "kind": "hay_roll", "position": [32.0 + index * 2.5, 0.0, 95.0], "yaw": float(index) * 0.8, "scale": 0.65})
	return rows
