class_name GlobeBoundaryBatch
extends RefCounted
## Static line neighbours for the existing screen-space polyline stroke.

const DATA_WIDTH: int = 256
const VERTICES_PER_SEGMENT: int = 16
var mesh := ArrayMesh.new()
var data: ImageTexture
var segment_count: int = 0
var vertex_count: int = 0
var index_count: int = 0

func prepare(boundaries: Array[Dictionary], kind: String, compact_internal_caps: bool = false) -> void:
	mesh.clear_surfaces()
	data = null
	vertex_count = 0
	index_count = 0
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
	var indices := PackedInt32Array()
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
		var core := vertices.size()
		for slot: int in range(8):
			vertices.append(Vector2(float(index), float(slot)))
		var start_cap := -1
		var end_cap := -1
		if not compact_internal_caps or bool(segment.begin_cap):
			start_cap = vertices.size()
			for slot: int in range(8,12): vertices.append(Vector2(float(index), float(slot)))
		if not compact_internal_caps or bool(segment.end_cap):
			end_cap = vertices.size()
			for slot: int in range(12,16): vertices.append(Vector2(float(index), float(slot)))
		# Inside the bounded REGION viewport, internal cap strips coincide and
		# have zero area. Dynamic horizon caps lie beyond its 9000 km extent.
		# WORLD retains them. Preserve every original shader slot and join.
		for strip: int in range(3):
			if strip == 1 and start_cap < 0 or strip == 2 and end_cap < 0: continue
			var first := core if strip == 0 else start_cap if strip == 1 else core+4
			var second := core+4 if strip == 0 else core if strip == 1 else end_cap
			for band: int in range(3):
				indices.append_array(PackedInt32Array([first+band, first+band+1, second+band, second+band, first+band+1, second+band+1]))
	vertex_count = vertices.size()
	index_count = indices.size()
	data = ImageTexture.create_from_image(Image.create_from_data(DATA_WIDTH, height, false, Image.FORMAT_RGBAF, values.to_byte_array()))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
