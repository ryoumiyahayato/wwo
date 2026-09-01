class_name FormalWorldMarketView
extends RefCounted
## Immutable consumer view over the composition-owned market registry.

var _revision: String = ""
var _mapping_fingerprint: String = ""
var _markets_by_id: Dictionary = {}
var _market_by_economic_aggregate_id: Dictionary = {}
var _economic_aggregate_by_market_id: Dictionary = {}


func _init(snapshot: Dictionary = {}) -> void:
	if (
		str(snapshot.get("schema_id", ""))
		!= FormalWorldMarketRegistry.SNAPSHOT_SCHEMA_ID
	):
		return
	_revision = str(snapshot.get("revision", ""))
	_mapping_fingerprint = str(snapshot.get("mapping_fingerprint", ""))
	for record: Dictionary in DataRecordUtils.to_dictionary_array(
		snapshot.get("markets", [])
	):
		var identity := MarketIdentity.new(record)
		if not identity.is_valid(_revision):
			_clear()
			return
		var market_id := identity.market_id()
		var aggregate_id := identity.source_economic_aggregate_id()
		if (
			_markets_by_id.has(market_id)
			or _market_by_economic_aggregate_id.has(aggregate_id)
		):
			_clear()
			return
		_markets_by_id[market_id] = identity.snapshot()
		_market_by_economic_aggregate_id[aggregate_id] = market_id
		_economic_aggregate_by_market_id[market_id] = aggregate_id


func is_configured() -> bool:
	return (
		not _revision.is_empty()
		and not _mapping_fingerprint.is_empty()
		and _markets_by_id.size()
		== FormalWorldMarketRegistry.EXPECTED_COMPATIBILITY_MARKET_COUNT
	)


func revision() -> String:
	return _revision


func mapping_fingerprint() -> String:
	return _mapping_fingerprint


func market_count() -> int:
	return _markets_by_id.size()


func market_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in _markets_by_id:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func markets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for market_id: String in market_ids():
		result.append((_markets_by_id[market_id] as Dictionary).duplicate(true))
	return result


func market(market_id: String) -> Dictionary:
	return (_markets_by_id.get(market_id, {}) as Dictionary).duplicate(true)


func has_market(market_id: String) -> bool:
	return _markets_by_id.has(market_id)


func market_id_for_economic_aggregate(economic_aggregate_id: String) -> String:
	return str(_market_by_economic_aggregate_id.get(economic_aggregate_id, ""))


func economic_aggregate_id_for_market(market_id: String) -> String:
	return str(_economic_aggregate_by_market_id.get(market_id, ""))


func _clear() -> void:
	_revision = ""
	_mapping_fingerprint = ""
	_markets_by_id.clear()
	_market_by_economic_aggregate_id.clear()
	_economic_aggregate_by_market_id.clear()
