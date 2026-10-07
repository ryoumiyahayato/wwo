class_name GlobeBoundaryBatch
extends RefCounted
## Static line neighbours for the existing screen-space polyline stroke.

const DATA_WIDTH: int = 256
const VERTICES_PER_SEGMENT: int = 16
var mesh := ArrayMesh.new()
var data: ImageTexture
var segment_count: int = 0

func prepare(boundaries: Array[Dictionary], kind: String) -> void:
	mesh.clear_surfaces()
	data = null
	var segments: Array[Dictionary] = []
	for boundary: Dictionary in boundaries:
		if str(boundary.kind) != kind:
			continue
		var points := boundary.points as PackedVector3Array
		var loop := points[0].is_equal_approx(points[points.size() - 1])
		for index: int in range(points.size() - 1):
			segments.append({"a": points[index], "b": points[index + 1],
				"before": points[index - 1 if index > 0 else points.size() - 2 if loop else 0],
				"after": points[index + 2 if index + 2 < points.size() else 1 if loop else points.size() - 1],
				"begin_cap": index == 0 and not loop, "end_cap": index == points.size() - 2 and not loop})
	segment_count = segments.size()
	if segment_count == 0:
		return
	var height := ceili(float(segment_count * 4) / DATA_WIDTH)
	var values := PackedFloat32Array()
	values.resize(DATA_WIDTH * height * 4)
	var vertices := PackedVector2Array()
	vertices.resize(segment_count * VERTICES_PER_SEGMENT)
	var indices := PackedInt32Array()
	indices.resize(segment_count * 54)
	for index: int in range(segment_count):
		var segment := segments[index] as Dictionary
		var neighbors: Array[Vector3] = [segment.a, segment.b, segment.before, segment.after]
		for neighbor: int in range(4):
			var offset := index * 16 + neighbor * 4
			values[offset] = neighbors[neighbor].x
			values[offset + 1] = neighbors[neighbor].y
			values[offset + 2] = neighbors[neighbor].z
		values[index * 16 + 3] = 1.0 if bool(segment.begin_cap) else 0.0
		values[index * 16 + 7] = 1.0 if bool(segment.end_cap) else 0.0
		for slot: int in range(VERTICES_PER_SEGMENT):
			vertices[index * VERTICES_PER_SEGMENT + slot] = Vector2(float(index), float(slot))
		# Three bands (left feather / stroke / right feather), with end feathers.
		for strip: int in range(3):
			var first := 0 if strip == 0 else 8 if strip == 1 else 4
			var second := 4 if strip == 0 else 0 if strip == 1 else 12
			for band: int in range(3):
				var offset := index * 54 + strip * 18 + band * 6
				var base := index * VERTICES_PER_SEGMENT
				var quad := PackedInt32Array([base + first + band, base + first + band + 1, base + second + band,
					base + second + band, base + first + band + 1, base + second + band + 1])
				for corner: int in range(6):
					indices[offset + corner] = quad[corner]
	data = ImageTexture.create_from_image(Image.create_from_data(DATA_WIDTH, height, false, Image.FORMAT_RGBAF, values.to_byte_array()))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
