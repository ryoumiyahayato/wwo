class_name VNextTerritorialControlLedger
extends RefCounted
## Sole mutable owner of current-world controller assignments by territory unit.
##
## Territory identity/topology and runtime political identity remain external,
## immutable reference views. Every mutation is prepared as a detached complete
## candidate and revalidated immediately before one atomic adoption.

const SNAPSHOT_SCHEMA_ID: String = "vnext_territorial_control_ledger_v1"
const CANDIDATE_SCHEMA_ID: String = "vnext_territorial_control_candidate_v1"
const FINGERPRINT_SCHEMA_ID: String = "vnext_territorial_control_fingerprint_v1"
const POLITICAL_REFERENCE_SCHEMA_ID: String = (
	"vnext_territorial_control_political_reference_v1"
)
const CONTROLLED: String = "controlled"
const UNCONTROLLED: String = "uncontrolled"
const OPERATION_INITIALIZE: String = "initialize"
const OPERATION_CHANGE: String = "change"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

const ASSIGNMENT_FIELDS: Array[String] = [
	"territory_unit_id",
	"control_state",
	"controller_id",
]
const CANDIDATE_FIELDS: Array[String] = [
	"schema_id",
	"operation",
	"expected_revision",
	"base_fingerprint",
	"territory_catalog_binding",
	"political_entity_fingerprint",
	"assignments",
	"candidate_fingerprint",
]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"revision",
	"territory_catalog_binding",
	"political_entity_fingerprint",
	"assignments",
	"fingerprint",
]

var _configured: bool = false
var _territory_catalog: VNextTerritoryUnitCatalog = null
var _political_entity_view: RuntimePoliticalEntityView = null
var _territory_catalog_binding: Dictionary = {}
var _political_entity_fingerprint: String = ""
var _assignments_by_territory: Dictionary = {}
var _revision: int = 0
var _errors: Array[String] = []


static func create(
	territory_catalog_value: VNextTerritoryUnitCatalog,
	political_entity_view_value: RuntimePoliticalEntityView
) -> VNextTerritorialControlLedger:
	var ledger := VNextTerritorialControlLedger.new()
	if not ledger.configure_reference_views(
		territory_catalog_value, political_entity_view_value
	):
		return null
	return ledger


func configure_reference_views(
	territory_catalog_value: VNextTerritoryUnitCatalog,
	political_entity_view_value: RuntimePoliticalEntityView
) -> bool:
	_errors.clear()
	if _configured:
		return _fail("reference views can only be configured once")
	if territory_catalog_value == null or not territory_catalog_value.is_sealed():
		return _fail("a sealed territory catalog is required")
	if (
		political_entity_view_value == null
		or not political_entity_view_value.is_configured()
	):
		return _fail("a configured runtime political entity view is required")
	if not _valid_political_reference_view(political_entity_view_value):
		return _fail("runtime political entity view contains invalid identities")

	_territory_catalog = territory_catalog_value
	_political_entity_view = political_entity_view_value
	_territory_catalog_binding = territory_catalog_value.binding().duplicate(true)
	_political_entity_fingerprint = _fingerprint_for_political_reference(
		political_entity_view_value
	)
	_configured = true
	return true


func is_configured() -> bool:
	return _configured and _references_match()


func revision() -> int:
	return _revision


func assignment_count() -> int:
	return _assignments_by_territory.size() if is_configured() else 0


func has_control_record(territory_unit_id: String) -> bool:
	return (
		is_configured()
		and _is_known_territory(territory_unit_id)
		and _assignments_by_territory.has(territory_unit_id)
	)


## Returns a detached explicit control record. An empty result means unknown or
## not initialized; explicit uncontrolled state is a non-empty record with null
## controller_id and control_state == UNCONTROLLED.
func controller_for_territory(territory_unit_id: String) -> Dictionary:
	_errors.clear()
	if not _require_references():
		return {}
	if not _is_known_territory(territory_unit_id):
		_fail("unknown or invalid territory unit: %s" % territory_unit_id)
		return {}
	var record: Dictionary = _assignments_by_territory.get(
		territory_unit_id, {}
	) as Dictionary
	return record.duplicate(true)


func control_for_territory(territory_unit_id: String) -> Dictionary:
	return controller_for_territory(territory_unit_id)


