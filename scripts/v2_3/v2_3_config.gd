class_name V23Config
extends RefCounted
## Validated aggregate for the V2.3 Lille and connected cross-border world.

const PATHS: Dictionary = {
	"locations": "res://data/v2_3/lille_locations.json",
	"cross_border_locations": "res://data/v2_3/cross_border_locations.json",
	"graph": "res://data/v2_3/lille_travel_graph.json",
	"cross_border_graph": "res://data/v2_3/cross_border_travel_graph.json",
	"transport": "res://data/v2_3/transport_modes.json",
	"communication": "res://data/v2_3/communication_channels.json",
	"knowledge": "res://data/v2_3/knowledge_rules.json",
	"relationships": "res://data/v2_3/relationship_rules.json",
	"people": "res://data/v2_3/social_people.json",
	"balance": "res://data/v2_3/v2_3_balance.json",
	"scenario": "res://data/scenarios/v2_3_lille_space_cognition.json",
}

var documents: Dictionary = {}
var errors: Array[String] = []


func load_all() -> Error:
	documents.clear()
	errors.clear()
	for raw_key: Variant in PATHS.keys():
		var key: String = str(raw_key)
		var document: Dictionary = _load_document(str(PATHS[key]))
		if not document.is_empty():
			documents[key] = document
	if documents.size() == PATHS.size():
		_validate()
	return OK if errors.is_empty() else ERR_INVALID_DATA


func get_document(key: String) -> Dictionary:
	var value: Variant = documents.get(key, {})
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


func location_records() -> Array:
	var result: Array = (
		get_document("locations").get("locations", []) as Array
	).duplicate(true)
	result.append_array(
		(get_document("cross_border_locations").get(
			"locations", []
		) as Array).duplicate(true)
	)
	return result


func edge_records() -> Array:
	var result: Array = (
		get_document("graph").get("edges", []) as Array
	).duplicate(true)
	result.append_array(
		(get_document("cross_border_graph").get(
			"edges", []
		) as Array).duplicate(true)
	)
	return result


func transport_records() -> Array:
	return get_document("transport").get("modes", []) as Array


func social_people() -> Array:
	return get_document("people").get("people", []) as Array


func relationship_records() -> Array:
	return get_document("people").get("relationships", []) as Array


func scenario() -> Dictionary:
	return get_document("scenario")


func _load_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取 V2.3 配置：%s" % path)
		return {}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		errors.append("V2.3 JSON 无效：%s:%d %s" % [
			path,
			parser.get_error_line(),
			parser.get_error_message(),
		])
		return {}
	if not parser.data is Dictionary:
		errors.append("V2.3 配置根节点必须是对象：%s" % path)
		return {}
	return _normalize(parser.data) as Dictionary


