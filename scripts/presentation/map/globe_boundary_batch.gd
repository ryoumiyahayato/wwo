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
	upload(encode(boundaries, kind, compact_internal_caps))

static func encode(boundaries: Array[Dictionary], kind: String, compact_internal_caps: bool = false) -> Dictionary:
	var segment_count: int = 0
	var caps: int = 0
	for boundary: Dictionary in boundaries:
		if str(boundary.kind) != kind: continue
		var points := boundary.points as PackedVector3Array
		segment_count += maxi(0, points.size()-1)
		if points.size() >= 2 and not points[0].is_equal_approx(points[-1]):
			if not boundary.has("before"): caps += 1
			if not boundary.has("after"): caps += 1
	if segment_count == 0: return {}
	var height := ceili(float(segment_count * 4) / DATA_WIDTH)
	var values := PackedFloat32Array()
	values.resize(DATA_WIDTH * height * 4)
	var vertices := PackedVector2Array()
	vertices.resize(segment_count * (8 if compact_internal_caps else 16) + (caps * 4 if compact_internal_caps else 0))
	var indices := PackedInt32Array()
	indices.resize(segment_count * (18 if compact_internal_caps else 54) + (caps * 18 if compact_internal_caps else 0))
	var segment: int = 0
	var vertex: int = 0
	var element: int = 0
	for boundary: Dictionary in boundaries:
		if str(boundary.kind) != kind: continue
		var points := boundary.points as PackedVector3Array
		if points.size() < 2: continue
		var loop := points[0].is_equal_approx(points[-1])
		for index: int in range(points.size()-1):
			var begin_cap := index == 0 and not loop and not boundary.has("before")
			var end_cap := index == points.size()-2 and not loop and not boundary.has("after")
			var neighbors := PackedVector3Array([points[index],points[index+1],points[index-1 if index>0 else points.size()-2 if loop else 0],points[index+2 if index+2<points.size() else 1 if loop else points.size()-1]])
			if index==0 and boundary.has("before"): neighbors[2] = boundary.before
			if index==points.size()-2 and boundary.has("after"): neighbors[3] = boundary.after
			for neighbor: int in range(4):
				var offset := segment * 16 + neighbor * 4
				values[offset] = neighbors[neighbor].x
				values[offset+1] = neighbors[neighbor].y
				values[offset+2] = neighbors[neighbor].z
			values[segment*16+3] = 1.0 if begin_cap else 0.0
			values[segment*16+7] = 1.0 if end_cap else 0.0
			var core := vertex
			for slot: int in range(8):
				vertices[vertex] = Vector2(float(segment),float(slot))
				vertex += 1
			var start_cap := -1
			var finish_cap := -1
			if not compact_internal_caps or begin_cap:
				start_cap = vertex
				for slot: int in range(8,12):
					vertices[vertex] = Vector2(float(segment),float(slot))
					vertex += 1
			if not compact_internal_caps or end_cap:
				finish_cap = vertex
				for slot: int in range(12,16):
					vertices[vertex] = Vector2(float(segment),float(slot))
					vertex += 1
			for strip: int in range(3):
				if strip == 1 and start_cap < 0 or strip == 2 and finish_cap < 0: continue
				var first := core if strip == 0 else start_cap if strip == 1 else core+4
				var second := core+4 if strip == 0 else core if strip == 1 else finish_cap
				for band: int in range(3):
					indices[element] = first+band
					indices[element+1] = first+band+1
					indices[element+2] = second+band
					indices[element+3] = second+band
					indices[element+4] = first+band+1
					indices[element+5] = second+band+1
					element += 6
			segment += 1
	return {"height":height,"values":values.to_byte_array(),"vertices":vertices,"indices":indices,"segments":segment_count}

func upload(payload: Dictionary) -> void:
	mesh.clear_surfaces()
	data = null
	vertex_count = 0
	index_count = 0
	segment_count = int(payload.get("segments",0))
	if payload.is_empty(): return
	vertex_count = (payload.vertices as PackedVector2Array).size()
	index_count = (payload.indices as PackedInt32Array).size()
	data = ImageTexture.create_from_image(Image.create_from_data(DATA_WIDTH,int(payload.height),false,Image.FORMAT_RGBAF,payload.values as PackedByteArray))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = payload.vertices
	arrays[Mesh.ARRAY_INDEX] = payload.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