func territories_controlled_by(controller_id: String) -> Array[String]:
	_errors.clear()
	var result: Array[String] = []
	if not _require_references():
		return result
	if not _is_known_controller(controller_id):
		_fail("unknown or invalid runtime political entity: %s" % controller_id)
		return result
	for territory_unit_id: String in _sorted_assignment_ids(
		_assignments_by_territory
	):
		var record: Dictionary = _assignments_by_territory[territory_unit_id] as Dictionary
		if (
			record.get("control_state") == CONTROLLED
			and record.get("controller_id") == controller_id
		):
			result.append(territory_unit_id)
	return result


func uncontrolled_territory_ids() -> Array[String]:
	var result: Array[String] = []
	if not is_configured():
		return result
	for territory_unit_id: String in _sorted_assignment_ids(
		_assignments_by_territory
	):
		var record: Dictionary = _assignments_by_territory[territory_unit_id] as Dictionary
		if record.get("control_state") == UNCONTROLLED:
			result.append(territory_unit_id)
	return result


func assignments() -> Array[Dictionary]:
	return _assignment_array(_assignments_by_territory) if is_configured() else []


static func controlled_assignment(
	territory_unit_id: String, controller_id: String
) -> Dictionary:
	return {
		"territory_unit_id": territory_unit_id,
		"control_state": CONTROLLED,
		"controller_id": controller_id,
	}


static func uncontrolled_assignment(territory_unit_id: String) -> Dictionary:
	return {
		"territory_unit_id": territory_unit_id,
		"control_state": UNCONTROLLED,
		"controller_id": null,
	}


func prepare_initial_assignments(
	assignments_value: Variant, expected_revision_value: Variant
) -> Dictionary:
	_errors.clear()
	if not _require_references():
		return {}
	var expected_revision: int = _normalize_nonnegative_int(expected_revision_value)
	if expected_revision < 0 or expected_revision != _revision:
		_fail("stale or invalid expected revision")
		return {}
	if not _assignments_by_territory.is_empty():
		_fail("initial assignments require an empty ledger")
		return {}
	var decoded: Dictionary = _decode_assignment_array(assignments_value)
	if decoded.is_empty():
		if _errors.is_empty():
			_fail("initial assignments cannot be empty")
		return {}
	return _build_candidate(OPERATION_INITIALIZE, expected_revision, decoded)


func initialize_assignments(
	assignments_value: Variant, expected_revision_value: Variant
) -> bool:
	var candidate: Dictionary = prepare_initial_assignments(
		assignments_value, expected_revision_value
	)
	return not candidate.is_empty() and adopt_candidate(candidate)


func assign_initial_controller(
	territory_unit_id: String,
	controller_id: String,
	expected_revision_value: Variant = 0
) -> bool:
	return initialize_assignments(
		[controlled_assignment(territory_unit_id, controller_id)],
		expected_revision_value
	)


func assign_initial_uncontrolled(
	territory_unit_id: String, expected_revision_value: Variant = 0
) -> bool:
	return initialize_assignments(
		[uncontrolled_assignment(territory_unit_id)], expected_revision_value
	)


func prepare_control_change(
	territory_unit_id_value: Variant,
	control_state_value: Variant,
	controller_id_value: Variant,
	expected_revision_value: Variant
) -> Dictionary:
	_errors.clear()
	if not _require_references():
		return {}
	var expected_revision: int = _normalize_nonnegative_int(expected_revision_value)
	if expected_revision < 0 or expected_revision != _revision:
		_fail("stale or invalid expected revision")
		return {}
	var raw_record: Dictionary = {
		"territory_unit_id": territory_unit_id_value,
		"control_state": control_state_value,
		"controller_id": controller_id_value,
	}
	var decoded_record: Dictionary = _decode_assignment(raw_record)
	if decoded_record.is_empty():
		return {}
	var territory_unit_id: String = str(decoded_record.get("territory_unit_id"))
	if (
		_assignments_by_territory.has(territory_unit_id)
		and _assignments_by_territory[territory_unit_id] == decoded_record
	):
		_fail("control change must change authoritative state")
		return {}
	var candidate_state: Dictionary = _assignments_by_territory.duplicate(true)
	candidate_state[territory_unit_id] = decoded_record
	return _build_candidate(OPERATION_CHANGE, expected_revision, candidate_state)


func validate_candidate(candidate_value: Variant) -> bool:
	_errors.clear()
	if not _require_references():
		return false
	return not _decode_candidate(candidate_value).is_empty()


