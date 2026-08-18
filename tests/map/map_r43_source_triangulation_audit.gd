extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const EDGE_GRID_DEGREES: float = 5.0
const TARGETS: Array[String] = [
	"dominion_of_canada",
	"russian_empire",
	"united_states_1900",
	"brazil_1900",
	"emirate_of_afghanistan",
	"ottoman_empire",
]

var _application: FormalWorldApplication


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("R4.3 source audit: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	get_root().add_child(_application)
	var startup_start_msec := Time.get_ticks_msec()
	var startup_deadline_msec := startup_start_msec + 120000
	var roster_report: Dictionary = _application.map_debug_historical_roster()
	while (
		not bool(roster_report.get("ready", false))
		and Time.get_ticks_msec() < startup_deadline_msec
	):
		await process_frame
		roster_report = _application.map_debug_historical_roster()
	if _application == null or not bool(roster_report.get("ready", false)):
		push_error("R4.3 source audit: historical roster did not initialize")
		quit(1)
		return
	_application.set("map_topology_validation_enabled", true)
	_application.set("map_screen_topology_diagnostics_enabled", true)
	var static_deadline_msec := Time.get_ticks_msec() + 180000
	while (
		not bool(_application.map_debug_static_surface_report().get("complete", false))
		and Time.get_ticks_msec() < static_deadline_msec
	):
		_application.call("_ensure_projection_cache")
		await process_frame
	if not bool(_application.map_debug_static_surface_report().get("complete", false)):
		push_error("R4.3 source audit: static surface buffers did not complete")
		_application.queue_free()
		quit(1)
		return
	_application.call("_ensure_projection_cache")
	var report: Dictionary = {
		"targets": {},
		"missing_targets": [],
		"runtime_identity_probe": {},
		"startup_wait_msec": Time.get_ticks_msec() - startup_start_msec,
	}
	for probe_id: String in ["dominion_of_canada", "russian_empire", "united_states_1900", "emirate_of_afghanistan"]:
		var probe_entity: Dictionary = _application.map_debug_country_record(probe_id)
		var probe_polygons: Array = _application.map_debug_country_source_polygons(probe_id)
		var first_point: Array = []
		if not probe_polygons.is_empty():
			var probe_source: PackedVector3Array = probe_polygons[0] as PackedVector3Array
			if not probe_source.is_empty():
				var probe_lon_lat: Vector2 = _application.call("_map_unit_to_lon_lat", probe_source[0]) as Vector2
				first_point = [probe_lon_lat.x, probe_lon_lat.y]
		(report["runtime_identity_probe"] as Dictionary)[probe_id] = {
			"entity": probe_entity.duplicate(true),
			"polygon_count": probe_polygons.size(),
			"first_source_point": first_point,
		}
	for country_id: String in TARGETS:
		var country_polygons: Array = _application.map_debug_country_source_polygons(country_id)
		if country_polygons.is_empty():
			(report["missing_targets"] as Array).append(country_id)
			continue
		var components: Array = []
		for source_index: int in range(country_polygons.size()):
			components.append(_audit_component(country_id, source_index, country_polygons[source_index] as PackedVector3Array))
		(report["targets"] as Dictionary)[country_id] = components
	var output_path := ProjectSettings.globalize_path("res://tmp/r43-source-triangulation-audit.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print("R43_SOURCE_TRIANGULATION_AUDIT=%s" % JSON.stringify(report))
	_application.queue_free()
	quit(0)


func _audit_component(country_id: String, source_index: int, source: PackedVector3Array) -> Dictionary:
	var component_id := "%s:%d" % [country_id, source_index]
	var records: Array = _application.map_debug_country_surface_records(country_id, source_index)
	var reference_longitude := _application.map_debug_country_reference_longitude(country_id)
	if is_zero_approx(reference_longitude) and not source.is_empty():
		reference_longitude = (_application.call("_map_unit_to_lon_lat", source[0]) as Vector2).x
	var outer := _application.call("_unwrapped_planar_ring", source, reference_longitude) as PackedVector2Array
	var holes := _application.call("_holes_for_surface_source", country_id, source_index) as Array
	var edge_bins := _build_ring_edge_bins(outer)
	var source_area := float(_application.call("_planar_polygon_area", outer))
	var triangle_area := 0.0
	var outside_sample_count := 0
	var boundary_crossing_count := 0
	var max_triangle_area := 0.0
	var max_triangle_area_index := -1
	var max_triangle_planar := PackedVector2Array()
	var max_edge_length := 0.0
	var max_edge_index := -1
	var max_edge_planar := PackedVector2Array()
	var suspicious: Array = []
	var triangle_values: Array[PackedVector2Array] = []
	for record_index: int in range(records.size()):
		var record := records[record_index] as Dictionary
		var triangle := record.get("planar", PackedVector2Array()) as PackedVector2Array
		if triangle.size() != 3:
			continue
		var area := float(_application.call("_planar_polygon_area", triangle))
		triangle_values.append(triangle)
		triangle_area += area
		if area > max_triangle_area:
			max_triangle_area = area
			max_triangle_area_index = record_index
			max_triangle_planar = triangle
		var edge_max := 0.0
		for edge_index: int in range(3):
			var edge_length := triangle[edge_index].distance_to(triangle[(edge_index + 1) % 3])
			edge_max = maxf(edge_max, edge_length)
		if edge_max > max_edge_length:
			max_edge_length = edge_max
			max_edge_index = record_index
			max_edge_planar = triangle
		var samples := PackedVector2Array([
			triangle[0], triangle[1], triangle[2],
			(triangle[0] + triangle[1] + triangle[2]) / 3.0,
			triangle[0] * 0.60 + triangle[1] * 0.20 + triangle[2] * 0.20,
			triangle[0] * 0.20 + triangle[1] * 0.60 + triangle[2] * 0.20,
			triangle[0] * 0.20 + triangle[1] * 0.20 + triangle[2] * 0.60,
		])
		var sample_outside := false
		for sample: Vector2 in samples:
			if not bool(_application.call("_point_in_planar_ring", sample, outer)):
				sample_outside = true
				break
		if sample_outside:
			outside_sample_count += 1
		var crossed := _triangle_crosses_ring(triangle, outer, edge_bins)
		if crossed:
			boundary_crossing_count += 1
		if crossed or sample_outside:
			if suspicious.size() < 32:
				suspicious.append({
					"source_triangle": record_index,
					"area": area,
					"edge_max": edge_max,
					"planar": _vector2_array(triangle),
					"crosses_ring": crossed,
					"sample_outside": sample_outside,
			})
	var overlap := _audit_triangle_overlaps(triangle_values)
	var uncovered := _audit_uncovered_samples(outer, holes, triangle_values)
	return {
		"component": component_id,
		"source_vertex_count": source.size(),
		"source_area": source_area,
		"triangulated_area": triangle_area,
		"area_ratio": triangle_area / source_area if source_area > 0.0 else 1.0,
		"triangle_count": records.size(),
		"outside_sample_count": outside_sample_count,
		"boundary_crossing_count": boundary_crossing_count,
		"max_triangle_area": max_triangle_area,
		"max_triangle_area_index": max_triangle_area_index,
		"max_triangle_planar": _vector2_array(max_triangle_planar),
		"max_edge_length": max_edge_length,
		"max_edge_index": max_edge_index,
		"max_edge_planar": _vector2_array(max_edge_planar),
		"suspicious": suspicious,
		"hole_count": holes.size(),
		"overlap_pair_count": int(overlap.get("pair_count", 0)),
		"overlap_area": float(overlap.get("area", 0.0)),
		"overlap_ratio": float(overlap.get("area", 0.0)) / source_area if source_area > 0.0 else 0.0,
		"overlap_intersection_tests": int(overlap.get("intersection_tests", 0)),
		"overlap_audit_truncated": bool(overlap.get("truncated", false)),
		"uncovered_sample_count": int(uncovered.get("count", 0)),
		"uncovered_samples": uncovered.get("samples", []),
	}


func _build_ring_edge_bins(ring: PackedVector2Array) -> Dictionary:
	var bins: Dictionary = {}
	for edge_index: int in range(ring.size()):
		var a := ring[edge_index]
		var b := ring[(edge_index + 1) % ring.size()]
		var minimum := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var maximum := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		var min_cell := Vector2i(floori(minimum.x / EDGE_GRID_DEGREES), floori(minimum.y / EDGE_GRID_DEGREES))
		var max_cell := Vector2i(floori(maximum.x / EDGE_GRID_DEGREES), floori(maximum.y / EDGE_GRID_DEGREES))
		for cell_x: int in range(min_cell.x - 1, max_cell.x + 2):
			for cell_y: int in range(min_cell.y - 1, max_cell.y + 2):
				var key := "%d:%d" % [cell_x, cell_y]
				var indices: Array = bins.get(key, []) as Array
				indices.append(edge_index)
				bins[key] = indices
	return bins


func _triangle_crosses_ring(triangle: PackedVector2Array, ring: PackedVector2Array, bins: Dictionary) -> bool:
	for triangle_edge: int in range(3):
		var a := triangle[triangle_edge]
		var b := triangle[(triangle_edge + 1) % 3]
		var minimum := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var maximum := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		var min_cell := Vector2i(floori(minimum.x / EDGE_GRID_DEGREES), floori(minimum.y / EDGE_GRID_DEGREES))
		var max_cell := Vector2i(floori(maximum.x / EDGE_GRID_DEGREES), floori(maximum.y / EDGE_GRID_DEGREES))
		var candidate_edges: Array[int] = []
		var seen_edges: Dictionary = {}
		for cell_x: int in range(min_cell.x - 1, max_cell.x + 2):
			for cell_y: int in range(min_cell.y - 1, max_cell.y + 2):
				for edge_value: Variant in (bins.get("%d:%d" % [cell_x, cell_y], []) as Array):
					var ring_edge := int(edge_value)
					if not seen_edges.has(ring_edge):
						seen_edges[ring_edge] = true
						candidate_edges.append(ring_edge)
		for ring_edge: int in candidate_edges:
			var c := ring[ring_edge]
			var d := ring[(ring_edge + 1) % ring.size()]
			if _segments_cross_interior(a, b, c, d):
				return true
	return false


func _segments_cross_interior(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := (b - a).cross(c - a)
	var ab_d := (b - a).cross(d - a)
	var cd_a := (d - c).cross(a - c)
	var cd_b := (d - c).cross(b - c)
	var epsilon := 0.0000001
	return ((ab_c > epsilon and ab_d < -epsilon) or (ab_c < -epsilon and ab_d > epsilon)) and ((cd_a > epsilon and cd_b < -epsilon) or (cd_a < -epsilon and cd_b > epsilon))


func _vector2_array(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result


func _audit_triangle_overlaps(triangles: Array[PackedVector2Array]) -> Dictionary:
	const CELL_SIZE := 5.0
	const MAX_EXACT_INTERSECTION_TESTS := 64
	const MAX_CANDIDATE_PAIRS := 50000
	var bins: Dictionary = {}
	for triangle_index: int in range(triangles.size()):
		var triangle := triangles[triangle_index]
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point: Vector2 in triangle:
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
		var min_cell := Vector2i(floori(minimum.x / CELL_SIZE), floori(minimum.y / CELL_SIZE))
		var max_cell := Vector2i(floori(maximum.x / CELL_SIZE), floori(maximum.y / CELL_SIZE))
		for cell_x: int in range(min_cell.x - 1, max_cell.x + 2):
			for cell_y: int in range(min_cell.y - 1, max_cell.y + 2):
				var key := "%d:%d" % [cell_x, cell_y]
				var values: Array = bins.get(key, []) as Array
				values.append(triangle_index)
				bins[key] = values
	var checked: Dictionary = {}
	var pair_count := 0
	var overlap_area := 0.0
	var intersection_tests := 0
	var candidate_pairs := 0
	var truncated := false
	for key_value: Variant in bins.keys():
		var values: Array = bins[key_value] as Array
		for first_position: int in range(values.size()):
			var first_index := int(values[first_position])
			for second_position: int in range(first_position + 1, values.size()):
				candidate_pairs += 1
				if candidate_pairs > MAX_CANDIDATE_PAIRS:
					truncated = true
					break
				var second_index := int(values[second_position])
				if first_index == second_index:
					continue
				var low := mini(first_index, second_index)
				var high := maxi(first_index, second_index)
				var pair_key := "%d:%d" % [low, high]
				if checked.has(pair_key):
					continue
				checked[pair_key] = true
				if not _triangles_have_positive_overlap_candidate(triangles[first_index], triangles[second_index]):
					continue
				intersection_tests += 1
				# The strict edge/containment probe above is the primary invariant and
				# is deliberately cheap.  Exact polygon intersection is sampled only
				# for the first few candidates so the audit cannot itself create a
				# multi-second startup hitch on Canada/Russia's dense rings.
				pair_count += 1
				if intersection_tests <= MAX_EXACT_INTERSECTION_TESTS:
					var intersection := Geometry2D.intersect_polygons(triangles[first_index], triangles[second_index])
					var pair_area := 0.0
					for polygon_value: Variant in intersection:
						if polygon_value is PackedVector2Array:
							pair_area += _polygon_area(polygon_value as PackedVector2Array)
					overlap_area += pair_area
			if truncated:
				break
		if truncated:
			break
	return {
		"pair_count": pair_count,
		"area": overlap_area,
		"intersection_tests": intersection_tests,
		"candidate_pairs": candidate_pairs,
		"truncated": truncated,
		"exact_intersection_sample_limit": MAX_EXACT_INTERSECTION_TESTS,
	}


func _triangles_have_positive_overlap_candidate(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for first_edge: int in range(3):
		var first_start := first[first_edge]
		var first_end := first[(first_edge + 1) % 3]
		for second_edge: int in range(3):
			var second_start := second[second_edge]
			var second_end := second[(second_edge + 1) % 3]
			if _segments_cross_strict(first_start, first_end, second_start, second_end):
				return true
	for point: Vector2 in first:
		if _point_strictly_in_triangle(point, second):
			return true
	for point: Vector2 in second:
		if _point_strictly_in_triangle(point, first):
			return true
	return false


func _segments_cross_strict(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := (b - a).cross(c - a)
	var ab_d := (b - a).cross(d - a)
	var cd_a := (d - c).cross(a - c)
	var cd_b := (d - c).cross(b - c)
	const EPSILON := 0.0000001
	return (
		((ab_c > EPSILON and ab_d < -EPSILON) or (ab_c < -EPSILON and ab_d > EPSILON))
		and ((cd_a > EPSILON and cd_b < -EPSILON) or (cd_a < -EPSILON and cd_b > EPSILON))
	)


func _point_strictly_in_triangle(point: Vector2, triangle: PackedVector2Array) -> bool:
	if triangle.size() != 3:
		return false
	var first := (triangle[1] - triangle[0]).cross(point - triangle[0])
	var second := (triangle[2] - triangle[1]).cross(point - triangle[1])
	var third := (triangle[0] - triangle[2]).cross(point - triangle[2])
	return (
		(first > 0.000001 and second > 0.000001 and third > 0.000001)
		or (first < -0.000001 and second < -0.000001 and third < -0.000001)
	)


func _audit_uncovered_samples(
	outer: PackedVector2Array,
	holes: Array,
	triangles: Array[PackedVector2Array]
) -> Dictionary:
	if outer.size() < 3 or triangles.is_empty():
		return {"count": 0, "samples": []}
	const SAMPLE_STEP := 6.0
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector2 in outer:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	var count := 0
	var samples: Array = []
	var triangle_bins: Dictionary = {}
	for triangle_index: int in range(triangles.size()):
		var triangle := triangles[triangle_index]
		var triangle_minimum := Vector2(INF, INF)
		var triangle_maximum := Vector2(-INF, -INF)
		for point: Vector2 in triangle:
			triangle_minimum.x = minf(triangle_minimum.x, point.x)
			triangle_minimum.y = minf(triangle_minimum.y, point.y)
			triangle_maximum.x = maxf(triangle_maximum.x, point.x)
			triangle_maximum.y = maxf(triangle_maximum.y, point.y)
		var min_cell := Vector2i(floori(triangle_minimum.x / SAMPLE_STEP), floori(triangle_minimum.y / SAMPLE_STEP))
		var max_cell := Vector2i(floori(triangle_maximum.x / SAMPLE_STEP), floori(triangle_maximum.y / SAMPLE_STEP))
		for cell_x: int in range(min_cell.x - 1, max_cell.x + 2):
			for cell_y: int in range(min_cell.y - 1, max_cell.y + 2):
				var key := "%d:%d" % [cell_x, cell_y]
				var values: Array = triangle_bins.get(key, []) as Array
				values.append(triangle_index)
				triangle_bins[key] = values
	var x := floorf(minimum.x / SAMPLE_STEP) * SAMPLE_STEP
	while x <= maximum.x:
		var y := floorf(minimum.y / SAMPLE_STEP) * SAMPLE_STEP
		while y <= maximum.y:
			var point := Vector2(x, y)
			if _point_in_ring(point, outer) and not _point_in_any_hole(point, holes):
				var covered := false
				var cell := Vector2i(floori(point.x / SAMPLE_STEP), floori(point.y / SAMPLE_STEP))
				var candidate_indices: Array = triangle_bins.get("%d:%d" % [cell.x, cell.y], []) as Array
				for triangle_index_value: Variant in candidate_indices:
					var triangle_index := int(triangle_index_value)
					if triangle_index >= 0 and triangle_index < triangles.size() and _point_in_triangle(point, triangles[triangle_index]):
						covered = true
						break
				if not covered:
					count += 1
					if samples.size() < 32:
						samples.append([point.x, point.y])
			y += SAMPLE_STEP
		x += SAMPLE_STEP
	return {"count": count, "samples": samples}


func _point_in_any_hole(point: Vector2, holes: Array) -> bool:
	for hole_value: Variant in holes:
		if hole_value is PackedVector3Array:
			var hole_planar := _application.call("_unwrapped_planar_ring", hole_value as PackedVector3Array, 0.0) as PackedVector2Array
			if _point_in_ring(point, hole_planar):
				return true
		elif hole_value is PackedVector2Array and _point_in_ring(point, hole_value as PackedVector2Array):
			return true
	return false


func _point_in_ring(point: Vector2, ring: PackedVector2Array) -> bool:
	return bool(_application.call("_point_in_planar_ring", point, ring))


func _point_in_triangle(point: Vector2, triangle: PackedVector2Array) -> bool:
	if triangle.size() != 3:
		return false
	var first := (triangle[1] - triangle[0]).cross(point - triangle[0])
	var second := (triangle[2] - triangle[1]).cross(point - triangle[1])
	var third := (triangle[0] - triangle[2]).cross(point - triangle[2])
	var has_negative := first < -0.000001 or second < -0.000001 or third < -0.000001
	var has_positive := first > 0.000001 or second > 0.000001 or third > 0.000001
	return not (has_negative and has_positive)


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(polygon.size()):
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(area) * 0.5
