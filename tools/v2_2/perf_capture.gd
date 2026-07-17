extends Control
## Visible-window V2.2 map/life-loop performance acceptance harness.

const MAIN_SCENE := preload(
	"res://scenes/v2_2/v2_2_life_loop_main.tscn"
)
const ARTIFACT_DIRECTORY := "res://artifacts/v2_2_life_loop_review"
const DRAG_SECONDS: float = 20.0

var _view: V2LifeLoopMain
var _csv_lines: PackedStringArray = PackedStringArray()
var _scenario_summaries: Array[Dictionary] = []
var _memory_start_mib: float = 0.0
var _memory_max_mib: float = 0.0
var _initial_hour: int = 0


func _ready() -> void:
	get_viewport().content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ARTIFACT_DIRECTORY)
	)
	_csv_lines.append(
		"scenario,frame,frame_ms,fps_monitor,process_ms,memory_mib,"
		+ "draw_calls,draw_primitives"
	)
	_view = MAIN_SCENE.instantiate() as V2LifeLoopMain
	add_child(_view)
	_run_capture.call_deferred()


func _run_capture() -> void:
	await _wait_frames(14)
	if _view.life_simulation == null or not _view.life_simulation.initialized:
		push_error("V2.2 visible performance scene did not initialize")
		get_tree().quit(1)
		return
	_initial_hour = _view.life_simulation.clock.total_hours
	_memory_start_mib = _memory_mib()
	_memory_max_mib = _memory_start_mib
	_view.interface.close_top_layer()
	_view.map_canvas.focus_player_location()
	await _wait_frames(8)
	await _save_screenshot("27_96x_paused_performance")
	await _measure_drag("paused_96x_drag_20s", DRAG_SECONDS)

	_view.life_binding.set_speed(1)
	await _measure_drag("running_1x_96x_drag_20s", DRAG_SECONDS)

	_view.life_binding.set_speed(8)
	await _save_screenshot("27_96x_8x_performance")
	await _measure_drag("running_8x_96x_drag_20s", DRAG_SECONDS)

	_view.interface.open_panel_named("character", false)
	_view.map_canvas.focus_player_location()
	await _wait_frames(6)
	await _save_screenshot("27_96x_8x_character_panel")
	await _measure_drag(
		"running_8x_character_panel_96x_drag_20s", DRAG_SECONDS
	)
	_view.interface.close_panel(false)

	_view.interface.set_review_mode(true)
	_view.interface.set_identity("official")
	_view.map_canvas.focus_player_location()
	await _wait_frames(6)
	await _save_screenshot("27_96x_8x_albert")
	await _measure_drag(
		"running_8x_albert_96x_drag_20s", DRAG_SECONDS
	)
	_view.interface.set_identity("worker")

	await _run_until_30_days()
	await _save_screenshot("28_30_day_map_performance")
	await _measure_drag("post_30_day_96x_drag_20s", DRAG_SECONDS)
	await _measure_rapid_zoom()
	await _write_results()
	print(
		"V2_2_PERF_CAPTURE_COMPLETE current=%s memory_delta_mib=%.4f"
		% [
			V2DateTime.iso_from_total_hour(
				_view.life_simulation.clock.total_hours
			),
			_memory_mib() - _memory_start_mib,
		]
	)
	await _wait_frames(4)
	get_tree().quit(0)


func _run_until_30_days() -> void:
	var target_hour: int = _initial_hour + 720
	_view.life_binding.set_speed(8)
	while _view.life_simulation.clock.total_hours < target_hour:
		await get_tree().process_frame
		_track_memory()
	_view.life_binding.set_paused(true)
	print(
		"V2_2_VISIBLE_30_DAY_REACHED %s ledger=%s"
		% [
			V2DateTime.iso_from_total_hour(
				_view.life_simulation.clock.total_hours
			),
			_view.life_simulation.ledger_consistency().success,
		]
	)


func _measure_drag(scenario: String, duration_seconds: float) -> void:
	_view.map_canvas.debug_reset_performance_metrics()
	_view.map_canvas.begin_camera_interaction()
	var samples: Array[Dictionary] = []
	var started_usec: int = Time.get_ticks_usec()
	var previous_frame_usec: int = started_usec
	var frame_index: int = 0
	while (
		float(Time.get_ticks_usec() - started_usec) / 1000000.0
		< duration_seconds
	):
		var horizontal: float = -1.0 if frame_index % 120 >= 60 else 1.0
		var vertical: float = -1.0 if frame_index % 84 >= 42 else 1.0
		_view.map_canvas.pan_by(
			Vector2(1.8 * horizontal, 1.3 * vertical)
		)
		await get_tree().process_frame
		var now_usec: int = Time.get_ticks_usec()
		var frame_ms: float = float(now_usec - previous_frame_usec) / 1000.0
		previous_frame_usec = now_usec
		samples.append(_sample_frame(scenario, frame_index, frame_ms))
		frame_index += 1
		_track_memory()
	_view.map_canvas.end_camera_interaction()
	await get_tree().process_frame
	_finish_scenario(scenario, samples)


