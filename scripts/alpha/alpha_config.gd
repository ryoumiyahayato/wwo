class_name AlphaConfig
extends RefCounted
## Loads Alpha content extensions and expands repeated city/location templates.

const PATHS: Dictionary = {
	"world": "res://data/alpha/world.json",
	"economy": "res://data/alpha/economy.json",
	"politics": "res://data/alpha/politics.json",
	"presets": "res://data/alpha/presets.json",
}
const LOCATION_ROLE_OFFSETS: Dictionary = {
	"home": [-0.22, 0.18],
	"workplace": [0.18, 0.14],
	"market": [-0.16, -0.08],
	"lender": [0.10, -0.12],
	"organization": [-0.05, 0.28],
	"government": [0.24, -0.24],
	"station": [0.34, 0.04],
	"square": [0.0, 0.0],
}

var documents: Dictionary = {}
var errors: Array[String] = []
var locations: Array[Dictionary] = []
var transport_edges: Array[Dictionary] = []
var people: Array[Dictionary] = []


func load_all() -> Error:
	documents.clear()
	errors.clear()
	locations.clear()
	transport_edges.clear()
	people.clear()
	for raw_key: Variant in PATHS.keys():
		var key: String = str(raw_key)
		var document: Dictionary = load_json(str(PATHS[key]))
		if not document.is_empty():
			documents[key] = document
	if documents.size() != PATHS.size():
		return ERR_FILE_CORRUPT
	_expand_people()
	_expand_locations()
	_expand_transport_edges()
	_validate()
	return OK if errors.is_empty() else ERR_INVALID_DATA


func get_document(key: String) -> Dictionary:
	var value: Variant = documents.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func world() -> Dictionary:
	return get_document("world")


func economy() -> Dictionary:
	return get_document("economy")


func politics() -> Dictionary:
	return get_document("politics")


func presets() -> Dictionary:
	return get_document("presets")


func country_profiles() -> Array:
	return world().get("country_profiles", []) as Array


func region_profiles() -> Array:
	return world().get("region_profiles", []) as Array


func cities() -> Array:
	return world().get("cities", []) as Array


func enterprise_records() -> Array:
	return economy().get("enterprises", []) as Array


func job_records() -> Array:
	return economy().get("jobs", []) as Array


func contract_templates() -> Array:
	return economy().get("contract_templates", []) as Array


func credit_products() -> Array:
	return economy().get("credit_products", []) as Array


func goods() -> Array:
	return economy().get("goods_and_services", []) as Array


func policy_records() -> Array:
	return politics().get("policies", []) as Array


func issue_records() -> Array:
	return politics().get("issues", []) as Array


func organization_additions() -> Array:
	return politics().get("organization_additions", []) as Array


func preset_records() -> Array:
	return presets().get("presets", []) as Array


func get_preset(preset_id: String) -> Dictionary:
	for raw_preset: Variant in preset_records():
		var preset: Dictionary = raw_preset as Dictionary
		if str(preset.get("preset_id", "")) == preset_id:
			return preset.duplicate(true)
	return {}


func default_preset() -> Dictionary:
	var records: Array = preset_records()
	return (records[0] as Dictionary).duplicate(true) if not records.is_empty() else {}


func city_location_id(city_id: String, role: String) -> String:
	return "location:%s:%s" % [city_id.trim_prefix("city:"), role]


func city_record(city_id: String) -> Dictionary:
	for raw_city: Variant in cities():
		var city: Dictionary = raw_city as Dictionary
		if str(city.get("city_id", "")) == city_id:
			return city.duplicate(true)
	return {}


func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取 Alpha 配置：%s" % path)
		return {}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		errors.append("Alpha JSON 无效：%s:%d %s" % [
			path, parser.get_error_line(), parser.get_error_message(),
		])
		return {}
	if not parser.data is Dictionary:
		errors.append("Alpha 配置根节点必须是对象：%s" % path)
		return {}
	return _normalize(parser.data) as Dictionary


