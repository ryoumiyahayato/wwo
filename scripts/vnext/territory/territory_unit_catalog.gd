class_name VNextTerritoryUnitCatalog
extends RefCounted
## Deterministic sealed catalog of stable geometry-unit identities.
##
## The fingerprint binds immutable catalog definitions only. Runtime control
## and all political, demographic, economic, and military state are external.

const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")

const FINGERPRINT_SCHEMA: String = "vnext_territory_unit_catalog_fingerprint_v1"

var _configured: bool = false
var _sealed: bool = false
var _catalog_version: String = ""
var _fingerprint: String = ""
var _units_by_id: Dictionary = {}
var _ordered_ids: Array[String] = []
var _errors: Array[String] = []


func configure(catalog_version_value: Variant) -> bool:
	if _configured or _sealed:
		return _fail("catalog can only be configured once")
	if (
		typeof(catalog_version_value) != TYPE_STRING
		or not TERRITORY_UNIT.is_valid_catalog_version(catalog_version_value as String)
	):
		return _fail("invalid catalog version")
	_catalog_version = catalog_version_value as String
	_configured = true
	_errors.clear()
	return true


func add_unit(unit_value: Variant) -> bool:
	if not _configured:
		return _fail("catalog must be configured before adding units")
	if _sealed:
		return _fail("sealed catalog is immutable")
	if not unit_value is VNextTerritoryUnit:
		return _fail("catalog entry must be a TerritoryUnit")
	var unit: VNextTerritoryUnit = unit_value as VNextTerritoryUnit
	if unit == null or not unit.is_configured():
		return _fail("territory unit is not configured")
	if unit.catalog_version() != _catalog_version:
		return _fail("territory unit catalog version mismatch")
	var territory_unit_id: String = unit.territory_unit_id()
	if not TERRITORY_UNIT.is_valid_territory_unit_id(territory_unit_id):
		return _fail("invalid territory unit id")
	if _units_by_id.has(territory_unit_id):
		return _fail("duplicate territory unit id: %s" % territory_unit_id)
	var detached_unit: VNextTerritoryUnit = unit.copy_detached()
	if detached_unit == null:
		return _fail("territory unit could not be detached")
	_units_by_id[territory_unit_id] = detached_unit
	return true


func seal() -> bool:
	if not _configured:
		return _fail("catalog must be configured before seal")
	if _sealed:
		return _fail("catalog is already sealed")
	if _units_by_id.is_empty():
		return _fail("catalog cannot seal without territory units")

	var candidate_ids: Array[String] = _sorted_unit_ids()
	for territory_unit_id: String in candidate_ids:
		var unit: VNextTerritoryUnit = _units_by_id[territory_unit_id] as VNextTerritoryUnit
		for neighbor_id: String in unit.neighbor_ids():
			if not _units_by_id.has(neighbor_id):
				return _fail(
					"unknown neighbor %s referenced by %s"
					% [neighbor_id, territory_unit_id]
				)
			var neighbor: VNextTerritoryUnit = (
				_units_by_id[neighbor_id] as VNextTerritoryUnit
			)
			if not neighbor.neighbor_ids().has(territory_unit_id):
				return _fail(
					"asymmetric adjacency between %s and %s"
					% [territory_unit_id, neighbor_id]
				)

	_ordered_ids = candidate_ids
	_fingerprint = _fingerprint_for_catalog()
	_sealed = true
	_errors.clear()
	return true


func is_sealed() -> bool:
	return _sealed


func catalog_version() -> String:
	return _catalog_version


func fingerprint() -> String:
	return _fingerprint if _sealed else ""


func unit_count() -> int:
	return _ordered_ids.size() if _sealed else 0


func unit_ids() -> Array[String]:
	return _copy_strings(_ordered_ids) if _sealed else []


func units() -> Array[VNextTerritoryUnit]:
	var copied: Array[VNextTerritoryUnit] = []
	if not _sealed:
		return copied
	for territory_unit_id: String in _ordered_ids:
		var unit: VNextTerritoryUnit = _units_by_id[territory_unit_id] as VNextTerritoryUnit
		copied.append(unit.copy_detached())
	return copied


func has_unit(territory_unit_id: String) -> bool:
	return (
		_sealed
		and TERRITORY_UNIT.is_valid_territory_unit_id(territory_unit_id)
		and _units_by_id.has(territory_unit_id)
	)


func unit_by_id(territory_unit_id: String) -> VNextTerritoryUnit:
	if not has_unit(territory_unit_id):
		return null
	var unit: VNextTerritoryUnit = _units_by_id[territory_unit_id] as VNextTerritoryUnit
	return unit.copy_detached()


func neighbor_ids(territory_unit_id: String) -> Array[String]:
	var unit: VNextTerritoryUnit = unit_by_id(territory_unit_id)
	return unit.neighbor_ids() if unit != null else []


func binding() -> Dictionary:
	if not _sealed:
		return {}
	return {
		"catalog_version": _catalog_version,
		"catalog_fingerprint": _fingerprint,
	}


func validates_binding(binding_value: Variant) -> bool:
	if not _sealed or typeof(binding_value) != TYPE_DICTIONARY:
		return false
	var candidate: Dictionary = binding_value as Dictionary
	return (
		candidate.size() == 2
		and typeof(candidate.get("catalog_version")) == TYPE_STRING
		and typeof(candidate.get("catalog_fingerprint")) == TYPE_STRING
		and candidate.get("catalog_version") == _catalog_version
		and candidate.get("catalog_fingerprint") == _fingerprint
	)


func errors() -> Array[String]:
	return _copy_strings(_errors)


func _fingerprint_for_catalog() -> String:
	var records: Array = []
	for territory_unit_id: String in _ordered_ids:
		var unit: VNextTerritoryUnit = _units_by_id[territory_unit_id] as VNextTerritoryUnit
		records.append(unit.to_detached_dict())
	var payload: Dictionary = {
		"fingerprint_schema": FINGERPRINT_SCHEMA,
		"catalog_version": _catalog_version,
		"territory_units": records,
	}
	return JSON.stringify(_canonical_copy(payload), "", false).sha256_text()


func _sorted_unit_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _units_by_id.keys():
		result.append(str(raw_id))
	result.sort()
	return result


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


static func _copy_strings(source: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	for value: String in source:
		copied.append(value)
	return copied


func _fail(message: String) -> bool:
	_errors.append(message)
	return false
