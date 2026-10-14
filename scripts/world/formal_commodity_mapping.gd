class_name FormalCommodityMapping
extends RefCounted
## Explicit unit crosswalk rules. These never own stock, prices or money.

static func valid_rows(value: Variant) -> bool:
	if not value is Array or value.size() > 64: return false
	var ids: Dictionary = {}
	var pairs: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["id", "legacy_commodity_id", "native_good_id", "legacy_unit_name_zh", "native_unit_id", "native_units_numerator", "legacy_units_denominator", "scope", "source", "basis", "semantic_assumption", "operations"]): return false
		for key: String in ["id", "legacy_commodity_id", "native_good_id", "legacy_unit_name_zh", "native_unit_id", "scope", "source", "semantic_assumption"]:
			if not row[key] is String or row[key].is_empty(): return false
		if ids.has(row["id"]) or pairs.has(row["legacy_commodity_id"]) or row["scope"] != "FORMAL_PERSON_OWNED_PROPERTY" or row["basis"] != "EXPLICIT_DEVELOPMENT_UNIT_CROSSWALK" or not row["operations"] is Array or row["operations"].is_empty(): return false
		for key: String in ["native_units_numerator", "legacy_units_denominator"]:
			if not FormalLedgerState.valid_amount(row[key]) or int(row[key]) < 1 or int(row[key]) > 1000000: return false
		var operations: Dictionary = {}
		for operation: Variant in row["operations"]:
			if operation not in ["OBSERVE", "PERSONAL_OWNED_HANDOVER", "FUTURE_FLOW_ARRANGEMENT"] or operations.has(operation): return false
			operations[operation] = true
		ids[row["id"]] = true
		pairs[row["legacy_commodity_id"]] = true
	return true

static func bindings_valid(rows: Array, market: FormalWorldEconomyState, settings: Dictionary) -> bool:
	if not valid_rows(rows): return false
	for row: Dictionary in rows:
		var original := market.commodity_definition(row["legacy_commodity_id"])
		var good: Dictionary = {}
		for entry: Dictionary in settings.get("goods", []):
			if entry["id"] == row["native_good_id"]: good = entry
		if original.is_empty() or good.is_empty() or original.get("unit_name_zh") != row["legacy_unit_name_zh"] or good.get("unit_id") != row["native_unit_id"] or row["source"] != FormalWorldEconomicEvidenceCatalog.COMMODITY_PATH: return false
	return true

static func find(rows: Array, legacy_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row["legacy_commodity_id"] == legacy_id: return row.duplicate(true)
	return {}

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return a

## Legacy owned quantities already use exact milli-units. Reject every remainder.
static func to_native(row: Dictionary, quantity_milli: int) -> Dictionary:
	if row.is_empty() or quantity_milli < 1: return {"success": false, "reason": "NO_EXPLICIT_COMMODITY_MAPPING"}
	var numerator := int(row["native_units_numerator"])
	var denominator := int(row["legacy_units_denominator"]) * 1000
	var divisor := _gcd(numerator, denominator)
	numerator /= divisor
	denominator /= divisor
	if quantity_milli % denominator != 0: return {"success": false, "reason": "QUANTITY_HAS_UNREPRESENTABLE_UNIT_REMAINDER"}
	var whole: int = quantity_milli / denominator
	if whole > FormalLedgerState.MAX_AMOUNT / numerator: return {"success": false, "reason": "MAPPED_QUANTITY_EXCEEDS_NUMERIC_BOUNDS"}
	return {"success": true, "quantity": whole*numerator}
