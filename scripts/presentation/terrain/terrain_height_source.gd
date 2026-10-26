extends RefCounted
## Pure data work for LayeredTerrain. Worker jobs never access the scene tree.
## Source coordinates are metres in an explicitly fictional training region.

const REGION_WIDTH: int = 1001
const REGION_STEP: float = 50.0
const REGION_ORIGIN: float = -22500.0
const NATIVE_WIDTH: int = 1251
const NATIVE_STEP: float = 4.0
const NATIVE_ORIGIN: float = -2500.0


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
	var heights: PackedFloat32Array = job["heights"]
	var width: int = int(job["width"])
	var source_origin: float = float(job["source_origin"])
	var source_step: float = float(job["source_step"])
	var patch_origin: Vector2 = job["origin"]
	var cells: int = int(job["cells"])
	var step: float = float(job["step"])
	var skirt: float = float(job.get("skirt", 0.0))
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var row_width: int = cells + 1
	vertices.resize(row_width * row_width)
	normals.resize(vertices.size())
	indices.resize(cells * cells * 6)
	for row: int in row_width:
		for column: int in row_width:
			var x: float = patch_origin.x + float(column) * step
			var z: float = patch_origin.y + float(row) * step
			var index: int = row * row_width + column
			var height: float = _sample_grid(heights, width, source_origin, source_step, x, z)
			var left: float = _sample_grid(heights, width, source_origin, source_step, x - source_step, z)
			var right: float = _sample_grid(heights, width, source_origin, source_step, x + source_step, z)
			var back: float = _sample_grid(heights, width, source_origin, source_step, x, z - source_step)
			var front: float = _sample_grid(heights, width, source_origin, source_step, x, z + source_step)
			vertices[index] = Vector3(x, height, z)
			normals[index] = Vector3(left - right, source_step * 2.0, back - front).normalized()
	var cursor: int = 0
	for row: int in cells:
		for column: int in cells:
			var a: int = row * row_width + column
			var b: int = a + 1
			var c: int = a + row_width
			var d: int = c + 1
			indices[cursor] = a
			indices[cursor + 1] = b
			indices[cursor + 2] = c
			indices[cursor + 3] = b
			indices[cursor + 4] = d
			indices[cursor + 5] = c
			cursor += 6
	if skirt > 0.0:
		var perimeter: PackedInt32Array = PackedInt32Array()
		for column: int in cells:
			perimeter.append(column)
		for row: int in cells:
			perimeter.append(row * row_width + cells)
		for column: int in range(cells, 0, -1):
			perimeter.append(cells * row_width + column)
		for row: int in range(cells, 0, -1):
			perimeter.append(row * row_width)
		var lower_start: int = vertices.size()
		for original: int in perimeter:
			vertices.append(vertices[original] - Vector3(0.0, skirt, 0.0))
			normals.append(normals[original])
		for index: int in perimeter.size():
			var next: int = (index + 1) % perimeter.size()
			indices.append_array(PackedInt32Array([
				perimeter[index], lower_start + index, perimeter[next],
				perimeter[next], lower_start + index, lower_start + next,
			]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"ok": true, "kind": str(job["kind"]), "key": job["key"], "arrays": arrays}
