class_name LocalSpatialLod
extends RefCounted
## Finite load-time caches derived from admitted facts, never new source facts.
const TOLERANCE_M: Dictionary = {"coarse": 600.0, "medium": 120.0, "local": 0.0}
const EARTH_RADIUS_M: float = 6371008.8

static func prepare(content: LocalSpatialContent, lods: Array[String] = ["coarse", "medium", "local"], visual_frames: Dictionary = {}, current: Callable = Callable()) -> Dictionary:
	# Hold the immutable input inside the worker, rather than in Thread's bound
	# arguments. Retired source arrays are then destroyed on their reader thread.
	content.geometry_mutex.lock()
	var source := content.line_chunks
	content.geometry_mutex.unlock()
	var chunks: Array[Dictionary] = []
	for lod_name: String in lods:
		if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[]}
		var groups: Dictionary = {}
		var surface_groups: Dictionary = {}
		var counts: Dictionary = {}
		for chunk: Dictionary in source:
			if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[]}
			if chunk.has("lod") and str(chunk.lod) != lod_name:
				continue
			var kind := str(chunk.kind)
			if chunk.has("polygons"):
				var faces: Array[Dictionary] = []
				var reference_groups: Dictionary = {}
				var source_face_index := 0
				if kind in ["land_reference", "ocean_reference"]:
					# These are already constrained source triangles. Re-running the
					# polygon pipeline both wastes work and rejects subpixel slivers
					# that collapse in Godot's float32 vectors. Degenerate display
					# faces have no area; no source or territorial polygon is edited.
					for polygon: Array in chunk.polygons as Array:
						var reference := ""
						var references := chunk.get("visual_reference_features", []) as Array
						var reference_indices := chunk.get("visual_reference_indices", []) as Array
						if source_face_index < reference_indices.size(): reference = str(references[int(reference_indices[source_face_index])])
						source_face_index += 1
						if not visual_frames.has(reference): reference = ""
						if not reference_groups.has(reference): reference_groups[reference] = []
						var ring := polygon[0] as Array
						var triangle := PackedVector2Array()
						for point: Array in ring.slice(0,3): triangle.append(Vector2(float(point[0]),float(point[1])))
						if GlobeProjection.polygon_area(triangle)<=0.0: continue
						for child: PackedVector2Array in GlobeProjection.tessellate_triangle(triangle):
							var uvs := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
							if not reference.is_empty():
								var bounds := visual_frames[reference] as Rect2
								for corner: int in range(3):
									var point := child[corner]
									point.x += 360.0 * roundf((bounds.get_center().x - point.x) / 360.0)
									var uv := (point - bounds.position) / bounds.size
									uvs[corner] = Vector2(uv.x,1.0-uv.y)
							var face := {"points":GlobeProjection.to_unit_line(child),"uvs":uvs,"component_index":0}
							(reference_groups[reference] as Array).append(face)
							faces.append(face)
				for polygon: Array in chunk.polygons as Array:
					if kind in ["land_reference", "ocean_reference"]: break
					var rings: Array[PackedVector2Array] = []
					for ring: Array in polygon:
						var points := PackedVector2Array()
						for coordinate: Array in ring:
							points.append(Vector2(float(coordinate[0]), float(coordinate[1])))
						if points.size() > 3 and points[0].is_equal_approx(points[-1]): points.resize(points.size()-1)
						rings.append(points)
					if not rings.is_empty():
						var mesh := GlobeProjection.source_mesh([{ "outer": rings[0], "holes": rings.slice(1)}], str(chunk.feature_id))
						faces.append_array(mesh.triangles as Array[Dictionary])
				# Limit a single upload step; exact offline patch triangles need no
				# camera-time topology or second political geometry.
				if reference_groups.is_empty(): reference_groups[""] = faces
				for reference: String in reference_groups:
					var reference_faces := reference_groups[reference] as Array
					var water_class := HydrographyStyle.surface_class(chunk)
					var key := kind + ":" + water_class + ":" + reference
					if not surface_groups.has(key): surface_groups[key] = {"kind":kind,"water_class":water_class,"reference":reference,"faces":[],"feature_ids":[]}
					(surface_groups[key].faces as Array).append_array(reference_faces)
					(surface_groups[key].feature_ids as Array).append(chunk.feature_id)
				continue
			if not groups.has(kind):
				groups[kind] = []
				counts[kind] = 0
			for boundary: Dictionary in chunk.boundaries as Array:
				var points := boundary.points as PackedVector3Array
				var parts: Array[PackedVector3Array] = [points]
				if kind=="coast" and str(boundary.feature_id).begins_with("coast:physical_") and str(boundary.feature_id).get_slice("_",2)=="0":
					parts = _without_polar_closure(points)
				for line_points: PackedVector3Array in parts:
					if lod_name != "local" and not chunk.has("lod"):
						line_points = simplify(line_points, float(TOLERANCE_M[lod_name]))
					if line_points.size() < 2:
						continue
					(groups[kind] as Array).append({"kind":kind, "points":line_points, "feature_id":boundary.feature_id, "source_fact_id":boundary.get("source_fact_id", "local_spatial:" + str(boundary.feature_id))})
					counts[kind] += line_points.size() - 1
					# Keep per-source line slices bounded, but coalesce their static
					# coastal draws to reduce the number of canvas submissions.
					var batch_limit: int = 1024 if chunk.has("lod") else 256
					if int(counts[kind]) >= batch_limit:
						chunks.append({"kind":kind, "boundaries":groups[kind], "lod":lod_name})
						groups[kind] = []
						counts[kind] = 0
		for key: String in surface_groups:
			var group := surface_groups[key] as Dictionary
			var faces := group.faces as Array
			for first: int in range(0,faces.size(),2048):
				chunks.append({"kind":group.kind,"lod":lod_name,"faces":faces.slice(first,first+2048),"feature_id":group.feature_ids[0],"source_feature_ids":group.feature_ids,"water_class":group.water_class,"visual_reference_feature":group.reference})
		for kind: String in groups:
			if not (groups[kind] as Array).is_empty():
				chunks.append({"kind":kind, "boundaries":groups[kind], "lod":lod_name})
	for chunk: Dictionary in chunks:
		if content.cancelled or (current.is_valid() and not current.call()): return {"chunks":[],"lods":[]}
		var bounds := AABB()
		var initialized := false
		var arrays: Array[PackedVector3Array] = []
		if chunk.has("faces"):
			for face: Dictionary in chunk.faces: arrays.append(face.points as PackedVector3Array)
		else:
			for boundary: Dictionary in chunk.boundaries: arrays.append(boundary.points as PackedVector3Array)
		for points: PackedVector3Array in arrays:
			for point: Vector3 in points:
				if not initialized:
					bounds = AABB(point,Vector3.ZERO)
					initialized = true
				else: bounds = bounds.expand(point)
		var center := bounds.get_center()
		var lower_dot := center.length() - bounds.size.length()*0.5
		chunk["cull_axis"] = center.normalized()
		chunk["cull_angle"] = acos(clampf(lower_dot,-1.0,1.0)) + deg_to_rad(GlobeProjection.SURFACE_EDGE_DEGREES)
		if chunk.has("faces"):
			chunk["face_count"] = (chunk.faces as Array).size()
			# Keep bounded visible land faces for geographic feedback, not sovereignty.
			chunk["payload"] = GlobeSurfaceBatch.encode(chunk.faces as Array,str(chunk.kind)=="land_reference",true,str(chunk.kind) in ["land_reference","lake"])
			chunk.erase("faces")
		else:
			var boundaries: Array[Dictionary] = []
			boundaries.assign(chunk.boundaries as Array)
			chunk["payload"] = GlobeBoundaryBatch.encode(boundaries,str(chunk.kind),str(chunk.kind) in ["coast","river"])
			chunk.erase("boundaries")
	return {"chunks":chunks, "lods":lods}

