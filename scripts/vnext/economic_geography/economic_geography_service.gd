class_name VNextEconomicGeographyService
extends RefCounted
## Authoritative primary-market assignment owner for stable territory units.
##
## Territory identity and Market identity are externally owned references.
## Missing entries for known territories have explicit unassigned semantics.

const CANDIDATE = preload("res://scripts/vnext/economic_geography/economic_geography_candidate.gd")
const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")

const SNAPSHOT_SCHEMA_ID: String = "vnext_economic_geography_snapshot_v1"
const FINGERPRINT_SCHEMA_ID: String = "vnext_economic_geography_fingerprint_v1"
const ASSIGNED: String = "assigned"
const UNASSIGNED: String = "unassigned"

var _configured: bool = false
var _territory_catalog: VNextTerritoryUnitCatalog = null
var _market_provider: Variant = null
var _territory_catalog_binding: Dictionary = {}
var _market_identity_binding: Dictionary = {}
var _assigned_market_by_territory: Dictionary = {}
var _revision: int = 0
var _state_fingerprint: String = ""
var _errors: Array[String] = []


func configure(
	territory_provider: Variant,
	market_identity_provider: Variant,
	initial_assignments_value: Variant = []
) -> bool:
	if _configured:
		return _fail("economic geography can only be configured once")
	if (
		territory_provider == null
		or not territory_provider is VNextTerritoryUnitCatalog
		or not (territory_provider as VNextTerritoryUnitCatalog).is_sealed()
	):
		return _fail("sealed TerritoryUnitCatalog provider is required")
	if not _is_supported_market_provider(market_identity_provider):
		return _fail("configured Market identity provider is required")
	if typeof(initial_assignments_value) != TYPE_ARRAY:
		return _fail("initial assignments must be an array")

	var territory_catalog: VNextTerritoryUnitCatalog = territory_provider
	var territory_binding: Dictionary = territory_catalog.binding()
	var market_binding: Dictionary = _binding_for_market_provider(market_identity_provider)
	if territory_binding.is_empty() or market_binding.is_empty():
		return _fail("reference provider binding is unavailable")

	var candidate_assignments: Dictionary = {}
	var seen_territories: Dictionary = {}
	for assignment_value: Variant in initial_assignments_value as Array:
		if not CANDIDATE.is_assignment_record(assignment_value):
			return _fail("malformed initial assignment")
		var assignment: Dictionary = assignment_value as Dictionary
		var territory_unit_id: String = str(assignment.get("territory_unit_id", ""))
		if seen_territories.has(territory_unit_id):
			return _fail("duplicate initial territory assignment")
		if not _valid_territory_reference_for(territory_catalog, territory_unit_id):
			return _fail("invalid or unknown initial territory reference")
		if assignment.get("assignment_state") == ASSIGNED:
			var market_id: String = str(assignment.get("market_id", ""))
			if not _valid_market_reference_for(market_identity_provider, market_id):
				return _fail("invalid or unknown initial Market reference")
			candidate_assignments[territory_unit_id] = market_id
		seen_territories[territory_unit_id] = true

	_territory_catalog = territory_catalog
	_market_provider = market_identity_provider
	_territory_catalog_binding = territory_binding.duplicate(true)
	_market_identity_binding = market_binding.duplicate(true)
	_assigned_market_by_territory = candidate_assignments.duplicate(true)
	_revision = 0
	_state_fingerprint = _fingerprint_for_assignments(_all_assignments_for(candidate_assignments))
	if _state_fingerprint.is_empty():
		_clear()
		return _fail("economic geography fingerprint could not be created")
	_configured = true
	_errors.clear()
	return true


func is_configured() -> bool:
	return _configured


func revision() -> int:
	return _revision if _configured else -1


func state_fingerprint() -> String:
	return _state_fingerprint if _configured else ""


func territory_catalog_binding() -> Dictionary:
	return _territory_catalog_binding.duplicate(true) if _configured else {}


func market_identity_binding() -> Dictionary:
	return _market_identity_binding.duplicate(true) if _configured else {}


func market_for_territory(territory_unit_id_value: Variant) -> Dictionary:
	if not _configured or typeof(territory_unit_id_value) != TYPE_STRING:
		return {}
	var territory_unit_id: String = territory_unit_id_value as String
	if not _valid_territory_reference(territory_unit_id):
		return {}
	return _assignment_record(territory_unit_id, _assigned_market_by_territory)


