class_name GlobeSurfaceBatch
extends RefCounted
## Prepared display faces. Camera changes update uniforms, never source geometry.

const DATA_WIDTH: int = 256
const TEXELS_PER_FACE: int = 6
const VERTICES_PER_FACE: int = 12
const PICK_CHUNK_SIZE: int = 128
var mesh := ArrayMesh.new()
var data: ImageTexture
var _pick_chunks: Array[Dictionary] = []

func prepare(faces: Array) -> void:
	_pick_chunks.clear()
	mesh.clear_surfaces()
	data = null
	if faces.is_empty():
		return
	var height := maxi(1, ceili(float(faces.size() * TEXELS_PER_FACE) / DATA_WIDTH))
	var values := PackedFloat32Array()
	values.resize(DATA_WIDTH * height * 4)
	var vertices := PackedVector2Array()
	vertices.resize(faces.size() * VERTICES_PER_FACE)
	var indices := PackedInt32Array()
	indices.resize(faces.size() * 24)
	var chunk_faces: Array[Dictionary] = []
	var chunk_bounds := AABB()
	for face_index: int in range(faces.size()):
		var face := faces[face_index] as Dictionary
		var points := face.points as PackedVector3Array
		var uvs := face.uvs as PackedVector2Array
		var face_bounds := AABB(points[0], Vector3.ZERO).expand(points[1]).expand(points[2]).grow(GlobeProjection.SOURCE_EPSILON)
		for corner: int in range(3):
			var offset := (face_index * TEXELS_PER_FACE + corner) * 4
			values[offset] = points[corner].x
			values[offset + 1] = points[corner].y
			values[offset + 2] = points[corner].z
			offset += 12
			values[offset] = uvs[corner].x
			values[offset + 1] = uvs[corner].y
			if chunk_faces.is_empty() and corner == 0:
				chunk_bounds = AABB(points[0], Vector3.ZERO)
			chunk_bounds = chunk_bounds.expand(points[corner])
		chunk_faces.append({"face": face, "bounds": face_bounds})
		if chunk_faces.size() == PICK_CHUNK_SIZE or face_index == faces.size() - 1:
			_pick_chunks.append({"bounds": chunk_bounds, "faces": chunk_faces})
			chunk_faces = []
		for slot: int in range(VERTICES_PER_FACE):
			vertices[face_index * VERTICES_PER_FACE + slot] = Vector2(float(face_index), float(slot))
		for fan: int in range(2):
			var base := face_index * VERTICES_PER_FACE + fan * 6
			for triangle: int in range(4):
				var offset := face_index * 24 + fan * 12 + triangle * 3
				indices[offset] = base
				indices[offset + 1] = base + triangle + 1
				indices[offset + 2] = base + triangle + 2
	data = ImageTexture.create_from_image(Image.create_from_data(DATA_WIDTH, height, false, Image.FORMAT_RGBAF, values.to_byte_array()))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func contains_screen_point(origin: Vector3, direction: Vector3, basis: Basis, point: Vector2, center: Vector2, radius: float) -> bool:
	var end := origin + direction * 2.4
	for chunk: Dictionary in _pick_chunks:
		if (chunk.bounds as AABB).grow(GlobeProjection.SOURCE_EPSILON).intersects_segment(origin, end) == null:
			continue
		for entry: Dictionary in chunk.faces:
			if (entry.bounds as AABB).intersects_segment(origin, end) == null:
				continue
			# Use the existing exact screen predicate after conservative source bounds;
			# a 3D ray/triangle epsilon would silently miss very small islands.
			var projected := GlobeProjection.project_surface(entry.face as Dictionary, basis, center, radius)
			var polygon := projected.points as PackedVector2Array
			if polygon.size() >= 3 and GlobeProjection.polygon_area(polygon) > 0.0 and Geometry2D.is_point_in_polygon(point, polygon):
				return true
	return false

func contains_region_point(unit: Vector3, pixel: Vector2, camera: RegionCamera) -> bool:
	# Conservative ray bounds, then the exact same projected source triangles
	# as the shader. Identity never depends on a framebuffer colour.
	var origin := unit * 1.2
	var end := unit * 0.7
	for chunk: Dictionary in _pick_chunks:
		if (chunk.bounds as AABB).grow(0.002).intersects_segment(origin, end) == null:
			continue
		for entry: Dictionary in chunk.faces:
			if (entry.bounds as AABB).grow(0.002).intersects_segment(origin, end) == null:
				continue
			var points := (entry.face as Dictionary).points as PackedVector3Array
			var polygon := PackedVector2Array([camera.project(points[0]), camera.project(points[1]), camera.project(points[2])])
			if Geometry2D.is_point_in_polygon(pixel, polygon):
				return true
	return false
