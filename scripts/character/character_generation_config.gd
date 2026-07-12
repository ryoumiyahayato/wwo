class_name CharacterGenerationConfig
extends RefCounted
## Validated, data-driven rules for M4 character generation.

const DEFAULT_PATH: String = "res://data/characters/character_generation.json"

var age_min: int
var age_max: int
var aptitude_min: int
var aptitude_max: int
var growth_modifier_min: float
var growth_modifier_max: float
var trait_rules: Dictionary = {}
var aptitude_keys: Array[String] = []
var skill_keys: Array[String] = []
var trait_keys: Array[String] = []
var labels: Dictionary = {}
var tendency_poles: Dictionary = {}
var country_names: Dictionary = {}
var occupations: Array[Dictionary] = []
var tendency_events: Dictionary = {}
var error_message: String = ""


static func load_from_file(path: String = DEFAULT_PATH) -> CharacterGenerationConfig:
	var config := CharacterGenerationConfig.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		config.error_message = "无法读取人物生成配置：%s" % path
		return config
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		config.error_message = "人物生成配置 JSON 无效（第 %d 行）：%s" % [
			parser.get_error_line(), parser.get_error_message()
		]
		return config
	if not parser.data is Dictionary:
		config.error_message = "人物生成配置顶层必须是对象"
		return config
	config._load_dictionary(parser.data as Dictionary)
	return config


func is_valid() -> bool:
	return error_message.is_empty()


func get_label(group: String, key: String) -> String:
	var group_labels: Dictionary = labels.get(group, {}) as Dictionary
	return str(group_labels.get(key, key))


func get_category_ids() -> Array[String]:
	var output: Array[String] = []
	var category_labels: Dictionary = labels.get("categories", {}) as Dictionary
	for raw_key: Variant in category_labels:
		output.append(str(raw_key))
	output.sort()
	return output


func get_occupation(occupation_id: String) -> Dictionary:
	for occupation: Dictionary in occupations:
		if str(occupation.get("id", "")) == occupation_id:
			return occupation
	return {}


func growth_modifier(aptitude: int) -> float:
	var ratio: float = clampf(float(aptitude) / 100.0, 0.0, 1.0)
	return lerpf(growth_modifier_min, growth_modifier_max, ratio)


func describe_tendency(tendency_id: String, value: int) -> String:
	var poles: Dictionary = tendency_poles.get(tendency_id, {}) as Dictionary
	var negative: String = str(poles.get("negative", "负向"))
	var positive: String = str(poles.get("positive", "正向"))
	if value <= -60:
		return "明显偏向%s" % negative
	if value <= -20:
		return "倾向%s" % negative
	if value < 20:
		return "立场中间"
	if value < 60:
		return "倾向%s" % positive
	return "明显偏向%s" % positive


func _load_dictionary(data: Dictionary) -> void:
	if not data.has("config_version") or int(data.get("config_version", 0)) != 1:
		error_message = "不支持的人物生成配置版本"
		return
	var required: Array[String] = [
		"age_range", "aptitude_range", "growth_modifier_range", "trait_rules",
		"aptitude_keys", "skill_keys", "trait_keys", "labels", "tendency_poles",
		"country_names", "occupations", "tendency_events",
	]
	for key: String in required:
		if not data.has(key):
			error_message = "人物生成配置缺少字段：%s" % key
			return
	if not _valid_pair(data["age_range"]) or not _valid_pair(data["aptitude_range"]) or not _valid_pair(data["growth_modifier_range"]):
		error_message = "人物生成配置的范围字段无效"
		return
	age_min = int((data["age_range"] as Array)[0])
	age_max = int((data["age_range"] as Array)[1])
	aptitude_min = int((data["aptitude_range"] as Array)[0])
	aptitude_max = int((data["aptitude_range"] as Array)[1])
	growth_modifier_min = float((data["growth_modifier_range"] as Array)[0])
	growth_modifier_max = float((data["growth_modifier_range"] as Array)[1])
	if not data["trait_rules"] is Dictionary or not data["labels"] is Dictionary or not data["tendency_poles"] is Dictionary or not data["country_names"] is Dictionary or not data["occupations"] is Array or not data["tendency_events"] is Dictionary:
		error_message = "人物生成配置字段类型无效"
		return
	trait_rules = (data["trait_rules"] as Dictionary).duplicate(true)
	aptitude_keys = DataRecordUtils.to_string_array(data["aptitude_keys"])
	skill_keys = DataRecordUtils.to_string_array(data["skill_keys"])
	trait_keys = DataRecordUtils.to_string_array(data["trait_keys"])
	labels = (data["labels"] as Dictionary).duplicate(true)
	tendency_poles = (data["tendency_poles"] as Dictionary).duplicate(true)
	country_names = (data["country_names"] as Dictionary).duplicate(true)
	for raw_occupation: Variant in data["occupations"] as Array:
		if not raw_occupation is Dictionary:
			error_message = "职业配置必须是对象"
			return
		var occupation: Dictionary = raw_occupation as Dictionary
		for field: String in ["id", "name", "category", "standard_weight", "population_weight", "challenge", "position", "employment_status", "wealth_range", "reputation_range", "skill_bases", "tendency_bases"]:
			if not occupation.has(field):
				error_message = "职业配置缺少字段：%s" % field
				return
		occupations.append(occupation.duplicate(true))
	tendency_events = (data["tendency_events"] as Dictionary).duplicate(true)
	if age_min > age_max or aptitude_min > aptitude_max or growth_modifier_min > growth_modifier_max or occupations.is_empty():
		error_message = "人物生成配置范围顺序或职业列表无效"


static func _valid_pair(value: Variant) -> bool:
	return value is Array and (value as Array).size() == 2
