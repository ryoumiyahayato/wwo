class_name ContentDocument
extends RefCounted

static func read(path: String, errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("缺少数据：" + path)
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		errors.append("数据解析失败：" + path)
		return {}
	return parser.data as Dictionary
