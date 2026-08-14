class_name VNextMarketEconomyCatalog
extends RefCounted
## Reads existing 1900 calibration assets into a vNext-owned static boundary.
## The catalog owns definitions only; mutable inventories and market outcomes
## belong to VNextMarketEconomy.

const COMMODITY_MARKET_PATH: String = "res://data/alpha/commodity_market_1900.json"
const WORLD_PATH: String = "res://data/alpha/world.json"
const INTEGRATION_PATH: String = "res://data/alpha/economy_integration_1900.json"
const HISTORICAL_MANIFEST_PATH: String = "res://data/alpha/historical_world_economy_1900.json"
const HISTORICAL_COUNTRY_TABLE_PATH: String = (
	"res://data/alpha/historical_world_economy_1900/countries_compact.json"
)

const CATEGORY_PRICE_ELASTICITY_BP: Dictionary = {
	"agricultural_food": 1500,
	"agricultural_raw": 1200,
	"colonial_consumable": 3800,
	"energy_raw": 1100,
	"industrial_raw": 1400,
	"mineral_raw": 1000,
	"industrial_intermediate": 1800,
	"mass_manufacture": 2600,
	"processed_food": 2800,
	"textile": 3200,
	"manufactured_good": 3600,
	"capital_good": 2200,
	"local_service": 1800,
	"luxury": 5200,
}

var commodities: Dictionary = {}
var recipes: Dictionary = {}
var production_sites: Dictionary = {}
var regions: Dictionary = {}
var countries: Dictionary = {}
var transport_edges: Array[Dictionary] = []
var trade_relations: Dictionary = {}
var policies: Dictionary = {}
var source_summary: Dictionary = {}
var initialization_error: String = ""

var _source_region_to_market: Dictionary = {}
var _source_country_to_market: Dictionary = {}


func load_1900() -> bool:
	_clear()
	var commodity_document: Dictionary = _read_document(COMMODITY_MARKET_PATH)
	if commodity_document.is_empty():
		return false
	if str(commodity_document.get("schema_id", "")) != "alpha_commodity_market_1900_v1":
		return _fail("商品校准目录 Schema 无效")
	policies = (commodity_document.get("policies", {}) as Dictionary).duplicate(true)
	policies["international_market"] = (
		commodity_document.get("international_market", {}) as Dictionary
	).duplicate(true)
	if not _load_commodities(commodity_document):
		return false
	if not _load_recipes(commodity_document):
		return false

	var world_document: Dictionary = _read_document(WORLD_PATH)
	if world_document.is_empty() or not _load_world_profiles(world_document):
		return false
	if not _load_production_sites(commodity_document):
		return false

	var integration_document: Dictionary = _read_document(INTEGRATION_PATH)
	if integration_document.is_empty() or not _load_logistics(integration_document):
		return false
	if not _load_historical_summary():
		return false

	policies["integration"] = (
		integration_document.get("policies", {}) as Dictionary
	).duplicate(true)
	return validate_integrity()


func region_market_id(source_region_id: String) -> String:
	return str(_source_region_to_market.get(source_region_id, ""))


func country_market_id(source_country_id: String) -> String:
	return str(_source_country_to_market.get(source_country_id, ""))


func source_region_id(market_id: String) -> String:
	return str((regions.get(market_id, {}) as Dictionary).get("source_region_id", ""))


func source_country_id(market_id: String) -> String:
	return str((countries.get(market_id, {}) as Dictionary).get("source_country_id", ""))


func region_market_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in regions:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func country_market_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in countries:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func validate_integrity() -> bool:
	if commodities.size() < 50 or recipes.size() < 20:
		return _fail("商品或生产配方覆盖不足")
	if countries.size() < 2 or regions.size() < 8:
		return _fail("地区或国家市场覆盖不足")
	for commodity_id: String in commodities:
		var commodity: Dictionary = commodities[commodity_id] as Dictionary
		if (
			commodity_id.is_empty()
			or not _is_catalog_token(commodity_id)
			or int(commodity.get("base_price_centimes", 0)) <= 0
			or float(commodity.get("unit_mass_kg", -1.0)) < 0.0
			or float(commodity.get("target_stock_days", 0.0)) < 0.0
		):
			return _fail("商品参数无效：%s" % commodity_id)
	for recipe_id: String in recipes:
		var recipe: Dictionary = recipes[recipe_id] as Dictionary
		if recipe_id.is_empty() or not _flows_are_valid(recipe.get("inputs", [])):
			return _fail("生产配方输入无效：%s" % recipe_id)
		if not _flows_are_valid(recipe.get("outputs", [])):
			return _fail("生产配方输出无效：%s" % recipe_id)
	for site_id: String in production_sites:
		var site: Dictionary = production_sites[site_id] as Dictionary
		if (
			site_id.is_empty()
			or not regions.has(str(site.get("market_id", "")))
			or not recipes.has(str(site.get("recipe_id", "")))
			or float(site.get("capacity_batches_per_day", 0.0)) <= 0.0
		):
			return _fail("生产设施引用无效：%s" % site_id)
	for edge: Dictionary in transport_edges:
		if (
			str(edge.get("edge_id", "")).is_empty()
			or not regions.has(str(edge.get("from_market_id", "")))
			or not regions.has(str(edge.get("to_market_id", "")))
			or float(edge.get("capacity_units_per_day", 0.0)) <= 0.0
			or int(edge.get("duration_hours", 0)) <= 0
		):
			return _fail("运输边引用或容量无效")
	return true


