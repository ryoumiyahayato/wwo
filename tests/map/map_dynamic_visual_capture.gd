extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "res://artifacts/map-r4-2-player-screenshots"
const PRODUCT_VIEW_STATES: Array[Dictionary] = [
	{"id": "AFRICA", "yaw": 0.0, "tilt": 0.0, "zoom": 0.86},
	{"id": "EURASIA", "yaw": 78.0, "tilt": 4.0, "zoom": 0.88},
	{"id": "NORTH-AMERICA", "yaw": 180.0, "tilt": 0.0, "zoom": 0.86},
]
const CAMERA_STATES: Array[Dictionary] = [
	{"id": "RUS-1-normal", "yaw": 0.0, "tilt": 0.0, "zoom": 0.86},
	{"id": "RUS-2-north", "yaw": 42.0, "tilt": 38.0, "zoom": 0.90},
	{"id": "RUS-3-high-north", "yaw": 94.0, "tilt": 72.0, "zoom": 0.96},
	{"id": "RUS-4-horizon", "yaw": 146.0, "tilt": 82.0, "zoom": 1.02},
	{"id": "RUS-5-opposite", "yaw": 218.0, "tilt": 24.0, "zoom": 0.88},
	{"id": "RUS-6-return", "yaw": 360.0, "tilt": 0.0, "zoom": 0.86},
]
const WORLD_ROTATION_YAWS: Array[float] = [0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0]
const POLAR_NORTH_STATES: Array[Dictionary] = [
	{"id": "POLAR-NORTH-1", "yaw": 0.0, "tilt": 70.0, "zoom": 0.92},
	{"id": "POLAR-NORTH-2", "yaw": 120.0, "tilt": 82.0, "zoom": 1.00},
	{"id": "POLAR-NORTH-3", "yaw": 240.0, "tilt": 76.0, "zoom": 1.06},
]
const POLAR_SOUTH_STATES: Array[Dictionary] = [
	{"id": "POLAR-SOUTH-1", "yaw": 0.0, "tilt": -70.0, "zoom": 0.92},
	{"id": "POLAR-SOUTH-2", "yaw": 120.0, "tilt": -82.0, "zoom": 1.00},
	{"id": "POLAR-SOUTH-3", "yaw": 240.0, "tilt": -76.0, "zoom": 1.06},
]
const NEJD_CENTRAL_ARABIA_STATES: Array[Dictionary] = [
	{"id": "NEJD-3-rotated-west-MISSING-HISTORICAL-RECORD", "yaw": 285.0, "tilt": 18.0, "zoom": 1.02},
	{"id": "NEJD-4-rotated-east-MISSING-HISTORICAL-RECORD", "yaw": 45.0, "tilt": 18.0, "zoom": 1.02},
	{"id": "NEJD-5-higher-pitch-MISSING-HISTORICAL-RECORD", "yaw": 315.0, "tilt": 42.0, "zoom": 1.08},
	{"id": "NEJD-6-closer-MISSING-HISTORICAL-RECORD", "yaw": 315.0, "tilt": 18.0, "zoom": 1.22},
]

