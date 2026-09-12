class_name VNextPopulationAuthority
extends RefCounted
## Sole Current World owner of mutable, territory-keyed population totals.
##
## Country and polity totals are projections over caller-supplied territory
## sets. Controller identity is deliberately absent from this authority.

const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")
const POPULATION_STATE = preload(
	"res://scripts/vnext/population/population_state.gd"
)
const POPULATION_CANDIDATE = preload(
	"res://scripts/vnext/population/population_candidate.gd"
)
const CONSERVATION_VALIDATOR = preload(
	"res://scripts/vnext/population/population_conservation_validator.gd"
)

const SNAPSHOT_SCHEMA_ID: String = "vnext_population_authority_v1"
const FINGERPRINT_SCHEMA_ID: String = "vnext_population_authority_fingerprint_v1"
const _SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"revision",
	"territory_catalog_binding",
	"records",
	"state_fingerprint",
]
const _RECORD_FIELDS: Array[String] = ["territory_unit_id", "total_population"]

var _territory_catalog: VNextTerritoryUnitCatalog = null
var _states_by_id: Dictionary = {}
var _revision: int = 0
var _last_error: String = ""


static func create(territory_catalog_value: Variant) -> VNextPopulationAuthority:
	var authority := VNextPopulationAuthority.new()
	return authority if authority.configure_territory_catalog(territory_catalog_value) else null


func configure_territory_catalog(territory_catalog_value: Variant) -> bool:
	if _territory_catalog != null or not territory_catalog_value is VNextTerritoryUnitCatalog:
		return _fail("a sealed Territory Unit Catalog is required")
	var candidate_catalog: VNextTerritoryUnitCatalog = (
		territory_catalog_value as VNextTerritoryUnitCatalog
	)
	if candidate_catalog == null or not candidate_catalog.is_sealed():
		return _fail("a sealed Territory Unit Catalog is required")
	_territory_catalog = candidate_catalog
	_last_error = ""
	return true


func is_configured() -> bool:
	return _territory_catalog != null and _territory_catalog.is_sealed()


func revision() -> int:
	return _revision


func last_error() -> String:
	return _last_error


func territory_catalog_binding() -> Dictionary:
	return _territory_catalog.binding() if is_configured() else {}


## Territories may remain explicitly uninitialized. Initialization is unique;
## replacement is only available through a validated candidate/restore path.
func initialize_population(
	territory_unit_id_value: Variant, total_population_value: Variant
) -> bool:
	if _revision >= POPULATION_STATE.MAX_JSON_SAFE_INTEGER:
		return _fail("population revision cannot advance beyond JSON-safe bounds")
	if not _is_known_territory_value(territory_unit_id_value):
		return _fail("territory reference is malformed, wrong-kind, unknown, or unbound")
	var territory_unit_id: String = territory_unit_id_value as String
	if _states_by_id.has(territory_unit_id):
		return _fail("duplicate population initialization")
	if not POPULATION_STATE.is_valid_population_value(total_population_value):
		return _fail("population must be a non-negative JSON-safe integer")

	var candidate_states: Dictionary = _copy_states(_states_by_id)
	var candidate_state := VNextPopulationState.new()
	if not candidate_state.configure(territory_unit_id, total_population_value):
		return _fail("population state is invalid")
	candidate_states[territory_unit_id] = candidate_state
	if not _validate_state_map(candidate_states):
		return _fail("population state would exceed deterministic numeric bounds")
	_states_by_id = candidate_states
	_revision += 1
	_last_error = ""
	return true


func has_population(territory_unit_id: String) -> bool:
	return _is_known_territory_value(territory_unit_id) and _states_by_id.has(
		territory_unit_id
	)


func population_for_territory(territory_unit_id: String) -> Dictionary:
	if not has_population(territory_unit_id):
		_fail("territory population is unavailable")
		return {}
	_last_error = ""
	var state: VNextPopulationState = _states_by_id[territory_unit_id] as VNextPopulationState
	return state.to_detached_dict()


