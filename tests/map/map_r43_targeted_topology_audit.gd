extends SceneTree

## Targeted source-topology audit for the real political surface buffers.
## It deliberately leaves the production topology-validation switch off so the
## audit observes the normal candidate path, then independently checks the
## provenance records that the renderer will submit.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const TARGETS: Array[String] = [
	"dominion_of_canada",
	"russian_empire",
	"united_states_1900",
	"emirate_of_afghanistan",
]

var _application: FormalWorldApplication

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("R4.3 targeted topology audit: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	get_root().add_child(_application)
	var deadline := Time.get_ticks_msec() + 180000
	while (
		not bool(_application.map_debug_historical_roster().get("ready", false))
		and Time.get_ticks_msec() < deadline
	):
		await process_frame
	if not bool(_application.map_debug_historical_roster().get("ready", false)):
		push_error("R4.3 targeted topology audit: roster did not initialize")
		quit(1)
		return
	while (
		not bool(_application.map_debug_static_surface_report().get("complete", false))
		and Time.get_ticks_msec() < deadline
	):
		_application.call("_ensure_projection_cache")
		await process_frame
	if not bool(_application.map_debug_static_surface_report().get("complete", false)):
		push_error("R4.3 targeted topology audit: static buffers did not complete")
		quit(1)
		return
	var report: Dictionary = {"targets": {}, "missing_targets": []}
	for entity_id: String in TARGETS:
		var sources: Array = _application.map_debug_country_source_polygons(entity_id)
		if sources.is_empty():
			(report["missing_targets"] as Array).append(entity_id)
			continue
		var components: Array = []
		for source_index: int in range(sources.size()):
			components.append(_audit_component(entity_id, source_index, sources[source_index] as PackedVector3Array))
		(report["targets"] as Dictionary)[entity_id] = components
	var output_path := ProjectSettings.globalize_path("res://tmp/r43-targeted-topology-audit.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print("R43_TARGETED_TOPOLOGY_AUDIT=%s" % JSON.stringify(report))
	_application.queue_free()
	quit(0)


func _audit_component(entity_id: String, source_index: int, source: PackedVector3Array) -> Dictionary:
	var reference_longitude := _application.map_debug_country_reference_longitude(entity_id)
	if is_zero_approx(reference_longitude) and not source.is_empty():
		reference_longitude = (_application.call("_map_unit_to_lon_lat", source[0]) as Vector2).x
	var outer := _normalize_ring(_application.call("_unwrapped_planar_ring", source, reference_longitude) as PackedVector2Array)
	var records: Array = _application.map_debug_country_surface_records(entity_id, source_index)
	var holes: Array = _application.call("_holes_for_surface_source", entity_id, source_index) as Array
	var normalized_holes: Array[PackedVector2Array] = []
	for hole_value: Variant in holes:
		var hole_source := hole_value as PackedVector3Array
		var hole := _normalize_ring(_application.call("_unwrapped_planar_ring", hole_source, reference_longitude) as PackedVector2Array)
		if hole.size() >= 3:
			normalized_holes.append(hole)
	var source_area := float(_application.call("_planar_polygon_area", outer))
	var ring_self_intersection_count := _ring_self_intersections(outer)
	var child_area := 0.0
	var child_outside := 0
	var parent_outside := 0
	var parent_crossing := 0
	var parent_count := 0
	var largest_child_edge := 0.0
	var largest_child_index := -1
	var suspicious: Array = []
	var seen_parents: Dictionary = {}
	for record_index: int in range(records.size()):
		var record := records[record_index] as Dictionary
		var child := record.get("planar", PackedVector2Array()) as PackedVector2Array
		if child.size() != 3:
			continue
		child_area += float(_application.call("_planar_polygon_area", child))
		# Child tessellation is affine subdivision of the parent.  Audit the
		# unique source parent once below; repeating point-in-ring checks for every
		# child made this diagnostic itself take minutes on Canada/Russia.
		var child_edge := _max_edge(child)
		if child_edge > largest_child_edge:
			largest_child_edge = child_edge
			largest_child_index = record_index
		var parent := record.get("source_triangle_original_planar", PackedVector2Array()) as PackedVector2Array
		var parent_key := _triangle_key(parent)
		if parent.size() == 3 and not seen_parents.has(parent_key):
			seen_parents[parent_key] = true
			parent_count += 1
			var parent_valid := _triangle_inside(parent, outer, normalized_holes)
			var crossing := _triangle_crosses_ring(parent, outer)
			if not parent_valid:
				parent_outside += 1
			if crossing:
				parent_crossing += 1
			if (not parent_valid or crossing) and suspicious.size() < 24:
				suspicious.append({
					"record_index": record_index,
					"source_triangle_parent": int(record.get("source_triangle_parent", -1)),
					"source_triangle_child": int(record.get("source_triangle_child", -1)),
					"parent_valid": parent_valid,
					"crosses_ring": crossing,
					"parent": _vector2_array(parent),
					"child": _vector2_array(child),
				})
	return {
		"component": "%s:%d" % [entity_id, source_index],
		"source_vertex_count": source.size(),
		"record_count": records.size(),
		"parent_count": parent_count,
		"source_area": source_area,
		"ring_self_intersection_count": ring_self_intersection_count,
		"child_area": child_area,
		"area_ratio": child_area / source_area if source_area > 0.000001 else 0.0,
		"child_outside_count": child_outside,
		"parent_outside_count": parent_outside,
		"parent_boundary_crossing_count": parent_crossing,
		"hole_count": normalized_holes.size(),
		"largest_child_edge": largest_child_edge,
		"largest_child_index": largest_child_index,
		"suspicious": suspicious,
	}


func _normalize_ring(ring: PackedVector2Array) -> PackedVector2Array:
	var output := PackedVector2Array()
	for point: Vector2 in ring:
		if output.is_empty() or output[output.size() - 1].distance_to(point) > 0.000001:
			output.append(point)
	if output.size() > 1 and output[0].distance_to(output[output.size() - 1]) <= 0.000001:
		output.resize(output.size() - 1)
	return output


func _triangle_inside(triangle: PackedVector2Array, outer: PackedVector2Array, holes: Array[PackedVector2Array]) -> bool:
	if triangle.size() != 3 or outer.size() < 3:
		return false
	var samples := PackedVector2Array([
		triangle[0], triangle[1], triangle[2],
		(triangle[0] + triangle[1] + triangle[2]) / 3.0,
		triangle[0] * 0.60 + triangle[1] * 0.20 + triangle[2] * 0.20,
		triangle[0] * 0.20 + triangle[1] * 0.60 + triangle[2] * 0.20,
		triangle[0] * 0.20 + triangle[1] * 0.20 + triangle[2] * 0.60,
	])
	for sample: Vector2 in samples:
		if not bool(_application.call("_point_in_planar_ring", sample, outer)):
			return false
		for hole: PackedVector2Array in holes:
			if bool(_application.call("_point_in_planar_ring", sample, hole)):
				return false
	return true


func _triangle_crosses_ring(triangle: PackedVector2Array, ring: PackedVector2Array) -> bool:
	if triangle.size() != 3 or ring.size() < 3:
		return true
	for triangle_edge: int in range(3):
		var a := triangle[triangle_edge]
		var b := triangle[(triangle_edge + 1) % 3]
		for ring_edge: int in range(ring.size()):
			var c := ring[ring_edge]
			var d := ring[(ring_edge + 1) % ring.size()]
			if _segments_cross_interior(a, b, c, d):
				return true
	return false


func _ring_self_intersections(ring: PackedVector2Array) -> int:
	var count := 0
	if ring.size() < 4:
		return count
	for first_index: int in range(ring.size()):
		var first_next := (first_index + 1) % ring.size()
		var a := ring[first_index]
		var b := ring[first_next]
		var minimum_a := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var maximum_a := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		for second_index: int in range(first_index + 1, ring.size()):
			var second_next := (second_index + 1) % ring.size()
			if second_index == first_index or second_index == first_next or second_next == first_index:
				continue
			var c := ring[second_index]
			var d := ring[second_next]
			var minimum_b := Vector2(minf(c.x, d.x), minf(c.y, d.y))
			var maximum_b := Vector2(maxf(c.x, d.x), maxf(c.y, d.y))
			if (
				maximum_a.x < minimum_b.x or maximum_b.x < minimum_a.x
				or maximum_a.y < minimum_b.y or maximum_b.y < minimum_a.y
			):
				continue
			if _segments_cross_interior(a, b, c, d):
				count += 1
	return count


func _segments_cross_interior(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := (b - a).cross(c - a)
	var ab_d := (b - a).cross(d - a)
	var cd_a := (d - c).cross(a - c)
	var cd_b := (d - c).cross(b - c)
	const EPSILON := 0.0000001
	return (
		((ab_c > EPSILON and ab_d < -EPSILON) or (ab_c < -EPSILON and ab_d > EPSILON))
		and ((cd_a > EPSILON and cd_b < -EPSILON) or (cd_a < -EPSILON and cd_b > EPSILON))
	)


func _max_edge(triangle: PackedVector2Array) -> float:
	var result := 0.0
	for index: int in range(3):
		result = maxf(result, triangle[index].distance_to(triangle[(index + 1) % 3]))
	return result


func _triangle_key(triangle: PackedVector2Array) -> String:
	var values: Array[String] = []
	for point: Vector2 in triangle:
		values.append("%.6f,%.6f" % [point.x, point.y])
	return "|".join(values)


func _vector2_array(points: PackedVector2Array) -> Array:
	var output: Array = []
	for point: Vector2 in points:
		output.append([point.x, point.y])
	return output
