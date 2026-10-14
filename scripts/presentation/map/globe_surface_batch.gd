class_name GlobeSurfaceBatch
extends RefCounted
## Prepared display faces. Camera changes update uniforms, never source geometry.

const DATA_WIDTH: int = 256
const TEXELS_PER_FACE: int = 6
const VERTICES_PER_FACE: int = 12
const PICK_CHUNK_SIZE: int = 128
var cull_axis := Vector3.ZERO
var cull_angle: float = PI
var mesh := ArrayMesh.new()
var data: ImageTexture
var _pick_chunks: Array[Dictionary] = []
var _component_caps: Dictionary = {}
var vertex_count_per_face: int = VERTICES_PER_FACE
var index_count_per_face: int = 24

func prepare(faces: Array, retain_picking: bool = true, regional_reference: bool = false, zero_expansion: bool = false) -> void:
	upload(encode(faces, retain_picking, regional_reference, zero_expansion))

static func encode(faces: Array, retain_picking: bool = true, regional_reference: bool = false, zero_expansion: bool = false) -> Dictionary:
	# A regional viewport ends before the horizon by more than the maximum
	# source edge. Its reference faces need only the first triangle fan; the
	# WORLD and authoritative picking meshes retain both horizon fans.
	var compact := regional_reference and zero_expansion
	var vertex_count_per_face: int = 3 if compact else 6 if regional_reference else VERTICES_PER_FACE
	var index_count_per_face: int = 3 if compact else 12 if regional_reference else 24
	if faces.is_empty():
		return {}
	var height := maxi(1, ceili(float(faces.size() * TEXELS_PER_FACE) / DATA_WIDTH))
	var values := PackedFloat32Array()
	values.resize(DATA_WIDTH * height * 4)
	var vertices := PackedVector2Array()
	vertices.resize(faces.size() * vertex_count_per_face)
	var indices := PackedInt32Array()
	indices.resize(faces.size() * index_count_per_face)
	var pick_chunks: Array[Dictionary] = []
	var bounds := AABB()
	var initialized := false
	var chunk_faces: Array[Dictionary] = []
	var chunk_bounds := AABB()
	var component_bounds: Dictionary = {}
	for face_index: int in range(faces.size()):
		var face := faces[face_index] as Dictionary
		var points := face.points as PackedVector3Array
		var uvs := face.uvs as PackedVector2Array
		var component := str(face.get("pick_component_key",face.get("component_index",-1)))
		if retain_picking:
			var box := component_bounds.get(component,AABB(points[0],Vector3.ZERO)) as AABB
			for point: Vector3 in points: box = box.expand(point)
			component_bounds[component] = box
		for corner: int in range(3):
			var offset := (face_index * TEXELS_PER_FACE + corner) * 4
			if not initialized:
				bounds = AABB(points[corner], Vector3.ZERO)
				initialized = true
			else: bounds = bounds.expand(points[corner])
			values[offset] = points[corner].x
			values[offset + 1] = points[corner].y
			values[offset + 2] = points[corner].z
			offset += 12
			values[offset] = uvs[corner].x
			values[offset + 1] = uvs[corner].y
			if retain_picking and chunk_faces.is_empty() and corner == 0:
				chunk_bounds = AABB(points[0], Vector3.ZERO)
			if retain_picking: chunk_bounds = chunk_bounds.expand(points[corner])
		if retain_picking: chunk_faces.append({"face": face, "bounds": AABB(points[0], Vector3.ZERO).expand(points[1]).expand(points[2]).grow(GlobeProjection.SOURCE_EPSILON)})
		if retain_picking and (chunk_faces.size() == PICK_CHUNK_SIZE or face_index == faces.size() - 1):
			pick_chunks.append({"bounds": chunk_bounds, "faces": chunk_faces})
			chunk_faces = []
		for slot: int in range(vertex_count_per_face):
			# At zero expansion, paired corners coincide and three of the four
			# fan triangles have zero area. Keep the original surviving slots.
			var shader_slot: int = [0,3,4][slot] if compact else slot
			vertices[face_index * vertex_count_per_face + slot] = Vector2(float(face_index), float(shader_slot))
		if compact:
			for corner: int in range(3): indices[face_index*3+corner] = face_index*3+corner
			continue
		for fan: int in range(vertex_count_per_face / 6):
			var base := face_index * vertex_count_per_face + fan * 6
			for triangle: int in range(4):
				var offset := face_index * index_count_per_face + fan * 12 + triangle * 3
				indices[offset] = base
				indices[offset + 1] = base + triangle + 1
				indices[offset + 2] = base + triangle + 2
	var center := bounds.get_center()
	var caps: Dictionary = {}
	for component: String in component_bounds:
		caps[component] = (component_bounds[component] as AABB).size.length()*0.5
	return {"height":height,"values":values.to_byte_array(),"vertices":vertices,"indices":indices,"pick_chunks":pick_chunks,"component_caps":caps,"vertex_count_per_face":vertex_count_per_face,"index_count_per_face":index_count_per_face,"cull_axis":center.normalized(),"cull_angle":acos(clampf(center.length()-bounds.size.length()*0.5,-1.0,1.0))+deg_to_rad(GlobeProjection.SURFACE_EDGE_DEGREES)}

