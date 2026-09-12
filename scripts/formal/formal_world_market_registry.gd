class_name FormalWorldMarketRegistry
extends RefCounted
## Composition-owned identity catalog for current formal pricing scopes.

const REVISION: String = "formal_world_market_registry_v1"
const STATE_SCHEMA_ID: String = "formal_world_market_state_v1"
const SNAPSHOT_SCHEMA_ID: String = "formal_world_market_registry_snapshot_v1"
const EXPECTED_COMPATIBILITY_MARKET_COUNT: int = 50

var initialization_error: String = ""
var _configured: bool = false
var _markets_by_id: Dictionary = {}
var _market_by_economic_aggregate_id: Dictionary = {}
var _economic_aggregate_by_market_id: Dictionary = {}
var _mapping_fingerprint: String = ""


func configure(
	economic_aggregate_ids: Array[String], political_ids: Array[String]
) -> bool:
	if _configured:
		return _fail("Formal market registry is already initialized")
	initialization_error = ""
	_markets_by_id.clear()
	_market_by_economic_aggregate_id.clear()
	_economic_aggregate_by_market_id.clear()
	_mapping_fingerprint = ""

	var forbidden_political_ids: Dictionary = {}
	for political_id: String in political_ids:
		if political_id.is_empty() or forbidden_political_ids.has(political_id):
			return _fail("Runtime political identity list is invalid")
		forbidden_political_ids[political_id] = true

	var sorted_aggregate_ids := economic_aggregate_ids.duplicate()
	sorted_aggregate_ids.sort()
	if sorted_aggregate_ids.size() != EXPECTED_COMPATIBILITY_MARKET_COUNT:
		return _fail(
			"Formal compatibility market count must be %d" % (
				EXPECTED_COMPATIBILITY_MARKET_COUNT
			)
		)
	for economic_aggregate_id: String in sorted_aggregate_ids:
		if (
			economic_aggregate_id.is_empty()
			or _market_by_economic_aggregate_id.has(economic_aggregate_id)
		):
			return _fail("Economic aggregate identity is missing or duplicated")
		var identity := MarketIdentity.new(
			MarketIdentity.compatibility_snapshot(economic_aggregate_id, REVISION)
		)
		if not identity.is_valid(REVISION):
			return _fail("Compatibility market identity is invalid")
		var market_id := identity.market_id()
		if (
			forbidden_political_ids.has(market_id)
			or _markets_by_id.has(market_id)
			or market_id == economic_aggregate_id
		):
			return _fail("Market identity collides with another identity domain")
		_markets_by_id[market_id] = identity.snapshot()
		_market_by_economic_aggregate_id[economic_aggregate_id] = market_id
		_economic_aggregate_by_market_id[market_id] = economic_aggregate_id

	_mapping_fingerprint = _fingerprint(_ordered_market_snapshots())
	if _mapping_fingerprint.is_empty():
		return _fail("Unable to fingerprint formal market mapping")
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func revision() -> String:
	return REVISION if _configured else ""


func mapping_fingerprint() -> String:
	return _mapping_fingerprint


func market_count() -> int:
	return _markets_by_id.size()


func market_id_for_economic_aggregate(economic_aggregate_id: String) -> String:
	return str(_market_by_economic_aggregate_id.get(economic_aggregate_id, ""))


func economic_aggregate_id_for_market(market_id: String) -> String:
	return str(_economic_aggregate_by_market_id.get(market_id, ""))


func has_market(market_id: String) -> bool:
	return _markets_by_id.has(market_id)


func read_only_snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"revision": REVISION,
		"mapping_fingerprint": _mapping_fingerprint,
		"markets": _ordered_market_snapshots(),
	}


func get_persistent_state() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": STATE_SCHEMA_ID,
		"revision": REVISION,
		"mapping_fingerprint": _mapping_fingerprint,
	}


func validate_persistent_state(state: Dictionary) -> bool:
	return (
		_configured
		and state.size() == 3
		and str(state.get("schema_id", "")) == STATE_SCHEMA_ID
		and str(state.get("revision", "")) == REVISION
		and str(state.get("mapping_fingerprint", "")) == _mapping_fingerprint
	)


func _ordered_market_snapshots() -> Array[Dictionary]:
	var ids: Array[String] = []
	for raw_id: Variant in _markets_by_id:
		ids.append(str(raw_id))
	ids.sort()
	var result: Array[Dictionary] = []
	for market_id: String in ids:
		result.append((_markets_by_id[market_id] as Dictionary).duplicate(true))
	return result


func _fingerprint(value: Variant) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(JSON.stringify(value).to_utf8_buffer()) != OK:
		return ""
	return hashing.finish().hex_encode()


func _fail(message: String) -> bool:
	initialization_error = message
	return false
