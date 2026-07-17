class_name V2LifeLoopConfig
extends RefCounted
## Validated aggregate of the small V2.2 scenario documents.

const PATHS: Dictionary = {
	"balance": "res://data/v2_2/v2_2_balance.json",
	"living_costs": "res://data/v2_2/lille_demo_living_costs.json",
	"locations": "res://data/v2_2/lille_demo_locations.json",
	"employment": "res://data/v2_2/lille_demo_employment.json",
	"people": "res://data/v2_2/lille_demo_people.json",
	"scenario": "res://data/scenarios/v2_2_lille_life_loop.json",
}

var documents: Dictionary = {}
var errors: Array[String] = []


func load_all() -> Error:
	documents.clear()
	errors.clear()
	for key_variant: Variant in PATHS.keys():
		var key: String = str(key_variant)
		var path: String = str(PATHS[key])
		var document: Dictionary = _load_document(path)
		if not document.is_empty():
			documents[key] = document
	_validate()
	return OK if errors.is_empty() else ERR_INVALID_DATA


func get_document(key: String) -> Dictionary:
	var value: Variant = documents.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func person_records() -> Array:
	return get_document("people").get("people", []) as Array


func household_records() -> Array:
	return get_document("people").get("households", []) as Array


func contract_records() -> Array:
	return get_document("employment").get("contracts", []) as Array


func person_record(person_id: String) -> Dictionary:
	for record_variant: Variant in person_records():
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("person_id", "")) == person_id:
			return record.duplicate(true)
	return {}


func contract_for_person(person_id: String) -> Dictionary:
	for record_variant: Variant in contract_records():
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("person_id", "")) == person_id:
			return record.duplicate(true)
	return {}


func location_name(location_id: String) -> String:
	for record_variant: Variant in get_document("locations").get("locations", []):
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("id", "")) == location_id:
			return str(record.get("name", location_id))
	return location_id


func _load_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取 V2.2 配置：%s" % path)
		return {}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		errors.append("V2.2 配置 JSON 无效：%s:%d %s" % [
			path, parser.get_error_line(), parser.get_error_message()
		])
		return {}
	if not parser.data is Dictionary:
		errors.append("V2.2 配置顶层必须是对象：%s" % path)
		return {}
	return _normalize_json_value(parser.data) as Dictionary


static func _normalize_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for raw_key: Variant in (value as Dictionary).keys():
			normalized[str(raw_key)] = _normalize_json_value((value as Dictionary)[raw_key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for item: Variant in value as Array:
			normalized.append(_normalize_json_value(item))
		return normalized
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value


func _validate() -> void:
	if documents.size() != PATHS.size():
		return
	for key_variant: Variant in documents.keys():
		var key: String = str(key_variant)
		var document: Dictionary = documents[key] as Dictionary
		if int(document.get("config_version", document.get("schema_version", 0))) != 1:
			errors.append("%s 配置版本不是 1" % key)
		if key != "scenario" and document.get("prototype_balance_value", false) != true:
			errors.append("%s 未标记 prototype_balance_value" % key)
	var scenario: Dictionary = documents["scenario"] as Dictionary
	for field: String in [
		"scenario_id", "start_datetime", "default_selected_person_id",
		"random_seed", "review_save_path",
	]:
		if not scenario.has(field):
			errors.append("评审场景缺少字段：%s" % field)
	var people: Array = (documents["people"] as Dictionary).get("people", []) as Array
	var households: Array = (documents["people"] as Dictionary).get("households", []) as Array
	var contracts: Array = (documents["employment"] as Dictionary).get("contracts", []) as Array
	if people.size() != 2 or households.size() != 2 or contracts.size() != 2:
		errors.append("V2.2 评审场景必须恰好包含两个人物、住户和合同")
	var person_ids: Dictionary = {}
	for record_variant: Variant in people:
		var record: Dictionary = record_variant as Dictionary
		var person_id: String = str(record.get("person_id", ""))
		if person_id.is_empty() or person_ids.has(person_id):
			errors.append("人物 ID 缺失或重复：%s" % person_id)
		person_ids[person_id] = true
	for contract_variant: Variant in contracts:
		var contract: Dictionary = contract_variant as Dictionary
		if not person_ids.has(str(contract.get("person_id", ""))):
			errors.append("劳动合同引用未知人物")
	var speeds: Array = (
		((documents["balance"] as Dictionary).get("time", {}) as Dictionary)
		.get("allowed_speed_multipliers", []) as Array
	)
	var parsed_speeds: Array[int] = []
	for raw_speed: Variant in speeds:
		parsed_speeds.append(int(raw_speed))
	if parsed_speeds != [1, 2, 4, 8]:
		errors.append("V2.2 倍率配置必须为 1/2/4/8")