func _clear() -> void:
	commodities.clear()
	recipes.clear()
	production_sites.clear()
	regions.clear()
	countries.clear()
	transport_edges.clear()
	trade_relations.clear()
	policies.clear()
	source_summary.clear()
	initialization_error = ""
	_source_region_to_market.clear()
	_source_country_to_market.clear()


func _load_commodities(document: Dictionary) -> bool:
	for raw_value: Variant in document.get("commodities", []) as Array:
		if not raw_value is Dictionary:
			return _fail("商品记录格式无效")
		var commodity: Dictionary = (raw_value as Dictionary).duplicate(true)
		var commodity_id: String = str(commodity.get("commodity_id", ""))
		if commodity_id.is_empty() or commodities.has(commodity_id):
			return _fail("商品 ID 缺失或重复：%s" % commodity_id)
		commodity["price_elasticity_bp"] = int(
			commodity.get(
				"price_elasticity_bp",
				CATEGORY_PRICE_ELASTICITY_BP.get(str(commodity.get("category", "")), 2200)
			)
		)
		commodity["catalog_source"] = COMMODITY_MARKET_PATH
		commodities[commodity_id] = commodity
	return true


func _load_recipes(document: Dictionary) -> bool:
	for raw_value: Variant in document.get("recipes", []) as Array:
		if not raw_value is Dictionary:
			return _fail("生产配方记录格式无效")
		var recipe: Dictionary = (raw_value as Dictionary).duplicate(true)
		var recipe_id: String = str(recipe.get("recipe_id", ""))
		if recipe_id.is_empty() or recipes.has(recipe_id):
			return _fail("生产配方 ID 缺失或重复：%s" % recipe_id)
		if not _flows_are_valid(recipe.get("inputs", [])) or not _flows_are_valid(
			recipe.get("outputs", [])
		):
			return _fail("生产配方引用无效：%s" % recipe_id)
		recipes[recipe_id] = recipe
	return true


func _load_world_profiles(document: Dictionary) -> bool:
	for raw_value: Variant in document.get("country_profiles", []) as Array:
		if not raw_value is Dictionary:
			return _fail("国家记录格式无效")
		var source: Dictionary = raw_value as Dictionary
		var source_id: String = str(source.get("country_id", ""))
		var market_id: String = _economy_id("country", source_id)
		if source_id.is_empty() or market_id.is_empty() or countries.has(market_id):
			return _fail("国家市场 ID 无效或重复：%s" % source_id)
		var country: Dictionary = source.duplicate(true)
		country["market_id"] = market_id
		country["source_country_id"] = source_id
		country["market_level"] = "country"
		countries[market_id] = country
		_source_country_to_market[source_id] = market_id

	for raw_value: Variant in document.get("region_profiles", []) as Array:
		if not raw_value is Dictionary:
			return _fail("地区记录格式无效")
		var source: Dictionary = raw_value as Dictionary
		var source_id: String = str(source.get("region_id", ""))
		var source_country_id_value: String = str(source.get("country_id", ""))
		var market_id: String = _economy_id("region", source_id)
		var parent_market_id: String = country_market_id(source_country_id_value)
		if (
			source_id.is_empty()
			or market_id.is_empty()
			or regions.has(market_id)
			or parent_market_id.is_empty()
		):
			return _fail("地区市场引用无效：%s" % source_id)
		var region: Dictionary = source.duplicate(true)
		region["market_id"] = market_id
		region["source_region_id"] = source_id
		region["country_market_id"] = parent_market_id
		region["market_level"] = "region"
		regions[market_id] = region
		_source_region_to_market[source_id] = market_id
	return true


func _load_production_sites(document: Dictionary) -> bool:
	var overrides: Dictionary = document.get("region_overrides", {}) as Dictionary
	for raw_value: Variant in document.get("production_sites", []) as Array:
		if not raw_value is Dictionary:
			return _fail("生产设施记录格式无效")
		var source: Dictionary = raw_value as Dictionary
		var site_id: String = str(source.get("site_id", ""))
		var source_region_id: String = str(source.get("region_id", ""))
		var market_id: String = region_market_id(source_region_id)
		var recipe_id: String = str(source.get("recipe_id", ""))
		if (
			site_id.is_empty()
			or production_sites.has(site_id)
			or market_id.is_empty()
			or not recipes.has(recipe_id)
		):
			return _fail("生产设施引用无效：%s" % site_id)
		var site: Dictionary = source.duplicate(true)
		site["market_id"] = market_id
		site["source_region_id"] = source_region_id
		site["operating_target_bp"] = int(source.get("opening_operating_bp", 9000))
		site["technology_efficiency_bp"] = int(source.get("technology_efficiency_bp", 10000))
		site["region_override"] = (
		(overrides.get(source_region_id, {}) as Dictionary).duplicate(true)
		if overrides.has(source_region_id)
		else {}
	)
		production_sites[site_id] = site
	return true


