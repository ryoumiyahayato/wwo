class_name GameClock
extends RefCounted
## Sole owner of elapsed Formal game minutes. No domain scheduling.

var _total_minutes: int = 0
var error: String = ""

func total_minutes() -> int:
	return _total_minutes

func current_hour() -> int:
	return int(_total_minutes / 60)

func current_day() -> int:
	return int(current_hour() / 24)

func current_date() -> Dictionary:
	var value := GameCalendar.from_total_hour(current_hour())
	value["minute"] = _total_minutes % 60
	return value

func advance_minutes(minutes: int) -> bool:
	if minutes < 0 or _total_minutes > 9223372036854775807 - minutes:
		error = "GAME CLOCK DATA ERROR: invalid advance %d at minute %d" % [minutes, _total_minutes]
		push_error(error)
		return false
	_total_minutes += minutes
	return true

func snapshot() -> Dictionary:
	return {"total_minutes": _total_minutes, "minute_remainder": _total_minutes % 60}

func restore(state: Dictionary) -> bool:
	if state.size() != 2 or typeof(state.get("total_minutes")) != TYPE_INT or typeof(state.get("minute_remainder")) != TYPE_INT:
		error = "GAME CLOCK DATA ERROR: invalid total_minutes / minute_remainder fields"
		push_error(error)
		return false
	var total: int = state["total_minutes"]
	var remainder: int = state["minute_remainder"]
	if total < 0 or remainder < 0 or remainder > 59 or total % 60 != remainder:
		error = "GAME CLOCK DATA ERROR: impossible time total_minutes=%d minute_remainder=%d" % [total, remainder]
		push_error(error)
		return false
	_total_minutes = total
	error = ""
	return true