func _measure_rapid_zoom() -> void:
	const SCENARIO: String = "post_30_day_rapid_zoom_100"
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
		samples.append(
			_sample_frame(SCENARIO, operation_index, frame_ms)
		)
		_track_memory()
	_finish_scenario(SCENARIO, samples)


func _sample_frame(
	scenario: String, frame_index: int, frame_ms: float
) -> Dictionary:
	var sample: Dictionary = {
		"scenario": scenario,
		"frame": frame_index,
		"frame_ms": frame_ms,
		"fps_monitor": float(
			Performance.get_monitor(Performance.TIME_FPS)
		),
		"process_ms": float(
			Performance.get_monitor(Performance.TIME_PROCESS)
		) * 1000.0,
		"memory_mib": _memory_mib(),
		"draw_calls": int(
			Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
			)
		),
		"draw_primitives": int(
			Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
			)
		),
	}
	_csv_lines.append(
		"%s,%d,%.4f,%.2f,%.4f,%.4f,%d,%d"
		% [
			scenario,
			frame_index,
			frame_ms,
			float(sample["fps_monitor"]),
			float(sample["process_ms"]),
			float(sample["memory_mib"]),
			int(sample["draw_calls"]),
			int(sample["draw_primitives"]),
		]
	)
	return sample


func _finish_scenario(
	scenario: String, samples: Array[Dictionary]
) -> void:
	var frame_values: Array[float] = []
	var process_values: Array[float] = []
	var memory_values: Array[float] = []
	for sample: Dictionary in samples:
		frame_values.append(float(sample["frame_ms"]))
		process_values.append(float(sample["process_ms"]))
		memory_values.append(float(sample["memory_mib"]))
	var map_snapshot: Dictionary = (
		_view.map_canvas.debug_performance_snapshot()
	)
	var map_draw_values: Array[float] = []
	for raw_value: Variant in map_snapshot.get("draw_ms_samples", []):
		map_draw_values.append(float(raw_value))
	var average_frame_ms: float = _average(frame_values)
	var summary: Dictionary = {
		"scenario": scenario,
		"frames": samples.size(),
		"average_fps": (
			1000.0 / average_frame_ms
			if average_frame_ms > 0.0 else 0.0
		),
		"frame_ms_average": average_frame_ms,
		"frame_ms_p95": _percentile(frame_values, 0.95),
		"frame_ms_p99": _percentile(frame_values, 0.99),
		"frame_ms_max": _maximum(frame_values),
		"process_ms_average": _average(process_values),
		"process_ms_p95": _percentile(process_values, 0.95),
		"map_draw_ms_average": _average(map_draw_values),
		"map_draw_ms_p95": _percentile(map_draw_values, 0.95),
		"memory_mib_start": (
			memory_values[0] if not memory_values.is_empty() else 0.0
		),
		"memory_mib_end": (
			memory_values[-1] if not memory_values.is_empty() else 0.0
		),
		"map_metrics": map_snapshot,
	}
	_scenario_summaries.append(summary)
	print(
		"V2_2_PERF %s avg_fps=%.2f p95=%.3f max=%.3f"
		% [
			scenario,
			float(summary["average_fps"]),
			float(summary["frame_ms_p95"]),
			float(summary["frame_ms_max"]),
		]
	)


func _save_screenshot(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [ARTIFACT_DIRECTORY, stem]
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Unable to save V2.2 performance screenshot: %s" % path)


func _write_results() -> void:
	var csv_path: String = "%s/v2_2_visible_performance.csv" % (
		ARTIFACT_DIRECTORY
	)
	var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		push_error("Unable to write V2.2 performance CSV")
		return
	csv_file.store_string("\n".join(_csv_lines) + "\n")
	csv_file.close()
	var result: Dictionary = {
		"record_type": "v2_2_visible_window_performance",
		"engine_version": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [1280, 720],
		"map_maximum_zoom": _view.map_canvas.get_maximum_zoom(),
		"visible_30_day_target": V2DateTime.iso_from_total_hour(
			_initial_hour + 720
		),
		"final_datetime": V2DateTime.iso_from_total_hour(
			_view.life_simulation.clock.total_hours
		),
		"ledger_consistent": (
			_view.life_simulation.ledger_consistency().success
		),
		"memory_mib_start": _memory_start_mib,
		"memory_mib_end": _memory_mib(),
		"memory_mib_max": _memory_max_mib,
		"memory_mib_delta": _memory_mib() - _memory_start_mib,
		"scenarios": _scenario_summaries,
	}
	var summary_file := FileAccess.open(
		"%s/v2_2_visible_performance.json" % ARTIFACT_DIRECTORY,
		FileAccess.WRITE
	)
	if summary_file == null:
		push_error("Unable to write V2.2 performance JSON")
		return
	summary_file.store_string(JSON.stringify(result, "\t", false))
	summary_file.close()


func _track_memory() -> void:
	_memory_max_mib = maxf(_memory_max_mib, _memory_mib())


func _memory_mib() -> float:
	return float(
		Performance.get_monitor(Performance.MEMORY_STATIC)
	) / 1048576.0


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