func population_states() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for territory_unit_id: String in _sorted_state_ids(_states_by_id):
		var state: VNextPopulationState = (
			_states_by_id[territory_unit_id] as VNextPopulationState
		)
		output.append(state.to_detached_dict())
	return output


## Duplicate, malformed, unknown, and uninitialized inputs all fail closed.
func aggregate_population(territory_unit_ids_value: Variant) -> Dictionary:
	if not is_configured() or typeof(territory_unit_ids_value) != TYPE_ARRAY:
		return _aggregate_failure("territory IDs must be an array and catalog-bound")
	var seen: Dictionary = {}
	var ordered_ids: Array[String] = []
	var total: int = 0
	for raw_id: Variant in territory_unit_ids_value as Array:
		if not _is_known_territory_value(raw_id):
			return _aggregate_failure("aggregate contains an invalid or unknown territory")
		var territory_unit_id: String = raw_id as String
		if seen.has(territory_unit_id):
			return _aggregate_failure("aggregate contains a duplicate territory")
		if not _states_by_id.has(territory_unit_id):
			return _aggregate_failure("aggregate contains an uninitialized territory")
		var state: VNextPopulationState = (
			_states_by_id[territory_unit_id] as VNextPopulationState
		)
		var value: int = state.total_population()
		if value > POPULATION_STATE.MAX_JSON_SAFE_INTEGER - total:
			return _aggregate_failure("aggregate exceeds deterministic numeric bounds")
		total += value
		seen[territory_unit_id] = true
		ordered_ids.append(territory_unit_id)
	ordered_ids.sort()
	_last_error = ""
	return {
		"success": true,
		"territory_unit_ids": ordered_ids,
		"total_population": total,
	}


func total_population() -> int:
	return CONSERVATION_VALIDATOR.total_for_states(_states_by_id) if is_configured() else -1


func fingerprint() -> String:
	return _fingerprint_for_records(population_states()) if is_configured() else ""


func prepare_transfer(
	source_territory_unit_id_value: Variant,
	destination_territory_unit_id_value: Variant,
	amount_value: Variant,
	expected_revision_value: Variant
) -> VNextPopulationCandidate:
	if not is_configured():
		_fail("Territory Unit Catalog provider is missing")
		return null
	if (
		typeof(expected_revision_value) != TYPE_INT
		or int(expected_revision_value) != _revision
	):
		_fail("expected population revision is stale or malformed")
		return null
	if _revision >= POPULATION_STATE.MAX_JSON_SAFE_INTEGER:
		_fail("population revision cannot advance beyond JSON-safe bounds")
		return null
	if (
		not _is_known_territory_value(source_territory_unit_id_value)
		or not _is_known_territory_value(destination_territory_unit_id_value)
	):
		_fail("transfer territory reference is invalid")
		return null
	var source_id: String = source_territory_unit_id_value as String
	var destination_id: String = destination_territory_unit_id_value as String
	if source_id == destination_id:
		_fail("transfer source and destination must differ")
		return null
	if not _states_by_id.has(source_id) or not _states_by_id.has(destination_id):
		_fail("transfer requires initialized source and destination")
		return null
	if typeof(amount_value) != TYPE_INT or int(amount_value) <= 0:
		_fail("transfer amount must be a positive integer")
		return null
	var amount: int = int(amount_value)
	var source_state: VNextPopulationState = _states_by_id[source_id] as VNextPopulationState
	var destination_state: VNextPopulationState = (
		_states_by_id[destination_id] as VNextPopulationState
	)
	if source_state.total_population() < amount:
		_fail("source population is insufficient")
		return null
	if destination_state.total_population() > POPULATION_STATE.MAX_JSON_SAFE_INTEGER - amount:
		_fail("destination population would overflow")
		return null

	var candidate_states: Dictionary = _copy_states(_states_by_id)
	candidate_states[source_id] = _make_state(
		source_id, source_state.total_population() - amount
	)
	candidate_states[destination_id] = _make_state(
		destination_id, destination_state.total_population() + amount
	)
	if (
		not _validate_state_map(candidate_states)
		or not CONSERVATION_VALIDATOR.conserves(_states_by_id, candidate_states)
	):
		_fail("transfer candidate violates population conservation")
		return null
	var records: Array[Dictionary] = _records_for_states(candidate_states)
	var candidate := VNextPopulationCandidate.new()
	if not candidate.configure(
		POPULATION_CANDIDATE.TRANSFER,
		_revision,
		_revision + 1,
		fingerprint(),
		territory_catalog_binding(),
		records,
		_fingerprint_for_records(records),
		source_id,
		destination_id,
		amount
	):
		_fail("transfer candidate could not be created")
		return null
	_last_error = ""
	return candidate


