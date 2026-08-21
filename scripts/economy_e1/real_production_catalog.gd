class_name RealProductionE1CommodityCatalog
extends RefCounted
## Data-only bridge to the existing Alpha commodity identity catalog.
##
## This adapter deliberately imports commodity identity and metadata only.  It
## does not import Alpha regions, country/controller facts, production-site
## capacity, demand, prices, or transport behavior into E1.

const E1Numeric = preload("res://scripts/economy_e1/e1_numeric.gd")
const ALPHA_COMMODITY_PATH: String = "res://data/alpha/commodity_market_1900.json"


static func load_existing_commodity_catalog() -> Dictionary:
	var file: FileAccess = FileAccess.open(ALPHA_COMMODITY_PATH, FileAccess.READ)
	if file == null:
		return {"success": false, "code": "source_missing", "message": ALPHA_COMMODITY_PATH, "data": {}}
	var source_text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(source_text) != OK or not parser.data is Dictionary:
		return {"success": false, "code": "source_invalid", "message": "Alpha commodity JSON is invalid", "data": {}}
	var document: Dictionary = parser.data as Dictionary
	if str(document.get("schema_id", "")) != "alpha_commodity_market_1900_v1":
		return {"success": false, "code": "source_schema_mismatch", "message": "Alpha commodity schema mismatch", "data": {}}
	var definitions: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_value: Variant in document.get("commodities", []) as Array:
		if not raw_value is Dictionary:
			return {"success": false, "code": "source_record_invalid", "message": "commodity record is not a dictionary", "data": {}}
		var source: Dictionary = raw_value as Dictionary
		var commodity_id: String = str(source.get("commodity_id", "")).strip_edges()
		if commodity_id.is_empty() or seen.has(commodity_id):
			return {"success": false, "code": "duplicate_commodity_id", "message": commodity_id, "data": {}}
		var base_price: Dictionary = _read_json_integer(source.get("base_price_centimes", 0))
		var target_days: Dictionary = _read_json_integer(source.get("target_stock_days", 0))
		if not bool(base_price.get("success", false)) or not bool(target_days.get("success", false)) or int(base_price.get("value", 0)) <= 0 or int(target_days.get("value", 0)) < 0:
			return {"success": false, "code": "commodity_metadata_invalid", "message": commodity_id, "data": {}}
		seen[commodity_id] = true
		definitions.append({
			"commodity_id": commodity_id,
			"base_price_centimes": int(base_price.get("value", 0)),
			"target_stock_days": int(target_days.get("value", 0)),
			"category": str(source.get("category", "")),
			"unit_name": str(source.get("unit_name_zh", "")),
			"catalog_source": ALPHA_COMMODITY_PATH,
		})
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("commodity_id", "")) < str(b.get("commodity_id", ""))
	)
	var commodity_ids: Array[String] = E1Numeric.sorted_string_keys(seen)
	var canonical_source: Dictionary = {
		"schema_id": str(document.get("schema_id", "")),
		"commodities": definitions,
	}


	return {
		"success": true,
		"code": "ok",
		"message": "",
		"data": {
			"catalog_revision": "%s:%s" % [str(document.get("schema_id", "")), source_text.sha256_text()],
			"catalog_hash": E1Numeric.sha256(canonical_source),
			"commodities": definitions,
			"commodity_ids": commodity_ids,
		},
	}


static func _read_json_integer(value: Variant) -> Dictionary:
	if value is int:
		return {"success": true, "value": int(value)}
	if value is float:
		var converted: int = int(value)
		if float(converted) == float(value):
			return {"success": true, "value": converted}
	return {"success": false, "value": 0}
