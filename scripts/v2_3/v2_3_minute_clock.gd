class_name V23MinuteClock
extends SimulationClock
## Minute-authoritative clock for the formal V2.3 world.
## Existing hourly services remain connected to hour_advanced and settle only when
## this clock crosses a whole-hour boundary.

signal minute_advanced(total_minutes: int)

const REAL_SECONDS_PER_TICK: float = 0.1
const MINUTES_PER_SPEED: Dictionary = {
	1: 1,
	2: 5,
	3: 10,
	4: 20,
	5: 60,
}
const TICK_EPSILON: float = 0.000000001

var minute: int = 0
var total_minutes: int = 0
var _tick_seconds_remainder: float = 0.0


func _init(config: SimulationClockConfig) -> void:
	super(config)
	minute = 0
	total_minutes = total_hours * 60
	if speed_multiplier not in MINUTES_PER_SPEED:
		speed_multiplier = 1


func set_speed(multiplier: int) -> bool:
	if not MINUTES_PER_SPEED.has(multiplier):
		return false
	if speed_multiplier == multiplier:
		return true
	speed_multiplier = multiplier
	speed_changed.emit(speed_multiplier)
	return true


func get_allowed_speeds() -> Array[int]:
	return [1, 2, 3, 4, 5]


func minutes_per_tick() -> int:
	return int(MINUTES_PER_SPEED.get(speed_multiplier, 1))


func advance_real_seconds(delta_seconds: float) -> int:
	if is_paused or delta_seconds <= 0.0:
		return 0
	var previous_hour: int = total_hours
	_tick_seconds_remainder += delta_seconds
	var whole_ticks: int = int(floor(
		(_tick_seconds_remainder + TICK_EPSILON) / REAL_SECONDS_PER_TICK
	))
	if whole_ticks <= 0:
		return 0
	_tick_seconds_remainder -= float(whole_ticks) * REAL_SECONDS_PER_TICK
	if (
		_tick_seconds_remainder < 0.0
		and _tick_seconds_remainder > -TICK_EPSILON
	):
		_tick_seconds_remainder = 0.0
	advance_minutes(whole_ticks * minutes_per_tick())
	return total_hours - previous_hour


func advance_minutes(minute_count: int) -> void:
	if minute_count <= 0:
		return
	var crossed_hour: bool = false
	for _index: int in range(minute_count):
		minute += 1
		total_minutes += 1
		minute_advanced.emit(total_minutes)
		if minute < 60:
			continue
		minute = 0
		crossed_hour = true
		super.advance_hours(1)
	if not crossed_hour:
		time_changed.emit(get_snapshot())


func step_one_hour() -> void:
	advance_minutes(60)


func advance_hours(hour_count: int) -> void:
	if hour_count <= 0:
		return
	if minute != 0:
		# Interactive time can be between hour boundaries; preserve the exact
		# minute and the per-minute presentation signal in that case.
		advance_minutes(hour_count * 60)
		return
	# Offline day/year simulation has no minute-level social work. Advancing
	# through 60 presentation ticks per hour would make performance depend on
	# an unused signal frequency, so use the existing authoritative hourly
	# clock directly and publish one final minute snapshot.
	total_minutes += hour_count * 60
	super.advance_hours(hour_count)
	minute_advanced.emit(total_minutes)


func get_real_seconds_remainder() -> float:
	return _tick_seconds_remainder


func get_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_snapshot()
	snapshot["minute"] = minute
	snapshot["total_minutes"] = total_minutes
	snapshot["speed_level"] = speed_multiplier
	snapshot["game_minutes_per_tick"] = minutes_per_tick()
	snapshot["real_seconds_per_tick"] = REAL_SECONDS_PER_TICK
	return snapshot


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["minute"] = minute
	state["total_minutes"] = total_minutes
	state["minute_tick_seconds_remainder"] = _tick_seconds_remainder
	state["clock_resolution"] = "minute"
	return state


func restore_persistent_state(state: Dictionary) -> bool:
	var normalized: Dictionary = state.duplicate(true)
	var restored_speed: int = int(normalized.get("speed_multiplier", 1))
	if restored_speed not in MINUTES_PER_SPEED:
		# Old V2.3 saves used 1/2/4/8. Preserve their relative intent.
		restored_speed = {
			1: 1,
			2: 2,
			4: 4,
			8: 5,
		}.get(restored_speed, 1)
	normalized["speed_multiplier"] = restored_speed
	var base_remainder: float = float(
		normalized.get("real_seconds_remainder", 0.0)
	)
	if base_remainder < 0.0 or base_remainder >= 1.0:
		normalized["real_seconds_remainder"] = 0.0
	if not super.restore_persistent_state(normalized):
		return false
	var restored_minute: int = int(state.get("minute", 0))
	if restored_minute < 0 or restored_minute >= 60:
		return false
	var restored_total_minutes: int = int(
		state.get("total_minutes", total_hours * 60 + restored_minute)
	)
	if restored_total_minutes != total_hours * 60 + restored_minute:
		return false
	var tick_remainder: float = float(
		state.get("minute_tick_seconds_remainder", 0.0)
	)
	if tick_remainder < 0.0 or tick_remainder >= REAL_SECONDS_PER_TICK:
		return false
	minute = restored_minute
	total_minutes = restored_total_minutes
	_tick_seconds_remainder = tick_remainder
	time_changed.emit(get_snapshot())
	return true


func set_datetime_for_debug(
	target_year: int,
	target_month: int,
	target_day: int,
	target_hour: int
) -> bool:
	if not super.set_datetime_for_debug(
		target_year, target_month, target_day, target_hour
	):
		return false
	minute = 0
	total_minutes = total_hours * 60
	_tick_seconds_remainder = 0.0
	time_changed.emit(get_snapshot())
	return true