func territories_for_market(market_id_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not _configured or typeof(market_id_value) != TYPE_STRING:
		return result
	var market_id: String = market_id_value as String
	if not _valid_market_reference(market_id):
		return result
	for territory_unit_id: String in _territory_catalog.unit_ids():
		if str(_assigned_market_by_territory.get(territory_unit_id, "")) == market_id:
			result.append(territory_unit_id)
	return result


func all_assignments() -> Array[Dictionary]:
	return _all_assignments_for(_assigned_market_by_territory) if _configured else []


## Completeness is an explicit caller-selected policy, not a permanent invariant.
func validates_assignment_coverage(require_all_assigned: bool = false) -> bool:
	if not _configured:
		return false
	return (
		not require_all_assigned
		or _assigned_market_by_territory.size() == _territory_catalog.unit_count()
	)


func prepare_remap(
	territory_unit_id_value: Variant,
	target_market_id_value: Variant,
	expected_revision_value: Variant
) -> VNextEconomicGeographyCandidate:
	if typeof(target_market_id_value) != TYPE_STRING:
		return null
	var target_market_id: String = target_market_id_value as String
	if not _valid_market_reference(target_market_id):
		return null
	return _prepare_candidate(
		territory_unit_id_value,
		{
			"territory_unit_id": territory_unit_id_value,
			"assignment_state": ASSIGNED,
			"market_id": target_market_id,
		},
		expected_revision_value
	)


func prepare_unassign(
	territory_unit_id_value: Variant, expected_revision_value: Variant
) -> VNextEconomicGeographyCandidate:
	return _prepare_candidate(
		territory_unit_id_value,
		{
			"territory_unit_id": territory_unit_id_value,
			"assignment_state": UNASSIGNED,
		},
		expected_revision_value
	)


func adopt_candidate(candidate_value: Variant) -> bool:
	if not _configured or not candidate_value is VNextEconomicGeographyCandidate:
		return false
	var candidate: VNextEconomicGeographyCandidate = candidate_value
	if not _validate_candidate(candidate):
		return false
	var territory_unit_id: String = candidate.territory_unit_id()
	var target: Dictionary = candidate.target_assignment()
	if target.get("assignment_state") == ASSIGNED:
		_assigned_market_by_territory[territory_unit_id] = str(target.get("market_id", ""))
	else:
		_assigned_market_by_territory.erase(territory_unit_id)
	_revision += 1
	_state_fingerprint = _fingerprint_for_assignments(all_assignments())
	return true


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"revision": _revision,
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"market_identity_binding": _market_identity_binding.duplicate(true),
		"assignments": all_assignments(),
		"state_fingerprint": _state_fingerprint,
	}


func restore(snapshot_value: Variant) -> bool:
	if not _configured:
		return false
	var parsed: Variant = snapshot_value
	if typeof(snapshot_value) == TYPE_STRING:
		var parser := JSON.new()
		if parser.parse(snapshot_value as String) != OK:
			return false
		parsed = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var source: Dictionary = (parsed as Dictionary).duplicate(true)
	if source.size() != 6 or source.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if not _is_valid_revision_value(source.get("revision")):
		return false
	if source.get("territory_catalog_binding") != _territory_catalog_binding:
		return false
	if source.get("market_identity_binding") != _market_identity_binding:
		return false
	if typeof(source.get("assignments")) != TYPE_ARRAY:
		return false
	if typeof(source.get("state_fingerprint")) != TYPE_STRING:
		return false

	var candidate_assignments: Dictionary = {}
	var seen_territories: Dictionary = {}
	for assignment_value: Variant in source.get("assignments") as Array:
		if not CANDIDATE.is_assignment_record(assignment_value):
			return false
		var assignment: Dictionary = assignment_value as Dictionary
		var territory_unit_id: String = str(assignment.get("territory_unit_id", ""))
		if seen_territories.has(territory_unit_id):
			return false
		if not _valid_territory_reference(territory_unit_id):
			return false
		if assignment.get("assignment_state") == ASSIGNED:
			var market_id: String = str(assignment.get("market_id", ""))
			if not _valid_market_reference(market_id):
				return false
			candidate_assignments[territory_unit_id] = market_id
		seen_territories[territory_unit_id] = true
	if seen_territories.size() != _territory_catalog.unit_count():
		return false
	for territory_unit_id: String in _territory_catalog.unit_ids():
		if not seen_territories.has(territory_unit_id):
			return false

	var candidate_records: Array[Dictionary] = _all_assignments_for(candidate_assignments)
	var candidate_fingerprint: String = _fingerprint_for_assignments(candidate_records)
	if candidate_fingerprint != source.get("state_fingerprint"):
		return false

	_assigned_market_by_territory = candidate_assignments.duplicate(true)
	_revision = int(source.get("revision"))
	_state_fingerprint = candidate_fingerprint
	return true


func errors() -> Array[String]:
	return _errors.duplicate()


