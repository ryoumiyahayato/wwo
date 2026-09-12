class_name MarketIdentity
extends RefCounted
## Immutable identity for an Economy-owned pricing scope.

const LEGACY_AGGREGATE_PREFIX: String = "market:legacy_aggregate:"
const LEGACY_APPLICABILITY_MODE: String = "legacy_aggregate_pricing_scope"

var _market_id: String = ""
var _source_economic_aggregate_id: String = ""
var _applicability: Dictionary = {}
var _revision: String = ""
var _provenance: Dictionary = {}


func _init(snapshot: Dictionary = {}) -> void:
	_market_id = str(snapshot.get("market_id", ""))
	_source_economic_aggregate_id = str(
		snapshot.get("source_economic_aggregate_id", "")
	)
	_applicability = (snapshot.get("applicability", {}) as Dictionary).duplicate(true)
	_revision = str(snapshot.get("revision", ""))
	_provenance = (snapshot.get("provenance", {}) as Dictionary).duplicate(true)


static func compatibility_market_id(economic_aggregate_id: String) -> String:
	if economic_aggregate_id.is_empty() or economic_aggregate_id.contains(":"):
		return ""
	return LEGACY_AGGREGATE_PREFIX + economic_aggregate_id


static func compatibility_snapshot(
	economic_aggregate_id: String, revision_value: String
) -> Dictionary:
	return {
		"market_id": compatibility_market_id(economic_aggregate_id),
		"source_economic_aggregate_id": economic_aggregate_id,
		"applicability": {
			"mode": LEGACY_APPLICABILITY_MODE,
			"start_date": "1900-01-01",
			"end_date": "",
		},
		"revision": revision_value,
		"provenance": {
			"source": "FormalWorldEconomicEvidenceCatalog",
			"role": "legacy_aggregate_market_identity",
		},
	}


func is_valid(expected_revision: String = "") -> bool:
	if (
		_market_id.is_empty()
		or _source_economic_aggregate_id.is_empty()
		or _revision.is_empty()
		or _applicability.is_empty()
		or _provenance.is_empty()
	):
		return false
	if not expected_revision.is_empty() and _revision != expected_revision:
		return false
	if _market_id != compatibility_market_id(_source_economic_aggregate_id):
		return false
	if str(_applicability.get("mode", "")) != LEGACY_APPLICABILITY_MODE:
		return false
	if str(_applicability.get("start_date", "")) != "1900-01-01":
		return false
	if (
		str(_provenance.get("source", "")).is_empty()
		or str(_provenance.get("role", "")) != "legacy_aggregate_market_identity"
	):
		return false
	return (
		_market_id != _source_economic_aggregate_id
		and not _market_id.begins_with("state:")
		and not _market_id.begins_with("economic_region:")
		and not _market_id.begins_with("site:")
	)


func market_id() -> String:
	return _market_id


func source_economic_aggregate_id() -> String:
	return _source_economic_aggregate_id


func snapshot() -> Dictionary:
	return {
		"market_id": _market_id,
		"source_economic_aggregate_id": _source_economic_aggregate_id,
		"applicability": _applicability.duplicate(true),
		"revision": _revision,
		"provenance": _provenance.duplicate(true),
	}