func _expand_people() -> void:
	for raw_person: Variant in world().get("high_detail_people", []) as Array:
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = (raw_person as Dictionary).duplicate(true)
		var city_id: String = str(person.get("city_id", ""))
		person["home_location_id"] = city_location_id(
			city_id, str(person.get("home_role", "home"))
		)
		person["workplace_location_id"] = city_location_id(
			city_id, str(person.get("workplace_role", "workplace"))
		)
		person["postal_address_location_id"] = person["home_location_id"]
		person["initial_condition"] = {
			"health": 880,
			"fatigue": 260,
			"stress": 220,
			"sleep_hours_current_day": 0,
			"consecutive_short_sleep_days": 0,
			"consecutive_food_deficit_days": 0,
		}
		person["default_schedule"] = {
			"sleep_start_hour": 22,
			"sleep_end_hour": 6,
			"commute_to_work_start_hour": 7,
			"meal_break_start_hour": 12,
			"commute_home_start_hour": 17,
		}
		people.append(person)


func _expand_locations() -> void:
	var templates: Array = world().get("location_templates", []) as Array
	for raw_city: Variant in cities():
		var city: Dictionary = raw_city as Dictionary
		var city_id: String = str(city.get("city_id", ""))
		var anchor: Array = city.get("anchor", []) as Array
		var city_people: Array[String] = []
		for person: Dictionary in people:
			if str(person.get("city_id", "")) == city_id:
				city_people.append(str(person.get("person_id", "")))
		for raw_template: Variant in templates:
			var template: Dictionary = raw_template as Dictionary
			var role: String = str(template.get("role", ""))
			var offset: Array = LOCATION_ROLE_OFFSETS.get(role, [0.0, 0.0]) as Array
			var location_id: String = city_location_id(city_id, role)
			locations.append({
				"location_id": location_id,
				"display_name": "%s%s" % [
					str(city.get("name", city_id)), str(template.get("name", role)),
				],
				"location_type": str(template.get("location_type", "")),
				"parent_region_id": str(city.get("region_id", "")),
				"country_id": str(city.get("country_id", "")),
				"city_id": city_id,
				"world_position": [
					float(anchor[0]) + float(offset[0]),
					float(anchor[1]) + float(offset[1]),
				],
				"local_position": offset.duplicate(),
				"known_by_default_person_ids": city_people.duplicate(),
				"opening_hours": (
					template.get("opening_hours", {}) as Dictionary
				).duplicate(true),
				"organization_ids": [],
				"workplace_ids": [],
				"resident_person_ids": city_people.duplicate() if role == "home" else [],
				"available_services": (
					template.get("services", []) as Array
				).duplicate(),
				"communication_services": (
					["local_letter_address"] if role == "home"
					else ["public_notice", "local_letter"] if role == "square"
					else []
				),
				"map_visibility_rule": "person_knowledge",
				"discovery_rule": "visit_route_message_or_public_record",
				"prototype_balance_value": true,
			})


func _expand_transport_edges() -> void:
	for raw_city: Variant in cities():
		var city: Dictionary = raw_city as Dictionary
		var city_id: String = str(city.get("city_id", ""))
		var station_id: String = city_location_id(city_id, "station")
		for role: String in [
			"home", "workplace", "market", "lender", "organization",
			"government", "square",
		]:
			var destination_id: String = city_location_id(city_id, role)
			transport_edges.append({
				"edge_id": "edge:%s:station_%s" % [
					city_id.trim_prefix("city:"), role,
				],
				"from_location_id": station_id,
				"to_location_id": destination_id,
				"bidirectional": true,
				"available_modes": ["walk", "urban_transit"],
				"duration_hours_by_mode": {"walk": 1, "urban_transit": 1},
				"cost_centimes_by_mode": {"walk": 0, "urban_transit": 8},
				"opening_hours_by_mode": {
					"walk": [0, 24], "urban_transit": [5, 23],
				},
				"fatigue_by_mode": {"walk": 22, "urban_transit": 7},
				"stress_by_mode": {"walk": 3, "urban_transit": 4},
				"required_knowledge": "public_city_route",
				"active": true,
				"prototype_balance_value": true,
			})
	for raw_connection: Variant in world().get("intercity_connections", []) as Array:
		var connection: Dictionary = raw_connection as Dictionary
		var from_city_id: String = str(connection.get("from_city_id", ""))
		var to_city_id: String = str(connection.get("to_city_id", ""))
		transport_edges.append({
			"edge_id": str(connection.get("edge_id", "")),
			"from_location_id": city_location_id(from_city_id, "station"),
			"to_location_id": city_location_id(to_city_id, "station"),
			"bidirectional": true,
			"available_modes": ["regional_train"],
			"duration_hours_by_mode": {
				"regional_train": int(connection.get("duration_hours", 1)),
			},
			"cost_centimes_by_mode": {
				"regional_train": int(connection.get("cost_centimes", 0)),
			},
			"opening_hours_by_mode": {"regional_train": [5, 23]},
			"fatigue_by_mode": {"regional_train": 12},
			"stress_by_mode": {"regional_train": 8},
			"required_knowledge": "public_intercity_timetable",
			"active": true,
			"cross_border": bool(connection.get("cross_border", false)),
			"prototype_balance_value": true,
		})


