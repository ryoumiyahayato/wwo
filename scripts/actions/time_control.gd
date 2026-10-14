class_name TimeControl
extends Node
## Scheduling preference only; elapsed game time belongs to GameClock.

signal advance_requested(minutes: int)
signal controls_changed
const MINUTES_PER_TICK: int = 15
var paused: bool = true
var speed: int = 1

func tick() -> void:
	if not paused:
		advance_requested.emit(MINUTES_PER_TICK * speed)

func toggle_pause() -> void:
	paused = not paused
	controls_changed.emit()

func set_speed(value: int) -> void:
	if value in [1, 2, 4]:
		speed = value
		paused = false
		controls_changed.emit()
