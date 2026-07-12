class_name SimulationClock
extends RefCounted
## Authoritative discrete game clock. Rendering delta is converted to whole game hours;
## all calendar state and scheduled events advance only through this service.

signal hour_advanced(total_hours: int)
signal day_advanced(year: int, month: int, day: int)
signal week_advanced(week_index: int)
signal month_advanced(year: int, month: int)
signal scheduled_event_due(event_id: String, due_hour: int, payload: Dictionary)
signal time_changed(snapshot: Dictionary)
signal pause_changed(is_paused: bool)
signal speed_changed(multiplier: int)

const HOURS_PER_DAY: int = 24
const HOURS_PER_WEEK: int = 168
const ACCUMULATOR_EPSILON: float = 0.000000001

var year: int
var month: int
var day: int
var hour: int
var total_hours: int = 0
var is_paused: bool = true
var speed_multiplier: int = 1

var _config: SimulationClockConfig
var _real_seconds_accumulator: float = 0.0
var _event_queue := SimulationEventQueue.new()


func _init(config: SimulationClockConfig) -> void:
	_config = config
	year = config.start_year
	month = config.start_month
	day = config.start_day
	hour = config.start_hour
	speed_multiplier = config.allowed_speed_multipliers[0]


func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	pause_changed.emit(is_paused)


func set_speed(multiplier: int) -> bool:
	if not _config.allowed_speed_multipliers.has(multiplier):
		return false
	if speed_multiplier == multiplier:
		return true
	speed_multiplier = multiplier
	speed_changed.emit(speed_multiplier)
	return true


func get_allowed_speeds() -> Array[int]:
	return _config.allowed_speed_multipliers.duplicate()


func advance_real_seconds(delta_seconds: float) -> int:
	if is_paused or delta_seconds <= 0.0:
		return 0
	_real_seconds_accumulator += delta_seconds * float(speed_multiplier)
	var hour_seconds: float = _config.real_seconds_per_game_hour
	var whole_hours: int = int(floor(
		(_real_seconds_accumulator + ACCUMULATOR_EPSILON) / hour_seconds
	))
	if whole_hours <= 0:
		return 0
	_real_seconds_accumulator -= float(whole_hours) * hour_seconds
	if _real_seconds_accumulator < 0.0 and _real_seconds_accumulator > -ACCUMULATOR_EPSILON:
		_real_seconds_accumulator = 0.0
	advance_hours(whole_hours)
	return whole_hours


func step_one_hour() -> void:
	advance_hours(1)


func advance_hours(hour_count: int) -> void:
	if hour_count <= 0:
		return
	for _index: int in range(hour_count):
		_advance_one_hour()
	time_changed.emit(get_snapshot())


func schedule_event_in_hours(
	event_id: String,
	hours_from_now: int,
	payload: Dictionary = {}
) -> bool:
	if hours_from_now < 1:
		return false
	return _event_queue.schedule_event(event_id, total_hours + hours_from_now, payload)


func cancel_scheduled_event(event_id: String) -> bool:
	return _event_queue.cancel_event(event_id)


func get_scheduled_event_count() -> int:
	return _event_queue.size()


func get_real_seconds_remainder() -> float:
	return _real_seconds_accumulator


func get_snapshot() -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"total_hours": total_hours,
		"is_paused": is_paused,
		"speed_multiplier": speed_multiplier,
	}


func get_persistent_state() -> Dictionary:
	var state: Dictionary = get_snapshot()
	state["real_seconds_remainder"] = _real_seconds_accumulator
	state["event_queue"] = _event_queue.get_state()
	return state


func restore_persistent_state(state: Dictionary) -> bool:
	var restored_year: int = int(state.get("year", 0))
	var restored_month: int = int(state.get("month", 0))
	var restored_day: int = int(state.get("day", 0))
	var restored_hour: int = int(state.get("hour", -1))
	var restored_total_hours: int = int(state.get("total_hours", -1))
	var restored_speed: int = int(state.get("speed_multiplier", 0))
	var remainder: float = float(state.get("real_seconds_remainder", 0.0))
	if restored_year < _config.start_year or restored_month < 1 or restored_month > 12:
		return false
	if restored_day < 1 or restored_day > _days_in_month(restored_year, restored_month):
		return false
	if restored_hour < 0 or restored_hour >= HOURS_PER_DAY or restored_total_hours < 0:
		return false
	if not _config.allowed_speed_multipliers.has(restored_speed):
		return false
	if remainder < 0.0 or remainder >= _config.real_seconds_per_game_hour:
		return false
	var queue_state: Variant = state.get("event_queue", {})
	if not queue_state is Dictionary:
		return false
	var restored_queue := SimulationEventQueue.new()
	if not restored_queue.restore_state(queue_state as Dictionary):
		return false
	year = restored_year
	month = restored_month
	day = restored_day
	hour = restored_hour
	total_hours = restored_total_hours
	is_paused = bool(state.get("is_paused", true))
	speed_multiplier = restored_speed
	_real_seconds_accumulator = remainder
	_event_queue = restored_queue
	time_changed.emit(get_snapshot())
	pause_changed.emit(is_paused)
	speed_changed.emit(speed_multiplier)
	return true


func set_datetime_for_debug(target_year: int, target_month: int, target_day: int, target_hour: int) -> bool:
	if target_year < _config.start_year or target_month < 1 or target_month > 12 or target_hour < 0 or target_hour >= HOURS_PER_DAY:
		return false
	if target_day < 1 or target_day > _days_in_month(target_year, target_month):
		return false
	var computed_hours: int = 0
	for calendar_year: int in range(_config.start_year, target_year):
		computed_hours += (366 if _is_leap_year(calendar_year) else 365) * HOURS_PER_DAY
	for calendar_month: int in range(1, target_month):
		computed_hours += _days_in_month(target_year, calendar_month) * HOURS_PER_DAY
	computed_hours += (target_day - 1) * HOURS_PER_DAY + target_hour
	year = target_year
	month = target_month
	day = target_day
	hour = target_hour
	total_hours = computed_hours
	_real_seconds_accumulator = 0.0
	_event_queue.clear()
	time_changed.emit(get_snapshot())
	return true


func _advance_one_hour() -> void:
	total_hours += 1
	var crossed_day: bool = false
	var crossed_month: bool = false

	hour += 1
	if hour >= HOURS_PER_DAY:
		hour = 0
		day += 1
		crossed_day = true
		if day > _days_in_month(year, month):
			day = 1
			month += 1
			crossed_month = true
			if month > 12:
				month = 1
				year += 1

	hour_advanced.emit(total_hours)
	if crossed_day:
		day_advanced.emit(year, month, day)
		if total_hours % HOURS_PER_WEEK == 0:
			week_advanced.emit(int(total_hours / HOURS_PER_WEEK))
		if crossed_month:
			month_advanced.emit(year, month)

	var due_events: Array[Dictionary] = _event_queue.pop_due_events(total_hours)
	for event: Dictionary in due_events:
		scheduled_event_due.emit(
			str(event["id"]),
			int(event["due_hour"]),
			(event["payload"] as Dictionary).duplicate(true)
		)


static func _days_in_month(target_year: int, target_month: int) -> int:
	match target_month:
		2:
			return 29 if _is_leap_year(target_year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


static func _is_leap_year(target_year: int) -> bool:
	return target_year % 400 == 0 or (
		target_year % 4 == 0 and target_year % 100 != 0
	)
