extends Control
## Presents read-only clock state and forwards explicit user commands to the clock.

const UiStrings = preload("res://scripts/ui/ui_strings.gd")

@onready var runner: SimulationRunner = %SimulationRunner
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var date_time_label: Label = %DateTimeLabel
@onready var status_label: Label = %StatusLabel
@onready var event_count_label: Label = %EventCountLabel
@onready var pause_button: Button = %PauseButton
@onready var step_button: Button = %StepButton
@onready var speed_1_button: Button = %Speed1Button
@onready var speed_2_button: Button = %Speed2Button
@onready var speed_4_button: Button = %Speed4Button
@onready var speed_8_button: Button = %Speed8Button
@onready var back_button: Button = %BackButton

var _clock: SimulationClock
var _hour_event_count: int = 0


func _ready() -> void:
	title_label.text = UiStrings.CLOCK_TITLE
	description_label.text = UiStrings.CLOCK_DESCRIPTION
	step_button.text = UiStrings.CLOCK_STEP
	back_button.text = UiStrings.CLOCK_BACK

	pause_button.pressed.connect(_on_pause_pressed)
	step_button.pressed.connect(_on_step_pressed)
	speed_1_button.pressed.connect(_on_speed_pressed.bind(1))
	speed_2_button.pressed.connect(_on_speed_pressed.bind(2))
	speed_4_button.pressed.connect(_on_speed_pressed.bind(4))
	speed_8_button.pressed.connect(_on_speed_pressed.bind(8))
	back_button.pressed.connect(_on_back_pressed)

	if runner.clock == null:
		_show_initialization_error()
		return
	_clock = runner.clock
	_clock.time_changed.connect(_on_time_changed)
	_clock.pause_changed.connect(_on_pause_changed)
	_clock.speed_changed.connect(_on_speed_changed)
	_clock.hour_advanced.connect(_on_hour_advanced)
	_refresh(_clock.get_snapshot())


func _show_initialization_error() -> void:
	date_time_label.text = UiStrings.CLOCK_CONFIG_ERROR
	status_label.text = runner.initialization_error
	pause_button.disabled = true
	step_button.disabled = true
	for button: Button in _get_speed_buttons():
		button.disabled = true


func _on_pause_pressed() -> void:
	_clock.set_paused(not _clock.is_paused)


func _on_step_pressed() -> void:
	_clock.set_paused(true)
	_clock.step_one_hour()


func _on_speed_pressed(multiplier: int) -> void:
	if _clock.set_speed(multiplier):
		_clock.set_paused(false)


func _on_back_pressed() -> void:
	var change_error: Error = get_tree().change_scene_to_file(
		"res://scenes/menu/main_menu.tscn"
	)
	if change_error != OK:
		LogService.error("ClockView", "无法返回主菜单：%s" % error_string(change_error))


func _on_time_changed(snapshot: Dictionary) -> void:
	_refresh(snapshot)


func _on_pause_changed(_paused: bool) -> void:
	_refresh(_clock.get_snapshot())


func _on_speed_changed(_multiplier: int) -> void:
	_refresh(_clock.get_snapshot())


func _on_hour_advanced(_total_hours: int) -> void:
	_hour_event_count += 1


func _refresh(snapshot: Dictionary) -> void:
	date_time_label.text = "%04d年%02d月%02d日 %02d:00" % [
		int(snapshot["year"]),
		int(snapshot["month"]),
		int(snapshot["day"]),
		int(snapshot["hour"]),
	]
	var current_speed: int = int(snapshot["speed_multiplier"])
	if bool(snapshot["is_paused"]):
		status_label.text = UiStrings.CLOCK_STATUS_PAUSED % current_speed
		pause_button.text = UiStrings.CLOCK_RESUME
	else:
		status_label.text = UiStrings.CLOCK_STATUS_RUNNING % current_speed
		pause_button.text = UiStrings.CLOCK_PAUSE
	event_count_label.text = UiStrings.CLOCK_EVENT_COUNT % _hour_event_count

	var speeds: Array[int] = [1, 2, 4, 8]
	var buttons: Array[Button] = _get_speed_buttons()
	for index: int in range(buttons.size()):
		buttons[index].button_pressed = speeds[index] == current_speed


func _get_speed_buttons() -> Array[Button]:
	return [speed_1_button, speed_2_button, speed_4_button, speed_8_button]

