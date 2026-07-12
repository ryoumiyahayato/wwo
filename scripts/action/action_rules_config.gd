class_name ActionRulesConfig
extends RefCounted
## Global M5 formula and presentation bands. Per-action weights remain on definitions.

const DEFAULT_PATH: String = "res://data/balance/action_rules.json"

var primary_skill_weight: float
var secondary_skill_weight: float
var position_permission_bonus: float
var progress_base_multiplier: float
var progress_effective_scale: float
var minimum_progress_multiplier: float
var maximum_progress_multiplier: float
var state_rules: Dictionary = {}
var outlook_bands: Array[Dictionary] = []
var guaranteed_label: String
var aptitude_by_skill: Dictionary = {}
var error_message: String = ""


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "无法读取行动规则：%s" % path
		return ERR_FILE_CANT_OPEN
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		error_message = "行动规则 JSON 无效"
		return ERR_PARSE_ERROR
	var data: Dictionary = parser.data as Dictionary
	var required: Array[String] = [
		"config_version", "primary_skill_weight", "secondary_skill_weight",
		"position_permission_bonus", "progress_base_multiplier",
		"progress_effective_scale", "minimum_progress_multiplier",
		"maximum_progress_multiplier", "state", "outlook_bands",
		"guaranteed_label", "aptitude_by_skill",
	]
	for key: String in required:
		if not data.has(key):
			error_message = "行动规则缺少字段：%s" % key
			return ERR_INVALID_DATA
	if int(data["config_version"]) != 1 or not data["state"] is Dictionary or not data["outlook_bands"] is Array or not data["aptitude_by_skill"] is Dictionary:
		error_message = "行动规则版本或字段类型无效"
		return ERR_INVALID_DATA
	primary_skill_weight = float(data["primary_skill_weight"])
	secondary_skill_weight = float(data["secondary_skill_weight"])
	position_permission_bonus = float(data["position_permission_bonus"])
	progress_base_multiplier = float(data["progress_base_multiplier"])
	progress_effective_scale = float(data["progress_effective_scale"])
	minimum_progress_multiplier = float(data["minimum_progress_multiplier"])
	maximum_progress_multiplier = float(data["maximum_progress_multiplier"])
	state_rules = (data["state"] as Dictionary).duplicate(true)
	for raw_band: Variant in data["outlook_bands"] as Array:
		if not raw_band is Dictionary or not (raw_band as Dictionary).has("maximum") or not (raw_band as Dictionary).has("label"):
			error_message = "行动把握分档无效"
			return ERR_INVALID_DATA
		outlook_bands.append((raw_band as Dictionary).duplicate(true))
	guaranteed_label = str(data["guaranteed_label"])
	aptitude_by_skill = (data["aptitude_by_skill"] as Dictionary).duplicate(true)
	if primary_skill_weight < 0.0 or secondary_skill_weight < 0.0 or minimum_progress_multiplier <= 0.0 or maximum_progress_multiplier < minimum_progress_multiplier or outlook_bands.is_empty():
		error_message = "行动规则数值范围无效"
		return ERR_INVALID_DATA
	return OK


func get_outlook(effective_value: float, guaranteed_threshold: float) -> String:
	if effective_value >= guaranteed_threshold:
		return guaranteed_label
	for band: Dictionary in outlook_bands:
		if effective_value < float(band["maximum"]):
			return str(band["label"])
	return str(outlook_bands.back()["label"])

