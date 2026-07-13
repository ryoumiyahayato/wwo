class_name ActionRulesConfig
extends RefCounted
## Global action formula, presentation bands and player-derived context rules.

const DEFAULT_PATH: String = "res://data/balance/action_rules.json"

var primary_skill_weight: float
var secondary_skill_weight: float
var position_permission_bonus: float
var progress_base_multiplier: float
var progress_effective_scale: float
var minimum_progress_multiplier: float
var maximum_progress_multiplier: float
var mastery_guarantee: Dictionary = {}
var practice_growth: Dictionary = {}
var state_rules: Dictionary = {}
var player_context_rules: Dictionary = {}
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
		"maximum_progress_multiplier", "mastery_guarantee", "practice_growth",
		"state", "player_context", "outlook_bands", "guaranteed_label",
		"aptitude_by_skill",
	]
	for key: String in required:
		if not data.has(key):
			error_message = "行动规则缺少字段：%s" % key
			return ERR_INVALID_DATA
	if (
		int(data["config_version"]) != 1
		or not data["mastery_guarantee"] is Dictionary
		or not data["practice_growth"] is Dictionary
		or not data["state"] is Dictionary
		or not data["player_context"] is Dictionary
		or not data["outlook_bands"] is Array
		or not data["aptitude_by_skill"] is Dictionary
	):
		error_message = "行动规则版本或字段类型无效"
		return ERR_INVALID_DATA
	primary_skill_weight = float(data["primary_skill_weight"])
	secondary_skill_weight = float(data["secondary_skill_weight"])
	position_permission_bonus = float(data["position_permission_bonus"])
	progress_base_multiplier = float(data["progress_base_multiplier"])
	progress_effective_scale = float(data["progress_effective_scale"])
	minimum_progress_multiplier = float(data["minimum_progress_multiplier"])
	maximum_progress_multiplier = float(data["maximum_progress_multiplier"])
	mastery_guarantee = (data["mastery_guarantee"] as Dictionary).duplicate(true)
	practice_growth = (data["practice_growth"] as Dictionary).duplicate(true)
	state_rules = (data["state"] as Dictionary).duplicate(true)
	player_context_rules = (data["player_context"] as Dictionary).duplicate(true)
	outlook_bands.clear()
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
	for key: String in [
		"skill_threshold",
		"preparation_threshold",
		"funding_threshold",
		"effective_value_bonus",
	]:
		if typeof(mastery_guarantee.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			error_message = "行动精通保证规则 %s 必须是数字" % key
			return ERR_INVALID_DATA
	for key: String in ["skill_threshold", "preparation_threshold", "funding_threshold"]:
		var threshold: float = float(mastery_guarantee[key])
		if threshold < 0.0 or threshold > 100.0:
			error_message = "行动精通保证阈值 %s 超出范围" % key
			return ERR_INVALID_DATA
	if float(mastery_guarantee["effective_value_bonus"]) < 0.0:
		error_message = "行动精通保证加成无效"
		return ERR_INVALID_DATA
	for key: String in ["success_delta", "failure_delta"]:
		if typeof(practice_growth.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			error_message = "行动实践成长规则 %s 必须是数字" % key
			return ERR_INVALID_DATA
		var value: float = float(practice_growth[key])
		if value < 0.0 or value > 10.0 or value != floor(value):
			error_message = "行动实践成长规则 %s 超出范围" % key
			return ERR_INVALID_DATA
	var costs: Variant = player_context_rules.get("funding_cost_by_category", {})
	if not costs is Dictionary:
		error_message = "玩家行动费用规则无效"
		return ERR_INVALID_DATA
	for key: String in [
		"funding_value_per_wealth",
		"preparation_value_per_extra_wealth",
	]:
		if float(player_context_rules.get(key, -1.0)) < 0.0:
			error_message = "玩家行动上下文规则 %s 无效" % key
			return ERR_INVALID_DATA
	if int(player_context_rules.get("maximum_extra_funding", -1)) < 0:
		error_message = "玩家额外投入上限无效"
		return ERR_INVALID_DATA
	return OK


func get_outlook(effective_value: float, guaranteed_threshold: float) -> String:
	if effective_value >= guaranteed_threshold:
		return guaranteed_label
	for band: Dictionary in outlook_bands:
		if effective_value < float(band["maximum"]):
			return str(band["label"])
	return str(outlook_bands.back()["label"])
