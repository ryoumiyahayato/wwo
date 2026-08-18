extends SceneTree

## Deterministic evidence capture for the R4.3 player-runtime gate.
## This instantiates the formal product scene and saves the actual viewport,
## including the same draw path used by the player.  It never mutates source
## map data and writes only to the R4.3 evidence directory.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/map-r4-3-player-runtime"
const WAIT_AFTER_CAMERA_FRAMES := 3
const FRAME_SEQUENCE_COUNT := 40
const FRAME_SEQUENCE_STEP := 15

var _application: FormalWorldApplication
var _capture_index := 0
var _manifest: Array[Dictionary] = []


func _initialize() -> void:

	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("R4.3 runtime capture: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	_application.map_interaction_flag_lod_enabled = false
	_application.map_screen_topology_diagnostics_enabled = false
	_application.map_debug_hide_physical_boundaries = OS.get_cmdline_args().has("--r43-hide-physical-boundaries")
	_application.map_debug_hide_physical_land = OS.get_cmdline_args().has("--r43-hide-physical-land")
	get_root().add_child(_application)
	await _wait_until_ready()
	if _application == null or _application.map_debug_historical_roster().is_empty():
		push_error("R4.3 runtime capture: historical roster did not initialize")
		quit(1)
		return
	_application.economy_panel_open = false
	await _wait_frames(4)

	var static_states: Array[Dictionary] = [
		{"id": "CANADA-normal", "yaw": 180.0, "tilt": 0.0, "zoom": 0.86, "phases": ["solid", "flags"]},
		{"id": "CANADA-high-north", "yaw": 220.0, "tilt": 72.0, "zoom": 1.10, "phases": ["solid", "flags"]},
		{"id": "CANADA-horizon", "yaw": 250.0, "tilt": 82.0, "zoom": 1.00, "phases": ["solid", "flags"]},
		{"id": "RUSSIA-high-north", "yaw": 94.0, "tilt": 72.0, "zoom": 1.08, "phases": ["solid", "flags"]},
		{"id": "AFGHANISTAN-close-emirate_of_afghanistan", "focus_entity": "emirate_of_afghanistan", "zoom": 2.40, "phases": ["solid", "flags"]},
		{"id": "CENTRAL-ARABIA-JABAL-SHAMMAR-control-approximate", "focus_lon_lat": [44.0, 24.0], "zoom": 2.40, "phases": ["physical", "solid", "flags"]},
		{"id": "ZOOM-world", "yaw": 0.0, "tilt": 0.0, "zoom": 0.76, "phases": ["flags"]},
		{"id": "ZOOM-continent", "yaw": 78.0, "tilt": 4.0, "zoom": 1.35, "phases": ["flags"]},
		{"id": "ZOOM-country", "yaw": 104.0, "tilt": 28.0, "zoom": 2.40, "phases": ["flags"]},
		{"id": "ZOOM-regional", "yaw": 104.0, "tilt": 28.0, "zoom": 4.20, "phases": ["flags"]},
	]
	for state: Dictionary in static_states:
		for phase: String in state.get("phases", []) as Array:
			await _capture_state(str(state.get("id", "state")) + "-" + phase, state, phase)
	if OS.get_cmdline_args().has("--r43-static-only"):
		await _write_manifest()
		_application.queue_free()
		quit(0)
		return

	await _capture_lod_transition()
	await _capture_rotation_sequence("CANADA-high-lat-rotation", 220.0, 72.0, 1.10)
	await _capture_rotation_sequence("RUSSIA-high-lat-rotation", 94.0, 72.0, 1.08)
	await _capture_zoom_sequence()

	await _write_manifest()
	_application.queue_free()
	quit(0)


func _write_manifest() -> void:
	var manifest_file := FileAccess.open(
		ProjectSettings.globalize_path(OUTPUT_DIR).path_join("R4-3-player-runtime-manifest.json"),
		FileAccess.WRITE
	)
	if manifest_file != null:
		manifest_file.store_string(JSON.stringify({
			"camera_center_contract": _application.camera_navigation_report(),
			"historical_targets": {
				"afghanistan": _application.map_debug_country_record("emirate_of_afghanistan"),
				"central_arabia": _application.call("historical_central_arabia_source_audit") if _application.has_method("historical_central_arabia_source_audit") else {},
			},
			"frames": _manifest,
		}, "  "))


func _wait_until_ready() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		if _application != null and bool(_application.map_debug_historical_roster().get("ready", false)):
			return
		await process_frame


func _capture_lod_transition() -> void:
	var state: Dictionary = {"yaw": 94.0, "tilt": 72.0, "zoom": 1.08}
	_application.map_interaction_flag_lod_enabled = true
	_application.dragging = false
	await _capture_state("LOD-idle-before", state, "flags")
	_application.dragging = true
	await _capture_state("LOD-during-drag", state, "flags")
	_application.dragging = false
	_application.angular_velocity = 0.0
	await _capture_state("LOD-first-frame-after-release", state, "flags")
	await _wait_frames(12)
	await _capture_state("LOD-settled-full-detail", state, "flags")
	_application.map_interaction_flag_lod_enabled = false


func _capture_rotation_sequence(prefix: String, yaw_start: float, pitch: float, zoom: float) -> void:
	for index: int in range(FRAME_SEQUENCE_COUNT):
		var state := {
			"yaw": yaw_start + float(index) * 9.0,
			"tilt": pitch,
			"zoom": zoom,
		}
		await _capture_state("%s-%03d" % [prefix, index], state, "flags")
		await _wait_frames(FRAME_SEQUENCE_STEP)


func _capture_zoom_sequence() -> void:
	var zooms: Array[float] = [0.76, 1.20, 2.00, 3.20, 4.80, 3.20, 2.00, 1.20, 0.76]
	for index: int in range(zooms.size()):
		var state := {"yaw": 104.0, "tilt": 28.0, "zoom": zooms[index]}
		await _capture_state("ZOOM-round-trip-%02d" % index, state, "flags")
		await _wait_frames(8)


func _capture_state(label: String, state: Dictionary, phase_name: String) -> void:
	await _set_camera(state)
	_application.map_render_phase = {
		"physical": _application.MAP_PHASE_LAND_ONLY,
		"solid": _application.MAP_PHASE_POLITICAL_SOLID,
		"flags": _application.MAP_PHASE_HISTORICAL_FLAGS,
	}.get(phase_name, _application.MAP_PHASE_HISTORICAL_FLAGS)
	_application.queue_redraw()
	await _wait_for_static_surface_complete()
	await _wait_frames(WAIT_AFTER_CAMERA_FRAMES)
	var image: Image = _application.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("R4.3 runtime capture: empty image for " + label)
		return
	var filename := "%03d_%s.png" % [_capture_index, label]
	_capture_index += 1
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR).path_join(filename)
	var error := image.save_png(absolute)
	if error != OK:
		push_error("R4.3 runtime capture failed for %s: %s" % [label, error_string(error)])
		return
	_manifest.append({
		"label": label,
		"file": filename,
		"phase": phase_name,
		"camera": _application.camera_navigation_report(),
		"trace": _application.map_render_trace(),
	})


