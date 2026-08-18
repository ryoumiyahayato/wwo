extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
var _application: FormalWorldApplication

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	_application = scene.instantiate() as FormalWorldApplication
	get_root().add_child(_application)
	while not bool(_application.map_debug_historical_roster().get("ready", false)):
		await process_frame
	var doc := _application.call("_read_document", "res://data/world_map/world_coastlines.json") as Dictionary
	var targets := ["Canada", "United States of America", "Russia", "Western Sahara", "Antarctica", "People's Republic of China"]
	var output: Array = []
	for feature_value: Variant in (doc.get("features", []) as Array):
		var feature := feature_value as Dictionary
		if not targets.has(str(feature.get("name", ""))):
			continue
		var feature_report := {"name": feature.get("name", ""), "iso": feature.get("iso_a3", ""), "polygons": []}
		for polygon_value: Variant in (feature.get("polygons", []) as Array):
			var polygon := polygon_value as Dictionary
			var raw := _application.call("_points_from_raw", polygon.get("outer", [])) as PackedVector2Array
			for limit: int in [20, 120, 1000000]:
				var simplified := raw if raw.size() <= limit else _application.call("_simplify_line", raw, limit) as PackedVector2Array
				var indices: PackedInt32Array = _application.call("_triangulate_planar_polygon", simplified) as PackedInt32Array
				var valid: bool = bool(_application.call("_triangulation_is_valid_for_ring", simplified, indices))
				(feature_report["polygons"] as Array).append({
					"raw_count": raw.size(),
					"limit": limit,
					"count": simplified.size(),
					"indices": indices.size(),
					"valid": valid,
					"points": _array(simplified),
				})
		output.append(feature_report)
	var path := ProjectSettings.globalize_path("res://tmp/r43-ring-probe.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(output, "  "))
	print(JSON.stringify(output))
	_application.queue_free()
	quit(0)

func _array(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result