func validate_candidate(candidate_value: Variant) -> bool:
	if not is_configured() or not candidate_value is VNextPopulationCandidate:
		return _fail("population candidate is missing or malformed")
	var candidate: VNextPopulationCandidate = candidate_value as VNextPopulationCandidate
	if candidate == null or not candidate.is_configured():
		return _fail("population candidate is not configured")
	if (
		candidate.expected_revision() != _revision
		or candidate.expected_authority_fingerprint() != fingerprint()
		or not _territory_catalog.validates_binding(candidate.territory_catalog_binding())
	):
		return _fail("population candidate precondition mismatch")
	var candidate_states: Dictionary = _parse_records(candidate.records())
	if candidate_states.is_empty() and not candidate.records().is_empty():
		return _fail("population candidate records are invalid")
	if not _validate_state_map(candidate_states):
		return _fail("population candidate state is invalid")
	var records: Array[Dictionary] = _records_for_states(candidate_states)
	if candidate.state_fingerprint() != _fingerprint_for_records(records):
		return _fail("population candidate fingerprint is corrupted")

	if candidate.operation() == POPULATION_CANDIDATE.TRANSFER:
		if not _validate_transfer_semantics(candidate, candidate_states):
			return _fail("population transfer semantics are invalid")
	elif candidate.operation() == POPULATION_CANDIDATE.RESTORE:
		if not _is_valid_revision(candidate.target_revision()):
			return _fail("population restore revision is invalid")
	else:
		return _fail("population candidate operation is unsupported")
	_last_error = ""
	return true


func adopt_candidate(candidate_value: Variant) -> bool:
	if not validate_candidate(candidate_value):
		return false
	var candidate: VNextPopulationCandidate = candidate_value as VNextPopulationCandidate
	var candidate_states: Dictionary = _parse_records(candidate.records())
	_states_by_id = candidate_states
	_revision = candidate.target_revision()
	_last_error = ""
	return true


func snapshot() -> Dictionary:
	if not is_configured():
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"revision": _revision,
		"territory_catalog_binding": territory_catalog_binding(),
		"records": population_states(),
		"state_fingerprint": fingerprint(),
	}


func prepare_restore(snapshot_value: Variant) -> VNextPopulationCandidate:
	if not is_configured() or typeof(snapshot_value) != TYPE_DICTIONARY:
		_fail("population snapshot or Territory Unit Catalog provider is missing")
		return null
	var candidate_snapshot: Dictionary = (snapshot_value as Dictionary).duplicate(true)
	if (
		not _has_exact_fields(candidate_snapshot, _SNAPSHOT_FIELDS)
		or candidate_snapshot.get("schema_id") != SNAPSHOT_SCHEMA_ID
		or not _is_valid_revision(candidate_snapshot.get("revision"))
		or not _territory_catalog.validates_binding(
			candidate_snapshot.get("territory_catalog_binding")
		)
		or typeof(candidate_snapshot.get("records")) != TYPE_ARRAY
		or not _is_valid_fingerprint(candidate_snapshot.get("state_fingerprint"))
	):
		_fail("population snapshot schema, revision, or catalog binding is invalid")
		return null
	var records: Array = candidate_snapshot.get("records") as Array
	var candidate_states: Dictionary = _parse_records(records)
	if candidate_states.is_empty() and not records.is_empty():
		_fail("population snapshot records are invalid")
		return null
	if not _validate_state_map(candidate_states):
		_fail("population snapshot state is invalid")
		return null
	var canonical_records: Array[Dictionary] = _records_for_states(candidate_states)
	var expected_fingerprint: String = _fingerprint_for_records(canonical_records)
	if candidate_snapshot.get("state_fingerprint") != expected_fingerprint:
		_fail("population snapshot fingerprint is corrupted")
		return null
	var candidate := VNextPopulationCandidate.new()
	if not candidate.configure(
		POPULATION_CANDIDATE.RESTORE,
		_revision,
		int(candidate_snapshot.get("revision")),
		fingerprint(),
		territory_catalog_binding(),
		canonical_records,
		expected_fingerprint
	):
		_fail("population restore candidate could not be created")
		return null
	_last_error = ""
	return candidate


