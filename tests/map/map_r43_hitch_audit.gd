extends SceneTree

## Actual Formal World frame-time audit for R4.3.
## The workload drives the real scene/camera draw path; it does not replace the
## product with a synthetic gameplay loop.  It records wall-clock frame gaps
## and the renderer's own per-frame profile separately.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_PATH := "res://artifacts/map-r4-3-player-runtime/R4-3-hitch-audit.json"
const DEFAULT_WORKLOAD_SECONDS := 30.0

var _application: FormalWorldApplication
var _workloads: Dictionary = {}
var _workload_seconds: float = DEFAULT_WORKLOAD_SECONDS
var _active_slow_frames: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_args().has("--r43-short"):
		_workload_seconds = 3.0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("R4.3 hitch audit: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	_application.map_interaction_flag_lod_enabled = true
	get_root().add_child(_application)
	var startup := await _measure_startup()
	_workloads["startup"] = startup
	await _wait_for_static_surface_complete()
	_workloads["horizontal_drag_30s"] = await _measure_camera_workload("horizontal_drag_30s", 1.0, 0.0, false)
	_workloads["diagonal_drag_30s"] = await _measure_camera_workload("diagonal_drag_30s", 0.74, 0.42, false)
	_workloads["high_latitude_drag_30s"] = await _measure_camera_workload("high_latitude_drag_30s", 0.31, 0.92, false)
	_workloads["repeated_zoom_30s"] = await _measure_zoom_workload()
	_workloads["drag_release_drag"] = await _measure_transition_workload("drag_release_drag")
	_workloads["select_ocean_navigate"] = await _measure_transition_workload("select_ocean_navigate")
	var file := FileAccess.open(ProjectSettings.globalize_path(OUTPUT_PATH), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"workload_seconds": _workload_seconds,
			"camera_center_contract": _application.camera_navigation_report(),
			"workloads": _workloads,
		}, "  "))
	_application.queue_free()
	quit(0)


func _measure_startup() -> Dictionary:
	var samples: Array[float] = []
	var profile_samples: Array[float] = []
	var started := Time.get_ticks_usec()
	var first_usable_usec := -1
	var static_complete_usec := -1
	var deadline := started + 180000000
	var frame_counter := 0
	_active_slow_frames.clear()
	while Time.get_ticks_usec() < deadline:
		var before := Time.get_ticks_usec()
		await process_frame
		var elapsed := float(Time.get_ticks_usec() - before) / 1000.0
		samples.append(elapsed)
		var trace := _application.map_render_trace()
		profile_samples.append(float((trace.get("profile", {}) as Dictionary).get("frame_usec", 0)) / 1000.0)
		if elapsed > 100.0:
			_active_slow_frames.append(_slow_frame_sample(elapsed))
		if first_usable_usec < 0 and bool(_application.map_debug_historical_roster().get("ready", false)):
			first_usable_usec = Time.get_ticks_usec() - started
		if static_complete_usec < 0 and bool(_application.map_debug_static_surface_report().get("complete", false)):
			static_complete_usec = Time.get_ticks_usec() - started
		if frame_counter % 60 == 0:
			print("R43_STARTUP_PROGRESS frame=%d roster=%s static=%s" % [
				frame_counter,
				str(_application.map_debug_historical_roster().get("ready", false)),
				str(_application.map_debug_static_surface_report().get("complete", false)),
			])
		frame_counter += 1
		if static_complete_usec >= 0:
			break
	return {
		"wall_to_first_usable_ms": float(first_usable_usec) / 1000.0 if first_usable_usec >= 0 else -1.0,
		"wall_to_static_complete_ms": float(static_complete_usec) / 1000.0 if static_complete_usec >= 0 else -1.0,
		"wall_frames": _frame_statistics(samples),
		"renderer_frames": _frame_statistics(profile_samples),
		"slow_frames": _active_slow_frames.duplicate(true),
		"profile": _application.map_render_trace().get("profile", {}),
	}


func _measure_camera_workload(label: String, yaw_step: float, tilt_step: float, high_pitch: bool) -> Dictionary:
	_application.dragging = true
	_application.angular_velocity = 0.0
	var samples: Array[float] = []
	var profile_samples: Array[float] = []
	var started := Time.get_ticks_usec()
	var frame_index := 0
	var slow_frames: Array[Dictionary] = []
	while float(Time.get_ticks_usec() - started) < _workload_seconds * 1000000.0:
		var before := Time.get_ticks_usec()
		_application.yaw += yaw_step * 0.016
		_application.tilt = clampf(
			_application.tilt + tilt_step * 0.016 * (1.0 if high_pitch or frame_index % 2 == 0 else -1.0),
			-1.45,
			1.45
		)
		_application._mark_projection_dirty()
		_application.queue_redraw()
		await process_frame
		var elapsed := float(Time.get_ticks_usec() - before) / 1000.0
		samples.append(elapsed)
		var trace := _application.map_render_trace()
		profile_samples.append(float((trace.get("profile", {}) as Dictionary).get("frame_usec", 0)) / 1000.0)
		if elapsed > 100.0:
			slow_frames.append(_slow_frame_sample(elapsed))
		frame_index += 1
	_application.dragging = false
	_application.angular_velocity = 0.0
	await _wait_frames(4)
	return {
		"label": label,
		"wall_frames": _frame_statistics(samples),
		"renderer_frames": _frame_statistics(profile_samples),
		"slow_frames": slow_frames,
		"frame_count": samples.size(),
		"final_camera": _application.camera_navigation_report(),
	}


