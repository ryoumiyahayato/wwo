class_name AlphaHistoricalWorldEconomyData
extends RefCounted
## Source-gated 1900 country calibration, household budgets and transport skeleton.
## The compact tables preserve numeric bounds and confidence while avoiding repeated metadata.

const WORLD_MANIFEST_PATH := "res://data/alpha/historical_world_economy_1900.json"
const HOUSEHOLD_BUDGET_PATH := "res://data/alpha/historical_household_budgets_1900.json"
const TRANSPORT_MANIFEST_PATH := "res://data/alpha/historical_transport_network_1900.json"

var world_manifest: Dictionary = {}
var household_budgets: Dictionary = {}
var transport_manifest: Dictionary = {}
var countries: Array[Dictionary] = []
var domestic_networks: Array[Dictionary] = []
var maritime_corridors: Array[Dictionary] = []
var river_corridors: Array[Dictionary] = []
var country_by_entity: Dictionary = {}
var budget_by_id: Dictionary = {}
var initialization_error: String = ""


func configure() -> bool:
	initialization_error = ""
	countries.clear()
	domestic_networks.clear()
	maritime_corridors.clear()
	river_corridors.clear()
	country_by_entity.clear()
	budget_by_id.clear()
	world_manifest = _load_document(WORLD_MANIFEST_PATH)
	household_budgets = _load_document(HOUSEHOLD_BUDGET_PATH)
	transport_manifest = _load_document(TRANSPORT_MANIFEST_PATH)
	if world_manifest.is_empty() or household_budgets.is_empty() or transport_manifest.is_empty():
		return false
	if str(world_manifest.get("schema_id", "")) != "historical_world_economy_1900_estimates_v1":
		return _fail("1900世界经济清单 Schema 无效")
	if str(household_budgets.get("schema_id", "")) != "historical_household_budgets_1900_v1":
		return _fail("1900家庭预算 Schema 无效")
	if str(transport_manifest.get("schema_id", "")) != "historical_transport_network_1900_estimates_v1":
		return _fail("1900运输网络清单 Schema 无效")
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
	var result: Array[Dictionary] = []
	var threshold: int = int((world_manifest.get("policy", {}) as Dictionary).get(
		"minimum_formal_confidence_bp", 4500
	))
	for record: Dictionary in countries:
		if (
			bool(record.get("formal_simulation_allowed", false))
			and int(record.get("overall_confidence_bp", 0)) >= threshold
		):
			result.append(record.duplicate(true))
	return result


func coverage_summary() -> Dictionary:
	var summary: Dictionary = (world_manifest.get("coverage_summary", {}) as Dictionary).duplicate(true)
	summary["loaded_country_count"] = countries.size()
	summary["formal_country_count"] = formal_countries().size()
	summary["domestic_network_count"] = domestic_networks.size()
	summary["maritime_corridor_count"] = maritime_corridors.size()
	summary["river_corridor_count"] = river_corridors.size()
	summary["household_budget_count"] = budget_by_id.size()
	return summary


func validate_integrity() -> Dictionary:
	if countries.size() != 50:
		return _result(false, "国家校准记录不是50项")
	if domestic_networks.size() != 50:
		return _result(false, "国内运输记录不是50项")
	if maritime_corridors.size() < 30 or river_corridors.size() < 12:
		return _result(false, "国际海运或河运骨架覆盖不足")
	if budget_by_id.size() < 6:
		return _result(false, "家庭预算模板覆盖不足")
	var seen_ranks: Dictionary = {}
	for record: Dictionary in countries:
		var entity_id: String = str(record.get("entity_id", ""))
		var rank: int = int(record.get("rank", 0))
		if entity_id.is_empty() or country_by_entity.get(entity_id, {}) != record:
			return _result(false, "国家记录索引无效")
		if seen_ranks.has(rank) or rank < 1 or rank > 50:
			return _result(false, "国家优先级缺失或重复")
		seen_ranks[rank] = true
		for field: String in ["population", "gdp_per_capita_2011_intl_dollars", "urban_population_share_bp"]:
			var bounded: Dictionary = record.get(field, {}) as Dictionary
			if float(bounded.get("lower", 0)) > float(bounded.get("value", 0)):
				return _result(false, "估算下界高于中心值：%s/%s" % [entity_id, field])
			if float(bounded.get("value", 0)) > float(bounded.get("upper", 0)):
				return _result(false, "估算中心值高于上界：%s/%s" % [entity_id, field])
			if int(bounded.get("confidence_bp", 0)) <= 0:
				return _result(false, "估算缺少有效置信度：%s/%s" % [entity_id, field])
		if not budget_by_id.has(str(record.get("household_budget_template_id", ""))):
			return _result(false, "国家引用未知家庭预算模板：%s" % entity_id)
	for budget: Dictionary in budget_by_id.values():
		var total: int = 0
		for value: Variant in (budget.get("shares_bp", {}) as Dictionary).values():
			total += int(value)
		if total != 10000:
			return _result(false, "家庭预算份额不等于10000基点")
	return _result(true, "ok")


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
		var record: Dictionary = _expand_country(flat, methods)
		var entity_id: String = str(record.get("entity_id", ""))
		if entity_id.is_empty() or country_by_entity.has(entity_id):
			return _fail("1900国家记录ID缺失或重复")
		countries.append(record)
		country_by_entity[entity_id] = record
	countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 0)) < int(b.get("rank", 0))
	)
	return true


func _expand_country(flat: Dictionary, methods: Dictionary) -> Dictionary:
	return {
		"rank": int(flat.get("rank", 0)),
		"entity_id": str(flat.get("entity_id", "")),
		"primary_iso3": str(flat.get("primary_iso3", "")),
		"population": _bounded(flat, "population", "population", methods),
		"gdp_per_capita_2011_intl_dollars": _bounded(flat, "gdp_pc", "gdp", methods),
		"urban_population_share_bp": _bounded(flat, "urban", "urban", methods),
		"production": {
			"agriculture_capacity_index": int(flat.get("agriculture_capacity_index", 0)),
			"industrial_capacity_index": int(flat.get("industrial_capacity_index", 0)),
			"steel_output_tonnes": int(flat.get("steel_output_tonnes", 0)),
			"primary_energy_coal_equivalent_tonnes": int(flat.get("energy_coal_equivalent_tonnes", 0)),
			"mineral_capacity_index": {
				"coal": int(flat.get("coal_index", 0)),
				"iron_ore": int(flat.get("iron_ore_index", 0)),
				"copper": int(flat.get("copper_index", 0)),
				"petroleum": int(flat.get("petroleum_index", 0)),
				"timber": int(flat.get("timber_index", 0)),
			},
			"confidence_bp": int(flat.get("production_confidence_bp", 0)),
			"method": str(methods.get("production", "")),
		},
		"infrastructure": {
			"rail_route_km": int(flat.get("rail_route_km", 0)),
			"rail_route_km_lower": int(flat.get("rail_lower_km", 0)),
			"rail_route_km_upper": int(flat.get("rail_upper_km", 0)),
			"navigable_waterway_km": int(flat.get("waterway_km", 0)),
			"port_capacity_index": int(flat.get("port_capacity_index", 0)),
			"merchant_shipping_index": int(flat.get("merchant_shipping_index", 0)),
			"major_ports": (flat.get("major_ports", []) as Array).duplicate(),
			"confidence_bp": int(flat.get("infrastructure_confidence_bp", 0)),
			"method": str(methods.get("infrastructure", "")),
		},
		"household_budget_template_id": str(flat.get("household_budget_template_id", "")),
		"overall_confidence_bp": int(flat.get("overall_confidence_bp", 0)),
		"formal_simulation_allowed": bool(flat.get("formal_simulation_allowed", false)),
	}


func _bounded(flat: Dictionary, prefix: String, method_key: String, methods: Dictionary) -> Dictionary:
	var value_key: String = prefix + "_value"
	var lower_key: String = prefix + "_lower"
	var upper_key: String = prefix + "_upper"
	var confidence_key: String = prefix + "_confidence_bp"
	if prefix == "urban":
		value_key = "urban_value_bp"
		lower_key = "urban_lower_bp"
		upper_key = "urban_upper_bp"
	elif prefix == "gdp_pc":
		confidence_key = "gdp_confidence_bp"
	return {
		"value": flat.get(value_key, 0),
		"lower": flat.get(lower_key, 0),
		"upper": flat.get(upper_key, 0),
		"confidence_bp": int(flat.get(confidence_key, 0)),
		"method": str(methods.get(method_key, "bounded_estimate")),
	}


func _load_transport_table() -> bool:
	var table: Dictionary = _load_document(str(transport_manifest.get("compact_table_path", "")))
	if str(table.get("schema_id", "")) != "historical_transport_network_1900_compact_tables_v1":
		return _fail("1900运输紧凑表 Schema 无效")
	domestic_networks = _expand_rows(table, "domestic")
	maritime_corridors = _expand_rows(table, "maritime")
	river_corridors = _expand_rows(table, "river")
	return true


func _expand_rows(table: Dictionary, prefix: String) -> Array[Dictionary]:
	var fields: Array[String] = DataRecordUtils.to_string_array(table.get(prefix + "_field_order", []))
	var result: Array[Dictionary] = []
	for raw_row: Variant in table.get(prefix + "_rows", []) as Array:
		var row: Array = raw_row as Array
		if row.size() != fields.size():
			continue
		var record: Dictionary = {}
		for index: int in fields.size():
			record[fields[index]] = row[index]
		result.append(record)
	return result


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


func _result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message}