func _load_logistics(document: Dictionary) -> bool:
	var raw_edges: Array = document.get("transport_edges", []) as Array
	for raw_value: Variant in raw_edges:
		if not raw_value is Dictionary:
			return _fail("运输边记录格式无效")
		var source: Dictionary = raw_value as Dictionary
		var from_market_id: String = region_market_id(str(source.get("from_region_id", "")))
		var to_market_id: String = region_market_id(str(source.get("to_region_id", "")))
		var edge_id: String = str(source.get("edge_id", ""))
		if (
			edge_id.is_empty()
			or from_market_id.is_empty()
			or to_market_id.is_empty()
			or float(source.get("capacity_units_per_day", 0.0)) <= 0.0
		):
			return _fail("运输边引用无效：%s" % edge_id)
		var edge: Dictionary = source.duplicate(true)
		edge["from_market_id"] = from_market_id
		edge["to_market_id"] = to_market_id
		edge["duration_hours"] = maxi(1, int(source.get("duration_hours", 0)))
		edge["distance_days"] = float(edge["duration_hours"]) / 24.0
		transport_edges.append(edge)

	for raw_value: Variant in document.get("trade_relations", []) as Array:
		if not raw_value is Dictionary:
			return _fail("贸易关系记录格式无效")
		var relation: Dictionary = raw_value as Dictionary
		var exporter: String = country_market_id(str(relation.get("exporter_country_id", "")))
		var importer: String = country_market_id(str(relation.get("importer_country_id", "")))
		var key: String = _trade_key(exporter, importer)
		if exporter.is_empty() or importer.is_empty() or trade_relations.has(key):
			return _fail("贸易关系引用无效")
		var normalized: Dictionary = relation.duplicate(true)
		normalized["exporter_market_id"] = exporter
		normalized["importer_market_id"] = importer
		trade_relations[key] = normalized
	return not transport_edges.is_empty()


func _load_historical_summary() -> bool:
	var manifest: Dictionary = _read_document(HISTORICAL_MANIFEST_PATH)
	var compact: Dictionary = _read_document(HISTORICAL_COUNTRY_TABLE_PATH)
	if manifest.is_empty() or compact.is_empty():
		return false
	if str(manifest.get("schema_id", "")) != "historical_world_economy_1900_estimates_v1":
		return _fail("1900历史经济 manifest Schema 无效")
	var field_order: Array = compact.get("field_order", []) as Array
	var rows: Array = compact.get("rows", []) as Array
	var index_by_field: Dictionary = {}
	for index: int in range(field_order.size()):
		index_by_field[str(field_order[index])] = index
	for field: String in [
		"entity_id", "population_value", "gdp_pc_value", "formal_simulation_allowed"
	]:
		if not index_by_field.has(field):
			return _fail("1900历史经济字段缺失：%s" % field)
	var formal_count: int = 0
	var population_total: int = 0
	for row_value: Variant in rows:
		if not row_value is Array:
			return _fail("1900历史经济紧凑行格式无效")
		var row: Array = row_value as Array
		if row.size() != field_order.size():
			return _fail("1900历史经济紧凑行长度无效")
		if bool(row[int(index_by_field["formal_simulation_allowed"])]):
			formal_count += 1
		population_total += int(row[int(index_by_field["population_value"])])
	source_summary = {
		"commodity_schema_id": "alpha_commodity_market_1900_v1",
		"commodity_count": commodities.size(),
		"historical_country_table_schema_id": str(compact.get("schema_id", "")),
		"historical_country_count": rows.size(),
		"historical_formal_simulation_allowed_count": formal_count,
		"historical_population_total": population_total,
		"historical_manifest_path": HISTORICAL_MANIFEST_PATH,
		"transport_source_path": INTEGRATION_PATH,
	}
	return true


func _flows_are_valid(raw_value: Variant) -> bool:
	if not raw_value is Array:
		return false
	for flow_value: Variant in raw_value as Array:
		if not flow_value is Dictionary:
			return false
		var flow: Dictionary = flow_value as Dictionary
		if (
			not commodities.has(str(flow.get("commodity_id", "")))
			or float(flow.get("units", 0.0)) <= 0.0
		):
			return false
	return true


func _economy_id(prefix: String, source_id: String) -> String:
	if source_id.is_empty():
		return ""
	var local_id: String = source_id.replace(":", "_")
	return VNextStableId.compose("economy", "%s_%s" % [prefix, local_id])


func _trade_key(exporter: String, importer: String) -> String:
	return exporter + ">" + importer


func _is_catalog_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var character: String = value.substr(index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true


func _read_document(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail_value("无法读取经济数据：%s" % path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return _fail_value("经济数据 JSON 无效：%s" % path)
	return (parser.data as Dictionary).duplicate(true)


func _fail_value(message: String) -> Dictionary:
	initialization_error = message
	return {}


func _fail(message: String) -> bool:
	initialization_error = message
	return false
