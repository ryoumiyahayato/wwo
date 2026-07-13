class_name MapRulesConfig
extends RefCounted
## Loads all M3 map geometry, interaction, and control thresholds.

const DEFAULT_PATH: String = "res://data/balance/map_rules.json"

var tile_width: float = 86.0
var tile_height: float = 68.0
var min_zoom: float = 0.65
var max_zoom: float = 1.8
var zoom_step: float = 0.15
var pan_visible_margin: float = 110.0
var weak_control_threshold: float = 0.55
var contested_threshold: float = 0.45
var capture_strength_threshold: float = 0.15
var capture_contested_threshold: float = 0.65
var consolidation_strength: float = 0.3
var pressure_strength_loss: float = 0.12
var pressure_contested_gain: float = 0.18
var pressure_enemy_gain: float = 0.15
var rail_attack_bonus: float = 0.18
var rail_defense_bonus: float = 0.12
var rail_consolidation_bonus: float = 0.14
var social_support_scale: float = 0.35
var surrounded_attack_bonus: float = 0.35
var multi_front_bonus: float = 0.12
var minimum_pressure_multiplier: float = 0.35
var maximum_pressure_multiplier: float = 1.9
var error_message: String = ""


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	error_message = ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error_message = "无法读取地图规则：%s" % path
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		error_message = "地图规则 JSON 无效（第 %d 行）：%s" % [
			parser.get_error_line(), parser.get_error_message()
		]
		return parse_error
	if not parser.data is Dictionary:
		error_message = "地图规则顶层必须是对象"
		return ERR_INVALID_DATA
	var data: Dictionary = parser.data as Dictionary
	var fields: PackedStringArray = [
		"tile_width",
		"tile_height",
		"min_zoom",
		"max_zoom",
		"zoom_step",
		"pan_visible_margin",
		"weak_control_threshold",
		"contested_threshold",
		"capture_strength_threshold",
		"capture_contested_threshold",
		"consolidation_strength",
		"pressure_strength_loss",
		"pressure_contested_gain",
		"pressure_enemy_gain",
		"rail_attack_bonus",
		"rail_defense_bonus",
		"rail_consolidation_bonus",
		"social_support_scale",
		"surrounded_attack_bonus",
		"multi_front_bonus",
		"minimum_pressure_multiplier",
		"maximum_pressure_multiplier",
	]
	for field: String in fields:
		if not data.has(field) or (
			not data[field] is int and not data[field] is float
		):
			error_message = "地图规则字段 %s 必须是数字" % field
			return ERR_INVALID_DATA

	tile_width = float(data["tile_width"])
	tile_height = float(data["tile_height"])
	min_zoom = float(data["min_zoom"])
	max_zoom = float(data["max_zoom"])
	zoom_step = float(data["zoom_step"])
	pan_visible_margin = float(data["pan_visible_margin"])
	weak_control_threshold = float(data["weak_control_threshold"])
	contested_threshold = float(data["contested_threshold"])
	capture_strength_threshold = float(data["capture_strength_threshold"])
	capture_contested_threshold = float(data["capture_contested_threshold"])
	consolidation_strength = float(data["consolidation_strength"])
	pressure_strength_loss = float(data["pressure_strength_loss"])
	pressure_contested_gain = float(data["pressure_contested_gain"])
	pressure_enemy_gain = float(data["pressure_enemy_gain"])
	rail_attack_bonus = float(data["rail_attack_bonus"])
	rail_defense_bonus = float(data["rail_defense_bonus"])
	rail_consolidation_bonus = float(data["rail_consolidation_bonus"])
	social_support_scale = float(data["social_support_scale"])
	surrounded_attack_bonus = float(data["surrounded_attack_bonus"])
	multi_front_bonus = float(data["multi_front_bonus"])
	minimum_pressure_multiplier = float(data["minimum_pressure_multiplier"])
	maximum_pressure_multiplier = float(data["maximum_pressure_multiplier"])

	if tile_width <= 0.0 or tile_height <= 0.0:
		error_message = "地图单元尺寸必须大于零"
		return ERR_INVALID_DATA
	if min_zoom <= 0.0 or max_zoom < min_zoom or zoom_step <= 0.0:
		error_message = "地图缩放范围无效"
		return ERR_INVALID_DATA
	for value: float in [
		weak_control_threshold,
		contested_threshold,
		capture_strength_threshold,
		capture_contested_threshold,
		consolidation_strength,
		pressure_strength_loss,
		pressure_contested_gain,
		pressure_enemy_gain,
		rail_attack_bonus,
		rail_defense_bonus,
		rail_consolidation_bonus,
		social_support_scale,
		surrounded_attack_bonus,
		multi_front_bonus,
	]:
		if value < 0.0 or value > 1.0:
			error_message = "地图控制阈值和修正必须位于 0 至 1"
			return ERR_INVALID_DATA
	if (
		minimum_pressure_multiplier <= 0.0
		or maximum_pressure_multiplier < minimum_pressure_multiplier
		or maximum_pressure_multiplier > 3.0
	):
		error_message = "地图压力倍率范围无效"
		return ERR_INVALID_DATA
	return OK
