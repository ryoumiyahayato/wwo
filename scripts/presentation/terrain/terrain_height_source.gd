extends RefCounted
## Pure data work for LayeredTerrain. Worker jobs never access the scene tree.
## Source coordinates are metres in an explicitly fictional training region.

const REGION_WIDTH: int = 1001
const REGION_STEP: float = 50.0
const REGION_ORIGIN: float = -22500.0
const NATIVE_WIDTH: int = 1251
const NATIVE_STEP: float = 4.0
const NATIVE_ORIGIN: float = -2500.0


static func run_timed_job(task: Callable, context: Dictionary) -> Variant:
	# Opt-in wrapper only. No scene-tree/Engine queries on the worker thread.
	var started_usec: int = Time.get_ticks_usec()
	var result: Variant = task.call()
	var ended_usec: int = Time.get_ticks_usec()
	if result is Dictionary:
		var timing: Dictionary = context.duplicate()
		timing["start_usec"] = started_usec
		timing["end_usec"] = ended_usec
		result["_slow_worker"] = timing
	return result


static func read_sources(base_path: String) -> Dictionary:
	var metadata_path: String = base_path + "continuous/assets/region.json"
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "缺少训练地形说明：" + metadata_path}
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not decoded is Dictionary:
		return {"ok": false, "error": "训练地形说明不是有效 JSON 对象"}
	var metadata: Dictionary = decoded
	if str(metadata.get("schema", "")) != "continuous-training-region-v1" or metadata.get("training_only", false) != true:
		return {"ok": false, "error": "只接受 continuous-training-region-v1 的 training_only 地形"}
	if not _matches_bounds(metadata.get("bounds"), [-22500.0, -22500.0, 27500.0, 27500.0]):
		return {"ok": false, "error": "50km 训练地形坐标范围不匹配"}
	if not _matches_bounds(metadata.get("native_ridgevale_bounds"), [-2500.0, -2500.0, 2500.0, 2500.0]):
		return {"ok": false, "error": "5km Ridgevale 训练地形坐标范围不匹配"}
	var region: Dictionary = _read_floats(base_path + "continuous/assets/height_50m.f32", REGION_WIDTH)
	if not bool(region.get("ok", false)):
		return region
	var native: Dictionary = _read_floats(base_path + "ridgevale/assets/height_4m.f32", NATIVE_WIDTH)
	return {
		"ok": true,
		"region": region["heights"],
		"native": native.get("heights", PackedFloat32Array()),
		"native_error": str(native.get("error", "")),
		"training_only": true,
	}


static func _matches_bounds(value: Variant, expected: Array) -> bool:
	if not value is Array:
		return false
	var numbers: Array = value
	if numbers.size() != expected.size():
		return false
	for index: int in expected.size():
		var number: Variant = numbers[index]
		if not (number is float or number is int):
			return false
		if not is_finite(float(number)) or not is_equal_approx(float(number), float(expected[index])):
			return false
	return true


static func _read_floats(path: String, width: int) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "缺少高度源：" + path}
	var expected_bytes: int = width * width * 4
	if file.get_length() != expected_bytes:
		file.close()
		return {"ok": false, "error": "高度源字节数不匹配：" + path}
	var bytes: PackedByteArray = file.get_buffer(expected_bytes)
	file.close()
	var heights: PackedFloat32Array = bytes.to_float32_array()
	if heights.size() != width * width:
		return {"ok": false, "error": "高度源未完整读取：" + path}
	for height: float in heights:
		if not is_finite(height):
			return {"ok": false, "error": "高度源含非有限数值：" + path}
	return {"ok": true, "heights": heights}


static func sample(heights: PackedFloat32Array, width: int, origin: float, step: float, x: float, z: float) -> float:
	if heights.size() != width * width or not is_finite(x) or not is_finite(z):
		return NAN
	var edge: float = origin + float(width - 1) * step
	if x < origin or z < origin or x > edge or z > edge:
		return NAN
	return _sample_grid(heights, width, origin, step, x, z)


static func _sample_grid(heights: PackedFloat32Array, width: int, origin: float, step: float, x: float, z: float) -> float:
	var fx: float = clampf((x - origin) / step, 0.0, float(width - 1))
	var fz: float = clampf((z - origin) / step, 0.0, float(width - 1))
	var ix: int = mini(floori(fx), width - 2)
	var iz: int = mini(floori(fz), width - 2)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var index: int = iz * width + ix
	var a: float = heights[index]
	var b: float = heights[index + 1]
	var c: float = heights[index + width]
	var d: float = heights[index + width + 1]
	# Same b-c diagonal as the actual 4m fine mesh and its local collider.
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