func _validate() -> void:
	for raw_key: Variant in documents.keys():
		var key: String = str(raw_key)
		var document: Dictionary = documents[key] as Dictionary
		if int(document.get(
			"config_version", document.get("schema_version", 0)
		)) != 1:
			errors.append("%s 配置版本不是 1" % key)
		if not bool(document.get("prototype_balance_value", false)):
			errors.append("%s 未标记 prototype_balance_value" % key)
	var locations: Dictionary = {}
	var allowed_types: PackedStringArray = [
		"residence",
		"workplace",
		"market",
		"organization_hall",
		"government_office",
		"post_office",
		"public_square",
		"railway_station",
		"city_centre",
		"regional_centre",
	]
	for raw_location: Variant in location_records():
		if not raw_location is Dictionary:
			errors.append("V2.3 地点记录必须是对象")
			continue
		var location: Dictionary = raw_location as Dictionary
		var location_id: String = str(location.get("location_id", ""))
		if location_id.is_empty() or locations.has(location_id):
			errors.append("V2.3 地点 ID 缺失或重复：%s" % location_id)
		else:
			locations[location_id] = true
		if str(location.get("location_type", "")) not in allowed_types:
			errors.append("V2.3 地点类型无效：%s" % location_id)
		if not _valid_pair(location.get("world_position", [])):
			errors.append("V2.3 地点世界坐标无效：%s" % location_id)
		if not location.get("opening_hours", {}) is Dictionary:
			errors.append("V2.3 地点营业时间无效：%s" % location_id)
	if locations.size() < 17:
		errors.append("V2.3 正式地点少于 17 个")

	var modes: Dictionary = {}
	for raw_mode: Variant in transport_records():
		if not raw_mode is Dictionary:
			continue
		var mode: Dictionary = raw_mode as Dictionary
		var mode_id: String = str(mode.get("mode_id", ""))
		if mode_id.is_empty() or modes.has(mode_id):
			errors.append("V2.3 交通方式 ID 缺失或重复：%s" % mode_id)
		else:
			modes[mode_id] = true
	for required_mode: String in [
		"walk", "urban_transit", "regional_train",
	]:
		if not modes.has(required_mode):
			errors.append("V2.3 缺少交通方式：%s" % required_mode)

	var edges: Dictionary = {}
	for raw_edge: Variant in edge_records():
		if not raw_edge is Dictionary:
			errors.append("V2.3 交通边记录必须是对象")
			continue
		var edge: Dictionary = raw_edge as Dictionary
		var edge_id: String = str(edge.get("edge_id", ""))
		if edge_id.is_empty() or edges.has(edge_id):
			errors.append("V2.3 交通边 ID 缺失或重复：%s" % edge_id)
		else:
			edges[edge_id] = true
		for field: String in ["from_location_id", "to_location_id"]:
			if not locations.has(str(edge.get(field, ""))):
				errors.append(
					"V2.3 交通边引用未知地点：%s/%s" % [edge_id, field]
				)
		for raw_mode_id: Variant in edge.get("available_modes", []) as Array:
			var mode_id: String = str(raw_mode_id)
			if not modes.has(mode_id):
				errors.append(
					"V2.3 交通边引用未知交通方式：%s/%s" % [
						edge_id, mode_id,
					]
				)
			var duration: int = int(
				(edge.get("duration_hours_by_mode", {}) as Dictionary).get(
					mode_id, 0
				)
			)
			var cost: int = int(
				(edge.get("cost_centimes_by_mode", {}) as Dictionary).get(
					mode_id, -1
				)
			)
			if duration < 1 or cost < 0:
				errors.append(
					"V2.3 交通边耗时或费用无效：%s/%s" % [
						edge_id, mode_id,
					]
				)
	_validate_people(locations)


func _validate_people(locations: Dictionary) -> void:
	var people: Dictionary = {}
	for raw_person: Variant in social_people():
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		if person_id.is_empty() or people.has(person_id):
			errors.append("V2.3 人物 ID 缺失或重复：%s" % person_id)
		else:
			people[person_id] = true
		for field: String in [
			"home_location_id",
			"workplace_location_id",
			"postal_address_location_id",
		]:
			if not locations.has(str(person.get(field, ""))):
				errors.append(
					"V2.3 人物引用未知地点：%s/%s" % [person_id, field]
				)
	for required_id: String in [
		"character_pierre_lefevre",
		"character_albert_dumont",
		"jeanne",
		"character_jules_martin",
		"character_lucien_moreau",
	]:
		if not people.has(required_id):
			errors.append("V2.3 缺少人物：%s" % required_id)


static func _valid_pair(value: Variant) -> bool:
	return value is Array and (value as Array).size() == 2


static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for raw_key: Variant in (value as Dictionary).keys():
			result[str(raw_key)] = _normalize(
				(value as Dictionary)[raw_key]
			)
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_normalize(item))
		return result
	if (
		typeof(value) == TYPE_FLOAT
		and is_equal_approx(float(value), roundf(float(value)))
	):
		return int(roundf(float(value)))
	return value
