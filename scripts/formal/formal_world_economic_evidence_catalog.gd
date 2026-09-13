class_name FormalWorldEconomicEvidenceCatalog
extends RefCounted
## Composition-owned, immutable bootstrap evidence for the formal economy.
## It owns source loading; the economy receives snapshots and never opens data files.

const REVISION: String = "formal_economic_evidence_1900_v1"
const POPULATION_REVISION: String = "formal_population_input_1900_v1"
const COMMODITY_PATH: String = "res://data/alpha/commodity_market_1900.json"
const CROSSWALK_PATH: String = (
	"res://data/world_map/historical/major_economy_polity_crosswalk_1900.json"
)
const SOURCE_PATHS: Array[String] = [
	AlphaHistoricalWorldEconomyData.WORLD_MANIFEST_PATH,
	AlphaHistoricalWorldEconomyData.HOUSEHOLD_BUDGET_PATH,
	AlphaHistoricalWorldEconomyData.TRANSPORT_MANIFEST_PATH,
	AlphaHistoricalWorldEconomyData.COVERAGE_REGISTRY_PATH,
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
	var historical := AlphaHistoricalWorldEconomyData.new()
	if not historical.configure():
		return _fail(historical.initialization_error)
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
	var population_date := str(historical.world_manifest.get("calibration_date", ""))
	if population_date.is_empty():
		return _fail("正式人口输入缺少 calibration_date")
	for source_record: Dictionary in historical.simulation_countries():
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
				"source": AlphaHistoricalWorldEconomyData.WORLD_MANIFEST_PATH,
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
		"formal_verified_countries": historical.formal_countries(),
		"commodities": (commodity_document.get("commodities", []) as Array).duplicate(true),
		"crosswalk_records": (crosswalk_document.get("records", []) as Array).duplicate(true),
		"maritime_corridors": historical.maritime_corridors.duplicate(true),
		"river_corridors": historical.river_corridors.duplicate(true),
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
			"source": AlphaHistoricalWorldEconomyData.WORLD_MANIFEST_PATH,
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
