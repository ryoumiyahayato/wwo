class_name LocalSpatialLod
extends RefCounted
## Finite load-time caches derived from admitted facts, never new source facts.
const TOLERANCE_M: Dictionary = {"coarse": 600.0, "medium": 120.0, "local": 0.0}
const EARTH_RADIUS_M: float = 6371008.8

static func prepare(source: Array[Dictionary], lods: Array[String] = ["coarse", "medium", "local"]) -> Dictionary:
	var started := Time.get_ticks_usec()
	var chunks: Array[Dictionary] = []
	var stats: Dictionary = {}
	for lod_name: String in lods:
		var groups: Dictionary = {}
		var counts: Dictionary = {}
		var segments: int = 0
		var vector_bytes: int = 0
		var precomputed: bool = false
		var source_tolerances: Dictionary = {}
		for chunk: Dictionary in source:
			if chunk.has("lod") and str(chunk.lod) != lod_name:
				continue
			precomputed = precomputed or chunk.has("lod")
			var kind := str(chunk.kind)
			if chunk.has("tolerance_m"): source_tolerances[kind] = chunk.tolerance_m
			if chunk.has("polygons"):
				var faces: Array[Dictionary] = []
				if kind in ["land_reference", "ocean_reference"]:
					# These are already constrained source triangles. Re-running the
					# polygon pipeline both wastes work and rejects subpixel slivers
					# that collapse in Godot's float32 vectors. Degenerate display
					# faces have no area; no source or territorial polygon is edited.
					for polygon: Array in chunk.polygons as Array:
						var ring := polygon[0] as Array
						var triangle := PackedVector2Array()
						for point: Array in ring.slice(0,3): triangle.append(Vector2(float(point[0]),float(point[1])))
						if GlobeProjection.polygon_area(triangle)<=0.0: continue
						for child: PackedVector2Array in GlobeProjection.tessellate_triangle(triangle):
							faces.append({"points":GlobeProjection.to_unit_line(child),"uvs":PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]),"component_index":0})
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
				for first: int in range(0, faces.size(), 1024):
					chunks.append({"kind": kind, "lod": lod_name, "faces": faces.slice(first,first+1024), "feature_id": chunk.feature_id, "water_class": HydrographyStyle.surface_class(chunk)})
				vector_bytes += faces.size() * 60
				continue
			if not groups.has(kind):
				groups[kind] = []
				counts[kind] = 0
			for boundary: Dictionary in chunk.boundaries as Array:
				var points := boundary.points as PackedVector3Array
				if lod_name != "local" and not chunk.has("lod"):
					points = simplify(points, float(TOLERANCE_M[lod_name]))
				if points.size() < 2:
					continue
				(groups[kind] as Array).append({"kind":kind, "points":points, "feature_id":boundary.feature_id, "source_fact_id":boundary.get("source_fact_id", "local_spatial:" + str(boundary.feature_id))})
				counts[kind] += points.size() - 1
				segments += points.size() - 1
				vector_bytes += points.size() * 12
				# Keep per-source line slices bounded, but coalesce their static
				# coastal draws. The native FAR probe exposed driver overhead
				# from many tiny batches, rather than insufficient source detail.
				var batch_limit: int = 1024 if kind=="coast" and chunk.has("lod") else 256
				if int(counts[kind]) >= batch_limit:
					chunks.append({"kind":kind, "boundaries":groups[kind], "lod":lod_name})
					groups[kind] = []
					counts[kind] = 0
		for kind: String in groups:
			if not (groups[kind] as Array).is_empty():
				chunks.append({"kind":kind, "boundaries":groups[kind], "lod":lod_name})
		stats[lod_name] = {"segments":segments, "packed_vector_bytes":vector_bytes, "tolerance_m":(5000.0 if lod_name == "coarse" else 1500.0) if precomputed else TOLERANCE_M[lod_name], "source_tolerances_m":source_tolerances, "precomputed": precomputed}
	return {"chunks":chunks, "lod_stats":stats, "lod_prepare_usec":Time.get_ticks_usec()-started}

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
