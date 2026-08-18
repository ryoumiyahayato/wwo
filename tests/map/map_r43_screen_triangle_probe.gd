extends SceneTree

## Screen-space provenance probe for the actual projection cache.  It reports
## the largest projected triangles at deterministic camera states, including
## the original geographic source triangle, so an apparent Arctic wedge can be
## classified as valid clipping or a projection/render defect.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const TARGETS: Array[String] = [
	"dominion_of_canada",
	"russian_empire",
	"united_states_1900",
	"emirate_of_afghanistan",
	"ottoman_empire",
]
const STATES: Array[Dictionary] = [
	{"id": "canada_high_north", "yaw": 220.0, "tilt": 72.0, "zoom": 1.10},
	{"id": "canada_horizon", "yaw": 250.0, "tilt": 82.0, "zoom": 1.00},
	{"id": "russia_high_north", "yaw": 94.0, "tilt": 72.0, "zoom": 1.08},
	{"id": "central_arabia", "yaw": 0.0, "tilt": 0.0, "zoom": 2.40},
]

var _application: FormalWorldApplication

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("R4.3 screen triangle probe: formal scene could not load")
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
	while (
		not bool(_application.map_debug_static_surface_report().get("complete", false))
		and Time.get_ticks_msec() < deadline
	):
		_application.call("_ensure_projection_cache")
		await process_frame
	if not bool(_application.map_debug_static_surface_report().get("complete", false)):
		push_error("R4.3 screen triangle probe: static buffers did not complete")
		quit(1)
		return
	_application.map_screen_topology_diagnostics_enabled = true
	var report: Dictionary = {"states": []}
	for state: Dictionary in STATES:
		_application.yaw = deg_to_rad(float(state.get("yaw", 0.0)))
		_application.tilt = clampf(deg_to_rad(float(state.get("tilt", 0.0))), -1.45, 1.45)
		_application.world_zoom = clampf(float(state.get("zoom", 1.0)), 0.74, 6.0)
		_application.call("_apply_world_zoom_geometry")
		_application.call("_mark_projection_dirty")
		_application.call("_ensure_projection_cache")
		var state_report: Dictionary = {"id": str(state.get("id", "state")), "targets": {}}
		for entity_id: String in TARGETS:
			(state_report["targets"] as Dictionary)[entity_id] = _audit_entity(entity_id)
		(report["states"] as Array).append(state_report)
	var output_path := ProjectSettings.globalize_path("res://tmp/r43-screen-triangle-probe.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print("R43_SCREEN_TRIANGLE_PROBE=%s" % JSON.stringify(report))
	_application.queue_free()
	quit(0)


func _audit_entity(entity_id: String) -> Dictionary:
	var records: Array = _application.map_debug_country_screen_triangle_records(entity_id)
	var largest: Array = []
	var invalid_count := 0
	var suspicious_count := 0
	for record_index: int in range(records.size()):
		var record := records[record_index] as Dictionary
		var screen := record.get("screen", PackedVector2Array()) as PackedVector2Array
		if screen.size() != 3:
			invalid_count += 1
			continue
		var edge_max := 0.0
		for edge_index: int in range(3):
			edge_max = maxf(edge_max, screen[edge_index].distance_to(screen[(edge_index + 1) % 3]))
		var area := absf(
			screen[0].x * (screen[1].y - screen[2].y)
			+ screen[1].x * (screen[2].y - screen[0].y)
			+ screen[2].x * (screen[0].y - screen[1].y)
		) * 0.5
		var topology := record.get("topology", {}) as Dictionary
		if bool(topology.get("suspicious", false)):
			suspicious_count += 1
		if edge_max < 120.0 and not bool(topology.get("suspicious", false)):
			continue
		largest.append({
			"record_index": record_index,
			"edge_max": edge_max,
			"area": area,
			"source_component": str(record.get("source_component", "")),
			"source_triangle": int(record.get("source_triangle", -1)),
			"clipped_child": int(record.get("clipped_child", -1)),
			"screen": _vector2_array(screen),
			"topology": topology,
		})
	largest.sort_custom(Callable(self, "_larger_edge_first"))
	if largest.size() > 12:
		largest.resize(12)
	return {
		"screen_record_count": records.size(),
		"invalid_screen_count": invalid_count,
		"suspicious_screen_count": suspicious_count,
		"large_triangle_samples": largest,
	}


func _larger_edge_first(first: Dictionary, second: Dictionary) -> bool:
	return float(first.get("edge_max", 0.0)) > float(second.get("edge_max", 0.0))


func _vector2_array(points: PackedVector2Array) -> Array:
	var output: Array = []
	for point: Vector2 in points:
		output.append([point.x, point.y])
	return output
