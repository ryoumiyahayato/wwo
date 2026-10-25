extends Node
## Display scheduling only. Never pauses the tree, physics or world clock.
signal low_activity_changed(low: bool)
const IDLE_SECONDS: float = 2.0
var _controller: GlobeController
var _inspection: Callable
var _busy: Callable
var _active_fps: int = 60
var _original_fps: int = 60
var _apply_limit: Callable
var _last_input_ms: int = 0
var _low: bool = false
var _enabled: bool = true

func configure(fps: int, enabled: bool, controller: GlobeController, inspection: Callable, busy: Callable, apply_limit: Callable) -> void:
	_active_fps = 30 if fps==30 else 60
	_enabled = enabled
	if OS.has_feature("editor") and "--idle-power-review-no-adaptation" in OS.get_cmdline_user_args(): _enabled=false
	_controller = controller; _inspection = inspection; _busy=busy; _apply_limit=apply_limit
	_original_fps = Engine.max_fps

func _ready() -> void:
	add_to_group("wwo_display_power")
	_last_input_ms = Time.get_ticks_msec()
	get_window().focus_entered.connect(wake)
	get_window().focus_exited.connect(_refresh)
	if _controller!=null: _controller.view_changed.connect(wake)
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_refresh)
	add_child(timer);timer.start()
	_refresh()

func set_preferences(fps: int, enabled: bool) -> void:
	_active_fps = 30 if fps==30 else 60
	_enabled = enabled
	wake()

func wake() -> void:
	_last_input_ms = Time.get_ticks_msec()
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch or event is InputEventScreenDrag:
		wake()

func _refresh() -> void:
	if not is_inside_tree(): return
	var window := get_window()
	var background := window.mode==Window.MODE_MINIMIZED or not window.has_focus()
	var moving := _controller!=null and _controller.camera_motion_active()
	moving = moving or (_busy.is_valid() and bool(_busy.call())) or not get_tree().get_processed_tweens().is_empty()
	var idle := Time.get_ticks_msec()-_last_input_ms>=int(IDLE_SECONDS*1000.0)
	var low := _enabled and (background or (idle and not moving))
	# Static maps/minimized windows already draw nothing. Keep their original
	# scheduling: the isolated 10 FPS candidate worsened first-interaction P1.
	var limit := _active_fps
	if _inspection.is_valid() and _inspection.call(): limit=mini(limit,30)
	_apply_limit.call(limit)
	if _low!=low:
		_low=low
		low_activity_changed.emit(low)

func _exit_tree() -> void:
	Engine.max_fps = _original_fps
