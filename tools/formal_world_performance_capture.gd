extends Node
## Observational visible-window benchmark for the normal formal-world product.
## Wall-clock samples never enter authoritative simulation or save state.

const MENU_SCENE := preload("res://scenes/formal/formal_world_menu.tscn")
const WORLD_SCENE := preload("res://scenes/formal/formal_world_main.tscn")
const OUTPUT_DIRECTORY := "res://artifacts/formal_world_performance"
const STANDARD_SECONDS: float = 6.0
const ACTIVE_4X_SECONDS: float = 13.0
const SCENARIO_FILTER: String = "WWO_PERF_SCENARIO"

var _summaries: Array[Dictionary] = []
var _memory_max_mib: float = 0.0


func _ready() -> void:
	get_viewport().content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	_run.call_deferred()


func _run() -> void:
	var menu := MENU_SCENE.instantiate() as Control
	add_child(menu)
	await _wait_frames(12)
	await _measure("title_idle", STANDARD_SECONDS, Callable())
	menu.queue_free()
	await _wait_frames(3)

	var world := WORLD_SCENE.instantiate() as FormalWorldApplication
	add_child(world)
	await _wait_frames(20)
	if not world.formal_simulation.initialized:
		push_error("Formal performance capture could not initialize the formal world")
		get_tree().quit(1)
		return
	world.sim_paused = true
	world.economy_panel_open = false
	world.queue_redraw()
	await _measure("global_map_paused", STANDARD_SECONDS, Callable(), world)
	await _measure("global_map_pan_zoom", STANDARD_SECONDS, Callable(self, "_pan_zoom_frame").bind(world), world)
	if OS.get_environment(SCENARIO_FILTER) == "pan_zoom_only":
		await _write_results(world)
		print("FORMAL_PERFORMANCE_CAPTURE_COMPLETE")
		world.queue_free()
		await _wait_frames(3)
		get_tree().quit(0)
		return

	world.selected_country_id = "country_fra"
	world.queue_redraw()
	await _measure("selected_polity_paused", STANDARD_SECONDS, Callable(), world)
	world.economy_panel_open = true
	world.queue_redraw()
	await _measure("economy_panel_open", STANDARD_SECONDS, Callable(), world)

	for speed: int in [1, 2, 4]:
		world.sim_speed = speed
		world.sim_paused = false
		world.queue_redraw()
		await _measure(
			"simulation_%dx" % speed,
			ACTIVE_4X_SECONDS if speed == 4 else STANDARD_SECONDS,
			Callable(),
			world
		)
	world.sim_paused = true
	world.selected_country_id = "german_empire"
	world.call("_focus_selected_country")
	world.call("_enter_region")
	world.queue_redraw()
	await _measure("polity_admin_view", STANDARD_SECONDS, Callable(), world)
	world.call("_return_to_global_world")
	world.queue_redraw()
	await _wait_frames(4)

	var save_started := Time.get_ticks_usec()
	var save_result := world.formal_simulation.save_to_user()
	var save_usec := Time.get_ticks_usec() - save_started
	var load_started := Time.get_ticks_usec()
	var load_result := world.formal_simulation.load_from_user()
	var load_usec := Time.get_ticks_usec() - load_started
	_summaries.append({
		"scenario": "save_load_operation",
		"save_success": save_result.success,
		"load_success": load_result.success,
		"save_ms": float(save_usec) / 1000.0,
		"load_ms": float(load_usec) / 1000.0,
	})
	await _write_results(world)
	print("FORMAL_PERFORMANCE_CAPTURE_COMPLETE")
	world.queue_free()
	await _wait_frames(3)
	get_tree().quit(0)


func _measure(
	scenario: String,
	duration_seconds: float,
	per_frame: Callable = Callable(),
	world: FormalWorldApplication = null
) -> void:
	if world != null:
		world.debug_reset_performance_metrics()
	var frames: Array[float] = []
	var process_times: Array[float] = []
	var physics_times: Array[float] = []
	var draw_calls: Array[float] = []
	var objects: Array[float] = []
	var memory_start := _memory_mib()
	var previous_usec := Time.get_ticks_usec()
	var started_usec := previous_usec
	var frame_index := 0
	while float(Time.get_ticks_usec() - started_usec) / 1_000_000.0 < duration_seconds:
		if per_frame.is_valid():
			per_frame.call(frame_index)
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		frames.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		process_times.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		physics_times.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		_memory_max_mib = maxf(_memory_max_mib, _memory_mib())
		frame_index += 1
	var average_ms := _average(frames)
	var summary: Dictionary = {
		"scenario": scenario,
		"sample_seconds": duration_seconds,
		"frames": frames.size(),
		"average_fps": 1000.0 / average_ms if average_ms > 0.0 else 0.0,
		"one_percent_low_fps": 1000.0 / _percentile(frames, 0.99) if not frames.is_empty() else 0.0,
		"frame_ms_average": average_ms,
		"frame_ms_p95": _percentile(frames, 0.95),
		"frame_ms_p99": _percentile(frames, 0.99),
		"frame_ms_max": _maximum(frames),
		"process_ms_average": _average(process_times),
		"process_ms_p95": _percentile(process_times, 0.95),
		"physics_ms_average": _average(physics_times),
		"draw_calls_average": _average(draw_calls),
		"draw_calls_max": _maximum(draw_calls),
		"rendered_objects_average": _average(objects),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"memory_mib_start": memory_start,
		"memory_mib_end": _memory_mib(),
	}
	if world != null:
		summary["map_metrics"] = world.debug_performance_snapshot()
	_summaries.append(summary)
	print("FORMAL_PERF %s avg_fps=%.2f p99=%.3f max=%.3f process=%.3f" % [
		scenario,
		float(summary["average_fps"]),
		float(summary["frame_ms_p99"]),
		float(summary["frame_ms_max"]),
		float(summary["process_ms_average"]),
	])


func _pan_zoom_frame(frame_index: int, world: FormalWorldApplication) -> void:
	world.yaw += 0.004 if frame_index % 160 < 80 else -0.004
	if frame_index % 45 == 0:
		var direction := 1.0 if frame_index % 90 == 0 else -1.0
		world.call("_set_world_zoom", world.world_zoom * (1.04 if direction > 0.0 else 0.96))
	world.call("_mark_projection_dirty")
	world.queue_redraw()


func _write_results(world: FormalWorldApplication) -> void:
	var result := {
		"record_type": "formal_world_visible_performance_v1",
		"audited_sha": OS.get_environment("WWO_AUDITED_SHA"),
		"engine_version": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"viewport": [get_viewport().size.x, get_viewport().size.y],
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"debug_build": OS.is_debug_build(),
		"memory_mib_max": _memory_max_mib,
		"final_total_minutes": world.formal_simulation.total_minutes,
		"scenarios": _summaries,
	}
	var path := "%s/formal_world_visible_performance.json" % OUTPUT_DIRECTORY
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write formal performance result")
		return
	file.store_string(JSON.stringify(result, "\t", false))
	file.close()


func _memory_mib() -> float:
	return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _average(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var total := 0.0
	for value: float in values: total += value
	return total / float(values.size())


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value: float in values: result = maxf(result, value)
	return result


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(int(ceil(float(ordered.size()) * ratio)) - 1, 0, ordered.size() - 1)]