func _prepare_candidate(
	territory_unit_id_value: Variant,
	target_assignment: Dictionary,
	expected_revision_value: Variant
) -> VNextEconomicGeographyCandidate:
	if (
		not _configured
		or typeof(territory_unit_id_value) != TYPE_STRING
		or typeof(expected_revision_value) != TYPE_INT
	):
		return null
	var territory_unit_id: String = territory_unit_id_value as String
	var expected_revision: int = expected_revision_value as int
	if expected_revision != _revision or not _valid_territory_reference(territory_unit_id):
		return null
	var before: Dictionary = market_for_territory(territory_unit_id)
	if before == target_assignment:
		return null
	var candidate := VNextEconomicGeographyCandidate.new()
	if not candidate.configure(
		expected_revision,
		before,
		target_assignment,
		_territory_catalog_binding,
		_market_identity_binding
	):
		return null
	return candidate


func _validate_candidate(candidate: VNextEconomicGeographyCandidate) -> bool:
	if candidate == null or not candidate.is_well_formed():
		return false
	if candidate.expected_revision() != _revision:
		return false
	if candidate.territory_catalog_binding() != _territory_catalog_binding:
		return false
	if candidate.market_identity_binding() != _market_identity_binding:
		return false
	var territory_unit_id: String = candidate.territory_unit_id()
	if not _valid_territory_reference(territory_unit_id):
		return false
	if candidate.before_assignment() != market_for_territory(territory_unit_id):
		return false
	var target: Dictionary = candidate.target_assignment()
	if target.get("assignment_state") == ASSIGNED:
		return _valid_market_reference(str(target.get("market_id", "")))
	return target.get("assignment_state") == UNASSIGNED


func _assignment_record(territory_unit_id: String, assignments: Dictionary) -> Dictionary:
	if assignments.has(territory_unit_id):
		return {
			"territory_unit_id": territory_unit_id,
			"assignment_state": ASSIGNED,
			"market_id": str(assignments.get(territory_unit_id, "")),
		}
	return {
		"territory_unit_id": territory_unit_id,
		"assignment_state": UNASSIGNED,
	}


func _all_assignments_for(assignments: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if _territory_catalog == null:
		return records
	for territory_unit_id: String in _territory_catalog.unit_ids():
		records.append(_assignment_record(territory_unit_id, assignments))
	return records


func _fingerprint_for_assignments(assignments: Array[Dictionary]) -> String:
	var payload: Dictionary = {
		"fingerprint_schema_id": FINGERPRINT_SCHEMA_ID,
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"market_identity_binding": _market_identity_binding.duplicate(true),
		"assignments": assignments.duplicate(true),
	}
	return JSON.stringify(_canonical_copy(payload), "", false).sha256_text()


func _valid_territory_reference(territory_unit_id: String) -> bool:
	return _valid_territory_reference_for(_territory_catalog, territory_unit_id)


static func _valid_territory_reference_for(
	catalog: VNextTerritoryUnitCatalog, territory_unit_id: String
) -> bool:
	return (
		catalog != null
		and TERRITORY_UNIT.is_valid_territory_unit_id(territory_unit_id)
		and catalog.has_unit(territory_unit_id)
	)


func _valid_market_reference(market_id: String) -> bool:
	return _valid_market_reference_for(_market_provider, market_id)


static func _valid_market_reference_for(provider: Variant, market_id: String) -> bool:
	return _is_well_formed_market_id(market_id) and provider != null and provider.has_market(market_id)


static func _is_well_formed_market_id(market_id: String) -> bool:
	if market_id != market_id.strip_edges():
		return false
	var parts: PackedStringArray = market_id.split(":")
	if parts.size() != 3 or parts[0] != "market":
		return false
	for part_index: int in [1, 2]:
		var part: String = parts[part_index]
		if part.is_empty():
			return false
		for character_index: int in part.length():
			if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(part.substr(character_index, 1)):
				return false
	return true


static func _is_supported_market_provider(provider: Variant) -> bool:
	if provider is FormalWorldMarketRegistry:
		return (provider as FormalWorldMarketRegistry).is_configured()
	if provider is FormalWorldMarketView:
		return (provider as FormalWorldMarketView).is_configured()
	return false


static func _is_valid_revision_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0
	if typeof(value) == TYPE_FLOAT:
		var number: float = value as float
		return is_finite(number) and number >= 0.0 and number == floorf(number)
	return false


static func _binding_for_market_provider(provider: Variant) -> Dictionary:
	if not _is_supported_market_provider(provider):
		return {}
	return {
		"identity_revision": str(provider.revision()),
		"identity_fingerprint": str(provider.mapping_fingerprint()),
	}


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


func _clear() -> void:
	_territory_catalog = null
	_market_provider = null
	_territory_catalog_binding.clear()
	_market_identity_binding.clear()
	_assigned_market_by_territory.clear()
	_revision = 0
	_state_fingerprint = ""
	_configured = false


func _fail(message: String) -> bool:
	_errors.append(message)
	return false