static func _without_polar_closure(points: PackedVector3Array) -> Array[PackedVector3Array]:
	# NE land's Antarctic polygon closes along the date line to the pole.
	# Its planar closure belongs to fill geometry, never a physical shoreline.
	var parts: Array[PackedVector3Array] = []
	var part := PackedVector3Array()
	for index: int in range(points.size()):
		var point := points[index]
		if index > 0:
			var previous := points[index-1]
			var closure := previous.y < -0.99 and point.y < -0.99 and absf(previous.x)<0.000001 and absf(point.x)<0.000001 and previous.z<=0.000001 and point.z<=0.000001
			if closure:
				if part.size()>=2: parts.append(part)
				part = PackedVector3Array()
		part.append(point)
	if part.size()>=2: parts.append(part)
	return parts

static func simplify(points: PackedVector3Array, tolerance_m: float) -> PackedVector3Array:
	if points.size() <= 2:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size()-1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size()-1)]
	var tolerance_squared := pow(tolerance_m / EARTH_RADIUS_M, 2.0)
	while not stack.is_empty():
		var span := stack.pop_back() as Vector2i
		var a := points[span.x]
		var delta := points[span.y] - a
		var denominator := delta.length_squared()
		var farthest: int = -1
		var maximum := tolerance_squared
		for index: int in range(span.x+1, span.y):
			var ratio := clampf((points[index]-a).dot(delta)/denominator, 0.0, 1.0) if denominator > 0.0 else 0.0
			var distance := points[index].distance_squared_to(a+delta*ratio)
			if distance > maximum:
				maximum = distance
				farthest = index
		if farthest >= 0:
			keep[farthest] = 1
			stack.append(Vector2i(span.x, farthest))
			stack.append(Vector2i(farthest, span.y))
	var result := PackedVector3Array()
	for index: int in range(points.size()):
		if keep[index] == 1:
			result.append(points[index])
	# A subpixel closed island/loop may disappear in coarse view, never become
	# a zero-length stroke. Its canonical feature and evidence remain intact.
	if result.size() == 2 and result[0].is_equal_approx(result[1]):
		return PackedVector3Array()
	return result
