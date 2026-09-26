extends Node
## Visible R2 M probe. An external watchdog observes this frame heartbeat while
## the real Compatibility renderer executes a deterministic player-like camera
## journey. This is diagnostic-only; it never bypasses the Formal product path.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "C:/Users/agcrf/wwo-formal-person-entry-r1/evidence/player_experience_r2/m/watchdog"

var _application: FormalWorldApplication
var _stage := "bootstrap"
var _frame_index := 0
var _heartbeat_accumulator := 0.0
var _rotate_velocity := 0.0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_run.call_deferred()


func _process(delta: float) -> void:
	_frame_index += 1
	_heartbeat_accumulator += delta
	if _application != null and not is_zero_approx(_rotate_velocity):
		_application.yaw = wrapf(_application.yaw + _rotate_velocity * delta, -PI, PI)
		_application._map_player_audit_input_kind = "drag"
		_application._mark_projection_dirty()
		_application.queue_redraw()
	if _heartbeat_accumulator < 0.20:
		return
	_heartbeat_accumulator = 0.0
	_write_heartbeat()


func _run() -> void:
	var service := FormalNewGameService.new()
	var preview := service.preview_player_candidates({
		"population_origin_id": "country_fra",
		"start_place_id": "place:lille",
		"birth_year_min": 1860,
		"birth_year_max": 1882,
		"random_origin": false,
		"locked_fields": {},
		"seed": 19000101,
		"rules_version": FormalNewGameService.RULES_VERSION,
		"draft_index": 0,
	})
	if not bool(preview.get("success", false)):
		_fail("candidate preview failed")
		return
	var candidate := (preview.get("candidates", []) as Array)[0] as Dictionary
	var created := service.create_new_game(
		str(candidate.get("candidate_token", "")), "watchdog:player-experience-r2:m"
	)
	if not bool(created.get("success", false)):
		_fail(str(created.get("message", "new game failed")))
		return
	var world := created.get("world") as FormalWorldSimulation
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	_application = (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(_application)
	_application._map_player_audit_path = OUTPUT_DIR.path_join("map_frame_audit.json")
	await _frames(12)
	_application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	_application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_POLITICAL)
	_application.selected_country_id = "state:country_fra"

	await _stage_wait("global_idle", 3.0)
	_stage = "continuous_rotate_30s"
	_application.dragging = true
	_rotate_velocity = 0.72
	await get_tree().create_timer(30.0).timeout
	_rotate_velocity = 0.0
	_application.dragging = false

	for zoom_step: float in [2.35, 6.0, 2.35, 1.0]:
		_stage = "zoom_%.2f" % zoom_step
		_application._map_player_audit_input_kind = "zoom"
		_application._set_world_zoom(zoom_step)
		await get_tree().create_timer(1.0).timeout

	_stage = "high_latitude_rotate"
	_application.tilt = 1.28
	_application.dragging = true
	_rotate_velocity = 0.55
	await get_tree().create_timer(5.0).timeout
	_rotate_velocity = 0.0
	_application.dragging = false

	_stage = "dateline_rotate"
	_application.yaw = 3.08
	_application.tilt = 0.42
	_application._mark_projection_dirty()
	_application.dragging = true
	_rotate_velocity = 0.28
	await get_tree().create_timer(3.0).timeout
	_rotate_velocity = 0.0
	_application.dragging = false

	_stage = "selected_polity"
	_application.selected_country_id = "state:russian_empire"
	_application._mark_projection_dirty()
	await get_tree().create_timer(2.0).timeout

	_stage = "economy_overlay"
	_application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_FULFILLMENT)
	await get_tree().create_timer(2.0).timeout

	_stage = "repeat_roundtrip"
	for zoom_step: float in [6.0, 2.35, 1.0]:
		_application._set_world_zoom(zoom_step)
		await get_tree().create_timer(1.0).timeout

	_stage = "final_idle_restore"
	_application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_POLITICAL)
	_application.selected_country_id = "state:country_fra"
	_application.yaw = -0.72
	_application.tilt = 0.42
	_application._set_world_zoom(1.0)
	_application._mark_projection_dirty()
	await get_tree().create_timer(3.0).timeout
	var diagnostic := {
		"final_state": _application.formal_map_lod_report(true),
		"performance": _application.map_performance_diagnostic_report(),
		"player_person_id": _application.formal_simulation.player_person_id(),
	}
	var diagnostic_file := FileAccess.open(
		OUTPUT_DIR.path_join("probe_final_diagnostic.json"), FileAccess.WRITE
	)
	if diagnostic_file == null:
		_fail("could not write final diagnostic")
		return
	diagnostic_file.store_string(JSON.stringify(diagnostic, "  "))
	_stage = "complete"
	_write_heartbeat()
	_application.queue_free()
	get_tree().quit(0)


func _stage_wait(stage_name: String, seconds: float) -> void:
	_stage = stage_name
	await get_tree().create_timer(seconds).timeout


func _frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame


func _write_heartbeat() -> void:
	var state: Dictionary = {}
	if _application != null:
		state = _application.formal_map_lod_report()
	var file := FileAccess.open(OUTPUT_DIR.path_join("heartbeat.json"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"timestamp_unix_msec": Time.get_unix_time_from_system() * 1000.0,
		"ticks_usec": Time.get_ticks_usec(),
		"frame": _frame_index,
		"stage": _stage,
		"yaw": state.get("yaw", 0.0),
		"pitch": state.get("pitch", 0.0),
		"zoom": state.get("zoom", 0.0),
		"lod": state.get("visual_lod", ""),
		"flag_batches": state.get("drawn_flag_entity_count", 0),
		"fallback_count": state.get("fallback_count", 0),
	}))


func _fail(message: String) -> void:
	push_error("R2 M watchdog probe: " + message)
	_stage = "failed"
	_write_heartbeat()
	get_tree().quit(1)
