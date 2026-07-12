class_name SimulationClockConfig
extends RefCounted
## Loads and validates the data-driven constants required by SimulationClock.

const DEFAULT_PATH: String = "res://data/balance/simulation_clock.json"

var start_year: int = 1900
var start_month: int = 1
var start_day: int = 1
var start_hour: int = 0
var real_seconds_per_game_hour: float = 1.0
var allowed_speed_multipliers: Array[int] = [1, 2, 4, 8]
var error_message: String = ""


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	error_message = ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "无法读取时间配置：%s" % path
		return FileAccess.get_open_error()

	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		error_message = "时间配置 JSON 无效（第 %d 行）：%s" % [
			parser.get_error_line(), parser.get_error_message()
		]
		return parse_error
	if not parser.data is Dictionary:
		error_message = "时间配置顶层必须是对象"
		return ERR_INVALID_DATA

	var data: Dictionary = parser.data as Dictionary
	var required_keys: PackedStringArray = [
		"start_year",
		"start_month",
		"start_day",
		"start_hour",
		"real_seconds_per_game_hour",
		"allowed_speed_multipliers",
	]
	for key: String in required_keys:
		if not data.has(key):
			error_message = "时间配置缺少字段：%s" % key
			return ERR_INVALID_DATA

	start_year = int(data["start_year"])
	start_month = int(data["start_month"])
	start_day = int(data["start_day"])
	start_hour = int(data["start_hour"])
	real_seconds_per_game_hour = float(data["real_seconds_per_game_hour"])

	if start_year < 1 or start_month < 1 or start_month > 12:
		error_message = "时间配置的起始年月无效"
		return ERR_INVALID_DATA
	if start_day < 1 or start_day > _days_in_month(start_year, start_month):
		error_message = "时间配置的起始日期无效"
		return ERR_INVALID_DATA
	if start_hour < 0 or start_hour > 23:
		error_message = "时间配置的起始小时无效"
		return ERR_INVALID_DATA
	if real_seconds_per_game_hour <= 0.0:
		error_message = "每游戏小时对应的现实秒数必须大于零"
		return ERR_INVALID_DATA
	if not data["allowed_speed_multipliers"] is Array:
		error_message = "允许速度必须是数组"
		return ERR_INVALID_DATA

	var parsed_speeds: Array[int] = []
	for raw_speed: Variant in data["allowed_speed_multipliers"] as Array:
		var speed: int = int(raw_speed)
		if speed <= 0 or parsed_speeds.has(speed):
			error_message = "允许速度必须为不重复的正整数"
			return ERR_INVALID_DATA
		parsed_speeds.append(speed)
	parsed_speeds.sort()
	if parsed_speeds.is_empty():
		error_message = "至少需要一个允许速度"
		return ERR_INVALID_DATA
	allowed_speed_multipliers = parsed_speeds
	return OK


static func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if _is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)

