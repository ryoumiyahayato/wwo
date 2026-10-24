class_name FormalWorldEconomicEvidenceCatalog
extends RefCounted
## Composition-owned, immutable bootstrap evidence for the formal economy.
## It owns source loading; the economy receives snapshots and never opens data files.

const REVISION: String = "formal_economic_evidence_1900_v1"
const POPULATION_REVISION: String = "formal_population_input_1900_v1"
const WORLD_MANIFEST_PATH: String = "res://data/alpha/historical_world_economy_1900.json"
const HOUSEHOLD_BUDGET_PATH: String = "res://data/alpha/historical_household_budgets_1900.json"
const TRANSPORT_MANIFEST_PATH: String = "res://data/alpha/historical_transport_network_1900.json"
const COVERAGE_REGISTRY_PATH: String = "res://data/alpha/historical_economy_coverage_1900.json"
const COMMODITY_PATH: String = "res://data/alpha/commodity_market_1900.json"
const CROSSWALK_PATH: String = (
	"res://data/world_map/historical/major_economy_polity_crosswalk_1900.json"
)
const SOURCE_PATHS: Array[String] = [
	WORLD_MANIFEST_PATH,
	HOUSEHOLD_BUDGET_PATH,
	TRANSPORT_MANIFEST_PATH,
	COVERAGE_REGISTRY_PATH,
	"res://data/alpha/historical_world_economy_1900/countries_compact.json",
	"res://data/alpha/historical_transport_network_1900/transport_compact.json",
	COMMODITY_PATH,
	CROSSWALK_PATH,
]

var initialization_error: String = ""
var _configured: bool = false
var _fingerprint: String = ""
var _population_fingerprint: String = ""
var _economic_snapshot: Dictionary = {}
var _population_snapshot: Dictionary = {}


func configure(provenance_gate: HistoricalProvenanceGate = null) -> bool:
	if _configured:
		return _fail("Formal economic evidence is already initialized")
	initialization_error = ""
	if provenance_gate == null:
		return _fail("Formal economic evidence requires provenance admission")
	var historical := _load_historical_inputs()
	if historical.is_empty():
		return false
	var commodity_document := _read_document(COMMODITY_PATH)
	var crosswalk_document := _read_document(CROSSWALK_PATH)
	if commodity_document.is_empty() or crosswalk_document.is_empty():
		return false
	if str(commodity_document.get("schema_id", "")) != "alpha_commodity_market_1900_v1":
		return _fail("1900商品目录 Schema 无效")
	if (
		str(crosswalk_document.get("schema_id", ""))
		!= "major_economy_polity_crosswalk_1900_v1"
	):
		return _fail("主要经济体与政治单元交叉表 Schema 无效")

	var economic_records: Array[Dictionary] = []
	var population_records: Array[Dictionary] = []
	var population_date := str(historical["calibration_date"])
	if population_date.is_empty():
		return _fail("正式人口输入缺少 calibration_date")
	for source_record: Dictionary in historical["countries"]:
		var economic_record := source_record.duplicate(true)
		var economy_entity_id := str(source_record.get("entity_id", ""))
		var population := source_record.get("population", {}) as Dictionary
		var population_assertion := {
			"lower_bound": population.get("lower", 0),
			"observation_period": {"from": population_date, "to": population_date},
			"spatial_scope": {"kind": "major_economy_aggregate", "id": economy_entity_id},
			"subject_id": "population:" + economy_entity_id,
			"unit": "persons",
			"upper_bound": population.get("upper", 0),
			"value": population.get("value", 0),
		}
		if not provenance_gate.admit_runtime_fact(
			"population_aggregate:population:" + economy_entity_id,
			"population_aggregate",
			population_assertion
		):
			return _fail("正式人口输入 provenance admission 失败：%s" % economy_entity_id)
		var population_record := {
			"economy_entity_id": economy_entity_id,
			"population": (
				(source_record.get("population", {}) as Dictionary).duplicate(true)
			),
			"urban_population_share_bp": (
				(source_record.get("urban_population_share_bp", {}) as Dictionary)
				.duplicate(true)
			),
			"provenance": {
				"source": WORLD_MANIFEST_PATH,
				"role": "demographic_bootstrap_fact",
			},
		}
		economic_record.erase("population")
		economic_record.erase("urban_population_share_bp")
		economic_records.append(economic_record)
		population_records.append(population_record)

	_fingerprint = _source_fingerprint(SOURCE_PATHS)
	_population_fingerprint = _value_fingerprint(population_records)
	if _fingerprint.is_empty() or _population_fingerprint.is_empty():
		return _fail("无法计算正式经济输入指纹")
	_economic_snapshot = {
		"revision": REVISION,
		"fingerprint": _fingerprint,
		"countries": economic_records,
		"formal_verified_countries": historical["formal_verified_countries"],
		"commodities": (commodity_document.get("commodities", []) as Array).duplicate(true),
		"crosswalk_records": (crosswalk_document.get("records", []) as Array).duplicate(true),
		"maritime_corridors": (historical["maritime_corridors"] as Array).duplicate(true),
		"river_corridors": (historical["river_corridors"] as Array).duplicate(true),
		"provenance": {
			"source_paths": SOURCE_PATHS.duplicate(),
			"role": "static_economic_bootstrap_evidence",
		},
	}
	_population_snapshot = {
		"revision": POPULATION_REVISION,
		"fingerprint": _population_fingerprint,
		"records": population_records,
		"provenance": {
			"source": WORLD_MANIFEST_PATH,
			"role": "read_only_demographic_input",
		},
	}
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func economic_snapshot() -> Dictionary:
	return _economic_snapshot.duplicate(true)


