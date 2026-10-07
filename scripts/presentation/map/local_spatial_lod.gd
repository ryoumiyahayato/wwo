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
		for chunk: Dictionary in source:
			var kind := str(chunk.kind)
			if not groups.has(kind):
				groups[kind] = []
				counts[kind] = 0
			for boundary: Dictionary in chunk.boundaries as Array:
				var points := boundary.points as PackedVector3Array
				if lod_name != "local":
					points = simplify(points, float(TOLERANCE_M[lod_name]))
				if points.size() < 2:
					continue
				(groups[kind] as Array).append({"kind":kind, "points":points, "feature_id":boundary.feature_id, "source_fact_id":"local_spatial:" + str(boundary.feature_id)})
				counts[kind] += points.size() - 1
				segments += points.size() - 1
				vector_bytes += points.size() * 12
				if int(counts[kind]) >= 256:
					chunks.append({"kind":kind, "boundaries":groups[kind], "lod":lod_name})
					groups[kind] = []
					counts[kind] = 0
		for kind: String in groups:
			if not (groups[kind] as Array).is_empty():
				chunks.append({"kind":kind, "boundaries":groups[kind], "lod":lod_name})
		stats[lod_name] = {"segments":segments, "packed_vector_bytes":vector_bytes, "tolerance_m":TOLERANCE_M[lod_name]}
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