func _measure_zoom_workload() -> Dictionary:
	_application.dragging = false
	var samples: Array[float] = []
	var profile_samples: Array[float] = []
	var started := Time.get_ticks_usec()
	var direction := 1.0
	var slow_frames: Array[Dictionary] = []
	while float(Time.get_ticks_usec() - started) < _workload_seconds * 1000000.0:
		var before := Time.get_ticks_usec()
		_application._set_world_zoom(_application.world_zoom + direction * 0.10, _application._hemisphere_center)
		if _application.world_zoom >= 5.9:
			direction = -1.0
		elif _application.world_zoom <= 0.76:
			direction = 1.0
		await process_frame
		var elapsed := float(Time.get_ticks_usec() - before) / 1000.0
		samples.append(elapsed)
		var trace := _application.map_render_trace()
		profile_samples.append(float((trace.get("profile", {}) as Dictionary).get("frame_usec", 0)) / 1000.0)
		if elapsed > 100.0:
			slow_frames.append(_slow_frame_sample(elapsed))
	return {
		"wall_frames": _frame_statistics(samples),
		"renderer_frames": _frame_statistics(profile_samples),
		"slow_frames": slow_frames,
		"frame_count": samples.size(),
		"final_camera": _application.camera_navigation_report(),
	}


func _measure_transition_workload(label: String) -> Dictionary:
	var samples: Array[float] = []
	var profile_samples: Array[float] = []
	var phase_boundaries: Array[Dictionary] = []
	_active_slow_frames.clear()
	var overall_start := Time.get_ticks_usec()
	_application.dragging = true
	for index: int in range(24):
		_application.yaw += 0.012
		_application.tilt = clampf(_application.tilt + 0.003, -1.45, 1.45)
		await _sample_one_frame(samples, profile_samples)
	_application.dragging = false
	phase_boundaries.append({"phase": "release", "elapsed_ms": float(Time.get_ticks_usec() - overall_start) / 1000.0})
	for _index: int in range(48):
		await _sample_one_frame(samples, profile_samples)
	phase_boundaries.append({"phase": "settled_probe", "elapsed_ms": float(Time.get_ticks_usec() - overall_start) / 1000.0})
	_application.dragging = true
	for index: int in range(24):
		_application.yaw -= 0.009
		_application.tilt = clampf(_application.tilt - 0.002, -1.45, 1.45)
		await _sample_one_frame(samples, profile_samples)
	_application.dragging = false
	return {
		"label": label,
		"wall_frames": _frame_statistics(samples),
		"renderer_frames": _frame_statistics(profile_samples),
		"slow_frames": _active_slow_frames.duplicate(true),
		"phase_boundaries": phase_boundaries,
		"final_camera": _application.camera_navigation_report(),
	}


func _sample_one_frame(samples: Array[float], profile_samples: Array[float]) -> void:
	var before := Time.get_ticks_usec()
	_application._mark_projection_dirty()
	_application.queue_redraw()
	await process_frame
	samples.append(float(Time.get_ticks_usec() - before) / 1000.0)
	var trace := _application.map_render_trace()
	profile_samples.append(float((trace.get("profile", {}) as Dictionary).get("frame_usec", 0)) / 1000.0)
	if samples.back() > 100.0:
		_active_slow_frames.append(_slow_frame_sample(float(samples.back())))


func _slow_frame_sample(elapsed_ms: float) -> Dictionary:
	return {
		"elapsed_ms": elapsed_ms,
		"profile": _application.map_render_trace().get("profile", {}),
		"camera": _application.camera_navigation_report(),
		"static_surface": _application.map_debug_static_surface_report(),
		"detail_restore_in_progress": bool(_application.get("_detail_restore_in_progress")),
		"interactive_surface_build_complete": bool(_application.get("_interactive_surface_build_complete")),
		"flag_cache_revision": int(_application.get("_flag_projection_cache_revision")),
	}


func _frame_statistics(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	var over_250 := 0
	var over_500 := 0
	var over_1000 := 0
	var longest_stall := 0
	var current_stall := 0
	for value: float in values:
		total += value
		if value > 33.0:
			over_33 += 1
			current_stall += 1
			longest_stall = maxi(longest_stall, current_stall)
		else:
			current_stall = 0
		if value > 50.0: over_50 += 1
		if value > 100.0: over_100 += 1
		if value > 250.0: over_250 += 1
		if value > 500.0: over_500 += 1
		if value > 1000.0: over_1000 += 1
	return {
		"count": values.size(),
		"median_ms": _percentile(sorted, 0.50),
		"p90_ms": _percentile(sorted, 0.90),
		"p99_ms": _percentile(sorted, 0.99),
		"max_ms": float(sorted[sorted.size() - 1]),
		"mean_ms": total / float(values.size()),
		"frames_over_33ms": over_33,
		"frames_over_50ms": over_50,
		"frames_over_100ms": over_100,
		"frames_over_250ms": over_250,
		"frames_over_500ms": over_500,
		"frames_over_1000ms": over_1000,
		"longest_consecutive_over_33ms": longest_stall,
	}


func _percentile(sorted: Array, fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return float(sorted[index])


func _wait_for_static_surface_complete() -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		if bool(_application.map_debug_static_surface_report().get("complete", false)):
			return
		await process_frame


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame
