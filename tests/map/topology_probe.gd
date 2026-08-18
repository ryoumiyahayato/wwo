extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var _application: FormalWorldApplication


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("Topology probe: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	get_root().add_child(_application)
	for _frame: int in range(10):
		await process_frame
	if _application == null or _application._countries.is_empty():
		push_error("Topology probe: formal roster did not load")
		quit(1)
		return

	_application._ensure_country_surface_triangle_buffers()
	var invalid_count := 0
	var triangle_count := 0
	var component_reports: Array[Dictionary] = []
	var invalid_samples: Array[Dictionary] = []
	for key_value: Variant in _application._country_surface_triangle_records.keys():
		var cache_key := str(key_value)
		var separator := cache_key.rfind(":")
		if separator <= 0:
			continue
		var country_id := cache_key.substr(0, separator)
		var source_index := int(cache_key.substr(separator + 1))
		var source_polygons: Array = _application._country_unit_polygons.get(country_id, []) as Array
		if source_index < 0 or source_index >= source_polygons.size():
			continue
		var source: PackedVector3Array = source_polygons[source_index]
		var reference_longitude := float(
			_application._country_flag_uv_reference_longitudes.get(
				country_id,
				_application._map_unit_to_lon_lat(source[0]).x
			)
		)
		var outer := _application._unwrapped_planar_ring(source, reference_longitude)
		var holes: Array = _application._holes_for_surface_source(country_id, source_index)
		var source_area := _application._planar_polygon_area(outer)
		var entity_invalid := 0
		var triangulated_area := 0.0
		var max_triangle_ratio := 0.0
		for record_value: Variant in (_application._country_surface_triangle_records.get(cache_key, []) as Array):
			var record := record_value as Dictionary
			var triangle: PackedVector2Array = record.get("planar", PackedVector2Array()) as PackedVector2Array
			if triangle.size() != 3:
				continue
			triangle_count += 1
			var triangle_area := _application._planar_polygon_area(triangle)
			triangulated_area += triangle_area
			max_triangle_ratio = maxf(max_triangle_ratio, triangle_area / maxf(source_area, 0.000001))
			var sample_points := PackedVector2Array([
				triangle[0] * 0.60 + triangle[1] * 0.20 + triangle[2] * 0.20,
				triangle[0] * 0.20 + triangle[1] * 0.60 + triangle[2] * 0.20,
				triangle[0] * 0.20 + triangle[1] * 0.20 + triangle[2] * 0.60,
				(triangle[0] + triangle[1] + triangle[2]) / 3.0,
			])
			var invalid := false
			for sample: Vector2 in sample_points:
				if not _point_in_planar_ring(sample, outer):
					invalid = true
					break
				for hole_value: Variant in holes:
					var hole := hole_value as PackedVector3Array
					var hole_planar := _application._unwrapped_planar_ring(hole, reference_longitude)
					if _point_in_planar_ring(sample, hole_planar):
						invalid = true
						break
				if invalid:
					break
			if invalid:
				invalid_count += 1
				entity_invalid += 1
				if invalid_samples.size() < 20:
					invalid_samples.append({
						"component": cache_key,
						"triangle": triangle,
						"outer_first": outer[0] if not outer.is_empty() else Vector2.ZERO,
						"outer_size": outer.size(),
						"triangle_area": triangle_area,
						"source_area": source_area,
					})
		if entity_invalid > 0:
			var direct_indices := Geometry2D.triangulate_polygon(outer)
			var reversed_outer := PackedVector2Array()
			for reverse_index: int in range(outer.size() - 1, -1, -1):
				reversed_outer.append(outer[reverse_index])
			var reversed_indices := Geometry2D.triangulate_polygon(reversed_outer)
			var remapped_reversed := PackedInt32Array()
			for reverse_value: int in reversed_indices:
				remapped_reversed.append(outer.size() - 1 - reverse_value)
			var direct_audit := _audit_triangle_indices(outer, direct_indices, holes)
			var reversed_audit := _audit_triangle_indices(outer, remapped_reversed, holes)
			component_reports.append({
				"component": cache_key,
				"source_vertices": outer.size(),
				"hole_count": holes.size(),
				"source_area": source_area,
				"cached_triangle_count": (_application._country_surface_triangle_records.get(cache_key, []) as Array).size(),
				"cached_triangulated_area": triangulated_area,
				"cached_area_ratio": triangulated_area / maxf(source_area, 0.000001),
				"cached_invalid_triangles": entity_invalid,
				"cached_max_triangle_source_area_ratio": max_triangle_ratio,
				"direct_index_count": direct_indices.size(),
				"direct_audit": direct_audit,
				"reversed_index_count": reversed_indices.size(),
				"reversed_audit": reversed_audit,
			})
	var report := {
		"triangle_count": triangle_count,
		"invalid_triangle_count": invalid_count,
		"invalid_samples": invalid_samples,
		"invalid_components": component_reports,
	}
	print("TOPOLOGY_PROBE=" + JSON.stringify(report))
	quit(1 if invalid_count > 0 else 0)


func _audit_triangle_indices(
	polygon: PackedVector2Array,
	indices: PackedInt32Array,
	holes: Array
) -> Dictionary:
	var invalid := 0
	var triangle_count := 0
	var area := 0.0
	for index: int in range(0, indices.size(), 3):
		if index + 2 >= indices.size():
			break
		var first := int(indices[index])
		var second := int(indices[index + 1])
		var third := int(indices[index + 2])
		if (
			first < 0 or second < 0 or third < 0
			or first >= polygon.size() or second >= polygon.size() or third >= polygon.size()
		):
			invalid += 1
			continue
		var triangle := PackedVector2Array([polygon[first], polygon[second], polygon[third]])
		var triangle_area := _application._planar_polygon_area(triangle)
		if triangle_area <= 0.00001:
			invalid += 1
			continue
		triangle_count += 1
		area += triangle_area
		var sample := (triangle[0] + triangle[1] + triangle[2]) / 3.0
		if not _point_in_planar_ring(sample, polygon):
			invalid += 1
			continue
		for hole_value: Variant in holes:
			var hole := _application._unwrapped_planar_ring(hole_value as PackedVector3Array, 0.0)
			if _point_in_planar_ring(sample, hole):
				invalid += 1
				break
	return {
		"triangle_count": triangle_count,
		"invalid_triangles": invalid,
		"triangulated_area": area,
	}


func _point_in_planar_ring(point: Vector2, ring: PackedVector2Array) -> bool:
	if ring.size() < 3:
		return false
	var inside := false
	for index: int in range(ring.size()):
		var start := ring[index]
		var end := ring[(index + 1) % ring.size()]
		var edge := end - start
		var relative := point - start
		if absf(edge.cross(relative)) <= 0.00001 and relative.dot(point - end) <= 0.00001:
			return true
		if (start.y > point.y) == (end.y > point.y):
			continue
		var denominator := end.y - start.y
		if absf(denominator) <= 0.0000001:
			continue
		var intersection_x := start.x + (point.y - start.y) * (end.x - start.x) / denominator
		if intersection_x >= point.x:
			inside = not inside
	return inside
