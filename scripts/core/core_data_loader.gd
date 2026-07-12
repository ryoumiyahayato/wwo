class_name CoreDataLoader
extends RefCounted
## Loads core JSON data in two phases: record shape/ID validation, then typed
## model construction and cross-reference validation. Invalid content never throws.

const SCHEMA_VERSION: int = 1
const COLLECTIONS: PackedStringArray = [
	"countries",
	"regions",
	"control_units",
	"population_groups",
	"characters",
	"organizations",
	"relationships",
	"actions",
]
const ID_NAMESPACES: Dictionary = {
	"countries": "country",
	"regions": "region",
	"control_units": "control",
	"population_groups": "population",
	"characters": "character",
	"organizations": "organization",
	"relationships": "relationship",
	"actions": "action",
}


func load_from_file(path: String) -> CoreDataLoadResult:
	var result := CoreDataLoadResult.new()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.add_error("无法读取核心数据：%s" % path)
		return result

	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		result.add_error("JSON 无效（第 %d 行）：%s" % [
			parser.get_error_line(), parser.get_error_message()
		])
		return result
	if not parser.data is Dictionary:
		result.add_error("核心数据顶层必须是对象")
		return result
	return load_from_dictionary(parser.data as Dictionary)


func load_from_dictionary(data: Dictionary) -> CoreDataLoadResult:
	var result := CoreDataLoadResult.new()
	_validate_top_level(data, result)
	if not result.errors.is_empty():
		return result

	var all_ids: Dictionary = {}
	for collection_name: String in COLLECTIONS:
		var records: Array = data[collection_name] as Array
		for index: int in range(records.size()):
			var path: String = "%s[%d]" % [collection_name, index]
			if not records[index] is Dictionary:
				result.add_error("%s 必须是对象" % path)
				continue
			var record: Dictionary = records[index] as Dictionary
			_validate_record_shape(collection_name, record, path, result)
			_register_id(collection_name, record, path, all_ids, result)
	if not result.errors.is_empty():
		return result

	var data_set: CoreDataSet = _construct_data_set(data)
	_validate_references(data_set, result)
	if result.errors.is_empty():
		result.data_set = data_set
	return result


func _validate_top_level(data: Dictionary, result: CoreDataLoadResult) -> void:
	if not data.has("schema_version") or not _is_integer_number(data["schema_version"]):
		result.add_error("schema_version 必须是整数")
	elif int(data["schema_version"]) != SCHEMA_VERSION:
		result.add_error("不支持的 schema_version：%s" % data["schema_version"])
	for collection_name: String in COLLECTIONS:
		if not data.has(collection_name) or not data[collection_name] is Array:
			result.add_error("顶层字段 %s 必须是数组" % collection_name)


func _register_id(
	collection_name: String,
	record: Dictionary,
	path: String,
	all_ids: Dictionary,
	result: CoreDataLoadResult
) -> void:
	if not record.has("id") or not record["id"] is String:
		return
	var entity_id: String = record["id"] as String
	if not StableIdService.is_valid_id(entity_id):
		result.add_error("%s.id 不是有效稳定 ID：%s" % [path, entity_id])
		return
	var expected_namespace: String = str(ID_NAMESPACES[collection_name])
	if StableIdService.get_namespace(entity_id) != expected_namespace:
		result.add_error("%s.id 必须使用命名空间 %s" % [path, expected_namespace])
	if all_ids.has(entity_id):
		result.add_error("重复 ID %s（%s 与 %s）" % [entity_id, all_ids[entity_id], path])
	else:
		all_ids[entity_id] = path