func adopt_candidate(candidate_value: Variant) -> bool:
	_errors.clear()
	if not _require_references():
		return false
	var decoded: Dictionary = _decode_candidate(candidate_value)
	if decoded.is_empty():
		return false
	_assignments_by_territory = (
		decoded.get("assignments_by_territory", {}) as Dictionary
	).duplicate(true)
	_revision += 1
	return true


func authoritative_fingerprint() -> String:
	if not is_configured():
		return ""
	return _fingerprint_for_state(_revision, _assignments_by_territory)


func snapshot() -> Dictionary:
	if not is_configured():
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"revision": _revision,
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"political_entity_fingerprint": _political_entity_fingerprint,
		"assignments": _assignment_array(_assignments_by_territory),
		"fingerprint": authoritative_fingerprint(),
	}


## Fully decodes and validates a detached restore candidate before swapping any
## authoritative field. Rejection cannot require rollback because live state is
## never touched until this final assignment block.
func restore(snapshot_value: Variant) -> bool:
	_errors.clear()
	if not _require_references():
		return false
	var decoded: Dictionary = _decode_snapshot(snapshot_value)
	if decoded.is_empty():
		return false
	_assignments_by_territory = (
		decoded.get("assignments_by_territory", {}) as Dictionary
	).duplicate(true)
	_revision = int(decoded.get("revision", 0))
	return true


func restore_snapshot(snapshot_value: Variant) -> bool:
	return restore(snapshot_value)


func errors() -> Array[String]:
	var copied: Array[String] = []
	for message: String in _errors:
		copied.append(message)
	return copied


func _build_candidate(
	operation: String, expected_revision: int, candidate_state: Dictionary
) -> Dictionary:
	var candidate: Dictionary = {
		"schema_id": CANDIDATE_SCHEMA_ID,
		"operation": operation,
		"expected_revision": expected_revision,
		"base_fingerprint": authoritative_fingerprint(),
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"political_entity_fingerprint": _political_entity_fingerprint,
		"assignments": _assignment_array(candidate_state),
	}
	candidate["candidate_fingerprint"] = _fingerprint_for_candidate(candidate)
	return candidate.duplicate(true)


func _decode_candidate(candidate_value: Variant) -> Dictionary:
	if typeof(candidate_value) != TYPE_DICTIONARY:
		_fail("candidate must be a dictionary")
		return {}
	var candidate: Dictionary = (candidate_value as Dictionary).duplicate(true)
	if not _has_exact_fields(candidate, CANDIDATE_FIELDS):
		_fail("candidate fields are malformed")
		return {}
	if candidate.get("schema_id") != CANDIDATE_SCHEMA_ID:
		_fail("candidate schema is unsupported")
		return {}
	var operation_value: Variant = candidate.get("operation")
	if (
		typeof(operation_value) != TYPE_STRING
		or operation_value not in [OPERATION_INITIALIZE, OPERATION_CHANGE]
	):
		_fail("candidate operation is invalid")
		return {}
	var expected_revision: int = _normalize_nonnegative_int(
		candidate.get("expected_revision")
	)
	if expected_revision < 0 or expected_revision != _revision:
		_fail("candidate expected revision is stale")
		return {}
	if (
		typeof(candidate.get("base_fingerprint")) != TYPE_STRING
		or candidate.get("base_fingerprint") != authoritative_fingerprint()
	):
		_fail("candidate base fingerprint is stale")
		return {}
	if (
		typeof(candidate.get("territory_catalog_binding")) != TYPE_DICTIONARY
		or candidate.get("territory_catalog_binding") != _territory_catalog_binding
	):
		_fail("candidate territory catalog binding does not match")
		return {}
	if (
		typeof(candidate.get("political_entity_fingerprint")) != TYPE_STRING
		or candidate.get("political_entity_fingerprint")
		!= _political_entity_fingerprint
	):
		_fail("candidate political entity binding does not match")
		return {}
	if typeof(candidate.get("candidate_fingerprint")) != TYPE_STRING:
		_fail("candidate fingerprint is malformed")
		return {}
	var fingerprint_payload: Dictionary = candidate.duplicate(true)
	fingerprint_payload.erase("candidate_fingerprint")
	if (
		candidate.get("candidate_fingerprint")
		!= _fingerprint_for_candidate(fingerprint_payload)
	):
		_fail("candidate fingerprint does not match")
		return {}
	var decoded_state: Dictionary = _decode_assignment_array(
		candidate.get("assignments")
	)
	if decoded_state.is_empty():
		if _errors.is_empty():
			_fail("candidate assignments cannot be empty")
		return {}

	var operation: String = operation_value as String
	if operation == OPERATION_INITIALIZE:
		if not _assignments_by_territory.is_empty():
			_fail("initialize candidate requires an empty ledger")
			return {}
	elif not _is_single_change(_assignments_by_territory, decoded_state):
		_fail("change candidate must replace or add exactly one assignment")
		return {}
	return {
		"operation": operation,
		"assignments_by_territory": decoded_state,
	}