func population_snapshot() -> Dictionary:
	return _population_snapshot.duplicate(true)


func _source_fingerprint(paths: Array[String]) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return ""
		if hashing.update(path.to_utf8_buffer()) != OK:
			return ""
		if hashing.update(file.get_buffer(file.get_length())) != OK:
			return ""
	return hashing.finish().hex_encode()


func _value_fingerprint(value: Variant) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(JSON.stringify(value).to_utf8_buffer()) != OK:
		return ""
	return hashing.finish().hex_encode()


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取正式经济证据：%s" % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK or not parser.data is Dictionary:
		_fail("正式经济证据 JSON 无效：%s" % path)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _fail(message: String) -> bool:
	initialization_error = message
	return false


func _load_historical_inputs() -> Dictionary:
	# Only source decoding/admission lives here. No Alpha runtime is constructed.
	var world_manifest := _read_document(WORLD_MANIFEST_PATH)
	var household_budgets := _read_document(HOUSEHOLD_BUDGET_PATH)
	var transport_manifest := _read_document(TRANSPORT_MANIFEST_PATH)
	var coverage_registry := _read_document(COVERAGE_REGISTRY_PATH)
	if world_manifest.is_empty() or household_budgets.is_empty() or transport_manifest.is_empty() or coverage_registry.is_empty():
		return {}
	var schemas := {
		"1900世界经济清单": [world_manifest, "historical_world_economy_1900_estimates_v1"],
		"1900家庭预算": [household_budgets, "historical_household_budgets_1900_v1"],
		"1900运输网络清单": [transport_manifest, "historical_transport_network_1900_estimates_v1"],
		"1900经济覆盖登记表": [coverage_registry, "historical_economy_coverage_1900_v1"],
	}
	for label: String in schemas:
		var entry: Array = schemas[label]
		if str((entry[0] as Dictionary).get("schema_id", "")) != str(entry[1]):
			_fail(label + " Schema 无效")
			return {}
	var table := _read_document(str(world_manifest.get("compact_country_table_path", "")))
	if str(table.get("schema_id", "")) != "historical_world_economy_1900_compact_country_table_v1":
		_fail("1900国家紧凑表 Schema 无效")
		return {}
	var fields := DataRecordUtils.to_string_array(table.get("field_order", []))
	var methods := table.get("common_methods", {}) as Dictionary
	var countries: Array[Dictionary] = []
	var country_by_entity: Dictionary = {}
	for raw_row: Variant in table.get("rows", []) as Array:
		if not raw_row is Array or (raw_row as Array).size() != fields.size():
			_fail("1900国家紧凑表行格式或列数无效")
			return {}
		var values: Array = raw_row
		var flat: Dictionary = {}
		for index: int in fields.size():
			flat[fields[index]] = values[index]
		var record := expand_country_row(flat, methods)
		var entity_id := str(record.get("entity_id", ""))
		if entity_id.is_empty() or country_by_entity.has(entity_id):
			_fail("1900国家记录ID缺失或重复")
			return {}
		countries.append(record)
		country_by_entity[entity_id] = record
	countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 0)) < int(b.get("rank", 0))
	)
	var transport := _read_document(str(transport_manifest.get("compact_table_path", "")))
	if str(transport.get("schema_id", "")) != "historical_transport_network_1900_compact_tables_v1":
		_fail("1900运输紧凑表 Schema 无效")
		return {}
	var domestic := expand_transport_rows(transport, "domestic")
	var maritime := expand_transport_rows(transport, "maritime")
	var river := expand_transport_rows(transport, "river")
	var coverage_by_entity: Dictionary = {}
	for raw_record: Variant in coverage_registry.get("countries", []) as Array:
		if raw_record is Dictionary:
			var record := (raw_record as Dictionary).duplicate(true)
			var entity_id := str(record.get("entity_id", ""))
			if not entity_id.is_empty():
				coverage_by_entity[entity_id] = record
	var budget_by_id: Dictionary = {}
	for raw_budget: Variant in household_budgets.get("templates", []) as Array:
		if raw_budget is Dictionary:
			var budget := (raw_budget as Dictionary).duplicate(true)
			var budget_id := str(budget.get("template_id", ""))
			if not budget_id.is_empty():
				budget_by_id[budget_id] = budget
	var integrity := validate_historical_records(countries, country_by_entity, domestic, maritime, river, budget_by_id)
	if not bool(integrity.get("success", false)):
		_fail(str(integrity["message"]))
		return {}
	var verified := admit_country_records(world_manifest, countries, coverage_by_entity)
	return {
		"calibration_date": str(world_manifest.get("calibration_date", "")),
		"countries": simulation_country_records(countries, coverage_by_entity, coverage_registry, verified),
		"formal_verified_countries": verified,
		"maritime_corridors": maritime,
		"river_corridors": river,
	}


