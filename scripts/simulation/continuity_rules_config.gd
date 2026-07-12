class_name ContinuityRulesConfig
extends RefCounted

const DEFAULT_PATH: String = "res://data/balance/continuity_rules.json"

var social_influence: Dictionary = {}
var candidate: Dictionary = {}
var enemy_affinity_threshold: float
var position_inheritance_minimum_score: float
var exit_reasons: Dictionary = {}
var error_message: String = ""


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "无法读取连续性规则：%s" % path
		return ERR_FILE_CANT_OPEN
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		error_message = "连续性规则 JSON 无效"
		return ERR_PARSE_ERROR
	var data: Dictionary = parser.data as Dictionary
	for key: String in ["config_version", "social_influence", "candidate", "enemy_affinity_threshold", "position_inheritance_minimum_score", "exit_reasons"]:
		if not data.has(key):
			error_message = "连续性规则缺少字段：%s" % key
			return ERR_INVALID_DATA
	if int(data["config_version"]) != 1 or not data["social_influence"] is Dictionary or not data["candidate"] is Dictionary or not data["exit_reasons"] is Dictionary:
		error_message = "连续性规则版本或字段类型无效"
		return ERR_INVALID_DATA
	social_influence = (data["social_influence"] as Dictionary).duplicate(true)
	candidate = (data["candidate"] as Dictionary).duplicate(true)
	enemy_affinity_threshold = float(data["enemy_affinity_threshold"])
	position_inheritance_minimum_score = float(data["position_inheritance_minimum_score"])
	exit_reasons = (data["exit_reasons"] as Dictionary).duplicate(true)
	for reason_id: String in ["death", "retirement", "long_imprisonment", "disgrace", "voluntary"]:
		if not exit_reasons.has(reason_id) or not exit_reasons[reason_id] is Dictionary:
			error_message = "缺少退出原因规则：%s" % reason_id
			return ERR_INVALID_DATA
		var reason: Dictionary = exit_reasons[reason_id] as Dictionary
		for ratio_key: String in ["wealth_ratio", "reputation_ratio", "intelligence_ratio", "ally_relationship_ratio", "enemy_relationship_ratio"]:
			if not reason.has(ratio_key) or float(reason[ratio_key]) < 0.0 or float(reason[ratio_key]) > 1.0:
				error_message = "退出原因 %s 的 %s 无效" % [reason_id, ratio_key]
				return ERR_INVALID_DATA
	return OK


func get_exit_reason_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in exit_reasons:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func get_exit_label(reason_id: String) -> String:
	var reason: Dictionary = exit_reasons.get(reason_id, {}) as Dictionary
	return str(reason.get("label", reason_id))