func _validate() -> void:
	for raw_key: Variant in documents.keys():
		var key: String = str(raw_key)
		if int((documents[key] as Dictionary).get("config_version", 0)) != 1:
			errors.append("Alpha 配置版本无效：%s" % key)
	if str(world().get("schema_id", "")) != "prototype_0_001_alpha_1":
		errors.append("Alpha 世界 Schema 无效")
	_expect_count("国家", country_profiles().size(), 2, 2)
	_expect_count("行政地区", region_profiles().size(), 8, 8)
	_expect_count("主要城市", cities().size(), 4, 4)
	_expect_count("城市地点", locations.size(), 32, 32)
	_expect_count("交通连接", transport_edges.size(), 20, 9999)
	_expect_count("高精度人物", people.size(), 8, 20)
	_expect_count("商品与服务", goods().size(), 8, 9999)
	_expect_count("企业", enterprise_records().size(), 12, 9999)
	_expect_count("工作模板", job_records().size(), 12, 9999)
	_expect_count("合同模板", contract_templates().size(), 7, 9999)
	_expect_count("信贷产品", credit_products().size(), 5, 9999)
	_expect_count("预制人物", preset_records().size(), 8, 9999)
	var cross_border: int = 0
	for edge: Dictionary in transport_edges:
		if bool(edge.get("cross_border", false)):
			cross_border += 1
	if cross_border < 2:
		errors.append("Alpha 跨国交通连接少于 2 条")
	var region_ids: Dictionary = {}
	for raw_region: Variant in region_profiles():
		var region: Dictionary = raw_region as Dictionary
		var region_id: String = str(region.get("region_id", ""))
		if region_id.is_empty() or region_ids.has(region_id):
			errors.append("Alpha 地区 ID 缺失或重复：%s" % region_id)
		region_ids[region_id] = true
		for field: String in [
			"economic_role", "population", "classes", "industries", "supply",
			"demand", "wage_index", "living_cost_index", "transport",
			"credit_environment", "opportunities", "risks", "dependencies",
		]:
			if not region.has(field):
				errors.append("Alpha 地区缺少字段：%s/%s" % [region_id, field])
	var city_ids: Dictionary = {}
	for raw_city: Variant in cities():
		var city: Dictionary = raw_city as Dictionary
		var city_id: String = str(city.get("city_id", ""))
		if city_id.is_empty() or city_ids.has(city_id):
			errors.append("Alpha 城市 ID 缺失或重复：%s" % city_id)
		city_ids[city_id] = true
		if not region_ids.has(str(city.get("region_id", ""))):
			errors.append("Alpha 城市引用未知地区：%s" % city_id)
	var types: Dictionary = {}
	for raw_template: Variant in contract_templates():
		types[str((raw_template as Dictionary).get("contract_type", ""))] = true
	for required_type: String in [
		"employment", "sale", "service", "lease", "loan", "partnership", "order",
	]:
		if not types.has(required_type):
			errors.append("Alpha 缺少合同类型：%s" % required_type)


func _expect_count(
	label: String, actual: int, minimum: int, maximum: int
) -> void:
	if actual < minimum or actual > maximum:
		errors.append("%s数量无效：%d（要求 %d—%d）" % [
			label, actual, minimum, maximum,
		])


static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for raw_key: Variant in (value as Dictionary).keys():
			result[str(raw_key)] = _normalize((value as Dictionary)[raw_key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_normalize(item))
		return result
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value
