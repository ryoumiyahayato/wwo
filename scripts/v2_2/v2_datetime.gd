class_name V2DateTime
extends RefCounted
## Gregorian conversion for authoritative hours since 1900-01-01 00:00.

const START_YEAR: int = 1900
const WEEKDAY_NAMES: PackedStringArray = [
	"星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日",
]


static func from_total_hour(total_hour: int) -> Dictionary:
	if total_hour < 0:
		return {}
	var remaining_days: int = total_hour / 24
	var result_hour: int = posmod(total_hour, 24)
	var result_year: int = START_YEAR
	while true:
		var year_days: int = 366 if is_leap_year(result_year) else 365
		if remaining_days < year_days:
			break
		remaining_days -= year_days
		result_year += 1
	var result_month: int = 1
	while remaining_days >= days_in_month(result_year, result_month):
		remaining_days -= days_in_month(result_year, result_month)
		result_month += 1
	var result_day: int = remaining_days + 1
	var absolute_day: int = absolute_day_index(result_year, result_month, result_day)
	return {
		"year": result_year,
		"month": result_month,
		"day": result_day,
		"hour": result_hour,
		"weekday": posmod(absolute_day, 7),
	}


static func to_total_hour(value: Dictionary) -> int:
	var year: int = int(value.get("year", 0))
	var month: int = int(value.get("month", 0))
	var day: int = int(value.get("day", 0))
	var hour: int = int(value.get("hour", -1))
	if (
		year < START_YEAR
		or month < 1
		or month > 12
		or day < 1
		or day > days_in_month(year, month)
		or hour < 0
		or hour > 23
	):
		return -1
	var start_day: int = absolute_day_index(START_YEAR, 1, 1)
	var target_day: int = absolute_day_index(year, month, day)
	return (target_day - start_day) * 24 + hour


static func parse_iso(value: String) -> Dictionary:
	if value.length() != 19:
		return {}
	if (
		value.substr(4, 1) != "-"
		or value.substr(7, 1) != "-"
		or value.substr(10, 1) != "T"
		or value.substr(13, 1) != ":"
		or value.substr(16, 1) != ":"
	):
		return {}
	var year_text: String = value.substr(0, 4)
	var month_text: String = value.substr(5, 2)
	var day_text: String = value.substr(8, 2)
	var hour_text: String = value.substr(11, 2)
	var minute_text: String = value.substr(14, 2)
	var second_text: String = value.substr(17, 2)
	for component: String in [
		year_text, month_text, day_text, hour_text, minute_text, second_text,
	]:
		if not component.is_valid_int():
			return {}
	if minute_text != "00" or second_text != "00":
		return {}
	var parsed: Dictionary = {
		"year": int(year_text),
		"month": int(month_text),
		"day": int(day_text),
		"hour": int(hour_text),
	}
	var total_hour: int = to_total_hour(parsed)
	if total_hour < 0:
		return {}
	parsed["weekday"] = int(from_total_hour(total_hour).get("weekday", -1))
	return parsed


static func total_hour_from_iso(value: String) -> int:
	var parsed: Dictionary = parse_iso(value)
	return -1 if parsed.is_empty() else to_total_hour(parsed)


static func iso_from_total_hour(total_hour: int) -> String:
	var value: Dictionary = from_total_hour(total_hour)
	if value.is_empty():
		return ""
	return "%04d-%02d-%02dT%02d:00:00" % [
		int(value["year"]), int(value["month"]), int(value["day"]), int(value["hour"]),
	]


static func date_from_total_hour(total_hour: int) -> String:
	var value: Dictionary = from_total_hour(total_hour)
	if value.is_empty():
		return ""
	return "%04d-%02d-%02d" % [
		int(value["year"]), int(value["month"]), int(value["day"]),
	]


static func display_from_total_hour(total_hour: int) -> String:
	var value: Dictionary = from_total_hour(total_hour)
	if value.is_empty():
		return "无效时间"
	return "%04d年%d月%d日 %s %02d:00" % [
		int(value["year"]),
		int(value["month"]),
		int(value["day"]),
		WEEKDAY_NAMES[int(value["weekday"])],
		int(value["hour"]),
	]


static func week_id(total_hour: int) -> String:
	var value: Dictionary = from_total_hour(total_hour)
	if value.is_empty():
		return ""
	var year: int = int(value["year"])
	var day_of_year: int = 0
	for month: int in range(1, int(value["month"])):
		day_of_year += days_in_month(year, month)
	day_of_year += int(value["day"])
	var january_first_weekday: int = posmod(absolute_day_index(year, 1, 1), 7)
	var week_number: int = ((day_of_year - 1 + january_first_weekday) / 7) + 1
	return "%04d-W%02d" % [year, week_number]


static func next_month_hour(total_hour: int, day: int, hour: int) -> int:
	var value: Dictionary = from_total_hour(total_hour)
	if value.is_empty() or day < 1 or hour < 0 or hour > 23:
		return -1
	var year: int = int(value["year"])
	var month: int = int(value["month"]) + 1
	if month > 12:
		month = 1
		year += 1
	return to_total_hour({
		"year": year,
		"month": month,
		"day": mini(day, days_in_month(year, month)),
		"hour": hour,
	})


static func absolute_day_index(year: int, month: int, day: int) -> int:
	var previous_year: int = year - 1
	var days: int = (
		previous_year * 365
		+ floori(float(previous_year) / 4.0)
		- floori(float(previous_year) / 100.0)
		+ floori(float(previous_year) / 400.0)
	)
	for calendar_month: int in range(1, month):
		days += days_in_month(year, calendar_month)
	return days + day - 1


static func days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		1, 3, 5, 7, 8, 10, 12:
			return 31
		_:
			return 0


static func is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