## Pure table decoding and source admission, also used by the legacy audit reader.
static func admit_country_records(
	world_manifest: Dictionary,
	countries: Array[Dictionary],
	coverage_by_entity: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var threshold: int = int((world_manifest.get("policy", {}) as Dictionary).get(
		"minimum_formal_confidence_bp", 4500
	))
	var required_dimensions: Array[String] = [
		"population", "industrial_capacity", "railway_capacity",
	]
	for record: Dictionary in countries:
		var entity_id := str(record.get("entity_id", ""))
		var coverage := coverage_by_entity.get(entity_id, {}) as Dictionary
		if str(coverage.get("status", "source_required")) != "verified":
			continue
		var verified := DataRecordUtils.to_string_array(coverage.get("verified_dimensions", []))
		var complete := true
		for dimension: String in required_dimensions:
			if dimension not in verified:
				complete = false
				break
		if (
			complete
			and bool(record.get("formal_simulation_allowed", false))
			and int(record.get("overall_confidence_bp", 0)) >= threshold
		):
			var admitted := record.duplicate(true)
			admitted["coverage"] = coverage.duplicate(true)
			result.append(admitted)
	return result


static func simulation_country_records(
	countries: Array[Dictionary],
	coverage_by_entity: Dictionary,
	coverage_registry: Dictionary,
	verified_countries: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var formally_admitted: Dictionary = {}
	for record: Dictionary in verified_countries:
		formally_admitted[str(record.get("entity_id", ""))] = true
	for record: Dictionary in countries:
		var entity_id := str(record.get("entity_id", ""))
		var coverage := (coverage_by_entity.get(entity_id, {
			"entity_id": entity_id,
			"status": "source_required",
			"verified_dimensions": [],
			"missing_dimensions": (coverage_registry.get("dimensions", []) as Array).duplicate(),
		}) as Dictionary).duplicate(true)
		coverage["status"] = "verified" if formally_admitted.has(entity_id) else "bounded_estimate"
		var simulation_record := record.duplicate(true)
		simulation_record["coverage"] = coverage
		simulation_record["admission_status"] = str(coverage.get("status", "bounded_estimate"))
		result.append(simulation_record)
	return result


static func validate_historical_records(
	countries: Array[Dictionary],
	country_by_entity: Dictionary,
	domestic_networks: Array[Dictionary],
	maritime_corridors: Array[Dictionary],
	river_corridors: Array[Dictionary],
	budget_by_id: Dictionary
) -> Dictionary:
	if countries.size() != 50:
		return _integrity_result(false, "国家校准记录不是50项")
	if domestic_networks.size() != 50:
		return _integrity_result(false, "国内运输记录不是50项")
	if maritime_corridors.size() < 30 or river_corridors.size() < 12:
		return _integrity_result(false, "国际海运或河运骨架覆盖不足")
	if budget_by_id.size() < 6:
		return _integrity_result(false, "家庭预算模板覆盖不足")
	var seen_ranks: Dictionary = {}
	for record: Dictionary in countries:
		var entity_id: String = str(record.get("entity_id", ""))
		var rank: int = int(record.get("rank", 0))
		if entity_id.is_empty() or country_by_entity.get(entity_id, {}) != record:
			return _integrity_result(false, "国家记录索引无效")
		if seen_ranks.has(rank) or rank < 1 or rank > 50:
			return _integrity_result(false, "国家优先级缺失或重复")
		seen_ranks[rank] = true
		for field: String in ["population", "gdp_per_capita_2011_intl_dollars", "urban_population_share_bp"]:
			var bounded: Dictionary = record.get(field, {}) as Dictionary
			if float(bounded.get("lower", 0)) > float(bounded.get("value", 0)):
				return _integrity_result(false, "估算下界高于中心值：%s/%s" % [entity_id, field])
			if float(bounded.get("value", 0)) > float(bounded.get("upper", 0)):
				return _integrity_result(false, "估算中心值高于上界：%s/%s" % [entity_id, field])
			if int(bounded.get("confidence_bp", 0)) <= 0:
				return _integrity_result(false, "估算缺少有效置信度：%s/%s" % [entity_id, field])
		if not budget_by_id.has(str(record.get("household_budget_template_id", ""))):
			return _integrity_result(false, "国家引用未知家庭预算模板：%s" % entity_id)
	for budget: Dictionary in budget_by_id.values():
		var total: int = 0
		for value: Variant in (budget.get("shares_bp", {}) as Dictionary).values():
			total += int(value)
		if total != 10000:
			return _integrity_result(false, "家庭预算份额不等于10000基点")
	return _integrity_result(true, "ok")


static func expand_country_row(flat: Dictionary, methods: Dictionary) -> Dictionary:
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


static func _bounded(flat: Dictionary, prefix: String, method_key: String, methods: Dictionary) -> Dictionary:
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


static func expand_transport_rows(table: Dictionary, prefix: String) -> Array[Dictionary]:
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


static func _integrity_result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message}