var _application: FormalWorldApplication
var _capture_index := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("Dynamic visual capture: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	_application.map_interaction_flag_lod_enabled = false
	_application.map_screen_topology_diagnostics_enabled = true
	get_root().add_child(_application)
	await _wait_frames(24)
	if _application == null or _application._countries.is_empty():
		push_error("Dynamic visual capture: formal roster did not initialize")
		quit(1)
		return
	_application.economy_panel_open = false
	_application.map_screen_topology_diagnostics_enabled = false
	await _wait_frames(4)

	for camera: Dictionary in PRODUCT_VIEW_STATES:
		await _capture_pair(str(camera.get("id", "view")), camera)
	for camera: Dictionary in CAMERA_STATES:
		await _capture_pair(str(camera.get("id", "camera")), camera)
	for yaw_value: float in WORLD_ROTATION_YAWS:
		var camera := {"yaw": yaw_value, "tilt": 0.0, "zoom": 0.86}
		await _capture_phase("ROT-%03d-flags" % int(yaw_value), camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	for camera: Dictionary in POLAR_NORTH_STATES:
		await _capture_phase(str(camera.get("id", "polar")) + "-flags", camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	for camera: Dictionary in POLAR_SOUTH_STATES:
		await _capture_phase(str(camera.get("id", "polar")) + "-flags", camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	await _capture_nejd_missing_record_evidence()

	# Explicit LOD transition evidence at a fixed camera. The political backing
	# stays visible during the synthetic drag state; only presentation is deferred.
	_application.map_interaction_flag_lod_enabled = true
	var lod_camera: Dictionary = {"yaw": 41.0, "tilt": 13.0, "zoom": 0.94}
	_application.dragging = false
	await _set_camera(lod_camera, false)
	await _capture_phase("LOD-Russia-before-drag", lod_camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	_application.dragging = true
	await _set_camera(lod_camera, true)
	await _capture_phase("LOD-Russia-during-drag", lod_camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	_application.dragging = false
	_application.angular_velocity = 0.0
	await _set_camera(lod_camera, false)
	await _capture_phase("LOD-Russia-first-post-drag", lod_camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	# The product deliberately holds the interaction LOD for 0.24 seconds
	# after the last camera event.  Do not call _set_camera again here: doing so
	# would renew that timer and make the evidence frame falsely look like the
	# interaction layer never restored its flags.
	await _wait_frames(20)
	await _capture_current_phase("LOD-Russia-settled", _application.MAP_PHASE_HISTORICAL_FLAGS)
	var render_diagnostic := {
		"source_audit": _application.call("historical_central_arabia_source_audit") if _application.has_method("historical_central_arabia_source_audit") else {},
		"map_render_trace": _application.call("map_render_trace") if _application.has_method("map_render_trace") else {},
	}
	var render_diagnostic_file := FileAccess.open(
		ProjectSettings.globalize_path(OUTPUT_DIR).path_join("R4-2-render-diagnostic.json"),
		FileAccess.WRITE
	)
	if render_diagnostic_file != null:
		render_diagnostic_file.store_string(JSON.stringify(render_diagnostic, "  "))

	_application.queue_free()
	quit(0)


func _capture_nejd_missing_record_evidence() -> void:
	# The repository has no 1900 Nejd/Najd/内志 unit or gw_697 geometry. These
	# are real product frames of the corresponding Central Arabia view, labelled
	# as evidence of the missing source record rather than as a fabricated polity.
	var central_arabia: Dictionary = {"yaw": 315.0, "tilt": 18.0, "zoom": 1.02}
	await _capture_phase("NEJD-1-solid-MISSING-HISTORICAL-RECORD", central_arabia, _application.MAP_PHASE_POLITICAL_SOLID)
	await _capture_phase("NEJD-2-final-material-MISSING-HISTORICAL-RECORD", central_arabia, _application.MAP_PHASE_HISTORICAL_FLAGS)
	for camera: Dictionary in NEJD_CENTRAL_ARABIA_STATES:
		var state_id := str(camera.get("id", "nejd"))
		await _capture_phase(state_id + "-solid", camera, _application.MAP_PHASE_POLITICAL_SOLID)
		await _capture_phase(state_id + "-final", camera, _application.MAP_PHASE_HISTORICAL_FLAGS)
	var diagnostic := {
		"entity_id": "",
		"historical_display_name": "内志酋长国 / Nejd",
		"repository_record_present": false,
		"geometry_present": false,
		"modern_saudi_substitution": false,
		"reason": "No 1900 Nejd/Najd/内志 polity or gw_697 geometry record exists in repository data.",
		"source_audit": _application.call("historical_central_arabia_source_audit") if _application.has_method("historical_central_arabia_source_audit") else {},
		"frames": [
			"NEJD-1-solid-MISSING-HISTORICAL-RECORD",
			"NEJD-2-final-material-MISSING-HISTORICAL-RECORD",
			"NEJD-3-rotated-west-MISSING-HISTORICAL-RECORD",
			"NEJD-4-rotated-east-MISSING-HISTORICAL-RECORD",
			"NEJD-5-higher-pitch-MISSING-HISTORICAL-RECORD",
			"NEJD-6-closer-MISSING-HISTORICAL-RECORD",
		],
	}
	var diagnostic_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join("NEJD-missing-historical-record.json")
	var diagnostic_file := FileAccess.open(diagnostic_path, FileAccess.WRITE)
	if diagnostic_file != null:
		diagnostic_file.store_string(JSON.stringify(diagnostic, "  "))


func _capture_pair(label: String, camera: Dictionary) -> void:
	await _capture_phase(label + "-solid", camera, _application.MAP_PHASE_POLITICAL_SOLID)
	await _capture_phase(label + "-flags", camera, _application.MAP_PHASE_HISTORICAL_FLAGS)


func _capture_phase(label: String, camera: Dictionary, phase: String, interactive: bool = false) -> void:
	await _set_camera(camera, interactive)
	await _capture_current_phase(label, phase)


func _capture_current_phase(label: String, phase: String) -> void:
	_application.map_render_phase = phase
	_application.queue_redraw()
	await _wait_frames(4)
	var image: Image = _application.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Dynamic visual capture: empty image for " + label)
		return
	var filename := "%03d_%s.png" % [_capture_index, label]
	_capture_index += 1
	var error: Error = image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR).path_join(filename))
	if error != OK:
		push_error("Dynamic visual capture failed for %s: %s" % [label, error_string(error)])


func _set_camera(camera: Dictionary, interactive: bool) -> void:
	_application.yaw = deg_to_rad(float(camera.get("yaw", 0.0)))
	_application.tilt = clampf(
		deg_to_rad(float(camera.get("tilt", 0.0))),
		-1.45,
		1.45
	)
	_application.world_zoom = clampf(float(camera.get("zoom", 0.86)), 0.74, 1.24)
	_application.dragging = interactive
	_application.angular_velocity = 0.0
	_application._mark_projection_dirty()
	_application._ensure_projection_cache()
	_application.queue_redraw()
	await _wait_frames(2)


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame
