extends Control
## Deterministic visible-window performance capture for V2.1.2-PERF comparisons.

const MAIN_SCENE := preload("res://scenes/prototype_v2/prototype_v2_main.tscn")
const ARTIFACT_DIRECTORY := "res://artifacts/prototype_v2_perf_review"
const LONG_SCENARIO_SECONDS: float = 20.0
const OVERLAY_SCENARIO_SECONDS: float = 5.0

var _view: PrototypeV2Main
var _phase: String = "before"
var _csv_lines: PackedStringArray = PackedStringArray()
var _scenario_summaries: Array[Dictionary] = []
var _memory_stability_summary: Dictionary = {}


func _ready() -> void:
	get_viewport().content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIRECTORY))
	_phase = "after" if FileAccess.file_exists(
		"%s/godot_profiler_before.csv" % ARTIFACT_DIRECTORY
	) else "before"
	_csv_lines.append(
		"scenario,frame,frame_ms,fps_monitor,process_ms,memory_mib,nodes,"
		+ "draw_objects,draw_primitives,draw_calls"
	)
	_view = MAIN_SCENE.instantiate() as PrototypeV2Main
	add_child(_view)
	_run_capture.call_deferred()


func _run_capture() -> void:
	await _wait_frames(12)
	_view.interface.close_top_layer()
	_view.map_canvas.focus_world()
	await _wait_frames(6)
	await _save_screenshot("01_world_far")
	await _measure_drag("world_far_drag", LONG_SCENARIO_SECONDS, Vector2(2.4, 1.1))

	_view.interface.close_top_layer()
	_view.map_canvas.focus_france()
	await _wait_frames(6)
	await _save_screenshot("02_france")
	await _measure_drag("france_drag", LONG_SCENARIO_SECONDS, Vector2(2.1, 1.3))

	_view.interface.close_top_layer()
	_view.map_canvas.focus_player_location()
	await _wait_frames(6)
	await _save_screenshot("03_nord_96x")
	await _measure_drag("nord_96x_drag", LONG_SCENARIO_SECONDS, Vector2(1.8, 1.4))

	_view.interface.open_panel_named("character", false)
	_view.map_canvas.focus_player_location()
	await _wait_frames(6)
	await _save_screenshot("04_character_panel")
	await _measure_drag("nord_96x_character_panel_drag", LONG_SCENARIO_SECONDS, Vector2(1.7, 1.3))
	_view.interface.close_panel(false)

	for mode_id: String in ["population", "market", "war"]:
		_view.map_canvas.set_mode(mode_id)
		_view.interface.set_mode_display(mode_id)
		_view.map_canvas.focus_player_location()
		await _wait_frames(4)
		await _measure_drag(
			"nord_96x_%s_drag" % mode_id,
			OVERLAY_SCENARIO_SECONDS,
			Vector2(1.6, 1.2)
		)

	_view.map_canvas.set_mode("legal")
	_view.interface.set_mode_display("legal")
	_view.map_canvas.focus_player_location()
	await _wait_frames(4)
	await _measure_rapid_zoom()
	await _measure_memory_stability()
	await _write_results()
	print("PROTOTYPE_PERF_CAPTURE_COMPLETE phase=%s" % _phase)
	await _wait_frames(3)
	get_tree().quit()


func _measure_drag(scenario: String, duration_seconds: float, amplitude: Vector2) -> void:
	_view.map_canvas.debug_reset_performance_metrics()
	_view.map_canvas.begin_camera_interaction()
	var samples: Array[Dictionary] = []
	var started_usec: int = Time.get_ticks_usec()
	var previous_frame_usec: int = started_usec
	var frame_index: int = 0
	while float(Time.get_ticks_usec() - started_usec) / 1000000.0 < duration_seconds:
		var direction: float = -1.0 if frame_index % 120 >= 60 else 1.0
		var vertical: float = -1.0 if frame_index % 84 >= 42 else 1.0
		_view.map_canvas.pan_by(Vector2(amplitude.x * direction, amplitude.y * vertical))
		await get_tree().process_frame
		var now_usec: int = Time.get_ticks_usec()
		var frame_ms: float = float(now_usec - previous_frame_usec) / 1000.0
		previous_frame_usec = now_usec
		samples.append(_sample_frame(scenario, frame_index, frame_ms))
		frame_index += 1
	var restore_started_usec: int = Time.get_ticks_usec()
	_view.map_canvas.end_camera_interaction()
	await get_tree().process_frame
	var label_restore_ms: float = float(
		Time.get_ticks_usec() - restore_started_usec
	) / 1000.0
	_finish_scenario(
		scenario,
		samples,
		{"label_restore_ms": label_restore_ms}
	)


func _measure_rapid_zoom() -> void:
	const SCENARIO := "nord_96x_rapid_zoom_100"
	_view.map_canvas.debug_reset_performance_metrics()
	var samples: Array[Dictionary] = []
	var previous_frame_usec: int = Time.get_ticks_usec()
	var anchor := Vector2(704.0, 372.0)
	for operation_index: int in range(100):
		var direction: float = -1.0 if operation_index % 2 == 0 else 1.0
		_view.map_canvas.zoom_at(direction, anchor)
		if operation_index % 4 == 3:
			_view.map_canvas.pan_by(Vector2(6.0, -3.0))
		await get_tree().process_frame
		var now_usec: int = Time.get_ticks_usec()
		var frame_ms: float = float(now_usec - previous_frame_usec) / 1000.0
		previous_frame_usec = now_usec
		samples.append(_sample_frame(SCENARIO, operation_index, frame_ms))
	_finish_scenario(SCENARIO, samples)


func _measure_memory_stability() -> void:
	_view.interface.close_top_layer()
	_view.map_canvas.set_mode("legal")
	_view.interface.set_mode_display("legal")
	_view.map_canvas.focus_player_location()
	await _wait_frames(20)
	_view.map_canvas.debug_reset_performance_metrics()
	_view.map_canvas.begin_camera_interaction()
	var started_usec: int = Time.get_ticks_usec()
	var start_mib: float = float(
		Performance.get_monitor(Performance.MEMORY_STATIC)
	) / 1048576.0
	var maximum_mib: float = start_mib
	var frame_count: int = 0
	while float(Time.get_ticks_usec() - started_usec) / 1000000.0 < 20.0:
		var horizontal: float = -1.0 if frame_count % 180 >= 90 else 1.0
		var vertical: float = -1.0 if frame_count % 126 >= 63 else 1.0
		_view.map_canvas.pan_by(Vector2(2.0 * horizontal, 1.3 * vertical))
		await get_tree().process_frame
		if frame_count % 60 == 0:
			maximum_mib = maxf(
				maximum_mib,
				float(Performance.get_monitor(Performance.MEMORY_STATIC))
				/ 1048576.0
			)
		frame_count += 1
	_view.map_canvas.end_camera_interaction()
	await _wait_frames(10)
	var end_mib: float = float(
		Performance.get_monitor(Performance.MEMORY_STATIC)
	) / 1048576.0
	var map_snapshot: Dictionary = _view.map_canvas.debug_performance_snapshot()
	_memory_stability_summary = {
		"scenario": "nord_96x_unrecorded_drag_20s",
		"frames": frame_count,
		"duration_seconds": float(Time.get_ticks_usec() - started_usec) / 1000000.0,
		"memory_mib_start": start_mib,
		"memory_mib_end": end_mib,
		"memory_mib_max": maxf(maximum_mib, end_mib),
		"memory_mib_delta": end_mib - start_mib,
		"map_metrics": map_snapshot,
	}
	print(
		"PERF_MEMORY_STABILITY frames=%d delta_mib=%.4f max_mib=%.4f" % [
			frame_count,
			end_mib - start_mib,
			maxf(maximum_mib, end_mib),
		]
	)


func _sample_frame(
	scenario: String,
	frame_index: int,
	frame_ms: float
) -> Dictionary:
	var sample := {
		"scenario": scenario,
		"frame": frame_index,
		"frame_ms": frame_ms,
		"fps_monitor": float(Performance.get_monitor(Performance.TIME_FPS)),
		"process_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		"memory_mib": float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"draw_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"draw_primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	}
	_csv_lines.append(
		"%s,%d,%.4f,%.2f,%.4f,%.4f,%d,%d,%d,%d" % [
			scenario,
			frame_index,
			frame_ms,
			float(sample["fps_monitor"]),
			float(sample["process_ms"]),
			float(sample["memory_mib"]),
			int(sample["nodes"]),
			int(sample["draw_objects"]),
			int(sample["draw_primitives"]),
			int(sample["draw_calls"]),
		]
	)
	return sample


func _finish_scenario(
	scenario: String,
	samples: Array[Dictionary],
	extra: Dictionary = {}
) -> void:
	var frame_values: Array[float] = []
	var process_values: Array[float] = []
	var memory_values: Array[float] = []
	var draw_call_values: Array[float] = []
	var primitive_values: Array[float] = []
	for sample: Dictionary in samples:
		frame_values.append(float(sample["frame_ms"]))
		process_values.append(float(sample["process_ms"]))
		memory_values.append(float(sample["memory_mib"]))
		draw_call_values.append(float(sample["draw_calls"]))
		primitive_values.append(float(sample["draw_primitives"]))
	var map_snapshot: Dictionary = _view.map_canvas.debug_performance_snapshot()
	var map_draw_values: Array[float] = []
	for value: Variant in map_snapshot.get("draw_ms_samples", []):
		map_draw_values.append(float(value))
	var average_frame_ms: float = _average(frame_values)
	var summary := {
		"scenario": scenario,
		"frames": samples.size(),
		"average_fps": 1000.0 / average_frame_ms if average_frame_ms > 0.0 else 0.0,
		"minimum_fps": 1000.0 / _maximum(frame_values) if not frame_values.is_empty() else 0.0,
		"one_percent_low_fps": 1000.0 / _percentile(frame_values, 0.99) if not frame_values.is_empty() else 0.0,
		"frame_ms_average": average_frame_ms,
		"frame_ms_p95": _percentile(frame_values, 0.95),
		"frame_ms_max": _maximum(frame_values),
		"process_ms_average": _average(process_values),
		"process_ms_p95": _percentile(process_values, 0.95),
		"map_draw_ms_average": _average(map_draw_values),
		"map_draw_ms_p95": _percentile(map_draw_values, 0.95),
		"map_draw_ms_max": _maximum(map_draw_values),
		"memory_mib_start": memory_values[0] if not memory_values.is_empty() else 0.0,
		"memory_mib_end": memory_values[-1] if not memory_values.is_empty() else 0.0,
		"memory_mib_max": _maximum(memory_values),
		"draw_calls_average": _average(draw_call_values),
		"draw_primitives_average": _average(primitive_values),
		"map_metrics": map_snapshot,
	}
	summary.merge(extra, true)
	_scenario_summaries.append(summary)
	print(
		"PERF_SCENARIO %s avg_fps=%.2f p95=%.3f max=%.3f map_p95=%.3f" % [
			scenario,
			float(summary["average_fps"]),
			float(summary["frame_ms_p95"]),
			float(summary["frame_ms_max"]),
			float(summary["map_draw_ms_p95"]),
		]
	)


func _save_screenshot(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [ARTIFACT_DIRECTORY, _phase, stem]
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Unable to save performance review screenshot: %s" % path)


func _write_results() -> void:
	var csv_path := "%s/godot_profiler_%s.csv" % [ARTIFACT_DIRECTORY, _phase]
	var csv_file: FileAccess = FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		push_error("Unable to write performance CSV: %s" % csv_path)
		return
	csv_file.store_string("\n".join(_csv_lines) + "\n")
	var summary_path := "%s/performance_%s.json" % [ARTIFACT_DIRECTORY, _phase]
	var summary_file: FileAccess = FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file == null:
		push_error("Unable to write performance summary: %s" % summary_path)
		return
	summary_file.store_string(
		JSON.stringify(
			{
				"phase": _phase,
				"engine_version": Engine.get_version_info(),
				"renderer": RenderingServer.get_current_rendering_method(),
				"viewport": [1280, 720],
				"scenarios": _scenario_summaries,
				"memory_stability": _memory_stability_summary,
			},
			"\t"
		)
	)


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().process_frame


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _maximum(values: Array[float]) -> float:
	var result: float = 0.0
	for value: float in values:
		result = maxf(result, value)
	return result


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	var index: int = clampi(
		int(ceil(float(ordered.size()) * ratio)) - 1,
		0,
		ordered.size() - 1
	)
	return ordered[index]