func _validate_record_shape(
	collection_name: String,
	record: Dictionary,
	path: String,
	result: CoreDataLoadResult
) -> void:
	_require_string(record, "id", path, result)
	match collection_name:
		"countries":
			_require_string(record, "name", path, result)
			_require_string_array(record, "region_ids", path, result)
			_require_dictionary(record, "public_status", path, result)
		"regions":
			_require_string(record, "name", path, result)
			_require_string(record, "de_jure_country_id", path, result)
			_require_string_array(record, "population_group_ids", path, result)
			_require_string_array(record, "city_names", path, result)
			_require_dictionary(record, "resources", path, result)
			_require_dictionary(record, "infrastructure", path, result)
			_require_string_array(record, "organization_ids", path, result)
			_require_dictionary(record, "social_influence", path, result)
		"control_units":
			_require_string(record, "region_id", path, result)
			_require_integer(record, "grid_x", path, result, 0)
			_require_integer(record, "grid_y", path, result, 0)
			_require_string(record, "city_name", path, result, true)
			_require_string_array(record, "neighbor_ids", path, result)
			_require_string(record, "de_jure_country_id", path, result)
			_require_string(record, "controller_country_id", path, result, true)
			for field: String in [
				"control_strength", "contested_level", "garrison_pressure",
				"enemy_pressure", "social_support"
			]:
				_require_number(record, field, path, result, 0.0, 1.0)
			_require_string_array(record, "railroad_neighbor_ids", path, result)
			_require_string(record, "infrastructure_state", path, result)
		"population_groups":
			_require_string(record, "region_id", path, result)
			_require_integer(record, "population_count", path, result, 0)
			_require_string(record, "social_class", path, result)
			_require_string(record, "occupation_category", path, result)
			_require_number(record, "average_income", path, result, 0.0)
			_require_number(record, "average_education", path, result, 0.0, 1.0)
			_require_number(record, "unemployment_rate", path, result, 0.0, 1.0)
			_require_dictionary(record, "public_political_leaning", path, result)
			_require_string(record, "basic_living_state", path, result)
		"characters":
			_require_string(record, "name", path, result)
			_require_integer(record, "age", path, result, 0)
			_require_string(record, "country_id", path, result)
			_require_string(record, "region_id", path, result)
			_require_string(record, "occupation_id", path, result)
			_require_string(record, "occupation", path, result)
			_require_string(record, "public_position", path, result, true)
			_require_string_array(record, "organization_ids", path, result)
			_require_string_array(record, "relationship_ids", path, result)
			_require_dictionary(record, "hidden_aptitudes", path, result)
			_require_dictionary(record, "temperament_weights", path, result)
			_require_dictionary(record, "skills", path, result)
			_require_string_array(record, "manifested_traits", path, result)
			_require_dictionary(record, "tendencies", path, result)
			_require_dictionary(record, "known_tendencies", path, result)
			_require_dictionary(record, "current_status", path, result)
			_require_bool(record, "is_active", path, result)
			_require_string(record, "random_mode", path, result, true)
			_require_string(record, "random_category", path, result, true)
			_require_bool(record, "is_challenge_start", path, result)
			_require_integer(record, "generation_seed", path, result, -9223372036854775807)
			_require_integer(record, "random_state", path, result, -9223372036854775807)
		"organizations":
			for field: String in ["name", "type", "country_id"]:
				_require_string(record, field, path, result)
			_require_string(record, "region_id", path, result, true)
			for field: String in ["size", "resources", "influence"]:
				_require_number(record, field, path, result, 0.0)
			_require_string(record, "public_stance", path, result)
			_require_string(record, "leader_character_id", path, result, true)
			_require_string_array(record, "member_ids", path, result)
			_require_dictionary(record, "position_structure", path, result)
			_require_dictionary(record, "organization_relations", path, result)
		"relationships":
			_require_string(record, "character_a_id", path, result)
			_require_string(record, "character_b_id", path, result)
			_require_number(record, "familiarity", path, result, 0.0, 1.0)
			_require_number(record, "trust", path, result, -1.0, 1.0)
			_require_number(record, "affinity", path, result, -1.0, 1.0)
			_require_string(record, "interest_link", path, result, true)
			_require_bool(record, "is_public", path, result)
			_require_integer(record, "last_interaction_hour", path, result, 0)
		"actions":
			for field: String in ["name", "category", "primary_skill"]:
				_require_string(record, field, path, result)
			_require_number(record, "total_work", path, result, 0.000001)
			_require_number(record, "base_progress_per_hour", path, result, 0.000001)
			_require_string_array(record, "secondary_skills", path, result)
			_require_number(record, "aptitude_modifier_weight", path, result, 0.0)
			_require_string(record, "position_permission_required", path, result, true)
			for field: String in [
				"organization_support_weight", "relationship_support_weight",
				"funding_weight", "preparation_weight", "state_modifier_weight",
				"base_target_resistance"
			]:
				_require_number(record, field, path, result, 0.0)
			_require_string_array(record, "interruption_conditions", path, result)
			_require_number(record, "success_threshold", path, result)
			_require_number(record, "guaranteed_success_threshold", path, result)
			_require_dictionary(record, "success_result", path, result)
			_require_dictionary(record, "failure_result", path, result)
			if _has_number(record, "success_threshold") and _has_number(
				record, "guaranteed_success_threshold"
			) and float(record["guaranteed_success_threshold"]) < float(record["success_threshold"]):
				result.add_error("%s.guaranteed_success_threshold 不得小于 success_threshold" % path)


