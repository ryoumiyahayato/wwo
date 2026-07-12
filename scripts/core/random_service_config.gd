class_name RandomServiceConfig
extends RefCounted
## Loads the project default seed without coupling random generation to file access.

const DEFAULT_PATH: String = "res://data/balance/random_service.json"

var default_seed: int = 19000101
var error_message: String = ""


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	error_message = ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "无法读取随机配置：%s" % path
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		error_message = "随机配置 JSON 无效（第 %d 行）：%s" % [
			parser.get_error_line(), parser.get_error_message()
		]
		return parse_error
	if not parser.data is Dictionary:
		error_message = "随机配置顶层必须是对象"
		return ERR_INVALID_DATA
	var data: Dictionary = parser.data as Dictionary
	if not data.has("default_seed") or (
		not data["default_seed"] is int and not data["default_seed"] is float
	):
		error_message = "随机配置缺少整数 default_seed"
		return ERR_INVALID_DATA
	var numeric_seed: float = float(data["default_seed"])
	if numeric_seed != floor(numeric_seed):
		error_message = "default_seed 必须是整数"
		return ERR_INVALID_DATA
	default_seed = int(numeric_seed)
	return OK