func restore(snapshot_value: Variant) -> bool:
	var candidate: VNextPopulationCandidate = prepare_restore(snapshot_value)
	return candidate != null and adopt_candidate(candidate)


func _validate_transfer_semantics(
	candidate: VNextPopulationCandidate, candidate_states: Dictionary
) -> bool:
	if (
		candidate.target_revision() != _revision + 1
		or not POPULATION_STATE.is_valid_population_value(candidate.amount())
		or candidate.amount() <= 0
		or not _states_by_id.has(candidate.source_territory_unit_id())
		or not _states_by_id.has(candidate.destination_territory_unit_id())
		or candidate.source_territory_unit_id() == candidate.destination_territory_unit_id()
		or candidate_states.size() != _states_by_id.size()
		or not CONSERVATION_VALIDATOR.conserves(_states_by_id, candidate_states)
	):
		return false
	var source_before: VNextPopulationState = (
		_states_by_id[candidate.source_territory_unit_id()] as VNextPopulationState
	)
	var destination_before: VNextPopulationState = (
		_states_by_id[candidate.destination_territory_unit_id()] as VNextPopulationState
	)
	var source_after: VNextPopulationState = (
		candidate_states.get(candidate.source_territory_unit_id()) as VNextPopulationState
	)
	var destination_after: VNextPopulationState = (
		candidate_states.get(candidate.destination_territory_unit_id()) as VNextPopulationState
	)
	if source_after == null or destination_after == null:
		return false
	if (
		source_before.total_population() - candidate.amount()
		!= source_after.total_population()
		or destination_before.total_population() + candidate.amount()
		!= destination_after.total_population()
	):
		return false
	for territory_unit_id: String in _sorted_state_ids(_states_by_id):
		if not candidate_states.has(territory_unit_id):
			return false
		if (
			territory_unit_id != candidate.source_territory_unit_id()
			and territory_unit_id != candidate.destination_territory_unit_id()
		):
			var before: VNextPopulationState = (
				_states_by_id[territory_unit_id] as VNextPopulationState
			)
			var after: VNextPopulationState = (
				candidate_states[territory_unit_id] as VNextPopulationState
			)
			if before.total_population() != after.total_population():
				return false
	return true


func _parse_records(records_value: Array) -> Dictionary:
	var candidate_states: Dictionary = {}
	for raw_record: Variant in records_value:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return {}
		var record: Dictionary = raw_record as Dictionary
		if (
			not _has_exact_fields(record, _RECORD_FIELDS)
			or typeof(record.get("territory_unit_id")) != TYPE_STRING
			or not _is_known_territory_value(record.get("territory_unit_id"))
		):
			return {}
		var territory_unit_id: String = record.get("territory_unit_id") as String
		if candidate_states.has(territory_unit_id):
			return {}
		var normalized_population: int = _normalize_snapshot_integer(
			record.get("total_population")
		)
		if normalized_population < 0:
			return {}
		var state: VNextPopulationState = _make_state(
			territory_unit_id, normalized_population
		)
		if state == null:
			return {}
		candidate_states[territory_unit_id] = state
	return candidate_states


