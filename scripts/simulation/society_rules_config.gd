class_name SocietyRulesConfig
extends RefCounted

const DEFAULT_PATH: String = "res://data/balance/society_rules.json"

var background_character_count: int
var active_character_limit: int
var initial_active_npc_count: int
var background_seed_base: int
var relationship_defaults: Dictionary = {}
var organization_economy: Dictionary = {}
var lifecycle_rules: Dictionary = {}
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
	for key: String in [
		"config_version",
		"background_character_count",
		"active_character_limit",
		"initial_active_npc_count",
		"background_seed_base",
		"relationship_defaults",
		"organization_economy",
		"lifecycle",
		"ai",
	]:
		if not data.has(key):
			error_message = "社会模拟规则缺少字段：%s" % key
			return ERR_INVALID_DATA
	if int(data["config_version"]) != 1 or not data["relationship_defaults"] is Dictionary or not data["organization_economy"] is Dictionary or not data["lifecycle"] is Dictionary or not data["ai"] is Dictionary:
		error_message = "社会模拟规则版本或字段类型无效"
		return ERR_INVALID_DATA
	background_character_count = int(data["background_character_count"])
	active_character_limit = int(data["active_character_limit"])
	initial_active_npc_count = int(data["initial_active_npc_count"])
	background_seed_base = int(data["background_seed_base"])
	relationship_defaults = (
		data["relationship_defaults"] as Dictionary
	).duplicate(true)
	organization_economy = (
		data["organization_economy"] as Dictionary
	).duplicate(true)
	lifecycle_rules = (data["lifecycle"] as Dictionary).duplicate(true)
	ai_rules = (data["ai"] as Dictionary).duplicate(true)
	if background_character_count < 100 or background_character_count > 200 or active_character_limit < 1 or active_character_limit > 20 or initial_active_npc_count < 0 or initial_active_npc_count >= active_character_limit:
		error_message = "社会人物规模超出 Demo 预算"
		return ERR_INVALID_DATA
	if not ai_rules.has("candidates") or not ai_rules["candidates"] is Array or (ai_rules["candidates"] as Array).is_empty():
		error_message = "AI 候选配置无效"
		return ERR_INVALID_DATA
	for key: String in [
		"monthly_base_income",
		"size_income_scale",
		"influence_income_scale",
		"resource_cap",
	]:
		if float(organization_economy.get(key, -1.0)) < 0.0:
			error_message = "组织经济规则 %s 无效" % key
			return ERR_INVALID_DATA
	for key: String in [
		"retirement_age",
		"maximum_age",
		"health_decline_start_age",
		"old_age_start",
		"annual_health_decline",
		"old_age_additional_decline",
		"background_exit_age",
	]:
		if int(lifecycle_rules.get(key, -1)) < 0:
			error_message = "人物生命周期规则 %s 无效" % key
			return ERR_INVALID_DATA
	if int(lifecycle_rules["maximum_age"]) < int(lifecycle_rules["retirement_age"]) or int(lifecycle_rules["old_age_start"]) < int(lifecycle_rules["health_decline_start_age"]):
		error_message = "人物生命周期年龄顺序无效"
		return ERR_INVALID_DATA
	return OK


func get_goal_label(goal_id: String) -> String:
	var labels: Dictionary = ai_rules.get("goal_labels", {}) as Dictionary
	return str(labels.get(goal_id, goal_id))
