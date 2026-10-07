class_name AlphaHistoricalWorldEconomyData
extends RefCounted
## Source-gated 1900 country calibration, household budgets and transport skeleton.
## The compact tables preserve numeric bounds and confidence while avoiding repeated metadata.

const WORLD_MANIFEST_PATH := "res://data/alpha/historical_world_economy_1900.json"
const HOUSEHOLD_BUDGET_PATH := "res://data/alpha/historical_household_budgets_1900.json"
const TRANSPORT_MANIFEST_PATH := "res://data/alpha/historical_transport_network_1900.json"
const COVERAGE_REGISTRY_PATH := "res://data/alpha/historical_economy_coverage_1900.json"

var world_manifest: Dictionary = {}
var household_budgets: Dictionary = {}
var transport_manifest: Dictionary = {}
var coverage_registry: Dictionary = {}
var countries: Array[Dictionary] = []
var domestic_networks: Array[Dictionary] = []
var maritime_corridors: Array[Dictionary] = []
var river_corridors: Array[Dictionary] = []
var country_by_entity: Dictionary = {}
var budget_by_id: Dictionary = {}
var coverage_by_entity: Dictionary = {}
var initialization_error: String = ""


func configure() -> bool:
	initialization_error = ""
	countries.clear()
	domestic_networks.clear()
	maritime_corridors.clear()
	river_corridors.clear()
	country_by_entity.clear()
	budget_by_id.clear()
	coverage_by_entity.clear()
	world_manifest = _load_document(WORLD_MANIFEST_PATH)
	household_budgets = _load_document(HOUSEHOLD_BUDGET_PATH)
	transport_manifest = _load_document(TRANSPORT_MANIFEST_PATH)
	coverage_registry = _load_document(COVERAGE_REGISTRY_PATH)
	if (
		world_manifest.is_empty()
		or household_budgets.is_empty()
		or transport_manifest.is_empty()
		or coverage_registry.is_empty()
	):
		return false
	if str(world_manifest.get("schema_id", "")) != "historical_world_economy_1900_estimates_v1":
		return _fail("1900世界经济清单 Schema 无效")
	if str(household_budgets.get("schema_id", "")) != "historical_household_budgets_1900_v1":
		return _fail("1900家庭预算 Schema 无效")
	if str(transport_manifest.get("schema_id", "")) != "historical_transport_network_1900_estimates_v1":
		return _fail("1900运输网络清单 Schema 无效")
	if str(coverage_registry.get("schema_id", "")) != "historical_economy_coverage_1900_v1":
		return _fail("1900经济覆盖登记表 Schema 无效")
	_load_coverage_registry()
	if not _load_country_table():
		return false
	if not _load_transport_table():
		return false
	for raw_budget: Variant in household_budgets.get("templates", []) as Array:
		if not raw_budget is Dictionary:
			continue
		var budget: Dictionary = (raw_budget as Dictionary).duplicate(true)
		var budget_id: String = str(budget.get("template_id", ""))
		if not budget_id.is_empty():
			budget_by_id[budget_id] = budget
	var integrity: Dictionary = validate_integrity()
	if not bool(integrity.get("success", false)):
		return _fail(str(integrity.get("message", "1900世界经济数据完整性失败")))
	return true


func country(entity_id: String) -> Dictionary:
	return (country_by_entity.get(entity_id, {}) as Dictionary).duplicate(true)


func formal_countries() -> Array[Dictionary]:
	return FormalWorldEconomicEvidenceCatalog.admit_country_records(world_manifest, countries, coverage_by_entity)


func simulation_countries() -> Array[Dictionary]:
	return FormalWorldEconomicEvidenceCatalog.simulation_country_records(countries, coverage_by_entity, coverage_registry, formal_countries())


func _load_coverage_registry() -> void:
	coverage_by_entity.clear()
	for raw_record: Variant in coverage_registry.get("countries", []) as Array:
		if not raw_record is Dictionary:
			continue
		var record := (raw_record as Dictionary).duplicate(true)
		var entity_id := str(record.get("entity_id", ""))
		if not entity_id.is_empty():
			coverage_by_entity[entity_id] = record


func coverage_summary() -> Dictionary:
	var summary: Dictionary = (world_manifest.get("coverage_summary", {}) as Dictionary).duplicate(true)
	summary["loaded_country_count"] = countries.size()
	summary["formal_country_count"] = formal_countries().size()
	summary["bounded_simulation_country_count"] = simulation_countries().size()
	summary["coverage_registry_country_count"] = coverage_by_entity.size()
	summary["domestic_network_count"] = domestic_networks.size()
	summary["maritime_corridor_count"] = maritime_corridors.size()
	summary["river_corridor_count"] = river_corridors.size()
	summary["household_budget_count"] = budget_by_id.size()
	return summary


func validate_integrity() -> Dictionary:
	return FormalWorldEconomicEvidenceCatalog.validate_historical_records(countries, country_by_entity, domestic_networks, maritime_corridors, river_corridors, budget_by_id)


func _load_country_table() -> bool:
	var table_path: String = str(world_manifest.get("compact_country_table_path", ""))
	var table: Dictionary = _load_document(table_path)
	if str(table.get("schema_id", "")) != "historical_world_economy_1900_compact_country_table_v1":
		return _fail("1900国家紧凑表 Schema 无效")
	var fields: Array[String] = DataRecordUtils.to_string_array(table.get("field_order", []))
	var methods: Dictionary = table.get("common_methods", {}) as Dictionary
	for raw_row: Variant in table.get("rows", []) as Array:
		if not raw_row is Array:
			return _fail("1900国家紧凑表行格式无效")
		var values: Array = raw_row as Array
		if values.size() != fields.size():
			return _fail("1900国家紧凑表列数不一致")
		var flat: Dictionary = {}
		for index: int in fields.size():
			flat[fields[index]] = values[index]
		var record: Dictionary = FormalWorldEconomicEvidenceCatalog.expand_country_row(flat, methods)
		var entity_id: String = str(record.get("entity_id", ""))
		if entity_id.is_empty() or country_by_entity.has(entity_id):
			return _fail("1900国家记录ID缺失或重复")
		countries.append(record)
		country_by_entity[entity_id] = record
	countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 0)) < int(b.get("rank", 0))
	)
	return true


func _load_transport_table() -> bool:
	var table: Dictionary = _load_document(str(transport_manifest.get("compact_table_path", "")))
	if str(table.get("schema_id", "")) != "historical_transport_network_1900_compact_tables_v1":
		return _fail("1900运输紧凑表 Schema 无效")
	domestic_networks = FormalWorldEconomicEvidenceCatalog.expand_transport_rows(table, "domestic")
	maritime_corridors = FormalWorldEconomicEvidenceCatalog.expand_transport_rows(table, "maritime")
	river_corridors = FormalWorldEconomicEvidenceCatalog.expand_transport_rows(table, "river")
	return true


func _load_document(path: String) -> Dictionary:
	if path.is_empty():
		_fail("历史经济数据路径为空")
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取历史经济数据：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("历史经济JSON无效：%s" % path)
		return {}
	return (parsed as Dictionary).duplicate(true)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