func _validate_state_map(candidate_states: Dictionary) -> bool:
	if not is_configured():
		return false
	for raw_id: Variant in candidate_states.keys():
		if typeof(raw_id) != TYPE_STRING or not _is_known_territory_value(raw_id):
			return false
		var state_value: Variant = candidate_states.get(raw_id)
		if not state_value is VNextPopulationState:
			return false
		var state: VNextPopulationState = state_value as VNextPopulationState
		if (
			state == null
			or not state.is_configured()
			or state.territory_unit_id() != str(raw_id)
			or not POPULATION_STATE.is_valid_population_value(state.total_population())
		):
			return false
	return CONSERVATION_VALIDATOR.total_for_states(candidate_states) >= 0


func _is_known_territory_value(candidate_value: Variant) -> bool:
	return (
		is_configured()
		and typeof(candidate_value) == TYPE_STRING
		and TERRITORY_UNIT.is_valid_territory_unit_id(candidate_value as String)
		and _territory_catalog.has_unit(candidate_value as String)
	)


func _fingerprint_for_records(records_value: Array) -> String:
	var payload: Dictionary = {
		"fingerprint_schema": FINGERPRINT_SCHEMA_ID,
		"territory_catalog_binding": territory_catalog_binding(),
		"records": records_value.duplicate(true),
	}
	return JSON.stringify(_canonical_copy(payload), "", false).sha256_text()


func _records_for_states(states_by_id: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for territory_unit_id: String in _sorted_state_ids(states_by_id):
		var state: VNextPopulationState = (
			states_by_id[territory_unit_id] as VNextPopulationState
		)
		output.append(state.to_detached_dict())
	return output


func _copy_states(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for territory_unit_id: String in _sorted_state_ids(source):
		var source_state: VNextPopulationState = source[territory_unit_id] as VNextPopulationState
		output[territory_unit_id] = source_state.copy_detached()
	return output


func _make_state(territory_unit_id: String, total_population_value: int) -> VNextPopulationState:
	var state := VNextPopulationState.new()
	return state if state.configure(territory_unit_id, total_population_value) else null


func _sorted_state_ids(source: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for raw_id: Variant in source.keys():
		if typeof(raw_id) == TYPE_STRING:
			output.append(raw_id as String)
	output.sort()
	return output


func _aggregate_failure(message: String) -> Dictionary:
	_fail(message)
	return {
		"success": false,
		"error": message,
		"territory_unit_ids": [],
		"total_population": 0,
	}


func _is_valid_revision(candidate_value: Variant) -> bool:
	return _normalize_snapshot_integer(candidate_value) >= 0


func _normalize_snapshot_integer(candidate_value: Variant) -> int:
	if typeof(candidate_value) == TYPE_INT:
		var integer_value: int = int(candidate_value)
		return (
			integer_value
			if integer_value >= 0
			and integer_value <= POPULATION_STATE.MAX_JSON_SAFE_INTEGER
			else -1
		)
	if typeof(candidate_value) == TYPE_FLOAT:
		var float_value: float = float(candidate_value)
		if (
			not is_finite(float_value)
			or float_value < 0.0
			or float_value > float(POPULATION_STATE.MAX_JSON_SAFE_INTEGER)
			or float_value != floor(float_value)
		):
			return -1
		return int(float_value)
	return -1


func _is_valid_fingerprint(candidate_value: Variant) -> bool:
	if typeof(candidate_value) != TYPE_STRING:
		return false
	var candidate: String = candidate_value as String
	if candidate.length() != 64:
		return false
	for character_index: int in candidate.length():
		if not "0123456789abcdef".contains(candidate.substr(character_index, 1)):
			return false
	return true


func _has_exact_fields(record: Dictionary, fields: Array[String]) -> bool:
	if record.size() != fields.size():
		return false
	for field: String in fields:
		if not record.has(field):
			return false
	return true


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


func _fail(message: String) -> bool:
	_last_error = message
	return false