func _construct_data_set(data: Dictionary) -> CoreDataSet:
	var data_set := CoreDataSet.new()
	for record: Dictionary in data["countries"] as Array:
		var model: CountryData = CountryData.from_dict(record)
		data_set.countries[model.id] = model
	for record: Dictionary in data["regions"] as Array:
		var model: RegionData = RegionData.from_dict(record)
		data_set.regions[model.id] = model
	for record: Dictionary in data["control_units"] as Array:
		var model: ControlUnitData = ControlUnitData.from_dict(record)
		data_set.control_units[model.id] = model
	for record: Dictionary in data["population_groups"] as Array:
		var model: PopulationGroupData = PopulationGroupData.from_dict(record)
		data_set.population_groups[model.id] = model
	for record: Dictionary in data["characters"] as Array:
		var model: CharacterData = CharacterData.from_dict(record)
		data_set.characters[model.id] = model
	for record: Dictionary in data["organizations"] as Array:
		var model: OrganizationData = OrganizationData.from_dict(record)
		data_set.organizations[model.id] = model
	for record: Dictionary in data["relationships"] as Array:
		var model: RelationshipData = RelationshipData.from_dict(record)
		data_set.relationships[model.id] = model
	for record: Dictionary in data["actions"] as Array:
		var model: ActionDefinitionData = ActionDefinitionData.from_dict(record)
		data_set.actions[model.id] = model
	return data_set


