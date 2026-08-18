extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var _application: FormalWorldApplication

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("R4.3 physical triangulation audit: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	get_root().add_child(_application)
	var deadline := Time.get_ticks_msec() + 120000
	while not bool(_application.map_debug_historical_roster().get("ready", false)) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(_application.map_debug_historical_roster().get("ready", false)):
		push_error("R4.3 physical triangulation audit: roster did not initialize")
		quit(1)
		return
	_application.call("_ensure_physical_land_triangle_cache")
	var sources: Array = _application.get("_physical_land_polygons") as Array
	var report: Dictionary = {
		"source_count": sources.size(),
		"components": [],
		"summary": {
			"engine_invalid": 0,
			"runtime_invalid": 0,
			"runtime_empty": 0,
			"engine_area_loss": 0,
			"runtime_area_loss": 0,
			"runtime_area_gain": 0,
		},
	}
	for source_index: int in range(sources.size()):
		var source := sources[source_index] as PackedVector3Array
		if source.size() < 3:
			continue
		var first_lon_lat := _application.call("_map_unit_to_lon_lat", source[0]) as Vector2
		var outer := _application.call("_unwrapped_planar_ring", source, first_lon_lat.x) as PackedVector2Array
		var engine_indices := Geometry2D.triangulate_polygon(outer)
		var runtime_indices := _application.call("_triangulate_planar_polygon", outer) as PackedInt32Array
		var engine_metrics := _metrics(outer, engine_indices)
		var runtime_metrics := _metrics(outer, runtime_indices)
		var item := {
			"source_index": source_index,
			"vertex_count": source.size(),
			"engine": engine_metrics,
			"runtime": runtime_metrics,
		}
		(report["components"] as Array).append(item)
		if not bool(engine_metrics.get("valid", false)):
			(report["summary"] as Dictionary)["engine_invalid"] = int((report["summary"] as Dictionary).get("engine_invalid", 0)) + 1
		if not bool(runtime_metrics.get("valid", false)):
			(report["summary"] as Dictionary)["runtime_invalid"] = int((report["summary"] as Dictionary).get("runtime_invalid", 0)) + 1
		if int(runtime_metrics.get("triangle_count", 0)) == 0:
			(report["summary"] as Dictionary)["runtime_empty"] = int((report["summary"] as Dictionary).get("runtime_empty", 0)) + 1
		var engine_ratio := float(engine_metrics.get("area_ratio", 1.0))
		var runtime_ratio := float(runtime_metrics.get("area_ratio", 1.0))
		if engine_ratio < 0.995:
			(report["summary"] as Dictionary)["engine_area_loss"] = int((report["summary"] as Dictionary).get("engine_area_loss", 0)) + 1
		if runtime_ratio < 0.995:
			(report["summary"] as Dictionary)["runtime_area_loss"] = int((report["summary"] as Dictionary).get("runtime_area_loss", 0)) + 1
		if runtime_ratio > 1.005:
			(report["summary"] as Dictionary)["runtime_area_gain"] = int((report["summary"] as Dictionary).get("runtime_area_gain", 0)) + 1
	var output_path := ProjectSettings.globalize_path("res://tmp/r43-physical-triangulation-audit.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print("R43_PHYSICAL_TRIANGULATION_AUDIT=%s" % JSON.stringify(report))
	_application.queue_free()
	quit(0)


func _metrics(outer: PackedVector2Array, indices: PackedInt32Array) -> Dictionary:
	var source_area := absf(_area(outer))
	var triangle_area := 0.0
	var outside_count := 0
	var crossing_count := 0
	var max_edge := 0.0
	var max_triangle: Array = []
	for index: int in range(0, indices.size(), 3):
		if index + 2 >= indices.size():
			break
		var a_index := int(indices[index])
		var b_index := int(indices[index + 1])
		var c_index := int(indices[index + 2])
		if a_index < 0 or b_index < 0 or c_index < 0 or a_index >= outer.size() or b_index >= outer.size() or c_index >= outer.size():
			outside_count += 1
			continue
		var triangle := PackedVector2Array([outer[a_index], outer[b_index], outer[c_index]])
		var area := absf(_area(triangle))
		triangle_area += area
		var edge_max := 0.0
		for edge_index: int in range(3):
			edge_max = maxf(edge_max, triangle[edge_index].distance_to(triangle[(edge_index + 1) % 3]))
		if edge_max > max_edge:
			max_edge = edge_max
			max_triangle = _array(triangle)
		var samples := PackedVector2Array([
			triangle[0], triangle[1], triangle[2],
			(triangle[0] + triangle[1] + triangle[2]) / 3.0,
		])
		for sample: Vector2 in samples:
			if not bool(_application.call("_point_in_planar_ring", sample, outer)):
				outside_count += 1
				break
	return {
		"valid": indices.size() >= 3 and indices.size() % 3 == 0 and source_area > 0.000001 and outside_count == 0,
		"triangle_count": indices.size() / 3,
		"source_area": source_area,
		"triangulated_area": triangle_area,
		"area_ratio": triangle_area / source_area if source_area > 0.000001 else 0.0,
		"outside_sample_count": outside_count,
		"boundary_crossing_count": crossing_count,
		"max_edge": max_edge,
		"max_triangle": max_triangle,
	}


func _area(points: PackedVector2Array) -> float:
	var result := 0.0
	for index: int in range(points.size()):
		result += points[index].cross(points[(index + 1) % points.size()])
	return result * 0.5


func _array(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result