func _decode_snapshot(snapshot_value: Variant) -> Dictionary:
	if typeof(snapshot_value) != TYPE_DICTIONARY:
		_fail("snapshot must be a dictionary")
		return {}
	var candidate: Dictionary = (snapshot_value as Dictionary).duplicate(true)
	if not _has_exact_fields(candidate, SNAPSHOT_FIELDS):
		_fail("snapshot fields are malformed")
		return {}
	if candidate.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		_fail("snapshot schema is unsupported")
		return {}
	var candidate_revision: int = _normalize_nonnegative_int(candidate.get("revision"))
	if candidate_revision < 0:
		_fail("snapshot revision is invalid")
		return {}
	if (
		typeof(candidate.get("territory_catalog_binding")) != TYPE_DICTIONARY
		or candidate.get("territory_catalog_binding") != _territory_catalog_binding
	):
		_fail("snapshot territory catalog binding does not match")
		return {}
	if (
		typeof(candidate.get("political_entity_fingerprint")) != TYPE_STRING
		or candidate.get("political_entity_fingerprint")
		!= _political_entity_fingerprint
	):
		_fail("snapshot political entity binding does not match")
		return {}
	var candidate_state: Dictionary = _decode_assignment_array(
		candidate.get("assignments"), true
	)
	if not _errors.is_empty():
		return {}
	if candidate_revision == 0 and not candidate_state.is_empty():
		_fail("revision zero cannot contain adopted assignments")
		return {}
	if typeof(candidate.get("fingerprint")) != TYPE_STRING:
		_fail("snapshot fingerprint is malformed")
		return {}
	if (
		candidate.get("fingerprint")
		!= _fingerprint_for_state(candidate_revision, candidate_state)
	):
		_fail("snapshot fingerprint does not match")
		return {}
	return {
		"revision": candidate_revision,
		"assignments_by_territory": candidate_state,
	}


func _decode_assignment_array(
	assignments_value: Variant, allow_empty: bool = false
) -> Dictionary:
	if typeof(assignments_value) != TYPE_ARRAY:
		_fail("assignments must be an array")
		return {}
	var decoded: Dictionary = {}
	for raw_assignment: Variant in assignments_value as Array:
		if typeof(raw_assignment) != TYPE_DICTIONARY:
			_fail("assignment must be a dictionary")
			return {}
		var record: Dictionary = _decode_assignment(raw_assignment as Dictionary)
		if record.is_empty():
			return {}
		var territory_unit_id: String = str(record.get("territory_unit_id"))
		if decoded.has(territory_unit_id):
			_fail("duplicate territory assignment: %s" % territory_unit_id)
			return {}
		decoded[territory_unit_id] = record
	if decoded.is_empty() and not allow_empty:
		_fail("assignments cannot be empty")
	return decoded


func _decode_assignment(raw_assignment: Dictionary) -> Dictionary:
	if not _has_exact_fields(raw_assignment, ASSIGNMENT_FIELDS):
		_fail("assignment fields are malformed")
		return {}
	if (
		typeof(raw_assignment.get("territory_unit_id")) != TYPE_STRING
		or typeof(raw_assignment.get("control_state")) != TYPE_STRING
	):
		_fail("assignment identity or state has the wrong type")
		return {}
	var territory_unit_id: String = raw_assignment.get("territory_unit_id") as String
	if not _is_known_territory(territory_unit_id):
		_fail("unknown or invalid territory unit: %s" % territory_unit_id)
		return {}
	var control_state: String = raw_assignment.get("control_state") as String
	var controller_value: Variant = raw_assignment.get("controller_id")
	if control_state == CONTROLLED:
		if (
			typeof(controller_value) != TYPE_STRING
			or not _is_known_controller(controller_value as String)
		):
			_fail("controlled assignment requires a known runtime political entity")
			return {}
		return controlled_assignment(territory_unit_id, controller_value as String)
	if control_state == UNCONTROLLED:
		if typeof(controller_value) != TYPE_NIL:
			_fail("uncontrolled assignment requires an explicit null controller")
			return {}
		return uncontrolled_assignment(territory_unit_id)
	_fail("unknown control state: %s" % control_state)
	return {}


func _is_single_change(before: Dictionary, after: Dictionary) -> bool:
	if after.size() < before.size() or after.size() > before.size() + 1:
		return false
	var changed_count: int = 0
	for territory_unit_id: String in _sorted_assignment_ids(before):
		if not after.has(territory_unit_id):
			return false
		if before[territory_unit_id] != after[territory_unit_id]:
			changed_count += 1
	for territory_unit_id: String in _sorted_assignment_ids(after):
		if not before.has(territory_unit_id):
			changed_count += 1
	return changed_count == 1


func _fingerprint_for_state(revision_value: int, state: Dictionary) -> String:
	var payload: Dictionary = {
		"fingerprint_schema": FINGERPRINT_SCHEMA_ID,
		"revision": revision_value,
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"political_entity_fingerprint": _political_entity_fingerprint,
		"assignments": _assignment_array(state),
	}
	return JSON.stringify(_canonical_copy(payload), "", false).sha256_text()


func _fingerprint_for_candidate(candidate_without_fingerprint: Dictionary) -> String:
	return JSON.stringify(
		_canonical_copy(candidate_without_fingerprint), "", false
	).sha256_text()


func _fingerprint_for_political_reference(
	view: RuntimePoliticalEntityView
) -> String:
	var entities: Array[Dictionary] = []
	for runtime_id: String in view.entity_ids():
		entities.append(view.entity(runtime_id))
	var payload: Dictionary = {
		"schema_id": POLITICAL_REFERENCE_SCHEMA_ID,
		"entities": entities,
	}
	return JSON.stringify(_canonical_copy(payload), "", false).sha256_text()


func _assignment_array(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for territory_unit_id: String in _sorted_assignment_ids(state):
		var record: Dictionary = state[territory_unit_id] as Dictionary
		result.append(record.duplicate(true))
	return result


func _references_match() -> bool:
	return (
		_configured
		and _territory_catalog != null
		and _territory_catalog.is_sealed()
		and _territory_catalog.binding() == _territory_catalog_binding
		and _political_entity_view != null
		and _political_entity_view.is_configured()
		and _valid_political_reference_view(_political_entity_view)
		and _fingerprint_for_political_reference(_political_entity_view)
		== _political_entity_fingerprint
	)


func _require_references() -> bool:
	if _references_match():
		return true
	return _fail("required territory or political reference view is unavailable")


func _valid_political_reference_view(view: RuntimePoliticalEntityView) -> bool:
	for runtime_id: String in view.entity_ids():
		var entity: Dictionary = view.entity(runtime_id)
		if (
			not VNextStableId.is_valid(runtime_id)
			or VNextStableId.kind_of(runtime_id) != "state"
			or entity.get("runtime_id") != runtime_id
			or entity.get("lifecycle_status") != "active"
		):
			return false
	return true


func _is_known_territory(territory_unit_id: String) -> bool:
	return (
		VNextStableId.is_valid(territory_unit_id)
		and VNextStableId.kind_of(territory_unit_id) == "territory_unit"
		and _territory_catalog != null
		and _territory_catalog.has_unit(territory_unit_id)
	)


func _is_known_controller(controller_id: String) -> bool:
	return (
		VNextStableId.is_valid(controller_id)
		and VNextStableId.kind_of(controller_id) == "state"
		and _political_entity_view != null
		and _political_entity_view.has_entity(controller_id)
	)


static func _sorted_assignment_ids(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in state.keys():
		if typeof(raw_id) != TYPE_STRING:
			return []
		result.append(raw_id as String)
	result.sort()
	return result


static func _has_exact_fields(value: Dictionary, expected_fields: Array[String]) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field_name: String in expected_fields:
		if not value.has(field_name):
			return false
	return true


static func _normalize_nonnegative_int(candidate_value: Variant) -> int:
	if typeof(candidate_value) == TYPE_INT:
		var integer_value: int = int(candidate_value)
		return (
			integer_value
			if integer_value >= 0 and integer_value <= MAX_JSON_SAFE_INTEGER
			else -1
		)
	if typeof(candidate_value) == TYPE_FLOAT:
		var float_value: float = float(candidate_value)
		if (
			not is_finite(float_value)
			or float_value < 0.0
			or float_value > float(MAX_JSON_SAFE_INTEGER)
			or float_value != floor(float_value)
		):
			return -1
		return int(float_value)
	return -1


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
	_errors.append(message)
	return false