func _validate_references(data_set: CoreDataSet, result: CoreDataLoadResult) -> void:
	var occupied_grid_positions: Dictionary = {}
	for country_value: Variant in data_set.countries.values():
		var country: CountryData = country_value as CountryData
		_validate_reference_array(country.region_ids, data_set.regions, country.id + ".region_ids", result)
		for region_id: String in country.region_ids:
			if data_set.regions.has(region_id):
				var region: RegionData = data_set.regions[region_id] as RegionData
				if region.de_jure_country_id != country.id:
					result.add_error("%s 声明地区 %s，但其法理国家为 %s" % [
						country.id, region_id, region.de_jure_country_id
					])

	for region_value: Variant in data_set.regions.values():
		var region: RegionData = region_value as RegionData
		_validate_reference(region.de_jure_country_id, data_set.countries, region.id + ".de_jure_country_id", result)
		_validate_reference_array(region.population_group_ids, data_set.population_groups, region.id + ".population_group_ids", result)
		_validate_reference_array(region.organization_ids, data_set.organizations, region.id + ".organization_ids", result)

	for unit_value: Variant in data_set.control_units.values():
		var unit: ControlUnitData = unit_value as ControlUnitData
		var position_key: String = "%d,%d" % [unit.grid_x, unit.grid_y]
		if occupied_grid_positions.has(position_key):
			result.add_error("控制单元 %s 与 %s 使用重复网格坐标 %s" % [
				unit.id, occupied_grid_positions[position_key], position_key
			])
		else:
			occupied_grid_positions[position_key] = unit.id
		_validate_reference(unit.region_id, data_set.regions, unit.id + ".region_id", result)
		_validate_reference(unit.de_jure_country_id, data_set.countries, unit.id + ".de_jure_country_id", result)
		if not unit.controller_country_id.is_empty():
			_validate_reference(unit.controller_country_id, data_set.countries, unit.id + ".controller_country_id", result)
		_validate_reference_array(unit.neighbor_ids, data_set.control_units, unit.id + ".neighbor_ids", result)
		_validate_reference_array(unit.railroad_neighbor_ids, data_set.control_units, unit.id + ".railroad_neighbor_ids", result)
		if unit.neighbor_ids.has(unit.id):
			result.add_error("%s 不能与自身相邻" % unit.id)
		for neighbor_id: String in unit.neighbor_ids:
			if data_set.control_units.has(neighbor_id):
				var neighbor: ControlUnitData = data_set.control_units[neighbor_id] as ControlUnitData
				if not neighbor.neighbor_ids.has(unit.id):
					result.add_error("邻接必须对称：%s 引用 %s，但反向不存在" % [unit.id, neighbor_id])
		for rail_neighbor_id: String in unit.railroad_neighbor_ids:
			if not unit.neighbor_ids.has(rail_neighbor_id):
				result.add_error("%s 的铁路连接 %s 不是相邻单元" % [unit.id, rail_neighbor_id])
		if not unit.city_name.is_empty() and data_set.regions.has(unit.region_id):
			var city_region: RegionData = data_set.regions[unit.region_id] as RegionData
			if not city_region.city_names.has(unit.city_name):
				result.add_error("%s 的城市 %s 未在地区 %s 声明" % [
					unit.id, unit.city_name, unit.region_id
				])

	for population_value: Variant in data_set.population_groups.values():
		var population: PopulationGroupData = population_value as PopulationGroupData
		_validate_reference(population.region_id, data_set.regions, population.id + ".region_id", result)

	for character_value: Variant in data_set.characters.values():
		var character: CharacterData = character_value as CharacterData
		_validate_reference(character.country_id, data_set.countries, character.id + ".country_id", result)
		_validate_reference(character.region_id, data_set.regions, character.id + ".region_id", result)
		_validate_reference_array(character.organization_ids, data_set.organizations, character.id + ".organization_ids", result)
		_validate_reference_array(character.relationship_ids, data_set.relationships, character.id + ".relationship_ids", result)

	for organization_value: Variant in data_set.organizations.values():
		var organization: OrganizationData = organization_value as OrganizationData
		_validate_reference(organization.country_id, data_set.countries, organization.id + ".country_id", result)
		if not organization.region_id.is_empty():
			_validate_reference(organization.region_id, data_set.regions, organization.id + ".region_id", result)
		if not organization.leader_character_id.is_empty():
			_validate_reference(organization.leader_character_id, data_set.characters, organization.id + ".leader_character_id", result)
		_validate_reference_array(organization.member_ids, data_set.characters, organization.id + ".member_ids", result)
		_validate_organization_structure(organization, data_set, result)

	for relationship_value: Variant in data_set.relationships.values():
		var relationship: RelationshipData = relationship_value as RelationshipData
		_validate_reference(relationship.character_a_id, data_set.characters, relationship.id + ".character_a_id", result)
		_validate_reference(relationship.character_b_id, data_set.characters, relationship.id + ".character_b_id", result)
		if relationship.character_a_id == relationship.character_b_id:
			result.add_error("%s 的关系双方不能是同一人物" % relationship.id)


func _validate_organization_structure(
	organization: OrganizationData, data_set: CoreDataSet, result: CoreDataLoadResult
) -> void:
	var structure: Dictionary = organization.position_structure
	if not structure.has("entry_position") or not structure["entry_position"] is String or not structure.has("leader_position") or not structure["leader_position"] is String or not structure.has("positions") or not structure["positions"] is Dictionary:
		result.add_error("%s.position_structure 缺少有效入口、领导职位或职位表" % organization.id)
		return
	var positions: Dictionary = structure["positions"] as Dictionary
	for required_position: String in [str(structure["entry_position"]), str(structure["leader_position"])]:
		if not positions.has(required_position):
			result.add_error("%s 缺少声明职位：%s" % [organization.id, required_position])
	for raw_position_id: Variant in positions:
		var position_id: String = str(raw_position_id)
		if not positions[raw_position_id] is Dictionary:
			result.add_error("%s.positions.%s 必须是对象" % [organization.id, position_id])
			continue
		var position: Dictionary = positions[raw_position_id] as Dictionary
		if not position.has("name") or not position["name"] is String or not position.has("level") or not _is_integer_number(position["level"]) or not position.has("slots") or not _is_integer_number(position["slots"]) or int(position["slots"]) < 1:
			result.add_error("%s.positions.%s 的名称、等级或槽位无效" % [organization.id, position_id])
		if not position.has("permissions") or not position["permissions"] is Array or not position.has("holder_ids") or not position["holder_ids"] is Array:
			result.add_error("%s.positions.%s 的权限或任职者数组无效" % [organization.id, position_id])
	for raw_related_id: Variant in organization.organization_relations:
		var related_id: String = str(raw_related_id)
		_validate_reference(related_id, data_set.organizations, organization.id + ".organization_relations", result)
		if related_id == organization.id:
			result.add_error("%s 不得声明自身组织关系" % organization.id)
		var value: Variant = organization.organization_relations[raw_related_id]
		if not value is int and not value is float or float(value) < -1.0 or float(value) > 1.0:
			result.add_error("%s 与 %s 的组织关系必须位于 -1 至 1" % [organization.id, related_id])


