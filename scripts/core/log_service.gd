class_name LogService
extends RefCounted
## Central logging service for project code.
## It depends only on Godot's console output and keeps log filtering out of UI code.

enum Level {
	DEBUG,
	INFO,
	WARNING,
	ERROR,
}

static var minimum_level: int = Level.INFO


static func set_minimum_level(level: int) -> void:
	minimum_level = clampi(level, Level.DEBUG, Level.ERROR)


static func should_log(level: int) -> bool:
	return level >= minimum_level


static func format_message(level_label: String, source: String, message: String) -> String:
	return "[%s] [%s] %s" % [level_label, source, message]


static func debug(source: String, message: String) -> void:
	_write(Level.DEBUG, "DEBUG", source, message)


static func info(source: String, message: String) -> void:
	_write(Level.INFO, "INFO", source, message)


static func warning(source: String, message: String) -> void:
	_write(Level.WARNING, "WARNING", source, message)


static func error(source: String, message: String) -> void:
	_write(Level.ERROR, "ERROR", source, message)


static func _write(level: int, level_label: String, source: String, message: String) -> void:
	if not should_log(level):
		return
	print(format_message(level_label, source, message))

