class_name SocietyRulesConfig
extends RefCounted

const DEFAULT_PATH: String = "res://data/balance/society_rules.json"

var background_character_count: int
var active_character_limit: int
var initial_active_npc_count: int
var background_seed_base: int
var relationship_defaults: Dictionary = {}
var ai_rules: Dictionary = {}
var error_message: String = ""


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "无法读取社会模拟规则：%s" % path
		return ERR_FILE_CANT_OPEN
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		error_message = "社会模拟规则 JSON 无效"
		return ERR_PARSE_ERROR
	var data: Dictionary = parser.data as Dictionary
	for key: String in ["config_version", "background_character_count", "active_character_limit", "initial_active_npc_count", "background_seed_base", "relationship_defaults", "ai"]:
		if not data.has(key):
			error_message = "社会模拟规则缺少字段：%s" % key
			return ERR_INVALID_DATA
	if int(data["config_version"]) != 1 or not data["relationship_defaults"] is Dictionary or not data["ai"] is Dictionary:
		error_message = "社会模拟规则版本或字段类型无效"
		return ERR_INVALID_DATA
	background_character_count = int(data["background_character_count"])
	active_character_limit = int(data["active_character_limit"])
	initial_active_npc_count = int(data["initial_active_npc_count"])
	background_seed_base = int(data["background_seed_base"])
	relationship_defaults = (data["relationship_defaults"] as Dictionary).duplicate(true)
	ai_rules = (data["ai"] as Dictionary).duplicate(true)
	if background_character_count < 100 or background_character_count > 200 or active_character_limit < 1 or active_character_limit > 20 or initial_active_npc_count < 0 or initial_active_npc_count >= active_character_limit:
		error_message = "社会人物规模超出 Demo 预算"
		return ERR_INVALID_DATA
	if not ai_rules.has("candidates") or not ai_rules["candidates"] is Array or (ai_rules["candidates"] as Array).is_empty():
		error_message = "AI 候选配置无效"
		return ERR_INVALID_DATA
	return OK


func get_goal_label(goal_id: String) -> String:
	var labels: Dictionary = ai_rules.get("goal_labels", {}) as Dictionary
	return str(labels.get(goal_id, goal_id))