func _validate_reference(
	entity_id: String,
	index: Dictionary,
	path: String,
	result: CoreDataLoadResult
) -> void:
	if not index.has(entity_id):
		result.add_error("%s 引用不存在的 ID：%s" % [path, entity_id])


func _validate_reference_array(
	entity_ids: Array[String],
	index: Dictionary,
	path: String,
	result: CoreDataLoadResult
) -> void:
	for entity_id: String in entity_ids:
		_validate_reference(entity_id, index, path, result)


func _require_string(
	record: Dictionary,
	field: String,
	path: String,
	result: CoreDataLoadResult,
	allow_empty: bool = false
) -> void:
	if not record.has(field) or not record[field] is String:
		result.add_error("%s.%s 必须是字符串" % [path, field])
		return
	if not allow_empty and (record[field] as String).is_empty():
		result.add_error("%s.%s 不得为空" % [path, field])


func _require_string_array(
	record: Dictionary,
	field: String,
	path: String,
	result: CoreDataLoadResult
) -> void:
	if not record.has(field) or not record[field] is Array:
		result.add_error("%s.%s 必须是数组" % [path, field])
		return
	var seen: Dictionary = {}
	for index: int in range((record[field] as Array).size()):
		var value: Variant = (record[field] as Array)[index]
		if not value is String or (value as String).is_empty():
			result.add_error("%s.%s[%d] 必须是非空字符串" % [path, field, index])
			continue
		if seen.has(value):
			result.add_error("%s.%s 包含重复值：%s" % [path, field, value])
		else:
			seen[value] = true


func _require_dictionary(
	record: Dictionary,
	field: String,
	path: String,
	result: CoreDataLoadResult
) -> void:
	if not record.has(field) or not record[field] is Dictionary:
		result.add_error("%s.%s 必须是对象" % [path, field])


func _require_bool(
	record: Dictionary,
	field: String,
	path: String,
	result: CoreDataLoadResult
) -> void:
	if not record.has(field) or not record[field] is bool:
		result.add_error("%s.%s 必须是布尔值" % [path, field])


func _require_integer(
	record: Dictionary,
	field: String,
	path: String,
	result: CoreDataLoadResult,
	minimum: int
) -> void:
	if not record.has(field) or not _is_integer_number(record[field]):
		result.add_error("%s.%s 必须是整数" % [path, field])
		return
	if int(record[field]) < minimum:
		result.add_error("%s.%s 不得小于 %d" % [path, field, minimum])


func _require_number(
	record: Dictionary,
	field: String,
	path: String,
	result: CoreDataLoadResult,
	minimum: float = -INF,
	maximum: float = INF
) -> void:
	if not record.has(field) or not _is_number(record[field]):
		result.add_error("%s.%s 必须是数字" % [path, field])
		return
	var value: float = float(record[field])
	if value < minimum or value > maximum:
		result.add_error("%s.%s 必须在 %s 至 %s 之间" % [path, field, minimum, maximum])


static func _has_number(record: Dictionary, field: String) -> bool:
	return record.has(field) and _is_number(record[field])


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and float(value) == floor(float(value))