static func build_patch(job: Dictionary) -> Dictionary:
	var patch_origin: Vector2 = job["origin"]
	var cells: int = int(job["cells"])
	var step: float = float(job["step"])
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var row_width: int = cells + 1
	vertices.resize(row_width * row_width)
	normals.resize(vertices.size())
	for row: int in row_width:
		for column: int in row_width:
			var point: Vector2 = patch_origin + Vector2(column, row) * step
			var index: int = row * row_width + column
			vertices[index] = Vector3(point.x, _render_height(job, point), point.y)
			normals[index] = _source_normal(job, point)
	for row: int in cells:
		for column: int in cells:
			var a: int = row * row_width + column
			var b: int = a + 1
			var c: int = a + row_width
			var d: int = c + 1
			if int(job.get("lod", 250)) == 4 or (row > 0 and column > 0 and row < cells - 1 and column < cells - 1):
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
				continue
			var corners: PackedInt32Array = PackedInt32Array([a, b, d, c])
			var polygon: PackedInt32Array = PackedInt32Array()
			var divided: bool = false
			for edge: int in 4:
				var first: int = corners[edge]
				var last: int = corners[(edge + 1) % 4]
				polygon.append(first)
				var start: Vector2 = Vector2(vertices[first].x, vertices[first].z)
				var end: Vector2 = Vector2(vertices[last].x, vertices[last].z)
				var edge_step: float = _edge_step(job, start, end)
				if edge_step <= 0.0:
					continue
				var extra: PackedVector2Array = _edge_points(start, end, edge_step)
				for point: Vector2 in extra:
					polygon.append(vertices.size())
					vertices.append(Vector3(point.x, _render_height(job, point), point.y))
					normals.append(_source_normal(job, point))
					divided = true
			if not divided:
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
				continue
			# Only a COARSE boundary cell changes topology. Its centre remains on
			# the old b-c diagonal; the ordered polygon follows the finer contour.
			var center: int = vertices.size()
			vertices.append((vertices[b] + vertices[c]) * 0.5)
			normals.append((normals[b] + normals[c]).normalized())
			for edge: int in polygon.size():
				indices.append_array(PackedInt32Array([center, polygon[edge], polygon[(edge + 1) % polygon.size()]]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return {
		"ok": true, "kind": str(job["kind"]), "key": job["key"],
		"signature": str(job.get("signature", "")), "lod": int(job.get("lod", 250)),
		"arrays": arrays,
	}


static func build_transition(jobs: Array[Dictionary], fine: Dictionary) -> Dictionary:
	var patches: Array[Dictionary] = []
	for job: Dictionary in jobs:
		patches.append(build_patch(job))
	return {"ok": true, "kind": "transition", "patches": patches, "fine": fine}


static func build_collision(key: Vector2i, heights: PackedFloat32Array) -> Dictionary:
	# Original 4m vertices and b-c diagonal. No visual stitch, skirt or GPU readback.
	const CELLS: int = 25
	var origin: Vector2 = Vector2(-2500.0, -2500.0) + Vector2(key) * 100.0
	var grid: PackedVector3Array = PackedVector3Array()
	grid.resize((CELLS + 1) * (CELLS + 1))
	for row: int in CELLS + 1:
		for column: int in CELLS + 1:
			var point: Vector2 = origin + Vector2(column, row) * 4.0
			grid[row * (CELLS + 1) + column] = Vector3(point.x, _sample_grid(heights, NATIVE_WIDTH, -2500.0, 4.0, point.x, point.y), point.y)
	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(CELLS * CELLS * 6)
	var cursor: int = 0
	for row: int in CELLS:
		for column: int in CELLS:
			var a: int = row * (CELLS + 1) + column
			var b: int = a + 1
			var c: int = a + CELLS + 1
			var d: int = c + 1
			for index: int in PackedInt32Array([a, b, c, b, d, c]):
				faces[cursor] = grid[index]
				cursor += 1
	return {"ok": true, "kind": "collision", "key": key, "faces": faces}


static func _source_normal(job: Dictionary, point: Vector2) -> Vector3:
	var heights: PackedFloat32Array = job["heights"]
	var width: int = int(job["width"])
	var origin: float = float(job["source_origin"])
	var step: float = float(job["source_step"])
	var left: float = _sample_grid(heights, width, origin, step, point.x - step, point.y)
	var right: float = _sample_grid(heights, width, origin, step, point.x + step, point.y)
	var back: float = _sample_grid(heights, width, origin, step, point.x, point.y - step)
	var front: float = _sample_grid(heights, width, origin, step, point.x, point.y + step)
	return Vector3(left - right, step * 2.0, back - front).normalized()


static func _on_native_border(point: Vector2) -> bool:
	return (is_equal_approx(absf(point.x), 2500.0) and absf(point.y) <= 2500.0) or (is_equal_approx(absf(point.y), 2500.0) and absf(point.x) <= 2500.0)


static func _native_key(point: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((point.x + 2500.0) / 500.0), 0, 9), clampi(floori((point.y + 2500.0) / 500.0), 0, 9))


static func _native_boundary_height(heights: PackedFloat32Array, point: Vector2, lod: float) -> float:
	# Native boundary is an axis-aligned polyline. Interpolate that actual LOD
	# contour, including region's 250m corners which need not coincide with 20m.
	var along_z: bool = is_equal_approx(absf(point.x), 2500.0)
	var value: float = point.y if along_z else point.x
	var first: float = -2500.0 + floorf((value + 2500.0) / lod) * lod
	first = minf(first, 2500.0 - lod)
	var a: Vector2 = Vector2(point.x, first) if along_z else Vector2(first, point.y)
	var b: Vector2 = Vector2(point.x, first + lod) if along_z else Vector2(first + lod, point.y)
	var height_a: float = _sample_grid(heights, NATIVE_WIDTH, -2500.0, 4.0, a.x, a.y)
	var height_b: float = _sample_grid(heights, NATIVE_WIDTH, -2500.0, 4.0, b.x, b.y)
	return lerpf(height_a, height_b, (value - first) / lod)


static func _render_height(job: Dictionary, point: Vector2) -> float:
	var heights: PackedFloat32Array = job["heights"]
	if str(job["kind"]) == "region" and _on_native_border(point):
		var native: PackedFloat32Array = job.get("native", PackedFloat32Array())
		if not native.is_empty():
			var fine: Dictionary = job.get("fine", {})
			var lod: float = 4.0 if fine.has(_native_key(point)) else 20.0
			return _native_boundary_height(native, point, lod)
	return _sample_grid(heights, int(job["width"]), float(job["source_origin"]), float(job["source_step"]), point.x, point.y)


static func _edge_step(job: Dictionary, start: Vector2, end: Vector2) -> float:
	var middle: Vector2 = (start + end) * 0.5
	var fine: Dictionary = job.get("fine", {})
	if str(job["kind"]) == "region":
		var native: PackedFloat32Array = job.get("native", PackedFloat32Array())
		if not native.is_empty() and _on_native_border(middle):
			return 4.0 if fine.has(_native_key(middle)) else 20.0
		return 0.0
	if int(job["lod"]) != 20:
		return 0.0
	var origin: Vector2 = job["origin"]
	var key: Vector2i = job["key"]
	var neighbor: Vector2i = Vector2i(-99, -99)
	if is_equal_approx(start.x, end.x):
		if is_equal_approx(start.x, origin.x):
			neighbor = key + Vector2i.LEFT
		elif is_equal_approx(start.x, origin.x + 500.0):
			neighbor = key + Vector2i.RIGHT
	else:
		if is_equal_approx(start.y, origin.y):
			neighbor = key + Vector2i.UP
		elif is_equal_approx(start.y, origin.y + 500.0):
			neighbor = key + Vector2i.DOWN
	return 4.0 if fine.has(neighbor) else 0.0


static func _edge_points(start: Vector2, end: Vector2, step: float) -> PackedVector2Array:
	var along_z: bool = is_equal_approx(start.x, end.x)
	var first: float = start.y if along_z else start.x
	var last: float = end.y if along_z else end.x
	var low: float = minf(first, last)
	var high: float = maxf(first, last)
	var value: float = -2500.0 + (floorf((low + 2500.0) / step) + 1.0) * step
	var points: PackedVector2Array = PackedVector2Array()
	while value < high - 0.00001:
		points.append(Vector2(start.x, value) if along_z else Vector2(value, start.y))
		value += step
	if first > last:
		points.reverse()
	return points