func _wait_for_static_surface_complete() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		if _application != null and bool(_application.map_debug_static_surface_report().get("complete", false)):
			return
		await process_frame


func _set_camera(state: Dictionary) -> void:
	if state.has("focus_entity") and _application.has_method("map_debug_focus_camera_on_entity"):
		_application.call("map_debug_focus_camera_on_entity", str(state.get("focus_entity", "")), float(state.get("zoom", 2.4)))
		return
	if state.has("focus_lon_lat") and _application.has_method("map_debug_focus_camera_on_lon_lat"):
		var focus_lon_lat: Array = state.get("focus_lon_lat", []) as Array
		if focus_lon_lat.size() >= 2:
			_application.call(
				"map_debug_focus_camera_on_lon_lat",
				float(focus_lon_lat[0]),
				float(focus_lon_lat[1]),
				float(state.get("zoom", 2.4))
			)
			return
	_application.yaw = deg_to_rad(float(state.get("yaw", 0.0)))
	_application.tilt = clampf(deg_to_rad(float(state.get("tilt", 0.0))), -1.45, 1.45)
	_application.world_zoom = clampf(float(state.get("zoom", 0.86)), 0.74, 6.0)
	_application._mark_projection_dirty()
	_application._ensure_projection_cache()
	_application.queue_redraw()


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame
