class_name VNextEconomicGeographyCandidate
extends RefCounted
## Detached, domain-local proposal for one primary-market remap.

const SCHEMA_ID: String = "vnext_economic_geography_candidate_v1"
const ASSIGNED: String = "assigned"
const UNASSIGNED: String = "unassigned"

var _configured: bool = false
var _expected_revision: int = -1
var _before_assignment: Dictionary = {}
var _target_assignment: Dictionary = {}
var _territory_catalog_binding: Dictionary = {}
var _market_identity_binding: Dictionary = {}
var _fingerprint: String = ""


func configure(
	expected_revision_value: Variant,
	before_assignment_value: Variant,
	target_assignment_value: Variant,
	territory_catalog_binding_value: Variant,
	market_identity_binding_value: Variant
) -> bool:
	if _configured or typeof(expected_revision_value) != TYPE_INT:
		return false
	var candidate_revision: int = expected_revision_value as int
	if candidate_revision < 0:
		return false
	if not is_assignment_record(before_assignment_value):
		return false
	if not is_assignment_record(target_assignment_value):
		return false
	var before: Dictionary = before_assignment_value as Dictionary
	var target: Dictionary = target_assignment_value as Dictionary
	if before.get("territory_unit_id") != target.get("territory_unit_id"):
		return false
	if before == target:
		return false
	if typeof(territory_catalog_binding_value) != TYPE_DICTIONARY:
		return false
	if typeof(market_identity_binding_value) != TYPE_DICTIONARY:
		return false
	var territory_binding: Dictionary = territory_catalog_binding_value as Dictionary
	var market_binding: Dictionary = market_identity_binding_value as Dictionary
	if territory_binding.size() != 2 or market_binding.size() != 2:
		return false
	if (
		typeof(territory_binding.get("catalog_version")) != TYPE_STRING
		or typeof(territory_binding.get("catalog_fingerprint")) != TYPE_STRING
		or str(territory_binding.get("catalog_version", "")).is_empty()
		or str(territory_binding.get("catalog_fingerprint", "")).length() != 64
	):
		return false
	if (
		typeof(market_binding.get("identity_revision")) != TYPE_STRING
		or typeof(market_binding.get("identity_fingerprint")) != TYPE_STRING
		or str(market_binding.get("identity_revision", "")).is_empty()
		or str(market_binding.get("identity_fingerprint", "")).length() != 64
	):
		return false

	_expected_revision = candidate_revision
	_before_assignment = before.duplicate(true)
	_target_assignment = target.duplicate(true)
	_territory_catalog_binding = territory_binding.duplicate(true)
	_market_identity_binding = market_binding.duplicate(true)
	_fingerprint = _fingerprint_for(_payload())
	_configured = not _fingerprint.is_empty()
	return _configured


func is_well_formed() -> bool:
	return (
		_configured
		and is_assignment_record(_before_assignment)
		and is_assignment_record(_target_assignment)
		and _before_assignment.get("territory_unit_id")
		== _target_assignment.get("territory_unit_id")
		and _before_assignment != _target_assignment
		and _fingerprint == _fingerprint_for(_payload())
	)


func expected_revision() -> int:
	return _expected_revision


func territory_unit_id() -> String:
	return str(_before_assignment.get("territory_unit_id", ""))


func before_assignment() -> Dictionary:
	return _before_assignment.duplicate(true)


func target_assignment() -> Dictionary:
	return _target_assignment.duplicate(true)


func territory_catalog_binding() -> Dictionary:
	return _territory_catalog_binding.duplicate(true)


func market_identity_binding() -> Dictionary:
	return _market_identity_binding.duplicate(true)


func fingerprint() -> String:
	return _fingerprint


func to_detached_dict() -> Dictionary:
	var detached: Dictionary = _payload()
	detached["candidate_fingerprint"] = _fingerprint
	return detached


static func from_detached_dict(value: Variant) -> VNextEconomicGeographyCandidate:
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var source: Dictionary = value as Dictionary
	if source.size() != 7 or source.get("schema_id") != SCHEMA_ID:
		return null
	if typeof(source.get("candidate_fingerprint")) != TYPE_STRING:
		return null
	var candidate := VNextEconomicGeographyCandidate.new()
	if not candidate.configure(
		source.get("expected_revision"),
		source.get("before_assignment"),
		source.get("target_assignment"),
		source.get("territory_catalog_binding"),
		source.get("market_identity_binding")
	):
		return null
	if candidate.fingerprint() != source.get("candidate_fingerprint"):
		return null
	return candidate


static func is_assignment_record(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var record: Dictionary = value as Dictionary
	if typeof(record.get("territory_unit_id")) != TYPE_STRING:
		return false
	var assignment_state: Variant = record.get("assignment_state")
	if assignment_state == UNASSIGNED:
		return record.size() == 2
	return (
		assignment_state == ASSIGNED
		and record.size() == 3
		and typeof(record.get("market_id")) == TYPE_STRING
	)


func _payload() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"expected_revision": _expected_revision,
		"before_assignment": _before_assignment.duplicate(true),
		"target_assignment": _target_assignment.duplicate(true),
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"market_identity_binding": _market_identity_binding.duplicate(true),
	}


static func _fingerprint_for(value: Variant) -> String:
	return JSON.stringify(_canonical_copy(value), "", false).sha256_text()


static func _canonical_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var copied_array: Array = []
		for item: Variant in value as Array:
			copied_array.append(_canonical_copy(item))
		return copied_array
	if typeof(value) == TYPE_DICTIONARY:
		var source: Dictionary = value as Dictionary
		var keys: Array = source.keys()
		keys.sort()
		var copied_dictionary: Dictionary = {}
		for key: Variant in keys:
			copied_dictionary[key] = _canonical_copy(source.get(key))
		return copied_dictionary
	return value