func upload(payload: Dictionary) -> void:
	_pick_chunks.clear()
	_component_caps = payload.get("component_caps",{}) as Dictionary
	mesh.clear_surfaces()
	data = null
	if payload.is_empty(): return
	vertex_count_per_face = int(payload.vertex_count_per_face)
	index_count_per_face = int(payload.index_count_per_face)
	_pick_chunks.assign(payload.pick_chunks as Array)
	cull_axis = payload.cull_axis as Vector3
	cull_angle = float(payload.cull_angle)
	data = ImageTexture.create_from_image(Image.create_from_data(DATA_WIDTH, int(payload.height), false, Image.FORMAT_RGBAF, payload.values as PackedByteArray))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = payload.vertices
	arrays[Mesh.ARRAY_INDEX] = payload.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func distance_screen_point(origin: Vector3, direction: Vector3, basis: Basis, point: Vector2, center: Vector2, radius: float, tolerance: float = 4.0) -> float:
	var best := INF
	var end := origin + direction * 2.4
	var margin := maxf(GlobeProjection.SOURCE_EPSILON,tolerance/maxf(radius,1.0))
	for chunk: Dictionary in _pick_chunks:
		if (chunk.bounds as AABB).grow(margin).intersects_segment(origin,end)==null: continue
		for entry: Dictionary in chunk.faces:
			if (entry.bounds as AABB).grow(margin).intersects_segment(origin,end)==null: continue
			var polygon := GlobeProjection.project_surface(entry.face as Dictionary,basis,center,radius).points as PackedVector2Array
			var distance := _display_face_distance(point,polygon)
			var diameter := 2.0*radius*float(_component_caps.get(str(entry.face.get("pick_component_key",entry.face.get("component_index",-1))),1.0))
			if distance<=tolerance and (distance<=0.75 or diameter<=18.0): best = minf(best,distance)
			if best==0.0: return best
	return best if best<=tolerance else INF

func distance_region_point(unit: Vector3, pixel: Vector2, camera: RegionCamera, tolerance: float = 4.0) -> float:
	var best := INF
	var origin := unit*1.2
	var end := unit*0.7
	# Include the pixel allowance in the conservative geographic prefilter.
	var margin := maxf(0.002,tolerance*camera.km_per_pixel/RegionProjection.EARTH_RADIUS_KM)
	for chunk: Dictionary in _pick_chunks:
		if (chunk.bounds as AABB).grow(margin).intersects_segment(origin,end)==null: continue
		for entry: Dictionary in chunk.faces:
			if (entry.bounds as AABB).grow(margin).intersects_segment(origin,end)==null: continue
			var polygon := _region_face(entry.face as Dictionary,camera)
			var distance := _display_face_distance(pixel,polygon)
			var diameter := 2.0*RegionProjection.EARTH_RADIUS_KM*float(_component_caps.get(str(entry.face.get("pick_component_key",entry.face.get("component_index",-1))),1.0))/camera.km_per_pixel
			if distance<=tolerance and (distance<=0.75 or diameter<=18.0): best = minf(best,distance)
			if best==0.0: return best
	return best if best<=tolerance else INF

static func _region_face(face: Dictionary, camera: RegionCamera) -> PackedVector2Array:
	var points := face.points as PackedVector3Array
	var polygon := PackedVector2Array()
	var previous := points[-1]
	var previous_z := previous.dot(camera.tangent_frame.z)
	for point: Vector3 in points:
		var z := point.dot(camera.tangent_frame.z)
		if (z>=0.0)!=(previous_z>=0.0):
			polygon.append(camera.project(previous.lerp(point,previous_z/(previous_z-z)).normalized()))
		if z>=0.0: polygon.append(camera.project(point))
		previous = point
		previous_z = z
	return polygon

static func _display_face_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	# Degenerate faces are not drawn by political_surface.gdshader either.
	if polygon.size()<3 or GlobeProjection.polygon_area(polygon)<=0.0000005: return INF
	if Geometry2D.is_point_in_polygon(point,polygon): return 0.0
	var squared := INF
	for index: int in range(polygon.size()):
		squared = minf(squared,Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()]).distance_squared_to(point))
	return sqrt(squared)
