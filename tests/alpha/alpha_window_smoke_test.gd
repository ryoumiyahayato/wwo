extends SceneTree
## Visible-window smoke test. This is intentionally excluded from headless validation.

const MAIN_SCENE: String = "res://scenes/alpha/alpha_main.tscn"
const SAMPLE_SECONDS: float = 8.0
const REQUIRED_SIZE := Vector2i(1280, 720)
const MINIMUM_AVERAGE_FPS: float = 30.0

var _sample_started_usec: int = 0
var _sample_frames: int = 0


func _initialize() -> void:
	set_meta(AlphaMain.LAUNCH_MODE_META, "new")
	set_meta(AlphaMain.REVIEW_STATE_META, "employed_worker")
	set_meta(AlphaMain.DEVELOPER_META, false)
	var error: Error = change_scene_to_file(MAIN_SCENE)
	if error != OK:
		push_error("WINDOW_SMOKE scene_load_failed=%s" % error_string(error))
		quit(1)


func _process(_delta: float) -> bool:
	if current_scene == null or not current_scene is AlphaMain:
		return false
	if _sample_started_usec == 0:
		_sample_started_usec = Time.get_ticks_usec()
		_sample_frames = 0
		return false
	_sample_frames += 1
	var elapsed_seconds: float = (
		float(Time.get_ticks_usec() - _sample_started_usec) / 1_000_000.0
	)
	if elapsed_seconds < SAMPLE_SECONDS:
		return false
	var average_fps: float = float(_sample_frames) / elapsed_seconds
	var window_size: Vector2i = DisplayServer.window_get_size()
	var passed: bool = (
		window_size == REQUIRED_SIZE
		and average_fps >= MINIMUM_AVERAGE_FPS
	)
	print(
		"ALPHA_WINDOW_SMOKE size=%dx%d average_fps=%.2f frames=%d seconds=%.3f result=%s"
		% [
			window_size.x,
			window_size.y,
			average_fps,
			_sample_frames,
			elapsed_seconds,
			"PASS" if passed else "FAIL",
		]
	)
	quit(0 if passed else 1)
	return true
